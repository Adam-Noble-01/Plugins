/* =============================================================================
   NA PROFILE TOOLS - VIEWPORT - SVG GENERATOR
   =============================================================================
   FILE       : Na__ProfileTools__Viewport__SvgGenerator__.js
   NAMESPACE  : window.Na__ProfilePathTracer__Viewport__SvgGenerator
   PURPOSE    : Generate SVG code for the 2D profile preview panel
   ============================================================================= */

(function() {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Constants
    // -------------------------------------------------------------------------

    const NA_DEFAULT_VIEWBOX = '-120 -120 240 240';
    const NA_PREVIEW_MARGIN = 16;
    const NA_AXES_PADDING = 20;
    const NA_POINT_EQUALITY_TOLERANCE = 0.0001;

    // Marker sizes are a fraction of the viewBox span, not an absolute unit count.
    // The SVG scales to fit its box, so this is what keeps the datum X and the
    // vertex handles the same on-screen size for a 20 mm bead and a 500 mm cornice.
    const NA_ORIGIN_MARKER_FRACTION = 0.045;
    const NA_VERTEX_HANDLE_FRACTION = 0.030;

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | SVG Helpers
    // -------------------------------------------------------------------------

    function Na__Svg__IsSamePoint(pointA, pointB) {
        if (!Array.isArray(pointA) || !Array.isArray(pointB)) return false;
        var deltaX = Math.abs(Number(pointA[0]) - Number(pointB[0]));
        var deltaY = Math.abs(Number(pointA[1]) - Number(pointB[1]));
        return deltaX <= NA_POINT_EQUALITY_TOLERANCE && deltaY <= NA_POINT_EQUALITY_TOLERANCE;
    }

    function Na__Svg__NormaliseLoopPoints(points) {
        if (!Array.isArray(points)) return [];

        var normalised = [];
        points.forEach(function(point) {
            if (!Array.isArray(point) || point.length < 2) return;
            var x = Number(point[0]);
            var y = Number(point[1]);
            if (Number.isNaN(x) || Number.isNaN(y)) return;

            var nextPoint = [x, y];
            var previousPoint = normalised.length > 0 ? normalised[normalised.length - 1] : null;
            if (previousPoint && Na__Svg__IsSamePoint(previousPoint, nextPoint)) return;
            normalised.push(nextPoint);
        });

        if (normalised.length > 1 && Na__Svg__IsSamePoint(normalised[0], normalised[normalised.length - 1])) {
            normalised.pop();
        }

        return normalised;
    }

    function Na__Svg__ClosedPolyline(points, className) {
        var loopPoints = Na__Svg__NormaliseLoopPoints(points);
        if (loopPoints.length < 2) return '';

        var closedPoints = loopPoints.slice();
        if (loopPoints.length >= 3) {
            closedPoints.push(loopPoints[0]);
        }

        const pointsText = closedPoints.map(function(point) {
            return point[0] + ',' + (-point[1]);
        }).join(' ');

        return '<polyline class="' + className + '" points="' + pointsText + '" />';
    }

    function Na__Svg__Axes(bounds) {
        const size = Math.max(bounds.halfWidth, bounds.halfHeight) + NA_AXES_PADDING;
        return [
            '<line class="naAxisLine" x1="' + (-size) + '" y1="0" x2="' + size + '" y2="0" />',
            '<line class="naAxisLine" x1="0" y1="' + (-size) + '" x2="0" y2="' + size + '" />'
        ].join('');
    }

    function Na__Svg__Bounds(points, options) {
        let minX = Number.POSITIVE_INFINITY;
        let maxX = Number.NEGATIVE_INFINITY;
        let minY = Number.POSITIVE_INFINITY;
        let maxY = Number.NEGATIVE_INFINITY;
        var includeOrigin = options && options.includeOrigin === true;

        points.forEach(function(point) {
            minX = Math.min(minX, Number(point[0]));
            maxX = Math.max(maxX, Number(point[0]));
            minY = Math.min(minY, Number(point[1]));
            maxY = Math.max(maxY, Number(point[1]));
        });

        if (includeOrigin) {
            minX = Math.min(minX, 0);
            maxX = Math.max(maxX, 0);
            minY = Math.min(minY, 0);
            maxY = Math.max(maxY, 0);
        }

        const centerX = (minX + maxX) / 2;
        const centerY = (minY + maxY) / 2;
        const halfWidth = Math.max(10, (maxX - minX) / 2);
        const halfHeight = Math.max(10, (maxY - minY) / 2);
        const margin = (options && typeof options.margin === 'number') ? options.margin : NA_PREVIEW_MARGIN;
        const viewBoxWidth = (halfWidth + margin) * 2;
        const viewBoxHeight = (halfHeight + margin) * 2;

        return {
            centerX: centerX,
            centerY: centerY,
            halfWidth: halfWidth,
            halfHeight: halfHeight,
            viewBoxWidth: viewBoxWidth,
            viewBoxHeight: viewBoxHeight,
            viewBox: [
                centerX - halfWidth - margin,
                -(centerY + halfHeight + margin),
                viewBoxWidth,
                viewBoxHeight
            ].join(' ')
        };
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Display Transform Pipeline
    // -------------------------------------------------------------------------

    // The mirror/rotate/flip chain is captured as an ordered op list with the
    // mirror axes frozen up front. That lets the profile outline AND the lone
    // datum point run through the exact same transform, so the X marker always
    // lands where the path line will actually sit.
    function Na__Svg__BuildDisplayOps(basePoints, toggleStates, rotationStep, reverseDirection) {
        var flags = toggleStates || {};
        var bounds = Na__Svg__Bounds(basePoints, { includeOrigin: true });
        var ops = [];

        if (flags.flipXCenter === true) ops.push({ kind: 'flipX', axis: bounds.centerY });
        if (flags.flipYCenter === true) ops.push({ kind: 'flipY', axis: bounds.centerX });
        if (flags.flipXWorld === true)  ops.push({ kind: 'flipX', axis: 0 });
        if (flags.flipYWorld === true)  ops.push({ kind: 'flipY', axis: 0 });

        var normalizedStep = Number(rotationStep || 0) % 4;
        if (normalizedStep < 0) normalizedStep += 4;
        if (normalizedStep !== 0) ops.push({ kind: 'rotate', step: normalizedStep });

        if (reverseDirection) ops.push({ kind: 'flipY', axis: 0 });
        ops.push({ kind: 'flipY', axis: 0 });

        return ops;
    }

    function Na__Svg__ApplyDisplayOps(point, ops) {
        var x = Number(point[0]);
        var y = Number(point[1]);

        ops.forEach(function(op) {
            if (op.kind === 'flipX') {
                y = (2 * op.axis) - y;
            } else if (op.kind === 'flipY') {
                x = (2 * op.axis) - x;
            } else if (op.kind === 'rotate') {
                var priorX = x;
                var priorY = y;
                if (op.step === 1)      { x = -priorY; y = priorX; }
                else if (op.step === 2) { x = -priorX; y = -priorY; }
                else                    { x = priorY;  y = -priorX; }
            }
        });

        return [x, y];
    }

    function Na__Svg__ApplyOriginOffset(points, originOffset) {
        if (!originOffset) return points;
        var offsetY = Number(originOffset.y) || 0;
        var offsetZ = Number(originOffset.z) || 0;
        if (offsetY === 0 && offsetZ === 0) return points;
        return points.map(function(point) {
            return [Number(point[0]) - offsetY, Number(point[1]) - offsetZ];
        });
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Profile SVG Generation
    // -------------------------------------------------------------------------

    // Marker sizes key off the rendered viewBox span, margin included — that span
    // is what maps onto the fixed pixel box, so a fraction of it is a fixed
    // on-screen size whether the profile is a 20mm bead or a 500mm cornice.
    function Na__Svg__MarkerScale(bounds) {
        return Math.max(bounds.viewBoxWidth, bounds.viewBoxHeight);
    }

    // Datum marker: always a diagonal X of the same on-screen size, drawn at the
    // active insertion point rather than assuming it sits at (0,0).
    function Na__Svg__OriginMarker(bounds, datumPoint) {
        var arm = Na__Svg__MarkerScale(bounds) * NA_ORIGIN_MARKER_FRACTION;
        var cx = Number(datumPoint[0]);
        var cy = -Number(datumPoint[1]);

        return [
            '<line class="naProfileOriginCross" x1="' + (cx - arm) + '" y1="' + (cy - arm) + '"',
            '                                   x2="' + (cx + arm) + '" y2="' + (cy + arm) + '" />',
            '<line class="naProfileOriginCross" x1="' + (cx - arm) + '" y1="' + (cy + arm) + '"',
            '                                   x2="' + (cx + arm) + '" y2="' + (cy - arm) + '" />'
        ].join(' ');
    }

    function Na__Svg__VertexHandles(bounds, displayPoints) {
        var radius = Na__Svg__MarkerScale(bounds) * NA_VERTEX_HANDLE_FRACTION;

        return displayPoints.map(function(point, index) {
            return [
                '<circle class="naProfileVertexHandle"',
                '        data-na-vertex-index="' + index + '"',
                '        cx="' + Number(point[0]) + '"',
                '        cy="' + (-Number(point[1])) + '"',
                '        r="' + radius + '" />'
            ].join(' ');
        }).join('');
    }

    function Na__Svg__ExtractPointsFromUnifiedSchema(profileRecord) {
        var profileData = (profileRecord || {}).profileData || {};
        if (profileData.type !== 'na_unified_asset') return [];

        var assetData = profileData.assetData || {};
        var profileBlock = assetData.Na__Asset__Profile2D || {};
        var vertices = Array.isArray(profileBlock.Na__Geometry__Vertices) ? profileBlock.Na__Geometry__Vertices : [];
        var faces = Array.isArray(profileBlock.Na__Geometry__Faces) ? profileBlock.Na__Geometry__Faces : [];
        if (vertices.length === 0 || faces.length === 0) return [];

        var vertexMap = {};
        vertices.forEach(function(vertex) {
            if (!vertex || !vertex.VertexId) return;
            vertexMap[String(vertex.VertexId)] = [Number(vertex.PosY_mm), Number(vertex.PosZ_mm)];
        });

        var outerLoop = Array.isArray(faces[0].OuterLoopVertices) ? faces[0].OuterLoopVertices : [];
        if (outerLoop.length < 3) return [];

        return outerLoop.map(function(vertexId) {
            return vertexMap[String(vertexId)] || null;
        }).filter(function(point) {
            return Array.isArray(point) && point.length >= 2;
        });
    }

    function Na__Svg__GenerateProfile(profileRecord, options) {
        if (!profileRecord || !profileRecord.profileData) {
            return {
                isValid: false,
                reason: 'Profile data missing.',
                viewBox: NA_DEFAULT_VIEWBOX,
                svg: ''
            };
        }

        var points = Na__Svg__NormaliseLoopPoints(Na__Svg__ExtractPointsFromUnifiedSchema(profileRecord));

        if (points.length < 2 || points.some(function(point) { return Number.isNaN(point[0]) || Number.isNaN(point[1]); })) {
            return {
                isValid: false,
                reason: 'Unified schema profile points are invalid.',
                viewBox: NA_DEFAULT_VIEWBOX,
                svg: ''
            };
        }

        var toggleStates       = (options && options.toggleStates)     ? options.toggleStates     : {};
        var rotationStep       = (options && options.rotationStep)     ? Number(options.rotationStep) : 0;
        var thumbnailMode      = !!(options && options.thumbnailMode);
        var reverseDirection   = !!(options && options.reverseDirection);
        var originOffset       = (options && options.originOffset)     ? options.originOffset     : null;
        var showVertexHandles  = !!(options && options.showVertexHandles);

        // sourcePoints keep the profile's authored coordinates so a picked handle
        // can be reported back as an absolute datum, independent of the offset
        // already in force.
        var sourcePoints = points.map(function(point) { return [Number(point[0]), Number(point[1])]; });
        var basePoints   = Na__Svg__ApplyOriginOffset(sourcePoints, originOffset);

        var displayOps    = Na__Svg__BuildDisplayOps(basePoints, toggleStates, rotationStep, reverseDirection);
        var displayPoints = basePoints.map(function(point) { return Na__Svg__ApplyDisplayOps(point, displayOps); });
        var datumPoint    = Na__Svg__ApplyDisplayOps([0, 0], displayOps);

        var boundsOptions;
        if (thumbnailMode) {
            var tightBounds = Na__Svg__Bounds(displayPoints, { includeOrigin: false, margin: 0 });
            var propMargin = Math.max(tightBounds.halfWidth, tightBounds.halfHeight) * 0.10;
            boundsOptions = { includeOrigin: false, margin: Math.max(propMargin, 4) };
        } else {
            boundsOptions = { includeOrigin: true };
        }

        const bounds = Na__Svg__Bounds(displayPoints, boundsOptions);
        const profileLine = Na__Svg__ClosedPolyline(displayPoints, 'naProfileLine');

        return {
            isValid: true,
            reason: null,
            viewBox: bounds.viewBox,
            sourcePoints: sourcePoints,
            svg: [
                '<g class="naProfilePreviewLayer">',
                Na__Svg__Axes(bounds),
                // Gallery thumbnails are about shape recognition — a datum marker
                // sized for the working preview would just be noise at card scale.
                thumbnailMode ? '' : Na__Svg__OriginMarker(bounds, datumPoint),
                profileLine,
                showVertexHandles ? Na__Svg__VertexHandles(bounds, displayPoints) : '',
                '</g>'
            ].join('')
        };
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Export
    // -------------------------------------------------------------------------

    window.Na__ProfilePathTracer__Viewport__SvgGenerator = {
        Na__Svg__GenerateProfile: Na__Svg__GenerateProfile
    };

    // endregion ----------------------------------------------------------------
})();
