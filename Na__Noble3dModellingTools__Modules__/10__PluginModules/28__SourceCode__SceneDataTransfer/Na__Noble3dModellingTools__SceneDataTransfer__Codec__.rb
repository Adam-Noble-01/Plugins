# =============================================================================
# NA NOBLE3D MODELLING TOOLS - SCENE DATA TRANSFER - CODEC
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__SceneDataTransfer__Codec__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__SceneDataTransfer__Codec
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Encode a payload Hash into an attribute dictionary and decode it
#              back, handling compression, chunking and stale chunk cleanup.
# CREATED    : 2026
#
# WHY CHUNKING:
# There is no documented maximum length for a SketchUp attribute String, but
# the .skp file-size cost of a single very long value is severe and reported to
# be superlinear. Splitting into fixed-size slices across zero-padded numbered
# keys keeps each stored value small and keeps every key individually readable
# in the native attribute inspector.
#
# WHY REASSEMBLY BY INDEX:
# Sketchup::AttributeDictionary#each gives NO ordering guarantee, so chunks are
# always reassembled by walking 0...chunk_count and never by iterating the
# dictionary. Stale chunks from a previous longer payload are deleted before
# every write, otherwise orphaned keys bloat the file permanently.
#
# WHY NO Hash IS EVER STORED:
# The permitted attribute value types are Boolean, Integer, Float, Length, nil,
# String, Time, Array, Geom::Point3d and Geom::Vector3d. Hash is NOT supported.
# Everything structural therefore goes in as a JSON String.
#
# =============================================================================

require 'json'
require 'zlib'
require 'base64'

module Na__Noble3dModellingTools
    module Na__SceneDataTransfer__Codec

# -----------------------------------------------------------------------------
# REGION | Public Write API
# -----------------------------------------------------------------------------

        # FUNCTION | Serialise a Payload Hash Into an Entity Attribute Dictionary
        # ------------------------------------------------------------
        # The entity is a Sketchup::Model for the local copy, or a
        # Sketchup::ComponentDefinition for the cross-model carrier copy.
        def self.Na__SceneDataTransfer__WritePayload(entity, payload_hash)
            return false unless entity && payload_hash.is_a?(Hash)

            schema        = Na__SceneDataTransfer__Schema
            json_text     = JSON.generate(payload_hash)
            encoding_key  = na_encoding_for(json_text)
            encoded_text  = na_encode(json_text, encoding_key)
            chunks        = na_split_into_chunks(encoded_text)

            na_clear_payload_chunks(entity)                                         # <-- Drop orphans before writing

            entity.set_attribute(schema::NA_PAYLOAD_DICTIONARY, schema::NA_KEY_SCHEMA_VERSION,      schema::NA_SCHEMA_VERSION)
            entity.set_attribute(schema::NA_PAYLOAD_DICTIONARY, schema::NA_KEY_PAYLOAD_ENCODING,    encoding_key)
            entity.set_attribute(schema::NA_PAYLOAD_DICTIONARY, schema::NA_KEY_PAYLOAD_CHUNK_COUNT, chunks.length)
            entity.set_attribute(schema::NA_PAYLOAD_DICTIONARY, schema::NA_KEY_PAYLOAD_BYTE_LENGTH, json_text.length)

            na_write_header_fields(entity, payload_hash)

            chunks.each_with_index do |chunk_text, chunk_index|
                entity.set_attribute(
                    schema::NA_PAYLOAD_DICTIONARY,
                    na_chunk_key(chunk_index),
                    chunk_text
                )
            end

            true
        rescue => error
            puts "[Na__SceneDataTransfer] Payload write error: #{error.class}: #{error.message}"
            false
        end
        # ------------------------------------------------------------

        # FUNCTION | Delete Every Payload Key From an Entity Dictionary
        # ------------------------------------------------------------
        def self.Na__SceneDataTransfer__ErasePayload(entity)
            return false unless entity

            schema     = Na__SceneDataTransfer__Schema
            dictionary = entity.attribute_dictionary(schema::NA_PAYLOAD_DICTIONARY, false)
            return true unless dictionary

            na_clear_payload_chunks(entity)

            stored_keys = dictionary.keys.dup                                       # <-- Snapshot; never delete while iterating
            stored_keys.each { |stored_key| dictionary.delete_key(stored_key) }

            true
        rescue => error
            puts "[Na__SceneDataTransfer] Payload erase warning: #{error.class}: #{error.message}"
            false
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Read API
# -----------------------------------------------------------------------------

        # FUNCTION | Report Whether an Entity Carries a Readable Payload
        # ------------------------------------------------------------
        def self.Na__SceneDataTransfer__HasPayload(entity)
            return false unless entity

            schema     = Na__SceneDataTransfer__Schema
            dictionary = entity.attribute_dictionary(schema::NA_PAYLOAD_DICTIONARY, false)
            return false unless dictionary

            dictionary[schema::NA_KEY_PAYLOAD_CHUNK_COUNT].to_i > 0
        rescue
            false
        end
        # ------------------------------------------------------------

        # FUNCTION | Read and Decode a Payload Hash From an Entity Dictionary
        # ------------------------------------------------------------
        def self.Na__SceneDataTransfer__ReadPayload(entity)
            return nil unless entity

            schema     = Na__SceneDataTransfer__Schema
            dictionary = entity.attribute_dictionary(schema::NA_PAYLOAD_DICTIONARY, false)
            return nil unless dictionary

            chunk_count = dictionary[schema::NA_KEY_PAYLOAD_CHUNK_COUNT].to_i
            return nil if chunk_count <= 0

            encoded_text = na_join_chunks(dictionary, chunk_count)
            return nil if encoded_text.nil?

            encoding_key = dictionary[schema::NA_KEY_PAYLOAD_ENCODING].to_s
            json_text    = na_decode(encoded_text, encoding_key)
            return nil if json_text.nil? || json_text.empty?

            parsed = JSON.parse(json_text)
            parsed.is_a?(Hash) ? parsed : nil
        rescue JSON::ParserError => error
            puts "[Na__SceneDataTransfer] Payload JSON parse error: #{error.message}"
            nil
        rescue => error
            puts "[Na__SceneDataTransfer] Payload read error: #{error.class}: #{error.message}"
            nil
        end
        # ------------------------------------------------------------

        # FUNCTION | Read Only the Cheap Header Fields, Without Decoding Chunks
        # ------------------------------------------------------------
        # Used to show a source model summary before committing to a full read.
        def self.Na__SceneDataTransfer__ReadHeader(entity)
            return nil unless entity

            schema     = Na__SceneDataTransfer__Schema
            dictionary = entity.attribute_dictionary(schema::NA_PAYLOAD_DICTIONARY, false)
            return nil unless dictionary

            {
                'schema_version'    => dictionary[schema::NA_KEY_SCHEMA_VERSION].to_s,
                'captured_at'       => dictionary[schema::NA_KEY_CAPTURED_AT].to_s,
                'captured_by'       => dictionary[schema::NA_KEY_CAPTURED_BY].to_s,
                'source_model_name' => dictionary[schema::NA_KEY_SOURCE_MODEL_NAME].to_s,
                'source_model_path' => dictionary[schema::NA_KEY_SOURCE_MODEL_PATH].to_s,
                'source_model_guid' => dictionary[schema::NA_KEY_SOURCE_MODEL_GUID].to_s,
                'sketchup_version'  => dictionary[schema::NA_KEY_SKETCHUP_VERSION].to_s,
                'scene_count'       => dictionary[schema::NA_KEY_SCENE_COUNT].to_i,
                'domains_captured'  => na_parse_domain_list(dictionary[schema::NA_KEY_DOMAINS_CAPTURED]),
                'chunk_count'       => dictionary[schema::NA_KEY_PAYLOAD_CHUNK_COUNT].to_i,
                'byte_length'       => dictionary[schema::NA_KEY_PAYLOAD_BYTE_LENGTH].to_i,
                'encoding'          => dictionary[schema::NA_KEY_PAYLOAD_ENCODING].to_s
            }
        rescue => error
            puts "[Na__SceneDataTransfer] Header read warning: #{error.class}: #{error.message}"
            nil
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Header Field Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Mirror the Payload Header Onto Individual Dictionary Keys
        # ------------------------------------------------------------
        # These duplicate values already present inside the JSON, but keeping
        # them as plain keys makes the dictionary legible in SketchUp's native
        # attribute inspector and lets the reader summarise a source model
        # without paying to decompress the whole payload.
        def self.na_write_header_fields(entity, payload_hash)
            schema = Na__SceneDataTransfer__Schema
            source = payload_hash['source'] || {}
            scenes = payload_hash['scenes'] || []

            entity.set_attribute(schema::NA_PAYLOAD_DICTIONARY, schema::NA_KEY_CAPTURED_AT,       payload_hash['captured_at'].to_s)
            entity.set_attribute(schema::NA_PAYLOAD_DICTIONARY, schema::NA_KEY_CAPTURED_BY,       payload_hash['captured_by'].to_s)
            entity.set_attribute(schema::NA_PAYLOAD_DICTIONARY, schema::NA_KEY_SOURCE_MODEL_NAME, source['name'].to_s)
            entity.set_attribute(schema::NA_PAYLOAD_DICTIONARY, schema::NA_KEY_SOURCE_MODEL_PATH, source['path'].to_s)
            entity.set_attribute(schema::NA_PAYLOAD_DICTIONARY, schema::NA_KEY_SOURCE_MODEL_GUID, source['guid'].to_s)
            entity.set_attribute(schema::NA_PAYLOAD_DICTIONARY, schema::NA_KEY_SKETCHUP_VERSION,  source['sketchup_version'].to_s)
            entity.set_attribute(schema::NA_PAYLOAD_DICTIONARY, schema::NA_KEY_SCENE_COUNT,       scenes.length)
            entity.set_attribute(
                schema::NA_PAYLOAD_DICTIONARY,
                schema::NA_KEY_DOMAINS_CAPTURED,
                Array(payload_hash['domains_captured']).join(',')
            )
        end
        private_class_method :na_write_header_fields
        # ------------------------------------------------------------

        # HELPER FUNCTION | Split a Stored Comma List Back Into Domain Keys
        # ------------------------------------------------------------
        def self.na_parse_domain_list(stored_value)
            stored_value.to_s.split(',').map(&:strip).reject(&:empty?)
        end
        private_class_method :na_parse_domain_list
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Chunk Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Build the Zero-Padded Key Name for a Chunk Index
        # ------------------------------------------------------------
        def self.na_chunk_key(chunk_index)
            format('%s%04d', Na__SceneDataTransfer__Schema::NA_PAYLOAD_CHUNK_PREFIX, chunk_index)
        end
        private_class_method :na_chunk_key
        # ------------------------------------------------------------

        # HELPER FUNCTION | Slice an Encoded String Into Fixed-Size Chunks
        # ------------------------------------------------------------
        def self.na_split_into_chunks(encoded_text)
            chunk_size = Na__SceneDataTransfer__Schema::NA_CHUNK_SIZE_BYTES
            return [''] if encoded_text.nil? || encoded_text.empty?

            encoded_text.scan(/.{1,#{chunk_size}}/m)
        end
        private_class_method :na_split_into_chunks
        # ------------------------------------------------------------

        # HELPER FUNCTION | Reassemble Chunks Strictly by Index
        # ------------------------------------------------------------
        # AttributeDictionary#each has no ordering guarantee, so the only safe
        # reassembly walks the index range. A missing chunk aborts the read
        # rather than returning a silently truncated payload.
        def self.na_join_chunks(dictionary, chunk_count)
            buffer = ''

            (0...chunk_count).each do |chunk_index|
                chunk_text = dictionary[na_chunk_key(chunk_index)]

                if chunk_text.nil?
                    puts "[Na__SceneDataTransfer] Payload is missing chunk #{chunk_index} of #{chunk_count}."
                    return nil
                end

                buffer << chunk_text.to_s
            end

            buffer
        end
        private_class_method :na_join_chunks
        # ------------------------------------------------------------

        # HELPER FUNCTION | Delete Every Numbered Chunk Key From an Entity
        # ------------------------------------------------------------
        def self.na_clear_payload_chunks(entity)
            schema     = Na__SceneDataTransfer__Schema
            dictionary = entity.attribute_dictionary(schema::NA_PAYLOAD_DICTIONARY, false)
            return true unless dictionary

            prefix      = schema::NA_PAYLOAD_CHUNK_PREFIX
            stored_keys = dictionary.keys.dup                                       # <-- Snapshot; mutating while iterating skips keys

            stored_keys.each do |stored_key|
                next unless stored_key.to_s.start_with?(prefix)

                dictionary.delete_key(stored_key)
            end

            true
        rescue => error
            puts "[Na__SceneDataTransfer] Chunk cleanup warning: #{error.class}: #{error.message}"
            false
        end
        private_class_method :na_clear_payload_chunks
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Encoding Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Choose an Encoding for a JSON String
        # ------------------------------------------------------------
        def self.na_encoding_for(json_text)
            schema = Na__SceneDataTransfer__Schema

            if json_text.length >= schema::NA_COMPRESS_THRESHOLD_BYTES
                schema::NA_ENCODING_DEFLATE_B64
            else
                schema::NA_ENCODING_RAW
            end
        end
        private_class_method :na_encoding_for
        # ------------------------------------------------------------

        # HELPER FUNCTION | Apply the Chosen Encoding
        # ------------------------------------------------------------
        def self.na_encode(json_text, encoding_key)
            return json_text unless encoding_key == Na__SceneDataTransfer__Schema::NA_ENCODING_DEFLATE_B64

            Base64.strict_encode64(Zlib::Deflate.deflate(json_text))
        rescue => error
            puts "[Na__SceneDataTransfer] Compression fell back to raw: #{error.class}: #{error.message}"
            json_text
        end
        private_class_method :na_encode
        # ------------------------------------------------------------

        # HELPER FUNCTION | Reverse the Stored Encoding
        # ------------------------------------------------------------
        def self.na_decode(encoded_text, encoding_key)
            return encoded_text unless encoding_key == Na__SceneDataTransfer__Schema::NA_ENCODING_DEFLATE_B64

            Zlib::Inflate.inflate(Base64.strict_decode64(encoded_text))
        rescue => error
            puts "[Na__SceneDataTransfer] Decompression error: #{error.class}: #{error.message}"
            nil
        end
        private_class_method :na_decode
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__SceneDataTransfer__Codec
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
