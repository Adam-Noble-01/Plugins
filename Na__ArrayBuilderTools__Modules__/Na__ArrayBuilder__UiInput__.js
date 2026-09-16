/* =============================================================================
   NA ARRAY BUILDER TOOLS - UI INPUT
   FILE       : Na__ArrayBuilder__UiInput__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Forgiving dimensional input without eval or partial-number edits.
   ============================================================================= */

import { Na__Arithmetic__Evaluate } from './Na__ArrayBuilder__Arithmetic__.js';

export function Na__UiInput__Minimum(na_key) {
    return na_key.startsWith('offset_') || na_key === 'inset_mm' ? -1000000 : (na_key.startsWith('unit_') ? 0.1 : 0);
}

// FUNCTION | Accept Complete Numeric Values With Optional Length Units
// -----------------------------------------------------------------------------
export function Na__UiInput__ParseLength(na_text, na_key) {
    const na_match = String(na_text).trim().match(/^([+-]?(?:\d+(?:\.\d*)?|\.\d+))\s*(mm|cm|m|in|inch|inches|ft|"|')?$/i);
    if (!na_match) return null;
    const na_factors = { mm: 1, cm: 10, m: 1000, in: 25.4, inch: 25.4, inches: 25.4, ft: 304.8, '"': 25.4, "'": 304.8 };
    const na_value = Number(na_match[1]) * (na_factors[(na_match[2] || 'mm').toLowerCase()]);
    const na_min = Na__UiInput__Minimum(na_key);
    return Number.isFinite(na_value) && na_value >= na_min && na_value <= 1000000 ? na_value : null;
}

// FUNCTION | Commit Calculations Using the Value at the Start of the Edit
// -----------------------------------------------------------------------------
export function Na__UiInput__Resolve(na_text, na_key, na_current) {
    const na_raw = String(na_text).trim();
    const na_min = Na__UiInput__Minimum(na_key);
    const na_relative = /^[+*/^]/.test(na_raw) || (na_min >= 0 && /^-/.test(na_raw));
    const na_expression = na_relative ? '(' + (Number(na_current) || 0) + ')' + na_raw : na_raw;
    const na_value = Na__Arithmetic__Evaluate(na_expression);
    return Number(Math.max(na_min, Math.min(1000000, na_value)).toFixed(3));
}

export function Na__UiInput__Nudge(na_value, na_key, na_direction, na_shift) {
    return Number(Math.max(Na__UiInput__Minimum(na_key), Math.min(1000000, na_value + na_direction * (na_shift ? 50 : 5))).toFixed(3));
}
