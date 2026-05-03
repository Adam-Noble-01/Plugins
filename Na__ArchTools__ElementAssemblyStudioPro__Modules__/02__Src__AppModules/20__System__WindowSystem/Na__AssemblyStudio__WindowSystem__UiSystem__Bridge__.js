/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - WINDOW SYSTEM - UI EVENT TO RUBY API BRIDGE
   =============================================================================
   
   FILE       : Na__AssemblyStudio__WindowSystem__UiSystem__Bridge__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Bridge between JavaScript UI and Ruby SketchUp API
   CREATED    : 2026
   
   DESCRIPTION:
   - Handles communication between the HTML dialog and SketchUp Ruby backend
   - Provides callback functions for Create, Update, Export, and Reload
   - Receives configuration data from Ruby and updates UI
   - Sends user actions and configuration changes to Ruby
   
   NAMING CONVENTION:
   - All custom identifiers use na_ prefix
   - Window-level functions that Ruby calls start with na_
   
   ============================================================================= */

// =============================================================================
// REGION | Module Variables
// =============================================================================

// Module Variables | Current Window State
// ------------------------------------------------------------
let na_currentWindowId = null;                                       // Current window ID being edited
let na_isEditMode = false;                                           // Whether we're editing an existing window
let na_liveModeEnabled = false;                                     // Live update mode state
let na_liveUpdateTimer = null;                                       // Debounce timer for live updates
let na_loadedMetadata = null;                                        // Cached metadata from Ruby (preserves timestamps)
let na_placementModeActive = false;                                  // True while the SketchUp placement tool is active

// endregion ===================================================================

// =============================================================================
// REGION | Constants
// =============================================================================

// CONSTANTS | Live Update Timing
// ------------------------------------------------------------
const NA_LIVE_UPDATE_DEBOUNCE_MS = 100;                              // 100ms debounce for smoother updates

// endregion ===================================================================

// =============================================================================
// REGION | Ruby -> JavaScript Callbacks (Called by Ruby via execute_script)
// =============================================================================

// FUNCTION | Set Initial Configuration from Ruby
// ------------------------------------------------------------
// Called when dialog opens or when window is selected
// @param {string} configJson - JSON string of window configuration
window.na_setInitialConfig = function(configJson) {
    console.log('[NA_BRIDGE] Received initial config from Ruby');
    
    try {
        const config = JSON.parse(configJson);
        
        // Check if this is an existing window (has WindowUniqueId)
        if (config.windowMetadata && 
            config.windowMetadata[0] && 
            config.windowMetadata[0].WindowUniqueId) {
            
            na_currentWindowId = config.windowMetadata[0].WindowUniqueId;
            na_isEditMode = true;
            na_loadedMetadata = config.windowMetadata[0];
            
            // Update window info display
            na_updateWindowInfo(config.windowMetadata[0]);
            
            // Show update button, hide create button
            na_toggleEditMode(true);
            
            console.log('[NA_BRIDGE] Loaded existing window:', na_currentWindowId);
        } else {
            na_currentWindowId = null;
            na_isEditMode = false;
            na_loadedMetadata = null;
            na_toggleEditMode(false);
            console.log('[NA_BRIDGE] Using default configuration (new window)');
        }
        
        // Update UI controls with configuration values
        if (config.windowConfiguration && typeof Na_DynamicUI !== 'undefined') {
            Na_DynamicUI.na_setConfig(config.windowConfiguration);
        }
        
    } catch (e) {
        console.error('[NA_BRIDGE] Error parsing config JSON:', e);
    }
};
// ---------------------------------------------------------------

// FUNCTION | Clear Current Window (When Selection is Cleared)
// ------------------------------------------------------------
// Called by Ruby when no window is selected. v0.11.6 - Now also
// resets the Description input so a stale label from the previously
// loaded window cannot leak into the next na_createWindow call.
// With the new tab-aware SelectionObserver this fires more often
// (any deselect or off-tab selection clears both tabs).
window.na_clearCurrentWindow = function() {
    console.log('[NA_BRIDGE] Clearing current window');

    na_currentWindowId = null;
    na_isEditMode      = false;
    na_loadedMetadata  = null;

    const infoSection = document.getElementById('na-window-info');
    if (infoSection) {
        infoSection.classList.add('na-hidden');
    }

    const descInput = document.getElementById('na-info-description');         // <-- v0.11.6 Drop the previous window's description
    if (descInput) descInput.value = '';

    na_toggleEditMode(false);
};
// ---------------------------------------------------------------

// FUNCTION | Show Status Message
// ------------------------------------------------------------
// Called by Ruby to display feedback to user
// @param {string} type - Status type: 'success', 'error', 'warning', 'info'
// @param {string} message - Message to display
window.na_showStatus = function(type, message) {
    console.log(`[NA_BRIDGE] Status (${type}): ${message}`);
    
    const statusBar = document.getElementById('na-status-bar');
    const statusMessage = document.getElementById('na-status-message');
    
    if (statusBar && statusMessage) {
        // Remove all status classes
        statusBar.classList.remove('na-hidden', 'na-status-success', 'na-status-error', 
                                   'na-status-warning', 'na-status-info');
        
        // Add appropriate class
        statusBar.classList.add(`na-status-${type}`);
        statusMessage.textContent = message;
        
        // Auto-hide after delay (except for errors)
        if (type !== 'error') {
            setTimeout(() => {
                statusBar.classList.add('na-hidden');
            }, 3000);
        }
    }
};
// ---------------------------------------------------------------

// FUNCTION | Receive Measurement from Measure Opening Tool
// ------------------------------------------------------------
// Called by Ruby after user completes the two-click measurement in the 3D viewport.
// Updates the width and height sliders in the UI with the measured values.
// @param {number} widthMm   - Measured opening width in millimeters
// @param {number} heightMm  - Adjusted opening height in millimeters (cill height already deducted)
// @param {number} [originXIn] - Point A x in inches  (cached server-side; ignored here)
// @param {number} [originYIn] - Point A y in inches  (cached server-side; ignored here)
// @param {number} [originZIn] - Point A z in inches  (cached server-side; ignored here)
window.na_receiveMeasurement = function(widthMm, heightMm /*, originXIn, originYIn, originZIn */) {
    // v0.11.7 - The Ruby bridge now casts every numeric argument to Float
    // before interpolating into this script string, so widthMm and heightMm
    // are guaranteed to be JS numbers, not undefined. If a future regression
    // ever sends NaN / undefined / a string, the explicit type check below
    // surfaces it loudly in the SketchUp Ruby Console.
    if (typeof widthMm !== 'number' || isNaN(widthMm) ||
        typeof heightMm !== 'number' || isNaN(heightMm)) {
        console.error(
            '[NA_BRIDGE] na_receiveMeasurement got bad args:',
            'widthMm=', widthMm, 'heightMm=', heightMm
        );
        window.na_showStatus('error', 'Measurement data corrupted - check Ruby Console.');
        return;
    }

    console.log(`[NA_BRIDGE] Received measurement: Width=${widthMm}mm, Height=${heightMm}mm`);

    const measureBtn = document.getElementById('na-btn-measure');
    if (measureBtn) {
        measureBtn.classList.remove('na-btn-measure-active');
    }

    if (typeof Na_DynamicUI === 'undefined') {
        console.error('[NA_BRIDGE] Na_DynamicUI not available to apply measurement');
        return;
    }

    Na_DynamicUI.na_setConfig({
        width_mm:  widthMm,
        height_mm: heightMm
    });

    // Point A is cached on the Ruby side; the next na_createWindow call will
    // insert at Point A automatically, falling back to the placement crosshair
    // if no measurement is pending.
    window.na_showStatus(
        'success',
        `Opening measured: ${widthMm}mm x ${heightMm}mm  -  Insert at Point A queued.`
    );
};
// ---------------------------------------------------------------

// FUNCTION | Measure Tool Cancelled
// ------------------------------------------------------------
// Called by Ruby when the user cancels the measurement tool (ESC key).
// Removes the active styling from the Measure Opening button.
window.na_measureCancelled = function() {
    console.log('[NA_BRIDGE] Measurement cancelled');
    
    const measureBtn = document.getElementById('na-btn-measure');
    if (measureBtn) {
        measureBtn.classList.remove('na-btn-measure-active');
    }
};
// ---------------------------------------------------------------

// FUNCTION | Set Placement Mode Active State
// ------------------------------------------------------------
// Called by Ruby via execute_script when the placement tool starts or ends.
// When active, Tab key presses are forwarded to Ruby instead of cycling HTML focus.
window.na_setPlacementActive = function(active) {
    na_placementModeActive = !!active;
    console.log('[NA_BRIDGE] Placement mode:', na_placementModeActive);
};
// ---------------------------------------------------------------

// endregion ===================================================================

// =============================================================================
// REGION | JavaScript -> Ruby Callbacks (Called by UI, sent to Ruby)
// =============================================================================

// FUNCTION | Create a New Window
// ------------------------------------------------------------
// Called when user clicks "Create New Window" button
// ONLY sends to SketchUp if SVG preview is valid
function na_createWindow() {
    console.log('[NA_BRIDGE] Create window requested');
    
    if (typeof Na_DynamicUI === 'undefined') {
        console.error('[NA_BRIDGE] Na_DynamicUI not available');
        return;
    }
    
    // VALIDATION: Check if SVG preview is valid before sending to SketchUp
    if (!Na_DynamicUI.na_isSvgValid()) {
        console.warn('[NA_BRIDGE] SVG preview is not valid - cannot create window');
        window.na_showStatus('error', 'Cannot create window: preview validation failed');
        return;
    }
    
    console.log('[NA_BRIDGE] SVG valid - sending to SketchUp');
    
    // Build full configuration object
    const config = na_buildFullConfig();
    const configJson = JSON.stringify(config);
    
    // Send to Ruby
    if (typeof sketchup !== 'undefined') {
        sketchup.na_createWindow(configJson);
        // Blur active element so the SketchUp viewport can receive keyboard events.
        // Tab key is handled separately via the keydown interceptor above.
        if (document.activeElement) { document.activeElement.blur(); }
    } else {
        console.log('[NA_BRIDGE] SketchUp not available. Config:', config);
        window.na_showStatus('warning', 'SketchUp connection not available');
    }
}
// ---------------------------------------------------------------

// FUNCTION | Update Existing Window
// ------------------------------------------------------------
// Called when user clicks "Update Window" button
// ONLY sends to SketchUp if SVG preview is valid
function na_updateWindow() {
    console.log('[NA_BRIDGE] Update window requested:', na_currentWindowId);
    
    if (!na_currentWindowId) {
        console.warn('[NA_BRIDGE] No window selected to update');
        window.na_showStatus('warning', 'No window selected to update');
        return;
    }
    
    if (typeof Na_DynamicUI === 'undefined') {
        console.error('[NA_BRIDGE] Na_DynamicUI not available');
        return;
    }
    
    // VALIDATION: Check if SVG preview is valid before sending to SketchUp
    if (!Na_DynamicUI.na_isSvgValid()) {
        console.warn('[NA_BRIDGE] SVG preview is not valid - cannot update window');
        window.na_showStatus('error', 'Cannot update window: preview validation failed');
        return;
    }
    
    console.log('[NA_BRIDGE] SVG valid - sending update to SketchUp');
    
    // Build full configuration object
    const config = na_buildFullConfig();
    
    // Ensure the WindowUniqueId is set
    if (config.windowMetadata && config.windowMetadata[0]) {
        config.windowMetadata[0].WindowUniqueId = na_currentWindowId;
    }
    
    const configJson = JSON.stringify(config);
    
    // Send to Ruby
    if (typeof sketchup !== 'undefined') {
        sketchup.na_updateWindow(configJson);
    } else {
        console.log('[NA_BRIDGE] SketchUp not available. Config:', config);
        window.na_showStatus('warning', 'SketchUp connection not available');
    }
}
// ---------------------------------------------------------------

// FUNCTION | Reload Ruby Scripts (Developer Feature)
// ------------------------------------------------------------
// Called when user clicks the header reload icon button
function na_reloadScripts() {
    console.log('[NA_BRIDGE] Reloading scripts');
    
    if (typeof sketchup !== 'undefined') {
        sketchup.na_reloadScripts();
    } else {
        console.log('[NA_BRIDGE] SketchUp not available for reload');
        window.na_showStatus('info', 'Reload request sent (debug mode)');
    }
}
// ---------------------------------------------------------------

// v0.11.6 - na_measureOpening() and na_toggleLiveMode() were removed.
// The global Measure Opening / Live Mode buttons are now wired through
// Na_AppContext.na_dispatch_measure() and na_dispatch_live_toggle()
// which call sketchup.na_measureOpening / na_setLiveModeFlag /
// na_performLiveUpdate directly. The bridge keeps the receive-side
// callbacks (window.na_receiveMeasurement, window.na_measureCancelled)
// because Ruby still needs them.
// ---------------------------------------------------------------

// FUNCTION | Export DXF
// ------------------------------------------------------------
// Called when user clicks "Export DXF" button.
// Sends current config to Ruby for DXF generation (proper layered CAD output).
function na_exportDxf() {
    console.log('[NA_BRIDGE] Requesting DXF export');
    
    if (typeof Na_DynamicUI === 'undefined') {
        console.error('[NA_BRIDGE] Na_DynamicUI not available');
        window.na_showStatus('error', 'UI module not available');
        return;
    }
    
    // Get current configuration
    const config = Na_DynamicUI.na_getConfig();
    
    if (!config) {
        console.error('[NA_BRIDGE] Failed to get configuration');
        window.na_showStatus('error', 'Failed to get window configuration');
        return;
    }
    
    // Convert config to JSON string
    const configJson = JSON.stringify(config);
    console.log('[NA_BRIDGE] Sending config to Ruby for DXF generation');
    
    if (typeof sketchup !== 'undefined') {
        // Send config to Ruby - DXF generation happens server-side
        sketchup.na_exportDxf(configJson);
        window.na_showStatus('info', 'Generating DXF...');
    } else {
        // Browser fallback: use simplified JS-based DXF (for testing)
        console.warn('[NA_BRIDGE] SketchUp not available, using browser fallback');
        const dxfContent = Na_Viewport.na_exportDxf();
        if (dxfContent) {
            na_downloadDxf(dxfContent);
        } else {
            window.na_showStatus('error', 'Failed to generate DXF');
        }
    }
}
// ---------------------------------------------------------------

// FUNCTION | Reset Hidden Elements
// ------------------------------------------------------------
// Restores all currently hidden preview/model elements back to visible.
function na_resetElements() {
    console.log('[NA_BRIDGE] Reset elements requested');

    if (typeof Na_DynamicUI === 'undefined') {
        console.error('[NA_BRIDGE] Na_DynamicUI not available');
        window.na_showStatus('error', 'UI module not available');
        return;
    }

    Na_DynamicUI.na_resetHiddenElements();
    window.na_showStatus('success', 'All hidden elements restored');
}
// ---------------------------------------------------------------

// FUNCTION | Log Message to Ruby Console
// ------------------------------------------------------------
// Useful for debugging
function na_logToRuby(message) {
    if (typeof sketchup !== 'undefined') {
        sketchup.na_jsLog(message);
    }
    console.log('[NA_JS]', message);
}
// ---------------------------------------------------------------

// FUNCTION | Set the Window-Tab Live Mode Flag (Called by Na_AppContext)
// ------------------------------------------------------------
// v0.11.6 - The global Live Mode button is wired to
// Na_AppContext.na_dispatch_live_toggle, which calls this setter to
// flip the bridge-private na_liveModeEnabled boolean. The dispatcher
// owns button label / class painting so this function does not touch
// the DOM. Keeping the setter explicit means there is one tested
// gateway into na_liveModeEnabled rather than every consumer poking
// at the variable directly.
window.na_setLiveModeFlag = function (enabled) {
    na_liveModeEnabled = !!enabled;
    console.log('[NA_BRIDGE] Live Mode flag =', na_liveModeEnabled);
};
// ---------------------------------------------------------------

// FUNCTION | Send Live Update to SketchUp (Debounced)
// ------------------------------------------------------------
// Called automatically when config changes and Live Mode is enabled.
// Uses debouncing to prevent overwhelming SketchUp with rapid slider changes.
function na_sendLiveUpdate() {
    if (!na_liveModeEnabled) return;
    
    // Clear any pending update
    if (na_liveUpdateTimer) {
        clearTimeout(na_liveUpdateTimer);
    }
    
    // Schedule the update with debounce
    na_liveUpdateTimer = setTimeout(function() {
        na_performLiveUpdate();
    }, NA_LIVE_UPDATE_DEBOUNCE_MS);
}
// ---------------------------------------------------------------

// FUNCTION | Actually Perform the Live Update (Called After Debounce)
// ------------------------------------------------------------
// Exposed on window so Na_AppContext.na_dispatch_live_toggle can
// trigger an immediate sync the moment the user enables Live Mode
// (matches the previous na_toggleLiveMode behaviour).
function na_performLiveUpdate() {
    if (!na_liveModeEnabled) return;
    
    if (typeof Na_DynamicUI === 'undefined') {
        console.error('[NA_BRIDGE] Na_DynamicUI not available');
        return;
    }
    
    // Check if SVG preview is valid before sending to SketchUp
    if (!Na_DynamicUI.na_isSvgValid()) {
        console.warn('[NA_BRIDGE] SVG preview not valid - skipping live update');
        return;
    }
    
    console.log('[NA_BRIDGE] Sending live update to SketchUp');
    
    // Build configuration object
    const config = na_buildFullConfig();
    const configJson = JSON.stringify(config);
    
    // Send to Ruby via live update callback
    if (typeof sketchup !== 'undefined') {
        sketchup.na_liveUpdate(configJson);
    } else {
        console.log('[NA_BRIDGE] SketchUp not available for live update. Config:', config);
    }
}
window.na_performLiveUpdate = na_performLiveUpdate;                  // <-- v0.11.6 dispatcher entry-point
// ---------------------------------------------------------------

// FUNCTION | Check if Live Mode is Currently Enabled
// ------------------------------------------------------------
function na_isLiveModeEnabled() {
    return na_liveModeEnabled;
}
// ---------------------------------------------------------------

// endregion ===================================================================

// =============================================================================
// REGION | Helper Functions
// =============================================================================

// FUNCTION | Build Full Configuration Object for Ruby
// ------------------------------------------------------------
function na_buildFullConfig() {
    const uiConfig = Na_DynamicUI.na_getConfig();
    
    // Get description suffix from the text input
    const descInput = document.getElementById('na-info-description');
    const description = descInput ? descInput.value.trim() : '';
    
    return {
        windowMetadata: [
            {
                WindowUniqueId: na_currentWindowId,
                WindowName: na_loadedMetadata ? na_loadedMetadata.WindowName : "Na Window",
                WindowDescription: description,
                WindowNotes: na_loadedMetadata ? na_loadedMetadata.WindowNotes : "Created with Element Assembly Studio Pro",
                CreatedDate: na_loadedMetadata ? na_loadedMetadata.CreatedDate : null,
                LastModified: na_loadedMetadata ? na_loadedMetadata.LastModified : null
            }
        ],
        windowComponents: [],
        windowConfiguration: uiConfig
    };
}
// ---------------------------------------------------------------

// FUNCTION | Toggle Between Create and Edit Modes
// ------------------------------------------------------------
function na_toggleEditMode(isEdit) {
    const createBtn = document.getElementById('na-btn-create');
    const updateBtn = document.getElementById('na-btn-update');
    const infoSection = document.getElementById('na-window-info');
    
    if (isEdit) {
        // Keep both buttons visible, but enable update button
        if (updateBtn) {
            updateBtn.disabled = false;
            updateBtn.classList.remove('na-btn-disabled');
        }
        if (infoSection) infoSection.classList.remove('na-hidden');
    } else {
        // Keep both buttons visible, but disable update button
        if (updateBtn) {
            updateBtn.disabled = true;
            updateBtn.classList.add('na-btn-disabled');
        }
        if (infoSection) infoSection.classList.add('na-hidden');
    }
}
// ---------------------------------------------------------------

// FUNCTION | Update Window Info Display
// ------------------------------------------------------------
function na_updateWindowInfo(metadata) {
    const idElem = document.getElementById('na-info-window-id');
    const descInput = document.getElementById('na-info-description');
    const createdElem = document.getElementById('na-info-created');
    const modifiedElem = document.getElementById('na-info-modified');
    
    if (idElem) idElem.textContent = metadata.WindowUniqueId || '-';
    if (descInput) descInput.value = metadata.WindowDescription || '';
    if (createdElem) createdElem.textContent = metadata.CreatedDate || '-';
    if (modifiedElem) modifiedElem.textContent = metadata.LastModified || '-';
}
// ---------------------------------------------------------------

// FUNCTION | Fallback DXF Download (When Not in SketchUp)
// ------------------------------------------------------------
function na_downloadDxf(dxfContent) {
    const blob = new Blob([dxfContent], { type: 'application/dxf' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = 'window_export.dxf';
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
    
    window.na_showStatus('success', 'DXF downloaded');
}
// ---------------------------------------------------------------

// endregion ===================================================================

// =============================================================================
// REGION | Initialization
// =============================================================================

// FUNCTION | Initialize Bridge When DOM is Ready
// ------------------------------------------------------------
document.addEventListener('DOMContentLoaded', function() {
    console.log('[NA_BRIDGE] Bridge initialized');
    
    // Log to Ruby that JS is ready
    na_logToRuby('JavaScript bridge initialized and ready');
});
// ---------------------------------------------------------------

// FUNCTION | Tab Key Interceptor for Placement Mode
// ------------------------------------------------------------
// When the SketchUp placement tool is active, Tab is intercepted here to
// prevent the browser cycling HTML focus and instead forward the keypress
// to Ruby as a rotation command.
// This fires for EVERY keydown regardless of which element has focus,
// which is exactly what is needed when the dialog holds OS keyboard focus.
document.addEventListener('keydown', function(e) {
    if (na_placementModeActive && e.key === 'Tab') {
        e.preventDefault();
        if (typeof sketchup !== 'undefined') {
            sketchup.na_keyboard_tab();
        }
    }
});
// ---------------------------------------------------------------

// endregion ===================================================================

// =============================================================================
// END OF FILE
// =============================================================================
