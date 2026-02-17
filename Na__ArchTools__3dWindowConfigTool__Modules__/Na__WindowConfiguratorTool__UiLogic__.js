/* =============================================================================
   NA WINDOW CONFIGURATOR TOOL - UI LOGIC (MAIN ORCHESTRATOR)
   =============================================================================
   
   FILE       : Na__WindowConfiguratorTool__UiLogic__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Main orchestration and state management
   CREATED    : 2026
   
   DESCRIPTION:
   - Orchestrates all UI and viewport modules
   - Manages global configuration state
   - Coordinates between UI changes and viewport rendering
   - Provides public API for external access (bridge)
   - Modular architecture with separated concerns
   
   DEPENDENCIES:
   - Na__WindowConfiguratorTool__Ui__Config__.js
   - Na__WindowConfiguratorTool__Ui__Controls__.js
   - Na__WindowConfiguratorTool__Ui__Events__.js
   - Na__WindowConfiguratorTool__Viewport__Validation__.js
   - Na__WindowConfiguratorTool__Viewport__SvgGenerator__.js
   - Na__WindowConfiguratorTool__Viewport__Controls__.js
   - Na__WindowConfiguratorTool__Export__Dxf__.js
   
   NAMING CONVENTION:
   - All custom identifiers use Na_ or na_ prefix
   
   ============================================================================= */

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
        na_buildControls('na-controls-primary', window.NA_UI_CONFIG);
        
        // Build glaze bar controls
        na_buildControls('na-controls-glazebars', window.NA_GLAZEBAR_CONFIG);
        
        // Build cill & frame controls
        na_buildControls('na-controls-cill-frame', window.NA_CILL_FRAME_CONFIG);
        
        // Build options controls
        na_buildControls('na-controls-options', window.NA_OPTIONS_CONFIG);
        
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
            const controlHtml = window.Na__Ui__Controls.na_createControl(config);
            container.insertAdjacentHTML('beforeend', controlHtml);
        });
        
        // Attach event listeners with callback
        configArray.forEach(config => {
            window.Na__Ui__Events.na_attachEventListeners(config, na_onControlChange);
        });
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Set Default Values
    // ------------------------------------------------------------
    function na_setDefaults() {
        [window.NA_UI_CONFIG, window.NA_GLAZEBAR_CONFIG, window.NA_CILL_FRAME_CONFIG, window.NA_OPTIONS_CONFIG].forEach(config => {
            config.forEach(item => {
                _config[item.id] = item.default;
                
                // Handle expandable controls with children
                if (item.type === 'expandable' && item.children) {
                    item.children.forEach(childConfig => {
                        _config[childConfig.id] = childConfig.default;
                    });
                }
            });
        });
        
        // Initialize removed_casements array (tracks which openings have casements removed)
        _config.removed_casements = [];
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Called When a Control Value Changes (Callback from Events Module)
    // ------------------------------------------------------------
    function na_onControlChange(id, value) {
        _config[id] = value;
        na_onConfigChange();
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Called When Any Config Value Changes
    // ------------------------------------------------------------
    function na_onConfigChange() {
        // Clean up removed_casements: remove indices that exceed current opening count
        const numOpenings = (_config.mullions || 0) + 1;
        if (_config.removed_casements && _config.removed_casements.length > 0) {
            _config.removed_casements = _config.removed_casements.filter(idx => idx < numOpenings);
        }
        
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
    
    // FUNCTION | Toggle Casement Removal for a Specific Opening
    // ------------------------------------------------------------
    // Adds or removes an opening index from removed_casements array.
    // Called by Na_Viewport when user clicks on an opening in the SVG preview.
    // @param {number} openingIndex - The index of the opening to toggle
    function na_toggleCasementRemoval(openingIndex) {
        if (!_config.removed_casements) {
            _config.removed_casements = [];
        }
        
        const idx = _config.removed_casements.indexOf(openingIndex);
        if (idx === -1) {
            // Add to removed list
            _config.removed_casements.push(openingIndex);
            console.log(`[NA_UI] Removed casement from opening ${openingIndex}`);
        } else {
            // Remove from removed list (restore casement)
            _config.removed_casements.splice(idx, 1);
            console.log(`[NA_UI] Restored casement to opening ${openingIndex}`);
        }
        
        na_onConfigChange();
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
            let config = [window.NA_UI_CONFIG, window.NA_GLAZEBAR_CONFIG, window.NA_CILL_FRAME_CONFIG].flat().find(c => c.id === id);
            if (!config) {
                // Search in expandable children
                for (const parentConfig of window.NA_UI_CONFIG) {
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
        
        // Try color picker
        const colorPicker = document.getElementById(`${id}-color`);
        if (colorPicker) {
            colorPicker.value = value;
            if (display) display.textContent = value;
            return;
        }
        
        // Try material cards
        const cardsContainer = document.getElementById(`${id}-cards`);
        if (cardsContainer) {
            const cards = cardsContainer.querySelectorAll('.na-material-card');
            cards.forEach(card => {
                if (card.dataset.materialId === value) {
                    card.classList.add('na-material-card-selected');
                } else {
                    card.classList.remove('na-material-card-selected');
                }
            });
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
        na_isSvgValid: na_isSvgValid,
        na_toggleCasementRemoval: na_toggleCasementRemoval
    };
    
})();

// endregion ===================================================================

// =============================================================================
// REGION | Viewport Module
// =============================================================================

const Na_Viewport = (function() {
    
    // Module Variables
    // ------------------------------------------------------------
    let _svgElement = null;                                          // SVG DOM element reference
    let _viewBox = { x: -50, y: -50, width: 500, height: 400 };     // Current viewBox state
    let _interactionState = {                                        // Interaction state object
        scale: 1,
        isPanning: false,
        didPan: false,
        lastMousePos: { x: 0, y: 0 },
        panStartPos: { x: 0, y: 0 }
    };
    
    // FUNCTION | Initialize the Viewport
    // ------------------------------------------------------------
    function na_init() {
        console.log('[NA_VIEWPORT] Initializing viewport');
        
        _svgElement = document.getElementById('na-viewport-svg');
        if (!_svgElement) {
            console.error('[NA_VIEWPORT] SVG element not found');
            return;
        }
        
        // Setup pan/zoom handlers using Controls module
        window.Na__Viewport__Controls.na_setupPanZoom(
            _svgElement,
            _viewBox,
            _interactionState,
            () => window.Na__Viewport__Controls.na_updateViewBox(_svgElement, _viewBox)
        );
        
        console.log('[NA_VIEWPORT] Viewport initialized');
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Render the Window Model
    // ------------------------------------------------------------
    // @returns {boolean} True if SVG was generated successfully
    function na_render(config) {
        if (!_svgElement) {
            console.error('[NA_VIEWPORT] No SVG element');
            return false;
        }
        
        console.log('[NA_VIEWPORT] Rendering window preview');
        
        try {
            // Validate config using Validation module
            const validation = window.Na__Viewport__Validation.na_validateConfig(config);
            if (!validation.valid) {
                console.warn('[NA_VIEWPORT] Invalid config:', validation.errors);
                window.Na__Viewport__Validation.na_showValidationError(validation.errors);
                return false;
            }
            
            // Generate SVG content using SvgGenerator module
            const svgContent = window.Na__Viewport__SvgGenerator.na_generateWindowSvg(config);
            
            if (!svgContent) {
                console.error('[NA_VIEWPORT] Failed to generate SVG');
                return false;
            }
            
            // Update SVG element
            _svgElement.innerHTML = svgContent;
            
            // Setup click targets for casement toggling using Controls module
            window.Na__Viewport__Controls.na_setupCasementClickTargets(
                _svgElement,
                _interactionState,
                (openingIndex) => Na_DynamicUI.na_toggleCasementRemoval(openingIndex)
            );
            
            // Reset view to fit new content
            na_resetView();
            
            // Show success indicator
            window.Na__Viewport__Validation.na_showValidationSuccess();
            
            console.log('[NA_VIEWPORT] SVG rendered successfully');
            return true;
            
        } catch (e) {
            console.error('[NA_VIEWPORT] Error rendering:', e);
            window.Na__Viewport__Validation.na_showValidationError(['Render error: ' + e.message]);
            return false;
        }
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Reset View to Fit Window
    // ------------------------------------------------------------
    function na_resetView() {
        const config = Na_DynamicUI.na_getConfig();
        window.Na__Viewport__Controls.na_resetView(_svgElement, _viewBox, _interactionState, config);
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Export Current Model as DXF
    // ------------------------------------------------------------
    function na_exportDxf() {
        const config = Na_DynamicUI.na_getConfig();
        return window.Na__Export__Dxf.na_exportDxf(config);
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
