// =============================================================================
// ELEMENT ASSEMBLY STUDIO PRO - INTERIOR DOOR SYSTEM - FINISH CARDS
// =============================================================================
//
// FILE       : Na__AssemblyStudio__InteriorDoorSystem__UiSystem__FinishCards__.js
// NAMESPACE  : window.Na_FrameFinishCards
// AUTHOR     : Noble Architecture
// PURPOSE    : Render the Joinery Finish + Handle Finish swatch card rows
//              shown beneath the Interior Door panel. Source data is the
//              live materials JSON pushed in by Ruby as
//              window.NA_FRAME_FINISH_SWATCHES.
//
// BEHAVIOUR
// - When the materials JSON failed to load from the web, both card sections
//   stay hidden (NO fallback swatches are rendered). This is intentional --
//   the user explicitly requested empty UI on failure as a debug aid.
// - A persistent toast is raised on the Ruby side when load fails, so the
//   user is told why the cards have disappeared.
// - Joinery clicks broadcast the picked material ID across Lining, Panel
//   and Architrave config keys in one update. Handle clicks update only
//   the Handle config key.
//
// =============================================================================

(function () {
    'use strict';

    var Na_FrameFinishCards = {};

    var NA_JOINERY_SECTION_ID  = 'na-door-joinery-finish-section';
    var NA_HANDLE_SECTION_ID   = 'na-door-handle-finish-section';
    var NA_JOINERY_CARDS_ID    = 'na-door-joinery-finish-cards';
    var NA_HANDLE_CARDS_ID     = 'na-door-handle-finish-cards';

    var NA_LINING_KEY          = 'Na__DoorConfig__LiningMaterialId';
    var NA_PANEL_KEY           = 'Na__DoorConfig__PanelMaterialId';
    var NA_ARCHITRAVE_KEY      = 'Na__DoorConfig__ArchitraveMaterialId';
    var NA_HANDLE_KEY          = 'Na__DoorConfig__HandleMaterialId';

    var NA_LOAD_STATUS_OK      = 'ok';

    var NA_CARD_CLASS          = 'na-material-card';
    var NA_CARD_SELECTED_CLASS = 'na-material-card-selected';
    var NA_SWATCH_CLASS        = 'na-material-swatch';
    var NA_LABEL_CLASS         = 'na-material-name';

    // -----------------------------------------------------------------------
    // REGION | Public API
    // -----------------------------------------------------------------------

    // FUNCTION | Render Both Door Card Rows + Refresh the Window Frame Finish
    // ------------------------------------------------------------
    // Called by Ruby (after pushing swatches) and by the door tab on mount.
    // Also rebuilds the Window tab's Frame Finish control so it picks up the
    // same live swatches without needing to reopen the dialog.
    Na_FrameFinishCards.na_render_all = function () {
        var swatches  = na_resolve_swatches();
        var canRender = na_can_render(swatches);

        na_set_section_visibility(NA_JOINERY_SECTION_ID, canRender);
        na_set_section_visibility(NA_HANDLE_SECTION_ID,  canRender);

        if (!canRender) {
            na_clear_container(NA_JOINERY_CARDS_ID);
            na_clear_container(NA_HANDLE_CARDS_ID);
            na_rebuild_window_frame_finish();                                  // <-- Will hide window row too via empty placeholder
            return;
        }

        var activeConfig = na_get_active_door_config();
        var joineryId    = na_resolve_initial_joinery_id(activeConfig, swatches);
        var handleId     = na_resolve_initial_handle_id(activeConfig, swatches);

        na_render_card_row(NA_JOINERY_CARDS_ID, swatches, joineryId, na_handle_joinery_click);
        na_render_card_row(NA_HANDLE_CARDS_ID,  swatches, handleId,  na_handle_handle_click);

        na_rebuild_window_frame_finish();
    };

    function na_rebuild_window_frame_finish() {
        if (typeof window.Na_DynamicUI === 'object' &&
            typeof window.Na_DynamicUI.na_rebuild_frame_finish_control === 'function') {
            try { window.Na_DynamicUI.na_rebuild_frame_finish_control(); }
            catch (err) { console.warn('[Na_FrameFinishCards] rebuild window frame finish failed:', err); }
        }
    }

    // FUNCTION | Update the Selected Card to Match an External Config Change
    // ------------------------------------------------------------
    // Used after Ruby pushes a loaded door's config back to the dialog.
    Na_FrameFinishCards.na_sync_selection = function (config) {
        if (!config) return;
        var joineryId = config[NA_LINING_KEY] || config[NA_PANEL_KEY] || config[NA_ARCHITRAVE_KEY];
        var handleId  = config[NA_HANDLE_KEY];
        na_apply_selected(NA_JOINERY_CARDS_ID, joineryId);
        na_apply_selected(NA_HANDLE_CARDS_ID,  handleId);
    };

    // -----------------------------------------------------------------------
    // REGION | Internals - Data Resolution
    // -----------------------------------------------------------------------

    function na_resolve_swatches() {
        var raw = window.NA_FRAME_FINISH_SWATCHES;
        return Array.isArray(raw) ? raw : [];
    }

    function na_can_render(swatches) {
        if (window.NA_MATERIALS_LOAD_STATUS !== NA_LOAD_STATUS_OK) return false;
        return swatches.length > 0;
    }

    function na_get_active_door_config() {
        if (typeof window.Na_DoorUI !== 'object' || typeof window.Na_DoorUI.na_get_active_config !== 'function') {
            return {};
        }
        try {
            var payload = window.Na_DoorUI.na_get_active_config();
            return (payload && payload['Na__DoorConfiguration']) || {};
        } catch (err) {
            console.warn('[Na_FrameFinishCards] Could not read door config:', err);
            return {};
        }
    }

    function na_resolve_initial_joinery_id(config, swatches) {
        var current = config[NA_LINING_KEY] || config[NA_PANEL_KEY] || config[NA_ARCHITRAVE_KEY];
        if (na_is_known_swatch_id(current, swatches)) return current;
        return na_default_swatch_id(swatches);
    }

    function na_resolve_initial_handle_id(config, swatches) {
        var current = config[NA_HANDLE_KEY];
        if (na_is_known_swatch_id(current, swatches)) return current;
        return na_default_swatch_id(swatches);
    }

    function na_is_known_swatch_id(id, swatches) {
        if (!id) return false;
        for (var i = 0; i < swatches.length; i++) {
            if (swatches[i] && swatches[i].id === id) return true;
        }
        return false;
    }

    function na_default_swatch_id(swatches) {
        var configured = window.NA_FRAME_FINISH_DEFAULT_KEY;
        if (na_is_known_swatch_id(configured, swatches)) return configured;
        return swatches.length > 0 ? swatches[0].id : null;
    }

    // -----------------------------------------------------------------------
    // REGION | Internals - DOM Rendering
    // -----------------------------------------------------------------------

    function na_set_section_visibility(sectionId, visible) {
        var section = document.getElementById(sectionId);
        if (!section) return;
        section.style.display = visible ? '' : 'none';
    }

    function na_clear_container(containerId) {
        var container = document.getElementById(containerId);
        if (container) container.innerHTML = '';
    }

    function na_render_card_row(containerId, swatches, selectedId, onSelect) {
        var container = document.getElementById(containerId);
        if (!container) return;

        container.innerHTML = '';

        swatches.forEach(function (swatch) {
            var card = na_build_card(swatch, swatch.id === selectedId, onSelect);
            container.appendChild(card);
        });
    }

    function na_build_card(swatch, isSelected, onSelect) {
        var card = document.createElement('div');
        card.className = NA_CARD_CLASS + (isSelected ? ' ' + NA_CARD_SELECTED_CLASS : '');
        card.setAttribute('data-material-id', swatch.id);
        card.setAttribute('title', swatch.label || swatch.id);

        var swatchPatch = document.createElement('div');
        swatchPatch.className           = NA_SWATCH_CLASS;
        swatchPatch.style.backgroundColor = swatch.hex || '#FFFFFF';

        var label = document.createElement('div');
        label.className   = NA_LABEL_CLASS;
        label.textContent = swatch.label || swatch.id;

        card.appendChild(swatchPatch);
        card.appendChild(label);

        card.addEventListener('click', function () {
            na_mark_selected_in_row(card);
            onSelect(swatch.id);
        });

        return card;
    }

    function na_mark_selected_in_row(card) {
        var parent = card.parentNode;
        if (!parent) return;
        var siblings = parent.querySelectorAll('.' + NA_CARD_CLASS);
        for (var i = 0; i < siblings.length; i++) {
            siblings[i].classList.remove(NA_CARD_SELECTED_CLASS);
        }
        card.classList.add(NA_CARD_SELECTED_CLASS);
    }

    function na_apply_selected(containerId, selectedId) {
        var container = document.getElementById(containerId);
        if (!container) return;
        var cards = container.querySelectorAll('.' + NA_CARD_CLASS);
        for (var i = 0; i < cards.length; i++) {
            if (cards[i].getAttribute('data-material-id') === selectedId) {
                cards[i].classList.add(NA_CARD_SELECTED_CLASS);
            } else {
                cards[i].classList.remove(NA_CARD_SELECTED_CLASS);
            }
        }
    }

    // -----------------------------------------------------------------------
    // REGION | Internals - Click Handlers
    // -----------------------------------------------------------------------

    function na_handle_joinery_click(materialId) {
        na_apply_door_config_change({
            'Na__DoorConfig__LiningMaterialId'    : materialId,
            'Na__DoorConfig__PanelMaterialId'     : materialId,
            'Na__DoorConfig__ArchitraveMaterialId': materialId
        });
    }

    function na_handle_handle_click(materialId) {
        na_apply_door_config_change({
            'Na__DoorConfig__HandleMaterialId': materialId
        });
    }

    function na_apply_door_config_change(updates) {
        if (typeof window.Na_DoorUI !== 'object' ||
            typeof window.Na_DoorUI.na_apply_config_change !== 'function') {
            console.warn('[Na_FrameFinishCards] Na_DoorUI.na_apply_config_change unavailable');
            return;
        }
        window.Na_DoorUI.na_apply_config_change(updates);
    }

    // -----------------------------------------------------------------------

    window.Na_FrameFinishCards = Na_FrameFinishCards;

})();

// =============================================================================
// END OF FILE
// =============================================================================
