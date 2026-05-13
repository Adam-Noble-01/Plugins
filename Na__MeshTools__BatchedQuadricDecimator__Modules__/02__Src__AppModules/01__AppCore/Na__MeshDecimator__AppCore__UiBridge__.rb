# =============================================================================
# NA MESH TOOLS - BATCHED QUADRIC DECIMATOR - UI BRIDGE (Ruby side)
# =============================================================================
#
# FILE       : Na__MeshDecimator__AppCore__UiBridge__.rb
# NAMESPACE  : Na__MeshDecimator::Na__AppCore::Na__UiBridge
# AUTHOR     : Adam Noble / Noble Architecture
# PURPOSE    : Single, app-wide bridge between Ruby and the HtmlDialog.
#              All Ruby -> JS calls and JS -> Ruby callback registration
#              go through this module.
#
# CONTRACT
# - Every Ruby -> JS call uses one of:
#     na_execute_json_function(dialog, fn_name, payload)
#     na_send_status(dialog, type, message)
#     na_invoke(dialog, fn_name, *args)
# - JS -> Ruby registration is always via na_register_callbacks(dialog, registry).
#
# =============================================================================

require 'json'
require 'sketchup.rb'

module Na__MeshDecimator
    module Na__AppCore
        module Na__UiBridge

            # -----------------------------------------------------------------
            # REGION | Guard Helpers
            # -----------------------------------------------------------------

            def self.na_dialog_visible?(dialog)
                dialog && dialog.respond_to?(:visible?) && dialog.visible?
            end
            private_class_method :na_dialog_visible?

            def self.na_escape_js_string(str)
                return '' if str.nil?
                str.to_s.gsub("'", "\\\\'")
            end
            private_class_method :na_escape_js_string

            # -----------------------------------------------------------------
            # REGION | Ruby -> JS Execution
            # -----------------------------------------------------------------

            def self.na_invoke(dialog, fn_name, *args)
                return false unless na_dialog_visible?(dialog)
                arg_str = args.map(&:to_s).join(', ')
                dialog.execute_script("if(typeof #{fn_name}==='function'){#{fn_name}(#{arg_str});}")
                true
            end

            # Serialises payload as JSON, escapes it, and calls the named JS
            # function with the JSON string as its sole argument.
            def self.na_execute_json_function(dialog, fn_name, payload)
                return false unless na_dialog_visible?(dialog)
                json_text = JSON.generate(payload)
                escaped   = na_escape_js_string(json_text)
                dialog.execute_script("if(typeof #{fn_name}==='function'){#{fn_name}('#{escaped}');}")
                true
            end

            # Push a status message to the JS na_showStatus handler.
            def self.na_send_status(dialog, type, message)
                return false unless na_dialog_visible?(dialog)
                t = na_escape_js_string(type)
                m = na_escape_js_string(message)
                dialog.execute_script(
                    "if(typeof window.Na__MeshDecimator__Ui__ShowStatus==='function'){" \
                    "window.Na__MeshDecimator__Ui__ShowStatus('#{t}','#{m}');}"
                )
                true
            end

            # -----------------------------------------------------------------
            # REGION | Callback Registration
            # -----------------------------------------------------------------

            # Register a map of JS callback names -> Ruby Procs on a dialog.
            # Errors inside each handler are caught, logged to the Ruby
            # console, and surfaced to the JS status bar.
            #
            # @param dialog   [UI::HtmlDialog]
            # @param registry [Hash{String=>Proc}]
            # @return [Integer] number of callbacks registered
            def self.na_register_callbacks(dialog, registry)
                return 0 unless dialog && registry.is_a?(Hash)
                count = 0

                registry.each do |name, handler|
                    next unless handler.respond_to?(:call)

                    dialog.add_action_callback(name) do |_ctx, *raw_args|
                        begin
                            handler.call(*raw_args)
                        rescue StandardError => e
                            puts "[!] Na__MeshDecimator UiBridge — callback '#{name}' failed: #{e.message}"
                            puts e.backtrace.first.to_s
                            na_send_status(dialog, 'error', "#{name} failed: #{e.message}")
                        end
                    end

                    count += 1
                end

                puts "[+] Na__MeshDecimator UiBridge — registered #{count} callbacks"
                count
            end

        end
    end
end
