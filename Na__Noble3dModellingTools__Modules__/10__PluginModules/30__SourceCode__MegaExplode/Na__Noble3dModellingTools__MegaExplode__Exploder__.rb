# =============================================================================
# NA NOBLE3D MODELLING TOOLS - MEGA EXPLODE - EXPLODER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__MegaExplode__Exploder__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__MegaExplode__Exploder
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Recursively explode every group and component in the selection,
#              then optionally untag, strip materials, and purge unused
# CREATED    : 2026
#
# EXPLODE RULES:
# - Breadth-first. Each explode returns the child entities; nested groups and
#   components are queued and exploded until only loose drawing elements remain.
# - Sibling selections and mixed nesting (Group -> Component -> Group, etc.)
#   all use the same queue. Directly selected faces and edges are left in place.
# - Locked containers are skipped unless unlock_locked is on.
# - Exploding an instance does not change other placements of that definition.
#
# CLEANUP:
# - move_to_untagged assigns every remaining entity to Layer0, shown as
#   Untagged in SketchUp 2020+.
# - strip_materials sets Face#material, Face#back_material and Edge#material
#   to nil (SketchUp's Default swatch). Images are left alone.
# - delete_faces erases remaining faces and SketchUp surfaces (faces joined by
#   soft or smooth edges), leaving visible bounding edges as linework.
# - delete_hidden erases remaining hidden faces, edges, construction and
#   leftover containers.
# - purge_unused then removes unused component definitions, materials and tags.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__MegaExplode__Exploder

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_OPERATION_NAME          = 'Mega Explode'.freeze
        NA_MAX_EXPLODE_STEPS       = 100_000
        NA_MAX_SURFACE_FACES       = 250_000
        NA_EXPLODE_STATUS_EVERY    = 250
        NA_RESELECT_BATCH_SIZE     = 500
        NA_DEFAULT_OPTIONS         = {
            move_to_untagged: false,
            strip_materials:   false,
            delete_faces:     false,
            delete_hidden:    false,
            unlock_locked:    false,
            purge_unused:     false
        }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Explode API
# -----------------------------------------------------------------------------

        # FUNCTION | Recursively Explode the Active Selection
        # ------------------------------------------------------------
        # @param options [Hash]
        # @return [Hash] { success:, message: }
        # ------------------------------------------------------------
        def self.Na__MegaExplode__Exploder__ExplodeSelection(options = {})
            model = Sketchup.active_model
            return na_result(false, 'No active SketchUp model.') unless model

            selection = model.selection
            return na_result(false, 'Select one or more groups or components, then run Mega Explode again.') if selection.empty?

            resolved_options = na_resolve_options(options)
            seeds = selection.to_a
            return na_result(false, 'Select one or more groups or components, then run Mega Explode again.') unless na_any_container?(seeds)

            na_run_explode_operation(model, selection, seeds, resolved_options)
        rescue => error
            na_result(false, "Mega Explode failed: #{error.class}: #{error.message}")
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Explode Operation
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Run Explode, Cleanup and Reselect in One Undo Step
        # ------------------------------------------------------------
        def self.na_run_explode_operation(model, selection, seeds, options)
            operation_started = false
            stats = na_empty_explode_stats

            model.start_operation(NA_OPERATION_NAME, true)
            operation_started = true

            remaining_entities = na_explode_queue(seeds, options, stats)
            na_apply_cleanup(remaining_entities, options, model, stats)
            na_delete_faces_and_surfaces(remaining_entities, stats) if options[:delete_faces]
            na_delete_hidden_geometry(remaining_entities, stats) if options[:delete_hidden]
            na_purge_unused(model, stats) if options[:purge_unused]

            remaining_entities.select! { |entity| na_valid_entity?(entity) }
            na_reselect(selection, remaining_entities)

            model.commit_operation
            operation_started = false

            message_text = na_summary_message(stats, options)
            Sketchup.set_status_text(message_text)
            na_result(true, message_text)
        rescue => error
            model.abort_operation if operation_started
            na_result(false, "Mega Explode failed: #{error.class}: #{error.message}")
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Explode Every Nested Container From the Seed List
        # ------------------------------------------------------------
        def self.na_explode_queue(seeds, options, stats)
            remaining_entities = []
            remaining_ids = {}
            queue = []
            queued_ids = {}

            seeds.each do |entity|
                next unless na_valid_entity?(entity)

                if na_container?(entity)
                    na_enqueue_container(entity, queue, queued_ids)
                else
                    na_remember_remaining(entity, remaining_entities, remaining_ids)
                end
            end

            explode_steps = 0
            until queue.empty?
                explode_steps += 1
                if explode_steps > NA_MAX_EXPLODE_STEPS
                    stats[:failed_count] += queue.length
                    break
                end

                na_report_explode_progress(explode_steps)

                entity = queue.shift
                next unless na_valid_entity?(entity)

                exploded_children = na_explode_one_container(entity, options, stats)
                if exploded_children.nil?
                    na_remember_remaining(entity, remaining_entities, remaining_ids) if na_valid_entity?(entity)
                    next
                end

                exploded_children.each do |child|
                    next unless na_valid_entity?(child)

                    if na_container?(child)
                        na_enqueue_container(child, queue, queued_ids)
                    else
                        na_remember_remaining(child, remaining_entities, remaining_ids)
                    end
                end
            end

            remaining_entities
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Queue a Container Once
        # ------------------------------------------------------------
        def self.na_enqueue_container(entity, queue, queued_ids)
            entity_id = entity.entityID
            return if queued_ids[entity_id]

            queued_ids[entity_id] = true
            queue << entity
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Keep One Remaining Drawing Element
        # ------------------------------------------------------------
        def self.na_remember_remaining(entity, remaining_entities, remaining_ids)
            entity_id = entity.entityID
            return if remaining_ids[entity_id]

            remaining_ids[entity_id] = true
            remaining_entities << entity
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Explode One Group or Component Instance
        # ------------------------------------------------------------
        # @return [Array, nil] Child entities, or nil when the container was
        #                      skipped or explode failed
        # ------------------------------------------------------------
        def self.na_explode_one_container(entity, options, stats)
            if entity.locked?
                unless options[:unlock_locked]
                    stats[:skipped_locked_count] += 1
                    return nil
                end

                entity.locked = false
                stats[:unlocked_count] += 1
            end

            exploded = entity.explode
            unless exploded.is_a?(Array)
                stats[:failed_count] += 1
                return nil
            end

            stats[:exploded_container_count] += 1
            exploded
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Replace the Selection With the Surviving Entities
        # ------------------------------------------------------------
        def self.na_reselect(selection, remaining_entities)
            valid_entities = remaining_entities.select { |entity| na_valid_entity?(entity) }
            selection.clear
            return if valid_entities.empty?

            valid_entities.each_slice(NA_RESELECT_BATCH_SIZE) do |batch|
                selection.add(*batch)
            end
        rescue
            nil
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Show Progress So a Long Explode Does Not Look Frozen
        # ------------------------------------------------------------
        def self.na_report_explode_progress(explode_steps)
            return unless (explode_steps % NA_EXPLODE_STATUS_EVERY).zero?

            Sketchup.set_status_text("Mega Explode: exploded #{explode_steps} containers...")
        rescue
            nil
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Cleanup
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Untag and / or Strip Materials on Remaining Entities
        # ------------------------------------------------------------
        # Applied only to exploded results and leftover containers themselves.
        # Nested contents of skipped locked containers are left alone so a
        # shared definition is not rewritten from the outside.
        # ------------------------------------------------------------
        def self.na_apply_cleanup(entities, options, model, stats)
            return unless options[:move_to_untagged] || options[:strip_materials]

            untagged_layer = model.layers[0]
            entities.each do |entity|
                next unless na_valid_entity?(entity)

                na_untag_entity(entity, untagged_layer, stats) if options[:move_to_untagged]
            end

            na_strip_all_materials(entities, stats) if options[:strip_materials]
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Move One Entity Onto Layer0 / Untagged
        # ------------------------------------------------------------
        def self.na_untag_entity(entity, untagged_layer, stats)
            return unless untagged_layer
            return unless entity.respond_to?(:layer) && entity.layer
            return if entity.layer == untagged_layer

            entity.layer = untagged_layer
            stats[:untagged_count] += 1
        rescue
            nil
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Strip Front, Back and Edge Materials Back to Default
        # ------------------------------------------------------------
        # Group#explode often omits merged bounding edges from its return
        # array, so faces are expanded to their edges before stripping.
        # Front and back are cleared in separate rescues so one failure cannot
        # leave the other side painted.
        # ------------------------------------------------------------
        def self.na_strip_all_materials(entities, stats)
            faces, edges, others = na_collect_material_strip_targets(entities)

            faces.each { |face| na_strip_face_materials(face, stats) }
            edges.each { |edge| na_clear_drawing_material(edge, stats) }
            others.each { |entity| na_clear_drawing_material(entity, stats) }
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Collect Faces, Bounding Edges and Other Paintable Entities
        # ------------------------------------------------------------
        def self.na_collect_material_strip_targets(entities)
            faces = []
            edges = []
            others = []
            seen_face_ids = {}
            seen_edge_ids = {}

            entities.each do |entity|
                next unless na_valid_entity?(entity)

                case entity
                when Sketchup::Face
                    na_remember_strip_target(entity, faces, seen_face_ids)
                    na_collect_face_edges(entity, edges, seen_edge_ids)
                when Sketchup::Edge
                    na_remember_strip_target(entity, edges, seen_edge_ids)
                when Sketchup::Image
                    next
                else
                    others << entity if entity.respond_to?(:material)
                end
            end

            [faces, edges, others]
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Add a Face's Bounding Edges to the Strip Set
        # ------------------------------------------------------------
        def self.na_collect_face_edges(face, edges, seen_edge_ids)
            return unless face.respond_to?(:edges)

            face.edges.each do |edge|
                na_remember_strip_target(edge, edges, seen_edge_ids)
            end
        rescue
            nil
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Remember One Entity Once, by Entity ID
        # ------------------------------------------------------------
        def self.na_remember_strip_target(entity, collection, seen_ids)
            return unless na_valid_entity?(entity)

            entity_id = entity.entityID
            return if seen_ids[entity_id]

            seen_ids[entity_id] = true
            collection << entity
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Clear Front and Back Materials on One Face
        # ------------------------------------------------------------
        def self.na_strip_face_materials(face, stats)
            return unless na_valid_entity?(face)

            na_clear_drawing_material(face, stats)
            na_clear_back_material(face, stats)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Clear Drawingelement#material (Front Face or Edge)
        # ------------------------------------------------------------
        def self.na_clear_drawing_material(entity, stats)
            return unless na_valid_entity?(entity)
            return unless entity.respond_to?(:material)
            return unless entity.material

            entity.material = nil
            stats[:stripped_material_count] += 1
        rescue
            nil
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Clear Face#back_material
        # ------------------------------------------------------------
        def self.na_clear_back_material(face, stats)
            return unless na_valid_entity?(face)
            return unless face.respond_to?(:back_material)
            return unless face.back_material

            face.back_material = nil
            stats[:stripped_material_count] += 1
        rescue
            nil
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Erase Remaining Faces and SketchUp Surfaces
        # ------------------------------------------------------------
        # SketchUp has no Surface class. Soft or smooth edges join faces into a
        # surface in the UI. Those neighbour faces are collected too, because
        # explode's return array often omits them.
        # ------------------------------------------------------------
        def self.na_delete_faces_and_surfaces(entities, stats)
            faces = na_collect_faces_and_surfaces(entities)
            na_erase_entity_list(faces, stats, :deleted_face_count)
        rescue => error
            puts "[Na__MegaExplode] Delete faces warning: #{error.class}: #{error.message}"
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Collect Seed Faces and Expand Across Surface Joins
        # ------------------------------------------------------------
        def self.na_collect_faces_and_surfaces(entities)
            seed_faces = []
            seen_ids = {}

            entities.each do |entity|
                next unless na_valid_entity?(entity)

                if entity.is_a?(Sketchup::Face)
                    na_remember_strip_target(entity, seed_faces, seen_ids)
                elsif entity.is_a?(Sketchup::Edge)
                    na_collect_edge_faces(entity, seed_faces, seen_ids)
                end
            end

            na_expand_surface_faces(seed_faces)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Add Faces Bound by One Edge
        # ------------------------------------------------------------
        def self.na_collect_edge_faces(edge, faces, seen_ids)
            return unless edge.respond_to?(:faces)

            edge.faces.each do |face|
                na_remember_strip_target(face, faces, seen_ids)
            end
        rescue
            nil
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Walk Faces Joined Into a SketchUp Surface
        # ------------------------------------------------------------
        # Only soft/smooth edges form a SketchUp surface. Hidden-only edges
        # were incorrectly treated as joins and could flood-walk the whole
        # model after explode merged into the parent entities.
        # ------------------------------------------------------------
        def self.na_expand_surface_faces(seed_faces)
            result = []
            seen_ids = {}
            queue = []

            seed_faces.each do |face|
                na_enqueue_unseen_face(face, queue, seen_ids)
            end

            until queue.empty?
                break if result.length >= NA_MAX_SURFACE_FACES

                face = queue.shift
                next unless na_valid_entity?(face) && face.is_a?(Sketchup::Face)

                result << face
                na_enqueue_surface_neighbours(face, queue, seen_ids)
            end

            result
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Queue Faces Sharing a Soft or Smooth Edge
        # ------------------------------------------------------------
        def self.na_enqueue_surface_neighbours(face, queue, seen_ids)
            return unless face.respond_to?(:edges)

            face.edges.each do |edge|
                next unless na_surface_joining_edge?(edge)
                next unless edge.respond_to?(:faces)

                edge.faces.each do |neighbour|
                    na_enqueue_unseen_face(neighbour, queue, seen_ids)
                end
            end
        rescue
            nil
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Queue a Face Once, Before It Is Walked
        # ------------------------------------------------------------
        def self.na_enqueue_unseen_face(face, queue, seen_ids)
            return unless na_valid_entity?(face) && face.is_a?(Sketchup::Face)

            entity_id = face.entityID
            return if seen_ids[entity_id]

            seen_ids[entity_id] = true
            queue << face
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | True When an Edge Joins Faces Into a Surface
        # ------------------------------------------------------------
        def self.na_surface_joining_edge?(edge)
            return false unless na_valid_entity?(edge)
            return true if edge.respond_to?(:soft?) && edge.soft?
            return true if edge.respond_to?(:smooth?) && edge.smooth?

            false
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Erase Remaining Hidden Geometry
        # ------------------------------------------------------------
        def self.na_delete_hidden_geometry(entities, stats)
            hidden_entities = na_collect_hidden_geometry(entities)
            na_erase_entity_list(hidden_entities, stats, :deleted_hidden_count)
        rescue => error
            puts "[Na__MegaExplode] Delete hidden geometry warning: #{error.class}: #{error.message}"
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Collect Hidden Faces, Edges and Other Drawing Elements
        # ------------------------------------------------------------
        # Only the exploded remainder and each remaining face's bounding
        # edges. Face#all_connected was called once per remaining entity and
        # could walk the entire parent mesh after explode.
        # ------------------------------------------------------------
        def self.na_collect_hidden_geometry(entities)
            hidden = []
            seen_ids = {}

            entities.each do |entity|
                next unless na_valid_entity?(entity)

                na_remember_hidden_entity(entity, hidden, seen_ids)
                next unless entity.is_a?(Sketchup::Face)
                next unless entity.respond_to?(:edges)

                entity.edges.each do |edge|
                    na_remember_hidden_entity(edge, hidden, seen_ids)
                end
            end

            hidden
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Remember One Hidden Entity
        # ------------------------------------------------------------
        def self.na_remember_hidden_entity(entity, hidden, seen_ids)
            return unless na_valid_entity?(entity)
            return unless entity.respond_to?(:hidden?) && entity.hidden?

            na_remember_strip_target(entity, hidden, seen_ids)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Bulk Erase Entities Grouped by Their Owning Entities
        # ------------------------------------------------------------
        def self.na_erase_entity_list(entities, stats, count_key)
            grouped = Hash.new { |hash, key| hash[key] = [] }

            entities.each do |entity|
                next unless na_valid_entity?(entity)

                owning = na_owning_entities(entity)
                next unless owning

                grouped[owning] << entity
            end

            grouped.each do |ents_collection, list|
                valid_list = list.select { |entity| na_valid_entity?(entity) }
                next if valid_list.empty?

                stats[count_key] += valid_list.length
                ents_collection.erase_entities(valid_list)
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Owning Entities Collection for a Drawing Element
        # ------------------------------------------------------------
        def self.na_owning_entities(entity)
            return nil unless na_valid_entity?(entity)
            return nil unless entity.respond_to?(:parent)

            parent = entity.parent
            return parent.entities if parent.respond_to?(:entities)

            nil
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Purge Unused Definitions, Materials and Tags
        # ------------------------------------------------------------
        def self.na_purge_unused(model, stats)
            stats[:purged_definitions] = na_purge_count { model.definitions.purge_unused }
            stats[:purged_materials]    = na_purge_count { model.materials.purge_unused }
            stats[:purged_tags]         = na_purge_count { model.layers.purge_unused }

            return unless model.layers.respond_to?(:purge_unused_folders)

            stats[:purged_tag_folders] = na_purge_count { model.layers.purge_unused_folders }
        rescue => error
            puts "[Na__MegaExplode] Purge unused warning: #{error.class}: #{error.message}"
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Run a Purge Call and Coerce the Return to an Integer
        # ------------------------------------------------------------
        def self.na_purge_count
            result = yield
            result.to_i
        rescue
            0
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Messaging
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Build the Result Sentence
        # ------------------------------------------------------------
        def self.na_summary_message(stats, options)
            exploded = stats[:exploded_container_count]
            parts = ["Exploded #{exploded} #{na_plural(exploded, 'container', 'containers')}."]

            if stats[:unlocked_count] > 0
                parts << "Unlocked #{stats[:unlocked_count]} first."
            end

            if stats[:skipped_locked_count] > 0
                skipped = stats[:skipped_locked_count]
                parts << "#{skipped} locked #{na_plural(skipped, 'container was', 'containers were')} skipped."
            end

            if stats[:failed_count] > 0
                parts << "#{stats[:failed_count]} could not be exploded."
            end

            if options[:move_to_untagged]
                parts << "Moved #{stats[:untagged_count]} #{na_plural(stats[:untagged_count], 'entity', 'entities')} to Untagged."
            end

            if options[:strip_materials]
                parts << "Stripped #{stats[:stripped_material_count]} front, back and edge material #{na_plural(stats[:stripped_material_count], 'assignment', 'assignments')}."
            end

            if options[:delete_faces]
                parts << "Deleted #{stats[:deleted_face_count]} #{na_plural(stats[:deleted_face_count], 'face', 'faces')} and surfaces."
            end

            if options[:delete_hidden]
                parts << "Deleted #{stats[:deleted_hidden_count]} hidden #{na_plural(stats[:deleted_hidden_count], 'entity', 'entities')}."
            end

            if options[:purge_unused]
                parts << na_purge_text(stats)
            end

            parts.compact.join(' ')
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Describe What Purge Unused Removed
        # ------------------------------------------------------------
        def self.na_purge_text(stats)
            removed = [
                na_count_label(stats[:purged_definitions], 'definition', 'definitions'),
                na_count_label(stats[:purged_materials], 'material', 'materials'),
                na_count_label(stats[:purged_tags], 'tag', 'tags')
            ].compact

            return 'Purged unused items.' if removed.empty?

            "Purged unused #{removed.join(', ')}."
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Skip Zero Counts When Listing Purge Results
        # ------------------------------------------------------------
        def self.na_count_label(count_value, singular_word, plural_word)
            return nil unless count_value && count_value > 0

            "#{count_value} #{na_plural(count_value, singular_word, plural_word)}"
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Pick Singular or Plural
        # ------------------------------------------------------------
        def self.na_plural(count_value, singular_word, plural_word)
            count_value == 1 ? singular_word : plural_word
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Merge Dialog Options Onto the Off-by-Default Set
        # ------------------------------------------------------------
        def self.na_resolve_options(options)
            resolved = NA_DEFAULT_OPTIONS.dup
            return resolved unless options.is_a?(Hash)

            resolved[:move_to_untagged] = na_truthy?(options[:move_to_untagged] || options['move_to_untagged'])
            resolved[:strip_materials]  = na_truthy?(options[:strip_materials]  || options['strip_materials'])
            resolved[:delete_faces]    = na_truthy?(options[:delete_faces]     || options['delete_faces'])
            resolved[:delete_hidden]   = na_truthy?(options[:delete_hidden]    || options['delete_hidden'])
            resolved[:unlock_locked]   = na_truthy?(options[:unlock_locked]    || options['unlock_locked'])
            resolved[:purge_unused]     = na_truthy?(options[:purge_unused]    || options['purge_unused'])
            resolved
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | True When the Seed List Contains a Container
        # ------------------------------------------------------------
        def self.na_any_container?(entities)
            entities.any? { |entity| na_valid_entity?(entity) && na_container?(entity) }
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Empty Explode Statistics
        # ------------------------------------------------------------
        def self.na_empty_explode_stats
            {
                exploded_container_count: 0,
                skipped_locked_count:     0,
                unlocked_count:            0,
                failed_count:              0,
                untagged_count:            0,
                stripped_material_count:   0,
                deleted_face_count:       0,
                deleted_hidden_count:     0,
                purged_definitions:       0,
                purged_materials:          0,
                purged_tags:              0,
                purged_tag_folders:       0
            }
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | True When the Entity Is a Group or Component Instance
        # ------------------------------------------------------------
        def self.na_container?(entity)
            entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | True When the Entity Can Still Be Used
        # ------------------------------------------------------------
        def self.na_valid_entity?(entity)
            entity && entity.valid?
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Coerce Dialog / Preference Values to Boolean
        # ------------------------------------------------------------
        def self.na_truthy?(raw_value)
            return raw_value if raw_value == true || raw_value == false

            %w[true 1].include?(raw_value.to_s.strip.downcase)
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

    end # module Na__MegaExplode__Exploder
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
