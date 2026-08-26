# =============================================================================
# NA NOBLE3D MODELLING TOOLS - SCENE IMAGE EXPORTER - MODEL STATE
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__SceneImageExporter__ModelState__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__SceneImageExporter__ModelState
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Serialise the scene tick state and the last export settings into
#              a model attribute dictionary so both survive save / reopen.
# CREATED    : 2026
#
# PERSISTENCE PATTERN:
# Mirrors Na__ComponentEditorTools::Na__LibrarySerializer. The dictionary is
# fetched with model.attribute_dictionary(name, true) and every value is stored
# as a plain string so each key stays individually readable in SketchUp's native
# attribute inspector. Only the scene tick list is a JSON string, because it is
# genuinely a list.
#
# Dictionary : "Na__SceneImageExporter" on Sketchup::Model
#
# Keys       : schema_version           - dictionary format version
#              selected_scenes          - JSON array of ticked scene names
#              preset_key               - active export preset
#              image_height             - output height in pixels
#              aspect_mode              - aspect ratio mode key
#              custom_aspect_width      - custom ratio numerator
#              custom_aspect_height     - custom ratio denominator
#              file_format              - png / jpg / tif / bmp
#              jpeg_quality             - 0.0 to 1.0, JPEG only
#              line_scale_factor        - write_image :scale_factor
#              transparent_background   - PNG alpha flag
#              antialias                - always "true", stored for the record
#              filename_pattern         - token pattern for output names
#              overwrite_mode           - overwrite / skip / unique
#              export_folder            - last chosen output folder
#              silhouette_width         - profile edge weight when forced on
#              line_extension_amount    - edge overshoot when forced on
#              render_override_<key>    - one key per tri-state render override
#              last_export_time         - human readable stamp of the last run
#              last_export_count        - files written by the last run
#              last_export_folder       - folder the last run wrote into
#
# =============================================================================

require 'json'

module Na__Noble3dModellingTools
    module Na__SceneImageExporter__ModelState

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_STATE_DICTIONARY   = 'Na__SceneImageExporter'.freeze
        NA_OVERRIDE_KEY_PREFIX = 'render_override_'.freeze

        NA_INTEGER_KEYS = %w[
            image_height custom_aspect_width custom_aspect_height
            silhouette_width line_extension_amount
        ].freeze

        NA_FLOAT_KEYS = %w[
            jpeg_quality line_scale_factor
        ].freeze

        NA_BOOLEAN_KEYS = %w[
            transparent_background antialias
        ].freeze

        NA_STRING_KEYS = %w[
            preset_key aspect_mode file_format filename_pattern
            overwrite_mode export_folder
        ].freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Read API
# -----------------------------------------------------------------------------

        # FUNCTION | Read the Persisted Settings Hash, Merged Over the Defaults
        # ------------------------------------------------------------
        def self.Na__SceneImageExporter__ReadSettings(model)
            settings = Na__SceneImageExporter__Presets.Na__SceneImageExporter__DefaultSettings
            dictionary = na_dictionary(model, false)
            return settings unless dictionary

            NA_STRING_KEYS.each do |key|
                stored = dictionary[key]
                settings[key] = stored.to_s unless stored.nil? || stored.to_s.empty?
            end

            NA_INTEGER_KEYS.each do |key|
                stored = dictionary[key]
                settings[key] = stored.to_i unless stored.nil? || stored.to_s.empty?
            end

            NA_FLOAT_KEYS.each do |key|
                stored = dictionary[key]
                settings[key] = stored.to_f unless stored.nil? || stored.to_s.empty?
            end

            NA_BOOLEAN_KEYS.each do |key|
                stored = dictionary[key]
                settings[key] = na_boolean_from(stored) unless stored.nil? || stored.to_s.empty?
            end

            settings['antialias'] = true                                            # <-- Antialiasing is never user-disabled

            overrides = settings['render_overrides']
            Na__SceneImageExporter__Presets::NA_RENDER_OVERRIDES.each do |entry|
                stored = dictionary["#{NA_OVERRIDE_KEY_PREFIX}#{entry['key']}"]
                next if stored.nil? || stored.to_s.empty?

                overrides[entry['key']] = stored.to_s
            end
            settings['render_overrides'] = overrides

            settings
        rescue => error
            puts "[Na__SceneImageExporter] Settings read warning: #{error.class}: #{error.message}"
            Na__SceneImageExporter__Presets.Na__SceneImageExporter__DefaultSettings
        end
        # ------------------------------------------------------------

        # FUNCTION | Read the Ticked Scene Names, Filtered to Scenes That Still Exist
        # ------------------------------------------------------------
        def self.Na__SceneImageExporter__ReadSelectedScenes(model)
            dictionary = na_dictionary(model, false)
            return [] unless dictionary

            raw_value = dictionary['selected_scenes'].to_s
            return [] if raw_value.empty?

            stored_names = JSON.parse(raw_value)
            return [] unless stored_names.is_a?(Array)

            live_names = model.pages.map { |page| page.name.to_s }
            stored_names.map(&:to_s).select { |name| live_names.include?(name) }
        rescue JSON::ParserError
            []
        rescue => error
            puts "[Na__SceneImageExporter] Scene state read warning: #{error.class}: #{error.message}"
            []
        end
        # ------------------------------------------------------------

        # FUNCTION | Read the Summary of the Previous Export Run
        # ------------------------------------------------------------
        def self.Na__SceneImageExporter__ReadLastExportSummary(model)
            dictionary = na_dictionary(model, false)
            return { 'time' => '', 'count' => 0, 'folder' => '' } unless dictionary

            {
                'time'   => dictionary['last_export_time'].to_s,
                'count'  => dictionary['last_export_count'].to_i,
                'folder' => dictionary['last_export_folder'].to_s
            }
        rescue => error
            puts "[Na__SceneImageExporter] Export summary read warning: #{error.class}: #{error.message}"
            { 'time' => '', 'count' => 0, 'folder' => '' }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Write API
# -----------------------------------------------------------------------------

        # FUNCTION | Persist the Settings Hash to the Model Dictionary
        # ------------------------------------------------------------
        def self.Na__SceneImageExporter__WriteSettings(model, settings_hash)
            return false unless model && settings_hash.is_a?(Hash)

            na_within_silent_operation(model, 'NA Scene Image Exporter Settings') do
                dictionary = na_dictionary(model, true)
                raise 'Could not create the Na__SceneImageExporter dictionary.' unless dictionary

                dictionary['schema_version'] = Na__SceneImageExporter__Presets::NA_SCHEMA_VERSION

                (NA_STRING_KEYS + NA_INTEGER_KEYS + NA_FLOAT_KEYS + NA_BOOLEAN_KEYS).each do |key|
                    next unless settings_hash.key?(key)

                    dictionary[key] = settings_hash[key].to_s
                end

                overrides = settings_hash['render_overrides']
                if overrides.is_a?(Hash)
                    Na__SceneImageExporter__Presets::NA_RENDER_OVERRIDES.each do |entry|
                        state_value = overrides[entry['key']].to_s
                        next if state_value.empty?

                        dictionary["#{NA_OVERRIDE_KEY_PREFIX}#{entry['key']}"] = state_value
                    end
                end
            end

            true
        rescue => error
            puts "[Na__SceneImageExporter] Settings write warning: #{error.class}: #{error.message}"
            false
        end
        # ------------------------------------------------------------

        # FUNCTION | Persist the Ticked Scene Names to the Model Dictionary
        # ------------------------------------------------------------
        def self.Na__SceneImageExporter__WriteSelectedScenes(model, scene_names)
            return false unless model

            clean_names = Array(scene_names).map(&:to_s).reject(&:empty?).uniq

            na_within_silent_operation(model, 'NA Scene Image Exporter Selection') do
                dictionary = na_dictionary(model, true)
                raise 'Could not create the Na__SceneImageExporter dictionary.' unless dictionary

                dictionary['schema_version']  = Na__SceneImageExporter__Presets::NA_SCHEMA_VERSION
                dictionary['selected_scenes'] = clean_names.to_json
            end

            true
        rescue => error
            puts "[Na__SceneImageExporter] Scene state write warning: #{error.class}: #{error.message}"
            false
        end
        # ------------------------------------------------------------

        # FUNCTION | Persist a Summary of the Export Run Just Completed
        # ------------------------------------------------------------
        def self.Na__SceneImageExporter__WriteLastExportSummary(model, written_count, folder_path)
            return false unless model

            na_within_silent_operation(model, 'NA Scene Image Exporter Summary') do
                dictionary = na_dictionary(model, true)
                raise 'Could not create the Na__SceneImageExporter dictionary.' unless dictionary

                dictionary['last_export_time']   = Time.now.strftime('%d-%b-%Y %H:%M')
                dictionary['last_export_count']  = written_count.to_i.to_s
                dictionary['last_export_folder'] = folder_path.to_s
            end

            true
        rescue => error
            puts "[Na__SceneImageExporter] Export summary write warning: #{error.class}: #{error.message}"
            false
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Fetch or Create the Model Attribute Dictionary
        # ------------------------------------------------------------
        def self.na_dictionary(model, create_flag)
            return nil unless model

            model.attribute_dictionary(NA_STATE_DICTIONARY, create_flag)
        end
        private_class_method :na_dictionary
        # ------------------------------------------------------------

        # HELPER FUNCTION | Coerce a Stored String Back Into a Boolean
        # ------------------------------------------------------------
        def self.na_boolean_from(stored_value)
            %w[true 1 yes].include?(stored_value.to_s.strip.downcase)
        end
        private_class_method :na_boolean_from
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

    end # module Na__SceneImageExporter__ModelState
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
