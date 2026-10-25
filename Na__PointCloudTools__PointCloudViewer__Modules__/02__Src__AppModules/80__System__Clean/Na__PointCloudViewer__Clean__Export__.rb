# =============================================================================
# NA POINT CLOUD VIEWER - CLEAN - EXPORT
# =============================================================================
#
# FILE       : Na__PointCloudViewer__Clean__Export__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__CleanExport
# PURPOSE    : Clean & Export LAS: cleans the WHOLE cloud with the Clean tab's
#              settings, writes the result as a NEW LAS file, loads it, and
#              only then makes the model use it.
#
# THE ORIGINAL IS NEVER TOUCHED (the rules, in order):
#   1. Save As every time; the suggested name is <name>_Cleaned_01.las, then
#      _02 and so on (the first free one). There is no option to overwrite:
#      the source file itself, and any file that already exists, are refused
#      (the engine checks again: it creates the new file exclusively and
#      refuses one that turns out to be the source through another path).
#   2. The engine cleans the whole cloud in tiles on its own thread, writes
#      <final>.partial-<tag> in the destination folder, flushes it, reads it
#      back with LASzip and checks every record, then renames it into place
#      WITHOUT replacing anything. Cancel or any failure deletes the partial
#      file; nothing else is ever deleted.
#   3. The new file is loaded like any LAS (a new point cache, named by its
#      own content key; the original's cache is kept).
#   4. Only when export, check and load have all succeeded does the model
#      change: the cloud's link names the new file (what it was made from is
#      kept) and its position is carried over exactly, as ONE undoable
#      operation "Point Cloud: Use Cleaned LAS". The clip box and scenes are
#      in model coordinates and need no change. It is the same cloud of the
#      model (the same id), now made from the cleaned file; the model's other
#      clouds are not touched.
#   5. Export done but loading failed or cancelled: the file stays, the model
#      keeps the original, and Load Cleaned LAS tries again.
#   SketchUp's Undo can put the model's link back to the earlier file; Undo
#   never deletes, moves or changes any file.
#
# CROP AND CUT (v0.11.0): Remove Points & Export LAS (Na__CleanBoxes) is a job
#   of this same class, kind 'boxes', and follows every rule above. Only how
#   the points are decided differs: the boxes mark them (no cleaning, nothing
#   moves), the suggested name is <name>_Cropped_NN.las, the operation is
#   "Point Cloud: Use Cropped LAS", and it also clears the boxes, which have
#   done their work (the same Undo brings them back).
#
# COORDINATES: the new LAS keeps the source's own coordinates, scale and
#   offset; the SketchUp position is never baked in. Its bounds (and so its
#   local origin) can differ from the source's, so the position is carried
#   over by Na__Placement__ForNewOrigin and the cloud stays where it was.
#
# =============================================================================

module Na__PointCloudViewer
    module Na__CleanExport

    # -------------------------------------------------------------------------
    # REGION | Checks + Names
    # -------------------------------------------------------------------------

        # nil, or why Clean & Export cannot start (shown on the button).
        def self.Na__CleanExport__Blocker(slot)
            problem = self.Na__CleanExport__SourceBlocker(slot)
            return problem if problem
            settings = Na__CleanSettings.Na__CleanSettings__Current
            return 'Turn on at least one filter first.' unless Na__CleanSettings::NA_FILTERS.any? { |filter| settings[filter]['enabled'] }
            return 'Another task is still running.' if Na__AsyncJobs.Na__Jobs__Busy?
            nil
        end

        # nil, or why the cloud's LAS cannot be the source of a new file (both
        # exports read the original's own records).
        def self.Na__CleanExport__SourceBlocker(slot)
            cloud = slot ? slot.cloud : nil
            return slot ? "Load #{slot.name} first (View tab)." : 'Load a point cloud first.' unless cloud
            info = cloud.las_info || {}
            unless info['hasRecordIndex']
                return 'This cloud came from a point cache made before v0.8.0, which does not record where each point is in the LAS. ' \
                       'Clear Point Caches (Settings tab), then Reload Point Cloud, then export.'
            end
            path = cloud.source_path.to_s
            unless File.file?(path)
                return "The LAS this cloud came from is not at #{path}. Use Locate LAS on the View tab first: the export reads the original file."
            end
            return 'Only an uncompressed .las source can be cleaned and exported.' unless File.extname(path).casecmp('.las').zero?
            nil
        end

        # [nil, content key] when the LAS on disk is still the one loaded, else
        # [why not, nil]. Reads its header and about 2 MB for the key.
        def self.na_check_source(cloud)
            source = cloud.source_path.to_s
            info   = cloud.las_info || {}
            header = Na__NativeEngine.Na__Native__LasReadHeader(source)
            return ['The LAS file is LAZ-compressed; only uncompressed LAS can be cleaned and exported.', nil] if header['isCompressed'].to_i == 1
            if header['pointCount'].to_i != cloud.total_points.to_i
                return ["The LAS file now holds #{Na__PerfStats.Na__Perf__Thousands(header['pointCount'])} points but the loaded cloud has " \
                        "#{Na__PerfStats.Na__Perf__Thousands(cloud.total_points)}. It has changed since it was loaded: Reload Point Cloud first.", nil]
            end
            key = Na__NativeEngine.Na__Native__LasContentKey(source)
            if info['contentKey'] && key != info['contentKey']
                return ['The LAS file has changed since this cloud was loaded. Reload Point Cloud first, then export.', nil]
            end
            [nil, key]
        end

        # <stem><suffix>NN.las (suffix _Cleaned_ unless given), the first number
        # not taken in that folder. A source that is itself such a copy counts on
        # from its stem.
        def self.Na__CleanExport__SuggestedName(source_path, suffix = nil)
            return '' if source_path.to_s.empty?
            suffix ||= Na__ConfigLoader.Na__Config__GetOr('_Cleaned_', 'clean', 'export', 'suffix').to_s
            folder = File.dirname(source_path)
            stem = File.basename(source_path, '.*').sub(/#{Regexp.escape(suffix)}\d+\z/i, '')
            (1..999).each do |number|
                name = format('%s%s%02d.las', stem, suffix, number)
                return name unless File.exist?(File.join(folder, name))
            end
            format('%s%s%s.las', stem, suffix, Time.now.strftime('%Y%m%d-%H%M%S'))
        end

        # nil, or why this destination is refused.
        def self.Na__CleanExport__DestinationProblem(source_path, dest_path)
            name = File.basename(dest_path)
            return 'Save the new cloud as a .las file.' unless File.extname(dest_path).casecmp('.las').zero?
            if File.expand_path(dest_path).casecmp(File.expand_path(source_path)).zero?
                return "#{name} is the original LAS. The original is never overwritten: choose a new name."
            end
            return "#{name} already exists. Nothing is ever overwritten: choose a new name." if File.exist?(dest_path)
            return "The folder #{File.dirname(dest_path)} does not exist." unless File.directory?(File.dirname(dest_path))
            nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Start (from the dialog)
    # -------------------------------------------------------------------------

        # Returns nil when the job has started, 'cancelled', or a reason.
        def self.Na__CleanExport__Start(slot)
            problem = self.Na__CleanExport__Blocker(slot)
            return problem if problem
            cloud  = slot.cloud
            source = cloud.source_path.to_s
            info   = cloud.las_info || {}
            problem, key = self.na_check_source(cloud)
            return problem if problem

            dest = self.na_ask_destination(source)
            return 'cancelled' unless dest

            settings = Na__CleanSettings.Na__CleanSettings__Current
            mm_per_unit = Na__CleanSettings.Na__CleanSettings__MmPerUnit(cloud)
            params = Na__CleanSettings.Na__CleanSettings__EngineParams(mm_per_unit, settings)
            provenance = self.na_provenance(slot, cloud, key, settings, params)
            Na__Placement.Na__Placement__Ensure(slot)
            return 'The loaded cloud has no position record; Reload it first.' unless slot.placement
            job = Na__CleanExportJob.new(slot, Sketchup.active_model.active_view, {
                'source' => source, 'dest' => dest, 'params' => params, 'provenance' => provenance,
                'origin' => info['localOriginSource'], 'sourceKey' => key, 'settings' => settings
            })
            Na__AsyncJobs.Na__Jobs__Start(job) ? nil : 'Another task is still running.'
        end

        # Retry after an export whose loading failed or was cancelled (either
        # kind: the retry remembers which).
        def self.Na__CleanExport__RetryLoad(slot)
            state = Na__CleanPreview.Na__Clean__State(slot)
            retry_info = state.retry_load
            return 'There is no new LAS waiting to be loaded.' unless retry_info
            return "The new LAS is no longer at #{retry_info['path']}." unless File.file?(retry_info['path'])
            return 'Another task is still running.' if Na__AsyncJobs.Na__Jobs__Busy?
            job = Na__CleanExportJob.new(slot, Sketchup.active_model.active_view, retry_info.merge('reloadOnly' => true))
            Na__AsyncJobs.Na__Jobs__Start(job) ? nil : 'Another task is still running.'
        end

        # Save As until the user picks an acceptable new file or cancels.
        def self.na_ask_destination(source, title = 'Save the cleaned point cloud as a NEW LAS file', suffix = nil)
            folder = File.dirname(source)
            name = self.Na__CleanExport__SuggestedName(source, suffix)
            20.times do
                path = UI.savepanel(title, folder, name)
                return nil unless path
                path = path.tr('\\', '/')
                path += '.las' if File.extname(path).empty?
                problem = self.Na__CleanExport__DestinationProblem(source, path)
                return path unless problem
                UI.messagebox(problem)
                folder = File.dirname(path) if File.directory?(File.dirname(path))
                name = self.Na__CleanExport__SuggestedName(File.join(folder, File.basename(source)), suffix)
            end
            nil
        end

        def self.na_provenance(slot, cloud, source_key, settings, params)
            model = slot.model
            JSON.generate(
                'tool'        => Na__ConfigLoader.Na__Config__GetOr('Na Point Cloud Viewer', 'plugin', 'name'),
                'version'     => Na__PointCloudViewer.Na__PublicApi__Version,
                'operation'   => 'clean',
                'exportId'    => format('%016x', Random.new.rand(2**64)),   # every export a distinct file (and content key)
                'createdAt'   => Time.now.strftime('%Y-%m-%dT%H:%M:%S%z'),
                'source'      => { 'fileName' => File.basename(cloud.source_path.to_s), 'contentKey' => source_key,
                                   'pointCount' => cloud.total_points, 'sourceUnit' => cloud.source_unit },
                'settings'    => Na__CleanSettings.Na__CleanSettings__Provenance(settings),
                'engineParams'=> Na__NativeEngine::NA_CLEAN_PARAM_KEYS.zip(params.map { |v| v.round(6) }).to_h,
                'model'       => { 'title' => model ? model.title.to_s : '' }
            )
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Use the New File (after it has loaded)
    # -------------------------------------------------------------------------

        # Called with the freshly loaded new cloud. Writes the model's link and
        # position (one undoable operation), then installs the cloud. A Crop and
        # Cut export also clears the boxes in that operation: they have done
        # their work, and the same Undo brings them back with the old link.
        # Raises (and leaves the original installed) when the model write fails.
        def self.na_use_cleaned(slot, new_cloud, view, job_info)
            model = slot.model
            raise 'The model this cloud belongs to was closed.' unless model && model.valid?
            raise "#{slot.name} was removed from the model during the export." unless Na__CloudSet.Na__Slots__All(slot.session).include?(slot)
            boxes = job_info['kind'] == 'boxes'
            base = self.na_base(slot, job_info)
            new_key = Na__Placement.Na__Placement__CloudKey(new_cloud)
            placement = Na__Placement.Na__Placement__ForNewOrigin(base['placement'], base['unitFactor'], base['origin'],
                                                                   new_cloud.las_info['localOriginSource'], new_key)
            now = Time.now.strftime('%Y-%m-%dT%H:%M:%S%z')
            previous = slot.record ? slot.record['link'] : nil
            part = Na__ModelLink.Na__Link__CloudPart(model, new_cloud, new_key)
            part['derivedFrom'] = base['derivedFrom'].merge('cleanedAt' => now, 'operation' => boxes ? 'cropCut' : 'clean')
            history = (previous && previous['history'].is_a?(Array) ? previous['history'] : []) +
                      [previous ? previous.reject { |key, _| key == 'history' } : base['derivedFrom']]
            part['history'] = history.last(20)
            part['linkedAt'] = now
            operation = Na__CloudSet.Na__Slots__OpName(slot, boxes ? 'Use Cropped LAS' : 'Use Cleaned LAS')
            problem = Na__CloudStore.Na__Store__WriteSlots(slot.session, [slot], operation) do |_slot, record|
                record['link'] = part
                record['placement'] = Na__Placement.Na__Placement__Part(placement)
                record.delete(Na__CleanBoxes::NA_RECORD_KEY) if boxes
            end
            raise problem if problem
            # the model names the new file now: show it where the old one was
            Na__Placement.Na__Placement__StopTool(slot)
            slot.placement = placement
            slot.placement_note = nil
            if boxes
                slot.box_showing = nil
                slot.box_counts = nil
            end
            Na__Placement.na_apply(slot, new_cloud)
            Na__RenderController.Na__Render__InstallCloud(slot, new_cloud, view)
            slot.visible = true
            Na__ModelRegistry.Na__Registry__SetVisible(true)
        end

        # What the new cloud's position is carried over from: the original
        # cloud as it is placed now if it is still loaded, else as it was when
        # the export started.
        def self.na_base(slot, job_info)
            cloud = slot.cloud
            if cloud && cloud.equal?(job_info['sourceCloud']) && slot.placement
                return {
                    'placement'   => slot.placement,
                    'unitFactor'  => cloud.unit_factor,
                    'origin'      => cloud.las_info['localOriginSource'],
                    'derivedFrom' => job_info['derivedFrom']
                }
            end
            job_info['base']
        end

    # endregion ----------------------------------------------------------------

    end

    # -------------------------------------------------------------------------
    # REGION | The Job (Na__AsyncJobs contract)
    # -------------------------------------------------------------------------

    class Na__CleanExportJob

        NA_POLL_SECONDS = 0.15
        NA_PHASE_TEXT = {
            0 => 'Checking the LAS file...',
            1 => 'Indexing the whole cloud...',
            2 => 'Cleaning the whole cloud',
            3 => 'Writing the new LAS',
            4 => 'Reading the new file back and checking every point',
            5 => 'Publishing the new file (nothing is replaced)...',
            6 => 'Finishing...'
        }.freeze
        NA_PHASE_SPAN = { 0 => [0, 1], 1 => [1, 5], 2 => [5, 60], 3 => [60, 75], 4 => [75, 88], 5 => [88, 89], 6 => [89, 90] }.freeze
        # Crop and Cut: marking is quick; writing and the check are the work.
        NA_BOX_PHASE_TEXT = {
            0 => 'Checking the LAS file...',
            2 => 'Marking the points the boxes remove',
            3 => 'Writing the new LAS',
            4 => 'Reading the new file back and checking every point',
            5 => 'Publishing the new file (nothing is replaced)...',
            6 => 'Finishing...'
        }.freeze
        NA_BOX_PHASE_SPAN = { 0 => [0, 1], 2 => [1, 6], 3 => [6, 60], 4 => [60, 88], 5 => [88, 89], 6 => [89, 90] }.freeze

        # info: 'source', 'dest', 'params', 'provenance', 'origin', 'sourceKey', 'settings';
        #       or, kind 'boxes' (Crop and Cut): 'source', 'dest', 'transform', 'block',
        #       'provenance', 'origin', 'sourceKey', 'counts';
        #       or a retry: 'path' + 'unit' + 'base' + 'kind' + 'reloadOnly'.
        def initialize(slot, view, info)
            @slot = slot
            @view    = view
            @info    = info
            @kind    = info['kind'] == 'boxes' ? 'boxes' : 'clean'
            @handle  = nil
            @reload  = nil
            @result  = nil
            @cancel_message = nil
            cloud = slot.cloud
            if info['reloadOnly']
                @stage    = :reload
                @dest     = info['path']
                @unit     = info['unit']
                @job_info = info
            else
                @stage    = :export
                @dest     = info['dest']
                @unit     = cloud.source_unit
                derived = {
                    'fileName'   => File.basename(info['source']),
                    'lastPath'   => info['source'],
                    'contentKey' => info['sourceKey'],
                    'pointCount' => cloud.total_points,
                    'sourceUnit' => cloud.source_unit
                }
                @job_info = {
                    'kind'        => @kind,
                    'sourceCloud' => cloud,
                    'derivedFrom' => derived,
                    'base' => {
                        'placement'   => Marshal.load(Marshal.dump(slot.placement)),
                        'unitFactor'  => cloud.unit_factor,
                        'origin'      => (cloud.las_info || {})['localOriginSource'],
                        'derivedFrom' => derived
                    }
                }
            end
        end

        def na_title
            return "Loading #{File.basename(@dest)}" if @stage == :reload && @info['reloadOnly']
            source = File.basename(@info['source'].to_s)
            @kind == 'boxes' ? "Remove Points from #{source}" : "Clean & Export #{source}"
        end

        def na_step
            @stage == :export ? self.na_step_export : self.na_step_reload
        end

        def na_cancel
            if @stage == :export
                if @handle
                    Na__NativeEngine.Na__Native__ExportCancel(@handle)
                    poll = self.na_wait_finished(@handle)
                    Na__NativeEngine.Na__Native__ExportDestroy(@handle)   # joins; deletes any partial file
                    @handle = nil
                    # Cancel came after the new file was published: it stays, and is offered
                    if poll && poll['finished'].to_i == 1 && poll['failed'].to_i.zero? && poll['cancelled'].to_i.zero? && File.file?(@dest)
                        self.na_offer_retry
                        @cancel_message = "#{File.basename(@dest)} had already been written and checked when you cancelled. " \
                                          "The model still uses the original. #{self.na_retry_words} loads it."
                        return
                    end
                end
                @cancel_message = 'Cancelled. Nothing was written and the original LAS is untouched.'
            else
                @reload.na_cancel if @reload
                @reload = nil
                self.na_offer_retry
                @cancel_message = "#{File.basename(@dest)} was written and checked, but loading it was cancelled. " \
                                  "The model still uses the original. #{self.na_retry_words} loads it."
            end
        end

        # Where the retry button is, in words.
        def na_retry_words
            @kind == 'boxes' ? 'Load Cropped LAS (Clean tab, Crop and Cut)' : 'Load Cleaned LAS (Clean tab)'
        end

        # After a cancel request the engine stops at its next check (a fraction
        # of a second); its last word says whether it had already published.
        def na_wait_finished(handle)
            deadline = Na__PerfStats.Na__Perf__NowMs + 10_000.0
            loop do
                poll = Na__NativeEngine.Na__Native__ExportPoll(handle)
                return poll if poll['finished'].to_i == 1
                return nil if Na__PerfStats.Na__Perf__NowMs > deadline
                sleep 0.01
            end
        end

        def na_cancel_message
            @cancel_message
        end

        def na_result_summary
            { 'kind' => 'cleanExport', 'export' => @summary }
        end

        # ---------------------------------------------------------------
        # Export
        # ---------------------------------------------------------------

        def na_step_export
            unless @handle
                state = Na__CleanPreview.Na__Clean__State(@slot)
                Na__NativeEngine.Na__Native__CleanCancel(state.context) if state.context   # the filter preview yields
                software = "#{Na__ConfigLoader.Na__Config__GetOr('Na Point Cloud Viewer', 'clean', 'export', 'software')} #{Na__PointCloudViewer.Na__PublicApi__Version}"
                if @kind == 'boxes'
                    cloud = @job_info['sourceCloud']
                    unless cloud && Na__NativeEngine.Na__Native__CloudLive?(cloud.native_cloud)
                        raise "#{@slot.name} was unloaded before the export could start. Nothing was written."
                    end
                    @handle = Na__NativeEngine.Na__Native__BoxExportStart(cloud.native_cloud, @info['source'], @dest, @info['transform'],
                                                                          @info['block'], @info['origin'], @info['provenance'], software)
                else
                    Na__CleanPreview.na_ensure_context(@slot)
                    @handle = Na__NativeEngine.Na__Native__ExportStart(state.context, @info['source'], @dest, @info['params'],
                                                                       @info['origin'], @info['provenance'], software)
                end
                return { 'done' => false, 'status' => self.na_phase_text[0], 'percent' => 0.5, 'delay' => NA_POLL_SECONDS }
            end
            poll = Na__NativeEngine.Na__Native__ExportPoll(@handle)
            return self.na_export_finished(poll) if poll['finished'].to_i == 1
            { 'done' => false, 'status' => self.na_status(poll), 'percent' => self.na_percent(poll), 'delay' => NA_POLL_SECONDS }
        end

        def na_export_finished(poll)
            notes = Na__NativeEngine.Na__Native__ExportNotes(@handle)
            if poll['failed'].to_i == 1 || poll['cancelled'].to_i == 1
                message = poll['cancelled'].to_i == 1 ? 'The export was cancelled.' : Na__NativeEngine.Na__Native__ExportError(@handle)
                Na__NativeEngine.Na__Native__ExportDestroy(@handle)
                @handle = nil
                raise "#{message} The original LAS is untouched." unless message.include?('untouched')
                raise message
            end
            Na__NativeEngine.Na__Native__ExportDestroy(@handle)
            @handle = nil
            raise "The new file was not found at #{@dest} after publishing." unless File.file?(@dest)
            @result = poll
            @notes = notes
            @summary = self.na_export_summary(poll, notes)
            state = Na__CleanPreview.Na__Clean__State(@slot)
            if @kind == 'boxes'
                state.last_box_export = @summary
            else
                state.last_export = @summary
            end
            what = @kind == 'boxes' ? 'Remove Points & Export' : 'Clean & Export'
            Na__DebugTools.Na__Debug__Info("#{what} wrote #{@dest} (#{poll['written'].to_i} points, #{(poll['totalMs'].to_f / 1000).round(1)} s). #{notes}")
            @stage = :reload
            { 'done' => false, 'status' => "Written and checked. Loading #{File.basename(@dest)}...", 'percent' => 90.0, 'delay' => 0.01 }
        end

        # ---------------------------------------------------------------
        # Reload + Use
        # ---------------------------------------------------------------

        def na_step_reload
            unless @reload
                options = Na__LasImport.Na__LasImport__CacheOptions(@dest)
                options['onCloud'] = lambda do |cloud|
                    Na__CleanExport.na_use_cleaned(@slot, cloud, @view, @job_info)
                    self.na_final_message(cloud)
                end
                @reload = Na__LasImport::Na__LasImportJob.new(@slot.session, @view, @dest, @unit, 0, options)
            end
            step = @reload.na_step
            if step['done']
                Na__CleanPreview.Na__Clean__State(@slot).retry_load = nil
                return step
            end
            percent = step['percent'] ? 90.0 + step['percent'].to_f * 0.1 : nil
            { 'done' => false, 'status' => "Loading the new LAS: #{step['status']}", 'percent' => percent, 'delay' => step['delay'] }
        rescue StandardError => error
            begin
                @reload.na_cancel if @reload
            rescue StandardError
                nil
            end
            @reload = nil
            self.na_offer_retry
            Na__DebugTools.Na__Debug__Error('The new LAS was written but could not be loaded.', error)
            {
                'done' => true, 'outcome' => 'partial',
                'status' => "#{File.basename(@dest)} was written and checked, but loading it failed (#{error.message}). " \
                            "The file is kept and the model still uses the original. #{self.na_retry_words} tries again."
            }
        end

        def na_offer_retry
            Na__CleanPreview.Na__Clean__State(@slot).retry_load = {
                'kind' => @kind, 'path' => @dest, 'unit' => @unit, 'base' => @job_info['base'], 'derivedFrom' => @job_info['derivedFrom'],
                'sourceCloud' => @job_info['sourceCloud']
            }
        end

        def na_final_message(cloud)
            name = File.basename(@dest)
            unless @result
                return "Loaded #{name} (#{Na__PerfStats.Na__Perf__Thousands(cloud.total_points)} points). The model now uses it; the original LAS is untouched."
            end
            return self.na_final_box_message(name) if @kind == 'boxes'
            removed = @result['removed'].to_i
            source = @result['sourcePoints'].to_i
            share = source > 0 ? removed * 100.0 / source : 0.0
            text = "Saved #{name}: #{Na__PerfStats.Na__Perf__Thousands(@result['written'])} points " \
                   "(#{Na__PerfStats.Na__Perf__Thousands(removed)} removed, #{format('%.1f', share)} %; " \
                   "#{Na__PerfStats.Na__Perf__Thousands(@result['moved'])} refined) in #{format('%.1f', @result['totalMs'].to_f / 1000.0)} s. " \
                   'It was checked point by point and is now the model\'s point cloud, in the same position. ' \
                   'The original LAS and its cache are untouched; Undo puts the model\'s link back.'
            text += " #{Na__PerfStats.Na__Perf__Thousands(@result['heldRange'])} points kept their position: the file's coordinate range could not hold the move." if @result['heldRange'].to_i > 0
            text
        end

        def na_final_box_message(name)
            thousands = ->(value) { Na__PerfStats.Na__Perf__Thousands(value.to_i) }
            removed = @result['removed'].to_i
            source = @result['sourcePoints'].to_i
            share = source > 0 ? removed * 100.0 / source : 0.0
            parts = []
            parts << "#{thousands.(@result['removedKeep'])} outside the Keep box" if @result['removedKeep'].to_i > 0
            parts << "#{thousands.(@result['removedCut'])} inside the Cut boxes" if @result['removedCut'].to_i > 0
            "Saved #{name}: #{thousands.(@result['written'])} points kept, #{thousands.(removed)} removed (#{format('%.1f', share)} %" \
                "#{parts.empty? ? '' : ': ' + parts.join(', ')}) in #{format('%.1f', @result['totalMs'].to_f / 1000.0)} s. " \
                'It was checked point by point and is now the model\'s point cloud, in the same position. ' \
                'The original LAS and its cache are untouched; Undo puts the model\'s link and the boxes back.'
        end

        # ---------------------------------------------------------------
        # Progress + summary
        # ---------------------------------------------------------------

        def na_phase_text
            @kind == 'boxes' ? NA_BOX_PHASE_TEXT : NA_PHASE_TEXT
        end

        def na_status(poll)
            phase = poll['phase'].to_i
            text = self.na_phase_text.fetch(phase, 'Working...')
            total = poll['total'].to_i
            return text unless [2, 3, 4].include?(phase) && total > 0
            unit = phase == 2 ? 'points' : 'records'
            "#{text}... #{Na__PerfStats.Na__Perf__Thousands(poll['done'])} of #{Na__PerfStats.Na__Perf__Thousands(total)} #{unit}"
        end

        def na_percent(poll)
            span = (@kind == 'boxes' ? NA_BOX_PHASE_SPAN : NA_PHASE_SPAN).fetch(poll['phase'].to_i, [0, 1])
            total = poll['total'].to_f
            fraction = total > 0 ? [[poll['done'].to_f / total, 0.0].max, 1.0].min : 0.0
            (span[0] + (span[1] - span[0]) * fraction).round(1)
        end

        def na_export_summary(poll, notes)
            {
                'kind'            => @kind,
                'removedKeep'     => poll['removedKeep'].to_i,
                'removedCut'      => poll['removedCut'].to_i,
                'fileName'        => File.basename(@dest),
                'path'            => @dest,
                'sourcePoints'    => poll['sourcePoints'].to_i,
                'written'         => poll['written'].to_i,
                'removed'         => poll['removed'].to_i,
                'removedIsolated' => poll['removedIsolated'].to_i,
                'removedCluster'  => poll['removedCluster'].to_i,
                'removedBlowout'  => poll['removedBlowout'].to_i,
                'removedDensity'  => poll['removedDensity'].to_i,
                'moved'           => poll['moved'].to_i,
                'heldRange'       => poll['heldRange'].to_i,
                'doubling'        => poll['doubling'].to_i,
                'candidates'      => poll['candidates'].to_i,
                'bytes'           => poll['bytes'].to_i,
                'seconds'         => (poll['totalMs'].to_f / 1000.0).round(1),
                'tiles'           => poll['tiles'].to_i,
                'peakWorkMb'      => poll['peakWorkMb'].to_f.round,
                'notes'           => notes.to_s.split(' | ').reject(&:empty?)
            }
        end

    end

    # endregion ----------------------------------------------------------------

end

# =============================================================================
# END OF FILE
# =============================================================================
