# =============================================================================
# NA COMPONENT EDITOR TOOLS - APPCORE SELECTION OBSERVER
# =============================================================================
#
# FILE       : Na__ComponentEditorTools__AppCore__SelectionObserver__.rb
# NAMESPACE  : Na__ComponentEditorTools::Na__ComponentEditorTools__SelectionObserver
# PURPOSE    : Forward SketchUp selection changes to the HtmlDialog payload sync
# CREATED    : 2026
#
# =============================================================================

require 'sketchup.rb'

module Na__ComponentEditorTools
    class Na__ComponentEditorTools__SelectionObserver < Sketchup::SelectionObserver

        def onSelectionAdded(_selection, _entity)
            Na__ComponentEditorTools::Na__DialogManager.Na__ComponentEditorTools__HandleSelectionChanged
        end

        def onSelectionBulkChange(_selection)
            Na__ComponentEditorTools::Na__DialogManager.Na__ComponentEditorTools__HandleSelectionChanged
        end

        def onSelectionCleared(_selection)
            Na__ComponentEditorTools::Na__DialogManager.Na__ComponentEditorTools__HandleSelectionChanged
        end

        def onSelectionRemoved(_selection, _entity)
            Na__ComponentEditorTools::Na__DialogManager.Na__ComponentEditorTools__HandleSelectionChanged
        end

        alias_method :onSelectedRemoved, :onSelectionRemoved
    end
end

# =============================================================================
# END OF FILE
# =============================================================================
