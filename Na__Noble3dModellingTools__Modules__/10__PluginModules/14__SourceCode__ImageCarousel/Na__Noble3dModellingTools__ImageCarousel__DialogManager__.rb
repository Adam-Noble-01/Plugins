# =============================================================================
# NA NOBLE3D MODELLING TOOLS - IMAGE CAROUSEL - DIALOG MANAGER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__ImageCarousel__DialogManager__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__ImageCarousel__DialogManager
# PURPOSE    : Manage the dedicated HtmlDialog for the Image Viewer
# CREATED    : 2026
#
# DESIGN NOTES:
# - A new dialog is created fresh on each invocation; @na_dialog is nilled on
#   close so callbacks are always registered on the live instance.
# - No @callbacks_set guard is used — callbacks are registered unconditionally
#   on every new dialog creation to avoid the stale-guard bug where a re-opened
#   dialog would have no attached callbacks.
#
# =============================================================================

require 'json'

module Na__Noble3dModellingTools
    module Na__ImageCarousel__DialogManager

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_DIALOG_TITLE          = 'Na Noble3d Tools : Image Viewer'.freeze
        NA_DIALOG_PREFERENCES_KEY = 'Na__Noble3dModellingTools__ImageCarousel'.freeze
        NA_DIALOG_WIDTH          = 1200
        NA_DIALOG_HEIGHT         = 800
        NA_DIALOG_MIN_WIDTH      = 900
        NA_DIALOG_MIN_HEIGHT     = 600

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dialog Lifecycle
# -----------------------------------------------------------------------------

        def self.Na__ImageCarousel__DialogManager__ShowDialog
            if @na_dialog && @na_dialog.visible?
                @na_dialog.close
                @na_dialog = nil
            end

            @na_dialog = na_create_dialog
            @na_dialog.set_html(na_render_html)
            na_register_callbacks(@na_dialog)
            @na_dialog.set_on_closed { @na_dialog = nil }
            @na_dialog.show
            @na_dialog.bring_to_front
            @na_dialog
        end

        def self.Na__ImageCarousel__DialogManager__ResetDialog
            return unless @na_dialog

            @na_dialog.close if @na_dialog.visible?
            @na_dialog = nil
            true
        rescue => error
            puts "[Na__ImageCarousel] reset dialog warning: #{error.class}: #{error.message}"
            @na_dialog = nil
            false
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dialog Construction
# -----------------------------------------------------------------------------

        def self.na_create_dialog
            UI::HtmlDialog.new(
                dialog_title:    NA_DIALOG_TITLE,
                preferences_key: NA_DIALOG_PREFERENCES_KEY,
                style:           UI::HtmlDialog::STYLE_DIALOG,
                width:           NA_DIALOG_WIDTH,
                height:          NA_DIALOG_HEIGHT,
                min_width:       NA_DIALOG_MIN_WIDTH,
                min_height:      NA_DIALOG_MIN_HEIGHT,
                resizable:       true,
                scrollable:      false
            )
        end

        def self.na_render_html
            layout_path      = File.join(__dir__, 'Na__Noble3dModellingTools__ImageCarousel__UiLayout__.html')
            style_path       = File.join(__dir__, 'Na__Noble3dModellingTools__ImageCarousel__Styles__.css')
            script_path      = File.join(__dir__, 'Na__Noble3dModellingTools__ImageCarousel__UiBridge__.js')
            measurement_path = File.join(__dir__, 'Na__Noble3dModellingTools__ImageCarousel__Measurement__.js')

            template = File.read(layout_path)
            template
                .gsub('{{STYLESHEET_CONTENT}}', File.read(style_path))
                .gsub('{{UI_BRIDGE_SCRIPT}}',   File.read(script_path))
                .gsub('{{MEASUREMENT_SCRIPT}}', File.read(measurement_path))
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Callback Registration
# -----------------------------------------------------------------------------

        def self.na_register_callbacks(dialog)
            dialog.add_action_callback('choose_folder') do |_ctx, _param|
                begin
                    puts '[Na__ImageCarousel] choose_folder callback reached'
                    na_handle_folder_selection(dialog)
                rescue => error
                    puts "[Na__ImageCarousel] choose_folder error: #{error.class}: #{error.message}"
                    UI.messagebox("Image Viewer: folder selection error\n#{error.message}")
                end
            end

            dialog.add_action_callback('open_in_os') do |_ctx, path|
                begin
                    na_open_in_os(path)
                rescue => error
                    puts "[Na__ImageCarousel] open_in_os error: #{error.class}: #{error.message}"
                end
            end

            dialog.add_action_callback('copy_path') do |_ctx, path|
                begin
                    na_copy_path_to_clipboard(path)
                rescue => error
                    puts "[Na__ImageCarousel] copy_path error: #{error.class}: #{error.message}"
                end
            end
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Callback Handlers
# -----------------------------------------------------------------------------

        def self.na_handle_folder_selection(dialog)
            default_dir = Sketchup.read_default(NA_DIALOG_PREFERENCES_KEY, 'last_dir', Dir.home)
            folder = UI.select_directory(title: 'Select image folder', directory: default_dir)

            unless folder
                puts '[Na__ImageCarousel] folder selection cancelled'
                dialog.execute_script('window.SKP_onFolderChosen(null);')
                return
            end

            Sketchup.write_default(NA_DIALOG_PREFERENCES_KEY, 'last_dir', folder)
            paths = Na__ImageCarousel__FolderScanner.Na__ImageCarousel__FolderScanner__CollectImages(folder)
            puts "[Na__ImageCarousel] selected folder: #{folder}"
            puts "[Na__ImageCarousel] image paths found: #{paths.length}"
            na_push_folder_images_to_dialog(dialog, paths)
        end

        def self.na_push_folder_images_to_dialog(dialog, paths)
            image_json = paths.to_json
            script = <<~JS
                (function() {
                    var imagePaths = #{image_json};
                    var statusEl = document.getElementById('naImageViewer_meta');
                    if (statusEl) {
                        statusEl.textContent = 'Loading ' + imagePaths.length + ' image(s)...';
                    }
                    setTimeout(function() {
                        if (window.SKP_onFolderChosen) {
                            window.SKP_onFolderChosen(imagePaths);
                        } else if (window.Na__ImageViewer__OnFolderChosen) {
                            window.Na__ImageViewer__OnFolderChosen(imagePaths);
                        } else if (statusEl) {
                            statusEl.textContent = 'Image viewer JavaScript callback is unavailable.';
                        }
                    }, 0);
                })();
            JS
            dialog.execute_script(script)
        end

        def self.na_open_in_os(path)
            return unless path && !path.empty?

            native_path = Sketchup.platform == :platform_win ? path.tr('/', '\\') : path

            if File.exist?(native_path)
                if Sketchup.platform == :platform_win
                    system('explorer', '/select,', native_path)
                else
                    system('open', '-R', native_path)
                end
            else
                UI.messagebox("File not found:\n#{native_path}")
            end
        end

        def self.na_copy_path_to_clipboard(path)
            return unless path && !path.empty?

            native_path = Sketchup.platform == :platform_win ? path.tr('/', '\\') : path
            begin
                if Sketchup.platform == :platform_win
                    IO.popen('clip', 'w') { |clipboard| clipboard.write(native_path) }
                elsif system('which pbcopy > /dev/null 2>&1')
                    IO.popen('pbcopy', 'w') { |clipboard| clipboard.write(native_path) }
                else
                    raise 'No supported clipboard command found for this platform.'
                end
                puts "[Na__ImageCarousel] copied path to clipboard: #{native_path}"
            rescue => error
                UI.messagebox("Copy to clipboard failed: #{error.message}")
            end
        end

# endregion -------------------------------------------------------------------

    end # module Na__ImageCarousel__DialogManager
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
