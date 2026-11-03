# =============================================================================
# NA PAINTERLYNPR ASSETS - NPR EXPORT - JOBS
# =============================================================================
#
# FILE       : Na__PainterlyAssets__NprExport__Jobs__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__NprExport
# PURPOSE    : One export, from Export pressed to the files in their folder:
#              the pictures planned (the current view, or the ticked scenes,
#              each with its camera taken now), the NPR Viewport readied, the
#              job handed to its page, each picture moved from the server's
#              outbox to its name, and the report.
# CREATED    : 01-Nov-2026 (v0.3.0)
#
# DESCRIPTION:
# - THE PICTURES ARE THE ENGINE'S, drawn in the NPR Viewport's own engine with
#   its scene and its look (its page's HostExport), so the viewport opens when
#   it is not open, and the job waits until it has the model's scene.
# - EACH CAMERA IS TAKEN WHEN EXPORT IS PRESSED (a snapshot of SketchUp's view,
#   or of each scene's own camera, never by selecting a scene: SketchUp's view
#   is never moved), and turned into the engine's camera once the scene's
#   placement is known. A scene that keeps no camera is drawn from the view's.
# - WHAT IS DRAWN is the model as the NPR Viewport has it: a scene's own
#   hidden tags and objects are not applied (the GLB cache is the whole model).
# - THE VIEWPORT HOLDS STILL while the job runs (no camera, no new scene),
#   then follows SketchUp again.
# - NOTHING IS WRITTEN BUT THE PICTURES, each to the name planned for it (a
#   number added when one is there, unless Replace was chosen). A picture that
#   could not be drawn or written is in the report with the reason; the rest
#   still land.
#
# =============================================================================

require 'fileutils'
require 'securerandom'

module Na__PainterlyAssets
    module Na__NprExport

    # -------------------------------------------------------------------------
    # REGION | Constants and State
    # -------------------------------------------------------------------------

        NA_FILE_PATTERN  = /\A[0-9a-f]{12}__[0-9]{1,4}\.(png|jpg|pdf)\z/.freeze           unless defined?(NA_FILE_PATTERN)
        NA_CALIBRATIONS  = %w[calibration:pdf:300 calibration:pdf:600 calibration:png:300].freeze unless defined?(NA_CALIBRATIONS)
        NA_POLL_SECONDS  = 0.5                                                             unless defined?(NA_POLL_SECONDS)

        @na_job = nil unless defined?(@na_job)                                             # <-- The export running (one at a time)

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        # FUNCTION | Start an Export of the Model's Pictures (or the Pen Calibration Sheet)
        # ------------------------------------------------------------
        # @param calibration [String, nil] one of NA_CALIBRATIONS: the engine's own sheet, named by the engine
        # @return [String, nil] why it could not start, or nil (started)
        def self.Na__Export__Start(model, settings, calibration = nil)
            return 'An export is already running. Cancel it, or wait for its report.' if @na_job
            return 'There is no model.' unless model
            settings = Na__NprSettings.Na__Settings__NormaliseExport(settings)
            folder   = Na__NprExportNaming.Na__Naming__Folder(model.path, settings)
            return folder['problem'] if folder['problem']
            items, problem = calibration ? self.na_calibration_items(calibration) : self.na_items(model, settings)
            return problem if problem
            taken = {}
            problem = self.na_plan_targets(model, settings, folder['path'], items, taken)
            return problem if problem
            unless folder['exists']
                begin
                    FileUtils.mkdir_p(folder['path'])
                rescue SystemCallError => error
                    return "The folder for the pictures could not be made (#{folder['path']}): #{error.message}"
                end
            end
            @na_job = {
                'id'       => SecureRandom.hex(6),
                'model'    => model,
                'settings' => settings,
                'folder'   => folder['path'],
                'items'    => items,
                'taken'    => taken,
                'results'  => {},
                'state'    => 'waiting',
                'started'  => self.na_now,
                'news'     => self.na_now,
                'asked'    => false,
                'timer'    => nil
            }
            self.na_clean_outbox(nil)
            self.na_progress('Getting the NPR Viewport ready to draw...', 'busy')
            self.na_begin_waiting(@na_job)
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Cancel: before the drawing starts at once, during it after the picture being drawn
        # ------------------------------------------------------------
        def self.Na__Export__Cancel
            job = @na_job
            return unless job
            return self.Na__Export__Finish(job, nil, cancelled: true) unless job['state'] == 'sent'
            job['cancelling'] = true
            Na__NprWindows.Na__Windows__Send('viewport', 'exportCancel', { 'Job' => job['id'] })
            self.na_progress('Stopping after the picture being drawn...', 'busy')
        end
        # ---------------------------------------------------------------

        def self.Na__Export__Running?
            @na_job ? true : false
        end

        # FUNCTION | The Viewport Drew One Picture (or could not): move it to its name
        # ------------------------------------------------------------
        def self.Na__Export__ItemDone(payload)
            job = @na_job
            return unless job && payload['Job'].to_s == job['id']
            item = job['items'].find { |candidate| candidate['Id'] == payload['Id'].to_i }
            return unless item && !job['results'].key?(item['Id'])
            job['news'] = self.na_now
            job['results'][item['Id']] = payload['Ok'] ? self.na_receive(job, item, payload) :
                                                         { 'ok' => false, 'label' => item['Label'], 'message' => payload['Message'].to_s }
            done = job['results'].length
            self.na_progress("#{done} of #{job['items'].length} drawn#{done < job['items'].length ? '...' : '.'}", done < job['items'].length ? 'busy' : 'info')
            self.Na__Export__Finish(job, nil) if done == job['items'].length
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Viewport Finished the Job (all drawn, cancelled, or it could not)
        # ------------------------------------------------------------
        def self.Na__Export__JobDone(payload)
            job = @na_job
            return unless job && payload['Job'].to_s == job['id']
            problem = payload['Message'].to_s.empty? ? nil : "The NPR Viewport could not draw the export: #{payload['Message']}."
            self.Na__Export__Finish(job, problem, cancelled: payload['Cancelled'] == true)
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Viewport Closed or Reloaded: a job it was drawing has gone with it
        # ------------------------------------------------------------
        def self.Na__Export__ViewportClosed
            job = @na_job
            self.Na__Export__Finish(job, 'The NPR Viewport was closed, so the export stopped.') if job
        end

        def self.Na__Export__ViewportReady(_info)
            job = @na_job
            self.Na__Export__Finish(job, 'The NPR Viewport reloaded while it was drawing, so the export stopped.') if job && job['state'] == 'sent'
            self.Na__Export__PushState if self.Na__Export__WindowVisible?
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Job Ends: the viewport follows SketchUp again, the report, the folder
        # ------------------------------------------------------------
        def self.Na__Export__Finish(job, problem, cancelled: false)
            return unless job && @na_job.equal?(job)
            @na_job = nil
            UI.stop_timer(job['timer']) if job['timer']
            Na__LiveSync.Na__Live__Hold(false) if job['state'] == 'sent'
            files  = job['results'].values.select { |result| result['ok'] }
            failed = job['items'].map do |item|
                result = job['results'][item['Id']]
                next nil if result && result['ok']
                { 'label' => item['Label'], 'message' => result ? result['message'] : (cancelled ? 'Cancelled before it was drawn.' : 'Not drawn.') }
            end.compact
            report = {
                'Ok'        => problem.nil? && !cancelled && failed.empty?,
                'Cancelled' => cancelled,
                'Problem'   => problem,
                'Folder'    => job['folder'],
                'Files'     => files.map { |file| file.reject { |key, _| key == 'ok' } },
                'Failed'    => failed,
                'Seconds'   => (self.na_now - job['started']).round(1)
            }
            self.na_clean_outbox(job['id'])
            self.na_send_window('report', report)
            self.na_open_after(job, files)
            Na__DebugTools.Na__Debug__Info("NPR Export: #{files.length} of #{job['items'].length} written to #{job['folder']}#{problem ? " (#{problem})" : ''}.")
            report
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Planning the Pictures
    # -------------------------------------------------------------------------

        # The current view, or the ticked scenes in the model's own order: [items, problem]
        def self.na_items(model, settings)
            view   = model.active_view
            aspect = Na__CameraSync.Na__Camera__ViewAspect(view)
            dpi    = settings['dpi']
            base   = {
                'Which'   => settings['format'] == 'pdf' ? "pdf:#{dpi}" : "dpi:#{dpi}",
                'Format'  => settings['format'],
                'Quality' => (settings['jpegQuality'] / 100.0).round(2),
                'Dpi'     => dpi
            }
            if settings['views'] == 'scenes'
                pages = self.Na__Export__TickedPages(model, settings['scenes'])
                return [nil, 'Tick at least one scene to export, or choose The Current SketchUp View.'] if pages.empty?
                items = pages.each_with_index.map do |page, index|
                    camera = page.use_camera? ? page.camera : view.camera                     # <-- A scene that keeps no camera shows the view's
                    base.merge('Id' => index + 1, 'Label' => page.name.to_s, 'View' => page.name.to_s,
                               'Snapshot' => Na__CameraSync.Na__Camera__Snapshot(camera, aspect))
                end
                return [items, nil]
            end
            [[base.merge('Id' => 1, 'Label' => 'The current SketchUp view', 'View' => 'CurrentView',
                         'Snapshot' => Na__CameraSync.Na__Camera__Snapshot(view.camera, aspect))], nil]
        end

        def self.na_calibration_items(which)
            return [nil, 'That is not one of the engine\'s calibration sheets.'] unless NA_CALIBRATIONS.include?(which.to_s)
            format = which.to_s.split(':')[1]
            [[{ 'Id' => 1, 'Label' => 'The pen calibration sheet', 'Which' => which.to_s, 'Format' => format,
                'Quality' => 1.0, 'Dpi' => which.to_s.split(':')[2].to_i, 'Snapshot' => nil, 'Calibration' => true }], nil]
        end

        # FUNCTION | The Scenes Ticked: by persistent id, else by name (a scene made again), in the model's order
        # ------------------------------------------------------------
        def self.Na__Export__TickedPages(model, scenes)
            pages = model.pages.to_a
            pids  = scenes.map { |scene| scene['pid'].to_i }
            found = pages.select { |page| pids.include?(page.persistent_id.to_i) }
            lost  = scenes.reject { |scene| pages.any? { |page| page.persistent_id.to_i == scene['pid'].to_i } }.map { |scene| scene['name'].to_s }
            found += pages.select { |page| !found.include?(page) && lost.include?(page.name.to_s) }
            pages.select { |page| found.include?(page) }
        end
        # ---------------------------------------------------------------

        # Every picture's name decided now (a calibration sheet's when it arrives, by the engine's own name)
        def self.na_plan_targets(model, settings, folder, items, taken)
            seed    = self.na_seed(model)
            replace = settings['ifExists'] == 'replace'
            limit   = Na__PathResolver.Na__Paths__Limit
            title   = model.title.to_s.empty? ? 'Untitled' : model.title.to_s
            items.each do |item|
                next if item['Calibration']
                values = Na__NprExportNaming.Na__Naming__Values(title, item['View'], item['Dpi'], seed)
                name   = Na__NprExportNaming.Na__Naming__FileName(settings['fileName'], values, settings['format'])
                target = Na__NprExportNaming.Na__Naming__Target(folder, name, taken, replace)
                return "Every numbered name for #{name} is taken in #{folder}." unless target
                return "#{File.basename(target)} would be #{target.length} characters with its folder, past the #{limit} SketchUp can write. Shorten the file name, or choose a shorter folder." if target.length > limit
                item['Target'] = target
            end
            nil
        end

        def self.na_seed(model)
            settings = Na__NprSettings.Na__Settings__Look(model)['settings']
            settings.is_a?(Hash) ? settings['Seed'] : nil
        rescue StandardError
            nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Waiting for the Viewport, Then Handing It the Job
    # -------------------------------------------------------------------------

        def self.na_begin_waiting(job)
            self.na_defer { Na__NprWindows.Na__Windows__Open('viewport') } unless Na__NprWindows.Na__Windows__Visible?('viewport')
            if Na__LocalServer.Na__Server__Running? && !Na__LocalServer.Na__Server__Current?
                Na__NprWindows.Na__Windows__Restart                                        # <-- A server from before 0.3.0 cannot take the pictures
            end
            job['timer'] = UI.start_timer(NA_POLL_SECONDS, true) { Na__PainterlyAssets::Na__NprExport.na_tick }
        end

        def self.na_tick
            job = @na_job
            return unless job
            return if job['ticking']
            job['ticking'] = true
            begin
                job['state'] == 'waiting' ? self.na_tick_waiting(job) : self.na_tick_sent(job)
            ensure
                job['ticking'] = false
            end
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('NPR Export failed while it waited.', error)
            self.Na__Export__Finish(@na_job, "The export stopped: #{error.message}") if @na_job
        end

        def self.na_tick_waiting(job)
            model = job['model']
            return self.Na__Export__Finish(job, 'Another model came to the front, so the export stopped.') unless model.equal?(Sketchup.active_model)
            if Na__LiveSync.Na__Live__SceneReady?(model) && Na__LocalServer.Na__Server__Current?
                return self.na_send(job)
            end
            if Na__NprWindows.Na__Windows__Ready?('viewport') && !job['asked']
                job['asked'] = true
                Na__LiveSync.Na__Live__EnsureScene(model)
            end
            limit = Na__ConfigLoader.Na__Config__GetOr(300, 'nprExport', 'readySeconds').to_f
            waited = self.na_now - job['started']
            if waited > limit
                reason = model.active_path ? 'a group or component is open (the NPR Viewport gets the model when it is closed)' : 'the NPR Viewport did not get the model in time'
                return self.Na__Export__Finish(job, "The export did not start: #{reason}.")
            end
            self.na_progress('Close the open group or component: the NPR Viewport gets the model when it is closed.', 'warn') if model.active_path && !job['saidPath']
            job['saidPath'] = true if model.active_path
        end

        def self.na_tick_sent(job)
            limit = Na__ConfigLoader.Na__Config__GetOr(600, 'nprExport', 'itemTimeoutSeconds').to_f
            return unless self.na_now - job['news'] > limit
            self.Na__Export__Finish(job, "The NPR Viewport has said nothing for #{limit.round} seconds, so the export stopped. A lower resolution needs less of the graphics card.")
        end

        def self.na_send(job)
            placement = Na__LiveSync.Na__Live__Placement(job['model'])
            items = job['items'].map do |item|
                camera = item['Snapshot'] ? Na__CameraSync.Na__Camera__FromSnapshot(item['Snapshot'], placement) : nil
                { 'Id' => item['Id'], 'Label' => item['Label'], 'Which' => item['Which'], 'Format' => item['Format'],
                  'Quality' => item['Quality'], 'Dpi' => item['Dpi'], 'Camera' => camera }
            end
            Na__LiveSync.Na__Live__Hold(true)
            job['state'] = 'sent'
            job['news']  = self.na_now
            message = { 'Job' => job['id'], 'Token' => Na__LocalServer.Na__Server__Token, 'Upload' => '/__na/export', 'Items' => items }
            return self.Na__Export__Finish(job, 'The NPR Viewport could not be given the export.') unless Na__NprWindows.Na__Windows__Send('viewport', 'export', message)
            self.na_progress("Drawing #{items.length == 1 ? 'the picture' : "#{items.length} pictures"} at #{job['items'].first['Dpi']} dpi...", 'busy')
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | A Picture Arrives
    # -------------------------------------------------------------------------

        # From the server's outbox to its name: { 'ok', 'label', 'name', 'path', 'bytes', 'width', 'height', 'seconds' }
        def self.na_receive(job, item, payload)
            file = payload['File'].to_s
            unless file.match?(NA_FILE_PATTERN) && file.start_with?("#{job['id']}__")
                return { 'ok' => false, 'label' => item['Label'], 'message' => 'The picture came back under a name this export did not give.' }
            end
            source = File.join(Na__LocalServer.Na__Server__Outbox, file)
            return { 'ok' => false, 'label' => item['Label'], 'message' => 'The picture did not arrive in the outbox.' } unless File.file?(source)
            replace = job['settings']['ifExists'] == 'replace'
            target  = item['Calibration'] ? self.na_calibration_target(job, payload, file) : item['Target']
            if target && File.exist?(target) && !replace                                     # <-- Something arrived there since Export was pressed
                target = Na__NprExportNaming.Na__Naming__Target(File.dirname(target), File.basename(target), job['taken'], false)
            end
            return { 'ok' => false, 'label' => item['Label'], 'message' => 'Every numbered name for it is taken.' } unless target
            FileUtils.mkdir_p(File.dirname(target))
            File.delete(target) if replace && File.file?(target)                           # <-- Replace was chosen in NPR Export
            FileUtils.mv(source, target)
            {
                'ok'      => true,
                'label'   => item['Label'],
                'name'    => File.basename(target),
                'path'    => target,
                'bytes'   => File.size(target),
                'width'   => payload['Width'].to_i,
                'height'  => payload['Height'].to_i,
                'seconds' => payload['Seconds'].to_f
            }
        rescue SystemCallError => error
            { 'ok' => false, 'label' => item['Label'], 'message' => "It could not be written to #{target}: #{error.message}" }
        end

        # The engine's own name for its sheet, in the export's folder, with this file's extension
        def self.na_calibration_target(job, payload, file)
            stem = Na__NprExportNaming.Na__Naming__Safe(File.basename(payload['EngineName'].to_s, '.*'))
            stem = 'PainterlyNPR__PenCalibration__' if stem.gsub('_', '').empty?
            Na__NprExportNaming.Na__Naming__Target(job['folder'], "#{stem}#{File.extname(file)}", job['taken'], job['settings']['ifExists'] == 'replace')
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals
    # -------------------------------------------------------------------------

        # The folder (and the pictures, when asked) shown once the job is done
        def self.na_open_after(job, files)
            return if files.empty?
            settings = job['settings']
            self.na_defer { UI.openURL(Na__PathResolver.Na__Paths__FileUri(job['folder'])) } if settings['openFolder']
            files.first(8).each { |file| self.na_defer { UI.openURL(Na__PathResolver.Na__Paths__FileUri(file['path'])) } } if settings['openFile']
        end

        # A job's leftovers, or (nil) anything over a day old
        def self.na_clean_outbox(job_id)
            outbox = Na__LocalServer.Na__Server__Outbox
            return unless File.directory?(outbox)
            cutoff = Time.now - 86_400
            Dir.glob(File.join(outbox, '*')).each do |path|
                name = File.basename(path)
                stale = job_id ? name.start_with?("#{job_id}__") : File.mtime(path) < cutoff
                File.delete(path) if stale && File.file?(path)
            end
        rescue SystemCallError => error
            Na__DebugTools.Na__Debug__Warn("NPR Export's outbox could not be tidied: #{error.message}")
        end

        def self.na_now
            Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

        def self.na_defer(&block)
            fired = false
            UI.start_timer(0.1, false) do                                                  # <-- Never a window or a panel inside another window's callback
                next if fired
                fired = true
                begin
                    block.call
                rescue StandardError => error
                    Na__PainterlyAssets::Na__DebugTools.Na__Debug__Error('An NPR Export step failed.', error)
                end
            end
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
