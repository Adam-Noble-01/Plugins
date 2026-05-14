# =============================================================================
# NA NOBLE3D MODELLING TOOLS - INSERT COMPONENT IN PLACE - RUN ENTRYPOINT
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__InsertComponentInPlace__Run__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__InsertComponentInPlace
# PURPOSE    : Load a selected SKP file as a component and insert it at identity
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__InsertComponentInPlace

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_FILE_DIALOG_TITLE = 'Select Component .skp File'.freeze
        NA_FILE_DIALOG_FILTER = 'SketchUp Files (*.skp)|*.skp||'.freeze
        NA_IDENTITY_TRANSFORM = Geom::Transformation.new

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Entry Point
# -----------------------------------------------------------------------------

        # FUNCTION | Insert Selected Component File at Global Identity Transform
        # ------------------------------------------------------------
        def self.Na__InsertComponentInPlace__Run
            model = Sketchup.active_model
            return na_result(false, 'No active model available.') unless model

            component_file_path = na_prompt_for_component_file
            return na_result(false, 'Insert Component In Place cancelled.') if component_file_path.to_s.empty?
            return na_result(false, 'Selected component file does not exist.') unless File.exist?(component_file_path)

            operation_started = false
            Sketchup.status_text = 'Loading component file in place...'

            model.start_operation('Insert Component In Place', true)
            operation_started = true

            definition = model.definitions.load(component_file_path)
            unless definition
                model.abort_operation
                operation_started = false
                Sketchup.status_text = ''
                return na_result(false, 'SketchUp could not load the selected component file.')
            end

            instance = model.entities.add_instance(definition, NA_IDENTITY_TRANSFORM)
            model.selection.clear
            model.selection.add(instance) if instance&.valid?
            model.commit_operation
            operation_started = false

            Sketchup.status_text = ''
            na_result(true, "Inserted component in place: #{File.basename(component_file_path)}")
        rescue => error
            model.abort_operation if model && operation_started
            Sketchup.status_text = ''
            na_result(false, "Insert Component In Place failed: #{error.class}: #{error.message}")
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Prompt User for a SketchUp Component File
        # ------------------------------------------------------------
        def self.na_prompt_for_component_file
            UI.openpanel(NA_FILE_DIALOG_TITLE, '', NA_FILE_DIALOG_FILTER)
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

    end # module Na__InsertComponentInPlace
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
