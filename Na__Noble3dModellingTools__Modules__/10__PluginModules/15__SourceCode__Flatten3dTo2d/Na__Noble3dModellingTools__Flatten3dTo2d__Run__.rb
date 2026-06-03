# =============================================================================
# NA NOBLE3D MODELLING TOOLS - FLATTEN 3D TO 2D - RUN ENTRYPOINTS
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__Flatten3dTo2d__Run__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__Flatten3dTo2d
# PURPOSE    : Public execution entrypoints for the Flatten 3D To 2D tools
# CREATED    : 2026
#
# DESCRIPTION:
# - Na__Flatten3dTo2d__RunToGroup      : flatten selection to all-linework group.
# - Na__Flatten3dTo2d__RunToSilhouette : flatten selection to outline-only group.
# - Validates the selection, enforces Parallel Projection (offering to switch),
#   wraps creation in a single undoable operation, places the result at the front
#   plane facing the camera, selects it, and never alters the original geometry.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__Flatten3dTo2d

# -----------------------------------------------------------------------------
# REGION | Public Entry Points
# -----------------------------------------------------------------------------

        # FUNCTION | Flatten 3D To Group (All Linework)
        # ------------------------------------------------------------
        def self.Na__Flatten3dTo2d__RunToGroup
            na_run_flatten(:linework)
        end
        # ------------------------------------------------------------

        # FUNCTION | Flatten 3D To Silhouette (Outline Only)
        # ------------------------------------------------------------
        def self.Na__Flatten3dTo2d__RunToSilhouette
            na_run_flatten(:silhouette)
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Orchestration
# -----------------------------------------------------------------------------

        # FUNCTION | Shared Flatten Workflow for Both Modes
        # ------------------------------------------------------------
        def self.na_run_flatten(mode)
            model = Sketchup.active_model
            return na_result(false, 'No active model available.') unless model

            selection = model.selection
            return na_result(false, 'Select one or more groups/components, then run the tool again.') if selection.empty?

            view = model.active_view
            return na_result(false, 'Flatten cancelled: this tool requires Parallel Projection.') unless na_ensure_parallel_projection(view)

            world_normal = na_world_view_direction(view)
            edit_inverse = model.edit_transform.inverse

            operation_name = na_operation_name(mode)
            operation_started = false
            Sketchup.status_text = "#{operation_name}..."

            begin
                model.start_operation(operation_name, true)
                operation_started = true

                result_group = na_build_for_mode(mode, model, model.active_entities, selection, world_normal, edit_inverse)

                if result_group.nil? || !result_group.valid? || na_group_empty?(result_group)
                    model.abort_operation
                    operation_started = false
                    Sketchup.status_text = ''
                    return na_result(false, na_empty_message(mode))
                end

                model.selection.clear
                model.selection.add(result_group)
                model.commit_operation
                operation_started = false

                Sketchup.status_text = ''
                na_result(true, na_success_message(mode))
            rescue StandardError => error
                model.abort_operation if operation_started
                Sketchup.status_text = ''
                na_result(false, "#{operation_name} failed: #{error.class}: #{error.message}")
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Collect and Build the Group for the Requested Mode
        # ------------------------------------------------------------
        def self.na_build_for_mode(mode, model, active_entities, selection, view_normal, edit_inverse)
            base_transform = model.edit_transform

            if mode == :silhouette
                faces = na_collect_world_faces(selection, base_transform)
                return nil if faces.empty?
                na_build_silhouette_group(active_entities, faces, view_normal, edit_inverse)[:group]
            else
                edges = na_collect_world_edges(selection, base_transform)
                return nil if edges.empty?
                visible_edges = na_filter_visible_edges(model, edges, view_normal)
                return nil if visible_edges.empty?
                na_build_linework_group(active_entities, visible_edges, view_normal, edit_inverse)
            end
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Parallel Projection Guard
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Ensure Parallel Projection, Offering to Switch
        # ------------------------------------------------------------
        def self.na_ensure_parallel_projection(view)
            return false unless view
            return true if na_parallel_projection?(view)

            choice = UI.messagebox(
                "Flatten 3D To 2D requires Parallel Projection.\n\n" \
                "Switch the current view to Parallel Projection and continue?",
                MB_YESNO
            )
            return false unless choice == IDYES

            view.camera.perspective = false                               # <-- Switch to Parallel Projection
            view.invalidate
            true
        rescue StandardError
            false
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Result / Message Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Check Whether the Built Group Has No Geometry
        # ------------------------------------------------------------
        def self.na_group_empty?(group)
            group.entities.length == 0
        rescue StandardError
            true
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Operation Name for the Requested Mode
        # ------------------------------------------------------------
        def self.na_operation_name(mode)
            mode == :silhouette ? 'Flatten 3D To Silhouette' : 'Flatten 3D To Group'
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Success Message for the Requested Mode
        # ------------------------------------------------------------
        def self.na_success_message(mode)
            if mode == :silhouette
                'Flattened selection to a 2D silhouette outline group.'
            else
                'Flattened selection to a 2D linework group.'
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Empty-Result Message for the Requested Mode
        # ------------------------------------------------------------
        def self.na_empty_message(mode)
            if mode == :silhouette
                'No faces could be projected. The selection may contain no faces, or all faces are edge-on to this view.'
            else
                'No camera-visible edges were found to flatten from this view.'
            end
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

    end # module Na__Flatten3dTo2d
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
