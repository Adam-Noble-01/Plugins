# =============================================================================
# NA NOBLE3D MODELLING TOOLS - GROUP / COMPONENT CONVERTER - RUN ENTRYPOINT
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__GroupComponentConverter__Run__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__GroupComponentConverter
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Public execution entrypoints for the Group / Component Converter
# CREATED    : 2026
#
# WORKFLOW:
# 1. Select any mix of groups, components and loose geometry.
# 2. The converter opens a dedicated HtmlDialog. The first switch picks the
#    direction (Groups -> Components or Components -> Groups), the second
#    picks the reach (Current Level Only or Deep Nesting).
# 3. The dialog reports how many groups and components sit at each nested
#    level and exactly how many will convert, from what to what.
# 4. Confirm in the in-dialog modal. One undoable operation converts them.
#
# REPLACES: Entity Utils > Convert Components To Groups (module 05) and
#           Entity Utils > Groups To Component (module 17).
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__GroupComponentConverter

# -----------------------------------------------------------------------------
# REGION | Public Entry Points
# -----------------------------------------------------------------------------

        # FUNCTION | Open the Converter Dialog
        # ------------------------------------------------------------
        def self.Na__GroupComponentConverter__Run
            model = Sketchup.active_model
            return na_result(false, 'No active SketchUp model.') unless model

            Na__GroupComponentConverter__DialogManager.Na__GroupComponentConverter__ShowDialog
            na_result(true, 'Group / Component Converter opened.')
        rescue => error
            na_result(false, "Group / Component Converter failed to open: #{error.class}: #{error.message}")
        end
        # ------------------------------------------------------------

        # FUNCTION | Convert the Current Selection With the Given Options
        # ------------------------------------------------------------
        # @param options [Hash] Switches and toggles from the dialog
        # @return [Hash] { success:, message: }
        # ------------------------------------------------------------
        def self.Na__GroupComponentConverter__ConvertCurrentSelection(options = {})
            Na__GroupComponentConverter__Converter.Na__GroupComponentConverter__Converter__ConvertSelection(options)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build Standard Result Hash
        # ------------------------------------------------------------
        def self.na_result(success_flag, message_text)
            {
                success: !!success_flag,
                message: message_text.to_s
            }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__GroupComponentConverter
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
