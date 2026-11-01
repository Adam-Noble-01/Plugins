# =============================================================================
# NA PAINTERLYNPR ASSETS - PROJECT CACHE - SYNC
# =============================================================================
#
# FILE       : Na__PainterlyAssets__ProjectCache__Sync__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__CacheSync
# PURPOSE    : Bring a model's local NPR cache up to date with the model: the
#              builder's units fingerprinted, only the stale ones exported,
#              each file's version moved only when its bytes changed, gone units'
#              files removed, the scene rebuilt when its files changed, and the
#              placed library assets read. Answers what changed, so the NPR
#              Viewport fetches only those files.
# CREATED    : 01-Nov-2026
#
# DESCRIPTION:
# - ONE PASS, NO OPERATION: it reads the model and writes only files in its
#   cache folder. The GLB builder's export runs inside it, as Cloud Sync's
#   does, so it runs on SketchUp's main thread: the live sync calls it after
#   the model has been still for a moment, never mid-gesture.
# - MODES: :incremental keeps every definition's digest except the ones the
#   caller says a change touched; :full forgets them all (Refresh, live turned
#   back on, undo and redo), the "cycle through" Adam asked for.
# - A UNIT TAKES ITS NEW FINGERPRINT ONLY WHEN EVERY ONE OF ITS FILES WAS
#   WRITTEN, so a failed export is tried again next time. A file rewritten
#   byte for byte keeps its version: the viewport never fetches it again.
# - Nothing is exported with a group open (see Na__GlbBridge); the answer says
#   'waiting' and the live sync tries again when the group closes.
#
# =============================================================================

module Na__PainterlyAssets
    module Na__CacheSync

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        # FUNCTION | Bring the Model's Cache Up to Date
        # ------------------------------------------------------------
        # @param mode [Symbol] :incremental or :full
        # @param forget [Array<Sketchup::ComponentDefinition>] definitions a change touched
        # @return [Hash] { 'ok', 'state' ('synced' | 'waiting' | 'error'), 'key', 'folder', 'changed', 'removed',
        #                  'exported', 'units', 'scene', 'proxies', 'message', 'seconds' }
        def self.Na__Sync__Run(model, mode: :incremental, forget: [])
            started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            return self.na_answer('waiting', 'Changes reach the NPR view when the open group or component is closed.', started) if model.active_path

            folder = Na__CacheStore.Na__Cache__Folder(model)
            key    = Na__CacheStore.Na__Cache__Key(model)
            if mode == :full
                Na__Fingerprint.Na__Fp__ForgetAll(model)
            else
                Na__Fingerprint.Na__Fp__Forget(model, forget)
            end

            plan     = Na__GlbBridge.Na__GlbBridge__Plan(model)
            rules    = Na__SceneFile.na_rules
            units    = plan['Units'].reject { |unit| self.na_ignored?(unit, rules) }
            manifest = Na__CacheStore.Na__Cache__ReadManifest(folder)

            fingerprints = {}
            stale = units.select do |unit|
                fingerprints[unit['Key']] = Na__Fingerprint.Na__Fp__Unit(model, unit)
                record = manifest['Units'][unit['Key']]
                record.nil? || record['Fingerprint'] != fingerprints[unit['Key']] || record['Files'] != unit['Files'] ||
                    unit['Files'].any? { |name| !File.file?(File.join(folder, name)) }
            end

            too_long = Na__CacheStore.Na__Cache__TooLong(folder, stale.flat_map { |unit| unit['Files'] })
            wanted   = stale.flat_map { |unit| unit['Files'] } - too_long
            export   = wanted.empty? ? nil : Na__GlbBridge.Na__GlbBridge__Export(model, folder, wanted)
            written  = export ? export['written'] : []

            changed = []
            stale.each do |unit|
                next unless unit['Files'].all? { |name| written.include?(name) }       # <-- Only a whole unit takes its fingerprint: a failed one is tried again
                unit['Files'].each { |name| changed << name if self.na_record_file(manifest, folder, unit, name) }
                manifest['Units'][unit['Key']] = { 'Kind' => unit['Kind'], 'Files' => unit['Files'], 'Fingerprint' => fingerprints[unit['Key']], 'Entities' => unit['Entities'].length }
            end

            removed = self.na_remove_gone(manifest, folder, units)
            scene   = Na__CacheStore.Na__Cache__ReadScene(folder)
            if scene.nil? || changed.any? || removed.any?
                scene = Na__SceneFile.Na__Scene__Build(folder, manifest['Files'].keys, scene)
                Na__CacheStore.Na__Cache__WriteScene(folder, scene)
            end
            manifest['Revision']   = manifest['Revision'].to_i + 1 if changed.any? || removed.any?
            manifest['ProjectKey'] = key
            manifest['ModelPath']  = model.path.to_s
            manifest['ModelTitle'] = model.title.to_s
            manifest['Prefix']     = plan['Prefix']
            manifest['SyncedIso']  = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
            Na__CacheStore.Na__Cache__WriteManifest(folder, manifest)

            proxies = Na__ConfigLoader.Na__Config__GetOr(true, 'nprViewport', 'assets', 'includeProxies') == false ? [] :
                      Na__AssetProxies.Na__Proxies__Collect(model, scene['NprScene__ModelPlacement'] || {})
            message = self.na_message(units, stale, changed, removed, export, too_long, mode)
            ok      = export.nil? || export['ok']
            self.na_answer(ok && too_long.empty? ? 'synced' : 'error', message, started).merge(
                'ok'       => ok && too_long.empty?,
                'key'      => key,
                'folder'   => folder,
                'changed'  => changed,
                'removed'  => removed,
                'exported' => written,
                'units'    => units.length,
                'manifest' => manifest,
                'scene'    => scene,
                'proxies'  => proxies,
                'tooLong'  => too_long
            )
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('The NPR cache sync failed.', error)
            self.na_answer('error', "The NPR cache could not be brought up to date: #{error.message}", started)
        end
        # ---------------------------------------------------------------

        # FUNCTION | What the Viewport Needs to Draw the Cache: the files, their versions, the scene, the assets
        # ------------------------------------------------------------
        def self.Na__Sync__Payload(result)
            manifest = result['manifest'] || {}
            files    = (manifest['Files'] || {}).map { |name, record| { 'Name' => name, 'Version' => record['Version'].to_i, 'Bytes' => record['Bytes'].to_i } }
            scene    = result['scene'] || {}
            {
                'Key'           => result['key'],
                'Base'          => "/cache/#{result['key']}/",
                'SceneFile'     => Na__CacheStore::NA_SCENE_FILE,
                'SceneRevision' => scene.dig('NprScene__Meta', 'Revision').to_i,
                'Placement'     => scene['NprScene__ModelPlacement'] || {},
                'Files'         => files.sort_by { |f| f['Name'] },
                'Changed'       => result['changed'] || [],
                'Removed'       => result['removed'] || [],
                'Proxies'       => result['proxies'] || [],
                'Message'       => result['message'],
                'Seconds'       => result['seconds']
            }
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals
    # -------------------------------------------------------------------------

        def self.na_ignored?(unit, rules)
            part = Na__SceneFile.Na__Scene__ParseFile(unit['Files'].first)
            part && Na__SceneFile.Na__Scene__FileRule(part, rules['Rules'])['Use'] == 'Ignore'
        end

        # A written file's record; true when its bytes changed (its version moves)
        def self.na_record_file(manifest, folder, unit, name)
            path   = File.join(folder, name)
            sha    = Na__CacheStore.Na__Cache__Sha256(path)
            record = manifest['Files'][name] || {}
            return false if record['Sha256'] == sha && record['Unit'] == unit['Key']
            manifest['Files'][name] = {
                'Unit'       => unit['Key'],
                'Sha256'     => sha,
                'Bytes'      => File.size(path),
                'Version'    => record['Version'].to_i + 1,
                'WrittenIso' => Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
            }
            true
        end

        # Units the model no longer has, and files no unit names now: deleted
        def self.na_remove_gone(manifest, folder, units)
            live    = units.map { |unit| unit['Key'] }
            names   = units.flat_map { |unit| unit['Files'] }
            removed = []
            (manifest['Units'].keys - live).each { |key| manifest['Units'].delete(key) }
            (manifest['Files'].keys - names).each do |name|
                path = File.join(folder, name)
                File.delete(path) if File.file?(path)
                manifest['Files'].delete(name)
                removed << name
            end
            removed
        end

        def self.na_message(units, stale, changed, removed, export, too_long, mode)
            parts = []
            if stale.empty?
                parts << "Up to date: #{units.length} model #{units.length == 1 ? 'part' : 'parts'}#{mode == :full ? ' checked' : ''}."
            else
                names = stale.map { |unit| unit['Key'].split('__').last }.uniq
                parts << "#{stale.length} of #{units.length} model parts exported (#{names.first(4).join(', ')}#{names.length > 4 ? ', ...' : ''})."
                parts << "#{changed.length} file(s) changed." if changed.any?
            end
            parts << "#{removed.length} file(s) removed." if removed.any?
            parts << export['message'] if export && !export['ok']
            parts << "Too long a path for SketchUp to write: #{too_long.first}" if too_long.any?
            parts.join(' ')
        end

        def self.na_answer(state, message, started)
            {
                'ok'      => state == 'synced',
                'state'   => state,
                'message' => message,
                'seconds' => (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(2)
            }
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
