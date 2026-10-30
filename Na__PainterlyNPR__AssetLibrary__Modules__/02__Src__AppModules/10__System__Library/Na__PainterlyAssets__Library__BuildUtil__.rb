# =============================================================================
# NA PAINTERLYNPR ASSETS - LIBRARY - PAINTERLYNPR'S BUILD UTILITY
# =============================================================================
#
# FILE       : Na__PainterlyAssets__Library__BuildUtil__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__BuildUtil
# PURPOSE    : Runs PainterlyNPR's asset library utility
#              (60__Dev__WebBuildUtils/PainterlyNPR__BuildUtil__AssetLibrary__.py)
#              for the three answers only it may give: the next free Id
#              (`next CC Type [--family FFF]`), the verdict on every asset
#              (`validate`) and the index the web app reads (`index`).
# CREATED    : 30-Oct-2026
#
# DESCRIPTION:
# - One set of rules, whoever writes an asset: the plugin never works out an
#   Id or a verdict of its own.
# - A run is a spawned process whose output goes straight into a run log
#   (90__AppCache__TempFilesCache), never a pipe: Open3 under SketchUp's GUI
#   host can come back with empty pipes (GLB Builder 2.9.3, Cloud Sync), and a
#   file is also the record of what ran. The child gets no stdin and a clean
#   environment, and runs isolated (-I) in UTF-8 mode (-X utf8): SketchUp
#   2026's own embedded Python exports PYTHONHOME / PYTHONPATH, which make an
#   external python.exe print nothing and exit 0.
# - SketchUp is never frozen waiting: a repeating 0.1 s timer polls the child
#   (Process.wait2 with WNOHANG) and hands the result to the caller's block.
#   Ruby threads stall once a callback returns, so none are used. One run at a
#   time; a run past the config's timeoutSeconds is stopped and reported.
# - Na__BuildUtil__RunSync runs the same command and waits, for the offline
#   suites and for the rare caller that cannot continue without the answer.
#
# =============================================================================

module Na__PainterlyAssets
    module Na__BuildUtil

    # -------------------------------------------------------------------------
    # REGION | Constants and State
    # -------------------------------------------------------------------------

        NA_POLL_SECONDS = 0.1                                                                       unless defined?(NA_POLL_SECONDS)
        NA_RUN_LOG      = 'Na__PainterlyAssets__PythonRun__Last__.log'.freeze                       unless defined?(NA_RUN_LOG)
        NA_CLEAN_ENV    = {
            'PYTHONHOME'          => nil,                                                            # <-- Do NOT inherit SketchUp's embedded Python home
            'PYTHONPATH'          => nil,                                                            # <-- ...nor its module path
            'PYTHONSTARTUP'       => nil,
            'PYTHONEXECUTABLE'    => nil,
            'PYTHONNOUSERSITE'    => nil,
            '__PYVENV_LAUNCHER__' => nil,
            'PYTHONUTF8'          => '1',
            'PYTHONIOENCODING'    => 'utf-8',
            'PYTHONUNBUFFERED'    => '1'
        }.freeze unless defined?(NA_CLEAN_ENV)

        @na_job = nil unless defined?(@na_job)                                                      # <-- The run in flight: { pid, started, timer, log, ... }

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        def self.Na__BuildUtil__Busy?
            !@na_job.nil?
        end

        # FUNCTION | Run the Utility and Hand Its Result to the Block, Without Waiting
        # ------------------------------------------------------------
        # @param args [Array<String>] e.g. ['next', '07', 'Trees']
        # @yield [Hash] the result (see na_result); always called exactly once
        # @return [Boolean] true when the run started
        def self.Na__BuildUtil__Run(args, &on_done)
            if self.Na__BuildUtil__Busy?
                on_done.call(self.na_failure(args, 'PainterlyNPR\'s build utility is still busy with the last request. Try again in a moment.')) if on_done
                return false
            end

            launch = self.na_launch(args)
            if launch['error']
                on_done.call(self.na_failure(args, launch['error'])) if on_done
                return false
            end

            @na_job = launch.merge('done' => on_done, 'polling' => false)
            @na_job['timer'] = UI.start_timer(NA_POLL_SECONDS, true) { Na__PainterlyAssets::Na__BuildUtil.na_poll }
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Run Several Commands One After Another, Then Hand Over All Results
        # ------------------------------------------------------------
        # Stops at the first run that could not even start (no Python, a busy
        # utility); a command that ran and failed still lets the next one run,
        # as validate's errors must not stop the index from being written.
        def self.Na__BuildUtil__RunChain(commands, results = [], &on_done)
            return on_done.call(results) if commands.empty?

            started = self.Na__BuildUtil__Run(commands.first) do |result|
                results << result
                if result['launched']
                    Na__PainterlyAssets::Na__BuildUtil.Na__BuildUtil__RunChain(commands.drop(1), results, &on_done)
                else
                    on_done.call(results)
                end
            end
            started
        end
        # ---------------------------------------------------------------

        # FUNCTION | Run the Utility and Wait for It (offline suites, the rare blocking caller)
        # ------------------------------------------------------------
        def self.Na__BuildUtil__RunSync(args)
            return self.na_failure(args, 'PainterlyNPR\'s build utility is still busy with the last request.') if self.Na__BuildUtil__Busy?

            launch = self.na_launch(args)
            return self.na_failure(args, launch['error']) if launch['error']

            _pid, status = Process.wait2(launch['pid'])
            self.na_result(launch, status, false)
        end
        # ---------------------------------------------------------------

        # FUNCTION | What the Next Run Would Use (Settings shows it)
        # ------------------------------------------------------------
        def self.Na__BuildUtil__Describe
            python = Na__PathResolver.Na__Paths__Python
            util   = Na__PathResolver.Na__Paths__RootFile('buildUtil')
            {
                'python'     => python && python['exe'],
                'source'     => python && python['source'],
                'windowless' => python ? python['windowless'] : false,
                'utility'    => util,
                'utilityOk'  => util ? File.file?(util) : false,
                'runLog'     => File.join(Na__PainterlyAssets::NA_CACHE_DIR, NA_RUN_LOG)
            }
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals - Launching and Polling
    # -------------------------------------------------------------------------

        def self.na_launch(args)
            root   = Na__PathResolver.Na__Paths__Root
            return { 'error' => 'The PainterlyNPR folder was not found. Choose it in Settings, Library Folder.' } unless root

            util   = Na__PathResolver.Na__Paths__RootFile('buildUtil', root)
            return { 'error' => "PainterlyNPR's build utility is missing: #{util}" } unless util && File.file?(util)

            python = Na__PathResolver.Na__Paths__Python
            return { 'error' => 'No Python 3 was found. Install Python 3, or choose python.exe in Settings, Python.' } unless python

            log = File.join(Na__PathResolver.Na__Paths__CacheDir, NA_RUN_LOG)
            File.delete(log) if File.exist?(log)
            command = [python['exe'], '-I', '-X', 'utf8', util] + args.map(&:to_s)
            pid = Process.spawn(NA_CLEAN_ENV, *command, chdir: root, in: File::NULL, out: log, err: [:child, :out])
            {
                'pid'     => pid,
                'args'    => args.map(&:to_s),
                'command' => "#{File.basename(python['exe'])} #{File.basename(util)} #{args.join(' ')}",
                'python'  => python['exe'],
                'log'     => log,
                'started' => Process.clock_gettime(Process::CLOCK_MONOTONIC)
            }
        rescue SystemCallError, ArgumentError => error
            { 'error' => "Python could not be started (#{error.class}): #{error.message}" }
        end

        # The timer's tick. The busy flag stops a tick fired again from inside
        # a modal dialog (a modal pumps the event loop) from re-entering.
        def self.na_poll
            job = @na_job
            return unless job
            return if job['polling']

            job['polling'] = true
            begin
                _pid, status = Process.wait2(job['pid'], Process::WNOHANG)
                elapsed      = Process.clock_gettime(Process::CLOCK_MONOTONIC) - job['started']
                timeout      = Na__ConfigLoader.Na__Config__GetOr(60, 'python', 'timeoutSeconds').to_f
                if status.nil? && elapsed < timeout
                    job['polling'] = false
                    return
                end

                timed_out = status.nil?
                self.na_stop(job['pid']) if timed_out
                self.na_finish(job, self.na_result(job, status, timed_out))
            rescue StandardError => error
                Na__DebugTools.Na__Debug__Error('Polling the build utility failed.', error)
                self.na_finish(job, self.na_failure(job['args'], "The build utility's run could not be followed: #{error.message}"))
            end
        end

        def self.na_finish(job, result)
            UI.stop_timer(job['timer']) if job['timer']
            @na_job = nil                                                                            # <-- Free before calling back: the callback may start the next run
            job['done'].call(result) if job['done']
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('A build utility result could not be handled.', error)
        end

        def self.na_stop(pid)
            Process.kill('KILL', pid)
            Process.wait2(pid)
        rescue SystemCallError => error
            Na__DebugTools.Na__Debug__Warn("The timed-out build utility run (pid #{pid}) could not be stopped: #{error.message}")
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals - Results
    # -------------------------------------------------------------------------

        # FUNCTION | One Run's Result
        # ------------------------------------------------------------
        # @return [Hash] { 'launched', 'ok', 'exitCode', 'lines', 'output', 'command', 'python', 'seconds', 'timedOut', 'error' }
        def self.na_result(launch, status, timed_out)
            output = File.exist?(launch['log']) ? File.read(launch['log'], encoding: 'bom|utf-8') : ''
            output = output.scrub('?')
            code   = status ? status.exitstatus : nil
            seconds = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - launch['started']).round(2)
            error = if timed_out
                        "The build utility did not finish within #{Na__ConfigLoader.Na__Config__GetOr(60, 'python', 'timeoutSeconds')} seconds and was stopped."
                    elsif output.strip.empty? && code != 0
                        "Python printed nothing and ended with code #{code.inspect}. If it is the Windows Store stub, choose a real python.exe in Settings, Python."
                    end
            Na__DebugTools.Na__Debug__Info("Build utility: #{launch['command']} -> exit #{code.inspect} in #{seconds} s")
            {
                'launched' => true,
                'ok'       => !timed_out && code == 0,
                'exitCode' => code,
                'lines'    => output.lines.map(&:rstrip).reject(&:empty?),
                'output'   => output,
                'command'  => launch['command'],
                'args'     => launch['args'],
                'python'   => launch['python'],
                'seconds'  => seconds,
                'timedOut' => timed_out,
                'error'    => error
            }
        end
        # ---------------------------------------------------------------

        def self.na_failure(args, message)
            {
                'launched' => false, 'ok' => false, 'exitCode' => nil, 'lines' => [], 'output' => '',
                'command' => Array(args).join(' '), 'args' => Array(args).map(&:to_s), 'python' => nil,
                'seconds' => 0.0, 'timedOut' => false, 'error' => message.to_s
            }
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
