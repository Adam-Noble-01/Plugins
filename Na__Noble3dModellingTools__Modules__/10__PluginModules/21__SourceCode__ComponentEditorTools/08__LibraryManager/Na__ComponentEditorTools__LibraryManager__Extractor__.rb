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
# =============================================================================

require 'json'
require 'fileutils'

module Na__ComponentEditorTools
    module Na__LibraryExtractor

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__ExtractAll(scan_entries)
            results = scan_entries.map do |entry|
                self.Na__ComponentEditorTools__ExtractEntry(entry)
            end

            self.Na__ComponentEditorTools__SaveCache(results)
            results
        end

        def self.Na__ComponentEditorTools__SaveLastResult(result_payload)
            result_path = Na__PathResolver.Na__ComponentEditorTools__LibraryLastResultFilePath
            FileUtils.mkdir_p(File.dirname(result_path))
            File.write(result_path, JSON.pretty_generate(result_payload), encoding: 'UTF-8')
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
            cache_key = entry[:cache_key] || entry['cache_key']
            file_path = entry[:path] || entry['path']

            cached = self.Na__ComponentEditorTools__CachedResult(cache_key)
            return cached if cached

            self.Na__ComponentEditorTools__ExtractFromFile(entry)
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

            model = Sketchup.active_model
            definition = model.definitions.load(file_path)
            raise 'Could not load component definition.' unless definition

            def_name        = definition.name.to_s
            def_description = definition.description.to_s
            attribute_data  = self.Na__ComponentEditorTools__ExtractAttributes(definition)
            thumbnail_uri   = self.Na__ComponentEditorTools__SaveThumbnail(definition, file_path)
            library_data    = Na__LibrarySerializer.Na__ComponentEditorTools__ReadFromDefinition(definition)

            model.definitions.remove(definition) rescue nil

            result = {
                'cache_key'     => cache_key,
                'path'          => file_path,
                'file_name'     => file_name,
                'relative_dir'  => relative_dir,
                'relative_path' => relative_path,
                'mtime'         => mtime,
                'def_name'      => def_name,
                'description'   => def_description,
                'attributes'    => attribute_data,
                'thumbnail_uri' => thumbnail_uri,
                'code'          => library_data['code'],
                'code_stored'   => library_data['code_stored'],
                'code_derived'  => library_data['code_derived'],
                'gallery_name'  => library_data['gallery_name'],
                'notes'         => library_data['notes'],
                'category'      => library_data['category'],
                'type'          => library_data['type'],
                'custom'        => library_data['custom'],
                'ok'            => true
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
                'cache_key'     => (entry[:cache_key] || entry['cache_key'] || ''),
                'path'          => (entry[:path] || entry['path'] || ''),
                'file_name'     => (entry[:file_name] || entry['file_name'] || ''),
                'relative_dir'  => (entry[:relative_dir] || entry['relative_dir'] || ''),
                'relative_path' => (entry[:relative_path] || entry['relative_path'] || ''),
                'mtime'         => (entry[:mtime] || entry['mtime'] || 0),
                'def_name'      => '',
                'description'   => '',
                'attributes'    => {},
                'thumbnail_uri' => '',
                'code'          => '',
                'code_stored'   => '',
                'code_derived'  => '',
                'gallery_name'  => '',
                'notes'         => '',
                'category'      => '',
                'type'          => '',
                'custom'        => {},
                'ok'            => false,
                'error'         => message_text
            }
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
            FileUtils.mkdir_p(File.dirname(cache_path))

            cache_hash = {}
            results_array.each do |result|
                key = result['cache_key'] || result[:cache_key]
                cache_hash[key.to_s] = result if key
            end

            File.write(cache_path, JSON.pretty_generate(cache_hash), encoding: 'UTF-8')
            @na_extract_cache = cache_hash
        rescue => error
            puts "[Na__ComponentEditorTools] Extractor cache save warning: #{error.class}: #{error.message}"
        end

# endregion -------------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
