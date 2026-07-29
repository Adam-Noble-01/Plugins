# frozen_string_literal: true

# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - PRESETS LIBRARY DIALOG CALLBACKS
# =============================================================================
#
# FILE       : Na__AssemblyStudio__PresetsLibrary__DialogCallbacks__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__PresetsLibrarySystem
# MODULE     : Na__DialogCallbacks
# AUTHOR     : Noble Architecture
# CREATED    : 2026
# PURPOSE    : All Presets Gallery JS->Ruby callbacks. Thin handlers that
#              parse the bridge payload, delegate the file work to Na__Store
#              and push results back through UiBridge.
#
# DESCRIPTION
# - Registry: na_presetsRequestLibrary, na_presetsSaveNew,
#   na_presetsUpdateMeta, na_presetsUpdateConfig.
# - Ruby->JS pushes: window.na_receivePresetsLibrary(payload) and
#   window.na_receivePresetsSaveResult(payload), both string-keyed
#   camelCase with human statusMessage + machine reason.
# - Every handler body is broad-rescued at the top level only so a
#   failure ALWAYS reaches JS as a well-formed error payload.
# =============================================================================

require 'sketchup.rb'
require 'json'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../01__AppCore/Na__AssemblyStudio__AppCore__UiBridge__'
require_relative 'Na__AssemblyStudio__PresetsLibrary__Store__'

module Na__AssemblyStudio
    module Na__PresetsLibrarySystem
        module Na__DialogCallbacks

            DebugTools = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
            UiBridge   = Na__AssemblyStudio::Na__AppCore::Na__UiBridge
            Store      = Na__AssemblyStudio::Na__PresetsLibrarySystem::Na__Store

            @na_dialog = nil

            # -----------------------------------------------------------------
            # REGION | Dialog Attachment and Callback Registry
            # -----------------------------------------------------------------

            def self.na_attach_dialog(dialog)
                @na_dialog = dialog
            end

            # FUNCTION | Build the JS -> Ruby Callback Registry
            # ------------------------------------------------------------
            # @return [Hash{String=>Proc}] registry consumed by
            #     UiBridge.na_register_callbacks from the Init hook
            def self.na_callback_registry
                {
                    "na_presetsRequestLibrary" => proc { na_handle_request_library },
                    "na_presetsSaveNew"        => proc { |json| na_handle_save_new(json) },
                    "na_presetsUpdateMeta"     => proc { |json| na_handle_update_meta(json) },
                    "na_presetsUpdateConfig"   => proc { |json| na_handle_update_config(json) }
                }
            end
            # ---------------------------------------------------------------

            # -----------------------------------------------------------------
            # REGION | Library Push (Ruby -> JS)
            # -----------------------------------------------------------------

            # FUNCTION | Scan the Store and Push the Library to the Dialog
            # ------------------------------------------------------------
            # Always delivers a well-formed payload: on any failure the JS
            # side still receives isOk false with an empty presets array.
            # @return [void]
            def self.na_push_library_to_dialog
                records = Store.na_scan_presets
                UiBridge.na_execute_json_function(@na_dialog, 'window.na_receivePresetsLibrary', {
                    'isOk'          => true,
                    'presets'       => records,
                    'statusMessage' => "Preset library loaded (#{records.length} preset#{records.length == 1 ? '' : 's'}).",
                    'reason'        => nil
                })
            rescue StandardError => e
                DebugTools.na_debug_error("[PresetsLibrary] Library push failed", e)
                UiBridge.na_execute_json_function(@na_dialog, 'window.na_receivePresetsLibrary', {
                    'isOk'          => false,
                    'presets'       => [],
                    'statusMessage' => 'Preset library could not be loaded.',
                    'reason'        => e.message
                })
            end
            # ---------------------------------------------------------------

            # -----------------------------------------------------------------
            # REGION | Callback Handlers
            # -----------------------------------------------------------------

            # FUNCTION | Handle the Library Request Callback
            # ------------------------------------------------------------
            # @return [void]
            def self.na_handle_request_library
                DebugTools.na_debug_ui("[PresetsLibrary] Library requested from JS")
                na_push_library_to_dialog
            rescue StandardError => e
                DebugTools.na_debug_error("[PresetsLibrary] Library request failed", e)
            end
            # ---------------------------------------------------------------

            # FUNCTION | Handle the Save-New-Preset Callback
            # ------------------------------------------------------------
            # Store allocates the EAS code + filename and writes the file;
            # on success the library is re-pushed BEFORE the save result
            # so the gallery re-renders with the new card ready.
            # @param json [String] raw JSON payload from the dialog
            # @return [void]
            def self.na_handle_save_new(json)
                params = JSON.parse(json.to_s)
                result = Store.na_save_new_preset(params)
                na_push_library_to_dialog if result['isSaved']
                na_send_save_result(result)
            rescue StandardError => e
                DebugTools.na_debug_error("[PresetsLibrary] Save-new failed", e)
                na_send_save_result(na_error_result('Preset could not be saved.', e.message))
            end
            # ---------------------------------------------------------------

            # FUNCTION | Handle the Update-Preset-Metadata Callback
            # ------------------------------------------------------------
            # @param json [String] raw JSON payload from the dialog
            # @return [void]
            def self.na_handle_update_meta(json)
                params = JSON.parse(json.to_s)
                result = Store.na_update_preset_meta(params)
                na_push_library_to_dialog if result['isSaved']
                na_send_save_result(result)
            rescue StandardError => e
                DebugTools.na_debug_error("[PresetsLibrary] Metadata update failed", e)
                na_send_save_result(na_error_result('Preset details could not be saved.', e.message))
            end
            # ---------------------------------------------------------------

            # FUNCTION | Handle the Update-Preset-Configuration Callback
            # ------------------------------------------------------------
            # @param json [String] raw JSON payload from the dialog
            # @return [void]
            def self.na_handle_update_config(json)
                params = JSON.parse(json.to_s)
                result = Store.na_update_preset_config(params)
                na_push_library_to_dialog if result['isSaved']
                na_send_save_result(result)
            rescue StandardError => e
                DebugTools.na_debug_error("[PresetsLibrary] Configuration update failed", e)
                na_send_save_result(na_error_result('Preset could not be updated.', e.message))
            end
            # ---------------------------------------------------------------

            # -----------------------------------------------------------------
            # REGION | Save Result Push (Ruby -> JS)
            # -----------------------------------------------------------------

            # HELPER FUNCTION | Push a Save Result Payload to the Dialog
            # ------------------------------------------------------------
            # @param result [Hash] store result hash (isSaved, presetCode,
            #     sourceFile, statusMessage, reason)
            # @return [void]
            def self.na_send_save_result(result)
                result = {} unless result.is_a?(Hash)
                UiBridge.na_execute_json_function(@na_dialog, 'window.na_receivePresetsSaveResult', {
                    'isSaved'       => result['isSaved'] == true,
                    'presetCode'    => result['presetCode'].to_s,
                    'sourceFile'    => result['sourceFile'].to_s,
                    'statusMessage' => result['statusMessage'].to_s,
                    'reason'        => result['reason']
                })
            rescue StandardError => e
                DebugTools.na_debug_error("[PresetsLibrary] Save result push failed", e)
            end
            private_class_method :na_send_save_result
            # ---------------------------------------------------------------

            # HELPER FUNCTION | Build a Well-Formed Error Result Hash
            # ------------------------------------------------------------
            # @param status_message [String] human-readable status text
            # @param reason         [String] machine-readable reason detail
            # @return [Hash] error result in the standard save-result shape
            def self.na_error_result(status_message, reason)
                {
                    'isSaved'       => false,
                    'presetCode'    => '',
                    'sourceFile'    => '',
                    'statusMessage' => status_message.to_s,
                    'reason'        => reason.to_s
                }
            end
            private_class_method :na_error_result
            # ---------------------------------------------------------------

        end
    end
end
