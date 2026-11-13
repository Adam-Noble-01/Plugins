# =============================================================================
# NA NOBLE3D MODELLING TOOLS - TO SCALE ORTHO TEXTURE MAKER - POINT CLOUD ORTHO PLANE
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__ToScaleOrthoTextureMaker__PointCloudOrtho__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__ToScaleOrthoTextureMaker__PointCloudOrtho
# PURPOSE    : Point Cloud Ortho Plane (13-Nov-2026): a scaled, square-on picture
#              of the point cloud, placed in the model as a textured drawing plane
#              (REF__DrawingPlane__<View>__PointCloudOrtho__<Name>) to draw over.
#              ONE build path with two front doors: the Ortho tab's button and
#              the Na SketchUp MCP tool point_cloud_ortho_plane (a thin seam).
# CREATED    : 13-Nov-2026
#
# WHY (Adam, Kann 64562, 13-Nov-2026):
#   "Pointcloud -> Scaled 2D Image -> 2D Linework -> (Eventually 3D)" for low
#   quality clouds; "inserting the image plane worked EXCELLENTLY for me to in
#   model reference and check your workings"; "ALWAYS use a parallel projection".
#   Spec: Na__SketchUpMcp__Modules__/85__Docs__AgentReference/Specs/
#   Na__SketchUpMcp__Spec__PointCloudOrthoPlane__.md (agreed 13-Nov-2026).
#
# HOW:
# 1. A frame: origin, x (picture right), y (picture up), z = x cross y (toward
#    the camera). u, v and depth are lengths along x, y and z from the origin.
# 2. The dot size: from the points' spacing in the slab (the viewer's spacing
#    read), so the dots just meet at this resolution.
# 3. The capture, with ZERO TRACE: inside an operation that is always aborted,
#    the model is hidden, the parallel camera set, the view written on white
#    (ProjectionEngine), then the viewer's composite draws the clouds over it
#    with a TURNED clip box (the slab) for this capture only, and two cross
#    marks prove the pixel map. The camera is put back after.
# 4. The PNG is saved in the job folder (01__ReferenceFiles/12__PointCloud__Orthos).
# 5. The plane: a textured face (MaterialUvBuilder) in front of the model's
#    geometry along the view (raytests over the picture), named and tagged,
#    stamped with PlaneBuilder's Na__Ortho__Capture dictionary so the Export
#    button works on it. ONE undo step, "Point Cloud Ortho Plane".
#
# Every length inside is in model INCHES.
#
# =============================================================================

require 'json'
require 'fileutils'
require 'tmpdir'

module Na__Noble3dModellingTools

# -----------------------------------------------------------------------------
# REGION | Refusal
# -----------------------------------------------------------------------------

    # A refusal with a code and a hint naming the fix (the MCP seam turns it into
    # its own error; the dialog shows message and hint).
    class Na__PointCloudOrthoError < StandardError
        attr_reader :na_code, :na_hint, :na_details

        def initialize(code, message, hint = nil, details = nil)
            super(message)
            @na_code = code
            @na_hint = hint
            @na_details = details
        end
    end

# endregion -------------------------------------------------------------------

    module Na__ToScaleOrthoTextureMaker__PointCloudOrtho

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_VERSION = '1.0.0'.freeze unless const_defined?(:NA_VERSION)
        NA_MM = 25.4 unless const_defined?(:NA_MM)
        NA_OPERATION_NAME = 'Point Cloud Ortho Plane'.freeze unless const_defined?(:NA_OPERATION_NAME)
        NA_CAPTURE_OPERATION = 'Point Cloud Ortho Plane (capture, undone)'.freeze unless const_defined?(:NA_CAPTURE_OPERATION)
        NA_PLANE_PREFIX = 'REF__DrawingPlane__'.freeze unless const_defined?(:NA_PLANE_PREFIX)
        NA_DEFAULT_TAG = '06__Drawings'.freeze unless const_defined?(:NA_DEFAULT_TAG)
        NA_DEFAULT_NAME = 'Cloud'.freeze unless const_defined?(:NA_DEFAULT_NAME)
        NA_MIN_RES_MM = 0.5 unless const_defined?(:NA_MIN_RES_MM)
        NA_MAX_RES_MM = 1000.0 unless const_defined?(:NA_MAX_RES_MM)
        NA_MAX_PIXELS = 12_000_000 unless const_defined?(:NA_MAX_PIXELS)
        NA_MAX_SIDE = 16_000 unless const_defined?(:NA_MAX_SIDE)
        NA_FILL_FACTOR = 1.3 unless const_defined?(:NA_FILL_FACTOR)
        NA_MAX_DOT_PX = 64.0 unless const_defined?(:NA_MAX_DOT_PX)
        NA_SPACING_CELL_MM = 250.0 unless const_defined?(:NA_SPACING_CELL_MM)
        NA_FRONT_GAP_MM = 100.0 unless const_defined?(:NA_FRONT_GAP_MM)
        NA_GRID_MM = 5.0 unless const_defined?(:NA_GRID_MM)
        NA_RAY_SAMPLES = 24 unless const_defined?(:NA_RAY_SAMPLES)
        NA_RAY_SKIPS = 6 unless const_defined?(:NA_RAY_SKIPS)
        NA_EYE_GAP_MM = 5000.0 unless const_defined?(:NA_EYE_GAP_MM)
        NA_CALIBRATION_LIMIT_PX = 1.0 unless const_defined?(:NA_CALIBRATION_LIMIT_PX)
        NA_AUTO_V_RANGE_MM = [-30_000.0, 60_000.0].freeze unless const_defined?(:NA_AUTO_V_RANGE_MM)
        NA_AUTO_V_PAD_MM = 500.0 unless const_defined?(:NA_AUTO_V_PAD_MM)
        NA_FOLDER_PARTS = %w[01__ReferenceFiles 12__PointCloud__Orthos].freeze unless const_defined?(:NA_FOLDER_PARTS)
        NA_MONTHS = %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec].freeze unless const_defined?(:NA_MONTHS)
        NA_BACKGROUNDS = %w[white transparent].freeze unless const_defined?(:NA_BACKGROUNDS)
        NA_PLACEMENTS = %w[front frame].freeze unless const_defined?(:NA_PLACEMENTS)
        NA_STANDARD_VIEWS = {
            # name => [x (picture right), y (picture up)]; z = x cross y points to the camera
            'top'    => [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0]],
            'bottom' => [[-1.0, 0.0, 0.0], [0.0, 1.0, 0.0]],
            'front'  => [[1.0, 0.0, 0.0], [0.0, 0.0, 1.0]],
            'back'   => [[-1.0, 0.0, 0.0], [0.0, 0.0, 1.0]],
            'left'   => [[0.0, -1.0, 0.0], [0.0, 0.0, 1.0]],
            'right'  => [[0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]
        }.freeze unless const_defined?(:NA_STANDARD_VIEWS)

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Make One Point Cloud Ortho Plane
        # ------------------------------------------------------------
        # spec (lengths in model INCHES, string keys):
        #   'frame'        => { 'origin', 'x_axis', 'y_axis' } (Na__..._Frame* make it)
        #   'u', 'v'       => [min, max] along x and y from the origin
        #   'depth'        => [behind, front] along z (the slab kept)
        #   'resolution'   => model length per pixel
        # optional: 'fill' (true), 'dot_px', 'look' {point_size_px, opacity_percent,
        #   colour_mode}, 'background' ('white'), 'placement' ('front'), 'offset' (0),
        #   'name', 'view_word', 'tag' ('06__Drawings'), 'save_path', 'clouds',
        #   'place' (true), 'hide' ('model' or 'none'), 'calibrate' (true).
        # Returns a Hash (string keys, inches); raises Na__PointCloudOrthoError.
        def self.Na__ToScaleOrthoTextureMaker__PointCloudOrtho__Make(spec)
            spec = {} unless spec.is_a?(Hash)
            model = Sketchup.active_model
            na_refuse('unsupported', 'No SketchUp model is open.') unless model
            operations = self.Na__ToScaleOrthoTextureMaker__PointCloudOrtho__Viewer
            warnings = []

            frame = na_frame_in(spec['frame'])
            resolution = na_length(spec['resolution'], 'resolution')
            unless resolution * NA_MM >= NA_MIN_RES_MM && resolution * NA_MM <= NA_MAX_RES_MM
                na_refuse('invalid_params', "resolution must be from #{NA_MIN_RES_MM} to #{NA_MAX_RES_MM} mm a pixel.", 'Use e.g. 10 mm a pixel for a garden, 5 for a wall.')
            end
            u0, u1 = na_range(spec['u'], 'u')
            v0, v1 = na_range(spec['v'], 'v')
            behind, front = na_depth(spec['depth'])
            width = ((u1 - u0) / resolution).round
            height = ((v1 - v0) / resolution).round
            na_refuse('invalid_params', 'The picture would be less than a pixel across.', 'Make the extent bigger or the resolution finer.') if width < 1 || height < 1
            if width > NA_MAX_SIDE || height > NA_MAX_SIDE || width * height > NA_MAX_PIXELS
                coarser = (Math.sqrt((u1 - u0) * (v1 - v0) / NA_MAX_PIXELS) * NA_MM).ceil
                na_refuse('invalid_params', "The picture would be #{width} x #{height} px; at most #{NA_MAX_SIDE} a side and #{NA_MAX_PIXELS / 1_000_000} MP.",
                          "Use a resolution of #{[coarser, (NA_MAX_RES_MM).to_i].min} mm a pixel or more, or a smaller extent.")
            end
            u1 = u0 + width * resolution
            v1 = v0 + height * resolution

            background = na_choice(spec['background'] || 'white', NA_BACKGROUNDS, 'background')
            placement = na_choice(spec['placement'] || 'front', NA_PLACEMENTS, 'placement')
            offset = spec.key?('offset') && !spec['offset'].nil? ? na_number(spec['offset'], 'offset') : 0.0
            view_word = spec['view_word'] ? na_word(spec['view_word']) : self.Na__ToScaleOrthoTextureMaker__PointCloudOrtho__ViewWord(frame)
            name = na_word(spec['name'].to_s.strip.empty? ? NA_DEFAULT_NAME : spec['name'])
            clouds = na_clouds(operations, spec['clouds'])

            dot_px, spacing = if spec.key?('dot_px') && !spec['dot_px'].nil?
                                  [na_number(spec['dot_px'], 'dot_px'), nil]
                              elsif spec['fill'] != false
                                  na_fill_dot(operations, frame, clouds, [u0, v0, -behind], [u1, v1, front], resolution, warnings)
                              else
                                  [nil, nil]
                              end
            if dot_px && (dot_px < 1.0 || dot_px > NA_MAX_DOT_PX)
                na_refuse('invalid_params', "dot_px must be from 1 to #{NA_MAX_DOT_PX.to_i}.", 'Leave it out to size the dots from the points\' spacing.')
            end

            capture = na_capture(model, operations, frame, [u0, u1, v0, v1], [behind, front], width, height, background,
                                 spec, clouds, dot_px, warnings)
            png_path = na_save_png(model, spec['save_path'], capture[:png], view_word, name, resolution, warnings)
            File.delete(capture[:png]) if File.exist?(capture[:png]) && capture[:png] != png_path

            result = {
                'png'              => png_path,
                'pixels'           => [width, height],
                'resolution'       => resolution,
                'frame'            => na_frame_out(frame),
                'u'                => [u0, u1],
                'v'                => [v0, v1],
                'depth'            => [behind, front],
                'map'              => { 'u0' => u0, 'v1' => v1, 'rule' => 'u = u0 + (col + 0.5) * resolution; v = v1 - (row + 0.5) * resolution; ' \
                                                                        'model point = origin + u * x_axis + v * y_axis + depth * z_axis' },
                'camera'           => { 'parallel' => true, 'ortho_height' => v1 - v0 },
                'background'       => background,
                'dot_px'           => capture[:composite]['dot_px'],
                'spacing'          => spacing,
                'points_drawn'     => capture[:composite]['points_drawn'].to_i,
                'pixels_covered_percent' => (100.0 * capture[:composite]['pixels_covered'].to_f / (width * height)).round(1),
                'clouds'           => capture[:composite]['clouds'],
                'calibration_px'   => capture[:calibration_px],
                'turned_clip'      => capture[:composite]['turned_clip'] ? true : false,
                'view_word'        => view_word
            }
            if spec['place'] == false
                result['placed'] = false
            else
                result.merge!(na_place(model, frame, [u0, u1, v0, v1], [behind, front], placement, offset, png_path,
                                       view_word, name, spec['tag'] || NA_DEFAULT_TAG, result, warnings))
            end
            result['warnings'] = warnings unless warnings.empty?
            result
        end
        # ------------------------------------------------------------

        # FUNCTION | The Viewer's MCP Seam, With the Ortho Feature
        # ------------------------------------------------------------
        def self.Na__ToScaleOrthoTextureMaker__PointCloudOrtho__Viewer
            unless defined?(::Na__PointCloudViewer::Na__McpOperations) &&
                   ::Na__PointCloudViewer::Na__McpOperations.respond_to?(:Na__PointCloudViewer__McpRead)
                na_refuse('unsupported', 'Point Cloud Ortho Plane needs Na Point Cloud Viewer, loaded in this SketchUp.',
                          'Install or update the Point Cloud Viewer (0.14.7 or newer), then restart SketchUp or use its Reload Plugin.')
            end
            operations = ::Na__PointCloudViewer::Na__McpOperations
            features = operations.const_defined?(:NA_FEATURES) ? operations::NA_FEATURES : []
            unless features.include?('ortho')
                na_refuse('unsupported', 'Point Cloud Ortho Plane needs Na Point Cloud Viewer 0.14.7 or newer (its turned clip boxes).',
                          'Update the Point Cloud Viewer, use its Reload Plugin (Settings), then try again.')
            end
            operations
        end
        # ------------------------------------------------------------

        # FUNCTION | Is It Available? [true, nil] or [false, reason]
        # ------------------------------------------------------------
        def self.Na__ToScaleOrthoTextureMaker__PointCloudOrtho__Available
            self.Na__ToScaleOrthoTextureMaker__PointCloudOrtho__Viewer
            [true, nil]
        rescue Na__PointCloudOrthoError => error
            [false, error.message]
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Frames (shared by the button and the MCP)
# -----------------------------------------------------------------------------

        # A standard view (top, bottom, front, back, left, right) through origin.
        def self.Na__ToScaleOrthoTextureMaker__PointCloudOrtho__FrameStandard(view_name, origin = [0.0, 0.0, 0.0])
            axes = NA_STANDARD_VIEWS[view_name.to_s]
            na_refuse('invalid_params', "view must be one of #{NA_STANDARD_VIEWS.keys.join(', ')}, wall or frame, not '#{view_name}'.") unless axes
            { 'origin' => na_triple(origin, 'origin'), 'x_axis' => axes[0], 'y_axis' => axes[1] }
        end

        # A wall's face line in plan, a to b, seen from look_from (any point on the
        # camera's side). The picture runs from its left end to its right end as
        # seen from there: a and b are swapped when look_from is on a to b's left.
        # Returns [frame, length]; the origin is the left end at z 0, so u runs
        # 0..length along the wall and v is the model's z.
        def self.Na__ToScaleOrthoTextureMaker__PointCloudOrtho__FrameWall(a, b, look_from)
            a = na_triple(a, 'wall a', true)
            b = na_triple(b, 'wall b', true)
            side = na_triple(look_from, 'wall look_from', true)
            dx = b[0] - a[0]
            dy = b[1] - a[1]
            length = Math.sqrt(dx * dx + dy * dy)
            na_refuse('invalid_params', 'wall a and b are the same point in plan.', 'Give two points along the wall face, apart.') if length < 1e-6
            right = [dy / length, -dx / length, 0.0]
            across = (side[0] - a[0]) * right[0] + (side[1] - a[1]) * right[1]
            na_refuse('invalid_params', 'look_from is on the wall line itself.', 'Give a point on the side you look from, e.g. a metre into the garden.') if across.abs < 1e-6
            if across < 0
                a, b = b, a
                dx = -dx
                dy = -dy
            end
            x = [dx / length, dy / length, 0.0]
            [{ 'origin' => [a[0], a[1], 0.0], 'x_axis' => x, 'y_axis' => [0.0, 0.0, 1.0] }, length]
        end

        # The current view's camera, which must be parallel: the picture is what
        # the view shows. Returns [frame, u, v].
        def self.Na__ToScaleOrthoTextureMaker__PointCloudOrtho__FrameCamera(view)
            camera = view.camera
            if camera.perspective?
                na_refuse('invalid_params', 'The camera is in Perspective; a point cloud ortho plane needs a parallel camera.',
                          'Camera > Parallel Projection, set the view (a scene or a standard view), then try again.')
            end
            up = camera.up.normalize
            toward = camera.direction.reverse.normalize
            x = up * toward
            y = toward * x
            height = camera.height.to_f
            aspect = view.vpheight.to_f > 0 ? view.vpwidth.to_f / view.vpheight.to_f : 1.0
            half_w = height * aspect / 2.0
            frame = { 'origin' => camera.target.to_a, 'x_axis' => x.normalize.to_a, 'y_axis' => y.normalize.to_a }
            [frame, [-half_w, half_w], [-height / 2.0, height / 2.0]]
        end

        # A face (world points, world normal), seen from the side the view looks
        # at it from: x level where it can be, y up the face. Returns [frame, u, v]
        # round the face, grown by margin.
        def self.Na__ToScaleOrthoTextureMaker__PointCloudOrtho__FrameFace(points, normal, view_direction, margin)
            n = na_unit(normal.to_a, 'face normal')
            n = n.map { |value| -value } if na_dot(n, view_direction.to_a) > 0
            up = [0.0, 0.0, 1.0]
            y = if na_dot(n, up).abs > 0.99
                    [0.0, 1.0, 0.0]
                else
                    na_unit(na_sub(up, na_scale(n, na_dot(up, n))), 'face up')
                end
            x = na_cross(y, n)
            origin = points.first.to_a
            frame = { 'origin' => origin, 'x_axis' => x, 'y_axis' => y }
            us = points.map { |p| na_dot(na_sub(p.to_a, origin), x) }
            vs = points.map { |p| na_dot(na_sub(p.to_a, origin), y) }
            [frame, [us.min - margin, us.max + margin], [vs.min - margin, vs.max + margin]]
        end

        # FUNCTION | A Frame From a Cloud's Clip Box (13-Nov-2026, viewer 0.14.8)
        # ------------------------------------------------------------
        # The clip box of `cloud` (an id or name; default the viewer's active
        # cloud), level or TURNED: a picture square to its FRONT face (its own
        # -y side, looking along its own +y), as wide and as high as the box,
        # the box's own depth the slab. So a box turned to a wall in the viewer
        # (Turn to Two Points) gives that wall's elevation in one step.
        # Returns [frame, u, v, depth, the cloud's name], inches.
        def self.Na__ToScaleOrthoTextureMaker__PointCloudOrtho__FrameClip(cloud = nil)
            operations = self.Na__ToScaleOrthoTextureMaker__PointCloudOrtho__Viewer
            state = na_read(operations, 'state', 'per_inch' => 1.0)
            clouds = Array(state['clouds'])
            wanted = cloud.to_s.empty? ? state['active_cloud'].to_s : cloud.to_s
            entry = clouds.find { |each| each['id'] == wanted || each['name'] == wanted }
            unless entry
                na_refuse('invalid_params', cloud.to_s.empty? ? 'There is no point cloud in this model.' : "No point cloud is called '#{cloud}'.",
                          'Pick the cloud on the viewer\'s View tab (it becomes the active cloud), or pass its id or name.')
            end
            clip = entry['clip']
            unless clip
                na_refuse('invalid_params', "#{entry['name']} has no clip box.",
                          'Draw one in the viewer (Clipping tab, Draw Clip Box), turn it to the wall with Turn to Two Points, then make the plane.')
            end
            turned = clip['turned']
            if turned
                origin, x, y = turned['origin'], turned['x_axis'], turned['y_axis']
                lo, hi = turned['min'], turned['max']
            else
                origin, x, y = [0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0]
                lo, hi = clip['min'], clip['max']
            end
            z = na_cross(x, y)
            front = (0..2).map { |k| origin[k].to_f + lo[1].to_f * y[k].to_f }   # on the front face's plane
            frame = { 'origin' => front, 'x_axis' => x.map(&:to_f), 'y_axis' => z }
            [frame, [lo[0].to_f, hi[0].to_f], [lo[2].to_f, hi[2].to_f], [hi[1].to_f - lo[1].to_f, 0.0], entry['name'].to_s]
        end
        # ------------------------------------------------------------

        # Picture extent along v from the cloud itself (a wall picked in plan):
        # the 1st to 99th percentile of the points in the slab, padded.
        def self.Na__ToScaleOrthoTextureMaker__PointCloudOrtho__AutoV(frame, u, depth, clouds = nil)
            operations = self.Na__ToScaleOrthoTextureMaker__PointCloudOrtho__Viewer
            behind, front = na_depth(depth)
            low = NA_AUTO_V_RANGE_MM[0] / NA_MM
            high = NA_AUTO_V_RANGE_MM[1] / NA_MM
            lows = []
            highs = []
            na_clouds(operations, clouds).each do |cloud|
                reply = na_read(operations, 'histogram', 'cloud' => cloud['id'], 'frame' => na_frame_spec(frame), 'axis' => 'y', 'bin' => 100.0 / NA_MM,
                                                         'min' => [u[0], low, -behind], 'max' => [u[1], high, front], 'per_inch' => 1.0)
                next unless reply['points'].to_i > 0
                p = reply['percentiles'] || {}
                lows << (p['p1'] || p['1']).to_f
                highs << (p['p99'] || p['99']).to_f
            end
            na_refuse('invalid_params', 'No points in the slab along that wall.', 'Check the wall line, the side and the slab depth.') if lows.empty?
            pad = NA_AUTO_V_PAD_MM / NA_MM
            [lows.min - pad, highs.max + pad]
        end

        # Adam's view word for the plane's name, from where its camera looks:
        # PlanView (from above), UnderView, or the elevation whose face it sees
        # (a face looking -Y is Front, -X Left).
        def self.Na__ToScaleOrthoTextureMaker__PointCloudOrtho__ViewWord(frame)
            frame = na_frame_in(frame) unless frame.key?('z_axis')
            z = frame['z_axis']
            return 'PlanView' if z[2] > 0.7
            return 'UnderView' if z[2] < -0.7
            if z[1].abs >= z[0].abs
                z[1] < 0 ? 'FrontElevation' : 'BackElevation'
            else
                z[0] < 0 ? 'LeftElevation' : 'RightElevation'
            end
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dots That Meet
# -----------------------------------------------------------------------------

        # The dot that covers the gaps: from each cloud's spacing in its sparser
        # quarter of the slab (the viewer's spacing_sparse; the median where an
        # older viewer lacks it), the densest cloud's. Measured on Kann's Google
        # Earth cloud, 13-Nov-2026: dots from the median left a speckle on the
        # wall faces, where the trees crowd the points.
        def self.na_fill_dot(operations, frame, clouds, min, max, resolution, warnings)
            cell = [NA_SPACING_CELL_MM / NA_MM, resolution * 4].max
            spacings = clouds.map do |cloud|
                reply = na_read(operations, 'spacing', 'cloud' => cloud['id'], 'frame' => na_frame_spec(frame), 'min' => min, 'max' => max,
                                                     'cell' => cell, 'per_inch' => 1.0)
                reply['spacing_sparse'] || reply['spacing']
            end.compact.map(&:to_f).select(&:positive?)
            if spacings.empty?
                warnings << 'No points in the slab, so the dots keep the cloud\'s own size.'
                return [nil, nil]
            end
            spacing = spacings.min
            dot = (NA_FILL_FACTOR * spacing / resolution).ceil.to_f
            dot = [[dot, 1.0].max, NA_MAX_DOT_PX].min
            warnings << "The points are #{(spacing * NA_MM).round} mm apart, so dots of #{dot.to_i} px blur below #{(spacing * NA_MM).round} mm." if dot >= NA_MAX_DOT_PX
            [dot, spacing]
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Capture (zero trace)
# -----------------------------------------------------------------------------

        def self.na_capture(model, operations, frame, extent, depth, width, height, background, spec, clouds, dot_px, warnings)
            u0, u1, v0, v1 = extent
            behind, front = depth
            view = model.active_view
            saved = na_camera_state(view.camera)
            camera = na_camera(frame, extent, front)
            png = File.join(Dir.tmpdir, "na_cloud_ortho_#{Time.now.to_i}_#{rand(99_999)}.png")
            calibration = nil
            composite = nil
            model.start_operation(NA_CAPTURE_OPERATION, true)
            begin
                na_hide_model(model) unless spec['hide'].to_s == 'none'
                view.camera = camera
                capture = Na__ToScaleOrthoTextureMaker__ProjectionEngine.Na__ToScaleOrthoTextureMaker__ProjectionEngine__CaptureViewportImage(
                    { view: view, aspect: width.to_f / height }, width, background.to_sym
                )
                na_refuse('operation_failed', capture[:message].to_s, 'Try a coarser resolution.') unless capture[:success]
                unless capture[:output_width] == width && capture[:output_height] == height
                    na_refuse('operation_failed', "The capture came out #{capture[:output_width]} x #{capture[:output_height]}, not #{width} x #{height}.")
                end
                FileUtils.mv(capture[:image_path], png)
                arguments = {
                    'camera_object' => camera, 'path' => png, 'width' => width, 'height' => height,
                    'clip_frame' => na_frame_spec(frame), 'clip_min' => [u0, v0, -behind], 'clip_max' => [u1, v1, front]
                }
                arguments['clouds'] = clouds.map { |cloud| cloud['id'] } if spec['clouds']
                arguments['dot_px'] = dot_px if dot_px
                arguments['look'] = spec['look'] if spec['look'].is_a?(Hash) && !spec['look'].empty?
                composite = na_read(operations, 'composite', arguments)
                unless composite['composited']
                    na_refuse('operation_failed', composite['note'] || 'No point cloud was drawn.',
                              'Switch the point cloud overlay on and show the cloud, then try again.')
                end
                warnings << composite['note'] if composite['note']
                calibration = na_calibrate(model, view, frame, extent, width, height) unless spec['calibrate'] == false
            ensure
                model.abort_operation
                na_restore_camera(view, saved)
            end
            if calibration.nil? && spec['calibrate'] != false
                warnings << 'The pixel map could not be proved (the style draws no edges?); it follows the camera maths.'
            elsif calibration && calibration > NA_CALIBRATION_LIMIT_PX
                File.delete(png) if File.exist?(png)
                na_refuse('operation_failed', "The picture is #{calibration.round(2)} px off its own map.", 'Report this: the capture and the plane would not line up.')
            end
            { png: png, composite: composite, calibration_px: calibration && calibration.round(3) }
        end

        # A parallel camera square to the frame, centred on the picture, looking
        # along -z from in front of the slab.
        def self.na_camera(frame, extent, front)
            u0, u1, v0, v1 = extent
            centre = na_to_model(frame, [(u0 + u1) / 2.0, (v0 + v1) / 2.0, 0.0])
            eye = na_to_model(frame, [(u0 + u1) / 2.0, (v0 + v1) / 2.0, front + NA_EYE_GAP_MM / NA_MM])
            camera = Sketchup::Camera.new(Geom::Point3d.new(*eye), Geom::Point3d.new(*centre), Geom::Vector3d.new(*frame['y_axis']))
            camera.perspective = false
            camera.height = v1 - v0
            camera
        end

        def self.na_camera_state(camera)
            {
                eye: camera.eye, target: camera.target, up: camera.up, perspective: camera.perspective?,
                fov: camera.perspective? ? camera.fov : nil, height: camera.perspective? ? nil : camera.height
            }
        end

        def self.na_restore_camera(view, saved)
            camera = Sketchup::Camera.new(saved[:eye], saved[:target], saved[:up])
            camera.perspective = saved[:perspective]
            camera.fov = saved[:fov] if saved[:fov]
            camera.height = saved[:height] if saved[:height]
            view.camera = camera
        rescue StandardError
            nil
        end

        # Inside the capture's own (aborted) operation.
        def self.na_hide_model(model)
            model.entities.each { |entity| entity.hidden = true if entity.respond_to?(:hidden=) && !entity.hidden? }
        end

        # Two crosses on the frame's plane, captured without the clouds: where
        # their lines land against where the map says they must (pixel edges).
        # Returns the worst error in pixels, or nil when no line shows.
        def self.na_calibrate(model, view, frame, extent, width, height)
            u0, u1, v0, v1 = extent
            res = (u1 - u0) / width
            arm = [width, height].min * 0.1
            return nil if arm < 6
            marks = [[(width * 0.3).round, (height * 0.3).round], [(width * 0.7).round, (height * 0.7).round]]
            group = model.entities.add_group
            marks.each do |col, row_up|
                p = [u0 + col * res, v0 + row_up * res]
                group.entities.add_line(Geom::Point3d.new(*na_to_model(frame, [p[0] - arm * res, p[1], 0.0])), Geom::Point3d.new(*na_to_model(frame, [p[0] + arm * res, p[1], 0.0])))
                group.entities.add_line(Geom::Point3d.new(*na_to_model(frame, [p[0], p[1] - arm * res, 0.0])), Geom::Point3d.new(*na_to_model(frame, [p[0], p[1] + arm * res, 0.0])))
            end
            path = File.join(Dir.tmpdir, "na_cloud_ortho_check_#{Time.now.to_i}_#{rand(99_999)}.png")
            engine = Na__ToScaleOrthoTextureMaker__ProjectionEngine
            snapshot = engine.na_apply_white_background(model)   # sky and ground would read as ink
            begin
                view.write_image(filename: path, width: width, height: height, antialias: false, transparent: false)
            ensure
                engine.na_restore_rendering_options(model, snapshot)
            end
            picture = Sketchup::ImageRep.new
            picture.load_file(path)
            errors = marks.map do |col, row_up|
                row = height - row_up
                [na_line_offset(picture, :column, col, row, arm), na_line_offset(picture, :row, row, col, arm)]
            end.flatten
            File.delete(path) if File.exist?(path)
            return nil if errors.any?(&:nil?)
            errors.max
        rescue StandardError
            nil
        end

        # How far a drawn line sits from the pixel edge `edge` (a column edge for
        # :column, a row edge for :row), measured over the arm round `across`.
        def self.na_line_offset(picture, kind, edge, across, arm)
            bytes = picture.bits_per_pixel / 8
            stride = picture.width * bytes + picture.row_padding
            data = picture.data
            background = data.byteslice(0, 3).bytes
            span = ((across - arm * 0.6).ceil..(across + arm * 0.6).floor)
            hits = []
            ((edge - 4)..(edge + 3)).each do |line|
                next if line < 0 || line >= (kind == :column ? picture.width : picture.height)
                inked = span.count do |other|
                    col, row = kind == :column ? [line, other] : [other, line]
                    next false if col < 0 || row < 0 || col >= picture.width || row >= picture.height
                    at = row * stride + col * bytes
                    data.byteslice(at, 3).bytes.zip(background).map { |a, b| (a - b).abs }.max > 60
                end
                hits << line if inked >= span.size * 0.6
            end
            return nil if hits.empty?
            ((hits.sum.to_f / hits.length) + 0.5 - edge).abs
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Saving the Picture
# -----------------------------------------------------------------------------

        def self.na_save_png(model, save_path, temp_png, view_word, name, resolution, warnings)
            if save_path && !save_path.to_s.strip.empty?
                path = File.expand_path(save_path.to_s)
                path += '.png' unless File.extname(path).casecmp?('.png')
                na_refuse('file_error', "#{path} already exists.", 'Pass another save_path; a picture is never written over.') if File.exist?(path)
            else
                folder, client = na_output_folder(model, warnings)
                FileUtils.mkdir_p(folder)
                number = na_next_number(folder)
                path = File.join(folder, "#{client}__PointCloudOrtho__#{format('%02d', number)}__#{view_word}__#{name}__#{na_res_text(resolution)}mmPx__#{na_date}.png")
            end
            FileUtils.mkdir_p(File.dirname(path))
            FileUtils.cp(temp_png, path)
            path
        end

        # The job folder's 01__ReferenceFiles/12__PointCloud__Orthos (the model's
        # NNNNN__Client__... ancestor), beside the model when there is none, or
        # the temp folder for an unsaved model. Returns [folder, client].
        def self.na_output_folder(model, warnings)
            path = model.path.to_s.tr('\\', '/')   # Dir.glob reads backslashes as escapes on Windows
            if path.empty?
                warnings << 'The model is not saved, so the picture went to the temp folder.'
                return [File.join(Dir.tmpdir, 'PointCloudOrthos'), 'Model']
            end
            dir = File.dirname(path)
            loop do
                name = File.basename(dir)
                return [File.join(dir, *NA_FOLDER_PARTS), name.split('__')[1] || 'Job'] if name =~ /\A\d{5}__/
                parent = File.dirname(dir)
                break if parent == dir
                dir = parent
            end
            [File.join(File.dirname(path), 'PointCloudOrthos'), File.basename(path, '.skp').split('__').first]
        end

        def self.na_next_number(folder)
            numbers = Dir.glob(File.join(folder.tr('\\', '/'), '*__PointCloudOrtho__*.png')).map do |file|
                File.basename(file)[/__PointCloudOrtho__(\d+)__/, 1].to_i
            end
            (numbers.max || 0) + 1
        end

        def self.na_res_text(resolution)
            mm = (resolution * NA_MM).round(2)
            mm == mm.round ? mm.round.to_s : mm.to_s.tr('.', '-')
        end

        def self.na_date(time = Time.now)
            format('%02d-%s-%d', time.day, NA_MONTHS[time.month - 1], time.year)
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | The Plane
# -----------------------------------------------------------------------------

        def self.na_place(model, frame, extent, depth, placement, offset, png_path, view_word, name, tag_name, result, warnings)
            u0, u1, v0, v1 = extent
            started = false
            model.start_operation(NA_OPERATION_NAME, true)
            started = true
            plane_depth, in_front_of = placement == 'front' ? na_front_depth(model, frame, extent, depth) : [0.0, []]
            plane_depth += offset
            corners = [[u0, v0], [u1, v0], [u1, v1], [u0, v1]].map { |u, v| Geom::Point3d.new(*na_to_model(frame, [u, v, plane_depth])) }
            group = model.entities.add_group
            face = group.entities.add_face(corners)
            na_refuse('operation_failed', 'The plane\'s face could not be made.') unless face
            toward_camera = Geom::Vector3d.new(*frame['z_axis'])
            Na__ToScaleOrthoTextureMaker__PlaneBuilder.na_orient_face_toward_camera(face, toward_camera.reverse)
            textured = Na__ToScaleOrthoTextureMaker__MaterialUvBuilder.Na__ToScaleOrthoTextureMaker__MaterialUvBuilder__ApplyTextureToFace(
                model: model, face: face, corner_points: corners, texture_path: png_path,
                material_name: "Na__OrthoProjected__PointCloud__#{File.basename(png_path, '.png')}"
            )
            na_refuse('operation_failed', textured[:message].to_s) unless textured[:success]
            group.name = "#{NA_PLANE_PREFIX}#{view_word}__PointCloudOrtho__#{name}"
            group.layer = model.layers[tag_name.to_s] || model.layers.add(tag_name.to_s)
            na_stamp(group, frame, extent, depth, plane_depth, png_path, view_word, result)
            model.commit_operation
            started = false
            {
                'placed'       => true,
                'id'           => group.persistent_id,
                'name'         => group.name,
                'tag'          => group.layer.name,
                'placement'    => placement,
                'plane_depth'  => plane_depth,
                'in_front_of'  => in_front_of,
                'corners'      => corners.map(&:to_a),
                'undo_step'    => NA_OPERATION_NAME
            }
        rescue StandardError
            model.abort_operation if started
            raise
        end

        # How far toward the camera the plane goes: just in front of the nearest
        # visible geometry inside the slab (raytests over the picture, other
        # drawing planes passed through), never behind the frame's own plane,
        # rounded out to a whole 5 mm from the MODEL origin along the normal, so
        # a plan or square elevation lands on the 5 mm grid whatever the frame's
        # origin (a camera's target is rarely on it).
        def self.na_front_depth(model, frame, extent, depth)
            u0, u1, v0, v1 = extent
            behind, front = depth
            down = Geom::Vector3d.new(*frame['z_axis']).reverse
            deepest = nil
            names = {}
            NA_RAY_SAMPLES.times do |i|
                NA_RAY_SAMPLES.times do |j|
                    u = u0 + (u1 - u0) * (i + 0.5) / NA_RAY_SAMPLES
                    v = v0 + (v1 - v0) * (j + 0.5) / NA_RAY_SAMPLES
                    start = Geom::Point3d.new(*na_to_model(frame, [u, v, front]))
                    NA_RAY_SKIPS.times do
                        hit = model.raytest([start, down], true)
                        break unless hit
                        point, path = hit
                        z = na_dot(na_sub(point.to_a, frame['origin']), frame['z_axis'])
                        break if z < -behind
                        owner = path.find { |entity| entity.respond_to?(:name) && entity.name.to_s.start_with?(NA_PLANE_PREFIX) }
                        if owner
                            start = point.offset(down, 0.05)
                            next
                        end
                        top = path.find { |entity| entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance) }
                        names[(top && top.name.to_s.empty? ? (top.respond_to?(:definition) ? top.definition.name : 'Group') : (top ? top.name : 'loose geometry'))] = true
                        deepest = z if deepest.nil? || z > deepest
                        break
                    end
                end
            end
            gap = NA_FRONT_GAP_MM / NA_MM
            grid = NA_GRID_MM / NA_MM
            base = na_dot(frame['origin'], frame['z_axis'])
            plane = deepest ? [0.0, deepest + gap].max : 0.0
            [((base + plane) / grid - 1e-9).ceil * grid - base, names.keys.first(8)]
        end

        def self.na_stamp(group, frame, extent, depth, plane_depth, png_path, view_word, result)
            dict = Na__ToScaleOrthoTextureMaker__PlaneBuilder::NA_CAPTURE_DICT_NAME
            u0, u1, v0, v1 = extent
            mm = ->(value) { (value * NA_MM).round(2) }
            {
                'label' => view_word, 'mm_width' => mm.call(u1 - u0), 'mm_height' => mm.call(v1 - v0),
                'pixel_width' => result['pixels'][0], 'pixel_height' => result['pixels'][1],
                'background_mode' => result['background'], 'capture_time_iso' => Time.now.strftime('%Y%m%dT%H%M%S'),
                'plugin_version' => Na__ToScaleOrthoTextureMaker__PlaneBuilder::NA_PLUGIN_VERSION,
                'source' => 'point_cloud', 'point_cloud_ortho_version' => NA_VERSION,
                'resolution_mm' => mm.call(result['resolution']), 'png_path' => png_path,
                'frame_origin_mm' => frame['origin'].map { |value| mm.call(value) }, 'frame_x_axis' => frame['x_axis'], 'frame_y_axis' => frame['y_axis'],
                'u_range_mm' => [mm.call(u0), mm.call(u1)], 'v_range_mm' => [mm.call(v0), mm.call(v1)],
                'depth_mm' => depth.map { |value| mm.call(value) }, 'plane_depth_mm' => mm.call(plane_depth),
                'dot_px' => result['dot_px'].to_f, 'calibration_px' => result['calibration_px'].to_f,
                'clouds' => Array(result['clouds']).join(',')
            }.each { |key, value| group.set_attribute(dict, key, value) }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Reading Values
# -----------------------------------------------------------------------------

        def self.na_read(operations, action, arguments)
            operations.Na__PointCloudViewer__McpRead(action, arguments)
        rescue Na__PointCloudOrthoError
            raise
        rescue StandardError => error
            if error.respond_to?(:na_code)
                na_refuse(error.na_code, error.message, error.respond_to?(:na_hint) ? error.na_hint : nil)
            end
            raise
        end

        # The clouds to draw: those named, else every cloud on show and loaded.
        # [{ 'id', 'name' }]
        def self.na_clouds(operations, keys)
            state = na_read(operations, 'state', 'per_inch' => 1.0)
            all = Array(state['clouds'])
            chosen = if keys
                         Array(keys).map do |key|
                             found = all.find { |cloud| cloud['id'] == key.to_s } || all.find { |cloud| cloud['name'].to_s.casecmp?(key.to_s) }
                             na_refuse('not_found', "No point cloud '#{key}' in this model.", "Use one of: #{all.map { |c| c['id'] }.join(', ')}.") unless found
                             found
                         end
                     else
                         all.select { |cloud| cloud['shown'] && cloud['loaded'] }
                     end
            na_refuse('not_found', 'No point cloud is on show and loaded.', 'Show the cloud in the Point Cloud Viewer (and Reload it), then try again.') if chosen.empty?
            unloaded = chosen.reject { |cloud| cloud['loaded'] }
            na_refuse('operation_failed', "#{unloaded.map { |c| c['name'] }.join(', ')} is not loaded.", 'Reload it in the Point Cloud Viewer, then try again.') unless unloaded.empty?
            chosen.map { |cloud| { 'id' => cloud['id'], 'name' => cloud['name'] } }
        end

        def self.na_frame_in(spec)
            na_refuse('invalid_params', 'frame must be an object: origin, x_axis, y_axis.') unless spec.is_a?(Hash)
            origin = na_triple(spec['origin'] || [0.0, 0.0, 0.0], 'frame origin')
            x = na_unit(na_triple(spec['x_axis'], 'frame x_axis'), 'frame x_axis')
            raw_y = na_triple(spec['y_axis'], 'frame y_axis')
            y = na_unit(na_sub(raw_y, na_scale(x, na_dot(raw_y, x))), 'frame y_axis (square to x_axis)')
            { 'origin' => origin, 'x_axis' => x, 'y_axis' => y, 'z_axis' => na_cross(x, y) }
        end

        def self.na_frame_spec(frame)
            { 'origin' => frame['origin'], 'x_axis' => frame['x_axis'], 'y_axis' => frame['y_axis'] }
        end

        def self.na_frame_out(frame)
            tidy = ->(axis) { axis.map { |value| value.round(9) + 0.0 } }
            { 'origin' => frame['origin'], 'x_axis' => tidy.call(frame['x_axis']), 'y_axis' => tidy.call(frame['y_axis']), 'z_axis' => tidy.call(frame['z_axis']) }
        end

        def self.na_to_model(frame, point)
            o = frame['origin']
            x = frame['x_axis']
            y = frame['y_axis']
            z = frame['z_axis']
            (0..2).map { |k| o[k] + point[0] * x[k] + point[1] * y[k] + point[2] * z[k] }
        end

        def self.na_length(value, label)
            number = na_number(value, label)
            na_refuse('invalid_params', "#{label} must be a positive length.") unless number > 0
            number
        end

        def self.na_number(value, label)
            na_refuse('invalid_params', "#{label} must be a number, not #{value.inspect}.") unless value.is_a?(Numeric) && value.to_f.finite?
            value.to_f
        end

        def self.na_range(value, label)
            unless value.is_a?(Array) && value.length == 2 && value.all? { |item| item.is_a?(Numeric) && item.to_f.finite? }
                na_refuse('invalid_params', "#{label} must be [min, max], not #{value.inspect}.", 'Give the picture\'s extent along the frame\'s axes.')
            end
            low, high = value.map(&:to_f)
            na_refuse('invalid_params', "#{label} max must be greater than its min.") unless high > low
            [low, high]
        end

        def self.na_depth(value)
            unless value.is_a?(Array) && value.length == 2 && value.all? { |item| item.is_a?(Numeric) && item.to_f.finite? && item.to_f >= 0 }
                na_refuse('invalid_params', "depth must be [behind, front], each zero or more, not #{value.inspect}.",
                          'How far behind and in front of the frame\'s plane the slab of cloud reaches.')
            end
            behind, front = value.map(&:to_f)
            na_refuse('invalid_params', 'depth gives the slab no thickness.') unless behind + front > 0
            [behind, front]
        end

        def self.na_choice(value, allowed, label)
            text = value.to_s
            na_refuse('invalid_params', "#{label} must be one of #{allowed.join(', ')}, not '#{text}'.") unless allowed.include?(text)
            text
        end

        def self.na_word(value)
            text = value.to_s.strip.gsub(/[^A-Za-z0-9_\-]+/, '_').gsub(/_{3,}/, '__').sub(/\A_+/, '').sub(/_+\z/, '')
            text.empty? ? NA_DEFAULT_NAME : text
        end

        def self.na_triple(value, label, plan = false)
            value = value.to_a if value.respond_to?(:to_a) && !value.is_a?(Array)
            value = value + [0.0] if plan && value.is_a?(Array) && value.length == 2
            unless value.is_a?(Array) && value.length == 3 && value.all? { |item| item.is_a?(Numeric) && item.to_f.finite? }
                na_refuse('invalid_params', "#{label} must be [x, y, z]#{plan ? ' or [x, y]' : ''}, not #{value.inspect}.")
            end
            value.map(&:to_f)
        end

        def self.na_unit(vector, label)
            length = Math.sqrt(na_dot(vector, vector))
            na_refuse('invalid_params', "#{label} has no length.") unless length > 1e-9
            vector.map { |value| value / length }
        end

        def self.na_dot(a, b)
            a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
        end

        def self.na_cross(a, b)
            [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
        end

        def self.na_sub(a, b)
            [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
        end

        def self.na_scale(a, s)
            [a[0] * s, a[1] * s, a[2] * s]
        end

        def self.na_refuse(code, message, hint = nil, details = nil)
            raise Na__PointCloudOrthoError.new(code, message, hint, details)
        end

# endregion -------------------------------------------------------------------

    end # module Na__ToScaleOrthoTextureMaker__PointCloudOrtho
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
