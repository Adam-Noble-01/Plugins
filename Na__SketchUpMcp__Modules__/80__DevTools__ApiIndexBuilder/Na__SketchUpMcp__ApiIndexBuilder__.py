# =============================================================================
# NA SKETCHUP MCP - SKETCHUP RUBY API INDEX BUILDER
# =============================================================================
#
# FILE       : Na__SketchUpMcp__ApiIndexBuilder__.py
# NAMESPACE  : Na__SketchUpMcp (developer tooling, never loaded by SketchUp)
# PURPOSE    : Parse SketchUp's official Ruby API stubs into one JSON index that
#              the MCP server searches and validates against
# CREATED    : 2026
#
# SOURCE OF TRUTH:
# https://github.com/SketchUp/ruby-api-stubs (MIT, Copyright (c) 2016-2019 SketchUp) is the
# YARD source that ruby.sketchup.com is generated from. Every class, method,
# signature, @version and summary in the index comes from those files, never
# from memory. The enumerations (send_action names, rendering option keys,
# shadow info keys, exporter and importer options) are lifted from the same
# doc comments and the stubs' pages/*.md.
#
# USAGE:
#   git clone --depth 1 https://github.com/SketchUp/ruby-api-stubs.git <dir>
#   python Na__SketchUpMcp__ApiIndexBuilder__.py --stubs <dir>
#
# OUTPUT:
#   02__Plugin__CoreAppData/Na__SketchUpMcp__CoreAppData__SketchUpApiIndex__.json
#
# =============================================================================

import argparse
import datetime
import json
import os
import re
import subprocess
import sys

sys.dont_write_bytecode = True


# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

NA_INDEX_SCHEMA_VERSION = 1
NA_SUMMARY_MAX_CHARS = 420
NA_PARAM_DESC_MAX_CHARS = 200
NA_RETURN_DESC_MAX_CHARS = 520
NA_EXAMPLE_MAX_CHARS = 700
NA_MODULES_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
NA_DEFAULT_OUTPUT_PATH = os.path.join(
    NA_MODULES_ROOT,
    '02__Plugin__CoreAppData',
    'Na__SketchUpMcp__CoreAppData__SketchUpApiIndex__.json'
)

NA_TOP_LEVEL_KEY = '(top_level)'
NA_CLASS_LINE = re.compile(r'^(class|module)\s+([A-Z][\w:]*)(?:\s*<\s*([A-Z][\w:]*))?')
NA_DEF_LINE = re.compile(r'^\s+def\s+(self\.)?([^\s(]+)(\(.*\))?\s*$')
NA_CONSTANT_LINE = re.compile(r'^\s+([A-Z][A-Za-z0-9_]*)\s*=\s*nil\s*#\s*Stub value\.')
NA_INCLUDE_LINE = re.compile(r'^\s+include\s+([A-Z][\w:]*)')
NA_TAG_LINE = re.compile(r'^(\s*)@(\w+)\s?(.*)$')

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Text Cleaning
# -----------------------------------------------------------------------------

def na_clean_yard_markup(text):
    """Strip YARD link braces and +code+ markers so text reads as plain prose."""
    text = re.sub(r'\{file:[^\s}]+\s+([^}]+)\}', r'\1', text)
    text = re.sub(r'\{([^{}\s]+)\s+([^{}]+)\}', r'\2', text)
    text = re.sub(r'\{([^{}]+)\}', r'\1', text)
    text = re.sub(r'\+([^+\s][^+]*?)\+', r'\1', text)
    return text


def na_collapse_whitespace(text):
    return re.sub(r'\s+', ' ', text).strip()


def na_truncate(text, max_chars):
    if len(text) <= max_chars:
        return text
    cut = text[:max_chars].rsplit(' ', 1)[0]
    return cut + ' ...'


def na_first_paragraphs(lines, max_chars):
    """Join the leading prose paragraphs of a doc block, capped at max_chars."""
    paragraphs = []
    current = []
    for line in lines:
        if line.strip() == '':
            if current:
                paragraphs.append(' '.join(current))
                current = []
            continue
        current.append(line.strip())
    if current:
        paragraphs.append(' '.join(current))

    text = ''
    for paragraph in paragraphs:
        candidate = (text + ' ' + paragraph).strip() if text else paragraph
        if text and len(candidate) > max_chars:
            break
        text = candidate
    return na_truncate(na_clean_yard_markup(na_collapse_whitespace(text)), max_chars)

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Doc Comment Parsing
# -----------------------------------------------------------------------------

def na_parse_doc_block(comment_lines):
    """Split one YARD comment block into prose lines and @tag entries."""
    prose_lines = []
    tags = []
    current_tag = None

    for raw_line in comment_lines:
        tag_match = NA_TAG_LINE.match(raw_line)
        if tag_match:
            current_tag = {
                'indent': len(tag_match.group(1)),
                'tag': tag_match.group(2),
                'lines': [tag_match.group(3)]
            }
            tags.append(current_tag)
            continue

        if current_tag is None:
            prose_lines.append(raw_line)
        else:
            current_tag['lines'].append(raw_line)

    return prose_lines, tags


def na_tag_text(tag_entry):
    return na_clean_yard_markup(na_collapse_whitespace(' '.join(tag_entry['lines'])))


def na_parse_param_tag(tag_entry):
    text = na_tag_text(tag_entry)
    types = ''
    type_match = re.match(r'^\[([^\]]*)\]\s*(.*)$', text)
    if type_match:
        types, text = type_match.group(1), type_match.group(2)

    name_match = re.match(r'^([A-Za-z_*&][\w]*)\s*(.*)$', text)
    if not name_match:
        return None
    name, description = name_match.group(1), name_match.group(2)

    if not types:
        trailing_type = re.match(r'^\[([^\]]*)\]\s*(.*)$', description)
        if trailing_type:
            types, description = trailing_type.group(1), trailing_type.group(2)

    return {
        'name': name,
        'types': types,
        'desc': na_truncate(description, NA_PARAM_DESC_MAX_CHARS)
    }


def na_parse_return_tag(tag_entry):
    text = na_tag_text(tag_entry)
    type_match = re.match(r'^\[([^\]]*)\]\s*(.*)$', text)
    if type_match:
        return {'types': type_match.group(1), 'desc': na_truncate(type_match.group(2), NA_RETURN_DESC_MAX_CHARS)}
    return {'types': '', 'desc': na_truncate(text, NA_RETURN_DESC_MAX_CHARS)}


def na_parse_option_tag(tag_entry):
    """'@option options [Type] :key (default) description' -> {hash, key, types, desc}."""
    text = na_tag_text(tag_entry)
    match = re.match(r'^(\w+)\s+(?:\[([^\]]*)\]\s*)?:?(\w+)\s*(.*)$', text)
    if not match:
        return None
    return {
        'hash': match.group(1),
        'key': match.group(3),
        'types': match.group(2) or '',
        'desc': na_truncate(match.group(4), NA_PARAM_DESC_MAX_CHARS)
    }


def na_example_text(tag_entry):
    lines = tag_entry['lines']
    title = lines[0].strip()
    body_lines = lines[1:]
    indents = [len(line) - len(line.lstrip()) for line in body_lines if line.strip()]
    shift = min(indents) if indents else 0
    body = '\n'.join(line[shift:] if len(line) >= shift else line.strip() for line in body_lines).strip('\n')
    text = (title + '\n' + body).strip() if title else body
    if len(text) > NA_EXAMPLE_MAX_CHARS:
        text = text[:NA_EXAMPLE_MAX_CHARS].rsplit('\n', 1)[0] + '\n# ...'
    return text


def na_build_method_record(name, scope, def_signature, comment_lines):
    prose_lines, tags = na_parse_doc_block(comment_lines)
    record = {
        'name': name,
        'scope': scope,
        'signatures': [],
        'version': '',
        'summary': na_first_paragraphs(prose_lines, NA_SUMMARY_MAX_CHARS),
        'params': [],
        'returns': None
    }

    seen_params = set()
    for tag_entry in tags:
        tag_name = tag_entry['tag']
        if tag_name == 'overload':
            record['signatures'].append(na_collapse_whitespace(tag_entry['lines'][0]))
        elif tag_name == 'param':
            param = na_parse_param_tag(tag_entry)
            if param and param['name'] not in seen_params:
                seen_params.add(param['name'])
                record['params'].append(param)
        elif tag_name == 'option':
            option = na_parse_option_tag(tag_entry)
            if option and all(existing['key'] != option['key'] for existing in record.get('options', [])):
                record.setdefault('options', []).append(option)
        elif tag_name == 'return' and record['returns'] is None:
            record['returns'] = na_parse_return_tag(tag_entry)
        elif tag_name == 'version' and not record['version']:
            record['version'] = na_collapse_whitespace(tag_entry['lines'][0])
        elif tag_name == 'deprecated':
            record['deprecated'] = na_truncate(na_tag_text(tag_entry), NA_PARAM_DESC_MAX_CHARS) or 'deprecated'
        elif tag_name == 'raise':
            record.setdefault('raises', []).append(na_truncate(na_tag_text(tag_entry), NA_PARAM_DESC_MAX_CHARS))
        elif tag_name == 'note':
            record.setdefault('notes', []).append(na_truncate(na_tag_text(tag_entry), NA_PARAM_DESC_MAX_CHARS))
        elif tag_name == 'bug':
            record.setdefault('bugs', []).append(na_truncate(na_tag_text(tag_entry), NA_PARAM_DESC_MAX_CHARS))
        elif tag_name == 'example' and 'example' not in record:
            record['example'] = na_example_text(tag_entry)

    if not record['signatures']:
        record['signatures'].append(name + (def_signature or ''))
    if record['returns'] is None:
        del record['returns']
    return record

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Stub File Parsing
# -----------------------------------------------------------------------------

def na_parse_stub_file(file_path, classes):
    with open(file_path, encoding='utf-8') as handle:
        lines = handle.read().split('\n')

    current_class = None
    comment_lines = []

    for line in lines:
        stripped = line.strip()
        if stripped.startswith('#'):
            comment_lines.append(re.sub(r'^\s*# ?', '', line))
            continue

        class_match = NA_CLASS_LINE.match(line)
        if class_match:
            full_name = class_match.group(2)
            prose_lines, tags = na_parse_doc_block(comment_lines)
            version = ''
            for tag_entry in tags:
                if tag_entry['tag'] == 'version':
                    version = na_collapse_whitespace(tag_entry['lines'][0])
                    break
            entry = classes.setdefault(full_name, {
                'kind': class_match.group(1),
                'superclass': class_match.group(3) or '',
                'includes': [],
                'version': version,
                'summary': '',
                'constants': [],
                'methods': []
            })
            if not entry['summary']:
                entry['summary'] = na_first_paragraphs(prose_lines, NA_SUMMARY_MAX_CHARS)
            if class_match.group(3) and not entry['superclass']:
                entry['superclass'] = class_match.group(3)
            current_class = full_name
            comment_lines = []
            continue

        if current_class is None:
            # _top_level.rb declares global constants (PAGE_USE_ALL, TextAlignLeft,
            # SnapTo_Arbitrary, IDENTITY...) outside any class.
            top_constant = NA_CONSTANT_LINE.match(line)
            if top_constant:
                top_entry = classes.setdefault(NA_TOP_LEVEL_KEY, {
                    'kind': 'top_level',
                    'superclass': '',
                    'includes': [],
                    'version': '',
                    'summary': 'Global constants defined by SketchUp at the top level (Object).',
                    'constants': [],
                    'methods': []
                })
                top_entry['constants'].append(top_constant.group(1))
            comment_lines = []
            continue

        def_match = NA_DEF_LINE.match(line)
        if def_match:
            scope = 'class' if def_match.group(1) else 'instance'
            record = na_build_method_record(def_match.group(2), scope, def_match.group(3), comment_lines)
            classes[current_class]['methods'].append(record)
            comment_lines = []
            continue

        constant_match = NA_CONSTANT_LINE.match(line)
        if constant_match:
            classes[current_class]['constants'].append(constant_match.group(1))
            comment_lines = []
            continue

        include_match = NA_INCLUDE_LINE.match(line)
        if include_match:
            classes[current_class]['includes'].append(include_match.group(1))
            comment_lines = []
            continue

        if stripped == '' and comment_lines:
            continue
        comment_lines = []


def na_parse_all_stubs(stubs_dir):
    classes = {}
    for folder, _subfolders, files in os.walk(stubs_dir):
        for file_name in sorted(files):
            if file_name.endswith('.rb'):
                na_parse_stub_file(os.path.join(folder, file_name), classes)
    for entry in classes.values():
        entry['methods'].sort(key=lambda method: (method['scope'] != 'class', method['name']))
        entry['constants'].sort()
    return dict(sorted(classes.items()))

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Enumeration Extraction (valid values documented by SketchUp)
# -----------------------------------------------------------------------------

def na_raw_doc_for(stub_path, anchor_regex):
    """Return the raw comment block immediately above the first line matching anchor_regex."""
    with open(stub_path, encoding='utf-8') as handle:
        lines = handle.read().split('\n')
    for index, line in enumerate(lines):
        if re.search(anchor_regex, line):
            block = []
            cursor = index - 1
            while cursor >= 0 and lines[cursor].strip().startswith('#'):
                block.insert(0, re.sub(r'^\s*# ?', '', lines[cursor]))
                cursor -= 1
            return block
    return []


def na_extract_send_actions(stubs_dir):
    block = na_raw_doc_for(os.path.join(stubs_dir, 'Sketchup.rb'), r'def self\.send_action\(')
    supported = []
    added_in = {}
    removed = []
    mode = 'base'
    mode_version = ''
    for line in block:
        text = line.strip()
        added_match = re.match(r'^Added in (SketchUp [\d.]+)\+?:', text)
        removed_match = re.match(r'^Removed in (SketchUp [\d.]+)\+?:', text)
        if added_match:
            mode, mode_version = 'added', added_match.group(1)
            continue
        if removed_match:
            mode, mode_version = 'removed', removed_match.group(1)
            continue
        if text.startswith('On the PC only'):
            break
        action_match = re.match(r'^- ([A-Za-z0-9]+:)$', text)
        if not action_match:
            continue
        action = action_match.group(1)
        if mode == 'removed':
            removed.append({'action': action, 'removed_in': mode_version})
            continue
        if action not in supported:
            supported.append(action)
        if mode == 'added':
            added_in[action] = mode_version
    removed_names = {entry['action'] for entry in removed}
    return {
        'supported': [action for action in supported if action not in removed_names],
        'added_in': added_in,
        'removed': removed,
        'note': 'Named actions only. The numeric codes in the same doc are officially unsupported and are deliberately excluded.'
    }


def na_extract_keyed_list(stub_path, anchor_regex):
    """Parse '- +Key+' bullet lists with 'Added in SketchUp N:' section headers."""
    block = na_raw_doc_for(stub_path, anchor_regex)
    keys = []
    since = 'SketchUp 6.0'
    removed_mode = False
    for line in block:
        text = line.strip()
        added_match = re.match(r'^Added in (SketchUp [\d.]+)', text)
        removed_match = re.match(r'^Removed in (SketchUp [\d.]+)', text)
        if added_match:
            since, removed_mode = added_match.group(1), False
            continue
        if removed_match:
            removed_mode = True
            continue
        key_match = re.match(r'^- \+([A-Za-z_]+)\+\s*(.*)$', text)
        if key_match:
            record = {'key': key_match.group(1), 'since': since}
            if key_match.group(2):
                record['note'] = na_clean_yard_markup(key_match.group(2))
            if removed_mode:
                record['removed'] = True
            keys.append(record)
    return keys


def na_extract_option_pages(pages_path):
    """Parse pages/exporter_options.md or importer_options.md into {format: {option: note}}.

    '##' headings are formats; '###' headings are variants of the format above
    them (IFC has one option set for SketchUp 2026+ and one for older versions).
    A format documented as taking no options is kept with an empty option map.
    """
    formats = {}
    current_format = None
    parent_format = None
    with open(pages_path, encoding='utf-8') as handle:
        for line in handle:
            heading = re.match(r'^(##+)\s+(.*)$', line)
            if heading:
                title = heading.group(2).strip()
                if len(heading.group(1)) == 2:
                    parent_format = title
                    current_format = title
                else:
                    formats.pop(parent_format, None)
                    current_format = '%s - %s' % (parent_format, title)
                formats.setdefault(current_format, {})
                continue
            stripped = line.strip()
            if current_format and re.match(r'^-\s+No options', stripped):
                formats[current_format] = {}
                continue
            option = re.match(r'^-\s+`:?([a-z_]+)`\s*(.*)$', stripped)
            if option and current_format:
                formats[current_format][option.group(1)] = na_clean_yard_markup(option.group(2).lstrip('- ').strip())
                continue
            values = re.match(r'^-\s+values:\s*(.*)$', stripped)
            if values and current_format and formats[current_format]:
                last_key = list(formats[current_format].keys())[-1]
                formats[current_format][last_key] += ' Values: ' + values.group(1).replace('`', '')
    formats.pop('Note', None)
    formats.pop('Exporter Options', None)
    formats.pop('Importer Options', None)
    return formats

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Output
# -----------------------------------------------------------------------------

def na_git_revision(repo_dir):
    try:
        output = subprocess.check_output(
            ['git', '-C', repo_dir, 'log', '-1', '--format=%H|%cs'],
            stderr=subprocess.DEVNULL
        ).decode('utf-8').strip()
        commit, date = output.split('|')
        return commit, date
    except (OSError, subprocess.CalledProcessError, ValueError):
        return 'unknown', 'unknown'


def na_highest_version(classes):
    def version_key(text):
        numbers = re.findall(r'\d+', text)
        return [int(number) for number in numbers] if numbers else [0]

    versions = [method.get('version', '') for entry in classes.values() for method in entry['methods']]
    versions = [version for version in versions if version.startswith('SketchUp')]
    return max(versions, key=version_key) if versions else ''


def Na__ApiIndexBuilder__Build(stubs_repo_dir, output_path):
    stubs_dir = os.path.join(stubs_repo_dir, 'lib', 'sketchup-api-stubs', 'stubs')
    pages_dir = os.path.join(stubs_repo_dir, 'pages')
    if not os.path.isdir(stubs_dir):
        raise SystemExit('Stubs folder not found: ' + stubs_dir + ' (clone https://github.com/SketchUp/ruby-api-stubs first)')

    classes = na_parse_all_stubs(stubs_dir)
    commit, commit_date = na_git_revision(stubs_repo_dir)
    method_count = sum(len(entry['methods']) for entry in classes.values())

    index = {
        'schema': NA_INDEX_SCHEMA_VERSION,
        'source': {
            'repo': 'https://github.com/SketchUp/ruby-api-stubs',
            'commit': commit,
            'commit_date': commit_date,
            'license': 'MIT License, Copyright (c) 2016-2019 SketchUp. Doc text reproduced from the MIT-licensed stubs.',
            'docs_site': 'https://ruby.sketchup.com/'
        },
        'generated_by': 'Na__SketchUpMcp__ApiIndexBuilder__.py',
        'generated_at': datetime.date.today().isoformat(),
        'api_highest_version': na_highest_version(classes),
        'counts': {'classes': len(classes), 'methods': method_count},
        'enumerations': {
            'send_action': na_extract_send_actions(stubs_dir),
            'rendering_options_keys': na_extract_keyed_list(
                os.path.join(stubs_dir, 'Sketchup', 'RenderingOptions.rb'), r'^class Sketchup::RenderingOptions'),
            'shadow_info_keys': na_extract_keyed_list(
                os.path.join(stubs_dir, 'Sketchup', 'ShadowInfo.rb'), r'^class Sketchup::ShadowInfo'),
            'exporter_options': na_extract_option_pages(os.path.join(pages_dir, 'exporter_options.md')),
            'importer_options': na_extract_option_pages(os.path.join(pages_dir, 'importer_options.md'))
        },
        'classes': classes
    }

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, 'w', encoding='utf-8', newline='\n') as handle:
        json.dump(index, handle, ensure_ascii=False, separators=(',', ':'))
        handle.write('\n')
    return index


def na_main():
    parser = argparse.ArgumentParser(description='Build the SketchUp Ruby API index from ruby-api-stubs.')
    parser.add_argument('--stubs', required=True, help='Path to a clone of github.com/SketchUp/ruby-api-stubs')
    parser.add_argument('--out', default=NA_DEFAULT_OUTPUT_PATH, help='Output JSON path')
    arguments = parser.parse_args()
    index = Na__ApiIndexBuilder__Build(os.path.abspath(arguments.stubs), os.path.abspath(arguments.out))
    size_kb = os.path.getsize(arguments.out) / 1024.0
    enumerations = index['enumerations']
    print('Index written: %s (%.0f KB)' % (arguments.out, size_kb))
    print('Classes: %d  Methods: %d  Highest @version: %s' % (
        index['counts']['classes'], index['counts']['methods'], index['api_highest_version']))
    print('send_action names: %d  rendering keys: %d  shadow keys: %d  exporters: %d  importers: %d' % (
        len(enumerations['send_action']['supported']),
        len(enumerations['rendering_options_keys']),
        len(enumerations['shadow_info_keys']),
        len(enumerations['exporter_options']),
        len(enumerations['importer_options'])))


if __name__ == '__main__':
    na_main()

# =============================================================================
# END OF FILE
# =============================================================================
