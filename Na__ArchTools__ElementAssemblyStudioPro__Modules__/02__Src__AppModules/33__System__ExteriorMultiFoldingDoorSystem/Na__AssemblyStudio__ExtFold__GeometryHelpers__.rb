# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - BIFOLD DOOR GEOMETRY HELPERS
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtFold__GeometryHelpers__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem
# MODULE     : Na__GeometryHelpers
# AUTHOR     : Noble Architecture
# PURPOSE    : Bifold-door specific geometry helpers (per-panel width
#              division, per-panel rail/stile maths, panel-front-face
#              Y-origin, mm->inch unit conversion). Generic box geometry
#              continues to live in shared AppCore
#              `04__GeometryHelpers/Na__AssemblyStudio__GeometryHelpers__Box__.rb`.
# CREATED    : 17-May-2026
#
# DESCRIPTION:
# - Pure functions only - no SketchUp side effects.
# - All inputs millimetres, outputs are either millimetres (when computing
#   layout positions) or SketchUp inches (when feeding the shared Box
#   primitive). The `na_mm_to_inch` helper is the only conversion path.
# - Layout-level maths (panel pivot positions, MVE travel distances)
#   lives in the per-Layout module under
#   `Na__AssemblyStudio__ExtFold__Layout__*__.rb`.
#
# COORDINATE SYSTEM (ADR-local, mirrors WindowSystem opening-local):
# - Origin       = bottom-front-left corner of the structural opening.
# - X+           = along the wall (left -> right across opening).
# - Y+           = through the wall depth (front face at Y=0).
# - Z+           = upwards.
#
# DEVELOPMENT LOG:
# 17-May-2026 - Version 1.7.2
# - Added accordion-fold helpers `na_compute_panel_rot_degrees` and
#   `na_compute_slave_mve_distance_mm`. Layout modules now route every
#   master + slave through these helpers so the TrueVision animation
#   stops at perpendicular (with a small termination tilt) and the
#   slaves end up offset by panel_thickness + small gap from the
#   master, instead of all collapsing onto the master's hinge.
#
# 17-May-2026 - Version 0.2.0
# - Phase-3a implementation: full per-panel maths surface.
#
# 17-May-2026 - Version 0.1.0
# - Phase-1 scaffold (na_compute_panel_width_mm placeholder).
#
# =============================================================================

require 'sketchup.rb'

module Na__AssemblyStudio
module Na__ExteriorMultiFoldingDoorSystem
module Na__GeometryHelpers

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

    NA_MM_TO_INCH                       = 1.0 / 25.4                            # <-- Single mm -> inch factor
    NA_INNER_GLAZING_DEPTH_RATIO        = 0.4                                   # <-- Glazing depth as fraction of panel thickness
    NA_TRACK_DEPTH_PADDING_MM           = 30                                    # <-- Track casing wider than panel thickness

    # Accordion-fold tuning (V1.7.2). The bifold open-state is a
    # compressed-accordion stack where every panel ends up perpendicular
    # to the wall, offset from its neighbour by the panel thickness + a
    # small visible gap, and tilted by a small termination angle so the
    # stack reads as an accordion rather than a flat deck of cards.
    NA_ACCORDION_BASE_ROT_DEG           = 90.0                                  # <-- Magnitude of the perpendicular swing
    NA_ACCORDION_TERMINATION_ANGLE_DEG  = 2.0                                   # <-- Small zigzag tilt either side of perpendicular
    NA_ACCORDION_PANEL_GAP_MM           = 10.0                                  # <-- Visible gap between adjacent stacked panels

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Unit Conversion
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Convert Millimetres to SketchUp Inches
    # ------------------------------------------------------------
    def self.na_mm_to_inch(value_mm)
        value_mm.to_f * NA_MM_TO_INCH
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Per-Panel Dimension Maths
# -----------------------------------------------------------------------------

    # FUNCTION | Resolve Per-Panel Width Given Opening + Panel Count
    # ------------------------------------------------------------
    # Equal-width division for layouts where every panel is the same
    # size (EqualEqual, AllOneWay). MasterSlaves overrides this for
    # the master leaf via `na_compute_master_panel_width_mm`.
    #
    # @param opening_width_mm [Numeric] Total clear opening width
    # @param panel_count      [Integer] Number of panels (>= 1)
    # @return [Float] Per-panel width in mm (0.0 if panel_count <= 0)
    def self.na_compute_panel_width_mm(opening_width_mm, panel_count)
        n = panel_count.to_i
        return 0.0 if n <= 0
        opening_width_mm.to_f / n
    end
    # ---------------------------------------------------------------

    # FUNCTION | Resolve Per-Panel Height (Opening Height Minus Floor Clearance)
    # ------------------------------------------------------------
    # All bifold panels share a single height equal to the opening
    # height minus the floor clearance gap at the bottom. The head
    # track sits in the head_rail thickness above the panels and is
    # rendered separately by AssemblyComposer.
    #
    # @param opening_height_mm   [Numeric] Clear opening height
    # @param floor_clearance_mm  [Numeric] Bottom gap to slab
    # @return [Float] Panel height in mm
    def self.na_compute_panel_height_mm(opening_height_mm, floor_clearance_mm)
        h = opening_height_mm.to_f - floor_clearance_mm.to_f
        h < 0.0 ? 0.0 : h
    end
    # ---------------------------------------------------------------

    # FUNCTION | Resolve Door Opening Frame Dimensions From Window-Level Keys (Phase 9)
    # ------------------------------------------------------------
    # Bifold + sliding doors now share the WindowSystem's Dimensions /
    # Cill & Frame controls. This helper centralises the lookup so
    # Layout modules and the AssemblyComposer agree on a single set of
    # numbers. Reads `width_mm`, `height_mm`, `frame_thickness_mm`,
    # the four advanced per-edge thicknesses (when
    # `advanced_frame_controls == true`), `frame_depth_mm`,
    # `frame_wall_inset_mm`. Returns mm values + the inner clear box.
    #
    # @param config_hash [Hash] Live windowConfiguration
    # @return [Hash] {
    #   :width_mm, :height_mm,
    #   :frame_top_mm, :frame_bottom_mm, :frame_left_mm, :frame_right_mm,
    #   :frame_depth_mm, :frame_wall_inset_mm,
    #   :inner_w_mm, :inner_h_mm
    # }
    def self.na_resolve_door_opening_dimensions(config_hash)
        width_mm     = (config_hash["width_mm"]  || 3600).to_f
        width_mm     = 0.0 if width_mm < 0.0
        height_mm    = (config_hash["height_mm"] || 2100).to_f
        height_mm    = 0.0 if height_mm < 0.0

        advanced     = (config_hash["advanced_frame_controls"] == true)
        uniform_mm   = (config_hash["frame_thickness_mm"] || 50).to_f
        uniform_mm   = 0.0 if uniform_mm < 0.0

        resolve_edge = lambda do |edge_key|
            raw = advanced ? config_hash[edge_key] : uniform_mm
            v   = (raw.nil? ? uniform_mm : raw.to_f)
            v < 0.0 ? 0.0 : v
        end

        frame_top    = resolve_edge.call("frame_top_thickness_mm")
        frame_bottom = resolve_edge.call("frame_bottom_thickness_mm")
        frame_left   = resolve_edge.call("frame_left_thickness_mm")
        frame_right  = resolve_edge.call("frame_right_thickness_mm")

        frame_depth      = (config_hash["frame_depth_mm"]      || 70).to_f
        frame_depth      = 1.0 if frame_depth <= 0.0
        frame_wall_inset = (config_hash["frame_wall_inset_mm"] || 0).to_f

        inner_w = width_mm  - frame_left - frame_right
        inner_h = height_mm - frame_top  - frame_bottom
        inner_w = 0.0 if inner_w < 0.0
        inner_h = 0.0 if inner_h < 0.0

        {
            :width_mm            => width_mm,
            :height_mm           => height_mm,
            :frame_top_mm        => frame_top,
            :frame_bottom_mm     => frame_bottom,
            :frame_left_mm       => frame_left,
            :frame_right_mm      => frame_right,
            :frame_depth_mm      => frame_depth,
            :frame_wall_inset_mm => frame_wall_inset,
            :inner_w_mm          => inner_w,
            :inner_h_mm          => inner_h
        }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Resolve Panel Y-Origin Centred Inside the Frame Depth (Phase 9)
    # ------------------------------------------------------------
    # The Phase-9 frame change replaces the head/base tracks with the
    # WindowSystem's per-edge frame. Panels now sit centred along Y
    # inside the frame depth so they read as proper bifold leaves
    # hanging in the door reveal rather than projecting forward of the
    # wall plane.
    def self.na_compute_panel_y_origin_in_frame_mm(panel_thickness_mm, frame_depth_mm, frame_wall_inset_mm)
        panel_t = panel_thickness_mm.to_f
        depth   = frame_depth_mm.to_f
        depth   = panel_t if depth < panel_t
        frame_wall_inset_mm.to_f + ((depth - panel_t) / 2.0)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Resolve Glazing Pane Inner Box (mm) Inside a Panel Frame
    # ------------------------------------------------------------
    # Returns the inner glazing rectangle bounded by the panel rails
    # (head + base) and stiles (left + right). Origin is panel-local
    # (panel bottom-left corner = 0, 0).
    #
    # @param panel_w_mm     [Numeric] Per-panel width
    # @param panel_h_mm     [Numeric] Per-panel height
    # @param head_rail_mm   [Numeric] Top rail height
    # @param base_rail_mm   [Numeric] Base rail height
    # @param stile_width_mm [Numeric] Stile width (same on both sides)
    # @return [Hash] { :x => mm, :z => mm, :width => mm, :height => mm } or nil if degenerate
    def self.na_compute_glazing_box_mm(panel_w_mm, panel_h_mm, head_rail_mm, base_rail_mm, stile_width_mm)
        inner_w = panel_w_mm.to_f - 2.0 * stile_width_mm.to_f
        inner_h = panel_h_mm.to_f - head_rail_mm.to_f - base_rail_mm.to_f
        return nil if inner_w <= 0.0 || inner_h <= 0.0
        {
            :x      => stile_width_mm.to_f,
            :z      => base_rail_mm.to_f,
            :width  => inner_w,
            :height => inner_h
        }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Resolve Glazing Depth (Y-Extent) for a Panel
    # ------------------------------------------------------------
    # Glazing sits centred in the panel thickness with a thin pane
    # depth (default 40% of panel thickness) so it visually reads as
    # a glass pane rather than a solid slab.
    def self.na_compute_glazing_depth_mm(panel_thickness_mm)
        d = panel_thickness_mm.to_f * NA_INNER_GLAZING_DEPTH_RATIO
        d < 1.0 ? 1.0 : d
    end
    # ---------------------------------------------------------------

    # FUNCTION | Resolve Glazing Y-Origin (Centred In Panel Thickness)
    # ------------------------------------------------------------
    def self.na_compute_glazing_y_origin_mm(panel_thickness_mm)
        d = na_compute_glazing_depth_mm(panel_thickness_mm)
        (panel_thickness_mm.to_f - d) / 2.0
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Track + Frame Maths
# -----------------------------------------------------------------------------

    # FUNCTION | Resolve Head-Track Depth In Y (Panel Thickness + Padding)
    # ------------------------------------------------------------
    # The head track casing is slightly wider than the panel thickness
    # so the panels can swing/translate through it without geometry
    # collisions in the closed/open states.
    def self.na_compute_track_depth_mm(panel_thickness_mm)
        panel_thickness_mm.to_f + NA_TRACK_DEPTH_PADDING_MM
    end
    # ---------------------------------------------------------------

    # FUNCTION | Resolve Head-Track Y-Origin
    # ------------------------------------------------------------
    # Track is centred on the panel thickness so panels can hang
    # from it without any visible offset on either side.
    def self.na_compute_track_y_origin_mm(panel_thickness_mm)
        d = na_compute_track_depth_mm(panel_thickness_mm)
        -(d - panel_thickness_mm.to_f) / 2.0
    end
    # ---------------------------------------------------------------

    # FUNCTION | Resolve Panel Front-Face Y-Origin Inside Wall
    # ------------------------------------------------------------
    # Bifold panels sit at Y=0 by default (front face flush with the
    # outer wall plane). Override per-instance in Layout modules if
    # a setback is required (e.g. recessed master leaf).
    def self.na_compute_panel_y_origin_mm(_panel_thickness_mm)
        0.0
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Accordion-Fold Math (V1.7.2)
# -----------------------------------------------------------------------------
#
# The bifold OPEN state is a compressed-accordion stack: every panel
# rotates to (almost) perpendicular to the wall and is X-offset from
# its master by `slave_pos * (panel_thickness + gap)` so the panels
# end up sitting next to each other rather than all collapsing onto
# the master's hinge. Adjacent panels alternate the rotation sign by
# a small `termination_angle` so the stack reads as a true zigzag
# concertina rather than a flat deck of cards.
#
# All three layouts (EqualEqual, AllOneWay, MasterSlaves) call into
# the helpers below so the contract stays in lockstep across modes.
# Pre-V1.7.2 the slaves rotated 180 deg + slid a full panel-width,
# which made every slave land in the same world position and (for
# right-jamb masters) sometimes swung INTO the wall plane.

    # FUNCTION | Resolve the Open-State Rotation (Degrees) for a Cascade Panel
    # ------------------------------------------------------------
    # `slave_pos` is 0 for the cascade master (or a "lone" master that
    # opens like a single hinged door) and 1, 2, ... for each successive
    # slave away from the master.
    #
    # `cascade_direction` is :left when the cascade ends at the LEFT
    # jamb and :right when it ends at the RIGHT jamb. The base swing
    # magnitude is fixed at +/- 90 deg; only the termination tilt is
    # alternated.
    #
    # @return [Integer] open-state rotation in degrees, signed.
    def self.na_compute_panel_rot_degrees(slave_pos, cascade_direction, accordion_angle_deg = NA_ACCORDION_TERMINATION_ANGLE_DEG)
        base_deg       = (cascade_direction == :left) ? -NA_ACCORDION_BASE_ROT_DEG : +NA_ACCORDION_BASE_ROT_DEG
        direction_sign = (cascade_direction == :left) ? +1.0 : -1.0
        parity_sign    = slave_pos.to_i.even? ? +1.0 : -1.0
        tilt           = parity_sign * direction_sign * accordion_angle_deg.to_f
        (base_deg + tilt).round.to_i
    end
    # ---------------------------------------------------------------

    # FUNCTION | Resolve the Slave's X-Track Translation Distance (Signed mm)
    # ------------------------------------------------------------
    # The cascade master stays anchored at its jamb (no MVE). Slave k
    # translates along the wall axis by `k * (panel_w - panel_t - gap)`
    # so that, after rotating to perpendicular, its hinge lands
    # `k * (panel_t + gap)` from the master's hinge - leaving exactly
    # `gap` mm of clear air between adjacent stacked panels.
    #
    # The sign is negative for :left cascades (panels travel back to
    # the LEFT jamb) and positive for :right cascades.
    #
    # @return [Integer] signed mm-magnitude (0 for the master).
    def self.na_compute_slave_mve_distance_mm(slave_pos, cascade_direction, panel_w_mm, panel_thickness_mm, gap_mm = NA_ACCORDION_PANEL_GAP_MM)
        k = slave_pos.to_i
        return 0 if k == 0
        direction_sign = (cascade_direction == :left) ? -1.0 : +1.0
        magnitude      = k * (panel_w_mm.to_f - panel_thickness_mm.to_f - gap_mm.to_f)
        (direction_sign * magnitude).round.to_i
    end
    # ---------------------------------------------------------------

    # FUNCTION | Resolve the Effective Panel Thickness in mm From Config
    # ------------------------------------------------------------
    # Layouts read panel_thickness from the bifold config so the slave
    # MVE distance matches the geometry the AssemblyComposer will draw.
    # Defaults match the bifold default-config thickness.
    def self.na_resolve_panel_thickness_mm(config_hash, default_mm = 50.0)
        raw = config_hash["bifold_door_panel_thickness_mm"] if config_hash.is_a?(Hash)
        v   = raw.nil? ? default_mm : raw.to_f
        v   = default_mm if v <= 0.0
        v
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__GeometryHelpers
end # module Na__ExteriorMultiFoldingDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
