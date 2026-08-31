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
                {
                    id: 'trim_to_face',
                    type: 'select',
                    label: 'Trim to Face Edges',
                    default: 'true',
                    options: [
                        { value: 'true', label: 'Yes - overshoot and trim' },
                        { value: 'false', label: 'No - whole units only' }
                    ],
                    hint: 'Yes runs the pattern past the face perimeter and cuts it back to the face edges, filling hips, valleys and verges. No places only whole, untrimmed units.'
                },
                { id: 'lift_mm', type: 'number', label: 'Lift from face (mm)', default: 0, min: 0, max: 100, step: 1 }
            ]
        },
        flooring: {
            label: 'Floor Tiling',
            fields: [
                {
                    id: 'preset_key',
                    type: 'select',
                    label: 'Tile Size Preset',
                    default: 'floor_600x400',
                    options: [
                        { value: 'floor_300x300',  label: 'Tile 300 x 300' },
                        { value: 'floor_450x450',  label: 'Tile 450 x 450' },
                        { value: 'floor_600x600',  label: 'Slab 600 x 600' },
                        { value: 'floor_600x400',  label: 'Slab 600 x 400' },
                        { value: 'floor_900x600',  label: 'Large Format 900 x 600' },
                        { value: 'floor_1000x500', label: 'Large Format 1000 x 500' },
                        { value: 'floor_1200x600', label: 'Large Format 1200 x 600' },
                        { value: 'floor_1200x200', label: 'Plank 1200 x 200' },
                        { value: 'floor_600x100',  label: 'Parquet Block 600 x 100' },
                        { value: 'floor_280x70',   label: 'Parquet Block 280 x 70' },
                        { value: 'floor_200x100',  label: 'Paver 200 x 100' },
                        { value: 'custom',         label: 'Custom' }
                    ],
                    applies: {
                        floor_300x300:  { tile_length_mm: 300,  tile_width_mm: 300 },
                        floor_450x450:  { tile_length_mm: 450,  tile_width_mm: 450 },
                        floor_600x600:  { tile_length_mm: 600,  tile_width_mm: 600 },
                        floor_600x400:  { tile_length_mm: 600,  tile_width_mm: 400 },
                        floor_900x600:  { tile_length_mm: 900,  tile_width_mm: 600 },
                        floor_1000x500: { tile_length_mm: 1000, tile_width_mm: 500 },
                        floor_1200x600: { tile_length_mm: 1200, tile_width_mm: 600 },
                        floor_1200x200: { tile_length_mm: 1200, tile_width_mm: 200 },
                        floor_600x100:  { tile_length_mm: 600,  tile_width_mm: 100 },
                        floor_280x70:   { tile_length_mm: 280,  tile_width_mm: 70 },
                        floor_200x100:  { tile_length_mm: 200,  tile_width_mm: 100 }
                    }
                },
                { id: 'tile_length_mm', type: 'number', label: 'Tile Length (mm)', default: 600, min: 5, max: 5000, step: 5 },
                { id: 'tile_width_mm', type: 'number', label: 'Tile Width (mm)', default: 400, min: 5, max: 5000, step: 5 },
                {
                    id: 'bond',
                    type: 'select',
                    label: 'Bond / Layout',
                    default: 'stack',
                    options: [
                        { value: 'stack',           label: 'Stack Bond - grid, straight in line' },
                        { value: 'running_half',    label: 'Running / Brick Bond - 1/2 offset' },
                        { value: 'running_third',   label: 'Running Bond - 1/3 offset' },
                        { value: 'running_quarter', label: 'Running Bond - 1/4 offset' },
                        { value: 'stack_diagonal',  label: 'Diagonal Grid - 45 degrees' },
                        { value: 'herringbone',     label: 'Herringbone - square to face' },
                        { value: 'herringbone_45',  label: 'Herringbone - 45 degrees' },
                        { value: 'basketweave',     label: 'Basketweave' }
                    ],
                    applies: {
                        stack:           { offset_pct: 0,    rotation_deg: 0 },
                        running_half:    { offset_pct: 50,   rotation_deg: 0 },
                        running_third:   { offset_pct: 33.3, rotation_deg: 0 },
                        running_quarter: { offset_pct: 25,   rotation_deg: 0 },
                        stack_diagonal:  { offset_pct: 0,    rotation_deg: 45 },
                        herringbone:     { offset_pct: 0,    rotation_deg: 0 },
                        herringbone_45:  { offset_pct: 0,    rotation_deg: 45 },
                        basketweave:     { offset_pct: 0,    rotation_deg: 0 }
                    },
                    hint: 'Basketweave keeps the tile length as the block size and fits the tile width to divide it exactly.'
                },
                {
                    id: 'offset_pct',
                    type: 'number',
                    label: 'Course Offset (%)',
                    default: 0,
                    min: 0,
                    max: 100,
                    step: 1,
                    showWhen: { bond: ['stack', 'running_half', 'running_third', 'running_quarter', 'stack_diagonal'] },
                    hint: 'Shift applied to each successive course, as a percentage of the tile length. The offset accumulates, so 33% runs 0, 1/3, 2/3 before repeating.'
                },
                {
                    id: 'rotation_deg',
                    type: 'number',
                    label: 'Pattern Rotation (°)',
                    default: 0,
                    min: -180,
                    max: 180,
                    step: 5,
                    hint: 'Spins the whole layout about the centre of the face. The named 45 degree bonds simply preset this value.'
                },
                {
                    id: 'joint_mm',
                    type: 'number',
                    label: 'Joint / Gap (mm)',
                    default: 0,
                    min: 0,
                    max: 50,
                    step: 0.5,
                    hint: 'Default 0 draws a gapless hatch - every tile shares its edge with its neighbour. Raise it to draw a real grout joint for detail-stage drawings.'
                },
                {
                    id: 'setting_out',
                    type: 'select',
                    label: 'Setting Out',
                    default: 'centre',
                    options: [
                        { value: 'centre', label: 'Centred on face' },
                        { value: 'corner', label: 'From face corner' }
                    ],
                    hint: 'Centred puts a whole tile on the middle of the face so the perimeter cuts balance. From corner starts the first whole tile at the bounding box corner.'
                },
                {
                    id: 'offset_x_mm',
                    type: 'slider',
                    label: 'Offset X (mm)',
                    default: 0,
                    min: -20000,
                    max: 20000,
                    slider_min: -1500,
                    slider_max: 1500,
                    step: 1,
                    hint: 'Slides the whole layout along the tile length axis to line a joint up with a corner. Drag the slider or type any value, positive or negative; the box is not limited to the slider travel.'
                },
                {
                    id: 'offset_y_mm',
                    type: 'slider',
                    label: 'Offset Y (mm)',
                    default: 0,
                    min: -20000,
                    max: 20000,
                    slider_min: -1500,
                    slider_max: 1500,
                    step: 1,
                    hint: 'Same across the tile width axis. Both offsets follow the pattern rotation, so a rotated layout still nudges along its own grid.'
                },
                {
                    id: 'trim_to_face',
                    type: 'select',
                    label: 'Trim to Face Edges',
                    default: 'true',
                    options: [
                        { value: 'true', label: 'Yes - overshoot and trim' },
                        { value: 'false', label: 'No - whole units only' }
                    ],
                    hint: 'Yes runs the pattern past the face perimeter and cuts it back to the face edges, filling hips, valleys and verges. No places only whole, untrimmed units.'
                },
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
                {
                    id: 'trim_to_face',
                    type: 'select',
                    label: 'Trim to Face Edges',
                    default: 'true',
                    options: [
                        { value: 'true', label: 'Yes - overshoot and trim' },
                        { value: 'false', label: 'No - whole units only' }
                    ],
                    hint: 'Yes runs the pattern past the face perimeter and cuts it back to the face edges, filling hips, valleys and verges. No places only whole, untrimmed units.'
                },
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
                {
                    id: 'trim_to_face',
                    type: 'select',
                    label: 'Trim to Face Edges',
                    default: 'true',
                    options: [
                        { value: 'true', label: 'Yes - overshoot and trim' },
                        { value: 'false', label: 'No - whole units only' }
                    ],
                    hint: 'Yes runs the pattern past the face perimeter and cuts it back to the face edges, filling hips, valleys and verges. No places only whole, untrimmed units.'
                },
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
                    ],
                    applies: {
                        slate_600x300_100: { slate_length_mm: 600, slate_width_mm: 300, headlap_mm: 100 },
                        slate_500x300_100: { slate_length_mm: 500, slate_width_mm: 300, headlap_mm: 100 },
                        slate_500x250_100: { slate_length_mm: 500, slate_width_mm: 250, headlap_mm: 100 },
                        slate_460x220_80:  { slate_length_mm: 460, slate_width_mm: 220, headlap_mm: 80 },
                        slate_400x250_75:  { slate_length_mm: 400, slate_width_mm: 250, headlap_mm: 75 }
                    }
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
                {
                    id: 'trim_to_face',
                    type: 'select',
                    label: 'Trim to Face Edges',
                    default: 'true',
                    options: [
                        { value: 'true', label: 'Yes - overshoot and trim' },
                        { value: 'false', label: 'No - whole units only' }
                    ],
                    hint: 'Yes runs the pattern past the face perimeter and cuts it back to the face edges, filling hips, valleys and verges. No places only whole, untrimmed units.'
                },
                { id: 'lift_mm', type: 'number', label: 'Lift from face (mm)', default: 0, min: 0, max: 100, step: 1 }
            ]
        },
        rosemary: {
            label: 'Rosemary Tile Roof',
            fields: [
                {
                    id: 'preset_key',
                    type: 'select',
                    label: 'Preset',
                    default: 'rosemary_265x165_65',
                    options: [
                        { value: 'rosemary_265x165_65', label: 'Rosemary 265x165 - 65 headlap (100 gauge)' },
                        { value: 'rosemary_265x165_75', label: 'Rosemary 265x165 - 75 headlap (95 gauge)' },
                        { value: 'rosemary_265x165_85', label: 'Rosemary 265x165 - 85 headlap (90 gauge)' },
                        { value: 'custom', label: 'Custom' }
                    ],
                    applies: {
                        rosemary_265x165_65: { tile_length_mm: 265, tile_width_mm: 165, headlap_mm: 65 },
                        rosemary_265x165_75: { tile_length_mm: 265, tile_width_mm: 165, headlap_mm: 75 },
                        rosemary_265x165_85: { tile_length_mm: 265, tile_width_mm: 165, headlap_mm: 85 }
                    }
                },
                { id: 'tile_length_mm', type: 'number', label: 'Tile Length (mm)', default: 265, min: 100, max: 600, step: 5 },
                { id: 'tile_width_mm', type: 'number', label: 'Tile Width (mm)', default: 165, min: 50, max: 600, step: 5 },
                { id: 'headlap_mm', type: 'number', label: 'Headlap (mm)', default: 65, min: 1, max: 200, step: 1, hint: 'BS 5534 minimum 65mm headlap for double-lap plain tiles.' },
                { id: 'side_gap_mm', type: 'number', label: 'Side Gap / Shunt (mm)', default: 0, min: 0, max: 20, step: 0.5, hint: 'Set 1.5 for Rosemary 166.5mm linear cover (165 tile + 1.5 shunt).' },
                { id: 'base_thickness_mm', type: 'number', label: 'Base Thickness (mm)', default: 10, min: 0, max: 30, step: 1, hint: 'Visible tile end at the base of each course — drawn as a second line above the bottom edge. Set 0 to disable.' },
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
                {
                    id: 'trim_to_face',
                    type: 'select',
                    label: 'Trim to Face Edges',
                    default: 'true',
                    options: [
                        { value: 'true', label: 'Yes - overshoot and trim' },
                        { value: 'false', label: 'No - whole units only' }
                    ],
                    hint: 'Yes runs the pattern past the face perimeter and cuts it back to the face edges, filling hips, valleys and verges. No places only whole, untrimmed units.'
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
