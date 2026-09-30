# =============================================================================
# NA SKETCHUP MCP - BRIDGE HELPERS - PARAMS
# =============================================================================
#
# FILE       : Na__SketchUpMcp__BridgeHelpers__Params__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Params
# PURPOSE    : Typed, validated access to a request's parameters
# CREATED    : 2026
#
# TWO LAYERS OF VALIDATION:
# The Python server checks every call against the tool's JSON input schema
# before it reaches SketchUp. These helpers are the second layer: they run on
# values the schema cannot see (batch steps after $ref substitution, ranges that
# depend on the model) and they refuse with the fix named rather than clamping.
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Params

# -----------------------------------------------------------------------------
# REGION | Presence
# -----------------------------------------------------------------------------

        def self.Na__Params__Has(params, key)
            params.key?(key.to_s) && !params[key.to_s].nil?
        end

        def self.Na__Params__Required(params, key)
            return params[key.to_s] if self.Na__Params__Has(params, key)

            raise Na__McpError.new('invalid_params', "Missing required parameter '#{key}'.",
                                   "Add '#{key}' to the arguments (see the tool's input schema).")
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Scalars
# -----------------------------------------------------------------------------

        def self.Na__Params__String(params, key, default_value = nil, required: false, allow_empty: false)
            value = required ? self.Na__Params__Required(params, key) : params.fetch(key.to_s, default_value)
            return default_value if value.nil?
            unless value.is_a?(String)
                raise Na__McpError.new('invalid_params', "'#{key}' must be a string, got #{value.class}.", nil)
            end
            if value.strip.empty? && !allow_empty
                raise Na__McpError.new('invalid_params', "'#{key}' must not be empty.", nil)
            end

            value
        end

        def self.Na__Params__Integer(params, key, default_value = nil, required: false, min: nil, max: nil)
            value = required ? self.Na__Params__Required(params, key) : params.fetch(key.to_s, default_value)
            return default_value if value.nil?

            number = value.is_a?(Float) && value == value.floor ? value.to_i : value
            unless number.is_a?(Integer)
                raise Na__McpError.new('invalid_params', "'#{key}' must be a whole number, got #{value.inspect}.", nil)
            end

            na_check_range(key, number, min, max)
        end

        def self.Na__Params__Number(params, key, default_value = nil, required: false, min: nil, max: nil)
            value = required ? self.Na__Params__Required(params, key) : params.fetch(key.to_s, default_value)
            return default_value if value.nil?
            unless value.is_a?(Numeric) && value.to_f.finite?
                raise Na__McpError.new('invalid_params', "'#{key}' must be a number, got #{value.inspect}.", nil)
            end

            na_check_range(key, value.to_f, min, max)
        end

        def self.Na__Params__Boolean(params, key, default_value = false)
            value = params.fetch(key.to_s, default_value)
            return default_value if value.nil?
            return value if value == true || value == false

            raise Na__McpError.new('invalid_params', "'#{key}' must be true or false, got #{value.inspect}.", nil)
        end

        def self.Na__Params__Enum(params, key, allowed_values, default_value = nil, required: false)
            value = required ? self.Na__Params__Required(params, key) : params.fetch(key.to_s, default_value)
            return default_value if value.nil?
            return value if allowed_values.include?(value)

            raise Na__McpError.new('invalid_params', "'#{key}' is #{value.inspect}; it must be one of: #{allowed_values.join(', ')}.", nil)
        end

        def self.na_check_range(key, number, min, max)
            if (min && number < min) || (max && number > max)
                range_text = [min ? ">= #{min}" : nil, max ? "<= #{max}" : nil].compact.join(' and ')
                raise Na__McpError.new('invalid_params', "'#{key}' is #{number}; it must be #{range_text}.",
                                       'Values are refused, never clamped, so a typo cannot silently change the model.')
            end

            number
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Collections
# -----------------------------------------------------------------------------

        def self.Na__Params__Array(params, key, default_value = nil, required: false, min_items: nil, max_items: nil)
            value = required ? self.Na__Params__Required(params, key) : params.fetch(key.to_s, default_value)
            return default_value if value.nil?
            unless value.is_a?(Array)
                raise Na__McpError.new('invalid_params', "'#{key}' must be an array, got #{value.class}.", nil)
            end
            if min_items && value.length < min_items
                raise Na__McpError.new('invalid_params', "'#{key}' needs at least #{min_items} item(s), got #{value.length}.", nil)
            end
            if max_items && value.length > max_items
                raise Na__McpError.new('invalid_params', "'#{key}' allows at most #{max_items} item(s), got #{value.length}.", nil)
            end

            value
        end

        def self.Na__Params__IdArray(params, key, required: true)
            ids = self.Na__Params__Array(params, key, nil, required: required, min_items: required ? 1 : nil)
            return nil if ids.nil?

            ids.map do |value|
                number = value.is_a?(Float) && value == value.floor ? value.to_i : value
                unless number.is_a?(Integer)
                    raise Na__McpError.new('invalid_params', "'#{key}' must contain persistent ids (whole numbers), found #{value.inspect}.",
                                           'Use the "id" values returned by entity_query, outliner_tree or selection_get.')
                end

                number
            end
        end

        # [limit, offset] with the AppConfig defaults and ceiling.
        def self.Na__Params__Page(params)
            max_limit = Na__ConfigLoader.Na__ConfigLoader__Get('defaults', 'query_limit_max', 500).to_i
            default_limit = Na__ConfigLoader.Na__ConfigLoader__Get('defaults', 'query_limit', 50).to_i
            [self.Na__Params__Integer(params, 'limit', default_limit, min: 1, max: max_limit),
             self.Na__Params__Integer(params, 'offset', 0, min: 0)]
        end

        def self.Na__Params__Hash(params, key, default_value = nil, required: false)
            value = required ? self.Na__Params__Required(params, key) : params.fetch(key.to_s, default_value)
            return default_value if value.nil?
            return value if value.is_a?(Hash)

            raise Na__McpError.new('invalid_params', "'#{key}' must be an object, got #{value.class}.", nil)
        end

# endregion -------------------------------------------------------------------

    end # module Na__Params
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
