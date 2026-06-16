// =============================================================================
// NA NOBLE3D MODELLING TOOLS - FACE PATTERN - NOISE
// =============================================================================
//
// FILE       : Na__FacePattern__Noise__.js
// NAMESPACE  : window.Na__FacePattern__Noise
// AUTHOR     : Adam Noble - Noble Architecture
// PURPOSE    : Mulberry32 seeded random, 2D value noise, and 3-octave FBM —
//              consolidated from the Brickwork and Stonework prototypes.
// CREATED    : 2026
//
// =============================================================================

window.Na__FacePattern__Noise = (function () {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Seeded Random
    // -------------------------------------------------------------------------

    // FUNCTION | Mulberry32 Seeded Pseudo-Random Number Generator
    // ------------------------------------------------------------
    function na_seededRandom(seed) {
        var t = seed + 0x6D2B79F5;
        t = Math.imul(t ^ (t >>> 15), t | 1);
        t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Value Noise and FBM
    // -------------------------------------------------------------------------

    // FUNCTION | 2D Value Noise with Smooth Interpolation
    // ------------------------------------------------------------
    function na_noise2D(x, y, seed) {
        function hash(ix, iy) {
            return na_seededRandom(ix * 374761393 + iy * 668265263 + seed * 1013904223);
        }

        var ix = Math.floor(x);
        var iy = Math.floor(y);
        var fx = x - ix;
        var fy = y - iy;
        var sx = fx * fx * (3 - (2 * fx));
        var sy = fy * fy * (3 - (2 * fy));

        var n00 = hash(ix, iy);
        var n10 = hash(ix + 1, iy);
        var n01 = hash(ix, iy + 1);
        var n11 = hash(ix + 1, iy + 1);

        var nx0 = n00 + (sx * (n10 - n00));
        var nx1 = n01 + (sx * (n11 - n01));
        return nx0 + (sy * (nx1 - nx0));
    }
    // ------------------------------------------------------------

    // FUNCTION | Fractal Brownian Motion (Multi-Octave Value Noise)
    // ------------------------------------------------------------
    function na_fbmNoise(x, y, seed, octaves) {
        var total = 0;
        var amplitude = 1;
        var frequency = 1;
        var maxAmplitude = 0;
        var index = 0;
        var octaveCount = octaves || 3;

        for (; index < octaveCount; index += 1) {
            total += amplitude * na_noise2D(x * frequency, y * frequency, seed + (index * 1999));
            maxAmplitude += amplitude;
            amplitude *= 0.5;
            frequency *= 2;
        }

        return maxAmplitude > 0 ? total / maxAmplitude : 0;
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    return {
        na_seededRandom: na_seededRandom,
        na_noise2D: na_noise2D,
        na_fbmNoise: na_fbmNoise
    };

})();

// =============================================================================
// END OF FILE
// =============================================================================
