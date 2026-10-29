// =============================================================================
// ELEMENT ASSEMBLY STUDIO PRO - INTERIOR CABINETRY SYSTEM - LAYOUT RESOLVER (JS)
// =============================================================================
//
// FILE       : Na__AssemblyStudio__Cabinetry__Viewport__LayoutResolver__.js
// NAMESPACE  : window.Na__Cabinetry__LayoutResolver
// AUTHOR     : Noble Architecture
// PURPOSE    : Turns one cabinet configuration into the position and size of
//              every part, in millimetres: carcass panels, top rails, back,
//              shelves, the fronts and their style, drawer boxes, the plinth,
//              the leg points and the handle anchors. Pure maths, no DOM.
// CREATED    : 29-Oct-2026
//
// ONE SET OF RULES, TWO LANGUAGES
// - The elevation and section previews draw from this file.
// - Na__AssemblyStudio__Cabinetry__LayoutResolver__.rb applies the same rules
//   in Ruby and the geometry builders build from its result. The CabinetLayout
//   spec runs both over the same configurations and fails on any difference,
//   so a rule changed here must be changed there too.
//
// UNIT FRAME (millimetres)
// - Origin : the BACK-LEFT corner of the carcass, at FLOOR level, on the wall
//            line. Every unit type shares the floor datum, so a wall unit is
//            built 1400 up inside its own frame and runs line up by type.
// - X      : along the run, 0 to the width (left to right seen from the front)
// - Y      : depth. The carcass fills -depth..0, the fronts sit in front of
//            it (more negative), so the unit faces -Y like SketchUp's Front view.
// - Z      : up from the floor.
//
// HANDLE ANCHORS
// - A handle is placed by the point one of its ends (or its centre) must sit
//   on, so the layout does not depend on the length of the chosen handle:
//     anchor 'top' / 'bottom' / 'left' / 'right' = that end of the bar
//     anchor 'centre'                             = the handle's centre
//   The builders and the preview offset by half the handle's own length.
//
// NAMING CONVENTION:
// - All custom identifiers use Na_ / na_ prefix.
//
// =============================================================================

(function () {
    'use strict';

// -----------------------------------------------------------------------------
// REGION | Construction Allowances (not user settings)
// -----------------------------------------------------------------------------

    const NA_KEY_PREFIX                 = 'Na__CabinetConfig__';
    const NA_AUTO_PAIR_OVER_MM          = 600;    // <-- UK single doors stop at 600; wider units take a pair
    const NA_MIN_DOOR_WIDTH_MM          = 100;
    const NA_MIN_FRONT_HEIGHT_MM        = 60;
    const NA_SHAKER_MIN_PANEL_MM        = 30;    // <-- Smallest centre panel worth recessing
    const NA_SHAKER_MIN_FRAME_MM        = 15;    // <-- Below this the front is left flat
    const NA_GROOVE_MIN_LAND_MM         = 20;    // <-- Solid front needed beyond the groove
    const NA_GROOVE_MIN_BACK_MM         = 3;     // <-- Front left behind the deepest point of the groove
    const NA_SHELF_MIN_GAP_MM           = 40;
    const NA_RUNNER_CLEARANCE_MM        = 13;    // <-- Side-mount runner space each side of a drawer box (UK 12.5)
    const NA_DRAWER_SIDE_MM             = 15;
    const NA_DRAWER_BASE_MM             = 6;
    const NA_DRAWER_BELOW_FRONT_TOP_MM  = 30;    // <-- Box top sits this far below its front's top
    const NA_DRAWER_ABOVE_FRONT_BASE_MM = 15;    // <-- Box bottom sits this far above its front's bottom
    const NA_DRAWER_CARCASS_CLEAR_MM    = 5;     // <-- Box kept clear of the base panel and the top
    const NA_DRAWER_LENGTH_STEP_MM      = 50;    // <-- Drawer boxes come in 50s (500 in a 560 carcass)
    const NA_DRAWER_REAR_CLEAR_MM       = 10;
    const NA_DRAWER_MIN_WIDTH_MM        = 100;
    const NA_DRAWER_HANDLE_DROP_MM      = 70;    // <-- Drawer handle centre at most this far below the front top
    const NA_TALL_HANDLE_HEIGHT_MM      = 1050;  // <-- Handle centre above the floor on a full height tall door
    const NA_TALL_HANDLE_HALF_MM        = 100;   // <-- Clearance kept for the bar when that centre is clamped
    const NA_LEG_MIN_HEIGHT_MM          = 80;    // <-- No legs below this plinth height
    const NA_LEG_BEHIND_PLINTH_MM       = 35;    // <-- Front leg centre behind the plinth's back face
    const NA_LEG_BEHIND_BACK_MM         = 35;    // <-- Back leg centre in front of a set-in back panel
    const NA_LEG_MIN_ROW_GAP_MM         = 40;
    const NA_MIDDLE_LEGS_OVER_MM        = 900;   // <-- 1000 units get a middle pair of legs
    const NA_PLINTH_MIN_HEIGHT_MM       = 20;
    const NA_RAIL_DIAMETER_MM           = 25;

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Config Readers
// -----------------------------------------------------------------------------

    // HELPER FUNCTION | Every Descriptor Array of the Cabinetry Tab
    // ------------------------------------------------------------
    function na_descriptor_arrays() {
        const root = (typeof window !== 'undefined') ? window : {};
        return [
            root.NA_CABINET_PRODUCT_CONFIG, root.NA_CABINET_SIZE_CONFIG, root.NA_CABINET_FRONTS_CONFIG,
            root.NA_CABINET_INTERIOR_CONFIG, root.NA_CABINET_CARCASS_CONFIG, root.NA_CABINET_PLINTH_CONFIG,
            root.NA_CABINET_HARDWARE_CONFIG, root.NA_CABINET_FINISH_CONFIG, root.NA_CABINET_OUTPUT_CONFIG
        ].filter(Array.isArray);
    }
    // ---------------------------------------------------------------

    let na_defaults_cache = null;

    // HELPER FUNCTION | The Descriptor Default of One Key
    // ------------------------------------------------------------
    function na_default_of(key) {
        if (!na_defaults_cache) {
            na_defaults_cache = {};
            na_descriptor_arrays().forEach(list => list.forEach(descriptor => {
                if (descriptor && descriptor.id) na_defaults_cache[descriptor.id] = descriptor.default;
            }));
        }
        return na_defaults_cache[NA_KEY_PREFIX + key];
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Read a Number, Falling Back to the Default, Clamped
    // ------------------------------------------------------------
    function na_number(cfg, key, min, max) {
        const raw   = cfg[NA_KEY_PREFIX + key];
        let   value = Number((raw === undefined || raw === null || raw === '') ? na_default_of(key) : raw);
        if (!isFinite(value)) value = Number(na_default_of(key));
        if (!isFinite(value)) value = min;
        return Math.min(max, Math.max(min, value));
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Read One of a Set of Strings, Falling Back to the Default
    // ------------------------------------------------------------
    function na_choice(cfg, key, allowed) {
        const raw = cfg[NA_KEY_PREFIX + key];
        if (allowed.indexOf(String(raw)) !== -1) return String(raw);
        const fallback = String(na_default_of(key));
        return allowed.indexOf(fallback) !== -1 ? fallback : allowed[0];
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Read a Boolean (Anything But false Is On), With Default
    // ------------------------------------------------------------
    function na_flag(cfg, key) {
        const raw = cfg[NA_KEY_PREFIX + key];
        if (raw === undefined || raw === null) return na_default_of(key) !== false;
        return raw !== false && raw !== 'false';
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Read a Free Text Value, With Default
    // ------------------------------------------------------------
    function na_text(cfg, key) {
        const raw = cfg[NA_KEY_PREFIX + key];
        if (raw === undefined || raw === null || String(raw).trim() === '') return String(na_default_of(key) || '');
        return String(raw).trim();
    }
    // ---------------------------------------------------------------

    // FUNCTION | Resolve Every Value the Layout Uses, Defaulted and Clamped
    // ------------------------------------------------------------
    // @param  {Object} cfg - A Na__CabinetConfiguration block (UI or saved)
    // @return {Object}       Plain values in mm, plus the chosen options
    function na_effective(cfg) {
        cfg = cfg || {};
        const type   = na_choice(cfg, 'UnitType', ['Base', 'Wall', 'Tower']);
        const isBase = type === 'Base';
        const isWall = type === 'Wall';

        const height = isWall ? na_number(cfg, 'WallHeight_mm', 100, 3500)
                     : (isBase ? na_number(cfg, 'BaseHeight_mm', 100, 3500) : na_number(cfg, 'TowerHeight_mm', 100, 3500));
        const depth  = isWall ? na_number(cfg, 'WallDepth_mm', 100, 1200)
                     : (isBase ? na_number(cfg, 'BaseDepth_mm', 100, 1200) : na_number(cfg, 'TowerDepth_mm', 100, 1200));
        const board  = na_number(cfg, 'BoardThickness_mm', 6, 50);
        const layout = isWall ? na_choice(cfg, 'WallFrontLayout', ['Doors', 'Open'])
                     : (isBase ? na_choice(cfg, 'BaseFrontLayout', ['Doors', 'DrawerDoors', 'Drawers', 'Open'])
                               : na_choice(cfg, 'TowerFrontLayout', ['Doors', 'SplitDoors', 'Open']));

        return {
            type            : type,
            width           : na_number(cfg, 'Width_mm', 50, 3000),
            height          : height,
            depth           : depth,
            zBase           : isWall ? na_number(cfg, 'WallMountHeight_mm', 0, 4000) : na_number(cfg, 'PlinthHeight_mm', 0, 400),
            board           : board,
            back            : na_number(cfg, 'BackPanelThickness_mm', 0, 40),
            backInset       : Math.min(na_number(cfg, 'BackPanelInset_mm', 0, 200), depth / 2),
            topConstruction : isBase ? na_choice(cfg, 'BaseTopConstruction', ['Rails', 'TopPanel']) : 'TopPanel',
            railDepth       : na_number(cfg, 'TopRailDepth_mm', 20, 400),
            layout          : layout,
            style           : na_choice(cfg, 'DoorStyle', ['Flat', 'Shaker', 'Recessed']),
            doorCount       : na_choice(cfg, 'DoorCount', ['Auto', '1', '2']),
            hinge           : na_choice(cfg, 'HingeSide', ['Left', 'Right']),
            drawerCount     : Math.round(na_number(cfg, 'DrawerCount', 1, 8)),
            drawerLayout    : na_choice(cfg, 'DrawerLayout', ['Graduated', 'Equal']),
            topDrawer       : na_number(cfg, 'TopDrawerHeight_mm', 40, 600),
            splitUpper      : na_number(cfg, 'SplitUpperHeight_mm', 100, 3000),
            frontThickness  : na_number(cfg, 'DoorThickness_mm', 6, 50),
            gap             : na_number(cfg, 'DoorGap_mm', 0, 20),
            shakerFrame     : na_number(cfg, 'ShakerFrameWidth_mm', 10, 300),
            shakerRecess    : na_number(cfg, 'ShakerPanelRecess_mm', 1, 30),
            grooveWidth     : na_number(cfg, 'GrooveWidth_mm', 4, 80),
            grooveDepth     : na_number(cfg, 'GrooveDepth_mm', 2, 40),
            grooveOffset    : na_number(cfg, 'GrooveOffset_mm', 0, 200),
            shelves         : Math.round(isWall ? na_number(cfg, 'WallShelfCount', 0, 20)
                                       : (isBase ? na_number(cfg, 'BaseShelfCount', 0, 20) : na_number(cfg, 'TowerShelfCount', 0, 20))),
            towerInterior   : (type === 'Tower') ? na_choice(cfg, 'TowerInterior', ['Shelves', 'Hanging']) : 'Shelves',
            hatShelfDrop    : na_number(cfg, 'HatShelfDrop_mm', 0, 1500),
            railDrop        : na_number(cfg, 'RailDropBelowShelf_mm', 0, 500),
            shelfSetback    : na_number(cfg, 'ShelfSetback_mm', 0, 300),
            plinthEnabled   : na_flag(cfg, 'PlinthEnabled'),
            plinthSetback   : na_number(cfg, 'PlinthSetback_mm', 0, 400),
            plinthThickness : na_number(cfg, 'PlinthThickness_mm', 3, 60),
            legsEnabled     : na_flag(cfg, 'LegsEnabled'),
            legSideInset    : na_number(cfg, 'LegSideInset_mm', 0, 500),
            legBackInset    : na_number(cfg, 'LegBackInset_mm', 0, 500),
            legKey          : na_text(cfg, 'LegAssetKey'),
            handleKey       : na_text(cfg, 'HandleAssetKey'),
            handleDirection : na_choice(cfg, 'HandleOrientation', ['Auto', 'Vertical', 'Horizontal']),
            handleEdgeInset : na_number(cfg, 'HandleEdgeInset_mm', 0, 500),
            handleEndInset  : na_number(cfg, 'HandleEndInset_mm', 0, 1000),
            drawerBoxes     : na_flag(cfg, 'DrawerBoxesEnabled')
        };
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Small Builders
// -----------------------------------------------------------------------------

    // HELPER FUNCTION | One Board as an Axis-Aligned Box (mm)
    // ------------------------------------------------------------
    function na_box(name, role, x0, x1, y0, y1, z0, z1) {
        return { name: name, role: role, x0: x0, x1: x1, y0: y0, y1: y1, z0: z0, z1: z1 };
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Does a Box Have Real Volume
    // ------------------------------------------------------------
    function na_box_ok(box) {
        return (box.x1 - box.x0) > 0.01 && (box.y1 - box.y0) > 0.01 && (box.z1 - box.z0) > 0.01;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Spread n Shelves Evenly Through a Height Range
    // ------------------------------------------------------------
    // Returns the bottom face of each shelf, lowest first. Drops shelves
    // until each opening is at least NA_SHELF_MIN_GAP_MM tall.
    function na_shelf_levels(zBottom, zTop, count, thickness) {
        let n = Math.max(0, count);
        while (n > 0 && ((zTop - zBottom) - n * thickness) / (n + 1) < NA_SHELF_MIN_GAP_MM) n -= 1;
        const gap    = ((zTop - zBottom) - n * thickness) / (n + 1);
        const levels = [];
        for (let k = 1; k <= n; k += 1) levels.push(zBottom + k * gap + (k - 1) * thickness);
        return levels;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Two-Digit Part Number
    // ------------------------------------------------------------
    function na_pad(index) {
        return (index < 10 ? '0' : '') + index;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Is the Chosen Handle a Knob (Placed by Its Centre)
    // ------------------------------------------------------------
    function na_is_knob(handleKey) {
        return /__Knob__/i.test(String(handleKey || ''));
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Carcass
// -----------------------------------------------------------------------------

    // SUB FUNCTION | Sides, Base, Top (Rails or Panel) and Back
    // ------------------------------------------------------------
    // The sides run full height and full depth; everything else sits between
    // them. The back panel is full height between the sides, set in 20 from
    // their back edges: the scribe, the strip of side a fitter planes to an
    // uneven wall, which leaves a void behind the back for pipes and the wall
    // unit hanging rail. The base, top and shelves stop at the back panel.
    function na_build_carcass(v, L) {
        const t    = v.board;
        const W    = v.width;
        const D    = v.depth;
        const z0   = v.zBase;
        const z1   = v.zBase + v.height;
        const yBp  = L.yBackPanelFront;

        L.parts.push(na_box('SidePanel__Left',  'side', 0,     t, -D, 0, z0, z1));
        L.parts.push(na_box('SidePanel__Right', 'side', W - t, W, -D, 0, z0, z1));
        L.parts.push(na_box('BasePanel',        'base', t, W - t, -D, yBp, z0, z0 + t));

        const railsFit = (yBp + D) >= (2 * v.railDepth + 10);
        if (v.topConstruction === 'Rails' && railsFit) {
            L.parts.push(na_box('TopRail__Front', 'rail', t, W - t, -D, -D + v.railDepth, z1 - t, z1));
            L.parts.push(na_box('TopRail__Rear',  'rail', t, W - t, yBp - v.railDepth, yBp, z1 - t, z1));
        } else {
            if (v.topConstruction === 'Rails') L.warnings.push('The carcass is too shallow for two top rails, so it has a top panel.');
            L.parts.push(na_box('TopPanel', 'top', t, W - t, -D, yBp, z1 - t, z1));
        }

        if (v.back > 0) {
            L.parts.push(na_box('BackPanel', 'back', t, W - t, -(v.backInset + v.back), -v.backInset, z0, z1));
        }
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Fronts
// -----------------------------------------------------------------------------

    // HELPER FUNCTION | How Many Doors Across
    // ------------------------------------------------------------
    function na_doors_across(v, L) {
        let count = (v.doorCount === 'Auto') ? (v.width > NA_AUTO_PAIR_OVER_MM ? 2 : 1) : Number(v.doorCount);
        if (count === 2 && (v.width / 2 - v.gap) < NA_MIN_DOOR_WIDTH_MM) {
            L.warnings.push('Too narrow for a pair of doors, so it has one.');
            count = 1;
        }
        return count;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Front Heights for a Drawer Pack (Top Drawer First)
    // ------------------------------------------------------------
    // The fronts share the carcass height less a half gap top and bottom and
    // a full gap between each pair. Graduated keeps the top front at the Top
    // Drawer Front Height and shares the rest; if that would leave the lower
    // fronts shallower than the top one, all are made equal.
    function na_drawer_heights(v, L) {
        const n     = v.drawerCount;
        const total = v.height - n * v.gap;
        if (n === 1) return [total];
        if (v.drawerLayout === 'Graduated') {
            const top  = Math.min(v.topDrawer, total - (n - 1) * NA_MIN_FRONT_HEIGHT_MM);
            const rest = (total - top) / (n - 1);
            if (rest >= top) {
                const heights = [top];
                for (let k = 1; k < n; k += 1) heights.push(rest);
                return heights;
            }
            L.warnings.push('The lower drawers would be shallower than the top one, so all ' + n + ' are equal.');
        }
        const heights = [];
        for (let k = 0; k < n; k += 1) heights.push(total / n);
        return heights;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Which Edge a Recessed Handle Groove Runs Along
    // ------------------------------------------------------------
    // Base fronts and lower tall doors open from the top, wall doors and
    // upper tall doors from the bottom; a full height tall door takes a
    // vertical groove up its opening edge.
    function na_groove_edge(v, kind, row, hinge) {
        if (kind === 'drawer') return 'top';
        if (v.type === 'Wall') return 'bottom';
        if (v.type === 'Tower') {
            if (row === 'upper') return 'bottom';
            if (row === 'lower') return 'top';
            return hinge === 'Right' ? 'left' : 'right';
        }
        return 'top';
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Shaker Frame for One Front (Null When Too Small)
    // ------------------------------------------------------------
    function na_shaker_frame(v, w, h) {
        const stile = Math.min(v.shakerFrame, (w - NA_SHAKER_MIN_PANEL_MM) / 2);
        const rail  = Math.min(v.shakerFrame, (h - NA_SHAKER_MIN_PANEL_MM) / 2);
        if (stile < NA_SHAKER_MIN_FRAME_MM || rail < NA_SHAKER_MIN_FRAME_MM) return null;
        return { stile: stile, rail: rail, recess: Math.min(v.shakerRecess, v.frontThickness - 4) };
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Handle Groove for One Front (Null When It Will Not Fit)
    // ------------------------------------------------------------
    function na_groove(v, edge, w, h) {
        const span     = (edge === 'left' || edge === 'right') ? w : h;
        const depth    = Math.min(v.grooveDepth, v.frontThickness - NA_GROOVE_MIN_BACK_MM);
        const width    = Math.min(v.grooveWidth, 2 * depth);                   // <-- Round bottom: half the width fits in the depth
        if (depth <= 0 || span < v.grooveOffset + width + NA_GROOVE_MIN_LAND_MM) return null;
        return { edge: edge, offset: v.grooveOffset, width: width, depth: depth };
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Describe One Front and Its Handle
    // ------------------------------------------------------------
    function na_add_front(v, L, name, kind, row, hinge, x0, x1, z0, z1) {
        const w = x1 - x0;
        const h = z1 - z0;
        if (w < 1 || h < 1) return;
        if (h < NA_MIN_FRONT_HEIGHT_MM) L.warnings.push(name.replace(/__/g, ' ') + ' is only ' + Math.round(h) + 'mm tall.');

        const front = {
            name  : name,
            kind  : kind,
            row   : row,
            hinge : hinge,
            x0    : x0, x1: x1,
            y0    : -(v.depth + v.frontThickness), y1: -v.depth,
            z0    : z0, z1: z1,
            style : v.style,
            shaker: null,
            groove: null
        };
        if (v.style === 'Shaker')   front.shaker = na_shaker_frame(v, w, h);
        if (v.style === 'Recessed') front.groove = na_groove(v, na_groove_edge(v, kind, row, hinge), w, h);
        if (v.style === 'Recessed' && !front.groove) L.warnings.push(name.replace(/__/g, ' ') + ' is too small for a handle groove.');
        L.fronts.push(front);

        if (v.style !== 'Recessed') na_add_handle(v, L, front);
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Anchor the Handle on One Front
    // ------------------------------------------------------------
    // Doors: the handle sits on the opening edge, near the top on base doors
    // and lower tall doors, near the bottom on wall doors and upper tall
    // doors, and at about 1050 above the floor on a full height tall door.
    // Drawers: centred across, on the top rail of a full shaker frame,
    // otherwise its centre at most 70 below the front's top.
    function na_add_handle(v, L, front) {
        if (!v.handleKey || v.handleKey === 'None') return;
        const knob     = na_is_knob(v.handleKey);
        const vertical = (v.handleDirection === 'Auto') ? (front.kind === 'door') : (v.handleDirection === 'Vertical');
        const handle   = { front: front.name, orientation: vertical ? 'vertical' : 'horizontal', x: 0, z: 0, anchor: 'centre', y: front.y0 };

        if (front.kind === 'drawer') {
            handle.x = (front.x0 + front.x1) / 2;
            handle.z = vertical ? (front.z0 + front.z1) / 2 : na_drawer_handle_z(v, front);
            L.handles.push(handle);
            return;
        }

        const openRight = front.hinge !== 'Right';                             // <-- Hinged left opens on the right edge
        const nearTop   = (v.type === 'Base') || front.row === 'lower';
        const nearBase  = (v.type === 'Wall') || front.row === 'upper';

        if (vertical || knob) {
            handle.x = openRight ? front.x1 - v.handleEdgeInset : front.x0 + v.handleEdgeInset;
            if (nearTop) {
                handle.z      = front.z1 - v.handleEndInset;
                handle.anchor = knob ? 'centre' : 'top';
            } else if (nearBase) {
                handle.z      = front.z0 + v.handleEndInset;
                handle.anchor = knob ? 'centre' : 'bottom';
            } else {
                const low  = front.z0 + v.handleEndInset + NA_TALL_HANDLE_HALF_MM;
                const high = front.z1 - v.handleEndInset - NA_TALL_HANDLE_HALF_MM;
                handle.z   = (low > high) ? (front.z0 + front.z1) / 2 : Math.min(high, Math.max(low, NA_TALL_HANDLE_HEIGHT_MM));
            }
        } else {
            handle.x      = openRight ? front.x1 - v.handleEdgeInset : front.x0 + v.handleEdgeInset;
            handle.anchor = openRight ? 'right' : 'left';
            handle.z      = nearBase ? front.z0 + v.handleEndInset
                          : (nearTop ? front.z1 - v.handleEndInset
                                     : Math.min(front.z1 - v.handleEndInset, Math.max(front.z0 + v.handleEndInset, NA_TALL_HANDLE_HEIGHT_MM)));
        }
        L.handles.push(handle);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Height of a Horizontal Drawer Handle
    // ------------------------------------------------------------
    // A shaker front with its full frame carries the handle on its top rail,
    // clear of the panel joint. A slim front (rails cut down to fit) and the
    // other styles centre it, at most 70 below the top on a deep front.
    function na_drawer_handle_z(v, front) {
        if (front.shaker && front.shaker.rail >= v.shakerFrame - 1e-6) return front.z1 - front.shaker.rail / 2;
        return front.z1 - Math.min((front.z1 - front.z0) / 2, NA_DRAWER_HANDLE_DROP_MM);
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | One Row of Doors Across the Unit
    // ------------------------------------------------------------
    function na_add_door_row(v, L, row, count, z0, z1) {
        const W     = v.width;
        const g     = v.gap;
        const label = (row === 'upper') ? '__Upper' : ((row === 'lower') ? '__Lower' : '');
        for (let j = 0; j < count; j += 1) {
            const hinge = (count === 1) ? v.hinge : (j === 0 ? 'Left' : 'Right');
            const side  = (count === 1) ? '' : (j === 0 ? '__Left' : '__Right');
            na_add_front(v, L, 'Door' + label + side, 'door', row, hinge,
                         j * W / count + g / 2, (j + 1) * W / count - g / 2, z0, z1);
        }
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Every Front for the Chosen Layout
    // ------------------------------------------------------------
    function na_build_fronts(v, L) {
        const g    = v.gap;
        const zLow = v.zBase;
        const zTop = v.zBase + v.height;
        const W    = v.width;

        if (v.layout === 'Open') return;

        if (v.layout === 'Doors') {
            na_add_door_row(v, L, 'full', na_doors_across(v, L), zLow + g / 2, zTop - g / 2);
            return;
        }

        if (v.layout === 'SplitDoors') {
            const split = Math.min(v.splitUpper, v.height - 100);
            const count = na_doors_across(v, L);
            na_add_door_row(v, L, 'upper', count, zTop - split + g / 2, zTop - g / 2);
            na_add_door_row(v, L, 'lower', count, zLow + g / 2, zTop - split - g / 2);
            return;
        }

        if (v.layout === 'DrawerDoors') {
            const drawer = Math.min(v.topDrawer, v.height - 2 * g - 100);
            na_add_front(v, L, 'DrawerFront__01', 'drawer', 'top', null, g / 2, W - g / 2, zTop - g / 2 - drawer, zTop - g / 2);
            na_add_door_row(v, L, 'lower', na_doors_across(v, L), zLow + g / 2, zTop - 1.5 * g - drawer);
            return;
        }

        let cursor = zTop - g / 2;
        na_drawer_heights(v, L).forEach((height, index) => {
            na_add_front(v, L, 'DrawerFront__' + na_pad(index + 1), 'drawer', 'drawer', null, g / 2, W - g / 2, cursor - height, cursor);
            cursor -= height + g;
        });
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Interior
// -----------------------------------------------------------------------------

    // SUB FUNCTION | Shelves (Adjustable, Fixed Split Shelf, Wardrobe Top Shelf)
    // ------------------------------------------------------------
    function na_build_shelves(v, L) {
        const t      = v.board;
        const W      = v.width;
        const D      = v.depth;
        const yBp    = L.yBackPanelFront;
        const zIn0   = v.zBase + t;
        const zIn1   = v.zBase + v.height - t;
        const yFront = -D + Math.min(v.shelfSetback, (yBp + D) - 50);

        const shelf = (name, role, z, front) => L.parts.push(na_box(name, role, t, W - t, front, yBp, z, z + t));
        const spread = (zBottom, zTop, count, first) => {
            const levels = na_shelf_levels(zBottom, zTop, count, t);
            levels.forEach((z, index) => shelf('Shelf__' + na_pad(first + index), 'shelf', z, yFront));
            return levels.length;
        };

        if (v.layout === 'Drawers') return;

        let zones = [[zIn0, zIn1]];
        if (v.layout === 'DrawerDoors') {
            const drawer = L.fronts.filter(front => front.kind === 'drawer')[0];
            zones = [[zIn0, drawer ? drawer.z0 - v.gap / 2 - t : zIn1]];
        }
        if (v.type === 'Tower' && v.layout === 'SplitDoors') {
            const split = v.zBase + v.height - Math.min(v.splitUpper, v.height - 100);
            shelf('FixedShelf', 'fixedShelf', split - t / 2, -D);
            zones = [[zIn0, split - t / 2], [split + t / 2, zIn1]];
        }

        if (v.type === 'Tower' && v.towerInterior === 'Hanging') {
            const top = zIn1 - v.hatShelfDrop;
            if (top - t > zIn0 + 100) {
                shelf('HatShelf', 'hatShelf', top - t, yFront);
                const railZ = top - t - v.railDrop - NA_RAIL_DIAMETER_MM / 2;
                if (railZ - NA_RAIL_DIAMETER_MM / 2 > zIn0) {
                    L.rail = { name: 'HangingRail', x0: t, x1: W - t, y: (-D + yBp) / 2, z: railZ, diameter: NA_RAIL_DIAMETER_MM };
                }
            } else {
                L.warnings.push('The unit is too short for a wardrobe top shelf and rail.');
            }
            return;
        }

        if (zones.length === 1) {
            spread(zones[0][0], zones[0][1], v.shelves, 1);
            return;
        }
        const lower = zones[0][1] - zones[0][0];
        const upper = zones[1][1] - zones[1][0];
        const nUp   = Math.round(v.shelves * upper / Math.max(1, lower + upper));
        const done  = spread(zones[0][0], zones[0][1], v.shelves - nUp, 1);
        spread(zones[1][0], zones[1][1], nUp, 1 + done);
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | A Drawer Box Behind Every Drawer Front
    // ------------------------------------------------------------
    // Side-mount runners: 13 clear each side. The box is a 50mm multiple long
    // (500 in a 560 carcass), 15mm sides, front and back, on a 6mm base.
    function na_build_drawer_boxes(v, L) {
        if (!v.drawerBoxes || v.type !== 'Base') return;
        const t      = v.board;
        const s      = NA_DRAWER_SIDE_MM;
        const zIn0   = v.zBase + t;
        const zIn1   = v.zBase + v.height - t;
        const bx0    = t + NA_RUNNER_CLEARANCE_MM;
        const bx1    = v.width - t - NA_RUNNER_CLEARANCE_MM;
        const inside = L.yBackPanelFront + v.depth;
        const length = Math.floor((inside - NA_DRAWER_REAR_CLEAR_MM) / NA_DRAWER_LENGTH_STEP_MM) * NA_DRAWER_LENGTH_STEP_MM;
        if (bx1 - bx0 < NA_DRAWER_MIN_WIDTH_MM || length < NA_DRAWER_LENGTH_STEP_MM) return;

        const y0 = -v.depth;
        const y1 = y0 + length;
        L.fronts.filter(front => front.kind === 'drawer').forEach((front, index) => {
            const z0  = Math.max(front.z0 + NA_DRAWER_ABOVE_FRONT_BASE_MM, zIn0 + NA_DRAWER_CARCASS_CLEAR_MM);
            const top = Math.min(front.z1 - NA_DRAWER_BELOW_FRONT_TOP_MM, zIn1 - NA_DRAWER_CARCASS_CLEAR_MM);
            if (top - z0 < NA_MIN_FRONT_HEIGHT_MM) return;
            const base  = 'DrawerBox__' + na_pad(index + 1);
            L.drawerBoxes.push({
                name : base,
                parts: [
                    na_box(base + '__Side__Left',  'drawerSide',  bx0, bx0 + s, y0, y1, z0, top),
                    na_box(base + '__Side__Right', 'drawerSide',  bx1 - s, bx1, y0, y1, z0, top),
                    na_box(base + '__Front',       'drawerFront', bx0 + s, bx1 - s, y0, y0 + s, z0, top),
                    na_box(base + '__Back',        'drawerBack',  bx0 + s, bx1 - s, y1 - s, y1, z0, top),
                    na_box(base + '__Base',        'drawerBase',  bx0 + s, bx1 - s, y0 + s, y1 - s, z0, z0 + NA_DRAWER_BASE_MM)
                ]
            });
        });
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Plinth and Legs
// -----------------------------------------------------------------------------

    // SUB FUNCTION | Plinth Board and Leg Points (Floor Standing Units Only)
    // ------------------------------------------------------------
    // The plinth runs the full width so a run of units reads as one. The
    // front legs stand just behind the plinth (the plinth clips to them), the
    // back legs in from the back; units over 900 wide get a middle pair.
    function na_build_plinth_and_legs(v, L) {
        if (v.type === 'Wall' || v.zBase <= 0) return;
        const W = v.width;
        const D = v.depth;

        const setback  = Math.max(0, Math.min(v.plinthSetback, D / 2 - v.plinthThickness));
        const hasPlinth = v.plinthEnabled && v.zBase >= NA_PLINTH_MIN_HEIGHT_MM;
        if (hasPlinth) {
            L.plinth = na_box('Plinth', 'plinth', 0, W, -D + setback, -D + setback + v.plinthThickness, 0, v.zBase);
        }

        if (!v.legsEnabled) return;
        if (v.zBase < NA_LEG_MIN_HEIGHT_MM) {
            L.warnings.push('Legs need a plinth height of at least ' + NA_LEG_MIN_HEIGHT_MM + 'mm.');
            return;
        }

        let xs = (W < 2 * v.legSideInset + NA_LEG_MIN_ROW_GAP_MM) ? [W / 2] : [v.legSideInset, W - v.legSideInset];
        if (xs.length === 2 && W > NA_MIDDLE_LEGS_OVER_MM) xs = [xs[0], W / 2, xs[1]];

        const yFront = hasPlinth ? (-D + setback + v.plinthThickness + NA_LEG_BEHIND_PLINTH_MM) : (-D + v.legBackInset);
        const yBack  = -Math.max(v.legBackInset, v.backInset + v.back + NA_LEG_BEHIND_BACK_MM);
        const ys     = (yBack - yFront >= NA_LEG_MIN_ROW_GAP_MM) ? [yFront, yBack] : [(yFront + yBack) / 2];

        L.legHeight = v.zBase;
        ys.forEach(y => xs.forEach(x => L.legs.push({ x: x, y: y })));
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Public API
// -----------------------------------------------------------------------------

    // FUNCTION | Resolve a Configuration Into Its Parts
    // ------------------------------------------------------------
    // @param  {Object} cfg - Na__CabinetConfiguration block
    // @return {Object}       { values, parts, fronts, handles, drawerBoxes,
    //                          rail, plinth, legs, legHeight, bounds, warnings }
    function na_resolve(cfg) {
        const v = na_effective(cfg);
        const L = {
            values         : v,
            yBackPanelFront: -(v.backInset + v.back),
            parts          : [],
            fronts         : [],
            handles        : [],
            drawerBoxes    : [],
            rail           : null,
            plinth         : null,
            legs           : [],
            legHeight      : 0,
            warnings       : []
        };

        na_build_carcass(v, L);
        na_build_fronts(v, L);
        na_build_shelves(v, L);
        na_build_drawer_boxes(v, L);
        na_build_plinth_and_legs(v, L);
        L.parts = L.parts.filter(na_box_ok);

        L.bounds = {
            x0: 0,
            x1: v.width,
            y0: -(v.depth + (L.fronts.length ? v.frontThickness : 0)),
            y1: 0,
            z0: (v.type === 'Wall') ? v.zBase : 0,
            z1: v.zBase + v.height
        };
        return L;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Stretch a Leg Asset Height Value to a Plinth Height (mm)
    // ------------------------------------------------------------
    // Mirrors Na__AssetMeshBuilder.na_stretch_z: above the stretch zone moves
    // by the difference, inside it scales; shorter than the zone allows, the
    // zone closes and the rest scales to fit.
    // @param {Number} z      - height in the asset (mm)
    // @param {Object} leg    - { nominal, zoneMin, zoneMax } (asset metadata)
    // @param {Number} height - wanted leg height (mm)
    function na_stretch_leg_z(z, leg, height) {
        const nominal = Number(leg && leg.nominal) || 0;
        const lo      = Number(leg && leg.zoneMin) || 0;
        const hi      = Number(leg && leg.zoneMax) || 0;
        if (nominal <= 0 || hi <= lo) return z;
        const zone    = hi - lo;
        const delta   = height - nominal;
        const newZone = zone + delta;
        if (newZone <= 0) {
            const closed = z <= lo ? z : (z >= hi ? z - zone : lo);
            return closed * (height / (nominal - zone));
        }
        if (z <= lo) return z;
        if (z >= hi) return z + delta;
        return lo + (z - lo) * (newZone / zone);
    }
    // ---------------------------------------------------------------

    window.Na__Cabinetry__LayoutResolver = {
        na_resolve       : na_resolve,
        na_effective     : na_effective,
        na_is_knob       : na_is_knob,
        na_stretch_leg_z : na_stretch_leg_z
    };

// endregion -------------------------------------------------------------------

})();

// =============================================================================
// END OF FILE
// =============================================================================
