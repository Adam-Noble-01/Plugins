# =============================================================================
# NA INSERT PRIMATIVES - DEEP VERTEX MOVE - SCOPE AND CANDIDATE VERTICES
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnVertexMove__Scope__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Read the selection as the scope and list every vertex inside it,
#              at any nesting depth, with where it sits in the world
# CREATED    : 2026
#
# DESCRIPTION:
# - The selection made before the tool starts is an instruction: ONLY the
#   vertices inside these items may move. A group or component offers every
#   vertex at every depth below it; a loose face or edge offers its own
#   vertices and nothing else. Nothing outside the scope can be picked, so
#   nothing outside it can move.
# - Every vertex is listed with the CONTEXT it lives in: the entities that own
#   it, the instance path down to them and the transformation to world. A
#   definition reached by several paths is read once and placed once per path.
# - Hidden geometry, hidden objects and hidden tags are left out unless the
#   view is showing them. Locked groups are skipped and counted, as the deep
#   pickers skip them: locked means not there to the tool.
#
# COORDINATES (the 5.1.2 rule, see the DeepPick hub header):
# - The scope is read from the ACTIVE context, where every coordinate is
#   global. A selected instance's transformation is therefore already its
#   transformation to world, and a selected loose vertex is already world.
# - Below that every definition is closed: positions are local and each
#   nested transformation is relative to its parent, so the world
#   transformation is the product down the path. No edit_transform is
#   involved; the one place it is (a local gimbal on the open group's own
#   axes) is legitimate use 1 of the rule.
#
# FINDING A VERTEX AGAIN:
# - A move that opens a group can hand back new vertex objects (a group copy
#   made unique on opening), and an undo can take them away again. So a
#   picked vertex is re-found by its scope root, its nesting depth and where
#   it stands in the world, never by object identity alone.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnGridSnap__'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnDeepPick__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Scope Constants
    # -----------------------------------------------------------------------------

    NA_VM_MAX_CANDIDATES = 200_000                                            # <-- A scope bigger than this is cut short, and says so
    NA_VM_MAX_DEPTH      = 48                                                 # <-- Guard on the nesting walk
    NA_VM_CELL           = 0.01                                               # <-- Inches; one cell of the find-it-again index
    NA_VM_MATCH_TOL      = 0.002                                              # <-- Inches; twice SketchUp's merge tolerance, as the deep pick uses
    NA_VM_OPEN_KEY       = 'open'.freeze                                      # <-- Context key of the geometry loose in the open context

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Visibility
    # -----------------------------------------------------------------------------

    # FUNCTION | Is This a Group or a Component Instance?
    # ------------------------------------------------------------
    def self.Na__VertexMove__Instance?(entity)
        entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
    end
    # ---------------------------------------------------------------

    # FUNCTION | What the View Is Showing That Is Normally Hidden
    # ------------------------------------------------------------
    # Returns [hidden_geometry, hidden_objects]. SketchUp 2020 split the one
    # switch into two; before that DrawHidden answered for both.
    # ------------------------------------------------------------
    def self.Na__VertexMove__ShowHidden(model)
        options  = model.rendering_options
        geometry = options['DrawHidden'] == true
        objects  = options['DrawHiddenObjects']
        [geometry, objects.nil? ? geometry : objects == true]
    rescue StandardError
        [false, false]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is an Entity's Tag Showing, Folders Included?
    # ------------------------------------------------------------
    def self.Na__VertexMove__TagShown?(entity)
        layer = entity.layer
        return true unless layer
        return false unless layer.visible?

        folder = layer.respond_to?(:folder) ? layer.folder : nil
        while folder
            return false unless folder.visible?

            folder = folder.respond_to?(:folder) ? folder.folder : nil
        end

        true
    rescue StandardError
        true
    end
    # ---------------------------------------------------------------

    # FUNCTION | Should the Walk See This Entity?
    # ------------------------------------------------------------
    def self.Na__VertexMove__Shown?(entity, show_hidden)
        return false unless entity && entity.valid?
        return false if entity.hidden? && !show_hidden

        Na__InsertPrimatives.Na__VertexMove__TagShown?(entity)
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Readable Name of an Instance
    # ------------------------------------------------------------
    def self.Na__VertexMove__InstanceName(instance)
        return 'model' unless instance

        name = instance.name.to_s
        name = instance.definition.name.to_s if name.empty? && instance.respond_to?(:definition)
        name.empty? ? 'unnamed' : name
    rescue StandardError
        'unnamed'
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Walking the Scope
    # -----------------------------------------------------------------------------

    # FUNCTION | Every Vertex Inside the Selected Items, With Its Context
    # ------------------------------------------------------------
    # `roots` are entities of the ACTIVE context — what Model#selection holds.
    # Anything that is not a group, a component, a face or an edge is ignored:
    # an image or a guide has no vertices to offer.
    # ------------------------------------------------------------
    def self.Na__VertexMove__CollectScope(model, roots)
        scope = {
            :roots           => [],
            :root_ids        => [],
            :contexts        => [],
            :contexts_by_key => {},
            :candidates      => [],
            :by_key          => {},
            :points          => [],                                           # <-- Every candidate's world point, for one draw call
            :open_path       => Na__InsertPrimatives.Na__DeepPick__ContextPath || [],
            :instances       => 0,
            :loose           => 0,
            :locked          => 0,
            :truncated       => false,
            :min             => nil,
            :max             => nil
        }

        show_geometry, show_objects = Na__InsertPrimatives.Na__VertexMove__ShowHidden(model)
        memo  = {}
        loose = []

        (roots || []).each do |entity|
            next unless entity && entity.valid?

            if Na__InsertPrimatives.Na__VertexMove__Instance?(entity)
                scope[:roots] << entity

                if entity.locked?
                    scope[:locked] += 1
                    next
                end

                Na__InsertPrimatives.Na__VertexMove__WalkInstance(
                    scope, entity, entity.transformation, [entity], entity.entityID,
                    show_geometry, show_objects, memo
                )
            elsif entity.is_a?(Sketchup::Face) || entity.is_a?(Sketchup::Edge)
                scope[:roots] << entity
                loose << entity
            end
        end

        Na__InsertPrimatives.Na__VertexMove__AddLoose(scope, model, loose) unless loose.empty?

        scope[:root_ids] = scope[:roots].map(&:entityID)
        scope
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Selected Loose Faces and Edges — Their Own Vertices Only
    # ------------------------------------------------------------
    # They live in the open context, where positions are already global, so
    # the context's transformation is the identity.
    # ------------------------------------------------------------
    def self.Na__VertexMove__AddLoose(scope, model, loose)
        context = Na__InsertPrimatives.Na__VertexMove__NewContext(
            scope, model.active_entities, [], Geom::Transformation.new, 0, true
        )
        seen = {}

        loose.each do |entity|
            entity.vertices.each do |vertex|
                next if seen[vertex]

                seen[vertex] = true
                break if Na__InsertPrimatives.Na__VertexMove__Full?(scope)

                Na__InsertPrimatives.Na__VertexMove__AddCandidate(scope, context, vertex, vertex.position)
            end
        end

        scope[:loose] = loose.length
    end
    # ---------------------------------------------------------------

    # FUNCTION | One Instance, Then Everything Nested Inside It
    # ------------------------------------------------------------
    # `world` maps the instance's definition coordinates to world. A child's
    # transformation is relative to this definition, so the child's world is
    # world * child.transformation — the product down the path.
    # ------------------------------------------------------------
    def self.Na__VertexMove__WalkInstance(scope, instance, world, nested, root_id, show_geometry, show_objects, memo)
        return if nested.length > NA_VM_MAX_DEPTH
        return if Na__InsertPrimatives.Na__VertexMove__Full?(scope)

        definition = instance.definition
        return unless definition

        context  = Na__InsertPrimatives.Na__VertexMove__NewContext(scope, definition.entities, nested, world, root_id, false)
        contents = memo[definition] ||= Na__InsertPrimatives.Na__VertexMove__DefinitionContents(definition, show_geometry, show_objects)
        scope[:instances] += 1

        contents[:vertices].each do |vertex|
            break if Na__InsertPrimatives.Na__VertexMove__Full?(scope)

            Na__InsertPrimatives.Na__VertexMove__AddCandidate(scope, context, vertex, vertex.position.transform(world))
        end

        contents[:instances].each do |child|
            break if Na__InsertPrimatives.Na__VertexMove__Full?(scope)

            if child.locked?
                scope[:locked] += 1
                next
            end

            Na__InsertPrimatives.Na__VertexMove__WalkInstance(
                scope, child, world * child.transformation, nested + [child], root_id,
                show_geometry, show_objects, memo
            )
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Vertices and Child Instances a Definition Shows
    # ------------------------------------------------------------
    # Read once per definition however many paths reach it. A face's vertices
    # come in with the face, so a hidden edge between two shown faces still
    # gives up its ends; soft and smooth edges are not hidden and count.
    # ------------------------------------------------------------
    def self.Na__VertexMove__DefinitionContents(definition, show_geometry, show_objects)
        seen      = {}
        instances = []

        definition.entities.each do |entity|
            if entity.is_a?(Sketchup::Edge) || entity.is_a?(Sketchup::Face)
                next unless Na__InsertPrimatives.Na__VertexMove__Shown?(entity, show_geometry)

                entity.vertices.each { |vertex| seen[vertex] = true }
            elsif Na__InsertPrimatives.Na__VertexMove__Instance?(entity)
                instances << entity if Na__InsertPrimatives.Na__VertexMove__Shown?(entity, show_objects)
            end
        end

        { :vertices => seen.keys, :instances => instances }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Record One Place Vertices Live
    # ------------------------------------------------------------
    # The key is the chain of instance ids below the open context, so the
    # same definition reached by two paths is two contexts — two places in
    # the world — sharing one set of vertices.
    # ------------------------------------------------------------
    def self.Na__VertexMove__NewContext(scope, entities, nested, transformation, root_id, open)
        key = nested.empty? ? NA_VM_OPEN_KEY : nested.map(&:entityID).join('/')

        context = {
            :key            => key,
            :entities       => entities,
            :nested         => nested,                                        # <-- Instances below the open context, outermost first
            :path           => scope[:open_path] + nested,                    # <-- ABSOLUTE: model root to the innermost instance
            :transformation => transformation,                                # <-- Reported coordinates to world
            :root_id        => root_id,
            :depth          => nested.length,
            :open           => open,
            :shared         => Na__InsertPrimatives.Na__VertexMove__SharedOnPath(nested)
        }

        scope[:contexts] << context
        scope[:contexts_by_key][key] = context
        context
    end
    # ---------------------------------------------------------------

    # FUNCTION | The First Instance on the Path Whose Definition Has Copies
    # ------------------------------------------------------------
    # Editing anywhere below it changes every copy, which is SketchUp's own
    # rule for components and is said out loud rather than discovered.
    # ------------------------------------------------------------
    def self.Na__VertexMove__SharedOnPath(nested)
        nested.each do |instance|
            count = instance.definition.instances.length
            next if count <= 1

            return { :name => Na__InsertPrimatives.Na__VertexMove__InstanceName(instance), :count => count }
        end

        nil
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Add One Vertex, in One Context, at One World Point
    # ------------------------------------------------------------
    def self.Na__VertexMove__AddCandidate(scope, context, vertex, world)
        candidate = {
            :key     => "#{context[:key]}|#{vertex.entityID}",
            :vertex  => vertex,
            :context => context,
            :world   => world
        }

        scope[:candidates] << candidate
        scope[:by_key][candidate[:key]] = candidate
        scope[:points] << world
        Na__InsertPrimatives.Na__VertexMove__GrowBounds(scope, world)
        candidate
    end
    # ---------------------------------------------------------------

    # FUNCTION | Has the Walk Reached Its Cap?
    # ------------------------------------------------------------
    def self.Na__VertexMove__Full?(scope)
        return false if scope[:candidates].length < NA_VM_MAX_CANDIDATES

        scope[:truncated] = true
        true
    end
    # ---------------------------------------------------------------

    # FUNCTION | Keep the World Box Round the Scope, for the Draw Extents
    # ------------------------------------------------------------
    def self.Na__VertexMove__GrowBounds(scope, point)
        low  = scope[:min]
        high = scope[:max]

        if low.nil?
            scope[:min] = [point.x.to_f, point.y.to_f, point.z.to_f]
            scope[:max] = [point.x.to_f, point.y.to_f, point.z.to_f]
            return
        end

        low[0]  = point.x.to_f if point.x.to_f < low[0]
        low[1]  = point.y.to_f if point.y.to_f < low[1]
        low[2]  = point.z.to_f if point.z.to_f < low[2]
        high[0] = point.x.to_f if point.x.to_f > high[0]
        high[1] = point.y.to_f if point.y.to_f > high[1]
        high[2] = point.z.to_f if point.z.to_f > high[2]
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Finding a Picked Vertex Again
    # -----------------------------------------------------------------------------

    # FUNCTION | Cell of the Find-It-Again Index for a Point
    # ------------------------------------------------------------
    def self.Na__VertexMove__Cell(point)
        [
            (point.x.to_f / NA_VM_CELL).floor,
            (point.y.to_f / NA_VM_CELL).floor,
            (point.z.to_f / NA_VM_CELL).floor
        ]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Index Every Candidate by Root, Depth and World Cell
    # ------------------------------------------------------------
    def self.Na__VertexMove__PositionIndex(scope)
        index = {}

        scope[:candidates].each do |candidate|
            context = candidate[:context]
            cell    = Na__InsertPrimatives.Na__VertexMove__Cell(candidate[:world])
            key     = [context[:root_id], context[:depth]] + cell
            (index[key] ||= []) << candidate
        end

        index
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Candidate Standing at a World Point, or nil
    # ------------------------------------------------------------
    # The neighbouring cells are searched too, so a point a hair either side
    # of a cell boundary is still found.
    # ------------------------------------------------------------
    def self.Na__VertexMove__Nearest(index, root_id, depth, point)
        return nil unless point

        cx, cy, cz = Na__InsertPrimatives.Na__VertexMove__Cell(point)
        best       = nil
        best_gap   = NA_VM_MATCH_TOL

        (-1..1).each do |dx|
            (-1..1).each do |dy|
                (-1..1).each do |dz|
                    list = index[[root_id, depth, cx + dx, cy + dy, cz + dz]]
                    next unless list

                    list.each do |candidate|
                        gap = candidate[:world].distance(point).to_f
                        next if gap > best_gap

                        best     = candidate
                        best_gap = gap
                    end
                end
            end
        end

        best
    end
    # ---------------------------------------------------------------

    # FUNCTION | Carry a Set of Picked Vertices Across to a Fresh Scope
    # ------------------------------------------------------------
    # Tried in order, first answer wins:
    #   1. the same vertex in the same context, if it is still alive;
    #   2. whatever stands where it was, moved by `offset` when a move has
    #      just been made;
    #   3. whatever stands where it was BEFORE the last move — the case an
    #      undo leaves behind once a context has been made unique.
    # Returns a Hash, key => candidate, in the order the picks were made.
    # ------------------------------------------------------------
    def self.Na__VertexMove__Remap(scope, entries, offset = nil, keep_before = false)
        result = {}
        index  = nil

        entries.each do |entry|
            vertex  = entry[:vertex]
            context = entry[:context]
            found   = nil

            found = scope[:by_key][entry[:key]] if vertex && vertex.valid?

            unless found
                index ||= Na__InsertPrimatives.Na__VertexMove__PositionIndex(scope)
                wanted  = offset ? entry[:world] + offset : entry[:world]
                found   = Na__InsertPrimatives.Na__VertexMove__Nearest(index, context[:root_id], context[:depth], wanted)
                found ||= Na__InsertPrimatives.Na__VertexMove__Nearest(index, context[:root_id], context[:depth], entry[:before]) if entry[:before]
            end

            next unless found

            before = keep_before ? entry[:world] : entry[:before]
            result[found[:key]] = before ? found.merge(:before => before) : found
        end

        result
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Gimbal Frame and Centre
    # -----------------------------------------------------------------------------

    # FUNCTION | Scale a Vector by a Number
    # Vector3d#* is the CROSS product in SketchUp, so scaling is spelled out.
    # ------------------------------------------------------------
    def self.Na__VertexMove__Scale(vector, factor)
        f = factor.to_f
        Geom::Vector3d.new(vector.x.to_f * f, vector.y.to_f * f, vector.z.to_f * f)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Three Axes Made Unit and Square to Each Other, Directions Kept
    # ------------------------------------------------------------
    # A scaled instance has unit-less axes and a skewed one has axes that lean;
    # neither may tilt the gimbal. Each axis keeps the way it points, so a
    # mirrored group keeps its own sense of +X, +Y and +Z.
    # ------------------------------------------------------------
    def self.Na__VertexMove__Orthonormal(x_axis, y_axis, z_axis)
        x = x_axis.clone
        return nil unless x.length.to_f > 0.0

        x.normalize!

        y = y_axis - Na__InsertPrimatives.Na__VertexMove__Scale(x, y_axis.dot(x))
        return nil unless y.length.to_f > 0.0

        y.normalize!

        z = z_axis - Na__InsertPrimatives.Na__VertexMove__Scale(x, z_axis.dot(x)) - Na__InsertPrimatives.Na__VertexMove__Scale(y, z_axis.dot(y))
        return nil unless z.length.to_f > 0.0

        z.normalize!
        [x, y, z]
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Axes the Gimbal Points Along
    # ------------------------------------------------------------
    # :drawing — the drawing axes, the frame the plugin's grid snaps in.
    # :local   — the axes of the innermost group every picked vertex shares,
    #            so a rotated window can be stretched along its own width.
    #            Picks spread across unrelated groups have no such group; the
    #            open group then stands in, and at the model root the drawing
    #            axes do, and the label says so.
    # ------------------------------------------------------------
    def self.Na__VertexMove__Frame(model, scope, entries, mode)
        drawing = {
            :axes  => Na__InsertPrimatives.Na__DrawnGrid__AxisVectors,
            :label => 'drawing',
            :local => false
        }
        return drawing unless mode == :local

        common = nil
        (entries || []).each do |entry|
            nested = entry[:context][:nested]
            common = common.nil? ? nested.dup : common.take_while.with_index { |instance, i| nested[i] == instance }
            break if common.empty?
        end

        transformation = nil
        name           = nil

        if common && !common.empty?
            context = scope ? scope[:contexts_by_key][common.map(&:entityID).join('/')] : nil
            if context
                transformation = context[:transformation]
                name           = Na__InsertPrimatives.Na__VertexMove__InstanceName(common.last)
            end
        elsif scope && !scope[:open_path].empty? && model.respond_to?(:edit_transform)
            transformation = model.edit_transform
            name           = Na__InsertPrimatives.Na__VertexMove__InstanceName(scope[:open_path].last)
        end

        return drawing.merge(:label => 'drawing (no shared group)') unless transformation

        axes = Na__InsertPrimatives.Na__VertexMove__Orthonormal(transformation.xaxis, transformation.yaxis, transformation.zaxis)
        return drawing.merge(:label => 'drawing (no shared group)') unless axes

        { :axes => axes, :label => name, :local => true }
    rescue StandardError
        { :axes => Na__InsertPrimatives.Na__DrawnGrid__AxisVectors, :label => 'drawing', :local => false }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Centre of a Set of World Points, Measured Along the Frame
    # ------------------------------------------------------------
    # The middle of their box in the gimbal's own axes, so a stretch handle
    # sits in the middle of the face being stretched whatever way it faces.
    # ------------------------------------------------------------
    def self.Na__VertexMove__Centre(points, axes)
        return nil if points.nil? || points.empty?

        low  = [Float::INFINITY] * 3
        high = [-Float::INFINITY] * 3

        points.each do |point|
            axes.each_with_index do |axis, i|
                along   = (point.x.to_f * axis.x.to_f) + (point.y.to_f * axis.y.to_f) + (point.z.to_f * axis.z.to_f)
                low[i]  = along if along < low[i]
                high[i] = along if along > high[i]
            end
        end

        middle = (0..2).map { |i| (low[i] + high[i]) * 0.5 }

        Geom::Point3d.new(
            (0..2).sum { |i| axes[i].x.to_f * middle[i] },
            (0..2).sum { |i| axes[i].y.to_f * middle[i] },
            (0..2).sum { |i| axes[i].z.to_f * middle[i] }
        )
    end
    # ---------------------------------------------------------------

    # FUNCTION | A World Vector as Components Along the Frame
    # ------------------------------------------------------------
    def self.Na__VertexMove__Components(vector, axes)
        axes.map { |axis| vector.dot(axis).to_f }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Components Along the Frame Back to a World Vector
    # ------------------------------------------------------------
    def self.Na__VertexMove__FromComponents(values, axes)
        Geom::Vector3d.new(
            (0..2).sum { |i| axes[i].x.to_f * values[i].to_f },
            (0..2).sum { |i| axes[i].y.to_f * values[i].to_f },
            (0..2).sum { |i| axes[i].z.to_f * values[i].to_f }
        )
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP VERTEX MOVE SCOPE MODULE
# =============================================================================
