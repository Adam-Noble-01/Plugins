# =============================================================================
# NA SKETCHUP MCP - PYTHON SERVER - SKETCHUP API INDEX
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Server__ApiIndex__.py
# PURPOSE    : Answer ruby_api_lookup (search, method detail, enumerations) and
#              lint ruby_eval code against the official SketchUp Ruby API
# CREATED    : 2026
#
# SOURCES (both generated, never hand-written):
# - Na__SketchUpMcp__CoreAppData__SketchUpApiIndex__.json: every class and
#   method of SketchUp's official ruby-api-stubs (MIT, Trimble), with
#   signatures, @version, summaries, params, options, returns, examples, and
#   the documented enumerations (send_action names, rendering option keys,
#   shadow keys, exporter / importer options).
#   Rebuild: 80__DevTools__ApiIndexBuilder/Na__SketchUpMcp__ApiIndexBuilder__.py
# - Na__SketchUpMcp__CoreAppData__RubyCoreNames__.json: every method and
#   constant name of SketchUp's own Ruby 3.2 (+ common stdlib).
#   Rebuild: 80__DevTools__ApiIndexBuilder/Na__SketchUpMcp__RubyCoreNamesBuilder__.rb
#
# THE LINT IS A NET, NOT A PROOF:
# Ruby is dynamic, so a name the lint does not know may still be a method of
# the user's own plugins. It reports such names with suggestions so the agent
# looks before it leaps; it never blocks the code.
#
# =============================================================================

import difflib
import json
import os
import re
import urllib.parse

NA_SERVER_DIR = os.path.dirname(os.path.abspath(__file__))
NA_DATA_DIR = os.path.abspath(os.path.join(NA_SERVER_DIR, '..', '02__Plugin__CoreAppData'))
NA_API_INDEX_PATH = os.path.join(NA_DATA_DIR, 'Na__SketchUpMcp__CoreAppData__SketchUpApiIndex__.json')
NA_RUBY_NAMES_PATH = os.path.join(NA_DATA_DIR, 'Na__SketchUpMcp__CoreAppData__RubyCoreNames__.json')
NA_DOCS_ROOT = 'https://ruby.sketchup.com/'
NA_NAMESPACE_PREFERENCE = ['Sketchup::', 'Geom::', 'UI::', '', 'Layout::']

NA_SIGNATURE = re.compile(r'^\s*([A-Z][\w:]*)?\s*(#|\.)\s*([\w?!=\[\]<>+\-*/%]+)\s*$')
# A method call: a single dot (not part of a .. range) then an identifier (not a digit, so 1.5 is skipped).
NA_CALL = re.compile(r'(?<!\.)\.(?!\.)\s*([a-z_][A-Za-z0-9_]*[?!=]?)')
NA_SAFE_CALL = re.compile(r'&\.\s*([a-z_][A-Za-z0-9_]*[?!]?)')
NA_CONSTANT_PATH = re.compile(r'\b((?:Sketchup|Geom|UI|Layout)(?:::[A-Z][A-Za-z0-9_]*)+)')
NA_DEFINED_METHOD = re.compile(r'\bdef\s+(?:self\.)?([A-Za-z_][A-Za-z0-9_]*[?!=]?)')


# -----------------------------------------------------------------------------
# REGION | Index
# -----------------------------------------------------------------------------

class Na__ApiIndex:
    """Lazy-loaded SketchUp API index with lookup, search and lint."""

    def __init__(self, index_path=NA_API_INDEX_PATH, ruby_names_path=NA_RUBY_NAMES_PATH):
        self.na_index_path = index_path
        self.na_ruby_names_path = ruby_names_path
        self.na_index = None
        self.na_ruby_methods = set()
        self.na_ruby_constants = set()
        self.na_api_method_names = set()
        self.na_method_owners = {}

    def na_load(self):
        if self.na_index is not None:
            return
        with open(self.na_index_path, encoding='utf-8') as handle:
            self.na_index = json.load(handle)
        for class_name, entry in self.na_index['classes'].items():
            for method in entry['methods']:
                self.na_api_method_names.add(method['name'])
                self.na_method_owners.setdefault(method['name'], []).append((class_name, method['scope']))
        try:
            with open(self.na_ruby_names_path, encoding='utf-8') as handle:
                ruby_names = json.load(handle)
            self.na_ruby_methods = set(ruby_names.get('methods', []))
            self.na_ruby_constants = set(ruby_names.get('constants', []))
        except (OSError, ValueError):
            pass

    def Na__ApiIndex__Facts(self):
        self.na_load()
        return {
            'source': self.na_index['source'],
            'api_highest_version': self.na_index['api_highest_version'],
            'classes': self.na_index['counts']['classes'],
            'methods': self.na_index['counts']['methods'],
            'ruby_core_names': len(self.na_ruby_methods)
        }

    def Na__ApiIndex__Classes(self):
        self.na_load()
        return self.na_index['classes']

    # --- class and method resolution --------------------------------------------

    def na_resolve_class(self, name):
        classes = self.na_index['classes']
        if name in classes:
            return name
        for prefix in NA_NAMESPACE_PREFERENCE:
            candidate = prefix + name
            if candidate in classes:
                return candidate
        suffix = [key for key in classes if key.split('::')[-1] == name]
        return suffix[0] if suffix else None

    def na_class_chain(self, class_name):
        chain = []
        while class_name and class_name in self.na_index['classes'] and class_name not in chain:
            chain.append(class_name)
            class_name = self.na_index['classes'][class_name].get('superclass')
        return chain

    def na_find_method(self, class_name, scope, method_name):
        if method_name == 'new' and scope == 'class':
            method_name, scope = 'initialize', 'instance'
        for owner in self.na_class_chain(class_name):
            for method in self.na_index['classes'][owner]['methods']:
                if method['name'] == method_name and method['scope'] == scope:
                    return owner, method
        return None, None

    # --- output shaping -----------------------------------------------------------

    def Na__ApiIndex__DocUrl(self, class_name, method=None):
        if class_name == '(top_level)':
            return NA_DOCS_ROOT + 'top-level-namespace.html'
        url = NA_DOCS_ROOT + class_name.replace('::', '/') + '.html'
        if method:
            url += '#' + urllib.parse.quote(method['name'], safe='') + ('-class_method' if method['scope'] == 'class' else '-instance_method')
        return url

    def na_method_card(self, owner, method, requested_class, include_example):
        separator = '.' if method['scope'] == 'class' else '#'
        card = {
            'method': owner + separator + method['name'],
            'signatures': method['signatures'],
            'version': method.get('version', ''),
            'summary': method.get('summary', ''),
            'doc_url': self.Na__ApiIndex__DocUrl(owner, method)
        }
        if requested_class and requested_class != owner:
            card['inherited_by'] = requested_class
        for key in ('params', 'options', 'returns', 'raises', 'notes', 'bugs', 'deprecated'):
            if method.get(key):
                card[key] = method[key]
        if include_example and method.get('example'):
            card['example'] = method['example']
        return card

    def na_class_card(self, class_name):
        entry = self.na_index['classes'][class_name]
        methods = [('.' if method['scope'] == 'class' else '#') + method['name'] for method in entry['methods']]
        chain = self.na_class_chain(class_name)
        inherited = []
        for owner in chain[1:]:
            inherited.append({'from': owner, 'methods': [('.' if m['scope'] == 'class' else '#') + m['name'] for m in self.na_index['classes'][owner]['methods']]})
        return {
            'class': class_name,
            'kind': entry['kind'],
            'superclass': entry.get('superclass', ''),
            'includes': entry.get('includes', []),
            'version': entry.get('version', ''),
            'summary': entry.get('summary', ''),
            'constants': entry.get('constants', [])[:200],
            'methods': methods,
            'inherited': inherited,
            'doc_url': self.Na__ApiIndex__DocUrl(class_name)
        }

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Lookup and Search
# -----------------------------------------------------------------------------

    def Na__ApiIndex__Lookup(self, query, limit=12, include_examples=True):
        """Resolve a class, a Class#method / Class.method, a bare method name, an enumeration, or free text."""
        self.na_load()
        text = (query or '').strip()
        if not text:
            return {'error': 'Pass query (e.g. "Face#pushpull", "Sketchup::Layer", "section plane") or code.'}

        enumeration = self.na_enumeration_for(text)
        if enumeration:
            return enumeration

        signature = NA_SIGNATURE.match(text)
        if signature and (signature.group(1) or signature.group(2)):
            class_part = signature.group(1)
            method_name = signature.group(3)
            scope = 'class' if signature.group(2) == '.' else 'instance'
            if class_part:
                class_name = self.na_resolve_class(class_part)
                if not class_name:
                    return {'found': False, 'message': 'No SketchUp API class or module named %s.' % class_part,
                            'did_you_mean': difflib.get_close_matches(class_part, list(self.na_index['classes'].keys()), n=5, cutoff=0.5)}
                owner, method = self.na_find_method(class_name, scope, method_name)
                if method:
                    return {'found': True, 'results': [self.na_method_card(owner, method, class_name, include_examples)]}
                return {'found': False, 'message': '%s%s%s does not exist in the SketchUp API (checked the class and its superclasses).' % (
                            class_name, signature.group(2), method_name),
                        'did_you_mean': self.na_similar_methods(method_name, class_name)}

        class_name = self.na_resolve_class(text)
        if class_name:
            return {'found': True, 'results': [self.na_class_card(class_name)]}

        if re.match(r'^[a-z_][A-Za-z0-9_]*[?!=]?$', text):
            owners = self.na_method_owners.get(text, [])
            if owners:
                cards = []
                for owner_name, scope in owners[:limit]:
                    owner, method = self.na_find_method(owner_name, scope, text)
                    if method:
                        cards.append(self.na_method_card(owner, method, None, include_examples and len(owners) <= 3))
                return {'found': True, 'results': cards, 'total': len(owners)}

        return self.na_free_text(text, limit)

    def na_free_text(self, text, limit):
        words = [word for word in re.split(r'[^a-z0-9_]+', text.lower()) if len(word) > 1]
        if not words:
            return {'found': False, 'message': 'Nothing to search for.'}
        scored = []
        for class_name, entry in self.na_index['classes'].items():
            class_lower = class_name.lower()
            for method in entry['methods']:
                name_lower = method['name'].lower()
                summary_lower = method.get('summary', '').lower()
                score = 0
                for word in words:
                    if word == name_lower:
                        score += 6
                    elif word in name_lower:
                        score += 3
                    if word in class_lower:
                        score += 2
                    if word in summary_lower:
                        score += 1
                if score >= len(words) * 2:
                    scored.append((score, class_name, method))
        scored.sort(key=lambda item: (-item[0], item[1], item[2]['name']))
        results = [{
            'method': class_name + ('.' if method['scope'] == 'class' else '#') + method['name'],
            'signature': method['signatures'][0],
            'version': method.get('version', ''),
            'summary': method.get('summary', '')[:180]
        } for _score, class_name, method in scored[:limit]]
        return {'found': bool(results), 'results': results, 'total': len(scored),
                'hint': 'Look up one of these by name (e.g. "Sketchup::Face#pushpull") for the full signature, parameters and example.'}

    def na_similar_methods(self, method_name, class_name=None):
        suggestions = []
        if class_name:
            local = []
            for owner in self.na_class_chain(class_name):
                local.extend(method['name'] for method in self.na_index['classes'][owner]['methods'])
            suggestions = difflib.get_close_matches(method_name, local, n=5, cutoff=0.5)
        if not suggestions:
            suggestions = difflib.get_close_matches(method_name, list(self.na_api_method_names), n=5, cutoff=0.6)
        return suggestions

    def na_enumeration_for(self, text):
        lower = text.lower()
        enumerations = self.na_index['enumerations']
        if 'send_action' in lower or 'send action' in lower:
            return {'found': True, 'enumeration': 'Sketchup.send_action names', 'values': enumerations['send_action']}
        if 'exporter' in lower or 'export option' in lower:
            return {'found': True, 'enumeration': 'Model#export options by format', 'values': enumerations['exporter_options']}
        if 'importer' in lower or 'import option' in lower:
            return {'found': True, 'enumeration': 'Model#import options by format', 'values': enumerations['importer_options']}
        if 'rendering option' in lower or 'rendering_options' in lower:
            return {'found': True, 'enumeration': 'RenderingOptions keys', 'values': enumerations['rendering_options_keys']}
        if 'shadow' in lower and ('key' in lower or 'info' in lower):
            return {'found': True, 'enumeration': 'ShadowInfo keys', 'values': enumerations['shadow_info_keys']}
        return None

    def Na__ApiIndex__Enumeration(self, name):
        self.na_load()
        return self.na_index['enumerations'].get(name)

    def Na__ApiIndex__Signatures(self, cards):
        """Class#method strings from lookup cards (for a live probe in SketchUp)."""
        return [card['method'] for card in cards if isinstance(card, dict) and card.get('method')]

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Code Lint (for ruby_eval)
# -----------------------------------------------------------------------------

    def Na__ApiIndex__Lint(self, code):
        """Unknown method and constant names in Ruby code (not in SketchUp API, Ruby core, or the code itself)."""
        self.na_load()
        stripped = na_strip_ruby_comments_and_strings(code or '')
        defined = set(NA_DEFINED_METHOD.findall(stripped))
        known = self.na_api_method_names | self.na_ruby_methods | defined
        unknown = {}
        calls = 0
        for pattern in (NA_CALL, NA_SAFE_CALL):
            for match in pattern.finditer(stripped):
                name = match.group(1)
                calls += 1
                bare = name.rstrip('=')
                if name in known or bare in known or (name.endswith('=') and bare + '=' in known):
                    continue
                line = stripped.count('\n', 0, match.start()) + 1
                unknown.setdefault(name, line)

        unknown_constants = []
        classes = self.na_index['classes']
        for match in NA_CONSTANT_PATH.finditer(stripped):
            path = match.group(1)
            if path in classes or path in self.na_ruby_constants:
                continue
            parent, _separator, leaf = path.rpartition('::')
            if parent in classes and leaf in classes[parent].get('constants', []):
                continue
            unknown_constants.append(path)

        findings = []
        for name, line in sorted(unknown.items(), key=lambda item: item[1]):
            findings.append({'name': name, 'line': line, 'did_you_mean': difflib.get_close_matches(name, list(self.na_api_method_names), n=3, cutoff=0.72)})
        return {
            'calls_checked': calls,
            'unknown_methods': findings,
            'unknown_constants': sorted(set(unknown_constants)),
            'note': 'Names found in neither the SketchUp API index nor Ruby core. Fine if they are your own or a plugin\'s methods; otherwise check with ruby_api_lookup.'
        }

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Ruby Source Scrubbing (so strings and comments are not linted)
# -----------------------------------------------------------------------------

NA_PERCENT_PAIRS = {'[': ']', '(': ')', '{': '}', '<': '>'}


def na_strip_ruby_comments_and_strings(code):
    """Blank out string literals, %w/%i/%q/%r literals and # comments, keeping line numbers."""
    result = []
    index = 0
    length = len(code)
    while index < length:
        char = code[index]
        if (char == '%' and index + 2 < length and code[index + 1] in 'wWiIqQr'
                and not code[index + 2].isalnum() and not code[index + 2].isspace()):
            opener = code[index + 2]
            closer = NA_PERCENT_PAIRS.get(opener, opener)
            result.append('   ')
            index += 3
            depth = 1
            while index < length and depth > 0:
                current = code[index]
                if current == opener and opener != closer:
                    depth += 1
                elif current == closer:
                    depth -= 1
                result.append('\n' if current == '\n' else ' ')
                index += 1
            continue
        if char in ('"', "'", '`'):
            quote = char
            result.append(' ')
            index += 1
            while index < length and code[index] != quote:
                if code[index] == '\\' and index + 1 < length:
                    result.append(' ')
                    index += 1
                result.append('\n' if code[index] == '\n' else ' ')
                index += 1
            result.append(' ')
            index += 1
            continue
        if char == '#':
            while index < length and code[index] != '\n':
                result.append(' ')
                index += 1
            continue
        result.append(char)
        index += 1
    return ''.join(result)

# endregion -------------------------------------------------------------------

# =============================================================================
# END OF FILE
# =============================================================================
