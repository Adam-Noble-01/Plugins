/* =============================================================================
   NA WINDOW CONFIGURATOR TOOL - UI CONTROLS
   =============================================================================
   
   FILE       : Na__WindowConfiguratorTool__Ui__Controls__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : HTML generation for UI controls
   CREATED    : 2026
   
   DESCRIPTION:
   - Pure HTML generation functions for UI controls
   - Slider controls with range input and number input
   - Toggle switches for boolean options
   - Color picker controls
   - Expandable panel controls with child controls
   
   NAMING CONVENTION:
   - All functions use na_ prefix (lowercase)
   - Exported to window.Na__Ui__Controls object
   
   ============================================================================= */

// =============================================================================
// REGION | UI Controls Module
// =============================================================================

const Na__Ui__Controls = (function() {
    
    // FUNCTION | Create HTML for a Control Based on Type
    // ------------------------------------------------------------
    function na_createControl(config) {
        switch (config.type) {
            case 'slider':
                return na_createSliderHtml(config);
            case 'toggle':
                return na_createToggleHtml(config);
            case 'color':
                return na_createColorHtml(config);
            case 'material_cards':
                return na_createMaterialCardsHtml(config);
            case 'expandable':
                return na_createExpandableHtml(config);
            default:
                return '';
        }
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Create Expandable Panel Control HTML
    // ------------------------------------------------------------
    function na_createExpandableHtml(config) {
        let childControlsHtml = '';
        if (config.children && config.children.length > 0) {
            config.children.forEach(childConfig => {
                childControlsHtml += na_createSliderHtml(childConfig);
            });
        }
        
        return `
            <div class="na-control-item na-expandable-wrapper" data-control-id="${config.id}">
                <div class="na-expandable-header" id="${config.id}-header" data-expanded="false">
                    <span class="na-expandable-title">${config.label}</span>
                    <div class="na-expandable-arrow"></div>
                </div>
                <div class="na-expandable-content" id="${config.id}-content">
                    ${childControlsHtml}
                </div>
            </div>
        `;
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Create Slider Control HTML
    // ------------------------------------------------------------
    function na_createSliderHtml(config) {
        return `
            <div class="na-control-item" data-control-id="${config.id}">
                <div class="na-control-label">
                    <span>${config.label}</span>
                    <span class="na-control-value" id="${config.id}-display">${config.default}${config.unit}</span>
                </div>
                <div class="na-slider-container">
                    <input type="range" 
                           class="na-slider" 
                           id="${config.id}-slider"
                           min="${config.min}" 
                           max="${config.max}" 
                           step="${config.step}"
                           value="${config.default}">
                    <input type="number" 
                           class="na-slider-input" 
                           id="${config.id}-input"
                           min="${config.min}" 
                           max="${config.max}" 
                           step="${config.step}"
                           value="${config.default}">
                </div>
            </div>
        `;
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Create Toggle Control HTML
    // ------------------------------------------------------------
    function na_createToggleHtml(config) {
        const activeClass = config.default ? 'na-active' : '';
        return `
            <div class="na-control-item" data-control-id="${config.id}">
                <div class="na-toggle-container">
                    <span class="na-control-label">${config.label}</span>
                    <div class="na-toggle ${activeClass}" id="${config.id}-toggle" data-value="${config.default}">
                        <div class="na-toggle-knob"></div>
                    </div>
                </div>
            </div>
        `;
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Create Color Picker Control HTML
    // ------------------------------------------------------------
    function na_createColorHtml(config) {
        return `
            <div class="na-control-item" data-control-id="${config.id}">
                <div class="na-control-label">
                    <span>${config.label}</span>
                </div>
                <div class="na-color-container">
                    <input type="color" 
                           class="na-color-picker" 
                           id="${config.id}-color"
                           value="${config.default}">
                    <span class="na-color-value" id="${config.id}-display">${config.default}</span>
                </div>
            </div>
        `;
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Create Material Cards Control HTML
    // ------------------------------------------------------------
    function na_createMaterialCardsHtml(config) {
        const cardsHtml = config.materials.map(material => {
            const isSelected = material.id === config.default;
            const selectedClass = isSelected ? 'na-material-card-selected' : '';
            return `
                <div class="na-material-card ${selectedClass}" 
                     data-material-id="${material.id}"
                     data-color="${material.color}"
                     title="${material.name}">
                    <div class="na-material-swatch" style="background-color: ${material.color};"></div>
                    <div class="na-material-name">${material.name}</div>
                </div>
            `;
        }).join('');
        
        return `
            <div class="na-control-item" data-control-id="${config.id}">
                <div class="na-control-label">
                    <span>${config.label}</span>
                </div>
                <div class="na-material-cards-container" id="${config.id}-cards">
                    ${cardsHtml}
                </div>
            </div>
        `;
    }
    // ---------------------------------------------------------------
    
    // Public API
    // ------------------------------------------------------------
    return {
        na_createControl: na_createControl,
        na_createSliderHtml: na_createSliderHtml,
        na_createToggleHtml: na_createToggleHtml,
        na_createColorHtml: na_createColorHtml,
        na_createMaterialCardsHtml: na_createMaterialCardsHtml,
        na_createExpandableHtml: na_createExpandableHtml
    };
    
})();

// endregion ===================================================================

// =============================================================================
// REGION | Global Exports
// =============================================================================

// Export to global window object for access by other modules
// ------------------------------------------------------------
window.Na__Ui__Controls = Na__Ui__Controls;

console.log('[NA_UI_CONTROLS] Controls module loaded');

// endregion ===================================================================

// =============================================================================
// END OF FILE
// =============================================================================
