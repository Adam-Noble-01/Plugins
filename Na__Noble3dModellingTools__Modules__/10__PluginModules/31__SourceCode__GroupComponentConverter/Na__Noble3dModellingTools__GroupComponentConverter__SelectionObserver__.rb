# =============================================================================
# NA NOBLE3D MODELLING TOOLS - GROUP / COMPONENT CONVERTER - SELECTION OBSERVER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__GroupComponentConverter__SelectionObserver__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__GroupComponentConverter__SelectionObserver
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Forward SketchUp selection changes to the converter dialog
# CREATED    : 2026
#
# =============================================================================

require 'sketchup.rb'

module Na__Noble3dModellingTools

    class Na__GroupComponentConverter__SelectionObserver < Sketchup::SelectionObserver

        def onSelectionAdded(_selection, _entity)
            Na__GroupComponentConverter__DialogManager.Na__GroupComponentConverter__DialogManager__HandleSelectionChanged
        end

        def onSelectionBulkChange(_selection)
            Na__GroupComponentConverter__DialogManager.Na__GroupComponentConverter__DialogManager__HandleSelectionChanged
        end

        def onSelectionCleared(_selection)
            Na__GroupComponentConverter__DialogManager.Na__GroupComponentConverter__DialogManager__HandleSelectionChanged
        end

        def onSelectionRemoved(_selection, _entity)
            Na__GroupComponentConverter__DialogManager.Na__GroupComponentConverter__DialogManager__HandleSelectionChanged
        end

        alias_method :onSelectedRemoved, :onSelectionRemoved

    end # class Na__GroupComponentConverter__SelectionObserver

end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
