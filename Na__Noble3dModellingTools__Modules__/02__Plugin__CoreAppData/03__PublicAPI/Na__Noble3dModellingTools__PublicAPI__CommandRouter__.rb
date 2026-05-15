# =============================================================================
# NA NOBLE3D MODELLING TOOLS - PUBLIC API COMMAND ROUTER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__PublicAPI__CommandRouter__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__CommandRouter
# PURPOSE    : Route JSON command IDs to module entrypoints
# CREATED    : 2026
#
# CONFIG-FIRST DESIGN NOTE:
# This router maps registry handler keys to module entrypoints only. Tool tabs,
# grouping, labels, command IDs, ordering, and hotkey visibility belong in the
# JSON registry so the UI can evolve without hardcoded Ruby layout.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__CommandRouter

# -----------------------------------------------------------------------------
# REGION | Command Execution
# -----------------------------------------------------------------------------

        def self.Na__Noble3dModellingTools__RunCommand(command_id)
            command_entry = Na__ConfigLoader.Na__Noble3dModellingTools__CommandById(command_id)
            return na_result(false, "Unknown command: #{command_id}") unless command_entry

            handler_key = command_entry.fetch('handler_key', '')
            return na_result(false, "Missing handler key for command: #{command_id}") if handler_key.empty?

            handler_proc = na_handler_proc_for_key(handler_key)
            return na_result(false, "No handler registered for key: #{handler_key}") unless handler_proc

            result = handler_proc.call
            na_normalize_result(result, command_entry.fetch('menu_text', command_id))
        rescue => error
            na_result(false, "#{error.class}: #{error.message}")
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Handler Registry
# -----------------------------------------------------------------------------

        def self.na_handler_proc_for_key(handler_key)
            case handler_key
            when 'open_main_dialog'
                proc do
                    Na__DialogManager.Na__Noble3dModellingTools__ShowDialog
                    na_result(true, 'Dialog opened.')
                end

            when 'select_quad_face_rings_shortest'
                proc { Na__SelectQuadFaceRings.Na__SelectQuadFaceRings__Run(:shortest_opposite_edges) }

            when 'select_quad_face_rings_longest'
                proc { Na__SelectQuadFaceRings.Na__SelectQuadFaceRings__Run(:longest_opposite_edges) }

            when 'select_quad_face_rings_largest'
                proc { Na__SelectQuadFaceRings.Na__SelectQuadFaceRings__Run(:largest_face_count) }

            when 'lattice_maker_prompt'
                proc { Na__LatticeMaker.Na__LatticeMaker__RunWithPrompt }

            when 'lattice_maker_last'
                proc { Na__LatticeMaker.Na__LatticeMaker__RunWithLastValues }

            when 'auto_group_utility'
                proc { Na__AutoGroupUtility.Na__AutoGroupUtility__Run }

            when 'auto_group_face_islands'
                proc { Na__AutoGroupFaceIslands.Na__AutoGroupFaceIslands__Run }

            when 'create_bounding_box'
                proc { Na__CreateBoundingBox.Na__CreateBoundingBox__Run }

            when 'convert_components_to_groups'
                proc { Na__ConvertComponentsToGroups.Na__ConvertComponentsToGroups__Run }

            when 'insert_component_in_place'
                proc { Na__InsertComponentInPlace.Na__InsertComponentInPlace__Run }

            when 'load_modelling_utility_materials'
                proc { Na__MaterialUtils.Na__MaterialUtils__LoadModelingUtilityMaterials }

            when 'load_truevision_materials_palette'
                proc { Na__MaterialUtils.Na__MaterialUtils__LoadTrueVisionMaterialsPalette }

            when 'load_all_noble_architecture_materials'
                proc { Na__MaterialUtils.Na__MaterialUtils__LoadAllNobleArchitectureMaterials }

            when 'load_all_tags'
                proc { Na__TagUtils.Na__TagUtils__LoadAllTags }

            when 'load_modeling_helper_tags'
                proc { Na__TagUtils.Na__TagUtils__LoadModelingHelperTags }

            when 'load_line_thickness_tags'
                proc { Na__TagUtils.Na__TagUtils__LoadLineThicknessTags }

            when 'load_truevision_minimal_tags'
                proc { Na__TagUtils.Na__TagUtils__LoadTrueVisionMinimalTags }

            when 'load_truevision_all_tags'
                proc { Na__TagUtils.Na__TagUtils__LoadTrueVisionAllTags }

            when 'check_web_status'
                proc { Na__WebStatus.Na__WebStatus__CheckDataLibWebStatus }

            when 'reload_plugin_data'
                proc { Na__ReloadManager.Na__Noble3dModellingTools__ReloadPluginData }

            else
                nil
            end
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Result Helpers
# -----------------------------------------------------------------------------

        def self.na_normalize_result(result, default_message)
            return result if result.is_a?(Hash) && result.key?(:success) && result.key?(:message)
            return na_result(result, default_message) if result == true || result == false
            return na_result(true, default_message) if !result.nil?

            na_result(false, "#{default_message} failed.")
        end

        def self.na_result(success_flag, message_text)
            {
                success: !!success_flag,
                message: message_text.to_s
            }
        end

# endregion -------------------------------------------------------------------

    end # module Na__CommandRouter
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
