# =============================================================================
# VALEDESIGNSUITE - VALEVISION CLOUD SYNC - ENTOURAGE SYNC (SKETCHUP SIDE)
# =============================================================================
#
# FILE       : Na__ValeVisionCloudSync__EntourageSync__.rb
# NAMESPACE  : Na__ValeVisionCloudSync::Na__EntourageSync
# PURPOSE    : The Sync Entourage tab: hand SketchUp's entourage proxies to the entourage
#              sync (Python), then place, move, take out and stamp proxies as its answer
#              says, in one undo step. Also starts placing a new proxy from the entourage
#              asset library.
# CREATED    : 05-Nov-2026
#
# DESCRIPTION:
# - Adam, 05-Nov-2026, asked "Should placed people sync both ways with SketchUp, as plants do
#   through Cloud Sync?": "Yes, both ways now". Sync Vegetation's shape, without what only a
#   plant has: a path, a turn, a size of its own.
# - A PROXY is a component instance at the model root whose definition this plugin built and
#   stamped with an AssetId (NA_ASSET_DICT). Inside a group it is not seen, and the report
#   says how many are. Once synced the instance carries its figure's Uid (NA_FIGURE_DICT)
#   and sits on the proxy tag (AppConfig entourage.proxy_tag, in the GLB builder's skip
#   range, so a proxy never goes into the model's GLBs: ValeVision draws the figure itself).
# - ITS OWN DICTIONARIES, NOT VEGETATION'S: Sync Vegetation takes any definition in its
#   dictionary with a VVL id for a plant, and both libraries number their assets VVL.
# - THE SHAPE is the source component's, read from the asset: a flat figure in the definition's
#   x z plane at y 0, feet on z 0, front on -y, always facing the camera and its shadow facing
#   the sun, so it turns to the camera in SketchUp as in the app. A Silhouette is one face, its
#   edges hidden, in the source's translucent mid grey. A LineDrawing is its faces, unpainted
#   as the Labrador's source is, and its lines as edges. One definition an asset, which keeps
#   the size it was built at; an instance is that placed and scaled evenly.
# - A FIGURE HAS NO TURN: it always faces the camera. So no turn is read or written here, and
#   moving a proxy keeps the directions of its axes, whatever they are.
# - THE BASE (what both sides held after the last sync) is kept in the model's
#   ValeVision__CloudExport dictionary as a JSON string, written in the same operation as the
#   proxies: an Undo puts both back together. It does not take back what the sync wrote to the
#   project, and the next sync sorts that out.
# - COORDINATES: Ruby reads and writes raw SketchUp poses only (origin in inches, the lengths
#   of the axes); every conversion to the app's saved values is in the Python, in one place.
#   Proxies live in model.entities, whose transformations are world whatever is open, and the
#   sync and the placing refuse to run with a group open anyway: a proxy placed inside one
#   would never be seen.
# - IMG## SCENES: the proxy tag is hidden in them, or the whitecard pictures would show the
#   proxies (Sync Aura's known trap). A scene that does not save tags is reported.
# - THE SIGN-IN is the Sync Aura tab's: one Vale sign-in for every Vale app.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 05-Nov-2026 - Version 1.0.0
# - Initial build: Sync People, placing from the asset library, the proxy tag on new
#   instances, hidden in the IMG## scenes.
#
# =============================================================================

require 'json'
require 'tmpdir'

module Na__ValeVisionCloudSync
    module Na__EntourageSync

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

        SCOPE_SYNC          = 'ent_sync'.freeze                                    # <-- [matches UI button]
        SCOPES              = [SCOPE_SYNC].freeze

        NA_ASSET_DICT       = 'Na__ValeVisionCloudSync__EntourageAsset'.freeze     # <-- On a proxy's definition: its asset and the size it was built at
        NA_FIGURE_DICT      = 'Na__ValeVisionCloudSync__EntourageFigure'.freeze    # <-- On a synced proxy instance: its figure
        NA_ASSET_ID         = /\AVVL_\d{2}_\d{4}\z/
        NA_UID              = /\AE\d{4,}\z/                                        # <-- E0007
        NA_BASE_KEY         = 'entourage_base'.freeze                              # <-- Model dictionary keys (ValeVision__CloudExport)
        NA_BASE_PROJECT_KEY = 'entourage_base_project'.freeze
        NA_LAST_SYNC_KEY    = 'entourage_last_sync'.freeze

        NA_KIND_SILHOUETTE  = 'Silhouette'.freeze                                  # <-- Asset__Figure's Figure__Kind
        NA_KIND_LINEDRAWING = 'LineDrawing'.freeze
        NA_MATERIAL_NAME    = 'MAT901__Entourage__Silhouette__MidGrey'.freeze      # <-- The source components' own
        NA_MATERIAL_RGB     = [127, 127, 127].freeze
        NA_MATERIAL_ALPHA   = 0.5

        NA_LIBRARY_INDEX    = 'EntourageLibrary__Index__.json'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Sync
# -----------------------------------------------------------------------------

        # FUNCTION | Run One Sync Entourage Action
        # ------------------------------------------------------------
        # Returns the report hash the dialog renders (same shape as the
        # orchestrator's).
        # ---------------------------------------------------------------
        def self.Na__EntSync__Run(scope_id, dialog_manager)
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

            dialog_manager.na_push_status('running', 'Syncing the people with ValeVision 3D...')
            proxies  = self.na_collect_proxies(model)
            handover = self.na_write_handover(model, proxies)
            result, raw = self.na_run_python([
                '--project-root',  paths[:project_root].to_s,
                '--library-id',    library[:library_id].to_s,
                '--sketchup-file', handover
            ])
            Na__SyncOrchestrator.na_append_python_steps(report, result)

            answer = raw.is_a?(Hash) ? raw['entourage'] : nil
            if result[:success] && answer.is_a?(Hash)
                dialog_manager.na_push_status('running', "Bringing the project's people into SketchUp...")
                report[:steps] << self.na_apply(model, proxies, answer)
            end
            Na__SyncOrchestrator.na_finalise_report(report)
        end

        # HELPER FUNCTION | What Stops a Sync Before Anything Runs ('' when nothing)
        # ---------------------------------------------------------------
        def self.na_preflight(model)
            return 'Open a model first.' unless model
            return 'Save the model in its project folder first.' if model.path.to_s.empty?
            return 'Close every group and component first: the entourage proxies work at the model root.' unless model.active_path.nil?
            ''
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Placing a Proxy, Status
# -----------------------------------------------------------------------------

        # FUNCTION | Start Placing a New Proxy With SketchUp's Own Component Tool
        # ------------------------------------------------------------
        # It becomes a figure at the next sync. Its tag is set as it lands (the
        # observer below), so a GLB export before then still leaves it out.
        # ---------------------------------------------------------------
        def self.Na__EntSync__Place(asset_id)
            model = Sketchup.active_model
            return { success: false, message: 'Open a model first.' } unless model
            return { success: false, message: 'Close every group and component first: a proxy lives at the model root.' } unless model.active_path.nil?

            spec = self.na_library_spec(asset_id.to_s)
            return { success: false, message: "#{asset_id} is not in the entourage library on this PC." } unless spec

            definition = nil
            model.start_operation('ValeVision Cloud Sync: Entourage Proxy', true)
            begin
                definition = self.na_definition(model, asset_id.to_s, spec)
                self.na_hide_in_image_scenes(model, self.na_proxy_layer(model))                       # <-- It is in the pictures' way before its first sync too
                model.commit_operation
            rescue => error
                model.abort_operation
                return { success: false, message: "The proxy could not be built (#{error.class}: #{error.message})." }
            end
            model.place_component(definition, false)
            { success: true, message: "Click in the model to place #{spec['Name']}. It becomes a figure in ValeVision 3D at the next Sync." }
        rescue => error
            { success: false, message: "#{error.class}: #{error.message}" }
        end

        # FUNCTION | The Sync Entourage Tab's Status Rows (no network)
        # ------------------------------------------------------------
        def self.Na__EntSync__Status(model = Sketchup.active_model)
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
                proxy_tag:    Na__ConfigLoader.Na__ValeVisionCloudSync__EntouragePaths[:proxy_tag],
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
            File.join(mirror, Na__ConfigLoader.Na__ValeVisionCloudSync__EntouragePaths[:asset_library])
        end

        # HELPER FUNCTION | The Library's Generated Index Rows, or None
        # ---------------------------------------------------------------
        def self.na_index_rows
            doc = JSON.parse(File.read(File.join(self.na_library_folder, NA_LIBRARY_INDEX), encoding: 'UTF-8'))
            Array(doc['EntourageLibrary__Index__Assets'])
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
              'NominalMm' => [size['Size__WidthMm'], size['Size__HeightMm']],
              'Figure'    => doc['Asset__Figure'] || {} }
        rescue JSON::ParserError, SystemCallError, KeyError
            nil
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Reading the Proxies (raw SketchUp poses)
# -----------------------------------------------------------------------------

        # FUNCTION | Every Entourage Proxy at the Model Root
        # ------------------------------------------------------------
        # model.entities is the root whatever is open, and a root instance's
        # transformation is world. Key: the instance's persistent id. Scale is on the
        # axes in this SketchUp (measured, 2027.0), and the last number of the matrix
        # is divided out for what older SketchUps saved there. No turn: a figure has none.
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
                uid   = instance.get_attribute(NA_FIGURE_DICT, 'Uid').to_s
                {
                    'Key'       => "pid:#{instance.persistent_id}",
                    'Uid'       => uid.match?(NA_UID) ? uid : '',
                    'AssetId'   => asset_id,
                    'OriginIn'  => [m[12].to_f / w, m[13].to_f / w, m[14].to_f / w],                  # <-- Inches
                    'ScaleXYZ'  => [x_len / w, y_len / w, z_len / w],
                    'NominalMm' => self.na_nominal_of(instance.definition),
                    'Tilted'    => z_len > 0 && (m[10] / z_len) < 0.9999,
                    '_instance' => instance
                }
            end
        end

        # HELPER FUNCTION | The [Width, Height] a Proxy's Definition Was Built at, or nil
        # ---------------------------------------------------------------
        def self.na_nominal_of(definition)
            sizes = JSON.parse(definition.get_attribute(NA_ASSET_DICT, 'NominalMm').to_s)
            sizes.is_a?(Array) && sizes.length == 2 && sizes.all? { |v| v.is_a?(Numeric) && v > 0 } ? sizes : nil
        rescue JSON::ParserError
            nil
        end

        # HELPER FUNCTION | How Many Proxies Sit Inside a Group or Component, Where a Sync Cannot See Them
        # ---------------------------------------------------------------
        def self.na_count_nested(model)
            model.definitions.sum do |definition|
                next 0 unless definition.get_attribute(NA_ASSET_DICT, 'AssetId').to_s.match?(NA_ASSET_ID)
                definition.instances.count { |instance| instance.parent.is_a?(Sketchup::ComponentDefinition) }
            end
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
                'Nested'        => self.na_count_nested(model),
                'Proxies'       => proxies.map { |p| p.reject { |key, _| key == '_instance' } }
            }
            dir  = Na__SyncOrchestrator.na_python_log_dir || Dir.tmpdir
            path = File.join(dir, "Na__ValeVisionCloudSync__EntourageHandover__#{Time.now.strftime('%Y%m%d_%H%M%S_%L')}.json").tr('\\', '/')
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
            model.start_operation('ValeVision Cloud Sync: Entourage', true)
            begin
                layer   = self.na_proxy_layer(model)
                erasing = []
                ops.each do |op|
                    begin
                        instance = by_key[op['Key']]
                        case op['Op']
                        when 'update'
                            raise 'its proxy has gone' unless instance && instance.valid?
                            self.na_unlocked(instance) { instance.transformation = self.na_pose(op, instance) }
                            self.na_stamp(instance, op, project, layer)
                        when 'stamp'
                            raise 'its proxy has gone' unless instance && instance.valid?
                            self.na_stamp(instance, op, project, layer)
                        when 'unstamp'
                            if instance && instance.valid?
                                self.na_unlocked(instance) { instance.delete_attribute(NA_FIGURE_DICT) }
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
                return { label: 'Apply People In SketchUp', success: false,
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
            { label: 'Apply People In SketchUp', success: failed.empty?, message: message }
        end

        # HELPER FUNCTION | A Raw SketchUp Pose as a Transformation
        # ---------------------------------------------------------------
        # The origin and an even scale from the sync. A figure has no turn, so a proxy being
        # moved (keeping) keeps the directions of its axes; a new one stands square to the model.
        # ---------------------------------------------------------------
        def self.na_pose(op, keeping = nil)
            origin = Array(op['OriginIn']).map(&:to_f)
            scale  = op['ScaleEven'].to_f
            raise 'it has no position' unless origin.length == 3
            raise 'it has no size' unless scale > 0
            m    = keeping ? keeping.transformation.to_a : Geom::Transformation.new.to_a
            axes = [m[0, 3], m[4, 3], m[8, 3]].map do |axis|
                length = Math.sqrt(axis[0]**2 + axis[1]**2 + axis[2]**2)
                raise 'its axes have no length' unless length > 0
                axis.map { |value| value / length * scale }
            end
            Geom::Transformation.new(axes[0] + [0.0] + axes[1] + [0.0] + axes[2] + [0.0] + origin + [1.0])
        end

        # HELPER FUNCTION | Do Something to an Instance Someone May Have Locked, Then Leave It as It Was
        # ---------------------------------------------------------------
        def self.na_unlocked(instance)
            locked = instance.locked?
            instance.locked = false if locked
            yield
            instance.locked = true if locked
        end

        # HELPER FUNCTION | Mark an Instance as One Figure (its Uid, the project, the tag)
        # ---------------------------------------------------------------
        def self.na_stamp(instance, op, project, layer)
            uid = op['Uid'].to_s
            raise "#{uid.inspect} is not a figure's Uid" unless uid.match?(NA_UID)
            self.na_unlocked(instance) do
                instance.set_attribute(NA_FIGURE_DICT, 'Uid', uid)
                instance.set_attribute(NA_FIGURE_DICT, 'ProjectId', project)
                instance.layer = layer if layer && instance.layer != layer
                instance.name  = "#{op['Name']} #{uid}" unless op['Name'].to_s.empty?                 # <-- The Outliner names it as the app does
            end
        end

        # HELPER FUNCTION | The Proxy Tag, Made If It Is Not There, or nil If None Is Set
        # ---------------------------------------------------------------
        def self.na_proxy_layer(model)
            tag = Na__ConfigLoader.Na__ValeVisionCloudSync__EntouragePaths[:proxy_tag].to_s
            tag.empty? ? nil : (model.layers[tag] || model.layers.add(tag))
        end

        # HELPER FUNCTION | Hide the Proxy Tag in the IMG## Scenes, So the Pictures Never Show a Proxy
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
# REGION | The Proxy's Definition (the source component's flat figure)
# -----------------------------------------------------------------------------

        # FUNCTION | The Definition for an Asset: the One in the Model, or a New One
        # ------------------------------------------------------------
        # spec: { 'Name', 'NominalMm' => [width, height], 'Figure' => Asset__Figure }. A build
        # that fails leaves no empty definition behind for the next sync to find.
        # ---------------------------------------------------------------
        def self.na_definition(model, asset_id, spec)
            raise "#{asset_id.inspect} is not an entourage asset" unless asset_id.match?(NA_ASSET_ID)
            found = model.definitions.find { |definition| definition.get_attribute(NA_ASSET_DICT, 'AssetId') == asset_id }
            if found
                self.na_watch(found)
                return found
            end
            raise 'the sync did not say how to build it' unless spec.is_a?(Hash)
            nominal = Array(spec['NominalMm']).map(&:to_f)
            raise 'it has no size' unless nominal.length == 2 && nominal.all? { |v| v > 0 }
            figure  = spec['Figure'].is_a?(Hash) ? spec['Figure'] : {}
            kind    = figure['Figure__Kind'].to_s
            raise "it is a #{kind.empty? ? 'figure with no kind' : kind}, which this plugin cannot draw" unless [NA_KIND_SILHOUETTE, NA_KIND_LINEDRAWING].include?(kind)

            definition = model.definitions.add("EntourageProxy__#{asset_id}")
            begin
                if kind == NA_KIND_SILHOUETTE
                    self.na_build_silhouette(definition.entities, figure, self.na_proxy_material(model))
                else
                    self.na_build_line_drawing(definition.entities, figure)
                end
            rescue
                model.definitions.remove(definition)
                raise
            end
            definition.description = "ValeVision 3D entourage proxy: #{spec['Name']}. ValeVision draws the figure; move or scale this and Sync Entourage."
            definition.behavior.always_face_camera = true
            definition.behavior.shadows_face_sun   = true
            definition.set_attribute(NA_ASSET_DICT, 'AssetId', asset_id)
            definition.set_attribute(NA_ASSET_DICT, 'Name', spec['Name'].to_s)
            definition.set_attribute(NA_ASSET_DICT, 'NominalMm', nominal.to_json)
            self.na_watch(definition)
            definition
        end

        # HELPER FUNCTION | The Silhouette's Mid Grey: the Model's Own Copy, or a New One
        # ---------------------------------------------------------------
        # A file brought in may have it under a name with a number after it.
        # ---------------------------------------------------------------
        def self.na_proxy_material(model)
            existing = model.materials[NA_MATERIAL_NAME] || model.materials.find { |material| material.name.to_s.start_with?(NA_MATERIAL_NAME) }
            return existing if existing
            material = model.materials.add(NA_MATERIAL_NAME)
            material.color = Sketchup::Color.new(*NA_MATERIAL_RGB)
            material.alpha = NA_MATERIAL_ALPHA
            material
        end

        # HELPER FUNCTION | An Asset's String of x,y Pairs as Points in the Definition's Plane
        # ---------------------------------------------------------------
        # Figure x across -> local x, figure y up -> local z, in local inches at y 0: the
        # definition's own entities are local whatever is open. A repeat of the last point, or a
        # last point closing the loop on the first, is left out: SketchUp refuses a face with one.
        # ---------------------------------------------------------------
        def self.na_points_of(text, closed)
            points = []
            text.to_s.split(/\s+/).each do |pair|
                x, y = pair.split(',', 2).map { |value| Float(value, exception: false) }
                next unless x && y
                point = Geom::Point3d.new(x.mm, 0, y.mm)
                points << point unless points.last == point
            end
            points.pop if closed && points.length > 1 && points.first == points.last
            points
        end

        # HELPER FUNCTION | Turn Every Face's Front to -y, as the Source Components' Are
        # ---------------------------------------------------------------
        def self.na_face_the_front(entities)
            entities.grep(Sketchup::Face).each { |face| face.reverse! if face.normal.y > 0 }
        end

        # FUNCTION | Build a Silhouette: One Face From the Outline, Its Edges Hidden, Mid Grey Both Sides
        # ------------------------------------------------------------
        def self.na_build_silhouette(entities, figure, material)
            outline, *pinched = self.na_split_at_repeats(self.na_points_of(figure['Figure__OutlineMm'], true))
            raise 'its outline has under three points' unless outline
            face = self.na_add_face(entities, outline)
            raise 'its outline made no face' unless face
            pinched.each { |hole| self.na_cut_hole(entities, hole) }
            self.na_face_the_front(entities)
            entities.grep(Sketchup::Face).each do |each_face|
                each_face.material      = material
                each_face.back_material = material
            end
            entities.grep(Sketchup::Edge).each { |edge| edge.hidden = true }
        end

        # FUNCTION | Build a Line Drawing: Its Faces, Then Its Lines as Edges
        # ------------------------------------------------------------
        # Largest first, so a face that fills another's hole comes after that hole is cut. A
        # sliver SketchUp will not make a face of is left out: the drawing's lines still show.
        # ---------------------------------------------------------------
        def self.na_build_line_drawing(entities, figure)
            rows = Array(figure['Figure__FacesMm']).map do |row|
                outer, *pinched = self.na_split_at_repeats(self.na_points_of(row['Face__OuterMm'], true))
                { outer: outer || [], holes: Array(row['Face__HolesMm']).map { |hole| self.na_points_of(hole, true) } + pinched }
            end
            rows.sort_by { |row| -self.na_loop_area(row[:outer]) }.each do |row|
                next unless self.na_add_face(entities, row[:outer])
                row[:holes].each { |hole| self.na_cut_hole(entities, hole) }
            end
            (Array(figure['Figure__OuterChainsMm']) + Array(figure['Figure__InnerChainsMm'])).each do |chain|
                self.na_add_chain(entities, chain)
            end
            raise 'it drew nothing' if entities.grep(Sketchup::Edge).empty?
            self.na_face_the_front(entities)
        end

        # HELPER FUNCTION | A Loop That Passes Through One Point Twice, as Loops That Do Not, Largest First
        # ---------------------------------------------------------------
        # add_face refuses a repeated point, yet SketchUp's own outer loop repeats one when a hole
        # touches the outline at a vertex: the Labrador's body. A face's inside is all one piece,
        # so whatever the loop goes round on the way is such a hole. Fewer than three points is
        # no loop at all, and the drawing's own lines are what show there.
        # ---------------------------------------------------------------
        def self.na_split_at_repeats(points)
            loops, walked = [], []
            points.each do |point|
                seen = walked.index { |held| held == point }
                if seen
                    loops << walked[seen..-1]
                    walked = walked[0..seen]
                else
                    walked << point
                end
            end
            (loops << walked).select { |piece| piece.length >= 3 }.sort_by { |piece| -self.na_loop_area(piece) }
        end

        # HELPER FUNCTION | Cut a Hole in the Face These Points Lie On
        # ---------------------------------------------------------------
        # The loop makes a face of its own, which goes, leaving its edges. Only if it is the size
        # the points say: whatever else add_face handed back is not the hole, and stays.
        # ---------------------------------------------------------------
        def self.na_cut_hole(entities, points)
            inner = self.na_add_face(entities, points)
            return unless inner && inner.valid?
            wanted = self.na_loop_area(points)
            inner.erase! if (inner.area - wanted).abs <= wanted * 0.01
        end

        # HELPER FUNCTION | A Face, or nil If SketchUp Will Not Make One of These Points
        # ---------------------------------------------------------------
        def self.na_add_face(entities, points)
            return nil if points.length < 3
            entities.add_face(points)
        rescue ArgumentError
            nil
        end

        # HELPER FUNCTION | One Chain of Lines. A Closed One Takes Its Last Line Apart
        # ---------------------------------------------------------------
        # add_edges does not merge the two ends of a closed loop (its API note), add_line does.
        # ---------------------------------------------------------------
        def self.na_add_chain(entities, chain)
            points = self.na_points_of(chain, false)
            return if points.length < 2
            closes = points.length > 2 && points.first == points.last
            points.pop if closes
            entities.add_edges(points)
            entities.add_line(points.last, points.first) if closes
        end

        # HELPER FUNCTION | The Size of a Loop in the x z Plane, by the Shoelace Sum
        # ---------------------------------------------------------------
        def self.na_loop_area(points)
            twice = 0.0
            points.each_with_index do |point, index|
                following = points[(index + 1) % points.length]
                twice += point.x * following.z - following.x * point.z
            end
            twice.abs / 2.0
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | A New Instance Goes on the Proxy Tag as It Lands
# -----------------------------------------------------------------------------

        # CLASS | Tells the Module When a Proxy Definition Gains an Instance
        # ------------------------------------------------------------
        class Na__ProxyLandedObserver < Sketchup::DefinitionObserver
            def onComponentInstanceAdded(definition, instance)
                Na__EntourageSync.na_proxy_landed(definition, instance)
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
                    next if layer.nil? || instance.layer == layer || !instance.parent.is_a?(Sketchup::Model)
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
# REGION | Running the Entourage Sync (Python)
# -----------------------------------------------------------------------------

        # FUNCTION | Launch the Entourage Sync and Read Its Report
        # ------------------------------------------------------------
        # Returns [normalised result, the raw report hash]. Reuses the
        # orchestrator's interpreter search, sanitised environment and run log,
        # and the Sync Aura tab's kept session.
        # ---------------------------------------------------------------
        def self.na_run_python(extra_args)
            paths     = Na__ConfigLoader.Na__ValeVisionCloudSync__EntouragePaths
            session   = Na__ConfigLoader.Na__ValeVisionCloudSync__AuraPaths[:session_file]
            lib_paths = Na__ConfigLoader.Na__ValeVisionCloudSync__LibraryPaths
            unless File.exist?(paths[:script])
                return [{ success: false, message: "Entourage sync script not found at #{paths[:script]}." }, nil]
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

    end # module Na__EntourageSync
end # module Na__ValeVisionCloudSync

# =============================================================================
# END OF FILE
# =============================================================================
