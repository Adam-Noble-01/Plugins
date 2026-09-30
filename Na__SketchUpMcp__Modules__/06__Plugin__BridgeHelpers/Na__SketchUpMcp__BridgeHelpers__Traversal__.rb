# =============================================================================
# NA SKETCHUP MCP - BRIDGE HELPERS - TRAVERSAL
# =============================================================================
#
# FILE       : Na__SketchUpMcp__BridgeHelpers__Traversal__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Traversal
# PURPOSE    : Walk the model hierarchy with instance paths and a hard budget
# CREATED    : 2026
#
# WHY A BUDGET:
# A component used 2,000 times is walked 2,000 times when world positions
# matter (each copy sits somewhere else). On a big model that is millions of
# entities, so every walk carries a budget (AppConfig max_traversal_entities)
# and reports "truncated" instead of freezing SketchUp. The agent is told to
# narrow the query (parent_id, types, max_depth) when that happens.
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Traversal

# -----------------------------------------------------------------------------
# REGION | Budget
# -----------------------------------------------------------------------------

        def self.Na__Traversal__NewBudget(limit = nil)
            limit ||= Na__ConfigLoader.Na__ConfigLoader__Get('defaults', 'max_traversal_entities', 250_000).to_i
            { remaining: limit, visited: 0, truncated: false }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Walk
# -----------------------------------------------------------------------------

        # Yields |entity, container_path, depth| for every entity in `entities`, then descends
        # into groups/components (whose own entities get container_path + [instance]).
        # depth 0 = the given collection. recurse: false visits only that collection.
        def self.Na__Traversal__Walk(entities, container_path, max_depth, budget, recurse = true, depth = 0, &block)
            entities.each do |entity|
                if budget[:remaining] <= 0
                    budget[:truncated] = true
                    return
                end

                budget[:remaining] -= 1
                budget[:visited] += 1
                yield(entity, container_path, depth)

                next unless recurse && depth < max_depth && Na__EntityResolver.Na__EntityResolver__IsInstance(entity)

                self.Na__Traversal__Walk(entity.definition.entities, container_path + [entity], max_depth, budget, recurse, depth + 1, &block)
                return if budget[:truncated]
            end
        end

        # Faces (with their container paths) inside the given entities, looking into groups/components.
        def self.Na__Traversal__FacesWithin(entity, container_path, max_depth, budget)
            faces = []
            if entity.is_a?(Sketchup::Face)
                faces << [entity, container_path]
            elsif Na__EntityResolver.Na__EntityResolver__IsInstance(entity)
                self.Na__Traversal__Walk(entity.definition.entities, container_path + [entity], max_depth, budget) do |child, child_path, _depth|
                    faces << [child, child_path] if child.is_a?(Sketchup::Face)
                end
            end
            faces
        end

# endregion -------------------------------------------------------------------

    end # module Na__Traversal
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
