# =============================================================================
# NA NOBLE3D MODELLING TOOLS - CONVERT COMPONENTS TO GROUPS - COMPONENT PROPS
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__ConvertComponentsToGroups__ComponentProps__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__ConvertComponentsToGroups__ComponentProps
# PURPOSE    : Preserve component instance properties when creating replacement groups
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__ConvertComponentsToGroups__ComponentProps

# -----------------------------------------------------------------------------
# REGION | Property Transfer
# -----------------------------------------------------------------------------

        # FUNCTION | Extract Supported Properties from a Component Instance
        # ------------------------------------------------------------
        def self.Na__ConvertComponentsToGroups__ComponentProps__Extract(component_instance)
            {
                name: component_instance.name.to_s,
                definition_name: component_instance.definition.name.to_s,
                transformation: component_instance.transformation,
                layer: component_instance.layer,
                material: component_instance.material,
                hidden: component_instance.hidden?,
                casts_shadows: component_instance.casts_shadows?,
                receives_shadows: component_instance.receives_shadows?,
                attributes: Na__ConvertComponentsToGroups__EntityUtils.Na__ConvertComponentsToGroups__EntityUtils__ExtractAttributeDictionaries(component_instance)
            }
        end
        # ------------------------------------------------------------

        # FUNCTION | Apply Extracted Component Properties to a Group
        # ------------------------------------------------------------
        def self.Na__ConvertComponentsToGroups__ComponentProps__ApplyToGroup(group, properties)
            na_apply_name(group, properties)
            na_apply_optional_entity_property(group, :layer=, properties[:layer])
            na_apply_optional_entity_property(group, :material=, properties[:material])
            na_apply_boolean_entity_properties(group, properties)

            Na__ConvertComponentsToGroups__EntityUtils.Na__ConvertComponentsToGroups__EntityUtils__ApplyAttributeDictionaries(group, properties[:attributes])
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Apply Preferred Group Name
        # ------------------------------------------------------------
        def self.na_apply_name(group, properties)
            preferred_name = properties[:name].to_s.empty? ? properties[:definition_name].to_s : properties[:name].to_s
            group.name = preferred_name unless preferred_name.empty?
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Apply Optional Entity Property
        # ------------------------------------------------------------
        def self.na_apply_optional_entity_property(entity, setter_name, value)
            entity.public_send(setter_name, value) if value
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Apply Boolean Entity Properties
        # ------------------------------------------------------------
        def self.na_apply_boolean_entity_properties(group, properties)
            group.hidden = !!properties[:hidden]
            group.casts_shadows = !!properties[:casts_shadows]
            group.receives_shadows = !!properties[:receives_shadows]
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__ConvertComponentsToGroups__ComponentProps
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
