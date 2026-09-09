# =============================================================================
# NA NOBLE3D MODELLING TOOLS - MEGA EXPLODE - SELECTION OBSERVER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__MegaExplode__SelectionObserver__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__MegaExplode__SelectionObserver
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Forward SketchUp selection changes to the Mega Explode dialog
# CREATED    : 2026
#
# =============================================================================

require 'sketchup.rb'

module Na__Noble3dModellingTools

    class Na__MegaExplode__SelectionObserver < Sketchup::SelectionObserver

        def onSelectionAdded(_selection, _entity)
            Na__MegaExplode__DialogManager.Na__MegaExplode__DialogManager__HandleSelectionChanged
        end

        def onSelectionBulkChange(_selection)
            Na__MegaExplode__DialogManager.Na__MegaExplode__DialogManager__HandleSelectionChanged
        end

        def onSelectionCleared(_selection)
            Na__MegaExplode__DialogManager.Na__MegaExplode__DialogManager__HandleSelectionChanged
        end

        def onSelectionRemoved(_selection, _entity)
            Na__MegaExplode__DialogManager.Na__MegaExplode__DialogManager__HandleSelectionChanged
        end

        alias_method :onSelectedRemoved, :onSelectionRemoved

    end # class Na__MegaExplode__SelectionObserver

end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
