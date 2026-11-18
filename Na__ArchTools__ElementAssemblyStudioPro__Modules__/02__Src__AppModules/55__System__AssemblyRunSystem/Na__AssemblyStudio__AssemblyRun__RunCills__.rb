# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - ASSEMBLY RUN SYSTEM - RUN CILLS
# =============================================================================
#
# FILE       : Na__AssemblyStudio__AssemblyRun__RunCills__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__AssemblyRunSystem
# MODULE     : Na__RunCills
# AUTHOR     : Noble Architecture
# PURPOSE    : Where a run's one continuous cill and one continuous window
#              board run, and the plan shape of a band that follows the path
#              round its corners. Read by the layout resolver (the stretches,
#              and what stands on the cill), by the builders (the solids) and
#              by the dialog's preview (the cill drawn in plan).
# CREATED    : 17-Nov-2026 (V2.7.3)
#
# WHY (Adam, 17-Nov-2026, the SK02 bay windows)
#   "Make a way to be able to connect the sills up ... the sill should wrap
#   around all of the sides, and there shouldn't be any join lines."
#   Each window carried its own cill, the width of the window, and the run's
#   mullions and corner posts stood from the base between them, so the cill
#   line was broken at every post and every corner. Each window's internal
#   board overlapped its neighbour's at the mullions and at the corners.
#
# THE WORDS
# - A STRETCH is one unbroken length of the path that one cill (or one
#   window board) runs along: it may turn any number of corners.
# - Walking the path in order, every span, post, column and corner either
#   CARRIES the cill or breaks it:
#     carries  a span at the run's base (its panel type has no sill height),
#              a fused mullion or jamb, an infill block, a corner post or an
#              open corner
#     breaks   a gap, a library column (it stands on its own base), a library
#              corner column, a span raised on a sill (it keeps its own cill),
#              and the empty length left at a leg's end
#   The window board is carried the same way, except that a door breaks it
#   (a door has no board), and it ends at its first and last windows unless
#   it reaches the path's free end (under the end block or jamb there).
# - A stretch with no span (no window, for a board) is not built.
#
# THE WORKTOP (V2.7.4, Cabinets runs; asked for 17-Nov-2026 for SK02's kitchen)
# - One worktop per stretch of base and drawer units, walked the same way:
#     carries  a base or drawer unit, an infill block, a gap (an appliance
#              space: a washing machine under the worktop), a corner unit, a
#              blind corner and an open corner
#     breaks   a wall, tall or wardrobe unit, a gap marked Worktop false (a
#              cooker space), and the empty length left at a leg's end
#   A stretch with no base or drawer unit is not built. Where a stretch
#   reaches a free end of an open path it is made longer by the run's end
#   overhang. How deep and how high it is comes from the units themselves,
#   so the builder sizes it (Na__FrameworkBuilder.na_build_worktops).
#
# THE BAND (na_band_outline)
# - y is measured to the LEFT of the path, as everywhere in a run: in Frames
#   mode the frames stand on the left and the outside is on the right, so a
#   cill runs from y = -projection (proud of the framework face) to the back
#   of the posts. Each corner is a true mitre: the two legs' offset lines
#   meet there, so the band is one shape, and one solid, with no join lines.
#
# PURE RUBY: no Sketchup or Geom calls, so the offline suite can run it.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require_relative 'Na__AssemblyStudio__AssemblyRun__Defaults__'
require_relative 'Na__AssemblyStudio__AssemblyRun__PathMath__'

module Na__AssemblyStudio
module Na__AssemblyRunSystem
    module Na__RunCills

# -----------------------------------------------------------------------------
# REGION | Module References and Constants
# -----------------------------------------------------------------------------

        Defaults = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__Defaults
        PathMath = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__PathMath

        NA_TOLERANCE_MM  = 0.5                                                   # <-- Less than this along a leg is no length at all
        NA_PARALLEL_SINE = 1.0e-9                                                # <-- Two legs this close to parallel meet in a straight line

        # The corners a worktop turns round (V2.7.4): each has a base unit,
        # or the empty square of an open corner, under it.
        NA_WORKTOP_CORNERS = [Defaults::NA_CORNER_UNIT, Defaults::NA_CORNER_BLIND, Defaults::NA_CORNER_OPEN].freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Stretches
# -----------------------------------------------------------------------------

        # FUNCTION | The Stretches One Cill and One Window Board Run Along
        # ------------------------------------------------------------
        # @param legs    [Array<Hash>] the resolver's legs, items placed
        # @param corners [Array<Hash>] the resolver's corners
        # @param types   [Hash] the resolver's panel types (product, sill)
        # @param closed  [Boolean] the path is a loop
        # @return [Hash] { :cills => [stretch], :boards => [stretch] } where a
        #     stretch is { :index, :closed, :start => [leg, s], :end => [leg, s],
        #     :ranges => [{ :leg, :s0, :s1 }], :centreline => [[x, y] mm],
        #     :spans => [keys], :types => [codes], :segments => [walk entries] }
        def self.na_stretches(legs, corners, types, closed)
            walk   = na_walk(legs, corners, types)
            cills  = na_group(walk, closed, :cill).select { |group| group[:segments].any? { |segment| segment[:span] } }
            boards = na_group(walk, closed, :board).filter_map { |group| na_trim_board(group, legs) }
            {
                :cills  => cills.each_with_index.map { |group, index| na_describe(group, legs, index) },
                :boards => boards.each_with_index.map { |group, index| na_describe(group, legs, index) }
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Stand What Is on a Cill on Top of It
        # ------------------------------------------------------------
        # Posts, infill blocks and corner posts in a cill stretch start at
        # the cill's top instead of the run's base. Every span gets :base_z,
        # where its own panel starts: the cill's top for a span on a cill,
        # else its own bottom. Library columns stand on their own base.
        def self.na_lift!(legs, corners, cill_stretches, cill_height)
            lift = cill_height.to_f
            legs.each do |leg|
                Array(leg[:items]).each { |item| item[:base_z] = item[:z0].to_f if item[:kind] == Defaults::NA_ITEM_SPAN }
            end
            corners.each { |corner| corner[:z0] = 0.0 }
            cill_stretches.each do |stretch|
                stretch[:segments].each do |segment|
                    if segment[:kind] == :corner
                        segment[:corner][:z0] = lift
                        next
                    end
                    item = segment[:item]
                    next unless item
                    if item[:kind] == Defaults::NA_ITEM_SPAN
                        item[:base_z] = item[:z0].to_f + lift
                    elsif item[:z1]
                        item[:z0] = lift
                    end
                end
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Stretches a Cabinets Run's One Worktop Runs Along (V2.7.4)
        # ------------------------------------------------------------
        # @param end_overhang [Float] mm the worktop runs on past a free end
        #     of an open path
        # @return [Array<Hash>] stretches as na_stretches gives them, each
        #     with :extend => [mm added at its start, mm added at its end];
        #     its :centreline already includes them
        def self.na_worktop_stretches(legs, corners, types, closed, end_overhang = 0.0)
            walk   = na_worktop_walk(legs, corners, types)
            groups = na_group(walk, closed, :worktop).select { |group| group[:segments].any? { |segment| segment[:span] } }
            groups.each_with_index.map do |group, index|
                stretch = na_describe(group, legs, index)
                na_extend_free_ends!(stretch, legs, end_overhang.to_f, closed)
                stretch
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Geometry
# -----------------------------------------------------------------------------

        # FUNCTION | A Band Following a Path, Mitred at Every Corner
        # ------------------------------------------------------------
        # @param centreline [Array<Array>] [[x, y], ...] mm, in path order
        # @param y_lo, y_hi [Float] the band's two edges, mm to the path's left
        # @param closed     [Boolean] the centreline is a loop
        # @return [Hash] { :outer => [[x, y], ...], :inner => [[x, y], ...] or nil }
        #     An open band is one outline; a closed band is a ring (outer and
        #     its hole).
        def self.na_band_outline(centreline, y_lo, y_hi, closed)
            low  = na_offset_line(centreline, y_lo, closed)
            high = na_offset_line(centreline, y_hi, closed)
            return { :outer => high + low.reverse, :inner => nil } unless closed

            if na_area(high).abs >= na_area(low).abs
                { :outer => high, :inner => low }
            else
                { :outer => low, :inner => high }
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Line Drawn a Set Distance to the Left of a Path
        # ------------------------------------------------------------
        # Each leg's line is moved sideways; at each corner the two moved
        # lines meet (a mitre). An open line starts and ends square to its
        # first and last legs.
        # @return [Array<Array>] [[x, y], ...] one point per centreline point
        def self.na_offset_line(centreline, offset, closed)
            points = centreline.map { |point| [point[0].to_f, point[1].to_f] }
            count  = points.length
            return [] if count < 2
            legs = (closed ? count : count - 1).times.map do |index|
                p0 = points[index]
                p1 = points[(index + 1) % count]
                direction = PathMath.na_direction(p0, p1) || [1.0, 0.0]
                left = PathMath.na_left(direction)
                { :p0 => PathMath.na_add(p0, left, offset), :dir => direction }
            end

            points.each_index.map do |index|
                incoming = closed ? legs[(index - 1) % legs.length] : (index.zero? ? nil : legs[index - 1])
                outgoing = closed ? legs[index % legs.length] : legs[index]
                next PathMath.na_add(points[index], PathMath.na_left(outgoing[:dir]), offset) unless incoming
                next PathMath.na_add(points[index], PathMath.na_left(incoming[:dir]), offset) unless outgoing
                na_meet(incoming, outgoing) || PathMath.na_add(points[index], PathMath.na_left(outgoing[:dir]), offset)
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Profile Swept Along a Path: One Rail per Profile Point
        # ------------------------------------------------------------
        # @param profile [Array<Array>] [[y, z], ...] mm: y to the path's left
        # @return [Array<Array<Array>>] rails[j] = [[x, y, z], ...] along the path
        def self.na_rails(centreline, profile, closed)
            profile.map do |y_mm, z_mm|
                na_offset_line(centreline, y_mm, closed).map { |x, y| [x, y, z_mm.to_f] }
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Signed Area of a Plan Polygon (Positive = Anticlockwise)
        # ------------------------------------------------------------
        def self.na_area(points)
            sum = 0.0
            points.each_index do |index|
                a = points[index]
                b = points[(index + 1) % points.length]
                sum += a[0] * b[1] - b[0] * a[1]
            end
            sum / 2.0
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | The Walk Along the Path
# -----------------------------------------------------------------------------

        # FUNCTION | Every Span, Post, Column, Corner and Empty Length, in Path Order
        # ------------------------------------------------------------
        def self.na_walk(legs, corners, types)
            corner_after = corners.each_with_object({}) { |corner, found| found[corner[:leg_in]] = corner }
            legs.each_with_index.flat_map do |leg, index|
                items    = Array(leg[:items])
                segments = items.map { |item| na_item_segment(item, leg, types) }
                last_end = items.empty? ? leg[:setback_start].to_f : items.last[:s1].to_f
                stop     = leg[:length].to_f - leg[:setback_end].to_f
                if stop - last_end > NA_TOLERANCE_MM
                    segments << { :kind => :empty, :leg => index, :s0 => last_end, :s1 => stop, :cill => false, :board => false }
                end
                corner = corner_after[index]
                segments << na_corner_segment(corner, legs) if corner
                segments
            end
        end
        private_class_method :na_walk
        # ---------------------------------------------------------------

        # HELPER FUNCTION | One Item of a Leg as a Walk Entry
        # ------------------------------------------------------------
        def self.na_item_segment(item, leg, types)
            entry = { :kind => :item, :leg => leg[:index], :s0 => item[:s0].to_f, :s1 => item[:s1].to_f, :item => item,
                      :cill => false, :board => false, :span => false, :window => false }
            case item[:kind]
            when Defaults::NA_ITEM_SPAN
                type = types[item[:type]] || {}
                base = type[:sill].to_f <= NA_TOLERANCE_MM
                window = base && Defaults::NA_WINDOW_PRODUCTS.include?(type[:product].to_s)
                entry.merge!(:cill => base, :board => window, :span => base, :window => window)
            when Defaults::NA_ITEM_COLUMN
                carries = item[:role] == Defaults::NA_COLUMN_INFILL
                entry.merge!(:cill => carries, :board => carries)
            else
                entry.merge!(:cill => true, :board => true)                    # <-- A fused mullion or jamb
            end
            entry
        end
        private_class_method :na_item_segment
        # ---------------------------------------------------------------

        # HELPER FUNCTION | One Corner as a Walk Entry
        # ------------------------------------------------------------
        # From where the arriving leg stops short of the corner, round the
        # vertex, to where the leaving leg starts.
        def self.na_corner_segment(corner, legs)
            leg_in   = legs[corner[:leg_in]]
            carries  = corner[:library].nil? && [Defaults::NA_CORNER_POST, Defaults::NA_CORNER_OPEN].include?(corner[:kind])
            { :kind => :corner, :corner => corner, :leg_in => corner[:leg_in], :leg_out => corner[:leg_out],
              :s_in => leg_in[:length].to_f - corner[:setback_in].to_f, :s_out => corner[:setback_out].to_f,
              :cill => carries, :board => carries, :span => false, :window => false }
        end
        private_class_method :na_corner_segment
        # ---------------------------------------------------------------

        # FUNCTION | The Walk for a Worktop: What Carries It and What Breaks It (V2.7.4)
        # ------------------------------------------------------------
        # The same entries as na_walk, flagged :worktop, with :span marking
        # the base and drawer units (a stretch needs one).
        def self.na_worktop_walk(legs, corners, types)
            corner_after = corners.each_with_object({}) { |corner, found| found[corner[:leg_in]] = corner }
            legs.each_with_index.flat_map do |leg, index|
                items    = Array(leg[:items])
                segments = items.map { |item| na_worktop_item_segment(item, leg, types) }
                last_end = items.empty? ? leg[:setback_start].to_f : items.last[:s1].to_f
                stop     = leg[:length].to_f - leg[:setback_end].to_f
                if stop - last_end > NA_TOLERANCE_MM
                    segments << { :kind => :empty, :leg => index, :s0 => last_end, :s1 => stop, :worktop => false, :span => false }
                end
                corner = corner_after[index]
                segments << na_corner_segment(corner, legs).merge(:worktop => NA_WORKTOP_CORNERS.include?(corner[:kind])) if corner
                segments
            end
        end
        private_class_method :na_worktop_walk
        # ---------------------------------------------------------------

        # HELPER FUNCTION | One Item of a Leg as a Worktop Walk Entry
        # ------------------------------------------------------------
        def self.na_worktop_item_segment(item, leg, types)
            entry = { :kind => :item, :leg => leg[:index], :s0 => item[:s0].to_f, :s1 => item[:s1].to_f, :item => item,
                      :worktop => false, :span => false }
            case item[:kind]
            when Defaults::NA_ITEM_SPAN
                unit = Defaults::NA_WORKTOP_PRODUCTS.include?((types[item[:type]] || {})[:product].to_s)
                entry.merge!(:worktop => unit, :span => unit)
            when Defaults::NA_ITEM_COLUMN
                entry[:worktop] = item[:worktop] != false && [Defaults::NA_COLUMN_INFILL, Defaults::NA_COLUMN_GAP].include?(item[:role])
            end
            entry
        end
        private_class_method :na_worktop_item_segment
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Run a Worktop to the Path's Free Ends, Then On Past Them
        # ------------------------------------------------------------
        # Only where the stretch reaches a free end of an open path: beside a
        # tall unit or a cooker space it stops where they start. It is taken
        # from the path's own end, not the last unit's: an Equal fill rounds
        # each unit down to 0.1 mm, and the worktop would stop just short.
        def self.na_extend_free_ends!(stretch, legs, overhang, path_closed)
            stretch[:extend] = [0.0, 0.0]
            return if path_closed || stretch[:closed] || stretch[:centreline].length < 2

            points = stretch[:centreline]
            first  = legs.first
            last   = legs.last
            if stretch[:start][0].zero? && stretch[:start][1] <= NA_TOLERANCE_MM
                points[0] = PathMath.na_add(first[:p0], first[:dir], -overhang)
                stretch[:extend][0] = overhang
            end
            if stretch[:end][0] == last[:index] && stretch[:end][1] >= last[:length].to_f - NA_TOLERANCE_MM
                points[-1] = PathMath.na_add(last[:p0], last[:dir], last[:length].to_f + overhang)
                stretch[:extend][1] = overhang
            end
        end
        private_class_method :na_extend_free_ends!
        # ---------------------------------------------------------------

        # FUNCTION | Group the Walk Into Unbroken Stretches of One Kind
        # ------------------------------------------------------------
        # A closed path carried all the way round is one closed stretch.
        # Otherwise the walk is started just after a break, so a stretch
        # that runs through the path's first point stays whole.
        def self.na_group(walk, closed, key)
            return [] if walk.empty?
            return [{ :segments => walk, :closed => true }] if closed && walk.all? { |segment| segment[key] }

            if closed
                first_break = walk.index { |segment| !segment[key] }
                walk = walk.rotate(first_break + 1)
            end
            groups  = []
            current = []
            walk.each do |segment|
                if segment[key]
                    current << segment
                else
                    groups << current unless current.empty?
                    current = []
                end
            end
            groups << current unless current.empty?
            groups.map { |segments| { :segments => segments, :closed => false } }
        end
        private_class_method :na_group
        # ---------------------------------------------------------------

        # SUB FUNCTION | A Window Board Ends at Its First and Last Windows
        # ------------------------------------------------------------
        # Posts and corners beyond them are dropped, so a board never wraps
        # round a corner past the last window or runs on beside a door. At
        # the path's free ends nothing is dropped: the board reaches the
        # wall there, under the end block or jamb.
        def self.na_trim_board(group, legs)
            return (group[:segments].any? { |segment| segment[:window] } ? group : nil) if group[:closed]

            segments = group[:segments].dup
            segments.shift while segments.any? && !segments.first[:window] && !na_at_path_start?(segments.first)
            segments.pop while segments.any? && !segments.last[:window] && !na_at_path_end?(segments.last, legs)
            return nil unless segments.any? { |segment| segment[:window] }
            { :segments => segments, :closed => false }
        end
        private_class_method :na_trim_board
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Does a Walk Entry Start Where an Open Path Starts
        # ------------------------------------------------------------
        def self.na_at_path_start?(segment)
            segment[:kind] == :item && segment[:leg].zero? && segment[:s0] <= NA_TOLERANCE_MM
        end
        private_class_method :na_at_path_start?
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Does a Walk Entry End Where an Open Path Ends
        # ------------------------------------------------------------
        def self.na_at_path_end?(segment, legs)
            segment[:kind] == :item && segment[:leg] == legs.length - 1 && segment[:s1] >= legs.last[:length].to_f - NA_TOLERANCE_MM
        end
        private_class_method :na_at_path_end?
        # ---------------------------------------------------------------

        # FUNCTION | A Group of Walk Entries as a Stretch
        # ------------------------------------------------------------
        def self.na_describe(group, legs, index)
            segments = group[:segments]
            spans    = segments.select { |segment| segment[:span] }.map { |segment| segment[:item] }
            base     = { :index => index, :closed => group[:closed], :segments => segments,
                         :spans => spans.map { |span| span[:key] }, :types => spans.map { |span| span[:type] }.uniq }
            if group[:closed]
                return base.merge(:start => [0, 0.0], :end => [0, 0.0],
                                  :ranges => legs.map { |leg| { :leg => leg[:index], :s0 => 0.0, :s1 => leg[:length].to_f } },
                                  :centreline => legs.map { |leg| [leg[:p0][0].to_f, leg[:p0][1].to_f] })
            end

            first = segments.first
            last  = segments.last
            start = first[:kind] == :corner ? [first[:leg_in], first[:s_in]] : [first[:leg], first[:s0]]
            stop  = last[:kind] == :corner ? [last[:leg_out], last[:s_out]] : [last[:leg], last[:s1]]

            points = [na_point_on(legs[start[0]], start[1])]
            segments.each { |segment| points << na_point_on(legs[segment[:leg_in]], legs[segment[:leg_in]][:length].to_f) if segment[:kind] == :corner }
            points << na_point_on(legs[stop[0]], stop[1])
            base.merge(:start => start, :end => stop, :ranges => na_ranges(segments, legs), :centreline => na_drop_repeats(points))
        end
        private_class_method :na_describe
        # ---------------------------------------------------------------

        # HELPER FUNCTION | What a Stretch Covers of Each Leg, in Order
        # ------------------------------------------------------------
        def self.na_ranges(segments, legs)
            pieces = segments.flat_map do |segment|
                next [[segment[:leg], segment[:s0], segment[:s1]]] unless segment[:kind] == :corner
                [[segment[:leg_in], segment[:s_in], legs[segment[:leg_in]][:length].to_f], [segment[:leg_out], 0.0, segment[:s_out]]]
            end
            pieces.each_with_object([]) do |(leg, s0, s1), ranges|
                last = ranges.last
                if last && last[:leg] == leg && (s0 - last[:s1]).abs <= NA_TOLERANCE_MM
                    last[:s1] = s1
                else
                    ranges << { :leg => leg, :s0 => s0, :s1 => s1 }
                end
            end
        end
        private_class_method :na_ranges
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | A Point s Along a Leg
        # ------------------------------------------------------------
        def self.na_point_on(leg, station)
            PathMath.na_add(leg[:p0], leg[:dir], station.to_f)
        end
        private_class_method :na_point_on
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Where Two Moved Leg Lines Meet (Nil When Parallel)
        # ------------------------------------------------------------
        def self.na_meet(incoming, outgoing)
            d1 = incoming[:dir]
            d2 = outgoing[:dir]
            sine = d1[0] * d2[1] - d1[1] * d2[0]
            return nil if sine.abs < NA_PARALLEL_SINE
            delta = [outgoing[:p0][0] - incoming[:p0][0], outgoing[:p0][1] - incoming[:p0][1]]
            t = (delta[0] * d2[1] - delta[1] * d2[0]) / sine
            PathMath.na_add(incoming[:p0], d1, t)
        end
        private_class_method :na_meet
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Drop a Point That Repeats the One Before It
        # ------------------------------------------------------------
        def self.na_drop_repeats(points)
            points.each_with_object([]) do |point, kept|
                kept << point unless kept.last && PathMath.na_distance(kept.last, point) < NA_TOLERANCE_MM
            end
        end
        private_class_method :na_drop_repeats
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__RunCills
end # module Na__AssemblyRunSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
