# =============================================================================
# NA SKETCHUP MCP - PYTHON SERVER - SCHEMA VALIDATOR
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Server__SchemaValidator__.py
# PURPOSE    : Check tool arguments against the tool's JSON input schema before
#              anything is sent to SketchUp
# CREATED    : 2026
#
# SCOPE:
# The registry schemas deliberately use a small, portable subset of JSON Schema
# (type, enum, required, properties, additionalProperties, items, min/max,
# minItems/maxItems, minLength/maxLength) so that every MCP client and model
# family understands them. This validator implements exactly that subset.
# Failures come back as tool errors (isError), per MCP 2025-11-25, so the model
# can read them and fix its call.
#
# BATCH REFERENCES:
# With allow_references=True a string "$<step>.<path>" is accepted wherever a
# value is expected; the bridge substitutes the real value before running.
#
# =============================================================================

import re

NA_REFERENCE = re.compile(r'^\$\d+(\.[A-Za-z0-9_]+)*$')
NA_MAX_ERRORS = 12


# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

def Na__SchemaValidator__Validate(schema, value, root_label='arguments', allow_references=False):
    """Return a list of human-readable problems (empty when the value is valid)."""
    errors = []
    na_validate(schema, value, root_label, errors, allow_references)
    return errors[:NA_MAX_ERRORS]


def Na__SchemaValidator__JsonType(value):
    if value is None:
        return 'null'
    if isinstance(value, bool):
        return 'boolean'
    if isinstance(value, int):
        return 'integer'
    if isinstance(value, float):
        return 'number'
    if isinstance(value, str):
        return 'string'
    if isinstance(value, list):
        return 'array'
    if isinstance(value, dict):
        return 'object'
    return type(value).__name__

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Validation
# -----------------------------------------------------------------------------

def na_type_matches(expected, value):
    if expected == 'integer':
        return (isinstance(value, int) and not isinstance(value, bool)) or (isinstance(value, float) and value.is_integer())
    if expected == 'number':
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    if expected == 'string':
        return isinstance(value, str)
    if expected == 'boolean':
        return isinstance(value, bool)
    if expected == 'array':
        return isinstance(value, list)
    if expected == 'object':
        return isinstance(value, dict)
    if expected == 'null':
        return value is None
    return True


def na_short(value):
    text = repr(value)
    return text if len(text) <= 60 else text[:57] + '...'


def na_validate(schema, value, label, errors, allow_references):
    if len(errors) >= NA_MAX_ERRORS or not isinstance(schema, dict) or not schema:
        return
    if allow_references and isinstance(value, str) and NA_REFERENCE.match(value):
        return

    expected = schema.get('type')
    if expected is not None:
        expected_list = expected if isinstance(expected, list) else [expected]
        if not any(na_type_matches(item, value) for item in expected_list):
            errors.append('%s must be %s, got %s %s.' % (
                label, ' or '.join(expected_list), Na__SchemaValidator__JsonType(value), na_short(value)))
            return

    if 'enum' in schema and value not in schema['enum']:
        options = schema['enum']
        shown = ', '.join(repr(option) for option in options[:25]) + (' ...' if len(options) > 25 else '')
        errors.append('%s is %s; allowed: %s.' % (label, na_short(value), shown))
        return

    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if 'minimum' in schema and value < schema['minimum']:
            errors.append('%s is %s; it must be >= %s.' % (label, value, schema['minimum']))
        if 'maximum' in schema and value > schema['maximum']:
            errors.append('%s is %s; it must be <= %s.' % (label, value, schema['maximum']))

    if isinstance(value, str):
        if 'minLength' in schema and len(value) < schema['minLength']:
            errors.append('%s is shorter than %d characters.' % (label, schema['minLength']))
        if 'maxLength' in schema and len(value) > schema['maxLength']:
            errors.append('%s is longer than %d characters.' % (label, schema['maxLength']))

    if isinstance(value, list):
        na_validate_array(schema, value, label, errors, allow_references)

    if isinstance(value, dict):
        na_validate_object(schema, value, label, errors, allow_references)


def na_validate_array(schema, value, label, errors, allow_references):
    if 'minItems' in schema and len(value) < schema['minItems']:
        errors.append('%s needs at least %d item(s), got %d.' % (label, schema['minItems'], len(value)))
    if 'maxItems' in schema and len(value) > schema['maxItems']:
        errors.append('%s allows at most %d item(s), got %d.' % (label, schema['maxItems'], len(value)))
    item_schema = schema.get('items')
    if isinstance(item_schema, dict):
        for index, item in enumerate(value):
            na_validate(item_schema, item, '%s[%d]' % (label, index), errors, allow_references)
            if len(errors) >= NA_MAX_ERRORS:
                return


def na_validate_object(schema, value, label, errors, allow_references):
    properties = schema.get('properties', {})
    for required in schema.get('required', []):
        if required not in value or value[required] is None:
            errors.append('%s.%s is required.' % (label, required))
    if schema.get('additionalProperties') is False:
        unknown = [key for key in value if key not in properties]
        if unknown:
            errors.append('%s has unknown argument(s) %s; valid: %s.' % (
                label, ', '.join(unknown), ', '.join(sorted(properties.keys()))))
    for key, item in value.items():
        if key in properties and item is not None:
            na_validate(properties[key], item, '%s.%s' % (label, key), errors, allow_references)

# endregion -------------------------------------------------------------------

# =============================================================================
# END OF FILE
# =============================================================================
