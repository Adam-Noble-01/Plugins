# =============================================================================
# NA NOBLE3D MODELLING TOOLS - SCENE IMAGE EXPORTER - RUN ENTRYPOINT
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__SceneImageExporter__Run__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__SceneImageExporter
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Public execution entrypoint for the Scene Image Exporter tool.
# CREATED    : 2026
#
# WORKFLOW:
# 1. Open the dialog and list every scene in the active model.
# 2. Tick the scenes to export; the tick state is written to the model
#    dictionary immediately so it survives save, close and reopen.
# 3. Choose an export preset, or adjust size, aspect, line weight and render
#    overrides by hand. Those settings persist in the same dictionary.
# 4. Pick an output folder through the OS folder picker.
# 5. Export renders every ticked scene through Sketchup::View#write_image with
#    scene transitions suppressed, then restores the model exactly as found.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__SceneImageExporter

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_SCENE_EXPORTER_TITLE = 'Na Noble3d - Scene Image Exporter'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Entry Point
# -----------------------------------------------------------------------------

        # FUNCTION | Open the Scene Image Exporter Dialog
        # ------------------------------------------------------------
        def self.Na__SceneImageExporter__Run
            model = Sketchup.active_model
            return na_result(false, 'No active SketchUp model.') unless model

            if model.pages.count.zero?
                UI.messagebox(
                    "#{NA_SCENE_EXPORTER_TITLE}\n\n" \
                    "This model has no scenes.\n\n" \
                    'Add scene tabs first, then reopen the exporter.'
                )
                return na_result(false, 'The active model has no scenes to export.')
            end

            Na__SceneImageExporter__DialogManager.Na__SceneImageExporter__ShowDialog
            na_result(true, 'Scene Image Exporter opened.')
        rescue => error
            na_result(false, "Scene Image Exporter failed to open: #{error.class}: #{error.message}")
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

    end # module Na__SceneImageExporter
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
