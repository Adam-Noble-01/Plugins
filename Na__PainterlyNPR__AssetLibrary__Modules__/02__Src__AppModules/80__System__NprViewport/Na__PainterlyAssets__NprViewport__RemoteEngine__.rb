# =============================================================================
# NA PAINTERLYNPR ASSETS - NPR VIEWPORT - REMOTE ENGINE
# =============================================================================
#
# FILE       : Na__PainterlyAssets__NprViewport__RemoteEngine__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__RemoteEngine
# PURPOSE    : PainterlyNPR's render engine, from its GitHub repo, cached on
#              this PC (93__RemoteCache__CoreEngine): is it there, which commit
#              it is, and Reload Remote Plugin Files, which downloads the
#              branch's latest commit again.
# CREATED    : 01-Nov-2026
#
# DESCRIPTION:
# - THE ENGINE IS ALWAYS THE REPO'S (Adam, 01-Nov-2026: "It should always
#   call the render engine because we will be working on that centralised
#   repo for any render engine edits"). Nothing of it is in this plugin: the
#   cache is the repo's own files at one commit, and the NPR windows run the
#   repo's own page from it.
# - The download is Na__PainterlyAssets__NprViewport__RemoteFetch__.py under
#   pythonw.exe (no console window), with git and this PC's own GitHub
#   credentials, followed by a repeating timer as the build utility's runs
#   are, so SketchUp never waits. It downloads only when the cache is missing
#   or when Reload Remote Plugin Files asks.
# - A local PainterlyNPR folder can stand in for the cache while the engine
#   itself is being worked on (engine.localOverrideFolder in the viewport's
#   user config): served as commit 'local', never cached.
#
# =============================================================================

module Na__PainterlyAssets
    module Na__RemoteEngine

    # -------------------------------------------------------------------------
    # REGION | Constants and State
    # -------------------------------------------------------------------------

        NA_STATE_FILE   = 'Na__PainterlyAssets__RemoteCache__State__.json'.freeze          unless defined?(NA_STATE_FILE)
        NA_FETCH_SCRIPT = 'Na__PainterlyAssets__NprViewport__RemoteFetch__.py'.freeze      unless defined?(NA_FETCH_SCRIPT)
        NA_APP_PAGE     = 'PainterlyNPR__App__.html'.freeze                                unless defined?(NA_APP_PAGE)
        NA_POLL_SECONDS = 0.25                                                             unless defined?(NA_POLL_SECONDS)

        @na_job     = nil unless defined?(@na_job)                                            # <-- The download in flight
        @na_waiters = []  unless defined?(@na_waiters)                                        # <-- Blocks to call when it ends

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | What Is Cached
    # -------------------------------------------------------------------------

        def self.Na__Remote__Root
            FileUtils.mkdir_p(Na__PainterlyAssets::NA_REMOTE_CACHE_DIR)
            Na__PainterlyAssets::NA_REMOTE_CACHE_DIR
        end

        def self.Na__Remote__State
            Na__SafeFileWriter.Na__SafeFile__ReadJson(File.join(self.Na__Remote__Root, NA_STATE_FILE))
        end

        # A local engine folder chosen in the user config, when it holds the app page
        def self.Na__Remote__Override
            folder = Na__ViewportConfig.Na__ViewportConfig__Get('engine', 'localOverrideFolder', '').to_s.strip
            return nil if folder.empty?
            clean = File.expand_path(folder).tr('\\', '/')
            File.file?(File.join(clean, NA_APP_PAGE)) ? clean : nil
        end

        # FUNCTION | The Engine the Windows Load: { 'commit', 'folder', 'appVersion', ... } or nil
        # ------------------------------------------------------------
        # commit is the server's path segment: the cache's short commit, or
        # 'local' for an override folder.
        def self.Na__Remote__Current
            override = self.Na__Remote__Override
            return { 'commit' => 'local', 'folder' => override, 'appVersion' => 'local', 'source' => 'override', 'url' => nil } if override

            state = self.Na__Remote__State
            return nil unless state.is_a?(Hash) && state['Folder'].to_s =~ /\APainterlyNPR__[0-9a-f]{7}\z/
            folder = File.join(self.Na__Remote__Root, state['Folder'])
            return nil unless File.file?(File.join(folder, NA_APP_PAGE))
            {
                'commit'     => state['CommitShort'],
                'folder'     => folder,
                'appVersion' => state['AppVersion'],
                'fetchedIso' => state['FetchedIso'],
                'url'        => state['Url'],
                'branch'     => state['Branch'],
                'files'      => state['Files'],
                'bytes'      => state['Bytes'],
                'source'     => 'cache'
            }
        end
        # ---------------------------------------------------------------

        def self.Na__Remote__Busy?
            !@na_job.nil?
        end

        # FUNCTION | Does This Plugin Want More of the Repo Than the Cache Holds?
        # ------------------------------------------------------------
        # The cache's state records the patterns it was downloaded with. A plugin
        # that asks for others (v0.4.0: the asset library's pictures, for the
        # viewport's Assets drawer) tops the cache up once, by itself. Never for
        # an override folder, which holds everything.
        def self.Na__Remote__Outdated?
            return false if self.Na__Remote__Override
            state = self.Na__Remote__State
            return false unless state.is_a?(Hash)
            wanted = Array((Na__ConfigLoader.Na__Config__Get('nprViewport', 'remoteEngine') || {})['patterns'])
            Array(state['Patterns']) != wanted
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Downloading
    # -------------------------------------------------------------------------

        # FUNCTION | Download the Branch's Latest Commit (force: even when it is the cached one)
        # ------------------------------------------------------------
        # @yield [Hash] { 'ok', 'changed', 'commit', 'appVersion', 'message', 'seconds' }; always called once.
        #   A second request while one runs waits for the same download.
        def self.Na__Remote__Fetch(force: false, &on_done)
            @na_waiters << on_done if on_done
            return true if self.Na__Remote__Busy?

            launch = self.na_launch(force)
            if launch['error']
                self.na_finish('ok' => false, 'message' => launch['error'])
                return false
            end
            @na_job = launch
            @na_job['timer'] = UI.start_timer(NA_POLL_SECONDS, true) { Na__PainterlyAssets::Na__RemoteEngine.na_poll }
            Na__DebugTools.Na__Debug__Info("Downloading PainterlyNPR from #{launch['url']} (#{launch['branch']})#{force ? ', forced' : ''}.")
            true
        end
        # ---------------------------------------------------------------

        def self.na_launch(force)
            python = Na__PathResolver.Na__Paths__Python
            return { 'error' => 'No Python 3 was found, so PainterlyNPR cannot be downloaded. Install Python 3, or choose python.exe in the Asset Library\'s Settings.' } unless python

            section  = Na__ConfigLoader.Na__Config__Get('nprViewport', 'remoteEngine') || {}
            url      = section['url'].to_s
            branch   = section['branch'].to_s.empty? ? 'main' : section['branch'].to_s
            patterns = Array(section['patterns'])
            return { 'error' => 'The plugin config names no GitHub repo for PainterlyNPR (nprViewport.remoteEngine.url).' } if url.empty? || patterns.empty?

            root     = self.Na__Remote__Root
            work     = Na__PathResolver.Na__Paths__CacheDir
            pattern_file = File.join(work, 'Na__PainterlyAssets__RemoteFetch__Patterns__.json')
            result_file  = File.join(work, 'Na__PainterlyAssets__RemoteFetch__Result__.json')
            log_file     = File.join(work, 'Na__PainterlyAssets__RemoteFetch__Run__.log')
            Na__SafeFileWriter.Na__SafeFile__WriteJson(pattern_file, patterns, 4)
            File.delete(result_file) if File.exist?(result_file)

            script  = File.join(__dir__, NA_FETCH_SCRIPT)
            command = [python['exe'], '-I', '-X', 'utf8', script, '--url', url, '--branch', branch, '--cache-root', root,
                       '--patterns', pattern_file, '--result', result_file]
            command += ['--git', section['git'].to_s] unless section['git'].to_s.empty?
            command << '--force' if force
            pid = Process.spawn(Na__BuildUtil::NA_CLEAN_ENV, *command, chdir: root, in: File::NULL, out: log_file, err: [:child, :out])
            { 'pid' => pid, 'url' => url, 'branch' => branch, 'result' => result_file, 'log' => log_file,
              'started' => Process.clock_gettime(Process::CLOCK_MONOTONIC), 'polling' => false }
        rescue SystemCallError, ArgumentError => error
            { 'error' => "The download could not start (#{error.class}): #{error.message}" }
        end

        def self.na_poll
            job = @na_job
            return unless job
            return if job['polling']

            job['polling'] = true
            begin
                _pid, status = Process.wait2(job['pid'], Process::WNOHANG)
                elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - job['started']
                limit   = Na__ConfigLoader.Na__Config__GetOr(300, 'nprViewport', 'remoteEngine', 'timeoutSeconds').to_f
                if status.nil? && elapsed < limit
                    job['polling'] = false
                    return
                end
                if status.nil?
                    begin
                        Process.kill('KILL', job['pid'])
                        Process.wait2(job['pid'])
                    rescue SystemCallError
                        nil
                    end
                end
                result = Na__SafeFileWriter.Na__SafeFile__ReadJson(job['result'])
                result ||= { 'ok' => false, 'message' => status.nil? ? "The download took longer than #{limit.round} seconds and was stopped." :
                                                                     "The download ended without a result (code #{status.exitstatus.inspect}). See #{File.basename(job['log'])}." }
                UI.stop_timer(job['timer']) if job['timer']
                @na_job = nil
                self.na_finish(result)
            rescue StandardError => error
                UI.stop_timer(job['timer']) if job['timer']
                @na_job = nil
                Na__DebugTools.Na__Debug__Error('Following the PainterlyNPR download failed.', error)
                self.na_finish('ok' => false, 'message' => "The download could not be followed: #{error.message}")
            end
        end

        def self.na_finish(result)
            level = result['ok'] ? 'Info' : 'Warn'
            Na__DebugTools.send("Na__Debug__#{level}", "PainterlyNPR download: #{result['message']}")
            waiters = @na_waiters
            @na_waiters = []
            waiters.each do |block|
                begin
                    block.call(result)
                rescue StandardError => error
                    Na__DebugTools.Na__Debug__Error('A PainterlyNPR download result could not be handled.', error)
                end
            end
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
