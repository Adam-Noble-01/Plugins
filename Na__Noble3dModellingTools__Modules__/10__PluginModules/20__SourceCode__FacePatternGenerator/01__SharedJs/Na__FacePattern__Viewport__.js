(function () {
    'use strict';

    function na_computeBounds(polylines) {
        var minX = Infinity;
        var minY = Infinity;
        var maxX = -Infinity;
        var maxY = -Infinity;

        (polylines || []).forEach(function (polyline) {
            (polyline || []).forEach(function (point) {
                minX = Math.min(minX, point[0]);
                minY = Math.min(minY, point[1]);
                maxX = Math.max(maxX, point[0]);
                maxY = Math.max(maxY, point[1]);
            });
        });

        if (!isFinite(minX) || !isFinite(minY) || !isFinite(maxX) || !isFinite(maxY)) {
            return { minX: 0, minY: 0, maxX: 1000, maxY: 1000, width: 1000, height: 1000 };
        }

        return {
            minX: minX,
            minY: minY,
            maxX: maxX,
            maxY: maxY,
            width: Math.max(1, maxX - minX),
            height: Math.max(1, maxY - minY)
        };
    }

    function na_buildViewBox(bounds, paddingRatio) {
        var padX = bounds.width * (paddingRatio || 0.06);
        var padY = bounds.height * (paddingRatio || 0.06);
        return {
            minX: bounds.minX - padX,
            minY: bounds.minY - padY,
            width: bounds.width + (padX * 2),
            height: bounds.height + (padY * 2)
        };
    }

    function na_attachPanZoom(wrapper, state, onChange) {
        var dragging = false;
        var lastX = 0;
        var lastY = 0;

        wrapper.addEventListener('wheel', function (event) {
            event.preventDefault();
            var zoom = event.deltaY < 0 ? 0.92 : 1.08;
            state.width *= zoom;
            state.height *= zoom;
            onChange();
        }, { passive: false });

        wrapper.addEventListener('mousedown', function (event) {
            dragging = true;
            lastX = event.clientX;
            lastY = event.clientY;
            wrapper.style.cursor = 'grabbing';
        });

        window.addEventListener('mousemove', function (event) {
            if (!dragging) {
                return;
            }

            var dx = event.clientX - lastX;
            var dy = event.clientY - lastY;
            lastX = event.clientX;
            lastY = event.clientY;

            var rect = wrapper.getBoundingClientRect();
            if (rect.width <= 0 || rect.height <= 0) {
                return;
            }

            state.minX -= (dx / rect.width) * state.width;
            state.minY += (dy / rect.height) * state.height;
            onChange();
        });

        window.addEventListener('mouseup', function () {
            dragging = false;
            wrapper.style.cursor = 'grab';
        });
    }

    window.Na__FacePattern__Viewport = {
        na_computeBounds: na_computeBounds,
        na_buildViewBox: na_buildViewBox,
        na_attachPanZoom: na_attachPanZoom
    };
})();
