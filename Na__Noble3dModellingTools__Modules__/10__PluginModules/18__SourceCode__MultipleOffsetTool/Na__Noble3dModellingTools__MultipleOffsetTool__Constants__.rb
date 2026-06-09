# =============================================================================
# NA NOBLE3D MODELLING TOOLS - MULTIPLE OFFSET TOOL - CONSTANTS
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__MultipleOffsetTool__Constants__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__MultipleOffsetTool
# PURPOSE    : Module-level constants for the Multiple Offset Tool
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__MultipleOffsetTool

# -----------------------------------------------------------------------------
# REGION | Embedded JSON Method & Function Index
# -----------------------------------------------------------------------------

        SCRIPT_METHOD_INDEX = {
            "script_info" => {
                "name"    => "Na__MultipleOffsetTool",
                "version" => "1.0.1",
                "purpose" => "Interactive multi-face inward perimeter offset tool (per-face plane)"
            },
            "constants" => {
                "visual"   => ["PREVIEW_LINE_COLOR", "PREVIEW_LINE_WIDTH", "INVALID_HINT_COLOR"],
                "state"    => ["STATE_IDLE", "STATE_PREVIEW"],
                "geometry" => ["MIN_EDGE_LENGTH_INTERNAL", "MIN_AREA_INTERNAL", "LINE_INTERSECT_EPSILON", "OFFSET_LIMIT_SAFETY_FACTOR", "OFFSET_SEED_FRACTION", "OUTWARD_LIMIT_MULTIPLE", "MOUSE_MOVE_TOLERANCE_PX", "DOUBLE_ENTER_SECONDS"],
                "defaults" => ["DEFAULT_OFFSET_DISTANCE", "PREF_NAMESPACE", "PREF_DISTANCE"]
            },
            "helper_functions" => {
                "plane"    => ["na_build_face_plane_frame", "na_newell_normal", "na_first_edge_direction", "na_points_to_local", "na_local_to_world", "na_polygon_centroid_2d"],
                "polygon"  => ["na_signed_area_2d", "na_inward_offset_polygon", "na_line_intersection_2d", "na_offset_polygon_valid?", "na_point_in_polygon_2d?"],
                "distance" => ["na_point_to_polygon_min_distance", "na_point_to_segment_distance_2d"]
            },
            "tool_class" => {
                "lifecycle" => ["initialize", "activate", "deactivate", "resume", "rearm_vcb_and_focus"],
                "input"     => ["onMouseMove", "onLButtonDown", "onKeyDown", "onCancel", "enableVCB?", "onUserText", "onReturn"],
                "drawing"   => ["draw", "getExtents"],
                "core"      => ["build_face_cache", "recompute_previews", "commit_offset", "rebuild_cache_from_selection", "ensure_sane_seed_distance"]
            },
            "entry_points" => {
                "public" => ["Na__MultipleOffsetTool__Run"]
            }
        }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Visual Feedback Constants
# -----------------------------------------------------------------------------

        PREVIEW_LINE_COLOR = Sketchup::Color.new(255, 102, 0)            # <-- Orange preview loop color
        PREVIEW_LINE_WIDTH = 2                                           # <-- Preview loop line width in pixels
        INVALID_HINT_COLOR = Sketchup::Color.new(200, 0, 0)             # <-- Reserved colour for invalid-offset hints

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Tool State Constants
# -----------------------------------------------------------------------------

        STATE_IDLE    = 0                                                # <-- No usable face selection cached
        STATE_PREVIEW = 1                                                # <-- Faces cached; live preview running

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Geometry Tolerance Constants (internal units = inches)
# -----------------------------------------------------------------------------

        MIN_EDGE_LENGTH_INTERNAL = 0.001                                # <-- Minimum usable edge length (inches)
        MIN_AREA_INTERNAL        = 0.0001                               # <-- Minimum usable 2D polygon area (inches^2)
        LINE_INTERSECT_EPSILON   = 1.0e-9                              # <-- Parallel-line determinant epsilon

        # Largest safe inset is bounded by the smallest face's inscribed radius
        # (centroid-to-edge distance). Staying just under it keeps every preview
        # bounded and inside its face; the seed starts at half of that.
        OFFSET_LIMIT_SAFETY_FACTOR = 0.98                               # <-- Fraction of inscribed radius treated as max inward inset
        OFFSET_SEED_FRACTION       = 0.5                                # <-- Seed offset as a fraction of the max inset
        OUTWARD_LIMIT_MULTIPLE     = 50.0                               # <-- Max outward (negative) offset as a multiple of the inward cap
        MOUSE_MOVE_TOLERANCE_PX    = 2                                  # <-- Screen-pixel travel before a move ends the re-typeable state
        DOUBLE_ENTER_SECONDS       = 1.0                                # <-- Two Enter presses within this window commit the previewed offset

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Default & Preference Constants
# -----------------------------------------------------------------------------

        DEFAULT_OFFSET_DISTANCE = 50.mm                                 # <-- Seed offset distance when none stored
        PREF_NAMESPACE          = 'Na__Noble3dModellingTools__MultipleOffsetTool'  # <-- Read/write_default namespace
        PREF_DISTANCE           = 'offset_distance'                     # <-- Stored last-used distance key

# endregion -------------------------------------------------------------------

    end # module Na__MultipleOffsetTool
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
