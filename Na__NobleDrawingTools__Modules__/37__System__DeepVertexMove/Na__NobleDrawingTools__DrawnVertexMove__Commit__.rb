# =============================================================================
# NA NOBLE DRAWING TOOLS - DEEP VERTEX MOVE - COMMIT
# =============================================================================
#
# FILE       : Na__NobleDrawingTools__DrawnVertexMove__Commit__.rb
# NAMESPACE  : Na__NobleDrawingTools
# AUTHOR     : Noble Architecture
# PURPOSE    : Move a set of picked vertices by one world offset, wherever in
#              the nesting each of them lives
# CREATED    : 2026
#
# DESCRIPTION:
# - Every collection a move touches is OPENED before it is touched: editing a
#   definition from outside its context is the stale display saga the push
#   tool was cured of in 5.0, and every deep edit in this plugin goes in
#   through the front door since.
# - Inside an opened context positions read global and a vector given to it
#   is taken as global (the 5.1.2 rule), so the move is the world offset as
#   it stands.
# - The vertices are found again INSIDE the open context by where they stand
#   in the world. Making a copy unique, or opening a group, hands back fresh
#   vertex objects, and the ones picked a moment ago then belong to the
#   copies left behind. Position is the one thing that cannot lie.
# - The move itself is Na__SlopePush__MoveVertices: transform_by_vectors with
#   a witness vertex measured and one correction, already proven by slope
#   push. Nothing here takes a move on trust either.
#
# SHARED COMPONENTS (5.2.43, 04__GeometryHelpers/..DrawnDeepUnique__.rb):
# - Until 5.2.43 the picks were batched by PATH, so thirty balusters (thirty
#   copies of one component) were thirty batches into one definition: the
#   same vertices moved thirty times, each batch its own undo step, and every
#   copy in the model moved with them, picked or not.
# - Now the move is planned first. Each path down to a pick is a node, signed
#   with what the move does to its definition in that definition's own axes
#   (which vertices, and the offset as it reads there). Copies picked alike
#   share one definition and are moved ONCE, through one of them; copies the
#   picks do not reach, anywhere in the model, keep the definition they had
#   (make_unique on the first picked copy, definition= on the rest). Copies
#   picked differently, or turned so the offset reads differently, part.
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
# - ONE undo step for the whole move, however many copies and contexts. The
#   user's own context goes first (its loose picks, and the copies standing
#   in it settled onto their definitions), next_transparent when a context
#   is to be opened; every opened context's edit joins the entry just made
#   and pulls in the next; the last pulls in the return to the user's
#   context. tally[:ops] says 1, which is what a retype undoes.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../04__GeometryHelpers/Na__NobleDrawingTools__DrawnDeepPick__'
require_relative '../04__GeometryHelpers/Na__NobleDrawingTools__DrawnDeepPick__Context__'
require_relative '../04__GeometryHelpers/Na__NobleDrawingTools__DrawnDeepPick__Focus__'
require_relative '../04__GeometryHelpers/Na__NobleDrawingTools__DrawnDeepUnique__'
require_relative '../04__GeometryHelpers/Na__NobleDrawingTools__DrawnSlopePush__'
require_relative '../04__GeometryHelpers/Na__NobleDrawingTools__CurveUnweld__'
require_relative 'Na__NobleDrawingTools__DrawnVertexMove__Scope__'

module Na__NobleDrawingTools

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
    # the scope's own items, used to walk the scope again if the picks have
    # gone stale. Returns a tally:
    #   :success, :moved, :missed, :folded, :welded, :ops, :entered, :errors,
    #   :copies  copies that moved through another copy's one edit
    #   :made    new definitions made to keep copies elsewhere as they were
    #   :shared  the words for the status line (Na__DeepUnique__Report)
    # ------------------------------------------------------------
    def self.Na__VertexMove__Apply(model, roots, entries, offset)
        tally = {
            :success => false, :moved => 0, :missed => 0, :folded => 0, :welded => 0, :ops => 0, :entered => 0,
            :errors  => [], :copies => 0, :made => 0, :shared => ''
        }

        if entries.nil? || entries.empty?
            tally[:errors] << 'nothing picked to move'
            return tally
        end

        if offset.nil? || offset.length.to_f < NA_VM_MIN_MOVE
            tally[:errors] << 'the move is zero'
            return tally
        end

        entries = Na__NobleDrawingTools.Na__VertexMove__FreshEntries(model, roots, entries)

        if entries.empty?
            tally[:errors] << 'a group changed under the pick and its vertices could not be found again'
            return tally
        end

        plan = Na__NobleDrawingTools.Na__VertexMove__Plan(model, entries, offset)

        if plan[:refused]
            tally[:errors] << plan[:refused]
            return tally
        end

        previous = model.active_path
        nested   = !plan[:roots].empty?
        selected = nested ? Na__NobleDrawingTools.Na__DeepPick__FocusSnapshot(model) : []   # <-- Opening a context clears this
        queue    = []

        # 1. The user's own context: its loose picks move, and the copies
        #    standing in it are settled onto their definitions while closed.
        #    No operation when neither changes anything: the first opened
        #    context then starts the step.
        if !plan[:loose].empty? || Na__NobleDrawingTools.Na__DeepUnique__NeedsSettle?(plan, plan[:roots])
            model.start_operation(NA_VM_OPERATION, true, nested, false)    # <-- next_transparent: the first context entry joins this step

            begin
                unless plan[:loose].empty?
                    found, total = Na__NobleDrawingTools.Na__VertexMove__MoveHere(model.active_entities, plan[:loose], offset, tally)
                    tally[:moved]  += found
                    tally[:missed] += total - found
                end

                queue = Na__NobleDrawingTools.Na__DeepUnique__SettleIn(plan, plan[:roots], model.active_entities)
                model.commit_operation
            rescue StandardError => error
                model.abort_operation                                       # <-- Not transparent, and ours: nothing is left half done
                tally[:errors] << error.message
                return tally
            end

            pending = nested
        else
            begin
                queue = Na__NobleDrawingTools.Na__DeepUnique__SettleIn(plan, plan[:roots], model.active_entities)
            rescue StandardError => error
                tally[:errors] << error.message
                return tally
            end

            pending = false
        end

        # 2. One copy of each final definition, opened in turn.
        failed = nil
        pending, failed = Na__NobleDrawingTools.Na__VertexMove__Walk(model, plan, queue, previous, offset, tally, pending) if nested

        # 3. The user's context put back: the last edit pulls it in.
        restored = Na__NobleDrawingTools.Na__DeepUnique__Restore(model, previous)
        Na__NobleDrawingTools.Na__DeepUnique__ClosePending(model, NA_VM_OPERATION) if pending && !restored
        Na__NobleDrawingTools.Na__DeepPick__FocusRestore(model, selected) if nested

        Na__NobleDrawingTools.Na__VertexMove__CountCopies(plan, tally)
        tally[:errors] << failed if failed
        tally[:errors] << 'the picked vertices could not be found in their group' if tally[:moved].zero? && tally[:missed] > 0 && tally[:errors].empty?
        tally[:ops]     = 1
        tally[:made]    = plan[:made]
        tally[:shared]  = Na__NobleDrawingTools.Na__DeepUnique__Report(plan)
        tally[:success] = tally[:moved] > 0
        tally
    end
    # ---------------------------------------------------------------

    # FUNCTION | Open One Copy of Each Final Definition and Move Its Picks
    # ------------------------------------------------------------
    # Each node in the queue is a representative: the first copy of its
    # final definition. Opened, its own picks are moved, the copies inside it
    # are settled while still closed, and the representatives among them
    # join the queue. A node with nothing of its own to move and nothing
    # inside it to settle is not opened at all: its parts are found where
    # they stand. Returns [pending, failed].
    # ------------------------------------------------------------
    def self.Na__VertexMove__Walk(model, plan, queue, previous, offset, tally, pending)
        base   = Array(previous)
        failed = nil

        until queue.empty?
            node = queue.shift
            own  = node[:payload][:entries]

            if own.empty? && !Na__NobleDrawingTools.Na__DeepUnique__NeedsSettle?(plan, node[:children])
                begin
                    queue.unshift(*Na__NobleDrawingTools.Na__DeepUnique__SettleIn(plan, node[:children], node[:live].definition.entities))
                rescue StandardError => error
                    failed = error.message
                    break
                end

                next
            end

            path = base + Na__NobleDrawingTools.Na__DeepUnique__LivePath(node)

            unless Na__NobleDrawingTools.Na__DeepUnique__Enter(model, path)
                failed = "#{Na__NobleDrawingTools.Na__DeepUnique__Name(node[:live])} would not open for editing — the move stopped there; Ctrl+Z takes back what was done"
                break
            end

            tally[:entered] += 1
            pending          = false
            model.start_operation(NA_VM_OPERATION, true, true, true)          # <-- Joins the entry just made, pulls in the next

            begin
                unless own.empty?
                    found, total = Na__NobleDrawingTools.Na__VertexMove__MoveHere(model.active_entities, own, offset, tally)
                    node[:payload][:found] = found
                    node[:payload][:total] = total
                end

                queue.concat(Na__NobleDrawingTools.Na__DeepUnique__SettleIn(plan, node[:children], model.active_entities))
            rescue StandardError => error
                failed = "#{error.message} — the move stopped there; Ctrl+Z takes back what was done"
            end

            model.commit_operation                                            # <-- Never abort a transparent operation (ruby.sketchup.com): what stands is kept, and said
            pending = true
            break if failed
        end

        [pending, failed]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Move the Picks Standing in the Open Context; Returns [found, total]
    # ------------------------------------------------------------
    # The collection is open, so its positions read world and it takes the
    # world offset as it stands.
    # ------------------------------------------------------------
    def self.Na__VertexMove__MoveHere(entities, entries, offset, tally)
        vertices = Na__NobleDrawingTools.Na__VertexMove__FindInOpen(entities, entries)
        return [0, entries.length] if vertices.empty?

        chains = Na__NobleDrawingTools.Na__CurveUnweld__Explode(vertices)        # <-- A welded curve would be re-fitted round the move (CurveUnweld)
        tally[:folded] += Na__NobleDrawingTools.Na__VertexMove__FoldBending(entities, vertices, offset)

        unless Na__NobleDrawingTools.Na__SlopePush__MoveVertices(entities, nil, vertices, offset)
            raise 'SketchUp would not move the vertices'
        end

        tally[:welded] += Na__NobleDrawingTools.Na__CurveUnweld__Reweld(entities, chains)
        [vertices.length, entries.length]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Count the Picks Moved, Copies That Rode Along Included
    # ------------------------------------------------------------
    # Each representative moved its picks once, and every copy riding on its
    # definition moved the same picks with it, so its count is multiplied by
    # its copies. Counted after the walk: copies met later still join.
    # ------------------------------------------------------------
    def self.Na__VertexMove__CountCopies(plan, tally)
        plan[:finals].each_value do |node|
            total = node[:payload][:total]
            next unless total

            copies          = Na__NobleDrawingTools.Na__DeepUnique__CopiesOf(plan, node)
            tally[:moved]  += node[:payload][:found] * copies
            tally[:missed] += (total - node[:payload][:found]) * copies
            tally[:copies] += copies - 1
        end
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Planning the Move
    # -----------------------------------------------------------------------------

    # FUNCTION | The Move on Paper: One Node per Path Down to a Pick
    # ------------------------------------------------------------
    # A pick loose in the user's own context goes to plan[:loose]. Every other
    # pick hangs on the node at the end of its path, and every instance on
    # the way down is a node too: a container is settled before what is in
    # it. A node's world is the product of the transformations down the
    # path, the first read in the open context (world), the rest local to
    # their parents: the scope's own rule (Scope header).
    # ------------------------------------------------------------
    def self.Na__VertexMove__Plan(model, entries, offset)
        plan         = Na__NobleDrawingTools.Na__DeepUnique__NewPlan(model)
        plan[:loose] = []
        nodes        = {}

        entries.each do |entry|
            context = entry[:context]

            if context[:open] || context[:nested].empty?
                plan[:loose] << entry
                next
            end

            parent = nil
            key    = nil

            context[:nested].each do |instance|
                key  = key ? "#{key}/#{instance.entityID}" : instance.entityID.to_s
                node = nodes[key]

                unless node
                    world      = parent ? parent[:world] * instance.transformation : instance.transformation
                    node       = Na__NobleDrawingTools.Na__DeepUnique__AddNode(plan, instance, parent, world, { :entries => [], :key => key })
                    nodes[key] = node
                end

                parent = node
            end

            parent[:payload][:entries] << entry
        end

        plan[:roots].each { |node| Na__NobleDrawingTools.Na__VertexMove__Sign(node, offset) }
        Na__NobleDrawingTools.Na__DeepUnique__Decide(plan)
    end
    # ---------------------------------------------------------------

    # FUNCTION | What the Move Does to a Node's Definition, Down Through It
    # ------------------------------------------------------------
    # The vertices picked through this copy, the offset as it reads in the
    # copy's own axes (a copy turned or mirrored reads it differently, so it
    # cannot share), and the same for every node below. Vertex objects are
    # one set per definition, so their ids compare across copies.
    # ------------------------------------------------------------
    def self.Na__VertexMove__Sign(node, offset)
        node[:children].each { |child| Na__NobleDrawingTools.Na__VertexMove__Sign(child, offset) }

        picked = node[:payload][:entries].map { |entry| entry[:vertex].entityID }.uniq.sort
        move   = picked.empty? ? nil : Na__NobleDrawingTools.Na__DeepUnique__Quantise(Na__NobleDrawingTools.Na__DeepUnique__LocalVector(node[:world], offset))
        below  = node[:children].map { |child| [child[:instance].entityID, child[:signature]] }.sort_by(&:first)

        node[:signature] = [move, picked, below]
    end
    # ---------------------------------------------------------------

    # FUNCTION | What Moving These Picks Would Do to Shared Copies, Said Before It Is Done
    # ------------------------------------------------------------
    # For the status line while picking: of the definition picked through
    # the most copies, how many copies the picks reach against how many the
    # model holds. "" when nothing picked is shared.
    # ------------------------------------------------------------
    def self.Na__VertexMove__CopiesNote(model, entries)
        counts = Hash.new(0)
        seen   = {}

        (entries || []).each do |entry|
            context = entry[:context]
            next if context[:open] || context[:nested].empty?
            next if seen[context[:key]]

            seen[context[:key]] = true
            counts[context[:nested].last.definition] += 1
        end

        return '' if counts.empty?

        plan        = Na__NobleDrawingTools.Na__DeepUnique__NewPlan(model)
        mult        = Na__NobleDrawingTools.Na__DeepUnique__ContextOccurrences(plan)
        definition  = counts.max_by { |_definition, count| count }.first
        picked      = counts[definition] * mult
        total       = Na__NobleDrawingTools.Na__DeepUnique__Occurrences(definition, plan[:memo])
        name        = Na__NobleDrawingTools.Na__DeepUnique__Name(definition)

        return " — #{picked} of #{total} copies of #{name} picked: only those move, as one" if total > picked
        return " — #{picked} copies of #{name}, moved as one" if picked > 1

        ''
    rescue StandardError
        ''
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
    # An undo, or a move that made a copy unique, can replace everything
    # below a container; this is how that is noticed rather than edited blind.
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

    # FUNCTION | The Picks As They Stand Now — Re-Walked If Any Went Stale
    # ------------------------------------------------------------
    # A pick is stale when its vertex is gone, has left the collection it was
    # picked in, or its path no longer chains. Then the whole scope is walked
    # again and every pick found where it stood.
    # ------------------------------------------------------------
    def self.Na__VertexMove__FreshEntries(model, roots, entries)
        stale = entries.any? do |entry|
            context = entry[:context]
            vertex  = entry[:vertex]

            !Na__NobleDrawingTools.Na__VertexMove__ContextCurrent?(context) ||
                !(context[:open] ? (vertex && vertex.valid?) : Na__NobleDrawingTools.Na__VertexMove__VertexIn?(vertex, context[:entities].parent))
        end
        return entries unless stale

        scope = Na__NobleDrawingTools.Na__VertexMove__CollectScope(model, roots)
        Na__NobleDrawingTools.Na__VertexMove__Remap(scope, entries).values
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

        if direct.all? { |vertex| Na__NobleDrawingTools.Na__VertexMove__VertexIn?(vertex, owner) }
            return direct.uniq
        end

        index = {}
        entities.grep(Sketchup::Edge).each do |edge|
            edge.vertices.each do |vertex|
                cell = Na__NobleDrawingTools.Na__VertexMove__Cell(vertex.position)
                list = (index[cell] ||= [])
                list << vertex unless list.include?(vertex)
            end
        end

        batch.map { |entry| Na__NobleDrawingTools.Na__VertexMove__VertexNear(index, entry[:world]) }.compact.uniq
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
        cx, cy, cz = Na__NobleDrawingTools.Na__VertexMove__Cell(point)
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
            next if Na__NobleDrawingTools.Na__VertexMove__Flat?(landed)

            folded += Na__NobleDrawingTools.Na__VertexMove__Fold(entities, face)
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
        face.vertices.each { |vertex| by_cell[Na__NobleDrawingTools.Na__VertexMove__Cell(vertex.position)] = vertex }

        mesh  = face.mesh
        added = 0

        mesh.polygons.each do |polygon|
            corners = polygon.map do |index|
                point = mesh.point_at(index.abs)
                by_cell[Na__NobleDrawingTools.Na__VertexMove__Cell(point)] ||
                    Na__NobleDrawingTools.Na__VertexMove__VertexNear(Na__NobleDrawingTools.Na__VertexMove__CellIndex(face), point)
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
        Na__NobleDrawingTools.Na__Debug__Puts "NA VERTEX MOVE: could not fold a face — #{error.message}"
        0
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Face's Vertices in a Cell Index, for the Near-Miss Lookup
    # ------------------------------------------------------------
    def self.Na__VertexMove__CellIndex(face)
        index = {}
        face.vertices.each do |vertex|
            (index[Na__NobleDrawingTools.Na__VertexMove__Cell(vertex.position)] ||= []) << vertex
        end
        index
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__NobleDrawingTools module

# =============================================================================
# END OF DEEP VERTEX MOVE COMMIT MODULE
# =============================================================================
