/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - ACTION DOCK
   =============================================================================
   FILE       : Na__AssemblyStudio__AppCore__UiSystem__ActionDock__.js
   NAMESPACE  : window.Na__Ui__ActionDock
   AUTHOR     : Noble Architecture
   PURPOSE    : Keeps the hint line of the pinned action dock current. The dock
                holds every action in one place at the foot of the dialog:
                (1) Measure Opening -> (2) Insert at Measured Point, side by
                side, then Create at Cursor, Update and Live Mode.
   CREATED    : 28-Oct-2026

   HOW IT WORKS
   - The buttons keep their original ids, onclick handlers and the classes the
     bridges already paint (na-btn-measure-active, na-btn-create-measure-ready,
     disabled, na-btn-live-active), so no bridge changes.
   - This module only watches those states (MutationObserver) and writes one
     sentence saying what happens next. A status message from na_showStatus
     takes the line's place while it is shown.
   - Which tab's buttons show is CSS: body[data-na-active-tab] (set by
     Na_AppContext) against each button's data-na-dock-tab.
   ============================================================================= */

(function () {
    'use strict';

    // -----------------------------------------------------------------------------
    // REGION | Constants
    // -----------------------------------------------------------------------------

    const NA_HINT_ID = 'na-dock-hint';

    // Per tab: which buttons say "a measurement is waiting" and "an element is
    // being edited". Windows reads its Window Info strip (the Update button is
    // enabled whenever the preview is valid, so it cannot tell); Interior Doors
    // enables Update only while a door is selected.
    const NA_TAB_SOURCES = {
        windows: {
            measuredButtonId : 'na-btn-create-at-measurement',
            isEditing        : () => {
                const info = document.getElementById('na-window-info');
                return !!info && !info.classList.contains('na-hidden');
            },
            measuringHint    : 'Click the opening’s corners in the model to measure it. Esc cancels.',
            thing            : 'element'
        },
        doors: {
            measuredButtonId : 'na-btn-door-create-at-measurement',
            isEditing        : () => {
                const update = document.getElementById('na-btn-door-update');
                return !!update && !update.disabled;
            },
            measuringHint    : 'Click Point A, then Point B, then drag to set the wall depth. Esc cancels.',
            thing            : 'door'
        },
        // Cabinets measure a run and keep it: every Insert in Run takes the
        // next point along it. Create at Cursor places units until Esc.
        cabinets: {
            measuredButtonId : 'na-btn-cab-create-at-measurement',
            isEditing        : () => {
                const update = document.getElementById('na-btn-cab-update');
                return !!update && !update.disabled;
            },
            isPlacing        : () => {
                const create = document.getElementById('na-btn-cab-create');
                return !!create && create.classList.contains('na-dock__btn--placing');
            },
            measuringHint    : 'Click the start of the run on the floor line, then its end, then the room side. Esc cancels.',
            measuredHint     : () => {
                const run   = window.NA_CABINET_RUN || {};
                const left  = Math.round((run.lengthMm || 0) - (run.usedMm || 0));
                const cfg   = window.Na_CabinetUI ? window.Na_CabinetUI.na_get_ui_config() : {};
                const width = Math.round(Number(cfg.Na__CabinetConfig__Width_mm) || 0);
                const range = (window.NA_CABINET_SIZE_CONFIG || []).find(item => item.id === 'Na__CabinetConfig__Width_mm');
                if (left <= 0) return 'The measured run is full. Measure the next run, or Create at Cursor.';
                if (range && left < Number(range.min)) {
                    return left + 'mm left, narrower than the smallest unit. Fit a filler there, then measure the next run.';
                }
                if (width > left) {
                    return left.toLocaleString('en-GB') + 'mm left, less than this ' + width + 'mm unit. Set Width to ' + left + ' to fill it, then ② Insert in Run.';
                }
                return 'Run measured, ' + left.toLocaleString('en-GB') + 'mm left. Set the unit, then press ② Insert in Run.';
            },
            placingHint      : 'Placing: click in the model. Over a unit it goes beside it, over a wall it backs onto it. Tab turns, Esc finishes.',
            idleHint         : 'Nothing selected. Set the unit up, then Create at Cursor, or ① measure a run along a wall.',
            thing            : 'unit'
        }
    };

    // endregion -------------------------------------------------------------------

    // -----------------------------------------------------------------------------
    // REGION | Hint
    // -----------------------------------------------------------------------------

    // HELPER FUNCTION | Resolve the Active Tab Id
    // ------------------------------------------------------------
    function na_active_tab() {
        if (window.Na_AppContext && typeof window.Na_AppContext.na_get_active_tab === 'function') {
            return window.Na_AppContext.na_get_active_tab();
        }
        return document.body.getAttribute('data-na-active-tab') || 'windows';
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Compose the Sentence for the Current State
    // ------------------------------------------------------------
    function na_compose_hint(source) {
        const measure  = document.getElementById('na-btn-measure');
        const measured = document.getElementById(source.measuredButtonId);
        const live     = document.getElementById('na-btn-live');

        if (measure && measure.classList.contains('na-btn-measure-active')) {
            return { tone: 'amber', text: source.measuringHint };
        }
        if (source.isPlacing && source.isPlacing()) {
            return { tone: 'amber', text: source.placingHint };
        }
        if (measured && !measured.disabled) {
            return { tone: 'amber', text: source.measuredHint ? source.measuredHint() : 'Opening measured. Adjust anything, then press ② Insert at Measured Point.' };
        }
        if (source.isEditing()) {
            if (live && live.classList.contains('na-btn-live-active')) {
                return { tone: 'green', text: 'Live Mode: every change goes straight to the selected ' + source.thing + '.' };
            }
            return { tone: 'green', text: 'Editing the selected ' + source.thing + '. Press Update to apply your changes.' };
        }
        return { tone: '', text: source.idleHint || 'Nothing selected. Set it up, then Create at Cursor, or ① measure an opening first.' };
    }
    // ---------------------------------------------------------------

    // FUNCTION | Repaint the Dock Hint
    // ------------------------------------------------------------
    function na_refresh_hint() {
        const hint   = document.getElementById(NA_HINT_ID);
        const source = NA_TAB_SOURCES[na_active_tab()];
        if (!hint || !source) return;
        const state = na_compose_hint(source);
        hint.textContent = state.text;
        hint.setAttribute('data-na-tone', state.tone);
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------

    // -----------------------------------------------------------------------------
    // REGION | Observation
    // -----------------------------------------------------------------------------

    // FUNCTION | Watch Every Element Whose State the Hint Reads
    // ------------------------------------------------------------
    function na_observe() {
        const ids = [
            'na-btn-measure', 'na-btn-live', 'na-window-info',
            'na-btn-create-at-measurement', 'na-btn-door-create-at-measurement',
            'na-btn-door-update',
            'na-btn-cab-create-at-measurement', 'na-btn-cab-update', 'na-btn-cab-create'
        ];
        const observer = new MutationObserver(na_refresh_hint);
        ids.forEach(id => {
            const el = document.getElementById(id);
            if (el) observer.observe(el, { attributes: true, attributeFilter: ['class', 'disabled'] });
        });
        observer.observe(document.body, { attributes: true, attributeFilter: ['data-na-active-tab'] });
        na_refresh_hint();
    }
    // ---------------------------------------------------------------

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', na_observe);
    } else {
        na_observe();
    }

    window.Na__Ui__ActionDock = { na_refresh_hint: na_refresh_hint };

    // endregion -------------------------------------------------------------------
})();

/* =============================================================================
   END OF FILE
   ============================================================================= */
