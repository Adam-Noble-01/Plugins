"""Run isolated Ruby checks using SketchUp's bundled interpreter (not its model).

No SketchUp process or document is controlled. Test scripts end in .rb.test so
Noble's recursive Ruby reloader cannot load the test harness into SketchUp.
"""
import ctypes
import json
import os
from pathlib import Path
import sys

sketchup_dir = Path(r"C:\Program Files\SketchUp\SketchUp 2026\SketchUp")
dll_directory = os.add_dll_directory(str(sketchup_dir))
ruby = ctypes.CDLL(str(sketchup_dir / "x64-ucrt-ruby320.dll"))
argc = ctypes.c_int(1)
argv = (ctypes.c_char_p * 2)(b"noble_vegetation_checks", None)
argv_pointer = ctypes.cast(argv, ctypes.POINTER(ctypes.c_char_p))
ruby.ruby_sysinit(ctypes.byref(argc), ctypes.byref(argv_pointer))
ruby.ruby_init()
ruby.ruby_init_loadpath()
# ruby_options loads Ruby's builtin prelude (Dir.[], Kernel#warn, etc.).
options = (ctypes.c_char_p * 4)(b"ruby", b"-e", b"", None)
ruby.ruby_options.argtypes = [ctypes.c_int, ctypes.POINTER(ctypes.c_char_p)]
ruby.ruby_options.restype = ctypes.c_void_p
ruby.ruby_options(3, options)
ruby.rb_eval_string_protect.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_int)]
ruby.rb_eval_string_protect.restype = ctypes.c_size_t
stdlib = sketchup_dir / "Tools" / "RubyStdLib"
script = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).with_name("regression.rb.test")
source = "$LOAD_PATH.unshift(" + ",".join(json.dumps(str(p).replace("\\", "/")) for p in [stdlib, stdlib / "platform_specific"]) + ");"
source += "begin; load " + json.dumps(script.as_posix()) + "; rescue Exception => e; warn e.full_message; raise; end"
state = ctypes.c_int()
ruby.rb_eval_string_protect(source.encode("utf-8"), ctypes.byref(state))
result = 1 if state.value else 0
ruby.ruby_cleanup(result)
sys.exit(result)
