# =============================================================================
# NA PAINTERLYNPR ASSETS - APP UTILS - PATH RESOLVER
# =============================================================================
#
# FILE       : Na__PainterlyAssets__AppUtils__PathResolver__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__PathResolver
# PURPOSE    : Where things are: the PainterlyNPR folder and the files inside it
#              the plugin reads, the Python interpreter that runs PainterlyNPR's
#              build utility, file:/// URIs for the dialog's pictures, and the
#              path length SketchUp's Ruby can open.
# CREATED    : 30-Oct-2026
#
# DESCRIPTION:
# - The library lives in another repo, so it cannot be found from __FILE__.
#   The folder is the one Settings chose on this PC, else the first of the
#   config's rootCandidates that holds the register. Nothing is hard-coded in
#   source; nothing machine-specific is ever written into a model.
# - SketchUp 2026 embeds its own CPython and exports PYTHONHOME / PYTHONPATH,
#   which poison an external python.exe (it prints nothing and exits 0). The
#   interpreter is an absolute python.exe found on disk (never the Windows
#   Store stub), run as pythonw.exe beside it where there is one so no console
#   window flashes, with -I (isolated: no PYTHON* variables, no user site) and
#   -X utf8. See Na__BuildUtil for the run itself.
#
# =============================================================================

module Na__PainterlyAssets
    module Na__PathResolver

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_PATH_LIMIT_FALLBACK = 259 unless defined?(NA_PATH_LIMIT_FALLBACK)                         # <-- SketchUp's Ruby cannot open a path over 259, long paths on or not

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | The PainterlyNPR Folder
    # -------------------------------------------------------------------------

        # FUNCTION | Resolve the PainterlyNPR Folder
        # ------------------------------------------------------------
        # @return [Hash] { 'root' => String|nil, 'source' => 'chosen'|'default'|nil, 'tried' => [String] }
        def self.Na__Paths__RootResolution
            tried      = []
            candidates = []
            chosen     = Na__UserConfigStore.Na__UserConfig__Get('library', 'root')
            candidates << [chosen, 'chosen'] if chosen.is_a?(String) && !chosen.strip.empty?
            Array(Na__ConfigLoader.Na__Config__Get('library', 'rootCandidates')).each { |path| candidates << [path, 'default'] }

            candidates.each do |path, source|
                clean = self.Na__Paths__Clean(path)
                tried << clean
                return { 'root' => clean, 'source' => source, 'tried' => tried } if self.Na__Paths__IsRoot?(clean)
            end
            { 'root' => nil, 'source' => nil, 'tried' => tried }
        end
        # ---------------------------------------------------------------

        def self.Na__Paths__Root
            self.Na__Paths__RootResolution['root']
        end

        # A PainterlyNPR folder is one that holds the library's register.
        def self.Na__Paths__IsRoot?(path)
            return false if path.nil? || path.to_s.empty?
            File.file?(File.join(path, self.na_library_folder, self.na_config('registerFile', 'PainterlyNPR__AssetLibrary__Register__.json')))
        end

        # FUNCTION | A Folder Chosen in Settings, as the PainterlyNPR Folder
        # ------------------------------------------------------------
        # Accepts the repo folder itself or its 12__Data__AssetLibrary, the two
        # a person is likely to pick. nil when neither holds the register.
        def self.Na__Paths__NormaliseChosenRoot(path)
            clean = self.Na__Paths__Clean(path)
            clean = File.dirname(clean) if File.basename(clean) == self.na_library_folder
            self.Na__Paths__IsRoot?(clean) ? clean : nil
        end
        # ---------------------------------------------------------------

        # Forward slashes throughout: a backslash is Dir.glob's escape character.
        def self.Na__Paths__Clean(path)
            File.expand_path(path.to_s.strip).tr('\\', '/')
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Files in the PainterlyNPR Folder
    # -------------------------------------------------------------------------

        def self.Na__Paths__Library(root = self.Na__Paths__Root)
            root && File.join(root, self.na_library_folder)
        end

        def self.Na__Paths__Register(root = self.Na__Paths__Root)
            root && File.join(self.Na__Paths__Library(root), self.na_config('registerFile', 'PainterlyNPR__AssetLibrary__Register__.json'))
        end

        def self.Na__Paths__Index(root = self.Na__Paths__Root)
            root && File.join(self.Na__Paths__Library(root), self.na_config('indexFile', 'PainterlyNPR__AssetLibrary__Index__.json'))
        end

        # FUNCTION | A File Named in the Config's library Section, From the Repo Folder
        # ------------------------------------------------------------
        # @param key [String] datSchema, buildUtil, generators, materials or organics
        def self.Na__Paths__RootFile(key, root = self.Na__Paths__Root)
            relative = self.na_config(key, nil)
            root && relative ? File.join(root, relative) : nil
        end
        # ---------------------------------------------------------------

        def self.Na__Paths__CacheDir
            FileUtils.mkdir_p(Na__PainterlyAssets::NA_CACHE_DIR)
            Na__PainterlyAssets::NA_CACHE_DIR
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Path Length and URIs
    # -------------------------------------------------------------------------

        def self.Na__Paths__Limit
            Na__ConfigLoader.Na__Config__GetOr(NA_PATH_LIMIT_FALLBACK, 'library', 'pathLimit').to_i
        end

        def self.Na__Paths__TooLong?(path)
            path.to_s.length > self.Na__Paths__Limit
        end

        # FUNCTION | A file:/// URI the Dialog Can Load a Picture From
        # ------------------------------------------------------------
        # Each segment percent-encoded (a space, a #, a % or a non-ASCII letter
        # in a folder name would otherwise break the URL); the drive stays as
        # it is. Chromium ignores a ?v= query on a file URL, which is what lets
        # a picture re-rendered by the factory show without a stale cache.
        def self.Na__Paths__FileUri(path, version = nil)
            segments = self.Na__Paths__Clean(path).split('/')
            encoded  = segments.each_with_index.map do |segment, index|
                index.zero? && segment =~ /\A[A-Za-z]:\z/ ? segment : self.na_uri_escape(segment)
            end
            uri = "file:///#{encoded.join('/')}"
            version.nil? || version.to_s.empty? ? uri : "#{uri}?v=#{self.na_uri_escape(version.to_s)}"
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Python
    # -------------------------------------------------------------------------

        # FUNCTION | The Python That Runs PainterlyNPR's Build Utility
        # ------------------------------------------------------------
        # 1. Settings' choice on this PC, 2. the config's executable, 3. the
        # newest Python 3 found at the config's searchPatterns, 4. python.exe on
        # PATH outside WindowsApps. Only absolute files that exist count, so the
        # Store stub (which runs, prints nothing and exits 0) is never taken.
        #
        # @return [Hash, nil] { 'exe', 'console', 'source', 'windowless' }
        def self.Na__Paths__Python
            chosen = Na__UserConfigStore.Na__UserConfig__Get('python', 'executable')
            return self.na_python_record(chosen, 'chosen') if self.na_real_python?(chosen)

            configured = Na__ConfigLoader.Na__Config__Get('python', 'executable')
            return self.na_python_record(configured, 'config') if self.na_real_python?(configured)

            self.na_discovered_pythons.each { |exe| return self.na_python_record(exe, 'found') }

            ENV['PATH'].to_s.split(File::PATH_SEPARATOR).each do |dir|
                exe = File.join(dir.tr('\\', '/'), 'python.exe')
                return self.na_python_record(exe, 'path') if self.na_real_python?(exe)
            end
            nil
        end
        # ---------------------------------------------------------------

        def self.na_real_python?(path)
            return false unless path.is_a?(String) && !path.strip.empty?
            clean = path.tr('\\', '/')
            return false if clean.downcase.include?('/windowsapps/')                                    # <-- The Store stub
            File.file?(clean)
        end

        # Newest first: Python313 before Python312 before Python39.
        def self.na_discovered_pythons
            patterns = Array(Na__ConfigLoader.Na__Config__Get('python', 'searchPatterns'))
            found    = patterns.flat_map do |pattern|
                expanded = pattern.to_s.gsub(/%([A-Za-z_]+)%/) { ENV[Regexp.last_match(1)].to_s.tr('\\', '/') }
                expanded.start_with?('/') ? [] : Dir.glob(expanded)                                     # <-- An unset %VARIABLE% leaves a bare /Programs/...: skip it
            end
            found.select { |exe| self.na_real_python?(exe) }
                 .uniq { |exe| exe.downcase }
                 .sort_by { |exe| -(exe[/Python3(\d+)/i, 1] || '0').to_i }
        end

        def self.na_python_record(console_exe, source)
            console    = console_exe.tr('\\', '/')
            windowless = File.join(File.dirname(console), 'pythonw.exe')
            use_w      = Na__ConfigLoader.Na__Config__GetOr(true, 'python', 'preferWindowless') != false && File.file?(windowless)
            { 'exe' => use_w ? windowless : console, 'console' => console, 'source' => source, 'windowless' => use_w }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals
    # -------------------------------------------------------------------------

        def self.na_config(key, fallback)
            Na__ConfigLoader.Na__Config__GetOr(fallback, 'library', key)
        end

        def self.na_library_folder
            self.na_config('libraryFolder', '12__Data__AssetLibrary')
        end

        # String#b, not force_encoding('BINARY'): the name lookup is missing from
        # the embedded Ruby the offline suites run on.
        def self.na_uri_escape(segment)
            segment.to_s.b.gsub(/[^A-Za-z0-9_.~\-]/n) { |char| format('%%%02X', char.ord) }
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
