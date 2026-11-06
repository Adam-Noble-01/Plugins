# =============================================================================
# NA NOBLE DRAWING TOOLS - DEEP PROJECT SECTIONS
# =============================================================================
#
# FILE       : Na__NobleDrawingTools__DrawnProject__Sections__.rb
# NAMESPACE  : Na__NobleDrawingTools
# AUTHOR     : Noble Architecture
# PURPOSE    : Carry only the parts of a face that actually meet the target,
#              splitting the face where the target ends (5.2.31, the default)
# CREATED    : 2026
#
# DESCRIPTION:
# - Before 5.2.31 a target face was an endless PLANE: every corner of the face
#   ran on to it, even where the target face itself stopped short. Now the
#   target is the face as drawn. Each part of the face is carried along the
#   travel until it meets the target; a part that would pass the target by
#   stays where it is, and the face is broken along the line where the two
#   meet. An OBJECT target is read the same way: each part lands on the first
#   face of the object it reaches, so a wall top climbs both slopes of a hip.
# - The old behaviour is the FULL FACE option in the right-click menu under
#   the tool: the whole face to the target's plane, or rigidly to first
#   contact with an object.
#
# HOW THE SECTIONS ARE FOUND (no SketchUp API, world floats only):
# - Everything happens in the face's own plane. The target's outline is
#   carried back down the travel on to that plane: its SHADOW. One uniform
#   motion m with m . n = 1 makes that one subtraction: s = t - ((t - O) . n) m.
# - The face's loops and every shadow are thrown together as line segments,
#   cut wherever they cross or touch, and the faces of that drawing are walked
#   (an arrangement). Each cell of it is asked once, at a point just inside
#   one of its edges, what it meets: nothing (it stays), or which landing
#   plane. Coplanar faces of an object are one landing.
# - A CUT is an edge of the drawing with a different answer on each side,
#   both inside the face. The cuts are the lines drawn on the face before
#   anything moves; with no cuts and one answer everywhere, the face is
#   carried whole by the routes that always carried it.
#
# HOW A SPLIT FACE IS BUILT (the explicit sweep, inside the open context):
# - The cuts are drawn, so the face falls into pieces. Each moving piece gets
#   its landed face, and every edge round it a wall from the height on one
#   side to the height on the other, facing the lower side. That one rule
#   covers carrying out, cutting back, a cut and extend (the wall becomes two
#   triangles where the heights cross) and two pieces landing at different
#   heights side by side. The moving pieces are then erased.
# - The faces round the original face are honoured as pushpull would:
#     runs along the travel, going out   the wall is its continuation; the
#                                        seam is healed unless QUADS
#     runs along the travel, going back  it is trimmed to the target
#     anything else, going back          only when the cut stays inside the
#                                        solid there; otherwise refused
# - Everything is checked before the operation commits: a piece that did not
#   split cleanly, a trim that ran off the end of the solid, a landed face
#   that did not survive. One failure rolls the lot back.
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__NobleDrawingTools__DrawnProject__Geometry__'

module Na__NobleDrawingTools

    # -----------------------------------------------------------------------------
    # REGION | Section Constants
    # -----------------------------------------------------------------------------

    NA_PROJECT_SECTION_SNAP      = 2.0e-4                                    # <-- Inches; drawing points closer than this are one point
    NA_PROJECT_SECTION_PROBE     = 4.0e-3                                    # <-- Inches; how far inside an edge a cell is sampled
    NA_PROJECT_SECTION_MAX_EDGES = 4000                                      # <-- Segments; past this the face is not split
    NA_PROJECT_SECTION_MAX_POLYS = 800                                       # <-- Object faces in the face's shadow
    NA_PROJECT_SECTION_AREA_TOL  = 1.0e-6                                    # <-- Square inches; a cell smaller than this is a sliver

    NA_PROJECT_FULL_FACE_OPTION  = 'project_full_face'.freeze                # <-- Declared in NA_TOOL_OPTIONS under :drawn_project

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Does Section Mode Apply?
    # -----------------------------------------------------------------------------

    # FUNCTION | Section Mode Answers for This Face and Target, or Leaves It to the Old Routes
    # ------------------------------------------------------------
    # A point has no outline and FOLLOW has no single travel to cast a shadow
    # along, so both keep carrying the whole face.
    # ------------------------------------------------------------
    def self.Na__ProjectSections__Applies?(source, target, settings)
        return false unless settings && settings[:sections]
        return false unless source && target && source[:uniform]
        return false unless source[:motions] && source[:motions][0] && source[:motions][0][0]
        return false unless [:plane, :object].include?(target[:kind])
        return false if target[:kind] == :plane && !target[:loops]
        return false if target[:kind] == :object && !(target[:scan] && target[:scan][:faces])

        true
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Solving the Sections
    # -----------------------------------------------------------------------------

    # FUNCTION | Which Parts of the Face Meet the Target, and Where They Land
    # ------------------------------------------------------------
    # Returns one of:
    #   { :ok => false, :reason }                          refused
    #   { :ok => true, :whole => true, :plane => [o, n] }  one landing for the
    #                                                      whole face: the old
    #                                                      routes carry it
    #   { :ok => true, :sections => {...}, :loops, :starts, :heights,
    #     :travels, :way, :plane => nil, :lookup => {}, :sense }
    # The split itself (the arrangement and every cell's answer) is kept on
    # the target per face, direction and sense: only the landing heights
    # depend on the offset, so a retyped offset re-solves in no time.
    # ------------------------------------------------------------
    def self.Na__ProjectSections__Solve(source, target, settings, force = false)
        offset = (settings || {})[:offset].to_f
        split  = Na__NobleDrawingTools.Na__ProjectSections__CachedSplit(source, target, (settings || {})[:sense])
        return split unless split[:ok]

        classes = Na__NobleDrawingTools.Na__ProjectSections__Classes(source, split, offset)
        cells   = split[:cells].select { |cell| cell[:class].is_a?(Integer) }
        name    = target[:name] || 'the target'

        if cells.empty?
            return Na__NobleDrawingTools.Na__Project__Refused(
                "no part of the face meets #{name} along this direction — Full Face (right-click menu) carries it to the plane"
            )
        end

        whole = split[:cuts].empty? && split[:cells].all? { |cell| cell[:class] == cells.first[:class] }
        if whole && !force
            return { :ok => true, :whole => true, :plane => classes[cells.first[:class]][:bare], :sense => split[:sense] }
        end

        frame   = split[:frame]
        motion  = frame[:m]
        built   = []
        heights = []

        cells.each do |cell|
            plane  = classes[cell[:class]][:plane]
            loops  = [cell[:outer]] + cell[:holes]
            starts = []
            landed = []
            rises  = []
            spans  = []

            loops.each do |points|
                row_start  = []
                row_landed = []
                row_rise   = []
                row_span   = []

                points.each do |point|
                    world  = Na__NobleDrawingTools.Na__ProjectSections__From2d(frame, point)
                    height = Na__NobleDrawingTools.Na__ProjectSections__HeightToPlane(world, motion, plane)
                    return Na__NobleDrawingTools.Na__Project__Refused('a part of the face would travel parallel to the target and never reach it') if height.nil?

                    dest   = Na__NobleDrawingTools.Na__ProjectSections__Lift(world, motion, height)
                    travel = Math.sqrt(Na__NobleDrawingTools.Na__Project__Dot(Na__NobleDrawingTools.Na__Project__Sub(dest, world), Na__NobleDrawingTools.Na__Project__Sub(dest, world)))

                    if travel > NA_PROJECT_MAX_TRAVEL.to_f
                        metres = (travel * NA_DRAWN_INCH_TO_MM / 1000.0).round
                        return Na__NobleDrawingTools.Na__Project__Refused("that target is #{metres} m away — the travel all but runs along it")
                    end

                    row_start  << Na__NobleDrawingTools.Na__ProjectSections__Point(world)
                    row_landed << Na__NobleDrawingTools.Na__ProjectSections__Point(dest)
                    row_rise   << height
                    row_span   << travel
                end

                starts << row_start
                landed << row_landed
                rises  << row_rise
                spans  << row_span
            end

            heights.concat(rises.flatten)
            built << {
                :class     => cell[:class],
                :starts    => starts,
                :landed    => landed,
                :heights   => rises,
                :travels   => spans,
                :triangles => cell[:triangles]
            }
        end

        way = Na__NobleDrawingTools.Na__Project__Way(heights)
        return Na__NobleDrawingTools.Na__Project__Refused('the face lies on that target already') if way == :none

        sections = {
            :frame    => frame,
            :classes  => classes,
            :cells    => built,
            :cuts     => split[:cuts].map { |pair| pair.map { |point| Na__NobleDrawingTools.Na__ProjectSections__Point(Na__NobleDrawingTools.Na__ProjectSections__From2d(frame, point)) } },
            :classify => split[:classify],
            :face2d   => split[:face2d],
            :stays    => split[:cells].any? { |cell| cell[:class] == :static }
        }

        {
            :ok       => true,
            :sections => sections,
            :loops    => built.map { |cell| cell[:landed][0] },
            :starts   => built.map { |cell| cell[:starts][0] },
            :heights  => built.map { |cell| cell[:heights][0] },
            :travels  => built.map { |cell| cell[:travels][0] },
            :way      => way,
            :plane    => nil,
            :lookup   => {},
            :sense    => split[:sense]
        }
    rescue StandardError => error
        Na__NobleDrawingTools.Na__Project__Refused("the sections could not be solved (#{error.message})")
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Split for a Face, a Target and a Sense, Worked Out Once
    # ------------------------------------------------------------
    def self.Na__ProjectSections__CachedSplit(source, target, sense)
        memo = (target[:memo] ||= {})
        key  = [:sections, source[:key], sense.is_a?(Numeric) ? sense.to_f : :auto]
        return memo[key] if memo.key?(key)

        memo.delete(memo.keys.first) if memo.length > 24
        memo[key] = Na__NobleDrawingTools.Na__ProjectSections__Split(source, target, sense)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Every Landing Plane, With the Offset Applied
    # ------------------------------------------------------------
    # The offset moves each plane square to itself toward the face's side of
    # it, exactly as Na__Project__PlaneFor does a single target's.
    # ------------------------------------------------------------
    def self.Na__ProjectSections__Classes(source, split, offset)
        centroid = Na__NobleDrawingTools.Na__Project__Xyz(source[:centroid])

        split[:planes].map do |origin, normal|
            side   = Na__NobleDrawingTools.Na__Project__Dot(Na__NobleDrawingTools.Na__Project__Sub(centroid, origin), normal)
            toward = side < 0.0 ? normal.map { |value| -value } : normal
            moved  = [origin[0] + toward[0] * offset, origin[1] + toward[1] * offset, origin[2] + toward[2] * offset]

            {
                :plane => [moved, normal],
                :bare  => [Na__NobleDrawingTools.Na__ProjectSections__Point(origin), Na__NobleDrawingTools.Na__ProjectSections__Vector(normal)]
            }
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Cast the Target on to the Face, Draw Them Together, Ask Every Cell
    # ------------------------------------------------------------
    def self.Na__ProjectSections__Split(source, target, sense)
        frame  = Na__NobleDrawingTools.Na__ProjectSections__Frame(source)
        face2d = source[:loops].map { |points| points.map { |point| Na__NobleDrawingTools.Na__ProjectSections__To2d(frame, Na__NobleDrawingTools.Na__Project__Xyz(point)) } }
        box    = Na__NobleDrawingTools.Na__ProjectSections__Box(face2d)
        name   = target[:name] || 'the target'

        found = Na__NobleDrawingTools.Na__ProjectSections__Polygons(source, target, frame, box)
        return found unless found[:ok]

        polys = found[:polys]
        if polys.empty?
            return Na__NobleDrawingTools.Na__Project__Refused(
                "no part of the face meets #{name} along this direction — Full Face (right-click menu) carries it to the plane"
            )
        end

        loops = face2d + polys.flat_map { |poly| poly[:shadow] }
        count = loops.inject(0) { |sum, points| sum + points.length }
        return Na__NobleDrawingTools.Na__Project__Refused("#{name} has too much under the face to split it by — Full Face carries it whole") if count > NA_PROJECT_SECTION_MAX_EDGES

        drawing = Na__NobleDrawingTools.Na__ProjectSections__Arrange(loops)
        senses  = target[:kind] == :object ? (sense.is_a?(Numeric) ? [sense.to_f] : [1.0, -1.0]) : [1.0]

        senses.each do |each_sense|
            state = { :face2d => face2d, :polys => polys, :mode => target[:kind], :sense => each_sense, :frame => frame }
            classify = Na__NobleDrawingTools.Na__ProjectSections__Classifier(state)
            cells, cuts = Na__NobleDrawingTools.Na__ProjectSections__Cells(drawing, classify)
            next unless cells.any? { |cell| cell[:class].is_a?(Integer) }

            used = cells.map { |cell| cell[:class] }.select { |value| value.is_a?(Integer) }.uniq.sort
            return {
                :ok       => true,
                :frame    => frame,
                :face2d   => face2d,
                :cells    => cells,
                :cuts     => cuts,
                :planes   => found[:planes],
                :classify => classify,
                :sense    => target[:kind] == :object ? each_sense : nil,
                :used     => used
            }
        end

        Na__NobleDrawingTools.Na__Project__Refused(
            target[:kind] == :object && sense.is_a?(Numeric) ?
                "no part of the face meets #{name} that way — DOWN looks the other way" :
                "no part of the face meets #{name} along this direction — Full Face (right-click menu) carries it to the plane"
        )
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Target as Shadows on the Face's Plane, Each With Its Landing Plane
    # ------------------------------------------------------------
    # Returns { :ok, :polys => [{ :shadow, :box, :class, :hit }], :planes }.
    # :hit is the bare plane an object face is reached on (first contact
    # decides which face a cell meets); :class indexes :planes, one per plane,
    # so coplanar faces of an object land as one.
    # ------------------------------------------------------------
    def self.Na__ProjectSections__Polygons(source, target, frame, box)
        motion = frame[:m]
        length = Math.sqrt(Na__NobleDrawingTools.Na__Project__Dot(motion, motion))
        polys  = []
        planes = []
        index  = {}

        candidates =
            if target[:kind] == :plane
                origin, normal = target[:plane]
                [{ :loops => target[:loops], :plane => [Na__NobleDrawingTools.Na__Project__Xyz(origin), Na__NobleDrawingTools.Na__ProjectSections__Unit(Na__NobleDrawingTools.Na__Project__Xyz(normal))] }]
            else
                target[:scan][:faces]
            end

        candidates.each do |candidate|
            loops = candidate[:loops].map { |points| points.map { |point| point.is_a?(Array) ? point : Na__NobleDrawingTools.Na__Project__Xyz(point) } }
            next if loops.empty? || loops[0].length < 3

            plane = candidate[:plane] || Na__NobleDrawingTools.Na__ProjectSections__PlaneOf(loops[0])
            next unless plane

            origin, normal = plane
            next if Na__NobleDrawingTools.Na__Project__Dot(motion, normal).abs < NA_PROJECT_MIN_MEET * length

            shadow = loops.map { |points| points.map { |point| Na__NobleDrawingTools.Na__ProjectSections__Shadow2d(frame, point) } }
            area   = Na__NobleDrawingTools.Na__ProjectSections__Area(shadow[0]).abs
            next if area < NA_PROJECT_SECTION_AREA_TOL

            outline = Na__NobleDrawingTools.Na__ProjectSections__Box(shadow)
            next unless Na__NobleDrawingTools.Na__ProjectSections__Overlap?(outline, box)

            # One plane however it faces: turned to face along the travel, and
            # keyed finely enough that only truly coplanar faces share it.
            normal = normal.map { |value| -value } if Na__NobleDrawingTools.Na__Project__Dot(normal, motion) < 0.0
            key    = normal.map { |value| (value * 1.0e5).round } + [(Na__NobleDrawingTools.Na__Project__Dot(origin, normal) * 1.0e3).round]

            unless index.key?(key)
                index[key] = planes.length
                planes << [origin, normal]
            end

            polys << { :shadow => shadow, :box => outline, :class => index[key], :hit => [origin, normal] }

            if polys.length > NA_PROJECT_SECTION_MAX_POLYS
                return Na__NobleDrawingTools.Na__Project__Refused("#{target[:name]} has too many faces under this one to split it by — Full Face carries it whole")
            end
        end

        { :ok => true, :polys => polys, :planes => planes }
    end
    # ---------------------------------------------------------------

    # FUNCTION | What Any Point of the Face Meets: nil Outside It, :static, or a Landing
    # ------------------------------------------------------------
    # A face target: inside its shadow it lands, outside it stays, and the
    # plane may be in front of the face or behind it (cut and extend). An
    # object: the first of its faces reached along the travel, that way.
    # ------------------------------------------------------------
    def self.Na__ProjectSections__Classifier(state)
        face2d = state[:face2d]
        polys  = state[:polys]
        frame  = state[:frame]
        motion = frame[:m]
        sense  = state[:sense].to_f
        object = state[:mode] == :object

        lambda do |point|
            next nil unless Na__NobleDrawingTools.Na__ProjectSections__Inside?(point, face2d)

            unless object
                hit = polys.find do |poly|
                    Na__NobleDrawingTools.Na__ProjectSections__InBox?(point, poly[:box]) &&
                        Na__NobleDrawingTools.Na__ProjectSections__Inside?(point, poly[:shadow])
                end
                next hit ? hit[:class] : :static
            end

            world = Na__NobleDrawingTools.Na__ProjectSections__From2d(frame, point)
            best  = nil
            found = :static

            polys.each do |poly|
                next unless Na__NobleDrawingTools.Na__ProjectSections__InBox?(point, poly[:box])
                next unless Na__NobleDrawingTools.Na__ProjectSections__Inside?(point, poly[:shadow])

                height = Na__NobleDrawingTools.Na__ProjectSections__HeightToPlane(world, motion, poly[:hit])
                next unless height

                ahead = height * sense
                next unless ahead > NA_PROJECT_TOL
                next if best && ahead >= best

                best  = ahead
                found = poly[:class]
            end

            found
        end
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | The Arrangement — Segments Cut Where They Meet, Faces Walked
    # -----------------------------------------------------------------------------

    # FUNCTION | Throw Loops Together, Cut Every Segment Where Another Meets It
    # ------------------------------------------------------------
    # Returns { :points => [[u, v]], :edges => [[i, j]] }, every edge whole
    # between two drawing points and none repeated. Points within the snap of
    # each other are one point, so a target edge lying along an edge of the
    # face becomes that edge rather than a sliver beside it.
    # ------------------------------------------------------------
    def self.Na__ProjectSections__Arrange(loops)
        pool     = { :points => [], :grid => {} }
        segments = {}

        loops.each do |points|
            count = points.length
            count.times do |index|
                a = Na__NobleDrawingTools.Na__ProjectSections__PointId(pool, points[index])
                b = Na__NobleDrawingTools.Na__ProjectSections__PointId(pool, points[(index + 1) % count])
                next if a == b

                segments[[a, b].minmax] ||= { :a => a, :b => b, :on => [] }
            end
        end

        list = segments.values
        pts  = pool[:points]
        list.each do |segment|
            pa = pts[segment[:a]]
            pb = pts[segment[:b]]
            segment[:x0] = [pa[0], pb[0]].min
            segment[:x1] = [pa[0], pb[0]].max
            segment[:y0] = [pa[1], pb[1]].min
            segment[:y1] = [pa[1], pb[1]].max
        end
        list.sort_by! { |segment| segment[:x0] }

        snap = NA_PROJECT_SECTION_SNAP
        list.each_with_index do |first, index|
            ((index + 1)...list.length).each do |other|
                second = list[other]
                break if second[:x0] > first[:x1] + snap
                next if second[:y0] > first[:y1] + snap || second[:y1] < first[:y0] - snap

                Na__NobleDrawingTools.Na__ProjectSections__Meet(pool, first, second)
            end
        end

        edges = {}
        list.each do |segment|
            chain = [segment[:a]] + segment[:on].sort_by { |t, _id| t }.map { |_t, id| id } + [segment[:b]]
            chain.each_cons(2) do |a, b|
                next if a == b

                edges[[a, b].minmax] = true
            end
        end

        { :points => pool[:points], :edges => edges.keys }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Where Two Segments Meet: a Crossing, or an End Lying on the Other
    # ------------------------------------------------------------
    def self.Na__ProjectSections__Meet(pool, first, second)
        pts  = pool[:points]
        snap = NA_PROJECT_SECTION_SNAP

        [[first, second], [second, first]].each do |host, guest|
            [guest[:a], guest[:b]].each do |id|
                next if id == host[:a] || id == host[:b]

                t = Na__NobleDrawingTools.Na__ProjectSections__OnSegment(pts[id], pts[host[:a]], pts[host[:b]], snap)
                host[:on] << [t, id] if t
            end
        end

        p = pts[first[:a]]
        q = pts[first[:b]]
        r = pts[second[:a]]
        s = pts[second[:b]]
        d1 = [q[0] - p[0], q[1] - p[1]]
        d2 = [s[0] - r[0], s[1] - r[1]]
        cross = d1[0] * d2[1] - d1[1] * d2[0]
        len1  = Math.sqrt(d1[0] * d1[0] + d1[1] * d1[1])
        len2  = Math.sqrt(d2[0] * d2[0] + d2[1] * d2[1])
        return if cross.abs <= 1.0e-12 * len1 * len2

        w = [r[0] - p[0], r[1] - p[1]]
        t = (w[0] * d2[1] - w[1] * d2[0]) / cross
        u = (w[0] * d1[1] - w[1] * d1[0]) / cross
        return if t * len1 <= snap || (1.0 - t) * len1 <= snap
        return if u * len2 <= snap || (1.0 - u) * len2 <= snap

        id = Na__NobleDrawingTools.Na__ProjectSections__PointId(pool, [p[0] + d1[0] * t, p[1] + d1[1] * t])
        first[:on]  << [t, id] unless id == first[:a] || id == first[:b]
        second[:on] << [u, id] unless id == second[:a] || id == second[:b]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Where Along a Segment a Point Lies, If It Lies On It Between the Ends
    # ------------------------------------------------------------
    def self.Na__ProjectSections__OnSegment(point, start, finish, snap)
        dx = finish[0] - start[0]
        dy = finish[1] - start[1]
        squared = dx * dx + dy * dy
        return nil if squared <= 0.0

        t = ((point[0] - start[0]) * dx + (point[1] - start[1]) * dy) / squared
        length = Math.sqrt(squared)
        return nil if t * length <= snap || (1.0 - t) * length <= snap

        nx = start[0] + dx * t - point[0]
        ny = start[1] + dy * t - point[1]
        nx * nx + ny * ny <= snap * snap ? t : nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | The One Id of a Drawing Point, Snapped to Any Already Within Reach
    # ------------------------------------------------------------
    def self.Na__ProjectSections__PointId(pool, point)
        snap = NA_PROJECT_SECTION_SNAP
        x    = point[0].to_f
        y    = point[1].to_f
        gx   = (x / snap).floor
        gy   = (y / snap).floor

        (gx - 1..gx + 1).each do |cx|
            (gy - 1..gy + 1).each do |cy|
                (pool[:grid][[cx, cy]] || []).each do |id|
                    other = pool[:points][id]
                    return id if (other[0] - x).abs <= snap && (other[1] - y).abs <= snap
                end
            end
        end

        id = pool[:points].length
        pool[:points] << [x, y]
        (pool[:grid][[gx, gy]] ||= []) << id
        id
    end
    # ---------------------------------------------------------------

    # FUNCTION | Walk the Faces of the Drawing, Ask Each One, Find the Cuts
    # ------------------------------------------------------------
    # Every half-edge is walked once with its face on the left: arriving at a
    # point, the next edge is the first one clockwise from the way back.
    # Anticlockwise cycles are faces; clockwise ones are the outsides of
    # pieces of the drawing, a hole in the smallest face that holds them.
    #
    # Returns [cells, cuts]: cells are { :outer, :holes, :class, :triangles }
    # for every face inside the source face; cuts are [[u, v], [u, v]] pairs.
    # ------------------------------------------------------------
    def self.Na__ProjectSections__Cells(drawing, classify)
        points = drawing[:points]
        around = Hash.new { |hash, key| hash[key] = [] }

        drawing[:edges].each do |a, b|
            around[a] << b
            around[b] << a
        end

        around.each do |id, others|
            origin = points[id]
            others.sort_by! { |other| Math.atan2(points[other][1] - origin[1], points[other][0] - origin[0]) }
        end

        owner  = {}
        cycles = []

        drawing[:edges].each do |a, b|
            [[a, b], [b, a]].each do |start|
                next if owner.key?(start)

                cycle   = []
                current = start
                guard   = 0

                loop do
                    owner[current] = cycles.length
                    cycle << current[0]

                    from, to = current
                    ring     = around[to]
                    back     = ring.index(from)
                    current  = [to, ring[(back - 1) % ring.length]]

                    guard += 1
                    break if current == start || guard > 100_000
                end

                cycles << { :ids => cycle, :area => Na__NobleDrawingTools.Na__ProjectSections__Area(cycle.map { |id| points[id] }) }
            end
        end

        faces = cycles.each_index.select { |index| cycles[index][:area] > NA_PROJECT_SECTION_AREA_TOL }
        faces.each do |index|
            cycle = cycles[index]
            cycle[:holes] = []
            cycle[:class] = classify.call(Na__NobleDrawingTools.Na__ProjectSections__SampleLeft(cycle[:ids], points))
        end

        cycles.each_with_index do |cycle, index|
            next if cycle[:area] > NA_PROJECT_SECTION_AREA_TOL

            probe  = points[cycle[:ids].first]
            holder = faces.select do |face|
                next false if cycles[face][:area] <= cycle[:area].abs
                Na__NobleDrawingTools.Na__ProjectSections__Inside?(probe, [cycles[face][:ids].map { |id| points[id] }])
            end.min_by { |face| cycles[face][:area] }

            cycle[:holder] = holder
            cycles[holder][:holes] << index if holder && cycle[:area] < -NA_PROJECT_SECTION_AREA_TOL
        end

        answer = lambda do |index|
            cycle = cycles[index]
            next cycle[:class] if cycle[:area] > NA_PROJECT_SECTION_AREA_TOL

            cycle[:holder] ? cycles[cycle[:holder]][:class] : nil
        end

        cuts = []
        drawing[:edges].each do |a, b|
            left  = owner[[a, b]] ? answer.call(owner[[a, b]]) : nil
            right = owner[[b, a]] ? answer.call(owner[[b, a]]) : nil
            next if left.nil? || right.nil? || left == right

            cuts << [points[a], points[b]]
        end

        cells = faces.map do |index|
            cycle = cycles[index]
            next nil if cycle[:class].nil?

            outer = cycle[:ids].map { |id| points[id] }
            holes = cycle[:holes].map { |hole| cycles[hole][:ids].map { |id| points[id] } }
            {
                :outer     => outer,
                :holes     => holes,
                :class     => cycle[:class],
                :triangles => holes.empty? ? Na__NobleDrawingTools.Na__ProjectSections__EarClip(outer) : []
            }
        end.compact

        [cells, cuts]
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Point Just Inside a Cycle, Off the Middle of Its Longest Edge
    # ------------------------------------------------------------
    def self.Na__ProjectSections__SampleLeft(ids, points)
        best   = nil
        length = -1.0

        ids.each_with_index do |id, index|
            a  = points[id]
            b  = points[ids[(index + 1) % ids.length]]
            dx = b[0] - a[0]
            dy = b[1] - a[1]
            span = Math.sqrt(dx * dx + dy * dy)
            next unless span > length

            length = span
            best   = [a, b, dx, dy, span]
        end

        a, b, dx, dy, span = best
        step = [NA_PROJECT_SECTION_PROBE, span * 0.05].min
        [(a[0] + b[0]) * 0.5 - dy / span * step, (a[1] + b[1]) * 0.5 + dx / span * step]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Triangles of a Simple Anticlockwise Polygon, as Index Triples
    # ------------------------------------------------------------
    # Ear clipping: enough for the preview's fill. A cell with a hole is
    # outlined but not filled.
    # ------------------------------------------------------------
    def self.Na__ProjectSections__EarClip(points)
        indices   = (0...points.length).to_a
        triangles = []
        guard     = 0

        while indices.length > 3 && guard < 10_000
            guard  += 1
            clipped = false

            indices.each_with_index do |current, position|
                previous = indices[(position - 1) % indices.length]
                following = indices[(position + 1) % indices.length]
                a = points[previous]
                b = points[current]
                c = points[following]
                next unless (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]) > 1.0e-12

                blocked = indices.any? do |other|
                    next false if other == previous || other == current || other == following
                    Na__NobleDrawingTools.Na__ProjectSections__InTriangle?(points[other], a, b, c)
                end
                next if blocked

                triangles << [previous, current, following]
                indices.delete_at(position)
                clipped = true
                break
            end

            break unless clipped
        end

        triangles << indices if indices.length == 3
        triangles
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is a Point Inside (or On) a Triangle?
    # ------------------------------------------------------------
    def self.Na__ProjectSections__InTriangle?(p, a, b, c)
        d1 = (p[0] - b[0]) * (a[1] - b[1]) - (a[0] - b[0]) * (p[1] - b[1])
        d2 = (p[0] - c[0]) * (b[1] - c[1]) - (b[0] - c[0]) * (p[1] - c[1])
        d3 = (p[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (p[1] - a[1])
        negative = d1 < 0.0 || d2 < 0.0 || d3 < 0.0
        positive = d1 > 0.0 || d2 > 0.0 || d3 > 0.0
        !(negative && positive)
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Plane Coordinates and Small Float Helpers
    # -----------------------------------------------------------------------------

    # FUNCTION | Two Axes in the Face's Plane, Its Normal and the Motion, as Floats
    # ------------------------------------------------------------
    def self.Na__ProjectSections__Frame(source)
        normal = Na__NobleDrawingTools.Na__ProjectSections__Unit(Na__NobleDrawingTools.Na__Project__Xyz(source[:normal]))
        helper = normal[2].abs < 0.9 ? [0.0, 0.0, 1.0] : [1.0, 0.0, 0.0]
        first  = Na__NobleDrawingTools.Na__ProjectSections__Unit(Na__NobleDrawingTools.Na__Project__Cross(helper, normal))

        {
            :o => Na__NobleDrawingTools.Na__Project__Xyz(source[:origin]),
            :u => first,
            :v => Na__NobleDrawingTools.Na__Project__Cross(normal, first),
            :n => normal,
            :m => Na__NobleDrawingTools.Na__Project__Xyz(source[:motions][0][0])
        }
    end
    # ---------------------------------------------------------------

    # FUNCTION | A World Point on the Face's Plane, in the Plane's Own Two Axes
    # ------------------------------------------------------------
    def self.Na__ProjectSections__To2d(frame, point)
        offset = Na__NobleDrawingTools.Na__Project__Sub(point, frame[:o])
        [Na__NobleDrawingTools.Na__Project__Dot(offset, frame[:u]), Na__NobleDrawingTools.Na__Project__Dot(offset, frame[:v])]
    end

    def self.Na__ProjectSections__From2d(frame, point)
        o = frame[:o]
        u = frame[:u]
        v = frame[:v]
        [o[0] + u[0] * point[0] + v[0] * point[1], o[1] + u[1] * point[0] + v[1] * point[1], o[2] + u[2] * point[0] + v[2] * point[1]]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Where a World Point Is Seen on the Face's Plane, Down the Travel
    # ------------------------------------------------------------
    def self.Na__ProjectSections__Shadow2d(frame, point)
        height = Na__NobleDrawingTools.Na__Project__Dot(Na__NobleDrawingTools.Na__Project__Sub(point, frame[:o]), frame[:n])
        m      = frame[:m]
        Na__NobleDrawingTools.Na__ProjectSections__To2d(frame, [point[0] - m[0] * height, point[1] - m[1] * height, point[2] - m[2] * height])
    end
    # ---------------------------------------------------------------

    # FUNCTION | How Far Along the Motion a World Point Rises to Meet a Plane
    # ------------------------------------------------------------
    def self.Na__ProjectSections__HeightToPlane(point, motion, plane)
        origin, normal = plane
        along = Na__NobleDrawingTools.Na__Project__Dot(motion, normal)
        return nil if along.abs < NA_PROJECT_MIN_MEET * Math.sqrt(Na__NobleDrawingTools.Na__Project__Dot(motion, motion))

        Na__NobleDrawingTools.Na__Project__Dot(Na__NobleDrawingTools.Na__Project__Sub(origin, point), normal) / along
    end

    def self.Na__ProjectSections__Lift(point, motion, height)
        [point[0] + motion[0] * height, point[1] + motion[1] * height, point[2] + motion[2] * height]
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Loop's Plane by Newell's Method, or nil When It Has None
    # ------------------------------------------------------------
    def self.Na__ProjectSections__PlaneOf(points)
        x = 0.0
        y = 0.0
        z = 0.0

        points.each_with_index do |point, index|
            following = points[(index + 1) % points.length]
            x += (point[1] - following[1]) * (point[2] + following[2])
            y += (point[2] - following[2]) * (point[0] + following[0])
            z += (point[0] - following[0]) * (point[1] + following[1])
        end

        size = Math.sqrt(x * x + y * y + z * z)
        return nil unless size > 1.0e-12

        [points[0], [x / size, y / size, z / size]]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Signed Area of a 2D Loop (Anticlockwise Positive)
    # ------------------------------------------------------------
    def self.Na__ProjectSections__Area(points)
        sum = 0.0
        points.each_with_index do |point, index|
            following = points[(index + 1) % points.length]
            sum += point[0] * following[1] - following[0] * point[1]
        end
        sum * 0.5
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is a 2D Point Inside a Set of Loops? (Even-Odd, So Holes Are Holes)
    # ------------------------------------------------------------
    def self.Na__ProjectSections__Inside?(point, loops)
        px     = point[0]
        py     = point[1]
        inside = false

        loops.each do |points|
            last = points.length - 1
            points.each_with_index do |current, index|
                previous = points[last]
                if (current[1] > py) != (previous[1] > py)
                    crossing = current[0] + (py - current[1]) * (previous[0] - current[0]) / (previous[1] - current[1])
                    inside   = !inside if px < crossing
                end
                last = index
            end
        end

        inside
    end
    # ---------------------------------------------------------------

    # FUNCTION | 2D Bounding Boxes
    # ------------------------------------------------------------
    def self.Na__ProjectSections__Box(loops)
        xs = loops.flat_map { |points| points.map { |point| point[0] } }
        ys = loops.flat_map { |points| points.map { |point| point[1] } }
        [xs.min, xs.max, ys.min, ys.max]
    end

    def self.Na__ProjectSections__Overlap?(first, second)
        pad = NA_PROJECT_SECTION_SNAP
        first[0] <= second[1] + pad && second[0] <= first[1] + pad && first[2] <= second[3] + pad && second[2] <= first[3] + pad
    end

    def self.Na__ProjectSections__InBox?(point, box)
        pad = NA_PROJECT_SECTION_SNAP
        point[0] >= box[0] - pad && point[0] <= box[1] + pad && point[1] >= box[2] - pad && point[1] <= box[3] + pad
    end
    # ---------------------------------------------------------------

    # FUNCTION | Float Triples To and From Geom
    # ------------------------------------------------------------
    def self.Na__ProjectSections__Unit(vector)
        size = Math.sqrt(Na__NobleDrawingTools.Na__Project__Dot(vector, vector))
        size > 0.0 ? vector.map { |value| value / size } : vector
    end

    def self.Na__ProjectSections__Point(xyz)
        Geom::Point3d.new(xyz[0], xyz[1], xyz[2])
    end

    def self.Na__ProjectSections__Vector(xyz)
        Geom::Vector3d.new(xyz[0], xyz[1], xyz[2])
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | The Build (Inside the Open Operation and Context)
    # -----------------------------------------------------------------------------

    # FUNCTION | Split the Face, Carry the Pieces That Meet the Target, Leave the Rest
    # ------------------------------------------------------------
    # job       the commit's job: :entities, :face, :xform, :inverse, :quads
    # sections  Na__ProjectSections__Solve's :sections
    #
    # Positions are read and written in the space the face reports (world
    # when its context is open, by the Coordinate Rule) and converted to
    # world at the edges of this function; the sections are world.
    # Raises with a sentence on any failure, so the caller aborts the lot.
    # ------------------------------------------------------------
    def self.Na__ProjectSections__Build(job, sections)
        build = {
            :job      => job,
            :sections => sections,
            :entities => job[:entities],
            :motion   => sections[:frame][:m],
            :normal   => sections[:frame][:n],
            :walls    => [],
            :made     => {},
            :strips   => [],
            :stray    => []
        }

        normal_before = job[:face].normal

        cut_edges = sections[:cuts].map do |start, finish|
            Na__NobleDrawingTools.Na__ProjectSections__AddLine(build, start, finish)
        end.compact
        build[:stray].concat(cut_edges)

        # A line across the face splits it as it is drawn; a loop drawn wholly
        # inside it (a target smaller than the face) does not, until asked.
        cut_edges.each { |edge| edge.find_faces if edge.valid? }

        pieces = Na__NobleDrawingTools.Na__ProjectSections__Pieces(build, normal_before)
        moving = pieces.keys.select { |piece| pieces[piece].is_a?(Integer) }
        raise 'no part of the face was left to carry after the split — nothing was changed' if moving.empty?

        build[:pieces] = pieces
        landed = moving.map { |piece| Na__NobleDrawingTools.Na__ProjectSections__LandPiece(build, piece) }

        done = {}
        moving.each do |piece|
            piece.loops.each do |loop|
                loop.edges.each do |edge|
                    next if done[edge.entityID]

                    done[edge.entityID] = true
                    Na__NobleDrawingTools.Na__ProjectSections__WallsOn(build, piece, edge)
                end
            end
        end

        build[:stray].concat(moving.flat_map(&:edges))
        (moving + build[:strips]).each { |face| face.erase! if face.valid? }
        Na__NobleDrawingTools.Na__ProjectSections__Sweep(build[:stray])

        seams  = build[:walls].select(&:valid?).flat_map(&:edges)
        healed = job[:quads] ? 0 : Na__NobleDrawingTools.Na__ProjectSections__Heal(seams)
        Na__NobleDrawingTools.Na__ProjectSections__Sweep(seams)                # <-- A seam healed on both sides of an edge leaves it bounding nothing

        raise 'a landed part of the face did not survive the build — nothing was changed' unless landed.all?(&:valid?)

        { :route => :sections, :pieces => moving.length, :healed => healed, :quad => nil }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Draw One Line Between Two World Points, in the Space the Face Reports
    # ------------------------------------------------------------
    def self.Na__ProjectSections__AddLine(build, start, finish)
        a = Na__NobleDrawingTools.Na__ProjectSections__Reported(build, start)
        b = Na__NobleDrawingTools.Na__ProjectSections__Reported(build, finish)
        return nil if a.distance(b).to_f < NA_PROJECT_TOL * 0.25

        build[:entities].add_line(a, b)
    end
    # ---------------------------------------------------------------

    # FUNCTION | World and Reported Space, Converted at the Edges
    # ------------------------------------------------------------
    def self.Na__ProjectSections__Reported(build, world)
        point = world.is_a?(Array) ? Na__NobleDrawingTools.Na__ProjectSections__Point(world) : world
        point.transform(build[:job][:inverse])
    end

    def self.Na__ProjectSections__World(build, reported)
        Na__NobleDrawingTools.Na__Project__Xyz(reported.transform(build[:job][:xform]))
    end

    # A world direction as a reported one, two points carried and subtracted.
    def self.Na__ProjectSections__ReportedDirection(build, world_point, direction)
        ahead = [world_point[0] + direction[0], world_point[1] + direction[1], world_point[2] + direction[2]]
        Na__NobleDrawingTools.Na__ProjectSections__Reported(build, ahead) - Na__NobleDrawingTools.Na__ProjectSections__Reported(build, world_point)
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Pieces the Face Fell Into, Each With What It Meets
    # ------------------------------------------------------------
    # Every face on the original face's plane whose inside lies inside its
    # original outline. Each is then asked just inside every one of its edges
    # and must give one answer throughout: a piece that answers two ways was
    # not split where the target ends, and nothing is built on it.
    # ------------------------------------------------------------
    def self.Na__ProjectSections__Pieces(build, normal_before)
        sections = build[:sections]
        frame    = sections[:frame]
        classify = sections[:classify]
        pieces   = {}

        build[:entities].grep(Sketchup::Face).each do |face|
            next unless face.valid?
            next unless face.normal.samedirection?(normal_before)

            corner = Na__NobleDrawingTools.Na__ProjectSections__World(build, face.vertices.first.position)
            lift   = Na__NobleDrawingTools.Na__Project__Dot(Na__NobleDrawingTools.Na__Project__Sub(corner, frame[:o]), frame[:n])
            next if lift.abs > NA_PROJECT_TOL

            inside = Na__NobleDrawingTools.Na__SlopePush__InteriorPoint(face)
            next unless inside

            flat = Na__NobleDrawingTools.Na__ProjectSections__To2d(frame, Na__NobleDrawingTools.Na__ProjectSections__World(build, inside))
            next unless Na__NobleDrawingTools.Na__ProjectSections__Inside?(flat, sections[:face2d])

            answer = classify.call(flat)
            next if answer.nil?

            Na__NobleDrawingTools.Na__ProjectSections__CheckPiece(build, face, answer)
            pieces[face] = answer
        end

        pieces
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Piece Must Give One Answer Just Inside Every One of Its Edges
    # ------------------------------------------------------------
    def self.Na__ProjectSections__CheckPiece(build, face, answer)
        frame = build[:sections][:frame]

        face.edges.each do |edge|
            a = Na__NobleDrawingTools.Na__ProjectSections__World(build, edge.start.position)
            b = Na__NobleDrawingTools.Na__ProjectSections__World(build, edge.end.position)
            probe = Na__NobleDrawingTools.Na__ProjectSections__InsideProbe(build, face, a, b)
            next unless probe

            flat = Na__NobleDrawingTools.Na__ProjectSections__To2d(frame, probe[:point])
            next if build[:sections][:classify].call(flat) == answer

            raise 'the face could not be split where the target ends — nothing was changed'
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | A World Point Just Inside a Face Beside One of Its Edges, and the Way In
    # ------------------------------------------------------------
    # Returns { :point, :inward } (world floats), or nil for an edge too
    # short to probe beside.
    # ------------------------------------------------------------
    def self.Na__ProjectSections__InsideProbe(build, face, a, b)
        along  = Na__NobleDrawingTools.Na__Project__Sub(b, a)
        span   = Math.sqrt(Na__NobleDrawingTools.Na__Project__Dot(along, along))
        return nil unless span > NA_PROJECT_TOL

        across = Na__NobleDrawingTools.Na__ProjectSections__Unit(Na__NobleDrawingTools.Na__Project__Cross(build[:normal], along))
        step   = [NA_PROJECT_SECTION_PROBE, span * 0.05].min
        middle = [(a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5, (a[2] + b[2]) * 0.5]

        [1.0, -1.0].each do |sign|
            inward = across.map { |value| value * sign }
            point  = [middle[0] + inward[0] * step, middle[1] + inward[1] * step, middle[2] + inward[2] * step]
            local  = Na__NobleDrawingTools.Na__ProjectSections__Reported(build, point)
            return { :point => point, :inward => inward } if face.classify_point(local) == Sketchup::Face::PointInside
        end

        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Height of a World Point on One Side of an Edge: a Piece's Landing, or Nothing
    # ------------------------------------------------------------
    def self.Na__ProjectSections__HeightFor(build, answer, world)
        return 0.0 unless answer.is_a?(Integer)

        plane  = build[:sections][:classes][answer][:plane]
        height = Na__NobleDrawingTools.Na__ProjectSections__HeightToPlane(world, build[:motion], plane)
        raise 'a corner could not be carried to the target' if height.nil?

        height
    end
    # ---------------------------------------------------------------

    # FUNCTION | Add One Piece's Landed Face, Holes and All, Facing Along the Travel
    # ------------------------------------------------------------
    def self.Na__ProjectSections__LandPiece(build, piece)
        answer = build[:pieces][piece]
        outer  = piece.outer_loop
        loops  = [outer] + piece.loops.reject { |loop| loop == outer }

        rings = loops.map do |loop|
            loop.vertices.map do |vertex|
                world = Na__NobleDrawingTools.Na__ProjectSections__World(build, vertex.position)
                height = Na__NobleDrawingTools.Na__ProjectSections__HeightFor(build, answer, world)
                Na__NobleDrawingTools.Na__ProjectSections__Lift(world, build[:motion], height)
            end
        end

        face = build[:entities].add_face(rings[0].map { |point| Na__NobleDrawingTools.Na__ProjectSections__Reported(build, point) })
        raise 'a landed part of the face could not be made — nothing was changed' unless face && face.valid?

        build[:made][face] = true

        rings[1..-1].each do |ring|
            hole = build[:entities].add_face(ring.map { |point| Na__NobleDrawingTools.Na__ProjectSections__Reported(build, point) })
            hole.erase! if hole && hole.valid? && hole != face
        end

        Na__NobleDrawingTools.Na__ProjectSections__Orient(build, face, rings[0][0], build[:motion])
        face
    end
    # ---------------------------------------------------------------

    # FUNCTION | Turn a New Face to Face a World Direction
    # ------------------------------------------------------------
    def self.Na__ProjectSections__Orient(build, face, world_point, direction)
        wanted = Na__NobleDrawingTools.Na__ProjectSections__ReportedDirection(build, world_point, direction)
        face.reverse! if face.normal.dot(wanted) < 0.0
        face
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Wall (or Walls, or Trim) Along One Edge of a Moving Piece
    # ------------------------------------------------------------
    # Side 1 is this piece; side 2 is what lies across the edge: another
    # piece of the face (moving or staying), or the solid's own face round
    # the original outline, or nothing at all.
    # ------------------------------------------------------------
    def self.Na__ProjectSections__WallsOn(build, piece, edge)
        a = Na__NobleDrawingTools.Na__ProjectSections__World(build, edge.start.position)
        b = Na__NobleDrawingTools.Na__ProjectSections__World(build, edge.end.position)

        probe = Na__NobleDrawingTools.Na__ProjectSections__InsideProbe(build, piece, a, b)
        raise 'a piece of the face is too thin to build beside — nothing was changed' unless probe

        here   = build[:pieces][piece]
        others = edge.faces.reject { |face| face == piece || build[:made][face] }
        across = others.find { |face| build[:pieces].key?(face) }
        there  = across ? build[:pieces][across] : nil
        side   = across ? nil : others.first

        h1a = Na__NobleDrawingTools.Na__ProjectSections__HeightFor(build, here, a)
        h1b = Na__NobleDrawingTools.Na__ProjectSections__HeightFor(build, here, b)
        h2a = Na__NobleDrawingTools.Na__ProjectSections__HeightFor(build, there, a)
        h2b = Na__NobleDrawingTools.Na__ProjectSections__HeightFor(build, there, b)

        parts = Na__NobleDrawingTools.Na__ProjectSections__WallParts(a, b, h1a, h1b, h2a, h2b, build[:motion])
        return 0 if parts.empty?

        holds = side ? Na__NobleDrawingTools.Na__ProjectSections__HoldsTravel?(build, side) : false

        parts.each do |part|
            # The wall faces the lower side: away from this piece when it is
            # the higher, into it when it is the lower.
            facing = part[:higher] == 1 ? probe[:inward].map { |value| -value } : probe[:inward]

            if side && holds
                if part[:higher] == 1
                    Na__NobleDrawingTools.Na__ProjectSections__AddWall(build, part[:points], facing)
                else
                    Na__NobleDrawingTools.Na__ProjectSections__Trim(build, side, part[:points])
                end
            elsif side && part[:higher] == 2
                # Going back beside a face that does not run along the
                # travel: inside the solid only if the travel leans out
                # through that face, so its reverse runs into the solid.
                outward = Na__NobleDrawingTools.Na__ProjectSections__WorldNormal(build, side)
                if Na__NobleDrawingTools.Na__Project__Dot(build[:motion], outward) <= 0.0
                    raise 'cutting back there would come out through the side of the solid — nothing was changed'
                end

                Na__NobleDrawingTools.Na__ProjectSections__AddWall(build, part[:points], facing)
            else
                Na__NobleDrawingTools.Na__ProjectSections__AddWall(build, part[:points], facing)
            end
        end

        parts.length
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Wall Between Two Heights Along One Edge, as One or Two Flat Parts
    # ------------------------------------------------------------
    # Every point is the edge swept along the one motion, so each part is
    # flat. Where the two sides swap which is higher the wall pinches to
    # nothing, and it is made as two triangles meeting at that point.
    # :higher says which side stands higher across the part.
    # ------------------------------------------------------------
    def self.Na__ProjectSections__WallParts(a, b, h1a, h1b, h2a, h2b, motion)
        da  = h1a - h2a
        db  = h1b - h2b
        tol = NA_PROJECT_TOL
        return [] if da.abs < tol && db.abs < tol

        lift = lambda { |point, height| Na__NobleDrawingTools.Na__ProjectSections__Lift(point, motion, height) }

        if da * db < 0.0 && da.abs >= tol && db.abs >= tol
            t  = da / (da - db)
            x  = [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]
            hx = h1a + (h1b - h1a) * t

            return [
                { :points => [lift.call(a, h2a), lift.call(x, hx), lift.call(a, h1a)], :higher => da > 0.0 ? 1 : 2 },
                { :points => [lift.call(x, hx), lift.call(b, h2b), lift.call(b, h1b)], :higher => db > 0.0 ? 1 : 2 }
            ]
        end

        points = [lift.call(a, h2a), lift.call(b, h2b)]
        points << lift.call(b, h1b) if db.abs >= tol
        points << lift.call(a, h1a) if da.abs >= tol

        [{ :points => points, :higher => (da + db) > 0.0 ? 1 : 2 }]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Add One Wall Part, Facing the Way It Should
    # ------------------------------------------------------------
    def self.Na__ProjectSections__AddWall(build, points, facing)
        local = points.map { |point| Na__NobleDrawingTools.Na__ProjectSections__Reported(build, point) }
        face  = build[:entities].add_face(local)
        raise 'a wall of the projection could not be made — nothing was changed' unless face && face.valid?

        build[:made][face] = true
        build[:walls] << face

        Na__NobleDrawingTools.Na__ProjectSections__Orient(build, face, points[0], facing)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Cut a Strip Off a Face Round the Original That Runs Along the Travel
    # ------------------------------------------------------------
    # Going back, the wall would lie in that face: so that face is cut back
    # to the target instead. Its outline is drawn on it, the strip it splits
    # off is found by its middle and erased. A strip that is not there — the
    # cut runs past the far end of the solid — refuses the lot.
    # ------------------------------------------------------------
    def self.Na__ProjectSections__Trim(build, side, points)
        normal = side.normal
        lines = points.each_with_index.map do |point, index|
            Na__NobleDrawingTools.Na__ProjectSections__AddLine(build, point, points[(index + 1) % points.length])
        end.compact
        build[:stray].concat(lines)

        # Its lines may all be there already (drawn by the landed face and the
        # trims beside it) without the face having been split by them yet.
        lines.each { |edge| edge.find_faces if edge.valid? }

        middle = [0, 1, 2].map { |axis| points.inject(0.0) { |sum, point| sum + point[axis] } / points.length }
        local  = Na__NobleDrawingTools.Na__ProjectSections__Reported(build, middle)
        area   = Na__NobleDrawingTools.Na__ProjectSections__Area3d(points)

        strip = build[:entities].grep(Sketchup::Face).find do |face|
            face.valid? && face.normal.samedirection?(normal) && face.classify_point(local) == Sketchup::Face::PointInside
        end

        unless strip && (Na__NobleDrawingTools.Na__ProjectSections__FaceArea(build, strip) - area).abs <= [area * 0.01, NA_PROJECT_TOL].max
            raise 'the cut runs past the far end of the solid there — nothing was changed'
        end

        # Erased at the end, with the moving pieces: a later line drawn along
        # one of its edges must not find it gone and fill it in again.
        build[:stray].concat(strip.edges)
        build[:strips] << strip
        true
    end
    # ---------------------------------------------------------------

    # FUNCTION | Does a Face Already Contain the Travel?
    # ------------------------------------------------------------
    def self.Na__ProjectSections__HoldsTravel?(build, face)
        outward = Na__NobleDrawingTools.Na__ProjectSections__WorldNormal(build, face)
        motion  = Na__NobleDrawingTools.Na__ProjectSections__Unit(build[:motion])
        Na__NobleDrawingTools.Na__Project__Dot(outward, motion).abs <= 1.0e-3
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Face's Normal in World, Two Points Carried and Subtracted
    # ------------------------------------------------------------
    def self.Na__ProjectSections__WorldNormal(build, face)
        origin = face.vertices.first.position
        ahead  = Na__NobleDrawingTools.Na__DrawnGrid__OffsetPoint(origin, face.normal, 1.0)
        Na__NobleDrawingTools.Na__ProjectSections__Unit(
            Na__NobleDrawingTools.Na__Project__Sub(
                Na__NobleDrawingTools.Na__ProjectSections__World(build, ahead),
                Na__NobleDrawingTools.Na__ProjectSections__World(build, origin)
            )
        )
    end
    # ---------------------------------------------------------------

    # FUNCTION | Areas, in World Square Inches
    # ------------------------------------------------------------
    def self.Na__ProjectSections__Area3d(points)
        x = 0.0
        y = 0.0
        z = 0.0
        points.each_with_index do |point, index|
            following = points[(index + 1) % points.length]
            x += (point[1] - following[1]) * (point[2] + following[2])
            y += (point[2] - following[2]) * (point[0] + following[0])
            z += (point[0] - following[0]) * (point[1] + following[1])
        end
        Math.sqrt(x * x + y * y + z * z) * 0.5
    end

    def self.Na__ProjectSections__FaceArea(build, face)
        outer = face.outer_loop
        total = 0.0
        ([outer] + face.loops.reject { |loop| loop == outer }).each_with_index do |loop, index|
            ring  = loop.vertices.map { |vertex| Na__NobleDrawingTools.Na__ProjectSections__World(build, vertex.position) }
            area  = Na__NobleDrawingTools.Na__ProjectSections__Area3d(ring)
            total += index.zero? ? area : -area
        end
        total
    end
    # ---------------------------------------------------------------

    # FUNCTION | Erase the Edges of a Set That Bound Nothing Any More
    # ------------------------------------------------------------
    def self.Na__ProjectSections__Sweep(edges)
        edges.uniq.count { |edge| edge.valid? && edge.faces.empty? && edge.erase! }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Clear the Seams Where a Wall Came Out Coplanar With the Face Beside It
    # ------------------------------------------------------------
    # Asked of every edge of every wall made: the start line where a wall
    # carries on a face round the original, and the joint between two walls
    # that came out in one plane. Not with QUADS, which keeps them.
    # ------------------------------------------------------------
    def self.Na__ProjectSections__Heal(edges)
        removed = 0

        edges.uniq.each do |edge|
            next unless edge && edge.valid?

            faces = edge.faces
            next unless faces.length == 2
            next unless faces[0].valid? && faces[1].valid?
            next unless faces[0].normal.samedirection?(faces[1].normal)

            edge.erase!
            removed += 1
        end

        removed
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__NobleDrawingTools module

# =============================================================================
# END OF DEEP PROJECT SECTIONS
# =============================================================================
