# =============================================================================
# NA NOBLE3D MODELLING TOOLS - GROUP / COMPONENT CONVERTER - PROPERTY TRANSFER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__GroupComponentConverter__PropertyTransfer__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__GroupComponentConverter__PropertyTransfer
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Carry instance properties across when a group becomes a
#              component or a component becomes a group
# CREATED    : 2026
#
# CARRIED ACROSS:
# - Name, tag, material, hidden, cast / receive shadows, and every top-level
#   attribute dictionary on the instance.
# - Locked state is captured here but re-applied by the converter last, so a
#   relock can never block the other writes.
#
# NAMING RULES (they round-trip):
# - Group -> Component : the instance keeps the group's name. The new
#                        definition is named after the group, or "Component"
#                        when unnamed, plus __Common when two or more groups
#                        share it or __Unique when one group has it alone.
# - Component -> Group : the group takes the instance name, or the
#                        definition name with any __Common / __Unique suffix
#                        taken off when the instance is unnamed.
#
# NOT CARRIED ACROSS (SketchUp cannot hold them on the other container type):
# - Glue and cut-opening behaviour. Groups cannot glue to or cut faces.
# - Definition-level attributes and descriptions.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__GroupComponentConverter__PropertyTransfer

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_DEFAULT_COMPONENT_NAME = 'Component'.freeze
        NA_SHARED_SUFFIX          = '__Common'.freeze
        NA_SINGLE_SUFFIX          = '__Unique'.freeze
        NA_SUFFIX_PATTERN         = /__(?:Common|Unique)(?:#\d+)?\z/

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Property API
# -----------------------------------------------------------------------------

        # FUNCTION | Capture Every Property Carried Across a Conversion
        # ------------------------------------------------------------
        # @param instance [Sketchup::Group, Sketchup::ComponentInstance]
        # @return [Hash]
        # ------------------------------------------------------------
        def self.Na__GroupComponentConverter__PropertyTransfer__Capture(instance)
            {
                name:             instance.name.to_s,
                definition_name:  na_definition_name(instance),
                transformation:   instance.transformation,
                layer:            instance.layer,
                material:         instance.material,
                hidden:           instance.hidden?,
                casts_shadows:    instance.casts_shadows?,
                receives_shadows: instance.receives_shadows?,
                locked:           instance.locked?,
                attributes:       na_capture_attributes(instance)
            }
        end
        # ------------------------------------------------------------

        # FUNCTION | Apply Captured Properties to the Converted Container
        # ------------------------------------------------------------
        # @param target      [Sketchup::Group, Sketchup::ComponentInstance]
        # @param properties  [Hash] From Capture
        # @param target_name [String] Name to give the converted container
        # ------------------------------------------------------------
        def self.Na__GroupComponentConverter__PropertyTransfer__Apply(target, properties, target_name)
            return unless target && target.valid?

            na_write(target) { target.name = target_name.to_s }
            na_write(target) { target.layer = properties[:layer] } if properties[:layer]
            na_write(target) { target.material = properties[:material] }
            na_write(target) { target.hidden = !!properties[:hidden] }
            na_write(target) { target.casts_shadows = !!properties[:casts_shadows] }
            na_write(target) { target.receives_shadows = !!properties[:receives_shadows] }
            na_apply_attributes(target, properties[:attributes])
        end
        # ------------------------------------------------------------

        # FUNCTION | Name for a Group Converted From a Component
        # ------------------------------------------------------------
        def self.Na__GroupComponentConverter__PropertyTransfer__GroupNameFor(properties)
            instance_name = properties[:name].to_s
            return instance_name unless instance_name.strip.empty?

            na_strip_suffix(properties[:definition_name].to_s)
        end
        # ------------------------------------------------------------

        # FUNCTION | Name a Component Definition Made From Converted Groups
        # ------------------------------------------------------------
        # @param definition [Sketchup::ComponentDefinition]
        # @param group_name [String]  The first group's instance name
        # @param shared     [Boolean] True when two or more groups share it
        # @param model      [Sketchup::Model]
        # ------------------------------------------------------------
        def self.Na__GroupComponentConverter__PropertyTransfer__NameConvertedDefinition(definition, group_name, shared, model)
            return unless definition && definition.valid? && model

            base_name = na_strip_suffix(group_name.to_s.strip)
            base_name = NA_DEFAULT_COMPONENT_NAME if base_name.empty?
            wanted_name = "#{base_name}#{shared ? NA_SHARED_SUFFIX : NA_SINGLE_SUFFIX}"
            return if definition.name.to_s == wanted_name

            definition.name = model.definitions.unique_name(wanted_name)
        rescue => error
            puts "[Na__GroupComponentConverter] Definition naming warning: #{error.class}: #{error.message}"
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Attribute Dictionaries
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Copy Every Top-Level Attribute Dictionary Into a Hash
        # ------------------------------------------------------------
        def self.na_capture_attributes(entity)
            captured = {}
            dictionaries = entity.attribute_dictionaries
            return captured unless dictionaries

            dictionaries.each do |dictionary|
                next unless dictionary

                pairs = {}
                dictionary.each_pair { |key, value| pairs[key] = value }
                captured[dictionary.name] = pairs
            end

            captured
        rescue
            {}
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Write Captured Dictionaries Onto the Converted Container
        # ------------------------------------------------------------
        # Protected or read-only keys raise; each one is skipped on its own
        # so one refusal cannot drop the rest of the dictionary.
        # ------------------------------------------------------------
        def self.na_apply_attributes(entity, captured)
            return unless captured.is_a?(Hash)

            captured.each do |dictionary_name, pairs|
                next unless pairs.is_a?(Hash)

                pairs.each do |key, value|
                    na_write(entity) { entity.set_attribute(dictionary_name, key, value) }
                end
            end
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Drop a Trailing __Common / __Unique Suffix and Its Counter
        # ------------------------------------------------------------
        def self.na_strip_suffix(name_text)
            name_text.sub(NA_SUFFIX_PATTERN, '')
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Definition Name of an Instance, Empty When Unreadable
        # ------------------------------------------------------------
        def self.na_definition_name(instance)
            instance.definition.name.to_s
        rescue
            ''
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Run One Property Write, Ignoring a Refusal
        # ------------------------------------------------------------
        def self.na_write(entity)
            return unless entity && entity.valid?

            yield
        rescue
            nil
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__GroupComponentConverter__PropertyTransfer
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
