// =============================================================================
// NA MESH TOOLS - BATCHED QUADRIC DECIMATOR - SETTINGS TAB UI LOGIC
// =============================================================================
//
// FILE       : Na__MeshDecimator__Settings__UiLogic__.js
// NAMESPACE  : window.Na_SettingsUI
// AUTHOR     : Adam Noble / Noble Architecture
// PURPOSE    : Owns the markup for the Settings tab.  Mirrors the
//              Na__AssemblyStudio__AppUtils__SettingsTab__UiLogic__.js pattern.
//
//              Mount injects into #na-settings-body; unmount clears it.
//              Button onclick strings match exports from the Settings Bridge.
//
// =============================================================================

(function () {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Module State & Descriptor Tables
    // -------------------------------------------------------------------------

    var Na_SettingsUI        = {};
    var NA_BODY_CONTAINER_ID = 'na-settings-body';

    var NA_SETTINGS_SECTIONS = [
        {
            heading:     'Plugin Maintenance',
            description: 'Developer-facing actions. Reload re-requires every Ruby file under the plugin folder so code changes take effect without restarting SketchUp.',
            buttons: [
                {
                    id:      'na-btn-settings-reload',
                    label:   'Reload Scripts',
                    helper:  'Re-loads all .rb files under 02__Src__AppModules. Closes and reopens the dialog with the fresh code.',
                    onclick: 'na_settingsReloadScripts'
                }
            ]
        }
    ];

    var NA_ABOUT = {
        version: 'v0.0.4',
        author:  'Adam Noble / Noble Architecture',
        lines: [
            'Batched Quadric Decimator reduces the polygon count of selected SketchUp groups using the Quadric Error Metric (QEM) algorithm.',
            'Select one or more groups in SketchUp, set your options in the Decimation tab, and click Run Decimation.',
            'Results are written directly into the original groups as a new simplified mesh inside a single undoable operation.',
            'Source: 02__Src__AppModules/ — 9 Ruby modules + 4 JS modules + 1 CSS + 1 HTML.'
        ]
    };

    // -------------------------------------------------------------------------
    // REGION | DOM Helpers
    // -------------------------------------------------------------------------

    function na_get_or_create_body() {
        var el = document.getElementById(NA_BODY_CONTAINER_ID);
        if (el) return el;
        var panel = document.getElementById('na-tab-settings');
        if (!panel) return null;
        var body = document.createElement('div');
        body.id        = NA_BODY_CONTAINER_ID;
        body.className = 'na-settings-body';
        panel.appendChild(body);
        return body;
    }

    // -------------------------------------------------------------------------
    // REGION | Section Builders
    // -------------------------------------------------------------------------

    function na_build_button_block(descriptor) {
        var wrapper = document.createElement('div');
        wrapper.className = 'na-settings-button-row';

        var button = document.createElement('button');
        button.id          = descriptor.id;
        button.type        = 'button';
        button.className   = 'na-btn na-btn--primary na-settings-btn';
        button.textContent = descriptor.label;
        button.setAttribute('onclick', descriptor.onclick + '()');

        var helper = document.createElement('p');
        helper.className   = 'na-settings-helper';
        helper.textContent = descriptor.helper;

        wrapper.appendChild(button);
        wrapper.appendChild(helper);
        return wrapper;
    }

    function na_build_section(descriptor) {
        var section = document.createElement('section');
        section.className = 'na-settings-section';

        var h = document.createElement('h3');
        h.className   = 'na-settings-heading';
        h.textContent = descriptor.heading;
        section.appendChild(h);

        if (descriptor.description) {
            var desc = document.createElement('p');
            desc.className   = 'na-settings-description';
            desc.textContent = descriptor.description;
            section.appendChild(desc);
        }

        descriptor.buttons.forEach(function (b) { section.appendChild(na_build_button_block(b)); });
        return section;
    }

    function na_build_about_block() {
        var section = document.createElement('section');
        section.className = 'na-settings-section na-settings-section--about';

        var h = document.createElement('h3');
        h.className   = 'na-settings-heading';
        h.textContent = 'About';
        section.appendChild(h);

        var meta = document.createElement('p');
        meta.className   = 'na-settings-info-line na-settings-info-line--meta';
        meta.textContent = 'Batched Quadric Decimator  ' + NA_ABOUT.version + '  |  ' + NA_ABOUT.author;
        section.appendChild(meta);

        NA_ABOUT.lines.forEach(function (line) {
            var p = document.createElement('p');
            p.className   = 'na-settings-info-line';
            p.textContent = line;
            section.appendChild(p);
        });

        return section;
    }

    function na_render_body() {
        var body = na_get_or_create_body();
        if (!body) return;
        body.innerHTML = '';
        NA_SETTINGS_SECTIONS.forEach(function (s) { body.appendChild(na_build_section(s)); });
        body.appendChild(na_build_about_block());
    }

    // -------------------------------------------------------------------------
    // REGION | Public Tab Module API (na_mount / na_unmount contract)
    // -------------------------------------------------------------------------

    Na_SettingsUI.na_mount = function () {
        na_render_body();
    };

    Na_SettingsUI.na_unmount = function () {
        var body = document.getElementById(NA_BODY_CONTAINER_ID);
        if (body) body.innerHTML = '';
    };

    Na_SettingsUI.na_get_active_config = function () { return null; };

    window.Na_SettingsUI = Na_SettingsUI;

})();
