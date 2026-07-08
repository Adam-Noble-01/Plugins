# =============================================================================
# NA NOBLE3D MODELLING TOOLS - SELECT SIMILAR FILTER - SELECTION OBSERVER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__SelectSimilarFilter__SelectionObserver__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__SelectSimilarFilter__SelectionObserver
# PURPOSE    : Forward SketchUp selection changes to the DialogManager for a live reference readout
# CREATED    : 2026
#
# =============================================================================

require 'sketchup.rb'

module Na__Noble3dModellingTools

    class Na__SelectSimilarFilter__SelectionObserver < Sketchup::SelectionObserver

        def onSelectionAdded(_selection, _entity)
            Na__SelectSimilarFilter__DialogManager.Na__SelectSimilarFilter__DialogManager__HandleSelectionChanged
        end

        def onSelectionBulkChange(_selection)
            Na__SelectSimilarFilter__DialogManager.Na__SelectSimilarFilter__DialogManager__HandleSelectionChanged
        end

        def onSelectionCleared(_selection)
            Na__SelectSimilarFilter__DialogManager.Na__SelectSimilarFilter__DialogManager__HandleSelectionChanged
        end

        def onSelectionRemoved(_selection, _entity)
            Na__SelectSimilarFilter__DialogManager.Na__SelectSimilarFilter__DialogManager__HandleSelectionChanged
        end

        alias_method :onSelectedRemoved, :onSelectionRemoved

    end # class Na__SelectSimilarFilter__SelectionObserver

end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
