/* =============================================================================
   NA WINDOW CONFIGURATOR TOOL - DOOR PANEL UI CONFIGURATION
   =============================================================================
   
   FILE       : Na__WindowConfiguratorTool__DoorPanel__Config__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : UI control configuration for Door Mode panel controls
   CREATED    : 2026
   
   DESCRIPTION:
   - Configuration arrays for door panel UI controls
   - Core panel height, layout grid, design, and trim/moulding controls
   - Covers typical British door panel styles (single, 2-panel, 4-panel,
     6-panel Georgian, horizontal rail panels, etc.)
   - Only visible when door_mode toggle is enabled
   
   NAMING CONVENTION:
   - All constants use NA_ prefix (uppercase)
   - Exported to window object for global access
   
   ============================================================================= */

// =============================================================================
// REGION | Door Panel UI Control Configuration
// =============================================================================

// CONSTANTS | Door Panel UI Control Configuration
// ------------------------------------------------------------
const NA_DOOR_PANEL_CONFIG = [
    {
        id      :  'door_panel_height_mm',
        label   :  'Panel Section Height',
        unit    :  'mm',
        type    :  'slider',
        min     :  100,
        max     :  1200,
        step    :  10,
        default :  400
    },
    {
        id      :  'door_panel_layout_controls',
        label   :  'Panel Layout',
        type    :  'expandable',
        default :  false,
        children: [
            {
                id      :  'door_panel_columns',
                label   :  'Panel Columns',
                unit    :  '',
                type    :  'slider',
                min     :  1,
                max     :  4,
                step    :  1,
                default :  1
            },
            {
                id      :  'door_panel_rows',
                label   :  'Panel Rows',
                unit    :  '',
                type    :  'slider',
                min     :  1,
                max     :  3,
                step    :  1,
                default :  1
            },
            {
                id      :  'door_panel_rail_width_mm',
                label   :  'Rail Width',
                unit    :  'mm',
                type    :  'slider',
                min     :  15,
                max     :  95,
                step    :  5,
                default :  30
            },
            {
                id      :  'door_panel_stile_width_mm',
                label   :  'Stile Width',
                unit    :  'mm',
                type    :  'slider',
                min     :  15,
                max     :  95,
                step    :  5,
                default :  30
            }
        ]
    },
    {
        id      :  'door_panel_design_controls',
        label   :  'Panel Design',
        type    :  'expandable',
        default :  false,
        children: [
            {
                id      :  'door_panel_margin_mm',
                label   :  'Panel Margin',
                unit    :  'mm',
                type    :  'slider',
                min     :  10,
                max     :  100,
                step    :  5,
                default :  30
            },
            {
                id      :  'door_panel_recess_depth_mm',
                label   :  'Recess Depth',
                unit    :  'mm',
                type    :  'slider',
                min     :  2,
                max     :  25,
                step    :  1,
                default :  8
            }
        ]
    },
    {
        id      :  'door_panel_show_trim',
        label   :  'Show Trim / Moulding',
        type    :  'toggle',
        default :  false
    },
    {
        id      :  'door_panel_trim_controls',
        label   :  'Trim / Moulding',
        type    :  'expandable',
        default :  false,
        children: [
            {
                id      :  'door_panel_trim_width_mm',
                label   :  'Trim Width',
                unit    :  'mm',
                type    :  'slider',
                min     :  0,
                max     :  25,
                step    :  1,
                default :  5
            },
            {
                id      :  'door_panel_trim_depth_mm',
                label   :  'Trim Depth',
                unit    :  'mm',
                type    :  'slider',
                min     :  0,
                max     :  12,
                step    :  1,
                default :  3
            },
            {
                id      :  'door_panel_moulding_inset_mm',
                label   :  'Moulding Inset',
                unit    :  'mm',
                type    :  'slider',
                min     :  0,
                max     :  15,
                step    :  1,
                default :  5
            }
        ]
    }
];

// endregion ===================================================================

// =============================================================================
// REGION | Global Exports
// =============================================================================

window.NA_DOOR_PANEL_CONFIG = NA_DOOR_PANEL_CONFIG;

console.log('[NA_DOOR_PANEL_CONFIG] Door Panel configuration module loaded');

// endregion ===================================================================

// =============================================================================
// END OF FILE
// =============================================================================
