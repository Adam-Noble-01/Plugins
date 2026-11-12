# frozen_string_literal: true

# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - MCP OPERATIONS - VALIDATION (THE DIALOG'S RULES)
# =============================================================================
#
# FILE       : Na__AssemblyStudio__McpOperations__Validation__.rb
# NAMESPACE  : Na__AssemblyStudio
# MODULE     : Na__McpOperations
# AUTHOR     : Noble Architecture
# CREATED    : 11-Nov-2026 (V2.6.0)
# PURPOSE    : The checks the dialog makes before it lets a window or exterior
#              door be built, so an agent is refused with the very message
#              Adam would see.
#
# TWIN OF
#   05__Viewport__2dPreviewEngine/Na__AssemblyStudio__Viewport__Validation__.js
#     na_validateConfig            -> na_validate_window          (L70)
#     na_validateDoubleDoorConfig  -> na_validate_double_door     (L204)
#     na_validateSingleDoorConfig  -> na_validate_single_door     (L259)
#     na_validateBifoldConfig      -> na_validate_bifold_door     (L306)
#     na_validateSlidingConfig     -> na_validate_sliding_door    (L346)
#   The narrowest light uses the Ruby twin of Na__MullionMath that the
#   geometry itself uses (GeometryBuilders na_compute_mullion_layout).
#   JS falsy fallbacks ('x || 65') are kept with na_js_or. Change a rule in
#   the JS file, change it here, in the same commit.
#
# NOT MIRRORED (the build itself is checked instead)
#   - Per Casement Settings (na_validateCasementOverrides, needs CasementMath)
#   - The exterior doors' field layout check (LeafConfigResolver na_validate)
#   Interior doors and cabinets have no dialog-level rule: their controls'
#   ranges are checked in Catalogue, and the cabinet LayoutResolver clamps.
#
# =============================================================================

module Na__AssemblyStudio
module Na__McpOperations

# -----------------------------------------------------------------------------
# REGION | Validation - Dispatch
# -----------------------------------------------------------------------------

    # FUNCTION | The Dialog's Error Messages for a Full Config (Empty = Valid)
    # ------------------------------------------------------------
    def self.na_validation_errors(system, product_key, values)
        return [] unless system == 'window_family'

        case product_key
        when 'double'  then na_validate_double_door(values)
        when 'single'  then na_validate_single_door(values)
        when 'bifold'  then na_validate_bifold_door(values)
        when 'sliding' then na_validate_sliding_door(values)
        else                na_validate_window(values)
        end
    end
    private_class_method :na_validation_errors
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Validation - Windows
# -----------------------------------------------------------------------------

    def self.na_validate_window(c)
        errors = []
        width              = na_js_or(c['width_mm'], 0).to_f
        height             = na_js_or(c['height_mm'], 0).to_f
        frame              = na_frame_sides(c)
        casement_width     = na_js_or(c['casement_width_mm'], 65).to_f
        show_casements     = c['show_casements'] != false
        sash               = c['sliding_sash_window'] == true
        per_opening        = na_js_or(c['casements_per_opening'], 1).to_i.clamp(1, 6)
        mullions           = na_js_or(c['mullions'], 0).to_i
        mullion_width      = na_js_or(c['mullion_width_mm'], 40).to_f
        transoms           = na_js_or(c['transoms'], 0).to_f.round.clamp(0, 3)
        transom_width      = na_js_or(c['transom_width_mm'], 40).to_f
        individual         = c['casement_sizes_individual'] == true
        top_rail           = individual ? na_js_or(c['casement_top_rail_mm'], casement_width).to_f : casement_width
        bottom_rail        = individual ? na_js_or(c['casement_bottom_rail_mm'], casement_width).to_f : casement_width
        top_sash_bottom    = na_js_or(c['top_sash_bottom_rail_mm'], bottom_rail).to_f
        bottom_sash_top    = c['bottom_sash_top_rail_override'] == true ? na_js_or(c['bottom_sash_top_rail_mm'], top_rail).to_f : top_rail
        left_stile         = individual ? na_js_or(c['casement_left_stile_mm'], casement_width).to_f : casement_width
        right_stile        = individual ? na_js_or(c['casement_right_stile_mm'], casement_width).to_f : casement_width

        errors << 'Width must be at least 200mm' if width < 200
        errors << 'Height must be at least 200mm' if height < 200

        frameless    = frame.values.all?(&:zero?)
        inner_width  = width - frame[:left] - frame[:right]
        inner_height = height - frame[:top] - frame[:bottom]
        narrowest    = na_narrowest_light_mm(c, frame[:left], inner_width, mullions, mullion_width)
        min_casement = show_casements ? left_stile + right_stile + 50 : 50
        if narrowest / per_opening < min_casement
            errors << (mullions.positive? ? 'Opening too narrow - adjust mullion offsets, reduce mullions or increase width' : 'Opening too narrow - reduce mullions or increase width')
        end

        min_single_sash  = [top_rail + top_sash_bottom, bottom_sash_top + bottom_rail].max + 50
        min_inner_height = show_casements ? (sash ? min_single_sash * 2 : min_single_sash) : 50
        if inner_height < min_inner_height
            errors << if sash && show_casements
                          frameless ? 'Window too short for sliding sash casements' : 'Window too short for frame and sliding sash casements'
                      else
                          frameless ? 'Window too short for casement' : 'Window too short for frame and casement'
                      end
        end

        required = transoms * transom_width + (transoms + 1) * min_inner_height
        errors << 'Window too short for the requested transom layout' if transoms.positive? && inner_height < required
        errors
    end
    private_class_method :na_validate_window
    # ---------------------------------------------------------------

    # HELPER FUNCTION | The Narrowest Light (Per-Mullion Offsets Included), mm
    # ------------------------------------------------------------
    def self.na_narrowest_light_mm(c, inner_left_mm, inner_width_mm, mullions, mullion_width_mm)
        builders = Na__AssemblyStudio::Na__WindowSystem::Na__GeometryBuilders
        offsets  = builders.na_collect_mullion_offsets(c, mullions, 1.mm)
        layout   = builders.na_compute_mullion_layout(inner_left_mm.mm, inner_width_mm.mm, mullions, mullion_width_mm.mm, offsets)
        layout[:openings].map { |row| row[:width] }.min.to_f.to_mm
    rescue StandardError
        (inner_width_mm - mullions * mullion_width_mm) / (mullions + 1)
    end
    private_class_method :na_narrowest_light_mm
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Validation - Exterior Doors
# -----------------------------------------------------------------------------

    def self.na_validate_double_door(c)
        errors   = []
        width    = na_js_or(c['width_mm'], 0).to_f
        height   = na_js_or(c['height_mm'], 0).to_f
        frame    = na_frame_sides(c)
        inner_w  = width - frame[:left] - frame[:right]
        inner_h  = height - frame[:top] - frame[:bottom]
        raw      = c['double_door_active_leaf_width_mm']
        active   = raw.is_a?(Numeric) ? raw.to_f : Float(raw.to_s, exception: false)
        active   = inner_w / 2.0 if active.nil? || !active.finite?
        passive  = inner_w - active

        errors << 'Double-door opening width must be at least 800mm' if width < 800
        errors << 'Double-door opening height must be at least 1500mm' if height < 1500
        if inner_w <= 0 || inner_h <= 0
            errors << 'Double-door frame thickness leaves no clear opening'
        else
            errors << 'Active double-door leaf must be at least 300mm wide' if active < 300
            errors << 'Passive double-door leaf must be at least 300mm wide' if passive < 300
        end
        errors << 'Left leaf opening angle must be between 0 and 180 degrees' unless na_angle_ok?(c['double_door_left_opening_angle_deg'])
        errors << 'Right leaf opening angle must be between 0 and 180 degrees' unless na_angle_ok?(c['double_door_right_opening_angle_deg'])
        left_projection  = na_js_or(c['double_door_left_hinge_projection_mm'], 0).to_f
        right_projection = na_js_or(c['double_door_right_hinge_projection_mm'], 0).to_f
        unless left_projection.between?(0, 150) && right_projection.between?(0, 150)
            errors << 'Parliament hinge projection must be between 0 and 150mm'
        end
        errors
    end
    private_class_method :na_validate_double_door
    # ---------------------------------------------------------------

    def self.na_validate_single_door(c)
        errors  = []
        width   = na_js_or(c['width_mm'], 0).to_f
        height  = na_js_or(c['height_mm'], 0).to_f
        frame   = na_frame_sides(c)
        inner_w = width - frame[:left] - frame[:right]
        inner_h = height - frame[:top] - frame[:bottom]

        errors << 'Single-door opening width must be at least 400mm' if width < 400
        errors << 'Single-door opening height must be at least 1200mm' if height < 1200
        if inner_w <= 0 || inner_h <= 0
            errors << 'Single-door frame thickness leaves no clear opening'
        elsif inner_w < 300
            errors << 'Single-door leaf must be at least 300mm wide'
        end
        errors << 'Opening angle must be between 0 and 180 degrees' unless na_angle_ok?(c['single_door_opening_angle_deg'])
        projection = na_js_or(c['single_door_hinge_projection_mm'], 0).to_f
        errors << 'Parliament hinge projection must be between 0 and 150mm' unless projection.between?(0, 150)
        errors
    end
    private_class_method :na_validate_single_door
    # ---------------------------------------------------------------

    def self.na_validate_bifold_door(c)
        errors  = []
        width   = na_js_or(c['width_mm'], na_js_or(c['bifold_door_opening_width_mm'], 0)).to_f
        height  = na_js_or(c['height_mm'], na_js_or(c['bifold_door_opening_height_mm'], 0)).to_f
        panels  = na_js_or(Float(c['bifold_door_panel_count'].to_s, exception: false), 0).to_f.round
        stile   = [40.0, na_js_or(c['bifold_door_stile_width_mm'], 95).to_f].max
        head    = [40.0, na_js_or(c['bifold_door_head_rail_mm'], 95).to_f].max
        base    = [40.0, na_js_or(c['bifold_door_base_rail_mm'], 200).to_f].max
        frame   = na_frame_sides(c)

        errors << 'Bifold opening width must be at least 800mm' if width < 800
        errors << 'Bifold opening height must be at least 1500mm' if height < 1500
        errors << 'Bifold panel count must be between 2 and 8' if panels < 2 || panels > 8

        inner_w = width - frame[:left] - frame[:right]
        inner_h = height - frame[:top] - frame[:bottom]
        if inner_w <= 0 || inner_h <= 0
            errors << 'Bifold frame thickness leaves no room for panels - reduce frame edges'
        elsif panels >= 2
            errors << 'Bifold panels too narrow - reduce panel count, stile width or frame edges' if inner_w / panels < 2 * stile + 50
            errors << 'Bifold opening too short for head + base rails - reduce rail size or frame edges' if inner_h < head + base + 50
        end
        errors
    end
    private_class_method :na_validate_bifold_door
    # ---------------------------------------------------------------

    def self.na_validate_sliding_door(c)
        errors  = []
        width   = na_js_or(c['width_mm'], na_js_or(c['sliding_door_opening_width_mm'], 0)).to_f
        height  = na_js_or(c['height_mm'], na_js_or(c['sliding_door_opening_height_mm'], 0)).to_f
        setback = na_js_or(Float(c['sliding_door_rear_setback_mm'].to_s, exception: false), 0).to_f
        stile   = [40.0, na_js_or(c['sliding_door_stile_width_mm'], 95).to_f].max
        head    = [40.0, na_js_or(c['sliding_door_head_rail_mm'], 95).to_f].max
        base    = [40.0, na_js_or(c['sliding_door_base_rail_mm'], 200).to_f].max
        panels  = na_js_or(Float(c['sliding_door_panel_count'].to_s, exception: false), 2).to_f.round.clamp(2, 3)
        frame   = na_frame_sides(c)

        errors << 'Sliding opening width must be at least 800mm' if width < 800
        errors << 'Sliding opening height must be at least 1500mm' if height < 1500
        errors << 'Sliding rear setback must be at least 20mm' if setback < 20

        inner_w = width - frame[:left] - frame[:right]
        inner_h = height - frame[:top] - frame[:bottom]
        if inner_w <= 0 || inner_h <= 0
            errors << 'Sliding frame thickness leaves no room for leaves - reduce frame edges'
        else
            errors << 'Sliding leaves too narrow - reduce stile width or frame edges' if inner_w / panels < 2 * stile + 50
            errors << 'Sliding opening too short for head + base rails - reduce rail size or frame edges' if inner_h < head + base + 50
        end
        errors
    end
    private_class_method :na_validate_sliding_door
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Validation - Helpers
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | The Four Frame Sides (na_getEffectiveFrameThicknesses)
    # ------------------------------------------------------------
    def self.na_frame_sides(c)
        uniform  = c['frame_thickness_mm'].nil? ? 50.0 : c['frame_thickness_mm'].to_f
        advanced = c['advanced_frame_controls'] == true
        side = lambda do |key|
            raw = advanced ? c[key] : uniform
            [0.0, (raw.nil? ? uniform : raw).to_f].max
        end
        {
            top:    side.call('frame_top_thickness_mm'),
            bottom: side.call('frame_bottom_thickness_mm'),
            left:   side.call('frame_left_thickness_mm'),
            right:  side.call('frame_right_thickness_mm')
        }
    end
    private_class_method :na_frame_sides
    # ---------------------------------------------------------------

    # HELPER FUNCTION | JavaScript's 'value || fallback'
    # ------------------------------------------------------------
    # 0, '', nil, false and NaN all fall back, as they do in the dialog.
    def self.na_js_or(value, fallback)
        falsy = value.nil? || value == false || value == '' ||
                (value.is_a?(Numeric) && (value.zero? || (value.is_a?(Float) && value.nan?)))
        falsy ? fallback : value
    end
    private_class_method :na_js_or
    # ---------------------------------------------------------------

    def self.na_angle_ok?(raw)
        angle = raw.is_a?(Numeric) ? raw.to_f : Float(raw.to_s, exception: false)
        !angle.nil? && angle.finite? && angle.between?(0, 180)
    end
    private_class_method :na_angle_ok?

# endregion -------------------------------------------------------------------

end # module Na__McpOperations
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
