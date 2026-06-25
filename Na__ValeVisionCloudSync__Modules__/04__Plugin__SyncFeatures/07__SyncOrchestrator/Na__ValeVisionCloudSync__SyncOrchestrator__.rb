# =============================================================================
# VALEDESIGNSUITE - VALEVISION CLOUD SYNC ORCHESTRATOR
# =============================================================================
#
# FILE       : Na__ValeVisionCloudSync__SyncOrchestrator__.rb
# NAMESPACE  : Na__ValeVisionCloudSync::Na__SyncOrchestrator
# PURPOSE    : Coordinate the 4 Export-tab actions, shell to Python for R2
#              upload and Whitecardopedia mirroring, parse JSON report,
#              and drive the dialog's report panel and toasts.
# CREATED    : 25-Jun-2026
#
# DESCRIPTION:
# - Maps the 4 UI buttons to step scopes:
#     sync_all        -> images + camera + GLB + python sync
#     update_images   -> images only + python sync (images)
#     update_glb      -> GLB archive + GLB export only (no python)
#     update_cameras  -> camera capture + python sync (cameras)
# - Shells out to the Python single-project orchestrator when R2 upload is
#   required; parses its JSON stdout for the final dialog report.
# - Pushes progress via Na__DialogManager#na_push_status and
#   Na__DialogManager#na_push_report_step.
#
# =============================================================================

require 'json'
require 'open3'
require 'fileutils'

module Na__ValeVisionCloudSync
    module Na__SyncOrchestrator

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

        PYTHON_TIMEOUT_SECONDS  = 300  # <-- 5-minute timeout for the Python orchestrator
        SYNC_SCOPE_ALL          = 'sync_all'.freeze       # <-- Full sync (images + cameras + GLB + R2)
        SYNC_SCOPE_IMAGES       = 'update_images'.freeze  # <-- Images only + R2
        SYNC_SCOPE_GLB          = 'update_glb'.freeze     # <-- GLB archive + export only
        SYNC_SCOPE_CAMERAS      = 'update_cameras'.freeze # <-- Camera capture + R2

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Run Sync Action By Scope ID
        # ------------------------------------------------------------
        # scope_id matches the action IDs sent from UiBridge.js
        # Returns the final report hash
        # ---------------------------------------------------------------
        def self.Na__ValeVisionCloudSync__RunSyncAction(scope_id, dialog_manager)
            model        = Sketchup.active_model
            paths        = Na__ProjectPathMapper.Na__ValeVisionCloudSync__GetProjectPaths
            project_name = na_derive_project_name(model)
            report       = na_build_blank_report(scope_id, project_name)

            if paths.nil? || paths[:project_root].nil?
                dialog_manager.na_push_status('error', 'Project root path could not be determined. Check the Settings tab.')
                return report.merge(success: false, message: 'Project root not found.')
            end

            dialog_manager.na_push_status('running', "Starting: #{na_scope_label(scope_id)}…")

            case scope_id
            when SYNC_SCOPE_ALL
                report = na_run_full_sync(model, paths, project_name, dialog_manager, report)
            when SYNC_SCOPE_IMAGES
                report = na_run_images_sync(paths, project_name, dialog_manager, report)
            when SYNC_SCOPE_GLB
                report = na_run_glb_export(paths, project_name, dialog_manager, report)
            when SYNC_SCOPE_CAMERAS
                report = na_run_camera_sync(paths, project_name, dialog_manager, report)
            else
                report[:message] = "Unknown sync scope: #{scope_id}"
                report[:success] = false
            end

            final_status = report[:success] ? 'success' : 'error'
            dialog_manager.na_push_status(final_status, report[:message])
            dialog_manager.na_push_report(report)
            report
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Sync Scope Runners
# -----------------------------------------------------------------------------

        # FUNCTION | Full Sync (all steps)
        # ------------------------------------------------------------
        def self.na_run_full_sync(model, paths, project_name, dialog_manager, report)
            dialog_manager.na_push_status('running', 'Step 1/4 — Exporting scene images…')
            image_result = Na__SceneImageExporter.Na__ValeVisionCloudSync__ExportSceneImages(
                paths[:project_root]
            )
            report[:steps] << na_step_entry('Export Images', image_result)

            dialog_manager.na_push_status('running', 'Step 2/4 — Capturing scene cameras…')
            camera_result = Na__CameraDataCapture.Na__ValeVisionCloudSync__CaptureCameraData(
                paths[:project_root], model
            )
            report[:steps] << na_step_entry('Capture Camera Data', camera_result)

            dialog_manager.na_push_status('running', 'Step 3/4 — Archiving and exporting GLBs…')
            glb_result = Na__GlbExportBridge.Na__ValeVisionCloudSync__ExportGlbs(paths, project_name)
            report[:steps] << na_step_entry('Export GLB Models', glb_result)

            dialog_manager.na_push_status('running', 'Step 4/4 — Syncing to Cloudflare R2 and Whitecardopedia…')
            python_result = na_run_python_orchestrator(paths, 'all')
            report[:steps] << na_step_entry('Sync to R2 + Whitecardopedia', python_result)

            na_finalise_report(report)
        end

        # FUNCTION | Images Only Sync
        # ------------------------------------------------------------
        def self.na_run_images_sync(paths, project_name, dialog_manager, report)
            dialog_manager.na_push_status('running', 'Step 1/2 — Exporting scene images…')
            image_result = Na__SceneImageExporter.Na__ValeVisionCloudSync__ExportSceneImages(
                paths[:project_root]
            )
            report[:steps] << na_step_entry('Export Images', image_result)

            dialog_manager.na_push_status('running', 'Step 2/2 — Syncing images to R2 + Whitecardopedia…')
            python_result = na_run_python_orchestrator(paths, 'images')
            report[:steps] << na_step_entry('Sync Images to R2 + Whitecardopedia', python_result)

            na_finalise_report(report)
        end

        # FUNCTION | GLB Export Only (no Python/R2 step)
        # ------------------------------------------------------------
        def self.na_run_glb_export(paths, project_name, dialog_manager, report)
            dialog_manager.na_push_status('running', 'Archiving existing GLBs and exporting…')
            glb_result = Na__GlbExportBridge.Na__ValeVisionCloudSync__ExportGlbs(paths, project_name)
            report[:steps] << na_step_entry('Export GLB Models', glb_result)
            na_finalise_report(report)
        end

        # FUNCTION | Camera Capture + R2 Sync
        # ------------------------------------------------------------
        def self.na_run_camera_sync(paths, project_name, dialog_manager, report)
            model = Sketchup.active_model

            dialog_manager.na_push_status('running', 'Step 1/2 — Capturing scene cameras…')
            camera_result = Na__CameraDataCapture.Na__ValeVisionCloudSync__CaptureCameraData(
                paths[:project_root], model
            )
            report[:steps] << na_step_entry('Capture Camera Data', camera_result)

            dialog_manager.na_push_status('running', 'Step 2/2 — Syncing camera data to R2 + Whitecardopedia…')
            python_result = na_run_python_orchestrator(paths, 'cameras')
            report[:steps] << na_step_entry('Sync Camera Data to R2 + Whitecardopedia', python_result)

            na_finalise_report(report)
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Python Orchestrator Shell-Out
# -----------------------------------------------------------------------------

        # FUNCTION | Shell To The Python Single-Project Orchestrator
        # ------------------------------------------------------------
        def self.na_run_python_orchestrator(paths, action)
            config          = Na__ConfigLoader.Na__ValeVisionCloudSync__GetConfig
            wcp_root        = config.dig('python', 'whitecardopedia_root') || ''
            script_rel      = config.dig('python', 'orchestrator_script') || ''
            script_path     = File.join(wcp_root, script_rel)

            unless File.exist?(script_path)
                return {
                    success: false,
                    message: "Python orchestrator not found at: #{script_path}"
                }
            end

            project_root = paths[:project_root].to_s
            project_dir  = File.basename(project_root)
            year_folder  = na_derive_year_folder(project_root)

            cmd = [
                'python',
                script_path.gsub('/', File::ALT_SEPARATOR || '/'),
                '--project', project_dir,
                '--year',    year_folder,
                '--action',  action,
                '--json'
            ]

            na_execute_python(cmd, paths)
        end

        # HELPER FUNCTION | Execute Python Command And Parse JSON Response
        # ---------------------------------------------------------------
        def self.na_execute_python(cmd, paths)
            stdout_str, stderr_str, status = Open3.capture3(*cmd, chdir: File.dirname(cmd[1]))

            if status.success?
                na_parse_python_json_report(stdout_str)
            else
                {
                    success: false,
                    message: "Python orchestrator exited with code #{status.exitstatus}. #{stderr_str.strip}"
                }
            end
        rescue => error
            { success: false, message: "Failed to run Python orchestrator: #{error.message}" }
        end

        # HELPER FUNCTION | Parse Python Stdout JSON Report
        # ---------------------------------------------------------------
        def self.na_parse_python_json_report(stdout_str)
            last_json_line = stdout_str.lines.reverse.find { |line| line.strip.start_with?('{') }
            return { success: false, message: 'No JSON report from Python orchestrator.' } unless last_json_line

            parsed = JSON.parse(last_json_line.strip)
            {
                success:        parsed['success'] == true,
                message:        parsed['message']  || 'Python sync complete.',
                uploaded_count: parsed['uploaded'] || 0,
                mirrored_count: parsed['mirrored'] || 0,
                elapsed_ms:     parsed['elapsed_ms']
            }
        rescue JSON::ParserError => error
            { success: false, message: "Could not parse Python report: #{error.message}" }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Report Builders
# -----------------------------------------------------------------------------

        def self.na_build_blank_report(scope_id, project_name)
            {
                scope:        scope_id,
                project_name: project_name,
                started_at:   Time.now.strftime('%d-%b-%Y at %H:%M'),
                steps:        [],
                success:      false,
                message:      ''
            }
        end

        def self.na_step_entry(label, result)
            {
                label:   label,
                success: result[:success] == true,
                message: result[:message].to_s
            }
        end

        def self.na_finalise_report(report)
            all_passed    = report[:steps].all? { |s| s[:success] }
            report[:success] = all_passed
            report[:message] = all_passed ?
                "#{na_scope_label(report[:scope])} completed successfully." :
                "#{na_scope_label(report[:scope])} completed with errors — see step details."
            report
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Helpers
# -----------------------------------------------------------------------------

        def self.na_scope_label(scope_id)
            labels = {
                SYNC_SCOPE_ALL     => 'Sync Project To ValeVision 3D',
                SYNC_SCOPE_IMAGES  => 'Update Images For ValeVision 3D',
                SYNC_SCOPE_GLB     => 'Update GLB Models For ValeVision 3D',
                SYNC_SCOPE_CAMERAS => 'Update Camera Data For ValeVision 3D'
            }
            labels[scope_id] || scope_id
        end

        def self.na_derive_project_name(model)
            model_path = model&.path.to_s
            return 'UnknownProject' if model_path.empty?

            parts = model_path.gsub('\\', '/').split('/')
            sketchup_idx = parts.rindex { |p| p.downcase.include?('sketchup') || p.downcase.include?('02__') }
            return File.basename(model_path, '.skp') unless sketchup_idx && sketchup_idx > 0

            parts[sketchup_idx - 1]
        end

        def self.na_derive_year_folder(project_root)
            parts   = project_root.gsub('\\', '/').split('/')
            year_rx = /^\d{4}$/
            year    = parts.reverse.find { |p| p.match?(year_rx) }
            year || Time.now.year.to_s
        end

# endregion -------------------------------------------------------------------

    end # module Na__SyncOrchestrator
end # module Na__ValeVisionCloudSync

# =============================================================================
# END OF FILE
# =============================================================================
