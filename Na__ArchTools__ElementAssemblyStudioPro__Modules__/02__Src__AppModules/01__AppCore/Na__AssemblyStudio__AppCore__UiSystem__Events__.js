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
            case 'color':          na_attachColorListener(config, onChangeCallback); break;
            case 'material_cards': na_attachMaterialCardsListener(config, onChangeCallback); break;
            case 'expandable':     na_attachExpandableListener(config, onChangeCallback); break;
        }
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
            config.children.forEach(child => { na_attachSliderListeners(child, onChangeCallback); });
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
        na_attachEventListeners:        na_attachEventListeners,
        na_attachSliderListeners:       na_attachSliderListeners,
        na_attachToggleListener:        na_attachToggleListener,
        na_attachColorListener:         na_attachColorListener,
        na_attachMaterialCardsListener: na_attachMaterialCardsListener,
        na_attachExpandableListener:    na_attachExpandableListener
    };
})();

window.Na__Ui__Events = Na__Ui__Events;
console.log('[NA_UI_EVENTS] Shared events module loaded');
