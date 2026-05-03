/* =============================================================================
   NA PLUGIN CORE - VIEWPORT CONTROLS
   =============================================================================
   
   FILE       : Na__Viewport__Controls__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Viewport interaction (pan, zoom, viewBox updates, click handling)
   CREATED    : 2026
   RELOCATED  : 01-May-2026 (was Na__WindowConfiguratorTool__Viewport__Controls__.js)
   GENERALISED: 01-May-2026 - na_setupPanZoom now accepts the wrapper element
                as a parameter so it can drive ANY viewport (window, door
                plan, door elevation, future skylights, ...) instead of
                being hard-coded to #na-canvas-wrapper.

   DESCRIPTION:
   - Mouse wheel zoom functionality
   - Click-and-drag pan functionality
   - Distinguishes between clicks and drags
   - Reset view via a content-fitter callback supplied by the caller
   - Casement click target setup and handling (window-specific helper that
     simply delegates click targeting on whichever SVG it's given)
   - State management passed via parameters (decoupled)

   NAMING CONVENTION:
   - All functions use na_ prefix (lowercase)
   - Exported to window.Na__Viewport__Controls object (preserved global name)
   
   ============================================================================= */

// =============================================================================
// REGION | Viewport Controls Module
// =============================================================================

const Na__Viewport__Controls = (function() {
    
    // FUNCTION | Setup Pan and Zoom Event Handlers on a Wrapper Element
    // ------------------------------------------------------------
    // @param {HTMLElement} wrapperElement   - The wrapper element listening for mouse events.
    //                                         Was previously hard-coded to #na-canvas-wrapper.
    // @param {HTMLElement} svgElement       - The SVG element whose viewBox is updated.
    // @param {Object}      viewBoxState     - { x, y, width, height }
    // @param {Object}      interactionState - { scale, isPanning, didPan, lastMousePos, panStartPos }
    // @param {Function}    updateCallback   - Called after any viewBox mutation (typically
    //                                         () => na_updateViewBox(svgElement, viewBoxState))
    function na_setupPanZoom(wrapperElement, svgElement, viewBoxState, interactionState, updateCallback) {
        if (!wrapperElement) {
            console.warn('[NA_VIEWPORT_CONTROLS] na_setupPanZoom called without a wrapperElement');
            return;
        }

        // Apply the visual grab cursor only when interactivity is bound,
        // so any future static viewport doesn't lie about being draggable.
        wrapperElement.classList.add('na-viewport-interactive');

        // Mouse wheel zoom
        wrapperElement.addEventListener('wheel', (e) => {
            e.preventDefault();
            const zoomFactor = e.deltaY > 0 ? 1.1 : 0.9;
            interactionState.scale *= zoomFactor;
            interactionState.scale = Math.max(0.1, Math.min(10, interactionState.scale));

            viewBoxState.width  *= zoomFactor;
            viewBoxState.height *= zoomFactor;

            if (updateCallback) updateCallback();
        });

        // Pan start
        wrapperElement.addEventListener('mousedown', (e) => {
            interactionState.isPanning   = true;
            interactionState.didPan      = false;
            interactionState.panStartPos = { x: e.clientX, y: e.clientY };
            interactionState.lastMousePos = { x: e.clientX, y: e.clientY };
            wrapperElement.style.cursor  = 'grabbing';
        });

        // Pan move
        wrapperElement.addEventListener('mousemove', (e) => {
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
        wrapperElement.addEventListener('mouseup', () => {
            interactionState.isPanning = false;
            interactionState.didPan    = false;
            wrapperElement.style.cursor = 'grab';
        });

        wrapperElement.addEventListener('mouseleave', () => {
            interactionState.isPanning = false;
            interactionState.didPan    = false;
            wrapperElement.style.cursor = 'grab';
        });
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Update SVG viewBox Attribute
    // ------------------------------------------------------------
    // @param {HTMLElement} svgElement   - The SVG element
    // @param {Object}      viewBoxState - { x, y, width, height }
    function na_updateViewBox(svgElement, viewBoxState) {
        if (svgElement) {
            svgElement.setAttribute('viewBox', 
                `${viewBoxState.x} ${viewBoxState.y} ${viewBoxState.width} ${viewBoxState.height}`);
        }
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Reset View to Fit Content (Content-Fitter Callback Style)
    // ------------------------------------------------------------
    // Generic reset that delegates the actual content extents to a
    // caller-supplied fitter. The fitter receives (config) and must
    // return { x, y, width, height } for the desired viewBox.
    //
    // @param {HTMLElement} svgElement       - The SVG element
    // @param {Object}      viewBoxState     - { x, y, width, height } - mutated in place
    // @param {Object}      interactionState - { scale, ... }          - mutated in place
    // @param {Object}      config           - Tab-specific config supplied to the fitter
    // @param {Function}    fitToContent     - (config) => { x, y, width, height }
    function na_resetView(svgElement, viewBoxState, interactionState, config, fitToContent) {
        if (typeof fitToContent !== 'function') {
            console.warn('[NA_VIEWPORT_CONTROLS] na_resetView called without fitToContent fn');
            return;
        }

        const fit = fitToContent(config) || {};
        viewBoxState.x      = (typeof fit.x      === 'number') ? fit.x      : 0;
        viewBoxState.y      = (typeof fit.y      === 'number') ? fit.y      : 0;
        viewBoxState.width  = (typeof fit.width  === 'number') ? fit.width  : 1;
        viewBoxState.height = (typeof fit.height === 'number') ? fit.height : 1;

        interactionState.scale = 1;

        na_updateViewBox(svgElement, viewBoxState);
    }
    // ---------------------------------------------------------------

    // FUNCTION | Window-Specific Reset Fitter
    // ------------------------------------------------------------
    // Bottom-left-origin window viewBox with 200mm padding to leave
    // room for dimension annotations. Exported so callers can pass it
    // as the fitter into na_resetView, preserving the legacy behaviour
    // exactly.
    function na_windowResetFitter(config) {
        const padding = 200;
        const widthMm  = (config && config.width_mm)  || 900;
        const heightMm = (config && config.height_mm) || 1200;
        return {
            x      : -padding,
            y      : -heightMm - padding,
            width  : widthMm  + (padding * 2),
            height : heightMm + (padding * 2)
        };
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Setup Casement Click Targets (Event Delegation)
    // ------------------------------------------------------------
    // Window-specific click delegation kept here because it is the only
    // place that already understands the four click-target classes used
    // by the window SVG generator. Door viewports do not use these.
    //
    // @param {HTMLElement} svgElement              - The SVG element
    // @param {Object}      interactionState        - { didPan }
    // @param {Function}    clickCallback           - (openingIndex, cellIndex, panelIndex)
    // @param {Function}    transomClickCallback    - (openingIndex, transomIndex)
    // @param {Function}    glazebarClickCallback   - (openingIndex, cellIndex, panelIndex, sashIndex, orientation, barIndex)
    function na_setupCasementClickTargets(svgElement, interactionState, clickCallback, transomClickCallback, glazebarClickCallback) {
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
            if (target.classList.contains('na-glazebar-click-target')) {
                const openingIndex = parseInt(target.dataset.openingIndex, 10);
                const cellIndex = parseInt(target.dataset.cellIndex, 10);
                const panelIndex = parseInt(target.dataset.panelIndex, 10);
                const sashIndex = parseInt(target.dataset.sashIndex, 10);
                const barIndex = parseInt(target.dataset.barIndex, 10);
                const orientation = target.dataset.orientation;

                if (isNaN(openingIndex) ||
                    isNaN(cellIndex) ||
                    isNaN(panelIndex) ||
                    isNaN(sashIndex) ||
                    isNaN(barIndex) ||
                    (orientation !== 'horizontal' && orientation !== 'vertical')) {
                    return;
                }

                if (glazebarClickCallback) {
                    glazebarClickCallback(openingIndex, cellIndex, panelIndex, sashIndex, orientation, barIndex);
                }
                return;
            }

            if (target.classList.contains('na-transom-click-target')) {
                const openingIndex = parseInt(target.dataset.openingIndex, 10);
                const transomIndex = parseInt(target.dataset.transomIndex, 10);
                if (isNaN(openingIndex) || isNaN(transomIndex)) return;

                if (transomClickCallback) {
                    transomClickCallback(openingIndex, transomIndex);
                }
                return;
            }

            if (!target.classList.contains('na-opening-click-target')) return;

            const openingIndex = parseInt(target.dataset.openingIndex, 10);  // <-- Per-panel click target identifies opening
            const cellIndex = parseInt(target.dataset.cellIndex, 10);        // <-- ...and the transom-bound cell
            const panelIndex = parseInt(target.dataset.panelIndex, 10);      // <-- ...and the casement panel within
            if (isNaN(openingIndex) || isNaN(cellIndex) || isNaN(panelIndex)) return;

            if (clickCallback) {
                clickCallback(openingIndex, cellIndex, panelIndex);          // <-- Forward full per-panel identity
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
        na_setupPanZoom              : na_setupPanZoom,
        na_updateViewBox             : na_updateViewBox,
        na_resetView                 : na_resetView,
        na_windowResetFitter         : na_windowResetFitter,
        na_setupCasementClickTargets : na_setupCasementClickTargets
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
