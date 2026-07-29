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

        // @delegate: ../34__System__ExteriorDoubleDoorSystem/Na__AssemblyStudio__ExtDouble__UiSystem__Config__.js
        na_buildControls('na-controls-double-door', window.NA_DOUBLE_DOOR_CONFIG || []);

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
        [window.NA_UI_CONFIG, window.NA_GLAZEBAR_CONFIG, window.NA_CILL_FRAME_CONFIG, window.NA_OPTIONS_CONFIG, window.NA_DOOR_PANEL_CONFIG, window.NA_SLIDING_DOOR_CONFIG, window.NA_BIFOLD_DOOR_CONFIG, window.NA_DOUBLE_DOOR_CONFIG || []].forEach(config => {
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
        _config.double_door_removed_glazebars = [];
        _config.leaded_disabled_cells = [];
        _config.double_door_leaded_disabled_cells = [];
        na_syncModeFlagsFromHierarchy();
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

        if (id === 'bottom_sash_top_rail_override' && normalizedValue === true && previousValue !== true) {
            const inheritedTopRail = Number(_config.casement_top_rail_mm || _config.casement_width_mm || 60);
            _config.bottom_sash_top_rail_mm = inheritedTopRail;
            na_updateControlValue('bottom_sash_top_rail_mm', inheritedTopRail);
        }

        if (id === 'casement_top_rail_mm' && _config.bottom_sash_top_rail_override !== true) {
            _config.bottom_sash_top_rail_mm = Number(normalizedValue);
            na_updateControlValue('bottom_sash_top_rail_mm', normalizedValue);
        }

        if ((id === 'double_door_left_leaf_override_enabled' || id === 'double_door_right_leaf_override_enabled') &&
            normalizedValue === true &&
            previousValue !== true) {
            const side = id.indexOf('_left_') !== -1 ? 'left' : 'right';
            na_seedDoubleDoorLeafOverride(side);
        }

        if (_config.double_door_mode === true && (
            id === 'width_mm' ||
            id === 'frame_thickness_mm' ||
            id === 'advanced_frame_controls' ||
            id === 'frame_left_thickness_mm' ||
            id === 'frame_right_thickness_mm' ||
            id === 'double_door_active_leaf_width_mm'
        )) {
            na_clampDoubleDoorActiveLeafWidth();
        }

        // Seed Gothic-arch defaults on the false->true edge so the user
        // sees a sensible arch immediately. The Amount/Height sliders are
        // then user-controllable until the toggle is disabled.
        if (id === 'glazebar_gothic_arch_enabled' && previousValue !== true && normalizedValue === true) {
            na_applyGothicArchDefaultsOnEnable();
        }

        // Keep legacy bifold_door_glazed in sync with leaf composition so
        // Ruby PanelLayoutResolver fallback and any remaining glazed-only
        // readers stay consistent when the user picks FullyFielded /
        // GlazedOverFielded / FullyGlazed.
        if (id === 'bifold_door_leaf_composition') {
            na_syncBifoldGlazedFromComposition(_config);
        }

        // Soft-coupling: moving the Vertical Bars slider always drives
        // the Amount Of Arches to (vBars + 1), clamped to the slider's
        // [1..8] range. The user can still override arches manually
        // afterwards (decoupled), but the next vbar change re-syncs.
        // Mirrors the request that vbars and arches feel natural together
        // in Live Mode where each interior arch springing sits over one
        // vertical bar.
        if (id === 'vertical_glaze_bars') {
            na_syncArchAmountFromVerticalBars(value);
        }

        // Hierarchical product type: Window|Exterior Doors, then a second-row
        // exclusive subtype. Legacy boolean mode flags are derived here so
        // Ruby DialogCallbacks keep working unchanged.
        if (id === 'ui_element_category' || id === 'ui_window_type' || id === 'ui_exterior_door_type') {
            const previousModeId = na_resolveActiveProductModeId();
            na_syncModeFlagsFromHierarchy();
            const nextModeId = na_resolveActiveProductModeId();
            if (nextModeId !== previousModeId) {
                if (nextModeId === 'sliding_sash_window') {
                    na_applySlidingSashCasementDefaults();
                } else if (nextModeId) {
                    na_applyDoorModeDefaultDimensions(nextModeId);
                    if (nextModeId === 'double_door_mode') na_seedDoubleDoorActiveLeafWidth();
                }
            } else if (nextModeId === 'double_door_mode' && id === 'ui_exterior_door_type') {
                na_seedDoubleDoorActiveLeafWidth();
            }
        }

        na_onConfigChange();
    }
    // ---------------------------------------------------------------

    // FUNCTION | Apply Sliding Sash Casement Defaults
    // ------------------------------------------------------------
    function na_applySlidingSashCasementDefaults() {
        const defaults = {
            casement_sizes_individual: true,
            casement_top_rail_mm: 60,
            casement_bottom_rail_mm: 70,
            sliding_sash_overlap_mm: 40,
            top_sash_bottom_rail_mm: 60,
            bottom_sash_top_rail_override: false,
            bottom_sash_top_rail_mm: 60,
            casement_left_stile_mm: 40,
            casement_right_stile_mm: 40
        };

        Object.keys(defaults).forEach(controlId => {
            _config[controlId] = defaults[controlId];
            na_updateControlValue(controlId, defaults[controlId]);
        });
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
    
    // FUNCTION | Derive Legacy Mode Flags From Hierarchical Product Controls
    // ------------------------------------------------------------
    function na_syncModeFlagsFromHierarchy() {
        const category = _config.ui_element_category || 'Window';
        _config.door_mode = false;
        _config.ext_single_door_mode = false;
        _config.sliding_mode = false;
        _config.multifold_mode = false;
        _config.double_door_mode = false;
        _config.sliding_sash_window = false;

        if (category === 'ExteriorDoors') {
            const doorType = _config.ui_exterior_door_type || 'Double';
            if (doorType === 'Double') {
                _config.double_door_mode = true;
            } else if (doorType === 'Single') {
                _config.ext_single_door_mode = true;
            } else if (doorType === 'Sliding') {
                _config.sliding_mode = true;
            } else if (doorType === 'MultiFold') {
                _config.multifold_mode = true;
            }
            return;
        }

        if ((_config.ui_window_type || 'Casement') === 'SlidingSash') {
            _config.sliding_sash_window = true;
        }
    }
    // ---------------------------------------------------------------

    // FUNCTION | Hydrate Hierarchy Controls From Legacy Mode Flags
    // ------------------------------------------------------------
    // Used when Ruby selection restore still sends boolean mode flags.
    function na_hydrateHierarchyFromModeFlags() {
        if (_config.double_door_mode === true) {
            _config.ui_element_category = 'ExteriorDoors';
            _config.ui_exterior_door_type = 'Double';
        } else if (_config.ext_single_door_mode === true || _config.door_mode === true) {
            _config.ui_element_category = 'ExteriorDoors';
            _config.ui_exterior_door_type = 'Single';
            _config.ext_single_door_mode = true;
            _config.door_mode = false;
        } else if (_config.sliding_mode === true) {
            _config.ui_element_category = 'ExteriorDoors';
            _config.ui_exterior_door_type = 'Sliding';
        } else if (_config.multifold_mode === true) {
            _config.ui_element_category = 'ExteriorDoors';
            _config.ui_exterior_door_type = 'MultiFold';
        } else {
            _config.ui_element_category = 'Window';
            _config.ui_window_type = _config.sliding_sash_window === true ? 'SlidingSash' : 'Casement';
        }
    }
    // ---------------------------------------------------------------

    // FUNCTION | Resolve Active Product Mode Id For Dimension Seeding
    // ------------------------------------------------------------
    function na_resolveActiveProductModeId() {
        if (_config.double_door_mode === true) return 'double_door_mode';
        if (_config.ext_single_door_mode === true) return 'ext_single_door_mode';
        if (_config.sliding_mode === true) return 'sliding_mode';
        if (_config.multifold_mode === true) return 'multifold_mode';
        if (_config.sliding_sash_window === true) return 'sliding_sash_window';
        return null;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Show / Hide Hierarchical Second-Row Product Controls
    // ------------------------------------------------------------
    function na_updateProductTypeControlVisibility() {
        const isExterior = (_config.ui_element_category || 'Window') === 'ExteriorDoors';
        const windowTypeControl = document.querySelector('[data-control-id="ui_window_type"]');
        const doorTypeControl = document.querySelector('[data-control-id="ui_exterior_door_type"]');
        if (windowTypeControl) windowTypeControl.style.display = isExterior ? 'none' : '';
        if (doorTypeControl) doorTypeControl.style.display = isExterior ? '' : 'none';
    }
    // ---------------------------------------------------------------

    // FUNCTION | Called When Any Config Value Changes
    // ------------------------------------------------------------
    function na_onConfigChange() {
        na_updateProductTypeControlVisibility();
        na_updateSlidingSashOverlapVisibility();
        na_updateSashHornControlsVisibility();
        na_updateDoorPanelVisibility();
        na_updateSlidingDoorVisibility();
        na_updateMultifoldDoorVisibility();
        na_updateDoubleDoorVisibility();
        na_updateSingleDoorSubcontrolVisibility();
        na_updateSharedFieldedPanelVisibility('sliding_door', _config.sliding_mode === true);
        na_updateSharedFieldedPanelVisibility('bifold_door', _config.multifold_mode === true);
        na_updateAdvancedGlazebarVisibility();
        na_updateGlazebarOffsetVisibility();
        na_updateLeadedGlassVisibility();
        na_clampGlazebarMarginOffset();
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
        const clampedMax = _config.double_door_mode === true
            ? Math.max(0, Number(_config.double_door_leaf_thickness_mm || 50) / 2 - 1)
            : (function () {
                const casementDepth = _config.casement_depth_mm || 55;
                const glassThickness = _config.glass_thickness_mm || 20;
                const maxGlazebarInset = Math.floor((casementDepth - glassThickness) / 2);
                return Math.max(0, Math.min(20, maxGlazebarInset));
            })();
        const insetControlIds = _config.double_door_mode === true
            ? ['glazebar_inset_mm', 'double_door_left_glazebar_inset_mm', 'double_door_right_glazebar_inset_mm']
            : ['glazebar_inset_mm'];
        insetControlIds
            .forEach(controlId => {
                if (_config[controlId] == null || Number(_config[controlId]) <= clampedMax) return;
                _config[controlId] = clampedMax;
                na_updateControlValue(controlId, clampedMax);
            });
        
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
        if (_config.double_door_mode === true) {
            if (!Array.isArray(_config.double_door_removed_glazebars)) {
                _config.double_door_removed_glazebars = [];
            }
            _config.double_door_removed_glazebars = _config.double_door_removed_glazebars
                .map(key => String(key))
                .filter(key => validGlazebarKeys.has(key));
        } else {
            _config.removed_glazebars = _config.removed_glazebars
                .map(key => String(key))
                .filter(key => validGlazebarKeys.has(key));
        }

        // Clean up leaded_disabled_cells when the glazing cell grid changes
        if (!Array.isArray(_config.leaded_disabled_cells)) {
            _config.leaded_disabled_cells = [];
        }
        const validLeadedCellKeys = na_getValidLeadedCellKeySet();
        if (_config.double_door_mode === true) {
            if (!Array.isArray(_config.double_door_leaded_disabled_cells)) {
                _config.double_door_leaded_disabled_cells = [];
            }
            _config.double_door_leaded_disabled_cells = _config.double_door_leaded_disabled_cells
                .map(key => String(key))
                .filter(key => validLeadedCellKeys.has(key));
        } else {
            _config.leaded_disabled_cells = _config.leaded_disabled_cells
                .map(key => String(key))
                .filter(key => validLeadedCellKeys.has(key));
        }
        
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

    // FUNCTION | Toggle Sliding Sash Horn Control Visibility
    // ------------------------------------------------------------
    function na_updateSashHornControlsVisibility() {
        const showSashControls =
            _config.sliding_sash_window === true &&
            _config.show_casements !== false &&
            _config.multifold_mode !== true &&
            _config.sliding_mode !== true;

        ['top_sash_bottom_rail_mm', 'bottom_sash_top_rail_override', 'sash_horns_enabled', 'sash_horn_type'].forEach(controlId => {
            const control = document.querySelector(`[data-control-id="${controlId}"]`);
            if (control) control.style.display = showSashControls ? '' : 'none';
        });

        const bottomSashTopRailControl = document.querySelector('[data-control-id="bottom_sash_top_rail_mm"]');
        if (bottomSashTopRailControl) {
            bottomSashTopRailControl.style.display =
                showSashControls && _config.bottom_sash_top_rail_override === true ? '' : 'none';
        }
    }
    // ---------------------------------------------------------------

    // FUNCTION | Toggle Door Panel Section Visibility
    // ------------------------------------------------------------
    function na_updateDoorPanelVisibility() {
        const doorPanelSection = document.getElementById('na-section-door-panel');
        if (!doorPanelSection) return;

        const isDoorMode = _config.ext_single_door_mode === true;
        doorPanelSection.style.display = isDoorMode ? '' : 'none';
    }
    // ---------------------------------------------------------------

    // FUNCTION | Toggle Single-Door Fielded Subcontrol Visibility
    // ------------------------------------------------------------
    function na_updateSingleDoorSubcontrolVisibility() {
        if (_config.ext_single_door_mode !== true) return;
        na_updateSharedFieldedPanelVisibility('single_door', true);
    }
    // ---------------------------------------------------------------

    // FUNCTION | Shared Fielded-Panel Subcontrol Visibility
    // ------------------------------------------------------------
    // prefix: 'single_door' | 'sliding_door' | 'bifold_door' | 'double_door'
    function na_updateSharedFieldedPanelVisibility(prefix, isActive) {
        if (!isActive) return;

        const compositionKey = prefix === 'double_door'
            ? 'double_door_leaf_composition'
            : `${prefix}_leaf_composition`;
        const composition = _config[compositionKey] || (prefix === 'single_door' ? 'GlazedOverFielded' : 'FullyGlazed');
        const panelOutput = _config[`${prefix}_panel_output_mode`] || 'ThreeDimensional';
        const preset = _config[`${prefix}_panel_preset`] || 'OnePanel';
        const hasFielded = composition === 'GlazedOverFielded' || composition === 'FullyFielded';
        const midRailKey = prefix === 'double_door' || prefix === 'single_door'
            ? `${prefix}_mid_rail_width_mm`
            : `${prefix}_mid_rail_width_mm`;

        const visibilityMap = [
            { id: `${prefix}_panel_output_mode`, visible: hasFielded },
            { id: `${prefix}_panel_preset`, visible: hasFielded },
            { id: `${prefix}_panel_inset_mm`, visible: hasFielded },
            { id: `${prefix}_panel_profile`, visible: hasFielded && panelOutput === 'ThreeDimensional' },
            { id: `${prefix}_panel_depth_mm`, visible: hasFielded && panelOutput === 'ThreeDimensional' },
            { id: `${prefix}_panel_bevel_width_mm`, visible: hasFielded && panelOutput === 'ThreeDimensional' },
            { id: `${prefix}_fielded_section_height_mm`, visible: composition === 'GlazedOverFielded' },
            { id: midRailKey, visible: composition === 'GlazedOverFielded' },
            { id: `${prefix}_panel_columns`, visible: hasFielded && preset === 'Custom' },
            { id: `${prefix}_panel_rows`, visible: hasFielded && preset === 'Custom' }
        ];

        visibilityMap.forEach(entry => {
            const control = document.querySelector(`[data-control-id="${entry.id}"]`);
            if (control) control.style.display = entry.visible ? '' : 'none';
        });
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

    // FUNCTION | Toggle Exterior Double-Door Section and Viewports
    // ------------------------------------------------------------
    function na_updateDoubleDoorVisibility() {
        const isDoubleDoorMode = _config.double_door_mode === true;
        const section = document.getElementById('na-section-double-door');
        const standardViewport = document.getElementById('na-canvas-wrapper');
        const dualViewport = document.getElementById('na-double-door-dual-viewport');

        if (section) section.style.display = isDoubleDoorMode ? '' : 'none';
        if (standardViewport) standardViewport.style.display = isDoubleDoorMode ? 'none' : '';
        if (dualViewport) dualViewport.style.display = isDoubleDoorMode ? '' : 'none';

        na_updateDoubleDoorSubcontrolVisibility(isDoubleDoorMode);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Toggle Double-Door Conditional Controls
    // ------------------------------------------------------------
    function na_updateDoubleDoorSubcontrolVisibility(isDoubleDoorMode) {
        const linked = _config.double_door_leaf_settings_linked !== false;
        const composition = _config.double_door_leaf_composition || 'GlazedOverFielded';
        const panelOutput = _config.double_door_panel_output_mode || 'ThreeDimensional';
        const preset = _config.double_door_panel_preset || 'OnePanel';

        function na_setControlVisibility(controlId, visible) {
            const control = document.querySelector(`[data-control-id="${controlId}"]`);
            if (control) control.style.display = visible ? '' : 'none';
        }

        const sharedFieldIds = [
            'double_door_panel_output_mode',
            'double_door_panel_preset',
            'double_door_panel_inset_mm'
        ];
        const sharedThreeDimensionalIds = [
            'double_door_panel_profile',
            'double_door_panel_depth_mm',
            'double_door_panel_bevel_width_mm'
        ];
        const sharedHybridIds = [
            'double_door_fielded_section_height_mm',
            'double_door_mid_rail_width_mm'
        ];
        const sharedCustomIds = [
            'double_door_panel_columns',
            'double_door_panel_rows'
        ];

        sharedFieldIds.forEach(id => na_setControlVisibility(id, isDoubleDoorMode && composition !== 'FullyGlazed'));
        sharedThreeDimensionalIds.forEach(id => na_setControlVisibility(
            id,
            isDoubleDoorMode && composition !== 'FullyGlazed' && panelOutput === 'ThreeDimensional'
        ));
        sharedHybridIds.forEach(id => na_setControlVisibility(
            id,
            isDoubleDoorMode && composition === 'GlazedOverFielded'
        ));
        sharedCustomIds.forEach(id => na_setControlVisibility(
            id,
            isDoubleDoorMode && composition !== 'FullyGlazed' && preset === 'Custom'
        ));

        ['left', 'right'].forEach(side => {
            const prefix = `double_door_${side}_`;
            const overrideEnabled = _config[`${prefix}leaf_override_enabled`] === true;
            const showOverride = isDoubleDoorMode && !linked;
            na_setControlVisibility(`${prefix}leaf_override_enabled`, showOverride);

            const leafComposition = _config[`${prefix}leaf_composition`] || composition;
            const leafOutput = _config[`${prefix}panel_output_mode`] || panelOutput;
            const leafPreset = _config[`${prefix}panel_preset`] || preset;
            const childIds = [
                'leaf_composition',
                'panel_output_mode',
                'panel_profile',
                'panel_preset',
                'panel_columns',
                'panel_rows',
                'fielded_section_height_mm',
                'mid_rail_width_mm',
                'panel_stile_width_mm',
                'panel_top_rail_width_mm',
                'panel_bottom_rail_width_mm',
                'panel_inset_mm',
                'panel_depth_mm',
                'panel_bevel_width_mm',
                'horizontal_glaze_bars',
                'vertical_glaze_bars',
                'glaze_bar_width_mm',
                'glazebar_inset_mm'
            ];
            childIds.forEach(suffix => na_setControlVisibility(`${prefix}${suffix}`, showOverride && overrideEnabled));

            if (!showOverride || !overrideEnabled) return;
            const usesField = leafComposition !== 'FullyGlazed';
            const usesGlazing = leafComposition !== 'FullyFielded';
            ['panel_output_mode', 'panel_preset', 'panel_inset_mm'].forEach(suffix =>
                na_setControlVisibility(`${prefix}${suffix}`, usesField)
            );
            ['panel_profile', 'panel_depth_mm', 'panel_bevel_width_mm'].forEach(suffix =>
                na_setControlVisibility(`${prefix}${suffix}`, usesField && leafOutput === 'ThreeDimensional')
            );
            ['panel_columns', 'panel_rows'].forEach(suffix =>
                na_setControlVisibility(`${prefix}${suffix}`, usesField && leafPreset === 'Custom')
            );
            ['fielded_section_height_mm', 'mid_rail_width_mm'].forEach(suffix =>
                na_setControlVisibility(`${prefix}${suffix}`, leafComposition === 'GlazedOverFielded')
            );
            ['horizontal_glaze_bars', 'vertical_glaze_bars', 'glaze_bar_width_mm', 'glazebar_inset_mm'].forEach(suffix =>
                na_setControlVisibility(`${prefix}${suffix}`, usesGlazing)
            );
        });
    }
    // ---------------------------------------------------------------

    // FUNCTION | Seed Equal Double-Door Leaf Width
    // ------------------------------------------------------------
    // Default the active-leaf-width field to the literal 'EQ' (equal 50/50
    // split). The user may override with a mm number to make the active leaf
    // that width; typing EQ/blank snaps back to an even split.
    function na_seedDoubleDoorActiveLeafWidth() {
        _config.double_door_active_leaf_width_mm = 'EQ';
        na_updateControlValue('double_door_active_leaf_width_mm', 'EQ');
    }
    // ---------------------------------------------------------------

    // FUNCTION | Clamp Active Leaf Width to Preserve Both Leaves
    // ------------------------------------------------------------
    // No-op when the field is in 'EQ' mode (non-numeric): the resolver splits
    // the opening evenly. Only a numeric override is clamped so both leaves
    // keep at least the 300 mm minimum.
    function na_clampDoubleDoorActiveLeafWidth() {
        const raw = _config.double_door_active_leaf_width_mm;
        const currentWidth = (typeof raw === 'number') ? raw : parseFloat(raw);
        if (!isFinite(currentWidth)) return;                                  // <-- 'EQ' mode; nothing to clamp

        const innerWidth = na_getInnerFrameWidthMm();
        const minimumLeafWidth = 300;
        const maximumActiveWidth = Math.max(minimumLeafWidth, innerWidth - minimumLeafWidth);
        const clampedWidth = Math.max(minimumLeafWidth, Math.min(maximumActiveWidth, currentWidth));

        if (_config.double_door_active_leaf_width_mm !== clampedWidth) {
            _config.double_door_active_leaf_width_mm = clampedWidth;
            na_updateControlValue('double_door_active_leaf_width_mm', clampedWidth);
        }
    }
    // ---------------------------------------------------------------

    // FUNCTION | Seed a Per-Leaf Override From Current Effective Settings
    // ------------------------------------------------------------
    function na_seedDoubleDoorLeafOverride(side) {
        const resolver = window.Na__ExtDouble__LeafConfigResolver;
        if (!resolver || typeof resolver.na_seed_leaf_override !== 'function') return;

        const prefix = `double_door_${side}_`;
        const sourceConfig = {
            ..._config,
            [`${prefix}leaf_override_enabled`]: false
        };
        const seededConfig = resolver.na_seed_leaf_override(sourceConfig, side);
        Object.keys(seededConfig).forEach(key => {
            if (!key.startsWith(prefix)) return;
            _config[key] = seededConfig[key];
            na_updateControlValue(key, seededConfig[key]);
        });
    }
    // ---------------------------------------------------------------

    // FUNCTION | Estimate Single-Casement Glazing Panel Width (mm)
    // ------------------------------------------------------------
    // Per-casement glazed width = (innerFrameWidth - (mullions * mullion_width)) / casementsPerOpening
    // minus the casement's left + right stiles. This is used to seed Gothic
    // arch defaults (one arch per ~250mm of glazing width beyond 450mm).
    function na_getGlazingPanelWidthMm() {
        const innerWidthMm = na_getInnerFrameWidthMm();
        const mullionsCount = Math.max(0, Math.round(_config.mullions || 0));
        const mullionWidth = Math.max(0, Number(_config.mullion_width_mm || 30));
        const casementsPerOpening = Math.max(1, Math.round(_config.casements_per_opening || 1));
        const openingsCount = mullionsCount + 1;

        const totalCasementBandWidth = Math.max(0, innerWidthMm - (mullionsCount * mullionWidth));
        const perOpeningWidth = totalCasementBandWidth / Math.max(1, openingsCount);
        const perCasementWidth = perOpeningWidth / casementsPerOpening;

        const casementWidth = Math.max(0, Number(_config.casement_width_mm || 65));
        const useIndividualSizes = _config.casement_sizes_individual === true;
        const leftStile  = useIndividualSizes ? Number(_config.casement_left_stile_mm  || casementWidth) : casementWidth;
        const rightStile = useIndividualSizes ? Number(_config.casement_right_stile_mm || casementWidth) : casementWidth;

        return Math.max(0, perCasementWidth - leftStile - rightStile);
    }
    // ---------------------------------------------------------------

    // FUNCTION | Estimate Single-Casement Glazing Panel Height (mm)
    // ------------------------------------------------------------
    // Inner-frame height minus top/bottom casement rails. For multi-transom
    // configurations this still represents a typical single-cell glazed
    // height, which is the figure the Gothic-arch default reads against.
    function na_getGlazingPanelHeightMm() {
        const innerHeightMm = na_getInnerFrameHeightMm();
        const transomCount = Math.max(0, Math.min(3, Math.round(_config.transoms || 0)));
        const transomWidth = na_getTransomWidthMm();
        const verticalCellHeight = Math.max(0, (innerHeightMm - (transomCount * transomWidth)) / (transomCount + 1));

        const casementWidth = Math.max(0, Number(_config.casement_width_mm || 65));
        const useIndividualSizes = _config.casement_sizes_individual === true;
        const topRail    = useIndividualSizes ? Number(_config.casement_top_rail_mm    || casementWidth) : casementWidth;
        const bottomRail = useIndividualSizes ? Number(_config.casement_bottom_rail_mm || casementWidth) : casementWidth;

        return Math.max(0, verticalCellHeight - topRail - bottomRail);
    }
    // ---------------------------------------------------------------

    // FUNCTION | Compute Default Gothic Arch Amount From Glazing Panel Width
    // ------------------------------------------------------------
    // Narrow panels (<= 300mm) seed a single lancet arch - matches the
    // reference detail in the V1.9.4 hand-sketch where each tall narrow
    // window carries one pointed arch. From 300mm to 450mm we seed
    // two arches, then +1 arch per additional 250mm. Clamped to the
    // slider's [1..8] range.
    function na_computeGothicArchAmountDefault(panelWidthMm) {
        const width = Math.max(0, Number(panelWidthMm) || 0);
        if (width <= 300) return 1;                                                                // <-- V1.9.4 narrow panel -> single arch
        if (width <= 450) return 2;
        const extra = Math.floor((width - 450) / 250);
        return Math.max(1, Math.min(8, 2 + extra));
    }
    // ---------------------------------------------------------------

    // FUNCTION | Compute Default Gothic Arch Height From Glazing Panel Height
    // ------------------------------------------------------------
    // Quarter of the glazing panel height, rounded to the nearest 10mm and
    // clamped to the slider's [200..800] range.
    function na_computeGothicArchHeightDefault(glazingPanelHeightMm) {
        const raw = Math.max(0, Number(glazingPanelHeightMm) || 0) / 4;
        const rounded = Math.round(raw / 10) * 10;
        return Math.max(200, Math.min(800, rounded));
    }
    // ---------------------------------------------------------------

    // FUNCTION | Compute Max Glaze Bar Margin Offset From Glazed Area
    // ------------------------------------------------------------
    // Margin must leave space for at least one interior lite. Cap is 40% of
    // the smaller glazed dimension as specified, with the slider's static
    // hard floor of 50mm still in force.
    function na_computeMaxGlazebarMarginMm() {
        let glassWidth = na_getGlazingPanelWidthMm();
        let glassHeight = na_getGlazingPanelHeightMm();
        if (_config.double_door_mode === true &&
            window.Na__ExtDouble__LeafConfigResolver &&
            typeof window.Na__ExtDouble__LeafConfigResolver.na_resolve === 'function') {
            const resolved = window.Na__ExtDouble__LeafConfigResolver.na_resolve(_config);
            const glazedRegions = resolved.leaves
                .map(leaf => leaf.panelLayout && leaf.panelLayout.glazedRegion)
                .filter(Boolean);
            if (glazedRegions.length > 0) {
                glassWidth = Math.min(...glazedRegions.map(region => region.widthMm));
                glassHeight = Math.min(...glazedRegions.map(region => region.heightMm));
            }
        }
        const smaller = Math.max(0, Math.min(glassWidth, glassHeight));
        const cap = Math.floor((smaller * 0.4) / 10) * 10;
        return Math.max(50, cap);
    }
    // ---------------------------------------------------------------

    // FUNCTION | Seed Gothic Arch Defaults When First Enabled
    // ------------------------------------------------------------
    // Mirrors na_applyTransomDefaultsForCountChange - only fires on the
    // false->true edge so the user's manual values are not stomped during
    // routine re-renders. Both amount and height are recomputed from the
    // current panel dimensions and written into _config plus the live DOM.
    //
    // Arch amount on enable = max(width-based default, vBars + 1) so the
    // natural pairing (one vbar under every interior springing) is the
    // initial state when the user already has vertical bars configured.
    function na_applyGothicArchDefaultsOnEnable() {
        const widthDefault = na_computeGothicArchAmountDefault(na_getGlazingPanelWidthMm());
        const vBars        = Math.max(0, Math.round(Number(_config.vertical_glaze_bars || 0)));
        const pairedAmount = Math.max(1, Math.min(8, vBars + 1));                                   // <-- V1.9.4 vBars=0 -> 1 arch
        const defaultAmount = Math.max(1, Math.min(8, Math.max(widthDefault, pairedAmount)));        // <-- V1.9.4 allow single-arch result
        const defaultHeight = na_computeGothicArchHeightDefault(na_getGlazingPanelHeightMm());

        _config.glazebar_gothic_arch_amount = defaultAmount;
        na_updateControlValue('glazebar_gothic_arch_amount', defaultAmount);

        _config.glazebar_gothic_arch_height_mm = defaultHeight;
        na_updateControlValue('glazebar_gothic_arch_height_mm', defaultHeight);
    }
    // ---------------------------------------------------------------

    // FUNCTION | Sync Arch Amount From Vertical Bars Slider
    // ------------------------------------------------------------
    // Implements the soft-coupling rule: every change of the Vertical
    // Bars slider re-pegs Amount Of Arches to (vBars + 1), clamped to
    // the slider's [1..8] range. The Arches slider remains user-
    // adjustable afterwards (decoupled until the next vbar change),
    // so a "preferred" amount can still be dialled in manually.
    function na_syncArchAmountFromVerticalBars(vBarsValue) {
        const vBars        = Math.max(0, Math.round(Number(vBarsValue || 0)));
        const pairedAmount = Math.max(1, Math.min(8, vBars + 1));                                   // <-- V1.9.4 vBars=0 -> 1 arch (was clamped to 2 minimum)
        if (_config.glazebar_gothic_arch_amount === pairedAmount) return;
        _config.glazebar_gothic_arch_amount = pairedAmount;
        na_updateControlValue('glazebar_gothic_arch_amount', pairedAmount);
    }
    // ---------------------------------------------------------------

    // FUNCTION | Toggle Advanced Glazebar Sub-Control Visibility
    // ------------------------------------------------------------
    // The Margin offset slider only shows when its toggle is on; the two
    // Gothic-arch sliders only show when their toggle is on. Mirrors
    // na_updateDoorPanelVisibility's trim-controls pattern.
    function na_updateAdvancedGlazebarVisibility() {
        const marginOffsetCtrl = document.querySelector('[data-control-id="glazebar_margin_offset_mm"]');
        if (marginOffsetCtrl) {
            const show = _config.glazebar_margin_enabled === true;
            marginOffsetCtrl.style.display = show ? '' : 'none';
        }

        const archAmountCtrl = document.querySelector('[data-control-id="glazebar_gothic_arch_amount"]');
        const archHeightCtrl = document.querySelector('[data-control-id="glazebar_gothic_arch_height_mm"]');
        const showArchSliders = _config.glazebar_gothic_arch_enabled === true;
        if (archAmountCtrl) archAmountCtrl.style.display = showArchSliders ? '' : 'none';
        if (archHeightCtrl) archHeightCtrl.style.display = showArchSliders ? '' : 'none';

        // V1.9.3 - Horizontal Bar Vertical Offset only has a visible
        // effect when there is at least one horizontal bar to move.
        // Hide it when h_bars == 0 so the panel stays uncluttered.
        const hOffsetCtrl = document.querySelector('[data-control-id="glazebar_horizontal_offset_mm"]');
        if (hOffsetCtrl) {
            const showHOffset = Math.max(0, Math.round(Number(_config.horizontal_glaze_bars || 0))) > 0;
            hOffsetCtrl.style.display = showHOffset ? '' : 'none';
        }
    }
    // ---------------------------------------------------------------

    // FUNCTION | Toggle Per-Bar Glaze Bar Offset Slider Visibility
    // ------------------------------------------------------------
    // Transom-style static pool: one offset slider per possible glaze
    // bar (glazebar_h_offset_N_mm / glazebar_v_offset_N_mm, N = 1..8).
    // Only the sliders for bars that currently exist are shown, so the
    // GLAZE BARS section stays uncluttered until offsets are relevant.
    // Hidden sliders keep their values, so restoring a bar count also
    // restores its nudges.
    function na_updateGlazebarOffsetVisibility() {
        const hBarCount = Math.max(0, Math.min(8, Math.round(Number(_config.horizontal_glaze_bars || 0))));
        const vBarCount = Math.max(0, Math.min(8, Math.round(Number(_config.vertical_glaze_bars || 0))));

        for (let barIndex = 1; barIndex <= 8; barIndex++) {
            const hCtrl = document.querySelector(`[data-control-id="glazebar_h_offset_${barIndex}_mm"]`);
            if (hCtrl) hCtrl.style.display = barIndex <= hBarCount ? '' : 'none';

            const vCtrl = document.querySelector(`[data-control-id="glazebar_v_offset_${barIndex}_mm"]`);
            if (vCtrl) vCtrl.style.display = barIndex <= vBarCount ? '' : 'none';
        }
    }
    // ---------------------------------------------------------------

    // FUNCTION | Toggle Leaded Glass Sub-Control Visibility
    // ------------------------------------------------------------
    // When disabled, only the enable toggle stays visible inside the
    // expandable. Centre Lines Only hides Width + Depth (ignored in Ruby).
    function na_updateLeadedGlassVisibility() {
        const enabled = _config.leaded_glass_enabled === true;
        const centreLinesOnly = _config.leaded_centre_lines_only === true;

        const dependentIds = [
            'horizontal_leaded_bars',
            'vertical_leaded_bars',
            'leaded_width_mm',
            'leaded_depth_mm',
            'leaded_centre_lines_only'
        ];
        dependentIds.forEach(function (id) {
            const ctrl = document.querySelector('[data-control-id="' + id + '"]');
            if (!ctrl) return;
            if (!enabled) {
                ctrl.style.display = 'none';
                return;
            }
            if (centreLinesOnly && (id === 'leaded_width_mm' || id === 'leaded_depth_mm')) {
                ctrl.style.display = 'none';
                return;
            }
            ctrl.style.display = '';
        });
    }
    // ---------------------------------------------------------------

    // FUNCTION | Clamp Margin Offset Slider Against Current Glazed Area
    // ------------------------------------------------------------
    // Reads the live <input> max attributes off the slider + numeric input
    // and replaces them with the per-panel cap so the user cannot drag past
    // the geometric feasibility limit. Any existing config value over the
    // new cap is pulled back and reflected in the UI immediately.
    function na_clampGlazebarMarginOffset() {
        const maxOffset = na_computeMaxGlazebarMarginMm();
        const slider = document.getElementById('glazebar_margin_offset_mm-slider');
        const input  = document.getElementById('glazebar_margin_offset_mm-input');
        if (slider) slider.max = String(maxOffset);
        if (input)  input.max  = String(maxOffset);

        const current = Number(_config.glazebar_margin_offset_mm || 0);
        if (current > maxOffset) {
            _config.glazebar_margin_offset_mm = maxOffset;
            na_updateControlValue('glazebar_margin_offset_mm', maxOffset);
        }
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
        const inDoorMode =
            (_config.multifold_mode === true) ||
            (_config.sliding_mode === true) ||
            (_config.double_door_mode === true) ||
            (_config.ext_single_door_mode === true);

        const alwaysWindowOnlyIds = [
            'casement_width_mm',                                                // <-- Casement controls (single + advanced)
            'casement_sizes_individual',                                        // <-- Casement individual rail/stile expandable
            'advanced_casement_controls',                                       // <-- Casement depth/inset/glazing thickness expandable
            'mullions',                                                         // <-- Window-only (split openings)
            'mullion_width_mm',                                                 // <-- Window-only mullion thickness
            'transoms',                                                         // <-- Window-only (split openings vertically)
            'show_casements'                                                    // <-- Casement-specific toggle
        ];

        const dynamicWindowOnlyIds = [
            'transom_width_mm',                                                 // <-- Managed by transom count in window mode
            'transom_1_y_mm',
            'transom_2_y_mm',
            'transom_3_y_mm',
            'sliding_sash_overlap_mm',                                          // <-- Managed by sliding_sash_window toggle in window mode
            'top_sash_bottom_rail_mm',
            'bottom_sash_top_rail_override',
            'bottom_sash_top_rail_mm',
            'sash_horns_enabled',
            'sash_horn_type'
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
        const inDoorMode =
            (_config.multifold_mode === true) ||
            (_config.sliding_mode === true) ||
            (_config.double_door_mode === true);
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
    //   ext_single_door_mode : 2100 mm  (standard single exterior door leaf height)
    //   sliding_mode         : 2100 mm  (standard sliding patio/bi-pass height)
    //   multifold_mode       : 2100 mm  (standard bifold/multi-fold height)
    //   double_door_mode     : 2100 mm
    //
    // Default widths per mode:
    //   ext_single_door_mode : 1000 mm  (standard single door leaf)
    //   double_door_mode     : 1800 mm
    //   sliding_mode         : 3000 mm  (typical two-panel sliding set)
    //   multifold_mode       : 3000 mm  (typical four-panel bifold set)
    function na_applyDoorModeDefaultDimensions(modeId) {
        const defaultWidth = (modeId === 'ext_single_door_mode' || modeId === 'door_mode')
            ? 1000
            : (modeId === 'double_door_mode' ? 1800 : 3000);
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
        const topSashBottomRail = Number(_config.top_sash_bottom_rail_mm || casBottomRail);
        const bottomSashTopRail = _config.bottom_sash_top_rail_override === true
            ? Number(_config.bottom_sash_top_rail_mm || casTopRail)
            : Number(casTopRail);
        const largestRailPair = Math.max(
            casTopRail + topSashBottomRail,
            bottomSashTopRail + casBottomRail
        );
        const minSingleSashHeight = (_config.show_casements !== false) ? (largestRailPair + 50) : 50;

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
        if (_config.double_door_mode === true &&
            window.Na__ExtDouble__LeafConfigResolver &&
            typeof window.Na__ExtDouble__LeafConfigResolver.na_resolve === 'function') {
            const validKeys = new Set();
            const resolved = window.Na__ExtDouble__LeafConfigResolver.na_resolve(_config);
            resolved.leaves.forEach(leaf => {
                for (let index = 1; index <= leaf.settings.horizontalBars; index += 1) {
                    validKeys.add(na_getGlazebarKey(0, 0, leaf.index - 1, 0, 'horizontal', index));
                }
                for (let index = 1; index <= leaf.settings.verticalBars; index += 1) {
                    validKeys.add(na_getGlazebarKey(0, 0, leaf.index - 1, 0, 'vertical', index));
                }
            });
            return validKeys;
        }

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
        na_toggleGlazebarRemovalInCollection(
            'removed_glazebars',
            openingIndex, cellIndex, panelIndex, sashIndex, orientation, barIndex
        );
    }
    // ---------------------------------------------------------------

    // FUNCTION | Toggle an Exterior Double-Door Glaze Bar
    // ------------------------------------------------------------
    function na_toggleDoubleDoorGlazebarRemoval(openingIndex, cellIndex, panelIndex, sashIndex, orientation, barIndex) {
        na_toggleGlazebarRemovalInCollection(
            'double_door_removed_glazebars',
            openingIndex, cellIndex, panelIndex, sashIndex, orientation, barIndex
        );
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Toggle a Glaze-Bar Key in a Named State Collection
    // ------------------------------------------------------------
    function na_toggleGlazebarRemovalInCollection(collectionKey, openingIndex, cellIndex, panelIndex, sashIndex, orientation, barIndex) {
        if (!Array.isArray(_config[collectionKey])) _config[collectionKey] = [];
        const glazebarKey = na_getGlazebarKey(openingIndex, cellIndex, panelIndex, sashIndex, orientation, barIndex);
        const existingIndex = _config[collectionKey].indexOf(glazebarKey);

        if (existingIndex === -1) {
            _config[collectionKey].push(glazebarKey);
            console.log(`[NA_UI] Removed glaze bar ${glazebarKey}`);
        } else {
            _config[collectionKey].splice(existingIndex, 1);
            console.log(`[NA_UI] Restored glaze bar ${glazebarKey}`);
        }

        na_onConfigChange();
    }
    // ---------------------------------------------------------------

    // FUNCTION | Build Leaded Glass Cell Key
    // ------------------------------------------------------------
    function na_getLeadedCellKey(openingIndex, cellIndex, panelIndex, sashIndex, col, row) {
        return `${openingIndex}:${cellIndex}:${panelIndex}:${sashIndex}:${col}:${row}`;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Collect Valid Leaded Glass Cell Keys
    // ------------------------------------------------------------
    // Grid shape only (bar counts define the cells) — deliberately NOT
    // gated on leaded_glass_enabled so per-cell choices survive the
    // leaded toggle being switched off and back on.
    function na_getValidLeadedCellKeySet() {
        if (_config.double_door_mode === true &&
            window.Na__ExtDouble__LeafConfigResolver &&
            typeof window.Na__ExtDouble__LeafConfigResolver.na_resolve === 'function') {
            const validKeys = new Set();
            const resolved = window.Na__ExtDouble__LeafConfigResolver.na_resolve(_config);
            resolved.leaves.forEach(leaf => {
                for (let row = 0; row <= leaf.settings.horizontalBars; row += 1) {
                    for (let col = 0; col <= leaf.settings.verticalBars; col += 1) {
                        validKeys.add(na_getLeadedCellKey(0, 0, leaf.index - 1, 0, col, row));
                    }
                }
            });
            return validKeys;
        }

        if (!window.Na__Viewport__SvgGenerator ||
            typeof window.Na__Viewport__SvgGenerator.na_collectValidLeadedCellKeys !== 'function') {
            return new Set();
        }

        return new Set(window.Na__Viewport__SvgGenerator.na_collectValidLeadedCellKeys(_config));
    }
    // ---------------------------------------------------------------

    // FUNCTION | Toggle Leaded Glass For One Glazing Cell
    // ------------------------------------------------------------
    function na_toggleLeadedCellState(openingIndex, cellIndex, panelIndex, sashIndex, col, row) {
        na_toggleLeadedCellStateInCollection(
            'leaded_disabled_cells',
            openingIndex, cellIndex, panelIndex, sashIndex, col, row
        );
    }
    // ---------------------------------------------------------------

    // FUNCTION | Toggle Leaded Glass For One Exterior Double-Door Cell
    // ------------------------------------------------------------
    function na_toggleDoubleDoorLeadedCellState(openingIndex, cellIndex, panelIndex, sashIndex, col, row) {
        na_toggleLeadedCellStateInCollection(
            'double_door_leaded_disabled_cells',
            openingIndex, cellIndex, panelIndex, sashIndex, col, row
        );
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Toggle a Leaded-Cell Key in a Named State Collection
    // ------------------------------------------------------------
    function na_toggleLeadedCellStateInCollection(collectionKey, openingIndex, cellIndex, panelIndex, sashIndex, col, row) {
        if (_config.leaded_glass_enabled !== true) return;               // <-- Cells only toggleable while leaded glass is on
        if (!Array.isArray(_config[collectionKey])) _config[collectionKey] = [];
        const cellKey = na_getLeadedCellKey(openingIndex, cellIndex, panelIndex, sashIndex, col, row);
        const existingIndex = _config[collectionKey].indexOf(cellKey);

        if (existingIndex === -1) {
            _config[collectionKey].push(cellKey);
            console.log(`[NA_UI] Disabled leaded glass cell ${cellKey}`);
        } else {
            _config[collectionKey].splice(existingIndex, 1);
            console.log(`[NA_UI] Enabled leaded glass cell ${cellKey}`);
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
        const removedDoubleDoorGlazebarsCount = Array.isArray(_config.double_door_removed_glazebars)
            ? _config.double_door_removed_glazebars.length
            : 0;
        const disabledLeadedCellsCount = Array.isArray(_config.leaded_disabled_cells)
            ? _config.leaded_disabled_cells.length
            : 0;
        const disabledDoubleDoorLeadedCellsCount = Array.isArray(_config.double_door_leaded_disabled_cells)
            ? _config.double_door_leaded_disabled_cells.length
            : 0;

        return removedCasementsCount > 0 ||
            removedTransomSegmentsCount > 0 ||
            removedGlazebarsCount > 0 ||
            removedDoubleDoorGlazebarsCount > 0 ||
            disabledLeadedCellsCount > 0 ||
            disabledDoubleDoorLeadedCellsCount > 0;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Reset Hidden Elements
    // ------------------------------------------------------------
    function na_resetHiddenElements() {
        _config.removed_casements = [];
        _config.removed_transom_segments = [];
        _config.removed_glazebars = [];
        _config.double_door_removed_glazebars = [];
        _config.leaded_disabled_cells = [];
        _config.double_door_leaded_disabled_cells = [];

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
            createBtn.textContent = na_resolveCreateButtonLabel();
            if (_svgValid) {
                createBtn.disabled = false;
                createBtn.classList.remove('na-btn-disabled');
            } else {
                createBtn.disabled = true;
                createBtn.classList.add('na-btn-disabled');
            }
        }
        
        if (updateBtn) {
            updateBtn.textContent = na_resolveUpdateButtonLabel();
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
    
    // FUNCTION | Resolve Create Button Label From Active Product
    // ------------------------------------------------------------
    function na_resolveCreateButtonLabel() {
        if (_config.double_door_mode === true) return 'Create Double Doors';
        if (_config.ext_single_door_mode === true) return 'Create Single Door';
        if (_config.sliding_mode === true) return 'Create Sliding Doors';
        if (_config.multifold_mode === true) return 'Create MultiFolding Door';
        return 'Create at Cursor';
    }
    // ---------------------------------------------------------------

    // FUNCTION | Resolve Update Button Label From Active Product
    // ------------------------------------------------------------
    function na_resolveUpdateButtonLabel() {
        if (_config.double_door_mode === true) return 'Update Double Doors';
        if (_config.ext_single_door_mode === true) return 'Update Single Door';
        if (_config.sliding_mode === true) return 'Update Sliding Doors';
        if (_config.multifold_mode === true) return 'Update MultiFolding Door';
        return 'Update Window';
    }
    // ---------------------------------------------------------------

    // FUNCTION | Set Configuration
    // ------------------------------------------------------------
    function na_setConfig(newConfig) {
        _config = { ..._config, ...newConfig };
        na_migrateLegacyLeadedColour(_config);
        na_syncBifoldGlazedFromComposition(_config);
        na_hydrateHierarchyFromModeFlags();
        na_syncModeFlagsFromHierarchy();

        // Update all UI controls (include hydrated hierarchy keys)
        Object.keys(_config).forEach(key => {
            na_updateControlValue(key, _config[key]);
        });
        
        // Trigger render
        na_onConfigChange();
    }
    // ---------------------------------------------------------------

    // FUNCTION | Sync Legacy bifold_door_glazed From Leaf Composition
    // ------------------------------------------------------------
    function na_syncBifoldGlazedFromComposition(cfg) {
        if (!cfg || typeof cfg !== 'object') return;
        if (cfg.bifold_door_leaf_composition) {
            cfg.bifold_door_glazed = (cfg.bifold_door_leaf_composition === 'FullyGlazed');
        }
    }
    // ---------------------------------------------------------------

    // FUNCTION | Migrate Legacy leaded_colour Mid/Light/Dark → edge_colour_leaded_id
    // ------------------------------------------------------------
    function na_migrateLegacyLeadedColour(cfg) {
        if (!cfg || typeof cfg !== 'object') return;
        if (cfg.edge_colour_leaded_id) {
            delete cfg.leaded_colour;
            return;
        }
        const legacy = cfg.leaded_colour;
        if (legacy === 'light') cfg.edge_colour_leaded_id = 'MTE107__LineColour__LightGrey__L85';
        else if (legacy === 'dark') cfg.edge_colour_leaded_id = 'MTE103__LineColour__DarkGrey__L40';
        else if (legacy === 'mid' || legacy) cfg.edge_colour_leaded_id = 'MTE104__LineColour__MidGrey__L60';
        delete cfg.leaded_colour;
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
            const allConfigArrays = [window.NA_UI_CONFIG, window.NA_GLAZEBAR_CONFIG, window.NA_CILL_FRAME_CONFIG, window.NA_DOOR_PANEL_CONFIG, window.NA_SLIDING_DOOR_CONFIG, window.NA_BIFOLD_DOOR_CONFIG, window.NA_DOUBLE_DOOR_CONFIG || []];
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

        // Try EQ-number hybrid text input (EQ / mm)
        const eqInput = document.getElementById(`${id}-eqnumber`);
        if (eqInput) {
            eqInput.value = (value === null || value === undefined) ? '' : value;
            return;
        }

        // Try multiway segmented toggle
        const segmented = document.getElementById(`${id}-segmented`);
        if (segmented) {
            segmented.dataset.value = value;
            segmented.querySelectorAll('.na-segmented-toggle__option').forEach(option => {
                option.classList.toggle(
                    'na-segmented-toggle__option--active',
                    option.getAttribute('data-option-value') === String(value)
                );
            });
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

    // FUNCTION | Rebuild Window-Tab Material Card Controls After Live Swatches Arrive
    // ------------------------------------------------------------
    // Called by Na_FrameFinishCards once Ruby pushes window.NA_FRAME_FINISH_SWATCHES.
    // Locates the existing frame_material_id wrapper inside na-controls-options
    // and replaces it in-place with freshly generated markup driven by the live
    // swatches, then re-binds its click handler. If the materials JSON failed
    // to load, the wrapper stays hidden (controls.js emits an empty placeholder
    // with display:none).
    function na_rebuild_frame_finish_control() {
        if (!window.Na__Ui__Controls) return;

        const materialGroups = [
            { containerId: 'na-controls-options', descriptors: window.NA_OPTIONS_CONFIG || [] },
            { containerId: 'na-controls-door-panel', descriptors: window.NA_DOOR_PANEL_CONFIG || [] },
            { containerId: 'na-controls-double-door', descriptors: window.NA_DOUBLE_DOOR_CONFIG || [] }
        ];

        materialGroups.forEach(group => {
            const container = document.getElementById(group.containerId);
            if (!container) return;

            group.descriptors
                .filter(descriptor => descriptor && descriptor.type === 'material_cards')
                .forEach(descriptor => {
                    na_replace_material_card_control(container, descriptor);
                });
        });

        // Re-render the SVG so the frame tint reflects the just-arrived swatch hex.
        try { na_onConfigChange(); }
        catch (err) { console.warn('[NA_UI] Re-render after swatch refresh failed:', err); }
    }
    // ---------------------------------------------------------------

    // FUNCTION | Rebuild Edge Colour Material Cards (Nested Under Expandable)
    // ------------------------------------------------------------
    // Called when Ruby pushes window.NA_EDGE_COLOUR_SWATCHES.
    function na_rebuild_edge_colour_controls() {
        if (!window.Na__Ui__Controls) return;

        const container = document.getElementById('na-controls-options');
        if (!container) return;

        const expandable = (window.NA_OPTIONS_CONFIG || []).find(function (d) {
            return d && d.id === 'edge_colour_controls' && d.type === 'expandable';
        });
        if (!expandable || !Array.isArray(expandable.children)) return;

        expandable.children
            .filter(function (child) { return child && child.type === 'material_cards'; })
            .forEach(function (descriptor) {
                na_replace_material_card_control(container, descriptor);
            });

        try { na_onConfigChange(); }
        catch (err) { console.warn('[NA_UI] Re-render after edge-colour swatch refresh failed:', err); }
    }
    // ---------------------------------------------------------------

    // HELPER | Replace One Material-Card Control In Place
    // ------------------------------------------------------------
    function na_replace_material_card_control(container, descriptor) {
        if (!container || !descriptor || !window.Na__Ui__Controls) return;

        const currentValue = (_config && _config[descriptor.id]) || descriptor.default;
        const renderConfig = Object.assign({}, descriptor, { default: currentValue });
        const newHtml = window.Na__Ui__Controls.na_createControl(renderConfig);
        const existing = container.querySelector('[data-control-id="' + descriptor.id + '"]');

        if (existing) existing.outerHTML = newHtml;
        else container.insertAdjacentHTML('beforeend', newHtml);

        if (window.Na__Ui__Events && typeof window.Na__Ui__Events.na_attachEventListeners === 'function') {
            window.Na__Ui__Events.na_attachEventListeners(descriptor, na_onControlChange);
        }
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
        na_toggleDoubleDoorGlazebarRemoval: na_toggleDoubleDoorGlazebarRemoval,
        na_toggleLeadedCellState: na_toggleLeadedCellState,
        na_toggleDoubleDoorLeadedCellState: na_toggleDoubleDoorLeadedCellState,
        na_resetHiddenElements: na_resetHiddenElements,
        na_rebuild_frame_finish_control: na_rebuild_frame_finish_control,
        na_rebuild_edge_colour_controls: na_rebuild_edge_colour_controls
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
    let _instance = null;                                            // <-- Shared standard window viewport instance
    let _svgElement = null;                                          // <-- Cached standard SVG element reference
    let _doubleDoorPlanInstance = null;                              // <-- Exterior Double Door plan viewport
    let _doubleDoorElevationInstance = null;                         // <-- Exterior Double Door elevation viewport
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

        na_init_double_door_viewports();
        console.log('[NA_VIEWPORT] Window viewport initialized');
    }
    // ---------------------------------------------------------------

    // FUNCTION | Initialize Exterior Double-Door Plan and Elevation Viewports
    // ------------------------------------------------------------
    function na_init_double_door_viewports() {
        _doubleDoorPlanInstance = window.Na__Viewport__Instance.na_create({
            wrapperId: 'na-double-door-plan-wrapper',
            svgId: 'na-double-door-plan-svg',
            initialViewBox: { x: -100, y: -300, width: 2200, height: 900 },
            autoResetOnRender: true,
            fitToContent: function (config) {
                if (window.Na__ExtDouble__PlanGenerator &&
                    typeof window.Na__ExtDouble__PlanGenerator.na_fit_to_content === 'function') {
                    return window.Na__ExtDouble__PlanGenerator.na_fit_to_content(config);
                }
                const width = Math.max(800, Number(config.width_mm || 1800));
                const depth = Math.max(200, Number(config.frame_depth_mm || 70) + 400);
                return { x: -100, y: -depth, width: width + 200, height: depth * 2 };
            },
            onRender: na_paint_double_door_plan_svg
        });

        _doubleDoorElevationInstance = window.Na__Viewport__Instance.na_create({
            wrapperId: 'na-double-door-elevation-wrapper',
            svgId: 'na-double-door-elevation-svg',
            initialViewBox: { x: -100, y: -2300, width: 2200, height: 2500 },
            autoResetOnRender: true,
            fitToContent: function (config) {
                if (window.Na__ExtDouble__ElevationGenerator &&
                    typeof window.Na__ExtDouble__ElevationGenerator.na_fit_to_content === 'function') {
                    return window.Na__ExtDouble__ElevationGenerator.na_fit_to_content(config);
                }
                const width = Math.max(800, Number(config.width_mm || 1800));
                const height = Math.max(1500, Number(config.height_mm || 2100));
                return { x: -100, y: -height - 100, width: width + 200, height: height + 250 };
            },
            onRender: na_paint_double_door_elevation_svg
        });

        if (_doubleDoorPlanInstance) _doubleDoorPlanInstance.na_init();
        if (_doubleDoorElevationInstance) _doubleDoorElevationInstance.na_init();
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Paint Exterior Double-Door Plan SVG
    // ------------------------------------------------------------
    function na_paint_double_door_plan_svg(svgEl, config) {
        if (!window.Na__ExtDouble__PlanGenerator ||
            typeof window.Na__ExtDouble__PlanGenerator.na_render !== 'function') {
            throw new Error('Exterior Double Door plan generator is not loaded');
        }
        window.Na__ExtDouble__PlanGenerator.na_render(svgEl, config);
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Paint Exterior Double-Door Elevation SVG
    // ------------------------------------------------------------
    function na_paint_double_door_elevation_svg(svgEl, config) {
        if (!window.Na__ExtDouble__ElevationGenerator ||
            typeof window.Na__ExtDouble__ElevationGenerator.na_render !== 'function') {
            throw new Error('Exterior Double Door elevation generator is not loaded');
        }
        window.Na__ExtDouble__ElevationGenerator.na_render(svgEl, config);
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
            },
            function (openingIndex, cellIndex, panelIndex, sashIndex, col, row) {
                Na_DynamicUI.na_toggleLeadedCellState(
                    openingIndex,
                    cellIndex,
                    panelIndex,
                    sashIndex,
                    col,
                    row
                );
            }
        );
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Bind Double-Door Elevation Glaze-Bar Click Targets
    // ------------------------------------------------------------
    function na_bind_double_door_glazebar_click_targets() {
        if (!_doubleDoorElevationInstance || !window.Na__Viewport__Controls) return;
        const svgEl = _doubleDoorElevationInstance.na_get_svg();
        if (!svgEl) return;
        const interactionState = _doubleDoorElevationInstance.na_get_interaction_state();
        window.Na__Viewport__Controls.na_setupCasementClickTargets(
            svgEl,
            interactionState,
            null,
            null,
            function (openingIndex, cellIndex, panelIndex, sashIndex, orientation, barIndex) {
                Na_DynamicUI.na_toggleDoubleDoorGlazebarRemoval(
                    openingIndex,
                    cellIndex,
                    panelIndex,
                    sashIndex,
                    orientation,
                    barIndex
                );
            },
            function (openingIndex, cellIndex, panelIndex, sashIndex, col, row) {
                Na_DynamicUI.na_toggleDoubleDoorLeadedCellState(
                    openingIndex,
                    cellIndex,
                    panelIndex,
                    sashIndex,
                    col,
                    row
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

            if (config && config.double_door_mode === true) {
                if (!_doubleDoorPlanInstance || !_doubleDoorElevationInstance) {
                    throw new Error('Exterior Double Door viewports are not initialised');
                }
                const planOk = _doubleDoorPlanInstance.na_render(config);
                const elevationOk = _doubleDoorElevationInstance.na_render(config);
                if (!planOk || !elevationOk) return false;
                na_bind_double_door_glazebar_click_targets();
                na_resetView();
                window.Na__Viewport__Validation.na_showValidationSuccess();
                return true;
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
        const config = Na_DynamicUI.na_getConfig();
        if (config.double_door_mode === true) {
            if (_doubleDoorPlanInstance) _doubleDoorPlanInstance.na_resetView(config);
            if (_doubleDoorElevationInstance) _doubleDoorElevationInstance.na_resetView(config);
            return;
        }
        if (!_instance) return;
        _instance.na_resetView(config);
    }
    // ---------------------------------------------------------------


    // FUNCTION | Export Current Model as DXF
    // ------------------------------------------------------------
    function na_exportDxf() {
        const config = Na_DynamicUI.na_getConfig();
        if (config.double_door_mode === true &&
            window.Na__ExtDouble__DxfExporter &&
            typeof window.Na__ExtDouble__DxfExporter.na_export_dxf === 'function') {
            return window.Na__ExtDouble__DxfExporter.na_export_dxf(config);
        }
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
    const doubleDoorPlanWrapper = document.getElementById('na-double-door-plan-wrapper');
    const doubleDoorElevationWrapper = document.getElementById('na-double-door-elevation-wrapper');
    
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
        const doubleDoorMode = Na_DynamicUI.na_getConfig().double_door_mode === true;
        const activeWrapper = doubleDoorMode && doubleDoorPlanWrapper ? doubleDoorPlanWrapper : wrapper;
        startHeight = activeWrapper.offsetHeight;
        document.body.style.cursor = 'ns-resize';
        e.preventDefault();
    });
    
    // Mouse move - update size
    document.addEventListener('mousemove', function(e) {
        if (!isResizing) return;
        
        const deltaY = e.clientY - startY;
        const newHeight = Math.max(100, Math.min(600, startHeight + deltaY));
        const doubleDoorMode = Na_DynamicUI.na_getConfig().double_door_mode === true;
        if (doubleDoorMode) {
            if (doubleDoorPlanWrapper) doubleDoorPlanWrapper.style.height = newHeight + 'px';
            if (doubleDoorElevationWrapper) doubleDoorElevationWrapper.style.height = newHeight + 'px';
        } else {
            wrapper.style.height = newHeight + 'px';
        }
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

    if (typeof window.na_requestDoorHandleAssetOptions === 'function') {
        window.na_requestDoorHandleAssetOptions();
    }
    
    console.log('[NA_UI] Element Assembly Studio Pro - Window UI initialized successfully');
    console.log('[NA_UI] ═══════════════════════════════════════════════════════');
});
// ---------------------------------------------------------------

// endregion ===================================================================

// =============================================================================
// END OF FILE
// =============================================================================
