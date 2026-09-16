# =============================================================================
# NA NOBLE3D MODELLING TOOLS - VEGETATION SKETCHER - TREE FORMS
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__VegetationSketcher__TreeForms__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__VegetationSketcher__TreeForms
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Species envelopes and timber tubes on the shared quad lattice
# CREATED    : 2026
#
# Species envelopes deform the same closed quad lattice as other vegetation.
# Units remain millimetres until Builder converts to SketchUp inches.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__VegetationSketcher__TreeForms

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_OAK_LOBES = [[-0.48, 5, 0.2], [0.08, 7, 0.7], [0.68, 5, 0.1]].flat_map do |z, count, phase|
            count.times.map do |i|
                angle = phase + i * Math::PI * 2 / count
                r = Math.sqrt(1 - z * z)
                [Math.cos(angle) * r, Math.sin(angle) * r, z]
            end
        end.freeze

        NA_SPECIES = %w[douglas_fir english_oak].freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Species API
# -----------------------------------------------------------------------------

        # FUNCTION | True When the Settings Use a Named Tree Species
        # ------------------------------------------------------------
        def self.Na__VegetationSketcher__TreeForms__Species?(options)
            options['preset'] == 'tree' && NA_SPECIES.include?(options['tree_type'])
        end
        # ------------------------------------------------------------

        # FUNCTION | Map a Unit Sphere Point Onto the Species Crown
        # ------------------------------------------------------------
        def self.Na__VegetationSketcher__TreeForms__Crown(unit, dims, options)
            if options['tree_type'] == 'douglas_fir'
                na_douglas_fir_crown(unit, dims, options)
            else
                na_english_oak_crown(unit, dims, options)
            end
        end
        # ------------------------------------------------------------

        # FUNCTION | Fit Displaced Foliage to the Requested Width Depth Height
        # ------------------------------------------------------------
        def self.Na__VegetationSketcher__TreeForms__FitDimensions!(points, dims, offset)
            3.times do |axis|
                low, high = points.map { |p| p[axis] }.minmax
                span = high - low
                raise ArgumentError, 'Tree dimensions collapsed. Increase the tree size.' if span <= 1.0e-8

                start = axis == 2 ? offset : -dims[axis] / 2.0
                points.each { |p| p[axis] = start + (p[axis] - low) / span * dims[axis] }
            end
        end
        # ------------------------------------------------------------

        # FUNCTION | Trunk and Branch Tubes For the Named Species
        # ------------------------------------------------------------
        def self.Na__VegetationSketcher__TreeForms__Timber(options)
            points, faces = [], []
            h, clear = options['height'].to_f, options['trunk_height'].to_f
            crown = h - clear
            radius = options['trunk_diameter'] / 2.0
            if options['tree_type'] == 'douglas_fir'
                na_tube(
                    points,
                    faces,
                    [[0, 0, 0], [0, 0, clear], [0, 0, clear + crown * 0.50], [0, 0, clear + crown * 0.96]],
                    [radius, radius * 0.92, radius * 0.45, radius * 0.035]
                )
            else
                na_english_oak_timber(points, faces, options, clear, crown, radius)
            end
            { points: points, faces: faces }
        end
        # ------------------------------------------------------------

        # FUNCTION | 3D Cross Product Used by Topology Checks
        # ------------------------------------------------------------
        def self.Na__VegetationSketcher__TreeForms__Cross(a, b)
            na_cross(a, b)
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Crown Envelopes
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Broad Lower Whorls and a Narrow Leader
        # ------------------------------------------------------------
        def self.na_douglas_fir_crown(unit, dims, options)
            x, y, z = unit
            t = ((z + 1.0) / 2.0).clamp(0.0, 1.0)
            angle = Math.atan2(y, x)
            phase = (options['seed'] % 997) / 997.0 * Math::PI * 2
            round = options['soften'] / 100.0
            radius = (1.0 - t)**0.86 * (1.0 - Math.exp(-t * 42.0))
            tier = 1.0 - (0.12 + (1.0 - round) * 0.10) * (0.5 + 0.5 * Math.cos(t * Math::PI * 16))
            radial = Math.hypot(x, y)
            radius *= tier * (1 + 0.035 * Math.sin(angle * 7 + phase + t * 4))
            ratio = radial > 1.0e-9 ? radius / radial : 0.0
            [x * ratio * dims[0] / 2.0, y * ratio * dims[1] / 2.0, z * dims[2] / 2.0]
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Single Lobed Oak Crown
        # ------------------------------------------------------------
        def self.na_english_oak_crown(unit, dims, options)
            x, y, z = unit
            angle = Math.atan2(y, x)
            phase = (options['seed'] % 997) / 997.0 * Math::PI * 2
            round = options['soften'] / 100.0
            equator = [1 - z * z, 0].max
            rx = x * Math.cos(phase) - y * Math.sin(phase)
            ry = x * Math.sin(phase) + y * Math.cos(phase)
            clusters = NA_OAK_LOBES.sum { |a, b, c| Math.exp((rx * a + ry * b + z * c - 1) * 22) }
            lobe = 0.83 + (0.28 + (1 - round) * 0.18) * clusters
            spread = lobe * (1.0 - z * 0.10)
            top = z * lobe + 0.04 * Math.sin(angle * 4 + phase) * equator
            [x * spread * dims[0] / 2.0, y * spread * dims[1] / 2.0, top * dims[2] / 2.0]
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Timber Tubes
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Stout Bole Plus Five Rising Scaffold Limbs
        # ------------------------------------------------------------
        def self.na_english_oak_timber(points, faces, options, clear, crown, radius)
            phase = (options['seed'] % 997) / 997.0 * Math::PI * 2
            bend = [options['width'], options['depth']].min * 0.018
            spine = [
                [0, 0, 0],
                [0, 0, clear * 0.62],
                [bend * Math.cos(phase), bend * Math.sin(phase), clear + crown * 0.24]
            ]
            na_tube(points, faces, spine, [radius, radius * 0.88, radius * 0.40])
            5.times do |i|
                angle = phase + i * Math::PI * 2 / 5
                start = [0, 0, clear * (0.68 + i * 0.045)]
                middle = [Math.cos(angle) * options['width'] * 0.13, Math.sin(angle) * options['depth'] * 0.13, clear + crown * 0.06]
                tip = [Math.cos(angle + 0.13) * options['width'] * 0.30, Math.sin(angle + 0.13) * options['depth'] * 0.30, clear + crown * 0.40]
                na_tube(points, faces, [start, middle, tip], [radius * 0.50, radius * 0.32, radius * 0.07])
                fork = [Math.cos(angle - 0.32) * options['width'] * 0.26, Math.sin(angle - 0.32) * options['depth'] * 0.26, clear + crown * 0.32]
                na_tube(points, faces, [middle, fork], [radius * 0.20, radius * 0.05])
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | 3D Cross Product
        # ------------------------------------------------------------
        def self.na_cross(a, b)
            [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Unit Vector, Assuming Non-Zero Length
        # ------------------------------------------------------------
        def self.na_unit(v)
            length = Math.sqrt(v.sum { |n| n * n })
            v.map { |n| n / length }
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Closed Tube Along a Polyline of Radii
        # ------------------------------------------------------------
        def self.na_tube(points, faces, centers, radii)
            base, sides = points.length, 8
            centers.each_with_index do |center, index|
                previous, following = centers[[index - 1, 0].max], centers[[index + 1, centers.length - 1].min]
                tangent = na_unit(3.times.map { |k| following[k] - previous[k] })
                side = na_cross(tangent, [0, 0, 1])
                side = side.sum { |n| n * n } < 1.0e-10 ? [1, 0, 0] : na_unit(side)
                other = na_cross(tangent, side)
                sides.times do |i|
                    angle = i * Math::PI * 2 / sides
                    points << 3.times.map { |k| center[k] + radii[index] * (side[k] * Math.cos(angle) + other[k] * Math.sin(angle)) }
                end
            end
            (centers.length - 1).times do |level|
                sides.times do |i|
                    a, b = base + level * sides + i, base + level * sides + (i + 1) % sides
                    faces << [a, b, b + sides, a + sides]
                end
            end
            faces << sides.times.map { |i| base + i }.reverse
            faces << sides.times.map { |i| base + (centers.length - 1) * sides + i }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__VegetationSketcher__TreeForms
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
