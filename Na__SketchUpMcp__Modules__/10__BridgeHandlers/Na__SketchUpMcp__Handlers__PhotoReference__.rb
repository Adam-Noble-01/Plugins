# =============================================================================
# NA SKETCHUP MCP - HANDLERS - PHOTO REFERENCE (image_rectify, image_flatten)
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__PhotoReference__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__PhotoReference
# PURPOSE    : image_rectify: lay a site photo flat on the ground (or on any
#              plane) in the model, rectified by a homography fitted to four or
#              more pairs of photo pixel <-> model point, so Adam and an agent
#              can see where things in the photo sit against the model.
#              image_flatten (1.0.33): flatten part of a photo onto a rectangle
#              of known width on its plane, as a new square-on image mapped
#              plainly onto a face, to draw over like a CAD sheet
# CREATED    : 12-Nov-2026 (1.0.30; image_flatten 1.0.33)
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

# -----------------------------------------------------------------------------
# REGION | image_flatten (1.0.33)
# -----------------------------------------------------------------------------
#
# Adam, 12-Nov-2026, after an agent began scaling a door's photo by eye: "build a
# MCP tool that allows you to flatten out images, so you know the width of the
# window opening so you can draw a rough theoretical rectangle, warp the window to
# suit and create a image mapped to a rectangle to draw over, similar to
# sketchups texture markers".
#
# HOW: the corners (the four texture pins) and any known points fix a homography
# from the rectangle's plane to the photo (Na__PlanGeometry: an unknown height is
# solved from the points, or else estimated from the corners' perspective). The
# photo's pixels are warped through it into a new square-on PNG
# (Na__PlanGeometry__WarpPixels on Sketchup::ImageRep bytes), mapped plainly onto
# a face over the rectangle and its margin. Unlike image_rectify (the photo
# itself, distorted by SketchUp's free pins, for context) the result is a flat
# image a drafting kit reads like a CAD sheet, with its fit reported on the plane.
#
# The image's up is the world-up side of the rectangle's y axis (y itself on a
# level plane); its right is x, or -x where x would mirror the photo; the face's
# front looks back towards the camera.

        NA_FLAT_PREFIX       = 'REF__PhotoPlane__'.freeze
        NA_FLAT_DICTIONARY   = 'Na__SketchUpMcp__PhotoPlane'.freeze
        NA_FLAT_MAX_PIXELS   = 4_000_000
        NA_FLAT_LIMIT_PIXELS = 16_000_000
        NA_FLAT_SUBFOLDER    = File.join('01__ReferenceFiles', '11__Photos__Flattened').freeze
        # What Sketchup::ImageRep#load_file reads. It refuses WebP (SketchUp 2027, 12-Nov-2026).
        NA_FLAT_FORMATS      = %w[.png .jpg .jpeg .bmp .tif .tiff .tga .gif .psd].freeze

        def self.Na__Handlers__PhotoReference__Flatten(params, ctx)
            unit = ctx[:unit]
            path = File.expand_path(Na__Params.Na__Params__String(params, 'path', nil, required: true))
            raise Na__McpError.new('file_error', "No image at #{path}.", 'Give the absolute path of a PNG or JPEG.') unless File.file?(path)
            unless NA_FLAT_FORMATS.include?(File.extname(path).downcase)
                raise Na__McpError.new('invalid_params', "SketchUp cannot read #{File.extname(path)} images.", 'Convert the photo to PNG or JPEG first.')
            end

            rect = na_flat_rectangle(params, unit)
            frame = na_flat_frame(rect)
            corners = na_flat_corners(params)
            points = na_flat_points(params, frame, unit, ctx)
            source = na_flat_load(path)
            sw = source.width
            sh = source.height
            # Pixels come as viewers show the photo; ImageRep loads it unturned (a JPEG's EXIF orientation ignored).
            orientation = na_flat_orientation(path)
            corners = corners.map { |pixel| Na__PlanGeometry.Na__PlanGeometry__UprightToRaw(pixel, orientation, sw, sh) }
            points = points.map { |at, pixel| [at, Na__PlanGeometry.Na__PlanGeometry__UprightToRaw(pixel, orientation, sw, sh)] }
            solved = na_flat_solve(rect, corners, points, sw, sh, ctx)
            height = solved[:height]
            matrix = solved[:fit][:matrix]
            inverse = Na__PlanGeometry.Na__PlanGeometry__Invert3(matrix)
            raise Na__McpError.new('invalid_params', 'The fitted mapping cannot be inverted.', "Check the corners are the rectangle's, in order.") unless inverse

            region, coverage = na_flat_region(params, unit, rect[:width], height, inverse, corners, sw, sh)
            size = na_flat_pixel_size(params, unit, matrix, region, sw, sh)
            dw = [((region[2] - region[0]) / size).ceil, 1].max
            dh = [((region[3] - region[1]) / size).ceil, 1].max
            layout = na_flat_layout(rect, region, dw, dh, matrix)
            bytes_per_pixel = source.bits_per_pixel / 8
            stride = (sw * bytes_per_pixel) + source.row_padding
            bytes = Na__PlanGeometry.Na__PlanGeometry__WarpPixels(source.data, sw, sh, bytes_per_pixel, stride,
                                                                 Na__PlanGeometry.na_mat_mul(matrix, layout[:to_plane]), dw, dh)

            name = na_flat_name(params['name'])
            out = na_flat_output_path(params, ctx[:model], name)
            image = Sketchup::ImageRep.new
            image.set_data(dw, dh, 32, 0, bytes)
            image.save_file(out)
            raise Na__McpError.new('file_error', "SketchUp could not write #{out}.", 'Check the folder can be written to, or give save_path.') unless File.file?(out)

            begin
                placed = na_flat_place(params, ctx, rect, height, frame, layout, out, name, dw, dh)
            rescue StandardError
                File.delete(out) if File.file?(out)
                raise
            end

            known = [[0.0, 0.0], [rect[:width], 0.0], [rect[:width], height], [0.0, height]] + points.map(&:first)
            pixels = corners + points.map(&:last)
            residuals = na_flat_residuals(matrix, inverse, known, pixels, unit)
            check = na_flat_mapping_check(placed[:face], layout, frame, placed[:prepared][:input_to_reported], known, dw, dh)
            worst = residuals.map { |entry| entry['on_plane'] || 0.0 }.max
            if worst > Na__Units.Na__Units__FromInches(Na__Units.Na__Units__ToInches(25.0, 'mm'), unit)
                ctx[:warnings] << "The fit is #{worst} #{unit} out on the plane at its worst pin or point; check those pixels pair up with their positions."
            end
            ctx[:warnings] << "SketchUp's texture mapping is #{check.round(1)} output px off at the pins." if check && check > 1.0
            ctx[:warnings] << "The photo covers #{(coverage * 100).round} % of the flattened area; the rest is transparent." if coverage < 0.9

            na_flat_record(placed[:prepared][:wrapper], path, out, corners, rect, height, solved, layout)
            placed[:prepared][:wrapper].set_attribute(NA_FLAT_DICTIONARY, 'exif_orientation', orientation)
            result = Na__Creation.Na__Creation__Finish(placed[:prepared], params.reject { |key, _value| key == 'path' }.merge('name' => name), ctx, [], kind: 'Photo plane')
            to_unit = ->(inches) { Na__Units.Na__Units__FromInches(inches, unit).round(1) }
            fit = solved[:fit]
            labels = (1..4).map { |index| "corner #{index}" } + (1..points.length).map { |index| "point #{index}" }
            how = { 'given' => 'height given', 'points' => "height solved from #{points.length} point(s)", 'perspective' => 'height estimated from perspective' }[solved[:from]]
            result.merge(
                'summary' => "Flattened #{File.basename(path)} onto a #{to_unit.call(rect[:width])} x #{to_unit.call(height)} #{unit} rectangle " \
                             "(#{how}; fit #{fit[:rms_px].round(2)} px rms, worst #{worst} #{unit} on the plane): " \
                             "#{dw} x #{dh} px at #{to_unit.call(layout[:pixel_size].max)} #{unit} a pixel, as #{name}.",
                'image' => { 'source' => path, 'source_px' => orientation >= 5 ? [sh, sw] : [sw, sh], 'exif_orientation' => orientation,
                             'output' => out, 'output_px' => [dw, dh],
                             'pixel_size' => layout[:pixel_size].map { |value| Na__Units.Na__Units__FromInches(value, unit).round(3) } },
                'rectangle' => { 'width' => to_unit.call(rect[:width]), 'height' => to_unit.call(height), 'height_from' => solved[:from],
                                 'perspective_height' => solved[:guess] && to_unit.call(solved[:guess]),
                                 'perspective_focal_px' => solved[:focal_px] && solved[:focal_px].round,
                                 'corners' => known.first(4).map { |p| Na__Units.Na__Units__PointOut(na_from_plane(frame, p), unit).map { |value| value.round(1) } } },
                'fit' => { 'pairs' => known.length, 'rms_px' => fit[:rms_px].round(2), 'max_px' => fit[:max_px].round(2),
                           'residuals' => labels.each_with_index.map { |label, index| residuals[index].merge('pair' => label) },
                           'mapping_check_px' => check && check.round(2) },
                'coverage' => coverage.round(3),
                'on_plane_only' => 'Only what lies on the rectangle\'s plane is true to scale; anything in front of it or behind it (reveals, cills, ' \
                                   'pipes, a frame set back) is shifted. Read the residuals before trusting it to the millimetre.'
            )
        end

        # The rectangle: origin (world inches), unit x along its width, unit y across
        # it (towards y_axis), normal x * y, width and the height when given.
        def self.na_flat_rectangle(params, unit)
            spec = Na__Params.Na__Params__Hash(params, 'rectangle', nil, required: true)
            origin = Na__Units.Na__Units__Point(spec['origin'], unit, 'rectangle.origin')
            x_axis = Na__Units.Na__Units__Direction(spec['x_axis'], 'rectangle.x_axis')
            y_axis = Na__Units.Na__Units__Direction(spec['y_axis'], 'rectangle.y_axis')
            x = x_axis.normalize
            normal = x * y_axis
            if normal.length < 1.0e-9
                raise Na__McpError.new('invalid_params', 'rectangle.x_axis and rectangle.y_axis are parallel.',
                                       'Give two directions in the plane, e.g. [1, 0, 0] and [0, 0, 1] on a wall along X.')
            end

            normal.normalize!
            y = (normal * x).normalize
            width = Na__Units.Na__Units__PositiveLength(spec['width'], unit, 'rectangle.width')
            height = Na__Params.Na__Params__Has(spec, 'height') ? Na__Units.Na__Units__PositiveLength(spec['height'], unit, 'rectangle.height') : nil
            { origin: origin, x: x, y: y, normal: normal, width: width, height: height }
        end

        def self.na_flat_frame(rect)
            { origin: rect[:origin], x: rect[:x], y: rect[:y], normal: [rect[:normal].x, rect[:normal].y, rect[:normal].z] }
        end

        def self.na_flat_corners(params)
            corners = Na__Params.Na__Params__Array(params, 'corners', nil, required: true, min_items: 4, max_items: 4)
            pixels = corners.each_with_index.map do |pixel, index|
                unless pixel.is_a?(Array) && pixel.length == 2 && pixel.all?(Numeric)
                    raise Na__McpError.new('invalid_params', "corners[#{index}] needs a pixel [u, v] from the photo's top left.", nil)
                end

                pixel.map(&:to_f)
            end
            if Na__PlanGeometry.Na__PlanGeometry__SelfIntersects(pixels)
                raise Na__McpError.new('invalid_params', 'The corners cross over each other.',
                                       'Give them in order round the rectangle: origin, along x_axis, the far corner, along y_axis.')
            end

            pixels
        end

        # Known points: a pixel with at [along x, along y] from the origin corner, or
        # with a world point on the plane. In rectangle inches: [[[s, t], [u, v]], ...].
        def self.na_flat_points(params, frame, unit, ctx)
            off_plane = 0.0
            pairs = Na__Params.Na__Params__Array(params, 'points', [], max_items: 60).each_with_index.map do |point, index|
                unless point.is_a?(Hash) && point['pixel'].is_a?(Array) && point['pixel'].length == 2
                    raise Na__McpError.new('invalid_params', "points[#{index}] needs pixel [u, v] from the photo's top left.", nil)
                end

                at = if point['at'].is_a?(Array) && point['at'].length == 2
                         point['at'].each_with_index.map { |value, axis| Na__Units.Na__Units__ToInches(value, unit, "points[#{index}].at[#{axis}]") }
                     elsif point['world'].is_a?(Array)
                         local = na_to_plane(frame, Na__Units.Na__Units__Point(point['world'], unit, "points[#{index}].world"))
                         off_plane = [off_plane, local[2].abs].max
                         [local[0], local[1]]
                     else
                         raise Na__McpError.new('invalid_params', "points[#{index}] needs at [along x, along y] from the rectangle's origin corner, or world [x, y, z].", nil)
                     end
                [at, point['pixel'].map(&:to_f)]
            end
            if off_plane > Na__Units.Na__Units__ToInches(50.0, 'mm')
                ctx[:warnings] << "Some points lie up to #{Na__Units.Na__Units__FromInches(off_plane, unit).round} #{unit} off the rectangle's plane; " \
                                  'they are used where they fall square onto it.'
            end
            pairs
        end

        def self.na_flat_orientation(path)
            return 1 unless %w[.jpg .jpeg].include?(File.extname(path).downcase)

            Na__PlanGeometry.Na__PlanGeometry__JpegOrientation(File.binread(path, 262_144))
        rescue StandardError
            1
        end

        def self.na_flat_load(path)
            image = Sketchup::ImageRep.new
            image.load_file(path)
            unless image.bits_per_pixel >= 24
                raise Na__McpError.new('invalid_params', "#{File.basename(path)} has #{image.bits_per_pixel} bits a pixel.", 'Use an RGB or RGBA photo (24 or 32 bits a pixel).')
            end

            image
        rescue ArgumentError
            raise Na__McpError.new('file_error', "SketchUp could not read #{path}.", 'Use a PNG or JPEG.')
        end

        # The height and the plane-to-photo fit: as given; else solved from the
        # points; else estimated from the corners' perspective (flagged as rough).
        def self.na_flat_solve(rect, corners, points, sw, sh, ctx)
            width = rect[:width]
            estimate = Na__PlanGeometry.Na__PlanGeometry__RectangleAspect(corners, [sw / 2.0, sh / 2.0])
            guess = estimate && estimate[:aspect] > 1.0e-6 ? width / estimate[:aspect] : nil
            if rect[:height]
                height = rect[:height]
                from = 'given'
                fit = na_flat_fit(width, height, corners, points)
            elsif points.any?
                low = [guess || width, width].min / 10.0
                high = [guess || width, width].max * 10.0
                solved = Na__PlanGeometry.Na__PlanGeometry__SolveRectangleHeight(corners, width, points, low, high)
                raise Na__McpError.new('invalid_params', "The points do not fix the rectangle's height.", 'Spread the points out, or give rectangle.height.') unless solved

                height = solved[:height]
                fit = solved[:fit]
                from = 'points'
                ctx[:warnings] << 'The solved height is at the edge of the search; check the corners and points pair up.' if height < low * 1.05 || height > high / 1.05
            elsif guess
                height = guess
                from = 'perspective'
                fit = na_flat_fit(width, height, corners, [])
                # Kann 64562 (12-Nov-2026): a narrow door near the edge of an ultra-wide phone photo came out 11 % short.
                ctx[:warnings] << "The height is estimated from the photo's perspective alone: rough (11 % out on a door near the edge of an " \
                                  'ultra-wide phone photo), and wrong for a cropped photo. Give rectangle.height, or points at known positions ' \
                                  'inside the rectangle, to fix it.'
            else
                raise Na__McpError.new('invalid_params', "The corners alone cannot fix the rectangle's height.",
                                       'Give rectangle.height, or points at known positions inside the rectangle.')
            end
            raise Na__McpError.new('invalid_params', 'The corners and points do not fix a mapping (three on one line, or repeated).', 'Check the four corners are the rectangle\'s, in order.') unless fit

            { height: height, from: from, fit: fit, guess: guess, focal_px: estimate && estimate[:focal_px] }
        end

        def self.na_flat_fit(width, height, corners, points)
            Na__PlanGeometry.Na__PlanGeometry__FitHomography([[0.0, 0.0], [width, 0.0], [width, height], [0.0, height]] + points.map(&:first),
                                                             corners + points.map(&:last))
        end

        # The plane area to flatten, in rectangle inches [s0, t0, s1, t1]: the
        # rectangle and its margin, cut to the box of what the photo sees (clear of
        # the horizon, as image_rectify keeps it), and the share the photo covers.
        def self.na_flat_region(params, unit, width, height, inverse, corners, sw, sh)
            margin = Na__Params.Na__Params__Has(params, 'margin') ? Na__Units.Na__Units__ToInches(params['margin'], unit, 'margin') : 0.0
            raise Na__McpError.new('invalid_params', 'margin cannot be negative.', nil) if margin.negative?

            weights = corners.map { |pixel| Na__PlanGeometry.Na__PlanGeometry__HomographyW(inverse, pixel) }
            sign = weights.sum.negative? ? -1.0 : 1.0
            floor = weights.map { |weight| weight * sign }.min * NA_HORIZON_KEEP
            image = [[0.0, 0.0], [sw.to_f, 0.0], [sw.to_f, sh.to_f], [0.0, sh.to_f]]
            visible = Na__PlanGeometry.Na__PlanGeometry__ClipHalfPlane(image) { |pixel| (sign * Na__PlanGeometry.Na__PlanGeometry__HomographyW(inverse, pixel)) - floor }
            seen = visible.map { |pixel| Na__PlanGeometry.Na__PlanGeometry__ApplyHomography(inverse, pixel) }.compact
            inside = Na__PlanGeometry.Na__PlanGeometry__ClipRectangle(seen, [-margin, -margin, width + margin, height + margin])
            if inside.length < 3 || Na__PlanGeometry.Na__PlanGeometry__Area(inside).abs < 1.0e-6
                raise Na__McpError.new('invalid_params', 'The photo shows none of the rectangle.', 'Check the corners pair up with the rectangle.')
            end

            xs = inside.map(&:first)
            ys = inside.map(&:last)
            region = [xs.min, ys.min, xs.max, ys.max]
            box = (region[2] - region[0]) * (region[3] - region[1])
            [region, box.positive? ? Na__PlanGeometry.Na__PlanGeometry__Area(inside).abs / box : 0.0]
        end

        # The output's pixel size in inches: pixel_size when given; else the photo's
        # finest detail on the plane (its pixels per inch along x and y at nine
        # points of the region the photo sees), so nothing is lost; capped at max_pixels.
        def self.na_flat_pixel_size(params, unit, matrix, region, sw, sh)
            limit = Na__Params.Na__Params__Integer(params, 'max_pixels', NA_FLAT_MAX_PIXELS, min: 10_000, max: NA_FLAT_LIMIT_PIXELS)
            rw = region[2] - region[0]
            rh = region[3] - region[1]
            if Na__Params.Na__Params__Has(params, 'pixel_size')
                size = Na__Units.Na__Units__PositiveLength(params['pixel_size'], unit, 'pixel_size')
                count = (rw / size).ceil * (rh / size).ceil
                if count > limit
                    raise Na__McpError.new('invalid_params', "pixel_size makes #{count} pixels, over max_pixels (#{limit}).",
                                           'Use a bigger pixel_size or a smaller margin, or raise max_pixels.')
                end

                return size
            end

            step = [rw, rh].max * 1.0e-4
            finest = 0.0
            [region[0], (region[0] + region[2]) / 2.0, region[2]].product([region[1], (region[1] + region[3]) / 2.0, region[3]]).each do |s, t|
                p = Na__PlanGeometry.Na__PlanGeometry__ApplyHomography(matrix, [s, t])
                ps = Na__PlanGeometry.Na__PlanGeometry__ApplyHomography(matrix, [s + step, t])
                pt = Na__PlanGeometry.Na__PlanGeometry__ApplyHomography(matrix, [s, t + step])
                next unless p && ps && pt
                next if p[0].negative? || p[1].negative? || p[0] > sw || p[1] > sh

                finest = [finest, Na__PlanGeometry.na_dist(p, ps) / step, Na__PlanGeometry.na_dist(p, pt) / step].max
            end
            size = finest > 1.0e-9 ? 1.0 / finest : [rw, rh].max / 1000.0
            [size, Math.sqrt(rw * rh / limit)].max
        end

        # How the output's pixels sit on the plane. to_plane maps an output position
        # (pixels from its top left) to rectangle inches; front is the face's front.
        def self.na_flat_layout(rect, region, dw, dh, matrix)
            up = rect[:y].z < -1.0e-6 ? -1.0 : 1.0
            sx = (region[2] - region[0]) / dw
            sy = (region[3] - region[1]) / dh
            build = lambda do |right|
                [[right * sx, 0.0, right.positive? ? region[0] : region[2]],
                 [0.0, -up * sy, up.positive? ? region[3] : region[1]],
                 [0.0, 0.0, 1.0]]
            end
            right = 1.0
            to_plane = build.call(right)
            if na_flat_mirrored?(Na__PlanGeometry.na_mat_mul(matrix, to_plane), dw, dh)
                right = -1.0
                to_plane = build.call(right)
            end
            normal = rect[:normal]
            { to_plane: to_plane, pixel_size: [sx, sy], front: [normal.x * right * up, normal.y * right * up, normal.z * right * up] }
        end

        # True when going from the output to the photo turns the picture over.
        def self.na_flat_mirrored?(warp, dw, dh)
            middle = [dw / 2.0, dh / 2.0]
            p = Na__PlanGeometry.Na__PlanGeometry__ApplyHomography(warp, middle)
            px = Na__PlanGeometry.Na__PlanGeometry__ApplyHomography(warp, [middle[0] + 1.0, middle[1]])
            py = Na__PlanGeometry.Na__PlanGeometry__ApplyHomography(warp, [middle[0], middle[1] + 1.0])
            return false unless p && px && py

            Na__PlanGeometry.na_cross(Na__PlanGeometry.na_sub(px, p), Na__PlanGeometry.na_sub(py, p)).negative?
        end

        # The group: one face over the region carrying the flattened image (front and
        # back, pinned at its corners, edges hidden), and the rectangle's outline in a
        # group of its own so it never splits the face.
        def self.na_flat_place(params, ctx, rect, height, frame, layout, out, name, dw, dh)
            model = ctx[:model]
            material = model.materials.add(name)
            material.texture = out
            raise Na__McpError.new('file_error', "SketchUp could not load #{out} as a texture.", nil) unless material.texture

            material.alpha = Na__Params.Na__Params__Number(params, 'opacity', 0.75, min: 0.05, max: 1.0)
            prepared = Na__Creation.Na__Creation__Prepare(params.reject { |key, _value| key == 'path' }.merge('wrap_in' => 'group', 'parent_id' => params.fetch('parent_id', 0)), ctx, 'group')
            to_reported = prepared[:input_to_reported]
            on_plane = ->(i, j) { to_reported * na_from_plane(frame, Na__PlanGeometry.Na__PlanGeometry__ApplyHomography(layout[:to_plane], [i, j])) }
            face = prepared[:entities].add_face([on_plane.call(0, dh), on_plane.call(dw, dh), on_plane.call(dw, 0), on_plane.call(0, 0)])
            raise Na__McpError.new('operation_failed', 'SketchUp made no face for the photo.', nil) unless face

            Na__Creation.Na__Creation__OrientFace(face, Na__Creation.Na__Creation__Direction(layout[:front], prepared, 'normal', normal: true))
            pins = [[0, 0, 0.0, 1.0], [dw, 0, 1.0, 1.0], [dw, dh, 1.0, 0.0], [0, dh, 0.0, 0.0]].flat_map do |i, j, u, v|
                [on_plane.call(i, j), Geom::Point3d.new(u, v, 0.0)]
            end
            face.material = material
            face.position_material(material, pins, true)
            face.back_material = material
            face.position_material(material, pins, false)
            face.edges.each { |edge| edge.hidden = true }
            if Na__Params.Na__Params__Boolean(params, 'outline', true)
                na_flat_outline(prepared, frame, rect[:width], height, ctx, params)
            end
            { prepared: prepared, face: face }
        end

        def self.na_flat_outline(prepared, frame, width, height, ctx, params)
            outline = prepared[:entities].add_group
            Na__Coordinates.Na__Coordinates__PinGroupToIdentity(outline)
            corners = [[0.0, 0.0], [width, 0.0], [width, height], [0.0, height]].map { |p| prepared[:input_to_reported] * na_from_plane(frame, p) }
            edges = outline.entities.add_edges(corners + [corners.first])
            if params['edge_material']
                material = Na__EntityResolver.Na__EntityResolver__ResolveMaterial(ctx[:model], params['edge_material'], ctx[:warnings])
                edges.each { |edge| edge.material = material }
            end
            size = [width, height].map { |value| Na__Units.Na__Units__FromInches(value, ctx[:unit]).round }
            outline.name = "Rectangle__#{size[0]}x#{size[1]}"
            outline
        end

        # Each pin and point: the fit's error in photo pixels and, carried back onto
        # the plane, in the call's units.
        def self.na_flat_residuals(matrix, inverse, known, pixels, unit)
            known.each_with_index.map do |p, index|
                q = Na__PlanGeometry.Na__PlanGeometry__ApplyHomography(matrix, p)
                back = Na__PlanGeometry.Na__PlanGeometry__ApplyHomography(inverse, pixels[index])
                { 'px' => q ? Na__PlanGeometry.na_dist(q, pixels[index]).round(2) : nil,
                  'on_plane' => back ? Na__Units.Na__Units__FromInches(Na__PlanGeometry.na_dist(back, p), unit).round(1) : nil }
            end
        end

        # Largest gap, in output pixels, between SketchUp's mapping and the layout
        # at the pins and points that lie on the face. nil when none do.
        def self.na_flat_mapping_check(face, layout, frame, to_reported, known, dw, dh)
            helper = face.get_UVHelper(true, false)
            back = Na__PlanGeometry.Na__PlanGeometry__Invert3(layout[:to_plane])
            on_face = [Sketchup::Face::PointInside, Sketchup::Face::PointOnEdge, Sketchup::Face::PointOnVertex]
            errors = known.filter_map do |p|
                point = to_reported * na_from_plane(frame, p)
                next unless on_face.include?(face.classify_point(point))

                uvq = helper.get_front_UVQ(point)
                next if uvq.z.abs < 1.0e-12

                pixel = Na__PlanGeometry.Na__PlanGeometry__ApplyHomography(back, p)
                Math.hypot(((uvq.x / uvq.z) - (pixel[0] / dw)) * dw, ((uvq.y / uvq.z) - (1.0 - (pixel[1] / dh))) * dh)
            end
            errors.max
        rescue StandardError
            nil
        end

        # What made this plane, kept on it for Adam and later agents (lengths in mm).
        def self.na_flat_record(wrapper, path, out, corners, rect, height, solved, layout)
            mm = ->(inches) { Na__Units.Na__Units__FromInches(inches, 'mm').round(2) }
            {
                'source' => path, 'output' => out, 'corners_raw_px' => corners.flatten,
                'origin_mm' => [rect[:origin].x, rect[:origin].y, rect[:origin].z].map { |value| mm.call(value) },
                'x_axis' => [rect[:x].x, rect[:x].y, rect[:x].z], 'y_axis' => [rect[:y].x, rect[:y].y, rect[:y].z],
                'width_mm' => mm.call(rect[:width]), 'height_mm' => mm.call(height), 'height_from' => solved[:from],
                'rms_px' => solved[:fit][:rms_px].round(3), 'pixel_size_mm' => layout[:pixel_size].map { |value| mm.call(value) },
                'created' => Time.now.strftime('%d-%b-%Y %H:%M')
            }.each { |key, value| wrapper.set_attribute(NA_FLAT_DICTIONARY, key, value) }
        end

        def self.na_flat_name(name)
            text = name.to_s.strip
            text = 'Photo' if text.empty?
            text.start_with?('REF__') ? text : "#{NA_FLAT_PREFIX}#{text}"
        end

        # Where the flattened PNG goes, never over a file: save_path; else the job
        # folder's 01__ReferenceFiles/11__Photos__Flattened (the first NNNNN__ folder
        # above the saved model, where Adam files a job's reference images); else
        # this plugin's PhotoPlanes folder. Named <name>__<dd-Mon-yyyy>.png.
        def self.na_flat_output_path(params, model, name)
            if Na__Params.Na__Params__Has(params, 'save_path')
                out = File.expand_path(Na__Params.Na__Params__String(params, 'save_path', nil, required: true))
                raise Na__McpError.new('invalid_params', 'save_path must end in .png.', nil) unless File.extname(out).casecmp('.png').zero?
                raise Na__McpError.new('invalid_params', "#{out} exists; a flattened photo is never written over.", 'Give another save_path, or leave it out for a dated name.') if File.exist?(out)

                Na__PathResolver.Na__PathResolver__EnsureDirectory(File.dirname(out))
                return out
            end

            job = na_flat_job_folder(model)
            folder = job ? File.join(job, NA_FLAT_SUBFOLDER) : File.join(Na__PathResolver.Na__PathResolver__UserConfigDirectory, 'PhotoPlanes')
            Na__PathResolver.Na__PathResolver__EnsureDirectory(folder)
            stem = "#{name.delete_prefix(NA_FLAT_PREFIX).gsub(/[^A-Za-z0-9_-]+/, '_')[0, 60]}__#{Time.now.strftime('%d-%b-%Y')}"
            out = File.join(folder, "#{stem}.png")
            count = 2
            while File.exist?(out)
                out = File.join(folder, format('%<stem>s__%<count>02d.png', stem: stem, count: count))
                count += 1
            end
            out
        end

        def self.na_flat_job_folder(model)
            path = model.path.to_s.tr('\\', '/')
            return nil if path.empty?

            folder = File.dirname(path)
            10.times do
                return folder if File.basename(folder).match?(/\A\d{5}__/)

                parent = File.dirname(folder)
                return nil if parent == folder

                folder = parent
            end
            nil
        end

# endregion -------------------------------------------------------------------

    end # module Na__Handlers__PhotoReference
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
