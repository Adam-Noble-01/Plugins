# =============================================================================
# NA COMPONENT EDITOR TOOLS - APPCORE UI BRIDGE (RUBY SIDE)
# =============================================================================
#
# FILE       : Na__ComponentEditorTools__AppCore__UiBridge__.rb
# NAMESPACE  : Na__ComponentEditorTools::Na__UiBridge
# PURPOSE    : Shared Ruby helpers for HtmlDialog callback registration and
#              Ruby-to-JavaScript payload pushes.
# CREATED    : 2026
#
# =============================================================================

require 'json'

module Na__ComponentEditorTools
    module Na__UiBridge

# -----------------------------------------------------------------------------
# REGION | Dialog Visibility Helpers
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__DialogVisible(dialog)
            dialog && dialog.respond_to?(:visible?) && dialog.visible?
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Ruby -> JavaScript Helpers
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__ExecuteScript(dialog, script_source)
            return false unless self.Na__ComponentEditorTools__DialogVisible(dialog)

            dialog.execute_script(script_source.to_s)
            true
        rescue => error
            puts "[Na__ComponentEditorTools] execute_script failed: #{error.class}: #{error.message}"
            false
        end

        def self.Na__ComponentEditorTools__ExecuteJsonFunction(dialog, function_name, payload_hash)
            return false unless self.Na__ComponentEditorTools__DialogVisible(dialog)

            script = <<~SCRIPT
            if (window.#{function_name}) {
                window.#{function_name}(#{JSON.generate(payload_hash)});
            }
            SCRIPT
            self.Na__ComponentEditorTools__ExecuteScript(dialog, script)
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | JavaScript -> Ruby Callback Registration
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__RegisterCallbacks(dialog, callback_registry)
            return 0 unless dialog && callback_registry.is_a?(Hash)

            count = 0
            callback_registry.each do |callback_name, callback_proc|
                next unless callback_proc.respond_to?(:call)

                dialog.add_action_callback(callback_name) do |_context, *raw_args|
                    callback_proc.call(*raw_args)
                rescue => error
                    puts "[Na__ComponentEditorTools] Callback '#{callback_name}' failed: #{error.class}: #{error.message}"
                end

                count += 1
            end

            count
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Payload Parsing Helpers
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__ParseJsonPayload(raw_payload)
            return {} if raw_payload.nil?
            return raw_payload if raw_payload.is_a?(Hash)

            text_payload = raw_payload.to_s.strip
            return {} if text_payload.empty?

            parsed_payload = JSON.parse(text_payload)
            parsed_payload.is_a?(Hash) ? parsed_payload : {}
        rescue JSON::ParserError
            {}
        end

# endregion -------------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
