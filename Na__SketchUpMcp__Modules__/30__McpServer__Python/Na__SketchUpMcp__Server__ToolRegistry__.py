# =============================================================================
# NA SKETCHUP MCP - PYTHON SERVER - TOOL REGISTRY
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Server__ToolRegistry__.py
# PURPOSE    : Load the shared tool registry JSON and present it as MCP tools
# CREATED    : 2026
#
# SINGLE SOURCE OF TRUTH:
# 02__Plugin__CoreAppData/Na__SketchUpMcp__CoreAppData__ToolRegistry__.json is
# read by this server (names, descriptions, schemas, annotations, toolsets,
# timeouts) AND by the Ruby bridge (handler routes, undo behaviour, API
# dependencies). {"$use": "name"} entries are expanded here from
# common_schemas so the JSON stays DRY while clients receive plain schemas.
#
# TOOLSETS:
# full (default) = every tool. core = the tools listed under toolsets.core,
# for clients that cap the number of tools (e.g. older Cursor builds).
#
# HOT RELOAD:
# Na__ToolRegistry__ReloadIfChanged re-reads the file when its modification
# time changes, so the protocol layer can tell clients the list changed.
#
# =============================================================================

import copy
import json
import os

NA_SERVER_DIR = os.path.dirname(os.path.abspath(__file__))
NA_MODULES_ROOT = os.path.abspath(os.path.join(NA_SERVER_DIR, '..'))
NA_REGISTRY_PATH = os.path.join(NA_MODULES_ROOT, '02__Plugin__CoreAppData', 'Na__SketchUpMcp__CoreAppData__ToolRegistry__.json')


# -----------------------------------------------------------------------------
# REGION | Schema Expansion
# -----------------------------------------------------------------------------

def na_expand(node, common):
    """Replace {"$use": name, ...overrides} with a deep copy of common[name] updated by the overrides."""
    if isinstance(node, list):
        return [na_expand(item, common) for item in node]
    if not isinstance(node, dict):
        return node
    if '$use' in node:
        name = node['$use']
        if name not in common:
            raise KeyError('Registry $use refers to unknown common schema: %s' % name)
        expanded = copy.deepcopy(common[name])
        for key, value in node.items():
            if key != '$use':
                expanded[key] = na_expand(value, common)
        return na_expand(expanded, common)
    return {key: na_expand(value, common) for key, value in node.items()}

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Registry
# -----------------------------------------------------------------------------

class Na__ToolRegistry:
    """Holds the expanded registry and the active toolset; reloads when the file changes."""

    def __init__(self, toolset='full', registry_path=NA_REGISTRY_PATH):
        self.na_registry_path = registry_path
        self.na_toolset = toolset
        self.na_mtime = None
        self.na_raw = {}
        self.na_tools = []
        self.na_by_name = {}
        self.Na__ToolRegistry__Load()

    def Na__ToolRegistry__Load(self):
        with open(self.na_registry_path, encoding='utf-8') as handle:
            raw = json.load(handle)
        common = raw.get('common_schemas', {})
        tools = []
        for entry in raw.get('tools', []):
            tool = dict(entry)
            tool['input_schema'] = na_expand(entry.get('input_schema', {'type': 'object'}), common)
            tools.append(tool)

        if self.na_toolset == 'core':
            core_names = set(raw.get('toolsets', {}).get('core', []))
            tools = [tool for tool in tools if tool['name'] in core_names]

        self.na_raw = raw
        self.na_tools = tools
        self.na_by_name = {tool['name']: tool for tool in tools}
        self.na_mtime = os.path.getmtime(self.na_registry_path)

    def Na__ToolRegistry__ReloadIfChanged(self):
        """True when the file changed and was reloaded successfully."""
        try:
            if os.path.getmtime(self.na_registry_path) == self.na_mtime:
                return False
            self.Na__ToolRegistry__Load()
            return True
        except (OSError, ValueError, KeyError):
            return False

    def Na__ToolRegistry__ByName(self, name):
        return self.na_by_name.get(name)

    def Na__ToolRegistry__AnyByName(self, name):
        """Look up a tool even if the current toolset hides it (batch steps may use any bridge tool)."""
        tool = self.na_by_name.get(name)
        if tool:
            return tool
        common = self.na_raw.get('common_schemas', {})
        for entry in self.na_raw.get('tools', []):
            if entry.get('name') == name:
                expanded = dict(entry)
                expanded['input_schema'] = na_expand(entry.get('input_schema', {'type': 'object'}), common)
                return expanded
        return None

    def Na__ToolRegistry__Names(self):
        return [tool['name'] for tool in self.na_tools]

    def Na__ToolRegistry__Server(self):
        return self.na_raw.get('server', {})

    def Na__ToolRegistry__McpTools(self):
        """Tool definitions in MCP tools/list shape, in registry order (stable for prompt caching)."""
        definitions = []
        for tool in self.na_tools:
            annotations = dict(tool.get('annotations', {}))
            annotations['title'] = tool.get('title', tool['name'])
            definitions.append({
                'name': tool['name'],
                'title': tool.get('title', tool['name']),
                'description': tool['description'],
                'inputSchema': tool['input_schema'],
                'annotations': annotations
            })
        return definitions

# endregion -------------------------------------------------------------------

# =============================================================================
# END OF FILE
# =============================================================================
