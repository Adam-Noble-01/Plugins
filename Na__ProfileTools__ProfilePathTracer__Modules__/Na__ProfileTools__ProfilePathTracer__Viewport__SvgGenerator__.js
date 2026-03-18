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

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | SVG Helpers
    // -------------------------------------------------------------------------

    function Na__Svg__Polyline(points, className) {
        if (!Array.isArray(points) || points.length < 2) {
            return '';
        }

        const pointsText = points.map(function(point) {
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

    function Na__Svg__Bounds(points) {
        let minX = Number.POSITIVE_INFINITY;
        let maxX = Number.NEGATIVE_INFINITY;
        let minY = Number.POSITIVE_INFINITY;
        let maxY = Number.NEGATIVE_INFINITY;

        points.forEach(function(point) {
            minX = Math.min(minX, Number(point[0]));
            maxX = Math.max(maxX, Number(point[0]));
            minY = Math.min(minY, Number(point[1]));
            maxY = Math.max(maxY, Number(point[1]));
        });

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

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Profile SVG Generation
    // -------------------------------------------------------------------------

    function Na__Svg__GenerateProfile(profileRecord) {
        if (!profileRecord || !profileRecord.profileData || !Array.isArray(profileRecord.profileData.points)) {
            return {
                isValid: false,
                reason: 'Profile data missing points array.',
                viewBox: NA_DEFAULT_VIEWBOX,
                svg: ''
            };
        }

        const points = profileRecord.profileData.points
            .filter(function(point) { return Array.isArray(point) && point.length >= 2; })
            .map(function(point) { return [Number(point[0]), Number(point[1])]; });

        if (points.length < 2 || points.some(function(point) { return Number.isNaN(point[0]) || Number.isNaN(point[1]); })) {
            return {
                isValid: false,
                reason: 'Profile points are invalid.',
                viewBox: NA_DEFAULT_VIEWBOX,
                svg: ''
            };
        }

        const bounds = Na__Svg__Bounds(points);
        const profileLine = Na__Svg__Polyline(points, 'naProfileLine');
        const startPoint = points[0];
        const startPointSvg = '<circle class="naProfileStartPoint" cx="' + startPoint[0] + '" cy="' + (-startPoint[1]) + '" r="2.5" />';

        return {
            isValid: true,
            reason: null,
            viewBox: bounds.viewBox,
            svg: [
                '<g class="naProfilePreviewLayer">',
                Na__Svg__Axes(bounds),
                profileLine,
                startPointSvg,
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
