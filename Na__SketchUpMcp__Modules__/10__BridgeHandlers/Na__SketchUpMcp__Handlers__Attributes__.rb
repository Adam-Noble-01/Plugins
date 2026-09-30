# =============================================================================
# NA SKETCHUP MCP - HANDLERS - ATTRIBUTES
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__Attributes__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__Attributes
# PURPOSE    : attributes_get, attributes_set (attribute dictionaries on
#              entities, component definitions and the model itself)
# CREATED    : 2026
#
# WHERE AGENTS KEEP STATE:
# Attribute dictionaries travel inside the .skp, so they are the right place
# for an agent (or a Na__ plugin) to record project data on the geometry it
# describes: element type, spec codes, source files. "model": true targets the
# model's own dictionaries (Model is an Entity).
#
# VALUE TYPES:
# SketchUp stores booleans, integers, floats, strings, nil and arrays of those.
# Hashes are refused (SketchUp cannot store them); JSON-encode them first.
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Handlers__Attributes

# -----------------------------------------------------------------------------
# REGION | attributes_get
# -----------------------------------------------------------------------------

        def self.Na__Handlers__Attributes__Get(params, ctx)
            targets = na_targets(params, ctx)
            dictionary = params['dictionary']
            key = params['key']
            max_chars = Na__ConfigLoader.Na__ConfigLoader__Get('defaults', 'max_attribute_value_chars', 2000).to_i
            records = targets.map do |target|
                {
                    'target'       => na_target_label(target),
                    'dictionaries' => Na__Serializer.Na__Serializer__AttributeDictionaries(target, dictionary, key, max_chars)
                }
            end
            { 'targets' => records }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | attributes_set
# -----------------------------------------------------------------------------

        def self.Na__Handlers__Attributes__Set(params, ctx)
            targets = na_targets(params, ctx)
            dictionary = Na__Params.Na__Params__String(params, 'dictionary', nil, required: true)

            if Na__Params.Na__Params__Boolean(params, 'delete_dictionary', false)
                targets.each { |target| target.delete_attribute(dictionary) }
                return { 'deleted_dictionary' => dictionary, 'targets' => targets.length }
            end

            values = Na__Params.Na__Params__Hash(params, 'values', nil, required: true)
            written = 0
            deleted = 0
            targets.each do |target|
                values.each do |attribute_key, value|
                    if value.nil?
                        target.delete_attribute(dictionary, attribute_key.to_s)
                        deleted += 1
                    else
                        target.set_attribute(dictionary, attribute_key.to_s, na_storable(value, attribute_key))
                        written += 1
                    end
                end
            end
            { 'dictionary' => dictionary, 'written' => written, 'deleted' => deleted, 'targets' => targets.length,
              'summary' => "Wrote #{written} and deleted #{deleted} attribute value(s) on #{targets.length} target(s)." }
        end

        def self.na_storable(value, key)
            case value
            when Hash
                raise Na__McpError.new('invalid_params', "values.#{key} is an object; SketchUp attributes cannot store objects.",
                                       'Store it as a JSON string, or split it into several keys.')
            when Array
                value.map { |item| na_storable(item, key) }
            else
                value
            end
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Targets
# -----------------------------------------------------------------------------

        # ids (entities or definitions) and/or model:true.
        def self.na_targets(params, ctx)
            targets = []
            targets << ctx[:model] if Na__Params.Na__Params__Boolean(params, 'model', false)
            ids = Na__Params.Na__Params__IdArray(params, 'ids', required: false)
            targets.concat(Na__EntityResolver.Na__EntityResolver__RequireEntities(ctx[:model], ids)) if ids
            return targets unless targets.empty?

            raise Na__McpError.new('invalid_params', 'No target.', 'Pass ids (entities or component definitions) and/or model: true.')
        end

        def self.na_target_label(target)
            return { 'type' => 'Model', 'title' => target.title.to_s } if target.is_a?(Sketchup::Model)

            label = { 'id' => target.persistent_id, 'type' => Na__EntityResolver.Na__EntityResolver__TypeName(target) }
            name = Na__EntityResolver.Na__EntityResolver__DisplayName(target)
            label['name'] = name unless name.empty?
            label
        end

# endregion -------------------------------------------------------------------

    end # module Na__Handlers__Attributes
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
