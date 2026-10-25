# =============================================================================
# NA POINT CLOUD VIEWER - CLOUD SET - SLOTS
# =============================================================================
#
# FILE       : Na__PointCloudViewer__CloudSet__Slots__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__CloudSet
# PURPOSE    : The model's point clouds (v0.10.0): which ones it has, which one
#              the tools work on, which are on show and how each one looks.
#
# ONE ACTIVE CLOUD: the Clipping, Transform and Clean tabs, the Move and
#   Rotate tools, the clip box tool and Export Configuration all work on the
#   active cloud, and every one of them is handed that cloud's slot when it
#   starts. Choosing another cloud ends a tool that is working on the old one,
#   so a tool can never move from one cloud to another half way through.
#
# ON SHOW: each cloud has its own Show switch, and SketchUp's Overlays panel
#   (the overlay's own switch) still shows or hides them all. Show and each
#   cloud's look (dot size, opacity, colour) are view settings: changing them
#   never writes to the model and never adds an Undo step. Point cloud scenes
#   keep them, and this computer remembers each cloud's look. The point budget
#   is shared by every cloud on show (see Na__ImageRenderer).
#
# WHAT IS WRITTEN: a cloud's name and colour (with its link, position and
#   clip box, through Na__CloudStore), and the order of the clouds.
#
# =============================================================================

module Na__PointCloudViewer
    module Na__CloudSet

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_REMEMBERED_LOOKS = 40

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | The Slots (read from the model on first use)
    # -------------------------------------------------------------------------

        def self.Na__Slots__Ensure(session)
            return [] unless session
            return session.slots if session.slots
            session.slots = []
            self.Na__Slots__Sync(session)
            self.na_adopt_legacy_session(session)
            session.slots
        end

        def self.Na__Slots__All(session)
            self.Na__Slots__Ensure(session)
        end

        # Reads every cloud record again (first use, Undo / Redo, Restore,
        # Remove). A slot keeps its loaded points and its view settings when
        # its record is still there; a loaded cloud whose record went (an Undo
        # took it out) stays loaded, marked unsaved; any other slot whose
        # record went is dropped.
        def self.Na__Slots__Sync(session)
            read = Na__CloudStore.Na__Store__Read(session.model)
            existing = Array(session.slots).each_with_object({}) { |slot, hash| hash[slot.id] = slot }
            slots = read['clouds'].map do |entry|
                slot = existing.delete(entry['id']) || Na__CloudSlot.new(session, entry['id'])
                slot.session      = session
                slot.record       = entry['record']
                slot.record_state = entry['state']
                self.na_apply_identity(session, slot)
                slot.display ||= self.na_remembered_display(session, slot)
                Na__ClipBox.Na__Clip__Load(slot)
                slot
            end
            existing.each_value do |slot|
                if slot.cloud
                    slot.record = nil
                    slot.record_state = 'unsaved'
                    slots << slot
                else
                    Na__CleanPreview.Na__Clean__Reset(slot) if defined?(Na__CleanPreview)
                end
            end
            session.slots          = slots
            session.store_index    = read['index']
            session.store_legacy   = read['legacy']
            session.store_readonly = read['readonly']
            session.store_problem  = read['problems'].first
            self.na_fix_active(session)
            slots
        end

        def self.Na__Slots__Find(session, id)
            self.Na__Slots__Ensure(session).find { |slot| slot.id == id.to_s }
        end

        def self.Na__Slots__Active(session)
            slots = self.Na__Slots__Ensure(session)
            slots.find { |slot| slot.id == session.active_slot_id } || slots.first
        end

        def self.Na__Slots__Multi?(session)
            self.Na__Slots__Ensure(session).length > 1
        end

        # The clouds drawn now: on show and loaded, in the model's order.
        def self.Na__Slots__Drawn(session)
            self.Na__Slots__Ensure(session).select { |slot| slot.visible && slot.cloud }
        end

        def self.Na__Slots__Loaded(session)
            self.Na__Slots__Ensure(session).select(&:cloud)
        end

        # The slot of a LAS: the one whose link names that content (or, for a
        # link from before v0.8.0, that fingerprint), or the loaded one.
        def self.Na__Slots__ForFile(session, content_key, fingerprint)
            self.Na__Slots__Ensure(session).find do |slot|
                link = slot.record && slot.record['link']
                loaded_key = slot.cloud && slot.cloud.las_info ? slot.cloud.las_info['contentKey'] : nil
                key = link ? link['contentKey'] : loaded_key
                if key && content_key
                    key == content_key
                else
                    known = link ? link['fingerprint'] : (slot.placement ? Na__ModelLink.Na__Link__FingerprintFromKey(slot.placement['key']) : nil)
                    known && known == fingerprint
                end
            end
        end

        # A new cloud for the model (not saved yet: the import saves it).
        def self.Na__Slots__New(session, cloud)
            self.Na__Slots__Ensure(session)
            slot = Na__CloudSlot.new(session, Na__CloudStore.Na__Store__NewCloudId(session))
            slot.name    = Na__CloudStore.na_clean_name(nil, cloud ? cloud.source_path : '')
            slot.colour  = Na__CloudStore.Na__Store__NextColour(session)
            slot.display = Na__RenderSettings.Na__Settings__DisplayPart(session.settings)
            slot.clip_loaded = true
            session.slots << slot
            slot
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Active Cloud
    # -------------------------------------------------------------------------

        # Returns nil, or a plain sentence about what had to stop.
        def self.Na__Slots__Activate(session, slot)
            return 'That point cloud is no longer in this model.' unless slot && self.Na__Slots__Ensure(session).include?(slot)
            previous = self.Na__Slots__Active(session)
            return nil if previous.equal?(slot) && session.active_slot_id == slot.id
            ended = self.na_end_tools_not_on(session, slot)
            session.active_slot_id = slot.id
            Na__CleanPreview.Na__Clean__ActiveChanged(session, previous, slot) if defined?(Na__CleanPreview)
            Na__RenderController.Na__Render__RefreshExtents(session)
            self.na_invalidate(session)
            ended ? "Now working on #{slot.name}. The #{ended} was finished on #{previous.name}." : nil
        end

        # The tool name ended, or nil: a Move / Rotate or clip box tool working
        # on a different cloud than `slot` is deselected.
        def self.na_end_tools_not_on(session, slot)
            tool = session.transform_tool
            if tool && tool.respond_to?(:na_slot) && !tool.na_slot.equal?(slot)
                name = tool.na_kind == 'rotate' ? 'Rotate tool' : 'Move tool'
                Sketchup.active_model.select_tool(nil)
                session.transform_tool = nil
                return name
            end
            editing = self.Na__Slots__Ensure(session).find(&:clip_editing)
            if editing && !editing.equal?(slot)
                Sketchup.active_model.select_tool(nil)
                editing.clip_editing = false
                return 'clip box editing'
            end
            nil
        end

        def self.na_fix_active(session)
            slots = session.slots || []
            return session.active_slot_id = nil if slots.empty?
            return if slots.any? { |slot| slot.id == session.active_slot_id }
            session.active_slot_id = (slots.find(&:cloud) || slots.first).id
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | View Settings (never written to the model)
    # -------------------------------------------------------------------------

        def self.Na__Slots__SetVisible(slot, visible)
            slot.visible = visible ? true : false
            Na__RenderController.Na__Render__RefreshExtents(slot.session)
            self.na_invalidate(slot.session)
            nil
        end

        # Returns the keys that changed. The look is remembered on this
        # computer, so the cloud looks the same after the next Reload.
        def self.Na__Slots__ApplyDisplay(slot, partial)
            before = slot.display || Na__RenderSettings.Na__Settings__DisplayPart(slot.session.settings)
            after  = Na__RenderSettings.Na__Settings__MergeDisplay(before, partial)
            slot.display = after
            changed = Na__RenderSettings.Na__Settings__ChangedKeys(before, after)
            self.na_remember_display(slot) unless changed.empty?
            changed
        end

        def self.na_remembered_display(session, slot)
            looks = Na__UserConfigStore.Na__UserConfig__Get('render', 'cloudLooks', {})
            saved = looks.is_a?(Hash) ? looks[slot.id] : nil
            base  = Na__RenderSettings.Na__Settings__DisplayPart(session.settings)
            saved.is_a?(Hash) ? Na__RenderSettings.Na__Settings__MergeDisplay(base, saved) : base
        end

        def self.na_remember_display(slot)
            looks = Na__UserConfigStore.Na__UserConfig__Get('render', 'cloudLooks', {})
            looks = looks.is_a?(Hash) ? looks.reject { |id, _| id == slot.id } : {}
            looks[slot.id] = slot.display
            looks = looks.to_a.last(NA_REMEMBERED_LOOKS).to_h
            Na__UserConfigStore.Na__UserConfig__Set('render', 'cloudLooks', looks)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Name, Colour, Order, Remove (each one undoable)
    # -------------------------------------------------------------------------

        def self.Na__Slots__Rename(slot, name)
            clean = name.to_s.strip[0, 60]
            return 'Give the point cloud a name.' if clean.empty?
            return nil if clean == slot.name
            old = slot.name
            problem = Na__CloudStore.Na__Store__WriteSlots(slot.session, [slot], "Point Cloud: Rename #{old} to #{clean}") do |_slot, record|
                record['name'] = clean
            end
            slot.name = clean unless problem
            problem
        end

        # rgb: [r, g, b] 0..255 (a palette colour from the dialog).
        def self.Na__Slots__SetColour(slot, rgb)
            return 'Choose one of the colours shown.' unless Na__CloudStore.na_valid_rgb(rgb)
            colour = rgb.map(&:to_i)
            return nil if colour == slot.colour
            problem = Na__CloudStore.Na__Store__WriteSlots(slot.session, [slot], self.Na__Slots__OpName(slot, 'Colour')) do |_slot, record|
                record['colour'] = colour
            end
            unless problem
                slot.colour = colour
                self.na_invalidate(slot.session)
            end
            problem
        end

        # ids: every saved cloud's id, top to bottom (the dialog's drag).
        def self.Na__Slots__Reorder(session, ids)
            slots = self.Na__Slots__Ensure(session)
            saved = slots.select { |slot| %w[saved legacy].include?(slot.record_state) }
            wanted = Array(ids).map(&:to_s)
            current = saved.map(&:id)
            return 'The point clouds changed while you were moving one, so nothing was moved. Try again.' unless wanted.sort == current.sort && wanted.uniq.length == wanted.length
            return nil if wanted == current
            before = slots.dup
            by_id = saved.each_with_object({}) { |slot, hash| hash[slot.id] = slot }
            session.slots = wanted.map { |id| by_id[id] } + (slots - saved)
            problem = Na__CloudStore.Na__Store__WriteOrder(session, wanted, 'Point Cloud: Reorder Point Clouds')
            session.slots = before if problem
            problem
        rescue StandardError
            session.slots = before if before
            raise
        end

        # Takes the cloud out of the model: its points are released and its
        # record goes (Undo brings the record back; Reload its points). The LAS
        # file and its point cache are never touched.
        def self.Na__Slots__Remove(slot)
            session = slot.session
            view = Sketchup.active_model.active_view
            self.na_end_tools_on(session, slot)
            if %w[saved legacy].include?(slot.record_state)
                problem = Na__CloudStore.Na__Store__RemoveSlot(session, slot, "Point Cloud: Remove #{slot.name}")
                return problem if problem
            end
            Na__RenderController.Na__Render__ClearCloud(slot, view) if slot.cloud
            Na__CleanPreview.Na__Clean__Reset(slot) if defined?(Na__CleanPreview)
            session.slots.delete(slot)
            self.na_fix_active(session)
            Na__RenderController.Na__Render__RefreshExtents(session)
            self.na_invalidate(session)
            nil
        end

        # A cloud the model does not hold (its import was undone, or every
        # record was taken out) has nothing to come back from once it is
        # unloaded, so it leaves the list. Returns true when it did.
        def self.Na__Slots__ForgetUnsaved(slot)
            session = slot.session
            return false unless session && slot.cloud.nil? && slot.record.nil? && slot.record_state == 'unsaved'
            Na__CleanPreview.Na__Clean__Reset(slot) if defined?(Na__CleanPreview)
            session.slots.delete(slot)
            self.na_fix_active(session)
            Na__RenderController.Na__Render__RefreshExtents(session)
            true
        end

        def self.na_end_tools_on(session, slot)
            tool = session.transform_tool
            if tool && tool.respond_to?(:na_slot) && tool.na_slot.equal?(slot)
                Sketchup.active_model.select_tool(nil)
                session.transform_tool = nil
            end
            Sketchup.active_model.select_tool(nil) if slot.clip_editing
            slot.clip_editing = false
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Words (operation names and messages)
    # -------------------------------------------------------------------------

        # "Point Cloud: Clip On", or "Point Cloud: Clip On (Interior)" once the
        # model has more than one cloud, so SketchUp's Undo says which cloud.
        def self.Na__Slots__OpName(slot, text)
            return "Point Cloud: #{text}" unless slot && slot.session && self.Na__Slots__Multi?(slot.session)
            "Point Cloud: #{text} (#{slot.name})"
        end

        # "Interior: " before a status message once there is more than one cloud.
        def self.Na__Slots__Prefix(slot)
            slot && slot.session && self.Na__Slots__Multi?(slot.session) ? "#{slot.name}: " : ''
        end

        def self.Na__Slots__HexColour(rgb)
            format('#%02x%02x%02x', *Array(rgb).first(3).map { |value| [[value.to_i, 0].max, 255].min })
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Dialog Payload
    # -------------------------------------------------------------------------

        def self.Na__Slots__Payload(session, model)
            return { 'isAvailable' => false, 'list' => [], 'count' => 0 } unless session
            slots  = self.Na__Slots__Ensure(session)
            active = self.Na__Slots__Active(session)
            backup = Na__LocalBackup.Na__Backup__Find(model, session)
            {
                'isAvailable'   => true,
                'count'         => slots.length,
                'maxClouds'     => Na__CloudStore.Na__Store__MaxClouds,
                'activeId'      => active ? active.id : nil,
                'loadedCount'   => slots.count(&:cloud),
                'unloadedCount' => slots.count { |slot| !slot.cloud },
                'reloadCount'   => slots.count { |slot| Na__ModelLink.Na__Link__NeedsReload?(slot) },
                'readonly'      => session.store_readonly ? true : false,
                'problem'       => session.store_problem,
                'palette'       => Na__CloudStore.Na__Store__Palette.map { |rgb| self.Na__Slots__HexColour(rgb) },
                'list'          => slots.map { |slot| self.na_slot_payload(slot, active, model, backup) }
            }
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('The point cloud list could not be built.', error)
            { 'isAvailable' => true, 'list' => [], 'count' => 0, 'problem' => "The point clouds could not be listed (#{error.message})." }
        end

        def self.na_slot_payload(slot, active, model, backup)
            link  = slot.record ? slot.record['link'] : nil
            cloud = slot.cloud
            needs = Na__ModelLink.Na__Link__NeedsReload?(slot)
            found = needs ? Na__ModelLink.Na__Link__FoundPath(model, slot, backup) : nil
            stats = slot.layer_stats || {}
            display = slot.display || {}
            {
                'id'          => slot.id,
                'name'        => slot.name,
                'colour'      => self.Na__Slots__HexColour(slot.colour),
                'isActive'    => slot.equal?(active),
                'visible'     => slot.visible ? true : false,
                'loaded'      => !cloud.nil?,
                'needsReload' => needs,
                'namesOther'  => cloud && needs ? true : false,
                'recordState' => slot.record_state,
                'fileName'    => link ? link['fileName'].to_s : (cloud ? cloud.label.to_s : ''),
                'derivedFrom' => link && link['derivedFrom'].is_a?(Hash) ? link['derivedFrom']['fileName'].to_s : nil,
                'unitLabel'   => Na__UnitContract.Na__Units__SourceUnitLabel(cloud ? cloud.source_unit : (link ? link['sourceUnit'] : nil)),
                'pointsText'  => Na__PerfStats.Na__Perf__Thousands(cloud ? cloud.total_points : (link ? link['pointCount'] : 0)),
                'totalPoints' => cloud ? cloud.total_points : (link ? link['pointCount'].to_i : 0),
                'sizeText'    => cloud && cloud.bounds ? Na__StatePayload.na_bounds_text(cloud.bounds) : '',
                'lastPath'    => link ? link['lastPath'].to_s : (cloud ? cloud.source_path.to_s : ''),
                'foundPath'   => found,
                'locked'      => slot.placement ? slot.placement['locked'] != false : true,
                'clipOn'      => slot.clip && slot.clip['enabled'] ? true : false,
                'colourMode'  => display['colourMode'],
                'opacityPercent' => display['opacityPercent'],
                'drawn'       => cloud && slot.visible ? stats['onScreen'] : nil,
                'share'       => cloud && slot.visible ? stats['share'] : nil,
                'note'        => slot.placement_note,
                'positionText'=> Na__ModelLink.na_position_text(slot.record ? Na__Placement.na_valid_part(slot.record['placement']) : nil)
            }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Viewport Label (which cloud a tool is working on)
    # -------------------------------------------------------------------------

        NA_LABEL_TEXT_COLOUR = Sketchup::Color.new(32, 36, 43) unless defined?(NA_LABEL_TEXT_COLOUR)
        NA_LABEL_BACK_COLOUR = Sketchup::Color.new(255, 255, 255) unless defined?(NA_LABEL_BACK_COLOUR)

        # With more than one cloud in the model, the Move, Rotate and clip box
        # tools carry the name of the cloud they move, in its colour, beside
        # the gimbal, the protractor or the top of the box.
        def self.Na__Slots__DrawToolLabel(session, view)
            return unless self.Na__Slots__Multi?(session)
            slot, anchor = self.na_label_target(session)
            return unless slot && anchor
            point = Geom::Point3d.new(*anchor)
            return unless Na__ClipBox.na_in_front?(view, point)
            screen = view.screen_coords(point)
            text = slot.name.to_s
            width = self.na_text_width(view, text) + 26.0
            x = screen.x + 18.0
            y = screen.y - 38.0
            box = [[x, y], [x + width, y], [x + width, y + 20.0], [x, y + 20.0]].map { |px, py| Geom::Point3d.new(px, py, 0) }
            swatch = [[x + 5, y + 5], [x + 15, y + 5], [x + 15, y + 15], [x + 5, y + 15]].map { |px, py| Geom::Point3d.new(px, py, 0) }
            colour = Sketchup::Color.new(*slot.colour)
            view.line_stipple = ''
            view.drawing_color = NA_LABEL_BACK_COLOUR
            view.draw2d(GL_QUADS, box)
            view.drawing_color = colour
            view.draw2d(GL_QUADS, swatch)
            view.line_width = 2
            view.draw2d(GL_LINE_LOOP, box)
            view.line_width = 1
            view.draw_text(Geom::Point3d.new(x + 20.0, y + 3.0, 0), text, size: 10, bold: true, color: NA_LABEL_TEXT_COLOUR)
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Warn("The cloud label could not be drawn: #{error.message}")
        end

        # [slot, model point] the label sits by, or nil.
        def self.na_label_target(session)
            tool = session.transform_tool
            if tool && tool.respond_to?(:na_slot) && tool.na_slot && tool.na_slot.cloud && tool.na_slot.placement
                return [tool.na_slot, tool.na_label_anchor] if tool.respond_to?(:na_label_anchor) && tool.na_label_anchor
                return [tool.na_slot, Na__Placement.Na__Placement__GimbalModel(tool.na_slot)]
            end
            editing = self.Na__Slots__Ensure(session).find { |slot| slot.clip_editing && slot.clip }
            return nil unless editing
            top = Na__ClipBox.Na__Clip__Face('top')
            [editing, Na__ClipBox.na_face_centre(editing.clip, top).to_a]
        end

        def self.na_text_width(view, text)
            if view.respond_to?(:text_bounds)
                bounds = view.text_bounds(Geom::Point3d.new(0, 0, 0), text, size: 10, bold: true)
                return bounds.width.to_f if bounds && bounds.respond_to?(:width) && bounds.width.to_f > 0
            end
            text.length * 7.0
        rescue StandardError
            text.length * 7.0
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals
    # -------------------------------------------------------------------------

        def self.na_apply_identity(session, slot)
            record = slot.record
            slot.name = record['name'].to_s if record && !record['name'].to_s.empty?
            colour = record ? record['colour'] : nil
            slot.colour = if Na__CloudStore.na_valid_rgb(colour)
                              colour.map(&:to_i)
                          elsif slot.colour && !(session.slots || []).any? { |other| !other.equal?(slot) && other.colour == slot.colour }
                              slot.colour
                          else
                              Na__CloudStore.Na__Store__NextColour(session)
                          end
        end

        # A session made before v0.10.0, still alive after Reload Plugin: its
        # one loaded cloud moves into the slot of the same LAS.
        def self.na_adopt_legacy_session(session)
            state = session.na_legacy_state
            return if state.empty?
            session.na_forget_legacy_state
            old_clean = state[:@clean_state]
            if old_clean && old_clean.respond_to?(:context)
                (old_clean.preview_clouds || {}).each_value { |pointer| Na__NativeEngine.Na__Native__CloudRelease(pointer) if pointer }
                Na__NativeEngine.Na__Native__CleanDestroy(old_clean.context) if old_clean.context
            end
            cloud = state[:@cloud]
            return unless cloud
            info = cloud.las_info || {}
            placement = state[:@placement]
            fingerprint = placement ? Na__ModelLink.Na__Link__FingerprintFromKey(placement['key']) : nil
            slot = self.Na__Slots__ForFile(session, info['contentKey'], fingerprint) || self.Na__Slots__New(session, cloud)
            slot.cloud = cloud
            slot.placement = placement
            slot.placement_note = state[:@placement_note]
            session.active_slot_id = slot.id
            Na__DebugTools.Na__Debug__Info("The cloud loaded before the reload (#{cloud.label}) is now #{slot.name} (#{slot.id}).")
        end

        def self.na_invalidate(session)
            model = session ? session.model : nil
            model.active_view.invalidate if model && model == Sketchup.active_model
        rescue StandardError
            nil
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
