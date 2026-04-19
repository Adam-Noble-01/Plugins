// =============================================================================
// NA TO SCALE ORTHO TEXTURE MAKER - UI EVENT TO RUBY API BRIDGE
// =============================================================================

// -----------------------------------------------------------------------------
// REGION | DOM References
// -----------------------------------------------------------------------------

const na_sceneSelectElement = document.getElementById('na-scene-select');
const na_resolutionSelectElement = document.getElementById('na-resolution-select');
const na_backgroundSelectElement = document.getElementById('na-background-select');
const na_runButtonElement = document.getElementById('na-btn-run');
const na_exportButtonElement = document.getElementById('na-btn-export');
const na_refreshButtonElement = document.getElementById('na-btn-refresh');
const na_mainStatusElement = document.getElementById('na-status-main');
const na_exportStatusElement = document.getElementById('na-status-export');
const na_settingsStatusElement = document.getElementById('na-status-settings');

// endregion -------------------------------------------------------------------

// -----------------------------------------------------------------------------
// REGION | Ruby To JavaScript Callbacks
// -----------------------------------------------------------------------------

window.na_setSceneOptions = function(sceneNames) {
    const scenes = Array.isArray(sceneNames) ? sceneNames : [];
    na_sceneSelectElement.innerHTML = '';

    scenes.forEach(function(sceneName) {
        const optionElement = document.createElement('option');
        optionElement.value = sceneName;
        optionElement.textContent = sceneName;
        na_sceneSelectElement.appendChild(optionElement);
    });
};

window.na_setStatus = function(statusType, message) {
    na_setCaptureBusy(false);                                                       // <-- Always release busy state on status update
    na_setStatusOnElement(na_mainStatusElement, statusType, message);
};

window.na_setSettingsStatus = function(statusType, message) {
    na_setStatusOnElement(na_settingsStatusElement, statusType, message);
};

window.na_setExportStatus = function(statusType, message) {
    na_setExportBusy(false);                                                        // <-- Always release export busy state
    na_setStatusOnElement(na_exportStatusElement, statusType, message);
};

function na_setStatusOnElement(targetElement, statusType, message) {
    if (!targetElement) return;

    targetElement.textContent = message || '';
    targetElement.classList.remove(
        'na-status-info',
        'na-status-success',
        'na-status-error',
        'na-status-busy'
    );

    if (statusType === 'success') {
        targetElement.classList.add('na-status-success');
        return;
    }

    if (statusType === 'error') {
        targetElement.classList.add('na-status-error');
        return;
    }

    if (statusType === 'busy') {
        targetElement.classList.add('na-status-busy');
        return;
    }

    targetElement.classList.add('na-status-info');
}

function na_setCaptureBusy(isBusy) {
    if (!na_runButtonElement) return;

    if (isBusy) {
        na_runButtonElement.disabled = true;
        na_runButtonElement.textContent = 'Capturing...';
        na_setStatusOnElement(
            na_mainStatusElement,
            'busy',
            'Capturing viewport... please wait. SketchUp may appear frozen briefly at high resolutions.'
        );
        return;
    }

    na_runButtonElement.disabled = false;
    na_runButtonElement.textContent = 'Capture Viewport';
}

function na_setExportBusy(isBusy) {
    if (!na_exportButtonElement) return;

    if (isBusy) {
        na_exportButtonElement.disabled = true;
        na_exportButtonElement.textContent = 'Exporting...';
        na_setStatusOnElement(
            na_exportStatusElement,
            'busy',
            'Exporting texture... choose a destination in the SketchUp save dialog.'
        );
        return;
    }

    na_exportButtonElement.disabled = false;
    na_exportButtonElement.textContent = 'Export Texture';
}

// endregion -------------------------------------------------------------------

// -----------------------------------------------------------------------------
// REGION | JavaScript To Ruby Bridge
// -----------------------------------------------------------------------------

function na_sendProjectionRequest() {
    const payload = {
        scene_name: na_sceneSelectElement.value,
        capture_resolution: parseInt(na_resolutionSelectElement.value, 10),
        background_mode: na_backgroundSelectElement ? na_backgroundSelectElement.value : 'transparent'
    };

    if (typeof sketchup !== 'undefined' && sketchup.na_runProjection) {
        na_setCaptureBusy(true);                                                    // <-- Disable button and show spinner
        setTimeout(function() {                                                     // <-- Yield so the DOM paints before Ruby blocks the main thread
            sketchup.na_runProjection(JSON.stringify(payload));
        }, 30);
        return;
    }

    window.na_setStatus('error', 'SketchUp bridge is not available.');
}

function na_sendExportRequest() {
    if (typeof sketchup !== 'undefined' && sketchup.na_exportTexture) {
        na_setExportBusy(true);                                                     // <-- Disable button and show spinner
        setTimeout(function() {                                                     // <-- Yield so UI paints before save dialog blocks
            sketchup.na_exportTexture(JSON.stringify({}));
        }, 30);
        return;
    }

    window.na_setExportStatus('error', 'SketchUp bridge is not available.');
}

function na_sendRefreshScriptsRequest() {
    if (typeof sketchup !== 'undefined' && sketchup.na_refreshScripts) {
        window.na_setSettingsStatus('info', 'Refreshing scripts...');
        sketchup.na_refreshScripts();
        return;
    }

    window.na_setSettingsStatus('error', 'SketchUp bridge is not available.');
}

function naShowTab(tabId, buttonElement) {
    const allTabs = document.querySelectorAll('.naTabContent');
    allTabs.forEach(function(tabElement) {
        tabElement.classList.remove('naTabContent--active');
    });

    const allButtons = document.querySelectorAll('.naTabBtn');
    allButtons.forEach(function(tabButtonElement) {
        tabButtonElement.classList.remove('naTabBtn--active');
    });

    const targetTab = document.getElementById('tab-' + tabId);
    if (targetTab) {
        targetTab.classList.add('naTabContent--active');
    }

    if (buttonElement) {
        buttonElement.classList.add('naTabBtn--active');
    }
}

// endregion -------------------------------------------------------------------

// -----------------------------------------------------------------------------
// REGION | Initialization
// -----------------------------------------------------------------------------

na_runButtonElement.addEventListener('click', na_sendProjectionRequest);
if (na_exportButtonElement) {
    na_exportButtonElement.addEventListener('click', na_sendExportRequest);
}
na_refreshButtonElement.addEventListener('click', na_sendRefreshScriptsRequest);
window.naShowTab = naShowTab;

if (typeof sketchup !== 'undefined' && sketchup.na_requestScenes) {
    sketchup.na_requestScenes();
}

if (typeof sketchup !== 'undefined' && sketchup.na_jsLog) {
    sketchup.na_jsLog('Na__Ortho UI bridge initialized.');
}

// endregion -------------------------------------------------------------------
