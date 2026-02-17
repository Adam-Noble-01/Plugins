/* =============================================================================
   NA WINDOW CONFIGURATOR TOOL - UI LOGIC
   =============================================================================
   
   FILE       : Na__WindowConfiguratorTool__UiLogic__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Dynamic UI generation and Custom SVG 2D viewport
   CREATED    : 2026
   
   DESCRIPTION:
   - Custom SVG generator (no Maker.js dependency)
   - Live preview that validates before sending to SketchUp
   - Data only passes to SketchUp when SVG preview is valid
   
   NAMING CONVENTION:
   - All custom identifiers use Na_ or na_ prefix
   
   ============================================================================= */

// =============================================================================
// REGION | Configuration Constants
// =============================================================================

// CONSTANTS | Primary UI Control Configuration
// ------------------------------------------------------------
const NA_UI_CONFIG = [
    {
        id: 'width_mm',
        label: 'Width',
        unit: 'mm',
        type: 'slider',
        min: 300,
        max: 4000,
        step: 10,
        default: 900
    },
    {
        id: 'height_mm',
        label: 'Height',
        unit: 'mm',
        type: 'slider',
        min: 300,
        max: 2500,
        step: 10,
        default: 1200
    },
    {
        id: 'frame_thickness_mm',
        label: 'Frame Thickness',
        unit: 'mm',
        type: 'slider',
        min: 30,
        max: 120,
        step: 5,
        default: 50
    },
    {
        id: 'casement_width_mm',
        label: 'Casement Width',
        unit: 'mm',
        type: 'slider',
        min: 20,
        max: 250,
        step: 5,
        default: 65
    },
    {
        id: 'casement_sizes_individual',
        label: 'Individual Casement Sizes',
        type: 'expandable',
        default: false,
        children: [
            {
                id: 'casement_top_rail_mm',
                label: 'Top Rail',
                unit: 'mm',
                type: 'slider',
                min: 20,
                max: 250,
                step: 5,
                default: 65
            },
            {
                id: 'casement_bottom_rail_mm',
                label: 'Bottom Rail',
                unit: 'mm',
                type: 'slider',
                min: 20,
                max: 350,
                step: 5,
                default: 65
            },
            {
                id: 'casement_left_stile_mm',
                label: 'Left Stile',
                unit: 'mm',
                type: 'slider',
                min: 20,
                max: 250,
                step: 5,
                default: 65
            },
            {
                id: 'casement_right_stile_mm',
                label: 'Right Stile',
                unit: 'mm',
                type: 'slider',
                min: 20,
                max: 250,
                step: 5,
                default: 65
            }
        ]
    },
    {
        id: 'mullions',
        label: 'Mullions',
        unit: '',
        type: 'slider',
        min: 0,
        max: 6,
        step: 1,
        default: 0
    },
    {
        id: 'mullion_width_mm',
        label: 'Mullion Width',
        unit: 'mm',
        type: 'slider',
        min: 30,
        max: 120,
        step: 5,
        default: 40
    }
];

// CONSTANTS | Glaze Bars Configuration
// ------------------------------------------------------------
const NA_GLAZEBAR_CONFIG = [
    {
        id: 'horizontal_glaze_bars',
        label: 'Horizontal Bars',
        unit: '',
        type: 'slider',
        min: 0,
        max: 6,
        step: 1,
        default: 0
    },
    {
        id: 'vertical_glaze_bars',
        label: 'Vertical Bars',
        unit: '',
        type: 'slider',
        min: 0,
        max: 6,
        step: 1,
        default: 0
    },
    {
        id: 'glaze_bar_width_mm',
        label: 'Bar Width',
        unit: 'mm',
        type: 'slider',
        min: 15,
        max: 60,
        step: 5,
        default: 25
    }
];

// CONSTANTS | Options Configuration
// ------------------------------------------------------------
const NA_OPTIONS_CONFIG = [
    {
        id: 'show_casements',
        label: 'Show Casements',
        type: 'toggle',
        default: true
    },
    {
        id: 'twin_casements',
        label: 'Twin Casements',
        type: 'toggle',
        default: false
    },
    {
        id: 'has_cill',
        label: 'Include Cill',
        type: 'toggle',
        default: true
    },
    {
        id: 'show_dimensions',
        label: 'Show Dimensions',
        type: 'toggle',
        default: true
    },
    {
        id: 'frame_color',
        label: 'Frame Color',
        type: 'color',
        default: '#D2B48C'
    }
];

// endregion ===================================================================

// =============================================================================
// REGION | Dynamic UI Module
// =============================================================================

const Na_DynamicUI = (function() {
    
    // Module Variables
    // ------------------------------------------------------------
    let _config = {};                                                // Current configuration state
    let _updateCallback = null;                                      // External update callback function
    let _svgValid = false;                                           // SVG preview validation state
    
    // FUNCTION | Initialize the Dynamic UI
    // ------------------------------------------------------------
    function na_init() {
        console.log('[NA_UI] Initializing Dynamic UI');
        
        // Build primary controls
        na_buildControls('na-controls-primary', NA_UI_CONFIG);
        
        // Build glaze bar controls
        na_buildControls('na-controls-glazebars', NA_GLAZEBAR_CONFIG);
        
        // Build options controls
        na_buildControls('na-controls-options', NA_OPTIONS_CONFIG);
        
        // Set default values
        na_setDefaults();
        
        // Initial render
        na_onConfigChange();
        
        console.log('[NA_UI] Dynamic UI initialized');
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Build Controls for a Container
    // ------------------------------------------------------------
    function na_buildControls(containerId, configArray) {
        const container = document.getElementById(containerId);
        if (!container) {
            console.error('[NA_UI] Container not found:', containerId);
            return;
        }
        
        container.innerHTML = '';
        
        configArray.forEach(config => {
            const controlHtml = na_createControl(config);
            container.insertAdjacentHTML('beforeend', controlHtml);
        });
        
        // Attach event listeners
        configArray.forEach(config => {
            na_attachEventListeners(config);
        });
    }
    // ---------------------------------------------------------------
    
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
    
    // FUNCTION | Attach Event Listeners to a Control
    // ------------------------------------------------------------
    function na_attachEventListeners(config) {
        switch (config.type) {
            case 'slider':
                na_attachSliderListeners(config);
                break;
            case 'toggle':
                na_attachToggleListener(config);
                break;
            case 'color':
                na_attachColorListener(config);
                break;
            case 'expandable':
                na_attachExpandableListener(config);
                break;
        }
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Attach Expandable Panel Event Listener
    // ------------------------------------------------------------
    function na_attachExpandableListener(config) {
        const header = document.getElementById(`${config.id}-header`);
        const content = document.getElementById(`${config.id}-content`);
        
        if (header && content) {
            header.addEventListener('click', () => {
                const isExpanded = header.dataset.expanded === 'true';
                const newState = !isExpanded;
                
                header.dataset.expanded = newState;
                header.classList.toggle('na-expanded', newState);
                content.classList.toggle('na-expanded', newState);
                
                _config[config.id] = newState;
                na_onConfigChange();
            });
        }
        
        // Attach listeners to child controls
        if (config.children && config.children.length > 0) {
            config.children.forEach(childConfig => {
                na_attachSliderListeners(childConfig);
            });
        }
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Attach Slider Event Listeners
    // ------------------------------------------------------------
    function na_attachSliderListeners(config) {
        const slider = document.getElementById(`${config.id}-slider`);
        const input = document.getElementById(`${config.id}-input`);
        const display = document.getElementById(`${config.id}-display`);
        
        if (slider) {
            slider.addEventListener('input', () => {
                const value = parseFloat(slider.value);
                if (input) input.value = value;
                if (display) display.textContent = `${value}${config.unit}`;
                _config[config.id] = value;
                na_onConfigChange();
            });
        }
        
        if (input) {
            input.addEventListener('change', () => {
                let value = parseFloat(input.value);
                value = Math.max(config.min, Math.min(config.max, value));
                input.value = value;
                if (slider) slider.value = value;
                if (display) display.textContent = `${value}${config.unit}`;
                _config[config.id] = value;
                na_onConfigChange();
            });
        }
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Attach Toggle Event Listener
    // ------------------------------------------------------------
    function na_attachToggleListener(config) {
        const toggle = document.getElementById(`${config.id}-toggle`);
        
        if (toggle) {
            toggle.addEventListener('click', () => {
                const currentValue = toggle.dataset.value === 'true';
                const newValue = !currentValue;
                toggle.dataset.value = newValue;
                toggle.classList.toggle('na-active', newValue);
                _config[config.id] = newValue;
                na_onConfigChange();
            });
        }
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Attach Color Picker Event Listener
    // ------------------------------------------------------------
    function na_attachColorListener(config) {
        const colorPicker = document.getElementById(`${config.id}-color`);
        const display = document.getElementById(`${config.id}-display`);
        
        if (colorPicker) {
            colorPicker.addEventListener('input', () => {
                const value = colorPicker.value;
                if (display) display.textContent = value;
                _config[config.id] = value;
                na_onConfigChange();
            });
        }
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Set Default Values
    // ------------------------------------------------------------
    function na_setDefaults() {
        [...NA_UI_CONFIG, ...NA_GLAZEBAR_CONFIG, ...NA_OPTIONS_CONFIG].forEach(config => {
            _config[config.id] = config.default;
            
            // Handle expandable controls with children
            if (config.type === 'expandable' && config.children) {
                config.children.forEach(childConfig => {
                    _config[childConfig.id] = childConfig.default;
                });
            }
        });
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Called When Any Config Value Changes
    // ------------------------------------------------------------
    function na_onConfigChange() {
        // Update 2D viewport and validate
        _svgValid = Na_Viewport.na_render(_config);
        
        // Update button states based on SVG validity
        na_updateButtonStates();
        
        // Call external callback if set
        if (_updateCallback) {
            _updateCallback(_config);
        }
        
        // Send live update to SketchUp if Live Mode is enabled
        if (typeof na_sendLiveUpdate === 'function') {
            na_sendLiveUpdate();
        }
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Update Button States Based on SVG Validity
    // ------------------------------------------------------------
    function na_updateButtonStates() {
        const createBtn = document.getElementById('na-btn-create');
        const updateBtn = document.getElementById('na-btn-update');
        
        if (createBtn) {
            if (_svgValid) {
                createBtn.disabled = false;
                createBtn.classList.remove('na-btn-disabled');
            } else {
                createBtn.disabled = true;
                createBtn.classList.add('na-btn-disabled');
            }
        }
        
        if (updateBtn) {
            if (_svgValid) {
                updateBtn.disabled = false;
                updateBtn.classList.remove('na-btn-disabled');
            } else {
                updateBtn.disabled = true;
                updateBtn.classList.add('na-btn-disabled');
            }
        }
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Check if SVG Preview is Valid
    // ------------------------------------------------------------
    function na_isSvgValid() {
        return _svgValid;
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Get Current Configuration
    // ------------------------------------------------------------
    function na_getConfig() {
        return { ..._config };
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Set Configuration
    // ------------------------------------------------------------
    function na_setConfig(newConfig) {
        _config = { ..._config, ...newConfig };
        
        // Update all UI controls
        Object.keys(newConfig).forEach(key => {
            na_updateControlValue(key, newConfig[key]);
        });
        
        // Trigger render
        na_onConfigChange();
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Update a Single Control's Displayed Value
    // ------------------------------------------------------------
    function na_updateControlValue(id, value) {
        // Try slider
        const slider = document.getElementById(`${id}-slider`);
        const input = document.getElementById(`${id}-input`);
        const display = document.getElementById(`${id}-display`);
        
        if (slider) {
            slider.value = value;
            if (input) input.value = value;
            
            // Find config in main arrays or in expandable children
            let config = [...NA_UI_CONFIG, ...NA_GLAZEBAR_CONFIG].find(c => c.id === id);
            if (!config) {
                // Search in expandable children
                for (const parentConfig of NA_UI_CONFIG) {
                    if (parentConfig.type === 'expandable' && parentConfig.children) {
                        config = parentConfig.children.find(c => c.id === id);
                        if (config) break;
                    }
                }
            }
            if (display && config) {
                display.textContent = `${value}${config.unit}`;
            }
            return;
        }
        
        // Try toggle
        const toggle = document.getElementById(`${id}-toggle`);
        if (toggle) {
            toggle.dataset.value = value;
            toggle.classList.toggle('na-active', value);
            return;
        }
        
        // Try color
        const colorPicker = document.getElementById(`${id}-color`);
        if (colorPicker) {
            colorPicker.value = value;
            if (display) display.textContent = value;
            return;
        }
        
        // Try expandable header (for expanded state)
        const expandableHeader = document.getElementById(`${id}-header`);
        const expandableContent = document.getElementById(`${id}-content`);
        if (expandableHeader && expandableContent) {
            expandableHeader.dataset.expanded = value;
            expandableHeader.classList.toggle('na-expanded', value);
            expandableContent.classList.toggle('na-expanded', value);
            return;
        }
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Set Update Callback
    // ------------------------------------------------------------
    function na_setUpdateCallback(callback) {
        _updateCallback = callback;
    }
    // ---------------------------------------------------------------
    
    // Public API
    // ------------------------------------------------------------
    return {
        na_init: na_init,
        na_getConfig: na_getConfig,
        na_setConfig: na_setConfig,
        na_setUpdateCallback: na_setUpdateCallback,
        na_isSvgValid: na_isSvgValid
    };
    
})();

// endregion ===================================================================

// =============================================================================
// REGION | Custom SVG Viewport Module (No Maker.js dependency)
// =============================================================================

const Na_Viewport = (function() {
    
    // Module Variables
    // ------------------------------------------------------------
    let _svgElement = null;                                          // SVG DOM element reference
    let _viewBox = { x: -50, y: -50, width: 500, height: 400 };     // Current viewBox state
    let _isPanning = false;                                          // Pan interaction state
    let _lastMousePos = { x: 0, y: 0 };                             // Last mouse position for panning
    let _scale = 1;                                                  // Current zoom scale
    let _lastValidSvg = '';                                          // Last successfully generated SVG content
    
    // FUNCTION | Initialize the Viewport
    // ------------------------------------------------------------
    function na_init() {
        console.log('[NA_VIEWPORT] Initializing custom SVG viewport');
        
        _svgElement = document.getElementById('na-viewport-svg');
        if (!_svgElement) {
            console.error('[NA_VIEWPORT] SVG element not found');
            return;
        }
        
        // Setup pan/zoom handlers
        na_setupPanZoom();
        
        console.log('[NA_VIEWPORT] Viewport initialized');
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Setup Pan and Zoom Event Handlers
    // ------------------------------------------------------------
    function na_setupPanZoom() {
        const wrapper = document.getElementById('na-canvas-wrapper');
        if (!wrapper) return;
        
        // Mouse wheel zoom
        wrapper.addEventListener('wheel', (e) => {
            e.preventDefault();
            const zoomFactor = e.deltaY > 0 ? 1.1 : 0.9;
            _scale *= zoomFactor;
            _scale = Math.max(0.1, Math.min(10, _scale));
            
            _viewBox.width *= zoomFactor;
            _viewBox.height *= zoomFactor;
            
            na_updateViewBox();
        });
        
        // Pan start
        wrapper.addEventListener('mousedown', (e) => {
            _isPanning = true;
            _lastMousePos = { x: e.clientX, y: e.clientY };
            wrapper.style.cursor = 'grabbing';
        });
        
        // Pan move
        wrapper.addEventListener('mousemove', (e) => {
            if (!_isPanning) return;
            
            const dx = (e.clientX - _lastMousePos.x) * _scale;
            const dy = (e.clientY - _lastMousePos.y) * _scale;
            
            _viewBox.x -= dx;
            _viewBox.y -= dy;
            
            _lastMousePos = { x: e.clientX, y: e.clientY };
            na_updateViewBox();
        });
        
        // Pan end
        wrapper.addEventListener('mouseup', () => {
            _isPanning = false;
            wrapper.style.cursor = 'grab';
        });
        
        wrapper.addEventListener('mouseleave', () => {
            _isPanning = false;
            wrapper.style.cursor = 'grab';
        });
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Update SVG viewBox
    // ------------------------------------------------------------
    function na_updateViewBox() {
        if (_svgElement) {
            _svgElement.setAttribute('viewBox', 
                `${_viewBox.x} ${_viewBox.y} ${_viewBox.width} ${_viewBox.height}`);
        }
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Reset View to Fit Window
    // ------------------------------------------------------------
    function na_resetView() {
        const config = Na_DynamicUI.na_getConfig();
        const padding = 200;  // Extra padding to accommodate dimension annotations
        
        _viewBox = {
            x: -padding,
            y: -(config.height_mm || 1200) - padding,
            width: (config.width_mm || 900) + (padding * 2),
            height: (config.height_mm || 1200) + (padding * 2)
        };
        _scale = 1;
        
        na_updateViewBox();
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Render the Window Model Using Custom SVG Generation
    // ------------------------------------------------------------
    // @returns {boolean} True if SVG was generated successfully
    function na_render(config) {
        if (!_svgElement) {
            console.error('[NA_VIEWPORT] No SVG element');
            return false;
        }
        
        console.log('[NA_VIEWPORT] Rendering window preview');
        
        try {
            // Validate config
            const validation = na_validateConfig(config);
            if (!validation.valid) {
                console.warn('[NA_VIEWPORT] Invalid config:', validation.errors);
                na_showValidationError(validation.errors);
                return false;
            }
            
            // Generate SVG content
            const svgContent = na_generateWindowSvg(config);
            
            if (!svgContent) {
                console.error('[NA_VIEWPORT] Failed to generate SVG');
                return false;
            }
            
            // Update SVG element
            _svgElement.innerHTML = svgContent;
            _lastValidSvg = svgContent;
            
            // Reset view to fit new content
            na_resetView();
            
            // Show success indicator
            na_showValidationSuccess();
            
            console.log('[NA_VIEWPORT] SVG rendered successfully');
            return true;
            
        } catch (e) {
            console.error('[NA_VIEWPORT] Error rendering:', e);
            na_showValidationError(['Render error: ' + e.message]);
            return false;
        }
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Validate Configuration Values
    // ------------------------------------------------------------
    function na_validateConfig(config) {
        const errors = [];
        
        // Check required values
        const width = config.width_mm || 0;
        const height = config.height_mm || 0;
        const frameThickness = config.frame_thickness_mm || 0;
        const casementWidth = config.casement_width_mm || 65;
        const showCasements = config.show_casements !== false;
        const twinCasements = config.twin_casements === true;
        const numMullions = config.mullions || 0;
        const mullionWidth = config.mullion_width_mm || 40;
        
        // Individual casement sizes
        const useIndividualSizes = config.casement_sizes_individual === true;
        const casTopRail = useIndividualSizes ? (config.casement_top_rail_mm || casementWidth) : casementWidth;
        const casBottomRail = useIndividualSizes ? (config.casement_bottom_rail_mm || casementWidth) : casementWidth;
        const casLeftStile = useIndividualSizes ? (config.casement_left_stile_mm || casementWidth) : casementWidth;
        const casRightStile = useIndividualSizes ? (config.casement_right_stile_mm || casementWidth) : casementWidth;
        
        if (width < 200) errors.push('Width must be at least 200mm');
        if (height < 200) errors.push('Height must be at least 200mm');
        if (frameThickness < 20) errors.push('Frame thickness must be at least 20mm');
        
        // Calculate opening dimensions
        const numOpenings = numMullions + 1;
        const innerWidth = width - (2 * frameThickness);
        const innerHeight = height - (2 * frameThickness);
        const totalMullionWidth = numMullions * mullionWidth;
        const availableWidth = innerWidth - totalMullionWidth;
        let openingWidth = availableWidth / numOpenings;
        
        // For twin casements, each casement is half the opening width
        const casementUnitWidth = twinCasements ? (openingWidth / 2) : openingWidth;
        
        // Check that frame and mullions don't exceed window size
        const minCasementWidth = showCasements ? (casLeftStile + casRightStile) + 50 : 50;
        if (casementUnitWidth < minCasementWidth) {
            errors.push('Opening too narrow - reduce mullions or increase width');
        }
        
        // Check inner height
        const minInnerHeight = showCasements ? (casTopRail + casBottomRail) + 50 : 50;
        if (innerHeight < minInnerHeight) {
            errors.push('Window too short for frame and casement');
        }
        
        return {
            valid: errors.length === 0,
            errors: errors
        };
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Generate SVG Content for Window with Mullions and Optional Casements
    // ------------------------------------------------------------
    function na_generateWindowSvg(config) {
        const width = config.width_mm || 900;
        const height = config.height_mm || 1200;
        const frameThickness = config.frame_thickness_mm || 50;
        const casementWidth = config.casement_width_mm || 65;
        const showCasements = config.show_casements !== false;
        const twinCasements = config.twin_casements === true;
        const numMullions = config.mullions || 0;
        const mullionWidth = config.mullion_width_mm || 40;
        const hBars = config.horizontal_glaze_bars || 0;
        const vBars = config.vertical_glaze_bars || 0;
        const barWidth = config.glaze_bar_width_mm || 25;
        const frameColor = config.frame_color || '#D2B48C';
        const showDimensions = config.show_dimensions !== false;
        const hasCill = config.has_cill !== false;
        
        // Individual casement sizes (used when expanded panel is open)
        const useIndividualSizes = config.casement_sizes_individual === true;
        const casTopRail = useIndividualSizes ? (config.casement_top_rail_mm || casementWidth) : casementWidth;
        const casBottomRail = useIndividualSizes ? (config.casement_bottom_rail_mm || casementWidth) : casementWidth;
        const casLeftStile = useIndividualSizes ? (config.casement_left_stile_mm || casementWidth) : casementWidth;
        const casRightStile = useIndividualSizes ? (config.casement_right_stile_mm || casementWidth) : casementWidth;
        
        let svg = '';
        
        // Calculate openings
        const numOpenings = numMullions + 1;
        const innerWidth = width - (2 * frameThickness);
        const innerHeight = height - (2 * frameThickness);
        const totalMullionWidth = numMullions * mullionWidth;
        const availableWidth = innerWidth - totalMullionWidth;
        const openingWidth = availableWidth / numOpenings;
        
        // Outer frame (4 rectangles) - JOINERY CONVENTION: Stiles full height, rails inset
        svg += na_svgRect(0, 0, frameThickness, height, frameColor, '#000', 1); // Left stile (full height)
        svg += na_svgRect(width - frameThickness, 0, frameThickness, height, frameColor, '#000', 1); // Right stile (full height)
        svg += na_svgRect(frameThickness, 0, innerWidth, frameThickness, frameColor, '#000', 1); // Bottom rail (inset)
        svg += na_svgRect(frameThickness, height - frameThickness, innerWidth, frameThickness, frameColor, '#000', 1); // Top rail (inset)
        
        // Draw mullions
        for (let m = 1; m <= numMullions; m++) {
            const mullionX = frameThickness + (m * openingWidth) + ((m - 1) * mullionWidth);
            svg += na_svgRect(mullionX, frameThickness, mullionWidth, innerHeight, frameColor, '#000', 1);
        }
        
        // Draw each opening with casement (if enabled), glass, and glaze bars
        for (let i = 0; i < numOpenings; i++) {
            const openingX = frameThickness + (i * (openingWidth + mullionWidth));
            const openingY = frameThickness;
            
            if (showCasements) {
                if (twinCasements) {
                    // TWIN CASEMENTS: Two casements per opening, meeting at center
                    const halfWidth = openingWidth / 2;
                    
                    // Left casement of the pair
                    svg += na_generateSingleCasementSvg(
                        openingX, openingY, halfWidth, innerHeight,
                        casTopRail, casBottomRail, casLeftStile, casRightStile,
                        frameColor, hBars, vBars, barWidth
                    );
                    
                    // Right casement of the pair
                    svg += na_generateSingleCasementSvg(
                        openingX + halfWidth, openingY, halfWidth, innerHeight,
                        casTopRail, casBottomRail, casLeftStile, casRightStile,
                        frameColor, hBars, vBars, barWidth
                    );
                } else {
                    // SINGLE CASEMENT: One casement per opening
                    svg += na_generateSingleCasementSvg(
                        openingX, openingY, openingWidth, innerHeight,
                        casTopRail, casBottomRail, casLeftStile, casRightStile,
                        frameColor, hBars, vBars, barWidth
                    );
                }
            } else {
                // Direct glazed - glass sits directly in opening
                const glassX = openingX;
                const glassY = openingY;
                let glassWidth, glassHeight;
                
                if (twinCasements) {
                    // Even without casements showing, twin mode splits glass
                    const halfWidth = openingWidth / 2;
                    glassWidth = halfWidth;
                    glassHeight = innerHeight;
                    
                    // Two glass panes
                    svg += na_svgRect(glassX, glassY, glassWidth, glassHeight, 'rgba(135, 206, 235, 0.3)', '#87CEEB', 0.5);
                    svg += na_svgRect(glassX + halfWidth, glassY, glassWidth, glassHeight, 'rgba(135, 206, 235, 0.3)', '#87CEEB', 0.5);
                } else {
                    glassWidth = openingWidth;
                    glassHeight = innerHeight;
                    svg += na_svgRect(glassX, glassY, glassWidth, glassHeight, 'rgba(135, 206, 235, 0.3)', '#87CEEB', 0.5);
                }
            }
        }
        
        // Cill
        if (hasCill) {
            const cillDepth = config.cill_depth_mm || 50;
            const cillHeight = config.cill_height_mm || 30;
            svg += na_svgRect(0, -cillHeight, width, cillHeight, '#A0908A', '#000', 1);
        }
        
        // Dimensions
        if (showDimensions) {
            svg += na_svgDimensions(width, height);
        }
        
        return svg;
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Generate SVG for a Single Casement with Individual Sizes
    // ------------------------------------------------------------
    function na_generateSingleCasementSvg(x, y, width, height, topRail, bottomRail, leftStile, rightStile, frameColor, hBars, vBars, barWidth) {
        let svg = '';
        
        // Casement frame (4 pieces) - JOINERY CONVENTION: Stiles full height, rails inset
        // Left stile (full height)
        svg += na_svgRect(x, y, leftStile, height, frameColor, '#000', 0.5);
        // Right stile (full height)
        svg += na_svgRect(x + width - rightStile, y, rightStile, height, frameColor, '#000', 0.5);
        // Bottom rail (inset between stiles)
        svg += na_svgRect(x + leftStile, y, width - leftStile - rightStile, bottomRail, frameColor, '#000', 0.5);
        // Top rail (inset between stiles)
        svg += na_svgRect(x + leftStile, y + height - topRail, width - leftStile - rightStile, topRail, frameColor, '#000', 0.5);
        
        // Glass area inside casement
        const glassX = x + leftStile;
        const glassY = y + bottomRail;
        const glassWidth = width - leftStile - rightStile;
        const glassHeight = height - topRail - bottomRail;
        
        // Glass pane
        svg += na_svgRect(glassX, glassY, glassWidth, glassHeight, 'rgba(135, 206, 235, 0.3)', '#87CEEB', 0.5);
        
        // Horizontal glaze bars for this casement
        if (hBars > 0) {
            const sectionHeight = glassHeight / (hBars + 1);
            for (let b = 1; b <= hBars; b++) {
                const barY = glassY + (sectionHeight * b) - (barWidth / 2);
                svg += na_svgRect(glassX, barY, glassWidth, barWidth, frameColor, '#000', 0.5);
            }
        }
        
        // Vertical glaze bars for this casement
        if (vBars > 0) {
            const sectionWidth = glassWidth / (vBars + 1);
            for (let b = 1; b <= vBars; b++) {
                const barX = glassX + (sectionWidth * b) - (barWidth / 2);
                svg += na_svgRect(barX, glassY, barWidth, glassHeight, frameColor, '#000', 0.5);
            }
        }
        
        return svg;
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Generate SVG Rectangle
    // ------------------------------------------------------------
    function na_svgRect(x, y, w, h, fill, stroke, strokeWidth) {
        // Flip Y coordinate for SVG (origin at bottom-left visually)
        const svgY = -y - h;
        return `<rect x="${x}" y="${svgY}" width="${w}" height="${h}" 
                      fill="${fill}" stroke="${stroke}" stroke-width="${strokeWidth}"/>`;
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Generate Dimension Annotations
    // ------------------------------------------------------------
    function na_svgDimensions(width, height) {
        let svg = '';
        
        // Responsive font size scales with window dimensions
        const fontSize = Math.min(height) * 0.04;
        const lineWidth = 2;
        const tickSize = 15;
        const dimOffset = 100;
        const textOffset = fontSize * 0.85;
        
        // Width dimension (below window)
        svg += `<line x1="0" y1="${dimOffset}" x2="${width}" y2="${dimOffset}" stroke="#606060" stroke-width="${lineWidth}"/>`;
        svg += `<line x1="0" y1="${dimOffset - tickSize}" x2="0" y2="${dimOffset + tickSize}" stroke="#606060" stroke-width="${lineWidth}"/>`;
        svg += `<line x1="${width}" y1="${dimOffset - tickSize}" x2="${width}" y2="${dimOffset + tickSize}" stroke="#606060" stroke-width="${lineWidth}"/>`;
        svg += `<text x="${width / 2}" y="${dimOffset + textOffset}" text-anchor="middle" fill="#303030" font-size="${fontSize}" font-weight="600">${width}mm</text>`;
        
        // Height dimension (left of window)
        svg += `<line x1="${-dimOffset}" y1="${-height}" x2="${-dimOffset}" y2="0" stroke="#606060" stroke-width="${lineWidth}"/>`;
        svg += `<line x1="${-dimOffset - tickSize}" y1="${-height}" x2="${-dimOffset + tickSize}" y2="${-height}" stroke="#606060" stroke-width="${lineWidth}"/>`;
        svg += `<line x1="${-dimOffset - tickSize}" y1="0" x2="${-dimOffset + tickSize}" y2="0" stroke="#606060" stroke-width="${lineWidth}"/>`;
        svg += `<text x="${-dimOffset - textOffset}" y="${-height / 2}" text-anchor="middle" fill="#303030" font-size="${fontSize}" font-weight="600" transform="rotate(-90, ${-dimOffset - textOffset}, ${-height / 2})">${height}mm</text>`;
        
        return svg;
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Show Validation Error in Viewport
    // ------------------------------------------------------------
    function na_showValidationError(errors) {
        const statusBar = document.getElementById('na-status-bar');
        if (statusBar) {
            statusBar.classList.remove('na-hidden', 'na-status-success', 'na-status-info');
            statusBar.classList.add('na-status-error');
            document.getElementById('na-status-message').textContent = errors.join(', ');
        }
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Show Validation Success
    // ------------------------------------------------------------
    function na_showValidationSuccess() {
        const statusBar = document.getElementById('na-status-bar');
        if (statusBar) {
            statusBar.classList.add('na-hidden');
        }
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Export Current Model as DXF (Simplified)
    // ------------------------------------------------------------
    function na_exportDxf() {
        const config = Na_DynamicUI.na_getConfig();
        
        // Generate simple DXF content
        let dxf = '0\nSECTION\n2\nENTITIES\n';
        
        const width = config.width_mm || 900;
        const height = config.height_mm || 1200;
        const frameThickness = config.frame_thickness_mm || 50;
        
        // Outer frame rectangle
        dxf += na_dxfRect(0, 0, width, height);
        
        // Inner frame opening
        dxf += na_dxfRect(frameThickness, frameThickness, width - frameThickness, height - frameThickness);
        
        dxf += '0\nENDSEC\n0\nEOF\n';
        
        return dxf;
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Generate DXF Rectangle
    // ------------------------------------------------------------
    function na_dxfRect(x1, y1, x2, y2) {
        return `0\nLINE\n8\n0\n10\n${x1}\n20\n${y1}\n11\n${x2}\n21\n${y1}\n` +
               `0\nLINE\n8\n0\n10\n${x2}\n20\n${y1}\n11\n${x2}\n21\n${y2}\n` +
               `0\nLINE\n8\n0\n10\n${x2}\n20\n${y2}\n11\n${x1}\n21\n${y2}\n` +
               `0\nLINE\n8\n0\n10\n${x1}\n20\n${y2}\n11\n${x1}\n21\n${y1}\n`;
    }
    // ---------------------------------------------------------------
    
    // Public API
    // ------------------------------------------------------------
    return {
        na_init: na_init,
        na_render: na_render,
        na_resetView: na_resetView,
        na_exportDxf: na_exportDxf
    };
    
})();

// endregion ===================================================================

// =============================================================================
// REGION | Viewport Resize Functionality
// =============================================================================

// FUNCTION | Initialize Viewport Resize Handle
// ------------------------------------------------------------
// Allows user to drag and resize the 2D preview viewport
function na_initViewportResize() {
    const handle = document.getElementById('na-viewport-resize-handle');
    const wrapper = document.getElementById('na-canvas-wrapper');
    
    if (!handle || !wrapper) {
        console.warn('[NA_VIEWPORT] Resize handle or wrapper not found');
        return;
    }
    
    let isResizing = false;
    let startY = 0;
    let startHeight = 0;
    
    // Mouse down - start resizing
    handle.addEventListener('mousedown', function(e) {
        isResizing = true;
        startY = e.clientY;
        startHeight = wrapper.offsetHeight;
        document.body.style.cursor = 'ns-resize';
        e.preventDefault();
    });
    
    // Mouse move - update size
    document.addEventListener('mousemove', function(e) {
        if (!isResizing) return;
        
        const deltaY = e.clientY - startY;
        const newHeight = Math.max(100, Math.min(600, startHeight + deltaY));
        wrapper.style.height = newHeight + 'px';
    });
    
    // Mouse up - stop resizing
    document.addEventListener('mouseup', function() {
        if (isResizing) {
            isResizing = false;
            document.body.style.cursor = '';
            Na_Viewport.na_resetView();
        }
    });
    
    console.log('[NA_VIEWPORT] Resize handle initialized');
}
// ---------------------------------------------------------------

// endregion ===================================================================

// =============================================================================
// REGION | Initialization
// =============================================================================

// FUNCTION | Initialize All UI Modules When DOM is Ready
// ------------------------------------------------------------
document.addEventListener('DOMContentLoaded', function() {
    console.log('[NA_UI] ═══════════════════════════════════════════════════════');
    console.log('[NA_UI] NA WINDOW CONFIGURATOR - INITIALIZING');
    console.log('[NA_UI] ═══════════════════════════════════════════════════════');
    
    // Initialize Dynamic UI
    Na_DynamicUI.na_init();
    
    // Initialize Viewport
    Na_Viewport.na_init();
    
    // Initialize viewport resize handle
    na_initViewportResize();
    
    // Request initial config from Ruby
    if (typeof sketchup !== 'undefined') {
        sketchup.na_requestConfig();
        console.log('[NA_UI] Requested initial config from Ruby');
    } else {
        console.warn('[NA_UI] SketchUp bridge not available (browser mode)');
    }
    
    console.log('[NA_UI] Window Configurator UI initialized successfully');
    console.log('[NA_UI] ═══════════════════════════════════════════════════════');
});
// ---------------------------------------------------------------

// endregion ===================================================================

// =============================================================================
// END OF FILE
// =============================================================================
