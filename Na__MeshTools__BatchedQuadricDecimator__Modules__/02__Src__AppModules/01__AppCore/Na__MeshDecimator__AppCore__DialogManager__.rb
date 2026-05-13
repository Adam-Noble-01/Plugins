# =============================================================================
# NA MESH TOOLS - BATCHED QUADRIC DECIMATOR - DIALOG MANAGER
# =============================================================================
#
# FILE       : Na__MeshDecimator__AppCore__DialogManager__.rb
# NAMESPACE  : Na__MeshDecimator::Na__AppCore::Na__DialogManager
# AUTHOR     : Adam Noble / Noble Architecture
# PURPOSE    : Owns the UI::HtmlDialog lifecycle.  Constructs and shows the
#              dialog, wires all Ruby <-> JS callbacks, and handles the
#              na_run_decimation and na_reload_scripts callbacks.
#
# JS CALLBACKS REGISTERED
#   na_run_decimation(options_json)  — parse options, run Ruby orchestrator, push result
#   na_run_native_decimation(options_json) — parse options, run C++ orchestrator, push result
#   na_request_group_count           — push current selection group count to JS
#   na_reload_scripts                — hot-reload all plugin Ruby files
#   na_jsLog(message)                — forward JS console messages to Ruby console
#
# @delegate: 01__AppCore/Na__MeshDecimator__AppCore__UiBridge__.rb
# @delegate: 05__Orchestrator/Na__MeshDecimator__Orchestrator__RunDecimation__.rb
# @delegate: 05__Orchestrator/Na__MeshDecimator__Orchestrator__RunNativeDecimation__.rb
#
# =============================================================================

require 'sketchup.rb'
require 'json'
require_relative 'Na__MeshDecimator__AppCore__UiBridge__'

module Na__MeshDecimator
    module Na__AppCore
        module Na__DialogManager

            UiBridge          = Na__MeshDecimator::Na__AppCore::Na__UiBridge
            Orchestrator      = Na__MeshDecimator::Na__Orchestrator::Na__RunDecimation
            NativeOrchestrator = Na__MeshDecimator::Na__Orchestrator::Na__RunNativeDecimation
            Collector         = Na__MeshDecimator::Na__GroupSelection::Na__Collector

            # -----------------------------------------------------------------
            # REGION | State
            # -----------------------------------------------------------------

            @na_dialog       = nil
            @na_html_path    = nil
            @na_modules_root = nil

            def self.na_get_dialog
                @na_dialog
            end

            # -----------------------------------------------------------------
            # REGION | Dialog Lifecycle
            # -----------------------------------------------------------------

            def self.na_show_dialog(html_file_path, modules_root_path)
                @na_html_path    = html_file_path
                @na_modules_root = modules_root_path

                if @na_dialog && @na_dialog.visible?
                    @na_dialog.bring_to_front
                    return
                end

                config = na_load_ui_config(modules_root_path)

                @na_dialog = UI::HtmlDialog.new(
                    dialog_title:    config['title'],
                    preferences_key: 'Na__MeshDecimator',
                    scrollable:      true,
                    resizable:       true,
                    width:           config['width'],
                    height:          config['height'],
                    left:            200,
                    top:             100,
                    style:           UI::HtmlDialog::STYLE_DIALOG
                )

                if File.exist?(html_file_path)
                    @na_dialog.set_file(html_file_path)
                    puts "[+] Na__MeshDecimator DialogManager — HTML loaded"
                else
                    puts "[!] Na__MeshDecimator DialogManager — HTML not found, using fallback"
                    @na_dialog.set_html(na_create_fallback_html)
                end

                na_setup_callbacks
                @na_dialog.show
            end

            # -----------------------------------------------------------------
            # REGION | Config Loading
            # -----------------------------------------------------------------

            def self.na_load_ui_config(modules_root_path)
                config_path = File.join(modules_root_path, '04__Data__AppData', 'Na__MeshDecimator__AppConfig__Main.json')

                if File.exist?(config_path)
                    raw    = File.read(config_path)
                    parsed = JSON.parse(raw)
                    ui     = parsed['ui'] || {}
                    {
                    'title'  => ui['title']  || 'Batched Quadric Decimator',
                    'width'  => ui['width']  || 520,
                    'height' => ui['height'] || 640
                }
                else
                    { 'title' => 'Batched Quadric Decimator', 'width' => 520, 'height' => 640 }
                end
            rescue StandardError => e
                puts "[!] Na__MeshDecimator DialogManager — config load failed: #{e.message}"
                { 'title' => 'Batched Quadric Decimator', 'width' => 520, 'height' => 640 }
            end
            private_class_method :na_load_ui_config

            # -----------------------------------------------------------------
            # REGION | Callback Registration
            # -----------------------------------------------------------------

            def self.na_setup_callbacks
                registry = {
                    'na_run_decimation'        => method(:na_handle_run_decimation),
                    'na_run_native_decimation' => method(:na_handle_run_native_decimation),
                    'na_request_group_count'   => method(:na_handle_request_group_count),
                    'na_reload_scripts'        => method(:na_handle_reload_scripts),
                    'na_jsLog'                 => proc { |msg| puts "[JS] #{msg}" }
                }
                UiBridge.na_register_callbacks(@na_dialog, registry)
            end
            private_class_method :na_setup_callbacks

            # -----------------------------------------------------------------
            # REGION | Run Decimation Callback
            # -----------------------------------------------------------------

            def self.na_handle_run_decimation(options_json)
                options = na_parse_and_validate_options(options_json)

                UiBridge.na_send_status(@na_dialog, 'info', 'Running decimation...')

                result = Orchestrator.na_run(options)

                if result[:success]
                    UiBridge.na_execute_json_function(@na_dialog, 'Na__MeshDecimator__Ui__OnComplete', result)
                else
                    UiBridge.na_execute_json_function(@na_dialog, 'Na__MeshDecimator__Ui__OnError', result)
                end
            end
            private_class_method :na_handle_run_decimation

            def self.na_handle_run_native_decimation(options_json)
                options = na_parse_and_validate_options(options_json)

                UiBridge.na_send_status(@na_dialog, 'info', 'Running advanced native decimation...')

                result = NativeOrchestrator.na_run(options)

                if result[:success]
                    UiBridge.na_execute_json_function(@na_dialog, 'Na__MeshDecimator__Ui__OnComplete', result)
                else
                    UiBridge.na_execute_json_function(@na_dialog, 'Na__MeshDecimator__Ui__OnError', result)
                end
            end
            private_class_method :na_handle_run_native_decimation

            # -----------------------------------------------------------------
            # REGION | Group Count Callback
            # -----------------------------------------------------------------

            def self.na_handle_request_group_count
                model  = Sketchup.active_model
                groups = Collector.na_collect_groups_from_selection_or_context(model)
                count  = groups.reject { |g| g.deleted? || g.locked? }.length
                UiBridge.na_execute_json_function(@na_dialog, 'Na__MeshDecimator__Ui__OnGroupCount', { :count => count })
            end
            private_class_method :na_handle_request_group_count

            # -----------------------------------------------------------------
            # REGION | Reload Scripts Callback
            # -----------------------------------------------------------------

            def self.na_handle_reload_scripts
                return unless @na_modules_root

                # Save references before reload — load re-executes the module body
                # which resets @na_dialog / @na_html_path / @na_modules_root to nil.
                saved_dialog       = @na_dialog
                saved_html_path    = @na_html_path
                saved_modules_root = @na_modules_root

                rb_count    = 0
                error_count = 0

                glob_pattern = File.join(saved_modules_root, '02__Src__AppModules', '**', '*.rb')
                files        = Dir.glob(glob_pattern).select { |f| File.file?(f) }.sort

                files.each do |file|
                    previous_verbose = $VERBOSE
                    begin
                        $VERBOSE = nil
                        load file
                        rb_count += 1
                    rescue StandardError => e
                        error_count += 1
                        puts "[!] Na__MeshDecimator reload — #{File.basename(file)}: #{e.message}"
                    ensure
                        $VERBOSE = previous_verbose
                    end
                end

                summary = if error_count > 0
                    "#{rb_count} scripts reloaded (#{error_count} errors — see Ruby Console)"
                else
                    "#{rb_count} scripts reloaded successfully"
                end

                puts "[+] Na__MeshDecimator reload: #{summary}"

                UI.refresh_inspectors if UI.respond_to?(:refresh_inspectors)

                if saved_dialog && saved_dialog.visible?
                    saved_dialog.close
                    na_show_dialog(saved_html_path, saved_modules_root)
                end
            end
            private_class_method :na_handle_reload_scripts

            # -----------------------------------------------------------------
            # REGION | Options Parsing & Validation
            # -----------------------------------------------------------------

            def self.na_parse_and_validate_options(options_json)
                raw  = JSON.parse(options_json)
                bool = Na__MeshDecimator::Na__GroupSelection::Na__Collector.method(:na_parse_boolean)

                {
                    :percentage_decimation            => [[raw['percentage_decimation'].to_f, 0.0].max, 99.0].min,
                    :maintain_border_edges            => bool.call(raw['maintain_border_edges']),
                    :preserve_material_boundary_edges => bool.call(raw['preserve_material_boundary_edges']),
                    :weld_tolerance_inches            => [raw['weld_tolerance_mm'].to_f / 25.4, 0.000001].max,
                    :process_nested_groups            => bool.call(raw['process_nested_groups']),
                    :smooth_rebuilt_edges             => bool.call(raw['smooth_rebuilt_edges']),
                    :max_seconds_per_group            => [raw['max_seconds_per_group'].to_f, 1.0].max,
                    :max_passes_per_group             => [raw['max_passes_per_group'].to_i, 1].max,
                    :max_candidate_edges_per_pass     => [raw['max_candidate_edges_per_pass'].to_i, 1000].max
                }
            rescue StandardError => e
                puts "[!] Na__MeshDecimator DialogManager — options parse failed: #{e.message}"
                raise
            end
            private_class_method :na_parse_and_validate_options

            # -----------------------------------------------------------------
            # REGION | Fallback HTML
            # -----------------------------------------------------------------

            def self.na_create_fallback_html
                <<~HTML
                <!DOCTYPE html>
                <html lang="en">
                <head>
                    <meta charset="UTF-8">
                    <title>Batched Quadric Decimator</title>
                    <style>
                        body { font-family: Arial, sans-serif; padding: 20px; background: #2a2a2a; color: #e0e0e0; }
                        .na-error { color: #ff7070; background: #3a2a2a; padding: 15px; border-radius: 4px; }
                    </style>
                </head>
                <body>
                    <h2>Batched Quadric Decimator</h2>
                    <div class="na-error">
                        <strong>Error:</strong> HTML layout file not found.<br>
                        Expected: Na__MeshDecimator__UiLayout__.html in the modules folder.
                    </div>
                    <script>
                        window.Na__MeshDecimator__Ui__OnComplete  = function(j) {};
                        window.Na__MeshDecimator__Ui__OnError      = function(j) {};
                        window.Na__MeshDecimator__Ui__OnGroupCount = function(j) {};
                    </script>
                </body>
                </html>
                HTML
            end
            private_class_method :na_create_fallback_html

        end
    end
end
