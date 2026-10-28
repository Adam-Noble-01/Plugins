# =============================================================================
# NA INSERT PRIMATIVES - DEEP SCALE FIELD AND STRETCH PLANES
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnScale__Field__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Where every point of an object goes when it is scaled or
#              stretched, the stretch planes saved with it, and typed sizes
# CREATED    : 2026
#
# DESCRIPTION:
# - A scale and a stretch are the same question asked of every point: where
#   does it go? This file answers it once, as a FIELD, and the preview, the
#   commit and the plane markers all read the same answer. They cannot drift.
# - The field is separable: each local axis of the object has its own rule,
#   and a point's new X depends only on its old X. Three rules:
#     :fixed    the axis is not changing
#     :scale    every point moves away from the anchor in proportion — what
#               SketchUp's Scale tool does
#     :stretch  the axis has stretch planes, and the object comes apart AT
#               them: everything between two planes moves as one piece, and
#               only what crosses a plane gets longer
#
# HOW A STRETCH SHARES THE CHANGE:
# - n planes cut the object into n + 1 slices, and every slice moves without
#   changing size. The change in length is shared equally between the planes,
#   so with two planes each opens by half. A plane through each panel of a
#   door makes the panels wider and leaves the stiles, the muntin and the
#   lock rail exactly as they were — and a third plane is a third place to
#   stretch, never a plane that does nothing.
# - The anchor decides which slice stands still: the min end, the max end, or
#   About Centre the middle, with the ends moving out equally.
#
# A POINT ON A PLANE (the tie rule):
# - A plane snapped to an edge has geometry lying exactly on it, and that
#   geometry has to go one way or the other. It goes with the OUTER slice,
#   the one nearer that end of the object. So two planes snapped to the inner
#   faces of a door's stiles leave both stiles whole and stretch the panels,
#   which is what snapping them there means.
#
# THE STRETCH PLANES (saved with the object):
# - Stored on the DEFINITION, not the instance: dictionary
#   Na__InsertPrimatives__StretchPlanes, keys Na__StretchPlanes__XMm / YMm /
#   ZMm, each a sorted list of positions in definition-local mm. They are
#   in the definition's own axes because they describe its geometry, so
#   every copy of a component shares where it may stretch, a native Scale of
#   one copy does not move them, a reopened file or a component saved to the
#   library still has them, and an undo takes them back. Written only inside
#   an operation, like the tool memory.
# - Kept clean. A plane left outside the object (its geometry edited away
#   with another tool, or squeezed out by a stretch) is ignored when read and
#   dropped at the next write. No planes at all removes the dictionary. A
#   definition nothing uses any more keeps its planes until Purge Unused
#   removes it, planes and all; nothing else refers to them.
# - Copies and nesting. A stretch that makes the object, or a shared part
#   inside it, unique copies the planes to the new definition and leaves the
#   old one's for the copies still using it. A part's own planes are its
#   own: carried whole they stay as they are; opened by a stretch they move
#   with its geometry (Na__ScaleCommit__CarryPartPlanes).
#
# =============================================================================

require 'sketchup.rb'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Field and Plane Constants
    # -----------------------------------------------------------------------------

    NA_SCALE_PLANE_TOL          = 0.002                                       # <-- Inches; a point this close to a plane is ON it
    NA_SCALE_PLANE_MERGE_MM     = 0.5                                         # <-- Two planes closer than this are one plane
    NA_SCALE_SQUARE_TOL         = 0.01                                        # <-- Inches; an edge or face this flat across an axis snaps a plane
    NA_SCALE_MIN_WORLD          = 1.mm                                        # <-- The smallest size a grip or a typed value can make an axis
    NA_SCALE_MIN_GAP            = 1.mm                                        # <-- World; the least a shrink leaves between details either side of a plane

    NA_SCALE_PLANES_DICTIONARY  = 'Na__InsertPrimatives__StretchPlanes'.freeze
    NA_SCALE_PLANES_KEYS        = {
        :x => 'Na__StretchPlanes__XMm',
        :y => 'Na__StretchPlanes__YMm',
        :z => 'Na__StretchPlanes__ZMm'
    }.freeze

    # A factor is typed with an x after it or a star before it: 1.5x, *1.5,
    # x1.5. A bare number is a length in mm, as everywhere else in this plugin.
    NA_SCALE_VCB_FACTOR_PATTERN = /\A(?:[x*]\s*(\d+(?:\.\d+)?)|(\d+(?:\.\d+)?)\s*x)\z/i

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Building the Field
    # -----------------------------------------------------------------------------

    # FUNCTION | The Field for a Set of Factors
    # ------------------------------------------------------------
    # factors  { axis => new length / old length }, only the axes changing
    # sides    { axis => :min | :max | :centre } — the end that stands still
    # planes   { axis => [local inches] } when Stretch Planes is on, else nil
    #
    # An axis with planes inside the box stretches; one without scales.
    # ------------------------------------------------------------
    def self.Na__ScaleField__Build(frame, factors, sides, planes = nil)
        field = { :stretch => false }

        NA_SCALE_AXES.each_with_index do |axis, n|
            factor = factors[axis]

            if factor.nil? || (factor.to_f - 1.0).abs < 1e-9 || !frame[:usable][n]
                field[axis] = { :mode => :fixed }
                next
            end

            factor = factor.to_f
            side   = sides[axis] || :min
            anchor =
                case side
                when :max    then frame[:max][n]
                when :centre then frame[:centre][n]
                else              frame[:min][n]
                end

            inside = planes ? Na__InsertPrimatives.Na__ScalePlanes__Inside(frame, axis, planes[axis]) : []

            if inside.empty?
                field[axis] = { :mode => :scale, :anchor => anchor, :factor => factor }
                next
            end

            delta = frame[:local_lengths][n] * (factor - 1.0)
            base  =
                case side
                when :max    then -delta
                when :centre then -delta * 0.5
                else              0.0
                end

            field[axis] = {
                :mode   => :stretch,
                :planes => inside,
                :delta  => delta,
                :base   => base,
                :centre => frame[:centre][n],
                :factor => factor
            }
            field[:stretch] = true
        end

        field
    end
    # ---------------------------------------------------------------

    # FUNCTION | Does the Field Move Anything at All?
    # ------------------------------------------------------------
    def self.Na__ScaleField__Identity?(field)
        return true unless field

        NA_SCALE_AXES.all? { |axis| field[axis].nil? || field[axis][:mode] == :fixed }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is Every Number in the Field a Real One?
    # ------------------------------------------------------------
    # A factor that came out of a zero length, or a plane read back as
    # nonsense, would hand SketchUp NaN or infinite coordinates. The commit
    # refuses such a field outright rather than let one vertex go to them.
    # ------------------------------------------------------------
    def self.Na__ScaleField__Finite?(field)
        return false unless field

        NA_SCALE_AXES.all? do |axis|
            spec = field[axis]
            next false unless spec

            numbers = [spec[:anchor], spec[:factor], spec[:delta], spec[:base], spec[:centre]].compact + (spec[:planes] || [])
            ok      = numbers.all? { |value| value.is_a?(Numeric) && value.to_f.finite? }
            ok && (spec[:factor].nil? || spec[:factor].to_f > 0.0)
        end
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Reading the Field
    # -----------------------------------------------------------------------------

    # FUNCTION | Which Slice a Coordinate Falls In — 0 Below the First Plane
    # ------------------------------------------------------------
    # A coordinate ON a plane goes with the outer slice: beyond a plane that
    # sits past the middle, before one that sits short of it (the tie rule in
    # the header). A plane exactly in the middle keeps it on the low side.
    # ------------------------------------------------------------
    def self.Na__ScaleField__Slice(spec, u)
        centre = spec[:centre].to_f
        count  = 0

        spec[:planes].each do |plane|
            if u > plane + NA_SCALE_PLANE_TOL
                count += 1
            elsif (u - plane).abs <= NA_SCALE_PLANE_TOL && plane > centre + NA_SCALE_PLANE_TOL
                count += 1
            end
        end

        count
    end
    # ---------------------------------------------------------------

    # FUNCTION | How Far Every Point of One Slice Moves
    # ------------------------------------------------------------
    def self.Na__ScaleField__SliceShift(spec, slice)
        spec[:base] + (slice * (spec[:delta] / spec[:planes].length))
    end
    # ---------------------------------------------------------------

    # FUNCTION | Where One Coordinate Goes Under One Axis Rule
    # ------------------------------------------------------------
    def self.Na__ScaleField__Value(spec, u)
        value = u.to_f

        case spec[:mode]
        when :scale
            spec[:anchor] + ((value - spec[:anchor]) * spec[:factor])
        when :stretch
            value + Na__InsertPrimatives.Na__ScaleField__SliceShift(spec, Na__InsertPrimatives.Na__ScaleField__Slice(spec, value))
        else
            value
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Where a Definition-Local Point Goes
    # ------------------------------------------------------------
    def self.Na__ScaleField__MapPoint(field, point)
        Geom::Point3d.new(
            Na__InsertPrimatives.Na__ScaleField__Value(field[:x], point.x),
            Na__InsertPrimatives.Na__ScaleField__Value(field[:y], point.y),
            Na__InsertPrimatives.Na__ScaleField__Value(field[:z], point.z)
        )
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Object's Box After the Field, as [mins, maxs]
    # Every rule keeps order along its axis, so the ends of the box go to the
    # ends of the new box: there is no need to map the geometry to know it.
    # ------------------------------------------------------------
    def self.Na__ScaleField__Box(field, frame)
        mins = []
        maxs = []

        NA_SCALE_AXES.each_with_index do |axis, n|
            low  = Na__InsertPrimatives.Na__ScaleField__Value(field[axis], frame[:min][n])
            high = Na__InsertPrimatives.Na__ScaleField__Value(field[axis], frame[:max][n])
            mins << (low < high ? low : high)
            maxs << (low < high ? high : low)
        end

        [mins, maxs]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is a Local Box Carried Whole, With No Plane Through It?
    # ------------------------------------------------------------
    # A nested group or component that sits inside one slice on every
    # stretching axis is carried as a piece: its own transformation changes
    # and nothing inside it is touched. One a plane runs through has to be
    # opened and stretched point by point. Both ends go through the tie
    # rule, so a box that only TOUCHES a plane is judged exactly the way its
    # points would be.
    # ------------------------------------------------------------
    def self.Na__ScaleField__RigidOver?(field, mins, maxs)
        NA_SCALE_AXES.each_with_index.all? do |axis, n|
            spec = field[axis]
            next true unless spec[:mode] == :stretch

            Na__InsertPrimatives.Na__ScaleField__Slice(spec, mins[n]) == Na__InsertPrimatives.Na__ScaleField__Slice(spec, maxs[n])
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Field Over a Rigid Box, as One Local Transformation
    # ------------------------------------------------------------
    # Over a box with no plane through it every rule is affine — a shift
    # on a stretching axis, a scale about the anchor on a scaling one — so
    # the three combine into one diagonal transformation. Column-major, the
    # order Geom::Transformation.new takes sixteen values in.
    # ------------------------------------------------------------
    def self.Na__ScaleField__Affine(field, mins)
        terms = NA_SCALE_AXES.each_with_index.map do |axis, n|
            spec = field[axis]

            case spec[:mode]
            when :scale
                [spec[:factor], spec[:anchor] * (1.0 - spec[:factor])]
            when :stretch
                [1.0, Na__InsertPrimatives.Na__ScaleField__SliceShift(spec, Na__InsertPrimatives.Na__ScaleField__Slice(spec, mins[n]))]
            else
                [1.0, 0.0]
            end
        end

        Geom::Transformation.new([
            terms[0][0], 0.0, 0.0, 0.0,
            0.0, terms[1][0], 0.0, 0.0,
            0.0, 0.0, terms[2][0], 0.0,
            terms[0][1], terms[1][1], terms[2][1], 1.0
        ])
    end
    # ---------------------------------------------------------------

    # FUNCTION | Where the Planes Sit Once the Geometry Has Moved
    # ------------------------------------------------------------
    # For the stretch commit only, which moves the geometry itself. A plane
    # goes to the middle of the gap it opened, so it is still inside the part
    # it was stretching and the next stretch finds it there. A plain scale
    # changes the instance and not the definition, so its planes stay put.
    # ------------------------------------------------------------
    def self.Na__ScaleField__PlanesAfter(field, planes)
        result = {}

        NA_SCALE_AXES.each do |axis|
            list = (planes && planes[axis]) || []
            spec = field[axis]

            result[axis] =
                case spec[:mode]
                when :stretch
                    step = spec[:delta] / spec[:planes].length

                    list.map do |value|
                        index = spec[:planes].index { |plane| (plane - value).abs <= NA_SCALE_PLANE_TOL }
                        index ? value + spec[:base] + ((index + 0.5) * step) : Na__InsertPrimatives.Na__ScaleField__Value(spec, value)
                    end
                when :scale
                    list.map { |value| Na__InsertPrimatives.Na__ScaleField__Value(spec, value) }
                else
                    list.dup
                end
        end

        result
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Most a Stretch Can Take Away Before It Turns Inside Out
    # ------------------------------------------------------------
    # Shrinking closes every gap, and a gap can only close as far as the
    # nearest points either side of it before the slices pass through each
    # other. For each pair of neighbouring slices that hold any geometry,
    # the room is the space between them shared by the planes in between.
    #
    # keep is the gap that must survive (local, NA_SCALE_MIN_GAP over the
    # axis's scale). Closed all the way, the points either side of a plane
    # land on each other: zero-length edges and faces folded flat, the
    # broken geometry SketchUp's validity check then has to repair.
    #
    # coords are the object's point coordinates along this axis, local.
    # Returns the most negative local change allowed (zero or less).
    # ------------------------------------------------------------
    def self.Na__ScaleField__StretchMinDelta(planes, centre, length, coords, keep = 0.0)
        spec  = { :planes => planes, :centre => centre }
        count = planes.length
        return -length.to_f if count.zero?

        lows  = Array.new(count + 1)
        highs = Array.new(count + 1)

        coords.each do |u|
            slice        = Na__InsertPrimatives.Na__ScaleField__Slice(spec, u)
            lows[slice]  = u if lows[slice].nil?  || u < lows[slice]
            highs[slice] = u if highs[slice].nil? || u > highs[slice]
        end

        room     = length.to_f
        previous = nil

        (0..count).each do |slice|
            next if lows[slice].nil?

            if previous
                gap     = lows[slice] - highs[previous] - keep.to_f
                gap     = 0.0 if gap < 0.0
                between = slice - previous
                share   = (gap * count) / between
                room    = share if share < room
            end

            previous = slice
        end

        room = 0.0 if room < 0.0
        -room
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Stretch Planes Saved With the Object
    # -----------------------------------------------------------------------------

    # FUNCTION | An Empty Set of Planes
    # ------------------------------------------------------------
    def self.Na__ScalePlanes__Empty
        { :x => [], :y => [], :z => [] }
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Planes Saved on a Definition, in Local Inches
    # ------------------------------------------------------------
    def self.Na__ScalePlanes__Read(definition)
        planes = Na__InsertPrimatives.Na__ScalePlanes__Empty
        return planes unless definition && definition.valid?

        dictionary = definition.attribute_dictionary(NA_SCALE_PLANES_DICTIONARY, false)
        return planes unless dictionary

        NA_SCALE_AXES.each do |axis|
            stored = dictionary[NA_SCALE_PLANES_KEYS[axis]]
            next unless stored.is_a?(Array)

            planes[axis] = stored.map { |value| value.to_f / NA_DRAWN_INCH_TO_MM }.sort
        end

        planes
    rescue StandardError
        Na__InsertPrimatives.Na__ScalePlanes__Empty
    end
    # ---------------------------------------------------------------

    # FUNCTION | Save a Set of Planes on a Definition — Inside an Operation Only
    # ------------------------------------------------------------
    # mm, to three places, so the dictionary reads sensibly in an attribute
    # inspector. No planes at all removes the dictionary rather than leaving
    # three empty lists behind on every object that was ever stretched.
    # ------------------------------------------------------------
    def self.Na__ScalePlanes__Write(definition, planes)
        return false unless definition && definition.valid?

        if Na__InsertPrimatives.Na__ScalePlanes__Total(planes).zero?
            definition.delete_attribute(NA_SCALE_PLANES_DICTIONARY) if definition.attribute_dictionary(NA_SCALE_PLANES_DICTIONARY, false)
            return true
        end

        NA_SCALE_AXES.each do |axis|
            values = (planes[axis] || []).map { |value| (value.to_f * NA_DRAWN_INCH_TO_MM).round(3) }.sort
            definition.set_attribute(NA_SCALE_PLANES_DICTIONARY, NA_SCALE_PLANES_KEYS[axis], values)
        end

        true
    rescue StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "NA DEEP SCALE: planes not saved — #{error.message}"
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | How Many Planes a Set Holds
    # ------------------------------------------------------------
    def self.Na__ScalePlanes__Total(planes)
        return 0 unless planes

        NA_SCALE_AXES.inject(0) { |sum, axis| sum + (planes[axis] || []).length }
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Planes of One Axis That Are Actually Inside the Box
    # ------------------------------------------------------------
    # A plane left outside by an edit made with another tool is kept in the
    # dictionary but ignored, rather than stretching empty space.
    # ------------------------------------------------------------
    def self.Na__ScalePlanes__Inside(frame, axis, list)
        n = NA_SCALE_AXIS_INDEX[axis]

        (list || []).select do |value|
            value > frame[:min][n] + NA_SCALE_PLANE_TOL && value < frame[:max][n] - NA_SCALE_PLANE_TOL
        end.sort
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Plane Set With Every Plane Outside a Local Box Dropped
    # ------------------------------------------------------------
    # The cleaning of orphans. A plane is orphaned when the geometry it was
    # placed in has gone — edited away with another tool, or squeezed out by
    # a stretch. It is ignored while it is read, and dropped the next time
    # the object's planes are written, so the dictionary only ever holds
    # planes that can still cut something.
    # ------------------------------------------------------------
    def self.Na__ScalePlanes__Prune(planes, mins, maxs)
        kept = Na__InsertPrimatives.Na__ScalePlanes__Empty

        NA_SCALE_AXES.each_with_index do |axis, n|
            kept[axis] = ((planes || {})[axis] || []).select do |value|
                value > mins[n] + NA_SCALE_PLANE_TOL && value < maxs[n] - NA_SCALE_PLANE_TOL
            end
        end

        kept
    end
    # ---------------------------------------------------------------

    # FUNCTION | A List of Planes Sorted, With Near-Duplicates Merged
    # ------------------------------------------------------------
    def self.Na__ScalePlanes__Tidy(list, frame, n)
        merge   = (NA_SCALE_PLANE_MERGE_MM / NA_DRAWN_INCH_TO_MM) / frame[:scales][n]
        sorted  = list.map(&:to_f).sort
        tidied  = []

        sorted.each do |value|
            next if !tidied.empty? && (value - tidied.last).abs < merge

            tidied << value
        end

        tidied
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Plane Geometry and Snapping
    # -----------------------------------------------------------------------------

    # FUNCTION | A Local Point at u Along One Axis, Centred on the Other Two
    # ------------------------------------------------------------
    def self.Na__ScalePlanes__AxisPoint(frame, axis, u)
        values    = frame[:centre].dup
        values[NA_SCALE_AXIS_INDEX[axis]] = u.to_f

        Geom::Point3d.new(values[0], values[1], values[2])
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Centre Line of One Axis, End to End, in World Space
    # ------------------------------------------------------------
    def self.Na__ScalePlanes__CentreLine(frame, axis)
        n = NA_SCALE_AXIS_INDEX[axis]

        [
            Na__InsertPrimatives.Na__ScalePlanes__AxisPoint(frame, axis, frame[:min][n]).transform(frame[:world]),
            Na__InsertPrimatives.Na__ScalePlanes__AxisPoint(frame, axis, frame[:max][n]).transform(frame[:world])
        ]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Where a Plane Crosses Its Centre Line, in World Space
    # ------------------------------------------------------------
    def self.Na__ScalePlanes__HandlePoint(frame, axis, u)
        Na__InsertPrimatives.Na__ScalePlanes__AxisPoint(frame, axis, u).transform(frame[:world])
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Plane Drawn as a Quad Across the Box, a Little Oversize
    # ------------------------------------------------------------
    # It stands proud of the object by `margin` of each side, so a plane
    # through a slab still reads as a plane and not as one more edge.
    # mins / maxs default to the frame's box; the drag passes the new one.
    # ------------------------------------------------------------
    def self.Na__ScalePlanes__Quad(frame, axis, u, margin = 0.08, mins = nil, maxs = nil)
        lo = mins || frame[:min]
        hi = maxs || frame[:max]
        n  = NA_SCALE_AXIS_INDEX[axis]
        b  = (n + 1) % 3
        c  = (n + 2) % 3

        pad = lambda do |index|
            span = hi[index] - lo[index]
            span = frame[:world_lengths].max / frame[:scales][index] * 0.05 if span <= NA_SCALE_PLANE_TOL
            span * margin
        end

        b_lo = lo[b] - pad.call(b)
        b_hi = hi[b] + pad.call(b)
        c_lo = lo[c] - pad.call(c)
        c_hi = hi[c] + pad.call(c)

        [[b_lo, c_lo], [b_hi, c_lo], [b_hi, c_hi], [b_lo, c_hi]].map do |bv, cv|
            values    = [0.0, 0.0, 0.0]
            values[n] = u.to_f
            values[b] = bv
            values[c] = cv
            Geom::Point3d.new(values[0], values[1], values[2]).transform(frame[:world])
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Plane's Distance From Each End of the Object, in World mm
    # ------------------------------------------------------------
    def self.Na__ScalePlanes__DistancesMm(frame, axis, u)
        n     = NA_SCALE_AXIS_INDEX[axis]
        scale = frame[:scales][n]

        [
            Na__InsertPrimatives.Na__DrawnFormat__Mm((u - frame[:min][n]) * scale),
            Na__InsertPrimatives.Na__DrawnFormat__Mm((frame[:max][n] - u) * scale)
        ]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Keep a Plane Strictly Inside the Box
    # ------------------------------------------------------------
    def self.Na__ScalePlanes__Clamp(frame, axis, u)
        n    = NA_SCALE_AXIS_INDEX[axis]
        gap  = (NA_SCALE_PLANE_MERGE_MM / NA_DRAWN_INCH_TO_MM) / frame[:scales][n]
        low  = frame[:min][n] + gap
        high = frame[:max][n] - gap
        return frame[:centre][n] if low >= high

        u < low ? low : (u > high ? high : u)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Round a Plane's Distance From the Low End onto the Snap Grid
    # The distance is what gets read out ("296 | 754"), so it is the distance
    # that lands on the grid, measured in world mm along the object's axis.
    # ------------------------------------------------------------
    def self.Na__ScalePlanes__GridValue(frame, axis, u)
        n     = NA_SCALE_AXIS_INDEX[axis]
        scale = frame[:scales][n]
        along = Na__InsertPrimatives.Na__DrawnGrid__SnapDistance((u - frame[:min][n]) * scale)

        frame[:min][n] + (along / scale)
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Cursor Ray Brought Onto an Axis's Centre Line, as a Local u
    # nil when the line is seen end-on or the answer is behind the camera.
    # ------------------------------------------------------------
    def self.Na__ScalePlanes__RayValue(view, frame, axis, x, y)
        start, finish = Na__InsertPrimatives.Na__ScalePlanes__CentreLine(frame, axis)
        direction     = finish - start
        return nil unless direction.length > 0.0

        ray     = view.pickray(x, y)
        closest = Geom.closest_points([start, direction], ray)
        return nil unless closest && closest[0] && closest[1]
        return nil unless (closest[1] - ray[0]).dot(ray[1]) > 0.0

        closest[0].transform(frame[:inverse])[NA_SCALE_AXIS_INDEX[axis]]
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Where to Put a Plane for the Cursor, and Why There
    # ------------------------------------------------------------
    # SketchUp's own inference first: a point snaps the plane to it exactly,
    # and so does an edge or a face that runs square across the axis — the
    # inner face of a stile, the end of a rail. Anything else (a face the
    # axis runs along, open space) gives the cursor's place on the centre
    # line, with its distance from the low end rounded onto the grid.
    #
    # ip must already be picked at (x, y). Returns [u, how] or nil, where how
    # names the snap for the label: 'point', 'edge', 'face' or 'grid'.
    # ------------------------------------------------------------
    def self.Na__ScalePlanes__SnapValue(view, frame, axis, ip, x, y)
        n = NA_SCALE_AXIS_INDEX[axis]

        if ip && ip.valid?
            how =
                case ip.degrees_of_freedom
                when 0 then 'point'
                when 1 then Na__InsertPrimatives.Na__ScalePlanes__SquareAcross?(frame, n, ip, ip.edge) ? 'edge' : nil
                when 2 then Na__InsertPrimatives.Na__ScalePlanes__SquareAcross?(frame, n, ip, ip.face) ? 'face' : nil
                end

            if how && ip.position
                u = ip.position.transform(frame[:inverse])[n]
                inside = u > frame[:min][n] + NA_SCALE_PLANE_TOL && u < frame[:max][n] - NA_SCALE_PLANE_TOL
                return [u, how] if inside
            end
        end

        u = Na__InsertPrimatives.Na__ScalePlanes__RayValue(view, frame, axis, x, y)
        return nil unless u

        [Na__InsertPrimatives.Na__ScalePlanes__GridValue(frame, axis, u), 'grid']
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Does an Inferred Edge or Face Run Square Across the Axis?
    # ------------------------------------------------------------
    # Its vertices are read in whichever space puts the InputPoint ON it: the
    # InputPoint's transformation for something inside a closed group, the
    # identity for something in the open context (whose positions are
    # already global). Trying both and keeping the one that fits is a
    # measurement, not a belief about what InputPoint#transformation holds.
    # ------------------------------------------------------------
    def self.Na__ScalePlanes__SquareAcross?(frame, n, ip, entity)
        return false unless entity && entity.valid? && entity.respond_to?(:vertices)

        positions = entity.vertices.map(&:position)
        return false if positions.length < 2

        candidates = [ip.transformation, Geom::Transformation.new].compact
        best       = nil
        best_miss  = nil

        candidates.each do |xform|
            points = positions.map { |point| point.transform(xform) }
            miss   = points.map { |point| point.distance(ip.position) }.min.to_f
            plane  = entity.is_a?(Sketchup::Face) ? Geom.fit_plane_to_points(points) : nil
            miss   = ip.position.distance_to_plane(plane).to_f if plane
            miss   = ip.position.distance_to_line([points[0], points[1] - points[0]]).to_f if entity.is_a?(Sketchup::Edge) && points[0] != points[1]

            if best_miss.nil? || miss < best_miss
                best      = points
                best_miss = miss
            end
        end

        values = best.map { |point| point.transform(frame[:inverse])[n] }
        (values.max - values.min) <= NA_SCALE_SQUARE_TOL
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Typed Sizes and Factors
    # -----------------------------------------------------------------------------

    # FUNCTION | Read a Measurements Box Entry for Deep Scale
    # ------------------------------------------------------------
    # Comma separated and positional, like every entry in this plugin, each
    # token one of:
    #   ""        keep this axis
    #   2400      a size, mm unless it names cm or m
    #   +100 -50  bigger or smaller by that much
    #   1.5x *1.5 a factor
    # Returns nil, [:factor, f] or [:length, sign, inches] per token.
    # ------------------------------------------------------------
    def self.Na__ScaleVcb__ParseEntry(text)
        parts = text.to_s.split(',', -1)
        raise ArgumentError, 'no value entered' if parts.empty?

        parts.map do |part|
            stripped = part.strip
            next nil if stripped.empty?

            factor = NA_SCALE_VCB_FACTOR_PATTERN.match(stripped)

            if factor
                value = (factor[1] || factor[2]).to_f
                raise ArgumentError, "a factor has to be more than 0 — '#{stripped}'" unless value > 0.0

                next [:factor, value]
            end

            sign, magnitude = Na__InsertPrimatives.Na__DrawnVcb__ParseToken(stripped)
            [:length, sign, magnitude]
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Factor One Token Asks For, Against an Axis's World Length
    # ------------------------------------------------------------
    def self.Na__ScaleVcb__Factor(token, world_length, label = 'size')
        return nil if token.nil?
        return token[1] if token[0] == :factor

        _kind, sign, magnitude = token
        length = world_length.to_f

        wanted =
            case sign
            when :plus  then length + magnitude
            when :minus then length - magnitude
            else             magnitude
            end

        unless wanted > NA_SCALE_MIN_WORLD.to_f
            raise ArgumentError, "#{label} would be #{Na__InsertPrimatives.Na__DrawnFormat__Mm(wanted)}mm — it has to be more than 0"
        end

        wanted / length
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP SCALE FIELD AND STRETCH PLANES
# =============================================================================
