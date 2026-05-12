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
    // https://blog.sentry.io/2016/01/04/client-javascript-reporting-window-onerror#browser-compatibility
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
 * Compatibility shim
 *
 ******************************************************************************/


// Even though minimum requirement for SU2015 is IE9 there is a good number of
// users with Win7 IE8.
if (typeof Date.now === 'undefined') {
  Date.now = function () {
    return new Date();
  }
}

// Shim Vue's transition effects for IE8. This skips any transitions and avoids
// errors that would otherwise prevent the object from changing state.
try {
  if (typeof CSSStyleDeclaration.prototype.transitionDelay === 'undefined') {
    CSSStyleDeclaration.prototype.transitionDelay = '';
    CSSStyleDeclaration.prototype.transitionDuration = '';
    CSSStyleDeclaration.prototype.animationDelay = '';
    CSSStyleDeclaration.prototype.animationDuration = '';
  }
} catch (error) {
  // WebKit will throw a TypeError in recent versions.
  console.log('ignoring error', error);
}

// Shim to work around IE9's missing console.log until developer console has
// been opened.
// http://stackoverflow.com/a/5473193/486990
if (typeof console === "undefined" || typeof console.log === "undefined") {
  console = {};
  console.log = function() {};
}

// https://tc39.github.io/ecma262/#sec-array.prototype.find
if (!Array.prototype.find) {
  Object.defineProperty(Array.prototype, 'find', {
    value: function(predicate) {
     // 1. Let O be ? ToObject(this value).
      if (this == null) {
        throw new TypeError('"this" is null or not defined');
      }

      var o = Object(this);

      // 2. Let len be ? ToLength(? Get(O, "length")).
      var len = o.length >>> 0;

      // 3. If IsCallable(predicate) is false, throw a TypeError exception.
      if (typeof predicate !== 'function') {
        throw new TypeError('predicate must be a function');
      }

      // 4. If thisArg was supplied, let T be thisArg; else let T be undefined.
      var thisArg = arguments[1];

      // 5. Let k be 0.
      var k = 0;

      // 6. Repeat, while k < len
      while (k < len) {
        // a. Let Pk be ! ToString(k).
        // b. Let kValue be ? Get(O, Pk).
        // c. Let testResult be ToBoolean(? Call(predicate, T, « kValue, k, O »)).
        // d. If testResult is true, return kValue.
        var kValue = o[k];
        if (predicate.call(thisArg, kValue, k, o)) {
          return kValue;
        }
        // e. Increase k by 1.
        k++;
      }

      // 7. Return undefined.
      return undefined;
    }
  });
}


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
        // Detect skp: actions and don't intercept them.
        if (this.href.indexOf("skp:") != 0 && this.href.indexOf("http:") == 0) {
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
        Bridge.set_data(data);
        window.location = "skp:callback@" + event_name;
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
  Bridge.init();
  Sketchup.callback("Window.ready");
});
