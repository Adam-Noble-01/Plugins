# =============================================================================
# VALEDESIGNSUITE - VALEVISION CLOUD SYNC - AURA SYNC (SKETCHUP SIDE)
# =============================================================================
#
# FILE       : Na__ValeVisionCloudSync__AuraSync__.rb
# NAMESPACE  : Na__ValeVisionCloudSync::Na__AuraSync
# PURPOSE    : The Sync Aura tab: export this model's GLBs for ValeVision AURA,
#              hand SketchUp's NPR asset proxies to the AURA sync (Python), then
#              place, move, take out and stamp proxies as AURA's answer says, in
#              one undo step. Also signs in and out of AURA.
# CREATED    : 30-Oct-2026
#
# DESCRIPTION:
# - Asked by Adam (30-Oct-2026): "Changes in the Sketchup model can be pushed to
#   the AuraRender engine, but then Aura's proxy objects can also be loaded back
#   to Sketchup, keeping both in lockstep."
# - A PROXY is a component instance at the model root whose definition the Na
#   PainterlyNPR Assets plugin stamped with an AssetId (Na__PainterlyAssets__Asset).
#   Once synced, the instance carries its AURA plop's Uid (NA_PLOP_DICT) and sits
#   on the proxy tag (AppConfig aura.proxy_tag, in the GLB builder's skip range,
#   so a proxy never goes into AURA's model: AURA draws the plop itself).
# - THE BASE (what both sides held after the last sync, AURA's world) is kept in
#   the model's ValeVision__CloudExport dictionary as a JSON string, written in
#   the same operation as the proxies: an Undo puts both back together.
# - COORDINATES: Ruby reads and writes raw SketchUp poses only (origin in inches,
#   the turn about +Z, one scale); every conversion to AURA's world is in the
#   Python, in one place. Proxies live in model.entities, whose transformations
#   are world whatever is open; the sync refuses to run with a group open anyway,
#   because the GLB builder exports the active context.
# - Proxies AURA adds come from the Na PainterlyNPR Assets plugin's own
#   definitions (its SKP, else a proxy built from its MOD). Without that plugin
#   the model still syncs; AURA's new plops wait for the next sync.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 30-Oct-2026 - Version 1.0.0
# - Initial build: Sync Model and Assets, Sync Assets Only, Sign In, Sign Out.
#
# =============================================================================

require 'json'
require 'fileutils'
require 'tmpdir'

module Na__ValeVisionCloudSync
    module Na__AuraSync

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

        SCOPE_MODEL         = 'aura_sync'.freeze                                   # <-- Model and assets [matches UI button]
        SCOPE_ASSETS        = 'aura_assets'.freeze                                 # <-- Assets only, no export, no engine session [matches UI button]
        SCOPES              = [SCOPE_MODEL, SCOPE_ASSETS].freeze

        NA_ASSET_DICT       = 'Na__PainterlyAssets__Asset'.freeze                  # <-- Na PainterlyNPR Assets stamps its definitions with this
        NA_PLOP_DICT        = 'Na__ValeVisionCloudSync__AuraPlop'.freeze           # <-- On a synced proxy instance: its AURA plop
        NA_ASSET_ID         = /\ANPR_\d{2}_\d{4}\z/
        NA_UID              = /\AA\d{4,}\z/
        NA_BASE_KEY         = 'aura_base'.freeze                                   # <-- Model dictionary keys (ValeVision__CloudExport)
        NA_BASE_PROJECT_KEY = 'aura_base_project'.freeze
        NA_LAST_SYNC_KEY    = 'aura_last_sync'.freeze
        NA_DRAWING_REV_KEY  = 'aura_drawing_rev'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Sync
# -----------------------------------------------------------------------------

        # FUNCTION | Run One Sync Aura Action
        # ------------------------------------------------------------
        # Returns the report hash the dialog renders (same shape as the
        # orchestrator's).
        # ---------------------------------------------------------------
        def self.Na__AuraSync__Run(scope_id, dialog_manager)
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
            problem = if paths[:project_root].nil?          then 'Project root not found: check the Settings tab.'
                      elsif !library[:error].to_s.empty?    then library[:error]
                      elsif !library[:exists]               then "#{library[:library_id]} is not in the Project Library yet: run Sync Project To ValeVision 3D once, and switch it on for AURA in the Gallery's Project Editor."
                      else ''
                      end
            unless problem.empty?
                report[:steps] << { label: 'Resolve Library Project', success: false, message: problem }
                return report.merge(message: problem)
            end
            report[:library_id]   = library[:library_id]
            report[:project_name] = Na__SyncOrchestrator.na_derive_project_name(model)

            if scope_id == SCOPE_MODEL
                dialog_manager.na_push_status('running', 'Step 1/3 - Exporting GLBs for AURA...')
                glb_result = Na__GlbExportBridge.Na__ValeVisionCloudSync__ExportGlbs(paths, report[:project_name], glb_dir: paths[:aura_glb_sync])
                report[:steps] << Na__SyncOrchestrator.na_step_entry('Export GLB Models For AURA', glb_result)
                unless glb_result[:success]
                    report[:steps] << { label: 'Sync With AURA', success: false, message: 'Skipped: the export failed. Nothing was sent to AURA.' }
                    return Na__SyncOrchestrator.na_finalise_report(report)
                end
                dialog_manager.na_push_status('running', 'Step 2/3 - Sending the model to AURA and syncing its NPR assets...')
            else
                dialog_manager.na_push_status('running', 'Syncing NPR assets with AURA...')
            end

            proxies  = self.na_collect_proxies(model)
            handover = self.na_write_handover(model, proxies)
            action   = scope_id == SCOPE_MODEL ? 'sync' : 'assets'
            result, raw = self.na_run_python(action, [
                '--project-root',  paths[:project_root].to_s,
                '--library-id',    library[:library_id].to_s,
                '--sketchup-file', handover
            ])
            Na__SyncOrchestrator.na_append_python_steps(report, result)

            aura = raw.is_a?(Hash) ? raw['aura'] : nil
            if result[:success] && aura.is_a?(Hash)
                dialog_manager.na_push_status('running', "#{scope_id == SCOPE_MODEL ? 'Step 3/3 - ' : ''}Bringing AURA's NPR assets into SketchUp...")
                report[:steps] << self.na_apply(model, proxies, aura)
            end
            Na__SyncOrchestrator.na_finalise_report(report)
        end

        # HELPER FUNCTION | What Stops a Sync Before Anything Runs ('' when nothing)
        # ---------------------------------------------------------------
        def self.na_preflight(model)
            return 'Open a model first.' unless model
            return 'Save the model in its project folder first.' if model.path.to_s.empty?
            return 'Close every group and component first: the GLB export and the proxies work at the model root.' unless model.active_path.nil?
            ''
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Sign In, Sign Out, Status
# -----------------------------------------------------------------------------

        # FUNCTION | Sign In to AURA (the password goes to the Python on stdin, never kept)
        # ------------------------------------------------------------
        def self.Na__AuraSync__SignIn(email, password)
            result, raw = self.na_run_python('signin', [], { 'email' => email.to_s, 'password' => password.to_s }.to_json)
            password = nil                                                                             # <-- Nothing of it outlives the call
            { success: result[:success], message: result[:message].to_s, user: raw.is_a?(Hash) ? raw['user'] : nil }
        end

        # FUNCTION | Sign Out of AURA (on the server, then the session file goes)
        # ------------------------------------------------------------
        def self.Na__AuraSync__SignOut
            result, _raw = self.na_run_python('signout', [])
            { success: result[:success], message: result[:message].to_s }
        end

        # FUNCTION | The Sync Aura Tab's Status Rows (no network: the kept session only)
        # ------------------------------------------------------------
        def self.Na__AuraSync__Status(model = Sketchup.active_model)
            session = self.na_read_session
            user    = session ? (session['User'] || {}) : {}
            proxies = model ? self.na_collect_proxies(model) : []
            dict    = model ? model.attribute_dictionary(Na__ConfigLoader.Na__ValeVisionCloudSync__ModelDictionaryName, false) : nil
            {
                signed_in:    !session.nil?,
                user_name:    (user['name'] || user['displayName'] || (session && session['Email'])).to_s,
                user_level:   (user['level'] || user['permissionLevel']).to_s,
                email:        session ? session['Email'].to_s : '',
                signed_in_at: session ? session['SignedInIso'].to_s : '',
                proxies:      proxies.length,
                synced:       proxies.count { |p| !p['Uid'].empty? },
                last_sync:    dict ? dict[NA_LAST_SYNC_KEY].to_s : '',
                base_project: dict ? dict[NA_BASE_PROJECT_KEY].to_s : '',
                proxy_tag:    Na__ConfigLoader.Na__ValeVisionCloudSync__AuraPaths[:proxy_tag],
                assets_plugin: self.na_assets_plugin?
            }
        rescue => error
            { signed_in: false, error: "#{error.class}: #{error.message}" }
        end

        # HELPER FUNCTION | The Kept Session, or nil
        # ---------------------------------------------------------------
        def self.na_read_session
            path = Na__ConfigLoader.Na__ValeVisionCloudSync__AuraPaths[:session_file]
            return nil unless File.exist?(path)
            doc = JSON.parse(File.read(path, encoding: 'UTF-8'))
            doc.is_a?(Hash) && !doc['Cookie'].to_s.empty? ? doc : nil
        rescue JSON::ParserError, SystemCallError
            nil
        end

        def self.na_assets_plugin?
            defined?(Na__PainterlyAssets) && Na__PainterlyAssets.respond_to?(:Na__PublicApi__DefinitionForAsset) ? true : false
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Reading the Proxies (raw SketchUp poses)
# -----------------------------------------------------------------------------

        # FUNCTION | Every NPR Asset Proxy at the Model Root
        # ------------------------------------------------------------
        # model.entities is the root whatever is open, and a root instance's
        # transformation is world. Key: the instance's persistent id.
        # ---------------------------------------------------------------
        def self.na_collect_proxies(model)
            model.entities.grep(Sketchup::ComponentInstance).filter_map do |instance|
                asset_id = instance.definition.get_attribute(NA_ASSET_DICT, 'AssetId').to_s
                next unless asset_id.match?(NA_ASSET_ID)

                m      = instance.transformation.to_a                                                 # <-- Column-major: x axis, y axis, z axis, origin
                scale  = Math.sqrt(m[0]**2 + m[1]**2 + m[2]**2)
                z_len  = Math.sqrt(m[8]**2 + m[9]**2 + m[10]**2)
                uid    = instance.get_attribute(NA_PLOP_DICT, 'Uid').to_s
                {
                    'Key'      => "pid:#{instance.persistent_id}",
                    'Uid'      => uid.match?(NA_UID) ? uid : '',
                    'AssetId'  => asset_id,
                    'OriginIn' => [m[12].to_f, m[13].to_f, m[14].to_f],                                # <-- Inches
                    'RotZDeg'  => Math.atan2(m[1], m[0]) * 180.0 / Math::PI,
                    'Scale'    => scale.round(6),
                    'Tilted'   => z_len > 0 && (m[10] / z_len) < 0.9999,
                    '_instance' => instance
                }
            end
        end

        # FUNCTION | Write the Hand-Over File (model name, proxies, the last synced base)
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
                'Proxies'       => proxies.map { |p| p.reject { |key, _| key == '_instance' } }
            }
            dir  = Na__SyncOrchestrator.na_python_log_dir || Dir.tmpdir
            path = File.join(dir, "Na__ValeVisionCloudSync__AuraHandover__#{Time.now.strftime('%Y%m%d_%H%M%S_%L')}.json").tr('\\', '/')
            File.write(path, JSON.pretty_generate(doc))
            path
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Applying AURA's Answer (one operation, the base inside it)
# -----------------------------------------------------------------------------

        # FUNCTION | Place, Move, Take Out and Stamp Proxies, Then Keep the New Base
        # ------------------------------------------------------------
        # A failed create or move drops that Uid from the base, so the next sync
        # sees "AURA has it, SketchUp does not match" and tries again, instead of
        # reading the gap as a deletion made in SketchUp.
        # ---------------------------------------------------------------
        def self.na_apply(model, proxies, aura)
            ops     = Array(aura['Apply'])
            by_key  = proxies.each_with_object({}) { |p, map| map[p['Key']] = p['_instance'] }
            tag     = Na__ConfigLoader.Na__ValeVisionCloudSync__AuraPaths[:proxy_tag]
            failed  = []
            counts  = Hash.new(0)
            project = aura['BaseProjectId'].to_s

            model.start_operation('ValeVision Cloud Sync: AURA Assets', true)
            begin
                layer   = tag.to_s.empty? ? nil : (model.layers[tag] || model.layers.add(tag))
                erasing = []
                ops.each do |op|
                    begin
                        instance = by_key[op['Key']]
                        case op['Op']
                        when 'update'
                            raise 'its proxy has gone' unless instance && instance.valid?
                            instance.transformation = self.na_pose(op)
                            self.na_stamp(instance, op['Uid'], project, layer, op['Name'])
                        when 'stamp'
                            raise 'its proxy has gone' unless instance && instance.valid?
                            self.na_stamp(instance, op['Uid'], project, layer, nil)
                        when 'unstamp'
                            instance.delete_attribute(NA_PLOP_DICT) if instance && instance.valid?
                        when 'delete'
                            erasing << instance if instance && instance.valid?
                        when 'create'
                            definition = self.na_definition(model, op['AssetId'])
                            created = model.entities.add_instance(definition, self.na_pose(op))
                            self.na_stamp(created, op['Uid'], project, layer, op['Name'])
                        else
                            next
                        end
                        counts[op['Op']] += 1
                    rescue => error
                        failed << { 'Uid' => op['Uid'].to_s, 'Op' => op['Op'].to_s, 'Why' => "#{op['AssetId'] || op['Uid']}: #{error.message}" }
                    end
                end
                model.entities.erase_entities(erasing.uniq) unless erasing.empty?

                retry_uids = failed.select { |f| %w[create update].include?(f['Op']) }.map { |f| f['Uid'] }
                base = Array(aura['Base']).reject { |entry| retry_uids.include?(entry['Uid'].to_s) }
                dict = model.attribute_dictionary(Na__ConfigLoader.Na__ValeVisionCloudSync__ModelDictionaryName, true)
                dict[NA_BASE_KEY]         = base.to_json                                              # <-- A JSON string: a Hash does not survive as an attribute
                dict[NA_BASE_PROJECT_KEY] = project
                dict[NA_LAST_SYNC_KEY]    = Time.now.strftime('%d-%b-%Y at %H:%M')
                dict[NA_DRAWING_REV_KEY]  = aura['DrawingRev'].to_i
                model.commit_operation
            rescue => error
                model.abort_operation
                return { label: 'Apply AURA Assets In SketchUp', success: false,
                         message: "Nothing was changed in SketchUp (#{error.class}: #{error.message}). AURA already holds this sync's changes; Sync Assets again." }
            end

            parts = []
            parts << "#{counts['create']} placed"     if counts['create'] > 0
            parts << "#{counts['update']} moved"      if counts['update'] > 0
            parts << "#{counts['delete']} taken out"  if counts['delete'] > 0
            parts << "#{counts['stamp']} newly linked to AURA" if counts['stamp'] > 0
            message = parts.empty? ? 'SketchUp already matched AURA.' : "#{parts.join(', ')} (one undo step)."
            unless failed.empty?
                message += " Not done, retried next sync: #{failed.map { |f| f['Why'] }.first(6).join('; ')}."
                message += ' Load Na PainterlyNPR Assets (Extensions menu) to place AURA\'s assets.' unless self.na_assets_plugin?
            end
            { label: 'Apply AURA Assets In SketchUp', success: failed.empty?, message: message }
        end

        # HELPER FUNCTION | A Raw SketchUp Pose as a Transformation (origin, turn about +Z, one scale)
        # ---------------------------------------------------------------
        def self.na_pose(op)
            origin = Array(op['OriginIn']).map(&:to_f)
            raise 'it has no position' unless origin.length == 3
            scale  = op['Scale'].to_f > 0 ? op['Scale'].to_f : 1.0
            Geom::Transformation.new(Geom::Point3d.new(*origin)) *
                Geom::Transformation.rotation(ORIGIN, Z_AXIS, op['RotZDeg'].to_f.degrees) *
                Geom::Transformation.scaling(scale)
        end

        # HELPER FUNCTION | Mark an Instance as One AURA Plop (its Uid, the project, the proxy tag)
        # ---------------------------------------------------------------
        def self.na_stamp(instance, uid, project, layer, name)
            raise "#{uid.inspect} is not a plop Uid" unless uid.to_s.match?(NA_UID)
            instance.set_attribute(NA_PLOP_DICT, 'Uid', uid.to_s)
            instance.set_attribute(NA_PLOP_DICT, 'ProjectId', project)
            instance.layer = layer if layer && instance.layer != layer
            instance.name  = "#{name} #{uid}" unless name.to_s.empty?                                  # <-- The Outliner names it as AURA's hover does
        end

        # HELPER FUNCTION | The Definition for an Asset, From Na PainterlyNPR Assets
        # ---------------------------------------------------------------
        def self.na_definition(model, asset_id)
            raise 'Na PainterlyNPR Assets is not loaded' unless self.na_assets_plugin?
            Na__PainterlyAssets.Na__PublicApi__DefinitionForAsset(model, asset_id.to_s, in_operation: true)
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Running the AURA Sync (Python)
# -----------------------------------------------------------------------------

        # FUNCTION | Launch the AURA Sync and Read Its Report
        # ------------------------------------------------------------
        # Returns [normalised result, the raw report hash]. Reuses the
        # orchestrator's interpreter search, sanitised environment and run log.
        # ---------------------------------------------------------------
        def self.na_run_python(action, extra_args, stdin_data = nil)
            aura      = Na__ConfigLoader.Na__ValeVisionCloudSync__AuraPaths
            lib_paths = Na__ConfigLoader.Na__ValeVisionCloudSync__LibraryPaths
            unless File.exist?(aura[:script])
                return [{ success: false, message: "AURA sync script not found at #{aura[:script]}." }, nil]
            end
            if %w[sync assets].include?(action)
                missing = [[:engine, 'Server Manager sync engine'], [:sync_map, 'Server Manager sync map']].reject { |key, _| File.exist?(lib_paths[key]) }
                unless missing.empty?
                    return [{ success: false, message: missing.map { |key, name| "#{name} not found at #{lib_paths[key]}" }.join("\n") }, nil]
                end
            end

            resolution  = Na__SyncOrchestrator.na_resolve_python_executable(Na__ConfigLoader.Na__ValeVisionCloudSync__PythonConfig)
            report_file = Na__SyncOrchestrator.na_build_report_file_path
            args = ['--action', action, '--site', lib_paths[:site], '--session-file', aura[:session_file],
                    '--sync-map', lib_paths[:sync_map], '--engine', lib_paths[:engine], '--mapping', lib_paths[:mapping],
                    '--json', '--report-file', report_file] + extra_args
            result = Na__SyncOrchestrator.na_execute_python(resolution[:command], aura[:script], args, report_file, stdin_data: stdin_data)
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

    end # module Na__AuraSync
end # module Na__ValeVisionCloudSync

# =============================================================================
# END OF FILE
# =============================================================================
