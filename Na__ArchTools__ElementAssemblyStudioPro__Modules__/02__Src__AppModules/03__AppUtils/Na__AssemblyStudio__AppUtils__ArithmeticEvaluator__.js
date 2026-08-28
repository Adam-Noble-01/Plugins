/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - SHARED ARITHMETIC EVALUATOR
   =============================================================================

   FILE       : Na__AssemblyStudio__AppUtils__ArithmeticEvaluator__.js
   NAMESPACE  : window.Na__Utils__Arithmetic
   AUTHOR     : Noble Architecture
   PURPOSE    : Turn every numeric field in the dialog into a small calculator,
                the way SketchUp's own VCB accepts arithmetic. Parses and
                evaluates a typed expression so the user never has to reach for
                a separate calculator to size an opening.
   CREATED    : 27-Aug-2026

   SUPPORTED SYNTAX:
   - Operators      : +  -  *  /  ^      (also accepts the typographic
                      x, ÷ and − characters, and 'x' between two numbers)
   - Brackets       : ( ) nested to any depth
   - Decimals       : 1650.5   .5
   - Whitespace     : ignored entirely
   - Relative entry : an expression that STARTS with an operator is applied to
                      the field's current value, so typing '+200' into a field
                      holding 2400 gives 2600 (see NOTE ON LEADING MINUS).

   WORKED EXAMPLES (all from real sizing tasks):
       1700-50                  -> 1650      trim an opening
       2400+200                 -> 2600      grow an opening
       +200                     -> current + 200
       2400/3                   -> 800       split a run into three bays
       800*3                    -> 2400      three bays back to a run
       2400+(100+100+100+100)   -> 2800      four packers added
       (3000-2*95)/3            -> 936.667   three equal lights inside stiles

   NOTE ON LEADING MINUS:
   A leading '-' is ambiguous: in a Width field '-50' can only sensibly mean
   "take 50 off", but in a signed field such as Meeting Rail Offset (-600..600)
   or Frame Wall Inset (-50..150) it must stay a literal negative. The caller
   therefore passes `allowRelativeMinus`, which the UI layer sets from the
   control's own minimum: relative when min >= 0, literal when the field can
   legitimately hold a negative. Leading '+', '*', '/' and '^' are always
   relative because none of them can begin a literal number.

   DESIGN NOTE:
   This is a hand-written tokeniser + recursive-descent parser rather than
   eval() / new Function(). Typed text is never executed as code, an
   unparseable entry returns a clean error instead of throwing, and the caller
   can revert the field rather than poisoning the config with NaN.

   NAMING CONVENTION:
   - All custom identifiers use Na__ or na_ prefix.

   ============================================================================= */


const Na__Utils__Arithmetic = (function () {

    'use strict';


    // -----------------------------------------------------------------------------
    // REGION | Module Constants
    // -----------------------------------------------------------------------------

    const NA_DECIMAL_PLACES   = 3;                                              // <-- Sub-micron in mm; kills float noise
    const NA_OPERATOR_TOKENS  = '+-*/^';                                        // <-- Binary operator character set
    const NA_PLAIN_NUMBER_RE  = /^[+-]?(\d+\.?\d*|\.\d+)$/;                     // <-- A value needing no evaluation
    const NA_LEADING_OP_RE    = /^[+\-*/^]/;                                    // <-- Marks a relative entry
    const NA_SPLIT_NUMBER_RE  = /[\d.]\s+[\d.]/;                                // <-- Two numbers with no operator

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Text Normalisation
    // -----------------------------------------------------------------------------

    // HELPER FUNCTION | Fold Typographic Operators Down to ASCII and Strip Spaces
    // ------------------------------------------------------------
    // Keyboards, autocorrect and pasted text all produce ×, ÷ and the real
    // minus sign −. Folding them here means the parser only ever sees ASCII.
    // A lone 'x' between two numbers ('3x600') is treated as multiply, which
    // is how joinery schedules are usually written.
    // @param  {String} text - Raw field text
    // @return {String}        Normalised, whitespace-free expression
    function na_normalise_text(text) {
        return String(text == null ? '' : text)
            .replace(/×/g, '*')                                            // <-- × multiplication sign
            .replace(/÷/g, '/')                                            // <-- ÷ division sign
            .replace(/[−–—]/g, '-')                              // <-- − – — dashes to hyphen
            .replace(/,/g, '')                                             // <-- Drop thousands separators
            .replace(/\s+/g, '')                                                // <-- All whitespace is insignificant
            .replace(/(\d)[xX](?=[\d.(])/g, '$1*');                             // <-- '3x600' -> '3*600'
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Reject Two Numbers Separated Only by Whitespace
    // ------------------------------------------------------------
    // Whitespace is stripped so '1700 - 50' reads naturally, but that would
    // also silently fuse a typo like '100 50' into 10050 and drop it straight
    // into a dimension. Caught on the raw text, before normalisation.
    // @param  {String}  rawText - Untouched field text
    // @return {Boolean}           True when an operator is missing
    function na_has_split_number(rawText) {
        return NA_SPLIT_NUMBER_RE.test(String(rawText == null ? '' : rawText));
    }
    // ---------------------------------------------------------------

    // FUNCTION | Test Whether Text Is Already a Plain Number
    // ------------------------------------------------------------
    // Callers use this to keep live per-keystroke updates working for ordinary
    // typing while deferring anything operator-bearing to the commit event.
    // @param  {String}  text - Raw field text
    // @return {Boolean}        True when no evaluation is needed
    function na_is_plain_number(text) {
        return NA_PLAIN_NUMBER_RE.test(na_normalise_text(text));
    }
    // ---------------------------------------------------------------

    // FUNCTION | Test Whether Text Carries Any Arithmetic
    // ------------------------------------------------------------
    // @param  {String}  text - Raw field text
    // @return {Boolean}        True when the text is more than a bare number
    function na_looks_like_expression(text) {
        const normalised = na_normalise_text(text);
        if (normalised === '') return false;
        return !NA_PLAIN_NUMBER_RE.test(normalised);
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Tokeniser
    // -----------------------------------------------------------------------------

    // HELPER FUNCTION | Split a Normalised Expression Into Tokens
    // ------------------------------------------------------------
    // Emits { type: 'number', value } for literals and { type: <char> } for
    // operators and brackets. Any other character is a hard error - better a
    // rejected entry the user can see than a silently mangled dimension.
    // @param  {String} normalised - Output of na_normalise_text
    // @return {Object}              { ok: true, tokens } | { ok: false, error }
    function na_tokenise(normalised) {
        const tokens = [];
        let index    = 0;

        while (index < normalised.length) {
            const character = normalised.charAt(index);

            if ((character >= '0' && character <= '9') || character === '.') {
                const start = index;
                let seenDot = false;
                while (index < normalised.length) {
                    const scan = normalised.charAt(index);
                    if (scan >= '0' && scan <= '9') { index += 1; continue; }
                    if (scan === '.' && !seenDot)   { seenDot = true; index += 1; continue; }
                    break;
                }
                const raw   = normalised.slice(start, index);
                const value = parseFloat(raw);
                if (!isFinite(value)) return { ok: false, error: 'Not a number: "' + raw + '"' };
                tokens.push({ type: 'number', value: value });
                continue;
            }

            if (NA_OPERATOR_TOKENS.indexOf(character) !== -1 || character === '(' || character === ')') {
                tokens.push({ type: character });
                index += 1;
                continue;
            }

            return { ok: false, error: 'Cannot use "' + character + '" here' };
        }

        return { ok: true, tokens: tokens };
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Recursive-Descent Parser
    // -----------------------------------------------------------------------------

    // HELPER FUNCTION | Parse and Fold a Token Stream to a Single Number
    // ------------------------------------------------------------
    // Grammar, loosest binding first:
    //   expression := term (('+' | '-') term)*
    //   term       := unary (('*' | '/') unary)*
    //   unary      := ('+' | '-') unary | power
    //   power      := primary ('^' unary)?          <-- right associative
    //   primary    := number | '(' expression ')'
    // @param  {Array}  tokens - Output of na_tokenise
    // @return {Object}          { value } | { error }
    function na_parse(tokens) {
        let position = 0;

        function na_peek() {
            return tokens[position];
        }

        function na_parse_primary() {
            const token = na_peek();
            if (!token) return { error: 'Expression is incomplete' };

            if (token.type === 'number') {
                position += 1;
                return { value: token.value };
            }
            if (token.type === '(') {
                position += 1;
                const inner = na_parse_expression();
                if (inner.error) return inner;
                const closing = na_peek();
                if (!closing || closing.type !== ')') return { error: 'Missing a closing bracket' };
                position += 1;
                return { value: inner.value };
            }
            if (token.type === ')') return { error: 'Unmatched closing bracket' };
            return { error: 'Missing a number before "' + token.type + '"' };
        }

        function na_parse_power() {
            const base = na_parse_primary();
            if (base.error) return base;
            const token = na_peek();
            if (!token || token.type !== '^') return base;
            position += 1;
            const exponent = na_parse_unary();                                  // <-- Right associative: 2^3^2 = 2^9
            if (exponent.error) return exponent;
            return { value: Math.pow(base.value, exponent.value) };
        }

        function na_parse_unary() {
            const token = na_peek();
            if (token && (token.type === '+' || token.type === '-')) {
                position += 1;
                const operand = na_parse_unary();
                if (operand.error) return operand;
                return { value: token.type === '-' ? -operand.value : operand.value };
            }
            return na_parse_power();
        }

        function na_parse_term() {
            let left = na_parse_unary();
            if (left.error) return left;
            for (;;) {
                const token = na_peek();
                if (!token || (token.type !== '*' && token.type !== '/')) break;
                position += 1;
                const right = na_parse_unary();
                if (right.error) return right;
                if (token.type === '/' && right.value === 0) return { error: 'Cannot divide by zero' };
                left = { value: token.type === '*' ? left.value * right.value : left.value / right.value };
            }
            return left;
        }

        function na_parse_expression() {
            let left = na_parse_term();
            if (left.error) return left;
            for (;;) {
                const token = na_peek();
                if (!token || (token.type !== '+' && token.type !== '-')) break;
                position += 1;
                const right = na_parse_term();
                if (right.error) return right;
                left = { value: token.type === '+' ? left.value + right.value : left.value - right.value };
            }
            return left;
        }

        const result = na_parse_expression();
        if (result.error) return result;
        if (position < tokens.length) {
            return { error: 'Cannot read past "' + tokens[position].type + '"' };
        }
        return result;
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Rounding
    // -----------------------------------------------------------------------------

    // FUNCTION | Round Away Binary Floating-Point Noise
    // ------------------------------------------------------------
    // 0.1 + 0.2 must present as 0.3, and 2400/7 as 342.857 rather than
    // 342.85714285714283 landing in a millimetre field.
    // @param  {Number} value - Raw computed value
    // @return {Number}        Value rounded to NA_DECIMAL_PLACES
    function na_round(value) {
        const factor = Math.pow(10, NA_DECIMAL_PLACES);
        return Math.round(value * factor) / factor;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Render a Number for Display in a Field
    // ------------------------------------------------------------
    // @param  {Number} value - Resolved value
    // @return {String}         Trimmed decimal string ('1650', '342.857')
    function na_format(value) {
        if (typeof value !== 'number' || !isFinite(value)) return '';
        return String(na_round(value));
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Public API - Evaluation
    // -----------------------------------------------------------------------------

    // FUNCTION | Evaluate a Standalone Arithmetic Expression
    // ------------------------------------------------------------
    // Never throws. Relative entry is NOT handled here - use
    // na_resolve_field_value for anything typed into a live control.
    // @param  {String} text - Expression text
    // @return {Object}        { ok: true, value } | { ok: false, error }
    function na_evaluate(text) {
        if (na_has_split_number(text)) return { ok: false, error: 'Missing an operator between numbers' };

        const normalised = na_normalise_text(text);
        if (normalised === '') return { ok: false, error: 'Nothing to calculate' };

        const tokenised = na_tokenise(normalised);
        if (!tokenised.ok) return { ok: false, error: tokenised.error };
        if (tokenised.tokens.length === 0) return { ok: false, error: 'Nothing to calculate' };

        const parsed = na_parse(tokenised.tokens);
        if (parsed.error) return { ok: false, error: parsed.error };
        if (!isFinite(parsed.value)) return { ok: false, error: 'Result is not a finite number' };

        return { ok: true, value: na_round(parsed.value) };
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Public API - Field Resolution
    // -----------------------------------------------------------------------------

    // FUNCTION | Resolve What the User Typed Into a Usable Field Value
    // ------------------------------------------------------------
    // The single entry point for every numeric control. Handles relative
    // entry, evaluation and range clamping in one place so the shared slider,
    // the Interior Door slider and the EQ-number field all behave identically.
    //
    // @param  {String} rawText - Exactly what is sitting in the input
    // @param  {Object} options
    //         {Number}  currentValue       - Value before this edit (for relative entry)
    //         {Number}  min                - Lower clamp; omit or non-finite to skip
    //         {Number}  max                - Upper clamp; omit or non-finite to skip
    //         {Boolean} allowRelativeMinus - Treat a leading '-' as relative
    // @return {Object}
    //         {Boolean} ok             - False when the entry could not be read
    //         {Number}  value          - Resolved, clamped value (ok only)
    //         {String}  text           - Value formatted for the field (ok only)
    //         {Boolean} wasExpression  - True when arithmetic was actually performed
    //         {Boolean} wasRelative    - True when applied to currentValue
    //         {Boolean} wasClamped     - True when the range clamp moved the result
    //         {String}  error          - Human-readable reason (failure only)
    function na_resolve_field_value(rawText, options) {
        const settings = options || {};
        if (na_has_split_number(rawText)) return { ok: false, error: 'Missing an operator between numbers' };

        const normalised = na_normalise_text(rawText);
        if (normalised === '') return { ok: false, error: 'Nothing to calculate' };

        const current      = Number(settings.currentValue);
        const hasCurrent   = isFinite(current);
        const startsWithOp = NA_LEADING_OP_RE.test(normalised);
        const minusIsRelative = settings.allowRelativeMinus !== false;

        // Relative entry: fold the current value in as a bracketed left operand
        // so '+200' becomes '(2400)+200' and '/3' becomes '(2400)/3'.
        let wasRelative = false;
        let expression  = normalised;
        if (startsWithOp && hasCurrent) {
            const leadingCharacter = normalised.charAt(0);
            if (leadingCharacter !== '-' || minusIsRelative) {
                expression  = '(' + current + ')' + normalised;
                wasRelative = true;
            }
        }

        const evaluated = na_evaluate(expression);
        if (!evaluated.ok) return { ok: false, error: evaluated.error };

        // Clamp last, so a relative nudge past the end of the range still lands
        // on the range end rather than being rejected outright.
        let value      = evaluated.value;
        let wasClamped = false;
        const minimum  = Number(settings.min);
        const maximum  = Number(settings.max);
        if (isFinite(minimum) && value < minimum) { value = minimum; wasClamped = true; }
        if (isFinite(maximum) && value > maximum) { value = maximum; wasClamped = true; }
        value = na_round(value);

        return {
            ok            : true,
            value         : value,
            text          : na_format(value),
            wasExpression : wasRelative || !NA_PLAIN_NUMBER_RE.test(normalised),
            wasRelative   : wasRelative,
            wasClamped    : wasClamped
        };
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------


    return {
        na_evaluate             : na_evaluate,
        na_resolve_field_value  : na_resolve_field_value,
        na_is_plain_number      : na_is_plain_number,
        na_looks_like_expression: na_looks_like_expression,
        na_format               : na_format,
        na_round                : na_round
    };

})();


// =============================================================================
// REGION | Browser Global Attachment
// =============================================================================

window.Na__Utils__Arithmetic = Object.freeze(Na__Utils__Arithmetic);
console.log('[NA_UTILS_ARITHMETIC] Shared arithmetic evaluator loaded');

// endregion -------------------------------------------------------------------


/* =============================================================================
   END OF FILE
   ============================================================================= */
