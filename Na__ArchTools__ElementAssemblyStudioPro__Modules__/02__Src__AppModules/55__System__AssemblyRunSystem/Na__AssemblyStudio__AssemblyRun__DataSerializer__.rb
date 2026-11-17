# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - ASSEMBLY RUN SYSTEM - DATA SERIALIZER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__AssemblyRun__DataSerializer__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__AssemblyRunSystem
# MODULE     : Na__DataSerializer
# AUTHOR     : Noble Architecture
# PURPOSE    : ARN ids, the run's saved configuration (its path, legs, panel
#              types and settings) on the run's own definition, the component
#              name, and the membership stamp on every span's element.
# CREATED    : 16-Nov-2026 (V2.7.0)
#
# WHERE A RUN'S DATA LIVES (the path is DATA, as a Profile Path Tracer trace
# keeps its PathRuns: the geometry is rebuilt from it, never read back)
# - On the run's ComponentInstance  : Na__AssemblyRunConfiguratorInfo
#       RunID, SketchUpInstanceName, SketchUpDefinitionName
# - On the run's ComponentDefinition: Na__AssemblyRunConfigurator_ARN001
#       Na__AssemblyRunMetadata, Na__AssemblyRunComponents (one row per span:
#       leg, place, panel type, element id), Na__AssemblyRunConfiguration
# - On each span's element instance : Na__AssemblyRunMemberInfo
#       RunID, PanelType, Leg, Span
#   Every length is millimetres in the run's own frame, so a run that is
#   moved, turned or nested carries its path with it unchanged.
#
# COMPONENT NAME
# - ARN001__AssemblyRun__<optional name>. The head is fixed and machine read;
#   the tail is the user's (Na__ComponentNameSuffix).
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../02__AppData/Na__AssemblyStudio__AppData__SerializerBase__'
require_relative '../04__GeometryHelpers/Na__AssemblyStudio__ComponentNameSuffix__'
require_relative 'Na__AssemblyStudio__AssemblyRun__Defaults__'

module Na__AssemblyStudio
module Na__AssemblyRunSystem
    module Na__DataSerializer

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools     = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        SerializerBase = Na__AssemblyStudio::Na__AppData::Na__SerializerBase
        NameSuffix     = Na__AssemblyStudio::Na__GeometryHelpers::Na__ComponentNameSuffix
        Defaults       = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__Defaults

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Serializer Config
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | The SerializerBase Contract (AppConfig, Then Defaults)
        # ------------------------------------------------------------
        def self.na_config
            from_app = SerializerBase.na_config_from_app_config("assemblyRunSystem")
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

        # FUNCTION | The Next Free ARN Id
        # ------------------------------------------------------------
        def self.na_generate_next_id
            SerializerBase.na_generate_next_id(na_config)
        end
        # ---------------------------------------------------------------

        # FUNCTION | The ARN Id a Component Instance Carries (or Nil)
        # ------------------------------------------------------------
        def self.na_get_id_from_instance(instance)
            SerializerBase.na_get_id_from_instance(na_config, instance)
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Save / Load
# -----------------------------------------------------------------------------

        # FUNCTION | Save the Root Payload on the Run's Definition
        # ------------------------------------------------------------
        # Written straight onto the definition given, not looked up by id:
        # a run mid-build has its definition in hand, and two copies of a
        # run made unique by hand would otherwise share one lookup.
        # @return [Boolean]
        def self.na_save(definition, run_id, data)
            cfg = na_config
            return false unless definition && definition.valid?
            return false unless SerializerBase.na_valid_id?(cfg, run_id) && SerializerBase.na_valid_structure?(cfg, data)

            dict = definition.attribute_dictionary("#{cfg[:definition_dict_prefix]}#{run_id}", true)
            dict[cfg[:metadata_key]]      = JSON.generate(data[cfg[:metadata_key]]      || [])
            dict[cfg[:components_key]]    = JSON.generate(data[cfg[:components_key]]    || [])
            dict[cfg[:configuration_key]] = JSON.generate(data[cfg[:configuration_key]] || {})
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Load the Root Payload From a Run Instance's Definition
        # ------------------------------------------------------------
        # @return [Hash, nil]
        def self.na_load_from_instance(instance, run_id)
            SerializerBase.na_load_from_instance(na_config, instance, run_id)
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Identity and Name
# -----------------------------------------------------------------------------

        # FUNCTION | Stamp the Id and Write the Component Name
        # ------------------------------------------------------------
        # @param component_name [String, Symbol] the name tail, or
        #     Na__ComponentNameSuffix::NA_KEEP to keep the one it has
        # @return [String, nil] the full name written
        def self.na_apply_identity(instance, run_id, component_name = NameSuffix::NA_KEEP)
            return nil unless instance.is_a?(Sketchup::ComponentInstance) && instance.valid?

            full_name = NameSuffix.na_apply(instance, Defaults.na_name_head(run_id), component_name)
            cfg       = na_config
            instance.set_attribute(cfg[:instance_dict_name], cfg[:instance_id_attribute], run_id)
            instance.set_attribute(cfg[:instance_dict_name], "SketchUpInstanceName",   instance.name)
            instance.set_attribute(cfg[:instance_dict_name], "SketchUpDefinitionName", instance.definition.name)
            full_name
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Name Tail a Run Wears Now
        # ------------------------------------------------------------
        def self.na_current_tail(instance, run_id)
            NameSuffix.na_current_suffix(instance, Defaults.na_name_head(run_id))
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Membership (a Span's Element Inside a Run)
# -----------------------------------------------------------------------------

        # FUNCTION | Stamp a Span's Element With Its Run, Panel Type and Place
        # ------------------------------------------------------------
        def self.na_stamp_member(instance, run_id, type_code, leg_index, span_index)
            instance.set_attribute(Defaults::NA_MEMBER_DICT, Defaults::NA_MEMBER_KEY_RUN_ID, run_id)
            instance.set_attribute(Defaults::NA_MEMBER_DICT, Defaults::NA_MEMBER_KEY_TYPE,   type_code)
            instance.set_attribute(Defaults::NA_MEMBER_DICT, Defaults::NA_MEMBER_KEY_LEG,    leg_index)
            instance.set_attribute(Defaults::NA_MEMBER_DICT, Defaults::NA_MEMBER_KEY_SPAN,   span_index)
        end
        # ---------------------------------------------------------------

        # FUNCTION | What a Selected Instance Is Inside a Run (or Nil)
        # ------------------------------------------------------------
        # The instance must be a direct child of a run's definition and wear
        # the membership stamp of that same run. A copy dragged out of its
        # run keeps the stamp but has another parent, so it is no member.
        # @return [Hash, nil] { :run_id, :run_definition, :type, :leg, :span }
        def self.na_member_of(instance)
            return nil unless instance.is_a?(Sketchup::ComponentInstance) && instance.valid?
            run_id = instance.get_attribute(Defaults::NA_MEMBER_DICT, Defaults::NA_MEMBER_KEY_RUN_ID)
            return nil unless run_id

            parent = instance.parent
            return nil unless parent.is_a?(Sketchup::ComponentDefinition)
            return nil unless parent.attribute_dictionary("#{Defaults::NA_DEF_DICT_PREFIX}#{run_id}")
            {
                :run_id         => run_id,
                :run_definition => parent,
                :type           => instance.get_attribute(Defaults::NA_MEMBER_DICT, Defaults::NA_MEMBER_KEY_TYPE).to_s,
                :leg            => instance.get_attribute(Defaults::NA_MEMBER_DICT, Defaults::NA_MEMBER_KEY_LEG).to_i,
                :span           => instance.get_attribute(Defaults::NA_MEMBER_DICT, Defaults::NA_MEMBER_KEY_SPAN).to_i
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Every Span Element Standing Directly in a Run's Definition
        # ------------------------------------------------------------
        # @return [Array<Sketchup::ComponentInstance>]
        def self.na_members(run_definition)
            run_definition.entities.grep(Sketchup::ComponentInstance).select do |instance|
                instance.get_attribute(Defaults::NA_MEMBER_DICT, Defaults::NA_MEMBER_KEY_TYPE)
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Placed Instance of a Run by Its Definition
        # ------------------------------------------------------------
        # A run may be placed more than once (each copy shows the same run).
        # @return [Sketchup::ComponentInstance, nil] its first placed copy
        def self.na_instance_of(run_definition)
            run_definition.instances.find { |instance| instance.valid? && na_get_id_from_instance(instance) }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Every Run Placed in the Model, at Any Depth
        # ------------------------------------------------------------
        # @return [Array<Sketchup::ComponentInstance>] one per run id
        def self.na_all_runs(model = Sketchup.active_model)
            return [] unless model
            seen = {}
            model.definitions.each do |definition|
                next if definition.image?
                definition.instances.each do |instance|
                    run_id = na_get_id_from_instance(instance)
                    seen[run_id] ||= instance if run_id
                end
            end
            seen.values
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__DataSerializer
end # module Na__AssemblyRunSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
