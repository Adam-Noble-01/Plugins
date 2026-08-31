# =============================================================================
# NA NOBLE3D MODELLING TOOLS - PAINT DEEP NESTED FACES - OBSERVERS
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__PaintDeepNestedFaces__Observers__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__PaintDeepNestedFaces__*Observer
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Keep the dialog in step with SketchUp - the material swatch
#              follows the Materials tray, the face count follows the selection.
# CREATED    : 2026
#
# DESIGN NOTES:
# - onMaterialSetCurrent is the callback fired when the user clicks a swatch in
#   the Materials window or loads one into the Paint Bucket. Its materials
#   argument can be nil when the swatch comes straight from a library, so the
#   handler always re-reads Sketchup.active_model.materials.current instead of
#   trusting the arguments.
# - onMaterialRemove must not touch the material it is handed, so the handler
#   only asks the dialog to refresh from the model.
# - Every callback hands off to the DialogManager, which defers the real work
#   onto a zero-delay timer so nothing heavy runs inside the observer callback.
#
# =============================================================================

require 'sketchup.rb'

module Na__Noble3dModellingTools

# -----------------------------------------------------------------------------
# REGION | Materials Tray Observer
# -----------------------------------------------------------------------------

    # CLASS | Track the Material Selected in the SketchUp Materials Window
    # ------------------------------------------------------------
    class Na__PaintDeepNestedFaces__MaterialsObserver < Sketchup::MaterialsObserver

        # CALLBACK | User Picked a Different Material in the Tray or Paint Bucket
        def onMaterialSetCurrent(_materials, _material)
            Na__PaintDeepNestedFaces__DialogManager
                .Na__PaintDeepNestedFaces__DialogManager__HandleMaterialChanged
        end

        # CALLBACK | A Material Had Its Colour, Opacity or Texture Edited
        def onMaterialChange(_materials, _material)
            Na__PaintDeepNestedFaces__DialogManager
                .Na__PaintDeepNestedFaces__DialogManager__HandleMaterialChanged
        end

        # CALLBACK | A Material Was Added to the Model
        def onMaterialAdd(_materials, _material)
            Na__PaintDeepNestedFaces__DialogManager
                .Na__PaintDeepNestedFaces__DialogManager__HandleMaterialChanged
        end

        # CALLBACK | A Material Was Removed - Never Touch the Passed Material
        def onMaterialRemove(_materials, _material)
            Na__PaintDeepNestedFaces__DialogManager
                .Na__PaintDeepNestedFaces__DialogManager__HandleMaterialChanged
        end

        # CALLBACK | Undo or Redo Moved the Material State
        def onMaterialUndoRedo(_materials, _material)
            Na__PaintDeepNestedFaces__DialogManager
                .Na__PaintDeepNestedFaces__DialogManager__HandleMaterialChanged
        end

    end # class Na__PaintDeepNestedFaces__MaterialsObserver
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Selection Observer
# -----------------------------------------------------------------------------

    # CLASS | Keep the Live Face Count in Step with the Model Selection
    # ------------------------------------------------------------
    class Na__PaintDeepNestedFaces__SelectionObserver < Sketchup::SelectionObserver

        def onSelectionAdded(_selection, _entity)
            Na__PaintDeepNestedFaces__DialogManager
                .Na__PaintDeepNestedFaces__DialogManager__HandleSelectionChanged
        end

        def onSelectionBulkChange(_selection)
            Na__PaintDeepNestedFaces__DialogManager
                .Na__PaintDeepNestedFaces__DialogManager__HandleSelectionChanged
        end

        def onSelectionCleared(_selection)
            Na__PaintDeepNestedFaces__DialogManager
                .Na__PaintDeepNestedFaces__DialogManager__HandleSelectionChanged
        end

        def onSelectionRemoved(_selection, _entity)
            Na__PaintDeepNestedFaces__DialogManager
                .Na__PaintDeepNestedFaces__DialogManager__HandleSelectionChanged
        end

        alias_method :onSelectedRemoved, :onSelectionRemoved

    end # class Na__PaintDeepNestedFaces__SelectionObserver
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
