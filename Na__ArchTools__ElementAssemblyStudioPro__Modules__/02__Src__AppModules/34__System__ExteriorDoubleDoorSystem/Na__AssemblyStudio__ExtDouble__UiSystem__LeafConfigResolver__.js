(function () {
    'use strict';

    var NA_MIN_LEAF_WIDTH_MM = 300;
    var NA_PRESETS = {
        OnePanel: [1, 1],
        TwoVertical: [2, 1],
        TwoHorizontal: [1, 2],
        FourPanel: [2, 2],
        SixPanel: [2, 3]
    };

    function na_number(value, fallback) {
        var number = Number(value);
        return Number.isFinite(number) ? number : fallback;
    }

    function na_boolean(value, fallback) {
        if (value === undefined || value === null) return fallback;
        return value === true || String(value).toLowerCase() === 'true';
    }

    function na_clamp(value, minimum, maximum) {
        return Math.min(maximum, Math.max(minimum, na_number(value, minimum)));
    }

    function na_dimensions(config) {
        var width = Math.max(0, na_number(config.width_mm, 1900));
        var height = Math.max(0, na_number(config.height_mm, 2100));
        var uniform = Math.max(0, na_number(config.frame_thickness_mm, 50));
        var advanced = na_boolean(config.advanced_frame_controls, false);
        function na_edge(key) {
            return advanced ? Math.max(0, na_number(config[key], uniform)) : uniform;
        }
        var left = na_edge('frame_left_thickness_mm');
        var right = na_edge('frame_right_thickness_mm');
        var top = na_edge('frame_top_thickness_mm');
        var bottom = na_edge('frame_bottom_thickness_mm');
        return {
            widthMm: width,
            heightMm: height,
            frameLeftMm: left,
            frameRightMm: right,
            frameTopMm: top,
            frameBottomMm: bottom,
            frameDepthMm: Math.max(1, na_number(config.frame_depth_mm, 70)),
            frameInsetMm: na_number(config.frame_wall_inset_mm, 0),
            innerXMm: left,
            innerZMm: bottom,
            innerWidthMm: Math.max(0, width - left - right),
            innerHeightMm: Math.max(0, height - top - bottom)
        };
    }

    function na_effectiveLeafConfig(config, side) {
        var sidePrefix = 'double_door_' + side + '_';
        var linked = na_boolean(config.double_door_leaf_settings_linked, true);
        var override = na_boolean(config[sidePrefix + 'leaf_override_enabled'], false);
        function na_value(suffix, fallback) {
            var sharedKey = 'double_door_' + suffix;
            var leafKey = sidePrefix + suffix;
            if (!linked && override && config[leafKey] !== undefined) return config[leafKey];
            return config[sharedKey] !== undefined ? config[sharedKey] : fallback;
        }
        var legacyRailMm = na_number(na_value('panel_rail_width_mm', 150), 150);
        return {
            composition: na_value('leaf_composition', 'GlazedOverFielded'),
            outputMode: na_value('panel_output_mode', 'ThreeDimensional'),
            profile: na_value('panel_profile', 'RaisedBevelled'),
            preset: na_value('panel_preset', 'OnePanel'),
            columns: na_clamp(na_value('panel_columns', 1), 1, 6),
            rows: na_clamp(na_value('panel_rows', 1), 1, 6),
            fieldedHeightMm: na_number(na_value('fielded_section_height_mm', 300), 300),
            midRailMm: na_number(na_value('mid_rail_width_mm', 120), 120),
            stileMm: na_number(na_value('panel_stile_width_mm', 95), 95),
            topRailMm: na_number(na_value('panel_top_rail_width_mm', 95), 95),
            bottomRailMm: na_number(na_value('panel_bottom_rail_width_mm', legacyRailMm), legacyRailMm),
            insetMm: na_number(na_value('panel_inset_mm', 25), 25),
            depthMm: na_number(na_value('panel_depth_mm', 12), 12),
            bevelMm: na_number(na_value('panel_bevel_width_mm', 18), 18),
            horizontalBars: na_clamp(na_value('horizontal_glaze_bars', config.horizontal_glaze_bars || 0), 0, 12),
            verticalBars: na_clamp(na_value('vertical_glaze_bars', config.vertical_glaze_bars || 0), 0, 12),
            glazeBarWidthMm: na_clamp(na_value('glaze_bar_width_mm', config.glaze_bar_width_mm || 25), 5, 100),
            glazeBarInsetMm: na_clamp(na_value('glazebar_inset_mm', config.glazebar_inset_mm || 10), 0, 100),
            marginEnabled: na_boolean(na_value('glazebar_margin_enabled', config.glazebar_margin_enabled), false),
            marginOffsetMm: Math.max(0, na_number(
                na_value('glazebar_margin_offset_mm', config.glazebar_margin_offset_mm || 120),
                120
            )),
            horizontalOffsetMm: na_number(
                na_value('glazebar_horizontal_offset_mm', config.glazebar_horizontal_offset_mm || 0),
                0
            )
        };
    }

    function na_signedAngle(side, direction, angle) {
        var hingeSign = side === 'left' ? 1 : -1;
        var directionSign = String(direction).toLowerCase() === 'inward' ? -1 : 1;
        return hingeSign * directionSign * na_clamp(angle, 0, 180);
    }

    function na_panelY(config, dimensions) {
        var thickness = Math.max(1, na_number(config.double_door_leaf_thickness_mm, 50));
        var direction = String(config.double_door_swing_direction || 'Inward').toLowerCase();
        return direction === 'outward'
            ? dimensions.frameInsetMm + dimensions.frameDepthMm - thickness
            : dimensions.frameInsetMm;
    }

    function na_pivotY(config, dimensions, projection) {
        var direction = String(config.double_door_swing_direction || 'Inward').toLowerCase();
        return direction === 'outward'
            ? dimensions.frameInsetMm + dimensions.frameDepthMm + projection
            : dimensions.frameInsetMm - projection;
    }

    function na_leaf(config, dimensions, widths, side) {
        var left = side === 'left';
        var width = left ? widths.left : widths.right;
        var originX = left ? dimensions.innerXMm : dimensions.innerXMm + widths.left;
        var projection = na_clamp(config['double_door_' + side + '_hinge_projection_mm'], 0, 150);
        var angle = na_clamp(config['double_door_' + side + '_opening_angle_deg'], 0, 180);
        var settings = na_effectiveLeafConfig(config, side);
        var leafThickness = Math.max(1, na_number(config.double_door_leaf_thickness_mm, 50));
        settings.glazeBarInsetMm = na_clamp(
            settings.glazeBarInsetMm,
            0,
            Math.max(0, leafThickness / 2 - 1)
        );
        var leaf = {
            index: left ? 1 : 2,
            side: side,
            sideName: left ? 'Left' : 'Right',
            isActive: String(config.double_door_active_leaf || 'Left').toLowerCase() === side,
            originXMm: originX,
            originYMm: na_panelY(config, dimensions),
            originZMm: dimensions.innerZMm,
            widthMm: width,
            heightMm: dimensions.innerHeightMm,
            thicknessMm: leafThickness,
            hingeXMm: left ? dimensions.innerXMm : dimensions.innerXMm + dimensions.innerWidthMm,
            pivotYMm: na_pivotY(config, dimensions, projection),
            hingeProjectionMm: projection,
            openingAngleDeg: angle,
            signedAngleDeg: na_signedAngle(side, config.double_door_swing_direction || 'Inward', angle),
            closedLatchAngleDeg: left ? 0 : 180,
            settings: settings
        };
        leaf.panelLayout = na_panelLayout(leaf);
        return leaf;
    }

    function na_panelLayout(leaf) {
        var settings = leaf.settings;
        var stile = na_clamp(settings.stileMm, 20, leaf.widthMm / 3);
        var topRail = na_clamp(settings.topRailMm, 20, leaf.heightMm / 3);
        var bottomRail = na_clamp(settings.bottomRailMm, 20, leaf.heightMm / 3);
        var midRail = na_clamp(settings.midRailMm, 20, leaf.heightMm / 3);
        var full = {
            xMm: leaf.originXMm + stile,
            zMm: leaf.originZMm + bottomRail,
            widthMm: Math.max(0, leaf.widthMm - 2 * stile),
            heightMm: Math.max(0, leaf.heightMm - topRail - bottomRail)
        };
        var field = null;
        var glazed = null;
        if (settings.composition === 'FullyGlazed') {
            glazed = full;
        } else if (settings.composition === 'FullyFielded') {
            field = full;
        } else {
            var fieldHeight = na_clamp(settings.fieldedHeightMm, 100, Math.max(100, full.heightMm - midRail - 100));
            field = Object.assign({}, full, { heightMm: fieldHeight });
            glazed = {
                xMm: full.xMm,
                zMm: full.zMm + fieldHeight + midRail,
                widthMm: full.widthMm,
                heightMm: Math.max(0, full.heightMm - fieldHeight - midRail)
            };
        }
        var fieldCells = na_fieldCells(field, settings, midRail);
        return {
            stileMm: stile,
            topRailMm: topRail,
            bottomRailMm: bottomRail,
            midRailMm: midRail,
            fieldRegion: field,
            glazedRegion: glazed,
            fieldCells: fieldCells,
            fieldDividers: na_fieldDividers(field, fieldCells)
        };
    }

    function na_fieldCells(region, settings, separatorSource) {
        if (!region || region.widthMm <= 0 || region.heightMm <= 0) return [];
        var grid = settings.preset === 'Custom'
            ? [Math.round(settings.columns), Math.round(settings.rows)]
            : (NA_PRESETS[settings.preset] || [1, 1]);
        var columns = grid[0];
        var rows = grid[1];
        var separator = Math.max(30, separatorSource * 0.55);
        var width = (region.widthMm - separator * (columns - 1)) / columns;
        var height = (region.heightMm - separator * (rows - 1)) / rows;
        if (width < 40 || height < 40) return [];
        var cells = [];
        for (var row = 0; row < rows; row += 1) {
            for (var column = 0; column < columns; column += 1) {
                cells.push({
                    xMm: region.xMm + column * (width + separator),
                    zMm: region.zMm + row * (height + separator),
                    widthMm: width,
                    heightMm: height
                });
            }
        }
        return cells;
    }

    function na_fieldDividers(region, cells) {
        if (!region || cells.length < 2) return [];
        var columnsByX = new Map();
        var rowsByZ = new Map();
        cells.forEach(function (cell) {
            if (!columnsByX.has(cell.xMm)) columnsByX.set(cell.xMm, cell);
            if (!rowsByZ.has(cell.zMm)) rowsByZ.set(cell.zMm, cell);
        });
        var columns = Array.from(columnsByX.values()).sort(function (a, b) { return a.xMm - b.xMm; });
        var rows = Array.from(rowsByZ.values()).sort(function (a, b) { return a.zMm - b.zMm; });
        var dividers = [];
        for (var column = 0; column < columns.length - 1; column += 1) {
            var currentColumn = columns[column];
            var followingColumn = columns[column + 1];
            var gapX = currentColumn.xMm + currentColumn.widthMm;
            var gapWidth = followingColumn.xMm - gapX;
            if (gapWidth > 0) {
                dividers.push({
                    orientation: 'vertical', index: column + 1,
                    xMm: gapX, zMm: region.zMm,
                    widthMm: gapWidth, heightMm: region.heightMm
                });
            }
        }
        for (var row = 0; row < rows.length - 1; row += 1) {
            var currentRow = rows[row];
            var followingRow = rows[row + 1];
            var gapZ = currentRow.zMm + currentRow.heightMm;
            var gapHeight = followingRow.zMm - gapZ;
            if (gapHeight > 0) {
                dividers.push({
                    orientation: 'horizontal', index: row + 1,
                    xMm: region.xMm, zMm: gapZ,
                    widthMm: region.widthMm, heightMm: gapHeight
                });
            }
        }
        return dividers;
    }

    // Resolve the active-leaf width from the EQ/mm hybrid field: 'EQ' (or any
    // non-numeric value) means an equal 50/50 split; a number is the active
    // leaf width in mm, clamped so both leaves keep the 300 mm minimum.
    function na_resolveActiveLeafWidthMm(config, innerWidthMm, minimum, maximum) {
        var raw = config.double_door_active_leaf_width_mm;
        var num = (typeof raw === 'number') ? raw : parseFloat(raw);
        if (!isFinite(num)) return innerWidthMm / 2;
        return na_clamp(num, minimum, maximum);
    }

    function na_resolve(config) {
        config = config || {};
        var dimensions = na_dimensions(config);
        var minimum = Math.min(NA_MIN_LEAF_WIDTH_MM, dimensions.innerWidthMm / 2);
        var maximum = Math.max(minimum, dimensions.innerWidthMm - minimum);
        var activeWidth = na_resolveActiveLeafWidthMm(config, dimensions.innerWidthMm, minimum, maximum);
        var activeSide = String(config.double_door_active_leaf || 'Left').toLowerCase();
        var leftWidth = activeSide === 'right' ? dimensions.innerWidthMm - activeWidth : activeWidth;
        var widths = { left: leftWidth, right: dimensions.innerWidthMm - leftWidth };
        return {
            dimensions: dimensions,
            leaves: [
                na_leaf(config, dimensions, widths, 'left'),
                na_leaf(config, dimensions, widths, 'right')
            ]
        };
    }

    function na_seedLeafOverride(config, side) {
        var result = Object.assign({}, config || {});
        var source = na_effectiveLeafConfig(result, side);
        var prefix = 'double_door_' + side + '_';
        var mapping = {
            leaf_composition: 'composition', panel_output_mode: 'outputMode',
            panel_profile: 'profile', panel_preset: 'preset', panel_columns: 'columns',
            panel_rows: 'rows', fielded_section_height_mm: 'fieldedHeightMm',
            mid_rail_width_mm: 'midRailMm', panel_stile_width_mm: 'stileMm',
            panel_top_rail_width_mm: 'topRailMm',
            panel_bottom_rail_width_mm: 'bottomRailMm',
            panel_inset_mm: 'insetMm',
            panel_depth_mm: 'depthMm', panel_bevel_width_mm: 'bevelMm',
            horizontal_glaze_bars: 'horizontalBars', vertical_glaze_bars: 'verticalBars',
            glaze_bar_width_mm: 'glazeBarWidthMm', glazebar_inset_mm: 'glazeBarInsetMm'
        };
        Object.keys(mapping).forEach(function (suffix) {
            result[prefix + suffix] = source[mapping[suffix]];
        });
        result[prefix + 'leaf_override_enabled'] = true;
        return result;
    }

    function na_validate(config) {
        var resolved = na_resolve(config);
        var errors = [];
        if (resolved.dimensions.innerWidthMm < 2 * NA_MIN_LEAF_WIDTH_MM) {
            errors.push('Clear frame width must accommodate two 300 mm leaves.');
        }
        if (resolved.dimensions.innerHeightMm <= 0) errors.push('Clear frame height must be positive.');
        resolved.leaves.forEach(function (leaf) {
            if (!leaf.panelLayout.fieldCells.length && leaf.settings.composition !== 'FullyGlazed') {
                errors.push(leaf.sideName + ' field layout is too small for the selected settings.');
            }
        });
        return { valid: errors.length === 0, errors: errors, resolved: resolved };
    }

    window.Na__ExtDouble__LeafConfigResolver = Object.freeze({
        na_resolve: na_resolve,
        na_effective_leaf_config: na_effectiveLeafConfig,
        na_seed_leaf_override: na_seedLeafOverride,
        na_validate: na_validate
    });
}());
