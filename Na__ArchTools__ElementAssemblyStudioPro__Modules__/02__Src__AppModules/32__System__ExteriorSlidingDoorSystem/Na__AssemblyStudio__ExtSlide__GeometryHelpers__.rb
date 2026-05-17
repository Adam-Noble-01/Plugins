# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - SLIDING DOOR GEOMETRY HELPERS
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtSlide__GeometryHelpers__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::Na__GeometryHelpers
# AUTHOR     : Noble Architecture
# PURPOSE    : Sliding-door specific geometry helpers. Computes per-leaf
#              width (2-panel sliding door), MVE travel distance, rear
#              panel Y-setback origin, head/base track depth and panel
#              Y-origin from the snake_case bifold-parallel config keys.
# CREATED    : 17-May-2026
#
# DESCRIPTION:
# - All inputs and outputs are in millimetres.
# - Inch conversion goes through `na_mm_to_inch` so SketchUp callers
#   never reimplement the factor (1 inch = 25.4 mm).
# - Track depth defaults to panel thickness * 1.6 so the head + base
#   tracks visually wrap both leaves (front + setback rear).
# - Glazing depth = 60 % of leaf thickness, centred on the panel face.
#
# COORDINATE SYSTEM (door-local):
# - Origin       = bottom-front-left corner of the structural opening.
# - X+           = along the wall (left -> right across opening).
# - Y+           = through the wall depth (front face at Y=0).
# - Z+           = upwards.
#
# DEVELOPMENT LOG:
# 17-May-2026 - Version 0.2.0
# - Phase-3b implementation: full helper surface mirrors bifold helpers.
#
# 17-May-2026 - Version 0.1.0
# - Phase-1 scaffold (placeholder helpers).
#
# =============================================================================

require 'sketchup.rb'

module Na__AssemblyStudio
module Na__ExteriorSlidingDoorSystem
module Na__GeometryHelpers

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

    NA_INCHES_PER_MM                = 1.0 / 25.4                                       # <-- Inch conversion factor
    NA_TRACK_DEPTH_MULTIPLIER       = 1.6                                              # <-- Track depth = panel_t * 1.6
    NA_GLAZING_DEPTH_RATIO          = 0.6                                              # <-- Glazing pane = 60 % of leaf thickness
    NA_LEAF_OVERLAP_DEFAULT_MM      = 20                                               # <-- Default leaf-to-leaf overlap when sliding closed

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Unit Conversion
# -----------------------------------------------------------------------------

    # FUNCTION | Convert Millimetres to SketchUp Inches
    # ------------------------------------------------------------
    def self.na_mm_to_inch(mm)
        mm.to_f * NA_INCHES_PER_MM
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Per-Leaf Geometry
# -----------------------------------------------------------------------------

    # FUNCTION | Compute the Per-Leaf Width for a Two-Panel Sliding Door
    # ------------------------------------------------------------
    # Each leaf occupies half the opening width (no rebate / overlap
    # built into the leaf — overlap is realised by the front leaf
    # being set in front of the rear leaf at Y=0 and Y=setback).
    def self.na_compute_leaf_width_mm(opening_width_mm)
        opening_width_mm.to_f / 2.0
    end
    # ---------------------------------------------------------------

    # FUNCTION | Compute the Per-Leaf Open Height
    # ------------------------------------------------------------
    # Subtracts the floor clearance from the clear opening height so
    # the leaf sits flush against the head track.
    def self.na_compute_leaf_height_mm(opening_height_mm, floor_clearance_mm)
        opening_height_mm.to_f - floor_clearance_mm.to_f
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - MVE Travel
# -----------------------------------------------------------------------------

    # FUNCTION | Compute the MVE Travel Distance for the Moving Leaf
    # ------------------------------------------------------------
    # When the leaf slides open it parks behind the fixed leaf with a
    # small visible overlap. Travel = leaf_width - overlap.
    # Caller signs the result based on the slide mode (negative for
    # FrontSlidesLeft, positive for FrontSlidesRight).
    def self.na_compute_slide_travel_mm(leaf_width_mm, overlap_mm = NA_LEAF_OVERLAP_DEFAULT_MM)
        travel = leaf_width_mm.to_f - overlap_mm.to_f
        travel < 0.0 ? 0.0 : travel
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Y Origins (Front + Rear Leaf, Track)
# -----------------------------------------------------------------------------

    # FUNCTION | Front Leaf Y-Origin (Always at Y=0)
    # ------------------------------------------------------------
    def self.na_compute_front_panel_y_origin_mm
        0.0
    end
    # ---------------------------------------------------------------

    # FUNCTION | Rear Leaf Y-Origin (Setback Depth)
    # ------------------------------------------------------------
    # Rear leaf is set back by the configured setback distance so the
    # two leaves run on parallel tracks rather than colliding.
    def self.na_compute_rear_panel_y_origin_mm(rear_setback_mm)
        rear_setback_mm.to_f
    end
    # ---------------------------------------------------------------

    # FUNCTION | Track Y-Origin (Spans Both Leaves)
    # ------------------------------------------------------------
    # The head and base track are wide enough to cover both panel
    # tracks, so they start at Y=0 (front) and extend by track depth.
    def self.na_compute_track_y_origin_mm
        0.0
    end
    # ---------------------------------------------------------------

    # FUNCTION | Track Depth (Y Extent of Head + Base Track)
    # ------------------------------------------------------------
    # Track extends slightly beyond the rear panel so it visually wraps
    # both leaves with a small overhang for the rear panel face.
    def self.na_compute_track_depth_mm(panel_thickness_mm, rear_setback_mm)
        rear_back_face = rear_setback_mm.to_f + panel_thickness_mm.to_f
        rear_back_face + (panel_thickness_mm.to_f * 0.3)
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Glazing Geometry
# -----------------------------------------------------------------------------

    # FUNCTION | Glazing Depth (Centred Within the Panel Thickness)
    # ------------------------------------------------------------
    def self.na_compute_glazing_depth_mm(panel_thickness_mm)
        panel_thickness_mm.to_f * NA_GLAZING_DEPTH_RATIO
    end
    # ---------------------------------------------------------------

    # FUNCTION | Glazing Y-Origin Within a Leaf (Local to Leaf Front Face)
    # ------------------------------------------------------------
    # Returns the Y offset from the leaf's own front face (Y=0 in
    # leaf-local space) to the front of the glazing pane.
    def self.na_compute_glazing_y_origin_mm(panel_thickness_mm)
        (panel_thickness_mm.to_f - na_compute_glazing_depth_mm(panel_thickness_mm)) / 2.0
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Slide Mode Resolution
# -----------------------------------------------------------------------------

    # FUNCTION | Resolve the Signed MVE X-Distance for the Front Leaf
    # ------------------------------------------------------------
    # `FrontSlidesRight` -> +X displacement, `FrontSlidesLeft` -> -X.
    # Defaults to +X (Right) when the mode is unknown so a degenerate
    # config still produces a sensible model.
    def self.na_resolve_front_leaf_signed_travel_mm(slide_mode, leaf_width_mm)
        magnitude = na_compute_slide_travel_mm(leaf_width_mm).to_f
        return -magnitude if slide_mode.to_s == "FrontSlidesLeft"
        magnitude
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__GeometryHelpers
end # module Na__ExteriorSlidingDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
