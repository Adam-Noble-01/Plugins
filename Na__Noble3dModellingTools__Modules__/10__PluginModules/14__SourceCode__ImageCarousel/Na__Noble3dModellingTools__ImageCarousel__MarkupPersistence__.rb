# =============================================================================
# NA NOBLE3D MODELLING TOOLS - IMAGE CAROUSEL - MARKUP PERSISTENCE
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__ImageCarousel__MarkupPersistence__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__ImageCarousel__MarkupPersistence
# PURPOSE    : Keep the Image Viewer's markup (pen and highlighter strokes) in
#              the model, so the marks come back with it
# CREATED    : 29-Oct-2026
#
# DESIGN NOTES:
# - Same approach as ModelPersistence: a custom model attribute dictionary,
#   so the marks travel inside the .skp. One key per photo, each holding that
#   photo's marks as one versioned JSON string:
#     { "schema":1, "name":"IMG_0001.jpg", "w":4032, "h":3024,
#       "strokes":[ { "k":"hl", "c":"#ffe600", "w":22.4, "p":[x, y, x, y, ...] } ] }
#   k is the tool (pen | hl), c the colour, w the width in photo pixels and p
#   the points in photo pixels, origin at the photo's top-left. w and h are the
#   photo's own size, so a stroke is placed on the same detail whatever the
#   viewer is doing, and a copy of the photo at another size can take it scaled.
# - A photo is named by its path under the model's image folder (lower case,
#   forward slashes), so moving or renaming the folder, or opening the model on
#   another machine, still finds the marks once the folder is chosen again.
# - The dialog sends a photo's marks after every change. They are checked and
#   held here (Queue); Flush writes everything held in one undo step. The dialog
#   flushes a moment after the last change and again when it closes, so a burst
#   of strokes is one step in SketchUp's undo list, not one per stroke.
# - Nothing the dialog sends is trusted: kinds, colours, sizes and every number
#   are checked and rounded here, and a photo's entry has a size limit.
# - A photo with no marks has no key: Flush removes it, and the dictionary with
#   it when it is empty.
#
# =============================================================================

require 'json'

module Na__Noble3dModellingTools
    module Na__ImageCarousel__MarkupPersistence

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_DICTIONARY_NAME = 'Na__Noble3dModellingTools__ImageCarousel__Markup'.freeze
        NA_STATE_SCHEMA    = 1
        NA_OPERATION_NAME  = 'Image Viewer: Markup'.freeze

        NA_STROKE_KINDS    = %w[pen hl].freeze
        NA_DEFAULT_COLOUR  = '#e23b2e'.freeze
        NA_COLOUR_PATTERN  = /\A#[0-9a-f]{6}\z/i
        NA_DECIMALS        = 2

        NA_MAX_STROKES     = 5000        # per photo
        NA_MAX_POINTS      = 20_000      # per stroke
        NA_MAX_ENTRY_BYTES = 4_000_000   # per photo, serialised
        NA_MAX_DIMENSION   = 100_000     # photo pixels
        NA_MAX_COORDINATE  = 1_000_000.0
        NA_MIN_WIDTH       = 0.01
        NA_MAX_WIDTH       = 5_000.0

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # The key a photo's marks are kept under: its path below the image
        # folder, lower case. A path outside the folder (or no folder) is kept
        # under its file name.
        def self.Na__ImageCarousel__MarkupPersistence__KeyForPath(path, root)
            normal = na_normalise_path(path)
            return nil if normal.empty?

            base = na_normalise_path(root).chomp('/')
            relative = if !base.empty? && normal.downcase.start_with?("#{base.downcase}/")
                normal.sub(/\A#{Regexp.escape(base)}\//i, '')
            else
                File.basename(normal)
            end
            relative = relative.sub(%r{\A/+}, '')
            relative.empty? ? nil : relative.downcase
        end

        # Check one photo's marks as the dialog sent them (JSON text or a Hash)
        # and hold them for Flush. Returns { 'ok' => true, 'key', 'name',
        # 'strokes' } or { 'ok' => false, 'path', 'error' }.
        def self.Na__ImageCarousel__MarkupPersistence__Queue(payload, root)
            path = nil
            data = payload.is_a?(String) ? JSON.parse(payload) : payload
            raise ArgumentError, 'the marks were not sent as an object' unless data.is_a?(Hash)

            path = data['path'].to_s
            key  = Na__ImageCarousel__MarkupPersistence__KeyForPath(path, root)
            raise ArgumentError, 'the marks have no photo path' if key.nil?

            entry = na_clean_entry(data, File.basename(na_normalise_path(path)))
            text  = nil
            unless entry['strokes'].empty?
                text = JSON.generate(entry)
                raise ArgumentError, "too much markup to keep on one photo (#{text.bytesize} bytes)" if text.bytesize > NA_MAX_ENTRY_BYTES
            end

            na_pending[key] = { 'text' => text, 'name' => entry['name'], 'strokes' => entry['strokes'].length }
            { 'ok' => true, 'key' => key, 'name' => entry['name'], 'strokes' => entry['strokes'].length }
        rescue JSON::ParserError, ArgumentError, TypeError => error
            puts "[Na__ImageCarousel] markup not kept: #{error.message}"
            { 'ok' => false, 'path' => path, 'error' => error.message }
        end

        def self.Na__ImageCarousel__MarkupPersistence__HasPending
            !na_pending.empty?
        end

        # Write everything held to the model in one undo step. Returns
        # { 'ok' => true, 'saved' => [ { 'key', 'name', 'strokes', 'bytes', 'written' } ] }
        # or { 'ok' => false, 'error' } with the marks still held for another try.
        def self.Na__ImageCarousel__MarkupPersistence__Flush(model)
            started = false   # abort only an operation this method opened: with none open it could undo the user's last step
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
                { 'key' => key, 'name' => item['name'], 'strokes' => item['strokes'],
                  'bytes' => item['text'].to_s.bytesize, 'written' => changes.key?(key) }
            end
            { 'ok' => true, 'saved' => saved }
        rescue => error
            model.abort_operation if started
            puts "[Na__ImageCarousel] save markup to model failed: #{error.class}: #{error.message}"
            { 'ok' => false, 'error' => error.message, 'saved' => [] }
        end

        # The model's marks for the photos of a folder, as { path => { 'w', 'h',
        # 'strokes' } } for the photos that have any. Marks still held for the
        # model (not yet written) win over what the model holds.
        def self.Na__ImageCarousel__MarkupPersistence__LoadForPaths(model, paths, root)
            found = {}
            dict  = model.nil? ? nil : model.attribute_dictionary(NA_DICTIONARY_NAME)

            Array(paths).each do |path|
                key = Na__ImageCarousel__MarkupPersistence__KeyForPath(path, root)
                next if key.nil?

                held = na_pending[key]
                text = held ? held['text'] : (dict.nil? ? nil : dict[key])
                entry = na_read_entry(text)
                found[path.to_s] = entry if entry
            end
            found
        rescue => error
            puts "[Na__ImageCarousel] read markup from model failed: #{error.class}: #{error.message}"
            {}
        end

        # Forget anything held (the tests start from nothing).
        def self.Na__ImageCarousel__MarkupPersistence__DiscardPending
            na_pending.clear
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Model Dictionary
# -----------------------------------------------------------------------------

        def self.na_pending
            @na_pending ||= {}
        end

        # Would writing text (nil: remove) change what the model holds?
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

        # A photo's marks, checked: raises ArgumentError for a payload that is
        # not marks at all, and drops a single stroke that cannot be one.
        def self.na_clean_entry(data, name)
            raw = data['strokes']
            raise ArgumentError, 'the marks are missing' unless raw.is_a?(Array)
            raise ArgumentError, "too many marks on one photo (#{raw.length})" if raw.length > NA_MAX_STROKES

            {
                'schema'  => NA_STATE_SCHEMA,
                'name'    => name,
                'w'       => na_dimension(data['w']),
                'h'       => na_dimension(data['h']),
                'strokes' => raw.map { |stroke| na_clean_stroke(stroke) }.compact
            }
        end

        def self.na_clean_stroke(raw)
            return nil unless raw.is_a?(Hash)

            kind   = raw['k'].to_s
            points = raw['p']
            return nil unless NA_STROKE_KINDS.include?(kind)
            return nil unless points.is_a?(Array) && points.length >= 2 && points.length.even?
            raise ArgumentError, 'a mark has too many points' if points.length > NA_MAX_POINTS * 2

            flat = points.map { |value| na_number(value, NA_MAX_COORDINATE) }
            return nil if flat.any?(&:nil?)

            colour = raw['c'].to_s
            colour = NA_DEFAULT_COLOUR unless colour.match?(NA_COLOUR_PATTERN)
            width  = na_number(raw['w'], NA_MAX_WIDTH) || NA_MIN_WIDTH
            width  = NA_MIN_WIDTH if width < NA_MIN_WIDTH

            { 'k' => kind, 'c' => colour.downcase, 'w' => width, 'p' => flat }
        end

        # A finite number within a limit, rounded; a whole one comes back as an
        # Integer so it serialises short. nil for anything else.
        def self.na_number(value, limit)
            return nil unless value.is_a?(Numeric)

            float = value.to_f
            return nil unless float.finite? && float.abs <= limit

            rounded = float.round(NA_DECIMALS)
            rounded == rounded.to_i ? rounded.to_i : rounded
        end

        def self.na_dimension(value)
            number = value.is_a?(Numeric) ? value.to_f : nil
            ok = number && number.finite? && number >= 1 && number <= NA_MAX_DIMENSION
            raise ArgumentError, 'the photo size is missing or out of range' unless ok

            number.round
        end

        # A saved entry, read back: nil for text that is not one, or has no marks.
        def self.na_read_entry(text)
            return nil unless text.is_a?(String) && !text.strip.empty?

            data = JSON.parse(text)
            return nil unless data.is_a?(Hash) && data['strokes'].is_a?(Array)
            return nil if data['schema'].to_i > NA_STATE_SCHEMA

            strokes = data['strokes'].first(NA_MAX_STROKES).map { |stroke| na_clean_stroke(stroke) }.compact
            return nil if strokes.empty?

            { 'w' => na_dimension(data['w']), 'h' => na_dimension(data['h']), 'strokes' => strokes }
        rescue JSON::ParserError, ArgumentError, TypeError
            nil
        end

        def self.na_normalise_path(path)
            path.to_s.strip.gsub('\\', '/')
        end

# endregion -------------------------------------------------------------------

    end # module Na__ImageCarousel__MarkupPersistence
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
