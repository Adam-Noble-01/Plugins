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

module Na__WindowConfiguratorTool

# =============================================================================
# REGION | Module References
# =============================================================================

    DebugTools = Na__WindowConfiguratorTool::Na__DebugTools
    DataSerializer = Na__WindowConfiguratorTool::Na__DataSerializer

# endregion ===================================================================

# =============================================================================
# REGION | Selection Observer Class
# =============================================================================

    class Na__WindowSelectionObserver < Sketchup::SelectionObserver
        
        # FUNCTION | Selection Bulk Change Handler
        # ------------------------------------------------------------
        # Called when selection changes (one or more entities selected)
        def onSelectionBulkChange(selection)
            DebugTools.na_debug_observer("Selection changed: #{selection.length} entities")
            
            if selection.length == 1 && selection.first.is_a?(Sketchup::ComponentInstance)
                instance = selection.first
                window_id = DataSerializer.na_get_window_id_from_instance(instance)
                
                if window_id
                    DebugTools.na_debug_observer("Selected window: #{window_id}")
                    # Notify main module to load window config
                    Na__WindowConfiguratorTool.na_load_window_into_dialog(instance, window_id)
                end
            elsif selection.empty?
                Na__WindowConfiguratorTool.na_clear_window_from_dialog
            end
        end
        # ---------------------------------------------------------------
        
        # FUNCTION | Selection Cleared Handler
        # ------------------------------------------------------------
        # Called when selection is explicitly cleared
        def onSelectionCleared(selection)
            DebugTools.na_debug_observer("Selection cleared")
            Na__WindowConfiguratorTool.na_clear_window_from_dialog
        end
        # ---------------------------------------------------------------
        
    end

# endregion ===================================================================

end # module Na__WindowConfiguratorTool

# =============================================================================
# END OF FILE
# =============================================================================
