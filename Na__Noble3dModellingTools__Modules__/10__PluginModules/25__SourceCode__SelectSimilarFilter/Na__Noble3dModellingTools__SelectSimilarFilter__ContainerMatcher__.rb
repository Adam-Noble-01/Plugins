# =============================================================================
# NA NOBLE3D MODELLING TOOLS - SELECT SIMILAR FILTER - CONTAINER MATCHER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__SelectSimilarFilter__ContainerMatcher__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__SelectSimilarFilter__ContainerMatcher
# PURPOSE    : Definition/bounding-box similarity matching for groups and component
#              instances, with an optional deep-nested promote-to-current-level pass
# CREATED    : 2026
#
# MATCHING STRATEGY:
# A candidate group/component matches a reference group/component if either
# enabled criterion hits: (a) it shares the same ComponentDefinition as a
# reference (catches repeated placements of the same component, or copies of
# the same group), or (b) its local, scale-adjusted bounding-box dimensions
# — sorted so orientation does not matter — fall within an mm threshold of a
# reference's dimensions (catches differently-defined but similarly-sized
# groups/components). At least one criterion must be enabled to run, exactly
# like the Geometry mode's Faces/Edges toggles.
#
# DEEP NESTED PROMOTION:
# With Deep Nested enabled, the search additionally recurses into every
# nested group/component below the current editing level. Any nested match
# is promoted to the current level: a new instance of its definition is
# added directly to `model.active_entities` at the same current-level-
# relative transform it already occupied (so it does not visually move),
# its tag/material/shadow/name attributes are copied across, and the
# original nested placement is erased. This is the functional equivalent of
# "cut, then paste in place" applied at depth, and is what allows the tool
# to cumulatively select entities nested at different depths in one pass —
# something the native SketchUp selection tools cannot do.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__SelectSimilarFilter__ContainerMatcher

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        # Hard ceiling on recursion depth while walking nested definitions.
        # Component/group nesting cannot be cyclic in SketchUp, so this only
        # guards against pathologically deep files, not infinite loops.
        NA_MAX_RECURSION_DEPTH = 64

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Entry Point
# -----------------------------------------------------------------------------

        # FUNCTION | Find All Groups/Components Similar to the Reference Selection
        # ------------------------------------------------------------
        # @param model                   [Sketchup::Model]
        # @param reference_entities      [Array<Object>] Entities used as the match seed
        # @param match_definition        [Boolean] Match candidates sharing a reference's definition
        # @param match_bbox              [Boolean] Match candidates within the bbox threshold
        # @param bbox_threshold_internal [Length] Bounding-box tolerance in SketchUp internal units
        # @param deep_nested             [Boolean] Recurse into nested containers and promote matches
        # @return [Hash] { matches:, shallow_count:, promoted_count:, shared_definition_promotion_count: }
        # ------------------------------------------------------------
        def self.Na__SelectSimilarFilter__ContainerMatcher__FindMatches(model, reference_entities, match_definition, match_bbox, bbox_threshold_internal, deep_nested)
            reference_containers = reference_entities.select { |entity| na_container?(entity) }
            return na_empty_result if reference_containers.empty?

            reference_definitions = reference_containers.map(&:definition).compact.uniq
            reference_sizes       = match_bbox ? reference_containers.map { |entity| na_container_size_signature(entity) }.compact : []

            active_entities = model.active_entities
            shallow_matches = na_matching_containers(active_entities, reference_definitions, reference_sizes, match_definition, match_bbox, bbox_threshold_internal)

            promoted_matches, shared_definition_promotion_count =
                deep_nested ? na_promote_nested_matches(model, active_entities, reference_definitions, reference_sizes, match_definition, match_bbox, bbox_threshold_internal) : [[], 0]

            {
                matches:                          shallow_matches + promoted_matches,
                shallow_count:                     shallow_matches.length,
                promoted_count:                    promoted_matches.length,
                shared_definition_promotion_count: shared_definition_promotion_count
            }
        end
        # ------------------------------------------------------------

        # FUNCTION | Summarize Reference Entity Counts from a Selection
        # ------------------------------------------------------------
        # @param selection [Sketchup::Selection]
        # @return [Hash] { group_count:, component_count: }
        # ------------------------------------------------------------
        def self.Na__SelectSimilarFilter__ContainerMatcher__ReferenceSummary(selection)
            {
                group_count:     selection.grep(Sketchup::Group).length,
                component_count: selection.grep(Sketchup::ComponentInstance).length
            }
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build an Empty Result Hash
        # ------------------------------------------------------------
        def self.na_empty_result
            { matches: [], shallow_count: 0, promoted_count: 0, shared_definition_promotion_count: 0 }
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Test Whether an Entity is a Container (Group or Component Instance)
        # ------------------------------------------------------------
        # Sketchup::Group is NOT a subclass of Sketchup::ComponentInstance —
        # they are sibling Drawingelement subclasses — so both must be tested
        # explicitly. Both expose #definition and #transformation, which is
        # all the matcher relies on.
        # ------------------------------------------------------------
        def self.na_container?(entity)
            entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Match Testing
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Find Groups/Components at the Current Level Matching Any Reference
        # ------------------------------------------------------------
        def self.na_matching_containers(active_entities, reference_definitions, reference_sizes, match_definition, match_bbox, bbox_threshold_internal)
            candidates = active_entities.select { |entity| na_container?(entity) }

            na_visible_entities(candidates).select do |candidate|
                na_container_is_match?(candidate, reference_definitions, reference_sizes, match_definition, match_bbox, bbox_threshold_internal)
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Test Whether a Candidate Matches Any Reference by Definition or Bounding Box
        # ------------------------------------------------------------
        def self.na_container_is_match?(candidate, reference_definitions, reference_sizes, match_definition, match_bbox, bbox_threshold_internal)
            return true if match_definition && reference_definitions.include?(candidate.definition)
            return false unless match_bbox

            candidate_size = na_container_size_signature(candidate)
            return false unless candidate_size

            reference_sizes.any? { |reference_size| na_size_signatures_match?(reference_size, candidate_size, bbox_threshold_internal) }
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build a Scale-Adjusted, Orientation-Invariant Bounding-Box Signature
        # ------------------------------------------------------------
        # Uses the definition's own local bounds (its "Drawingelement#bounds"
        # follows the component's internal coordinate system, per the Ruby
        # API docs) scaled by the instance's own axis scale factors, rather
        # than the instance's parent-space bounds, so a rotated duplicate of
        # the same container still produces the same signature.
        # ------------------------------------------------------------
        def self.na_container_size_signature(entity)
            definition = entity.definition
            return nil unless definition

            bounds = definition.bounds
            scale  = na_transformation_axis_scale(entity.transformation)

            [
                bounds.width  * scale[0],
                bounds.height * scale[1],
                bounds.depth  * scale[2]
            ].sort
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Extract the Absolute Axis Scale Factors from a Transformation
        # ------------------------------------------------------------
        # Transforms each world unit axis through the transformation and
        # measures the resulting length. This is unambiguous regardless of
        # whether Transformation#xaxis/yaxis/zaxis are normalized (community
        # references disagree), since a rotation alone cannot change a unit
        # vector's length — only the scale component of the matrix can.
        # ------------------------------------------------------------
        def self.na_transformation_axis_scale(transformation)
            [
                X_AXIS.transform(transformation).length,
                Y_AXIS.transform(transformation).length,
                Z_AXIS.transform(transformation).length
            ]
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Compare Two Sorted Bounding-Box Size Triples Within Threshold
        # ------------------------------------------------------------
        def self.na_size_signatures_match?(reference_sizes, candidate_sizes, threshold_internal)
            reference_sizes.each_index.all? do |index|
                (candidate_sizes[index] - reference_sizes[index]).abs <= threshold_internal
            end
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Deep Nested Promotion
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Collect, Then Promote, Every Nested Match to the Current Level
        # ------------------------------------------------------------
        # Traverses read-only first so no entity is mutated mid-walk, then
        # promotes the full match list inside a single undo-able operation.
        # ------------------------------------------------------------
        def self.na_promote_nested_matches(model, active_entities, reference_definitions, reference_sizes, match_definition, match_bbox, bbox_threshold_internal)
            active_path = model.active_path || []
            nested_hits = na_collect_nested_matches(active_entities, active_path, reference_definitions, reference_sizes, match_definition, match_bbox, bbox_threshold_internal)
            return [[], 0] if nested_hits.empty?

            promoted_entities                 = []
            shared_definition_promotion_count = 0

            model.start_operation('Select Similar Containers - Promote Nested', true)
            begin
                nested_hits.each do |hit|
                    next unless hit[:entity].valid?

                    shared_definition_promotion_count += 1 if na_shared_definition_promotion?(hit[:entity])
                    promoted_entities << na_promote_entity(active_entities, hit[:entity], hit[:transform])
                end
                model.commit_operation
            rescue => error
                model.abort_operation
                raise error
            end

            [promoted_entities, shared_definition_promotion_count]
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Recursively Collect Nested Matches Below the Current Level
        # ------------------------------------------------------------
        # Returns an array of { entity:, transform: } for every nested match,
        # where transform is already expressed relative to the current
        # editing level (ready to pass straight into add_instance).
        # ------------------------------------------------------------
        def self.na_collect_nested_matches(active_entities, active_path, reference_definitions, reference_sizes, match_definition, match_bbox, bbox_threshold_internal)
            results = []

            top_level_containers = na_visible_entities(active_entities.select { |entity| na_container?(entity) })
            top_level_containers.each do |top_container|
                next if active_path.include?(top_container)

                na_walk_nested_containers(top_container, top_container.transformation, active_path, reference_definitions, reference_sizes, match_definition, match_bbox, bbox_threshold_internal, results, 0)
            end

            results
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Walk One Container's Children, Recording Matches and Recursing Deeper
        # ------------------------------------------------------------
        def self.na_walk_nested_containers(container, accumulated_transform, active_path, reference_definitions, reference_sizes, match_definition, match_bbox, bbox_threshold_internal, results, depth)
            return if depth >= NA_MAX_RECURSION_DEPTH

            children = na_visible_entities(container.definition.entities.select { |entity| na_container?(entity) })
            children.each do |child|
                next if active_path.include?(child)

                child_transform = accumulated_transform * child.transformation

                if na_container_is_match?(child, reference_definitions, reference_sizes, match_definition, match_bbox, bbox_threshold_internal)
                    results << { entity: child, transform: child_transform }
                end

                na_walk_nested_containers(child, child_transform, active_path, reference_definitions, reference_sizes, match_definition, match_bbox, bbox_threshold_internal, results, depth + 1)
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Promote a Single Nested Entity to the Current Editing Level
        # ------------------------------------------------------------
        # Adds a new instance of the entity's definition at its current-
        # level-relative transform (so it does not visually move), restores
        # its organisational attributes, converts back to a Group if the
        # source was a Group, then erases the original nested placement.
        # ------------------------------------------------------------
        def self.na_promote_entity(active_entities, entity, transform)
            new_instance = active_entities.add_instance(entity.definition, transform)
            promoted     = entity.is_a?(Sketchup::Group) ? na_convert_instance_to_group(active_entities, new_instance, transform) : new_instance

            na_copy_instance_attributes(entity, promoted)
            entity.erase!

            promoted
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Convert a Freshly-Added Component Instance Back into a Group
        # ------------------------------------------------------------
        # The Ruby API has no ComponentInstance#to_group counterpart to the
        # existing Group#to_component, so a Group source is promoted by
        # adding an instance of its (private) definition, exploding that
        # single instance, and immediately re-wrapping the result in a new
        # group — the standard workaround for this API gap. If the source
        # was a genuinely empty group, explode yields nothing to wrap, so
        # the new empty group's transform is set explicitly instead.
        # ------------------------------------------------------------
        def self.na_convert_instance_to_group(active_entities, instance, transform)
            exploded_entities = instance.explode
            drawing_elements  = exploded_entities.grep(Sketchup::Drawingelement)
            new_group         = active_entities.add_group(drawing_elements)
            new_group.transformation = transform if drawing_elements.empty?
            new_group
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Copy Organisational Attributes from a Source Entity to Its Promoted Copy
        # ------------------------------------------------------------
        def self.na_copy_instance_attributes(source_entity, target_entity)
            target_entity.layer            = source_entity.layer if source_entity.layer
            target_entity.material         = source_entity.material if source_entity.material
            target_entity.casts_shadows    = source_entity.casts_shadows?
            target_entity.receives_shadows = source_entity.receives_shadows?
            target_entity.hidden           = source_entity.hidden?
            target_entity.name             = source_entity.name if source_entity.respond_to?(:name)
        rescue => error
            puts "[Na__Noble3dModellingTools] SelectSimilarFilter: attribute copy warning: #{error.class}: #{error.message}"
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Detect Whether Promoting This Entity Mutates a Definition Used Elsewhere
        # ------------------------------------------------------------
        # A Group's definition is normally exclusive to it, but a Component's
        # definition can back many placements — erasing a nested instance out
        # of a shared definition changes every placement of that component,
        # exactly as manually editing into it and deleting something would.
        # ------------------------------------------------------------
        def self.na_shared_definition_promotion?(entity)
            definition = entity.definition
            definition && definition.instances.length > 1
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Visibility Filtering
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Reject Hidden Entities and Entities on Hidden Tags
        # ------------------------------------------------------------
        # Delegates to the Geometry mode's matcher so both modes share one
        # visibility rule instead of maintaining two copies of it.
        # ------------------------------------------------------------
        def self.na_visible_entities(entities)
            Na__SelectSimilarFilter__SimilarityMatcher.na_visible_entities(entities)
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__SelectSimilarFilter__ContainerMatcher
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
