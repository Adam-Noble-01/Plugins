# =============================================================================
# NA NOBLE3D MODELLING TOOLS - TEXTURED PLANE TO IMAGE - RUN ENTRYPOINT
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__TexturedPlaneToImage__Run__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__TexturedPlaneToImage
# PURPOSE    : Convert selected textured rectangles into in-place SketchUp Images
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__TexturedPlaneToImage

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_OPERATION_NAME = 'Textured Plane to Image'.freeze unless const_defined?(:NA_OPERATION_NAME)

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Entry Point
# -----------------------------------------------------------------------------

        # FUNCTION | Convert Each Selected Textured Rectangle into an Image
        # ------------------------------------------------------------
        def self.Na__TexturedPlaneToImage__Run
            model = Sketchup.active_model
            return na_result(false, 'No active model available.') unless model

            faces = na_collect_targets(model)
            return na_result(false, 'Select one or more textured rectangular faces, or groups that contain them.') if faces.empty?

            operation_started = false
            converted_count = 0
            failure_messages = []

            model.start_operation(NA_OPERATION_NAME, true)
            operation_started = true
            faces.each do |target|
                result = na_convert_target(model, target)
                if result[:success]
                    converted_count += 1
                else
                    failure_messages << result[:message]
                end
            end

            if converted_count.positive?
                model.commit_operation
            else
                model.abort_operation
            end
            operation_started = false
            na_result(converted_count.positive?, na_summary(converted_count, faces.length, failure_messages))
        rescue StandardError => error
            model.abort_operation if model && operation_started
            na_result(false, "#{NA_OPERATION_NAME} failed: #{error.class}: #{error.message}")
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Selection and Conversion
# -----------------------------------------------------------------------------

        def self.na_collect_targets(model)
            targets = []
            model.selection.each do |entity|
                if entity.is_a?(Sketchup::Face)
                    targets << { face: entity, chain: [] }
                elsif na_container?(entity)
                    na_walk_container(na_unique_container(entity), [], targets)
                end
            end
            targets
        end

        def self.na_walk_container(container, chain, targets)
            return if container.respond_to?(:locked?) && container.locked?

            container = na_unique_container(container)
            current_chain = chain[0...-1] + [container]
            container.definition.entities.each do |child|
                if child.is_a?(Sketchup::Face)
                    targets << { face: child, chain: current_chain.dup }
                elsif na_container?(child)
                    na_walk_container(child, current_chain + [child], targets)
                end
            end
        end

        def self.na_container?(entity)
            entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
        end

        def self.na_unique_container(entity)
            return entity unless entity.respond_to?(:definition) && entity.definition.respond_to?(:count_instances)
            return entity if entity.definition.count_instances <= 1

            entity.make_unique
        end

        def self.na_convert_target(model, target)
            Na__TexturedPlaneToImage__PlacementContext.Na__TexturedPlaneToImage__PlacementContext__InContext(model, target[:chain]) do |entered|
                result = na_convert_face(target[:face])
                unless entered
                    Na__TexturedPlaneToImage__PlacementContext.Na__TexturedPlaneToImage__PlacementContext__Invalidate(target[:chain])
                end
                result
            end
        end

        def self.na_orient_to_textured_side(description)
            corners = description[:corners]
            width_vector = corners[1] - corners[0]
            height_vector = corners[3] - corners[0]
            desired_normal = description[:front] ? description[:face].normal : description[:face].normal.reverse
            return if width_vector.cross(height_vector).dot(desired_normal) >= 0

            description[:corners] = [corners[1], corners[0], corners[3], corners[2]]
            uvs = description[:uvs]
            description[:uvs] = [uvs[1], uvs[0], uvs[3], uvs[2]]
        end

        def self.na_convert_face(face)
            description = Na__TexturedPlaneToImage__FaceProbe.Na__TexturedPlaneToImage__FaceProbe__Describe(face)
            return description unless description[:success]

            na_orient_to_textured_side(description)
            bitmap = Na__TexturedPlaneToImage__BitmapWriter.Na__TexturedPlaneToImage__BitmapWriter__Write(
                description[:texture],
                description[:uvs]
            )
            return bitmap unless bitmap[:success]

            Na__TexturedPlaneToImage__ImagePlacer.Na__TexturedPlaneToImage__ImagePlacer__ReplaceFace(description, bitmap[:path])
        rescue StandardError => error
            { success: false, message: error.message }
        end

        def self.na_summary(converted_count, face_count, failure_messages)
            parts = ["#{converted_count} face(s) converted to images"]
            skipped_count = face_count - converted_count
            parts << "#{skipped_count} skipped" if skipped_count.positive?
            unique_failures = failure_messages.uniq
            parts << unique_failures.first if unique_failures.length == 1
            parts << "#{unique_failures.length} different reasons" if unique_failures.length > 1
            "#{NA_OPERATION_NAME}: #{parts.join('; ')}."
        end

        def self.na_result(success_flag, message_text)
            { success: !!success_flag, message: message_text.to_s }
        end

# endregion -------------------------------------------------------------------

    end # module Na__TexturedPlaneToImage
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
