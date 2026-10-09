/* =============================================================================
   NA PROFILE TOOLS - DRAW PROFILE - MEASUREMENTS BOX (VCB)
   =============================================================================
   FILE       : Na__ProfileTools__DrawProfile__Vcb__.js
   NAMESPACE  : window.Na__DrawProfile__Vcb
   PURPOSE    : SketchUp's Value Control Box for the Draw Profile editor: read
                what is typed, and the box itself - type without clicking,
                Enter to apply, Esc to clear, with the live reading shown while
                nothing is typed and what a value will mean shown as it is typed.

   READING (TV MeasureParse, ported; additions marked +)
     2500  2,500  250cm  2.5m        a length in millimetres; commas are
                                     thousands separators where exactly three
                                     digits follow (TV's rule)
     900,600  900x600  900;600       a pair (TV's comma rule for pairs)
     3x  x3  *3  /3                  an array after a copy (TV)
   + @50,20  @50;20                  a relative point: 50 across, 20 up
   + [120,45]                        an absolute point
   + 50<30                           50 long at 30 degrees
   + 12s                             segments for an arc or circle (SketchUp)
   + 20r  40d  5b                    radius, diameter, bulge
   + 30deg  30°                      an angle

   A bare number means what the active tool's label says it means; the hint
   line spells the reading out before Enter, so nothing is guessed in secret.
   ============================================================================= */

(function () {
    'use strict';

    var G = window.Na__DrawProfile__Geom;

    // -------------------------------------------------------------------------
    // REGION | TV MeasureParse (ported verbatim but for the module wrapper)
    // -------------------------------------------------------------------------

    var UNITS = [ { name : 'mm', factor : 1 }, { name : 'cm', factor : 10 }, { name : 'm', factor : 1000 } ];
    var PAIR_SEPARATORS = 'xX*;';
    var PAIR_MAX_DIGITS = 6;

    function IsDigit(ch) { return typeof ch === 'string' && ch.length === 1 && ch >= '0' && ch <= '9'; }
    function SkipSpaces(text, index) { var i = index; while (i < text.length && text[i] === ' ') i++; return i; }

    function ReadLength(text, index, pairMode) {
        var i = SkipSpaces(text, index);
        var sign = 1;
        if (text[i] === '-' || text[i] === '+') {
            if (text[i] === '-') sign = -1;
            i = SkipSpaces(text, i + 1);
        }
        var whole = '';
        while (IsDigit(text[i])) { whole += text[i]; i++; }
        if (whole.length >= 1 && whole.length <= 3 && whole !== '0') {
            var lead = whole.length;
            while (text[i] === ',' && IsDigit(text[i + 1]) && IsDigit(text[i + 2]) && IsDigit(text[i + 3]) && !IsDigit(text[i + 4])) {
                if (pairMode && lead === 3 && whole.length === 3) break;
                if (pairMode && whole.length + 3 > PAIR_MAX_DIGITS) break;
                whole += text.substr(i + 1, 3);
                i += 4;
            }
        }
        var fraction = '';
        if (text[i] === '.') {
            var j = i + 1;
            while (IsDigit(text[j])) { fraction += text[j]; j++; }
            if (fraction.length || whole.length) i = j;
        }
        if (!whole.length && !fraction.length) return { error : 'number' };
        var magnitude = parseFloat((whole || '0') + '.' + (fraction || '0'));
        if (!Number.isFinite(magnitude)) return { error : 'number' };
        var afterNumber = i;
        i = SkipSpaces(text, i);
        var rest = text.slice(i).toLowerCase();
        var unit = null;
        for (var u = 0; u < UNITS.length; u++) { if (rest.indexOf(UNITS[u].name) === 0) { unit = UNITS[u]; break; } }
        if (unit) {
            var next = text[i + unit.name.length];
            if (next !== undefined && /[a-zA-Z]/.test(next)) return { error : 'unit' };
            i += unit.name.length;
        } else {
            if (/^[a-zA-Z]/.test(rest) && PAIR_SEPARATORS.indexOf(rest.charAt(0)) === -1) return { error : 'unit' };
            i = afterNumber;
        }
        return { valueMm : sign * magnitude * (unit ? unit.factor : 1), end : i, unit : unit ? unit.name : null };
    }

    function Length(text) {
        var src = String(text === undefined || text === null ? '' : text).trim();
        if (!src) return { ok : false, reason : 'empty' };
        var token = ReadLength(src, 0, false);
        if (token.error) return { ok : false, reason : token.error };
        if (SkipSpaces(src, token.end) !== src.length) return { ok : false, reason : 'number' };
        return { ok : true, valueMm : token.valueMm };
    }

    function Sides(left, right) {
        var a = left.trim(), b = right.trim();
        if (!a && !b) return { ok : false, reason : 'pair' };
        var first = a ? Length(a) : null;
        var second = b ? Length(b) : null;
        if ((first && !first.ok) || (second && !second.ok)) return { ok : false, reason : 'pair' };
        return { ok : true, first : first ? first.valueMm : null, second : second ? second.valueMm : null, square : false };
    }

    function Pair(text) {
        var src = String(text === undefined || text === null ? '' : text).trim();
        if (!src) return { ok : false, reason : 'empty' };
        var explicitAt = -1, explicitCount = 0;
        for (var c = 0; c < src.length; c++) {
            if (PAIR_SEPARATORS.indexOf(src[c]) !== -1) { explicitCount++; if (explicitAt === -1) explicitAt = c; }
        }
        if (explicitCount > 1) return { ok : false, reason : 'pair' };
        if (explicitCount === 1) return Sides(src.slice(0, explicitAt), src.slice(explicitAt + 1));
        var i = 0, first = null, token;
        if (src[0] !== ',') {
            token = ReadLength(src, 0, true);
            if (token.error) return { ok : false, reason : token.error === 'unit' ? token.error : 'pair' };
            first = token.valueMm;
            i = SkipSpaces(src, token.end);
            if (i === src.length) return { ok : true, first : first, second : first, square : true };
        }
        if (src[i] !== ',') return { ok : false, reason : 'pair' };
        i = SkipSpaces(src, i + 1);
        if (i === src.length) return first === null ? { ok : false, reason : 'pair' } : { ok : true, first : first, second : null, square : false };
        token = ReadLength(src, i, true);
        if (token.error) return { ok : false, reason : token.error === 'unit' ? token.error : 'pair' };
        if (SkipSpaces(src, token.end) !== src.length) return { ok : false, reason : 'pair' };
        return { ok : true, first : first, second : token.valueMm, square : false };
    }

    function ArrayCount(text) {
        var src = String(text === undefined || text === null ? '' : text).trim();
        if (!src) return { ok : false, reason : 'empty' };
        var found = /^(?:([xX*])\s*([0-9.,]+)|([0-9.,]+)\s*([xX*])|\/\s*([0-9.,]+)|([0-9.,]+)\s*\/)$/.exec(src);
        if (!found) return { ok : false, reason : 'number' };
        var digits = found[2] || found[3] || found[5] || found[6];
        var mode = (found[5] || found[6]) ? 'divide' : 'times';
        if (!/^[0-9]+$/.test(digits)) return { ok : false, reason : 'count' };
        var count = parseInt(digits, 10);
        if (!(count >= 1)) return { ok : false, reason : 'count' };
        return { ok : true, mode : mode, count : count };
    }

    function Format(valueMm, precision) {
        return G.FormatMm(valueMm, Number.isFinite(precision) ? precision : 2);
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Reading Everything Else (+)
    // -------------------------------------------------------------------------

    var NUM = '[-+]?(?:\\d+(?:\\.\\d*)?|\\.\\d+)';

    // One reader for every form. Returns { ok, type, ... } where type is one
    // of: segments, radius, diameter, bulge, angle, absolute, relative, polar,
    // array, length, pair. options.pair true lets "a,b" read as a pair once
    // it is not a single length (TV's own Length rule tried first).
    function Read(text, options) {
        var src = String(text === undefined || text === null ? '' : text).trim();
        var opts = options || {};
        if (!src) return { ok : false, reason : 'empty' };
        var m;

        if ((m = /^(\d+)\s*s$/i.exec(src))) return { ok : true, type : 'segments', count : parseInt(m[1], 10) };

        if ((m = new RegExp('^(' + NUM + ')\\s*(?:°|deg|degs|degrees)$', 'i').exec(src))) {
            return { ok : true, type : 'angle', deg : parseFloat(m[1]) };
        }

        if ((m = /^(.+?)\s*([rdb])$/i.exec(src)) && !/[cm]m?$/i.test(src)) {
            var inner = Length(m[1]);
            if (inner.ok) {
                var kind = m[2].toLowerCase();
                return { ok : true, type : kind === 'r' ? 'radius' : (kind === 'd' ? 'diameter' : 'bulge'), valueMm : inner.valueMm };
            }
        }

        if ((m = /^\[\s*(.+?)\s*[,;]\s*(.+?)\s*\]$/.exec(src))) {
            var ax = Length(m[1]), ay = Length(m[2]);
            if (ax.ok && ay.ok) return { ok : true, type : 'absolute', x : ax.valueMm, y : ay.valueMm };
            return { ok : false, reason : 'point' };
        }

        if ((m = /^@\s*(.+?)\s*[,;]\s*(.+)$/.exec(src))) {
            var rx = Length(m[1]), ry = Length(m[2]);
            if (rx.ok && ry.ok) return { ok : true, type : 'relative', dx : rx.valueMm, dy : ry.valueMm };
            return { ok : false, reason : 'point' };
        }

        if ((m = new RegExp('^(.+?)\\s*<\\s*(' + NUM + ')\\s*(?:°|deg)?$', 'i').exec(src))) {
            var pl = Length(m[1]);
            if (pl.ok) return { ok : true, type : 'polar', length : pl.valueMm, deg : parseFloat(m[2]) };
            return { ok : false, reason : 'point' };
        }

        var arr = ArrayCount(src);
        if (arr.ok) return { ok : true, type : 'array', mode : arr.mode, count : arr.count };

        // Where a pair is welcome, TV's pair rule reads the comma first:
        // 900,600 is two figures, 1,500 is still one (it reads as a square,
        // which is no pair, and falls through to the length).
        if (opts.pair !== false) {
            var pair = Pair(src);
            if (pair.ok && !pair.square) return { ok : true, type : 'pair', first : pair.first, second : pair.second };
        }

        var len = Length(src);
        if (len.ok) return { ok : true, type : 'length', valueMm : len.valueMm };

        if (opts.plainNumber && new RegExp('^' + NUM + '$').test(src)) return { ok : true, type : 'number', value : parseFloat(src) };
        return { ok : false, reason : len.reason || 'number' };
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | The Box
    // -------------------------------------------------------------------------

    // TV Measurements: a value starts with one of these; once it has started
    // every printable key goes to it until Enter or Esc.
    var START_CHARS = '0123456789.,-+@[<';

    function Controller(elements, handlers) {
        this.el = elements;               // { root, label, input, hint }
        this.handlers = handlers || {};   // { commit(text) -> {ok, message}, preview(text) -> string, isActive() -> bool }
        this.text = '';
        this.hintTimer = null;
        this.reading = '';
        this.labelText = '';
        this.SyncDom();
    }

    // With nothing to measure the box still says what it is, greyed (TV).
    Controller.prototype.SetLabel = function (label) {
        this.labelText = label || '';
        if (this.el.label) this.el.label.textContent = this.labelText || 'Measurements';
        if (this.el.root) this.el.root.classList.toggle('na-dp-vcb--idle', !this.labelText);
    };

    // The live reading, shown as the placeholder while nothing is typed.
    Controller.prototype.SetReading = function (reading) {
        this.reading = reading || '';
        if (this.el.input) this.el.input.placeholder = this.reading;
    };

    Controller.prototype.Hint = function (message, isError, holdMs) {
        var self = this;
        if (!this.el.hint) return;
        this.el.hint.textContent = message || '';
        this.el.hint.classList.toggle('na-dp-vcb__hint--error', !!isError);
        this.el.hint.classList.toggle('na-dp-vcb__hint--shown', !!message);
        if (this.hintTimer) window.clearTimeout(this.hintTimer);
        this.hintTimer = null;
        if (message && holdMs !== 0) {
            this.hintTimer = window.setTimeout(function () { self.Hint(''); }, holdMs || 2800);
        }
    };

    Controller.prototype.Clear = function () {
        this.text = '';
        this.SyncDom();
    };

    Controller.prototype.HasText = function () {
        return this.text.length > 0;
    };

    Controller.prototype.SyncDom = function () {
        if (this.el.input && document.activeElement !== this.el.input) this.el.input.value = this.text;
        if (this.el.root) this.el.root.classList.toggle('na-dp-vcb--typing', this.text.length > 0);
        this.Preview();
    };

    Controller.prototype.Preview = function () {
        if (!this.text) { if (this.el.hint && !this.hintTimer) this.Hint(''); return; }
        var describe = this.handlers.preview ? this.handlers.preview(this.text) : '';
        this.Hint(describe || '', false, 0);
    };

    Controller.prototype.Commit = function () {
        var text = this.text.trim();
        if (!text) return false;
        var outcome = this.handlers.commit ? this.handlers.commit(text) : { ok : false, message : 'Nothing takes a value right now.' };
        if (outcome && outcome.ok) {
            this.text = '';
            this.SyncDom();
            this.Hint(outcome.message || '', false);
        } else {
            this.Hint((outcome && outcome.message) || ('"' + text + '" is not a value this tool can use.'), true, 4200);
        }
        return true;
    };

    // Keydown from the document, capture phase. Returns true when the key was
    // the box's to take, so the editor's shortcuts never see it.
    Controller.prototype.OnKey = function (event) {
        if (event.ctrlKey || event.altKey || event.metaKey) return false;
        var key = event.key;
        if (this.text.length === 0) {
            if (key.length === 1 && START_CHARS.indexOf(key) !== -1) {
                this.text = key;
                this.SyncDom();
                return true;
            }
            return false;
        }
        if (key === 'Enter') { this.Commit(); return true; }
        if (key === 'Escape' || key === 'Delete') { this.Clear(); this.Hint(''); return true; }
        if (key === 'Backspace') { this.text = this.text.slice(0, -1); this.SyncDom(); return true; }
        if (key.length === 1) { this.text += key; this.SyncDom(); return true; }
        return false;
    };

    // Typing straight into the input when it has been clicked.
    Controller.prototype.BindInput = function () {
        var self = this;
        var input = this.el.input;
        if (!input) return;
        input.addEventListener('input', function () { self.text = input.value; self.Preview(); if (self.el.root) self.el.root.classList.toggle('na-dp-vcb--typing', self.text.length > 0); });
        input.addEventListener('keydown', function (event) {
            if (event.key === 'Enter') { event.preventDefault(); event.stopPropagation(); self.text = input.value; self.Commit(); input.value = self.text; }
            else if (event.key === 'Escape') { event.preventDefault(); event.stopPropagation(); self.Clear(); input.value = ''; input.blur(); }
            else event.stopPropagation();
        });
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Export
    // -------------------------------------------------------------------------

    window.Na__DrawProfile__Vcb = {
        Length : Length,
        Pair : Pair,
        ArrayCount : ArrayCount,
        Format : Format,
        Read : Read,
        Controller : Controller
    };

    // endregion ----------------------------------------------------------------
})();
