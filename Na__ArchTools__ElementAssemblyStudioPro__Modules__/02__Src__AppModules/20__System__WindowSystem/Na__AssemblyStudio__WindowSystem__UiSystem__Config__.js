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
        step    :  5,
        default :  900
    },
    {
        id      :  'height_mm',
        label   :  'Height',
        unit    :  'mm',
        type    :  'slider',
        min     :  300,
        max     :  2600,
        step    :  5,
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
        default :  40
    },
    {
        id      :  'top_sash_bottom_rail_mm',
        label   :  'Top Sash Bottom Rail',
        unit    :  'mm',
        type    :  'slider',
        min     :  20,
        max     :  500,
        step    :  5,
        default :  60
    },
    {
        id      :  'bottom_sash_top_rail_override',
        label   :  'Override Bottom Sash Top Rail',
        type    :  'toggle',
        default :  false
    },
    {
        id      :  'bottom_sash_top_rail_mm',
        label   :  'Bottom Sash Top Rail',
        unit    :  'mm',
        type    :  'slider',
        min     :  20,
        max     :  500,
        step    :  5,
        default :  60
    },
    {
        id      :  'meeting_rail_position_override',
        label   :  'Custom Meeting Rail Position',
        type    :  'toggle',
        default :  false
    },
    {
        id      :  'meeting_rail_offset_mm',
        label   :  'Meeting Rail Offset',
        unit    :  'mm',
        type    :  'slider',
        min     :  -600,
        max     :   600,
        step    :  5,
        default :  0
    }
];

// endregion ===================================================================

// =============================================================================
// REGION | Glaze Bars Configuration
// =============================================================================

// CONSTANTS | Per-Bar Offset Slider Pool
// ------------------------------------------------------------
// One signed nudge slider per glaze bar (transom-style static pool).
// Keys: glazebar_h_offset_N_mm / glazebar_v_offset_N_mm (N = 1-based
// bar index matching the removal-key bar numbering). Applied AFTER the
// automatic spacing step. Horizontal bars: positive = up. Vertical
// bars: positive = right. MainUiLogic shows only the first
// horizontal_glaze_bars / vertical_glaze_bars sliders of each pool
// (na_updateGlazebarOffsetVisibility) so the UI stays uncluttered.
const NA_GLAZEBAR_OFFSET_MAX_BARS = 8;

function na_buildGlazebarOffsetDescriptors(axisKey, axisLabel) {
    const descriptors = [];
    for (let barIndex = 1; barIndex <= NA_GLAZEBAR_OFFSET_MAX_BARS; barIndex += 1) {
        descriptors.push({
            id      :  'glazebar_' + axisKey + '_offset_' + barIndex + '_mm',
            label   :  axisLabel + ' Bar ' + barIndex + ' Offset',
            unit    :  'mm',
            type    :  'slider',
            min     :  -500,
            max     :   500,
            step    :  5,
            default :  0
        });
    }
    return descriptors;
}
// ------------------------------------------------------------

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
    ...na_buildGlazebarOffsetDescriptors('h', 'Horizontal'),
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
    ...na_buildGlazebarOffsetDescriptors('v', 'Vertical'),
    {
        id      :  'glaze_bar_width_mm',
        label   :  'Bar Width',
        unit    :  'mm',
        type    :  'slider',
        min     :  10,
        max     :  60,
        step    :  5,
        default :  25
    },
    // -------------------------------------------------------------------------
    // Advanced Glazebar Controls (expandable)
    //
    // Houses two opt-in decorations driven by toggle children:
    //   * Margin Glazing  - inset the outermost pair of bars by N mm and
    //                       redistribute interior bars evenly between them.
    //   * Gothic Arch     - overshooting two-centred lancet arches across the
    //                       top of the glazed area; regular bars below adapt
    //                       to the reduced effective glass height.
    //
    // Slider defaults for the Gothic arch sliders are static seeds; runtime
    // dynamic recomputation lives in MainUiLogic
    // (na_computeGothicArchAmountDefault / na_computeGothicArchHeightDefault).
    // Visibility of dependant sliders is wired in MainUiLogic
    // (na_updateAdvancedGlazebarVisibility).
    // -------------------------------------------------------------------------
    {
        id      :  'advanced_glazebar_controls',
        label   :  'Advanced Glazebar Controls',
        type    :  'expandable',
        default :  false,
        children: [
            {
                id      :  'glazebar_margin_enabled',
                label   :  'Glaze Bar Margins',
                type    :  'toggle',
                default :  false
            },
            {
                id      :  'glazebar_margin_offset_mm',
                label   :  'Glaze Bar Margin Size',
                unit    :  'mm',
                type    :  'slider',
                min     :  50,
                max     :  400,
                step    :  10,
                default :  120
            },
            {
                id      :  'glazebar_gothic_arch_enabled',
                label   :  'Glaze Bar Gothic Arch Decoration',
                type    :  'toggle',
                default :  false
            },
            {
                id      :  'glazebar_gothic_arch_amount',
                label   :  'Amount Of Arches',
                unit    :  '',
                type    :  'slider',
                min     :  1,
                max     :  8,
                step    :  1,
                default :  2
            },
            {
                id      :  'glazebar_gothic_arch_height_mm',
                label   :  'Height Of Arches',
                unit    :  'mm',
                type    :  'slider',
                min     :  200,
                max     :  800,
                step    :  10,
                default :  400
            },
            // ---------------------------------------------------------
            // Horizontal Bar Vertical Offset
            //
            // Uniform vertical nudge applied to every horizontal glaze
            // bar after the automatic spacing is computed. Positive
            // values lift the bars towards the top of the glass.
            //
            // Use case: When Gothic Arch is enabled, the effective
            // glass height shrinks to fit the arch zone, and the
            // central horizontal bar drops below where it would
            // visually align with the arch springing. This slider
            // lets the user nudge that central bar (and any other
            // horizontal bars) upward to line up with the springing
            // or wherever the design calls for.
            //
            // Behaviour:
            //   * h_bars == 1 -> single (central) bar shifts.
            //   * h_bars >= 2 -> ALL horizontal bars shift uniformly.
            //   * h_bars == 0 -> slider has no effect (no bars to move).
            // ---------------------------------------------------------
            {
                id      :  'glazebar_horizontal_offset_mm',
                label   :  'Horizontal Bar Vertical Offset',
                unit    :  'mm',
                type    :  'slider',
                min     :  -500,
                max     :   500,
                step    :  5,
                default :  0
            }
        ]
    },
    // -------------------------------------------------------------------------
    // Leaded Glass Controls (expandable)
    //
    // Overlay lead came on the outer glass face (does not subdivide glass).
    // Modes: centre-lines only / flat ribbons (depth 0) / extruded (1–5 mm).
    // Visibility of child controls is wired in MainUiLogic
    // (na_updateLeadedGlassVisibility).
    // -------------------------------------------------------------------------
    {
        id      :  'leaded_glass_controls',
        label   :  'Leaded Glass',
        type    :  'expandable',
        default :  false,
        children: [
            {
                id      :  'leaded_glass_enabled',
                label   :  'Enable Leaded Glass',
                type    :  'toggle',
                default :  false
            },
            {
                id      :  'horizontal_leaded_bars',
                label   :  'Horizontal Lead Lines',
                unit    :  '',
                type    :  'slider',
                min     :  0,
                max     :  10,
                step    :  1,
                default :  0
            },
            {
                id      :  'vertical_leaded_bars',
                label   :  'Vertical Lead Lines',
                unit    :  '',
                type    :  'slider',
                min     :  0,
                max     :  8,
                step    :  1,
                default :  0
            },
            {
                id      :  'leaded_width_mm',
                label   :  'Lead Width',
                unit    :  'mm',
                type    :  'slider',
                min     :  2,
                max     :  20,
                step    :  1,
                default :  6
            },
            {
                id      :  'leaded_depth_mm',
                label   :  'Lead Depth',
                unit    :  'mm',
                type    :  'slider',
                min     :  0,
                max     :  5,
                step    :  1,
                default :  0
            },
            {
                id      :  'leaded_centre_lines_only',
                label   :  'Centre Lines Only',
                type    :  'toggle',
                default :  false
            }
        ]
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
        id      :  'ui_element_category',
        label   :  'Product',
        type    :  'binary_toggle',
        default :  'Window',
        options :  [
            { value: 'Window', label: 'Windows' },
            { value: 'ExteriorDoors', label: 'Exterior Doors' }
        ]
    },
    {
        id      :  'ui_window_type',
        label   :  'Window Type',
        type    :  'binary_toggle',
        default :  'Casement',
        options :  [
            { value: 'Casement', label: 'Casement Window' },
            { value: 'SlidingSash', label: 'Sliding Sash Window' }
        ]
    },
    {
        id      :  'ui_exterior_door_type',
        label   :  'Door Type',
        type    :  'multiway_toggle',
        default :  'Double',
        options :  [
            { value: 'Double', label: 'Double Doors' },
            { value: 'Single', label: 'Single Door' },
            { value: 'MultiFold', label: 'MultiFolding Door' },
            { value: 'Sliding', label: 'Sliding Doors' }
        ]
    },
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
        id              : 'frame_material_id',
        label           : 'Frame Finish',
        type            : 'material_cards',
        default         : 'MAT120__GenericWood',
        materialsSource : 'NA_FRAME_FINISH_SWATCHES'                              // <-- Live swatches from materials JSON via Ruby push
    },
    {
        id      :  'edge_colour_controls',
        label   :  'Edge Colours',
        type    :  'expandable',
        default :  false,
        children:  [
            {
                id              : 'edge_colour_frame_id',
                label           : 'Frame',
                type            : 'material_cards',
                default         : 'MTE102__LineColour__SoftBlack__L20',
                materialsSource : 'NA_EDGE_COLOUR_SWATCHES'
            },
            {
                id              : 'edge_colour_casement_id',
                label           : 'Casement',
                type            : 'material_cards',
                default         : 'MTE103__LineColour__DarkGrey__L40',
                materialsSource : 'NA_EDGE_COLOUR_SWATCHES'
            },
            {
                id              : 'edge_colour_glazebar_id',
                label           : 'Glazebar',
                type            : 'material_cards',
                default         : 'MTE103__LineColour__DarkGrey__L40',
                materialsSource : 'NA_EDGE_COLOUR_SWATCHES'
            },
            {
                id              : 'edge_colour_leaded_id',
                label           : 'Lead Lines',
                type            : 'material_cards',
                default         : 'MTE104__LineColour__MidGrey__L60',
                materialsSource : 'NA_EDGE_COLOUR_SWATCHES'
            },
            {
                id              : 'edge_colour_fielded_panel_id',
                label           : 'Fielded Panel',
                type            : 'material_cards',
                default         : 'MTE103__LineColour__DarkGrey__L40',
                materialsSource : 'NA_EDGE_COLOUR_SWATCHES'
            }
        ]
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
