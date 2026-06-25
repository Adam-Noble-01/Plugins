# =============================================================================
# VALEDESIGNSUITE - VALEVISION CLOUD SYNC COMMAND ROUTER
# =============================================================================
#
# FILE       : Na__ValeVisionCloudSync__PublicAPI__CommandRouter__.rb
# NAMESPACE  : Na__ValeVisionCloudSync::Na__CommandRouter
# PURPOSE    : Route registry command IDs to module entrypoints
# CREATED    : 25-Jun-2026
#
# DESCRIPTION:
# - Maps handler_key values (from UiCommandRegistry JSON) to procs.
# - Sync actions (sync_project, update_images etc.) are handled via the
#   dedicated dialog callback 'na_vvcs_run_sync_action', not here; this
#   router handles structural commands only (open dialog, reload plugin).
#
# =============================================================================

module Na__ValeVisionCloudSync
    module Na__CommandRouter

# -----------------------------------------------------------------------------
# REGION | Command Execution
# -----------------------------------------------------------------------------

        def self.Na__ValeVisionCloudSync__RunCommand(command_id)
            command_entry = Na__ConfigLoader.Na__ValeVisionCloudSync__CommandById(command_id)
            return na_result(false, "Unknown command: #{command_id}") unless command_entry

            handler_key  = command_entry.fetch('handler_key', '')
            return na_result(false, "Missing handler key for: #{command_id}") if handler_key.empty?

            handler_proc = na_handler_proc_for_key(handler_key)
            return na_result(false, "No handler for key: #{handler_key}") unless handler_proc

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
                    Na__DialogManager.Na__ValeVisionCloudSync__ShowDialog
                    na_result(true, 'Dialog opened.')
                end

            when 'reload_plugin'
                proc { Na__ReloadManager.Na__ValeVisionCloudSync__ReloadPluginData }

            when 'sync_project', 'update_images', 'update_glb_models', 'update_camera_data'
                # <-- Sync ops route through the dedicated dialog callback, not here
                proc { na_result(true, 'Use the Export tab buttons to run sync actions.') }

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
            return na_result(true, default_message) unless result.nil?

            na_result(false, "#{default_message} failed.")
        end

        def self.na_result(success_flag, message_text)
            { success: !!success_flag, message: message_text.to_s }
        end

# endregion -------------------------------------------------------------------

    end # module Na__CommandRouter
end # module Na__ValeVisionCloudSync

# =============================================================================
# END OF FILE
# =============================================================================
