# =============================================================================
# NA INSERT PRIMATIVES - DRAWN PIPE BUILD
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnPipe__Build__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Solved rings into one SketchUp mesh, the pipe group that holds it,
#              and the route and spec the group keeps so it can be resized and
#              re-routed later
# CREATED    : 2026
#
# ONE MESH, EVERY EDGE DECIDED:
# - The whole pipe goes in with Entities#fill_from_mesh into an empty group,
#   which is SketchUp's fastest way in. Which edges are soft is not left to
#   AUTO_SOFTEN's guess: each polygon marks its own soft edges with negative
#   indices (SOFTEN_BASED_ON_INDEX), and SMOOTH_SOFT_EDGES smooths them.
#     soft  the long edges of a round pipe (6 sides and up), every ring
#           inside or at the ends of a bend, every ring inside a drawn arc,
#           the radial seams across a hollow pipe's end
#     hard  the cap outlines, a real mitre's seam, the long edges of a
#           square or triangular duct, both rims of a hollow pipe's end
# - Every quad between two rings is flat by construction (two rings on the
#   same bend are the same section turned, so opposite sides are parallel).
#   One that is not — only a 3D loop's spread twist does that — is split
#   into two triangles across a soft diagonal rather than refused.
#
# A TRUE PIPE (5.2.10):
# - With a bore, the same stations are ringed a second time at the bore's
#   radius and wound the other way, so those faces look into the bore. The
#   open ends become flat rings between the two rims. End Caps does not apply
#   to a hollow pipe: its ends are its walls.
#
# THE PIPE REMEMBERS ITS ROUTE:
# - Each group keeps its cleaned route, curve flags, spec (bore included),
#   caps and up in the NA_DRAWN_PIPE_DICTIONARY attributes, in the group's
#   OWN coordinates. A new group is pinned to the world identity, so at birth
#   those are the world points it was drawn through; moved, rotated or nested
#   later, they are still exactly where its geometry is. Resizing a pipe, or
#   giving it a new route from an edited red line (DrawnPipe__Edit__), is a
#   rebuild from those numbers with no coordinate conversion at all.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnGeometry__'
require_relative 'Na__InsertPrimatives__DrawnPipe__Spec__'
require_relative 'Na__InsertPrimatives__DrawnPipe__Route__'
require_relative 'Na__InsertPrimatives__DrawnPipe__Solver__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Build Constants
    # -----------------------------------------------------------------------------

    NA_DRAWN_PIPE_GROUP_PREFIX   = '01__DrawnPipe'
    NA_DRAWN_PIPE_ROUTE_VERSION  = 1
    NA_DRAWN_PIPE_PLANAR_TOL     = 1.0e-4                                     # <-- Inches a quad's fourth corner may sit off the plane of the other three

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Mesh
    # -----------------------------------------------------------------------------

    # FUNCTION | The Solved Rings as One Polygon Mesh
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__Mesh(solved, caps = true)
        rings  = solved[:rings]
        bore   = solved[:bore]
        sides  = rings.first.length
        count  = rings.length
        layers = bore ? 2 : 1
        mesh   = Geom::PolygonMesh.new(count * sides * layers, (count * sides * 2 + 2) * layers)

        outer = Na__InsertPrimatives.Na__DrawnPipe__AddRings(mesh, rings)
        inner = bore ? Na__InsertPrimatives.Na__DrawnPipe__AddRings(mesh, bore) : nil

        Na__InsertPrimatives.Na__DrawnPipe__AddTube(mesh, solved, rings, outer, false)
        Na__InsertPrimatives.Na__DrawnPipe__AddTube(mesh, solved, bore, inner, true) if inner

        return mesh if solved[:closed]

        if inner
            Na__InsertPrimatives.Na__DrawnPipe__AddAnnulus(mesh, outer.first, inner.first, true)
            Na__InsertPrimatives.Na__DrawnPipe__AddAnnulus(mesh, outer.last, inner.last, false)
        elsif caps
            mesh.add_polygon(outer.first.reverse)                             # <-- Wound backwards: the start cap faces back down the pipe
            mesh.add_polygon(outer.last)
        end

        mesh
    end
    # ---------------------------------------------------------------

    # FUNCTION | Every Ring's Points Into the Mesh; Returns Their Indices
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__AddRings(mesh, rings)
        rings.map do |ring|
            ring.map { |point| mesh.add_point(Geom::Point3d.new(point[0], point[1], point[2])) }
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Side Quads Between Consecutive Rings
    # ------------------------------------------------------------
    # `inward` winds them the other way round, a, d, c, b, so the bore's faces
    # look into the bore; the soft flags travel with the edges they belong to.
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__AddTube(mesh, solved, rings, index, inward)
        sides = rings.first.length
        count = rings.length

        pairs = (0...(count - 1)).map { |ring| [ring, ring + 1, 0] }
        pairs << [count - 1, 0, solved[:offset].to_i] if solved[:closed]

        pairs.each do |from, to, offset|
            soft_from = !solved[:hard][from]
            soft_to   = !solved[:hard][to]
            long_soft = solved[:round] ? true : false

            sides.times do |j|
                ids = [
                    index[from][j],
                    index[from][(j + 1) % sides],
                    index[to][(j + 1 + offset) % sides],
                    index[to][(j + offset) % sides]
                ]
                pts = [
                    rings[from][j],
                    rings[from][(j + 1) % sides],
                    rings[to][(j + 1 + offset) % sides],
                    rings[to][(j + offset) % sides]
                ]
                soft = [soft_from, long_soft, soft_to, long_soft]

                if inward
                    ids  = [ids[0], ids[3], ids[2], ids[1]]
                    pts  = [pts[0], pts[3], pts[2], pts[1]]
                    soft = [long_soft, soft_to, long_soft, soft_from]
                end

                Na__InsertPrimatives.Na__DrawnPipe__AddQuad(mesh, ids, pts, soft)
            end
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Hollow Pipe's Open End: Flat Quads Between the Two Rims
    # ------------------------------------------------------------
    # Both rims stay hard (they are the outline of the end); the radial seams
    # between the quads are soft, so the end reads as one flat ring.
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__AddAnnulus(mesh, outer, inner, start)
        sides = outer.length

        sides.times do |j|
            k = (j + 1) % sides

            if start
                mesh.add_polygon(outer[k], -outer[j], inner[j], -inner[k])   # <-- Faces back down the pipe
            else
                mesh.add_polygon(outer[j], -outer[k], inner[k], -inner[j])
            end
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | One Side Quad, or Two Triangles When It Is Not Flat
    # ------------------------------------------------------------
    # ids are a, b, c, d round the quad; soft says, for the edge that STARTS
    # at each of them (a-b, b-c, c-d, d-a), whether it is soft. A negative
    # index is how a PolygonMesh is told so.
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__AddQuad(mesh, ids, pts, soft)
        a, b, c, d = ids
        mark = lambda { |id, is_soft| is_soft ? -id : id }

        if Na__InsertPrimatives.Na__DrawnPipe__Flat?(pts)
            mesh.add_polygon(mark.call(a, soft[0]), mark.call(b, soft[1]), mark.call(c, soft[2]), mark.call(d, soft[3]))
        else
            mesh.add_polygon(mark.call(a, soft[0]), mark.call(b, soft[1]), -c)   # <-- c-a is the diagonal: always soft
            mesh.add_polygon(-a, mark.call(c, soft[2]), mark.call(d, soft[3]))
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Do Four Points Lie in One Plane?
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__Flat?(pts)
        p0, p1, p2, p3 = pts
        e1 = [p1[0] - p0[0], p1[1] - p0[1], p1[2] - p0[2]]
        e2 = [p2[0] - p0[0], p2[1] - p0[1], p2[2] - p0[2]]
        e3 = [p3[0] - p0[0], p3[1] - p0[1], p3[2] - p0[2]]
        n  = [e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0]]
        nl = Math.sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2])
        return false unless nl > 0.0

        ((e3[0] * n[0] + e3[1] * n[1] + e3[2] * n[2]) / nl).abs <= NA_DRAWN_PIPE_PLANAR_TOL
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Smoothing Flags Every Pipe Is Filled With
    # (Not SmoothFlags: that name is the route reader's per-vertex curve flags.)
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__MeshSmoothing
        Geom::PolygonMesh::SOFTEN_BASED_ON_INDEX | Geom::PolygonMesh::SMOOTH_SOFT_EDGES
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Groups
    # -----------------------------------------------------------------------------

    # FUNCTION | The Outliner Name for a Pipe of This Spec
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__GroupName(spec)
        "#{NA_DRAWN_PIPE_GROUP_PREFIX}__#{Na__InsertPrimatives.Na__DrawnPipe__FormatMm(spec[:diameter])}mm"
    end
    # ---------------------------------------------------------------

    # FUNCTION | Build One Run as a New Pipe Group in `entities`
    # ------------------------------------------------------------
    # Runs inside the caller's operation, so a whole selection of runs is one
    # Ctrl+Z. `up` and the run's points are WORLD (see the file header).
    # Returns [group or nil, solved].
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__CreateGroup(entities, run, spec, up, caps)
        solved = Na__InsertPrimatives.Na__DrawnPipe__Solve(run, spec, up)
        return [nil, solved] unless solved[:ok]

        group      = entities.add_group
        group.name = Na__InsertPrimatives.Na__DrawnPipe__GroupName(spec)
        Na__InsertPrimatives.Na__DrawnGeom__PinGroupToWorld(group)            # <-- World points into a closed group: see DrawnGeometry

        unless Na__InsertPrimatives.Na__DrawnPipe__WritePipe(group, solved, spec, up, caps)
            group.erase! if group.valid?
            return [nil, solved.merge(:ok => false, :message => 'SketchUp would not make faces from this pipe')]
        end

        [group, solved]
    end
    # ---------------------------------------------------------------

    # FUNCTION | A New Pipe Beside an Existing One, in the Same Frame
    # ------------------------------------------------------------
    # For a re-routed pipe whose red line now holds more than one run: the
    # extra runs become pipes of their own. They are in the first pipe's own
    # coordinates, so the new group is given the first one's transformation —
    # both read in the same frame, the parent's, whether it is open or not.
    # `solved` comes ready, so the caller can refuse before any operation.
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__CreateSibling(pipe, solved, spec, up, caps)
        entities = pipe.parent.entities

        group                = entities.add_group
        group.transformation = pipe.transformation
        group.name           = Na__InsertPrimatives.Na__DrawnPipe__GroupName(spec)

        return group if Na__InsertPrimatives.Na__DrawnPipe__WritePipe(group, solved, spec, up, caps)

        group.erase! if group.valid?
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Rebuild a Pipe Group at a New Spec From Its Own Stored Route
    # ------------------------------------------------------------
    # Local coordinates throughout: the stored route is the group's own. A
    # copied pipe is made unique first, or resizing one would resize its twin.
    # `route` ({ :points, :closed, :smooth }, the group's own coordinates)
    # replaces the stored one — an edited red line. The pipe's own caps are
    # kept unless `caps` says otherwise.
    # Returns [true / false, solved].
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__RebuildGroup(group, spec, route = nil, caps = nil)
        stored = Na__InsertPrimatives.Na__DrawnPipe__StoredRoute(group)
        return [false, { :ok => false, :message => 'this group has no pipe route stored', :warnings => [] }] unless stored

        source = route ? stored.merge(route) : stored
        solved = Na__InsertPrimatives.Na__DrawnPipe__Solve(source, spec, stored[:up])
        return [false, solved] unless solved[:ok]

        ok = Na__InsertPrimatives.Na__DrawnPipe__RebuildSolved(group, solved, spec, caps.nil? ? stored[:caps] : caps)
        ok ? [true, solved] : [false, solved.merge(:ok => false, :message => 'SketchUp would not make faces from this pipe')]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Replace a Pipe Group's Geometry With a Solve Made Earlier
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__RebuildSolved(group, solved, spec, caps)
        stored = Na__InsertPrimatives.Na__DrawnPipe__StoredRoute(group)
        up     = stored ? stored[:up] : [0.0, 0.0, 1.0]

        group.make_unique if group.respond_to?(:make_unique)
        group.entities.clear!
        return false unless Na__InsertPrimatives.Na__DrawnPipe__WritePipe(group, solved, spec, up, caps)

        if group.name.to_s.start_with?(NA_DRAWN_PIPE_GROUP_PREFIX)
            group.name = Na__InsertPrimatives.Na__DrawnPipe__GroupName(spec)
        end

        true
    end
    # ---------------------------------------------------------------

    # FUNCTION | Fill an Empty Group With the Pipe and Store What Built It
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__WritePipe(group, solved, spec, up, caps)
        return false unless Na__InsertPrimatives.Na__DrawnPipe__Fill(group.entities, solved, caps)

        Na__InsertPrimatives.Na__DrawnPipe__StoreRoute(group, solved, spec, up, caps)
        true
    end
    # ---------------------------------------------------------------

    # FUNCTION | Fill an Empty Entities Collection With the Pipe
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__Fill(entities, solved, caps)
        mesh = Na__InsertPrimatives.Na__DrawnPipe__Mesh(solved, caps)
        entities.fill_from_mesh(mesh, true, Na__InsertPrimatives.Na__DrawnPipe__MeshSmoothing)
        entities.length > 0
    rescue StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "DRAWN PIPE: fill failed — #{error.message}"
        false
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Stored Route
    # -----------------------------------------------------------------------------

    # FUNCTION | Write the Route and Spec Onto the Group
    # Flat number arrays: an attribute holds an Array of numbers safely, a
    # nested one not reliably.
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__StoreRoute(group, solved, spec, up, caps)
        up_vector = up.respond_to?(:x) ? [up.x.to_f, up.y.to_f, up.z.to_f] : (up || [0.0, 0.0, 1.0]).map(&:to_f)

        group.set_attribute(NA_DRAWN_PIPE_DICTIONARY, 'Version',       NA_DRAWN_PIPE_ROUTE_VERSION)
        group.set_attribute(NA_DRAWN_PIPE_DICTIONARY, 'Points',        solved[:points].flatten.map(&:to_f))
        group.set_attribute(NA_DRAWN_PIPE_DICTIONARY, 'Smooth',        solved[:smooth].map { |flag| flag ? 1 : 0 })
        group.set_attribute(NA_DRAWN_PIPE_DICTIONARY, 'Closed',        solved[:closed] ? true : false)
        Na__InsertPrimatives.Na__DrawnPipe__StoreSpecOn(group, spec)
        group.set_attribute(NA_DRAWN_PIPE_DICTIONARY, 'Caps',          caps ? true : false)
        group.set_attribute(NA_DRAWN_PIPE_DICTIONARY, 'Up',            up_vector)
        true
    end
    # ---------------------------------------------------------------

    # FUNCTION | Write Only the Spec Onto a Pipe Group
    # During a path edit the spec is changed ahead of the rebuild, so it has
    # a writer of its own.
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__StoreSpecOn(group, spec)
        group.set_attribute(NA_DRAWN_PIPE_DICTIONARY, 'Diameter',      spec[:diameter].to_f)
        group.set_attribute(NA_DRAWN_PIPE_DICTIONARY, 'BendRadius',    spec[:bend].to_f)
        group.set_attribute(NA_DRAWN_PIPE_DICTIONARY, 'Sides',         spec[:sides].to_i)
        group.set_attribute(NA_DRAWN_PIPE_DICTIONARY, 'InnerDiameter', spec[:inner].to_f)
        true
    end
    # ---------------------------------------------------------------

    # FUNCTION | Read a Pipe Group's Route Back, or nil
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__StoredRoute(group)
        return nil unless Na__InsertPrimatives.Na__DrawnPipe__IsPipe?(group)

        flat = group.get_attribute(NA_DRAWN_PIPE_DICTIONARY, 'Points')
        return nil unless flat.is_a?(Array) && flat.length >= 6 && (flat.length % 3).zero?

        points = flat.each_slice(3).map { |x, y, z| Geom::Point3d.new(x.to_f, y.to_f, z.to_f) }
        smooth = (group.get_attribute(NA_DRAWN_PIPE_DICTIONARY, 'Smooth') || []).map { |flag| flag.to_i == 1 }
        up     = group.get_attribute(NA_DRAWN_PIPE_DICTIONARY, 'Up')
        caps   = group.get_attribute(NA_DRAWN_PIPE_DICTIONARY, 'Caps')

        {
            :points => points,
            :smooth => smooth,
            :closed => group.get_attribute(NA_DRAWN_PIPE_DICTIONARY, 'Closed') ? true : false,
            :up     => up.is_a?(Array) && up.length == 3 ? up.map(&:to_f) : [0.0, 0.0, 1.0],
            :caps   => caps.nil? ? true : (caps ? true : false)
        }
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Spec a Pipe Group Was Last Built With, or nil
    # Pipes built before the bore existed read as solid.
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__StoredSpec(group)
        return nil unless Na__InsertPrimatives.Na__DrawnPipe__IsPipe?(group)

        {
            :diameter => group.get_attribute(NA_DRAWN_PIPE_DICTIONARY, 'Diameter').to_f,
            :bend     => group.get_attribute(NA_DRAWN_PIPE_DICTIONARY, 'BendRadius').to_f,
            :sides    => group.get_attribute(NA_DRAWN_PIPE_DICTIONARY, 'Sides').to_i,
            :inner    => group.get_attribute(NA_DRAWN_PIPE_DICTIONARY, 'InnerDiameter').to_f
        }
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DRAWN PIPE BUILD
# =============================================================================
