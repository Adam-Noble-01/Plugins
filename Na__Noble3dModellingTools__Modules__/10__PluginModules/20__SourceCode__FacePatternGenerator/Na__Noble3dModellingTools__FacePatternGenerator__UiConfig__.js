// =============================================================================
// NA NOBLE3D MODELLING TOOLS - FACE PATTERN GENERATOR - UI CONFIG
// =============================================================================
//
// FILE       : Na__Noble3dModellingTools__FacePatternGenerator__UiConfig__.js
// NAMESPACE  : window.Na__FacePattern__UiConfig
// AUTHOR     : Adam Noble - Noble Architecture
// PURPOSE    : Per-pattern field descriptors (type, label, default, min, max,
//              options) consumed by the DynamicUI control panel builder.
// CREATED    : 2026
//
// =============================================================================

(function () {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Pattern Field Descriptors
    // -------------------------------------------------------------------------

    var NA_PATTERN_CONFIG = {
        patio: {
            label: 'Patio',
            fields: [
                { id: 'module_mm', type: 'number', label: 'Module (mm)', default: 300, min: 100, max: 800, step: 50 },
                { id: 'joint_mm', type: 'number', label: 'Joint (mm)', default: 10, min: 0, max: 40, step: 1, hint: 'Set 0 for gapless hatch.' },
                { id: 'lift_mm', type: 'number', label: 'Lift from face (mm)', default: 0, min: 0, max: 100, step: 1 }
            ]
        },
        brickwork: {
            label: 'Brickwork',
            fields: [
                {
                    id: 'unit_system',
                    type: 'select',
                    label: 'Unit System',
                    default: 'imperial',
                    options: [
                        { value: 'imperial', label: 'Imperial' },
                        { value: 'metric', label: 'Metric' }
                    ]
                },
                {
                    id: 'bond_type',
                    type: 'select',
                    label: 'Bond Type',
                    default: 'stretcher',
                    options: [
                        { value: 'stretcher', label: 'Stretcher' },
                        { value: 'flemish', label: 'Flemish' },
                        { value: 'english', label: 'English' }
                    ]
                },
                {
                    id: 'render_mode',
                    type: 'select',
                    label: 'Render Mode',
                    default: 'continuous',
                    options: [
                        { value: 'continuous', label: 'Continuous' },
                        { value: 'artistic', label: 'Artistic' }
                    ]
                },
                { id: 'mortar_mm', type: 'number', label: 'Mortar (mm)', default: 10, min: 0, max: 20, step: 1 },
                { id: 'density_pct', type: 'number', label: 'Density (%)', default: 50, min: 0, max: 100, step: 1 },
                { id: 'lift_mm', type: 'number', label: 'Lift from face (mm)', default: 0, min: 0, max: 100, step: 1 }
            ]
        },
        stonework: {
            label: 'Stonework',
            fields: [
                {
                    id: 'pattern_type',
                    type: 'select',
                    label: 'Pattern Type',
                    default: 'uncoursed',
                    options: [
                        { value: 'uncoursed', label: 'Uncoursed / Snecked' },
                        { value: 'coursed', label: 'Coursed Rough' }
                    ]
                },
                {
                    id: 'stone_size',
                    type: 'select',
                    label: 'Stone Size',
                    default: 'medium',
                    options: [
                        { value: 'small', label: 'Small' },
                        { value: 'medium', label: 'Medium' },
                        { value: 'large', label: 'Large' }
                    ]
                },
                {
                    id: 'render_mode',
                    type: 'select',
                    label: 'Render Mode',
                    default: 'continuous',
                    options: [
                        { value: 'continuous', label: 'Continuous' },
                        { value: 'artistic', label: 'Artistic (Ruined)' }
                    ]
                },
                { id: 'mortar_mm', type: 'number', label: 'Mortar (mm)', default: 15, min: 0, max: 30, step: 1 },
                { id: 'density_pct', type: 'number', label: 'Density (%)', default: 50, min: 0, max: 100, step: 1 },
                { id: 'lift_mm', type: 'number', label: 'Lift from face (mm)', default: 0, min: 0, max: 100, step: 1 }
            ]
        },
        shrub: {
            label: 'Shrub',
            fields: [
                {
                    id: 'shrub_type',
                    type: 'select',
                    label: 'Shrub Type',
                    default: 'round',
                    options: [
                        { value: 'round', label: 'Round' },
                        { value: 'wild', label: 'Wild' },
                        { value: 'topiary', label: 'Topiary' }
                    ]
                },
                { id: 'shrub_width_mm', type: 'number', label: 'Shrub Width (mm)', default: 1200, min: 200, max: 10000, step: 10 },
                { id: 'shrub_height_mm', type: 'number', label: 'Shrub Height (mm)', default: 900, min: 200, max: 10000, step: 10 },
                { id: 'leaf_scale', type: 'number', label: 'Leaf Scale', default: 24, min: 1, max: 120, step: 1 },
                { id: 'roughness_pct', type: 'number', label: 'Roughness (%)', default: 35, min: 0, max: 100, step: 1 },
                { id: 'lift_mm', type: 'number', label: 'Lift from face (mm)', default: 0, min: 0, max: 100, step: 1 }
            ]
        },
        slate: {
            label: 'Slate Roof',
            fields: [
                {
                    id: 'preset_key',
                    type: 'select',
                    label: 'Preset',
                    default: 'slate_500x250_100',
                    options: [
                        { value: 'slate_600x300_100', label: 'Natural 600x300 - 100 headlap' },
                        { value: 'slate_500x300_100', label: 'Natural 500x300 - 100 headlap' },
                        { value: 'slate_500x250_100', label: 'Natural 500x250 - 100 headlap' },
                        { value: 'slate_460x220_80', label: 'Natural 460x220 - 80 headlap' },
                        { value: 'slate_400x250_75', label: 'Natural 400x250 - 75 headlap' },
                        { value: 'custom', label: 'Custom' }
                    ]
                },
                { id: 'slate_length_mm', type: 'number', label: 'Slate Length (mm)', default: 500, min: 100, max: 2000, step: 5 },
                { id: 'slate_width_mm', type: 'number', label: 'Slate Width (mm)', default: 250, min: 100, max: 2000, step: 5 },
                { id: 'headlap_mm', type: 'number', label: 'Headlap (mm)', default: 100, min: 1, max: 1000, step: 1 },
                { id: 'side_gap_mm', type: 'number', label: 'Side Gap (mm)', default: 0, min: 0, max: 200, step: 1 },
                {
                    id: 'stagger',
                    type: 'select',
                    label: 'Half Bond Stagger',
                    default: 'true',
                    options: [
                        { value: 'true', label: 'Yes' },
                        { value: 'false', label: 'No' }
                    ]
                },
                { id: 'lift_mm', type: 'number', label: 'Lift from face (mm)', default: 0, min: 0, max: 100, step: 1 }
            ]
        }
    };

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public API
    // -------------------------------------------------------------------------

    // FUNCTION | Return Pattern Key / Label Pairs for the Top-Level Selector
    // ------------------------------------------------------------
    function na_patternEntries() {
        return Object.keys(NA_PATTERN_CONFIG).map(function (key) {
            return { key: key, label: NA_PATTERN_CONFIG[key].label };
        });
    }
    // ------------------------------------------------------------

    // FUNCTION | Return the Field Descriptor Set for a Pattern Key
    // ------------------------------------------------------------
    function na_getPatternConfig(patternKey) {
        return NA_PATTERN_CONFIG[patternKey] || NA_PATTERN_CONFIG.patio;
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    window.Na__FacePattern__UiConfig = {
        na_patternEntries: na_patternEntries,
        na_getPatternConfig: na_getPatternConfig
    };

})();

// =============================================================================
// END OF FILE
// =============================================================================
