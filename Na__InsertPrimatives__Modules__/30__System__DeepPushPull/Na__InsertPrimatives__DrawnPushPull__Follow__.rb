# =============================================================================
# NA INSERT PRIMATIVES - DEEP PUSH PULL FOLLOW (SHIFT+ALT)
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnPushPull__Follow__.rb
# NAMESPACE  : Na__InsertPrimatives / Na__InsertPrimatives::DrawnPushPullFollow
# AUTHOR     : Noble Architecture
# PURPOSE    : Push/pull where every corner of the face runs along its OWN edge,
#              so the faces round it keep their planes and a taper stays a taper
# CREATED    : 2026
#
# DESCRIPTION:
# - A plain push carries the whole face along its normal. SHIFT carries the
#   whole face along ONE neighbour's slope. Neither is right for the front of a
#   tapered slab: its top edge wants to run up the roof, its bottom edge along
#   the soffit, and its ends along the end faces, all at once.
# - SHIFT+ALT is that: FOLLOW mode, Fredo's "Follow Push Pull". Every corner of
#   the face slides along its RAIL, the line where the two faces either side of
#   that corner meet (on a solid, simply the edge running back from it). Each
#   corner travels however far it has to along its own rail for the face to land
#   on a plane parallel to where it started, the drag distance away. So:
#     the face stays flat          (every corner on one offset plane)
#     every neighbour stays flat   (its corners only move within its own plane)
#     nothing new is made          (the solid is stretched or shortened in place)
# - With QUADS on, dragging INTO the material is a FOLLOW LOOP CUT: the ring is
#   the offset face's outline, each corner on its rail, stitched into the faces
#   round it, so on the tapered slab the line runs up the roof, down the end and
#   along the soffit exactly as marked up. Dragging OUT with QUADS on stretches
#   and puts the start loop back as a quad line, as every quad push does.
#
# LIMITS, SAID NOT SILENT:
# - A corner cannot run past the far end of the edge it follows. Inward, the
#   deepest push is the shortest rail's reach, measured along the normal. It is
#   shown on the card and anything past it is refused. Outward there is no
#   limit. A corner with no single line to follow (an open edge, or neighbours
#   that do not meet in a line), or a rail running along the face itself, makes
#   FOLLOW unavailable on that face, and the status line says which.
#
# ALT, AND WHY IT IS SAFE AS SHIFT+ALT:
# - There is no ALT bit in the mouse flags, so ALT is tracked from key events
#   (see the 0.4.34 - 0.4.36 devlog: a BARE ALT press goes to the Windows menu
#   bar and its key-up can be lost). Pressed with SHIFT it is not bare, so the
#   key-up arrives. Belt and braces: whenever SHIFT is seen to go up, ALT is
#   cleared too, so a lost key-up can never outlive the SHIFT it rode on.
#
# COORDINATES: rails are computed where they are used. The preview reads them
# in world through the pick's transformation; the commit reads them again
# inside its operation, in the space the open context reports.
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__InsertPrimatives__DrawnPushPull__QuadRing__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Follow Constants
    # -----------------------------------------------------------------------------

    NA_FOLLOW_MIN_RAIL_DOT = 0.05                                             # <-- A rail this close to lying IN the face would run away
    NA_FOLLOW_PARALLEL_DOT = 0.9999                                           # <-- An edge this parallel to the rail line IS the rail
    NA_FOLLOW_TOL          = 0.004                                            # <-- Inches (~0.1mm); a corner this near its rail's end is at it
    NA_FOLLOW_ALT_KEY      = defined?(ALT_MODIFIER_KEY) ? ALT_MODIFIER_KEY : 18

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Rails
    # -----------------------------------------------------------------------------

    # FUNCTION | The Rail Every Corner of a Face Runs Along
    # ------------------------------------------------------------
    # Returns { :ok, :reason, :rails } in the space the face REPORTS. Each rail
    # is { :vertex, :point, :dir, :inward }: dir is a unit vector turned so
    # dir . normal > 0 (the outward way along the rail), and inward is how far
    # the rail edge runs back into the material from the corner, or 0 when no
    # edge does. Every loop of the face is included, holes too.
    # ------------------------------------------------------------
    def self.Na__FollowPush__Rails(face)
        return { :ok => false, :reason => 'no face' } unless face && face.valid?

        normal = face.normal
        rails  = []

        face.loops.each do |loop|
            loop.vertices.each do |vertex|
                rail = Na__InsertPrimatives.Na__FollowPush__RailAt(face, normal, vertex)
                return { :ok => false, :reason => rail } if rail.is_a?(String)

                rails << rail
            end
        end

        { :ok => true, :reason => nil, :rails => rails }
    rescue StandardError => error
        { :ok => false, :reason => "the corners could not be read (#{error.message})" }
    end
    # ---------------------------------------------------------------

    # FUNCTION | One Corner's Rail, or a Sentence Saying Why It Has None
    # ------------------------------------------------------------
    # The rail is where the two faces either side of the corner meet: the
    # cross product of their normals. On a solid that is exactly the edge
    # running back from the corner, and asking the planes rather than the
    # edges also covers a corner whose edges are split. Where the two
    # neighbours are one flat surface (a corner on a straight run), the one
    # edge leaving the corner is the rail.
    # ------------------------------------------------------------
    def self.Na__FollowPush__RailAt(face, normal, vertex)
        own = vertex.edges.select { |edge| edge.faces.include?(face) }
        return 'a corner of this face is not a simple corner' unless own.length == 2

        neighbours = own.map do |edge|
            others = edge.faces - [face]
            return 'an edge of this face is open — nothing to follow there' if others.empty?
            return 'an edge of this face is shared by more than two faces' if others.length > 1

            others.first
        end

        direction = neighbours[0].normal.cross(neighbours[1].normal)

        if direction.length < 1.0e-6
            leaving = vertex.edges - own
            return 'a corner of this face has no single edge to follow' unless leaving.length == 1

            direction = leaving.first.other_vertex(vertex).position - vertex.position
            return 'a corner of this face has no single edge to follow' if direction.length <= 0.0
        end

        direction = direction.normalize
        direction = direction.reverse if direction.dot(normal) < 0.0
        return 'an edge this face would follow runs along the face itself' if direction.dot(normal) < NA_FOLLOW_MIN_RAIL_DOT

        {
            :vertex => vertex,
            :point  => vertex.position,
            :dir    => direction,
            :inward => Na__InsertPrimatives.Na__FollowPush__InwardReach(vertex, own, direction)
        }
    end
    # ---------------------------------------------------------------

    # FUNCTION | How Far the Rail Edge Runs Back Into the Material From a Corner
    # Collinear pieces are walked through, so a rail already cut by quad lines
    # still reads its full length.
    # ------------------------------------------------------------
    def self.Na__FollowPush__InwardReach(vertex, own, direction)
        back  = direction.reverse
        at    = vertex
        total = 0.0
        skip  = own
        steps = 0

        while steps < 4096
            edge = (at.edges - skip).find do |candidate|
                heading = candidate.other_vertex(at).position - at.position
                heading.length > 0.0 && heading.normalize.dot(back) > NA_FOLLOW_PARALLEL_DOT
            end
            break unless edge

            total += edge.length.to_f
            at     = edge.other_vertex(at)
            skip   = [edge]
            steps += 1
        end

        total
    rescue StandardError
        0.0
    end
    # ---------------------------------------------------------------

    # FUNCTION | How a Corner Moves for a Push of `distance` Along the Normal
    # The corner lands on the plane `distance` from the face, travelling along
    # its own rail: dir × distance / (dir . normal).
    # ------------------------------------------------------------
    def self.Na__FollowPush__Vector(direction, normal, distance)
        along = direction.dot(normal).to_f
        scale = along.abs < 1.0e-9 ? 0.0 : distance.to_f / along

        Geom::Vector3d.new(direction.x.to_f * scale, direction.y.to_f * scale, direction.z.to_f * scale)
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Same Rails in World, for the Preview
    # ------------------------------------------------------------
    # Returns { :ok, :reason, :rails => [{ :point, :dir, :inward }], :normal,
    # :max_in } where max_in is the deepest INWARD push (along the normal) the
    # rails allow, in world inches, or nil when nothing limits it.
    # ------------------------------------------------------------
    def self.Na__FollowPush__WorldRails(target)
        face  = target && target[:face]
        found = Na__InsertPrimatives.Na__FollowPush__Rails(face)
        return found unless found[:ok]

        xform  = target[:transformation] || Geom::Transformation.new
        normal = target[:world_normal]
        rails  = found[:rails].map do |rail|
            start = rail[:point].transform(xform)
            ahead = rail[:point].offset(rail[:dir]).transform(xform) - start
            dir   = ahead.normalize
            dir   = dir.reverse if dir.dot(normal) < 0.0
            back  = rail[:inward].to_f > 0.0 ?
                        (rail[:point].offset(rail[:dir].reverse, rail[:inward].to_f).transform(xform) - start).length.to_f : 0.0

            { :point => start, :dir => dir, :inward => back }
        end

        limits = rails.map { |rail| rail[:inward] * rail[:dir].dot(normal).to_f }

        { :ok => true, :reason => nil, :rails => rails, :normal => normal, :max_in => limits.min }
    rescue StandardError => error
        { :ok => false, :reason => "the corners could not be read (#{error.message})" }
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Tool Side
    # -----------------------------------------------------------------------------

    module DrawnPushPullFollow

        # -----------------------------------------------------------------------------
        # REGION | ALT, Tracked Beside SHIFT
        # -----------------------------------------------------------------------------

        # ON KEY DOWN | ALT Arms Follow; Everything Else Is the Shared Handler's
        # Swallowed (true) so a bare ALT does not also wake the menu bar.
        # ------------------------------------------------------------
        def onKeyDown(key, repeat, flags, view)
            return super unless key == NA_FOLLOW_ALT_KEY

            unless @na_alt_held
                @na_alt_held = true
                na_drawn__after_follow_key(view)
            end
            true
        end
        # ---------------------------------------------------------------

        # ON KEY UP | ALT Released; SHIFT Released Takes ALT With It
        # ------------------------------------------------------------
        def onKeyUp(key, repeat, flags, view)
            if key == NA_FOLLOW_ALT_KEY
                if @na_alt_held
                    @na_alt_held = false
                    na_drawn__after_follow_key(view)
                end
                return true
            end

            result = super
            @na_alt_held = false unless @na_shift_held
            result
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Mouse Flags Are the Truth About SHIFT, and ALT Rides On It
        # ------------------------------------------------------------
        def na_drawn__sync_modifier(flags)
            changed = super

            if @na_alt_held && !@na_shift_held
                @na_alt_held = false
                changed      = true
            end

            changed
        end
        # ---------------------------------------------------------------

        # FUNCTION | Redraw at Once When ALT Changes
        # ------------------------------------------------------------
        def na_drawn__after_follow_key(view)
            na_drawn__update_cursor(view, @na_last_mouse_x, @na_last_mouse_y)
            @na_last_status_text = nil
            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Is Follow On?
        # -----------------------------------------------------------------------------

        # FUNCTION | SHIFT and ALT Both Down
        # ------------------------------------------------------------
        def na_drawn__follow_requested?
            @na_shift_held && @na_alt_held ? true : false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Requested, and This Face Has a Rail at Every Corner
        # ------------------------------------------------------------
        def na_drawn__follow_mode?
            na_drawn__follow_requested? && @na_pp_follow && @na_pp_follow[:ok] ? true : false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Read This Face's Rails, for the Preview
        # Called whenever the target changes (and by a retype on the face it
        # found again), never per frame.
        # ------------------------------------------------------------
        def na_drawn__follow_refresh(target)
            @na_pp_follow = target && target[:face] ? Na__InsertPrimatives.Na__FollowPush__WorldRails(target) : nil
            @na_pp_follow_lookup = nil
            @na_pp_follow
        end
        # ---------------------------------------------------------------

        # FUNCTION | Why Follow Is Off on This Face, or nil
        # ------------------------------------------------------------
        def na_drawn__follow_reason
            return nil unless na_drawn__follow_requested?
            return 'no face to follow from' unless @na_pp_follow

            @na_pp_follow[:ok] ? nil : @na_pp_follow[:reason]
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Preview
        # -----------------------------------------------------------------------------

        # FUNCTION | Where a World Point of the Face Goes Under the Live Push
        # ------------------------------------------------------------
        # Off follow, the uniform offset every preview always used. On follow,
        # a corner runs along its own rail; a point that is not a corner (a
        # triangulation point inside a concave face) keeps the uniform offset.
        # ------------------------------------------------------------
        def na_drawn__move_world_point(point, offset)
            return point.offset(offset) unless na_drawn__follow_mode? && offset

            rail = na_drawn__follow_rail_at(point)
            return point.offset(offset) unless rail

            normal   = @na_pp_follow[:normal]
            distance = offset.dot(normal).to_f

            Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(
                point, Na__InsertPrimatives.Na__FollowPush__Vector(rail[:dir], normal, distance), 1.0
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Rail Whose Corner Sits at a World Point, or nil
        # ------------------------------------------------------------
        def na_drawn__follow_rail_at(point)
            @na_pp_follow_lookup ||= @na_pp_follow[:rails].each_with_object({}) do |rail, lookup|
                lookup[na_drawn__follow_key(rail[:point])] = rail
            end

            found = @na_pp_follow_lookup[na_drawn__follow_key(point)]
            return found if found

            @na_pp_follow[:rails].find { |rail| rail[:point].distance(point) < NA_FOLLOW_TOL }
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Point Rounded for the Lookup
        # ------------------------------------------------------------
        def na_drawn__follow_key(point)
            [(point.x.to_f * 1000.0).round, (point.y.to_f * 1000.0).round, (point.z.to_f * 1000.0).round]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Why the Live Push Cannot Follow, or nil When It Can
        # Only inward is limited: a corner cannot run past its rail's end.
        # ------------------------------------------------------------
        def na_drawn__follow_problem
            return nil unless na_drawn__follow_mode?

            max_in = @na_pp_follow[:max_in]
            travel = na_drawn__world_travel_distance
            return nil unless max_in && travel < 0.0
            return nil if travel.abs < max_in - NA_FOLLOW_TOL

            "past the end of an edge it follows — #{Na__InsertPrimatives.Na__DrawnFormat__Mm(max_in).abs} mm in is the most"
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Card and Status Line's Word on Follow
        # ------------------------------------------------------------
        def na_drawn__follow_note
            reason = na_drawn__follow_reason
            return " · FOLLOW off: #{reason}" if reason
            return '' unless na_drawn__follow_mode?

            problem = na_drawn__follow_problem
            return " · FOLLOW: #{problem}" if problem

            max_in = @na_pp_follow[:max_in]
            limit  = max_in ? " (#{Na__InsertPrimatives.Na__DrawnFormat__Mm(max_in).abs} mm in at most)" : ''
            " · FOLLOW — each corner along its own edge#{limit}"
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Commit
        # -----------------------------------------------------------------------------

        # FUNCTION | Push the Face With Every Corner on Its Own Rail
        # ------------------------------------------------------------
        # Runs inside the push's operation, after the context was entered, so
        # the rails are read HERE in the space the face reports now. The world
        # travel is turned into that space through a point on the offset plane,
        # so an instance scale cannot stretch it. Returns the quad ring's stats
        # (or nil when no ring was involved). Raises on anything it cannot do,
        # and the operation rolls back.
        # ------------------------------------------------------------
        def na_drawn__execute_follow(model, entities, face, target, entered, world_travel, loops, cut)
            found = Na__InsertPrimatives.Na__FollowPush__Rails(face)
            raise "follow: #{found[:reason]}" unless found[:ok]

            rails    = found[:rails]
            normal   = face.normal
            xform    = entered ? Geom::Transformation.new : target[:transformation]
            anchor   = rails.first[:point]
            on_plane = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(anchor.transform(xform), target[:world_normal], world_travel)
            distance = (on_plane.transform(xform.inverse) - anchor).dot(normal).to_f

            vectors = rails.map { |rail| Na__InsertPrimatives.Na__FollowPush__Vector(rail[:dir], normal, distance) }

            if distance < 0.0
                rails.each_with_index do |rail, index|
                    next if vectors[index].length.to_f < rail[:inward].to_f - NA_FOLLOW_TOL

                    raise 'follow: the push runs past the end of an edge it follows'
                end
            end

            if cut
                moved = {}
                rails.each_with_index do |rail, index|
                    moved[rail[:vertex].entityID] = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(rail[:point], vectors[index], 1.0)
                end

                rings = face.loops.map { |loop| loop.vertices.map { |vertex| moved[vertex.entityID] } }
                raise 'follow: a corner of the ring could not be placed' if rings.flatten.any?(&:nil?)
                build = Na__InsertPrimatives.Na__DeepPick__AddTransform(model, entities, rings.first.first)
                return Na__InsertPrimatives.Na__PushPull__StitchQuadRing(entities, rings, build)
            end

            vertices = rails.map { |rail| rail[:vertex] }
            wanted   = rails.each_with_index.map { |rail, index| Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(rail[:point], vectors[index], 1.0) }

            entities.transform_by_vectors(vertices, vectors)

            vertices.each_with_index do |vertex, index|
                next if vertex.valid? && vertex.position.distance(wanted[index]) < NA_FOLLOW_TOL

                raise 'follow: a corner did not land on its edge — nothing was changed'
            end

            return nil if loops.nil? || loops.empty?

            build = Na__InsertPrimatives.Na__DeepPick__AddTransform(model, entities, loops.first.first)
            Na__InsertPrimatives.Na__PushPull__StitchQuadRing(entities, loops, build)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnPushPullFollow module

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP PUSH PULL FOLLOW
# =============================================================================
