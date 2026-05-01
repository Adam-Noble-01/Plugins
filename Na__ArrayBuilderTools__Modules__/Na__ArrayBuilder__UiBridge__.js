// =============================================================================
// NA ARRAY BUILDER - UI BRIDGE (JavaScript <-> Ruby)
// =============================================================================
//
// FILE       : Na__ArrayBuilder__UiBridge__.js
// AUTHOR     : Noble Architecture
// VERSION    : 0.0.3
// PURPOSE    : Handles UI interactions and Ruby communication
//
// =============================================================================

// =============================================================================
// REGION | Default Configurations
// =============================================================================

var NA_DEFAULTS = {
    dentil: {
        type: 'dentil',
        unit_width_mm: 110,
        unit_depth_mm: 30,
        unit_height_mm: 75,
        spacing_mm: 115
    },
    dogtooth: {
        type: 'dogtooth',
        unit_width_mm: 65,
        unit_depth_mm: 102.5,
        unit_height_mm: 65,
        spacing_mm: 0
    },
    object: {
        type: 'object',
        spacing_mm: 0,
        anchor_mode: 'local_axis'
    }
};

var na_currentType   = 'dentil';
var na_currentAnchor = 'local_axis';

// endregion ===================================================================

// =============================================================================
// REGION | Type Selection
// =============================================================================

function na_selectType(type) {
    na_currentType = type;

    var btnDentil   = document.getElementById('na-btn-dentil');
    var btnDogtooth = document.getElementById('na-btn-dogtooth');
    var btnObject   = document.getElementById('na-btn-object');

    btnDentil.classList.toggle('na-active', type === 'dentil');
    btnDogtooth.classList.toggle('na-active', type === 'dogtooth');
    if (btnObject) btnObject.classList.toggle('na-active', type === 'object');

    na_toggleSourceSections(type);

    if (type === 'dentil' || type === 'dogtooth') {
        var defaults = NA_DEFAULTS[type];
        document.getElementById('na-unit-width').value  = defaults.unit_width_mm;
        document.getElementById('na-unit-depth').value  = defaults.unit_depth_mm;
        document.getElementById('na-unit-height').value = defaults.unit_height_mm;
        document.getElementById('na-spacing').value     = defaults.spacing_mm;
    }

    document.getElementById('na-preview-count').textContent  = '--';
    document.getElementById('na-preview-length').textContent = '--';
}

// FUNCTION | Toggle Dimensions vs Object-Source Sections
// ----------------------------------------------------------------------------
function na_toggleSourceSections(type) {
    var dimsSection = document.getElementById('na-dimensions-section');
    var objSection  = document.getElementById('na-object-source-section');

    if (!dimsSection || !objSection) return;

    if (type === 'object') {
        dimsSection.style.display = 'none';
        objSection.style.display  = 'block';
    } else {
        dimsSection.style.display = 'block';
        objSection.style.display  = 'none';
    }
}

// endregion ===================================================================

// =============================================================================
// REGION | Object Source (Pick / Clear / Anchor Mode)
// =============================================================================

function na_pickObject() {
    if (typeof sketchup !== 'undefined') {
        sketchup.na_pickObject();
    } else {
        console.log('[NA_ArrayBuilder] SketchUp not available (na_pickObject)');
    }
}

function na_clearObject() {
    if (typeof sketchup !== 'undefined') {
        sketchup.na_clearObject();
    } else {
        window.na_objectCleared();
    }
}

function na_setAnchorMode(mode) {
    na_currentAnchor = mode;

    var btnLocal  = document.getElementById('na-btn-anchor-local');
    var btnCentre = document.getElementById('na-btn-anchor-centre');

    if (btnLocal)  btnLocal.classList.toggle('na-active',  mode === 'local_axis');
    if (btnCentre) btnCentre.classList.toggle('na-active', mode === 'centre');
}

// endregion ===================================================================

// =============================================================================
// REGION | Start Placement
// =============================================================================

function na_startPlacement() {
    var normalise = document.getElementById('na-normalise').checked;
    var config;

    if (na_currentType === 'object') {
        config = na_buildObjectConfig(normalise);
    } else {
        config = na_buildBoxConfig(normalise);
    }

    var configJson = JSON.stringify(config);

    if (typeof sketchup !== 'undefined') {
        sketchup.na_startArray(configJson);
    } else {
        console.log('[NA_ArrayBuilder] SketchUp not available. Config:', configJson);
        window.na_showStatus('warning', 'SketchUp connection not available');
    }
}

// FUNCTION | Build Box-Mode Config (Dentil / Dog-Tooth)
// ----------------------------------------------------------------------------
function na_buildBoxConfig(normalise) {
    return {
        type:               na_currentType,
        unit_width_mm:      parseFloat(document.getElementById('na-unit-width').value)  || 110,
        unit_depth_mm:      parseFloat(document.getElementById('na-unit-depth').value)  || 30,
        unit_height_mm:     parseFloat(document.getElementById('na-unit-height').value) || 75,
        spacing_mm:         parseFloat(document.getElementById('na-spacing').value)     || 0,
        normalise_distance: normalise
    };
}

// FUNCTION | Build Object-Mode Config
// ----------------------------------------------------------------------------
// unit_*_mm are derived Ruby-side from the registered definition, so we only
// forward the spacing, anchor mode and normalise flag here.
function na_buildObjectConfig(normalise) {
    return {
        type:               'object',
        anchor_mode:        na_currentAnchor,
        spacing_mm:         parseFloat(document.getElementById('na-object-spacing').value) || 0,
        normalise_distance: normalise
    };
}

// endregion ===================================================================

// =============================================================================
// REGION | Ruby -> JavaScript Callbacks
// =============================================================================

window.na_showStatus = function(type, message) {
    var bar = document.getElementById('na-status-bar');
    if (!bar) return;

    bar.textContent = message;
    bar.className = 'na-status-bar na-status-' + type;

    if (type === 'success' || type === 'info') {
        clearTimeout(window._na_statusTimer);
        window._na_statusTimer = setTimeout(function() {
            bar.textContent = 'Ready';
            bar.className = 'na-status-bar na-status-info';
        }, 5000);
    }
};

window.na_arrayComplete = function(count) {
    window.na_showStatus('success', 'Created ' + count + ' units successfully');

    document.getElementById('na-preview-count').textContent  = count;
};

window.na_updatePreviewInfo = function(count, totalLengthMm, actualSpacingMm) {
    document.getElementById('na-preview-count').textContent  = count;
    document.getElementById('na-preview-length').textContent = totalLengthMm + ' mm';

    var spacingRow = document.getElementById('na-actual-spacing-row');
    var spacingVal = document.getElementById('na-actual-spacing');
    if (typeof actualSpacingMm === 'number' && actualSpacingMm >= 0) {
        spacingRow.style.display = 'flex';
        spacingVal.textContent = actualSpacingMm + ' mm';
    } else {
        spacingRow.style.display = 'none';
        spacingVal.textContent = '--';
    }
};

window.na_objectPicked = function(name, wMm, dMm, hMm) {
    var nameEl = document.getElementById('na-object-name');
    var wEl    = document.getElementById('na-object-w');
    var dEl    = document.getElementById('na-object-d');
    var hEl    = document.getElementById('na-object-h');
    var info   = document.getElementById('na-object-info');

    if (nameEl) nameEl.textContent = name || '<Unnamed>';
    if (wEl)    wEl.textContent    = wMm + ' mm';
    if (dEl)    dEl.textContent    = dMm + ' mm';
    if (hEl)    hEl.textContent    = hMm + ' mm';
    if (info)   info.classList.add('na-object-info-active');
};

window.na_objectCleared = function() {
    var nameEl = document.getElementById('na-object-name');
    var wEl    = document.getElementById('na-object-w');
    var dEl    = document.getElementById('na-object-d');
    var hEl    = document.getElementById('na-object-h');
    var info   = document.getElementById('na-object-info');

    if (nameEl) nameEl.textContent = 'No object selected';
    if (wEl)    wEl.textContent    = '--';
    if (dEl)    dEl.textContent    = '--';
    if (hEl)    hEl.textContent    = '--';
    if (info)   info.classList.remove('na-object-info-active');
};

// endregion ===================================================================
