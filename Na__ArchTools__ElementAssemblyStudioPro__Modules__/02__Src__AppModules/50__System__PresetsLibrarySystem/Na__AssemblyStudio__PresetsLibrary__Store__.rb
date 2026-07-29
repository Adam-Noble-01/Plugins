# frozen_string_literal: true

# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - PRESETS LIBRARY STORE
# =============================================================================
#
# FILE       : Na__AssemblyStudio__PresetsLibrary__Store__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__PresetsLibrarySystem
# MODULE     : Na__Store
# AUTHOR     : Noble Architecture
# CREATED    : 2026
# PURPOSE    : File-system store for the Presets Gallery. Owns the
#              05__Data__PresetsLibrary folder scan/parse/validate cycle,
#              EAS code allocation, preset file naming, the column-aligned
#              pretty JSON writer, new-file writes and in-place meta/config
#              patches (.bak backup before every overwrite).
#
# DESCRIPTION
# - Preset files are named Na__<CODE>__<Family>Preset__<SafeName>__.json with
#   CODE allocated via the AppConfig codeFormat (EAS%03d -> EAS001, ...).
# - The scanner reads top-level *.json only (01__Archive/ and .bak files are
#   never seen), skips zero-byte files and schema-gates every parse; a bad
#   file is debug-warned and skipped, never fatal to the scan.
# - Every patch validates the source path against the presets folder
#   (traversal guard), writes <file>.bak of the ORIGINAL raw content and
#   rewrites through the same pretty writer so on-disk diffs stay clean.
# - All records / results returned to callers are string-keyed camelCase
#   hashes ready to cross the JS bridge unchanged.
# =============================================================================

require 'json'
require 'fileutils'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../02__AppData/Na__AssemblyStudio__AppData__ConfigLoader__'

module Na__AssemblyStudio
    module Na__PresetsLibrarySystem
        module Na__Store

            DebugTools   = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
            ConfigLoader = Na__AssemblyStudio::Na__AppData::Na__ConfigLoader

            # -----------------------------------------------------------------
            # REGION | Module Constants and Path Resolution
            # -----------------------------------------------------------------

            NA_MODULE_DIR   = File.dirname(__FILE__)
            NA_MODULES_ROOT = File.expand_path('../..', NA_MODULE_DIR)

            NA_FAMILY_SEGMENTS      = ['Window', 'ExteriorDoor', 'InteriorDoor'].freeze
            NA_REQUIRED_ROOT_KEYS   = ['meta', 'Na__Preset__Metadata', 'Na__Preset__Configuration', 'Na__Preset__SvgPreview'].freeze
            NA_DEFAULT_ROOT_FOLDER  = '05__Data__PresetsLibrary'
            NA_DEFAULT_CODE_PREFIX  = 'EAS'
            NA_DEFAULT_CODE_FORMAT  = 'EAS%03d'
            NA_INLINE_ARRAY_MAX_LEN = 60

            @na_presets_dir = nil

            # HELPER FUNCTION | Read an AppConfig Value With a Safe Fallback
            # ------------------------------------------------------------
            # @param default_value [Object] value returned when the key path
            #     is missing OR the AppConfig itself cannot be loaded
            # @param key_path [Array<String>] nested key path into appConfig
            # @return [Object] configured value or the fallback
            def self.na_config_value(default_value, *key_path)
                ConfigLoader.na_get_or(default_value, *key_path)
            rescue StandardError
                default_value
            end
            private_class_method :na_config_value
            # ---------------------------------------------------------------

            # FUNCTION | Resolve the Presets Library Folder (Memoized)
            # ------------------------------------------------------------
            # @return [String] absolute path to 05__Data__PresetsLibrary
            def self.na_presets_dir
                @na_presets_dir ||= File.join(
                    NA_MODULES_ROOT,
                    na_config_value(NA_DEFAULT_ROOT_FOLDER, 'presetsLibrary', 'rootFolder').to_s
                )
            end
            # ---------------------------------------------------------------

            def self.na_code_prefix
                na_config_value(NA_DEFAULT_CODE_PREFIX, 'presetsLibrary', 'codePrefix').to_s
            end

            def self.na_code_format
                na_config_value(NA_DEFAULT_CODE_FORMAT, 'presetsLibrary', 'codeFormat').to_s
            end

            # -----------------------------------------------------------------
            # REGION | Library Scanner
            # -----------------------------------------------------------------

            # FUNCTION | Scan the Presets Folder Into Sorted Bridge Records
            # ------------------------------------------------------------
            # Top-level *.json glob only so 01__Archive/ and .bak files
            # are never picked up. Zero-byte and schema-invalid files are
            # debug-warned and skipped so a single bad file can never
            # break the gallery.
            # @return [Array<Hash>] flattened records sorted by preset code
            def self.na_scan_presets
                dir = na_presets_dir
                return [] unless File.directory?(dir)

                records = []
                Dir.glob(File.join(dir, '*.json')).sort.each do |file_path|
                    record = na_parse_preset_file(file_path)
                    records << record if record
                end

                records.sort_by { |record| [record['presetCode'].to_s[/\d+/].to_i, record['presetCode'].to_s] }
            end
            # ---------------------------------------------------------------

            # HELPER FUNCTION | Parse + Schema-Gate a Single Preset File
            # ------------------------------------------------------------
            # @param file_path [String] absolute path of the *.json file
            # @return [Hash, nil] flattened record, or nil when rejected
            def self.na_parse_preset_file(file_path)
                if File.size(file_path).zero?
                    DebugTools.na_debug_warn("[PresetsLibrary] Skipped zero-byte preset file: #{File.basename(file_path)}")
                    return nil
                end

                data = JSON.parse(File.read(file_path, encoding: 'UTF-8'))
                unless na_valid_preset_schema?(data)
                    DebugTools.na_debug_warn("[PresetsLibrary] Rejected preset file (invalid schema): #{File.basename(file_path)}")
                    return nil
                end

                na_build_preset_record(file_path, data)
            rescue StandardError => e
                DebugTools.na_debug_warn("[PresetsLibrary] Failed to parse preset file: #{File.basename(file_path)} - #{e.message}")
                nil
            end
            private_class_method :na_parse_preset_file
            # ---------------------------------------------------------------

            # HELPER FUNCTION | Validate the Canonical Preset File Schema
            # ------------------------------------------------------------
            # @param data [Object] parsed JSON root
            # @return [Boolean] true when all schema-gate checks pass
            def self.na_valid_preset_schema?(data)
                return false unless data.is_a?(Hash)
                return false unless NA_REQUIRED_ROOT_KEYS.all? { |key| data.key?(key) }

                metadata      = data['Na__Preset__Metadata']
                configuration = data['Na__Preset__Configuration']
                return false unless metadata.is_a?(Hash) && configuration.is_a?(Hash)

                values = configuration['Na__PresetConfig__Values']
                return false unless values.is_a?(Hash) && !values.empty?
                return false if metadata['Na__Preset__Code'].to_s.strip.empty?
                return false if metadata['Na__Preset__Name'].to_s.strip.empty?

                true
            end
            private_class_method :na_valid_preset_schema?
            # ---------------------------------------------------------------

            # HELPER FUNCTION | Flatten a Parsed File Into a Bridge Record
            # ------------------------------------------------------------
            # @param file_path [String] absolute path of the source file
            # @param data      [Hash]   schema-validated parsed JSON
            # @return [Hash] string-keyed camelCase record for the JS side
            def self.na_build_preset_record(file_path, data)
                metadata      = data['Na__Preset__Metadata']      || {}
                configuration = data['Na__Preset__Configuration'] || {}
                preview       = data['Na__Preset__SvgPreview']    || {}

                preset_code  = metadata['Na__Preset__Code'].to_s.strip
                display_name = metadata['Na__Preset__Name'].to_s.strip
                display_name = preset_code if display_name.empty?

                contract = configuration['Na__PresetConfig__SchemaContract'].to_s.strip
                contract = 'windowConfiguration' if contract.empty?

                family = metadata['Na__Preset__ProductFamily'].to_s.strip
                family = 'Window' if family.empty?

                {
                    'presetCode'     => preset_code,
                    'displayName'    => display_name,
                    'description'    => metadata['Na__Preset__Description'].to_s,
                    'keywords'       => Array(metadata['Na__Preset__Keywords']).map { |keyword| keyword.to_s },
                    'productFamily'  => family,
                    'productType'    => metadata['Na__Preset__ProductType'].to_s,
                    'schemaContract' => contract,
                    'sourceFile'     => file_path,
                    'createdDate'    => metadata['Na__Preset__CreatedDate'].to_s,
                    'lastModified'   => metadata['Na__Preset__LastModified'].to_s,
                    'svgPreview'     => {
                        'viewBox'   => preview['Na__PresetPreview__ViewBox'].to_s,
                        'widthMm'   => na_numeric_or_zero(preview['Na__PresetPreview__WidthMm']),
                        'heightMm'  => na_numeric_or_zero(preview['Na__PresetPreview__HeightMm']),
                        'svgMarkup' => preview['Na__PresetPreview__SvgMarkup'].to_s
                    },
                    'configValues'   => configuration['Na__PresetConfig__Values']
                }
            end
            private_class_method :na_build_preset_record
            # ---------------------------------------------------------------

            # -----------------------------------------------------------------
            # REGION | Code Allocation and File Naming
            # -----------------------------------------------------------------

            # FUNCTION | Allocate the Next Free Preset Code (EAS%03d)
            # ------------------------------------------------------------
            # Highest numeric suffix wins across BOTH the parsed
            # Na__Preset__Code values AND the raw filenames (fallback for
            # invalid / zero-byte files so their codes are never reissued).
            # @return [String] formatted code, e.g. "EAS003"
            def self.na_next_preset_code
                prefix     = na_code_prefix
                file_regex = /\ANa__#{Regexp.escape(prefix)}(\d+)__/
                code_regex = /\A#{Regexp.escape(prefix)}(\d+)\z/
                highest    = 0

                dir = na_presets_dir
                if File.directory?(dir)
                    Dir.glob(File.join(dir, '*.json')).each do |file_path|
                        name_match = File.basename(file_path).match(file_regex)
                        highest    = [highest, name_match[1].to_i].max if name_match

                        next if File.size(file_path).zero?
                        begin
                            data       = JSON.parse(File.read(file_path, encoding: 'UTF-8'))
                            code       = data.is_a?(Hash) ? data.dig('Na__Preset__Metadata', 'Na__Preset__Code').to_s : ''
                            code_match = code.match(code_regex)
                            highest    = [highest, code_match[1].to_i].max if code_match
                        rescue StandardError
                            next
                        end
                    end
                end

                next_number = highest + 1
                next_number = 1 if next_number < 1
                format(na_code_format, next_number)
            end
            # ---------------------------------------------------------------

            # FUNCTION | Build the Canonical Preset File Name
            # ------------------------------------------------------------
            # @param code        [String] allocated preset code (EAS0XX)
            # @param family      [String] Window | ExteriorDoor | InteriorDoor
            # @param preset_name [String] user-entered preset name
            # @return [String] Na__<CODE>__<Family>Preset__<SafeName>__.json
            def self.na_build_file_name(code, family, preset_name)
                "Na__#{code}__#{na_normalise_family(family)}Preset__#{na_safe_name_segment(preset_name)}__.json"
            end
            # ---------------------------------------------------------------

            # HELPER FUNCTION | PascalCase + Sanitise the Name Segment
            # ------------------------------------------------------------
            # Words are PascalCased, then any character outside
            # [A-Za-z0-9_-] is stripped. Falls back to "Preset" so the
            # filename is never malformed.
            # @param preset_name [String] raw user-entered name
            # @return [String] safe filename segment
            def self.na_safe_name_segment(preset_name)
                joined = preset_name.to_s.strip.split(/\s+/).map { |word|
                    word.sub(/\A[a-z]/) { |first_char| first_char.upcase }
                }.join
                safe = joined.gsub(/[^A-Za-z0-9_-]/, '')
                safe.empty? ? 'Preset' : safe
            end
            private_class_method :na_safe_name_segment
            # ---------------------------------------------------------------

            # HELPER FUNCTION | Clamp a Product Family to a Known Segment
            # ------------------------------------------------------------
            # @param product_family [String] inbound family value
            # @return [String] valid family segment (default "Window")
            def self.na_normalise_family(product_family)
                family = product_family.to_s.strip
                NA_FAMILY_SEGMENTS.include?(family) ? family : 'Window'
            end
            private_class_method :na_normalise_family
            # ---------------------------------------------------------------

            # -----------------------------------------------------------------
            # REGION | Save New Preset
            # -----------------------------------------------------------------

            # FUNCTION | Allocate Code + Filename and Write a New Preset File
            # ------------------------------------------------------------
            # @param params [Hash] bridge payload: presetName, presetDescription,
            #     presetKeywords, productFamily, productType, schemaContract,
            #     configValues, svgPreview {viewBox, widthMm, heightMm, svgMarkup}
            # @return [Hash] { isSaved, presetCode, sourceFile, statusMessage, reason }
            def self.na_save_new_preset(params)
                params        = {} unless params.is_a?(Hash)
                preset_name   = params['presetName'].to_s.strip
                description   = params['presetDescription'].to_s
                keywords      = na_normalise_keywords(params['presetKeywords'])
                family        = na_normalise_family(params['productFamily'])
                product_type  = params['productType'].to_s
                contract      = params['schemaContract'].to_s.strip
                contract      = 'windowConfiguration' if contract.empty?
                config_values = params['configValues']

                return na_failed_result('', '', 'Preset name is required.', 'nameRequired') if preset_name.empty?
                unless config_values.is_a?(Hash) && !config_values.empty?
                    return na_failed_result('', '', 'No captured configuration to save.', 'configValuesMissing')
                end

                code      = na_next_preset_code
                file_name = na_build_file_name(code, family, preset_name)
                dir       = na_presets_dir
                FileUtils.mkdir_p(dir) unless File.directory?(dir)
                file_path = File.join(dir, file_name)
                if File.exist?(file_path)
                    return na_failed_result(code, file_path, "Preset file already exists: #{file_name}", 'fileExists')
                end

                document = na_build_preset_document(
                    'fileName'          => file_name,
                    'presetCode'        => code,
                    'presetName'        => preset_name,
                    'presetDescription' => description,
                    'presetKeywords'    => keywords,
                    'productFamily'     => family,
                    'productType'       => product_type,
                    'schemaContract'    => contract,
                    'configValues'      => config_values,
                    'svgPreview'        => params['svgPreview']
                )
                File.open(file_path, 'w:utf-8') { |file| file.write(na_generate_pretty_json(document)) }
                DebugTools.na_debug_success("[PresetsLibrary] New preset written: #{file_name}")

                {
                    'isSaved'       => true,
                    'presetCode'    => code,
                    'sourceFile'    => file_path,
                    'statusMessage' => "Preset #{code} — #{preset_name} saved.",
                    'reason'        => nil
                }
            end
            # ---------------------------------------------------------------

            # HELPER FUNCTION | Build the Canonical On-Disk Preset Document
            # ------------------------------------------------------------
            # Insertion order here IS the on-disk key order: meta first,
            # then Metadata, Configuration, SvgPreview.
            # @param details [Hash] normalised save-new details
            # @return [Hash] full document ready for the pretty writer
            def self.na_build_preset_document(details)
                {
                    'meta' => {
                        'fileName'         => details['fileName'],
                        'description'      => 'Element Assembly Studio Pro preset data file.',
                        'version'          => '1.0.0',
                        'lastUpdated'      => na_today_date,
                        'namingConvention' => 'All custom keys prefixed Na__. Three-stage form Na__Section__SubSection__FieldName.',
                        'fieldPrefixes'    => {
                            'Na__Preset__'        => 'Preset metadata and library organisation fields',
                            'Na__PresetConfig__'  => 'Captured UI configuration payload',
                            'Na__PresetPreview__' => 'Stored SVG preview data'
                        }
                    },
                    'Na__Preset__Metadata' => {
                        'Na__Preset__Code'          => details['presetCode'],
                        'Na__Preset__Name'          => details['presetName'],
                        'Na__Preset__Description'   => details['presetDescription'],
                        'Na__Preset__Keywords'      => details['presetKeywords'],
                        'Na__Preset__ProductFamily' => details['productFamily'],
                        'Na__Preset__ProductType'   => details['productType'],
                        'Na__Preset__CreatedDate'   => na_timestamp_date,
                        'Na__Preset__LastModified'  => na_today_date
                    },
                    'Na__Preset__Configuration' => {
                        'Na__PresetConfig__SchemaContract' => details['schemaContract'],
                        'Na__PresetConfig__Values'         => details['configValues']
                    },
                    'Na__Preset__SvgPreview' => na_normalise_svg_preview(details['svgPreview'])
                }
            end
            private_class_method :na_build_preset_document
            # ---------------------------------------------------------------

            # -----------------------------------------------------------------
            # REGION | Patch Existing Preset - Metadata
            # -----------------------------------------------------------------

            # FUNCTION | Patch Name / Description / Keywords In Place
            # ------------------------------------------------------------
            # Guards the path, writes <file>.bak of the original raw
            # content, patches ONLY the contracted metadata keys plus the
            # LastModified / meta.lastUpdated dates, then rewrites via the
            # pretty writer.
            # @param params [Hash] bridge payload: presetCode, sourceFile,
            #     presetName, presetDescription, presetKeywords
            # @return [Hash] { isSaved, presetCode, sourceFile, statusMessage, reason }
            def self.na_update_preset_meta(params)
                params      = {} unless params.is_a?(Hash)
                preset_code = params['presetCode'].to_s.strip
                source_file = params['sourceFile'].to_s.strip
                new_name    = params['presetName'].to_s.strip
                new_desc    = params['presetDescription'].to_s
                new_keys    = na_normalise_keywords(params['presetKeywords'])

                return na_failed_result(preset_code, source_file, 'Preset code is required.', 'codeRequired') if preset_code.empty?

                validation = na_validate_source_path(source_file)
                unless validation['isValid']
                    return na_failed_result(preset_code, source_file, validation['statusMessage'], validation['reason'])
                end

                expanded_path = validation['expandedPath']
                raw_content   = File.read(expanded_path, encoding: 'UTF-8')
                data          = JSON.parse(raw_content)
                na_write_backup(expanded_path, raw_content)

                metadata = (data['Na__Preset__Metadata'] ||= {})
                metadata['Na__Preset__Name']         = new_name unless new_name.empty?
                metadata['Na__Preset__Description']  = new_desc
                metadata['Na__Preset__Keywords']     = new_keys
                metadata['Na__Preset__LastModified'] = na_today_date
                (data['meta'] ||= {})['lastUpdated'] = na_today_date

                File.open(expanded_path, 'w:utf-8') { |file| file.write(na_generate_pretty_json(data)) }
                DebugTools.na_debug_success("[PresetsLibrary] Metadata patched: #{File.basename(expanded_path)}")

                {
                    'isSaved'       => true,
                    'presetCode'    => preset_code,
                    'sourceFile'    => expanded_path,
                    'statusMessage' => "Preset #{preset_code} details saved. Backup written as .bak.",
                    'reason'        => nil
                }
            rescue JSON::ParserError => e
                na_failed_result(preset_code, source_file, 'Preset file could not be parsed.', "jsonParseError: #{e.message}")
            end
            # ---------------------------------------------------------------

            # -----------------------------------------------------------------
            # REGION | Patch Existing Preset - Configuration + Preview
            # -----------------------------------------------------------------

            # FUNCTION | Overwrite Stored Config + SVG From the Current UI
            # ------------------------------------------------------------
            # Guards the path, writes <file>.bak, patches the Configuration
            # block, the SvgPreview block, ProductFamily / ProductType and
            # the LastModified / meta.lastUpdated dates, then rewrites via
            # the pretty writer.
            # @param params [Hash] bridge payload: presetCode, sourceFile,
            #     productFamily, productType, schemaContract, configValues,
            #     svgPreview
            # @return [Hash] { isSaved, presetCode, sourceFile, statusMessage, reason }
            def self.na_update_preset_config(params)
                params        = {} unless params.is_a?(Hash)
                preset_code   = params['presetCode'].to_s.strip
                source_file   = params['sourceFile'].to_s.strip
                family        = na_normalise_family(params['productFamily'])
                product_type  = params['productType'].to_s
                contract      = params['schemaContract'].to_s.strip
                config_values = params['configValues']
                svg_preview   = params['svgPreview']

                return na_failed_result(preset_code, source_file, 'Preset code is required.', 'codeRequired') if preset_code.empty?
                unless config_values.is_a?(Hash) && !config_values.empty?
                    return na_failed_result(preset_code, source_file, 'No captured configuration to store.', 'configValuesMissing')
                end

                validation = na_validate_source_path(source_file)
                unless validation['isValid']
                    return na_failed_result(preset_code, source_file, validation['statusMessage'], validation['reason'])
                end

                expanded_path = validation['expandedPath']
                raw_content   = File.read(expanded_path, encoding: 'UTF-8')
                data          = JSON.parse(raw_content)
                na_write_backup(expanded_path, raw_content)

                configuration = (data['Na__Preset__Configuration'] ||= {})
                configuration['Na__PresetConfig__SchemaContract'] = contract unless contract.empty?
                configuration['Na__PresetConfig__Values']         = config_values
                data['Na__Preset__SvgPreview'] = na_normalise_svg_preview(svg_preview) if svg_preview.is_a?(Hash) && !svg_preview.empty?

                metadata = (data['Na__Preset__Metadata'] ||= {})
                metadata['Na__Preset__ProductFamily'] = family
                metadata['Na__Preset__ProductType']   = product_type unless product_type.empty?
                metadata['Na__Preset__LastModified']  = na_today_date
                (data['meta'] ||= {})['lastUpdated']  = na_today_date

                File.open(expanded_path, 'w:utf-8') { |file| file.write(na_generate_pretty_json(data)) }
                DebugTools.na_debug_success("[PresetsLibrary] Configuration patched: #{File.basename(expanded_path)}")

                {
                    'isSaved'       => true,
                    'presetCode'    => preset_code,
                    'sourceFile'    => expanded_path,
                    'statusMessage' => "Preset #{preset_code} updated from the current design. Backup written as .bak.",
                    'reason'        => nil
                }
            rescue JSON::ParserError => e
                na_failed_result(preset_code, source_file, 'Preset file could not be parsed.', "jsonParseError: #{e.message}")
            end
            # ---------------------------------------------------------------

            # -----------------------------------------------------------------
            # REGION | Path Guard, Backup and Shared Value Helpers
            # -----------------------------------------------------------------

            # FUNCTION | Validate a Source File Path (Traversal Guard)
            # ------------------------------------------------------------
            # The expanded path MUST live inside the presets folder, MUST
            # exist and MUST end .json. Separators are normalised before
            # comparison so Windows backslash paths cannot slip through.
            # @param source_file [String] path received from the JS side
            # @return [Hash] { isValid, expandedPath, statusMessage, reason }
            def self.na_validate_source_path(source_file)
                if source_file.to_s.strip.empty?
                    return { 'isValid' => false, 'expandedPath' => nil, 'statusMessage' => 'Source file path is required.', 'reason' => 'sourceFileRequired' }
                end

                expanded_source   = File.expand_path(source_file)
                normalised_source = expanded_source.tr('\\', '/')
                normalised_dir    = File.expand_path(na_presets_dir).tr('\\', '/')

                unless normalised_source.start_with?(normalised_dir + '/')
                    return { 'isValid' => false, 'expandedPath' => nil, 'statusMessage' => 'Source file is outside the presets library folder.', 'reason' => 'pathOutsideLibrary' }
                end
                unless File.exist?(expanded_source)
                    return { 'isValid' => false, 'expandedPath' => nil, 'statusMessage' => "Source file not found: #{File.basename(expanded_source)}", 'reason' => 'fileNotFound' }
                end
                unless normalised_source.end_with?('.json')
                    return { 'isValid' => false, 'expandedPath' => nil, 'statusMessage' => 'Source file is not a .json preset file.', 'reason' => 'notJsonFile' }
                end

                { 'isValid' => true, 'expandedPath' => expanded_source, 'statusMessage' => '', 'reason' => nil }
            end
            # ---------------------------------------------------------------

            # HELPER FUNCTION | Write <file>.bak of the Original Raw Content
            # ------------------------------------------------------------
            # Overwrites any prior .bak. A failed backup is warned but
            # never blocks the save (matches the ProfilePathTracer
            # MetaWriter behaviour).
            # @param expanded_path [String] validated preset file path
            # @param raw_content   [String] original file content pre-patch
            # @return [void]
            def self.na_write_backup(expanded_path, raw_content)
                bak_path = expanded_path + '.bak'
                File.open(bak_path, 'w:utf-8') { |file| file.write(raw_content) }
            rescue StandardError => e
                DebugTools.na_debug_warn("[PresetsLibrary] Backup write failed for #{File.basename(expanded_path)}: #{e.message}")
            end
            private_class_method :na_write_backup
            # ---------------------------------------------------------------

            # HELPER FUNCTION | Normalise the Bridge SvgPreview Block
            # ------------------------------------------------------------
            # @param svg_preview [Hash, nil] { viewBox, widthMm, heightMm, svgMarkup }
            # @return [Hash] Na__PresetPreview__* keyed block for disk
            def self.na_normalise_svg_preview(svg_preview)
                svg_preview = {} unless svg_preview.is_a?(Hash)
                {
                    'Na__PresetPreview__ViewBox'   => svg_preview['viewBox'].to_s,
                    'Na__PresetPreview__WidthMm'   => na_numeric_or_zero(svg_preview['widthMm']),
                    'Na__PresetPreview__HeightMm'  => na_numeric_or_zero(svg_preview['heightMm']),
                    'Na__PresetPreview__SvgMarkup' => svg_preview['svgMarkup'].to_s
                }
            end
            private_class_method :na_normalise_svg_preview
            # ---------------------------------------------------------------

            def self.na_normalise_keywords(keywords)
                Array(keywords).map { |keyword| keyword.to_s.strip }.reject(&:empty?)
            end
            private_class_method :na_normalise_keywords

            def self.na_numeric_or_zero(value)
                value.is_a?(Numeric) ? value : value.to_s.to_f
            end
            private_class_method :na_numeric_or_zero

            def self.na_today_date
                Time.now.strftime('%d-%b-%Y')
            end
            private_class_method :na_today_date

            def self.na_timestamp_date
                Time.now.strftime('%d-%b-%Y__%H:%M')
            end
            private_class_method :na_timestamp_date

            # HELPER FUNCTION | Build a Well-Formed Failure Result Hash
            # ------------------------------------------------------------
            # @param preset_code    [String] code echoed back (may be empty)
            # @param source_file    [String] path echoed back (may be empty)
            # @param status_message [String] human-readable status text
            # @param reason         [String] machine-readable reason token
            # @return [Hash] { isSaved false, presetCode, sourceFile, statusMessage, reason }
            def self.na_failed_result(preset_code, source_file, status_message, reason)
                {
                    'isSaved'       => false,
                    'presetCode'    => preset_code.to_s,
                    'sourceFile'    => source_file.to_s,
                    'statusMessage' => status_message.to_s,
                    'reason'        => reason.to_s
                }
            end
            private_class_method :na_failed_result
            # ---------------------------------------------------------------

            # -----------------------------------------------------------------
            # REGION | Column-Aligned Pretty JSON Writer (Na__ House Style)
            # -----------------------------------------------------------------
            # Self-contained equivalent of the DevTools JsonExporter2D
            # writer: 4-space indent, keys within each object padded so
            # the colons align, short scalar arrays kept inline, key order
            # preserved exactly as inserted.
            # -----------------------------------------------------------------

            # FUNCTION | Serialise a Root Hash to Column-Aligned Pretty JSON
            # ------------------------------------------------------------
            # @param root_hash [Hash] document to serialise (insertion order kept)
            # @return [String] pretty JSON text with trailing newline
            def self.na_generate_pretty_json(root_hash)
                width = root_hash.keys.map { |key| key.to_json.length }.max
                parts = root_hash.map { |key, value| na_format_key_value_pair(key, value, 1, width) }
                "{\n#{parts.join(",\n")}\n}\n"
            end
            # ---------------------------------------------------------------

            def self.na_indent_line(line_depth)
                return '' if line_depth < 1
                ' ' * (4 * line_depth)
            end
            private_class_method :na_indent_line

            def self.na_json_scalar_fragment(value)
                case value
                when NilClass   then 'null'
                when TrueClass  then 'true'
                when FalseClass then 'false'
                when Float
                    value.nan? || value.infinite? ? 'null' : value.to_json
                else
                    value.to_json
                end
            end
            private_class_method :na_json_scalar_fragment

            def self.na_key_colon_padded(key, key_column_width)
                key_json = key.to_json
                pad      = [0, key_column_width - key_json.length].max
                "#{key_json}#{' ' * pad} : "
            end
            private_class_method :na_key_colon_padded

            def self.na_scalar_array?(value)
                value.all? { |element| !element.is_a?(Hash) && !element.is_a?(Array) }
            end
            private_class_method :na_scalar_array?

            def self.na_format_key_value_pair(key, value, key_line_depth, key_column_width)
                indent = na_indent_line(key_line_depth)
                keycol = na_key_colon_padded(key, key_column_width)

                case value
                when Hash
                    return "#{indent}#{keycol}{}" if value.empty?
                    body = na_format_object_body(value, key_line_depth + 1)
                    "#{indent}#{keycol}{\n#{body}\n#{indent}}"
                when Array
                    return "#{indent}#{keycol}[]" if value.empty?
                    if na_scalar_array?(value)
                        inline = value.map { |element| na_json_scalar_fragment(element) }.join(', ')
                        return "#{indent}#{keycol}[#{inline}]" if inline.length <= NA_INLINE_ARRAY_MAX_LEN
                    end
                    inner = na_format_array_body(value, key_line_depth)
                    "#{indent}#{keycol}[\n#{inner}\n#{indent}]"
                else
                    "#{indent}#{keycol}#{na_json_scalar_fragment(value)}"
                end
            end
            private_class_method :na_format_key_value_pair

            def self.na_format_object_body(hash, inner_key_line_depth)
                return '' if hash.empty?
                width = hash.keys.map { |key| key.to_json.length }.max
                pairs = hash.map { |key, value| na_format_key_value_pair(key, value, inner_key_line_depth, width) }
                pairs.join(",\n")
            end
            private_class_method :na_format_object_body

            def self.na_format_array_body(arr, parent_key_line_depth)
                elem_depth = parent_key_line_depth + 1
                chunks     = arr.map { |element| na_format_array_element(element, elem_depth) }
                chunks.join(",\n")
            end
            private_class_method :na_format_array_body

            def self.na_format_array_element(element, elem_line_depth)
                case element
                when Hash
                    return "#{na_indent_line(elem_line_depth)}{}" if element.empty?
                    body = na_format_object_body(element, elem_line_depth + 1)
                    open = na_indent_line(elem_line_depth)
                    "#{open}{\n#{body}\n#{open}}"
                when Array
                    return "#{na_indent_line(elem_line_depth)}[]" if element.empty?
                    inner = na_format_array_body(element, elem_line_depth)
                    "#{na_indent_line(elem_line_depth)}[\n#{inner}\n#{na_indent_line(elem_line_depth)}]"
                else
                    "#{na_indent_line(elem_line_depth)}#{na_json_scalar_fragment(element)}"
                end
            end
            private_class_method :na_format_array_element
            # ---------------------------------------------------------------

        end
    end
end
