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
   - Window board outline (dashed, inside the room) when Include Window Board is on
   - Dimension annotations: overall sizes plus mullion and transom set out
     chains (V2.2.0), each value marked up so the preview can edit it
   - Lead Line Margins (V2.2.0): first and last lead lines set in from each pane
   - Arched Header Rail (V2.5.2): the rail is drawn last in its casement, so it
     covers the square ends of the bars and lead that run into it
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
    // @param {string} materialId - Material ID (e.g., 'MAT001__Default')
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

    // FUNCTION | Build Lead Line Storage Key (V2.2.1)
    // ------------------------------------------------------------
    // The line's glazing cell key, then 'h' or 'v', then its number in that
    // cell counting from 1 (bottom up, left to right), as glaze bars count:
    // "opening:cell:panel:sash:col:row:h:2".
    function na_getLeadLineKey(cellKey, axis, number) {
        return `${cellKey}:${axis}:${number}`;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Build Removed Lead Line Set (V2.2.1)
    // ------------------------------------------------------------
    function na_getRemovedLeadLineSet(removedLines) {
        return new Set(Array.isArray(removedLines) ? removedLines.map(key => String(key)) : []);
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
// REGION | Cill Horns (V2.4.0)
// -----------------------------------------------------------------------------

    // FUNCTION | Cill Horn Length Past Each Reveal, in mm
    // ------------------------------------------------------------
    // The horns run past the reveal in front of the wall face, plus however
    // far they are let into the wall. A cill set back behind the wall face
    // with nothing let in has no timber there to run past, so it has no horns.
    //
    // Shared with the door previews and the door DXF. Mirrors
    // Na__GeometryBuilders.na_cill_horn_length_mm on the Ruby side.
    function na_cillHornLengthMm(config) {
        if (!config || config.cill_horns_enabled !== true) return 0;
        const letIn = Math.max(0, Number(config.cill_horn_let_in_mm) || 0);
        const projection = config.cill_depth_mm != null ? Number(config.cill_depth_mm) : 50;
        if (projection + letIn <= 0) return 0;
        const length = config.cill_horn_length_mm != null ? Number(config.cill_horn_length_mm) : 40;
        return length > 0 ? length : 0;
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
        const numMullions = config.mullions || 0;                        // <-- Mullion WIDTH and positions now come from Na__MullionMath below
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
            hBars        : Math.max(0, Math.min(12, Math.round(Number(config.horizontal_leaded_bars || 0)))),
            vBars        : Math.max(0, Math.min(12, Math.round(Number(config.vertical_leaded_bars || 0)))),
            widthMm      : Math.max(2, Number(config.leaded_width_mm || 6)),
            centreLines  : config.leaded_centre_lines_only === true,
            colourId     : na_resolveLeadedColourId(config),
            disabledCells: na_getDisabledLeadedCellSet(config.leaded_disabled_cells),       // <-- Per-cell opt-out toggled from the preview
            // V1.8.0 - Align Lead Lines Across Casements. Casement windows
            // only: a sliding sash and a window with no casements already
            // lay every pane out on its own reference glass.
            globalAlignment: config.leaded_global_alignment === true && !slidingSashWindow && showCasements,
            margins      : na_resolveLeadMargins(config),                    // <-- V2.2.0 Lead Line Margins, null when off
            removedLines : na_getRemovedLeadLineSet(config.removed_lead_lines)   // <-- V2.2.1 Lines clicked off in the preview (windows only)
        };
        const frameMaterialId = config.frame_material_id || 'MAT001__Default';
        const frameColor = na_getMaterialColor(frameMaterialId);
        const showDimensions = config.show_dimensions !== false;
        const hasCill = config.has_cill !== false;
        const removedCasementSet = na_getRemovedCasementSet(config.removed_casements); // <-- Per-panel removal set with legacy support
        const casementMath = window.Na__CasementMath;
        const casementOverrides = (casementMath && casementMath.na_supportsCasementOverrides(config))
            ? (config.casement_overrides || {})                          // <-- Per Casement Settings (V1.8.0), casement windows only
            : null;
        const archedHeader = window.Na__ArchMath ? window.Na__ArchMath.na_settings(config, '') : null;   // <-- V2.5.2 Null unless Arched Header Rail is on

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
        // Signed nudge for the meeting rail away from the 50/50 split.
        // Positive drives the meeting rail UP (shorter top sash, taller
        // bottom sash); negative drives it DOWN. Resolved to 0 when the
        // override toggle is off so legacy configs render unchanged.
        const meetingRailOffset = config.meeting_rail_position_override === true
            ? Number(config.meeting_rail_offset_mm || 0)
            : 0;

        let svg = '';
        let openingClickTargetsSvg = '';
        let transomClickTargetsSvg = '';
        let glazebarClickTargetsSvg = '';
        let leadedCellClickTargetsSvg = '';

        const numOpenings = numMullions + 1;
        const innerWidth = width - leftFrameThickness - rightFrameThickness;
        const innerHeight = height - topFrameThickness - bottomFrameThickness;
        // Mullion positions and the resulting light widths come from the
        // shared resolver so the preview, the DXF stream and the SketchUp
        // solid all read the same numbers off the same offsets.
        const mullionLayout = Na__MullionMath.na_resolveMullionLayoutFromConfig(
            config,
            leftFrameThickness,
            innerWidth
        );

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

        mullionLayout.mullions.forEach(mullion => {
            svg += na_svgRect(mullion.x, bottomFrameThickness, mullion.width, innerHeight, frameColor, '#000', 1);
        });

        for (let i = 0; i < numOpenings; i++) {
            const opening = mullionLayout.openings[i];
            const openingX = opening.x;
            const openingWidth = opening.width;
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
                        meetingRailOffset: meetingRailOffset,
                        casementsPerOpening: casementsPerOpening,
                        casTopRail: casTopRail,
                        casBottomRail: casBottomRail,
                        topSashBottomRail: topSashBottomRail,
                        bottomSashTopRail: bottomSashTopRail,
                        casLeftStile: casLeftStile,
                        casRightStile: casRightStile,
                        casementOverrides: casementOverrides,
                        archedHeader: cellIndex === openingLayout.cells.length - 1 ? archedHeader : null,   // <-- The top casement of each light takes it
                        sashHornOptions: sashHornOptions,
                        frameColor: frameColor,
                        hBars: hBars,
                        vBars: vBars,
                        barWidth: barWidth,
                        advancedGlazebar: advancedGlazebar,
                        leadedGlass: leadedGlass,
                        removedGlazebars: removedGlazebars
                    }
                );
                svg += openingCellRender.svg;
                openingClickTargetsSvg += openingCellRender.casementClickTargetsSvg;
                glazebarClickTargetsSvg += openingCellRender.clickTargetsSvg;
                leadedCellClickTargetsSvg += openingCellRender.leadedClickTargetsSvg;
            });
        }

        // Casement numbers, only while Advanced Casement Controls > Per
        // Casement Settings is open, so each group there can be matched to
        // its casement on screen.
        if (casementOverrides !== null &&
            config.advanced_casement_controls === true &&
            config.casement_individual_controls === true) {
            svg += na_generateCasementNumberBadgesSvg(config);
        }

        if (hasCill && bottomFrameThickness > 0) {
            const cillHeight = config.cill_height_mm || 50;
            const cillHorn = na_cillHornLengthMm(config);                // <-- V2.4.0 Zero unless Cill Horns is on
            svg += na_svgRect(0 - cillHorn, -cillHeight, width + 2 * cillHorn, cillHeight, '#A0908A', '#000', 1);
        }

        if (na_isWindowBoardShown(config)) {
            svg += na_generateWindowBoardSvg(config, width);
        }

        if (showDimensions) {
            svg += na_svgDimensions(width, height, {
                editable : true,                                          // <-- V2.2.0 Click a value to type a new one
                chains   : na_computeDimensionChains(config)              // <-- Mullion and transom set out chains
            });
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
// REGION | Window Board (Elevation Outline)
// -----------------------------------------------------------------------------

    // CONSTANT | Board Thickness Until Ruby Pushes the Nosing Assets
    // ------------------------------------------------------------
    const NA_WINDOW_BOARD_DEFAULT_THICKNESS_MM = 30;

    // FUNCTION | True When the Window Board Is On and This Is a Window
    // ------------------------------------------------------------
    // Ruby builds the board in the window engine only, so the hinged door
    // products (which fall back to this generator behind their own
    // viewport) never draw one.
    function na_isWindowBoardShown(config) {
        return config.window_board_enabled === true &&
               config.double_door_mode !== true &&
               config.ext_single_door_mode !== true &&
               config.sliding_mode !== true &&
               config.multifold_mode !== true;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Resolve a Nosing Type's Board Thickness From the Asset Cache
    // ------------------------------------------------------------
    // Read off the profile itself (top face less underside), the same way
    // Na__WindowBoardBuilder sizes the solid.
    function na_getWindowBoardThickness(type) {
        const cache    = window.NA_WINDOW_BOARD_ASSET_CACHE || {};
        const asset    = cache[String(type || '1')];
        const profile  = asset && asset.Na__Asset__Profile2D;
        const vertices = profile && Array.isArray(profile.Na__Geometry__Vertices) ? profile.Na__Geometry__Vertices : [];
        const heights  = vertices.map(vertex => Number(vertex.PosZ_mm)).filter(Number.isFinite);
        if (heights.length < 2) return NA_WINDOW_BOARD_DEFAULT_THICKNESS_MM;

        const thickness = Math.max(...heights) - Math.min(...heights);
        return thickness > 0 ? thickness : NA_WINDOW_BOARD_DEFAULT_THICKNESS_MM;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Generate the Window Board Outline Under the Frame
    // ------------------------------------------------------------
    // The board is inside the room, so this front view shows it dashed: top
    // face flush with the frame underside, one board thickness deep, and one
    // thickness past each side of the reveal when the nosing is returned.
    function na_generateWindowBoardSvg(config, width) {
        const thickness        = na_getWindowBoardThickness(config.window_board_nosing_type);
        const returnProjection = config.window_board_nosing_returns_enabled === false ? 0 : thickness;
        const boardX           = -returnProjection;
        const boardWidth       = width + (2 * returnProjection);
        return `<rect class="na-window-board-outline" x="${boardX}" y="0" width="${boardWidth}" height="${thickness}"
                      fill="none" stroke="#606060" stroke-width="1.5" stroke-dasharray="10 6"/>`;
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

            // Align Lead Lines Across Casements (V1.8.0): the glass a casement
            // built to the window-wide settings would have in this panel. Every
            // pane lays its HORIZONTAL lead out on it, whatever its own casement
            // does; verticals divide the pane's own glass (V2.1.1).
            const leadReference = (options.leadedGlass && options.leadedGlass.globalAlignment)
                ? {
                    x: panelX + options.casLeftStile,
                    y: cell.y + options.casBottomRail,
                    width: panelWidth - options.casLeftStile - options.casRightStile,
                    height: cell.height - options.casTopRail - options.casBottomRail
                }
                : null;

            if (panelHasCasement) {
                // V1.5.3: the legacy `door_mode` branch that drew a fielded door leaf
                // inside a window casement is gone. Exterior single doors preview
                // through Na__ExtSingleDoor__ElevationGenerator instead.
                if (options.slidingSashWindow) {
                    na_mergeSvgRenderBuckets(
                        renderBucket,
                        na_generateSlidingSashPanelSvg(
                            panelX, cell.y, panelWidth, cell.height,
                            options.casTopRail, options.casBottomRail, options.topSashBottomRail, options.bottomSashTopRail, options.casLeftStile, options.casRightStile,
                            options.frameColor, options.hBars, options.vBars, options.barWidth, options.slidingSashOverlap,
                            options.meetingRailOffset,
                            panelContext, options.removedGlazebars, options.sashHornOptions, options.advancedGlazebar,
                            options.leadedGlass,
                            options.archedHeader
                        )
                    );
                } else {
                    const sizes = na_resolvePanelCasementSizes(options, panelContext);   // <-- Window-wide, or this casement's own (V1.8.0)
                    na_mergeSvgRenderBuckets(
                        renderBucket,
                        na_generateSingleCasementSvg(
                            panelX, cell.y, panelWidth, cell.height,
                            sizes.top_rail_mm, sizes.bottom_rail_mm, sizes.left_stile_mm, sizes.right_stile_mm,
                            options.frameColor, options.hBars, options.vBars, options.barWidth,
                            {
                                openingIndex: panelContext.openingIndex,
                                cellIndex: panelContext.cellIndex,
                                panelIndex: panelContext.panelIndex,
                                sashIndex: 0
                            },
                            options.removedGlazebars,
                            options.advancedGlazebar,
                            options.leadedGlass,
                            leadReference,
                            options.archedHeader
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
                        clickBucket: renderBucket,
                        referenceGlass: leadReference
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

    // HELPER FUNCTION | Resolve One Panel's Rails and Stiles (V1.8.0)
    // ------------------------------------------------------------
    // The window-wide sizes, with this casement's Per Casement Settings laid
    // over them when it has some switched on. options.casementOverrides is
    // null outside casement windows, which keeps the shared sizes.
    function na_resolvePanelCasementSizes(options, panelContext) {
        const globalSizes = {
            top_rail_mm    : options.casTopRail,
            bottom_rail_mm : options.casBottomRail,
            left_stile_mm  : options.casLeftStile,
            right_stile_mm : options.casRightStile
        };
        if (!options.casementOverrides || !window.Na__CasementMath) return globalSizes;
        return window.Na__CasementMath.na_applyCasementOverride(
            globalSizes,
            options.casementOverrides,
            na_getCasementKey(panelContext.openingIndex, panelContext.cellIndex, panelContext.panelIndex)
        );
    }
    // ---------------------------------------------------------------

    // FUNCTION | Generate Casement Number Badges (V1.8.0)
    // ------------------------------------------------------------
    // A numbered disc in the middle of each casement's glass, matching the
    // "Casement N" groups in Per Casement Settings. A casement on its own
    // settings is drawn filled, one on the window-wide settings outlined.
    // pointer-events none, so clicks still reach the casement targets.
    function na_generateCasementNumberBadgesSvg(config) {
        const casementMath = window.Na__CasementMath;
        if (!casementMath) return '';
        const accent = '#4a90d9';
        let svg = '';

        casementMath.na_enumerateCasements(config).forEach(casement => {
            if (casement.removed) return;
            const sizes = casement.sizes;
            const glassWidth = casement.width - sizes.left_stile_mm - sizes.right_stile_mm;
            const glassHeight = casement.height - sizes.top_rail_mm - sizes.bottom_rail_mm;
            if (glassWidth <= 0 || glassHeight <= 0) return;

            const centreX = casement.x + sizes.left_stile_mm + (glassWidth / 2);
            const centreY = casement.y + sizes.bottom_rail_mm + (glassHeight / 2);
            const radius = Math.max(22, Math.min(70, Math.min(glassWidth, glassHeight) * 0.12));
            const fill = sizes.overridden ? accent : '#FFFFFF';
            const ink = sizes.overridden ? '#FFFFFF' : accent;

            svg += `<g class="na-casement-number-badge" pointer-events="none">` +
                   `<circle cx="${centreX}" cy="${-centreY}" r="${radius}" fill="${fill}" stroke="${accent}" stroke-width="${Math.max(2, radius * 0.08)}"/>` +
                   `<text x="${centreX}" y="${-centreY}" text-anchor="middle" dominant-baseline="central" ` +
                   `font-size="${radius * 1.1}" font-weight="700" fill="${ink}">${casement.number}</text>` +
                   `</g>`;
        });

        return svg;
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
    // leadReference (V1.8.0, optional): the glass the horizontal lead lines
    // are laid out on when Align Lead Lines Across Casements is on. Omitted,
    // the lead divides this casement's own glass. Verticals always do.
    // archedHeader (V2.5.2, optional): settings from Na__ArchMath.na_settings
    // when this casement takes the arched header. Omitted, a flat head.
    function na_generateSingleCasementSvg(x, y, width, height, topRail, bottomRail, leftStile, rightStile, frameColor, hBars, vBars, barWidth, panelContext, removedGlazebars, advancedGlazebar, leadedGlass, leadReference, archedHeader) {
        const renderBucket = na_createSvgRenderBucket();

        const glassX = x + leftStile;
        const glassY = y + bottomRail;
        const glassWidth = width - leftStile - rightStile;
        const glassHeight = height - topRail - bottomRail;
        const archMath = window.Na__ArchMath;
        const arch = (archMath && archedHeader) ? archMath.na_resolve(archedHeader, glassX, glassY, glassWidth, glassHeight) : null;
        const stileHeight = arch ? archMath.na_stileHeight(arch, y, height) : height;

        renderBucket.svg += na_svgRect(x, y, leftStile, stileHeight, frameColor, '#000', 0.5);
        renderBucket.svg += na_svgRect(x + width - rightStile, y, rightStile, stileHeight, frameColor, '#000', 0.5);
        renderBucket.svg += na_svgRect(x + leftStile, y, width - leftStile - rightStile, bottomRail, frameColor, '#000', 0.5);
        if (!arch) {
            renderBucket.svg += na_svgRect(x + leftStile, y + height - topRail, width - leftStile - rightStile, topRail, frameColor, '#000', 0.5);
        }

        renderBucket.svg += arch
            ? na_svgPolygon(archMath.na_glassOutline(arch, glassY), 'rgba(135, 206, 235, 0.3)', '#87CEEB', 0.5)
            : na_svgRect(glassX, glassY, glassWidth, glassHeight, 'rgba(135, 206, 235, 0.3)', '#87CEEB', 0.5);

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
                clickBucket: renderBucket,
                referenceGlass: leadReference || null
            }
        );

        if (arch) {
            renderBucket.svg += na_svgPolygon(archMath.na_headOutline(arch, x, x + width, y + height), frameColor, '#000', 0.5);
        }

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

    // FUNCTION | Resolve Meeting Rail Height Within a Sash Cell
    // ------------------------------------------------------------
    // Returns the height of the bottom sash zone measured up from the
    // cell floor - i.e. where the meeting rail sits inside the cell.
    // offsetMm is signed: positive drives the meeting rail UP (shorter
    // top sash), negative drives it DOWN. Clamped so neither sash falls
    // below 10% of the cell height. An offset of 0 returns the exact
    // 50/50 split, so legacy configs are bit-identical.
    // Mirrored by GeometryEngine.na_resolve_meeting_rail_height (3D),
    // DxfExporter.na_resolve_meeting_rail_height (Ruby DXF) and
    // Export__Dxf__.na_resolveMeetingRailHeight (JS DXF).
    function na_resolveMeetingRailHeight(height, offsetMm) {
        const centreSplit = height / 2;
        const offset = Number(offsetMm) || 0;
        if (offset === 0) return centreSplit;
        return Math.max(height * 0.10, Math.min(height * 0.90, centreSplit + offset));
    }
    // ---------------------------------------------------------------

    // FUNCTION | Generate Sliding Sash SVG for One Panel
    // ------------------------------------------------------------
    // Draws top and bottom casements stacked vertically.
    // Bottom sash gets a subtle shading overlay to indicate setback depth.
    function na_generateSlidingSashPanelSvg(x, y, width, height, topRail, bottomRail, topSashBottomRail, bottomSashTopRail, leftStile, rightStile, frameColor, hBars, vBars, barWidth, overlapMm, meetingRailOffsetMm, panelContext, removedGlazebars, sashHornOptions, advancedGlazebar, leadedGlass, archedHeader) {
        const renderBucket = na_createSvgRenderBucket();

        const meetingRailY = na_resolveMeetingRailHeight(height, meetingRailOffsetMm);
        const bottomSashHeight = meetingRailY;                                              // <-- Cell floor up to the meeting rail
        const topSashHeight = height - meetingRailY;                                        // <-- Meeting rail up to the cell head
        const sashOverlap = Math.max(0, Math.min(overlapMm || 0, topSashHeight - 1));       // <-- Bottom sash tucks up into the top sash
        const bottomSashY = y;
        const topSashY = y + meetingRailY;

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
            x, bottomSashY, width, bottomSashHeight + sashOverlap,
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
        renderBucket.svg += na_svgRect(x, bottomSashY, width, bottomSashHeight + sashOverlap, 'rgba(0, 0, 0, 0.1)', 'none', 0);

        // Top sash gets the full advancedGlazebar (margin + arches if enabled).
        na_mergeSvgRenderBuckets(
            renderBucket,
            na_generateSingleCasementSvg(
            x, topSashY, width, topSashHeight,
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
                leadedGlass,
                null,
                archedHeader                                             // <-- The bottom sash's head is the flat meeting rail
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

    // CONSTANT | Lead Line Margin Until One Is Typed
    // ------------------------------------------------------------
    const NA_LEAD_MARGIN_DEFAULT_MM = 50;

    // FUNCTION | Resolve the Lead Line Margins (V2.2.0)
    // ------------------------------------------------------------
    // Lead Line Margins on: { x, y } in mm, how far the first and last
    // vertical (x) and horizontal (y) lead lines sit in from the edges of
    // each pane, the lines between dividing the rest evenly. Off, or absent
    // on a window saved before V2.2.0: null, the even layout. Each direction
    // has its own switch (V2.2.2): one switched off comes back null, so that
    // direction divides evenly; absent (V2.2.0, V2.2.1) means on. Shared by
    // the window, sliding, bifold and hinged door previews. Ruby mirror:
    // LeadedGlassBuilder.na_resolve_leaded_params (:margin_x, :margin_y).
    function na_resolveLeadMargins(config) {
        if (!config || config.leaded_margins_enabled !== true) return null;
        const xOn = config.leaded_margin_x_enabled !== false;
        const yOn = config.leaded_margin_y_enabled !== false;
        if (!xOn && !yOn) return null;
        const x = config.leaded_margin_x_mm == null ? NaN : Number(config.leaded_margin_x_mm);
        const y = config.leaded_margin_y_mm == null ? NaN : Number(config.leaded_margin_y_mm);
        return {
            x: xOn ? (Number.isFinite(x) ? Math.max(0, x) : NA_LEAD_MARGIN_DEFAULT_MM) : null,
            y: yOn ? (Number.isFinite(y) ? Math.max(0, y) : NA_LEAD_MARGIN_DEFAULT_MM) : null
        };
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
    //                 panelContext, clickBucket, referenceGlass }
    //
    // referenceGlass (V1.8.0, optional) = { x, y, width, height }: with
    // Align Lead Lines Across Casements on, the HORIZONTAL lines are laid
    // out on this glass and each real glazing cell shows the ones that land
    // inside it, so they run level through a casement whose own rails
    // differ, or a light with no casement at all. Vertical lines always
    // divide each cell's own width evenly (V2.1.1): a light's verticals
    // never line up with another light's, and a pane with no casement or
    // wider stiles would otherwise get crowded verticals and wide end panes.
    // A pane that IS its reference keeps the per-cell layout, line for line.
    //
    // leadedOptions.margins (V2.2.0, optional) = { x, y } from
    // na_resolveLeadMargins: the first and last lines of each cell sit that
    // far in from its edges, the rest dividing evenly between them. The
    // aligned horizontals take the y margin on the reference glass.
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
        const margins = opts.margins || null;
        const referenceRows = na_computeReferenceLeadRows(
            context.referenceGlass, glassX, glassY, glassWidth, glassHeight,
            glazeHBars, glazeVBars, glazeBarWidth, context.advancedGlazebar, hLeads,
            margins ? margins.y : null, opts.widthMm
        );
        const leadMargin = Math.max(1, Math.max(2, Number(opts.widthMm || 6)) / 2);   // <-- Keeps a line's ribbon off rails and bars
        const removedLines = opts.removedLines instanceof Set ? opts.removedLines : null;   // <-- V2.2.1 Window lines switched off one by one

        let svg = '';
        for (let row = 0; row < rowBounds.length; row++) {
            for (let col = 0; col < columnBounds.length; col++) {
                const cellX = columnBounds[col].start;
                const cellW = columnBounds[col].size;
                const cellY = rowBounds[row].start;
                const cellH = rowBounds[row].size;
                if (cellW <= 0 || cellH <= 0) continue;

                const cellKey = panelContext
                    ? na_getLeadedCellKey(
                        panelContext.openingIndex, panelContext.cellIndex,
                        panelContext.panelIndex, panelContext.sashIndex, col, row)
                    : null;
                const cellDisabled = cellKey ? disabledCells.has(cellKey) : false;

                if (panelContext && clickBucket) {
                    clickBucket.leadedClickTargetsSvg += na_generateLeadedCellClickTargetSvg(
                        cellX, cellY, cellW, cellH, panelContext, col, row
                    );
                }

                if (!cellDisabled) {
                    const positions = na_resolveCellLeadPositions(cellX, cellY, cellW, cellH, hLeads, vLeads, opts,
                        referenceRows ? { h: math.na_filterPositionsInside(referenceRows, cellY, cellH, leadMargin) } : null);   // <-- Verticals stay even in this cell
                    const isRemoved = (removedLines && cellKey)
                        ? (axis, number) => removedLines.has(na_getLeadLineKey(cellKey, axis, number))
                        : null;
                    svg += na_generateLeadedCellLinesSvg(cellX, cellY, cellW, cellH, opts, positions, isRemoved);

                    if (removedLines && cellKey && clickBucket) {                                  // <-- After the cell's own target, so a line wins over its pane
                        clickBucket.leadedClickTargetsSvg += na_generateLeadLineClickTargetsSvg(
                            cellX, cellY, cellW, cellH, positions, cellKey, opts.widthMm
                        );
                    }
                }
            }
        }

        return svg;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Where One Glazing Cell's Lead Lines Run
    // ------------------------------------------------------------
    // linePositions (V1.8.0, optional) = { h: [y...] } already cut from the
    // aligned rows, either axis optional. An axis it does not give is laid
    // out on the cell itself: hLeads + 1 by vLeads + 1 equal panes, as it
    // always was, or inside opts.margins when Lead Line Margins is on
    // (V2.2.0).
    // @returns {Object} { h: [y...], v: [x...] }, each ascending
    function na_resolveCellLeadPositions(cellX, cellY, cellWidth, cellHeight, hLeads, vLeads, opts, linePositions) {
        const math = window.Na__GlazebarMath;
        const widthMm = Math.max(1, Number(opts.widthMm || 6));
        const margins = opts.margins || null;
        return {
            h: (linePositions && linePositions.h)
                ? linePositions.h
                : (hLeads > 0 ? math.na_computeLeadPositions(cellY, cellHeight, hLeads, margins ? margins.y : null, widthMm) : []),
            v: (linePositions && linePositions.v)
                ? linePositions.v
                : (vLeads > 0 ? math.na_computeLeadPositions(cellX, cellWidth, vLeads, margins ? margins.x : null, widthMm) : [])
        };
    }
    // ---------------------------------------------------------------

    // FUNCTION | Generate Lead Lines Within One Glazing Cell
    // ------------------------------------------------------------
    // positions from na_resolveCellLeadPositions. isRemoved (V2.2.1,
    // optional) = (axis 'h' | 'v', number from 1) => true for a line
    // switched off in the preview, which is then not drawn.
    function na_generateLeadedCellLinesSvg(cellX, cellY, cellWidth, cellHeight, opts, positions, isRemoved) {
        const stroke = na_leadedColourHex(opts.colourId || opts.colour);
        const centreLines = opts.centreLines === true;
        const widthMm = Math.max(1, Number(opts.widthMm || 6));
        let svg = '';

        positions.h.forEach(function (cy, index) {
            if (isRemoved && isRemoved('h', index + 1)) return;
            if (centreLines) {
                svg += `<line x1="${cellX}" y1="${-cy}" x2="${cellX + cellWidth}" y2="${-cy}" stroke="${stroke}" stroke-width="1" />`;
            } else {
                svg += na_svgRect(cellX, cy - widthMm / 2, cellWidth, widthMm, stroke, stroke, 0.4);
            }
        });

        positions.v.forEach(function (cx, index) {
            if (isRemoved && isRemoved('v', index + 1)) return;
            if (centreLines) {
                svg += `<line x1="${cx}" y1="${-cellY}" x2="${cx}" y2="${-(cellY + cellHeight)}" stroke="${stroke}" stroke-width="1" />`;
            } else {
                svg += na_svgRect(cx - widthMm / 2, cellY, widthMm, cellHeight, stroke, stroke, 0.4);
            }
        });

        return svg;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Click Targets for One Cell's Lead Lines (V2.2.1)
    // ------------------------------------------------------------
    // One thin hit strip per line, drawn or switched off, so a line clicked
    // off is clicked back on where it was, the way glaze bars work. A strip
    // is as wide as the room either side of its line allows, between the
    // lead width and 14mm, so lines close together in a small pane (a
    // clerestory) stay separate: zoom in to pick one.
    function na_generateLeadLineClickTargetsSvg(cellX, cellY, cellWidth, cellHeight, positions, cellKey, leadWidthMm) {
        const leadWidth = Math.max(1, Number(leadWidthMm) || 6);

        function na_hitSizes(list, start, size) {
            return list.map(function (position, index) {
                const before = index > 0 ? position - list[index - 1] : (position - start) * 2;
                const after = index < list.length - 1 ? list[index + 1] - position : (start + size - position) * 2;
                return Math.max(leadWidth, Math.min(14, before, after));
            });
        }

        function na_target(key, x, y, width, height) {
            return `<rect class="na-lead-line-click-target" data-lead-key="${key}"
                      x="${x}" y="${-y - height}" width="${width}" height="${height}"
                      fill="rgba(0, 0, 0, 0.001)" stroke="none"
                      style="cursor: pointer; pointer-events: all;"/>`;
        }

        let svg = '';
        const hSizes = na_hitSizes(positions.h, cellY, cellHeight);
        positions.h.forEach(function (cy, index) {
            svg += na_target(na_getLeadLineKey(cellKey, 'h', index + 1), cellX, cy - hSizes[index] / 2, cellWidth, hSizes[index]);
        });
        const vSizes = na_hitSizes(positions.v, cellX, cellWidth);
        positions.v.forEach(function (cx, index) {
            svg += na_target(na_getLeadLineKey(cellKey, 'v', index + 1), cx - vSizes[index] / 2, cellY, vSizes[index], cellHeight);
        });
        return svg;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Lay the Aligned Lead Rows Out on a Reference Glass (V1.8.0)
    // ------------------------------------------------------------
    // Returns [y...], every HORIZONTAL lead centreline a pane of
    // `referenceGlass` would carry: its own glaze bar rows, each divided
    // evenly, exactly as the per-cell layout divides a pane. Verticals are
    // not aligned (V2.1.1): every cell divides its own width. The full
    // reference rect is still used, because a Gothic arch's zone, and so the
    // rows beneath it, depends on the glass width. Returns null when there
    // is no reference, or when the pane being drawn is the reference, so a
    // casement on the window-wide settings draws the same lines it always
    // did. Ruby mirror: GeometryEngine na_build_lead_reference_grid +
    // LeadedGlassBuilder na_compute_reference_lead_rows. marginY and
    // leadWidthMm (V2.2.0, optional) set the reference rows' lines inside
    // the Lead Line Margins, exactly as a cell of their own would be.
    function na_computeReferenceLeadRows(referenceGlass, glassX, glassY, glassWidth, glassHeight, glazeHBars, glazeVBars, glazeBarWidth, advancedGlazebar, hLeads, marginY, leadWidthMm) {
        if (!referenceGlass) return null;
        if (!(referenceGlass.width > 0) || !(referenceGlass.height > 0)) return null;

        const tolerance = 0.01;
        if (Math.abs(referenceGlass.x - glassX) < tolerance &&
            Math.abs(referenceGlass.y - glassY) < tolerance &&
            Math.abs(referenceGlass.width - glassWidth) < tolerance &&
            Math.abs(referenceGlass.height - glassHeight) < tolerance) {
            return null;
        }

        const math = window.Na__GlazebarMath;
        const referenceLayout = na_computeFinalBarPositions(
            referenceGlass.x, referenceGlass.y, referenceGlass.width, referenceGlass.height,
            glazeHBars, glazeVBars, glazeBarWidth, advancedGlazebar
        );
        const referenceRows = math.na_computeCellBounds(referenceGlass.y, referenceLayout.effectiveGlassHeight, referenceLayout.hPositions, glazeBarWidth);

        return math.na_computeLeadLinePositions(referenceRows, hLeads, marginY, leadWidthMm);
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
        const mullionLayout = Na__MullionMath.na_resolveMullionLayoutFromConfig(config, leftFrameThickness, innerWidth);

        for (let openingIndex = 0; openingIndex < numOpenings; openingIndex++) {
            const opening = mullionLayout.openings[openingIndex];
            const openingY = bottomFrameThickness;
            const openingLayout = na_getOpeningCellLayout(
                openingIndex,
                opening.x,
                openingY,
                opening.width,
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
        const mullionLayout = Na__MullionMath.na_resolveMullionLayoutFromConfig(config, frameThicknesses.left, innerWidth);

        for (let openingIndex = 0; openingIndex < numOpenings; openingIndex++) {
            const opening = mullionLayout.openings[openingIndex];
            const openingLayout = na_getOpeningCellLayout(
                openingIndex,
                opening.x,
                frameThicknesses.bottom,
                opening.width,
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

    // FUNCTION | Collect Valid Lead Line Keys (V2.2.1)
    // ------------------------------------------------------------
    // Every line number each glazing cell can carry: the configured counts.
    // Aligned rows can leave a cell fewer lines; a key past them just waits
    // until its line is drawn again. Like the cell keys, independent of
    // leaded_glass_enabled, so the choices survive switching lead off and on.
    function na_collectValidLeadLineKeys(config) {
        const hLeads = Math.max(0, Math.min(12, Math.round(Number(config.horizontal_leaded_bars || 0))));
        const vLeads = Math.max(0, Math.min(12, Math.round(Number(config.vertical_leaded_bars || 0))));
        const validKeys = [];
        na_collectValidLeadedCellKeys(config).forEach(cellKey => {
            for (let number = 1; number <= hLeads; number++) validKeys.push(na_getLeadLineKey(cellKey, 'h', number));
            for (let number = 1; number <= vLeads; number++) validKeys.push(na_getLeadLineKey(cellKey, 'v', number));
        });
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
    
    // FUNCTION | Generate SVG Polygon From [x, y] Pairs (V2.5.2)
    // ------------------------------------------------------------
    // y up, as na_svgRect takes it.
    function na_svgPolygon(pairs, fill, stroke, strokeWidth) {
        const points = pairs.map(pair => `${pair[0]},${-pair[1]}`).join(' ');
        return `<polygon points="${points}" fill="${fill}" stroke="${stroke}" stroke-width="${strokeWidth}"/>`;
    }
    // ---------------------------------------------------------------

    // CONSTANTS | Dimension Drawing (Millimetres, the Preview's Own Units)
    // ------------------------------------------------------------
    const NA_DIM_OFFSET_MM        = 100;                                   // <-- Dimension line out from the frame
    const NA_DIM_TICK_MM          = 15;                                    // <-- Half a tick
    const NA_DIM_WITNESS_GAP_MM   = 12;                                    // <-- Witness line gap off the frame
    const NA_DIM_WITNESS_OVER_MM  = 15;                                    // <-- Witness line run past the dimension line
    const NA_DIM_STROKE           = '#606060';
    const NA_DIM_WITNESS_STROKE   = '#a8a8a8';
    const NA_DIM_TEXT_FILL        = '#303030';
    // ---------------------------------------------------------------

    // FUNCTION | Generate Dimension Annotations
    // ------------------------------------------------------------
    // Overall width below the window, overall height to its left and, from
    // V2.2.0, the set out chains: mullion centrelines across the top and
    // transom centrelines up the right, each segment its own value.
    // @param {number} width   - Window width
    // @param {number} height  - Window height
    // @param {Object} options - Optional (V2.2.0):
    //        {boolean} editable - Values can be clicked and typed over
    //        {Object}  chains   - na_computeDimensionChains output
    // @returns {string} SVG dimension lines and text
    function na_svgDimensions(width, height, options) {
        const opts = options || {};
        const editable = opts.editable === true;
        const chains = opts.chains || null;
        let svg = '';

        // Responsive font size scales with window dimensions
        const fontSize = Math.min(height) * 0.04;
        const lineWidth = 2;
        const tickSize = 15;
        const dimOffset = NA_DIM_OFFSET_MM;
        const textOffset = fontSize * 0.85;

        // Width dimension (below window)
        svg += `<line x1="0" y1="${dimOffset}" x2="${width}" y2="${dimOffset}" stroke="${NA_DIM_STROKE}" stroke-width="${lineWidth}"/>`;
        svg += `<line x1="0" y1="${dimOffset - tickSize}" x2="0" y2="${dimOffset + tickSize}" stroke="${NA_DIM_STROKE}" stroke-width="${lineWidth}"/>`;
        svg += `<line x1="${width}" y1="${dimOffset - tickSize}" x2="${width}" y2="${dimOffset + tickSize}" stroke="${NA_DIM_STROKE}" stroke-width="${lineWidth}"/>`;
        svg += na_svgDimensionValue(width / 2, dimOffset + textOffset, `${na_formatDimensionValue(width)}mm`, fontSize, false,
            editable ? { kind: 'width', index: 0, value: width, label: 'Overall width' } : null);

        // Height dimension (left of window)
        svg += `<line x1="${-dimOffset}" y1="${-height}" x2="${-dimOffset}" y2="0" stroke="${NA_DIM_STROKE}" stroke-width="${lineWidth}"/>`;
        svg += `<line x1="${-dimOffset - tickSize}" y1="${-height}" x2="${-dimOffset + tickSize}" y2="${-height}" stroke="${NA_DIM_STROKE}" stroke-width="${lineWidth}"/>`;
        svg += `<line x1="${-dimOffset - tickSize}" y1="0" x2="${-dimOffset + tickSize}" y2="0" stroke="${NA_DIM_STROKE}" stroke-width="${lineWidth}"/>`;
        svg += na_svgDimensionValue(-dimOffset - textOffset, -height / 2, `${na_formatDimensionValue(height)}mm`, fontSize, true,
            editable ? { kind: 'height', index: 0, value: height, label: 'Overall height' } : null);

        // Set out chains (V2.2.0)
        if (chains && Array.isArray(chains.mullions) && chains.mullions.length > 2) {
            svg += na_svgChainDimension(chains.mullions, 'horizontal', width, height, fontSize * 0.85, editable ? 'mullion' : null);
        }
        if (chains && Array.isArray(chains.transoms) && chains.transoms.length > 2) {
            svg += na_svgChainDimension(chains.transoms, 'vertical', width, height, fontSize * 0.85, editable ? 'transom' : null);
        }

        return svg;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Draw One Set Out Chain (Mullions Across, Transoms Up)
    // ------------------------------------------------------------
    // stations are window millimetres along the chain (x for 'horizontal',
    // y up for 'vertical'), frame edge to frame edge. Every station gets a
    // witness line from the frame out past the dimension line and a tick on
    // it; every segment between two stations gets its own value. The
    // horizontal chain runs above the window, the vertical one to its right,
    // so neither meets the overall dimensions.
    // @param {Array<number>} stations - Ascending, first and last the frame
    // @param {string}        axis     - 'horizontal' | 'vertical'
    // @param {string|null}   editKind - 'mullion' | 'transom' to make the
    //                                    segment values editable
    function na_svgChainDimension(stations, axis, width, height, fontSize, editKind) {
        const label = editKind === 'transom' ? 'Transom spacing' : 'Mullion spacing';
        let svg = '';

        if (axis === 'horizontal') {
            const lineY = -height - NA_DIM_OFFSET_MM;
            stations.forEach(x => {
                svg += `<line class="na-dim-witness" x1="${x}" y1="${-height - NA_DIM_WITNESS_GAP_MM}" x2="${x}" y2="${lineY - NA_DIM_WITNESS_OVER_MM}" stroke="${NA_DIM_WITNESS_STROKE}" stroke-width="1"/>`;
                svg += `<line x1="${x}" y1="${lineY - NA_DIM_TICK_MM}" x2="${x}" y2="${lineY + NA_DIM_TICK_MM}" stroke="${NA_DIM_STROKE}" stroke-width="2"/>`;
            });
            svg += `<line x1="${stations[0]}" y1="${lineY}" x2="${stations[stations.length - 1]}" y2="${lineY}" stroke="${NA_DIM_STROKE}" stroke-width="2"/>`;
            for (let index = 0; index < stations.length - 1; index++) {
                const length = stations[index + 1] - stations[index];
                svg += na_svgDimensionValue((stations[index] + stations[index + 1]) / 2, lineY - fontSize * 0.3,
                    na_formatDimensionValue(length), fontSize, false,
                    editKind ? { kind: editKind, index: index, value: length, label: label + ' ' + (index + 1) } : null);
            }
            return svg;
        }

        const lineX = width + NA_DIM_OFFSET_MM;
        stations.forEach(station => {
            svg += `<line class="na-dim-witness" x1="${width + NA_DIM_WITNESS_GAP_MM}" y1="${-station}" x2="${lineX + NA_DIM_WITNESS_OVER_MM}" y2="${-station}" stroke="${NA_DIM_WITNESS_STROKE}" stroke-width="1"/>`;
            svg += `<line x1="${lineX - NA_DIM_TICK_MM}" y1="${-station}" x2="${lineX + NA_DIM_TICK_MM}" y2="${-station}" stroke="${NA_DIM_STROKE}" stroke-width="2"/>`;
        });
        svg += `<line x1="${lineX}" y1="${-stations[0]}" x2="${lineX}" y2="${-stations[stations.length - 1]}" stroke="${NA_DIM_STROKE}" stroke-width="2"/>`;
        for (let index = 0; index < stations.length - 1; index++) {
            const length = stations[index + 1] - stations[index];
            svg += na_svgDimensionValue(lineX - fontSize * 0.3, -(stations[index] + stations[index + 1]) / 2,
                na_formatDimensionValue(length), fontSize, true,
                editKind ? { kind: editKind, index: index, value: length, label: label + ' ' + (index + 1) } : null);
        }
        return svg;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | One Dimension Value, Optionally Click To Edit
    // ------------------------------------------------------------
    // (x, y) is the text anchor: middle of the baseline. rotate turns it to
    // read up the page. An editable value (V2.2.0) is wrapped in
    // <g class="na-dim-edit"> carrying what it measures (kind, index) and
    // its exact number, which is all Na__Viewport__Controls needs to open
    // its edit box over it; a clear hit rect behind the text makes the
    // whole label easy to click.
    // @param {Object|null} edit - { kind, index, value, label } or null
    function na_svgDimensionValue(x, y, text, fontSize, rotate, edit) {
        const transform = rotate ? ` transform="rotate(-90, ${x}, ${y})"` : '';
        const textSvg = `<text x="${x}" y="${y}" text-anchor="middle" fill="${NA_DIM_TEXT_FILL}" font-size="${fontSize}" font-weight="600"${edit ? '' : transform}>${text}</text>`;
        if (!edit) return textSvg;

        const hitWidth = Math.max(text.length * 0.62, 2.4) * fontSize + fontSize * 0.6;
        const hitHeight = fontSize * 1.4;
        return `<g class="na-dim-edit" data-dim-kind="${edit.kind}" data-dim-index="${edit.index}" data-dim-value="${edit.value}" data-dim-label="${edit.label}"${transform}>` +
               `<title>${edit.label}: click to type a new size</title>` +
               `<rect class="na-dim-hit" x="${x - hitWidth / 2}" y="${y - fontSize * 1.05}" width="${hitWidth}" height="${hitHeight}" fill="rgba(0, 0, 0, 0.001)" stroke="none"/>` +
               textSvg +
               `</g>`;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Dimension Value Text (Whole mm, or One Decimal)
    // ------------------------------------------------------------
    function na_formatDimensionValue(value) {
        const rounded = Math.round(Number(value) * 10) / 10;
        return Number.isFinite(rounded) ? String(rounded) : '';
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Dimension Chains & Typed Dimension Resolution (V2.2.0)
// -----------------------------------------------------------------------------
// The preview's dimensions double as a second way to set the window out:
// click a value, type a size, and the controls it is made of take it. These
// pure helpers say what each chain measures and what a typed size means, so
// the drawing and the edit can never disagree. MainUiLogic applies the
// result through the panel's own controls (na_applyDimensionEdit).

    // FUNCTION | Set Out Stations for the Preview's Chain Dimensions
    // ------------------------------------------------------------
    // Worked out from the config the same way the preview draws it.
    //   mullions : across the window, outer frame edge, each mullion
    //              centreline, outer frame edge (null with no mullions)
    //   transoms : up the window, outer frame bottom, each transom
    //              centreline, outer frame top (null with no transoms)
    // Window millimetres: x from the left of the frame, y up from its bottom.
    // @returns {Object} { width, height, mullions, transoms }
    function na_computeDimensionChains(config) {
        const cfg = config || {};
        const width = cfg.width_mm || 900;
        const height = cfg.height_mm || 1200;
        const frame = na_getEffectiveFrameThicknesses(cfg);
        const innerWidth = width - frame.left - frame.right;

        const mullionLayout = Na__MullionMath.na_resolveMullionLayoutFromConfig(cfg, frame.left, innerWidth);
        const mullions = mullionLayout.mullions.length > 0
            ? [0].concat(mullionLayout.mullions.map(mullion => mullion.x + mullion.width / 2), [width])
            : null;

        const transomCount = Math.max(0, Math.min(3, Math.round(cfg.transoms || 0)));
        const transomWidth = cfg.transom_width_mm || 40;
        const transoms = transomCount > 0
            ? [0].concat(na_getActiveTransomBottoms(cfg, transomCount).map(bottom => frame.bottom + bottom + transomWidth / 2), [height])
            : null;

        return { width: width, height: height, mullions: mullions, transoms: transoms };
    }
    // ---------------------------------------------------------------

    // FUNCTION | Which Station a Typed Chain Segment Moves, and Where
    // ------------------------------------------------------------
    // Segment k runs from station k to station k + 1. A new length moves
    // the station at its far end, so the segment after it takes up the
    // difference; the last segment's far end is the frame, so it moves its
    // near end instead. The frame edges never move: the overall size holds.
    // @returns {Object|null} { station, position }, station 1..n
    function na_solveChainSegmentEdit(stations, segmentIndex, newLength) {
        if (!Array.isArray(stations) || stations.length < 3) return null;
        const lastSegment = stations.length - 2;
        const segment = Math.round(Number(segmentIndex));
        const length = Number(newLength);
        if (!(segment >= 0 && segment <= lastSegment) || !Number.isFinite(length)) return null;
        if (segment < lastSegment) return { station: segment + 1, position: stations[segment] + length };
        return { station: segment, position: stations[segment + 1] - length };
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Round a Resolved Setting (The Panel Fields' 3 dp)
    // ------------------------------------------------------------
    function na_roundSetting(value) {
        return Math.round(Number(value) * 1000) / 1000;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Turn a Typed Dimension Into Config Changes
    // ------------------------------------------------------------
    // kind 'width' | 'height' | 'mullion' | 'transom', index the chain
    // segment, value the new size in mm.
    //   width / height : the Width / Height control.
    //   mullion        : Individual Mullion Offsets, switched on, with every
    //                    mullion's offset written from where it is drawn now
    //                    (so only the one being moved moves) and the moved
    //                    one's from its new centreline. Offsets are measured
    //                    from the equal lights position, as the sliders are.
    //   transom        : the moved transom's stored height, its bottom above
    //                    the inside of the frame (the form the transom
    //                    controls keep internally).
    // The layout's own clamps (narrowest light, transom order) still apply
    // when the result is drawn.
    // @returns {Object} { changes: { key: value } } | { error }
    function na_resolveDimensionEdit(config, kind, index, value) {
        const cfg = config || {};
        const newValue = Number(value);
        if (!Number.isFinite(newValue)) return { error: 'Not a number' };
        if (kind === 'width') return { changes: { width_mm: newValue } };
        if (kind === 'height') return { changes: { height_mm: newValue } };

        const chains = na_computeDimensionChains(cfg);
        const frame = na_getEffectiveFrameThicknesses(cfg);

        if (kind === 'mullion') {
            const move = na_solveChainSegmentEdit(chains.mullions, index, newValue);
            if (!move) return { error: 'That mullion spacing is not on the drawing' };
            const count = chains.mullions.length - 2;
            const mullionWidth = cfg.mullion_width_mm || 40;
            const even = Na__MullionMath.na_computeEvenMullionLayout(frame.left, chains.width - frame.left - frame.right, count, mullionWidth);
            const changes = { mullion_offsets_enabled: true };
            for (let mullion = 1; mullion <= count; mullion++) {
                const key = `mullion_offset_${mullion}_mm`;
                const centre = mullion === move.station ? move.position : chains.mullions[mullion];
                const offset = centre - (mullionWidth / 2) - even.mullions[mullion - 1].x;
                const stored = Number(cfg[key]);
                const keepStored = mullion !== move.station && cfg.mullion_offsets_enabled === true &&
                                   Number.isFinite(stored) && Math.abs(stored - offset) < 0.001;
                changes[key] = keepStored ? stored : na_roundSetting(offset);
            }
            return { changes: changes };
        }

        if (kind === 'transom') {
            const move = na_solveChainSegmentEdit(chains.transoms, index, newValue);
            if (!move) return { error: 'That transom spacing is not on the drawing' };
            const transomWidth = cfg.transom_width_mm || 40;
            const changes = {};
            changes[`transom_${move.station}_y_mm`] = na_roundSetting(move.position - frame.bottom - (transomWidth / 2));
            return { changes: changes };
        }

        return { error: 'That dimension cannot be typed over' };
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
        na_generateWindowBoardSvg: na_generateWindowBoardSvg,             // <-- Exposed for the window board spec
        na_cillHornLengthMm: na_cillHornLengthMm,                         // <-- V2.4.0 Shared with the door previews and door DXF
        na_getWindowBoardThickness: na_getWindowBoardThickness,
        na_generateGlazeBarsSvg: na_generateGlazeBarsSvg,
        na_generateLeadedGlassSvg: na_generateLeadedGlassSvg,
        na_generateGothicArchSvg: na_generateGothicArchSvg,                 // <-- Exposed for ExtFold/ExtSlide elevation parity
        na_computeFinalBarPositions: na_computeFinalBarPositions,           // <-- Exposed so DXF / door elevations share final bar math
        na_collectValidGlazebarKeys: na_collectValidGlazebarKeys,
        na_collectValidLeadedCellKeys: na_collectValidLeadedCellKeys,       // <-- Exposed for leaded-cell pruning in UiLogic
        na_collectValidLeadLineKeys: na_collectValidLeadLineKeys,           // <-- V2.2.1 Exposed for lead line pruning in UiLogic
        na_getLeadedCellKey: na_getLeadedCellKey,                           // <-- Exposed for leaded-cell toggles in UiLogic
        na_getLeadLineKey: na_getLeadLineKey,                               // <-- V2.2.1
        na_getCasementKey: na_getCasementKey,                            // <-- Exposed for cross-module reuse
        na_getRemovedCasementSet: na_getRemovedCasementSet,              // <-- Exposed for DXF JS fallback
        na_isPanelCasementRemoved: na_isPanelCasementRemoved,            // <-- Exposed for DXF JS fallback
        na_getOpeningCellLayout: na_getOpeningCellLayout,                // <-- Exposed for valid-key collectors in UiLogic
        na_getActiveTransomBottoms: na_getActiveTransomBottoms,          // <-- Exposed for valid-key collectors in UiLogic
        na_getRemovedTransomSegmentSet: na_getRemovedTransomSegmentSet,  // <-- Exposed for valid-key collectors in UiLogic
        na_getEffectiveFrameThicknesses: na_getEffectiveFrameThicknesses,// <-- Exposed for valid-key collectors in UiLogic
        na_svgRect: na_svgRect,
        na_svgPolygon: na_svgPolygon,                                    // <-- V2.5.2 Shared with the sliding and bifold previews
        na_svgDimensions: na_svgDimensions,
        na_computeDimensionChains: na_computeDimensionChains,            // <-- V2.2.0 Set out chains, shared with the dimension editor
        na_solveChainSegmentEdit: na_solveChainSegmentEdit,
        na_resolveDimensionEdit: na_resolveDimensionEdit,
        na_getMaterialColor: na_getMaterialColor,
        na_resolveLeadedColourId: na_resolveLeadedColourId,
        na_leadedColourHex: na_leadedColourHex,
        na_resolveLeadMargins: na_resolveLeadMargins                     // <-- V2.2.0 Shared with the door previews
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
