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
require_relative '../02__AppData/Na__AssemblyStudio__AppData__MaterialManager__'
require_relative '../02__AppData/Na__AssemblyStudio__AppData__EdgeColourManager__'
require_relative '../02__AppData/Na__AssemblyStudio__AppData__FrameFinishSwatches__'
require_relative '../../../Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__CacheData__'
require_relative 'Na__AssemblyStudio__AppCore__UiBridge__'

module Na__AssemblyStudio
    module Na__AppCore
        module Na__DialogManager

            DebugTools          = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
            UiBridge            = Na__AssemblyStudio::Na__AppCore::Na__UiBridge
            MaterialManager     = Na__AssemblyStudio::Na__AppData::Na__MaterialManager
            EdgeColourManager   = Na__AssemblyStudio::Na__AppData::Na__EdgeColourManager
            FrameFinishSwatches = Na__AssemblyStudio::Na__AppData::Na__FrameFinishSwatches

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

                # Force-refresh the materials AND edge-colour libraries from
                # the live URL on every dialog open. Cache files are preserved
                # for internet dropouts. The edge-colour palette feeds the
                # door panel design subsystem (Na__PanelDesignBuilder) so it
                # must be hot before any door geometry is generated.
                MaterialManager.na_force_refresh_from_url
                EdgeColourManager.na_force_refresh_from_url

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
                na_register_swatch_push_callback(@na_dialog)
                @na_dialog.show
                na_schedule_proactive_swatch_push(@na_dialog)
            end

            # Push the frame-finish swatches into JS exactly once, after the
            # dialog DOM is fully parsed and ready. The HTML side calls
            # sketchup.na_requestFrameFinishSwatches() on DOMContentLoaded.
            def self.na_register_swatch_push_callback(dialog)
                dialog.add_action_callback("na_requestFrameFinishSwatches") do |_ctx|
                    DebugTools.na_debug_ui("[DialogManager] na_requestFrameFinishSwatches callback invoked from JS")
                    FrameFinishSwatches.na_push_to_dialog(dialog)
                end
            end
            private_class_method :na_register_swatch_push_callback

            # Belt-and-braces: push swatches from Ruby a moment after `show`
            # so the cards still populate even if the JS bootstrap script
            # never reaches the sketchup.na_requestFrameFinishSwatches call
            # (e.g. callback not yet bound, transient bridge timing issue).
            # Idempotent because the JS-triggered push and this timed push
            # both call the same na_push_to_dialog.
            def self.na_schedule_proactive_swatch_push(dialog)
                UI.start_timer(0.5, false) do
                    begin
                        if dialog && dialog.respond_to?(:visible?) && dialog.visible?
                            DebugTools.na_debug_ui("[DialogManager] Proactive swatch push (0.5s after show)")
                            FrameFinishSwatches.na_push_to_dialog(dialog)
                        end
                    rescue StandardError => e
                        DebugTools.na_debug_error("[DialogManager] Proactive swatch push failed", e)
                    end
                end
            end
            private_class_method :na_schedule_proactive_swatch_push

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

            # Ruby paths swept by developer reload (`na_reload_scripts`).
            #
            # Use one recursive glob per tree so newly added systems (for
            # example `05__Viewport__2dPreviewEngine`) are picked up without
            # remembering to extend a manual folder list.

            NA_RELOAD_GLOB_SEGMENTS = [
                File.join("02__Src__AppModules", "**", "*.rb"),
                File.join("65__Dev__DevTools", "**", "*.rb"),
            ].freeze

            def self.na_collect_rb_files_for_reload(modules_root_path)
                root_pn = Pathname.new(modules_root_path)
                files = NA_RELOAD_GLOB_SEGMENTS.flat_map do |segment|
                    pattern = root_pn.join(segment).to_s
                    Dir.glob(pattern).select { |path| File.file?(path) }
                end

                files.uniq.sort
            end

            def self.na_format_reload_path(file_path, modules_root_path)
                Pathname.new(file_path).relative_path_from(Pathname.new(modules_root_path)).to_s
            rescue ArgumentError
                File.basename(file_path)
            end

            # HELPER FUNCTION | Reload Ruby File With Constant Warnings Silenced
            # ------------------------------------------------------------
            # During developer reload we intentionally re-evaluate modules.
            # Temporarily disabling $VERBOSE suppresses noisy "already
            # initialized constant" warnings for that reload pass only.
            # ---------------------------------------------------------------
            def self.na_reload_file_without_verbose_constant_warnings(file_path)
                previous_verbose = $VERBOSE
                $VERBOSE = nil
                load file_path
            ensure
                $VERBOSE = previous_verbose
            end
            private_class_method :na_reload_file_without_verbose_constant_warnings

            # FUNCTION | Replay Interior-Door Bootstrap Side Effects Post-Reload
            # ------------------------------------------------------------
            # `Kernel#load` replaces method bodies but does not unwind
            # `require_relative`, and Ruby keeps lazily-loaded door state warm.
            #
            # - Clears `@na_door_modules_loaded` so the next HtmlDialog bootstrap
            #   passes through `Na__InteriorDoorSystem.na_require_door_modules`
            #   again (replays AssetLibrary root assignment and keeps any new
            #   future side effects in that funnel discoverable).
            # - Drops parsed JSON caches and cached handle ComponentDefinitions
            #   so geometry/metadata edits on disk flush through immediately.
            def self.na_finalize_developer_reload
                if defined?(::Na__AssemblyStudio::Na__InteriorDoorSystem) &&
                   ::Na__AssemblyStudio::Na__InteriorDoorSystem.respond_to?(:na_reset_door_module_load_gate_for_developer_reload)
                    ::Na__AssemblyStudio::Na__InteriorDoorSystem.na_reset_door_module_load_gate_for_developer_reload
                end

                if defined?(::Na__AssemblyStudio::Na__InteriorDoorSystem::Na__AssetLibrary)
                    ::Na__AssemblyStudio::Na__InteriorDoorSystem::Na__AssetLibrary.na_clear_caches
                end

                if defined?(::Na__AssemblyStudio::Na__InteriorDoorSystem::Na__HandleBuilder3D)
                    ::Na__AssemblyStudio::Na__InteriorDoorSystem::Na__HandleBuilder3D.na_clear_definition_cache
                end
            rescue StandardError => e
                DebugTools.na_debug_warn("Developer reload finalize failed: #{e.message}")
            end
            private_class_method :na_finalize_developer_reload

            def self.na_reload_scripts(modules_root_path)
                DebugTools.na_debug_method("AppCore::DialogManager.na_reload_scripts")
                rb_count    = 0
                error_count = 0

                # STEP 1 | Purge the materials AND edge-materials cache files
                # and force-fetch fresh JSON from the live URLs BEFORE
                # reloading Ruby files. This guarantees the next dialog open
                # sees the latest published palette (face materials, edge
                # MTE colours, swatches) and is NOT served stale on-disk
                # cached JSON.
                materials_source = na_force_refresh_materials_json
                edge_materials_source = na_force_refresh_edge_materials_json

                # STEP 2 | Reload all plugin Ruby files in place (`load`).
                files = na_collect_rb_files_for_reload(modules_root_path)
                files.each do |file|
                    begin
                        na_reload_file_without_verbose_constant_warnings(file)
                        rb_count += 1
                    rescue StandardError => e
                        DebugTools.na_debug_error("[ERROR] #{na_format_reload_path(file, modules_root_path)}: #{e.message}", e)
                        error_count += 1
                    end
                end

                na_finalize_developer_reload

                UI.refresh_inspectors if UI.respond_to?(:refresh_inspectors)

                # STEP 3 | Close + reopen the dialog so the freshly-loaded Ruby
                # state and the freshly-fetched JSON both flow through to JS.
                if @na_dialog && @na_dialog.visible?
                    @na_dialog.close
                    na_show_dialog(@na_html_path, modules_root_path)
                end

                summary = "✅ #{rb_count} scripts reloaded"
                if materials_source == :failed || edge_materials_source == :failed
                    summary = "#{summary} (asset refresh fallback)"
                end
                if error_count > 0
                    summary = "⚠ #{rb_count} scripts reloaded (#{error_count} errors)"
                    puts "    [Reload] #{summary}"
                    UiBridge.na_send_status(@na_dialog, "warning", summary)
                else
                    puts "    [Reload] #{summary}"
                    UiBridge.na_send_status(@na_dialog, "success", summary)
                end

                { reload_dialog: true }
            end

            # Purge cache + force-fetch the materials JSON from the live URL.
            # Returns :url, :cache, :local, or :failed for surfacing in the
            # status bar so the user knows where the data came from.
            def self.na_force_refresh_materials_json
                Na__DataLib__CacheData.Na__Cache__PurgeCacheFile(:materials)
                Na__DataLib__CacheData.Na__Cache__LoadData(:materials, true)
                source = Na__DataLib__CacheData.Na__Cache__LastSource(:materials)
                source || :failed
            rescue StandardError => e
                DebugTools.na_debug_warn("[Reload] Materials force-fetch raised: #{e.message}")
                :failed
            end
            private_class_method :na_force_refresh_materials_json

            # Purge cache + force-fetch the edge-materials (MTE) JSON from
            # the live URL. Mirrors na_force_refresh_materials_json so the
            # door panel design subsystem sees fresh edge colours after a
            # developer reload.
            def self.na_force_refresh_edge_materials_json
                Na__DataLib__CacheData.Na__Cache__PurgeCacheFile(:edge_materials)
                Na__DataLib__CacheData.Na__Cache__LoadData(:edge_materials, true)
                source = Na__DataLib__CacheData.Na__Cache__LastSource(:edge_materials)
                source || :failed
            rescue StandardError => e
                DebugTools.na_debug_warn("[Reload] Edge materials force-fetch raised: #{e.message}")
                :failed
            end
            private_class_method :na_force_refresh_edge_materials_json

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
