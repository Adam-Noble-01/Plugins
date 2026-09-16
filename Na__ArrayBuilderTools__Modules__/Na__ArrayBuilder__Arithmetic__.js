/* =============================================================================
   NA ARRAY BUILDER TOOLS - ARITHMETIC
   FILE       : Na__ArrayBuilder__Arithmetic__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Small expression parser following Element Assembly Studio's input
                conventions. No eval, scripts or third-party dependencies.
   ============================================================================= */

// FUNCTION | Evaluate Numbers, Lengths, Parentheses and Arithmetic Operators
// -----------------------------------------------------------------------------
export function Na__Arithmetic__Evaluate(na_raw) {
    let na_text = String(na_raw).trim().replace(/[×x]/g, '*').replace(/÷/g, '/').replace(/[−–—]/g, '-');
    if (!na_text || na_text.length > 256 || /\d\s+\d/.test(na_text)) throw new Error('Enter a complete calculation.');
    const na_units = { mm: 1, cm: 10, m: 1000, in: 25.4, inch: 25.4, inches: 25.4, ft: 304.8, '"': 25.4, "'": 304.8 };
    const na_tokens = [];
    while (na_text.trim()) {
        na_text = na_text.trimStart();
        const na_number = na_text.match(/^(\d+(?:\.\d*)?|\.\d+)(?:\s*(inches|inch|mm|cm|ft|in|m|"|'))?/i);
        if (na_number) {
            na_tokens.push(Number(na_number[1]) * (na_units[(na_number[2] || 'mm').toLowerCase()]));
            na_text = na_text.slice(na_number[0].length);
        } else if ('+-*/^()'.includes(na_text[0])) {
            na_tokens.push(na_text[0]);
            na_text = na_text.slice(1);
        } else throw new Error('Use numbers, mm/cm/m/in/ft, and + − × ÷ ^ ( ).');
    }
    let na_cursor = 0;
    function Na__Arithmetic__Primary() {
        const na_token = na_tokens[na_cursor++];
        if (typeof na_token === 'number') return na_token;
        if (na_token === '(') {
            const na_value = Na__Arithmetic__Expression();
            if (na_tokens[na_cursor++] !== ')') throw new Error('Close the calculation with a matching parenthesis.');
            return na_value;
        }
        throw new Error('Finish entering the calculation.');
    }
    function Na__Arithmetic__Unary() {
        if (na_tokens[na_cursor] === '+') { na_cursor++; return Na__Arithmetic__Unary(); }
        if (na_tokens[na_cursor] === '-') { na_cursor++; return -Na__Arithmetic__Unary(); }
        let na_value = Na__Arithmetic__Primary();
        if (na_tokens[na_cursor] === '^') { na_cursor++; na_value **= Na__Arithmetic__Unary(); }
        return na_value;
    }
    function Na__Arithmetic__Term() {
        let na_value = Na__Arithmetic__Unary();
        while (['*', '/'].includes(na_tokens[na_cursor])) {
            const na_operator = na_tokens[na_cursor++];
            const na_right = Na__Arithmetic__Unary();
            if (na_operator === '/' && na_right === 0) throw new Error('Cannot divide by zero.');
            na_value = na_operator === '*' ? na_value * na_right : na_value / na_right;
        }
        return na_value;
    }
    function Na__Arithmetic__Expression() {
        let na_value = Na__Arithmetic__Term();
        while (['+', '-'].includes(na_tokens[na_cursor])) {
            const na_operator = na_tokens[na_cursor++];
            const na_right = Na__Arithmetic__Term();
            na_value = na_operator === '+' ? na_value + na_right : na_value - na_right;
        }
        return na_value;
    }
    const na_result = Na__Arithmetic__Expression();
    if (na_cursor !== na_tokens.length || !Number.isFinite(na_result)) throw new Error('The calculation must produce a finite number.');
    return na_result;
}
