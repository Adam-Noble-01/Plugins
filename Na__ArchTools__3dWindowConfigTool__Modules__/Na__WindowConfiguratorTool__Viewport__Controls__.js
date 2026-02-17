/* =============================================================================
   NA WINDOW CONFIGURATOR TOOL - VIEWPORT CONTROLS
   =============================================================================
   
   FILE       : Na__WindowConfiguratorTool__Viewport__Controls__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Viewport interaction (pan, zoom, click handling)
   CREATED    : 2026
   
   DESCRIPTION:
   - Mouse wheel zoom functionality
   - Click-and-drag pan functionality
   - Distinguishes between clicks and drags
   - Reset view to fit window
   - Casement click target setup and handling
   - State management passed via parameters (decoupled)
   
   NAMING CONVENTION:
   - All functions use na_ prefix (lowercase)
   - Exported to window.Na__Viewport__Controls object
   
   ============================================================================= */

// =============================================================================
// REGION | Viewport Controls Module
// =============================================================================

const Na__Viewport__Controls = (function() {
    
    // FUNCTION | Setup Pan and Zoom Event Handlers
    // ------------------------------------------------------------
    // @param {HTMLElement} svgElement - The SVG element
    // @param {Object} viewBoxState - ViewBox state object { x, y, width, height }
    // @param {Object} interactionState - Interaction state { scale, isPanning, didPan, lastMousePos, panStartPos }
    // @param {Function} updateCallback - Callback function to trigger viewBox update
    function na_setupPanZoom(svgElement, viewBoxState, interactionState, updateCallback) {
        const wrapper = document.getElementById('na-canvas-wrapper');
        if (!wrapper) return;
        
        // Mouse wheel zoom
        wrapper.addEventListener('wheel', (e) => {
            e.preventDefault();
            const zoomFactor = e.deltaY > 0 ? 1.1 : 0.9;
            interactionState.scale *= zoomFactor;
            interactionState.scale = Math.max(0.1, Math.min(10, interactionState.scale));
            
            viewBoxState.width *= zoomFactor;
            viewBoxState.height *= zoomFactor;
            
            if (updateCallback) updateCallback();
        });
        
        // Pan start
        wrapper.addEventListener('mousedown', (e) => {
            interactionState.isPanning = true;
            interactionState.didPan = false;
            interactionState.panStartPos = { x: e.clientX, y: e.clientY };
            interactionState.lastMousePos = { x: e.clientX, y: e.clientY };
            wrapper.style.cursor = 'grabbing';
        });
        
        // Pan move
        wrapper.addEventListener('mousemove', (e) => {
            if (!interactionState.isPanning) return;
            
            // Track total pan distance to distinguish click from drag
            const totalDx = Math.abs(e.clientX - interactionState.panStartPos.x);
            const totalDy = Math.abs(e.clientY - interactionState.panStartPos.y);
            if (totalDx > 5 || totalDy > 5) {
                interactionState.didPan = true;
            }
            
            const dx = (e.clientX - interactionState.lastMousePos.x) * interactionState.scale;
            const dy = (e.clientY - interactionState.lastMousePos.y) * interactionState.scale;
            
            viewBoxState.x -= dx;
            viewBoxState.y -= dy;
            
            interactionState.lastMousePos = { x: e.clientX, y: e.clientY };
            if (updateCallback) updateCallback();
        });
        
        // Pan end
        wrapper.addEventListener('mouseup', () => {
            interactionState.isPanning = false;
            interactionState.didPan = false;
            wrapper.style.cursor = 'grab';
        });
        
        wrapper.addEventListener('mouseleave', () => {
            interactionState.isPanning = false;
            interactionState.didPan = false;
            wrapper.style.cursor = 'grab';
        });
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Update SVG viewBox Attribute
    // ------------------------------------------------------------
    // @param {HTMLElement} svgElement - The SVG element
    // @param {Object} viewBoxState - ViewBox state object { x, y, width, height }
    function na_updateViewBox(svgElement, viewBoxState) {
        if (svgElement) {
            svgElement.setAttribute('viewBox', 
                `${viewBoxState.x} ${viewBoxState.y} ${viewBoxState.width} ${viewBoxState.height}`);
        }
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Reset View to Fit Window
    // ------------------------------------------------------------
    // @param {HTMLElement} svgElement - The SVG element
    // @param {Object} viewBoxState - ViewBox state object { x, y, width, height }
    // @param {Object} interactionState - Interaction state { scale }
    // @param {Object} config - Window configuration object
    function na_resetView(svgElement, viewBoxState, interactionState, config) {
        const padding = 200;  // Extra padding to accommodate dimension annotations
        
        viewBoxState.x = -padding;
        viewBoxState.y = -(config.height_mm || 1200) - padding;
        viewBoxState.width = (config.width_mm || 900) + (padding * 2);
        viewBoxState.height = (config.height_mm || 1200) + (padding * 2);
        
        interactionState.scale = 1;
        
        na_updateViewBox(svgElement, viewBoxState);
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Setup Casement Click Targets (Event Delegation)
    // ------------------------------------------------------------
    // Attaches click handler to the SVG element for casement toggling.
    // Uses event delegation to handle clicks on dynamically generated rects.
    // @param {HTMLElement} svgElement - The SVG element
    // @param {Object} interactionState - Interaction state { didPan }
    // @param {Function} clickCallback - Callback function(openingIndex) called when opening is clicked
    function na_setupCasementClickTargets(svgElement, interactionState, clickCallback) {
        if (!svgElement) return;
        
        // Remove previous listener if it exists
        if (svgElement._na_clickHandler) {
            svgElement.removeEventListener('click', svgElement._na_clickHandler);
        }
        
        // Create named handler function for proper removal
        const handleClick = (e) => {
            // Ignore click if user was panning (dragged the view)
            if (interactionState.didPan) return;
            
            // Check if clicked element is a click-target
            const target = e.target;
            if (!target.classList.contains('na-opening-click-target')) return;
            
            const openingIndex = parseInt(target.dataset.openingIndex, 10);
            if (isNaN(openingIndex)) return;
            
            // Call the callback with the opening index
            if (clickCallback) {
                clickCallback(openingIndex);
            }
        };
        
        // Add new listener and store it for next cleanup
        svgElement.addEventListener('click', handleClick);
        svgElement._na_clickHandler = handleClick;
    }
    // ---------------------------------------------------------------
    
    // Public API
    // ------------------------------------------------------------
    return {
        na_setupPanZoom: na_setupPanZoom,
        na_updateViewBox: na_updateViewBox,
        na_resetView: na_resetView,
        na_setupCasementClickTargets: na_setupCasementClickTargets
    };
    
})();

// endregion ===================================================================

// =============================================================================
// REGION | Global Exports
// =============================================================================

// Export to global window object for access by other modules
// ------------------------------------------------------------
window.Na__Viewport__Controls = Na__Viewport__Controls;

console.log('[NA_VIEWPORT_CONTROLS] Viewport Controls module loaded');

// endregion ===================================================================

// =============================================================================
// END OF FILE
// =============================================================================
