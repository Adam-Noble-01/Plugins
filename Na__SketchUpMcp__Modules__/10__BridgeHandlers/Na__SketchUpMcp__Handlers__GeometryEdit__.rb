# =============================================================================
# NA SKETCHUP MCP - HANDLERS - GEOMETRY EDIT
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__GeometryEdit__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__GeometryEdit
# PURPOSE    : geometry_edit: soften / harden / hide / show edges, reverse
#              faces, find faces, erase stray edges, merge coplanar faces,
#              intersect groups
# CREATED    : 2026
#
# SHARED DEFINITIONS:
# Editing the geometry inside a component edits EVERY copy of it. Group and
# component ids are resolved to their definitions once each (never twice for
# two copies), and the result says how many copies were affected. Pass
# make_unique:true to give the targeted instances their own definitions first.
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Handlers__GeometryEdit

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_OPERATIONS = %w[soften_edges harden_edges hide_edges show_edges reverse_faces find_faces
                           erase_stray_edges merge_coplanar_faces intersect].freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | geometry_edit
# -----------------------------------------------------------------------------

        def self.Na__Handlers__GeometryEdit__Edit(params, ctx)
            model = ctx[:model]
            operation = Na__Params.Na__Params__Enum(params, 'operation', NA_OPERATIONS, nil, required: true)
            targets = Na__EntityResolver.Na__EntityResolver__RequireEntities(model, Na__Params.Na__Params__IdArray(params, 'ids'))
            return na_intersect(targets, params, ctx) if operation == 'intersect'

            if Na__Params.Na__Params__Boolean(params, 'make_unique', false)
                targets = targets.map { |entity| Na__EntityResolver.Na__EntityResolver__IsInstance(entity) ? na_make_unique(entity) : entity }
            end

            faces, edges, definitions = na_collect(targets, Na__Params.Na__Params__Boolean(params, 'recursive', true))
            na_warn_shared(definitions, ctx)
            count = na_apply(operation, faces, edges, params)
            { 'operation' => operation, 'changed' => count, 'faces_considered' => faces.length, 'edges_considered' => edges.length,
              'definitions_edited' => definitions.length, 'summary' => "#{operation}: #{count} element(s) changed." }
        end

        def self.na_apply(operation, faces, edges, params)
            case operation
            when 'soften_edges'
                self.Na__Handlers__GeometryEdit__SoftenByAngle(edges, Na__Params.Na__Params__Number(params, 'angle', Na__ConfigLoader.Na__ConfigLoader__Get('defaults', 'soften_angle_degrees', 20.0).to_f, min: 0.0, max: 180.0), true)
            when 'harden_edges'
                edges.each { |edge| edge.soft = false; edge.smooth = false }.length
            when 'hide_edges'
                edges.each { |edge| edge.hidden = true }.length
            when 'show_edges'
                edges.each { |edge| edge.hidden = false }.length
            when 'reverse_faces'
                faces.each(&:reverse!).length
            when 'find_faces'
                edges.select(&:valid?).sum { |edge| edge.find_faces.to_i }
            when 'erase_stray_edges'
                na_erase_grouped(edges.select { |edge| edge.valid? && edge.faces.empty? })
            when 'merge_coplanar_faces'
                na_erase_grouped(edges.select { |edge| edge.valid? && na_coplanar_seam?(edge) })
            end
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Helper: soften by angle (also used by geometry_create_mesh)
# -----------------------------------------------------------------------------

        # Soft+smooth every edge whose two faces meet at less than angle_degrees.
        def self.Na__Handlers__GeometryEdit__SoftenByAngle(edges, angle_degrees, smooth_flag)
            limit = Na__Units.Na__Units__Radians(angle_degrees)
            edges.count do |edge|
                next false unless edge.valid?

                neighbours = edge.faces
                next false unless neighbours.length == 2 && neighbours[0].normal.angle_between(neighbours[1].normal) <= limit

                edge.soft = true
                edge.smooth = smooth_flag
                true
            end
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Collection
# -----------------------------------------------------------------------------

        # Public: [faces, edges, definitions] inside the targets, each definition once.
        def self.Na__Handlers__GeometryEdit__Collect(targets, recursive)
            na_collect(targets, recursive)
        end

        # -> [faces, edges, definitions_touched]
        def self.na_collect(targets, recursive)
            faces = []
            edges = []
            definitions = []
            add_definition = lambda do |definition|
                next if definitions.include?(definition)

                definitions << definition
                definition.entities.each do |entity|
                    faces << entity if entity.is_a?(Sketchup::Face)
                    edges << entity if entity.is_a?(Sketchup::Edge)
                    add_definition.call(entity.definition) if recursive && Na__EntityResolver.Na__EntityResolver__IsInstance(entity)
                end
            end

            targets.each do |entity|
                case entity
                when Sketchup::Face
                    faces << entity
                    edges.concat(entity.edges)
                when Sketchup::Edge
                    edges << entity
                when Sketchup::Group, Sketchup::ComponentInstance
                    add_definition.call(entity.definition)
                end
            end
            [faces.uniq, edges.uniq, definitions]
        end

        def self.na_warn_shared(definitions, ctx)
            shared = definitions.select { |definition| definition.count_instances > 1 }
            return if shared.empty?

            copies = shared.sum(&:count_instances)
            ctx[:warnings] << "Edited #{shared.length} definition(s) used #{copies} times in total; every copy changed. " \
                              'Pass make_unique:true to change only the targeted instances.'
        end

        def self.na_make_unique(instance)
            return instance if instance.definition.count_instances <= 1

            instance.make_unique
            instance
        end

        def self.na_coplanar_seam?(edge)
            neighbours = edge.faces
            return false unless neighbours.length == 2

            first, second = neighbours
            return false unless first.material == second.material && first.back_material == second.back_material

            if first.respond_to?(:coplanar_with?)
                first.coplanar_with?(second)
            else
                plane = first.plane
                first.normal.parallel?(second.normal) && second.vertices.all? { |vertex| vertex.position.distance_to_plane(plane).abs < 0.001 }
            end
        end

        def self.na_erase_grouped(edges)
            edges.group_by(&:parent).each do |owner, group|
                owner.entities.erase_entities(group.select(&:valid?))
            end
            edges.length
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Intersect
# -----------------------------------------------------------------------------

        # Each target group/component is intersected with the others (or with its whole
        # context); the new edges go inside each target, like Intersect Faces > With Selection.
        def self.na_intersect(targets, params, ctx)
            instances = targets.select { |entity| Na__EntityResolver.Na__EntityResolver__IsInstance(entity) }
            if instances.length != targets.length
                raise Na__McpError.new('wrong_type', 'intersect works on groups/components.', 'Group the loose geometry first with group_create.')
            end

            owners = instances.map(&:parent).uniq
            if owners.length > 1
                raise Na__McpError.new('context_error', 'All targets must share the same parent (the same group or the model root).',
                                       'Move them into one context first.')
            end

            mode = Na__Params.Na__Params__Enum(params, 'mode', %w[with_each_other with_context], 'with_each_other')
            include_hidden = Na__Params.Na__Params__Boolean(params, 'include_hidden', false)
            if Na__Params.Na__Params__Boolean(params, 'make_unique', false)
                instances = instances.map { |instance| na_make_unique(instance) }
            end
            if mode == 'with_each_other' && instances.length < 2
                raise Na__McpError.new('invalid_params', 'with_each_other needs at least two groups.', 'Pass two or more ids, or use mode "with_context".')
            end

            context_entities = owners.first.entities
            created = 0
            instances.each do |instance|
                others = mode == 'with_each_other' ? instances - [instance] : context_entities.to_a - [instance]
                new_edges = context_entities.intersect_with(false, Na__Coordinates.Na__Coordinates__Identity, instance.definition.entities,
                                                            instance.transformation, include_hidden, others)
                created += new_edges ? new_edges.length : 0
            end
            na_warn_shared(instances.map(&:definition).uniq, ctx)
            { 'operation' => 'intersect', 'mode' => mode, 'edges_created' => created,
              'summary' => "Intersected #{instances.length} group(s): #{created} new edge(s)." }
        end

# endregion -------------------------------------------------------------------

    end # module Na__Handlers__GeometryEdit
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
