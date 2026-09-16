/* =============================================================================
   NA ARRAY BUILDER TOOLS - UI INPUT
   FILE       : Na__ArrayBuilder__UiInput__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Forgiving dimensional input without eval or partial-number edits.
   ============================================================================= */

// FUNCTION | Accept Complete Numeric Values With Optional Length Units
// -----------------------------------------------------------------------------
export function Na__UiInput__ParseLength(na_text, na_key) {
    const na_match = String(na_text).trim().match(/^([+-]?(?:\d+(?:\.\d*)?|\.\d+))\s*(mm|cm|m|in|inch|inches|ft|"|')?$/i);
    if (!na_match) return null;
    const na_factors = { mm: 1, cm: 10, m: 1000, in: 25.4, inch: 25.4, inches: 25.4, ft: 304.8, '"': 25.4, "'": 304.8 };
    const na_value = Number(na_match[1]) * (na_factors[(na_match[2] || 'mm').toLowerCase()]);
    const na_min = na_key.startsWith('offset_') ? -1000000 : (na_key.startsWith('unit_') ? 0.1 : 0);
    return Number.isFinite(na_value) && na_value >= na_min && na_value <= 1000000 ? na_value : null;
}
