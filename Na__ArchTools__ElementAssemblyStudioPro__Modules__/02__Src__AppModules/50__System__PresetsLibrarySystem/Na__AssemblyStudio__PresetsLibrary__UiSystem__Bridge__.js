// =============================================================================
// ELEMENT ASSEMBLY STUDIO PRO - PRESETS LIBRARY - UI EVENT TO RUBY API BRIDGE
// =============================================================================
//
// FILE       : Na__AssemblyStudio__PresetsLibrary__UiSystem__Bridge__.js
// NAMESPACE  : window.Na__PresetsLibrary__Bridge
// MODULE     : Presets Library Bridge
// AUTHOR     : Noble Architecture
// PURPOSE    : Ruby comms, presets cache, default-config builder, and preset
//              apply / capture logic for the Presets Gallery feature.
// CREATED    : 2026
//
// DESCRIPTION:
// - Requests and caches the preset library scanned by Ruby Na__Store.
// - The Ruby side exposes these add_action_callback names:
//     * na_presetsRequestLibrary
//     * na_presetsSaveNew        (payload_json)
//     * na_presetsUpdateMeta     (payload_json)
//     * na_presetsUpdateConfig   (payload_json)
// - Ruby talks back via these globals on the JS side:
//     * window.na_receivePresetsLibrary(payload_json)
//     * window.na_receivePresetsSaveResult(payload_json)
// - Builds the full window-family defaults object (mirrors Na_DynamicUI
//   na_setDefaults) so applying a preset never leaves stale keys behind.
// - Captures the current UI design (config snapshot + SVG preview) and
//   stashes it as the pending capture consumed by the Preset Editor.
//
// NAMING CONVENTION:
// - All identifiers use Na_ / na_ prefix.
//
// =============================================================================


(function () {
    'use strict';


// -----------------------------------------------------------------------------
// REGION | Module State & Constants
// -----------------------------------------------------------------------------

    var Na__PresetsLibrary__Bridge = {};

    var NA_LIBRARY_RETRY_DELAY_MS  = 500;                                     // <-- Single deferred retry while the sketchup bridge installs
    var NA_MONTH_LABELS            = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                                      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

    var na_preset_records          = [];                                      // <-- Library records in Ruby push order (sorted by code)
    var na_preset_map              = {};                                      // <-- presetCode -> record lookup
    var na_pending_capture         = null;                                    // <-- Stashed capture consumed by the editor create flow
    var na_library_retry_scheduled = false;                                   // <-- Guards the single deferred request retry

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Generic Helpers
// -----------------------------------------------------------------------------

    // HELPER FUNCTION | Show a Status-Bar Message (Guarded)
    // ------------------------------------------------------------
    // @param {String} type    - 'success' | 'error' | 'warning' | 'info'
    // @param {String} message - Message to display
    function na_status(type, message) {
        if (typeof window.na_showStatus !== 'function') return;
        try { window.na_showStatus(type, message); }
        catch (err) { console.warn('[Na_PresetsBridge] na_showStatus failed:', err); }
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Check a SketchUp Callback Is Installed
    // ------------------------------------------------------------
    // @param  {String} fnName - Registered callback name on window.sketchup
    // @return {Boolean}         True when the callback can be invoked
    function na_sketchup_callback_available(fnName) {
        return typeof window.sketchup !== 'undefined' &&
               typeof window.sketchup[fnName] === 'function';
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | JSON.stringify a Payload to a SketchUp Callback (Guarded)
    // ------------------------------------------------------------
    // @param  {String} fnName  - Registered callback name on window.sketchup
    // @param  {Object} payload - Plain object serialised for Ruby
    // @return {Boolean}          True when the call was dispatched
    function na_call_sketchup_json(fnName, payload) {
        if (!na_sketchup_callback_available(fnName)) {
            console.warn('[Na_PresetsBridge] sketchup.' + fnName + ' not available');
            na_status('warning', 'SketchUp connection not available');
            return false;
        }
        try {
            window.sketchup[fnName](JSON.stringify(payload));
            return true;
        } catch (err) {
            console.error('[Na_PresetsBridge] ' + fnName + ' threw:', err);
            na_status('error', 'Failed to send preset data to SketchUp.');
            return false;
        }
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Parse a Ruby Payload (JSON String or Object)
    // ------------------------------------------------------------
    // Ruby pushes payloads through UiBridge.na_execute_json_function,
    // which delivers a JSON string argument; objects pass straight through
    // so browser-side testing can call the receivers directly.
    // @param  {String|Object} raw - Incoming payload
    // @return {Object|null}         Parsed payload or null on failure
    function na_parse_payload(raw) {
        if (raw === null || typeof raw === 'undefined') return null;
        if (typeof raw === 'object') return raw;
        try { return JSON.parse(raw); }
        catch (err) {
            console.error('[Na_PresetsBridge] Payload parse failed:', err);
            return null;
        }
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Format the Current Time in House Format
    // ------------------------------------------------------------
    // @return {String} Timestamp as 'DD-MMM-YYYY__HH:MM'
    function na_format_timestamp() {
        var now     = new Date();
        var day     = (now.getDate()    < 10 ? '0' : '') + now.getDate();
        var hours   = (now.getHours()   < 10 ? '0' : '') + now.getHours();
        var minutes = (now.getMinutes() < 10 ? '0' : '') + now.getMinutes();
        return day + '-' + NA_MONTH_LABELS[now.getMonth()] + '-' + now.getFullYear() +
               '__' + hours + ':' + minutes;
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Ruby -> JavaScript Receivers
// -----------------------------------------------------------------------------

    // FUNCTION | Receive the Preset Library Push From Ruby
    // ------------------------------------------------------------
    // Parses the payload, replaces the records cache and the presetCode
    // lookup map, then pings the mounted presets tabs so they re-render.
    // @param {String} payloadJson - { isOk, presets: [record...], statusMessage, reason }
    window.na_receivePresetsLibrary = function (payloadJson) {
        var payload = na_parse_payload(payloadJson);
        if (!payload) return;

        var records = Array.isArray(payload.presets) ? payload.presets : [];

        na_preset_records = records;
        na_preset_map     = {};
        records.forEach(function (record) {
            if (record && record.presetCode) na_preset_map[record.presetCode] = record;
        });

        if (payload.isOk === false) {
            na_status('warning', payload.statusMessage || 'Preset library failed to load.');
        }

        na_notify_library_updated();
    };
    // ---------------------------------------------------------------

    // FUNCTION | Receive a Preset Save Result From Ruby
    // ------------------------------------------------------------
    // @param {String} payloadJson - { isSaved, presetCode, sourceFile, statusMessage, reason }
    window.na_receivePresetsSaveResult = function (payloadJson) {
        var payload = na_parse_payload(payloadJson);
        if (!payload) return;

        if (typeof Na_PresetEditorUI !== 'undefined' &&
            typeof Na_PresetEditorUI.na_on_save_result === 'function') {
            try { Na_PresetEditorUI.na_on_save_result(payload); }
            catch (err) { console.error('[Na_PresetsBridge] na_on_save_result failed:', err); }
        }
    };
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Ping Mounted Presets Tabs After a Library Update
    // ------------------------------------------------------------
    function na_notify_library_updated() {
        if (typeof Na_PresetsUI !== 'undefined' &&
            typeof Na_PresetsUI.na_on_library_updated === 'function') {
            try { Na_PresetsUI.na_on_library_updated(); }
            catch (err) { console.error('[Na_PresetsBridge] Na_PresetsUI.na_on_library_updated failed:', err); }
        }
        if (typeof Na_PresetEditorUI !== 'undefined' &&
            typeof Na_PresetEditorUI.na_on_library_updated === 'function') {
            try { Na_PresetEditorUI.na_on_library_updated(); }
            catch (err) { console.error('[Na_PresetsBridge] Na_PresetEditorUI.na_on_library_updated failed:', err); }
        }
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Library Request & Cache Access
// -----------------------------------------------------------------------------

    // FUNCTION | Request the Preset Library From Ruby (Guarded)
    // ------------------------------------------------------------
    // The dialog's sketchup object installs asynchronously, so a request
    // fired on DOMContentLoaded may arrive too early. One deferred retry is
    // scheduled; gallery mount re-requests whenever the cache is empty.
    function na_request_library() {
        if (na_sketchup_callback_available('na_presetsRequestLibrary')) {
            try { window.sketchup.na_presetsRequestLibrary(); }
            catch (err) { console.warn('[Na_PresetsBridge] na_presetsRequestLibrary threw:', err); }
            return;
        }

        if (na_library_retry_scheduled) return;
        na_library_retry_scheduled = true;
        setTimeout(function () {
            if (!na_sketchup_callback_available('na_presetsRequestLibrary')) return;
            try { window.sketchup.na_presetsRequestLibrary(); }
            catch (err) { console.warn('[Na_PresetsBridge] na_presetsRequestLibrary retry threw:', err); }
        }, NA_LIBRARY_RETRY_DELAY_MS);
    }
    // ---------------------------------------------------------------

    // FUNCTION | Return a Copy of the Cached Preset Records
    // ------------------------------------------------------------
    // @return {Array} Cached preset records (sorted by code from Ruby)
    function na_get_presets() {
        return na_preset_records.slice();
    }
    // ---------------------------------------------------------------

    // FUNCTION | Look Up One Cached Preset Record by Code
    // ------------------------------------------------------------
    // @param  {String} code - Preset code (e.g. 'EAS001')
    // @return {Object|null}   Matching record or null
    function na_get_preset_by_code(code) {
        return na_preset_map[code] || null;
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Window-Family Defaults Builder & Preset Apply
// -----------------------------------------------------------------------------

    // FUNCTION | Build the Full Window-Family Defaults Object
    // ------------------------------------------------------------
    // Mirrors Na_DynamicUI.na_setDefaults: walks every descriptor array
    // (including expandable children) collecting id -> default, then seeds
    // the removed-element arrays that are part of every design snapshot.
    // Each array is guarded so a missing system module cannot break apply.
    // @return {Object} Complete default window/exterior-door configuration
    function na_build_default_window_config() {
        var descriptorArrays = [
            window.NA_UI_CONFIG,
            window.NA_GLAZEBAR_CONFIG,
            window.NA_CILL_FRAME_CONFIG,
            window.NA_OPTIONS_CONFIG,
            window.NA_DOOR_PANEL_CONFIG,
            window.NA_SLIDING_DOOR_CONFIG,
            window.NA_BIFOLD_DOOR_CONFIG,
            window.NA_DOUBLE_DOOR_CONFIG
        ];
        var defaults = {};

        descriptorArrays.forEach(function (configArray) {
            if (!Array.isArray(configArray)) return;
            configArray.forEach(function (item) {
                if (!item || typeof item.id === 'undefined') return;
                defaults[item.id] = item.default;

                if (item.type === 'expandable' && item.children) {
                    item.children.forEach(function (childConfig) {
                        defaults[childConfig.id] = childConfig.default;
                    });
                }
            });
        });

        defaults.removed_casements                  = [];
        defaults.removed_transom_segments           = [];
        defaults.removed_glazebars                  = [];
        defaults.double_door_removed_glazebars      = [];
        defaults.leaded_disabled_cells              = [];
        defaults.double_door_leaded_disabled_cells  = [];
        return defaults;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Apply a Window / Exterior-Door Preset to the Main UI
    // ------------------------------------------------------------
    // Merges the stored values over a full defaults object so keys the
    // preset never touched fall back to factory values instead of leaking
    // from the previously edited design.
    // @param  {Object} record - Preset record with configValues snapshot
    // @return {Boolean}         True when the preset was applied
    function na_apply_window_family_preset(record) {
        if (!record || !record.configValues) return false;
        if (typeof Na_DynamicUI === 'undefined' ||
            typeof Na_DynamicUI.na_setConfig !== 'function') {
            console.error('[Na_PresetsBridge] Na_DynamicUI not available to apply preset');
            return false;
        }

        var merged = na_build_default_window_config();
        var values = record.configValues;
        Object.keys(values).forEach(function (key) {
            merged[key] = values[key];
        });

        // Presets saved before V1.9.5 carry per-bar glaze bar offsets with no
        // Glaze Bar Offsets toggle. Dropping the defaulted key lets
        // Na_DynamicUI.na_setConfig derive it from the stored nudges instead
        // of forcing those presets to render with their offsets ignored.
        if (typeof values.glazebar_offsets_enabled === 'undefined') {
            delete merged.glazebar_offsets_enabled;
        }

        Na_DynamicUI.na_setConfig(merged);
        return true;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Apply an Interior-Door Preset to the Doors Tab
    // ------------------------------------------------------------
    // Resets the door system to factory defaults first so no stale keys
    // from a previous design survive, then bulk-applies the stored values.
    // @param  {Object} record - Preset record with configValues snapshot
    // @return {Boolean}         True when the preset was applied
    function na_apply_interior_door_preset(record) {
        if (!record || !record.configValues) return false;
        if (typeof Na_DoorUI === 'undefined' ||
            typeof Na_DoorUI.na_apply_config_change !== 'function') {
            console.error('[Na_PresetsBridge] Na_DoorUI not available to apply preset');
            return false;
        }

        if (typeof Na_DoorUI.na_reset_to_default === 'function') {
            Na_DoorUI.na_reset_to_default();
        }
        Na_DoorUI.na_apply_config_change(record.configValues);
        return true;
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Current-Design Capture & Pending Stash
// -----------------------------------------------------------------------------

    // FUNCTION | Capture the Current Main-UI Design for a New Preset
    // ------------------------------------------------------------
    // Reads the active configuration from the originating main tab,
    // derives productFamily/productType, renders the SVG preview via
    // SvgCapture, and stashes the result as the pending capture the
    // Preset Editor create flow consumes.
    // @param  {String} originTabId - 'windows' | 'doors' (defaults 'windows')
    // @return {Object|null}          Pending capture object or null
    function na_capture_current_design(originTabId) {
        var origin  = (originTabId === 'doors') ? 'doors' : 'windows';
        var capture = (origin === 'doors')
            ? na_capture_interior_door_design()
            : na_capture_window_family_design();
        if (!capture) return null;

        capture.originTabId = origin;
        capture.capturedAt  = na_format_timestamp();
        na_pending_capture  = capture;
        return capture;
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Capture the Windows-Tab (Window / Exterior Door) Design
    // ------------------------------------------------------------
    // Family/type derive from the hierarchical product controls:
    // ui_element_category 'ExteriorDoors' -> ExteriorDoor + ui_exterior_door_type
    // ('Double'|'Single'|'MultiFold'|'Sliding'); otherwise Window +
    // ui_window_type ('Casement'|'SlidingSash').
    // @return {Object|null} Capture block or null when the UI is unavailable
    function na_capture_window_family_design() {
        if (typeof Na_DynamicUI === 'undefined' ||
            typeof Na_DynamicUI.na_getConfig !== 'function') {
            console.error('[Na_PresetsBridge] Na_DynamicUI not available for capture');
            return null;
        }

        var config         = Na_DynamicUI.na_getConfig();
        var isExteriorDoor = (config.ui_element_category === 'ExteriorDoors');
        var productFamily  = isExteriorDoor ? 'ExteriorDoor' : 'Window';
        var productType    = isExteriorDoor
            ? (config.ui_exterior_door_type || 'Double')
            : (config.ui_window_type || 'Casement');

        return {
            productFamily  : productFamily,
            productType    : productType,
            schemaContract : 'windowConfiguration',
            configValues   : config,
            svgPreview     : na_capture_preview('na_capture_window_family_preview', config)
        };
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Capture the Interior-Doors-Tab Design
    // ------------------------------------------------------------
    // Na_DoorUI.na_get_active_config() returns the full payload envelope;
    // presets store only its Na__DoorConfiguration block.
    // @return {Object|null} Capture block or null when the UI is unavailable
    function na_capture_interior_door_design() {
        if (typeof Na_DoorUI === 'undefined' ||
            typeof Na_DoorUI.na_get_active_config !== 'function') {
            console.error('[Na_PresetsBridge] Na_DoorUI not available for capture');
            return null;
        }

        var payload     = Na_DoorUI.na_get_active_config();
        var configBlock = (payload && payload['Na__DoorConfiguration'])
            ? payload['Na__DoorConfiguration']
            : payload;
        if (!configBlock || typeof configBlock !== 'object') return null;

        return {
            productFamily  : 'InteriorDoor',
            productType    : 'InteriorDoor',
            schemaContract : 'Na__DoorConfiguration',
            configValues   : configBlock,
            svgPreview     : na_capture_preview('na_capture_interior_door_preview', configBlock)
        };
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Delegate One Preview Render to SvgCapture (Guarded)
    // ------------------------------------------------------------
    // @param  {String} fnName - SvgCapture function name to invoke
    // @param  {Object} config - Configuration handed to the generator
    // @return {Object}          { viewBox, widthMm, heightMm, svgMarkup }
    function na_capture_preview(fnName, config) {
        var capture = window.Na__PresetsLibrary__SvgCapture;
        var preview = null;
        if (capture && typeof capture[fnName] === 'function') {
            preview = capture[fnName](config);
        }
        return preview || { viewBox: '0 0 100 100', widthMm: 0, heightMm: 0, svgMarkup: '' };
    }
    // ---------------------------------------------------------------

    // FUNCTION | Return the Stashed Pending Capture (or null)
    // ------------------------------------------------------------
    // @return {Object|null} Pending capture awaiting the editor create flow
    function na_get_pending_capture() {
        return na_pending_capture;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Discard the Stashed Pending Capture
    // ------------------------------------------------------------
    function na_clear_pending_capture() {
        na_pending_capture = null;
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | JavaScript -> Ruby Save Callbacks
// -----------------------------------------------------------------------------

    // FUNCTION | Save the Pending Capture as a New Preset
    // ------------------------------------------------------------
    // Combines the editor's metadata form with the stashed capture and
    // dispatches na_presetsSaveNew; Ruby allocates the code + filename.
    // @param  {Object} meta - { presetName, presetDescription, presetKeywords }
    // @return {Boolean}       True when the call was dispatched
    function na_save_new_preset(meta) {
        if (!na_pending_capture) {
            na_status('error', 'No captured design on file - use Capture Current Design first.');
            return false;
        }

        var payload = {
            presetName        : (meta && meta.presetName)        || '',
            presetDescription : (meta && meta.presetDescription) || '',
            presetKeywords    : (meta && meta.presetKeywords)    || [],
            productFamily     : na_pending_capture.productFamily,
            productType       : na_pending_capture.productType,
            schemaContract    : na_pending_capture.schemaContract,
            configValues      : na_pending_capture.configValues,
            svgPreview        : na_pending_capture.svgPreview
        };
        return na_call_sketchup_json('na_presetsSaveNew', payload);
    }
    // ---------------------------------------------------------------

    // FUNCTION | Patch an Existing Preset's Metadata
    // ------------------------------------------------------------
    // @param  {Object} payload - { presetCode, sourceFile, presetName,
    //                              presetDescription, presetKeywords }
    // @return {Boolean}          True when the call was dispatched
    function na_update_preset_meta(payload) {
        return na_call_sketchup_json('na_presetsUpdateMeta', payload || {});
    }
    // ---------------------------------------------------------------

    // FUNCTION | Overwrite an Existing Preset's Configuration + Preview
    // ------------------------------------------------------------
    // @param  {Object} payload - { presetCode, sourceFile, productFamily,
    //                              productType, schemaContract, configValues,
    //                              svgPreview }
    // @return {Boolean}          True when the call was dispatched
    function na_update_preset_config(payload) {
        return na_call_sketchup_json('na_presetsUpdateConfig', payload || {});
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Initialization & Public Exports
// -----------------------------------------------------------------------------

    // FUNCTION | Request the Library Once the DOM Is Ready
    // ------------------------------------------------------------
    function na_init() {
        na_request_library();
    }
    // ---------------------------------------------------------------

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', na_init);
    } else {
        na_init();
    }

    Na__PresetsLibrary__Bridge.na_request_library               = na_request_library;
    Na__PresetsLibrary__Bridge.na_get_presets                   = na_get_presets;
    Na__PresetsLibrary__Bridge.na_get_preset_by_code            = na_get_preset_by_code;
    Na__PresetsLibrary__Bridge.na_build_default_window_config   = na_build_default_window_config;
    Na__PresetsLibrary__Bridge.na_apply_window_family_preset    = na_apply_window_family_preset;
    Na__PresetsLibrary__Bridge.na_apply_interior_door_preset    = na_apply_interior_door_preset;
    Na__PresetsLibrary__Bridge.na_capture_current_design        = na_capture_current_design;
    Na__PresetsLibrary__Bridge.na_get_pending_capture           = na_get_pending_capture;
    Na__PresetsLibrary__Bridge.na_clear_pending_capture         = na_clear_pending_capture;
    Na__PresetsLibrary__Bridge.na_save_new_preset               = na_save_new_preset;
    Na__PresetsLibrary__Bridge.na_update_preset_meta            = na_update_preset_meta;
    Na__PresetsLibrary__Bridge.na_update_preset_config          = na_update_preset_config;

    window.Na__PresetsLibrary__Bridge = Na__PresetsLibrary__Bridge;

    console.log('[NA_PRESETS_BRIDGE] Presets Library bridge loaded');

// endregion -------------------------------------------------------------------

})();
