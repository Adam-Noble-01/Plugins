/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - WINDOW SYSTEM - UI LOGIC (MAIN ORCHESTRATOR)
   =============================================================================
   
   FILE       : Na__AssemblyStudio__WindowSystem__UiSystem__MainUiLogic__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Main orchestration and state management
   CREATED    : 2026
   
   DESCRIPTION:
   - Orchestrates all UI and viewport modules
   - Manages global configuration state
   - Coordinates between UI changes and viewport rendering
   - Provides public API for external access (bridge)
   - Modular architecture with separated concerns
   
   DEPENDENCIES (load order matches Na__AssemblyStudio__UiLayout__.html):
   - Na__AssemblyStudio__WindowSystem__UiSystem__Config__.js
   - Na__AssemblyStudio__AppCore__UiSystem__Controls__.js
   - Na__AssemblyStudio__AppCore__UiSystem__Events__.js
   - Na__AssemblyStudio__Viewport__SvgHelpers__.js
   - Na__AssemblyStudio__Viewport__Validation__.js
   - Na__AssemblyStudio__WindowSystem__Viewport__SvgGenerator__.js   (exports window.Na__Viewport__SvgGenerator)
   - Na__AssemblyStudio__Viewport__Controls__.js
   - Na__AssemblyStudio__Viewport__Instance__.js
   - Na__AssemblyStudio__WindowSystem__UiSystem__Export__Dxf__.js
   
   NAMING CONVENTION:
   - All custom identifiers use Na_ or na_ prefix
   
   ============================================================================= */

// =============================================================================
// REGION | Dynamic UI Module
// =============================================================================

const Na_DynamicUI = (function() {
    
    // Module Variables
    // ------------------------------------------------------------
    let _config = {};                                                // Current configuration state
    let _updateCallback = null;                                      // External update callback function
    let _svgValid = false;                                           // SVG preview validation state
    
    // FUNCTION | Initialize the Dynamic UI
    // ------------------------------------------------------------
    function na_init() {
        console.log('[NA_UI] Initializing Dynamic UI');
        
        // Build primary controls
        na_buildControls('na-controls-primary', window.NA_UI_CONFIG);
        
        // Build glaze bar controls
        na_buildControls('na-controls-glazebars', window.NA_GLAZEBAR_CONFIG);
        
        // Build cill & frame controls
        na_buildControls('na-controls-cill-frame', window.NA_CILL_FRAME_CONFIG);
        
        // Build options controls
        na_buildControls('na-controls-options', window.NA_OPTIONS_CONFIG);
        
        // Build door panel controls
        na_buildControls('na-controls-door-panel', window.NA_DOOR_PANEL_CONFIG);

        // Build sliding-door controls (Phase-2: scaffolded under WindowSystem)
        na_buildControls('na-controls-sliding-door', window.NA_SLIDING_DOOR_CONFIG);

        // Build multi-folding-door controls (Phase-2: scaffolded under WindowSystem)
        na_buildControls('na-controls-multifold-door', window.NA_BIFOLD_DOOR_CONFIG);

        // Set default values
        na_setDefaults();
        
        // Initial render
        na_onConfigChange();
        
        console.log('[NA_UI] Dynamic UI initialized');
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Build Controls for a Container
    // ------------------------------------------------------------
    function na_buildControls(containerId, configArray) {
        const container = document.getElementById(containerId);
        if (!container) {
            console.error('[NA_UI] Container not found:', containerId);
            return;
        }
        
        container.innerHTML = '';
        
        configArray.forEach(config => {
            const controlHtml = window.Na__Ui__Controls.na_createControl(config);
            container.insertAdjacentHTML('beforeend', controlHtml);
        });
        
        // Attach event listeners with callback
        configArray.forEach(config => {
            window.Na__Ui__Events.na_attachEventListeners(config, na_onControlChange);
        });
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Set Default Values
    // ------------------------------------------------------------
    function na_setDefaults() {
        [window.NA_UI_CONFIG, window.NA_GLAZEBAR_CONFIG, window.NA_CILL_FRAME_CONFIG, window.NA_OPTIONS_CONFIG, window.NA_DOOR_PANEL_CONFIG, window.NA_SLIDING_DOOR_CONFIG, window.NA_BIFOLD_DOOR_CONFIG].forEach(config => {
            config.forEach(item => {
                _config[item.id] = item.default;
                
                // Handle expandable controls with children
                if (item.type === 'expandable' && item.children) {
                    item.children.forEach(childConfig => {
                        _config[childConfig.id] = childConfig.default;
                    });
                }
            });
        });
        
        // Initialize removed_casements array (tracks which openings have casements removed)
        _config.removed_casements = [];
        _config.removed_transom_segments = [];
        _config.removed_glazebars = [];
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Called When a Control Value Changes (Callback from Events Module)
    // ------------------------------------------------------------
    function na_onControlChange(id, value) {
        const previousValue = _config[id];
        const normalizedValue = na_isTransomHeightControl(id)
            ? na_convertUiTransomHeightToInternal(value)
            : value;
        _config[id] = normalizedValue;

        if (id === 'transoms') {
            na_applyTransomDefaultsForCountChange(previousValue, value);
        }

        // Mutual exclusivity between the three door-mode flags. When one
        // mode toggles ON, the other two toggle OFF so the user cannot
        // emit a hybrid window+sliding+bifold artefact. Touching the
        // _config Hash AND the live DOM toggle classes keeps the visual
        // state in sync without re-running na_buildControls.
        if (value === true && (id === 'door_mode' || id === 'sliding_mode' || id === 'multifold_mode')) {
            ['door_mode', 'sliding_mode', 'multifold_mode'].forEach(otherId => {
                if (otherId === id) return;
                if (_config[otherId] === true) {
                    _config[otherId] = false;
                    const otherToggle = document.getElementById(`${otherId}-toggle`);
                    if (otherToggle) {
                        otherToggle.dataset.value = 'false';
                        otherToggle.classList.remove('na-active');
                    }
                }
            });

            // Seed door-appropriate default dimensions so the user starts
            // with a valid door opening rather than the window defaults
            // (900 x 1200mm), which would trigger validation errors.
            na_applyDoorModeDefaultDimensions(id);
        }

        na_onConfigChange();
    }
    // ---------------------------------------------------------------

    // FUNCTION | Resolve Effective Frame Thicknesses
    // ------------------------------------------------------------
    function na_getEffectiveFrameThicknesses(config = _config) {
        const uniformThickness = (config.frame_thickness_mm != null)
            ? Number(config.frame_thickness_mm)
            : 50;
        const useAdvancedFrameControls = config.advanced_frame_controls === true;

        function na_resolveFrameSideThickness(sideKey) {
            const rawValue = useAdvancedFrameControls ? config[sideKey] : uniformThickness;
            const numericValue = Number(rawValue != null ? rawValue : uniformThickness);
            return Math.max(0, numericValue);
        }

        const frameThicknesses = {
            top: na_resolveFrameSideThickness('frame_top_thickness_mm'),
            bottom: na_resolveFrameSideThickness('frame_bottom_thickness_mm'),
            left: na_resolveFrameSideThickness('frame_left_thickness_mm'),
            right: na_resolveFrameSideThickness('frame_right_thickness_mm')
        };

        frameThicknesses.isFullyFrameless =
            frameThicknesses.top === 0 &&
            frameThicknesses.bottom === 0 &&
            frameThicknesses.left === 0 &&
            frameThicknesses.right === 0;

        return frameThicknesses;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Get Inner Frame Width in Millimetres
    // ------------------------------------------------------------
    function na_getInnerFrameWidthMm() {
        const frameThicknesses = na_getEffectiveFrameThicknesses();
        return Math.max(0, (_config.width_mm || 900) - frameThicknesses.left - frameThicknesses.right);
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Called When Any Config Value Changes
    // ------------------------------------------------------------
    function na_onConfigChange() {
        na_updateSlidingSashOverlapVisibility();
        na_updateDoorPanelVisibility();
        na_updateSlidingDoorVisibility();
        na_updateMultifoldDoorVisibility();
        na_updateTransomControlVisibility();
        na_updateWindowOnlyControlsVisibility();                                // <-- Phase 9: Hide casement/mullion/transom/sliding-sash controls in bifold/sliding mode
        na_updateWidthSliderRange();                                            // <-- Phase 10: Expand width to 8000mm in multi-leaf door modes
        na_normalizeTransomConfig();
        ['transom_1_y_mm', 'transom_2_y_mm', 'transom_3_y_mm'].forEach(controlId => {
            if (_config[controlId] != null) {
                na_updateControlValue(controlId, _config[controlId]);
            }
        });

        // Disable cill interaction whenever there is no effective bottom frame to support it,
        // but preserve the user's cill preference so it comes back automatically.
        const frameThicknesses = na_getEffectiveFrameThicknesses();
        const isBottomFrameless = frameThicknesses.bottom === 0;
        const cillToggle = document.getElementById('has_cill-toggle');
        if (isBottomFrameless) {
            if (cillToggle) {
                cillToggle.style.opacity = '0.4';
                cillToggle.style.pointerEvents = 'none';
            }
        } else {
            if (cillToggle) {
                cillToggle.style.opacity = '';
                cillToggle.style.pointerEvents = '';
            }
        }
        
        // Guard: clamp glazebar_inset to prevent impossible geometry
        // bar_depth = casement_depth - 2*inset must be >= glass_thickness
        const casementDepth = _config.casement_depth_mm || 55;
        const glassThickness = _config.glass_thickness_mm || 20;
        const maxGlazebarInset = Math.floor((casementDepth - glassThickness) / 2);
        const clampedMax = Math.max(0, Math.min(20, maxGlazebarInset));
        if ((_config.glazebar_inset_mm || 0) > clampedMax) {
            _config.glazebar_inset_mm = clampedMax;
            na_updateControlValue('glazebar_inset_mm', clampedMax);
        }
        
        const numOpenings = (_config.mullions || 0) + 1;

        if (!Array.isArray(_config.removed_casements)) {
            _config.removed_casements = [];
        }
        if (_config.removed_casements.length > 0) {
            _config.removed_casements = na_migrateLegacyRemovedCasements(_config.removed_casements);
            const validCasementKeys = na_getValidCasementKeySet();
            _config.removed_casements = _config.removed_casements.filter(key => validCasementKeys.has(key));
        }

        const transomCount = Math.max(0, Math.min(3, Math.round(_config.transoms || 0)));
        if (!Array.isArray(_config.removed_transom_segments)) {
            _config.removed_transom_segments = [];
        }
        _config.removed_transom_segments = _config.removed_transom_segments.filter(segmentKey => {
            const [openingIndex, transomIndex] = String(segmentKey).split(':').map(value => parseInt(value, 10));
            return !isNaN(openingIndex) &&
                !isNaN(transomIndex) &&
                openingIndex >= 0 &&
                openingIndex < numOpenings &&
                transomIndex >= 0 &&
                transomIndex < transomCount;
        });

        // Clean up removed_glazebars when the visible panel/cell/sash/bar layout changes
        if (!Array.isArray(_config.removed_glazebars)) {
            _config.removed_glazebars = [];
        }
        const validGlazebarKeys = na_getValidGlazebarKeySet();
        _config.removed_glazebars = _config.removed_glazebars
            .map(key => String(key))
            .filter(key => validGlazebarKeys.has(key));
        
        // Update 2D viewport and validate
        _svgValid = Na_Viewport.na_render(_config);
        
        // Update button states based on SVG validity
        na_updateButtonStates();
        
        // Call external callback if set
        if (_updateCallback) {
            _updateCallback(_config);
        }
        
        // Send live update to SketchUp if Live Mode is enabled
        if (typeof na_sendLiveUpdate === 'function') {
            na_sendLiveUpdate();
        }
    }
    // ---------------------------------------------------------------

    // FUNCTION | Toggle Sliding Sash Overlap Slider Visibility
    // ------------------------------------------------------------
    function na_updateSlidingSashOverlapVisibility() {
        const overlapControl = document.querySelector('[data-control-id="sliding_sash_overlap_mm"]');
        if (!overlapControl) return;

        const showOverlapControl = _config.sliding_sash_window === true;
        overlapControl.style.display = showOverlapControl ? '' : 'none';
    }
    // ---------------------------------------------------------------

    // FUNCTION | Toggle Door Panel Section Visibility
    // ------------------------------------------------------------
    function na_updateDoorPanelVisibility() {
        const doorPanelSection = document.getElementById('na-section-door-panel');
        if (!doorPanelSection) return;

        const isDoorMode = _config.door_mode === true;
        doorPanelSection.style.display = isDoorMode ? '' : 'none';

        const trimExpandable = document.querySelector('[data-control-id="door_panel_trim_controls"]');
        if (trimExpandable) {
            const showTrim = _config.door_panel_show_trim === true;
            trimExpandable.style.display = showTrim ? '' : 'none';
        }
    }
    // ---------------------------------------------------------------

    // FUNCTION | Toggle Sliding-Door Section Visibility (Phase-2)
    // ------------------------------------------------------------
    function na_updateSlidingDoorVisibility() {
        const slidingSection = document.getElementById('na-section-sliding-door');
        if (!slidingSection) return;
        slidingSection.style.display = (_config.sliding_mode === true) ? '' : 'none';
    }
    // ---------------------------------------------------------------

    // FUNCTION | Toggle Multi-Folding-Door Section Visibility (Phase-2)
    // ------------------------------------------------------------
    // Also drives the per-layout sub-control visibility:
    //   * `bifold_door_open_side`   visible only when layout = AllOneWay
    //   * `bifold_door_master_side` visible only when layout = MasterSlaves
    //   * EqualEqual layout shows neither
    function na_updateMultifoldDoorVisibility() {
        const multifoldSection = document.getElementById('na-section-multifold-door');
        if (!multifoldSection) return;
        const isMultifoldMode = _config.multifold_mode === true;
        multifoldSection.style.display = isMultifoldMode ? '' : 'none';
        if (!isMultifoldMode) return;

        const layout = _config.bifold_door_layout || 'EqualEqual';
        const openSideControl   = document.querySelector('[data-control-id="bifold_door_open_side"]');
        const masterSideControl = document.querySelector('[data-control-id="bifold_door_master_side"]');
        if (openSideControl)   openSideControl.style.display   = (layout === 'AllOneWay')    ? '' : 'none';
        if (masterSideControl) masterSideControl.style.display = (layout === 'MasterSlaves') ? '' : 'none';
    }
    // ---------------------------------------------------------------

    // FUNCTION | Toggle Transom Slider Visibility
    // ------------------------------------------------------------
    function na_updateTransomControlVisibility() {
        const transomCount = Math.max(0, Math.min(3, Math.round(_config.transoms || 0)));
        const transomWidthControl = document.querySelector('[data-control-id="transom_width_mm"]');

        if (transomWidthControl) {
            transomWidthControl.style.display = transomCount > 0 ? '' : 'none';
        }

        ['transom_1_y_mm', 'transom_2_y_mm', 'transom_3_y_mm'].forEach((controlId, index) => {
            const control = document.querySelector(`[data-control-id="${controlId}"]`);
            if (!control) return;
            control.style.display = index < transomCount ? '' : 'none';
        });
    }
    // ---------------------------------------------------------------

    // FUNCTION | Hide Window-Only Controls in Bifold / Sliding Mode (Phase 9)
    // ------------------------------------------------------------
    // Bifold + sliding doors share the window's Dimensions, Cill & Frame,
    // Glaze Bars and Options sections wholesale — but a number of
    // window-only controls (casements, mullions, transoms, sliding sash
    // overlap) make no sense for a multi-panel door. This helper runs
    // last after the specialised visibility helpers and force-hides
    // those controls when `multifold_mode === true || sliding_mode === true`.
    // In window-mode it restores the always-visible window controls
    // (the dynamic ones — transom_*, sliding_sash_overlap_mm — are
    // managed by their own specialised helpers above).
    function na_updateWindowOnlyControlsVisibility() {
        const inDoorMode = (_config.multifold_mode === true) || (_config.sliding_mode === true);

        const alwaysWindowOnlyIds = [
            'casement_width_mm',                                                // <-- Casement controls (single + advanced)
            'casement_sizes_individual',                                        // <-- Casement individual rail/stile expandable
            'advanced_casement_controls',                                       // <-- Casement depth/inset/glazing thickness expandable
            'mullions',                                                         // <-- Window-only (split openings)
            'mullion_width_mm',                                                 // <-- Window-only mullion thickness
            'transoms',                                                         // <-- Window-only (split openings vertically)
            'show_casements',                                                   // <-- Casement-specific toggle
            'sliding_sash_window'                                               // <-- Sliding sash window mode toggle (distinct from sliding_mode door)
        ];

        const dynamicWindowOnlyIds = [
            'transom_width_mm',                                                 // <-- Managed by transom count in window mode
            'transom_1_y_mm',
            'transom_2_y_mm',
            'transom_3_y_mm',
            'sliding_sash_overlap_mm'                                           // <-- Managed by sliding_sash_window toggle in window mode
        ];

        alwaysWindowOnlyIds.forEach(id => {
            const control = document.querySelector(`[data-control-id="${id}"]`);
            if (!control) return;
            control.style.display = inDoorMode ? 'none' : '';
        });

        if (inDoorMode) {
            dynamicWindowOnlyIds.forEach(id => {
                const control = document.querySelector(`[data-control-id="${id}"]`);
                if (control) control.style.display = 'none';
            });
        }
    }
    // ---------------------------------------------------------------

    // FUNCTION | Expand Width Slider Range in Multi-Leaf Door Modes (Phase-10)
    // ------------------------------------------------------------
    // Windows and single exterior doors: max 4000mm (sensible structural span).
    // Multi-folding / sliding door sets: max 8000mm (wide opening systems).
    // Called from na_onConfigChange for interactive mode-flag changes and from
    // na_updateControlValue before setting the slider value on load so the
    // browser cannot silently clamp a saved bifold/sliding width above 4000mm.
    function na_updateWidthSliderRange() {
        const slider = document.getElementById('width_mm-slider');
        const input  = document.getElementById('width_mm-input');
        if (!slider) return;

        const prevMax = Number(slider.max);
        na_applyWidthSliderRange(slider, input);
        const newMax  = Number(slider.max);

        // If the range just shrank (door mode → window mode) clamp the stored
        // value and refresh the control so it stays consistent.
        if (newMax < prevMax && _config.width_mm > newMax) {
            _config.width_mm = newMax;
            na_updateControlValue('width_mm', newMax);
        }
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Apply the Correct Max to a Width Slider + Input Pair
    // ------------------------------------------------------------
    function na_applyWidthSliderRange(slider, input) {
        const inDoorMode = (_config.multifold_mode === true) || (_config.sliding_mode === true);
        const newMax     = inDoorMode ? 8000 : 4000;                        // <-- 8 m for door sets, 4 m for windows
        slider.max       = newMax;
        if (input) input.max = newMax;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Seed Default Dimensions When a Door Mode Is Activated (Phase-10)
    // ------------------------------------------------------------
    // Called only from the manual toggle path in na_onControlChange — NOT from
    // na_setConfig — so a saved door loaded from SketchUp keeps its stored
    // dimensions while a freshly toggled mode always starts at a sensible door
    // opening rather than the window defaults (900 x 1200mm).
    //
    // Default heights per mode:
    //   door_mode      : 2100 mm  (standard single exterior door leaf height)
    //   sliding_mode   : 2100 mm  (standard sliding patio/bi-pass height)
    //   multifold_mode : 2100 mm  (standard bifold/multi-fold height)
    //
    // Default widths per mode:
    //   door_mode      : 1000 mm  (standard single door leaf)
    //   sliding_mode   : 3000 mm  (typical two-panel sliding set)
    //   multifold_mode : 3000 mm  (typical four-panel bifold set)
    function na_applyDoorModeDefaultDimensions(modeId) {
        const defaultWidth  = (modeId === 'door_mode') ? 1000 : 3000;      // <-- Single door vs multi-panel set
        const defaultHeight = 2100;                                          // <-- Standard door height for all door modes

        _config.height_mm = defaultHeight;
        _config.width_mm  = defaultWidth;

        na_updateControlValue('height_mm', defaultHeight);
        na_updateControlValue('width_mm',  defaultWidth);
    }
    // ---------------------------------------------------------------

    // FUNCTION | Check Transom Height Control
    // ------------------------------------------------------------
    function na_isTransomHeightControl(id) {
        return id === 'transom_1_y_mm' || id === 'transom_2_y_mm' || id === 'transom_3_y_mm';
    }
    // ---------------------------------------------------------------

    // FUNCTION | Get Inner Frame Height in Millimetres
    // ------------------------------------------------------------
    function na_getInnerFrameHeightMm() {
        const frameThicknesses = na_getEffectiveFrameThicknesses();
        return Math.max(0, (_config.height_mm || 1200) - frameThicknesses.top - frameThicknesses.bottom);
    }
    // ---------------------------------------------------------------

    // FUNCTION | Get Transom Width in Millimetres
    // ------------------------------------------------------------
    function na_getTransomWidthMm() {
        return Math.max(1, _config.transom_width_mm || 40);
    }
    // ---------------------------------------------------------------

    // FUNCTION | Convert UI Transom Height to Internal Bottom-Origin Value
    // ------------------------------------------------------------
    // UI shows the top section height; internal config stores transom bottom from the bottom.
    function na_convertUiTransomHeightToInternal(uiValue) {
        const innerHeight = na_getInnerFrameHeightMm();
        const transomWidth = na_getTransomWidthMm();
        return innerHeight - Number(uiValue || 0) - transomWidth;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Convert Internal Transom Height to UI Value
    // ------------------------------------------------------------
    function na_convertInternalTransomHeightToUi(internalValue) {
        const innerHeight = na_getInnerFrameHeightMm();
        const transomWidth = na_getTransomWidthMm();
        return innerHeight - Number(internalValue || 0) - transomWidth;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Get Minimum Clear Cell Height
    // ------------------------------------------------------------
    function na_getMinimumTransomCellHeight() {
        const casementWidth = _config.casement_width_mm || 65;
        const useIndividualSizes = _config.casement_sizes_individual === true;
        const casTopRail = useIndividualSizes ? (_config.casement_top_rail_mm || casementWidth) : casementWidth;
        const casBottomRail = useIndividualSizes ? (_config.casement_bottom_rail_mm || casementWidth) : casementWidth;
        const minSingleSashHeight = (_config.show_casements !== false) ? (casTopRail + casBottomRail + 50) : 50;

        if (_config.show_casements !== false && _config.sliding_sash_window === true) {
            return minSingleSashHeight * 2;
        }

        return minSingleSashHeight;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Normalize Transom Positions
    // ------------------------------------------------------------
    // Keeps active transom heights ordered and within the available inner opening.
    function na_normalizeTransomConfig() {
        const transomCount = Math.max(0, Math.min(3, Math.round(_config.transoms || 0)));
        const innerHeight = na_getInnerFrameHeightMm();
        const transomWidth = na_getTransomWidthMm();
        const minCellHeight = na_getMinimumTransomCellHeight();
        const transomIds = ['transom_1_y_mm', 'transom_2_y_mm', 'transom_3_y_mm'];
        let nextCellStart = 0;

        transomIds.forEach((controlId, index) => {
            if (index >= transomCount) return;

            const remainingTransoms = transomCount - index - 1;
            const rawValue = Number(_config[controlId]);
            const fallbackValue = index === 0 ? 300 : (_config[transomIds[index - 1]] + transomWidth + minCellHeight);
            const minValue = nextCellStart + minCellHeight;
            const maxValue = innerHeight - ((remainingTransoms + 1) * transomWidth) - ((remainingTransoms + 1) * minCellHeight);
            const clampedMax = Math.max(minValue, maxValue);
            const clampedValue = Math.max(minValue, Math.min(clampedMax, Number.isFinite(rawValue) ? rawValue : fallbackValue));

            if (_config[controlId] !== clampedValue) {
                _config[controlId] = clampedValue;
                na_updateControlValue(controlId, clampedValue);
            }

            nextCellStart = clampedValue + transomWidth;
        });
    }
    // ---------------------------------------------------------------

    // FUNCTION | Apply Friendly Transom Defaults
    // ------------------------------------------------------------
    // When a single transom is first enabled, seed it to a typical one-third height.
    function na_applyTransomDefaultsForCountChange(previousCount, newCount) {
        const previous = Math.max(0, Math.min(3, Math.round(previousCount || 0)));
        const next = Math.max(0, Math.min(3, Math.round(newCount || 0)));

        if (previous === 0 && next === 1) {
            const oneThirdTopSectionHeight = Math.round((na_getInnerFrameHeightMm() / 3) / 10) * 10;
            const internalValue = na_convertUiTransomHeightToInternal(oneThirdTopSectionHeight);
            _config.transom_1_y_mm = internalValue;
            na_updateControlValue('transom_1_y_mm', internalValue);
        }
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Build Casement Storage Key
    // ------------------------------------------------------------
    function na_getCasementKey(openingIndex, cellIndex, panelIndex) {
        return `${openingIndex}:${cellIndex}:${panelIndex}`;             // <-- Per-panel removal key
    }
    // ---------------------------------------------------------------

    // FUNCTION | Toggle Casement Removal for a Specific Panel
    // ------------------------------------------------------------
    // Adds or removes a per-panel key (openingIndex:cellIndex:panelIndex) from
    // removed_casements. Called by Na_Viewport when user clicks a casement panel.
    function na_toggleCasementRemoval(openingIndex, cellIndex, panelIndex) {
        if (!Array.isArray(_config.removed_casements)) {
            _config.removed_casements = [];
        }

        _config.removed_casements = na_migrateLegacyRemovedCasements(_config.removed_casements); // <-- Migrate before toggle

        const panelKey = na_getCasementKey(openingIndex, cellIndex, panelIndex);
        const existingIndex = _config.removed_casements.indexOf(panelKey);

        if (existingIndex === -1) {
            _config.removed_casements.push(panelKey);
            console.log(`[NA_UI] Removed casement panel ${panelKey}`);
        } else {
            _config.removed_casements.splice(existingIndex, 1);
            console.log(`[NA_UI] Restored casement panel ${panelKey}`);
        }

        na_onConfigChange();
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Migrate Legacy Bare-Integer Removed Casements to Per-Panel Keys
    // ---------------------------------------------------------------
    // Legacy data: removed_casements stored bare integers per-opening.
    // New data: stores "openingIndex:cellIndex:panelIndex" keys.
    // Bare integers expand to keys for every current cell/panel of that opening.
    function na_migrateLegacyRemovedCasements(removedCasements) {
        if (!Array.isArray(removedCasements) || removedCasements.length === 0) return [];

        const expandedKeys = new Set();                                  // <-- Deduplicate during migration
        const legacyOpeningIndices = [];

        removedCasements.forEach(entry => {
            if (entry === null || entry === undefined) return;
            const stringValue = String(entry);
            if (stringValue.indexOf(':') !== -1) {
                expandedKeys.add(stringValue);                           // <-- Already keyed
                return;
            }

            const numericValue = Number(stringValue);
            if (Number.isFinite(numericValue) && numericValue >= 0) {
                legacyOpeningIndices.push(Math.trunc(numericValue));     // <-- Defer expansion until layout known
            }
        });

        if (legacyOpeningIndices.length > 0) {
            const layoutKeysByOpening = na_buildPanelKeysByOpening();    // <-- Layout-aware expansion
            legacyOpeningIndices.forEach(openingIndex => {
                const keysForOpening = layoutKeysByOpening.get(openingIndex);
                if (!keysForOpening) return;
                keysForOpening.forEach(panelKey => expandedKeys.add(panelKey));
            });
        }

        return Array.from(expandedKeys);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Build Map Of Panel Keys Grouped By Opening Index
    // ---------------------------------------------------------------
    function na_buildPanelKeysByOpening() {
        const keysByOpening = new Map();
        const allKeys = na_collectValidCasementKeys();

        allKeys.forEach(key => {
            const openingIndex = Number(String(key).split(':')[0]);
            if (!Number.isFinite(openingIndex)) return;
            if (!keysByOpening.has(openingIndex)) {
                keysByOpening.set(openingIndex, []);
            }
            keysByOpening.get(openingIndex).push(key);
        });

        return keysByOpening;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Collect Valid Casement Panel Keys From Current Layout
    // ------------------------------------------------------------
    function na_collectValidCasementKeys() {
        const generator = window.Na__Viewport__SvgGenerator;
        if (!generator ||
            typeof generator.na_getOpeningCellLayout !== 'function' ||
            typeof generator.na_getActiveTransomBottoms !== 'function' ||
            typeof generator.na_getRemovedTransomSegmentSet !== 'function' ||
            typeof generator.na_getEffectiveFrameThicknesses !== 'function') {
            return [];
        }

        const config = _config;
        const frameThicknesses = generator.na_getEffectiveFrameThicknesses(config);
        const numMullions = config.mullions || 0;
        const mullionWidth = config.mullion_width_mm || 40;
        const transomCount = Math.max(0, Math.min(3, Math.round(config.transoms || 0)));
        const transomWidth = config.transom_width_mm || 40;
        const transomBottoms = generator.na_getActiveTransomBottoms(config, transomCount);
        const removedTransomSegments = generator.na_getRemovedTransomSegmentSet(config.removed_transom_segments);
        const casementsPerOpening = Math.max(1, Math.min(6, config.casements_per_opening || 1));

        const numOpenings = numMullions + 1;
        const innerWidth = (config.width_mm || 900) - frameThicknesses.left - frameThicknesses.right;
        const innerHeight = (config.height_mm || 1200) - frameThicknesses.top - frameThicknesses.bottom;
        const totalMullionWidth = numMullions * mullionWidth;
        const availableWidth = innerWidth - totalMullionWidth;
        const openingWidth = availableWidth / numOpenings;

        const validKeys = [];

        for (let openingIndex = 0; openingIndex < numOpenings; openingIndex++) {
            const openingX = frameThicknesses.left + (openingIndex * (openingWidth + mullionWidth));
            const openingY = frameThicknesses.bottom;
            const openingLayout = generator.na_getOpeningCellLayout(
                openingIndex,
                openingX,
                openingY,
                openingWidth,
                innerHeight,
                transomBottoms,
                transomWidth,
                removedTransomSegments
            );

            openingLayout.cells.forEach((cell, cellIndex) => {
                for (let panelIndex = 0; panelIndex < casementsPerOpening; panelIndex++) {
                    validKeys.push(na_getCasementKey(openingIndex, cellIndex, panelIndex));
                }
            });
        }

        return validKeys;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Build Valid Casement Key Set
    // ------------------------------------------------------------
    function na_getValidCasementKeySet() {
        return new Set(na_collectValidCasementKeys());
    }
    // ---------------------------------------------------------------

    // FUNCTION | Build Transom Segment Storage Key
    // ------------------------------------------------------------
    function na_getTransomSegmentKey(openingIndex, transomIndex) {
        return `${openingIndex}:${transomIndex}`;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Build Glaze Bar Storage Key
    // ------------------------------------------------------------
    function na_getGlazebarKey(openingIndex, cellIndex, panelIndex, sashIndex, orientation, barIndex) {
        return `${openingIndex}:${cellIndex}:${panelIndex}:${sashIndex}:${orientation}:${barIndex}`;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Collect Valid Glaze Bar Keys
    // ------------------------------------------------------------
    function na_getValidGlazebarKeySet() {
        if (!window.Na__Viewport__SvgGenerator ||
            typeof window.Na__Viewport__SvgGenerator.na_collectValidGlazebarKeys !== 'function') {
            return new Set();
        }

        return new Set(window.Na__Viewport__SvgGenerator.na_collectValidGlazebarKeys(_config));
    }
    // ---------------------------------------------------------------

    // FUNCTION | Toggle Transom Segment Removal
    // ------------------------------------------------------------
    function na_toggleTransomSegmentRemoval(openingIndex, transomIndex) {
        if (!Array.isArray(_config.removed_transom_segments)) {
            _config.removed_transom_segments = [];
        }

        const segmentKey = na_getTransomSegmentKey(openingIndex, transomIndex);
        const existingIndex = _config.removed_transom_segments.indexOf(segmentKey);

        if (existingIndex === -1) {
            _config.removed_transom_segments.push(segmentKey);
            console.log(`[NA_UI] Removed transom ${transomIndex} from opening ${openingIndex}`);
        } else {
            _config.removed_transom_segments.splice(existingIndex, 1);
            console.log(`[NA_UI] Restored transom ${transomIndex} to opening ${openingIndex}`);
        }

        na_onConfigChange();
    }
    // ---------------------------------------------------------------

    // FUNCTION | Toggle Individual Glaze Bar Removal
    // ------------------------------------------------------------
    function na_toggleGlazebarRemoval(openingIndex, cellIndex, panelIndex, sashIndex, orientation, barIndex) {
        if (!Array.isArray(_config.removed_glazebars)) {
            _config.removed_glazebars = [];
        }

        const glazebarKey = na_getGlazebarKey(openingIndex, cellIndex, panelIndex, sashIndex, orientation, barIndex);
        const existingIndex = _config.removed_glazebars.indexOf(glazebarKey);

        if (existingIndex === -1) {
            _config.removed_glazebars.push(glazebarKey);
            console.log(`[NA_UI] Removed glaze bar ${glazebarKey}`);
        } else {
            _config.removed_glazebars.splice(existingIndex, 1);
            console.log(`[NA_UI] Restored glaze bar ${glazebarKey}`);
        }

        na_onConfigChange();
    }
    // ---------------------------------------------------------------

    // FUNCTION | Check If Any Elements Are Hidden
    // ------------------------------------------------------------
    function na_hasHiddenElements() {
        const removedCasementsCount = Array.isArray(_config.removed_casements) ? _config.removed_casements.length : 0;
        const removedTransomSegmentsCount = Array.isArray(_config.removed_transom_segments) ? _config.removed_transom_segments.length : 0;
        const removedGlazebarsCount = Array.isArray(_config.removed_glazebars) ? _config.removed_glazebars.length : 0;

        return removedCasementsCount > 0 ||
            removedTransomSegmentsCount > 0 ||
            removedGlazebarsCount > 0;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Reset Hidden Elements
    // ------------------------------------------------------------
    function na_resetHiddenElements() {
        _config.removed_casements = [];
        _config.removed_transom_segments = [];
        _config.removed_glazebars = [];

        console.log('[NA_UI] Reset all hidden element state');
        na_onConfigChange();
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Update Button States Based on SVG Validity
    // ------------------------------------------------------------
    function na_updateButtonStates() {
        const createBtn = document.getElementById('na-btn-create');
        const updateBtn = document.getElementById('na-btn-update');
        const resetElementsBtn = document.getElementById('na-btn-reset-elements');
        
        if (createBtn) {
            if (_svgValid) {
                createBtn.disabled = false;
                createBtn.classList.remove('na-btn-disabled');
            } else {
                createBtn.disabled = true;
                createBtn.classList.add('na-btn-disabled');
            }
        }
        
        if (updateBtn) {
            if (_svgValid) {
                updateBtn.disabled = false;
                updateBtn.classList.remove('na-btn-disabled');
            } else {
                updateBtn.disabled = true;
                updateBtn.classList.add('na-btn-disabled');
            }
        }

        if (resetElementsBtn) {
            const hasHiddenElements = na_hasHiddenElements();
            resetElementsBtn.disabled = !hasHiddenElements;
            resetElementsBtn.classList.toggle('na-btn-disabled', !hasHiddenElements);
        }
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Check if SVG Preview is Valid
    // ------------------------------------------------------------
    function na_isSvgValid() {
        return _svgValid;
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Get Current Configuration
    // ------------------------------------------------------------
    function na_getConfig() {
        return { ..._config };
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Set Configuration
    // ------------------------------------------------------------
    function na_setConfig(newConfig) {
        _config = { ..._config, ...newConfig };
        
        // Update all UI controls
        Object.keys(newConfig).forEach(key => {
            na_updateControlValue(key, newConfig[key]);
        });
        
        // Trigger render
        na_onConfigChange();
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Update a Single Control's Displayed Value
    // ------------------------------------------------------------
    function na_updateControlValue(id, value) {
        // Try slider
        const slider = document.getElementById(`${id}-slider`);
        const input = document.getElementById(`${id}-input`);
        const display = document.getElementById(`${id}-display`);
        
        if (slider) {
            // Expand/contract width_mm range before assigning .value so the
            // browser doesn't silently clamp a bifold/sliding width > 4000mm.
            if (id === 'width_mm') na_applyWidthSliderRange(slider, input);

            const uiValue = na_isTransomHeightControl(id)
                ? na_convertInternalTransomHeightToUi(value)
                : value;
            slider.value = uiValue;
            if (input) input.value = uiValue;
            
            // Find config in main arrays or in expandable children
            const allConfigArrays = [window.NA_UI_CONFIG, window.NA_GLAZEBAR_CONFIG, window.NA_CILL_FRAME_CONFIG, window.NA_DOOR_PANEL_CONFIG, window.NA_SLIDING_DOOR_CONFIG, window.NA_BIFOLD_DOOR_CONFIG];
            let config = allConfigArrays.flat().find(c => c.id === id);
            if (!config) {
                // Search in expandable children across all config arrays
                for (const configArray of allConfigArrays) {
                    for (const parentConfig of configArray) {
                        if (parentConfig.type === 'expandable' && parentConfig.children) {
                            config = parentConfig.children.find(c => c.id === id);
                            if (config) break;
                        }
                    }
                    if (config) break;
                }
            }
            if (display && config) {
                display.textContent = `${uiValue}${config.unit}`;
            }
            return;
        }
        
        // Try toggle
        const toggle = document.getElementById(`${id}-toggle`);
        if (toggle) {
            toggle.dataset.value = value;
            toggle.classList.toggle('na-active', value);
            return;
        }
        
        // Try color picker
        const colorPicker = document.getElementById(`${id}-color`);
        if (colorPicker) {
            colorPicker.value = value;
            if (display) display.textContent = value;
            return;
        }
        
        // Try material cards
        const cardsContainer = document.getElementById(`${id}-cards`);
        if (cardsContainer) {
            const cards = cardsContainer.querySelectorAll('.na-material-card');
            cards.forEach(card => {
                if (card.dataset.materialId === value) {
                    card.classList.add('na-material-card-selected');
                } else {
                    card.classList.remove('na-material-card-selected');
                }
            });
            return;
        }
        
        // Try expandable header (for expanded state)
        const expandableHeader = document.getElementById(`${id}-header`);
        const expandableContent = document.getElementById(`${id}-content`);
        if (expandableHeader && expandableContent) {
            expandableHeader.dataset.expanded = value;
            expandableHeader.classList.toggle('na-expanded', value);
            expandableContent.classList.toggle('na-expanded', value);
            return;
        }

        // Try select dropdown
        const selectEl = document.getElementById(`${id}-select`);
        if (selectEl) {
            selectEl.value = value;                                          // <-- Reflects stored layout on selection
            return;
        }

        // Try binary toggle (Left | Right two-option switch)
        const btoggle = document.getElementById(`${id}-btoggle`);
        if (btoggle) {
            btoggle.dataset.value = value;
            const isRight = (value === btoggle.dataset.rightValue);          // <-- Match against rendered right-option value
            btoggle.classList.toggle('na-binary-toggle--right', isRight);
            btoggle.classList.toggle('na-binary-toggle--left',  !isRight);
            return;
        }
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Set Update Callback
    // ------------------------------------------------------------
    function na_setUpdateCallback(callback) {
        _updateCallback = callback;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Rebuild the Frame Finish Control After Live Swatches Arrive
    // ------------------------------------------------------------
    // Called by Na_FrameFinishCards once Ruby pushes window.NA_FRAME_FINISH_SWATCHES.
    // Locates the existing frame_material_id wrapper inside na-controls-options
    // and replaces it in-place with freshly generated markup driven by the live
    // swatches, then re-binds its click handler. If the materials JSON failed
    // to load, the wrapper stays hidden (controls.js emits an empty placeholder
    // with display:none).
    function na_rebuild_frame_finish_control() {
        const optionsContainer = document.getElementById('na-controls-options');
        if (!optionsContainer) return;
        if (!window.NA_OPTIONS_CONFIG || !window.Na__Ui__Controls) return;

        const descriptor = (window.NA_OPTIONS_CONFIG || []).find(function (item) {
            return item && item.id === 'frame_material_id';
        });
        if (!descriptor) return;

        // Honour the currently selected value rather than the descriptor default.
        const currentValue = (_config && _config.frame_material_id) || descriptor.default;
        const renderConfig = Object.assign({}, descriptor, { default: currentValue });

        const newHtml = window.Na__Ui__Controls.na_createControl(renderConfig);
        const existing = optionsContainer.querySelector('[data-control-id="frame_material_id"]');
        if (existing) {
            existing.outerHTML = newHtml;
        } else {
            optionsContainer.insertAdjacentHTML('beforeend', newHtml);
        }

        if (window.Na__Ui__Events && typeof window.Na__Ui__Events.na_attachEventListeners === 'function') {
            window.Na__Ui__Events.na_attachEventListeners(descriptor, na_onControlChange);
        }

        // Re-render the SVG so the frame tint reflects the just-arrived swatch hex.
        try { na_onConfigChange(); }
        catch (err) { console.warn('[NA_UI] Re-render after swatch refresh failed:', err); }
    }
    // ---------------------------------------------------------------

    // Public API
    // ------------------------------------------------------------
    return {
        na_init: na_init,
        na_getConfig: na_getConfig,
        na_getEffectiveFrameThicknesses: na_getEffectiveFrameThicknesses,
        na_setConfig: na_setConfig,
        na_setUpdateCallback: na_setUpdateCallback,
        na_isSvgValid: na_isSvgValid,
        na_toggleCasementRemoval: na_toggleCasementRemoval,
        na_toggleTransomSegmentRemoval: na_toggleTransomSegmentRemoval,
        na_toggleGlazebarRemoval: na_toggleGlazebarRemoval,
        na_resetHiddenElements: na_resetHiddenElements,
        na_rebuild_frame_finish_control: na_rebuild_frame_finish_control
    };
    
})();

// Top-level `const` declarations don't attach to window in browsers, so other
// scripts that look up window.Na_DynamicUI silently miss it. Mirror it here so
// FinishCards / cross-system calls work consistently.
window.Na_DynamicUI = Na_DynamicUI;

// endregion ===================================================================

// =============================================================================
// REGION | Viewport Module - Window Tab (Thin Wrapper Over Na__Viewport__Instance)
// =============================================================================
// As of 01-May-2026 the per-tab viewport state machine was relocated into the
// reusable Na__Viewport__Instance factory under
// 06__PluginCore__HtmlDialogue__ViewportModules/. Na_Viewport now owns only
// window-specific concerns:
//   - validation gate (returns false to disable Create / Update buttons)
//   - re-binding casement / transom / glazebar click delegation per render
//   - the window-shaped reset fitter
// All pan/zoom, viewBox state, and reset plumbing comes from the shared factory.
// =============================================================================

const Na_Viewport = (function() {

    // MODULE VARIABLES | Bound Window Viewport Instance + DOM Reference
    // ------------------------------------------------------------
    let _instance   = null;                                          // <-- Shared viewport instance
    let _svgElement = null;                                          // <-- Cached SVG element reference
    // ---------------------------------------------------------------


    // FUNCTION | Initialize the Window Viewport Instance
    // ------------------------------------------------------------
    function na_init() {
        console.log('[NA_VIEWPORT] Initializing window viewport via Na__Viewport__Instance');

        if (!window.Na__Viewport__Instance) {
            console.error('[NA_VIEWPORT] Na__Viewport__Instance not loaded');
            return;
        }

        _instance = window.Na__Viewport__Instance.na_create({
            wrapperId          : 'na-canvas-wrapper',
            svgId              : 'na-viewport-svg',
            initialViewBox     : { x: -50, y: -50, width: 500, height: 400 },
            autoResetOnRender  : false,                              // <-- na_render handles reset itself
            fitToContent       : function (config) {
                if (window.Na__Viewport__Controls &&
                    typeof window.Na__Viewport__Controls.na_windowResetFitter === 'function') {
                    return window.Na__Viewport__Controls.na_windowResetFitter(config);
                }
                return { x: 0, y: 0, width: 1000, height: 1000 };    // <-- Defensive fallback
            },
            onRender           : na_paint_window_svg                 // <-- Window-specific painter
        });

        if (!_instance) return;

        _instance.na_init();                                          // <-- Eagerly bind pan/zoom

        _svgElement = _instance.na_get_svg();
        if (!_svgElement) {
            console.error('[NA_VIEWPORT] Window SVG element not found after init');
            return;
        }

        console.log('[NA_VIEWPORT] Window viewport initialized');
    }
    // ---------------------------------------------------------------


    // SUB FUNCTION | Paint the Window SVG Markup into the Bound Element
    // ---------------------------------------------------------------
    // Mode-aware painter:
    //   - multifold_mode === true → bifold elevation generator
    //   - sliding_mode    === true → sliding elevation generator
    //   - otherwise              → legacy window SVG generator
    // Called by Na__Viewport__Instance after the validation hook has
    // already gated the render, so this can assume `config` is valid.
    function na_paint_window_svg(svgEl, config) {
        const svgContent = na_resolve_active_svg_markup(config);
        if (!svgContent) {
            throw new Error('Failed to generate viewport SVG');
        }
        svgEl.innerHTML = svgContent;                                 // <-- HTML string injection (shared across modes)
    }
    // ---------------------------------------------------------------


    // HELPER FUNCTION | Pick the Right SVG Generator for the Active Mode
    // ---------------------------------------------------------------
    function na_resolve_active_svg_markup(config) {
        if (config && config.multifold_mode === true && window.Na__ExtFold__ElevationGenerator) {
            return window.Na__ExtFold__ElevationGenerator.na_generate_bifold_svg(config);
        }
        if (config && config.sliding_mode === true && window.Na__ExtSlide__ElevationGenerator) {
            return window.Na__ExtSlide__ElevationGenerator.na_generate_sliding_svg(config);
        }
        return window.Na__Viewport__SvgGenerator.na_generateWindowSvg(config);
    }
    // ---------------------------------------------------------------


    // SUB FUNCTION | (Re-)Bind Casement / Transom / Glaze Bar Click Delegation
    // ---------------------------------------------------------------
    // Uses the LIVE interaction state owned by the underlying instance so
    // the click handler still sees `didPan === true` when a pan-drag has
    // just finished, exactly mirroring the legacy direct-shared-state
    // behaviour.
    function na_bind_window_click_targets(svgEl) {
        if (!svgEl || !window.Na__Viewport__Controls || !_instance) return;

        const liveInteractionState = _instance.na_get_interaction_state();

        window.Na__Viewport__Controls.na_setupCasementClickTargets(
            svgEl,
            liveInteractionState,
            function (openingIndex, cellIndex, panelIndex) {
                Na_DynamicUI.na_toggleCasementRemoval(openingIndex, cellIndex, panelIndex);
            },
            function (openingIndex, transomIndex) {
                Na_DynamicUI.na_toggleTransomSegmentRemoval(openingIndex, transomIndex);
            },
            function (openingIndex, cellIndex, panelIndex, sashIndex, orientation, barIndex) {
                Na_DynamicUI.na_toggleGlazebarRemoval(
                    openingIndex,
                    cellIndex,
                    panelIndex,
                    sashIndex,
                    orientation,
                    barIndex
                );
            }
        );
    }
    // ---------------------------------------------------------------


    // FUNCTION | Render the Window Model (Validation-Gated)
    // ------------------------------------------------------------
    // @returns {boolean} True if SVG was generated successfully
    function na_render(config) {
        if (!_instance) {
            console.error('[NA_VIEWPORT] Instance not initialised');
            return false;
        }

        try {
            const validation = window.Na__Viewport__Validation.na_validateConfig(config);
            if (!validation.valid) {
                console.warn('[NA_VIEWPORT] Invalid config:', validation.errors);
                window.Na__Viewport__Validation.na_showValidationError(validation.errors);
                return false;
            }

            const ok = _instance.na_render(config);                   // <-- Paint via shared instance
            if (!ok) return false;

            const svgEl = _instance.na_get_svg();
            na_bind_window_click_targets(svgEl);                      // <-- Per-render click rebinding (legacy behaviour)
            na_resetView();                                           // <-- Snap to fit after re-paint

            window.Na__Viewport__Validation.na_showValidationSuccess();
            return true;

        } catch (e) {
            console.error('[NA_VIEWPORT] Error rendering:', e);
            window.Na__Viewport__Validation.na_showValidationError(['Render error: ' + e.message]);
            return false;
        }
    }
    // ---------------------------------------------------------------


    // FUNCTION | Reset View to Fit Window
    // ------------------------------------------------------------
    function na_resetView() {
        if (!_instance) return;
        const config = Na_DynamicUI.na_getConfig();
        _instance.na_resetView(config);
    }
    // ---------------------------------------------------------------


    // FUNCTION | Export Current Model as DXF
    // ------------------------------------------------------------
    function na_exportDxf() {
        const config = Na_DynamicUI.na_getConfig();
        return window.Na__Export__Dxf.na_exportDxf(config);
    }
    // ---------------------------------------------------------------


    // Public API
    // ------------------------------------------------------------
    return {
        na_init      : na_init,
        na_render    : na_render,
        na_resetView : na_resetView,
        na_exportDxf : na_exportDxf
    };

})();

// endregion ===================================================================

// =============================================================================
// REGION | Viewport Resize Functionality
// =============================================================================

// FUNCTION | Initialize Viewport Resize Handle
// ------------------------------------------------------------
// Allows user to drag and resize the 2D preview viewport
function na_initViewportResize() {
    const handle = document.getElementById('na-viewport-resize-handle');
    const wrapper = document.getElementById('na-canvas-wrapper');
    
    if (!handle || !wrapper) {
        console.warn('[NA_VIEWPORT] Resize handle or wrapper not found');
        return;
    }
    
    let isResizing = false;
    let startY = 0;
    let startHeight = 0;
    
    // Mouse down - start resizing
    handle.addEventListener('mousedown', function(e) {
        isResizing = true;
        startY = e.clientY;
        startHeight = wrapper.offsetHeight;
        document.body.style.cursor = 'ns-resize';
        e.preventDefault();
    });
    
    // Mouse move - update size
    document.addEventListener('mousemove', function(e) {
        if (!isResizing) return;
        
        const deltaY = e.clientY - startY;
        const newHeight = Math.max(100, Math.min(600, startHeight + deltaY));
        wrapper.style.height = newHeight + 'px';
    });
    
    // Mouse up - stop resizing
    document.addEventListener('mouseup', function() {
        if (isResizing) {
            isResizing = false;
            document.body.style.cursor = '';
            Na_Viewport.na_resetView();
        }
    });
    
    console.log('[NA_VIEWPORT] Resize handle initialized');
}
// ---------------------------------------------------------------

// endregion ===================================================================

// =============================================================================
// REGION | Initialization
// =============================================================================

// FUNCTION | Initialize All UI Modules When DOM is Ready
// ------------------------------------------------------------
document.addEventListener('DOMContentLoaded', function() {
    console.log('[NA_UI] ═══════════════════════════════════════════════════════');
    console.log('[NA_UI] ELEMENT ASSEMBLY STUDIO PRO - WINDOW UI - INITIALIZING');
    console.log('[NA_UI] ═══════════════════════════════════════════════════════');

    // Initialise the Viewport FIRST so the SVG element reference is bound
    // before Na_DynamicUI's first na_onConfigChange triggers Na_Viewport.na_render.
    // Without this ordering the very first render returns false, _svgValid stays
    // false, and the Create / Update buttons remain disabled even though the
    // configuration is otherwise valid.
    Na_Viewport.na_init();

    // Now build the controls and run the initial render against the bound SVG.
    Na_DynamicUI.na_init();

    // Initialize viewport resize handle
    na_initViewportResize();
    
    // Request initial config from Ruby
    if (typeof sketchup !== 'undefined') {
        sketchup.na_requestConfig();
        console.log('[NA_UI] Requested initial config from Ruby');
    } else {
        console.warn('[NA_UI] SketchUp bridge not available (browser mode)');
    }
    
    console.log('[NA_UI] Element Assembly Studio Pro - Window UI initialized successfully');
    console.log('[NA_UI] ═══════════════════════════════════════════════════════');
});
// ---------------------------------------------------------------

// endregion ===================================================================

// =============================================================================
// END OF FILE
// =============================================================================
