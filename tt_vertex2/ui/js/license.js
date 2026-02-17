(function e(t,n,r){function s(o,u){if(!n[o]){if(!t[o]){var a=typeof require=="function"&&require;if(!u&&a)return a(o,!0);if(i)return i(o,!0);throw new Error("Cannot find module '"+o+"'")}var f=n[o]={exports:{}};t[o][0].call(f.exports,function(e){var n=t[o][1][e];return s(n?n:e)},f,f.exports,e,t,n,r)}return n[o].exports}var i=typeof require=="function"&&require;for(var o=0;o<r.length;o++)s(r[o]);return s})({1:[function(require,module,exports){
'use strict';

var _vooI18n = require('voo-i18n');

var _vooI18n2 = _interopRequireDefault(_vooI18n);

var _translator = require('./modules/translator.js');

var _translator2 = _interopRequireDefault(_translator);

var _vue_su_error_handler = require('./modules/vue_su_error_handler.js');

var _vue_su_error_handler2 = _interopRequireDefault(_vue_su_error_handler);

var _license = require('./license.vue');

var _license2 = _interopRequireDefault(_license);

function _interopRequireDefault(obj) { return obj && obj.__esModule ? obj : { default: obj }; }

/*******************************************************************************
 *
 * Thomas Thomassen
 * thomas[at]thomthom[dot]net
 *
 ******************************************************************************/

// TODO: Reuse code with license_error.js.
// import Vue from 'vue'
Vue.config.errorHandler = _vue_su_error_handler2.default;

function boot(config) {
  Vue.use(_vooI18n2.default, config.translations);
  Vue.use(_translator2.default);

  var vm = new Vue({
    el: '#app',
    render: function render(h) {
      return h(_license2.default, {
        props: {
          config: config.data
        }
      });
    },
    data: {
      locale: config.locale
    }
  });
  window.app = vm.$children[0];

  UI.disable_select();
  UI.disable_context_menu();
}

// For local debugging in browser.
if (navigator.userAgent.search('SketchUp') < 0) {
  console.log('Debug mode active');
  Sketchup.callback = function (name) {
    console.log(name);
  };
  $(document).ready(function () {
    var now = Math.floor(Date.now() / 1000); // In seconds.
    var days15 = 15 * 24 * 60 * 60;
    var config = {
      translations: {},
      data: {
        product_id: 'TT_Vertex2',
        license: {
          valid: true,
          trial: true,
          expire: now + days15
        },
        server: 'http://www.evilsoftwareempire.local'
      }
    };
    console.log('boot');
    boot(config);
  });
}

/*******************************************************************************
 * External functions for SketchUp
 ******************************************************************************/

window.boot = function (config) {
  boot(config);
};

window.display_license_info = function (license) {
  window.app.license = license;
};
},{"./license.vue":2,"./modules/translator.js":3,"./modules/vue_su_error_handler.js":4,"voo-i18n":42}],2:[function(require,module,exports){
var __vueify_style_dispose__ = require("vueify/lib/insert-css").insert(".fade-enter-active,.fade-leave-active{transition:opacity .3s}.fade-enter,.fade-leave-to{opacity:0}")
;(function(){
'use strict';

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.default = {
  name: 'app',
  props: ['config'],
  data: function data() {
    return {
      licenseKey: "",

      product_id: this.config.product_id,
      license: this.config.license,
      server: this.config.server,

      SLOW_RESPONSE_THRESHOLD: 10000,
      RESPONSE_TIMEOUT: 60000,

      request: {
        waiting: false,
        slow: false,
        error: false
      }
    };
  },
  computed: {
    trialExpired: function trialExpired() {
      var now = Math.floor(Date.now() / 1000);
      return this.license.trial && this.license.expire < now;
    },
    trialDaysLeft: function trialDaysLeft() {
      var now = Math.floor(Date.now() / 1000);
      var seconds_left = this.license.expire - now;
      return Math.floor(seconds_left / 60 / 60 / 24);
    }
  },
  methods: {
    help: function help() {
      Sketchup.callback('Window.help');
    },
    close: function close() {
      Sketchup.callback('Window.close');
    },

    show_slow_reponse_warning: function show_slow_reponse_warning() {
      this.request.slow = true;
    },

    remove_license: function remove_license() {
      Sketchup.callback("LicenseWindow.license_remove");
    },

    check_license: function check_license() {
      console.log('check_license()');

      var host = this.server;
      var api = host + '/api/v1';

      var product_id = this.product_id;
      var key = $.trim($('#license-key').val());

      var request_uri = api + '/license/validate/' + product_id + '/' + key;

      this.request.error = false;
      this.request.waiting = true;

      var timer = setTimeout(this.show_slow_reponse_warning, this.SLOW_RESPONSE_THRESHOLD);

      var app = this;
      $.ajax({
        url: request_uri,
        dataType: "jsonp",
        timeout: this.RESPONSE_TIMEOUT,

        success: function success(data) {
          Sketchup.callback("LicenseWindow.license_check", data);
        }
      }).fail(function (jqXHR, textStatus, errorThrown) {
        app.request.error = true;
        var data = {
          textStatus: textStatus,
          errorThrown: errorThrown,
          timeoutThreshold: app.RESPONSE_TIMEOUT
        };
        Sketchup.callback('Window.log', data);
      }).always(function () {
        clearTimeout(timer);
        app.request.waiting = false;
        app.request.slow = false;
      });
    }

  }
};
})()
if (module.exports.__esModule) module.exports = module.exports.default
var __vue__options__ = (typeof module.exports === "function"? module.exports.options: module.exports)
__vue__options__.render = function render () {var _vm=this;var _h=_vm.$createElement;var _c=_vm._self._c||_h;return _c('div',[_c('h1',[_c('img',{attrs:{"src":"../../Icons/EditVertices.svg","width":"24","height":"24"}}),_vm._v(" "),_c('span',{attrs:{"id":"title"}},[(_vm.license.valid && !_vm.license.trial)?_c('span',[_vm._v("\n        "+_vm._s(_vm.$tr('Licensed'))+"\n      ")]):_c('span',[_vm._v("\n        "+_vm._s(_vm.$tr('Not Licensed'))+"\n      ")])]),_vm._v(" "),_c('transition',{attrs:{"name":"fade"}},[(_vm.trialExpired)?_c('i',[_vm._v("\n        "+_vm._s(_vm.$tr('Trial expired'))+"\n      ")]):_vm._e(),_vm._v(" "),(_vm.license.trial && _vm.trialDaysLeft > 0)?_c('i',[_vm._v("\n        "+_vm._s(_vm.$tr(
            'Trial expire in %{num} day',
            'Trial expire in %{num} days',
            _vm.trialDaysLeft
          ))+"\n      ")]):_vm._e()])],1),_vm._v(" "),_c('div',{attrs:{"id":"content"}},[_c('div',{directives:[{name:"show",rawName:"v-show",value:(_vm.license.trial || !_vm.license.valid),expression:"license.trial || !license.valid"}],staticClass:"page",attrs:{"id":"activate"}},[_c('p',[_c('label',{attrs:{"for":"license-key"}},[_vm._v(_vm._s(_vm.$tr('License Key:')))]),_vm._v(" "),_c('input',{directives:[{name:"model",rawName:"v-model",value:(_vm.licenseKey),expression:"licenseKey"}],attrs:{"type":"text","id":"license-key","placeholder":"XXXX-XXXX-XXXX-XXXX"},domProps:{"value":(_vm.licenseKey)},on:{"input":function($event){if($event.target.composing){ return; }_vm.licenseKey=$event.target.value}}})]),_vm._v(" "),_c('div',{staticClass:"footer"},[_c('button',{attrs:{"id":"action-activate","disabled":_vm.request.waiting || _vm.licenseKey.length === 0},on:{"click":_vm.check_license}},[_vm._v("\n          "+_vm._s(_vm.$tr('Activate'))+"\n        ")])]),_vm._v(" "),_c('transition',{attrs:{"name":"fade"}},[(_vm.request.error)?_c('div',{staticClass:"error-info"},[_c('p',{staticClass:"error"},[_vm._v("\n            "+_vm._s(_vm.$tr('Failed to connect to the license server.'))+"\n          ")]),_vm._v(" "),_c('p',[_vm._v("\n            "+_vm._s(_vm.$tr("\n            Please check if any firewalls are blocking internet connections.\n            "))+"\n          ")]),_vm._v(" "),_c('p',[_vm._v("\n            "+_vm._s(_vm.$tr("\n            You might want to try to connect via VPN as some ISPs have been\n            known to block large IP-ranges that could affect the\n            license server.\n            "))+"\n          ")])]):_vm._e()])],1),_vm._v(" "),_c('div',{directives:[{name:"show",rawName:"v-show",value:(_vm.license.valid && !_vm.license.trial),expression:"license.valid && !license.trial"}],staticClass:"page",attrs:{"id":"deactivate"}},[_vm._m(0),_vm._v(" "),_c('div',{staticClass:"footer"},[_c('button',{attrs:{"id":"action-deactivate"},on:{"click":_vm.remove_license}},[_vm._v("\n          "+_vm._s(_vm.$tr('Deactivate'))+"\n        ")])])]),_vm._v(" "),_c('transition',{attrs:{"name":"fade"}},[(_vm.request.waiting)?_c('div',{attrs:{"id":"overlay"}},[_c('div',[_c('img',{attrs:{"src":"../images/working.gif"}})]),_vm._v(" "),_c('transition',{attrs:{"name":"fade"}},[(_vm.request.slow)?_c('p',[_vm._v("\n            "+_vm._s(_vm.$tr('Server slow to respond… :('))+"\n          ")]):_vm._e()])],1):_vm._e()])],1),_vm._v(" "),_c('div',{attrs:{"id":"footer"}},[_c('button',{on:{"click":_vm.help}},[_vm._v(_vm._s(_vm.$tr('Help')))]),_vm._v(" "),_c('button',{on:{"click":_vm.close}},[_vm._v(_vm._s(_vm.$tr('Close')))])])])}
__vue__options__.staticRenderFns = [function render () {var _vm=this;var _h=_vm.$createElement;var _c=_vm._self._c||_h;return _c('p',[_c('img',{attrs:{"src":"../images/licensed.svg","width":"100"}})])}]

},{"vueify/lib/insert-css":44}],3:[function(require,module,exports){
'use strict';

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.default = {
  install: function install(Vue) {
    // Wrapper around vue-i18n to handle plural selection.
    Vue.prototype.$tr = function (singular, plural, quantity) {
      if (plural) {
        var string = quantity == 1 ? singular : plural;
        string = string.replace('%{num}', '{num}');
        string = string.replace(/ +/g, ' '); // Collapse whitespace
        return this.$t(string, { num: quantity });
      } else {
        var _string = singular.replace(/ +/g, ' '); // Collapse whitespace
        return this.$t(_string);
      }
    };
  }
};
},{}],4:[function(require,module,exports){
'use strict';

Object.defineProperty(exports, "__esModule", {
  value: true
});

exports.default = function (error, vm, info) {
  var data = {
    'message': 'Vue Error (' + info + '): ' + error.message,
    'backtrace': error.backtrace,
    'user-agent': navigator.userAgent,
    'document-mode': document.documentMode
  };
  Sketchup.callback('Window.js_error', data);
  console.error(data.message);
  console.error(error);
};
},{}],5:[function(require,module,exports){
"use strict";

module.exports = { "default": require("core-js/library/fn/object/keys"), __esModule: true };
},{"core-js/library/fn/object/keys":6}],6:[function(require,module,exports){
'use strict';

require('../../modules/es6.object.keys');
module.exports = require('../../modules/_core').Object.keys;
},{"../../modules/_core":11,"../../modules/es6.object.keys":40}],7:[function(require,module,exports){
'use strict';

module.exports = function (it) {
  if (typeof it != 'function') throw TypeError(it + ' is not a function!');
  return it;
};
},{}],8:[function(require,module,exports){
'use strict';

var isObject = require('./_is-object');
module.exports = function (it) {
  if (!isObject(it)) throw TypeError(it + ' is not an object!');
  return it;
};
},{"./_is-object":24}],9:[function(require,module,exports){
'use strict';

// false -> Array#indexOf
// true  -> Array#includes
var toIObject = require('./_to-iobject');
var toLength = require('./_to-length');
var toAbsoluteIndex = require('./_to-absolute-index');
module.exports = function (IS_INCLUDES) {
  return function ($this, el, fromIndex) {
    var O = toIObject($this);
    var length = toLength(O.length);
    var index = toAbsoluteIndex(fromIndex, length);
    var value;
    // Array#includes uses SameValueZero equality algorithm
    // eslint-disable-next-line no-self-compare
    if (IS_INCLUDES && el != el) while (length > index) {
      value = O[index++];
      // eslint-disable-next-line no-self-compare
      if (value != value) return true;
      // Array#indexOf ignores holes, Array#includes - not
    } else for (; length > index; index++) {
      if (IS_INCLUDES || index in O) {
        if (O[index] === el) return IS_INCLUDES || index || 0;
      }
    }return !IS_INCLUDES && -1;
  };
};
},{"./_to-absolute-index":33,"./_to-iobject":35,"./_to-length":36}],10:[function(require,module,exports){
"use strict";

var toString = {}.toString;

module.exports = function (it) {
  return toString.call(it).slice(8, -1);
};
},{}],11:[function(require,module,exports){
'use strict';

var core = module.exports = { version: '2.6.11' };
if (typeof __e == 'number') __e = core; // eslint-disable-line no-undef
},{}],12:[function(require,module,exports){
'use strict';

// optional / simple context binding
var aFunction = require('./_a-function');
module.exports = function (fn, that, length) {
  aFunction(fn);
  if (that === undefined) return fn;
  switch (length) {
    case 1:
      return function (a) {
        return fn.call(that, a);
      };
    case 2:
      return function (a, b) {
        return fn.call(that, a, b);
      };
    case 3:
      return function (a, b, c) {
        return fn.call(that, a, b, c);
      };
  }
  return function () /* ...args */{
    return fn.apply(that, arguments);
  };
};
},{"./_a-function":7}],13:[function(require,module,exports){
"use strict";

// 7.2.1 RequireObjectCoercible(argument)
module.exports = function (it) {
  if (it == undefined) throw TypeError("Can't call method on  " + it);
  return it;
};
},{}],14:[function(require,module,exports){
'use strict';

// Thank's IE8 for his funny defineProperty
module.exports = !require('./_fails')(function () {
  return Object.defineProperty({}, 'a', { get: function get() {
      return 7;
    } }).a != 7;
});
},{"./_fails":18}],15:[function(require,module,exports){
'use strict';

var isObject = require('./_is-object');
var document = require('./_global').document;
// typeof document.createElement is 'object' in old IE
var is = isObject(document) && isObject(document.createElement);
module.exports = function (it) {
  return is ? document.createElement(it) : {};
};
},{"./_global":19,"./_is-object":24}],16:[function(require,module,exports){
'use strict';

// IE 8- don't enum bug keys
module.exports = 'constructor,hasOwnProperty,isPrototypeOf,propertyIsEnumerable,toLocaleString,toString,valueOf'.split(',');
},{}],17:[function(require,module,exports){
'use strict';

var global = require('./_global');
var core = require('./_core');
var ctx = require('./_ctx');
var hide = require('./_hide');
var has = require('./_has');
var PROTOTYPE = 'prototype';

var $export = function $export(type, name, source) {
  var IS_FORCED = type & $export.F;
  var IS_GLOBAL = type & $export.G;
  var IS_STATIC = type & $export.S;
  var IS_PROTO = type & $export.P;
  var IS_BIND = type & $export.B;
  var IS_WRAP = type & $export.W;
  var exports = IS_GLOBAL ? core : core[name] || (core[name] = {});
  var expProto = exports[PROTOTYPE];
  var target = IS_GLOBAL ? global : IS_STATIC ? global[name] : (global[name] || {})[PROTOTYPE];
  var key, own, out;
  if (IS_GLOBAL) source = name;
  for (key in source) {
    // contains in native
    own = !IS_FORCED && target && target[key] !== undefined;
    if (own && has(exports, key)) continue;
    // export native or passed
    out = own ? target[key] : source[key];
    // prevent global pollution for namespaces
    exports[key] = IS_GLOBAL && typeof target[key] != 'function' ? source[key]
    // bind timers to global for call from export context
    : IS_BIND && own ? ctx(out, global)
    // wrap global constructors for prevent change them in library
    : IS_WRAP && target[key] == out ? function (C) {
      var F = function F(a, b, c) {
        if (this instanceof C) {
          switch (arguments.length) {
            case 0:
              return new C();
            case 1:
              return new C(a);
            case 2:
              return new C(a, b);
          }return new C(a, b, c);
        }return C.apply(this, arguments);
      };
      F[PROTOTYPE] = C[PROTOTYPE];
      return F;
      // make static versions for prototype methods
    }(out) : IS_PROTO && typeof out == 'function' ? ctx(Function.call, out) : out;
    // export proto methods to core.%CONSTRUCTOR%.methods.%NAME%
    if (IS_PROTO) {
      (exports.virtual || (exports.virtual = {}))[key] = out;
      // export proto methods to core.%CONSTRUCTOR%.prototype.%NAME%
      if (type & $export.R && expProto && !expProto[key]) hide(expProto, key, out);
    }
  }
};
// type bitmap
$export.F = 1; // forced
$export.G = 2; // global
$export.S = 4; // static
$export.P = 8; // proto
$export.B = 16; // bind
$export.W = 32; // wrap
$export.U = 64; // safe
$export.R = 128; // real proto method for `library`
module.exports = $export;
},{"./_core":11,"./_ctx":12,"./_global":19,"./_has":20,"./_hide":21}],18:[function(require,module,exports){
"use strict";

module.exports = function (exec) {
  try {
    return !!exec();
  } catch (e) {
    return true;
  }
};
},{}],19:[function(require,module,exports){
'use strict';

// https://github.com/zloirock/core-js/issues/86#issuecomment-115759028
var global = module.exports = typeof window != 'undefined' && window.Math == Math ? window : typeof self != 'undefined' && self.Math == Math ? self
// eslint-disable-next-line no-new-func
: Function('return this')();
if (typeof __g == 'number') __g = global; // eslint-disable-line no-undef
},{}],20:[function(require,module,exports){
"use strict";

var hasOwnProperty = {}.hasOwnProperty;
module.exports = function (it, key) {
  return hasOwnProperty.call(it, key);
};
},{}],21:[function(require,module,exports){
'use strict';

var dP = require('./_object-dp');
var createDesc = require('./_property-desc');
module.exports = require('./_descriptors') ? function (object, key, value) {
  return dP.f(object, key, createDesc(1, value));
} : function (object, key, value) {
  object[key] = value;
  return object;
};
},{"./_descriptors":14,"./_object-dp":26,"./_property-desc":30}],22:[function(require,module,exports){
'use strict';

module.exports = !require('./_descriptors') && !require('./_fails')(function () {
  return Object.defineProperty(require('./_dom-create')('div'), 'a', { get: function get() {
      return 7;
    } }).a != 7;
});
},{"./_descriptors":14,"./_dom-create":15,"./_fails":18}],23:[function(require,module,exports){
'use strict';

// fallback for non-array-like ES3 and non-enumerable old V8 strings
var cof = require('./_cof');
// eslint-disable-next-line no-prototype-builtins
module.exports = Object('z').propertyIsEnumerable(0) ? Object : function (it) {
  return cof(it) == 'String' ? it.split('') : Object(it);
};
},{"./_cof":10}],24:[function(require,module,exports){
'use strict';

var _typeof = typeof Symbol === "function" && typeof Symbol.iterator === "symbol" ? function (obj) { return typeof obj; } : function (obj) { return obj && typeof Symbol === "function" && obj.constructor === Symbol && obj !== Symbol.prototype ? "symbol" : typeof obj; };

module.exports = function (it) {
  return (typeof it === 'undefined' ? 'undefined' : _typeof(it)) === 'object' ? it !== null : typeof it === 'function';
};
},{}],25:[function(require,module,exports){
"use strict";

module.exports = true;
},{}],26:[function(require,module,exports){
'use strict';

var anObject = require('./_an-object');
var IE8_DOM_DEFINE = require('./_ie8-dom-define');
var toPrimitive = require('./_to-primitive');
var dP = Object.defineProperty;

exports.f = require('./_descriptors') ? Object.defineProperty : function defineProperty(O, P, Attributes) {
  anObject(O);
  P = toPrimitive(P, true);
  anObject(Attributes);
  if (IE8_DOM_DEFINE) try {
    return dP(O, P, Attributes);
  } catch (e) {/* empty */}
  if ('get' in Attributes || 'set' in Attributes) throw TypeError('Accessors not supported!');
  if ('value' in Attributes) O[P] = Attributes.value;
  return O;
};
},{"./_an-object":8,"./_descriptors":14,"./_ie8-dom-define":22,"./_to-primitive":38}],27:[function(require,module,exports){
'use strict';

var has = require('./_has');
var toIObject = require('./_to-iobject');
var arrayIndexOf = require('./_array-includes')(false);
var IE_PROTO = require('./_shared-key')('IE_PROTO');

module.exports = function (object, names) {
  var O = toIObject(object);
  var i = 0;
  var result = [];
  var key;
  for (key in O) {
    if (key != IE_PROTO) has(O, key) && result.push(key);
  } // Don't enum bug & hidden keys
  while (names.length > i) {
    if (has(O, key = names[i++])) {
      ~arrayIndexOf(result, key) || result.push(key);
    }
  }return result;
};
},{"./_array-includes":9,"./_has":20,"./_shared-key":31,"./_to-iobject":35}],28:[function(require,module,exports){
'use strict';

// 19.1.2.14 / 15.2.3.14 Object.keys(O)
var $keys = require('./_object-keys-internal');
var enumBugKeys = require('./_enum-bug-keys');

module.exports = Object.keys || function keys(O) {
  return $keys(O, enumBugKeys);
};
},{"./_enum-bug-keys":16,"./_object-keys-internal":27}],29:[function(require,module,exports){
'use strict';

// most Object methods by ES6 should accept primitives
var $export = require('./_export');
var core = require('./_core');
var fails = require('./_fails');
module.exports = function (KEY, exec) {
  var fn = (core.Object || {})[KEY] || Object[KEY];
  var exp = {};
  exp[KEY] = exec(fn);
  $export($export.S + $export.F * fails(function () {
    fn(1);
  }), 'Object', exp);
};
},{"./_core":11,"./_export":17,"./_fails":18}],30:[function(require,module,exports){
"use strict";

module.exports = function (bitmap, value) {
  return {
    enumerable: !(bitmap & 1),
    configurable: !(bitmap & 2),
    writable: !(bitmap & 4),
    value: value
  };
};
},{}],31:[function(require,module,exports){
'use strict';

var shared = require('./_shared')('keys');
var uid = require('./_uid');
module.exports = function (key) {
  return shared[key] || (shared[key] = uid(key));
};
},{"./_shared":32,"./_uid":39}],32:[function(require,module,exports){
'use strict';

var core = require('./_core');
var global = require('./_global');
var SHARED = '__core-js_shared__';
var store = global[SHARED] || (global[SHARED] = {});

(module.exports = function (key, value) {
  return store[key] || (store[key] = value !== undefined ? value : {});
})('versions', []).push({
  version: core.version,
  mode: require('./_library') ? 'pure' : 'global',
  copyright: '© 2019 Denis Pushkarev (zloirock.ru)'
});
},{"./_core":11,"./_global":19,"./_library":25}],33:[function(require,module,exports){
'use strict';

var toInteger = require('./_to-integer');
var max = Math.max;
var min = Math.min;
module.exports = function (index, length) {
  index = toInteger(index);
  return index < 0 ? max(index + length, 0) : min(index, length);
};
},{"./_to-integer":34}],34:[function(require,module,exports){
"use strict";

// 7.1.4 ToInteger
var ceil = Math.ceil;
var floor = Math.floor;
module.exports = function (it) {
  return isNaN(it = +it) ? 0 : (it > 0 ? floor : ceil)(it);
};
},{}],35:[function(require,module,exports){
'use strict';

// to indexed object, toObject with fallback for non-array-like ES3 strings
var IObject = require('./_iobject');
var defined = require('./_defined');
module.exports = function (it) {
  return IObject(defined(it));
};
},{"./_defined":13,"./_iobject":23}],36:[function(require,module,exports){
'use strict';

// 7.1.15 ToLength
var toInteger = require('./_to-integer');
var min = Math.min;
module.exports = function (it) {
  return it > 0 ? min(toInteger(it), 0x1fffffffffffff) : 0; // pow(2, 53) - 1 == 9007199254740991
};
},{"./_to-integer":34}],37:[function(require,module,exports){
'use strict';

// 7.1.13 ToObject(argument)
var defined = require('./_defined');
module.exports = function (it) {
  return Object(defined(it));
};
},{"./_defined":13}],38:[function(require,module,exports){
'use strict';

// 7.1.1 ToPrimitive(input [, PreferredType])
var isObject = require('./_is-object');
// instead of the ES6 spec version, we didn't implement @@toPrimitive case
// and the second argument - flag - preferred type is a string
module.exports = function (it, S) {
  if (!isObject(it)) return it;
  var fn, val;
  if (S && typeof (fn = it.toString) == 'function' && !isObject(val = fn.call(it))) return val;
  if (typeof (fn = it.valueOf) == 'function' && !isObject(val = fn.call(it))) return val;
  if (!S && typeof (fn = it.toString) == 'function' && !isObject(val = fn.call(it))) return val;
  throw TypeError("Can't convert object to primitive value");
};
},{"./_is-object":24}],39:[function(require,module,exports){
'use strict';

var id = 0;
var px = Math.random();
module.exports = function (key) {
  return 'Symbol('.concat(key === undefined ? '' : key, ')_', (++id + px).toString(36));
};
},{}],40:[function(require,module,exports){
'use strict';

// 19.1.2.14 Object.keys(O)
var toObject = require('./_to-object');
var $keys = require('./_object-keys');

require('./_object-sap')('keys', function () {
  return function keys(it) {
    return $keys(toObject(it));
  };
});
},{"./_object-keys":28,"./_object-sap":29,"./_to-object":37}],41:[function(require,module,exports){
'use strict';

Object.defineProperty(exports, "__esModule", {
  value: true
});
var replace = exports.replace = function replace(translation) {
  var replacements = arguments.length > 1 && arguments[1] !== undefined ? arguments[1] : {};

  return translation.replace(/\{\w+\}/g, function (placeholder) {
    var key = placeholder.replace('{', '').replace('}', '');

    if (replacements[key] !== undefined) {
      return replacements[key];
    }

    return placeholder;
  });
};
},{}],42:[function(require,module,exports){
'use strict';

Object.defineProperty(exports, "__esModule", {
  value: true
});

var _format = require('./format');

var _translations = require('./translations');

exports.default = {
  install: function install(Vue) {
    var translations = arguments.length > 1 && arguments[1] !== undefined ? arguments[1] : {};


    (0, _translations.set)(translations);

    Vue.directive('locale', {
      params: ['key', 'replace'],

      update: function update(locale) {
        var translated_substrings = this.vm.$t(this.params.key, this.params.replace).split('|');

        var children = this.el.children;

        for (var i = 0; i < children.length; i++) {
          if (translated_substrings[i]) {
            children[i].innerText = translated_substrings[i];
          }
        }
      }
    });

    Vue.prototype.$t = function (key) {
      var replacements = arguments.length > 1 && arguments[1] !== undefined ? arguments[1] : {};

      var locale = replacements['locale'] || this.$root.locale;

      var translation = (0, _translations.fetch)(locale, key);

      return (0, _format.replace)(translation, replacements);
    };

    Vue.filter('translate', function (key) {
      var replacements = arguments.length > 1 && arguments[1] !== undefined ? arguments[1] : {};

      return this.$t(key, replacements);
    });
  }
};
},{"./format":41,"./translations":43}],43:[function(require,module,exports){
(function (global){
'use strict';

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.fetch = exports.set = undefined;

var _keys = require('babel-runtime/core-js/object/keys');

var _keys2 = _interopRequireDefault(_keys);

var _vue = (typeof window !== "undefined" ? window['Vue'] : typeof global !== "undefined" ? global['Vue'] : null);

var _vue2 = _interopRequireDefault(_vue);

function _interopRequireDefault(obj) { return obj && obj.__esModule ? obj : { default: obj }; }

var locale_translations = {
  /*
  'es': {
    'hello': 'hola'
  }
  */
};

var set = exports.set = function set(translations) {
  // we could just assign locale_translations = translations, but
  // I would like to keep locale_translations as a const,
  // therefore set each set of translations manually
  (0, _keys2.default)(translations).forEach(function (locale) {
    locale_translations[locale] = translations[locale];
  });
};

var fetch = exports.fetch = function fetch(locale, key) {
  if (!locale) return key;

  var translations = locale_translations[locale];

  if (translations && key in translations) {
    return translations[key];
  }

  // key not found, fall back from dialect translations

  if (locale.indexOf('_') > -1) {
    return fetch(locale.substr(0, locale.indexOf('_')), key);
  }

  if (locale.indexOf('-') > -1) {
    return fetch(locale.substr(0, locale.indexOf('-')), key);
  }

  // key does not exist

  if (translations && window.console && _vue2.default.config.debug) {
    console.warn('[vue-i18n] Translations exist for the locale \'' + locale + '\', but there is not an entry for \'' + key + '\'');
  }

  return key;
};
}).call(this,typeof self !== "undefined" ? self : typeof window !== "undefined" ? window : {})
},{"babel-runtime/core-js/object/keys":5}],44:[function(require,module,exports){
'use strict';

var inserted = exports.cache = {};

function noop() {}

exports.insert = function (css) {
  if (inserted[css]) return noop;
  inserted[css] = true;

  var elem = document.createElement('style');
  elem.setAttribute('type', 'text/css');

  if ('textContent' in elem) {
    elem.textContent = css;
  } else {
    elem.styleSheet.cssText = css;
  }

  document.getElementsByTagName('head')[0].appendChild(elem);
  return function () {
    document.getElementsByTagName('head')[0].removeChild(elem);
    inserted[css] = false;
  };
};
},{}]},{},[1])