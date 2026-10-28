# =============================================================================
# NA INSERT PRIMATIVES - DEEP PROJECT GEOMETRY
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnProject__Geometry__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Where every corner of a face lands when it is carried on to a
#              target plane, a point or an object — world-space maths only
# CREATED    : 2026
#
# DESCRIPTION:
# - Deep Project runs a face on until it reaches something: the plane of a
#   face picked anywhere in the model, the level of a point, or the first
#   thing of another object it would touch. This file answers the one
#   question the preview, the commit and the retype ghost all ask — where
#   does each corner go — so the three can never disagree about it.
# - Nothing here changes the model. The object scan reads it; everything
#   else is points in and points out, all of them world.
#
# ONE PARAMETER FOR EVERY DIRECTION:
# - Each corner travels along its own MOTION vector m, scaled so that
#   m . normal = 1: one unit of m lifts the corner one unit off the face's own
#   plane. A plain projection gives every corner m = the normal. SHIFT, an
#   arrow key or a picked edge give every corner the same tilted m. SHIFT+ALT
#   gives each corner the m of the edge it follows. So a corner's whole
#   journey is one number, its height h, and it lands at V + h m.
# - Dividing by the dot with the normal also makes m SENSE-FREE: turn a
#   direction end for end and m does not change. A plane is reached whichever
#   side of the face it lies on — in front, the face is carried out to it;
#   behind, the face is cut back to it. Only an object, which is found by
#   looking, needs telling which way to look.
#
# THE THREE TARGETS:
# - PLANE   Every corner on to the plane on its own:
#             h = (P0 - V) . np / (m . np)
#           so the end face lands IN the plane however the plane is tilted.
#           Wall tops up to a roof pitch, a beam end on to a raking wall.
# - POINT   The plane through the point, parallel to the face. Every corner
#           rises the same height: native Push/Pull's push-to-a-vertex, at
#           any nesting depth, along any of the directions.
# - OBJECT  The face travels rigidly — every corner the same height — and
#           stops where it first touches the object: a corner reaching one
#           of its triangles, one of its vertices reaching the face, or one
#           of its edges crossing the strip an edge of the face sweeps. The
#           end face stays parallel to where it started, just touching.
#
# THE OFFSET:
# - Positive stops short of the target, negative runs past it. A plane, or a
#   point's plane, is moved square to itself toward the face, so 25 is an
#   exact 25mm clearance however the plane is tilted. An object's contact is
#   pulled back along the travel.
#
# CUT AND EXTEND (5.2.2):
# - A target plane that passes THROUGH the face is not a refusal. Each corner
#   runs along its motion to the plane, out if the plane is in front of it,
#   back if it is behind, and the face lands flat on the target: the end of a
#   box trimmed and extended to a slope in one click. The way is :mixed.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnGridSnap__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Project Constants
    # -----------------------------------------------------------------------------

    NA_PROJECT_MIN_FACTOR = 0.0872                                            # <-- Cos 85 degrees; a direction this near the face cannot carry it
    NA_PROJECT_MIN_MEET   = 0.0087                                            # <-- Sin 0.5 degrees; a travel this near a target plane never meets it
    NA_PROJECT_TOL        = 0.004                                             # <-- Inches (~0.1mm); a corner this near its target is on it
    NA_PROJECT_MAX_TRAVEL = 2000.m                                            # <-- Further than this and the target is all but parallel
    NA_PROJECT_SCAN_LIMIT = 40_000                                            # <-- Triangles; an object bigger than this is not swept against
    NA_PROJECT_SCAN_DEPTH = 24                                                # <-- Nesting levels the object scan walks down
    NA_PROJECT_EPS        = 1.0e-9
    NA_PROJECT_EDGE_SLACK = 1.0e-6                                            # <-- A crossing this far past an end of an edge still counts

    # Said by the preview and, as a backstop, by the commit, so the two can
    # never word the one refusal of a cut and extend differently.
    NA_PROJECT_MIXED_REFUSAL = 'that target cuts through the face, and the faces round it do not run along the travel — ' \
                               'SHIFT+ALT cuts and extends each corner along its own edge instead'.freeze

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Motion
    # -----------------------------------------------------------------------------

    # FUNCTION | A Direction as a Motion: One Unit Lifts the Corner One Unit
    # ------------------------------------------------------------
    # nil when the direction lies too close to the face to carry it anywhere.
    # The default limit is the cos 85 the push tool's axis lock refuses at; a
    # followed edge passes its own, looser limit (Na__FollowPush__RailAt
    # already refused the rails that lie in the face), so FOLLOW passes 0.
    # ------------------------------------------------------------
    def self.Na__Project__Motion(direction, normal, minimum = NA_PROJECT_MIN_FACTOR)
        return nil unless direction && normal
        return nil unless direction.length.to_f > 0.0

        unit  = direction.normalize
        along = unit.dot(normal).to_f
        return nil if along.abs < NA_PROJECT_EPS
        return nil if along.abs < minimum.to_f

        Geom::Vector3d.new(unit.x.to_f / along, unit.y.to_f / along, unit.z.to_f / along)
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Corner Lifted a Height Along Its Motion
    # Longhand, so a height of nothing is a legal answer rather than the
    # zero-length offset Point3d#offset refuses.
    # ------------------------------------------------------------
    def self.Na__Project__Lift(point, motion, height)
        Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(point, motion, height.to_f)
    end
    # ---------------------------------------------------------------

    # FUNCTION | How High a Corner Must Rise Along Its Motion to Meet a Plane
    # nil when the motion all but lies in the plane: it would never get there.
    # ------------------------------------------------------------
    def self.Na__Project__HeightToPlane(point, motion, plane)
        origin, normal = plane
        along          = motion.dot(normal).to_f
        return nil if along.abs < NA_PROJECT_MIN_MEET * motion.length.to_f

        (origin - point).dot(normal).to_f / along
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Point Rounded for a Lookup Key
    # The same rounding the push tool's follow lookup uses: a thousandth of
    # an inch, far below anything SketchUp will keep apart.
    # ------------------------------------------------------------
    def self.Na__Project__PointKey(point)
        [(point.x.to_f * 1000.0).round, (point.y.to_f * 1000.0).round, (point.z.to_f * 1000.0).round]
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Target Planes
    # -----------------------------------------------------------------------------

    # FUNCTION | The Plane a Source Is Carried To, With the Offset Applied
    # ------------------------------------------------------------
    # A point target becomes the plane through it parallel to THIS face, so two
    # preselected faces at different angles each get their own. The offset
    # moves the plane square to itself, toward the face's side of it, which is
    # what makes 25 a 25mm clearance however the plane is tilted.
    # ------------------------------------------------------------
    def self.Na__Project__PlaneFor(source, target, offset)
        origin, normal = Na__InsertPrimatives.Na__Project__BarePlane(source, target)
        return nil unless origin && normal

        side   = (source[:centroid] - origin).dot(normal).to_f
        toward = side < 0.0 ? normal.reverse : normal

        [Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(origin, toward, offset.to_f), normal]
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Target's Own Plane for a Source, Before Any Offset
    # ------------------------------------------------------------
    def self.Na__Project__BarePlane(source, target)
        case target[:kind]
        when :plane then target[:plane]
        when :point then [Na__InsertPrimatives.Na__Project__PointLevel(source, target), source[:normal]]
        else             nil
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Where a Point Target Puts the Face's Plane
    # CTRL+SHIFT rounds the height onto the grid, the way the push tool rounds
    # a vertex-snapped travel: the vertex says roughly how far, the grid says
    # exactly how far.
    # ------------------------------------------------------------
    def self.Na__Project__PointLevel(source, target)
        point = target[:point]
        return point unless target[:round]

        height  = (point - source[:origin]).dot(source[:normal]).to_f
        rounded = Na__InsertPrimatives.Na__DrawnGrid__SnapDistance(height)

        Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(source[:origin], source[:normal], rounded)
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Solving One Face
    # -----------------------------------------------------------------------------

    # FUNCTION | Where Every Corner of One Face Lands
    # ------------------------------------------------------------
    # source    built by the tool: :loops (world, outer first), :motions
    #           (parallel to :loops), :reaches (how far each corner can run
    #           back: along its rail in FOLLOW, along the solid's own edge
    #           for a cut back; nil where nothing limits it), :normal,
    #           :origin, :centroid, :uniform, :key, :problem
    # target    :kind (:plane / :point / :object) and its own data
    # settings  :offset (inches; + short, - past) and :sense (:auto / 1.0 / -1.0)
    #
    # Returns { :ok => true, :loops, :heights, :travels, :way, :lookup, ... }
    # or { :ok => false, :reason }. The reason is a sentence for the status bar:
    # a projection refused without saying why reads as a broken tool.
    # ------------------------------------------------------------
    def self.Na__Project__Solve(source, target, settings)
        return Na__InsertPrimatives.Na__Project__Refused('there is no face to project') unless source
        return Na__InsertPrimatives.Na__Project__Refused('there is nothing to project to yet') unless target
        return Na__InsertPrimatives.Na__Project__Refused(source[:problem]) if source[:problem]
        return Na__InsertPrimatives.Na__Project__Refused(target[:refusal]) if target[:refusal]

        offset = (settings || {})[:offset].to_f
        found  =
            if target[:kind] == :object
                Na__InsertPrimatives.Na__Project__HeightsToObject(source, target, offset, (settings || {})[:sense])
            else
                Na__InsertPrimatives.Na__Project__HeightsToPlane(source, target, offset)
            end
        return found unless found[:ok]

        Na__InsertPrimatives.Na__Project__Land(source, found)
    rescue StandardError => error
        Na__InsertPrimatives.Na__Project__Refused("the corners could not be solved (#{error.message})")
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Refusal, in the Shape Every Caller Reads
    # ------------------------------------------------------------
    def self.Na__Project__Refused(reason)
        { :ok => false, :reason => reason.to_s }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Every Corner's Height to a Plane or a Point's Plane
    # ------------------------------------------------------------
    def self.Na__Project__HeightsToPlane(source, target, offset)
        if target[:kind] == :point
            level = Na__InsertPrimatives.Na__Project__PointLevel(source, target)
            lift  = (level - source[:origin]).dot(source[:normal]).to_f
            return Na__InsertPrimatives.Na__Project__Refused('that point is level with the face already') if lift.abs < NA_PROJECT_TOL
        end

        plane = Na__InsertPrimatives.Na__Project__PlaneFor(source, target, offset)
        return Na__InsertPrimatives.Na__Project__Refused('that target has no plane to reach') unless plane

        heights = source[:loops].each_with_index.map do |points, loop_index|
            points.each_with_index.map do |point, index|
                height = Na__InsertPrimatives.Na__Project__HeightToPlane(point, source[:motions][loop_index][index], plane)

                if height.nil?
                    return Na__InsertPrimatives.Na__Project__Refused('the face would travel parallel to that plane and never reach it')
                end

                height
            end
        end

        { :ok => true, :heights => heights, :plane => plane }
    end
    # ---------------------------------------------------------------

    # FUNCTION | One Rigid Height for Every Corner, to Where the Face First Touches an Object
    # ------------------------------------------------------------
    # The offset is measured along the travel for a single direction, so 25
    # stops the face 25mm back along its path from the touch. FOLLOW has no
    # single path, so there it is measured off the face's own plane.
    # ------------------------------------------------------------
    def self.Na__Project__HeightsToObject(source, target, offset, sense)
        contact = Na__InsertPrimatives.Na__Project__CachedContact(source, target, sense)
        name    = target[:name] || 'that object'

        unless contact
            return Na__InsertPrimatives.Na__Project__Refused(
                sense.is_a?(Numeric) ? "nothing of #{name} lies that way — DOWN looks the other way" :
                                       "nothing of #{name} lies in the face's path either way"
            )
        end

        scale = source[:uniform] ? source[:motions][0][0].length.to_f : 1.0
        scale = 1.0 unless scale > 0.0
        lift  = contact[:height].to_f - (offset.to_f / scale)

        if lift <= NA_PROJECT_TOL
            gap = Na__InsertPrimatives.Na__DrawnFormat__Mm(contact[:height].to_f * scale).abs
            return Na__InsertPrimatives.Na__Project__Refused("the offset is more than the #{gap} mm gap to #{name}")
        end

        height  = contact[:sense].to_f * lift
        heights = source[:loops].map { |points| Array.new(points.length, height) }

        { :ok => true, :heights => heights, :sense => contact[:sense], :contact => contact }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Turn Heights Into Landed Corners, Refusing the Ones That Cannot Go
    # ------------------------------------------------------------
    # Two refusals belong here rather than in the commit, so the preview shows
    # them before the click rather than the click discovering them: a target so
    # near parallel that the face would travel kilometres, and a corner run back
    # past the far end of the edge it follows or of the solid.
    #
    # A target that CROSSES the face is not refused (5.2.2). The corners in
    # front of it run out to it and the ones behind run back to it — CUT AND
    # EXTEND, :mixed — and the face lands flat on the target. Whether that can
    # be built is the commit's question: it can when the faces round this one
    # hold the travel, so they lengthen on one side and shorten on the other.
    # ------------------------------------------------------------
    def self.Na__Project__Land(source, found)
        heights = found[:heights]
        way     = Na__InsertPrimatives.Na__Project__Way(heights.flatten)

        return Na__InsertPrimatives.Na__Project__Refused('the face lies on that target already') if way == :none

        loops   = []
        travels = []
        lookup  = {}

        source[:loops].each_with_index do |points, loop_index|
            landed = []
            spans  = []

            points.each_with_index do |point, index|
                motion = source[:motions][loop_index][index]
                height = heights[loop_index][index]
                dest   = Na__InsertPrimatives.Na__Project__Lift(point, motion, height)
                travel = dest.distance(point).to_f

                if travel > NA_PROJECT_MAX_TRAVEL.to_f
                    metres = (travel * NA_DRAWN_INCH_TO_MM / 1000.0).round
                    return Na__InsertPrimatives.Na__Project__Refused("that target is #{metres} m away — the travel all but runs along it")
                end

                reach = source[:reaches] ? source[:reaches][loop_index][index] : nil
                if reach && height < 0.0 && travel > reach.to_f + NA_PROJECT_TOL
                    limit = Na__InsertPrimatives.Na__DrawnFormat__Mm(reach).abs
                    words = source[:uniform] ? 'that is past the far end of the solid' : 'past the end of an edge it follows'
                    return Na__InsertPrimatives.Na__Project__Refused("#{words} — #{limit} mm in is the most there")
                end

                landed << dest
                spans  << travel
                lookup[Na__InsertPrimatives.Na__Project__PointKey(point)] = dest
            end

            loops   << landed
            travels << spans
        end

        found.merge(:ok => true, :loops => loops, :travels => travels, :way => way, :lookup => lookup)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Which Way the Face Is Going: :out, :in, :none or :mixed
    # ------------------------------------------------------------
    def self.Na__Project__Way(heights)
        out    = heights.any? { |height| height.to_f >  NA_PROJECT_TOL }
        inward = heights.any? { |height| height.to_f < -NA_PROJECT_TOL }

        return :mixed if out && inward
        return :out   if out
        return :in    if inward

        :none
    end
    # ---------------------------------------------------------------

    # FUNCTION | Where Any Point of the Face Goes
    # ------------------------------------------------------------
    # A corner is looked up. Anything else — a triangulation point SketchUp
    # added inside a concave face — is carried by the face's average motion
    # to the same plane, or by the same rigid height, so a preview triangle
    # can never tear away from the corners round it.
    # ------------------------------------------------------------
    def self.Na__Project__Carry(source, solution, point)
        found = solution[:lookup][Na__InsertPrimatives.Na__Project__PointKey(point)]
        return found if found

        motion = source[:average_motion] || source[:motions][0][0]
        height =
            if solution[:plane]
                Na__InsertPrimatives.Na__Project__HeightToPlane(point, motion, solution[:plane])
            else
                solution[:heights][0][0]
            end

        Na__InsertPrimatives.Na__Project__Lift(point, motion, height.to_f)
    rescue StandardError
        point
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Shortest and Longest Corner Travel, as Text
    # ------------------------------------------------------------
    def self.Na__Project__TravelText(travels)
        flat = travels.flatten
        return '0' if flat.empty?

        low  = Na__InsertPrimatives.Na__DrawnFormat__Mm(flat.min).abs
        high = Na__InsertPrimatives.Na__DrawnFormat__Mm(flat.max).abs
        low == high ? low.to_s : "#{low}–#{high}"
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Cut and Extend as Text: "cut back 120, extend 394 mm"
    # ------------------------------------------------------------
    # The furthest any corner runs back and the furthest any runs out, across
    # every face being projected.
    # ------------------------------------------------------------
    def self.Na__Project__CutExtendText(solutions)
        back = 0.0
        out  = 0.0

        solutions.each do |solution|
            solution[:heights].flatten.each_with_index do |height, index|
                travel = solution[:travels].flatten[index].to_f
                height.to_f < 0.0 ? (back = travel if travel > back) : (out = travel if travel > out)
            end
        end

        "cut back #{Na__InsertPrimatives.Na__DrawnFormat__Mm(back).abs}, extend #{Na__InsertPrimatives.Na__DrawnFormat__Mm(out).abs} mm"
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Object Scan
    # -----------------------------------------------------------------------------

    # FUNCTION | Everything of an Object the Face Could Touch, as World Floats
    # ------------------------------------------------------------
    # Returns { :triangles => [[a, b, c]], :edges => [[p, q]], :vertices => [p],
    # :count, :truncated } with every point an [x, y, z] Float array: the
    # contact sweep runs these millions of times, and plain Floats are many
    # times quicker than Geom objects for it.
    #
    # Hidden geometry, and geometry on a hidden tag, is left out — a face
    # cannot be stopped by something the user cannot see. Nested groups and
    # components are walked down, each through its own transformation, so the
    # object is the whole thing under the cursor, not just its top level.
    # ------------------------------------------------------------
    def self.Na__Project__ScanInstance(instance, xform)
        return nil unless instance && instance.valid? && instance.respond_to?(:definition)

        state = { :triangles => [], :edges => [], :vertices => {}, :truncated => false }
        Na__InsertPrimatives.Na__Project__ScanEntities(
            instance.definition.entities, xform || Geom::Transformation.new, state, 0
        )

        {
            :triangles => state[:triangles],
            :edges     => state[:edges],
            :vertices  => state[:vertices].values,
            :count     => state[:triangles].length,
            :truncated => state[:truncated]
        }
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Walk One Collection Into the Scan
    # ------------------------------------------------------------
    def self.Na__Project__ScanEntities(entities, xform, state, depth)
        return if depth > NA_PROJECT_SCAN_DEPTH

        entities.each do |entity|
            return if state[:truncated]
            next unless Na__InsertPrimatives.Na__Project__Visible?(entity)

            case entity
            when Sketchup::Face
                Na__InsertPrimatives.Na__Project__ScanFace(entity, xform, state)
            when Sketchup::Edge
                start  = Na__InsertPrimatives.Na__Project__Xyz(entity.start.position.transform(xform))
                finish = Na__InsertPrimatives.Na__Project__Xyz(entity.end.position.transform(xform))

                state[:edges] << [start, finish]
                state[:vertices][start]  ||= start
                state[:vertices][finish] ||= finish
            when Sketchup::Group, Sketchup::ComponentInstance
                Na__InsertPrimatives.Na__Project__ScanEntities(
                    entity.definition.entities, xform * entity.transformation, state, depth + 1
                )
            end
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | One Face's Triangles Into the Scan
    # ------------------------------------------------------------
    def self.Na__Project__ScanFace(face, xform, state)
        mesh = face.mesh

        mesh.polygons.each do |polygon|
            next unless polygon.length == 3

            state[:triangles] << polygon.map do |index|
                Na__InsertPrimatives.Na__Project__Xyz(mesh.point_at(index.abs).transform(xform))
            end
        end

        state[:truncated] = true if state[:triangles].length > NA_PROJECT_SCAN_LIMIT
    end
    # ---------------------------------------------------------------

    # FUNCTION | Can the User See This Entity?
    # ------------------------------------------------------------
    def self.Na__Project__Visible?(entity)
        return false if entity.respond_to?(:hidden?) && entity.hidden?

        layer = entity.respond_to?(:layer) ? entity.layer : nil
        return false if layer && layer.respond_to?(:visible?) && !layer.visible?

        true
    rescue StandardError
        true
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Point or Vector as Three Floats
    # ------------------------------------------------------------
    def self.Na__Project__Xyz(point)
        [point.x.to_f, point.y.to_f, point.z.to_f]
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Scan of an Object, Read Once Per Placement
    # ------------------------------------------------------------
    # Hovering one object for a while asks for the same scan on every mouse
    # move. Keyed by the instance AND where it stands, so a moved object is
    # read again. The tool forgets every scan when it starts, after it places
    # and after an undo — the three moments the object could have changed.
    # ------------------------------------------------------------
    def self.Na__Project__CachedScan(instance, xform)
        return nil unless instance && instance.valid?

        cache = (@na_project_scans ||= {})
        key   = [instance.entityID, (xform || Geom::Transformation.new).to_a.map { |value| value.to_f.round(6) }]
        return cache[key] if cache.key?(key)

        cache.clear if cache.length > 8
        cache[key] = Na__InsertPrimatives.Na__Project__ScanInstance(instance, xform)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Forget Every Cached Scan
    # ------------------------------------------------------------
    def self.Na__Project__ForgetScans
        @na_project_scans = {}
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | First Contact With an Object
    # -----------------------------------------------------------------------------

    # FUNCTION | The Contact for a Source, Solved Once Per Object and Direction
    # Kept on the target itself, so it lives exactly as long as the hover on
    # that object does, and the retype ghost reuses it at every frame.
    # ------------------------------------------------------------
    def self.Na__Project__CachedContact(source, target, sense)
        memo = (target[:memo] ||= {})
        key  = [source[:key], sense]
        return memo[key] if memo.key?(key)

        memo[key] = Na__InsertPrimatives.Na__Project__Contact(source, target[:scan], sense)
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Nearest Contact, Looking One Way or Both
    # ------------------------------------------------------------
    # :auto looks outward first (the side the face faces) and only then back
    # through it, so an object on the face's own side always wins; a numeric
    # sense looks that way only. Returns { :height, :sense } or nil.
    # ------------------------------------------------------------
    def self.Na__Project__Contact(source, scan, sense)
        senses = sense.is_a?(Numeric) ? [sense.to_f] : [1.0, -1.0]

        senses.each do |each_sense|
            height = Na__InsertPrimatives.Na__Project__ContactHeight(source, scan, each_sense)
            return { :height => height, :sense => each_sense } if height
        end

        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | How High the Face Rises Before It First Touches an Object
    # ------------------------------------------------------------
    # Three ways two shapes first meet, and the answer is the earliest:
    #   CORNER  a corner of the face, carried along its motion, reaches a triangle
    #   POINT   a vertex of the object is reached by the rising face itself
    #   EDGE    an edge of the object crosses the strip an edge of the face sweeps
    # The third is the one a corner-and-vertex test alone misses: two squares
    # turned 45 degrees to each other meet edge to edge, nowhere near a corner
    # of either.
    #
    # The height is a count of the corner's own motion (sense applied), so it
    # is the face's lift off its plane. Contacts at no lift at all are not
    # contacts — the object is merely touching where the face starts.
    # ------------------------------------------------------------
    def self.Na__Project__ContactHeight(source, scan, sense)
        return nil unless scan

        normal  = Na__InsertPrimatives.Na__Project__Xyz(source[:normal])
        loops   = source[:loops].map { |points| points.map { |point| Na__InsertPrimatives.Na__Project__Xyz(point) } }
        motions = source[:motions].map do |row|
            row.map do |motion|
                [motion.x.to_f * sense, motion.y.to_f * sense, motion.z.to_f * sense]
            end
        end

        triangles = scan[:triangles]
        vertices  = scan[:vertices]
        edges     = scan[:edges]

        # One direction for the whole face means a shadow: nothing outside the
        # face's own outline, seen down the travel, can ever be reached. On a
        # large object that discards almost everything before any real test.
        if source[:uniform]
            frame  = Na__InsertPrimatives.Na__Project__ShadowFrame(motions[0][0])
            window = Na__InsertPrimatives.Na__Project__ShadowWindow(loops, frame)

            triangles = triangles.select { |points| Na__InsertPrimatives.Na__Project__InWindow?(points, frame, window) }
            vertices  = vertices.select  { |point|  Na__InsertPrimatives.Na__Project__InWindow?([point], frame, window) }
            edges     = edges.select     { |points| Na__InsertPrimatives.Na__Project__InWindow?(points, frame, window) }
        end

        origin = loops[0][0]
        best   = nil
        best   = Na__InsertPrimatives.Na__Project__CornerHits(loops, motions, triangles, best)
        best   = Na__InsertPrimatives.Na__Project__VertexHits(loops, motions, normal, origin, sense, vertices, best)
        Na__InsertPrimatives.Na__Project__EdgeHits(loops, motions, normal, sense, edges, best)
    end
    # ---------------------------------------------------------------

    # FUNCTION | CORNER — Every Corner's Ray Against Every Triangle
    # ------------------------------------------------------------
    def self.Na__Project__CornerHits(loops, motions, triangles, best)
        loops.each_with_index do |points, loop_index|
            points.each_with_index do |corner, index|
                motion = motions[loop_index][index]

                triangles.each do |a, b, c|
                    hit = Na__InsertPrimatives.Na__Project__RayTriangle(corner, motion, a, b, c)
                    next unless hit && hit > NA_PROJECT_TOL

                    best = hit if best.nil? || hit < best
                end
            end
        end

        best
    end
    # ---------------------------------------------------------------

    # FUNCTION | POINT — Every Object Vertex Against the Face Risen to Meet It
    # ------------------------------------------------------------
    def self.Na__Project__VertexHits(loops, motions, normal, origin, sense, vertices, best)
        vertices.each do |point|
            height = sense * Na__InsertPrimatives.Na__Project__Dot(
                Na__InsertPrimatives.Na__Project__Sub(point, origin), normal
            )
            next unless height > NA_PROJECT_TOL
            next if best && height >= best

            risen = loops.each_with_index.map do |points, loop_index|
                points.each_with_index.map do |corner, index|
                    motion = motions[loop_index][index]
                    [corner[0] + motion[0] * height, corner[1] + motion[1] * height, corner[2] + motion[2] * height]
                end
            end
            next unless Na__InsertPrimatives.Na__Project__InsideLoops?(point, risen, normal)

            best = height
        end

        best
    end
    # ---------------------------------------------------------------

    # FUNCTION | EDGE — Every Object Edge Against the Strip Each Face Edge Sweeps
    # ------------------------------------------------------------
    # The strip an edge sweeps is flat: along one direction it is the plane of
    # the edge and that direction, and in FOLLOW it is the neighbouring face's
    # own plane, which holds the rails at both ends. So an object edge is cut
    # with that plane, and the crossing is then checked to lie between the
    # two corners at the height it was reached.
    # ------------------------------------------------------------
    def self.Na__Project__EdgeHits(loops, motions, normal, sense, edges, best)
        loops.each_with_index do |points, loop_index|
            count = points.length

            count.times do |index|
                following = (index + 1) % count
                start     = points[index]
                finish    = points[following]
                lift_a    = motions[loop_index][index]
                lift_b    = motions[loop_index][following]
                along     = Na__InsertPrimatives.Na__Project__Sub(finish, start)
                across    = Na__InsertPrimatives.Na__Project__Cross(along, lift_a)
                next if Na__InsertPrimatives.Na__Project__Dot(across, across) < NA_PROJECT_EPS

                edges.each do |c, d|
                    run   = Na__InsertPrimatives.Na__Project__Sub(d, c)
                    meet  = Na__InsertPrimatives.Na__Project__Dot(run, across)
                    next if meet.abs < NA_PROJECT_EPS

                    share = Na__InsertPrimatives.Na__Project__Dot(Na__InsertPrimatives.Na__Project__Sub(start, c), across) / meet
                    next if share < -NA_PROJECT_EDGE_SLACK || share > 1.0 + NA_PROJECT_EDGE_SLACK

                    cross  = [c[0] + run[0] * share, c[1] + run[1] * share, c[2] + run[2] * share]
                    height = sense * Na__InsertPrimatives.Na__Project__Dot(Na__InsertPrimatives.Na__Project__Sub(cross, start), normal)
                    next unless height > NA_PROJECT_TOL
                    next if best && height >= best

                    risen_a = [start[0]  + lift_a[0] * height, start[1]  + lift_a[1] * height, start[2]  + lift_a[2] * height]
                    risen_b = [finish[0] + lift_b[0] * height, finish[1] + lift_b[1] * height, finish[2] + lift_b[2] * height]
                    span    = Na__InsertPrimatives.Na__Project__Sub(risen_b, risen_a)
                    reach   = Na__InsertPrimatives.Na__Project__Dot(span, span)
                    next if reach < NA_PROJECT_EPS

                    alpha = Na__InsertPrimatives.Na__Project__Dot(Na__InsertPrimatives.Na__Project__Sub(cross, risen_a), span) / reach
                    next if alpha < -NA_PROJECT_EDGE_SLACK || alpha > 1.0 + NA_PROJECT_EDGE_SLACK

                    on_edge = [risen_a[0] + span[0] * alpha, risen_a[1] + span[1] * alpha, risen_a[2] + span[2] * alpha]
                    off     = Na__InsertPrimatives.Na__Project__Sub(cross, on_edge)
                    next if Na__InsertPrimatives.Na__Project__Dot(off, off) > (NA_PROJECT_TOL * 4.0) ** 2

                    best = height
                end
            end
        end

        best
    end
    # ---------------------------------------------------------------

    # FUNCTION | Ray Against Triangle (Moller-Trumbore), in Units of the Ray Vector
    # ------------------------------------------------------------
    def self.Na__Project__RayTriangle(origin, ray, a, b, c)
        e1x = b[0] - a[0]
        e1y = b[1] - a[1]
        e1z = b[2] - a[2]
        e2x = c[0] - a[0]
        e2y = c[1] - a[1]
        e2z = c[2] - a[2]

        px = ray[1] * e2z - ray[2] * e2y
        py = ray[2] * e2x - ray[0] * e2z
        pz = ray[0] * e2y - ray[1] * e2x

        det = e1x * px + e1y * py + e1z * pz
        return nil if det.abs < 1.0e-12

        inv = 1.0 / det
        tx  = origin[0] - a[0]
        ty  = origin[1] - a[1]
        tz  = origin[2] - a[2]

        u = (tx * px + ty * py + tz * pz) * inv
        return nil if u < -NA_PROJECT_EDGE_SLACK || u > 1.0 + NA_PROJECT_EDGE_SLACK

        qx = ty * e1z - tz * e1y
        qy = tz * e1x - tx * e1z
        qz = tx * e1y - ty * e1x

        v = (ray[0] * qx + ray[1] * qy + ray[2] * qz) * inv
        return nil if v < -NA_PROJECT_EDGE_SLACK || u + v > 1.0 + NA_PROJECT_EDGE_SLACK

        (e2x * qx + e2y * qy + e2z * qz) * inv
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is a Point Inside a Face's Loops? (Even-Odd, So Holes Are Holes)
    # ------------------------------------------------------------
    # The loops are flattened onto the two axes the normal leans on least,
    # which keeps the test well conditioned at any tilt.
    # ------------------------------------------------------------
    def self.Na__Project__InsideLoops?(point, loops, normal)
        nx = normal[0].abs
        ny = normal[1].abs
        nz = normal[2].abs

        a, b =
            if    nz >= nx && nz >= ny then [0, 1]
            elsif ny >= nx              then [0, 2]
            else                             [1, 2]
            end

        px     = point[a]
        py     = point[b]
        inside = false

        loops.each do |points|
            count = points.length
            last  = count - 1

            count.times do |index|
                xi = points[index][a]
                yi = points[index][b]
                xj = points[last][a]
                yj = points[last][b]

                if (yi > py) != (yj > py)
                    crossing = xi + (py - yi) * (xj - xi) / (yj - yi)
                    inside   = !inside if px < crossing
                end

                last = index
            end
        end

        inside
    end
    # ---------------------------------------------------------------

    # FUNCTION | Two Axes Square to the Travel, for the Shadow Test
    # ------------------------------------------------------------
    def self.Na__Project__ShadowFrame(motion)
        length = Math.sqrt(Na__InsertPrimatives.Na__Project__Dot(motion, motion))
        unit   = [motion[0] / length, motion[1] / length, motion[2] / length]
        helper = unit[2].abs < 0.9 ? [0.0, 0.0, 1.0] : [1.0, 0.0, 0.0]

        first  = Na__InsertPrimatives.Na__Project__Cross(helper, unit)
        size   = Math.sqrt(Na__InsertPrimatives.Na__Project__Dot(first, first))
        first  = [first[0] / size, first[1] / size, first[2] / size]
        second = Na__InsertPrimatives.Na__Project__Cross(unit, first)

        [first, second]
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Face's Outline Seen Down the Travel, as a Padded Window
    # ------------------------------------------------------------
    def self.Na__Project__ShadowWindow(loops, frame)
        us = []
        vs = []

        loops.each do |points|
            points.each do |point|
                us << Na__InsertPrimatives.Na__Project__Dot(point, frame[0])
                vs << Na__InsertPrimatives.Na__Project__Dot(point, frame[1])
            end
        end

        pad = NA_PROJECT_TOL * 4.0
        [us.min - pad, us.max + pad, vs.min - pad, vs.max + pad]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Does Anything of These Points Fall Inside the Window?
    # ------------------------------------------------------------
    def self.Na__Project__InWindow?(points, frame, window)
        us = points.map { |point| Na__InsertPrimatives.Na__Project__Dot(point, frame[0]) }
        vs = points.map { |point| Na__InsertPrimatives.Na__Project__Dot(point, frame[1]) }

        us.max >= window[0] && us.min <= window[1] && vs.max >= window[2] && vs.min <= window[3]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Float-Array Vector Arithmetic
    # ------------------------------------------------------------
    def self.Na__Project__Sub(a, b)
        [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
    end

    def self.Na__Project__Dot(a, b)
        a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
    end

    def self.Na__Project__Cross(a, b)
        [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | The Last Target (Double-Click Repeat)
    # -----------------------------------------------------------------------------

    # FUNCTION | Remember What the Last Projection Reached
    # ------------------------------------------------------------
    # Held on the module rather than in the model: a target is a plane, a
    # point or a live object, not a number the tool memory dictionary could
    # carry, and an object would not survive a reopened file anyway. It does
    # survive switching tools and coming back, which is when it is wanted.
    # ------------------------------------------------------------
    def self.Na__Project__RememberLast(target)
        @na_project_last = target
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Last Target, or nil When It Can No Longer Be Reached
    # ------------------------------------------------------------
    def self.Na__Project__Last
        last = @na_project_last
        return nil unless last
        return nil if last[:kind] == :object && !(last[:instance] && last[:instance].valid?)

        last
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP PROJECT GEOMETRY
# =============================================================================
