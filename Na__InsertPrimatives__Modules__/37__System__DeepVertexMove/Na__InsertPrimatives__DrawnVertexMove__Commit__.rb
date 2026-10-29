# =============================================================================
# NA INSERT PRIMATIVES - DEEP VERTEX MOVE - COMMIT
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnVertexMove__Commit__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Move a set of picked vertices by one world offset, wherever in
#              the nesting each of them lives
# CREATED    : 2026
#
# DESCRIPTION:
# - The picks are grouped by the entities collection that owns them, and each
#   collection is OPENED through Na__DeepPick__ExecuteInContext before it is
#   touched: editing a definition from outside its context is the stale
#   display saga the push tool was cured of in 5.0, and every deep edit in
#   this plugin goes in through the front door since.
# - Inside an opened context positions read global and a vector given to it
#   is taken as global (the 5.1.2 rule), so the move is the world offset as it
#   stands. Where SketchUp will not open the context, the fallback edits it
#   from outside, the offset brought into the definition's own space through
#   the inverse of its world transformation — the identity for geometry loose
#   in the user's own open context.
# - The vertices are found again INSIDE the open context by where they stand
#   in the world. Opening a group can hand back a fresh definition (a copy
#   made unique), and the objects picked a moment ago would then belong to
#   the copies left behind. Position is the one thing that cannot lie.
# - The move itself is Na__SlopePush__MoveVertices: transform_by_vectors with
#   a witness vertex measured and one correction, already proven by slope
#   push. Nothing here takes a move on trust either.
#
# FACES THAT WOULD BEND:
# - A face is flat or it is not a face. Move one corner of a box's top and
#   the top can no longer lie in one plane. Before the move, every face that
#   would bend is folded along its own triangulation, the fold lines soft
#   and smooth, so it stays whole and reads as the one surface it was.
#   Faces that only stretch — the sides of a box whose end is pulled — stay
#   flat and are left exactly as they are.
#
# WELDED CURVES (5.2.18):
# - A vertex of an arc, circle or welded run moved on its own makes SketchUp
#   re-fit the whole curve round it, so the curve warps. Every curve touching
#   a moving vertex is exploded first and welded back after the move
#   (04__GeometryHelpers/..CurveUnweld__.rb); an arc comes back as a curve.
#
# UNDO:
# - One undo step per collection opened, which for a pick inside one group
#   (the usual case) is one. ExecuteInContext chains the open, the edit and
#   the close into that one step.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnDeepPick__'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnDeepPick__Context__'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnSlopePush__'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__CurveUnweld__'
require_relative 'Na__InsertPrimatives__DrawnVertexMove__Scope__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Commit Constants
    # -----------------------------------------------------------------------------

    NA_VM_OPERATION   = 'Deep Vertex Move'.freeze
    NA_VM_MIN_MOVE    = 0.0005                                                # <-- Inches; slope push's own floor for a move worth making
    NA_VM_PLANAR_TOL  = 0.001                                                 # <-- Inches; a corner further than this off the plane bends the face

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | The Move
    # -----------------------------------------------------------------------------

    # FUNCTION | Move Every Picked Vertex by One World Offset
    # ------------------------------------------------------------
    # `entries` are candidates from Na__VertexMove__CollectScope. `roots` are
    # the scope's own items, used to walk the scope again if a context has
    # gone stale under an earlier batch. Returns a tally:
    #   :success, :moved, :missed, :folded, :ops, :entered, :errors
    # ------------------------------------------------------------
    def self.Na__VertexMove__Apply(model, roots, entries, offset)
        tally = { :success => false, :moved => 0, :missed => 0, :folded => 0, :welded => 0, :ops => 0, :entered => 0, :errors => [] }

        if entries.nil? || entries.empty?
            tally[:errors] << 'nothing picked to move'
            return tally
        end

        if offset.nil? || offset.length.to_f < NA_VM_MIN_MOVE
            tally[:errors] << 'the move is zero'
            return tally
        end

        batches = {}
        entries.each { |entry| (batches[entry[:context][:key]] ||= []) << entry }

        batches.each_value do |batch|
            batch = Na__InsertPrimatives.Na__VertexMove__FreshBatch(model, roots, batch)

            if batch.empty?
                tally[:errors] << 'a group changed under the pick and its vertices could not be found again'
                next
            end

            Na__InsertPrimatives.Na__VertexMove__ApplyBatch(model, batch, offset, tally)
        end

        tally[:success] = tally[:moved] > 0
        tally
    end
    # ---------------------------------------------------------------

    # FUNCTION | Open One Collection and Move Its Share of the Picks
    # ------------------------------------------------------------
    def self.Na__VertexMove__ApplyBatch(model, batch, offset, tally)
        context = batch.first[:context]
        found   = 0

        result = Na__InsertPrimatives.Na__DeepPick__ExecuteInContext(model, context[:path], NA_VM_OPERATION) do |entered|
            if entered
                entities = model.active_entities
                vertices = Na__InsertPrimatives.Na__VertexMove__FindInOpen(entities, batch)
                vector   = offset
            else
                entities = context[:entities]
                vertices = batch.map { |entry| entry[:vertex] }.select { |vertex| vertex && vertex.valid? }.uniq
                vector   = Na__InsertPrimatives.Na__VertexMove__ContextVector(context, offset)
            end

            raise 'the picked vertices could not be found in their group' if vertices.empty?

            chains = Na__InsertPrimatives.Na__CurveUnweld__Explode(vertices)          # <-- A welded curve would be re-fitted round the move (CurveUnweld)
            tally[:folded] += Na__InsertPrimatives.Na__VertexMove__FoldBending(entities, vertices, vector)

            unless Na__InsertPrimatives.Na__SlopePush__MoveVertices(entities, nil, vertices, vector)
                raise 'SketchUp would not move the vertices'
            end

            tally[:welded] += Na__InsertPrimatives.Na__CurveUnweld__Reweld(entities, chains)
            found = vertices.length
        end

        if result[:success]
            tally[:ops]     += 1
            tally[:entered] += 1 if result[:entered]
            tally[:moved]   += found
            tally[:missed]  += batch.length - found if batch.length > found
        else
            tally[:errors] << result[:error].to_s
        end

        result[:success]
    end
    # ---------------------------------------------------------------

    # FUNCTION | A World Offset in the Space a Closed Context Reads
    # ------------------------------------------------------------
    # Two points through the inverse rather than the bare vector, as the push
    # tool does it: a direction is a difference of positions, and that cannot
    # be caught out by how a translation applies to a vector. Through a scaled
    # instance the local vector comes out longer or shorter by the scale,
    # which is exactly what lands the vertex the right WORLD distance away.
    # ------------------------------------------------------------
    def self.Na__VertexMove__ContextVector(context, offset)
        return offset if context[:open]

        inverse = context[:transformation].inverse
        origin  = Geom::Point3d.new(0, 0, 0)

        (origin + offset).transform(inverse) - origin.transform(inverse)
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Finding the Picks Again
    # -----------------------------------------------------------------------------

    # FUNCTION | Is a Context Still the Same Place It Was When It Was Walked?
    # ------------------------------------------------------------
    # Every instance on the path alive, each sitting in the definition of the
    # one above it, and the collection the walk saw still the innermost one's.
    # A batch before this one can make a group unique and replace everything
    # below it; this is how that is noticed rather than edited blind.
    # ------------------------------------------------------------
    def self.Na__VertexMove__ContextCurrent?(context)
        return true if context[:open]

        nested = context[:nested]
        return false if nested.empty?

        nested.each_with_index do |instance, index|
            return false unless instance && instance.valid?
            next if index.zero?

            return false unless instance.parent == nested[index - 1].definition
        end

        context[:entities].parent == nested.last.definition
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Batch As It Stands Now — Re-Walked If Its Context Went Stale
    # ------------------------------------------------------------
    def self.Na__VertexMove__FreshBatch(model, roots, batch)
        return batch if Na__InsertPrimatives.Na__VertexMove__ContextCurrent?(batch.first[:context])

        scope = Na__InsertPrimatives.Na__VertexMove__CollectScope(model, roots)
        Na__InsertPrimatives.Na__VertexMove__Remap(scope, batch).values
    rescue StandardError
        []
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Picked Vertices Inside the Context Now Open, by Position
    # ------------------------------------------------------------
    # Fast when the vertices picked are the ones standing here; otherwise
    # every vertex of the open collection is indexed by its world position
    # (the collection reports global while it is open) and each pick is
    # looked up where it was.
    # ------------------------------------------------------------
    def self.Na__VertexMove__FindInOpen(entities, batch)
        owner  = entities.parent
        direct = batch.map { |entry| entry[:vertex] }

        if direct.all? { |vertex| Na__InsertPrimatives.Na__VertexMove__VertexIn?(vertex, owner) }
            return direct.uniq
        end

        index = {}
        entities.grep(Sketchup::Edge).each do |edge|
            edge.vertices.each do |vertex|
                cell = Na__InsertPrimatives.Na__VertexMove__Cell(vertex.position)
                list = (index[cell] ||= [])
                list << vertex unless list.include?(vertex)
            end
        end

        batch.map { |entry| Na__InsertPrimatives.Na__VertexMove__VertexNear(index, entry[:world]) }.compact.uniq
    end
    # ---------------------------------------------------------------

    # FUNCTION | Does This Vertex Belong to the Collection Owned by `owner`?
    # ------------------------------------------------------------
    def self.Na__VertexMove__VertexIn?(vertex, owner)
        return false unless vertex && vertex.valid?

        edge = vertex.edges.first
        edge ? edge.parent == owner : false
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Vertex Standing at a Point, From a Cell Index, or nil
    # ------------------------------------------------------------
    def self.Na__VertexMove__VertexNear(index, point)
        cx, cy, cz = Na__InsertPrimatives.Na__VertexMove__Cell(point)
        best       = nil
        best_gap   = NA_VM_MATCH_TOL

        (-1..1).each do |dx|
            (-1..1).each do |dy|
                (-1..1).each do |dz|
                    list = index[[cx + dx, cy + dy, cz + dz]]
                    next unless list

                    list.each do |vertex|
                        gap = vertex.position.distance(point).to_f
                        next if gap > best_gap

                        best     = vertex
                        best_gap = gap
                    end
                end
            end
        end

        best
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Keeping Every Face Flat
    # -----------------------------------------------------------------------------

    # FUNCTION | Fold Every Face the Move Would Bend
    # ------------------------------------------------------------
    # `vector` is in the space the collection reports, the same space the
    # positions are read in, so the test needs no conversion. Returns how many
    # fold lines were added.
    # ------------------------------------------------------------
    def self.Na__VertexMove__FoldBending(entities, vertices, vector)
        moving = {}
        vertices.each { |vertex| moving[vertex] = true }

        faces = {}
        vertices.each { |vertex| vertex.faces.each { |face| faces[face] = true } }

        folded = 0
        faces.each_key do |face|
            next unless face.valid?

            corners = face.vertices
            next if corners.all? { |vertex| moving[vertex] }                  # <-- Carried whole: a translation never bends anything

            landed = corners.map { |vertex| moving[vertex] ? vertex.position + vector : vertex.position }
            next if Na__InsertPrimatives.Na__VertexMove__Flat?(landed)

            folded += Na__InsertPrimatives.Na__VertexMove__Fold(entities, face)
        end

        folded
    end
    # ---------------------------------------------------------------

    # FUNCTION | Do These Points Still Lie in One Plane?
    # ------------------------------------------------------------
    def self.Na__VertexMove__Flat?(points)
        return true if points.length <= 3

        plane = Geom.fit_plane_to_points(points)
        return true unless plane                                              # <-- Degenerate: leave it to SketchUp

        points.all? { |point| point.distance_to_plane(plane).to_f <= NA_VM_PLANAR_TOL }
    rescue StandardError
        true
    end
    # ---------------------------------------------------------------

    # FUNCTION | Fold One Face Along Its Own Triangulation
    # ------------------------------------------------------------
    # The face's PolygonMesh is SketchUp's own triangulation of it, holes and
    # concave outlines included. Every triangle side that is not already an
    # edge is a diagonal across the face, and drawing it splits the face
    # there. Diagonals are soft and smooth, so the folded face still reads as
    # one surface; turn on Hidden Geometry to see them.
    # ------------------------------------------------------------
    def self.Na__VertexMove__Fold(entities, face)
        by_cell = {}
        face.vertices.each { |vertex| by_cell[Na__InsertPrimatives.Na__VertexMove__Cell(vertex.position)] = vertex }

        mesh  = face.mesh
        added = 0

        mesh.polygons.each do |polygon|
            corners = polygon.map do |index|
                point = mesh.point_at(index.abs)
                by_cell[Na__InsertPrimatives.Na__VertexMove__Cell(point)] ||
                    Na__InsertPrimatives.Na__VertexMove__VertexNear(Na__InsertPrimatives.Na__VertexMove__CellIndex(face), point)
            end
            next if corners.include?(nil)

            corners.each_with_index do |vertex, index|
                other = corners[(index + 1) % corners.length]
                next if vertex == other
                next if vertex.common_edge(other)

                edge = entities.add_line(vertex.position, other.position)
                next unless edge

                edge.soft   = true
                edge.smooth = true
                added += 1
            end
        end

        added
    rescue StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "NA VERTEX MOVE: could not fold a face — #{error.message}"
        0
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Face's Vertices in a Cell Index, for the Near-Miss Lookup
    # ------------------------------------------------------------
    def self.Na__VertexMove__CellIndex(face)
        index = {}
        face.vertices.each do |vertex|
            (index[Na__InsertPrimatives.Na__VertexMove__Cell(vertex.position)] ||= []) << vertex
        end
        index
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP VERTEX MOVE COMMIT MODULE
# =============================================================================
