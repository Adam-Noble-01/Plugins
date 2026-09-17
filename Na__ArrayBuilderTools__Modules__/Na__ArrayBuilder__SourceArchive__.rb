# =============================================================================
# NA ARRAY BUILDER TOOLS - SOURCE ARCHIVE
# FILE       : Na__ArrayBuilder__SourceArchive__.rb
# AUTHOR     : Noble Architecture
# PURPOSE    : Preserve the complete custom source as native SKP data in the model.
# =============================================================================

require 'json'
require 'base64'
require 'digest'
require 'tmpdir'

module Na__ArrayBuilderTools
    module Na__ArrayBuilder__SourceArchive

        NA_DICTIONARY = 'Na__ArrayBuilder__Source'.freeze
        NA_MODEL_DICTIONARY = 'Na__ArrayBuilder__Sources'.freeze

        # FUNCTION | Capture Once per Source Revision Inside the Array Operation
        # ------------------------------------------------------------
        # A definition attribute travels with copied arrays, including copy/paste
        # into another model. The model dictionary retains a second lookup by ID.
        def self.Na__Source__Save(na_model, na_array_definition, na_source)
            return nil unless na_source
            na_definition = na_source[:definition]
            na_previous = na_array_definition.get_attribute(NA_DICTIONARY, 'archive')
            na_archive = Na__Source__Read(na_previous) if na_previous
            unless na_archive && na_archive['definition_pid'] == na_definition.persistent_id &&
                   na_archive['definition_guid'] == na_definition.guid
                na_bytes = Dir.mktmpdir('na_array_source_') do |na_directory|
                    na_file = File.join(na_directory, 'source.skp')
                    raise IOError, 'Could not preserve the custom source geometry.' unless na_definition.save_copy(na_file)
                    File.binread(na_file)
                end
                raise IOError, 'The saved custom source is empty.' if na_bytes.empty?
                na_archive = {
                    'schema_version' => 1, 'format' => 'skp',
                    'id' => Digest::SHA256.hexdigest(na_bytes),
                    'definition_pid' => na_definition.persistent_id, 'definition_guid' => na_definition.guid,
                    'data_base64' => Base64.strict_encode64(na_bytes)
                }
            end
            na_json = JSON.generate(na_archive)
            na_array_definition.set_attribute(NA_DICTIONARY, 'archive', na_json) unless na_previous == na_json
            unless na_model.get_attribute(NA_MODEL_DICTIONARY, na_archive['id']) == na_json
                na_model.set_attribute(NA_MODEL_DICTIONARY, na_archive['id'], na_json)
            end
            na_archive['id']
        end

        def self.Na__Source__Read(na_json)
            return nil unless na_json.is_a?(String)
            na_archive = JSON.parse(na_json)
            return nil unless na_archive.is_a?(Hash) && na_archive['schema_version'] == 1 &&
                na_archive['format'] == 'skp' && na_archive['id'].to_s.match?(/\A[0-9a-f]{64}\z/) && na_archive['data_base64'].is_a?(String)
            na_archive
        rescue JSON::ParserError
            nil
        end

        # FUNCTION | Restore a Missing Source Without Depending on External Files
        # ------------------------------------------------------------
        # Only explicit edit/update actions call this mutation. Observer refreshes
        # only inspect the surviving native units and never import definitions.
        def self.Na__Source__Restore(na_model, na_array_definition, na_record)
            na_bytes = Na__Source__VerifiedBytes(na_model, na_array_definition, na_record)
            na_model.start_operation('Restore Noble Array Source', true)
            begin
                na_definition = Dir.mktmpdir('na_array_restore_') do |na_directory|
                    na_file = File.join(na_directory, 'source.skp')
                    File.binwrite(na_file, na_bytes)
                    na_model.definitions.load(na_file)
                end
                raise ArgumentError, 'SketchUp could not restore the saved custom source.' unless na_definition && na_definition.valid?
                na_model.commit_operation
                na_definition
            rescue StandardError
                na_model.abort_operation
                raise
            end
        end

        def self.Na__Source__VerifiedBytes(na_model, na_array_definition, na_record)
            na_candidates = [na_array_definition.get_attribute(NA_DICTIONARY, 'archive')]
            na_candidates << na_model.get_attribute(NA_MODEL_DICTIONARY, na_record['archive_id']) if na_record['archive_id']
            na_candidates.each do |na_json|
                na_archive = Na__Source__Read(na_json)
                next unless na_archive && (!na_record['archive_id'] || na_record['archive_id'] == na_archive['id'])
                begin
                    na_bytes = Base64.strict_decode64(na_archive['data_base64'])
                    return na_bytes if Digest::SHA256.hexdigest(na_bytes) == na_archive['id']
                rescue ArgumentError
                    next
                end
            end
            raise ArgumentError, 'The saved source geometry is missing or damaged. Pick a replacement object.'
        end

    end # module Na__ArrayBuilder__SourceArchive
end # module Na__ArrayBuilderTools
