# =============================================================================
# TRUEVISION3D - GLB BUILDER UTILITY - SCENE SYNC
# =============================================================================
#
# FILE       : Na__TrueVision__GlbBuilder__SceneSync__.rb
# NAMESPACE  : TrueVision3D::GlbBuilderUtility
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : SketchUp scenes kept in lockstep with TrueVision: the plans,
#              elevations, sections and 3D views its layout viewports bind to,
#              set up once, in SketchUp.
# CREATED    : 19-Oct-2026
#
# DESCRIPTION:
# - Adam: "We need a way like ValeVision that can take 3D and 2D scenes from
#   SketchUp and sync them to TrueVision ... by default they should just all
#   be off. Certain ones, when switched on, stay in sync and thus have
#   generatable 3D and 2D viewports, so you don't have to set everything up
#   twice." And: "SketchUp has ownership, but they should be detachable ...
#   kept in lockstep with the TrueVision versions unless detached at either
#   end or toggled off."
# - OFF BY DEFAULT, scene by scene. A scene is switched on in the Scene Sync
#   tab; nothing else is ever sent.
# - BY PERSISTENT ID. A scene is found by Page#persistent_id (stable within a
#   model since SketchUp 2018); its name is only a label. Renaming a scene in
#   SketchUp renames it in TrueVision and breaks nothing.
# - NOTHING IS WRITTEN TO A SKETCHUP SCENE. This plugin keeps its choices in
#   its own model dictionary (Na__TrueVision__GlbBuilder__SceneSync) and only
#   READS pages: camera, active section planes (SketchUp 2026), hidden tags.
#   No page is ever selected, so no scene transition is ever started.
# - THE FILE TRUEVISION READS describes each scene's GEOMETRY in neutral terms:
#   its camera in SketchUp inches and in TrueVision metres, its section plane,
#   and the drawing it implies (a plan's cut height, an elevation's exact
#   bearing and plane, where the camera looks and how much it shows). The
#   TrueVision side builds its own read-only plan, elevation and presentation
#   scene records from it when a project loads.
# - NEVER DELETED. A scene switched off, detached, or whose SketchUp scene is
#   gone stays in the file with its last synced geometry and a state that says
#   why, so a TrueVision viewport bound to it keeps working:
#     synced    switched on: refreshed by every sync
#     off       switched off: frozen at its last sync
#     detached  detached here: frozen for good; switching the scene on again
#               starts a NEW synced scene, the detached one stays TrueVision's
#     missing   switched on, but the SketchUp scene was deleted
# - DETACHED AT EITHER END. Detached here, the row is frozen as above.
#   Detached in TrueVision (its Layout Editor's SketchUp Scenes panel), the
#   records become TrueVision's own, saved in the project data with
#   Sync__DetachedFrom 'sketchup'; TrueVision then ignores this file for that
#   id. The tab reads the project data on this computer to say so.
# - Several SketchUp models may sync into one project: each model's scenes
#   carry its store id, and a sync rewrites only its own model's rows.
#
# STORE (30__TrueVision__AppContent/SceneSync__SketchUpSceneData/):
#   TrueVision__SceneSyncData__Manifest__.json     every synced scene, all models
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 19-Oct-2026 - Version 2.12.0
# - Initial Scene Sync.
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

        unless defined?(NA_SS_DICT)
            NA_SS_DICT              = 'Na__TrueVision__GlbBuilder__SceneSync'.freeze
            NA_SS_KEY               = 'json'.freeze
            NA_SS_SCHEMA            = 'Na__TrueVision__GlbBuilder__SceneSync'.freeze
            NA_SS_SCHEMA_VERSION    = 1
            NA_SS_FOLDER_DEFAULT    = 'SceneSync__SketchUpSceneData'.freeze
            NA_SS_MANIFEST          = 'TrueVision__SceneSyncData__Manifest__.json'.freeze
            NA_SS_MANIFEST_SCHEMA   = 'TrueVision__SceneSyncData__Manifest'.freeze
            NA_SS_MANIFEST_VERSION  = 1
            NA_SS_ID_PATTERN        = /\Asus_[0-9a-f]{8,32}\z/.freeze
            NA_SS_STORE_PATTERN     = /\Asuss_[0-9a-f]{8,32}\z/.freeze
            NA_SS_TYPES             = %w[plan elevation section view3d].freeze
            NA_SS_EXPORTER_VERSION  = '2.12.0'.freeze
            NA_SS_INCH_M            = 0.0254
            NA_SS_INCH_MM           = 25.4
        end
        NA_SS_TYPE_LABELS = { 'plan' => 'Plan', 'elevation' => 'Elevation', 'section' => 'Section', 'view3d' => '3D View' }.freeze unless defined?(NA_SS_TYPE_LABELS)

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Settings (this plugin's own model dictionary)
    # -----------------------------------------------------------------------------

        # FUNCTION | Read The Scene Sync Settings Of A Model
        # ---------------------------------------------------------------
        # Always answers { 'storeId', 'scenes' => [entry], 'detached' => [entry],
        # 'extra', 'readonly' }. An entry is { 'id', 'pid', 'name', 'on', 'type' }
        # ('type' nil means automatic). A model nobody has touched has no
        # entries at all: every scene off. A record from a newer GLB Builder is
        # read but never rewritten; one that cannot be read is left alone too.
        # ---------------------------------------------------------------
        def self.Na__SceneSync__Settings(model = Sketchup.active_model)
            blank = { 'storeId' => nil, 'scenes' => [], 'detached' => [], 'extra' => {}, 'readonly' => false }
            return blank unless model
            raw = model.get_attribute(NA_SS_DICT, NA_SS_KEY)
            return blank unless raw.is_a?(String) && !raw.empty?
            data = JSON.parse(raw)
            return blank.merge('readonly' => true, 'problem' => 'The Scene Sync record is not one this plugin wrote.') unless data.is_a?(Hash) && data['schema'] == NA_SS_SCHEMA
            clean = lambda do |entry|
                next nil unless entry.is_a?(Hash) && entry['id'].to_s =~ NA_SS_ID_PATTERN && entry['pid'].is_a?(Integer)
                { 'id' => entry['id'].to_s, 'pid' => entry['pid'], 'name' => entry['name'].to_s, 'on' => entry['on'] == true,
                  'type' => NA_SS_TYPES.include?(entry['type']) ? entry['type'] : nil,
                  'detachedAt' => entry['detachedAt'] }
            end
            {
                'storeId'  => data['storeId'].to_s =~ NA_SS_STORE_PATTERN ? data['storeId'].to_s : nil,
                'scenes'   => Array(data['scenes']).map(&clean).compact,
                'detached' => Array(data['detached']).map(&clean).compact,
                'extra'    => data.reject { |key, _| %w[schema schemaVersion storeId scenes detached updatedAt].include?(key) },
                'readonly' => data['schemaVersion'].to_i > NA_SS_SCHEMA_VERSION
            }
        rescue JSON::ParserError, StandardError => e
            Na__Log__Warn "[SceneSync] The Scene Sync settings could not be read: #{e.message}"
            blank.merge('readonly' => true, 'problem' => "The Scene Sync record could not be read (#{e.message}), so it is left untouched.")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Write The Scene Sync Settings (one undoable operation)
        # ---------------------------------------------------------------
        def self.Na__SceneSync__WriteSettings(model, settings, operation_name)
            return { success: false, message: 'No active model.' } unless model
            if settings['readonly']
                return { success: false, message: settings['problem'] || 'These Scene Sync settings were saved by a newer GLB Builder and are left untouched.' }
            end
            settings['storeId'] ||= "suss_#{SecureRandom.hex(6)}"
            strip = ->(entry) { entry.reject { |key, value| value.nil? || (key == 'detachedAt' && value.to_s.empty?) } }
            data = (settings['extra'] || {}).merge(
                'schema'        => NA_SS_SCHEMA,
                'schemaVersion' => NA_SS_SCHEMA_VERSION,
                'storeId'       => settings['storeId'],
                'scenes'        => settings['scenes'].map(&strip),
                'detached'      => settings['detached'].map(&strip),
                'updatedAt'     => Time.now.strftime('%Y-%m-%dT%H:%M:%S%z')
            )
            model.start_operation(operation_name, true)
            model.set_attribute(NA_SS_DICT, NA_SS_KEY, JSON.generate(data))
            model.commit_operation
            { success: true, message: '' }
        rescue => e
            model.abort_operation rescue nil
            Na__Log__Warn "[SceneSync] The Scene Sync settings could not be saved: #{e.message}"
            { success: false, message: "#{e.class}: #{e.message}" }
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | A Fresh Scene Id Nobody In This Model Has Used
        # ---------------------------------------------------------------
        def self.na_ss_new_id(settings)
            used = (settings['scenes'] + settings['detached']).map { |entry| entry['id'] }
            loop do
                id = "sus_#{SecureRandom.hex(4)}"
                return id unless used.include?(id)
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Switch Scenes On Or Off (by persistent id), One Operation
        # ---------------------------------------------------------------
        # Switching off keeps the entry (and its id), so switching the scene on
        # again resumes the SAME TrueVision scene. A detached scene's page that
        # is switched on again gets a NEW entry: the detached one stays as it was.
        # ---------------------------------------------------------------
        def self.Na__SceneSync__SetOn(model, pids, on)
            settings = self.Na__SceneSync__Settings(model)
            pages = self.na_ss_pages_by_pid(model)
            Array(pids).map(&:to_i).uniq.each do |pid|
                entry = settings['scenes'].find { |row| row['pid'] == pid }
                if entry
                    entry['on'] = on ? true : false
                    entry['name'] = pages[pid].name.to_s if pages[pid]
                elsif on && pages[pid]
                    settings['scenes'] << { 'id' => self.na_ss_new_id(settings), 'pid' => pid, 'name' => pages[pid].name.to_s, 'on' => true, 'type' => nil }
                end
            end
            self.Na__SceneSync__WriteSettings(model, settings, on ? 'TrueVision: Scene Sync On' : 'TrueVision: Scene Sync Off')
        end
        # ---------------------------------------------------------------

        # FUNCTION | Choose A Scene's Type (nil: automatic, from its camera)
        # ---------------------------------------------------------------
        def self.Na__SceneSync__SetType(model, pid, type)
            settings = self.Na__SceneSync__Settings(model)
            entry = settings['scenes'].find { |row| row['pid'] == pid.to_i }
            return { success: false, message: 'Switch this scene on first.' } unless entry
            entry['type'] = NA_SS_TYPES.include?(type.to_s) ? type.to_s : nil
            self.Na__SceneSync__WriteSettings(model, settings, 'TrueVision: Scene Sync Type')
        end
        # ---------------------------------------------------------------

        # FUNCTION | Detach A Scene: TrueVision Keeps Its Last Sync For Good
        # ---------------------------------------------------------------
        # The entry moves to the detached list; the next sync writes it to the
        # project frozen, marked detached, and never touches it again.
        # ---------------------------------------------------------------
        def self.Na__SceneSync__Detach(model, pid)
            settings = self.Na__SceneSync__Settings(model)
            entry = settings['scenes'].find { |row| row['pid'] == pid.to_i }
            return { success: false, message: 'This scene is not synced, so there is nothing to detach.' } unless entry
            settings['scenes'].delete(entry)
            settings['detached'] << entry.merge('on' => false, 'detachedAt' => Time.now.strftime('%Y-%m-%dT%H:%M:%S%z'))
            self.Na__SceneSync__WriteSettings(model, settings, 'TrueVision: Scene Sync Detach')
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Reading A Scene (never selects it)
    # -----------------------------------------------------------------------------

        # HELPER FUNCTION | The Model's Pages By Persistent Id
        # ---------------------------------------------------------------
        def self.na_ss_pages_by_pid(model)
            return {} unless model && model.respond_to?(:pages)
            model.pages.to_a.each_with_object({}) { |page, hash| hash[page.persistent_id] = page if page.respond_to?(:persistent_id) }
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | SketchUp Inches (x, y, z) to TrueVision Metres (x, z, -y), and a Direction Likewise
        # ---------------------------------------------------------------
        def self.na_ss_point_m(point)
            [point.x.to_f * NA_SS_INCH_M, point.z.to_f * NA_SS_INCH_M, -point.y.to_f * NA_SS_INCH_M].map { |value| value.round(6) }
        end
        def self.na_ss_vector(vector)
            length = Math.sqrt(vector.x.to_f**2 + vector.y.to_f**2 + vector.z.to_f**2)
            length = 1.0 if length.zero?
            [vector.x.to_f / length, vector.z.to_f / length, -vector.y.to_f / length].map { |value| value.round(9) }
        end
        def self.na_ss_su(point)
            [point.x.to_f, point.y.to_f, point.z.to_f].map { |value| value.round(6) }
        end
        # ---------------------------------------------------------------

        # FUNCTION | What Type The Camera Says A Scene Is
        # ---------------------------------------------------------------
        # Perspective: a 3D View. Parallel looking straight down: a Plan.
        # Parallel looking level: a Section when a section plane faces the
        # camera, else an Elevation. Anything else (an axonometric) is a 3D View.
        # ---------------------------------------------------------------
        def self.na_ss_suggested_type(camera, section)
            return 'view3d' if camera.perspective?
            dz = camera.direction.z.to_f
            return 'plan' if dz < -0.999
            return (section && section[:facing] ? 'section' : 'elevation') if dz.abs < 0.001
            'view3d'
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Scene's Active Section Plane That Faces Its Camera (nil when none)
        # ---------------------------------------------------------------
        # Page#active_section_planes is SketchUp 2026. Only planes at the
        # model's top level are read: a plane inside a group or component would
        # need that instance's transformation, and TrueVision's cut is one
        # plane across the whole model anyway. Of several, the one most square
        # to the view wins. { point (inches), normal, name, facing, offDeg }.
        # ---------------------------------------------------------------
        def self.na_ss_section(page, camera)
            return nil unless page.respond_to?(:active_section_planes) && page.respond_to?(:use_section_planes?) && page.use_section_planes?
            planes = Array(page.active_section_planes).select { |plane| plane.respond_to?(:get_plane) && plane.parent.is_a?(Sketchup::Model) }
            return nil if planes.empty?
            view = camera.direction
            best = planes.map do |plane|
                a, b, c, d = plane.get_plane.map(&:to_f)
                length = Math.sqrt(a * a + b * b + c * c)
                next nil if length.zero?
                normal = [a / length, b / length, c / length]
                cosine = (normal[0] * view.x + normal[1] * view.y + normal[2] * view.z).abs
                { plane: plane, normal: normal, point: normal.map { |value| value * (-d / length) }, cosine: cosine }
            end.compact.max_by { |item| item[:cosine] }
            return nil unless best
            off_deg = Math.acos([[best[:cosine], 1.0].min, -1.0].max) * 180.0 / Math::PI
            {
                point:  best[:point],
                normal: best[:normal],
                name:   (best[:plane].respond_to?(:name) ? best[:plane].name.to_s : ''),
                facing: off_deg <= 0.5,
                offDeg: off_deg
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | The TrueVision Model Layer Keys This Scene Hides
        # ---------------------------------------------------------------
        # A category is hidden only when EVERY tag that feeds it is hidden in
        # the scene (the GLB Builder groups tags by number, so several tags
        # make one category). Keys are the GLB file stems, exactly as
        # TrueVision's Model Layers panel names them. Storey categories are not
        # read yet: their keys depend on the storey container a tag sits in.
        # ---------------------------------------------------------------
        def self.na_ss_hidden_categories(model, page)
            ranges = self.Na__ExportConfig__TagRanges rescue {}
            skips  = self.Na__ExportConfig__SkipRanges rescue []
            linetypes = {}
            begin
                tags_data = Na__DataLib__CacheData.Na__Cache__LoadData(:tags)
                linetypes = self.Na__Linetype__BuildDefinitions(tags_data).first if tags_data && self.respond_to?(:Na__Linetype__BuildDefinitions)
            rescue StandardError
                linetypes = {}
            end
            use_hidden = page.respond_to?(:use_hidden_layers?) && page.use_hidden_layers?
            flipped    = use_hidden ? Array(page.layers) : []
            flipped_folders = use_hidden && page.respond_to?(:layer_folders) ? Array(page.layer_folders) : []
            # A page lists the tags and folders whose visibility DIFFERS from their
            # default (Page#layers, #layer_folders), so each is visible on the
            # page when "listed" and "hidden by default" agree.
            on_page = lambda do |item, listed|
                by_default = item.respond_to?(:page_behavior) ? ((item.page_behavior & LAYER_HIDDEN_BY_DEFAULT) == LAYER_HIDDEN_BY_DEFAULT rescue false) : false
                listed.include?(item) == by_default
            end
            folder_shown = lambda do |folder|
                while folder
                    return false unless on_page.call(folder, flipped_folders)
                    folder = folder.respond_to?(:folder) ? folder.folder : nil
                end
                true
            end
            visible_any = {}
            model.layers.each do |layer|
                name = layer.name.to_s
                key = if linetypes[name]
                          linetypes[name][:stem]
                      elsif (match = name.match(/\A(\d{2})__/))
                          number = match[1].to_i
                          next if skips.include?(number)
                          ranges.find { |_stem, numbers| Array(numbers).include?(number) }&.first
                      end
                next unless key
                visible = if use_hidden
                              on_page.call(layer, flipped) && folder_shown.call(layer.respond_to?(:folder) ? layer.folder : nil)
                          else
                              layer.visible?                                        # <-- the scene does not save tags: the model's own state
                          end
                visible_any[key] = (visible_any[key] || false) || visible
            end
            visible_any.reject { |_key, visible| visible }.keys.sort
        rescue => e
            Na__Log__Warn "[SceneSync] Hidden tags could not be read for #{page.name}: #{e.message}"
            []
        end
        # ---------------------------------------------------------------

        # FUNCTION | Read One Scene Into Its Manifest Row (or { problem })
        # ---------------------------------------------------------------
        def self.Na__SceneSync__Capture(model, page, entry)
            return { problem: 'This SketchUp scene does not save a camera position. Tick Camera Location in its scene properties and update it.' } unless page.use_camera?
            camera    = page.camera
            section   = self.na_ss_section(page, camera)
            suggested = self.na_ss_suggested_type(camera, section)
            type      = entry['type'] || suggested
            eye_m     = self.na_ss_point_m(camera.eye)
            target_m  = self.na_ss_point_m(camera.target)
            dir_m     = self.na_ss_vector(camera.direction)
            perspective = camera.perspective?
            aspect    = camera.aspect_ratio.to_f
            fov_v     = nil
            if perspective
                fov_v = camera.fov.to_f
                fov_v = (2.0 * Math.atan(Math.tan(fov_v * Math::PI / 360.0) / aspect) * 180.0 / Math::PI) if aspect > 0.0 && camera.respond_to?(:fov_is_height?) && !camera.fov_is_height?
            end
            ortho_h_m = perspective ? nil : (camera.height.to_f * NA_SS_INCH_M).round(6)
            warnings = []
            warnings << 'A plan should look straight down. This scene\'s camera is tilted, so TrueVision draws it as seen from directly above.' if type == 'plan' && (perspective || camera.direction.z.to_f > -0.9999)
            warnings << 'An elevation or section should look level. This scene\'s camera is tilted, so TrueVision draws it looking level on the same bearing.' if %w[elevation section].include?(type) && (perspective || camera.direction.z.to_f.abs > 1e-4)
            warnings << 'A section needs an active section plane facing the camera. TrueVision draws this scene as an elevation until it has one.' if type == 'section' && !(section && section[:facing])
            warnings << "The section plane is #{section[:offDeg].round(2)} degrees off square to the camera, so TrueVision cuts square to the view through the same point." if section && %w[elevation section plan].include?(type) && !section[:facing] && section[:offDeg] < 30

            drawing = self.na_ss_drawing(type, camera, section, target_m, dir_m, aspect)
            row = {
                'Scene__Id'           => entry['id'],
                'Scene__PagePid'      => page.persistent_id,
                'Scene__Name'         => page.name.to_s,
                'Scene__Description'  => page.description.to_s,
                'Scene__Type'         => type,
                'Scene__TypeLabel'    => NA_SS_TYPE_LABELS[type],
                'Scene__TypeSuggested'=> suggested,
                'Camera'              => {
                    'Projection' => perspective ? 'perspective' : 'orthographic',
                    'SketchUp'   => {
                        'Units' => 'inches', 'UpAxis' => 'Z',
                        'Eye' => self.na_ss_su(camera.eye), 'Target' => self.na_ss_su(camera.target),
                        'Up' => [camera.up.x, camera.up.y, camera.up.z].map { |v| v.to_f.round(9) },
                        'Direction' => [camera.direction.x, camera.direction.y, camera.direction.z].map { |v| v.to_f.round(9) },
                        'Perspective' => perspective, 'FovDeg' => perspective ? camera.fov.to_f.round(6) : nil,
                        'FovIsHeight' => camera.respond_to?(:fov_is_height?) ? camera.fov_is_height? : true,
                        'AspectRatio' => aspect.round(6), 'OrthoHeight' => perspective ? nil : camera.height.to_f.round(6)
                    },
                    'ThreeJs'    => {
                        'Units' => 'metres', 'UpAxis' => 'Y',
                        'Position' => eye_m, 'Target' => target_m, 'Up' => self.na_ss_vector(camera.up), 'Direction' => dir_m,
                        'Right' => self.na_ss_vector(camera.xaxis),
                        'FovVerticalDeg' => fov_v ? fov_v.round(6) : nil,
                        'Aspect' => aspect > 0.0 ? aspect.round(6) : nil,
                        'OrthoHeightM' => ortho_h_m
                    }
                },
                'Section'             => section ? {
                    'Name' => section[:name], 'PointM' => [section[:point][0] * NA_SS_INCH_M, section[:point][2] * NA_SS_INCH_M, -section[:point][1] * NA_SS_INCH_M].map { |v| v.round(6) },
                    'NormalM' => [section[:normal][0], section[:normal][2], -section[:normal][1]].map { |v| v.round(9) },
                    'OffSquareDeg' => section[:offDeg].round(4)
                } : nil,
                'Drawing'             => drawing,
                'ModelLayers'         => { 'Hidden' => self.na_ss_hidden_categories(model, page) }
            }
            row = self.na_ss_clean(row)                                         # <-- No -0.0 anywhere: the same view always writes the same bytes
            row['Scene__Revision'] = Digest::SHA256.hexdigest(JSON.generate(row.reject { |key, _| key == 'Scene__Id' }))[0, 10]
            row['Scene__Warnings'] = warnings unless warnings.empty?
            row
        rescue => e
            Na__Log__Warn "[SceneSync] #{page.name} could not be read: #{e.class}: #{e.message}"
            { problem: "This scene could not be read (#{e.message})." }
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Every -0.0 in a Row Made 0.0 (rounding a tiny negative gives -0.0)
        # ---------------------------------------------------------------
        def self.na_ss_clean(value)
            case value
            when Hash  then value.each_with_object({}) { |(key, item), hash| hash[key] = self.na_ss_clean(item) }
            when Array then value.map { |item| self.na_ss_clean(item) }
            when Float then value.zero? ? 0.0 : value
            else value
            end
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | The Drawing A Scene Implies, In TrueVision's Own Terms
        # ---------------------------------------------------------------
        # Elevation and section: Na__ElevData__GetAxes - the normal points from
        # the building to the viewer, azimuth 0 stands the viewer to the north
        # (-Z), azimuth = atan2(normal x, -normal z); drawing x is the run along
        # right = (normal z, 0, -normal x) and drawing y is minus the height, in
        # millimetres from the world origin. The plane's distance along the
        # normal is what the section cut reads (GetPlaneDistanceMm).
        # Plan: drawing x = world X, drawing y = world Z, in millimetres.
        # ---------------------------------------------------------------
        def self.na_ss_drawing(type, camera, section, target_m, dir_m, aspect)
            target_mm = target_m.map { |value| value * 1000.0 }
            height_mm = camera.perspective? ? nil : camera.height.to_f * NA_SS_INCH_MM
            frame = height_mm ? { 'Height' => height_mm.round(3), 'Width' => (aspect > 0.0 ? (height_mm * aspect).round(3) : nil) } : nil
            case type
            when 'plan'
                cut = section && section[:normal][2].abs > 0.999 ? (section[:point][2] * NA_SS_INCH_MM).round(3) : nil   # <-- SketchUp z is TrueVision's height
                {
                    'Kind' => 'plan',
                    'CutHeightMm' => cut,
                    'FrameCentreMm' => { 'X' => target_mm[0].round(3), 'Y' => target_mm[2].round(3) },
                    'FrameSizeMm' => frame
                }
            when 'elevation', 'section'
                nx, nz = -dir_m[0], -dir_m[2]
                length = Math.sqrt(nx * nx + nz * nz)
                return nil if length < 1e-9                                       # <-- straight down: no bearing to give it
                nx /= length
                nz /= length
                azimuth = (Math.atan2(nx, -nz) * 180.0 / Math::PI) % 360.0
                rx, rz = nz, -nx
                cutting = type == 'section' && section && section[:facing]
                plane_mm = if cutting
                               point = [section[:point][0] * NA_SS_INCH_MM, section[:point][2] * NA_SS_INCH_MM, -section[:point][1] * NA_SS_INCH_MM]
                               # the plane's point nearest the camera target, so the plane origin sits where the view looks
                               normal = [section[:normal][0], section[:normal][2], -section[:normal][1]]
                               along = (target_mm[0] - point[0]) * normal[0] + (target_mm[1] - point[1]) * normal[1] + (target_mm[2] - point[2]) * normal[2]
                               [target_mm[0] - along * normal[0], target_mm[2] - along * normal[2]]
                           else
                               [target_mm[0], target_mm[2]]
                           end
                {
                    'Kind' => 'elevation',
                    'Mode' => cutting ? 'section' : 'elevation',
                    'AzimuthDeg' => azimuth.round(6),
                    'PlaneOriginMm' => { 'PosX' => plane_mm[0].round(3), 'PosZ' => plane_mm[1].round(3) },
                    'PlaneDistanceMm' => (plane_mm[0] * nx + plane_mm[1] * nz).round(3),
                    'FrameCentreMm' => { 'X' => (target_mm[0] * rx + target_mm[2] * rz).round(3), 'Y' => (-target_mm[1]).round(3) },
                    'FrameSizeMm' => frame
                }
            else
                nil
            end
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | The Store
    # -----------------------------------------------------------------------------

        def self.Na__SceneSync__FolderName
            name = (self.Na__PortalMapper__Config.dig('TrueVisionContent', 'SceneSyncFolderName') rescue nil).to_s
            name.empty? ? NA_SS_FOLDER_DEFAULT : name
        end

        # The store for a linked project, or nil when the project is not on
        # this computer (nothing is ever created under a missing project).
        def self.Na__SceneSync__StorePath(link)
            return nil unless link && link[:linked]
            return nil if self.Na__PortalMapper__MissingProjectMessage(link[:project_root])
            self.Na__PortalMapper__PhaseFolderPath(link[:project_root], self.Na__SceneSync__FolderName)
        end

        # FUNCTION | Read The Manifest (nil when absent or not ours)
        # ---------------------------------------------------------------
        def self.Na__SceneSync__ReadManifest(store_path)
            path = File.join(store_path.to_s, NA_SS_MANIFEST)
            return nil unless File.file?(path)
            data = JSON.parse(File.read(path, encoding: 'bom|utf-8'))
            data.is_a?(Hash) && data['SceneSyncData__Schema'] == NA_SS_MANIFEST_SCHEMA ? data : nil
        rescue JSON::ParserError, StandardError => e
            Na__Log__Warn "[SceneSync] The Scene Sync manifest could not be read: #{e.message}"
            nil
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Will The Manifest's Path Fit SketchUp's 259 Characters?
        # ---------------------------------------------------------------
        def self.na_ss_path_problem(store)
            longest = File.join(store, "#{NA_SS_MANIFEST}.0000.tmp")
            limit = defined?(NA_PC_PATH_LIMIT) ? NA_PC_PATH_LIMIT : 259
            return nil if longest.length <= limit
            "This project's folder path is too long for SketchUp to write the Scene Sync file: #{longest.length} characters, where SketchUp can open #{limit}. " \
            "Shorten the project folder's name, or move the repository to a shorter path."
        end
        # ---------------------------------------------------------------

        # FUNCTION | Write This Model's Scenes Into The Project (quick: nothing renders)
        # ---------------------------------------------------------------
        # Returns { success, message, steps, synced, frozen }. Other models'
        # rows are kept as they are; this model's rows are rewritten: synced
        # scenes refreshed, the rest frozen at their last sync with their state.
        # Nothing is written while no scene of this model was ever switched on.
        # ---------------------------------------------------------------
        def self.Na__SceneSync__Write(model, link)
            steps = []
            settings = self.Na__SceneSync__Settings(model)
            return { success: true, skipped: true, message: 'No scenes are switched on for Scene Sync.', steps: steps, synced: 0, frozen: 0 } if settings['scenes'].empty? && settings['detached'].empty?
            return { success: false, message: settings['problem'] || 'The Scene Sync settings are read only here.', steps: steps, synced: 0, frozen: 0 } if settings['readonly']
            unless link && link[:linked]
                return { success: false, message: 'Link this model to a project on the Project tab first.', steps: steps, synced: 0, frozen: 0 }
            end
            missing = self.Na__PortalMapper__MissingProjectMessage(link[:project_root])
            return { success: false, message: missing, steps: steps, synced: 0, frozen: 0 } if missing
            store = self.Na__SceneSync__StorePath(link)
            too_long = self.na_ss_path_problem(store)
            return { success: false, message: too_long, steps: steps, synced: 0, frozen: 0 } if too_long

            if settings['storeId'].nil?                                             # <-- first sync: give this model its store id
                written = self.Na__SceneSync__WriteSettings(model, settings, 'TrueVision: Scene Sync Store')
                return { success: false, message: written[:message], steps: steps, synced: 0, frozen: 0 } unless written[:success]
                settings = self.Na__SceneSync__Settings(model)
            end
            store_id = settings['storeId']
            existing = self.Na__SceneSync__ReadManifest(store) || {}
            previous = Array(existing['SceneSyncData__Scenes']).each_with_object({}) { |row, hash| hash[row['Scene__Id']] = row if row.is_a?(Hash) }
            pages    = self.na_ss_pages_by_pid(model)
            pcv      = self.na_ss_point_cloud_by_pid(model)
            now      = Time.now.strftime('%Y-%m-%dT%H:%M:%S%z')
            rows     = []
            synced   = 0
            frozen   = 0

            settings['scenes'].each do |entry|
                page = pages[entry['pid']]
                old  = previous[entry['id']]
                if entry['on'] && page
                    captured = self.Na__SceneSync__Capture(model, page, entry)
                    if captured[:problem]
                        steps << { label: page.name.to_s, success: false, message: captured[:problem] }
                        rows << old.merge('Scene__State' => 'synced', 'Scene__Problem' => captured[:problem]) if old   # <-- keeps its last good geometry
                        next
                    end
                    captured['Scene__SourceStoreId']    = store_id
                    captured['Scene__SourceModel']      = model.title.to_s
                    captured['Scene__PointCloudSceneId'] = pcv[entry['pid']]
                    captured['Scene__State']            = 'synced'
                    captured['Scene__SyncedIso']        = old && old['Scene__Revision'] == captured['Scene__Revision'] ? old['Scene__SyncedIso'] : now
                    rows << captured
                    synced += 1
                    steps << { label: page.name.to_s, success: true, message: self.na_ss_summary(captured) }
                elsif old
                    state = page ? 'off' : 'missing'
                    rows << old.merge('Scene__State' => state, 'Scene__Name' => page ? page.name.to_s : old['Scene__Name'])
                    frozen += 1
                end
            end
            settings['detached'].each do |entry|
                old = previous[entry['id']]
                next unless old
                rows << old.merge('Scene__State' => 'detached', 'Scene__DetachedIso' => entry['detachedAt'])
                frozen += 1
            end

            kept_other = previous.values.reject { |row| row['Scene__SourceStoreId'] == store_id }
            manifest = {
                'SceneSyncData__Schema'          => NA_SS_MANIFEST_SCHEMA,
                'SceneSyncData__SchemaVersion'   => NA_SS_MANIFEST_VERSION,
                'SceneSyncData__ExportedIso'     => now,
                'SceneSyncData__ExporterVersion' => NA_SS_EXPORTER_VERSION,
                'SceneSyncData__CoordinateSystem' => {
                    'Units' => 'metres (camera, section), millimetres (drawing)', 'UpAxis' => 'Y',
                    'FromSketchUp' => 'SketchUp inches (x, y, z), Z up, become (x, z, -y) x 0.0254 metres, with no offset: the same as the GLB Builder models.'
                },
                'SceneSyncData__Scenes'          => (rows + kept_other).sort_by { |row| [row['Scene__State'] == 'synced' ? 0 : 1, row['Scene__Name'].to_s.downcase] }
            }
            FileUtils.mkdir_p(store)
            self.Na__PointCloud__WriteJsonAtomic(File.join(store, NA_SS_MANIFEST), manifest)
            message = "Scene Sync: #{synced} scene(s) synced" + (frozen > 0 ? ", #{frozen} kept as last synced (switched off, detached or deleted in SketchUp)." : '.')
            { success: steps.none? { |step| step[:success] == false }, message: message, steps: steps, synced: synced, frozen: frozen }
        rescue => e
            Na__Log__Warn "[SceneSync] Writing the scenes failed: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
            { success: false, message: "Scene Sync: #{e.class}: #{e.message}", steps: steps || [], synced: 0, frozen: 0 }
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Point Cloud Scenes Of This Model, By Page (viewer API 2's pagePid)
        # ---------------------------------------------------------------
        def self.na_ss_point_cloud_by_pid(model)
            return {} unless self.respond_to?(:Na__PointCloud__SceneList)
            list = self.Na__PointCloud__SceneList(model)
            return {} unless list['ok']
            Array(list['scenes']).each_with_object({}) { |row, hash| hash[row['pagePid'].to_i] = row['id'].to_s if row['pagePid'] }
        rescue StandardError
            {}
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | One Line Saying What A Scene Will Be In TrueVision
        # ---------------------------------------------------------------
        def self.na_ss_summary(row)
            drawing = row['Drawing']
            case row['Scene__Type']
            when 'plan'
                cut = drawing && drawing['CutHeightMm'] ? "cut at #{(drawing['CutHeightMm'] / 1000.0).round(3)} m" : 'seen whole from above (no horizontal section plane)'
                "Plan, #{cut}."
            when 'elevation', 'section'
                return 'Looks straight down, so it has no bearing for an elevation. Choose Plan.' unless drawing
                bearing = "azimuth #{format('%.2f', drawing['AzimuthDeg'])} degrees"
                drawing['Mode'] == 'section' ? "Section, #{bearing}, cut by #{row.dig('Section', 'Name').to_s.empty? ? 'its section plane' : row.dig('Section', 'Name')}." : "Elevation, #{bearing}."
            else
                camera = row.dig('Camera', 'ThreeJs') || {}
                camera['FovVerticalDeg'] ? "3D View, #{camera['FovVerticalDeg'].round(1)} degree vertical field of view." : '3D View, parallel projection.'
            end
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Detached in TrueVision
    # -----------------------------------------------------------------------------

        # FUNCTION | The Scene Ids TrueVision Has Made Its Own (Detach in the Layout Editor)
        # ---------------------------------------------------------------
        # Read from the project data on this computer (the Layout Editor's save
        # writes the repository copy as well as R2): a plan, elevation or scene
        # saved with Sync__DetachedFrom 'sketchup'. Cached by the file's time
        # and size, so a status push does not parse megabytes each time. An
        # empty list when the file is missing or unreadable.
        # ---------------------------------------------------------------
        def self.na_ss_detached_in_truevision(link)
            return [] unless link && link[:linked]
            path = File.join(link[:project_root].to_s, self.Na__PortalMapper__ContentFolderName, 'TrueVision__ProjectData__.json')
            return [] unless File.file?(path)
            stamp = [path, File.mtime(path).to_f, File.size(path)]
            @na_ss_detached_cache = nil unless defined?(@na_ss_detached_cache)
            return @na_ss_detached_cache[:ids] if @na_ss_detached_cache && @na_ss_detached_cache[:stamp] == stamp
            data = JSON.parse(File.read(path, encoding: 'bom|utf-8'))
            records = []
            drawings = data['LayoutEditor__DrawingsData']
            if drawings.is_a?(Hash)
                records.concat(Array(drawings['LayoutEditor__DrawingsData__FloorPlans']))
                records.concat(Array(drawings['LayoutEditor__DrawingsData__Elevations']))
            end
            scenes = data['PresentationMode__SavedCameraScenes']
            records.concat(Array(scenes['PresentationMode__SavedCameraScenes__Scenes'])) if scenes.is_a?(Hash)
            ids = records.each_with_object([]) do |record, list|
                next unless record.is_a?(Hash) && record['Sync__DetachedFrom'] == 'sketchup'
                id = record['PresentationMode__Scene__Id'] || record['FloorPlan__Id'] || record['Elevation__Id']
                list << id.to_s if id.to_s =~ NA_SS_ID_PATTERN
            end.uniq
            @na_ss_detached_cache = { stamp: stamp, ids: ids }
            ids
        rescue JSON::ParserError, StandardError => e
            Na__Log__Warn "[SceneSync] The project data could not be read for TrueVision detaches: #{e.message}"
            []
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Tab Status
    # -----------------------------------------------------------------------------

        # FUNCTION | Everything The Scene Sync Tab Shows
        # ---------------------------------------------------------------
        # Every SketchUp scene, in the model's order, with its switch, type,
        # what it will be in TrueVision and how it stands against the project.
        # ---------------------------------------------------------------
        def self.Na__SceneSync__BuildStatus(model = Sketchup.active_model)
            settings = self.Na__SceneSync__Settings(model)
            link     = self.Na__ProjectLink__Read(model)
            store    = self.Na__SceneSync__StorePath(link)
            manifest = store ? self.Na__SceneSync__ReadManifest(store) : nil
            synced_rows = Array(manifest && manifest['SceneSyncData__Scenes']).each_with_object({}) { |row, hash| hash[row['Scene__Id']] = row if row.is_a?(Hash) }
            pcv = self.na_ss_point_cloud_by_pid(model)
            detached_tv = self.na_ss_detached_in_truevision(link)
            by_pid = settings['scenes'].each_with_object({}) { |entry, hash| hash[entry['pid']] = entry }
            detached_pids = settings['detached'].map { |entry| entry['pid'] }

            scenes = (model ? model.pages.to_a : []).map do |page|
                entry = by_pid[page.persistent_id]
                row = {
                    'pid' => page.persistent_id, 'name' => page.name.to_s,
                    'on' => entry ? entry['on'] : false, 'id' => entry ? entry['id'] : nil,
                    'typeChosen' => entry ? entry['type'] : nil,
                    'hasCamera' => page.use_camera?, 'pointCloudSceneId' => pcv[page.persistent_id],
                    'detachedBefore' => detached_pids.include?(page.persistent_id)
                }
                if page.use_camera?
                    section = self.na_ss_section(page, page.camera)
                    row['typeSuggested'] = self.na_ss_suggested_type(page.camera, section)
                    row['type'] = row['typeChosen'] || row['typeSuggested']
                end
                last = entry ? synced_rows[entry['id']] : nil
                if row['on'] && page.use_camera?
                    preview = self.Na__SceneSync__Capture(model, page, entry || { 'id' => 'sus_00000000', 'type' => nil })
                    row['summary']  = preview[:problem] || self.na_ss_summary(preview)
                    row['warnings'] = preview[:problem] ? [preview[:problem]] : Array(preview['Scene__Warnings'])
                    row['syncState'] = last.nil? ? 'notSynced' : (last['Scene__Revision'] == preview['Scene__Revision'] && last['Scene__State'] == 'synced' ? 'upToDate' : 'changed')
                else
                    row['summary']  = page.use_camera? ? '' : 'This scene does not save a camera position, so it cannot be synced.'
                    row['warnings'] = []
                    row['syncState'] = last ? 'frozen' : 'off'
                end
                row['typeLabel'] = NA_SS_TYPE_LABELS[row['type']] if row['type']
                row['syncState'] = 'detachedInTrueVision' if entry && detached_tv.include?(entry['id'])   # <-- TrueVision made it its own: a sync no longer changes it there
                row
            end

            {
                readonly:      settings['readonly'] == true,
                problem:       settings['problem'].to_s,
                projectLinked: link[:linked] == true,
                projectCode:   link[:project_code].to_s,
                storeFolder:   self.Na__SceneSync__FolderName,
                storePath:     store.to_s,
                storeMissingWhy: link[:linked] ? self.Na__PortalMapper__MissingProjectMessage(link[:project_root]).to_s : 'Link this model to a project on the Project tab.',
                storePathProblem: store ? self.na_ss_path_problem(store).to_s : '',
                lastSyncedIso: manifest ? manifest['SceneSyncData__ExportedIso'] : nil,
                scenes:        scenes,
                onCount:       scenes.count { |row| row['on'] },
                frozenCount:   synced_rows.values.count { |row| row['Scene__SourceStoreId'] == settings['storeId'] && row['Scene__State'] != 'synced' },
                types:         NA_SS_TYPES.map { |type| { 'id' => type, 'label' => NA_SS_TYPE_LABELS[type] } }
            }
        rescue => e
            Na__Log__Warn "[SceneSync] The Scene Sync tab status could not be built: #{e.message}"
            { readonly: true, problem: e.message, scenes: [], types: [] }
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

    end
end
