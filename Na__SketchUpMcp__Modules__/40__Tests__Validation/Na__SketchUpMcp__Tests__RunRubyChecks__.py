# =============================================================================
# NA SKETCHUP MCP - TESTS - RUN RUBY CHECKS
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Tests__RunRubyChecks__.py
# PURPOSE    : Compile every bridge .rb file with SketchUp's own bundled Ruby,
#              then run the .rb.test suites against API doubles
# CREATED    : 2026
#
# HOW IT WORKS (same approach as Vegetation Sketcher's tests/run_ruby_checks.py):
# SketchUp 2026 ships Ruby 3.2 only as x64-ucrt-ruby320.dll, no ruby.exe. This
# script loads that DLL through ctypes and evaluates Ruby in-process. No
# SketchUp process or document is touched.
#
# Test scripts end in .rb.test so the plugin's own Reload Plugin Data (which
# loads every *.rb under the modules folder) can never load a test harness
# into the live SketchUp.
#
# USAGE:
#   python Na__SketchUpMcp__Tests__RunRubyChecks__.py            (syntax + every suite)
#   python Na__SketchUpMcp__Tests__RunRubyChecks__.py --syntax   (syntax only)
#   python Na__SketchUpMcp__Tests__RunRubyChecks__.py <file.rb.test> [...]
#
# =============================================================================

import ctypes
import json
import os
import sys
from pathlib import Path

sys.dont_write_bytecode = True

NA_SKETCHUP_DIR = Path(os.environ.get('NA_SKETCHUP_DIR', r'C:\Program Files\SketchUp\SketchUp 2026\SketchUp'))
NA_RUBY_DLL_NAME = 'x64-ucrt-ruby320.dll'
NA_TESTS_DIR = Path(__file__).resolve().parent
NA_MODULES_ROOT = NA_TESTS_DIR.parent


# -----------------------------------------------------------------------------
# REGION | Embedded Ruby
# -----------------------------------------------------------------------------

def na_boot_ruby():
    os.add_dll_directory(str(NA_SKETCHUP_DIR))
    ruby = ctypes.CDLL(str(NA_SKETCHUP_DIR / NA_RUBY_DLL_NAME))
    argc = ctypes.c_int(1)
    argv = (ctypes.c_char_p * 2)(b'na_sketchup_mcp_checks', None)
    argv_pointer = ctypes.cast(argv, ctypes.POINTER(ctypes.c_char_p))
    ruby.ruby_sysinit(ctypes.byref(argc), ctypes.byref(argv_pointer))
    ruby.ruby_init()
    ruby.ruby_init_loadpath()
    options = (ctypes.c_char_p * 4)(b'ruby', b'-e', b'', None)
    ruby.ruby_options.argtypes = [ctypes.c_int, ctypes.POINTER(ctypes.c_char_p)]
    ruby.ruby_options.restype = ctypes.c_void_p
    ruby.ruby_options(3, options)
    ruby.rb_eval_string_protect.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_int)]
    ruby.rb_eval_string_protect.restype = ctypes.c_size_t
    return ruby


def na_eval(ruby, source):
    state = ctypes.c_int()
    ruby.rb_eval_string_protect(source.encode('utf-8'), ctypes.byref(state))
    return state.value == 0


def na_load_path_prefix():
    stdlib = NA_SKETCHUP_DIR / 'Tools' / 'RubyStdLib'
    paths = [stdlib, stdlib / 'platform_specific']
    return '$LOAD_PATH.unshift(' + ','.join(json.dumps(str(path).replace('\\', '/')) for path in paths) + ');'

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Checks
# -----------------------------------------------------------------------------

def na_syntax_source():
    files = sorted(str(path).replace('\\', '/') for path in NA_MODULES_ROOT.rglob('*.rb'))
    loader = NA_MODULES_ROOT.parent / 'Na__SketchUpMcp__Loader__.rb'
    if loader.exists():
        files.append(str(loader).replace('\\', '/'))
    return (
        'na_failures = 0; na_files = ' + json.dumps(files) + ';'
        'na_files.each { |path| begin; RubyVM::InstructionSequence.compile_file(path); '
        'rescue SyntaxError => error; na_failures += 1; warn "SYNTAX ERROR #{path}\\n#{error.message}"; end };'
        'puts "Syntax: #{na_files.length - na_failures}/#{na_files.length} Ruby files compile under Ruby #{RUBY_VERSION}.";'
        'raise "syntax failures: #{na_failures}" if na_failures > 0'
    )


def na_test_source(test_path):
    return (
        '$NA_MODULES_ROOT = ' + json.dumps(str(NA_MODULES_ROOT).replace('\\', '/')) + ';'
        'begin; load ' + json.dumps(test_path.as_posix()) + '; '
        'rescue Exception => error; warn error.full_message; raise; end'
    )


def na_main(arguments):
    ruby = na_boot_ruby()
    if not na_eval(ruby, na_load_path_prefix()):
        print('Could not set the Ruby load path.')
        return 1

    syntax_only = '--syntax' in arguments
    explicit_tests = [Path(argument).resolve() for argument in arguments if not argument.startswith('--')]

    exit_code = 0
    if not explicit_tests:
        if not na_eval(ruby, na_syntax_source()):
            exit_code = 1

    if not syntax_only:
        tests = explicit_tests or sorted(NA_TESTS_DIR.glob('*.rb.test'))
        for test_path in tests:
            print('--- %s' % test_path.name)
            sys.stdout.flush()
            if not na_eval(ruby, na_test_source(test_path)):
                exit_code = 1

    sys.stdout.flush()
    ruby.ruby_cleanup(exit_code)
    return exit_code


if __name__ == '__main__':
    sys.exit(na_main(sys.argv[1:]))

# =============================================================================
# END OF FILE
# =============================================================================
