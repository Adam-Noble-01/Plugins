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
    // Blank / "eq" / "equal" / "=" (case-insensitive) / non-numeric -> 'EQ'.
    function na_normalizeEqValue(raw) {
        const text = String(raw == null ? '' : raw).trim();
        if (text === '') return 'EQ';
        if (/^(eq|equal|equals|equ|=)$/i.test(text)) return 'EQ';
        const num = parseFloat(text);
        if (!isFinite(num)) return 'EQ';
        return num;
    }

    function na_attachEqNumberListener(config, onChangeCallback) {
        const input = document.getElementById(`${config.id}-eqnumber`);
        if (!input) return;
        input.addEventListener('change', () => {
            const normalized = na_normalizeEqValue(input.value);
            input.value = normalized;
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

    function na_attachSliderListeners(config, onChangeCallback) {
        const slider  = document.getElementById(`${config.id}-slider`);
        const input   = document.getElementById(`${config.id}-input`);
        const display = document.getElementById(`${config.id}-display`);
        if (slider) {
            slider.addEventListener('input', () => {
                const value = parseFloat(slider.value);
                if (input)   input.value = value;
                if (display) display.textContent = `${value}${config.unit}`;
                if (onChangeCallback) onChangeCallback(config.id, value);
            });
        }
        if (input) {
            input.addEventListener('change', () => {
                let value = parseFloat(input.value);
                value = Math.max(config.min, Math.min(config.max, value));
                input.value = value;
                if (slider)  slider.value = value;
                if (display) display.textContent = `${value}${config.unit}`;
                if (onChangeCallback) onChangeCallback(config.id, value);
            });
        }
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
