# =============================================================================
# NA NOBLE3D MODELLING TOOLS - PAINT DEEP NESTED FACES - FACE COLLECTOR
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__PaintDeepNestedFaces__FaceCollector__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__PaintDeepNestedFaces__FaceCollector
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Walk the current selection and gather every paintable face,
#              deliberately ignoring edges and every other entity type.
# CREATED    : 2026
#
# NESTING RULES:
# - Deep nesting ON  : faces are gathered from every level below the selection.
# - Deep nesting OFF : faces are gathered from the selection itself and from one
#                      level inside each selected container only.
# - Directly selected faces are always gathered, whichever mode is active.
#
# SAFETY:
# - Locked containers are skipped and counted rather than raising.
# - Recursion is capped and definition identity is tracked to stop cycles.
# - Faces are de-duplicated by entityID, so a definition reached through two
#   instances is reported and painted once.
#
# =============================================================================

require 'set'

module Na__Noble3dModellingTools
    module Na__PaintDeepNestedFaces__FaceCollector

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_MAX_RECURSION_DEPTH = 64                                                 # <-- Hard stop for pathological nesting
        NA_LIMIT_THROW_TAG     = :na_paint_faces_limit                              # <-- Unwinds the walk once a preview cap is hit

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Collection API
# -----------------------------------------------------------------------------

        # FUNCTION | Collect Every Paintable Face Within a Selection
        # ------------------------------------------------------------
        # @param selection      [Sketchup::Selection, Array] Entities to walk
        # @param deep_nesting   [Boolean] True to walk every nested level
        # @param isolate_shared [Boolean] True to make shared containers unique
        #                                 before descending (model-modifying, so
        #                                 only pass true inside an operation)
        # @param face_limit     [Integer, nil] Stop after this many faces. Used
        #                                 by the live preview so a huge
        #                                 selection cannot stall the dialog.
        #                                 Pass nil when actually painting.
        # @return [Hash] { faces: [Sketchup::Face], stats: Hash }
        # ------------------------------------------------------------
        def self.Na__PaintDeepNestedFaces__FaceCollector__Collect(selection, deep_nesting, isolate_shared = false, face_limit = nil)
            context = {
                faces:      [],
                seen_faces: Set.new,
                seen_defs:  Set.new,
                stats:      na_empty_statistics,
                deep:       !!deep_nesting,
                isolate:    !!isolate_shared,
                limit:      face_limit
            }

            catch(NA_LIMIT_THROW_TAG) do
                selection.to_a.each do |entity|
                    na_walk_entity(entity, context, 0, [], true)
                end
            end

            context[:stats][:face_count] = context[:faces].length
            { faces: context[:faces], stats: context[:stats] }
        end
        # ------------------------------------------------------------

        # FUNCTION | Build an Empty Result for the No-Selection State
        # ------------------------------------------------------------
        def self.Na__PaintDeepNestedFaces__FaceCollector__EmptyResult
            { faces: [], stats: na_empty_statistics }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Selection Traversal
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Walk One Entity and Route It by Type
        # ------------------------------------------------------------
        # Edges are not listed here on purpose. They fall through to the final
        # branch and are never touched, which is the whole point of this tool.
        # ------------------------------------------------------------
        def self.na_walk_entity(entity, context, depth, definition_stack, is_top_level)
            return unless na_valid_entity?(entity)

            case entity
            when Sketchup::Face
                na_record_face(entity, context, is_top_level)
            when Sketchup::Group, Sketchup::ComponentInstance
                na_walk_container(entity, context, depth, definition_stack)
            else
                context[:stats][:ignored_entity_count] += 1
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Walk One Container and Its Immediate Children
        # ------------------------------------------------------------
        def self.na_walk_container(container, context, depth, definition_stack)
            if container.locked?
                context[:stats][:locked_container_count] += 1
                return
            end

            if depth >= NA_MAX_RECURSION_DEPTH
                context[:stats][:depth_limit_count] += 1
                return
            end

            definition_id = na_container_definition_id(container)
            if definition_id && definition_stack.include?(definition_id)
                context[:stats][:cyclic_container_count] += 1
                return
            end

            na_record_shared_container(container, context)
            container.make_unique if context[:isolate] && na_shared_container?(container)

            child_depth      = depth + 1
            next_stack       = definition_stack.dup
            unique_defn_id   = na_container_definition_id(container)
            next_stack << unique_defn_id if unique_defn_id

            context[:stats][:container_count] += 1
            context[:stats][:deepest_level] = child_depth if child_depth > context[:stats][:deepest_level]

            na_container_entities(container).to_a.each do |child_entity|
                if na_container_entity?(child_entity) && !context[:deep]
                    context[:stats][:skipped_nested_container_count] += 1
                    next
                end

                na_walk_entity(child_entity, context, child_depth, next_stack, false)
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Check Whether an Entity Is a Walkable Container
        # ------------------------------------------------------------
        # With deep nesting off, nested containers are left alone entirely, so
        # only the faces sitting directly inside the selected container change.
        # ------------------------------------------------------------
        def self.na_container_entity?(entity)
            entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Record One Face Once
        # ------------------------------------------------------------
        # Faces reached through two instances of the same definition are the
        # same entity, so de-duplicating by entityID keeps the reported count
        # honest and stops the painter touching one face twice.
        # ------------------------------------------------------------
        def self.na_record_face(face, context, is_top_level)
            face_id = face.entityID
            return if context[:seen_faces].include?(face_id)

            context[:seen_faces] << face_id
            context[:faces] << face
            context[:stats][:direct_face_count] += 1 if is_top_level

            return unless context[:limit] && context[:faces].length >= context[:limit]

            context[:stats][:limit_reached] = true
            throw NA_LIMIT_THROW_TAG
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Shared Definition Reporting
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Record a Container Whose Definition Has Siblings
        # ------------------------------------------------------------
        # Painting inside a shared definition changes every placement of it.
        # Each definition is counted once so the dialog can warn honestly.
        # ------------------------------------------------------------
        def self.na_record_shared_container(container, context)
            return unless na_shared_container?(container)

            definition_id = na_container_definition_id(container)
            return if definition_id.nil? || context[:seen_defs].include?(definition_id)

            context[:seen_defs] << definition_id
            context[:stats][:shared_definition_count] += 1
            context[:stats][:other_instance_count]    += (na_instance_count(container) - 1)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Check Whether a Container Shares Its Definition
        # ------------------------------------------------------------
        def self.na_shared_container?(container)
            na_instance_count(container) > 1
        rescue
            false
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Count the Placements of a Container Definition
        # ------------------------------------------------------------
        def self.na_instance_count(container)
            definition = container.definition
            return 1 unless definition

            definition.instances.length
        rescue
            1
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Container Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Return the Editable Entities for a Container
        # ------------------------------------------------------------
        def self.na_container_entities(container)
            return container.entities if container.is_a?(Sketchup::Group)

            container.definition.entities
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Return a Container Definition Identity
        # ------------------------------------------------------------
        def self.na_container_definition_id(container)
            container.definition.entityID
        rescue StandardError
            nil
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Check Entity Can Be Safely Inspected
        # ------------------------------------------------------------
        def self.na_valid_entity?(entity)
            entity &&
                entity.respond_to?(:valid?) &&
                entity.valid? &&
                (!entity.respond_to?(:deleted?) || !entity.deleted?)
        rescue StandardError
            false
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Statistics
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Build an Empty Traversal Statistics Hash
        # ------------------------------------------------------------
        def self.na_empty_statistics
            {
                face_count:                    0,
                direct_face_count:             0,
                container_count:               0,
                deepest_level:                 0,
                locked_container_count:        0,
                skipped_nested_container_count: 0,
                shared_definition_count:       0,
                other_instance_count:          0,
                ignored_entity_count:          0,
                depth_limit_count:             0,
                cyclic_container_count:        0,
                limit_reached:                 false
            }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__PaintDeepNestedFaces__FaceCollector
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
