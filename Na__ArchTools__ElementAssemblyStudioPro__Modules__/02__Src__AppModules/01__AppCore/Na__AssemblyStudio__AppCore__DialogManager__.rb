# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - DIALOG MANAGER (generic chrome only)
# =============================================================================
#
# FILE       : Na__AssemblyStudio__AppCore__DialogManager__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__AppCore
# MODULE     : Na__DialogManager
# AUTHOR     : Noble Architecture
# PURPOSE    : Generic HtmlDialog chrome only. Owns the dialog lifecycle, the
#              tab cache, the developer reload flow, the settings/devtools
#              glue and the fallback HTML. Window/door specific create/update/
#              live-update handlers live in their respective system folders
#              (see WindowDialogCallbacks and InteriorDoorSystem DialogRouter).
#
# REFACTOR NOTES (v2 / EASP):
# - ~480-550 lines of window-specific handler code from the original
#   1037-line DialogManager moved out to WindowSystem/DialogCallbacks.
# - JSON.generate + gsub + execute_script boilerplate replaced by UiBridge.
# - Reload uses Pathname#relative_path_from instead of manual tr/string concat.
# - All raw `puts` routed through DebugTools.
#
# =============================================================================

require 'sketchup.rb'
require 'json'
require 'pathname'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative 'Na__AssemblyStudio__AppCore__UiBridge__'

module Na__AssemblyStudio
    module Na__AppCore
        module Na__DialogManager

            DebugTools = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
            UiBridge   = Na__AssemblyStudio::Na__AppCore::Na__UiBridge

            # -----------------------------------------------------------------
            # REGION | State
            # -----------------------------------------------------------------

            @na_dialog            = nil
            @na_active_tab_id     = "windows"
            @na_html_path         = nil
            @na_modules_root_path = nil
            @na_system_init_hooks = []          # [Proc(dialog), ...] invoked once on each (re)open

            def self.na_get_dialog
                @na_dialog
            end

            def self.na_get_active_tab_id
                @na_active_tab_id || "windows"
            end

            def self.na_get_modules_root_path
                @na_modules_root_path
            end

            def self.na_register_system_init_hook(&block)
                @na_system_init_hooks << block if block_given?
            end

            # -----------------------------------------------------------------
            # REGION | Dialog Lifecycle
            # -----------------------------------------------------------------

            def self.na_show_dialog(html_file_path, modules_root_path)
                DebugTools.na_debug_method("AppCore::DialogManager.na_show_dialog")

                @na_html_path         = html_file_path
                @na_modules_root_path = modules_root_path

                if @na_dialog && @na_dialog.visible?
                    @na_dialog.close
                end

                @na_dialog = UI::HtmlDialog.new(
                    dialog_title:    "Element Assembly Studio Pro by Noble Architecture",
                    preferences_key: "Na__AssemblyStudio",
                    scrollable:      true,
                    resizable:       true,
                    width:           780,
                    height:          1200,
                    left:            100,
                    top:             100,
                    style:           UI::HtmlDialog::STYLE_DIALOG
                )

                if File.exist?(html_file_path)
                    @na_dialog.set_file(html_file_path)
                    DebugTools.na_debug_ui("Loaded HTML from: #{html_file_path}")
                else
                    DebugTools.na_debug_error("HTML file not found: #{html_file_path}")
                    @na_dialog.set_html(na_create_fallback_html)
                end

                na_setup_core_callbacks
                na_invoke_system_init_hooks(@na_dialog)
                @na_dialog.show
            end

            def self.na_invoke_system_init_hooks(dialog)
                @na_system_init_hooks.each do |hook|
                    begin
                        hook.call(dialog)
                    rescue StandardError => e
                        DebugTools.na_debug_error("System init hook failed", e)
                    end
                end
            end
            private_class_method :na_invoke_system_init_hooks

            def self.na_request_tab_switch(tab_id)
                return unless @na_dialog && @na_dialog.visible?
                return if tab_id.nil?
                safe_id = tab_id.to_s.gsub(/[^A-Za-z0-9_-]/, "")
                return if safe_id.empty?
                @na_dialog.execute_script(
                    "if(window.Na_AppContext){Na_AppContext.na_activateTab('#{safe_id}');}"
                )
                @na_active_tab_id = safe_id
                DebugTools.na_debug_ui("Requested tab switch to #{safe_id}")
            end

            # -----------------------------------------------------------------
            # REGION | Core Callback Registration
            # -----------------------------------------------------------------

            # Only truly tab-agnostic callbacks live here. Window/door system
            # callbacks register themselves in their system Init via
            # UiBridge.na_register_callbacks(dialog, ...).
            def self.na_setup_core_callbacks
                core_registry = {
                    "na_reloadScripts"      => proc { na_reload_scripts(@na_modules_root_path) },
                    "na_settingsExport2D"   => proc { na_handle_settings_export_2d },
                    "na_settingsExport3D"   => proc { na_handle_settings_export_3d },
                    "na_jsLog"              => proc { |message| DebugTools.na_debug_ui("[JS] #{message}") },
                    "na_setActiveTab"       => proc { |tab_id|
                        @na_active_tab_id = tab_id.to_s if tab_id
                        DebugTools.na_debug_ui("Active tab cached: #{@na_active_tab_id}")
                    }
                }
                UiBridge.na_register_callbacks(@na_dialog, core_registry)
            end

            # -----------------------------------------------------------------
            # REGION | Dev Tools Settings Glue
            # -----------------------------------------------------------------

            def self.na_handle_settings_export_2d
                unless defined?(::Na__AssemblyStudio::Na__DevTools)
                    UiBridge.na_send_status(@na_dialog, "warning", "Dev tools not loaded - check 65__Dev__DevTools/")
                    return
                end
                ::Na__AssemblyStudio::Na__DevTools.na_run_export_2d
                UiBridge.na_send_status(@na_dialog, "info", "2D exporter finished - see Ruby Console")
            rescue StandardError => e
                DebugTools.na_debug_error("Settings 2D export failed", e)
                UiBridge.na_send_status(@na_dialog, "warning", "2D export failed: #{e.message}")
            end

            def self.na_handle_settings_export_3d
                unless defined?(::Na__AssemblyStudio::Na__DevTools)
                    UiBridge.na_send_status(@na_dialog, "warning", "Dev tools not loaded - check 65__Dev__DevTools/")
                    return
                end
                ::Na__AssemblyStudio::Na__DevTools.na_run_export_3d
                UiBridge.na_send_status(@na_dialog, "info", "3D exporter finished - see Ruby Console")
            rescue StandardError => e
                DebugTools.na_debug_error("Settings 3D export failed", e)
                UiBridge.na_send_status(@na_dialog, "warning", "3D export failed: #{e.message}")
            end

            # -----------------------------------------------------------------
            # REGION | Reload Scripts (developer feature)
            # -----------------------------------------------------------------

            # Reloadable Ruby file roots (relative to the modules root). Each
            # entry is a Pathname-friendly relative path. Adding a new system
            # is a one-line change here.
            NA_RELOAD_RB_ROOTS = [
                "02__Src__AppModules/01__AppCore",
                "02__Src__AppModules/02__AppData",
                "02__Src__AppModules/03__AppUtils",
                "02__Src__AppModules/04__GeometryHelpers",
                "02__Src__AppModules/06__Tools__MeasurementTools",
                "02__Src__AppModules/07__Tools__PlacementTools",
                "02__Src__AppModules/20__System__WindowSystem",
                "02__Src__AppModules/30__System__ExteriorDoorSystem",
                "02__Src__AppModules/40__System__InteriorDoorSystem",
                "65__Dev__DevTools"
            ].freeze

            def self.na_collect_rb_files_for_reload(modules_root_path)
                root_pn = Pathname.new(modules_root_path)
                NA_RELOAD_RB_ROOTS.flat_map do |rel|
                    abs_dir = root_pn.join(rel)
                    if abs_dir.directory?
                        Dir.glob(abs_dir.join("**", "*.rb").to_s)
                    else
                        []
                    end
                end.uniq.sort
            end

            def self.na_format_reload_path(file_path, modules_root_path)
                Pathname.new(file_path).relative_path_from(Pathname.new(modules_root_path)).to_s
            rescue ArgumentError
                File.basename(file_path)
            end

            def self.na_reload_scripts(modules_root_path)
                DebugTools.na_debug_method("AppCore::DialogManager.na_reload_scripts")
                rb_count    = 0
                error_count = 0

                files = na_collect_rb_files_for_reload(modules_root_path)
                files.each do |file|
                    begin
                        load file
                        DebugTools.na_debug_info("[OK] #{na_format_reload_path(file, modules_root_path)}")
                        rb_count += 1
                    rescue StandardError => e
                        DebugTools.na_debug_error("[ERROR] #{na_format_reload_path(file, modules_root_path)}: #{e.message}", e)
                        error_count += 1
                    end
                end

                UI.refresh_inspectors if UI.respond_to?(:refresh_inspectors)

                if @na_dialog && @na_dialog.visible?
                    @na_dialog.close
                    na_show_dialog(@na_html_path, modules_root_path)
                end

                if error_count > 0
                    UiBridge.na_send_status(@na_dialog, "warning", "Reloaded #{rb_count} Ruby files with #{error_count} errors")
                else
                    UiBridge.na_send_status(@na_dialog, "success", "Reloaded #{rb_count} Ruby files")
                end

                { reload_dialog: true }
            end

            # -----------------------------------------------------------------
            # REGION | Fallback HTML
            # -----------------------------------------------------------------

            def self.na_create_fallback_html
                <<~HTML
                <!DOCTYPE html>
                <html>
                <head>
                    <meta charset="UTF-8">
                    <title>Element Assembly Studio Pro</title>
                    <style>
                        body { font-family: Arial, sans-serif; padding: 20px; background: #2d2d2d; color: #fff; }
                        .error { color: #ff6b6b; background: #3d2d2d; padding: 15px; border-radius: 5px; }
                        button { background: #4a90d9; color: white; border: none; padding: 10px 20px; cursor: pointer; margin: 5px; }
                        button:hover { background: #5a9fe9; }
                    </style>
                </head>
                <body>
                    <h2>Element Assembly Studio Pro by Noble Architecture</h2>
                    <div class="error">
                        <strong>Error:</strong> HTML layout file not found.<br>
                        Expected: Na__AssemblyStudio__UiLayout__.html in the modules folder.
                    </div>
                    <button type="button" onclick="sketchup.na_reloadScripts()">Reload Scripts</button>
                    <script>
                        window.na_setInitialConfig    = function(json) { console.log('Config received'); };
                        window.na_clearCurrentWindow  = function() { console.log('Window cleared'); };
                        window.na_showStatus          = function(type, msg) { console.log(type + ': ' + msg); };
                    </script>
                </body>
                </html>
                HTML
            end

        end
    end
end
