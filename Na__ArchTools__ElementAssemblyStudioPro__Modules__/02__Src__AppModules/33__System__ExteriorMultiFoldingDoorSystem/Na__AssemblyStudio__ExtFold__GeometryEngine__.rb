# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - BIFOLD DOOR GEOMETRY ENGINE
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtFold__GeometryEngine__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem
# MODULE     : Na__GeometryEngine
# AUTHOR     : Noble Architecture
# PURPOSE    : Top-level orchestrator that turns a bifold-door config
#              Hash into a SketchUp ADR ComponentInstance with N panels,
#              MOD/ROT/MVE markers, head + base track. Selects one of
#              the three Layout algorithms based on `bifold_door_layout`.
# CREATED    : 17-May-2026
#
# DESCRIPTION:
# - Public surface (mirrors `Na__InteriorDoorSystem::Na__GeometryEngine`):
#     * na_build_bifold_door(config, door_id, insertion_origin_in) -> Instance
#     * na_update_bifold_door(instance, config)                    -> Boolean
#     * na_resolve_layout_module(layout_id)                        -> Module
# - Build pipeline:
#     1. Validate config + resolve layout module.
#     2. Allocate a globally-unique ADR id (or reuse the supplied one).
#     3. Create ComponentDefinition "<ADR>__BifoldDoor__".
#     4. Generate panel descriptors via the chosen Layout module.
#     5. Compose the ADR (head + base track + per-panel MOD/ROT/MVE)
#        via `Na__AssemblyComposer.na_compose_adr`.
#     6. Add a single ComponentInstance at insertion_origin_in (or
#        IDENTITY when nil). Tag :proposed_doors when available.
# - Update path clears the definition entities and rebuilds in place;
#   the instance position in the model is preserved.
#
# COORDINATE SYSTEM (door-local, ADR ComponentDefinition):
# - Origin       = bottom-front-left corner of the structural opening.
# - X+           = along the wall (left -> right across opening).
# - Y+           = through the wall depth (front face at Y=0).
# - Z+           = upwards.
#
# DEVELOPMENT LOG:
# 17-May-2026 - Version 0.2.0
# - Phase-3a implementation: full create / update / dispatch surface.
#
# 17-May-2026 - Version 0.1.0
# - Phase-1 scaffold (returned nil).
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__TagManager__'
require_relative 'Na__AssemblyStudio__ExtFold__GeometryHelpers__'
require_relative 'Na__AssemblyStudio__ExtFold__AssemblyComposer__'
require_relative 'Na__AssemblyStudio__ExtFold__Layout__EqualEqual__'
require_relative 'Na__AssemblyStudio__ExtFold__Layout__AllOneWay__'
require_relative 'Na__AssemblyStudio__ExtFold__Layout__MasterSlaves__'
require_relative 'Na__AssemblyStudio__ExtFold__DataSerializer__'

module Na__AssemblyStudio
module Na__ExteriorMultiFoldingDoorSystem
module Na__GeometryEngine

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

    DebugTools         = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
    TagManager         = Na__AssemblyStudio::Na__AppUtils::Na__TagManager
    GeometryHelpers    = Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::Na__GeometryHelpers
    AssemblyComposer   = Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::Na__AssemblyComposer
    DataSerializer     = Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::Na__DataSerializer
    Layout_EqualEqual  = Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::Na__Layout__EqualEqual
    Layout_AllOneWay   = Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::Na__Layout__AllOneWay
    Layout_MasterSlaves = Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::Na__Layout__MasterSlaves

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

    NA_DEFINITION_SUFFIX = "__BifoldDoor__".freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Create
# -----------------------------------------------------------------------------

    # FUNCTION | Build a New Bifold-Door Component Instance
    # ------------------------------------------------------------
    # @param config_hash         [Hash]        full bifold config
    # @param door_id             [String,nil]  pre-allocated ADR id (optional)
    # @param insertion_origin_in [Geom::Point3d,nil] insertion point (inches)
    # @return [Sketchup::ComponentInstance, nil]
    def self.na_build_bifold_door(config_hash, door_id = nil, insertion_origin_in = nil)
        DebugTools.na_debug_method("ExtFold::GeometryEngine.na_build_bifold_door")

        return nil unless config_hash.is_a?(Hash)
        model = Sketchup.active_model
        return nil unless model

        layout_module = na_resolve_layout_module(config_hash["bifold_door_layout"])
        return nil unless layout_module

        descriptors = layout_module.na_generate_panel_descriptors(config_hash)
        if descriptors.nil? || descriptors.empty?
            DebugTools.na_debug_warn("ExtFold: layout '#{config_hash["bifold_door_layout"]}' produced no panels - aborting build")
            return nil
        end

        door_id        ||= AssemblyComposer.na_allocate_adr_id(model)
        definition_name  = "#{door_id}#{NA_DEFINITION_SUFFIX}"

        begin
            door_def         = model.definitions.add(definition_name)
            AssemblyComposer.na_compose_adr(config_hash, descriptors, door_def.entities)

            instance_xform   = na_resolve_insertion_transform(insertion_origin_in)
            instance         = model.active_entities.add_instance(door_def, instance_xform)

            DataSerializer.na_set_door_id_on_instance(instance, door_id)               # <-- Pointer dict + canonical naming

            tag_proposed     = TagManager.na_get_or_create_tag(:proposed_doors)
            instance.layer   = tag_proposed if tag_proposed

            DebugTools.na_debug_geometry("ExtFold: built bifold door #{definition_name} (#{descriptors.length} panels)")
            instance
        rescue StandardError => e
            DebugTools.na_debug_error("Error building bifold door #{definition_name}", e)
            nil
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Update
# -----------------------------------------------------------------------------

    # FUNCTION | Rebuild an Existing Bifold-Door Definition in Place
    # ------------------------------------------------------------
    # @param instance [Sketchup::ComponentInstance]
    # @param config_hash [Hash]
    # @return [Boolean]
    def self.na_update_bifold_door(instance, config_hash)
        DebugTools.na_debug_method("ExtFold::GeometryEngine.na_update_bifold_door")

        return false unless instance && instance.valid?
        return false unless config_hash.is_a?(Hash)

        layout_module = na_resolve_layout_module(config_hash["bifold_door_layout"])
        return false unless layout_module

        descriptors = layout_module.na_generate_panel_descriptors(config_hash)
        return false if descriptors.nil? || descriptors.empty?

        definition = instance.definition
        return false unless definition

        begin
            definition.entities.clear!
            AssemblyComposer.na_compose_adr(config_hash, descriptors, definition.entities)

            DebugTools.na_debug_geometry("ExtFold: updated bifold door #{definition.name} (#{descriptors.length} panels)")
            true
        rescue StandardError => e
            DebugTools.na_debug_error("Error updating bifold door #{definition.name}", e)
            false
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Layout Dispatch
# -----------------------------------------------------------------------------

    # FUNCTION | Resolve the Layout Module for a Given Layout Identifier
    # ------------------------------------------------------------
    # @param layout_id [String] one of EqualEqual | AllOneWay | MasterSlaves
    # @return [Module, nil]
    def self.na_resolve_layout_module(layout_id)
        case layout_id.to_s
        when Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::NA_LAYOUT_EQUAL_EQUAL
            Layout_EqualEqual
        when Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::NA_LAYOUT_ALL_ONE_WAY
            Layout_AllOneWay
        when Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::NA_LAYOUT_MASTER_SLAVES
            Layout_MasterSlaves
        else
            DebugTools.na_debug_warn("ExtFold: unknown layout '#{layout_id}', defaulting to EqualEqual")
            Layout_EqualEqual
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Resolve the Insertion Transform for the New Instance
    # ------------------------------------------------------------
    # Returns a translation transform when the caller supplied a
    # measured Point A, otherwise IDENTITY (caller will engage the
    # SketchUp placement tool just like the Window pipeline).
    def self.na_resolve_insertion_transform(insertion_origin_in)
        return IDENTITY unless insertion_origin_in.is_a?(Geom::Point3d)
        Geom::Transformation.new(insertion_origin_in)
    end
    private_class_method :na_resolve_insertion_transform
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__GeometryEngine
end # module Na__ExteriorMultiFoldingDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
