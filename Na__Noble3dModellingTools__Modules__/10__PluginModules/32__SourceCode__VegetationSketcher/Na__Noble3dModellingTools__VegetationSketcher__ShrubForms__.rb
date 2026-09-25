# frozen_string_literal: true
# Noble Vegetation Sketcher: closed, low-poly planting-bed envelopes.
# These are indicative forms, authored in millimetres, not botanical models.
module Na__Noble3dModellingTools
    module Na__VegetationSketcher__ShrubForms
        NA_FORMS = {
            'spreading' => [5, 0.16, -0.30, 1.55],
            'cushion'   => [4, 0.055, -0.12, 1.10],
            'rounded'   => [5, 0.13, 0.02, 1.00],
            'loose'     => [6, 0.27, 0.18, 0.95],
            'upright'   => [4, 0.12, -0.38, 0.90],
            'arching'   => [5, 0.25, 0.48, 1.20]
        }.freeze

        def self.na_shrub?(options)
            options['preset'] == 'shrub' && NA_FORMS.key?(options['shrub_type'])
        end

        # Build the random profile once per mesh. Different seeds change the
        # main silhouette as well as the existing fine XYZ displacement.
        def self.na_profile(options)
            rng = Random.new(options['seed'])
            phase = rng.rand * Math::PI * 2
            count = options['shrub_type'] == 'arching' ? 5 : 7
            heads = count.times.map do |i|
                angle = phase + i*Math::PI*2/count + (rng.rand-0.5)*0.35
                z = options['shrub_type'] == 'arching' ? -0.10 + rng.rand*0.65 : 0.12 + rng.rand*0.76
                radial = Math.sqrt(1-z*z)
                [Math.cos(angle)*radial, Math.sin(angle)*radial, z, 0.65+rng.rand*0.65]
            end
            { phase: phase, skew: rng.rand * 0.16 - 0.08,
              lobes: Array.new(6) { 0.65 + rng.rand * 0.7 }, heads: heads }
        end

        def self.na_crown(unit, dims, options)
            count, strength, flare, exponent = NA_FORMS.fetch(options['shrub_type'])
            profile = options['_shrub_profile'] || na_profile(options)
            x, y, z = unit
            angle = Math.atan2(y, x) + profile[:phase]
            belt = [1.0 - z*z, 0].max
            # Smooth periodic lobes avoid overlapping spheres and internal faces.
            clusters = count.times.sum do |i|
                profile[:lobes][i] * Math.exp((Math.cos(angle - i*Math::PI*2/count) - 1) * 6)
            end
            strength *= 1.35 - options['soften'] * 0.006
            radius = (1.0 + flare*z) * (1.0 + strength*(clusters - 0.65)*belt)
            radius *= 1.0 + profile[:skew]*Math.sin(angle*2)*belt
            t = ((z + 1.0) / 2.0).clamp(0,1)**exponent
            # Arching/loose crowns have uneven shoulders while retaining closed
            # poles. The full displaced mesh is fitted to exact requested bounds.
            shoulder = %w[arching loose].include?(options['shrub_type']) ? strength*0.16*(clusters-0.65)*belt : 0.0
            if %w[arching loose].include?(options['shrub_type'])
                # Large foliage heads give loose shrubs a recognisable outline,
                # with one connected skin rather than intersecting clump meshes.
                heads = profile[:heads].sum { |a,b,c,weight| weight*Math.exp((x*a+y*b+z*c-1)*18) }
                clump = 0.70 + (0.78-options['soften']*0.003)*heads
                if options['shrub_type'] == 'arching'
                    return [x*clump*(1+0.45*z)*dims[0]/2, y*clump*(1+0.45*z)*dims[1]/2,
                            (z*clump*0.78-0.16*belt)*dims[2]/2]
                end
                return [x*clump*dims[0]/2, y*clump*dims[1]/2, z*clump*dims[2]/2]
            end
            if options['shrub_type'] == 'upright'
                x += Math.cos(profile[:phase])*0.10*Math.sin(z*Math::PI)*belt
                y += Math.sin(profile[:phase])*0.10*Math.sin(z*Math::PI)*belt
            end
            [x*radius*dims[0]/2, y*radius*dims[1]/2, (t-0.5+shoulder)*dims[2]]
        end
    end
end
