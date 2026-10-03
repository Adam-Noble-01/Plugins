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
                4 => 'Preparing viewport data...'
            }.freeze

            def initialize(session, view, path, source_unit, header_ms)
                @session     = session
                @view        = view
                @path        = path
                @source_unit = source_unit
                @header_ms   = header_ms
                @handle      = nil
                @started_ms  = Na__PerfStats.Na__Perf__NowMs
                @summary     = { 'kind' => 'las' }
            end

            def na_title
                "Importing #{File.basename(@path)}"
            end

            def na_step
                unless @handle
                    fallback = Na__ConfigLoader.Na__Config__GetOr([110, 110, 110], 'render', 'noRgbFallbackRgb')
                    @handle = Na__NativeEngine.Na__Native__LasImportStart(@path, fallback)
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
                    raise message.empty? ? 'The LAS import failed.' : message
                end

                pointer = Na__NativeEngine.Na__Native__JobTakeCloud(@handle)
                Na__NativeEngine.Na__Native__JobDestroy(@handle)
                @handle = nil
                raise 'The LAS import finished without a point cloud.' unless pointer

                cloud = self.na_build_cloud(pointer, poll)
                restored = Na__Placement.Na__Placement__AttachCloud(@session, cloud)
                Na__RenderController.Na__Render__InstallCloud(@session, cloud, @view)
                Na__ModelLink.Na__Link__AfterImport(@session, cloud)
                Na__ModelRegistry.Na__Registry__SetVisible(true)
                Na__RenderController.Na__Render__ZoomToCloud(@session, @view)

                @summary = { 'kind' => 'las', 'totalPoints' => cloud.total_points, 'timings' => cloud.timings }
                shown = [@session.settings['pointBudget'].to_i, cloud.total_points].min
                message = "Imported #{Na__PerfStats.Na__Perf__Thousands(cloud.total_points)} points from #{File.basename(@path)} " \
                          "(#{Na__UnitContract.Na__Units__SourceUnitLabel(@source_unit)}) in #{format('%.1f', cloud.timings['importWallMs'] / 1000.0)} s."
                message += ' Its saved position in this model was restored.' if restored
                message += " Showing #{Na__PerfStats.Na__Perf__Thousands(shown)}. Raise the Point Budget to see more." if shown < cloud.total_points
                { 'done' => true, 'status' => message, 'percent' => 100.0 }
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
                cloud.las_info          = {
                    'localOriginSource' => [poll['originX'], poll['originY'], poll['originZ']],
                    'colourBits'        => poll['colourBits'].to_i
                }
                cloud.timings['lasHeaderMs']    = @header_ms
                cloud.timings['lasReadMs']      = poll['readMs'].round(1)
                cloud.timings['lasColourMs']    = poll['colourMs'].round(1)
                cloud.timings['lasShuffleMs']   = poll['shuffleMs'].round(1)
                cloud.timings['nativeImportMs'] = poll['totalMs'].round(1)
                cloud.timings['importWallMs']   = (Na__PerfStats.Na__Perf__NowMs - @started_ms).round(1)
                cloud
            end

            # ---------------------------------------------------------------
            # Progress text
            # ---------------------------------------------------------------

            def na_status(poll)
                phase = poll['phase'].to_i
                text  = NA_PHASE_TEXT.fetch(phase, 'Working...')
                return text unless [1, 3].include?(phase) && poll['total'].to_i > 0
                "#{text}... #{Na__PerfStats.Na__Perf__Thousands(poll['done'])} of #{Na__PerfStats.Na__Perf__Thousands(poll['total'])}"
            end

            def na_percent(poll)
                total = [poll['total'].to_f, 1.0].max
                case poll['phase'].to_i
                when 1 then 2.0 + 83.0 * poll['done'].to_f / total
                when 2 then 86.0
                when 3 then 88.0 + 11.0 * poll['done'].to_f / total
                else 1.0
                end.round(1)
            end

        end

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
