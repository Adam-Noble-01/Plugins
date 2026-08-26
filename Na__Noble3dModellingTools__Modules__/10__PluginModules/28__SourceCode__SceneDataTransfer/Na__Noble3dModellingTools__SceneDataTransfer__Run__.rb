# =============================================================================
# NA NOBLE3D MODELLING TOOLS - SCENE DATA TRANSFER - RUN ENTRYPOINT
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__SceneDataTransfer__Run__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__SceneDataTransfer
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Public execution entrypoint for the Scene Data Transfer tool.
# CREATED    : 2026
#
# WORKFLOW:
#
# In the model you want to harvest scenes FROM (model B):
#   1. Open the tool and switch to the Capture tab.
#   2. Press Capture Scene Data. Every scene is serialised into a hidden
#      carrier component inside the model.
#   3. SAVE THE MODEL. The data only reaches the .skp file on save.
#
# In the model you want the scenes IN (model A):
#   4. Open the tool and switch to the Import tab.
#   5. Browse to model B's .skp. It is read straight off disk - model B is
#      never opened and the model you are working in is never disturbed.
#   6. Tick the scenes you want and tick what to reconstruct.
#   7. Press Import. Each scene is rebuilt with the chosen properties only,
#      named with an __IMPORTED suffix.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__SceneDataTransfer

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_SCENE_TRANSFER_TITLE = 'Na Noble3d - Scene Data Transfer'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Entry Point
# -----------------------------------------------------------------------------

        # FUNCTION | Open the Scene Data Transfer Dialog
        # ------------------------------------------------------------
        def self.Na__SceneDataTransfer__Run
            model = Sketchup.active_model
            return na_result(false, 'No active SketchUp model.') unless model

            Na__SceneDataTransfer__DialogManager.Na__SceneDataTransfer__ShowDialog
            na_result(true, 'Scene Data Transfer opened.')
        rescue => error
            na_result(false, "Scene Data Transfer failed to open: #{error.class}: #{error.message}")
        end
        # ------------------------------------------------------------

        # FUNCTION | Capture This Model's Scenes Without Opening the Dialog
        # ------------------------------------------------------------
        # Exposed so the capture step can be bound to its own toolbar button or
        # hotkey without going through the dialog.
        def self.Na__SceneDataTransfer__CaptureActiveModel
            model = Sketchup.active_model
            return na_result(false, 'No active SketchUp model.') unless model

            if model.pages.count.zero?
                UI.messagebox(
                    "#{NA_SCENE_TRANSFER_TITLE}\n\n" \
                    "This model has no scenes to capture.\n\n" \
                    'Add scene tabs first, then run the capture again.'
                )
                return na_result(false, 'The active model has no scenes to capture.')
            end

            result = Na__SceneDataTransfer__Capture.Na__SceneDataTransfer__CaptureModel(model)
            UI.messagebox("#{NA_SCENE_TRANSFER_TITLE}\n\n#{result['message']}")

            na_result(result['success'], result['message'])
        rescue => error
            na_result(false, "Capture failed: #{error.class}: #{error.message}")
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Result Helper
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Build Standard Result Hash
        # ------------------------------------------------------------
        def self.na_result(success_flag, message_text, extra = {})
            { success: !!success_flag, message: message_text.to_s }.merge(extra)
        end
        private_class_method :na_result
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__SceneDataTransfer
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
