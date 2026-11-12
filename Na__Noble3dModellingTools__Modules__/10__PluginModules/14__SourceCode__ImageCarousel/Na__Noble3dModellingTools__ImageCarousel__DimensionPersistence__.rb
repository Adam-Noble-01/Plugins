# =============================================================================
# NA NOBLE3D MODELLING TOOLS - IMAGE CAROUSEL - DIMENSION PERSISTENCE
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__ImageCarousel__DimensionPersistence__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__ImageCarousel__DimensionPersistence
# PURPOSE    : Keep the Image Viewer's dimensions and reference scale in the
#              model, so they come back with it
# CREATED    : 11-Nov-2026
#
# DESIGN NOTES:
# - Same approach as MarkupPersistence, beside it in its own dictionary: one
#   key per photo (its path under the model's image folder, lower case, the
#   same key the marks use), each holding one versioned JSON string:
#     { "schema":1, "name":"IMG_0001.jpg", "w":4032, "h":3024,
#       "dims":[ [ax, ay, bx, by], ... ],
#       "scale":{ "pxPerMm":0.512, "unit":"mm", "ref":[ax, ay, bx, by, mm] } }
#   Points are photo pixels, origin at the photo's top-left; w and h are the
#   photo's own size, so a copy of the photo at another size can take them
#   scaled. scale is absent until a reference length has been set.
# - The dialog sends a photo's dimensions after every change; they are checked
#   and held here (Queue) and written in one undo step by Flush, which the
#   DialogManager runs with the markup's, a moment after the last change and
#   when the dialog closes.
# - Nothing the dialog sends is trusted. A photo with no dimensions and no
#   reference has no key; the dictionary goes when it is empty.
#
# =============================================================================

require 'json'

module Na__Noble3dModellingTools
    module Na__ImageCarousel__DimensionPersistence

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_DICTIONARY_NAME = 'Na__Noble3dModellingTools__ImageCarousel__Dimensions'.freeze unless const_defined?(:NA_DICTIONARY_NAME)
        NA_STATE_SCHEMA    = 1 unless const_defined?(:NA_STATE_SCHEMA)
        NA_OPERATION_NAME  = 'Image Viewer: Dimensions'.freeze unless const_defined?(:NA_OPERATION_NAME)

        NA_UNITS           = %w[mm cm m].freeze unless const_defined?(:NA_UNITS)
        NA_DECIMALS        = 3 unless const_defined?(:NA_DECIMALS)
        NA_MAX_DIMS        = 2000 unless const_defined?(:NA_MAX_DIMS)          # per photo
        NA_MAX_DIMENSION   = 100_000 unless const_defined?(:NA_MAX_DIMENSION)  # photo pixels
        NA_MAX_COORDINATE  = 1_000_000.0 unless const_defined?(:NA_MAX_COORDINATE)
        NA_MAX_MM          = 1_000_000_000.0 unless const_defined?(:NA_MAX_MM)

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        def self.Na__ImageCarousel__DimensionPersistence__KeyForPath(path, root)
            Na__ImageCarousel__MarkupPersistence.Na__ImageCarousel__MarkupPersistence__KeyForPath(path, root)
        end

        # Check one photo's dimensions as the dialog sent them and hold them for
        # Flush. Returns { 'ok' => true, 'key', 'name', 'dims', 'scale' } or
        # { 'ok' => false, 'path', 'error' }.
        def self.Na__ImageCarousel__DimensionPersistence__Queue(payload, root)
            path = nil
            data = payload.is_a?(String) ? JSON.parse(payload) : payload
            raise ArgumentError, 'the dimensions were not sent as an object' unless data.is_a?(Hash)

            path = data['path'].to_s
            key  = Na__ImageCarousel__DimensionPersistence__KeyForPath(path, root)
            raise ArgumentError, 'the dimensions have no photo path' if key.nil?

            entry = na_clean_entry(data, File.basename(path.to_s.strip.tr('\\', '/')))
            text  = na_empty?(entry) ? nil : JSON.generate(entry)
            na_pending[key] = { 'text' => text, 'name' => entry['name'], 'dims' => entry['dims'].length, 'scale' => entry.key?('scale') }
            { 'ok' => true, 'key' => key, 'name' => entry['name'], 'dims' => entry['dims'].length, 'scale' => entry.key?('scale') }
        rescue JSON::ParserError, ArgumentError, TypeError => error
            puts "[Na__ImageCarousel] dimensions not kept: #{error.message}"
            { 'ok' => false, 'path' => path, 'error' => error.message }
        end

        def self.Na__ImageCarousel__DimensionPersistence__HasPending
            !na_pending.empty?
        end

        # Write everything held to the model in one undo step.
        def self.Na__ImageCarousel__DimensionPersistence__Flush(model)
            started = false
            pending = na_pending
            return { 'ok' => true, 'saved' => [] } if pending.empty?
            return { 'ok' => false, 'error' => 'no model is open', 'saved' => [] } if model.nil?

            batch   = pending.dup
            changes = batch.select { |key, item| na_differs?(model, key, item['text']) }
            unless changes.empty?
                model.start_operation(NA_OPERATION_NAME, true)
                started = true
                changes.each { |key, item| na_write(model, key, item['text']) }
                model.commit_operation
                started = false
            end

            batch.each { |key, item| pending.delete(key) if pending[key].equal?(item) }
            saved = batch.map do |key, item|
                { 'key' => key, 'name' => item['name'], 'dims' => item['dims'], 'scale' => item['scale'], 'written' => changes.key?(key) }
            end
            { 'ok' => true, 'saved' => saved }
        rescue => error
            model.abort_operation if started
            puts "[Na__ImageCarousel] save dimensions to model failed: #{error.class}: #{error.message}"
            { 'ok' => false, 'error' => error.message, 'saved' => [] }
        end

        # The model's dimensions for a folder's photos, { path => entry }, for
        # the photos that have any. What is still held wins over the model.
        def self.Na__ImageCarousel__DimensionPersistence__LoadForPaths(model, paths, root)
            found = {}
            dict  = model.nil? ? nil : model.attribute_dictionary(NA_DICTIONARY_NAME)

            Array(paths).each do |path|
                key = Na__ImageCarousel__DimensionPersistence__KeyForPath(path, root)
                next if key.nil?

                held  = na_pending[key]
                text  = held ? held['text'] : (dict.nil? ? nil : dict[key])
                entry = na_read_entry(text)
                found[path.to_s] = entry if entry
            end
            found
        rescue => error
            puts "[Na__ImageCarousel] read dimensions from model failed: #{error.class}: #{error.message}"
            {}
        end

        def self.Na__ImageCarousel__DimensionPersistence__DiscardPending
            na_pending.clear
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Model Dictionary
# -----------------------------------------------------------------------------

        def self.na_pending
            @na_pending ||= {}
        end

        def self.na_differs?(model, key, text)
            if text.nil?
                dict = model.attribute_dictionary(NA_DICTIONARY_NAME)
                !dict.nil? && !dict[key].nil?
            else
                model.get_attribute(NA_DICTIONARY_NAME, key) != text
            end
        end

        def self.na_write(model, key, text)
            unless text.nil?
                model.set_attribute(NA_DICTIONARY_NAME, key, text)
                return
            end

            dict = model.attribute_dictionary(NA_DICTIONARY_NAME)
            return if dict.nil?

            dict.delete_key(key)
            dict = model.attribute_dictionary(NA_DICTIONARY_NAME)
            return unless dict && dict.length.zero?

            all = model.attribute_dictionaries
            all.delete(NA_DICTIONARY_NAME) unless all.nil?
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Checking What The Dialog Sends
# -----------------------------------------------------------------------------

        def self.na_clean_entry(data, name)
            raw = data['dims']
            raise ArgumentError, 'the dimensions are missing' unless raw.is_a?(Array)
            raise ArgumentError, "too many dimensions on one photo (#{raw.length})" if raw.length > NA_MAX_DIMS

            entry = {
                'schema' => NA_STATE_SCHEMA,
                'name'   => name,
                'w'      => na_dimension(data['w']),
                'h'      => na_dimension(data['h']),
                'dims'   => raw.map { |dim| na_clean_line(dim, 4) }.compact
            }
            scale = na_clean_scale(data['scale'])
            entry['scale'] = scale if scale
            entry
        end

        def self.na_empty?(entry)
            entry['dims'].empty? && !entry.key?('scale')
        end

        # [ax, ay, bx, by] (or [ax, ay, bx, by, mm] for the reference), checked.
        def self.na_clean_line(raw, length)
            return nil unless raw.is_a?(Array) && raw.length == length

            values = raw.each_with_index.map do |value, i|
                na_number(value, i < 4 ? NA_MAX_COORDINATE : NA_MAX_MM)
            end
            values.any?(&:nil?) ? nil : values
        end

        def self.na_clean_scale(raw)
            return nil unless raw.is_a?(Hash)

            px_per_mm = na_number(raw['pxPerMm'], NA_MAX_COORDINATE, 9)
            return nil unless px_per_mm && px_per_mm > 0

            unit  = NA_UNITS.include?(raw['unit'].to_s) ? raw['unit'].to_s : 'mm'
            scale = { 'pxPerMm' => px_per_mm, 'unit' => unit }
            ref   = na_clean_line(raw['ref'], 5)
            scale['ref'] = ref if ref && ref[4] > 0
            scale
        end

        def self.na_number(value, limit, decimals = NA_DECIMALS)
            return nil unless value.is_a?(Numeric)

            float = value.to_f
            return nil unless float.finite? && float.abs <= limit

            rounded = float.round(decimals)
            rounded == rounded.to_i ? rounded.to_i : rounded
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
            return nil unless data.is_a?(Hash) && data['dims'].is_a?(Array)
            return nil if data['schema'].to_i > NA_STATE_SCHEMA

            entry = {
                'w'    => na_dimension(data['w']),
                'h'    => na_dimension(data['h']),
                'dims' => data['dims'].first(NA_MAX_DIMS).map { |dim| na_clean_line(dim, 4) }.compact
            }
            scale = na_clean_scale(data['scale'])
            entry['scale'] = scale if scale
            na_empty?(entry) ? nil : entry
        rescue JSON::ParserError, ArgumentError, TypeError
            nil
        end

# endregion -------------------------------------------------------------------

    end # module Na__ImageCarousel__DimensionPersistence
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
