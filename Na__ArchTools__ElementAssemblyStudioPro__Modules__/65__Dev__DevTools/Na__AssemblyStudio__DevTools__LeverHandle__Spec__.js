/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - LEVER HANDLE SPEC
   =============================================================================

   FILE       : Na__AssemblyStudio__DevTools__LeverHandle__Spec__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Regression suite for V2.5.0 - the Curved Lever on Long Plate
                handle: its asset contract and sizes, the exterior door preview
                drawing a handle from its own Elevation2D paths, and the Scroll
                keeping its drawn schematic. V2.5.1 - the interior door preview
                handed as the 3D builds it, and the Scroll placed 60 in from the
                latch on an interior door.
   CREATED    : 02-Nov-2026

   HOW TO RUN (from anywhere, needs only Node - no install, no dependencies):

       node "65__Dev__DevTools/Na__AssemblyStudio__DevTools__LeverHandle__Spec__.js"

   Exits 0 when everything passes, 1 otherwise.

   The suite loads the SHIPPED source files and the SHIPPED asset JSON unmodified
   against a minimal DOM / window stub, so it tests what actually runs in the
   dialog. The 3D build itself needs SketchUp; see the devlog's How to Test.

   ============================================================================= */

'use strict';

const fs   = require('fs');
const path = require('path');


// -----------------------------------------------------------------------------
// REGION | Harness
// -----------------------------------------------------------------------------

const NA_MODULES = path.resolve(__dirname, '..', '02__Src__AppModules');
const NA_ASSETS  = path.resolve(__dirname, '..', '04__Data__AssetLibrary');
const NA_LEVER   = 'Na__ExteriorDoor__Handle__LeverOnLongPlate';
const NA_SCROLL  = 'Na__ExteriorDoor__Handle__Scroll';
const NA_KEYHOLE_LINE = 'MTE105__LineColour__LightMidGrey__L70';

let na_pass = 0;
let na_fail = 0;

// HELPER FUNCTION | Assert Deep Equality and Record the Outcome
// ------------------------------------------------------------
function na_expect(label, actual, expected) {
    if (JSON.stringify(actual) === JSON.stringify(expected)) {
        na_pass += 1;
        return;
    }
    na_fail += 1;
    console.log('  FAIL  ' + label + '\n        got  ' + JSON.stringify(actual) +
                '\n        want ' + JSON.stringify(expected));
}
// ---------------------------------------------------------------

// HELPER FUNCTION | Assert Two Numbers Agree Within a Tolerance
// ------------------------------------------------------------
function na_close(label, actual, expected, tolerance) {
    na_expect(label + ' (' + actual + ')', Math.abs(Number(actual) - Number(expected)) <= (tolerance || 0.01), true);
}
// ---------------------------------------------------------------

// HELPER FUNCTION | Print a Suite Heading
// ------------------------------------------------------------
function na_suite(title) {
    console.log('\n' + title);
}
// ---------------------------------------------------------------

// HELPER FUNCTION | A Recording SVG Node
// ------------------------------------------------------------
function na_make_node(tag) {
    const node = {
        tag: tag, attrs: {}, children: [], textContent: '',
        setAttribute: (name, value) => { node.attrs[name] = value; },
        appendChild : (child) => { node.children.push(child); return child; },
        removeChild : (child) => {
            const index = node.children.indexOf(child);
            if (index >= 0) node.children.splice(index, 1);
            return child;
        }
    };
    Object.defineProperty(node, 'firstChild', { get: () => (node.children.length ? node.children[0] : null) });
    return node;
}
// ---------------------------------------------------------------

// HELPER FUNCTION | Flatten a Rendered Node Tree
// ------------------------------------------------------------
function na_flatten(node, collected) {
    collected = collected || [];
    node.children.forEach((child) => {
        collected.push(child);
        na_flatten(child, collected);
    });
    return collected;
}
// ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | DOM Stub and Shipped Modules
// -----------------------------------------------------------------------------

global.window   = global;
global.document = {
    createElementNS  : (ns, tag) => na_make_node(tag),
    createElement    : () => ({ appendChild: () => {} }),
    getElementById   : () => null,
    querySelector    : () => null,
    querySelectorAll : () => [],
    addEventListener : () => {},
    readyState       : 'loading'
};
window.Na__Ui__Controls      = { na_createControl: () => '' };
window.Na__Ui__Events        = { na_attachEventListeners: () => {} };
window.Na__Ui__SectionLayout = { na_register: () => {} };

const NA_REQUESTS = [];
let   na_redraws  = 0;
window.sketchup    = { na_requestDoorHandlePreviewAsset: (key) => { NA_REQUESTS.push(key); } };
global.Na_DynamicUI = { na_getConfig: () => ({}) };
global.Na_Viewport  = { na_render: () => { na_redraws += 1; } };

const NA_SOURCES = [
    '03__AppUtils/Na__AssemblyStudio__AppUtils__ArithmeticEvaluator__.js',
    '05__Viewport__2dPreviewEngine/Na__AssemblyStudio__Viewport__SvgHelpers__.js',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__UiSystem__Config__.js',
    '31__System__ExteriorSingleDoorSystem/Na__AssemblyStudio__ExtSingleDoor__UiSystem__Config__.js',
    '34__System__ExteriorDoubleDoorSystem/Na__AssemblyStudio__ExtDouble__UiSystem__Config__.js',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__Viewport__MullionMath__.js',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__Viewport__CasementMath__.js',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__Viewport__GlazebarMath__.js',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__Viewport__SvgGenerator__.js',
    '30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__UiSystem__LeafConfigResolver__.js',
    '30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__Viewport__ElevationGenerator__.js',
    '34__System__ExteriorDoubleDoorSystem/Na__AssemblyStudio__ExtDouble__UiSystem__LeafConfigResolver__.js',
    '34__System__ExteriorDoubleDoorSystem/Na__AssemblyStudio__ExtDouble__Viewport__ElevationGenerator__.js',
    '31__System__ExteriorSingleDoorSystem/Na__AssemblyStudio__ExtSingleDoor__UiSystem__LeafConfigResolver__.js',
    '31__System__ExteriorSingleDoorSystem/Na__AssemblyStudio__ExtSingleDoor__Viewport__ElevationGenerator__.js',
    '40__System__InteriorDoorSystem/Na__AssemblyStudio__InteriorDoorSystem__UiSystem__Config__.js',
    '40__System__InteriorDoorSystem/Na__AssemblyStudio__InteriorDoorSystem__UiSystem__Bridge__.js',
    '40__System__InteriorDoorSystem/Na__AssemblyStudio__InteriorDoorSystem__Viewport__ElevationGenerator__.js'
];
const na_console_log = console.log;
console.log = () => {};
NA_SOURCES.forEach((relativePath) => {
    // eslint-disable-next-line no-eval
    (0, eval)('(function(){' + fs.readFileSync(path.join(NA_MODULES, relativePath), 'utf8') + '\n})()');
});
console.log = na_console_log;

const NA_ASSET  = JSON.parse(fs.readFileSync(path.join(NA_ASSETS, 'ExteriorDoor__Handles__', NA_LEVER + '__.json'), 'utf8'));
const NA_SCROLL_ASSET = JSON.parse(fs.readFileSync(path.join(NA_ASSETS, 'ExteriorDoor__Handles__', NA_SCROLL + '__.json'), 'utf8'));
const NA_META   = NA_ASSET.Na__Asset__Metadata;
const NA_MESH   = NA_ASSET.Na__Asset__Mesh3D;
const NA_VERTEX = {};
NA_MESH.Na__Geometry__Vertices.forEach((vertex) => { NA_VERTEX[vertex.VertexId] = vertex; });

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Helpers
// -----------------------------------------------------------------------------

// HELPER FUNCTION | A Hinged Door Config Seeded From Its Own Controls
// ------------------------------------------------------------
function na_hinged(prefix, array, modeKey, overrides) {
    const seeded = {};
    window[array].forEach((item) => {
        if (item && typeof item.id === 'string' && item.id.indexOf(prefix) === 0) seeded[item.id] = item.default;
    });
    const config = { width_mm: 1000, height_mm: 2100, frame_thickness_mm: 50, frame_depth_mm: 70,
                     frame_wall_inset_mm: 0, has_cill: true, cill_height_mm: 50, cill_depth_mm: 50,
                     show_dimensions: false, horizontal_glaze_bars: 0, vertical_glaze_bars: 0, glaze_bar_width_mm: 25, glazebar_inset_mm: 10 };
    config[modeKey] = true;
    return Object.assign(config, seeded, overrides || {});
}
// ---------------------------------------------------------------

// HELPER FUNCTION | Render a Door and Return Its Nodes
// ------------------------------------------------------------
function na_render(generator, config) {
    const root = na_make_node('svg');
    generator.na_render(root, config);
    return na_flatten(root);
}
// ---------------------------------------------------------------

// HELPER FUNCTION | A Single Door Config With a Chosen Handle
// ------------------------------------------------------------
function na_single(key, side) {
    return na_hinged('single_door_', 'NA_EXT_SINGLE_DOOR_CONFIG', 'ext_single_door_mode',
                     { single_door_handle_asset_key: key, single_door_swing_side: side || 'Left' });
}
// ---------------------------------------------------------------

// HELPER FUNCTION | Points of an SVG Polygon
// ------------------------------------------------------------
function na_points(node) {
    return String(node.attrs.points).split(' ').map((pair) => pair.split(',').map(Number));
}
// ---------------------------------------------------------------

// HELPER FUNCTION | The Asset's Polygons as Drawn: Those Filled With a Sentinel Finish
// ------------------------------------------------------------
const NA_FINISH = '#123456';
function na_handle_polygons(nodes) {
    return nodes.filter(node => node.tag === 'polygon' && node.attrs.fill === NA_FINISH);
}
// ---------------------------------------------------------------

// HELPER FUNCTION | The Drawn Scroll Schematic: Its Rose Circle
// ------------------------------------------------------------
function na_schematic_roses(nodes) {
    return nodes.filter(node => node.tag === 'circle' && node.attrs.fill === NA_FINISH && Number(node.attrs.r) === 10);
}
// ---------------------------------------------------------------

window.NA_HANDLE_FINISH_SWATCHES = [{ id: 'FINISH', hex: NA_FINISH }];

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Asset Contract
// -----------------------------------------------------------------------------

na_suite('Asset metadata matches the Scroll\'s contract');
na_expect('type', NA_META.Na__Asset__Type, 'DoorHandle');
na_expect('code', NA_META.Na__Asset__Code, 'NA__HDL__003');
na_expect('has a label for the dropdown', NA_META.Na__Asset__Name.length > 0, true);
na_expect('flags', [NA_META.Na__Asset__Has2dPlan, NA_META.Na__Asset__Has2dElevation, NA_META.Na__Asset__Has2dProfile, NA_META.Na__Asset__Has3d], [true, true, false, true]);
na_expect('same finishes', NA_META.Na__Asset__AvailableFinishes, NA_SCROLL_ASSET.Na__Asset__Metadata.Na__Asset__AvailableFinishes);
['Na__PanelPlacement__DefaultHeight_mm', 'Na__PanelPlacement__CorrectionRotZ_deg', 'Na__PanelPlacement__RightHand', 'Na__PanelPlacement__LeftHand'].forEach((key) => {
    na_expect('same placement: ' + key, NA_META[key], NA_SCROLL_ASSET.Na__Asset__Metadata[key]);
});

na_suite('The builder\'s mesh contract holds');
const NA_FACES = NA_MESH.Na__Geometry__Faces;
const NA_EDGES = NA_MESH.Na__Geometry__Edges;
na_expect('every vertex id is unique', Object.keys(NA_VERTEX).length, NA_MESH.Na__Geometry__Vertices.length);
na_expect('every face has 3 or more known vertices', NA_FACES.filter(face => face.OuterLoop_VertexIds.length < 3 || face.OuterLoop_VertexIds.some(id => !NA_VERTEX[id])).length, 0);
na_expect('every edge ends on known vertices', NA_EDGES.filter(edge => !NA_VERTEX[edge.StartVertex] || !NA_VERTEX[edge.EndVertex]).length, 0);
na_expect('no face carries a material: the finish is the instance\'s', NA_FACES.filter(face => face.MaterialName !== '').length, 0);
na_expect('counts agree', [NA_MESH.Na__Geometry__Counts.Na__Geometry__VertexCount, NA_MESH.Na__Geometry__Counts.Na__Geometry__FaceCount, NA_MESH.Na__Geometry__Counts.Na__Geometry__EdgeCount],
          [NA_MESH.Na__Geometry__Vertices.length, NA_FACES.length, NA_EDGES.length]);
const na_out_of_plane = NA_FACES.filter(face => face.OuterLoop_VertexIds.length === 4).map((face) => {
    const [a, b, c, d] = face.OuterLoop_VertexIds.map(id => [NA_VERTEX[id].PosX_mm, NA_VERTEX[id].PosY_mm, NA_VERTEX[id].PosZ_mm]);
    const e1 = [c[0] - a[0], c[1] - a[1], c[2] - a[2]];
    const e2 = [d[0] - b[0], d[1] - b[1], d[2] - b[2]];
    const n  = [e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0]];
    const ln = Math.hypot(n[0], n[1], n[2]) || 1;
    return Math.abs(((a[0] - b[0]) * n[0] + (a[1] - b[1]) * n[1] + (a[2] - b[2]) * n[2]) / ln);
});
na_expect('every quad is flat to the 0.001 inch add_face needs', Math.max.apply(null, na_out_of_plane) < 0.0254, true);

na_suite('Sizes are the maker\'s');
const NA_ALL = NA_MESH.Na__Geometry__Vertices;
const NA_PLATE = NA_FACES.filter(face => face.Na__Object__NodeId === 'OBJ0002');
const na_ids_of = faces => Array.from(new Set(faces.reduce((all, face) => all.concat(face.OuterLoop_VertexIds), [])));
const NA_PLATE_V = na_ids_of(NA_PLATE).map(id => NA_VERTEX[id]);
const na_span = (list, key) => [Math.min.apply(null, list.map(v => v[key])), Math.max.apply(null, list.map(v => v[key]))];
na_expect('plate 30 wide', na_span(NA_PLATE_V, 'PosX_mm'), [-15, 15]);
na_expect('plate 245 long, spindle 93 below the top', na_span(NA_PLATE_V, 'PosY_mm'), [-152, 93]);
na_expect('plate 8 thick, its back on the door', na_span(NA_PLATE_V, 'PosZ_mm'), [0, 8]);
na_expect('nothing behind the door face', Math.min.apply(null, NA_ALL.map(v => v.PosZ_mm)), 0);
na_close('59 projection from the plate', Math.max.apply(null, NA_ALL.map(v => v.PosZ_mm)) - 8, 59, 0.1);
na_close('lever tip 113 from the spindle', Math.max.apply(null, NA_ALL.map(v => v.PosX_mm)), 113, 0.3);

na_suite('Adam: the collar fits between the plate\'s roll lines');
const NA_LEVER_V = na_ids_of(NA_FACES.filter(face => face.Na__Object__NodeId === 'OBJ0003')).map(id => NA_VERTEX[id]);
const NA_COLLAR  = NA_LEVER_V.filter(v => v.PosZ_mm === 8);
na_expect('a whole ring sits on the plate', NA_COLLAR.length, 24);
na_expect('inside the 24 mm flat each side', Math.max.apply(null, NA_COLLAR.map(v => Math.abs(v.PosX_mm))) < 12, true);

na_suite('Adam: a solid plate, the keyhole a 2D shape in his light mid grey line');
const NA_KEY_FACES = NA_FACES.filter(face => face.Na__Object__NodeId === 'OBJ0004');
const NA_KEY_V     = na_ids_of(NA_KEY_FACES).map(id => NA_VERTEX[id]);
const NA_COLOURED  = NA_EDGES.filter(edge => edge.EdgeColourId);
na_expect('one flat face', NA_KEY_FACES.length, 1);
na_expect('stands off the plate', NA_KEY_V.every(v => v.PosZ_mm === 8.2), true);
na_expect('no holes in any face', NA_FACES.filter(face => face.InnerLoops.length).length, 0);
na_expect('only its edges carry a line colour', NA_COLOURED.length, NA_KEY_V.length);
na_expect('and that colour is MTE105', Array.from(new Set(NA_COLOURED.map(edge => edge.EdgeColourId))), [NA_KEYHOLE_LINE]);
na_close('92 below the spindle: round top', Math.max.apply(null, NA_KEY_V.map(v => v.PosY_mm)), -92 + 9.5, 0.01);

na_suite('2D blocks');
const NA_ELEVATION = NA_ASSET.Na__Asset__Elevation2D.Na__Geometry__Paths;
na_expect('elevation draws in order', NA_ELEVATION.map(p => p.VertexName), ['Na__Elevation__Backplate', 'Na__Elevation__Keyhole', 'Na__Elevation__Collar', 'Na__Elevation__Lever']);
na_expect('only the keyhole names a line', NA_ELEVATION.map(p => p.EdgeColourId || null), [null, NA_KEYHOLE_LINE, null, null]);
na_expect('plan has plate and lever', NA_ASSET.Na__Asset__Plan2D.Na__Geometry__Paths.map(p => p.VertexName), ['Na__Plan__Backplate', 'Na__Plan__Lever']);
na_close('plan projection matches the mesh', NA_ASSET.Na__Asset__Plan2D.Na__Geometry__BoundingBox.Na__Geometry__MaxY_mm, Math.max.apply(null, NA_ALL.map(v => v.PosZ_mm)), 0.01);
na_close('elevation reach matches the mesh', NA_ASSET.Na__Asset__Elevation2D.Na__Geometry__BoundingBox.Na__Geometry__MaxX_mm, Math.max.apply(null, NA_ALL.map(v => v.PosX_mm)), 0.01);

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Exterior Door Preview
// -----------------------------------------------------------------------------

const Single = window.Na__ExtSingleDoor__ElevationGenerator;
const Double = window.Na__ExtDouble__ElevationGenerator;

na_suite('The Scroll keeps its schematic and never asks for paths');
const NA_INTERIOR = 'Na__InteriorDoor__Handle__Default';
window.na_receiveDoorHandleAssetOptions(JSON.stringify({
    defaultKey: NA_INTERIOR,
    options: [{ value: NA_INTERIOR, label: 'Default', hasElevation: true }, { value: NA_SCROLL, label: 'Scroll', hasElevation: false }, { value: NA_LEVER, label: 'Lever', hasElevation: true }]
}));
na_expect('options record which handles have paths', window.NA_DOOR_HANDLE_KEYS_WITH_ELEVATION, { [NA_INTERIOR]: true, [NA_LEVER]: true });
na_expect('options redraw the exterior preview', na_redraws > 0, true);
na_expect('the interior door still asks for its own selected handle', NA_REQUESTS, [NA_INTERIOR]);
NA_REQUESTS.length = 0;
const na_finish = config => Object.assign(config, { single_door_handle_material_id: 'FINISH', double_door_handle_material_id: 'FINISH' });
let nodes = na_render(Single, na_finish(na_single(NA_SCROLL)));
na_expect('rose drawn', na_schematic_roses(nodes).length, 1);
na_expect('no asset polygons', na_handle_polygons(nodes).length, 0);
na_expect('nothing asked for', NA_REQUESTS, []);

na_suite('The lever asks for its paths once, then draws them');
nodes = na_render(Single, na_finish(na_single(NA_LEVER)));
na_expect('schematic until they arrive', na_schematic_roses(nodes).length, 1);
na_expect('asked', NA_REQUESTS, [NA_LEVER]);
na_render(Single, na_finish(na_single(NA_LEVER)));
na_expect('not asked twice', NA_REQUESTS, [NA_LEVER]);

const na_redraws_before = na_redraws;
// Ruby sends each path's line colour as a hex, looked up from the SSOT
const NA_SSOT = JSON.parse(fs.readFileSync(path.resolve(__dirname, '..', '..', 'Na__Common__DataLib__CoreSuEntityStandards', 'Na__DataLib__CoreIndex__EdgeMaterials__.json'), 'utf8'));
const na_ssot_hex = (function find(node) {
    if (!node || typeof node !== 'object') return null;
    if (node.SketchUpName === NA_KEYHOLE_LINE) return node.HexValue;
    return Object.keys(node).reduce((hit, key) => hit || find(node[key]), null);
}(NA_SSOT));
na_expect('the SSOT has the keyhole line', typeof na_ssot_hex, 'string');
const na_as_sent = block => Object.assign({}, block, { Na__Geometry__Paths: block.Na__Geometry__Paths.map(item => (item.EdgeColourId ? Object.assign({}, item, { EdgeColourHex: na_ssot_hex }) : item)) });
window.na_receiveDoorHandlePreviewAsset(JSON.stringify({ assetKey: NA_LEVER, Na__Asset__Plan2D: na_as_sent(NA_ASSET.Na__Asset__Plan2D), Na__Asset__Elevation2D: na_as_sent(NA_ASSET.Na__Asset__Elevation2D), warnings: [] }));
na_expect('the answer redraws the exterior preview', na_redraws > na_redraws_before, true);

nodes = na_render(Single, na_finish(na_single(NA_LEVER, 'Left')));
let polys = na_handle_polygons(nodes);
na_expect('schematic gone', na_schematic_roses(nodes).length, 0);
na_expect('backplate, keyhole, collar, lever', polys.length, 4);

// Door 1000 wide with a 50 frame: a left leaf's latch is 950 from the left of the opening, spindle 40 back
const na_spindle = (points) => {
    const xs = points.map(p => p[0]);
    return (Math.min.apply(null, xs) + Math.max.apply(null, xs)) / 2;
};
const na_left_plate = na_points(polys[0]);
const na_left_x     = na_spindle(na_left_plate);
const na_left_lever = na_points(polys[3]).map(p => p[0]);
na_close('plate drawn 30 wide', Math.max.apply(null, na_left_plate.map(p => p[0])) - Math.min.apply(null, na_left_plate.map(p => p[0])), 30, 0.01);
na_close('plate drawn 245 tall', Math.max.apply(null, na_left_plate.map(p => p[1])) - Math.min.apply(null, na_left_plate.map(p => p[1])), 245, 0.01);
na_close('left-hung: lever points left, at the hinge', Math.min.apply(null, na_left_lever) - na_left_x, -NA_ASSET.Na__Asset__Elevation2D.Na__Geometry__BoundingBox.Na__Geometry__MaxX_mm, 0.01);
na_expect('keyhole drawn in its line colour', polys[1].attrs.stroke, na_ssot_hex);
na_expect('the rest in the door\'s outline', [polys[0].attrs.stroke, polys[2].attrs.stroke, polys[3].attrs.stroke].every(stroke => stroke !== na_ssot_hex), true);

polys = na_handle_polygons(na_render(Single, na_finish(na_single(NA_LEVER, 'Right'))));
const na_right_x     = na_spindle(na_points(polys[0]));
const na_right_lever = na_points(polys[3]).map(p => p[0]);
na_close('right-hung: lever points right, at the hinge', Math.max.apply(null, na_right_lever) - na_right_x, NA_ASSET.Na__Asset__Elevation2D.Na__Geometry__BoundingBox.Na__Geometry__MaxX_mm, 0.01);
na_expect('right-hung spindle sits left of left-hung\'s', na_right_x < na_left_x, true);

na_suite('The double door draws through the same code');
polys = na_handle_polygons(na_render(Double, na_finish(na_hinged('double_door_', 'NA_DOUBLE_DOOR_CONFIG', 'ext_double_door_mode', { width_mm: 1800, double_door_handle_asset_key: NA_LEVER }))));
na_expect('whole handles only', polys.length % 4, 0);
na_expect('at least one', polys.length >= 4, true);

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Interior Door Preview and 3D Placement
// -----------------------------------------------------------------------------

// HELPER FUNCTION | An Interior Door Config With a Chosen Handle
// ------------------------------------------------------------
function na_interior(key, side, overrides) {
    return Object.assign({
        Na__DoorConfig__OpeningWidth_mm: 850, Na__DoorConfig__OpeningHeight_mm: 2100, Na__DoorConfig__LiningThickness_mm: 35,
        Na__DoorConfig__HandleHeight_mm: 900, Na__DoorConfig__HandleMaterialId: 'FINISH',
        Na__DoorConfig__HandleAssetKey: key, Na__DoorConfig__SwingSide: side
    }, overrides || {});
}
// ---------------------------------------------------------------

const Interior = window.Na_DoorElevationGenerator;
const NA_REACH = NA_ASSET.Na__Asset__Elevation2D.Na__Geometry__BoundingBox.Na__Geometry__MaxX_mm;
const na_xs_of = node => na_points(node).map(p => p[0]);

// An 850 door with a 35 lining: the leaf is 780 wide, hung from x 35 or x 815.
// The preview draws it 200 further right, its padding.
na_suite('Interior door preview: a left-hung door has its handle at the right, lever pointing left');
nodes = na_render(Interior, na_interior(NA_LEVER, 'Left'));
polys = na_handle_polygons(nodes);
const na_panel = nodes.filter(node => node.tag === 'rect')[0];
na_expect('the leaf is where the test assumes', [Number(na_panel.attrs.x), Number(na_panel.attrs.width)], [235, 780]);
na_expect('backplate, keyhole, collar, lever', polys.length, 4);
const na_int_left_x = na_spindle(na_points(polys[0]));
na_close('spindle 60 in from the latch', na_int_left_x, 235 + 780 - 60, 0.01);
na_close('lever points at the hinge', Math.min.apply(null, na_xs_of(polys[3])) - na_int_left_x, -NA_REACH, 0.01);

na_suite('Interior door preview: a right-hung door has its handle at the left, lever pointing right');
polys = na_handle_polygons(na_render(Interior, na_interior(NA_LEVER, 'Right')));
const na_int_right_x = na_spindle(na_points(polys[0]));
na_close('spindle 60 in from the latch', na_int_right_x, 235 + 60, 0.01);
na_close('lever points at the hinge', Math.max.apply(null, na_xs_of(polys[3])) - na_int_right_x, NA_REACH, 0.01);

na_suite('Interior door preview: the rest follows');
polys = na_handle_polygons(na_render(Interior, na_interior(NA_LEVER, undefined)));
na_close('no swing set draws as right-hung, as before', na_spindle(na_points(polys[0])), na_int_right_x, 0.01);
const na_marker_x = (side) => {
    const markers = na_render(Interior, na_interior('Handle__WithNoPaths', side)).filter(node => node.tag === 'circle' && Number(node.attrs.r) === 18);
    return markers.map(node => Number(node.attrs.cx));
};
na_expect('a handle with no paths marks the left-hung latch side', na_marker_x('Left'), [955]);
na_expect('and the right-hung latch side', na_marker_x('Right'), [295]);
polys = na_handle_polygons(na_render(Interior, na_interior(NA_LEVER, 'Left', { Na__DoorConfig__DoorType: 'Double' })));
na_expect('double door: both leaves, whichever swing is set', polys.length, 8);
na_close('left leaf spindle 60 in from the meeting edge', na_spindle(na_points(polys[0])), 235 + 390 - 60, 0.01);
na_close('its lever points left', Math.min.apply(null, na_xs_of(polys[3])) - na_spindle(na_points(polys[0])), -NA_REACH, 0.01);
na_close('right leaf spindle 60 in from the meeting edge', na_spindle(na_points(polys[4])), 235 + 390 + 60, 0.01);
na_close('its lever points right', Math.max.apply(null, na_xs_of(polys[7])) - na_spindle(na_points(polys[4])), NA_REACH, 0.01);

na_suite('Interior door 3D placement: the lever and the Scroll land where the preview draws');
[['lever', NA_ASSET], ['Scroll', NA_SCROLL_ASSET]].forEach(([name, asset]) => {
    const left  = asset.Na__Asset__Metadata.Na__PanelPlacement__LeftHand;
    const right = asset.Na__Asset__Metadata.Na__PanelPlacement__RightHand;
    // The builder's own sums: hinge + leaf + offset, and hinge - leaf + offset x ScaleX
    na_close(name + ' left-hung', 35 + 780 + left.Na__PanelPlacement__OffsetX_mm, na_int_left_x - 200, 0.01);
    na_close(name + ' right-hung', 815 - 780 + right.Na__PanelPlacement__OffsetX_mm * right.Na__PanelPlacement__ScaleX, na_int_right_x - 200, 0.01);
});

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Ruby Side Agrees
// -----------------------------------------------------------------------------

na_suite('Ruby side agrees');
const na_read = relative => fs.readFileSync(path.join(NA_MODULES, relative), 'utf8');
const na_builder = na_read('40__System__InteriorDoorSystem/Na__AssemblyStudio__InteriorDoorSystem__HandleBuilder3D__.rb');
na_expect('asset line colours go on after the standard dark grey',
          na_builder.indexOf('na_apply_asset_edge_colours(handle_def') > na_builder.indexOf('na_apply_standard_dark_grey_edge_colour(interior_inst'), true);
na_expect('the builder\'s interior sums are the ones tested above', /hinge_x_mm \+ leaf_w_mm \+ offset_x_mm/.test(na_builder) && /hinge_x_mm - leaf_w_mm \+ offset_x_mm \* scale_x/.test(na_builder), true);
na_expect('an absolute X wins over the offset', na_builder.indexOf('absolute_x_mm.to_f') < na_builder.indexOf('hinge_x_mm + leaf_w_mm + offset_x_mm'), true);
na_expect('exterior doors pass an absolute X, so the offset never moves them', /'Na__DoorConfig__HandleAbsoluteX_mm'\s*=>\s*na_handle_x_from_meeting_stile/.test(na_read('30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__HandleBuilder__.rb')), true);
const na_router = na_read('40__System__InteriorDoorSystem/Na__AssemblyStudio__InteriorDoorSystem__DialogRouter__.rb');
na_expect('the options say which handles have paths', /"hasElevation"\s*=>/.test(na_router), true);
na_expect('the preview gets each line hex from the SSOT', /"EdgeColourHex"\s*=>\s*entry\["HexValue"\]/.test(na_router), true);
na_expect('the interior door preview draws it too', /stroke:\s*pathItem\.EdgeColourHex\s*\|\|\s*NA_HANDLE_STROKE/.test(na_read('40__System__InteriorDoorSystem/Na__AssemblyStudio__InteriorDoorSystem__Viewport__ElevationGenerator__.js')), true);
na_expect('the Scroll stays the single door default', /'single_door_handle_asset_key'\s*=>\s*'Na__ExteriorDoor__Handle__Scroll'/.test(na_read('31__System__ExteriorSingleDoorSystem/Na__AssemblyStudio__ExtSingleDoor__Init__.rb')), true);
na_expect('the Scroll stays the double door default', /'double_door_handle_asset_key'\s*=>\s*'Na__ExteriorDoor__Handle__Scroll'/.test(na_read('34__System__ExteriorDoubleDoorSystem/Na__AssemblyStudio__ExtDouble__Init__.rb')), true);
const na_index = JSON.parse(fs.readFileSync(path.join(NA_ASSETS, 'Na__AssemblyStudio__AssetIndex__.json'), 'utf8'));
na_expect('the asset index lists the bucket', !!na_index.Na__AssemblyStudio__AssetIndex.buckets.ExteriorDoor__Handles__, true);

// endregion -------------------------------------------------------------------


console.log('\n' + na_pass + ' passed, ' + na_fail + ' failed');
process.exit(na_fail === 0 ? 0 : 1);
