# =============================================================================
# NA POINT CLOUD VIEWER - APP CORE - MODEL REGISTRY
# =============================================================================
#
# FILE       : Na__PointCloudViewer__AppCore__ModelRegistry__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__ModelRegistry
# PURPOSE    : Gives every open model exactly one Na__CloudOverlay, and finds
#              the active model's cloud session.
#
# LEAK-PROOFING (hot reload):
#   - The AppObserver instance is stored `unless defined?` and added to
#     SketchUp once per session; a reload reopens its class instead.
#   - Overlays are found by id in model.overlays (the model is the registry),
#     so a reload never adds a second overlay - SketchUp would refuse the
#     duplicate id anyway.
#   - No Ruby-side hash of models is kept, so a closed model's overlay and
#     its point arrays are released with the model.
#
# =============================================================================

module Na__PointCloudViewer
    module Na__ModelRegistry

    # -------------------------------------------------------------------------
    # REGION | App Observer
    # -------------------------------------------------------------------------

        class Na__AppObserver < Sketchup::AppObserver

            def expectsStartupModelNotifications
                true
            end

            def onNewModel(model)
                Na__ModelRegistry.Na__Registry__EnsureOverlay(model)
                Na__ModelRegistry.na_notify_dialog
            end

            def onOpenModel(model)
                Na__ModelRegistry.Na__Registry__EnsureOverlay(model)
                Na__ModelRegistry.na_notify_dialog
            end

            def onActivateModel(_model)
                Na__ModelRegistry.na_notify_dialog
            end

        end

        # Clip and placement changes are undoable model operations; after
        # Undo/Redo both are re-read. Deferred: observers must not touch the model.
        class Na__ModelObserver < Sketchup::ModelObserver

            def onTransactionUndo(model)
                UI.start_timer(0, false) { Na__PointCloudViewer::Na__ModelRegistry.Na__Registry__ReloadModelState(model) }
            end

            def onTransactionRedo(model)
                UI.start_timer(0, false) { Na__PointCloudViewer::Na__ModelRegistry.Na__Registry__ReloadModelState(model) }
            end

        end

        @na_app_observer = nil unless defined?(@na_app_observer)

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Install
    # -------------------------------------------------------------------------

        def self.Na__Registry__InstallOnce
            unless @na_app_observer
                @na_app_observer = Na__AppObserver.new
                Sketchup.add_observer(@na_app_observer)
            end
            model = Sketchup.active_model
            self.Na__Registry__EnsureOverlay(model) if model
            true
        end

        def self.Na__Registry__OverlayId
            Na__ConfigLoader.Na__Config__GetOr('noble_architecture.point_cloud_viewer.cloud', 'overlay', 'id')
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Lookup
    # -------------------------------------------------------------------------

        def self.Na__Registry__FindOverlay(model)
            return nil unless model && model.respond_to?(:overlays)
            overlay_id = self.Na__Registry__OverlayId
            model.overlays.find { |overlay| overlay.overlay_id == overlay_id && overlay.valid? }
        end

        def self.Na__Registry__EnsureOverlay(model)
            return nil unless model && model.respond_to?(:overlays)
            overlay = self.Na__Registry__FindOverlay(model)
            unless overlay
                overlay = Na__CloudOverlay.new
                model.overlays.add(overlay)
            end
            self.na_bind_session(overlay, model)
            overlay
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('The point cloud overlay could not be registered for this model.', error)
            nil
        end

        # The session needs its model (clip state lives in the model) and one
        # ModelObserver per model. Both are idempotent, so reloads add nothing.
        def self.na_bind_session(overlay, model)
            session = overlay.na_session
            session.model ||= model
            return if overlay.instance_variable_get(:@na_model_observer)
            observer = Na__ModelObserver.new
            model.add_observer(observer)
            overlay.instance_variable_set(:@na_model_observer, observer)
        end

        # The model's stored clip state and cloud placement, read again.
        def self.Na__Registry__ReloadModelState(model)
            overlay = self.Na__Registry__FindOverlay(model)
            return unless overlay && overlay.respond_to?(:na_session)
            session = overlay.na_session
            Na__ClipBox.Na__Clip__Load(session)
            Na__Placement.Na__Placement__Reload(session)
            Na__LocalBackup.Na__Backup__AfterReload(model, session)
            Na__RenderController.Na__Render__RefreshExtents(session)
            model.active_view.invalidate
            Na__DialogManager.Na__Dialog__PushState if Na__DialogManager.Na__Dialog__Visible?
        end

        def self.Na__Registry__ActiveOverlay
            self.Na__Registry__EnsureOverlay(Sketchup.active_model)
        end

        def self.Na__Registry__ActiveSession
            overlay = self.Na__Registry__ActiveOverlay
            overlay && overlay.respond_to?(:na_session) ? overlay.na_session : nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Visibility (= overlay enabled state, shared with the Overlays panel)
    # -------------------------------------------------------------------------

        def self.Na__Registry__SetVisible(is_visible)
            overlay = self.Na__Registry__ActiveOverlay
            return false unless overlay
            overlay.enabled = is_visible ? true : false
            Sketchup.active_model.active_view.invalidate
            true
        end

        def self.Na__Registry__IsVisible?
            overlay = self.Na__Registry__FindOverlay(Sketchup.active_model)
            overlay ? overlay.enabled? : false
        end

        # Called from Overlay#start / #stop - including when the user flips the
        # overlay in SketchUp's own Overlays panel. Only UI sync happens here:
        # overlay events must never modify the model.
        def self.Na__Registry__OnOverlayToggled(_overlay, _is_enabled)
            self.na_notify_dialog
        end

        def self.na_notify_dialog
            return unless defined?(Na__DialogManager) && Na__DialogManager.Na__Dialog__Visible?
            UI.start_timer(0, false) { Na__PointCloudViewer::Na__DialogManager.Na__Dialog__PushState }
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
