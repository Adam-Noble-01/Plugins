# =============================================================================
# NA POINT CLOUD VIEWER - SCENES - STORE
# =============================================================================
#
# FILE       : Na__PointCloudViewer__Scenes__Store__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__SceneStore
# PURPOSE    : Point cloud scenes: the viewer's settings bound to SketchUp
#              scenes. What a binding is, where it is stored, how it finds its
#              SketchUp scene, and every change the dialog can make to it.
#
# WHERE IT LIVES: ONE JSON string in the model attribute dictionary
#   'Na__PointCloudViewer__Scenes' (key 'json'), our own dictionary on the
#   MODEL. SketchUp's scenes are never written to: no attribute dictionary on a
#   Page, no observer, no rename, no Update Scene, no new or deleted Page. With
#   or without this plugin the .skp opens exactly as it would anyway.
#
# HOW A BINDING FINDS ITS SCENE: by Sketchup::Page#persistent_id (SketchUp
#   2018+). SketchUp keeps it for the life of the scene: renaming, reordering
#   and Update Scene leave it alone, and it survives save and reopen. The
#   scene's NAME is stored only as a hint for the user (shown when the scene has
#   gone, and offered for Relink); it is never used to find anything, so a
#   renamed scene can never break or mislink a binding. A binding whose scene
#   cannot be found is shown as Missing with Relink and Remove. Nothing is ever
#   guessed and nothing on the SketchUp side is ever changed to "repair" it.
#
# NOTHING ON OPEN: read when the dialog, an export, the public API or a pressed
#   SketchUp scene tab (Na__SceneFollow, v0.12.0) asks, never while a model
#   opens. The scene LIST has no observer: the dialog refreshes it when the
#   Scenes tab is shown or the window gains focus.
#
# NEVER CLOBBERED: a record written by a newer version of this plugin
#   (schemaVersion above ours) is shown read-only and never rewritten. Keys this
#   version does not know are carried through every save untouched.
#
# EVERY CLOUD, BY ID (schema 2, v0.10.0): a scene holds the shared point
#   budget and whether the overlay is on ('settings'), and for EVERY cloud of
#   the model, by its permanent cloud id ('clouds'): shown or hidden, its look
#   (dot size, opacity, colour) and its clip box, with its name and file as a
#   hint. Recalling the scene gives each cloud back exactly that; a cloud the
#   scene does not know (added later) is hidden, and the card says so. The
#   picture TrueVision Sync exports draws the clouds the scene shows.
#   A schema 1 scene (v0.9: one cloud) reads as a scene of the model's one
#   cloud, and is written in schema 2 with the model's first change.
#
# =============================================================================

require 'json'
require 'securerandom'

module Na__PointCloudViewer
    module Na__SceneStore

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_DICT           = 'Na__PointCloudViewer__Scenes'.freeze
        NA_KEY            = 'json'.freeze
        NA_SCHEMA         = 'Na__PointCloudViewer__Scenes'.freeze
        NA_SCHEMA_VERSION = 2
        NA_ID_PATTERN     = /\Apcs_[0-9a-f]{8,32}\z/.freeze
        NA_STORE_ID_PATTERN = /\Apcss_[0-9a-f]{8,32}\z/.freeze
        NA_SETTING_KEYS   = %w[pointBudget pointSizePx opacityPercent colourMode].freeze   # schema 1 (one cloud)
        NA_DISPLAY_KEYS   = %w[pointSizePx opacityPercent colourMode].freeze
        NA_MAX_SCENES     = 200

        NA_FALLBACK_VIEW_TYPES = [
            { 'id' => 'plan',      'label' => 'Plan' },
            { 'id' => 'siteplan',  'label' => 'Site Plan' },
            { 'id' => 'elevation', 'label' => 'Elevation' },
            { 'id' => 'section',   'label' => 'Section' },
            { 'id' => 'view3d',    'label' => '3D View' }
        ].freeze

        NA_FALLBACK_SCALES = [
            { 'denominator' => 10,   'pointSizePx' => 10 },
            { 'denominator' => 20,   'pointSizePx' => 6 },
            { 'denominator' => 50,   'pointSizePx' => 3 },
            { 'denominator' => 100,  'pointSizePx' => 2 },
            { 'denominator' => 200,  'pointSizePx' => 1 },
            { 'denominator' => 500,  'pointSizePx' => 1 },
            { 'denominator' => 1250, 'pointSizePx' => 1 },
            { 'denominator' => 2500, 'pointSizePx' => 1 }
        ].freeze

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Config (view types, scales, image widths)
    # -------------------------------------------------------------------------

        def self.Na__Scenes__Config(*keys)
            Na__ConfigLoader.Na__Config__GetOr(nil, 'scenes', *keys)
        end

        def self.Na__Scenes__ViewTypes
            list = self.Na__Scenes__Config('viewTypes')
            list = NA_FALLBACK_VIEW_TYPES unless list.is_a?(Array) && !list.empty?
            list.select { |type| type.is_a?(Hash) && type['id'].is_a?(String) }
        end

        def self.Na__Scenes__ViewTypeLabel(type_id)
            found = self.Na__Scenes__ViewTypes.find { |type| type['id'] == type_id.to_s }
            found ? found['label'].to_s : type_id.to_s
        end

        def self.Na__Scenes__ScalePresets
            list = self.Na__Scenes__Config('scalePresets')
            list = NA_FALLBACK_SCALES unless list.is_a?(Array) && !list.empty?
            list.select { |preset| preset.is_a?(Hash) && preset['denominator'].to_f > 0 }
                .map { |preset| { 'denominator' => preset['denominator'], 'pointSizePx' => [preset['pointSizePx'].to_i, 1].max,
                                  'label' => self.Na__Scenes__ScaleLabel(preset['denominator']) } }
        end

        def self.Na__Scenes__ImageWidthPresets
            list = self.Na__Scenes__Config('imageWidthPresets')
            list = [2000, 3000, 4000, 6000, 8000] unless list.is_a?(Array) && !list.empty?
            list.map(&:to_i).select(&:positive?)
        end

        # "1:50", "1:1250", "1:2.5"
        def self.Na__Scenes__ScaleLabel(denominator)
            value = denominator.to_f
            text = value == value.round ? value.round.to_s : Na__UnitContract.Na__Units__TrimNumber(value, 3)
            "1:#{text}"
        end

        # The opacity TrueVision starts the scene's picture at: the highest of
        # the clouds the scene shows (the picture itself is baked at 100 %).
        def self.Na__Scenes__DefaultOpacity(scene)
            shown = (scene['clouds'] || {}).values.select { |entry| entry['visible'] != false }
            values = shown.map { |entry| (entry['display'] || {})['opacityPercent'].to_i }.select(&:positive?)
            values.empty? ? 100 : values.max
        end

        # The dot size an export bakes in: the scene's own choice, else the
        # scale preset's, else round(factor / denominator). Perspective scenes
        # have no scale and use their own default.
        def self.Na__Scenes__ExportPointSize(scene, perspective)
            max = (self.Na__Scenes__Config('exportPointSizeMaxPx') || 32).to_i
            chosen = scene.dig('export', 'pointSizePx')
            return [[chosen.to_i, 1].max, max].min if chosen
            return [[(self.Na__Scenes__Config('perspectivePointSizePx') || 2).to_i, 1].max, max].min if perspective
            denominator = (scene.dig('export', 'scale') || self.Na__Scenes__Config('defaultScale') || 50).to_f
            preset = self.Na__Scenes__ScalePresets.find { |item| (item['denominator'].to_f - denominator).abs < 1e-9 }
            return [[preset['pointSizePx'], 1].max, max].min if preset
            factor = (self.Na__Scenes__Config('customPointSizeFactor') || 150).to_f
            [[(factor / denominator).round, 1].max, max].min
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Load + Save (model attribute dictionary)
    # -------------------------------------------------------------------------

        def self.Na__Scenes__Ensure(session)
            return if session.scenes_loaded
            self.Na__Scenes__Load(session)
        end

        # The cloud a schema 1 scene (one cloud, v0.9) belongs to: the model's
        # v0.9 cloud (its id comes from the old link id, before and after the
        # model is converted), else the first cloud, else nil.
        def self.na_v1_cloud_id(session)
            slots = Na__CloudSet.Na__Slots__All(session)
            index = session.store_index
            migrated = index.is_a?(Hash) && index['migratedFrom'].is_a?(Hash) ? index['migratedFrom']['cloudId'] : nil
            return migrated if migrated && slots.any? { |slot| slot.id == migrated }
            legacy = slots.find { |slot| slot.record_state == 'legacy' }
            (legacy || slots.first) ? (legacy || slots.first).id : nil
        end

        # Never raises: a record that cannot be read is ignored with a log line
        # and the tab says so (the escape hatch is Remove Point Cloud Data).
        def self.Na__Scenes__Load(session)
            session.scenes_loaded   = true
            session.scenes          = []
            session.scenes_meta     = { 'storeId' => nil, 'revision' => 0, 'extra' => {} }
            session.scenes_problem  = nil
            session.scenes_readonly = false
            raw = session.model ? session.model.get_attribute(NA_DICT, NA_KEY) : nil
            return unless raw.is_a?(String) && !raw.empty?
            data = JSON.parse(raw)
            unless data.is_a?(Hash) && data['schema'] == NA_SCHEMA
                session.scenes_problem = 'The saved point cloud scenes could not be read, so they are not shown. Nothing has been changed.'
                session.scenes_readonly = true
                return
            end
            if data['schemaVersion'].to_i > NA_SCHEMA_VERSION
                session.scenes_problem = 'These point cloud scenes were saved by a newer version of the viewer. They are shown read-only so nothing it saved is lost.'
                session.scenes_readonly = true
            end
            store_id = data['storeId'].to_s
            session.scenes_meta = {
                'storeId'  => store_id.match?(NA_STORE_ID_PATTERN) ? store_id : nil,
                'revision' => data['revision'].to_i,
                'schemaVersion' => data['schemaVersion'].to_i,
                'extra'    => data.reject { |key, _| %w[schema schemaVersion storeId revision updatedAt updatedEpoch scenes].include?(key) }
            }
            v1_cloud = data['schemaVersion'].to_i <= 1 ? self.na_v1_cloud_id(session) : nil
            seen = {}
            Array(data['scenes']).each do |raw_scene|
                scene = self.na_valid_scene(raw_scene, v1_cloud)
                next unless scene && !seen[scene['id']]
                seen[scene['id']] = true
                session.scenes << scene
            end
        rescue JSON::ParserError => error
            session.scenes_problem = 'The saved point cloud scenes could not be read, so they are not shown. Nothing has been changed.'
            session.scenes_readonly = true
            Na__DebugTools.Na__Debug__Warn("Stored point cloud scenes could not be read and were ignored: #{error.message}")
        end

        # One undoable operation per committed change. Returns nil, or a plain
        # reason nothing was written. A model saved before v0.10.0 takes the
        # new form of every record inside the same operation.
        def self.Na__Scenes__Save(session, operation_name)
            model = session.model
            return 'There is no model.' unless model
            return session.scenes_problem || 'These scenes are read-only.' if session.scenes_readonly
            return Na__CloudStore.na_readonly_text if session.store_readonly
            now = Time.now
            data, meta = self.na_record(session, now)
            migrated = nil
            begin
                model.start_operation(operation_name, true)
                migrated = Na__CloudStore.Na__Store__MigrateInOperation(session, now)
                model.set_attribute(NA_DICT, NA_KEY, JSON.generate(data))
                model.commit_operation
            rescue StandardError
                model.abort_operation
                raise
            end
            Na__CloudStore.Na__Store__AfterMigration(session, migrated)
            session.scenes_meta = meta
            Na__LocalBackup.Na__Backup__AfterSave(model, session)
            nil
        end

        # [the record to write, the meta it leaves] for the scenes held now.
        def self.na_record(session, now)
            meta = Marshal.load(Marshal.dump(session.scenes_meta || {}))
            meta['storeId'] ||= "pcss_#{SecureRandom.hex(6)}"
            meta['revision'] = meta['revision'].to_i + 1
            meta['schemaVersion'] = NA_SCHEMA_VERSION
            data = (meta['extra'] || {}).merge(
                'schema'        => NA_SCHEMA,
                'schemaVersion' => NA_SCHEMA_VERSION,
                'storeId'       => meta['storeId'],
                'revision'      => meta['revision'],
                'updatedAt'     => now.strftime('%Y-%m-%dT%H:%M:%S%z'),
                'updatedEpoch'  => now.to_f,
                'scenes'        => session.scenes
            )
            [data, meta]
        end

        # Inside the operation that converts a v0.9 model (Na__CloudStore): a
        # schema 1 record is written again in schema 2. Returns the meta to
        # keep once the operation commits, or nil when there is nothing to do.
        def self.Na__Scenes__MigrateInOperation(session, now)
            self.Na__Scenes__Ensure(session)
            return nil if session.scenes_readonly
            return nil unless session.model.get_attribute(NA_DICT, NA_KEY).is_a?(String)
            return nil if (session.scenes_meta || {})['schemaVersion'].to_i >= NA_SCHEMA_VERSION
            data, meta = self.na_record(session, now)
            session.model.set_attribute(NA_DICT, NA_KEY, JSON.generate(data))
            meta
        end

        def self.Na__Scenes__AfterMigration(session, meta)
            session.scenes_meta = meta if meta
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | SketchUp Scenes (read only)
    # -------------------------------------------------------------------------

        # Never 0 for a real scene on SketchUp 2018+; 0 means "cannot bind".
        def self.Na__Scenes__PagePid(page)
            page.persistent_id.to_i
        rescue StandardError
            0
        end

        def self.Na__Scenes__FindPage(model, pid)
            wanted = pid.to_i
            return nil unless model && wanted > 0
            model.pages.each { |page| return page if self.Na__Scenes__PagePid(page) == wanted }
            nil
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Warn("SketchUp scenes could not be searched: #{error.message}")
            nil
        end

        def self.Na__Scenes__ResolvePage(model, scene)
            self.Na__Scenes__FindPage(model, scene.dig('page', 'pid'))
        end

        # Plain facts about one SketchUp scene. page.camera is only meaningful
        # when the scene saves a camera, so the flag travels with it.
        def self.Na__Scenes__PageInfo(page, index)
            camera = page.camera
            {
                'pid'         => self.Na__Scenes__PagePid(page),
                'name'        => page.name.to_s,
                'index'       => index,
                'usesCamera'  => page.use_camera? ? true : false,
                'perspective' => camera && camera.perspective? ? true : false,
                'direction'   => camera ? camera.direction.to_a.map(&:to_f) : nil
            }
        rescue StandardError
            { 'pid' => self.Na__Scenes__PagePid(page), 'name' => page.name.to_s, 'index' => index,
              'usesCamera' => false, 'perspective' => false, 'direction' => nil }
        end

        def self.Na__Scenes__AllPages(model)
            return [] unless model
            list = []
            model.pages.each_with_index { |page, index| list << self.Na__Scenes__PageInfo(page, index) }
            list
        rescue StandardError
            []
        end

        def self.Na__Scenes__SelectedPagePid(model)
            page = model ? model.pages.selected_page : nil
            page ? self.Na__Scenes__PagePid(page) : 0
        rescue StandardError
            0
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Capture (what a binding remembers)
    # -------------------------------------------------------------------------

        # The viewer's current state, as a scene stores it: the shared budget
        # and the overlay switch, then every cloud of the model by its id.
        def self.Na__Scenes__Capture(session, view)
            clouds = Na__CloudSet.Na__Slots__All(session).each_with_object({}) do |slot, hash|
                hash[slot.id] = self.na_capture_cloud(slot)
            end
            {
                'settings' => { 'pointBudget' => session.settings['pointBudget'].to_i,
                                'overlayOn'   => Na__ModelRegistry.Na__Registry__IsVisible? },
                'clouds'   => clouds,
                'view'     => { 'aspect' => self.na_view_aspect(view) }
            }
        end

        def self.na_capture_cloud(slot)
            Na__ClipBox.Na__Clip__Ensure(slot)
            clip = slot.clip ? { 'enabled' => slot.clip['enabled'] ? true : false,
                                 'min' => slot.clip['min'].map(&:to_f), 'max' => slot.clip['max'].map(&:to_f) } : nil
            link = slot.record ? slot.record['link'] : nil
            {
                'visible'  => slot.visible ? true : false,
                'display'  => Na__RenderSettings.Na__Settings__MergeDisplay(slot.display, {}),
                'clip'     => clip,
                'identity' => { 'name' => slot.name, 'fileName' => link ? link['fileName'] : (slot.cloud ? slot.cloud.label : nil),
                                'contentKey' => link ? link['contentKey'] : nil, 'fingerprint' => link ? link['fingerprint'] : nil }
            }
        end

        # True when the viewer shows something other than what the scene holds.
        def self.Na__Scenes__Differs?(session, scene, view)
            now = self.Na__Scenes__Capture(session, view)
            return true if now['settings']['pointBudget'] != scene.dig('settings', 'pointBudget').to_i
            return true if now['settings']['overlayOn'] != (scene.dig('settings', 'overlayOn') != false)
            saved = scene['clouds'] || {}
            now['clouds'].any? do |id, current|
                entry = saved[id]
                next current['visible'] unless entry           # a cloud the scene does not know shows now
                next true if current['visible'] != entry['visible']
                next true if NA_DISPLAY_KEYS.any? { |key| current['display'][key] != (entry['display'] || {})[key] }
                !self.na_same_clip?(current['clip'], entry['clip'])
            end
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Changes (each one undoable; nil = done, String = why not)
    # -------------------------------------------------------------------------

        def self.Na__Scenes__Add(session, pid, view)
            self.Na__Scenes__Ensure(session)
            return session.scenes_problem if session.scenes_readonly
            return "There is a limit of #{NA_MAX_SCENES} point cloud scenes." if session.scenes.length >= NA_MAX_SCENES
            page = self.Na__Scenes__FindPage(session.model, pid)
            return 'That SketchUp scene no longer exists. Pick another one.' unless page
            return "#{page.name} already has point cloud settings." if self.Na__Scenes__ForPid(session, pid)
            info = self.Na__Scenes__PageInfo(page, self.na_page_index(session.model, page))
            now = Time.now
            scene = {
                'id'        => self.na_new_id(session),
                'page'      => { 'pid' => info['pid'], 'name' => info['name'], 'index' => info['index'] },
                'viewType'  => self.na_suggest_view_type(info),
                'export'    => { 'scale' => info['perspective'] ? nil : (self.Na__Scenes__Config('defaultScale') || 50),
                                 'imageWidthPx' => info['perspective'] ? (self.Na__Scenes__Config('defaultImageWidthPx') || 4000).to_i : nil,
                                 'pointSizePx' => nil },
                'createdAt' => now.strftime('%Y-%m-%dT%H:%M:%S%z')
            }.merge(self.na_stamp(self.Na__Scenes__Capture(session, view), now))
            session.scenes << scene
            problem = self.na_save_or_undo(session, "Point Cloud: Add Scene #{info['name']}") { session.scenes.delete(scene) }
            session.scene_active_id = scene['id'] unless problem
            problem
        end

        # The viewer's current state replaces what the scene holds. The
        # SketchUp scene itself is not touched (Update Scene is SketchUp's).
        def self.Na__Scenes__Update(session, scene_id, view)
            scene = self.Na__Scenes__Find(session, scene_id)
            return 'That point cloud scene no longer exists.' unless scene
            before = Marshal.load(Marshal.dump(scene))
            scene.merge!(self.na_stamp(self.Na__Scenes__Capture(session, view), Time.now))
            self.na_refresh_page_hint(session, scene)
            problem = self.na_save_or_undo(session, "Point Cloud: Update Scene #{self.Na__Scenes__DisplayName(session, scene)}") { scene.replace(before) }
            session.scene_active_id = scene['id'] unless problem
            problem
        end

        # Our record only. The SketchUp scene stays exactly as it is.
        def self.Na__Scenes__Remove(session, scene_id)
            scene = self.Na__Scenes__Find(session, scene_id)
            return 'That point cloud scene no longer exists.' unless scene
            index = session.scenes.index(scene)
            session.scenes.delete(scene)
            problem = self.na_save_or_undo(session, "Point Cloud: Remove Scene #{self.Na__Scenes__DisplayName(session, scene)}") { session.scenes.insert(index, scene) }
            session.scene_active_id = nil if !problem && session.scene_active_id == scene_id
            problem
        end

        # Drag to reorder (the Scenes tab, or TrueVision Sync through the public
        # API): ids is every scene id, top to bottom. Only the order changes,
        # as one undoable step. A list that no longer matches the scenes (one
        # added or removed meanwhile) changes nothing.
        def self.Na__Scenes__Reorder(session, ids)
            self.Na__Scenes__Ensure(session)
            return session.scenes_problem || 'These scenes are read-only.' if session.scenes_readonly
            wanted  = Array(ids).map(&:to_s)
            current = session.scenes.map { |scene| scene['id'] }
            return 'The point cloud scenes changed while you were moving one, so nothing was moved. Try again.' unless wanted.sort == current.sort && wanted.uniq.length == wanted.length
            return nil if wanted == current
            before = session.scenes.dup
            by_id  = before.each_with_object({}) { |scene, hash| hash[scene['id']] = scene }
            session.scenes.replace(wanted.map { |id| by_id[id] })
            self.na_save_or_undo(session, 'Point Cloud: Reorder Scenes') { session.scenes.replace(before) }
        end

        # Points a binding at another SketchUp scene (typically after its own
        # scene was deleted). The new scene must not have settings already.
        def self.Na__Scenes__Relink(session, scene_id, pid)
            scene = self.Na__Scenes__Find(session, scene_id)
            return 'That point cloud scene no longer exists.' unless scene
            page = self.Na__Scenes__FindPage(session.model, pid)
            return 'That SketchUp scene no longer exists. Pick another one.' unless page
            other = self.Na__Scenes__ForPid(session, pid)
            return "#{page.name} already has point cloud settings." if other && other['id'] != scene['id']
            before = Marshal.load(Marshal.dump(scene['page']))
            scene['page'] = { 'pid' => self.Na__Scenes__PagePid(page), 'name' => page.name.to_s,
                              'index' => self.na_page_index(session.model, page) }
            self.na_save_or_undo(session, "Point Cloud: Relink Scene #{page.name}") { scene['page'] = before }
        end

        # values: any of viewType, scale (denominator or nil), imageWidthPx,
        # pointSizePx (nil = automatic).
        def self.Na__Scenes__SetExport(session, scene_id, values)
            scene = self.Na__Scenes__Find(session, scene_id)
            return 'That point cloud scene no longer exists.' unless scene
            before = Marshal.load(Marshal.dump(scene))
            if values.key?('viewType')
                type = values['viewType'].to_s
                return 'Unknown view type.' unless self.Na__Scenes__ViewTypes.any? { |item| item['id'] == type }
                scene['viewType'] = type
            end
            scene['export'] ||= {}
            if values.key?('scale')
                scale = self.na_valid_scale(values['scale'])
                return "Enter a scale between 1:#{self.na_scale_min} and 1:#{self.na_scale_max}." if values['scale'] && !scale
                scene['export']['scale'] = scale
            end
            if values.key?('imageWidthPx')
                width = values['imageWidthPx'].nil? ? nil : values['imageWidthPx'].to_i
                return 'Enter an image width between 500 and 30000 pixels.' if width && !(500..30_000).cover?(width)
                scene['export']['imageWidthPx'] = width
            end
            if values.key?('pointSizePx')
                raw = values['pointSizePx']
                size = raw.nil? || raw.to_s.strip.empty? ? nil : raw.to_i
                max = (self.Na__Scenes__Config('exportPointSizeMaxPx') || 32).to_i
                return "Enter a point size between 1 and #{max} pixels, or leave it on Auto." if size && !(1..max).cover?(size)
                scene['export']['pointSizePx'] = size
            end
            return nil if scene == before
            self.na_save_or_undo(session, "Point Cloud: Scene Export Settings #{self.Na__Scenes__DisplayName(session, scene)}") { scene.replace(before) }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Lookup
    # -------------------------------------------------------------------------

        def self.Na__Scenes__Find(session, scene_id)
            self.Na__Scenes__Ensure(session)
            session.scenes.find { |scene| scene['id'] == scene_id.to_s }
        end

        def self.Na__Scenes__ForPid(session, pid)
            self.Na__Scenes__Ensure(session)
            wanted = pid.to_i
            session.scenes.find { |scene| scene.dig('page', 'pid').to_i == wanted }
        end

        # The SketchUp scene's live name, else the last name we saw.
        def self.Na__Scenes__DisplayName(session, scene)
            page = self.Na__Scenes__ResolvePage(session.model, scene)
            page ? page.name.to_s : scene.dig('page', 'name').to_s
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals
    # -------------------------------------------------------------------------

        # Saves; if the save raises, the in-memory change is put back first so
        # memory never runs ahead of the model.
        def self.na_save_or_undo(session, operation_name)
            problem = self.Na__Scenes__Save(session, operation_name)
            yield if problem && block_given?
            problem
        rescue StandardError
            yield if block_given?
            raise
        end

        def self.na_stamp(capture, now)
            capture.merge('updatedAt' => now.strftime('%Y-%m-%dT%H:%M:%S%z'), 'updatedEpoch' => now.to_f)
        end

        def self.na_refresh_page_hint(session, scene)
            page = self.Na__Scenes__ResolvePage(session.model, scene)
            return unless page
            scene['page'] = scene['page'].merge('name' => page.name.to_s, 'index' => self.na_page_index(session.model, page))
        end

        def self.na_page_index(model, page)
            model.pages.to_a.index(page) || 0
        rescue StandardError
            0
        end

        def self.na_new_id(session)
            used = session.scenes.map { |scene| scene['id'] }
            loop do
                id = "pcs_#{SecureRandom.hex(4)}"
                return id unless used.include?(id)
            end
        end

        # A parallel scene looking straight down is a plan; one looking level is
        # an elevation; a perspective scene is a 3D view. Only a suggestion: the
        # user picks the type.
        def self.na_suggest_view_type(info)
            return 'view3d' if info['perspective']
            dz = info['direction'] ? info['direction'][2].to_f : 0.0
            return 'plan' if dz < -0.99
            return 'elevation' if dz.abs < 0.01
            'view3d'
        end

        def self.na_view_aspect(view)
            camera = view.camera
            return camera.aspect_ratio.to_f if camera.aspect_ratio.to_f > 0.0
            height = view.vpheight.to_f
            height > 0 ? view.vpwidth.to_f / height : 1.0
        rescue StandardError
            1.0
        end

        def self.na_same_clip?(a, b)
            return a.nil? && b.nil? if a.nil? || b.nil?
            return false unless (a['enabled'] ? true : false) == (b['enabled'] ? true : false)
            (0..2).all? { |i| (a['min'][i] - b['min'][i]).abs < 1e-6 && (a['max'][i] - b['max'][i]).abs < 1e-6 }
        end

        def self.na_scale_min
            (self.Na__Scenes__Config('customScaleMin') || 1).to_f
        end

        def self.na_scale_max
            (self.Na__Scenes__Config('customScaleMax') || 5000).to_f
        end

        def self.na_valid_scale(raw)
            return nil if raw.nil?
            value = Float(raw.to_s.sub(/\A\s*1\s*:\s*/, ''))
            return nil unless value.finite? && value >= self.na_scale_min && value <= self.na_scale_max
            value == value.round ? value.round : value.round(3)
        rescue ArgumentError, TypeError
            nil
        end

        # Validates one stored scene; unknown keys are carried through.
        # v1_cloud: the cloud id a schema 1 scene (one cloud) belongs to, or nil
        # for a schema 2 record.
        def self.na_valid_scene(raw, v1_cloud = nil)
            return nil unless raw.is_a?(Hash) && raw['id'].is_a?(String) && raw['id'].match?(NA_ID_PATTERN)
            page = raw['page']
            return nil unless page.is_a?(Hash) && page['pid'].to_i > 0
            scene = Marshal.load(Marshal.dump(raw))
            scene = self.na_scene_from_v1(scene, v1_cloud) unless scene['clouds'].is_a?(Hash)
            scene['page'] = page.merge('pid' => page['pid'].to_i, 'name' => page['name'].to_s[0, 200], 'index' => page['index'].to_i)
            scene['viewType'] = 'view3d' unless self.Na__Scenes__ViewTypes.any? { |type| type['id'] == scene['viewType'] }
            export = scene['export'].is_a?(Hash) ? scene['export'] : {}
            scene['export'] = export.merge(
                'scale'        => self.na_valid_scale(export['scale']),
                'imageWidthPx' => export['imageWidthPx'] ? export['imageWidthPx'].to_i : nil,
                'pointSizePx'  => export['pointSizePx'] ? export['pointSizePx'].to_i : nil
            )
            stored = scene['settings'].is_a?(Hash) ? scene['settings'] : {}
            budget = Na__RenderSettings.Na__Settings__Merge(Na__RenderSettings.Na__Settings__Defaults, stored.slice('pointBudget'))['pointBudget']
            scene['settings'] = stored.merge('pointBudget' => budget, 'overlayOn' => stored['overlayOn'] != false)
            scene['clouds'] = scene['clouds'].each_with_object({}) do |(id, entry), out|
                next unless id.to_s.match?(Na__CloudStore::NA_ID_PATTERN) && entry.is_a?(Hash)
                out[id.to_s] = entry.merge(
                    'visible'  => entry['visible'] != false,
                    'display'  => Na__RenderSettings.Na__Settings__MergeDisplay(entry['display'], {}),
                    'clip'     => self.na_valid_clip(entry['clip']),
                    'identity' => entry['identity'].is_a?(Hash) ? entry['identity'] : {}
                )
            end
            aspect = scene.dig('view', 'aspect').to_f
            scene['view'] = (scene['view'].is_a?(Hash) ? scene['view'] : {}).merge('aspect' => aspect > 0.05 && aspect < 20 ? aspect : 1.0)
            scene
        rescue StandardError
            nil
        end

        # A schema 1 scene (v0.9: one cloud's settings, visibility and clip box)
        # as a schema 2 scene of that one cloud. The cloud was always drawn in
        # its exported picture; 'visible' was the overlay switch.
        def self.na_scene_from_v1(scene, cloud_id)
            settings = scene['settings'].is_a?(Hash) ? scene['settings'] : {}
            merged = Na__RenderSettings.Na__Settings__Merge(Na__RenderSettings.Na__Settings__Defaults, settings)
            entry = {
                'visible'  => true,
                'display'  => Na__RenderSettings.Na__Settings__DisplayPart(merged),
                'clip'     => scene['clip'],
                'identity' => scene['cloud'].is_a?(Hash) ? scene['cloud'] : {}
            }
            scene.reject { |key, _| %w[settings clip cloud].include?(key) }.merge(
                'settings' => { 'pointBudget' => merged['pointBudget'], 'overlayOn' => settings['visible'] != false },
                'clouds'   => cloud_id ? { cloud_id => entry } : {}
            )
        end

        def self.na_valid_clip(raw)
            return nil unless raw.is_a?(Hash)
            min = Array(raw['min']).map { |v| Float(v) }
            max = Array(raw['max']).map { |v| Float(v) }
            return nil unless min.length == 3 && max.length == 3 && (0..2).all? { |i| max[i] > min[i] }
            { 'enabled' => raw['enabled'] ? true : false, 'min' => min, 'max' => max }
        rescue ArgumentError, TypeError
            nil
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
