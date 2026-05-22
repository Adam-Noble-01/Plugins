/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - WINDOW SYSTEM - UI CONFIGURATION
   =============================================================================
   
   FILE       : Na__AssemblyStudio__WindowSystem__UiSystem__Config__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : UI control configuration constants
   CREATED    : 2026
   
   DESCRIPTION:
   - Configuration arrays for all UI control types
   - Primary dimension controls (width, height, frame, casement, mullions)
   - Glaze bar controls (horizontal, vertical, bar width)
   - Cill & frame controls (cill height/depth, frame depth/inset)
   - Options controls (toggles, color pickers)
   
   NAMING CONVENTION:
   - All constants use NA_ prefix (uppercase)
   - Exported to window object for global access
   
   ============================================================================= */

// =============================================================================
// REGION | Primary UI Control Configuration
// =============================================================================

// CONSTANTS | Primary UI Control Configuration
// ------------------------------------------------------------
const NA_UI_CONFIG = [
    {
        id      :  'width_mm',
        label   :  'Width',
        unit    :  'mm',
        type    :  'slider',
        min     :  300,
        max     :  4000,
        step    :  10,
        default :  900
    },
    {
        id      :  'height_mm',
        label   :  'Height',
        unit    :  'mm',
        type    :  'slider',
        min     :  300,
        max     :  2600,
        step    :  10,
        default :  1200
    },
    {
        id      :  'frame_thickness_mm',
        label   :  'Frame Thickness',
        unit    :  'mm',
        type    :  'slider',
        min     :  0,
        max     :  120,
        step    :  5,
        default :  50
    },
    {
        id      :  'advanced_frame_controls',
        label   :  'Advanced Frame Controls',
        type    :  'expandable',
        default :  false,
        children: [
            {
                id      :  'frame_top_thickness_mm',
                label   :  'Top Frame',
                unit    :  'mm',
                type    :  'slider',
                min     :  0,
                max     :  150,
                step    :  5,
                default :  50
            },
            {
                id      :  'frame_bottom_thickness_mm',
                label   :  'Bottom Frame',
                unit    :  'mm',
                type    :  'slider',
                min     :  0,
                max     :  150,
                step    :  5,
                default :  50
            },
            {
                id      :  'frame_left_thickness_mm',
                label   :  'Left Frame',
                unit    :  'mm',
                type    :  'slider',
                min     :  0,
                max     :  150,
                step    :  5,
                default :  50
            },
            {
                id      :  'frame_right_thickness_mm',
                label   :  'Right Frame',
                unit    :  'mm',
                type    :  'slider',
                min     :  0,
                max     :  150,
                step    :  5,
                default :  50
            }
        ]
    },
    {
        id      :  'casement_width_mm',
        label   :  'Casement Width',
        unit    :  'mm',
        type    :  'slider',
        min     :  20,
        max     :  250,
        step    :  5,
        default :  65
    },
    {
        id      :  'casement_sizes_individual',
        label   :  'Individual Casement Sizes',
        type    :  'expandable',
        default :  false,
        children: [
            {
                id      :  'casement_top_rail_mm',
                label   :  'Top Rail',
                unit    :  'mm',
                type    :  'slider',
                min     :  20,
                max     :  250,
                step    :  5,
                default :  60
            },
            {
                id      :  'casement_bottom_rail_mm',
                label   :  'Bottom Rail',
                unit    :  'mm',
                type    :  'slider',
                min     :  20,
                max     :  500,
                step    :  5,
                default :  70
            },
            {
                id      :  'casement_left_stile_mm',
                label   :  'Left Stile',
                unit    :  'mm',
                type    :  'slider',
                min     :  20,
                max     :  250,
                step    :  5,
                default :  40
            },
            {
                id      :  'casement_right_stile_mm',
                label   :  'Right Stile',
                unit    :  'mm',
                type    :  'slider',
                min     :  20,
                max     :  250,
                step    :  5,
                default :  40
            }
        ]
    },
    {
        id      :  'advanced_casement_controls',
        label   :  'Advanced Casement Controls',
        type    :  'expandable',
        default :  false,
        children: [
            {
                id      :  'casement_depth_mm',
                label   :  'Casement Depth',
                unit    :  'mm',
                type    :  'slider',
                min     :  40,
                max     :  100,
                step    :  5,
                default :  55
            },
            {
                id      :  'casement_inset_mm',
                label   :  'Casement Frame Inset',
                unit    :  'mm',
                type    :  'slider',
                min     :  0,
                max     :  100,
                step    :  1,
                default :  10
            },
            {
                id      :  'glass_thickness_mm',
                label   :  'Glazing Thickness',
                unit    :  'mm',
                type    :  'slider',
                min     :  5,
                max     :  35,
                step    :  1,
                default :  20
            },
            {
                id      :  'glazebar_inset_mm',
                label   :  'Glaze Bar Inset',
                unit    :  'mm',
                type    :  'slider',
                min     :  0,
                max     :  20,
                step    :  1,
                default :  10
            },
            {
                id      :  'casements_per_opening',
                label   :  'Casements Per Opening',
                unit    :  '',
                type    :  'slider',
                min     :  1,
                max     :  6,
                step    :  1,
                default :  1
            }
        ]
    },
    {
        id      :  'mullions',
        label   :  'Mullions',
        unit    :  '',
        type    :  'slider',
        min     :  0,
        max     :  6,
        step    :  1,
        default :  0
    },
    {
        id      :  'mullion_width_mm',
        label   :  'Mullion Width',
        unit    :  'mm',
        type    :  'slider',
        min     :  30,
        max     :  120,
        step    :  5,
        default :  40
    },
    {
        id      :  'transoms',
        label   :  'Transoms',
        unit    :  '',
        type    :  'slider',
        min     :  0,
        max     :  3,
        step    :  1,
        default :  0
    },
    {
        id      :  'transom_width_mm',
        label   :  'Transom Width',
        unit    :  'mm',
        type    :  'slider',
        min     :  30,
        max     :  120,
        step    :  5,
        default :  40
    },
    {
        id      :  'transom_1_y_mm',
        label   :  'Transom 1 Height',
        unit    :  'mm',
        type    :  'slider',
        min     :  50,
        max     :  2400,
        step    :  10,
        default :  300
    },
    {
        id      :  'transom_2_y_mm',
        label   :  'Transom 2 Height',
        unit    :  'mm',
        type    :  'slider',
        min     :  50,
        max     :  2400,
        step    :  10,
        default :  600
    },
    {
        id      :  'transom_3_y_mm',
        label   :  'Transom 3 Height',
        unit    :  'mm',
        type    :  'slider',
        min     :  50,
        max     :  2400,
        step    :  10,
        default :  900
    },
    {
        id      :  'sliding_sash_overlap_mm',
        label   :  'Sliding Sash Overlap',
        unit    :  'mm',
        type    :  'slider',
        min     :  0,
        max     :  60,
        step    :  1,
        default :  20
    },
    {
        id      :  'top_sash_bottom_rail_mm',
        label   :  'Top Sash Bottom Rail',
        unit    :  'mm',
        type    :  'slider',
        min     :  20,
        max     :  500,
        step    :  5,
        default :  70
    }
];

// endregion ===================================================================

// =============================================================================
// REGION | Glaze Bars Configuration
// =============================================================================

// CONSTANTS | Glaze Bars Configuration
// ------------------------------------------------------------
const NA_GLAZEBAR_CONFIG = [
    {
        id      :  'horizontal_glaze_bars',
        label   :  'Horizontal Bars',
        unit    :  '',
        type    :  'slider',
        min     :  0,
        max     :  8,
        step    :  1,
        default :  0
    },
    {
        id      :  'vertical_glaze_bars',
        label   :  'Vertical Bars',
        unit    :  '',
        type    :  'slider',
        min     :  0,
        max     :  8,
        step    :  1,
        default :  0
    },
    {
        id      :  'glaze_bar_width_mm',
        label   :  'Bar Width',
        unit    :  'mm',
        type    :  'slider',
        min     :  10,
        max     :  60,
        step    :  5,
        default :  25
    }
];

// endregion ===================================================================

// =============================================================================
// REGION | Cill & Frame Configuration
// =============================================================================

// CONSTANTS | Cill & Frame Configuration
// ------------------------------------------------------------
const NA_CILL_FRAME_CONFIG = [
    {
        id      :  'cill_height_mm',
        label   :  'Cill Height',
        unit    :  'mm',
        type    :  'slider',
        min     :  20,
        max     :  100,
        step    :  5,
        default :  50
    },
    {
        id      :  'cill_depth_mm',
        label   :  'Cill Protrusion',
        unit    :  'mm',
        type    :  'slider',
        min     :  20,
        max     :  100,
        step    :  5,
        default :  50
    },
    {
        id      :  'frame_depth_mm',
        label   :  'Frame Depth',
        unit    :  'mm',
        type    :  'slider',
        min     :  50,
        max     :  140,
        step    :  5,
        default :  70
    },
    {
        id      :  'frame_wall_inset_mm',
        label   :  'Frame Wall Inset',
        unit    :  'mm',
        type    :  'slider',
        min     :  -50,
        max     :  150,
        step    :  5,
        default :  0
    }
];

// endregion ===================================================================

// =============================================================================
// REGION | Options Configuration
// =============================================================================

// CONSTANTS | Options Configuration
// ------------------------------------------------------------
const NA_OPTIONS_CONFIG = [
    {
        id      :  'show_casements',
        label   :  'Show Casements',
        type    :  'toggle',
        default :  true
    },
    {
        id      :  'has_cill',
        label   :  'Include Cill',
        type    :  'toggle',
        default :  true
    },
    {
        id      :  'show_dimensions',
        label   :  'Show Dimensions',
        type    :  'toggle',
        default :  true
    },
    {
        id      :  'fuse_parts',
        label   :  'Fuse Parts',
        type    :  'toggle',
        default :  false
    },
    {
        id      :  'paint_cill',
        label   :  'Paint Cill',
        type    :  'toggle',
        default :  false
    },
    {
        id      :  'sliding_sash_window',
        label   :  'Sliding Sash Window',
        type    :  'toggle',
        default :  false
    },
    {
        id      :  'sash_horns_enabled',
        label   :  'Show Sash Horns',
        type    :  'toggle',
        default :  true
    },
    {
        id      :  'sash_horn_type',
        label   :  'Sash Horn Type',
        type    :  'select',
        default :  '1',
        options :  [
            { value: '1', label: 'Type 01' },
            { value: '2', label: 'Type 02' },
            { value: '3', label: 'Type 03' },
            { value: '4', label: 'Type 04' }
        ]
    },
    {
        id      :  'door_mode',
        label   :  'Door Mode',
        type    :  'toggle',
        default :  false
    },
    {
        id      :  'sliding_mode',
        label   :  'Sliding Door',
        type    :  'toggle',
        default :  false
    },
    {
        id      :  'multifold_mode',
        label   :  'Multi-Folding Door',
        type    :  'toggle',
        default :  false
    },
    {
        id              : 'frame_material_id',
        label           : 'Frame Finish',
        type            : 'material_cards',
        default         : 'MAT120__GenericWood',
        materialsSource : 'NA_FRAME_FINISH_SWATCHES'                              // <-- Live swatches from materials JSON via Ruby push
    }
];

// endregion ===================================================================

// =============================================================================
// REGION | Global Exports
// =============================================================================

// Export to global window object for access by other modules
// ------------------------------------------------------------
window.NA_UI_CONFIG = NA_UI_CONFIG;
window.NA_GLAZEBAR_CONFIG = NA_GLAZEBAR_CONFIG;
window.NA_CILL_FRAME_CONFIG = NA_CILL_FRAME_CONFIG;
window.NA_OPTIONS_CONFIG = NA_OPTIONS_CONFIG;

console.log('[NA_UI_CONFIG] Configuration module loaded');

// endregion ===================================================================

// =============================================================================
// END OF FILE
// =============================================================================
