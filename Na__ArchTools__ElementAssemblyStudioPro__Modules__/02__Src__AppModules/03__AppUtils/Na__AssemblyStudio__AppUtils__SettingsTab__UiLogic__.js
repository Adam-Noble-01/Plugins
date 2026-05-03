// =============================================================================
// ELEMENT ASSEMBLY STUDIO PRO - SETTINGS TAB UI LOGIC
// =============================================================================
//
// FILE       : Na__AssemblyStudio__AppUtils__SettingsTab__UiLogic__.js
// NAMESPACE  : window.Na_SettingsUI
// AUTHOR     : Noble Architecture
// PURPOSE    : Owns markup for the HtmlDialog Settings tab: maintenance actions,
//              exporter buttons, helper copy, and static About footer.
//
// DESCRIPTION:
// - Mount injects `#na-settings-body` under `#na-tab-settings`; unmount clears.
// - Button onclick strings match exports from SettingsTab Bridge.
//
// NAMING CONVENTION:
// - Aggregate Na_SettingsUI + na_* internal helpers aligned with Noble prefix.
//
// =============================================================================


(function () {
    'use strict';


// -----------------------------------------------------------------------------
// REGION | Module State & Descriptor Tables
// -----------------------------------------------------------------------------

    var Na_SettingsUI         = {};
    var NA_PANEL_CONTAINER_ID = 'na-tab-settings';                              // <-- host tab pane
    var NA_BODY_CONTAINER_ID  = 'na-settings-body';                           // <-- mutable body subtree

    var NA_SETTINGS_SECTIONS = [
        {
            heading    : 'Plugin Maintenance',
            description: 'Developer-facing actions. Reload re-requires every Ruby file under the plugin folder so changes take effect without restarting SketchUp.',
            buttons    : [
                {
                    id      : 'na-btn-settings-reload',
                    label   : 'Reload Scripts',
                    helper  : 'Re-loads all Ruby scripts under the plugin folder. Reopens the dialog with fresh code.',
                    onclick : 'na_settingsReloadScripts'
                }
            ]
        },
        {
            heading    : 'Asset JSON Exporters',
            description: 'Export the currently selected SketchUp geometry to a structured JSON asset file. Selection requirements are listed beneath each button.',
            buttons    : [
                {
                    id      : 'na-btn-settings-export-2d',
                    label   : 'Export 2D Data',
                    helper  : 'Selection: loose 2D edges and faces in the XY plane plus a group named "00__OriginPoint". Produces a ValeSpec hardware-item JSON.',
                    onclick : 'na_settingsExport2D'
                },
                {
                    id      : 'na-btn-settings-export-3d',
                    label   : 'Export 3D Data',
                    helper  : 'Selection: a "00__OriginPoint" group plus optional "01__PlanView", "02__ElevationView", "03__Model3D", "04__Profile2D" groups. Produces a unified Na__Asset__* JSON.',
                    onclick : 'na_settingsExport3D'
                }
            ]
        }
    ];

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | DOM — Panel & Body Container
// -----------------------------------------------------------------------------

    // FUNCTION | Return the HtmlDialog `#na-tab-settings` root
    // ------------------------------------------------------------
    function na_get_panel_container() {
        return document.getElementById(NA_PANEL_CONTAINER_ID);
    }
    // ---------------------------------------------------------------

    // FUNCTION | Locate or lazily instantiate the scrolling body subtree
    // ------------------------------------------------------------
    function na_get_or_create_body_container() {
        var existing = document.getElementById(NA_BODY_CONTAINER_ID);
        if (existing) return existing;
        var panel = na_get_panel_container();
        if (!panel) return null;
        var body = document.createElement('div');
        body.id          = NA_BODY_CONTAINER_ID;
        body.className   = 'na-settings-body';
        panel.appendChild(body);
        return body;
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Section Builders
// -----------------------------------------------------------------------------

    // FUNCTION | Materialise one labelled button plus helper caption
    // ------------------------------------------------------------
    function na_build_button_block(descriptor) {
        var wrapper = document.createElement('div');
        wrapper.className = 'na-settings-button-row';

        var button = document.createElement('button');
        button.id                   = descriptor.id;
        button.type                 = 'button';
        button.className            = 'na-btn na-btn-primary na-settings-btn';
        button.textContent          = descriptor.label;
        button.setAttribute('onclick', descriptor.onclick + '()');

        var helper = document.createElement('p');
        helper.className   = 'na-settings-helper';
        helper.textContent = descriptor.helper;

        wrapper.appendChild(button);
        wrapper.appendChild(helper);
        return wrapper;
    }
    // ---------------------------------------------------------------

    // FUNCTION | One settings card describing a group of exporters/actions
    // ------------------------------------------------------------
    function na_build_section(descriptor) {
        var section = document.createElement('section');
        section.className = 'na-settings-section';

        var heading = document.createElement('h3');
        heading.className   = 'na-settings-heading';
        heading.textContent = descriptor.heading;
        section.appendChild(heading);

        if (descriptor.description) {
            var desc = document.createElement('p');
            desc.className   = 'na-settings-description';
            desc.textContent = descriptor.description;
            section.appendChild(desc);
        }

        descriptor.buttons.forEach(function (b) { section.appendChild(na_build_button_block(b)); });
        return section;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Static About copy block at the Settings tab footer
    // ------------------------------------------------------------
    function na_build_info_block() {
        var section = document.createElement('section');
        section.className = 'na-settings-section na-settings-section-info';

        var heading = document.createElement('h3');
        heading.className   = 'na-settings-heading';
        heading.textContent = 'About';
        section.appendChild(heading);

        var lines = [
            'Element Assembly Studio Pro by Noble Architecture',
            'Tabs: Windows, Interior Doors, Settings.',
            'JSON exporters live in 65__Dev__DevTools/ so any future system can reuse them.'
        ];
        lines.forEach(function (line) {
            var p       = document.createElement('p');
            p.className = 'na-settings-info-line';
            p.textContent = line;
            section.appendChild(p);
        });
        return section;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Recompose the entire mutable body subtree
    // ------------------------------------------------------------
    function na_render_body() {
        var body = na_get_or_create_body_container();
        if (!body) return;
        body.innerHTML = '';
        NA_SETTINGS_SECTIONS.forEach(function (s) { body.appendChild(na_build_section(s)); });
        body.appendChild(na_build_info_block());
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Public API — Mount Contract (shared HtmlDialog orchestrator)
// -----------------------------------------------------------------------------

    // FUNCTION | First paint / reopen hook (config unused today)
    // ------------------------------------------------------------
    Na_SettingsUI.na_mount = function (_initialConfig) {
        na_render_body();
    };
    // ---------------------------------------------------------------

    // FUNCTION | Tab tear-down clears generated nodes only
    // ------------------------------------------------------------
    Na_SettingsUI.na_unmount = function () {
        var body = document.getElementById(NA_BODY_CONTAINER_ID);
        if (body) body.innerHTML = '';
    };
    // ---------------------------------------------------------------

    // FUNCTION | Tab-visible refresh ping (delegates na_render_body)
    // ------------------------------------------------------------
    Na_SettingsUI.na_render = function (_config) {
        na_render_body();
    };
    // ---------------------------------------------------------------

    // FUNCTION | Settings tab emits no persisted config payload yet
    // ------------------------------------------------------------
    Na_SettingsUI.na_get_active_config = function () {
        return null;
    };
    // ---------------------------------------------------------------

    window.Na_SettingsUI = Na_SettingsUI;

    console.log('[NA_SETTINGS_UI] Settings tab UiLogic mounted contract ready');

// endregion -------------------------------------------------------------------

})();
