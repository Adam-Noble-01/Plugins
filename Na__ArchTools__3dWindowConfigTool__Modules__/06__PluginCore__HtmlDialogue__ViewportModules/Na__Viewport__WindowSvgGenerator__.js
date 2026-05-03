/* =============================================================================
   NA PLUGIN CORE - WINDOW VIEWPORT SVG GENERATOR
   =============================================================================
   
   FILE       : Na__Viewport__WindowSvgGenerator__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : SVG markup generation for the Window Configurator preview
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
    // Looks up a material's hex color from the hardcoded materials array.
    // @param {string} materialId - Material ID (e.g., 'MAT120__GenericWood')
    // @returns {string} Hex color string (e.g., '#D2B48C')
    function na_getMaterialColor(materialId) {
        // Get frame material config from NA_OPTIONS_CONFIG
        const frameMatConfig = window.NA_OPTIONS_CONFIG.find(c => c.id === 'frame_material_id');
        if (!frameMatConfig || !frameMatConfig.materials) {
            return '#D2B48C'; // Fallback to generic wood color
        }
        
        const material = frameMatConfig.materials.find(m => m.id === materialId);
        return material ? material.color : '#D2B48C';
    }
    // ---------------------------------------------------------------

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

    // FUNCTION | Create SVG Render Bucket
    // ------------------------------------------------------------
    function na_createSvgRenderBucket() {
        return {
            svg: '',
            clickTargetsSvg: '',                                         // <-- Glaze bar click rects
            casementClickTargetsSvg: ''                                  // <-- Per-panel casement click rects
        };
    }
    // ---------------------------------------------------------------

    // FUNCTION | Merge SVG Render Buckets
    // ------------------------------------------------------------
    function na_mergeSvgRenderBuckets(targetBucket, sourceBucket) {
        targetBucket.svg += sourceBucket.svg;
        targetBucket.clickTargetsSvg += sourceBucket.clickTargetsSvg;
        targetBucket.casementClickTargetsSvg += (sourceBucket.casementClickTargetsSvg || ''); // <-- Forward casement targets
    }
    // ---------------------------------------------------------------
    
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

        let svg = '';
        let openingClickTargetsSvg = '';
        let transomClickTargetsSvg = '';
        let glazebarClickTargetsSvg = '';

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
                        casLeftStile: casLeftStile,
                        casRightStile: casRightStile,
                        frameColor: frameColor,
                        hBars: hBars,
                        vBars: vBars,
                        barWidth: barWidth,
                        removedGlazebars: removedGlazebars,
                        doorMode: doorMode,
                        doorPanelHeightMm: doorPanelHeightMm,
                        doorConfig: doorMode ? config : null
                    }
                );
                svg += openingCellRender.svg;
                openingClickTargetsSvg += openingCellRender.casementClickTargetsSvg;
                glazebarClickTargetsSvg += openingCellRender.clickTargetsSvg;
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
        svg += glazebarClickTargetsSvg;

        return svg;
    }
    // ---------------------------------------------------------------

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
                            panelContext, options.removedGlazebars
                        )
                    );
                } else if (options.slidingSashWindow) {
                    na_mergeSvgRenderBuckets(
                        renderBucket,
                        na_generateSlidingSashPanelSvg(
                            panelX, cell.y, panelWidth, cell.height,
                            options.casTopRail, options.casBottomRail, options.casLeftStile, options.casRightStile,
                            options.frameColor, options.hBars, options.vBars, options.barWidth, options.slidingSashOverlap,
                            panelContext, options.removedGlazebars
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
                            options.removedGlazebars
                        )
                    );
                }
            } else {
                renderBucket.svg += na_svgRect(panelX, cell.y, panelWidth, cell.height, 'rgba(135, 206, 235, 0.3)', '#87CEEB', 0.5);

                if (options.hBars > 0 || options.vBars > 0) {
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
                            options.removedGlazebars
                        )
                    );
                }

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
    
    // FUNCTION | Generate SVG for a Single Casement with Individual Sizes
    // ------------------------------------------------------------
    function na_generateSingleCasementSvg(x, y, width, height, topRail, bottomRail, leftStile, rightStile, frameColor, hBars, vBars, barWidth, panelContext, removedGlazebars) {
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

        if (hBars > 0 || vBars > 0) {
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
                    removedGlazebars
                )
            );
        }

        return renderBucket;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Generate Sliding Sash SVG for One Panel
    // ------------------------------------------------------------
    // Draws top and bottom casements stacked vertically.
    // Bottom sash gets a subtle shading overlay to indicate setback depth.
    function na_generateSlidingSashPanelSvg(x, y, width, height, topRail, bottomRail, leftStile, rightStile, frameColor, hBars, vBars, barWidth, overlapMm, panelContext, removedGlazebars) {
        const renderBucket = na_createSvgRenderBucket();

        const sashHeight = height / 2;
        const sashOverlap = Math.max(0, Math.min(overlapMm || 0, sashHeight - 1));
        const bottomSashY = y;
        const topSashY = y + sashHeight;

        // Bottom sash extends behind the top sash to represent weathering overlap.
        na_mergeSvgRenderBuckets(
            renderBucket,
            na_generateSingleCasementSvg(
            x, bottomSashY, width, sashHeight + sashOverlap,
            topRail, bottomRail, leftStile, rightStile,
                frameColor, hBars, vBars, barWidth,
                {
                    openingIndex: panelContext.openingIndex,
                    cellIndex: panelContext.cellIndex,
                    panelIndex: panelContext.panelIndex,
                    sashIndex: 1
                },
                removedGlazebars
            )
        );

        // Reduced by 50% from previous 0.2 intensity.
        renderBucket.svg += na_svgRect(x, bottomSashY, width, sashHeight + sashOverlap, 'rgba(0, 0, 0, 0.1)', 'none', 0);

        // Draw top sash last so it visually sits in front.
        na_mergeSvgRenderBuckets(
            renderBucket,
            na_generateSingleCasementSvg(
            x, topSashY, width, sashHeight,
            topRail, bottomRail, leftStile, rightStile,
                frameColor, hBars, vBars, barWidth,
                {
                    openingIndex: panelContext.openingIndex,
                    cellIndex: panelContext.cellIndex,
                    panelIndex: panelContext.panelIndex,
                    sashIndex: 0
                },
                removedGlazebars
            )
        );

        return renderBucket;
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Generate Door Casement SVG
    // ------------------------------------------------------------
    // Draws a full-height casement with stiles, top/bottom/mid rails,
    // glass + glaze bars in the upper zone, and door panel content in the lower zone.
    function na_generateDoorCasementSvg(x, y, width, height, topRail, bottomRail, leftStile, rightStile, frameColor, hBars, vBars, barWidth, doorPanelHeightMm, doorConfig, panelContext, removedGlazebars) {
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

            if (hBars > 0 || vBars > 0) {
                na_mergeSvgRenderBuckets(
                    renderBucket,
                    na_generateGlazeBarsSvg(
                        glassX, glassY, glassWidth, glassHeight,
                        hBars, vBars, barWidth, frameColor,
                        { openingIndex: panelContext.openingIndex, cellIndex: panelContext.cellIndex, panelIndex: panelContext.panelIndex, sashIndex: 0 },
                        removedGlazebars
                    )
                );
            }
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

    // FUNCTION | Generate SVG Glaze Bars for a Glass Area (No Casement Frame)
    // ------------------------------------------------------------
    // Used for direct-glazed openings where casement has been removed.
    // Draws horizontal and vertical glaze bars within the given glass area.
    function na_generateGlazeBarsSvg(glassX, glassY, glassWidth, glassHeight, hBars, vBars, barWidth, frameColor, panelContext, removedGlazebars) {
        const renderBucket = na_createSvgRenderBucket();

        if (glassWidth <= 0 || glassHeight <= 0) {
            return renderBucket;
        }

        if (hBars > 0) {
            const sectionHeight = glassHeight / (hBars + 1);
            for (let b = 1; b <= hBars; b++) {
                const barY = glassY + (sectionHeight * b) - (barWidth / 2);
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
            const sectionWidth = glassWidth / (vBars + 1);
            for (let b = 1; b <= vBars; b++) {
                const barX = glassX + (sectionWidth * b) - (barWidth / 2);
                const barKey = na_getGlazebarKey(
                    panelContext.openingIndex,
                    panelContext.cellIndex,
                    panelContext.panelIndex,
                    panelContext.sashIndex,
                    'vertical',
                    b
                );

                if (!removedGlazebars.has(barKey)) {
                    renderBucket.svg += na_svgRect(barX, glassY, barWidth, glassHeight, frameColor, '#000', 0.5);
                }

                renderBucket.clickTargetsSvg += na_generateGlazebarClickTargetSvg(
                    barX,
                    glassY,
                    barWidth,
                    glassHeight,
                    panelContext,
                    'vertical',
                    b
                );
            }
        }

        return renderBucket;
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
    
    // Public API
    // ------------------------------------------------------------
    return {
        na_generateWindowSvg: na_generateWindowSvg,
        na_generateSingleCasementSvg: na_generateSingleCasementSvg,
        na_generateSlidingSashPanelSvg: na_generateSlidingSashPanelSvg,
        na_generateGlazeBarsSvg: na_generateGlazeBarsSvg,
        na_collectValidGlazebarKeys: na_collectValidGlazebarKeys,
        na_getCasementKey: na_getCasementKey,                            // <-- Exposed for cross-module reuse
        na_getRemovedCasementSet: na_getRemovedCasementSet,              // <-- Exposed for DXF JS fallback
        na_isPanelCasementRemoved: na_isPanelCasementRemoved,            // <-- Exposed for DXF JS fallback
        na_getOpeningCellLayout: na_getOpeningCellLayout,                // <-- Exposed for valid-key collectors in UiLogic
        na_getActiveTransomBottoms: na_getActiveTransomBottoms,          // <-- Exposed for valid-key collectors in UiLogic
        na_getRemovedTransomSegmentSet: na_getRemovedTransomSegmentSet,  // <-- Exposed for valid-key collectors in UiLogic
        na_getEffectiveFrameThicknesses: na_getEffectiveFrameThicknesses,// <-- Exposed for valid-key collectors in UiLogic
        na_svgRect: na_svgRect,
        na_svgDimensions: na_svgDimensions,
        na_getMaterialColor: na_getMaterialColor
    };
    
})();

// endregion ===================================================================

// =============================================================================
// REGION | Global Exports
// =============================================================================

// Export to global window object for access by other modules
// ------------------------------------------------------------
window.Na__Viewport__SvgGenerator = Na__Viewport__SvgGenerator;

console.log('[NA_VIEWPORT_SVGGENERATOR] SVG Generator module loaded');

// endregion ===================================================================

// =============================================================================
// END OF FILE
// =============================================================================
