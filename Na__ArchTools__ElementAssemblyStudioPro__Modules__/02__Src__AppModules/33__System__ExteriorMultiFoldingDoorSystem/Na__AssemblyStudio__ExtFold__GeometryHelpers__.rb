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

end # module Na__GeometryHelpers
end # module Na__ExteriorMultiFoldingDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
