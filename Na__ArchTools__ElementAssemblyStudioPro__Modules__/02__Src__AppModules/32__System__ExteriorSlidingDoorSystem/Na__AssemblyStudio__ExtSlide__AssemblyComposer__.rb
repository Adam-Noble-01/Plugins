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
# - Phase-9 replaced the bulky head/base "track" boxes with a
#   window-style opening frame (per-edge jambs + head + bottom rail)
#   and an optional cill, both delegated to the WindowSystem
#   GeometryBuilders so sliding doors share the windows' Dimensions /
#   Cill & Frame controls.
# - One placeholder ROT001 marker is emitted at the ADR origin to
#   satisfy the TrueVision animation contract that every animatable
#   ADR exposes at least one ROT marker. Sliding doors do not pivot;
#   the placeholder carries no rotation data.
# - ADR id allocator scans BOTH the sliding dictionary
#   (`Na__SlidingDoorConfiguratorInfo`) and the legacy interior-door
#   dictionary (`Na__DoorConfiguratorInfo`) so IDs are globally unique
#   across door systems in the model.
#
# COORDINATE SYSTEM (ADR-local):
# - Origin       = bottom-front-left corner of the structural opening.
# - X+           = along the wall (left -> right across opening).
# - Y+           = through the wall depth (front face at Y=0).
# - Z+           = upwards.
#
# DEVELOPMENT LOG:
# 17-May-2026 - Version 0.3.0
# - Phase-9: replaced track casings with delegated WindowSystem frame
#   + optional cill, fixed panel joinery (stiles full-height, rails
#   between), renamed inner parts to FuseParts-compatible
#   `Na_DoorPanel_{panel_id}_*` / `Na_Glass_{panel_id}` schema, and
#   wired up the panel grille via na_create_glazebar_geometry.
#
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
require_relative '../02__AppData/Na__AssemblyStudio__AppData__MaterialManager__'
require_relative '../04__GeometryHelpers/Na__AssemblyStudio__GeometryHelpers__Box__'
require_relative '../20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__Defaults__'
require_relative '../20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__GeometryBuilders__'
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
# REGION | Module Constants - Per-Panel Group Naming (Phase-9 FuseParts compatible)
# -----------------------------------------------------------------------------
#
# Phase-9 renamed the inner panel parts to the FuseParts-compatible
# `Na_DoorPanel_{panel_id}_*` / `Na_Glass_{panel_id}` scheme so the
# sliding panel fuser can discover and merge them via the same regex
# the exterior single-door fuser uses. `panel_id` for a sliding leaf
# is `Sliding_{ADR_id}_P{NN}` (NN = zero-padded panel index, 1-based).
#
    NA_PANEL_ID_FORMAT_SLIDING        = "Sliding_%s_P%02d".freeze
    NA_PANEL_ID_FORMAT_SLIDING_NOADR  = "Sliding_NoADR_P%02d".freeze
    NA_PART_NAME_RAIL_TOP             = "Na_DoorPanel_%s_Rail_Top".freeze
    NA_PART_NAME_RAIL_BOTTOM          = "Na_DoorPanel_%s_Rail_Bottom".freeze
    NA_PART_NAME_STILE_LEFT           = "Na_DoorPanel_%s_Stile_Left".freeze
    NA_PART_NAME_STILE_RIGHT          = "Na_DoorPanel_%s_Stile_Right".freeze
    NA_PART_NAME_GLAZING              = "Na_Glass_%s".freeze

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
    # Builds the static opening frame + optional cill, then the front
    # + rear leaves with their MOD wrappers, ROT placeholder, and MVE
    # markers.
    #
    # @param config_hash       [Hash]               full sliding-door config
    # @param parent_entities   [Sketchup::Entities] target entities
    # @param door_id           [String,nil]         ADR id (e.g. "ADR023") for FuseParts naming
    # @return [Hash] { :mod_groups => [...], :rot_groups => [...], :mve_groups => [...] }
    def self.na_compose_adr(config_hash, parent_entities, door_id = nil)
        return nil unless parent_entities
        return nil unless config_hash.is_a?(Hash)

        DebugTools.na_debug_method("ExtSlide::AssemblyComposer.na_compose_adr")

        dims      = GeometryHelpers.na_resolve_door_opening_dimensions(config_hash)
        materials = na_resolve_materials(config_hash)                          # <-- V1.7.1: shared frame + glass materials for the whole ADR

        na_build_opening_frame(config_hash, dims, parent_entities, materials)
        na_build_opening_cill(config_hash,  dims, parent_entities)

        result = { :mod_groups => [], :rot_groups => [], :mve_groups => [] }

        front_descriptor = na_build_front_leaf_descriptor(config_hash, dims)
        rear_descriptor  = na_build_rear_leaf_descriptor(config_hash, dims)

        front_mod = na_build_panel_mod_group(config_hash, dims, front_descriptor, parent_entities, door_id, materials)
        result[:mod_groups] << front_mod if front_mod

        rear_mod  = na_build_panel_mod_group(config_hash, dims, rear_descriptor, parent_entities, door_id, materials)
        result[:mod_groups] << rear_mod if rear_mod

        rot_group = na_build_placeholder_rot(config_hash, dims, parent_entities)
        result[:rot_groups] << rot_group if rot_group

        front_mve = na_build_panel_mve_marker(config_hash, dims, front_descriptor, parent_entities, 1)
        result[:mve_groups] << front_mve if front_mve

        na_apply_cill_lift(config_hash, dims, parent_entities)                 # <-- V1.7.1: shift everything up so the cill sits ON the floor

        result
    rescue StandardError => e
        DebugTools.na_debug_error("ExtSlide::AssemblyComposer.na_compose_adr failed", e)
        nil
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Opening Frame + Cill (delegated to WindowSystem)
# -----------------------------------------------------------------------------
#
# Phase-9 replaced the bulky head/base track casings with a window-style
# opening frame (per-edge jambs + head rail + bottom rail) and an
# optional cill, both supplied by the WindowSystem GeometryBuilders so
# bifold + sliding doors look exactly like the rest of the openings.

    # HELPER FUNCTION | Resolve the Frame + Glass Materials for the ADR (V1.7.1)
    # ------------------------------------------------------------
    # Centralises the material lookup so the frame, cill, panel timber,
    # glazing pane and glaze bars all share a single resolved hash.
    # Mirrors the WindowSystem GeometryEngine flow: frame material from
    # `frame_material_id`, glass material from the WindowSystem default,
    # both fetched via the shared MaterialManager.
    def self.na_resolve_materials(config_hash)
        material_mgr     = Na__AssemblyStudio::Na__AppData::Na__MaterialManager
        default_frame_id = Na__AssemblyStudio::Na__WindowSystem::NA_DEFAULT_FRAME_MATERIAL_ID
        default_glass_id = Na__AssemblyStudio::Na__WindowSystem::NA_DEFAULT_GLASS_MATERIAL_ID
        frame_mat_id     = config_hash["frame_material_id"] || default_frame_id
        glass_mat_id     = config_hash["glass_material_id"] || default_glass_id

        {
            :frame => material_mgr.na_get_material_by_id(frame_mat_id),
            :glass => material_mgr.na_get_material_by_id(glass_mat_id)
        }
    rescue StandardError => e
        DebugTools.na_debug_error("ExtSlide::AssemblyComposer.na_resolve_materials failed", e)
        { :frame => nil, :glass => nil }
    end
    private_class_method :na_resolve_materials
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Build the Static Per-Edge Opening Frame
    # ------------------------------------------------------------
    # Delegates to `Na__WindowSystem::Na__GeometryBuilders.na_create_frame_geometry`
    # so the same per-edge thickness, depth, wall_inset and frame
    # material logic drives every opening type.
    def self.na_build_opening_frame(config_hash, dims, parent_entities, materials = nil)
        return if dims[:width_mm]  <= 0.0
        return if dims[:height_mm] <= 0.0
        return if dims[:frame_top_mm]    == 0.0 &&
                  dims[:frame_bottom_mm] == 0.0 &&
                  dims[:frame_left_mm]   == 0.0 &&
                  dims[:frame_right_mm]  == 0.0

        return unless defined?(Na__AssemblyStudio::Na__WindowSystem::Na__GeometryBuilders)

        builders        = Na__AssemblyStudio::Na__WindowSystem::Na__GeometryBuilders
        materials       = na_resolve_materials(config_hash) if materials.nil?
        frame_material  = materials[:frame]

        edges_in = {
            top:    GeometryHelpers.na_mm_to_inch(dims[:frame_top_mm]),
            bottom: GeometryHelpers.na_mm_to_inch(dims[:frame_bottom_mm]),
            left:   GeometryHelpers.na_mm_to_inch(dims[:frame_left_mm]),
            right:  GeometryHelpers.na_mm_to_inch(dims[:frame_right_mm])
        }

        builders.na_create_frame_geometry(
            parent_entities,
            GeometryHelpers.na_mm_to_inch(dims[:width_mm]),
            GeometryHelpers.na_mm_to_inch(dims[:height_mm]),
            edges_in,
            GeometryHelpers.na_mm_to_inch(dims[:frame_depth_mm]),
            frame_material,
            GeometryHelpers.na_mm_to_inch(dims[:frame_wall_inset_mm])
        )
    rescue StandardError => e
        DebugTools.na_debug_error("ExtSlide::AssemblyComposer.na_build_opening_frame failed", e)
    end
    private_class_method :na_build_opening_frame
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Lift the ADR So the Cill Sits ON Top of the Floor (V1.7.1)
    # ------------------------------------------------------------
    # Pre-V1.7.1 the cill geometry occupied the negative-Z slab below
    # the frame (z = -cill_height to 0). When the user dropped the
    # component at floor level the cill ended up below the floor and
    # the entire door was effectively cill_height too low - they had
    # to manually nudge it up to close the gap at the head.
    #
    # V1.7.1: We post-process the ADR by translating every entity up by
    # cill_height when the cill is enabled. The cill ends up at z = 0..H
    # (sitting on the floor), the frame moves up to z = H..H+frame_h
    # (sitting on the cill), and every ROT/MVE marker rises with its
    # leaf so the TrueVision animation pipeline stays consistent.
    def self.na_apply_cill_lift(config_hash, dims, parent_entities)
        return unless config_hash["has_cill"] == true
        return unless dims[:frame_bottom_mm] > 0.0

        cill_height_mm = (config_hash["cill_height_mm"] || 0).to_f
        return if cill_height_mm <= 0.0

        cill_height_in = GeometryHelpers.na_mm_to_inch(cill_height_mm)
        translation    = Geom::Transformation.translation(Geom::Vector3d.new(0.0, 0.0, cill_height_in))
        targets        = parent_entities.to_a
        return if targets.empty?

        parent_entities.transform_entities(translation, targets)
    rescue StandardError => e
        DebugTools.na_debug_error("ExtSlide::AssemblyComposer.na_apply_cill_lift failed", e)
    end
    private_class_method :na_apply_cill_lift
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Build the Optional Cill Below the Opening
    # ------------------------------------------------------------
    # Gated on `has_cill == true && frame_bottom_mm > 0` so a frameless
    # opening cannot accidentally float a cill in mid-air. Cill material
    # honours the `paint_cill` toggle (frame finish if true, default
    # Sapele timber otherwise).
    def self.na_build_opening_cill(config_hash, dims, parent_entities)
        return unless config_hash["has_cill"] == true
        return unless dims[:frame_bottom_mm] > 0.0
        return if dims[:width_mm] <= 0.0

        cill_height_mm = (config_hash["cill_height_mm"] || 50).to_f
        cill_depth_mm  = (config_hash["cill_depth_mm"]  || 50).to_f
        return if cill_height_mm <= 0.0 || cill_depth_mm <= 0.0

        return unless defined?(Na__AssemblyStudio::Na__WindowSystem::Na__GeometryBuilders)

        builders         = Na__AssemblyStudio::Na__WindowSystem::Na__GeometryBuilders
        material_mgr     = Na__AssemblyStudio::Na__AppData::Na__MaterialManager
        paint_cill       = (config_hash["paint_cill"] == true)
        default_frame_id = Na__AssemblyStudio::Na__WindowSystem::NA_DEFAULT_FRAME_MATERIAL_ID
        default_cill_id  = Na__AssemblyStudio::Na__WindowSystem::NA_DEFAULT_CILL_MATERIAL_ID
        cill_mat_id      = paint_cill ? (config_hash["frame_material_id"] || default_frame_id) : default_cill_id
        cill_material    = material_mgr.na_get_material_by_id(cill_mat_id)

        builders.na_create_cill_geometry(
            parent_entities,
            GeometryHelpers.na_mm_to_inch(dims[:width_mm]),
            GeometryHelpers.na_mm_to_inch(cill_depth_mm),
            GeometryHelpers.na_mm_to_inch(cill_height_mm),
            GeometryHelpers.na_mm_to_inch(dims[:frame_depth_mm]),
            cill_material,
            GeometryHelpers.na_mm_to_inch(dims[:frame_wall_inset_mm])
        )
    rescue StandardError => e
        DebugTools.na_debug_error("ExtSlide::AssemblyComposer.na_build_opening_cill failed", e)
    end
    private_class_method :na_build_opening_cill
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Per-Leaf Descriptors
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Build the Descriptor for the Front (Moving) Leaf
    # ------------------------------------------------------------
    # Phase-9: leaf width = inner_w / 2 (frame-aware) and Y origin uses
    # the new frame-relative panel layout helper.
    def self.na_build_front_leaf_descriptor(config_hash, dims)
        slide_mode      = config_hash["sliding_door_mode"].to_s
        panel_t_mm      = config_hash["sliding_door_panel_thickness_mm"].to_f
        rear_setback_mm = config_hash["sliding_door_rear_setback_mm"].to_f
        leaf_w_mm       = GeometryHelpers.na_compute_leaf_width_mm(dims[:inner_w_mm])
        leaf_h_mm       = dims[:inner_h_mm]
        signed_travel   = GeometryHelpers.na_resolve_front_leaf_signed_travel_mm(slide_mode, leaf_w_mm)

        # Origin X relative to inner clear left edge.
        front_origin_x_mm = (slide_mode == "FrontSlidesLeft") ? leaf_w_mm : 0.0
        front_y_mm        = GeometryHelpers.na_compute_front_panel_y_origin_in_frame_mm(
                                panel_t_mm, dims[:frame_depth_mm], dims[:frame_wall_inset_mm]
                            )

        {
            :index           => 1,
            :role            => :front,
            :width_mm        => leaf_w_mm,
            :height_mm       => leaf_h_mm,
            :origin_x_mm     => front_origin_x_mm,
            :origin_y_mm     => front_y_mm,
            :mve_axis        => "X",
            :mve_distance_mm => signed_travel.to_i,
            :hinge_x_mm      => front_origin_x_mm,
            :hinge_y_mm      => front_y_mm,
            :has_handle      => true
        }
    end
    private_class_method :na_build_front_leaf_descriptor
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Build the Descriptor for the Rear (Fixed) Leaf
    # ------------------------------------------------------------
    def self.na_build_rear_leaf_descriptor(config_hash, dims)
        slide_mode      = config_hash["sliding_door_mode"].to_s
        panel_t_mm      = config_hash["sliding_door_panel_thickness_mm"].to_f
        rear_setback_mm = config_hash["sliding_door_rear_setback_mm"].to_f
        leaf_w_mm       = GeometryHelpers.na_compute_leaf_width_mm(dims[:inner_w_mm])
        leaf_h_mm       = dims[:inner_h_mm]

        rear_origin_x_mm = (slide_mode == "FrontSlidesLeft") ? 0.0 : leaf_w_mm
        rear_y_mm        = GeometryHelpers.na_compute_rear_panel_y_origin_in_frame_mm(
                                panel_t_mm, dims[:frame_depth_mm], dims[:frame_wall_inset_mm], rear_setback_mm
                           )

        {
            :index           => 2,
            :role            => :rear_fixed,
            :width_mm        => leaf_w_mm,
            :height_mm       => leaf_h_mm,
            :origin_x_mm     => rear_origin_x_mm,
            :origin_y_mm     => rear_y_mm,
            :mve_axis        => "X",
            :mve_distance_mm => 0,                                                 # <-- Rear leaf is fixed
            :hinge_x_mm      => rear_origin_x_mm,
            :hinge_y_mm      => rear_y_mm,
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
    # Phase-9: leaf sits inside the inner clear opening (offset by
    # frame_left/bottom), uses window-style joinery (stiles full-height,
    # rails between), and inner parts are renamed to FuseParts-compatible
    # `Na_DoorPanel_{panel_id}_*` schema.
    def self.na_build_panel_mod_group(config_hash, dims, descriptor, parent_entities, door_id, materials = nil)
        mod_name        = na_resolve_mod_name(descriptor)
        mod_group       = parent_entities.add_group
        mod_group.name  = mod_name
        mod_entities    = mod_group.entities

        materials       = na_resolve_materials(config_hash) if materials.nil?
        frame_material  = materials[:frame]
        glass_material  = materials[:glass]

        panel_t_mm      = config_hash["sliding_door_panel_thickness_mm"].to_f
        head_rail_mm    = config_hash["sliding_door_head_rail_mm"].to_f
        base_rail_mm    = config_hash["sliding_door_base_rail_mm"].to_f
        stile_width_mm  = config_hash["sliding_door_stile_width_mm"].to_f
        is_glazed       = config_hash["sliding_door_glazed"] == true

        origin_x_mm     = dims[:frame_left_mm]   + descriptor[:origin_x_mm].to_f
        origin_y_mm     = descriptor[:origin_y_mm].to_f
        origin_z_mm     = dims[:frame_bottom_mm]
        panel_w_mm      = descriptor[:width_mm].to_f
        panel_h_mm      = descriptor[:height_mm].to_f

        panel_id        = na_resolve_panel_id(descriptor, door_id)
        part_names      = na_resolve_panel_part_names(panel_id)

        na_build_panel_stiles(mod_entities, origin_x_mm, origin_y_mm, origin_z_mm,
                              panel_w_mm, panel_h_mm, panel_t_mm,
                              stile_width_mm, part_names, frame_material)
        na_build_panel_rails(mod_entities, origin_x_mm, origin_y_mm, origin_z_mm,
                             panel_w_mm, panel_h_mm, panel_t_mm,
                             head_rail_mm, base_rail_mm, stile_width_mm, part_names, frame_material)

        if is_glazed
            na_build_panel_glazing(mod_entities, origin_x_mm, origin_y_mm, origin_z_mm,
                                   panel_w_mm, panel_h_mm, panel_t_mm,
                                   head_rail_mm, base_rail_mm, stile_width_mm, part_names, glass_material)
            na_build_panel_glaze_bars(mod_entities, config_hash, dims,
                                      origin_x_mm, origin_y_mm, origin_z_mm,
                                      panel_w_mm, panel_h_mm, panel_t_mm,
                                      head_rail_mm, base_rail_mm, stile_width_mm,
                                      panel_id, descriptor[:index].to_i,
                                      frame_material)
        end

        DebugTools.na_debug_geometry(
            "ExtSlide MOD: #{mod_name} (leaf #{descriptor[:index]}, role=#{descriptor[:role]})"
        )
        mod_group
    end
    private_class_method :na_build_panel_mod_group
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Resolve the FuseParts-Compatible Panel Identifier
    # ------------------------------------------------------------
    def self.na_resolve_panel_id(descriptor, door_id)
        idx = descriptor[:index].to_i
        if door_id.is_a?(String) && !door_id.empty?
            format(NA_PANEL_ID_FORMAT_SLIDING, door_id, idx)
        else
            format(NA_PANEL_ID_FORMAT_SLIDING_NOADR, idx)
        end
    end
    private_class_method :na_resolve_panel_id
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Resolve Per-Panel Part Names (Phase-9 FuseParts schema)
    # ------------------------------------------------------------
    def self.na_resolve_panel_part_names(panel_id)
        {
            :rail_top    => format(NA_PART_NAME_RAIL_TOP,    panel_id),
            :rail_bottom => format(NA_PART_NAME_RAIL_BOTTOM, panel_id),
            :stile_left  => format(NA_PART_NAME_STILE_LEFT,  panel_id),
            :stile_right => format(NA_PART_NAME_STILE_RIGHT, panel_id),
            :glazing     => format(NA_PART_NAME_GLAZING,     panel_id)
        }
    end
    private_class_method :na_resolve_panel_part_names
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Resolve the MOD Group Name From a Leaf Descriptor
    # ------------------------------------------------------------
    # Phase-4 contract: fixed leaves get a `MOD###__FIXED__SlidingPanel` name
    # while moving leaves get `MOD###__MVE__<axis><signed>mm__SlidingPanel`.
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

    # HELPER FUNCTION | Build the Top + Base Rails of a Sliding Leaf (Phase-9 joinery)
    # ------------------------------------------------------------
    # Window-style joinery: rails sit BETWEEN the two stiles. Their X
    # extent is `panel_w - 2*stile_width` and they slot in from
    # x = origin + stile_width.
    def self.na_build_panel_rails(entities, origin_x_mm, origin_y_mm, origin_z_mm,
                                  panel_w_mm, panel_h_mm, panel_t_mm,
                                  head_rail_mm, base_rail_mm, stile_width_mm,
                                  part_names, material = nil)
        rail_x_mm = origin_x_mm + stile_width_mm
        rail_w_mm = panel_w_mm  - 2.0 * stile_width_mm
        return if rail_w_mm <= 0.0

        head_z_mm = origin_z_mm + (panel_h_mm - head_rail_mm)
        na_create_box_mm(entities, part_names[:rail_top],
                         rail_x_mm, origin_y_mm, head_z_mm,
                         rail_w_mm, panel_t_mm, head_rail_mm, material)

        na_create_box_mm(entities, part_names[:rail_bottom],
                         rail_x_mm, origin_y_mm, origin_z_mm,
                         rail_w_mm, panel_t_mm, base_rail_mm, material)
    end
    private_class_method :na_build_panel_rails
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Build the Left + Right Stiles of a Sliding Leaf (Phase-9 joinery)
    # ------------------------------------------------------------
    # Window-style joinery: stiles span the FULL panel height, with
    # rails terminating between them.
    def self.na_build_panel_stiles(entities, origin_x_mm, origin_y_mm, origin_z_mm,
                                   panel_w_mm, panel_h_mm, panel_t_mm,
                                   stile_width_mm, part_names, material = nil)
        return if panel_h_mm <= 0.0
        return if stile_width_mm <= 0.0
        return if panel_w_mm <= 2.0 * stile_width_mm

        na_create_box_mm(entities, part_names[:stile_left],
                         origin_x_mm, origin_y_mm, origin_z_mm,
                         stile_width_mm, panel_t_mm, panel_h_mm, material)

        right_stile_x = origin_x_mm + (panel_w_mm - stile_width_mm)
        na_create_box_mm(entities, part_names[:stile_right],
                         right_stile_x, origin_y_mm, origin_z_mm,
                         stile_width_mm, panel_t_mm, panel_h_mm, material)
    end
    private_class_method :na_build_panel_stiles
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Build the Centred Glazing Pane Inside the Frame
    # ------------------------------------------------------------
    def self.na_build_panel_glazing(entities, origin_x_mm, origin_y_mm, origin_z_mm,
                                    panel_w_mm, panel_h_mm, panel_t_mm,
                                    head_rail_mm, base_rail_mm, stile_width_mm,
                                    part_names, material = nil)
        clear_box = na_compute_clear_glazing_box(origin_x_mm, origin_z_mm,
                                                 panel_w_mm, panel_h_mm,
                                                 head_rail_mm, base_rail_mm,
                                                 stile_width_mm)
        return unless clear_box

        glaze_d_mm  = GeometryHelpers.na_compute_glazing_depth_mm(panel_t_mm)
        glaze_y_mm  = origin_y_mm + GeometryHelpers.na_compute_glazing_y_origin_mm(panel_t_mm)

        na_create_box_mm(entities, part_names[:glazing],
                         clear_box[:x], glaze_y_mm, clear_box[:z],
                         clear_box[:width], glaze_d_mm, clear_box[:height], material)
    end
    private_class_method :na_build_panel_glazing
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Compute the Clear Inner Glazing Rectangle (mm)
    # ------------------------------------------------------------
    # Returns the bounding rectangle inside the stiles + rails. Used by
    # both the glazing pane builder and the glaze-bar grille builder.
    def self.na_compute_clear_glazing_box(origin_x_mm, origin_z_mm,
                                          panel_w_mm, panel_h_mm,
                                          head_rail_mm, base_rail_mm,
                                          stile_width_mm)
        inner_x = origin_x_mm + stile_width_mm
        inner_z = origin_z_mm + base_rail_mm
        inner_w = panel_w_mm - 2.0 * stile_width_mm
        inner_h = panel_h_mm - head_rail_mm - base_rail_mm
        return nil if inner_w <= 0.0 || inner_h <= 0.0
        { :x => inner_x, :z => inner_z, :width => inner_w, :height => inner_h }
    end
    private_class_method :na_compute_clear_glazing_box
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Build the Glaze-Bar Grille for a Single Leaf (Phase-9)
    # ------------------------------------------------------------
    # Mirrors the window casement grille: horizontal + vertical bars
    # fill the clear inner rectangle, sized via shared
    # `horizontal_glaze_bars`, `vertical_glaze_bars`, `glaze_bar_width_mm`,
    # `glazebar_inset_mm` keys. Delegates to the WindowSystem builder.
    def self.na_build_panel_glaze_bars(entities, config_hash, dims,
                                       origin_x_mm, origin_y_mm, origin_z_mm,
                                       panel_w_mm, panel_h_mm, panel_t_mm,
                                       head_rail_mm, base_rail_mm, stile_width_mm,
                                       panel_id, panel_index, frame_material = nil)
        h_bars = (config_hash["horizontal_glaze_bars"] || 0).to_i
        v_bars = (config_hash["vertical_glaze_bars"]   || 0).to_i
        gothic_arch_enabled = config_hash["glazebar_gothic_arch_enabled"] == true
        return if h_bars <= 0 && v_bars <= 0 && !gothic_arch_enabled

        bar_width_mm    = (config_hash["glaze_bar_width_mm"] || 25).to_f
        bar_inset_mm    = (config_hash["glazebar_inset_mm"]  || 10).to_f
        glass_thick_mm  = (config_hash["glass_thickness_mm"] || 20).to_f

        # Advanced glazebar (Margin + Gothic) — converted to inches inline
        # so the WindowSystem builder receives the same units it gets from
        # the regular window code path.
        mm_to_inch = 1.0 / 25.4
        advanced_glazebar = {
            margin_enabled:  config_hash["glazebar_margin_enabled"] == true,
            margin_offset:   (config_hash["glazebar_margin_offset_mm"] || 0).to_f * mm_to_inch,
            arch_enabled:    gothic_arch_enabled,
            arch_amount:     [[(config_hash["glazebar_gothic_arch_amount"] || 2).to_i, 1].max, 8].min,           # <-- V1.9.4 Allow single lancet arch
            arch_height:     (config_hash["glazebar_gothic_arch_height_mm"] || 0).to_f * mm_to_inch,
            arch_height_mm:  (config_hash["glazebar_gothic_arch_height_mm"] || 0).to_f,
            h_offset:        (config_hash["glazebar_horizontal_offset_mm"] || 0).to_f * mm_to_inch,    # <-- Uniform vertical nudge for horizontal bars
            h_offset_mm:     (config_hash["glazebar_horizontal_offset_mm"] || 0).to_f
        }

        clear_box = na_compute_clear_glazing_box(origin_x_mm, origin_z_mm,
                                                 panel_w_mm, panel_h_mm,
                                                 head_rail_mm, base_rail_mm,
                                                 stile_width_mm)
        return unless clear_box

        return unless defined?(Na__AssemblyStudio::Na__WindowSystem::Na__GeometryBuilders)

        builders     = Na__AssemblyStudio::Na__WindowSystem::Na__GeometryBuilders
        if frame_material.nil?
            material_mgr = Na__AssemblyStudio::Na__AppData::Na__MaterialManager
            frame_mat_id = config_hash["frame_material_id"] ||
                           Na__AssemblyStudio::Na__WindowSystem::NA_DEFAULT_FRAME_MATERIAL_ID
            frame_material = material_mgr.na_get_material_by_id(frame_mat_id)
        end
        frame_mat    = frame_material

        glass_w_in        = GeometryHelpers.na_mm_to_inch(clear_box[:width])
        glass_h_in        = GeometryHelpers.na_mm_to_inch(clear_box[:height])
        bar_w_in          = GeometryHelpers.na_mm_to_inch(bar_width_mm)
        glass_offset_x_in = GeometryHelpers.na_mm_to_inch(clear_box[:x])
        glass_offset_z_in = GeometryHelpers.na_mm_to_inch(clear_box[:z])
        glass_thick_in    = GeometryHelpers.na_mm_to_inch(glass_thick_mm)
        panel_t_in        = GeometryHelpers.na_mm_to_inch(panel_t_mm)
        bar_inset_in      = GeometryHelpers.na_mm_to_inch(bar_inset_mm)
        panel_y_in        = GeometryHelpers.na_mm_to_inch(origin_y_mm)

        removed = config_hash["removed_glazebars"]
        removed = [] unless removed.is_a?(Array)

        builders.na_create_glazebar_geometry(
            entities,
            panel_id,
            glass_w_in,
            glass_h_in,
            h_bars,
            v_bars,
            bar_w_in,
            glass_thick_in,
            glass_offset_x_in,
            glass_offset_z_in,
            panel_t_in,
            frame_mat,
            panel_y_in,
            panel_t_in,
            0.0,
            bar_inset_in,
            removed,
            0,
            0,
            panel_index,
            0,
            advanced_glazebar
        )
    rescue StandardError => e
        DebugTools.na_debug_error("ExtSlide::AssemblyComposer.na_build_panel_glaze_bars failed", e)
    end
    private_class_method :na_build_panel_glaze_bars
    # ---------------------------------------------------------------

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
    def self.na_build_placeholder_rot(config_hash, dims, parent_entities)
        slide_mode      = config_hash["sliding_door_mode"].to_s
        leaf_w_mm       = GeometryHelpers.na_compute_leaf_width_mm(dims[:inner_w_mm])
        rot_x_mm        = dims[:frame_left_mm] + ((slide_mode == "FrontSlidesLeft") ? leaf_w_mm : 0.0)

        origin_in       = Geom::Point3d.new(
            GeometryHelpers.na_mm_to_inch(rot_x_mm),
            GeometryHelpers.na_mm_to_inch(0.0),
            GeometryHelpers.na_mm_to_inch(dims[:frame_bottom_mm])
        )

        RotationPivotBuilder.na_build_rotation_pivot(parent_entities, origin_in)
    end
    private_class_method :na_build_placeholder_rot
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Build an MVE Marker for a Single Translating Leaf
    # ------------------------------------------------------------
    def self.na_build_panel_mve_marker(config_hash, dims, descriptor, parent_entities, mve_index)
        return nil if descriptor[:mve_distance_mm].to_i == 0

        panel_h_mm      = descriptor[:height_mm].to_f
        marker_z_mm     = dims[:frame_bottom_mm] + panel_h_mm                    # <-- MVE marker at leaf TOP

        origin_in       = Geom::Point3d.new(
            GeometryHelpers.na_mm_to_inch(dims[:frame_left_mm] + descriptor[:hinge_x_mm].to_f),
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
    # V1.7.1 added the optional `material` argument so timber + glass
    # parts can carry the correct SketchUp material - without this they
    # rendered as plain white.
    def self.na_create_box_mm(entities, name, x_mm, y_mm, z_mm, w_mm, d_mm, h_mm, material = nil)
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
            material
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
        double_dict_key   = "Na__ExteriorDoubleDoorConfiguratorInfo".freeze
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

                double_id = na_safe_get_attribute(instance, double_dict_key, legacy_id_key)
                used << na_extract_adr_number(double_id) if double_id
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
