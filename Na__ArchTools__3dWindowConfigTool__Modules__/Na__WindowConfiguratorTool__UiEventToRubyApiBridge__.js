/* =============================================================================
   NA WINDOW CONFIGURATOR TOOL - UI EVENT TO RUBY API BRIDGE
   =============================================================================
   
   FILE       : Na__WindowConfiguratorTool__UiEventToRubyApiBridge__.js
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
// Called by Ruby when no window is selected
window.na_clearCurrentWindow = function() {
    console.log('[NA_BRIDGE] Clearing current window');
    
    na_currentWindowId = null;
    na_isEditMode = false;
    na_loadedMetadata = null;
    
    // Hide window info section
    const infoSection = document.getElementById('na-window-info');
    if (infoSection) {
        infoSection.classList.add('na-hidden');
    }
    
    // Show create button, hide update button
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
// @param {number} widthMm - Measured opening width in millimeters
// @param {number} heightMm - Adjusted opening height in millimeters (cill height already deducted)
window.na_receiveMeasurement = function(widthMm, heightMm) {
    console.log(`[NA_BRIDGE] Received measurement: Width=${widthMm}mm, Height=${heightMm}mm`);
    
    // Remove active class from button (measurement complete)
    const measureBtn = document.getElementById('na-btn-measure');
    if (measureBtn) {
        measureBtn.classList.remove('na-btn-measure-active');
    }
    
    if (typeof Na_DynamicUI === 'undefined') {
        console.error('[NA_BRIDGE] Na_DynamicUI not available to apply measurement');
        return;
    }
    
    // Update the width and height configuration values
    Na_DynamicUI.na_setConfig({
        width_mm: widthMm,
        height_mm: heightMm
    });
    
    window.na_showStatus('success', `Opening measured: ${widthMm}mm x ${heightMm}mm`);
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
// Called when user clicks "Reload Plugin" button
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

// FUNCTION | Measure Opening (Activate 3D Measurement Tool)
// ------------------------------------------------------------
// Called when user clicks "Measure Opening" button.
// Activates the Ruby-side MeasureOpeningTool for two-click measurement.
function na_measureOpening() {
    console.log('[NA_BRIDGE] Requesting Measure Opening tool');
    
    // Add active class to button to show orange styling
    const measureBtn = document.getElementById('na-btn-measure');
    if (measureBtn) {
        measureBtn.classList.add('na-btn-measure-active');
    }
    
    if (typeof sketchup !== 'undefined') {
        sketchup.na_measureOpening();
        window.na_showStatus('info', 'Click Point A (base corner) in the 3D viewport...');
    } else {
        console.log('[NA_BRIDGE] SketchUp not available for measure opening');
        window.na_showStatus('warning', 'SketchUp connection not available');
        // Remove active class if connection failed
        if (measureBtn) {
            measureBtn.classList.remove('na-btn-measure-active');
        }
    }
}
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

// FUNCTION | Toggle Live Mode
// ------------------------------------------------------------
// When enabled, sends config changes to SketchUp in real-time
function na_toggleLiveMode() {
    na_liveModeEnabled = !na_liveModeEnabled;
    
    const btn = document.getElementById('na-btn-live');
    if (btn) {
        if (na_liveModeEnabled) {
            btn.classList.add('na-btn-live-active');
            btn.textContent = 'Live Mode ON';
            console.log('[NA_BRIDGE] Live Mode ENABLED');
            window.na_showStatus('success', 'Live Mode enabled - select a window to sync changes');
            
            // Immediately send current config to sync with any selected window
            na_performLiveUpdate();
        } else {
            btn.classList.remove('na-btn-live-active');
            btn.textContent = 'Live Mode';
            console.log('[NA_BRIDGE] Live Mode DISABLED');
            window.na_showStatus('info', 'Live Mode disabled');
        }
    }
}
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
                WindowNotes: na_loadedMetadata ? na_loadedMetadata.WindowNotes : "Created with Na Window Configurator",
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

// endregion ===================================================================

// =============================================================================
// END OF FILE
// =============================================================================
