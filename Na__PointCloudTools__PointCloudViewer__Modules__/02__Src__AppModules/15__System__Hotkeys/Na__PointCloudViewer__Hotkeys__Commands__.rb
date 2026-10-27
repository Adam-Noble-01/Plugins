# =============================================================================
# NA POINT CLOUD VIEWER - HOTKEYS - COMMANDS
# =============================================================================
#
# FILE       : Na__PointCloudViewer__Hotkeys__Commands__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__HotkeyCommands
# PURPOSE    : What each shortcut command does (v0.13.0). Na__HotkeyManager puts
#              them in the menu and runs them; the config lists them.
#
# WHICH CLOUDS: the commands are for working, so they act on what is on screen.
#   Show or Hide Point Clouds is the master switch (the overlay, the same as
#   the Show switch and SketchUp's Overlays panel). Draw Clip Box, Clip Box
#   Around Selection, Clip On or Off and the Colour Mode commands act on every
#   cloud on show, or the active cloud when none is (Na__Clip__TargetSlots).
#   Show or Hide the Active Cloud, Next Point Cloud and Edit Clip Box act on
#   the active cloud, the one the tabs work on.
#
# WORDS: each command returns [message, level] for the status line, or nil
#   when what it did speaks for itself.
#
# =============================================================================

module Na__PointCloudViewer
    module Na__HotkeyCommands

    # -------------------------------------------------------------------------
    # REGION | Routing Table
    # -------------------------------------------------------------------------

        NA_HANDLERS = {
            'open_viewer'    => :na_open_viewer,
            'toggle_clouds'  => :na_toggle_clouds,
            'toggle_active'  => :na_toggle_active,
            'next_cloud'     => :na_next_cloud,
            'zoom_clouds'    => :na_zoom_clouds,
            'draw_clip'      => :na_draw_clip,
            'clip_selection' => :na_clip_selection,
            'edit_clip'      => :na_edit_clip,
            'toggle_clip'    => :na_toggle_clip,
            'colour_rgb'     => :na_colour_rgb,
            'colour_mono'    => :na_colour_mono,
            'colour_primary' => :na_colour_primary,
            'fewer_points'   => :na_fewer_points,
            'more_points'    => :na_more_points
        }.freeze

        # The commands whose menu item carries a checkmark while it is on.
        NA_TOGGLES = %w[toggle_clouds toggle_active draw_clip edit_clip toggle_clip colour_rgb colour_mono colour_primary].freeze

        NA_COLOUR_MODES = { 'colour_rgb' => 'rgb', 'colour_mono' => 'black', 'colour_primary' => 'primary' }.freeze

        def self.Na__Commands__Known?(id)
            NA_HANDLERS.key?(id.to_s)
        end

        def self.Na__Commands__Toggle?(id)
            NA_TOGGLES.include?(id.to_s)
        end

        # Returns [message, level] or nil.
        def self.Na__Commands__Run(id)
            handler = NA_HANDLERS[id.to_s]
            return ["There is no shortcut command called '#{id}'.", 'warn'] unless handler
            self.send(handler)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Viewing
    # -------------------------------------------------------------------------

        def self.na_open_viewer
            Na__PointCloudViewer.Na__PublicApi__OpenDialog
            nil
        end

        # The master switch. Showing them when every cloud was switched off on
        # its own row switches them all on, so the key always shows something;
        # and with every row switched off it shows them, never hides nothing.
        def self.na_toggle_clouds
            session = self.na_session
            return self.na_no_overlay unless session
            slots = Na__CloudSet.Na__Slots__All(session)
            return self.na_no_clouds if slots.empty?
            if Na__ModelRegistry.Na__Registry__IsVisible? && slots.any?(&:visible)
                Na__ModelRegistry.Na__Registry__SetVisible(false)
                return ['Point clouds hidden.', 'info']
            end
            all_hidden = slots.none?(&:visible)
            slots.each { |slot| Na__CloudSet.Na__Slots__SetVisible(slot, true) } if all_hidden
            Na__ModelRegistry.Na__Registry__SetVisible(true)
            text = all_hidden ? 'Point clouds shown. Each one had been hidden on its own, so all of them are shown now.' : 'Point clouds shown.'
            ["#{text}#{self.na_not_loaded_note(slots.select(&:visible))}", 'info']
        end

        def self.na_toggle_active
            session = self.na_session
            return self.na_no_overlay unless session
            slot = Na__CloudSet.Na__Slots__Active(session)
            return self.na_no_clouds unless slot
            if slot.visible && Na__ModelRegistry.Na__Registry__IsVisible?
                Na__CloudSet.Na__Slots__SetVisible(slot, false)
                return ["#{slot.name} hidden.", 'info']
            end
            Na__CloudSet.Na__Slots__SetVisible(slot, true)
            Na__ModelRegistry.Na__Registry__SetVisible(true) unless Na__ModelRegistry.Na__Registry__IsVisible?
            ["#{slot.name} shown.#{self.na_not_loaded_note([slot])}", 'info']
        end

        def self.na_next_cloud
            session = self.na_session
            return self.na_no_overlay unless session
            slots = Na__CloudSet.Na__Slots__All(session)
            return self.na_no_clouds if slots.empty?
            return ["#{slots.first.name} is the only point cloud in this model.", 'info'] if slots.length == 1
            active = Na__CloudSet.Na__Slots__Active(session)
            target = slots[((slots.index(active) || -1) + 1) % slots.length]
            note = Na__CloudSet.Na__Slots__Activate(session, target)
            return [note, 'warn'] if note
            shown = target.visible && Na__ModelRegistry.Na__Registry__IsVisible?
            ["Working on #{target.name}.#{shown ? '' : ' It is hidden: Show or Hide the Active Cloud shows it.'}", 'info']
        end

        def self.na_zoom_clouds
            session = self.na_session
            return self.na_no_overlay unless session
            if Na__CloudSet.Na__Slots__Drawn(session).empty? || !Na__ModelRegistry.Na__Registry__IsVisible?
                return ['There is no point cloud on show to zoom to.', 'warn']
            end
            Na__RenderController.Na__Render__ZoomToCloud(session, Sketchup.active_model.active_view)
            nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Clipping
    # -------------------------------------------------------------------------

        # A fresh Draw Clip Box tool every time, as SketchUp's own tool keys
        # start their tool again. Its status line explains it.
        def self.na_draw_clip
            problem = Na__ClipBox.Na__Clip__StartDrawing(self.na_session)
            problem ? [problem, 'warn'] : nil
        end

        def self.na_clip_selection
            session = self.na_session
            return self.na_no_overlay unless session
            problem, note = Na__ClipBox.Na__Clip__BoxAroundSelection(session, Sketchup.active_model)
            problem ? [problem, 'warn'] : [note, 'success']
        end

        # The active cloud's box, with its sides to push and pull. The cage is
        # drawn by the overlay, so the cloud and the overlay are switched on.
        def self.na_edit_clip
            session = self.na_session
            return self.na_no_overlay unless session
            slot = Na__CloudSet.Na__Slots__Active(session)
            return self.na_no_clouds unless slot
            if slot.clip_editing
                Na__ClipBox.Na__Clip__StopEditing(slot)
                return ['Clip box editing finished.', 'info']
            end
            problem = Na__ClipBox.Na__Clip__StartEditing(slot)
            return [problem, 'warn'] if problem
            Na__CloudSet.Na__Slots__SetVisible(slot, true) unless slot.visible
            Na__ModelRegistry.Na__Registry__SetVisible(true) unless Na__ModelRegistry.Na__Registry__IsVisible?
            Na__RenderController.Na__Render__RefreshExtents(session)
            nil
        end

        def self.na_toggle_clip
            session = self.na_session
            return self.na_no_overlay unless session
            problem, note = Na__ClipBox.Na__Clip__ToggleShown(session)
            Na__RenderController.Na__Render__RefreshExtents(session)
            Sketchup.active_model.active_view.invalidate
            problem ? [problem, 'warn'] : [note, 'info']
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Look and Point Budget
    # -------------------------------------------------------------------------

        def self.na_colour_rgb
            self.na_colour('colour_rgb', 'RGB colour')
        end

        def self.na_colour_mono
            self.na_colour('colour_mono', 'Monochrome')
        end

        def self.na_colour_primary
            self.na_colour('colour_primary', 'Primary Colour')
        end

        # Each cloud's look is its own and is remembered on this computer
        # (never written to the model, no Undo step), as on the View tab.
        def self.na_colour(id, label)
            session = self.na_session
            return self.na_no_overlay unless session
            slots = Na__ClipBox.Na__Clip__TargetSlots(session)
            return self.na_no_clouds if slots.empty?
            slots.each { |slot| Na__RenderController.Na__Render__ApplySettings(session, { 'colourMode' => NA_COLOUR_MODES[id] }, nil, slot) }
            Sketchup.active_model.active_view.invalidate
            names = Na__CloudSet.Na__Slots__Multi?(session) ? " for #{Na__ClipBox.Na__Clip__Names(slots)}" : ''
            ["#{label}#{names}.", 'info']
        end

        def self.na_fewer_points
            self.na_budget_step(-1)
        end

        def self.na_more_points
            self.na_budget_step(1)
        end

        # One step along the View tab's presets: those below the points on
        # show, then All (every point on show), as its preset row shows them.
        def self.na_budget_step(direction)
            session = self.na_session
            return self.na_no_overlay unless session
            total = Na__CloudSet.Na__Slots__Drawn(session).sum { |slot| slot.cloud.total_points.to_i }
            presets = Array(Na__ConfigLoader.Na__Config__GetOr([], 'render', 'budgetPresets')).select { |preset| preset.is_a?(Hash) && preset['points'].to_i > 0 }
            steps = presets.map { |preset| preset['points'].to_i }
            steps = steps.select { |points| points < total } + [total] if total > 0
            steps = steps.uniq.sort
            current = session.settings['pointBudget'].to_i
            current = total if total > 0 && current > total
            target = direction > 0 ? steps.find { |points| points > current } : steps.reverse.find { |points| points < current }
            unless target
                return ['The point budget is at the top already: every point on show is drawn.', 'info'] if direction > 0
                return ['The point budget is at its lowest preset already.', 'info']
            end
            Na__RenderController.Na__Render__ApplySettings(session, { 'pointBudget' => target }, Sketchup.active_model.active_view)
            preset = presets.find { |each| each['points'].to_i == target }
            label = total > 0 && target >= total ? 'All' : (preset ? preset['label'].to_s : 'Custom')
            ["Point budget: #{label}, #{Na__PerfStats.Na__Perf__Thousands(target)} points.", 'info']
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Menu Checkmarks (read only: what is already in memory)
    # -------------------------------------------------------------------------

        # True when the command's switch is on now. Reads only what the session
        # holds already, never the model, and never creates an overlay.
        def self.Na__Commands__Checked?(id)
            overlay = Na__ModelRegistry.Na__Registry__FindOverlay(Sketchup.active_model)
            return false unless overlay && overlay.respond_to?(:na_session)
            session = overlay.na_session
            slots = session.slots || []
            shown = slots.select(&:visible)
            case id.to_s
            when 'toggle_clouds' then overlay.enabled?
            when 'toggle_active'
                active = slots.find { |slot| slot.id == session.active_slot_id } || slots.first
                active && active.visible && overlay.enabled? ? true : false
            when 'draw_clip'     then !session.clip_draw_tool.nil?
            when 'edit_clip'     then slots.any?(&:clip_editing)
            when 'toggle_clip'   then shown.any? { |slot| slot.clip && slot.clip['enabled'] }
            else
                mode = NA_COLOUR_MODES[id.to_s]
                mode && !shown.empty? && shown.all? { |slot| slot.display && slot.display['colourMode'] == mode } ? true : false
            end
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Helpers
    # -------------------------------------------------------------------------

        def self.na_session
            Na__ModelRegistry.Na__Registry__ActiveSession
        end

        def self.na_no_overlay
            ['The point cloud overlay is not available for this model (SketchUp 2023 or newer is required).', 'warn']
        end

        def self.na_no_clouds
            ['There is no point cloud in this model yet. Open the Point Cloud Viewer to import one.', 'warn']
        end

        # " Interior is not loaded yet: Reload on the View tab loads it."
        def self.na_not_loaded_note(slots)
            waiting = slots.reject(&:cloud)
            return '' if waiting.empty?
            one = waiting.length == 1
            " #{Na__ClipBox.Na__Clip__Names(waiting)} #{one ? 'is' : 'are'} not loaded yet: Reload on the View tab loads #{one ? 'it' : 'them'}."
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
