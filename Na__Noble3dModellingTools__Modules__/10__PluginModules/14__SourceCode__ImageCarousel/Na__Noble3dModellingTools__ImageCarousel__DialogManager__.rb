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
# - The last chosen folder is remembered per model (ModelPersistence). When
#   the page reports ready, a remembered folder is scanned and shown; a
#   missing one gets a quiet note on the canvas. A model with nothing
#   remembered opens empty and waits for Select Folder.
# - Scripts and styles are inlined with the block form of gsub, so a
#   backslash in a script (\1, \\, \') is inserted literally rather than
#   read as a replacement escape.
# - request_photo_info answers the Perspective Angle tool with the photo's
#   lens data (PhotoInfo). Only files with an image extension are read.
# - The Count tool (CountTool.js) is inlined last: it reads the Perspective
#   Angle tool's directions and the solver's counting maths.
# - The Markup tool (MarkupTool.js) is inlined straight after the UI bridge, so
#   its marks are drawn under the other tools' lines. Its marks reach the model
#   through markup_save: checked and held at once (MarkupPersistence), written
#   to the model dictionary by a timer a moment after the last change, and again
#   when the dialog closes. The model's marks for a folder go to the dialog with
#   that folder's image list.
# - Dimensions and the reference scale (Measurement.js) go the same way, in
#   their own dictionary (DimensionPersistence): dimensions_save holds them,
#   the same timer and the same close write them, and the folder's list comes
#   with the model's dimensions for its photos.
# - The Count tool's counts and the Perspective Angle tool's work go the same
#   way through ToolStatePersistence (tool_state_save), one dictionary per
#   tool, sent by the viewer's Core a moment after a change.
# - The top bar's nesting (ToolbarMenu.js) is inlined before the tools, so its
#   Esc listener runs first. Toolbar icons are inlined from
#   UiIcons__MenuIcons__ImageViewer through {{ICON:name}} placeholders.
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
        NA_DIALOG_MIN_WIDTH      = 640
        NA_DIALOG_MIN_HEIGHT     = 600
        NA_MARKUP_FLUSH_SECONDS  = 1.0   # quiet time after a mark before it is written to the model

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
            @na_dialog.set_on_closed do
                na_flush_markup(nil)
                @na_dialog = nil
            end
            @na_dialog.show
            @na_dialog.bring_to_front
            @na_dialog
        end

        def self.Na__ImageCarousel__DialogManager__ResetDialog
            return unless @na_dialog

            na_flush_markup(nil)
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
            markup_path      = File.join(__dir__, 'Na__Noble3dModellingTools__ImageCarousel__MarkupTool__.js')
            measurement_path = File.join(__dir__, 'Na__Noble3dModellingTools__ImageCarousel__Measurement__.js')
            solver_path      = File.join(__dir__, 'Na__Noble3dModellingTools__ImageCarousel__PerspectiveSolver__.js')
            perspective_path = File.join(__dir__, 'Na__Noble3dModellingTools__ImageCarousel__PerspectiveAngle__.js')
            count_path       = File.join(__dir__, 'Na__Noble3dModellingTools__ImageCarousel__CountTool__.js')
            protractor_path  = File.join(__dir__, 'Na__Noble3dModellingTools__ImageCarousel__ProtractorTool__.js')
            toolbar_path     = File.join(__dir__, 'Na__Noble3dModellingTools__ImageCarousel__ToolbarMenu__.js')

            template = na_inline_icons(File.read(layout_path))
            template
                .gsub('{{STYLESHEET_CONTENT}}')        { File.read(style_path) }
                .gsub('{{UI_BRIDGE_SCRIPT}}')          { File.read(script_path) }
                .gsub('{{TOOLBAR_MENU_SCRIPT}}')       { File.read(toolbar_path) }
                .gsub('{{MARKUP_SCRIPT}}')             { File.read(markup_path) }
                .gsub('{{MEASUREMENT_SCRIPT}}')        { File.read(measurement_path) }
                .gsub('{{PROTRACTOR_SCRIPT}}')         { File.read(protractor_path) }
                .gsub('{{PERSPECTIVE_SOLVER_SCRIPT}}') { File.read(solver_path) }
                .gsub('{{PERSPECTIVE_ANGLE_SCRIPT}}')  { File.read(perspective_path) }
                .gsub('{{COUNT_TOOL_SCRIPT}}')         { File.read(count_path) }
        end

        # {{ICON:name}} becomes that icon's SVG, inline so CSS can colour it. A
        # missing file costs the picture only: the button still has its name.
        def self.na_inline_icons(html)
            html.gsub(/\{\{ICON:(\w+)\}\}/) do
                icon_path = File.join(__dir__, 'UiIcons__MenuIcons__ImageViewer', "#{Regexp.last_match(1)}.svg")
                File.exist?(icon_path) ? File.read(icon_path) : ''
            end
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Callback Registration
# -----------------------------------------------------------------------------

        def self.na_register_callbacks(dialog)
            dialog.add_action_callback('dialog_ready') do |_ctx, _param|
                begin
                    na_restore_model_folder(dialog)
                rescue => error
                    puts "[Na__ImageCarousel] restore folder error: #{error.class}: #{error.message}"
                end
            end

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

            dialog.add_action_callback('request_photo_info') do |_ctx, path|
                begin
                    na_send_photo_info(dialog, path)
                rescue => error
                    puts "[Na__ImageCarousel] request_photo_info error: #{error.class}: #{error.message}"
                end
            end

            dialog.add_action_callback('read_image_data') do |_ctx, path|
                begin
                    na_send_image_data(dialog, path)
                rescue => error
                    puts "[Na__ImageCarousel] read_image_data error: #{error.class}: #{error.message}"
                    na_execute_safely(dialog, 'Na__ImageViewer__OnImageData', { 'path' => path.to_s, 'error' => error.message })
                end
            end

            dialog.add_action_callback('save_dimensioned_image') do |_ctx, payload|
                result = begin
                    na_save_dimensioned_image(payload)
                rescue => error
                    puts "[Na__ImageCarousel] save_dimensioned_image error: #{error.class}: #{error.message}"
                    { 'ok' => false, 'error' => error.message }
                end
                na_execute_safely(dialog, 'Na__ImageViewer__OnImageSaved', result)
            end

            dialog.add_action_callback('dimensions_save') do |_ctx, payload|
                begin
                    na_queue_dimensions(dialog, payload)
                rescue => error
                    puts "[Na__ImageCarousel] dimensions_save error: #{error.class}: #{error.message}"
                end
            end

            dialog.add_action_callback('tool_state_save') do |_ctx, payload|
                begin
                    na_queue_tool_state(dialog, payload)
                rescue => error
                    puts "[Na__ImageCarousel] tool_state_save error: #{error.class}: #{error.message}"
                end
            end

            dialog.add_action_callback('markup_save') do |_ctx, payload|
                begin
                    na_queue_markup(dialog, payload)
                rescue => error
                    puts "[Na__ImageCarousel] markup_save error: #{error.class}: #{error.message}"
                end
            end
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Callback Handlers
# -----------------------------------------------------------------------------

        def self.na_restore_model_folder(dialog)
            folder = Na__ImageCarousel__ModelPersistence.Na__ImageCarousel__ModelPersistence__LoadFolder(Sketchup.active_model)
            return unless folder

            unless File.directory?(folder)
                puts "[Na__ImageCarousel] remembered folder not found: #{folder}"
                note_text = "This model's last image folder was not found: #{na_native_path(folder)}"
                dialog.execute_script("window.Na__ImageViewer__ShowRestoreNote && window.Na__ImageViewer__ShowRestoreNote(#{note_text.to_json});")
                return
            end

            paths = Na__ImageCarousel__FolderScanner.Na__ImageCarousel__FolderScanner__CollectImages(folder)
            puts "[Na__ImageCarousel] restored model folder: #{folder} (#{paths.length} image(s))"
            na_push_folder_images_to_dialog(dialog, paths)
        end

        def self.na_handle_folder_selection(dialog)
            model_dir   = Na__ImageCarousel__ModelPersistence.Na__ImageCarousel__ModelPersistence__LoadFolder(Sketchup.active_model)
            default_dir = model_dir && File.directory?(model_dir) ? model_dir : Sketchup.read_default(NA_DIALOG_PREFERENCES_KEY, 'last_dir', Dir.home)
            folder = UI.select_directory(title: 'Select image folder', directory: default_dir)

            unless folder
                puts '[Na__ImageCarousel] folder selection cancelled'
                return
            end

            Sketchup.write_default(NA_DIALOG_PREFERENCES_KEY, 'last_dir', folder)
            Na__ImageCarousel__ModelPersistence.Na__ImageCarousel__ModelPersistence__SaveFolder(Sketchup.active_model, folder)
            paths = Na__ImageCarousel__FolderScanner.Na__ImageCarousel__FolderScanner__CollectImages(folder)
            puts "[Na__ImageCarousel] selected folder: #{folder}"
            puts "[Na__ImageCarousel] image paths found: #{paths.length}"
            na_push_folder_images_to_dialog(dialog, paths)
        end

        # The folder's image list goes with the model's marks for those photos,
        # ahead of the list, so a photo's marks are there when it is shown.
        def self.na_push_folder_images_to_dialog(dialog, paths)
            image_json  = paths.to_json
            markup_json = na_markup_for_paths(paths).to_json
            dims_json   = na_dimensions_for_paths(paths).to_json
            tools_json  = na_tool_state_for_paths(paths).to_json
            script = <<~JS
                (function() {
                    var imagePaths = #{image_json};
                    var statusEl = document.getElementById('naImageViewer_meta');
                    if (window.Na__ImageViewer__OnMarkupLoaded) {
                        window.Na__ImageViewer__OnMarkupLoaded(#{markup_json});
                    }
                    if (window.Na__ImageViewer__OnDimensionsLoaded) {
                        window.Na__ImageViewer__OnDimensionsLoaded(#{dims_json});
                    }
                    if (window.Na__ImageViewer__OnToolStateLoaded) {
                        window.Na__ImageViewer__OnToolStateLoaded(#{tools_json});
                    }
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

        # Lens data for the Perspective Angle tool. Only image files are read,
        # and only their header bytes.
        def self.na_send_photo_info(dialog, path)
            file_path = path.to_s
            info = if Na__ImageCarousel__FolderScanner.na_supported_extension?(file_path)
                Na__ImageCarousel__PhotoInfo.Na__ImageCarousel__PhotoInfo__Read(file_path)
            else
                { 'path' => file_path, 'none' => true }
            end
            dialog.execute_script("window.Na__ImageViewer__OnPhotoInfo && window.Na__ImageViewer__OnPhotoInfo(#{info.to_json});")
        end

        # The model's marks for the photos of the folder just chosen or restored.
        def self.na_markup_for_paths(paths)
            model = Sketchup.active_model
            Na__ImageCarousel__MarkupPersistence.Na__ImageCarousel__MarkupPersistence__LoadForPaths(model, paths, na_markup_root(model))
        end

        # The model's dimensions for the photos of the folder just chosen or restored.
        # Never in the way of the folder itself: no dimensions rather than no photos.
        def self.na_dimensions_for_paths(paths)
            return {} unless defined?(Na__ImageCarousel__DimensionPersistence)

            model = Sketchup.active_model
            Na__ImageCarousel__DimensionPersistence.Na__ImageCarousel__DimensionPersistence__LoadForPaths(model, paths, na_markup_root(model))
        rescue => error
            puts "[Na__ImageCarousel] read dimensions error: #{error.class}: #{error.message}"
            {}
        end

        # The model's counts and angle work for the photos of a folder. Never in
        # the way of the folder itself.
        def self.na_tool_state_for_paths(paths)
            return {} unless defined?(Na__ImageCarousel__ToolStatePersistence)

            model = Sketchup.active_model
            Na__ImageCarousel__ToolStatePersistence.Na__ImageCarousel__ToolStatePersistence__LoadForPaths(model, paths, na_markup_root(model))
        rescue => error
            puts "[Na__ImageCarousel] read tool state error: #{error.class}: #{error.message}"
            {}
        end

        # A photo's state for one tool: checked and held now, written with the marks.
        def self.na_queue_tool_state(dialog, payload)
            root   = na_markup_root(Sketchup.active_model)
            result = Na__ImageCarousel__ToolStatePersistence.Na__ImageCarousel__ToolStatePersistence__Queue(payload, root)
            if result['ok']
                na_schedule_markup_flush(dialog)
            else
                na_execute_safely(dialog, 'Na__ImageViewer__ToolStateOnSaved', result)
            end
        end

        # A photo's dimensions from the dialog: checked and held now, written
        # with the marks once the dialog has been quiet for a moment.
        def self.na_queue_dimensions(dialog, payload)
            root   = na_markup_root(Sketchup.active_model)
            result = Na__ImageCarousel__DimensionPersistence.Na__ImageCarousel__DimensionPersistence__Queue(payload, root)
            if result['ok']
                na_schedule_markup_flush(dialog)
            else
                na_execute_safely(dialog, 'Na__ImageViewer__DimensionsOnSaved', result)
            end
        end

        # The model's image folder, which a photo's marks are named under.
        def self.na_markup_root(model)
            Na__ImageCarousel__ModelPersistence.Na__ImageCarousel__ModelPersistence__LoadFolder(model)
        end

        # A photo's marks from the dialog: checked and held now, written to the
        # model once the dialog has been quiet for a moment. A mark that cannot
        # be kept is reported to the dialog at once.
        def self.na_queue_markup(dialog, payload)
            root   = na_markup_root(Sketchup.active_model)
            result = Na__ImageCarousel__MarkupPersistence.Na__ImageCarousel__MarkupPersistence__Queue(payload, root)
            if result['ok']
                na_schedule_markup_flush(dialog)
            else
                na_notify_markup_saved(dialog, result)
            end
        end

        def self.na_schedule_markup_flush(dialog)
            na_stop_markup_timer
            @na_markup_timer = UI.start_timer(NA_MARKUP_FLUSH_SECONDS, false) do
                @na_markup_timer = nil
                begin
                    na_flush_markup(dialog)
                rescue => error
                    puts "[Na__ImageCarousel] markup flush error: #{error.class}: #{error.message}"
                end
            end
        end

        def self.na_stop_markup_timer
            return unless @na_markup_timer

            UI.stop_timer(@na_markup_timer)
            @na_markup_timer = nil
        end

        # Write the marks held to the model now, and tell the dialog (when it is
        # still there) how it went.
        # Dimensions held are written here too, in their own undo step.
        def self.na_flush_markup(dialog)
            na_stop_markup_timer
            na_flush_dimensions(dialog)
            na_flush_tool_state(dialog)

            persistence = Na__ImageCarousel__MarkupPersistence
            return unless persistence.Na__ImageCarousel__MarkupPersistence__HasPending

            result = persistence.Na__ImageCarousel__MarkupPersistence__Flush(Sketchup.active_model)
            na_notify_markup_saved(dialog, result)
        end

        # Counts and angle work held: one undo step per tool. Never in the way of the marks.
        def self.na_flush_tool_state(dialog)
            return unless defined?(Na__ImageCarousel__ToolStatePersistence)

            store = Na__ImageCarousel__ToolStatePersistence
            return unless store.Na__ImageCarousel__ToolStatePersistence__HasPending

            result = store.Na__ImageCarousel__ToolStatePersistence__Flush(Sketchup.active_model)
            na_execute_safely(dialog, 'Na__ImageViewer__ToolStateOnSaved', result)
        rescue => error
            puts "[Na__ImageCarousel] tool state flush error: #{error.class}: #{error.message}"
        end

        # A problem here must never stop the marks being written.
        def self.na_flush_dimensions(dialog)
            return unless defined?(Na__ImageCarousel__DimensionPersistence)

            dims = Na__ImageCarousel__DimensionPersistence
            return unless dims.Na__ImageCarousel__DimensionPersistence__HasPending

            result = dims.Na__ImageCarousel__DimensionPersistence__Flush(Sketchup.active_model)
            na_execute_safely(dialog, 'Na__ImageViewer__DimensionsOnSaved', result)
        rescue => error
            puts "[Na__ImageCarousel] dimensions flush error: #{error.class}: #{error.message}"
        end

        def self.na_notify_markup_saved(dialog, result)
            return unless dialog

            dialog.execute_script("window.Na__ImageViewer__MarkupOnSaved && window.Na__ImageViewer__MarkupOnSaved(#{result.to_json});")
        rescue => error
            puts "[Na__ImageCarousel] markup notice skipped: #{error.class}: #{error.message}"
        end

        # ---- Save Dimensioned Image -------------------------------------------
        # The dialog draws the photo with its dimensions and marks at full size
        # and sends it as a data URL; it is written beside the original as
        # <name>__DimensionsAdded__<ext>. Only the photo's own folder is written
        # to, only that one derived name, and an earlier one is replaced.

        NA_DIMENSIONED_SUFFIX = '__DimensionsAdded__'.freeze unless const_defined?(:NA_DIMENSIONED_SUFFIX)
        NA_DIMENSIONED_TYPES  = { '.png' => 'png', '.jpg' => 'jpeg', '.jpeg' => 'jpeg', '.webp' => 'webp' }.freeze unless const_defined?(:NA_DIMENSIONED_TYPES)

        def self.na_dimensioned_path(source_path, ext)
            dir  = File.dirname(source_path)
            base = File.basename(source_path, File.extname(source_path))
            File.join(dir, "#{base}#{NA_DIMENSIONED_SUFFIX}#{ext}")
        end

        def self.na_save_dimensioned_image(payload)
            data   = JSON.parse(payload.to_s)
            source = data['path'].to_s.tr('\\', '/')
            ext    = data['ext'].to_s
            return { 'ok' => false, 'error' => 'no photo given' } if source.empty?
            return { 'ok' => false, 'error' => "photo not found: #{na_native_path(source)}" } unless File.file?(source)
            return { 'ok' => false, 'error' => 'not an image file' } unless Na__ImageCarousel__FolderScanner.na_supported_extension?(source)

            # The original's extension (and its case) unless the dialog had to write PNG.
            ext = File.extname(source) if ext.casecmp?(File.extname(source))
            type = NA_DIMENSIONED_TYPES[ext.downcase]
            return { 'ok' => false, 'error' => "cannot save as #{ext}" } unless type

            match = %r{\Adata:image/(png|jpeg|webp);base64,(.+)\z}m.match(data['data'].to_s)
            return { 'ok' => false, 'error' => 'the picture did not arrive' } unless match
            return { 'ok' => false, 'error' => "picture is #{match[1]}, name says #{ext}" } unless match[1] == type

            target   = na_dimensioned_path(source, ext)
            replaced = File.exist?(target)
            bytes    = match[2].unpack1('m')
            File.binwrite(target, bytes)
            puts "[Na__ImageCarousel] saved dimensioned image: #{na_native_path(target)} (#{bytes.bytesize} bytes#{replaced ? ', replaced' : ''})"
            { 'ok' => true, 'path' => target, 'name' => File.basename(target), 'replaced' => replaced, 'bytes' => bytes.bytesize }
        end

        # The photo's bytes for the dialog, when drawing the file itself would
        # taint its canvas. Only image files are read.
        def self.na_send_image_data(dialog, path)
            file_path = path.to_s
            info = if !File.file?(file_path)
                { 'path' => file_path, 'error' => 'photo not found' }
            elsif !Na__ImageCarousel__FolderScanner.na_supported_extension?(file_path)
                { 'path' => file_path, 'error' => 'not an image file' }
            else
                mime = { '.png' => 'image/png', '.gif' => 'image/gif', '.bmp' => 'image/bmp', '.webp' => 'image/webp' }
                       .fetch(File.extname(file_path).downcase, 'image/jpeg')
                { 'path' => file_path, 'data' => "data:#{mime};base64,#{[File.binread(file_path)].pack('m0')}" }
            end
            na_execute_safely(dialog, 'Na__ImageViewer__OnImageData', info)
        end

        def self.na_execute_safely(dialog, function_name, payload)
            return unless dialog

            dialog.execute_script("window.#{function_name} && window.#{function_name}(#{payload.to_json});")
        rescue => error
            puts "[Na__ImageCarousel] #{function_name} notice skipped: #{error.class}: #{error.message}"
        end

        def self.na_native_path(path)
            Sketchup.platform == :platform_win ? path.to_s.tr('/', '\\') : path.to_s
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
