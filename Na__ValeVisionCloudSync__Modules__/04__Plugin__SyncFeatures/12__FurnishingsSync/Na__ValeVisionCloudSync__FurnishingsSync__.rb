# =============================================================================
# VALEDESIGNSUITE - VALEVISION CLOUD SYNC - FURNISHINGS SYNC (SKETCHUP SIDE)
# =============================================================================
#
# FILE       : Na__ValeVisionCloudSync__FurnishingsSync__.rb
# NAMESPACE  : Na__ValeVisionCloudSync::Na__FurnishingsSync
# PURPOSE    : The Sync Furnishings tab: hand SketchUp's furnishings proxies to the furnishings
#              sync (Python), then place, move, turn, take out and stamp proxies as its answer
#              says, in one undo step. Also starts placing a new proxy from the furnishings library.
# CREATED    : 25-Nov-2026
#
# DESCRIPTION:
# - Adam's answer 9 (25-Nov-2026): SketchUp both ways now. Plan of record: the app's
#   ValeVision__PLAN__FurnishingsSystem__.md, section 5.6. Sync Entourage's shape (11__EntourageSync)
#   with a turn, and with the REAL library component as the proxy, not a figure built here.
# - A PROXY is a component instance at the model root, on the proxy tag (AppConfig furnishings.proxy_tag,
#   in the GLB builder's skip range, so it never goes into the model's GLBs: ValeVision draws the piece
#   from its own library) or already stamped with a piece's Uid (NA_ITEM_DICT). Its asset is the code
#   in its definition's NA_ASSET_DICT, or the core library code its definition's name starts with, so a
#   library component Adam drags in from his component browser and puts on the proxy tag comes back to
#   ValeVision. The same component on its own element tag (28__ProposedBuilding__Furniture) is model,
#   not a proxy, and is never touched.
# - ITS OWN DICTIONARIES, as every proxy kind has (Sync Entourage's L198 lesson).
# - A PIECE HAS ITS REAL SIZE: a proxy scaled or mirrored is handed over as such, and the sync leaves it
#   out. Its turn is the red axis about Z. A tilt is reported and only the turn is kept.
# - THE BASE (what both sides held after the last sync) is kept in the model's ValeVision__CloudExport
#   dictionary as a JSON string, written in the same operation as the proxies: an Undo puts both back
#   together. It does not take back what the sync wrote to the project; the next sync sorts that out.
# - COORDINATES: Ruby reads and writes raw SketchUp poses only (origin in inches, the turn about Z in
#   degrees); every conversion to the app's saved values is in the Python, in one place. Proxies live in
#   model.entities, whose transformations are world whatever is open, and the sync refuses to run with a
#   group open anyway: a proxy inside one would never be seen.
# - IMG## SCENES: the proxy tag is hidden in them, or the whitecard pictures would show each piece twice.
# - THE SIGN-IN is the Sync Aura tab's: one Vale sign-in for every Vale app.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 25-Nov-2026 - Version 0.0.1 (Cloud Sync 0.7.2)
# - Initial build: Sync Furnishings, placing from the furnishings library, the proxy tag on new
#   instances, hidden in the IMG## scenes.
#
# =============================================================================

require 'json'
require 'tmpdir'

module Na__ValeVisionCloudSync
    module Na__FurnishingsSync

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

        SCOPE_SYNC          = 'furn_sync'.freeze                                   # <-- [matches UI button]
        SCOPES              = [SCOPE_SYNC].freeze

        NA_ASSET_DICT       = 'Na__ValeVisionCloudSync__FurnishingsAsset'.freeze   # <-- On a proxy's definition: its asset
        NA_ITEM_DICT        = 'Na__ValeVisionCloudSync__FurnishingsItem'.freeze    # <-- On a synced proxy instance: its piece
        NA_ASSET_ID         = /\A\d{2}_\d{3}[1-9]\z/                               # <-- The core library code, as the furnishings library's register
        NA_CODE_LEADING     = /\A(\d{2}_\d{3}[1-9])__/                             # <-- A library component's name starts with its code
        NA_UID              = /\AF\d{4,}\z/                                        # <-- F0007
        NA_BASE_KEY         = 'furnishings_base'.freeze                            # <-- Model dictionary keys (ValeVision__CloudExport)
        NA_BASE_PROJECT_KEY = 'furnishings_base_project'.freeze
        NA_LAST_SYNC_KEY    = 'furnishings_last_sync'.freeze
        NA_SCALE_TOLERANCE  = 0.001
        NA_LIBRARY_INDEX    = 'FurnishingsLibrary__Index__.json'.freeze
        NA_LIBRARY_REGISTER = 'FurnishingsLibrary__Register__.json'.freeze

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Public API - Sync
# -----------------------------------------------------------------------------

        # FUNCTION | Run One Sync Furnishings Action
        # ------------------------------------------------------------
        # Returns the report hash the dialog renders (same shape as the orchestrator's).
        # ---------------------------------------------------------------
        def self.Na__FurnSync__Run(scope_id, dialog_manager)
            model  = Sketchup.active_model
            report = { scope: scope_id, project_name: '', started_at: Time.now.strftime('%d-%b-%Y at %H:%M'),
                       steps: [], success: false, message: '' }

            problem = self.na_preflight(model)
            unless problem.empty?
                report[:steps] << { label: 'Check Model', success: false, message: problem }
                return report.merge(message: problem)
            end

            paths   = Na__ProjectPathMapper.Na__ValeVisionCloudSync__GetProjectPaths(model)
            library = Na__ProjectPathMapper.Na__ValeVisionCloudSync__ResolveLibraryProject(model)
            problem = if !library[:error].to_s.empty? then library[:error]
                      elsif !library[:exists]         then "#{library[:library_id]} is not in the Project Library yet: run Sync Project To ValeVision 3D once."
                      else ''
                      end
            unless problem.empty?
                report[:steps] << { label: 'Resolve Library Project', success: false, message: problem }
                return report.merge(message: problem)
            end
            report[:library_id]   = library[:library_id]
            report[:project_name] = Na__SyncOrchestrator.na_derive_project_name(model)

            dialog_manager.na_push_status('running', 'Syncing the furnishings with ValeVision 3D...')
            report[:steps] << self.Na__FurnSync__SyncModel(model, paths[:project_root].to_s, library[:library_id].to_s, report)
            report[:steps].compact!
            Na__SyncOrchestrator.na_finalise_report(report)
        end

        # FUNCTION | The Sync Itself: Hand Over, Run the Python, Apply Its Answer
        # ------------------------------------------------------------
        # Also what a test harness calls, with its own Python arguments (a testing server's
        # site and a test session), so the round trip is proved on a sandbox before a real one.
        # Returns the Apply step, or nil when the Python said no; the Python's own steps go
        # into report.
        # ---------------------------------------------------------------
        def self.Na__FurnSync__SyncModel(model, project_root, library_id, report, overrides = {})
            proxies  = self.na_collect_proxies(model)
            handover = self.na_write_handover(model, proxies)
            result, raw = self.na_run_python([
                '--project-root',  project_root,
                '--library-id',    library_id,
                '--sketchup-file', handover
            ], overrides)
            Na__SyncOrchestrator.na_append_python_steps(report, result)
            answer = raw.is_a?(Hash) ? raw['furnishings'] : nil
            return nil unless result[:success] && answer.is_a?(Hash)
            self.na_apply(model, proxies, answer)
        end

        # HELPER FUNCTION | What Stops a Sync Before Anything Runs ('' when nothing)
        # ---------------------------------------------------------------
        def self.na_preflight(model)
            return 'Open a model first.' unless model
            return 'Save the model in its project folder first.' if model.path.to_s.empty?
            return 'Close every group and component first: the furnishings proxies work at the model root.' unless model.active_path.nil?
            ''
        end

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Public API - Placing a Proxy, Status
# -----------------------------------------------------------------------------

        # FUNCTION | Start Placing a New Proxy With SketchUp's Own Component Tool
        # ------------------------------------------------------------
        # The real library component, loaded from the core library. It becomes a piece at the
        # next sync. Its tag is set as it lands (the observer below), so a GLB export before
        # then still leaves it out.
        # ---------------------------------------------------------------
        def self.Na__FurnSync__Place(asset_id)
            model = Sketchup.active_model
            return { success: false, message: 'Open a model first.' } unless model
            return { success: false, message: 'Close every group and component first: a proxy lives at the model root.' } unless model.active_path.nil?

            spec = self.na_library_spec(asset_id.to_s)
            return { success: false, message: "#{asset_id} is not in the furnishings library on this PC." } unless spec

            definition = nil
            model.start_operation('ValeVision Cloud Sync: Furnishings Proxy', true)
            begin
                definition = self.na_definition(model, asset_id.to_s, spec)
                self.na_hide_in_image_scenes(model, self.na_proxy_layer(model))                       # <-- It is in the pictures' way before its first sync too
                model.commit_operation
            rescue => error
                model.abort_operation
                return { success: false, message: "The component could not be loaded (#{error.class}: #{error.message})." }
            end
            @na_placing = definition
            model.place_component(definition, false)
            { success: true, message: "Click in the model to place #{spec['Name']}. It becomes a piece in ValeVision 3D at the next Sync." }
        rescue => error
            { success: false, message: "#{error.class}: #{error.message}" }
        end

        # FUNCTION | The Sync Furnishings Tab's Status Rows (no network)
        # ------------------------------------------------------------
        def self.Na__FurnSync__Status(model = Sketchup.active_model)
            session = defined?(Na__AuraSync) ? Na__AuraSync.na_read_session : nil
            user    = session ? (session['User'] || {}) : {}
            proxies = model ? self.na_collect_proxies(model) : []
            dict    = model ? model.attribute_dictionary(Na__ConfigLoader.Na__ValeVisionCloudSync__ModelDictionaryName, false) : nil
            {
                signed_in:    !session.nil?,
                user_name:    (user['name'] || user['displayName'] || (session && session['Email'])).to_s,
                user_level:   (user['level'] || user['permissionLevel']).to_s,
                proxies:      proxies.length,
                linked:       proxies.count { |p| !p['Uid'].empty? },
                last_sync:    dict ? dict[NA_LAST_SYNC_KEY].to_s : '',
                base_project: dict ? dict[NA_BASE_PROJECT_KEY].to_s : '',
                proxy_tag:    Na__ConfigLoader.Na__ValeVisionCloudSync__FurnishingsPaths[:proxy_tag],
                assets:       self.na_catalogue
            }
        rescue => error
            { signed_in: false, assets: [], error: "#{error.class}: #{error.message}" }
        end

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | The Furnishings Library on This PC
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | The Library's Folder, From the Server Manager's Sync Map
        # ---------------------------------------------------------------
        def self.na_library_folder
            sync_map = Na__ConfigLoader.Na__ValeVisionCloudSync__LibraryPaths[:sync_map]
            mirror   = JSON.parse(File.read(sync_map, encoding: 'UTF-8')).fetch('Local').fetch('MirrorRoot').to_s.tr('\\', '/')
            File.join(mirror, Na__ConfigLoader.Na__ValeVisionCloudSync__FurnishingsPaths[:asset_library])
        end

        # HELPER FUNCTION | The Library's Generated Index Rows, or None
        # ---------------------------------------------------------------
        def self.na_index_rows
            doc = JSON.parse(File.read(File.join(self.na_library_folder, NA_LIBRARY_INDEX), encoding: 'UTF-8'))
            Array(doc['FurnishingsLibrary__Index__Assets'])
        rescue JSON::ParserError, SystemCallError, KeyError
            []
        end

        # FUNCTION | The Tab's List of Pieces to Place, With Their Categories' Labels
        # ------------------------------------------------------------
        def self.na_catalogue
            doc    = JSON.parse(File.read(File.join(self.na_library_folder, NA_LIBRARY_INDEX), encoding: 'UTF-8'))
            labels = Array(doc['FurnishingsLibrary__Index__Categories']).each_with_object({}) { |c, map| map[c['Category__Key']] = c['Category__Label'] }
            Array(doc['FurnishingsLibrary__Index__Assets']).select { |row| row['Asset__Status'] == 'Active' && row['Asset__Id'].to_s.match?(NA_ASSET_ID) }.map do |row|
                { id: row['Asset__Id'].to_s, name: row['Asset__Name'].to_s, category: (labels[row['Asset__Category']] || row['Asset__Category']).to_s,
                  width_mm: row['Asset__WidthMm'].to_i, depth_mm: row['Asset__DepthMm'].to_i, height_mm: row['Asset__HeightMm'].to_i }
            end
        rescue JSON::ParserError, SystemCallError, KeyError
            []
        end

        # HELPER FUNCTION | Where an Asset's Real Component Is, From Its Record and the Register, or nil
        # ---------------------------------------------------------------
        def self.na_library_spec(asset_id)
            row = self.na_index_rows.find { |candidate| candidate['Asset__Id'] == asset_id }
            return nil unless row && row['Asset__DataFile'].to_s != ''
            folder   = self.na_library_folder
            data     = JSON.parse(File.read(File.join(folder, row['Asset__DataFile'].to_s), encoding: 'UTF-8'))
            register = JSON.parse(File.read(File.join(folder, NA_LIBRARY_REGISTER), encoding: 'UTF-8'))
            root     = register.fetch('FurnishingsLibrary__Register__Source').fetch('Source__Root').to_s
            { 'Name' => data['Asset__Name'].to_s, 'SkpPath' => File.join(root, data.fetch('Asset__Source').fetch('Source__SketchUpFile').to_s) }
        rescue JSON::ParserError, SystemCallError, KeyError
            nil
        end

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Reading the Proxies (raw SketchUp poses)
# -----------------------------------------------------------------------------

        # FUNCTION | Every Furnishings Proxy at the Model Root
        # ------------------------------------------------------------
        # model.entities is the root whatever is open, and a root instance's transformation is
        # world. Key: the instance's persistent id. The turn is the red axis about Z; the scale
        # is the axes' lengths, which a piece of real size keeps at 1.
        # ---------------------------------------------------------------
        def self.na_collect_proxies(model)
            layer = self.na_proxy_layer(model, false)
            model.entities.grep(Sketchup::ComponentInstance).filter_map do |instance|
                uid = instance.get_attribute(NA_ITEM_DICT, 'Uid').to_s
                next unless (layer && instance.layer == layer) || uid.match?(NA_UID)
                asset_id = self.na_asset_of(instance.definition)
                next unless asset_id

                m     = instance.transformation.to_a                                                  # <-- Column-major: x axis, y axis, z axis, origin, divisor
                w     = m[15].to_f.zero? ? 1.0 : m[15].to_f
                x_len = Math.sqrt(m[0]**2 + m[1]**2 + m[2]**2)
                y_len = Math.sqrt(m[4]**2 + m[5]**2 + m[6]**2)
                z_len = Math.sqrt(m[8]**2 + m[9]**2 + m[10]**2)
                det   = m[0] * (m[5] * m[10] - m[6] * m[9]) - m[4] * (m[1] * m[10] - m[2] * m[9]) + m[8] * (m[1] * m[6] - m[2] * m[5])
                {
                    'Key'      => "pid:#{instance.persistent_id}",
                    'Uid'      => uid.match?(NA_UID) ? uid : '',
                    'AssetId'  => asset_id,
                    'OriginIn' => [m[12].to_f / w, m[13].to_f / w, m[14].to_f / w],                   # <-- Inches
                    'RotZDeg'  => Math.atan2(m[1], m[0]) * 180.0 / Math::PI,
                    'Scaled'   => [x_len, y_len, z_len].any? { |length| (length / w - 1.0).abs > NA_SCALE_TOLERANCE },
                    'Mirrored' => det < 0,
                    'Tilted'   => z_len > 0 && (m[10] / z_len) < 0.9999,
                    '_instance' => instance
                }
            end
        end

        # HELPER FUNCTION | A Definition's Asset: Its Stamp, or the Code Its Name Starts With, or nil
        # ---------------------------------------------------------------
        def self.na_asset_of(definition)
            stamped = definition.get_attribute(NA_ASSET_DICT, 'AssetId').to_s
            return stamped if stamped.match?(NA_ASSET_ID)
            definition.name.to_s[NA_CODE_LEADING, 1]
        end

        # HELPER FUNCTION | How Many Proxies Sit Inside a Group or Component, Where a Sync Cannot See Them
        # ---------------------------------------------------------------
        def self.na_count_nested(model)
            model.definitions.sum do |definition|
                next 0 if definition.image?
                definition.instances.count { |instance| instance.parent.is_a?(Sketchup::ComponentDefinition) && instance.get_attribute(NA_ITEM_DICT, 'Uid').to_s.match?(NA_UID) }
            end
        end

        # FUNCTION | Write the Hand-Over File (proxies and the last synced base)
        # ------------------------------------------------------------
        def self.na_write_handover(model, proxies)
            dict = model.attribute_dictionary(Na__ConfigLoader.Na__ValeVisionCloudSync__ModelDictionaryName, false)
            base = begin
                dict && !dict[NA_BASE_KEY].to_s.empty? ? JSON.parse(dict[NA_BASE_KEY].to_s) : []
            rescue JSON::ParserError
                []
            end
            doc = {
                'ModelName'     => File.basename(model.path.to_s, '.skp'),
                'BaseProjectId' => dict ? dict[NA_BASE_PROJECT_KEY].to_s : '',
                'Base'          => base.is_a?(Array) ? base : [],
                'Nested'        => self.na_count_nested(model),
                'Proxies'       => proxies.map { |p| p.reject { |key, _| key == '_instance' } }
            }
            dir  = Na__SyncOrchestrator.na_python_log_dir || Dir.tmpdir
            path = File.join(dir, "Na__ValeVisionCloudSync__FurnishingsHandover__#{Time.now.strftime('%Y%m%d_%H%M%S_%L')}.json").tr('\\', '/')
            File.write(path, JSON.pretty_generate(doc))
            path
        end

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Applying the Sync's Answer (one operation, the base inside it)
# -----------------------------------------------------------------------------

        # FUNCTION | Place, Move, Turn, Take Out and Stamp Proxies, Then Keep the New Base
        # ------------------------------------------------------------
        # A failed create or move drops that Uid from the base, so the next sync sees
        # "ValeVision has it, SketchUp does not match" and tries again, instead of reading
        # the gap as a deletion made in SketchUp.
        # ---------------------------------------------------------------
        def self.na_apply(model, proxies, answer)
            ops     = Array(answer['Apply'])
            specs   = answer['Definitions'].is_a?(Hash) ? answer['Definitions'] : {}
            by_key  = proxies.each_with_object({}) { |p, map| map[p['Key']] = p['_instance'] }
            failed  = []
            counts  = Hash.new(0)
            project = answer['BaseProjectId'].to_s
            scenes  = nil

            @na_applying = true
            model.start_operation('ValeVision Cloud Sync: Furnishings', true)
            begin
                layer   = self.na_proxy_layer(model)
                erasing = []
                ops.each do |op|
                    begin
                        instance = by_key[op['Key']]
                        case op['Op']
                        when 'update'
                            raise 'its proxy has gone' unless instance && instance.valid?
                            self.na_unlocked(instance) { instance.transformation = self.na_pose(op) }
                            self.na_stamp(instance, op, project, layer)
                        when 'stamp'
                            raise 'its proxy has gone' unless instance && instance.valid?
                            self.na_stamp(instance, op, project, layer)
                        when 'unstamp'
                            if instance && instance.valid?
                                self.na_unlocked(instance) { instance.delete_attribute(NA_ITEM_DICT) }
                            end
                        when 'delete'
                            if instance && instance.valid?
                                instance.locked = false
                                erasing << instance
                            end
                        when 'create'
                            definition = self.na_definition(model, op['AssetId'].to_s, specs[op['AssetId'].to_s])
                            created = model.entities.add_instance(definition, self.na_pose(op))
                            self.na_stamp(created, op, project, layer)
                        else
                            next
                        end
                        counts[op['Op']] += 1
                    rescue => error
                        failed << { 'Uid' => op['Uid'].to_s, 'Op' => op['Op'].to_s, 'Why' => "#{op['AssetId'] || op['Uid']}: #{error.message}" }
                    end
                end
                model.entities.erase_entities(erasing.uniq) unless erasing.empty?
                self.na_collect_proxies(model).each do |proxy|                                       # <-- A stamped proxy moved off the tag goes back on it
                    instance = proxy['_instance']
                    next if instance.layer == layer
                    self.na_unlocked(instance) { instance.layer = layer }
                end
                scenes = self.na_hide_in_image_scenes(model, layer)

                retry_uids = failed.select { |f| %w[create update].include?(f['Op']) }.map { |f| f['Uid'] }
                base = Array(answer['Base']).reject { |entry| retry_uids.include?(entry['Uid'].to_s) }
                dict = model.attribute_dictionary(Na__ConfigLoader.Na__ValeVisionCloudSync__ModelDictionaryName, true)
                dict[NA_BASE_KEY]         = base.to_json                                              # <-- A JSON string: a Hash does not survive as an attribute
                dict[NA_BASE_PROJECT_KEY] = project
                dict[NA_LAST_SYNC_KEY]    = Time.now.strftime('%d-%b-%Y at %H:%M')
                model.commit_operation
            rescue => error
                model.abort_operation
                return { label: 'Apply Furnishings In SketchUp', success: false,
                         message: "Nothing was changed in SketchUp (#{error.class}: #{error.message}). ValeVision already holds this sync's changes; Sync again." }
            ensure
                @na_applying = false
            end

            parts = []
            parts << "#{counts['create']} placed"     if counts['create'] > 0
            parts << "#{counts['update']} moved"      if counts['update'] > 0
            parts << "#{counts['delete']} taken out"  if counts['delete'] > 0
            parts << "#{counts['stamp']} newly linked to ValeVision" if counts['stamp'] > 0
            message = parts.empty? ? 'SketchUp already matched ValeVision.' : "#{parts.join(', ')} (one undo step)."
            message += " Tag hidden in #{scenes[:hidden]} IMG scene(s)." if scenes[:hidden] > 0
            message += " #{scenes[:unsaved]} IMG scene(s) do not save tags, so the proxies may show in their pictures." if scenes[:unsaved] > 0
            message += " Not done, retried next sync: #{failed.map { |f| f['Why'] }.first(6).join('; ')}." unless failed.empty?
            { label: 'Apply Furnishings In SketchUp', success: failed.empty?, message: message }
        end

        # HELPER FUNCTION | A Raw SketchUp Pose as a Transformation: the Origin, Then the Turn About Z
        # ---------------------------------------------------------------
        def self.na_pose(op)
            origin = Array(op['OriginIn']).map(&:to_f)
            raise 'it has no position' unless origin.length == 3
            turn = op['RotZDeg'].to_f * Math::PI / 180.0
            Geom::Transformation.new(Geom::Point3d.new(*origin)) * Geom::Transformation.rotation(ORIGIN, Z_AXIS, turn)
        end

        # HELPER FUNCTION | Do Something to an Instance Someone May Have Locked, Then Leave It as It Was
        # ---------------------------------------------------------------
        def self.na_unlocked(instance)
            locked = instance.locked?
            instance.locked = false if locked
            yield
            instance.locked = true if locked
        end

        # HELPER FUNCTION | Mark an Instance as One Piece (its Uid, the project, the tag), and Its Definition's Asset
        # ---------------------------------------------------------------
        def self.na_stamp(instance, op, project, layer)
            uid = op['Uid'].to_s
            raise "#{uid.inspect} is not a piece's Uid" unless uid.match?(NA_UID)
            asset_id = op['AssetId'].to_s
            if asset_id.match?(NA_ASSET_ID) && instance.definition.get_attribute(NA_ASSET_DICT, 'AssetId').to_s != asset_id
                instance.definition.set_attribute(NA_ASSET_DICT, 'AssetId', asset_id)
                self.na_watch(instance.definition)
            end
            self.na_unlocked(instance) do
                instance.set_attribute(NA_ITEM_DICT, 'Uid', uid)
                instance.set_attribute(NA_ITEM_DICT, 'ProjectId', project)
                instance.layer = layer if layer && instance.layer != layer
                instance.name  = "#{op['Name']} #{uid}" unless op['Name'].to_s.empty?                 # <-- The Outliner names it as the app does
            end
        end

        # HELPER FUNCTION | The Proxy Tag (made if it is not there and make is true), or nil If None Is Set
        # ---------------------------------------------------------------
        def self.na_proxy_layer(model, make = true)
            tag = Na__ConfigLoader.Na__ValeVisionCloudSync__FurnishingsPaths[:proxy_tag].to_s
            return nil if tag.empty?
            model.layers[tag] || (make ? model.layers.add(tag) : nil)
        end

        # HELPER FUNCTION | Hide the Proxy Tag in the IMG## Scenes, So the Pictures Never Show a Piece Twice
        # ---------------------------------------------------------------
        # Returns { hidden: scenes changed, unsaved: scenes that do not save tags }.
        # ---------------------------------------------------------------
        def self.na_hide_in_image_scenes(model, layer)
            out = { hidden: 0, unsaved: 0 }
            return out unless layer
            prefix = Na__ConfigLoader.Na__ValeVisionCloudSync__ScenePrefixRegex
            model.pages.each do |page|
                next unless page.name.to_s.match?(prefix)
                unless page.use_hidden_layers?
                    out[:unsaved] += 1
                    next
                end
                next if page.layers.include?(layer)
                page.set_visibility(layer, false)
                out[:hidden] += 1
            end
            out
        end

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | The Proxy's Definition (the real library component)
# -----------------------------------------------------------------------------

        # FUNCTION | The Definition for an Asset: One Stamped With It, One Named for It, or the Library's Own .skp
        # ------------------------------------------------------------
        # spec: { 'Name', 'SkpPath' }. A component already in the model (on its own element
        # tag, say) is the same definition: stamping it changes nothing about those instances.
        # ---------------------------------------------------------------
        def self.na_definition(model, asset_id, spec)
            raise "#{asset_id.inspect} is not a furnishings asset" unless asset_id.match?(NA_ASSET_ID)
            found = model.definitions.find { |definition| !definition.image? && definition.get_attribute(NA_ASSET_DICT, 'AssetId') == asset_id }
            found ||= model.definitions.find { |definition| !definition.image? && definition.name.to_s[NA_CODE_LEADING, 1] == asset_id }
            unless found
                path = spec.is_a?(Hash) ? spec['SkpPath'].to_s : ''
                raise 'the sync did not say where its component is' if path.empty?
                raise "its component is not at #{path}" unless File.exist?(path)
                found = model.definitions.load(path)
            end
            found.set_attribute(NA_ASSET_DICT, 'AssetId', asset_id)
            found.set_attribute(NA_ASSET_DICT, 'Name', spec['Name'].to_s) if spec.is_a?(Hash) && !spec['Name'].to_s.empty?
            self.na_watch(found)
            found
        end

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | A New Instance Goes on the Proxy Tag as It Lands
# -----------------------------------------------------------------------------

        # CLASS | Tells the Module When a Proxy Definition Gains an Instance
        # ------------------------------------------------------------
        class Na__ProxyLandedObserver < Sketchup::DefinitionObserver
            def onComponentInstanceAdded(definition, instance)
                Na__FurnishingsSync.na_proxy_landed(definition, instance)
            end
        end

        # HELPER FUNCTION | Watch a Proxy's Definition (the same observer once, whatever the count)
        # ---------------------------------------------------------------
        def self.na_watch(definition)
            @na_observer ||= Na__ProxyLandedObserver.new
            @na_watched  ||= {}
            return if @na_watched[definition.object_id]
            definition.add_observer(@na_observer)
            @na_watched[definition.object_id] = true
        end

        # FUNCTION | Put a Proxy Placed From the Tab on the Tag
        # ------------------------------------------------------------
        # Only an instance this tab started placing: the same component placed from the
        # component browser is model, on whatever tag the person gives it. Not while a sync
        # applies its answer, which does this itself. On the next tick, once SketchUp's own
        # tool has finished, as a transparent operation: one Undo takes out both.
        # ---------------------------------------------------------------
        def self.na_proxy_landed(definition, instance)
            return if @na_applying
            return unless @na_placing && @na_placing == definition
            UI.start_timer(0, false) do
                begin
                    next unless instance.valid?
                    model = instance.model
                    layer = self.na_proxy_layer(model)
                    next if layer.nil? || instance.layer == layer || !instance.parent.is_a?(Sketchup::Model)
                    model.start_operation('ValeVision Cloud Sync: Proxy Tag', true, false, true)
                    instance.layer = layer
                    model.commit_operation
                rescue => error
                    puts "[Na__ValeVisionCloudSync] Furnishings proxy tag: #{error.class}: #{error.message}"
                end
            end
        end

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Running the Furnishings Sync (Python)
# -----------------------------------------------------------------------------

        # FUNCTION | Launch the Furnishings Sync and Read Its Report
        # ------------------------------------------------------------
        # Returns [normalised result, the raw report hash]. Reuses the orchestrator's
        # interpreter search, sanitised environment and run log, and the Sync Aura tab's kept
        # session. overrides: { site:, session_file: } for a sandbox run only.
        # ---------------------------------------------------------------
        def self.na_run_python(extra_args, overrides = {})
            paths     = Na__ConfigLoader.Na__ValeVisionCloudSync__FurnishingsPaths
            session   = (overrides[:session_file] || Na__ConfigLoader.Na__ValeVisionCloudSync__AuraPaths[:session_file]).to_s
            lib_paths = Na__ConfigLoader.Na__ValeVisionCloudSync__LibraryPaths
            site      = (overrides[:site] || lib_paths[:site]).to_s
            unless File.exist?(paths[:script])
                return [{ success: false, message: "Furnishings sync script not found at #{paths[:script]}." }, nil]
            end

            resolution  = Na__SyncOrchestrator.na_resolve_python_executable(Na__ConfigLoader.Na__ValeVisionCloudSync__PythonConfig)
            report_file = Na__SyncOrchestrator.na_build_report_file_path
            args = ['--action', 'sync', '--site', site, '--session-file', session,
                    '--sync-map', lib_paths[:sync_map], '--json', '--report-file', report_file] + extra_args
            result = Na__SyncOrchestrator.na_execute_python(resolution[:command], paths[:script], args, report_file)
            result[:interpreter_note] = resolution[:note]
            result[:interpreter_ok]   = resolution[:trusted]
            raw = begin
                File.exist?(report_file) ? JSON.parse(File.read(report_file, encoding: 'UTF-8')) : nil
            rescue JSON::ParserError
                nil
            end
            [result, raw]
        end

# endregion -------------------------------------------------------------------

    end # module Na__FurnishingsSync
end # module Na__ValeVisionCloudSync

# =============================================================================
# END OF FILE
# =============================================================================
