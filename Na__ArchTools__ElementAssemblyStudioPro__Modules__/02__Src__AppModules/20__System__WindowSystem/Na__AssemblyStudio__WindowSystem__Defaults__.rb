# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - WINDOW SYSTEM DEFAULTS
# =============================================================================
#
# FILE       : Na__AssemblyStudio__WindowSystem__Defaults__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__WindowSystem::Na__Defaults
# PURPOSE    : Window-system NA_DEFAULT_CONFIG plus the legacy module
#              constants the GeometryEngine reads via constants_from_parent.
# =============================================================================

require 'json'

module Na__AssemblyStudio
    module Na__WindowSystem

        # CONSTANTS | Default Window Dimensions (in mm)
        NA_MM_TO_INCH                       = 1.0 / 25.4
        NA_DEFAULT_WIDTH                    = 900
        NA_DEFAULT_HEIGHT                   = 1200
        NA_DEFAULT_FRAME_THICKNESS          = 50
        NA_DEFAULT_FRAME_TOP_THICKNESS      = 50
        NA_DEFAULT_FRAME_BOTTOM_THICKNESS   = 50
        NA_DEFAULT_FRAME_LEFT_THICKNESS     = 50
        NA_DEFAULT_FRAME_RIGHT_THICKNESS    = 50
        NA_DEFAULT_CASEMENT_WIDTH           = 65
        NA_DEFAULT_CASEMENT_DEPTH           = 55
        NA_DEFAULT_CASEMENT_INSET           = 10
        NA_DEFAULT_GLASS_THICKNESS          = 20
        NA_DEFAULT_GLAZE_BAR_WIDTH          = 25
        NA_DEFAULT_GLAZEBAR_INSET           = 10
        NA_DEFAULT_CILL_DEPTH               = 50
        NA_DEFAULT_CILL_HEIGHT              = 50
        NA_DEFAULT_FRAME_DEPTH              = 70
        NA_DEFAULT_FRAME_WALL_INSET         = 0
        NA_DEFAULT_MULLION_COUNT            = 0
        NA_DEFAULT_MULLION_WIDTH            = 40
        NA_DEFAULT_TRANSOM_COUNT            = 0
        NA_DEFAULT_TRANSOM_WIDTH            = 40
        NA_DEFAULT_TRANSOM_1_Y              = 300
        NA_DEFAULT_TRANSOM_2_Y              = 600
        NA_DEFAULT_TRANSOM_3_Y              = 900
        NA_DEFAULT_FRAME_MATERIAL_ID        = "MAT120__GenericWood"
        NA_DEFAULT_GLASS_MATERIAL_ID        = "MAT101__GenericGlass"
        NA_DEFAULT_CILL_MATERIAL_ID         = "MAT541__Timber__Sapele"

        module Na__Defaults

            NA_DEFAULT_CONFIG_JSON = <<~JSON_STRING
            {
                "windowMetadata": [
                    {
                        "WindowUniqueId": null,
                        "WindowName": "New Window",
                        "WindowDescription": "",
                        "WindowNotes": "Created with Element Assembly Studio Pro",
                        "CreatedDate": null,
                        "LastModified": null
                    }
                ],
                "windowComponents": [],
                "windowConfiguration": {
                    "width_mm": 900, "height_mm": 1200,
                    "frame_thickness_mm": 50, "advanced_frame_controls": false,
                    "frame_top_thickness_mm": 50, "frame_bottom_thickness_mm": 50,
                    "frame_left_thickness_mm": 50, "frame_right_thickness_mm": 50,
                    "casement_width_mm": 65, "casement_sizes_individual": false,
                    "casement_top_rail_mm": 65, "casement_bottom_rail_mm": 65,
                    "casement_left_stile_mm": 65, "casement_right_stile_mm": 65,
                    "casement_depth_mm": 55, "casement_inset_mm": 10,
                    "casements_per_opening": 1, "sliding_sash_overlap_mm": 20,
                    "mullion_width_mm": 40, "mullions": 0,
                    "transoms": 0, "transom_width_mm": 40,
                    "transom_1_y_mm": 300, "transom_2_y_mm": 600, "transom_3_y_mm": 900,
                    "glass_thickness_mm": 20,
                    "horizontal_glaze_bars": 0, "vertical_glaze_bars": 0,
                    "glaze_bar_width_mm": 25, "glazebar_inset_mm": 10,
                    "has_cill": true, "cill_depth_mm": 50, "cill_height_mm": 50,
                    "frame_depth_mm": 70, "frame_wall_inset_mm": 0,
                    "removed_casements": [], "removed_transom_segments": [], "removed_glazebars": [],
                    "frame_material_id": "MAT120__GenericWood",
                    "paint_cill": false, "show_dimensions": true, "show_casements": true,
                    "sliding_sash_window": false,
                    "door_mode": false,
                    "sliding_mode": false,
                    "multifold_mode": false,
                    "door_panel_height_mm": 400, "door_panel_columns": 1, "door_panel_rows": 1,
                    "door_panel_rail_width_mm": 30, "door_panel_stile_width_mm": 30,
                    "door_mid_rail_width_mm": 150, "door_base_rail_width_mm": 200,
                    "door_panel_margin_mm": 30, "door_panel_recess_depth_mm": 10,
                    "door_panel_show_trim": false, "door_panel_trim_width_mm": 5,
                    "door_panel_trim_depth_mm": 3, "door_panel_moulding_inset_mm": 5,
                    "fuse_parts": false,
                    "sliding_door_mode": "FrontSlidesRight",
                    "sliding_door_opening_width_mm": 2400,
                    "sliding_door_opening_height_mm": 2100,
                    "sliding_door_wall_depth_mm": 105,
                    "sliding_door_panel_thickness_mm": 50,
                    "sliding_door_floor_clearance_mm": 10,
                    "sliding_door_rear_setback_mm": 60,
                    "sliding_door_head_rail_mm": 95,
                    "sliding_door_base_rail_mm": 200,
                    "sliding_door_stile_width_mm": 95,
                    "sliding_door_glazed": true,
                    "sliding_door_panel_design_open": false,
                    "sliding_door_handle_asset_key": "Na__ExteriorDoor__Handle__SlidingDefault",
                    "sliding_door_handle_height_mm": 1000,
                    "bifold_door_layout": "EqualEqual",
                    "bifold_door_open_side": "Right",
                    "bifold_door_master_side": "Right",
                    "bifold_door_panel_count": 4,
                    "bifold_door_opening_width_mm": 3600,
                    "bifold_door_opening_height_mm": 2100,
                    "bifold_door_wall_depth_mm": 105,
                    "bifold_door_panel_thickness_mm": 50,
                    "bifold_door_floor_clearance_mm": 10,
                    "bifold_door_head_rail_mm": 95,
                    "bifold_door_base_rail_mm": 200,
                    "bifold_door_stile_width_mm": 95,
                    "bifold_door_glazed": true,
                    "bifold_door_panel_design_open": false,
                    "bifold_door_handle_asset_key": "Na__ExteriorDoor__Handle__BifoldDefault",
                    "bifold_door_handle_height_mm": 1000
                }
            }
            JSON_STRING

            NA_DEFAULT_CONFIG = JSON.parse(NA_DEFAULT_CONFIG_JSON)

            def self.na_default_config
                NA_DEFAULT_CONFIG
            end

        end

    end
end
