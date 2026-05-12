// =============================================================================
// NA PROFILE TOOLS - APP UTILS - SETTINGS TAB - UI LOGIC
// =============================================================================
//
// FILE       : Na__ProfileTools__AppUtils__SettingsTab__UiLogic__.js
// NAMESPACE  : window.Na__ProfileTools__Settings__Tab
// PURPOSE    : Settings tab content — Plugin Maintenance, Edge Materials Cache,
//              and About section. Implements the mount/unmount contract.
//
// =============================================================================

(function () {
    'use strict';

    var Na__ProfileTools__Settings__Tab = {};
    var NA_SETTINGS_BODY_ID = 'na-tab-settings-body';

    // -------------------------------------------------------------------------
    // REGION | Section Descriptors
    // -------------------------------------------------------------------------

    var NA_SETTINGS_SECTIONS = [
        {
            heading: 'Plugin Maintenance',
            description: 'Reload re-requires every Ruby file under the plugin folder so changes take effect without restarting SketchUp.',
            buttons: [
                {
                    id: 'na-btn-settings-reload',
                    label: 'Reload Plugin',
                    helper: 'Re-loads all Ruby and validates JS assets. Reopens the dialog with fresh code.',
                    onclick: 'na_profiletools_settingsReloadPlugin'
                }
            ]
        },
        {
            heading: 'Edge Materials Cache',
            description: 'Edge material standards are downloaded from the Noble Architecture GitHub repository each time the plugin loads. Use these controls to manually refresh or clear the cache.',
            buttons: [
                {
                    id: 'na-btn-settings-refresh-edges',
                    label: 'Refresh Edge Materials Now',
                    helper: 'Forces a fresh download of the edge materials JSON from the URL. Updates the cache file.',
                    onclick: 'na_profiletools_settingsRefreshEdgeMaterials'
                },
                {
                    id: 'na-btn-settings-purge-edges',
                    label: 'Purge Edge Materials Cache',
                    helper: 'Deletes the cached edge materials file and downloads a fresh copy. Use after data corrections on the source repository.',
                    onclick: 'na_profiletools_settingsPurgeEdgeMaterialsCache'
                }
            ]
        }
    ];

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Section Builders
    // -------------------------------------------------------------------------

    function na_build_button_block(descriptor) {
        var wrapper = document.createElement('div');
        wrapper.className = 'na-settings-button-row';

        var button = document.createElement('button');
        button.id        = descriptor.id;
        button.type      = 'button';
        button.className = 'na-btn na-btn-primary na-settings-btn';
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

    function na_build_about_block() {
        var section = document.createElement('section');
        section.className = 'na-settings-section na-settings-section-info';

        var heading = document.createElement('h3');
        heading.className   = 'na-settings-heading';
        heading.textContent = 'About';
        section.appendChild(heading);

        var lines = [
            'Na Profile Path Tracer by Noble Architecture',
            'Edge material standards: https://github.com/Adam-Noble-01/Plugins',
            'Load status is shown on the status bar at the bottom of the dialog.'
        ];
        lines.forEach(function (line) {
            var p = document.createElement('p');
            p.className   = 'na-settings-info-line';
            p.textContent = line;
            section.appendChild(p);
        });
        return section;
    }

    function na_render_body() {
        var body = document.getElementById(NA_SETTINGS_BODY_ID);
        if (!body) return;
        body.innerHTML = '';
        NA_SETTINGS_SECTIONS.forEach(function (s) { body.appendChild(na_build_section(s)); });
        body.appendChild(na_build_about_block());
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Tab Lifecycle
    // -------------------------------------------------------------------------

    Na__ProfileTools__Settings__Tab.na_mount = function () {
        na_render_body();
    };

    Na__ProfileTools__Settings__Tab.na_unmount = function () {
        var body = document.getElementById(NA_SETTINGS_BODY_ID);
        if (body) body.innerHTML = '';
    };

    Na__ProfileTools__Settings__Tab.na_get_active_config = function () { return null; };

    // endregion ----------------------------------------------------------------

    window.Na__ProfileTools__Settings__Tab = Na__ProfileTools__Settings__Tab;

    // endregion ----------------------------------------------------------------
})();
