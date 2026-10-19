# =============================================================================
# TRUEVISION3D - GLB BUILDER UTILITY - POINT CLOUD EXPORT
# =============================================================================
#
# FILE       : Na__TrueVision__GlbBuilder__PointCloudExport__.rb
# NAMESPACE  : TrueVision3D::GlbBuilderUtility
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Point cloud scenes from the Na Point Cloud Viewer, rendered to
#              WebP tiles plus placement manifests in the project's
#              PointCloud__ViewportData store, ready for TrueVision viewports.
# CREATED    : 19-Oct-2026
#
# DESCRIPTION:
# - OFF BY DEFAULT. The Point Cloud tab's master switch ("Export Point Clouds")
#   is stored per model. Off, no export ever renders or even looks at a point
#   cloud; every setting is kept for when it is switched back on.
# - THE SCENES ARE THE VIEWER'S. Which SketchUp scenes carry point cloud
#   settings, their type, scale and dot size live in the Point Cloud Viewer's
#   own model dictionary and are read and changed only through its public Ruby
#   API (Na__PointCloudViewer.Na__PublicApi__*). This plugin stores only its own
#   choices: the master switch and which scenes are left out of the sync.
# - NO SCREEN CAPTURE. Each scene is rendered off screen from its SAVED camera
#   (the SketchUp scene is never selected, so no scene animation can ever be
#   caught half way). The viewer renders PNG tiles; Python turns them into WebP.
# - NOTHING IS OVERWRITTEN. Every render goes into its own revision folder,
#   named by a hash of everything that changes its pixels: an unchanged scene is
#   not rendered again, and a TrueVision viewport pinned to an older revision
#   keeps working. The store manifest is written last and atomically.
#
# STORE LAYOUT (30__TrueVision__AppContent/PointCloud__ViewportData/):
#   TrueVision__PointCloudData__Manifest__.json        <- every scene, current revision
#   PointCloudScene__<sceneId>/Rev__<key>/
#       PointCloudScene__RevisionManifest__.json        <- camera, frame, tiles, datum
#       PointCloudScene__Preview__.webp                 <- whole image, longest side <= 2048
#       PointCloud__Tile__R00__C00__.webp ...           <- full resolution, 2048 px tiles
#   00__Staging/                                         <- work in progress, removed after
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 19-Oct-2026 - Version 2.11.0
# - Initial point cloud export.
#
# =============================================================================

require 'json'
require 'fileutils'
require 'securerandom'
require 'digest'

module TrueVision3D
    module GlbBuilderUtility

    # -----------------------------------------------------------------------------
    # REGION | Constants
    # -----------------------------------------------------------------------------

        unless defined?(NA_PC_DICT)
            NA_PC_DICT              = 'Na__TrueVision__GlbBuilder__PointClouds'.freeze
            NA_PC_KEY               = 'json'.freeze
            NA_PC_SCHEMA            = 'Na__TrueVision__GlbBuilder__PointClouds'.freeze
            NA_PC_SCHEMA_VERSION    = 1
            NA_PC_FOLDER_DEFAULT    = 'PointCloud__ViewportData'.freeze
            NA_PC_STORE_MANIFEST    = 'TrueVision__PointCloudData__Manifest__.json'.freeze
            NA_PC_REVISION_MANIFEST = 'PointCloudScene__RevisionManifest__.json'.freeze
            NA_PC_PREVIEW_FILE      = 'PointCloudScene__Preview__.webp'.freeze
            NA_PC_STAGING_FOLDER    = '00__Staging'.freeze
            NA_PC_SCENE_PREFIX      = 'PointCloudScene__'.freeze
            NA_PC_REVISION_PREFIX   = 'Rev__'.freeze
            NA_PC_DATUM_TAG_PATTERN = /^\d{2}__Survey__DatumBenchmark/.freeze
            NA_PC_VIEWER_API_MIN    = 1
            NA_PC_TILE_SIZE_PX      = 2048                                  # <-- power of two: previews reduce exactly
            NA_PC_WEBP_QUALITY      = 90
            NA_PC_WEBP_METHOD       = 4
            NA_PC_PREVIEW_MAX_PX    = 2048
            NA_PC_EXPORTER_VERSION  = '2.11.0'.freeze
        end

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Settings (this plugin's own model dictionary)
    # -----------------------------------------------------------------------------

        # FUNCTION | Read The Point Cloud Settings Of A Model
        # ---------------------------------------------------------------
        # Always answers { 'enabled' => bool, 'deselected' => [ids] }. Off when
        # nothing is stored, and off when the record cannot be read.
        # ---------------------------------------------------------------
        def self.Na__PointCloud__Settings(model = Sketchup.active_model)
            blank = { 'enabled' => false, 'deselected' => [] }
            return blank unless model
            raw = model.get_attribute(NA_PC_DICT, NA_PC_KEY)
            return blank unless raw.is_a?(String) && !raw.empty?
            data = JSON.parse(raw)
            return blank unless data.is_a?(Hash) && data['schema'] == NA_PC_SCHEMA
            {
                'enabled'    => data['enabled'] == true,
                'deselected' => Array(data['deselected']).map(&:to_s).uniq,
                'extra'      => data.reject { |key, _| %w[schema schemaVersion enabled deselected updatedAt].include?(key) },
                'readonly'   => data['schemaVersion'].to_i > NA_PC_SCHEMA_VERSION
            }
        rescue JSON::ParserError, StandardError => e
            Na__Log__Warn "[PointCloud] The point cloud settings could not be read: #{e.message}"
            blank
        end
        # ---------------------------------------------------------------

        # FUNCTION | Write The Point Cloud Settings (one undoable operation)
        # ---------------------------------------------------------------
        def self.Na__PointCloud__WriteSettings(model, settings, operation_name)
            return { success: false, message: 'No active model.' } unless model
            if settings['readonly']
                return { success: false, message: 'These settings were saved by a newer GLB Builder and are left untouched.' }
            end
            data = (settings['extra'] || {}).merge(
                'schema'        => NA_PC_SCHEMA,
                'schemaVersion' => NA_PC_SCHEMA_VERSION,
                'enabled'       => settings['enabled'] == true,
                'deselected'    => Array(settings['deselected']).map(&:to_s).uniq.sort,
                'updatedAt'     => Time.now.strftime('%Y-%m-%dT%H:%M:%S%z')
            )
            model.start_operation(operation_name, true)
            model.set_attribute(NA_PC_DICT, NA_PC_KEY, JSON.generate(data))
            model.commit_operation
            { success: true, message: '' }
        rescue => e
            model.abort_operation rescue nil
            Na__Log__Warn "[PointCloud] The point cloud settings could not be saved: #{e.message}"
            { success: false, message: "#{e.class}: #{e.message}" }
        end
        # ---------------------------------------------------------------

        def self.Na__PointCloud__Enabled?(model = Sketchup.active_model)
            self.Na__PointCloud__Settings(model)['enabled'] == true
        end

        def self.Na__PointCloud__SetEnabled(model, enabled)
            settings = self.Na__PointCloud__Settings(model)
            settings['enabled'] = enabled ? true : false
            self.Na__PointCloud__WriteSettings(model, settings, enabled ? 'TrueVision: Export Point Clouds On' : 'TrueVision: Export Point Clouds Off')
        end

        # The store holds the scenes LEFT OUT, so a scene added later in the
        # viewer is synced by default.
        def self.Na__PointCloud__SetSceneSelected(model, scene_ids, selected)
            settings = self.Na__PointCloud__Settings(model)
            set = settings['deselected'].each_with_object({}) { |id, hash| hash[id] = true }
            Array(scene_ids).map(&:to_s).reject(&:empty?).each { |id| selected ? set.delete(id) : set[id] = true }
            settings['deselected'] = set.keys
            self.Na__PointCloud__WriteSettings(model, settings, 'TrueVision: Point Cloud Scene Selection')
        end

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Point Cloud Viewer API
    # -----------------------------------------------------------------------------

        # FUNCTION | Is The Point Cloud Viewer Here, And New Enough?
        # ---------------------------------------------------------------
        def self.Na__PointCloud__ViewerStatus
            unless defined?(::Na__PointCloudViewer) && ::Na__PointCloudViewer.respond_to?(:Na__PublicApi__ScenesApiVersion)
                return { available: false, version: nil,
                         message: 'The Na Point Cloud Viewer (0.9.0 or newer) is not installed or not loaded. Its Scenes tab is where point cloud scenes are set up.' }
            end
            api = ::Na__PointCloudViewer.Na__PublicApi__ScenesApiVersion.to_i
            version = ::Na__PointCloudViewer.Na__PublicApi__Version rescue '?'
            if api < NA_PC_VIEWER_API_MIN
                return { available: false, version: version, message: "The Na Point Cloud Viewer #{version} is too old. Update it to 0.9.0 or newer." }
            end
            { available: true, version: version, message: '' }
        rescue => e
            { available: false, version: nil, message: "The Na Point Cloud Viewer could not be reached (#{e.message})." }
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Viewer's Scene List, Or Why There Is None
        # ---------------------------------------------------------------
        def self.Na__PointCloud__SceneList(model = Sketchup.active_model)
            viewer = self.Na__PointCloud__ViewerStatus
            return { 'ok' => false, 'problem' => viewer[:message] } unless viewer[:available]
            ::Na__PointCloudViewer.Na__PublicApi__SceneList(model)
        rescue => e
            { 'ok' => false, 'problem' => "The point cloud scenes could not be read (#{e.message})." }
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Store Paths And Manifest
    # -----------------------------------------------------------------------------

        def self.Na__PointCloud__FolderName
            name = self.Na__PortalMapper__Config.dig('TrueVisionContent', 'PointCloudFolderName').to_s
            name.empty? ? NA_PC_FOLDER_DEFAULT : name
        end

        # The store for a linked project, or nil when the project is not on
        # this computer (nothing is ever created under a missing project).
        def self.Na__PointCloud__StorePath(link)
            return nil unless link && link[:linked]
            return nil if self.Na__PortalMapper__MissingProjectMessage(link[:project_root])
            self.Na__PortalMapper__PhaseFolderPath(link[:project_root], self.Na__PointCloud__FolderName)
        end

        def self.Na__PointCloud__SceneFolder(scene_id)
            "#{NA_PC_SCENE_PREFIX}#{scene_id}"
        end

        def self.Na__PointCloud__RevisionFolder(key)
            "#{NA_PC_REVISION_PREFIX}#{key}"
        end

        # FUNCTION | Read The Store Manifest (nil when absent or unreadable)
        # ---------------------------------------------------------------
        def self.Na__PointCloud__ReadStoreManifest(store_path)
            path = File.join(store_path.to_s, NA_PC_STORE_MANIFEST)
            return nil unless File.file?(path)
            data = JSON.parse(File.read(path, encoding: 'bom|utf-8'))
            data.is_a?(Hash) && data['PointCloudData__Schema'] == 'TrueVision__PointCloudData__Manifest' ? data : nil
        rescue JSON::ParserError, StandardError => e
            Na__Log__Warn "[PointCloud] The point cloud manifest could not be read: #{e.message}"
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Revision Already Exported, Complete On Disk?
        # ---------------------------------------------------------------
        def self.Na__PointCloud__RevisionComplete?(store_path, scene_id, key)
            folder = File.join(store_path.to_s, self.Na__PointCloud__SceneFolder(scene_id), self.Na__PointCloud__RevisionFolder(key))
            manifest = File.join(folder, NA_PC_REVISION_MANIFEST)
            return false unless File.file?(manifest)
            data = JSON.parse(File.read(manifest, encoding: 'bom|utf-8'))
            tiles = Array(data.dig('Image', 'Tiles'))
            tiles.all? { |tile| tile['File'].nil? || File.file?(File.join(folder, tile['File'].to_s)) }
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Write JSON So A Reader Never Sees Half A File
        # ---------------------------------------------------------------
        def self.Na__PointCloud__WriteJsonAtomic(path, data)
            temporary = "#{path}.#{SecureRandom.hex(4)}.tmp"
            File.write(temporary, JSON.pretty_generate(data))
            File.rename(temporary, path)
        ensure
            File.delete(temporary) if temporary && File.exist?(temporary)
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Datum Benchmark
    # -----------------------------------------------------------------------------

        # FUNCTION | Find The Survey Datum Benchmarks In A Model
        # ---------------------------------------------------------------
        # Any group or component on a ##__Survey__DatumBenchmark tag, at any depth
        # (the tag is excluded from every GLB, so the marker never shows as
        # geometry). The benchmark point is the instance's own origin, so the
        # standard component carries its axes at the benchmark.
        # ---------------------------------------------------------------
        def self.Na__PointCloud__FindDatums(model, limit = 20)
            found = []
            walk = lambda do |entities, transform, depth|
                return if depth > 8 || found.length >= limit
                entities.each do |entity|
                    next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
                    world = transform * entity.transformation
                    if entity.layer && entity.layer.name.to_s =~ NA_PC_DATUM_TAG_PATTERN
                        origin = world.origin
                        name = entity.name.to_s.empty? ? (entity.respond_to?(:definition) ? entity.definition.name.to_s : 'Datum') : entity.name.to_s
                        found << { 'Datum__Name' => name, 'Datum__Tag' => entity.layer.name.to_s,
                                   'Datum__PositionSketchUpIn' => [origin.x.to_f, origin.y.to_f, origin.z.to_f],
                                   'Datum__PositionM' => [origin.x.to_f * INCHES_TO_METERS, origin.z.to_f * INCHES_TO_METERS, -origin.y.to_f * INCHES_TO_METERS] }
                        next
                    end
                    definition = entity.respond_to?(:definition) ? entity.definition : nil
                    walk.call(definition.entities, world, depth + 1) if definition
                end
            end
            walk.call(model.entities, Geom::Transformation.new, 0)
            found
        rescue => e
            Na__Log__Warn "[PointCloud] The datum benchmark could not be read: #{e.message}"
            []
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Status (Point Cloud tab payload)
    # -----------------------------------------------------------------------------

        # FUNCTION | Build The Point Cloud Tab Status
        # ---------------------------------------------------------------
        # Plans every scene (no rendering) to say whether its last export is
        # still current. Cheap: a plan is a few hundred arithmetic operations.
        # ---------------------------------------------------------------
        def self.Na__PointCloud__BuildStatus(model = Sketchup.active_model)
            settings = self.Na__PointCloud__Settings(model)
            link     = self.Na__ProjectLink__Read(model)
            store    = self.Na__PointCloud__StorePath(link)
            manifest = store ? self.Na__PointCloud__ReadStoreManifest(store) : nil
            exported = Array(manifest && manifest['PointCloudData__Scenes']).each_with_object({}) { |row, hash| hash[row['Scene__Id']] = row }
            list     = self.Na__PointCloud__SceneList(model)
            viewer   = self.Na__PointCloud__ViewerStatus
            deselected = settings['deselected'].each_with_object({}) { |id, hash| hash[id] = true }

            scenes = Array(list['scenes']).map do |row|
                entry   = exported[row['id']]
                state   = 'notExported'
                current = entry ? entry['Scene__CurrentRevision'].to_s.sub(NA_PC_REVISION_PREFIX, '') : nil
                if entry && list['cloudLoaded'] && row['status'] == 'linked'
                    plan = ::Na__PointCloudViewer.Na__PublicApi__PlanSceneExport(model, row['id'], 'tileSizePx' => NA_PC_TILE_SIZE_PX)
                    state = plan['ok'] ? (plan['plan']['revisionKey'] == current ? 'upToDate' : 'changed') : 'unknown'
                elsif entry
                    state = 'unknown'
                end
                row.merge(
                    'selected'      => !deselected[row['id']],
                    'exportState'   => state,
                    'exportedIso'   => entry ? entry['Scene__UpdatedIso'] : nil,
                    'revisionCount' => entry ? Array(entry['Scene__Revisions']).length : 0
                )
            end

            {
                enabled:        settings['enabled'],
                readonly:       settings['readonly'] == true,
                viewer:         viewer,
                listOk:         list['ok'] == true,
                listProblem:    list['ok'] ? list['problem'] : list['problem'].to_s,
                cloudLoaded:    list['cloudLoaded'] == true,
                cloudLinked:    list['cloudLinked'] == true,
                cloudName:      list['cloudName'],
                scenes:         scenes,
                selectedCount:  scenes.count { |row| row['selected'] && row['status'] == 'linked' },
                viewTypes:      list['viewTypes'] || [],
                scalePresets:   list['scalePresets'] || [],
                imageWidthPresets: list['imageWidthPresets'] || [],
                pointSizeMaxPx: list['pointSizeMaxPx'] || 32,
                pxPerPaperMm:   list['pxPerPaperMm'] || 12,
                projectLinked:  link[:linked] == true,
                projectCode:    link[:project_code].to_s,
                storeFolder:    self.Na__PointCloud__FolderName,
                storePath:      store.to_s,
                storeExists:    store ? Dir.exist?(store) : false,
                storeMissingWhy: link[:linked] ? self.Na__PortalMapper__MissingProjectMessage(link[:project_root]).to_s : 'Link this model to a project on the Project tab.',
                datumCount:     self.Na__PointCloud__FindDatums(model, 5).length
            }
        rescue => e
            Na__Log__Warn "[PointCloud] The Point Cloud tab status could not be built: #{e.message}"
            { enabled: false, viewer: { available: false, message: e.message }, listOk: false, listProblem: e.message, scenes: [] }
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Export Job
    # -----------------------------------------------------------------------------

        # FUNCTION | Render, Convert And Publish The Selected Scenes
        # ---------------------------------------------------------------
        # Runs inside a CloudJob Fiber: it hands control back to SketchUp after
        # every tile and while Python converts, so SketchUp never freezes. Called
        # outside a Fiber (tests) it simply runs straight through.
        #
        # progress: proc(text) for the status line, or nil.
        # Returns { success, message, steps, rendered, unchanged, failed }.
        # ---------------------------------------------------------------
        def self.Na__PointCloud__ExportJob(model, link, progress = nil)
            steps = []
            say = ->(text) { progress.call(text) if progress }

            viewer = self.Na__PointCloud__ViewerStatus
            return self.na_pc_fail(steps, 'Point Cloud Viewer', viewer[:message]) unless viewer[:available]
            return self.na_pc_fail(steps, 'Project', 'Link this model to a project first.') unless link[:linked]
            missing = self.Na__PortalMapper__MissingProjectMessage(link[:project_root])
            return self.na_pc_fail(steps, 'Project', missing) if missing

            list = ::Na__PointCloudViewer.Na__PublicApi__SceneList(model)
            return self.na_pc_fail(steps, 'Point Cloud Scenes', list['problem']) unless list['ok']
            unless list['cloudLoaded']
                why = list['cloudLinked'] ? 'The point cloud is not loaded. Press Reload Point Cloud (Point Cloud tab, or the viewer\'s View tab), then export again.' :
                                            'This model has no point cloud. Import one in the Na Point Cloud Viewer first.'
                return self.na_pc_fail(steps, 'Point Cloud', why)
            end

            settings   = self.Na__PointCloud__Settings(model)
            deselected = settings['deselected'].each_with_object({}) { |id, hash| hash[id] = true }
            chosen     = Array(list['scenes']).reject { |row| deselected[row['id']] }
            left_out   = Array(list['scenes']).length - chosen.length
            if chosen.empty?
                return self.na_pc_fail(steps, 'Point Cloud Scenes', 'No point cloud scenes are switched on for sync. Set them up in the viewer\'s Scenes tab, then tick them on the Point Cloud tab.')
            end

            store = self.Na__PointCloud__StorePath(link)
            FileUtils.mkdir_p(store)
            staging = File.join(store, NA_PC_STAGING_FOLDER, Time.now.strftime('%Y%m%d-%H%M%S-') + SecureRandom.hex(3))
            steps << { label: 'Point Cloud Store', success: true, message: "#{self.Na__PointCloud__FolderName} in #{link[:project_code]}" }
            steps << { label: 'Left Out', status: 'skip', message: "#{left_out} scene(s) are switched off for sync and were left as they are." } if left_out > 0

            # --- plan: refusals are reported, the rest go on --------------------------
            plans = []
            chosen.each do |row|
                result = ::Na__PointCloudViewer.Na__PublicApi__PlanSceneExport(model, row['id'], 'tileSizePx' => NA_PC_TILE_SIZE_PX)
                if result['ok']
                    plans << result['plan']
                else
                    steps << { label: row['name'].to_s, success: false, message: result['problem'].to_s }
                end
            end

            datums    = self.Na__PointCloud__FindDatums(model)
            unchanged = plans.select { |plan| self.Na__PointCloud__RevisionComplete?(store, plan['sceneId'], plan['revisionKey']) }
            to_render = plans - unchanged
            unchanged.each { |plan| steps << { label: plan['sceneName'], status: 'skip', message: "Unchanged since its last export (#{self.Na__PointCloud__RevisionFolder(plan['revisionKey'])})." } }

            # --- render ---------------------------------------------------------------------
            rendered = []
            to_render.each_with_index do |plan, index|
                scene_dir = File.join(staging, self.Na__PointCloud__SceneFolder(plan['sceneId']), self.Na__PointCloud__RevisionFolder(plan['revisionKey']))
                png_dir   = File.join(staging, 'png', plan['sceneId'])
                FileUtils.mkdir_p(scene_dir)
                total = plan['tiles'].length
                say.call("Rendering #{plan['sceneName']} (#{index + 1} of #{to_render.length}): #{total} tile(s)...")
                self.na_pc_yield
                render = ::Na__PointCloudViewer.Na__PublicApi__RenderSceneTiles(model, plan, png_dir) do |done, count|
                    say.call("Rendering #{plan['sceneName']}: tile #{done} of #{count}")
                    self.na_pc_yield
                end
                if render['ok']
                    rendered << { plan: plan, render: render, scene_dir: scene_dir, png_dir: png_dir }
                else
                    steps << { label: plan['sceneName'], success: false, message: render['problem'].to_s }
                    FileUtils.rm_rf(scene_dir)
                end
            end

            # --- convert (Python, off SketchUp's thread) -----------------------------------------
            unless rendered.empty?
                say.call("Converting #{rendered.sum { |item| item[:render]['tiles'].count { |t| !t['empty'] } }} tile(s) to WebP...")
                converted = self.na_pc_convert(rendered, staging)
                unless converted['success']
                    FileUtils.rm_rf(staging)
                    steps << { label: 'WebP Conversion', success: false, message: converted['message'].to_s }
                    return self.na_pc_finish(steps, rendered: 0, unchanged: unchanged.length, failed: chosen.length - unchanged.length)
                end
                by_scene = Array(converted['scenes']).each_with_object({}) { |scene, hash| hash[scene['sceneId']] = scene }
                rendered.each do |item|
                    plan  = item[:plan]
                    scene = by_scene[plan['sceneId']]
                    manifest = self.na_pc_revision_manifest(plan, item[:render], scene, datums, link)
                    self.Na__PointCloud__WriteJsonAtomic(File.join(item[:scene_dir], NA_PC_REVISION_MANIFEST), manifest)
                    final_dir = File.join(store, self.Na__PointCloud__SceneFolder(plan['sceneId']), self.Na__PointCloud__RevisionFolder(plan['revisionKey']))
                    FileUtils.mkdir_p(File.dirname(final_dir))
                    FileUtils.rm_rf(final_dir) if Dir.exist?(final_dir)            # <-- an incomplete earlier try of the SAME revision
                    File.rename(item[:scene_dir], final_dir)
                    tiles = Array(manifest.dig('Image', 'Tiles'))
                    kept  = tiles.count { |tile| tile['File'] }
                    bytes = tiles.sum { |tile| tile['Bytes'].to_i } + manifest.dig('Image', 'Preview', 'Bytes').to_i
                    steps << { label: plan['sceneName'], success: true,
                               message: "#{plan['frame']['widthPx']} x #{plan['frame']['heightPx']} px, #{kept} of #{tiles.length} tile(s) written " \
                                        "(#{tiles.length - kept} empty), #{(bytes / 1024.0 / 1024.0).round(1)} MB. #{self.na_pc_scale_text(plan)}" }
                end
            end

            # --- manifest last, then tidy up --------------------------------------------------------
            self.na_pc_update_store_manifest(store, model, list, plans, datums)
            FileUtils.rm_rf(staging)
            staging_root = File.join(store, NA_PC_STAGING_FOLDER)
            Dir.rmdir(staging_root) if Dir.exist?(staging_root) && Dir.empty?(staging_root)
            steps << { label: 'Datum Benchmark', status: datums.empty? ? 'skip' : 'ok',
                       message: datums.empty? ? 'No survey datum benchmark in this model (tag ##__Survey__DatumBenchmark).' :
                                                "#{datums.length} benchmark(s) recorded with every scene: #{datums.map { |d| d['Datum__Name'] }.join(', ')}." }
            self.na_pc_finish(steps, rendered: rendered.length, unchanged: unchanged.length,
                              failed: chosen.length - rendered.length - unchanged.length)
        rescue => e
            Na__Log__Warn "[PointCloud] Export failed: #{e.class}: #{e.message}\n#{e.backtrace.first(6).join("\n")}"
            FileUtils.rm_rf(staging) if defined?(staging) && staging && Dir.exist?(staging)
            self.na_pc_fail(steps, 'Point Cloud Export', "#{e.class}: #{e.message}")
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Export Job Internals
    # -----------------------------------------------------------------------------

        # Hand control back to SketchUp when running inside a CloudJob Fiber.
        def self.na_pc_yield
            Fiber.yield
        rescue FiberError
            nil                                                                    # <-- not in a Fiber (tests): carry on
        end

        def self.na_pc_fail(steps, label, message)
            steps << { label: label, success: false, message: message.to_s }
            { success: false, message: message.to_s, steps: steps, rendered: 0, unchanged: 0, failed: 0 }
        end

        def self.na_pc_finish(steps, rendered:, unchanged:, failed:)
            success = failed.zero?
            message = "Point clouds: #{rendered} scene(s) rendered, #{unchanged} unchanged" + (failed > 0 ? ", #{failed} could not be exported." : '.')
            { success: success, message: message, steps: steps, rendered: rendered, unchanged: unchanged, failed: failed }
        end

        def self.na_pc_scale_text(plan)
            frame = plan['frame']
            return "Perspective, #{plan['pointSizePx']} px dots." if plan['projection'] == 'perspective'
            text = "1:#{frame['scaleDenominator'].to_f == frame['scaleDenominator'].to_f.round ? frame['scaleDenominator'].to_f.round : frame['scaleDenominator']} " \
                   "at #{frame['pxPerPaperMm'].to_f.round(2)} px per paper mm, #{plan['pointSizePx']} px dots."
            text += ' Reduced from 12 px per mm to stay within the image size limit.' if frame['reducedFromPxPerMm']
            text
        end

        # FUNCTION | Run The WebP Converter Through PowerShell (yields while it runs)
        # ---------------------------------------------------------------
        def self.na_pc_convert(rendered, staging)
            job = {
                'quality'      => NA_PC_WEBP_QUALITY,
                'method'       => NA_PC_WEBP_METHOD,
                'previewMaxPx' => NA_PC_PREVIEW_MAX_PX,
                'progressFile' => File.join(staging, 'progress.json'),
                'scenes'       => rendered.map do |item|
                    plan = item[:plan]
                    {
                        'sceneId'     => plan['sceneId'],
                        'widthPx'     => plan['frame']['widthPx'],
                        'heightPx'    => plan['frame']['heightPx'],
                        'tileSizePx'  => plan['tileSizePx'],
                        'previewFile' => File.join(item[:scene_dir], NA_PC_PREVIEW_FILE),
                        'tiles'       => item[:render]['tiles'].map do |tile|
                            tile.merge('png'  => File.join(item[:png_dir], tile['file']),
                                       'webp' => File.join(item[:scene_dir], tile['file'].sub(/\.png\z/, '.webp')))
                        end
                    }
                end
            }
            job_path    = File.join(staging, 'webp-job.json')
            result_path = File.join(staging, 'webp-result.json')
            File.write(job_path, JSON.generate(job))
            script = File.join(__dir__, 'Na__TrueVision__GlbBuilder__PointCloud__WebpTiles__.py')
            python = self.Na__CloudSync__ResolvePythonExecutable[:command]
            run = self.Na__CloudSync__Execute(python, script, [job_path, result_path], staging)
            unless File.file?(result_path)
                tail = [run[:stderr], run[:stdout]].map(&:to_s).reject(&:empty?).first.to_s[-600..] || ''
                hint = tail.include?('PIL') ? ' Python needs Pillow: run  pip install pillow  once.' : ''
                return { 'success' => false, 'message' => "The WebP converter did not finish.#{hint} #{tail}".strip }
            end
            JSON.parse(File.read(result_path, encoding: 'bom|utf-8'))
        rescue => e
            { 'success' => false, 'message' => "The WebP converter could not run (#{e.message})." }
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Revision Manifest TrueVision Reads For One Scene
        # ---------------------------------------------------------------
        def self.na_pc_revision_manifest(plan, render, converted, datums, link)
            frame_record = ::Na__PointCloudViewer.Na__PublicApi__SceneFrameRecord(plan)
            tiles = Array(converted && converted['tiles']).map do |tile|
                { 'Row' => tile['row'], 'Col' => tile['col'], 'X' => tile['x'], 'Y' => tile['y'], 'W' => tile['w'], 'H' => tile['h'],
                  'File' => tile['file'], 'Bytes' => tile['bytes'].to_i }
            end
            preview = converted ? converted['preview'] : nil
            frame = plan['frame']
            clip = plan['clip']
            {
                'Revision__Schema'        => 'TrueVision__PointCloudScene__Revision',
                'Revision__SchemaVersion' => 1,
                'Revision__Id'            => self.Na__PointCloud__RevisionFolder(plan['revisionKey']),
                'Revision__Key'           => plan['revisionKey'],
                'Revision__ExportedIso'   => Time.now.strftime('%Y-%m-%dT%H:%M:%S%z'),
                'Revision__Exporter'      => { 'GlbBuilder' => NA_PC_EXPORTER_VERSION,
                                               'PointCloudViewer' => (::Na__PointCloudViewer.Na__PublicApi__Version rescue nil) },
                'Project__Code'           => link[:project_code].to_s,
                'Scene__Id'               => plan['sceneId'],
                'Scene__Name'             => plan['sceneName'],
                'Scene__ViewType'         => plan['viewType'],
                'Scene__Projection'       => plan['projection'],
                'Scene__Scale'            => plan['projection'] == 'perspective' ? nil :
                                             { 'Denominator' => frame['scaleDenominator'], 'Label' => self.na_pc_scale_label(frame['scaleDenominator']) },
                'Scene__DefaultOpacity'   => (plan['opacityPercent'].to_f / 100.0).round(3),
                'Camera'                  => plan['camera'],
                'Frame'                   => frame_record,
                'Image'                   => {
                    'Format'      => 'webp',
                    'Quality'     => NA_PC_WEBP_QUALITY,
                    'WidthPx'     => frame['widthPx'],
                    'HeightPx'    => frame['heightPx'],
                    'TileSizePx'  => plan['tileSizePx'],
                    'PointSizePx' => plan['pointSizePx'],
                    'Tiles'       => tiles,
                    'Preview'     => preview ? { 'File' => preview['file'], 'WidthPx' => preview['widthPx'], 'HeightPx' => preview['heightPx'],
                                                 'Factor' => preview['factor'], 'Bytes' => preview['bytes'].to_i } : nil,
                    'RenderMs'    => render['renderMs']
                },
                'PointCloud'              => {
                    'FileName'    => plan.dig('cloud', 'fileName'),
                    'ContentKey'  => plan.dig('cloud', 'contentKey'),
                    'TotalPoints' => plan.dig('cloud', 'totalPoints'),
                    'PointBudget' => plan['pointBudget'],
                    'ColourMode'  => plan['colourMode'],
                    'Clip'        => clip ? { 'MinSketchUpIn' => clip['min'], 'MaxSketchUpIn' => clip['max'] } : nil
                },
                'Datums'                  => datums.map do |datum|
                    pixel = ::Na__PointCloudViewer.Na__PublicApi__ScenePixelFor(plan, datum['Datum__PositionSketchUpIn'])
                    datum.merge('Datum__ImagePixel' => pixel ? pixel.map { |value| value.round(3) } : nil)
                end
            }
        end
        # ---------------------------------------------------------------

        # The preview a revision names (a one-tile image is its own preview).
        def self.na_pc_preview_file(store, folder, revision)
            path = File.join(store, folder, revision, NA_PC_REVISION_MANIFEST)
            JSON.parse(File.read(path, encoding: 'bom|utf-8')).dig('Image', 'Preview', 'File')
        rescue StandardError
            nil
        end

        def self.na_pc_scale_label(denominator)
            value = denominator.to_f
            value == value.round ? "1:#{value.round}" : "1:#{value.round(3)}"
        end

        # FUNCTION | Merge This Export Into The Store Manifest (written last)
        # ---------------------------------------------------------------
        # Scenes from other models are never touched. A scene this model no
        # longer has (removed in the viewer) is marked retired, never deleted:
        # a TrueVision viewport may still show it.
        # ---------------------------------------------------------------
        def self.na_pc_update_store_manifest(store, model, list, plans, datums)
            existing = self.Na__PointCloud__ReadStoreManifest(store) || {}
            rows = Array(existing['PointCloudData__Scenes']).select { |row| row.is_a?(Hash) && row['Scene__Id'] }
            by_id = rows.each_with_object({}) { |row, hash| hash[row['Scene__Id']] = row }
            store_id = list['storeId']
            now = Time.now.strftime('%Y-%m-%dT%H:%M:%S%z')

            plans.each do |plan|
                next unless self.Na__PointCloud__RevisionComplete?(store, plan['sceneId'], plan['revisionKey'])
                folder   = self.Na__PointCloud__SceneFolder(plan['sceneId'])
                revision = self.Na__PointCloud__RevisionFolder(plan['revisionKey'])
                preview  = self.na_pc_preview_file(store, folder, revision)
                row = by_id[plan['sceneId']] || { 'Scene__Id' => plan['sceneId'], 'Scene__Revisions' => [] }
                history = Array(row['Scene__Revisions'])
                unless history.any? { |item| item['Revision__Id'] == revision }
                    history << { 'Revision__Id' => revision, 'Revision__ExportedIso' => now,
                                 'Revision__Manifest' => "#{folder}/#{revision}/#{NA_PC_REVISION_MANIFEST}" }
                end
                row.merge!(
                    'Scene__Name'            => plan['sceneName'],
                    'Scene__ViewType'        => plan['viewType'],
                    'Scene__Projection'      => plan['projection'],
                    'Scene__Scale'           => plan['projection'] == 'perspective' ? nil :
                                                { 'Denominator' => plan['frame']['scaleDenominator'], 'Label' => self.na_pc_scale_label(plan['frame']['scaleDenominator']) },
                    'Scene__DefaultOpacity'  => (plan['opacityPercent'].to_f / 100.0).round(3),
                    'Scene__Status'          => 'active',
                    'Scene__SourceStoreId'   => store_id,
                    'Scene__SourceModel'     => model.title.to_s,
                    'Scene__Folder'          => folder,
                    'Scene__CurrentRevision' => revision,
                    'Scene__CurrentManifest' => "#{folder}/#{revision}/#{NA_PC_REVISION_MANIFEST}",
                    'Scene__Preview'         => preview ? "#{folder}/#{revision}/#{preview}" : nil,
                    'Scene__UpdatedIso'      => now,
                    'Scene__Revisions'       => history
                )
                by_id[plan['sceneId']] = row
            end

            live_ids = Array(list['scenes']).map { |row| row['id'] }
            by_id.each_value do |row|
                next unless store_id && row['Scene__SourceStoreId'] == store_id
                row['Scene__Status'] = 'retired' unless live_ids.include?(row['Scene__Id'])
            end

            manifest = {
                'PointCloudData__Schema'        => 'TrueVision__PointCloudData__Manifest',
                'PointCloudData__SchemaVersion' => 1,
                'PointCloudData__ExportedIso'   => now,
                'PointCloudData__ExporterVersion' => NA_PC_EXPORTER_VERSION,
                'PointCloudData__CoordinateSystem' => {
                    'Units' => 'metres', 'UpAxis' => 'Y',
                    'FromSketchUp' => 'SketchUp inches (x, y, z), Z up, become (x, z, -y) x 0.0254 metres, with no offset: the same as the GLB Builder models.'
                },
                'PointCloudData__Scenes'        => by_id.values.sort_by { |row| [row['Scene__Status'] == 'active' ? 0 : 1, row['Scene__Name'].to_s.downcase] },
                'PointCloudData__Datums'        => datums
            }
            self.Na__PointCloud__WriteJsonAtomic(File.join(store, NA_PC_STORE_MANIFEST), manifest)
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

    end  # module GlbBuilderUtility
end  # module TrueVision3D

# =============================================================================
# END OF FILE
# =============================================================================
