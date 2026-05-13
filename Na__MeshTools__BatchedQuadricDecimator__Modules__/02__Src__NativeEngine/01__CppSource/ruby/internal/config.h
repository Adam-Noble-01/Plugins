#pragma once

// SketchUp's vendored Ruby 3.2 Windows headers include ruby/config.h but
// ruby/ruby.h asks for ruby/internal/config.h. Keep this local shim in the
// native engine include path so the third-party dependency stays untouched.
#include "ruby/config.h"
