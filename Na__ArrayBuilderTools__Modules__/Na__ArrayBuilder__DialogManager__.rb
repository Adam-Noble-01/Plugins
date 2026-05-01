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
# VERSION    : 0.0.3
#
# DESCRIPTION:
# - Creates and manages the UI::HtmlDialog instance
# - Sets up JavaScript -> Ruby action callbacks
# - Handles start-array action (activates the PathTool)
# - Activates the ObjectPicker tool when the user requests a custom
#   object source for the 'object' array type
# - Sends status, picked-object info and completion messages back to dialog
#
# =============================================================================

require 'sketchup.rb'
require 'json'
require_relative 'Na__ArrayBuilder__ObjectRegistry__'
require_relative 'Na__ArrayBuilder__ObjectPicker__'
require_relative 'Na__ArrayBuilder__PathTool__'
require_relative 'Na__ArrayBuilder__GeometryBuilder__'

module Na__ArrayBuilderTools
    module Na__ArrayBuilder__DialogManager

# -----------------------------------------------------------------------------
# REGION | Module Variables
# -----------------------------------------------------------------------------

        @dialog = nil

        # Memoised last preview-info payload: avoids JS-bridge round-trips
        # on every viewport refresh when nothing in the preview has changed.
        @na_last_preview_count   = nil
        @na_last_preview_length  = nil
        @na_last_preview_spacing = nil

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
                width: 400,
                height: 650,
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

            # Callback: Pick Custom Source Object (Object array type)
            @dialog.add_action_callback("na_pickObject") do |_ctx|
                na_handle_pick_object
            end

            # Callback: Clear Picked Custom Source Object
            @dialog.add_action_callback("na_clearObject") do |_ctx|
                na_handle_clear_object
            end

            # Callback: Log from JavaScript (quiet unless NA_DEBUG_LOG=true)
            @dialog.add_action_callback("na_jsLog") do |_ctx, message|
                Na__ArrayBuilderTools.na_debug_log("[JS] #{message}")
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

                if config['type'] == 'object'
                    return unless na_validate_object_source_or_warn
                end

                path_tool = Na__ArrayBuilder__PathTool.new(config, self)
                Sketchup.active_model.select_tool(path_tool)

                na_send_status_to_dialog("info", "Click to set start point...")
            rescue => e
                Na__ArrayBuilderTools.na_debug_log("start array error: #{e.message}")
                na_send_status_to_dialog("error", "Error: #{e.message}")
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Validate That a Source Object Has Been Picked
        # ------------------------------------------------------------
        # Used before launching the path tool in 'object' array mode.
        # Returns true when registry holds a usable definition. Sends a
        # warning to the dialog and returns false otherwise.
        def self.na_validate_object_source_or_warn
            if Na__ArrayBuilder__ObjectRegistry.Na__Registry__IsValid?
                return true
            end

            na_send_status_to_dialog(
                "warning",
                "Pick a Group or Component first (Object Source > Pick Object)"
            )
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Handle Pick Object Callback
        # ------------------------------------------------------------
        def self.na_handle_pick_object
            picker = Na__ArrayBuilder__ObjectPicker.new(self)
            Sketchup.active_model.select_tool(picker)
            na_send_status_to_dialog("info", "Click a Group or Component in the model...")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Handle Clear Object Callback
        # ------------------------------------------------------------
        def self.na_handle_clear_object
            Na__ArrayBuilder__ObjectRegistry.Na__Registry__Clear
            na_send_object_cleared
            na_send_status_to_dialog("info", "Source object cleared")
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
        # Throttled: skips the JS-bridge round-trip when count, length
        # and spacing are unchanged from the previous push. The path
        # tool's draw method calls this on every viewport refresh, so
        # the throttle removes a per-frame IPC hop and removes the
        # main source of viewport jank during path placement.
        def self.na_send_preview_info(count, total_length_mm, actual_spacing_mm = nil)
            return unless @dialog && @dialog.visible?

            length_rounded = total_length_mm.round

            return if @na_last_preview_count   == count        &&
                      @na_last_preview_length  == length_rounded &&
                      @na_last_preview_spacing == actual_spacing_mm

            @na_last_preview_count   = count
            @na_last_preview_length  = length_rounded
            @na_last_preview_spacing = actual_spacing_mm

            if actual_spacing_mm
                @dialog.execute_script("window.na_updatePreviewInfo(#{count}, #{length_rounded}, #{actual_spacing_mm});")
            else
                @dialog.execute_script("window.na_updatePreviewInfo(#{count}, #{length_rounded}, null);")
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Reset Memoised Preview Info
        # ------------------------------------------------------------
        # Called when the path tool starts/ends so the next preview
        # push always reaches the dialog.
        def self.na_reset_preview_info_memo
            @na_last_preview_count   = nil
            @na_last_preview_length  = nil
            @na_last_preview_spacing = nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Send Picked-Object Info to Dialog
        # ------------------------------------------------------------
        # Pushes the picked source-object's display name and bbox-derived
        # dimensions (in millimetres) to the dialog so the Object Source
        # panel can render them.
        def self.na_send_object_picked(name, w_mm, d_mm, h_mm)
            return unless @dialog && @dialog.visible?

            escaped = name.to_s.gsub("'", "\\\\'")
            @dialog.execute_script(
                "window.na_objectPicked('#{escaped}', #{w_mm.round(1)}, #{d_mm.round(1)}, #{h_mm.round(1)});"
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | Send Object-Cleared Notification to Dialog
        # ------------------------------------------------------------
        def self.na_send_object_cleared
            return unless @dialog && @dialog.visible?

            @dialog.execute_script("window.na_objectCleared();")
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
