# =============================================================================
# NA POINT CLOUD VIEWER - LAS IMPORT - JOB
# =============================================================================
#
# FILE       : Na__PointCloudViewer__LasImport__Job__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__LasImport::Na__LasImportJob
# PURPOSE    : Async job that runs the native LAS import. The C++ worker
#              thread does all the reading; each Ruby tick (every 0.1 s) only
#              polls its atomic progress counters, so SketchUp and the dialog
#              stay responsive and Cancel takes effect within one chunk.
#
# RESULT: an engine-only cloud (no Ruby points): coordinates in the source
#   unit relative to a local origin; local_to_model carries the exact unit
#   factor and the placement (Na__Placement: a saved position for this same
#   LAS is restored). The LAS file itself is only ever opened for reading.
#
# POINT CACHE (Na__PointCache): a LAS import also writes the engine's .napc
#   cache on the same worker thread, named by and recording the LAS content
#   key; a job started with 'fromCache' loads that cache instead of the LAS
#   (about a second instead of a full read), and the engine refuses a cache
#   recording any other key. A cache that turns out unusable falls back to
#   reading the LAS, if it is there.
#
# RECORD IDENTITY: the cloud remembers which LAS record each point came from
#   (las_info['hasRecordIndex']); exporting a cleaned copy needs it.
#
# 'onCloud' (Ruby callers only): a callable that takes the finished cloud and
#   returns the status message, instead of the usual install, placement and
#   link (the Clean export loads its new file this way).
#
# WHICH CLOUD (v0.10.0): 'slotId' loads into that cloud (Reload, Locate);
#   without it, the cloud of the model that already names this LAS, else a NEW
#   cloud of the model. The cloud loaded becomes the active one and is shown.
#   Na__ReloadSeriesJob (below) loads several clouds one after the other.
#
# =============================================================================

module Na__PointCloudViewer
    module Na__LasImport

        class Na__LasImportJob

            NA_POLL_SECONDS = 0.1
            NA_PHASE_TEXT = {
                0 => 'Opening the LAS file...',
                1 => 'Reading point records',
                2 => 'Converting colours...',
                3 => 'Shuffling points so the point budget samples the whole cloud',
                4 => 'Saving a point cache so the next Reload is quick',
                5 => 'Preparing viewport data...'
            }.freeze

            # options: 'cachePath' + 'lasStamp' [bytes, mtime] -> also write the cache;
            #          'fromCache' (+ 'expectCount', 'lasMissing') -> load that cache instead;
            #          'contentKey' -> the LAS content key (recorded in, or required of, the cache);
            #          'slotId' -> the cloud to load into; 'noZoom' -> keep the camera;
            #          'onCloud' -> see the file header.
            def initialize(session, view, path, source_unit, header_ms, options = {})
                @session     = session
                @view        = view
                @path        = path
                @source_unit = source_unit
                @header_ms   = header_ms
                @options     = options || {}
                @from_cache  = @options['fromCache']
                @handle      = nil
                @fell_back   = false
                @started_ms  = Na__PerfStats.Na__Perf__NowMs
                @summary     = { 'kind' => 'las' }
            end

            def na_title
                @from_cache ? "Loading #{File.basename(@path)}" : "Importing #{File.basename(@path)}"
            end

            def na_step
                unless @handle
                    if @from_cache
                        @handle = Na__NativeEngine.Na__Native__CacheLoadStart(@from_cache, @options['expectCount'].to_i, @options['contentKey'])
                        return { 'done' => false, 'status' => 'Opening the point cache...', 'percent' => 1.0, 'delay' => NA_POLL_SECONDS }
                    end
                    fallback = Na__ConfigLoader.Na__Config__GetOr([110, 110, 110], 'render', 'noRgbFallbackRgb')
                    las_bytes, las_mtime = @options['lasStamp'] || [0, 0]
                    @handle = Na__NativeEngine.Na__Native__LasImportStart(@path, fallback, @options['cachePath'], las_bytes, las_mtime, @options['contentKey'])
                    return { 'done' => false, 'status' => NA_PHASE_TEXT[0], 'percent' => 1.0, 'delay' => NA_POLL_SECONDS }
                end

                poll = Na__NativeEngine.Na__Native__JobPoll(@handle)
                return self.na_finish(poll) if poll['finished'].to_i == 1
                { 'done' => false, 'status' => self.na_status(poll), 'percent' => self.na_percent(poll), 'delay' => NA_POLL_SECONDS }
            end

            def na_cancel
                return unless @handle
                Na__NativeEngine.Na__Native__JobCancel(@handle)
                Na__NativeEngine.Na__Native__JobDestroy(@handle)
                @handle = nil
            end

            def na_result_summary
                @summary
            end

            # ---------------------------------------------------------------
            # Finish
            # ---------------------------------------------------------------

            def na_finish(poll)
                if poll['failed'].to_i == 1
                    message = Na__NativeEngine.Na__Native__JobError(@handle)
                    return self.na_fall_back_to_las(message) if @from_cache && File.file?(@path)
                    raise message.empty? ? 'The LAS import failed.' : message
                end
                cache_note = self.na_cache_note(poll)

                pointer = Na__NativeEngine.Na__Native__JobTakeCloud(@handle)
                Na__NativeEngine.Na__Native__JobDestroy(@handle)
                @handle = nil
                raise 'The LAS import finished without a point cloud.' unless pointer

                cloud = self.na_build_cloud(pointer, poll)
                if @options['onCloud']
                    message = @options['onCloud'].call(cloud)
                    @summary = { 'kind' => 'las', 'totalPoints' => cloud.total_points, 'timings' => cloud.timings, 'fromCache' => @from_cache ? true : false }
                    return { 'done' => true, 'status' => message, 'percent' => 100.0 }
                end
                slot, is_new = self.na_target_slot(cloud)
                others_loaded = Na__CloudSet.Na__Slots__Loaded(@session).any? { |other| !other.equal?(slot) }
                restored = Na__Placement.Na__Placement__AttachCloud(slot, cloud)
                Na__RenderController.Na__Render__InstallCloud(slot, cloud, @view)
                Na__ModelLink.Na__Link__AfterImport(slot, cloud)
                slot.visible = true
                Na__CloudSet.Na__Slots__Activate(@session, slot)
                Na__ModelRegistry.Na__Registry__SetVisible(true)
                Na__RenderController.Na__Render__ZoomToCloud(slot, @view) if !@options['noZoom'] && (is_new || !others_loaded)

                @summary = { 'kind' => 'las', 'totalPoints' => cloud.total_points, 'timings' => cloud.timings, 'fromCache' => @from_cache ? true : false,
                             'cloudId' => slot.id, 'cloudName' => slot.name, 'newCloud' => is_new }
                shown = [@session.settings['pointBudget'].to_i, cloud.total_points].min
                seconds = format('%.1f', cloud.timings['importWallMs'] / 1000.0)
                message = if @from_cache
                              "Loaded #{Na__PerfStats.Na__Perf__Thousands(cloud.total_points)} points of #{File.basename(@path)} from the point cache in #{seconds} s."
                          else
                              "Imported #{Na__PerfStats.Na__Perf__Thousands(cloud.total_points)} points from #{File.basename(@path)} " \
                                  "(#{Na__UnitContract.Na__Units__SourceUnitLabel(@source_unit)}) in #{seconds} s."
                          end
                if is_new && Na__CloudSet.Na__Slots__Multi?(@session)
                    message = "Added #{slot.name} to the model. #{message} It is the cloud the tools work on now."
                else
                    message = "#{Na__CloudSet.Na__Slots__Prefix(slot)}#{message}"
                end
                message += ' The LAS was not found at its saved location; this computer\'s cached copy of it was used.' if @options['lasMissing']
                message += ' Its saved position in this model was restored.' if restored
                message += " #{cache_note}" if cache_note
                if Na__CloudSet.Na__Slots__Drawn(@session).length > 1
                    message += " The point budget (#{Na__PerfStats.Na__Perf__Thousands(@session.settings['pointBudget'])}) is shared by the clouds on show."
                elsif shown < cloud.total_points
                    message += " Showing #{Na__PerfStats.Na__Perf__Thousands(shown)}. Raise the Point Budget to see more."
                end
                { 'done' => true, 'status' => message, 'percent' => 100.0 }
            end

            # [slot, new?]: the cloud asked for, else the model's cloud of this
            # same LAS, else a new cloud of the model.
            def na_target_slot(cloud)
                slot = @options['slotId'] ? Na__CloudSet.Na__Slots__Find(@session, @options['slotId']) : nil
                key = Na__Placement.Na__Placement__CloudKey(cloud)
                slot ||= Na__CloudSet.Na__Slots__ForFile(@session, (cloud.las_info || {})['contentKey'], Na__ModelLink.Na__Link__FingerprintFromKey(key))
                return [slot, false] if slot
                [Na__CloudSet.Na__Slots__New(@session, cloud), true]
            end

            def na_build_cloud(pointer, poll)
                factor = Na__UnitContract.Na__Units__InchesPerSourceUnit(@source_unit)

                cloud = Na__CloudData.new
                cloud.label             = File.basename(@path)
                cloud.source_kind       = 'las'
                cloud.source_unit       = @source_unit
                cloud.source_path       = @path
                cloud.total_points      = poll['pointCount'].to_i
                cloud.native_cloud      = pointer
                cloud.native_generation = Na__NativeEngine.Na__Native__Generation
                cloud.unit_factor       = factor
                cloud.local_min         = [poll['minX'], poll['minY'], poll['minZ']]
                cloud.local_max         = [poll['maxX'], poll['maxY'], poll['maxZ']]
                cloud.local_to_model    = [factor, 0.0, 0.0, 0.0, factor, 0.0, 0.0, 0.0, factor, 0.0, 0.0, 0.0]
                cloud.bounds            = Na__Placement.na_model_bounds(cloud)
                flags = poll['flags'].to_i
                cloud.las_info          = {
                    'localOriginSource' => [poll['originX'], poll['originY'], poll['originZ']],
                    'colourBits'        => poll['colourBits'].to_i,
                    'contentKey'        => poll['contentKey'] || @options['contentKey'],
                    'hasRecordIndex'    => (flags & 1) != 0,
                    'hasTime'           => (flags & 2) != 0,
                    'timeBase'          => poll['timeBase'],
                    'fromCacheVersion'  => @from_cache ? poll['cacheVersion'].to_i : nil
                }
                cloud.timings['lasHeaderMs']    = @header_ms
                cloud.timings['fromCache']      = @from_cache ? true : false
                cloud.timings['lasReadMs']      = poll['readMs'].round(1)
                cloud.timings['lasColourMs']    = poll['colourMs'].round(1)
                cloud.timings['lasShuffleMs']   = poll['shuffleMs'].round(1)
                cloud.timings['nativeImportMs'] = poll['totalMs'].round(1)
                cloud.timings['importWallMs']   = (Na__PerfStats.Na__Perf__NowMs - @started_ms).round(1)
                cloud
            end

            # The cache could not be used (damaged, or from another version):
            # delete it and read the LAS instead, writing a fresh cache.
            def na_fall_back_to_las(message)
                Na__DebugTools.Na__Debug__Warn("Point cache not used (#{message}); reading the LAS instead.")
                Na__NativeEngine.Na__Native__JobDestroy(@handle)
                @handle = nil
                cache_path = @from_cache
                File.delete(cache_path) if File.file?(cache_path)
                @from_cache = nil
                @fell_back  = true
                key = @options['contentKey'] || Na__NativeEngine.Na__Native__LasContentKey(@path)
                @options = @options.reject { |name, _| %w[fromCache expectCount lasMissing].include?(name) }
                                   .merge('cachePath' => Na__PointCache.Na__Cache__PathForKey(key), 'contentKey' => key,
                                          'lasStamp' => Na__PointCache.Na__Cache__LasStamp(@path))
                { 'done' => false, 'status' => 'The point cache could not be used; reading the LAS instead...', 'percent' => 1.0, 'delay' => NA_POLL_SECONDS }
            rescue SystemCallError
                { 'done' => false, 'status' => 'Reading the LAS instead...', 'percent' => 1.0, 'delay' => NA_POLL_SECONDS }
            end

            def na_cache_note(poll)
                return nil if @from_cache || !@options['cachePath']
                case poll['cacheState'].to_i
                when 1  then 'A point cache was saved, so the next Reload takes about a second.'
                when -1 then "No point cache was saved (#{Na__NativeEngine.Na__Native__JobError(@handle)})."
                end
            end

            # ---------------------------------------------------------------
            # Progress text
            # ---------------------------------------------------------------

            def na_status(poll)
                phase = poll['phase'].to_i
                return 'Reading the point cache...' if @from_cache && phase == 1
                text  = NA_PHASE_TEXT.fetch(phase, 'Working...')
                return text unless [1, 3].include?(phase) && poll['total'].to_i > 0
                "#{text}... #{Na__PerfStats.Na__Perf__Thousands(poll['done'])} of #{Na__PerfStats.Na__Perf__Thousands(poll['total'])}"
            end

            def na_percent(poll)
                total = [poll['total'].to_f, 1.0].max
                fraction = poll['done'].to_f / total
                return (2.0 + 95.0 * fraction).round(1) if @from_cache && poll['phase'].to_i == 1
                case poll['phase'].to_i
                when 1 then 2.0 + 78.0 * fraction
                when 2 then 81.0
                when 3 then 82.0 + 8.0 * fraction
                when 4 then 90.0 + 9.0 * fraction
                else 1.0
                end.round(1)
            end

        end

        # -------------------------------------------------------------------
        # Reload All: several clouds, one after the other
        # -------------------------------------------------------------------

        # Loads every given cloud (Reload All, or TrueVision Sync's Reload) one
        # after the other with the usual job for each. A cloud whose file cannot
        # be found, or whose load fails, is listed at the end; the others still
        # load. Cancel stops after the cloud being loaded is cancelled.
        class Na__ReloadSeriesJob

            def initialize(session, slots)
                @session = session
                @queue   = slots.dup
                @total   = slots.length
                @index   = 0
                @current = nil
                @slot    = nil
                @loaded  = []
                @missed  = []
                @had_loaded = Na__CloudSet.Na__Slots__Loaded(session).any?
                @summary = { 'kind' => 'lasSeries' }
            end

            def na_title
                "Reloading #{@total} point clouds"
            end

            def na_step
                unless @current
                    return self.na_finish if @queue.empty?
                    @slot = @queue.shift
                    @index += 1
                    return self.na_next_soon if !Na__CloudSet.Na__Slots__All(@session).include?(@slot) || !Na__ModelLink.Na__Link__NeedsReload?(@slot)
                    plan = Na__ModelLink.Na__Link__ReloadPlan(@slot)
                    if plan.is_a?(String)
                        @missed << "#{@slot.name} (#{plan.sub(/\.\z/, '')})"
                        return self.na_next_soon
                    end
                    @current = Na__LasImport.Na__LasImport__JobForPlan(@slot, plan, 'noZoom' => true)
                end
                step = @current.na_step
                if step['done']
                    @current = nil
                    @loaded << @slot.name
                    return self.na_next_soon
                end
                fraction = ((@index - 1) + step['percent'].to_f / 100.0) / [@total, 1].max
                { 'done' => false, 'status' => "#{@slot.name} (#{@index} of #{@total}): #{step['status']}",
                  'percent' => (100.0 * fraction).round(1), 'delay' => step['delay'] }
            rescue StandardError => error
                begin
                    @current.na_cancel if @current
                rescue StandardError
                    nil
                end
                @current = nil
                @missed << "#{@slot ? @slot.name : 'a cloud'} (#{error.message.sub(/\.\z/, '')})"
                Na__DebugTools.Na__Debug__Warn("Reload All: #{@slot && @slot.name} did not load: #{error.message}")
                self.na_next_soon
            end

            def na_cancel
                @current.na_cancel if @current
                @current = nil
                @queue.clear
            end

            def na_cancel_message
                @loaded.empty? ? 'Cancelled. No point cloud was loaded.' : "Cancelled. Loaded: #{@loaded.join(', ')}. The others are not loaded."
            end

            def na_result_summary
                @summary
            end

            def na_next_soon
                return self.na_finish if @queue.empty?
                { 'done' => false, 'status' => "Next point cloud (#{@index + 1} of #{@total})...", 'percent' => (100.0 * @index / [@total, 1].max).round(1), 'delay' => 0.01 }
            end

            def na_finish
                view = Sketchup.active_model.active_view
                Na__RenderController.Na__Render__ZoomToCloud(@session, view) if !@had_loaded && !@loaded.empty?
                @summary = { 'kind' => 'lasSeries', 'loaded' => @loaded, 'missed' => @missed }
                text = @loaded.empty? ? 'No point cloud was loaded.' : "Reloaded #{self.na_list(@loaded)}."
                text += " Not loaded: #{@missed.join('; ')}. Use Locate LAS on its row." unless @missed.empty?
                text += " The point budget (#{Na__PerfStats.Na__Perf__Thousands(@session.settings['pointBudget'])}) is shared by the clouds on show." if @loaded.length > 1
                result = { 'done' => true, 'status' => text, 'percent' => 100.0 }
                result['outcome'] = 'partial' unless @missed.empty?
                result
            end

            def na_list(names)
                names.length <= 1 ? names.join : "#{names[0..-2].join(', ')} and #{names[-1]}"
            end

        end

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
