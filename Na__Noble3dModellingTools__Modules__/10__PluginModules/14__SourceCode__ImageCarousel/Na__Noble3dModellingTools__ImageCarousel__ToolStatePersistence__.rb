# =============================================================================
# NA NOBLE3D MODELLING TOOLS - IMAGE CAROUSEL - TOOL STATE PERSISTENCE
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__ImageCarousel__ToolStatePersistence__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__ImageCarousel__ToolStatePersistence
# PURPOSE    : Keep the Image Viewer's other tools' work in the model: the Count
#              tool's counts, the Perspective Angle tool's lines, angles,
#              guides and lens, and the Protractor's angles, so they come back
#              with it
# CREATED    : 11-Nov-2026
#
# DESIGN NOTES:
# - Beside MarkupPersistence and DimensionPersistence, built the same way, for
#   any tool listed in NA_TOOLS: each has its own model dictionary and undo
#   step name. One key per photo (its path under the model's image folder,
#   lower case, as the marks use), one versioned JSON string:
#     { "schema":1, "tool":"count", "name":"IMG_0001.jpg", "w":4032, "h":3024,
#       "state":{ ...the tool's own... } }
#   The tool (in the dialog) decides its state's shape; points are photo
#   pixels from the top-left, vanishing points homogeneous (x, y, w) in the
#   same frame. The viewer's Core does the converting both ways.
# - The dialog's Core sends a photo's state a moment after it changes, and
#   before another photo is shown. It is checked and held here (Queue) and
#   written by Flush, which the DialogManager runs with the marks', one undo
#   step per tool.
# - Nothing sent is trusted: only objects, arrays, finite numbers, short
#   strings, true, false and null, within depth and size limits. A null state
#   removes the photo's key, and the dictionary goes when it is empty.
#
# =============================================================================

require 'json'

module Na__Noble3dModellingTools
    module Na__ImageCarousel__ToolStatePersistence

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        unless const_defined?(:NA_TOOLS)
            NA_TOOLS = {
                'count' => { 'dict' => 'Na__Noble3dModellingTools__ImageCarousel__Counts', 'op' => 'Image Viewer: Counts' }.freeze,
                'angle' => { 'dict' => 'Na__Noble3dModellingTools__ImageCarousel__AngleGuides', 'op' => 'Image Viewer: Angle Guides' }.freeze,
                'protractor' => { 'dict' => 'Na__Noble3dModellingTools__ImageCarousel__Protractors', 'op' => 'Image Viewer: Protractor' }.freeze
            }.freeze
        end
        NA_STATE_SCHEMA    = 1 unless const_defined?(:NA_STATE_SCHEMA)
        NA_MAX_ENTRY_BYTES = 2_000_000 unless const_defined?(:NA_MAX_ENTRY_BYTES)
        NA_MAX_DEPTH       = 8 unless const_defined?(:NA_MAX_DEPTH)
        NA_MAX_ITEMS       = 10_000 unless const_defined?(:NA_MAX_ITEMS)   # per array or object
        NA_MAX_STRING      = 200 unless const_defined?(:NA_MAX_STRING)
        NA_MAX_DIMENSION   = 100_000 unless const_defined?(:NA_MAX_DIMENSION)

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        def self.Na__ImageCarousel__ToolStatePersistence__Tools
            NA_TOOLS.keys
        end

        # Check one photo's state for one tool and hold it for Flush. Returns
        # { 'ok' => true, 'tool', 'key', 'name', 'empty' } or { 'ok' => false, 'tool', 'path', 'error' }.
        def self.Na__ImageCarousel__ToolStatePersistence__Queue(payload, root)
            tool = nil
            path = nil
            data = payload.is_a?(String) ? JSON.parse(payload) : payload
            raise ArgumentError, 'the tool state was not sent as an object' unless data.is_a?(Hash)

            tool = data['tool'].to_s
            raise ArgumentError, "no such tool: #{tool}" unless NA_TOOLS.key?(tool)

            path = data['path'].to_s
            key  = Na__ImageCarousel__MarkupPersistence.Na__ImageCarousel__MarkupPersistence__KeyForPath(path, root)
            raise ArgumentError, 'the tool state has no photo path' if key.nil?

            name  = File.basename(path.strip.tr('\\', '/'))
            state = data['state'].nil? ? nil : na_clean(data['state'], 0)
            text  = nil
            unless state.nil?
                entry = { 'schema' => NA_STATE_SCHEMA, 'tool' => tool, 'name' => name,
                          'w' => na_dimension(data['w']), 'h' => na_dimension(data['h']), 'state' => state }
                text = JSON.generate(entry)
                raise ArgumentError, "too much to keep on one photo (#{text.bytesize} bytes)" if text.bytesize > NA_MAX_ENTRY_BYTES
            end

            na_pending(tool)[key] = { 'text' => text, 'name' => name }
            { 'ok' => true, 'tool' => tool, 'key' => key, 'name' => name, 'empty' => text.nil? }
        rescue JSON::ParserError, ArgumentError, TypeError => error
            puts "[Na__ImageCarousel] tool state not kept: #{error.message}"
            { 'ok' => false, 'tool' => tool, 'path' => path, 'error' => error.message }
        end

        def self.Na__ImageCarousel__ToolStatePersistence__HasPending
            NA_TOOLS.keys.any? { |tool| !na_pending(tool).empty? }
        end

        # Write everything held, one undo step per tool. Returns
        # { 'ok', 'saved' => [ { 'tool', 'key', 'name', 'written' } ], 'errors' => [...] }.
        def self.Na__ImageCarousel__ToolStatePersistence__Flush(model)
            return { 'ok' => false, 'error' => 'no model is open', 'saved' => [] } if model.nil? && Na__ImageCarousel__ToolStatePersistence__HasPending

            saved  = []
            errors = []
            NA_TOOLS.each do |tool, info|
                result = na_flush_tool(model, tool, info)
                saved.concat(result['saved'])
                errors << result['error'] unless result['ok']
            end
            { 'ok' => errors.empty?, 'saved' => saved, 'errors' => errors }
        end

        # The model's state for a folder's photos: { tool => { path => { 'w', 'h', 'state' } } }.
        # What is still held wins over the model.
        def self.Na__ImageCarousel__ToolStatePersistence__LoadForPaths(model, paths, root)
            found = {}
            NA_TOOLS.each do |tool, info|
                dict = model.nil? ? nil : model.attribute_dictionary(info['dict'])
                Array(paths).each do |path|
                    key = Na__ImageCarousel__MarkupPersistence.Na__ImageCarousel__MarkupPersistence__KeyForPath(path, root)
                    next if key.nil?

                    held  = na_pending(tool)[key]
                    text  = held ? held['text'] : (dict.nil? ? nil : dict[key])
                    entry = na_read_entry(text)
                    (found[tool] ||= {})[path.to_s] = entry if entry
                end
            end
            found
        rescue => error
            puts "[Na__ImageCarousel] read tool state from model failed: #{error.class}: #{error.message}"
            {}
        end

        def self.Na__ImageCarousel__ToolStatePersistence__DiscardPending
            @na_pending = {}
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Model Dictionary
# -----------------------------------------------------------------------------

        def self.na_pending(tool)
            @na_pending ||= {}
            @na_pending[tool] ||= {}
        end

        def self.na_flush_tool(model, tool, info)
            started = false
            pending = na_pending(tool)
            return { 'ok' => true, 'saved' => [] } if pending.empty?

            batch   = pending.dup
            changes = batch.select { |key, item| na_differs?(model, info['dict'], key, item['text']) }
            unless changes.empty?
                model.start_operation(info['op'], true)
                started = true
                changes.each { |key, item| na_write(model, info['dict'], key, item['text']) }
                model.commit_operation
                started = false
            end

            batch.each { |key, item| pending.delete(key) if pending[key].equal?(item) }
            { 'ok' => true, 'saved' => batch.map { |key, item| { 'tool' => tool, 'key' => key, 'name' => item['name'], 'written' => changes.key?(key) } } }
        rescue => error
            model.abort_operation if started
            puts "[Na__ImageCarousel] save #{tool} to model failed: #{error.class}: #{error.message}"
            { 'ok' => false, 'error' => "#{tool}: #{error.message}", 'saved' => [] }
        end

        def self.na_differs?(model, dict_name, key, text)
            if text.nil?
                dict = model.attribute_dictionary(dict_name)
                !dict.nil? && !dict[key].nil?
            else
                model.get_attribute(dict_name, key) != text
            end
        end

        def self.na_write(model, dict_name, key, text)
            unless text.nil?
                model.set_attribute(dict_name, key, text)
                return
            end

            dict = model.attribute_dictionary(dict_name)
            return if dict.nil?

            dict.delete_key(key)
            dict = model.attribute_dictionary(dict_name)
            return unless dict && dict.length.zero?

            all = model.attribute_dictionaries
            all.delete(dict_name) unless all.nil?
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Checking What The Dialog Sends
# -----------------------------------------------------------------------------

        # Plain JSON data only, within limits; raises ArgumentError otherwise.
        def self.na_clean(value, depth)
            raise ArgumentError, 'the tool state is nested too deep' if depth > NA_MAX_DEPTH

            case value
            when Hash
                raise ArgumentError, 'an object in the tool state is too big' if value.length > NA_MAX_ITEMS
                value.each_with_object({}) do |(k, v), out|
                    name = k.to_s
                    raise ArgumentError, 'a name in the tool state is too long' if name.length > 40
                    out[name] = na_clean(v, depth + 1)
                end
            when Array
                raise ArgumentError, 'a list in the tool state is too long' if value.length > NA_MAX_ITEMS
                value.map { |v| na_clean(v, depth + 1) }
            when Integer
                value
            when Float
                raise ArgumentError, 'a number in the tool state is not finite' unless value.finite?
                value
            when String
                raise ArgumentError, 'a string in the tool state is too long' if value.length > NA_MAX_STRING
                value
            when true, false, nil
                value
            else
                raise ArgumentError, "the tool state holds a #{value.class}"
            end
        end

        def self.na_dimension(value)
            number = value.is_a?(Numeric) ? value.to_f : nil
            ok = number && number.finite? && number >= 1 && number <= NA_MAX_DIMENSION
            raise ArgumentError, 'the photo size is missing or out of range' unless ok

            number.round
        end

        def self.na_read_entry(text)
            return nil unless text.is_a?(String) && !text.strip.empty?

            data = JSON.parse(text)
            return nil unless data.is_a?(Hash) && !data['state'].nil?
            return nil if data['schema'].to_i > NA_STATE_SCHEMA

            { 'w' => na_dimension(data['w']), 'h' => na_dimension(data['h']), 'state' => na_clean(data['state'], 0) }
        rescue JSON::ParserError, ArgumentError, TypeError
            nil
        end

# endregion -------------------------------------------------------------------

    end # module Na__ImageCarousel__ToolStatePersistence
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
