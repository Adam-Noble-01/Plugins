# =============================================================================
# NA INSERT PRIMATIVES - SLOPE PUSH
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnSlopePush__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Push a face along the plane of the face NEXT to it instead of
#              along its own normal, so a roof carries on down its own rake
# CREATED    : 2026
#
# DESCRIPTION:
# - Sketchup::Face#pushpull only ever extrudes along the face normal. On the
#   plumb-cut end of a roof that normal is horizontal, so the only thing the
#   native tool can do is push the end sideways: the roof gets longer on plan
#   and the rake it was cut to is thrown away.
# - What is wanted instead is the trajectory the geometry is already on. The
#   sloped face NEXT to the one being pushed carries that trajectory, so SHIFT
#   swaps the normal for the direction that continues THAT face's plane, and
#   the roof runs on down its own pitch with its end cut still plumb.
#
# HOW A NEIGHBOUR BECOMES A DIRECTION:
# - Across the shared edge, the direction that continues a neighbour's surface
#   is the one lying IN its plane, square to that edge, pointing away from it.
#   That is a cross product of the neighbour's normal with the edge direction,
#   signed so it leads out of the neighbour rather than back across it.
#
# WHICH NEIGHBOUR, WHEN THERE ARE FOUR OF THEM:
# - The end face of a roof has neighbours on all four sides. The two sloped
#   ones (the top surface and the soffit) are parallel and hand back the SAME
#   direction, so they collapse to one candidate. The two upright ones hand
#   back the face normal itself, because continuing a plane that is already
#   square to the face is just pushing normally.
# - So the rule is: keep the candidates that go FORWARD, throw away the ones
#   that are the normal in disguise, and take the one that deviates most. On
#   anything shaped like a roof that leaves exactly one answer, and it is the
#   rake. On a plain box it leaves none, which is correct — a box has no
#   trajectory to continue.
#
# WHY THE PUSH IS STILL A PUSHPULL:
# - Moving the end face along the slope by hand would stretch every face around
#   it, which is only valid while every one of those faces contains the slope
#   direction. Let one of them not contain it and the result is a face that is
#   no longer planar.
# - So the extrusion is still pushpull — along the normal, by the normal's
#   share of the slope travel — and the moved face is then SHEARED sideways by
#   the remainder. Every wall the push created is a parallelogram either way,
#   so the solid stays valid whatever the neighbours are doing, and the end
#   face lands exactly where the slope said it should.
#
# =============================================================================

require 'sketchup.rb'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Slope Push Constants
    # -----------------------------------------------------------------------------

    # Cos 85 degrees. A continuation this close to square with the face normal
    # leaves pushpull almost nothing to extrude along, and the shear would be
    # doing all the work — the same limit, for the same reason, that the arrow
    # key axis lock refuses.
    NA_SLOPE_PUSH_MIN_FORWARD = 0.0872

    # Cos 2 degrees. Closer to the normal than this and the neighbour is not a
    # slope at all, it is the upright side of the same prism.
    NA_SLOPE_PUSH_MIN_BEND    = 0.99939

    # Two candidates this close together are the same trajectory reached from
    # opposite sides — a roof's top surface and its soffit.
    NA_SLOPE_PUSH_SAME_DIR    = 0.9999

    NA_SLOPE_PUSH_PROBE       = 0.01                                          # <-- Inches; the side-of-the-edge test step
    NA_SLOPE_PUSH_MIN_SHEAR   = 0.0005
    # Sin 0.1 degrees. A neighbour whose normal is this close to square with the
    # slope CONTAINS the slope, so stretching the face along it leaves that
    # neighbour planar and simply longer.
    NA_SLOPE_PUSH_IN_PLANE    = 0.0018                                        # <-- Inches; below SketchUp's own merge tolerance, so not worth applying

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Finding the Trajectory
    # -----------------------------------------------------------------------------

    # FUNCTION | Every Neighbour Trajectory This Face Could Be Pushed Along
    # ------------------------------------------------------------
    # Returns an array of candidate hashes, most deviant first:
    #
    #   :direction       world unit vector the face would travel along
    #   :local_direction the same, in the face's own definition space
    #   :face            the neighbour whose plane it continues
    #   :dot             cosine between the direction and the face normal
    #   :degrees         that cosine as an angle, for the status line
    #
    # Empty when the face has no neighbour offering anything other than its own
    # normal, which is the honest answer for a box.
    # ------------------------------------------------------------
    def self.Na__SlopePush__Candidates(target)
        return [] unless target

        face = target[:face]
        return [] unless face && face.valid?

        normal = target[:world_normal]
        xform  = target[:transformation] || Geom::Transformation.new
        return [] unless normal

        found = []

        face.edges.each do |edge|
            next unless edge && edge.valid?

            edge.faces.each do |neighbour|
                next if neighbour == face
                next unless neighbour.valid?

                local = Na__InsertPrimatives.Na__SlopePush__ContinuationOf(edge, neighbour)
                next unless local

                world = Na__InsertPrimatives.Na__SlopePush__ToWorld(edge, local, xform)
                next unless world

                dot = world.dot(normal).to_f
                next if dot < NA_SLOPE_PUSH_MIN_FORWARD                       # <-- Sideways or backwards; not a continuation
                next if dot > NA_SLOPE_PUSH_MIN_BEND                          # <-- The normal in disguise; nothing gained

                found << {
                    :direction       => world,
                    :local_direction => local,
                    :face            => neighbour,
                    :edge            => edge,
                    :dot             => dot,
                    :degrees         => Na__InsertPrimatives.Na__SlopePush__Degrees(dot)
                }
            end
        end

        Na__InsertPrimatives.Na__SlopePush__Distinct(found)
    rescue StandardError
        []
    end
    # ---------------------------------------------------------------

    # FUNCTION | The One Trajectory SHIFT Will Use, or nil
    # Most deviant wins. On a roof end that is the rake, because the only other
    # candidates were the upright sides and those were dropped for being the
    # normal already.
    # ------------------------------------------------------------
    def self.Na__SlopePush__Best(target)
        Na__InsertPrimatives.Na__SlopePush__Candidates(target).first
    end
    # ---------------------------------------------------------------

    # FUNCTION | Collapse Candidates Pointing the Same Way, Most Deviant First
    # ------------------------------------------------------------
    def self.Na__SlopePush__Distinct(found)
        unique = []

        found.sort_by { |candidate| candidate[:dot] }.each do |candidate|
            duplicate = unique.any? do |kept|
                kept[:direction].dot(candidate[:direction]) > NA_SLOPE_PUSH_SAME_DIR
            end

            unique << candidate unless duplicate
        end

        unique
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Direction That Carries On Out of a Neighbour, Locally
    # ------------------------------------------------------------
    # In the neighbour's plane and square to the shared edge — a cross product
    # of its normal with the edge — then signed to lead AWAY from it.
    #
    # The sign is decided twice on purpose. The centroid says which side the
    # bulk of the neighbour lies on, which is right for anything convex and
    # cheap for everything. classify_point then asks the face itself whether a
    # step that way lands back inside it, which is the answer that holds for an
    # L-shaped or a holed neighbour where a centroid can mislead.
    # ------------------------------------------------------------
    def self.Na__SlopePush__ContinuationOf(edge, neighbour)
        edge_dir = edge.line[1]
        return nil unless edge_dir && edge_dir.length > 0

        direction = neighbour.normal.cross(edge_dir.normalize)
        return nil unless direction.length > 0

        direction = direction.normalize
        middle    = Na__InsertPrimatives.Na__SlopePush__EdgeMidpoint(edge)
        return nil unless middle

        centre = Na__InsertPrimatives.Na__SlopePush__FaceCentre(neighbour)
        if centre
            inward    = centre - middle
            direction = direction.reverse if inward.length > 0 && direction.dot(inward) > 0
        end

        probe = middle.offset(direction, NA_SLOPE_PUSH_PROBE)
        direction = direction.reverse if neighbour.classify_point(probe) == Sketchup::Face::PointInside

        direction
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Carry a Local Direction Out to World Space
    # ------------------------------------------------------------
    # Two points rather than the vector, deliberately. A direction is only a
    # difference of positions, and transforming the two positions cannot be
    # caught out by how a translation is or is not applied to a bare vector.
    # ------------------------------------------------------------
    def self.Na__SlopePush__ToWorld(edge, local_direction, xform)
        start_point = Na__InsertPrimatives.Na__SlopePush__EdgeMidpoint(edge)
        return nil unless start_point

        ahead = start_point.offset(local_direction, 1.0)
        world = ahead.transform(xform) - start_point.transform(xform)
        return nil unless world.length > 0

        world.normalize
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Midpoint of an Edge, in Its Own Local Space
    # ------------------------------------------------------------
    def self.Na__SlopePush__EdgeMidpoint(edge)
        a = edge.start.position
        b = edge.end.position

        Geom::Point3d.new(
            (a.x.to_f + b.x.to_f) * 0.5,
            (a.y.to_f + b.y.to_f) * 0.5,
            (a.z.to_f + b.z.to_f) * 0.5
        )
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Average of a Face's Vertices, in Its Own Local Space
    # ------------------------------------------------------------
    def self.Na__SlopePush__FaceCentre(face)
        vertices = face.vertices
        return nil if vertices.empty?

        x = 0.0
        y = 0.0
        z = 0.0

        vertices.each do |vertex|
            position = vertex.position
            x += position.x.to_f
            y += position.y.to_f
            z += position.z.to_f
        end

        count = vertices.length.to_f
        Geom::Point3d.new(x / count, y / count, z / count)
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Cosine as a Whole-Tenth Angle
    # ------------------------------------------------------------
    def self.Na__SlopePush__Degrees(dot)
        clamped = dot.to_f
        clamped =  1.0 if clamped >  1.0
        clamped = -1.0 if clamped < -1.0

        (Math.acos(clamped) * 180.0 / Math::PI).round(1)
    rescue StandardError
        0.0
    end
    # ---------------------------------------------------------------

    # FUNCTION | How the Status Line Names the Trajectory
    # On a plumb-cut roof end the face normal is horizontal, so this angle IS
    # the pitch the roof is about to carry on down.
    # ------------------------------------------------------------
    def self.Na__SlopePush__Label(candidate)
        return nil unless candidate

        "#{format('%.1f', candidate[:degrees])}° off normal"
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Splitting the Travel into a Push and a Shear
    # -----------------------------------------------------------------------------

    # FUNCTION | Break a Local Offset into What pushpull Can Do and What It Cannot
    # ------------------------------------------------------------
    # Returns { :distance, :shear } in the face's own definition space:
    # :distance is what pushpull is given, :shear is the sideways remainder the
    # moved face has to be slid by afterwards.
    #
    # For an ordinary push the offset IS the normal times the distance, so the
    # shear comes out as a zero vector and this reduces to exactly the maths the
    # tool used before slope mode existed.
    # ------------------------------------------------------------
    def self.Na__SlopePush__SplitOffset(face, local_offset)
        normal   = face.normal
        distance = local_offset.dot(normal).to_f

        shear = Geom::Vector3d.new(
            local_offset.x.to_f - normal.x.to_f * distance,
            local_offset.y.to_f - normal.y.to_f * distance,
            local_offset.z.to_f - normal.z.to_f * distance
        )

        { :distance => distance, :shear => shear }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Push a Set of Vertices Once, and Report What Actually Moved
    # ------------------------------------------------------------
    # Returns the delta a witness vertex ACTUALLY travelled, or nil if nothing
    # moved at all.
    #
    # WHY THREE APIS AND A MEASUREMENT RATHER THAN ONE CALL:
    # - transform_by_vectors is the documented way to move vertices; it is also
    #   the call that raised on SketchUp 2026 and took slope mode's whole commit
    #   with it, which is the only way that release could have previewed
    #   correctly and built nothing.
    # - transform_entities with a translation is how everything else in SketchUp
    #   gets moved, and it is tried at the vertices and then at the FACE, which
    #   carries the vertices it is bounded by.
    # - Which of the three will actually shift a Vertex in a given build is not
    #   something to take on trust, and a call that quietly does nothing is
    #   indistinguishable from one that was never made.
    # - It is also undocumented which SPACE either of them reads a delta in. An
    #   open editing session moves the goalposts, and guessing wrong there is
    #   silent: the geometry moves, just not where it was told. That exact class
    #   of bug cost the chamfer tool three releases, which is why
    #   Na__DeepPick__AddTransform probes rather than assumes.
    # - So this asks the model. It tries, it measures a witness vertex, and it
    #   hands back the truth for the caller to correct or refuse on.
    # ------------------------------------------------------------
    def self.Na__SlopePush__Nudge(entities, face, vertices, wanted)
        witness = vertices.first
        return nil unless witness && witness.valid?

        # CLONED, not aliased. If Vertex#position ever handed back a live handle
        # rather than a copy, the witness would appear never to have moved and
        # every route below would be judged a failure — a measurement that
        # cannot be trusted is worse than none.
        before      = witness.position.clone
        translation = Geom::Transformation.translation(wanted)

        # ROUTE 1 — the documented way to move vertices.
        begin
            entities.transform_by_vectors(vertices, Array.new(vertices.length, wanted))
        rescue StandardError
            nil
        end
        landed = Na__InsertPrimatives.Na__SlopePush__Travelled(witness, before)
        return landed if landed

        # ROUTE 2 — the way everything else in SketchUp gets moved, aimed at the
        # vertices.
        begin
            entities.transform_entities(translation, vertices)
        rescue StandardError
            nil
        end
        landed = Na__InsertPrimatives.Na__SlopePush__Travelled(witness, before)
        return landed if landed

        # ROUTE 3 — the same, aimed at the FACE. Transforming a face carries the
        # vertices it is bounded by, which is precisely the hand operation being
        # reproduced: select the end of the roof and move it.
        begin
            entities.transform_entities(translation, [face]) if face && face.valid?
        rescue StandardError
            nil
        end

        Na__InsertPrimatives.Na__SlopePush__Travelled(witness, before)
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | How Far a Witness Vertex Moved, or nil for Not at All
    # ------------------------------------------------------------
    def self.Na__SlopePush__Travelled(witness, before)
        return nil unless witness && witness.valid?

        now = witness.position
        return nil if now.distance(before).to_f < NA_SLOPE_PUSH_MIN_SHEAR

        now - before
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Move a Set of Vertices, Then Check They Actually Went There
    # ------------------------------------------------------------
    # One nudge, one measurement, and one correction if the nudge landed
    # somewhere other than where it was sent. When the first move was right —
    # which is what is expected — the shortfall is nothing and no second move
    # is made. Exactly one correction pass: a second failure is a refusal, not
    # something to keep chasing.
    # ------------------------------------------------------------
    def self.Na__SlopePush__MoveVertices(entities, face, vertices, wanted)
        return false unless entities && vertices && wanted
        return false if vertices.empty?
        return false if wanted.length.to_f < NA_SLOPE_PUSH_MIN_SHEAR

        landed = Na__InsertPrimatives.Na__SlopePush__Nudge(entities, face, vertices, wanted)
        return false unless landed

        shortfall = wanted - landed
        return true if shortfall.length.to_f < NA_SLOPE_PUSH_MIN_SHEAR

        Na__InsertPrimatives.Na__SlopePush__Nudge(entities, face, vertices, shortfall)
        true
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Point Guaranteed to Lie Strictly Inside a Face
    # Taken off the face's own triangulation, so it holds for a concave outline
    # or one with a hole in it, where an average of the vertices need not.
    # ------------------------------------------------------------
    def self.Na__SlopePush__InteriorPoint(face)
        return nil unless face && face.valid?

        mesh    = face.mesh
        polygon = mesh.polygons.find { |indices| indices.length == 3 }
        return Na__InsertPrimatives.Na__SlopePush__FaceCentre(face) unless polygon

        points = polygon.map { |index| mesh.point_at(index.abs) }

        Geom::Point3d.new(
            (points[0].x.to_f + points[1].x.to_f + points[2].x.to_f) / 3.0,
            (points[0].y.to_f + points[1].y.to_f + points[2].y.to_f) / 3.0,
            (points[0].z.to_f + points[1].z.to_f + points[2].z.to_f) / 3.0
        )
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Which Face Did pushpull Actually Leave at the Far End?
    # ------------------------------------------------------------
    # Sketchup::Face#pushpull is not documented to leave the Face object alive
    # and bounding the moved loop, and betting the shear on it did not pay: a
    # shear applied to a dead or unmoved face is a silent no-op, which is
    # exactly how slope mode came to preview correctly and build nothing.
    #
    # So the moved face is IDENTIFIED rather than assumed. A point known to be
    # strictly inside the face before the push, carried along the push, must
    # land strictly inside the moved face afterwards — that is what "the face
    # moved there" means. The original object is asked first because it is one
    # test and it is very often the answer; only if it is not does this sweep
    # the definition, which is affordable once at commit time and never during
    # a drag.
    # ------------------------------------------------------------
    def self.Na__SlopePush__MovedFace(entities, face, interior_before, travel, normal)
        return nil unless interior_before && travel

        wanted = interior_before.offset(travel)

        if face && face.valid? &&
           face.classify_point(wanted) == Sketchup::Face::PointInside
            return face
        end

        return nil unless entities

        entities.grep(Sketchup::Face).each do |candidate|
            next unless candidate.valid?
            next unless normal.nil? || candidate.normal.samedirection?(normal)
            return candidate if candidate.classify_point(wanted) == Sketchup::Face::PointInside
        end

        nil
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Would Stretching Along This Slope Keep Every Neighbour Flat?
    # ------------------------------------------------------------
    # THE QUESTION THIS ANSWERS:
    # - Moving the face bodily along the slope is the operation a user does by
    #   hand: select the end of the roof, move it down the rake. Nothing is
    #   created, nothing is welded, and there is no seam to tidy afterwards —
    #   the surrounding faces simply get longer. It is the cleanest possible
    #   answer and it is what the roof case actually wants.
    # - It is only VALID while every face that shares a vertex with this one
    #   contains the slope direction. One that does not gets dragged out of its
    #   own plane, and a non-planar face is a mess SketchUp resolves by
    #   triangulating behind the user's back.
    # - Vertices, not edges: a face touching only a corner of this one still
    #   moves with it, so the edge neighbours alone are not the whole set.
    # ------------------------------------------------------------
    def self.Na__SlopePush__CanStretch?(face, local_direction)
        return false unless face && face.valid? && local_direction
        return false if local_direction.length.to_f <= 0.0

        heading  = local_direction.normalize
        affected = []

        face.vertices.each do |vertex|
            vertex.faces.each do |other|
                next if other == face
                affected << other if other.valid?
            end
        end

        affected.uniq!
        return false if affected.empty?

        affected.all? { |other| other.normal.dot(heading).abs <= NA_SLOPE_PUSH_IN_PLANE }
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Carry the Face Bodily Along the Slope
    # No pushpull, nothing created, no seam: the faces around it stretch to
    # follow, which is the whole point of taking this path.
    # ------------------------------------------------------------
    def self.Na__SlopePush__Stretch(entities, face, local_offset)
        return false unless face && face.valid?

        Na__InsertPrimatives.Na__SlopePush__MoveVertices(entities, face, face.vertices, local_offset)
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Slide the Face pushpull Just Moved
    # ------------------------------------------------------------
    # Only that face's own vertices move, so every wall the push created goes
    # from a rectangle to a parallelogram — still planar, because the moved loop
    # is a pure translation of the loop it grew from. Nothing else in the model
    # is touched.
    #
    # Hand this the face Na__SlopePush__MovedFace identified, never the object
    # that went into pushpull: see the note there for why those are not reliably
    # the same face.
    # ------------------------------------------------------------
    def self.Na__SlopePush__ApplyShear(entities, face, shear)
        return false unless face && face.valid?

        Na__InsertPrimatives.Na__SlopePush__MoveVertices(entities, face, face.vertices, shear)
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Erase the Seam a Sheared Push Leaves Behind
    # ------------------------------------------------------------
    # A normal push welds its new wall into the coplanar wall it grew out of and
    # deletes the line where they met. A sheared one cannot: at the moment
    # pushpull runs the new wall is NOT yet coplanar with the roof — the shear
    # is what makes it so, and by then the weld has already not happened. Left
    # alone that puts a plumb line across a roof the user just made continuous.
    #
    # WHERE THE CANDIDATES COME FROM:
    # - The walls this push created are exactly the faces touching the moved
    #   face, and the seam is one of THEIR edges. Reading them off the moved
    #   face afterwards asks the model what actually happened rather than
    #   assuming which edges pushpull chose to keep, which is not documented and
    #   is not the sort of thing to bet a delete on.
    # - Every edge in that set is a line this push put there: the top loop
    #   (moved face against wall), the corners (wall against wall) and the seam
    #   (wall against what it grew from). So every weld this can make is one
    #   native pushpull would have made itself.
    #
    # WHAT IT REFUSES TO TOUCH:
    # - Anything not bounded by exactly two faces.
    # - The moved face's own boundary, so the face being pushed can never be
    #   dissolved into the wall it just made.
    # - Faces that fold back on each other: their normals are anti-parallel, and
    #   that is why the test is samedirection? rather than parallel?.
    # ------------------------------------------------------------
    def self.Na__SlopePush__HealSeam(face)
        return 0 unless face && face.valid?

        walls = []
        face.edges.each do |edge|
            edge.faces.each do |wall|
                next if wall == face
                walls << wall if wall.valid?
            end
        end
        walls.uniq!

        candidates = []
        walls.each { |wall| candidates.concat(wall.edges) }
        candidates.uniq!

        removed = 0

        candidates.each do |edge|
            next unless edge && edge.valid?

            faces = edge.faces
            next unless faces.length == 2
            next if faces.include?(face)
            next unless faces[0].valid? && faces[1].valid?
            next unless faces[0].normal.samedirection?(faces[1].normal)

            edge.erase!
            removed += 1
        end

        removed
    rescue StandardError
        0
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF SLOPE PUSH MODULE
# =============================================================================
