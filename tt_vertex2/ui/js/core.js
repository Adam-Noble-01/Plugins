/*******************************************************************************
 *
 * Thomas Thomassen
 * thomas[at]thomthom[dot]net
 *
 ******************************************************************************/


window.onerror = function(message, file, line, column, error) {
  try
  {
    // Not all browsers pass along the error object. Without that it's not
    // possible to get full backtrace.
    // http://blog.bugsnag.com/js-stacktraces
    var backtrace = [];
    if (error && error.stack)
    {
      backtrace = String(error.stack).split("\n");
    }
    else
    {
      backtrace = [file + ':' + line + ':' + column];
    }
    var data = {
      'message' : message,
      'backtrace' : backtrace,
      'user-agent': navigator.userAgent,
      'document-mode': document.documentMode
    };
    Sketchup.callback('Window.js_error', data);
  }
  catch (error)
  {
    debugger;
    throw error;
  }
};


/*******************************************************************************
 *
 * module UI
 *
 ******************************************************************************/


var UI = function() {
  return {

    /* Ensure links are opened in the default browser. This ensures that the
     * WebDialog doesn't replace the content with the target URL.
     */
    redirect_links : function() {
      $(document).on('click', 'a[href]', function()
      {
        console.log(`redirect_links`)
        // Detect skp: actions and don't intercept them.
        if (this.href.indexOf("skp:") != 0 && (this.href.indexOf("http:") == 0 || this.href.indexOf("https:") == 0)) {
          console.log(`> Window.open_url ${this.href}`)
          var data = { url : this.href };
          Sketchup.callback('Window.open_url', data);
          return false;
        }
      } );
    },


    /* Disables text selection on elements other than input type elements where
     * it makes sense to allow selections. This mimics native windows.
     */
    disable_select : function() {
      $(document).on('mousedown selectstart', function(e) {
        return $(e.target).is('input, textarea, select, option');
      });
    },


    /* Disables the context menu with the exception for textboxes in order to
     * mimic native windows.
     */
    disable_context_menu : function() {
      $(document).on('contextmenu', function(e) {
        return $(e.target).is('input[type=text], textarea');
      });
    }

  };

}(); // UI


/*******************************************************************************
 *
 * module Sketchup
 *
 ******************************************************************************/


var Sketchup = function() {
  return {

    callback : function(event_name, data) {
      // Defer with a timer in order to allow the UI to update.
      setTimeout(function() {
        // Bridge.set_data(data);
        // window.location = "skp:callback@" + event_name;
        if (data !== undefined) {
          let json_data = JSON.stringify(data);
          sketchup.callback(event_name, json_data);
        } else {
          sketchup.callback(event_name);
        }
      }, 0);
    }

  };

}(); // Sketchup



/*******************************************************************************
 *
 * module Log
 *
 ******************************************************************************/


var Log = function() {
  return {

    debug : function(value) {
      Sketchup.callback('Window.log', { debug: value })
    }

  };

}(); // Log


/*******************************************************************************
 *
 * module Bridge
 *
 ******************************************************************************/


var Bridge = function() {
  return {

    // Creates a hidden textarea element used to pass data from JavaScript to
    // Ruby. Ruby calls UI::WebDialog.get_element_value to fetch the content and
    // parse it as JSON.
    // This avoids many issues in regard to transferring data:
    // * Data can be any size.
    // * Avoid string encoding issues.
    // * Avoid evaluation bug in SketchUp when the string has a single quote.
    init : function() {
      var $bridge = $("<textarea id='SU_BRIDGE'></textarea>");
      $bridge.hide();
      $("body").append($bridge);
    },


    set_data : function(data) {
      var $bridge = $("#SU_BRIDGE");
      $bridge.text("");
      if (data !== undefined) {
        var json = JSON.stringify(data);
        $bridge.text(json);
      }
    }

  };

}(); // UI


/*******************************************************************************
 *
 * initializer
 *
 ******************************************************************************/


$(document).ready(function() {
  // Bridge.init();
  Sketchup.callback("Window.ready");
});
