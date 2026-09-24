// =============================================================================
// NA NOBLE3D MODELLING TOOLS - TO SCALE ORTHO TEXTURE MAKER - UI BRIDGE
// FILE : Na__Noble3dModellingTools__ToScaleOrthoTextureMaker__UiBridge__.js
// =============================================================================

const na_sceneSelectElement = document.getElementById('na-scene-select');
const na_resolutionSelectElement = document.getElementById('na-resolution-select');
const na_backgroundSelectElement = document.getElementById('na-background-select');
const na_runButtonElement = document.getElementById('na-btn-run');
const na_exportButtonElement = document.getElementById('na-btn-export');
const na_refreshButtonElement = document.getElementById('na-btn-refresh');
const na_mainStatusElement = document.getElementById('na-status-main');
const na_exportStatusElement = document.getElementById('na-status-export');
const na_settingsStatusElement = document.getElementById('na-status-settings');

const NA_STATUS_CLASSES = [
    'naOrtho__Status--info',
    'naOrtho__Status--success',
    'naOrtho__Status--error',
    'naOrtho__Status--busy'
];

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
    na_setCaptureBusy(false);
    na_setStatusOnElement(na_mainStatusElement, statusType, message);
};

window.na_setSettingsStatus = function(statusType, message) {
    na_setStatusOnElement(na_settingsStatusElement, statusType, message);
};

window.na_setExportStatus = function(statusType, message) {
    na_setExportBusy(false);
    na_setStatusOnElement(na_exportStatusElement, statusType, message);
};

function na_setStatusOnElement(targetElement, statusType, message) {
    if (!targetElement) return;
    targetElement.textContent = message || '';
    NA_STATUS_CLASSES.forEach(function(className) {
        targetElement.classList.remove(className);
    });
    const statusClass = {
        success: 'naOrtho__Status--success',
        error: 'naOrtho__Status--error',
        busy: 'naOrtho__Status--busy'
    }[statusType] || 'naOrtho__Status--info';
    targetElement.classList.add(statusClass);
}

function na_setCaptureBusy(isBusy) {
    if (!na_runButtonElement) return;
    na_runButtonElement.disabled = isBusy;
    na_runButtonElement.textContent = isBusy ? 'Capturing...' : 'Capture Viewport';
    if (isBusy) {
        na_setStatusOnElement(
            na_mainStatusElement,
            'busy',
            'Capturing viewport. SketchUp may appear frozen briefly at high resolutions.'
        );
    }
}

function na_setExportBusy(isBusy) {
    if (!na_exportButtonElement) return;
    na_exportButtonElement.disabled = isBusy;
    na_exportButtonElement.textContent = isBusy ? 'Exporting...' : 'Export Texture';
    if (isBusy) {
        na_setStatusOnElement(
            na_exportStatusElement,
            'busy',
            'Exporting texture. Choose a destination in the SketchUp save dialog.'
        );
    }
}

function na_sendProjectionRequest() {
    const payload = {
        scene_name: na_sceneSelectElement.value,
        capture_resolution: parseInt(na_resolutionSelectElement.value, 10),
        background_mode: na_backgroundSelectElement ? na_backgroundSelectElement.value : 'transparent'
    };
    if (typeof sketchup !== 'undefined' && sketchup.na_runProjection) {
        na_setCaptureBusy(true);
        setTimeout(function() {
            sketchup.na_runProjection(JSON.stringify(payload));
        }, 30);
        return;
    }
    window.na_setStatus('error', 'SketchUp bridge is not available.');
}

function na_sendExportRequest() {
    if (typeof sketchup !== 'undefined' && sketchup.na_exportTexture) {
        na_setExportBusy(true);
        setTimeout(function() {
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
    document.querySelectorAll('.naOrtho__TabContent').forEach(function(tabElement) {
        tabElement.classList.remove('naOrtho__TabContent--active');
    });
    document.querySelectorAll('.naOrtho__TabButton').forEach(function(tabButtonElement) {
        tabButtonElement.classList.remove('naOrtho__TabButton--active');
    });
    const targetTab = document.getElementById('tab-' + tabId);
    if (targetTab) targetTab.classList.add('naOrtho__TabContent--active');
    if (buttonElement) buttonElement.classList.add('naOrtho__TabButton--active');
}

na_runButtonElement.addEventListener('click', na_sendProjectionRequest);
if (na_exportButtonElement) na_exportButtonElement.addEventListener('click', na_sendExportRequest);
na_refreshButtonElement.addEventListener('click', na_sendRefreshScriptsRequest);
window.naShowTab = naShowTab;

if (typeof sketchup !== 'undefined' && sketchup.na_requestScenes) sketchup.na_requestScenes();
if (typeof sketchup !== 'undefined' && sketchup.na_jsLog) sketchup.na_jsLog('To Scale Ortho Texture Maker UI ready.');
