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
#     * na_build_sliding_door(config, door_id, insertion_frame)      -> Instance
#     * na_update_sliding_door(instance, config)                     -> Boolean
# - Build pipeline:
#     1. Validate config.
#     2. Allocate a globally-unique ADR id (or reuse the supplied one).
#     3. Create ComponentDefinition "<ADR>__SlidingDoor__".
#     4. Compose the ADR (head + base track + per-leaf MOD/ROT/MVE)
#        via `Na__AssemblyComposer.na_compose_adr`.
#     5. Add a single ComponentInstance via Na__InsertionFrame which
#        honours measurement frame > origin + model.axes > active axes.
#        Tag :proposed_doors when available.
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
    InsertionFrame     = Na__AssemblyStudio::Na__GeometryHelpers::Na__InsertionFrame                    # <-- Wall-aware insertion transform helper

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
    # @param config_hash     [Hash]                   full sliding config
    # @param door_id         [String,nil]             pre-allocated ADR id (optional)
    # @param insertion_frame [Hash,Geom::Point3d,nil] measurement frame
    #     (origin + xaxis/yaxis/zaxis), bare origin Point3d, or nil.
    # @return [Sketchup::ComponentInstance, nil]
    def self.na_build_sliding_door(config_hash, door_id = nil, insertion_frame = nil)
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
            AssemblyComposer.na_compose_adr(config_hash, door_def.entities, door_id)

            instance_xform   = na_resolve_insertion_transform(insertion_frame)
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
            existing_door_id = na_resolve_existing_door_id(instance, definition)
            definition.entities.clear!
            AssemblyComposer.na_compose_adr(config_hash, definition.entities, existing_door_id)

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
    # Delegates to the shared InsertionFrame helper so the sliding
    # path honours the same priority as Window / Bifold / Interior
    # Door (measurement frame > origin + active axes > active axes).
    #
    # @param insertion_frame [Hash, Geom::Point3d, nil]
    # @return [Geom::Transformation]
    def self.na_resolve_insertion_transform(insertion_frame)
        InsertionFrame.na_resolve_insertion_transform(insertion_frame)
    end
    private_class_method :na_resolve_insertion_transform
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Resolve the Existing Door ID for an Update Pass (Phase-9)
    # ------------------------------------------------------------
    # Looks up the persisted DoorID on the instance / definition first
    # (so the existing FuseParts naming stays stable across updates) and
    # falls back to extracting the leading "ADR###" token from the
    # definition name when no attribute is present.
    def self.na_resolve_existing_door_id(instance, definition)
        return nil unless instance && definition

        dict_key = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::NA_DOOR_INFO_DICT
        id_key   = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::NA_KEY_DOOR_ID

        attr_id = nil
        attr_id = instance.get_attribute(dict_key, id_key) if instance.respond_to?(:get_attribute)
        return attr_id if attr_id.is_a?(String) && !attr_id.empty?

        match = definition.name.to_s.match(/^(ADR\d{3})/)
        match ? match[1] : nil
    rescue StandardError
        nil
    end
    private_class_method :na_resolve_existing_door_id
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__GeometryEngine
end # module Na__ExteriorSlidingDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
