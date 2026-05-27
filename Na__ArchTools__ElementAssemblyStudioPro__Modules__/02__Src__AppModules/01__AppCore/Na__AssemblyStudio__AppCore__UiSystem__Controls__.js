/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - SHARED UI CONTROLS
   =============================================================================
   FILE       : Na__AssemblyStudio__AppCore__UiSystem__Controls__.js
   NAMESPACE  : window.Na__Ui__Controls (lifted from WindowSystem so all
                systems can share one descriptor-control engine)
   AUTHOR     : Noble Architecture
   PURPOSE    : Pure HTML generation for descriptor-driven UI controls.
                Slider, toggle, color picker, material cards and expandable
                panels. Every system (Windows, Doors, Settings) consumes
                the same engine via window.Na__Ui__Controls.na_createControl.

   REFACTOR NOTES (v2 / EASP)
   - InteriorDoorSystem previously had its own na_build_slider_control etc.
     It now consumes this shared engine.
   ============================================================================= */

const Na__Ui__Controls = (function () {

    function na_createControl(config) {
        switch (config.type) {
            case 'slider':         return na_createSliderHtml(config);
            case 'toggle':         return na_createToggleHtml(config);
            case 'binary_toggle':  return na_createBinaryToggleHtml(config);
            case 'select':         return na_createSelectHtml(config);
            case 'color':          return na_createColorHtml(config);
            case 'material_cards': return na_createMaterialCardsHtml(config);
            case 'expandable':     return na_createExpandableHtml(config);
            default:               return '';
        }
    }

    function na_createExpandableHtml(config) {
        let childControlsHtml = '';
        if (config.children && config.children.length > 0) {
            // Dispatch on child.type so expandable sections can host sliders,
            // toggles, etc. (e.g. Advanced Glazebar Controls hosts both).
            config.children.forEach(child => {
                childControlsHtml += na_createControl(child);
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

    function na_createSliderHtml(config) {
        return `
            <div class="na-control-item" data-control-id="${config.id}">
                <div class="na-control-label">
                    <span>${config.label}</span>
                    <span class="na-control-value" id="${config.id}-display">${config.default}${config.unit}</span>
                </div>
                <div class="na-slider-container">
                    <input type="range" class="na-slider" id="${config.id}-slider"
                           min="${config.min}" max="${config.max}" step="${config.step}" value="${config.default}">
                    <input type="number" class="na-slider-input" id="${config.id}-input"
                           min="${config.min}" max="${config.max}" step="${config.step}" value="${config.default}">
                </div>
            </div>
        `;
    }

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

    // Select: native <select> dropdown rendered by an HTML string.
    // descriptor shape:
    //   {
    //     id      : string,
    //     label   : string,
    //     type    : 'select',
    //     default : <one of options[].value>,
    //     options : [ { value, label }, ... ]
    //   }
    // DOM matches the imperative builder used by the Interior Door tab so
    // the existing CSS (.na-select) works unchanged.
    function na_createSelectHtml(config) {
        const options = Array.isArray(config.options) ? config.options : [];
        const opts = options.map(function (opt) {
            const isSelected = (opt.value === config.default) ? ' selected' : '';
            return '<option value="' + opt.value + '"' + isSelected + '>' + opt.label + '</option>';
        }).join('');
        return `
            <div class="na-control-item" data-control-id="${config.id}">
                <div class="na-control-label"><span>${config.label}</span></div>
                <select class="na-select" id="${config.id}-select">${opts}</select>
            </div>
        `;
    }

    // Binary toggle: two-option inline switch (e.g. Left | Right, Inward | Outward).
    // descriptor shape:
    //   {
    //     id      : string,
    //     label   : string,
    //     type    : 'binary_toggle',
    //     default : <one of options[].value>,
    //     options : [ { value, label }, { value, label } ]   // exactly 2 entries
    //   }
    // DOM matches the imperative builder used by the Interior Door tab so the
    // existing CSS (.na-binary-toggle, .na-binary-toggle__track, etc.) works
    // unchanged.
    function na_createBinaryToggleHtml(config) {
        const options       = Array.isArray(config.options) ? config.options : [];
        const leftOpt       = options[0] || { value: '', label: '' };
        const rightOpt      = options[1] || { value: '', label: '' };
        const isRight       = (config.default === rightOpt.value);
        const sideClass     = isRight ? 'na-binary-toggle--right' : 'na-binary-toggle--left';
        return `
            <div class="na-control-item" data-control-id="${config.id}">
                <div class="na-toggle-container">
                    <span class="na-control-label">${config.label}</span>
                    <div class="na-binary-toggle ${sideClass}" id="${config.id}-btoggle" data-value="${config.default}"
                         data-left-value="${leftOpt.value}" data-right-value="${rightOpt.value}">
                        <span class="na-binary-toggle__option na-binary-toggle__option--left">${leftOpt.label}</span>
                        <div class="na-binary-toggle__track"><div class="na-binary-toggle__thumb"></div></div>
                        <span class="na-binary-toggle__option na-binary-toggle__option--right">${rightOpt.label}</span>
                    </div>
                </div>
            </div>
        `;
    }

    function na_createColorHtml(config) {
        return `
            <div class="na-control-item" data-control-id="${config.id}">
                <div class="na-control-label"><span>${config.label}</span></div>
                <div class="na-color-container">
                    <input type="color" class="na-color-picker" id="${config.id}-color" value="${config.default}">
                    <span class="na-color-value" id="${config.id}-display">${config.default}</span>
                </div>
            </div>
        `;
    }

    // Resolve the swatch list for a material_cards control:
    //   1. If config.materialsSource is set, look up that name on window.
    //      Returns [] if missing - the caller can then hide the section.
    //   2. Otherwise fall back to the inline config.materials array.
    function na_resolveMaterials(config) {
        if (typeof config.materialsSource === 'string' && config.materialsSource.length > 0) {
            const live = window[config.materialsSource];
            return Array.isArray(live) ? live : [];
        }
        return Array.isArray(config.materials) ? config.materials : [];
    }

    // Normalise to the legacy {id, name, color} shape so the markup stays
    // backward compatible. The Ruby push uses {id, label, hex}.
    function na_normaliseSwatch(material) {
        return {
            id    : material.id,
            name  : material.name  || material.label || material.id,
            color : material.color || material.hex   || '#FFFFFF'
        };
    }

    function na_createMaterialCardsHtml(config) {
        const swatches = na_resolveMaterials(config).map(na_normaliseSwatch);
        if (swatches.length === 0) {
            // No live data yet -- emit a placeholder container so a later
            // re-render (after Ruby pushes swatches) can populate it.
            return `
                <div class="na-control-item na-material-cards-empty" data-control-id="${config.id}" style="display:none;">
                    <div class="na-control-label"><span>${config.label}</span></div>
                    <div class="na-material-cards-container" id="${config.id}-cards"></div>
                </div>
            `;
        }
        const cardsHtml = swatches.map(material => {
            const isSelected    = material.id === config.default;
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
                <div class="na-control-label"><span>${config.label}</span></div>
                <div class="na-material-cards-container" id="${config.id}-cards">
                    ${cardsHtml}
                </div>
            </div>
        `;
    }

    return {
        na_createControl:           na_createControl,
        na_createSliderHtml:        na_createSliderHtml,
        na_createToggleHtml:        na_createToggleHtml,
        na_createBinaryToggleHtml:  na_createBinaryToggleHtml,
        na_createSelectHtml:        na_createSelectHtml,
        na_createColorHtml:         na_createColorHtml,
        na_createMaterialCardsHtml: na_createMaterialCardsHtml,
        na_createExpandableHtml:    na_createExpandableHtml
    };
})();

window.Na__Ui__Controls = Na__Ui__Controls;
console.log('[NA_UI_CONTROLS] Shared controls module loaded');
