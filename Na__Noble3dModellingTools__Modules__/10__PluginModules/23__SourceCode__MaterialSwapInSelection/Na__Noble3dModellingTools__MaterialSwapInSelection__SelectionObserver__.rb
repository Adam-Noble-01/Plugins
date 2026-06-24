# =============================================================================
# NA NOBLE3D MODELLING TOOLS - MATERIAL SWAP IN SELECTION - SELECTION OBSERVER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__MaterialSwapInSelection__SelectionObserver__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__MaterialSwapInSelection__SelectionObserver
# PURPOSE    : Forward SketchUp selection changes to the DialogManager for live UI sync
# CREATED    : 2026
#
# =============================================================================

require 'sketchup.rb'

module Na__Noble3dModellingTools

    class Na__MaterialSwapInSelection__SelectionObserver < Sketchup::SelectionObserver

        def onSelectionAdded(_selection, _entity)
            Na__MaterialSwapInSelection__DialogManager.Na__MaterialSwapInSelection__DialogManager__HandleSelectionChanged
        end

        def onSelectionBulkChange(_selection)
            Na__MaterialSwapInSelection__DialogManager.Na__MaterialSwapInSelection__DialogManager__HandleSelectionChanged
        end

        def onSelectionCleared(_selection)
            Na__MaterialSwapInSelection__DialogManager.Na__MaterialSwapInSelection__DialogManager__HandleSelectionChanged
        end

        def onSelectionRemoved(_selection, _entity)
            Na__MaterialSwapInSelection__DialogManager.Na__MaterialSwapInSelection__DialogManager__HandleSelectionChanged
        end

        alias_method :onSelectedRemoved, :onSelectionRemoved

    end # class Na__MaterialSwapInSelection__SelectionObserver

end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
