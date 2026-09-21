# =============================================================================
# TRUEVISION3D - GLB BUILDER UTILITY - CLOUD SYNC ORCHESTRATOR
# =============================================================================
#
# FILE       : Na__TrueVision__GlbBuilder__CloudSyncOrchestrator__.rb
# NAMESPACE  : TrueVision3D::GlbBuilderUtility
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Run the ProjectVision build and the Cloudflare R2 push from
#              inside SketchUp
# CREATED    : 19-Sep-2026
#
# DESCRIPTION:
# - Runs the SAME two Python scripts that ProjectVision__BuildPipeline__.ps1
#   runs for '--Project--{CODE}--TV' (its interactive menu option 3):
#
#       1. ProjectVision__BuildScript__.py
#          Rebuilds the master index and regenerates TrueVision__ProjectData__.json
#          from whatever design phase folders now exist on disk.
#
#       2. CloudflareR2__ModelSync__Main__.py --project {FOLDER} --tv-only
#          Mirrors the project's GLBs and TrueVision JSON up to R2.
#
# - The two scripts are invoked DIRECTLY rather than through the .bat. The .bat
#   launches a detached PowerShell window with -NoExit, and the .ps1 ends on a
#   Read-Host prompt; neither is safe to drive from a GUI host that needs to
#   know whether the work succeeded. The arguments below are exactly the ones
#   the .ps1 assembles, so this is the same wheel, not a new one.
#
# - Python discovery follows the ValeVision Cloud Sync approach, for the same
#   reason: SketchUp's child-process PATH can resolve a bare `python` to the
#   Windows Store stub, which runs and produces nothing at all.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 19-Sep-2026 - Version 2.9.0
# - Initial cloud sync orchestrator.
#
# =============================================================================

require 'json'
require 'open3'
require 'tmpdir'

module TrueVision3D
    module GlbBuilderUtility

    # -----------------------------------------------------------------------------
    # REGION | Public Entry Point
    # -----------------------------------------------------------------------------

        # FUNCTION | Build The Project Data And Push It To Cloudflare R2
        # ---------------------------------------------------------------
        # Returns { success:, message:, steps: [...] } in the dialog's report
        # shape, so the caller can render it without translation.
        # ---------------------------------------------------------------
        def self.Na__CloudSync__PushProject(link, dry_run: false)
            portal_root    = link[:portal_root].to_s
            project_folder = link[:project_folder].to_s

            if portal_root.empty? || project_folder.empty?
                return self.Na__CloudSync__FailureReport('This model is not linked to a project, so there is nothing to push.')
            end

            script_dir = self.Na__CloudSync__ScriptDirectory(portal_root)
            unless script_dir && Dir.exist?(script_dir)
                return self.Na__CloudSync__FailureReport("The ProjectVision script folder was not found at:\n#{script_dir}")
            end

            interpreter = self.Na__CloudSync__ResolvePythonExecutable
            steps       = []
            steps << {
                label:   'Interpreter',
                success: interpreter[:trusted],
                message: interpreter[:note]
            }

            build_step = self.Na__CloudSync__RunBuildScript(interpreter[:command], script_dir)
            steps << build_step
            unless build_step[:success]
                return { success: false, running: false, message: 'Project build failed - nothing was pushed to R2.', steps: steps }
            end

            push_step = self.Na__CloudSync__RunR2Sync(interpreter[:command], script_dir, project_folder, dry_run)
            steps << push_step

            succeeded = push_step[:success]
            message   = if !succeeded
                'Cloudflare R2 sync failed. Open the debug log for the full output.'
            elsif dry_run
                "Dry run complete for #{project_folder}. Nothing was uploaded."
            else
                "#{project_folder} synced to Cloudflare R2."
            end

            { success: succeeded, running: false, message: message, steps: steps }
        rescue => e
            Na__Log__Warn "[CloudSync] Push failed: #{e.message}"
            Na__Log__Warn e.backtrace.first(5).join("\n")
            self.Na__CloudSync__FailureReport("#{e.class}: #{e.message}")
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Strip ANSI Colour Codes Before Parsing
        # ---------------------------------------------------------------
        # The sync script colours its output; the escape sequences sit between
        # the markers and the values we match on.
        # ---------------------------------------------------------------
        def self.Na__CloudSync__StripAnsi(text)
            text.to_s.gsub(/\e\[[0-9;]*m/, '')
        end
        # ---------------------------------------------------------------

        # FUNCTION | Open The Build Pipeline In Its Own Window
        # ---------------------------------------------------------------
        # The manual escape hatch: launches the .bat exactly as double-clicking
        # the desktop shortcut does, so the interactive menu is still reachable
        # when something needs eyes on it.
        # ---------------------------------------------------------------
        def self.Na__CloudSync__OpenBuildPipelineWindow(link, project_code = nil)
            script_dir = self.Na__CloudSync__ScriptDirectory(link[:portal_root].to_s)
            bat_name   = self.Na__CloudSync__PipelineConfig['LauncherBatName'].to_s
            bat_path   = File.join(script_dir.to_s, bat_name).tr('/', '\\')

            return { success: false, message: "Launcher not found at:\n#{bat_path}" } unless File.exist?(bat_path)

            code = project_code.to_s.strip.upcase
            args = self.Na__ProjectLink__ValidCode?(code) ? " --Project--#{code}--TV" : ''

            UI.openURL("file:///#{bat_path.tr('\\', '/')}") if args.empty?
            system("cmd.exe /c start \"\" \"#{bat_path}\"#{args}") unless args.empty?

            {
                success: true,
                message: args.empty? ? 'Build pipeline opened.' : "Build pipeline opened for#{args}."
            }
        rescue => e
            { success: false, message: "#{e.class}: #{e.message}" }
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Script Execution
    # -----------------------------------------------------------------------------

        # HELPER FUNCTION | Run ProjectVision__BuildScript__.py
        # ---------------------------------------------------------------
        def self.Na__CloudSync__RunBuildScript(interpreter, script_dir)
            script_name = self.Na__CloudSync__PipelineConfig['BuildScriptName'].to_s
            script_path = File.join(script_dir, script_name).tr('\\', '/')

            unless File.exist?(script_path)
                return { label: 'Project Build', success: false, message: "Script not found:\n#{script_path}" }
            end

            result = self.Na__CloudSync__Execute(interpreter, script_path, [], script_dir)

            {
                label:   'Project Build',
                success: result[:success],
                message: result[:success] ? 'Project index and TrueVision__ProjectData__.json rebuilt.'
                                          : self.Na__CloudSync__DescribeFailure(result)
            }
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Run CloudflareR2__ModelSync__Main__.py
        # ---------------------------------------------------------------
        def self.Na__CloudSync__RunR2Sync(interpreter, script_dir, project_folder, dry_run)
            config      = self.Na__CloudSync__PipelineConfig
            script_name = config['R2SyncScriptName'].to_s
            script_path = File.join(script_dir, script_name).tr('\\', '/')

            unless File.exist?(script_path)
                return { label: 'Cloudflare R2', success: false, message: "Script not found:\n#{script_path}" }
            end

            args  = ['--project', project_folder, config['R2SyncTrueVisionArg'].to_s]
            args << '--dry-run-only' if dry_run

            # ANSWER THE PROMPT | The sync script previews the upload and then asks
            # "Proceed with uploading files to Cloudflare R2? (yes/no)" on stdin.
            # auto_confirm_upload exists inside the script but is never wired to a
            # CLI flag, so the prompt always runs. With stdin closed its input()
            # raises EOFError, the script prints "[CANCEL] Upload cancelled" and
            # RETURNS 0 - a success exit code having uploaded nothing at all.
            # Feeding it "yes" is exactly what the interactive menu does; the
            # dialog has already confirmed with the user before reaching here.
            stdin_data = dry_run ? nil : "yes\n"

            result = self.Na__CloudSync__Execute(interpreter, script_path, args, script_dir, stdin_data)

            self.Na__CloudSync__DescribeR2Outcome(result, project_folder, dry_run)
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Decide What The R2 Sync Actually Did
        # ---------------------------------------------------------------
        # The exit code alone is not evidence of an upload: a cancelled upload
        # also exits 0. The outcome is read from the script's own output.
        # ---------------------------------------------------------------
        def self.Na__CloudSync__DescribeR2Outcome(result, project_folder, dry_run)
            label  = dry_run ? 'R2 Dry Run' : 'Cloudflare R2'
            output = "#{result[:stdout]}\n#{result[:stderr]}"

            unless result[:success]
                return { label: label, success: false, message: self.Na__CloudSync__DescribeFailure(result) }
            end

            # The script cancelled instead of uploading - treat as a failure even
            # though it exited 0, because nothing reached the bucket.
            if output =~ /\[CANCEL\]/i
                return {
                    label:   label,
                    success: false,
                    message: "The sync script cancelled its own upload and nothing was sent to R2.\n" \
                             "#{self.Na__CloudSync__MeaningfulTail(output, 3)}\n" \
                             "Log: #{result[:log_path]}"
                }
            end

            if dry_run
                return {
                    label:   label,
                    success: true,
                    message: "Dry run for #{project_folder} - nothing uploaded.\n#{self.Na__CloudSync__MeaningfulTail(result[:stdout], 4)}"
                }
            end

            # "Upload complete! N file(s) uploaded, M failed."
            if (match = output.match(/Upload complete!\s*(\d+) file\(s\) uploaded,\s*(\d+) failed/i))
                uploaded = match[1].to_i
                failed   = match[2].to_i
                message  = "#{uploaded} file(s) uploaded to R2#{failed.zero? ? '' : ", #{failed} failed"}."

                # The sync mirrors: GLBs no local folder holds are deleted once the uploads land
                if (cleanup = output.match(/Stale GLB cleanup:\s*(\d+) removed from R2,\s*(\d+) failed/i))
                    failed  += cleanup[2].to_i
                    message += " #{cleanup[1]} stale GLB(s) removed from R2#{cleanup[2].to_i.zero? ? '' : ", #{cleanup[2]} could not be"}."
                elsif output =~ /\[HELD\]/
                    message += ' Stale GLBs were left on R2 because an upload failed.'
                end

                return {
                    label:   label,
                    success: failed.zero?,
                    message: message
                }
            end

            if output =~ /All files are up to date/i
                return {
                    label:   label,
                    success: true,
                    message: "R2 already holds this project's current files - nothing needed uploading."
                }
            end

            # No recognisable outcome. A GUI host can hand back empty pipes even
            # when the child printed normally, so say so rather than claim success.
            {
                label:   label,
                success: false,
                message: "The sync script exited cleanly, but its output could not be read, so the upload is " \
                         "unconfirmed. Check the log, or use Open Build Pipeline Window to watch it run.\n" \
                         "Log: #{result[:log_path]}"
            }
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Run One Python Script And Capture Its Output
        # ---------------------------------------------------------------
        # Every run is written to a debug log on disk, because a GUI host can
        # return empty pipes even when the child printed normally.
        # ---------------------------------------------------------------
        def self.Na__CloudSync__Execute(interpreter, script_path, script_args, working_dir, stdin_data = nil)
            command     = Array(interpreter) + [script_path] + Array(script_args)
            display     = command.join(' ')
            child_env   = self.Na__CloudSync__SanitizedPythonEnv

            options = { chdir: working_dir }
            options[:stdin_data] = stdin_data if stdin_data                 # <-- Answers the script's yes/no prompt

            stdout_str, stderr_str, status = Open3.capture3(child_env, *command, **options)
            exit_code = status.respond_to?(:exitstatus) ? status.exitstatus : nil

            log_path = self.Na__CloudSync__WriteDebugLog(display, exit_code, stdout_str, stderr_str)

            {
                success:   exit_code == 0,
                exit_code: exit_code,
                stdout:    stdout_str.to_s,
                stderr:    stderr_str.to_s,
                command:   display,
                log_path:  log_path
            }
        rescue => e
            {
                success:   false,
                exit_code: nil,
                stdout:    '',
                stderr:    "#{e.class}: #{e.message}",
                command:   Array(interpreter).join(' '),
                log_path:  nil
            }
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Summarise A Failed Run For The Report Panel
        # ---------------------------------------------------------------
        def self.Na__CloudSync__DescribeFailure(result)
            lines = []
            lines << "Exit code: #{result[:exit_code].nil? ? '(none)' : result[:exit_code]}"

            stderr_tail = self.Na__CloudSync__MeaningfulTail(result[:stderr])
            stdout_tail = self.Na__CloudSync__MeaningfulTail(result[:stdout])
            lines << stderr_tail unless stderr_tail.empty?
            lines << stdout_tail if stderr_tail.empty? && !stdout_tail.empty?
            lines << "Log: #{result[:log_path]}" if result[:log_path]

            lines.join("\n")
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Take The Last Few Non-Empty Output Lines
        # ---------------------------------------------------------------
        def self.Na__CloudSync__MeaningfulTail(raw_output, line_count = 4)
            raw_output.to_s
                .lines
                .map(&:rstrip)
                .reject(&:empty?)
                .reject { |line| line.match?(/\A[-=\s]+\z/) }            # <-- Drop the scripts' rule lines
                .last(line_count)
                .join("\n")
        rescue
            ''
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Python Interpreter Resolution
    # -----------------------------------------------------------------------------

        # FUNCTION | Resolve A Python Interpreter That Actually Runs
        # ---------------------------------------------------------------
        # In order: an absolute path from the config, an absolute python.exe
        # found on disk, a PATH launcher that survives a probe, then bare
        # `python` as a last resort.
        # ---------------------------------------------------------------
        def self.Na__CloudSync__ResolvePythonExecutable
            configured = self.Na__CloudSync__PythonConfig['PythonExecutable'].to_s.strip
            unless configured.empty?
                return {
                    command: [configured],
                    note:    "Using the interpreter set in the portal config: #{configured}",
                    trusted: true
                }
            end

            absolute = self.Na__CloudSync__DiscoverAbsolutePythonExes.first
            if absolute
                return { command: [absolute], note: "Found Python on disk: #{absolute}", trusted: true }
            end

            [['py', '-3'], ['python3'], ['python']].each do |candidate|
                next unless self.Na__CloudSync__PythonCandidateWorks?(candidate)

                return {
                    command: candidate,
                    note:    "Using the PATH launcher: #{candidate.join(' ')}",
                    trusted: true
                }
            end

            {
                command: ['python'],
                note:    'No real interpreter found. Falling back to bare "python" - if this is the Windows Store stub it will produce no output. Set "PythonExecutable" in Na__TrueVision__GlbBuilder__ProjectPortalConfig__.json to a full python.exe path.',
                trusted: false
            }
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Glob The Common Real Python Install Locations
        # ---------------------------------------------------------------
        # These are trusted without a probe: the Store stub never lives in any
        # of them.
        # ---------------------------------------------------------------
        def self.Na__CloudSync__DiscoverAbsolutePythonExes
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
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Probe Whether A PATH Launcher Actually Runs
        # ---------------------------------------------------------------
        def self.Na__CloudSync__PythonCandidateWorks?(candidate)
            out, _err, status = Open3.capture3(
                self.Na__CloudSync__SanitizedPythonEnv, *candidate,
                '-c', 'import sys; sys.stdout.write(sys.executable or "")'
            )
            real_exe = out.to_s.strip

            return false unless status.success?
            return false if real_exe.empty?
            return false if real_exe.tr('\\', '/').downcase.include?('/windowsapps/')   # <-- Reject the Store stub

            true
        rescue
            false                                                        # <-- ENOENT etc: candidate unavailable
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Build A Child Environment Free Of SketchUp's Python
        # ---------------------------------------------------------------
        def self.Na__CloudSync__SanitizedPythonEnv
            {
                'PYTHONHOME'          => nil,    # <-- Do NOT inherit SketchUp's Python home
                'PYTHONPATH'          => nil,    # <-- Do NOT inherit SketchUp's module path
                'PYTHONSTARTUP'       => nil,    # <-- Avoid running any startup hook
                'PYTHONEXECUTABLE'    => nil,    # <-- Avoid forcing a foreign executable
                'PYTHONNOUSERSITE'    => nil,    # <-- Let the real interpreter use its own site config
                '__PYVENV_LAUNCHER__' => nil,    # <-- Clear any venv launcher redirection
                'PYTHONUTF8'          => '1',    # <-- The build scripts print box-drawing and tick glyphs
                'PYTHONIOENCODING'    => 'utf-8',# <-- Guarantee UTF-8 stdio under a pipe
                'PYTHONUNBUFFERED'    => '1'     # <-- Flush immediately so no output is lost
            }
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Paths, Config and Logging
    # -----------------------------------------------------------------------------

        # HELPER FUNCTION | Read The Build Pipeline Config Block
        # ---------------------------------------------------------------
        def self.Na__CloudSync__PipelineConfig
            self.Na__PortalMapper__Config['BuildPipeline'] || {}
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Read The Python Config Block
        # ---------------------------------------------------------------
        def self.Na__CloudSync__PythonConfig
            self.Na__PortalMapper__Config['Python'] || {}
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Resolve The ProjectVision Script Directory
        # ---------------------------------------------------------------
        def self.Na__CloudSync__ScriptDirectory(portal_root)
            rel = self.Na__CloudSync__PipelineConfig['ScriptDirRel'].to_s
            return nil if rel.empty? || portal_root.to_s.empty?

            File.join(self.Na__PortalMapper__RepoRoot(portal_root), rel).tr('\\', '/')
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Write A Full Run Log Next To The Plugin Logs
        # ---------------------------------------------------------------
        def self.Na__CloudSync__WriteDebugLog(command_display, exit_code, stdout_str, stderr_str)
            dir  = File.join(Dir.tmpdir, 'Na__TrueVision__GlbBuilder__CloudSync')
            FileUtils.mkdir_p(dir)
            path = File.join(dir, "CloudSync__#{Time.now.strftime('%Y%m%d_%H%M%S_%L')}.log")

            File.open(path, 'w:UTF-8') do |file|
                file.puts '==============================================================================='
                file.puts " TrueVision GLB Builder - Cloud Sync Run"
                file.puts " #{Time.now.strftime('%d-%b-%Y %H:%M:%S')}"
                file.puts '==============================================================================='
                file.puts "COMMAND   : #{command_display}"
                file.puts "EXIT CODE : #{exit_code.nil? ? '(none)' : exit_code}"
                file.puts '-------------------------------------------------------------------------------'
                file.puts 'STDOUT'
                file.puts stdout_str.to_s
                file.puts '-------------------------------------------------------------------------------'
                file.puts 'STDERR'
                file.puts stderr_str.to_s
                file.puts '==============================================================================='
            end

            path.tr('\\', '/')
        rescue
            nil
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Build A One-Step Failure Report
        # ---------------------------------------------------------------
        def self.Na__CloudSync__FailureReport(message)
            {
                success: false,
                running: false,
                message: message,
                steps:   [{ label: 'Cloud Sync', success: false, message: message }]
            }
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

    end  # module GlbBuilderUtility
end  # module TrueVision3D

# =============================================================================
# END OF FILE
# =============================================================================

load File.join(__dir__, 'truevision_cloud_manager.rb')
