# =============================================================================
# NA ARRAY BUILDER TOOLS - DIALOG MANAGER
# =============================================================================
#
# FILE       : Na__ArrayBuilder__DialogManager__.rb
# NAMESPACE  : Na__ArrayBuilderTools
# MODULE     : Na__ArrayBuilder__DialogManager
# AUTHOR     : Noble Architecture
# PURPOSE    : Manages UI::HtmlDialog and JS <-> Ruby communication
# CREATED    : 2026
# VERSION    : 0.0.2
#
# DESCRIPTION:
# - Creates and manages the UI::HtmlDialog instance
# - Sets up JavaScript -> Ruby action callbacks
# - Handles start-array action (activates the PathTool)
# - Sends status and completion messages back to dialog
#
# =============================================================================

require 'sketchup.rb'
require 'json'
require_relative 'Na__ArrayBuilder__PathTool__'
require_relative 'Na__ArrayBuilder__GeometryBuilder__'

module Na__ArrayBuilderTools
    module Na__ArrayBuilder__DialogManager

# -----------------------------------------------------------------------------
# REGION | Module Variables
# -----------------------------------------------------------------------------

        @dialog = nil

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dialog Lifecycle
# -----------------------------------------------------------------------------

        # FUNCTION | Show Configuration Dialog
        # ------------------------------------------------------------
        def self.na_show_dialog(html_file_path, plugin_root_path)
            if @dialog && @dialog.visible?
                @dialog.bring_to_front
                return
            end

            @dialog = UI::HtmlDialog.new(
                dialog_title: "Na Array Builder",
                preferences_key: "Na__ArrayBuilderTools",
                scrollable: true,
                resizable: true,
                width: 360,
                height: 540,
                left: 100,
                top: 100,
                style: UI::HtmlDialog::STYLE_DIALOG
            )

            if File.exist?(html_file_path)
                @dialog.set_file(html_file_path)
            else
                puts "✗ Na Array Builder HTML not found: #{html_file_path}"
                @dialog.set_html(na_create_fallback_html)
            end

            na_setup_dialog_callbacks(plugin_root_path)
            @dialog.show
        end
        # ---------------------------------------------------------------

        # FUNCTION | Get Dialog Instance
        # ------------------------------------------------------------
        def self.na_get_dialog
            @dialog
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Callback Setup
# -----------------------------------------------------------------------------

        # FUNCTION | Setup Dialog Action Callbacks
        # ------------------------------------------------------------
        def self.na_setup_dialog_callbacks(plugin_root_path)

            # Callback: Start Array Placement
            @dialog.add_action_callback("na_startArray") do |_ctx, config_json|
                na_handle_start_array(config_json)
            end

            # Callback: Log from JavaScript
            @dialog.add_action_callback("na_jsLog") do |_ctx, message|
                puts "[NA_ArrayBuilder JS] #{message}"
            end

            # Callback: Reload Scripts (Developer Feature)
            @dialog.add_action_callback("na_reloadScripts") do |_ctx|
                na_reload_scripts(plugin_root_path)
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Callback Handlers
# -----------------------------------------------------------------------------

        # FUNCTION | Handle Start Array Callback
        # ------------------------------------------------------------
        def self.na_handle_start_array(config_json)
            begin
                config = JSON.parse(config_json)

                path_tool = Na__ArrayBuilder__PathTool.new(config, self)
                Sketchup.active_model.select_tool(path_tool)

                na_send_status_to_dialog("info", "Click to set start point...")
            rescue => e
                puts "✗ Na Array Builder error: #{e.message}"
                na_send_status_to_dialog("error", "Error: #{e.message}")
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Reload Scripts (Developer Feature)
        # ------------------------------------------------------------
        def self.na_reload_scripts(plugin_root_path)
            puts "\n" + "=" * 60
            puts "NA ARRAY BUILDER - RELOADING SCRIPTS"
            puts "=" * 60

            rb_files = Dir.glob(File.join(plugin_root_path, "*.rb"))
            rb_files.each do |file|
                begin
                    load file
                    puts "  [OK] #{File.basename(file)}"
                rescue => e
                    puts "  [ERROR] #{File.basename(file)}: #{e.message}"
                end
            end

            puts "=" * 60 + "\n"

            if @dialog && @dialog.visible?
                @dialog.close
            end

            return { reload_dialog: true }
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dialog Communication
# -----------------------------------------------------------------------------

        # FUNCTION | Send Status Message to Dialog
        # ------------------------------------------------------------
        def self.na_send_status_to_dialog(status_type, message)
            return unless @dialog && @dialog.visible?

            escaped = message.gsub("'", "\\\\'")
            @dialog.execute_script("window.na_showStatus('#{status_type}', '#{escaped}');")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Send Array Complete Notification to Dialog
        # ------------------------------------------------------------
        def self.na_send_array_complete(count)
            return unless @dialog && @dialog.visible?

            @dialog.execute_script("window.na_arrayComplete(#{count});")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Send Preview Info Update to Dialog
        # ------------------------------------------------------------
        def self.na_send_preview_info(count, total_length_mm, actual_spacing_mm = nil)
            return unless @dialog && @dialog.visible?

            if actual_spacing_mm
                @dialog.execute_script("window.na_updatePreviewInfo(#{count}, #{total_length_mm.round}, #{actual_spacing_mm});")
            else
                @dialog.execute_script("window.na_updatePreviewInfo(#{count}, #{total_length_mm.round}, null);")
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Fallback HTML
# -----------------------------------------------------------------------------

        # FUNCTION | Create Fallback HTML
        # ------------------------------------------------------------
        def self.na_create_fallback_html
            <<~HTML
            <!DOCTYPE html>
            <html>
            <head>
                <meta charset="UTF-8">
                <title>Na Array Builder</title>
                <style>
                    body { font-family: Arial, sans-serif; padding: 20px; background: #2d2d2d; color: #fff; }
                    .error { color: #ff6b6b; background: #3d2d2d; padding: 15px; border-radius: 5px; }
                    button { background: #4a90d9; color: white; border: none; padding: 10px 20px; cursor: pointer; }
                    button:hover { background: #5a9fe9; }
                </style>
            </head>
            <body>
                <h2>Na Array Builder</h2>
                <div class="error">
                    <strong>Error:</strong> HTML layout file not found.<br>
                    Ensure Na__ArrayBuilder__UiLayout__.html exists in the modules folder.
                </div>
                <br>
                <button onclick="sketchup.na_reloadScripts()">Reload Scripts</button>
                <script>
                    window.na_showStatus = function(type, msg) { console.log(type + ': ' + msg); };
                    window.na_arrayComplete = function(count) { console.log('Complete: ' + count); };
                    window.na_updatePreviewInfo = function(c, l) { console.log('Preview: ' + c + ' units'); };
                </script>
            </body>
            </html>
            HTML
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__ArrayBuilder__DialogManager
end # module Na__ArrayBuilderTools

# =============================================================================
# END OF FILE
# =============================================================================
