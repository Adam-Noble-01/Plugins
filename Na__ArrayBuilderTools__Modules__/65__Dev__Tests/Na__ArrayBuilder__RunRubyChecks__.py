"""Run isolated checks with SketchUp's bundled Ruby, without controlling a model."""
import ctypes
import json
import os
from pathlib import Path
import sys

na_sketchup = Path(r"C:\Program Files\SketchUp\SketchUp 2026\SketchUp")
na_dll_directory = os.add_dll_directory(str(na_sketchup))
na_ruby = ctypes.CDLL(str(na_sketchup / "x64-ucrt-ruby320.dll"))
na_argc = ctypes.c_int(1)
na_argv = (ctypes.c_char_p * 2)(b"noble_array_checks", None)
na_argv_pointer = ctypes.cast(na_argv, ctypes.POINTER(ctypes.c_char_p))
na_ruby.ruby_sysinit(ctypes.byref(na_argc), ctypes.byref(na_argv_pointer))
na_ruby.ruby_init()
na_ruby.ruby_init_loadpath()
na_options = (ctypes.c_char_p * 4)(b"ruby", b"-e", b"", None)
na_ruby.ruby_options.argtypes = [ctypes.c_int, ctypes.POINTER(ctypes.c_char_p)]
na_ruby.ruby_options.restype = ctypes.c_void_p
na_ruby.ruby_options(3, na_options)
na_ruby.rb_eval_string_protect.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_int)]
na_ruby.rb_eval_string_protect.restype = ctypes.c_size_t
na_stdlib = na_sketchup / "Tools" / "RubyStdLib"
na_script = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).with_name("Na__ArrayBuilder__Core__Spec__.rb.test")
na_source = "$LOAD_PATH.unshift(" + ",".join(json.dumps(na_path.as_posix()) for na_path in [na_stdlib, na_stdlib / "platform_specific"]) + ");"
na_source += "Encoding.const_set(:UTF_8, Encoding.find('UTF-8')) unless Encoding.const_defined?(:UTF_8);"
na_source += "begin; load " + json.dumps(na_script.as_posix()) + "; rescue Exception => na_error; warn na_error.full_message; raise; end"
na_state = ctypes.c_int()
na_ruby.rb_eval_string_protect(na_source.encode("utf-8"), ctypes.byref(na_state))
na_result = 1 if na_state.value else 0
na_ruby.ruby_cleanup(na_result)
sys.exit(na_result)
