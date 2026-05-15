# =============================================================================
# NA COMPONENT EDITOR TOOLS - THUMBNAIL TOOLS
# =============================================================================
#
# FILE       : Na__ComponentEditorTools__ThumbnailTools__Main__.rb
# NAMESPACE  : Na__ComponentEditorTools::Na__ThumbnailTools
# PURPOSE    : Thumbnail camera refresh + viewport framebuffer PNG utilities
# CREATED    : 2026
#
# =============================================================================

require 'fileutils'

module Na__ComponentEditorTools
    module Na__ThumbnailTools

# -----------------------------------------------------------------------------
# REGION | Public Operations
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__RefreshThumbnailFromCurrentView
            model = Sketchup.active_model
            selected_instance = Na__SelectionInspector.Na__ComponentEditorTools__SelectedInstance
            selected_definition = selected_instance&.definition

            raise 'Select a component instance or group first.' unless selected_instance && selected_definition
            if selected_definition.respond_to?(:live_component?) && selected_definition.live_component?
                raise 'Live Components should not be modified through this utility.'
            end

            active_view = model.active_view

            model.start_operation('NA Refresh Component Thumbnail', true)
            selected_definition.thumbnail_camera = active_view.camera
            selected_definition.refresh_thumbnail
            model.commit_operation

            exported_thumbnail_path = self.Na__ComponentEditorTools__TempFilePath('component_thumbnail', 'png')
            selected_definition.save_thumbnail(exported_thumbnail_path)
            visible_view_path = self.Na__ComponentEditorTools__CaptureVisibleViewportImage(model, selected_definition)

            extension_key = Na__ComponentEditorTools::NA_EXTENSION_NAME
            selected_definition.set_attribute(extension_key, 'last_exported_thumbnail_path', exported_thumbnail_path)
            selected_definition.set_attribute(extension_key, 'last_visible_view_render_png', visible_view_path)
            selected_definition.set_attribute(extension_key, 'last_thumbnail_refresh_time', Time.now.to_s)
            selected_definition.set_attribute(
                extension_key,
                'last_thumbnail_refresh_note',
                'SketchUp browser thumbnail refreshed via thumbnail_camera + refresh_thumbnail. Visible viewport render is saved separately because the Ruby API cannot inject arbitrary PNG pixels into the internal component thumbnail.'
            )

            self.Na__ComponentEditorTools__Result(
                true,
                "Visible viewport render saved to #{visible_view_path}. SketchUp internal thumbnail was refreshed via the supported thumbnail camera API.",
                visible_view_path
            )
        rescue => error
            model.abort_operation if model
            self.Na__ComponentEditorTools__Result(false, "#{error.class}: #{error.message}")
        end

        def self.Na__ComponentEditorTools__CaptureViewportPng
            model = Sketchup.active_model
            selected_definition = Na__SelectionInspector.Na__ComponentEditorTools__SelectedDefinition
            raise 'Select a component instance or group first.' unless selected_definition

            image_path = self.Na__ComponentEditorTools__CaptureVisibleViewportImage(model, selected_definition, 'viewport_framebuffer')

            extension_key = Na__ComponentEditorTools::NA_EXTENSION_NAME
            selected_definition.set_attribute(extension_key, 'last_viewport_framebuffer_png', image_path)
            selected_definition.set_attribute(extension_key, 'last_visible_view_render_png', image_path)
            selected_definition.set_attribute(extension_key, 'last_viewport_framebuffer_time', Time.now.to_s)
            selected_definition.set_attribute(
                extension_key,
                'last_viewport_framebuffer_note',
                'Full visible viewport framebuffer capture. This includes what the active SketchUp view draws, such as dimensions, styles, and watermark overlays.'
            )

            self.Na__ComponentEditorTools__Result(true, "Visible viewport PNG exported to #{image_path}.", image_path)
        rescue => error
            self.Na__ComponentEditorTools__Result(false, "#{error.class}: #{error.message}")
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Helper Functions
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__TempFilePath(prefix_name, extension_name)
            temp_folder = File.join(Sketchup.temp_dir, Na__ComponentEditorTools::NA_EXTENSION_NAME)
            FileUtils.mkdir_p(temp_folder)

            safe_time = Time.now.strftime('%Y%m%d_%H%M%S_%L')
            File.join(temp_folder, "#{prefix_name}_#{safe_time}.#{extension_name}")
        end

        def self.Na__ComponentEditorTools__CurrentThumbnailPreviewData(definition)
            return {} unless definition

            preview_path = self.Na__ComponentEditorTools__PreferredPreviewPath(definition)
            preview_source = 'visible_viewport'

            unless preview_path && File.exist?(preview_path)
                preview_path = self.Na__ComponentEditorTools__CurrentThumbnailPreviewPath(definition)
                definition.save_thumbnail(preview_path)
                preview_source = 'component_thumbnail'
            end

            {
                current_thumbnail_preview_path: preview_path,
                current_thumbnail_preview_uri: self.Na__ComponentEditorTools__FilePathToFileUri(preview_path),
                current_thumbnail_preview_source: preview_source
            }
        rescue => error
            {
                current_thumbnail_preview_path: '',
                current_thumbnail_preview_uri: '',
                current_thumbnail_preview_source: '',
                current_thumbnail_preview_error: "#{error.class}: #{error.message}"
            }
        end

        def self.Na__ComponentEditorTools__CaptureVisibleViewportImage(model, definition, prefix_name = 'visible_viewport_render')
            image_path = self.Na__ComponentEditorTools__TempFilePath(prefix_name, 'png')
            saved_selection = model.selection.to_a

            model.selection.clear
            model.active_view.refresh

            operation_ok = model.active_view.write_image(
                filename: image_path,
                source: :framebuffer,
                compression: 0.9
            )
            raise 'Visible viewport framebuffer image export failed.' unless operation_ok

            definition.set_attribute(Na__ComponentEditorTools::NA_EXTENSION_NAME, 'last_visible_view_render_png', image_path)
            image_path
        ensure
            if model && saved_selection
                model.selection.clear
                saved_selection.each { |entity| model.selection.add(entity) if entity && entity.valid? }
                model.active_view.refresh
            end
        end

        def self.Na__ComponentEditorTools__PreferredPreviewPath(definition)
            extension_key = Na__ComponentEditorTools::NA_EXTENSION_NAME
            rendered_view_path = definition.get_attribute(extension_key, 'last_visible_view_render_png', '').to_s
            return rendered_view_path if !rendered_view_path.empty? && File.exist?(rendered_view_path)

            viewport_path = definition.get_attribute(extension_key, 'last_viewport_framebuffer_png', '').to_s
            return viewport_path if !viewport_path.empty? && File.exist?(viewport_path)

            ''
        end

        def self.Na__ComponentEditorTools__CurrentThumbnailPreviewPath(definition)
            temp_folder = File.join(Sketchup.temp_dir, Na__ComponentEditorTools::NA_EXTENSION_NAME)
            FileUtils.mkdir_p(temp_folder)

            token_value = if definition.respond_to?(:persistent_id)
                              definition.persistent_id.to_s
                          elsif definition.respond_to?(:guid)
                              definition.guid.to_s
                          else
                              'definition'
                          end
            safe_token = token_value.gsub(/[^A-Za-z0-9_-]/, '_')
            File.join(temp_folder, "component_thumbnail_current_#{safe_token}.png")
        end

        def self.Na__ComponentEditorTools__FilePathToFileUri(file_path)
            return '' if file_path.to_s.empty?

            normalized_path = file_path.to_s.tr('\\', '/').sub(%r{^/+}, '')
            'file:///' + normalized_path.gsub(' ', '%20')
        end

        def self.Na__ComponentEditorTools__Result(success_flag, message_text, visible_view_render_path = '')
            result_hash = {
                success: !!success_flag,
                message: message_text.to_s
            }
            result_hash[:visible_view_render_path] = visible_view_render_path.to_s unless visible_view_render_path.to_s.empty?
            result_hash
        end

# endregion -------------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
