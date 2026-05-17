# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - SLIDING DOOR GEOMETRY ENGINE
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtSlide__GeometryEngine__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem
# MODULE     : Na__GeometryEngine
# AUTHOR     : Noble Architecture
# PURPOSE    : Top-level orchestrator that turns a sliding-door config
#              Hash into a SketchUp ADR ComponentInstance with two
#              leaves, MOD/ROT/MVE markers, head + base track.
# CREATED    : 17-May-2026
#
# DESCRIPTION:
# - Public surface (mirrors the bifold and Window engines):
#     * na_build_sliding_door(config, door_id, insertion_origin_in)  -> Instance
#     * na_update_sliding_door(instance, config)                     -> Boolean
# - Build pipeline:
#     1. Validate config.
#     2. Allocate a globally-unique ADR id (or reuse the supplied one).
#     3. Create ComponentDefinition "<ADR>__SlidingDoor__".
#     4. Compose the ADR (head + base track + per-leaf MOD/ROT/MVE)
#        via `Na__AssemblyComposer.na_compose_adr`.
#     5. Add a single ComponentInstance at insertion_origin_in (or
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
# - Phase-3b implementation: full create / update / dispatch surface.
#
# 17-May-2026 - Version 0.1.0
# - Phase-1 scaffold (returned nil).
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__TagManager__'
require_relative 'Na__AssemblyStudio__ExtSlide__GeometryHelpers__'
require_relative 'Na__AssemblyStudio__ExtSlide__AssemblyComposer__'
require_relative 'Na__AssemblyStudio__ExtSlide__DataSerializer__'

module Na__AssemblyStudio
module Na__ExteriorSlidingDoorSystem
module Na__GeometryEngine

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

    DebugTools         = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
    TagManager         = Na__AssemblyStudio::Na__AppUtils::Na__TagManager
    GeometryHelpers    = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::Na__GeometryHelpers
    AssemblyComposer   = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::Na__AssemblyComposer
    DataSerializer     = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::Na__DataSerializer

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

    NA_DEFINITION_SUFFIX = "__SlidingDoor__".freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Create
# -----------------------------------------------------------------------------

    # FUNCTION | Build a New Sliding-Door Component Instance
    # ------------------------------------------------------------
    # @param config_hash         [Hash]            full sliding config
    # @param door_id             [String,nil]      pre-allocated ADR id (optional)
    # @param insertion_origin_in [Geom::Point3d,nil] insertion point (inches)
    # @return [Sketchup::ComponentInstance, nil]
    def self.na_build_sliding_door(config_hash, door_id = nil, insertion_origin_in = nil)
        DebugTools.na_debug_method("ExtSlide::GeometryEngine.na_build_sliding_door")

        return nil unless config_hash.is_a?(Hash)
        model = Sketchup.active_model
        return nil unless model

        opening_w_mm = config_hash["sliding_door_opening_width_mm"].to_f
        opening_h_mm = config_hash["sliding_door_opening_height_mm"].to_f
        if opening_w_mm <= 0.0 || opening_h_mm <= 0.0
            DebugTools.na_debug_warn("ExtSlide: invalid opening dimensions #{opening_w_mm}x#{opening_h_mm} - aborting build")
            return nil
        end

        door_id        ||= AssemblyComposer.na_allocate_adr_id(model)
        definition_name  = "#{door_id}#{NA_DEFINITION_SUFFIX}"

        begin
            door_def         = model.definitions.add(definition_name)
            AssemblyComposer.na_compose_adr(config_hash, door_def.entities)

            instance_xform   = na_resolve_insertion_transform(insertion_origin_in)
            instance         = model.active_entities.add_instance(door_def, instance_xform)

            DataSerializer.na_set_door_id_on_instance(instance, door_id)               # <-- Pointer dict + canonical naming

            tag_proposed     = TagManager.na_get_or_create_tag(:proposed_doors)
            instance.layer   = tag_proposed if tag_proposed

            DebugTools.na_debug_geometry("ExtSlide: built sliding door #{definition_name}")
            instance
        rescue StandardError => e
            DebugTools.na_debug_error("Error building sliding door #{definition_name}", e)
            nil
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Update
# -----------------------------------------------------------------------------

    # FUNCTION | Rebuild an Existing Sliding-Door Definition in Place
    # ------------------------------------------------------------
    # @param instance [Sketchup::ComponentInstance]
    # @param config_hash [Hash]
    # @return [Boolean]
    def self.na_update_sliding_door(instance, config_hash)
        DebugTools.na_debug_method("ExtSlide::GeometryEngine.na_update_sliding_door")

        return false unless instance && instance.valid?
        return false unless config_hash.is_a?(Hash)

        definition = instance.definition
        return false unless definition

        begin
            definition.entities.clear!
            AssemblyComposer.na_compose_adr(config_hash, definition.entities)

            DebugTools.na_debug_geometry("ExtSlide: updated sliding door #{definition.name}")
            true
        rescue StandardError => e
            DebugTools.na_debug_error("Error updating sliding door #{definition.name}", e)
            false
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Resolve the Insertion Transform for the New Instance
    # ------------------------------------------------------------
    def self.na_resolve_insertion_transform(insertion_origin_in)
        return IDENTITY unless insertion_origin_in.is_a?(Geom::Point3d)
        Geom::Transformation.new(insertion_origin_in)
    end
    private_class_method :na_resolve_insertion_transform
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__GeometryEngine
end # module Na__ExteriorSlidingDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
