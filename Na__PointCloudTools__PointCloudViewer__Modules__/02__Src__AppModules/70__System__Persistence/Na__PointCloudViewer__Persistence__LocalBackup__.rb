# =============================================================================
# NA POINT CLOUD VIEWER - PERSISTENCE - LOCAL BACKUP
# =============================================================================
#
# FILE       : Na__PointCloudViewer__Persistence__LocalBackup__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__LocalBackup
# PURPOSE    : The second copy. Every time the model's point cloud records
#              change (link, position, clip box, scenes), the same records are
#              written to a small JSON file on this computer:
#                91__UserConfig__LocalOnly/Na__PointCloudViewer__ModelBackups/<linkId>.json
#              So two things have to fail before a day's alignment is lost:
#              the model's own copy AND this file. Typical saves:
#                - SketchUp closed (or crashed) without saving the .skp: the
#                  file holds the newer position; Reload offers to restore it.
#                - the model's records are missing or unreadable: the file
#                  holds the last good copy.
#
# NEVER AUTOMATIC: this file is only read when the dialog shows the model's
#   link card, and only written back into the model when the user presses
#   Restore. A failed backup write is logged, never raised: it must not break
#   the change the user just made.
#
# NEVER LOST: the file is only rewritten after a real point cloud change (a
#   save, or an Undo / Redo that changed these records), never by opening,
#   reloading or an unrelated Undo. If the file it replaces holds later
#   changes than the ones being written, that file is kept first as
#   <linkId>__superseded__<time>.json (the newest five are kept).
#
# =============================================================================

module Na__PointCloudViewer
    module Na__LocalBackup

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_SCHEMA         = 'Na__PointCloudViewer__LocalBackup'.freeze
        NA_SCHEMA_VERSION = 1
        NA_FOLDER_NAME    = 'Na__PointCloudViewer__ModelBackups'.freeze
        NA_ARCHIVES_KEPT  = 5

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Write
    # -------------------------------------------------------------------------

        def self.Na__Backup__Folder
            File.join(Na__AssetResolver.Na__Paths__UserConfigFolder, NA_FOLDER_NAME)
        end

        def self.Na__Backup__Path(link_id)
            File.join(self.Na__Backup__Folder, "#{link_id.to_s.gsub(/[^A-Za-z0-9_\-]/, '_')}.json")
        end

        # Mirrors the model's current records. Needs a link: a model with no
        # point cloud has nothing worth backing up.
        def self.Na__Backup__Write(model)
            return unless model
            link = Na__ModelLink.Na__Link__Read(model)
            return unless link
            data = {
                'schema'        => NA_SCHEMA,
                'schemaVersion' => NA_SCHEMA_VERSION,
                'linkId'        => link['linkId'],
                'writtenAt'     => Time.now.strftime('%Y-%m-%dT%H:%M:%S%z'),
                'modelPath'     => model.path.to_s.tr('\\', '/'),
                'modelTitle'    => model.title.to_s,
                'link'          => link,
                'placement'     => self.na_raw_record(model, Na__Placement::NA_DICT),
                'clip'          => self.na_raw_record(model, Na__ClipBox::NA_DICT)
            }
            path = self.Na__Backup__Path(link['linkId'])
            self.na_archive_if_newer(path, data)
            Na__SafeFileWriter.Na__SafeFile__WriteJson(path, data)
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Warn("The local backup of the point cloud setup could not be written: #{error.message}")
            nil
        end

        # After one of our own saves: remember what the model now holds, then
        # mirror it.
        def self.Na__Backup__AfterSave(model, session)
            session.persist_snapshot = self.na_raw_strings(model) if session
            self.Na__Backup__Write(model)
        end

        # After Undo / Redo: mirror only if our records actually changed, so an
        # unrelated Undo (a line, a face) never touches the backup.
        def self.Na__Backup__AfterReload(model, session)
            raws = self.na_raw_strings(model)
            changed = session.persist_snapshot && session.persist_snapshot != raws
            session.persist_snapshot = raws
            self.Na__Backup__Write(model) if changed
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Find + Compare
    # -------------------------------------------------------------------------

        # The backup for this model: by the link id stored in the model, or,
        # when the model has no readable link, the newest backup made from a
        # model saved at this same path.
        def self.Na__Backup__Find(model, link)
            if link
                found = self.na_read(self.Na__Backup__Path(link['linkId']))
                return found if found
            end
            path = model.path.to_s.tr('\\', '/')
            return nil if path.empty?
            Dir.glob(File.join(self.Na__Backup__Folder, '*.json'))
               .reject { |file| file.include?('__superseded__') }
               .map { |file| self.na_read(file) }
               .compact
               .select { |backup| backup['modelPath'].to_s.casecmp(path).zero? }
               .max_by { |backup| self.na_latest_epoch(backup) }
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Warn("Point cloud backups could not be searched: #{error.message}")
            nil
        end

        # { 'differs', 'newer' (the backup holds later changes than the model),
        #   'backupSavedText' }
        def self.Na__Backup__Compare(model, backup)
            return { 'differs' => false, 'newer' => false } unless backup
            model_records  = { 'placement' => self.na_raw_record(model, Na__Placement::NA_DICT),
                               'clip'      => self.na_raw_record(model, Na__ClipBox::NA_DICT) }
            differs = %w[placement clip].any? { |key| self.na_strip(model_records[key]) != self.na_strip(backup[key]) }
            model_epoch  = %w[placement clip].map { |key| self.na_epoch(model_records[key]) }.max
            backup_epoch = self.na_latest_epoch(backup)
            {
                'differs'         => differs,
                'newer'           => differs && backup_epoch > model_epoch,
                'backupSavedText' => backup_epoch > 0 ? Time.at(backup_epoch).strftime('%d %b %Y %H:%M') : 'unknown time'
            }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals
    # -------------------------------------------------------------------------

        def self.na_raw_strings(model)
            [Na__ModelLink::NA_DICT, Na__Placement::NA_DICT, Na__ClipBox::NA_DICT].map { |dict| model.get_attribute(dict, 'json') }
        end

        def self.na_archive_if_newer(path, data)
            existing = self.na_read(path)
            return unless existing
            differs = %w[placement clip].any? { |key| self.na_strip(existing[key]) != self.na_strip(data[key]) }
            return unless differs && self.na_latest_epoch(existing) > self.na_latest_epoch(data)
            stamp = Time.now.strftime('%Y%m%d-%H%M%S')
            FileUtils.cp(path, path.sub(/\.json\z/, "__superseded__#{stamp}.json"))
            archives = Dir.glob(path.sub(/\.json\z/, '__superseded__*.json')).sort
            archives.first([archives.length - NA_ARCHIVES_KEPT, 0].max).each { |old| File.delete(old) }
        end

        # The record exactly as stored in the model (parsed JSON), or nil.
        def self.na_raw_record(model, dict)
            raw = model.get_attribute(dict, 'json')
            return nil unless raw.is_a?(String) && !raw.empty?
            parsed = JSON.parse(raw)
            parsed.is_a?(Hash) ? parsed : nil
        rescue JSON::ParserError
            nil
        end

        def self.na_read(path)
            data = Na__SafeFileWriter.Na__SafeFile__ReadJson(path)
            return nil unless data && data['schema'] == NA_SCHEMA && data['schemaVersion'].to_i <= NA_SCHEMA_VERSION
            return nil unless data['link'].is_a?(Hash) && data['linkId'].is_a?(String)
            data
        end

        # Records compare equal whatever their timestamps.
        def self.na_strip(record)
            record.is_a?(Hash) ? record.reject { |key, _| %w[updatedAt updatedEpoch].include?(key) } : nil
        end

        def self.na_epoch(record)
            record.is_a?(Hash) ? record['updatedEpoch'].to_f : 0.0
        end

        def self.na_latest_epoch(backup)
            %w[placement clip].map { |key| self.na_epoch(backup[key]) }.max
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
