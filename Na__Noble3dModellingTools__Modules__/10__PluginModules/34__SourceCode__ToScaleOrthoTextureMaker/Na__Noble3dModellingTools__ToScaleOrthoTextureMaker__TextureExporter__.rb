# =============================================================================
# NA NOBLE3D MODELLING TOOLS - TO SCALE ORTHO TEXTURE MAKER - TEXTURE EXPORTER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__ToScaleOrthoTextureMaker__TextureExporter__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__ToScaleOrthoTextureMaker__TextureExporter
# PURPOSE    : Export a captured ortho texture to a scale-labelled PNG
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__ToScaleOrthoTextureMaker__TextureExporter

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_EXPORT_DICT_NAME = 'Na__Ortho__Capture'.freeze unless const_defined?(:NA_EXPORT_DICT_NAME)
        NA_EXPORT_PREFIX = 'Na__Ortho'.freeze unless const_defined?(:NA_EXPORT_PREFIX)
        NA_EXPORT_EXTENSION = '.png'.freeze unless const_defined?(:NA_EXPORT_EXTENSION)

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Export the Selected Capture Texture, or the Latest Capture
        # ------------------------------------------------------------
        def self.Na__ToScaleOrthoTextureMaker__TextureExporter__ExportSelected(model, config_hash = {})
            source_group = na_source_group(model)
            return source_group unless source_group.is_a?(Sketchup::Group)

            metadata = na_capture_metadata(source_group)
            texture = na_texture_from_group(source_group)
            return texture unless texture.is_a?(Sketchup::Texture)

            image_rep = na_image_rep_from_texture(texture)
            return image_rep unless image_rep.is_a?(Sketchup::ImageRep)

            default_filename = na_default_filename(metadata)
            target_path = na_target_path(config_hash, default_filename, model)
            return { success: false, message: 'Export cancelled by user.' } unless target_path

            image_rep.save_file(target_path)
            {
                success: true,
                file_path: target_path,
                message: na_success_message(target_path, metadata)
            }
        rescue StandardError => error
            { success: false, message: "Export failed: #{error.message}" }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Source Group
# -----------------------------------------------------------------------------

        def self.na_source_group(model)
            selected_group = na_capture_group_in_selection(model)
            return selected_group if selected_group

            latest_group = na_most_recent_capture_group(model)
            return latest_group if latest_group

            {
                success: false,
                message: 'No ortho capture group found. Run Capture Viewport first, then select the generated group.'
            }
        end

        def self.na_capture_group_in_selection(model)
            return nil unless model.selection && !model.selection.empty?

            model.selection.find { |entity| na_capture_group?(entity) }
        end

        def self.na_most_recent_capture_group(model)
            best_group = nil
            best_iso = ''
            model.entities.each do |entity|
                next unless na_capture_group?(entity)

                iso = entity.get_attribute(NA_EXPORT_DICT_NAME, 'capture_time_iso', '').to_s
                next unless iso > best_iso

                best_iso = iso
                best_group = entity
            end
            best_group
        end

        def self.na_capture_group?(entity)
            return false unless entity.is_a?(Sketchup::Group)
            return false unless entity.attribute_dictionaries

            !entity.attribute_dictionaries[NA_EXPORT_DICT_NAME].nil?
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Metadata and Texture
# -----------------------------------------------------------------------------

        def self.na_capture_metadata(group)
            {
                label: group.get_attribute(NA_EXPORT_DICT_NAME, 'label', 'CustomView'),
                mm_width: group.get_attribute(NA_EXPORT_DICT_NAME, 'mm_width', 0.0).to_f,
                mm_height: group.get_attribute(NA_EXPORT_DICT_NAME, 'mm_height', 0.0).to_f,
                pixel_width: group.get_attribute(NA_EXPORT_DICT_NAME, 'pixel_width', 0).to_i,
                pixel_height: group.get_attribute(NA_EXPORT_DICT_NAME, 'pixel_height', 0).to_i,
                background_mode: group.get_attribute(NA_EXPORT_DICT_NAME, 'background_mode', 'transparent').to_s,
                capture_time_iso: group.get_attribute(NA_EXPORT_DICT_NAME, 'capture_time_iso', '')
            }
        end

        def self.na_texture_from_group(group)
            face = na_first_face(group)
            return { success: false, message: 'Selected ortho group has no face.' } unless face

            material = face.material || face.back_material
            return { success: false, message: 'Selected face has no material assigned.' } unless material

            texture = material.texture
            return { success: false, message: 'Material has no texture attached.' } unless texture

            texture
        end

        def self.na_first_face(group)
            return nil unless group && group.entities

            group.entities.find { |entity| entity.is_a?(Sketchup::Face) }
        end

        def self.na_image_rep_from_texture(texture)
            return nil unless texture
            return texture.image_rep if texture.respond_to?(:image_rep)

            { success: false, message: 'This SketchUp version does not expose texture pixels via the Ruby API.' }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Filename and Path
# -----------------------------------------------------------------------------

        def self.na_default_filename(metadata)
            parts = [
                NA_EXPORT_PREFIX,
                na_sanitise_label(metadata[:label]),
                na_millimetre_segment(metadata),
                na_pixel_segment(metadata),
                na_time_segment(metadata)
            ]
            "#{parts.reject { |part| part.to_s.empty? }.join('__')}#{NA_EXPORT_EXTENSION}"
        end

        def self.na_sanitise_label(raw_label)
            raw_label.to_s.strip.gsub(/[^A-Za-z0-9_\-]+/, '_')
        end

        def self.na_millimetre_segment(metadata)
            return '' if metadata[:mm_width] <= 0 || metadata[:mm_height] <= 0

            "W#{metadata[:mm_width].round}mm_H#{metadata[:mm_height].round}mm"
        end

        def self.na_pixel_segment(metadata)
            return '' if metadata[:pixel_width] <= 0 || metadata[:pixel_height] <= 0

            "#{metadata[:pixel_width]}x#{metadata[:pixel_height]}px"
        end

        def self.na_time_segment(metadata)
            return metadata[:capture_time_iso] unless metadata[:capture_time_iso].to_s.empty?

            Time.now.strftime('%Y%m%dT%H%M%S')
        end

        def self.na_target_path(config_hash, default_filename, model)
            preselected = config_hash['target_path'] || config_hash[:target_path]
            return preselected.to_s unless preselected.to_s.empty?

            UI.savepanel('Export Ortho Texture', na_default_directory(model), default_filename)
        end

        def self.na_default_directory(model)
            return File.dirname(model.path) if model && !model.path.to_s.empty?

            ENV['USERPROFILE'] || ENV['HOME'] || Dir.pwd
        end

        def self.na_success_message(target_path, metadata)
            filename = File.basename(target_path)
            return "Exported #{filename}" if metadata[:mm_width] <= 0 || metadata[:mm_height] <= 0

            "Exported #{filename} (scale to #{metadata[:mm_width].round}mm x #{metadata[:mm_height].round}mm)."
        end

# endregion -------------------------------------------------------------------

    end # module Na__ToScaleOrthoTextureMaker__TextureExporter
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
