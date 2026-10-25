# =============================================================================
# NA POINT CLOUD VIEWER - CLOUD SET - STORE
# =============================================================================
#
# FILE       : Na__PointCloudViewer__CloudSet__Store__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__CloudStore
# PURPOSE    : How a model keeps its point clouds (v0.10.0): ONE record per
#              cloud, so what belongs to which cloud is never in doubt.
#
# WHAT THE MODEL HOLDS (model-level attribute dictionaries, key 'json', each
#   one small JSON string; no entities, no file references SketchUp follows):
#     Na__PointCloudViewer__Clouds            the index: the model's id (names
#                                             this computer's backup file) and
#                                             the clouds in order
#     Na__PointCloudViewer__Cloud__pc_<hex>   one per cloud, everything about it:
#         cloudId, name, colour
#         link             which LAS: file name, last path, path relative to the
#                          .skp, unit, point count, fingerprint, content key,
#                          derivedFrom (a cleaned or cropped copy), history
#         placement        position, rotation, gimbal point, lock
#         clip, clipScenes, activeClipScene   its own clip box and clip scenes
#         cropCut          its Crop and Cut boxes while it has any (v0.11.0,
#                          80__System__Clean/...Clean__Boxes__.rb)
#     Na__PointCloudViewer__Scenes            the point cloud scenes (90__System__Scenes);
#                                             each scene keeps every cloud's look
#                                             and clip box, by cloud id
#   A cloud's dictionary is its own: a change to one cloud rewrites only its
#   record, and a record that cannot be read hides only that cloud.
#
# MODELS SAVED BEFORE v0.10.0 hold three records for their one cloud
#   (Na__PointCloudViewer__ModelLink / __Placement / __ClipState). They are read
#   exactly as they are, as a cloud whose id comes from the old link id, and
#   NOTHING is written on open. The first change the user makes converts them,
#   inside that same undoable operation: the index and the cloud's record are
#   written, the scenes record takes its per-cloud form, and the three old
#   records go. One Undo puts the old records back.
#
# EVERY WRITE is one named operation, aborted on error, then the local backup.
#
# =============================================================================

require 'json'
require 'securerandom'
require 'digest'

module Na__PointCloudViewer
    module Na__CloudStore

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_KEY                   = 'json'.freeze
        NA_INDEX_DICT            = 'Na__PointCloudViewer__Clouds'.freeze
        NA_INDEX_SCHEMA          = 'Na__PointCloudViewer__Clouds'.freeze
        NA_INDEX_VERSION         = 1
        NA_CLOUD_DICT_PREFIX     = 'Na__PointCloudViewer__Cloud__'.freeze
        NA_CLOUD_SCHEMA          = 'Na__PointCloudViewer__Cloud'.freeze
        NA_CLOUD_VERSION         = 1
        NA_ID_PATTERN            = /\Apc_[0-9a-f]{8}\z/.freeze
        NA_LEGACY_LINK_DICT      = 'Na__PointCloudViewer__ModelLink'.freeze
        NA_LEGACY_PLACEMENT_DICT = 'Na__PointCloudViewer__Placement'.freeze
        NA_LEGACY_CLIP_DICT      = 'Na__PointCloudViewer__ClipState'.freeze
        NA_LEGACY_DICTS          = [NA_LEGACY_LINK_DICT, NA_LEGACY_PLACEMENT_DICT, NA_LEGACY_CLIP_DICT].freeze
        NA_SCENES_DICT           = 'Na__PointCloudViewer__Scenes'.freeze

        NA_FALLBACK_PALETTE = [
            [232, 113, 10], [26, 115, 232], [24, 128, 56], [142, 36, 170], [0, 137, 123],
            [197, 34, 31], [191, 144, 0], [216, 27, 96], [121, 85, 72], [84, 110, 122]
        ].freeze

        NA_STAMP_KEYS = %w[updatedAt updatedEpoch].freeze

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Names, Ids, Colours
    # -------------------------------------------------------------------------

        def self.Na__Store__DictName(cloud_id)
            "#{NA_CLOUD_DICT_PREFIX}#{cloud_id}"
        end

        def self.Na__Store__MaxClouds
            [[Na__ConfigLoader.Na__Config__GetOr(10, 'clouds', 'maxClouds').to_i, 1].max, 16].min
        end

        def self.Na__Store__Palette
            list = Na__ConfigLoader.Na__Config__GetOr(nil, 'clouds', 'palette')
            list = NA_FALLBACK_PALETTE unless list.is_a?(Array) && !list.empty?
            list.select { |rgb| self.na_valid_rgb(rgb) }.map { |rgb| rgb.map(&:to_i) }
        end

        # The first palette colour no cloud of the session uses yet.
        def self.Na__Store__NextColour(session)
            used = Array(session && session.slots).map(&:colour)
            palette = self.Na__Store__Palette
            palette.find { |rgb| !used.include?(rgb) } || palette[Array(session && session.slots).length % palette.length]
        end

        def self.Na__Store__NewCloudId(session)
            taken = Array(session && session.slots).map(&:id)
            taken += self.na_cloud_dict_names(session.model).map { |name| name.sub(NA_CLOUD_DICT_PREFIX, '') } if session && session.model
            loop do
                id = "pc_#{SecureRandom.hex(4)}"
                return id unless taken.include?(id)
            end
        end

        # The id a v0.9 model's one cloud is known by: the same on every read
        # and on every computer, so point cloud scenes find it before and after
        # the model is converted.
        def self.Na__Store__LegacyCloudId(link_id)
            "pc_#{Digest::SHA256.hexdigest("Na__PointCloudViewer|#{link_id}")[0, 8]}"
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Read (never writes, never raises)
    # -------------------------------------------------------------------------

        # Everything the model records about its clouds:
        #   'clouds'   [{ 'id', 'record', 'state' => 'saved' | 'legacy' }] in order
        #   'index'    the index record, or nil
        #   'legacy'   the model holds the v0.9 records
        #   'readonly' saved by a newer version of the viewer: shown, never rewritten
        #   'problems' plain sentences about records that could not be read
        def self.Na__Store__Read(model)
            result = { 'clouds' => [], 'index' => nil, 'legacy' => false, 'readonly' => false, 'problems' => [] }
            return result unless model
            names = self.na_cloud_dict_names(model)
            index_raw = model.get_attribute(NA_INDEX_DICT, NA_KEY)
            if (index_raw.is_a?(String) && !index_raw.empty?) || !names.empty?
                index = self.na_parse(index_raw)
                if index.is_a?(Hash) && index['schema'] == NA_INDEX_SCHEMA
                    result['readonly'] = true if index['schemaVersion'].to_i > NA_INDEX_VERSION
                    result['index'] = index
                elsif index_raw.is_a?(String) && !index_raw.empty?
                    result['problems'] << 'The list of point clouds saved in this model could not be read; the clouds are shown in the order they were added.'
                end
                records = {}
                names.each do |dict|
                    id = dict.sub(NA_CLOUD_DICT_PREFIX, '')
                    data = self.na_parse(model.get_attribute(dict, NA_KEY))
                    if data.is_a?(Hash) && data['schema'] == NA_CLOUD_SCHEMA && data['schemaVersion'].to_i > NA_CLOUD_VERSION
                        result['problems'] << "One point cloud (#{id}) was saved by a newer version of the viewer, so it is not shown here. Nothing it saved is changed."
                        next
                    end
                    record = self.Na__Store__ValidCloud(data, id)
                    if record
                        records[id] = record
                    else
                        result['problems'] << "The record of one point cloud (#{id}) could not be read, so it is not shown. Nothing has been changed."
                    end
                end
                order = result['index'] ? Array(result['index']['order']).map(&:to_s) : []
                ids = order.select { |id| records.key?(id) }.uniq
                ids += (records.keys - ids).sort_by { |id| [records[id]['createdAt'].to_s, id] }
                result['clouds'] = ids.map { |id| { 'id' => id, 'record' => records[id], 'state' => 'saved' } }
                return result
            end
            legacy = self.Na__Store__LegacyRecord(model)
            if legacy
                result['legacy'] = true
                result['clouds'] = [{ 'id' => legacy['cloudId'], 'record' => legacy, 'state' => 'legacy' }]
            elsif self.na_present?(model, NA_LEGACY_LINK_DICT)
                result['problems'] << 'The point cloud link saved in this model could not be read.'
            end
            result
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Warn("The point clouds saved in this model could not be read: #{error.message}")
            result['problems'] << 'The point clouds saved in this model could not be read.'
            result
        end

        # A cloud record as stored, checked: the right schema and id, a link the
        # viewer can use. Unknown keys are carried through every save.
        def self.Na__Store__ValidCloud(data, id)
            return nil unless data.is_a?(Hash) && data['schema'] == NA_CLOUD_SCHEMA && data['schemaVersion'].to_i <= NA_CLOUD_VERSION
            return nil unless data['cloudId'] == id && id.to_s.match?(NA_ID_PATTERN)
            link = data['link']
            return nil unless link.is_a?(Hash) && link['fingerprint'].is_a?(String) && Na__UnitContract.Na__Units__IsSupportedSourceUnit?(link['sourceUnit'])
            record = Marshal.load(Marshal.dump(data))
            record['name'] = self.na_clean_name(record['name'], link['fileName'])
            record['colour'] = self.na_valid_rgb(record['colour']) ? record['colour'].map(&:to_i) : nil
            record['clipScenes'] = [] unless record['clipScenes'].is_a?(Array)
            record
        rescue StandardError
            nil
        end

        # The one cloud of a model saved before v0.10.0, read from its three
        # records exactly as they are, in the form of a cloud record. nil when
        # the model has no readable v0.9 link.
        def self.Na__Store__LegacyRecord(model)
            link = self.na_parse(model.get_attribute(NA_LEGACY_LINK_DICT, NA_KEY))
            return nil unless link.is_a?(Hash) && link['schema'] == NA_LEGACY_LINK_DICT && link['schemaVersion'].to_i <= 1
            cloud = link['cloud']
            return nil unless link['linkId'].is_a?(String) && cloud.is_a?(Hash) && cloud['fingerprint'].is_a?(String)
            return nil unless Na__UnitContract.Na__Units__IsSupportedSourceUnit?(cloud['sourceUnit'])
            placement = self.na_parse(model.get_attribute(NA_LEGACY_PLACEMENT_DICT, NA_KEY))
            clip_state = self.na_parse(model.get_attribute(NA_LEGACY_CLIP_DICT, NA_KEY))
            clip_state = nil unless clip_state.is_a?(Hash) && clip_state['schema'] == NA_LEGACY_CLIP_DICT && clip_state['schemaVersion'].to_i <= 1
            placement = nil unless placement.is_a?(Hash) && placement['schema'] == NA_LEGACY_PLACEMENT_DICT && placement['schemaVersion'].to_i <= 1
            epochs = [link, placement, clip_state].compact.map { |record| record['updatedEpoch'].to_f }
            link_part = Marshal.load(Marshal.dump(cloud))
            link_part['history'] = link['history'] if link['history'].is_a?(Array) && !link['history'].empty?
            link_part['linkedAt'] = link['updatedAt'] if link['updatedAt']
            {
                'schema'          => NA_CLOUD_SCHEMA,
                'schemaVersion'   => NA_CLOUD_VERSION,
                'cloudId'         => self.Na__Store__LegacyCloudId(link['linkId']),
                'name'            => self.na_clean_name(nil, cloud['fileName']),
                'colour'          => self.Na__Store__Palette.first,
                'createdAt'       => link['createdAt'],
                'updatedAt'       => link['updatedAt'],
                'updatedEpoch'    => epochs.max || 0.0,
                'link'            => link_part,
                'placement'       => placement ? placement.reject { |key, _| %w[schema schemaVersion updatedAt updatedEpoch].include?(key) } : nil,
                'clip'            => clip_state ? clip_state['clip'] : nil,
                'clipScenes'      => clip_state && clip_state['scenes'].is_a?(Array) ? clip_state['scenes'] : [],
                'activeClipScene' => clip_state ? clip_state['activeScene'] : nil,
                'legacyLinkId'    => link['linkId']
            }
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Warn("The v0.9 point cloud records could not be read: #{error.message}")
            nil
        end

        # The id that names this computer's backup of the model: the index's,
        # or a v0.9 model's link id (its backup file carries on), or nil.
        def self.Na__Store__ModelId(session)
            index = session.store_index
            return index['modelId'] if index.is_a?(Hash) && index['modelId'].is_a?(String)
            legacy = Array(session.slots).find { |slot| slot.record_state == 'legacy' }
            legacy && legacy.record ? legacy.record['legacyLinkId'] : nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Write (each call ONE undoable operation)
    # -------------------------------------------------------------------------

        # Changes some clouds' records: each slot's record (a copy) is handed to
        # the block, changed there, stamped and written. Returns nil, or a plain
        # reason nothing was written.
        def self.Na__Store__WriteSlots(session, slots, operation_name)
            model = session.model
            return 'There is no model.' unless model
            return self.na_readonly_text if session.store_readonly
            now = Time.now
            staged = Array(slots).uniq.map do |slot|
                record = self.na_working_record(slot, now)
                yield(slot, record) if block_given?
                self.na_stamp(record, now)
                [slot, record]
            end
            written = staged.map(&:first)
            index = nil
            migrated = nil
            self.na_operation(model, operation_name) do
                migrated = self.na_migrate_in_operation(session, now)
                staged.each { |slot, record| model.set_attribute(self.Na__Store__DictName(slot.id), NA_KEY, JSON.generate(record)) }
                index = self.na_write_index(session, now, self.na_order_with(session, written), false, migrated)
            end
            self.na_after_migration(session, migrated)
            session.store_index = index if index
            staged.each do |slot, record|
                slot.record = record
                slot.record_state = 'saved'
            end
            Na__LocalBackup.Na__Backup__AfterSave(model, session)
            nil
        end

        # Takes one cloud out of the model (its record and its place in the
        # index). Its LAS and its point cache are never touched.
        def self.Na__Store__RemoveSlot(session, slot, operation_name)
            model = session.model
            return 'There is no model.' unless model
            return self.na_readonly_text if session.store_readonly
            now = Time.now
            index = nil
            migrated = nil
            order = Array(session.slots).select { |other| !other.equal?(slot) && %w[saved legacy].include?(other.record_state) }.map(&:id)
            self.na_operation(model, operation_name) do
                migrated = self.na_migrate_in_operation(session, now)
                dictionaries = model.attribute_dictionaries
                dict = self.Na__Store__DictName(slot.id)
                dictionaries.delete(dict) if dictionaries && dictionaries[dict]
                index = self.na_write_index(session, now, order, true, migrated)
            end
            self.na_after_migration(session, migrated)
            session.store_index = index if index
            slot.record = nil
            slot.record_state = 'unsaved'
            Na__LocalBackup.Na__Backup__AfterSave(model, session)
            nil
        end

        # A new order for the clouds (every saved id, top to bottom).
        def self.Na__Store__WriteOrder(session, ids, operation_name)
            model = session.model
            return 'There is no model.' unless model
            return self.na_readonly_text if session.store_readonly
            now = Time.now
            index = nil
            migrated = nil
            self.na_operation(model, operation_name) do
                migrated = self.na_migrate_in_operation(session, now)
                index = self.na_write_index(session, now, ids, true, migrated)
            end
            self.na_after_migration(session, migrated)
            session.store_index = index if index
            Na__LocalBackup.Na__Backup__AfterSave(model, session)
            nil
        end

        # For other writers (the scenes store): converts a v0.9 model inside an
        # operation they already opened. Returns what na_after_migration needs.
        def self.Na__Store__MigrateInOperation(session, now)
            self.na_migrate_in_operation(session, now)
        end

        def self.Na__Store__AfterMigration(session, migrated)
            self.na_after_migration(session, migrated)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Raw Records (backup, restore, remove everything)
    # -------------------------------------------------------------------------

        # Every point cloud dictionary the model holds now, by name.
        def self.Na__Store__AllDictNames(model)
            return [] unless model
            fixed = [NA_INDEX_DICT, *NA_LEGACY_DICTS, NA_SCENES_DICT].select { |name| self.na_present?(model, name) }
            (fixed + self.na_cloud_dict_names(model)).uniq
        end

        # { dictionary name => its record (parsed) } for every point cloud
        # record in the model. A string that does not parse is left out.
        def self.Na__Store__RawRecords(model)
            self.Na__Store__AllDictNames(model).each_with_object({}) do |name, records|
                parsed = self.na_parse(model.get_attribute(name, NA_KEY))
                records[name] = parsed if parsed.is_a?(Hash)
            end
        end

        # { dictionary name => the stored string } (Undo detection).
        def self.Na__Store__RawStrings(model)
            self.Na__Store__AllDictNames(model).each_with_object({}) do |name, strings|
                strings[name] = model.get_attribute(name, NA_KEY)
            end
        end

        # Replaces every point cloud record of the model with `records`
        # ({ dictionary name => record }), in one operation.
        def self.Na__Store__ReplaceAll(model, records, operation_name)
            allowed = records.select { |name, record| self.na_ours?(name) && record.is_a?(Hash) }
            self.na_operation(model, operation_name) do
                dictionaries = model.attribute_dictionaries
                self.Na__Store__AllDictNames(model).each { |name| dictionaries.delete(name) if dictionaries && dictionaries[name] }
                allowed.each { |name, record| model.set_attribute(name, NA_KEY, JSON.generate(record)) }
            end
            nil
        end

        # The escape hatch: every point cloud record goes (one operation).
        def self.Na__Store__RemoveAll(model, operation_name)
            present = self.Na__Store__AllDictNames(model)
            return 'This model holds no point cloud data.' if present.empty?
            self.na_operation(model, operation_name) do
                dictionaries = model.attribute_dictionaries
                present.each { |name| dictionaries.delete(name) if dictionaries && dictionaries[name] }
            end
            nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals
    # -------------------------------------------------------------------------

        def self.na_operation(model, operation_name)
            model.start_operation(operation_name, true)
            yield
            model.commit_operation
        rescue StandardError
            model.abort_operation
            raise
        end

        def self.na_readonly_text
            'The point clouds in this model were saved by a newer version of the viewer, so nothing is changed here. Update the viewer on this computer.'
        end

        # The record to change: a copy of the slot's own, or, for a cloud that
        # has none in the model (new, or taken out by an Undo), one built from
        # what the slot holds now.
        def self.na_working_record(slot, now)
            return Marshal.load(Marshal.dump(slot.record)).reject { |key, _| key == 'legacyLinkId' } if slot.record
            model = slot.model
            cloud = slot.cloud
            key = slot.placement ? slot.placement['key'] : (cloud ? Na__Placement.Na__Placement__CloudKey(cloud) : nil)
            {
                'schema'          => NA_CLOUD_SCHEMA,
                'schemaVersion'   => NA_CLOUD_VERSION,
                'cloudId'         => slot.id,
                'name'            => slot.name.to_s,
                'colour'          => slot.colour,
                'createdAt'       => now.strftime('%Y-%m-%dT%H:%M:%S%z'),
                'link'            => cloud && key ? Na__ModelLink.Na__Link__CloudPart(model, cloud, key) : nil,
                'placement'       => slot.placement ? Na__Placement.Na__Placement__Part(slot.placement) : nil,
                'clip'            => slot.clip,
                'clipScenes'      => slot.clip_scenes || [],
                'activeClipScene' => slot.clip_active_scene
            }
        end

        def self.na_stamp(record, now)
            record['updatedAt']     = now.strftime('%Y-%m-%dT%H:%M:%S%z')
            record['updatedEpoch']  = now.to_f
            record['pluginVersion'] = Na__PointCloudViewer.Na__PublicApi__Version
            record
        end

        # The saved clouds' order with the slots being written included.
        def self.na_order_with(session, written)
            Array(session.slots).select { |slot| written.include?(slot) || %w[saved legacy].include?(slot.record_state) }.map(&:id)
        end

        # Writes the index when it is new or its order changed (inside the open
        # operation). migrated: what na_migrate_in_operation just wrote in this
        # same operation (its index, with the v0.9 link id as the model id, is
        # the one to build on). Returns the index now in the model, or nil when
        # unchanged.
        def self.na_write_index(session, now, order, force = false, migrated = nil)
            model = session.model
            current = migrated ? migrated['index'] : session.store_index
            return nil if !force && current.is_a?(Hash) && Array(current['order']) == order && self.na_present?(model, NA_INDEX_DICT)
            index = current.is_a?(Hash) ? Marshal.load(Marshal.dump(current)) : {}
            index['schema']        = NA_INDEX_SCHEMA
            index['schemaVersion'] = NA_INDEX_VERSION
            index['modelId']     ||= self.na_new_model_id(now)
            index['createdAt']   ||= now.strftime('%Y-%m-%dT%H:%M:%S%z')
            index['order']         = order
            self.na_stamp(index, now)
            model.set_attribute(NA_INDEX_DICT, NA_KEY, JSON.generate(index))
            index
        end

        def self.na_new_model_id(now)
            "PCV-#{now.strftime('%Y%m%d-%H%M%S')}-#{format('%06x', rand(0x1000000))}"
        end

        # Inside an open operation: a v0.9 model takes the new form. Returns
        # what changes in memory once the operation commits, or nil.
        def self.na_migrate_in_operation(session, now)
            return nil unless session.store_legacy
            model = session.model
            legacy = Array(session.slots).find { |slot| slot.record_state == 'legacy' }
            return nil unless legacy && legacy.record
            link_id = legacy.record['legacyLinkId'].to_s
            record = legacy.record.reject { |key, _| key == 'legacyLinkId' }
            self.na_stamp(record, now)
            index = {
                'schema'        => NA_INDEX_SCHEMA,
                'schemaVersion' => NA_INDEX_VERSION,
                'modelId'       => link_id,                         # this computer's backup file carries on
                'createdAt'     => legacy.record['createdAt'] || now.strftime('%Y-%m-%dT%H:%M:%S%z'),
                'order'         => [legacy.id],
                'migratedFrom'  => { 'linkId' => link_id, 'cloudId' => legacy.id, 'fromVersion' => '0.9',
                                     'migratedAt' => now.strftime('%Y-%m-%dT%H:%M:%S%z') }
            }
            self.na_stamp(index, now)
            model.set_attribute(self.Na__Store__DictName(legacy.id), NA_KEY, JSON.generate(record))
            model.set_attribute(NA_INDEX_DICT, NA_KEY, JSON.generate(index))
            scenes = defined?(Na__SceneStore) ? Na__SceneStore.Na__Scenes__MigrateInOperation(session, now) : nil
            dictionaries = model.attribute_dictionaries
            NA_LEGACY_DICTS.each { |name| dictionaries.delete(name) if dictionaries && dictionaries[name] }
            Na__DebugTools.Na__Debug__Info("This model's point cloud records were converted to the v0.10 form (one record per cloud, #{legacy.id}).")
            { 'slot' => legacy, 'record' => record, 'index' => index, 'scenes' => scenes }
        end

        def self.na_after_migration(session, migrated)
            return unless migrated
            migrated['slot'].record = migrated['record']
            migrated['slot'].record_state = 'saved'
            session.store_index = migrated['index']
            session.store_legacy = false
            Na__SceneStore.Na__Scenes__AfterMigration(session, migrated['scenes']) if migrated['scenes'] && defined?(Na__SceneStore)
        end

        def self.na_cloud_dict_names(model)
            dictionaries = model ? model.attribute_dictionaries : nil
            return [] unless dictionaries
            names = []
            dictionaries.each do |dictionary|
                name = dictionary.name.to_s
                next unless name.start_with?(NA_CLOUD_DICT_PREFIX)
                names << name if name.sub(NA_CLOUD_DICT_PREFIX, '').match?(NA_ID_PATTERN)
            end
            names.sort
        rescue StandardError
            []
        end

        def self.na_ours?(name)
            [NA_INDEX_DICT, *NA_LEGACY_DICTS, NA_SCENES_DICT].include?(name) ||
                (name.to_s.start_with?(NA_CLOUD_DICT_PREFIX) && name.to_s.sub(NA_CLOUD_DICT_PREFIX, '').match?(NA_ID_PATTERN))
        end

        def self.na_present?(model, name)
            raw = model ? model.get_attribute(name, NA_KEY) : nil
            raw.is_a?(String) && !raw.empty?
        end

        def self.na_parse(raw)
            return nil unless raw.is_a?(String) && !raw.empty?
            JSON.parse(raw)
        rescue JSON::ParserError
            nil
        end

        def self.na_valid_rgb(rgb)
            rgb.is_a?(Array) && rgb.length == 3 && rgb.all? { |value| value.is_a?(Numeric) && value >= 0 && value <= 255 }
        end

        # A name for the UI: the one saved, else the LAS file name without its
        # extension. At most 60 characters.
        def self.na_clean_name(name, file_name)
            clean = name.to_s.strip[0, 60]
            return clean unless clean.empty?
            stem = File.basename(file_name.to_s, '.*').strip[0, 60]
            stem.empty? ? 'Point cloud' : stem
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
