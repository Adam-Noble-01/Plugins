# =============================================================================
# NA POINT CLOUD VIEWER - MCP OPERATIONS (AGENT SEAM)
# =============================================================================
#
# FILE       : Na__PointCloudViewer__McpOperations__Main__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__McpOperations
# CREATED    : 09-Nov-2026 (v0.13.1)
# PURPOSE    : What an agent may do with the model's point clouds through
#              Adam's Na SketchUp MCP plugin (tools point_cloud_state,
#              point_cloud_clip, point_cloud_view and point_cloud_slice). The
#              MCP handlers are thin: they read lengths in the call's units,
#              resolve entity ids, then call the two entry points below.
#
# ENTRY POINTS:
# - Na__McpOperations.Na__PointCloudViewer__McpRead(action, params)
#     state, count, histogram, image, points, density (the last two from v0.14.0),
#     composite (v0.14.1: the clouds on show drawn over a SketchUp capture),
#     fit (v0.14.2: a plane, line, circle, cylinder or box from the points),
#     check (v0.14.3: how far the points sit from a model's faces),
#     heightmap and profile (v0.14.4: heights per cell, heights along a path);
#     count, histogram, image, points, density, heightmap and profile take a
#     slice frame (v0.14.6: 'frame', any angle; see below)
# - Na__McpOperations.Na__PointCloudViewer__McpEdit(action, params)
#     clip_box, clip_on, clip_off, clip_scene, view
# - Refusals raise Na__PointCloudViewer::Na__McpOperationsError (code,
#   message, hint, details); the MCP handler turns them into its own error.
#
# LENGTHS: every length arrives in MODEL INCHES (the handler converts the
#   call's units). Every length returned is multiplied by params['per_inch']
#   (25.4, millimetres, when absent).
#
# WHAT IT REUSES (no second copy of a rule):
# - Clip boxes: Na__ClipBox (ApplyAreaBox, SetEnabledOn, SceneActivate,
#   GrowToGrid) and the cloud store, so each change is ONE undo step named
#   "Point Cloud: ...", exactly as Draw Clip Box and the Clipping tab make it.
# - Show and look: Na__CloudSet and Na__RenderController, as the dialog's
#   switches and sliders use them: view settings, never written to the model,
#   no undo step; each cloud's look is remembered on this computer.
# - Counting: the engine's napc_box_count (every point, on the render pool):
#   one pass over the whole cloud, about 28 ms per 43 M points (SK02's
#   RealityCapture cloud, 09-Nov-2026).
# - Histograms and density images (v0.14.0, ABI 9): napc_box_grid, one pass
#   for any number of bins or pixels. A histogram is a grid one cell wide.
# - Points (v0.14.0, ABI 9): napc_box_points, the first N the box keeps. The
#   engine stores every cloud shuffled, so they are an even sample. Up to
#   NA_MAX_INLINE_POINTS come back in the reply; up to NA_MAX_FILE_POINTS go
#   to a .npz the skill's pc_kit.py reads (p: model mm, float64; c: BGRA).
# - Overlays (v0.14.1): image and density draw model edges the MCP handler
#   collects (world segments, inches) in red, so an agent sees its model on
#   the slice. composite draws the clouds on show over a SketchUp capture with
#   the live overlay's own camera maths (na_camera_params) and each cloud's own
#   look. SketchUp's write_image keeps the camera's vertical field of view for
#   any image shape: measured 09-Nov-2026, within a pixel, perspective and
#   parallel.
# - Fitting (v0.14.2): fit reads an even sample of the box (napc_box_points)
#   and hands it to Na__McpFit (Na__PointCloudViewer__McpOperations__Fit__.rb,
#   pure Ruby): RANSAC then least squares, every answer with its residuals.
# - Checking (v0.14.3): check measures an even sample of the box against the
#   model's faces (world triangles the MCP collects) with Na__McpCheck
#   (Na__PointCloudViewer__McpOperations__Check__.rb, pure Ruby, a grid of
#   cells `reach` wide): overall, per part, the worst spots, and a heatmap.
# - Heights (v0.14.4): heightmap and profile read an even sample of the box (a
#   profile one box a piece of its path) and hand it to Na__McpHeight
#   (Na__PointCloudViewer__McpOperations__Height__.rb, pure Ruby, a counting
#   sort): percentiles a cell or station by pc_terrain.py's rank rule, its
#   rasters.npz layout for files, a coloured, shaded, contoured picture.
# - Slices at any angle (v0.14.6): params['frame'] (origin, then angle or
#   x_axis and y_axis, model inches) is made by Na__McpFrame
#   (Na__PointCloudViewer__McpOperations__Frame__.rb) and folded into the
#   cloud's local -> model transform, so the engine, which tests and returns
#   points in the coordinates that transform gives, works in the frame. A
#   wrapped slot (Na__FramedSlot) hands every call that folded transform.
#   With a frame, min, max, the view, the axis, a path and every position in
#   and out are in the frame; the reply echoes the frame; a points file keeps
#   model mm in 'p' and adds the frame's in 'f'; model edges drawn over a
#   picture are moved into the frame first. Measured against numpy on the real
#   DLL, 09-Nov-2026: counts and grids equal, points to 1e-12 mm.
# - Images: the engine's own renderer (napc_render_png) with a parallel camera
#   along a model axis and the box as its clip box, re-encoded here as a
#   greyscale PNG (white paper, black points, optional grid). The nearest
#   point wins a pixel: it shows shape, not density.
#
#
# =============================================================================

require 'json'
require 'zlib'
require 'delegate'
require_relative 'Na__PointCloudViewer__McpOperations__Frame__'
require_relative 'Na__PointCloudViewer__McpOperations__Fit__'
require_relative 'Na__PointCloudViewer__McpOperations__Check__'
require_relative 'Na__PointCloudViewer__McpOperations__Height__'

module Na__PointCloudViewer

    # -------------------------------------------------------------------------
    # REGION | Refusal Type
    # -------------------------------------------------------------------------

    # A refusal the MCP handler passes on with its fix.
    class Na__McpOperationsError < StandardError
        attr_reader :na_code, :na_hint, :na_details

        def initialize(code, message, hint = nil, details = nil)
            super(message)
            @na_code = code.to_s
            @na_hint = hint
            @na_details = details
        end
    end

    # endregion ----------------------------------------------------------------

    module Na__McpOperations

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_READ_ACTIONS     = %w[state count histogram image points density composite fit check heightmap profile].freeze
        NA_EDIT_ACTIONS     = %w[clip_box clip_on clip_off clip_scene view].freeze
        NA_FEATURES         = %w[frame].freeze   # what the MCP may ask for beyond the actions (0.14.6)
        NA_FRAMED_ACTIONS   = %w[count histogram image points density heightmap profile].freeze
        NA_MAX_BINS         = 10_000
        NA_DEFAULT_POINTS   = 1_000
        NA_MAX_INLINE_POINTS = 1_500
        NA_MAX_FILE_POINTS  = 5_000_000
        NA_PREVIEW_POINTS   = 10
        NA_DENSITY_CLIP     = 0.995
        NA_OVERLAY_RGB      = [230, 20, 20].freeze
        NA_MAX_OVERLAY_SEGMENTS = 200_000
        NA_FIT_SHAPES       = %w[plane line circle cylinder box].freeze
        NA_FIT_SAMPLE       = 20_000
        NA_FIT_MAX_SAMPLE   = 200_000
        NA_FIT_TOLERANCE_MM = 10.0
        NA_FIT_LOW_SHARE    = 0.3
        NA_FIT_SHORT_ARC_DEG = 60.0
        NA_CHECK_SAMPLE     = 20_000
        NA_CHECK_MAX_SAMPLE = 100_000
        NA_CHECK_TOLERANCE_MM = 10.0
        NA_CHECK_REACH_MM   = 50.0
        NA_CHECK_SPOT_MM    = 150.0
        NA_CHECK_GREEN      = [40, 160, 60].freeze
        NA_CHECK_RED        = [220, 30, 30].freeze
        NA_CHECK_BLUE       = [30, 70, 220].freeze
        NA_CHECK_AWAY       = [205, 205, 205].freeze
        NA_CHECK_EDGE       = [40, 40, 40].freeze
        NA_HEIGHT_STATS     = %w[p2 p50 p98].freeze
        NA_HEIGHT_SAMPLE    = 1_000_000      # about 2 s in SketchUp's Ruby (09-Nov-2026)
        NA_HEIGHT_MAX_SAMPLE = 5_000_000
        NA_HEIGHT_MAX_CELLS = 4_000_000
        NA_HEIGHT_MAX_INLINE = 2_500         # cells whose values come back in the reply
        NA_HEIGHT_PICTURE_SIDE = 900         # a small grid's picture is scaled up towards this
        NA_HEIGHT_MAX_SCALE = 8
        NA_HEIGHT_FEW       = 4              # median points a cell under this: a warning
        NA_HEIGHT_EDGE_RGB  = [230, 0, 230].freeze
        NA_HEIGHT_NO_COLOUR = [255.0, 255.0, 255.0].freeze
        NA_PROFILE_WIDTH_MM = 100.0
        NA_PROFILE_STEP_MM  = 50.0
        NA_PROFILE_SPAN_MM  = 1000.0         # the steepest stretch is measured over a metre
        NA_PROFILE_MAX_POINTS = 50
        NA_PROFILE_MAX_PIECES = 64
        NA_PROFILE_MIN_PIECE_SAMPLE = 10_000
        NA_PROFILE_MAX_STATIONS = 20_000
        NA_PROFILE_MAX_INLINE = 1_000
        NA_PROFILE_DRAWN    = 60_000
        NA_LINE_NAMES       = %w[red blue green purple orange teal grey black].freeze
        NA_FAR_INCHES       = 1.0e7
        NA_AXIS_NAMES       = %w[x y z].freeze
        NA_EDGE_INCHES      = 1e-6           # 0.14.5: a point this close outside a grid's edge counts in the edge cell
        NA_MAX_COMPOSITE_PIXELS = 12_000_000 # 0.14.5: the blend runs in Ruby, about 1.5 us a covered pixel
        NA_MAX_IMAGE_SIDE   = 4000
        NA_MAX_IMAGE_PIXELS = 8_000_000
        NA_MAX_GRID_LINES   = 400
        NA_MAX_PEAKS        = 30
        NA_PERCENTILES      = [1, 2, 5, 50, 95, 98, 99].freeze
        NA_DEFAULT_LABEL    = 'MCP Clip Box'.freeze
        NA_EYE_GAP_INCHES   = 12.0
        NA_GRID_MINOR_GREY  = 222
        NA_GRID_MAJOR_GREY  = 170

        # Parallel views along the model's axes, named by where they look (as
        # the skill's pc_kit.py): [screen right, screen up, into the screen].
        NA_VIEWS = {
            'top'   => [[1, 0, 0], [0, 1, 0], [0, 0, -1]],
            'front' => [[1, 0, 0], [0, 0, 1], [0, 1, 0]],
            'back'  => [[-1, 0, 0], [0, 0, 1], [0, -1, 0]],
            'left'  => [[0, -1, 0], [0, 0, 1], [1, 0, 0]],
            'right' => [[0, 1, 0], [0, 0, 1], [-1, 0, 0]]
        }.freeze

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Entry Points
    # -------------------------------------------------------------------------

        # Read-only: state, count, histogram, image. Returns a Hash with a 'summary'.
        def self.Na__PointCloudViewer__McpRead(action, params)
            params = {} unless params.is_a?(Hash)
            frame = nil
            if params['frame']
                unless NA_FRAMED_ACTIONS.include?(action.to_s)
                    self.na_refuse('invalid_params', "#{action} does not take a frame.", "A frame works with #{NA_FRAMED_ACTIONS.join(', ')}.")
                end
                frame = self.na_frame_in(params['frame'])
                params = params.merge('_frame' => frame)
                if params['overlay_segments'].is_a?(Array)
                    params['overlay_segments'] = params['overlay_segments'].map do |a, b|
                        a.is_a?(Array) && b.is_a?(Array) ? [Na__McpFrame.Na__Frame__ToFrame(frame, a), Na__McpFrame.Na__Frame__ToFrame(frame, b)] : [a, b]
                    end
                end
            end
            result = self.na_read(action, params)
            result['frame'] = self.na_frame_out(frame, params) if frame && result.is_a?(Hash)
            result
        end

        def self.na_read(action, params)
            case action.to_s
            when 'state'     then self.na_state(params)
            when 'count'     then self.na_count(params)
            when 'histogram' then self.na_histogram(params)
            when 'image'     then self.na_image(params)
            when 'points'    then self.na_points(params)
            when 'density'   then self.na_density(params)
            when 'composite' then self.na_composite(params)
            when 'fit'       then self.na_fit(params)
            when 'check'     then self.na_check(params)
            when 'heightmap' then self.na_heightmap(params)
            when 'profile'   then self.na_profile(params)
            else
                self.na_refuse('invalid_params', "Unknown point cloud read action '#{action}'.", "Use one of: #{NA_READ_ACTIONS.join(', ')}.")
            end
        end

        # Changes: clip_box, clip_on, clip_off, clip_scene (each ONE undo step of
        # the viewer's own) and view (view settings: no undo step).
        def self.Na__PointCloudViewer__McpEdit(action, params)
            params = {} unless params.is_a?(Hash)
            case action.to_s
            when 'clip_box'   then self.na_clip_box(params)
            when 'clip_on'    then self.na_clip_switch(params, true)
            when 'clip_off'   then self.na_clip_switch(params, false)
            when 'clip_scene' then self.na_clip_scene(params)
            when 'view'       then self.na_view(params)
            else
                self.na_refuse('invalid_params', "Unknown point cloud edit action '#{action}'.", "Use one of: #{NA_EDIT_ACTIONS.join(', ')}.")
            end
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | state
    # -------------------------------------------------------------------------

        def self.na_state(params)
            session = self.na_session
            all = Na__CloudSet.Na__Slots__All(session)
            slots = params['clouds'] ? self.na_named_slots(session, params['clouds']) : all
            active = Na__CloudSet.Na__Slots__Active(session)
            clouds = slots.map { |slot| self.na_cloud_state(slot, params) }
            summary = if all.empty?
                          'This model has no point cloud. Import one in the Point Cloud Viewer.'
                      else
                          clouds.map { |cloud| self.na_cloud_line(cloud, params) }.join(' ')
                      end
            {
                'viewer_version' => Na__PointCloudViewer.Na__PublicApi__Version,
                'overlay_on'     => Na__ModelRegistry.Na__Registry__IsVisible? ? true : false,
                'point_budget'   => session.settings['pointBudget'],
                'active_cloud'   => active ? active.id : nil,
                'clouds'         => clouds,
                'summary'        => summary
            }
        end

        def self.na_cloud_state(slot, params)
            Na__ClipBox.Na__Clip__Ensure(slot)
            cloud = slot.cloud
            link = slot.record ? slot.record['link'] : nil
            look = Na__RenderSettings.Na__Settings__MergeDisplay(slot.display || Na__RenderSettings.Na__Settings__DisplayPart(slot.session.settings), {})
            clip = slot.clip
            scene = clip && clip['enabled'] && slot.clip_active_scene ? slot.clip_scenes.find { |each| each['id'] == slot.clip_active_scene } : nil
            {
                'id'          => slot.id,
                'name'        => slot.name,
                'colour'      => Na__CloudSet.Na__Slots__HexColour(slot.colour),
                'shown'       => slot.visible ? true : false,
                'loaded'      => self.na_loaded?(slot),
                'points'      => cloud ? cloud.total_points : (link ? link['pointCount'] : nil),
                'file'        => link ? link['fileName'] : (cloud ? cloud.label : nil),
                'source_unit' => cloud ? cloud.source_unit : (link ? link['sourceUnit'] : nil),
                'cache'       => self.na_cache(link),
                'local_to_model' => cloud ? cloud.local_to_model : nil,
                'look'        => { 'point_size_px' => look['pointSizePx'], 'opacity_percent' => look['opacityPercent'],
                                   'colour_mode' => look['colourMode'] },
                'bounds'      => cloud && cloud.bounds ? self.na_box_out(cloud.bounds.min.to_a, cloud.bounds.max.to_a, params) : nil,
                'clip'        => clip ? { 'enabled' => clip['enabled'] ? true : false }.merge(self.na_box_out(clip['min'], clip['max'], params)) : nil,
                'clip_scene'  => scene ? { 'id' => scene['id'], 'name' => scene['name'], 'modified' => !Na__ClipBox.na_same_box?(scene, clip) } : nil,
                'clip_scenes' => slot.clip_scenes.map { |each| { 'id' => each['id'], 'name' => each['name'] }.merge(self.na_box_out(each['min'], each['max'], params)) }
            }
        end

        # The viewer's own point cache of the cloud's LAS (.napc v2, named by its
        # content key): for the skill's offline kit, which reads it with numpy.
        def self.na_cache(link)
            key = link ? link['contentKey'] : nil
            return nil unless key
            path = Na__PointCache.Na__Cache__PathForKey(key)
            { 'path' => path, 'exists' => File.exist?(path) }
        rescue ArgumentError
            nil
        end

        # "GeoSLAM Interior (pc_264338fa): shown, loaded, 37,512,004 points, clip on (scene Stair)."
        def self.na_cloud_line(cloud, _params)
            parts = [cloud['shown'] ? 'shown' : 'hidden', cloud['loaded'] ? 'loaded' : 'not loaded']
            parts << "#{self.na_thousands(cloud['points'])} points" if cloud['points']
            clip = cloud['clip']
            if clip && clip['enabled']
                parts << (cloud['clip_scene'] ? "clip on (scene #{cloud['clip_scene']['name']})" : 'clip on')
            else
                parts << (clip ? 'clip off' : 'no clip box')
            end
            "#{cloud['name']} (#{cloud['id']}): #{parts.join(', ')}."
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | count, histogram
    # -------------------------------------------------------------------------

        def self.na_count(params)
            slot = self.na_measured_slot(self.na_session, params)
            min, max = self.na_box_in(params)
            started = self.na_now
            points = self.na_count_in(slot, min, max)
            total = slot.cloud.total_points.to_i
            share = total > 0 ? (100.0 * points / total).round(3) : 0.0
            {
                'cloud'        => slot.id,
                'name'         => slot.name,
                'box'          => self.na_box_out(min, max, params),
                'points'       => points,
                'cloud_points' => total,
                'share_percent' => share,
                'ms'           => (self.na_now - started).round,
                'summary'      => "#{self.na_thousands(points)} points of #{slot.name} inside the box (#{share}% of #{self.na_thousands(total)})."
            }
        end

        def self.na_histogram(params)
            slot = self.na_measured_slot(self.na_session, params)
            min, max = self.na_box_in(params)
            axis = %w[x y z].index(params['axis'].to_s)
            self.na_refuse('invalid_params', "axis must be x, y or z, not '#{params['axis']}'.", 'Pass axis: "z" to find levels, "x" or "y" to find faces.') unless axis
            bin = self.na_positive(params, 'bin', 'bin')
            span = max[axis] - min[axis]
            count = [(span / bin - 1e-9).ceil, 1].max
            if count > NA_MAX_BINS
                self.na_refuse('invalid_params', "#{count} bins asked for; at most #{NA_MAX_BINS}.",
                               'Use a larger bin or a shorter box along the axis.')
            end
            started = self.na_now
            counts = self.na_histogram_counts(slot, min, max, axis, bin, count)
            elapsed = (self.na_now - started).round
            total = counts.sum
            share = params.key?('peak_share') ? params['peak_share'].to_f : 0.2
            self.na_refuse('invalid_params', 'peak_share must be from 0 to 1.', 'Pass e.g. 0.2: a peak must hold a fifth of the highest bin.') unless share >= 0 && share <= 1
            peaks = self.na_peaks(counts, min[axis], bin, share)
            label = %w[x y z][axis]
            {
                'cloud'       => slot.id,
                'name'        => slot.name,
                'axis'        => label,
                'box'         => self.na_box_out(min, max, params),
                'start'       => self.na_out_exact(min[axis], params),
                'bin'         => self.na_out_exact(bin, params),
                'counts'      => counts,
                'points'      => total,
                'peaks'       => peaks.map { |peak| { 'at' => self.na_out(peak[0], params), 'count' => peak[1], 'bin' => peak[2] } },
                'percentiles' => self.na_percentiles(counts, min[axis], bin, max[axis], total).transform_values { |value| value && self.na_out(value, params) },
                'ms'          => elapsed,
                'summary'     => "#{count} bins along #{label} from #{self.na_out(min[axis], params)}, #{self.na_thousands(total)} points; " \
                                 "#{peaks.length} peak(s)#{peaks.empty? ? '' : ' at ' + peaks.first(8).map { |peak| self.na_out(peak[0], params) }.join(', ')}" \
                                 "#{peaks.length > 8 ? ' ...' : ''}. #{elapsed} ms."
            }
        end

        # [[centre (inches), count, bin index]] for each local maximum holding at
        # least share x the highest bin, in order along the axis. The centre is
        # the count-weighted mean of the bin and its two neighbours.
        def self.na_peaks(counts, start, bin, share)
            top = counts.max.to_i
            return [] if top <= 0
            floor = share * top
            peaks = []
            counts.each_with_index do |value, index|
                next if value <= 0 || value < floor
                left = index > 0 ? counts[index - 1] : 0
                right = index < counts.length - 1 ? counts[index + 1] : 0
                next unless value >= left && value > right
                window = [index - 1, index, index + 1].select { |i| i >= 0 && i < counts.length }
                weight = window.sum { |i| counts[i] }.to_f
                centre = window.sum { |i| counts[i] * (start + (i + 0.5) * bin) } / weight
                peaks << [centre, value, index]
            end
            peaks.sort_by { |peak| -peak[1] }.first(NA_MAX_PEAKS).sort_by(&:first)
        end

        # { 'p1' => inches, ... } linear inside the bin where the share is reached.
        def self.na_percentiles(counts, start, bin, finish, total)
            NA_PERCENTILES.each_with_object({}) do |percent, result|
                if total <= 0
                    result["p#{percent}"] = nil
                    next
                end
                target = percent / 100.0 * total
                running = 0.0
                value = finish
                counts.each_with_index do |count, index|
                    if running + count >= target && count > 0
                        low = start + index * bin
                        high = [start + (index + 1) * bin, finish].min
                        value = low + (high - low) * ((target - running) / count)
                        break
                    end
                    running += count
                end
                result["p#{percent}"] = value
            end
        end

        # One pass on the engine's grid: one cell across (the whole box, along the
        # next axis), and down the histogram's axis from min one cell per bin plus
        # one. The box holds its own faces, so the extra cell can only hold points
        # exactly on the far face (when the box is a whole number of bins long);
        # they join the last bin, and the bins add up to what count gives. The
        # grid starts NA_EDGE_INCHES before the box (0.14.5): the engine sums a
        # point's grid position in another order than its box test, so a point
        # on a low face could come out a hair below the grid and be lost.
        def self.na_histogram_counts(slot, min, max, axis, bin, count)
            across = (axis + 1) % 3
            u = [0.0, 0.0, 0.0]
            v = [0.0, 0.0, 0.0]
            u[across] = 1.0
            v[axis] = -1.0
            width = (max[across] - min[across] + 2 * NA_EDGE_INCHES) * (1 + 1e-9)
            grid = u + v + [min[across] - NA_EDGE_INCHES, -(min[axis] - NA_EDGE_INCHES), width, bin, 1, count + 1]
            counts = self.na_grid_in(slot, min, max, grid)['counts'].unpack('V*')
            extra = counts.pop
            counts[-1] += extra
            counts
        end

        # Points per cell of a grid (Na__NativeEngine::NA_GRID_COUNT numbers) of
        # what the box keeps.
        def self.na_grid_in(slot, min, max, grid)
            block = [1.0, *min, *max, 0.0] + [0.0] * (Na__NativeEngine::NA_BOX_BLOCK_COUNT - 8)
            Na__NativeEngine.Na__Native__BoxGrid(slot.cloud.native_cloud, slot.cloud.local_to_model, block, grid)
        rescue Na__McpOperationsError
            raise
        rescue StandardError => error
            self.na_refuse('operation_failed', "The points of #{slot.name} could not be counted: #{error.message}",
                           'Reload the point cloud (point_cloud_view reload: true, or Reload in the viewer), then try again.')
        end

        def self.na_count_in(slot, min, max)
            block = [1.0, *min, *max, 0.0] + [0.0] * (Na__NativeEngine::NA_BOX_BLOCK_COUNT - 8)
            Na__NativeEngine.Na__Native__BoxCount(slot.cloud.native_cloud, slot.cloud.local_to_model, block)['kept'].to_i
        rescue Na__McpOperationsError
            raise
        rescue StandardError => error
            self.na_refuse('operation_failed', "The points of #{slot.name} could not be counted: #{error.message}",
                           'Reload the point cloud (point_cloud_view reload: true, or Reload in the viewer), then try again.')
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | image (the engine's renderer, parallel, along a model axis)
    # -------------------------------------------------------------------------

        def self.na_image(params)
            slot = self.na_measured_slot(self.na_session, params)
            min, max = self.na_box_in(params)
            view = params['view'].to_s
            self.na_refuse('invalid_params', "view must be one of #{NA_VIEWS.keys.join(', ')}, not '#{view}'.",
                           'right looks along -X (screen right = +Y), left along +X, front along +Y, back along -Y, top down.') unless NA_VIEWS.key?(view)
            pixel = self.na_positive(params, 'resolution', 'resolution')
            grid = params['grid'].to_f
            self.na_refuse('invalid_params', 'grid must be 0 (none) or a positive length.', 'Pass e.g. 100 (mm) for a line every 100 mm.') if grid < 0
            size = (params['point_size_px'] || 1).to_i
            self.na_refuse('invalid_params', 'point_size_px must be from 1 to 10.', 'Use 1 for measuring; 2 or 3 for a sparse slice.') unless size >= 1 && size <= 10
            out_path = params['out_path'].to_s
            self.na_refuse('invalid_params', 'out_path is required.', 'The MCP handler passes it.') if out_path.empty?

            frame = self.na_view_frame(view, min, max, pixel)
            xaxis, yaxis, zaxis = frame['axes']
            eye = frame['eye']
            cx0 = frame['cx0']
            cy1 = frame['cy1']
            width = frame['width']
            height = frame['height']

            cloud = slot.cloud
            colour = Na__ImageRenderer.Na__Image__ColourParams(slot, 'black')
            near = Na__ConfigLoader.Na__Config__GetOr(0.5, 'render', 'nativeImage', 'nearInches').to_f
            even = size.even? ? 0.5 : 0.0
            render = eye + xaxis + yaxis + zaxis +
                     [0, 2.0 / (width * pixel), 2.0 / (height * pixel), width, height, size, 1.0, 1, *colour[1, 3],
                      cloud.total_points.to_i, near] +
                     cloud.local_to_model + [1, *min, *max] +
                     [width, height, 0.5 * width + cx0 / pixel + even, 0.5 * height - cy1 / pixel + even]
            raw_path = "#{out_path}.native.png"
            started = self.na_now
            begin
                stats = Na__NativeEngine.Na__Native__RenderPng(cloud.native_cloud, render, raw_path)
                rows = self.na_read_rgba_rows(raw_path, width, height)
            rescue Na__McpOperationsError
                raise
            rescue StandardError => error
                self.na_refuse('operation_failed', "The point cloud image could not be drawn: #{error.message}",
                               'Reload the point cloud (point_cloud_view reload: true), or try a smaller image.')
            ensure
                File.delete(raw_path) if File.exist?(raw_path)
            end

            grey = rows.map { |row| self.na_grey_row(row) }
            result = self.na_picture(grey, frame, grid, out_path, slot, view, min, max, params)
            drawn = stats['pointsOnScreen'].to_i
            result['points_drawn'] = drawn
            result['ms'] = (self.na_now - started).round
            result['summary'] = "#{width} x #{height} px #{view} view of #{slot.name} inside the box, #{self.na_out(pixel, params)} per px, " \
                                "#{self.na_thousands(drawn)} points drawn. Black = a point (nearest wins): shape, not density; density shows how many."
            result
        end

        # The frame of a parallel view of the box: axes, eye, pixel-aligned
        # extents (screen x and y ARE signed model coordinates, because the eye
        # sits on the view axis only) and the image size, refused when too big.
        def self.na_view_frame(view, min, max, pixel, what = 'image')
            xaxis, yaxis, zaxis = NA_VIEWS[view]
            corners = [0, 1].product([0, 1], [0, 1]).map { |ix, iy, iz| [ix.zero? ? min[0] : max[0], iy.zero? ? min[1] : max[1], iz.zero? ? min[2] : max[2]] }
            depths = corners.map { |point| self.na_dot(zaxis, point) }
            cxs = corners.map { |point| self.na_dot(xaxis, point) }
            cys = corners.map { |point| self.na_dot(yaxis, point) }
            cx0 = (cxs.min / pixel + 1e-9).floor * pixel
            cx1 = (cxs.max / pixel - 1e-9).ceil * pixel
            cy0 = (cys.min / pixel + 1e-9).floor * pixel
            cy1 = (cys.max / pixel - 1e-9).ceil * pixel
            width = [((cx1 - cx0) / pixel).round, 1].max
            height = [((cy1 - cy0) / pixel).round, 1].max
            if width > NA_MAX_IMAGE_SIDE || height > NA_MAX_IMAGE_SIDE || width * height > NA_MAX_IMAGE_PIXELS
                if what == 'grid'
                    self.na_refuse('invalid_params', "The grid would be #{width} x #{height} cells; at most #{NA_MAX_IMAGE_SIDE} a side and #{NA_MAX_IMAGE_PIXELS / 1_000_000} M cells.",
                                   'Use a coarser resolution or a smaller box.')
                end
                self.na_refuse('invalid_params', "The image would be #{width} x #{height} px; at most #{NA_MAX_IMAGE_SIDE} px a side and #{NA_MAX_IMAGE_PIXELS / 1_000_000} MP.",
                               'Use a coarser resolution or a smaller box.')
            end
            {
                'axes' => [xaxis, yaxis, zaxis], 'eye' => zaxis.map { |value| value * (depths.min - NA_EYE_GAP_INCHES) },
                'cx0' => cx0, 'cx1' => cx1, 'cy0' => cy0, 'cy1' => cy1, 'pixel' => pixel, 'width' => width, 'height' => height
            }
        end

        # Writes the greyscale rows (with the grid) and returns what image and
        # density both report: the file, the size and the pixel-to-model mapping.
        def self.na_picture(grey, frame, grid, out_path, slot, view, min, max, params)
            xaxis, yaxis, = frame['axes']
            pixel = frame['pixel']
            width = frame['width']
            height = frame['height']
            u_index = xaxis.index { |value| value != 0 }
            v_index = yaxis.index { |value| value != 0 }
            u_sign = xaxis[u_index]
            v_sign = yaxis[v_index]
            u_left = frame['cx0'] * u_sign
            v_top = frame['cy1'] * v_sign
            note = nil
            if grid > 0
                lines = ((frame['cx1'] - frame['cx0']) / grid).ceil + ((frame['cy1'] - frame['cy0']) / grid).ceil
                if lines > NA_MAX_GRID_LINES
                    note = "No grid drawn: #{lines} lines would hide the points. Use a larger grid."
                else
                    self.na_draw_grid(grey, width, height, grid, u_left, u_sign * pixel, v_top, -v_sign * pixel)
                end
            end
            segments = params['overlay_segments']
            overlay = nil
            if segments.is_a?(Array) && !segments.empty?
                if segments.length > NA_MAX_OVERLAY_SEGMENTS
                    self.na_refuse('invalid_params', "#{self.na_thousands(segments.length)} edges to draw; at most #{self.na_thousands(NA_MAX_OVERLAY_SEGMENTS)}.",
                                   'Pass fewer or smaller groups in overlay_ids.')
                end
                clip = params['overlay_clip'] ? [min, max] : nil
                rgb = grey.map { |row| self.na_rgb_row(row) }
                drawn = self.na_draw_segments(rgb, frame, segments, clip)
                self.na_write_rgb_png(out_path, width, height, rgb)
                overlay = { 'edges' => segments.length, 'edges_drawn' => drawn, 'colour' => 'red', 'clipped_to_box' => clip ? true : false }
            else
                self.na_write_grey_png(out_path, width, height, grey)
            end
            axis_name = ->(index, sign) { "#{sign > 0 ? '+' : '-'}#{%w[x y z][index]}" }
            result = {
                'image_file'  => out_path,
                'mime_type'   => 'image/png',
                'cloud'       => slot.id,
                'name'        => slot.name,
                'view'        => view,
                'box'         => self.na_box_out(min, max, params),
                'width'       => width,
                'height'      => height,
                'resolution'  => self.na_out_exact(pixel, params),
                'u'           => { 'axis' => axis_name.call(u_index, u_sign), 'at_left_edge' => self.na_out_exact(u_left, params),
                                   'per_px' => self.na_out_exact(u_sign * pixel, params) },
                'v'           => { 'axis' => axis_name.call(v_index, v_sign), 'at_top_edge' => self.na_out_exact(v_top, params),
                                   'per_px' => self.na_out_exact(-v_sign * pixel, params) },
                'mapping'     => 'model value at a pixel centre = at_left_edge + (column + 0.5) * u.per_px, and at_top_edge + (row + 0.5) * v.per_px.',
                'grid'        => grid > 0 && note.nil? ? self.na_out(grid, params) : nil
            }
            result['note'] = note if note
            result['overlay'] = overlay if overlay
            result
        end

        # Model edges in red on a picture's RGB rows: each segment ([a, b], model
        # inches) projected along the view, clipped to the box first when clip
        # is [min, max]. Returns how many reached the picture.
        def self.na_draw_segments(rows, frame, segments, clip, colour = NA_OVERLAY_RGB)
            xaxis, yaxis, = frame['axes']
            pixel = frame['pixel']
            cx0 = frame['cx0']
            cy1 = frame['cy1']
            drawn = 0
            segments.each do |a, b|
                next unless a.is_a?(Array) && b.is_a?(Array) && a.length == 3 && b.length == 3
                a = a.map(&:to_f)
                b = b.map(&:to_f)
                if clip
                    piece = self.na_clip_segment(a, b, clip[0], clip[1])
                    next unless piece
                    a, b = piece
                end
                c0 = (self.na_dot(xaxis, a) - cx0) / pixel
                r0 = (cy1 - self.na_dot(yaxis, a)) / pixel
                c1 = (self.na_dot(xaxis, b) - cx0) / pixel
                r1 = (cy1 - self.na_dot(yaxis, b)) / pixel
                drawn += 1 if self.na_draw_line(rows, frame['width'], frame['height'], c0, r0, c1, r1, colour)
            end
            drawn
        end

        # The part of segment a-b inside the box lo..hi (Liang-Barsky), or nil.
        def self.na_clip_segment(a, b, lo, hi)
            t0 = 0.0
            t1 = 1.0
            d = (0..2).map { |i| b[i] - a[i] }
            3.times do |i|
                [[-d[i], a[i] - lo[i]], [d[i], hi[i] - a[i]]].each do |p, q|
                    if p.abs < 1e-12
                        return nil if q < 0
                        next
                    end
                    r = q / p
                    if p < 0
                        return nil if r > t1
                        t0 = r if r > t0
                    else
                        return nil if r < t0
                        t1 = r if r < t1
                    end
                end
            end
            [(0..2).map { |i| a[i] + t0 * d[i] }, (0..2).map { |i| a[i] + t1 * d[i] }]
        end

        # A one-pixel line from (c0, r0) to (c1, r1) (pixel coordinates, from the
        # top-left corner) on RGB rows, clipped to the picture. True when any of
        # it lands.
        # 0.14.5: a line lying on the right or bottom border (a box face on a
        # whole pixel) is drawn in the last column or row; it used to be clipped away.
        def self.na_draw_line(rows, width, height, c0, r0, c1, r1, colour = NA_OVERLAY_RGB)
            piece = self.na_clip_segment([c0, r0, 0.0], [c1, r1, 0.0], [-1e-6, -1e-6, -1.0], [width + 1e-6, height + 1e-6, 1.0])
            return false unless piece
            (c0, r0, _), (c1, r1, _) = piece
            steps = [(c1 - c0).abs, (r1 - r0).abs].max.ceil
            steps = 1 if steps < 1
            red, green, blue = colour
            (0..steps).each do |i|
                column = [[(c0 + (c1 - c0) * i / steps).floor, width - 1].min, 0].max
                row = [[(r0 + (r1 - r0) * i / steps).floor, height - 1].min, 0].max
                next if column < 0 || row < 0 || column >= width || row >= height
                line = rows[row]
                line.setbyte(3 * column, red)
                line.setbyte(3 * column + 1, green)
                line.setbyte(3 * column + 2, blue)
            end
            true
        end

        def self.na_rgb_row(grey)
            grey.unpack('C*').flat_map { |value| [value, value, value] }.pack('C*')
        end

        # An 8-bit RGB PNG (colour type 2, filter 0, deflated).
        def self.na_write_rgb_png(path, width, height, rows)
            raw = rows.map { |row| "\x00".b + row }.join
            chunk = lambda do |type, body|
                [body.bytesize].pack('N') + type + body + [Zlib.crc32(type + body)].pack('N')
            end
            header = [width, height, 8, 2, 0, 0, 0].pack('NNCCCCC')
            png = "\x89PNG\r\n\x1A\n".b + chunk.call('IHDR'.b, header) + chunk.call('IDAT'.b, Zlib::Deflate.deflate(raw)) + chunk.call('IEND'.b, ''.b)
            File.binwrite(path, png)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | composite (v0.14.1: the clouds on show over a SketchUp capture)
    # -------------------------------------------------------------------------

        # Draws every cloud on show (each with its own look, clip box and Crop
        # and Cut view, the session's point budget) for camera_object at width x
        # height with the engine, then over the capture at path, in place. The
        # image's own camera maths are the live overlay's (na_camera_params), so
        # the clouds sit on the model exactly as on screen. Dot sizes scale with
        # the image against the viewport. Nothing is drawn (and nothing refused)
        # when the overlay is off or no cloud is on show and loaded.
        def self.na_composite(params)
            session = self.na_session
            camera = params['camera_object']
            path = params['path'].to_s
            width = params['width'].to_i
            height = params['height'].to_i
            unless camera.is_a?(Sketchup::Camera) && File.exist?(path) && width > 0 && height > 0
                self.na_refuse('invalid_params', 'composite needs camera_object, an existing image path, width and height.', 'The MCP handler passes them.')
            end
            if width * height > NA_MAX_COMPOSITE_PIXELS
                self.na_refuse('invalid_params', "The capture is #{width} x #{height}; the clouds are drawn over captures up to #{NA_MAX_COMPOSITE_PIXELS / 1_000_000} MP.",
                               'Capture smaller (1600 x 1000 is plenty to see the cloud on the model).')
            end
            look = params['follow_scene'] ? self.na_follow_scene : nil
            unless Na__ModelRegistry.Na__Registry__IsVisible?
                return { 'composited' => false, 'note' => 'The point cloud overlay is off, so no cloud was drawn. Switch it on with point_cloud_view {overlay: true}.' }
            end
            begin
                layers = Na__ImageRenderer.na_layers(session)
            rescue StandardError => error
                self.na_refuse('operation_failed', "The point clouds could not be drawn: #{error.message}",
                               'Reload them (point_cloud_view reload: true, or Reload in the viewer), then capture again.')
            end
            return { 'composited' => false, 'note' => 'No point cloud is on show and loaded, so none was drawn.' } if layers.empty?

            view = Sketchup.active_model.active_view
            scale = width.to_f / [view.vpwidth.to_f, 1.0].max
            camera_part = Na__ImageRenderer.na_camera_params(camera, width.to_f, height.to_f)
            near = Na__ConfigLoader.Na__Config__GetOr(0.5, 'render', 'nativeImage', 'nearInches').to_f
            budget = Na__ImageRenderer.na_budget(session, 1.0)
            render = layers.map do |layer|
                slot = layer['slot']
                display = Na__ImageRenderer.na_display(slot)
                camera_part + [
                    width, height,
                    [display['pointSizePx'].to_f * scale, 1.0].max,
                    display['opacityPercent'].to_f / 100.0,
                    *Na__ImageRenderer.Na__Image__ColourParams(slot, display['colourMode']),
                    budget, near
                ] + (slot.cloud.local_to_model || Na__ImageRenderer::NA_IDENTITY_TRANSFORM) + Na__ClipBox.Na__Clip__RenderParams(slot) +
                    [width, height, 0, 0] + Na__CleanBoxes.Na__Boxes__RenderParams(slot)
            end
            raw_path = "#{path}.cloud.png"
            started = self.na_now
            begin
                stats = Na__NativeEngine.Na__Native__RenderLayersPng(layers.map { |layer| layer['pointer'] }, render, budget, raw_path)
                cloud_rows = self.na_read_rgba_rows(raw_path, width, height)
            rescue Na__McpOperationsError
                raise
            rescue StandardError => error
                self.na_refuse('operation_failed', "The point clouds could not be drawn: #{error.message}",
                               'Reload them (point_cloud_view reload: true), or capture a smaller image.')
            ensure
                File.delete(raw_path) if File.exist?(raw_path)
            end

            picture = Sketchup::ImageRep.new
            picture.load_file(path)
            unless picture.width == width && picture.height == height && [24, 32].include?(picture.bits_per_pixel)
                self.na_refuse('operation_failed', "The capture reads back as #{picture.width} x #{picture.height} at #{picture.bits_per_pixel} bits, not #{width} x #{height}.",
                               'Capture again without include_point_cloud.')
            end
            bytes = picture.bits_per_pixel / 8
            padding = picture.row_padding
            data = picture.data.dup.force_encoding(Encoding::BINARY)
            covered = self.na_blend(data, width * bytes + padding, bytes, cloud_rows, width, height)
            picture.set_data(width, height, picture.bits_per_pixel, padding, data)
            picture.save_file(path)
            {
                'composited'     => true,
                'clouds'         => layers.map { |layer| layer['slot'].id },
                'names'          => layers.map { |layer| layer['slot'].name },
                'points_drawn'   => stats['pointsOnScreen'].to_i,
                'point_budget'   => budget,
                'pixels_covered' => covered,
                'ms'             => (self.na_now - started).round
            }.merge(look ? { 'scene_look' => look.to_s } : {})
        end

        # The scene the capture just activated: its cloud look now, before the
        # clouds are drawn, not from the viewer's own timer 0.1 s after the
        # capture (0.14.5). Applying it twice changes nothing the second time.
        # Returns Na__Follow__Apply's answer, or nil when it does not apply.
        def self.na_follow_scene
            return nil unless defined?(Na__SceneFollow) && Na__SceneFollow.respond_to?(:Na__Follow__Apply)
            return nil unless Na__SceneFollow.Na__Follow__Enabled?
            model = Sketchup.active_model
            page = model && model.pages.selected_page
            return nil unless page
            Na__SceneFollow.Na__Follow__Apply(model, Na__SceneStore.Na__Scenes__PagePid(page))
        rescue StandardError
            nil
        end

        # The engine's RGBA rows over a picture's BGR(A) bytes: straight alpha,
        # each cloud pixel blended by its own opacity. A row the clouds miss is
        # skipped whole. Returns how many pixels a cloud covers.
        def self.na_blend(data, stride, bytes, cloud_rows, width, height)
            covered = 0
            height.times do |row|
                cloud = cloud_rows[row]
                next if cloud.count("\x00") == cloud.bytesize
                values = cloud.unpack('C*')
                base = row * stride
                width.times do |column|
                    alpha = values[4 * column + 3]
                    next if alpha.zero?
                    at = base + column * bytes
                    red = values[4 * column]
                    green = values[4 * column + 1]
                    blue = values[4 * column + 2]
                    if alpha == 255
                        data.setbyte(at, blue)
                        data.setbyte(at + 1, green)
                        data.setbyte(at + 2, red)
                        data.setbyte(at + 3, 255) if bytes == 4
                    elsif bytes == 4
                        # Over a transparent capture (0.14.5): the capture counts by its own
                        # alpha, so a cloud over nothing keeps its colour, not a tint of the
                        # hidden one.
                        under = data.getbyte(at + 3) * (255 - alpha) / 255.0
                        total = alpha + under
                        data.setbyte(at, ((blue * alpha + data.getbyte(at) * under) / total).round)
                        data.setbyte(at + 1, ((green * alpha + data.getbyte(at + 1) * under) / total).round)
                        data.setbyte(at + 2, ((red * alpha + data.getbyte(at + 2) * under) / total).round)
                        data.setbyte(at + 3, total.round)
                    else
                        rest = 255 - alpha
                        data.setbyte(at, (blue * alpha + data.getbyte(at) * rest) / 255)
                        data.setbyte(at + 1, (green * alpha + data.getbyte(at + 1) * rest) / 255)
                        data.setbyte(at + 2, (red * alpha + data.getbyte(at + 2) * rest) / 255)
                    end
                    covered += 1
                end
            end
            covered
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | fit (v0.14.2: a shape from the points in the box)
    # -------------------------------------------------------------------------

        # shape: plane (orientation any, horizontal, vertical), line, circle or
        # cylinder (axis, max_radius), box (axis, trim). tolerance (inches) is
        # how far a point may sit from the shape and still count. sample is how
        # many points napc_box_points hands over: the first that many the box
        # keeps, an even sample of it.
        def self.na_fit(params)
            slot = self.na_measured_slot(self.na_session, params)
            min, max = self.na_box_in(params)
            shape = params['shape'].to_s
            unless NA_FIT_SHAPES.include?(shape)
                self.na_refuse('invalid_params', "shape must be one of #{NA_FIT_SHAPES.join(', ')}, not '#{shape}'.",
                               'plane for a floor, tread, wall or riser; line for a rail or edge; circle or cylinder for a curve or a round post; box for a square post.')
            end
            tolerance = params.key?('tolerance') ? params['tolerance'].to_f : NA_FIT_TOLERANCE_MM / 25.4
            self.na_refuse('invalid_params', 'tolerance must be a positive length.', 'Pass e.g. 10 (mm): about the scan\'s noise.') unless tolerance > 0
            sample = (params['sample'] || NA_FIT_SAMPLE).to_i
            unless sample >= 100 && sample <= NA_FIT_MAX_SAMPLE
                self.na_refuse('invalid_params', "sample must be from 100 to #{self.na_thousands(NA_FIT_MAX_SAMPLE)}.", 'The default of 20,000 is plenty for any one surface.')
            end
            axis = (params['axis'] || 'z').to_s
            orientation = (params['orientation'] || 'any').to_s
            trim = (params['trim'] || 1.0).to_f
            self.na_refuse('invalid_params', "orientation must be any, horizontal or vertical, not '#{orientation}'.", 'horizontal for a floor or tread.') unless Na__McpFit::NA_ORIENTATIONS.include?(orientation)
            self.na_refuse('invalid_params', "axis must be x, y or z, not '#{axis}'.", 'z for a circle or post seen in plan.') unless Na__McpFit::NA_AXES.key?(axis)
            self.na_refuse('invalid_params', 'trim must be from 0 to 20 (percent each side).', 'The default 1 drops stray points.') unless trim >= 0 && trim <= 20
            u, v = Na__McpFit::NA_PLANE_AXES[Na__McpFit::NA_AXES[axis]]
            max_radius = params.key?('max_radius') ? params['max_radius'].to_f : [max[u] - min[u], max[v] - min[v]].max
            self.na_refuse('invalid_params', 'max_radius must be a positive length.', 'Pass a little more than the radius you expect.') unless max_radius > 0

            block = [1.0, *min, *max, 0.0] + [0.0] * (Na__NativeEngine::NA_BOX_BLOCK_COUNT - 8)
            started = self.na_now
            begin
                read = Na__NativeEngine.Na__Native__BoxPoints(slot.cloud.native_cloud, slot.cloud.local_to_model, block, sample, 1.0, false)
            rescue StandardError => error
                self.na_refuse('operation_failed', "The points of #{slot.name} could not be read: #{error.message}",
                               'Reload the point cloud (point_cloud_view reload: true), then try again.')
            end
            points = read['xyz'].unpack('E*').each_slice(3).to_a
            begin
                fit = case shape
                      when 'plane'    then Na__McpFit.Na__Fit__Plane(points, tolerance, orientation)
                      when 'line'     then Na__McpFit.Na__Fit__Line(points, tolerance)
                      when 'circle'   then Na__McpFit.Na__Fit__Circle(points, tolerance, axis, max_radius)
                      when 'cylinder' then Na__McpFit.Na__Fit__Circle(points, tolerance, axis, max_radius, true)
                      else Na__McpFit.Na__Fit__Box(points, axis, trim, tolerance)
                      end
            rescue ArgumentError => error
                hint = if %w[circle cylinder].include?(shape)
                           'Look at the box first (point_cloud_slice density) and tighten it round the curve. For a small round thing set tolerance ' \
                               "to the scan's noise (2 to 3 mm), and max_radius a little above the radius you expect."
                       else
                           'Look at the box first (point_cloud_slice density), then tighten it round one surface, or raise tolerance a little.'
                       end
                self.na_refuse('operation_failed', "No #{shape} could be fitted to the #{self.na_thousands(points.length)} points in the box: #{error.message}", hint)
            end
            used = points.length
            share = used > 0 ? fit['inliers'].to_f / used : 0.0
            warnings = []
            if shape != 'box' && share < NA_FIT_LOW_SHARE
                warnings << "Only #{(share * 100).round}% of the points fit the #{shape}: the box holds other things too. Tighten it round the one you mean."
            end
            if %w[circle cylinder].include?(shape) && (fit['radius'] > 0.9 * max_radius || fit['arc']['span_deg'] < NA_FIT_SHORT_ARC_DEG)
                # Measured on SK02's bullnose (09-Nov-2026): with the straight riser in the box the circle came out
                # 398 mm over 45 degrees; boxed to the curve alone, 166 mm over 96 degrees.
                warnings << "The circle covers #{fit['arc']['span_deg'].round} degrees at radius #{self.na_out(fit['radius'], params)}: " \
                            'a straight piece meeting the curve at a tangent may be pulling it bigger. End the box where the curve ends, ' \
                            'or set max_radius a little above the radius you expect.'
            end
            if fit['other_radius']
                warnings << "The points settle on more than one circle: radius #{self.na_out(fit['radius'], params)} from the best search, " \
                            "#{self.na_out(fit['other_radius'], params)} (centre #{fit['other_centre'].map { |x| self.na_out(x, params) }}) from all the points. " \
                            'The curve may not be one arc (a bullnose easing into its riser), or the box holds more than the curve: tighten the box round ' \
                            'the curve and compare tolerances (3, 5 and 10 mm).'
            end
            if %w[circle cylinder].include?(shape) && fit['radius'] < 2.0 * tolerance
                warnings << "The radius (#{self.na_out(fit['radius'], params)}) is under twice the tolerance (#{self.na_out(tolerance, params)}), so the tolerance " \
                            "cannot tell this circle from its centre: pass tolerance about the scan's noise (2 to 3 mm) and fit again."
            end
            out = self.na_fit_out(fit, params)
            {
                'cloud'          => slot.id,
                'name'           => slot.name,
                'shape'          => shape,
                'box'            => self.na_box_out(min, max, params),
                'points_in_box'  => read['kept'],
                'points_used'    => used,
                'tolerance'      => self.na_out(tolerance, params),
                'inlier_share'   => share.round(3),
                'fit'            => out,
                'warnings'       => warnings,
                'ms'             => (self.na_now - started).round,
                'summary'        => self.na_fit_line(shape, out, fit, used, params)
            }
        end

        # The fit with lengths in the call's units, directions as unit vectors
        # and angles in degrees, rounded.
        def self.na_fit_out(fit, params)
            lengths = %w[offset rms p95 radius diameter length from to width depth height other_radius]
            points = %w[point centre start end other_centre]
            fit.each_with_object({}) do |(key, value), out|
                out[key] = if lengths.include?(key)
                               self.na_out(value, params)
                           elsif points.include?(key)
                               value.map { |x| self.na_out(x, params) }
                           elsif key == 'corners'
                               value.map { |corner| corner.map { |x| self.na_out(x, params) } }
                           elsif %w[normal direction].include?(key)
                               value.map { |x| x.round(6) + 0.0 }
                           elsif key == 'in_plane'
                               { 'along' => value['along'].map { |x| x.round(6) + 0.0 }, 'across' => value['across'].map { |x| x.round(6) + 0.0 },
                                 'along_range' => value['along_range'].map { |x| self.na_out(x, params) },
                                 'across_range' => value['across_range'].map { |x| self.na_out(x, params) } }
                           elsif key == 'arc'
                               value.transform_values { |x| x.round(1) }
                           elsif key.end_with?('_deg')
                               value.round(2)
                           else
                               value
                           end
            end
        end

        def self.na_fit_line(shape, out, fit, used, params)
            of = "#{self.na_thousands(fit['inliers'])} of #{self.na_thousands(used)} points"
            case shape
            when 'plane'
                level = (fit['normal'][2].abs > 0.999999) ? ", level #{out['offset']}" : ''
                "Plane: normal #{out['normal'].map { |x| x.round(4) }}, through #{out['point']}#{level}, #{out['slope_deg']} deg from level, rms #{out['rms']} (95% within #{out['p95']}); #{of}."
            when 'line'
                "Line: #{out['slope_deg']} deg above level, azimuth #{out['azimuth_deg']} deg, from #{out['start']} to #{out['end']} (#{out['length']} long), rms #{out['rms']}; #{of}."
            when 'circle', 'cylinder'
                extra = shape == 'cylinder' ? ", #{out['from']} to #{out['to']} along #{out['axis']}" : ''
                "#{shape.capitalize} about #{out['axis']}: centre #{out['centre']}, radius #{out['radius']}, arc #{out['arc']['span_deg']} deg#{extra}, rms #{out['rms']}; #{of}."
            else
                "Box about #{out['axis']}: #{out['width']} x #{out['depth']}, turned #{out['rotation_deg']} deg, centre #{out['centre']}, #{out['from']} to #{out['to']} along #{out['axis']} " \
                    "(#{fit['trim_percent']}% trimmed each side), rms #{out['rms']} from the sides; #{of}."
            end
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | check (v0.14.3: how far the points sit from a model's faces)
    # -------------------------------------------------------------------------

        # triangles: [[a, b, c, outward normal, part], ...] (world inches) and
        # parts: [{ 'name', 'id' }] from the MCP handler. A point within reach of
        # a face is "near" and measured; farther ones are "away" (other things in
        # the box). Positive: the scan lies outside the face (the model is too
        # small, or sits inside the scan, there); negative: inside (the model is
        # proud). With view and resolution, a heatmap: near points green within
        # tolerance, red outside, blue inside, deeper towards reach; away points
        # pale grey; the model's edges dark over them.
        def self.na_check(params)
            slot = self.na_measured_slot(self.na_session, params)
            min, max = self.na_box_in(params)
            triangles = params['triangles']
            self.na_refuse('invalid_params', 'There are no faces to check against.', 'Pass groups, components or faces that hold faces.') unless triangles.is_a?(Array) && !triangles.empty?
            parts = Array(params['parts'])
            tolerance = params.key?('tolerance') ? params['tolerance'].to_f : NA_CHECK_TOLERANCE_MM / 25.4
            reach = params.key?('reach') ? params['reach'].to_f : NA_CHECK_REACH_MM / 25.4
            self.na_refuse('invalid_params', 'tolerance must be a positive length.', 'Pass e.g. 10 (mm): about the scan\'s noise.') unless tolerance > 0
            self.na_refuse('invalid_params', 'reach must be at least tolerance.', 'Pass e.g. 50 (mm): farther points belong to something else.') unless reach >= tolerance
            sample = (params['sample'] || NA_CHECK_SAMPLE).to_i
            unless sample >= 100 && sample <= NA_CHECK_MAX_SAMPLE
                self.na_refuse('invalid_params', "sample must be from 100 to #{self.na_thousands(NA_CHECK_MAX_SAMPLE)}.", 'The default of 20,000 gives steady numbers.')
            end
            frame = nil
            if params['view']
                view = params['view'].to_s
                self.na_refuse('invalid_params', "view must be one of #{NA_VIEWS.keys.join(', ')}, not '#{view}'.", 'right looks along -X, left along +X, front along +Y, back along -Y, top down.') unless NA_VIEWS.key?(view)
                self.na_refuse('invalid_params', 'out_path is required with view.', 'The MCP handler passes it.') if params['out_path'].to_s.empty?
                frame = self.na_view_frame(view, min, max, self.na_positive(params, 'resolution', 'resolution'))
            end

            started = self.na_now
            block = [1.0, *min, *max, 0.0] + [0.0] * (Na__NativeEngine::NA_BOX_BLOCK_COUNT - 8)
            begin
                read = Na__NativeEngine.Na__Native__BoxPoints(slot.cloud.native_cloud, slot.cloud.local_to_model, block, sample, 1.0, false)
            rescue StandardError => error
                self.na_refuse('operation_failed', "The points of #{slot.name} could not be read: #{error.message}",
                               'Reload the point cloud (point_cloud_view reload: true), then try again.')
            end
            points = read['xyz'].unpack('E*').each_slice(3).to_a
            if points.empty?
                self.na_refuse('operation_failed', "No points of #{slot.name} in the box round the model.",
                               'Check the cloud, and that the model sits where the scan is: point_cloud_slice count over the same box.')
            end
            begin
                index = Na__McpCheck.Na__Check__Index(triangles, reach)
            rescue ArgumentError => error
                self.na_refuse('invalid_params', error.message, 'Raise reach, or check a smaller part of the model.')
            end
            near = []
            signed = []
            owner = []
            nearest = Array.new(points.length)
            points.each_with_index do |point, i|
                found = Na__McpCheck.Na__Check__Nearest(index, point, i)
                next unless found
                nearest[i] = found[1]
                near << point
                signed << found[1]
                owner << index['triangles'][found[2]][4]
            end
            overall = Na__McpCheck.Na__Check__Summary(signed, tolerance)
            by_part = Hash.new { |hash, key| hash[key] = [] }
            owner.each_with_index { |part, i| by_part[part] << signed[i] }
            part_rows = by_part.map do |part, values|
                label = parts[part] || {}
                { 'name' => label['name'], 'id' => label['id'] }.merge(self.na_check_out(Na__McpCheck.Na__Check__Summary(values, tolerance), params))
            end.sort_by { |row| -(row['rms'] || 0) }
            silent = parts.each_index.reject { |part| by_part.key?(part) }.map { |part| parts[part]['name'] }
            spots = Na__McpCheck.Na__Check__Spots(near, signed, tolerance, [NA_CHECK_SPOT_MM / 25.4, 2.0 * reach].max, 5).map do |spot|
                { 'centre' => spot['centre'].map { |x| self.na_out(x, params) }, 'points' => spot['points'], 'mean' => self.na_out(spot['mean'], params) }
            end

            warnings = []
            if points.length > 0 && near.length < 0.1 * points.length
                warnings << "Only #{near.length} of #{points.length} points are within reach of the faces: is this the right cloud, and is the model where the scan is?"
            end
            if overall['points'].to_i > 0 && overall['mean'].abs > tolerance
                side = overall['mean'] > 0 ? 'outside' : 'inside'
                warnings << "On average the scan sits #{self.na_out(overall['mean'].abs, params)} #{side} the faces: the model may be offset as a whole."
            end
            warnings << "No points reached #{silent.first(5).join(', ')}#{silent.length > 5 ? ' ...' : ''}." unless silent.empty?

            result = {
                'cloud'         => slot.id,
                'name'          => slot.name,
                'box'           => self.na_box_out(min, max, params),
                'points_in_box' => read['kept'],
                'points_used'   => points.length,
                'near'          => near.length,
                'away'          => points.length - near.length,
                'tolerance'     => self.na_out(tolerance, params),
                'reach'         => self.na_out(reach, params),
                'faces'         => index['triangles'].length,
                'overall'       => self.na_check_out(overall, params),
                'parts'         => part_rows,
                'worst'         => spots,
                'sign'          => 'positive: the scan lies outside the faces (the model is too small there); negative: inside (the model is proud).',
                'warnings'      => warnings
            }
            if frame
                result.merge!(self.na_check_picture(frame, params, points, nearest, tolerance, reach, slot, min, max))
            end
            result['ms'] = (self.na_now - started).round
            within = overall['within'] ? (overall['within'] * 100).round(1) : 0
            result['summary'] = "#{self.na_thousands(near.length)} of #{self.na_thousands(points.length)} points within #{self.na_out(reach, params)} of #{index['triangles'].length} faces: " \
                                "rms #{self.na_out(overall['rms'].to_f, params)}, #{within}% within #{self.na_out(tolerance, params)}, mean #{self.na_out(overall['mean'].to_f, params)} " \
                                "(+ outside), 95% within #{self.na_out(overall['p95'].to_f, params)}." + (spots.empty? ? '' : " Worst spot: #{spots.first['points']} points round #{spots.first['centre']}.")
            result
        end

        def self.na_check_out(summary, params)
            out = { 'points' => summary['points'] }
            return out if summary['points'].to_i.zero?
            %w[rms mean p50 p95 max].each { |key| out[key] = self.na_out(summary[key], params) }
            out['within_share'] = summary['within'].round(3)
            out
        end

        # The heatmap: the sample in the slice's frame, coloured by distance.
        def self.na_check_picture(frame, params, points, nearest, tolerance, reach, slot, min, max)
            width = frame['width']
            height = frame['height']
            grey = Array.new(height) { ("\xFF" * width).b }
            grid = params['grid'].to_f
            if grid > 0
                lines = ((frame['cx1'] - frame['cx0']) / grid).ceil + ((frame['cy1'] - frame['cy0']) / grid).ceil
                if lines <= NA_MAX_GRID_LINES
                    xaxis, yaxis, = frame['axes']
                    u_index = xaxis.index { |value| value != 0 }
                    v_index = yaxis.index { |value| value != 0 }
                    self.na_draw_grid(grey, width, height, grid, frame['cx0'] * xaxis[u_index], xaxis[u_index] * frame['pixel'],
                                      frame['cy1'] * yaxis[v_index], -yaxis[v_index] * frame['pixel'])
                end
            end
            rows = grey.map { |row| self.na_rgb_row(row) }
            xaxis, yaxis, = frame['axes']
            dot = [(params['point_size_px'] || 2).to_i, 1].max
            order = points.each_index.sort_by { |i| nearest[i] ? nearest[i].abs : -1.0 }   # away first, worst last (on top)
            order.each do |i|
                point = points[i]
                column = ((self.na_dot(xaxis, point) - frame['cx0']) / frame['pixel']).floor
                row = ((frame['cy1'] - self.na_dot(yaxis, point)) / frame['pixel']).floor
                colour = self.na_check_colour(nearest[i], tolerance, reach)
                dot.times do |dy|
                    line = rows[row + dy]
                    next unless line && row + dy >= 0
                    dot.times do |dx|
                        c = column + dx
                        next if c < 0 || c >= width
                        line.setbyte(3 * c, colour[0])
                        line.setbyte(3 * c + 1, colour[1])
                        line.setbyte(3 * c + 2, colour[2])
                    end
                end
            end
            edges = params['edges']
            drawn = edges.is_a?(Array) && !edges.empty? ? self.na_draw_segments(rows, frame, edges, nil, NA_CHECK_EDGE) : 0
            self.na_write_rgb_png(params['out_path'], width, height, rows)
            picture = self.na_picture_mapping(frame, params)
            picture.merge('image_file' => params['out_path'], 'mime_type' => 'image/png', 'view' => params['view'], 'width' => width, 'height' => height,
                          'edges_drawn' => drawn,
                          'colours' => "green within #{self.na_out(tolerance, params)}; red outside, blue inside, deeper to #{self.na_out(reach, params)}; pale grey: away from the model; dark lines: the model's edges.")
        end

        def self.na_check_colour(distance, tolerance, reach)
            return NA_CHECK_AWAY if distance.nil?
            return NA_CHECK_GREEN if distance.abs <= tolerance
            share = [[(distance.abs - tolerance) / [reach - tolerance, 1e-9].max, 0.0].max, 1.0].min
            target = distance > 0 ? NA_CHECK_RED : NA_CHECK_BLUE
            light = distance > 0 ? [250, 170, 150] : [150, 180, 250]
            (0..2).map { |k| (light[k] + (target[k] - light[k]) * share).round }
        end

        # The u and v mapping of a frame, as image and density report it.
        def self.na_picture_mapping(frame, params)
            xaxis, yaxis, = frame['axes']
            pixel = frame['pixel']
            u_index = xaxis.index { |value| value != 0 }
            v_index = yaxis.index { |value| value != 0 }
            u_sign = xaxis[u_index]
            v_sign = yaxis[v_index]
            axis_name = ->(index, sign) { "#{sign > 0 ? '+' : '-'}#{%w[x y z][index]}" }
            {
                'resolution' => self.na_out_exact(pixel, params),
                'u' => { 'axis' => axis_name.call(u_index, u_sign), 'at_left_edge' => self.na_out_exact(frame['cx0'] * u_sign, params), 'per_px' => self.na_out_exact(u_sign * pixel, params) },
                'v' => { 'axis' => axis_name.call(v_index, v_sign), 'at_top_edge' => self.na_out_exact(frame['cy1'] * v_sign, params), 'per_px' => self.na_out_exact(-v_sign * pixel, params) },
                'mapping' => 'model value at a pixel centre = at_left_edge + (column + 0.5) * u.per_px, and at_top_edge + (row + 0.5) * v.per_px.'
            }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | heightmap and profile (v0.14.4: heights per cell, heights along a path)
    # -------------------------------------------------------------------------

        # Heights per cell of a grid seen along a model axis (top: z per x, y
        # cell): the statistics asked for (default p2, p50, p98), from an even
        # sample of the box (napc_box_points, default 1 M points), binned by
        # Na__McpHeight. A picture of one statistic (show): coloured low to high,
        # shaded, contoured, with the model's edges when overlay_segments come.
        # The values inline for small grids; a .npz (pc_terrain.py's rasters.npz
        # layout) or, from the top, an ESRI .asc grid in file_path.
        def self.na_heightmap(params)
            slot = self.na_measured_slot(self.na_session, params)
            min, max = self.na_box_in(params)
            view = self.na_height_view(params)
            cell = self.na_positive(params, 'resolution', 'resolution')
            specs, show = self.na_height_specs(params)
            sample = self.na_height_sample(params)
            contour = self.na_height_contour(params)
            colours = params['colours'] ? true : false
            out_path = params['out_path'].to_s
            self.na_refuse('invalid_params', 'out_path is required.', 'The MCP handler passes it.') if out_path.empty?
            file_path = self.na_height_file(params, %w[.npz .asc])
            if file_path && File.extname(file_path).casecmp?('.asc') && view != 'top'
                self.na_refuse('invalid_params', 'An .asc grid is a plan: it needs view top.', 'Save a side view as .npz instead.')
            end
            frame = self.na_view_frame(view, min, max, cell, 'grid')
            width = frame['width']
            height = frame['height']
            if width * height > NA_HEIGHT_MAX_CELLS
                self.na_refuse('invalid_params', "The grid would be #{width} x #{height} cells; at most #{self.na_thousands(NA_HEIGHT_MAX_CELLS)}.",
                               'Use a coarser resolution or a smaller box.')
            end

            started = self.na_now
            read = self.na_height_read(slot, min, max, sample, colours)
            grid = self.na_height_grid(frame)
            toward = grid['toward']   # +1 when a larger model value is nearer the viewer (top: higher z)
            cells, values = Na__McpHeight.Na__Height__GridCells(read['xyz'].unpack('E*'), grid)
            tints = colours ? read['bgra'].unpack('V*') : nil
            binned = Na__McpHeight.Na__Height__Bin(cells, values, width * height, specs, tints)
            cells = values = tints = nil
            shown = binned['stats'][show]
            filled = binned['count'].count(&:positive?)
            if filled.zero?
                self.na_refuse('operation_failed', "No points of #{slot.name} in the box.",
                               'Check the box with point_cloud_slice count or density, and that the cloud is the right one.')
            end
            # The values binned are nearness (toward x the model value): the picture uses them as they are.
            low = Na__McpHeight.Na__Height__Percentile(shown, 0.01)
            high = Na__McpHeight.Na__Height__Percentile(shown, 0.99)
            contour = self.na_auto_step((high - low) / 12.0, params) if contour.nil?
            scale = [[(NA_HEIGHT_PICTURE_SIDE / [width, height].max.to_f).floor, 1].max, NA_HEIGHT_MAX_SCALE].min
            rows = Na__McpHeight.Na__Height__Picture(shown, width, height, cell, scale, low, high, contour)
            picture = frame.merge('pixel' => cell / scale.to_f, 'width' => width * scale, 'height' => height * scale)
            overlay = self.na_height_overlay(rows, picture, params, min, max)
            self.na_write_rgb_png(out_path, width * scale, height * scale, rows)
            rows = nil

            axis = NA_AXIS_NAMES[grid['h']]
            per_cell = { 'columns' => width, 'rows' => height }.merge(self.na_height_mapping(frame, params))
            counts = binned['count'].select(&:positive?).sort
            median = counts[counts.length / 2]
            result = {
                'cloud'          => slot.id,
                'name'           => slot.name,
                'view'           => view,
                'value'          => "model #{axis}; a cell's values are ranked by nearness to the viewer, so max and p98 are the surface seen " \
                                    "(#{toward > 0 ? 'the largest' : 'the smallest'} #{axis}) and min and p2 the farthest",
                'box'            => self.na_box_out(min, max, params),
                'resolution'     => self.na_out_exact(cell, params),
                'points_in_box'  => read['kept'],
                'points_used'    => binned['binned'],
                'sample_percent' => read['kept'] > 0 ? (100.0 * read['written'] / read['kept']).round(3) : 0.0,
                'cells_with_points' => filled,
                'filled_share'   => (filled.to_f / (width * height)).round(3),
                'median_points_per_cell' => median,
                'stats'          => specs.to_h { |name, _| [name, self.na_height_range(binned['stats'][name], params, toward)] },
                'show'           => show,
                'slope'          => self.na_height_slope(Na__McpHeight.Na__Height__Plane(shown, width, height, cell), frame, view, params),
                'grid'           => per_cell,
                'rule'           => 'A percentile is the value at rank floor(q x (n - 1)) of the values in a cell sorted from the farthest to the nearest ' \
                                    'the viewer (from the top: lowest to highest); min = p0, max = p100; mean is the mean.',
                'image_file'     => out_path,
                'mime_type'      => 'image/png',
                'width'          => width * scale,
                'height'         => height * scale,
                'pixels_per_cell' => scale,
                'colour_range'   => { 'blue' => self.na_out(low * toward, params), 'red' => self.na_out(high * toward, params) },
                'contour'        => contour > 0 ? self.na_out_exact(contour, params) : nil,
                'colours'        => "#{show} from blue (#{toward > 0 ? 'low' : 'far'}) through green and yellow to red (#{toward > 0 ? 'high' : 'near'}), " \
                                    'shaded from the top left; white: no points; dark lines: contours, every fifth darker' \
                                    "#{overlay ? '; magenta: the model\'s edges' : ''}."
            }
            result['overlay'] = overlay if overlay
            if width * height <= NA_HEIGHT_MAX_INLINE
                result['values'] = Array.new(height) { |row| shown[row * width, width].map { |value| value && self.na_out(value * toward, params) } }
            end
            if file_path
                self.na_height_save_grid(file_path, frame, grid, view, binned, specs, show)
                result['file'] = file_path
                result['file_arrays'] = File.extname(file_path).casecmp?('.asc') ? "ESRI ASCII grid of #{show} in model mm, the north edge first, NODATA -9999." :
                                            self.na_height_npz_note(view, colours)
            end
            warnings = []
            if median < NA_HEIGHT_FEW
                warnings << "A filled cell holds #{median} points (median): too few for steady percentiles. Use a coarser resolution, or raise sample (up to #{self.na_thousands(NA_HEIGHT_MAX_SAMPLE)})."
            end
            warnings << "Only #{(100.0 * filled / (width * height)).round}% of the cells hold points: is the box round the scan?" if filled < 0.25 * width * height
            result['warnings'] = warnings
            result['ms'] = (self.na_now - started).round
            slope = result['slope']
            fall = if slope && slope['one_in'].nil?
                       " #{show} is level overall."
                   elsif slope && slope['falls_toward_azimuth_deg']
                       " #{show} falls #{self.na_slope_words(slope)} toward azimuth #{slope['falls_toward_azimuth_deg']} deg overall."
                   elsif slope
                       " #{show} leans #{slope['deg']} deg from the view's plane overall."
                   else
                       ''
                   end
            range = result['stats'][show]
            result['summary'] = "#{width} x #{height} cells of #{self.na_out_exact(cell, params)} (#{view} view, #{axis}) from #{self.na_thousands(binned['binned'])} of " \
                                "#{self.na_thousands(read['kept'])} points (#{result['sample_percent']}%); #{(100.0 * filled / (width * height)).round}% of cells hold points, " \
                                "median #{median} a cell. #{show} #{axis} from #{range['low']} to #{range['high']}.#{fall}"
            result
        end

        # Heights along a path (points in model inches; the view's axis is ignored,
        # so z does not matter from the top): every point within width / 2 of the
        # path, its value binned into stations step long by chainage. Pieces of
        # the path are read one box each (Na__Height__Pieces), so a diagonal
        # path keeps its own strip. A picture: the corridor's points grey, each
        # statistic a line; the numbers inline up to NA_PROFILE_MAX_INLINE stations.
        def self.na_profile(params)
            slot = self.na_measured_slot(self.na_session, params)
            view = self.na_height_view(params)
            path = Array(params['path'])
            unless path.length.between?(2, NA_PROFILE_MAX_POINTS) && path.all? { |point| point.is_a?(Array) && point.length == 3 }
                self.na_refuse('invalid_params', "path must be 2 to #{NA_PROFILE_MAX_POINTS} points, each [x, y, z].",
                               'From the top, z is ignored: e.g. [[14000, 12000, 0], [16000, 12000, 0]].')
            end
            path = path.map { |point| point.map(&:to_f) }
            width = params.key?('width') ? self.na_positive(params, 'width', 'width') : NA_PROFILE_WIDTH_MM / 25.4
            step = params.key?('step') ? self.na_positive(params, 'step', 'step') : NA_PROFILE_STEP_MM / 25.4
            specs, show = self.na_height_specs(params)
            sample = self.na_height_sample(params)
            exaggeration = params['exaggeration']
            unless exaggeration.nil? || (exaggeration.is_a?(Numeric) && exaggeration >= 0.1 && exaggeration <= 100)
                self.na_refuse('invalid_params', 'exaggeration must be from 0.1 to 100.', 'Leave it out to pick one that shows the falls.')
            end
            out_path = params['out_path'].to_s
            self.na_refuse('invalid_params', 'out_path is required.', 'The MCP handler passes it.') if out_path.empty?
            file_path = self.na_height_file(params, %w[.npz .csv])
            trim = params.key?('min') || params.key?('max') ? self.na_box_in(params) : nil

            xaxis, yaxis, zaxis = NA_VIEWS[view]
            h_index, h_sign = self.na_axis_of(zaxis)
            toward = -h_sign   # +1 when a larger model value is nearer the viewer (top: higher z)
            axes = { 'u' => self.na_axis_of(xaxis), 'v' => self.na_axis_of(yaxis), 'h' => h_index, 'toward' => toward }
            plane = path.map { |point| [self.na_dot(xaxis, point), self.na_dot(yaxis, point)] }
            begin
                pieces, length = Na__McpHeight.Na__Height__Pieces(plane, width, NA_PROFILE_MAX_PIECES)
            rescue ArgumentError => error
                self.na_refuse('invalid_params', error.message, 'Drop the repeated point, or move it along the path.')
            end
            count = [(length / step - 1e-9).ceil, 1].max   # 0.14.5: 33.000000000000004 steps are 33 stations
            if count > NA_PROFILE_MAX_STATIONS
                self.na_refuse('invalid_params', "#{self.na_thousands(count)} stations; at most #{self.na_thousands(NA_PROFILE_MAX_STATIONS)}.", 'Use a longer step or a shorter path.')
            end

            started = self.na_now
            # One sampling rate for every piece (0.14.5): count each piece's box first,
            # then read the same share of each, so a station on a join between two
            # pieces does not mix two rates.
            boxes = pieces.map do |piece|
                low = Array.new(3, -NA_FAR_INCHES)
                high = Array.new(3, NA_FAR_INCHES)
                [[axes['u'], 0], [axes['v'], 1]].each do |(index, sign), k|
                    ends = [sign * piece['low'][k], sign * piece['high'][k]]
                    low[index] = ends.min
                    high[index] = ends.max
                end
                if trim
                    low = low.each_with_index.map { |value, i| [value, trim[0][i]].max }
                    high = high.each_with_index.map { |value, i| [value, trim[1][i]].min }
                end
                (0..2).all? { |i| high[i] > low[i] } ? [low, high] : nil
            end
            in_boxes = boxes.map { |box| box ? self.na_count_in(slot, box[0], box[1]) : 0 }
            kept = in_boxes.sum
            rate = kept > sample ? sample.to_f / kept : 1.0
            stations = []
            values = []
            chainages = []
            read_total = 0
            pieces.each_with_index do |piece, n|
                next unless boxes[n] && in_boxes[n] > 0
                low, high = boxes[n]
                read = self.na_height_read(slot, low, high, [(in_boxes[n] * rate).ceil, in_boxes[n]].min, false)
                read_total += read['written']
                s, v, c = Na__McpHeight.Na__Height__Stations(read['xyz'].unpack('E*'), axes, piece, 0.5 * width, step, count)
                stations.concat(s)
                values.concat(v)
                chainages.concat(c)
            end
            binned = Na__McpHeight.Na__Height__Bin(stations, values, count, specs)
            filled = binned['count'].count(&:positive?)
            if filled.zero?
                self.na_refuse('operation_failed', "No points of #{slot.name} within #{self.na_out(0.5 * width, params)} of the path.",
                               'Check the path is on the scan (point_cloud_heightmap or point_cloud_slice density from the top), or widen the corridor.')
            end
            centres = Array.new(count) { |k| 0.5 * (k * step + [(k + 1) * step, length].min) }
            # Binned as nearness (the chart puts nearer the viewer up); reported as model values.
            shown = binned['stats'][show].map { |value| value && value * toward }

            all = specs.flat_map { |name, _| binned['stats'][name].compact }
            frame = Na__McpHeight.Na__Height__ProfileFrame(length, all.min, all.max, exaggeration)
            used = []
            stride = [(binned['binned'] / NA_PROFILE_DRAWN.to_f).ceil, 1].max
            seen = 0
            stations.each_with_index do |station, i|
                next if station < 0
                used << [chainages[i], values[i]] if (seen % stride).zero?
                seen += 1
            end
            stations = values = chainages = nil
            order = [show] + specs.map(&:first).reject { |name| name == show }
            lines = order.each_with_index.map { |name, i| [Na__McpHeight::NA_LINE_RGBS[i], centres.zip(binned['stats'][name])] }
            grid_x = self.na_auto_step(length / 10.0, params)
            grid_y = self.na_auto_step((frame['high'] - frame['low']) / 6.0, params)
            rows = Na__McpHeight.Na__Height__ProfilePicture(frame, used, lines, grid_x, grid_y)
            self.na_write_rgb_png(out_path, frame['width'], frame['height'], rows)
            rows = nil

            places = centres.map { |chainage| self.na_path_at(plane, chainage) }
            in_plane = [axes['u'], axes['v']].sort_by(&:first)
            names = in_plane.map { |index, _| NA_AXIS_NAMES[index] }
            coordinate = lambda do |place, (index, sign)|
                sign * place[index == axes['u'][0] ? 0 : 1]
            end
            prefix = view == 'top' ? 'z' : 'h'
            columns = ['chainage', *names, 'count'] + specs.map(&:first)
            line = Na__McpHeight.Na__Height__Line(centres, shown)
            steep = length >= NA_PROFILE_SPAN_MM / 25.4 ? Na__McpHeight.Na__Height__Steepest(centres, shown, NA_PROFILE_SPAN_MM / 25.4) : nil
            first = shown.index { |value| !value.nil? }
            last = shown.rindex { |value| !value.nil? }
            axis = NA_AXIS_NAMES[axes['h']]
            result = {
                'cloud'          => slot.id,
                'name'           => slot.name,
                'view'           => view,
                'value'          => "model #{axis}; a station's values are ranked by nearness to the viewer (max and p98 the nearest), and the chart puts nearer up",
                'path'           => path.map { |point| point.map { |x| self.na_out_exact(x, params) } },
                'length'         => self.na_out(length, params),
                'corridor_width' => self.na_out_exact(width, params),
                'step'           => self.na_out_exact(step, params),
                'stations'       => count,
                'stations_with_points' => filled,
                'pieces'         => pieces.length,
                'points_in_boxes' => kept,
                'points_read'    => read_total,
                'sample_percent' => (100.0 * rate).round(3),
                'points_used'    => binned['binned'],
                'show'           => show,
                'along'          => {
                    'start' => self.na_out(shown[first], params), 'end' => self.na_out(shown[last], params),
                    'rise' => self.na_out(shown[last] - shown[first], params),
                    'from' => self.na_out(centres[first], params), 'to' => self.na_out(centres[last], params)
                },
                'rule'           => 'A percentile is the value at rank floor(q x (n - 1)) of the values at a station sorted from the farthest to the nearest ' \
                                    'the viewer (from the top: lowest to highest); min = p0, max = p100; mean is the mean.'
            }
            result['line'] = self.na_profile_slope(line['slope'], params).merge('rms' => self.na_out(line['rms'], params)) if line
            if steep
                result['steepest'] = self.na_profile_slope(steep['slope'], params).merge('from' => self.na_out(steep['from'], params), 'to' => self.na_out(steep['to'], params),
                                                                                         'over' => self.na_out(NA_PROFILE_SPAN_MM / 25.4, params))
            end
            if count <= NA_PROFILE_MAX_INLINE
                result['columns'] = columns
                result['table'] = Array.new(count) do |k|
                    [self.na_out(centres[k], params), *in_plane.map { |pair| self.na_out(coordinate.call(places[k], pair), params) }, binned['count'][k]] +
                        specs.map { |name, _| (value = binned['stats'][name][k]) && self.na_out(value * toward, params) }
                end
            end
            legend = order.each_with_index.map { |name, i| "#{name} #{NA_LINE_NAMES[i]}" }.join(', ')
            result.merge!(
                'image_file'   => out_path,
                'mime_type'    => 'image/png',
                'width'        => frame['width'],
                'height'       => frame['height'],
                'exaggeration' => frame['exaggeration'],
                'mapping'      => {
                    'chainage_per_px' => self.na_out_exact(1.0 / frame['per_unit'], params),
                    'value_at_top'    => self.na_out_exact(frame['high'] * toward, params),
                    'value_per_px'    => self.na_out_exact(toward / (frame['per_unit'] * frame['exaggeration']), params),
                    'rule'            => "chainage = (column + 0.5 - #{frame['left']}) x chainage_per_px; value = value_at_top - (row + 0.5 - #{frame['top']}) x value_per_px."
                },
                'grid_lines'   => { 'along' => self.na_out_exact(grid_x, params), 'up' => self.na_out_exact(grid_y, params) },
                'colours'      => "#{legend}; grey dots: the corridor's points (#{stride == 1 ? 'all' : "1 in #{stride}"}); light lines: the grid."
            )
            if file_path
                self.na_profile_save(file_path, centres, places, in_plane, axes, binned, specs, prefix, names, coordinate, toward)
                result['file'] = file_path
                result['file_columns'] = "chainage, #{names.join(', ')}, count, #{specs.map { |name, _| Na__McpHeight.Na__Height__FileName(name, prefix) }.join(', ')}: model mm, empty where a station holds no points."
            end
            counts = binned['count'].select(&:positive?).sort
            median = counts[counts.length / 2]
            warnings = []
            warnings << "#{count - filled} of #{count} stations hold no points: gaps in the scan, or the path leaves it." if filled < count
            warnings << "A filled station holds #{median} points (median): widen the corridor or lengthen the step." if median < NA_HEIGHT_FEW
            if rate < 1.0
                warnings << "The pieces' boxes hold #{self.na_thousands(kept)} points (where pieces meet, their boxes overlap); #{(100.0 * rate).round(1)}% of each " \
                            "was read, an even sample; raise sample for more."
            end
            result['warnings'] = warnings
            result['ms'] = (self.na_now - started).round
            slope = result['line'] ? ", #{self.na_slope_words(result['line'])} by least squares" : ''
            steepest = result['steepest'] ? "; steepest #{self.na_slope_words(result['steepest'])} over #{result['steepest']['over']} (chainage #{result['steepest']['from']} to #{result['steepest']['to']})" : ''
            result['summary'] = "Profile #{result['length']} long (#{view} view, #{axis}), #{count} stations of #{result['step']} in a #{result['corridor_width']} corridor, " \
                                "#{self.na_thousands(binned['binned'])} points: #{show} from #{result['along']['start']} to #{result['along']['end']} " \
                                "(#{result['along']['rise']} over #{(result['along']['to'] - result['along']['from']).round(1)})#{slope}#{steepest}."
            result
        end

        # --- Shared by heightmap and profile -------------------------------------

        def self.na_height_view(params)
            view = (params['view'] || 'top').to_s
            return view if NA_VIEWS.key?(view)
            self.na_refuse('invalid_params', "view must be one of #{NA_VIEWS.keys.join(', ')}, not '#{view}'.",
                           'top for ground, roofs and falls; front, back, left or right for how flat a wall is.')
        end

        # [specs, show]: the statistics (default NA_HEIGHT_STATS) and the one the
        # picture shows (p50 when asked for, else the first).
        def self.na_height_specs(params)
            raw = params.key?('stats') ? Array(params['stats']) : NA_HEIGHT_STATS
            begin
                specs = Na__McpHeight.Na__Height__Specs(raw)
                names = specs.map(&:first)
                show = params['show'] ? Na__McpHeight.Na__Height__Specs([params['show']]).first.first : (names.include?('p50') ? 'p50' : names.first)
            rescue ArgumentError => error
                self.na_refuse('invalid_params', error.message, 'p2 for the ground under grass, p50 for a hard surface, p98 for tops (walls, kerbs, rails).')
            end
            self.na_refuse('invalid_params', "show must be one of stats (#{names.join(', ')}), not #{params['show']}.", 'Add it to stats.') unless names.include?(show)
            [specs, show]
        end

        def self.na_height_sample(params)
            sample = (params['sample'] || NA_HEIGHT_SAMPLE).to_i
            return sample if sample >= 1_000 && sample <= NA_HEIGHT_MAX_SAMPLE
            self.na_refuse('invalid_params', "sample must be from 1,000 to #{self.na_thousands(NA_HEIGHT_MAX_SAMPLE)}.",
                           'The default 1,000,000 takes about 2 s; 5,000,000 about 10 s.')
        end

        # nil: pick one (about twelve lines over the colours); 0: none.
        def self.na_height_contour(params)
            return nil unless params.key?('contour')
            contour = params['contour'].to_f
            return contour if contour >= 0
            self.na_refuse('invalid_params', 'contour must be 0 (none) or a positive length.', 'Pass e.g. 50 (mm), or leave it out to pick one.')
        end

        # file_path, its extension one of allowed, or nil.
        def self.na_height_file(params, allowed)
            path = params['file_path'].to_s
            return nil if path.empty?
            return path if allowed.any? { |ext| File.extname(path).casecmp?(ext) }
            self.na_refuse('invalid_params', "save_path must end #{allowed.join(' or ')}, not #{File.extname(path)}.", 'The MCP handler checks it.')
        end

        def self.na_height_read(slot, min, max, cap, colours)
            block = [1.0, *min, *max, 0.0] + [0.0] * (Na__NativeEngine::NA_BOX_BLOCK_COUNT - 8)
            Na__NativeEngine.Na__Native__BoxPoints(slot.cloud.native_cloud, slot.cloud.local_to_model, block, cap, 1.0, colours)
        rescue StandardError => error
            self.na_refuse('operation_failed', "The points of #{slot.name} could not be read: #{error.message}",
                           'Reload the point cloud (point_cloud_view reload: true), then try again.')
        end

        # [axis index, sign] of a view axis (one of its numbers is not 0).
        def self.na_axis_of(axis)
            index = axis.index { |value| value != 0 }
            [index, axis[index]]
        end

        # A view frame as Na__Height__GridCells reads it; 'toward' is +1 when a
        # larger model value is nearer the viewer (the eye looks along zaxis).
        def self.na_height_grid(frame)
            xaxis, yaxis, zaxis = frame['axes']
            h_index, h_sign = self.na_axis_of(zaxis)
            { 'u' => self.na_axis_of(xaxis), 'v' => self.na_axis_of(yaxis), 'h' => h_index, 'toward' => -h_sign,
              'left' => frame['cx0'], 'top' => frame['cy1'], 'cell' => frame['pixel'], 'width' => frame['width'], 'height' => frame['height'] }
        end

        def self.na_height_mapping(frame, params)
            mapping = self.na_picture_mapping(frame, params)
            {
                'u' => { 'axis' => mapping['u']['axis'], 'at_left_edge' => mapping['u']['at_left_edge'], 'per_cell' => mapping['u']['per_px'] },
                'v' => { 'axis' => mapping['v']['axis'], 'at_top_edge' => mapping['v']['at_top_edge'], 'per_cell' => mapping['v']['per_px'] },
                'rule' => 'model value at a cell centre = at_left_edge + (column + 0.5) x u.per_cell, and at_top_edge + (row + 0.5) x v.per_cell; ' \
                          'in the image, divide per_cell by pixels_per_cell.'
            }
        end

        # { 'low', 'high', 'mean' } of a statistic over the cells that hold one,
        # as model values (the cells hold nearness: toward x the model value).
        def self.na_height_range(values, params, toward = 1)
            kept = values.compact.map { |value| value * toward }
            return { 'low' => nil, 'high' => nil, 'mean' => nil } if kept.empty?
            { 'low' => self.na_out(kept.min, params), 'high' => self.na_out(kept.max, params), 'mean' => self.na_out(kept.sum / kept.length, params) }
        end

        # The best plane's slope as percent, 1 in N and degrees, the way it
        # falls (a model direction) and, from the top, its azimuth (degrees
        # anticlockwise from +x, as point_cloud_fit gives them).
        def self.na_height_slope(plane, frame, view, params)
            return nil unless plane
            xaxis, yaxis, = frame['axes']
            rise = (0..2).map { |k| plane['a'] * xaxis[k] + plane['b'] * yaxis[k] }
            size = Math.sqrt(rise.sum { |x| x * x })
            out = self.na_profile_slope(size, params).merge('deg' => (Math.atan(size) * 180.0 / Math::PI).round(2), 'rms' => self.na_out(plane['rms'], params))
            if size > 1e-12
                falls = rise.map { |x| -x / size }
                out['falls_toward'] = falls.map { |x| x.round(4) + 0.0 }
                out['falls_toward_azimuth_deg'] = (Math.atan2(falls[1], falls[0]) * 180.0 / Math::PI).round(1) if view == 'top'
            end
            out
        end

        def self.na_profile_slope(slope, _params)
            {
                'percent' => (100.0 * slope).round(2),
                'one_in'  => slope.abs > 1e-9 ? (1.0 / slope.abs).round(1) : nil
            }
        end

        # A nice step (1, 2 or 5 x a power of ten) in the call's units, back in inches.
        def self.na_auto_step(inches, params)
            per_inch = (params['per_inch'] || 25.4).to_f
            return 0.0 unless inches > 0
            Na__McpHeight.Na__Height__Nice(inches * per_inch) / per_inch
        end

        # The model's edges over the heightmap in magenta (overlay_segments, as slices take them).
        def self.na_height_overlay(rows, picture, params, min, max)
            segments = params['overlay_segments']
            return nil unless segments.is_a?(Array) && !segments.empty?
            if segments.length > NA_MAX_OVERLAY_SEGMENTS
                self.na_refuse('invalid_params', "#{self.na_thousands(segments.length)} edges to draw; at most #{self.na_thousands(NA_MAX_OVERLAY_SEGMENTS)}.",
                               'Pass fewer or smaller groups in overlay_ids.')
            end
            clip = params['overlay_clip'] ? [min, max] : nil
            drawn = self.na_draw_segments(rows, picture, segments, clip, NA_HEIGHT_EDGE_RGB)
            { 'edges' => segments.length, 'edges_drawn' => drawn, 'colour' => 'magenta', 'clipped_to_box' => clip ? true : false }
        end

        # The [u, v] on a path (points [u, v]) at a chainage along it.
        def self.na_path_at(path, chainage)
            gone = 0.0
            path.each_cons(2) do |a, b|
                length = Math.sqrt((b[0] - a[0])**2 + (b[1] - a[1])**2)
                if chainage <= gone + length
                    t = length > 0 ? (chainage - gone) / length : 0.0
                    return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]
                end
                gone += length
            end
            path.last
        end

        # The grid to a .npz in pc_terrain.py's rasters.npz layout (model mm,
        # float32, NaN where empty; count int32; rows from the top), or to an ESRI
        # ASCII grid of show (from the top only).
        def self.na_height_save_grid(path, frame, grid, view, binned, specs, show)
            mm = 25.4
            width = frame['width']
            height = frame['height']
            cell = frame['pixel']
            u_index, u_sign = grid['u']
            v_index, v_sign = grid['v']
            u0 = frame['cx0'] * u_sign
            v1 = frame['cy1'] * v_sign
            toward = grid['toward'] || 1
            if File.extname(path).casecmp?('.asc')
                File.open(path, 'w') do |file|
                    file.write("ncols #{width}\nnrows #{height}\nxllcorner #{(u0 * mm).round(3)}\nyllcorner #{((v1 - height * cell) * mm).round(3)}\n" \
                               "cellsize #{(cell * mm).round(3)}\nNODATA_value -9999\n")
                    values = binned['stats'][show]
                    height.times do |row|
                        file.write(values[row * width, width].map { |value| value ? (value * toward * mm).round(1) : -9999 }.join(' ') << "\n")
                    end
                end
                return path
            end
            prefix = view == 'top' ? 'z' : 'h'
            scalar = ->(name, value) { [name, '<f8', [], [value].pack('E')] }
            arrays = [scalar.call('res', cell * mm), ['W', '<i8', [], [width].pack('q<')], ['H', '<i8', [], [height].pack('q<')]]
            arrays += [scalar.call('x0', u0 * mm), scalar.call('y1', v1 * mm)] if view == 'top'
            arrays += [scalar.call('u0', u0 * mm), scalar.call('du', u_sign * cell * mm), scalar.call('v1', v1 * mm), scalar.call('dv', -v_sign * cell * mm),
                       ['axes', '<i4', [3], [u_index, v_index, grid['h']].pack('l<3')],
                       ['count', '<i4', [height, width], binned['count'].pack('l<*')]]
            specs.each do |name, _|
                data = binned['stats'][name].map { |value| value ? value * toward * mm : Float::NAN }.pack('e*')
                arrays << [Na__McpHeight.Na__Height__FileName(name, prefix), '<f4', [height, width], data]
            end
            %w[rgb_top rgb_low].each do |name|
                next unless binned[name]
                data = binned[name].flat_map { |rgb| rgb || NA_HEIGHT_NO_COLOUR }.pack('e*')
                arrays << [name, '<f4', [height, width, 3], data]
            end
            self.na_write_npz(path, arrays)
        end

        def self.na_height_npz_note(view, colours)
            names = view == 'top' ? 'x0, y1 (the north-west corner), ' : ''
            "res, W, H, #{names}u0, du, v1, dv, axes: the grid (model mm; a cell centre is u0 + (c + 0.5) du, v1 + (r + 0.5) dv); " \
                "count (int32, H x W); one float32 H x W array a statistic (#{view == 'top' ? 'z02, z50, z98' : 'h02, h50, h98'} ...), model mm, NaN where empty" \
                "#{colours ? '; rgb_top and rgb_low (float32 H x W x 3: the mean colour of the highest tenth and the lowest quarter, 255 where empty)' : ''}. " \
                "#{view == 'top' ? 'The layout of pc_terrain.py\'s rasters.npz.' : ''}".strip
        end

        # A profile's stations to .csv or .npz, model mm.
        def self.na_profile_save(path, centres, places, in_plane, axes, binned, specs, prefix, names, coordinate, toward = 1)
            mm = 25.4
            stats = specs.map { |name, _| [Na__McpHeight.Na__Height__FileName(name, prefix), binned['stats'][name].map { |value| value && value * toward }] }
            if File.extname(path).casecmp?('.csv')
                File.open(path, 'w') do |file|
                    file.write((['chainage', *names, 'count'] + stats.map(&:first)).join(',') << "\n")
                    centres.each_index do |k|
                        row = [(centres[k] * mm).round(1), *in_plane.map { |pair| (coordinate.call(places[k], pair) * mm).round(1) }, binned['count'][k]] +
                              stats.map { |_, values| values[k] ? (values[k] * mm).round(1) : '' }
                        file.write(row.join(',') << "\n")
                    end
                end
                return path
            end
            arrays = [['chainage', '<f8', [centres.length], centres.map { |x| x * mm }.pack('E*')]]
            in_plane.each_with_index do |pair, i|
                arrays << [names[i], '<f8', [centres.length], places.map { |place| coordinate.call(place, pair) * mm }.pack('E*')]
            end
            arrays << ['count', '<i4', [centres.length], binned['count'].pack('l<*')]
            stats.each { |name, values| arrays << [name, '<f4', [centres.length], values.map { |x| x ? x * mm : Float::NAN }.pack('e*')] }
            self.na_write_npz(path, arrays)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | density (v0.14.0: points per pixel, the engine's grid)
    # -------------------------------------------------------------------------

        # The same frame, grid and mapping as image, but every pixel counts the
        # points in the box behind it: grey = 1 - log(1 + n) / log(1 + top), top
        # the 99.5th percentile of the pixels that hold any point (linear: n / top).
        def self.na_density(params)
            slot = self.na_measured_slot(self.na_session, params)
            min, max = self.na_box_in(params)
            view = params['view'].to_s
            self.na_refuse('invalid_params', "view must be one of #{NA_VIEWS.keys.join(', ')}, not '#{view}'.",
                           'right looks along -X (screen right = +Y), left along +X, front along +Y, back along -Y, top down.') unless NA_VIEWS.key?(view)
            pixel = self.na_positive(params, 'resolution', 'resolution')
            grid = params['grid'].to_f
            self.na_refuse('invalid_params', 'grid must be 0 (none) or a positive length.', 'Pass e.g. 100 (mm) for a line every 100 mm.') if grid < 0
            scale = (params['scale'] || 'log').to_s
            self.na_refuse('invalid_params', "scale must be log or linear, not '#{scale}'.", 'log shows faint surfaces as well as dense ones.') unless %w[log linear].include?(scale)
            out_path = params['out_path'].to_s
            self.na_refuse('invalid_params', 'out_path is required.', 'The MCP handler passes it.') if out_path.empty?

            frame = self.na_view_frame(view, min, max, pixel)
            xaxis, yaxis, = frame['axes']
            width = frame['width']
            height = frame['height']
            started = self.na_now
            # One cell more past the right and bottom edges, and NA_EDGE_INCHES before
            # the left and top (0.14.5): points on the box's faces, where the frame's
            # edges lie on whole pixels, land in the edge pixels instead of off the image.
            cells = xaxis + yaxis + [frame['cx0'] - NA_EDGE_INCHES, frame['cy1'] + NA_EDGE_INCHES, pixel, pixel, width + 1, height + 1]
            counted = self.na_grid_in(slot, min, max, cells)
            counts = self.na_fold_edges(counted['counts'].unpack('V*'), width, height)
            filled = counts.reject(&:zero?).sort
            top = filled.empty? ? 0 : filled[((filled.length - 1) * NA_DENSITY_CLIP).round]
            top = [top, 1].max
            denominator = Math.log(1 + top)
            table = (0..top).map do |n|
                share = scale == 'log' ? Math.log(1 + n) / denominator : n.to_f / top
                (255 * (1.0 - [share, 1.0].min)).round
            end
            grey = Array.new(height) do |row|
                counts[row * width, width].map { |n| table[n > top ? top : n] }.pack('C*')
            end
            result = self.na_picture(grey, frame, grid, out_path, slot, view, min, max, params)
            result['scale'] = scale
            result['points_in_box'] = counted['kept']
            result['points_on_image'] = counted['written']
            result['max_per_pixel'] = counts.max.to_i
            result['p99_5_per_pixel'] = top
            result['pixels_with_points'] = filled.length
            result['ms'] = (self.na_now - started).round
            result['summary'] = "#{width} x #{height} px #{view} density of #{slot.name} inside the box, #{self.na_out(pixel, params)} per px, " \
                                "#{self.na_thousands(counted['written'])} points; darker = more (#{scale}, black at #{top} or more a pixel, the most #{counted['maxCell']})."
            result
        end

    # endregion ----------------------------------------------------------------

        # (width + 1) x (height + 1) counts folded to width x height: the extra
        # column into the last column, the extra row into the last row.
        def self.na_fold_edges(counts, width, height)
            wide = width + 1
            out = Array.new(width * height, 0)
            (height + 1).times do |row|
                line = counts[row * wide, wide]
                line[width - 1] += line[width]
                target = [row, height - 1].min
                width.times { |column| out[target * width + column] += line[column] }
            end
            out
        end

    # -------------------------------------------------------------------------
    # REGION | points (v0.14.0: the first N the box keeps, an even sample)
    # -------------------------------------------------------------------------

        # limit points (default NA_DEFAULT_POINTS). Without out_path they come back
        # in the reply (at most NA_MAX_INLINE_POINTS, in the call's units); with it
        # (from save_path) up to NA_MAX_FILE_POINTS go to a .npz in model mm.
        def self.na_points(params)
            slot = self.na_measured_slot(self.na_session, params)
            min, max = self.na_box_in(params)
            out_path = params['out_path'].to_s
            to_file = !out_path.empty?
            most = to_file ? NA_MAX_FILE_POINTS : NA_MAX_INLINE_POINTS
            raw = params.key?('limit') ? params['limit'] : NA_DEFAULT_POINTS
            limit = raw.is_a?(Numeric) && raw == raw.round ? raw.round : nil
            unless limit && limit >= 1 && limit <= most
                self.na_refuse('invalid_params', "limit must be a whole number from 1 to #{self.na_thousands(most)}#{to_file ? '' : ' in the reply'}, not #{raw.inspect}.",
                               to_file ? 'Ask for fewer points, or a smaller box.' : "Pass save_path for up to #{self.na_thousands(NA_MAX_FILE_POINTS)} points in a .npz file.")
            end
            per_inch = (params['per_inch'] || 25.4).to_f
            block = [1.0, *min, *max, 0.0] + [0.0] * (Na__NativeEngine::NA_BOX_BLOCK_COUNT - 8)
            started = self.na_now
            begin
                read = Na__NativeEngine.Na__Native__BoxPoints(slot.cloud.native_cloud, slot.cloud.local_to_model, block, limit,
                                                              to_file ? 25.4 : per_inch, to_file)
            rescue StandardError => error
                self.na_refuse('operation_failed', "The points of #{slot.name} could not be read: #{error.message}",
                               'Reload the point cloud (point_cloud_view reload: true, or Reload in the viewer), then try again.')
            end
            written = read['written']
            kept = read['kept']
            share = kept > 0 ? (100.0 * written / kept).round(3) : 0.0
            result = {
                'cloud'          => slot.id,
                'name'           => slot.name,
                'box'            => self.na_box_out(min, max, params),
                'points_in_box'  => kept,
                'returned'       => written,
                'sample_percent' => share,
                'note'           => 'An even sample of the points in the box: the viewer stores every cloud shuffled and these are the first it keeps.'
            }
            digits = per_inch >= 10 ? 1 : 4
            if to_file
                frame = params['_frame']
                if frame
                    # The engine gave frame mm: p goes back to model mm for the kit, f keeps the frame's (0.14.6).
                    model = Na__McpFrame.Na__Frame__PackedToModel(frame, read['xyz'].unpack('E*'), 25.4)
                    self.na_write_npz(out_path, [['p', '<f8', [written, 3], model], ['f', '<f8', [written, 3], read['xyz']], ['c', '<u4', [written], read['bgra']]])
                else
                    self.na_write_npz(out_path, [['p', '<f8', [written, 3], read['xyz']], ['c', '<u4', [written], read['bgra']]])
                end
                preview = read['xyz'].byteslice(0, 24 * [written, NA_PREVIEW_POINTS].min).unpack('E*')
                result['file'] = out_path
                result['file_arrays'] = 'p: x, y, z in model mm (float64); ' + (frame ? 'f: x, y, z in the frame, mm (float64); ' : '') +
                                        'c: colour 0xAARRGGBB (uint32). numpy.load reads it; so does pc_kit.py --pts.'
                result['preview'] = preview.each_slice(3).map { |point| point.map { |value| (value / 25.4 * per_inch).round(digits) } }
            else
                result['points'] = read['xyz'].unpack('E*').each_slice(3).map { |point| point.map { |value| value.round(digits) } }
            end
            result['ms'] = (self.na_now - started).round
            result['summary'] = "#{self.na_thousands(written)} of #{self.na_thousands(kept)} points of #{slot.name} in the box (#{share}%, an even sample)" \
                                "#{to_file ? " written to #{File.basename(out_path)}" : ''}."
            result
        end

        # A .npz (a stored zip of .npy files, as numpy.savez writes) streamed to
        # disk: arrays are [name, numpy descr, shape, little-endian bytes].
        def self.na_write_npz(path, arrays)
            central = ''.b
            offset = 0
            File.open(path, 'wb') do |file|
                arrays.each do |name, descr, shape, bytes|
                    header = self.na_npy_header(descr, shape)
                    size = header.bytesize + bytes.bytesize
                    crc = Zlib.crc32(bytes, Zlib.crc32(header))
                    entry = "#{name}.npy".b
                    local = [0x04034b50, 20, 0, 0, 0, 0x21, crc, size, size, entry.bytesize, 0].pack('VvvvvvVVVvv')
                    file.write(local)
                    file.write(entry)
                    file.write(header)
                    file.write(bytes)
                    central << [0x02014b50, 20, 20, 0, 0, 0, 0x21, crc, size, size, entry.bytesize, 0, 0, 0, 0, 0, offset].pack('VvvvvvvVVVvvvvvVV') << entry
                    offset += local.bytesize + entry.bytesize + size
                end
                file.write(central)
                file.write([0x06054b50, 0, 0, arrays.length, arrays.length, central.bytesize, offset, 0].pack('VvvvvVVv'))
            end
            path
        end

        # The .npy header (format 1.0), padded so the data starts on 64 bytes.
        def self.na_npy_header(descr, shape)
            shape_text = shape.length == 1 ? "(#{shape[0]},)" : "(#{shape.join(', ')})"
            text = "{'descr': '#{descr}', 'fortran_order': False, 'shape': #{shape_text}, }"
            pad = (64 - (10 + text.bytesize + 1) % 64) % 64
            text = text + (' ' * pad) + "\n"
            "\x93NUMPY".b + [1, 0].pack('CC') + [text.bytesize].pack('v') + text.b
        end

        # The engine's PNG (PngWriter: one IDAT of stored deflate blocks, filter
        # 0 on every row, RGBA) as one String of RGBA bytes per row.
        def self.na_read_rgba_rows(path, width, height)
            bytes = File.binread(path)
            position = 8
            data = ''.b
            while position + 8 <= bytes.bytesize
                length = bytes.byteslice(position, 4).unpack1('N')
                type = bytes.byteslice(position + 4, 4)
                data << bytes.byteslice(position + 8, length) if type == 'IDAT'
                position += 12 + length
            end
            raw = Zlib::Inflate.inflate(data)
            stride = 1 + 4 * width
            raise "the engine's image is #{raw.bytesize} bytes, not #{stride * height}" unless raw.bytesize == stride * height
            Array.new(height) { |row| raw.byteslice(row * stride + 1, 4 * width) }
        end

        # One RGBA row on white paper: grey = colour x alpha + white x (1 - alpha).
        def self.na_grey_row(rgba)
            rgba.unpack('N*').map do |pixel|
                alpha = pixel & 0xFF
                red = (pixel >> 24) & 0xFF
                (red * alpha + 255 * (255 - alpha)) / 255
            end.pack('C*')
        end

        # Grid lines on multiples of grid (model value), every fifth darker. A
        # line never lightens a point.
        def self.na_draw_grid(rows, width, height, grid, u_left, u_step, v_top, v_step)
            columns = self.na_grid_positions(u_left, u_step, width, grid)
            lines = self.na_grid_positions(v_top, v_step, height, grid)
            rows.each do |row|
                columns.each do |column, shade|
                    row.setbyte(column, shade) if row.getbyte(column) > shade
                end
            end
            lines.each do |line, shade|
                row = rows[line]
                width.times { |column| row.setbyte(column, shade) if row.getbyte(column) > shade }
            end
        end

        # [[pixel index, grey]] for each grid value inside the image.
        def self.na_grid_positions(start, step, count, grid)
            finish = start + step * count
            low, high = [start, finish].minmax
            first = (low / grid - 1e-6).ceil
            last = (high / grid + 1e-6).floor
            (first..last).map do |multiple|
                index = ((multiple * grid - start) / step + 1e-6).floor   # 0.14.5: a hair under a whole number was a pixel early
                index = count - 1 if index == count
                next nil if index < 0 || index >= count
                [index, (multiple % 5).zero? ? NA_GRID_MAJOR_GREY : NA_GRID_MINOR_GREY]
            end.compact
        end

        # An 8-bit greyscale PNG (colour type 0, filter 0, deflated).
        def self.na_write_grey_png(path, width, height, rows)
            raw = rows.map { |row| "\x00".b + row }.join
            chunk = lambda do |type, body|
                [body.bytesize].pack('N') + type + body + [Zlib.crc32(type + body)].pack('N')
            end
            header = [width, height, 8, 0, 0, 0, 0].pack('NNCCCCC')
            png = "\x89PNG\r\n\x1A\n".b + chunk.call('IHDR'.b, header) + chunk.call('IDAT'.b, Zlib::Deflate.deflate(raw)) + chunk.call('IEND'.b, ''.b)
            File.binwrite(path, png)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Clip Box Changes (each ONE undo step named "Point Cloud: ...")
    # -------------------------------------------------------------------------

        # min/max (inches), or around ([min, max] inches round entities) grown by
        # margin (inches; the viewer's selection margin when absent) and rounded
        # outwards onto the draw grid, as Clip Box Around Selection does.
        def self.na_clip_box(params)
            session = self.na_session
            slots = self.na_target_slots(session, params['clouds'])
            if params['around']
                margin = params.key?('margin') ? params['margin'].to_f : Na__ClipBox.Na__Clip__SelectionMarginMm / 25.4
                self.na_refuse('invalid_params', 'margin must be 0 or more.', 'Pass e.g. 100 (mm).') if margin < 0
                min, max = Na__ClipBox.Na__Clip__GrowToGrid(params['around'], margin)
            else
                min, max = self.na_box_in(params)
            end
            3.times do |axis|
                next if max[axis] - min[axis] >= Na__ClipBox::NA_MIN_GAP_INCHES
                self.na_refuse('invalid_params', "The box is too thin along #{%w[x y z][axis]}: a clip box is at least #{self.na_out(Na__ClipBox::NA_MIN_GAP_INCHES, params)} on every side.",
                               'Give it more size along that axis.')
            end
            label = params['label'].to_s.strip[0, 60]
            label = NA_DEFAULT_LABEL if label.empty?
            problem = Na__ClipBox.Na__Clip__ApplyAreaBox(session, slots, min, max, label)
            self.na_refuse('operation_failed', problem, 'Change the box, or pick clouds by id from point_cloud_state.') if problem
            undo = Na__ClipBox.na_op_for(slots, label)
            self.na_after_change
            {
                'clouds'    => slots.map { |slot| self.na_cloud_state(slot, params) },
                'box'       => self.na_box_out(min, max, params),
                'undo_step' => undo,
                'summary'   => "#{Na__ClipBox.Na__Clip__AreaMessage('Clip box', slots, min, max)} One undo step: \"#{undo}\"."
            }
        end

        def self.na_clip_switch(params, enabled)
            session = self.na_session
            slots = self.na_target_slots(session, params['clouds'])
            slots.each { |slot| Na__ClipBox.Na__Clip__Ensure(slot) }
            no_box = slots.reject(&:clip)
            if enabled && no_box.length == slots.length
                self.na_refuse('invalid_params', "#{Na__ClipBox.Na__Clip__Names(no_box)} #{no_box.length == 1 ? 'has' : 'have'} no clip box yet.",
                               'Set one with action "box" (min and max) or "around" (ids).')
            end
            problem, changed = Na__ClipBox.Na__Clip__SetEnabledOn(session, slots, enabled)
            self.na_refuse('operation_failed', problem, 'Nothing was changed.') if problem
            self.na_after_change
            word = enabled ? 'on' : 'off'
            undo = changed.empty? ? nil : Na__ClipBox.na_op_for(changed, enabled ? 'Clip On' : 'Clip Off')
            summary = if changed.empty?
                          "Clipping was already #{word} for #{Na__ClipBox.Na__Clip__Names(slots)}; nothing changed."
                      else
                          "Clipping #{word} for #{Na__ClipBox.Na__Clip__Names(changed)}. One undo step: \"#{undo}\"."
                      end
            summary += " #{Na__ClipBox.Na__Clip__Names(no_box)} #{no_box.length == 1 ? 'has' : 'have'} no clip box." if enabled && !no_box.empty?
            { 'clouds' => slots.map { |slot| self.na_cloud_state(slot, params) }, 'undo_step' => undo, 'summary' => summary }
        end

        # scene: a clip scene's id or name, or 'full' (clipping off, box kept).
        def self.na_clip_scene(params)
            session = self.na_session
            slot = if params['cloud']
                       self.na_find_slot(session, params['cloud'])
                   else
                       targets = Na__ClipBox.Na__Clip__TargetSlots(session)
                       if targets.length != 1
                           self.na_refuse('invalid_params', 'Say which point cloud: each cloud has its own clip scenes.',
                                          "Pass cloud: one of #{self.na_names(Na__CloudSet.Na__Slots__All(session))}.")
                       end
                       targets.first
                   end
            Na__ClipBox.Na__Clip__Ensure(slot)
            key = params['scene'].to_s.strip
            self.na_refuse('invalid_params', 'scene is required.', 'Pass a clip scene id or name from point_cloud_state, or "full".') if key.empty?
            named = slot.clip_scenes.find { |each| each['id'] == key } || slot.clip_scenes.find { |each| each['name'].to_s.casecmp?(key) }
            if named.nil? && (key.casecmp?(Na__ClipBox::NA_FULL_CLOUD_ID) || key.casecmp?('Full Cloud'))
                was_on = slot.clip && slot.clip['enabled']
                problem = self.na_scene_activate(slot, Na__ClipBox::NA_FULL_CLOUD_ID)
                self.na_refuse('operation_failed', problem, 'Nothing was changed.') if problem
                undo = was_on ? Na__CloudSet.Na__Slots__OpName(slot, 'Full Cloud') : nil
                text = was_on ? "#{slot.name}: Full Cloud (clipping off, box kept). One undo step: \"#{undo}\"." : "#{slot.name} was not clipping; nothing changed."
            else
                scene = named
                unless scene
                    names = slot.clip_scenes.map { |each| "#{each['id']} (#{each['name']})" }
                    self.na_refuse('not_found', "#{slot.name} has no clip scene '#{key}'.",
                                   names.empty? ? 'It has no clip scenes; set a box with action "box".' : "Use one of: #{names.join(', ')}, or \"full\".")
                end
                problem = self.na_scene_activate(slot, scene['id'])
                self.na_refuse('operation_failed', problem, 'Nothing was changed.') if problem
                undo = Na__CloudSet.Na__Slots__OpName(slot, "Clip Scene #{scene['name']}")
                text = "#{slot.name}: clip scene #{scene['name']}. One undo step: \"#{undo}\"."
            end
            self.na_after_change
            { 'clouds' => [self.na_cloud_state(slot, params)], 'undo_step' => undo, 'summary' => text }
        end

        # Na__Clip__SceneActivate, a raised error turned into a refusal (0.14.5);
        # the clip box puts the cloud back in step with the model itself.
        def self.na_scene_activate(slot, scene_id)
            Na__ClipBox.Na__Clip__SceneActivate(slot, scene_id)
        rescue StandardError => error
            self.na_refuse('operation_failed', "The clip scene could not be applied: #{error.message}", 'Nothing was changed. Try again, or use the viewer\'s Clip Box tab.')
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | view (view settings only: never written to the model)
    # -------------------------------------------------------------------------

        def self.na_view(params)
            session = self.na_session
            model = session.model
            slots = params['clouds'] ? self.na_named_slots(session, params['clouds']) : Na__CloudSet.Na__Slots__All(session)
            limits = Na__RenderSettings.Na__Settings__Limits
            look = {}
            look['pointSizePx'] = self.na_int_in(params, 'point_size_px', limits['pointSizeMinPx'], limits['pointSizeMaxPx']) if params.key?('point_size_px')
            look['opacityPercent'] = self.na_int_in(params, 'opacity_percent', limits['opacityMinPct'], limits['opacityMaxPct']) if params.key?('opacity_percent')
            if params.key?('colour_mode')
                mode = params['colour_mode'].to_s
                unless Na__RenderSettings::NA_COLOUR_MODES.include?(mode)
                    self.na_refuse('invalid_params', "colour_mode must be one of #{Na__RenderSettings::NA_COLOUR_MODES.join(', ')}, not '#{mode}'.",
                                   'black draws every point dark (best over the model); primary draws each cloud in its own colour.')
                end
                look['colourMode'] = mode
            end
            budget = self.na_int_in(params, 'point_budget', limits['pointBudgetMin'], limits['pointBudgetMax']) if params.key?('point_budget')
            if slots.empty? && (params.key?('shown') || !look.empty?)
                self.na_refuse('not_found', 'There is no point cloud in this model yet.', 'Import one in the Point Cloud Viewer first.')
            end

            view = model.active_view
            done = []
            if params.key?('shown')
                shown = params['shown'] == true
                slots.each { |slot| Na__CloudSet.Na__Slots__SetVisible(slot, shown) }
                Na__ModelRegistry.Na__Registry__SetVisible(true) if shown && !Na__ModelRegistry.Na__Registry__IsVisible?
                done << "#{shown ? 'shown' : 'hidden'}: #{Na__ClipBox.Na__Clip__Names(slots)}"
            end
            unless look.empty?
                slots.each { |slot| Na__RenderController.Na__Render__ApplySettings(session, look, view, slot) }
                names = { 'pointSizePx' => 'point_size_px', 'opacityPercent' => 'opacity_percent', 'colourMode' => 'colour_mode' }
                done << "look #{look.map { |key, value| "#{names[key]} #{value}" }.join(', ')}"
            end
            if budget
                Na__RenderController.Na__Render__ApplySettings(session, { 'pointBudget' => budget }, view)
                done << "point budget #{self.na_thousands(budget)}"
            end
            if params.key?('overlay')
                Na__ModelRegistry.Na__Registry__SetVisible(params['overlay'] == true)
                done << "overlay #{params['overlay'] == true ? 'on' : 'off'}"
            end
            warnings = []
            if params['reload'] == true
                if Na__CloudSet.Na__Slots__All(session).all? { |slot| self.na_loaded?(slot) }
                    done << 'every cloud already loaded'
                else
                    problem = Na__PointCloudViewer.Na__PublicApi__ReloadPointCloud(model)
                    if problem
                        warnings << "Reload did not start: #{problem}"
                    else
                        done << 'reload started (the viewer loads in the background; check point_cloud_state loaded)'
                    end
                end
            end
            self.na_after_change
            {
                'clouds'       => slots.map { |slot| self.na_cloud_state(slot, params) },
                'overlay_on'   => Na__ModelRegistry.Na__Registry__IsVisible? ? true : false,
                'point_budget' => session.settings['pointBudget'],
                'warnings'     => warnings,
                'summary'      => done.empty? ? 'Nothing asked for, so nothing changed.' : "#{done.join('; ')}. View settings only: not written to the model, no undo step."
            }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Slice Frames (v0.14.6: any angle, the engine unchanged)
    # -------------------------------------------------------------------------

        # A cloud seen in a slice frame: local_to_model is the frame folded in
        # (Na__Frame__Fold), so every engine call made with it (box tests,
        # grids, points, the renderer) works in the frame.
        class Na__FramedCloud < SimpleDelegator
            def initialize(cloud, transform)
                super(cloud)
                @na_transform = transform
            end

            def local_to_model
                @na_transform
            end
        end

        # A slot whose cloud is seen in a frame; everything else is the slot's own.
        class Na__FramedSlot < SimpleDelegator
            def initialize(slot, cloud)
                super(slot)
                @na_cloud = cloud
            end

            def cloud
                @na_cloud
            end
        end

        # The frame in params['frame'] (model inches), or a refusal naming the fault.
        def self.na_frame_in(spec)
            Na__McpFrame.Na__Frame__Make(spec)
        rescue ArgumentError => error
            self.na_refuse('invalid_params', error.message,
                           'Give the frame an origin and either angle (degrees from +x about the vertical), or x_axis with an optional y_axis.')
        end

        # The slot as the engine should see it: in the frame when the call has one.
        def self.na_framed(slot, params)
            frame = params['_frame']
            return slot unless frame && slot.cloud
            Na__FramedSlot.new(slot, Na__FramedCloud.new(slot.cloud, Na__McpFrame.Na__Frame__Fold(frame, slot.cloud.local_to_model)))
        end

        # The frame as the reply gives it back: origin in the call's units, unit axes.
        def self.na_frame_out(frame, params)
            x, y, z = frame['axes']
            tidy = ->(axis) { axis.map { |value| value.round(9) + 0.0 } }
            {
                'origin' => frame['origin'].map { |value| self.na_out_exact(value, params) },
                'x_axis' => tidy.call(x), 'y_axis' => tidy.call(y), 'z_axis' => tidy.call(z),
                'rule'   => 'model point = origin + x * x_axis + y * y_axis + z * z_axis. min, max, the view, axis, path and every position, ' \
                            'direction and azimuth in this reply are in the frame (top looks down its z, front along its +y).'
            }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Helpers
    # -------------------------------------------------------------------------

        def self.na_session
            model = Sketchup.active_model
            session = model ? Na__PointCloudViewer.na_api_session(model) : nil
            return session if session
            self.na_refuse('unsupported', 'The point cloud overlay is not available for this model.',
                           'The Point Cloud Viewer needs SketchUp 2023 or newer; open the model in this window and try again.')
        end

        def self.na_loaded?(slot)
            cloud = slot.cloud
            cloud && cloud.native_cloud && Na__NativeEngine.Na__Native__CloudLive?(cloud.native_cloud) ? true : false
        end

        def self.na_find_slot(session, key)
            slots = Na__CloudSet.Na__Slots__All(session)
            text = key.to_s.strip
            slot = slots.find { |each| each.id == text }
            return slot if slot
            named = slots.select { |each| each.name.to_s.casecmp?(text) }
            return named.first if named.length == 1
            if named.length > 1   # 0.14.5: names are not unique (import names a cloud after its file)
                self.na_refuse('invalid_params', "#{named.length} point clouds are named '#{text}'.", "Pass the id instead: #{self.na_names(named)}.")
            end
            self.na_refuse('not_found', "No point cloud '#{text}' in this model.",
                           slots.empty? ? 'This model has no point cloud yet.' : "Use an id or name from point_cloud_state: #{self.na_names(slots)}.")
        end

        def self.na_named_slots(session, keys)
            Array(keys).map { |key| self.na_find_slot(session, key) }.uniq
        end

        # Given clouds, or every cloud on show (the active one when none is),
        # as Draw Clip Box picks them.
        def self.na_target_slots(session, keys)
            slots = keys ? self.na_named_slots(session, keys) : Na__ClipBox.Na__Clip__TargetSlots(session)
            self.na_refuse('not_found', 'There is no point cloud in this model yet.', 'Import one in the Point Cloud Viewer first.') if slots.empty?
            slots
        end

        # The one cloud to measure: the one named, or the only loaded cloud on
        # show (or the only loaded cloud).
        def self.na_measured_slot(session, params)
            all = Na__CloudSet.Na__Slots__All(session)
            self.na_refuse('not_found', 'There is no point cloud in this model yet.', 'Import one in the Point Cloud Viewer first.') if all.empty?
            slot = if params['cloud']
                       self.na_find_slot(session, params['cloud'])
                   else
                       loaded = all.select { |each| each.visible && self.na_loaded?(each) }
                       loaded = all.select { |each| self.na_loaded?(each) } if loaded.empty?
                       unless loaded.length == 1
                           self.na_refuse('invalid_params', "Say which point cloud to measure: #{loaded.empty? ? 'none is loaded' : "#{loaded.length} are loaded"}.",
                                          "Pass cloud: one of #{self.na_names(all)}.")
                       end
                       loaded.first
                   end
            return self.na_framed(slot, params) if self.na_loaded?(slot)
            self.na_refuse('operation_failed', "#{slot.name} is not loaded, so its points cannot be read.",
                           'Load it with point_cloud_view {reload: true} (or Reload in the viewer), wait for point_cloud_state to show loaded, then try again.')
        end

        def self.na_names(slots)
            slots.map { |slot| "#{slot.id} (#{slot.name})" }.join(', ')
        end

        # [min, max] from params['min'] / params['max'] (inches), each side positive.
        def self.na_box_in(params)
            min = Array(params['min']).map(&:to_f)
            max = Array(params['max']).map(&:to_f)
            unless min.length == 3 && max.length == 3
                self.na_refuse('invalid_params', 'min and max are both required, each [x, y, z].', 'Pass the box corners in the call\'s units, e.g. min [14500, 10500, 0], max [19000, 17000, 5500].')
            end
            unless (min + max).all?(&:finite?)
                self.na_refuse('invalid_params', 'min and max must be finite numbers.', 'Pass the box corners in the call\'s units.')
            end
            3.times do |axis|
                next if max[axis] > min[axis]
                self.na_refuse('invalid_params', "max #{%w[x y z][axis]} must be greater than min #{%w[x y z][axis]}.", 'Swap the two values, or give the box some size.')
            end
            [min, max]
        end

        def self.na_positive(params, key, label)
            value = params[key].to_f
            return value if value > 0
            self.na_refuse('invalid_params', "#{label} must be a positive length.", "Pass #{label} in the call's units, e.g. 5 (mm).")
        end

        def self.na_int_in(params, key, low, high)
            raw = params[key]
            value = raw.is_a?(Numeric) && raw == raw.round ? raw.round : nil
            return value if value && value >= low.to_i && value <= high.to_i
            self.na_refuse('invalid_params', "#{key} must be a whole number from #{low} to #{high}, not #{raw.inspect}.", 'The viewer refuses anything outside its own limits.')
        end

        def self.na_after_change
            Na__DialogManager.Na__Dialog__PushState if Na__DialogManager.Na__Dialog__Visible?
            model = Sketchup.active_model
            model.active_view.invalidate if model
        rescue StandardError
            nil
        end

        def self.na_out(inches, params)
            per_inch = (params['per_inch'] || 25.4).to_f
            (inches.to_f * per_inch).round(per_inch >= 10 ? 1 : 4)
        end

        # A step, a mapping or an echo of the call's own numbers in the call's
        # units, to 9 significant figures (0.14.5): na_out's 0.1 mm turned a
        # 0.25 mm pixel into 0.2, 200 mm out across 4,000 pixels.
        def self.na_out_exact(inches, params)
            per_inch = (params['per_inch'] || 25.4).to_f
            value = inches.to_f * per_inch
            return 0.0 if value.zero? || !value.finite?
            digits = [[8 - Math.log10(value.abs).floor, 0].max, 12].min
            value.round(digits)
        end

        # "2.1% (1 in 48)", or "level" when there is no slope at all.
        def self.na_slope_words(slope)
            slope && slope['one_in'] ? "#{slope['percent']}% (1 in #{slope['one_in']})" : 'level'
        end

        def self.na_box_out(min, max, params)
            low = min.map { |value| self.na_out_exact(value, params) }
            high = max.map { |value| self.na_out_exact(value, params) }
            { 'min' => low, 'max' => high, 'size' => (0..2).map { |axis| (high[axis] - low[axis]).round(4) } }
        end

        def self.na_dot(a, b)
            a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
        end

        def self.na_now
            Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000.0
        end

        def self.na_thousands(number)
            number.to_i.to_s.reverse.scan(/\d{1,3}/).join(',').reverse
        end

        def self.na_refuse(code, message, hint = nil, details = nil)
            raise Na__McpOperationsError.new(code, message, hint, details)
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
