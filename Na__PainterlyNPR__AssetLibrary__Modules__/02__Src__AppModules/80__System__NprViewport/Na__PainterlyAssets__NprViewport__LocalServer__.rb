# =============================================================================
# NA PAINTERLYNPR ASSETS - NPR VIEWPORT - LOCAL SERVER
# =============================================================================
#
# FILE       : Na__PainterlyAssets__NprViewport__LocalServer__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__LocalServer
# PURPOSE    : Starts, finds and stops the plugin's own web server on
#              127.0.0.1 (Na__PainterlyAssets__NprViewport__LocalServer__.py),
#              which serves the cached PainterlyNPR engine, the windows' host
#              scripts and the projects' GLB caches. PainterlyNPR's ES modules
#              never load from a file:// page, so the NPR windows need one.
# CREATED    : 01-Nov-2026
#
# DESCRIPTION:
# - Python serves (threaded), not Ruby: Ruby threads stall inside SketchUp once
#   a callback returns, and a GLB fetched mid-orbit must not wait on SketchUp's
#   main thread. pythonw.exe, -I -X utf8, a clean environment, output to a log
#   (the build utility's way of running Python).
# - THE PORT is the operating system's choice, read from the ready file the
#   server writes once it listens; a 0.1 s timer waits for it.
# - ONE SERVER A SESSION: it survives Reload Plugin Data (its state is guarded)
#   and stops itself when SketchUp exits (it watches SketchUp's process id).
#   Stop asks it with the session's token, then ends the process if it must.
#   A server started by an older version of this file (its ready file names
#   its version) is restarted the next time a window needs it (v0.3.0: the
#   1.1.0 server takes NPR Export's pictures into its outbox).
#
# =============================================================================

require 'securerandom'

module Na__PainterlyAssets
    module Na__LocalServer

    # -------------------------------------------------------------------------
    # REGION | Constants and State
    # -------------------------------------------------------------------------

        NA_SERVER_SCRIPT = 'Na__PainterlyAssets__NprViewport__LocalServer__.py'.freeze unless defined?(NA_SERVER_SCRIPT)
        NA_READY_FILE    = 'Na__PainterlyAssets__LocalServer__Ready__.json'.freeze     unless defined?(NA_READY_FILE)
        NA_LOG_FILE      = 'Na__PainterlyAssets__LocalServer__Run__.log'.freeze        unless defined?(NA_LOG_FILE)
        NA_POLL_SECONDS  = 0.1                                                         unless defined?(NA_POLL_SECONDS)
        NA_SERVER_VERSION = '1.1.0'                                                    # <-- The .py's SERVER_VERSION: a running server of another is restarted
        NA_OUTBOX_FOLDER  = 'Na__PainterlyAssets__NprExport__Outbox'                   # <-- In 90__AppCache__TempFilesCache: NPR Export's pictures as they arrive

        @na_server   = nil unless defined?(@na_server)                                    # <-- { pid, port, token, override }
        @na_starting = nil unless defined?(@na_starting)                                  # <-- The start in flight: { pid, timer, started }
        @na_waiters  = []  unless defined?(@na_waiters)

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        def self.Na__Server__Port
            self.Na__Server__Running? ? @na_server['port'] : nil
        end

        def self.Na__Server__Running?
            return false unless @na_server
            _pid, status = Process.wait2(@na_server['pid'], Process::WNOHANG)
            if status
                @na_server = nil                                                         # <-- It ended (SketchUp's own exit, or a crash): start again next time
                return false
            end
            true
        rescue SystemCallError
            @na_server = nil
            false
        end

        # FUNCTION | A Running Server, Started If Needed
        # ------------------------------------------------------------
        # @yield [Hash] { 'ok', 'port', 'message' }, once. The override folder
        #   is fixed when the server starts, so a changed one restarts it.
        def self.Na__Server__Ensure(&on_ready)
            override = Na__RemoteEngine.Na__Remote__Override.to_s
            self.Na__Server__Stop if self.Na__Server__Running? && (@na_server['override'] != override || !self.Na__Server__Current?)
            return on_ready.call('ok' => true, 'port' => @na_server['port']) if on_ready && self.Na__Server__Running?
            @na_waiters << on_ready if on_ready
            return if @na_starting

            launch = self.na_launch(override)
            return self.na_finish('ok' => false, 'message' => launch['error']) if launch['error']

            @na_starting = launch
            @na_starting['timer'] = UI.start_timer(NA_POLL_SECONDS, true) { Na__PainterlyAssets::Na__LocalServer.na_poll }
        end
        # ---------------------------------------------------------------

        # FUNCTION | The URL a Window Opens: the engine's own page with its host
        # ------------------------------------------------------------
        # The parameters window is on localhost, the viewport on 127.0.0.1: two
        # origins, so each keeps its own browser storage (the engine's work
        # mode, folds and saves) and the parameters' quiet engine never sets the
        # viewport's.
        def self.Na__Server__PageUrl(role, commit)
            host = role.to_s == 'parameters' ? 'localhost' : '127.0.0.1'
            "http://#{host}:#{@na_server['port']}/npr/#{commit}/#{Na__RemoteEngine::NA_APP_PAGE}?na-host=#{role}"
        end

        def self.Na__Server__Stop
            server = @na_server
            @na_server = nil
            return false unless server
            begin
                require 'net/http'                                                         # <-- Only here: SketchUp's start-up never pays for it
                http = Net::HTTP.new('127.0.0.1', server['port'])
                http.open_timeout = 1
                http.read_timeout = 1
                request = Net::HTTP::Post.new('/__na/shutdown')
                request['X-Na-Token'] = server['token']
                http.request(request)
            rescue StandardError, LoadError
                nil                                                                        # <-- Not answered: the timer below ends the process
            end
            UI.start_timer(1.5, false) do
                begin
                    _pid, status = Process.wait2(server['pid'], Process::WNOHANG)
                    Process.kill('KILL', server['pid']) if status.nil?
                rescue SystemCallError
                    nil
                end
            end
            true
        end

        def self.Na__Server__LogPath
            File.join(Na__PathResolver.Na__Paths__CacheDir, NA_LOG_FILE)
        end

        # FUNCTION | Is the Running Server This Version's? (an older one has no export route)
        # ------------------------------------------------------------
        def self.Na__Server__Current?
            self.Na__Server__Running? && @na_server['version'].to_s == NA_SERVER_VERSION
        end
        # ---------------------------------------------------------------

        # FUNCTION | Where NPR Export's Pictures Arrive, and the Token That Lets Them In
        # ------------------------------------------------------------
        def self.Na__Server__Outbox
            File.join(Na__PathResolver.Na__Paths__CacheDir, NA_OUTBOX_FOLDER)
        end

        def self.Na__Server__Token
            self.Na__Server__Running? ? @na_server['token'] : nil
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals
    # -------------------------------------------------------------------------

        def self.na_launch(override)
            python = Na__PathResolver.Na__Paths__Python
            return { 'error' => 'No Python 3 was found, so the NPR windows have no server. Install Python 3, or choose python.exe in the Asset Library\'s Settings.' } unless python

            work   = Na__PathResolver.Na__Paths__CacheDir
            ready  = File.join(work, NA_READY_FILE)
            File.delete(ready) if File.exist?(ready)
            token  = SecureRandom.hex(16)
            script = File.join(__dir__, NA_SERVER_SCRIPT)
            command = [python['exe'], '-I', '-X', 'utf8', script,
                       '--engine-root', Na__RemoteEngine.Na__Remote__Root,
                       '--host-root', Na__PainterlyAssets::NA_MODULES_ROOT,
                       '--projects-root', Na__CacheStore.Na__Cache__Root,
                       '--parent-pid', Process.pid.to_s,
                       '--ready-file', ready,
                       '--token', token,
                       '--port', Na__ConfigLoader.Na__Config__GetOr(8147, 'nprViewport', 'server', 'port').to_i.to_s,   # <-- The usual port (taken: the system's choice)
                       '--log', self.Na__Server__LogPath,
                       '--outbox', self.Na__Server__Outbox]
            command += ['--override', override] unless override.empty?
            pid = Process.spawn(Na__BuildUtil::NA_CLEAN_ENV, *command, chdir: work, in: File::NULL,              # <-- Not detached: Running? reaps it with wait2
                                out: File.join(work, 'Na__PainterlyAssets__LocalServer__Console__.log'), err: [:child, :out])
            { 'pid' => pid, 'token' => token, 'ready' => ready, 'override' => override, 'started' => Process.clock_gettime(Process::CLOCK_MONOTONIC), 'polling' => false }
        rescue SystemCallError, ArgumentError => error
            { 'error' => "The NPR server could not start (#{error.class}): #{error.message}" }
        end

        def self.na_poll
            job = @na_starting
            return unless job
            return if job['polling']

            job['polling'] = true
            begin
                _pid, status = Process.wait2(job['pid'], Process::WNOHANG)
                ready = Na__SafeFileWriter.Na__SafeFile__ReadJson(job['ready'])
                limit = Na__ConfigLoader.Na__Config__GetOr(15, 'nprViewport', 'server', 'startTimeoutSeconds').to_f
                if ready && ready['port'].to_i > 0
                    @na_server = { 'pid' => job['pid'], 'port' => ready['port'].to_i, 'token' => job['token'], 'override' => job['override'], 'version' => ready['version'].to_s }
                    self.na_end_start
                    Na__DebugTools.Na__Debug__Info("NPR server on 127.0.0.1:#{ready['port']} (pid #{job['pid']}).")
                    return self.na_finish('ok' => true, 'port' => ready['port'].to_i)
                end
                if status || Process.clock_gettime(Process::CLOCK_MONOTONIC) - job['started'] > limit
                    self.na_kill(job['pid']) if status.nil?
                    self.na_end_start
                    return self.na_finish('ok' => false, 'message' => status ? "The NPR server stopped as it started (code #{status.exitstatus.inspect}). See #{NA_LOG_FILE} in 90__AppCache__TempFilesCache." :
                                                                               "The NPR server did not answer within #{limit.round} seconds.")
                end
                job['polling'] = false
            rescue StandardError => error
                self.na_end_start
                Na__DebugTools.Na__Debug__Error('Starting the NPR server failed.', error)
                self.na_finish('ok' => false, 'message' => "The NPR server could not be started: #{error.message}")
            end
        end

        def self.na_end_start
            UI.stop_timer(@na_starting['timer']) if @na_starting && @na_starting['timer']
            @na_starting = nil
        end

        def self.na_kill(pid)
            Process.kill('KILL', pid)
            Process.wait2(pid)
        rescue SystemCallError
            nil
        end

        def self.na_finish(result)
            waiters = @na_waiters
            @na_waiters = []
            waiters.each do |block|
                begin
                    block.call(result)
                rescue StandardError => error
                    Na__DebugTools.Na__Debug__Error('An NPR server result could not be handled.', error)
                end
            end
            nil
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
