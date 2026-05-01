# =============================================================================
# NA ARRAY BUILDER TOOLS - MODEL OBSERVERS
# =============================================================================
#
# FILE       : Na__ArrayBuilder__ModelObservers__.rb
# NAMESPACE  : Na__ArrayBuilderTools::Na__ArrayBuilder__ModelObservers
# AUTHOR     : Noble Architecture
# PURPOSE    : Keep Na__ArrayBuilder__ObjectRegistry consistent with the
#              currently-active SketchUp model, so the picked source-object
#              reference cannot go stale across model switches or after the
#              picked component definition is deleted.
# CREATED    : 2026
# VERSION    : 0.0.5
#
# DESCRIPTION:
# - Na__ArrayBuilder__AppObserver  watches Sketchup app-level events
#   (onNewModel / onOpenModel / onActivateModel) and clears the registry
#   whenever the active model changes, then re-attaches a definitions
#   observer to the new active model.
# - Na__ArrayBuilder__DefinitionsObserver watches the active model's
#   definition list and clears the registry only when the SPECIFIC
#   currently-stored definition is removed.
# - Both observers notify the dialog (via na_send_object_cleared) so the
#   Object Source panel never displays a stale picked-object name or
#   bounding-box dimensions.
# - Na__Observers__InstallOnce is idempotent: safe to call from the
#   plugin loader with file_loaded? guard already in place; an extra
#   guard inside the function prevents double-registration if the
#   loader is reloaded mid-session.
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__ArrayBuilder__ObjectRegistry__'

module Na__ArrayBuilderTools
    module Na__ArrayBuilder__ModelObservers

# -----------------------------------------------------------------------------
# REGION | Internal State
# -----------------------------------------------------------------------------

        @na_app_observer        = nil
        @na_definitions_obs     = nil
        @na_attached_definitions = nil

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Installation
# -----------------------------------------------------------------------------

        # FUNCTION | Install Observers Once (Idempotent)
        # ------------------------------------------------------------
        # Called from Na__ArrayBuilderTools__Loader.rb. Safe to call
        # repeatedly (e.g. during script reloads) - existing observers
        # are detached and re-installed cleanly.
        def self.Na__Observers__InstallOnce
            Na__Observers__UninstallExisting()

            @na_app_observer = Na__ArrayBuilder__AppObserver.new
            Sketchup.add_observer(@na_app_observer)

            current_model = Sketchup.active_model
            Na__Observers__AttachDefinitionsObserver(current_model) if current_model
        end
        # ---------------------------------------------------------------

        # FUNCTION | Uninstall Existing Observers (Internal)
        # ------------------------------------------------------------
        def self.Na__Observers__UninstallExisting
            if @na_app_observer
                begin
                    Sketchup.remove_observer(@na_app_observer)
                rescue StandardError => e
                    Na__ArrayBuilderTools.na_debug_log("failed to remove AppObserver: #{e.message}")
                end
                @na_app_observer = nil
            end

            Na__Observers__DetachDefinitionsObserver()
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Definitions Observer Attach / Detach
# -----------------------------------------------------------------------------

        # FUNCTION | Attach Definitions Observer to a Model
        # ------------------------------------------------------------
        # Detaches any prior attachment first so we never end up with
        # two observers on the same definition list.
        def self.Na__Observers__AttachDefinitionsObserver(model)
            return unless model

            Na__Observers__DetachDefinitionsObserver()

            @na_definitions_obs      = Na__ArrayBuilder__DefinitionsObserver.new
            @na_attached_definitions = model.definitions
            @na_attached_definitions.add_observer(@na_definitions_obs)
        rescue StandardError => e
            Na__ArrayBuilderTools.na_debug_log("failed to attach DefinitionsObserver: #{e.message}")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Detach Definitions Observer From the Last Model
        # ------------------------------------------------------------
        def self.Na__Observers__DetachDefinitionsObserver
            return unless @na_definitions_obs && @na_attached_definitions

            begin
                @na_attached_definitions.remove_observer(@na_definitions_obs)
            rescue StandardError => e
                Na__ArrayBuilderTools.na_debug_log("failed to detach DefinitionsObserver: #{e.message}")
            end

            @na_definitions_obs      = nil
            @na_attached_definitions = nil
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Registry + Dialog Notification
# -----------------------------------------------------------------------------

        # FUNCTION | Clear Registry and Push Cleared State to Dialog
        # ------------------------------------------------------------
        # Single point of contact for "the picked object is no longer
        # valid". Safe to call when the dialog has not been opened.
        def self.Na__Observers__ClearRegistryAndNotifyDialog
            Na__ArrayBuilder__ObjectRegistry.Na__Registry__Clear
            Na__Observers__NotifyDialogIfPresent()
        end
        # ---------------------------------------------------------------

        # FUNCTION | Notify Dialog If It Is Loaded and Visible
        # ------------------------------------------------------------
        # Resolved at call time (not stored) because DialogManager is
        # required after this file in the loader chain.
        def self.Na__Observers__NotifyDialogIfPresent
            return unless defined?(Na__ArrayBuilder__DialogManager)
            Na__ArrayBuilder__DialogManager.na_send_object_cleared
        rescue StandardError => e
            Na__ArrayBuilderTools.na_debug_log("dialog notify failed: #{e.message}")
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__ArrayBuilder__ModelObservers

# =============================================================================
# REGION | App Observer (Model Switch Events)
# =============================================================================

    class Na__ArrayBuilder__AppObserver < Sketchup::AppObserver

        # FUNCTION | Handle New Model Created
        # ------------------------------------------------------------
        def onNewModel(model)
            Na__ArrayBuilder__AppObserver__HandleModelChange(model)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Handle Model Opened From Disk
        # ------------------------------------------------------------
        def onOpenModel(model)
            Na__ArrayBuilder__AppObserver__HandleModelChange(model)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Handle Active Model Changed (Mac Multi-Tab)
        # ------------------------------------------------------------
        def onActivateModel(model)
            Na__ArrayBuilder__AppObserver__HandleModelChange(model)
        end
        # ---------------------------------------------------------------

        private

        # FUNCTION | Common Path: Re-Attach Definitions Observer + Clear
        # ------------------------------------------------------------
        # The previous model's ComponentDefinition reference cannot be
        # used in the new model (definitions are model-scoped), so the
        # registry is always cleared on a model change.
        def Na__ArrayBuilder__AppObserver__HandleModelChange(model)
            Na__ArrayBuilder__ModelObservers
                .Na__Observers__AttachDefinitionsObserver(model)
            Na__ArrayBuilder__ModelObservers
                .Na__Observers__ClearRegistryAndNotifyDialog
        end
        # ---------------------------------------------------------------

    end # class Na__ArrayBuilder__AppObserver

# endregion ===================================================================

# =============================================================================
# REGION | Definitions Observer (Component Removal)
# =============================================================================

    class Na__ArrayBuilder__DefinitionsObserver < Sketchup::DefinitionsObserver

        # FUNCTION | Handle Component Definition Removed
        # ------------------------------------------------------------
        # Only clears the registry when the removed definition matches
        # the one the user picked - other component deletions are no-op.
        def onComponentRemoved(_definitions, definition)
            stored = Na__ArrayBuilder__ObjectRegistry.Na__Registry__GetDefinition
            return unless stored
            return unless stored == definition

            Na__ArrayBuilder__ModelObservers
                .Na__Observers__ClearRegistryAndNotifyDialog
        end
        # ---------------------------------------------------------------

    end # class Na__ArrayBuilder__DefinitionsObserver

# endregion ===================================================================

end # module Na__ArrayBuilderTools

# =============================================================================
# END OF FILE
# =============================================================================
