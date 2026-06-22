# =============================================================================
# NA COMPONENT EDITOR TOOLS - LIBRARY MANAGER | SERIALIZER
# =============================================================================
#
# FILE       : Na__ComponentEditorTools__LibraryManager__Serializer__.rb
# NAMESPACE  : Na__ComponentEditorTools::Na__LibrarySerializer
# PURPOSE    : Read and write bespoke per-component library data to/from the
#              component definition's own attribute dictionary
#              "Na__ComponentLibrary". Each field is a plain string value so
#              it is individually inspectable via SketchUp's native attribute
#              inspector and travels with every .skp file in the library.
#
#              Reserved core keys: code, gallery_name, notes.
#              Any other key in "Na__ComponentLibrary" is a user custom field.
#
#              EAP pattern: definition.attribute_dictionary(name, true) then
#              dict[key] = value  /  JSON.parse(dict[key])
# CREATED    : 2026
#
# =============================================================================

module Na__ComponentEditorTools
    module Na__LibrarySerializer

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_LIBRARY_DICT = 'Na__ComponentLibrary'.freeze
        NA_CORE_KEYS    = %w[code gallery_name notes category type truevision_valid].freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Code Derivation
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__DeriveCode(definition_name)
            return '' if definition_name.to_s.empty?

            str = definition_name.to_s

            # Pattern: leading digit groups separated by single underscores
            # ending at a double underscore boundary
            # e.g. "03_11__Whitecard__..."  -> "03_11__"
            #      "27_4003__Bathroom__..." -> "27_4003__"
            #      "90_9031__..."           -> "90_9031__"
            match = str.match(/\A(\d+(?:_\d+)*__)/)
            return match[1] if match

            # Space-separated variant: "85 85 Stairs..." -> "85 85"
            match = str.match(/\A(\d+(?:[ _]\d+)+)(?=[ _])/)
            return match[1] if match

            # Single leading number: "27Component" -> "27"
            match = str.match(/\A(\d+)/)
            return match[1] if match

            ''
        rescue
            ''
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Read (called during extraction - read-only, no .skp writes)
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__ReadFromDefinition(definition)
            dict = definition.attribute_dictionary(NA_LIBRARY_DICT)

            stored_code      = dict ? dict['code'].to_s              : ''
            gallery_name     = dict ? dict['gallery_name'].to_s      : ''
            notes            = dict ? dict['notes'].to_s             : ''
            category         = dict ? dict['category'].to_s          : ''
            type_value       = dict ? dict['type'].to_s              : ''
            truevision_valid = dict ? dict['truevision_valid'].to_s  : ''

            derived_code = self.Na__ComponentEditorTools__DeriveCode(definition.name.to_s)
            display_code = stored_code.empty? ? derived_code : stored_code

            custom = {}
            if dict
                dict.each_pair do |key, value|
                    next if NA_CORE_KEYS.include?(key.to_s)

                    custom[key.to_s] = value.to_s
                end
            end

            {
                'code'             => display_code,
                'code_stored'      => stored_code,
                'code_derived'     => derived_code,
                'gallery_name'     => gallery_name,
                'notes'            => notes,
                'category'         => category,
                'type'             => type_value,
                'truevision_valid' => truevision_valid,
                'custom'           => custom
            }
        rescue => error
            puts "[Na__ComponentEditorTools] Serializer read warning: #{error.class}: #{error.message}"
            {
                'code'             => '',
                'code_stored'      => '',
                'code_derived'     => '',
                'gallery_name'     => '',
                'notes'            => '',
                'category'         => '',
                'type'             => '',
                'truevision_valid' => '',
                'custom'           => {}
            }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Write (called by Editor during LoadEditSaveRemove - writes to .skp)
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__WriteToDefinition(definition, data_hash)
            dict = definition.attribute_dictionary(NA_LIBRARY_DICT, true)
            raise 'Could not create Na__ComponentLibrary dictionary.' unless dict

            code_value       = data_hash['code'].to_s.strip
            gallery_value    = data_hash['gallery_name'].to_s
            notes_value      = data_hash['notes'].to_s
            category_value   = data_hash['category'].to_s
            type_value       = data_hash['type'].to_s
            tv_valid_value   = data_hash['truevision_valid'].to_s

            dict['code']             = code_value   unless code_value.empty?
            dict['gallery_name']     = gallery_value
            dict['notes']            = notes_value
            dict['category']         = category_value
            dict['type']             = type_value
            dict['truevision_valid'] = tv_valid_value

            custom_keys = data_hash['custom']
            if custom_keys.is_a?(Hash)
                custom_keys.each do |key, value|
                    clean_key = key.to_s.strip
                    next if clean_key.empty? || NA_CORE_KEYS.include?(clean_key)

                    dict[clean_key] = value.to_s
                end
            end

            deleted_keys = data_hash['deleted_custom_keys']
            if deleted_keys.is_a?(Array)
                deleted_keys.each do |key|
                    clean_key = key.to_s.strip
                    next if clean_key.empty? || NA_CORE_KEYS.include?(clean_key)

                    definition.delete_attribute(NA_LIBRARY_DICT, clean_key) rescue nil
                end
            end

            true
        rescue => error
            puts "[Na__ComponentEditorTools] Serializer write warning: #{error.class}: #{error.message}"
            false
        end

        # Surgical write of a single core dictionary key without disturbing the
        # other stored keys (used by inline Index editing). For 'code', an empty
        # value clears the stored override so the derived code is used again.
        def self.Na__ComponentEditorTools__WriteSingleField(definition, field_name, value)
            clean_field = field_name.to_s.strip
            raise 'Field name is required.' if clean_field.empty?

            dict = definition.attribute_dictionary(NA_LIBRARY_DICT, true)
            raise 'Could not create Na__ComponentLibrary dictionary.' unless dict

            if clean_field == 'code'
                code_value = value.to_s.strip
                if code_value.empty?
                    definition.delete_attribute(NA_LIBRARY_DICT, 'code') rescue nil
                else
                    dict['code'] = code_value
                end
            else
                dict[clean_field] = value.to_s
            end

            true
        rescue => error
            puts "[Na__ComponentEditorTools] Serializer single-field write warning: #{error.class}: #{error.message}"
            false
        end

# endregion -------------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
