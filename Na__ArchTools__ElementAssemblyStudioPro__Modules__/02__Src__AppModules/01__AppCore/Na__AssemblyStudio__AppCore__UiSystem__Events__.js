/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - SHARED UI EVENTS
   =============================================================================
   FILE       : Na__AssemblyStudio__AppCore__UiSystem__Events__.js
   NAMESPACE  : window.Na__Ui__Events (lifted from WindowSystem so all
                systems can share one descriptor-control event engine)
   AUTHOR     : Noble Architecture
   PURPOSE    : Attach event listeners to dynamically generated UI controls
                created by Na__Ui__Controls. Decoupled from state via callback.
   ============================================================================= */

const Na__Ui__Events = (function () {

    // -----------------------------------------------------------------------------
    // REGION | Arithmetic Entry Helpers
    // -----------------------------------------------------------------------------

    // HELPER FUNCTION | Resolve the Shared Arithmetic Evaluator
    // ------------------------------------------------------------
    // Returned lazily rather than captured at load time so the dialog still
    // works (falling back to plain numbers) if the utils script fails to load.
    // @return {Object|null} window.Na__Utils__Arithmetic or null
    function na_arithmetic() {
        return window.Na__Utils__Arithmetic || null;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Read the Live Clamp Range Off the Rendered Control
    // ------------------------------------------------------------
    // The DOM is authoritative, not the descriptor: `width_mm` is declared
    // max 4000 but has its slider max widened to 8000 in multi-leaf door
    // modes, and the Interior Door tab widens a max in place when a measured
    // opening exceeds it. Reading the descriptor here would silently clamp a
    // legitimate 6000mm bifold width back to 4000.
    // @param  {Object}  config - Control descriptor
    // @param  {Element} input  - The text entry field
    // @return {Object}           { min, max, step } - values may be NaN
    function na_readLiveRange(config, input) {
        // Absent means absent: Number(null) is 0, so a missing max attribute
        // would otherwise read as a hard ceiling of zero and clamp every entry
        // in the control to nothing.
        function na_toNumber(candidate) {
            if (candidate === null || candidate === undefined || candidate === '') return NaN;
            const value = Number(candidate);
            return isFinite(value) ? value : NaN;
        }
        function na_pick(attributeName, descriptorValue) {
            const fromDom = na_toNumber(input ? input.getAttribute(attributeName) : null);
            if (isFinite(fromDom)) return fromDom;
            return na_toNumber(descriptorValue);
        }
        return {
            min : na_pick('min',  config.min),
            max : na_pick('max',  config.max),
            step: na_pick('step', config.step)
        };
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Flag / Clear a Field That Could Not Be Read
    // ------------------------------------------------------------
    // Previously an unreadable entry ran through parseFloat('') -> NaN and was
    // written straight into the config. Now the field turns red, the reason
    // replaces its tooltip until the next keystroke, and the caller restores
    // the last good value instead. The arithmetic hint the field normally
    // carries is stashed so it can be put back.
    function na_markInputError(input, message) {
        if (!input) return;
        if (!input.classList.contains('na-input-error')) {
            input.dataset.naTitle = input.getAttribute('title') || '';
        }
        input.classList.add('na-input-error');
        input.setAttribute('title', message || 'Could not read that entry');
    }

    function na_clearInputError(input) {
        if (!input || !input.classList.contains('na-input-error')) return;
        input.classList.remove('na-input-error');
        input.setAttribute('title', input.dataset.naTitle || '');
        delete input.dataset.naTitle;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Resolve Typed Text Into a Committed Numeric Value
    // ------------------------------------------------------------
    // The single commit path shared by every numeric field. Evaluates the
    // expression, clamps to the live range, and on failure restores the value
    // the field held before the edit.
    //
    // A leading '-' is only treated as relative when the control cannot hold a
    // negative (min >= 0). In Meeting Rail Offset (-600..600) or Frame Wall
    // Inset (-50..150), '-50' stays a literal -50.
    //
    // @param  {String}  rawText      - Exactly what the user typed
    // @param  {Object}  range        - Output of na_readLiveRange
    // @param  {Number}  previousValue- Value before this edit
    // @return {Object}                 { ok, value } | { ok: false, error }
    function na_resolveTypedValue(rawText, range, previousValue) {
        const arithmetic = na_arithmetic();

        if (!arithmetic) {                                                      // <-- Degrade to plain-number entry
            const parsed = parseFloat(rawText);
            if (!isFinite(parsed)) return { ok: false, error: 'Not a number' };
            let value = parsed;
            if (isFinite(range.min)) value = Math.max(range.min, value);
            if (isFinite(range.max)) value = Math.min(range.max, value);
            return { ok: true, value: value };
        }

        return arithmetic.na_resolve_field_value(rawText, {
            currentValue      : previousValue,
            min               : range.min,
            max               : range.max,
            allowRelativeMinus: !(isFinite(range.min) && range.min < 0)
        });
    }
    // ---------------------------------------------------------------

    // FUNCTION | Format a Committed Value for Display in a Field
    // ------------------------------------------------------------
    function na_formatValue(value) {
        const arithmetic = na_arithmetic();
        return arithmetic ? arithmetic.na_format(value) : String(value);
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------

    function na_attachEventListeners(config, onChangeCallback) {
        switch (config.type) {
            case 'slider':         na_attachSliderListeners(config, onChangeCallback); break;
            case 'toggle':         na_attachToggleListener(config, onChangeCallback); break;
            case 'binary_toggle':  na_attachBinaryToggleListener(config, onChangeCallback); break;
            case 'multiway_toggle':na_attachMultiwayToggleListener(config, onChangeCallback); break;
            case 'eq_number':      na_attachEqNumberListener(config, onChangeCallback); break;
            case 'select':         na_attachSelectListener(config, onChangeCallback); break;
            case 'color':          na_attachColorListener(config, onChangeCallback); break;
            case 'material_cards': na_attachMaterialCardsListener(config, onChangeCallback); break;
            case 'expandable':     na_attachExpandableListener(config, onChangeCallback); break;
        }
    }

    // EQ-number: normalizes free text to the literal 'EQ' or a numeric mm value.
    // Blank / "eq" / "equal" / "=" (case-insensitive) -> 'EQ'. Anything else is
    // run through the arithmetic evaluator, so the leaf width accepts
    // '1700/2' or '+50' as readily as a plain number. An entry that cannot be
    // read falls back to 'EQ', which is this field's documented safe default
    // and is immediately visible in the field.
    // @param {String} raw          - Field text
    // @param {Number} currentValue - Numeric value before the edit, or NaN when 'EQ'
    function na_normalizeEqValue(raw, currentValue) {
        const text = String(raw == null ? '' : raw).trim();
        if (text === '') return 'EQ';
        if (/^(eq|equal|equals|equ|=)$/i.test(text)) return 'EQ';

        const arithmetic = na_arithmetic();
        if (arithmetic) {
            const resolved = arithmetic.na_resolve_field_value(text, {
                currentValue      : currentValue,
                allowRelativeMinus: true                                        // <-- A leaf width is never negative
            });
            return resolved.ok ? resolved.value : 'EQ';
        }

        const num = parseFloat(text);
        if (!isFinite(num)) return 'EQ';
        return num;
    }

    function na_attachEqNumberListener(config, onChangeCallback) {
        const input = document.getElementById(`${config.id}-eqnumber`);
        if (!input) return;

        // Relative entry needs the width the field held before the edit. 'EQ'
        // carries no number, so relative entry simply has nothing to build on
        // and the expression is evaluated standalone.
        let lastCommittedValue = parseFloat(config.default);

        input.addEventListener('focus', () => {
            const atFocus = parseFloat(input.value);
            lastCommittedValue = isFinite(atFocus) ? atFocus : NaN;
        });

        input.addEventListener('change', () => {
            const normalized = na_normalizeEqValue(input.value, lastCommittedValue);
            input.value = normalized;
            lastCommittedValue = (typeof normalized === 'number') ? normalized : NaN;
            if (onChangeCallback) onChangeCallback(config.id, normalized);
        });
    }

    // Multiway toggle: segmented switch. Clicking an option sets data-value on
    // the container and moves the --active class, then emits the option value.
    function na_attachMultiwayToggleListener(config, onChangeCallback) {
        const container = document.getElementById(`${config.id}-segmented`);
        if (!container) return;
        const buttons = container.querySelectorAll('.na-segmented-toggle__option');
        buttons.forEach(button => {
            button.addEventListener('click', () => {
                const value = button.getAttribute('data-option-value');
                container.setAttribute('data-value', value);
                buttons.forEach(other => other.classList.remove('na-segmented-toggle__option--active'));
                button.classList.add('na-segmented-toggle__option--active');
                if (onChangeCallback) onChangeCallback(config.id, value);
            });
        });
    }

    function na_attachExpandableListener(config, onChangeCallback) {
        const header  = document.getElementById(`${config.id}-header`);
        const content = document.getElementById(`${config.id}-content`);
        if (header && content) {
            header.addEventListener('click', () => {
                const isExpanded = header.dataset.expanded === 'true';
                const newState   = !isExpanded;
                header.dataset.expanded = newState;
                header.classList.toggle('na-expanded', newState);
                content.classList.toggle('na-expanded', newState);
                if (onChangeCallback) onChangeCallback(config.id, newState);
            });
        }
        if (config.children && config.children.length > 0) {
            // Dispatch on child.type so expandable sections can host sliders,
            // toggles, etc. (e.g. Advanced Glazebar Controls hosts both).
            config.children.forEach(child => {
                na_attachEventListeners(child, onChangeCallback);
            });
        }
    }

    // Slider: range + arithmetic-capable entry field.
    //
    // The entry field is type="text" (see Na__Ui__Controls.na_createSliderHtml)
    // so it accepts expressions. Evaluation happens on `change` - which fires
    // on Enter and on blur - never per keystroke, so a half-typed '1700-' is
    // never committed.
    function na_attachSliderListeners(config, onChangeCallback) {
        const slider  = document.getElementById(`${config.id}-slider`);
        const input   = document.getElementById(`${config.id}-input`);
        const display = document.getElementById(`${config.id}-display`);

        // Value the field held before the current edit. Seeded on focus (when
        // the field always shows a committed number, however it got there) and
        // refreshed on every commit, so consecutive relative entries stack:
        // '+200' then '+200' on 2400 gives 2800, not 2600 twice.
        let lastCommittedValue = Number(config.default);

        function na_currentValue() {
            if (isFinite(lastCommittedValue)) return lastCommittedValue;
            const fromSlider = slider ? parseFloat(slider.value) : NaN;
            return isFinite(fromSlider) ? fromSlider : NaN;
        }

        // `fromSlider` suppresses the write back to the range element, so a
        // live drag is never assigned to mid-gesture from its own handler.
        function na_applyValue(value, fromSlider) {
            lastCommittedValue = value;
            if (input)             input.value = na_formatValue(value);
            if (slider && !fromSlider) slider.value = value;
            if (display)           display.textContent = `${na_formatValue(value)}${config.unit}`;
            if (onChangeCallback)  onChangeCallback(config.id, value);
        }

        if (slider) {
            slider.addEventListener('input', () => {
                const value = parseFloat(slider.value);
                if (!isFinite(value)) return;
                na_clearInputError(input);
                na_applyValue(value, true);
            });
        }

        if (!input) return;

        // Re-read on focus so a value set programmatically (loading a saved
        // window, a linked control, a preset) is what relative entry builds on.
        input.addEventListener('focus', () => {
            const atFocus = parseFloat(input.value);
            if (isFinite(atFocus)) lastCommittedValue = atFocus;
        });

        // Typing clears a stale error mark; the entry is only judged on commit.
        input.addEventListener('input', () => na_clearInputError(input));

        input.addEventListener('change', () => {
            const range    = na_readLiveRange(config, input);
            const previous = na_currentValue();
            const resolved = na_resolveTypedValue(input.value, range, previous);

            if (!resolved.ok) {                                                 // <-- Restore, never write NaN
                na_markInputError(input, resolved.error);
                input.value = isFinite(previous) ? na_formatValue(previous) : '';
                return;
            }
            na_clearInputError(input);
            na_applyValue(resolved.value);
        });

        // Up/Down arrow stepping, which type="number" used to provide natively.
        // Shift multiplies the step by 10 for coarse moves.
        input.addEventListener('keydown', (event) => {
            if (event.key !== 'ArrowUp' && event.key !== 'ArrowDown') return;

            const range = na_readLiveRange(config, input);
            const step  = (isFinite(range.step) && range.step > 0) ? range.step : 1;
            const typed = parseFloat(input.value);
            const base  = isFinite(typed) ? typed : na_currentValue();          // <-- Step from the typed number when it is one
            if (!isFinite(base)) return;

            let next = base + (event.key === 'ArrowUp' ? step : -step) * (event.shiftKey ? 10 : 1);
            if (isFinite(range.min)) next = Math.max(range.min, next);
            if (isFinite(range.max)) next = Math.min(range.max, next);

            event.preventDefault();
            na_clearInputError(input);
            na_applyValue(next);
        });
    }

    function na_attachToggleListener(config, onChangeCallback) {
        const toggle = document.getElementById(`${config.id}-toggle`);
        if (toggle) {
            toggle.addEventListener('click', () => {
                const currentValue = toggle.dataset.value === 'true';
                const newValue     = !currentValue;
                toggle.dataset.value = newValue;
                toggle.classList.toggle('na-active', newValue);
                if (onChangeCallback) onChangeCallback(config.id, newValue);
            });
        }
    }

    // Select: emits the chosen option value on change.
    function na_attachSelectListener(config, onChangeCallback) {
        const select = document.getElementById(`${config.id}-select`);
        if (!select) return;
        select.addEventListener('change', () => {
            if (onChangeCallback) onChangeCallback(config.id, select.value);
        });
    }

    // Binary toggle: flips between the two `options` values declared on the
    // descriptor. Reads the left/right values out of data-attributes that
    // na_createBinaryToggleHtml stamped on the root element so the listener
    // does not need to know about descriptor mutation order.
    function na_attachBinaryToggleListener(config, onChangeCallback) {
        const toggle = document.getElementById(`${config.id}-btoggle`);
        if (!toggle) return;
        const leftValue  = toggle.getAttribute('data-left-value');
        const rightValue = toggle.getAttribute('data-right-value');
        toggle.addEventListener('click', () => {
            const currentVal = toggle.getAttribute('data-value');
            const newVal     = (currentVal === rightValue) ? leftValue : rightValue;
            const goingRight = (newVal === rightValue);
            toggle.setAttribute('data-value', newVal);
            toggle.classList.toggle('na-binary-toggle--left',  !goingRight);
            toggle.classList.toggle('na-binary-toggle--right', goingRight);
            if (onChangeCallback) onChangeCallback(config.id, newVal);
        });
    }

    function na_attachColorListener(config, onChangeCallback) {
        const colorPicker = document.getElementById(`${config.id}-color`);
        const display     = document.getElementById(`${config.id}-display`);
        if (colorPicker) {
            colorPicker.addEventListener('input', () => {
                const value = colorPicker.value;
                if (display) display.textContent = value;
                if (onChangeCallback) onChangeCallback(config.id, value);
            });
        }
    }

    function na_attachMaterialCardsListener(config, onChangeCallback) {
        const container = document.getElementById(`${config.id}-cards`);
        if (container) {
            const cards = container.querySelectorAll('.na-material-card');
            cards.forEach(card => {
                card.addEventListener('click', () => {
                    cards.forEach(c => c.classList.remove('na-material-card-selected'));
                    card.classList.add('na-material-card-selected');
                    const materialId = card.dataset.materialId;
                    if (onChangeCallback) onChangeCallback(config.id, materialId);
                });
            });
        }
    }

    return {
        na_attachEventListeners:         na_attachEventListeners,
        na_attachSliderListeners:        na_attachSliderListeners,
        na_attachToggleListener:         na_attachToggleListener,
        na_attachBinaryToggleListener:   na_attachBinaryToggleListener,
        na_attachMultiwayToggleListener: na_attachMultiwayToggleListener,
        na_attachEqNumberListener:       na_attachEqNumberListener,
        na_attachSelectListener:         na_attachSelectListener,
        na_attachColorListener:          na_attachColorListener,
        na_attachMaterialCardsListener:  na_attachMaterialCardsListener,
        na_attachExpandableListener:     na_attachExpandableListener
    };
})();

window.Na__Ui__Events = Na__Ui__Events;
console.log('[NA_UI_EVENTS] Shared events module loaded');
