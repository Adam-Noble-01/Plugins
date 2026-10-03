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
            'open_backups_folder'     => :na_open_backups_folder,
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

        def self.na_render_update_settings(payload)
            session = self.na_require_session
            return unless session
            Na__RenderController.Na__Render__ApplySettings(session, payload, Sketchup.active_model.active_view)
            Na__DialogManager.Na__Dialog__PushState
        end

        def self.na_render_set_visible(payload)
            Na__ModelRegistry.Na__Registry__SetVisible(payload['isVisible'] == true)
            Na__DialogManager.Na__Dialog__PushState
        end

        def self.na_view_zoom_to_cloud(_payload)
            session = self.na_require_session
            return unless session
            return Na__DialogManager.Na__Dialog__PushStatus('There is no point cloud to zoom to yet.', 'warn') unless session.cloud
            Na__RenderController.Na__Render__ZoomToCloud(session, Sketchup.active_model.active_view)
        end

        def self.na_cloud_unload(_payload)
            session = self.na_require_session
            return unless session
            Na__ClipBox.Na__Clip__StopEditing(session) if session.clip_editing
            Na__RenderController.Na__Render__ClearCloud(session, Sketchup.active_model.active_view)
            Na__DialogManager.Na__Dialog__PushState
            Na__DialogManager.Na__Dialog__PushStatus('Point cloud unloaded and its memory released. The LAS file is untouched.', 'success')
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
            self.na_clip_change { |session| Na__ClipBox.Na__Clip__SetEnabled(session, payload['enabled'] == true) }
        end

        def self.na_clip_reset(_payload)
            self.na_clip_change { |session| Na__ClipBox.Na__Clip__ResetToCloud(session) }
        end

        def self.na_clip_set_limits(payload)
            display = Na__UnitContract.Na__Units__ModelDisplay(Sketchup.active_model)
            values  = payload['limits'].is_a?(Hash) ? payload['limits'] : {}
            self.na_clip_change { |session| Na__ClipBox.Na__Clip__SetLimits(session, values, display) }
        end

        def self.na_clip_toggle_edit(_payload)
            self.na_clip_change do |session|
                session.clip_editing ? Na__ClipBox.Na__Clip__StopEditing(session) : Na__ClipBox.Na__Clip__StartEditing(session)
            end
        end

        def self.na_clip_scene_save(payload)
            self.na_clip_change { |session| Na__ClipBox.Na__Clip__SceneSave(session, payload['name']) }
        end

        def self.na_clip_scene_update(payload)
            self.na_clip_change { |session| Na__ClipBox.Na__Clip__SceneUpdate(session, payload['id']) }
        end

        def self.na_clip_scene_rename(payload)
            self.na_clip_change { |session| Na__ClipBox.Na__Clip__SceneRename(session, payload['id'], payload['name']) }
        end

        def self.na_clip_scene_delete(payload)
            self.na_clip_change { |session| Na__ClipBox.Na__Clip__SceneDelete(session, payload['id']) }
        end

        def self.na_clip_scene_activate(payload)
            self.na_clip_change { |session| Na__ClipBox.Na__Clip__SceneActivate(session, payload['id']) }
        end

        # Every clip and transform handler returns nil on success or a
        # plain-English reason, which is shown as a warning.
        def self.na_clip_change
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
            self.na_clip_change { |session| Na__Placement.Na__Placement__SetLocked(session, payload['locked'] == true) }
        end

        def self.na_transform_toggle_tool(payload)
            kind = payload['tool'] == 'rotate' ? 'rotate' : 'move'
            self.na_clip_change { |session| Na__Placement.Na__Placement__ToggleTool(session, kind) }
        end

        def self.na_transform_set_values(payload)
            display = Na__UnitContract.Na__Units__ModelDisplay(Sketchup.active_model)
            values  = payload['values'].is_a?(Hash) ? payload['values'] : {}
            self.na_clip_change { |session| Na__Placement.Na__Placement__SetValues(session, values, display) }
        end

        def self.na_transform_reset(_payload)
            self.na_clip_change { |session| Na__Placement.Na__Placement__Reset(session) }
        end

        def self.na_transform_pick_gimbal(_payload)
            self.na_clip_change { |session| Na__Placement.Na__Placement__PickGimbal(session) }
        end

        def self.na_transform_centre_gimbal(_payload)
            self.na_clip_change { |session| Na__Placement.Na__Placement__CentreGimbal(session) }
        end

        def self.na_transform_set_snap(payload)
            display = Na__UnitContract.Na__Units__ModelDisplay(Sketchup.active_model)
            self.na_clip_change { |_session| Na__Placement.Na__Placement__SetSnap(payload, display) }
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
        def self.na_link_reload(_payload)
            session = self.na_require_session
            return Na__DialogManager.Na__Dialog__SendJobFinished('failed', 'The point cloud overlay is not available.', {}) unless session
            problem = Na__ModelLink.Na__Link__Reload(session)
            Na__DialogManager.Na__Dialog__SendJobFinished('failed', problem, {}) if problem
        end

        def self.na_link_locate(_payload)
            session = self.na_require_session
            return unless session
            problem = Na__ModelLink.Na__Link__Locate(session)
            Na__DialogManager.Na__Dialog__PushStatus(problem, problem == 'Locate cancelled.' ? 'info' : 'warn') if problem
        end

        def self.na_link_restore_backup(_payload)
            restored = false
            self.na_clip_change do |session|
                problem = Na__ModelLink.Na__Link__RestoreBackup(session)
                restored = problem.nil?
                problem
            end
            Na__DialogManager.Na__Dialog__PushStatus('Restored the point cloud setup from this computer\'s backup. Undo puts it back.', 'success') if restored
        end

        def self.na_link_remove(_payload)
            self.na_clip_change { |session| Na__ModelLink.Na__Link__RemoveFromModel(session) }
        end

        def self.na_open_backups_folder(_payload)
            folder = Na__LocalBackup.Na__Backup__Folder
            FileUtils.mkdir_p(folder)
            Na__AssetResolver.Na__Paths__OpenInExplorer(folder)
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

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
