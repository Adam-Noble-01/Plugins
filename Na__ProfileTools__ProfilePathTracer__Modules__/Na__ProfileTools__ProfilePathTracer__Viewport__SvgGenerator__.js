/* =============================================================================
   NA PROFILE TOOLS - PROFILE PATH TRACER - VIEWPORT SVG GENERATOR
   =============================================================================
*/

(function() {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Constants
    // -------------------------------------------------------------------------

    const NA_DEFAULT_VIEWBOX = '-120 -120 240 240';
    const NA_PREVIEW_MARGIN = 16;
    const NA_AXES_PADDING = 20;
    const NA_POINT_EQUALITY_TOLERANCE = 0.0001;

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
        const margin = NA_PREVIEW_MARGIN;

        return {
            centerX: centerX,
            centerY: centerY,
            halfWidth: halfWidth,
            halfHeight: halfHeight,
            viewBox: [
                centerX - halfWidth - margin,
                -(centerY + halfHeight + margin),
                (halfWidth + margin) * 2,
                (halfHeight + margin) * 2
            ].join(' ')
        };
    }

    function Na__Svg__FlipAcrossXAtY(points, axisY) {
        return points.map(function(point) {
            return [Number(point[0]), (2 * Number(axisY)) - Number(point[1])];
        });
    }

    function Na__Svg__FlipAcrossYAtX(points, axisX) {
        return points.map(function(point) {
            return [(2 * Number(axisX)) - Number(point[0]), Number(point[1])];
        });
    }

    function Na__Svg__ApplyMirrorToggles(points, toggleStates) {
        if (!Array.isArray(points) || points.length === 0) return [];
        var mirroredPoints = Na__Svg__NormaliseLoopPoints(points).map(function(point) { return [Number(point[0]), Number(point[1])]; });
        var flags = toggleStates || {};
        var bounds = Na__Svg__Bounds(mirroredPoints, { includeOrigin: true });

        if (flags.flipXCenter === true) {
            mirroredPoints = Na__Svg__FlipAcrossXAtY(mirroredPoints, bounds.centerY);
        }
        if (flags.flipYCenter === true) {
            mirroredPoints = Na__Svg__FlipAcrossYAtX(mirroredPoints, bounds.centerX);
        }
        if (flags.flipXWorld === true) {
            mirroredPoints = Na__Svg__FlipAcrossXAtY(mirroredPoints, 0);
        }
        if (flags.flipYWorld === true) {
            mirroredPoints = Na__Svg__FlipAcrossYAtX(mirroredPoints, 0);
        }

        return mirroredPoints;
    }

    function Na__Svg__ApplyRotationStep(points, rotationStep) {
        if (!Array.isArray(points) || points.length === 0) return [];
        var normalizedStep = Number(rotationStep || 0) % 4;
        if (normalizedStep < 0) normalizedStep += 4;
        if (normalizedStep === 0) {
            return Na__Svg__NormaliseLoopPoints(points).map(function(point) { return [Number(point[0]), Number(point[1])]; });
        }

        return Na__Svg__NormaliseLoopPoints(points).map(function(point) {
            var x = Number(point[0]);
            var y = Number(point[1]);

            if (normalizedStep === 1) {
                return [-y, x];
            }
            if (normalizedStep === 2) {
                return [-x, -y];
            }
            return [y, -x];
        });
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Profile SVG Generation
    // -------------------------------------------------------------------------

    function Na__Svg__OriginMarker(bounds) {
        var markerSize = Math.max(3, Math.min(bounds.halfWidth, bounds.halfHeight) * 0.08);
        return [
            '<line class="naProfileOriginLine" x1="' + (-markerSize) + '" y1="0" x2="' + markerSize + '" y2="0" />',
            '<line class="naProfileOriginLine" x1="0" y1="' + (-markerSize) + '" x2="0" y2="' + markerSize + '" />',
            '<circle class="naProfileOriginPoint" cx="0" cy="0" r="2.2" />'
        ].join('');
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

        var toggleStates = (options && options.toggleStates) ? options.toggleStates : {};
        var rotationStep = (options && options.rotationStep) ? Number(options.rotationStep) : 0;
        points = Na__Svg__ApplyMirrorToggles(points, toggleStates);
        points = Na__Svg__ApplyRotationStep(points, rotationStep);
        points = Na__Svg__FlipAcrossYAtX(points, 0);

        const bounds = Na__Svg__Bounds(points, { includeOrigin: true });
        const profileLine = Na__Svg__ClosedPolyline(points, 'naProfileLine');

        return {
            isValid: true,
            reason: null,
            viewBox: bounds.viewBox,
            svg: [
                '<g class="naProfilePreviewLayer">',
                Na__Svg__Axes(bounds),
                Na__Svg__OriginMarker(bounds),
                profileLine,
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
