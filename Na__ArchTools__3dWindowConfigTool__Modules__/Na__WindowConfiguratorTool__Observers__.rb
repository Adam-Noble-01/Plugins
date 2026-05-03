# =============================================================================
# NA WINDOW CONFIGURATOR TOOL - OBSERVERS
# =============================================================================
#
# FILE       : Na__WindowConfiguratorTool__Observers__.rb
# NAMESPACE  : Na__WindowConfiguratorTool
# AUTHOR     : Noble Architecture
# PURPOSE    : Selection observers for detecting window component selection
# CREATED    : 2026
# VERSION    : 0.2.3b
#
# DESCRIPTION:
# - SelectionObserver monitors when user selects/deselects window components
# - Automatically loads window configuration into dialog when selected
# - Clears dialog when selection is empty or non-window entity
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__WindowConfiguratorTool__DebugTools__'
require_relative 'Na__WindowConfiguratorTool__DataSerializer__'
require_relative 'Na__WindowConfiguratorTool__DialogManager__'

module Na__WindowConfiguratorTool

# =============================================================================
# REGION | Module References
# =============================================================================

    DebugTools     = Na__WindowConfiguratorTool::Na__DebugTools
    DataSerializer = Na__WindowConfiguratorTool::Na__DataSerializer
    DialogManager  = Na__WindowConfiguratorTool::Na__DialogManager

# endregion ===================================================================

# =============================================================================
# REGION | Selection Observer Class
# =============================================================================

    class Na__WindowSelectionObserver < Sketchup::SelectionObserver

        # MODULE CONSTANTS | Tab IDs (mirror Na_AppContext)
        # ------------------------------------------------------------
        NA_TAB_WINDOWS = "windows".freeze
        NA_TAB_DOORS   = "doors".freeze
        # ---------------------------------------------------------------

        # FUNCTION | Selection Bulk Change Handler (Tab-Aware)
        # ------------------------------------------------------------
        # Called when selection changes (one or more entities selected).
        # v0.11.6 - Now routes single-instance selections through the
        # cached active-tab id from DialogManager. If the selected
        # component belongs to a tab the user is not currently viewing,
        # the dialog is asked to switch tabs first via
        # Na__DialogManager.na_request_tab_switch so the loaded config
        # is actually visible. Empty selections clear both tabs.
        def onSelectionBulkChange(selection)
            DebugTools.na_debug_observer("Selection changed: #{selection.length} entities")

            if selection.empty?
                na_clear_both_tabs
                return
            end

            return unless selection.length == 1 &&
                          selection.first.is_a?(Sketchup::ComponentInstance)

            instance  = selection.first
            window_id = DataSerializer.na_get_window_id_from_instance(instance)
            door_id   = na_get_door_id_from_instance(instance)

            return if na_dispatch_window_selection(instance, window_id)
            return if na_dispatch_door_selection(instance, door_id)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Selection Cleared Handler
        # ------------------------------------------------------------
        # Called when selection is explicitly cleared.
        def onSelectionCleared(selection)
            DebugTools.na_debug_observer("Selection cleared")
            na_clear_both_tabs
        end
        # ---------------------------------------------------------------

        private

        # HELPER FUNCTION | Resolve the JS-Side Active Tab from the Cache
        # ------------------------------------------------------------
        # Defaults to "windows" if the DialogManager has not yet cached
        # a tab id (e.g. observer fired before Na_AppContext booted).
        def na_active_tab_id
            return NA_TAB_WINDOWS unless DialogManager.respond_to?(:na_get_active_tab_id)
            DialogManager.na_get_active_tab_id
        rescue StandardError
            NA_TAB_WINDOWS
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Ask the Dialog to Switch to a Specific Tab
        # ------------------------------------------------------------
        def na_request_tab_switch(tab_id)
            return unless DialogManager.respond_to?(:na_request_tab_switch)
            DialogManager.na_request_tab_switch(tab_id)
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Dispatch a Window Selection to the Window Tab
        # ------------------------------------------------------------
        # Returns true if the selection was consumed (regardless of
        # whether a tab switch was needed) so the caller can short-circuit.
        # Returns false if the instance is not a window.
        def na_dispatch_window_selection(instance, window_id)
            return false unless window_id
            DebugTools.na_debug_observer("Selected window: #{window_id} (active tab=#{na_active_tab_id})")

            na_request_tab_switch(NA_TAB_WINDOWS) if na_active_tab_id != NA_TAB_WINDOWS
            Na__WindowConfiguratorTool.na_load_window_into_dialog(instance, window_id)
            true
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Dispatch a Door Selection to the Door Tab
        # ------------------------------------------------------------
        def na_dispatch_door_selection(instance, door_id)
            return false unless door_id
            DebugTools.na_debug_observer("Selected door: #{door_id} (active tab=#{na_active_tab_id})")

            na_request_tab_switch(NA_TAB_DOORS) if na_active_tab_id != NA_TAB_DOORS
            Na__WindowConfiguratorTool.na_load_door_into_dialog(instance, door_id)
            true
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Clear Both Tabs After an Empty Selection
        # ------------------------------------------------------------
        def na_clear_both_tabs
            Na__WindowConfiguratorTool.na_clear_window_from_dialog
            Na__WindowConfiguratorTool.na_clear_door_from_dialog
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Look Up the Door ID on a Component Instance
        # ------------------------------------------------------------
        # Returns the ADR### door id stored on the instance's
        # Na__DoorConfiguratorInfo dictionary, or nil if either the
        # Interior Door Configurator isn't loaded or the dictionary
        # isn't present.
        def na_get_door_id_from_instance(instance)
            return nil unless defined?(Na__InteriorDoorConfigurator::Na__DataSerializer)
            Na__InteriorDoorConfigurator::Na__DataSerializer.na_get_door_id_from_instance(instance)
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

    end

# endregion ===================================================================

end # module Na__WindowConfiguratorTool

# =============================================================================
# END OF FILE
# =============================================================================
