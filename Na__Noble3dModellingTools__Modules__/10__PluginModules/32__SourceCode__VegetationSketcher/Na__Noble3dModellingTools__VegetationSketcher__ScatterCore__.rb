# frozen_string_literal: true
# Noble Vegetation Scatter: deterministic sampling and triangle acceleration.
# Geometry arrays use SketchUp inches; UI distances are millimetres.
module Na__Noble3dModellingTools
    module Na__VegetationSketcher__ScatterCore
        NA_DEFAULTS = { 'radius' => 10000.0, 'spacing' => 3000.0, 'chance' => 100.0,
            'scale_min' => 85.0, 'scale_max' => 115.0, 'rotation' => 360.0,
            'slope' => 60.0, 'align' => false, 'seed' => 12345, 'limit' => 2000 }.freeze
        NA_LIMITS = { 'radius' => [250, 100000], 'spacing' => [100, 50000], 'chance' => [0, 100],
            'scale_min' => [5, 500], 'scale_max' => [5, 500], 'rotation' => [0, 360],
            'slope' => [0, 90], 'seed' => [1, 2147483646], 'limit' => [1, 10000] }.freeze

        def self.na_options(raw = {})
            raise ArgumentError, 'Scatter settings must be an object.' unless raw.is_a?(Hash)
            out = NA_DEFAULTS.dup
            NA_LIMITS.each do |key, (low, high)|
                next unless raw.key?(key)
                value = Float(raw[key])
                raise ArgumentError, "#{key.tr('_', ' ')} must be between #{low} and #{high}." unless value.finite? && value.between?(low, high)
                out[key] = value
            end
            raise ArgumentError, 'Minimum scale must not exceed maximum scale.' if out['scale_min'] > out['scale_max']
            %w[seed limit].each { |key| out[key] = out[key].to_i }
            out['align'] = raw['align'] == true
            out
        end

        def self.na_weights(sources)
            raise ArgumentError, 'Capture at least one tree or shrub source.' if sources.empty?
            weights = sources.map { |source| Float(source.fetch('weight', 1)) }
            raise ArgumentError, 'Source weights must be from 0 to 100.' unless weights.all? { |w| w.finite? && w.between?(0, 100) }
            raise ArgumentError, 'Give at least one source a probability above zero.' unless weights.sum > 0
            weights
        end

        def self.na_add(a, b); 3.times.map { |i| a[i] + b[i] }; end
        def self.na_sub(a, b); 3.times.map { |i| a[i] - b[i] }; end
        def self.na_mul(a, n); a.map { |v| v * n }; end
        def self.na_dot(a, b); 3.times.sum { |i| a[i] * b[i] }; end
        def self.na_cross(a, b); [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]]; end
        def self.na_length(a); Math.sqrt(na_dot(a, a)); end
        def self.na_unit(a); n = na_length(a); n > 1.0e-10 ? na_mul(a, 1.0/n) : [0,0,1]; end
        def self.na_basis(normal)
            n = na_unit(normal)
            x = na_unit(na_cross(n[2].abs < 0.9 ? [0,0,1] : [0,1,0], n))
            [x, na_cross(n, x), n]
        end

        # A spatial hash avoids testing every existing plant for every sample.
        class SpacingGrid
            def initialize(distance); @distance = distance; @cells = Hash.new { |h,k| h[k] = [] }; end
            def na_key(p); p.map { |v| (v / @distance).floor }; end
            def na_insert(p)
                key = na_key(p)
                (-1..1).each do |x|; (-1..1).each do |y|; (-1..1).each do |z|
                    points = @cells.fetch([key[0]+x,key[1]+y,key[2]+z], [])
                    return false if points.any? { |q| 3.times.sum { |i| (q[i]-p[i])**2 } < @distance**2 }
                end; end; end
                @cells[key] << p
                true
            end
        end

        # project(dab, candidate) returns [surface_position, surface_normal].
        # The same seed + dabs + geometry reproduces the same complete forest.
        def self.na_generate(options, sources, dabs, &project)
            options = na_options(options)
            weights = na_weights(sources)
            total_weight = weights.sum
            random = Random.new(options['seed'])
            radius, spacing = options.values_at('radius', 'spacing').map { |v| v / 25.4 }
            attempts = [(Math::PI * radius**2 / spacing**2 * 2).ceil, 1].max
            raise ArgumentError, 'Brush is too dense for this area. Increase spacing or reduce the brush radius.' if attempts * dabs.length > 250000
            grid, result = SpacingGrid.new(spacing), []
            dabs.each do |dab|
                x, y, normal = na_basis(dab.fetch(:normal))
                attempts.times do
                    angle, r = random.rand * Math::PI * 2, Math.sqrt(random.rand) * radius
                    point = na_add(dab.fetch(:point), na_add(na_mul(x, Math.cos(angle)*r), na_mul(y, Math.sin(angle)*r)))
                    chance, pick, scale, yaw = random.rand, random.rand, random.rand, random.rand
                    next if chance >= options['chance'] / 100.0
                    hit = project.call(dab, point)
                    next unless hit
                    position, up = hit
                    up = na_unit(up)
                    up = na_mul(up, -1) if up[2] < 0
                    slope = Math.acos(up[2].clamp(-1,1)) * 180 / Math::PI
                    next if slope > options['slope'] + 1.0e-7 || !grid.na_insert(position)
                    choice, sum = 0, 0.0
                    weights.each_with_index { |weight, i| sum += weight; if pick * total_weight < sum; choice = i; break; end }
                    result << { point: position, normal: options['align'] ? up : [0,0,1], source: choice,
                        scale: (options['scale_min'] + scale * (options['scale_max']-options['scale_min'])) / 100.0,
                        yaw: yaw * options['rotation'] * Math::PI / 180 }
                    return { plants: result, capped: true } if result.length >= options['limit']
                end
            end
            { plants: result, capped: false }
        end

        # Balanced bounding-volume tree: avoids a model raycast for every plant
        # and keeps existing foliage from obstructing the terrain projection.
        class SurfaceIndex
            def initialize(triangles)
                raise ArgumentError, 'The target surface has no usable triangles.' if triangles.empty?
                @root = na_node(triangles)
            end

            def na_node(triangles)
                bounds = 3.times.map { |i| triangles.flat_map { |t| t.map { |p| p[i] } }.minmax }
                return [bounds, triangles] if triangles.length <= 12
                axis = (0..2).max_by { |i| bounds[i][1] - bounds[i][0] }
                sorted = triangles.sort_by { |t| t.sum { |p| p[axis] } }
                mid = sorted.length / 2
                [bounds, nil, na_node(sorted.take(mid)), na_node(sorted.drop(mid))]
            end

            def na_box?(bounds, origin, direction, limit)
                near, far = 0.0, limit
                3.times do |i|
                    if direction[i].abs < 1.0e-12
                        return false unless origin[i].between?(bounds[i][0]-1.0e-7, bounds[i][1]+1.0e-7)
                    else
                        a, b = bounds[i].map { |v| (v-origin[i])/direction[i] }.minmax
                        near, far = [near,a].max, [far,b].min
                        return false if near > far + 1.0e-7
                    end
                end
                true
            end

            def na_hit(origin, direction, limit = Float::INFINITY)
                best, stack = nil, [@root]
                core = Na__VegetationSketcher__ScatterCore
                until stack.empty?
                    bounds, triangles, left, right = stack.pop
                    next unless na_box?(bounds, origin, direction, limit)
                    unless triangles
                        stack << left << right
                        next
                    end
                    triangles.each do |a,b,c|
                        e1, e2 = core.na_sub(b,a), core.na_sub(c,a)
                        h = core.na_cross(direction,e2)
                        det = core.na_dot(e1,h).to_f
                        next if det.abs < 1.0e-10
                        s = core.na_sub(origin,a)
                        u = core.na_dot(s,h)/det
                        next if u < -1.0e-8 || u > 1+1.0e-8
                        q = core.na_cross(s,e1)
                        v = core.na_dot(direction,q)/det
                        next if v < -1.0e-8 || u+v > 1+1.0e-8
                        t = core.na_dot(e2,q)/det
                        next if t < 0 || t > limit
                        limit = t
                        best = [core.na_add(origin,core.na_mul(direction,t)), core.na_unit(core.na_cross(e1,e2)), t]
                    end
                end
                best
            end
        end
    end
end
