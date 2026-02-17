$(function() {

    $(':text').on('keydown', function(event) {
        // Enter key is 13
        if (event.keyCode == 13) {
            this.blur();
        }
    })
} );

function rb_show_body() {
    $('.body-hide').removeClass('body-hide');
}

function sliderChange(element){
    id = element.id;
    value = element.value;
    var location = 'skp:SliderChanged@' + id + "|" + value;
    window.location = location;
}

function startSlider(element){
    element.onchange = function() { sliderChange(this); };
    element.oninput = function() { this.onchange = null; sliderChange(this); };

    var location = 'skp:SliderOperationStart';
    window.location = location;
}

function endSlider(element){
    element.onchange = null;
    element.oninput = null;
    value = element.value;
    
    var location = 'skp:SliderOperationEnd@' + value;
    window.location = location;
}

function encode_param(p) {
    var encoded = p.replace(/'/g, "PB2apos;");
    return encoded;
}

function set_checkbox_by_value(id) {
    var checkbox = document.getElementById(id);
    checkbox.checked = (checkbox.value == 'true');
}

function set_checkbox_value(id) {
    var checkbox = document.getElementById(id);
    checkbox.value = checkbox.checked;
}

function set_radio(name, value) {
    var $radios = $('input:radio[name=' + name + ']');
    $radios.each(function() {
       $(this).parent().removeClass('active');
       $(this).prop('checked', false);
    });
    // Although bootstrap should automatically add the active class when the radio
    // becomes checked, for some reason, this does not always happen so I am
    // also adding it explicitly to ensure it always happens.  I think this function
    // only gets called when the dialog gets refreshed
    $radios.filter('[value=' + value + ']').prop('checked', true).parent().addClass("active");
}

function tellSU(element) {
    id=element.id;
    value=element.value;
    sketchup.ValueChanged(id, value)
}

function tellSU2(id, value) {
    sketchup.ValueChanged(id, value)
}

function buttonClicked(element) {
    // Ensure that any active input fields will fire their onchange event prior to
    // the dialog firing the event for this button click
    unfocusActiveElement();
    tellSU(element);
}
 
function tellSUcb(element) {
    id=element.id;
    value=element.checked;
    sketchup.ValueChanged(id, value)
}

function unfocusActiveElement() {
    if (document.activeElement != document.body) {
        document.activeElement.blur();
    }
}

function ensure_tool_settings_are_updated(){
    if (document.activeElement != document.body) {
        // window.location = 'skp:triggerOnChangeEvent';
    }
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

function clearList(id)
{
    list=document.getElementById(id)
    list_length=list.length
    for (i=0;i<list_length;i++){
        list.remove(0)
    }
}

function createOptionAndValue(id,option_name,value_name)
{
    var op=document.createElement('option');
    op.text=option_name
    op.value=value_name
    document.getElementById(id).add(op);
}

 
//Credit to Julia Eneroth for this code
function port_key(){
  //Sends the keycode from the event to a Ruby callback.
  //This can be used for web dialogs inside a custom tools to send key events to the tool to change its behavior even when the web dialog is focused.
  //Run "document.onkeyup=port_key;" to initialize. onkeyup is used to avoid overriding calls to onkeydown already in use in the dialog. onkeypress doesn't fire for modifier keys.
  e = window.event || e;
  keycode = e.keyCode || e.which
   
  //It might be wise to only proceed for certain keys here, e.g. modifier keys or whatever keys are used in the tool.
   
//   window.location='skp:port_key@' + keycode;
}

function setButtonActive(id) {
    $("#" + id).addClass("ui-state-active");
}

function setButtonInactive(id) {
    $("#" + id).removeClass("ui-state-active");
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

function activateButton(id) {
    $("#" + id).addClass("active");
}

function deactivateButton(id) {
    $("#" + id).removeClass("active");
}

function tellSUButton(element) {
    var id = element.id;
    sketchup.button_clicked(id);
}

function setInputEvents() {
    $(':input').each(function() {
        var element = $(this)[0];
        var type = $(this).attr('type');
        if (type === undefined) {
            // It's a <select> if it's undefined
            type = $(this)[0].tagName.toLowerCase();
        }
        if (type === 'button' || type === 'image') {
            var onClickExists = $(this).attr('onclick');
            // Only set if it does not exist
            if (onClickExists === undefined) {
                if (type === 'button') {
                    $(this).click(function () {
                        tellSUButton(element)
                    });
                } else {
                    $(this).click(function () {
                        tellSU(element)
                    });
                }
            }
        } else {
            var onChangeExists = $(this).attr('onchange');
            if (onChangeExists === undefined) {
                if (type === 'checkbox') {
                    $(this).change(function () {
                        tellSUcb(element)
                    });
                } else if(type == 'radio') {
                    var radio_name = $(this).attr('name');
                    $(this).change(function () {
                        tellSU2(radio_name, $(this).val())
                    })
                } else if (type == 'range') {
                    var oninputExists = $(this).attr('oninput');
                    if (oninputExists === undefined) {
                        $(this).change(function() { tellSU(element) });
                    }
                } else {
                    $(this).change(function() { tellSU(element) });
                }
            }
        }
    });
}

function applyEventsToTextbox() {
    var onFocus = function() { $(this).select(); };
    $('input:text').each(function() {
        $(this).off('focus');
        $(this).on('focus', onFocus);
    });
}

function ready() {
    setInputEvents();
    applyEventsToTextbox();
    disableContextMenu();
    disableSelect();
    sketchup.ready();
}