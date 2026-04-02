// =============================================================================
// NA ARRAY BUILDER - UI BRIDGE (JavaScript <-> Ruby)
// =============================================================================
//
// FILE       : Na__ArrayBuilder__UiBridge__.js
// AUTHOR     : Noble Architecture
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
    }
};

var na_currentType = 'dentil';

// endregion ===================================================================

// =============================================================================
// REGION | Type Selection
// =============================================================================

function na_selectType(type) {
    na_currentType = type;

    var btnDentil = document.getElementById('na-btn-dentil');
    var btnDogtooth = document.getElementById('na-btn-dogtooth');

    btnDentil.classList.toggle('na-active', type === 'dentil');
    btnDogtooth.classList.toggle('na-active', type === 'dogtooth');

    var defaults = NA_DEFAULTS[type];
    if (defaults) {
        document.getElementById('na-unit-width').value  = defaults.unit_width_mm;
        document.getElementById('na-unit-depth').value   = defaults.unit_depth_mm;
        document.getElementById('na-unit-height').value  = defaults.unit_height_mm;
        document.getElementById('na-spacing').value      = defaults.spacing_mm;
    }

    document.getElementById('na-preview-count').textContent  = '--';
    document.getElementById('na-preview-length').textContent = '--';
}

// endregion ===================================================================

// =============================================================================
// REGION | Start Placement
// =============================================================================

function na_startPlacement() {
    var normalise = document.getElementById('na-normalise').checked;

    var config = {
        type:               na_currentType,
        unit_width_mm:      parseFloat(document.getElementById('na-unit-width').value)  || 110,
        unit_depth_mm:      parseFloat(document.getElementById('na-unit-depth').value)  || 30,
        unit_height_mm:     parseFloat(document.getElementById('na-unit-height').value) || 75,
        spacing_mm:         parseFloat(document.getElementById('na-spacing').value)     || 0,
        normalise_distance: normalise
    };

    var configJson = JSON.stringify(config);

    if (typeof sketchup !== 'undefined') {
        sketchup.na_startArray(configJson);
    } else {
        console.log('[NA_ArrayBuilder] SketchUp not available. Config:', configJson);
        window.na_showStatus('warning', 'SketchUp connection not available');
    }
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

// endregion ===================================================================
