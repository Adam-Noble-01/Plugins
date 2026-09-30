# =============================================================================
# NA SKETCHUP MCP - TESTS - VALIDATE API USAGE ("NO INVENTED API")
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Tests__ValidateApiUsage__.py
# PURPOSE    : Prove offline that the bridge only calls SketchUp API that exists
# CREATED    : 2026
#
# CHECKS:
#   1. Every "api" dependency in the tool registry exists in the official
#      SketchUp API index (class + method, following superclasses).
#   2. Every method called anywhere in the bridge's Ruby code (".name") is a
#      SketchUp API method, a Ruby 3.2 core/stdlib method, or a method this
#      plugin defines itself. Anything else is an invented method.
#   3. Every Sketchup::/Geom::/UI:: constant path used exists in the index, and
#      every SketchUp top-level constant used (PAGE_USE_*, MF_*, TextAlign*...)
#      is one SketchUp documents.
#   4. The router, the registry and the handler files agree: every bridge tool
#      has a route, every route points at a method that is defined.
#   5. Registry hygiene: tool names, description lengths (Claude Code cuts at
#      2,048 characters), schema expansion, core toolset, send_action enum.
#
# USAGE: python Na__SketchUpMcp__Tests__ValidateApiUsage__.py   (exit 1 on any failure)
#
# =============================================================================

import glob
import json
import os
import re
import sys

sys.dont_write_bytecode = True
NA_TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
NA_MODULES_ROOT = os.path.abspath(os.path.join(NA_TESTS_DIR, '..'))
NA_DATA_DIR = os.path.join(NA_MODULES_ROOT, '02__Plugin__CoreAppData')
sys.path.insert(0, os.path.join(NA_MODULES_ROOT, '30__McpServer__Python'))

import Na__SketchUpMcp__Server__ApiIndex__ as Na__ApiIndexModule          # noqa: E402
import Na__SketchUpMcp__Server__ToolRegistry__ as Na__ToolRegistryModule  # noqa: E402

NA_RUBY_FOLDERS = ['02__Plugin__CoreAppData', '03__Plugin__CoreAppLogic', '04__Plugin__BridgeCore', '06__Plugin__BridgeHelpers', '10__BridgeHandlers']

# asset_library / asset_library_edit call into Adam's Component Editor Tools (Na Noble3d
# Modelling Tools). Every def in that module counts as defined; its MCP seam (12__McpOperations
# and the SafeLoad it relies on) runs inside SketchUp for the agent, so it is checked like the bridge.
NA_PARTNER_ROOT = os.path.join(os.path.dirname(NA_MODULES_ROOT), 'Na__Noble3dModellingTools__Modules__', '10__PluginModules',
                               '21__SourceCode__ComponentEditorTools')
NA_PARTNER_CHECKED = [os.path.join('12__McpOperations', '*.rb'),
                      os.path.join('08__LibraryManager', 'Na__ComponentEditorTools__LibraryManager__SafeLoad__.rb')]
NA_SKETCHUP_TOP_LEVEL = re.compile(r'\b(PAGE_[A-Z_]+|MF_[A-Z]+|TB_[A-Z_]+|IDOK|IDCANCEL|TextAlign[A-Za-z]+|SnapTo_[A-Za-z]+|IDENTITY|ORIGIN|[XYZ]_AXIS)\b')

# Method names allowed although the index does not list them, each with its reason.
# (Internal Na__Module.na_helper calls are covered by the plugin's own def scan.)
NA_ALLOWLIST = {
    'crc32': 'Zlib.crc32 (Ruby stdlib zlib, bundled with SketchUp): asset_library_edit archive zips',
    'deflate': 'Zlib::Deflate#deflate: the zip entry',
    'inflate': 'Zlib::Inflate#inflate: the zip is read back and compared before the original moves',
}


# -----------------------------------------------------------------------------
# REGION | Helpers
# -----------------------------------------------------------------------------

def na_ruby_files():
    files = []
    for folder in NA_RUBY_FOLDERS:
        files.extend(glob.glob(os.path.join(NA_MODULES_ROOT, folder, '**', '*.rb'), recursive=True))
    files.append(os.path.join(os.path.dirname(NA_MODULES_ROOT), 'Na__SketchUpMcp__Loader__.rb'))
    return sorted(path for path in files if os.path.exists(path))


def na_partner_files():
    """(every .rb of the partner module, the partner files checked like the bridge)."""
    if not os.path.isdir(NA_PARTNER_ROOT):
        return [], []
    all_files = sorted(glob.glob(os.path.join(NA_PARTNER_ROOT, '**', '*.rb'), recursive=True))
    checked = sorted(path for pattern in NA_PARTNER_CHECKED for path in glob.glob(os.path.join(NA_PARTNER_ROOT, pattern)))
    return all_files, checked


def na_read(path):
    with open(path, encoding='utf-8') as handle:
        return handle.read()


def na_signature_exists(api, signature):
    match = re.match(r'^([A-Z][\w:]*)(#|\.)(.+)$', signature)
    if not match:
        return False
    class_name = api.na_resolve_class(match.group(1))
    if not class_name:
        return False
    scope = 'class' if match.group(2) == '.' else 'instance'
    _owner, method = api.na_find_method(class_name, scope, match.group(3))
    return method is not None

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Checks
# -----------------------------------------------------------------------------

def na_check_registry_api(api, registry_raw, failures):
    checked = 0
    for tool in registry_raw['tools']:
        for signature in tool.get('api', []):
            checked += 1
            if not na_signature_exists(api, signature):
                failures.append('registry %s: api dependency %s is not in the SketchUp API index' % (tool['name'], signature))
    return checked


def na_check_method_calls(api, files, failures, defining_files=()):
    own_defs = set()
    for path in list(files) + list(defining_files):
        own_defs.update(re.findall(r'\bdef\s+(?:self\.)?([A-Za-z_][A-Za-z0-9_]*[?!=]?)', na_read(path)))
    known = api.na_api_method_names | api.na_ruby_methods | own_defs | set(NA_ALLOWLIST)
    calls = 0
    for path in files:
        source = Na__ApiIndexModule.na_strip_ruby_comments_and_strings(na_read(path))
        for pattern in (Na__ApiIndexModule.NA_CALL, Na__ApiIndexModule.NA_SAFE_CALL):
            for match in pattern.finditer(source):
                name = match.group(1)
                calls += 1
                bare = name.rstrip('=')
                if name in known or bare in known or (bare + '=') in known:
                    continue
                line = source.count('\n', 0, match.start()) + 1
                failures.append('%s:%d calls .%s, which is not SketchUp API, Ruby core or defined by this plugin' % (
                    os.path.relpath(path, NA_MODULES_ROOT), line, name))
    return calls


def na_check_constants(api, files, failures):
    classes = api.na_index['classes']
    top_level = set(classes.get('(top_level)', {}).get('constants', []))
    checked = 0
    for path in files:
        source = Na__ApiIndexModule.na_strip_ruby_comments_and_strings(na_read(path))
        for match in Na__ApiIndexModule.NA_CONSTANT_PATH.finditer(source):
            constant_path = match.group(1)
            checked += 1
            if constant_path in classes:
                continue
            parent, _separator, leaf = constant_path.rpartition('::')
            if parent in classes and leaf in classes[parent].get('constants', []):
                continue
            failures.append('%s uses %s, which the SketchUp API does not define' % (os.path.relpath(path, NA_MODULES_ROOT), constant_path))
        for match in NA_SKETCHUP_TOP_LEVEL.finditer(source):
            checked += 1
            if match.group(1) not in top_level:
                failures.append('%s uses top-level constant %s, which SketchUp does not document' % (os.path.relpath(path, NA_MODULES_ROOT), match.group(1)))
        for name in re.findall(r'\bLength::([A-Z]\w*)', source):
            checked += 1
            if name not in classes['Length']['constants']:
                failures.append('%s uses Length::%s, which SketchUp does not define' % (os.path.relpath(path, NA_MODULES_ROOT), name))
        checked += na_check_string_constants(path, classes, top_level, failures)
    return checked


def na_check_string_constants(path, classes, top_level, failures):
    """Constant names kept in strings and looked up at runtime (Length units, SnapTo_*, PAGE_USE_* flags)."""
    raw = na_read(path)
    relative = os.path.relpath(path, NA_MODULES_ROOT)
    checked = 0
    for block in re.findall(r'NA_(?:LENGTH_UNIT|LENGTH_FORMAT|AREA_UNIT|VOLUME_UNIT)_NAMES\s*=\s*\{(.*?)\}\.freeze', raw, re.S):
        for name in re.findall(r"=>\s*'(\w+)'", block):
            checked += 1
            if name not in classes['Length']['constants']:
                failures.append('%s maps to Length::%s, which SketchUp does not define' % (relative, name))
    for name in re.findall(r"'((?:SnapTo_|PAGE_USE_|PAGE_NO_|TextAlign)\w+)'", raw):
        checked += 1
        if name not in top_level:
            failures.append('%s names top-level constant %s, which SketchUp does not define' % (relative, name))
    page_methods = {method['name'] for method in classes['Sketchup::Page']['methods']}
    for setter in re.findall(r"'PAGE_USE_\w+',\s*:(use_\w+=)", raw):
        checked += 1
        if setter not in page_methods:
            failures.append('%s calls Sketchup::Page#%s, which does not exist' % (relative, setter))
    return checked


def na_check_routes(registry_raw, files, failures):
    router = na_read(os.path.join(NA_MODULES_ROOT, '04__Plugin__BridgeCore', 'Na__SketchUpMcp__BridgeCore__CommandRouter__.rb'))
    routes = dict(re.findall(r"'([a-z_]+)'\s*=>\s*\[:Na__\w+,\s*:(Na__\w+)\]", router))
    defined = set()
    for path in files:
        defined.update(re.findall(r'\bdef\s+self\.(Na__[A-Za-z0-9_]+)', na_read(path)))
    for key, method in routes.items():
        if method not in defined:
            failures.append('router: %s -> %s, but no such method is defined' % (key, method))
    for tool in registry_raw['tools']:
        if tool.get('runs_on') == 'bridge' and tool['name'] != 'batch_execute' and tool.get('handler_key', tool['name']) not in routes:
            failures.append('registry tool %s runs on the bridge but has no route' % tool['name'])
    internal = {'ping', 'api_probe'}
    names = {tool.get('handler_key', tool['name']) for tool in registry_raw['tools']}
    for key in routes:
        if key not in names and key not in internal:
            failures.append('router: route %s has no registry tool' % key)
    return len(routes)


def na_check_registry_hygiene(api, failures):
    raw = json.load(open(Na__ToolRegistryModule.NA_REGISTRY_PATH, encoding='utf-8'))
    registry = Na__ToolRegistryModule.Na__ToolRegistry('full')
    names = [tool['name'] for tool in raw['tools']]
    if len(names) != len(set(names)):
        failures.append('registry: duplicate tool names')
    for tool in registry.na_tools:
        if not re.match(r'^[a-z][a-z0-9_]*$', tool['name']) or len('mcp__sketchup__' + tool['name']) > 64:
            failures.append('registry: bad tool name %s' % tool['name'])
        if len(tool['description']) > 2048:
            failures.append('registry: %s description is %d characters (Claude Code cuts at 2048)' % (tool['name'], len(tool['description'])))
        if '$use' in json.dumps(tool['input_schema']):
            failures.append('registry: %s schema still contains $use after expansion' % tool['name'])
        for prop in tool['input_schema'].get('properties', {}):
            if not re.match(r'^[A-Za-z0-9_.-]{1,64}$', prop):
                failures.append('registry: %s property name %r breaks client rules' % (tool['name'], prop))
    for name in raw['toolsets']['core']:
        if name not in names:
            failures.append('registry: core toolset lists unknown tool %s' % name)
    send_action = next(tool for tool in registry.na_tools if tool['name'] == 'sketchup_send_action')
    if send_action['input_schema']['properties']['action']['enum'] != api.na_index['enumerations']['send_action']['supported']:
        failures.append('registry: sketchup_send_action enum differs from the documented send_action list')
    return len(names), raw

# endregion -------------------------------------------------------------------


def na_main():
    api = Na__ApiIndexModule.Na__ApiIndex()
    api.na_load()
    failures = []
    tool_count, registry_raw = na_check_registry_hygiene(api, failures)
    files = na_ruby_files()
    partner_all, partner_checked = na_partner_files()
    api_count = na_check_registry_api(api, registry_raw, failures)
    call_count = na_check_method_calls(api, files + partner_checked, failures, partner_all)
    constant_count = na_check_constants(api, files + partner_checked, failures)
    route_count = na_check_routes(registry_raw, files, failures)

    print('Registry: %d tools; %d API dependencies checked against %d SketchUp methods (%s).' % (
        tool_count, api_count, api.na_index['counts']['methods'], api.na_index['api_highest_version']))
    print('Ruby: %d files, %d method calls, %d constant uses, %d routes checked.' % (len(files), call_count, constant_count, route_count))
    if partner_checked:
        print('Partner: %d Component Editor Tools files checked, %d defining.' % (len(partner_checked), len(partner_all)))
    else:
        print('Partner: Component Editor Tools not found at %s; asset_library calls into it are unchecked.' % NA_PARTNER_ROOT)
    if failures:
        print('FAILED (%d):' % len(failures))
        for failure in failures:
            print('  - ' + failure)
        return 1
    print('PASSED: no invented SketchUp API, every tool routed.')
    return 0


if __name__ == '__main__':
    sys.exit(na_main())

# =============================================================================
# END OF FILE
# =============================================================================
