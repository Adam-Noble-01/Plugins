# =============================================================================
# NA NOBLE3D MODELLING TOOLS - VEGETATION SKETCHER - OBSERVERS
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__VegetationSketcher__Observers__.rb
# NAMESPACE  : Na__Noble3dModellingTools
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Forward SketchUp selection, model, entity and app changes to
#              the vegetation dialog without doing work inside callbacks
# CREATED    : 2026
#
# Observers only schedule a refresh. The dialog manager reads selection and
# dictionaries on the next UI loop, outside SketchUp's transaction callbacks.
#
# =============================================================================

module Na__Noble3dModellingTools

# -----------------------------------------------------------------------------
# REGION | Selection Observer
# -----------------------------------------------------------------------------

    class Na__VegetationSketcher__SelectionObserver < Sketchup::SelectionObserver

        def onSelectionBulkChange(_selection)
            Na__VegetationSketcher__DialogManager.Na__VegetationSketcher__DialogManager__HandleObserverEvent
        end

        def onSelectionAdded(_selection, _entity)
            Na__VegetationSketcher__DialogManager.Na__VegetationSketcher__DialogManager__HandleObserverEvent
        end

        def onSelectionRemoved(_selection, _entity)
            Na__VegetationSketcher__DialogManager.Na__VegetationSketcher__DialogManager__HandleObserverEvent
        end

        def onSelectionCleared(_selection)
            Na__VegetationSketcher__DialogManager.Na__VegetationSketcher__DialogManager__HandleObserverEvent
        end

    end # class Na__VegetationSketcher__SelectionObserver

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Model Observer
# -----------------------------------------------------------------------------

    class Na__VegetationSketcher__ModelObserver < Sketchup::ModelObserver

        def onTransactionCommit(_model)
            Na__VegetationSketcher__DialogManager.Na__VegetationSketcher__DialogManager__HandleObserverEvent
        end

        def onTransactionUndo(_model)
            Na__VegetationSketcher__DialogManager.Na__VegetationSketcher__DialogManager__HandleObserverEvent
        end

        def onTransactionRedo(_model)
            Na__VegetationSketcher__DialogManager.Na__VegetationSketcher__DialogManager__HandleObserverEvent
        end

        def onTransactionAbort(_model)
            Na__VegetationSketcher__DialogManager.Na__VegetationSketcher__DialogManager__HandleObserverEvent
        end

        def onActivePathChanged(_model)
            Na__VegetationSketcher__DialogManager.Na__VegetationSketcher__DialogManager__HandleObserverEvent
        end

        def onDeleteModel(_model)
            Na__VegetationSketcher__DialogManager.Na__VegetationSketcher__DialogManager__HandleObserverEvent
        end

    end # class Na__VegetationSketcher__ModelObserver

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Entity Observer
# -----------------------------------------------------------------------------

    class Na__VegetationSketcher__EntityObserver < Sketchup::EntityObserver

        def onChangeEntity(_entity)
            Na__VegetationSketcher__DialogManager.Na__VegetationSketcher__DialogManager__HandleObserverEvent
        end

        def onEraseEntity(_entity)
            Na__VegetationSketcher__DialogManager.Na__VegetationSketcher__DialogManager__HandleObserverEvent
        end

    end # class Na__VegetationSketcher__EntityObserver

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | App Observer
# -----------------------------------------------------------------------------

    class Na__VegetationSketcher__AppObserver < Sketchup::AppObserver

        def onNewModel(_model)
            Na__VegetationSketcher__DialogManager.Na__VegetationSketcher__DialogManager__HandleObserverEvent
        end

        def onOpenModel(_model)
            Na__VegetationSketcher__DialogManager.Na__VegetationSketcher__DialogManager__HandleObserverEvent
        end

        def onActivateModel(_model)
            Na__VegetationSketcher__DialogManager.Na__VegetationSketcher__DialogManager__HandleObserverEvent
        end

    end # class Na__VegetationSketcher__AppObserver

# endregion -------------------------------------------------------------------

end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
