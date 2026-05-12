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
  name: 'tt-option-header',
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
  name: 'tt-option-group',
  props: {
    vertical: {
      type: Boolean,
      default: false
    }
  },
  computed: {
    classObject: function classObject() {
      return {
        'btn-group-vertical': this.vertical,
        'btn-block': this.vertical,
        'btn-group': !this.vertical,
        'btn-group-justified': !this.vertical
      };
    }
  }
};
})()
if (module.exports.__esModule) module.exports = module.exports.default
var __vue__options__ = (typeof module.exports === "function"? module.exports.options: module.exports)
__vue__options__.render = function render () {var _vm=this;var _h=_vm.$createElement;var _c=_vm._self._c||_h;return _c('div',{staticClass:"option",class:_vm.classObject},[_vm._t("default")],2)}
__vue__options__.staticRenderFns = []

},{}],4:[function(require,module,exports){
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

},{}],5:[function(require,module,exports){
;(function(){
'use strict';

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.default = {
  name: 'tt-option-radio',
  props: {
    option: Number,
    value: Number,
    title: null
  }
};
})()
if (module.exports.__esModule) module.exports = module.exports.default
var __vue__options__ = (typeof module.exports === "function"? module.exports.options: module.exports)
__vue__options__.render = function render () {var _vm=this;var _h=_vm.$createElement;var _c=_vm._self._c||_h;return _c('label',{staticClass:"btn btn-default btn-sm btn-subd",class:{ active: _vm.option == _vm.value },attrs:{"title":_vm.title},on:{"click":function($event){return _vm.$emit('input', _vm.option)}}},[_vm._t("default")],2)}
__vue__options__.staticRenderFns = []

},{}],6:[function(require,module,exports){
;(function(){
'use strict';

Object.defineProperty(exports, "__esModule", {
  value: true
});

var _optionHeader = require('./components/option-header.vue');

var _optionHeader2 = _interopRequireDefault(_optionHeader);

var _optionGroup = require('./components/option-group.vue');

var _optionGroup2 = _interopRequireDefault(_optionGroup);

var _optionCheckbox = require('./components/option-checkbox.vue');

var _optionCheckbox2 = _interopRequireDefault(_optionCheckbox);

var _optionRadio = require('./components/option-radio.vue');

var _optionRadio2 = _interopRequireDefault(_optionRadio);

var _button = require('./components/button.vue');

var _button2 = _interopRequireDefault(_button);

function _interopRequireDefault(obj) { return obj && obj.__esModule ? obj : { default: obj }; }

exports.default = {
  name: 'app',
  props: ['config'],
  components: {
    'tt-option-header': _optionHeader2.default,
    'tt-option-group': _optionGroup2.default,
    'tt-option-checkbox': _optionCheckbox2.default,
    'tt-option-radio': _optionRadio2.default,
    'tt-button': _button2.default
  },
  data: function data() {
    return {
      disable_updates: false,
      selection: {
        description: "",
        have_mesh: false
      },
      options: {
        subdivided: true,
        subdivisions: 1,
        scheme: 1,
        boundary: 1,
        fvar_interpolation: 5,
        edge_visibility: 1,
        triangle_subdivision: false,
        creasing: false
      }
    };
  },
  methods: {
    disable_notifications: function disable_notifications(callback) {
      this.disable_updates = true;
      callback(this);
      var vm = this;

      Vue.nextTick(function () {
        vm.disable_updates = false;
      });
    },
    update_mesh: function update_mesh(mesh) {
      this.disable_notifications(function (vm) {
        vm.options = mesh;
      });
    },
    reset_mesh: function reset_mesh() {
      this.disable_notifications(function (vm) {
        vm.options.subdivided = false;
      });
    },
    notify_update: function notify_update(notification, data) {
      if (!this.disable_updates) {
        Sketchup.callback(notification, data);
      }
    },
    su_log: function su_log(message) {
      Sketchup.callback("Window.log", { message: message });
    },

    on_subdivisions_change: function on_subdivisions_change(event, ui) {
      if (this.options.subdivisions == ui.value) return;

      this.options.subdivisions = ui.value;
      var data = { value: ui.value };
      this.notify_update("EntityInfo.subdivisions_change", data);
    },
    optionWatcher: function optionWatcher(key, newVal, oldVal) {
      var data = {
        option: key,
        value: Number(newVal)
      };
      this.notify_update("EntityInfo.option_change", data);
    }
  },
  mounted: function mounted() {
    $("#subdivisions_slider").slider({
      min: 1,
      max: 4,
      change: this.on_subdivisions_change
    });
    this.$watch('options.subdivisions', function (newVal, oldVal) {
      $("#subdivisions_slider").slider({ value: newVal });
    });
  },
  created: function created() {
    var _this = this;

    var _loop = function _loop(k) {
      if (k == 'subdivisions' || k == 'subdivided') return 'continue';
      _this.$watch('options.' + k, function (newVal, oldVal) {
        return _this.optionWatcher(k, newVal, oldVal);
      });
    };

    for (var k in this.options) {
      var _ret = _loop(k);

      if (_ret === 'continue') continue;
    }
    var app = this;
    this.$watch('options.subdivided', function (newVal, oldVal) {
      var data = { enabled: newVal };
      app.notify_update("EntityInfo.subdivisions_enabled_change", data);
    });
  }
};
})()
if (module.exports.__esModule) module.exports = module.exports.default
var __vue__options__ = (typeof module.exports === "function"? module.exports.options: module.exports)
__vue__options__.render = function render () {var _vm=this;var _h=_vm.$createElement;var _c=_vm._self._c||_h;return _c('div',[_c('div',{staticClass:"container"},[_c('h5',[_c('b',[(_vm.selection.description.length == 0)?_c('span',[_vm._v("\r\n        "+_vm._s(_vm.$tr('Nothing Selected'))+"\r\n      ")]):_c('span',[_vm._v("\r\n        "+_vm._s(_vm.selection.description)+"\r\n      ")])])]),_vm._v(" "),_c('hr',{staticClass:"hr-sm"}),_vm._v(" "),_c('div',{directives:[{name:"show",rawName:"v-show",value:(_vm.selection.description.length > 0),expression:"selection.description.length > 0"}],attrs:{"id":"subdivisions"}},[_c('h5',{staticClass:"header-option"},[_vm._v(_vm._s(_vm.$tr('Subdivisions')))]),_vm._v(" "),_c('button',{staticClass:"btn btn-primary btn-block",class:{active: _vm.options.subdivided},attrs:{"type":"button"},on:{"click":function($event){_vm.options.subdivided = !_vm.options.subdivided}}},[_vm._v("\r\n        "+_vm._s(_vm.$tr('Subdivided'))+"\r\n      ")]),_vm._v(" "),_c('div',{directives:[{name:"show",rawName:"v-show",value:(_vm.selection.have_mesh),expression:"selection.have_mesh"}]},[_c('div',{attrs:{"id":"subdivisions_slider"}}),_vm._v(" "),_vm._m(0),_vm._v(" "),_c('div',{attrs:{"id":"subdivisions_iterations"}},[_vm._v("\r\n          "+_vm._s(_vm.$tr('%{num} Iteration', '%{num} Iterations', _vm.options.subdivisions))+"\r\n        ")])]),_vm._v(" "),_c('div',{directives:[{name:"show",rawName:"v-show",value:(_vm.selection.have_mesh),expression:"selection.have_mesh"}],attrs:{"id":"options"}},[_c('hr',{staticClass:"hr-sm"}),_vm._v(" "),_c('tt-option-header',[_vm._v(_vm._s(_vm.$tr('Mesh Smoothing')))]),_vm._v(" "),_c('tt-option-group',[_c('tt-option-radio',{attrs:{"title":"Bilinear","option":0},model:{value:(_vm.options.scheme),callback:function ($$v) {_vm.$set(_vm.options, "scheme", $$v)},expression:"options.scheme"}},[_vm._v("\r\n            "+_vm._s(_vm.$tr('None'))+"\r\n          ")]),_vm._v(" "),_c('tt-option-radio',{attrs:{"title":"Catmull-Clark","option":1},model:{value:(_vm.options.scheme),callback:function ($$v) {_vm.$set(_vm.options, "scheme", $$v)},expression:"options.scheme"}},[_vm._v("\r\n            "+_vm._s(_vm.$tr('Quads'))+"\r\n          ")])],1),_vm._v(" "),_c('hr',{staticClass:"hr-sm"}),_vm._v(" "),_c('tt-option-header',[_vm._v(_vm._s(_vm.$tr('Boundary Corners')))]),_vm._v(" "),_c('tt-option-group',[_c('tt-option-radio',{attrs:{"option":1},model:{value:(_vm.options.boundary),callback:function ($$v) {_vm.$set(_vm.options, "boundary", $$v)},expression:"options.boundary"}},[_vm._v("\r\n            "+_vm._s(_vm.$tr('Smooth'))+"\r\n          ")]),_vm._v(" "),_c('tt-option-radio',{attrs:{"option":2},model:{value:(_vm.options.boundary),callback:function ($$v) {_vm.$set(_vm.options, "boundary", $$v)},expression:"options.boundary"}},[_vm._v("\r\n            "+_vm._s(_vm.$tr('Sharp'))+"\r\n          ")])],1),_vm._v(" "),_c('hr',{staticClass:"hr-sm"}),_vm._v(" "),_c('tt-option-header',[_vm._v(_vm._s(_vm.$tr('UV Interpolation')))]),_vm._v(" "),_c('tt-option-group',{attrs:{"vertical":""}},[_c('tt-option-radio',{attrs:{"option":0},model:{value:(_vm.options.fvar_interpolation),callback:function ($$v) {_vm.$set(_vm.options, "fvar_interpolation", $$v)},expression:"options.fvar_interpolation"}},[_vm._v("\r\n            "+_vm._s(_vm.$tr('All Smooth'))+"\r\n          ")]),_vm._v(" "),_c('tt-option-radio',{attrs:{"option":1},model:{value:(_vm.options.fvar_interpolation),callback:function ($$v) {_vm.$set(_vm.options, "fvar_interpolation", $$v)},expression:"options.fvar_interpolation"}},[_vm._v("\r\n            "+_vm._s(_vm.$tr('Sharp Corners'))+"\r\n          ")]),_vm._v(" "),_c('tt-option-radio',{attrs:{"option":4},model:{value:(_vm.options.fvar_interpolation),callback:function ($$v) {_vm.$set(_vm.options, "fvar_interpolation", $$v)},expression:"options.fvar_interpolation"}},[_vm._v("\r\n            "+_vm._s(_vm.$tr('Sharp Edges and Corners'))+"\r\n          ")]),_vm._v(" "),_c('tt-option-radio',{attrs:{"option":5},model:{value:(_vm.options.fvar_interpolation),callback:function ($$v) {_vm.$set(_vm.options, "fvar_interpolation", $$v)},expression:"options.fvar_interpolation"}},[_vm._v("\r\n            "+_vm._s(_vm.$tr('All Sharp'))+"\r\n          ")])],1),_vm._v(" "),_c('hr',{staticClass:"hr-sm"}),_vm._v(" "),_c('tt-option-header',[_vm._v(_vm._s(_vm.$tr('Edge Visibility')))]),_vm._v(" "),_c('tt-option-group',[_c('tt-option-radio',{attrs:{"option":0},model:{value:(_vm.options.edge_visibility),callback:function ($$v) {_vm.$set(_vm.options, "edge_visibility", $$v)},expression:"options.edge_visibility"}},[_vm._v("\r\n            "+_vm._s(_vm.$tr('None'))+"\r\n          ")]),_vm._v(" "),_c('tt-option-radio',{attrs:{"option":1},model:{value:(_vm.options.edge_visibility),callback:function ($$v) {_vm.$set(_vm.options, "edge_visibility", $$v)},expression:"options.edge_visibility"}},[_vm._v("\r\n            "+_vm._s(_vm.$tr('Original'))+"\r\n          ")]),_vm._v(" "),_c('tt-option-radio',{attrs:{"option":2},model:{value:(_vm.options.edge_visibility),callback:function ($$v) {_vm.$set(_vm.options, "edge_visibility", $$v)},expression:"options.edge_visibility"}},[_vm._v("\r\n            "+_vm._s(_vm.$tr('All'))+"\r\n          ")])],1),_vm._v(" "),_c('hr',{staticClass:"hr-sm"}),_vm._v(" "),_c('tt-option-checkbox',{model:{value:(_vm.options.triangle_subdivision),callback:function ($$v) {_vm.$set(_vm.options, "triangle_subdivision", $$v)},expression:"options.triangle_subdivision"}},[_vm._v("\r\n          "+_vm._s(_vm.$tr('Triangle Subdivision'))+"\r\n        ")]),_vm._v(" "),_c('tt-option-checkbox',{model:{value:(_vm.options.creasing),callback:function ($$v) {_vm.$set(_vm.options, "creasing", $$v)},expression:"options.creasing"}},[_vm._v("\r\n          "+_vm._s(_vm.$tr('Smooth Non-uniform Creasing'))+"\r\n        ")])],1)])])])}
__vue__options__.staticRenderFns = [function render () {var _vm=this;var _h=_vm.$createElement;var _c=_vm._self._c||_h;return _c('div',{staticClass:"ticks"},[_c('div',{staticClass:"tick"},[_vm._v(" ")]),_c('div',{staticClass:"tick"},[_vm._v(" ")]),_c('div',{staticClass:"tick"},[_vm._v(" ")])])}]

},{"./components/button.vue":1,"./components/option-checkbox.vue":2,"./components/option-group.vue":3,"./components/option-header.vue":4,"./components/option-radio.vue":5}],7:[function(require,module,exports){
'use strict';

var _vooI18n = require('voo-i18n');

var _vooI18n2 = _interopRequireDefault(_vooI18n);

var _translator = require('./modules/translator.js');

var _translator2 = _interopRequireDefault(_translator);

var _vue_su_error_handler = require('./modules/vue_su_error_handler.js');

var _vue_su_error_handler2 = _interopRequireDefault(_vue_su_error_handler);

var _entity_info = require('./entity_info.vue');

var _entity_info2 = _interopRequireDefault(_entity_info);

function _interopRequireDefault(obj) { return obj && obj.__esModule ? obj : { default: obj }; }

/*******************************************************************************
 *
 * Thomas Thomassen
 * thomas[at]thomthom[dot]net
 *
 ******************************************************************************/

// require('babelify-es6-polyfill');

// import Vue from 'vue'
Vue.config.errorHandler = _vue_su_error_handler2.default;

function boot(config) {
  Vue.use(_vooI18n2.default, config.translations);
  Vue.use(_translator2.default);

  var vm = new Vue({
    el: '#app',
    // https://vuejs.org/v2/guide/render-function#JSX
    // Aliasing createElement to h is a common convention you’ll see in the Vue
    // ecosystem and is actually required for JSX. If h is not available in the
    // scope, your app will throw an error.
    render: function render(h) {
      return h(_entity_info2.default, {
        props: {
          config: config
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

  Sketchup.callback("EntityInfo.ready");
}

// For local debugging in browser.
/*
if (navigator.userAgent.search('SketchUp') < 0) {
  console.log('Debug mode active');
  $(document).ready(function() {
    let config = {
      translations: {},
      locale: "en",
    };
    console.log('boot', config);
    boot(config);
    console.log('ready');
    window.show_selection_panel({ title: '1 Group Selected' });
    let mesh = {
      subdivided: true,
      subdivisions: 1,
      scheme: 1, // Catmull-Clark
      boundary: 1, // Smooth
      fvar_interpolation: 5, // All Sharp
      edge_visibility: 1, // Original
      triangle_subdivision: false,
      creasing: false,
    }
    window.show_subdivision_panel(mesh);
  });
}
*/

/*******************************************************************************
 * External functions for SketchUp
 ******************************************************************************/

window.boot = function (config) {
  boot(config);
};

window.show_subdivision_panel = function (mesh) {
  // console.log('show_subdivision_panel', mesh);
  if (Object.keys(mesh).length == 0) {
    // console.log('mesh = false');
    window.app.selection.have_mesh = false;
  } else {
    // console.log('mesh = true');
    window.app.update_mesh(mesh);
    window.app.selection.have_mesh = true;
  }
};

window.hide_subdivision_panel = function () {
  // console.log('hide_subdivision_panel');
  window.app.selection = {
    description: "",
    have_mesh: false
  };
};

window.show_selection_panel = function (data) {
  // console.log('show_selection_panel', data);
  window.app.selection.description = data.title;
};

window.reset_entity_info = function () {
  // console.log('reset_entity_info');
  window.app.selection = {
    description: "",
    have_mesh: false
  };
  window.app.reset_mesh();
};
},{"./entity_info.vue":6,"./modules/translator.js":8,"./modules/vue_su_error_handler.js":9,"voo-i18n":47}],8:[function(require,module,exports){
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
        return this.$t(string, { num: quantity });
      } else {
        return this.$t(singular);
      }
    };
  }
};
},{}],9:[function(require,module,exports){
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
},{}],10:[function(require,module,exports){
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

var core = module.exports = { version: '2.6.12' };
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
  copyright: '© 2020 Denis Pushkarev (zloirock.ru)'
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
},{"babel-runtime/core-js/object/keys":10}]},{},[7])