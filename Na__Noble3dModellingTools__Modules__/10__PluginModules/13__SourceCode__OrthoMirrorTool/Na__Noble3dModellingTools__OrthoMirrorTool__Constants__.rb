# =============================================================================
# NA NOBLE3D MODELLING TOOLS - ORTHO MIRROR TOOL - CONSTANTS
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__OrthoMirrorTool__Constants__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__OrthoMirrorTool
# PURPOSE    : Module-level constants for the Ortho Mirror Tool
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__OrthoMirrorTool

# -----------------------------------------------------------------------------
# REGION | Embedded JSON Method & Function Index
# -----------------------------------------------------------------------------

        SCRIPT_METHOD_INDEX = {
            "script_info" => {
                "name"    => "Na__OrthoMirrorTool",
                "version" => "1.2.0",
                "purpose" => "2D Mirror Tool for Orthographic Views with Context-Aware Axis Locking"
            },
            "constants" => {
                "visual"      => ["PREVIEW_LINE_COLOR", "PREVIEW_LINE_WIDTH", "ENDPOINT_COLOR", "MIDPOINT_COLOR", "INDICATOR_SIZE"],
                "axis_colors" => ["AXIS_COLOR_X", "AXIS_COLOR_Y", "AXIS_COLOR_Z"],
                "state"       => ["STATE_IDLE", "STATE_FIRST_POINT_SET"],
                "lock_state"  => ["LOCK_NONE", "LOCK_X", "LOCK_Y", "LOCK_Z"],
                "behaviour"   => ["MIRROR_RESULT_AS_GROUP"]
            },
            "helper_functions" => {
                "view_detection"  => ["get_camera_view_direction", "is_parallel_projection?", "identify_ortho_view"],
                "point_detection" => ["detect_point_type", "calculate_edge_midpoint", "is_near_midpoint?"],
                "geometry"        => ["calculate_mirror_plane_normal"],
                "axis_locking"    => ["get_axis_vector", "get_axis_color", "get_axis_name", "world_axis_for_lock", "constrain_point_to_axis"]
            },
            "tool_class" => {
                "lifecycle"    => ["initialize", "activate", "deactivate", "resume"],
                "input"        => ["onMouseMove", "onLButtonDown", "onCancel", "onKeyDown", "onKeyUp"],
                "drawing"      => ["draw", "getExtents", "draw_preview_line", "draw_axis_lock_indicator", "draw_endpoint_indicator", "draw_midpoint_indicator", "draw_start_point_marker"],
                "axis_locking" => ["world_axis_vector_for", "handle_arrow_key", "handle_axis_lock_key", "handle_escape", "lock_to_axis", "apply_inference_lock", "unlock_axis", "get_constrained_end_point"]
            },
            "core_functions" => {
                "mirror" => ["execute_mirror_transformation", "finalize_mirror_result", "build_mirror_transform"]
            },
            "entry_points" => {
                "public" => ["Na__OrthoMirrorTool__Run"],
                "menu"   => ["install_menu_and_commands", "activate_for_model"]
            }
        }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Visual Feedback Constants
# -----------------------------------------------------------------------------

        PREVIEW_LINE_COLOR = Sketchup::Color.new(0, 120, 255)           # <-- Blue preview line color
        PREVIEW_LINE_WIDTH = 3                                           # <-- Preview line width in pixels
        ENDPOINT_COLOR     = Sketchup::Color.new(255, 0, 0)             # <-- Red color for endpoint indicators
        MIDPOINT_COLOR     = Sketchup::Color.new(0, 200, 0)             # <-- Green color for midpoint indicators
        INDICATOR_SIZE     = 8                                           # <-- Size of point indicators in pixels

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Tool State Constants
# -----------------------------------------------------------------------------

        STATE_IDLE            = 0                                        # <-- Waiting for first point
        STATE_FIRST_POINT_SET = 1                                        # <-- First point placed, waiting for second

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Axis Lock Constants
# -----------------------------------------------------------------------------

        LOCK_NONE = :none                                                # <-- No axis lock active
        LOCK_X    = :x                                                   # <-- Locked to Red axis (X)
        LOCK_Y    = :y                                                   # <-- Locked to Green axis (Y)
        LOCK_Z    = :z                                                   # <-- Locked to Blue axis (Z)

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Axis Color Constants
# -----------------------------------------------------------------------------

        AXIS_COLOR_X = Sketchup::Color.new(255, 0, 0)                   # <-- Red for X axis
        AXIS_COLOR_Y = Sketchup::Color.new(0, 128, 0)                   # <-- Green for Y axis
        AXIS_COLOR_Z = Sketchup::Color.new(0, 0, 255)                   # <-- Blue for Z axis

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Behaviour Constants
# -----------------------------------------------------------------------------

        # When true, the mirrored copy is left as a tidy group (non-destructive,
        # the user's original geometry is never exploded/merged). Set false to
        # explode the mirrored copy into loose geometry in the current context.
        MIRROR_RESULT_AS_GROUP = true                                    # <-- Keep mirror output as a group (safe default)

# endregion -------------------------------------------------------------------

    end # module Na__OrthoMirrorTool
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
