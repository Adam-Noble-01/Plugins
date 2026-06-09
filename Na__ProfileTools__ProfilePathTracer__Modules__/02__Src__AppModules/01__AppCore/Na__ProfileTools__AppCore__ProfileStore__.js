// =============================================================================
// NA PROFILE TOOLS - APP CORE - PROFILE STORE
// =============================================================================
//
// FILE       : Na__ProfileTools__AppCore__ProfileStore__.js
// NAMESPACE  : window.Na__ProfileTools__ProfileStore
// PURPOSE    : Single source of truth for the loaded profile map and the
//              currently selected profile key.  All tab modules read from
//              and write to this store; changes are broadcast via Na_AppContext.
//
// EVENTS (dispatched via Na_AppContext.na_dispatch):
//   na_profiles_changed   - payload: { profiles, selectedKey }
//   na_selected_changed   - payload: { key, record }
//   na_profile_meta_updated - payload: { key, record }
//
// LOAD ORDER : Must load AFTER BridgeBase + MainShell, BEFORE any tab module.
//
// =============================================================================

(function () {
    'use strict';

    var Na__ProfileTools__ProfileStore = {};

    // -------------------------------------------------------------------------
    // REGION | Internal State
    // -------------------------------------------------------------------------

    var na_profiles     = {};
    var na_selected_key = '';

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Bus Helper
    // -------------------------------------------------------------------------

    function na_dispatch(eventName, payload) {
        if (window.Na_AppContext && typeof window.Na_AppContext.na_dispatch === 'function') {
            window.Na_AppContext.na_dispatch(eventName, payload);
        }
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Bulk Load (from Bootstrap)
    // -------------------------------------------------------------------------

    Na__ProfileTools__ProfileStore.Na__Store__SetProfiles = function (profilesByKey, defaultKey) {
        na_profiles = (profilesByKey && typeof profilesByKey === 'object') ? profilesByKey : {};

        var keys = Object.keys(na_profiles);
        if (defaultKey && na_profiles[defaultKey]) {
            na_selected_key = defaultKey;
        } else if (keys.length > 0) {
            na_selected_key = keys[0];
        } else {
            na_selected_key = '';
        }

        na_dispatch('na_profiles_changed', {
            profiles:    na_profiles,
            selectedKey: na_selected_key
        });
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Profile Read Accessors
    // -------------------------------------------------------------------------

    Na__ProfileTools__ProfileStore.Na__Store__GetProfiles = function () {
        return na_profiles;
    };

    Na__ProfileTools__ProfileStore.Na__Store__GetProfile = function (key) {
        return na_profiles[key] || null;
    };

    Na__ProfileTools__ProfileStore.Na__Store__GetSelectedKey = function () {
        return na_selected_key;
    };

    Na__ProfileTools__ProfileStore.Na__Store__GetSelectedRecord = function () {
        return na_selected_key ? (na_profiles[na_selected_key] || null) : null;
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Selection
    // -------------------------------------------------------------------------

    Na__ProfileTools__ProfileStore.Na__Store__SetSelected = function (key, options) {
        if (!key || !na_profiles[key]) return;
        na_selected_key = key;
        var record = na_profiles[key];
        var navigate = options && options.navigate === true;

        na_dispatch('na_selected_changed', { key: key, record: record, navigate: navigate });
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Meta Patch (live in-memory edit, pre-save)
    // -------------------------------------------------------------------------

    Na__ProfileTools__ProfileStore.Na__Store__ApplyMetaPatch = function (key, patch) {
        if (!key || !na_profiles[key]) return;
        var record = na_profiles[key];
        var assetData = (record.profileData && record.profileData.assetData) || {};
        var meta      = assetData.meta      || {};
        var assetMeta = assetData['Na__Asset__Metadata'] || {};

        if (Object.prototype.hasOwnProperty.call(patch, 'name')) {
            record.displayName              = patch.name;
            assetMeta['Na__Asset__Name']    = patch.name;
        }
        if (Object.prototype.hasOwnProperty.call(patch, 'description')) {
            assetMeta['Na__Asset__Description'] = patch.description;
        }
        if (Object.prototype.hasOwnProperty.call(patch, 'keywords')) {
            meta['Meta_ProfileKeywords']    = Array.isArray(patch.keywords) ? patch.keywords : [];
        }

        na_dispatch('na_profile_meta_updated', { key: key, record: record });
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Update Record (after successful server save)
    // -------------------------------------------------------------------------

    Na__ProfileTools__ProfileStore.Na__Store__UpdateRecord = function (key, freshRecord) {
        if (!key || !freshRecord) return;
        na_profiles[key] = freshRecord;
        if (na_selected_key === key) {
            na_dispatch('na_selected_changed', { key: key, record: freshRecord, navigate: false });
        }
        na_dispatch('na_profile_meta_updated', { key: key, record: freshRecord });
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Keyword Helper
    // -------------------------------------------------------------------------

    Na__ProfileTools__ProfileStore.Na__Store__ProfileKeywords = function (record) {
        if (!record) return [];
        var assetData = (record.profileData && record.profileData.assetData) || {};
        var meta = assetData.meta || {};
        var kw = meta['Meta_ProfileKeywords'];
        return Array.isArray(kw) ? kw : [];
    };

    // endregion ----------------------------------------------------------------

    window.Na__ProfileTools__ProfileStore = Na__ProfileTools__ProfileStore;

    // endregion ----------------------------------------------------------------
})();
