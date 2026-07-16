/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR SLIDING DOOR SYSTEM - UI CONFIGURATION
   =============================================================================

   FILE       : Na__AssemblyStudio__ExtSlide__UiSystem__Config__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Sliding-door section controls including shared fielded-panel
                settings applied to every leaf in the set.
   CREATED    : 17-May-2026

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

    var NA_SLIDING_DOOR_CONFIG = [
        {
            id: 'sliding_door_mode',
            label: 'Slide Direction',
            type: 'binary_toggle',
            default: 'FrontSlidesRight',
            options: [
                { value: 'FrontSlidesLeft', label: 'Slide Left' },
                { value: 'FrontSlidesRight', label: 'Slide Right' }
            ],
            section: 'Opening'
        },
        na_slider('sliding_door_panel_thickness_mm', 'Panel Thickness', 30, 80, 1, 50, 'Leaf Construction'),
        na_slider('sliding_door_rear_setback_mm', 'Rear Panel Setback', 30, 200, 1, 60, 'Leaf Construction'),
        na_select('sliding_door_leaf_composition', 'Leaf Composition', 'FullyGlazed', na_compositions, 'Leaf Construction'),
        na_slider('sliding_door_stile_width_mm', 'Perimeter Stile Width', 40, 250, 5, 95, 'Leaf Construction'),
        na_slider('sliding_door_head_rail_mm', 'Top Rail Width', 40, 300, 5, 95, 'Leaf Construction'),
        na_slider('sliding_door_base_rail_mm', 'Bottom Rail Width', 40, 400, 5, 200, 'Leaf Construction'),
        na_slider('sliding_door_mid_rail_width_mm', 'Separating Midrail Width', 40, 300, 5, 120, 'Leaf Construction'),

        na_select('sliding_door_panel_output_mode', 'Panel Output', 'ThreeDimensional', [
            { value: 'Linework', label: 'Linework' },
            { value: 'ThreeDimensional', label: 'Three Dimensional' }
        ], 'Fielded Panels'),
        na_select('sliding_door_panel_profile', 'Panel Profile', 'RaisedBevelled', [
            { value: 'RaisedBevelled', label: 'Raised Bevelled' },
            { value: 'RecessedShaker', label: 'Recessed Shaker' }
        ], 'Fielded Panels'),
        na_select('sliding_door_panel_preset', 'Panel Layout', 'OnePanel', na_presets, 'Fielded Panels'),
        Object.assign(na_slider('sliding_door_panel_columns', 'Custom Columns', 1, 6, 1, 1, 'Fielded Panels'), { unit: '' }),
        Object.assign(na_slider('sliding_door_panel_rows', 'Custom Rows', 1, 6, 1, 1, 'Fielded Panels'), { unit: '' }),
        na_slider('sliding_door_fielded_section_height_mm', 'Fielded Section Height', 100, 1800, 5, 300, 'Fielded Panels'),
        na_slider('sliding_door_panel_inset_mm', 'Panel Inset', 5, 100, 1, 25, 'Fielded Panels'),
        na_slider('sliding_door_panel_depth_mm', 'Panel Depth', 1, 30, 1, 12, 'Fielded Panels'),
        na_slider('sliding_door_panel_bevel_width_mm', 'Panel Bevel Width', 2, 60, 1, 18, 'Fielded Panels')
    ];

    window.NA_SLIDING_DOOR_CONFIG = NA_SLIDING_DOOR_CONFIG;
    console.log('[NA_EXT_SLIDE] UiSystem Config loaded (fielded panels).');
}());
