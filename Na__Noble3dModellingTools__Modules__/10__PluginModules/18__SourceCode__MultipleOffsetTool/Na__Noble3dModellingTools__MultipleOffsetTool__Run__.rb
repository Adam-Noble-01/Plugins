# =============================================================================
# NA NOBLE3D MODELLING TOOLS - MULTIPLE OFFSET TOOL - RUN ENTRYPOINT
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__MultipleOffsetTool__Run__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__MultipleOffsetTool
# PURPOSE    : Public execution entrypoint for activating the Multiple Offset
#              Tool, plus stored last-used distance read/write helpers.
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__MultipleOffsetTool

# -----------------------------------------------------------------------------
# REGION | Public Entry Point
# -----------------------------------------------------------------------------

        # FUNCTION | Run Multiple Offset Tool
        # ------------------------------------------------------------
        def self.Na__MultipleOffsetTool__Run
            model = Sketchup.active_model
            return na_result(false, 'No active model available.') unless model

            selected_faces = model.selection.grep(Sketchup::Face)
            if selected_faces.empty?
                return na_result(false, 'Select one or more faces first, then run the Multiple Offset Tool.')
            end

            model.select_tool(MultipleOffsetTool.new)
            na_result(true, 'Multiple Offset Tool activated.')
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Stored Distance Helpers
# -----------------------------------------------------------------------------

        # FUNCTION | Return the Stored Last-Used Offset Distance
        # ------------------------------------------------------------
        # The preference is persisted as a raw internal length value (inches,
        # SketchUp's internal unit). Reading it back through Numeric#to_l keeps the
        # round trip unambiguous and independent of the model's display units.
        # ------------------------------------------------------------
        def self.Na__MultipleOffsetTool__StoredDistance
            stored_value = Sketchup.read_default(PREF_NAMESPACE, PREF_DISTANCE, nil)
            return DEFAULT_OFFSET_DISTANCE if stored_value.nil?

            stored_inches = stored_value.to_f
            return DEFAULT_OFFSET_DISTANCE if stored_inches <= 0

            stored_inches.to_l                                            # <-- Interpret stored number as internal inches
        rescue StandardError
            DEFAULT_OFFSET_DISTANCE
        end
        # ------------------------------------------------------------


        # FUNCTION | Persist the Last-Used Offset Distance
        # ------------------------------------------------------------
        # Stored as the raw internal length (inches) so no unit parsing is needed
        # when it is read back.
        # ------------------------------------------------------------
        def self.Na__MultipleOffsetTool__StoreDistance(distance)
            Sketchup.write_default(PREF_NAMESPACE, PREF_DISTANCE, distance.to_f.to_s)
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Result Helper
# -----------------------------------------------------------------------------

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

    end # module Na__MultipleOffsetTool
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
