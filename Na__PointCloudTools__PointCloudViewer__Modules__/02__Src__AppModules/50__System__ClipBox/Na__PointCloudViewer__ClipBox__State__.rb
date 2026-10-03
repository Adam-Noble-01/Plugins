# =============================================================================
# NA POINT CLOUD VIEWER - CLIP BOX - STATE
# =============================================================================
#
# FILE       : Na__PointCloudViewer__ClipBox__State__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__ClipBox
# PURPOSE    : The clip box and the saved clip scenes: what they are, how
#              they are stored, and every change the dialog or the edit tool
#              can make to them.
#
# WHAT CLIPPING IS: six limits in MODEL coordinates (left/right = x,
#   front/back = y, bottom/top = z). Points outside are simply not drawn. The
#   LAS and the engine's copy of the points are never touched.
#
# WHERE IT LIVES: JSON in the model's attribute dictionary
#   'Na__PointCloudViewer__ClipState' (a few hundred bytes), so the clip box
#   and its scenes travel with the .skp to any computer. Each committed change
#   is one named, undoable operation; Undo/Redo re-read it (ModelRegistry).
#   No point data is ever stored here.
#
# =============================================================================

module Na__PointCloudViewer
    module Na__ClipBox

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_DICT           = 'Na__PointCloudViewer__ClipState'.freeze
        NA_KEY            = 'json'.freeze
        NA_SCHEMA         = 'Na__PointCloudViewer__ClipState'.freeze
        NA_SCHEMA_VERSION = 1
        NA_FULL_CLOUD_ID  = 'full'.freeze
        NA_MIN_GAP_INCHES = 0.5

        NA_FACES = [
            { 'id' => 'left',   'label' => 'Left',   'axis' => 0, 'side' => 'min' },
            { 'id' => 'right',  'label' => 'Right',  'axis' => 0, 'side' => 'max' },
            { 'id' => 'front',  'label' => 'Front',  'axis' => 1, 'side' => 'min' },
            { 'id' => 'back',   'label' => 'Back',   'axis' => 1, 'side' => 'max' },
            { 'id' => 'bottom', 'label' => 'Bottom', 'axis' => 2, 'side' => 'min' },
            { 'id' => 'top',    'label' => 'Top',    'axis' => 2, 'side' => 'max' }
        ].freeze

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Read (used by the renderer every frame, so keep it cheap)
    # -------------------------------------------------------------------------

        def self.Na__Clip__IsActive?(session)
            self.Na__Clip__Ensure(session)
            clip = session.clip
            clip && clip['enabled'] ? true : false
        end

        # Appended to the native render parameters.
        def self.Na__Clip__RenderParams(session)
            return [0, 0, 0, 0, 0, 0, 0] unless self.Na__Clip__IsActive?(session)
            [1] + session.clip['min'] + session.clip['max']
        end

        # Part of the image renderer's cache key: any change re-renders.
        def self.Na__Clip__Key(session)
            self.Na__Clip__IsActive?(session) ? (session.clip['min'] + session.clip['max']) : nil
        end

        def self.Na__Clip__Face(face_id)
            NA_FACES.find { |face| face['id'] == face_id.to_s }
        end

        def self.Na__Clip__FaceValue(session, face)
            session.clip[face['side']][face['axis']]
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Load + Save (model attribute dictionary)
    # -------------------------------------------------------------------------

        def self.Na__Clip__Ensure(session)
            return if session.clip_loaded
            self.Na__Clip__Load(session)
        end

        def self.Na__Clip__Load(session)
            session.clip_loaded = true
            session.clip, session.clip_scenes, session.clip_active_scene = nil, [], nil
            raw = session.model ? session.model.get_attribute(NA_DICT, NA_KEY) : nil
            return unless raw.is_a?(String) && !raw.empty?
            data = JSON.parse(raw)
            return unless data.is_a?(Hash) && data['schema'] == NA_SCHEMA && data['schemaVersion'].to_i <= NA_SCHEMA_VERSION
            session.clip              = self.na_valid_box(data['clip'], data.dig('clip', 'enabled') == true)
            session.clip_scenes       = Array(data['scenes']).map { |scene| self.na_valid_scene(scene) }.compact
            session.clip_active_scene = data['activeScene'].is_a?(String) ? data['activeScene'] : nil
        rescue JSON::ParserError => error
            Na__DebugTools.Na__Debug__Warn("Stored clip state could not be read and was ignored: #{error.message}")
        end

        # One undoable operation per committed change.
        def self.Na__Clip__Save(session, operation_name)
            model = session.model
            return unless model
            now = Time.now
            data = {
                'schema'        => NA_SCHEMA,
                'schemaVersion' => NA_SCHEMA_VERSION,
                'updatedAt'     => now.strftime('%Y-%m-%dT%H:%M:%S%z'),
                'updatedEpoch'  => now.to_f,
                'clip'          => session.clip,
                'scenes'        => session.clip_scenes,
                'activeScene'   => session.clip_active_scene
            }
            begin
                model.start_operation(operation_name, true)
                model.set_attribute(NA_DICT, NA_KEY, JSON.generate(data))
                model.commit_operation
            rescue StandardError
                model.abort_operation
                raise
            end
            Na__LocalBackup.Na__Backup__AfterSave(model, session)
        end

        # Undo / Redo: see Na__ModelRegistry.Na__Registry__ReloadModelState, which
        # re-reads this and the cloud placement together.
        def self.Na__Clip__ReloadFromModel(model)
            Na__ModelRegistry.Na__Registry__ReloadModelState(model)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Box Changes
    # -------------------------------------------------------------------------

        def self.Na__Clip__SetEnabled(session, enabled)
            self.Na__Clip__Ensure(session)
            unless session.clip
                return 'Import a point cloud first: the clip box starts at the cloud\'s bounds.' unless session.cloud
                session.clip = self.na_cloud_box(session)
            end
            session.clip['enabled'] = enabled ? true : false
            self.Na__Clip__Save(session, enabled ? 'Point Cloud: Clip On' : 'Point Cloud: Clip Off')
            nil
        end

        def self.Na__Clip__ResetToCloud(session)
            self.Na__Clip__Ensure(session)
            return 'Import a point cloud first: there are no bounds to reset to.' unless session.cloud
            session.clip = self.na_cloud_box(session)
            self.Na__Clip__Save(session, 'Point Cloud: Reset Clip Box')
            nil
        end

        # values: { 'left' => '3500', 'top' => '2.4m', ... } in the model's display
        # unit. Returns nil or a plain-English reason nothing changed.
        def self.Na__Clip__SetLimits(session, values, display)
            self.Na__Clip__Ensure(session)
            return 'There is no clip box yet. Turn clipping on or press Edit Clip Box first.' unless session.clip
            box = { 'enabled' => session.clip['enabled'], 'min' => session.clip['min'].dup, 'max' => session.clip['max'].dup }
            values.each do |face_id, text|
                face = self.Na__Clip__Face(face_id)
                next unless face
                box[face['side']][face['axis']] = Na__UnitContract.Na__Units__ParseDisplayLength(text, display)
            end
            3.times do |axis|
                if box['max'][axis] - box['min'][axis] < NA_MIN_GAP_INCHES
                    return "#{%w[Left Front Bottom][axis]} must be below #{%w[Right Back Top][axis]}."
                end
            end
            session.clip = box
            self.Na__Clip__Save(session, 'Point Cloud: Clip Limits')
            nil
        rescue ArgumentError => error
            error.message
        end

        # Live, unsaved change from the edit tool (one face). Keeps the box valid.
        def self.Na__Clip__SetFaceLive(session, face, value)
            axis = face['axis']
            value = if face['side'] == 'min'
                        [value, session.clip['max'][axis] - NA_MIN_GAP_INCHES].min
                    else
                        [value, session.clip['min'][axis] + NA_MIN_GAP_INCHES].max
                    end
            session.clip[face['side']][axis] = value
            value
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Clip Scenes
    # -------------------------------------------------------------------------

        def self.Na__Clip__SceneSave(session, name)
            self.Na__Clip__Ensure(session)
            return 'There is no clip box to save yet.' unless session.clip
            scene = { 'id' => self.na_new_scene_id(session), 'name' => self.na_scene_name(session, name) }.merge(self.na_box_copy(session.clip))
            session.clip_scenes << scene
            session.clip['enabled'] = true
            session.clip_active_scene = scene['id']
            self.Na__Clip__Save(session, 'Point Cloud: Save Clip Scene')
            nil
        end

        def self.Na__Clip__SceneUpdate(session, scene_id)
            scene = self.na_scene(session, scene_id)
            return 'That clip scene no longer exists.' unless scene && session.clip
            scene.merge!(self.na_box_copy(session.clip))
            session.clip['enabled'] = true
            session.clip_active_scene = scene['id']
            self.Na__Clip__Save(session, 'Point Cloud: Update Clip Scene')
            nil
        end

        def self.Na__Clip__SceneRename(session, scene_id, name)
            scene = self.na_scene(session, scene_id)
            return 'That clip scene no longer exists.' unless scene
            clean = name.to_s.strip[0, 60]
            return 'Give the scene a name.' if clean.empty?
            scene['name'] = clean
            self.Na__Clip__Save(session, 'Point Cloud: Rename Clip Scene')
            nil
        end

        def self.Na__Clip__SceneDelete(session, scene_id)
            scene = self.na_scene(session, scene_id)
            return 'That clip scene no longer exists.' unless scene
            session.clip_scenes.delete(scene)
            session.clip_active_scene = nil if session.clip_active_scene == scene_id
            self.Na__Clip__Save(session, 'Point Cloud: Delete Clip Scene')
            nil
        end

        # 'full' = Full Cloud: clipping off. The box and the scene it came from
        # are kept, so turning Clip back on returns to them.
        def self.Na__Clip__SceneActivate(session, scene_id)
            self.Na__Clip__Ensure(session)
            if scene_id.to_s == NA_FULL_CLOUD_ID
                return nil unless session.clip && session.clip['enabled']
                session.clip['enabled'] = false
                self.Na__Clip__Save(session, 'Point Cloud: Full Cloud')
                return nil
            end
            scene = self.na_scene(session, scene_id)
            return 'That clip scene no longer exists.' unless scene
            session.clip = self.na_box_copy(scene)
            session.clip_active_scene = scene['id']
            self.Na__Clip__Save(session, "Point Cloud: Clip Scene #{scene['name']}")
            nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Dialog Payload
    # -------------------------------------------------------------------------

        def self.Na__Clip__Payload(session, model)
            return { 'isAvailable' => false } unless session
            self.Na__Clip__Ensure(session)
            display = Na__UnitContract.Na__Units__ModelDisplay(model)
            clip = session.clip
            {
                'isAvailable'  => true,
                'hasCloud'     => !session.cloud.nil?,
                'hasBox'       => !clip.nil?,
                'enabled'      => clip ? clip['enabled'] : false,
                'isEditing'    => session.clip_editing ? true : false,
                'unit'         => display['suffix'],
                'limits'       => NA_FACES.map do |face|
                    value = clip ? Na__UnitContract.Na__Units__InchesToDisplayText(clip[face['side']][face['axis']], display) : ''
                    { 'id' => face['id'], 'label' => face['label'], 'value' => value }
                end,
                'fullCloudActive' => !(clip && clip['enabled']),
                'scenes'       => session.clip_scenes.map do |scene|
                    active = clip && clip['enabled'] && scene['id'] == session.clip_active_scene ? true : false
                    {
                        'id'         => scene['id'],
                        'name'       => scene['name'],
                        'isActive'   => active,
                        'isModified' => active && !self.na_same_box?(scene, clip)
                    }
                end
            }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals
    # -------------------------------------------------------------------------

        # The cloud's own bounds: exactly what "Reset to Cloud" means.
        def self.na_cloud_box(session)
            bounds = session.cloud.bounds
            { 'enabled' => true, 'min' => bounds.min.to_a.map(&:to_f), 'max' => bounds.max.to_a.map(&:to_f) }
        end

        # A scene always clips when switched to, so its copy is always enabled.
        def self.na_box_copy(box)
            { 'enabled' => true, 'min' => box['min'].dup, 'max' => box['max'].dup }
        end

        def self.na_same_box?(a, b)
            (0..2).all? { |i| (a['min'][i] - b['min'][i]).abs < 1e-6 && (a['max'][i] - b['max'][i]).abs < 1e-6 }
        end

        def self.na_valid_box(raw, enabled)
            return nil unless raw.is_a?(Hash)
            min = Array(raw['min']).map { |v| Float(v) }
            max = Array(raw['max']).map { |v| Float(v) }
            return nil unless min.length == 3 && max.length == 3 && (0..2).all? { |i| max[i] > min[i] }
            { 'enabled' => enabled ? true : false, 'min' => min, 'max' => max }
        rescue ArgumentError, TypeError
            nil
        end

        def self.na_valid_scene(raw)
            return nil unless raw.is_a?(Hash) && raw['id'].is_a?(String)
            box = self.na_valid_box(raw, true)
            return nil unless box
            { 'id' => raw['id'], 'name' => raw['name'].to_s.strip[0, 60] }.merge(box)
        end

        def self.na_scene(session, scene_id)
            self.Na__Clip__Ensure(session)
            session.clip_scenes.find { |scene| scene['id'] == scene_id.to_s }
        end

        def self.na_new_scene_id(session)
            used = session.clip_scenes.map { |scene| scene['id'] }
            index = session.clip_scenes.length + 1
            index += 1 while used.include?("scene#{index}")
            "scene#{index}"
        end

        def self.na_scene_name(session, name)
            clean = name.to_s.strip[0, 60]
            return clean unless clean.empty?
            "Clip scene #{session.clip_scenes.length + 1}"
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
