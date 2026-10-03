# =============================================================================
# NA POINT CLOUD VIEWER - PERSISTENCE - MODEL LINK
# =============================================================================
#
# FILE       : Na__PointCloudViewer__Persistence__ModelLink__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__ModelLink
# PURPOSE    : Tells a model which point cloud belongs to it, and brings that
#              cloud back when the user asks.
#
# WHAT IS STORED IN THE MODEL (three model-level attribute dictionaries, each
#   one small JSON string; no entities, no file references SketchUp follows,
#   nothing that runs on open, so a model opens normally with or without this
#   plugin and whether or not the LAS exists):
#     Na__PointCloudViewer__ModelLink  which LAS: file name, last path, path
#                                      relative to the .skp, unit, point count,
#                                      fingerprint, link id
#     Na__PointCloudViewer__Placement  position, rotation, gimbal point, lock
#     Na__PointCloudViewer__ClipState  clip box and clip scenes
#   A copy of all three is kept on this computer (Na__LocalBackup).
#
# NOTHING HAPPENS ON OPEN. The View tab shows the link and a Reload Point
#   Cloud button. Reload finds the LAS (last path, then beside the .skp, then
#   this computer's backup path, then the last import folder), reads only its
#   header, and loads it only if the header matches the link's fingerprint
#   (point count + survey origin). A moved or renamed LAS can be pointed to
#   with Locate LAS; the same check applies.
#
# =============================================================================

module Na__PointCloudViewer
    module Na__ModelLink

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_DICT           = 'Na__PointCloudViewer__ModelLink'.freeze
        NA_KEY            = 'json'.freeze
        NA_SCHEMA         = 'Na__PointCloudViewer__ModelLink'.freeze
        NA_SCHEMA_VERSION = 1
        NA_ALL_DICTS      = [NA_DICT, 'Na__PointCloudViewer__Placement', 'Na__PointCloudViewer__ClipState'].freeze

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Read
    # -------------------------------------------------------------------------

        def self.Na__Link__Read(model)
            raw = model ? model.get_attribute(NA_DICT, NA_KEY) : nil
            return nil unless raw.is_a?(String) && !raw.empty?
            data = JSON.parse(raw)
            return nil unless data.is_a?(Hash) && data['schema'] == NA_SCHEMA && data['schemaVersion'].to_i <= NA_SCHEMA_VERSION
            cloud = data['cloud']
            return nil unless data['linkId'].is_a?(String) && cloud.is_a?(Hash) && cloud['fingerprint'].is_a?(String)
            return nil unless Na__UnitContract.Na__Units__IsSupportedSourceUnit?(cloud['sourceUnit'])
            data
        rescue JSON::ParserError => error
            Na__DebugTools.Na__Debug__Warn("The point cloud link saved in this model could not be read: #{error.message}")
            nil
        end

        # Something is stored but it cannot be read (as opposed to no link).
        def self.Na__Link__Unreadable?(model)
            raw = model ? model.get_attribute(NA_DICT, NA_KEY) : nil
            raw.is_a?(String) && !raw.empty? && self.Na__Link__Read(model).nil?
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Fingerprints
    # -------------------------------------------------------------------------

        # Point count + survey origin (the header box's centre x, centre y and
        # min z, exactly as the engine computes it). The file name is not part
        # of it, so a renamed or moved copy of the same LAS still matches.
        def self.Na__Link__FingerprintFromHeader(info)
            origin = [(info['minX'].to_f + info['maxX'].to_f) * 0.5, (info['minY'].to_f + info['maxY'].to_f) * 0.5, info['minZ'].to_f]
            "#{info['pointCount'].to_i}|#{origin.map { |v| format('%.3f', v) }.join(',')}"
        end

        # The same fingerprint from a placement key ("name|count|origin").
        def self.Na__Link__FingerprintFromKey(key)
            key.to_s.split('|').last(2).join('|')
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | After an Import (record the link; no write if nothing changed)
    # -------------------------------------------------------------------------

        def self.Na__Link__AfterImport(session, cloud)
            model = session.model
            return unless model && session.placement
            current = self.Na__Link__Read(model)
            fingerprint = self.Na__Link__FingerprintFromKey(session.placement['key'])
            same_cloud = current && current['cloud']['fingerprint'] == fingerprint
            cloud_part = {
                'fileName'     => File.basename(cloud.source_path.to_s),
                'lastPath'     => cloud.source_path.to_s.tr('\\', '/'),
                'relativePath' => self.na_relative_path(model, cloud.source_path.to_s),
                'sourceUnit'   => cloud.source_unit,
                'pointCount'   => cloud.total_points,
                'fingerprint'  => fingerprint
            }
            changed = !(same_cloud && current['cloud'] == cloud_part)
            if changed
                now = Time.now
                record = {
                    'schema'        => NA_SCHEMA,
                    'schemaVersion' => NA_SCHEMA_VERSION,
                    'linkId'        => same_cloud ? current['linkId'] : self.na_new_link_id(now),
                    'createdAt'     => same_cloud ? current['createdAt'] : now.strftime('%Y-%m-%dT%H:%M:%S%z'),
                    'updatedAt'     => now.strftime('%Y-%m-%dT%H:%M:%S%z'),
                    'pluginVersion' => Na__PointCloudViewer.Na__PublicApi__Version,
                    'cloud'         => cloud_part
                }
                self.na_write(model, same_cloud ? 'Point Cloud: Update LAS Location' : 'Point Cloud: Link LAS to Model') do
                    model.set_attribute(NA_DICT, NA_KEY, JSON.generate(record))
                end
            end
            # A plain reload changes nothing in the model, and must not replace a
            # backup that may hold newer, unsaved work.
            first_backup = !File.exist?(Na__LocalBackup.Na__Backup__Path(self.Na__Link__Read(model)['linkId']))
            Na__LocalBackup.Na__Backup__AfterSave(model, session) if changed || first_backup
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('The point cloud link could not be saved in the model.', error)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Reload + Locate (explicit user actions only)
    # -------------------------------------------------------------------------

        # Returns nil when the import has started, or a plain-English reason.
        def self.Na__Link__Reload(session)
            model = session.model
            link = self.Na__Link__Read(model)
            return 'This model has no point cloud link to reload.' unless link
            backup = Na__LocalBackup.Na__Backup__Find(model, link)
            match, mismatched = self.na_find_matching_file(self.na_candidates(model, link, backup), link['cloud']['fingerprint'])
            unless match
                name = link['cloud']['fileName']
                return "#{name} is at a different location now. Use Locate LAS to point to it." if mismatched.empty?
                return "A file called #{name} was found, but it is not the same scan (different point count or position). Use Locate LAS to choose the right file."
            end
            self.na_start_import(session, match[0], link['cloud']['sourceUnit'], match[1])
        end

        def self.Na__Link__Locate(session)
            model = session.model
            link = self.Na__Link__Read(model)
            return 'This model has no point cloud link to locate.' unless link
            start = model.path.to_s.empty? ? '' : File.dirname(model.path)
            path = UI.openpanel("Locate #{link['cloud']['fileName']}", start, 'LAS point cloud (*.las)|*.las||')
            return 'Locate cancelled.' unless path
            match, = self.na_find_matching_file([path], link['cloud']['fingerprint'])
            unless match
                return "That file is not the scan this model was linked to (#{Na__PerfStats.Na__Perf__Thousands(link['cloud']['pointCount'])} points). Nothing was loaded."
            end
            self.na_start_import(session, match[0], link['cloud']['sourceUnit'], match[1])
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Restore From Backup + Remove (explicit user actions only)
    # -------------------------------------------------------------------------

        # Writes this computer's copy of the link, position and clip records
        # back into the model as ONE undoable operation.
        def self.Na__Link__RestoreBackup(session)
            model = session.model
            backup = Na__LocalBackup.Na__Backup__Find(model, self.Na__Link__Read(model))
            return 'There is no backup on this computer for this model.' unless backup
            self.na_write(model, 'Point Cloud: Restore From Backup') do
                model.set_attribute(NA_DICT, NA_KEY, JSON.generate(backup['link']))
                model.set_attribute(Na__Placement::NA_DICT, 'json', JSON.generate(backup['placement'])) if backup['placement']
                model.set_attribute(Na__ClipBox::NA_DICT, 'json', JSON.generate(backup['clip'])) if backup['clip']
            end
            Na__ModelRegistry.Na__Registry__ReloadModelState(model)
            nil
        end

        # The escape hatch: removes every point cloud record from the model
        # (one undoable operation). This computer's backup is kept.
        def self.Na__Link__RemoveFromModel(session)
            model = session.model
            return 'There is no model.' unless model
            Na__Placement.Na__Placement__StopTool(session)
            Na__ClipBox.Na__Clip__StopEditing(session) if session.clip_editing
            dictionaries = model.attribute_dictionaries
            present = NA_ALL_DICTS.select { |name| dictionaries && dictionaries[name] }
            return 'This model holds no point cloud data.' if present.empty?
            self.na_write(model, 'Point Cloud: Remove From Model') do
                present.each { |name| dictionaries.delete(name) }
            end
            Na__ModelRegistry.Na__Registry__ReloadModelState(model)
            nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Dialog Payload
    # -------------------------------------------------------------------------

        def self.Na__Link__Payload(session, model)
            return { 'state' => 'none' } unless session && model
            link   = self.Na__Link__Read(model)
            backup = Na__LocalBackup.Na__Backup__Find(model, link)
            unreadable = self.Na__Link__Unreadable?(model)
            return { 'state' => 'none', 'backupsFolder' => Na__LocalBackup.Na__Backup__Folder } unless link || backup
            compare = Na__LocalBackup.Na__Backup__Compare(model, backup)
            source = link || backup['link']
            cloud  = source['cloud']
            loaded = session.cloud && session.placement &&
                     self.Na__Link__FingerprintFromKey(session.placement['key']) == cloud['fingerprint'] ? true : false
            found = link ? self.na_first_existing(self.na_candidates(model, link, backup)) : nil
            stored_placement = Na__Placement.na_read(model)
            {
                'state'         => link ? 'linked' : 'backupOnly',
                'unreadable'    => unreadable,
                'loaded'        => loaded,
                'otherLoaded'   => session.cloud && !loaded ? true : false,
                'fileName'      => cloud['fileName'],
                'unitLabel'     => Na__UnitContract.Na__Units__SourceUnitLabel(cloud['sourceUnit']),
                'pointsText'    => Na__PerfStats.Na__Perf__Thousands(cloud['pointCount']),
                'lastPath'      => cloud['lastPath'],
                'foundPath'     => found,
                'positionText'  => self.na_position_text(stored_placement),
                'backup'        => {
                    'exists'    => !backup.nil?,
                    'newer'     => compare['newer'] || (backup && !link) ? true : false,
                    'savedText' => compare['backupSavedText']
                },
                'backupsFolder' => Na__LocalBackup.Na__Backup__Folder
            }
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Warn("Point cloud link status could not be built: #{error.message}")
            { 'state' => 'none' }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals
    # -------------------------------------------------------------------------

        # Every model write: one named operation, aborted on any error so a
        # half-written change never stays in the model.
        def self.na_write(model, operation_name)
            model.start_operation(operation_name, true)
            yield
            model.commit_operation
        rescue StandardError
            model.abort_operation
            raise
        end

        def self.na_new_link_id(now)
            "PCV-#{now.strftime('%Y%m%d-%H%M%S')}-#{format('%06x', rand(0x1000000))}"
        end

        # The LAS path relative to the .skp's folder, or nil (unsaved model, or
        # a different drive). Lets a project folder move between computers.
        def self.na_relative_path(model, las_path)
            return nil if model.path.to_s.empty?
            folder = File.dirname(File.expand_path(model.path))
            target = File.expand_path(las_path)
            return nil unless folder[0, 2].casecmp(target[0, 2]).zero?
            from = folder.tr('\\', '/').split('/')
            to   = target.tr('\\', '/').split('/')
            common = 0
            common += 1 while common < from.length && common < to.length - 1 && from[common].casecmp(to[common]).zero?
            (['..'] * (from.length - common) + to[common..]).join('/')
        rescue StandardError
            nil
        end

        def self.na_candidates(model, link, backup)
            cloud  = link['cloud']
            folder = model.path.to_s.empty? ? nil : File.dirname(model.path)
            list = [cloud['lastPath']]
            list << File.expand_path(cloud['relativePath'], folder) if folder && cloud['relativePath'].is_a?(String)
            list << File.join(folder, cloud['fileName']) if folder
            list << backup['link']['cloud']['lastPath'] if backup && backup['link']['cloud'].is_a?(Hash)
            last_folder = Na__UserConfigStore.Na__UserConfig__Get('import', 'lastFolder', '')
            list << File.join(last_folder, cloud['fileName']) if last_folder.is_a?(String) && !last_folder.empty?
            list.compact.map { |path| path.to_s.tr('\\', '/') }.reject(&:empty?).uniq { |path| path.downcase }
        end

        def self.na_first_existing(paths)
            paths.find { |path| File.file?(path) }
        end

        # [[path, header_ms], mismatched_paths]. Reads only LAS headers.
        def self.na_find_matching_file(paths, fingerprint)
            mismatched = []
            paths.each do |path|
                next unless File.file?(path) && File.extname(path).casecmp('.las').zero?
                info, header_ms = Na__PerfStats.Na__Perf__Measure { Na__NativeEngine.Na__Native__LasReadHeader(path) }
                if info['isCompressed'].to_i != 1 && self.Na__Link__FingerprintFromHeader(info) == fingerprint
                    return [[path, header_ms], mismatched]
                end
                mismatched << path
            rescue StandardError => error
                Na__DebugTools.Na__Debug__Warn("Could not read the header of #{path}: #{error.message}")
                mismatched << path
            end
            [nil, mismatched]
        end

        def self.na_start_import(session, path, unit, header_ms)
            return 'Another task is still running.' if Na__AsyncJobs.Na__Jobs__Busy?
            Na__UserConfigStore.Na__UserConfig__Set('import', 'lastFolder', File.dirname(path))
            Na__LasImport.Na__LasImport__Start('path' => path, 'sourceUnit' => unit, 'headerMs' => header_ms)
            nil
        end

        def self.na_position_text(placement)
            return 'No position saved yet: the cloud loads at its import position.' unless placement
            moved = !Na__Placement.na_identity?(placement)
            lock  = placement['locked'] ? 'locked' : 'unlocked'
            moved ? "Its saved position is restored (#{lock})." : "It loads at its import position (#{lock})."
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
