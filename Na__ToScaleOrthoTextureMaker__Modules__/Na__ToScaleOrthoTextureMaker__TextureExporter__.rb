# =============================================================================
# NA TO SCALE ORTHO TEXTURE MAKER - TEXTURE EXPORTER
# =============================================================================
#
# FILE       : Na__ToScaleOrthoTextureMaker__TextureExporter__.rb
# NAMESPACE  : Na__ToScaleOrthoTextureMaker::Na__TextureExporter
# MODULE     : Texture Exporter
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Exports the baked ortho texture from a Na__Ortho capture group
# CREATED    : 2026
#
# DESCRIPTION:
# - Owns every responsibility related to pushing a captured texture out of
#   SketchUp as a standalone image file.
# - Reads the Na__Ortho__Capture attribute dictionary stamped on the host
#   group by Na__PlaneBuilder to drive a self-describing filename that
#   embeds the true-scale mm dimensions, so downstream software (Photoshop,
#   Blender, Rhino, etc.) can be told exactly how to scale the texture.
# - Uses Sketchup::ImageRep.save_file to write the raw texture pixels
#   without any re-compression via write_image.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 19-Apr-2026 - Version 2.2.0
# - Initial release.
#
# =============================================================================

module Na__ToScaleOrthoTextureMaker
    module Na__TextureExporter

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

        NA_EXPORT_DICT_NAME   = 'Na__Ortho__Capture' unless const_defined?(:NA_EXPORT_DICT_NAME)
        NA_EXPORT_PREFIX      = 'Na__Ortho'          unless const_defined?(:NA_EXPORT_PREFIX)
        NA_EXPORT_EXTENSION   = '.png'               unless const_defined?(:NA_EXPORT_EXTENSION)

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Export Selected Capture Texture To Disk
        # ------------------------------------------------------------
        def self.Na__Export__ExportSelectedTexture(model, config_hash = {})
            source_group = self.Na__Export__ResolveSourceGroup(model)                   # Pick the capture group to export
            return source_group unless source_group.is_a?(Sketchup::Group)              # Propagate error hash

            metadata = self.Na__Export__ReadCaptureMetadata(source_group)               # Read stamped metadata
            texture  = self.Na__Export__ResolveTextureFromGroup(source_group)           # Locate the baked texture
            return texture unless texture.is_a?(Sketchup::Texture)                      # Propagate error hash

            image_rep = self.Na__Export__BuildImageRepFromTexture(texture)              # Raw pixels
            return image_rep unless image_rep.is_a?(Sketchup::ImageRep)                 # Propagate error hash

            default_filename = self.Na__Export__BuildDefaultFilename(metadata)          # mm-annotated filename
            target_path      = self.Na__Export__ResolveTargetPath(config_hash, default_filename, model)
            return { success: false, message: 'Export cancelled by user.' } unless target_path

            image_rep.save_file(target_path)                                            # Write PNG to disk

            {
                success:   true,
                file_path: target_path,
                message:   self.Na__Export__BuildSuccessMessage(target_path, metadata)
            }
        rescue => error
            { success: false, message: "Export failed: #{error.message}" }
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Source Group Resolution
# -----------------------------------------------------------------------------

        # SUB FUNCTION | Resolve The Capture Group To Export
        # ------------------------------------------------------------
        def self.Na__Export__ResolveSourceGroup(model)
            selection_group = self.Na__Export__FindCaptureGroupInSelection(model)       # Prefer user's selection
            return selection_group if selection_group

            latest_group = self.Na__Export__FindMostRecentCaptureGroup(model)           # Fallback to most recent stamp
            return latest_group if latest_group

            {
                success: false,
                message: 'No Na__Ortho capture group found. Run Capture Viewport first, then select the generated group.'
            }
        end
        # ---------------------------------------------------------------

        # SUB HELPER FUNCTION | Find Capture Group Inside Current Selection
        # ------------------------------------------------------------
        def self.Na__Export__FindCaptureGroupInSelection(model)
            return nil unless model.selection && !model.selection.empty?

            model.selection.each do |entity|
                return entity if self.Na__Export__IsCaptureGroup(entity)                # <-- First matching group wins
            end

            nil
        end
        # ---------------------------------------------------------------

        # SUB HELPER FUNCTION | Find Most Recently Stamped Capture Group In Model
        # ------------------------------------------------------------
        def self.Na__Export__FindMostRecentCaptureGroup(model)
            best_group = nil                                                            # <-- Winning group reference
            best_iso   = ''                                                             # <-- ISO timestamp to compare

            model.entities.each do |entity|
                next unless self.Na__Export__IsCaptureGroup(entity)
                iso = entity.get_attribute(NA_EXPORT_DICT_NAME, 'capture_time_iso', '')
                if iso.to_s > best_iso
                    best_iso   = iso.to_s
                    best_group = entity
                end
            end

            best_group
        end
        # ---------------------------------------------------------------

        # SUB HELPER FUNCTION | Detect Capture Group By Attribute Dictionary
        # ------------------------------------------------------------
        def self.Na__Export__IsCaptureGroup(entity)
            return false unless entity.is_a?(Sketchup::Group)
            return false unless entity.attribute_dictionaries
            !entity.attribute_dictionaries[NA_EXPORT_DICT_NAME].nil?
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Metadata And Texture Access
# -----------------------------------------------------------------------------

        # SUB FUNCTION | Read Capture Metadata From Group
        # ------------------------------------------------------------
        def self.Na__Export__ReadCaptureMetadata(group)
            {
                label:           group.get_attribute(NA_EXPORT_DICT_NAME, 'label',            'CustomView'),
                mm_width:        group.get_attribute(NA_EXPORT_DICT_NAME, 'mm_width',         0.0).to_f,
                mm_height:       group.get_attribute(NA_EXPORT_DICT_NAME, 'mm_height',        0.0).to_f,
                pixel_width:     group.get_attribute(NA_EXPORT_DICT_NAME, 'pixel_width',      0).to_i,
                pixel_height:    group.get_attribute(NA_EXPORT_DICT_NAME, 'pixel_height',     0).to_i,
                background_mode: group.get_attribute(NA_EXPORT_DICT_NAME, 'background_mode',  'transparent').to_s,
                capture_time_iso: group.get_attribute(NA_EXPORT_DICT_NAME, 'capture_time_iso', '')
            }
        end
        # ---------------------------------------------------------------

        # SUB FUNCTION | Resolve Textured Face On Capture Group
        # ------------------------------------------------------------
        def self.Na__Export__ResolveTextureFromGroup(group)
            face = self.Na__Export__FindFirstFaceOnGroup(group)
            return { success: false, message: 'Selected Na__Ortho group has no face.' } unless face

            material = face.material || face.back_material                              # Front or back-side material
            return { success: false, message: 'Selected face has no material assigned.' } unless material

            texture = material.texture                                                  # Attached texture
            return { success: false, message: 'Material has no texture attached.' } unless texture

            texture
        end
        # ---------------------------------------------------------------

        # SUB HELPER FUNCTION | Find First Face Inside Group
        # ------------------------------------------------------------
        def self.Na__Export__FindFirstFaceOnGroup(group)
            return nil unless group && group.entities
            group.entities.find { |entity| entity.is_a?(Sketchup::Face) }
        end
        # ---------------------------------------------------------------

        # SUB FUNCTION | Build ImageRep From Sketchup Texture
        # ------------------------------------------------------------
        def self.Na__Export__BuildImageRepFromTexture(texture)
            return nil unless texture
            return texture.image_rep if texture.respond_to?(:image_rep)                 # SketchUp 2018+ API path

            { success: false, message: 'This SketchUp version does not expose texture pixels via the Ruby API.' }
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Filename And Path Resolution
# -----------------------------------------------------------------------------

        # SUB FUNCTION | Build Default Filename With Embedded mm Dimensions
        # ------------------------------------------------------------
        def self.Na__Export__BuildDefaultFilename(metadata)
            label_segment  = self.Na__Export__SanitiseLabel(metadata[:label])
            mm_segment     = self.Na__Export__FormatMillimetreSegment(metadata)
            px_segment     = self.Na__Export__FormatPixelSegment(metadata)
            time_segment   = self.Na__Export__ResolveTimeSegment(metadata)

            base_name = [NA_EXPORT_PREFIX, label_segment, mm_segment, px_segment, time_segment]
                        .reject { |part| part.to_s.empty? }
                        .join('__')

            "#{base_name}#{NA_EXPORT_EXTENSION}"
        end
        # ---------------------------------------------------------------

        # SUB HELPER FUNCTION | Sanitise Label For Filename Safety
        # ------------------------------------------------------------
        def self.Na__Export__SanitiseLabel(raw_label)
            raw_label.to_s.strip.gsub(/[^A-Za-z0-9_\-]+/, '_')
        end
        # ---------------------------------------------------------------

        # SUB HELPER FUNCTION | Format mm Width x mm Height Segment
        # ------------------------------------------------------------
        def self.Na__Export__FormatMillimetreSegment(metadata)
            return '' if metadata[:mm_width] <= 0 || metadata[:mm_height] <= 0

            width_rounded  = metadata[:mm_width].round                                  # Whole mm is sufficient
            height_rounded = metadata[:mm_height].round                                 # Whole mm is sufficient
            "W#{width_rounded}mm_H#{height_rounded}mm"
        end
        # ---------------------------------------------------------------

        # SUB HELPER FUNCTION | Format Pixel Width x Pixel Height Segment
        # ------------------------------------------------------------
        def self.Na__Export__FormatPixelSegment(metadata)
            return '' if metadata[:pixel_width] <= 0 || metadata[:pixel_height] <= 0
            "#{metadata[:pixel_width]}x#{metadata[:pixel_height]}px"
        end
        # ---------------------------------------------------------------

        # SUB HELPER FUNCTION | Resolve ISO Timestamp Segment Or Fresh Timestamp
        # ------------------------------------------------------------
        def self.Na__Export__ResolveTimeSegment(metadata)
            return metadata[:capture_time_iso] unless metadata[:capture_time_iso].to_s.empty?
            Time.now.strftime('%Y%m%dT%H%M%S')
        end
        # ---------------------------------------------------------------

        # SUB FUNCTION | Resolve Save Target Path (Dialog Or Config)
        # ------------------------------------------------------------
        def self.Na__Export__ResolveTargetPath(config_hash, default_filename, model)
            preselected = config_hash['target_path'] || config_hash[:target_path]
            return preselected.to_s unless preselected.to_s.empty?

            default_dir = self.Na__Export__ResolveDefaultDirectory(model)
            UI.savepanel('Export Ortho Texture', default_dir, default_filename)
        end
        # ---------------------------------------------------------------

        # SUB HELPER FUNCTION | Resolve Default Directory For Save Dialog
        # ------------------------------------------------------------
        def self.Na__Export__ResolveDefaultDirectory(model)
            return File.dirname(model.path) if model && !model.path.to_s.empty?
            ENV['USERPROFILE'] || ENV['HOME'] || Dir.pwd
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Success Messaging
# -----------------------------------------------------------------------------

        # SUB FUNCTION | Build User-Facing Success Message
        # ------------------------------------------------------------
        def self.Na__Export__BuildSuccessMessage(target_path, metadata)
            filename   = File.basename(target_path)
            scale_text = self.Na__Export__FormatScaleText(metadata)
            "Exported #{filename}#{scale_text}"
        end
        # ---------------------------------------------------------------

        # SUB HELPER FUNCTION | Format Scale Annotation For Status Line
        # ------------------------------------------------------------
        def self.Na__Export__FormatScaleText(metadata)
            return '' if metadata[:mm_width] <= 0 || metadata[:mm_height] <= 0
            " (scale to #{metadata[:mm_width].round}mm x #{metadata[:mm_height].round}mm)."
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
