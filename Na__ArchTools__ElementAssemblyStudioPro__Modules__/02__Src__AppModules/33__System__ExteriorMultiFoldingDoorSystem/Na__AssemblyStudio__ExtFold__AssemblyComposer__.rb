# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - BIFOLD DOOR ASSEMBLY COMPOSER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtFold__AssemblyComposer__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem
# MODULE     : Na__AssemblyComposer
# AUTHOR     : Noble Architecture
# PURPOSE    : Orchestrates the per-panel composition of a bifold door
#              ADR. Receives a panel descriptor list from the chosen
#              Layout module and emits flat-sibling MOD/ROT/MVE groups
#              under the ADR ComponentDefinition entities.
# CREATED    : 17-May-2026
#
# DESCRIPTION:
# - Outer ADR is the door's ComponentDefinition itself
#   (e.g. ADR017__BifoldDoor__) - we do NOT wrap an inner ADR group.
#   The MOD/ROT/MVE markers sit as direct siblings inside the
#   definition entities so the GLB exporter preserves the names that
#   TrueVision3D's animation scanner relies on.
# - Each MOD group encodes its open-state transformation in the group
#   NAME, parsed by TrueVision3D at runtime:
#     * ROT-only:  MOD###__ROT__-90-Deg__BifoldPanel
#     * ROT + MVE: MOD###__ROT__180-Deg__MVE__X--600-mm__BifoldPanel
#   Names are formatted via the constants on
#   `Na__ExteriorMultiFoldingDoorSystem`: NA_MOD_NAME_FORMAT_ROT_ONLY
#   and NA_MOD_NAME_FORMAT_ROT_MVE.
# - Each ROT marker uses NA_GROUP_NAME_ROT_HINGE_FORMAT
#   (`ROT001__RotationPoint__BifoldHingeCentre`).
# - Each MVE marker uses NA_MVE_NAME_FORMAT
#   (`MVE001__MovementPoint__BifoldPanelTrack`).
# - ROT and MVE indices increment INDEPENDENTLY of the MOD index so
#   numbering stays compact (e.g. master panels skip the MVE counter).
# - ADR id allocator scans BOTH the bifold dictionary
#   (`Na__BifoldDoorConfiguratorInfo`) and the legacy interior-door
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
# 17-May-2026 - Version 0.2.0
# - Phase-3a implementation: ADR allocation, panel geometry, MOD/ROT/MVE
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
require_relative '../20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__LeadedGlassBuilder__'
require_relative '../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__PanelGeometryBuilder__'
require_relative '../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__PanelLineworkBuilder__'
require_relative 'Na__AssemblyStudio__ExtFold__GeometryHelpers__'
require_relative 'Na__AssemblyStudio__ExtFold__PanelLayoutResolver__'
require_relative 'Na__AssemblyStudio__ExtFold__RotationPivotBuilder__'
require_relative 'Na__AssemblyStudio__ExtFold__MovementPivotBuilder__'

module Na__AssemblyStudio
module Na__ExteriorMultiFoldingDoorSystem
module Na__AssemblyComposer

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

    DebugTools           = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
    TagManager           = Na__AssemblyStudio::Na__AppUtils::Na__TagManager
    Box                  = Na__AssemblyStudio::Na__GeometryHelpers::Na__Box
    GeometryHelpers      = Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::Na__GeometryHelpers
    PanelLayoutResolver  = Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::Na__PanelLayoutResolver
    SharedPanelGeometry  = Na__AssemblyStudio::Na__ExteriorDoorCommon::Na__PanelGeometryBuilder
    SharedPanelLinework  = Na__AssemblyStudio::Na__ExteriorDoorCommon::Na__PanelLineworkBuilder
    RotationPivotBuilder = Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::Na__RotationPivotBuilder
    MovementPivotBuilder = Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::Na__MovementPivotBuilder
    WindowBuilders       = Na__AssemblyStudio::Na__WindowSystem::Na__GeometryBuilders
    LeadedGlassBuilder   = Na__AssemblyStudio::Na__WindowSystem::Na__LeadedGlassBuilder
    NA_PANEL_NAMING      = { :container => 'Na__ExteriorMultiFoldDoor' }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants - Per-Panel Group Naming (Phase-9 FuseParts compatible)
# -----------------------------------------------------------------------------
#
# Phase-9 renamed the inner panel parts to the FuseParts-compatible
# `Na_DoorPanel_{panel_id}_*` / `Na_Glass_{panel_id}` scheme so the
# bifold panel fuser can discover and merge them via the same regex
# the exterior single-door fuser uses. `panel_id` for a bifold leaf is
# `Bifold_{ADR_id}_P{NN}` (NN = zero-padded panel index, 1-based).
#
    NA_PANEL_ID_FORMAT_BIFOLD        = "Bifold_%s_P%02d".freeze
    NA_PANEL_ID_FORMAT_BIFOLD_NOADR  = "Bifold_NoADR_P%02d".freeze
    NA_PART_NAME_RAIL_TOP            = "Na_DoorPanel_%s_Rail_Top".freeze
    NA_PART_NAME_RAIL_BOTTOM         = "Na_DoorPanel_%s_Rail_Bottom".freeze
    NA_PART_NAME_STILE_LEFT          = "Na_DoorPanel_%s_Stile_Left".freeze
    NA_PART_NAME_STILE_RIGHT         = "Na_DoorPanel_%s_Stile_Right".freeze
    NA_PART_NAME_GLAZING             = "Na_Glass_%s".freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - ADR ID Allocation
# -----------------------------------------------------------------------------

    # FUNCTION | Allocate the Next Available ADR Identifier
    # ------------------------------------------------------------
    # Scans both bifold and interior-door attribute dictionaries on
    # every ComponentInstance in the model so IDs stay globally unique
    # across systems. Returns the formatted ADR string (e.g. "ADR017").
    #
    # @param model [Sketchup::Model] active model (defaults to active)
    # @return [String] formatted ADR id
    def self.na_allocate_adr_id(model = Sketchup.active_model)
        return format_adr(1) unless model

        used_numbers = na_collect_used_adr_numbers(model)
        next_number  = (used_numbers.empty? ? 1 : used_numbers.max + 1)
        format_adr(next_number)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Format an ADR Number Into the Standard String Form
    # ------------------------------------------------------------
    def self.format_adr(number)
        format(Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::NA_DOOR_ID_FORMAT, number.to_i)
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Compose ADR
# -----------------------------------------------------------------------------

    # FUNCTION | Compose the ADR Component Entities From a Panel Descriptor List
    # ------------------------------------------------------------
    # Builds the sibling MOD / ROT / MVE groups inside the supplied
    # `parent_entities` (the ADR ComponentDefinition's entities).
    # Phase-9: also delegates the static opening frame + cill geometry
    # to the WindowSystem GeometryBuilders so the door inherits the
    # window's per-edge frame, depth, wall-inset and cill controls.
    #
    # @param config_hash       [Hash]              full bifold config
    # @param panel_descriptors [Array<Hash>]       per-panel descriptors
    # @param parent_entities   [Sketchup::Entities] target entities
    # @param door_id           [String,nil]        ADR id (e.g. "ADR017") for FuseParts naming
    # @return [Hash] { :mod_groups => [...], :rot_groups => [...], :mve_groups => [...] }
    def self.na_compose_adr(config_hash, panel_descriptors, parent_entities, door_id = nil)
        return nil unless parent_entities
        return nil unless panel_descriptors.is_a?(Array)

        DebugTools.na_debug_method("ExtFold::AssemblyComposer.na_compose_adr (#{panel_descriptors.length} panels)")

        dims      = GeometryHelpers.na_resolve_door_opening_dimensions(config_hash)
        materials = na_resolve_materials(config_hash)                          # <-- V1.7.1: shared frame + glass materials for the whole ADR

        na_build_opening_frame(config_hash, dims, parent_entities, materials)
        na_build_opening_cill(config_hash,  dims, parent_entities)

        result = { :mod_groups => [], :rot_groups => [], :mve_groups => [] }
        rot_index = 1
        mve_index = 1

        panel_descriptors.each do |descriptor|
            mod_group = na_build_panel_mod_group(config_hash, dims, descriptor, parent_entities, door_id, materials)
            result[:mod_groups] << mod_group if mod_group

            rot_group = na_build_panel_rot_marker(config_hash, dims, descriptor, parent_entities, rot_index)
            if rot_group
                result[:rot_groups] << rot_group
                rot_index += 1
            end

            if descriptor[:mve_axis] && descriptor[:mve_distance_mm].to_i != 0
                mve_group = na_build_panel_mve_marker(config_hash, dims, descriptor, parent_entities, mve_index)
                if mve_group
                    result[:mve_groups] << mve_group
                    mve_index += 1
                end
            end
        end

        na_apply_cill_lift(config_hash, dims, parent_entities)                 # <-- V1.7.1: shift everything up so the cill sits ON the floor

        result
    rescue StandardError => e
        DebugTools.na_debug_error("ExtFold::AssemblyComposer.na_compose_adr failed", e)
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
        DebugTools.na_debug_error("ExtFold::AssemblyComposer.na_resolve_materials failed", e)
        { :frame => nil, :glass => nil }
    end
    private_class_method :na_resolve_materials
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Build the Static Per-Edge Opening Frame
    # ------------------------------------------------------------
    # Delegates to `Na__WindowSystem::Na__GeometryBuilders.na_create_frame_geometry`
    # so the same per-edge thickness, depth, wall_inset and frame
    # material logic drives every opening type. Inputs are millimetres
    # converted to inches at the call site.
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
        DebugTools.na_debug_error("ExtFold::AssemblyComposer.na_build_opening_frame failed", e)
    end
    private_class_method :na_build_opening_frame
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Lift the ADR So the Cill Sits ON Top of the Floor (V1.7.1)
    # ------------------------------------------------------------
    # Pre-V1.7.1 the cill geometry occupied the negative-Z slab below the
    # frame (z = -cill_height to 0). When the user dropped the component
    # at floor level the cill ended up below the floor and the entire
    # door was effectively cill_height too low - they had to manually
    # nudge it up to close the gap at the head.
    #
    # V1.7.1: We post-process the ADR by translating every entity up by
    # cill_height when the cill is enabled. The cill ends up at z = 0..H
    # (sitting on the floor), the frame moves up to z = H..H+frame_h
    # (sitting on the cill), and every ROT/MVE marker rises with its
    # panel so the TrueVision animation pipeline stays consistent.
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
        DebugTools.na_debug_error("ExtFold::AssemblyComposer.na_apply_cill_lift failed", e)
    end
    private_class_method :na_apply_cill_lift
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Build the Optional Cill Below the Opening
    # ------------------------------------------------------------
    # Gated on `has_cill == true && frame_bottom_mm > 0` so a frameless
    # opening cannot accidentally float a cill in mid-air. Cill material
    # honours the `paint_cill` toggle (frame finish if true, default
    # Sapele timber otherwise) to mirror window behaviour.
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
        DebugTools.na_debug_error("ExtFold::AssemblyComposer.na_build_opening_cill failed", e)
    end
    private_class_method :na_build_opening_cill
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Per-Panel MOD Group
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Build the MOD Group for a Single Panel
    # ------------------------------------------------------------
    # The MOD group is the moving part of the panel. Its NAME encodes
    # the open-state ROT (and optional MVE) transformation that
    # TrueVision3D's animation scanner parses at runtime. The geometry
    # inside is the panel's frame (rails + stiles) plus either a fully
    # glazed lite or fielded-panel layout driven by
    # bifold_door_leaf_composition (FullyGlazed / GlazedOverFielded /
    # FullyFielded) via PanelLayoutResolver + ExtDoorCommon builders.
    #
    # Phase-9: panel inner parts now use the FuseParts-compatible
    # `Na_DoorPanel_{panel_id}_*` naming, panel sits inside the inner
    # clear opening (offset by frame_left/bottom), and the joinery is
    # flipped so stiles span the full panel height with rails between
    # them (mirrors window casement construction).
    def self.na_build_panel_mod_group(config_hash, dims, descriptor, parent_entities, door_id, materials = nil)
        mod_name        = na_resolve_mod_name(descriptor)
        mod_group       = parent_entities.add_group
        mod_group.name  = mod_name
        mod_entities    = mod_group.entities

        materials       = na_resolve_materials(config_hash) if materials.nil?
        frame_material  = materials[:frame]
        glass_material  = materials[:glass]

        panel_t_mm      = config_hash["bifold_door_panel_thickness_mm"].to_f
        panel_w_mm      = descriptor[:width_mm].to_f
        panel_h_mm      = descriptor[:height_mm].to_f
        origin_x_mm     = dims[:frame_left_mm]   + descriptor[:origin_x_mm].to_f
        origin_y_mm     = GeometryHelpers.na_compute_panel_y_origin_in_frame_mm(
                              panel_t_mm, dims[:frame_depth_mm], dims[:frame_wall_inset_mm]
                          )
        origin_z_mm     = dims[:frame_bottom_mm]
        panel_id        = na_resolve_panel_id(descriptor, door_id)
        part_names      = na_resolve_panel_part_names(panel_id)

        leaf = {
            :index => descriptor[:index].to_i,
            :origin_x_mm => origin_x_mm,
            :origin_y_mm => origin_y_mm,
            :origin_z_mm => origin_z_mm,
            :width_mm => panel_w_mm,
            :height_mm => panel_h_mm,
            :thickness_mm => panel_t_mm
        }
        # @delegate: Na__AssemblyStudio__ExtFold__PanelLayoutResolver__.rb
        panel_layout = PanelLayoutResolver.na_resolve(config_hash, leaf)

        if panel_layout[:composition] == 'FullyGlazed'
            head_rail_mm   = config_hash["bifold_door_head_rail_mm"].to_f
            base_rail_mm   = config_hash["bifold_door_base_rail_mm"].to_f
            stile_width_mm = config_hash["bifold_door_stile_width_mm"].to_f
            na_build_panel_stiles(mod_entities, origin_x_mm, origin_y_mm, origin_z_mm,
                                  panel_w_mm, panel_h_mm, panel_t_mm,
                                  stile_width_mm, part_names, frame_material)
            na_build_panel_rails(mod_entities, origin_x_mm, origin_y_mm, origin_z_mm,
                                 panel_w_mm, panel_h_mm, panel_t_mm,
                                 head_rail_mm, base_rail_mm, stile_width_mm, part_names, frame_material)
            na_build_panel_glazing(mod_entities, origin_x_mm, origin_y_mm, origin_z_mm,
                                   panel_w_mm, panel_h_mm, panel_t_mm,
                                   head_rail_mm, base_rail_mm, stile_width_mm, part_names, glass_material)
            na_build_panel_glaze_bars(mod_entities, config_hash, dims,
                                      origin_x_mm, origin_y_mm, origin_z_mm,
                                      panel_w_mm, panel_h_mm, panel_t_mm,
                                      head_rail_mm, base_rail_mm, stile_width_mm,
                                      panel_id, descriptor[:index].to_i,
                                      frame_material)
            na_build_panel_leaded_glass(mod_entities, config_hash,
                                        origin_x_mm, origin_y_mm, origin_z_mm,
                                        panel_w_mm, panel_h_mm, panel_t_mm,
                                        head_rail_mm, base_rail_mm, stile_width_mm,
                                        panel_id)
        else
            na_build_fielded_leaf_members(mod_entities, leaf, panel_layout, part_names, frame_material)
            na_build_fielded_field_dividers(mod_entities, leaf, panel_layout, frame_material, panel_id)
            na_build_fielded_glazed_region(mod_entities, leaf, panel_layout, part_names, materials, config_hash)
            if panel_layout[:output_mode] == 'Linework'
                SharedPanelLinework.na_build(
                    mod_entities, leaf, panel_layout, frame_material, NA_PANEL_NAMING,
                    edge_colour_id: config_hash['edge_colour_fielded_panel_id']
                )
            else
                SharedPanelGeometry.na_build(mod_entities, leaf, panel_layout, frame_material, NA_PANEL_NAMING)
            end
        end

        DebugTools.na_debug_geometry(
            "ExtFold MOD: #{mod_name} (panel #{descriptor[:index]}, w=#{panel_w_mm.round}mm, role=#{descriptor[:role]}, composition=#{panel_layout[:composition]})"
        )
        mod_group
    end
    private_class_method :na_build_panel_mod_group
    # ---------------------------------------------------------------

    def self.na_build_fielded_leaf_members(entities, leaf, layout, part_names, material)
        members = layout[:members]
        stile = members[:stile_width_mm]
        top_rail = members[:top_rail_width_mm]
        bottom_rail = members[:bottom_rail_width_mm]
        na_create_box_mm(entities, part_names[:stile_left], leaf[:origin_x_mm], leaf[:origin_y_mm], leaf[:origin_z_mm],
                         stile, leaf[:thickness_mm], leaf[:height_mm], material)
        na_create_box_mm(entities, part_names[:stile_right], leaf[:origin_x_mm] + leaf[:width_mm] - stile,
                         leaf[:origin_y_mm], leaf[:origin_z_mm], stile, leaf[:thickness_mm], leaf[:height_mm], material)
        inner_width = leaf[:width_mm] - 2.0 * stile
        na_create_box_mm(entities, part_names[:rail_bottom], leaf[:origin_x_mm] + stile, leaf[:origin_y_mm], leaf[:origin_z_mm],
                         inner_width, leaf[:thickness_mm], bottom_rail, material)
        na_create_box_mm(entities, part_names[:rail_top], leaf[:origin_x_mm] + stile, leaf[:origin_y_mm],
                         leaf[:origin_z_mm] + leaf[:height_mm] - top_rail,
                         inner_width, leaf[:thickness_mm], top_rail, material)

        return unless layout[:composition] == 'GlazedOverFielded' && layout[:field_region]
        mid_z = layout[:field_region][:z_mm] + layout[:field_region][:height_mm]
        panel_token = part_names[:glazing].to_s.sub(/^Na_Glass_/, '')
        na_create_box_mm(entities, "Na_DoorPanel_#{panel_token}_Rail_Mid",
                         leaf[:origin_x_mm] + stile, leaf[:origin_y_mm], mid_z,
                         inner_width, leaf[:thickness_mm], members[:mid_rail_width_mm], material)
    end
    private_class_method :na_build_fielded_leaf_members
    # ---------------------------------------------------------------

    def self.na_build_fielded_field_dividers(entities, leaf, layout, material, panel_id)
        layout[:field_dividers].each do |divider|
            role = divider[:orientation] == :vertical ? 'FieldStile' : 'FieldRail'
            name = format('Na__ExteriorMultiFoldDoor__%s__%s%02d', panel_id, role, divider[:index])
            na_create_box_mm(entities, name, divider[:x_mm], leaf[:origin_y_mm], divider[:z_mm],
                             divider[:width_mm], leaf[:thickness_mm], divider[:height_mm], material)
        end
    end
    private_class_method :na_build_fielded_field_dividers
    # ---------------------------------------------------------------

    def self.na_build_fielded_glazed_region(entities, leaf, layout, part_names, materials, config_hash = {})
        region = layout[:glazed_region]
        return unless region && region[:height_mm] > 0

        glass_depth = [leaf[:thickness_mm] * 0.35, 2.0].max
        glass_y = leaf[:origin_y_mm] + (leaf[:thickness_mm] - glass_depth) / 2.0
        na_create_box_mm(entities, part_names[:glazing],
                         region[:x_mm], glass_y, region[:z_mm],
                         region[:width_mm], glass_depth, region[:height_mm], materials[:glass])

        bars = layout[:glaze_bars]
        if bars && (bars[:vertical_count].to_i > 0 || bars[:horizontal_count].to_i > 0)
            panel_token = part_names[:glazing].to_s.sub(/^Na_Glass_/, '')
            y = leaf[:origin_y_mm] + bars[:inset_mm]
            depth = [leaf[:thickness_mm] - 2.0 * bars[:inset_mm], 2.0].max
            positions = na_final_bar_positions_mm(layout)
            vertical_positions = positions[:vertical]
            horizontal_positions = positions[:horizontal]

            vertical_positions.each_with_index do |x, index|
                na_create_box_mm(entities, "Na_GlazeBar_#{panel_token}_V#{index + 1}",
                                 x - bars[:width_mm] / 2.0, y, region[:z_mm],
                                 bars[:width_mm], depth, region[:height_mm], materials[:frame])
            end
            horizontal_positions.each_with_index do |z, index|
                na_create_box_mm(entities, "Na_GlazeBar_#{panel_token}_H#{index + 1}",
                                 region[:x_mm], y, z - bars[:width_mm] / 2.0,
                                 region[:width_mm], depth, bars[:width_mm], materials[:frame])
            end
        end

        panel_id = part_names[:glazing].to_s.sub(/^Na_Glass_/, '')
        na_create_leaded_from_region_mm(entities, config_hash, panel_id, region, glass_y)
    end
    private_class_method :na_build_fielded_glazed_region
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Final Bar Centerlines For One Panel (mm space)
    # ------------------------------------------------------------
    # Spacing -> uniform horizontal offset -> per-bar offsets. Mirrors
    # ExtDouble so GlazedOverFielded bifold panels honour the same
    # glazebar_h_offset_N_mm / glazebar_v_offset_N_mm sliders.
    def self.na_final_bar_positions_mm(layout)
        region = layout[:glazed_region]
        bars = layout[:glaze_bars]
        vertical_positions = WindowBuilders.na_compute_bar_positions(
            region[:x_mm],
            region[:width_mm],
            bars[:vertical_count],
            bars[:margin_enabled],
            bars[:margin_offset_mm]
        )
        vertical_positions = WindowBuilders.na_apply_bar_offsets(vertical_positions, bars[:v_offsets_mm])
        horizontal_positions = WindowBuilders.na_compute_bar_positions(
            region[:z_mm],
            region[:height_mm],
            bars[:horizontal_count],
            bars[:margin_enabled],
            bars[:margin_offset_mm]
        ).map { |position| position + bars[:horizontal_offset_mm] }
        horizontal_positions = WindowBuilders.na_apply_bar_offsets(horizontal_positions, bars[:h_offsets_mm])
        { :horizontal => horizontal_positions, :vertical => vertical_positions }
    end
    private_class_method :na_final_bar_positions_mm
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Resolve the FuseParts-Compatible Panel Identifier
    # ------------------------------------------------------------
    def self.na_resolve_panel_id(descriptor, door_id)
        idx = descriptor[:index].to_i
        if door_id.is_a?(String) && !door_id.empty?
            format(NA_PANEL_ID_FORMAT_BIFOLD, door_id, idx)
        else
            format(NA_PANEL_ID_FORMAT_BIFOLD_NOADR, idx)
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

    # HELPER FUNCTION | Resolve the MOD Group Name From a Panel Descriptor
    # ------------------------------------------------------------
    # The axis letter is normalised to a single uppercase character (X / Y / Z)
    # because the MVE format already embeds the magnitude's signed direction
    # via "%+d". See `Na__AssemblyStudio__DoorNamingContract__.rb` for the
    # canonical cross-system contract.
    def self.na_resolve_mod_name(descriptor)
        index           = descriptor[:index].to_i
        rot_deg         = descriptor[:rot_degrees].to_i
        mve_axis        = descriptor[:mve_axis]
        mve_distance_mm = descriptor[:mve_distance_mm].to_i

        if mve_axis.nil? || mve_distance_mm == 0
            format(
                Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::NA_MOD_NAME_FORMAT_ROT_ONLY,
                index, rot_deg.to_s
            )
        else
            axis_letter = na_normalise_axis_letter(mve_axis)
            format(
                Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::NA_MOD_NAME_FORMAT_ROT_MVE,
                index, rot_deg.to_s, axis_letter, mve_distance_mm
            )
        end
    end
    private_class_method :na_resolve_mod_name
    # ---------------------------------------------------------------


    # HELPER FUNCTION | Coerce an Axis Hint to a Single Uppercase Letter
    # ------------------------------------------------------------
    # Accepts symbols ("X" / :x / "X+" / "X-") and returns the canonical
    # single-letter token consumed by the MVE name format string.
    def self.na_normalise_axis_letter(axis_hint)
        s = axis_hint.to_s.upcase
        return s[0, 1] if s.length >= 1 && s[0, 1] =~ /[XYZ]/
        "X"
    end
    private_class_method :na_normalise_axis_letter
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Per-Panel Rails / Stiles / Glazing
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Build the Top + Base Rails of a Bifold Panel (Phase-9 joinery)
    # ------------------------------------------------------------
    # Window-style joinery: rails sit BETWEEN the two stiles. Their X
    # extent is `panel_w - 2*stile_width` and they slot in from
    # x = origin + stile_width. This matches how real bifold panels
    # are jointed and matches the WindowSystem's casement construction.
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

    # HELPER FUNCTION | Build the Left + Right Stiles of a Bifold Panel (Phase-9 joinery)
    # ------------------------------------------------------------
    # Window-style joinery: stiles span the FULL panel height, with
    # rails terminating between them. This is how real bifold leaves
    # are constructed and matches the WindowSystem's casement frame.
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
    # Glazing fills the clear inner rectangle bounded by stiles
    # (X) and rails (Z). Origin Y is centred in the panel thickness so
    # the glass reads as a thin pane rather than a full slab.
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

    # HELPER FUNCTION | Build the Glaze-Bar Grille for a Single Panel (Phase-9)
    # ------------------------------------------------------------
    # Mirrors the window casement grille: horizontal + vertical bars
    # fill the clear inner rectangle, sized via shared
    # `horizontal_glaze_bars`, `vertical_glaze_bars`, `glaze_bar_width_mm`,
    # `glazebar_inset_mm` keys. Delegates to the WindowSystem builder
    # so a single regression on glaze-bar geometry hits every opening
    # type at once.
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

        advanced_glazebar = na_fold_advanced_glazebar_hash(config_hash)

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

        # WindowSystem grille builder: bars inset from casement faces by
        # glazebar_inset. We treat each bifold leaf as one casement
        # (panel_t = casement_depth, casement_inset = 0, wall_inset =
        # the panel's Y-origin inside the door reveal).
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
        DebugTools.na_debug_error("ExtFold::AssemblyComposer.na_build_panel_glaze_bars failed", e)
    end
    private_class_method :na_build_panel_glaze_bars
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Build Leaded Glass Overlay for Fully-Glazed Leaf
    # ------------------------------------------------------------
    def self.na_build_panel_leaded_glass(entities, config_hash,
                                         origin_x_mm, origin_y_mm, origin_z_mm,
                                         panel_w_mm, panel_h_mm, panel_t_mm,
                                         head_rail_mm, base_rail_mm, stile_width_mm,
                                         panel_id)
        clear_box = na_compute_clear_glazing_box(origin_x_mm, origin_z_mm,
                                                 panel_w_mm, panel_h_mm,
                                                 head_rail_mm, base_rail_mm,
                                                 stile_width_mm)
        return unless clear_box

        glass_y_mm = origin_y_mm + GeometryHelpers.na_compute_glazing_y_origin_mm(panel_t_mm)
        na_create_leaded_from_region_mm(entities, config_hash, panel_id, clear_box, glass_y_mm)
    rescue StandardError => e
        DebugTools.na_debug_error("ExtFold::AssemblyComposer.na_build_panel_leaded_glass failed", e)
    end
    private_class_method :na_build_panel_leaded_glass
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Advanced Glazebar Hash (mm config -> inch space)
    # ------------------------------------------------------------
    # Single packing shared by the glaze bar builder and the leaded glass
    # cell grid so bar positions and lead cells always agree. Values are
    # converted to inches inline so the WindowSystem builder receives the
    # same units it gets when called from the regular window code path.
    def self.na_fold_advanced_glazebar_hash(config_hash)
        mm_to_inch = 1.0 / 25.4
        h_bars = (config_hash["horizontal_glaze_bars"] || 0).to_i
        v_bars = (config_hash["vertical_glaze_bars"]   || 0).to_i
        {
            margin_enabled:  config_hash["glazebar_margin_enabled"] == true,
            margin_offset:   (config_hash["glazebar_margin_offset_mm"] || 0).to_f * mm_to_inch,
            arch_enabled:    config_hash["glazebar_gothic_arch_enabled"] == true,
            arch_amount:     [[(config_hash["glazebar_gothic_arch_amount"] || 2).to_i, 1].max, 8].min,           # <-- V1.9.4 Allow single lancet arch
            arch_height:     (config_hash["glazebar_gothic_arch_height_mm"] || 0).to_f * mm_to_inch,
            arch_height_mm:  (config_hash["glazebar_gothic_arch_height_mm"] || 0).to_f,
            h_offset:        (config_hash["glazebar_horizontal_offset_mm"] || 0).to_f * mm_to_inch,    # <-- Uniform vertical nudge for horizontal bars
            h_offset_mm:     (config_hash["glazebar_horizontal_offset_mm"] || 0).to_f,
            h_bar_offsets:   (1..h_bars).map { |i| (config_hash["glazebar_h_offset_#{i}_mm"] || 0).to_f * mm_to_inch },   # <-- Per-bar vertical nudges (inches)
            v_bar_offsets:   (1..v_bars).map { |i| (config_hash["glazebar_v_offset_#{i}_mm"] || 0).to_f * mm_to_inch }    # <-- Per-bar horizontal nudges (inches)
        }
    end
    private_class_method :na_fold_advanced_glazebar_hash
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Create Leaded Glass From mm Region + Outer Face Y
    # ------------------------------------------------------------
    # Lead lines are laid out per glazing cell between the FINAL glaze
    # bar centerlines (per-cell render parity with the elevation preview;
    # no click-toggle on bifold panels yet, so no disabled-cell set).
    def self.na_create_leaded_from_region_mm(entities, config_hash, panel_id, region, glass_y_mm)
        leaded = LeadedGlassBuilder.na_resolve_leaded_params(config_hash)
        return unless leaded[:enabled]
        return if leaded[:h_bars] <= 0 && leaded[:v_bars] <= 0

        width_mm = region[:width] || region[:width_mm]
        height_mm = region[:height] || region[:height_mm]
        x_mm = region[:x] || region[:x_mm]
        z_mm = region[:z] || region[:z_mm]
        return unless width_mm.to_f > 0 && height_mm.to_f > 0

        mm = 1.0 / 25.4
        grid = nil
        if defined?(Na__AssemblyStudio::Na__WindowSystem::Na__GeometryBuilders)
            builders = Na__AssemblyStudio::Na__WindowSystem::Na__GeometryBuilders
            bar_layout = builders.na_compute_final_bar_positions(
                x_mm * mm, z_mm * mm, width_mm * mm, height_mm * mm,
                (config_hash["horizontal_glaze_bars"] || 0).to_i,
                (config_hash["vertical_glaze_bars"] || 0).to_i,
                (config_hash["glaze_bar_width_mm"] || 25).to_f * mm,
                na_fold_advanced_glazebar_hash(config_hash)
            )
            grid = {
                h_positions: bar_layout[:h_positions],
                v_positions: bar_layout[:v_positions],
                bar_width: (config_hash["glaze_bar_width_mm"] || 25).to_f * mm,
                effective_glass_height: bar_layout[:effective_glass_height]
            }
        end
        LeadedGlassBuilder.na_create_leaded_glass_geometry(
            entities,
            panel_id,
            width_mm * mm,
            height_mm * mm,
            x_mm * mm,
            z_mm * mm,
            glass_y_mm * mm,
            leaded,
            grid: grid
        )
    end
    private_class_method :na_create_leaded_from_region_mm
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Per-Panel ROT + MVE Markers
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Build the ROT Marker for a Single Panel
    # ------------------------------------------------------------
    # Phase-9: hinge X/Y are now relative to the inner clear left edge,
    # so the marker is offset by the resolved frame edges. Z origin is
    # the bottom frame thickness (replaces the old floor_clearance).
    def self.na_build_panel_rot_marker(config_hash, dims, descriptor, parent_entities, rot_index)
        panel_h_mm      = descriptor[:height_mm].to_f
        rotation_deg    = descriptor[:rot_degrees].to_i
        panel_t_mm      = config_hash["bifold_door_panel_thickness_mm"].to_f

        hinge_y_panel_local = descriptor[:hinge_y_mm].to_f                      # <-- Layout-local (Y=0 at panel front face)
        panel_y_origin_mm   = GeometryHelpers.na_compute_panel_y_origin_in_frame_mm(
                                  panel_t_mm, dims[:frame_depth_mm], dims[:frame_wall_inset_mm]
                              )

        origin_in       = Geom::Point3d.new(
            GeometryHelpers.na_mm_to_inch(dims[:frame_left_mm] + descriptor[:hinge_x_mm].to_f),
            GeometryHelpers.na_mm_to_inch(panel_y_origin_mm + hinge_y_panel_local),
            GeometryHelpers.na_mm_to_inch(dims[:frame_bottom_mm])
        )

        RotationPivotBuilder.na_build_rotation_pivot(
            parent_entities,
            origin_in,
            rot_index,
            panel_h_mm,
            rotation_deg
        )
    end
    private_class_method :na_build_panel_rot_marker
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Build the MVE Marker for a Single Translating Panel
    # ------------------------------------------------------------
    # Phase-9: same offsets as ROT marker - X relative to inner clear,
    # Z based on frame_bottom + panel_h, Y in centred panel reveal.
    def self.na_build_panel_mve_marker(config_hash, dims, descriptor, parent_entities, mve_index)
        panel_h_mm      = descriptor[:height_mm].to_f
        panel_t_mm      = config_hash["bifold_door_panel_thickness_mm"].to_f
        mve_axis        = descriptor[:mve_axis]
        mve_distance_mm = descriptor[:mve_distance_mm].to_i

        marker_z_mm     = dims[:frame_bottom_mm] + panel_h_mm                   # <-- MVE marker at panel TOP (head jamb height)
        hinge_y_panel_local = descriptor[:hinge_y_mm].to_f
        panel_y_origin_mm   = GeometryHelpers.na_compute_panel_y_origin_in_frame_mm(
                                  panel_t_mm, dims[:frame_depth_mm], dims[:frame_wall_inset_mm]
                              )

        origin_in       = Geom::Point3d.new(
            GeometryHelpers.na_mm_to_inch(dims[:frame_left_mm] + descriptor[:hinge_x_mm].to_f),
            GeometryHelpers.na_mm_to_inch(panel_y_origin_mm + hinge_y_panel_local),
            GeometryHelpers.na_mm_to_inch(marker_z_mm)
        )

        MovementPivotBuilder.na_build_movement_pivot(
            parent_entities,
            origin_in,
            mve_index,
            mve_axis,
            mve_distance_mm
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
    # Wraps the shared `Na__GeometryHelpers__Box.na_create_grouped_box`
    # primitive so callers stay in mm units. V1.7.1 added the optional
    # `material` argument so timber + glass parts can carry the correct
    # SketchUp material - without this they rendered as plain white.
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
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - ADR ID Scanning
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Collect All ADR Numbers Already Present on the Model
    # ------------------------------------------------------------
    # Walks every ComponentInstance and inspects every door system's
    # attribute dictionary for stored ADR ids. The ADR id pool is shared
    # across all door systems (interior, bifold, sliding) so a bifold door
    # cannot be allocated an id already used by a sibling sliding or
    # legacy-interior door, and vice-versa.
    def self.na_collect_used_adr_numbers(model)
        bifold_dict_key   = Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::NA_DOOR_INFO_DICT
        bifold_id_key     = Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::NA_KEY_DOOR_ID
        sliding_dict_key  = "Na__SlidingDoorConfiguratorInfo".freeze
        legacy_dict_key   = "Na__DoorConfiguratorInfo".freeze
        double_dict_key   = "Na__ExteriorDoubleDoorConfiguratorInfo".freeze
        common_id_key     = "DoorID".freeze

        used = []
        model.definitions.each do |definition|
            definition.instances.each do |instance|
                bifold_id  = na_safe_get_attribute(instance, bifold_dict_key,  bifold_id_key)
                sliding_id = na_safe_get_attribute(instance, sliding_dict_key, common_id_key)
                legacy_id  = na_safe_get_attribute(instance, legacy_dict_key,  common_id_key)
                double_id  = na_safe_get_attribute(instance, double_dict_key,  common_id_key)

                used << na_extract_adr_number(bifold_id)  if bifold_id
                used << na_extract_adr_number(sliding_id) if sliding_id
                used << na_extract_adr_number(legacy_id)  if legacy_id
                used << na_extract_adr_number(double_id)  if double_id
            end
        end
        used.compact
    end
    private_class_method :na_collect_used_adr_numbers
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Read an Attribute Safely (nil On Missing Dict)
    # ------------------------------------------------------------
    def self.na_safe_get_attribute(instance, dict_key, attr_key)
        return nil unless instance.respond_to?(:get_attribute)
        instance.get_attribute(dict_key, attr_key)
    rescue StandardError
        nil
    end
    private_class_method :na_safe_get_attribute
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Extract Integer Number From an "ADR###" String
    # ------------------------------------------------------------
    def self.na_extract_adr_number(adr_string)
        return nil unless adr_string.is_a?(String)
        match = adr_string.match(/^ADR(\d{3})$/)
        match ? match[1].to_i : nil
    end
    private_class_method :na_extract_adr_number
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__AssemblyComposer
end # module Na__ExteriorMultiFoldingDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
