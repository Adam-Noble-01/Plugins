# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - SLIDING DOOR ASSEMBLY COMPOSER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtSlide__AssemblyComposer__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem
# MODULE     : Na__AssemblyComposer
# AUTHOR     : Noble Architecture
# PURPOSE    : Orchestrates the per-leaf composition of a sliding door
#              ADR. Receives a sliding-door config Hash from the
#              GeometryEngine and emits flat-sibling MOD/ROT/MVE groups
#              under the ADR ComponentDefinition entities.
# CREATED    : 17-May-2026
#
# DESCRIPTION:
# - Outer ADR is the door's ComponentDefinition itself
#   (e.g. ADR023__SlidingDoor__) - we do NOT wrap an inner ADR group.
#   The MOD/ROT/MVE markers sit as direct siblings inside the
#   definition entities so the GLB exporter preserves the names that
#   TrueVision3D's animation scanner relies on.
# - Two leaves are composed per ADR:
#     * Front leaf  - MOD001 - moves along X by +/- travel
#     * Rear leaf   - MOD002 - rear setback Y, fixed (zero MVE distance)
#   The fixed leaf still gets a zero-distance MVE name so downstream
#   tools can treat all leaves uniformly when scanning the scene graph.
# - Static head and base track geometry spans the full opening width and
#   wraps both panel tracks. The track lives at the ADR definition
#   root with no MOD wrapper because it never animates.
# - One placeholder ROT001 marker is emitted at the ADR origin to
#   satisfy the TrueVision animation contract that every animatable
#   ADR exposes at least one ROT marker. Sliding doors do not pivot;
#   the placeholder carries no rotation data.
# - ADR id allocator scans BOTH the sliding dictionary
#   (`Na__SlidingDoorConfiguratorInfo`) and the legacy interior-door
#   dictionary (`Na__DoorConfiguratorInfo`) so IDs are globally unique
#   across door systems in the model. Phase 4 unifies this with the
#   bifold scanner under a shared ID generator.
#
# COORDINATE SYSTEM (ADR-local):
# - Origin       = bottom-front-left corner of the structural opening.
# - X+           = along the wall (left -> right across opening).
# - Y+           = through the wall depth (front face at Y=0).
# - Z+           = upwards.
#
# DEVELOPMENT LOG:
# 17-May-2026 - Version 0.2.0
# - Phase-3b implementation: ADR allocation, leaf geometry, ROT/MVE
#   sibling composition.
#
# 17-May-2026 - Version 0.1.0
# - Phase-1 scaffold (returned nil).
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__TagManager__'
require_relative '../04__GeometryHelpers/Na__AssemblyStudio__GeometryHelpers__Box__'
require_relative 'Na__AssemblyStudio__ExtSlide__GeometryHelpers__'
require_relative 'Na__AssemblyStudio__ExtSlide__RotationPivotBuilder__'
require_relative 'Na__AssemblyStudio__ExtSlide__MovementPivotBuilder__'

module Na__AssemblyStudio
module Na__ExteriorSlidingDoorSystem
module Na__AssemblyComposer

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

    DebugTools           = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
    TagManager           = Na__AssemblyStudio::Na__AppUtils::Na__TagManager
    Box                  = Na__AssemblyStudio::Na__GeometryHelpers::Na__Box
    GeometryHelpers      = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::Na__GeometryHelpers
    RotationPivotBuilder = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::Na__RotationPivotBuilder
    MovementPivotBuilder = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::Na__MovementPivotBuilder

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

    NA_TRACK_HEAD_GROUP_NAME         = "Na__SlidingFrame__HeadTrack".freeze
    NA_TRACK_BASE_GROUP_NAME         = "Na__SlidingFrame__BaseTrack".freeze
    NA_RAIL_HEAD_GROUP_NAME          = "Na__SlidingPanel__HeadRail".freeze
    NA_RAIL_BASE_GROUP_NAME          = "Na__SlidingPanel__BaseRail".freeze
    NA_STILE_LEFT_GROUP_NAME         = "Na__SlidingPanel__StileLeft".freeze
    NA_STILE_RIGHT_GROUP_NAME        = "Na__SlidingPanel__StileRight".freeze
    NA_GLAZING_GROUP_NAME            = "Na__SlidingPanel__Glazing".freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - ADR ID Allocation
# -----------------------------------------------------------------------------

    # FUNCTION | Allocate the Next Available ADR Identifier
    # ------------------------------------------------------------
    # Scans every ComponentInstance in the model checking sliding,
    # bifold, and legacy interior-door attribute dictionaries so IDs
    # stay globally unique across door systems.
    #
    # @param model [Sketchup::Model] active model (defaults to active)
    # @return [String] formatted ADR string (e.g. "ADR017")
    def self.na_allocate_adr_id(model = Sketchup.active_model)
        return format_adr(1) unless model

        used_numbers = na_collect_used_adr_numbers(model)
        next_number  = (used_numbers.empty? ? 1 : used_numbers.max + 1)
        format_adr(next_number)
    end
    # ---------------------------------------------------------------

    def self.format_adr(number)
        format(Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::NA_DOOR_ID_FORMAT, number.to_i)
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Compose ADR
# -----------------------------------------------------------------------------

    # FUNCTION | Compose the ADR Component Entities for a Sliding Door
    # ------------------------------------------------------------
    # Builds the head + base track frame, then the front + rear leaves
    # with their MOD wrappers, ROT placeholder, and MVE markers.
    #
    # @param config_hash       [Hash]               full sliding-door config
    # @param parent_entities   [Sketchup::Entities] target entities
    # @return [Hash] { :mod_groups => [...], :rot_groups => [...], :mve_groups => [...] }
    def self.na_compose_adr(config_hash, parent_entities)
        return nil unless parent_entities
        return nil unless config_hash.is_a?(Hash)

        DebugTools.na_debug_method("ExtSlide::AssemblyComposer.na_compose_adr")

        na_build_assembly_frame(config_hash, parent_entities)

        result = { :mod_groups => [], :rot_groups => [], :mve_groups => [] }

        front_descriptor = na_build_front_leaf_descriptor(config_hash)
        rear_descriptor  = na_build_rear_leaf_descriptor(config_hash)

        front_mod = na_build_panel_mod_group(config_hash, front_descriptor, parent_entities)
        result[:mod_groups] << front_mod if front_mod

        rear_mod  = na_build_panel_mod_group(config_hash, rear_descriptor, parent_entities)
        result[:mod_groups] << rear_mod if rear_mod

        rot_group = na_build_placeholder_rot(config_hash, parent_entities)
        result[:rot_groups] << rot_group if rot_group

        front_mve = na_build_panel_mve_marker(config_hash, front_descriptor, parent_entities, 1)
        result[:mve_groups] << front_mve if front_mve

        result
    rescue StandardError => e
        DebugTools.na_debug_error("ExtSlide::AssemblyComposer.na_compose_adr failed", e)
        nil
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Frame (Head + Base Track)
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Build the Static Head + Base Track Geometry
    # ------------------------------------------------------------
    def self.na_build_assembly_frame(config_hash, parent_entities)
        opening_w_mm    = config_hash["sliding_door_opening_width_mm"].to_f
        opening_h_mm    = config_hash["sliding_door_opening_height_mm"].to_f
        floor_clearance = config_hash["sliding_door_floor_clearance_mm"].to_f
        panel_t_mm      = config_hash["sliding_door_panel_thickness_mm"].to_f
        rear_setback_mm = config_hash["sliding_door_rear_setback_mm"].to_f
        head_rail_mm    = config_hash["sliding_door_head_rail_mm"].to_f

        track_y_mm      = GeometryHelpers.na_compute_track_y_origin_mm
        track_d_mm      = GeometryHelpers.na_compute_track_depth_mm(panel_t_mm, rear_setback_mm)

        head_z_mm       = opening_h_mm - head_rail_mm
        na_create_box_mm(parent_entities, NA_TRACK_HEAD_GROUP_NAME,
                         0.0, track_y_mm, head_z_mm,
                         opening_w_mm, track_d_mm, head_rail_mm)

        na_create_box_mm(parent_entities, NA_TRACK_BASE_GROUP_NAME,
                         0.0, track_y_mm, 0.0,
                         opening_w_mm, track_d_mm, floor_clearance)
    end
    private_class_method :na_build_assembly_frame
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Per-Leaf Descriptors
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Build the Descriptor for the Front (Moving) Leaf
    # ------------------------------------------------------------
    def self.na_build_front_leaf_descriptor(config_hash)
        opening_w_mm    = config_hash["sliding_door_opening_width_mm"].to_f
        opening_h_mm    = config_hash["sliding_door_opening_height_mm"].to_f
        floor_clearance = config_hash["sliding_door_floor_clearance_mm"].to_f
        slide_mode      = config_hash["sliding_door_mode"].to_s
        leaf_w_mm       = GeometryHelpers.na_compute_leaf_width_mm(opening_w_mm)
        leaf_h_mm       = GeometryHelpers.na_compute_leaf_height_mm(opening_h_mm, floor_clearance)
        signed_travel   = GeometryHelpers.na_resolve_front_leaf_signed_travel_mm(slide_mode, leaf_w_mm)

        front_origin_x_mm = (slide_mode == "FrontSlidesLeft") ? leaf_w_mm : 0.0

        {
            :index           => 1,
            :role            => :front,
            :width_mm        => leaf_w_mm,
            :height_mm       => leaf_h_mm,
            :origin_x_mm     => front_origin_x_mm,
            :origin_y_mm     => GeometryHelpers.na_compute_front_panel_y_origin_mm,
            :mve_axis        => "X",
            :mve_distance_mm => signed_travel.to_i,
            :hinge_x_mm      => front_origin_x_mm,
            :hinge_y_mm      => GeometryHelpers.na_compute_front_panel_y_origin_mm,
            :has_handle      => true
        }
    end
    private_class_method :na_build_front_leaf_descriptor
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Build the Descriptor for the Rear (Fixed) Leaf
    # ------------------------------------------------------------
    def self.na_build_rear_leaf_descriptor(config_hash)
        opening_w_mm    = config_hash["sliding_door_opening_width_mm"].to_f
        opening_h_mm    = config_hash["sliding_door_opening_height_mm"].to_f
        floor_clearance = config_hash["sliding_door_floor_clearance_mm"].to_f
        rear_setback_mm = config_hash["sliding_door_rear_setback_mm"].to_f
        slide_mode      = config_hash["sliding_door_mode"].to_s
        leaf_w_mm       = GeometryHelpers.na_compute_leaf_width_mm(opening_w_mm)
        leaf_h_mm       = GeometryHelpers.na_compute_leaf_height_mm(opening_h_mm, floor_clearance)

        rear_origin_x_mm = (slide_mode == "FrontSlidesLeft") ? 0.0 : leaf_w_mm

        {
            :index           => 2,
            :role            => :rear_fixed,
            :width_mm        => leaf_w_mm,
            :height_mm       => leaf_h_mm,
            :origin_x_mm     => rear_origin_x_mm,
            :origin_y_mm     => GeometryHelpers.na_compute_rear_panel_y_origin_mm(rear_setback_mm),
            :mve_axis        => "X",
            :mve_distance_mm => 0,                                                 # <-- Rear leaf is fixed in Phase-3b
            :hinge_x_mm      => rear_origin_x_mm,
            :hinge_y_mm      => GeometryHelpers.na_compute_rear_panel_y_origin_mm(rear_setback_mm),
            :has_handle      => false
        }
    end
    private_class_method :na_build_rear_leaf_descriptor
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Per-Leaf MOD Group
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Build the MOD Group for a Single Leaf
    # ------------------------------------------------------------
    # The MOD group is the moving part of the leaf. Its NAME encodes
    # the open-state MVE transformation that TrueVision3D's animation
    # scanner parses at runtime. The geometry inside is the leaf's
    # frame (rails + stiles) plus the glazing pane (when
    # `sliding_door_glazed == true`).
    def self.na_build_panel_mod_group(config_hash, descriptor, parent_entities)
        mod_name        = na_resolve_mod_name(descriptor)
        mod_group       = parent_entities.add_group
        mod_group.name  = mod_name
        mod_entities    = mod_group.entities

        floor_clearance = config_hash["sliding_door_floor_clearance_mm"].to_f
        panel_t_mm      = config_hash["sliding_door_panel_thickness_mm"].to_f
        head_rail_mm    = config_hash["sliding_door_head_rail_mm"].to_f
        base_rail_mm    = config_hash["sliding_door_base_rail_mm"].to_f
        stile_width_mm  = config_hash["sliding_door_stile_width_mm"].to_f
        is_glazed       = config_hash["sliding_door_glazed"] == true

        origin_x_mm     = descriptor[:origin_x_mm].to_f
        origin_y_mm     = descriptor[:origin_y_mm].to_f
        panel_w_mm      = descriptor[:width_mm].to_f
        panel_h_mm      = descriptor[:height_mm].to_f
        panel_z_mm      = floor_clearance

        na_build_panel_rails(mod_entities, origin_x_mm, origin_y_mm, panel_z_mm,
                             panel_w_mm, panel_h_mm, panel_t_mm,
                             head_rail_mm, base_rail_mm)
        na_build_panel_stiles(mod_entities, origin_x_mm, origin_y_mm, panel_z_mm,
                              panel_w_mm, panel_h_mm, panel_t_mm,
                              head_rail_mm, base_rail_mm, stile_width_mm)

        if is_glazed
            na_build_panel_glazing(mod_entities, origin_x_mm, origin_y_mm, panel_z_mm,
                                   panel_w_mm, panel_h_mm, panel_t_mm,
                                   head_rail_mm, base_rail_mm, stile_width_mm)
        end

        DebugTools.na_debug_geometry(
            "ExtSlide MOD: #{mod_name} (leaf #{descriptor[:index]}, role=#{descriptor[:role]})"
        )
        mod_group
    end
    private_class_method :na_build_panel_mod_group
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Resolve the MOD Group Name From a Leaf Descriptor
    # ------------------------------------------------------------
    # Phase-4 contract: fixed leaves get a `MOD###__FIXED__SlidingPanel` name
    # while moving leaves get `MOD###__MVE__<axis><signed>mm__SlidingPanel`.
    # The axis letter is normalised to a single uppercase character (X / Y / Z)
    # because the magnitude carries its own sign via "%+d" inside the format.
    # See `04__GeometryHelpers/Na__AssemblyStudio__DoorNamingContract__.rb`.
    def self.na_resolve_mod_name(descriptor)
        index           = descriptor[:index].to_i
        mve_axis        = descriptor[:mve_axis] || "X"
        mve_distance_mm = descriptor[:mve_distance_mm].to_i

        if mve_distance_mm == 0
            format(
                Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::NA_MOD_NAME_FORMAT_FIXED,
                index
            )
        else
            axis_letter = na_normalise_axis_letter(mve_axis)
            format(
                Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::NA_MOD_NAME_FORMAT,
                index, axis_letter, mve_distance_mm
            )
        end
    end
    private_class_method :na_resolve_mod_name
    # ---------------------------------------------------------------


    # HELPER FUNCTION | Coerce an Axis Hint to a Single Uppercase Letter
    # ------------------------------------------------------------
    def self.na_normalise_axis_letter(axis_hint)
        s = axis_hint.to_s.upcase
        return s[0, 1] if s.length >= 1 && s[0, 1] =~ /[XYZ]/
        "X"
    end
    private_class_method :na_normalise_axis_letter
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Per-Leaf Rails / Stiles / Glazing
# -----------------------------------------------------------------------------

    def self.na_build_panel_rails(entities, origin_x_mm, origin_y_mm, origin_z_mm, panel_w_mm, panel_h_mm, panel_t_mm, head_rail_mm, base_rail_mm)
        head_z_mm = origin_z_mm + (panel_h_mm - head_rail_mm)
        na_create_box_mm(entities, NA_RAIL_HEAD_GROUP_NAME,
                         origin_x_mm, origin_y_mm, head_z_mm,
                         panel_w_mm, panel_t_mm, head_rail_mm)

        na_create_box_mm(entities, NA_RAIL_BASE_GROUP_NAME,
                         origin_x_mm, origin_y_mm, origin_z_mm,
                         panel_w_mm, panel_t_mm, base_rail_mm)
    end
    private_class_method :na_build_panel_rails

    def self.na_build_panel_stiles(entities, origin_x_mm, origin_y_mm, origin_z_mm, panel_w_mm, panel_h_mm, panel_t_mm, head_rail_mm, base_rail_mm, stile_width_mm)
        stile_z_mm     = origin_z_mm + base_rail_mm
        stile_h_mm     = panel_h_mm - head_rail_mm - base_rail_mm
        return if stile_h_mm <= 0.0

        na_create_box_mm(entities, NA_STILE_LEFT_GROUP_NAME,
                         origin_x_mm, origin_y_mm, stile_z_mm,
                         stile_width_mm, panel_t_mm, stile_h_mm)

        right_stile_x  = origin_x_mm + (panel_w_mm - stile_width_mm)
        na_create_box_mm(entities, NA_STILE_RIGHT_GROUP_NAME,
                         right_stile_x, origin_y_mm, stile_z_mm,
                         stile_width_mm, panel_t_mm, stile_h_mm)
    end
    private_class_method :na_build_panel_stiles

    def self.na_build_panel_glazing(entities, origin_x_mm, origin_y_mm, origin_z_mm, panel_w_mm, panel_h_mm, panel_t_mm, head_rail_mm, base_rail_mm, stile_width_mm)
        inner_x_mm  = origin_x_mm + stile_width_mm
        inner_z_mm  = origin_z_mm + base_rail_mm
        inner_w_mm  = panel_w_mm - 2.0 * stile_width_mm
        inner_h_mm  = panel_h_mm - head_rail_mm - base_rail_mm
        return if inner_w_mm <= 0.0 || inner_h_mm <= 0.0

        glaze_d_mm  = GeometryHelpers.na_compute_glazing_depth_mm(panel_t_mm)
        glaze_y_mm  = origin_y_mm + GeometryHelpers.na_compute_glazing_y_origin_mm(panel_t_mm)

        na_create_box_mm(entities, NA_GLAZING_GROUP_NAME,
                         inner_x_mm, glaze_y_mm, inner_z_mm,
                         inner_w_mm, glaze_d_mm, inner_h_mm)
    end
    private_class_method :na_build_panel_glazing

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Markers (ROT + MVE)
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Build the Single Placeholder ROT001 Marker
    # ------------------------------------------------------------
    # Sliding doors do not pivot, but TrueVision's scanner expects a
    # ROT marker per ADR. The marker sits at the front-leaf hinge
    # position at floor level so it is visually associated with the
    # door even though it carries no rotation data.
    def self.na_build_placeholder_rot(config_hash, parent_entities)
        floor_clearance = config_hash["sliding_door_floor_clearance_mm"].to_f
        slide_mode      = config_hash["sliding_door_mode"].to_s
        opening_w_mm    = config_hash["sliding_door_opening_width_mm"].to_f
        leaf_w_mm       = GeometryHelpers.na_compute_leaf_width_mm(opening_w_mm)
        rot_x_mm        = (slide_mode == "FrontSlidesLeft") ? leaf_w_mm : 0.0

        origin_in       = Geom::Point3d.new(
            GeometryHelpers.na_mm_to_inch(rot_x_mm),
            GeometryHelpers.na_mm_to_inch(0.0),
            GeometryHelpers.na_mm_to_inch(floor_clearance)
        )

        RotationPivotBuilder.na_build_rotation_pivot(parent_entities, origin_in)
    end
    private_class_method :na_build_placeholder_rot
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Build an MVE Marker for a Single Translating Leaf
    # ------------------------------------------------------------
    def self.na_build_panel_mve_marker(config_hash, descriptor, parent_entities, mve_index)
        return nil if descriptor[:mve_distance_mm].to_i == 0

        floor_clearance = config_hash["sliding_door_floor_clearance_mm"].to_f
        panel_h_mm      = descriptor[:height_mm].to_f
        marker_z_mm     = floor_clearance + panel_h_mm                           # <-- MVE marker at leaf TOP

        origin_in       = Geom::Point3d.new(
            GeometryHelpers.na_mm_to_inch(descriptor[:hinge_x_mm].to_f),
            GeometryHelpers.na_mm_to_inch(descriptor[:hinge_y_mm].to_f),
            GeometryHelpers.na_mm_to_inch(marker_z_mm)
        )

        MovementPivotBuilder.na_build_movement_pivot(
            parent_entities,
            origin_in,
            mve_index,
            descriptor[:mve_axis],
            descriptor[:mve_distance_mm].to_i
        )
    end
    private_class_method :na_build_panel_mve_marker
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Geometry Primitive Wrappers
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Create a Named Box Group From mm-Local Origin + Size
    # ------------------------------------------------------------
    def self.na_create_box_mm(entities, name, x_mm, y_mm, z_mm, w_mm, d_mm, h_mm)
        return nil if w_mm <= 0.0 || d_mm <= 0.0 || h_mm <= 0.0

        Box.na_create_grouped_box(
            entities,
            name,
            GeometryHelpers.na_mm_to_inch(x_mm),
            GeometryHelpers.na_mm_to_inch(y_mm),
            GeometryHelpers.na_mm_to_inch(z_mm),
            GeometryHelpers.na_mm_to_inch(w_mm),
            GeometryHelpers.na_mm_to_inch(d_mm),
            GeometryHelpers.na_mm_to_inch(h_mm),
            nil
        )
    end
    private_class_method :na_create_box_mm

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - ADR ID Scanning
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Collect All ADR Numbers Already Present in the Model
    # ------------------------------------------------------------
    def self.na_collect_used_adr_numbers(model)
        sliding_dict_key  = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::NA_DOOR_INFO_DICT
        sliding_id_key    = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::NA_KEY_DOOR_ID
        bifold_dict_key   = "Na__BifoldDoorConfiguratorInfo".freeze
        legacy_dict_key   = "Na__DoorConfiguratorInfo".freeze
        legacy_id_key     = "DoorID".freeze

        used = []
        model.definitions.each do |definition|
            definition.instances.each do |instance|
                sliding_id = na_safe_get_attribute(instance, sliding_dict_key, sliding_id_key)
                used << na_extract_adr_number(sliding_id) if sliding_id

                bifold_id = na_safe_get_attribute(instance, bifold_dict_key, sliding_id_key)
                used << na_extract_adr_number(bifold_id) if bifold_id

                legacy_id = na_safe_get_attribute(instance, legacy_dict_key, legacy_id_key)
                used << na_extract_adr_number(legacy_id) if legacy_id
            end
        end
        used.compact
    end
    private_class_method :na_collect_used_adr_numbers
    # ---------------------------------------------------------------

    def self.na_safe_get_attribute(instance, dict_key, attr_key)
        return nil unless instance.respond_to?(:get_attribute)
        instance.get_attribute(dict_key, attr_key)
    rescue StandardError
        nil
    end
    private_class_method :na_safe_get_attribute

    def self.na_extract_adr_number(adr_string)
        return nil unless adr_string.is_a?(String)
        match = adr_string.match(/^ADR(\d{3})$/)
        match ? match[1].to_i : nil
    end
    private_class_method :na_extract_adr_number

# endregion -------------------------------------------------------------------

end # module Na__AssemblyComposer
end # module Na__ExteriorSlidingDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
