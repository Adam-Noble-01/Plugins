# =============================================================================
# NA SKETCHUP MCP - PYTHON SERVER - RESOURCES AND PROMPTS
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Server__Resources__.py
# PURPOSE    : MCP resources (guides, API reference, live model snapshots) and
#              prompts (ready-made workflows the user can start from the client)
# CREATED    : 2026
#
# RESOURCES:
#   sketchup://guide/agent        the full agent guide (markdown)
#   sketchup://guide/instructions the short server instructions
#   sketchup://api/summary        API index facts and every class name
#   sketchup://model/summary      live model_info           (needs SketchUp)
#   sketchup://model/selection    live selection_get        (needs SketchUp)
#   sketchup://model/outliner     live outliner_tree depth 2 (needs SketchUp)
# TEMPLATES:
#   sketchup://api/class/{name}   one API class: methods, constants, docs link
#   sketchup://entity/{id}        live entity_get for one persistent id
#
# Static resources are cacheable (public, 1 hour); live ones are never cached.
#
# =============================================================================

import json
import os
import re

import Na__SketchUpMcp__Server__BridgeClient__ as Na__BridgeClientModule

NA_SERVER_DIR = os.path.dirname(os.path.abspath(__file__))
NA_MODULES_ROOT = os.path.abspath(os.path.join(NA_SERVER_DIR, '..'))


class Na__ResourceNotFound(Exception):
    """resources/read for a URI this server does not serve."""


class Na__PromptNotFound(Exception):
    """prompts/get for an unknown prompt or a missing required argument."""


# -----------------------------------------------------------------------------
# REGION | Prompts (text kept short; the tools carry the detail)
# -----------------------------------------------------------------------------

NA_PROMPTS = [
    {
        'name': 'sketchup_survey_model',
        'title': 'Survey the open model',
        'description': 'Understand the open SketchUp model without changing it.',
        'arguments': [{'name': 'focus', 'description': 'Optional: what to pay attention to.', 'required': False}],
        'text': ('Survey the SketchUp model that is open right now, without changing anything. Call sketchup_status, model_info, '
                 'outliner_tree (max_depth 3), collection_list for tags and for materials, and view_capture with standard_view "iso". '
                 'Then summarise: what the model contains, how it is organised (groups, components, tags), its units, and anything '
                 'that looks wrong (loose geometry at the root, untagged groups, non-solid groups, unused items, very large or tiny '
                 'objects). Focus: {focus}')
    },
    {
        'name': 'sketchup_build_from_brief',
        'title': 'Build from a brief',
        'description': 'Plan, build and verify geometry from a written brief.',
        'arguments': [{'name': 'brief', 'description': 'What to build, with sizes if known.', 'required': True}],
        'text': ('Build this in the open SketchUp model: {brief}\n\nFirst call sketchup_status and look at what is already there. '
                 'Plan the elements with sizes in millimetres and world positions, and state assumptions in one short list. Build in '
                 'logical stages with batch_execute (one undo step per stage), giving every group a clear name and a tag. Check the '
                 'result with geometry_measure and view_capture from two directions, fix anything wrong, and finish with the ids and '
                 'names of what you created.')
    },
    {
        'name': 'sketchup_whitecard_massing',
        'title': 'Whitecard massing model',
        'description': 'Noble Architecture style whitecard massing for planning visuals.',
        'arguments': [{'name': 'description', 'description': 'The building or extension to mass.', 'required': True}],
        'text': ('Create a whitecard massing model of: {description}\n\nConventions: each building element is its own named solid '
                 'group (e.g. "Main House", "Rear Extension", "Roof - Main"), roofs are separate groups from walls, all faces plain '
                 'white or light grey (material "#F2F2F2"), groups tagged by element type, real dimensions in millimetres, ground '
                 'floor at z = 0. Use geometry_create_solid and batch_execute; keep geometry inside groups. Finish with view_capture '
                 'iso and front views.')
    },
    {
        'name': 'sketchup_tidy_model',
        'title': 'Tidy the model',
        'description': 'Audit the model and propose clean-up steps before doing any of them.',
        'arguments': [],
        'text': ('Audit the open SketchUp model for tidiness: loose geometry at the root, stray edges, groups or components with no '
                 'tag, geometry that is tagged (should be Untagged inside tagged groups), unused definitions, materials and tags, '
                 'duplicate or meaningless names. Use outliner_tree, entity_query and collection_list with include_usage. Report '
                 'findings as a numbered list of proposed changes, then ask before doing anything destructive (model_purge, '
                 'entity_delete, explode).')
    },
    {
        'name': 'sketchup_scene_set',
        'title': 'Standard scenes',
        'description': 'Create plan, elevation and iso scenes and capture each one.',
        'arguments': [{'name': 'views', 'description': 'Optional list, e.g. "top, front, back, left, right, iso".', 'required': False}],
        'text': ('Create a set of scenes in the open SketchUp model: {views}. For each: scene_manage action "create" with a clear name '
                 '(e.g. "Plan", "Front Elevation", "Iso"), standard_view, zoom "extents", and parallel projection (camera '
                 'perspective false) for plans and elevations. Then view_capture each scene (scene argument) at 1280 x 800 and show '
                 'the results.')
    }
]

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Resources
# -----------------------------------------------------------------------------

class Na__Resources:
    """Serves resources and prompts. Live resources reuse the bridge tools."""

    def __init__(self, registry, bridge, api_index):
        self.na_registry = registry
        self.na_bridge = bridge
        self.na_api_index = api_index

    def na_doc_path(self, key):
        relative = self.na_registry.Na__ToolRegistry__Server().get(key, '')
        return os.path.join(NA_MODULES_ROOT, relative.replace('/', os.sep)) if relative else ''

    def Na__Resources__List(self):
        return [
            {'uri': 'sketchup://guide/agent', 'name': 'agent-guide', 'title': 'SketchUp MCP agent guide',
             'description': 'How to work with this server: coordinates, units, ids, undo, workflows, pitfalls.', 'mimeType': 'text/markdown'},
            {'uri': 'sketchup://guide/instructions', 'name': 'server-instructions', 'title': 'Server instructions',
             'description': 'The short rules sent to every client at connection.', 'mimeType': 'text/markdown'},
            {'uri': 'sketchup://api/summary', 'name': 'api-summary', 'title': 'SketchUp Ruby API summary',
             'description': 'Index facts and every class/module name of the official SketchUp Ruby API.', 'mimeType': 'application/json'},
            {'uri': 'sketchup://model/summary', 'name': 'model-summary', 'title': 'Open model summary (live)',
             'description': 'model_info of the open model.', 'mimeType': 'application/json'},
            {'uri': 'sketchup://model/selection', 'name': 'model-selection', 'title': 'Current selection (live)',
             'description': 'selection_get of the open model.', 'mimeType': 'application/json'},
            {'uri': 'sketchup://model/outliner', 'name': 'model-outliner', 'title': 'Outliner (live)',
             'description': 'outliner_tree of the open model, two levels deep.', 'mimeType': 'application/json'}
        ]

    def Na__Resources__Templates(self):
        return [
            {'uriTemplate': 'sketchup://api/class/{name}', 'name': 'api-class', 'title': 'SketchUp API class',
             'description': 'Methods, constants and docs link of one API class, e.g. sketchup://api/class/Sketchup::Face', 'mimeType': 'application/json'},
            {'uriTemplate': 'sketchup://entity/{id}', 'name': 'entity', 'title': 'Entity by persistent id (live)',
             'description': 'entity_get for one id.', 'mimeType': 'application/json'}
        ]

    def Na__Resources__IsLive(self, uri):
        return uri.startswith('sketchup://model/') or uri.startswith('sketchup://entity/')

    def Na__Resources__Read(self, uri):
        """Return (mime_type, text)."""
        if uri == 'sketchup://guide/agent':
            return 'text/markdown', na_read_text(self.na_doc_path('guide_file'))
        if uri == 'sketchup://guide/instructions':
            return 'text/markdown', na_read_text(self.na_doc_path('instructions_file'))
        if uri == 'sketchup://api/summary':
            facts = self.na_api_index.Na__ApiIndex__Facts()
            facts['class_names'] = sorted(self.na_api_index.Na__ApiIndex__Classes().keys())
            return 'application/json', json.dumps(facts, ensure_ascii=False)
        class_match = re.match(r'^sketchup://api/class/(.+)$', uri)
        if class_match:
            lookup = self.na_api_index.Na__ApiIndex__Lookup(class_match.group(1), 1, False)
            if not lookup.get('found'):
                raise Na__ResourceNotFound(uri)
            return 'application/json', json.dumps(lookup['results'][0], ensure_ascii=False)
        live_calls = {
            'sketchup://model/summary': ('model_info', {}),
            'sketchup://model/selection': ('selection_get', {}),
            'sketchup://model/outliner': ('outliner_tree', {'max_depth': 2})
        }
        if uri in live_calls:
            return 'application/json', self.na_live(*live_calls[uri])
        entity_match = re.match(r'^sketchup://entity/(\d+)$', uri)
        if entity_match:
            return 'application/json', self.na_live('entity_get', {'ids': [int(entity_match.group(1))]})
        raise Na__ResourceNotFound(uri)

    def na_live(self, command, params):
        try:
            response = self.na_bridge.Na__BridgeClient__Request(command, params, 60)
        except Na__BridgeClientModule.Na__BridgeError as error:
            return json.dumps({'connected': False, 'message': error.na_message, 'how_to_fix': error.na_hint})
        return json.dumps(response.get('result') if response.get('ok') else {'error': response.get('error')}, ensure_ascii=False)

    # --- prompts ---------------------------------------------------------------------

    def Na__Resources__Prompts(self):
        return [{key: prompt[key] for key in ('name', 'title', 'description', 'arguments')} for prompt in NA_PROMPTS]

    def Na__Resources__PromptGet(self, name, arguments):
        prompt = next((item for item in NA_PROMPTS if item['name'] == name), None)
        if prompt is None:
            raise Na__PromptNotFound('Unknown prompt: %s' % name)
        arguments = arguments or {}
        values = {}
        for argument in prompt['arguments']:
            value = arguments.get(argument['name'])
            if argument.get('required') and not value:
                raise Na__PromptNotFound('Prompt %s needs argument %s.' % (name, argument['name']))
            values[argument['name']] = value or 'none given'
        return {
            'description': prompt['description'],
            'messages': [{'role': 'user', 'content': {'type': 'text', 'text': prompt['text'].format(**values)}}]
        }

# endregion -------------------------------------------------------------------


def na_read_text(path):
    try:
        with open(path, encoding='utf-8') as handle:
            return handle.read()
    except OSError:
        raise Na__ResourceNotFound(path)

# =============================================================================
# END OF FILE
# =============================================================================
