/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - WINDOW SYSTEM - VIEWPORT SVG GENERATOR
   =============================================================================
   
   FILE       : Na__AssemblyStudio__WindowSystem__Viewport__SvgGenerator__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : SVG markup generation for the Window System preview
   CREATED    : 2026
   RELOCATED  : 01-May-2026 (was Na__WindowConfiguratorTool__Viewport__SvgGenerator__.js)
   
   DESCRIPTION:
   - Generates SVG markup from window configuration
   - Supports frames, mullions, casements, and glaze bars
   - Multi-casement openings (1-6 panels per opening)
   - Individual casement rail/stile sizing
   - Clickable casement removal targets
   - Dimension annotations
   - Pure rendering functions with no side effects
   - Window-specific markup; door tab uses Door*Generator modules in this folder.
   
   NAMING CONVENTION:
   - All functions use na_ prefix (lowercase)
   - Exported to window.Na__Viewport__SvgGenerator object (preserved global name
     so existing consumers in Export__Dxf__.js, UiLogic__.js, and the bridge
     keep working without any rename).
   
   ============================================================================= */

// =============================================================================
// REGION | SVG Generator Module
// =============================================================================

const Na__Viewport__SvgGenerator = (function() {

// -----------------------------------------------------------------------------
// REGION | Frame Thickness & Material Colour
// -----------------------------------------------------------------------------

    // FUNCTION | Resolve Effective Frame Thicknesses
    // ------------------------------------------------------------
    function na_getEffectiveFrameThicknesses(config) {
        if (window.Na_DynamicUI && typeof window.Na_DynamicUI.na_getEffectiveFrameThicknesses === 'function') {
            return window.Na_DynamicUI.na_getEffectiveFrameThicknesses(config);
        }

        const uniformThickness = (config.frame_thickness_mm != null) ? Number(config.frame_thickness_mm) : 50;
        const useAdvancedFrameControls = config.advanced_frame_controls === true;

        function na_resolveFrameSideThickness(sideKey) {
            const rawValue = useAdvancedFrameControls ? config[sideKey] : uniformThickness;
            return Math.max(0, Number(rawValue != null ? rawValue : uniformThickness));
        }

        return {
            top: na_resolveFrameSideThickness('frame_top_thickness_mm'),
            bottom: na_resolveFrameSideThickness('frame_bottom_thickness_mm'),
            left: na_resolveFrameSideThickness('frame_left_thickness_mm'),
            right: na_resolveFrameSideThickness('frame_right_thickness_mm')
        };
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Get Material Color by ID
    // ------------------------------------------------------------
    // Resolves the SVG preview tint for a given frame material ID against
    // window.NA_FRAME_FINISH_SWATCHES (live data pushed by Ruby from the
    // central materials JSON). The SVG-only fallback is plain white if the
    // swatches haven't arrived yet -- the Frame Finish card row stays
    // hidden in that case so the user can't trigger an unknown ID anyway.
    // @param {string} materialId - Material ID (e.g., 'MAT120__GenericWood')
    // @returns {string} Hex color string (e.g., '#D2B48C')
    function na_getMaterialColor(materialId) {
        const swatches = window.NA_FRAME_FINISH_SWATCHES;
        if (Array.isArray(swatches)) {
            for (let i = 0; i < swatches.length; i++) {
                if (swatches[i] && swatches[i].id === materialId) {
                    return swatches[i].hex || swatches[i].color || '#FFFFFF';
                }
            }
        }
        return '#FFFFFF';
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Keys, Removal Sets & Panel State
// -----------------------------------------------------------------------------

    // FUNCTION | Build Glaze Bar Storage Key
    // ------------------------------------------------------------
    function na_getGlazebarKey(openingIndex, cellIndex, panelIndex, sashIndex, orientation, barIndex) {
        return `${openingIndex}:${cellIndex}:${panelIndex}:${sashIndex}:${orientation}:${barIndex}`;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Build Removed Glaze Bar Set
    // ------------------------------------------------------------
    function na_getRemovedGlazebarSet(removedGlazebars) {
        return new Set(Array.isArray(removedGlazebars) ? removedGlazebars.map(key => String(key)) : []);
    }
    // ---------------------------------------------------------------

    // FUNCTION | Build Leaded Glass Cell Storage Key
    // ------------------------------------------------------------
    // Cells are the sub-panes between glaze bars: col 0 = leftmost,
    // row 0 = bottom (logical y-up), matching the Ruby 3D convention.
    function na_getLeadedCellKey(openingIndex, cellIndex, panelIndex, sashIndex, col, row) {
        return `${openingIndex}:${cellIndex}:${panelIndex}:${sashIndex}:${col}:${row}`;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Build Disabled Leaded Cell Set
    // ------------------------------------------------------------
    function na_getDisabledLeadedCellSet(disabledCells) {
        return new Set(Array.isArray(disabledCells) ? disabledCells.map(key => String(key)) : []);
    }
    // ---------------------------------------------------------------

    // FUNCTION | Build Casement Storage Key
    // ------------------------------------------------------------
    function na_getCasementKey(openingIndex, cellIndex, panelIndex) {
        return `${openingIndex}:${cellIndex}:${panelIndex}`;             // <-- Per-panel removal key
    }
    // ---------------------------------------------------------------

    // FUNCTION | Build Removed Casement Set With Legacy Bare-Integer Support
    // ------------------------------------------------------------
    // Bare integer entries (e.g. 0) are legacy opening-wide removals.
    // They are kept as a separate set indexed by openingIndex.
    function na_getRemovedCasementSet(removedCasements) {
        const keySet = new Set();                                        // <-- Per-panel keyed entries
        const legacyOpeningSet = new Set();                              // <-- Legacy bare-integer opening indices

        if (!Array.isArray(removedCasements)) {
            return { keys: keySet, legacyOpenings: legacyOpeningSet };
        }

        removedCasements.forEach(entry => {
            if (entry === null || entry === undefined) return;
            const stringValue = String(entry);
            if (stringValue.indexOf(':') !== -1) {
                keySet.add(stringValue);                                 // <-- Already a keyed entry
                return;
            }

            const numericValue = Number(stringValue);
            if (Number.isFinite(numericValue) && numericValue >= 0) {
                legacyOpeningSet.add(Math.trunc(numericValue));          // <-- Legacy opening-wide flag
            }
        });

        return { keys: keySet, legacyOpenings: legacyOpeningSet };
    }
    // ---------------------------------------------------------------

    // FUNCTION | Check Panel Casement Removal
    // ------------------------------------------------------------
    function na_isPanelCasementRemoved(removedSet, openingIndex, cellIndex, panelIndex) {
        if (!removedSet) return false;
        if (removedSet.legacyOpenings && removedSet.legacyOpenings.has(openingIndex)) return true;
        if (removedSet.keys && removedSet.keys.has(na_getCasementKey(openingIndex, cellIndex, panelIndex))) return true;
        return false;
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | SVG Render Bucket Merge Helpers
// -----------------------------------------------------------------------------

    // FUNCTION | Create SVG Render Bucket
    // ------------------------------------------------------------
    function na_createSvgRenderBucket() {
        return {
            svg: '',
            clickTargetsSvg: '',                                         // <-- Glaze bar click rects
            casementClickTargetsSvg: '',                                 // <-- Per-panel casement click rects
            leadedClickTargetsSvg: ''                                    // <-- Per-cell leaded glass click rects
        };
    }
    // ---------------------------------------------------------------

    // FUNCTION | Merge SVG Render Buckets
    // ------------------------------------------------------------
    function na_mergeSvgRenderBuckets(targetBucket, sourceBucket) {
        targetBucket.svg += sourceBucket.svg;
        targetBucket.clickTargetsSvg += sourceBucket.clickTargetsSvg;
        targetBucket.casementClickTargetsSvg += (sourceBucket.casementClickTargetsSvg || ''); // <-- Forward casement targets
        targetBucket.leadedClickTargetsSvg += (sourceBucket.leadedClickTargetsSvg || '');     // <-- Forward leaded cell targets
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Main Window Composition (Frame → Openings → Cill → Dimensions)
// -----------------------------------------------------------------------------

    // FUNCTION | Generate SVG Content for Window with Mullions and Optional Casements
    // ------------------------------------------------------------
    // @param {Object} config - Window configuration object
    // @returns {string} SVG markup as string
    function na_generateWindowSvg(config) {
        const width = config.width_mm || 900;
        const height = config.height_mm || 1200;
        const frameThicknesses = na_getEffectiveFrameThicknesses(config);
        const topFrameThickness = frameThicknesses.top;
        const bottomFrameThickness = frameThicknesses.bottom;
        const leftFrameThickness = frameThicknesses.left;
        const rightFrameThickness = frameThicknesses.right;
        const casementWidth = config.casement_width_mm || 65;
        const showCasements = config.show_casements !== false;
        const slidingSashWindow = config.sliding_sash_window === true;
        const slidingSashOverlap = Math.max(0, Math.min(60, config.sliding_sash_overlap_mm || 20));
        const casementsPerOpening = Math.max(1, Math.min(6, config.casements_per_opening || 1));
        const numMullions = config.mullions || 0;
        const mullionWidth = config.mullion_width_mm || 40;
        const transomCount = Math.max(0, Math.min(3, Math.round(config.transoms || 0)));
        const transomWidth = config.transom_width_mm || 40;
        const transomBottoms = na_getActiveTransomBottoms(config, transomCount);
        const removedTransomSegments = na_getRemovedTransomSegmentSet(config.removed_transom_segments);
        const removedGlazebars = na_getRemovedGlazebarSet(config.removed_glazebars);
        const hBars = config.horizontal_glaze_bars || 0;
        const vBars = config.vertical_glaze_bars || 0;
        const barWidth = config.glaze_bar_width_mm || 25;
        // Advanced glazebar options (Margin Glazing + Gothic Arch). Packaged
        // up so all the per-cell render paths receive the same flags.
        const advancedGlazebar = {
            marginEnabled  : config.glazebar_margin_enabled === true,
            marginOffset   : Math.max(0, Number(config.glazebar_margin_offset_mm || 0)),
            archEnabled    : config.glazebar_gothic_arch_enabled === true,
            archAmount     : Math.max(1, Math.min(8, Math.round(config.glazebar_gothic_arch_amount || 2))),    // <-- V1.9.4 Allow single lancet arch (was clamped to 2 minimum)
            archHeight     : Math.max(0, Number(config.glazebar_gothic_arch_height_mm || 0)),
            hOffsetMm      : Number(config.glazebar_horizontal_offset_mm || 0),             // <-- Uniform vertical nudge for all horizontal bars (positive = up in mm)
            hOffsetsMm     : Na__GlazebarMath.na_collectBarOffsets(config, 'glazebar_h_offset_', hBars),   // <-- Per-bar vertical nudges (positive = up)
            vOffsetsMm     : Na__GlazebarMath.na_collectBarOffsets(config, 'glazebar_v_offset_', vBars)    // <-- Per-bar horizontal nudges (positive = right)
        };
        const leadedGlass = {
            enabled      : config.leaded_glass_enabled === true,
            hBars        : Math.max(0, Math.min(8, Math.round(Number(config.horizontal_leaded_bars || 0)))),
            vBars        : Math.max(0, Math.min(8, Math.round(Number(config.vertical_leaded_bars || 0)))),
            widthMm      : Math.max(2, Number(config.leaded_width_mm || 6)),
            centreLines  : config.leaded_centre_lines_only === true,
            colourId     : na_resolveLeadedColourId(config),
            disabledCells: na_getDisabledLeadedCellSet(config.leaded_disabled_cells)        // <-- Per-cell opt-out toggled from the preview
        };
        const frameMaterialId = config.frame_material_id || 'MAT120__GenericWood';
        const frameColor = na_getMaterialColor(frameMaterialId);
        const showDimensions = config.show_dimensions !== false;
        const hasCill = config.has_cill !== false;
        const removedCasementSet = na_getRemovedCasementSet(config.removed_casements); // <-- Per-panel removal set with legacy support

        const useIndividualSizes = config.casement_sizes_individual === true;
        const casTopRail = useIndividualSizes ? (config.casement_top_rail_mm || casementWidth) : casementWidth;
        const casBottomRail = useIndividualSizes ? (config.casement_bottom_rail_mm || casementWidth) : casementWidth;
        const casLeftStile = useIndividualSizes ? (config.casement_left_stile_mm || casementWidth) : casementWidth;
        const casRightStile = useIndividualSizes ? (config.casement_right_stile_mm || casementWidth) : casementWidth;
        const topSashBottomRail = Math.max(0, Number(config.top_sash_bottom_rail_mm || casBottomRail));
        const bottomSashTopRail = config.bottom_sash_top_rail_override === true
            ? Math.max(0, Number(config.bottom_sash_top_rail_mm || casTopRail))
            : Math.max(0, Number(casTopRail));
        const sashHornOptions = {
            enabled: config.sash_horns_enabled !== false,
            type: config.sash_horn_type || '1'
        };

        let svg = '';
        let openingClickTargetsSvg = '';
        let transomClickTargetsSvg = '';
        let glazebarClickTargetsSvg = '';
        let leadedCellClickTargetsSvg = '';

        const doorMode = config.door_mode === true;
        const doorPanelHeightMm = doorMode ? Math.max(0, config.door_panel_height_mm || 400) : 0;

        const numOpenings = numMullions + 1;
        const innerWidth = width - leftFrameThickness - rightFrameThickness;
        const innerHeight = height - topFrameThickness - bottomFrameThickness;
        const totalMullionWidth = numMullions * mullionWidth;
        const availableWidth = innerWidth - totalMullionWidth;
        const openingWidth = availableWidth / numOpenings;

        if (leftFrameThickness > 0) {
            svg += na_svgRect(0, 0, leftFrameThickness, height, frameColor, '#000', 1);
        }
        if (rightFrameThickness > 0) {
            svg += na_svgRect(width - rightFrameThickness, 0, rightFrameThickness, height, frameColor, '#000', 1);
        }
        if (bottomFrameThickness > 0) {
            svg += na_svgRect(leftFrameThickness, 0, innerWidth, bottomFrameThickness, frameColor, '#000', 1);
        }
        if (topFrameThickness > 0) {
            svg += na_svgRect(leftFrameThickness, height - topFrameThickness, innerWidth, topFrameThickness, frameColor, '#000', 1);
        }

        for (let m = 1; m <= numMullions; m++) {
            const mullionX = leftFrameThickness + (m * openingWidth) + ((m - 1) * mullionWidth);
            svg += na_svgRect(mullionX, bottomFrameThickness, mullionWidth, innerHeight, frameColor, '#000', 1);
        }

        for (let i = 0; i < numOpenings; i++) {
            const openingX = leftFrameThickness + (i * (openingWidth + mullionWidth));
            const openingY = bottomFrameThickness;
            const openingLayout = na_getOpeningCellLayout(
                i,
                openingX,
                openingY,
                openingWidth,
                innerHeight,
                transomBottoms,
                transomWidth,
                removedTransomSegments
            );

            openingLayout.transomSegments.forEach(segment => {
                svg += na_svgRect(segment.x, segment.y, segment.width, segment.height, frameColor, '#000', 1);
                transomClickTargetsSvg += na_generateTransomClickTargetSvg(segment);
            });

            openingLayout.cells.forEach((cell, cellIndex) => {
                const openingCellRender = na_generateOpeningCellSvg(
                    cell,
                    {
                        openingIndex: i,
                        cellIndex: cellIndex,
                        showCasements: showCasements,
                        removedCasementSet: removedCasementSet,
                        slidingSashWindow: slidingSashWindow,
                        slidingSashOverlap: slidingSashOverlap,
                        casementsPerOpening: casementsPerOpening,
                        casTopRail: casTopRail,
                        casBottomRail: casBottomRail,
                        topSashBottomRail: topSashBottomRail,
                        bottomSashTopRail: bottomSashTopRail,
                        casLeftStile: casLeftStile,
                        casRightStile: casRightStile,
                        sashHornOptions: sashHornOptions,
                        frameColor: frameColor,
                        hBars: hBars,
                        vBars: vBars,
                        barWidth: barWidth,
                        advancedGlazebar: advancedGlazebar,
                        leadedGlass: leadedGlass,
                        removedGlazebars: removedGlazebars,
                        doorMode: doorMode,
                        doorPanelHeightMm: doorPanelHeightMm,
                        doorConfig: doorMode ? config : null
                    }
                );
                svg += openingCellRender.svg;
                openingClickTargetsSvg += openingCellRender.casementClickTargetsSvg;
                glazebarClickTargetsSvg += openingCellRender.clickTargetsSvg;
                leadedCellClickTargetsSvg += openingCellRender.leadedClickTargetsSvg;
            });
        }

        if (hasCill && bottomFrameThickness > 0) {
            const cillHeight = config.cill_height_mm || 50;
            svg += na_svgRect(0, -cillHeight, width, cillHeight, '#A0908A', '#000', 1);
        }

        if (showDimensions) {
            svg += na_svgDimensions(width, height);
        }

        svg += openingClickTargetsSvg;
        svg += transomClickTargetsSvg;
        svg += leadedCellClickTargetsSvg;                                 // <-- Below glazebar targets so bar clicks win
        svg += glazebarClickTargetsSvg;

        return svg;
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Transom Stack — Layout & Removed Segment Queries
// -----------------------------------------------------------------------------

    // FUNCTION | Get Active Transom Heights
    // ------------------------------------------------------------
    function na_getActiveTransomBottoms(config, transomCount) {
        return [
            Number(config.transom_1_y_mm || 0),
            Number(config.transom_2_y_mm || 0),
            Number(config.transom_3_y_mm || 0)
        ].slice(0, transomCount);
    }
    // ---------------------------------------------------------------

    // FUNCTION | Build Removed Transom Segment Set
    // ------------------------------------------------------------
    function na_getRemovedTransomSegmentSet(removedSegments) {
        return new Set(Array.isArray(removedSegments) ? removedSegments.map(segment => String(segment)) : []);
    }
    // ---------------------------------------------------------------

    // FUNCTION | Check Transom Segment Removal
    // ------------------------------------------------------------
    function na_isTransomSegmentRemoved(removedSegments, openingIndex, transomIndex) {
        return removedSegments.has(`${openingIndex}:${transomIndex}`);
    }
    // ---------------------------------------------------------------

    // FUNCTION | Build Opening Cell Layout
    // ------------------------------------------------------------
    function na_getOpeningCellLayout(openingIndex, openingX, openingY, openingWidth, innerHeight, transomBottoms, transomWidth, removedSegments) {
        const cells = [];
        const transomSegments = [];
        let cellBottom = 0;

        transomBottoms.forEach((transomBottom, transomIndex) => {
            if (na_isTransomSegmentRemoved(removedSegments, openingIndex, transomIndex)) {
                return;
            }

            const cellHeight = transomBottom - cellBottom;
            if (cellHeight > 0) {
                cells.push({
                    x: openingX,
                    y: openingY + cellBottom,
                    width: openingWidth,
                    height: cellHeight
                });
            }

            transomSegments.push({
                x: openingX,
                y: openingY + transomBottom,
                width: openingWidth,
                height: transomWidth,
                openingIndex: openingIndex,
                transomIndex: transomIndex
            });

            cellBottom = transomBottom + transomWidth;
        });

        const topCellHeight = innerHeight - cellBottom;
        if (topCellHeight > 0) {
            cells.push({
                x: openingX,
                y: openingY + cellBottom,
                width: openingWidth,
                height: topCellHeight
            });
        }

        return { cells, transomSegments };
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Per-Opening Cell — Panel Loop & Casement Routing
// -----------------------------------------------------------------------------

    // FUNCTION | Generate SVG for One Opening Cell
    // ------------------------------------------------------------
    function na_generateOpeningCellSvg(cell, options) {
        const renderBucket = na_createSvgRenderBucket();
        const panelWidth = cell.width / options.casementsPerOpening;
        const showCasements = options.showCasements !== false;            // <-- Master casement visibility flag

        for (let p = 0; p < options.casementsPerOpening; p++) {
            const panelX = cell.x + (p * panelWidth);
            const panelContext = {
                openingIndex: options.openingIndex,
                cellIndex: options.cellIndex,
                panelIndex: p
            };

            const panelIsRemoved = na_isPanelCasementRemoved(             // <-- Per-panel removal lookup
                options.removedCasementSet,
                options.openingIndex,
                options.cellIndex,
                p
            );
            const panelHasCasement = showCasements && !panelIsRemoved;    // <-- Final per-panel render decision

            if (panelHasCasement) {
                if (options.doorMode) {
                    na_mergeSvgRenderBuckets(
                        renderBucket,
                        na_generateDoorCasementSvg(
                            panelX, cell.y, panelWidth, cell.height,
                            options.casTopRail, options.casBottomRail, options.casLeftStile, options.casRightStile,
                            options.frameColor, options.hBars, options.vBars, options.barWidth,
                            options.doorPanelHeightMm, options.doorConfig,
                            panelContext, options.removedGlazebars, options.advancedGlazebar,
                            options.leadedGlass
                        )
                    );
                } else if (options.slidingSashWindow) {
                    na_mergeSvgRenderBuckets(
                        renderBucket,
                        na_generateSlidingSashPanelSvg(
                            panelX, cell.y, panelWidth, cell.height,
                            options.casTopRail, options.casBottomRail, options.topSashBottomRail, options.bottomSashTopRail, options.casLeftStile, options.casRightStile,
                            options.frameColor, options.hBars, options.vBars, options.barWidth, options.slidingSashOverlap,
                            panelContext, options.removedGlazebars, options.sashHornOptions, options.advancedGlazebar,
                            options.leadedGlass
                        )
                    );
                } else {
                    na_mergeSvgRenderBuckets(
                        renderBucket,
                        na_generateSingleCasementSvg(
                            panelX, cell.y, panelWidth, cell.height,
                            options.casTopRail, options.casBottomRail, options.casLeftStile, options.casRightStile,
                            options.frameColor, options.hBars, options.vBars, options.barWidth,
                            {
                                openingIndex: panelContext.openingIndex,
                                cellIndex: panelContext.cellIndex,
                                panelIndex: panelContext.panelIndex,
                                sashIndex: 0
                            },
                            options.removedGlazebars,
                            options.advancedGlazebar,
                            options.leadedGlass
                        )
                    );
                }
            } else {
                renderBucket.svg += na_svgRect(panelX, cell.y, panelWidth, cell.height, 'rgba(135, 206, 235, 0.3)', '#87CEEB', 0.5);

                if (options.hBars > 0 || options.vBars > 0 || (options.advancedGlazebar && options.advancedGlazebar.archEnabled)) {
                    na_mergeSvgRenderBuckets(
                        renderBucket,
                        na_generateGlazeBarsSvg(
                            panelX,
                            cell.y,
                            panelWidth,
                            cell.height,
                            options.hBars,
                            options.vBars,
                            options.barWidth,
                            options.frameColor,
                            {
                                openingIndex: panelContext.openingIndex,
                                cellIndex: panelContext.cellIndex,
                                panelIndex: panelContext.panelIndex,
                                sashIndex: 0
                            },
                            options.removedGlazebars,
                            options.advancedGlazebar
                        )
                    );
                }

                renderBucket.svg += na_generateLeadedGlassSvg(
                    panelX, cell.y, panelWidth, cell.height, options.leadedGlass,
                    {
                        hBars: options.hBars,
                        vBars: options.vBars,
                        barWidth: options.barWidth,
                        advancedGlazebar: options.advancedGlazebar,
                        panelContext: {
                            openingIndex: panelContext.openingIndex,
                            cellIndex: panelContext.cellIndex,
                            panelIndex: panelContext.panelIndex,
                            sashIndex: 0
                        },
                        clickBucket: renderBucket
                    }
                );

                if (showCasements && panelIsRemoved) {                    // <-- Per-panel removed indicator
                    renderBucket.svg += na_generatePanelRemovedIndicatorSvg(panelX, cell.y, panelWidth, cell.height);
                }
            }

            if (showCasements) {                                          // <-- Per-panel click target always emitted when casements visible
                renderBucket.casementClickTargetsSvg += na_generateCasementClickTargetSvg(
                    panelX,
                    cell.y,
                    panelWidth,
                    cell.height,
                    panelContext
                );
            }
        }

        return renderBucket;
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Click Targets — Casement / Transom / Removed Indicator
// -----------------------------------------------------------------------------

    // FUNCTION | Generate Per-Panel Removed Casement Indicator SVG
    // ------------------------------------------------------------
    function na_generatePanelRemovedIndicatorSvg(panelX, panelY, panelWidth, panelHeight) {
        const inset = 4;                                                  // <-- Visual inset matches legacy opening indicator
        const innerWidth = Math.max(0, panelWidth - inset * 2);
        const innerHeight = Math.max(0, panelHeight - inset * 2);
        if (innerWidth <= 0 || innerHeight <= 0) return '';
        const svgY = -panelY - panelHeight + inset;
        return `<rect class="na-casement-removed-indicator"
                      x="${panelX + inset}" y="${svgY}"
                      width="${innerWidth}" height="${innerHeight}"
                      fill="none" stroke="rgba(244, 67, 54, 0.5)" stroke-width="2" stroke-dasharray="10 5"
                      pointer-events="none"/>`;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Generate Casement Click Target SVG
    // ------------------------------------------------------------
    function na_generateCasementClickTargetSvg(panelX, panelY, panelWidth, panelHeight, panelContext) {
        const svgY = -panelY - panelHeight;
        return `<rect class="na-opening-click-target"
                      data-opening-index="${panelContext.openingIndex}"
                      data-cell-index="${panelContext.cellIndex}"
                      data-panel-index="${panelContext.panelIndex}"
                      x="${panelX}" y="${svgY}"
                      width="${panelWidth}" height="${panelHeight}"
                      fill="transparent"
                      style="cursor: pointer; pointer-events: all;"/>`;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Generate Transom Click Target SVG
    // ------------------------------------------------------------
    function na_generateTransomClickTargetSvg(segment) {
        const svgY = -segment.y - segment.height;
        return `<rect class="na-transom-click-target"
                      data-opening-index="${segment.openingIndex}"
                      data-transom-index="${segment.transomIndex}"
                      x="${segment.x}" y="${svgY}"
                      width="${segment.width}" height="${segment.height}"
                      fill="rgba(0, 0, 0, 0.001)"
                      stroke="none"
                      style="cursor: pointer; pointer-events: all;"/>`;
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Casement Styles — Fixed & Sliding Sash
// -----------------------------------------------------------------------------

    // FUNCTION | Generate SVG for a Single Casement with Individual Sizes
    // ------------------------------------------------------------
    function na_generateSingleCasementSvg(x, y, width, height, topRail, bottomRail, leftStile, rightStile, frameColor, hBars, vBars, barWidth, panelContext, removedGlazebars, advancedGlazebar, leadedGlass) {
        const renderBucket = na_createSvgRenderBucket();

        renderBucket.svg += na_svgRect(x, y, leftStile, height, frameColor, '#000', 0.5);
        renderBucket.svg += na_svgRect(x + width - rightStile, y, rightStile, height, frameColor, '#000', 0.5);
        renderBucket.svg += na_svgRect(x + leftStile, y, width - leftStile - rightStile, bottomRail, frameColor, '#000', 0.5);
        renderBucket.svg += na_svgRect(x + leftStile, y + height - topRail, width - leftStile - rightStile, topRail, frameColor, '#000', 0.5);

        const glassX = x + leftStile;
        const glassY = y + bottomRail;
        const glassWidth = width - leftStile - rightStile;
        const glassHeight = height - topRail - bottomRail;

        renderBucket.svg += na_svgRect(glassX, glassY, glassWidth, glassHeight, 'rgba(135, 206, 235, 0.3)', '#87CEEB', 0.5);

        const archActive = !!(advancedGlazebar && advancedGlazebar.archEnabled);
        if (hBars > 0 || vBars > 0 || archActive) {
            na_mergeSvgRenderBuckets(
                renderBucket,
                na_generateGlazeBarsSvg(
                    glassX,
                    glassY,
                    glassWidth,
                    glassHeight,
                    hBars,
                    vBars,
                    barWidth,
                    frameColor,
                    panelContext,
                    removedGlazebars,
                    advancedGlazebar
                )
            );
        }

        renderBucket.svg += na_generateLeadedGlassSvg(
            glassX, glassY, glassWidth, glassHeight, leadedGlass,
            {
                hBars: hBars,
                vBars: vBars,
                barWidth: barWidth,
                advancedGlazebar: advancedGlazebar,
                panelContext: panelContext,
                clickBucket: renderBucket
            }
        );

        return renderBucket;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Resolve Sash Horn Asset From Ruby-Fed Cache
    // ------------------------------------------------------------
    function na_getSashHornAsset(type) {
        const cache = window.NA_SASH_HORN_ASSET_CACHE || {};
        const typeKey = String(type || '1').replace(/^Type-?0?/i, '');
        return cache[typeKey] || cache[String(Number(typeKey) || 1)] || null;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Extract Sash Horn Elevation Data
    // ------------------------------------------------------------
    function na_getSashHornElevationData(type) {
        const asset = na_getSashHornAsset(type);
        const elevation = asset && asset.Na__Asset__Elevation2D;
        if (!elevation || !Array.isArray(elevation.Na__Geometry__Paths)) return null;

        const polygon = elevation.Na__Geometry__Paths.find(path => {
            return path && path.PathType === 'Polygon' && Array.isArray(path.Vertices_mm);
        });
        const bbox = elevation.Na__Geometry__BoundingBox || {};
        if (!polygon || polygon.Vertices_mm.length < 3) return null;

        return {
            vertices: polygon.Vertices_mm,
            bbox: {
                minX: Number(bbox.Na__Geometry__MinX_mm || 0),
                maxX: Number(bbox.Na__Geometry__MaxX_mm || 40),
                minY: Number(bbox.Na__Geometry__MinY_mm || 0),
                maxY: Number(bbox.Na__Geometry__MaxY_mm || 70),
                width: Number(bbox.Na__Geometry__Width_mm || 40)
            }
        };
    }
    // ---------------------------------------------------------------

    // FUNCTION | Build Logical Sash Horn Polygon Points
    // ------------------------------------------------------------
    function na_buildSashHornLogicalPoints(data, side, panelX, topSashBottomY, panelWidth, leftStile, rightStile) {
        const bbox = data.bbox;
        const leftOuterX = panelX;
        const rightOuterX = panelX + panelWidth;

        return data.vertices.map(vertex => {
            const localX = Number(vertex.X || 0);
            const localY = Number(vertex.Y || 0);
            const x = side === 'left'
                ? leftOuterX + (bbox.maxX - localX)
                : rightOuterX - bbox.width + (localX - bbox.minX);

            return {
                x: x,
                y: topSashBottomY - bbox.maxY + localY
            };
        });
    }
    // ---------------------------------------------------------------

    // FUNCTION | Generate Sash Horn SVG Polygon
    // ------------------------------------------------------------
    function na_generateSashHornPolygonSvg(points, fill, stroke, strokeWidth) {
        if (!Array.isArray(points) || points.length < 3) return '';
        const pointList = points.map(point => `${point.x},${-point.y}`).join(' ');
        return `<polygon points="${pointList}" fill="${fill}" stroke="${stroke}" stroke-width="${strokeWidth}"/>`;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Generate Sliding Sash Horns SVG
    // ------------------------------------------------------------
    function na_generateSlidingSashHornsSvg(panelX, topSashBottomY, panelWidth, leftStile, rightStile, frameColor, sashHornOptions) {
        if (!sashHornOptions || sashHornOptions.enabled === false) return '';

        const data = na_getSashHornElevationData(sashHornOptions.type);
        if (!data) return '';

        const leftPoints = na_buildSashHornLogicalPoints(data, 'left', panelX, topSashBottomY, panelWidth, leftStile, rightStile);
        const rightPoints = na_buildSashHornLogicalPoints(data, 'right', panelX, topSashBottomY, panelWidth, leftStile, rightStile);
        return na_generateSashHornPolygonSvg(leftPoints, frameColor, '#000', 0.5) +
               na_generateSashHornPolygonSvg(rightPoints, frameColor, '#000', 0.5);
    }
    // ---------------------------------------------------------------

    // FUNCTION | Generate Sliding Sash SVG for One Panel
    // ------------------------------------------------------------
    // Draws top and bottom casements stacked vertically.
    // Bottom sash gets a subtle shading overlay to indicate setback depth.
    function na_generateSlidingSashPanelSvg(x, y, width, height, topRail, bottomRail, topSashBottomRail, bottomSashTopRail, leftStile, rightStile, frameColor, hBars, vBars, barWidth, overlapMm, panelContext, removedGlazebars, sashHornOptions, advancedGlazebar, leadedGlass) {
        const renderBucket = na_createSvgRenderBucket();

        const sashHeight = height / 2;
        const sashOverlap = Math.max(0, Math.min(overlapMm || 0, sashHeight - 1));
        const bottomSashY = y;
        const topSashY = y + sashHeight;

        // Bottom sash: arches are NOT drawn here even when enabled, because
        // architectural gothic tracery sits at the head of the assembly only.
        // We pass an arch-disabled clone of advancedGlazebar so margin glazing
        // still applies if the user enabled it.
        const advancedNoArch = advancedGlazebar
            ? { marginEnabled: advancedGlazebar.marginEnabled, marginOffset: advancedGlazebar.marginOffset,
                archEnabled: false, archAmount: 0, archHeight: 0,
                hOffsetMm: advancedGlazebar.hOffsetMm,
                hOffsetsMm: advancedGlazebar.hOffsetsMm,
                vOffsetsMm: advancedGlazebar.vOffsetsMm }
            : undefined;
        na_mergeSvgRenderBuckets(
            renderBucket,
            na_generateSingleCasementSvg(
            x, bottomSashY, width, sashHeight + sashOverlap,
            bottomSashTopRail, bottomRail, leftStile, rightStile,
                frameColor, hBars, vBars, barWidth,
                {
                    openingIndex: panelContext.openingIndex,
                    cellIndex: panelContext.cellIndex,
                    panelIndex: panelContext.panelIndex,
                    sashIndex: 1
                },
                removedGlazebars,
                advancedNoArch,
                leadedGlass
            )
        );

        // Reduced by 50% from previous 0.2 intensity.
        renderBucket.svg += na_svgRect(x, bottomSashY, width, sashHeight + sashOverlap, 'rgba(0, 0, 0, 0.1)', 'none', 0);

        // Top sash gets the full advancedGlazebar (margin + arches if enabled).
        na_mergeSvgRenderBuckets(
            renderBucket,
            na_generateSingleCasementSvg(
            x, topSashY, width, sashHeight,
            topRail, topSashBottomRail, leftStile, rightStile,
                frameColor, hBars, vBars, barWidth,
                {
                    openingIndex: panelContext.openingIndex,
                    cellIndex: panelContext.cellIndex,
                    panelIndex: panelContext.panelIndex,
                    sashIndex: 0
                },
                removedGlazebars,
                advancedGlazebar,
                leadedGlass
            )
        );

        renderBucket.svg += na_generateSlidingSashHornsSvg(
            x,
            topSashY,
            width,
            leftStile,
            rightStile,
            frameColor,
            sashHornOptions
        );

        return renderBucket;
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Door Mode — Casement Shell & Raised-Panel Inner
// -----------------------------------------------------------------------------

    // FUNCTION | Generate Door Casement SVG
    // ------------------------------------------------------------
    // Draws a full-height casement with stiles, top/bottom/mid rails,
    // glass + glaze bars in the upper zone, and door panel content in the lower zone.
    function na_generateDoorCasementSvg(x, y, width, height, topRail, bottomRail, leftStile, rightStile, frameColor, hBars, vBars, barWidth, doorPanelHeightMm, doorConfig, panelContext, removedGlazebars, advancedGlazebar, leadedGlass) {
        const renderBucket = na_createSvgRenderBucket();
        const midRailW = (doorConfig && doorConfig.door_mid_rail_width_mm) || 150;
        const baseRailW = (doorConfig && doorConfig.door_base_rail_width_mm) || 200;
        const doorPanelH = Math.min(Math.max(0, doorPanelHeightMm), height - topRail - midRailW - baseRailW - 50);

        // Full-height stiles
        renderBucket.svg += na_svgRect(x, y, leftStile, height, frameColor, '#000', 0.5);
        renderBucket.svg += na_svgRect(x + width - rightStile, y, rightStile, height, frameColor, '#000', 0.5);

        const railClearWidth = width - leftStile - rightStile;

        // Base rail (bottom of door)
        renderBucket.svg += na_svgRect(x + leftStile, y, railClearWidth, baseRailW, frameColor, '#000', 0.5);
        // Top rail
        renderBucket.svg += na_svgRect(x + leftStile, y + height - topRail, railClearWidth, topRail, frameColor, '#000', 0.5);

        // Mid-rail at the glass/panel junction
        const midRailY = y + baseRailW + doorPanelH;
        renderBucket.svg += na_svgRect(x + leftStile, midRailY, railClearWidth, midRailW, frameColor, '#000', 0.5);

        // Upper zone: glass + glaze bars
        const glassX = x + leftStile;
        const glassY = midRailY + midRailW;
        const glassWidth = railClearWidth;
        const glassHeight = height - topRail - midRailW - doorPanelH - baseRailW;

        if (glassHeight > 0 && glassWidth > 0) {
            renderBucket.svg += na_svgRect(glassX, glassY, glassWidth, glassHeight, 'rgba(135, 206, 235, 0.3)', '#87CEEB', 0.5);

            const archActiveDoor = !!(advancedGlazebar && advancedGlazebar.archEnabled);
            if (hBars > 0 || vBars > 0 || archActiveDoor) {
                na_mergeSvgRenderBuckets(
                    renderBucket,
                    na_generateGlazeBarsSvg(
                        glassX, glassY, glassWidth, glassHeight,
                        hBars, vBars, barWidth, frameColor,
                        { openingIndex: panelContext.openingIndex, cellIndex: panelContext.cellIndex, panelIndex: panelContext.panelIndex, sashIndex: 0 },
                        removedGlazebars,
                        advancedGlazebar
                    )
                );
            }

            renderBucket.svg += na_generateLeadedGlassSvg(
                glassX, glassY, glassWidth, glassHeight, leadedGlass,
                {
                    hBars: hBars,
                    vBars: vBars,
                    barWidth: barWidth,
                    advancedGlazebar: advancedGlazebar,
                    panelContext: {
                        openingIndex: panelContext.openingIndex,
                        cellIndex: panelContext.cellIndex,
                        panelIndex: panelContext.panelIndex,
                        sashIndex: 0
                    },
                    clickBucket: renderBucket
                }
            );
        }

        // Lower zone: door panel content (inside casement frame)
        const panelInnerX = x + leftStile;
        const panelInnerY = y + baseRailW;
        const panelInnerW = railClearWidth;
        const panelInnerH = doorPanelH;

        if (panelInnerH > 0 && panelInnerW > 0 && doorConfig) {
            renderBucket.svg += na_generateDoorPanelInnerSvg(panelInnerX, panelInnerY, panelInnerW, panelInnerH, doorConfig, frameColor);
        }

        return renderBucket;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Generate Door Panel Inner SVG
    // ------------------------------------------------------------
    // Draws the panel grid content (margin, cells, recesses, trim) inside
    // the lower zone of a door casement.
    function na_generateDoorPanelInnerSvg(x, y, width, height, config, frameColor) {
        let panelSvg = '';
        const margin = config.door_panel_margin_mm || 30;
        const columns = Math.max(1, Math.min(4, config.door_panel_columns || 2));
        const rows = Math.max(1, Math.min(3, config.door_panel_rows || 1));
        const railWidth = config.door_panel_rail_width_mm || 30;
        const stileWidth = config.door_panel_stile_width_mm || 30;
        const trimWidth = config.door_panel_trim_width_mm || 5;

        panelSvg += na_svgRect(x, y, width, height, frameColor, '#000', 0.5);

        const gridX = x + margin;
        const gridY = y + margin;
        const gridWidth = width - (2 * margin);
        const gridHeight = height - (2 * margin);

        if (gridWidth <= 0 || gridHeight <= 0) return panelSvg;

        const totalStileWidth = Math.max(0, columns - 1) * stileWidth;
        const totalRailHeight = Math.max(0, rows - 1) * railWidth;
        const cellAreaWidth = gridWidth - totalStileWidth;
        const cellAreaHeight = gridHeight - totalRailHeight;
        const cellWidth = cellAreaWidth / columns;
        const cellHeight = cellAreaHeight / rows;

        if (cellWidth <= 0 || cellHeight <= 0) return panelSvg;

        for (let row = 0; row < rows; row++) {
            const cellY = gridY + (row * (cellHeight + railWidth));
            for (let col = 0; col < columns; col++) {
                const cellX = gridX + (col * (cellWidth + stileWidth));
                const recessInset = trimWidth;
                const recessX = cellX + recessInset;
                const recessY = cellY + recessInset;
                const recessW = cellWidth - (2 * recessInset);
                const recessH = cellHeight - (2 * recessInset);

                if (recessW > 0 && recessH > 0) {
                    panelSvg += na_svgRect(recessX, recessY, recessW, recessH, 'rgba(0, 0, 0, 0.08)', frameColor, 0.5);
                }

                if (trimWidth > 0) {
                    panelSvg += na_svgRect(cellX, cellY, cellWidth, trimWidth, 'none', frameColor, 0.3);
                    panelSvg += na_svgRect(cellX, cellY + cellHeight - trimWidth, cellWidth, trimWidth, 'none', frameColor, 0.3);
                    panelSvg += na_svgRect(cellX, cellY + trimWidth, trimWidth, cellHeight - (2 * trimWidth), 'none', frameColor, 0.3);
                    panelSvg += na_svgRect(cellX + cellWidth - trimWidth, cellY + trimWidth, trimWidth, cellHeight - (2 * trimWidth), 'none', frameColor, 0.3);
                }
            }
        }

        for (let col = 1; col < columns; col++) {
            const stileX = gridX + (col * cellWidth) + ((col - 1) * stileWidth);
            panelSvg += na_svgRect(stileX, gridY, stileWidth, gridHeight, frameColor, '#000', 0.3);
        }

        for (let row = 1; row < rows; row++) {
            const railY = gridY + (row * cellHeight) + ((row - 1) * railWidth);
            panelSvg += na_svgRect(gridX, railY, gridWidth, railWidth, frameColor, '#000', 0.3);
        }

        return panelSvg;
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Glaze Bars — Geometry & Invisible Hit Rects
// -----------------------------------------------------------------------------

    // FUNCTION | Resolve Leaded Came Preview Stroke Colour From Edge Swatches
    // ------------------------------------------------------------
    function na_resolveLeadedColourId(config) {
        if (config && config.edge_colour_leaded_id) return String(config.edge_colour_leaded_id);
        const legacy = config && config.leaded_colour ? String(config.leaded_colour) : '';
        if (legacy === 'light') return 'MTE107__LineColour__LightGrey__L85';
        if (legacy === 'dark') return 'MTE103__LineColour__DarkGrey__L40';
        return 'MTE104__LineColour__MidGrey__L60';
    }

    function na_leadedColourHex(colourId) {
        const id = (colourId || '').toString();
        const swatches = window.NA_EDGE_COLOUR_SWATCHES;
        if (Array.isArray(swatches)) {
            const hit = swatches.find(function (s) { return s && s.id === id; });
            if (hit && hit.hex) return hit.hex;
        }
        if (id === 'light' || id.indexOf('LightGrey') >= 0) return '#D9D9D9';
        if (id === 'dark' || id.indexOf('DarkGrey') >= 0) return '#666666';
        if (id.indexOf('SoftBlack') >= 0) return '#333333';
        return '#999999';
    }
    // ---------------------------------------------------------------

    // FUNCTION | Compute Final Glaze Bar Centerlines for a Glass Area
    // ------------------------------------------------------------
    // Single source for the FINAL bar positions (spacing -> margin /
    // arch alignment -> uniform h offset -> per-bar offsets) so the bar
    // renderer and the per-cell leaded glass grid can never drift apart.
    // Returns { hPositions, vPositions, effectiveGlassHeight }.
    function na_computeFinalBarPositions(glassX, glassY, glassWidth, glassHeight, hBars, vBars, barWidth, advancedOptions) {
        const math = window.Na__GlazebarMath;
        const adv = advancedOptions || {};
        const marginEnabled = adv.marginEnabled === true;
        const marginOffset  = Math.max(0, Number(adv.marginOffset || 0));
        const archEnabled   = adv.archEnabled === true;
        const archAmount    = Math.max(1, Math.round(adv.archAmount || 1));
        const archHeight    = Math.max(0, Number(adv.archHeight || 0));
        const hOffsetMm     = Number(adv.hOffsetMm || 0);

        const effectiveGlassHeight = (math && math.na_computeEffectiveGlassHeight)
            ? math.na_computeEffectiveGlassHeight(glassHeight, archEnabled, archHeight, glassWidth, archAmount)
            : (archEnabled ? Math.max(0, glassHeight - archHeight) : glassHeight);

        let hPositions = [];
        if (hBars > 0 && effectiveGlassHeight > 0) {
            hPositions = math.na_computeBarPositions(glassY, effectiveGlassHeight, hBars, marginEnabled, marginOffset);
            if (hOffsetMm !== 0) {
                hPositions = hPositions.map(function (y) { return y + hOffsetMm; });
            }
            hPositions = math.na_applyBarOffsets(hPositions, adv.hOffsetsMm);
        }

        let vPositions = [];
        if (vBars > 0) {
            const archAlignVbars = archEnabled && !marginEnabled && (vBars + 1 === archAmount);
            vPositions = archAlignVbars
                ? math.na_computeArchAlignedBarPositions(glassX, glassWidth, vBars, barWidth, archAmount)
                : math.na_computeBarPositions(glassX, glassWidth, vBars, marginEnabled, marginOffset);
            vPositions = math.na_applyBarOffsets(vPositions, adv.vOffsetsMm);
        }

        return {
            hPositions: hPositions,
            vPositions: vPositions,
            effectiveGlassHeight: effectiveGlassHeight
        };
    }
    // ---------------------------------------------------------------

    // FUNCTION | Generate SVG Leaded Glass Overlay for a Glass Area
    // ------------------------------------------------------------
    // Centre-lines: thin strokes. Otherwise: light fill ribbons using width.
    // Lead lines are laid out PER GLAZING CELL (the sub-panes between
    // glaze bars) when cellContext is provided; each cell gets the
    // configured lead line counts and can be toggled off individually
    // (opts.disabledCells keyed by na_getLeadedCellKey). Without
    // cellContext the whole pane is treated as one cell (legacy shape).
    // cellContext = { hBars, vBars, barWidth, advancedGlazebar,
    //                 panelContext, clickBucket }
    function na_generateLeadedGlassSvg(glassX, glassY, glassWidth, glassHeight, leadedOptions, cellContext) {
        const opts = leadedOptions || {};
        if (!opts.enabled) return '';
        const hLeads = Math.max(0, Math.round(Number(opts.hBars || 0)));
        const vLeads = Math.max(0, Math.round(Number(opts.vBars || 0)));
        if (hLeads <= 0 && vLeads <= 0) return '';
        if (glassWidth <= 0 || glassHeight <= 0) return '';

        const math = window.Na__GlazebarMath;
        if (!math || typeof math.na_computeBarPositions !== 'function') return '';

        const context = cellContext || {};
        const glazeHBars = Math.max(0, Math.round(Number(context.hBars || 0)));
        const glazeVBars = Math.max(0, Math.round(Number(context.vBars || 0)));
        const glazeBarWidth = Math.max(0, Number(context.barWidth || 0));
        const panelContext = context.panelContext || null;
        const clickBucket = context.clickBucket || null;
        const disabledCells = opts.disabledCells instanceof Set
            ? opts.disabledCells
            : na_getDisabledLeadedCellSet(opts.disabledCells);

        // Build the cell grid from the FINAL glaze bar centerlines so the
        // lead lines always sit between the bars, offsets included.
        const barLayout = na_computeFinalBarPositions(
            glassX, glassY, glassWidth, glassHeight,
            glazeHBars, glazeVBars, glazeBarWidth, context.advancedGlazebar
        );
        const columnBounds = math.na_computeCellBounds(glassX, glassWidth, barLayout.vPositions, glazeBarWidth);
        const rowBounds = math.na_computeCellBounds(glassY, barLayout.effectiveGlassHeight, barLayout.hPositions, glazeBarWidth);

        let svg = '';
        for (let row = 0; row < rowBounds.length; row++) {
            for (let col = 0; col < columnBounds.length; col++) {
                const cellX = columnBounds[col].start;
                const cellW = columnBounds[col].size;
                const cellY = rowBounds[row].start;
                const cellH = rowBounds[row].size;
                if (cellW <= 0 || cellH <= 0) continue;

                const cellDisabled = panelContext
                    ? disabledCells.has(na_getLeadedCellKey(
                        panelContext.openingIndex, panelContext.cellIndex,
                        panelContext.panelIndex, panelContext.sashIndex, col, row))
                    : false;

                if (!cellDisabled) {
                    svg += na_generateLeadedCellLinesSvg(cellX, cellY, cellW, cellH, hLeads, vLeads, opts);
                }

                if (panelContext && clickBucket) {
                    clickBucket.leadedClickTargetsSvg += na_generateLeadedCellClickTargetSvg(
                        cellX, cellY, cellW, cellH, panelContext, col, row
                    );
                }
            }
        }

        return svg;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Generate Lead Lines Within One Glazing Cell
    // ------------------------------------------------------------
    function na_generateLeadedCellLinesSvg(cellX, cellY, cellWidth, cellHeight, hLeads, vLeads, opts) {
        const math = window.Na__GlazebarMath;
        const stroke = na_leadedColourHex(opts.colourId || opts.colour);
        const centreLines = opts.centreLines === true;
        const widthMm = Math.max(1, Number(opts.widthMm || 6));
        let svg = '';

        if (hLeads > 0) {
            const hPositions = math.na_computeBarPositions(cellY, cellHeight, hLeads, false, 0);
            for (let i = 0; i < hLeads; i++) {
                const cy = hPositions[i];
                if (centreLines) {
                    svg += `<line x1="${cellX}" y1="${-cy}" x2="${cellX + cellWidth}" y2="${-cy}" stroke="${stroke}" stroke-width="1" />`;
                } else {
                    svg += na_svgRect(cellX, cy - widthMm / 2, cellWidth, widthMm, stroke, stroke, 0.4);
                }
            }
        }

        if (vLeads > 0) {
            const vPositions = math.na_computeBarPositions(cellX, cellWidth, vLeads, false, 0);
            for (let i = 0; i < vLeads; i++) {
                const cx = vPositions[i];
                if (centreLines) {
                    svg += `<line x1="${cx}" y1="${-cellY}" x2="${cx}" y2="${-(cellY + cellHeight)}" stroke="${stroke}" stroke-width="1" />`;
                } else {
                    svg += na_svgRect(cx - widthMm / 2, cellY, widthMm, cellHeight, stroke, stroke, 0.4);
                }
            }
        }

        return svg;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Generate Leaded Cell Click Target SVG
    // ------------------------------------------------------------
    // Whole-cell invisible hit rect for toggling that cell's leaded
    // glass. Emitted BELOW the glaze bar hit rects and inset by half a
    // hit-zone so bar clicks always win near the boundaries.
    function na_generateLeadedCellClickTargetSvg(cellX, cellY, cellWidth, cellHeight, panelContext, col, row) {
        const inset = 4;
        const targetX = cellX + inset;
        const targetY = cellY + inset;
        const targetWidth = cellWidth - inset * 2;
        const targetHeight = cellHeight - inset * 2;
        if (targetWidth <= 0 || targetHeight <= 0) return '';
        const svgY = -targetY - targetHeight;
        return `<rect class="na-leaded-cell-click-target"
                      data-opening-index="${panelContext.openingIndex}"
                      data-cell-index="${panelContext.cellIndex}"
                      data-panel-index="${panelContext.panelIndex}"
                      data-sash-index="${panelContext.sashIndex}"
                      data-col="${col}"
                      data-row="${row}"
                      x="${targetX}" y="${svgY}"
                      width="${targetWidth}" height="${targetHeight}"
                      fill="rgba(0, 0, 0, 0.001)"
                      stroke="none"
                      style="cursor: pointer; pointer-events: all;"/>`;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Generate SVG Glaze Bars for a Glass Area (No Casement Frame)
    // ------------------------------------------------------------
    // Used for direct-glazed openings where casement has been removed.
    // Draws horizontal and vertical glaze bars within the given glass area.
    function na_generateGlazeBarsSvg(glassX, glassY, glassWidth, glassHeight, hBars, vBars, barWidth, frameColor, panelContext, removedGlazebars, advancedOptions) {
        const renderBucket = na_createSvgRenderBucket();

        if (glassWidth <= 0 || glassHeight <= 0) {
            return renderBucket;
        }

        // Optional advanced behaviours (Margin Glazing + Gothic Arch).
        // Defaults preserve the legacy divide-by-(N+1) layout exactly so
        // unrelated call sites are unaffected.
        const adv = advancedOptions || {};
        const archEnabled   = adv.archEnabled === true;
        const archAmount    = Math.max(1, Math.round(adv.archAmount || 1));
        const archHeight    = Math.max(0, Number(adv.archHeight || 0));

        // Final bar centerlines: spacing -> margin / arch alignment ->
        // uniform h offset -> per-bar offsets. Shared with the leaded
        // glass cell grid via na_computeFinalBarPositions. The SVG
        // generator uses a y-up local context, so positive offsets move
        // horizontal bars upward - matching Ruby's positive-Z-is-up.
        const barLayout = na_computeFinalBarPositions(
            glassX, glassY, glassWidth, glassHeight, hBars, vBars, barWidth, adv
        );
        const effectiveGlassHeight = barLayout.effectiveGlassHeight;

        if (hBars > 0 && effectiveGlassHeight > 0) {
            const hPositions = barLayout.hPositions;
            for (let b = 1; b <= hBars; b++) {
                const barCenterY = hPositions[b - 1];
                const barY = barCenterY - (barWidth / 2);
                const barKey = na_getGlazebarKey(
                    panelContext.openingIndex,
                    panelContext.cellIndex,
                    panelContext.panelIndex,
                    panelContext.sashIndex,
                    'horizontal',
                    b
                );

                if (!removedGlazebars.has(barKey)) {
                    renderBucket.svg += na_svgRect(glassX, barY, glassWidth, barWidth, frameColor, '#000', 0.5);
                }

                renderBucket.clickTargetsSvg += na_generateGlazebarClickTargetSvg(
                    glassX,
                    barY,
                    glassWidth,
                    barWidth,
                    panelContext,
                    'horizontal',
                    b
                );
            }
        }

        if (vBars > 0) {
            // Final positions include arch alignment (one vbar under
            // every interior springing when counts pair up), margin
            // glazing, and the per-bar offsets - see
            // na_computeFinalBarPositions for the ordering.
            const vPositions = barLayout.vPositions;
            // Vertical bars only span the regular (non-arch) zone height,
            // matching the reference image where mullions terminate at the
            // arch springing line.
            const vBarTop    = glassY;
            const vBarHeight = effectiveGlassHeight;
            for (let b = 1; b <= vBars; b++) {
                if (vBarHeight <= 0) break;
                const barCenterX = vPositions[b - 1];
                const barX = barCenterX - (barWidth / 2);
                const barKey = na_getGlazebarKey(
                    panelContext.openingIndex,
                    panelContext.cellIndex,
                    panelContext.panelIndex,
                    panelContext.sashIndex,
                    'vertical',
                    b
                );

                if (!removedGlazebars.has(barKey)) {
                    renderBucket.svg += na_svgRect(barX, vBarTop, barWidth, vBarHeight, frameColor, '#000', 0.5);
                }

                renderBucket.clickTargetsSvg += na_generateGlazebarClickTargetSvg(
                    barX,
                    vBarTop,
                    barWidth,
                    vBarHeight,
                    panelContext,
                    'vertical',
                    b
                );
            }
        }

        if (archEnabled && archHeight > 0 && archAmount >= 1) {
            const archSvg = na_generateGothicArchSvg(
                glassX, glassY + effectiveGlassHeight, glassWidth, archHeight,
                archAmount, barWidth, frameColor, panelContext
            );
            renderBucket.svg += archSvg;
        }

        return renderBucket;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Generate SVG Gothic Arch Tracery for a Glazed Panel
    // ------------------------------------------------------------
    // Draws `archAmount` two-centred lancet arches across the top of the
    // glazed area. Each arch consists of two overlapping arcs that overshoot
    // the apex, producing the decorative crossing pattern visible in the
    // reference images. Geometry is computed by the shared GlazebarMath
    // module so 2D, Ruby 3D, and DXF all stay synchronised.
    //
    // Coordinates:
    //   springingY  -- y of the springing line (top of the regular bar zone)
    //   The arch zone occupies [springingY .. springingY + archHeight].
    //   SVG y grows downward in the local context, but na_svgPath wraps
    //   everything with an outer translate(0, -panel) flip, so within this
    //   function we author paths in the same y-up convention used by the
    //   surrounding SVG generators.
    function na_generateGothicArchSvg(glassX, springingY, glassWidth, archHeight, archAmount, barWidth, frameColor, panelContext) {
        if (glassWidth <= 0 || archHeight <= 0 || archAmount <= 0) return '';

        const math = window.Na__GlazebarMath;
        if (!math || !math.na_computeGothicArcParams) return '';

        // Extend the arch zone outward (halfBar on each side, halfBar on
        // top) so each arch terminates slightly past the inside face of
        // the casement. An SVG clip-path then trims everything back to
        // the glass rectangle, producing clean plumb edges where the
        // arches meet the casement stiles and top rail (instead of the
        // curved tangent that would otherwise be left behind).
        const halfBar       = barWidth / 2;
        const extGlassX     = glassX - halfBar;
        const extGlassWidth = glassWidth + (2 * halfBar);
        const extArchHeight = archHeight + halfBar;
        const extBayWidth   = extGlassWidth / archAmount;

        let polygons = '';
        for (let a = 0; a < archAmount; a += 1) {
            const bayLeftX = extGlassX + (a * extBayWidth);
            const params   = math.na_computeGothicArcParams(extBayWidth, extArchHeight);
            polygons += na_buildGothicArchPath(bayLeftX, springingY, params, barWidth, frameColor, panelContext, a);
        }

        // Glass-area clip rectangle in SVG y-down coords. The top edge
        // sits at the TRUE glass top (the inside face of the casement
        // header), which is springingY + total_zone_height (where
        // total_zone_height = apex + overshoot). The caller's springingY
        // was placed exactly so this lands at glass_top. Earlier we
        // mistakenly clipped at springingY + archHeight (apex height
        // only) which chopped the overshoot ring above the apex.
        const originalBayWidth = glassWidth / archAmount;
        const totalZoneHeight  = (typeof math.na_computeGothicTotalZoneHeight === 'function')
            ? math.na_computeGothicTotalZoneHeight(originalBayWidth, archHeight)
            : archHeight;
        const glassTopMath = springingY + totalZoneHeight;

        const clipId = 'na-glass-clip-' +
            panelContext.openingIndex + '-' +
            panelContext.cellIndex + '-' +
            panelContext.panelIndex + '-' +
            panelContext.sashIndex;

        return (
            '<defs>' +
                '<clipPath id="' + clipId + '">' +
                    '<rect x="' + glassX + '" y="' + (-glassTopMath) +
                    '" width="' + glassWidth + '" height="' + totalZoneHeight + '"/>' +
                '</clipPath>' +
            '</defs>' +
            '<g clip-path="url(#' + clipId + ')">' + polygons + '</g>'
        );
    }
    // ---------------------------------------------------------------

    // HELPER | Build one bay's twin-arc SVG polygons (filled ring segments)
    // ------------------------------------------------------------
    // The arch bars are rendered as TESSELLATED POLYGONS rather than
    // SVG <path> arcs so the chosen frame-material fill renders
    // reliably in every browser/Embedded WebView combo. <path> with
    // M-A-L-A-Z sometimes failed to fill because the implicit winding
    // depends on sweep-flag direction, whereas <polygon> takes a flat
    // point list and the SVG fill rule has unambiguous winding.
    //
    // The bar thickness is baked into the geometry: the polygon walks
    // the OUTER radius (R + barWidth/2) forward through the arc, then
    // back along the INNER radius (R - barWidth/2). The result is a
    // closed ring segment of true bar-width thickness, filled with the
    // frame material and outlined in 0.5px black -- matching how the
    // straight glaze bars render via `na_svgRect`.
    //
    // The tessellation count mirrors the 3D side so all three
    // representations (SVG, Ruby 3D, DXF) stay in lockstep.
    function na_buildGothicArchPath(bayLeftX, springingY, params, barWidth, frameColor, panelContext, bayIndex) {
        const leftCx  = bayLeftX + params.leftCenterX;
        const rightCx = bayLeftX + params.rightCenterX;
        const cy      = springingY;
        const R       = params.radius;
        const halfBar = barWidth / 2;
        const rOut    = R + halfBar;
        const rIn     = Math.max(0.01, R - halfBar);

        const fill    = frameColor || '#000000';
        const stroke  = '#000000';
        const ctxId   = `${panelContext.openingIndex}_${panelContext.cellIndex}_${panelContext.panelIndex}_${panelContext.sashIndex}_arch${bayIndex}`;
        const math    = window.Na__GlazebarMath;
        const segments = (math && typeof math.na_gothicTessellationSegmentCount === 'function')
            ? math.na_gothicTessellationSegmentCount(params.archHeight)
            : 24;

        const leftPts  = na_buildArchRingPolygonPoints(leftCx,  cy, rOut, rIn, params.leftStartAng,  params.leftEndAng,  segments);
        const rightPts = na_buildArchRingPolygonPoints(rightCx, cy, rOut, rIn, params.rightStartAng, params.rightEndAng, segments);

        return `
            <polygon points="${leftPts}"  data-arch-id="${ctxId}_L" fill="${fill}" stroke="${stroke}" stroke-width="0.5"/>
            <polygon points="${rightPts}" data-arch-id="${ctxId}_R" fill="${fill}" stroke="${stroke}" stroke-width="0.5"/>
        `;
    }
    // ---------------------------------------------------------------

    // HELPER | Build A Closed Ring-Segment Polygon Point List
    // ------------------------------------------------------------
    // Walks the outer radius from start_angle to end_angle, then the
    // inner radius back, producing a flat space-separated "x,y x,y ..."
    // list ready for an SVG <polygon> element. Y is negated to convert
    // from math y-up to SVG y-down (same flip used by `na_svgRect`).
    function na_buildArchRingPolygonPoints(cx, cy, rOut, rIn, startAng, endAng, segments) {
        const seg = Math.max(8, Math.round(segments));
        const pts = [];
        for (let i = 0; i <= seg; i += 1) {
            const t = i / seg;
            const ang = startAng + (endAng - startAng) * t;
            const x = cx + rOut * Math.cos(ang);
            const y = cy + rOut * Math.sin(ang);
            pts.push(x + ',' + (-y));
        }
        for (let i = seg; i >= 0; i -= 1) {
            const t = i / seg;
            const ang = startAng + (endAng - startAng) * t;
            const x = cx + rIn * Math.cos(ang);
            const y = cy + rIn * Math.sin(ang);
            pts.push(x + ',' + (-y));
        }
        return pts.join(' ');
    }
    // ---------------------------------------------------------------

    // HELPER | Polar -> Cartesian endpoint (math y-up)
    // ------------------------------------------------------------
    function na_arcEndpoint(cx, cy, radius, angleRad) {
        return {
            x: cx + radius * Math.cos(angleRad),
            y: cy + radius * Math.sin(angleRad)
        };
    }
    // ---------------------------------------------------------------

    // FUNCTION | Generate Glaze Bar Click Target SVG
    // ------------------------------------------------------------
    function na_generateGlazebarClickTargetSvg(x, y, width, height, panelContext, orientation, barIndex) {
        const minHitSize = 16;
        let targetX = x;
        let targetY = y;
        let targetWidth = width;
        let targetHeight = height;

        if (orientation === 'horizontal') {
            const extraHeight = Math.max(0, minHitSize - height);
            targetY -= extraHeight / 2;
            targetHeight += extraHeight;
        } else {
            const extraWidth = Math.max(0, minHitSize - width);
            targetX -= extraWidth / 2;
            targetWidth += extraWidth;
        }

        const svgY = -targetY - targetHeight;
        return `<rect class="na-glazebar-click-target"
                      data-opening-index="${panelContext.openingIndex}"
                      data-cell-index="${panelContext.cellIndex}"
                      data-panel-index="${panelContext.panelIndex}"
                      data-sash-index="${panelContext.sashIndex}"
                      data-orientation="${orientation}"
                      data-bar-index="${barIndex}"
                      x="${targetX}" y="${svgY}"
                      width="${targetWidth}" height="${targetHeight}"
                      fill="rgba(0, 0, 0, 0.001)"
                      stroke="none"
                      style="cursor: pointer; pointer-events: all;"/>`;
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Glaze Bar Key Validation (mirrors raster layout)
// -----------------------------------------------------------------------------

    // FUNCTION | Collect Valid Glaze Bar Keys
    // ------------------------------------------------------------
    function na_collectValidGlazebarKeys(config) {
        const frameThicknesses = na_getEffectiveFrameThicknesses(config);
        const topFrameThickness = frameThicknesses.top;
        const bottomFrameThickness = frameThicknesses.bottom;
        const leftFrameThickness = frameThicknesses.left;
        const rightFrameThickness = frameThicknesses.right;
        const showCasements = config.show_casements !== false;
        const slidingSashWindow = config.sliding_sash_window === true;
        const casementsPerOpening = Math.max(1, Math.min(6, config.casements_per_opening || 1));
        const numMullions = config.mullions || 0;
        const mullionWidth = config.mullion_width_mm || 40;
        const transomCount = Math.max(0, Math.min(3, Math.round(config.transoms || 0)));
        const transomWidth = config.transom_width_mm || 40;
        const transomBottoms = na_getActiveTransomBottoms(config, transomCount);
        const removedTransomSegments = na_getRemovedTransomSegmentSet(config.removed_transom_segments);
        const hBars = config.horizontal_glaze_bars || 0;
        const vBars = config.vertical_glaze_bars || 0;
        const removedCasementSet = na_getRemovedCasementSet(config.removed_casements); // <-- Per-panel removal lookup
        const validKeys = [];

        if (hBars <= 0 && vBars <= 0) {
            return validKeys;
        }

        const numOpenings = numMullions + 1;
        const innerWidth = (config.width_mm || 900) - leftFrameThickness - rightFrameThickness;
        const innerHeight = (config.height_mm || 1200) - topFrameThickness - bottomFrameThickness;
        const totalMullionWidth = numMullions * mullionWidth;
        const availableWidth = innerWidth - totalMullionWidth;
        const openingWidth = availableWidth / numOpenings;

        for (let openingIndex = 0; openingIndex < numOpenings; openingIndex++) {
            const openingX = leftFrameThickness + (openingIndex * (openingWidth + mullionWidth));
            const openingY = bottomFrameThickness;
            const openingLayout = na_getOpeningCellLayout(
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
                    const panelHasCasement = showCasements && !na_isPanelCasementRemoved( // <-- Per-panel casement state
                        removedCasementSet,
                        openingIndex,
                        cellIndex,
                        panelIndex
                    );

                    if (panelHasCasement && slidingSashWindow) {
                        na_collectPanelGlazebarKeys(validKeys, openingIndex, cellIndex, panelIndex, 1, hBars, vBars);
                        na_collectPanelGlazebarKeys(validKeys, openingIndex, cellIndex, panelIndex, 0, hBars, vBars);
                    } else {
                        na_collectPanelGlazebarKeys(validKeys, openingIndex, cellIndex, panelIndex, 0, hBars, vBars);
                    }
                }
            });
        }

        return validKeys;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Collect Panel Glaze Bar Keys
    // ------------------------------------------------------------
    function na_collectPanelGlazebarKeys(validKeys, openingIndex, cellIndex, panelIndex, sashIndex, hBars, vBars) {
        for (let barIndex = 1; barIndex <= hBars; barIndex++) {
            validKeys.push(na_getGlazebarKey(openingIndex, cellIndex, panelIndex, sashIndex, 'horizontal', barIndex));
        }

        for (let barIndex = 1; barIndex <= vBars; barIndex++) {
            validKeys.push(na_getGlazebarKey(openingIndex, cellIndex, panelIndex, sashIndex, 'vertical', barIndex));
        }
    }
    // ---------------------------------------------------------------

    // FUNCTION | Collect Valid Leaded Glass Cell Keys
    // ------------------------------------------------------------
    // Mirrors na_collectValidGlazebarKeys but enumerates the glazing
    // cell grid: (vBars + 1) columns x (hBars + 1) rows per panel/sash.
    // Independent of leaded_glass_enabled so disabled-cell choices
    // survive toggling leaded glass off and on.
    function na_collectValidLeadedCellKeys(config) {
        const frameThicknesses = na_getEffectiveFrameThicknesses(config);
        const showCasements = config.show_casements !== false;
        const slidingSashWindow = config.sliding_sash_window === true;
        const casementsPerOpening = Math.max(1, Math.min(6, config.casements_per_opening || 1));
        const numMullions = config.mullions || 0;
        const mullionWidth = config.mullion_width_mm || 40;
        const transomCount = Math.max(0, Math.min(3, Math.round(config.transoms || 0)));
        const transomWidth = config.transom_width_mm || 40;
        const transomBottoms = na_getActiveTransomBottoms(config, transomCount);
        const removedTransomSegments = na_getRemovedTransomSegmentSet(config.removed_transom_segments);
        const hBars = config.horizontal_glaze_bars || 0;
        const vBars = config.vertical_glaze_bars || 0;
        const removedCasementSet = na_getRemovedCasementSet(config.removed_casements);
        const validKeys = [];

        const numOpenings = numMullions + 1;
        const innerWidth = (config.width_mm || 900) - frameThicknesses.left - frameThicknesses.right;
        const innerHeight = (config.height_mm || 1200) - frameThicknesses.top - frameThicknesses.bottom;
        const availableWidth = innerWidth - (numMullions * mullionWidth);
        const openingWidth = availableWidth / numOpenings;

        for (let openingIndex = 0; openingIndex < numOpenings; openingIndex++) {
            const openingX = frameThicknesses.left + (openingIndex * (openingWidth + mullionWidth));
            const openingLayout = na_getOpeningCellLayout(
                openingIndex,
                openingX,
                frameThicknesses.bottom,
                openingWidth,
                innerHeight,
                transomBottoms,
                transomWidth,
                removedTransomSegments
            );

            openingLayout.cells.forEach((cell, cellIndex) => {
                for (let panelIndex = 0; panelIndex < casementsPerOpening; panelIndex++) {
                    const panelHasCasement = showCasements && !na_isPanelCasementRemoved(
                        removedCasementSet,
                        openingIndex,
                        cellIndex,
                        panelIndex
                    );
                    const sashIndices = (panelHasCasement && slidingSashWindow) ? [0, 1] : [0];
                    sashIndices.forEach(sashIndex => {
                        for (let row = 0; row <= hBars; row++) {
                            for (let col = 0; col <= vBars; col++) {
                                validKeys.push(na_getLeadedCellKey(openingIndex, cellIndex, panelIndex, sashIndex, col, row));
                            }
                        }
                    });
                }
            });
        }

        return validKeys;
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Primitive SVG — Rect Shell & Dimensions
// -----------------------------------------------------------------------------

    // FUNCTION | Generate SVG Rectangle
    // ------------------------------------------------------------
    // @param {number} x - X coordinate (bottom-left origin)
    // @param {number} y - Y coordinate (bottom-left origin)
    // @param {number} w - Width
    // @param {number} h - Height
    // @param {string} fill - Fill color
    // @param {string} stroke - Stroke color
    // @param {number} strokeWidth - Stroke width
    // @returns {string} SVG rect element
    function na_svgRect(x, y, w, h, fill, stroke, strokeWidth) {
        // Flip Y coordinate for SVG (origin at bottom-left visually)
        const svgY = -y - h;
        return `<rect x="${x}" y="${svgY}" width="${w}" height="${h}" 
                      fill="${fill}" stroke="${stroke}" stroke-width="${strokeWidth}"/>`;
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Generate Dimension Annotations
    // ------------------------------------------------------------
    // @param {number} width - Window width
    // @param {number} height - Window height
    // @returns {string} SVG dimension lines and text
    function na_svgDimensions(width, height) {
        let svg = '';
        
        // Responsive font size scales with window dimensions
        const fontSize = Math.min(height) * 0.04;
        const lineWidth = 2;
        const tickSize = 15;
        const dimOffset = 100;
        const textOffset = fontSize * 0.85;
        
        // Width dimension (below window)
        svg += `<line x1="0" y1="${dimOffset}" x2="${width}" y2="${dimOffset}" stroke="#606060" stroke-width="${lineWidth}"/>`;
        svg += `<line x1="0" y1="${dimOffset - tickSize}" x2="0" y2="${dimOffset + tickSize}" stroke="#606060" stroke-width="${lineWidth}"/>`;
        svg += `<line x1="${width}" y1="${dimOffset - tickSize}" x2="${width}" y2="${dimOffset + tickSize}" stroke="#606060" stroke-width="${lineWidth}"/>`;
        svg += `<text x="${width / 2}" y="${dimOffset + textOffset}" text-anchor="middle" fill="#303030" font-size="${fontSize}" font-weight="600">${width}mm</text>`;
        
        // Height dimension (left of window)
        svg += `<line x1="${-dimOffset}" y1="${-height}" x2="${-dimOffset}" y2="0" stroke="#606060" stroke-width="${lineWidth}"/>`;
        svg += `<line x1="${-dimOffset - tickSize}" y1="${-height}" x2="${-dimOffset + tickSize}" y2="${-height}" stroke="#606060" stroke-width="${lineWidth}"/>`;
        svg += `<line x1="${-dimOffset - tickSize}" y1="0" x2="${-dimOffset + tickSize}" y2="0" stroke="#606060" stroke-width="${lineWidth}"/>`;
        svg += `<text x="${-dimOffset - textOffset}" y="${-height / 2}" text-anchor="middle" fill="#303030" font-size="${fontSize}" font-weight="600" transform="rotate(-90, ${-dimOffset - textOffset}, ${-height / 2})">${height}mm</text>`;
        
        return svg;
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Exported Public Surface (return hash)
// -----------------------------------------------------------------------------

    return {
        na_generateWindowSvg: na_generateWindowSvg,
        na_generateSingleCasementSvg: na_generateSingleCasementSvg,
        na_generateSlidingSashPanelSvg: na_generateSlidingSashPanelSvg,
        na_getSashHornElevationData: na_getSashHornElevationData,
        na_buildSashHornLogicalPoints: na_buildSashHornLogicalPoints,
        na_generateGlazeBarsSvg: na_generateGlazeBarsSvg,
        na_generateLeadedGlassSvg: na_generateLeadedGlassSvg,
        na_generateGothicArchSvg: na_generateGothicArchSvg,                 // <-- Exposed for ExtFold/ExtSlide elevation parity
        na_computeFinalBarPositions: na_computeFinalBarPositions,           // <-- Exposed so DXF / door elevations share final bar math
        na_collectValidGlazebarKeys: na_collectValidGlazebarKeys,
        na_collectValidLeadedCellKeys: na_collectValidLeadedCellKeys,       // <-- Exposed for leaded-cell pruning in UiLogic
        na_getLeadedCellKey: na_getLeadedCellKey,                           // <-- Exposed for leaded-cell toggles in UiLogic
        na_getCasementKey: na_getCasementKey,                            // <-- Exposed for cross-module reuse
        na_getRemovedCasementSet: na_getRemovedCasementSet,              // <-- Exposed for DXF JS fallback
        na_isPanelCasementRemoved: na_isPanelCasementRemoved,            // <-- Exposed for DXF JS fallback
        na_getOpeningCellLayout: na_getOpeningCellLayout,                // <-- Exposed for valid-key collectors in UiLogic
        na_getActiveTransomBottoms: na_getActiveTransomBottoms,          // <-- Exposed for valid-key collectors in UiLogic
        na_getRemovedTransomSegmentSet: na_getRemovedTransomSegmentSet,  // <-- Exposed for valid-key collectors in UiLogic
        na_getEffectiveFrameThicknesses: na_getEffectiveFrameThicknesses,// <-- Exposed for valid-key collectors in UiLogic
        na_svgRect: na_svgRect,
        na_svgDimensions: na_svgDimensions,
        na_getMaterialColor: na_getMaterialColor,
        na_resolveLeadedColourId: na_resolveLeadedColourId,
        na_leadedColourHex: na_leadedColourHex
    };

// endregion -------------------------------------------------------------------

})();

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Browser Global Attachment
// -----------------------------------------------------------------------------

// Export to global window object for access by other modules
// ------------------------------------------------------------
window.Na__Viewport__SvgGenerator = Na__Viewport__SvgGenerator;

console.log('[NA_VIEWPORT_SVGGENERATOR] SVG Generator module loaded');

// endregion -------------------------------------------------------------------
