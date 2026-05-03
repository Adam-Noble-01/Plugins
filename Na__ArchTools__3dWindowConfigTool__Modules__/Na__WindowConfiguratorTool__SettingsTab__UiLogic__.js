// =============================================================================
// NA WINDOW CONFIGURATOR TOOL - SETTINGS TAB UI LOGIC
// =============================================================================
//
// FILE       : Na__WindowConfiguratorTool__SettingsTab__UiLogic__.js
// NAMESPACE  : Na_SettingsUI (browser global)
// AUTHOR     : Noble Architecture
// PURPOSE    : Owns the Settings tab page-swap UI. Builds the action buttons
//              (Reload Scripts, Export 2D Data, Export 3D Data) and the
//              accompanying info panel inside #na-tab-settings.
// CREATED    : 01-May-2026
//
// DESCRIPTION:
// - Exposes Na_SettingsUI with the lifecycle hooks the existing TabRouter
//   expects:
//     * Na_SettingsUI.na_mount(initialConfig)  -> Build / refresh the panel.
//     * Na_SettingsUI.na_unmount()             -> Tear the panel back down.
//     * Na_SettingsUI.na_render(config)        -> Re-render in place.
//     * Na_SettingsUI.na_get_active_config()   -> Returns null (settings is
//                                                stateless on the JS side).
// - All button click handlers delegate to the
//   Na__WindowConfiguratorTool__SettingsTab__UiEventToRubyApiBridge__.js
//   bridge module, which in turn invokes Ruby action callbacks.
//
// NAMING CONVENTION:
// - All public symbols use Na_ / na_ prefix.
//
// =============================================================================


(function () {
    'use strict';


// -----------------------------------------------------------------------------
// REGION | Na_SettingsUI Module Definition
// -----------------------------------------------------------------------------

    // MODULE VARIABLES | Settings UI State
    // ------------------------------------------------------------
    var Na_SettingsUI            = {};                                        // <-- Public namespace
    var NA_PANEL_CONTAINER_ID    = 'na-tab-settings';                         // <-- Outer tab panel id
    var NA_BODY_CONTAINER_ID     = 'na-settings-body';                        // <-- Dynamic body container id
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Section Descriptors (Declarative)
// -----------------------------------------------------------------------------

    // MODULE CONSTANTS | Button Section Descriptors
    // ------------------------------------------------------------
    // Each section is rendered as <div class="na-settings-section">; each
    // entry inside is rendered as a stacked button + helper text pair.
    var NA_SETTINGS_SECTIONS = [
        {
            heading: 'Plugin Maintenance',
            description: 'Developer-facing actions. Reload re-requires every Ruby file under the plugin folder so changes take effect without restarting SketchUp.',
            buttons: [
                {
                    id      : 'na-btn-settings-reload',
                    label   : 'Reload Scripts',
                    helper  : 'Re-loads all Ruby scripts under the plugin folder. Closes the dialog so it can be reopened with fresh code.',
                    onclick : 'na_settingsReloadScripts'
                }
            ]
        },
        {
            heading: 'Asset JSON Exporters',
            description: 'Export the currently selected SketchUp geometry to a structured JSON asset file. The selection requirements are listed beneath each button.',
            buttons: [
                {
                    id      : 'na-btn-settings-export-2d',
                    label   : 'Export 2D Data',
                    helper  : 'Selection: loose 2D edges and faces in the XY plane plus a group named "00__OriginPoint". Produces a ValeSpec hardware-item JSON (HardwareItem__VectorData).',
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
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | DOM Builders
// -----------------------------------------------------------------------------

    // HELPER FUNCTION | Resolve the Outer Tab Panel Container
    // ------------------------------------------------------------
    function na_get_panel_container() {
        return document.getElementById(NA_PANEL_CONTAINER_ID);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Resolve or Create the Inner Body Container
    // ------------------------------------------------------------
    // The outer panel may contain a header (rendered statically by the
    // HTML template). The inner body container is what we rebuild on each
    // mount so the header survives unmount/remount cycles.
    function na_get_or_create_body_container() {
        var existing = document.getElementById(NA_BODY_CONTAINER_ID);
        if (existing) return existing;

        var panel = na_get_panel_container();
        if (!panel) return null;

        var body = document.createElement('div');
        body.id        = NA_BODY_CONTAINER_ID;
        body.className = 'na-settings-body';
        panel.appendChild(body);
        return body;
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Build a Single Button + Helper-Text Block
    // ------------------------------------------------------------
    function na_build_button_block(buttonDescriptor) {
        var wrapper = document.createElement('div');
        wrapper.className = 'na-settings-button-row';

        var button = document.createElement('button');
        button.id        = buttonDescriptor.id;
        button.type      = 'button';
        button.className = 'na-btn na-btn-primary na-settings-btn';
        button.textContent = buttonDescriptor.label;
        button.setAttribute('onclick', buttonDescriptor.onclick + '()');

        var helper = document.createElement('p');
        helper.className   = 'na-settings-helper';
        helper.textContent = buttonDescriptor.helper;

        wrapper.appendChild(button);
        wrapper.appendChild(helper);
        return wrapper;
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Build a Single Settings Section (Heading + Buttons)
    // ------------------------------------------------------------
    function na_build_section(sectionDescriptor) {
        var section = document.createElement('section');
        section.className = 'na-settings-section';

        var heading = document.createElement('h3');
        heading.className   = 'na-settings-heading';
        heading.textContent = sectionDescriptor.heading;
        section.appendChild(heading);

        if (sectionDescriptor.description) {
            var desc = document.createElement('p');
            desc.className   = 'na-settings-description';
            desc.textContent = sectionDescriptor.description;
            section.appendChild(desc);
        }

        for (var i = 0; i < sectionDescriptor.buttons.length; i++) {
            section.appendChild(na_build_button_block(sectionDescriptor.buttons[i]));
        }

        return section;
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Build the About / Info Block
    // ------------------------------------------------------------
    function na_build_info_block() {
        var section = document.createElement('section');
        section.className = 'na-settings-section na-settings-section-info';

        var heading = document.createElement('h3');
        heading.className   = 'na-settings-heading';
        heading.textContent = 'About';
        section.appendChild(heading);

        var lines = [
            'Na Architectural Configurator',
            'Tabs: Windows, Interior Doors, Settings.',
            'JSON exporters live in 65__DevTools/ so any future tool can reuse them.'
        ];

        for (var i = 0; i < lines.length; i++) {
            var p = document.createElement('p');
            p.className   = 'na-settings-info-line';
            p.textContent = lines[i];
            section.appendChild(p);
        }
        return section;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Render the Full Settings Body Into the Body Container
    // ------------------------------------------------------------
    function na_render_body() {
        var body = na_get_or_create_body_container();
        if (!body) return;

        body.innerHTML = '';

        for (var i = 0; i < NA_SETTINGS_SECTIONS.length; i++) {
            body.appendChild(na_build_section(NA_SETTINGS_SECTIONS[i]));
        }

        body.appendChild(na_build_info_block());
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Public API (TabRouter Lifecycle Hooks)
// -----------------------------------------------------------------------------

    // FUNCTION | Lifecycle - Mount the Settings Tab
    // ------------------------------------------------------------
    Na_SettingsUI.na_mount = function (initialConfig) {
        na_render_body();
    };
    // ---------------------------------------------------------------

    // FUNCTION | Lifecycle - Unmount the Settings Tab
    // ------------------------------------------------------------
    // Empties the body container so the next mount starts from a known
    // state. The outer panel + heading remain (they are owned by the HTML).
    Na_SettingsUI.na_unmount = function () {
        var body = document.getElementById(NA_BODY_CONTAINER_ID);
        if (body) body.innerHTML = '';
    };
    // ---------------------------------------------------------------

    // FUNCTION | Re-Render in Place (Forwarded by TabRouter as a Fallback)
    // ------------------------------------------------------------
    Na_SettingsUI.na_render = function (config) {
        na_render_body();
    };
    // ---------------------------------------------------------------

    // FUNCTION | Active Config Snapshot
    // ------------------------------------------------------------
    // The Settings tab is stateless on the JS side, so we return null.
    // The TabRouter handles a null gracefully (treated as "no config").
    Na_SettingsUI.na_get_active_config = function () {
        return null;
    };
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Bootstrap
// -----------------------------------------------------------------------------

    window.Na_SettingsUI = Na_SettingsUI;                                     // <-- Expose globally for TabRouter

// endregion -------------------------------------------------------------------

})();

// =============================================================================
// END OF FILE
// =============================================================================
