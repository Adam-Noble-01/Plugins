# =============================================================================
# NA NOBLE3D MODELLING TOOLS - SCENE DATA TRANSFER - MODEL STATE
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__SceneDataTransfer__ModelState__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__SceneDataTransfer__ModelState
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Persist the dialog's own preferences into a model attribute
#              dictionary so they survive save, close and reopen.
# CREATED    : 2026
#
# PERSISTENCE PATTERN:
# Mirrors Na__SceneImageExporter__ModelState. Every value is stored as a plain
# string so each key stays individually readable in SketchUp's native attribute
# inspector. Only genuine lists are JSON.
#
# This dictionary is deliberately SEPARATE from the payload dictionary. The
# payload travels between models; these are just this user's dialog settings and
# must never be confused with captured scene data.
#
# Dictionary : "Na__SceneDataTransfer__UiState" on Sketchup::Model
#
# Keys       : schema_version        - dictionary format version
#              source_model_path     - last source .skp chosen in the Import tab
#              selected_domains      - JSON array of ticked domain keys
#              selected_scenes       - JSON array of ticked source scene names
#              name_suffix           - suffix appended to imported scene names
#              last_import_time      - human readable stamp of the last import
#              last_import_count     - scenes created by the last import
#              last_capture_time     - human readable stamp of the last capture
#              last_capture_count    - scenes captured by the last capture
#
# =============================================================================

require 'json'

module Na__Noble3dModellingTools
    module Na__SceneDataTransfer__ModelState

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_KEY_SOURCE_PATH        = 'source_model_path'.freeze
        NA_KEY_SELECTED_DOMAINS   = 'selected_domains'.freeze
        NA_KEY_SELECTED_SCENES    = 'selected_scenes'.freeze
        NA_KEY_NAME_SUFFIX        = 'name_suffix'.freeze
        NA_KEY_LAST_IMPORT_TIME   = 'last_import_time'.freeze
        NA_KEY_LAST_IMPORT_COUNT  = 'last_import_count'.freeze
        NA_KEY_LAST_CAPTURE_TIME  = 'last_capture_time'.freeze
        NA_KEY_LAST_CAPTURE_COUNT = 'last_capture_count'.freeze

        NA_FALLBACK_PREFERENCE_KEY = 'Na__Noble3dModellingTools__SceneDataTransfer'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Read API
# -----------------------------------------------------------------------------

        # FUNCTION | Read the Persisted Dialog Settings, Merged Over the Defaults
        # ------------------------------------------------------------
        def self.Na__SceneDataTransfer__ReadSettings(model)
            settings   = na_default_settings
            dictionary = na_dictionary(model, false)
            return settings unless dictionary

            stored_path = dictionary[NA_KEY_SOURCE_PATH].to_s
            settings['source_model_path'] = stored_path unless stored_path.empty?

            stored_suffix = dictionary[NA_KEY_NAME_SUFFIX].to_s
            settings['name_suffix'] = stored_suffix unless stored_suffix.empty?

            stored_domains = na_parse_json_array(dictionary[NA_KEY_SELECTED_DOMAINS])
            settings['selected_domains'] = stored_domains unless stored_domains.empty?

            settings['selected_scenes'] = na_parse_json_array(dictionary[NA_KEY_SELECTED_SCENES])

            settings['last_import'] = {
                'time'  => dictionary[NA_KEY_LAST_IMPORT_TIME].to_s,
                'count' => dictionary[NA_KEY_LAST_IMPORT_COUNT].to_i
            }

            settings['last_capture'] = {
                'time'  => dictionary[NA_KEY_LAST_CAPTURE_TIME].to_s,
                'count' => dictionary[NA_KEY_LAST_CAPTURE_COUNT].to_i
            }

            settings
        rescue => error
            puts "[Na__SceneDataTransfer] Settings read warning: #{error.class}: #{error.message}"
            na_default_settings
        end
        # ------------------------------------------------------------

        # FUNCTION | Recall the Last Source Folder Across Models
        # ------------------------------------------------------------
        def self.Na__SceneDataTransfer__RecallSourceFolder(model)
            settings    = Na__SceneDataTransfer__ReadSettings(model)
            stored_path = settings['source_model_path'].to_s

            return File.dirname(stored_path) if !stored_path.empty? && File.exist?(stored_path)

            remembered = Sketchup.read_default(NA_FALLBACK_PREFERENCE_KEY, NA_KEY_SOURCE_PATH, '').to_s
            return File.dirname(remembered) if !remembered.empty? && File.exist?(remembered)

            model_path = model ? model.path.to_s : ''
            return File.dirname(model_path) unless model_path.empty?

            ''
        rescue
            ''
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Write API
# -----------------------------------------------------------------------------

        # FUNCTION | Persist the Dialog Settings to the Model Dictionary
        # ------------------------------------------------------------
        def self.Na__SceneDataTransfer__WriteSettings(model, settings_hash)
            return false unless model && settings_hash.is_a?(Hash)

            na_within_silent_operation(model, 'NA Scene Data Transfer Settings') do
                dictionary = na_dictionary(model, true)
                raise 'Could not create the settings dictionary.' unless dictionary

                dictionary['schema_version'] = Na__SceneDataTransfer__Schema::NA_SCHEMA_VERSION

                na_write_if_present(dictionary, NA_KEY_SOURCE_PATH, settings_hash, 'source_model_path')
                na_write_if_present(dictionary, NA_KEY_NAME_SUFFIX, settings_hash, 'name_suffix')

                dictionary[NA_KEY_SELECTED_DOMAINS] = na_clean_list(settings_hash['selected_domains']).to_json if settings_hash.key?('selected_domains')
                dictionary[NA_KEY_SELECTED_SCENES]  = na_clean_list(settings_hash['selected_scenes']).to_json  if settings_hash.key?('selected_scenes')
            end

            na_remember_source_path(settings_hash['source_model_path'])
            true
        rescue => error
            puts "[Na__SceneDataTransfer] Settings write warning: #{error.class}: #{error.message}"
            false
        end
        # ------------------------------------------------------------

        # FUNCTION | Record a Summary of the Import Just Completed
        # ------------------------------------------------------------
        def self.Na__SceneDataTransfer__WriteLastImport(model, created_count)
            na_write_stamp(model, NA_KEY_LAST_IMPORT_TIME, NA_KEY_LAST_IMPORT_COUNT, created_count, 'NA Scene Data Transfer Import Stamp')
        end
        # ------------------------------------------------------------

        # FUNCTION | Record a Summary of the Capture Just Completed
        # ------------------------------------------------------------
        def self.Na__SceneDataTransfer__WriteLastCapture(model, captured_count)
            na_write_stamp(model, NA_KEY_LAST_CAPTURE_TIME, NA_KEY_LAST_CAPTURE_COUNT, captured_count, 'NA Scene Data Transfer Capture Stamp')
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Build the Default Settings Hash
        # ------------------------------------------------------------
        def self.na_default_settings
            {
                'source_model_path' => '',
                'name_suffix'       => Na__SceneDataTransfer__Schema::NA_DEFAULT_IMPORT_SUFFIX,
                'selected_domains'  => Na__SceneDataTransfer__Schema.Na__SceneDataTransfer__ImplementedDomainKeys,
                'selected_scenes'   => [],
                'last_import'       => { 'time' => '', 'count' => 0 },
                'last_capture'      => { 'time' => '', 'count' => 0 }
            }
        end
        private_class_method :na_default_settings
        # ------------------------------------------------------------

        # HELPER FUNCTION | Write One Timestamp and Count Pair
        # ------------------------------------------------------------
        def self.na_write_stamp(model, time_key, count_key, count_value, operation_name)
            return false unless model

            na_within_silent_operation(model, operation_name) do
                dictionary = na_dictionary(model, true)
                raise 'Could not create the settings dictionary.' unless dictionary

                dictionary[time_key]  = Time.now.strftime('%d-%b-%Y %H:%M')
                dictionary[count_key] = count_value.to_i.to_s
            end

            true
        rescue => error
            puts "[Na__SceneDataTransfer] Stamp write warning: #{error.class}: #{error.message}"
            false
        end
        private_class_method :na_write_stamp
        # ------------------------------------------------------------

        # HELPER FUNCTION | Copy a Settings Value Across When It Is Present
        # ------------------------------------------------------------
        def self.na_write_if_present(dictionary, dictionary_key, settings_hash, settings_key)
            return unless settings_hash.key?(settings_key)

            dictionary[dictionary_key] = settings_hash[settings_key].to_s
        end
        private_class_method :na_write_if_present
        # ------------------------------------------------------------

        # HELPER FUNCTION | Mirror the Source Path Into SketchUp Preferences
        # ------------------------------------------------------------
        # Model dictionaries only help once a model has been used before. The
        # preference copy gives a sensible starting folder in a brand new model.
        def self.na_remember_source_path(source_path)
            clean_path = source_path.to_s.strip
            return if clean_path.empty?

            Sketchup.write_default(NA_FALLBACK_PREFERENCE_KEY, NA_KEY_SOURCE_PATH, clean_path)
        rescue => error
            puts "[Na__SceneDataTransfer] Preference write warning: #{error.class}: #{error.message}"
        end
        private_class_method :na_remember_source_path
        # ------------------------------------------------------------

        # HELPER FUNCTION | Parse a Stored JSON Array Back Into Strings
        # ------------------------------------------------------------
        def self.na_parse_json_array(raw_value)
            text = raw_value.to_s
            return [] if text.empty?

            parsed = JSON.parse(text)
            parsed.is_a?(Array) ? parsed.map(&:to_s) : []
        rescue JSON::ParserError
            []
        end
        private_class_method :na_parse_json_array
        # ------------------------------------------------------------

        # HELPER FUNCTION | Normalise a List Before Storing It
        # ------------------------------------------------------------
        def self.na_clean_list(raw_list)
            Array(raw_list).map(&:to_s).reject(&:empty?).uniq
        end
        private_class_method :na_clean_list
        # ------------------------------------------------------------

        # HELPER FUNCTION | Fetch or Create the Settings Dictionary
        # ------------------------------------------------------------
        def self.na_dictionary(model, create_flag)
            return nil unless model

            model.attribute_dictionary(Na__SceneDataTransfer__Schema::NA_UI_STATE_DICTIONARY, create_flag)
        end
        private_class_method :na_dictionary
        # ------------------------------------------------------------

        # HELPER FUNCTION | Run a Dictionary Write Inside a Transparent Operation
        # ------------------------------------------------------------
        # A transparent operation merges into whatever preceded it, so silently
        # remembering settings never adds a stray step to the user's undo stack.
        def self.na_within_silent_operation(model, operation_name)
            model.start_operation(operation_name, true, false, true)
            yield
            model.commit_operation
            true
        rescue => error
            model.abort_operation rescue nil
            raise error
        end
        private_class_method :na_within_silent_operation
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__SceneDataTransfer__ModelState
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
