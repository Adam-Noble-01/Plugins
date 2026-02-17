(function e(t,n,r){function s(o,u){if(!n[o]){if(!t[o]){var a=typeof require=="function"&&require;if(!u&&a)return a(o,!0);if(i)return i(o,!0);throw new Error("Cannot find module '"+o+"'")}var f=n[o]={exports:{}};t[o][0].call(f.exports,function(e){var n=t[o][1][e];return s(n?n:e)},f,f.exports,e,t,n,r)}return n[o].exports}var i=typeof require=="function"&&require;for(var o=0;o<r.length;o++)s(r[o]);return s})({1:[function(require,module,exports){
;(function(){
'use strict';

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.default = {
  name: 'tt-button',
  methods: {
    click: function click(e) {
      this.$emit('click', e);
    }
  }
};
})()
if (module.exports.__esModule) module.exports = module.exports.default
var __vue__options__ = (typeof module.exports === "function"? module.exports.options: module.exports)
__vue__options__.render = function render () {var _vm=this;var _h=_vm.$createElement;var _c=_vm._self._c||_h;return _c('button',{staticClass:"btn btn-default btn-sm btn-subd",on:{"click":_vm.click}},[_vm._t("default")],2)}
__vue__options__.staticRenderFns = []

},{}],2:[function(require,module,exports){
;(function(){
'use strict';

Object.defineProperty(exports, "__esModule", {
  value: true
});


var id_counter = 0;
exports.default = {
  name: 'tt-option-checkbox',
  props: ['value'],
  data: function data() {
    return {
      counter: 0
    };
  },
  computed: {
    auto_id: function auto_id() {
      return 'tt-checkbox-' + this.counter;
    }
  },
  created: function created() {
    this.counter = ++id_counter;
  }
};
})()
if (module.exports.__esModule) module.exports = module.exports.default
var __vue__options__ = (typeof module.exports === "function"? module.exports.options: module.exports)
__vue__options__.render = function render () {var _vm=this;var _h=_vm.$createElement;var _c=_vm._self._c||_h;return _c('div',{staticClass:"option checkbox"},[_c('input',{attrs:{"type":"checkbox","id":_vm.auto_id},domProps:{"checked":_vm.value},on:{"change":function($event){return _vm.$emit('input', $event.target.checked)}}}),_vm._v(" "),_c('label',{attrs:{"for":_vm.auto_id}},[_c('span',[_vm._t("default")],2)]),_vm._v(" "),_c('div',{staticClass:"description"},[_vm._t("description")],2)])}
__vue__options__.staticRenderFns = []

},{}],3:[function(require,module,exports){
;(function(){
'use strict';

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.default = {
  name: 'tt-option-header'
};
})()
if (module.exports.__esModule) module.exports = module.exports.default
var __vue__options__ = (typeof module.exports === "function"? module.exports.options: module.exports)
__vue__options__.render = function render () {var _vm=this;var _h=_vm.$createElement;var _c=_vm._self._c||_h;return _c('h5',{staticClass:"header-option"},[_vm._t("default")],2)}
__vue__options__.staticRenderFns = []

},{}],4:[function(require,module,exports){
;(function(){
'use strict';

Object.defineProperty(exports, "__esModule", {
  value: true
});


var id_counter = 0;
exports.default = {
  name: 'tt-option-numberbox',
  props: {
    value: { default: 0, type: Number },
    min: { default: undefined, type: Number },
    max: { default: undefined, type: Number }
  },
  data: function data() {
    return {
      counter: 0
    };
  },
  computed: {
    auto_id: function auto_id() {
      return 'tt-numberbox-' + this.counter;
    }
  },
  methods: {
    validate: function validate(event) {
      if (this.min !== undefined && this.value < this.min) {
        this.$emit('input', this.min);
      }
      if (this.max !== undefined && this.value > this.max) {
        this.$emit('input', this.max);
      }
    }
  },
  created: function created() {
    this.counter = ++id_counter;
  }
};
})()
if (module.exports.__esModule) module.exports = module.exports.default
var __vue__options__ = (typeof module.exports === "function"? module.exports.options: module.exports)
__vue__options__.render = function render () {var _vm=this;var _h=_vm.$createElement;var _c=_vm._self._c||_h;return _c('div',{staticClass:"option form-group"},[_c('label',{attrs:{"for":_vm.auto_id}},[_c('span',[_vm._t("default")],2)]),_vm._v(" "),_c('input',{staticClass:"form-control",attrs:{"type":"number","id":_vm.auto_id,"min":_vm.min,"max":_vm.max},domProps:{"value":_vm.value},on:{"input":function($event){_vm.$emit('input', parseFloat($event.target.value))},"blur":_vm.validate}}),_vm._v(" "),_c('div',{staticClass:"description"},[_vm._t("description")],2)])}
__vue__options__.staticRenderFns = []

},{}],5:[function(require,module,exports){
;(function(){
'use strict';

Object.defineProperty(exports, "__esModule", {
  value: true
});


var id_counter = 0;
exports.default = {
  name: 'tt-option-select',
  props: ['value'],
  data: function data() {
    return {
      counter: 0
    };
  },
  computed: {
    auto_id: function auto_id() {
      return 'tt-select-' + this.counter;
    }
  },
  created: function created() {
    this.counter = ++id_counter;
  }
};
})()
if (module.exports.__esModule) module.exports = module.exports.default
var __vue__options__ = (typeof module.exports === "function"? module.exports.options: module.exports)
__vue__options__.render = function render () {var _vm=this;var _h=_vm.$createElement;var _c=_vm._self._c||_h;return _c('div',{staticClass:"option form-group"},[_c('label',{attrs:{"for":_vm.auto_id}},[_vm._t("label")],2),_vm._v(" "),_c('select',{staticClass:"form-control",attrs:{"id":_vm.auto_id},domProps:{"value":_vm.value},on:{"change":function($event){return _vm.$emit('input', $event.target.value)}}},[_vm._t("default")],2),_vm._v(" "),_c('div',{staticClass:"description"},[_vm._t("description")],2)])}
__vue__options__.staticRenderFns = []

},{}],6:[function(require,module,exports){
'use strict';

var _vooI18n = require('voo-i18n');

var _vooI18n2 = _interopRequireDefault(_vooI18n);

var _translator = require('./modules/translator.js');

var _translator2 = _interopRequireDefault(_translator);

var _vue_su_error_handler = require('./modules/vue_su_error_handler.js');

var _vue_su_error_handler2 = _interopRequireDefault(_vue_su_error_handler);

var _preferences = require('./preferences.vue');

var _preferences2 = _interopRequireDefault(_preferences);

function _interopRequireDefault(obj) { return obj && obj.__esModule ? obj : { default: obj }; }

/*******************************************************************************
 *
 * Thomas Thomassen
 * thomas[at]thomthom[dot]net
 *
 ******************************************************************************/

// import Vue from 'vue'
Vue.config.errorHandler = _vue_su_error_handler2.default;

function boot(config) {
  Log.debug('Booting...');
  var debug_data = {
    'user-agent': navigator.userAgent,
    'document-mode': document.documentMode,
    'document-compatMode': document.compatMode
  };
  Log.debug(debug_data);
  Log.debug(config);

  Vue.use(_vooI18n2.default, config.translations);
  Vue.use(_translator2.default);

  Log.debug('Creating Vue instance...');
  var vm = new Vue({
    el: '#app',
    // https://vuejs.org/v2/guide/render-function#JSX
    // Aliasing createElement to h is a common convention you’ll see in the Vue
    // ecosystem and is actually required for JSX. If h is not available in the
    // scope, your app will throw an error.
    render: function render(h) {
      return h(_preferences2.default, {
        props: {
          config: config
        }
      });
    },
    data: {
      locale: config.options.locale
    }
  });
  window.app = vm.$children[0];

  Log.debug('Disabling select and context menu...');
  UI.disable_select();
  UI.disable_context_menu();

  Sketchup.callback("Preferences.ready");
}

// For local debugging in browser.
if (navigator.userAgent.search('SketchUp') < 0) {
  console.log('Debug mode active');
  console.log('Monkey patching...');
  Sketchup.callback = function (event_name, data) {
    var formatted_data = JSON.stringify(data);
    console.log('Sketchup.callback', event_name, formatted_data);
  };
  console.log('Faking boot...');
  $(document).ready(function () {
    var config = {
      translations: {
        'no': {
          'Modelling': 'Modellering',
          'Tools': 'Verktøy',
          'Display': 'Skjerm'
        }
      },
      language_list: [{
        code: 'en',
        metadata: {
          author: 'The Empire',
          contact: 'evil@empire.com',
          language: 'English'
        }
      }, {
        code: 'no',
        metadata: {
          author: 'ThomThom',
          contact: 'http://www.thomthom.net/',
          language: 'Norsk'
        }
      }],
      tools: [{ id: 'LAST_TOOL_USED', name: 'Last Used' }, { id: 'T_Select', name: 'Select' }, { id: 'T_Select_Rectangle', name: 'Select Rectangle' }, { id: 'T_Select_Circle', name: 'Select Circle' }, { id: 'T_Select_Freehand', name: 'Select Freehand' }, { id: 'T_Select_Polygon', name: 'Select Polygon' }, { id: 'T_Move', name: 'Move' }, { id: 'T_Scale', name: 'Scale' }, { id: 'T_Rotate', name: 'Rotate' }, { id: 'T_InsertVertex', name: 'Insert Vertex' }],
      options: {
        locale: 'no',
        initial_tool: 'LAST_TOOL_USED',
        vertex_size: 6,
        normal_size: 20,
        context_menu: true
      }
    };
    console.log('boot', config);
    boot(config);
  });
}

/*******************************************************************************
 * External functions for SketchUp
 ******************************************************************************/

window.boot = function (config) {
  boot(config);
};

window.update_language_list = function (locales) {
  window.app.locales = locales;
};

window.update_options = function (options) {
  window.app.options = options;
};
},{"./modules/translator.js":7,"./modules/vue_su_error_handler.js":8,"./preferences.vue":9,"voo-i18n":47}],7:[function(require,module,exports){
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
},{}],8:[function(require,module,exports){
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
},{}],9:[function(require,module,exports){
;(function(){
'use strict';

Object.defineProperty(exports, "__esModule", {
  value: true
});

var _optionHeader = require('./components/option-header.vue');

var _optionHeader2 = _interopRequireDefault(_optionHeader);

var _optionCheckbox = require('./components/option-checkbox.vue');

var _optionCheckbox2 = _interopRequireDefault(_optionCheckbox);

var _optionNumberbox = require('./components/option-numberbox.vue');

var _optionNumberbox2 = _interopRequireDefault(_optionNumberbox);

var _optionSelect = require('./components/option-select.vue');

var _optionSelect2 = _interopRequireDefault(_optionSelect);

var _button = require('./components/button.vue');

var _button2 = _interopRequireDefault(_button);

function _interopRequireDefault(obj) { return obj && obj.__esModule ? obj : { default: obj }; }

function sketchup_info() {
  var sketchup_pattern = /SketchUp(?: ([^\/]+))?\/([0-9.]+)/i;
  var matches = navigator.userAgent.match(sketchup_pattern);
  if (matches) {
    return {
      product: matches[1],
      version: parseInt(matches[2])
    };
  }
  return {
    product: null,
    version: 0
  };
}

exports.default = {
  name: 'app',
  props: ['config'],
  components: {
    'tt-option-header': _optionHeader2.default,
    'tt-option-checkbox': _optionCheckbox2.default,
    'tt-option-numberbox': _optionNumberbox2.default,
    'tt-option-select': _optionSelect2.default,
    'tt-button': _button2.default
  },
  data: function data() {
    return {
      options: this.config.options,
      locales: this.config.language_list,
      tools: this.config.tools
    };
  },
  computed: {
    current_language: function current_language() {
      var code = this.options.locale;
      return this.locales.find(function (element, index) {
        return element.code.toUpperCase() == code.toUpperCase();
      });
    }
  },
  methods: {
    save: function save() {
      Sketchup.callback('Preferences.save', this.options);
    },
    cancel: function cancel() {
      Sketchup.callback('Preferences.cancel');
    }
  }
};
})()
if (module.exports.__esModule) module.exports = module.exports.default
var __vue__options__ = (typeof module.exports === "function"? module.exports.options: module.exports)
__vue__options__.render = function render () {var _vm=this;var _h=_vm.$createElement;var _c=_vm._self._c||_h;return _c('div',[_c('div',{staticClass:"container"},[_c('tt-option-header',[_vm._v(_vm._s(_vm.$tr('User Interface')))]),_vm._v(" "),_c('tt-option-select',{model:{value:(_vm.options.locale),callback:function ($$v) {_vm.$set(_vm.options, "locale", $$v)},expression:"options.locale"}},[_c('span',{attrs:{"slot":"label"},slot:"label"},[_vm._v(_vm._s(_vm.$tr('Language')))]),_vm._v(" "),_vm._l((_vm.locales),function(locale){return _c('option',{key:locale.code,domProps:{"value":locale.code}},[_vm._v("\n        "+_vm._s(locale.metadata.language)+"\n      ")])}),_vm._v(" "),_c('p',{attrs:{"slot":"description"},slot:"description"},[_vm._v("\n        "+_vm._s(_vm.$tr('Author:'))+"\n        "),(_vm.current_language.metadata.contact.lastIndexOf('http', 0) === 0)?_c('a',{attrs:{"href":_vm.current_language.metadata.contact}},[_vm._v("\n          "+_vm._s(_vm.current_language.metadata.author)+"\n        ")]):_c('span',{attrs:{"title":_vm.current_language.metadata.contact}},[_vm._v("\n          "+_vm._s(_vm.current_language.metadata.author)+"\n        ")])])],2),_vm._v(" "),_c('p',{staticClass:"note"},[_c('span',{staticClass:"glyphicon glyphicon-info-sign",attrs:{"aria-hidden":"true"}}),_vm._v(" "),_c('span',{staticClass:"localize"},[_vm._v("\n        "+_vm._s(_vm.$tr('Language options require restart of SketchUp for changes to take effect.'))+"\n      ")])]),_vm._v(" "),_c('hr',{staticClass:"hr-sm"}),_vm._v(" "),_c('tt-option-select',{model:{value:(_vm.options.initial_tool),callback:function ($$v) {_vm.$set(_vm.options, "initial_tool", $$v)},expression:"options.initial_tool"}},[_c('span',{attrs:{"slot":"label"},slot:"label"},[_vm._v(_vm._s(_vm.$tr('Initial Tool')))]),_vm._v(" "),_vm._l((_vm.tools),function(tool){return _c('option',{key:tool.id,domProps:{"value":tool.id}},[_vm._v("\n        "+_vm._s(tool.name)+"\n      ")])}),_vm._v(" "),_c('p',{attrs:{"slot":"description"},slot:"description"},[_vm._v("\n        "+_vm._s(_vm.$tr('Customize the tool that should be active when vertex mode is activated.'))+"\n      ")])],2),_vm._v(" "),_c('hr',{staticClass:"hr-sm"}),_vm._v(" "),_c('tt-option-numberbox',{attrs:{"min":4,"max":10},model:{value:(_vm.options.vertex_size),callback:function ($$v) {_vm.$set(_vm.options, "vertex_size", $$v)},expression:"options.vertex_size"}},[_vm._v("\n      "+_vm._s(_vm.$tr('Vertex Size (px)'))+"\n      "),_c('div',{attrs:{"slot":"description"},slot:"description"},[_vm._v("\n        "+_vm._s(_vm.$tr('Customize the size of vertices in the viewport.'))+"\n      ")])]),_vm._v(" "),_c('tt-option-numberbox',{attrs:{"min":4,"max":50},model:{value:(_vm.options.normal_size),callback:function ($$v) {_vm.$set(_vm.options, "normal_size", $$v)},expression:"options.normal_size"}},[_vm._v("\n      "+_vm._s(_vm.$tr('Normal Size (px)'))+"\n      "),_c('div',{attrs:{"slot":"description"},slot:"description"},[_vm._v("\n        "+_vm._s(_vm.$tr('Customize the size of vertex normals in the viewport.'))+"\n      ")])]),_vm._v(" "),_c('hr',{staticClass:"hr-sm"}),_vm._v(" "),_c('tt-option-checkbox',{model:{value:(_vm.options.context_menu),callback:function ($$v) {_vm.$set(_vm.options, "context_menu", $$v)},expression:"options.context_menu"}},[_vm._v("\n      "+_vm._s(_vm.$tr('Context Menu'))+"\n      "),_c('div',{attrs:{"slot":"description"},slot:"description"},[_vm._v("\n        "+_vm._s(_vm.$tr('Toggle to add Vertex Tools to the SketchUp context menu for quick access when right clicking in the viewport.'))+"\n      ")])])],1),_vm._v(" "),_c('div',{staticClass:"footer"},[_c('tt-button',{on:{"click":_vm.cancel}},[_vm._v(_vm._s(_vm.$tr('Cancel')))]),_vm._v(" "),_c('tt-button',{on:{"click":_vm.save}},[_vm._v(_vm._s(_vm.$tr('Save')))])],1)])}
__vue__options__.staticRenderFns = []

},{"./components/button.vue":1,"./components/option-checkbox.vue":2,"./components/option-header.vue":3,"./components/option-numberbox.vue":4,"./components/option-select.vue":5}],10:[function(require,module,exports){
"use strict";

module.exports = { "default": require("core-js/library/fn/object/keys"), __esModule: true };
},{"core-js/library/fn/object/keys":11}],11:[function(require,module,exports){
'use strict';

require('../../modules/es6.object.keys');
module.exports = require('../../modules/_core').Object.keys;
},{"../../modules/_core":16,"../../modules/es6.object.keys":45}],12:[function(require,module,exports){
'use strict';

module.exports = function (it) {
  if (typeof it != 'function') throw TypeError(it + ' is not a function!');
  return it;
};
},{}],13:[function(require,module,exports){
'use strict';

var isObject = require('./_is-object');
module.exports = function (it) {
  if (!isObject(it)) throw TypeError(it + ' is not an object!');
  return it;
};
},{"./_is-object":29}],14:[function(require,module,exports){
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
},{"./_to-absolute-index":38,"./_to-iobject":40,"./_to-length":41}],15:[function(require,module,exports){
"use strict";

var toString = {}.toString;

module.exports = function (it) {
  return toString.call(it).slice(8, -1);
};
},{}],16:[function(require,module,exports){
'use strict';

var core = module.exports = { version: '2.6.11' };
if (typeof __e == 'number') __e = core; // eslint-disable-line no-undef
},{}],17:[function(require,module,exports){
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
},{"./_a-function":12}],18:[function(require,module,exports){
"use strict";

// 7.2.1 RequireObjectCoercible(argument)
module.exports = function (it) {
  if (it == undefined) throw TypeError("Can't call method on  " + it);
  return it;
};
},{}],19:[function(require,module,exports){
'use strict';

// Thank's IE8 for his funny defineProperty
module.exports = !require('./_fails')(function () {
  return Object.defineProperty({}, 'a', { get: function get() {
      return 7;
    } }).a != 7;
});
},{"./_fails":23}],20:[function(require,module,exports){
'use strict';

var isObject = require('./_is-object');
var document = require('./_global').document;
// typeof document.createElement is 'object' in old IE
var is = isObject(document) && isObject(document.createElement);
module.exports = function (it) {
  return is ? document.createElement(it) : {};
};
},{"./_global":24,"./_is-object":29}],21:[function(require,module,exports){
'use strict';

// IE 8- don't enum bug keys
module.exports = 'constructor,hasOwnProperty,isPrototypeOf,propertyIsEnumerable,toLocaleString,toString,valueOf'.split(',');
},{}],22:[function(require,module,exports){
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
},{"./_core":16,"./_ctx":17,"./_global":24,"./_has":25,"./_hide":26}],23:[function(require,module,exports){
"use strict";

module.exports = function (exec) {
  try {
    return !!exec();
  } catch (e) {
    return true;
  }
};
},{}],24:[function(require,module,exports){
'use strict';

// https://github.com/zloirock/core-js/issues/86#issuecomment-115759028
var global = module.exports = typeof window != 'undefined' && window.Math == Math ? window : typeof self != 'undefined' && self.Math == Math ? self
// eslint-disable-next-line no-new-func
: Function('return this')();
if (typeof __g == 'number') __g = global; // eslint-disable-line no-undef
},{}],25:[function(require,module,exports){
"use strict";

var hasOwnProperty = {}.hasOwnProperty;
module.exports = function (it, key) {
  return hasOwnProperty.call(it, key);
};
},{}],26:[function(require,module,exports){
'use strict';

var dP = require('./_object-dp');
var createDesc = require('./_property-desc');
module.exports = require('./_descriptors') ? function (object, key, value) {
  return dP.f(object, key, createDesc(1, value));
} : function (object, key, value) {
  object[key] = value;
  return object;
};
},{"./_descriptors":19,"./_object-dp":31,"./_property-desc":35}],27:[function(require,module,exports){
'use strict';

module.exports = !require('./_descriptors') && !require('./_fails')(function () {
  return Object.defineProperty(require('./_dom-create')('div'), 'a', { get: function get() {
      return 7;
    } }).a != 7;
});
},{"./_descriptors":19,"./_dom-create":20,"./_fails":23}],28:[function(require,module,exports){
'use strict';

// fallback for non-array-like ES3 and non-enumerable old V8 strings
var cof = require('./_cof');
// eslint-disable-next-line no-prototype-builtins
module.exports = Object('z').propertyIsEnumerable(0) ? Object : function (it) {
  return cof(it) == 'String' ? it.split('') : Object(it);
};
},{"./_cof":15}],29:[function(require,module,exports){
'use strict';

var _typeof = typeof Symbol === "function" && typeof Symbol.iterator === "symbol" ? function (obj) { return typeof obj; } : function (obj) { return obj && typeof Symbol === "function" && obj.constructor === Symbol && obj !== Symbol.prototype ? "symbol" : typeof obj; };

module.exports = function (it) {
  return (typeof it === 'undefined' ? 'undefined' : _typeof(it)) === 'object' ? it !== null : typeof it === 'function';
};
},{}],30:[function(require,module,exports){
"use strict";

module.exports = true;
},{}],31:[function(require,module,exports){
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
},{"./_an-object":13,"./_descriptors":19,"./_ie8-dom-define":27,"./_to-primitive":43}],32:[function(require,module,exports){
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
},{"./_array-includes":14,"./_has":25,"./_shared-key":36,"./_to-iobject":40}],33:[function(require,module,exports){
'use strict';

// 19.1.2.14 / 15.2.3.14 Object.keys(O)
var $keys = require('./_object-keys-internal');
var enumBugKeys = require('./_enum-bug-keys');

module.exports = Object.keys || function keys(O) {
  return $keys(O, enumBugKeys);
};
},{"./_enum-bug-keys":21,"./_object-keys-internal":32}],34:[function(require,module,exports){
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
},{"./_core":16,"./_export":22,"./_fails":23}],35:[function(require,module,exports){
"use strict";

module.exports = function (bitmap, value) {
  return {
    enumerable: !(bitmap & 1),
    configurable: !(bitmap & 2),
    writable: !(bitmap & 4),
    value: value
  };
};
},{}],36:[function(require,module,exports){
'use strict';

var shared = require('./_shared')('keys');
var uid = require('./_uid');
module.exports = function (key) {
  return shared[key] || (shared[key] = uid(key));
};
},{"./_shared":37,"./_uid":44}],37:[function(require,module,exports){
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
},{"./_core":16,"./_global":24,"./_library":30}],38:[function(require,module,exports){
'use strict';

var toInteger = require('./_to-integer');
var max = Math.max;
var min = Math.min;
module.exports = function (index, length) {
  index = toInteger(index);
  return index < 0 ? max(index + length, 0) : min(index, length);
};
},{"./_to-integer":39}],39:[function(require,module,exports){
"use strict";

// 7.1.4 ToInteger
var ceil = Math.ceil;
var floor = Math.floor;
module.exports = function (it) {
  return isNaN(it = +it) ? 0 : (it > 0 ? floor : ceil)(it);
};
},{}],40:[function(require,module,exports){
'use strict';

// to indexed object, toObject with fallback for non-array-like ES3 strings
var IObject = require('./_iobject');
var defined = require('./_defined');
module.exports = function (it) {
  return IObject(defined(it));
};
},{"./_defined":18,"./_iobject":28}],41:[function(require,module,exports){
'use strict';

// 7.1.15 ToLength
var toInteger = require('./_to-integer');
var min = Math.min;
module.exports = function (it) {
  return it > 0 ? min(toInteger(it), 0x1fffffffffffff) : 0; // pow(2, 53) - 1 == 9007199254740991
};
},{"./_to-integer":39}],42:[function(require,module,exports){
'use strict';

// 7.1.13 ToObject(argument)
var defined = require('./_defined');
module.exports = function (it) {
  return Object(defined(it));
};
},{"./_defined":18}],43:[function(require,module,exports){
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
},{"./_is-object":29}],44:[function(require,module,exports){
'use strict';

var id = 0;
var px = Math.random();
module.exports = function (key) {
  return 'Symbol('.concat(key === undefined ? '' : key, ')_', (++id + px).toString(36));
};
},{}],45:[function(require,module,exports){
'use strict';

// 19.1.2.14 Object.keys(O)
var toObject = require('./_to-object');
var $keys = require('./_object-keys');

require('./_object-sap')('keys', function () {
  return function keys(it) {
    return $keys(toObject(it));
  };
});
},{"./_object-keys":33,"./_object-sap":34,"./_to-object":42}],46:[function(require,module,exports){
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
},{}],47:[function(require,module,exports){
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
},{"./format":46,"./translations":48}],48:[function(require,module,exports){
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
},{"babel-runtime/core-js/object/keys":10}]},{},[6])