# frozen_string_literal: true
# Wall-local millimetre geometry. X runs across the wall, Y points out and Z
# follows projected world up. Saved loops retain openings when forms are edited.
require_relative 'Na__Noble3dModellingTools__VegetationSketcher__PlantForms__'

module Na__Noble3dModellingTools
    module Na__VegetationSketcher__VineForms
        NA_TYPES = %w[wisteria ivy climber].freeze
        NA_MAX_QUADS = 12_000
        NA_VIEWPORT_QUADS = 6000
        NA_MAX_POINTS = 512

        def self.na_stroke(raw)
            return nil if raw.nil?
            raise ArgumentError, 'Invalid saved vine stroke.' unless raw.is_a?(Hash)
            paths, loops = raw.values_at('paths', 'loops')
            [paths, loops].each do |list|
                unless list.is_a?(Array) && !list.empty? && list.length <= 128 && list.all? { |row| row.is_a?(Array) && row.length >= 2 }
                    raise ArgumentError, 'Invalid saved vine paths or wall boundary.'
                end
            end
            raise ArgumentError, 'Vine stroke is too large. Use several shorter strokes.' if paths.sum(&:length) > NA_MAX_POINTS || loops.sum(&:length) > 2000
            clean = [paths, loops].map do |list|
                list.map do |row|
                    row.map do |point|
                        unless point.is_a?(Array) && point.length == 2 && point.all? { |v| v.is_a?(Numeric) && v.finite? && v.abs <= 1_000_000 }
                            raise ArgumentError, 'Invalid vine point.'
                        end
                        point.map(&:to_f)
                    end
                end
            end
            clean[0].map! { |path| path.each_with_object([]) { |p,list| list << p unless list.last == p } }
            raise ArgumentError, 'Paint a longer vine stroke.' if clean[0].any? { |path| path.length < 2 }
            raise ArgumentError, 'Invalid wall boundary.' if clean[1].any? { |loop| loop.length < 3 }
            length = clean[0].sum { |row| row.each_cons(2).sum { |a,b| Math.hypot(b[0]-a[0], b[1]-a[1]) } }
            raise ArgumentError, 'Paint a stroke between 20 mm and 20 m long.' unless length.between?(20,20_000)
            { 'paths' => clean[0], 'loops' => clean[1] }
        end

        def self.na_example
            { 'paths' => [[[0,0],[-80,450],[60,950],[-30,1400],[170,1850],[650,2050]]],
              'loops' => [[[-1300,-400],[1500,-400],[1500,2700],[-1300,2700]]] }
        end

        # Even/odd polygon containment includes all holes, independent of winding.
        def self.na_inside?(p, loops)
            inside = false
            loops.each do |loop|
                loop.each_with_index do |a,i|
                    b = loop[(i+1)%loop.length]
                    dx, dz = b[0]-a[0], b[1]-a[1]
                    cross = dx*(p[1]-a[1])-dz*(p[0]-a[0])
                    return true if cross.abs < 0.001 && p[0].between?(*[a[0],b[0]].minmax) && p[1].between?(*[a[1],b[1]].minmax)
                    if (a[1] > p[1]) != (b[1] > p[1]) && p[0] < dx*(p[1]-a[1])/dz + a[0]
                        inside = !inside
                    end
                end
            end
            inside
        end

        def self.na_cross(a,b,c)
            (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
        end

        def self.na_supported_segment?(a,b,loops)
            return false unless na_inside?(a,loops) && na_inside?(b,loops) && na_inside?([(a[0]+b[0])/2,(a[1]+b[1])/2],loops)
            loops.none? do |loop|
                loop.each_with_index.any? do |c,i|
                    d = loop[(i+1)%loop.length]
                    na_cross(a,b,c)*na_cross(a,b,d) < -0.0001 && na_cross(c,d,a)*na_cross(c,d,b) < -0.0001
                end
            end
        end

        def self.na_build(options, preview: false)
            stroke = options['vine_stroke'] || na_example
            level = %w[low medium high].index(options['plant_detail']) || 1
            viewport = preview == :viewport
            paths = stroke['paths']
            total = paths.sum { |path| path.each_cons(2).sum { |a,b| Math.hypot(b[0]-a[0],b[1]-a[1]) } }
            # Long strokes spread their branching budget across the whole path.
            count = [(total / (22000.0/options['vine_density'])).ceil, [24,36,48][level]].min.clamp(2,48)
            mesh = WallWriter.new(stroke['loops'])
            rng = Random.new(options['seed'])
            offset = options['vine_offset']
            paths.each do |path|
                path.each_cons(2) { |a,b| mesh.safe { mesh.stem([a[0],offset,a[1]],[b[0],offset,b[1]],3.0,1,0) } } if path.length > 1
            end
            samples = na_samples(paths, total / count)
            samples.each_with_index do |(p,_tangent),i|
                reach = options['vine_width'] * (0.3+rng.rand*0.2)
                side = i.even? ? 1 : -1
                base = [p[0],offset,p[1]]
                tip = [p[0]+side*reach,offset+15+rng.rand*25,p[1]+reach*(0.25+rng.rand*0.6)]
                arch = options['soften']/100.0
                bend = [(options['random']/500.0),1].min * (rng.rand-0.5)*reach*0.3
                branch = (0..4).map do |j|
                    t=j/4.0
                    [base[0]+(tip[0]-base[0])*t+bend*Math.sin(t*Math::PI),
                     base[1]+(tip[1]-base[1])*t+arch*20*Math.sin(t*Math::PI),
                     base[2]+(tip[2]-base[2])*t]
                end
                # Stop branches at openings/edges instead of leaving floating leaves.
                valid = [branch.first]
                branch.each_cons(2) do |a,b|
                    break unless mesh.safe { mesh.stem(a,b,1.8,1,0) }
                    valid << b
                end
                next if valid.length < 2
                leaves = options['vine_type'] == 'wisteria' ? 6 : 4
                leaves.times do |j|
                    t=(j+1).to_f/(leaves+1)
                    pos=na_interpolate(valid,t)
                    angle=(side > 0 ? 0 : Math::PI)+(j.even? ? -0.7 : 0.7)
                    size=options['vine_leaf_size']*(0.75+rng.rand*0.5)
                    mesh.leaf(pos,size,angle,options['vine_type'],viewport ? 2 : [3,4,5][level],arch)
                end
                bloom_rng=Random.new(options['seed']+i*7919+104729)
                next unless options['vine_type'] == 'wisteria' && bloom_rng.rand*100 < options['vine_flowers']
                top=valid.last
                drop=options['vine_leaf_size']*(2.4+bloom_rng.rand*1.8)
                radius=options['vine_leaf_size']*0.24
                bloom_top=[top[0]+(bloom_rng.rand-0.5)*20,top[1]+radius+8,top[2]-10]
                finish=[bloom_top[0],bloom_top[1],bloom_top[2]-drop]
                attached=mesh.safe do
                    mesh.stem(top,bloom_top,1.8,1,0)
                    mesh.stem(bloom_top,finish,1.8,viewport ? 2 : 4,0)
                end
                if attached
                    # Tapered, lobed hanging racemes, kept above the wall plane.
                    mesh.raceme(bloom_top,drop,radius,viewport ? 4 : 8,viewport ? 4 : 8)
                end
            end
            points, quads = mesh.points, mesh.quads
            raise ArgumentError, 'No vine fits inside this wall boundary. Paint farther from the edge or use a wider face.' if quads.empty?
            cap = viewport ? NA_VIEWPORT_QUADS : NA_MAX_QUADS
            raise ArgumentError, 'Vine detail exceeds the mesh limit. Use a shorter stroke.' if quads.length > cap
            dims = 3.times.map { |axis| lo,hi=points.map { |p| p[axis] }.minmax; lo ? hi-lo : 0 }
            { points: points, quads: quads, trunk: { points: [], faces: [] },
              requested_quads: quads.length, resolution: options['resolution'], dimensions: dims,
              path: nil, form_mode: 'vine', preview_coarse: viewport, viewport_preview: viewport }
        end

        def self.na_samples(paths, spacing)
            paths.flat_map do |path|
                result=[]
                remaining=spacing*0.35
                path.each_cons(2) do |a,b|
                    length=Math.hypot(b[0]-a[0],b[1]-a[1])
                    next if length < 0.001
                    while remaining <= length
                        t=remaining/length
                        result << [[a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t],[(b[0]-a[0])/length,(b[1]-a[1])/length]]
                        remaining+=spacing
                    end
                    remaining-=length
                end
                result
            end
        end

        def self.na_interpolate(points,t)
            position=t*(points.length-1)
            i=[position.floor,points.length-2].min
            3.times.map { |axis| points[i][axis]+(points[i+1][axis]-points[i][axis])*(position-i) }
        end

        class WallWriter < Na__VegetationSketcher__PlantForms::MeshWriter
            def initialize(loops); super(); @loops=loops; end
            def safe
                first, face_first = @points.length, @quads.length
                yield
                supported = @quads[face_first..].all? do |quad|
                    xy=quad.map { |id| [@points[id][0],@points[id][2]] }
                    edges_fit=xy.each_with_index.all? { |a,i| Na__VegetationSketcher__VineForms.na_supported_segment?(a,xy[(i+1)%4],@loops) }
                    # A small opening can sit wholly inside a large leaf quad.
                    # Edge intersection alone would miss that case.
                    min_x,max_x=xy.map(&:first).minmax
                    min_z,max_z=xy.map(&:last).minmax
                    covers_opening=@loops.any? do |loop|
                        loop.any? { |p| p[0]>min_x && p[0]<max_x && p[1]>min_z && p[1]<max_z && Na__VegetationSketcher__VineForms.na_inside?(p,[xy]) }
                    end
                    edges_fit && !covers_opening
                end
                unless supported
                    @points.slice!(first..); @quads.slice!(face_first..)
                end
                supported
            end

            def leaf(base,size,angle,type,steps,arch)
                safe do
                    rows=(0..steps).map do |i|
                        t=i.to_f/steps
                        width=size*(type=='ivy' ? 0.48 : 0.23)*(0.04+Math.sin(t*Math::PI)**0.7)
                        width*=0.72+0.28*Math.cos(t*Math::PI*6) if type=='ivy'
                        [-1,0,1].map do |side|
                            along=size*t
                            point([base[0]+Math.cos(angle)*along-Math.sin(angle)*width*side,
                                   base[1]+12+Math.sin(t*Math::PI)*size*(0.15+arch*0.2)+(side.zero? ? width*0.3 : 0),
                                   base[2]+Math.sin(angle)*along+Math.cos(angle)*width*side])
                        end
                    end
                    steps.times { |i| 2.times { |j| quad(rows[i][j],rows[i+1][j],rows[i+1][j+1],rows[i][j+1]) } }
                end
            end

            def raceme(top,length,radius,rings,sides)
                safe do
                    rows=(0..rings).map do |i|
                        t=i.to_f/rings
                        r=radius*(0.12+(1-t)**0.6)*(0.7+0.3*Math.cos(t*Math::PI*8))
                        sides.times.map do |j|
                            a=j*Math::PI*2/sides
                            point([top[0]+Math.cos(a)*r,top[1]+Math.sin(a)*r,top[2]-length*t])
                        end
                    end
                    rings.times { |i| sides.times { |j| quad(rows[i][j],rows[i][(j+1)%sides],rows[i+1][(j+1)%sides],rows[i+1][j]) } }
                    [rows.first.reverse,rows.last].each do |row|
                        if sides == 4
                            quad(*row)
                            next
                        end
                        center=point(3.times.map { |axis| row.sum { |id| @points[id][axis] }/sides })
                        (sides/2).times { |j| quad(row[j*2],row[(j*2+1)%sides],row[(j*2+2)%sides],center) }
                    end
                end
            end
        end
    end
end
