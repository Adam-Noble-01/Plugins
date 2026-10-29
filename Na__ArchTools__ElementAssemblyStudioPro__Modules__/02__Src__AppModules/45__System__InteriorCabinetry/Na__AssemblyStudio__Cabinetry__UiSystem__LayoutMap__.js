// =============================================================================
// ELEMENT ASSEMBLY STUDIO PRO - INTERIOR CABINETRY SYSTEM - SECTION LAYOUT MAP
// =============================================================================
//
// FILE       : Na__AssemblyStudio__Cabinetry__UiSystem__LayoutMap__.js
// AUTHOR     : Noble Architecture
// PURPOSE    : Where every control of the Cabinetry tab lives: section, tier
//              (1 shown, 2 More, 3 Advanced) and product. Registered with
//              Na__Ui__SectionLayout, which moves the controls Na_CabinetUI
//              builds on every mount into these slots.
// CREATED    : 29-Oct-2026
//
// THE ORDER, AND WHY
// - The unit first (Base, Drawers, Wall, Tall, Wardrobe chips above the
//   preview), then its size, its doors and drawers, what is inside, the
//   carcass, the plinth and legs, the handles, the finish, and what is built.
// - Tier 1 holds what a fitter changes on almost every unit: width, height,
//   depth, door style, fronts, drawers, shelves, plinth height, handle and
//   the two finishes. The board thickness (20mm, or 18mm for true sizes) is
//   in Carcass > Advanced.
//
// PRODUCTS
// - base     : Base unit (doors, drawer + door, open)      UnitType Base
// - drawers  : Drawer unit                                 UnitType Base, Fronts Drawers
// - wall     : Wall unit                                   UnitType Wall
// - tall     : Tall unit (larder, housing)                 UnitType Tower, Inside Shelves
// - wardrobe : Fitted wardrobe                             UnitType Tower, Inside Hanging Rail
//
// NAMING CONVENTION:
// - All identifiers use Na_ / na_ prefix.
//
// =============================================================================

(function () {
    'use strict';

    var K = 'Na__CabinetConfig__';

// -----------------------------------------------------------------------------
// REGION | Products
// -----------------------------------------------------------------------------

    var NA_PRODUCTS = [
        { key: 'base',     group: 'Kitchen', label: 'Base',     title: 'Base Unit: 720 carcass on 150 legs, 560 deep',
          icon: '<rect x="4" y="4.5" width="16" height="13" rx="1"/><path d="M5.5 17.5v2.5M18.5 17.5v2.5M12 4.5v13"/><circle cx="10.4" cy="8" r=".8"/><circle cx="13.6" cy="8" r=".8"/>' },
        { key: 'drawers',  group: 'Kitchen', label: 'Drawers',  title: 'Drawer Unit: 140 top drawer over two pan drawers',
          icon: '<rect x="4" y="4.5" width="16" height="13" rx="1"/><path d="M4 8.5h16M4 13h16M5.5 17.5v2.5M18.5 17.5v2.5M10.5 6.5h3M10.5 10.7h3M10.5 15.2h3"/>' },
        { key: 'wall',     group: 'Kitchen', label: 'Wall',     title: 'Wall Unit: 720 high, 300 deep, hung 1400 above the floor',
          icon: '<path d="M3 3.5h18"/><rect x="5" y="5" width="14" height="10" rx="1"/><path d="M12 5v10M10.4 12.6v.4M13.6 12.6v.4"/>' },
        { key: 'tall',     group: 'Kitchen', label: 'Tall',     title: 'Tall Unit: 1970 larder on 150 legs, tops level with wall units',
          icon: '<rect x="7" y="2.5" width="10" height="17.5" rx="1"/><path d="M7 8.5h10M15.2 6.2v1M15.2 10v1.5M8 20v1.5M16 20v1.5"/>' },
        { key: 'wardrobe', group: 'Bedroom', label: 'Wardrobe', title: 'Fitted Wardrobe: 2150 high, 600 deep, top shelf and hanging rail',
          icon: '<rect x="4" y="2.5" width="16" height="17.5" rx="1"/><path d="M12 2.5v17.5M5.5 7h13M8.5 7l-1.5 3h3zM15.5 7l-1.5 3h3zM5.5 20v1.5M18.5 20v1.5"/>' }
    ];

    var NA_FLOOR_PRODUCTS = ['base', 'drawers', 'tall', 'wardrobe'];
    var NA_BASE_PRODUCTS  = ['base', 'drawers'];
    var NA_TOWER_PRODUCTS = ['tall', 'wardrobe'];

    // HELPER FUNCTION | Which Product the Config Is Set Up For
    // ------------------------------------------------------------
    function na_active_product(cfg) {
        var type = String(cfg[K + 'UnitType'] || 'Base');
        if (type === 'Wall')  return 'wall';
        if (type === 'Tower') return cfg[K + 'TowerInterior'] === 'Hanging' ? 'wardrobe' : 'tall';
        return cfg[K + 'BaseFrontLayout'] === 'Drawers' ? 'drawers' : 'base';
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | A Product's Full Name
    // ------------------------------------------------------------
    function na_product_name(key) {
        var product = NA_PRODUCTS.filter(function (entry) { return entry.key === key; })[0];
        return product ? product.title.split(':')[0] : '';
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Switch Product Through Na_CabinetUI
    // ------------------------------------------------------------
    // A chip only moves a size that still holds the other product's starting
    // value, so a height typed in by hand survives Tall <-> Wardrobe.
    function na_select_product(key) {
        var ui = window.Na_CabinetUI;
        if (!ui || typeof ui.na_apply_values !== 'function') return;
        var cfg     = ui.na_get_ui_config();
        var updates = {};

        if (key === 'base' || key === 'drawers') {
            updates[K + 'UnitType'] = 'Base';
            if (key === 'drawers') updates[K + 'BaseFrontLayout'] = 'Drawers';
            else if (cfg[K + 'BaseFrontLayout'] === 'Drawers') updates[K + 'BaseFrontLayout'] = 'Doors';
        } else if (key === 'wall') {
            updates[K + 'UnitType'] = 'Wall';
        } else {
            var other = (key === 'tall') ? 'wardrobe' : 'tall';
            updates[K + 'UnitType']      = 'Tower';
            updates[K + 'TowerInterior'] = (key === 'wardrobe') ? 'Hanging' : 'Shelves';
            [K + 'TowerHeight_mm', K + 'TowerDepth_mm', K + 'TowerFrontLayout'].forEach(function (id) {
                if (na_same(cfg[id], na_default_of(id, other))) updates[id] = na_default_of(id, key);
            });
        }
        ui.na_apply_values(updates);
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Config Tests and Summary Helpers
// -----------------------------------------------------------------------------

    // HELPER FUNCTION | The Front Layout of the Unit Type in Use
    // ------------------------------------------------------------
    function na_layout(cfg) {
        var type = String(cfg[K + 'UnitType'] || 'Base');
        if (type === 'Wall')  return cfg[K + 'WallFrontLayout'] || 'Doors';
        if (type === 'Tower') return cfg[K + 'TowerFrontLayout'] || 'SplitDoors';
        return cfg[K + 'BaseFrontLayout'] || 'Doors';
    }
    // ---------------------------------------------------------------

    function na_has_doors(cfg)      { return ['Doors', 'DrawerDoors', 'SplitDoors'].indexOf(na_layout(cfg)) !== -1; }
    function na_is_drawers(cfg)     { return String(cfg[K + 'UnitType'] || 'Base') === 'Base' && na_layout(cfg) === 'Drawers'; }
    function na_has_drawers(cfg)    { return na_is_drawers(cfg) || (String(cfg[K + 'UnitType'] || 'Base') === 'Base' && na_layout(cfg) === 'DrawerDoors'); }
    function na_is_hanging(cfg)     { return String(cfg[K + 'UnitType']) === 'Tower' && cfg[K + 'TowerInterior'] === 'Hanging'; }
    function na_style(cfg)          { return cfg[K + 'DoorStyle'] || 'Shaker'; }
    function na_has_handles(cfg)    { return na_style(cfg) !== 'Recessed' && String(cfg[K + 'HandleAssetKey'] || '') !== 'None'; }

    // HELPER FUNCTION | Does the Layout Resolve to a Single Door Somewhere
    // ------------------------------------------------------------
    function na_single_door(cfg) {
        if (!na_has_doors(cfg)) return false;
        var resolver = window.Na__Cabinetry__LayoutResolver;
        if (!resolver) return true;
        return resolver.na_resolve(cfg).fronts.some(function (front) {
            return front.kind === 'door' && front.name.indexOf('__Left') === -1 && front.name.indexOf('__Right') === -1;
        });
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Does the Unit Have Any Shelves to Set Back
    // ------------------------------------------------------------
    function na_has_shelves(cfg) {
        if (na_is_drawers(cfg)) return false;
        var type = String(cfg[K + 'UnitType'] || 'Base');
        if (type === 'Tower') return true;                                     // <-- Split shelf or wardrobe top shelf
        return Number(cfg[K + (type === 'Wall' ? 'WallShelfCount' : 'BaseShelfCount')]) > 0;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | A Number for Display (Unset Shows as a Dash)
    // ------------------------------------------------------------
    function na_num(value) {
        var number = Number(value);
        return isFinite(number) ? String(Math.round(number)) : '-';
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | The Label of an Option Value
    // ------------------------------------------------------------
    function na_option_label(id, value) {
        var label = String(value == null ? '' : value);
        na_descriptor_arrays().forEach(function (list) {
            list.forEach(function (descriptor) {
                if (!descriptor || descriptor.id !== id || !Array.isArray(descriptor.options)) return;
                descriptor.options.forEach(function (option) {
                    if (String(option.value) === String(value)) label = option.label;
                });
            });
        });
        return label;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | The Chosen Swatch Name of a Material Card Row
    // ------------------------------------------------------------
    function na_picked_card(id) {
        var container = document.getElementById(id + '-cards');
        var chosen = container ? container.querySelector('.na-material-card-selected') : null;
        return chosen ? (chosen.getAttribute('title') || '') : '';
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Height and Depth Keys of the Unit Type in Use
    // ------------------------------------------------------------
    function na_size_keys(cfg) {
        var type = String(cfg[K + 'UnitType'] || 'Base');
        var tag  = (type === 'Wall') ? 'Wall' : ((type === 'Tower') ? 'Tower' : 'Base');
        return { height: K + tag + 'Height_mm', depth: K + tag + 'Depth_mm' };
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Fronts Summary ("Shaker · 1 door, hinged left")
    // ------------------------------------------------------------
    function na_fronts_summary(cfg) {
        var style  = na_option_label(K + 'DoorStyle', na_style(cfg));
        var layout = na_layout(cfg);
        if (layout === 'Open') return 'Open, no fronts';
        var resolver = window.Na__Cabinetry__LayoutResolver;
        var fronts   = resolver ? resolver.na_resolve(cfg).fronts : [];
        var doors    = fronts.filter(function (front) { return front.kind === 'door'; }).length;
        var drawers  = fronts.filter(function (front) { return front.kind === 'drawer'; }).length;
        var parts    = [];
        if (drawers) parts.push(drawers + (drawers === 1 ? ' drawer' : ' drawers'));
        if (doors)   parts.push(doors + (doors === 1 ? ' door' : ' doors'));
        var hinge = (doors === 1) ? ', hinged ' + String(cfg[K + 'HingeSide'] || 'Left').toLowerCase() : '';
        return style + ' · ' + parts.join(' + ') + hinge;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Interior Summary
    // ------------------------------------------------------------
    function na_interior_summary(cfg) {
        if (na_is_drawers(cfg)) return cfg[K + 'DrawerBoxesEnabled'] === false ? 'Drawer fronts only' : 'Drawer boxes behind each front';
        if (na_is_hanging(cfg)) return 'Top shelf and hanging rail';
        var type  = String(cfg[K + 'UnitType'] || 'Base');
        var count = Number(cfg[K + (type === 'Wall' ? 'WallShelfCount' : (type === 'Tower' ? 'TowerShelfCount' : 'BaseShelfCount'))]) || 0;
        var text  = count === 0 ? 'No shelves' : (count === 1 ? '1 shelf' : count + ' shelves');
        if (type === 'Tower' && na_layout(cfg) === 'SplitDoors') text += ' + fixed shelf at the split';
        return text;
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Sections and Items
// -----------------------------------------------------------------------------

    var NA_NEED_SHAKER   = { text: 'Door Style: Shaker',          fix: [[K + 'DoorStyle', 'Shaker']] };
    var NA_NEED_RECESSED = { text: 'Door Style: Recessed Handle', fix: [[K + 'DoorStyle', 'Recessed']] };
    var NA_NEED_DRAWERS  = { text: 'Fronts: Drawers',             fix: [[K + 'UnitType', 'Base'], [K + 'BaseFrontLayout', 'Drawers']] };
    var NA_NEED_PLINTH   = { text: 'Include Plinth on',           fix: [[K + 'PlinthEnabled', true]] };
    var NA_NEED_LEGS     = { text: 'Include Legs on',             fix: [[K + 'LegsEnabled', true]] };
    var NA_NEED_HANGING  = { text: 'Inside: Hanging Rail',        fix: [[K + 'UnitType', 'Tower'], [K + 'TowerInterior', 'Hanging']] };

    var NA_SECTIONS = [
        {
            key: 'size', title: 'Size',
            summary: function (cfg) {
                var keys = na_size_keys(cfg);
                var text = na_num(cfg[K + 'Width_mm']) + ' × ' + na_num(cfg[keys.height]) + ' × ' + na_num(cfg[keys.depth]) + ' mm';
                if (String(cfg[K + 'UnitType']) === 'Wall') text += ' · underside ' + na_num(cfg[K + 'WallMountHeight_mm']) + ' up';
                return text;
            },
            items: [
                { id: K + 'Width_mm',           kw: 'width wide unit size 300 400 500 600 800 1000' },
                { id: K + 'BaseHeight_mm',      products: NA_BASE_PRODUCTS,  kw: 'height carcass 720 worktop' },
                { id: K + 'WallHeight_mm',      products: ['wall'],          kw: 'height carcass 575 720 900' },
                { id: K + 'TowerHeight_mm',     products: NA_TOWER_PRODUCTS, kw: 'height carcass 1820 1970 2150 larder wardrobe' },
                { id: K + 'BaseDepth_mm',       products: NA_BASE_PRODUCTS,  kw: 'depth deep carcass 560 570' },
                { id: K + 'WallDepth_mm',       products: ['wall'],          kw: 'depth deep carcass 300 330' },
                { id: K + 'TowerDepth_mm',      products: NA_TOWER_PRODUCTS, kw: 'depth deep carcass 560 600' },
                { id: K + 'WallMountHeight_mm', products: ['wall'],          kw: 'mounting height above floor underside fixing level 1400' }
            ]
        },
        {
            key: 'fronts', title: 'Doors & Drawers',
            summary: na_fronts_summary,
            items: [
                { id: K + 'DoorStyle',          kw: 'door style shaker flat slab handleless recessed j pull groove' },
                { id: K + 'BaseFrontLayout',    products: NA_BASE_PRODUCTS,  kw: 'fronts layout doors drawers drawerline open' },
                { id: K + 'WallFrontLayout',    products: ['wall'],          kw: 'fronts layout doors open' },
                { id: K + 'TowerFrontLayout',   products: NA_TOWER_PRODUCTS, kw: 'fronts layout full height split larder doors open' },
                { id: K + 'DrawerCount',        products: NA_BASE_PRODUCTS,  kw: 'drawers number count pan drawers',
                  showIf: na_is_drawers, need: NA_NEED_DRAWERS },
                { id: K + 'HingeSide',          kw: 'hinge hinged side hand handing left right',
                  showIf: na_single_door },
                { id: K + 'DoorCount',          tier: 2, kw: 'doors across pair single double one two',
                  showIf: na_has_doors },
                { id: K + 'DrawerLayout',       tier: 2, products: NA_BASE_PRODUCTS, kw: 'drawer heights graduated equal',
                  showIf: na_is_drawers, need: NA_NEED_DRAWERS },
                { id: K + 'TopDrawerHeight_mm', tier: 2, products: NA_BASE_PRODUCTS, kw: 'top drawer front height 140 drawerline',
                  showIf: function (cfg) { return na_layout(cfg) === 'DrawerDoors' || (na_is_drawers(cfg) && cfg[K + 'DrawerLayout'] !== 'Equal'); } },
                { id: K + 'SplitUpperHeight_mm', tier: 2, products: NA_TOWER_PRODUCTS, kw: 'upper door split height larder',
                  showIf: function (cfg) { return na_layout(cfg) === 'SplitDoors'; } },
                { id: K + 'ShakerFrameWidth_mm', tier: 2, kw: 'shaker frame stile rail width',
                  showIf: function (cfg) { return na_style(cfg) === 'Shaker'; }, need: NA_NEED_SHAKER },
                { id: K + 'GrooveOffset_mm',    tier: 2, kw: 'handle groove recess finger pull position edge',
                  showIf: function (cfg) { return na_style(cfg) === 'Recessed'; }, need: NA_NEED_RECESSED },
                { id: K + 'DoorThickness_mm',   tier: 2, kw: 'door front thickness' },
                { id: K + 'DoorGap_mm',         tier: 3, kw: 'gap between fronts reveal clearance' },
                { id: K + 'ShakerPanelRecess_mm', tier: 3, kw: 'shaker panel recess depth',
                  showIf: function (cfg) { return na_style(cfg) === 'Shaker'; }, need: NA_NEED_SHAKER },
                { id: K + 'GrooveWidth_mm',     tier: 3, kw: 'handle groove width',
                  showIf: function (cfg) { return na_style(cfg) === 'Recessed'; }, need: NA_NEED_RECESSED },
                { id: K + 'GrooveDepth_mm',     tier: 3, kw: 'handle groove depth',
                  showIf: function (cfg) { return na_style(cfg) === 'Recessed'; }, need: NA_NEED_RECESSED }
            ]
        },
        {
            key: 'interior', title: 'Interior',
            summary: na_interior_summary,
            emptyNote: function (cfg) {
                return na_is_drawers(cfg) ? 'Each drawer front has its own drawer box behind it. Output can leave the boxes out.'
                                          : 'Nothing to set here for this product.';
            },
            items: [
                { id: K + 'BaseShelfCount',     products: NA_BASE_PRODUCTS,  kw: 'shelves shelf number count',
                  showIf: function (cfg) { return !na_is_drawers(cfg); } },
                { id: K + 'WallShelfCount',     products: ['wall'],          kw: 'shelves shelf number count' },
                { id: K + 'TowerInterior',      products: NA_TOWER_PRODUCTS, kw: 'inside interior shelves hanging rail wardrobe' },
                { id: K + 'TowerShelfCount',    products: NA_TOWER_PRODUCTS, kw: 'shelves shelf number count larder',
                  showIf: function (cfg) { return !na_is_hanging(cfg); } },
                { id: K + 'HatShelfDrop_mm',    tier: 2, products: NA_TOWER_PRODUCTS, kw: 'wardrobe top hat shelf height',
                  showIf: na_is_hanging, need: NA_NEED_HANGING },
                { id: K + 'ShelfSetback_mm',    tier: 2, kw: 'shelf set back front',
                  showIf: na_has_shelves },
                { id: K + 'RailDropBelowShelf_mm', tier: 3, products: NA_TOWER_PRODUCTS, kw: 'hanging rail height drop',
                  showIf: na_is_hanging, need: NA_NEED_HANGING }
            ]
        },
        {
            key: 'carcass', title: 'Carcass',
            summary: function (cfg) {
                var top = (String(cfg[K + 'UnitType'] || 'Base') === 'Base' && cfg[K + 'BaseTopConstruction'] !== 'TopPanel') ? 'two top rails' : 'top panel';
                var scribe = Number(cfg[K + 'BackPanelInset_mm']) > 0 ? na_num(cfg[K + 'BackPanelInset_mm']) + ' scribe' : 'no scribe';
                return na_num(cfg[K + 'BoardThickness_mm']) + 'mm board · ' + top + ' · ' + na_num(cfg[K + 'BackPanelThickness_mm']) + 'mm back · ' + scribe;
            },
            items: [
                { id: K + 'BaseTopConstruction',   products: NA_BASE_PRODUCTS, kw: 'top rails panel stretchers cross bar' },
                { id: K + 'TopRailDepth_mm',       tier: 2, products: NA_BASE_PRODUCTS, kw: 'top rail depth width',
                  showIf: function (cfg) { return cfg[K + 'BaseTopConstruction'] !== 'TopPanel'; } },
                { id: K + 'BackPanelThickness_mm', tier: 2, kw: 'back panel thickness' },
                { id: K + 'BoardThickness_mm',     tier: 3, kw: 'carcass board thickness 18mm 20mm chipboard real true accurate' },
                { id: K + 'BackPanelInset_mm',     tier: 3, kw: 'scribe scribing back panel set in recessed service void wall' }
            ]
        },
        {
            key: 'plinth', title: 'Plinth & Legs',
            summary: function (cfg) {
                var height = Number(cfg[K + 'PlinthHeight_mm']);
                if (!(height > 0)) return 'Stands on the floor';
                var parts = [na_num(height) + ' plinth'];
                if (cfg[K + 'PlinthEnabled'] !== false) parts.push('set back ' + na_num(cfg[K + 'PlinthSetback_mm']));
                else parts.push('no plinth board');
                var resolver = window.Na__Cabinetry__LayoutResolver;
                var legs = resolver ? resolver.na_resolve(cfg).legs.length : 0;
                parts.push(legs ? legs + ' legs' : 'no legs');
                return parts.join(' · ');
            },
            items: [
                { id: K + 'PlinthHeight_mm',     products: NA_FLOOR_PRODUCTS, kw: 'plinth kickboard toe kick base board skirting leg height 150' },
                { id: K + 'PlinthEnabled',       products: NA_FLOOR_PRODUCTS, kw: 'include plinth kickboard' },
                { id: K + 'PlinthSetback_mm',    tier: 2, products: NA_FLOOR_PRODUCTS, kw: 'plinth set back recess toe space',
                  showIf: function (cfg) { return cfg[K + 'PlinthEnabled'] !== false; }, need: NA_NEED_PLINTH },
                { id: K + 'LegsEnabled',         tier: 2, products: NA_FLOOR_PRODUCTS, kw: 'include legs feet' },
                { id: K + 'LegAssetKey',         tier: 2, products: NA_FLOOR_PRODUCTS, kw: 'leg type adjustable feet',
                  showIf: function (cfg) { return cfg[K + 'LegsEnabled'] !== false; }, need: NA_NEED_LEGS },
                { id: K + 'PlinthThickness_mm',  tier: 3, products: NA_FLOOR_PRODUCTS, kw: 'plinth thickness',
                  showIf: function (cfg) { return cfg[K + 'PlinthEnabled'] !== false; }, need: NA_NEED_PLINTH },
                { id: K + 'PlinthMatchesDoors',  tier: 3, products: NA_FLOOR_PRODUCTS, kw: 'plinth finish colour match doors',
                  showIf: function (cfg) { return cfg[K + 'PlinthEnabled'] !== false; }, need: NA_NEED_PLINTH },
                { id: K + 'LegSideInset_mm',     tier: 3, products: NA_FLOOR_PRODUCTS, kw: 'leg position sides inset',
                  showIf: function (cfg) { return cfg[K + 'LegsEnabled'] !== false; }, need: NA_NEED_LEGS },
                { id: K + 'LegBackInset_mm',     tier: 3, products: NA_FLOOR_PRODUCTS, kw: 'leg position back inset',
                  showIf: function (cfg) { return cfg[K + 'LegsEnabled'] !== false; }, need: NA_NEED_LEGS }
            ]
        },
        {
            key: 'hardware', title: 'Handles',
            summary: function (cfg) {
                if (na_style(cfg) === 'Recessed') return 'Recessed handle groove';
                if (!na_has_handles(cfg)) return 'No handles';
                var select = document.getElementById(K + 'HandleAssetKey-select');
                var name   = (select && select.selectedIndex >= 0) ? select.options[select.selectedIndex].textContent : 'Handle';
                var finish = na_picked_card(K + 'HandleMaterialId');
                return name + (finish ? ' · ' + finish : '');
            },
            offNote: function (cfg) {
                return na_style(cfg) === 'Recessed' ? 'Recessed handle fronts open by their groove, so no handles are fitted.' : '';
            },
            items: [
                { id: K + 'HandleAssetKey',     kw: 'handle knob bar d pull hardware ironmongery' },
                { id: K + 'HandleMaterialId',   kw: 'handle finish chrome brushed steel brass nickel bronze',
                  showIf: na_has_handles },
                { id: K + 'HandleOrientation',  tier: 2, kw: 'handle direction vertical horizontal',
                  showIf: na_has_handles },
                { id: K + 'HandleEdgeInset_mm', tier: 2, kw: 'handle position in from edge',
                  showIf: na_has_handles },
                { id: K + 'HandleEndInset_mm',  tier: 2, kw: 'handle position from top bottom',
                  showIf: na_has_handles }
            ]
        },
        {
            key: 'finish', title: 'Finish',
            summary: function () {
                var doors   = na_picked_card(K + 'DoorMaterialId');
                var carcass = na_picked_card(K + 'CarcassMaterialId');
                return (doors || 'Default') + ' fronts · ' + (carcass || 'Default') + ' carcass';
            },
            emptyNote: function () {
                return 'The finish swatches arrive from the materials library when SketchUp opens the dialog.';
            },
            items: [
                { id: K + 'DoorMaterialId',    kw: 'door front finish colour paint wood' },
                { id: K + 'CarcassMaterialId', kw: 'carcass cabinet body finish colour' }
            ]
        },
        {
            key: 'output', title: 'Output',
            summary: function (cfg) {
                if (!na_has_drawers(cfg)) return 'Carcass, fronts and fittings';
                return cfg[K + 'DrawerBoxesEnabled'] === false ? 'Drawer fronts only' : 'Drawer boxes built';
            },
            emptyNote: function () {
                return 'Drawer boxes are the only optional part, and this unit has no drawers.';
            },
            items: [
                { id: K + 'DrawerBoxesEnabled', products: NA_BASE_PRODUCTS, kw: 'build drawer boxes lighter model',
                  showIf: na_has_drawers, need: NA_NEED_DRAWERS }
            ]
        }
    ];

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Defaults (for the Changed Chip and Reset)
// -----------------------------------------------------------------------------

    var na_defaults = null;

    // HELPER FUNCTION | Every Descriptor Array the Tab Builds From
    // ------------------------------------------------------------
    function na_descriptor_arrays() {
        return [
            window.NA_CABINET_PRODUCT_CONFIG, window.NA_CABINET_SIZE_CONFIG, window.NA_CABINET_FRONTS_CONFIG,
            window.NA_CABINET_INTERIOR_CONFIG, window.NA_CABINET_CARCASS_CONFIG, window.NA_CABINET_PLINTH_CONFIG,
            window.NA_CABINET_HARDWARE_CONFIG, window.NA_CABINET_FINISH_CONFIG, window.NA_CABINET_OUTPUT_CONFIG
        ].filter(Array.isArray);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | The Default of One Setting for a Product
    // ------------------------------------------------------------
    function na_default_of(id, product) {
        if (!na_defaults) {
            na_defaults = {};
            na_descriptor_arrays().forEach(function (list) {
                list.forEach(function (descriptor) {
                    if (descriptor && descriptor.id) na_defaults[descriptor.id] = descriptor.default;
                });
            });
        }
        var overrides = (window.NA_CABINET_PRODUCT_DEFAULTS || {})[product] || {};
        return Object.prototype.hasOwnProperty.call(overrides, id) ? overrides[id] : na_defaults[id];
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Loose Equality (5 Equals "5")
    // ------------------------------------------------------------
    function na_same(a, b) {
        if (a === b) return true;
        if (a == null || b == null) return false;
        var numA = Number(a);
        var numB = Number(b);
        if (String(a).trim() !== '' && String(b).trim() !== '' && isFinite(numA) && isFinite(numB)) return Math.abs(numA - numB) < 1e-6;
        return String(a) === String(b);
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Registration
// -----------------------------------------------------------------------------

    if (!window.Na__Ui__SectionLayout) {
        console.error('[NA_CABINET_LAYOUT] Na__Ui__SectionLayout not loaded - the Cabinetry tab keeps its build containers');
        return;
    }

    window.Na__Ui__SectionLayout.na_register('cabinets', {
        panelId          : 'na-tab-cabinets',
        sectionsHostId   : 'na-lay-sections-cabinets',
        resultsHostId    : 'na-lay-results-cabinets',
        stagingId        : 'na-lay-staging-cabinets',
        productStripId   : 'na-lay-products-cabinets',
        searchInputId    : 'na-search-cabinets',
        changedChipId    : 'na-chg-cabinets',
        previewId        : 'na-preview-cabinets',
        stickyTopId      : 'na-panel-top-cabinets',
        scrollerSelector : '.na-main-content',
        fallbackSection  : 'output',
        hiddenIds        : [K + 'UnitType'],                                    // <-- Replaced by the product chips
        products         : NA_PRODUCTS,
        sections         : NA_SECTIONS,
        getConfig        : function () {
            return (window.Na_CabinetUI && typeof window.Na_CabinetUI.na_get_ui_config === 'function') ? window.Na_CabinetUI.na_get_ui_config() : {};
        },
        setValue         : function (id, value) {
            if (window.Na_CabinetUI && typeof window.Na_CabinetUI.na_apply_control_value === 'function') window.Na_CabinetUI.na_apply_control_value(id, value);
        },
        activeProduct    : na_active_product,
        selectProduct    : na_select_product,
        productName      : na_product_name,
        defaultOf        : na_default_of,
        onRefresh        : function (cfg) {
            var badge = document.getElementById('na-preview-size-cabinets');
            var keys  = na_size_keys(cfg);
            if (badge) badge.textContent = na_num(cfg[K + 'Width_mm']) + ' × ' + na_num(cfg[keys.height]) + ' × ' + na_num(cfg[keys.depth]);
        }
    });

    window.Na__Cabinetry__LayoutMap = {
        na_active_product : na_active_product,
        na_default_of     : na_default_of,
        na_select_product : na_select_product
    };

// endregion -------------------------------------------------------------------

})();

// =============================================================================
// END OF FILE
// =============================================================================
