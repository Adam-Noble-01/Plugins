// =============================================================================
// ELEMENT ASSEMBLY STUDIO PRO - INTERIOR DOOR SYSTEM - FINISH CARDS
// =============================================================================
//
// FILE       : Na__AssemblyStudio__InteriorDoorSystem__UiSystem__FinishCards__.js
// NAMESPACE  : window.Na_FrameFinishCards
// AUTHOR     : Noble Architecture
// PURPOSE    : Render the Joinery Finish + Handle Finish swatch card rows
//              shown beneath the Interior Door panel. Each row reads from a
//              dedicated window global pushed in by Ruby:
//                Joinery -> window.NA_FRAME_FINISH_SWATCHES   (wood / paint)
//                Handle  -> window.NA_HANDLE_FINISH_SWATCHES  (metal ironmongery)
//
// BEHAVIOUR
// - When the materials JSON failed to load from the web, both card sections
//   stay hidden (NO fallback swatches). This is intentional debug aid.
// - A persistent toast is raised on the Ruby side when load fails.
// - Joinery clicks broadcast the picked material ID to Lining + Panel +
//   Architrave config keys in one update. Handle clicks update only the
//   Handle config key.
// - Each row hides independently if its own palette is empty/missing.
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

    var NA_FRAME_SWATCHES_GLOBAL   = 'NA_FRAME_FINISH_SWATCHES';
    var NA_FRAME_DEFAULT_GLOBAL    = 'NA_FRAME_FINISH_DEFAULT_KEY';
    var NA_HANDLE_SWATCHES_GLOBAL  = 'NA_HANDLE_FINISH_SWATCHES';
    var NA_HANDLE_DEFAULT_GLOBAL   = 'NA_HANDLE_FINISH_DEFAULT_KEY';

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
    // Joinery row uses NA_FRAME_FINISH_SWATCHES, Handle row uses
    // NA_HANDLE_FINISH_SWATCHES. Each row hides independently if its palette
    // is empty or the materials library failed to load.
    Na_FrameFinishCards.na_render_all = function () {
        var loadOk         = (window.NA_MATERIALS_LOAD_STATUS === NA_LOAD_STATUS_OK);
        var frameSwatches  = na_resolve_palette(NA_FRAME_SWATCHES_GLOBAL);
        var handleSwatches = na_resolve_palette(NA_HANDLE_SWATCHES_GLOBAL);
        var activeConfig   = na_get_active_door_config();

        na_render_palette_row({
            sectionId      : NA_JOINERY_SECTION_ID,
            cardsId        : NA_JOINERY_CARDS_ID,
            swatches       : frameSwatches,
            canRender      : loadOk && frameSwatches.length > 0,
            currentId      : na_resolve_initial_id(activeConfig, frameSwatches, [
                                NA_LINING_KEY, NA_PANEL_KEY, NA_ARCHITRAVE_KEY
                             ], NA_FRAME_DEFAULT_GLOBAL),
            onSelect       : na_handle_joinery_click
        });

        na_render_palette_row({
            sectionId      : NA_HANDLE_SECTION_ID,
            cardsId        : NA_HANDLE_CARDS_ID,
            swatches       : handleSwatches,
            canRender      : loadOk && handleSwatches.length > 0,
            currentId      : na_resolve_initial_id(activeConfig, handleSwatches, [
                                NA_HANDLE_KEY
                             ], NA_HANDLE_DEFAULT_GLOBAL),
            onSelect       : na_handle_handle_click
        });

        na_rebuild_window_frame_finish();
    };

    // FUNCTION | Update the Selected Cards to Match an External Config Change
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
    // REGION | Internals - Per-Palette Rendering
    // -----------------------------------------------------------------------

    function na_render_palette_row(opts) {
        na_set_section_visibility(opts.sectionId, opts.canRender);
        if (!opts.canRender) {
            na_clear_container(opts.cardsId);
            return;
        }
        na_render_card_row(opts.cardsId, opts.swatches, opts.currentId, opts.onSelect);
    }

    function na_resolve_palette(globalName) {
        var raw = window[globalName];
        return Array.isArray(raw) ? raw : [];
    }

    function na_get_active_door_config() {
        if (typeof window.Na_DoorUI !== 'object' ||
            typeof window.Na_DoorUI.na_get_active_config !== 'function') {
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

    function na_resolve_initial_id(config, swatches, configKeys, defaultGlobalName) {
        for (var i = 0; i < configKeys.length; i++) {
            var current = config[configKeys[i]];
            if (na_is_known_swatch_id(current, swatches)) return current;
        }
        return na_default_for_palette(swatches, defaultGlobalName);
    }

    function na_is_known_swatch_id(id, swatches) {
        if (!id) return false;
        for (var i = 0; i < swatches.length; i++) {
            if (swatches[i] && swatches[i].id === id) return true;
        }
        return false;
    }

    function na_default_for_palette(swatches, defaultGlobalName) {
        var configured = window[defaultGlobalName];
        if (na_is_known_swatch_id(configured, swatches)) return configured;
        return swatches.length > 0 ? swatches[0].id : null;
    }

    function na_rebuild_window_frame_finish() {
        if (typeof window.Na_DynamicUI === 'object' &&
            typeof window.Na_DynamicUI.na_rebuild_frame_finish_control === 'function') {
            try { window.Na_DynamicUI.na_rebuild_frame_finish_control(); }
            catch (err) { console.warn('[Na_FrameFinishCards] rebuild window frame finish failed:', err); }
        }
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
