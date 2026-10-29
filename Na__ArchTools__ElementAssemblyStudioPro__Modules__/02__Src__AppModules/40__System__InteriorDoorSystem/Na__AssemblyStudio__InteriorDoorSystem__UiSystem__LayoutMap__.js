// =============================================================================
// ELEMENT ASSEMBLY STUDIO PRO - INTERIOR DOOR SYSTEM - SECTION LAYOUT MAP
// =============================================================================
//
// FILE       : Na__AssemblyStudio__InteriorDoorSystem__UiSystem__LayoutMap__.js
// AUTHOR     : Noble Architecture
// PURPOSE    : Where every control of the Interior Doors tab lives: section,
//              tier (1 shown, 2 More, 3 Advanced) and door type. Registered
//              with Na__Ui__SectionLayout, which moves the controls Na_DoorUI
//              builds on every mount into these slots.
// CREATED    : 28-Oct-2026
//
// THE ORDER, AND WHY
// - Door type first (Single / Double chips above the preview), then the
//   opening it fills, the leaf and its swing, the panel design, the
//   architrave, the hardware, the finish, and last what gets built.
// - The structural opening and the door leaf size sit side by side in Tier 1:
//   the measure tool fills the opening, the leaf sliders dial in a standard
//   leaf (762 x 1981) and drive the opening back.
// - The Joinery Finish and Handle Finish swatch rows (Na_FrameFinishCards)
//   are static blocks placed into Finish and Hardware.
//
// NAMING CONVENTION:
// - All identifiers use Na_ / na_ prefix.
//
// =============================================================================

(function () {
    'use strict';

// -----------------------------------------------------------------------------
// REGION | Door Types
// -----------------------------------------------------------------------------

    var NA_DOOR_TYPE_KEY = 'Na__DoorConfig__DoorType';

    var NA_PRODUCTS = [
        { key: 'single', group: 'Interior Door', label: 'Single Door',  title: 'Single Interior Door',
          icon: '<rect x="6" y="2.5" width="12" height="19" rx="1"/><circle cx="15.2" cy="12.5" r=".9"/>' },
        { key: 'double', group: 'Interior Door', label: 'Double Doors', title: 'Double Interior Doors',
          icon: '<rect x="3.5" y="2.5" width="17" height="19" rx="1"/><path d="M12 2.5v19"/><circle cx="10" cy="12.5" r=".8"/><circle cx="14" cy="12.5" r=".8"/>' }
    ];

    // HELPER FUNCTION | Which Door Type the Config Is Set Up For
    // ------------------------------------------------------------
    function na_active_product(cfg) {
        return String(cfg[NA_DOOR_TYPE_KEY] || 'Single').toLowerCase() === 'double' ? 'double' : 'single';
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Switch Door Type Through Na_DoorUI
    // ------------------------------------------------------------
    function na_select_product(key) {
        if (!window.Na_DoorUI || typeof window.Na_DoorUI.na_apply_control_value !== 'function') return;
        window.Na_DoorUI.na_apply_control_value(NA_DOOR_TYPE_KEY, key === 'double' ? 'Double' : 'Single');
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | A Door Type's Full Name
    // ------------------------------------------------------------
    function na_product_name(key) {
        var product = NA_PRODUCTS.filter(function (entry) { return entry.key === key; })[0];
        return product ? product.title : '';
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
            window.NA_DOOR_OPENING_CONFIG, window.NA_DOOR_PANEL_TAB_CONFIG, window.NA_DOOR_ARCHITRAVE_CONFIG,
            window.NA_DOOR_HANDLE_CONFIG, window.NA_DOOR_OPTIONS_CONFIG
        ].filter(Array.isArray);
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

    // HELPER FUNCTION | The Text of the Option a <select> Is Showing
    // ------------------------------------------------------------
    function na_select_text(id) {
        var select = document.getElementById(id + '-select');
        if (!select || select.selectedIndex < 0) return '';
        var option = select.options[select.selectedIndex];
        return option ? option.textContent : '';
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | The Chosen Swatch in a Finish Card Row
    // ------------------------------------------------------------
    function na_picked_card(containerId) {
        var container = document.getElementById(containerId);
        var chosen = container ? container.querySelector('.na-material-card-selected') : null;
        return chosen ? (chosen.getAttribute('title') || '') : '';
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | A Number for Display (Unset Shows as a Dash)
    // ------------------------------------------------------------
    function na_num(value) {
        var number = Number(value);
        return isFinite(number) ? String(Math.round(number)) : '-';
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Sections and Items
// -----------------------------------------------------------------------------

    var NA_NEED_DESIGN     = { text: 'Show Panel Design on', fix: [['Na__DoorConfig__PanelDesignEnabled', true]] };
    var NA_NEED_ARCHITRAVE = { text: 'Show Architrave on',   fix: [['Na__DoorConfig__ArchitraveEnabled', true]] };

    var NA_SECTIONS = [
        {
            key: 'opening', title: 'Opening & Wall',
            summary: function (cfg) {
                return na_num(cfg.Na__DoorConfig__OpeningWidth_mm) + ' × ' + na_num(cfg.Na__DoorConfig__OpeningHeight_mm) +
                       ' opening · leaf ' + na_num(cfg.Na__DoorConfig__LeafWidth_mm) + ' × ' + na_num(cfg.Na__DoorConfig__LeafHeight_mm) +
                       ' · wall ' + na_num(cfg.Na__DoorConfig__WallDepth_mm);
            },
            items: [
                { id: 'Na__DoorConfig__OpeningWidth_mm',    kw: 'structural opening width size' },
                { id: 'Na__DoorConfig__OpeningHeight_mm',   kw: 'structural opening height size' },
                { id: 'Na__DoorConfig__LeafWidth_mm',       kw: 'door leaf width standard size' },
                { id: 'Na__DoorConfig__LeafHeight_mm',      kw: 'door leaf height standard size' },
                { id: 'Na__DoorConfig__WallDepth_mm',       kw: 'wall depth thickness lining width reveal' },
                { id: 'Na__DoorConfig__LiningThickness_mm', tier: 2, kw: 'lining thickness jamb frame' }
            ]
        },
        {
            key: 'leaf', title: 'Leaf & Swing',
            summary: function (cfg, product) {
                var direction = String(na_option_label('Na__DoorConfig__SwingDirection', cfg.Na__DoorConfig__SwingDirection)).toLowerCase();
                if (product === 'double') return 'Pair · opens ' + direction;
                return na_option_label('Na__DoorConfig__SwingSide', cfg.Na__DoorConfig__SwingSide) + ' · opens ' + direction;
            },
            items: [
                { id: 'Na__DoorConfig__SwingSide',          kw: 'swing side hand handing hinge left right' },
                { id: 'Na__DoorConfig__SwingDirection',     kw: 'swing direction opens inward outward' },
                { id: 'Na__DoorConfig__PanelThickness_mm',  tier: 2, kw: 'door leaf panel thickness' }
            ]
        },
        {
            key: 'design', title: 'Panel Design',
            summary: function (cfg) {
                if (cfg.Na__DoorConfig__PanelDesignEnabled === false) return 'Plain leaf';
                return na_option_label('Na__DoorConfig__PanelDesignStyle', cfg.Na__DoorConfig__PanelDesignStyle);
            },
            items: [
                { id: 'Na__DoorConfig__PanelDesignEnabled', kw: 'show panel design linework mouldings' },
                { id: 'Na__DoorConfig__PanelDesignStyle',   need: NA_NEED_DESIGN, kw: 'panel design style six panel four panel shaker' },
                { id: 'Na__DoorConfig__PanelDesignStileWidth_mm',          tier: 2, need: NA_NEED_DESIGN, kw: 'stile width sides' },
                { id: 'Na__DoorConfig__PanelDesignTopRail_mm',             tier: 2, need: NA_NEED_DESIGN, kw: 'top rail height' },
                { id: 'Na__DoorConfig__PanelDesignBottomRail_mm',          tier: 2, need: NA_NEED_DESIGN, kw: 'bottom rail height kick' },
                { id: 'Na__DoorConfig__PanelDesignInnerRailThickness_mm',  tier: 2, need: NA_NEED_DESIGN, kw: 'inner rail mullion thickness' },
                { id: 'Na__DoorConfig__PanelDesignVerticalPaneWidth_mm',   tier: 2, kw: 'vertical pane width narrow panels',
                  need: { text: 'Panel Design Style: Vertical Narrow Panels',
                          fix : [['Na__DoorConfig__PanelDesignEnabled', true], ['Na__DoorConfig__PanelDesignStyle', 'VerticalNarrow']] } }
            ]
        },
        {
            key: 'architrave', title: 'Architrave',
            summary: function (cfg) {
                if (cfg.Na__DoorConfig__ArchitraveEnabled === false) return 'No architrave';
                return (na_select_text('Na__DoorConfig__ArchitraveProfileKey') || 'Default profile') +
                       ' · offset ' + na_num(cfg.Na__DoorConfig__ArchitraveOffset_mm);
            },
            items: [
                { id: 'Na__DoorConfig__ArchitraveEnabled',    kw: 'show architrave trim casing' },
                { id: 'Na__DoorConfig__ArchitraveProfileKey', kw: 'architrave profile moulding',
                  showIf: function (cfg) { return cfg.Na__DoorConfig__ArchitraveEnabled !== false; }, need: NA_NEED_ARCHITRAVE },
                { id: 'Na__DoorConfig__ArchitraveOffset_mm',  tier: 2, kw: 'architrave offset reveal margin',
                  showIf: function (cfg) { return cfg.Na__DoorConfig__ArchitraveEnabled !== false; }, need: NA_NEED_ARCHITRAVE }
            ]
        },
        {
            key: 'hardware', title: 'Hardware',
            summary: function (cfg) {
                return (na_select_text('Na__DoorConfig__HandleAssetKey') || 'Handle') + ' · ' +
                       na_num(cfg.Na__DoorConfig__HandleHeight_mm) + ' from floor' +
                       (na_picked_card('na-door-handle-finish-cards') ? ' · ' + na_picked_card('na-door-handle-finish-cards') : '');
            },
            items: [
                { id: 'Na__DoorConfig__HandleAssetKey',   kw: 'handle asset ironmongery lever hardware' },
                { id: 'Na__DoorConfig__HandleHeight_mm',  kw: 'handle height from floor' },
                { id: 'na-door-handle-finish-section',    kind: 'block', label: 'Handle Finish', kw: 'handle finish colour material chrome ironmongery' }
            ]
        },
        {
            key: 'finish', title: 'Finish',
            summary: function () {
                return na_picked_card('na-door-joinery-finish-cards') || 'Joinery finish';
            },
            emptyNote: function () {
                return 'The finish swatches arrive from the materials library when SketchUp opens the dialog.';
            },
            items: [
                { id: 'na-door-joinery-finish-section', kind: 'block', label: 'Joinery Finish', kw: 'joinery finish lining panel architrave material colour paint' }
            ]
        },
        {
            key: 'output', title: 'Output',
            summary: function (cfg) {
                var parts = [cfg.Na__DoorConfig__FuseLining === false ? 'Separate lining parts' : 'Fused lining'];
                if (cfg.Na__DoorConfig__ShowSwingArc === false) parts.push('no swing arc');
                if (cfg.Na__DoorConfig__CreateOpenStateCopy === false) parts.push('no open copy');
                return parts.join(' · ');
            },
            items: [
                { id: 'Na__DoorConfig__FuseLining',          kw: 'fuse lining outer shell merge solid' },
                { id: 'Na__DoorConfig__ShowSwingArc',        kw: 'show 2d swing arc plan' },
                { id: 'Na__DoorConfig__CreateOpenStateCopy', kw: 'create open state copy' }
            ]
        }
    ];

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Defaults (for the Changed Chip and Reset)
// -----------------------------------------------------------------------------

    var na_defaults = null;

    // HELPER FUNCTION | The Default of One Setting
    // ------------------------------------------------------------
    function na_default_of(id) {
        if (!na_defaults) {
            na_defaults = {};
            na_descriptor_arrays().forEach(function (list) {
                list.forEach(function (descriptor) {
                    if (descriptor && descriptor.id) na_defaults[descriptor.id] = descriptor.default;
                });
            });
        }
        return na_defaults[id];
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Registration
// -----------------------------------------------------------------------------

    if (!window.Na__Ui__SectionLayout) {
        console.error('[NA_DOOR_LAYOUT] Na__Ui__SectionLayout not loaded - the Interior Doors tab keeps its build containers');
        return;
    }

    window.Na__Ui__SectionLayout.na_register('doors', {
        panelId          : 'na-tab-doors',
        sectionsHostId   : 'na-lay-sections-doors',
        resultsHostId    : 'na-lay-results-doors',
        stagingId        : 'na-lay-staging-doors',
        productStripId   : 'na-lay-products-doors',
        searchInputId    : 'na-search-doors',
        changedChipId    : 'na-chg-doors',
        previewId        : 'na-preview-doors',
        stickyTopId      : 'na-panel-top-doors',
        scrollerSelector : '.na-main-content',
        fallbackSection  : 'output',
        hiddenIds        : [NA_DOOR_TYPE_KEY],                                   // <-- Replaced by the door type chips
        changedIgnore    : ['Na__DoorConfig__LeafWidth_mm', 'Na__DoorConfig__LeafHeight_mm'],   // <-- Derived from the opening
        products         : NA_PRODUCTS,
        sections         : NA_SECTIONS,
        getConfig        : function () {
            return (window.Na_DoorUI && typeof window.Na_DoorUI.na_get_ui_config === 'function') ? window.Na_DoorUI.na_get_ui_config() : {};
        },
        setValue         : function (id, value) {
            if (window.Na_DoorUI && typeof window.Na_DoorUI.na_apply_control_value === 'function') window.Na_DoorUI.na_apply_control_value(id, value);
        },
        activeProduct    : na_active_product,
        selectProduct    : na_select_product,
        productName      : na_product_name,
        defaultOf        : na_default_of,
        onRefresh        : function (cfg) {
            var badge = document.getElementById('na-preview-size-doors');
            if (badge) badge.textContent = na_num(cfg.Na__DoorConfig__OpeningWidth_mm) + ' × ' + na_num(cfg.Na__DoorConfig__OpeningHeight_mm);
        }
    });

// endregion -------------------------------------------------------------------

})();

// =============================================================================
// END OF FILE
// =============================================================================
