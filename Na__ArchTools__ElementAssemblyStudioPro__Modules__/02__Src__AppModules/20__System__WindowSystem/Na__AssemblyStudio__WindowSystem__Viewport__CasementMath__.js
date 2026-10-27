/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - CASEMENT MATH (PER-CASEMENT SIZES)
   =============================================================================
   FILE       : Na__AssemblyStudio__WindowSystem__Viewport__CasementMath__.js
   NAMESPACE  : window.Na__CasementMath
   AUTHOR     : Noble Architecture
   PURPOSE    : The single authority for how big each casement's members are.
                Resolves the window-wide stiles, rails and Casement Frame
                Inset, lays any Per Casement Settings override over them, and
                lists the casements a layout holds with the number and name
                the dialog shows. Consumed by the WindowSystem SVG generator
                (2D preview), the JS DXF exporter, the viewport validator and
                the UI logic. Mirrored in Ruby by
                GeometryEngine.na_resolve_panel_casement_sizes (3D) and
                DxfExporter.na_resolve_casement_sizes_dxf (DXF stream).

   WHY THIS EXISTS
   Until V1.8.0 every casement in a window shared one set of stiles and
   rails. Real windows often do not: the centre light of a three-light
   cottage window is commonly a heavier fixed casement that sits proud of
   its neighbours. Per Casement Settings gives any casement its own left and
   right stiles, top and bottom rails and Casement Frame Inset.

   OVERRIDE STORE
   config.casement_overrides is keyed by the same casement key the removal
   set uses, "openingIndex:cellIndex:panelIndex":

       { "1:0:0": { enabled: true, left_stile_mm: 70, right_stile_mm: 70,
                    top_rail_mm: 100, bottom_rail_mm: 90, inset_mm: -20 } }

   An entry only counts while `enabled` is true, so switching a casement off
   puts it back on the window-wide settings without losing its own values.
   A missing or non-numeric field falls back to the window-wide value.
   Overrides apply to casement windows only: a sliding sash key covers two
   sashes, and the door products have no casements.

   PUBLIC API
   - na_getCasementKey(openingIndex, cellIndex, panelIndex)
   - na_supportsCasementOverrides(config)
   - na_resolveGlobalCasementSizes(config)
   - na_applyCasementOverride(globalSizes, overrides, key)
   - na_resolveCasementSizes(config, openingIndex, cellIndex, panelIndex)
   - na_enumerateCasements(config)
       Every casement panel in the layout, numbered in reading order (top
       row first, then left to right) with a name such as
       "Casement 2 (Centre Light)". Removed casements stay in the list,
       flagged `removed`, so the numbers do not shuffle when one is clicked
       off in the preview.

   ============================================================================= */

const Na__CasementMath = (function () {

    // CONSTANT | Fields One Casement Can Take On Its Own
    // ---------------------------------------------------------------
    // Size keys match the stored override keys, so a resolved size object
    // and an override entry can be read with the same names. The UI ranges
    // and labels live in NA_CASEMENT_OVERRIDE_FIELDS in the UI config.
    const NA_OVERRIDE_FIELDS = ['left_stile_mm', 'right_stile_mm', 'top_rail_mm', 'bottom_rail_mm', 'inset_mm'];

    // Casements whose top edges sit within this many millimetres are on the
    // same row when the list is put into reading order.
    const NA_ROW_TOLERANCE_MM = 0.5;
    // ---------------------------------------------------------------

    // FUNCTION | Build Casement Storage Key
    // ---------------------------------------------------------------
    function na_getCasementKey(openingIndex, cellIndex, panelIndex) {
        return openingIndex + ':' + cellIndex + ':' + panelIndex;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Does This Product Take Per-Casement Overrides
    // ---------------------------------------------------------------
    // Casement windows with their casements shown. A sliding sash keys both
    // sashes of a panel with one key, and every door product builds through
    // its own system, so neither reads the store.
    function na_supportsCasementOverrides(config) {
        if (!config) return false;
        if (config.sliding_sash_window === true) return false;
        if (config.double_door_mode === true || config.ext_single_door_mode === true ||
            config.sliding_mode === true || config.multifold_mode === true) return false;
        return config.show_casements !== false;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Resolve the Window-Wide Casement Sizes
    // ---------------------------------------------------------------
    // Same rule as every producer before V1.8.0: one Casement Width for all
    // four members unless Individual Casement Sizes is open, and a Casement
    // Frame Inset of 10mm when the key is missing. Zero is a real inset, so
    // it is never replaced by the default.
    function na_resolveGlobalCasementSizes(config) {
        const source = config || {};
        const casementWidth = Number(source.casement_width_mm || 65);
        const individual = source.casement_sizes_individual === true;

        function na_member(key) {
            return individual ? Number(source[key] || casementWidth) : casementWidth;
        }

        const insetValue = Number(source.casement_inset_mm);
        const hasInset = source.casement_inset_mm !== null &&
                         source.casement_inset_mm !== undefined &&
                         isFinite(insetValue);

        return {
            top_rail_mm    : na_member('casement_top_rail_mm'),
            bottom_rail_mm : na_member('casement_bottom_rail_mm'),
            left_stile_mm  : na_member('casement_left_stile_mm'),
            right_stile_mm : na_member('casement_right_stile_mm'),
            inset_mm       : hasInset ? insetValue : 10,
            overridden     : false
        };
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Return a Switched-On Override Entry, or null
    // ---------------------------------------------------------------
    function na_getEnabledOverride(overrides, key) {
        if (!overrides || typeof overrides !== 'object' || Array.isArray(overrides)) return null;
        const entry = overrides[key];
        if (!entry || typeof entry !== 'object') return null;
        return entry.enabled === true ? entry : null;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Lay One Casement's Override Over the Window-Wide Sizes
    // ---------------------------------------------------------------
    // Rails and stiles cannot go below zero. The inset is signed: negative
    // brings the casement proud of the frame face, exactly as the
    // window-wide Casement Frame Inset does.
    function na_applyCasementOverride(globalSizes, overrides, key) {
        const sizes = Object.assign({}, globalSizes, { overridden: false });
        const entry = na_getEnabledOverride(overrides, key);
        if (!entry) return sizes;

        sizes.overridden = true;
        NA_OVERRIDE_FIELDS.forEach(function (field) {
            const value = entry[field];
            if (typeof value !== 'number' || !isFinite(value)) return;
            sizes[field] = (field === 'inset_mm') ? value : Math.max(0, value);
        });
        return sizes;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Resolve One Casement's Sizes Straight From a Flat Config
    // ---------------------------------------------------------------
    function na_resolveCasementSizes(config, openingIndex, cellIndex, panelIndex) {
        const globalSizes = na_resolveGlobalCasementSizes(config);
        if (!na_supportsCasementOverrides(config)) return globalSizes;
        return na_applyCasementOverride(
            globalSizes,
            config.casement_overrides,
            na_getCasementKey(openingIndex, cellIndex, panelIndex)
        );
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Describe Where a Casement Sits, in Words
    // ---------------------------------------------------------------
    // "Centre Light", "Left Light, Top", "Light 4, Leaf 2". Counts are per
    // opening, because a transom clicked off in one light merges that
    // light's tiers without touching its neighbours.
    function na_describeCasementLocation(openingIndex, openingCount, cellIndex, cellCount, panelIndex, panelCount) {
        const parts = [];
        const lightNames = {
            2: ['Left Light', 'Right Light'],
            3: ['Left Light', 'Centre Light', 'Right Light']
        };
        const tierNames = {
            2: ['Bottom', 'Top'],
            3: ['Bottom', 'Middle', 'Top'],
            4: ['Bottom', 'Lower Middle', 'Upper Middle', 'Top']
        };

        if (lightNames[openingCount]) {
            parts.push(lightNames[openingCount][openingIndex]);
        } else if (openingCount > 3) {
            parts.push('Light ' + (openingIndex + 1));
        }
        if (cellCount > 1) {
            parts.push(tierNames[cellCount] ? tierNames[cellCount][cellIndex] : 'Tier ' + (cellIndex + 1));
        }
        if (panelCount > 1) {
            parts.push('Leaf ' + (panelIndex + 1));
        }
        return parts.join(', ');
    }
    // ---------------------------------------------------------------

    // FUNCTION | List Every Casement Panel the Layout Holds
    // ---------------------------------------------------------------
    // Walks the same layout the preview draws: the shared mullion layout,
    // then each light's transom cells, then the casements across each cell.
    // Uses the SVG generator's layout helpers at call time, the way the UI
    // logic's key collectors do, so the list can never disagree with the
    // panels on screen. Returns [] until those modules are loaded.
    //
    // Each entry: { key, openingIndex, cellIndex, panelIndex, x, y, width,
    //               height, removed, number, name, location, label, sizes }
    // x / y / width / height are the PANEL (outside of the casement), in the
    // preview's millimetre space with y measured up from the bottom.
    function na_enumerateCasements(config) {
        const generator = window.Na__Viewport__SvgGenerator;
        const mullionMath = window.Na__MullionMath;
        if (!config || !generator || !mullionMath ||
            typeof generator.na_getOpeningCellLayout !== 'function') {
            return [];
        }

        const frame = generator.na_getEffectiveFrameThicknesses(config);
        const innerWidth = (config.width_mm || 900) - frame.left - frame.right;
        const innerHeight = (config.height_mm || 1200) - frame.top - frame.bottom;
        const transomCount = Math.max(0, Math.min(3, Math.round(config.transoms || 0)));
        const transomBottoms = generator.na_getActiveTransomBottoms(config, transomCount);
        const removedSegments = generator.na_getRemovedTransomSegmentSet(config.removed_transom_segments);
        const removedCasements = generator.na_getRemovedCasementSet(config.removed_casements);
        const panelCount = Math.max(1, Math.min(6, config.casements_per_opening || 1));
        const mullionLayout = mullionMath.na_resolveMullionLayoutFromConfig(config, frame.left, innerWidth);
        const openingCount = mullionLayout.openings.length;
        const globalSizes = na_resolveGlobalCasementSizes(config);
        const overrides = na_supportsCasementOverrides(config) ? config.casement_overrides : null;

        const casements = [];
        mullionLayout.openings.forEach(function (opening, openingIndex) {
            const cellLayout = generator.na_getOpeningCellLayout(
                openingIndex,
                opening.x,
                frame.bottom,
                opening.width,
                innerHeight,
                transomBottoms,
                config.transom_width_mm || 40,
                removedSegments
            );
            const cellCount = cellLayout.cells.length;

            cellLayout.cells.forEach(function (cell, cellIndex) {
                const panelWidth = cell.width / panelCount;
                for (let panelIndex = 0; panelIndex < panelCount; panelIndex += 1) {
                    const key = na_getCasementKey(openingIndex, cellIndex, panelIndex);
                    casements.push({
                        key          : key,
                        openingIndex : openingIndex,
                        cellIndex    : cellIndex,
                        panelIndex   : panelIndex,
                        x            : cell.x + (panelIndex * panelWidth),
                        y            : cell.y,
                        width        : panelWidth,
                        height       : cell.height,
                        removed      : generator.na_isPanelCasementRemoved(removedCasements, openingIndex, cellIndex, panelIndex),
                        location     : na_describeCasementLocation(openingIndex, openingCount, cellIndex, cellCount, panelIndex, panelCount),
                        sizes        : na_applyCasementOverride(globalSizes, overrides, key)
                    });
                }
            });
        });

        casements.sort(function (a, b) {
            const topDifference = (b.y + b.height) - (a.y + a.height);
            if (Math.abs(topDifference) > NA_ROW_TOLERANCE_MM) return topDifference;
            return a.x - b.x;
        });
        casements.forEach(function (casement, index) {
            casement.number = index + 1;
            casement.name = 'Casement ' + casement.number;
            casement.label = casement.location ? casement.name + ' (' + casement.location + ')' : casement.name;
        });
        return casements;
    }
    // ---------------------------------------------------------------

    return {
        NA_OVERRIDE_FIELDS             : NA_OVERRIDE_FIELDS,
        na_getCasementKey              : na_getCasementKey,
        na_supportsCasementOverrides   : na_supportsCasementOverrides,
        na_resolveGlobalCasementSizes  : na_resolveGlobalCasementSizes,
        na_applyCasementOverride       : na_applyCasementOverride,
        na_resolveCasementSizes        : na_resolveCasementSizes,
        na_describeCasementLocation    : na_describeCasementLocation,
        na_enumerateCasements          : na_enumerateCasements
    };
})();

window.Na__CasementMath = Na__CasementMath;
console.log('[NA_CASEMENT_MATH] Shared per-casement sizing module loaded');

/* =============================================================================
   END OF FILE
   ============================================================================= */
