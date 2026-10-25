# =============================================================================
# NA POINT CLOUD VIEWER - PERSISTENCE - LOCAL BACKUP
# =============================================================================
#
# FILE       : Na__PointCloudViewer__Persistence__LocalBackup__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__LocalBackup
# PURPOSE    : The second copy. Every time the model's point cloud records
#              change (any cloud's link, position, clip box, name or colour,
#              the list of clouds, the scenes), every one of those records is
#              written to a small JSON file on this computer:
#                91__UserConfig__LocalOnly/Na__PointCloudViewer__ModelBackups/<modelId>.json
#              So two things have to fail before a day's alignment is lost:
#              the model's own copy AND this file. Typical saves:
#                - SketchUp closed (or crashed) without saving the .skp: the
#                  file holds the newer positions; the dialog offers to restore.
#                - the model's records are missing or unreadable: the file
#                  holds the last good copy.
#
# SCHEMA 2 (v0.10.0): 'records' holds every point cloud record of the model by
#   its dictionary name (the index, one per cloud, the scenes), exactly as the
#   model held them, so Restore writes back the same records. A v0.9 backup
#   (link, placement, clip and scenes of the one cloud) is still read, and
#   restores the model's v0.9 records. The file is named by the model's id: a
#   v0.9 model keeps its link id, so its backup file carries on.
#
# NEVER AUTOMATIC: this file is only read when the dialog shows the model's
#   point clouds, and only written back into the model when the user presses
#   Restore. A failed backup write is logged, never raised: it must not break
#   the change the user just made.
#
# NEVER LOST: the file is only rewritten after a real point cloud change (a
#   save, or an Undo / Redo that changed these records), never by opening,
#   reloading or an unrelated Undo. If the file it replaces holds later
#   changes than the ones being written, that file is kept first as
#   <modelId>__superseded__<time>.json (the newest five are kept).
#
# =============================================================================

module Na__PointCloudViewer
    module Na__LocalBackup

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_SCHEMA         = 'Na__PointCloudViewer__LocalBackup'.freeze
        NA_SCHEMA_VERSION = 2
        NA_FOLDER_NAME    = 'Na__PointCloudViewer__ModelBackups'.freeze
        NA_ARCHIVES_KEPT  = 5
        NA_SCENES_DICT    = 'Na__PointCloudViewer__Scenes'.freeze
        NA_V1_RECORD_DICTS = {
            'link'      => 'Na__PointCloudViewer__ModelLink',
            'placement' => 'Na__PointCloudViewer__Placement',
            'clip'      => 'Na__PointCloudViewer__ClipState',
            'scenes'    => 'Na__PointCloudViewer__Scenes'
        }.freeze
        NA_STAMP_KEYS     = %w[updatedAt updatedEpoch pluginVersion].freeze

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Write
    # -------------------------------------------------------------------------

        def self.Na__Backup__Folder
            File.join(Na__AssetResolver.Na__Paths__UserConfigFolder, NA_FOLDER_NAME)
        end

        def self.Na__Backup__Path(model_id)
            File.join(self.Na__Backup__Folder, "#{model_id.to_s.gsub(/[^A-Za-z0-9_\-]/, '_')}.json")
        end

        # Mirrors the model's current records. Needs a model id: a model with no
        # point cloud has nothing worth backing up.
        def self.Na__Backup__Write(model, session)
            return unless model && session
            model_id = Na__CloudStore.Na__Store__ModelId(session)
            return unless model_id
            records = Na__CloudStore.Na__Store__RawRecords(model)
            return if records.empty?
            data = {
                'schema'        => NA_SCHEMA,
                'schemaVersion' => NA_SCHEMA_VERSION,
                'modelId'       => model_id,
                'writtenAt'     => Time.now.strftime('%Y-%m-%dT%H:%M:%S%z'),
                'modelPath'     => model.path.to_s.tr('\\', '/'),
                'modelTitle'    => model.title.to_s,
                'records'       => records
            }
            path = self.Na__Backup__Path(model_id)
            self.na_archive_if_newer(path, data)
            Na__SafeFileWriter.Na__SafeFile__WriteJson(path, data)
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Warn("The local backup of the point cloud setup could not be written: #{error.message}")
            nil
        end

        # After one of our own saves: remember what the model now holds, then
        # mirror it.
        def self.Na__Backup__AfterSave(model, session)
            session.persist_snapshot = Na__CloudStore.Na__Store__RawStrings(model) if session
            self.Na__Backup__Write(model, session)
        end

        # After Undo / Redo: mirror only if our records actually changed, so an
        # unrelated Undo (a line, a face) never touches the backup.
        def self.Na__Backup__AfterReload(model, session)
            raws = Na__CloudStore.Na__Store__RawStrings(model)
            changed = session.persist_snapshot && session.persist_snapshot != raws
            session.persist_snapshot = raws
            self.Na__Backup__Write(model, session) if changed
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Find + Compare
    # -------------------------------------------------------------------------

        # The backup for this model: by the model's id, or, when the model holds
        # no readable point cloud records, the newest backup made from a model
        # saved at this same path. { 'modelId', 'records', ... } or nil.
        def self.Na__Backup__Find(model, session)
            model_id = session ? Na__CloudStore.Na__Store__ModelId(session) : nil
            if model_id
                found = self.na_read(self.Na__Backup__Path(model_id))
                return found if found
            end
            path = model.path.to_s.tr('\\', '/')
            return nil if path.empty?
            Dir.glob(File.join(self.Na__Backup__Folder, '*.json'))
               .reject { |file| file.include?('__superseded__') }
               .map { |file| self.na_read(file) }
               .compact
               .select { |backup| backup['modelPath'].to_s.casecmp(path).zero? }
               .max_by { |backup| self.na_latest_epoch(backup['records']) }
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Warn("Point cloud backups could not be searched: #{error.message}")
            nil
        end

        # { 'differs', 'newer' (the backup holds later changes than the model),
        #   'backupSavedText' }. Where a LAS file sits is not compared: it can
        #   differ between computers without anything being lost.
        def self.Na__Backup__Compare(model, backup)
            return { 'differs' => false, 'newer' => false } unless backup
            model_records  = Na__CloudStore.Na__Store__RawRecords(model)
            backup_records = backup['records'] || {}
            names = (model_records.keys + backup_records.keys).uniq
            differs = names.any? { |name| self.na_comparable(name, model_records[name]) != self.na_comparable(name, backup_records[name]) }
            model_epoch  = self.na_latest_epoch(model_records)
            backup_epoch = self.na_latest_epoch(backup_records)
            {
                'differs'         => differs,
                'newer'           => differs && backup_epoch > model_epoch,
                'backupSavedText' => backup_epoch > 0 ? Time.at(backup_epoch).strftime('%d %b %Y %H:%M') : 'unknown time'
            }
        end

        # The cloud names a backup holds (for the dialog), in its index order.
        def self.Na__Backup__CloudNames(backup)
            records = backup ? backup['records'] || {} : {}
            names = records.select { |name, _| name.start_with?(Na__CloudStore::NA_CLOUD_DICT_PREFIX) }.values.map { |record| record['name'].to_s }
            if names.empty? && records['Na__PointCloudViewer__ModelLink'].is_a?(Hash)
                names << records['Na__PointCloudViewer__ModelLink'].dig('cloud', 'fileName').to_s
            end
            names.reject(&:empty?)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals
    # -------------------------------------------------------------------------

        def self.na_archive_if_newer(path, data)
            existing = self.na_read(path)
            return unless existing
            names = (existing['records'].keys + data['records'].keys).uniq
            differs = names.any? { |name| self.na_comparable(name, existing['records'][name]) != self.na_comparable(name, data['records'][name]) }
            return unless differs && self.na_latest_epoch(existing['records']) > self.na_latest_epoch(data['records'])
            stamp = Time.now.strftime('%Y%m%d-%H%M%S')
            FileUtils.cp(path, path.sub(/\.json\z/, "__superseded__#{stamp}.json"))
            archives = Dir.glob(path.sub(/\.json\z/, '__superseded__*.json')).sort
            archives.first([archives.length - NA_ARCHIVES_KEPT, 0].max).each { |old| File.delete(old) }
        end

        # A backup file in either schema, as { 'modelId', 'modelPath', 'records', ... }.
        def self.na_read(path)
            data = Na__SafeFileWriter.Na__SafeFile__ReadJson(path)
            return nil unless data && data['schema'] == NA_SCHEMA
            version = data['schemaVersion'].to_i
            if version >= 2
                return nil unless version <= NA_SCHEMA_VERSION && data['modelId'].is_a?(String) && data['records'].is_a?(Hash)
                return data
            end
            # v1 (v0.9): one cloud's link, placement and clip, and the scenes
            return nil unless data['link'].is_a?(Hash) && data['linkId'].is_a?(String)
            records = NA_V1_RECORD_DICTS.each_with_object({}) { |(key, dict), out| out[dict] = data[key] if data[key].is_a?(Hash) }
            data.merge('modelId' => data['linkId'], 'records' => records, 'fromVersion' => 1)
        end

        # A record as it is compared: without its time stamps, and without where
        # the LAS sits (a cloud's link part, or a v0.9 link record).
        def self.na_comparable(name, record)
            return nil unless record.is_a?(Hash)
            return nil if name == 'Na__PointCloudViewer__ModelLink'
            stripped = record.reject { |key, _| NA_STAMP_KEYS.include?(key) }
            stripped = stripped.reject { |key, _| key == 'link' } if name.to_s.start_with?(Na__CloudStore::NA_CLOUD_DICT_PREFIX)
            stripped
        end

        def self.na_epoch(record)
            record.is_a?(Hash) ? record['updatedEpoch'].to_f : 0.0
        end

        def self.na_latest_epoch(records)
            (records || {}).values.map { |record| self.na_epoch(record) }.max || 0.0
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
