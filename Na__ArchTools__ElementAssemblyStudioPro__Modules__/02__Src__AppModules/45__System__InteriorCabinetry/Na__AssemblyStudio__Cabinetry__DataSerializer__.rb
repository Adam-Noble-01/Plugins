# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - INTERIOR CABINETRY SYSTEM - DATA SERIALIZER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__Cabinetry__DataSerializer__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__InteriorCabinetrySystem
# MODULE     : Na__DataSerializer
# AUTHOR     : Noble Architecture
# PURPOSE    : ACB ids, the saved configuration on each cabinet's definition,
#              and the component name, through the shared Na__SerializerBase.
# CREATED    : 29-Oct-2026
#
# DICTIONARIES
# - On the ComponentInstance  : Na__CabinetConfiguratorInfo
#       CabinetID, SketchUpInstanceName, SketchUpDefinitionName
# - On the ComponentDefinition: Na__CabinetConfigurator_ACB001
#       Na__CabinetMetadata, Na__CabinetComponents, Na__CabinetConfiguration
#
# COMPONENT NAME
# - <ID>__<TypeTag>__<optional name>, e.g. ACB004__BaseUnit__Kitchen__Sink.
#   The head is fixed and machine read; the tail is the user's and is kept
#   through every rebuild (Na__ComponentNameSuffix), including a change of
#   unit type, which only swaps the type tag.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../02__AppData/Na__AssemblyStudio__AppData__SerializerBase__'
require_relative '../04__GeometryHelpers/Na__AssemblyStudio__ComponentNameSuffix__'
require_relative 'Na__AssemblyStudio__Cabinetry__Defaults__'

module Na__AssemblyStudio
module Na__InteriorCabinetrySystem
    module Na__DataSerializer

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools     = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        SerializerBase = Na__AssemblyStudio::Na__AppData::Na__SerializerBase
        NameSuffix     = Na__AssemblyStudio::Na__GeometryHelpers::Na__ComponentNameSuffix
        Defaults       = Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__Defaults

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Serializer Config
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | The SerializerBase Contract (AppConfig, Then Defaults)
        # ------------------------------------------------------------
        def self.na_config
            from_app = SerializerBase.na_config_from_app_config("interiorCabinetrySystem")
            (from_app && from_app.values.none? { |value| value.nil? }) ? from_app : Defaults::NA_SERIALIZER_CONFIG
        rescue StandardError
            Defaults::NA_SERIALIZER_CONFIG
        end
        private_class_method :na_config
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Ids
# -----------------------------------------------------------------------------

        # FUNCTION | The Next Free ACB Id
        # ------------------------------------------------------------
        def self.na_generate_next_id
            SerializerBase.na_generate_next_id(na_config)
        end
        # ---------------------------------------------------------------

        # FUNCTION | The ACB Id a Component Instance Carries (or Nil)
        # ------------------------------------------------------------
        def self.na_get_id_from_instance(instance)
            SerializerBase.na_get_id_from_instance(na_config, instance)
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Save / Load
# -----------------------------------------------------------------------------

        # FUNCTION | Save the Root Payload on the Cabinet's Definition
        # ------------------------------------------------------------
        def self.na_save(cabinet_id, data)
            SerializerBase.na_save(na_config, cabinet_id, data)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Load the Root Payload From an Instance's Definition
        # ------------------------------------------------------------
        def self.na_load_from_instance(instance, cabinet_id)
            SerializerBase.na_load_from_instance(na_config, instance, cabinet_id)
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Identity and Name
# -----------------------------------------------------------------------------

        # FUNCTION | Stamp the Id and Write the Component Name
        # ------------------------------------------------------------
        # @param instance       [Sketchup::ComponentInstance]
        # @param cabinet_id     [String]  "ACB001"
        # @param unit_type      [String]  "Base" | "Wall" | "Tower"
        # @param component_name [String, Symbol] the name tail, or
        #                       Na__ComponentNameSuffix::NA_KEEP to keep it
        # @return [String, nil] the full name written
        def self.na_apply_identity(instance, cabinet_id, unit_type, component_name = NameSuffix::NA_KEEP)
            return nil unless instance.is_a?(Sketchup::ComponentInstance) && instance.valid?

            head      = Defaults.na_name_head(cabinet_id, unit_type)
            requested = (component_name == NameSuffix::NA_KEEP) ? na_current_tail(instance, cabinet_id) : component_name
            full_name = NameSuffix.na_apply(instance, head, requested.to_s)

            cfg = na_config
            instance.set_attribute(cfg[:instance_dict_name], cfg[:instance_id_attribute], cabinet_id)
            instance.set_attribute(cfg[:instance_dict_name], "SketchUpInstanceName",   instance.name)
            instance.set_attribute(cfg[:instance_dict_name], "SketchUpDefinitionName", instance.definition.name)
            full_name
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Name Tail an Instance Wears Now, Under Any Type Tag
        # ------------------------------------------------------------
        def self.na_current_tail(instance, cabinet_id)
            Defaults::NA_TYPE_TAGS.keys.each do |unit_type|
                tail = NameSuffix.na_current_suffix(instance, Defaults.na_name_head(cabinet_id, unit_type))
                return tail unless tail.empty?
            end
            ""
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__DataSerializer
end # module Na__InteriorCabinetrySystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
