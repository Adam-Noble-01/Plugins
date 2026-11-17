# =============================================================================
# NA COMPONENT EDITOR TOOLS - LIBRARY MANAGER | EXTRACTOR
# =============================================================================
#
# FILE       : Na__ComponentEditorTools__LibraryManager__Extractor__.rb
# NAMESPACE  : Na__ComponentEditorTools::Na__LibraryExtractor
# PURPOSE    : Load a .skp file into the current model's definitions, extract
#              component name, description, attribute dictionaries, and save a
#              thumbnail PNG, then remove the temporary definition. Caches
#              results keyed by file path + mtime so large libraries are only
#              re-extracted when a file changes on disk.
# CREATED    : 2026
#
# READING THE LIBRARY IN STEPS (17-Nov-2026):
# - The Gallery's Scan and Refresh call ExtractAllInSteps: one file per timer
#   tick, so SketchUp stays usable and the status line shows progress. Before,
#   Refresh deleted the whole cache and read all ~334 files in one call on the
#   main thread (about 2 hours with the Agent Outliner's tracker watching), so
#   SketchUp looked crashed.
# - ONLY WHAT CHANGED IS READ: a cached read is kept while its key (path::mtime)
#   matches, it read without error and its thumbnail is still on disk. Cached
#   errors are always read again (the 22 SketchUp 2027 files failed under the
#   old reader and read now).
# - A FILE WAITS while a tool other than Select or a camera tool is active: a
#   tool mid-gesture (Move, Push/Pull, Rotate) holds an operation open, and a
#   read starts and aborts its own (SketchUp does not nest operations).
# - The per-file cache is written every NA_SAVE_EVERY files, so a SketchUp
#   closed mid-read keeps what it read; the end of a read writes only the files
#   scanned, which drops removed and renamed ones.
# - Files saved by a newer SketchUp are read with allow_newer: true and marked
#   newer_version; file_version is the version in the file's header.
#
# =============================================================================

require 'json'
require 'fileutils'

module Na__ComponentEditorTools
    module Na__LibraryExtractor

# -----------------------------------------------------------------------------
# REGION | Constants and State
# -----------------------------------------------------------------------------

        NA_SAVE_EVERY   = 10   unless defined?(NA_SAVE_EVERY)                          # <-- Files read between cache writes during a stepped read
        NA_STEP_S       = 0.01 unless defined?(NA_STEP_S)                              # <-- Pause between two files
        NA_WAIT_S       = 0.5  unless defined?(NA_WAIT_S)                              # <-- How often a waiting read looks at the tool again
        NA_STALL_S      = 120  unless defined?(NA_STALL_S)                             # <-- A read with no step for this long lost its timer: a new one may start
        NA_IDLE_TOOLS   = /\A(SelectionTool|Camera)/.freeze unless defined?(NA_IDLE_TOOLS)

        @na_run = nil unless defined?(@na_run)                                         # <-- The stepped read under way, or nil

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # Every entry in one call (scripts). The Gallery uses ExtractAllInSteps.
        def self.Na__ComponentEditorTools__ExtractAll(scan_entries)
            results = scan_entries.map do |entry|
                self.Na__ComponentEditorTools__ExtractEntry(entry)
            end

            self.Na__ComponentEditorTools__SaveCache(results)
            results
        end

        # FUNCTION | Read the Library One File per Timer Tick
        # ------------------------------------------------------------
        # Entries with a usable cached read are taken from the cache at once; the
        # rest are read one per tick. on_progress.call(info) after each file and
        # while waiting for a tool; on_done.call(results, info) at the end, results
        # in scan order. info: total, read, errors, current, waiting_for,
        # elapsed_s, cached. Returns false when a read is already under way.
        def self.Na__ComponentEditorTools__ExtractAllInSteps(scan_entries, on_progress: nil, on_done: nil)
            return false if self.Na__ComponentEditorTools__ExtractRunning?

            results = Array.new(scan_entries.length)
            todo    = []
            scan_entries.each_with_index do |entry, index|
                cached = self.Na__ComponentEditorTools__UsableCachedResult(entry)
                if cached
                    results[index] = cached
                else
                    todo << index
                end
            end

            now = self.na_clock
            @na_run = {
                entries:     scan_entries,
                results:     results,
                todo:        todo,
                total:       todo.length,
                cached:      scan_entries.length - todo.length,
                read:        0,
                errors:      0,
                current:     nil,
                waiting_for: nil,
                unsaved:     0,
                started:     now,
                stepped:     now,
                on_progress: on_progress,
                on_done:     on_done
            }
            self.na_book_step(NA_STEP_S)
            true
        end

        # FUNCTION | Is a Stepped Read Under Way?
        # ------------------------------------------------------------
        def self.Na__ComponentEditorTools__ExtractRunning?
            run = @na_run
            return false unless run

            if self.na_clock - run[:stepped].to_f > NA_STALL_S                           # <-- Its timer was lost (never seen, but a stuck read would block every Refresh)
                @na_run = nil
                return false
            end
            true
        end

        # FUNCTION | Where the Stepped Read Is (nil when none is under way)
        # ------------------------------------------------------------
        def self.Na__ComponentEditorTools__ExtractProgress
            run = @na_run
            run ? self.na_info(run) : nil
        end

        # FUNCTION | One Line for the Status Bar About a Read (info from the callbacks)
        # ------------------------------------------------------------
        def self.Na__ComponentEditorTools__ExtractStatusText(info = nil)
            info ||= self.Na__ComponentEditorTools__ExtractProgress
            return 'Library ready.' unless info

            done = "#{info[:read]} of #{info[:total]} new or changed file(s) read"
            if info[:waiting_for]
                "Library read waiting for the #{info[:waiting_for]} to finish (press Space for Select): #{done}."
            elsif info[:current]
                "Reading the library: #{done} (#{info[:current]})..."
            else
                "Reading the library: #{done}..."
            end
        end

        def self.Na__ComponentEditorTools__SaveLastResult(result_payload)
            result_path = Na__PathResolver.Na__ComponentEditorTools__LibraryLastResultFilePath
            self.na_write_json(result_path, result_payload)
        rescue => error
            puts "[Na__ComponentEditorTools] SaveLastResult warning: #{error.class}: #{error.message}"
        end

        def self.Na__ComponentEditorTools__LoadLastResult
            result_path = Na__PathResolver.Na__ComponentEditorTools__LibraryLastResultFilePath
            return nil unless File.exist?(result_path)

            raw = File.read(result_path, encoding: 'UTF-8')
            parsed = JSON.parse(raw)
            return nil unless parsed.is_a?(Hash) && parsed['entries'].is_a?(Array)

            parsed
        rescue => error
            puts "[Na__ComponentEditorTools] LoadLastResult warning: #{error.class}: #{error.message}"
            nil
        end

        def self.Na__ComponentEditorTools__PurgeLastResult
            result_path = Na__PathResolver.Na__ComponentEditorTools__LibraryLastResultFilePath
            File.delete(result_path) if File.exist?(result_path)
        rescue
            nil
        end

        def self.Na__ComponentEditorTools__ExtractEntry(entry)
            cached = self.Na__ComponentEditorTools__UsableCachedResult(entry)
            return cached if cached

            self.Na__ComponentEditorTools__ExtractFromFile(entry)
        end

        # A cached read still good for this entry: same key (path::mtime), read
        # without error, and its thumbnail still on disk. nil otherwise.
        def self.Na__ComponentEditorTools__UsableCachedResult(entry)
            cache_key = entry[:cache_key] || entry['cache_key']
            cached = self.Na__ComponentEditorTools__CachedResult(cache_key)
            return nil unless cached.is_a?(Hash) && cached['ok']
            return nil unless self.na_thumbnail_present?(cached['thumbnail_uri'])

            cached
        end

        def self.Na__ComponentEditorTools__InvalidateCache
            @na_extract_cache = nil
            cache_path = Na__PathResolver.Na__ComponentEditorTools__LibraryCacheFilePath
            File.delete(cache_path) if File.exist?(cache_path)
        rescue
            nil
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Extraction
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__ExtractFromFile(entry)
            file_path     = entry[:path] || entry['path']
            file_name     = entry[:file_name] || entry['file_name']
            relative_dir  = entry[:relative_dir] || entry['relative_dir']
            relative_path = entry[:relative_path] || entry['relative_path']
            mtime         = entry[:mtime] || entry['mtime']
            cache_key     = entry[:cache_key] || entry['cache_key']

            return self.Na__ComponentEditorTools__ErrorResult(entry, 'File not found.') unless File.exist?(file_path.to_s)

            # Read inside an operation that is always aborted, so nested definitions
            # are not left behind and a component placed in the open model is never
            # removed (see Na__ComponentEditorTools__LibraryManager__SafeLoad__.rb).
            # A read only: a file saved by a newer SketchUp is read with allow_newer.
            def_name, def_description, attribute_data, thumbnail_uri, library_data, newer_version =
                Na__LibrarySafeLoad.Na__ComponentEditorTools__WithTemporaryDefinition(file_path, 'Read library component', allow_newer: true) do |definition, load_info|
                    [
                        definition.name.to_s,
                        definition.description.to_s,
                        self.Na__ComponentEditorTools__ExtractAttributes(definition),
                        self.Na__ComponentEditorTools__SaveThumbnail(definition, file_path),
                        Na__LibrarySerializer.Na__ComponentEditorTools__ReadFromDefinition(definition),
                        load_info[:newer_version] ? true : false
                    ]
                end

            result = {
                'cache_key'        => cache_key,
                'path'             => file_path,
                'file_name'        => file_name,
                'relative_dir'     => relative_dir,
                'relative_path'    => relative_path,
                'mtime'            => mtime,
                'def_name'         => def_name,
                'description'      => def_description,
                'attributes'       => attribute_data,
                'thumbnail_uri'    => thumbnail_uri,
                'code'             => library_data['code'],
                'code_stored'      => library_data['code_stored'],
                'code_derived'     => library_data['code_derived'],
                'gallery_name'     => library_data['gallery_name'],
                'notes'            => library_data['notes'],
                'category'         => library_data['category'],
                'type'             => library_data['type'],
                'truevision_valid' => library_data['truevision_valid'],
                'custom'           => library_data['custom'],
                'file_version'     => Na__LibrarySafeLoad.Na__ComponentEditorTools__FileVersion(file_path).to_s,
                'newer_version'    => newer_version,
                'ok'               => true
            }

            self.Na__ComponentEditorTools__StoreInCache(cache_key, result)
            result
        rescue => error
            self.Na__ComponentEditorTools__ErrorResult(entry, "#{error.class}: #{error.message}")
        end

        def self.Na__ComponentEditorTools__ExtractAttributes(definition)
            dictionaries = definition.attribute_dictionaries
            return {} unless dictionaries

            result = {}
            dictionaries.each do |dict|
                dict_data = {}
                dict.each_pair { |k, v| dict_data[k.to_s] = v.to_s }
                result[dict.name.to_s] = dict_data
            end
            result
        rescue
            {}
        end

        def self.Na__ComponentEditorTools__SaveThumbnail(definition, source_path)
            thumb_dir = Na__PathResolver.Na__ComponentEditorTools__LibraryThumbnailCacheDirectory
            FileUtils.mkdir_p(thumb_dir)

            safe_name = File.basename(source_path, '.skp').gsub(/[^A-Za-z0-9_-]/, '_')
            thumb_path = File.join(thumb_dir, "#{safe_name}.png")

            definition.save_thumbnail(thumb_path)

            return '' unless File.exist?(thumb_path)

            normalized = thumb_path.tr('\\', '/').sub(%r{^/+}, '')
            'file:///' + normalized.gsub(' ', '%20')
        rescue
            ''
        end

        def self.Na__ComponentEditorTools__ErrorResult(entry, message_text)
            {
                'cache_key'        => (entry[:cache_key] || entry['cache_key'] || ''),
                'path'             => (entry[:path] || entry['path'] || ''),
                'file_name'        => (entry[:file_name] || entry['file_name'] || ''),
                'relative_dir'     => (entry[:relative_dir] || entry['relative_dir'] || ''),
                'relative_path'    => (entry[:relative_path] || entry['relative_path'] || ''),
                'mtime'            => (entry[:mtime] || entry['mtime'] || 0),
                'def_name'         => '',
                'description'      => '',
                'attributes'       => {},
                'thumbnail_uri'    => '',
                'code'             => '',
                'code_stored'      => '',
                'code_derived'     => '',
                'gallery_name'     => '',
                'notes'            => '',
                'category'         => '',
                'type'             => '',
                'truevision_valid' => '',
                'custom'           => {},
                'ok'               => false,
                'error'            => message_text
            }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Stepped Read (one file per timer tick)
# -----------------------------------------------------------------------------

        def self.na_book_step(delay)
            UI.start_timer(delay, false) do
                Na__ComponentEditorTools::Na__LibraryExtractor.na_step
            end
        end

        def self.na_step
            run = @na_run
            return unless run

            run[:stepped] = self.na_clock
            return self.na_finish(run) if run[:todo].empty?

            busy = self.na_busy_tool
            if busy
                run[:waiting_for] = busy
                self.na_tell(run[:on_progress], self.na_info(run))
                return self.na_book_step(NA_WAIT_S)
            end
            run[:waiting_for] = nil

            index = run[:todo].shift
            entry = run[:entries][index]
            run[:current] = (entry[:file_name] || entry['file_name']).to_s
            result = self.Na__ComponentEditorTools__ExtractFromFile(entry)
            run[:results][index] = result
            run[:read]   += 1
            run[:errors] += 1 unless result['ok']
            run[:unsaved] += 1
            if run[:unsaved] >= NA_SAVE_EVERY
                self.na_save_cache_now
                run[:unsaved] = 0
            end
            self.na_tell(run[:on_progress], self.na_info(run))
            run[:stepped] = self.na_clock                                               # <-- After the file too: a slow file is not a lost timer
            self.na_book_step(NA_STEP_S)
        rescue StandardError => error
            # A fault here must not leave a read standing that blocks every Refresh.
            puts "[Na__ComponentEditorTools] Library read stopped: #{error.class}: #{error.message}"
            @na_run = nil
            info = run ? self.na_info(run).merge(error: "#{error.class}: #{error.message}") : { error: error.message }
            self.na_tell(run && run[:on_done], nil, info)
        end

        def self.na_finish(run)
            @na_run = nil
            run[:current] = nil
            results = run[:results].each_with_index.map do |result, index|
                result || self.Na__ComponentEditorTools__ErrorResult(run[:entries][index], 'Not read.')
            end
            self.Na__ComponentEditorTools__SaveCache(results)
            self.na_tell(run[:on_done], results, self.na_info(run))
        end

        def self.na_info(run)
            {
                total:       run[:total],
                read:        run[:read],
                errors:      run[:errors],
                cached:      run[:cached],
                current:     run[:current],
                waiting_for: run[:waiting_for],
                elapsed_s:   (self.na_clock - run[:started].to_f).round(1)
            }
        end

        # Calls a callback; a fault in it is reported, never raised into the read.
        def self.na_tell(callback, *args)
            return unless callback

            callback.call(*args)
        rescue StandardError => error
            puts "[Na__ComponentEditorTools] Library read callback warning: #{error.class}: #{error.message}"
        end

        # The active tool's name when it is not Select or a camera tool (one of
        # those may be mid-gesture with an operation open), else nil.
        def self.na_busy_tool
            model = Sketchup.active_model
            return nil unless model

            name = model.tools.active_tool_name.to_s
            return nil if name.empty? || name =~ NA_IDLE_TOOLS

            name
        rescue StandardError
            nil
        end

        # A thumbnail_uri ('file:///C:/.../x.png', spaces as %20) still on disk.
        # An empty one never had a thumbnail: reading again would not make one.
        def self.na_thumbnail_present?(uri)
            text = uri.to_s
            return true if text.empty?

            File.exist?(text.sub(%r{\Afile:///}, '').gsub('%20', ' '))
        end

        def self.na_clock
            Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Cache Helpers
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__Cache
            return @na_extract_cache if @na_extract_cache

            cache_path = Na__PathResolver.Na__ComponentEditorTools__LibraryCacheFilePath

            @na_extract_cache = if File.exist?(cache_path)
                                    begin
                                        JSON.parse(File.read(cache_path, encoding: 'UTF-8'))
                                    rescue JSON::ParserError
                                        {}
                                    end
                                else
                                    {}
                                end
        end

        def self.Na__ComponentEditorTools__CachedResult(cache_key)
            self.Na__ComponentEditorTools__Cache[cache_key.to_s]
        end

        def self.Na__ComponentEditorTools__StoreInCache(cache_key, result_hash)
            self.Na__ComponentEditorTools__Cache[cache_key.to_s] = result_hash
        end

        def self.Na__ComponentEditorTools__SaveCache(results_array)
            cache_path = Na__PathResolver.Na__ComponentEditorTools__LibraryCacheFilePath

            cache_hash = {}
            results_array.each do |result|
                key = result['cache_key'] || result[:cache_key]
                cache_hash[key.to_s] = result if key
            end

            self.na_write_json(cache_path, cache_hash)
            @na_extract_cache = cache_hash
        rescue => error
            puts "[Na__ComponentEditorTools] Extractor cache save warning: #{error.class}: #{error.message}"
        end

        # The cache as it stands (old entries and this read's), mid-read.
        def self.na_save_cache_now
            self.na_write_json(Na__PathResolver.Na__ComponentEditorTools__LibraryCacheFilePath, self.Na__ComponentEditorTools__Cache)
        rescue => error
            puts "[Na__ComponentEditorTools] Extractor cache save warning: #{error.class}: #{error.message}"
        end

        # Written beside the file and moved over it, so a reader (another SketchUp
        # window shares these files) never finds half a file.
        def self.na_write_json(path, data)
            FileUtils.mkdir_p(File.dirname(path))
            temp = "#{path}.#{Process.pid}.tmp"
            File.write(temp, JSON.pretty_generate(data), encoding: 'UTF-8')
            File.delete(path) if File.exist?(path)
            File.rename(temp, path)
        end

# endregion -------------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
