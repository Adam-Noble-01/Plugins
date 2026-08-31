# =============================================================================
# NA NOBLE3D MODELLING TOOLS - PAINT DEEP NESTED FACES - RUN ENTRYPOINT
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__PaintDeepNestedFaces__Run__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__PaintDeepNestedFaces
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Public execution entrypoints for the Paint Deep Nested Faces tool
# CREATED    : 2026
#
# WORKFLOW:
# 1. Pick a material in the SketchUp Materials tray. The dialog previews its
#    colour, opacity and name, and states which back face rule will apply.
# 2. Select the groups or components to paint. The dialog reports live how many
#    faces the current nesting mode would reach.
# 3. Deep Nesting on  - every face at every level below the selection.
#    Deep Nesting off - only the faces sitting one level inside each selected
#                       container, plus any directly selected faces.
# 4. Paint. Edges are never touched. Opaque materials paint the front face and
#    strip the back face; transparent materials paint both sides.
#
# STRIP MODE:
# Picking the Default swatch in the Materials tray strips instead of painting.
# SketchUp represents the default material as nil, so the same traversal and the
# same painter clear both sides of every face reached. That makes stripping deep
# nested faces a first class mode rather than a separate tool.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__PaintDeepNestedFaces

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_PAINT_OPERATION     = 'Paint Deep Nested Faces'.freeze
        NA_STRIP_OPERATION     = 'Strip Deep Nested Faces'.freeze
        NA_BAD_MATERIAL_MSG    = 'The active material could not be read. Click a swatch in the SketchUp ' \
                                 'Materials tray, then run Paint Deep Nested Faces again.'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Entry Points
# -----------------------------------------------------------------------------

        # FUNCTION | Open the Paint Deep Nested Faces Dialog
        # ------------------------------------------------------------
        def self.Na__PaintDeepNestedFaces__Run
            model = Sketchup.active_model
            return na_result(false, 'No active SketchUp model.') unless model

            Na__PaintDeepNestedFaces__DialogManager.Na__PaintDeepNestedFaces__ShowDialog
            na_result(true, 'Paint Deep Nested Faces opened.')
        rescue => error
            na_result(false, "Paint Deep Nested Faces failed to open: #{error.class}: #{error.message}")
        end
        # ------------------------------------------------------------

        # FUNCTION | Paint the Selection Using the Saved Toggle State
        # ------------------------------------------------------------
        # One-click entrypoint for a keyboard shortcut. It reuses whatever the
        # dialog was last set to, so the hotkey and the dialog never disagree.
        # ------------------------------------------------------------
        def self.Na__PaintDeepNestedFaces__RunWithSavedSettings
            deep_nesting   = na_saved_flag(
                Na__PaintDeepNestedFaces__DialogManager::NA_PREF_DEEP_NESTING, true
            )
            isolate_shared = na_saved_flag(
                Na__PaintDeepNestedFaces__DialogManager::NA_PREF_ISOLATE_SHARED, false
            )

            Na__PaintDeepNestedFaces__PaintCurrentSelection(deep_nesting, isolate_shared)
        end
        # ------------------------------------------------------------

        # FUNCTION | Paint Every Reachable Face in the Current Selection
        # ------------------------------------------------------------
        # A nil current material is the Default swatch, which is a valid choice
        # meaning "strip these faces", so it is not rejected here.
        #
        # @param deep_nesting   [Boolean] True to walk every nested level
        # @param isolate_shared [Boolean] True to make shared containers unique
        #                                 before painting inside them
        # @return [Hash] { success:, message: }
        # ------------------------------------------------------------
        def self.Na__PaintDeepNestedFaces__PaintCurrentSelection(deep_nesting = true, isolate_shared = false)
            model = Sketchup.active_model
            return na_result(false, 'No active SketchUp model.') unless model

            material = model.materials.current
            return na_result(false, NA_BAD_MATERIAL_MSG) unless material.nil? || na_material_ready?(material)

            selection = model.selection
            return na_result(false, 'Select the groups, components or faces to paint, then run again.') if selection.empty?

            preflight = Na__PaintDeepNestedFaces__FaceCollector
                        .Na__PaintDeepNestedFaces__FaceCollector__Collect(selection, deep_nesting, false)

            return na_result(false, na_no_faces_message(deep_nesting)) if preflight[:faces].empty?

            na_run_paint_operation(model, selection, material, deep_nesting, isolate_shared, preflight)
        rescue => error
            na_result(false, "Paint Deep Nested Faces failed: #{error.class}: #{error.message}")
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Paint Operation
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Run the Whole Paint Inside One Undoable Operation
        # ------------------------------------------------------------
        def self.na_run_paint_operation(model, selection, material, deep_nesting, isolate_shared, preflight)
            operation_started = false

            model.start_operation(material.nil? ? NA_STRIP_OPERATION : NA_PAINT_OPERATION, true)
            operation_started = true

            resolved = na_resolve_paintable_material(model, material)

            collected = if isolate_shared
                            Na__PaintDeepNestedFaces__FaceCollector
                                .Na__PaintDeepNestedFaces__FaceCollector__Collect(selection, deep_nesting, true)
                        else
                            preflight
                        end

            paint_stats = Na__PaintDeepNestedFaces__Painter
                          .Na__PaintDeepNestedFaces__Painter__PaintFaces(collected[:faces], resolved[:material])

            model.commit_operation
            operation_started = false

            summary_text = na_summary_message(
                resolved, collected[:stats], paint_stats, deep_nesting, isolate_shared
            )
            Sketchup.set_status_text(summary_text)
            na_result(true, summary_text)
        rescue => error
            model.abort_operation if operation_started
            na_result(false, "Paint Deep Nested Faces failed: #{error.class}: #{error.message}")
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Library Material Resolution
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Return a Material That Is Safe to Apply
        # ------------------------------------------------------------
        # Materials#current happily hands back a swatch clicked in a material
        # library, which does not belong to the model. Applying one of those to
        # an entity crashes SketchUp, so it is copied into the model first -
        # which is what SketchUp itself does when you paint with a library
        # swatch. Must run inside the operation, because it edits the model.
        #
        # @return [Hash] { material:, copied: }
        # ------------------------------------------------------------
        def self.na_resolve_paintable_material(model, material)
            return { material: nil, copied: false } if material.nil?

            in_model = Na__PaintDeepNestedFaces__MaterialProbe
                       .Na__PaintDeepNestedFaces__MaterialProbe__IsInModel(model, material)
            return { material: material, copied: false } if in_model

            existing = model.materials[material.name]
            return { material: existing, copied: false } if existing

            { material: na_copy_material_into_model(model, material), copied: true }
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Copy a Library Material Into the Model
        # ------------------------------------------------------------
        # Colour, opacity and texture are copied, and the texture is resized back
        # to the library size so the copy is scaled like the original rather than
        # reverting to the raw image dimensions.
        # ------------------------------------------------------------
        def self.na_copy_material_into_model(model, material)
            copied_material = model.materials.add(material.name)

            copied_material.color = material.color if material.color
            copied_material.alpha = material.alpha

            na_copy_texture(copied_material, material.texture)
            copied_material
        rescue => error
            raise "#{material.display_name} is a library material and could not be copied into the model " \
                  "(#{error.message}). Paint one face with it using the Paint Bucket first, then run again."
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Carry a Texture and Its Size Onto the Copied Material
        # ------------------------------------------------------------
        def self.na_copy_texture(copied_material, source_texture)
            return if source_texture.nil?

            texture_path = source_texture.filename.to_s
            return if texture_path.empty?

            copied_material.texture = texture_path
            return unless copied_material.texture

            copied_material.texture.size = [source_texture.width, source_texture.height]
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Messaging
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Build the Result Sentence for a Completed Paint
        # ------------------------------------------------------------
        def self.na_summary_message(resolved, walk_stats, paint_stats, deep_nesting, isolate_shared)
            parts = [na_headline_text(resolved[:material], paint_stats)]

            parts << na_reach_text(walk_stats, deep_nesting)
            parts << na_unchanged_text(paint_stats)             if paint_stats[:unchanged_face_count] > 0
            parts << na_copied_text(resolved[:material])        if resolved[:copied]
            parts << na_locked_text(walk_stats)                 if walk_stats[:locked_container_count] > 0
            parts << na_shared_text(walk_stats, isolate_shared) if walk_stats[:shared_definition_count] > 0

            parts.compact.join(' ')
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Describe What Was Painted and Under Which Rule
        # ------------------------------------------------------------
        def self.na_headline_text(material, paint_stats)
            face_count = paint_stats[:changed_face_count]
            face_word  = face_count == 1 ? 'face' : 'faces'

            if paint_stats[:is_default]
                return "Stripped #{face_count} #{face_word} back to the default material " \
                       '(front and back both cleared).'
            end

            rule_text = if paint_stats[:back_face_rule] == 'paint_both'
                            'transparent material, front and back painted'
                        else
                            'opaque material, front painted and back stripped to default'
                        end

            "Painted #{face_count} #{face_word} with #{material.display_name} (#{rule_text})."
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Describe the Faces That Were Already Correct
        # ------------------------------------------------------------
        def self.na_unchanged_text(paint_stats)
            unchanged_count = paint_stats[:unchanged_face_count]
            return "#{unchanged_count} already had no material." if paint_stats[:is_default]

            "#{unchanged_count} already matched."
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Note That a Library Material Was Added to the Model
        # ------------------------------------------------------------
        def self.na_copied_text(material)
            return nil if material.nil?

            "#{material.display_name} was copied from a library into this model first."
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Describe How Far the Walk Reached
        # ------------------------------------------------------------
        def self.na_reach_text(walk_stats, deep_nesting)
            container_count = walk_stats[:container_count]
            return 'Painted directly selected faces only.' if container_count.zero?

            mode_text = deep_nesting ? "#{walk_stats[:deepest_level]} levels deep" : 'one level deep'
            "Walked #{container_count} #{container_count == 1 ? 'container' : 'containers'}, #{mode_text}."
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Describe Locked Containers That Were Left Alone
        # ------------------------------------------------------------
        def self.na_locked_text(walk_stats)
            locked_count = walk_stats[:locked_container_count]
            "#{locked_count} locked #{locked_count == 1 ? 'container was' : 'containers were'} skipped."
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Describe the Shared Definition Impact
        # ------------------------------------------------------------
        def self.na_shared_text(walk_stats, isolate_shared)
            shared_count = walk_stats[:shared_definition_count]
            other_count  = walk_stats[:other_instance_count]

            if isolate_shared
                "#{shared_count} shared #{shared_count == 1 ? 'definition was' : 'definitions were'} " \
                'made unique first, so no other placements changed.'
            else
                "#{shared_count} shared #{shared_count == 1 ? 'definition was' : 'definitions were'} painted, " \
                "which also changed #{other_count} other #{other_count == 1 ? 'placement' : 'placements'}."
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Explain Why the Walk Found Nothing to Paint
        # ------------------------------------------------------------
        def self.na_no_faces_message(deep_nesting)
            return 'No faces found in the selection. Only edges or empty containers were selected.' if deep_nesting

            'No faces found one level inside the selection. Turn Deep Nesting on to reach faces further down.'
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Check the Materials Tray Is Holding a Usable Material
        # ------------------------------------------------------------
        def self.na_material_ready?(material)
            Na__PaintDeepNestedFaces__MaterialProbe
                .Na__PaintDeepNestedFaces__MaterialProbe__IsUsable(material)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Read One Persisted Toggle Without Opening the Dialog
        # ------------------------------------------------------------
        def self.na_saved_flag(preference_name, default_value)
            stored_value = Sketchup.read_default(
                Na__PaintDeepNestedFaces__DialogManager::NA_DIALOG_PREFERENCES_KEY,
                preference_name,
                default_value
            )

            return stored_value if stored_value == true || stored_value == false

            %w[true 1].include?(stored_value.to_s.strip.downcase)
        rescue
            default_value
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build Standard Result Hash
        # ------------------------------------------------------------
        def self.na_result(success_flag, message_text)
            {
                success: !!success_flag,
                message: message_text.to_s
            }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__PaintDeepNestedFaces
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
