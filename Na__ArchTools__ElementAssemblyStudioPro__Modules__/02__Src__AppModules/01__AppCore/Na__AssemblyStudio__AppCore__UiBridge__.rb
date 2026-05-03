# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - UI BRIDGE (Ruby side)
# =============================================================================
#
# FILE       : Na__AssemblyStudio__AppCore__UiBridge__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__AppCore
# MODULE     : Na__UiBridge
# AUTHOR     : Noble Architecture
# PURPOSE    : Single, app-wide bridge between Ruby and the HtmlDialog. Replaces
#              the four+ duplicated `JSON.generate + gsub + execute_script`
#              patterns that were sprinkled across DialogManager and DialogRouter.
#
# CONTRACT
# - Every Ruby->JS call goes through one of:
#     na_execute_json_function(dialog, fn_name, payload)
#     na_execute_numeric_function(dialog, fn_name, *floats)
#     na_send_status(dialog, type, message)
#     na_invoke(dialog, fn_name, *args)
# - Every system-side callback registry is built via na_register_callbacks.
#
# =============================================================================

require 'json'
require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'

module Na__AssemblyStudio
    module Na__AppCore
        module Na__UiBridge

            DebugTools = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools

            # -----------------------------------------------------------------
            # REGION | JS string escaping
            # -----------------------------------------------------------------

            def self.na_escape_js_string(str)
                return "" if str.nil?
                str.to_s.gsub("'", "\\\\'")
            end

            # -----------------------------------------------------------------
            # REGION | Ruby -> JS execution helpers
            # -----------------------------------------------------------------

            def self.na_dialog_visible?(dialog)
                dialog && dialog.respond_to?(:visible?) && dialog.visible?
            end

            def self.na_invoke(dialog, fn_name, *args)
                return false unless na_dialog_visible?(dialog)
                arg_str = args.map { |a| a.to_s }.join(", ")
                dialog.execute_script("if(typeof #{fn_name}==='function'){#{fn_name}(#{arg_str});}")
                true
            end

            def self.na_execute_json_function(dialog, fn_name, payload)
                return false unless na_dialog_visible?(dialog)
                json_text   = JSON.generate(payload)
                escaped     = na_escape_js_string(json_text)
                dialog.execute_script("if(typeof #{fn_name}==='function'){#{fn_name}('#{escaped}');}")
                true
            end

            def self.na_execute_numeric_function(dialog, fn_name, *floats)
                return false unless na_dialog_visible?(dialog)
                cast = floats.map { |f| Float(f.to_f) }
                dialog.execute_script("if(typeof #{fn_name}==='function'){#{fn_name}(#{cast.join(', ')});}")
                true
            end

            def self.na_send_status(dialog, type, message, persistent: false)
                return false unless na_dialog_visible?(dialog)
                t              = na_escape_js_string(type)
                m              = na_escape_js_string(message)
                persistent_flag = persistent ? "true" : "false"
                dialog.execute_script(
                    "if(typeof window.na_showStatus==='function'){" \
                    "window.na_showStatus('#{t}', '#{m}', #{persistent_flag});}"
                )
                true
            end

            # -----------------------------------------------------------------
            # REGION | Callback registration
            # -----------------------------------------------------------------

            # FUNCTION | Register a Map of JS -> Ruby Callbacks on a Dialog
            # ---------------------------------------------------
            # @param dialog [UI::HtmlDialog]
            # @param registry [Hash{String=>Proc}] callback name -> handler proc
            #   Each handler is called with the raw payload(s) the JS side
            #   sent. Errors are caught at the boundary, logged via
            #   DebugTools, and surfaced to the user via na_send_status.
            # @return [Integer] number of callbacks registered
            def self.na_register_callbacks(dialog, registry)
                return 0 unless dialog && registry.is_a?(Hash)
                count = 0
                registry.each do |name, handler|
                    next unless handler.respond_to?(:call)
                    dialog.add_action_callback(name) do |_action_context, *raw_args|
                        begin
                            handler.call(*raw_args)
                        rescue StandardError => e
                            DebugTools.na_debug_error("Callback '#{name}' failed: #{e.message}", e)
                            na_send_status(dialog, 'error', "#{name} failed: #{e.message}")
                        end
                    end
                    count += 1
                end
                DebugTools.na_debug_ui("UiBridge: registered #{count} callbacks")
                count
            end

            # -----------------------------------------------------------------
            # REGION | Convenience: deep clone (replaces Marshal/Marshal sprinkles)
            # -----------------------------------------------------------------

            def self.na_deep_clone(obj)
                Marshal.load(Marshal.dump(obj))
            end

        end
    end
end
