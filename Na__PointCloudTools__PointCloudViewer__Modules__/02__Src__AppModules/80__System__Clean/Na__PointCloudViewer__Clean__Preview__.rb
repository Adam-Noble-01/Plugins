# =============================================================================
# NA POINT CLOUD VIEWER - CLEAN - PREVIEW
# =============================================================================
#
# FILE       : Na__PointCloudViewer__Clean__Preview__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__CleanPreview
# PURPOSE    : The Clean tab's live preview of the three filters inside the
#              clip box, drawn by the existing renderer.
#
# NEVER ON THE MAIN THREAD: the engine's cleaning context owns one worker
#   thread per loaded cloud. Ruby only sends a request (a few numbers) and
#   polls on a short timer; a newer request cancels and replaces the running
#   one, and the engine re-uses every stage whose inputs did not change.
#   Changes are debounced (clean.preview.debounceSeconds) so dragging a slider
#   sends one request, not fifty.
#
# THE REGION is the clip box (model inches, axis-aligned in the model): the
#   engine maps it into the cloud's own coordinates with the cloud's current
#   placement, reads the box plus a halo around it, and cleans the points in
#   the box exactly as a run over the whole cloud would (tested bit for bit).
#   With clipping off there is no preview; the export always cleans the
#   whole cloud whatever the box.
#
# WHAT IS DRAWN: while the Clean tab is the active tab and a preview exists,
#   the renderer draws the preview's own cloud of the box instead of the
#   loaded cloud: Cleaned (kept points at their refined positions) or
#   Differences (every point coloured by what happened to it). Original
#   draws the loaded cloud as usual. Leaving the tab always shows the loaded
#   cloud again. Nothing here changes the loaded cloud or any file.
#
# ONE CLOUD AT A TIME (v0.10.0): each cloud keeps its own preview state, but
#   only the ACTIVE cloud previews, and only while the Clean tab shows. The
#   other clouds on show are drawn as they are. Choosing another cloud cancels
#   the old one's running preview and starts the new one's.
#
# =============================================================================

module Na__PointCloudViewer

    # -------------------------------------------------------------------------
    # REGION | State (one per cloud)
    # -------------------------------------------------------------------------

    class Na__CleanState

        # context        : the engine's cleaning context (Fiddle pointer)
        # context_cloud  : the Na__CloudData it was made for
        # request_id / request_key : the latest request and what it asked for
        # result_id / result_key   : the result shown and what it was for
        # state          : 'idle' | 'running' | 'done' | 'failed' | 'cancelled'
        # stats          : the shown result's statistics (engine Hash)
        # display        : 'cleaned' | 'original' | 'differences'
        # preview_clouds : { 'cleaned' => pointer, 'differences' => pointer }
        # tab_active     : (before v0.10.0; the session's clean_tab_active now)
        # schedule_serial: debounce counter (only the newest timer acts)
        # retry_load     : a published export whose loading failed or was cancelled
        # last_export    : the last export's summary for the Results card
        attr_accessor :context, :context_cloud, :request_id, :request_key, :requested_ms, :result_id, :result_key,
                      :result_ms, :state, :stats, :error, :display, :preview_clouds, :tab_active, :schedule_serial,
                      :poll_armed, :note, :retry_load, :last_export

        def initialize
            @state          = 'idle'
            @display        = 'cleaned'
            @preview_clouds = {}
            @tab_active     = false
            @schedule_serial = 0
            @poll_armed     = false
        end

    end

    # endregion ----------------------------------------------------------------

    module Na__CleanPreview

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_DISPLAYS = %w[cleaned original differences].freeze
        NA_SURFACE_NOTES = {
            1 => 'Several surfaces of similar size are in the box, so no single figure is reported. Move the clip box onto one wall, floor or ceiling.',
            2 => 'There is no dominant flat surface in the box (clutter, curves or openings), so no single figure is reported.',
            3 => 'Too few points in the box for a reliable figure.'
        }.freeze

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | State Access
    # -------------------------------------------------------------------------

        def self.Na__Clean__State(slot)
            slot.clean_state ||= Na__CleanState.new
        end

        # Previews run for the active cloud while the Clean tab shows.
        def self.na_previewing?(slot)
            session = slot ? slot.session : nil
            session && session.clean_tab_active && Na__CloudSet.Na__Slots__Active(session).equal?(slot) ? true : false
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Events (tab, settings, clip box, placement, cloud)
    # -------------------------------------------------------------------------

        # The dialog's tab changed (ui_remember_tab) or the dialog closed.
        # session: the model's session (the tab shows one cloud: the active one).
        def self.Na__Clean__SetTabActive(session, active)
            return unless session
            was = session.clean_tab_active ? true : false
            session.clean_tab_active = active ? true : false
            slot = Na__CloudSet.Na__Slots__Active(session)
            if session.clean_tab_active && !was
                self.Na__Clean__Schedule(slot, 0.0) if slot
            elsif !session.clean_tab_active && was
                Na__CloudSet.Na__Slots__All(session).each { |each_slot| self.na_cancel_running(each_slot) }
            end
            Na__CloudSet.na_invalidate(session)
        end

        # The active cloud changed: the old one's running preview stops, the
        # new one previews if the tab shows.
        def self.Na__Clean__ActiveChanged(session, previous, slot)
            self.na_cancel_running(previous) if previous && !previous.equal?(slot)
            self.Na__Clean__Schedule(slot, 0.0) if slot && session.clean_tab_active
        end

        def self.na_cancel_running(slot)
            state = slot ? slot.clean_state : nil
            Na__NativeEngine.Na__Native__CleanCancel(state.context) if state && state.context && state.state == 'running'
        end

        # Filter settings, clip box or placement changed: preview again soon.
        def self.Na__Clean__Changed(slot)
            return unless slot && self.na_previewing?(slot)
            self.Na__Clean__Schedule(slot, Na__ConfigLoader.Na__Config__GetOr(0.35, 'clean', 'preview', 'debounceSeconds').to_f)
        end

        # A different cloud (import, reload, unload) or a DLL swap: everything
        # made for the old one goes. Never touches a file.
        def self.Na__Clean__Reset(slot)
            state = slot ? slot.clean_state : nil
            return unless state
            self.na_release_previews(state)
            Na__NativeEngine.Na__Native__CleanDestroy(state.context) if state.context
            state.context = nil
            state.context_cloud = nil
            state.request_id = state.request_key = state.result_id = state.result_key = nil
            state.stats = nil
            state.error = nil
            state.note = nil
            state.state = 'idle'
            state.schedule_serial += 1
        end

        def self.Na__Clean__SetDisplay(slot, display)
            state = self.Na__Clean__State(slot)
            return 'Unknown view.' unless NA_DISPLAYS.include?(display.to_s)
            state.display = display.to_s
            self.na_invalidate(slot)
            nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Requests (debounced) + Poll
    # -------------------------------------------------------------------------

        def self.Na__Clean__Schedule(slot, delay)
            state = self.Na__Clean__State(slot)
            state.schedule_serial += 1
            serial = state.schedule_serial
            UI.start_timer([delay.to_f, 0.0].max, false) do
                Na__PointCloudViewer::Na__CleanPreview.na_scheduled(slot, serial)
            end
        end

        def self.na_scheduled(slot, serial)
            state = slot.clean_state
            return unless state && state.schedule_serial == serial && self.na_previewing?(slot)
            self.Na__Clean__RequestNow(slot)
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('The cleaning preview could not start.', error)
            state.state = 'failed' if state
            state.error = error.message if state
            self.na_push
        end

        # Sends the request now. Returns nil, or why there is no preview (also
        # kept in state.note for the dialog).
        def self.Na__Clean__RequestNow(slot)
            state = self.Na__Clean__State(slot)
            problem = self.na_preview_blocker(slot)
            state.note = problem
            if problem
                Na__NativeEngine.Na__Native__CleanCancel(state.context) if state.context
                state.state = 'idle' unless state.state == 'done'
                self.na_push
                self.na_invalidate(slot)
                return problem
            end
            self.na_ensure_context(slot)
            region = self.Na__Clean__Region(slot)
            params = Na__CleanSettings.Na__CleanSettings__EngineParams(Na__CleanSettings.Na__CleanSettings__MmPerUnit(slot.cloud))
            key = [region, params]
            return nil if key == state.request_key && %w[running done].include?(state.state)
            state.request_id   = Na__NativeEngine.Na__Native__CleanRequest(state.context, region, params)
            state.request_key  = key
            state.requested_ms = Na__PerfStats.Na__Perf__NowMs
            state.state        = 'running'
            state.error        = nil
            self.na_arm_poll(slot)
            self.na_push
            nil
        end

        # The clip box as the engine's region: frame = R k local + t (the
        # cloud's placement, model inches), box = the clip limits.
        def self.Na__Clean__Region(slot)
            cloud = slot.cloud
            m = cloud.local_to_model
            m[0, 9] + m[9, 3] + slot.clip['min'] + slot.clip['max'] + [cloud.unit_factor.to_f]
        end

        def self.na_arm_poll(slot)
            state = slot.clean_state
            return if state.poll_armed
            state.poll_armed = true
            delay = Na__ConfigLoader.Na__Config__GetOr(0.12, 'clean', 'preview', 'pollSeconds').to_f
            UI.start_timer(delay, false) { Na__PointCloudViewer::Na__CleanPreview.na_poll_tick(slot) }
        end

        def self.na_poll_tick(slot)
            state = slot.clean_state
            return unless state
            state.poll_armed = false
            return unless state.state == 'running' && Na__NativeEngine.Na__Native__CleanContextLive?(state.context)
            poll = Na__NativeEngine.Na__Native__CleanPoll(state.context)
            case poll['state']
            when 'done'
                return self.na_arm_poll(slot) unless poll['finishedId'] == state.request_id
                self.na_take_result(slot)
            when 'failed'
                state.state = 'failed'
                state.error = Na__NativeEngine.Na__Native__CleanError(state.context)
                self.na_push
            when 'cancelled', 'idle'
                state.state = 'cancelled'
                self.na_push
            else
                self.na_arm_poll(slot)
            end
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('The cleaning preview poll failed.', error)
            state.state = 'failed' if state
            state.error = error.message if state
            self.na_push
        end

        # A finished preview: its statistics and both display clouds (so the
        # Original / Cleaned / Differences switch is instant).
        def self.na_take_result(slot)
            state = slot.clean_state
            stats = Na__NativeEngine.Na__Native__CleanStats(state.context)
            self.na_release_previews(state)
            colours = self.na_diff_colours
            state.preview_clouds = {
                'cleaned'     => Na__NativeEngine.Na__Native__CleanPreviewCloud(state.context, 0, colours),
                'differences' => Na__NativeEngine.Na__Native__CleanPreviewCloud(state.context, 1, colours)
            }
            state.stats      = stats
            state.result_id  = state.request_id
            state.result_key = state.request_key
            state.result_ms  = stats ? stats['totalMs'] : nil
            state.state      = 'done'
            self.na_invalidate(slot)
            self.na_push
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Renderer Hook
    # -------------------------------------------------------------------------

        # The native cloud the renderer draws instead of the loaded one, or nil.
        def self.Na__Clean__DisplayCloud(slot)
            state = slot.clean_state
            return nil unless state && self.na_previewing?(slot) && state.result_id && state.display != 'original'
            return nil unless slot.cloud && state.context_cloud.equal?(slot.cloud)
            return nil unless Na__ClipBox.Na__Clip__IsActive?(slot)
            pointer = state.preview_clouds[state.display]
            Na__NativeEngine.Na__Native__CloudLive?(pointer) ? pointer : nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Dialog Payload
    # -------------------------------------------------------------------------

        def self.Na__Clean__Payload(slot, model)
            unless slot
                return { 'isAvailable' => true, 'hasCloud' => false, 'filters' => Na__CleanSettings.Na__CleanSettings__Payload,
                         'display' => 'cleaned', 'busy' => Na__AsyncJobs.Na__Jobs__Busy?, 'retryLoad' => nil, 'lastExport' => nil }
            end
            state = self.Na__Clean__State(slot)
            cloud = slot.cloud
            payload = {
                'isAvailable' => true,
                'cloudId'     => slot.id,
                'cloudName'   => slot.name,
                'inModel'     => true,
                'hasCloud'    => !cloud.nil?,
                'filters'     => Na__CleanSettings.Na__CleanSettings__Payload,
                'display'     => state.display,
                'busy'        => Na__AsyncJobs.Na__Jobs__Busy?,
                'retryLoad'   => state.retry_load ? { 'fileName' => File.basename(state.retry_load['path'].to_s), 'path' => state.retry_load['path'] } : nil,
                'lastExport'  => state.last_export
            }
            return payload unless cloud
            info = cloud.las_info || {}
            current_key = self.na_current_key(slot)
            payload.merge(
                'cloudName'     => cloud.label,
                'unitLabel'     => Na__UnitContract.Na__Units__SourceUnitLabel(cloud.source_unit),
                'mmPerUnit'     => Na__CleanSettings.Na__CleanSettings__MmPerUnit(cloud),
                'exportBlocker' => Na__CleanExport.Na__CleanExport__Blocker(slot),
                'suggestedName' => Na__CleanExport.Na__CleanExport__SuggestedName(cloud.source_path.to_s),
                'region'        => self.na_region_payload(slot),
                'preview'       => {
                    'state'      => state.state,
                    'error'      => state.error,
                    'note'       => state.note,
                    'hasResult'  => !state.result_id.nil?,
                    'isCurrent'  => !state.result_key.nil? && state.result_key == current_key,
                    'elapsedMs'  => state.state == 'running' && state.requested_ms ? (Na__PerfStats.Na__Perf__NowMs - state.requested_ms).round : nil,
                    'stats'      => state.stats,
                    'surfaceNoteText' => state.stats ? NA_SURFACE_NOTES[state.stats['surfaceNote'].to_i] : nil,
                    'showing'    => self.Na__Clean__DisplayCloud(slot) ? state.display : 'original'
                },
                'recordIdentity' => info['hasRecordIndex'] ? true : false
            )
        end

        def self.na_region_payload(slot)
            active = Na__ClipBox.Na__Clip__IsActive?(slot)
            return { 'clipOn' => false } unless active
            clip = slot.clip
            metres = (0..2).map { |i| (clip['max'][i] - clip['min'][i]) * 0.0254 }
            estimate = self.na_estimate_points(slot)
            large = Na__ConfigLoader.Na__Config__GetOr(3_000_000, 'clean', 'preview', 'largeBoxPoints').to_i
            {
                'clipOn'         => true,
                'sizeText'       => metres.map { |m| format('%.2f m', m) }.join(' x '),
                'estimatePoints' => estimate,
                'isLarge'        => estimate && estimate > large,
                'haloMm'         => slot.clean_state && slot.clean_state.stats ? slot.clean_state.stats['haloMm'] : nil
            }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals
    # -------------------------------------------------------------------------

        # nil, or why the box cannot be previewed now.
        def self.na_preview_blocker(slot)
            cloud = slot.cloud
            return "Load #{slot.name} first (View tab)." unless cloud
            unless cloud.native_cloud && cloud.native_generation == Na__NativeEngine.Na__Native__Generation &&
                   Na__NativeEngine.Na__Native__CloudLive?(cloud.native_cloud)
                return "The native engine was reloaded after #{slot.name} was loaded. Reload it (View tab) to preview."
            end
            return 'Turn the clip box on (Clipping tab) to choose the region to preview. Only the points inside it are previewed; Clean & Export always cleans the whole cloud.' unless Na__ClipBox.Na__Clip__IsActive?(slot)
            return 'Another task is running. The preview resumes when it finishes.' if Na__AsyncJobs.Na__Jobs__Busy?
            nil
        end

        def self.na_ensure_context(slot)
            state = slot.clean_state
            cloud = slot.cloud
            live = Na__NativeEngine.Na__Native__CleanContextLive?(state.context)
            return if live && state.context_cloud.equal?(cloud)
            self.Na__Clean__Reset(slot) if state.context || state.context_cloud
            state.context = Na__NativeEngine.Na__Native__CleanCreate(cloud.native_cloud, Na__CleanSettings.Na__CleanSettings__MmPerUnit(cloud))
            state.context_cloud = cloud
        end

        # What a request for the current settings and box would be (to tell
        # whether the shown result is current); nil when there is no box.
        def self.na_current_key(slot)
            return nil unless slot.cloud && Na__ClipBox.Na__Clip__IsActive?(slot)
            [self.Na__Clean__Region(slot), Na__CleanSettings.Na__CleanSettings__EngineParams(Na__CleanSettings.Na__CleanSettings__MmPerUnit(slot.cloud))]
        rescue StandardError
            nil
        end

        # About how many points are in the box: the cloud's count times the
        # share of its box volume inside the clip box (an even spread assumed).
        def self.na_estimate_points(slot)
            bounds = slot.cloud.bounds
            return nil unless bounds && !bounds.empty?
            lo = bounds.min.to_a
            hi = bounds.max.to_a
            clip = slot.clip
            inside = (0..2).map { |i| [[hi[i], clip['max'][i]].min - [lo[i], clip['min'][i]].max, 0.0].max }
            whole = (0..2).map { |i| [hi[i] - lo[i], 1e-9].max }
            share = inside.inject(:*) / whole.inject(:*)
            (slot.cloud.total_points * [[share, 0.0].max, 1.0].min).round
        end

        def self.na_diff_colours
            colours = Na__ConfigLoader.Na__Config__GetOr({}, 'render', 'cleanColours')
            colours = {} unless colours.is_a?(Hash)
            pick = ->(key, fallback) { colours[key].is_a?(Array) && colours[key].length == 3 ? colours[key] : fallback }
            pick.('removed', [214, 32, 32]) + pick.('movedSmall', [142, 197, 240]) + pick.('movedMax', [11, 60, 158]) +
                pick.('candidate', [240, 160, 0]) + pick.('doubling', [192, 0, 192]) + pick.('thinned', [200, 188, 168]) +
                pick.('unchangedTint', [230, 230, 230]) + [colours['tintShare'].is_a?(Numeric) ? colours['tintShare'].to_f : 0.6]
        end

        def self.na_release_previews(state)
            (state.preview_clouds || {}).each_value { |pointer| Na__NativeEngine.Na__Native__CloudRelease(pointer) if pointer }
            state.preview_clouds = {}
        end

        def self.na_invalidate(slot)
            model = slot ? slot.model : nil
            model.active_view.invalidate if model && model.valid? && model == Sketchup.active_model
        rescue StandardError
            nil
        end

        def self.na_push
            Na__DialogManager.Na__Dialog__PushState if Na__DialogManager.Na__Dialog__Visible?
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
