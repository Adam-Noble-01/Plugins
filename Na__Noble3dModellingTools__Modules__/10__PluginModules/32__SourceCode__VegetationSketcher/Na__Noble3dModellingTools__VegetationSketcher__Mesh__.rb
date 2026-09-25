# =============================================================================
# NA NOBLE3D MODELLING TOOLS - VEGETATION SKETCHER - MESH
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__VegetationSketcher__Mesh__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__VegetationSketcher__Mesh
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Build the closed millimetre quad lattice used by panel preview,
#              viewport drawing and final SketchUp creation
# CREATED    : 2026
#
# Pure millimetre geometry. No model mutations: shared vertices and outward
# quad winding survive rounding, noise, preview and final triangulation.
#
# =============================================================================

require_relative 'Na__Noble3dModellingTools__VegetationSketcher__TreeForms__'
require_relative 'Na__Noble3dModellingTools__VegetationSketcher__ShrubForms__'
require_relative 'Na__Noble3dModellingTools__VegetationSketcher__PlantForms__'

module Na__Noble3dModellingTools
    module Na__VegetationSketcher__Mesh

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_MAX_QUADS      = 80_000
        NA_PREVIEW_QUADS  = 2600
        NA_VIEWPORT_QUADS = 1300

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Mesh API
# -----------------------------------------------------------------------------

        # FUNCTION | Build Foliage Points, Quads and Optional Trunk Faces
        # ------------------------------------------------------------
        def self.Na__VegetationSketcher__Mesh__Build(options, length: nil, preview: false)
            return Na__VegetationSketcher__PlantForms.na_build(options, preview: preview) if Na__VegetationSketcher__PlantForms.na_plant?(options)
            if Na__VegetationSketcher__ShrubForms.na_shrub?(options)
                options = options.merge('_shrub_profile' => Na__VegetationSketcher__ShrubForms.na_profile(options))
            end
            dims = na_dimensions(options, length)
            path = options['preset'] == 'hedge' && options['path'] ? Na__VegetationSketcher__HedgePath.Na__VegetationSketcher__HedgePath__Prepare(options['path'], options['width']) : nil
            resolution = options['resolution'].to_f
            requested = na_count(dims, resolution, path)
            na_reject_over_budget(requested) unless preview
            resolution = na_preview_resolution(dims, resolution, path, preview) if preview
            div = na_grid(dims, resolution, path)
            stations = path ? Na__VegetationSketcher__HedgePath.Na__VegetationSketcher__HedgePath__Stations(path, resolution) : nil
            points, quads = na_closed_lattice(dims, div, options, path, stations)
            na_ground_and_fit!(points, dims, options, path)
            {
                points:           points,
                quads:            quads,
                trunk:            na_trunk(options),
                requested_quads:  requested,
                resolution:       resolution.round(1),
                preview_coarse:   resolution > options['resolution'],
                dimensions:       dims,
                path:             options['path'],
                viewport_preview: preview == :viewport
            }
        end
        # ------------------------------------------------------------

        # FUNCTION | Axis Lengths Used by Quad Budget and Drawing Scale
        # ------------------------------------------------------------
        def self.Na__VegetationSketcher__Mesh__Dimensions(options, length = nil)
            na_dimensions(options, length)
        end
        # ------------------------------------------------------------

        # FUNCTION | Closed-Box Quad Count For a Resolution
        # ------------------------------------------------------------
        def self.Na__VegetationSketcher__Mesh__Count(dims, resolution, path = nil)
            na_count(dims, resolution, path)
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Lattice Sizing
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Length Width Height of the Foliage Envelope
        # ------------------------------------------------------------
        def self.na_dimensions(options, length = nil)
            if options['preset'] == 'hedge'
                [options['path'] ? Na__VegetationSketcher__HedgePath.Na__VegetationSketcher__HedgePath__Length(options['path']) : (length || options['length']), options['width'], options['height']]
            else
                [options['width'], options['depth'], options['height'] - (options['preset'] == 'tree' ? options['trunk_height'] : 0)]
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Integer Divisions Along Each Axis
        # ------------------------------------------------------------
        def self.na_divisions(dims, resolution)
            dims.map { |d| [(d / resolution.to_f).ceil, 2].max }
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Lattice Counts, Including Path Stretch
        # ------------------------------------------------------------
        def self.na_grid(dims, resolution, path = nil)
            div = na_divisions(dims, resolution)
            if path
                div[0] = path[:segments].sum { |s| [(s[:mesh_length] / resolution).ceil, 1].max }
                div[1] = [(dims[1] * path[:width_scale] / resolution).ceil, 2].max
            end
            div
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Closed Quad Count For Six Faces
        # ------------------------------------------------------------
        def self.na_count(dims, resolution, path = nil)
            x, y, z = na_grid(dims, resolution, path)
            2 * (x * y + x * z + y * z)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Reject a Final Mesh Over the Quad Budget
        # ------------------------------------------------------------
        def self.na_reject_over_budget(requested)
            return unless requested > NA_MAX_QUADS

            formatted = requested.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
            raise ArgumentError, "#{formatted} quads exceeds the 80,000 limit. Choose a coarser resolution or a smaller form."
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Coarsen Drawing Resolution Within the Preview Cap
        # ------------------------------------------------------------
        def self.na_preview_resolution(dims, resolution, path, preview)
            viewport = preview == :viewport
            resolution *= 2.0 if viewport
            budget = viewport ? NA_VIEWPORT_QUADS : NA_PREVIEW_QUADS
            resolution *= 1.15 while na_count(dims, resolution, path) > budget
            resolution
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Closed Lattice
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Shared-Vertex Hexahedron, Optionally Swept
        # ------------------------------------------------------------
        def self.na_closed_lattice(dims, div, options, path, stations)
            points, quads, lookup = [], [], {}
            3.times do |axis|
                u, v = (axis + 1) % 3, (axis + 2) % 3
                [0, div[axis]].each do |side|
                    div[u].times do |i|
                        div[v].times do |j|
                            ids = [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]].map do |a, b|
                                key = [0, 0, 0]
                                key[axis], key[u], key[v] = side, a, b
                                lookup[key] ||= begin
                                    p = 3.times.map { |k| dims[k] * (key[k].to_f / div[k] - 0.5) }
                                    p[0] = stations[key[0]] - dims[0] / 2.0 if stations
                                    points << na_shape(p, dims, options, div, path: path)
                                    points.length - 1
                                end
                            end
                            ids.reverse! if side.zero?
                            quads << ids
                        end
                    end
                end
            end
            [points, quads]
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Ground the Form and Fit Species Bounds
        # ------------------------------------------------------------
        def self.na_ground_and_fit!(points, dims, options, path)
            offset = options['preset'] == 'tree' ? options['trunk_height'] : 0.0
            points.each do |p|
                p[0] += dims[0] / 2.0 if options['preset'] == 'hedge' && !path
                p[2] += dims[2] / 2.0 + offset unless path
                p[2] = [p[2], 0.0].max
            end
            if Na__VegetationSketcher__TreeForms.Na__VegetationSketcher__TreeForms__Species?(options) || Na__VegetationSketcher__ShrubForms.na_shrub?(options)
                Na__VegetationSketcher__TreeForms.Na__VegetationSketcher__TreeForms__FitDimensions!(points, dims, offset)
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Round, Optionally Warp, Then Displace One Vertex
        # ------------------------------------------------------------
        def self.na_shape(p, dims, options, div, path: nil)
            half = dims.map { |d| d / 2.0 }
            rounded, sphere = na_rounded_point(p, half, options, dims)
            amplitude = [options['random'].to_f, dims.min * 0.18].min
            cell = 3.times.map { |k| dims[k] / div[k] }.min
            wave = [dims.min * 0.55, 250.0, amplitude * 8].max
            ground = ((rounded[2] + half[2]) / [half[2] * 0.35, 1].max).clamp(0.0, 1.0)
            ground = 1.0 if options['preset'] == 'tree'
            detail = na_species_detail(options, sphere)
            rounded = Na__VegetationSketcher__HedgePath.Na__VegetationSketcher__HedgePath__Warp([rounded[0] + half[0], rounded[1], rounded[2] + half[2]], path) if path
            3.times.map do |k|
                drift = na_noise(rounded.map { |x| x / wave }, options['seed'] + k * 103) * amplitude
                jitter = na_hash_noise(*(p.map { |x| (x * 100).round }), options['seed'] + k * 997) * [amplitude * 0.14, cell * 0.12].min * detail
                rounded[k] + (drift + jitter) * ground
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Hedge Superellipse or Tree/Shrub Crown Point
        # ------------------------------------------------------------
        def self.na_rounded_point(p, half, options, dims)
            amount = options['soften'] / 100.0
            sphere = nil
            if options['preset'] == 'hedge'
                radius = half.min * amount * 0.95
                core = 3.times.map { |k| p[k].clamp(-half[k] + radius, half[k] - radius) }
                delta = 3.times.map { |k| p[k] - core[k] }
                magnitude = Math.sqrt(delta.sum { |x| x * x })
                rounded = magnitude.zero? ? p.dup : 3.times.map { |k| core[k] + delta[k] * radius / magnitude }
            else
                a = 3.times.map { |k| p[k] / half[k] }
                sphere = 3.times.map do |k|
                    b, c = a[(k + 1) % 3]**2, a[(k + 2) % 3]**2
                    a[k] * Math.sqrt([1.0 - b / 2 - c / 2 + b * c / 3, 0].max)
                end
                rounded = if Na__VegetationSketcher__TreeForms.Na__VegetationSketcher__TreeForms__Species?(options)
                              Na__VegetationSketcher__TreeForms.Na__VegetationSketcher__TreeForms__Crown(sphere, dims, options)
                          elsif Na__VegetationSketcher__ShrubForms.na_shrub?(options)
                              Na__VegetationSketcher__ShrubForms.na_crown(sphere, dims, options)
                          else
                              3.times.map { |k| p[k] * (1 - amount) + sphere[k] * half[k] * amount }
                          end
            end
            [rounded, sphere]
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Reduce Jitter on a Conifer Tip
        # ------------------------------------------------------------
        def self.na_species_detail(options, sphere)
            return 1.0 unless Na__VegetationSketcher__TreeForms.Na__VegetationSketcher__TreeForms__Species?(options) && options['tree_type'] == 'douglas_fir'
            return 1.0 unless sphere

            t = ((sphere[2] + 1.0) / 2.0).clamp(0.0, 1.0)
            [t * 20.0, (1.0 - t) * 8.0, 1.0].min
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Deterministic Hash Noise in -1..1
        # ------------------------------------------------------------
        def self.na_hash_noise(x, y, z, seed)
            n = (x * 374761393 + y * 668265263 + z * 2147483647 + seed * 1274126177) & 0xffffffff
            n = ((n ^ (n >> 13)) * 1274126177) & 0xffffffff
            ((n ^ (n >> 16)) & 0xffffffff) / 2147483647.5 - 1.0
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Trilinear Value Noise
        # ------------------------------------------------------------
        def self.na_noise(p, seed)
            base = p.map(&:floor)
            t = 3.times.map { |k| f = p[k] - base[k]; f * f * (3 - 2 * f) }
            value = 0.0
            2.times do |x|
                2.times do |y|
                    2.times do |z|
                        weight = (x.zero? ? 1 - t[0] : t[0]) * (y.zero? ? 1 - t[1] : t[1]) * (z.zero? ? 1 - t[2] : t[2])
                        value += weight * na_hash_noise(base[0] + x, base[1] + y, base[2] + z, seed)
                    end
                end
            end
            value
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Generic Trunk Prism, or Species Timber
        # ------------------------------------------------------------
        def self.na_trunk(options)
            return { points: [], faces: [] } unless options['preset'] == 'tree'
            return Na__VegetationSketcher__TreeForms.Na__VegetationSketcher__TreeForms__Timber(options) if Na__VegetationSketcher__TreeForms.Na__VegetationSketcher__TreeForms__Species?(options)

            points = []
            [0, options['trunk_height'] + (options['height'] - options['trunk_height']) * 0.42].each_with_index do |z, level|
                8.times do |i|
                    angle = i * Math::PI / 4
                    r = options['trunk_diameter'] / 2.0 * (level.zero? ? 1.0 : 0.62)
                    points << [Math.cos(angle) * r, Math.sin(angle) * r, z]
                end
            end
            faces = 8.times.map { |i| [i, (i + 1) % 8, (i + 1) % 8 + 8, i + 8] }
            faces << (0...8).to_a.reverse << (8...16).to_a
            { points: points, faces: faces }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__VegetationSketcher__Mesh
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
