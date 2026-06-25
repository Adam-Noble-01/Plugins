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
# - Maps the 4 UI buttons to step scopes (IDs match UiLayout onclick calls):
#     sync_project       -> images + camera + GLB + python sync
#     update_images      -> images only + python sync (images)
#     update_glb_models  -> GLB archive + GLB export + python GLB upload to R2
#     update_camera_data -> camera capture + python sync (cameras)
# - Shells out to the Python single-project orchestrator when R2 upload is
#   required; parses its JSON stdout for the final dialog report.
# - Pushes progress via Na__DialogManager#na_push_status and
#   Na__DialogManager#na_push_report_step.
#
# =============================================================================

require 'json'
require 'open3'
require 'fileutils'
require 'tmpdir'

module Na__ValeVisionCloudSync
    module Na__SyncOrchestrator

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

        PYTHON_TIMEOUT_SECONDS  = 300  # <-- 5-minute timeout for the Python orchestrator
        SYNC_SCOPE_ALL          = 'sync_project'.freeze       # <-- Full sync (images + cameras + GLB + R2) [matches UI button]
        SYNC_SCOPE_IMAGES       = 'update_images'.freeze      # <-- Images only + R2 [matches UI button]
        SYNC_SCOPE_GLB          = 'update_glb_models'.freeze  # <-- GLB archive + export only [matches UI button]
        SYNC_SCOPE_CAMERAS      = 'update_camera_data'.freeze # <-- Camera capture + R2 [matches UI button]

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
            na_append_python_steps(report, python_result)

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
            na_append_python_steps(report, python_result)

            na_finalise_report(report)
        end

        # FUNCTION | GLB Export + R2 Upload
        # ------------------------------------------------------------
        def self.na_run_glb_export(paths, project_name, dialog_manager, report)
            dialog_manager.na_push_status('running', 'Step 1/2 — Archiving existing GLBs and exporting…')
            glb_result = Na__GlbExportBridge.Na__ValeVisionCloudSync__ExportGlbs(paths, project_name)
            report[:steps] << na_step_entry('Export GLB Models', glb_result)

            dialog_manager.na_push_status('running', 'Step 2/2 — Uploading GLBs to Cloudflare R2…')
            python_result = na_run_python_orchestrator(paths, 'glb')   # <-- Mirror fresh GLBs to R2 + refresh index
            na_append_python_steps(report, python_result)

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
            na_append_python_steps(report, python_result)

            na_finalise_report(report)
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Python Orchestrator Shell-Out
# -----------------------------------------------------------------------------

        # FUNCTION | Shell To The Python Single-Project Orchestrator
        # ------------------------------------------------------------
        def self.na_run_python_orchestrator(paths, action)
            py_config       = Na__ConfigLoader.Na__ValeVisionCloudSync__PythonConfig
            wcp_root        = py_config['whitecardopedia_root'].to_s
            script_rel      = py_config['orchestrator_script'].to_s
            script_path     = File.join(wcp_root, script_rel).tr('\\', '/')  # <-- Forward slashes; Open3 accepts on Win

            unless File.exist?(script_path)
                return {
                    success: false,
                    message: "Python orchestrator script not found at:\n#{script_path}"
                }
            end

            project_root = paths[:project_root].to_s
            project_dir  = File.basename(project_root)
            year_folder  = na_derive_year_folder(project_root)

            resolution  = na_resolve_python_executable(py_config)           # <-- {command:, note:, trusted:}
            report_file = na_build_report_file_path                         # <-- Robust file channel (GUI host can't reliably capture stdout)
            script_args = [
                '--project',     project_dir,
                '--year',        year_folder,
                '--action',      action,
                '--json',
                '--report-file', report_file
            ]

            result = na_execute_python(resolution[:command], script_path, script_args, report_file)
            result[:interpreter_note] = resolution[:note]                   # <-- Surfaced as its own report line
            result[:interpreter_ok]   = resolution[:trusted]
            result
        end

        # HELPER FUNCTION | Build A Per-Run JSON Report File Path
        # ---------------------------------------------------------------
        # The Python orchestrator writes its final report here. Reading a file
        # avoids the SketchUp GUI-host pipe-capture problem where Open3 returns
        # empty stdout/stderr even though the child process printed normally.
        # ---------------------------------------------------------------
        def self.na_build_report_file_path
            dir = na_python_log_dir || Dir.tmpdir
            File.join(dir, "Na__ValeVisionCloudSync__Report__#{Time.now.strftime('%Y%m%d_%H%M%S_%L')}.json").tr('\\', '/')
        end

        # HELPER FUNCTION | Resolve A Real Python Interpreter
        # ---------------------------------------------------------------
        # SketchUp's child-process PATH can resolve bare `python` to the Windows
        # Store app-execution stub, which prints an install notice and exits 0
        # with no JSON. The most reliable dodge is to use an ABSOLUTE python.exe
        # we can confirm on disk (the Store stub lives under WindowsApps, never in
        # a real install dir), without depending on a child-process probe that can
        # itself misbehave inside SketchUp. Resolution order:
        #   1. Config override `python_executable` (absolute path, used as-is).
        #   2. Absolute python.exe discovered on disk via File.exist? (TRUSTED).
        #   3. PATH launchers (py -3 / python3 / python) confirmed by a probe.
        #   4. Bare `python` as a last resort (may be the Store stub).
        # Returns { command: [...], note: 'human readable', trusted: true/false }.
        # ---------------------------------------------------------------
        def self.na_resolve_python_executable(py_config)
            configured = py_config['python_executable'].to_s.strip
            unless configured.empty?
                if File.exist?(configured)
                    return { command: [configured], note: "Config override (verified on disk): #{configured}", trusted: true }
                end
                return { command: [configured], note: "Config override (NOT found on disk — trying anyway): #{configured}", trusted: false }
            end

            absolute = na_discover_absolute_python_exes
            unless absolute.empty?
                return { command: [absolute.first], note: "Absolute interpreter (verified on disk): #{absolute.first}", trusted: true }
            end

            [['py', '-3'], ['python3'], ['python']].each do |candidate|
                next unless na_python_candidate_works?(candidate)
                return { command: candidate, note: "PATH launcher (probe passed): #{candidate.join(' ')}", trusted: true }
            end

            {
                command: ['python'],
                note:    'No real interpreter found. Falling back to bare "python" — if this is the Windows Store stub it will produce empty output. Set "python_executable" in the plugin AppConfig to a full python.exe path.',
                trusted: false
            }
        end

        # HELPER FUNCTION | Discover Absolute python.exe Paths On Disk
        # ---------------------------------------------------------------
        # Globs the common real install locations. These are trusted without a
        # probe because the Store stub never lives in any of them.
        # ---------------------------------------------------------------
        def self.na_discover_absolute_python_exes
            found     = []
            local_app = ENV['LOCALAPPDATA'].to_s.tr('\\', '/')
            patterns  = []
            patterns << "#{local_app}/Programs/Python/Python3*/python.exe" unless local_app.empty?
            patterns << 'C:/Python3*/python.exe'
            patterns << 'C:/Program Files/Python3*/python.exe'
            patterns << 'C:/Program Files (x86)/Python3*/python.exe'

            patterns.each do |pattern|
                Dir.glob(pattern).sort.reverse.each do |exe|             # <-- Newest Python3x first
                    normalised = exe.tr('\\', '/')
                    found << normalised if File.exist?(normalised) && !found.include?(normalised)
                end
            end
            found
        rescue
            []
        end

        # HELPER FUNCTION | Probe Whether A PATH Launcher Actually Runs
        # ---------------------------------------------------------------
        # Asks the candidate for sys.executable; rejects empty output and the
        # WindowsApps Store stub. Only used for PATH launchers (not absolutes).
        # ---------------------------------------------------------------
        def self.na_python_candidate_works?(candidate)
            out, _err, status = Open3.capture3(na_build_sanitized_python_env, *candidate, '-c', 'import sys; sys.stdout.write(sys.executable or "")')
            real_exe = out.to_s.strip
            return false unless status.success?
            return false if real_exe.empty?
            return false if real_exe.tr('\\', '/').downcase.include?('/windowsapps/')  # <-- Reject Store stub
            true
        rescue
            false  # <-- ENOENT etc. → candidate unavailable
        end

        # HELPER FUNCTION | Execute Python Command And Parse JSON Response
        # ---------------------------------------------------------------
        # Always writes a full run log to disk and, on any non-JSON outcome,
        # returns a multi-line diagnostic so the dialog explains exactly what
        # happened (interpreter, command, exit code, stdout/stderr tails, log).
        # ---------------------------------------------------------------
        def self.na_execute_python(interpreter, script_path, script_args, report_file = nil)
            cmd         = interpreter + [script_path] + script_args
            cmd_display = cmd.join(' ')

            child_env   = na_build_sanitized_python_env  # <-- Strip SketchUp's embedded-Python poisoners
            inherited   = na_describe_inherited_python_env # <-- Record what SketchUp passed (for diagnostics)

            stdout_str, stderr_str, status = Open3.capture3(child_env, *cmd, chdir: File.dirname(script_path))
            exit_code   = status.respond_to?(:exitstatus) ? status.exitstatus : nil

            report_json = na_read_report_file_raw(report_file)                   # <-- Preferred channel (survives empty stdout)
            parsed      = na_read_report_file(report_file) ||                     # <-- 1) file channel
                          na_parse_python_json_report(stdout_str)                 # <-- 2) stdout fallback

            debug_log   = na_write_python_debug_log(
                cmd_display, exit_code, stdout_str, stderr_str, inherited, report_file, report_json, !parsed.nil?
            )

            if parsed
                parsed[:debug_log] = debug_log
                return parsed
            end

            {
                success:   false,
                message:   na_build_python_failure_message(cmd_display, exit_code, stdout_str, stderr_str, report_file, debug_log),
                debug_log: debug_log
            }
        rescue => error
            {
                success: false,
                message: "Failed to launch Python (#{error.class}): #{error.message}\nCommand: #{(interpreter + [script_path] + script_args).join(' ')}"
            }
        end

        # HELPER FUNCTION | Read The Raw JSON Report File Written By Python
        # ---------------------------------------------------------------
        def self.na_read_report_file_raw(report_file)
            return nil if report_file.nil? || report_file.to_s.empty?
            return nil unless File.exist?(report_file)
            File.read(report_file)
        rescue
            nil
        end

        # HELPER FUNCTION | Parse The Python Report File (nil When Absent/Invalid)
        # ---------------------------------------------------------------
        def self.na_read_report_file(report_file)
            raw = na_read_report_file_raw(report_file)
            return nil if raw.nil? || raw.strip.empty?
            na_normalise_python_report(JSON.parse(raw))
        rescue JSON::ParserError
            nil
        end

        # HELPER FUNCTION | Build A Sanitized Environment For The External Python
        # ---------------------------------------------------------------
        # SketchUp 2026 ships its own embedded CPython and exports PYTHONHOME /
        # PYTHONPATH (and friends) into the process environment. Those are
        # inherited by any child process, which poisons an external python.exe
        # (it tries to use SketchUp's stdlib) — the classic "exit 0, empty
        # stdout/stderr" symptom. Open3 treats a nil value as "delete this var",
        # so we strip the poisoners and force clean UTF-8, unbuffered output.
        # ---------------------------------------------------------------
        def self.na_build_sanitized_python_env
            {
                'PYTHONHOME'       => nil,    # <-- Do NOT inherit SketchUp's Python home
                'PYTHONPATH'       => nil,    # <-- Do NOT inherit SketchUp's module path
                'PYTHONSTARTUP'    => nil,    # <-- Avoid running any startup hook
                'PYTHONEXECUTABLE' => nil,    # <-- Avoid forcing a foreign executable
                'PYTHONNOUSERSITE' => nil,    # <-- Let the real interpreter use its own site config
                '__PYVENV_LAUNCHER__' => nil, # <-- Clear any venv launcher redirection
                'PYTHONUTF8'       => '1',    # <-- Force UTF-8 mode (script prints ✔ + ANSI)
                'PYTHONIOENCODING' => 'utf-8',# <-- Guarantee UTF-8 stdio under a pipe
                'PYTHONUNBUFFERED' => '1'     # <-- Flush immediately so no output is lost
            }
        end

        # HELPER FUNCTION | Describe Inherited PYTHON* Vars (For The Debug Log)
        # ---------------------------------------------------------------
        def self.na_describe_inherited_python_env
            keys = ENV.keys.select { |k| k.to_s.upcase.start_with?('PYTHON') || k == '__PYVENV_LAUNCHER__' }
            return '(none)' if keys.empty?
            keys.sort.map { |k| "#{k}=#{ENV[k]}" }.join("\n")
        end

        # HELPER FUNCTION | Parse Python Stdout JSON Report (nil When Absent)
        # ---------------------------------------------------------------
        def self.na_parse_python_json_report(stdout_str)
            last_json_line = stdout_str.to_s.lines.reverse.find { |line| line.strip.start_with?('{') }
            return nil unless last_json_line
            na_normalise_python_report(JSON.parse(last_json_line.strip))
        rescue JSON::ParserError
            nil  # <-- Caller builds a rich diagnostic instead
        end

        # HELPER FUNCTION | Normalise A Parsed Python Report Hash
        # ---------------------------------------------------------------
        # Shared by the file channel and the stdout fallback so both produce an
        # identical result shape for the dialog.
        # ---------------------------------------------------------------
        def self.na_normalise_python_report(parsed)
            {
                success:        parsed['success'] == true,
                message:        parsed['message']  || 'Python sync complete.',
                uploaded_count: parsed['uploaded'] || 0,
                mirrored_count: parsed['mirrored'] || 0,
                elapsed_ms:     parsed['elapsed_ms'],
                sub_steps:      parsed['steps'].is_a?(Array) ? parsed['steps'] : []  # <-- Per-step trail from Python
            }
        end

        # HELPER FUNCTION | Build A Multi-Line Python Failure Diagnostic
        # ---------------------------------------------------------------
        def self.na_build_python_failure_message(cmd_display, exit_code, stdout_str, stderr_str, report_file, debug_log)
            out_tail = na_tail_text(stdout_str, 400)
            err_tail = na_tail_text(stderr_str, 400)

            lines = []
            lines << "Python finished (exit code: #{exit_code.nil? ? 'unknown' : exit_code}) but no readable report was found."
            lines << "Report file expected at: #{report_file}" if report_file
            lines << "Report file status: #{File.exist?(report_file.to_s) ? 'present but unparseable' : 'NOT created by Python'}" if report_file
            lines << "stdout: #{out_tail.empty? ? '(empty)' : out_tail}"
            lines << "stderr: #{err_tail.empty? ? '(empty)' : err_tail}"
            lines << "Full run log: #{debug_log}" if debug_log

            if exit_code == 0 && stdout_str.to_s.strip.empty? && stderr_str.to_s.strip.empty? &&
               !(report_file && File.exist?(report_file.to_s))
                lines << 'No report file AND empty output usually means the launched interpreter was the Windows Store stub (it exits 0 silently). Fix: set "python_executable" in the plugin AppConfig (python block) to a full python.exe path, then Reload Plugin.'
            end
            lines.join("\n")
        end

        # HELPER FUNCTION | Write A Full, Human-Readable Python Run Log To Disk
        # ---------------------------------------------------------------
        # This log is the forensic record of one Python sync launch. It explains
        # what was run, which hand-off channel produced the report (file vs
        # stdout), and the raw report JSON, so a failed dialog can be diagnosed
        # without re-running anything.
        # ---------------------------------------------------------------
        def self.na_write_python_debug_log(cmd_display, exit_code, stdout_str, stderr_str,
                                           inherited_env, report_file, report_json, report_ok)
            dir = na_python_log_dir
            return nil unless dir

            path        = File.join(dir, "Na__ValeVisionCloudSync__PythonRun__#{Time.now.strftime('%Y%m%d_%H%M%S')}.log")
            file_exists = report_file && File.exist?(report_file.to_s)
            channel     = if report_ok && file_exists then 'report FILE (preferred channel)'
                          elsif report_ok            then 'STDOUT (fallback channel)'
                          else                             'NONE — no readable report (see Diagnosis)'
                          end

            content = []
            content << '============================================================================='
            content << ' ValeVision Cloud Sync  -  Python Subprocess Run Log'
            content << '============================================================================='
            content << ' The plugin shells out to a Python orchestrator to mirror this project to'
            content << ' Cloudflare R2 + Whitecardopedia. This log records that single launch so any'
            content << ' dialog error can be traced to exactly what ran and what came back.'
            content << ''
            content << " Result      : #{report_ok ? 'OK  - report parsed' : 'FAIL - no report parsed'}"
            content << " Channel     : #{channel}"
            content << " Exit code   : #{exit_code.nil? ? 'unknown' : exit_code}"
            content << " Time        : #{Time.now.strftime('%d-%b-%Y at %H:%M:%S')}"
            content << ''
            content << ' Command:'
            content << "   #{cmd_display}"
            content << ''
            content << ' Report file (preferred hand-off channel):'
            content << "   Path   : #{report_file || '(none requested)'}"
            content << "   Status : #{file_exists ? 'written by Python' : 'NOT created by Python'}"
            content << '   ----- report JSON -----'
            content << (report_json && !report_json.strip.empty? ? na_indent_block(report_json, '   ') : '   (none)')
            content << ''
            content << ' Captured stdout (fallback channel):'
            content << (stdout_str.to_s.strip.empty? ? '   (empty - normal when the report file was used)' : na_indent_block(stdout_str, '   '))
            content << ''
            content << ' Captured stderr:'
            content << (stderr_str.to_s.strip.empty? ? '   (empty)' : na_indent_block(stderr_str, '   '))
            content << ''
            content << ' Inherited PYTHON* env (stripped before launch):'
            content << na_indent_block(inherited_env.to_s, '   ')

            unless report_ok
                content << ''
                content << ' Diagnosis:'
                if exit_code == 0 && !file_exists && stdout_str.to_s.strip.empty?
                    content << '   Exit 0, no report file, empty stdout. The launched interpreter likely'
                    content << '   did not actually run the script (commonly the Windows Store python stub).'
                    content << '   Set "python_executable" in the plugin AppConfig to a real python.exe.'
                elsif file_exists
                    content << '   A report file exists but could not be parsed as JSON - inspect it above.'
                else
                    content << '   See stderr above for the Python traceback.'
                end
            end

            content << '============================================================================='
            File.write(path, content.join("\n"))
            path.tr('\\', '/')
        rescue
            nil
        end

        # HELPER FUNCTION | Indent A Multi-Line Text Block For The Log
        # ---------------------------------------------------------------
        def self.na_indent_block(text, prefix)
            text.to_s.split("\n", -1).map { |line| "#{prefix}#{line}" }.join("\n")
        end

        # HELPER FUNCTION | Resolve A Writable Logs Directory
        # ---------------------------------------------------------------
        def self.na_python_log_dir
            base = begin
                Na__PathResolver.Na__ValeVisionCloudSync__ModulesRoot.to_s
            rescue
                ''
            end
            dir = base.empty? ? Dir.tmpdir : File.join(base, '99__Logs')
            FileUtils.mkdir_p(dir)
            dir.tr('\\', '/')
        rescue
            nil
        end

        # HELPER FUNCTION | Trim Long Diagnostic Text To A Readable Tail
        # ---------------------------------------------------------------
        def self.na_tail_text(text, max_chars)
            s = text.to_s.strip
            s.length > max_chars ? "…#{s[-max_chars..-1]}" : s
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

        # HELPER FUNCTION | Append Python Orchestrator Sub-Steps As Individual Report Lines
        # ---------------------------------------------------------------
        # Surfaces each Python step (Clone, Thumbnails, Upload, Merge...) as its
        # own line so the dialog shows a full trail rather than a single summary.
        def self.na_append_python_steps(report, python_result)
            note = python_result[:interpreter_note].to_s
            unless note.empty?
                report[:steps] << {
                    label:   'Python Interpreter',
                    success: python_result[:interpreter_ok] != false,   # <-- ERR only when we fell back to an untrusted interpreter
                    message: note
                }
            end

            sub_steps = python_result[:sub_steps]
            if sub_steps.is_a?(Array) && !sub_steps.empty?
                sub_steps.each do |step|
                    report[:steps] << {
                        label:   step['label'].to_s,
                        success: step['success'] == true,
                        message: step['message'].to_s
                    }
                end
            else
                report[:steps] << na_step_entry('Sync to R2 + Whitecardopedia', python_result)
            end
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
            parent_name = File.basename(File.dirname(project_root.to_s.tr('\\', '/'))) # <-- e.g. "ValeProjects__2026"
            match       = parent_name.match(/(\d{4})/)                                 # <-- Extract 4-digit year
            match ? match[1] : Time.now.year.to_s                                       # <-- Fallback to current year
        end

# endregion -------------------------------------------------------------------

    end # module Na__SyncOrchestrator
end # module Na__ValeVisionCloudSync

# =============================================================================
# END OF FILE
# =============================================================================
