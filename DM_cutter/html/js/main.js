function encode_param(p) {
    var encoded = p.replace(/'/g, "PB2apos;");
    return encoded;
}

function tellSU(element) {
    id=element.id;
    temp=element.value;
    var value=encode_param(temp);
    window.location='skp:ValueChanged@' + id + "|" + value;
}

function detectIE() {
    var ua = window.navigator.userAgent;

    var msie = ua.indexOf('MSIE ');
    if (msie > 0) {
        // IE 10 or older => return version number
        return true;
    }

    var trident = ua.indexOf('Trident/');
    if (trident > 0) {
        // IE 11 => return version number
        return true;
    }

    var edge = ua.indexOf('Edge/');
    if (edge > 0) {
        return true;
    }

    // other browser
    return false;
}

// Localization
var l10n_strings = {};

function l10n(string) {
    var result = l10n_strings[string];
    if (result === undefined) {
        return string;
    } else {
        return result;
    }
}

// Call this method from WebDialog.
function localize(strings) {
    l10n_strings = strings;
    $(".localize").each(function() {
        var $this = $(this);
        var type = $this.prop('tagName').toLowerCase();
        var input, output = '';

        switch(type) {
            case "input":
                // Translate input placeholders
                input = $this.attr("placeholder");
                output = l10n(input);
                $this.attr("placeholder", output);
                // Translate button values
                input = $this.attr("value");
                output = l10n(input);
                $this.attr("value", output);
                break;

            default:
                input = $this.text();
                output = l10n(input);
                $this.text(output);
        }

    });
    $('[title]').each(function() {
        var $this = $(this);
        var input = $this.prop('title');
        var output = l10n(input);
        $this.prop('title', output);
    });
}

function disableContextMenu() {
    $(document).on('contextmenu', function(e) {
        return $(e.target).is('input[type=text]');
    });
}

function disableSelect() {
    $(document).on('mousedown selectstart', function(e) {
        return $(e.target).is('input, textarea, select, option');
    });
}

function ready() {
    disableContextMenu();
    disableSelect();
    sketchup.ready();
}