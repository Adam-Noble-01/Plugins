/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - WINDOW SYSTEM - SECTION LAYOUT MAP
   =============================================================================
   FILE       : Na__AssemblyStudio__WindowSystem__UiSystem__LayoutMap__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Where every control of the Windows & Exterior Doors tab lives:
                which section, which tier (1 shown, 2 More, 3 Advanced), which
                group and which products. Registered with
                Na__Ui__SectionLayout, which moves the controls MainUiLogic
                builds into these slots.
   CREATED    : 28-Oct-2026

   THE ORDER, AND WHY
   - Product first (the strip above the preview), then the order you would
     say it in: size, the lights or the opening, the leaves, the glass, the
     fielded panels, the frame and cill, the casements or sashes, the
     hardware, the finish, and last what gets built (Output).
   - Each topic has one home: everything about the frame is in Frame & Cill,
     everything about glass is in Glazing.
   - Tiers follow use. Tier 1 holds what the saved presets change most
     (size, frame thickness, wall inset, cill, glaze bars, finish, Fuse
     Parts); per-mullion / per-bar offsets, per-casement settings, per-leaf
     overrides and edge colours sit in Advanced.
   - Doors get their own Hardware section (handle, pairing, height, position,
     handle finish), all Tier 1, ahead of Finish.

   ADDING A CONTROL
   - Add its descriptor to the system's UiSystem Config file as before, then
     give its id a slot here. A control without a slot still appears, under
     Output > Advanced > Other, and the console says so.
   - Optional per item: showIf (a layout-level visibility rule), need (what
     the search says when it is hidden, with a "Turn It On" fix), kw (search
     keywords), products, kind (see the SectionLayout header).
   ============================================================================= */

(function () {
    'use strict';

    // -----------------------------------------------------------------------------
    // REGION | Products
    // -----------------------------------------------------------------------------

    const NA_W  = ['casement', 'sash'];
    const NA_D  = ['single', 'double', 'bifold', 'sliding'];
    const NA_HD = ['single', 'double'];

    const NA_DOOR_PREFIX = { single: 'single_door', double: 'double_door', bifold: 'bifold_door', sliding: 'sliding_door' };

    const NA_PRODUCTS = [
        { key: 'casement', group: 'Window',        label: 'Casement',     title: 'Casement Window',     category: 'Window',        type: 'Casement',
          icon: '<rect x="4" y="3" width="16" height="18" rx="1"/><path d="M12 3v18"/><path d="M13.5 5.5 18 12l-4.5 6.5" opacity=".55"/>' },
        { key: 'sash',     group: 'Window',        label: 'Sliding Sash', title: 'Sliding Sash Window', category: 'Window',        type: 'SlidingSash',
          icon: '<rect x="5" y="2.5" width="14" height="19" rx="1"/><path d="M5 12.5h14"/><path d="M7.5 5v5M16.5 15v4.5" opacity=".55"/>' },
        { key: 'single',   group: 'Exterior Door', label: 'Single',       title: 'Single Door',         category: 'ExteriorDoors', type: 'Single',
          icon: '<rect x="6" y="2.5" width="12" height="19" rx="1"/><circle cx="15.2" cy="12.5" r=".9"/>' },
        { key: 'double',   group: 'Exterior Door', label: 'Double',       title: 'Double Doors',        category: 'ExteriorDoors', type: 'Double',
          icon: '<rect x="3.5" y="2.5" width="17" height="19" rx="1"/><path d="M12 2.5v19"/><circle cx="10" cy="12.5" r=".8"/><circle cx="14" cy="12.5" r=".8"/>' },
        { key: 'bifold',   group: 'Exterior Door', label: 'Bifold',       title: 'Bifold Doors',        category: 'ExteriorDoors', type: 'MultiFold',
          icon: '<path d="M3 4.5 7.5 6v12L3 19.5zM7.5 6 12 4.5v15L7.5 18zM12 4.5 16.5 6v12L12 19.5zM16.5 6 21 4.5v15L16.5 18z"/>' },
        { key: 'sliding',  group: 'Exterior Door', label: 'Sliding',      title: 'Sliding Doors',       category: 'ExteriorDoors', type: 'Sliding',
          icon: '<rect x="2.5" y="4" width="11" height="16" rx="1"/><rect x="10.5" y="4" width="11" height="16" rx="1"/><path d="M4.5 12h5m-2-2 2 2-2 2"/>' }
    ];

    // HELPER FUNCTION | Which Product the Config Is Set Up For
    // ------------------------------------------------------------
    function na_active_product(cfg) {
        if (cfg.double_door_mode === true)     return 'double';
        if (cfg.ext_single_door_mode === true) return 'single';
        if (cfg.multifold_mode === true)       return 'bifold';
        if (cfg.sliding_mode === true)         return 'sliding';
        if (cfg.sliding_sash_window === true)  return 'sash';
        return 'casement';
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Switch Product Through Na_DynamicUI
    // ------------------------------------------------------------
    function na_select_product(key) {
        const product = NA_PRODUCTS.filter(entry => entry.key === key)[0];
        if (!product || !window.Na_DynamicUI || typeof window.Na_DynamicUI.na_setProduct !== 'function') return;
        window.Na_DynamicUI.na_setProduct(product.category, product.type);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | A Product's Full Name ("Double Doors")
    // ------------------------------------------------------------
    function na_product_name(key) {
        const product = NA_PRODUCTS.filter(entry => entry.key === key)[0];
        return product ? product.title : '';
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Is the Product a Window / a Hinged Door
    // ------------------------------------------------------------
    const na_is_window = product => NA_W.indexOf(product) !== -1;
    const na_is_hinged = product => NA_HD.indexOf(product) !== -1;
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------

    // -----------------------------------------------------------------------------
    // REGION | Item Helpers
    // -----------------------------------------------------------------------------

    // HELPER FUNCTION | One Item per Door Type for a Setting They All Hold
    // ------------------------------------------------------------
    // @param {Array}         products - Door product keys
    // @param {String|Object} suffix   - Key suffix, or { hinged, set } when the
    //                                    sliding / folding sets name it differently
    // @param {Number}        tier
    // @param {Function}      extra    - (product, prefix) -> extra item fields
    function na_door_items(products, suffix, tier, extra) {
        return products.map(product => {
            const prefix   = NA_DOOR_PREFIX[product];
            const ending   = (typeof suffix === 'string') ? suffix : (na_is_hinged(product) ? suffix.hinged : suffix.set);
            const additions = extra ? extra(product, prefix) : {};
            return Object.assign({ id: prefix + '_' + ending, tier: tier, products: [product] }, additions);
        });
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Raise a Count to at Least N (Never Lower It)
    // ------------------------------------------------------------
    function na_at_least(key, count) {
        return cfg => Math.max(Number(cfg[key] || 0), count);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | "Not a Fixed Panel" Requirement for Swing and Hardware
    // ------------------------------------------------------------
    function na_need_not_fixed(prefix) {
        return { text: 'Fixed Panel off', fix: [[prefix + '_fixed_panels', false]] };
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Requirement for Controls of a Leaf With Fielded Panels
    // ------------------------------------------------------------
    function na_need_fielded(prefix) {
        const composition = prefix + '_leaf_composition';
        return {
            text: 'a Leaf Composition with fielded panels',
            fix : [[composition, cfg => (cfg[composition] === 'FullyGlazed' ? 'GlazedOverFielded' : cfg[composition])]]
        };
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Requirement for Glazed-Over-Fielded Only Controls
    // ------------------------------------------------------------
    function na_need_glazed_over_fielded(prefix) {
        return { text: 'Leaf Composition: Glazed Over Fielded', fix: [[prefix + '_leaf_composition', 'GlazedOverFielded']] };
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Requirement for 3D Panel Controls (Profile, Depth, Bevel)
    // ------------------------------------------------------------
    function na_need_three_dimensional(prefix) {
        const fielded = na_need_fielded(prefix);
        return {
            text: 'Panel Output: Three Dimensional',
            fix : fielded.fix.concat([[prefix + '_panel_output_mode', 'ThreeDimensional']])
        };
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Requirement for Custom Panel Grid Controls
    // ------------------------------------------------------------
    function na_need_custom_grid(prefix) {
        const fielded = na_need_fielded(prefix);
        return { text: 'Panel Layout: Custom', fix: fielded.fix.concat([[prefix + '_panel_preset', 'Custom']]) };
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------

    // -----------------------------------------------------------------------------
    // REGION | Summary Helpers
    // -----------------------------------------------------------------------------

    // HELPER FUNCTION | Every Descriptor Array the Tab Builds From
    // ------------------------------------------------------------
    function na_descriptor_arrays() {
        return [
            window.NA_UI_CONFIG, window.NA_GLAZEBAR_CONFIG, window.NA_CILL_FRAME_CONFIG,
            window.NA_OPTIONS_CONFIG, window.NA_WINDOW_BOARD_CONFIG, window.NA_DOOR_PANEL_CONFIG,
            window.NA_SLIDING_DOOR_CONFIG, window.NA_BIFOLD_DOOR_CONFIG, window.NA_DOUBLE_DOOR_CONFIG
        ].filter(Array.isArray);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Find a Descriptor (Expandable Children Included)
    // ------------------------------------------------------------
    function na_find_descriptor(id) {
        let found = null;
        const walk = list => list.forEach(descriptor => {
            if (found || !descriptor) return;
            if (descriptor.id === id) { found = descriptor; return; }
            if (Array.isArray(descriptor.children)) walk(descriptor.children);
        });
        na_descriptor_arrays().forEach(walk);
        return found;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | The Label of an Option Value ("MasterSlaves" -> "Master + Slaves")
    // ------------------------------------------------------------
    function na_option_label(id, value) {
        const descriptor = na_find_descriptor(id);
        const options = descriptor && Array.isArray(descriptor.options) ? descriptor.options : [];
        const match = options.filter(option => String(option.value) === String(value))[0];
        return match ? match.label : String(value == null ? '' : value);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | A Finish Swatch's Name From Its Material Id
    // ------------------------------------------------------------
    function na_swatch_name(id) {
        const pools = [window.NA_FRAME_FINISH_SWATCHES, window.NA_HANDLE_FINISH_SWATCHES].filter(Array.isArray);
        for (let index = 0; index < pools.length; index += 1) {
            const swatch = pools[index].filter(entry => entry && entry.id === id)[0];
            if (swatch) return swatch.label || swatch.name || id;
        }
        return String(id || '').replace(/^MAT\d+__/, '').replace(/__/g, ' ');
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | The Text of the Option a <select> Is Showing
    // ------------------------------------------------------------
    function na_select_text(id) {
        const select = document.getElementById(id + '-select');
        if (!select || select.selectedIndex < 0) return '';
        const option = select.options[select.selectedIndex];
        return option ? option.textContent : '';
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | A Number for Display (Unset Shows as a Dash)
    // ------------------------------------------------------------
    function na_num(value) {
        const number = Number(value);
        return isFinite(number) ? String(Math.round(number * 10) / 10) : '-';
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | The Active Door Type's Leaf Composition
    // ------------------------------------------------------------
    function na_door_composition(cfg, product) {
        const prefix = NA_DOOR_PREFIX[product];
        return prefix ? (cfg[prefix + '_leaf_composition'] || '') : '';
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------

    // -----------------------------------------------------------------------------
    // REGION | Section Summaries
    // -----------------------------------------------------------------------------

    const NA_SUMMARY = {
        size: cfg => na_num(cfg.width_mm) + ' × ' + na_num(cfg.height_mm) + ' mm',

        lights: (cfg, product) => {
            const mullions = Number(cfg.mullions || 0);
            const transoms = Number(cfg.transoms || 0);
            const perLight = Number(cfg.casements_per_opening || 1);
            return (mullions + 1) + ' light' + (mullions ? 's' : '') + ' wide · ' + (transoms + 1) + ' high' +
                   (product === 'casement' && perLight > 1 ? ' · ' + perLight + ' per light' : '');
        },

        opening: (cfg, product) => {
            if (product === 'single') {
                if (cfg.single_door_fixed_panels === true) return 'Fixed panel';
                return na_option_label('single_door_swing_side', cfg.single_door_swing_side) + ' swing · opens ' +
                       String(na_option_label('single_door_swing_direction', cfg.single_door_swing_direction)).toLowerCase();
            }
            if (product === 'double') {
                const width = cfg.double_door_active_leaf_width_mm;
                const split = (width === 'EQ' || width === '' || width == null) ? 'equal leaves' : 'active leaf ' + na_num(width);
                if (cfg.double_door_fixed_panels === true) return 'Fixed pair · ' + split;
                return na_option_label('double_door_active_leaf', cfg.double_door_active_leaf) + ' active · opens ' +
                       String(na_option_label('double_door_swing_direction', cfg.double_door_swing_direction)).toLowerCase() + ' · ' + split;
            }
            if (product === 'bifold') {
                return na_num(cfg.bifold_door_panel_count) + ' panels · ' + na_option_label('bifold_door_layout', cfg.bifold_door_layout);
            }
            return na_option_label('sliding_door_panel_count', cfg.sliding_door_panel_count) + ' · ' +
                   na_option_label('sliding_door_mode', cfg.sliding_door_mode);
        },

        leaves: (cfg, product) => {
            const prefix = NA_DOOR_PREFIX[product];
            const composition = na_door_composition(cfg, product);
            const parts = [na_option_label(prefix + '_leaf_composition', composition)];
            if (composition === 'GlazedOverFielded') parts.push('midrail ' + na_num(cfg[prefix + '_mid_rail_width_mm']));
            if (product === 'double' && cfg.double_door_leaf_settings_linked === false) parts.push('leaves differ');
            return parts.join(' · ');
        },

        glazing: cfg => {
            const horizontal = Number(cfg.horizontal_glaze_bars || 0);
            const vertical   = Number(cfg.vertical_glaze_bars || 0);
            const parts = [(horizontal || vertical) ? horizontal + ' × ' + vertical + ' bars' : 'No bars'];
            if (cfg.glazebar_margin_enabled === true)      parts.push('margins');
            if (cfg.glazebar_gothic_arch_enabled === true) parts.push('gothic arches');
            if (cfg.leaded_glass_enabled === true)         parts.push('leaded');
            return parts.join(' · ');
        },

        panels: (cfg, product) => {
            const prefix = NA_DOOR_PREFIX[product];
            const output = cfg[prefix + '_panel_output_mode'];
            const parts  = [na_option_label(prefix + '_panel_preset', cfg[prefix + '_panel_preset'])];
            parts.push(output === 'Linework' ? 'linework' : String(na_option_label(prefix + '_panel_profile', cfg[prefix + '_panel_profile'])).toLowerCase());
            return parts.join(' · ');
        },

        frame: (cfg, product) => {
            const thickness = Number(cfg.frame_thickness_mm);
            const frame = cfg.advanced_frame_controls === true ? 'Per-side frame'
                        : (thickness === 0 ? 'No frame' : na_num(thickness) + ' frame');
            const parts = [frame, 'set back ' + na_num(cfg.frame_wall_inset_mm),
                           cfg.has_cill === false ? 'no cill' : 'cill ' + na_num(cfg.cill_height_mm)];
            if (na_is_window(product) && cfg.window_board_enabled === true) parts.push('window board');
            return parts.join(' · ');
        },

        sashes: (cfg, product) => {
            if (cfg.show_casements === false) return 'Glass only';
            const size = cfg.casement_sizes_individual === true ? 'Individual sizes' : na_num(cfg.casement_width_mm) + ' rails & stiles';
            if (product === 'sash') {
                const horns = cfg.sash_horns_enabled === false ? 'no horns' : 'horns ' + na_option_label('sash_horn_type', cfg.sash_horn_type);
                return size + ' · ' + horns + (cfg.meeting_rail_position_override === true ? ' · rail moved' : '');
            }
            return size + ' · set back ' + na_num(cfg.casement_inset_mm);
        },

        hardware: (cfg, product) => {
            const prefix = NA_DOOR_PREFIX[product];
            if (cfg[prefix + '_fixed_panels'] === true) return 'No handles on a fixed panel';
            const parts = [na_select_text(prefix + '_handle_asset_key') || 'Handle', na_num(cfg[prefix + '_handle_height_mm']) + ' high'];
            if (product === 'double') parts.push(String(na_option_label('double_door_handle_pairing', cfg.double_door_handle_pairing)).toLowerCase());
            return parts.join(' · ');
        },

        finish: (cfg, product) => {
            const parts = [na_swatch_name(cfg.frame_material_id) + ' frame'];
            if (na_is_hinged(product)) parts.push(na_swatch_name(cfg[NA_DOOR_PREFIX[product] + '_leaf_material_id']) + ' leaf');
            return parts.join(' · ');
        },

        output: (cfg, product) => {
            const parts = [cfg.fuse_parts === true ? 'Fused' : 'Separate parts'];
            if (cfg.show_dimensions === false) parts.push('no preview dimensions');
            if (na_is_hinged(product) && cfg[NA_DOOR_PREFIX[product] + '_show_swing_arcs'] === false) parts.push('no swing arcs');
            return parts.join(' · ');
        }
    };

    // endregion -------------------------------------------------------------------

    // -----------------------------------------------------------------------------
    // REGION | Sections and Items
    // -----------------------------------------------------------------------------

    // Per-leaf override fields of a double door (Leaves > Advanced). Each is
    // drawn for the leaf the picker is editing.
    const NA_LEAF_OVERRIDE_SUFFIXES = [
        'leaf_composition', 'panel_output_mode', 'panel_profile', 'panel_preset', 'panel_columns', 'panel_rows',
        'fielded_section_height_mm', 'mid_rail_width_mm', 'panel_stile_width_mm', 'panel_top_rail_width_mm',
        'panel_bottom_rail_width_mm', 'panel_inset_mm', 'panel_depth_mm', 'panel_bevel_width_mm',
        'horizontal_glaze_bars', 'vertical_glaze_bars', 'glaze_bar_width_mm', 'glazebar_inset_mm'
    ];

    // HELPER FUNCTION | The Double Door's Per-Leaf Override Items
    // ------------------------------------------------------------
    function na_leaf_override_items() {
        const items = [];
        ['left', 'right'].forEach(side => {
            const leafName = side === 'left' ? 'Left' : 'Right';
            const base = 'double_door_' + side + '_';
            items.push({
                id: base + 'leaf_override_enabled', tier: 3, group: 'Per-Leaf Overrides', products: ['double'], side: side,
                need: { text: 'Link Leaf Settings off', fix: [['double_door_leaf_settings_linked', false]] },
                kw: side + ' leaf override per leaf'
            });
            NA_LEAF_OVERRIDE_SUFFIXES.forEach(suffix => items.push({
                id: base + suffix, tier: 3, group: 'Per-Leaf Overrides', products: ['double'], side: side,
                need: { text: leafName + ' Leaf Override on (Link Leaf Settings off)',
                        fix : [['double_door_leaf_settings_linked', false], [base + 'leaf_override_enabled', true]] },
                kw: side + ' leaf override'
            }));
        });
        return items;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Numbered Offset Sliders (Mullions, Glaze Bars)
    // ------------------------------------------------------------
    function na_offset_items(count, idFor, need, extra) {
        const items = [];
        for (let index = 1; index <= count; index += 1) {
            items.push(Object.assign({ id: idFor(index), tier: 3, pool: index > 1 ? index : 0, need: need(index) }, extra));
        }
        return items;
    }
    // ---------------------------------------------------------------

    const NA_NEED_CILL         = { text: 'Include Cill on', fix: [['has_cill', true]] };
    const NA_NEED_WINDOW_BOARD = { text: 'Include Window Board on', fix: [['window_board_enabled', true]] };
    const NA_NEED_LEADED       = { text: 'Leaded Glass on', fix: [['leaded_glass_enabled', true]] };
    const NA_NEED_LEAD_WIDTH   = { text: 'Leaded Glass on, Centre Lines Only off', fix: [['leaded_glass_enabled', true], ['leaded_centre_lines_only', false]] };
    const NA_NEED_GOTHIC       = { text: 'Glaze Bar Gothic Arch Decoration on', fix: [['glazebar_gothic_arch_enabled', true]] };

    const NA_SECTIONS = [
        {
            key: 'size', title: 'Size', summary: NA_SUMMARY.size,
            items: [
                { id: 'width_mm',  kw: 'opening overall span wide size' },
                { id: 'height_mm', kw: 'opening overall tall size' }
            ]
        },
        {
            key: 'lights', title: 'Lights & Dividers', products: NA_W, summary: NA_SUMMARY.lights,
            items: [
                { id: 'mullions', products: NA_W, kw: 'divider vertical lights bay split' },
                { id: 'transoms', products: NA_W, kw: 'divider horizontal fanlight toplight' },
                { id: 'transom_1_y_mm', products: NA_W, kw: 'transom position fanlight height',
                  need: { text: 'at least one transom', fix: [['transoms', na_at_least('transoms', 1)]] } },
                { id: 'transom_2_y_mm', products: NA_W, pool: 2, kw: 'transom position height',
                  need: { text: 'at least two transoms', fix: [['transoms', na_at_least('transoms', 2)]] } },
                { id: 'transom_3_y_mm', products: NA_W, pool: 3, kw: 'transom position height',
                  need: { text: 'three transoms', fix: [['transoms', na_at_least('transoms', 3)]] } },
                { id: 'mullion_width_mm', tier: 2, products: NA_W, kw: 'mullion width',
                  showIf: cfg => Number(cfg.mullions || 0) > 0,
                  need: { text: 'at least one mullion', fix: [['mullions', na_at_least('mullions', 1)]] } },
                { id: 'transom_width_mm', tier: 2, products: NA_W, kw: 'transom width',
                  need: { text: 'at least one transom', fix: [['transoms', na_at_least('transoms', 1)]] } },
                { id: 'casements_per_opening', tier: 2, products: NA_W, kw: 'casements per opening light split' },
                { id: 'mullion_offsets_enabled', tier: 3, products: NA_W, kw: 'individual mullion offsets unequal lights nudge move',
                  showIf: cfg => Number(cfg.mullions || 0) > 0,
                  need: { text: 'at least one mullion', fix: [['mullions', na_at_least('mullions', 1)]] } }
            ].concat(na_offset_items(6, index => 'mullion_offset_' + index + '_mm',
                index => ({ text: 'Individual Mullion Offsets on, with ' + index + '+ mullions',
                            fix : [['mullions', na_at_least('mullions', index)], ['mullion_offsets_enabled', true]] }),
                { products: NA_W, kw: 'mullion offset unequal lights nudge move' }))
        },
        {
            key: 'opening', title: 'Opening', products: NA_D, summary: NA_SUMMARY.opening,
            items: [
                { id: 'single_door_swing_side', products: ['single'], need: na_need_not_fixed('single_door'), kw: 'swing side hinge handing hand left right' },
                { id: 'single_door_swing_direction', products: ['single'], kw: 'swing direction opens inward outward' },
                { id: 'single_door_fixed_panels', products: ['single'], kw: 'fixed panel dead light non opening' },
                { id: 'single_door_opening_angle_deg', tier: 2, products: ['single'], need: na_need_not_fixed('single_door'), kw: 'opening angle swing' },
                { id: 'single_door_hinge_projection_mm', tier: 2, products: ['single'], need: na_need_not_fixed('single_door'), kw: 'hinge projection' },

                { id: 'double_door_active_leaf', products: ['double'], kw: 'active leaf opening leaf master' },
                { id: 'double_door_swing_direction', products: ['double'], kw: 'swing direction opens inward outward' },
                { id: 'double_door_fixed_panels', products: ['double'], kw: 'fixed panels dead lights non opening' },
                { id: 'double_door_active_leaf_width_mm', tier: 2, products: ['double'], kw: 'active leaf width unequal leaves split eq equal' },
                { id: 'double_door_left_opening_angle_deg', tier: 2, products: ['double'], need: na_need_not_fixed('double_door'), kw: 'opening angle swing left' },
                { id: 'double_door_right_opening_angle_deg', tier: 2, products: ['double'], need: na_need_not_fixed('double_door'), kw: 'opening angle swing right' },
                { id: 'double_door_left_hinge_projection_mm', tier: 2, products: ['double'], need: na_need_not_fixed('double_door'), kw: 'hinge projection left' },
                { id: 'double_door_right_hinge_projection_mm', tier: 2, products: ['double'], need: na_need_not_fixed('double_door'), kw: 'hinge projection right' },

                { id: 'bifold_door_panel_count', products: ['bifold'], kw: 'panels leaves count number' },
                { id: 'bifold_door_layout', products: ['bifold'], kw: 'folding pattern layout' },
                { id: 'bifold_door_open_side', products: ['bifold'], kw: 'open side folds to',
                  need: { text: 'Folding Pattern: All Open One Way', fix: [['bifold_door_layout', 'AllOneWay']] } },
                { id: 'bifold_door_master_side', products: ['bifold'], kw: 'master side traffic door',
                  need: { text: 'Folding Pattern: Master + Slaves', fix: [['bifold_door_layout', 'MasterSlaves']] } },

                { id: 'sliding_door_panel_count', products: ['sliding'], kw: 'panels leaves count track' },
                { id: 'sliding_door_mode', products: ['sliding'], kw: 'slide direction left right' },
                { id: 'sliding_door_rear_setback_mm', tier: 2, products: ['sliding'], kw: 'rear panel setback track offset depth' }
            ]
        },
        {
            key: 'leaves', title: 'Leaves', products: NA_D, summary: NA_SUMMARY.leaves,
            items: [].concat(
                na_door_items(NA_D, 'leaf_composition', 1, () => ({ kw: 'leaf composition style glazed fielded solid panel' })),
                na_door_items(NA_D, 'mid_rail_width_mm', 1, (product, prefix) => ({
                    need: na_need_glazed_over_fielded(prefix), kw: 'separating midrail mid rail lock rail' })),
                na_door_items(NA_D, 'fielded_section_height_mm', 1, (product, prefix) => ({
                    need: na_need_glazed_over_fielded(prefix), kw: 'fielded section panel height' })),
                na_door_items(NA_D, { hinged: 'leaf_thickness_mm', set: 'panel_thickness_mm' }, 2, () => ({ kw: 'leaf panel thickness depth' })),
                na_door_items(NA_D, { hinged: 'panel_stile_width_mm', set: 'stile_width_mm' }, 2, () => ({ kw: 'perimeter stile width' })),
                na_door_items(NA_D, { hinged: 'panel_top_rail_width_mm', set: 'head_rail_mm' }, 2, () => ({ kw: 'top rail head rail' })),
                na_door_items(NA_D, { hinged: 'panel_bottom_rail_width_mm', set: 'base_rail_mm' }, 2, () => ({ kw: 'bottom rail base rail kick' })),
                [
                    { id: 'double_door_leaf_settings_linked', tier: 3, group: 'Per-Leaf Overrides', products: ['double'], kw: 'link leaf settings override per leaf' },
                    { id: 'na_leaf_picker', kind: 'picker', tier: 3, group: 'Per-Leaf Overrides', products: ['double'], label: 'Editing', nosearch: true,
                      showIf: cfg => cfg.double_door_leaf_settings_linked === false }
                ],
                na_leaf_override_items()
            )
        },
        {
            key: 'glazing', title: 'Glazing', summary: NA_SUMMARY.glazing,
            offNote: (cfg, product) => (!na_is_window(product) && na_door_composition(cfg, product) === 'FullyFielded')
                ? 'Fully fielded leaves have no glass. Change Leaf Composition under Leaves to glaze them.' : '',
            items: [
                { id: 'horizontal_glaze_bars', kw: 'glaze bars georgian astragal muntin grid horizontal' },
                { id: 'vertical_glaze_bars',   kw: 'glaze bars georgian astragal muntin grid vertical' },
                { id: 'glaze_bar_width_mm', tier: 2, kw: 'glaze bar width' },
                { id: 'glazebar_inset_mm',  tier: 2, kw: 'glaze bar inset depth' },
                { id: 'glass_thickness_mm', tier: 2, kw: 'glazing thickness glass unit dgu double glazing' },
                { id: 'glazebar_margin_enabled', tier: 2, group: 'Decoration', kw: 'margin glazing border bars' },
                { id: 'glazebar_margin_offset_mm', tier: 2, group: 'Decoration', kw: 'margin size offset',
                  need: { text: 'Glaze Bar Margins on', fix: [['glazebar_margin_enabled', true]] } },
                { id: 'glazebar_gothic_arch_enabled', tier: 2, group: 'Decoration', kw: 'gothic arch lancet pointed tracery' },
                { id: 'glazebar_gothic_arch_amount', tier: 2, group: 'Decoration', need: NA_NEED_GOTHIC, kw: 'arches amount' },
                { id: 'glazebar_gothic_arch_height_mm', tier: 2, group: 'Decoration', need: NA_NEED_GOTHIC, kw: 'arch height' },
                { id: 'leaded_glass_enabled', tier: 2, group: 'Decoration', kw: 'lead came leaded lights' },
                { id: 'horizontal_leaded_bars', tier: 2, group: 'Decoration', need: NA_NEED_LEADED, kw: 'lead lines came horizontal' },
                { id: 'vertical_leaded_bars', tier: 2, group: 'Decoration', need: NA_NEED_LEADED, kw: 'lead lines came vertical' },
                { id: 'leaded_width_mm', tier: 2, group: 'Decoration', need: NA_NEED_LEAD_WIDTH, kw: 'lead came width' },
                { id: 'leaded_depth_mm', tier: 2, group: 'Decoration', need: NA_NEED_LEAD_WIDTH, kw: 'lead came depth ribbon' },
                { id: 'leaded_centre_lines_only', tier: 2, group: 'Decoration', need: NA_NEED_LEADED, kw: 'lead centre lines only' },
                { id: 'leaded_global_alignment', tier: 2, group: 'Decoration', products: ['casement'], need: NA_NEED_LEADED, kw: 'lead align across casements' },
                { id: 'glazebar_horizontal_offset_mm', tier: 3, kw: 'horizontal bar vertical offset raise springing shift',
                  need: { text: 'at least one horizontal bar', fix: [['horizontal_glaze_bars', na_at_least('horizontal_glaze_bars', 1)]] } },
                { id: 'glazebar_offsets_enabled', tier: 3, kw: 'glaze bar offsets nudge per bar individual' }
            ].concat(
                na_offset_items(8, index => 'glazebar_h_offset_' + index + '_mm',
                    index => ({ text: 'Glaze Bar Offsets on, with ' + index + '+ horizontal bars',
                                fix : [['horizontal_glaze_bars', na_at_least('horizontal_glaze_bars', index)], ['glazebar_offsets_enabled', true]] }),
                    { kw: 'glaze bar offset nudge horizontal' }),
                na_offset_items(8, index => 'glazebar_v_offset_' + index + '_mm',
                    index => ({ text: 'Glaze Bar Offsets on, with ' + index + '+ vertical bars',
                                fix : [['vertical_glaze_bars', na_at_least('vertical_glaze_bars', index)], ['glazebar_offsets_enabled', true]] }),
                    { kw: 'glaze bar offset nudge vertical' })
            )
        },
        {
            key: 'panels', title: 'Fielded Panels', products: NA_D, summary: NA_SUMMARY.panels,
            offNote: (cfg, product) => na_door_composition(cfg, product) === 'FullyGlazed'
                ? 'Fully glazed leaves have no fielded panels. Change Leaf Composition under Leaves to add some.' : '',
            items: [].concat(
                na_door_items(NA_D, 'panel_preset', 1, (product, prefix) => ({ need: na_need_fielded(prefix), kw: 'panel layout preset fielded' })),
                na_door_items(NA_D, 'panel_profile', 1, (product, prefix) => ({ need: na_need_three_dimensional(prefix), kw: 'raised bevelled recessed shaker profile' })),
                na_door_items(NA_D, 'panel_columns', 1, (product, prefix) => ({ need: na_need_custom_grid(prefix), kw: 'custom panel columns' })),
                na_door_items(NA_D, 'panel_rows', 1, (product, prefix) => ({ need: na_need_custom_grid(prefix), kw: 'custom panel rows' })),
                na_door_items(NA_D, 'panel_output_mode', 2, (product, prefix) => ({ need: na_need_fielded(prefix), kw: 'panel output linework three dimensional 3d' })),
                na_door_items(NA_D, 'panel_inset_mm', 2, (product, prefix) => ({ need: na_need_fielded(prefix), kw: 'panel inset' })),
                na_door_items(NA_D, 'panel_depth_mm', 2, (product, prefix) => ({ need: na_need_three_dimensional(prefix), kw: 'panel depth' })),
                na_door_items(NA_D, 'panel_bevel_width_mm', 2, (product, prefix) => ({ need: na_need_three_dimensional(prefix), kw: 'panel bevel width' }))
            )
        },
        {
            key: 'frame', title: 'Frame & Cill', summary: NA_SUMMARY.frame,
            items: [
                { id: 'frame_thickness_mm', kw: 'frame thickness width face no frame frameless',
                  showIf: cfg => cfg.advanced_frame_controls !== true,
                  need: { text: 'Per-Side Frame Thickness off', fix: [['advanced_frame_controls', false]] } },
                { id: 'frame_wall_inset_mm', kw: 'frame wall inset reveal recess set back position' },
                { id: 'has_cill', kw: 'include cill sill threshold' },
                { id: 'frame_depth_mm', tier: 2, kw: 'frame depth section' },
                { id: 'advanced_frame_controls', tier: 2, kind: 'switchgroup', kw: 'per side frame thickness advanced frame top bottom left right' },
                { id: 'frame_top_thickness_mm', inside: 'advanced_frame_controls', kw: 'top frame thickness',
                  need: { text: 'Per-Side Frame Thickness on', fix: [['advanced_frame_controls', true]] } },
                { id: 'frame_bottom_thickness_mm', inside: 'advanced_frame_controls', kw: 'bottom frame thickness threshold',
                  need: { text: 'Per-Side Frame Thickness on', fix: [['advanced_frame_controls', true]] } },
                { id: 'frame_left_thickness_mm', inside: 'advanced_frame_controls', kw: 'left frame thickness jamb',
                  need: { text: 'Per-Side Frame Thickness on', fix: [['advanced_frame_controls', true]] } },
                { id: 'frame_right_thickness_mm', inside: 'advanced_frame_controls', kw: 'right frame thickness jamb',
                  need: { text: 'Per-Side Frame Thickness on', fix: [['advanced_frame_controls', true]] } },
                { id: 'cill_height_mm', tier: 2, group: 'Cill', showIf: cfg => cfg.has_cill !== false, need: NA_NEED_CILL, kw: 'cill sill height' },
                { id: 'cill_depth_mm', tier: 2, group: 'Cill', showIf: cfg => cfg.has_cill !== false, need: NA_NEED_CILL, kw: 'cill sill protrusion projection stub depth' },
                { id: 'paint_cill', tier: 2, group: 'Cill', showIf: cfg => cfg.has_cill !== false, need: NA_NEED_CILL, kw: 'paint cill sill finish' },
                { id: 'window_board_enabled', tier: 2, group: 'Window Board', products: NA_W, kw: 'include window board internal sill board nosing' },
                { id: 'window_board_reveal_depth_mm', tier: 2, group: 'Window Board', products: NA_W, kw: 'window board reveal depth',
                  showIf: cfg => cfg.window_board_enabled === true, need: NA_NEED_WINDOW_BOARD },
                { id: 'window_board_nosing_overhang_mm', tier: 2, group: 'Window Board', products: NA_W, kw: 'window board nosing overhang',
                  showIf: cfg => cfg.window_board_enabled === true, need: NA_NEED_WINDOW_BOARD },
                { id: 'window_board_nosing_type', tier: 2, group: 'Window Board', products: NA_W, kw: 'window board nosing type bullnose square',
                  showIf: cfg => cfg.window_board_enabled === true, need: NA_NEED_WINDOW_BOARD },
                { id: 'window_board_nosing_returns_enabled', tier: 2, group: 'Window Board', products: NA_W, kw: 'window board nosing projection returns',
                  showIf: cfg => cfg.window_board_enabled === true, need: NA_NEED_WINDOW_BOARD }
            ]
        },
        {
            key: 'sashes', title: product => (product === 'sash' ? 'Sashes' : 'Casements'), products: NA_W, summary: NA_SUMMARY.sashes,
            items: [
                { id: 'casement_width_mm', products: NA_W, kw: 'casement width stile rail sash' },
                { id: 'show_casements', products: NA_W, kw: 'show casements sashes fixed glazing glass only' },
                { id: 'sash_horns_enabled', products: ['sash'], kw: 'show sash horns joggles' },
                { id: 'sash_horn_type', products: ['sash'], kw: 'sash horn type profile',
                  need: { text: 'Show Sash Horns on', fix: [['show_casements', true], ['sash_horns_enabled', true]] } },
                { id: 'meeting_rail_position_override', products: ['sash'], kw: 'custom meeting rail position' },
                { id: 'meeting_rail_offset_mm', products: ['sash'], kw: 'meeting rail offset position',
                  need: { text: 'Custom Meeting Rail Position on', fix: [['show_casements', true], ['meeting_rail_position_override', true]] } },
                { id: 'casement_sizes_individual', tier: 2, kind: 'switchgroup', products: NA_W, kw: 'individual casement sizes per side rails stiles' },
                { id: 'casement_top_rail_mm', inside: 'casement_sizes_individual', kw: 'casement sash top rail',
                  need: { text: 'Individual Casement Sizes on', fix: [['casement_sizes_individual', true]] } },
                { id: 'casement_bottom_rail_mm', inside: 'casement_sizes_individual', kw: 'casement sash bottom rail',
                  need: { text: 'Individual Casement Sizes on', fix: [['casement_sizes_individual', true]] } },
                { id: 'casement_left_stile_mm', inside: 'casement_sizes_individual', kw: 'casement sash left stile',
                  need: { text: 'Individual Casement Sizes on', fix: [['casement_sizes_individual', true]] } },
                { id: 'casement_right_stile_mm', inside: 'casement_sizes_individual', kw: 'casement sash right stile',
                  need: { text: 'Individual Casement Sizes on', fix: [['casement_sizes_individual', true]] } },
                { id: 'casement_depth_mm', tier: 2, products: NA_W, kw: 'casement sash depth thickness' },
                { id: 'casement_inset_mm', tier: 2, products: NA_W, kw: 'casement frame inset set back proud flush' },
                { id: 'sliding_sash_overlap_mm', tier: 2, products: ['sash'], kw: 'sliding sash overlap meeting' },
                { id: 'top_sash_bottom_rail_mm', tier: 2, products: ['sash'], kw: 'top sash bottom rail meeting rail' },
                { id: 'bottom_sash_top_rail_override', tier: 2, products: ['sash'], kw: 'override bottom sash top rail' },
                { id: 'bottom_sash_top_rail_mm', tier: 2, products: ['sash'], kw: 'bottom sash top rail meeting rail',
                  need: { text: 'Override Bottom Sash Top Rail on', fix: [['bottom_sash_top_rail_override', true]] } },
                { id: 'casement_individual_controls', tier: 3, kind: 'flatten', group: 'Per Casement Settings', products: ['casement'],
                  label: 'Per Casement Settings', kw: 'per casement individual override casement settings' }
            ]
        },
        {
            key: 'hardware', title: 'Hardware', products: NA_HD, summary: NA_SUMMARY.hardware,
            emptyNote: () => 'Fixed panels have no handles. Turn Fixed Panel off under Opening to fit one.',
            items: [
                { id: 'single_door_handle_asset_key', products: ['single'], need: na_need_not_fixed('single_door'), kw: 'handle asset ironmongery lever hardware' },
                { id: 'single_door_handle_height_mm', products: ['single'], need: na_need_not_fixed('single_door'), kw: 'handle height' },
                { id: 'single_door_handle_backset_mm', products: ['single'], need: na_need_not_fixed('single_door'), kw: 'handle position backset latch stile' },
                { id: 'single_door_handle_material_id', products: ['single'], need: na_need_not_fixed('single_door'), kw: 'handle finish colour material chrome ironmongery' },
                { id: 'double_door_handle_pairing', products: ['double'], need: na_need_not_fixed('double_door'), kw: 'handles single paired pair' },
                { id: 'double_door_handle_asset_key', products: ['double'], need: na_need_not_fixed('double_door'), kw: 'handle asset ironmongery lever hardware' },
                { id: 'double_door_handle_height_mm', products: ['double'], need: na_need_not_fixed('double_door'), kw: 'handle height' },
                { id: 'double_door_handle_backset_mm', products: ['double'], need: na_need_not_fixed('double_door'), kw: 'handle position backset meeting stile' },
                { id: 'double_door_handle_material_id', products: ['double'], need: na_need_not_fixed('double_door'), kw: 'handle finish colour material chrome ironmongery' }
            ]
        },
        {
            key: 'finish', title: 'Finish', summary: NA_SUMMARY.finish,
            emptyNote: () => 'The finish swatches arrive from the materials library when SketchUp opens the dialog.',
            items: [
                { id: 'frame_material_id', kw: 'frame finish material colour paint timber' },
                { id: 'single_door_leaf_material_id', products: ['single'], kw: 'leaf finish door material colour paint' },
                { id: 'double_door_leaf_material_id', products: ['double'], kw: 'leaf finish door material colour paint' },
                { id: 'edge_colour_frame_id', tier: 3, group: 'Edge Colours', kw: 'edge line colour frame' },
                { id: 'edge_colour_casement_id', tier: 3, group: 'Edge Colours', kw: 'edge line colour casement' },
                { id: 'edge_colour_glazebar_id', tier: 3, group: 'Edge Colours', kw: 'edge line colour glazebar glaze bar' },
                { id: 'edge_colour_leaded_id', tier: 3, group: 'Edge Colours', kw: 'edge line colour lead' },
                { id: 'edge_colour_fielded_panel_id', tier: 3, group: 'Edge Colours', kw: 'edge line colour fielded panel' },
                { id: 'edge_colour_window_board_id', tier: 3, group: 'Edge Colours', kw: 'edge line colour window board' }
            ]
        },
        {
            key: 'output', title: 'Output', summary: NA_SUMMARY.output,
            items: [
                { id: 'fuse_parts', kw: 'fuse parts merge weld solid single group' },
                { id: 'show_dimensions', tier: 2, kw: 'show dimensions 2d preview' },
                { id: 'single_door_show_swing_arcs', tier: 2, products: ['single'], need: na_need_not_fixed('single_door'), kw: 'swing arcs plan 2d' },
                { id: 'single_door_create_open_state_copy', tier: 2, products: ['single'], need: na_need_not_fixed('single_door'), kw: 'open state copy' },
                { id: 'double_door_show_swing_arcs', tier: 2, products: ['double'], need: na_need_not_fixed('double_door'), kw: 'swing arcs plan 2d' },
                { id: 'double_door_create_open_state_copy', tier: 2, products: ['double'], need: na_need_not_fixed('double_door'), kw: 'open state copy' }
            ]
        }
    ];

    // HELPER FUNCTION | Section Order for a Product
    // ------------------------------------------------------------
    function na_order_for(product) {
        return na_is_window(product)
            ? ['size', 'lights', 'glazing', 'frame', 'sashes', 'finish', 'output']
            : ['size', 'opening', 'leaves', 'glazing', 'panels', 'frame', 'hardware', 'finish', 'output'];
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------

    // -----------------------------------------------------------------------------
    // REGION | Defaults (for the Changed Chip and Reset)
    // -----------------------------------------------------------------------------

    // Expandables whose open state is itself a setting. Every other expandable
    // is only a box and has no default worth comparing against.
    const NA_SETTING_EXPANDABLES = ['advanced_frame_controls', 'casement_sizes_individual'];

    // A door type starts at its own opening (na_applyDoorModeDefaultDimensions)
    // and a sliding sash with its own rails (na_applySlidingSashCasementDefaults),
    // so those are the values "unchanged" is measured against.
    const NA_DOOR_DIMENSIONS = { single: [1000, 2100], double: [1800, 2100], bifold: [3000, 2100], sliding: [3000, 2100] };
    const NA_SASH_DEFAULTS = {
        casement_sizes_individual     : true,
        casement_top_rail_mm          : 60,
        casement_bottom_rail_mm       : 70,
        sliding_sash_overlap_mm       : 40,
        top_sash_bottom_rail_mm       : 60,
        bottom_sash_top_rail_override : false,
        bottom_sash_top_rail_mm       : 60,
        meeting_rail_position_override: false,
        meeting_rail_offset_mm        : 0,
        casement_left_stile_mm        : 40,
        casement_right_stile_mm       : 40
    };

    let na_descriptor_defaults = null;

    // HELPER FUNCTION | Descriptor Defaults, Collected Once
    // ------------------------------------------------------------
    function na_collect_defaults() {
        if (na_descriptor_defaults) return na_descriptor_defaults;
        const defaults = {};
        const walk = list => list.forEach(descriptor => {
            if (!descriptor || !descriptor.id) return;
            if (descriptor.type === 'expandable') {
                if (NA_SETTING_EXPANDABLES.indexOf(descriptor.id) !== -1) defaults[descriptor.id] = descriptor.default;
                if (Array.isArray(descriptor.children)) walk(descriptor.children);
                return;
            }
            defaults[descriptor.id] = descriptor.default;
        });
        na_descriptor_arrays().forEach(walk);
        na_descriptor_defaults = defaults;
        return defaults;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | The Default of One Setting for One Product
    // ------------------------------------------------------------
    function na_default_of(id, product) {
        const doorSize = NA_DOOR_DIMENSIONS[product];
        if (doorSize && id === 'width_mm')  return doorSize[0];
        if (doorSize && id === 'height_mm') return doorSize[1];
        if (product === 'sash' && Object.prototype.hasOwnProperty.call(NA_SASH_DEFAULTS, id)) return NA_SASH_DEFAULTS[id];
        return na_collect_defaults()[id];
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------

    // -----------------------------------------------------------------------------
    // REGION | Refresh Hook (Preview Header)
    // -----------------------------------------------------------------------------

    // HELPER FUNCTION | Keep the Preview's Size Badge and Dimensions Button Current
    // ------------------------------------------------------------
    function na_on_refresh(cfg) {
        const badge = document.getElementById('na-preview-size-windows');
        if (badge) badge.textContent = na_num(cfg.width_mm) + ' × ' + na_num(cfg.height_mm);
        const dims = document.getElementById('na-btn-dims-windows');
        if (dims) dims.setAttribute('aria-pressed', cfg.show_dimensions === false ? 'false' : 'true');
    }
    // ---------------------------------------------------------------

    // FUNCTION | Toggle Dimensions From the Preview Header
    // ------------------------------------------------------------
    window.na_toggleWindowPreviewDimensions = function () {
        if (!window.Na_DynamicUI || typeof window.Na_DynamicUI.na_applyControlChange !== 'function') return;
        const cfg = window.Na_DynamicUI.na_getConfig();
        window.Na_DynamicUI.na_applyControlChange('show_dimensions', cfg.show_dimensions === false);
    };
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------

    // -----------------------------------------------------------------------------
    // REGION | Registration
    // -----------------------------------------------------------------------------

    if (!window.Na__Ui__SectionLayout) {
        console.error('[NA_WINDOW_LAYOUT] Na__Ui__SectionLayout not loaded - the Windows tab keeps its build containers');
        return;
    }

    window.Na__Ui__SectionLayout.na_register('windows', {
        panelId          : 'na-tab-windows',
        sectionsHostId   : 'na-lay-sections-windows',
        resultsHostId    : 'na-lay-results-windows',
        stagingId        : 'na-lay-staging-windows',
        productStripId   : 'na-lay-products-windows',
        searchInputId    : 'na-search-windows',
        changedChipId    : 'na-chg-windows',
        previewId        : 'na-preview-windows',
        stickyTopId      : 'na-panel-top-windows',
        scrollerSelector : '.na-main-content',
        fallbackSection  : 'output',
        hiddenIds        : [
            'ui_element_category', 'ui_window_type', 'ui_exterior_door_type',                 // <-- Replaced by the product strip
            'advanced_casement_controls', 'advanced_mullion_controls',                         // <-- Boxes whose contents are laid out one by one
            'advanced_glazebar_controls', 'leaded_glass_controls', 'edge_colour_controls'
        ],
        changedIgnore    : [
            'transom_1_y_mm', 'transom_2_y_mm', 'transom_3_y_mm',                             // <-- Seeded and clamped by the layout itself
            'glazebar_gothic_arch_amount', 'glazebar_gothic_arch_height_mm'                    // <-- Re-seeded from the bars and the glass size
        ],
        products         : NA_PRODUCTS,
        sections         : NA_SECTIONS,
        getConfig        : () => (window.Na_DynamicUI ? window.Na_DynamicUI.na_getConfig() : {}),
        setValue         : (id, value) => { if (window.Na_DynamicUI) window.Na_DynamicUI.na_applyControlChange(id, value); },
        activeProduct    : na_active_product,
        selectProduct    : na_select_product,
        productName      : na_product_name,
        orderFor         : na_order_for,
        defaultOf        : na_default_of,
        onRefresh        : na_on_refresh
    });

    // endregion -------------------------------------------------------------------
})();

/* =============================================================================
   END OF FILE
   ============================================================================= */
