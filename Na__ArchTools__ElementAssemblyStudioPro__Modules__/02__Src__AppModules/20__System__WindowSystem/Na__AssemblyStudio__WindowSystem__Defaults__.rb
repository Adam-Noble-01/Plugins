# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - WINDOW SYSTEM DEFAULTS
# =============================================================================
#
# FILE       : Na__AssemblyStudio__WindowSystem__Defaults__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__WindowSystem
# MODULE     : Na__Defaults (configuration hash)
# AUTHOR     : Noble Architecture
# PURPOSE    : Window-system NA_DEFAULT_CONFIG plus legacy module constants
#              the GeometryEngine reads via constants_from_parent.
# CREATED    : 2026
#
# DESCRIPTION:
# - Owns every scalar default the Window System geometry pipeline expects
#   at Na__WindowSystem module scope (NA_DEFAULT_* constants).
# - Owns the full default dialog/serializer payload under Na__Defaults as
#   column-aligned JSON parsed once into NA_DEFAULT_CONFIG.
# - DialogCallbacks.na_default_config delegates here so Ruby and JS state
#   stay aligned from session start.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'json'

module Na__AssemblyStudio
module Na__WindowSystem

# -----------------------------------------------------------------------------
# REGION | Module Constants - Unit Conversion
# -----------------------------------------------------------------------------

    # MODULE CONSTANTS | SketchUp Unit Conversion
    # ------------------------------------------------------------
    NA_MM_TO_INCH                       = (1.0 / 25.4).freeze
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants - Default Window Dimensions
# -----------------------------------------------------------------------------

    # MODULE CONSTANTS | Opening and Frame (millimetres)
    # ------------------------------------------------------------
    NA_DEFAULT_WIDTH                    = 900
    NA_DEFAULT_HEIGHT                   = 1200
    NA_DEFAULT_FRAME_THICKNESS          = 50
    NA_DEFAULT_FRAME_TOP_THICKNESS      = 50
    NA_DEFAULT_FRAME_BOTTOM_THICKNESS   = 50
    NA_DEFAULT_FRAME_LEFT_THICKNESS     = 50
    NA_DEFAULT_FRAME_RIGHT_THICKNESS    = 50
    NA_DEFAULT_FRAME_DEPTH              = 70
    NA_DEFAULT_FRAME_WALL_INSET         = 0
    # ---------------------------------------------------------------

    # MODULE CONSTANTS | Casement and Glazing (millimetres)
    # ------------------------------------------------------------
    NA_DEFAULT_CASEMENT_WIDTH           = 65
    NA_DEFAULT_CASEMENT_DEPTH           = 55
    NA_DEFAULT_CASEMENT_INSET           = 10
    NA_DEFAULT_GLASS_THICKNESS          = 20
    NA_DEFAULT_GLAZE_BAR_WIDTH          = 25
    NA_DEFAULT_GLAZEBAR_INSET           = 10
    # ---------------------------------------------------------------

    # MODULE CONSTANTS | Cill, Mullions, and Transoms (millimetres)
    # ------------------------------------------------------------
    NA_DEFAULT_CILL_DEPTH               = 50
    NA_DEFAULT_CILL_HEIGHT              = 50
    NA_DEFAULT_MULLION_COUNT            = 0
    NA_DEFAULT_MULLION_WIDTH            = 40
    NA_DEFAULT_TRANSOM_COUNT            = 0
    NA_DEFAULT_TRANSOM_WIDTH            = 40
    NA_DEFAULT_TRANSOM_1_Y              = 300
    NA_DEFAULT_TRANSOM_2_Y              = 600
    NA_DEFAULT_TRANSOM_3_Y              = 900
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants - Default Material IDs
# -----------------------------------------------------------------------------

    # MODULE CONSTANTS | Default Material IDs (resolved against MaterialManager)
    # ------------------------------------------------------------
    NA_DEFAULT_FRAME_MATERIAL_ID        = "MAT120__GenericWood".freeze
    NA_DEFAULT_GLASS_MATERIAL_ID        = "MAT101__GenericGlass".freeze
    NA_DEFAULT_CILL_MATERIAL_ID         = "MAT541__Timber__Sapele".freeze
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Na__Defaults - Default Window Configuration JSON
# -----------------------------------------------------------------------------

    module Na__Defaults

        # MODULE CONSTANTS | Default Window Configuration
        # ------------------------------------------------------------
        # Three top-level blocks mirror the window serializer contract:
        #   * windowMetadata       (array)
        #   * windowComponents     (array, reserved)
        #   * windowConfiguration  (hash)
        # All numeric configuration values are millimetres unless suffixed.
        NA_DEFAULT_CONFIG_JSON = <<~JSON_STRING
        {
            "windowMetadata": [
                {
                    "WindowUniqueId"          : null,
                    "WindowName"              : "New Window",
                    "WindowDescription"       : "",
                    "WindowComponentName"     : "",
                    "WindowComponentBaseName" : "",
                    "WindowNotes"             : "Created with Element Assembly Studio Pro",
                    "CreatedDate"             : null,
                    "LastModified"            : null
                }
            ],

            "windowComponents": [],

            "windowConfiguration": {
                "width_mm"                              : 900,
                "height_mm"                             : 1200,

                "frame_thickness_mm"                    : 50,
                "advanced_frame_controls"               : false,
                "frame_top_thickness_mm"                : 50,
                "frame_bottom_thickness_mm"             : 50,
                "frame_left_thickness_mm"               : 50,
                "frame_right_thickness_mm"              : 50,
                "frame_depth_mm"                        : 70,
                "frame_wall_inset_mm"                   : 0,

                "casement_width_mm"                     : 65,
                "casement_sizes_individual"             : false,
                "casement_top_rail_mm"                  : 60,
                "casement_bottom_rail_mm"               : 70,
                "top_sash_bottom_rail_mm"               : 60,
                "bottom_sash_top_rail_override"         : false,
                "bottom_sash_top_rail_mm"               : 60,
                "meeting_rail_position_override"        : false,
                "meeting_rail_offset_mm"                : 0,
                "casement_left_stile_mm"                : 40,
                "casement_right_stile_mm"               : 40,
                "casement_depth_mm"                     : 55,
                "casement_inset_mm"                     : 10,
                "casements_per_opening"                 : 1,
                "sliding_sash_overlap_mm"               : 40,
                "sliding_sash_window"                   : false,
                "sash_horns_enabled"                    : true,
                "sash_horn_type"                        : "1",

                "mullion_width_mm"                      : 40,
                "mullions"                              : 0,
                "transoms"                              : 0,
                "transom_width_mm"                      : 40,
                "transom_1_y_mm"                        : 300,
                "transom_2_y_mm"                        : 600,
                "transom_3_y_mm"                        : 900,

                "glass_thickness_mm"                    : 20,
                "horizontal_glaze_bars"                 : 0,
                "vertical_glaze_bars"                   : 0,
                "glaze_bar_width_mm"                    : 25,
                "glazebar_inset_mm"                     : 10,
                "glazebar_margin_enabled"               : false,
                "glazebar_margin_offset_mm"             : 120,
                "glazebar_gothic_arch_enabled"          : false,
                "glazebar_gothic_arch_amount"           : 2,
                "glazebar_gothic_arch_height_mm"        : 400,
                "glazebar_horizontal_offset_mm"         : 0,

                "glazebar_offsets_enabled"              : false,
                "glazebar_h_offset_1_mm"                : 0,
                "glazebar_h_offset_2_mm"                : 0,
                "glazebar_h_offset_3_mm"                : 0,
                "glazebar_h_offset_4_mm"                : 0,
                "glazebar_h_offset_5_mm"                : 0,
                "glazebar_h_offset_6_mm"                : 0,
                "glazebar_h_offset_7_mm"                : 0,
                "glazebar_h_offset_8_mm"                : 0,
                "glazebar_v_offset_1_mm"                : 0,
                "glazebar_v_offset_2_mm"                : 0,
                "glazebar_v_offset_3_mm"                : 0,
                "glazebar_v_offset_4_mm"                : 0,
                "glazebar_v_offset_5_mm"                : 0,
                "glazebar_v_offset_6_mm"                : 0,
                "glazebar_v_offset_7_mm"                : 0,
                "glazebar_v_offset_8_mm"                : 0,

                "leaded_glass_controls"                 : false,
                "leaded_glass_enabled"                  : false,
                "horizontal_leaded_bars"                : 0,
                "vertical_leaded_bars"                  : 0,
                "leaded_width_mm"                       : 6,
                "leaded_depth_mm"                       : 0,
                "leaded_centre_lines_only"              : false,
                "leaded_disabled_cells"                 : [],
                "double_door_leaded_disabled_cells"     : [],

                "edge_colour_controls"                  : false,
                "edge_colour_frame_id"                  : "MTE102__LineColour__SoftBlack__L20",
                "edge_colour_casement_id"               : "MTE103__LineColour__DarkGrey__L40",
                "edge_colour_glazebar_id"               : "MTE103__LineColour__DarkGrey__L40",
                "edge_colour_leaded_id"                 : "MTE104__LineColour__MidGrey__L60",
                "edge_colour_fielded_panel_id"          : "MTE103__LineColour__DarkGrey__L40",

                "has_cill"                              : true,
                "cill_depth_mm"                         : 50,
                "cill_height_mm"                        : 50,

                "removed_casements"                     : [],
                "removed_transom_segments"              : [],
                "removed_glazebars"                     : [],

                "frame_material_id"                     : "MAT120__GenericWood",
                "paint_cill"                            : false,
                "show_dimensions"                       : true,
                "show_casements"                        : true,
                "fuse_parts"                            : false,

                "ext_single_door_mode"                  : false,
                "sliding_mode"                          : false,
                "multifold_mode"                        : false,
                "double_door_mode"                      : false,
                "ui_element_category"                   : "Window",
                "ui_window_type"                        : "Casement",
                "ui_exterior_door_type"                 : "Double",

                "sliding_door_mode"                     : "FrontSlidesRight",
                "sliding_door_opening_width_mm"         : 2400,
                "sliding_door_opening_height_mm"        : 2100,
                "sliding_door_wall_depth_mm"            : 105,
                "sliding_door_panel_thickness_mm"       : 50,
                "sliding_door_floor_clearance_mm"       : 10,
                "sliding_door_rear_setback_mm"          : 60,
                "sliding_door_head_rail_mm"             : 95,
                "sliding_door_base_rail_mm"             : 200,
                "sliding_door_stile_width_mm"           : 95,
                "sliding_door_glazed"                   : true,
                "sliding_door_panel_design_open"        : false,
                "sliding_door_handle_asset_key"         : "Na__ExteriorDoor__Handle__SlidingDefault",
                "sliding_door_handle_height_mm"         : 1000,

                "bifold_door_layout"                    : "EqualEqual",
                "bifold_door_open_side"                 : "Right",
                "bifold_door_master_side"               : "Right",
                "bifold_door_panel_count"               : 4,
                "bifold_door_opening_width_mm"          : 3600,
                "bifold_door_opening_height_mm"         : 2100,
                "bifold_door_wall_depth_mm"             : 105,
                "bifold_door_panel_thickness_mm"        : 50,
                "bifold_door_floor_clearance_mm"        : 10,
                "bifold_door_head_rail_mm"              : 95,
                "bifold_door_base_rail_mm"              : 200,
                "bifold_door_stile_width_mm"            : 95,
                "bifold_door_leaf_composition"          : "FullyGlazed",
                "bifold_door_mid_rail_width_mm"         : 120,
                "bifold_door_panel_output_mode"         : "ThreeDimensional",
                "bifold_door_panel_profile"             : "RaisedBevelled",
                "bifold_door_panel_preset"              : "OnePanel",
                "bifold_door_panel_columns"             : 1,
                "bifold_door_panel_rows"                : 1,
                "bifold_door_fielded_section_height_mm" : 300,
                "bifold_door_panel_inset_mm"            : 25,
                "bifold_door_panel_depth_mm"            : 12,
                "bifold_door_panel_bevel_width_mm"      : 18,
                "bifold_door_glazed"                    : true,
                "bifold_door_panel_design_open"         : false,
                "bifold_door_handle_asset_key"          : "Na__ExteriorDoor__Handle__BifoldDefault",
                "bifold_door_handle_height_mm"          : 1000
            }
        }
        JSON_STRING

        NA_DEFAULT_CONFIG = JSON.parse(NA_DEFAULT_CONFIG_JSON).freeze
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Na__Defaults - Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Return the Default Window Configuration Hash
        # ------------------------------------------------------------
        # @return [Hash] Parsed default config (frozen source; callers clone)
        def self.na_default_config
            NA_DEFAULT_CONFIG
        end
        # ---------------------------------------------------------------

        # FUNCTION | Return the Default Window Configuration as JSON
        # ------------------------------------------------------------
        # @return [String] JSON serialisation suitable for sending to the dialog
        def self.na_default_config_json
            JSON.generate(NA_DEFAULT_CONFIG)
        end
        # ---------------------------------------------------------------

    end # module Na__Defaults

end # module Na__WindowSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
