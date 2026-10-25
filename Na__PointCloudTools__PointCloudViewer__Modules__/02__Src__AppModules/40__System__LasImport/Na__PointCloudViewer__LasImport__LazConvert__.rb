# =============================================================================
# NA POINT CLOUD VIEWER - LAS IMPORT - LAZ TO LAS CONVERTER
# =============================================================================
#
# FILE       : Na__PointCloudViewer__LasImport__LazConvert__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__LasImport (+ Na__LazConvertJob)
# PURPOSE    : Import of a LAZ (Polycam and others): decompress it into a NEW
#              uncompressed LAS next to it, then show that LAS's usual import
#              report and unit question. Everything after that (cache, model
#              link, Clean & Export) works on the LAS as it always has.
#
# LOSSLESS (the rule): the native engine (LazConvert.hpp) decodes with the
#   vendored LASzip 3.5.0 and writes every point record back exactly as stored:
#   the same integer X, Y and Z, the same scale and offset, the same colours
#   and attributes, the same header bounds. It never rescales, re-offsets,
#   reorders or recomputes anything. Before the file gets its name, the engine
#   reads it back and checks every record against what was decoded.
#
# THE LAZ IS NEVER TOUCHED, AND NOTHING IS EVER OVERWRITTEN:
#   - Save As every time; the suggested name is <name>.las, or
#     <name>_FromLaz_01.las (then _02 ...) when that is taken. An existing
#     file is refused, never replaced.
#   - The engine writes <final>.partial-<tag>, checks it, then renames it
#     into place without replacing anything. Cancel or any failure deletes
#     the partial file and nothing else.
#
# BOUNDS: the LAS keeps the LAZ header's bounds byte for byte. The engine also
#   measures the points' real extent; the import report says whether the two
#   agree, and by how much when they do not (the import places its local
#   origin from the header bounds and shows the size from them).
#
# =============================================================================

module Na__PointCloudViewer
    module Na__LasImport

    # -------------------------------------------------------------------------
    # REGION | Start (from Import LAS / LAZ)
    # -------------------------------------------------------------------------

        def self.Na__LazConvert__Start(laz_path)
            return Na__DialogManager.Na__Dialog__PushStatus('Another task is still running.', 'error') if Na__AsyncJobs.Na__Jobs__Busy?
            dest = self.na_laz_ask_destination(laz_path)
            return Na__DialogManager.Na__Dialog__PushStatus('LAZ conversion cancelled. Nothing was written.', 'info') unless dest
            job = Na__LazConvertJob.new(laz_path, dest)
            Na__DialogManager.Na__Dialog__PushStatus('Another task is still running.', 'error') unless Na__AsyncJobs.Na__Jobs__Start(job)
        end

        # <stem>.las, or <stem>_FromLaz_NN.las (the first number not taken).
        def self.Na__LazConvert__SuggestedName(laz_path)
            folder = File.dirname(laz_path)
            stem = File.basename(laz_path, '.*')
            plain = "#{stem}.las"
            return plain unless File.exist?(File.join(folder, plain))
            (1..999).each do |number|
                name = format('%s_FromLaz_%02d.las', stem, number)
                return name unless File.exist?(File.join(folder, name))
            end
            format('%s_FromLaz_%s.las', stem, Time.now.strftime('%Y%m%d-%H%M%S'))
        end

        # nil, or why this destination is refused.
        def self.Na__LazConvert__DestinationProblem(laz_path, dest_path)
            name = File.basename(dest_path)
            return 'Save the decompressed point cloud as a .las file.' unless File.extname(dest_path).casecmp('.las').zero?
            if File.expand_path(dest_path).casecmp(File.expand_path(laz_path)).zero?
                return "#{name} is the LAZ itself. The LAZ is never overwritten: choose a new name."
            end
            if File.exist?(dest_path)
                return "#{name} already exists. Nothing is ever overwritten: choose a new name, " \
                       'or import that file with Import LAS / LAZ if it is already a conversion of this LAZ.'
            end
            return "The folder #{File.dirname(dest_path)} does not exist." unless File.directory?(File.dirname(dest_path))
            nil
        end

        # Save As until the user picks an acceptable new file or cancels.
        def self.na_laz_ask_destination(laz_path)
            folder = File.dirname(laz_path)
            name = self.Na__LazConvert__SuggestedName(laz_path)
            20.times do
                path = UI.savepanel('Save the decompressed point cloud as a NEW LAS file', folder, name)
                return nil unless path
                path = path.tr('\\', '/')
                path += '.las' if File.extname(path).empty?
                problem = self.Na__LazConvert__DestinationProblem(laz_path, path)
                return path unless problem
                UI.messagebox(problem)
                folder = File.dirname(path) if File.directory?(File.dirname(path))
                name = self.Na__LazConvert__SuggestedName(File.join(folder, File.basename(laz_path)))
            end
            nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Report (rows added to the LAS import report)
    # -------------------------------------------------------------------------

        # { 'rows' => [[label, text], ...], 'boundsAgree' => bool, 'statusText', 'statusLevel' }
        def self.Na__LazConvert__Report(laz_path, poll)
            count  = Na__PerfStats.Na__Perf__Thousands(poll['pointCount'])
            spread = %w[X Y Z].flat_map do |axis|
                [(poll["headerMin#{axis}"] - poll["pointMin#{axis}"]).abs, (poll["headerMax#{axis}"] - poll["pointMax#{axis}"]).abs]
            end.max
            agree  = spread.zero?
            bounds = if agree
                         'Match the points exactly (kept as the LAZ states them)'
                     else
                         format("Kept exactly as the LAZ states them; they differ from the points' real extent by up to %.6g file units", spread)
                     end
            rows = [
                ['Converted from', format('%s (%.1f MB LAZ, decompressed by LASzip 3.5.0)', File.basename(laz_path), poll['sourceBytes'] / 1_000_000.0)],
                ['Conversion check', "All #{count} points read back exactly as stored in the LAZ"],
                ['Header bounds', bounds]
            ]
            dropped = poll['droppedRecords'].to_i
            rows << ['Left out', "#{dropped} COPC index record#{dropped == 1 ? '' : 's'} (they index the compressed file; no point data)"] if dropped > 0
            status = "Decompressed #{File.basename(laz_path)} losslessly: all #{count} points checked. Check the report and choose the units, then press Import."
            unless agree
                status = "Decompressed #{File.basename(laz_path)} losslessly, but its header bounds differ from the points' real extent " \
                         "(see Header bounds). The size shown below comes from the header. Check it, choose the units, then press Import."
            end
            { 'rows' => rows, 'boundsAgree' => agree, 'statusText' => status, 'statusLevel' => agree ? 'success' : 'warn' }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Job
    # -------------------------------------------------------------------------

        class Na__LazConvertJob

            NA_POLL_SECONDS = 0.1
            NA_PHASE_TEXT = {
                0 => 'Opening the LAZ file...',
                1 => 'Decompressing point records',
                2 => 'Checking every record of the new LAS against the LAZ',
                3 => 'Giving the new LAS its name...',
                4 => 'Done'
            }.freeze

            def initialize(laz_path, dest_path)
                @laz_path  = laz_path
                @dest_path = dest_path
                @handle    = nil
                @summary   = { 'kind' => 'laz' }
            end

            def na_title
                "Converting #{File.basename(@laz_path)} to LAS"
            end

            def na_step
                unless @handle
                    @handle = Na__NativeEngine.Na__Native__LazStart(@laz_path, @dest_path)
                    return { 'done' => false, 'status' => NA_PHASE_TEXT[0], 'percent' => 1.0, 'delay' => NA_POLL_SECONDS }
                end
                poll = Na__NativeEngine.Na__Native__LazPoll(@handle)
                return self.na_finish(poll) if poll['finished'].to_i == 1
                { 'done' => false, 'status' => self.na_status(poll), 'percent' => self.na_percent(poll), 'delay' => NA_POLL_SECONDS }
            end

            def na_cancel
                return unless @handle
                Na__NativeEngine.Na__Native__LazCancel(@handle)
                Na__NativeEngine.Na__Native__LazDestroy(@handle)   # joins, deletes the partial file
                @handle = nil
            end

            def na_cancel_message
                'Conversion cancelled. The partial file was deleted; the LAZ is untouched.'
            end

            def na_result_summary
                @summary
            end

            def na_finish(poll)
                if poll['failed'].to_i == 1 || poll['cancelled'].to_i == 1
                    message = Na__NativeEngine.Na__Native__LazError(@handle)
                    self.na_cancel
                    raise message.empty? ? 'The LAZ conversion stopped before it finished. Nothing was kept.' : message
                end
                notes = Na__NativeEngine.Na__Native__LazNotes(@handle)
                Na__NativeEngine.Na__Native__LazDestroy(@handle)
                @handle = nil
                Na__DebugTools.Na__Debug__Info("LAZ converted: #{@dest_path} (#{poll['pointCount'].to_i} points, " \
                                               "#{poll['convertMs'].round} ms + #{poll['checkMs'].round} ms check)#{notes.empty? ? '' : ". #{notes}"}")

                report = Na__LasImport.Na__LazConvert__Report(@laz_path, poll)
                @summary = { 'kind' => 'laz', 'lasPath' => @dest_path, 'totalPoints' => poll['pointCount'].to_i,
                             'boundsAgree' => report['boundsAgree'], 'nativeTotalMs' => poll['totalMs'].round(1) }
                dest = @dest_path
                # after the job has closed its overlay: the new LAS's own import report
                UI.start_timer(0.05, false) { Na__PointCloudViewer::Na__LasImport.Na__LasImport__Inspect(dest, report) }
                seconds = format('%.1f', poll['totalMs'] / 1000.0)
                { 'done' => true, 'percent' => 100.0,
                  'status' => "Converted #{File.basename(@laz_path)} to #{File.basename(dest)} in #{seconds} s " \
                              "(#{Na__PerfStats.Na__Perf__Thousands(poll['pointCount'])} points, every one checked)." }
            end

            def na_status(poll)
                phase = poll['phase'].to_i
                text = NA_PHASE_TEXT.fetch(phase, 'Working...')
                return text unless [1, 2].include?(phase) && poll['total'].to_i > 0
                "#{text}... #{Na__PerfStats.Na__Perf__Thousands(poll['done'])} of #{Na__PerfStats.Na__Perf__Thousands(poll['total'])}"
            end

            def na_percent(poll)
                fraction = poll['done'].to_f / [poll['total'].to_f, 1.0].max
                case poll['phase'].to_i
                when 1 then 2.0 + 78.0 * fraction
                when 2 then 80.0 + 18.0 * fraction
                when 3, 4 then 99.0
                else 1.0
                end.round(1)
            end

        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
