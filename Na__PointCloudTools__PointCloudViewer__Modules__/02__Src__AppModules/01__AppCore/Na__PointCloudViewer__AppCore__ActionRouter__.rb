# =============================================================================
# NA POINT CLOUD VIEWER - APP CORE - ACTION ROUTER
# =============================================================================
#
# FILE       : Na__PointCloudViewer__AppCore__ActionRouter__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__ActionRouter
# PURPOSE    : Every dialog request arrives as na_pcv_action(actionId, json)
#              and is routed here. Handlers are small; each reports back by
#              pushing state or a status line.
#
# ERROR POLICY:
#   The user sees a plain-English line in the status bar; the class, message
#   and backtrace go to the technical log (Settings > Technical Log).
#
# WHICH CLOUD (v0.10.0): the Clipping, Transform and Clean actions work on the
#   ACTIVE cloud (the one marked in the cloud bar). The cloud_* actions name
#   the cloud they act on by its id.
#
# =============================================================================

module Na__PointCloudViewer
    module Na__ActionRouter

    # -------------------------------------------------------------------------
    # REGION | Routing Table
    # -------------------------------------------------------------------------

        NA_HANDLERS = {
            'state_refresh'           => :na_state_refresh,
            'render_update_settings'  => :na_render_update_settings,
            'render_set_visible'      => :na_render_set_visible,
            'view_zoom_to_cloud'      => :na_view_zoom_to_cloud,
            'cloud_unload'            => :na_cloud_unload,
            'cloud_activate'          => :na_cloud_activate,
            'cloud_set_visible'       => :na_cloud_set_visible,
            'cloud_rename'            => :na_cloud_rename,
            'cloud_set_colour'        => :na_cloud_set_colour,
            'cloud_reload'            => :na_cloud_reload,
            'cloud_reload_all'        => :na_cloud_reload_all,
            'cloud_locate'            => :na_cloud_locate,
            'cloud_remove'            => :na_cloud_remove,
            'cloud_reorder'           => :na_cloud_reorder,
            'cloud_zoom'              => :na_cloud_zoom,
            'las_pick_file'           => :na_las_pick_file,
            'las_import_start'        => :na_las_import_start,
            'clip_set_enabled'        => :na_clip_set_enabled,
            'clip_reset'              => :na_clip_reset,
            'clip_set_limits'         => :na_clip_set_limits,
            'clip_toggle_edit'        => :na_clip_toggle_edit,
            'clip_scene_save'         => :na_clip_scene_save,
            'clip_scene_update'       => :na_clip_scene_update,
            'clip_scene_rename'       => :na_clip_scene_rename,
            'clip_scene_delete'       => :na_clip_scene_delete,
            'clip_scene_activate'     => :na_clip_scene_activate,
            'clip_scene_reorder'      => :na_clip_scene_reorder,
            'clip_copy_to_others'     => :na_clip_copy_to_others,
            'transform_set_locked'    => :na_transform_set_locked,
            'transform_toggle_tool'   => :na_transform_toggle_tool,
            'transform_set_values'    => :na_transform_set_values,
            'transform_reset'         => :na_transform_reset,
            'transform_pick_gimbal'   => :na_transform_pick_gimbal,
            'transform_centre_gimbal' => :na_transform_centre_gimbal,
            'transform_set_snap'      => :na_transform_set_snap,
            'config_export'           => :na_config_export,
            'link_reload'             => :na_link_reload,
            'link_locate'             => :na_link_locate,
            'link_restore_backup'     => :na_link_restore_backup,
            'link_remove'             => :na_link_remove,
            'clean_tab_active'        => :na_clean_tab_active,
            'clean_set_filter'        => :na_clean_set_filter,
            'clean_reset_defaults'    => :na_clean_reset_defaults,
            'clean_set_display'       => :na_clean_set_display,
            'clean_preview_now'       => :na_clean_preview_now,
            'clean_export'            => :na_clean_export,
            'clean_retry_load'        => :na_clean_retry_load,
            'boxes_remove_outside'    => :na_boxes_remove_outside,
            'boxes_remove_inside'     => :na_boxes_remove_inside,
            'boxes_update'            => :na_boxes_update,
            'boxes_rename'            => :na_boxes_rename,
            'boxes_delete'            => :na_boxes_delete,
            'boxes_delete_all'        => :na_boxes_delete_all,
            'boxes_show_in_clip'      => :na_boxes_show_in_clip,
            'boxes_set_view'          => :na_boxes_set_view,
            'boxes_export'            => :na_boxes_export,
            'scenes_add'              => :na_scenes_add,
            'scenes_update'           => :na_scenes_update,
            'scenes_remove'           => :na_scenes_remove,
            'scenes_relink'           => :na_scenes_relink,
            'scenes_recall'           => :na_scenes_recall,
            'scenes_set_export'       => :na_scenes_set_export,
            'scenes_reorder'          => :na_scenes_reorder,
            'open_backups_folder'     => :na_open_backups_folder,
            'cache_clear'             => :na_cache_clear,
            'job_cancel'              => :na_job_cancel,
            'settings_reload_plugin'  => :na_settings_reload_plugin,
            'open_cache_folder'       => :na_open_cache_folder,
            'open_user_config_folder' => :na_open_user_config_folder,
            'ui_remember_tab'         => :na_ui_remember_tab
        }.freeze

        def self.Na__Action__Dispatch(action_id, payload)
            handler = NA_HANDLERS[action_id]
            unless handler
                Na__DebugTools.Na__Debug__Warn("Unknown dialog action '#{action_id}'.")
                return
            end
            self.send(handler, payload)
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error("Dialog action '#{action_id}' failed.", error)
            message = "Sorry, that did not work (#{error.message}). Details are in Settings > Technical Log."
            # jobFinished also clears a loading overlay the page may have raised
            # for this action; with a job running only the status line changes.
            if Na__AsyncJobs.Na__Jobs__Busy?
                Na__DialogManager.Na__Dialog__PushStatus(message, 'error')
            else
                Na__DialogManager.Na__Dialog__SendJobFinished('failed', message, {})
            end
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | View Tab
    # -------------------------------------------------------------------------

        def self.na_state_refresh(_payload)
            Na__DialogManager.Na__Dialog__PushState
        end

        # The point budget is shared; the look (size, opacity, colour) is the
        # active cloud's, or the one named by 'cloudId'.
        def self.na_render_update_settings(payload)
            session = self.na_require_session
            return unless session
            slot = payload['cloudId'] ? Na__CloudSet.Na__Slots__Find(session, payload['cloudId']) : Na__CloudSet.Na__Slots__Active(session)
            settings = payload.reject { |key, _| key == 'cloudId' }
            Na__RenderController.Na__Render__ApplySettings(session, settings, Sketchup.active_model.active_view, slot)
            Na__DialogManager.Na__Dialog__PushState
        end

        def self.na_render_set_visible(payload)
            Na__ModelRegistry.Na__Registry__SetVisible(payload['isVisible'] == true)
            Na__DialogManager.Na__Dialog__PushState
        end

        # Frames every cloud on show (each one, or only its part inside its clip
        # box while it clips).
        def self.na_view_zoom_to_cloud(_payload)
            session = self.na_require_session
            return unless session
            return Na__DialogManager.Na__Dialog__PushStatus('There is no point cloud on show to zoom to.', 'warn') if Na__CloudSet.Na__Slots__Drawn(session).empty?
            Na__RenderController.Na__Render__ZoomToCloud(session, Sketchup.active_model.active_view)
        end

        def self.na_cloud_unload(payload)
            slot = self.na_slot_for(payload)
            return unless slot
            return Na__DialogManager.Na__Dialog__PushStatus("#{slot.name} is not loaded.", 'info') unless slot.cloud
            Na__ClipBox.Na__Clip__StopEditing(slot) if slot.clip_editing
            prefix = Na__CloudSet.Na__Slots__Prefix(slot)
            Na__RenderController.Na__Render__ClearCloud(slot, Sketchup.active_model.active_view)
            forgotten = Na__CloudSet.Na__Slots__ForgetUnsaved(slot)
            Na__DialogManager.Na__Dialog__PushState
            text = forgotten ? 'Point cloud unloaded. It was not saved in this model, so it leaves the list. The LAS file is untouched.' :
                               'Point cloud unloaded and its memory released. The LAS file is untouched; it stays in the model.'
            Na__DialogManager.Na__Dialog__PushStatus("#{prefix}#{text}", 'success')
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Point Clouds (the cloud bar and the View tab's list)
    # @delegate: 02__Src__AppModules/20__System__CloudSet/
    # -------------------------------------------------------------------------

        def self.na_cloud_activate(payload)
            slot = self.na_slot_for(payload, true)
            return unless slot
            note = Na__CloudSet.Na__Slots__Activate(slot.session, slot)
            Na__DialogManager.Na__Dialog__PushState
            Na__DialogManager.Na__Dialog__PushStatus(note || "Working on #{slot.name}.", note ? 'warn' : 'info')
        end

        def self.na_cloud_set_visible(payload)
            slot = self.na_slot_for(payload, true)
            return unless slot
            Na__CloudSet.Na__Slots__SetVisible(slot, payload['visible'] == true)
            Na__ModelRegistry.Na__Registry__SetVisible(true) if payload['visible'] == true && !Na__ModelRegistry.Na__Registry__IsVisible?
            Na__DialogManager.Na__Dialog__PushState
            unless slot.cloud
                Na__DialogManager.Na__Dialog__PushStatus("#{slot.name} is not loaded, so there is nothing to show yet. Press Reload on its row.", 'info') if payload['visible'] == true
            end
        end

        def self.na_cloud_rename(payload)
            slot = self.na_slot_for(payload, true)
            return unless slot
            self.na_cloud_change { Na__CloudSet.Na__Slots__Rename(slot, payload['name']) }
        end

        # colour: '#rrggbb' (one of the palette's).
        def self.na_cloud_set_colour(payload)
            slot = self.na_slot_for(payload, true)
            return unless slot
            hex = payload['colour'].to_s
            rgb = hex.match?(/\A#[0-9a-fA-F]{6}\z/) ? [hex[1, 2], hex[3, 2], hex[5, 2]].map { |part| part.to_i(16) } : nil
            self.na_cloud_change { Na__CloudSet.Na__Slots__SetColour(slot, rgb) }
        end

        # The page raised its loading overlay before calling; a refusal must
        # clear it, so it is reported as a finished (failed) job.
        def self.na_cloud_reload(payload)
            slot = self.na_slot_for(payload, true)
            return Na__DialogManager.Na__Dialog__SendJobFinished('failed', 'That point cloud is no longer in this model.', {}) unless slot
            problem = Na__ModelLink.Na__Link__Reload(slot)
            Na__DialogManager.Na__Dialog__SendJobFinished('failed', "#{Na__CloudSet.Na__Slots__Prefix(slot)}#{problem}", {}) if problem
        end

        def self.na_cloud_reload_all(_payload)
            session = self.na_require_session
            return Na__DialogManager.Na__Dialog__SendJobFinished('failed', 'The point cloud overlay is not available.', {}) unless session
            problem = Na__ModelLink.Na__Link__ReloadAll(session)
            Na__DialogManager.Na__Dialog__SendJobFinished('failed', problem, {}) if problem
        end

        def self.na_cloud_locate(payload)
            slot = self.na_slot_for(payload, true)
            return unless slot
            problem = Na__ModelLink.Na__Link__Locate(slot)
            Na__DialogManager.Na__Dialog__PushStatus(problem, problem == 'Locate cancelled.' ? 'info' : 'warn') if problem
        end

        def self.na_cloud_remove(payload)
            slot = self.na_slot_for(payload, true)
            return unless slot
            name = slot.name
            problem = Na__CloudSet.Na__Slots__Remove(slot)
            Na__DialogManager.Na__Dialog__PushState
            if problem
                Na__DialogManager.Na__Dialog__PushStatus(problem, 'warn')
            else
                Na__DialogManager.Na__Dialog__PushStatus("#{name} was taken out of the model. Its LAS file and point cache are untouched; Edit, Undo puts it back.", 'success')
            end
        end

        def self.na_cloud_reorder(payload)
            session = self.na_require_session
            return unless session
            self.na_cloud_change { Na__CloudSet.Na__Slots__Reorder(session, payload['ids']) }
        end

        def self.na_cloud_zoom(payload)
            slot = self.na_slot_for(payload, true)
            return unless slot
            return Na__DialogManager.Na__Dialog__PushStatus("#{slot.name} is not loaded, so there is nothing to zoom to.", 'warn') unless slot.cloud
            Na__RenderController.Na__Render__ZoomToCloud(slot, Sketchup.active_model.active_view)
        end

        def self.na_cloud_change
            problem = yield
            Na__DialogManager.Na__Dialog__PushState
            Na__DialogManager.Na__Dialog__PushStatus(problem, 'warn') if problem
        end

        # @delegate: 02__Src__AppModules/40__System__LasImport/Na__PointCloudViewer__LasImport__Controller__.rb
        def self.na_las_pick_file(_payload)
            Na__LasImport.Na__LasImport__PickAndInspect
        end

        def self.na_las_import_start(payload)
            Na__LasImport.Na__LasImport__Start(payload)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Clipping Tab
    # @delegate: 02__Src__AppModules/50__System__ClipBox/Na__PointCloudViewer__ClipBox__State__.rb
    # -------------------------------------------------------------------------

        def self.na_clip_set_enabled(payload)
            self.na_clip_change { |slot| Na__ClipBox.Na__Clip__SetEnabled(slot, payload['enabled'] == true) }
        end

        def self.na_clip_reset(_payload)
            self.na_clip_change { |slot| Na__ClipBox.Na__Clip__ResetToCloud(slot) }
        end

        def self.na_clip_set_limits(payload)
            display = Na__UnitContract.Na__Units__ModelDisplay(Sketchup.active_model)
            values  = payload['limits'].is_a?(Hash) ? payload['limits'] : {}
            self.na_clip_change { |slot| Na__ClipBox.Na__Clip__SetLimits(slot, values, display) }
        end

        def self.na_clip_toggle_edit(_payload)
            self.na_clip_change do |slot|
                slot && slot.clip_editing ? Na__ClipBox.Na__Clip__StopEditing(slot) : Na__ClipBox.Na__Clip__StartEditing(slot)
            end
        end

        def self.na_clip_copy_to_others(_payload)
            done = false
            self.na_clip_change do |slot|
                problem = Na__ClipBox.Na__Clip__CopyToOthers(slot)
                done = problem.nil?
                problem
            end
            Na__DialogManager.Na__Dialog__PushStatus('Every other point cloud now has this clip box. Edit, Undo puts their own boxes back.', 'success') if done
        end

        def self.na_clip_scene_save(payload)
            self.na_clip_change { |slot| Na__ClipBox.Na__Clip__SceneSave(slot, payload['name']) }
        end

        def self.na_clip_scene_update(payload)
            self.na_clip_change { |slot| Na__ClipBox.Na__Clip__SceneUpdate(slot, payload['id']) }
        end

        def self.na_clip_scene_rename(payload)
            self.na_clip_change { |slot| Na__ClipBox.Na__Clip__SceneRename(slot, payload['id'], payload['name']) }
        end

        def self.na_clip_scene_delete(payload)
            self.na_clip_change { |slot| Na__ClipBox.Na__Clip__SceneDelete(slot, payload['id']) }
        end

        def self.na_clip_scene_activate(payload)
            self.na_clip_change { |slot| Na__ClipBox.Na__Clip__SceneActivate(slot, payload['id']) }
        end

        def self.na_clip_scene_reorder(payload)
            self.na_clip_change { |slot| Na__ClipBox.Na__Clip__SceneReorder(slot, payload['ids']) }
        end

        # Every clip and transform handler is handed the ACTIVE cloud's slot (nil
        # when the model has none) and returns nil on success or a plain-English
        # reason, which is shown as a warning.
        def self.na_clip_change
            session = self.na_require_session
            return unless session
            slot = Na__CloudSet.Na__Slots__Active(session)
            problem = yield(slot)
            Na__RenderController.Na__Render__RefreshExtents(session)
            Sketchup.active_model.active_view.invalidate
            Na__DialogManager.Na__Dialog__PushState
            Na__DialogManager.Na__Dialog__PushStatus(problem, 'warn') if problem
        end

        # The same, for the handlers that act on the whole model (scenes,
        # backups): handed the session.
        def self.na_model_change
            session = self.na_require_session
            return unless session
            problem = yield(session)
            Na__RenderController.Na__Render__RefreshExtents(session)
            Sketchup.active_model.active_view.invalidate
            Na__DialogManager.Na__Dialog__PushState
            Na__DialogManager.Na__Dialog__PushStatus(problem, 'warn') if problem
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Transform Tab
    # @delegate: 02__Src__AppModules/60__System__Transform/Na__PointCloudViewer__Transform__Placement__.rb
    # -------------------------------------------------------------------------

        def self.na_transform_set_locked(payload)
            self.na_clip_change { |slot| Na__Placement.Na__Placement__SetLocked(slot, payload['locked'] == true) }
        end

        def self.na_transform_toggle_tool(payload)
            kind = payload['tool'] == 'rotate' ? 'rotate' : 'move'
            self.na_clip_change { |slot| Na__Placement.Na__Placement__ToggleTool(slot, kind) }
        end

        def self.na_transform_set_values(payload)
            display = Na__UnitContract.Na__Units__ModelDisplay(Sketchup.active_model)
            values  = payload['values'].is_a?(Hash) ? payload['values'] : {}
            self.na_clip_change { |slot| Na__Placement.Na__Placement__SetValues(slot, values, display) }
        end

        def self.na_transform_reset(_payload)
            self.na_clip_change { |slot| Na__Placement.Na__Placement__Reset(slot) }
        end

        def self.na_transform_pick_gimbal(_payload)
            self.na_clip_change { |slot| Na__Placement.Na__Placement__PickGimbal(slot) }
        end

        def self.na_transform_centre_gimbal(_payload)
            self.na_clip_change { |slot| Na__Placement.Na__Placement__CentreGimbal(slot) }
        end

        def self.na_transform_set_snap(payload)
            display = Na__UnitContract.Na__Units__ModelDisplay(Sketchup.active_model)
            self.na_clip_change { |_slot| Na__Placement.Na__Placement__SetSnap(payload, display) }
        end

        def self.na_config_export(_payload)
            session = self.na_require_session
            return unless session
            path = Na__ConfigExport.Na__Export__Run(session, Sketchup.active_model)
            return Na__DialogManager.Na__Dialog__PushStatus('Export cancelled.', 'info') unless path
            Na__DialogManager.Na__Dialog__PushStatus("Configuration exported to #{File.basename(path)}.", 'success')
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Model Link (persistence): every one an explicit user action
    # @delegate: 02__Src__AppModules/70__System__Persistence/Na__PointCloudViewer__Persistence__ModelLink__.rb
    # -------------------------------------------------------------------------

        # The page raised its loading overlay before calling; a refusal must
        # clear it, so it is reported as a finished (failed) job.
        # Reload: every cloud of the model that is not loaded.
        def self.na_link_reload(_payload)
            self.na_cloud_reload_all({})
        end

        # Locate: the active cloud's LAS.
        def self.na_link_locate(_payload)
            self.na_cloud_locate({})
        end

        def self.na_link_restore_backup(_payload)
            restored = false
            self.na_model_change do |session|
                problem = Na__ModelLink.Na__Link__RestoreBackup(session)
                restored = problem.nil?
                problem
            end
            Na__DialogManager.Na__Dialog__PushStatus('Restored the point cloud setup from this computer\'s backup. Undo puts it back.', 'success') if restored
        end

        def self.na_link_remove(_payload)
            self.na_model_change { |session| Na__ModelLink.Na__Link__RemoveFromModel(session) }
        end

        # Loaded clouds are unaffected (they live in memory); the next Reload
        # reads the LAS and writes a new cache.
        def self.na_cache_clear(_payload)
            removed = Na__PointCache.Na__Cache__Clear
            Na__DialogManager.Na__Dialog__PushState
            Na__DialogManager.Na__Dialog__PushStatus(removed.zero? ? 'There were no point caches to clear.' : "Cleared #{removed} point cache file#{removed == 1 ? '' : 's'}. They rebuild from the LAS on the next import or Reload.", 'success')
        end

        def self.na_open_backups_folder(_payload)
            folder = Na__LocalBackup.Na__Backup__Folder
            FileUtils.mkdir_p(folder)
            Na__AssetResolver.Na__Paths__OpenInExplorer(folder)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Clean Tab
    # @delegate: 02__Src__AppModules/80__System__Clean/
    # -------------------------------------------------------------------------

        def self.na_clean_tab_active(payload)
            session = Na__ModelRegistry.Na__Registry__ActiveSession
            Na__CleanPreview.Na__Clean__SetTabActive(session, payload['active'] == true) if session
            Na__DialogManager.Na__Dialog__PushState
        end

        def self.na_clean_set_filter(payload)
            problem = Na__CleanSettings.Na__CleanSettings__Apply(payload)
            slot = Na__ModelRegistry.Na__Registry__ActiveSlot
            Na__CleanPreview.Na__Clean__Changed(slot) if slot && !problem
            Na__DialogManager.Na__Dialog__PushState
            Na__DialogManager.Na__Dialog__PushStatus(problem, 'warn') if problem
        end

        def self.na_clean_reset_defaults(_payload)
            Na__CleanSettings.Na__CleanSettings__Reset
            slot = Na__ModelRegistry.Na__Registry__ActiveSlot
            Na__CleanPreview.Na__Clean__Changed(slot) if slot
            Na__DialogManager.Na__Dialog__PushState
            Na__DialogManager.Na__Dialog__PushStatus('The three filters are back to their default settings.', 'success')
        end

        def self.na_clean_set_display(payload)
            slot = self.na_slot_for({}, true)
            return unless slot
            problem = Na__CleanPreview.Na__Clean__SetDisplay(slot, payload['display'])
            Na__DialogManager.Na__Dialog__PushState
            Na__DialogManager.Na__Dialog__PushStatus(problem, 'warn') if problem
        end

        def self.na_clean_preview_now(_payload)
            slot = self.na_slot_for({}, true)
            return unless slot
            state = Na__CleanPreview.Na__Clean__State(slot)
            state.request_key = nil        # run it again even if nothing changed
            problem = Na__CleanPreview.Na__Clean__RequestNow(slot)
            Na__DialogManager.Na__Dialog__PushStatus(problem, 'warn') if problem
        end

        # Opens Save As (modal) first, so the page raises no overlay before
        # calling; the job then reports progress like an import.
        def self.na_clean_export(_payload)
            slot = self.na_slot_for({}, true)
            return unless slot
            problem = Na__CleanExport.Na__CleanExport__Start(slot)
            return unless problem
            if problem == 'cancelled'
                Na__DialogManager.Na__Dialog__PushStatus('Export cancelled. Nothing was written.', 'info')
            else
                Na__DialogManager.Na__Dialog__PushStatus(problem, 'warn')
            end
        end

        def self.na_clean_retry_load(_payload)
            slot = self.na_slot_for({}, true)
            return unless slot
            problem = Na__CleanExport.Na__CleanExport__RetryLoad(slot)
            Na__DialogManager.Na__Dialog__PushStatus(problem, 'warn') if problem
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Clean Tab: Crop and Cut (the active cloud's boxes)
    # @delegate: 02__Src__AppModules/80__System__Clean/Na__PointCloudViewer__Clean__Boxes__.rb
    # -------------------------------------------------------------------------

        def self.na_boxes_remove_outside(_payload)
            self.na_boxes_capture('outside') { |slot| Na__CleanBoxes.Na__Boxes__RemoveOutside(slot) }
        end

        def self.na_boxes_remove_inside(_payload)
            self.na_boxes_capture('inside') { |slot| Na__CleanBoxes.Na__Boxes__RemoveInside(slot) }
        end

        # A capture says what it did (the clip change handler only warns).
        def self.na_boxes_capture(kind)
            captured = nil
            self.na_clip_change do |slot|
                problem = yield(slot)
                captured = slot unless problem
                problem
            end
            Na__DialogManager.Na__Dialog__PushStatus(Na__CleanBoxes.Na__Boxes__CaptureMessage(captured, kind), 'success') if captured
        end

        def self.na_boxes_update(payload)
            self.na_clip_change { |slot| Na__CleanBoxes.Na__Boxes__Update(slot, payload['id']) }
        end

        def self.na_boxes_rename(payload)
            self.na_clip_change { |slot| Na__CleanBoxes.Na__Boxes__Rename(slot, payload['id'], payload['name']) }
        end

        def self.na_boxes_delete(payload)
            self.na_clip_change { |slot| Na__CleanBoxes.Na__Boxes__Delete(slot, payload['id']) }
        end

        def self.na_boxes_delete_all(_payload)
            done = false
            self.na_clip_change do |slot|
                problem = Na__CleanBoxes.Na__Boxes__DeleteAll(slot)
                done = problem.nil?
                problem
            end
            Na__DialogManager.Na__Dialog__PushStatus('Every Crop and Cut box of this cloud was deleted. Edit, Undo brings them back.', 'success') if done
        end

        def self.na_boxes_show_in_clip(payload)
            note = nil
            self.na_clip_change do |slot|
                problem, note = Na__CleanBoxes.Na__Boxes__ShowInClip(slot, payload['id'])
                problem
            end
            Na__DialogManager.Na__Dialog__PushStatus(note, 'info') if note
        end

        def self.na_boxes_set_view(payload)
            self.na_clip_change { |slot| slot ? Na__CleanBoxes.Na__Boxes__SetView(slot, payload['view']) : 'There is no point cloud in this model yet.' }
        end

        # Opens Save As (modal) first, so the page raises no overlay before
        # calling; the job then reports progress like Clean & Export.
        def self.na_boxes_export(_payload)
            slot = self.na_slot_for({}, true)
            return unless slot
            problem = Na__CleanBoxes.Na__Boxes__ExportStart(slot)
            return unless problem
            if problem == 'cancelled'
                Na__DialogManager.Na__Dialog__PushStatus('Export cancelled. Nothing was written.', 'info')
            else
                Na__DialogManager.Na__Dialog__PushStatus(problem, 'warn')
            end
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Scenes Tab
    # @delegate: 02__Src__AppModules/90__System__Scenes/
    # -------------------------------------------------------------------------

        def self.na_scenes_add(payload)
            view = Sketchup.active_model.active_view
            self.na_model_change { |session| Na__SceneStore.Na__Scenes__Add(session, payload['pid'], view) }
        end

        def self.na_scenes_update(payload)
            view = Sketchup.active_model.active_view
            self.na_model_change { |session| Na__SceneStore.Na__Scenes__Update(session, payload['id'], view) }
        end

        def self.na_scenes_remove(payload)
            self.na_model_change { |session| Na__SceneStore.Na__Scenes__Remove(session, payload['id']) }
        end

        def self.na_scenes_relink(payload)
            self.na_model_change { |session| Na__SceneStore.Na__Scenes__Relink(session, payload['id'], payload['pid']) }
        end

        def self.na_scenes_recall(payload)
            view = Sketchup.active_model.active_view
            self.na_model_change { |session| Na__SceneRecall.Na__Scenes__Recall(session, payload['id'], view) }
        end

        def self.na_scenes_set_export(payload)
            values = payload['values'].is_a?(Hash) ? payload['values'] : {}
            self.na_model_change { |session| Na__SceneStore.Na__Scenes__SetExport(session, payload['id'], values) }
        end

        def self.na_scenes_reorder(payload)
            self.na_model_change { |session| Na__SceneStore.Na__Scenes__Reorder(session, payload['ids']) }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Jobs + Settings Tab
    # -------------------------------------------------------------------------

        def self.na_job_cancel(_payload)
            Na__AsyncJobs.Na__Jobs__RequestCancel
        end

        def self.na_settings_reload_plugin(_payload)
            Na__DialogManager.Na__Dialog__ReloadPlugin
        end

        def self.na_open_cache_folder(_payload)
            Na__AssetResolver.Na__Paths__OpenInExplorer(Na__AssetResolver.Na__Paths__CacheFolder)
        end

        def self.na_open_user_config_folder(_payload)
            Na__AssetResolver.Na__Paths__OpenInExplorer(Na__AssetResolver.Na__Paths__UserConfigFolder)
        end

        def self.na_ui_remember_tab(payload)
            tab_id = payload['tabId'].to_s
            Na__UserConfigStore.Na__UserConfig__Set('ui', 'activeTab', tab_id) unless tab_id.empty?
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Helpers
    # -------------------------------------------------------------------------

        def self.na_require_session
            session = Na__ModelRegistry.Na__Registry__ActiveSession
            return session if session
            Na__DialogManager.Na__Dialog__PushStatus('The point cloud overlay is not available for this model (SketchUp 2023 or newer is required).', 'error')
            nil
        end

        # The cloud named by payload['cloudId'] (or 'id'), else the active one.
        # say: tell the user when there is none.
        def self.na_slot_for(payload, say = true)
            session = self.na_require_session
            return nil unless session
            id = payload['cloudId'] || payload['id']
            slot = id ? Na__CloudSet.Na__Slots__Find(session, id) : Na__CloudSet.Na__Slots__Active(session)
            return slot if slot
            if say
                message = id ? 'That point cloud is no longer in this model.' : 'There is no point cloud in this model yet. Import one first.'
                Na__DialogManager.Na__Dialog__PushStatus(message, 'warn')
            end
            nil
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
