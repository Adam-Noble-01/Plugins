/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR SINGLE DOOR SYSTEM - UI CONFIGURATION
   =============================================================================

   FILE       : Na__AssemblyStudio__ExtSingleDoor__UiSystem__Config__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Fielded-panel UI controls for standalone exterior single doors.
                Mirrors ExtDouble fielded controls under the single_door_*
                prefix (one leaf, no left/right overrides).
   CREATED    : 2026

   DESCRIPTION:
   - Replaces the legacy door_panel_* casement-panel controls.
   - Visible when ui_exterior_door_type === Single / ext_single_door_mode.
   - Consumed by WindowSystem MainUiLogic via window.NA_DOOR_PANEL_CONFIG.

   ============================================================================= */

(function () {
    'use strict';

    function na_select(id, label, defaultValue, options, section) {
        return { id: id, label: label, type: 'select', default: defaultValue, options: options, section: section };
    }

    function na_slider(id, label, minimum, maximum, step, defaultValue, section) {
        return {
            id: id, label: label, type: 'slider', min: minimum, max: maximum,
            step: step, default: defaultValue, unit: 'mm', section: section
        };
    }

    function na_checkbox(id, label, defaultValue, section) {
        return { id: id, label: label, type: 'toggle', default: defaultValue, section: section };
    }

    var na_compositions = [
        { value: 'FullyGlazed', label: 'Fully Glazed' },
        { value: 'GlazedOverFielded', label: 'Glazed Over Fielded' },
        { value: 'FullyFielded', label: 'Fully Fielded' }
    ];
    var na_presets = [
        { value: 'OnePanel', label: 'One Panel' },
        { value: 'TwoVertical', label: 'Two Vertical' },
        { value: 'TwoHorizontal', label: 'Two Horizontal' },
        { value: 'FourPanel', label: 'Four Panel' },
        { value: 'SixPanel', label: 'Six Panel' },
        { value: 'Custom', label: 'Custom' }
    ];

    var na_controls = [
        Object.assign(na_select('single_door_swing_side', 'Swing Side', 'Left', [
            { value: 'Left', label: 'Left' }, { value: 'Right', label: 'Right' }
        ], 'Opening'), { type: 'binary_toggle' }),
        Object.assign(na_select('single_door_swing_direction', 'Swing Direction', 'Inward', [
            { value: 'Inward', label: 'Inward' }, { value: 'Outward', label: 'Outward' }
        ], 'Opening'), { type: 'binary_toggle' }),
        Object.assign(na_slider('single_door_opening_angle_deg', 'Opening Angle', 0, 180, 5, 90, 'Opening'), { unit: '°' }),
        na_slider('single_door_hinge_projection_mm', 'Hinge Projection', 0, 150, 5, 0, 'Opening'),

        na_checkbox('single_door_show_swing_arcs', 'Show 2D Swing Arcs', true, 'Swing Output'),
        na_checkbox('single_door_create_open_state_copy', 'Create Open-State Copy', true, 'Swing Output'),

        na_select('single_door_leaf_composition', 'Leaf Composition', 'GlazedOverFielded', na_compositions, 'Leaf Construction'),
        na_slider('single_door_leaf_thickness_mm', 'Leaf Thickness', 30, 80, 1, 50, 'Leaf Construction'),
        na_slider('single_door_panel_stile_width_mm', 'Perimeter Stile Width', 40, 250, 5, 95, 'Leaf Construction'),
        na_slider('single_door_panel_top_rail_width_mm', 'Top Rail Width', 40, 300, 5, 95, 'Leaf Construction'),
        na_slider('single_door_panel_bottom_rail_width_mm', 'Bottom Rail Width', 40, 400, 5, 150, 'Leaf Construction'),
        na_slider('single_door_mid_rail_width_mm', 'Separating Midrail Width', 40, 300, 5, 120, 'Leaf Construction'),

        na_select('single_door_panel_output_mode', 'Panel Output', 'ThreeDimensional', [
            { value: 'Linework', label: 'Linework' },
            { value: 'ThreeDimensional', label: 'Three Dimensional' }
        ], 'Fielded Panels'),
        na_select('single_door_panel_profile', 'Panel Profile', 'RaisedBevelled', [
            { value: 'RaisedBevelled', label: 'Raised Bevelled' },
            { value: 'RecessedShaker', label: 'Recessed Shaker' }
        ], 'Fielded Panels'),
        na_select('single_door_panel_preset', 'Panel Layout', 'OnePanel', na_presets, 'Fielded Panels'),
        Object.assign(na_slider('single_door_panel_columns', 'Custom Columns', 1, 6, 1, 1, 'Fielded Panels'), { unit: '' }),
        Object.assign(na_slider('single_door_panel_rows', 'Custom Rows', 1, 6, 1, 1, 'Fielded Panels'), { unit: '' }),
        na_slider('single_door_fielded_section_height_mm', 'Fielded Section Height', 100, 1800, 5, 300, 'Fielded Panels'),
        na_slider('single_door_panel_inset_mm', 'Panel Inset', 5, 100, 1, 25, 'Fielded Panels'),
        na_slider('single_door_panel_depth_mm', 'Panel Depth', 1, 30, 1, 12, 'Fielded Panels'),
        na_slider('single_door_panel_bevel_width_mm', 'Panel Bevel Width', 2, 60, 1, 18, 'Fielded Panels'),

        na_select('single_door_handle_asset_key', 'Handle Asset', 'Na__ExteriorDoor__Handle__Scroll', [], 'Hardware'),
        na_slider('single_door_handle_height_mm', 'Handle Height', 700, 1400, 5, 900, 'Hardware'),
        na_slider('single_door_handle_backset_mm', 'Handle Position from Latch Stile', 20, 250, 5, 40, 'Hardware'),
        {
            id: 'single_door_leaf_material_id',
            label: 'Leaf Finish',
            type: 'material_cards',
            default: 'MAT120__GenericWood',
            materialsSource: 'NA_FRAME_FINISH_SWATCHES',
            section: 'Finishes'
        },
        {
            id: 'single_door_handle_material_id',
            label: 'Handle Finish',
            type: 'material_cards',
            default: 'MAT615__Metal__Ironmongery__Chrome',
            materialsSource: 'NA_HANDLE_FINISH_SWATCHES',
            section: 'Finishes'
        }
    ];

    window.NA_DOOR_PANEL_CONFIG = na_controls;
    window.NA_EXT_SINGLE_DOOR_CONFIG = na_controls;
    window.Na__ExtSingleDoor__UiConfig = Object.freeze({
        na_controls: na_controls,
        na_compositions: na_compositions,
        na_presets: na_presets
    });
}());
