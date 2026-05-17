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
require_relative '../04__GeometryHelpers/Na__AssemblyStudio__GeometryHelpers__Box__'
require_relative 'Na__AssemblyStudio__ExtFold__GeometryHelpers__'
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
    RotationPivotBuilder = Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::Na__RotationPivotBuilder
    MovementPivotBuilder = Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::Na__MovementPivotBuilder

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

    NA_GLAZING_GROUP_NAME            = "Na__BifoldPanel__Glazing".freeze
    NA_RAIL_HEAD_GROUP_NAME          = "Na__BifoldPanel__HeadRail".freeze
    NA_RAIL_BASE_GROUP_NAME          = "Na__BifoldPanel__BaseRail".freeze
    NA_STILE_LEFT_GROUP_NAME         = "Na__BifoldPanel__StileLeft".freeze
    NA_STILE_RIGHT_GROUP_NAME        = "Na__BifoldPanel__StileRight".freeze
    NA_TRACK_HEAD_GROUP_NAME         = "Na__BifoldFrame__HeadTrack".freeze
    NA_TRACK_BASE_GROUP_NAME         = "Na__BifoldFrame__BaseTrack".freeze

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
    #
    # @param config_hash       [Hash]              full bifold config
    # @param panel_descriptors [Array<Hash>]       per-panel descriptors
    # @param parent_entities   [Sketchup::Entities] target entities
    # @return [Hash] { :mod_groups => [...], :rot_groups => [...], :mve_groups => [...] }
    def self.na_compose_adr(config_hash, panel_descriptors, parent_entities)
        return nil unless parent_entities
        return nil unless panel_descriptors.is_a?(Array)

        DebugTools.na_debug_method("ExtFold::AssemblyComposer.na_compose_adr (#{panel_descriptors.length} panels)")

        na_build_assembly_frame(config_hash, parent_entities)

        result = { :mod_groups => [], :rot_groups => [], :mve_groups => [] }
        rot_index = 1
        mve_index = 1

        panel_descriptors.each do |descriptor|
            mod_group = na_build_panel_mod_group(config_hash, descriptor, parent_entities)
            result[:mod_groups] << mod_group if mod_group

            rot_group = na_build_panel_rot_marker(config_hash, descriptor, parent_entities, rot_index)
            if rot_group
                result[:rot_groups] << rot_group
                rot_index += 1
            end

            if descriptor[:mve_axis] && descriptor[:mve_distance_mm].to_i != 0
                mve_group = na_build_panel_mve_marker(config_hash, descriptor, parent_entities, mve_index)
                if mve_group
                    result[:mve_groups] << mve_group
                    mve_index += 1
                end
            end
        end

        result
    rescue StandardError => e
        DebugTools.na_debug_error("ExtFold::AssemblyComposer.na_compose_adr failed", e)
        nil
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Frame (Head + Base Track)
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Build the Static Head + Base Track Geometry
    # ------------------------------------------------------------
    # Track casings span the full opening width and sit immediately
    # above (head) and below (base) the panel stack. They are static
    # geometry (no MOD wrapper) and stay at the ADR definition root.
    def self.na_build_assembly_frame(config_hash, parent_entities)
        opening_w_mm    = config_hash["bifold_door_opening_width_mm"].to_f
        opening_h_mm    = config_hash["bifold_door_opening_height_mm"].to_f
        floor_clearance = config_hash["bifold_door_floor_clearance_mm"].to_f
        panel_t_mm      = config_hash["bifold_door_panel_thickness_mm"].to_f
        head_rail_mm    = config_hash["bifold_door_head_rail_mm"].to_f
        base_rail_mm    = config_hash["bifold_door_base_rail_mm"].to_f

        track_y_mm      = GeometryHelpers.na_compute_track_y_origin_mm(panel_t_mm)
        track_d_mm      = GeometryHelpers.na_compute_track_depth_mm(panel_t_mm)

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
# REGION | Internal Helpers - Per-Panel MOD Group
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Build the MOD Group for a Single Panel
    # ------------------------------------------------------------
    # The MOD group is the moving part of the panel. Its NAME encodes
    # the open-state ROT (and optional MVE) transformation that
    # TrueVision3D's animation scanner parses at runtime. The geometry
    # inside is the panel's frame (rails + stiles) plus the glazing
    # pane (when `bifold_door_glazed == true`).
    def self.na_build_panel_mod_group(config_hash, descriptor, parent_entities)
        mod_name        = na_resolve_mod_name(descriptor)
        mod_group       = parent_entities.add_group
        mod_group.name  = mod_name
        mod_entities    = mod_group.entities

        floor_clearance = config_hash["bifold_door_floor_clearance_mm"].to_f
        panel_t_mm      = config_hash["bifold_door_panel_thickness_mm"].to_f
        head_rail_mm    = config_hash["bifold_door_head_rail_mm"].to_f
        base_rail_mm    = config_hash["bifold_door_base_rail_mm"].to_f
        stile_width_mm  = config_hash["bifold_door_stile_width_mm"].to_f
        is_glazed       = config_hash["bifold_door_glazed"] == true

        origin_x_mm     = descriptor[:origin_x_mm].to_f
        panel_w_mm      = descriptor[:width_mm].to_f
        panel_h_mm      = descriptor[:height_mm].to_f
        panel_y_mm      = GeometryHelpers.na_compute_panel_y_origin_mm(panel_t_mm)
        panel_z_mm      = floor_clearance

        na_build_panel_rails(mod_entities, origin_x_mm, panel_y_mm, panel_z_mm,
                             panel_w_mm, panel_h_mm, panel_t_mm,
                             head_rail_mm, base_rail_mm)
        na_build_panel_stiles(mod_entities, origin_x_mm, panel_y_mm, panel_z_mm,
                              panel_w_mm, panel_h_mm, panel_t_mm,
                              head_rail_mm, base_rail_mm, stile_width_mm)

        if is_glazed
            na_build_panel_glazing(mod_entities, origin_x_mm, panel_y_mm, panel_z_mm,
                                   panel_w_mm, panel_h_mm, panel_t_mm,
                                   head_rail_mm, base_rail_mm, stile_width_mm)
        end

        # NOTE | Handle placement is wired up in Phase-3.5 alongside the bifold
        # DataSerializer + SelectionCoordinator. Per-panel handle pseudo-config:
        # - Reuses Na__InteriorDoorSystem::Na__HandleBuilder3D as-is.
        # - Maps bifold_door_handle_asset_key -> Na__DoorConfig__HandleAssetKey.
        # - Maps panel_w_mm -> Na__DoorConfig__OpeningWidth_mm (lining = 0).
        # - Maps descriptor[:handle_side] -> Na__DoorConfig__SwingSide.
        # - Wraps the handles in a temporary group, translates by
        #   (origin_x_mm, panel_y_mm, 0), then explodes back into mod_entities.

        DebugTools.na_debug_geometry(
            "ExtFold MOD: #{mod_name} (panel #{descriptor[:index]}, w=#{panel_w_mm.round}mm, role=#{descriptor[:role]})"
        )
        mod_group
    end
    private_class_method :na_build_panel_mod_group
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

    # HELPER FUNCTION | Build the Top + Base Rails of a Bifold Panel
    # ------------------------------------------------------------
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
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Build the Left + Right Stiles of a Bifold Panel
    # ------------------------------------------------------------
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
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Build the Centred Glazing Pane Inside the Frame
    # ------------------------------------------------------------
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
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Per-Panel ROT + MVE Markers
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Build the ROT Marker for a Single Panel
    # ------------------------------------------------------------
    def self.na_build_panel_rot_marker(config_hash, descriptor, parent_entities, rot_index)
        floor_clearance = config_hash["bifold_door_floor_clearance_mm"].to_f
        panel_h_mm      = descriptor[:height_mm].to_f
        rotation_deg    = descriptor[:rot_degrees].to_i

        origin_in       = Geom::Point3d.new(
            GeometryHelpers.na_mm_to_inch(descriptor[:hinge_x_mm].to_f),
            GeometryHelpers.na_mm_to_inch(descriptor[:hinge_y_mm].to_f),
            GeometryHelpers.na_mm_to_inch(floor_clearance)
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
    def self.na_build_panel_mve_marker(config_hash, descriptor, parent_entities, mve_index)
        floor_clearance = config_hash["bifold_door_floor_clearance_mm"].to_f
        panel_h_mm      = descriptor[:height_mm].to_f
        mve_axis        = descriptor[:mve_axis]
        mve_distance_mm = descriptor[:mve_distance_mm].to_i

        marker_z_mm     = floor_clearance + panel_h_mm                          # <-- MVE marker at panel TOP (head-track height)
        origin_in       = Geom::Point3d.new(
            GeometryHelpers.na_mm_to_inch(descriptor[:hinge_x_mm].to_f),
            GeometryHelpers.na_mm_to_inch(descriptor[:hinge_y_mm].to_f),
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
    # primitive so callers stay in mm units.
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
        common_id_key     = "DoorID".freeze

        used = []
        model.definitions.each do |definition|
            definition.instances.each do |instance|
                bifold_id  = na_safe_get_attribute(instance, bifold_dict_key,  bifold_id_key)
                sliding_id = na_safe_get_attribute(instance, sliding_dict_key, common_id_key)
                legacy_id  = na_safe_get_attribute(instance, legacy_dict_key,  common_id_key)

                used << na_extract_adr_number(bifold_id)  if bifold_id
                used << na_extract_adr_number(sliding_id) if sliding_id
                used << na_extract_adr_number(legacy_id)  if legacy_id
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
