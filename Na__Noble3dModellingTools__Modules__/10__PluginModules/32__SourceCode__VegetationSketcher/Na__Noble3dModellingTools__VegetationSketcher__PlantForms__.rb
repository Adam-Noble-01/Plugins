# frozen_string_literal: true
# Noble Vegetation Sketcher - articulated whitecard flowers and grasses.
# Separate curved ribbons, stem tubes and flower heads share one bounded mesh.
# Leaves/petals are open, creased surfaces with white front/back materials.
module Na__Noble3dModellingTools
    module Na__VegetationSketcher__PlantForms
        NA_TYPES = %w[daisy_clump flower_spikes umbel_clump tuft_grass fountain_grass plume_grass].freeze
        NA_MAX_QUADS = 2000
        NA_VIEWPORT_QUADS = 1000

        def self.na_plant?(options)
            options['preset'] == 'shrub' && NA_TYPES.include?(options['shrub_type'])
        end

        def self.na_build(options, preview: false)
            level = %w[low medium high].index(options['plant_detail']) || 1
            plan = { count: [0.7,1.0,1.25][level], steps: [4,6,8][level],
                     petals: [2,3,4][level], rings: [6,8,10][level], sides: 8 }
            full = na_geometry(options,plan)
            # Hard bounds also apply at very large model dimensions.
            while full[:quads].length > NA_MAX_QUADS
                plan[:count] *= 0.85
                full = na_geometry(options,plan)
            end
            requested = full[:quads].length
            data = full
            if preview == :viewport
                reduced = plan.merge(steps: [(plan[:steps]/2.0).ceil,2].max,
                    petals: [(plan[:petals]/2.0).ceil,1].max, rings: [(plan[:rings]/2.0).ceil,3].max, sides: 4)
                data = na_geometry(options,reduced)
                while data[:quads].length > NA_VIEWPORT_QUADS
                    reduced[:count] *= 0.85
                    data = na_geometry(options,reduced)
                end
            end
            dims = options.values_at('width','depth','height')
            Na__VegetationSketcher__TreeForms.Na__VegetationSketcher__TreeForms__FitDimensions!(data[:points],dims,0)
            data.merge(trunk: { points: [], faces: [] }, requested_quads: requested,
                resolution: options['resolution'], dimensions: dims, path: nil,
                preview_coarse: preview == :viewport, viewport_preview: preview == :viewport,
                form_mode: 'botanical', detail: options['plant_detail'])
        end

        def self.na_geometry(options, plan)
            maker = MeshWriter.new
            type = options['shrub_type']
            rng = Random.new(options['seed'])
            arch = options['soften']/100.0
            variation = (options['random'].to_f / options.values_at('width','depth','height').min).clamp(0,0.35)
            if type.end_with?('grass')
                na_grass(maker,type,rng,arch,variation,plan)
            else
                na_flowers(maker,type,rng,arch,variation,plan)
            end
            { points: maker.points, quads: maker.quads }
        end

        def self.na_grass(mesh,type,rng,arch,variation,plan)
            count = ((type == 'tuft_grass' ? 32 : 44)*plan[:count]).round
            count.times do |i|
                angle = i*2.399963 + rng.rand*0.35
                outer = (i%4)/3.0
                length = 0.55+rng.rand*0.45
                length *= 0.66 if type == 'plume_grass'
                reach = (0.16+outer*0.34)*(0.8+arch*0.4)
                drop = type == 'tuft_grass' ? 0.16+outer*0.28 : 0.12+outer*(0.35+arch*0.23)
                root = [Math.cos(angle)*rng.rand*0.065, Math.sin(angle)*rng.rand*0.065,0]
                bend = (rng.rand-0.5)*variation
                width = type == 'tuft_grass' ? 0.022+rng.rand*0.013 : 0.026+rng.rand*0.016
                mesh.ribbon(plan[:steps],width,angle) do |t|
                    r = reach*t*t
                    [root[0]+Math.cos(angle)*r+Math.sin(angle)*bend*t*t,
                     root[1]+Math.sin(angle)*r-Math.cos(angle)*bend*t*t,
                     length*(t-drop*t*t*t)]
                end
            end
            return unless type == 'plume_grass'
            (6*plan[:count]).round.times do |i|
                a=i*2.399963+rng.rand*0.3
                height=0.88+rng.rand*0.20
                tip=[Math.cos(a)*(0.15+rng.rand*0.16),Math.sin(a)*(0.15+rng.rand*0.16),height]
                start=[Math.cos(a)*0.03,Math.sin(a)*0.03,0]
                mesh.stem(start,tip,0.004,plan[:steps],variation)
                mesh.head(tip,[0.036,0.036,0.18],plan[:rings],plan[:sides],a,0.18)
            end
        end

        def self.na_flowers(mesh,type,rng,arch,variation,plan)
            # Foliage remains visibly separate from the flowers.
            (12*plan[:count]).round.times do |i|
                a=i*2.399963+rng.rand*0.3
                reach=0.20+rng.rand*0.16
                height=0.18+rng.rand*0.15
                mesh.ribbon(plan[:steps],0.045+rng.rand*0.025,a) do |t|
                    [Math.cos(a)*reach*t,Math.sin(a)*reach*t,height*Math.sin(t*Math::PI*(0.68+arch*0.26))]
                end
            end
            count = ((type == 'umbel_clump' ? 5 : 7)*plan[:count]).round
            count.times do |i|
                a=i*2.399963+rng.rand*0.3
                r=0.08+Math.sqrt(rng.rand)*0.28
                height=0.55+rng.rand*0.37
                tip=[Math.cos(a)*r,Math.sin(a)*r,height]
                base=[Math.cos(a)*0.025,Math.sin(a)*0.025,0]
                mesh.stem(base,tip,0.0045,plan[:steps],variation)
                2.times do |leaf|
                    t=0.25+leaf*0.19
                    origin=mesh.stem_point(base,tip,t,variation)
                    direction=a+leaf*Math::PI
                    mesh.ribbon([plan[:steps]/2,2].max,0.030,direction) do |u|
                        [origin[0]+Math.cos(direction)*0.15*u,origin[1]+Math.sin(direction)*0.15*u,origin[2]+0.09*Math.sin(u*Math::PI*(0.68+arch*0.26))]
                    end
                end
                if type == 'daisy_clump'
                    mesh.flower(tip,0.085+rng.rand*0.025,8,plan[:petals],a,arch,plan[:sides])
                elsif type == 'flower_spikes'
                    mesh.head(tip,[0.035,0.035,0.18],plan[:rings],plan[:sides],a,0.38)
                else
                    6.times do |branch|
                        b=a+branch*Math::PI/3
                        reach=0.085+rng.rand*0.025
                        flower=[tip[0]+Math.cos(b)*reach,tip[1]+Math.sin(b)*reach,tip[2]+0.045+rng.rand*0.025]
                        mesh.stem(tip,flower,0.0025,2,0)
                        mesh.flower(flower,0.040,5,[plan[:petals]-1,1].max,b,arch,4)
                    end
                end
            end
        end

        class MeshWriter
            attr_reader :points,:quads
            def initialize; @points=[]; @quads=[]; end
            def point(p); @points << p; @points.length-1; end
            def quad(*ids); @quads << ids; end

            # Three columns give each leaf a central crease. Nonzero tip widths
            # avoid collapsed triangles and sub-tolerance edges in SketchUp.
            def ribbon(steps,width,angle)
                side=[-Math.sin(angle),Math.cos(angle),0]
                rows=(0..steps).map do |i|
                    t=i.to_f/steps
                    center=yield(t)
                    half=width*(0.025+0.475*Math.sin(Math::PI*t)**0.7)
                    [-1,0,1].map do |s|
                        point([center[0]+side[0]*half*s,center[1]+side[1]*half*s,
                            center[2]+(s.zero? ? half*0.25 : 0)])
                    end
                end
                steps.times do |i|
                    2.times { |j| quad(rows[i][j],rows[i+1][j],rows[i+1][j+1],rows[i][j+1]) }
                end
            end

            def stem_point(start,finish,t,bend)
                3.times.map { |k| start[k]+(finish[k]-start[k])*t+(k==0 ? bend*0.15*Math.sin(t*Math::PI) : 0) }
            end

            # Square tubes are sufficient at this stem size. An orthogonal
            # cross-section also supports nearly horizontal umbel branches.
            def stem(start,finish,radius,steps,bend)
                d=3.times.map { |k| finish[k]-start[k] }
                n=Math.sqrt(d.sum { |v| v*v }); d.map! { |v| v/n }
                side=d[2].abs<0.9 ? [-d[1],d[0],0] : [1,0,-d[0]/d[2]]
                n=Math.sqrt(side.sum { |v| v*v }); side.map! { |v| v/n }
                other=[d[1]*side[2]-d[2]*side[1],d[2]*side[0]-d[0]*side[2],d[0]*side[1]-d[1]*side[0]]
                rows=(0..steps).map do |i|
                    t=i.to_f/steps
                    center=stem_point(start,finish,t,bend)
                    [[-1,-1],[1,-1],[1,1],[-1,1]].map do |a,b|
                        point(3.times.map { |k| center[k]+radius*(1-t*0.35)*(side[k]*a+other[k]*b) })
                    end
                end
                steps.times { |i| 4.times { |j| quad(rows[i][j],rows[i][(j+1)%4],rows[i+1][(j+1)%4],rows[i+1][j]) } }
                quad(*rows.first.reverse); quad(*rows.last)
            end

            # Radial rings model petal centres and lobed flower/seed spires.
            # Rings end at a finite radius and receive nondegenerate quad caps.
            def head(center,radii,rings,sides,phase,lobes)
                rows=(0..rings).map do |i|
                    t=i.to_f/rings
                    z=-1+2*t
                    r=0.10+0.90*Math.sin(Math::PI*t)**0.7
                    r*=1-lobes*(0.5+0.5*Math.cos(t*Math::PI*8))
                    sides.times.map do |j|
                        a=phase+j*Math::PI*2/sides
                        point([center[0]+Math.cos(a)*r*radii[0],center[1]+Math.sin(a)*r*radii[1],center[2]+z*radii[2]])
                    end
                end
                rings.times { |i| sides.times { |j| quad(rows[i][j],rows[i][(j+1)%sides],rows[i+1][(j+1)%sides],rows[i+1][j]) } }
                [rows.first.reverse,rows.last].each do |row|
                    if sides==4
                        quad(*row)
                    else
                        c=point(3.times.map { |k| row.sum { |id| @points[id][k] }/sides })
                        (sides/2).times { |i| quad(row[i*2],row[(i*2+1)%sides],row[(i*2+2)%sides],c) }
                    end
                end
            end

            def flower(center,radius,petals,steps,phase,cup,sides)
                petals.times do |i|
                    a=phase+i*Math::PI*2/petals
                    ribbon(steps,radius*0.65,a) do |t|
                        r=radius*(0.15+0.85*t)
                        [center[0]+Math.cos(a)*r,center[1]+Math.sin(a)*r,
                         center[2]+radius*((0.15+cup*0.35)*t*t-0.12*Math.sin(t*Math::PI))]
                    end
                end
                head(center,[radius*0.24,radius*0.24,radius*0.15],2,sides,phase,0)
            end
        end
    end
end
