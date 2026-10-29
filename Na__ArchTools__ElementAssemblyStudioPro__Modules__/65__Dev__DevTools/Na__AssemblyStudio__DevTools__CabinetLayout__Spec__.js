/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - CABINET LAYOUT SPEC
   =============================================================================

   FILE       : Na__AssemblyStudio__DevTools__CabinetLayout__Spec__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Guards the Interior Cabinetry layout resolver (the JS twin of
                Na__AssemblyStudio__Cabinetry__LayoutResolver__.rb, which builds
                the same numbers in SketchUp): UK standard sizes for every unit,
                drawer and handle rules, boards that never overlap, the dialog
                defaults against the Ruby defaults, and closed asset meshes.
   CREATED    : 29-Oct-2026

   HOW TO RUN (from anywhere, needs only Node - no install, no dependencies):

       node "65__Dev__DevTools/Na__AssemblyStudio__DevTools__CabinetLayout__Spec__.js"

   Exits 0 when everything passes, 1 otherwise.

   WHY THIS EXISTS:
   A cabinet that is a few millimetres out still looks right in the preview,
   and a door 3mm too tall clashes with the worktop only on site. These
   checks pin the UK numbers (Howdens / Wren practice: 720 carcass on 150
   legs, 560 deep, backs set in 20 for the scribe, 140 drawerline, 13mm
   runner clearance, wall units hung at 1400 so their tops meet a 1970 tall
   unit at 2120) so a change to the resolver that moves one fails here first.

   ============================================================================= */

'use strict';

const fs   = require('fs');
const path = require('path');


// -----------------------------------------------------------------------------
// REGION | Harness
// -----------------------------------------------------------------------------

const NA_ROOT    = path.resolve(__dirname, '..');
const NA_MODULES = path.join(NA_ROOT, '02__Src__AppModules');
const NA_SYSTEM  = '45__System__InteriorCabinetry';
const NA_ASSETS  = path.join(NA_ROOT, '04__Data__AssetLibrary');
const K          = 'Na__CabinetConfig__';

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

// HELPER FUNCTION | Assert a Number Within a Tolerance
// ------------------------------------------------------------
function na_near(label, actual, expected, tolerance) {
    const ok = typeof actual === 'number' && Math.abs(actual - expected) <= (tolerance || 1e-6);
    na_expect(label, ok ? expected : actual, expected);
}
// ---------------------------------------------------------------

function na_suite(title) { console.log('\n' + title); }

function na_read(relativePath) { return fs.readFileSync(path.join(NA_MODULES, relativePath), 'utf8'); }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Shipped Modules
// -----------------------------------------------------------------------------

global.window = global;
[NA_SYSTEM + '/Na__AssemblyStudio__Cabinetry__UiSystem__Config__.js',
 NA_SYSTEM + '/Na__AssemblyStudio__Cabinetry__Viewport__LayoutResolver__.js'].forEach((relativePath) => {
    // eslint-disable-next-line no-eval
    (0, eval)('(function(){' + na_read(relativePath) + '\n})()');
});
const R = window.Na__Cabinetry__LayoutResolver;

const NA_ARRAYS = ['NA_CABINET_PRODUCT_CONFIG', 'NA_CABINET_SIZE_CONFIG', 'NA_CABINET_FRONTS_CONFIG',
                   'NA_CABINET_INTERIOR_CONFIG', 'NA_CABINET_CARCASS_CONFIG', 'NA_CABINET_PLINTH_CONFIG',
                   'NA_CABINET_HARDWARE_CONFIG', 'NA_CABINET_FINISH_CONFIG', 'NA_CABINET_OUTPUT_CONFIG'];

// HELPER FUNCTION | The Dialog's Defaults, a Product's Overrides, Then the Test's
// ------------------------------------------------------------
function na_cfg(product, overrides) {
    const cfg = {};
    NA_ARRAYS.forEach(name => (window[name] || []).forEach(d => { if (d && d.id) cfg[d.id] = d.default; }));
    Object.assign(cfg, (window.NA_CABINET_PRODUCT_DEFAULTS || {})[product] || {});
    const types = { wall: 'Wall', tall: 'Tower', wardrobe: 'Tower' };
    if (types[product]) cfg[K + 'UnitType'] = types[product];
    Object.keys(overrides || {}).forEach(key => { cfg[K + key] = overrides[key]; });
    return cfg;
}
// ---------------------------------------------------------------

const na_part  = (L, name) => L.parts.find(part => part.name === name);
const na_front = (L, name) => L.fronts.find(front => front.name === name);
const na_role  = (L, role) => L.parts.filter(part => part.role === role);

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | UK Standard Units
// -----------------------------------------------------------------------------

na_suite('Base unit, 600 (the default)');
{
    const L = R.na_resolve(na_cfg('base'));
    const v = L.values;
    na_expect('Carcass 600 x 720 x 560 on a 150 plinth', [v.width, v.height, v.depth, v.zBase], [600, 720, 560, 150]);
    na_expect('20mm board by default, 9mm back', [v.board, v.back], [20, 9]);
    na_expect('Sides run full height and depth', [na_part(L, 'SidePanel__Left').z0, na_part(L, 'SidePanel__Left').z1, na_part(L, 'SidePanel__Left').y0], [150, 870, -560]);
    na_expect('Two top rails, 100 deep', na_role(L, 'rail').map(p => [p.name, p.y1 - p.y0]), [['TopRail__Front', 100], ['TopRail__Rear', 100]]);
    na_expect('One shelf', na_role(L, 'shelf').length, 1);
    const door = na_front(L, 'Door');
    na_expect('One door, 597 x 717, 20 thick, hinged left', [door.x1 - door.x0, door.z1 - door.z0, door.y1 - door.y0, door.hinge], [597, 717, 20, 'Left']);
    na_expect('Door clears the carcass top by half a gap', 870 - door.z1, 1.5);
    const handle = L.handles[0];
    na_expect('Handle vertical on the opening edge, 40 in, 60 down', [handle.orientation, 598.5 - handle.x, door.z1 - handle.z, handle.anchor], ['vertical', 40, 60, 'top']);
    na_expect('Four legs, 150 high', [L.legs.length, L.legHeight], [4, 150]);
    na_expect('Plinth set back 40 from the carcass front', L.plinth.y0 + v.depth, 40);
    na_expect('Front legs 35 behind the plinth', L.legs.filter(leg => leg.y < -200).map(leg => Math.round(leg.y - L.plinth.y1)), [35, 35]);
}

na_suite('Drawer pack (pan drawers)');
{
    const L = R.na_resolve(na_cfg('drawers'));
    const heights = L.fronts.map(front => Math.round((front.z1 - front.z0) * 10) / 10);
    na_expect('Three fronts, 140 drawerline over two 285.5 pans', heights, [140, 285.5, 285.5]);
    na_expect('3mm between fronts', [L.fronts[0].z0 - L.fronts[1].z1, L.fronts[1].z0 - L.fronts[2].z1], [3, 3]);
    na_expect('Slim front: handle centred on it', L.handles[0].z, (L.fronts[0].z0 + L.fronts[0].z1) / 2);
    na_expect('Pan fronts: handle centred on the 70 top rail', L.handles.slice(1).map((h, i) => L.fronts[i + 1].z1 - h.z), [35, 35]);
    na_expect('Handles horizontal and centred across', L.handles.map(h => [h.orientation, h.x]), [['horizontal', 300], ['horizontal', 300], ['horizontal', 300]]);
    na_expect('A drawer box behind each front', L.drawerBoxes.length, 3);
    L.drawerBoxes.forEach((box, i) => {
        const left  = box.parts.find(p => p.name.endsWith('Side__Left'));
        const right = box.parts.find(p => p.name.endsWith('Side__Right'));
        na_expect('Box ' + (i + 1) + ': 13mm runner clearance each side', [left.x0 - 20, 580 - right.x1], [13, 13]);
        na_expect('Box ' + (i + 1) + ': 500 long, clear of the back', [left.y1 - left.y0, left.y1 <= L.yBackPanelFront - 10], [500, true]);
        na_expect('Box ' + (i + 1) + ': 30 under its front top', L.fronts[i].z1 - left.z1, 30);
    });
}

na_suite('Wall unit');
{
    const L = R.na_resolve(na_cfg('wall'));
    const v = L.values;
    na_expect('720 x 300, hung at 1400, top at 2120', [v.height, v.depth, v.zBase, v.zBase + v.height], [720, 300, 1400, 2120]);
    na_expect('No legs, no plinth', [L.legs.length, L.plinth], [0, null]);
    na_expect('Top panel, two shelves', [na_role(L, 'top').length, na_role(L, 'shelf').length], [1, 2]);
    na_expect('Handle near the bottom of the door', [L.handles[0].anchor, L.handles[0].z - L.fronts[0].z0], ['bottom', 60]);
}

na_suite('Tall larder and wardrobe');
{
    const tall = R.na_resolve(na_cfg('tall'));
    const wall = R.na_resolve(na_cfg('wall'));
    na_expect('Tall top meets the wall unit top (1970 + 150 = 2120)', tall.values.zBase + tall.values.height, wall.values.zBase + wall.values.height);
    na_expect('Split doors, upper over lower', tall.fronts.map(f => f.name), ['Door__Upper', 'Door__Lower']);
    na_expect('Fixed shelf at the split', na_role(tall, 'fixedShelf').length, 1);
    na_expect('Handles meet at the split', tall.handles.map(h => h.anchor), ['bottom', 'top']);

    const robe = R.na_resolve(na_cfg('wardrobe'));
    na_expect('Wardrobe 2150 x 600 on 150', [robe.values.height, robe.values.depth, robe.values.zBase], [2150, 600, 150]);
    na_expect('Hat shelf and hanging rail', [na_role(robe, 'hatShelf').length, !!robe.rail], [1, true]);
    na_expect('Rail centred in the depth', robe.rail.y, -(robe.values.depth - robe.values.back - robe.values.backInset) / 2 - robe.values.back - robe.values.backInset);
    na_expect('One full height door, handle at 1050', [robe.fronts.length, robe.handles[0].z], [1, 1050]);
}

na_suite('Widths');
{
    const w400  = R.na_resolve(na_cfg('base', { Width_mm: 400 }));
    const w1000 = R.na_resolve(na_cfg('base', { Width_mm: 1000 }));
    na_expect('400: one door', w400.fronts.length, 1);
    na_expect('1000: a pair, hinged outward', w1000.fronts.map(f => f.hinge), ['Left', 'Right']);
    na_expect('1000: middle legs (six)', w1000.legs.length, 6);
    na_expect('1000: handles on the meeting edges', w1000.handles.map(h => Math.round(h.x)), [Math.round(w1000.fronts[0].x1 - 40), Math.round(w1000.fronts[1].x0 + 40)]);
    const pair600 = R.na_resolve(na_cfg('base', { DoorCount: '2' }));
    na_expect('600 asked for a pair gets one', pair600.fronts.length, 2);
}

na_suite('Board thickness (the accuracy setting)');
{
    const b20 = R.na_resolve(na_cfg('base'));
    const b18 = R.na_resolve(na_cfg('base', { BoardThickness_mm: 18 }));
    const inside = L => na_part(L, 'SidePanel__Right').x0 - na_part(L, 'SidePanel__Left').x1;
    na_expect('20mm leaves 560 inside', inside(b20), 560);
    na_expect('18mm leaves 564 inside', inside(b18), 564);
    na_expect('The outside never changes', [b18.values.width, b18.bounds.x1], [600, 600]);
}

na_suite('Scribe (every back panel set in 20)');
{
    ['base', 'drawers', 'wall', 'tall', 'wardrobe'].forEach(product => {
        const L      = R.na_resolve(na_cfg(product));
        const back   = na_part(L, 'BackPanel');
        const behind = L.parts.filter(p => p.role !== 'side' && p.role !== 'back' && p.y1 > back.y0 + 1e-6).map(p => p.name);
        na_expect(product + ': 9mm back, 20 in from the sides\' back edges', [back.y0, back.y1], [-29, -20]);
        na_expect(product + ': sides run to the wall line', na_role(L, 'side').map(p => p.y1), [0, 0]);
        na_expect(product + ': only the sides reach behind the back panel', behind, []);
        na_expect(product + ': bounds still reach the wall line', L.bounds.y1, 0);
    });
    const base = R.na_resolve(na_cfg('base'));
    const rear = base.legs.filter(leg => leg.y > -200);
    na_expect('Base panel 531 deep (560 less the scribe and back)', na_part(base, 'BasePanel').y1 - na_part(base, 'BasePanel').y0, 531);
    na_expect('Rear legs 65 in, their 60 plate under the base panel', [rear.map(leg => leg.y), rear.every(leg => leg.y + 30 <= base.yBackPanelFront)], [[-65, -65], true]);
    const flush = R.na_resolve(na_cfg('base', { BackPanelInset_mm: 0 }));
    na_expect('Scribe 0: back flush with the sides, base to the back', [na_part(flush, 'BackPanel').y1, na_part(flush, 'BasePanel').y1], [0, -9]);
}

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Invariants Across Every Product, Style and Width
// -----------------------------------------------------------------------------

// HELPER FUNCTION | Do Two Boxes Share Any Volume
// ------------------------------------------------------------
function na_overlap(a, b) {
    const eps = 1e-6;
    return a.x0 < b.x1 - eps && b.x0 < a.x1 - eps && a.y0 < b.y1 - eps && b.y0 < a.y1 - eps && a.z0 < b.z1 - eps && b.z0 < a.z1 - eps;
}
// ---------------------------------------------------------------

na_suite('Invariants');
{
    const problems = [];
    let cases = 0;
    ['base', 'drawers', 'wall', 'tall', 'wardrobe'].forEach(product => {
        ['Flat', 'Shaker', 'Recessed'].forEach(style => {
            [150, 300, 450, 600, 800, 1000, 1200].forEach(width => {
                const L = R.na_resolve(na_cfg(product, { DoorStyle: style, Width_mm: width }));
                const tag = product + '/' + style + '/' + width;
                cases += 1;
                for (let i = 0; i < L.parts.length; i++) {
                    for (let j = i + 1; j < L.parts.length; j++) {
                        if (na_overlap(L.parts[i], L.parts[j])) problems.push(tag + ': ' + L.parts[i].name + ' overlaps ' + L.parts[j].name);
                    }
                }
                L.fronts.forEach(front => {
                    if (front.x0 < 0 || front.x1 > width) problems.push(tag + ': ' + front.name + ' outside the width');
                    if (front.y1 !== -L.values.depth) problems.push(tag + ': ' + front.name + ' not on the carcass front');
                });
                L.handles.forEach(handle => {
                    const front = na_front(L, handle.front);
                    if (!front || handle.y !== front.y0) problems.push(tag + ': handle off its front');
                    else if (handle.x < front.x0 || handle.x > front.x1 || handle.z < front.z0 || handle.z > front.z1) problems.push(tag + ': handle anchor outside ' + front.name);
                });
                if (style === 'Recessed' && L.handles.length) problems.push(tag + ': handles on recessed fronts');
                L.drawerBoxes.forEach(box => box.parts.forEach(part => L.parts.forEach(board => {
                    if (na_overlap(part, board)) problems.push(tag + ': ' + part.name + ' hits ' + board.name);
                })));
            });
        });
    });
    console.log('  ' + cases + ' configurations');
    na_expect('No overlapping boards, fronts on the carcass, handles on their fronts', problems.slice(0, 8), []);
}

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Dialog Defaults Against the Ruby Defaults
// -----------------------------------------------------------------------------

na_suite('Defaults parity (UiSystem Config vs Defaults.rb)');
{
    const ruby      = na_read(NA_SYSTEM + '/Na__AssemblyStudio__Cabinetry__Defaults__.rb');
    const constants = {};
    ruby.replace(/^\s*(NA_[A-Z_]+)\s*=\s*"([^"]*)"/gm, (_, name, value) => { constants[name] = value; return ''; });
    const block = ruby.slice(ruby.indexOf('NA_DEFAULT_CABINET_CONFIGURATION = {'), ruby.indexOf('}.freeze', ruby.indexOf('NA_DEFAULT_CABINET_CONFIGURATION = {')));
    const rubyDefaults = {};
    block.replace(/"(Na__CabinetConfig__\w+)"\s*=>\s*([^,#\n]+)/g, (_, key, raw) => {
        const text = raw.trim();
        rubyDefaults[key] = /^".*"$/.test(text) ? text.slice(1, -1)
                          : (text === 'true' || text === 'false') ? text === 'true'
                          : /^-?\d+(\.\d+)?$/.test(text) ? Number(text)
                          : constants[text];
        return '';
    });
    const js = na_cfg('base');
    const mismatched = Object.keys(js).filter(key => JSON.stringify(js[key]) !== JSON.stringify(rubyDefaults[key]));
    const rubyOnly   = Object.keys(rubyDefaults).filter(key => !(key in js));
    na_expect('Every dialog default equals the Ruby default', mismatched.map(key => key + ' js=' + js[key] + ' rb=' + rubyDefaults[key]), []);
    na_expect('Ruby-only keys are the hidden ones', rubyOnly, [K + 'LegMaterialId']);
}

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Asset Library
// -----------------------------------------------------------------------------

// HELPER FUNCTION | Closed, Outward, Planar Check of One Asset Mesh
// ------------------------------------------------------------
function na_mesh_report(mesh) {
    const pos = {};
    (mesh.Na__Geometry__Vertices || []).forEach(v => { pos[v.VertexId] = [Number(v.PosX_mm), Number(v.PosY_mm), Number(v.PosZ_mm)]; });
    const directed = {};
    let volume = 0;
    let nonPlanar = 0;
    (mesh.Na__Geometry__Faces || []).forEach(face => {
        const ids = face.OuterLoop_VertexIds || [];
        ids.forEach((a, i) => { const key = a + '>' + ids[(i + 1) % ids.length]; directed[key] = (directed[key] || 0) + 1; });
        const p = ids.map(id => pos[id]);
        let n = [0, 0, 0];
        p.forEach((a, i) => { const b = p[(i + 1) % p.length]; n = [n[0] + (a[1] - b[1]) * (a[2] + b[2]), n[1] + (a[2] - b[2]) * (a[0] + b[0]), n[2] + (a[0] - b[0]) * (a[1] + b[1])]; });
        const len = Math.hypot(n[0], n[1], n[2]) || 1;
        const d = (n[0] * p[0][0] + n[1] * p[0][1] + n[2] * p[0][2]) / len;
        if (p.some(q => Math.abs((n[0] * q[0] + n[1] * q[1] + n[2] * q[2]) / len - d) > 0.01)) nonPlanar += 1;
        for (let i = 1; i < p.length - 1; i++) {
            const a = p[0], b = p[i], c = p[i + 1];
            volume += (a[0] * (b[1] * c[2] - b[2] * c[1]) - a[1] * (b[0] * c[2] - b[2] * c[0]) + a[2] * (b[0] * c[1] - b[1] * c[0])) / 6;
        }
    });
    const open = Object.keys(directed).filter(key => { const [a, b] = key.split('>'); return directed[key] !== 1 || directed[b + '>' + a] !== 1; }).length;
    return { open, nonPlanar, volume };
}
// ---------------------------------------------------------------

na_suite('Asset library (legs and handles)');
{
    const index   = JSON.parse(fs.readFileSync(path.join(NA_ASSETS, 'Na__AssemblyStudio__AssetIndex__.json'), 'utf8'));
    const buckets = (index.Na__AssemblyStudio__AssetIndex || {}).buckets || {};
    ['Cabinetry__Legs__', 'Cabinetry__Handles__'].forEach(folder => {
        const files = fs.readdirSync(path.join(NA_ASSETS, folder)).filter(name => name.endsWith('.json'));
        na_expect(folder + ' is a bucket in the asset index', !!buckets[folder], true);
        na_expect(folder + ' has assets', files.length > 0, true);
        files.forEach(file => {
            const asset = JSON.parse(fs.readFileSync(path.join(NA_ASSETS, folder, file), 'utf8'));
            const meta  = asset.Na__Asset__Metadata || {};
            const r     = na_mesh_report(asset.Na__Asset__Mesh3D || {});
            na_expect(file + ': closed, planar, faces out', [r.open, r.nonPlanar, r.volume > 0], [0, 0, true]);
            na_expect(file + ': has a plan and an elevation', [!!asset.Na__Asset__Plan2D, !!asset.Na__Asset__Elevation2D], [true, true]);
            const needs = folder === 'Cabinetry__Legs__'
                ? ['Na__CabinetPlacement__NominalHeight_mm', 'Na__CabinetPlacement__StretchZoneMin_mm', 'Na__CabinetPlacement__StretchZoneMax_mm']
                : ['Na__CabinetPlacement__Kind', 'Na__CabinetPlacement__Length_mm', 'Na__CabinetPlacement__Projection_mm'];
            na_expect(file + ': placement data', needs.filter(key => !(key in meta)), []);
        });
    });
}

// endregion -------------------------------------------------------------------


console.log('\n' + na_pass + ' passed, ' + na_fail + ' failed');
process.exit(na_fail === 0 ? 0 : 1);

/* =============================================================================
   END OF FILE
   ============================================================================= */
