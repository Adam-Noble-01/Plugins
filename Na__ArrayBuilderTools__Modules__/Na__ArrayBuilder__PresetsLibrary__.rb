# =============================================================================
# NA ARRAY BUILDER TOOLS - PRESETS LIBRARY
# =============================================================================
# FILE       : Na__ArrayBuilder__PresetsLibrary__.rb
# AUTHOR     : Noble Architecture
# PURPOSE    : Portable JSON recipes and SKP sources, with backup and archive.
# =============================================================================

require 'json'
require 'fileutils'
require 'securerandom'
require_relative 'Na__ArrayBuilder__Configuration__'
require_relative 'Na__ArrayBuilder__ObjectRegistry__'

module Na__ArrayBuilderTools
    module Na__ArrayBuilder__PresetsLibrary

        NA_ROOT = File.join(__dir__, '05__Data__PresetsLibrary').freeze
        NA_ID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/

        # FUNCTION | Resolve Only Generated Library IDs, Never Client Paths
        # ------------------------------------------------------------
        def self.Na__Presets__Path(na_id)
            raise ArgumentError, 'Invalid preset identity.' unless na_id.is_a?(String) && na_id.match?(NA_ID_PATTERN)
            File.join(NA_ROOT, "Na__ArrayPreset__#{na_id}__.json")
        end

        def self.Na__Presets__Read(na_id)
            na_data = JSON.parse(File.read(Na__Presets__Path(na_id), encoding: 'UTF-8'))
            unless na_data.is_a?(Hash) && na_data['schema_version'] == 1 && na_data['id'] == na_id &&
                   na_data['name'].is_a?(String) && !na_data['name'].strip.empty?
                raise ArgumentError, 'Unsupported or damaged array preset.'
            end
            na_data['configuration'] = Na__ArrayBuilder__Configuration.Na__Config__Resolve(na_data.fetch('configuration'))
            if na_data['configuration']['type'] == 'object'
                na_source = na_data['source']
                unless na_source.is_a?(Hash) && na_source['asset_id'].to_s.match?(NA_ID_PATTERN) &&
                       na_source['scale'].is_a?(Array) && na_source['scale'].length == 3 &&
                       na_source['scale'].all? { |na_value| na_value.is_a?(Numeric) && na_value.finite? && na_value > 0 }
                    raise ArgumentError, 'The preset source reference is invalid.'
                end
            end
            na_data
        end

        # FUNCTION | A Bad File Cannot Prevent the Remaining Gallery Loading
        # ------------------------------------------------------------
        def self.Na__Presets__Scan
            na_errors = []
            na_records = Dir.glob(File.join(NA_ROOT, 'Na__ArrayPreset__*__.json')).filter_map do |na_path|
                begin
                    na_id = File.basename(na_path).sub('Na__ArrayPreset__', '').sub('__.json', '')
                    Na__Presets__Read(na_id)
                rescue StandardError
                    na_errors << File.basename(na_path)
                    nil
                end
            end
            { 'records' => na_records.sort_by { |na_record| na_record['name'].downcase }, 'skipped' => na_errors }
        end

        # FUNCTION | Save Metadata and Configuration With a Portable Source
        # ------------------------------------------------------------
        def self.Na__Presets__Save(na_payload, na_config, na_source)
            na_name = na_payload['name'].to_s.strip
            raise ArgumentError, 'Give this preset a name (up to 100 characters).' unless na_name.length.between?(1, 100)
            na_config = Na__ArrayBuilder__Configuration.Na__Config__Resolve(na_config)
            na_id = na_payload['id'].to_s.empty? ? SecureRandom.uuid : na_payload['id']
            na_path = Na__Presets__Path(na_id)
            na_previous = File.exist?(na_path) ? Na__Presets__Read(na_id) : nil
            na_now = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
            FileUtils.mkdir_p(NA_ROOT)
            na_source_record = nil
            if na_config['type'] == 'object'
                raise ArgumentError, 'Pick a source object before saving this preset.' unless na_source && na_source[:definition].valid?
                %w[width depth height].each do |na_axis|
                    na_config["unit_#{na_axis}_mm"] = [na_source[na_axis.to_sym] * 25.4, 0.1].max
                end
                na_asset_id = SecureRandom.uuid
                FileUtils.mkdir_p(File.join(NA_ROOT, '02__SourceObjects'))
                na_asset = File.join(NA_ROOT, '02__SourceObjects', "#{na_asset_id}.skp")
                raise IOError, 'Could not save the preset source geometry.' unless na_source[:definition].save_as(na_asset)
                na_source_record = { 'asset_id' => na_asset_id, 'name' => na_source[:definition].name, 'scale' => na_source[:scale] }
            end
            na_record = {
                'schema_version' => 1, 'id' => na_id, 'name' => na_name,
                'description' => na_payload['description'].to_s[0, 2000],
                'category' => na_payload['category'].to_s.strip[0, 60],
                'created_at' => na_previous ? na_previous['created_at'] : na_now,
                'updated_at' => na_now, 'configuration' => na_config, 'source' => na_source_record
            }
            FileUtils.cp(na_path, "#{na_path}.bak") if na_previous
            na_temp = "#{na_path}.#{SecureRandom.hex(6)}.tmp"
            begin
                File.write(na_temp, JSON.pretty_generate(na_record) + "\n", encoding: 'UTF-8')
                File.rename(na_temp, na_path)
            ensure
                File.delete(na_temp) if File.exist?(na_temp)
            end
            na_record
        end

        # FUNCTION | Load a Source Into the Current Model on Explicit Preset Use
        # ------------------------------------------------------------
        def self.Na__Presets__LoadSource(na_model, na_record)
            return nil unless na_record['configuration']['type'] == 'object'
            na_source = na_record.fetch('source')
            na_asset = File.join(NA_ROOT, '02__SourceObjects', "#{na_source.fetch('asset_id')}.skp")
            raise ArgumentError, 'The preset source SKP is missing. Restore its source file or pick a replacement.' unless File.file?(na_asset)
            na_model.start_operation('Load Array Preset Source', true)
            begin
                na_definition = na_model.definitions.load(na_asset)
                raise ArgumentError, 'Could not load the preset source.' unless na_definition && na_definition.valid?
                na_model.commit_operation
            rescue StandardError
                na_model.abort_operation
                raise
            end
            Na__ArrayBuilder__ObjectRegistry.Na__Registry__SetDefinition(na_definition, na_source['name'], na_source['scale'])
            Na__ArrayBuilder__ObjectRegistry.Na__Registry__GetPlacementInfo
        end

        # FUNCTION | Archive a Preset Without Permanently Deleting its Data
        # ------------------------------------------------------------
        def self.Na__Presets__Archive(na_id)
            na_path = Na__Presets__Path(na_id)
            raise ArgumentError, 'This preset no longer exists.' unless File.file?(na_path)
            na_archive = File.join(NA_ROOT, '01__Archive')
            FileUtils.mkdir_p(na_archive)
            FileUtils.mv(na_path, File.join(na_archive, "#{Time.now.to_i}__#{SecureRandom.hex(3)}__#{File.basename(na_path)}"))
        end

    end # module Na__ArrayBuilder__PresetsLibrary
end # module Na__ArrayBuilderTools
