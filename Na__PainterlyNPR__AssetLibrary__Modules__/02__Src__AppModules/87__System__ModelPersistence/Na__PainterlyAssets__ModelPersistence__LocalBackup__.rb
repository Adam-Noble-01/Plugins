# =============================================================================
# NA PAINTERLYNPR ASSETS - MODEL PERSISTENCE - LOCAL BACKUP
# =============================================================================
#
# FILE       : Na__PainterlyAssets__ModelPersistence__LocalBackup__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__NprSettingsBackup
# PURPOSE    : The second copy (the Point Cloud Viewer's rule: two things have
#              to fail before a look is lost). Every time this plugin writes a
#              model's NPR settings, the record is also written to a small JSON
#              file on this PC:
#                91__UserConfig__LocalOnly/Na__PainterlyAssets__ModelBackups/<storeId>.json
#              So when SketchUp is closed (or crashes) without saving the .skp,
#              or the model's record is missing or unreadable, this PC still
#              holds the last look and export settings, and the NPR windows
#              offer Restore.
# CREATED    : 01-Nov-2026 (v0.3.0)
#
# NEVER AUTOMATIC: read when an NPR window shows the model's settings, written
#   back into the model only when the user presses Restore. A failed backup
#   write is logged, never raised: it must not break the change just made.
#
# NEVER LOST: rewritten only after a real change (a write, or an Undo / Redo
#   that changed the record), never by opening or reading. If the file it
#   replaces holds later changes than the ones being written, that file is kept
#   first as <storeId>__superseded__<time>.json (the newest five are kept).
#
# =============================================================================

require 'json'
require 'fileutils'

module Na__PainterlyAssets
    module Na__NprSettingsBackup

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_SCHEMA         = 'Na__PainterlyAssets__NprSettingsBackup'.freeze     unless defined?(NA_SCHEMA)
        NA_SCHEMA_VERSION = 1                                                   unless defined?(NA_SCHEMA_VERSION)
        NA_FOLDER_NAME    = 'Na__PainterlyAssets__ModelBackups'.freeze          unless defined?(NA_FOLDER_NAME)
        NA_ARCHIVES_KEPT  = 5                                                   unless defined?(NA_ARCHIVES_KEPT)

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Write
    # -------------------------------------------------------------------------

        def self.Na__Backup__Folder
            File.join(Na__PainterlyAssets::NA_USER_CONFIG_DIR, NA_FOLDER_NAME)
        end

        def self.Na__Backup__Path(store_id)
            File.join(self.Na__Backup__Folder, "#{store_id.to_s.gsub(/[^A-Za-z0-9_\-]/, '_')}.json")
        end

        # FUNCTION | Mirror What the Model Now Holds (after one of our writes, or an Undo that changed it)
        # ------------------------------------------------------------
        # @param loaded [Hash] a Na__NprSettingsStore.Na__Store__Load result
        def self.Na__Backup__Write(model, loaded)
            return nil unless model && loaded && loaded['state'] == 'ok'
            store_id = (loaded['meta'] || {})['storeId']
            return nil unless store_id
            record = JSON.parse(loaded['raw'])
            data = {
                'schema'        => NA_SCHEMA,
                'schemaVersion' => NA_SCHEMA_VERSION,
                'storeId'       => store_id,
                'writtenAt'     => Time.now.strftime('%Y-%m-%dT%H:%M:%S%z'),
                'modelPath'     => self.na_model_path(model),
                'modelTitle'    => model.title.to_s,
                'record'        => record
            }
            FileUtils.mkdir_p(self.Na__Backup__Folder)
            path = self.Na__Backup__Path(store_id)
            self.na_archive_if_newer(path, record)
            Na__SafeFileWriter.Na__SafeFile__WriteJson(path, data, 4)
            path
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Warn("The local backup of the NPR settings could not be written: #{error.message}")
            nil
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Find and Compare
    # -------------------------------------------------------------------------

        # FUNCTION | This Model's Backup: by its record's id, or (no readable record) the newest saved from this path
        # ------------------------------------------------------------
        # @return [Hash, nil] { 'storeId', 'record', 'writtenAt', 'modelPath', ... }
        def self.Na__Backup__Find(model, loaded)
            store_id = loaded && (loaded['meta'] || {})['storeId']
            if store_id
                found = self.na_read(self.Na__Backup__Path(store_id))
                return found if found
            end
            path = self.na_model_path(model)
            return nil if path.empty? || (loaded && loaded['state'] == 'ok')
            Dir.glob(File.join(self.Na__Backup__Folder, '*.json'))
               .reject { |file| file.include?('__superseded__') }
               .map { |file| self.na_read(file) }
               .compact
               .select { |backup| backup['modelPath'].to_s.casecmp(path).zero? }
               .max_by { |backup| backup['record']['updatedEpoch'].to_f }
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Warn("NPR settings backups could not be searched: #{error.message}")
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Should Restore Be Offered? { 'offer', 'reason', 'savedText' }
        # ------------------------------------------------------------
        # Offered when the model holds no record and this PC does, or when this
        # PC's copy of the same record holds later changes than the model (the
        # model was closed without saving). Never for a read-only record.
        def self.Na__Backup__Offer(model, loaded)
            return { 'offer' => false } if loaded.nil? || loaded['state'] == 'readOnly'
            backup = self.Na__Backup__Find(model, loaded)
            return { 'offer' => false } unless backup
            saved = Time.at(backup['record']['updatedEpoch'].to_f).strftime('%d %b %Y %H:%M')
            if loaded['state'] == 'none'
                return { 'offer' => true, 'savedText' => saved, 'reason' => "This model holds no NPR settings, but this PC kept a copy of the settings saved from a model at this same path (#{saved})." }
            end
            newer   = backup['record']['updatedEpoch'].to_f > loaded['meta']['updatedEpoch'].to_f + 0.0005
            differs = self.na_blocks(backup['record']) != (loaded['blocks'] || {})
            return { 'offer' => false } unless newer && differs
            { 'offer' => true, 'savedText' => saved, 'reason' => "This PC holds later NPR settings for this model than the model itself (#{saved}): it was probably closed without saving." }
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals
    # -------------------------------------------------------------------------

        def self.na_model_path(model)
            model.path.to_s.tr('\\', '/')
        end

        def self.na_blocks(record)
            Na__NprSettingsStore::NA_BLOCKS.each_with_object({}) { |name, out| out[name] = record[name] if record[name].is_a?(Hash) }
        end

        def self.na_archive_if_newer(path, record)
            existing = self.na_read(path)
            return unless existing
            older   = existing['record']['updatedEpoch'].to_f > record['updatedEpoch'].to_f
            differs = self.na_blocks(existing['record']) != self.na_blocks(record)
            return unless older && differs
            stamp = Time.now.strftime('%Y%m%d-%H%M%S')
            FileUtils.cp(path, path.sub(/\.json\z/, "__superseded__#{stamp}.json"))
            archives = Dir.glob(path.sub(/\.json\z/, '__superseded__*.json')).sort
            archives.first([archives.length - NA_ARCHIVES_KEPT, 0].max).each { |old| File.delete(old) }
        end

        def self.na_read(path)
            data = Na__SafeFileWriter.Na__SafeFile__ReadJson(path)
            return nil unless data.is_a?(Hash) && data['schema'] == NA_SCHEMA && data['schemaVersion'].to_i <= NA_SCHEMA_VERSION
            return nil unless data['record'].is_a?(Hash) && data['record']['schema'] == Na__NprSettingsStore::NA_SCHEMA
            data
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
