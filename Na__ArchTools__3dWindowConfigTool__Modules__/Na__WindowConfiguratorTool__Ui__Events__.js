/* =============================================================================
   NA WINDOW CONFIGURATOR TOOL - UI EVENTS
   =============================================================================
   
   FILE       : Na__WindowConfiguratorTool__Ui__Events__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Event handler attachment for UI controls
   CREATED    : 2026
   
   DESCRIPTION:
   - Attaches event listeners to dynamically generated UI controls
   - Slider synchronization (range input <-> number input)
   - Toggle switch click handlers
   - Color picker change handlers
   - Expandable panel expand/collapse handlers
   - Decoupled from state management via callback pattern
   
   NAMING CONVENTION:
   - All functions use na_ prefix (lowercase)
   - Exported to window.Na__Ui__Events object
   
   ============================================================================= */

// =============================================================================
// REGION | UI Events Module
// =============================================================================

const Na__Ui__Events = (function() {
    
    // FUNCTION | Attach Event Listeners to a Control
    // ------------------------------------------------------------
    // @param {Object} config - Control configuration object
    // @param {Function} onChangeCallback - Callback function(id, value) called when value changes
    function na_attachEventListeners(config, onChangeCallback) {
        switch (config.type) {
            case 'slider':
                na_attachSliderListeners(config, onChangeCallback);
                break;
            case 'toggle':
                na_attachToggleListener(config, onChangeCallback);
                break;
            case 'color':
                na_attachColorListener(config, onChangeCallback);
                break;
            case 'material_cards':
                na_attachMaterialCardsListener(config, onChangeCallback);
                break;
            case 'expandable':
                na_attachExpandableListener(config, onChangeCallback);
                break;
        }
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Attach Expandable Panel Event Listener
    // ------------------------------------------------------------
    function na_attachExpandableListener(config, onChangeCallback) {
        const header = document.getElementById(`${config.id}-header`);
        const content = document.getElementById(`${config.id}-content`);
        
        if (header && content) {
            header.addEventListener('click', () => {
                const isExpanded = header.dataset.expanded === 'true';
                const newState = !isExpanded;
                
                header.dataset.expanded = newState;
                header.classList.toggle('na-expanded', newState);
                content.classList.toggle('na-expanded', newState);
                
                if (onChangeCallback) {
                    onChangeCallback(config.id, newState);
                }
            });
        }
        
        // Attach listeners to child controls
        if (config.children && config.children.length > 0) {
            config.children.forEach(childConfig => {
                na_attachSliderListeners(childConfig, onChangeCallback);
            });
        }
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Attach Slider Event Listeners
    // ------------------------------------------------------------
    function na_attachSliderListeners(config, onChangeCallback) {
        const slider = document.getElementById(`${config.id}-slider`);
        const input = document.getElementById(`${config.id}-input`);
        const display = document.getElementById(`${config.id}-display`);
        
        if (slider) {
            slider.addEventListener('input', () => {
                const value = parseFloat(slider.value);
                if (input) input.value = value;
                if (display) display.textContent = `${value}${config.unit}`;
                
                if (onChangeCallback) {
                    onChangeCallback(config.id, value);
                }
            });
        }
        
        if (input) {
            input.addEventListener('change', () => {
                let value = parseFloat(input.value);
                value = Math.max(config.min, Math.min(config.max, value));
                input.value = value;
                if (slider) slider.value = value;
                if (display) display.textContent = `${value}${config.unit}`;
                
                if (onChangeCallback) {
                    onChangeCallback(config.id, value);
                }
            });
        }
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Attach Toggle Event Listener
    // ------------------------------------------------------------
    function na_attachToggleListener(config, onChangeCallback) {
        const toggle = document.getElementById(`${config.id}-toggle`);
        
        if (toggle) {
            toggle.addEventListener('click', () => {
                const currentValue = toggle.dataset.value === 'true';
                const newValue = !currentValue;
                toggle.dataset.value = newValue;
                toggle.classList.toggle('na-active', newValue);
                
                if (onChangeCallback) {
                    onChangeCallback(config.id, newValue);
                }
            });
        }
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Attach Color Picker Event Listener
    // ------------------------------------------------------------
    function na_attachColorListener(config, onChangeCallback) {
        const colorPicker = document.getElementById(`${config.id}-color`);
        const display = document.getElementById(`${config.id}-display`);
        
        if (colorPicker) {
            colorPicker.addEventListener('input', () => {
                const value = colorPicker.value;
                if (display) display.textContent = value;
                
                if (onChangeCallback) {
                    onChangeCallback(config.id, value);
                }
            });
        }
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Attach Material Cards Event Listener
    // ------------------------------------------------------------
    function na_attachMaterialCardsListener(config, onChangeCallback) {
        const container = document.getElementById(`${config.id}-cards`);
        
        if (container) {
            const cards = container.querySelectorAll('.na-material-card');
            
            cards.forEach(card => {
                card.addEventListener('click', () => {
                    // Remove selection from all cards
                    cards.forEach(c => c.classList.remove('na-material-card-selected'));
                    
                    // Add selection to clicked card
                    card.classList.add('na-material-card-selected');
                    
                    // Get material ID (not color) and trigger callback
                    const materialId = card.dataset.materialId;
                    if (onChangeCallback) {
                        onChangeCallback(config.id, materialId);
                    }
                });
            });
        }
    }
    // ---------------------------------------------------------------
    
    // Public API
    // ------------------------------------------------------------
    return {
        na_attachEventListeners: na_attachEventListeners,
        na_attachSliderListeners: na_attachSliderListeners,
        na_attachToggleListener: na_attachToggleListener,
        na_attachColorListener: na_attachColorListener,
        na_attachMaterialCardsListener: na_attachMaterialCardsListener,
        na_attachExpandableListener: na_attachExpandableListener
    };
    
})();

// endregion ===================================================================

// =============================================================================
// REGION | Global Exports
// =============================================================================

// Export to global window object for access by other modules
// ------------------------------------------------------------
window.Na__Ui__Events = Na__Ui__Events;

console.log('[NA_UI_EVENTS] Events module loaded');

// endregion ===================================================================

// =============================================================================
// END OF FILE
// =============================================================================
