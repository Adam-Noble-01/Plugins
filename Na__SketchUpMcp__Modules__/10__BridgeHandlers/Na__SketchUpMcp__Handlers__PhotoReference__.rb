# =============================================================================
# NA SKETCHUP MCP - HANDLERS - PHOTO REFERENCE (image_rectify)
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__PhotoReference__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__PhotoReference
# PURPOSE    : Lay a site photo flat on the ground (or on any plane) in the
#              model, rectified by a homography fitted to four or more pairs of
#              photo pixel <-> model point, so Adam and an agent can see where
#              things in the photo sit against the model
# CREATED    : 12-Nov-2026 (1.0.30)
#
# A SITE PHOTO IS A REFERENCE, NEVER A SPEC (Adam, 12-Nov-2026):
# "if I give a site photo its just a reference and the agent must ask for more
# early on rather than trying to be too surgical on a site photograph". This
# tool places the photo for context and reports how well it fits; it measures
# nothing for the agent to copy. Everything off the plane (walls, plants,
# people) is smeared by the rectification. Precise inputs are CAD, elevation
# drawings, orthophotos, point clouds and the model's own geometry.
#
# HOW:
# Na__PlanGeometry fits H (plane x, y -> pixel u, v). The photo becomes a
# material; a face covers the part of the plane the photo sees (the image
# rectangle mapped back through H, kept clear of the horizon, cut to region);
# Face#position_material pins four of its corners to their pixels, which gives
# SketchUp's projective (free-pin) mapping. The mapping is then read back
# through a UVHelper at the control points and reported as mapping_check_px.
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Handlers__PhotoReference

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_PREFIX      = 'REF__SitePhoto__'.freeze
        NA_MAX_PAIRS   = 64
        NA_HORIZON_KEEP = 0.15

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | image_rectify
# -----------------------------------------------------------------------------

        def self.Na__Handlers__PhotoReference__Rectify(params, ctx)
            model = ctx[:model]
            unit = ctx[:unit]
            path = File.expand_path(Na__Params.Na__Params__String(params, 'path', nil, required: true))
            raise Na__McpError.new('file_error', "No image at #{path}.", 'Give the absolute path of a PNG or JPEG.') unless File.file?(path)

            frame = na_plane(params, unit)
            pairs = Na__Params.Na__Params__Array(params, 'pairs', nil, required: true, min_items: 4, max_items: NA_MAX_PAIRS)
            plane_points = []
            pixels = []
            off_plane = []
            pairs.each_with_index do |pair, index|
                unless pair.is_a?(Hash) && pair['pixel'].is_a?(Array) && pair['pixel'].length == 2 && pair['world'].is_a?(Array)
                    raise Na__McpError.new('invalid_params', "pairs[#{index}] needs pixel [u, v] (from the photo's top left) and world [x, y, z].", nil)
                end

                world = Na__Units.Na__Units__Point(pair['world'], unit, "pairs[#{index}].world")
                local = na_to_plane(frame, world)
                off_plane << local[2].abs
                plane_points << [local[0], local[1]]
                pixels << pair['pixel'].map(&:to_f)
            end
            if off_plane.max > Na__Units.Na__Units__ToInches(50.0, 'mm')
                ctx[:warnings] << "Some world points lie up to #{Na__Units.Na__Units__FromInches(off_plane.max, unit).round} #{unit} off the plane; " \
                                  'only points ON the plane rectify correctly (ground points for a ground photo).'
            end

            fit = Na__PlanGeometry.Na__PlanGeometry__FitHomography(plane_points, pixels)
            raise Na__McpError.new('invalid_params', 'The pairs do not fix a mapping (three or more on one line, or repeated).', 'Spread four or more points over the plane.') unless fit

            inverse = Na__PlanGeometry.Na__PlanGeometry__Invert3(fit[:matrix])
            raise Na__McpError.new('invalid_params', 'The fitted mapping cannot be inverted.', 'Check the pairs.') unless inverse

            material = na_material(model, params, path)
            width = material.texture.image_width.to_f
            height = material.texture.image_height.to_f
            polygon, kept = na_footprint(inverse, pixels, width, height, plane_points, params, frame, unit)
            if polygon.length < 3 || Na__PlanGeometry.Na__PlanGeometry__Area(polygon).abs < 1.0
                raise Na__McpError.new('invalid_params', 'The photo covers none of the requested region of the plane.', 'Widen region, or check pixel and world points pair up.')
            end

            # 'path' is the image here, not an instance path: keep it away from Prepare.
            prepared = Na__Creation.Na__Creation__Prepare(params.reject { |key, _value| key == 'path' }.merge('wrap_in' => 'group', 'parent_id' => params.fetch('parent_id', 0)), ctx, 'group')
            to_reported = prepared[:input_to_reported]
            corners = polygon.map { |p| to_reported * na_from_plane(frame, p) }
            face = prepared[:entities].add_face(corners)
            raise Na__McpError.new('operation_failed', 'SketchUp made no face for the photo.', nil) unless face

            Na__Creation.Na__Creation__OrientFace(face, Na__Creation.Na__Creation__Direction(frame[:normal], prepared, 'normal', normal: true))
            pins = na_pins(polygon).flat_map do |p|
                pixel = Na__PlanGeometry.Na__PlanGeometry__ApplyHomography(fit[:matrix], p)
                [to_reported * na_from_plane(frame, p), Geom::Point3d.new(pixel[0] / width, 1.0 - (pixel[1] / height), 0.0)]
            end
            face.material = material
            face.position_material(material, pins, true)
            face.back_material = material
            face.position_material(material, pins, false)
            if params['edge_material']
                edge_material = Na__EntityResolver.Na__EntityResolver__ResolveMaterial(model, params['edge_material'], ctx[:warnings])
                face.edges.each { |edge| edge.material = edge_material }
            end

            check = na_mapping_check(face, fit[:matrix], plane_points, frame, to_reported, width, height)
            if check && check > 3.0
                ctx[:warnings] << "SketchUp's texture mapping is #{check.round(1)} px off the fitted one at the control points; the photo may look slightly shifted."
            end

            params = params.merge('name' => na_name(params['name']))
            result = Na__Creation.Na__Creation__Finish(prepared, params.reject { |key, _value| key == 'path' }, ctx, [], kind: 'Site photo')
            ground = plane_points.each_with_index.map do |p, index|
                back = Na__PlanGeometry.Na__PlanGeometry__ApplyHomography(inverse, pixels[index])
                back ? Na__PlanGeometry.na_dist(back, p) : Float::INFINITY
            end
            result.merge(
                'image' => { 'path' => path, 'width_px' => width.to_i, 'height_px' => height.to_i },
                'fit' => { 'pairs' => pairs.length, 'rms_px' => fit[:rms_px].round(2), 'max_px' => fit[:max_px].round(2),
                           'residuals_px' => fit[:residuals_px].map { |value| value.round(2) },
                           'ground_error' => ground.map { |value| Na__Units.Na__Units__FromInches(value, unit).round(1) },
                           'mapping_check_px' => check && check.round(2) },
                'covered_area' => Na__Units.Na__Units__AreaFromSquareInches(Na__PlanGeometry.Na__PlanGeometry__Area(polygon).abs, unit).round(3),
                'horizon_clipped' => kept,
                'reference_only' => 'A site photo is context, not a spec: anything off the plane is smeared, and nothing here is measured for building. ' \
                                    'Ask Adam for the numbers (or CAD, an orthophoto or a scan) before modelling from it.'
            )
        end

        # The plane: origin, unit x and y in it, and its normal (world inches).
        def self.na_plane(params, unit)
            spec = params['plane'].is_a?(Hash) ? params['plane'] : {}
            z = Na__Units.Na__Units__ToInches(params.fetch('z', 0), unit, 'z')
            origin = spec['origin'] ? Na__Units.Na__Units__Point(spec['origin'], unit, 'plane.origin') : Geom::Point3d.new(0, 0, z)
            x_axis = spec['x_axis'] ? Na__Units.Na__Units__Direction(spec['x_axis'], 'plane.x_axis') : Geom::Vector3d.new(1, 0, 0)
            y_axis = spec['y_axis'] ? Na__Units.Na__Units__Direction(spec['y_axis'], 'plane.y_axis') : Geom::Vector3d.new(0, 1, 0)
            x = x_axis.normalize
            normal = x * y_axis
            raise Na__McpError.new('invalid_params', 'plane.x_axis and plane.y_axis are parallel.', nil) if normal.length < 1.0e-9

            normal.normalize!
            y = (normal * x).normalize
            { origin: origin, x: x, y: y, normal: [normal.x, normal.y, normal.z] }
        end

        def self.na_to_plane(frame, point)
            v = point - frame[:origin]
            n = Geom::Vector3d.new(*frame[:normal])
            [v.dot(frame[:x]), v.dot(frame[:y]), v.dot(n)]
        end

        def self.na_from_plane(frame, p)
            frame[:origin].offset(frame[:x], p[0]).offset(frame[:y], p[1])
        end

        def self.na_name(name)
            text = name.to_s.strip
            text = 'Photo' if text.empty?
            text.start_with?('REF__') ? text : "#{NA_PREFIX}#{text}"
        end

        def self.na_material(model, params, path)
            material = model.materials.add(na_name(params['name']))
            material.texture = path
            raise Na__McpError.new('file_error', "SketchUp could not load #{path} as a texture.", 'Use a PNG or JPEG.') unless material.texture

            material.alpha = Na__Params.Na__Params__Number(params, 'opacity', 0.75, min: 0.05, max: 1.0)
            material
        end

        # The part of the plane the photo sees: the image rectangle, kept clear of the
        # horizon (the side of the control points, and not nearer the horizon than a
        # fraction of their own distance), mapped to the plane and cut to the region.
        def self.na_footprint(inverse, pixels, width, height, plane_points, params, frame, unit)
            weights = pixels.map { |pixel| Na__PlanGeometry.Na__PlanGeometry__HomographyW(inverse, pixel) }
            sign = weights.sum.negative? ? -1.0 : 1.0
            floor = weights.map { |weight| (weight * sign) }.min * NA_HORIZON_KEEP
            image = [[0.0, 0.0], [width, 0.0], [width, height], [0.0, height]]
            visible = Na__PlanGeometry.Na__PlanGeometry__ClipHalfPlane(image) { |pixel| (sign * Na__PlanGeometry.Na__PlanGeometry__HomographyW(inverse, pixel)) - floor }
            kept = visible.length != 4 || visible.zip(image).any? { |a, b| Na__PlanGeometry.na_dist(a, b) > 1.0e-6 }
            mapped = visible.map { |pixel| Na__PlanGeometry.Na__PlanGeometry__ApplyHomography(inverse, pixel) }.compact
            rect = na_region(params, plane_points, frame, unit)
            [Na__PlanGeometry.Na__PlanGeometry__ClipRectangle(mapped, rect), kept]
        end

        # The region to cover, in plane coordinates: two opposite corners given, else the
        # control points' box grown by margin (default 25 % of its larger side).
        def self.na_region(params, plane_points, frame, unit)
            if params['region'].is_a?(Array) && params['region'].length == 2
                a = na_to_plane(frame, Na__Units.Na__Units__Point(params['region'][0], unit, 'region[0]'))
                b = na_to_plane(frame, Na__Units.Na__Units__Point(params['region'][1], unit, 'region[1]'))
                return [[a[0], b[0]].min, [a[1], b[1]].min, [a[0], b[0]].max, [a[1], b[1]].max]
            end

            xs = plane_points.map(&:first)
            ys = plane_points.map(&:last)
            side = [xs.max - xs.min, ys.max - ys.min].max
            margin = Na__Params.Na__Params__Has(params, 'margin') ? Na__Units.Na__Units__ToInches(params['margin'], unit, 'margin') : side * 0.25
            [xs.min - margin, ys.min - margin, xs.max + margin, ys.max + margin]
        end

        # Four well-spread corners of the polygon for the texture pins.
        def self.na_pins(polygon)
            return polygon.first(4) if polygon.length <= 4

            best = nil
            candidates = polygon.length <= 14 ? (0...polygon.length).to_a : (0...14).map { |k| (k * polygon.length / 14.0).floor }
            candidates.combination(4).each do |combo|
                quad = combo.map { |index| polygon[index] }
                area = Na__PlanGeometry.Na__PlanGeometry__Area(quad).abs
                best = [area, quad] if best.nil? || area > best[0]
            end
            best[1]
        end

        # Largest pixel error between SketchUp's mapping and the fit, at the control
        # points that lie on the face. nil when none do or the API cannot say.
        def self.na_mapping_check(face, matrix, plane_points, frame, to_reported, width, height)
            helper = face.get_UVHelper(true, false)
            errors = plane_points.filter_map do |p|
                point = to_reported * na_from_plane(frame, p)
                next unless face.classify_point(point) == Sketchup::Face::PointInside

                uvq = helper.get_front_UVQ(point)
                next if uvq.z.abs < 1.0e-12

                expected = Na__PlanGeometry.Na__PlanGeometry__ApplyHomography(matrix, p)
                got = [(uvq.x / uvq.z) * width, (1.0 - (uvq.y / uvq.z)) * height]
                Na__PlanGeometry.na_dist(expected, got)
            end
            errors.max
        rescue StandardError
            nil
        end

# endregion -------------------------------------------------------------------

    end # module Na__Handlers__PhotoReference
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
