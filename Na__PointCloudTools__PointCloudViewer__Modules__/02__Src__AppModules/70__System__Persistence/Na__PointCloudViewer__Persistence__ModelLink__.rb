# =============================================================================
# NA POINT CLOUD VIEWER - PERSISTENCE - MODEL LINK
# =============================================================================
#
# FILE       : Na__PointCloudViewer__Persistence__ModelLink__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__ModelLink
# PURPOSE    : Tells a model which LAS each of its point clouds uses, and brings
#              those clouds back when the user asks.
#
# WHAT IS STORED IN THE MODEL: each cloud's own record (Na__CloudStore) holds,
#   with its position and clip box, the 'link' part: file name, last path, path
#   relative to the .skp, unit, point count, fingerprint, content key, and for
#   a cleaned copy what it was made from, with the files it named before. No
#   entities, no file references SketchUp follows, nothing that runs on open,
#   so a model opens normally with or without this plugin and whether or not
#   the LAS files exist. A copy of every record is kept on this computer
#   (Na__LocalBackup).
#
# NOTHING HAPPENS ON OPEN. The View tab lists the clouds with a Reload button
#   each (and Reload All). Reload finds the LAS (last path, then relative to
#   and beside the .skp, then this computer's backup path, then the last import
#   folder), reads only its header, and loads it only if the header matches the
#   link's fingerprint (point count + survey origin) AND, when the link records
#   one, its content key: a cleaned copy with the same count and position is
#   never taken for its original, nor the other way round. A moved or renamed
#   LAS can be pointed to with Locate LAS; the same checks apply.
#
# CLEANED COPIES: after Clean & Export LAS, the cloud's link points to the NEW
#   file (derivedFrom names the file it was made from; history keeps every
#   earlier file). It is one undoable operation, so SketchUp's Undo can put
#   the link back to the earlier file. Undo never deletes or changes a file.
#
# =============================================================================

module Na__PointCloudViewer
    module Na__ModelLink

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_DICT           = 'Na__PointCloudViewer__ModelLink'.freeze   # v0.9 models only (read by Na__CloudStore)
        NA_KEY            = 'json'.freeze
        NA_SCHEMA         = 'Na__PointCloudViewer__ModelLink'.freeze
        NA_SCHEMA_VERSION = 1

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

        # slot: the cloud the import loaded. A new cloud (no record yet) is
        # added to the model; a known one is only written when its file moved.
        # A plain reload writes nothing (a v0.9 model stays exactly as it is).
        def self.Na__Link__AfterImport(slot, cloud)
            model = slot.model
            return unless model && slot.placement
            current = slot.record ? slot.record['link'] : nil
            part = self.Na__Link__CloudPart(model, cloud, slot.placement['key'])
            same_cloud = current && self.na_same_cloud_part?(current, part)
            if same_cloud
                # a cleaned copy loaded again keeps what it was made from, and its history
                part['derivedFrom'] = current['derivedFrom'] if current['derivedFrom']
                part['contentKey'] ||= current['contentKey'] if current['contentKey']
                part['history'] = current['history'] if current['history']
                part['linkedAt'] = current['linkedAt'] if current['linkedAt']
            end
            part['linkedAt'] ||= Time.now.strftime('%Y-%m-%dT%H:%M:%S%z')
            changed = !(same_cloud && self.na_link_core(current) == self.na_link_core(part))
            new_cloud = slot.record.nil?
            if changed || new_cloud
                name = if new_cloud
                           saved_before = Na__CloudSet.Na__Slots__All(slot.session).count { |other| %w[saved legacy].include?(other.record_state) }
                           saved_before.zero? ? 'Point Cloud: Link LAS to Model' : "Point Cloud: Add #{slot.name}"
                       else
                           Na__CloudSet.Na__Slots__OpName(slot, same_cloud ? 'Update LAS Location' : 'Link LAS to Model')
                       end
                problem = Na__CloudStore.Na__Store__WriteSlots(slot.session, [slot], name) do |_slot, record|
                    record['link'] = part
                    record['name'] = slot.name
                    record['colour'] = slot.colour
                    record['placement'] ||= Na__Placement.Na__Placement__Part(slot.placement)
                    record.merge!(Na__ClipBox.Na__Clip__Part(slot)) unless record.key?('clip')
                end
                Na__DebugTools.Na__Debug__Warn("The point cloud link was not saved: #{problem}") if problem
                return
            end
            # A plain reload changes nothing in the model, and must not replace a
            # backup that may hold newer, unsaved work.
            model_id = Na__CloudStore.Na__Store__ModelId(slot.session)
            Na__LocalBackup.Na__Backup__AfterSave(model, slot.session) if model_id && !File.exist?(Na__LocalBackup.Na__Backup__Path(model_id))
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('The point cloud link could not be saved in the model.', error)
        end

        # The link without what may legitimately differ between two loads of
        # the same file.
        def self.na_link_core(part)
            part.is_a?(Hash) ? part.reject { |key, _| %w[linkedAt history].include?(key) } : nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Reload + Locate (explicit user actions only)
    # -------------------------------------------------------------------------

        # Where this cloud's points will come from: { 'kind' => 'las', 'path',
        # 'unit', 'headerMs' } or { 'kind' => 'cache', 'lasPath', 'unit', 'cached' },
        # or a plain-English String when neither can be found.
        # Order: this computer's point cache when the LAS it was made from is
        # found unchanged (fast; decided by the import); else the LAS itself
        # (writes a fresh cache); else, with no matching LAS anywhere, the cache
        # alone (with a note).
        def self.Na__Link__ReloadPlan(slot)
            link = slot && slot.record ? slot.record['link'] : nil
            return 'This point cloud has no saved link to reload.' unless link
            model = slot.model
            backup = Na__LocalBackup.Na__Backup__Find(model, slot.session)
            candidates = self.na_candidates(model, link, self.na_backup_link(backup, slot))
            match, mismatched = self.na_find_matching_file(candidates, link)
            return { 'kind' => 'las', 'path' => match[0], 'unit' => link['sourceUnit'], 'headerMs' => match[1] } if match
            key = link['contentKey']
            cached = key ? Na__PointCache.Na__Cache__ForKey(key) : Na__PointCache.Na__Cache__LegacyForFingerprint(link['fingerprint'])
            return { 'kind' => 'cache', 'lasPath' => link['lastPath'], 'unit' => link['sourceUnit'], 'cached' => cached } if cached
            name = link['fileName']
            return "#{name} is at a different location now. Use Locate LAS to point to it." if mismatched.empty?
            "A file called #{name} was found, but it is not the same scan (different point count or position). Use Locate LAS to choose the right file."
        end

        # Returns nil when the load has started, or a plain-English reason.
        def self.Na__Link__Reload(slot)
            return 'Another task is still running.' if Na__AsyncJobs.Na__Jobs__Busy?
            plan = self.Na__Link__ReloadPlan(slot)
            return plan if plan.is_a?(String)
            job = Na__LasImport.Na__LasImport__JobForPlan(slot, plan)
            Na__UserConfigStore.Na__UserConfig__Set('import', 'lastFolder', File.dirname(plan['path'])) if plan['kind'] == 'las'
            Na__AsyncJobs.Na__Jobs__Start(job) ? nil : 'Another task is still running.'
        end

        # Every cloud of the model that needs it (Na__Link__NeedsReload?), one
        # after the other. Returns nil when the loads have started, or a
        # plain-English reason nothing was started.
        def self.Na__Link__ReloadAll(session)
            return 'Another task is still running.' if Na__AsyncJobs.Na__Jobs__Busy?
            slots = Na__CloudSet.Na__Slots__All(session).select { |slot| self.Na__Link__NeedsReload?(slot) }
            return 'Every point cloud of this model is loaded already.' if slots.empty?
            return self.Na__Link__Reload(slots.first) if slots.length == 1
            job = Na__LasImport::Na__ReloadSeriesJob.new(session, slots)
            Na__AsyncJobs.Na__Jobs__Start(job) ? nil : 'Another task is still running.'
        end

        # The cloud has a record and is not loaded, or what is loaded is not
        # the file its record names (an Undo of Use Cleaned LAS puts the
        # original back in the record while the cleaned cloud stays shown).
        def self.Na__Link__NeedsReload?(slot)
            return false unless slot.record && slot.record['link']
            return true unless slot.cloud
            slot.placement ? !Na__Placement.na_link_names_other(slot).nil? : false
        end

        def self.Na__Link__Locate(slot)
            link = slot && slot.record ? slot.record['link'] : nil
            return 'This point cloud has no saved link to locate.' unless link
            model = slot.model
            start = model.path.to_s.empty? ? '' : File.dirname(model.path)
            path = UI.openpanel("Locate #{link['fileName']}", start, 'LAS point cloud (*.las)|*.las||')
            return 'Locate cancelled.' unless path
            match, = self.na_find_matching_file([path], link)
            unless match
                same = link['contentKey'] ? ' and the same content' : ''
                return "That file is not the scan #{slot.name} was linked to (#{Na__PerfStats.Na__Perf__Thousands(link['pointCount'])} points#{same}). Nothing was loaded."
            end
            return 'Another task is still running.' if Na__AsyncJobs.Na__Jobs__Busy?
            Na__UserConfigStore.Na__UserConfig__Set('import', 'lastFolder', File.dirname(match[0]))
            job = Na__LasImport.Na__LasImport__JobForPlan(slot, { 'kind' => 'las', 'path' => match[0], 'unit' => link['sourceUnit'], 'headerMs' => match[1] })
            Na__AsyncJobs.Na__Jobs__Start(job) ? nil : 'Another task is still running.'
        end

        # The first place this cloud's LAS is found now (for the dialog), or nil.
        def self.Na__Link__FoundPath(model, slot, backup)
            link = slot.record ? slot.record['link'] : nil
            return nil unless link
            self.na_first_existing(self.na_candidates(model, link, self.na_backup_link(backup, slot)))
        rescue StandardError
            nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Restore From Backup + Remove (explicit user actions only)
    # -------------------------------------------------------------------------

        # Writes this computer's copy of every point cloud record back into the
        # model as ONE undoable operation.
        def self.Na__Link__RestoreBackup(session)
            model = session.model
            backup = Na__LocalBackup.Na__Backup__Find(model, session)
            return 'There is no backup on this computer for this model.' unless backup && !(backup['records'] || {}).empty?
            Na__ModelLink.na_end_every_tool(session)
            Na__CloudStore.Na__Store__ReplaceAll(model, backup['records'], 'Point Cloud: Restore From Backup')
            Na__ModelRegistry.Na__Registry__ReloadModelState(model)
            nil
        end

        # The escape hatch: removes every point cloud record from the model
        # (one undoable operation). Loaded clouds stay in memory, unsaved; this
        # computer's backup is kept.
        def self.Na__Link__RemoveFromModel(session)
            model = session.model
            return 'There is no model.' unless model
            self.na_end_every_tool(session)
            problem = Na__CloudStore.Na__Store__RemoveAll(model, 'Point Cloud: Remove From Model')
            return problem if problem
            Na__ModelRegistry.Na__Registry__ReloadModelState(model)
            nil
        end

        def self.na_end_every_tool(session)
            tool = session.transform_tool
            Sketchup.active_model.select_tool(nil) if tool || Na__CloudSet.Na__Slots__All(session).any?(&:clip_editing)
            session.transform_tool = nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Dialog Payload (the model's backup)
    # -------------------------------------------------------------------------

        # What the dialog says about the model's records and this computer's
        # backup of them. Each cloud's own file status is in the clouds list.
        def self.Na__Link__Payload(session, model)
            return { 'state' => 'none' } unless session && model
            slots  = Na__CloudSet.Na__Slots__All(session)
            backup = Na__LocalBackup.Na__Backup__Find(model, session)
            saved  = slots.count { |slot| %w[saved legacy].include?(slot.record_state) }
            return { 'state' => 'none', 'unreadable' => !session.store_problem.nil?, 'problem' => session.store_problem,
                     'backupsFolder' => Na__LocalBackup.Na__Backup__Folder } unless saved > 0 || backup
            compare = Na__LocalBackup.Na__Backup__Compare(model, backup)
            active = Na__CloudSet.Na__Slots__Active(session)
            {
                'state'         => saved > 0 ? 'linked' : 'backupOnly',
                'cloudCount'    => saved,
                'legacy'        => session.store_legacy ? true : false,
                'unreadable'    => !session.store_problem.nil?,
                'problem'       => session.store_problem,
                'fileName'      => active ? (active.record ? active.record.dig('link', 'fileName').to_s : active.name) : '',
                'backup'        => {
                    'exists'     => !backup.nil?,
                    'newer'      => compare['newer'] || (backup && saved.zero?) ? true : false,
                    'savedText'  => compare['backupSavedText'],
                    'cloudNames' => Na__LocalBackup.Na__Backup__CloudNames(backup)
                },
                'backupsFolder' => Na__LocalBackup.Na__Backup__Folder
            }
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Warn("Point cloud link status could not be built: #{error.message}")
            { 'state' => 'none' }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Records (shared with the Clean export)
    # -------------------------------------------------------------------------

        # The link's description of a loaded cloud.
        def self.Na__Link__CloudPart(model, cloud, placement_key)
            info = cloud.las_info || {}
            part = {
                'fileName'     => File.basename(cloud.source_path.to_s),
                'lastPath'     => cloud.source_path.to_s.tr('\\', '/'),
                'relativePath' => self.na_relative_path(model, cloud.source_path.to_s),
                'sourceUnit'   => cloud.source_unit,
                'pointCount'   => cloud.total_points,
                'fingerprint'  => self.Na__Link__FingerprintFromKey(placement_key)
            }
            part['contentKey'] = info['contentKey'] if info['contentKey']
            part
        end

        # Same file: the content keys agree when both are known, else the
        # fingerprints (links from before v0.8.0).
        def self.na_same_cloud_part?(a, b)
            return false unless a.is_a?(Hash) && b.is_a?(Hash)
            return a['contentKey'] == b['contentKey'] if a['contentKey'] && b['contentKey']
            a['fingerprint'] == b['fingerprint']
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals
    # -------------------------------------------------------------------------

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

        # The link this computer's backup holds for the same cloud (its record,
        # or the v0.9 link), or nil.
        def self.na_backup_link(backup, slot)
            records = backup ? backup['records'] || {} : {}
            record = records[Na__CloudStore.Na__Store__DictName(slot.id)]
            return record['link'] if record.is_a?(Hash) && record['link'].is_a?(Hash)
            legacy = records[NA_DICT]
            legacy.is_a?(Hash) && legacy['cloud'].is_a?(Hash) ? legacy['cloud'] : nil
        end

        def self.na_candidates(model, link, backup_link)
            folder = model.path.to_s.empty? ? nil : File.dirname(model.path)
            list = [link['lastPath']]
            list << File.expand_path(link['relativePath'], folder) if folder && link['relativePath'].is_a?(String)
            list << File.join(folder, link['fileName']) if folder
            list << backup_link['lastPath'] if backup_link
            last_folder = Na__UserConfigStore.Na__UserConfig__Get('import', 'lastFolder', '')
            list << File.join(last_folder, link['fileName']) if last_folder.is_a?(String) && !last_folder.empty?
            list.compact.map { |path| path.to_s.tr('\\', '/') }.reject(&:empty?).uniq { |path| path.downcase }
        end

        def self.na_first_existing(paths)
            paths.find { |path| File.file?(path) }
        end

        # [[path, header_ms], mismatched_paths]. Reads LAS headers, and for a
        # link that records a content key, about 2 MB of each file whose header
        # matches (the same count and position is not enough).
        def self.na_find_matching_file(paths, cloud_part)
            fingerprint = cloud_part['fingerprint']
            key = cloud_part['contentKey']
            mismatched = []
            paths.each do |path|
                next unless File.file?(path) && File.extname(path).casecmp('.las').zero?
                info, header_ms = Na__PerfStats.Na__Perf__Measure { Na__NativeEngine.Na__Native__LasReadHeader(path) }
                if info['isCompressed'].to_i != 1 && self.Na__Link__FingerprintFromHeader(info) == fingerprint &&
                   (key.nil? || Na__NativeEngine.Na__Native__LasContentKey(path) == key)
                    return [[path, header_ms], mismatched]
                end
                mismatched << path
            rescue StandardError => error
                Na__DebugTools.Na__Debug__Warn("Could not read the header of #{path}: #{error.message}")
                mismatched << path
            end
            [nil, mismatched]
        end

        def self.na_position_text(placement)
            return 'No position is saved yet: Reload puts the cloud at its import position.' unless placement
            moved = !Na__Placement.na_identity?(placement)
            lock  = placement['locked'] ? 'locked' : 'unlocked'
            moved ? "Reload puts it back in its saved position (#{lock})." : "Reload puts it at its import position (#{lock})."
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
