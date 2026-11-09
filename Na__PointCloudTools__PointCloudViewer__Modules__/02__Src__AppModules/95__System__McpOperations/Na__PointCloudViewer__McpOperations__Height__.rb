# =============================================================================
# NA POINT CLOUD VIEWER - MCP OPERATIONS - HEIGHTMAPS AND PROFILES
# =============================================================================
#
# FILE       : Na__PointCloudViewer__McpOperations__Height__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__McpHeight
# CREATED    : 09-Nov-2026 (v0.14.4)
# PURPOSE    : Heights per cell of a grid seen along a model axis, and heights
#              along a path, for the Na SketchUp MCP's point_cloud_heightmap.
#              Pure Ruby, no SketchUp API: the seam reads an even sample of the
#              points with napc_box_points and hands it here.
#
# METHOD:
# - Each point gets a cell (a grid cell, or a station along a path) and its
#   value along the view's axis (z from the top). A counting sort puts each
#   cell's values together; each cell is then sorted once.
# - Values are ranked by nearness to the viewer (0.14.5): the caller passes
#   'toward' (+1 when a larger model value is nearer, as z from the top; -1
#   from the front or the left), the value binned is toward x the model value,
#   so max, p98 and rgb_top are always the surface the viewer sees.
# - A percentile is the value at rank floor(q x (n - 1)) of the cell's sorted
#   values, the rule of the skill's pc_terrain.py (cmd_rasters): min is p0 and
#   max p100, and every statistic is a real point's value except the mean.
# - rgb_top and rgb_low are the mean colours of the highest tenth and the
#   lowest quarter of each cell's points, again as pc_terrain.py makes them.
#
# Every length in and out is in model inches.
#
# =============================================================================

module Na__PointCloudViewer
    module Na__McpHeight

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_WORDS       = { 'min' => 0.0, 'median' => 0.5, 'max' => 1.0 }.freeze
        NA_MAX_STATS   = 8
        NA_TOP_BAND    = [0.90, 1.0].freeze
        NA_LOW_BAND    = [0.0, 0.25].freeze
        NA_RANK_EPS    = 1e-9       # 0.29 x 100 is 28.999...: the rank it means is 29
        NA_EDGE_INCHES = 1e-6       # a point this close outside a grid's edge counts in the edge cell
        NA_RAMP        = [[0.0, [40, 60, 160]], [0.25, [40, 150, 170]], [0.5, [90, 180, 80]],
                          [0.75, [235, 210, 70]], [1.0, [200, 60, 40]]].freeze
        NA_EMPTY_RGB   = [255, 255, 255].freeze
        NA_CONTOUR_RGB = [25, 25, 25].freeze
        NA_LIGHT       = [-0.5, 0.5, Math.sqrt(0.5)].freeze   # from the top left, 45 degrees up
        NA_SHADE_FLAT  = 0.55                                  # a flat cell keeps its colour: 0.55 + 0.45
        NA_GRID_RGB    = [228, 228, 228].freeze
        NA_POINT_RGB   = [165, 165, 165].freeze
        NA_LINE_RGBS   = [[220, 30, 30], [30, 70, 220], [40, 160, 60], [150, 60, 180],
                          [230, 140, 20], [20, 150, 160], [110, 110, 110], [0, 0, 0]].freeze
        NA_MARGIN_PX   = 20
        NA_PROFILE_PX  = 1200       # the plot's width along the path
        NA_PROFILE_TALL = 300       # the height an automatic exaggeration aims for
        NA_PROFILE_MAX_PX = 1600
        NA_NICE        = [1, 2, 5, 10, 20, 50, 100].freeze

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Statistics Named
    # -------------------------------------------------------------------------

        # ['p2', 'median', 'mean'] -> [['p2', 0.02], ['p50', 0.5], ['mean', :mean]]:
        # names made plain (median is p50), repeats dropped. Raises ArgumentError
        # naming the bad one.
        def self.Na__Height__Specs(list)
            raise ArgumentError, 'stats is empty: name at least one, e.g. ["p50"].' if list.nil? || list.empty?
            specs = []
            list.each do |raw|
                text = raw.to_s.strip.downcase
                spec = if text == 'mean'
                           ['mean', :mean]
                       elsif text == 'median'
                           ['p50', 0.5]
                       elsif NA_WORDS.key?(text)
                           [text, NA_WORDS[text]]
                       elsif (match = text.match(/\Ap(\d{1,3}(?:\.\d{1,2})?)\z/))
                           percent = match[1].to_f
                           raise ArgumentError, "#{raw} is over p100." if percent > 100
                           ["p#{self.na_trim(percent)}", percent / 100.0]
                       else
                           raise ArgumentError, "#{raw.inspect} is not a statistic: use min, max, mean, median or p<percent> (p2, p50, p98, p99.5)."
                       end
                specs << spec unless specs.any? { |name, _| name == spec[0] }
            end
            raise ArgumentError, "At most #{NA_MAX_STATS} statistics in one call, not #{specs.length}." if specs.length > NA_MAX_STATS
            specs
        end

        # A statistic's name in a file: prefix + min, max or mean, or the
        # percentile in two digits (z02, z50, z98, z99_5), as pc_terrain.py names them.
        def self.Na__Height__FileName(name, prefix)
            return prefix + name unless name.start_with?('p')
            whole, part = name[1..].split('.')
            prefix + whole.rjust(2, '0') + (part ? "_#{part}" : '')
        end

        def self.na_trim(number)
            number == number.round ? number.round.to_s : number.round(2).to_s
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Cells and Statistics
    # -------------------------------------------------------------------------

        # Each point's cell on a grid seen along a model axis, and its value along
        # that axis. xyz: flat [x, y, z, x, y, z, ...]. grid: 'u' => [axis, sign]
        # (screen right), 'v' => [axis, sign] (screen up), 'h' => axis, 'left'
        # (u at the left edge), 'top' (v at the top edge), 'cell', 'width',
        # 'height'. Column floor((u - left) / cell), row floor((top - v) / cell),
        # as napc_box_grid and the slices count them. Returns [cells (-1 off the
        # grid), values].
        def self.Na__Height__GridCells(xyz, grid)
            ui, us = grid['u']
            vi, vs = grid['v']
            hi = grid['h']
            toward = (grid['toward'] || 1).to_f
            left = grid['left'].to_f
            top = grid['top'].to_f
            inverse = 1.0 / grid['cell']
            width = grid['width']
            height = grid['height']
            edge = NA_EDGE_INCHES * inverse
            count = xyz.length / 3
            cells = Array.new(count, -1)
            values = Array.new(count)
            i = 0
            while i < count
                base = 3 * i
                across = (us * xyz[base + ui] - left) * inverse
                down = (top - vs * xyz[base + vi]) * inverse
                column = across.floor
                row = down.floor
                # On the box's faces (0.14.5): a hair outside an edge is the edge cell, as the box keeps the point.
                column = 0 if column == -1 && across > -edge
                row = 0 if row == -1 && down > -edge
                column = width - 1 if column == width && across <= width + edge
                row = height - 1 if row == height && down <= height + edge
                cells[i] = row * width + column if column >= 0 && column < width && row >= 0 && row < height
                values[i] = toward * xyz[base + hi]
                i += 1
            end
            [cells, values]
        end

        # Per-cell statistics. cells and values: one each a point (cell -1 is
        # left out); count: how many cells; specs from Na__Height__Specs;
        # colours: nil, or one 0xAARRGGBB a point. Returns { 'count' => points a
        # cell, 'stats' => { name => value or nil a cell }, 'binned' => points
        # used } and, with colours, 'rgb_top' and 'rgb_low' => [r, g, b] or nil a cell.
        def self.Na__Height__Bin(cells, values, count, specs, colours = nil)
            counts = Array.new(count, 0)
            cells.each { |cell| counts[cell] += 1 if cell >= 0 }
            starts = Array.new(count)
            total = 0
            count.times do |cell|
                starts[cell] = total
                total += counts[cell]
            end
            fill = starts.dup
            sorted = Array.new(total)
            tints = colours ? Array.new(total) : nil
            i = 0
            length = cells.length
            while i < length
                cell = cells[i]
                if cell >= 0
                    at = fill[cell]
                    fill[cell] = at + 1
                    sorted[at] = values[i]
                    tints[at] = colours[i] if tints
                end
                i += 1
            end
            stats = specs.to_h { |name, _| [name, Array.new(count)] }
            top = tints ? Array.new(count) : nil
            low = tints ? Array.new(count) : nil
            count.times do |cell|
                n = counts[cell]
                next if n.zero?
                start = starts[cell]
                if tints
                    order = (start...start + n).sort_by { |at| sorted[at] }
                    heights = order.map { |at| sorted[at] }
                    top[cell] = self.na_band(order, tints, n, NA_TOP_BAND)
                    low[cell] = self.na_band(order, tints, n, NA_LOW_BAND)
                else
                    heights = sorted[start, n].sort!
                end
                specs.each do |name, q|
                    stats[name][cell] = q == :mean ? heights.sum / n : heights[(q * (n - 1) + NA_RANK_EPS).floor]
                end
            end
            result = { 'count' => counts, 'stats' => stats, 'binned' => total }
            if tints
                result['rgb_top'] = top
                result['rgb_low'] = low
            end
            result
        end

        # The mean colour of ranks floor(f0 x (n - 1)) to floor(f1 x (n - 1)).
        def self.na_band(order, tints, n, band)
            first = (band[0] * (n - 1) + NA_RANK_EPS).floor
            last = (band[1] * (n - 1) + NA_RANK_EPS).floor
            red = green = blue = 0
            (first..last).each do |rank|
                colour = tints[order[rank]]
                red += (colour >> 16) & 255
                green += (colour >> 8) & 255
                blue += colour & 255
            end
            size = (last - first + 1).to_f
            [red / size, green / size, blue / size]
        end

        # The plane value = a x u + b x v + c through the filled cells (u to the
        # right and v up, from the grid's top left corner to each cell's centre),
        # least squares. { 'a', 'b', 'c', 'rms', 'cells' }, or nil when fewer than
        # three cells hold a value or they all lie in a line.
        def self.Na__Height__Plane(values, width, height, cell)
            us = []
            vs = []
            hs = []
            height.times do |row|
                width.times do |column|
                    value = values[row * width + column]
                    next if value.nil?
                    us << (column + 0.5) * cell
                    vs << -(row + 0.5) * cell
                    hs << value
                end
            end
            n = hs.length
            return nil if n < 3
            mu = us.sum / n
            mv = vs.sum / n
            mh = hs.sum / n
            suu = suv = svv = suh = svh = 0.0
            n.times do |i|
                du = us[i] - mu
                dv = vs[i] - mv
                dh = hs[i] - mh
                suu += du * du
                suv += du * dv
                svv += dv * dv
                suh += du * dh
                svh += dv * dh
            end
            determinant = suu * svv - suv * suv
            return nil if determinant.abs <= 1e-12 * [suu * svv, 1e-300].max
            a = (suh * svv - svh * suv) / determinant
            b = (svh * suu - suh * suv) / determinant
            c = mh - a * mu - b * mv
            squares = 0.0
            n.times do |i|
                residual = hs[i] - (a * us[i] + b * vs[i] + c)
                squares += residual * residual
            end
            { 'a' => a, 'b' => b, 'c' => c, 'rms' => Math.sqrt(squares / n), 'cells' => n }
        end

        # The value at rank floor(q x (n - 1)) of the non-nil values, or nil.
        def self.Na__Height__Percentile(values, q)
            kept = values.compact.sort
            return nil if kept.empty?
            kept[(q * (kept.length - 1) + NA_RANK_EPS).floor]
        end

        # 1, 2 or 5 times a power of ten, the largest not over value.
        def self.Na__Height__Nice(value)
            return 0.0 unless value > 0
            power = 10.0**Math.log10(value).floor
            [5, 2, 1].map { |step| step * power }.find { |step| step <= value * (1 + 1e-9) } || power
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | The Heightmap Picture
    # -------------------------------------------------------------------------

        # RGB rows (Strings, 3 bytes a pixel), scale pixels a cell. values: one
        # a cell, larger = nearer the viewer (the seam flips side views so),
        # nil where empty. Each cell coloured along NA_RAMP from low (blue) to
        # high (red), clamped to low..high, shaded by a light from the top left,
        # white where empty; contour lines where a cell and its right or lower
        # neighbour fall either side of a multiple of contour (0: none), the
        # fifth multiples darker.
        def self.Na__Height__Picture(values, width, height, cell, scale, low, high, contour)
            span = high - low
            span = 1e-9 if span <= 0
            rows = []
            height.times do |row|
                line = ''.b
                width.times do |column|
                    value = values[row * width + column]
                    rgb = if value.nil?
                              NA_EMPTY_RGB
                          else
                              shade = self.na_shade(values, width, height, row, column, cell)
                              self.na_ramp((value - low) / span).map { |x| [(x * shade).round, 255].min }
                          end
                    line << (rgb.pack('C3') * scale)
                end
                scale.times { rows << line.dup }
            end
            if contour && contour > 0
                height.times do |row|
                    width.times do |column|
                        value = values[row * width + column]
                        next if value.nil?
                        right = column + 1 < width ? values[row * width + column + 1] : nil
                        below = row + 1 < height ? values[(row + 1) * width + column] : nil
                        if right && (major = self.na_crossing(value, right, contour)) != nil
                            scale.times { |dy| self.na_darken(rows[row * scale + dy], (column + 1) * scale - 1, major) }
                        end
                        if below && (major = self.na_crossing(value, below, contour)) != nil
                            line = rows[(row + 1) * scale - 1]
                            scale.times { |dx| self.na_darken(line, column * scale + dx, major) }
                        end
                    end
                end
            end
            rows
        end

        # nil when a and b lie between the same two multiples of step; else
        # true when a fifth multiple lies between them.
        def self.na_crossing(a, b, step)
            low, high = [a, b].minmax
            first = (low / step).floor + 1
            last = (high / step).floor
            return nil if last < first
            (first..last).any? { |multiple| (multiple % 5).zero? }
        end

        def self.na_darken(line, column, major)
            share = major ? 0.8 : 0.45
            3.times do |k|
                at = 3 * column + k
                old = line.getbyte(at)
                line.setbyte(at, (old + (NA_CONTOUR_RGB[k] - old) * share).round)
            end
        end

        # 0.55 + 0.45 x (n . light) / (flat n . light): a flat cell keeps its colour.
        def self.na_shade(values, width, height, row, column, cell)
            here = values[row * width + column]
            left = column > 0 ? values[row * width + column - 1] : nil
            right = column + 1 < width ? values[row * width + column + 1] : nil
            up = row > 0 ? values[(row - 1) * width + column] : nil
            down = row + 1 < height ? values[(row + 1) * width + column] : nil
            du = self.na_slope(left, here, right, cell)
            dv = self.na_slope(down, here, up, cell)
            normal = [-du, -dv, 1.0]
            length = Math.sqrt(du * du + dv * dv + 1.0)
            light = (normal[0] * NA_LIGHT[0] + normal[1] * NA_LIGHT[1] + normal[2] * NA_LIGHT[2]) / length
            NA_SHADE_FLAT + (1.0 - NA_SHADE_FLAT) * [light, 0.0].max / NA_LIGHT[2]
        end

        # The rise per length from before to after (either may be nil).
        def self.na_slope(before, here, after, cell)
            if before && after
                (after - before) / (2.0 * cell)
            elsif after
                (after - here) / cell
            elsif before
                (here - before) / cell
            else
                0.0
            end
        end

        def self.na_ramp(share)
            share = [[share, 0.0].max, 1.0].min
            NA_RAMP.each_cons(2) do |(s0, c0), (s1, c1)|
                next if share > s1
                t = (share - s0) / (s1 - s0)
                return (0..2).map { |k| c0[k] + (c1[k] - c0[k]) * t }
            end
            NA_RAMP.last[1].map(&:to_f)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Profiles
    # -------------------------------------------------------------------------

        # The path (points [u, v] on the view's plane) cut into pieces whose
        # axis-aligned boxes hug the corridor, so a diagonal stretch does not read
        # a square of points to keep a strip: a segment is cut into pieces about
        # `width` across, at most `most` pieces in all. Returns [pieces, length]:
        # each piece { 'start' (chainage at its segment's start), 'a' (that
        # start), 'direction', 'from', 'to' (along the segment), 'last',
        # 'low', 'high' ([u, v], grown by half the width) }.
        def self.Na__Height__Pieces(path, width, most)
            raise ArgumentError, 'path needs at least two points.' if path.length < 2
            segments = []
            chainage = 0.0
            path.each_cons(2) do |a, b|
                du = b[0] - a[0]
                dv = b[1] - a[1]
                length = Math.sqrt(du * du + dv * dv)
                raise ArgumentError, "Two neighbouring path points are #{length == 0 ? 'the same' : 'all but the same'} in this view." if length < 1e-6
                segments << { 'a' => a, 'direction' => [du / length, dv / length], 'length' => length, 'start' => chainage }
                chainage += length
            end
            wanted = segments.map do |segment|
                slant = segment['direction'].map(&:abs).min
                [(segment['length'] * slant / width).ceil, 1].max
            end
            total = wanted.sum
            wanted = wanted.map { |n| [(n * most.to_f / total).floor, 1].max } if total > most
            half = 0.5 * width
            pieces = []
            segments.each_with_index do |segment, index|
                n = wanted[index]
                n.times do |k|
                    from = segment['length'] * k / n
                    to = segment['length'] * (k + 1) / n
                    ends = [from, to].map { |t| [segment['a'][0] + segment['direction'][0] * t, segment['a'][1] + segment['direction'][1] * t] }
                    pieces << {
                        'start' => segment['start'], 'a' => segment['a'], 'direction' => segment['direction'],
                        'from' => from, 'to' => to, 'last' => index == segments.length - 1 && k == n - 1,
                        'low' => (0..1).map { |i| ends.map { |e| e[i] }.min - half },
                        'high' => (0..1).map { |i| ends.map { |e| e[i] }.max + half }
                    }
                end
            end
            [pieces, chainage]
        end

        # For points read from one piece's box: each point's station
        # (floor(chainage / step), at most count - 1) when it lies along this
        # piece (from <= along < to; the path's very end counts) and within half
        # of the path; -1 otherwise. axes: 'u' => [axis, sign], 'v' =>
        # [axis, sign], 'h' => axis. Returns [stations, values, chainages].
        def self.Na__Height__Stations(xyz, axes, piece, half, step, count)
            ui, us = axes['u']
            vi, vs = axes['v']
            hi = axes['h']
            toward = (axes['toward'] || 1).to_f
            au, av = piece['a']
            du, dv = piece['direction']
            from = piece['from']
            to = piece['to']
            last = piece['last']
            start = piece['start']
            n = xyz.length / 3
            stations = Array.new(n, -1)
            values = Array.new(n)
            chainages = Array.new(n)
            i = 0
            while i < n
                base = 3 * i
                pu = us * xyz[base + ui] - au
                pv = vs * xyz[base + vi] - av
                along = pu * du + pv * dv
                if along >= from && (along < to || (last && along <= to)) && (pv * du - pu * dv).abs <= half
                    chainage = start + along
                    station = (chainage / step).floor
                    stations[i] = station < count ? station : count - 1
                    chainages[i] = chainage
                end
                values[i] = toward * xyz[base + hi]
                i += 1
            end
            [stations, values, chainages]
        end

        # value = slope x chainage + intercept through the pairs (nil skipped),
        # least squares: { 'slope', 'intercept', 'rms', 'points' }, or nil under two.
        def self.Na__Height__Line(xs, ys)
            pairs = xs.zip(ys).reject { |_, y| y.nil? }
            n = pairs.length
            return nil if n < 2
            mx = pairs.sum { |x, _| x } / n
            my = pairs.sum { |_, y| y } / n
            sxx = pairs.sum { |x, _| (x - mx)**2 }
            return nil if sxx <= 0
            slope = pairs.sum { |x, y| (x - mx) * (y - my) } / sxx
            intercept = my - slope * mx
            rms = Math.sqrt(pairs.sum { |x, y| (y - (slope * x + intercept))**2 } / n)
            { 'slope' => slope, 'intercept' => intercept, 'rms' => rms, 'points' => n }
        end

        # The steepest rise or fall between two filled stations at least span
        # apart (the nearest such pair from each station): { 'slope', 'from',
        # 'to' }, or nil when the filled ones are never span apart.
        def self.Na__Height__Steepest(xs, ys, span)
            pairs = xs.zip(ys).reject { |_, y| y.nil? }
            best = nil
            j = 0
            pairs.each_with_index do |(x, y), i|
                j = i + 1 if j <= i
                j += 1 while j < pairs.length && pairs[j][0] - x < span
                break if j >= pairs.length
                slope = (pairs[j][1] - y) / (pairs[j][0] - x)
                best = { 'slope' => slope, 'from' => x, 'to' => pairs[j][0] } if best.nil? || slope.abs > best['slope'].abs
            end
            best
        end

        # The picture of a profile: chainage across, value up (exaggerated).
        # low and high: the value range to show. exaggeration: nil picks 1, 2, 5,
        # 10, 20, 50 or 100 so the range is about NA_PROFILE_TALL px high.
        # Returns { 'left', 'top' (px of chainage 0 and of the value 'high'),
        # 'per_unit' (px a unit of chainage), 'exaggeration', 'high', 'low',
        # 'width', 'height' }.
        def self.Na__Height__ProfileFrame(length, low, high, exaggeration)
            range = high - low
            pad = [0.05 * range, 0.002 * length, 1e-3].max
            low -= pad
            high += pad
            range = high - low
            per_unit = NA_PROFILE_PX / length
            if exaggeration.nil?
                want = NA_PROFILE_TALL / (range * per_unit)
                exaggeration = NA_NICE.reverse.find { |e| e <= want } || 1
            end
            tall = range * per_unit * exaggeration
            per_unit *= NA_PROFILE_MAX_PX / tall if tall > NA_PROFILE_MAX_PX
            {
                'left' => NA_MARGIN_PX, 'top' => NA_MARGIN_PX, 'per_unit' => per_unit, 'exaggeration' => exaggeration,
                'high' => high, 'low' => low,
                'width' => 2 * NA_MARGIN_PX + (length * per_unit).ceil + 1,
                'height' => 2 * NA_MARGIN_PX + (range * per_unit * exaggeration).ceil + 1
            }
        end

        # RGB rows: a light grid every grid_x along and grid_y up (0: none), the
        # points ([[chainage, value], ...]) grey, then each line ([rgb,
        # [[chainage, value or nil], ...]], broken where nil) two pixels thick.
        def self.Na__Height__ProfilePicture(frame, points, lines, grid_x, grid_y)
            width = frame['width']
            height = frame['height']
            rows = Array.new(height) { ("\xFF".b * (3 * width)) }
            x_of = ->(chainage) { frame['left'] + chainage * frame['per_unit'] }
            y_of = ->(value) { frame['top'] + (frame['high'] - value) * frame['per_unit'] * frame['exaggeration'] }
            if grid_x > 0
                (0..((width / frame['per_unit']) / grid_x).ceil).each do |k|
                    column = x_of.call(k * grid_x).floor
                    height.times { |row| self.na_put(rows, width, height, column, row, NA_GRID_RGB) } if column < width
                end
            end
            if grid_y > 0
                ((frame['low'] / grid_y).ceil..(frame['high'] / grid_y).floor).each do |k|
                    row = y_of.call(k * grid_y).floor
                    width.times { |column| self.na_put(rows, width, height, column, row, NA_GRID_RGB) }
                end
            end
            points.each { |chainage, value| self.na_put(rows, width, height, x_of.call(chainage).floor, y_of.call(value).floor, NA_POINT_RGB) }
            lines.each do |rgb, stations|
                stations.each_cons(2) do |(c0, v0), (c1, v1)|
                    next if v0.nil? || v1.nil?
                    x0 = x_of.call(c0)
                    y0 = y_of.call(v0)
                    x1 = x_of.call(c1)
                    y1 = y_of.call(v1)
                    steps = [[(x1 - x0).abs, (y1 - y0).abs].max.ceil, 1].max
                    (0..steps).each do |s|
                        column = (x0 + (x1 - x0) * s / steps).floor
                        row = (y0 + (y1 - y0) * s / steps).floor
                        self.na_put(rows, width, height, column, row, rgb)
                        self.na_put(rows, width, height, column, row + 1, rgb)
                    end
                end
                stations.each_with_index do |(chainage, value), i|
                    next if value.nil?
                    before = i > 0 ? stations[i - 1][1] : nil
                    after = i + 1 < stations.length ? stations[i + 1][1] : nil
                    next unless before.nil? && after.nil?
                    # A filled station alone between gaps: a short tick, so it shows.
                    column = x_of.call(chainage).floor
                    row = y_of.call(value).floor
                    (-2..2).each { |dx| self.na_put(rows, width, height, column + dx, row, rgb) }
                end
            end
            rows
        end

        def self.na_put(rows, width, height, column, row, rgb)
            return if column < 0 || row < 0 || column >= width || row >= height
            line = rows[row]
            line.setbyte(3 * column, rgb[0])
            line.setbyte(3 * column + 1, rgb[1])
            line.setbyte(3 * column + 2, rgb[2])
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
