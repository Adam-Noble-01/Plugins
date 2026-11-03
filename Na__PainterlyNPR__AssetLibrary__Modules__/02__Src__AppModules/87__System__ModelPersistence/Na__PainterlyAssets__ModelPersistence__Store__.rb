# =============================================================================
# NA PAINTERLYNPR ASSETS - MODEL PERSISTENCE - STORE
# =============================================================================
#
# FILE       : Na__PainterlyAssets__ModelPersistence__Store__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__NprSettingsStore
# PURPOSE    : The model's NPR settings record: where it lives, how it is read,
#              and how a change is written. What the blocks mean is
#              Na__NprSettings' business; this module only keeps them safe.
# CREATED    : 01-Nov-2026 (v0.3.0)
#
# WHERE IT LIVES: ONE JSON string in the model attribute dictionary
#   'Na__PainterlyAssets__NprSettings' (key 'json'), our own dictionary on the
#   MODEL, the Point Cloud Viewer's way. A record longer than 16,000 characters
#   is kept in parts ('json__000', 'json__001', ... and 'chunks', the count),
#   read back by index. Nothing else in the model is ever written.
#
# THE RECORD (schema 'Na__PainterlyAssets__NprSettings', schemaVersion 1):
#   storeId        'npst_' and 16 hex, the record's own id (Model#guid changes
#                  on every save, so it is never used)
#   revision       one more with every write
#   updatedAt      local time, '%Y-%m-%dT%H:%M:%S%z'; updatedEpoch, seconds
#   pluginVersion  the version that last wrote it
#   look           the drawing's look: PainterlyNPR's own settings object
#                  (Seed, Sun, Style, Paper, Composition), as its engine
#                  serialises it, so every parameter of NPR Parameters
#   export         NPR Export's settings (Na__NprSettings says which)
#
# NOTHING ON OPEN: read when an NPR window opens or asks, never while a model
#   opens; nothing is written until something is changed.
#
# NEVER CLOBBERED: a record that cannot be read, or one written by a newer
#   version of this plugin (schemaVersion above ours), is read-only: shown when
#   it can be, never rewritten. Keys this version does not know, at the top or
#   inside a block, are carried through every write untouched.
#
# ONE UNDO STEP: every write is one named, undoable operation. With
#   transparent: true it joins the operation before it (Na__NprSettings asks
#   for that only when that operation was its own write of the same block), and
#   a transparent operation that fails is committed, never aborted: aborting it
#   would undo the step it joined.
#
# =============================================================================

require 'json'
require 'securerandom'

module Na__PainterlyAssets
    module Na__NprSettingsStore

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_DICT             = 'Na__PainterlyAssets__NprSettings'.freeze          unless defined?(NA_DICT)
        NA_KEY              = 'json'.freeze                                       unless defined?(NA_KEY)
        NA_CHUNKS_KEY       = 'chunks'.freeze                                     unless defined?(NA_CHUNKS_KEY)
        NA_CHUNK_CHARS      = 16_000                                              unless defined?(NA_CHUNK_CHARS)
        NA_MAX_CHUNKS       = 64                                                  unless defined?(NA_MAX_CHUNKS)   # <-- 1 MB: far past any look; a record past it is refused, with the reason
        NA_SCHEMA           = 'Na__PainterlyAssets__NprSettings'.freeze           unless defined?(NA_SCHEMA)
        NA_SCHEMA_VERSION   = 1                                                   unless defined?(NA_SCHEMA_VERSION)
        NA_STORE_ID_PATTERN = /\Anpst_[0-9a-f]{8,32}\z/.freeze                    unless defined?(NA_STORE_ID_PATTERN)
        NA_BLOCKS           = %w[look export].freeze                              unless defined?(NA_BLOCKS)
        NA_META_KEYS        = %w[schema schemaVersion storeId revision updatedAt updatedEpoch pluginVersion].freeze unless defined?(NA_META_KEYS)

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Read
    # -------------------------------------------------------------------------

        # FUNCTION | Read the Record (never raises)
        # ------------------------------------------------------------
        # @return [Hash] 'state'   'none' (no record), 'ok', or 'readOnly'
        #                'blocks'  { 'look' => Hash, 'export' => Hash } (those present)
        #                'meta'    { 'storeId', 'revision', 'schemaVersion', 'updatedAt', 'updatedEpoch', 'pluginVersion' }
        #                'extra'   the record's keys this version does not know
        #                'raw'     the stored text ('' when none), for comparing
        #                'problem' why it is read-only, or nil
        def self.Na__Store__Load(model)
            raw = self.Na__Store__Raw(model)
            result = self.na_empty(raw.to_s)
            return result if raw.nil?
            if raw.is_a?(Symbol)
                return result.merge('state' => 'readOnly', 'problem' => self.na_problem_text(raw))
            end
            data = JSON.parse(raw)
            unless data.is_a?(Hash) && data['schema'] == NA_SCHEMA
                return result.merge('state' => 'readOnly', 'problem' => self.na_problem_text(:unreadable))
            end
            version = data['schemaVersion'].to_i
            store_id = data['storeId'].to_s
            result['meta'] = {
                'storeId'       => store_id.match?(NA_STORE_ID_PATTERN) ? store_id : nil,
                'revision'      => data['revision'].to_i,
                'schemaVersion' => version,
                'updatedAt'     => data['updatedAt'].to_s,
                'updatedEpoch'  => data['updatedEpoch'].to_f,
                'pluginVersion' => data['pluginVersion'].to_s
            }
            result['extra']  = data.reject { |key, _| NA_META_KEYS.include?(key) || NA_BLOCKS.include?(key) }
            result['blocks'] = NA_BLOCKS.each_with_object({}) { |name, out| out[name] = data[name] if data[name].is_a?(Hash) }
            if version > NA_SCHEMA_VERSION
                return result.merge('state' => 'readOnly', 'problem' => self.na_problem_text(:newer))
            end
            result.merge('state' => 'ok')
        rescue JSON::ParserError => error
            Na__DebugTools.Na__Debug__Warn("The model's NPR settings could not be read and were left as they are: #{error.message}")
            self.na_empty(raw.to_s).merge('state' => 'readOnly', 'problem' => self.na_problem_text(:unreadable))
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error("The model's NPR settings could not be read.", error)
            self.na_empty('').merge('state' => 'readOnly', 'problem' => self.na_problem_text(:unreadable))
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Stored Text: a String, nil (no record), or a Symbol naming what is wrong
        # ------------------------------------------------------------
        # Parts are put back together by index, never by the dictionary's order.
        def self.Na__Store__Raw(model)
            return nil unless model
            dict = model.attribute_dictionary(NA_DICT, false)
            return nil unless dict
            count = dict[NA_CHUNKS_KEY]
            text = if count.is_a?(Integer) && count > 0
                       return :parts if count > NA_MAX_CHUNKS
                       parts = (0...count).map { |index| dict[self.na_chunk_key(index)] }
                       return :parts unless parts.all? { |part| part.is_a?(String) }
                       parts.join
                   else
                       dict[NA_KEY]
                   end
            return nil if text.nil?
            return :unreadable unless text.is_a?(String)
            text = text.dup.force_encoding('UTF-8')                                    # <-- Read back on Windows it can carry another encoding
            return :encoding unless text.valid_encoding?
            text.empty? ? nil : text
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Warn("The model's NPR settings dictionary could not be read: #{error.message}")
            :unreadable
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Write
    # -------------------------------------------------------------------------

        # FUNCTION | Write a Change: the blocks given replace theirs, everything else is kept
        # ------------------------------------------------------------
        # @param loaded  [Hash] a Na__Store__Load result, read just before (never an old copy)
        # @param changes [Hash] { 'look' => Hash } and / or { 'export' => Hash }
        # @return [Array] [problem or nil, the Load result the model now holds]
        def self.Na__Store__Save(model, loaded, changes, operation_name, transparent: false)
            return ['There is no model.', loaded] unless model
            return [loaded['problem'] || self.na_problem_text(:unreadable), loaded] if loaded['state'] == 'readOnly'
            now  = Time.now
            data = self.na_record(loaded, changes, now)
            text = JSON.generate(data)
            parts = self.na_split(text)
            return ["The NPR settings are too large to keep in the model (#{text.length} characters).", loaded] if parts.length > NA_MAX_CHUNKS

            started = false
            begin
                model.start_operation(operation_name.to_s, true, false, transparent ? true : false)
                started = true
                self.na_write_parts(model, parts)
                model.commit_operation
                started = false
            rescue StandardError => error
                if started
                    transparent ? model.commit_operation : model.abort_operation          # <-- Never abort a transparent operation: it would undo the step it joined
                end
                Na__DebugTools.Na__Debug__Error("The NPR settings could not be written into the model (#{operation_name}).", error)
                return ["The NPR settings could not be saved in the model: #{error.message}", loaded]
            end
            [nil, self.Na__Store__Load(model)]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Write a Whole Record Back (Restore from a backup): its blocks, our meta
        # ------------------------------------------------------------
        def self.Na__Store__SaveRecord(model, loaded, record, operation_name)
            changes = NA_BLOCKS.each_with_object({}) { |name, out| out[name] = record[name] if record[name].is_a?(Hash) }
            extra = record.reject { |key, _| NA_META_KEYS.include?(key) || NA_BLOCKS.include?(key) }
            loaded = loaded.merge('extra' => (loaded['extra'] || {}).merge(extra))
            meta = loaded['meta'] || {}
            if meta['storeId'].nil? && record['storeId'].to_s.match?(NA_STORE_ID_PATTERN)
                loaded = loaded.merge('meta' => meta.merge('storeId' => record['storeId'], 'revision' => [meta['revision'].to_i, record['revision'].to_i].max))
            end
            self.Na__Store__Save(model, loaded, changes, operation_name)
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals
    # -------------------------------------------------------------------------

        def self.na_empty(raw)
            { 'state' => 'none', 'blocks' => {}, 'meta' => { 'storeId' => nil, 'revision' => 0, 'schemaVersion' => NA_SCHEMA_VERSION }, 'extra' => {}, 'raw' => raw, 'problem' => nil }
        end

        # The record to write: unknown keys first, then our meta, then the blocks
        def self.na_record(loaded, changes, now)
            meta   = loaded['meta'] || {}
            blocks = (loaded['blocks'] || {}).merge(changes.select { |name, value| NA_BLOCKS.include?(name) && value.is_a?(Hash) })
            data = (loaded['extra'] || {}).merge(
                'schema'        => NA_SCHEMA,
                'schemaVersion' => NA_SCHEMA_VERSION,
                'storeId'       => meta['storeId'] || "npst_#{SecureRandom.hex(8)}",
                'revision'      => meta['revision'].to_i + 1,
                'updatedAt'     => now.strftime('%Y-%m-%dT%H:%M:%S%z'),
                'updatedEpoch'  => now.to_f,
                'pluginVersion' => Na__PainterlyAssets.Na__PublicApi__Version.to_s
            )
            NA_BLOCKS.each { |name| data[name] = blocks[name] if blocks[name] }
            data
        end

        def self.na_split(text)
            return [text] if text.length <= NA_CHUNK_CHARS
            text.scan(/.{1,#{NA_CHUNK_CHARS}}/m)
        end

        # One part: 'json'. More: 'json__000'... and 'chunks'. The new keys are
        # written first and the stale ones removed after, so at every moment the
        # dictionary reads as the old record or the new one, whole: a write that
        # fails part way (inside a transparent operation, which is committed)
        # never leaves half of one. 'chunks' decides which shape is read.
        def self.na_write_parts(model, parts)
            if parts.length == 1
                model.set_attribute(NA_DICT, NA_KEY, parts.first)
                dict = model.attribute_dictionary(NA_DICT, false)
                dict.delete_key(NA_CHUNKS_KEY) if dict && dict.keys.include?(NA_CHUNKS_KEY)     # <-- From here the new 'json' is read
                self.na_delete_parts(dict, 0)
            else
                parts.each_with_index { |part, index| model.set_attribute(NA_DICT, self.na_chunk_key(index), part) }
                model.set_attribute(NA_DICT, NA_CHUNKS_KEY, parts.length)                          # <-- From here the new parts are read
                dict = model.attribute_dictionary(NA_DICT, false)
                dict.delete_key(NA_KEY) if dict && dict.keys.include?(NA_KEY)
                self.na_delete_parts(dict, parts.length)
            end
        end

        # Parts from index first_stale on (a longer record's tail)
        def self.na_delete_parts(dict, first_stale)
            return unless dict
            dict.keys.select { |key| key.to_s.match?(/\Ajson__\d{3}\z/) && key.to_s[6, 3].to_i >= first_stale }.each { |key| dict.delete_key(key) }
        end

        def self.na_chunk_key(index)
            format('json__%03d', index)
        end

        def self.na_problem_text(kind)
            case kind
            when :newer then "This model's NPR settings were saved by a newer version of Na PainterlyNPR Assets. They are used as they are, and never rewritten, so nothing it saved is lost."
            when :parts then "Part of this model's NPR settings is missing, so they could not be read. They have been left exactly as they are."
            when :encoding then "This model's NPR settings are not readable text, so they could not be read. They have been left exactly as they are."
            else "This model's NPR settings could not be read, so they are not used. They have been left exactly as they are."
            end
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
