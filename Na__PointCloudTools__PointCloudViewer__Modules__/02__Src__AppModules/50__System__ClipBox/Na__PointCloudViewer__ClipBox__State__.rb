# =============================================================================
# NA POINT CLOUD VIEWER - CLIP BOX - STATE
# =============================================================================
#
# FILE       : Na__PointCloudViewer__ClipBox__State__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__ClipBox
# PURPOSE    : The clip box and the saved clip scenes of ONE point cloud: what
#              they are, how they are stored, and every change the dialog or
#              the edit tool can make to them.
#
# WHAT CLIPPING IS: six limits in MODEL coordinates (left/right = x,
#   front/back = y, bottom/top = z). Points outside are simply not drawn. The
#   LAS and the engine's copy of the points are never touched.
#
# ONE BOX PER CLOUD (v0.10.0): every cloud of the model has its own clip box
#   and its own clip scenes; every function here is handed that cloud's slot.
#   Copy to Other Clouds gives every other cloud the same box in one undoable
#   step (one slice through two scans while they are aligned).
#
# THE CLOUDS ON SHOW (v0.13.0): Draw Clip Box, Clip Box Around Selection and
#   the Clip On or Off shortcut look at an AREA of the model, so they act on
#   every cloud on show together (or the active cloud when none is shown), in
#   ONE undoable step. The dialog's own switches still act on the active cloud.
#
# WHERE IT LIVES: the cloud's own record in the model (Na__CloudStore: 'clip',
#   'clipScenes', 'activeClipScene'), a few hundred bytes, so the clip box and
#   its scenes travel with the .skp to any computer. Each committed change is
#   one named, undoable operation; Undo/Redo re-read it (ModelRegistry).
#   No point data is ever stored here.
#
# =============================================================================

module Na__PointCloudViewer
    module Na__ClipBox

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_DICT           = 'Na__PointCloudViewer__ClipState'.freeze   # v0.9 models only (read by Na__CloudStore)
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

        def self.Na__Clip__IsActive?(slot)
            return false unless slot
            self.Na__Clip__Ensure(slot)
            clip = slot.clip
            clip && clip['enabled'] ? true : false
        end

        # Appended to the native render parameters.
        def self.Na__Clip__RenderParams(slot)
            return [0, 0, 0, 0, 0, 0, 0] unless self.Na__Clip__IsActive?(slot)
            [1] + slot.clip['min'] + slot.clip['max']
        end

        # Part of the image renderer's cache key: any change re-renders.
        def self.Na__Clip__Key(slot)
            self.Na__Clip__IsActive?(slot) ? (slot.clip['min'] + slot.clip['max']) : nil
        end

        def self.Na__Clip__Face(face_id)
            NA_FACES.find { |face| face['id'] == face_id.to_s }
        end

        def self.Na__Clip__FaceValue(slot, face)
            slot.clip[face['side']][face['axis']]
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Load + Save (the cloud's record)
    # -------------------------------------------------------------------------

        def self.Na__Clip__Ensure(slot)
            return if slot.clip_loaded
            self.Na__Clip__Load(slot)
        end

        # From the cloud's record as the model holds it. A part that cannot be
        # read is ignored with a log line.
        def self.Na__Clip__Load(slot)
            slot.clip_loaded = true
            record = slot.record
            unless record
                slot.clip_scenes ||= []
                return
            end
            slot.clip              = self.na_valid_box(record['clip'], record['clip'].is_a?(Hash) && record['clip']['enabled'] == true)
            slot.clip_scenes       = Array(record['clipScenes']).map { |scene| self.na_valid_scene(scene) }.compact
            slot.clip_active_scene = record['activeClipScene'].is_a?(String) ? record['activeClipScene'] : nil
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Warn("The stored clip box of #{slot.name} could not be read and was ignored: #{error.message}")
        end

        # The record's clip parts for the box and scenes the slot holds now.
        def self.Na__Clip__Part(slot)
            {
                'clip'            => slot.clip ? { 'enabled' => slot.clip['enabled'] ? true : false, 'min' => slot.clip['min'], 'max' => slot.clip['max'] } : nil,
                'clipScenes'      => slot.clip_scenes || [],
                'activeClipScene' => slot.clip_active_scene
            }
        end

        # One undoable operation per committed change.
        # Returns nil, or why nothing was written (the box then goes back to
        # what the model holds, so memory never runs ahead of the model).
        def self.Na__Clip__Save(slot, operation_name)
            problem = Na__CloudStore.Na__Store__WriteSlots(slot.session, [slot], operation_name) do |_slot, record|
                record.merge!(self.Na__Clip__Part(slot))
            end
            if problem
                self.Na__Clip__Load(slot)
                return problem
            end
            Na__CleanPreview.Na__Clean__Changed(slot) if defined?(Na__CleanPreview)   # the box is the preview region
            nil
        end

        # Undo / Redo: see Na__ModelRegistry.Na__Registry__ReloadModelState, which
        # re-reads every cloud's clip box and placement together.
        def self.Na__Clip__ReloadFromModel(model)
            Na__ModelRegistry.Na__Registry__ReloadModelState(model)
        end

        def self.na_op(slot, text)
            Na__CloudSet.Na__Slots__OpName(slot, text)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Box Changes
    # -------------------------------------------------------------------------

        def self.Na__Clip__SetEnabled(slot, enabled)
            return 'Import a point cloud first: the clip box starts at the cloud\'s bounds.' unless slot
            self.Na__Clip__Ensure(slot)
            unless slot.clip
                return 'Load this point cloud first: the clip box starts at the cloud\'s bounds.' unless slot.cloud
                slot.clip = self.na_cloud_box(slot)
            end
            slot.clip['enabled'] = enabled ? true : false
            self.Na__Clip__Save(slot, self.na_op(slot, enabled ? 'Clip On' : 'Clip Off'))
        end

        def self.Na__Clip__ResetToCloud(slot)
            return 'Import a point cloud first: there are no bounds to reset to.' unless slot
            self.Na__Clip__Ensure(slot)
            return 'Load this point cloud first: there are no bounds to reset to.' unless slot.cloud
            slot.clip = self.na_cloud_box(slot)
            self.Na__Clip__Save(slot, self.na_op(slot, 'Reset Clip Box'))
        end

        # values: { 'left' => '3500', 'top' => '2.4m', ... } in the model's display
        # unit. Returns nil or a plain-English reason nothing changed.
        def self.Na__Clip__SetLimits(slot, values, display)
            return 'Import a point cloud first.' unless slot
            self.Na__Clip__Ensure(slot)
            return 'There is no clip box yet. Turn clipping on or press Edit Clip Box first.' unless slot.clip
            box = { 'enabled' => slot.clip['enabled'], 'min' => slot.clip['min'].dup, 'max' => slot.clip['max'].dup }
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
            slot.clip = box
            self.Na__Clip__Save(slot, self.na_op(slot, 'Clip Limits'))
        rescue ArgumentError => error
            error.message
        end

        # Live, unsaved change from the edit tool (one face). Keeps the box valid.
        def self.Na__Clip__SetFaceLive(slot, face, value)
            axis = face['axis']
            value = if face['side'] == 'min'
                        [value, slot.clip['max'][axis] - NA_MIN_GAP_INCHES].min
                    else
                        [value, slot.clip['min'][axis] + NA_MIN_GAP_INCHES].max
                    end
            slot.clip[face['side']][axis] = value
            value
        end

        # Every other cloud of the model takes this cloud's box (and whether it
        # clips), in ONE undoable operation. Their own clip scenes are kept.
        def self.Na__Clip__CopyToOthers(slot)
            return 'Import a point cloud first.' unless slot
            self.Na__Clip__Ensure(slot)
            return 'There is no clip box to copy yet.' unless slot.clip
            others = Na__CloudSet.Na__Slots__All(slot.session).reject { |other| other.equal?(slot) }
            return 'This model has no other point cloud to copy the box to.' if others.empty?
            box = { 'enabled' => slot.clip['enabled'] ? true : false, 'min' => slot.clip['min'].dup, 'max' => slot.clip['max'].dup }
            before = others.map { |other| [other, other.clip, other.clip_active_scene] }
            others.each do |other|
                self.Na__Clip__Ensure(other)
                other.clip = Marshal.load(Marshal.dump(box))
                other.clip_active_scene = nil
            end
            begin
                problem = Na__CloudStore.Na__Store__WriteSlots(slot.session, others, "Point Cloud: Copy Clip Box of #{slot.name} to Other Clouds") do |other, record|
                    record.merge!(self.Na__Clip__Part(other))
                end
            rescue StandardError
                before.each { |other, clip, active| other.clip = clip; other.clip_active_scene = active }
                raise
            end
            if problem
                before.each { |other, clip, active| other.clip = clip; other.clip_active_scene = active }
                return problem
            end
            nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Boxes For The Clouds On Show (v0.13.0)
    # -------------------------------------------------------------------------

        # The clouds a drawn box, a box around the selection and the Clip On or
        # Off shortcut act on: every cloud on show (its own Show switch on), or
        # the active cloud when none is.
        def self.Na__Clip__TargetSlots(session)
            slots = Na__CloudSet.Na__Slots__All(session)
            shown = slots.select(&:visible)
            return shown unless shown.empty?
            active = Na__CloudSet.Na__Slots__Active(session)
            active ? [active] : []
        end

        # "Interior", "Interior and Exterior", "Interior, Exterior and Site".
        def self.Na__Clip__Names(slots)
            names = slots.map(&:name)
            return names.first.to_s if names.length < 2
            "#{names[0..-2].join(', ')} and #{names.last}"
        end

        # Gives every slot in `slots` the box min..max (model inches), clipping,
        # in ONE undoable operation named `text`. Each leaves the clip scene it
        # was showing: the box is a new area. Returns nil, or a plain reason
        # nothing changed (every box then stays as the model holds it).
        def self.Na__Clip__SetBoxOn(session, slots, min, max, text)
            return 'There is no point cloud in this model yet.' if slots.empty?
            min = min.map(&:to_f)
            max = max.map(&:to_f)
            3.times do |axis|
                next if max[axis] - min[axis] >= NA_MIN_GAP_INCHES
                return "The box is too thin: each side must be at least #{(NA_MIN_GAP_INCHES * 25.4).round} mm."
            end
            slots.each { |slot| self.Na__Clip__Ensure(slot) }
            before = slots.map { |slot| [slot, slot.clip, slot.clip_active_scene] }
            slots.each do |slot|
                slot.clip = { 'enabled' => true, 'min' => min.dup, 'max' => max.dup }
                slot.clip_active_scene = nil
            end
            begin
                problem = Na__CloudStore.Na__Store__WriteSlots(session, slots, self.na_op_for(slots, text)) do |slot, record|
                    record.merge!(self.Na__Clip__Part(slot))
                end
            rescue StandardError
                before.each { |slot, clip, active| slot.clip = clip; slot.clip_active_scene = active }
                raise
            end
            if problem
                before.each { |slot, clip, active| slot.clip = clip; slot.clip_active_scene = active }
                return problem
            end
            slots.each { |slot| Na__CleanPreview.Na__Clean__Changed(slot) } if defined?(Na__CleanPreview)
            nil
        end

        # The Clip On or Off shortcut: when any cloud on show clips, clipping
        # goes off for every one of them; otherwise it comes on for each that
        # has a box. ONE undoable step. Returns [problem, note]: the note says
        # what happened.
        def self.Na__Clip__ToggleShown(session)
            slots = self.Na__Clip__TargetSlots(session)
            return ['There is no point cloud in this model yet.', nil] if slots.empty?
            slots.each { |slot| self.Na__Clip__Ensure(slot) }
            clipping = slots.select { |slot| slot.clip && slot.clip['enabled'] }
            turning_on = clipping.empty?
            changing = turning_on ? slots.select(&:clip) : clipping
            return ['No cloud on show has a clip box yet. Draw Clip Box makes one.', nil] if changing.empty?
            changing.each { |slot| slot.clip['enabled'] = turning_on }
            begin
                problem = Na__CloudStore.Na__Store__WriteSlots(session, changing, self.na_op_for(changing, turning_on ? 'Clip On' : 'Clip Off')) do |slot, record|
                    record.merge!(self.Na__Clip__Part(slot))
                end
            rescue StandardError
                changing.each { |slot| slot.clip['enabled'] = !turning_on }
                raise
            end
            if problem
                changing.each { |slot| slot.clip['enabled'] = !turning_on }
                return [problem, nil]
            end
            changing.each { |slot| Na__CleanPreview.Na__Clean__Changed(slot) } if defined?(Na__CleanPreview)
            names = Na__CloudSet.Na__Slots__Multi?(session) ? " for #{self.Na__Clip__Names(changing)}" : ''
            note = turning_on ? "Clipping on#{names}." : "Clipping off#{names}: the whole cloud is shown. The box is kept for when clipping comes back on."
            [nil, note]
        end

        # "Point Cloud: Draw Clip Box", with the cloud's name once the model has
        # two clouds, or how many clouds took the box.
        def self.na_op_for(slots, text)
            return self.na_op(slots.first, text) if slots.length == 1
            return "Point Cloud: #{text} (#{self.Na__Clip__Names(slots)})" if slots.length == 2
            "Point Cloud: #{text} (#{slots.length} clouds)"
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Clip Scenes
    # -------------------------------------------------------------------------

        def self.Na__Clip__SceneSave(slot, name)
            return 'Import a point cloud first.' unless slot
            self.Na__Clip__Ensure(slot)
            return 'There is no clip box to save yet.' unless slot.clip
            scene = { 'id' => self.na_new_scene_id(slot), 'name' => self.na_scene_name(slot, name) }.merge(self.na_box_copy(slot.clip))
            slot.clip_scenes << scene
            slot.clip['enabled'] = true
            slot.clip_active_scene = scene['id']
            self.Na__Clip__Save(slot, self.na_op(slot, 'Save Clip Scene'))
        end

        def self.Na__Clip__SceneUpdate(slot, scene_id)
            scene = self.na_scene(slot, scene_id)
            return 'That clip scene no longer exists.' unless scene && slot.clip
            scene.merge!(self.na_box_copy(slot.clip))
            slot.clip['enabled'] = true
            slot.clip_active_scene = scene['id']
            self.Na__Clip__Save(slot, self.na_op(slot, 'Update Clip Scene'))
        end

        def self.Na__Clip__SceneRename(slot, scene_id, name)
            scene = self.na_scene(slot, scene_id)
            return 'That clip scene no longer exists.' unless scene
            clean = name.to_s.strip[0, 60]
            return 'Give the scene a name.' if clean.empty?
            scene['name'] = clean
            self.Na__Clip__Save(slot, self.na_op(slot, 'Rename Clip Scene'))
        end

        def self.Na__Clip__SceneDelete(slot, scene_id)
            scene = self.na_scene(slot, scene_id)
            return 'That clip scene no longer exists.' unless scene
            slot.clip_scenes.delete(scene)
            slot.clip_active_scene = nil if slot.clip_active_scene == scene_id
            self.Na__Clip__Save(slot, self.na_op(slot, 'Delete Clip Scene'))
        end

        # The dialog's drag to reorder: ids is every scene id, top to bottom.
        # Only the order changes, as one undoable step. A list that no longer
        # matches the scenes (one added or deleted meanwhile) changes nothing.
        def self.Na__Clip__SceneReorder(slot, ids)
            return 'Import a point cloud first.' unless slot
            self.Na__Clip__Ensure(slot)
            wanted  = Array(ids).map(&:to_s)
            current = slot.clip_scenes.map { |scene| scene['id'] }
            return 'The clip scenes changed while you were moving one, so nothing was moved. Try again.' unless wanted.sort == current.sort && wanted.uniq.length == wanted.length
            return nil if wanted == current
            before = slot.clip_scenes.dup
            by_id  = before.each_with_object({}) { |scene, hash| hash[scene['id']] = scene }
            slot.clip_scenes.replace(wanted.map { |id| by_id[id] })
            begin
                self.Na__Clip__Save(slot, self.na_op(slot, 'Reorder Clip Scenes'))
            rescue StandardError
                slot.clip_scenes.replace(before)
                raise
            end
        end

        # 'full' = Full Cloud: clipping off. The box and the scene it came from
        # are kept, so turning Clip back on returns to them.
        def self.Na__Clip__SceneActivate(slot, scene_id)
            return 'Import a point cloud first.' unless slot
            self.Na__Clip__Ensure(slot)
            if scene_id.to_s == NA_FULL_CLOUD_ID
                return nil unless slot.clip && slot.clip['enabled']
                slot.clip['enabled'] = false
                return self.Na__Clip__Save(slot, self.na_op(slot, 'Full Cloud'))
            end
            scene = self.na_scene(slot, scene_id)
            return 'That clip scene no longer exists.' unless scene
            slot.clip = self.na_box_copy(scene)
            slot.clip_active_scene = scene['id']
            self.Na__Clip__Save(slot, self.na_op(slot, "Clip Scene #{scene['name']}"))
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Dialog Payload
    # -------------------------------------------------------------------------

        def self.Na__Clip__Payload(slot, model)
            return { 'isAvailable' => true, 'hasCloud' => false, 'hasBox' => false, 'enabled' => false, 'isEditing' => false,
                     'unit' => Na__UnitContract.Na__Units__ModelDisplay(model)['suffix'], 'fullCloudActive' => true, 'scenes' => [],
                     'limits' => NA_FACES.map { |face| { 'id' => face['id'], 'label' => face['label'], 'value' => '' } },
                     'otherClouds' => 0 } unless slot
            self.Na__Clip__Ensure(slot)
            display = Na__UnitContract.Na__Units__ModelDisplay(model)
            clip = slot.clip
            {
                'isAvailable'  => true,
                'cloudId'      => slot.id,
                'cloudName'    => slot.name,
                'hasCloud'     => !slot.cloud.nil?,
                'hasBox'       => !clip.nil?,
                'enabled'      => clip ? clip['enabled'] : false,
                'isEditing'    => slot.clip_editing ? true : false,
                'unit'         => display['suffix'],
                'otherClouds'  => Na__CloudSet.Na__Slots__All(slot.session).length - 1,
                'limits'       => NA_FACES.map do |face|
                    value = clip ? Na__UnitContract.Na__Units__InchesToDisplayText(clip[face['side']][face['axis']], display) : ''
                    { 'id' => face['id'], 'label' => face['label'], 'value' => value }
                end,
                'fullCloudActive' => !(clip && clip['enabled']),
                'scenes'       => slot.clip_scenes.map do |scene|
                    active = clip && clip['enabled'] && scene['id'] == slot.clip_active_scene ? true : false
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
        def self.na_cloud_box(slot)
            bounds = slot.cloud.bounds
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

        def self.na_scene(slot, scene_id)
            return nil unless slot
            self.Na__Clip__Ensure(slot)
            slot.clip_scenes.find { |scene| scene['id'] == scene_id.to_s }
        end

        def self.na_new_scene_id(slot)
            used = slot.clip_scenes.map { |scene| scene['id'] }
            index = slot.clip_scenes.length + 1
            index += 1 while used.include?("scene#{index}")
            "scene#{index}"
        end

        def self.na_scene_name(slot, name)
            clean = name.to_s.strip[0, 60]
            return clean unless clean.empty?
            "Clip scene #{slot.clip_scenes.length + 1}"
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
