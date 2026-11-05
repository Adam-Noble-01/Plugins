# =============================================================================
# VALEDESIGNSUITE - VALEVISION CLOUD SYNC - VEGETATION SYNC (SKETCHUP SIDE)
# =============================================================================
#
# FILE       : Na__ValeVisionCloudSync__VegetationSync__.rb
# NAMESPACE  : Na__ValeVisionCloudSync::Na__VegetationSync
# PURPOSE    : The Sync Vegetation tab: hand SketchUp's vegetation proxies to the
#              vegetation sync (Python), then place, move, take out and stamp
#              proxies as its answer says, in one undo step. Also starts placing a
#              new proxy from the vegetation asset library.
# CREATED    : 04-Nov-2026
#
# DESCRIPTION:
# - Adam's answer, 04-Nov-2026, to whether the plants reach SketchUp: "Both ways, like
#   Sync Aura". The plan is ValeVision__PLAN__VegetationSystem__.md, section 5.
# - A PROXY is a component instance at the model root whose definition this plugin built
#   and stamped with an AssetId (NA_ASSET_DICT). Inside a group it is not seen. Once
#   synced the instance carries its plant's Uid (NA_PLOP_DICT) and sits on the proxy tag
#   (AppConfig vegetation.proxy_tag, in the GLB builder's skip range, so a proxy never
#   goes into the model's GLBs: ValeVision draws the plant itself).
# - THE SHAPE is the app's: a dome, or a box where the asset says (a hedge), width along
#   local x, depth along local y, height up, standing on its origin, built from the asset's
#   Asset__Proxy and Asset__Size. The definition keeps the size it was built at, and an
#   instance is that scaled on each axis, which is how one definition serves every plant of
#   an asset. Scale one evenly and its plant's scale follows in the app; on one axis, its
#   size, with its clumps keeping theirs.
# - A PATH'S PLANTS ARE READ-ONLY: stamped with the path's Uid and locked. Moving one
#   takes unlocking it first, and the next sync puts it back and says so.
# - THE BASE (what both sides held after the last sync) is kept in the model's
#   ValeVision__CloudExport dictionary as a JSON string, written in the same operation
#   as the proxies: an Undo puts both back together.
# - COORDINATES: Ruby reads and writes raw SketchUp poses only (origin in inches, the
#   turn about +Z, a scale per axis); every conversion to the app's saved values is in
#   the Python, in one place. Proxies live in model.entities, whose transformations are
#   world whatever is open, and the sync and the placing refuse to run with a group open
#   anyway: a proxy placed inside one would never be seen.
# - IMG## SCENES: the proxy tag is hidden in them, or the whitecard pictures would show
#   the domes (Sync Aura's known trap). A scene that does not save tags is reported.
# - THE SIGN-IN is the Sync Aura tab's: one Vale sign-in for every Vale app.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 05-Nov-2026 - Version 1.2.0
# - On unless switched off: its words, the Python decides.
#
# 04-Nov-2026 - Version 1.1.0
# - A box for an asset whose proxy is a box.
#
# 04-Nov-2026 - Version 1.0.0
# - Initial build: Sync Planting, placing from the asset library, read-only path plants,
#   the proxy tag on new instances, hidden in the IMG## scenes.
#
# =============================================================================

require 'json'
require 'tmpdir'

module Na__ValeVisionCloudSync
    module Na__VegetationSync

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

        SCOPE_SYNC          = 'veg_sync'.freeze                                    # <-- [matches UI button]
        NA_SHAPE_BOX        = 'Box'.freeze                                         # <-- Asset__Proxy's Proxy__Shape
        SCOPES              = [SCOPE_SYNC].freeze

        NA_ASSET_DICT       = 'Na__ValeVisionCloudSync__VegetationAsset'.freeze    # <-- On a proxy's definition: its asset and the size it was built at
        NA_PLOP_DICT        = 'Na__ValeVisionCloudSync__VegetationPlop'.freeze     # <-- On a synced proxy instance: its plant
        NA_ASSET_ID         = /\AVVL_\d{2}_\d{4}\z/
        NA_UID              = /\A[AP]\d{4,}(-\d{3,})?\z/                           # <-- A0007 a placed plant, P0002-014 a path's
        NA_PATH_UID         = /\AP\d{4,}\z/
        NA_BASE_KEY         = 'vegetation_base'.freeze                             # <-- Model dictionary keys (ValeVision__CloudExport)
        NA_BASE_PROJECT_KEY = 'vegetation_base_project'.freeze
        NA_LAST_SYNC_KEY    = 'vegetation_last_sync'.freeze

        NA_MATERIAL_NAME    = 'Na__ValeVision__VegetationProxy'.freeze
        NA_MATERIAL_RGB     = [214, 228, 205].freeze                               # <-- The app's proxy fill
        NA_MATERIAL_ALPHA   = 0.55
        NA_RINGS_MIN        = 2
        NA_RINGS_MAX        = 12
        NA_SECTORS_MIN      = 6
        NA_SECTORS_MAX      = 48
        NA_RINGS_FALLBACK   = 5
        NA_SECTORS_FALLBACK = 10

        NA_LIBRARY_INDEX    = 'VegetationLibrary__Index__.json'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Sync
# -----------------------------------------------------------------------------

        # FUNCTION | Run One Sync Vegetation Action
        # ------------------------------------------------------------
        # Returns the report hash the dialog renders (same shape as the
        # orchestrator's).
        # ---------------------------------------------------------------
        def self.Na__VegSync__Run(scope_id, dialog_manager)
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

            dialog_manager.na_push_status('running', 'Syncing the planting with ValeVision 3D...')
            proxies  = self.na_collect_proxies(model)
            handover = self.na_write_handover(model, proxies)
            result, raw = self.na_run_python([
                '--project-root',  paths[:project_root].to_s,
                '--library-id',    library[:library_id].to_s,
                '--sketchup-file', handover
            ])
            Na__SyncOrchestrator.na_append_python_steps(report, result)

            answer = raw.is_a?(Hash) ? raw['vegetation'] : nil
            if result[:success] && answer.is_a?(Hash)
                dialog_manager.na_push_status('running', "Bringing the project's plants into SketchUp...")
                report[:steps] << self.na_apply(model, proxies, answer)
            end
            Na__SyncOrchestrator.na_finalise_report(report)
        end

        # HELPER FUNCTION | What Stops a Sync Before Anything Runs ('' when nothing)
        # ---------------------------------------------------------------
        def self.na_preflight(model)
            return 'Open a model first.' unless model
            return 'Save the model in its project folder first.' if model.path.to_s.empty?
            return 'Close every group and component first: the vegetation proxies work at the model root.' unless model.active_path.nil?
            ''
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Placing a Proxy, Status
# -----------------------------------------------------------------------------

        # FUNCTION | Start Placing a New Proxy With SketchUp's Own Component Tool
        # ------------------------------------------------------------
        # It becomes a plant at the next sync. Its tag is set as it lands (the
        # observer below), so a GLB export before then still leaves it out.
        # ---------------------------------------------------------------
        def self.Na__VegSync__Place(asset_id)
            model = Sketchup.active_model
            return { success: false, message: 'Open a model first.' } unless model
            return { success: false, message: 'Close every group and component first: a proxy lives at the model root.' } unless model.active_path.nil?

            spec = self.na_library_spec(asset_id.to_s)
            return { success: false, message: "#{asset_id} is not in the vegetation library on this PC." } unless spec

            definition = nil
            model.start_operation('ValeVision Cloud Sync: Vegetation Proxy', true)
            begin
                definition = self.na_definition(model, asset_id.to_s, spec)
                self.na_hide_in_image_scenes(model, self.na_proxy_layer(model))                       # <-- It is in the pictures' way before its first sync too
                model.commit_operation
            rescue => error
                model.abort_operation
                return { success: false, message: "The proxy could not be built (#{error.class}: #{error.message})." }
            end
            model.place_component(definition, false)
            { success: true, message: "Click in the model to place #{spec['Name']}. It becomes a plant in ValeVision 3D at the next Sync." }
        rescue => error
            { success: false, message: "#{error.class}: #{error.message}" }
        end

        # FUNCTION | The Sync Vegetation Tab's Status Rows (no network)
        # ------------------------------------------------------------
        def self.Na__VegSync__Status(model = Sketchup.active_model)
            session = defined?(Na__AuraSync) ? Na__AuraSync.na_read_session : nil
            user    = session ? (session['User'] || {}) : {}
            proxies = model ? self.na_collect_proxies(model) : []
            dict    = model ? model.attribute_dictionary(Na__ConfigLoader.Na__ValeVisionCloudSync__ModelDictionaryName, false) : nil
            {
                signed_in:    !session.nil?,
                user_name:    (user['name'] || user['displayName'] || (session && session['Email'])).to_s,
                user_level:   (user['level'] || user['permissionLevel']).to_s,
                proxies:      proxies.length,
                linked:       proxies.count { |p| !p['Uid'].empty? && p['PathUid'].empty? },
                from_paths:   proxies.count { |p| !p['PathUid'].empty? },
                last_sync:    dict ? dict[NA_LAST_SYNC_KEY].to_s : '',
                base_project: dict ? dict[NA_BASE_PROJECT_KEY].to_s : '',
                proxy_tag:    Na__ConfigLoader.Na__ValeVisionCloudSync__VegetationPaths[:proxy_tag],
                assets:       self.na_catalogue
            }
        rescue => error
            { signed_in: false, assets: [], error: "#{error.class}: #{error.message}" }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | The Asset Library on This PC
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | The Library's Folder, From the Server Manager's Sync Map
        # ---------------------------------------------------------------
        def self.na_library_folder
            sync_map = Na__ConfigLoader.Na__ValeVisionCloudSync__LibraryPaths[:sync_map]
            mirror   = JSON.parse(File.read(sync_map, encoding: 'UTF-8')).fetch('Local').fetch('MirrorRoot').to_s.tr('\\', '/')
            File.join(mirror, Na__ConfigLoader.Na__ValeVisionCloudSync__VegetationPaths[:asset_library])
        end

        # HELPER FUNCTION | The Library's Generated Index Rows, or None
        # ---------------------------------------------------------------
        def self.na_index_rows
            doc = JSON.parse(File.read(File.join(self.na_library_folder, NA_LIBRARY_INDEX), encoding: 'UTF-8'))
            Array(doc['VegetationLibrary__Index__Assets'])
        rescue JSON::ParserError, SystemCallError, KeyError
            []
        end

        # FUNCTION | The Tab's List of Assets to Place
        # ------------------------------------------------------------
        def self.na_catalogue
            self.na_index_rows.select { |row| row['Asset__Status'] == 'Active' && row['Asset__Id'].to_s.match?(NA_ASSET_ID) }.map do |row|
                { id: row['Asset__Id'].to_s, name: row['Asset__Name'].to_s, type: row['Asset__TypeLabel'].to_s,
                  width_mm: row['Asset__WidthMm'].to_i, height_mm: row['Asset__HeightMm'].to_i }
            end
        end

        # HELPER FUNCTION | What a Proxy of a Library Asset Is Built From, or nil
        # ---------------------------------------------------------------
        def self.na_library_spec(asset_id)
            row = self.na_index_rows.find { |candidate| candidate['Asset__Id'] == asset_id }
            return nil unless row && row['Asset__File'].to_s != ''
            doc  = JSON.parse(File.read(File.join(self.na_library_folder, row['Asset__File'].to_s), encoding: 'UTF-8'))
            size = doc['Asset__Size'] || {}
            { 'Name'      => doc['Asset__Name'].to_s,
              'NominalMm' => [size['Size__WidthMm'], size['Size__DepthMm'], size['Size__HeightMm']],
              'Proxy'     => doc['Asset__Proxy'] || {} }
        rescue JSON::ParserError, SystemCallError, KeyError
            nil
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Reading the Proxies (raw SketchUp poses)
# -----------------------------------------------------------------------------

        # FUNCTION | Every Vegetation Proxy at the Model Root
        # ------------------------------------------------------------
        # model.entities is the root whatever is open, and a root instance's
        # transformation is world. Key: the instance's persistent id. Scale is on the
        # axes in this SketchUp (measured, 2027.0: a uniform scale too), and the last
        # number of the matrix is divided out for what older SketchUps saved there.
        # ---------------------------------------------------------------
        def self.na_collect_proxies(model)
            model.entities.grep(Sketchup::ComponentInstance).filter_map do |instance|
                asset_id = instance.definition.get_attribute(NA_ASSET_DICT, 'AssetId').to_s
                next unless asset_id.match?(NA_ASSET_ID)

                m     = instance.transformation.to_a                                                  # <-- Column-major: x axis, y axis, z axis, origin, divisor
                w     = m[15].to_f.zero? ? 1.0 : m[15].to_f
                x_len = Math.sqrt(m[0]**2 + m[1]**2 + m[2]**2)
                y_len = Math.sqrt(m[4]**2 + m[5]**2 + m[6]**2)
                z_len = Math.sqrt(m[8]**2 + m[9]**2 + m[10]**2)
                uid   = instance.get_attribute(NA_PLOP_DICT, 'Uid').to_s
                path  = instance.get_attribute(NA_PLOP_DICT, 'PathUid').to_s
                {
                    'Key'       => "pid:#{instance.persistent_id}",
                    'Uid'       => uid.match?(NA_UID) ? uid : '',
                    'PathUid'   => path.match?(NA_PATH_UID) ? path : '',
                    'AssetId'   => asset_id,
                    'OriginIn'  => [m[12].to_f / w, m[13].to_f / w, m[14].to_f / w],                  # <-- Inches
                    'RotZDeg'   => Math.atan2(m[1], m[0]) * 180.0 / Math::PI,
                    'ScaleXYZ'  => [x_len / w, y_len / w, z_len / w],
                    'NominalMm' => self.na_nominal_of(instance.definition),
                    'Tilted'    => z_len > 0 && (m[10] / z_len) < 0.9999,
                    '_instance' => instance
                }
            end
        end

        # HELPER FUNCTION | The Size a Proxy's Definition Was Built at, or nil
        # ---------------------------------------------------------------
        def self.na_nominal_of(definition)
            sizes = JSON.parse(definition.get_attribute(NA_ASSET_DICT, 'NominalMm').to_s)
            sizes.is_a?(Array) && sizes.length == 3 && sizes.all? { |v| v.is_a?(Numeric) && v > 0 } ? sizes : nil
        rescue JSON::ParserError
            nil
        end

        # FUNCTION | Write the Hand-Over File (proxies, the definitions' sizes, the last synced base)
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
                'Definitions'   => self.na_definition_sizes(model),
                'Proxies'       => proxies.map { |p| p.reject { |key, _| key == '_instance' } }
            }
            dir  = Na__SyncOrchestrator.na_python_log_dir || Dir.tmpdir
            path = File.join(dir, "Na__ValeVisionCloudSync__VegetationHandover__#{Time.now.strftime('%Y%m%d_%H%M%S_%L')}.json").tr('\\', '/')
            File.write(path, JSON.pretty_generate(doc))
            path
        end

        # HELPER FUNCTION | The Size of the Proxy Definition na_definition Would Use, per Asset
        # ---------------------------------------------------------------
        def self.na_definition_sizes(model)
            model.definitions.each_with_object({}) do |definition, sizes|
                asset_id = definition.get_attribute(NA_ASSET_DICT, 'AssetId').to_s
                next unless asset_id.match?(NA_ASSET_ID) && !sizes.key?(asset_id)
                nominal = self.na_nominal_of(definition)
                sizes[asset_id] = { 'NominalMm' => nominal } if nominal
            end
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Applying the Sync's Answer (one operation, the base inside it)
# -----------------------------------------------------------------------------

        # FUNCTION | Place, Move, Take Out and Stamp Proxies, Then Keep the New Base
        # ------------------------------------------------------------
        # A failed create or move drops that Uid from the base, so the next sync
        # sees "ValeVision has it, SketchUp does not match" and tries again, instead
        # of reading the gap as a deletion made in SketchUp.
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
            model.start_operation('ValeVision Cloud Sync: Vegetation', true)
            begin
                layer   = self.na_proxy_layer(model)
                erasing = []
                ops.each do |op|
                    begin
                        instance = by_key[op['Key']]
                        case op['Op']
                        when 'update'
                            raise 'its proxy has gone' unless instance && instance.valid?
                            instance.locked = false
                            instance.transformation = self.na_pose(op)
                            self.na_stamp(instance, op, project, layer)
                        when 'stamp'
                            raise 'its proxy has gone' unless instance && instance.valid?
                            self.na_stamp(instance, op, project, layer)
                        when 'unstamp'
                            if instance && instance.valid?
                                instance.locked = false
                                instance.delete_attribute(NA_PLOP_DICT)
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
                self.na_collect_proxies(model).each do |proxy|                                       # <-- A proxy placed by hand may have missed the tag
                    instance = proxy['_instance']
                    next if instance.layer == layer
                    locked = instance.locked?
                    instance.locked = false
                    instance.layer  = layer
                    instance.locked = locked
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
                return { label: 'Apply Planting In SketchUp', success: false,
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
            { label: 'Apply Planting In SketchUp', success: failed.empty?, message: message }
        end

        # HELPER FUNCTION | A Raw SketchUp Pose as a Transformation (origin, turn about +Z, a scale per axis)
        # ---------------------------------------------------------------
        def self.na_pose(op)
            origin = Array(op['OriginIn']).map(&:to_f)
            scale  = Array(op['ScaleXYZ']).map(&:to_f)
            raise 'it has no position' unless origin.length == 3
            raise 'it has no size' unless scale.length == 3 && scale.all? { |v| v > 0 }
            Geom::Transformation.new(Geom::Point3d.new(*origin)) *
                Geom::Transformation.rotation(ORIGIN, Z_AXIS, op['RotZDeg'].to_f.degrees) *
                Geom::Transformation.scaling(ORIGIN, scale[0], scale[1], scale[2])
        end

        # HELPER FUNCTION | Mark an Instance as One Plant (its Uid, its path, the project, the tag)
        # ---------------------------------------------------------------
        def self.na_stamp(instance, op, project, layer)
            uid = op['Uid'].to_s
            raise "#{uid.inspect} is not a plant's Uid" unless uid.match?(NA_UID)
            path = op['PathUid'].to_s
            instance.locked = false
            instance.set_attribute(NA_PLOP_DICT, 'Uid', uid)
            instance.set_attribute(NA_PLOP_DICT, 'PathUid', path)
            instance.set_attribute(NA_PLOP_DICT, 'ProjectId', project)
            instance.layer  = layer if layer && instance.layer != layer
            instance.name   = "#{op['Name']} #{uid}" unless op['Name'].to_s.empty?                    # <-- The Outliner names it as the app does
            instance.locked = !path.empty?                                                            # <-- A path's plant is the path's, not the artist's
        end

        # HELPER FUNCTION | The Proxy Tag, Made If It Is Not There, or nil If None Is Set
        # ---------------------------------------------------------------
        def self.na_proxy_layer(model)
            tag = Na__ConfigLoader.Na__ValeVisionCloudSync__VegetationPaths[:proxy_tag].to_s
            tag.empty? ? nil : (model.layers[tag] || model.layers.add(tag))
        end

        # HELPER FUNCTION | Hide the Proxy Tag in the IMG## Scenes, So the Pictures Never Show a Dome
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
# REGION | The Proxy's Definition (the app's dome)
# -----------------------------------------------------------------------------

        # FUNCTION | The Definition for an Asset: the One in the Model, or a New One
        # ------------------------------------------------------------
        # spec: { 'Name', 'NominalMm' => [width, depth, height], 'Proxy' => Asset__Proxy }.
        # ---------------------------------------------------------------
        def self.na_definition(model, asset_id, spec)
            raise "#{asset_id.inspect} is not a vegetation asset" unless asset_id.match?(NA_ASSET_ID)
            found = model.definitions.find { |definition| definition.get_attribute(NA_ASSET_DICT, 'AssetId') == asset_id }
            if found
                self.na_watch(found)
                return found
            end
            raise 'the sync did not say how to build it' unless spec.is_a?(Hash)
            nominal = Array(spec['NominalMm']).map(&:to_f)
            raise 'it has no size' unless nominal.length == 3 && nominal.all? { |v| v > 0 }

            definition = model.definitions.add("VegetationProxy__#{asset_id}")
            definition.description = "ValeVision 3D vegetation proxy: #{spec['Name']}. ValeVision draws the plant; move, turn or scale this and Sync Vegetation."
            definition.set_attribute(NA_ASSET_DICT, 'AssetId', asset_id)
            definition.set_attribute(NA_ASSET_DICT, 'Name', spec['Name'].to_s)
            definition.set_attribute(NA_ASSET_DICT, 'NominalMm', nominal.to_json)
            if spec['Proxy'].is_a?(Hash) && spec['Proxy']['Proxy__Shape'] == NA_SHAPE_BOX
                self.na_build_box(definition.entities, nominal, self.na_proxy_material(model))
            else
                self.na_build_dome(definition.entities, nominal, spec['Proxy'], self.na_proxy_material(model))
            end
            self.na_watch(definition)
            definition
        end

        # HELPER FUNCTION | The Proxies' Pale Material
        # ---------------------------------------------------------------
        def self.na_proxy_material(model)
            existing = model.materials[NA_MATERIAL_NAME]
            return existing if existing
            material = model.materials.add(NA_MATERIAL_NAME)
            material.color = Sketchup::Color.new(*NA_MATERIAL_RGB)
            material.alpha = NA_MATERIAL_ALPHA
            material
        end

        # FUNCTION | Build a Box: Closed, Normals Out, Standing on Its Origin
        # ------------------------------------------------------------
        # In a definition's own entities, which are local whatever is open: a hedge's proxy.
        # ---------------------------------------------------------------
        def self.na_build_box(entities, nominal_mm, material)
            a, b, h = nominal_mm[0].mm / 2.0, nominal_mm[1].mm / 2.0, nominal_mm[2].mm
            base = entities.add_face(Geom::Point3d.new(-a, -b, 0), Geom::Point3d.new(a, -b, 0), Geom::Point3d.new(a, b, 0), Geom::Point3d.new(-a, b, 0))
            base.reverse! if base.normal.z > 0                                                        # <-- Faces down, so a pushpull of minus the height raises it
            base.pushpull(-h)
            entities.grep(Sketchup::Face).each do |face|
                face.material = material
                face.back_material = material
            end
        end

        # FUNCTION | The Dome's Points: Rings From the Ground Up, Then the Top
        # ------------------------------------------------------------
        # Local inches, standing on the origin, width along x, depth along y. Each
        # ring is a level ellipse, so every panel between two rings is flat.
        # ---------------------------------------------------------------
        def self.na_dome_points(nominal_mm, proxy)
            rings   = (proxy.is_a?(Hash) ? proxy['Proxy__RingCount'] : nil).to_i
            sectors = (proxy.is_a?(Hash) ? proxy['Proxy__SectorCount'] : nil).to_i
            rings   = rings <= 0 ? NA_RINGS_FALLBACK : rings.clamp(NA_RINGS_MIN, NA_RINGS_MAX)
            sectors = sectors <= 0 ? NA_SECTORS_FALLBACK : sectors.clamp(NA_SECTORS_MIN, NA_SECTORS_MAX)
            a, b, h = nominal_mm[0].mm / 2.0, nominal_mm[1].mm / 2.0, nominal_mm[2].mm
            levels = (0...rings).map do |ring|
                latitude = (ring.to_f / rings) * (Math::PI / 2.0)
                (0...sectors).map do |sector|
                    angle = (sector.to_f / sectors) * (Math::PI * 2.0)
                    Geom::Point3d.new(Math.cos(angle) * a * Math.cos(latitude), Math.sin(angle) * b * Math.cos(latitude), h * Math.sin(latitude))
                end
            end
            { levels: levels, top: Geom::Point3d.new(0, 0, h) }
        end

        # FUNCTION | Build the Dome: Closed, Normals Out, Its Rings Showing
        # ------------------------------------------------------------
        # In a definition's own entities, which are local whatever is open. The rings
        # stay as lines and the runs up the dome are soft, so it reads as the app's rings.
        # ---------------------------------------------------------------
        def self.na_build_dome(entities, nominal_mm, proxy, material)
            dome   = self.na_dome_points(nominal_mm, proxy)
            levels = dome[:levels]
            faces  = []
            count  = levels.first.length
            (0...(levels.length - 1)).each do |ring|
                (0...count).each do |sector|
                    following = (sector + 1) % count
                    faces << entities.add_face(levels[ring][sector], levels[ring][following], levels[ring + 1][following], levels[ring + 1][sector])
                end
            end
            (0...count).each do |sector|
                faces << entities.add_face(levels.last[sector], levels.last[(sector + 1) % count], dome[:top])
            end
            base = entities.add_face(*levels.first)
            base.reverse! if base.normal.z > 0                                                        # <-- Faces down: the underside
            faces.compact.each do |face|
                outward = face.bounds.center - ORIGIN
                face.reverse! if face.normal.dot(outward) < 0
            end
            (faces.compact + [base]).each do |face|
                face.material = material
                face.back_material = material
            end
            entities.grep(Sketchup::Edge).each do |edge|
                level = (edge.start.position.z - edge.end.position.z).abs < 0.001                     # <-- A ring, or the run up the dome
                edge.smooth = !edge.faces.include?(base)
                edge.soft   = !level
            end
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | A New Instance Goes on the Proxy Tag as It Lands
# -----------------------------------------------------------------------------

        # CLASS | Tells the Module When a Proxy Definition Gains an Instance
        # ------------------------------------------------------------
        class Na__ProxyLandedObserver < Sketchup::DefinitionObserver
            def onComponentInstanceAdded(definition, instance)
                Na__VegetationSync.na_proxy_landed(definition, instance)
            end
        end

        # HELPER FUNCTION | Watch a Proxy's Definition (the same observer once, whatever the count)
        # ---------------------------------------------------------------
        def self.na_watch(definition)
            @na_observer ||= Na__ProxyLandedObserver.new
            definition.add_observer(@na_observer)
        end

        # FUNCTION | Put a Newly Landed Proxy on the Tag
        # ------------------------------------------------------------
        # Not while a sync applies its answer, which does this itself. Otherwise on
        # the next tick, once SketchUp's own tool has finished, as a transparent
        # operation: one Undo takes out the placing and this together.
        # ---------------------------------------------------------------
        def self.na_proxy_landed(_definition, instance)
            return if @na_applying
            UI.start_timer(0, false) do
                begin
                    next unless instance.valid?
                    model = instance.model
                    layer = self.na_proxy_layer(model)
                    next if layer.nil? || instance.layer == layer || instance.parent != model
                    model.start_operation('ValeVision Cloud Sync: Proxy Tag', true, false, true)
                    instance.layer = layer
                    model.commit_operation
                rescue => error
                    puts "[Na__ValeVisionCloudSync] Proxy tag: #{error.class}: #{error.message}"
                end
            end
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Running the Vegetation Sync (Python)
# -----------------------------------------------------------------------------

        # FUNCTION | Launch the Vegetation Sync and Read Its Report
        # ------------------------------------------------------------
        # Returns [normalised result, the raw report hash]. Reuses the
        # orchestrator's interpreter search, sanitised environment and run log,
        # and the Sync Aura tab's kept session.
        # ---------------------------------------------------------------
        def self.na_run_python(extra_args)
            paths     = Na__ConfigLoader.Na__ValeVisionCloudSync__VegetationPaths
            session   = Na__ConfigLoader.Na__ValeVisionCloudSync__AuraPaths[:session_file]
            lib_paths = Na__ConfigLoader.Na__ValeVisionCloudSync__LibraryPaths
            unless File.exist?(paths[:script])
                return [{ success: false, message: "Vegetation sync script not found at #{paths[:script]}." }, nil]
            end

            resolution  = Na__SyncOrchestrator.na_resolve_python_executable(Na__ConfigLoader.Na__ValeVisionCloudSync__PythonConfig)
            report_file = Na__SyncOrchestrator.na_build_report_file_path
            args = ['--action', 'sync', '--site', lib_paths[:site], '--session-file', session,
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

    end # module Na__VegetationSync
end # module Na__ValeVisionCloudSync

# =============================================================================
# END OF FILE
# =============================================================================
