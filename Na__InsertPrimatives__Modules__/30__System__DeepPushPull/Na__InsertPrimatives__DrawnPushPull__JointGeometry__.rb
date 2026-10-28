# =============================================================================
# NA INSERT PRIMATIVES - DEEP PUSH PULL JOINT GEOMETRY
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnPushPull__JointGeometry__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Push a whole surface as one: every face along its own normal,
#              every corner mitred, the faces round it stretched or walled
# CREATED    : 2026
#
# DESCRIPTION:
# - A curved fascia is not one face. It is fifty narrow ones joined by soft
#   edges, which SketchUp's Entity Info calls a Surface. Pushed one by one
#   (5.2.13 and every version before it), each face went out along its own
#   normal and the run opened into a fan of separate boxes with wedge-shaped
#   gaps between them. Fredo's Joint Push Pull moves them as one, and so does
#   this: each face's PLANE is offset by the push distance, and every corner
#   goes to where the offset planes of the faces round it meet. The faces stay
#   joined at every edge and the surface keeps its shape, one push further out.
#
# THE CORNER SOLVE (Na__JointPush__UnitOffset):
# - A corner shared by faces with normals n1..nk travels u * d, where u meets
#   n . u = 1 for every one of them, so each face lands exactly d out.
#   * one face:     u = n, the plain push.
#   * two faces:    u = (n1 + n2) / (1 + n1 . n2), the mitre. Exact, and it
#                   is the case every single-curved surface (a fascia, a
#                   barrel, a bay) is made of, so those stay perfectly flat.
#   * three or more: least squares, through an eigen-solve that leaves out
#                   directions the normals barely span. A box corner is exact;
#                   on a doubly curved mesh the faces land within a hair of
#                   flat and any that would bend are folded, soft and smooth.
# - A mitre is capped at NA_JOINT_MAX_MITRE times the push (about 151 degrees
#   between faces); two faces folding back on each other refuse the push.
# - Everything is linear in d, so u is solved once per corner when the
#   surface is picked and the preview is a multiply per frame.
#
# THREE ROUTES, CHOSEN PER PUSH (Na__JointPush__Route):
# - STRETCH: every face round the surface CONTAINS the travel at the corners
#   it shares (a flat roof above a vertical fascia, the soffit below it, the
#   caps of a cylinder). The surface's own vertices are moved and the faces
#   round it stretch in their planes: nothing is created, nothing welded, no
#   seam, materials and soft edges untouched. In or out alike.
# - REBUILD: some corner cannot slide (a face round it would tilt, or an edge
#   is open). The surface is erased and built again one push further out;
#   corners that can slide still slide, and the rest get new side walls back
#   to where the surface was, exactly as native Push/Pull walls a face. Walls
#   lying flat against a face round them are healed into it pushing out, and
#   taken back out of it pushing in. Faces wear their old paint and tag.
# - THICKEN: a lone surface (no face round it at all) is thickened, the way a
#   lone face pushes into a box: the surface stays as the back, turned round.
#
# COORDINATES:
# - A plan holds WORLD positions and directions, built through the
#   transformation that carries the faces' REPORTED coordinates to world: the
#   pick's for a face inside a closed group, the identity for one in the open
#   context. World normals come from the loop's transformed points (Newell),
#   which is exact under non-uniform scale where a transformed normal tilts.
# - The commit builds its plan again inside the context it opened, where the
#   reported space IS world, and turns every world point back through the
#   inverse (the identity there) before it touches the model.
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__InsertPrimatives__DrawnPushPull__QuadRing__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Joint Push Constants
    # -----------------------------------------------------------------------------

    NA_JOINT_OPTION          = 'push_joint_surfaces'.freeze                   # <-- The Joint Surfaces switch (ToolOptions, SHIFT+TAB)
    NA_JOINT_HOVER_MAX_FACES = 2000                                           # <-- A bigger surface is pushed whole only when selected
    NA_JOINT_SAME_NORMAL     = 0.99999                                        # <-- Normals this close are one direction (about 0.26 degrees)
    NA_JOINT_EIGEN_FLOOR     = 0.01                                           # <-- Directions weaker than this share are left out of a 3+ face solve
    NA_JOINT_MAX_MITRE       = 4.0                                            # <-- A corner travels at most this many times the push
    NA_JOINT_FOLD_BACK       = 0.015                                          # <-- 1 + n1.n2 below this: faces fold back (about 170 degrees)
    NA_JOINT_MIN_SHARE       = 0.5                                            # <-- A face moved less than half the push is not a joint push
    NA_JOINT_MIN_AREA        = 0.01                                           # <-- A face shrunk past 1% of its area is as good as inside out
    NA_JOINT_PLANE_TOL       = 0.0005                                         # <-- Inches a slide may carry a corner off a face round it
    NA_JOINT_FLAT_TOL        = 0.001                                          # <-- Inches; a corner further off its face's plane bends it
    NA_JOINT_LAND_TOL        = 0.004                                          # <-- Inches; a moved corner this near its target has landed
    NA_JOINT_POINT_TOL       = 0.002                                          # <-- Inches; twice SketchUp's merge tolerance
    NA_JOINT_COPLANAR_DOT    = 0.99999                                        # <-- Faces sharing an edge this parallel lie in one plane
    NA_JOINT_SOFT_DOT        = Math.cos(35.0 * Math::PI / 180.0)              # <-- Walls meeting flatter than 35 degrees are softened

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Which Faces Go Together
    # -----------------------------------------------------------------------------

    # FUNCTION | The Surface a Face Belongs To — Faces Joined by Soft Edges
    # ------------------------------------------------------------
    # SketchUp's own notion: the Select tool takes every face reachable across
    # soft edges in one click, and Entity Info calls that a Surface. Smoothing
    # alone (an edge drawn but shaded round) does not join faces there, so it
    # does not join them here. Returns nil past `limit` faces, so a hover over
    # a huge smoothed terrain stays one face rather than stalling the cursor.
    # ------------------------------------------------------------
    def self.Na__JointPush__SurfaceOf(face, limit = NA_JOINT_HOVER_MAX_FACES)
        return [] unless face && face.valid?

        seen  = { face => true }
        queue = [face]

        until queue.empty?
            current = queue.shift

            current.edges.each do |edge|
                next unless edge.soft?

                edge.faces.each do |other|
                    next if seen[other]

                    seen[other] = true
                    queue << other
                end
            end

            return nil if seen.length > limit
        end

        seen.keys
    rescue StandardError
        [face]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Split Selected Faces Into Groups That Share Edges
    # ------------------------------------------------------------
    # A selection is an instruction: faces chosen together that touch are
    # meant to move together, soft edge or hard. Faces touching no other
    # selected face come back as groups of one and push exactly as before.
    # ------------------------------------------------------------
    def self.Na__JointPush__Components(faces)
        member = {}
        faces.each { |face| member[face] = true }

        seen   = {}
        groups = []

        faces.each do |start|
            next if seen[start]

            seen[start] = true
            group       = []
            queue       = [start]

            until queue.empty?
                current = queue.shift
                group << current

                current.edges.each do |edge|
                    edge.faces.each do |other|
                        next unless member[other] && !seen[other]

                        seen[other] = true
                        queue << other
                    end
                end
            end

            groups << group
        end

        groups
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Normals and the Corner Solve
    # -----------------------------------------------------------------------------

    # FUNCTION | Newell's Sum Round a Loop of Points (Twice the Vector Area)
    # ------------------------------------------------------------
    def self.Na__JointPush__Newell(points)
        x     = 0.0
        y     = 0.0
        z     = 0.0
        count = points.length

        points.each_with_index do |a, index|
            b  = points[(index + 1) % count]
            x += (a.y.to_f - b.y.to_f) * (a.z.to_f + b.z.to_f)
            y += (a.z.to_f - b.z.to_f) * (a.x.to_f + b.x.to_f)
            z += (a.x.to_f - b.x.to_f) * (a.y.to_f + b.y.to_f)
        end

        Geom::Vector3d.new(x, y, z)
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Face's Front Normal in World, Whatever the Instance Does to It
    # ------------------------------------------------------------
    # Transforming the normal itself is only right for rotations and uniform
    # scale: under a non-uniform scale it tilts. The loop's points are
    # transformed instead and Newell's sum read off them, which is exact for
    # any transformation. The transformed local normal only decides which way
    # round: it always lies on the front side, because its dot with the true
    # normal is n . n for any invertible matrix, a mirrored instance included.
    # ------------------------------------------------------------
    def self.Na__JointPush__WorldNormal(face, world_points, xform)
        newell = Na__InsertPrimatives.Na__JointPush__Newell(world_points)
        return nil if newell.length.to_f < 1.0e-12

        normal = newell.normalize
        side   = face.normal.transform(xform)
        side.dot(normal) < 0.0 ? normal.reverse : normal
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | How a Corner Travels Per Unit of Push
    # ------------------------------------------------------------
    # Returns { :vector, :clamped } with :vector nil when the faces at the
    # corner fold back on each other. See the header for the three cases.
    # ------------------------------------------------------------
    def self.Na__JointPush__UnitOffset(normals)
        distinct = []

        normals.each do |normal|
            next unless normal
            distinct << normal unless distinct.any? { |kept| kept.dot(normal) > NA_JOINT_SAME_NORMAL }
        end

        return { :vector => nil, :clamped => false } if distinct.empty?
        return { :vector => distinct.first.clone, :clamped => false } if distinct.length == 1

        if distinct.length == 2
            a, b  = distinct
            share = 1.0 + a.dot(b).to_f
            return { :vector => nil, :clamped => false } if share < NA_JOINT_FOLD_BACK

            mitre = Geom::Vector3d.new((a.x + b.x) / share, (a.y + b.y) / share, (a.z + b.z) / share)
            return Na__InsertPrimatives.Na__JointPush__ClampMitre(mitre)
        end

        solved = Na__InsertPrimatives.Na__JointPush__LeastSquares(distinct)
        return { :vector => nil, :clamped => false } unless solved
        return { :vector => nil, :clamped => false } if distinct.any? { |normal| normal.dot(solved) < NA_JOINT_MIN_SHARE }

        Na__InsertPrimatives.Na__JointPush__ClampMitre(solved)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Hold a Mitre to NA_JOINT_MAX_MITRE Times the Push
    # ------------------------------------------------------------
    def self.Na__JointPush__ClampMitre(vector)
        length = vector.length.to_f
        return { :vector => vector, :clamped => false } if length <= NA_JOINT_MAX_MITRE

        scale = NA_JOINT_MAX_MITRE / length
        { :vector => Geom::Vector3d.new(vector.x * scale, vector.y * scale, vector.z * scale), :clamped => true }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Least-Squares Corner for Three or More Face Directions
    # ------------------------------------------------------------
    # Minimises the sum of (n . u - 1)^2 through the eigen-decomposition of
    # the 3x3 normal matrix. A direction whose eigenvalue is under
    # NA_JOINT_EIGEN_FLOOR of the strongest is left out: there the planes are
    # nearly parallel, their meeting point runs off to infinity, and the
    # surface is better served by the plain average than by chasing it.
    # ------------------------------------------------------------
    def self.Na__JointPush__LeastSquares(normals)
        matrix = [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
        rhs    = [0.0, 0.0, 0.0]

        normals.each do |normal|
            n = [normal.x.to_f, normal.y.to_f, normal.z.to_f]

            3.times do |i|
                rhs[i] += n[i]
                3.times { |j| matrix[i][j] += n[i] * n[j] }
            end
        end

        values, vectors = Na__InsertPrimatives.Na__JointPush__Eigen3(matrix)
        strongest       = values.max.to_f
        return nil if strongest <= 0.0

        solution = [0.0, 0.0, 0.0]

        3.times do |k|
            next if values[k] < NA_JOINT_EIGEN_FLOOR * strongest

            axis  = [vectors[0][k], vectors[1][k], vectors[2][k]]
            share = (axis[0] * rhs[0] + axis[1] * rhs[1] + axis[2] * rhs[2]) / values[k]
            3.times { |i| solution[i] += share * axis[i] }
        end

        Geom::Vector3d.new(solution[0], solution[1], solution[2])
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Eigenvalues and Eigenvectors of a Symmetric 3x3 (Jacobi)
    # ------------------------------------------------------------
    # Returns [values, vectors] with the eigenvectors as COLUMNS of vectors.
    # ------------------------------------------------------------
    def self.Na__JointPush__Eigen3(matrix)
        a = matrix.map(&:dup)
        v = [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]

        50.times do
            off = (a[0][1] * a[0][1]) + (a[0][2] * a[0][2]) + (a[1][2] * a[1][2])
            break if off < 1.0e-24

            [[0, 1], [0, 2], [1, 2]].each do |p, q|
                next if a[p][q].abs < 1.0e-30

                theta = (a[q][q] - a[p][p]) / (2.0 * a[p][q])
                t     = (theta >= 0.0 ? 1.0 : -1.0) / (theta.abs + Math.sqrt((theta * theta) + 1.0))
                c     = 1.0 / Math.sqrt((t * t) + 1.0)
                s     = t * c

                3.times do |k|
                    akp     = a[k][p]
                    akq     = a[k][q]
                    a[k][p] = (c * akp) - (s * akq)
                    a[k][q] = (s * akp) + (c * akq)
                end

                3.times do |k|
                    apk     = a[p][k]
                    aqk     = a[q][k]
                    a[p][k] = (c * apk) - (s * aqk)
                    a[q][k] = (s * apk) + (c * aqk)
                end

                3.times do |k|
                    vkp     = v[k][p]
                    vkq     = v[k][q]
                    v[k][p] = (c * vkp) - (s * vkq)
                    v[k][q] = (s * vkp) + (c * vkq)
                end
            end
        end

        [[a[0][0], a[1][1], a[2][2]], v]
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | The Plan — Everything a Joint Push Needs, Read Once
    # -----------------------------------------------------------------------------

    # FUNCTION | Read a Set of Faces Into a Joint Push Plan
    # ------------------------------------------------------------
    # `xform` carries the faces' reported coordinates to world. Returns nil for
    # fewer than two faces (a single face is an ordinary push). The plan:
    #   :faces :face_set :xform :vertices :positions (world) :units (world,
    #   per unit of push) :rows (per face: :outer :inners :normal :triangles)
    #   :triangles :segments (boundary [a, b, face, outward, edge])
    #   :interior ([edge, a, b]) :loops / :loose (the boundary chained)
    #   :lean :touches :free (per corner) :lone :area :count :clamped
    #   :problem :probe, and :reach / :slide_reach, the distances the live
    #   drag is judged against without re-measuring a face
    # ------------------------------------------------------------
    def self.Na__JointPush__Plan(faces, xform)
        xform ||= Geom::Transformation.new
        faces   = faces.select { |face| face && face.valid? }
        return nil if faces.length < 2

        member = {}
        faces.each { |face| member[face] = true }

        vertices = faces.flat_map(&:vertices).uniq
        index    = {}
        vertices.each_with_index { |vertex, position| index[vertex] = position }
        positions = vertices.map { |vertex| vertex.position.transform(xform) }

        rows = faces.map do |face|
            outer = face.outer_loop.vertices.map { |vertex| index[vertex] }

            {
                :face      => face,
                :outer     => outer,
                :inners    => face.loops.reject(&:outer?).map { |loop| loop.vertices.map { |vertex| index[vertex] } },
                :normal    => Na__InsertPrimatives.Na__JointPush__WorldNormal(face, outer.map { |i| positions[i] }, xform),
                :triangles => Na__InsertPrimatives.Na__JointPush__FaceTriangles(face, index)
            }
        end

        problem = rows.any? { |row| row[:normal].nil? } ? 'a face of it has no area to push' : nil

        incident = Array.new(vertices.length) { [] }
        rows.each_with_index do |row, face_index|
            (row[:outer] + row[:inners].flatten).uniq.each { |i| incident[i] << face_index }
        end

        units   = []
        clamped = 0

        incident.each do |face_indices|
            solved   = Na__InsertPrimatives.Na__JointPush__UnitOffset(face_indices.map { |face_index| rows[face_index][:normal] })
            problem ||= 'two of its faces fold back on each other — SHIFT+TAB pushes one face' unless solved[:vector]
            clamped  += 1 if solved[:clamped]
            units << solved[:vector]
        end

        segments, interior   = Na__InsertPrimatives.Na__JointPush__Edges(rows, member, index, positions)
        lean, touches, free  = Na__InsertPrimatives.Na__JointPush__Neighbours(vertices, member, units, xform, segments)
        loops, loose         = Na__InsertPrimatives.Na__JointPush__Loops(segments)
        area_mm2             = faces.sum { |face| face.area(xform).to_f } * NA_DRAWN_INCH_TO_MM * NA_DRAWN_INCH_TO_MM

        {
            :reach       => Na__InsertPrimatives.Na__JointPush__Reach(rows, positions, units),
            :slide_reach => Na__InsertPrimatives.Na__JointPush__SlideReach(units, lean, touches, free),
            :faces     => faces,
            :face_set  => member,
            :xform     => xform,
            :vertices  => vertices,
            :positions => positions,
            :units     => units,
            :rows      => rows,
            :triangles => rows.flat_map { |row| row[:triangles] },
            :segments  => segments,
            :interior  => interior,
            :loops     => loops,
            :loose     => loose,
            :lean      => lean,
            :touches   => touches,
            :free      => free,
            :lone      => !touches.any?,
            :area      => format('%.2f', area_mm2 / 1_000_000.0),
            :count     => faces.length,
            :clamped   => clamped,
            :problem   => problem,
            :probe     => vertices.first(3).map { |vertex| [vertex, vertex.position.clone] }
        }
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Face's Own Triangulation, as Corner Indices
    # ------------------------------------------------------------
    # The preview shades these, a face that will not stay flat is folded
    # along them, and a rebuilt face that will not go in whole goes in as
    # them. Holes and concave outlines come out right because they are
    # SketchUp's own triangles.
    # ------------------------------------------------------------
    def self.Na__JointPush__FaceTriangles(face, index)
        lookup = {}
        face.vertices.each { |vertex| lookup[Na__InsertPrimatives.Na__JointPush__Key(vertex.position)] = index[vertex] }

        mesh      = face.mesh(0)
        triangles = []

        mesh.polygons.each do |polygon|
            next unless polygon.length == 3

            corners = polygon.map do |mesh_index|
                point = mesh.point_at(mesh_index.abs)
                lookup[Na__InsertPrimatives.Na__JointPush__Key(point)] ||
                    Na__InsertPrimatives.Na__JointPush__NearestCorner(face, index, point)
            end

            triangles << corners unless corners.include?(nil)
        end

        triangles
    rescue StandardError
        []
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Point Rounded for a Lookup
    # ------------------------------------------------------------
    def self.Na__JointPush__Key(point)
        [(point.x.to_f * 1000.0).round, (point.y.to_f * 1000.0).round, (point.z.to_f * 1000.0).round]
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Corner of a Face Nearest a Point, When the Rounded Key Missed
    # ------------------------------------------------------------
    def self.Na__JointPush__NearestCorner(face, index, point)
        best = face.vertices.min_by { |vertex| vertex.position.distance(point).to_f }
        return nil unless best && best.position.distance(point).to_f < NA_JOINT_POINT_TOL * 10.0

        index[best]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Sort the Surface's Edges Into Boundary and Interior
    # ------------------------------------------------------------
    # An edge with one face of the surface on it is the BOUNDARY, where walls
    # or stretching happen; with two or more it is INTERIOR, rebuilt with its
    # soft and smooth flags. Each boundary edge is kept the way its face runs
    # it, with the world direction pointing AWAY from that face (the wall's
    # outside), worked out from the loop's own winding rather than trusted to
    # an ordering convention.
    # ------------------------------------------------------------
    def self.Na__JointPush__Edges(rows, member, index, positions)
        segments = []
        interior = []
        seen     = {}

        rows.each_with_index do |row, face_index|
            normal = row[:normal]
            next unless normal

            row[:face].loops.each do |loop|
                corners   = loop.vertices
                ids       = corners.map { |vertex| index[vertex] }
                winding   = Na__InsertPrimatives.Na__JointPush__Newell(ids.map { |i| positions[i] }).dot(normal) > 0.0
                face_left = loop.outer? ? winding : !winding                  # <-- Walking the loop, is the face on the left?

                corners.each_with_index do |vertex, k|
                    other = corners[(k + 1) % corners.length]
                    edge  = vertex.common_edge(other)
                    next unless edge

                    a = index[vertex]
                    b = index[other]

                    if edge.faces.count { |face| member[face] } >= 2
                        next if seen[edge]

                        seen[edge] = true
                        interior << [edge, a, b]
                        next
                    end

                    along   = positions[b] - positions[a]
                    outward = face_left ? along.cross(normal) : normal.cross(along)
                    next if outward.length.to_f <= 0.0

                    segments << [a, b, face_index, outward.normalize, edge]
                end
            end
        end

        [segments, interior]
    end
    # ---------------------------------------------------------------

    # FUNCTION | What Each Corner Touches Beyond the Surface
    # ------------------------------------------------------------
    # :touches — a face that is not part of the surface uses this corner.
    # :lean    — the most any such face's normal leans along the corner's
    #            travel: 0 means every one of them contains it, so the
    #            corner can slide and they stretch in their own planes.
    # :free    — the corner ends an open boundary edge (no face beyond it),
    #            which needs a wall, so the corner must stay.
    # ------------------------------------------------------------
    def self.Na__JointPush__Neighbours(vertices, member, units, xform, segments)
        normals = {}
        lean    = Array.new(vertices.length, 0.0)
        touches = Array.new(vertices.length, false)
        free    = Array.new(vertices.length, false)

        segments.each do |a, b, _face_index, _outward, edge|
            next if edge.faces.any? { |face| !member[face] }

            free[a] = true
            free[b] = true
        end

        vertices.each_with_index do |vertex, i|
            outside = vertex.faces.reject { |face| member[face] }
            next if outside.empty?

            touches[i] = true
            unit       = units[i]
            next unless unit && unit.length.to_f > 0.0

            heading = unit.normalize

            outside.each do |face|
                normals[face] = Na__InsertPrimatives.Na__JointPush__WorldNormal(
                    face, face.outer_loop.vertices.map { |corner| corner.position.transform(xform) }, xform
                ) unless normals.key?(face)

                normal = normals[face]
                next unless normal

                tilt    = normal.dot(heading).abs.to_f
                lean[i] = tilt if tilt > lean[i]
            end
        end

        [lean, touches, free]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Chain the Boundary Into Closed Loops
    # ------------------------------------------------------------
    # Returns [loops, loose]: closed rings of corner indices for the quad
    # line and the loop cut, and open runs where a corner is pinched (two
    # boundary edges leave it), stitched a segment at a time instead.
    # ------------------------------------------------------------
    def self.Na__JointPush__Loops(segments)
        following = Hash.new { |hash, key| hash[key] = [] }
        segments.each { |a, b| following[a] << b }

        used  = {}
        loops = []
        loose = []

        segments.each do |a, b|
            next if used[[a, b]]

            used[[a, b]] = true
            ring         = [a]
            current      = b
            closed       = true

            until current == a
                options = following[current]

                unless options.length == 1 && !used[[current, options.first]]
                    closed = false
                    break
                end

                ring << current
                used[[current, options.first]] = true
                current = options.first
            end

            closed ? loops << ring : loose << (ring + [current])
        end

        [loops, loose]
    end
    # ---------------------------------------------------------------

    # FUNCTION | How Far the Surface Can Go Each Way Before a Face Turns Inside Out
    # ------------------------------------------------------------
    # Every corner of a face moves as p + d u, so the face's Newell vector
    # (the sum of p_i x p_i+1) is a quadratic in d: A + dB + d^2 C. The face
    # stays the right way out while that vector keeps NA_JOINT_MIN_AREA of
    # its starting direction, and the roots of the quadratic bound d. Solved
    # once per surface, so the live drag asks two comparisons instead of
    # re-measuring every face on every mouse move. Points are taken about
    # the face's own first corner, which leaves the sum unchanged and keeps
    # a face far from the origin from cancelling its own digits away.
    # Returns [lowest, highest], -Infinity / Infinity when unbounded.
    # ------------------------------------------------------------
    def self.Na__JointPush__Reach(rows, positions, units)
        lowest  = -Float::INFINITY
        highest = Float::INFINITY
        still   = Geom::Vector3d.new(0, 0, 0)

        rows.each do |row|
            ids  = row[:outer]
            base = positions[ids.first]
            a    = [0.0, 0.0, 0.0]
            b    = [0.0, 0.0, 0.0]
            c    = [0.0, 0.0, 0.0]

            ids.each_with_index do |i, k|
                j = ids[(k + 1) % ids.length]
                p = positions[i] - base
                q = positions[j] - base
                u = units[i] || still
                w = units[j] || still

                [[a, p, q], [b, p, w], [b, u, q], [c, u, w]].each do |sum, first, second|
                    sum[0] += (first.y * second.z) - (first.z * second.y)
                    sum[1] += (first.z * second.x) - (first.x * second.z)
                    sum[2] += (first.x * second.y) - (first.y * second.x)
                end
            end

            square = (a[0] * a[0]) + (a[1] * a[1]) + (a[2] * a[2])
            next if square <= 0.0

            c0 = (1.0 - NA_JOINT_MIN_AREA) * square
            c1 = (b[0] * a[0]) + (b[1] * a[1]) + (b[2] * a[2])
            c2 = (c[0] * a[0]) + (c[1] * a[1]) + (c[2] * a[2])

            Na__InsertPrimatives.Na__JointPush__Roots(c2, c1, c0).each do |root|
                if root > 0.0
                    highest = root if root < highest
                elsif root < 0.0
                    lowest = root if root > lowest
                end
            end
        end

        [lowest, highest]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Real Roots of c2 d^2 + c1 d + c0 (c0 > 0, so never at 0)
    # ------------------------------------------------------------
    def self.Na__JointPush__Roots(c2, c1, c0)
        scale = [c2.abs, c1.abs, c0.abs].max
        return [] if scale <= 0.0

        if c2.abs <= 1.0e-12 * scale
            return [] if c1.abs <= 1.0e-12 * scale

            return [-c0 / c1]
        end

        disc = (c1 * c1) - (4.0 * c2 * c0)
        return [] if disc < 0.0

        root = Math.sqrt(disc)
        [(-c1 - root) / (2.0 * c2), (-c1 + root) / (2.0 * c2)]
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Longest Push Every Corner Can Slide For
    # ------------------------------------------------------------
    # Slides? at a distance d is lean * |u| * |d| <= NA_JOINT_PLANE_TOL, so
    # each corner slides up to a distance of its own; the surface stretches
    # up to the shortest of them. 0 when a corner cannot slide at all (an
    # open edge, or no face round it); corners of the surface alone do not
    # count, they move with it whatever the route.
    # ------------------------------------------------------------
    def self.Na__JointPush__SlideReach(units, lean, touches, free)
        reach = Float::INFINITY

        units.each_index do |i|
            next if !touches[i] && !free[i]
            return 0.0 if free[i] || units[i].nil?

            tilt = lean[i].to_f * units[i].length.to_f
            next if tilt <= 0.0

            limit = NA_JOINT_PLANE_TOL / tilt
            reach = limit if limit < reach
        end

        reach
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is a Plan Still the Surface Standing There?
    # ------------------------------------------------------------
    # Hovering asks this on every move, so it is a handful of reads: every
    # face alive, the same transformation, and a few corners where they were.
    # ------------------------------------------------------------
    def self.Na__JointPush__Fresh?(plan, xform)
        return false unless plan
        return false unless plan[:faces].all?(&:valid?)
        return false unless Na__InsertPrimatives.Na__JointPush__SameTransform?(plan[:xform], xform)

        plan[:probe].all? { |vertex, point| vertex.valid? && vertex.position.distance(point).to_f < NA_JOINT_POINT_TOL }
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Are Two Transformations the Same Matrix?
    # ------------------------------------------------------------
    def self.Na__JointPush__SameTransform?(first, second)
        a = (first  || Geom::Transformation.new).to_a
        b = (second || Geom::Transformation.new).to_a

        a.each_with_index.all? { |value, i| (value.to_f - b[i].to_f).abs < 1.0e-9 }
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | At a Distance — Where Everything Goes, and Which Route
    # -----------------------------------------------------------------------------

    # FUNCTION | Every Corner's World Position After a Push of `distance`
    # ------------------------------------------------------------
    def self.Na__JointPush__Moved(plan, distance)
        d = distance.to_f

        plan[:positions].each_with_index.map do |point, i|
            unit = plan[:units][i]
            next point.clone unless unit

            Geom::Point3d.new(point.x + (unit.x * d), point.y + (unit.y * d), point.z + (unit.z * d))
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Can This Corner Slide, the Faces Round It Stretching?
    # ------------------------------------------------------------
    # Measured in how far the slide would carry the corner off the flattest
    # face round it, so a fraction of a degree of drawing error on a long push
    # walls the corner rather than bending its neighbour.
    # ------------------------------------------------------------
    def self.Na__JointPush__Slides?(plan, i, distance)
        return false unless plan[:touches][i] && !plan[:free][i]

        unit = plan[:units][i]
        return false unless unit

        plan[:lean][i].to_f * unit.length.to_f * distance.to_f.abs <= NA_JOINT_PLANE_TOL
    end
    # ---------------------------------------------------------------

    # FUNCTION | Which of the Three Routes a Push of `distance` Takes
    # ------------------------------------------------------------
    # Stretch while every corner can slide that far (the plan's slide reach,
    # see Na__JointPush__SlideReach), rebuild beyond it; a lone surface is
    # always thickened.
    # ------------------------------------------------------------
    def self.Na__JointPush__Route(plan, distance)
        return :thicken if plan[:lone] && !plan[:segments].empty?

        distance.to_f.abs <= plan[:slide_reach] ? :stretch : :rebuild
    end
    # ---------------------------------------------------------------

    # FUNCTION | Why a Push of `distance` Cannot Be Made, or nil
    # ------------------------------------------------------------
    # The plan's own problem first. Then the reach: pushed past the centre of
    # a tight curve a face turns inside out, which no rebuild can make sense
    # of, so the push is refused before it starts, saying how far it can go.
    # The reach compares each outline with ITSELF before the push, never
    # with the face's normal: a mirrored instance winds every loop the other
    # way round.
    # ------------------------------------------------------------
    def self.Na__JointPush__Problem(plan, distance)
        return 'nothing to push' unless plan
        return plan[:problem] if plan[:problem]

        d                = distance.to_f
        lowest, highest  = plan[:reach]
        return nil if d > lowest && d < highest

        limit = Na__InsertPrimatives.Na__DrawnFormat__Mm(d < 0.0 ? lowest : highest).abs.floor
        "the surface would turn inside out — the curve allows #{limit} mm #{d < 0.0 ? 'in' : 'out'} at most"
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Commit — Apply a Plan to the Model
    # -----------------------------------------------------------------------------

    # FUNCTION | Push a Plan's Surface by `distance`
    # ------------------------------------------------------------
    # Runs inside the caller's operation, on the collection the faces live in,
    # with a plan built in that collection's CURRENT reported space. Raises on
    # anything it cannot do, so the operation rolls back whole. `cut` is the
    # QUADS-inward loop cut: nothing moves, the ring is offset into the faces
    # round the surface. Returns what was done, for the console report.
    # ------------------------------------------------------------
    def self.Na__JointPush__Apply(entities, plan, distance, quads, cut)
        d      = distance.to_f
        xform  = plan[:xform]
        back   = xform.inverse
        news   = Na__InsertPrimatives.Na__JointPush__Moved(plan, d).map { |point| point.transform(back) }
        olds   = plan[:vertices].map { |vertex| vertex.position.clone }
        route  = Na__InsertPrimatives.Na__JointPush__Route(plan, d)
        stats  = { :route => route, :moved => 0, :rebuilt => 0, :walls => 0, :healed => 0, :cancelled => 0,
                   :folded => 0, :softened => 0, :quad => nil, :cut => false }

        if cut
            raise 'a loop cut needs every face round the surface to run with it' unless route == :stretch

            stats[:quad] = Na__InsertPrimatives.Na__JointPush__Stitch(
                entities,
                plan[:loops].map { |ring| ring.map { |i| news[i] } },
                plan[:loose].map { |chain| chain.map { |i| news[i] } }
            )
            stats[:cut] = true
            return stats
        end

        # The start loop, read before anything moves: QUADS puts it back.
        start_rings  = quads ? plan[:loops].map { |ring| ring.map { |i| olds[i].clone } } : []
        start_chains = quads ? plan[:loose].map { |chain| chain.map { |i| olds[i].clone } } : []

        if route == :stretch
            stats[:folded] = Na__InsertPrimatives.Na__JointPush__FoldBending(entities, plan, news)
            stats[:moved]  = Na__InsertPrimatives.Na__JointPush__MoveVertices(entities, plan[:vertices], olds, news)
        else
            Na__InsertPrimatives.Na__JointPush__Rebuild(entities, plan, d, olds, news, route == :thicken, quads, stats)
        end

        stats[:quad] = Na__InsertPrimatives.Na__JointPush__Stitch(entities, start_rings, start_chains) if quads
        stats
    end
    # ---------------------------------------------------------------

    # FUNCTION | Move Corners, Then Check Every One Arrived
    # ------------------------------------------------------------
    # transform_by_vectors reads its vectors in the collection's reported
    # space (global while open, local while closed), the space olds and
    # news are in. A corner that did not land is a refusal, never a guess.
    # ------------------------------------------------------------
    def self.Na__JointPush__MoveVertices(entities, vertices, olds, news)
        return 0 if vertices.empty?

        vectors = vertices.each_index.map { |i| news[i] - olds[i] }
        entities.transform_by_vectors(vertices, vectors)

        vertices.each_with_index do |vertex, i|
            next if vertex.valid? && vertex.position.distance(news[i]).to_f < NA_JOINT_LAND_TOL

            raise 'a corner did not land where the push sent it — nothing was changed'
        end

        vertices.length
    end
    # ---------------------------------------------------------------

    # FUNCTION | Fold Every Face of the Surface That Would Not Stay Flat
    # ------------------------------------------------------------
    # Only the surface's own faces can bend on the stretch route: a face round
    # it only ever has corners slid within its own plane. Folds run along the
    # face's own triangulation, soft and smooth, so it still reads as one.
    # ------------------------------------------------------------
    def self.Na__JointPush__FoldBending(entities, plan, news)
        folded = 0

        plan[:rows].each do |row|
            ids = row[:outer] + row[:inners].flatten
            next if Na__InsertPrimatives.Na__JointPush__Flat?(ids.map { |i| news[i] })

            folded += Na__InsertPrimatives.Na__JointPush__Fold(entities, plan, row)
        end

        folded
    end
    # ---------------------------------------------------------------

    # FUNCTION | Do These Points Still Lie in One Plane?
    # ------------------------------------------------------------
    def self.Na__JointPush__Flat?(points)
        return true if points.length <= 3

        plane = Geom.fit_plane_to_points(points)
        return true unless plane

        points.all? { |point| point.distance_to_plane(plane).to_f <= NA_JOINT_FLAT_TOL }
    rescue StandardError
        true
    end
    # ---------------------------------------------------------------

    # FUNCTION | Split One Face Along Its Own Triangulation
    # ------------------------------------------------------------
    def self.Na__JointPush__Fold(entities, plan, row)
        vertices = plan[:vertices]
        added    = 0

        row[:triangles].each do |triangle|
            3.times do |k|
                a = vertices[triangle[k]]
                b = vertices[triangle[(k + 1) % 3]]
                next if a == b || a.common_edge(b)

                edge = entities.add_line(a.position, b.position)
                next unless edge

                edge.soft   = true
                edge.smooth = true
                added      += 1
            end
        end

        added
    rescue StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "NA JOINT PUSH: could not fold a face — #{error.message}"
        added
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Rebuild and Thicken Routes
    # ------------------------------------------------------------
    # In order, each step depending on the one before:
    #   1. read what every face wears, and every interior edge's flags;
    #   2. REBUILD: erase the surface and its interior edges (the boundary
    #      edges stay, still bounding the faces round it), then slide the
    #      corners that can slide — the faces round them stretch;
    #   3. add the surface again one push out, face for face, wearing what
    #      it wore; THICKEN keeps the original as the back instead;
    #   4. wall every boundary edge with a corner that stayed;
    #   5. tidy: soften walls meeting on a curve, take back out walls lying
    #      over a face round them (an inward push), heal walls flat with a
    #      face round them into it (an outward push, QUADS off).
    # ------------------------------------------------------------
    def self.Na__JointPush__Rebuild(entities, plan, d, olds, news, keep, quads, stats)
        xform    = plan[:xform]
        vertices = plan[:vertices]
        slide    = Array.new(vertices.length) { |i| !keep && Na__InsertPrimatives.Na__JointPush__Slides?(plan, i, d) }

        # 1. Read before anything is erased.
        dress       = plan[:rows].map { |row| Na__InsertPrimatives.Na__JointPush__Dress(row[:face], row, olds) }
        inner_flags = plan[:interior].map { |edge, a, b| [a, b, Na__InsertPrimatives.Na__JointPush__EdgeFlags(edge)] }
        holes       = plan[:rows].map do |row|
            row[:face].loops.reject(&:outer?).map do |loop|
                loop.edges.any? { |edge| edge.faces.any? { |face| face != row[:face] && plan[:face_set][face] } }
            end
        end

        # 2. Clear the old surface and slide what can slide.
        unless keep
            doomed  = plan[:faces].select(&:valid?)
            doomed += plan[:interior].map(&:first).select { |edge| edge.valid? && edge.faces.all? { |face| plan[:face_set][face] } }
            entities.erase_entities(doomed) unless doomed.empty?
        end

        sliders = vertices.each_index.select { |i| slide[i] }
        unless sliders.empty?
            stats[:moved] = Na__InsertPrimatives.Na__JointPush__MoveVertices(
                entities, sliders.map { |i| vertices[i] }, sliders.map { |i| olds[i] }, sliders.map { |i| news[i] }
            )
        end

        # 3. The surface again, one push out.
        made = []

        plan[:rows].each_with_index do |row, k|
            wanted  = (keep && d < 0.0) ? row[:normal].reverse : row[:normal]
            pieces  = Na__InsertPrimatives.Na__JointPush__AddPolygon(
                entities, row[:outer].map { |i| news[i] }, row[:triangles].map { |triangle| triangle.map { |i| news[i] } }
            )
            raise 'a face of the surface could not be built at that distance' if pieces.empty?

            pieces.each { |face| Na__InsertPrimatives.Na__JointPush__Orient(face, wanted, xform) }

            if pieces.length == 1
                row[:inners].each_with_index do |ids, hole|
                    next if holes[k][hole]                                    # <-- Filled by another face of the surface, rebuilt in its own right

                    Na__InsertPrimatives.Na__JointPush__Punch(entities, ids.map { |i| news[i] })
                end
            end

            pieces.each { |face| Na__InsertPrimatives.Na__JointPush__Wear(face, dress[k], news) }
            made.concat(pieces)
        end

        stats[:rebuilt] = made.length

        lookup = Na__InsertPrimatives.Na__JointPush__VertexLookup(made)
        inner_flags.each do |a, b, flags|
            edge = Na__InsertPrimatives.Na__JointPush__EdgeBetween(lookup, news[a], news[b])
            Na__InsertPrimatives.Na__JointPush__SetEdgeFlags(edge, flags) if edge
        end

        # 4. Walls where a corner stayed.
        walls = []

        plan[:segments].each do |a, b, _face_index, outward, _edge|
            next if slide[a] && slide[b]

            points = []
            points << olds[a] unless slide[a]
            points << olds[b] unless slide[b]
            points << news[b] << news[a]
            points = Na__InsertPrimatives.Na__JointPush__Distinct(points)
            next if points.length < 3

            wanted = (keep || d >= 0.0) ? outward : outward.reverse
            pieces = Na__InsertPrimatives.Na__JointPush__AddPolygon(entities, points, Na__InsertPrimatives.Na__JointPush__SplitQuad(points))
            pieces.each { |face| Na__InsertPrimatives.Na__JointPush__Orient(face, wanted, xform) }
            walls.concat(pieces)
        end

        stats[:walls] = walls.length

        plan[:faces].each { |face| face.reverse! if face.valid? } if keep && d > 0.0

        # 5. Tidy.
        stats[:softened]  = Na__InsertPrimatives.Na__JointPush__SoftenTravel(plan, vertices, slide, olds, news, walls)
        stats[:cancelled] = Na__InsertPrimatives.Na__JointPush__CancelOverlaps(entities, walls, made)
        stats[:healed]    = quads ? 0 : Na__InsertPrimatives.Na__JointPush__HealWalls(walls, made)
        stats[:faces]     = keep ? [] : made.select(&:valid?)                 # <-- The rebuilt surface, for a selection to take up
        stats
    end
    # ---------------------------------------------------------------

    # FUNCTION | Add a Polygon, or Its Triangles When It Will Not Go In Flat
    # ------------------------------------------------------------
    # add_face refuses points that do not lie in one plane. The fallback is
    # the triangles handed in (the face's own triangulation, or a quad split
    # on its shorter diagonal), their shared edges soft and smooth.
    # ------------------------------------------------------------
    def self.Na__JointPush__AddPolygon(entities, points, triangles)
        face = nil

        begin
            face = entities.add_face(points)
        rescue StandardError
            face = nil
        end

        return [face] if face && face.valid?
        return [] unless triangles

        pieces = []

        triangles.each do |corners|
            begin
                piece = entities.add_face(corners)
                pieces << piece if piece && piece.valid?
            rescue StandardError
                next
            end
        end

        Na__InsertPrimatives.Na__JointPush__SoftenSeams(pieces)
        pieces
    end
    # ---------------------------------------------------------------

    # FUNCTION | Soften the Edges Shared Between Pieces of One Face
    # ------------------------------------------------------------
    def self.Na__JointPush__SoftenSeams(faces)
        return 0 if faces.length < 2

        member = {}
        faces.each { |face| member[face] = true }
        count = 0

        faces.flat_map(&:edges).uniq.each do |edge|
            next unless edge.faces.count { |face| member[face] } >= 2

            edge.soft   = true
            edge.smooth = true
            count      += 1
        end

        count
    end
    # ---------------------------------------------------------------

    # FUNCTION | Two Triangles for a Quad, Split on Its Shorter Diagonal
    # ------------------------------------------------------------
    def self.Na__JointPush__SplitQuad(points)
        return nil unless points.length == 4

        if points[0].distance(points[2]).to_f <= points[1].distance(points[3]).to_f
            [[points[0], points[1], points[2]], [points[0], points[2], points[3]]]
        else
            [[points[0], points[1], points[3]], [points[1], points[2], points[3]]]
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Drop Repeated Corners; Nothing If What Is Left Has No Area
    # ------------------------------------------------------------
    def self.Na__JointPush__Distinct(points)
        kept = []
        points.each { |point| kept << point unless kept.last && kept.last.distance(point).to_f < NA_JOINT_POINT_TOL }
        kept.pop while kept.length > 1 && kept.last.distance(kept.first).to_f < NA_JOINT_POINT_TOL

        return [] if kept.length < 3
        return [] if Na__InsertPrimatives.Na__JointPush__Newell(kept).length.to_f < 1.0e-8

        kept
    end
    # ---------------------------------------------------------------

    # FUNCTION | Turn a Face to Face a World Direction
    # ------------------------------------------------------------
    # Never trusted to point order: SketchUp turns a face drawn on the ground
    # at the model root to face down whatever the order. The face's true world
    # normal is read back and compared. Returns true when it was reversed.
    # ------------------------------------------------------------
    def self.Na__JointPush__Orient(face, wanted, xform)
        return false unless face && face.valid? && wanted

        world  = face.outer_loop.vertices.map { |vertex| vertex.position.transform(xform) }
        normal = Na__InsertPrimatives.Na__JointPush__WorldNormal(face, world, xform)
        return false unless normal
        return false if normal.dot(wanted) >= 0.0

        face.reverse!
        true
    end
    # ---------------------------------------------------------------

    # FUNCTION | Open a Hole in a Rebuilt Face Where the Original Had One
    # ------------------------------------------------------------
    # The rebuilt face goes in from its outline alone, which fills the hole.
    # Adding the hole's own outline splits that fill off as a face of its
    # own, and erasing it opens the hole again.
    # ------------------------------------------------------------
    def self.Na__JointPush__Punch(entities, points)
        fill = entities.add_face(points)
        fill.erase! if fill && fill.valid?
        true
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Everything a Face Wears, Read Before It Is Erased
    # ------------------------------------------------------------
    def self.Na__JointPush__Dress(face, row, olds)
        {
            :material => face.material,
            :back     => face.back_material,
            :layer    => face.layer,
            :hidden   => face.hidden?,
            :front_uv => Na__InsertPrimatives.Na__JointPush__UvPairs(face, row, olds, true),
            :back_uv  => Na__InsertPrimatives.Na__JointPush__UvPairs(face, row, olds, false)
        }
    rescue StandardError
        {}
    end
    # ---------------------------------------------------------------

    # FUNCTION | Three Corners' Texture Coordinates, to Pin the Texture Back On
    # ------------------------------------------------------------
    # nil for an untextured side. Three corners spread round the outline give
    # an affine fit, so a texture that ran across the old face runs across
    # the rebuilt one the same way.
    # ------------------------------------------------------------
    def self.Na__JointPush__UvPairs(face, row, olds, front)
        material = front ? face.material : face.back_material
        return nil unless material && material.respond_to?(:texture) && material.texture

        writer = Sketchup.create_texture_writer
        helper = face.get_UVHelper(front, !front, writer)
        outer  = row[:outer]
        picks  = [0, outer.length / 3, (2 * outer.length) / 3].uniq.map { |k| outer[k] }

        picks.map do |i|
            uvq = front ? helper.get_front_UVQ(olds[i]) : helper.get_back_UVQ(olds[i])
            q   = uvq.z.to_f
            q   = 1.0 if q.abs < 1.0e-12
            [i, Geom::Point3d.new(uvq.x.to_f / q, uvq.y.to_f / q, 1.0)]
        end
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Put a Face's Paint, Tag and Texture Position on Its Rebuild
    # ------------------------------------------------------------
    def self.Na__JointPush__Wear(face, dress, news)
        return false unless face && face.valid? && dress

        face.material      = dress[:material] if dress[:material]
        face.back_material = dress[:back]     if dress[:back]
        face.layer         = dress[:layer]    if dress[:layer]
        face.hidden        = true             if dress[:hidden]

        Na__InsertPrimatives.Na__JointPush__PlaceTexture(face, dress[:material], dress[:front_uv], news, true)
        Na__InsertPrimatives.Na__JointPush__PlaceTexture(face, dress[:back], dress[:back_uv], news, false)
        true
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Pin a Texture to the Rebuilt Corners
    # ------------------------------------------------------------
    def self.Na__JointPush__PlaceTexture(face, material, pairs, news, front)
        return false unless material && pairs && pairs.length >= 2

        face.position_material(material, pairs.flat_map { |i, uv| [news[i], uv] }, front)
        true
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | An Edge's Look, to Copy On to Its Rebuild
    # ------------------------------------------------------------
    def self.Na__JointPush__EdgeFlags(edge)
        { :soft => edge.soft?, :smooth => edge.smooth?, :hidden => edge.hidden?, :layer => edge.layer }
    rescue StandardError
        {}
    end
    # ---------------------------------------------------------------

    # FUNCTION | Give an Edge the Look Read Off Another
    # ------------------------------------------------------------
    def self.Na__JointPush__SetEdgeFlags(edge, flags)
        edge.soft   = flags[:soft]   ? true : false
        edge.smooth = flags[:smooth] ? true : false
        edge.hidden = flags[:hidden] ? true : false
        edge.layer  = flags[:layer] if flags[:layer]
        true
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Every Vertex of Some Faces, by Rounded Position
    # ------------------------------------------------------------
    def self.Na__JointPush__VertexLookup(faces)
        lookup = {}

        faces.each do |face|
            next unless face.valid?

            face.vertices.each { |vertex| lookup[Na__InsertPrimatives.Na__JointPush__Key(vertex.position)] ||= vertex }
        end

        lookup
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Edge Joining Two Points, Through a Vertex Lookup
    # ------------------------------------------------------------
    def self.Na__JointPush__EdgeBetween(lookup, first, second)
        a = lookup[Na__InsertPrimatives.Na__JointPush__Key(first)]
        b = lookup[Na__InsertPrimatives.Na__JointPush__Key(second)]
        return nil unless a && b && a.valid? && b.valid?

        a.common_edge(b)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Soften the Travel Edge Where Two Walls Meet on a Curve
    # ------------------------------------------------------------
    # A pushed circle's sides come out smooth in native Push/Pull; the walls
    # round a curved boundary should too. Two walls flatter than 35 degrees
    # apart are one curved side, and the edge between them is softened.
    # ------------------------------------------------------------
    def self.Na__JointPush__SoftenTravel(plan, vertices, slide, olds, news, walls)
        member = {}
        walls.each { |wall| member[wall] = true }
        lookup   = Na__InsertPrimatives.Na__JointPush__VertexLookup(walls)
        boundary = plan[:segments].flat_map { |a, b| [a, b] }.uniq
        count    = 0

        boundary.each do |i|
            next if slide[i]

            start  = vertices[i]
            finish = lookup[Na__InsertPrimatives.Na__JointPush__Key(news[i])]
            next unless start && start.valid? && finish && finish.valid?

            edge = start.common_edge(finish)
            next unless edge

            faces = edge.faces
            next unless faces.length == 2 && faces.all? { |face| member[face] }

            dot = faces[0].normal.dot(faces[1].normal)
            next if dot > NA_JOINT_COPLANAR_DOT || dot < NA_JOINT_SOFT_DOT

            edge.soft   = true
            edge.smooth = true
            count      += 1
        end

        count
    rescue StandardError
        count || 0
    end
    # ---------------------------------------------------------------

    # FUNCTION | Take Back Out Any Wall Lying Over a Face Round the Surface
    # ------------------------------------------------------------
    # Pushing IN where a corner had to stay, a wall can land flat on a face
    # round the surface, on the face's own side: that strip is outside the
    # solid now and the face should end at the new edge. SketchUp has already
    # cut the wall out of the face when it went in; it shows as a flat
    # neighbour facing the other way. The wall is erased and any edge left
    # holding nothing goes with it.
    # ------------------------------------------------------------
    def self.Na__JointPush__CancelOverlaps(entities, walls, made)
        member = {}
        walls.each { |wall| member[wall] = true }
        made.each  { |face| member[face] = true }
        count = 0

        walls.each do |wall|
            next unless wall.valid?

            over = wall.edges.any? do |edge|
                edge.faces.any? do |other|
                    other.valid? && !member[other] && Na__InsertPrimatives.Na__JointPush__Flush(wall, other) == :opposite
                end
            end
            next unless over

            edges = wall.edges
            wall.erase!
            orphans = edges.select { |edge| edge.valid? && edge.faces.empty? }
            entities.erase_entities(orphans) unless orphans.empty?
            count += 1
        end

        count
    end
    # ---------------------------------------------------------------

    # FUNCTION | Are Two Faces Sharing an Edge Truly One Plane?
    # ------------------------------------------------------------
    # :same, :opposite, or nil. Strict on purpose: erasing the edge between
    # two faces merges them only when SketchUp itself calls them coplanar;
    # a hair out and it takes BOTH faces with it. So the normals must pass
    # SketchUp's own samedirection? and every corner of one face must lie on
    # the other's plane, or the seam is left standing.
    # ------------------------------------------------------------
    def self.Na__JointPush__Flush(first, second)
        a = first.normal
        b = second.normal

        kind = if a.samedirection?(b) then :same
               elsif a.samedirection?(b.reverse) then :opposite
               end
        return nil unless kind

        plane = first.plane
        return nil unless second.vertices.all? { |vertex| vertex.position.distance_to_plane(plane).to_f <= NA_JOINT_FLAT_TOL }

        kind
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Heal Walls Into the Flat Faces Beside Them
    # ------------------------------------------------------------
    # Native Push/Pull welds a new wall into a coplanar face it grew from and
    # deletes the line between them. The same here, and between coplanar
    # walls, never against the rebuilt surface. A face round the surface
    # lends its paint and tag to the wall first, so whichever of the two
    # SketchUp keeps, the merged face wears the paint the model had.
    # ------------------------------------------------------------
    def self.Na__JointPush__HealWalls(walls, made)
        wall_set = {}
        walls.each { |wall| wall_set[wall] = true }
        made_set = {}
        made.each { |face| made_set[face] = true }
        count = 0

        walls.select(&:valid?).flat_map(&:edges).uniq.each do |edge|
            next unless edge.valid?

            faces = edge.faces
            next unless faces.length == 2
            next if faces.any? { |face| made_set[face] }
            next unless faces.any? { |face| wall_set[face] }
            next unless Na__InsertPrimatives.Na__JointPush__Flush(faces[0], faces[1]) == :same

            keeper = faces.find { |face| !wall_set[face] }
            Na__InsertPrimatives.Na__JointPush__LendPaint(keeper, faces.find { |face| face != keeper }) if keeper

            edge.erase!
            count += 1
        end

        count
    rescue StandardError
        count || 0
    end
    # ---------------------------------------------------------------

    # FUNCTION | Paint a Wall Like the Face It Is About to Merge Into
    # ------------------------------------------------------------
    def self.Na__JointPush__LendPaint(from, to)
        return false unless from && to && from.valid? && to.valid?

        to.material      = from.material
        to.back_material = from.back_material
        to.layer         = from.layer
        true
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Draw Boundary Lines Back In: Closed Rings, Then Loose Runs
    # ------------------------------------------------------------
    # Rings go through the quad ring's own stitch (it takes back the fill a
    # closed coplanar ring makes); a run that is not a ring is drawn a
    # segment at a time. A line that lands on no face bounds nothing and is
    # swept back off, so the worst case leaves the model as QUADS off would.
    # ------------------------------------------------------------
    def self.Na__JointPush__Stitch(entities, rings, chains)
        stats = { :kept => 0, :swept => 0, :faces_removed => 0, :misplaced => false }

        unless rings.empty?
            ringed = Na__InsertPrimatives.Na__PushPull__StitchQuadRing(entities, rings, Geom::Transformation.new)
            stats.each_key { |key| stats[key] = key == :misplaced ? (stats[key] || ringed[key]) : stats[key] + ringed[key].to_i }
        end

        chains.each do |points|
            points.each_cons(2) do |a, b|
                edge = nil

                begin
                    edge = entities.add_line(a, b)
                rescue StandardError
                    edge = nil
                end

                next unless edge && edge.valid?

                if edge.faces.empty?
                    edge.erase!
                    stats[:swept] += 1
                else
                    stats[:kept] += 1
                end
            end
        end

        stats
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP PUSH PULL JOINT GEOMETRY
# =============================================================================
