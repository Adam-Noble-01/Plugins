# =============================================================================
# NA POINT CLOUD VIEWER - SCENES - IMAGE EXPORT
# =============================================================================
#
# FILE       : Na__PointCloudViewer__Scenes__ImageExport__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__SceneImageExport
# PURPOSE    : Renders a point cloud scene to image tiles, off screen, for
#              TrueVision, and describes exactly where every pixel sits in the
#              model so the image can be placed under the model's own linework.
#
# NO SCREEN CAPTURE, SO NO SCENE TRANSITION TO WAIT FOR: the camera is read
#   from the SketchUp scene itself (Page#camera, only when the scene saves a
#   camera) and the native engine renders it at any size. Nothing is selected,
#   no view changes, and a half-finished scene animation can never leak into an
#   image. The viewport, the window size and the user's own view do not matter.
#
# WHAT A PARALLEL (PLAN, ELEVATION, SECTION) SCENE PRODUCES: an image TO SCALE.
#   One pixel = scale / pxPerPaperMm millimetres in the model (1:50 at 12 px
#   per paper mm = 4.17 mm). The image covers the visible cloud (the cloud, or
#   its part inside the scene's clip box) projected along the scene's camera,
#   padded by the dot size and snapped to whole pixels. The frame record gives
#   the model position of the image's top-left corner and its right and down
#   directions, so model point P lands at pixel
#       u = (xaxis . (P - eye) - cx0) / pixel     v = (cy1 - yaxis . (P - eye)) / pixel
#   (u, v measured from the image's top-left corner, in pixels).
#
# WHAT A PERSPECTIVE (3D VIEW) SCENE PRODUCES: the camera's whole view at the
#   scene's image width and saved aspect ratio. It lines up only with the same
#   camera, which the record carries (SketchUp and three.js forms).
#
# SEVERAL CLOUDS (v0.10.0): every cloud the scene shows is one layer of the
#   same picture (one depth buffer: the nearest point wins whichever cloud it
#   comes from; one shared budget), each with its own placement, clip box and
#   colour, all at the scene's one dot size. The plan lists the layers
#   ('layers', 'cloudIds'); its top-level 'cloud', 'clip', 'colourMode' and
#   'localToModel' describe the first layer, as they described the one cloud
#   before. A scene of ONE cloud plans, keys and renders exactly as in v0.9, so
#   an unchanged scene is never exported again just because of the update.
#
# BAKED AT 100 % OPACITY. The scene's opacity (the highest of its clouds')
#   travels as TrueVision's default.
# DOT CENTRING: the engine puts an even-sized dot half a pixel right and down
#   of its point; the render shifts the projection half a pixel the other way
#   for even sizes, so every dot is centred on its point to within half a pixel.
#
# COORDINATES: SketchUp inches, Z up; three.js metres, Y up, exactly as the GLB
#   Builder writes its models: (x, y, z) -> (x, z, -y) x 0.0254, no offset.
#
# =============================================================================

require 'json'
require 'digest'
require 'fileutils'

module Na__PointCloudViewer
    module Na__SceneImageExport

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_FORMAT_VERSION = 1                      # bump when the pixels a plan produces change
        NA_METRES_PER_INCH = 0.0254
        NA_MM_PER_INCH     = 25.4

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Plan (what would be rendered; no rendering)
    # -------------------------------------------------------------------------

        # Returns { 'ok' => true, 'plan' => {...} } or { 'ok' => false, 'problem' => text }.
        # options: 'pxPerPaperMm', 'tileSizePx', 'maxMegapixels' override the config.
        def self.Na__Export__Plan(session, scene_id, options = {})
            scene = Na__SceneStore.Na__Scenes__Find(session, scene_id)
            return self.na_refuse('That point cloud scene no longer exists.') unless scene
            model = session.model
            page = Na__SceneStore.Na__Scenes__ResolvePage(model, scene)
            name = page ? page.name.to_s : scene.dig('page', 'name').to_s
            return self.na_refuse("The SketchUp scene \"#{name}\" no longer exists. Relink or remove this point cloud scene.") unless page
            return self.na_refuse("\"#{name}\" does not save a camera position, so it cannot be exported.") unless page.use_camera?
            layers, problem = self.na_layers(session, scene, name)
            return self.na_refuse(problem) if problem
            cloud = layers.first['slot'].cloud

            camera = page.camera
            perspective = camera.perspective? ? true : false
            config = self.na_config(options)
            point_size = Na__SceneStore.Na__Scenes__ExportPointSize(scene, perspective)
            basis = self.Na__Export__CameraBasis(camera)

            frame = if perspective
                        self.na_perspective_frame(scene, camera, config)
                    else
                        bounds = self.na_visible_bounds(layers)
                        return self.na_refuse(layers.length == 1 ? "The clip box saved with \"#{name}\" does not overlap the point cloud." :
                                                                   "The clip boxes saved with \"#{name}\" do not overlap their point clouds.") unless bounds
                        self.Na__Export__OrthoFrame(basis, bounds, (scene.dig('export', 'scale') || 50).to_f, config, point_size)
                    end
            return self.na_refuse(frame['problem']) if frame['problem']
            point_size = [(point_size * frame['pointSizeFactor'].to_f).round, 1].max if frame['pointSizeFactor']

            settings = scene['settings'] || {}
            budget = settings['pointBudget'].to_i
            layer_records = layers.map { |layer| self.na_layer_record(layer) }
            first = layer_records.first
            plan = {
                'sceneId'      => scene['id'],
                'sceneName'    => name,
                'viewType'     => scene['viewType'],
                'storeId'      => (session.scenes_meta || {})['storeId'],
                'projection'   => perspective ? 'perspective' : 'orthographic',
                'basis'        => basis,
                'frame'        => frame,
                'tileSizePx'   => config['tileSizePx'],
                'pointSizePx'  => point_size,
                'colourMode'   => first['colourMode'],
                'monoRgb'      => first['monoRgb'],
                'pointBudget'  => layers.length == 1 ? [budget, cloud.total_points.to_i].min : budget,
                'opacityPercent' => layer_records.map { |record| record['opacityPercent'] }.max,
                'clip'         => first['clip'],
                'localToModel' => first['localToModel'],
                'nativeGeneration' => cloud.native_generation,
                'camera'       => self.Na__Export__CameraRecord(camera, frame, scene),
                'cloud'        => first['cloud'],
                'cloudIds'     => layer_records.map { |record| record['cloudId'] },
                'layers'       => layer_records,
                'tiles'        => self.Na__Export__Tiles(frame['widthPx'], frame['heightPx'], config['tileSizePx'])
            }
            plan['revisionKey'] = self.Na__Export__RevisionKey(plan)
            { 'ok' => true, 'plan' => plan }
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('A point cloud scene could not be planned for export.', error)
            self.na_refuse("The scene could not be prepared for export (#{error.message}).")
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Render
    # -------------------------------------------------------------------------

        # Renders every tile of a plan as a PNG into out_dir (created). Returns
        # { 'ok', 'tiles' => [{ 'row', 'col', 'x', 'y', 'w', 'h', 'file', 'pointsOnTile', 'empty' }],
        #   'renderMs', 'problem' }. The block, if any, is called after each tile
        # with (done, total) so a caller can report progress.
        # A caller may hand control back to SketchUp between tiles (the block),
        # so the cloud is checked again before EVERY tile: unloaded, swapped,
        # moved or turned since the plan means stop, never render a mix.
        def self.Na__Export__RenderTiles(session, plan, out_dir)
            return self.na_refuse('The point cloud changed since this export was planned. Export again.') unless self.na_plan_current?(session, plan)
            return self.na_refuse(Na__NativeEngine.na_unavailable_error) unless Na__NativeEngine.Na__Native__EnsureLoaded
            FileUtils.mkdir_p(out_dir)
            started = Na__PerfStats.Na__Perf__NowMs
            results = []
            plan['tiles'].each_with_index do |tile, index|
                return self.na_refuse('A point cloud was unloaded, reloaded or moved during the export. Nothing from this scene was kept. Export again.') unless self.na_plan_current?(session, plan)
                pointers = self.na_plan_slots(session, plan).map { |slot| slot.cloud.native_cloud }
                path = File.join(out_dir, self.Na__Export__TileStem(tile) + '.png')
                stats = Na__NativeEngine.Na__Native__RenderLayersPng(pointers, self.Na__Export__TileLayerParams(plan, tile), plan['pointBudget'], path)
                on_tile = stats['pointsOnScreen'].to_i
                results << tile.merge('file' => File.basename(path), 'pointsOnTile' => on_tile, 'empty' => on_tile.zero?)
                yield(index + 1, plan['tiles'].length) if block_given?
            end
            { 'ok' => true, 'tiles' => results, 'renderMs' => (Na__PerfStats.Na__Perf__NowMs - started).round }
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('A point cloud scene could not be rendered.', error)
            self.na_refuse("The scene could not be rendered (#{error.message}).")
        end

        def self.Na__Export__TileStem(tile)
            format('PointCloud__Tile__R%02d__C%02d__', tile['row'], tile['col'])
        end

        # The 48 native render parameters of every layer for one tile (see the
        # engine's Na__RenderParamIndex), first layer first. Pure: the same plan
        # and tile give the same lists.
        def self.Na__Export__TileLayerParams(plan, tile)
            layers = plan['layers'] || [{ 'clip' => plan['clip'], 'colourMode' => plan['colourMode'], 'monoRgb' => plan['monoRgb'],
                                          'localToModel' => plan['localToModel'] }]
            layers.map { |layer| self.na_tile_params(plan, tile, layer) }
        end

        # The first layer's parameters (a one-cloud scene's whole render).
        def self.Na__Export__TileParams(plan, tile)
            self.Na__Export__TileLayerParams(plan, tile).first
        end

        def self.na_tile_params(plan, tile, layer)
            basis = plan['basis']
            frame = plan['frame']
            size  = plan['pointSizePx'].to_i
            even  = size.even? ? 0.5 : 0.0          # centres an even-sized dot on its point
            full_w = frame['widthPx'].to_f
            full_h = frame['heightPx'].to_f
            if plan['projection'] == 'perspective'
                scale_x = frame['scaleX'].to_f
                scale_y = frame['scaleY'].to_f
                crop_x = tile['x'] + even
                crop_y = tile['y'] + even
            else
                pixel = frame['pixelSizeIn'].to_f
                scale_x = 2.0 / (full_w * pixel)
                scale_y = 2.0 / (full_h * pixel)
                crop_x = 0.5 * full_w + frame['cx0'].to_f / pixel + tile['x'] + even
                crop_y = 0.5 * full_h - frame['cy1'].to_f / pixel + tile['y'] + even
            end
            clip = layer['clip'] ? [1] + layer['clip']['min'] + layer['clip']['max'] : [0, 0, 0, 0, 0, 0, 0]
            near = Na__ConfigLoader.Na__Config__GetOr(0.5, 'render', 'nativeImage', 'nearInches').to_f
            basis['eye'] + basis['xaxis'] + basis['yaxis'] + basis['zaxis'] +
                [plan['projection'] == 'perspective' ? 1 : 0, scale_x, scale_y,
                 tile['w'], tile['h'], size, 1.0, %w[black cloud].include?(layer['colourMode']) ? 1 : 0,
                 *layer['monoRgb'], plan['pointBudget'], near] +
                layer['localToModel'] + clip + [full_w, full_h, crop_x, crop_y]
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Geometry (pure functions: tested numerically)
    # -------------------------------------------------------------------------

        # eye and the camera's own axes: x right, y up the screen, z into it.
        def self.Na__Export__CameraBasis(camera)
            {
                'eye'    => camera.eye.to_a.map(&:to_f),
                'target' => camera.target.to_a.map(&:to_f),
                'xaxis'  => camera.xaxis.to_a.map(&:to_f),
                'yaxis'  => camera.yaxis.to_a.map(&:to_f),
                'zaxis'  => camera.zaxis.to_a.map(&:to_f)
            }
        end

        # A to-scale frame around the visible box. bounds = [[min], [max]] in
        # model inches. Snapped to whole pixels measured from the camera's own
        # axis, so an unchanged scene always lands on the same pixel grid.
        def self.Na__Export__OrthoFrame(basis, bounds, denominator, config, point_size)
            px_per_mm = config['pxPerPaperMm'].to_f
            factor = nil
            frame = self.na_ortho_frame_at(basis, bounds, denominator, px_per_mm, config, point_size)
            if frame['widthPx'] * frame['heightPx'] > config['maxMegapixels'] * 1_000_000.0
                factor = Math.sqrt(config['maxMegapixels'] * 1_000_000.0 / (frame['widthPx'] * frame['heightPx'])) * 0.98
                frame = self.na_ortho_frame_at(basis, bounds, denominator, px_per_mm * factor, config, [(point_size * factor).round, 1].max)
                frame['reducedFromPxPerMm'] = px_per_mm
                frame['pointSizeFactor'] = factor
            end
            frame
        end

        def self.na_ortho_frame_at(basis, bounds, denominator, px_per_mm, config, point_size)
            pixel = denominator / px_per_mm / NA_MM_PER_INCH            # inches per pixel
            lo, hi = bounds
            corners = [0, 1].product([0, 1], [0, 1]).map { |ix, iy, iz| [ix.zero? ? lo[0] : hi[0], iy.zero? ? lo[1] : hi[1], iz.zero? ? lo[2] : hi[2]] }
            eye = basis['eye']
            cxs = corners.map { |p| self.na_dot(basis['xaxis'], self.na_sub(p, eye)) }
            cys = corners.map { |p| self.na_dot(basis['yaxis'], self.na_sub(p, eye)) }
            pad = (point_size / 2.0 + config['framePaddingPx'].to_f) * pixel
            cx0 = ((cxs.min - pad) / pixel).floor * pixel
            cx1 = ((cxs.max + pad) / pixel).ceil * pixel
            cy0 = ((cys.min - pad) / pixel).floor * pixel
            cy1 = ((cys.max + pad) / pixel).ceil * pixel
            {
                'kind'             => 'orthographic',
                'scaleDenominator' => denominator,
                'pxPerPaperMm'     => px_per_mm,
                'pixelSizeIn'      => pixel,
                'cx0'              => cx0,
                'cy1'              => cy1,
                'widthPx'          => [((cx1 - cx0) / pixel).round, 1].max,
                'heightPx'         => [((cy1 - cy0) / pixel).round, 1].max
            }
        end

        # Model point (inches) -> image pixel position (u right, v down, from the
        # top-left corner). Used by the tests and by the datum record.
        def self.Na__Export__ModelToPixel(plan, point)
            basis = plan['basis']
            frame = plan['frame']
            rel = self.na_sub(point, basis['eye'])
            cx = self.na_dot(basis['xaxis'], rel)
            cy = self.na_dot(basis['yaxis'], rel)
            if plan['projection'] == 'perspective'
                cz = self.na_dot(basis['zaxis'], rel)
                return nil if cz <= 0
                [cx / cz * 0.5 * frame['widthPx'] * frame['scaleX'] + 0.5 * frame['widthPx'],
                 0.5 * frame['heightPx'] - cy / cz * 0.5 * frame['heightPx'] * frame['scaleY']]
            else
                pixel = frame['pixelSizeIn']
                [(cx - frame['cx0']) / pixel, (frame['cy1'] - cy) / pixel]
            end
        end

        def self.Na__Export__Tiles(width, height, tile_size)
            tiles = []
            rows = (height.to_f / tile_size).ceil
            cols = (width.to_f / tile_size).ceil
            rows.times do |row|
                cols.times do |col|
                    x = col * tile_size
                    y = row * tile_size
                    tiles << { 'row' => row, 'col' => col, 'x' => x, 'y' => y,
                               'w' => [tile_size, width - x].min, 'h' => [tile_size, height - y].min }
                end
            end
            tiles
        end

        # 10 hex digits over everything that changes the pixels. Same inputs,
        # same key, so an unchanged scene is never rendered or uploaded twice. A
        # one-cloud scene keys exactly as in v0.9; with several clouds every
        # layer's cloud, placement, clip box and colour are in the key.
        def self.Na__Export__RevisionKey(plan)
            inputs = {
                'v' => NA_FORMAT_VERSION, 'projection' => plan['projection'], 'basis' => plan['basis'],
                'frame' => plan['frame'], 'tile' => plan['tileSizePx'], 'size' => plan['pointSizePx'],
                'colour' => plan['colourMode'], 'mono' => plan['monoRgb'], 'budget' => plan['pointBudget'],
                'clip' => plan['clip'], 'm' => plan['localToModel'], 'cloud' => plan.dig('cloud', 'contentKey') || plan.dig('cloud', 'fingerprint')
            }
            layers = plan['layers'] || []
            if layers.length > 1
                inputs['layers'] = layers.map do |layer|
                    { 'cloud' => layer.dig('cloud', 'contentKey') || layer.dig('cloud', 'fingerprint'), 'm' => layer['localToModel'],
                      'clip' => layer['clip'], 'colour' => layer['colourMode'], 'mono' => layer['monoRgb'] }
                end
            end
            Digest::SHA256.hexdigest(JSON.generate(self.na_rounded(inputs)))[0, 10]
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Records (what TrueVision reads)
    # -------------------------------------------------------------------------

        # The scene camera in both coordinate systems, plus the image frame.
        def self.Na__Export__CameraRecord(camera, frame, scene)
            perspective = camera.perspective?
            basis = self.Na__Export__CameraBasis(camera)
            record = {
                'Projection' => perspective ? 'perspective' : 'orthographic',
                'SketchUp'   => {
                    'Units' => 'inches', 'UpAxis' => 'Z',
                    'Eye' => basis['eye'], 'Target' => basis['target'], 'Up' => camera.up.to_a.map(&:to_f),
                    'XAxis' => basis['xaxis'], 'YAxis' => basis['yaxis'], 'ZAxis' => basis['zaxis'],
                    'Perspective' => perspective ? true : false,
                    'AspectRatio' => camera.aspect_ratio.to_f
                },
                'ThreeJs'    => {
                    'Units' => 'metres', 'UpAxis' => 'Y',
                    'Position'  => self.Na__Export__ToThreePoint(basis['eye']),
                    'Target'    => self.Na__Export__ToThreePoint(basis['target']),
                    'Up'        => self.Na__Export__ToThreeVector(basis['yaxis']),
                    'Right'     => self.Na__Export__ToThreeVector(basis['xaxis']),
                    'Direction' => self.Na__Export__ToThreeVector(basis['zaxis'])
                }
            }
            if perspective
                record['SketchUp']['FovDeg'] = camera.fov.to_f
                record['SketchUp']['FovIsHeight'] = camera.fov_is_height? ? true : false
                record['ThreeJs']['FovVerticalDeg'] = frame['fovVerticalDeg']
                record['ThreeJs']['Aspect'] = frame['aspect']
            else
                aspect = scene.dig('view', 'aspect').to_f
                aspect = camera.aspect_ratio.to_f if camera.aspect_ratio.to_f > 0
                record['SketchUp']['OrthoHeight'] = camera.height.to_f
                record['ThreeJs']['SceneViewHeightM'] = camera.height.to_f * NA_METRES_PER_INCH
                record['ThreeJs']['SceneViewWidthM']  = camera.height.to_f * aspect * NA_METRES_PER_INCH
                record['ThreeJs']['SceneViewAspect']  = aspect
            end
            record
        end

        # Where the image sits in the model, ready for TrueVision.
        def self.Na__Export__FrameRecord(plan)
            frame = plan['frame']
            basis = plan['basis']
            return { 'Kind' => 'perspective', 'WidthPx' => frame['widthPx'], 'HeightPx' => frame['heightPx'],
                     'Aspect' => frame['aspect'], 'FovVerticalDeg' => frame['fovVerticalDeg'] } if plan['projection'] == 'perspective'
            pixel = frame['pixelSizeIn']
            depth = self.na_dot(basis['zaxis'], self.na_sub(basis['target'], basis['eye']))
            origin = (0..2).map { |i| basis['eye'][i] + basis['xaxis'][i] * frame['cx0'] + basis['yaxis'][i] * frame['cy1'] + basis['zaxis'][i] * depth }
            down = basis['yaxis'].map { |v| -v }
            {
                'Kind'             => 'orthographic',
                'WidthPx'          => frame['widthPx'],
                'HeightPx'         => frame['heightPx'],
                'ScaleDenominator' => frame['scaleDenominator'],
                'PxPerPaperMm'     => frame['pxPerPaperMm'],
                'ReducedFromPxPerPaperMm' => frame['reducedFromPxPerMm'],
                'PixelSizeMm'      => pixel * NA_MM_PER_INCH,
                'PixelSizeM'       => pixel * NA_METRES_PER_INCH,
                'WidthM'           => frame['widthPx'] * pixel * NA_METRES_PER_INCH,
                'HeightM'          => frame['heightPx'] * pixel * NA_METRES_PER_INCH,
                'OriginM'          => self.Na__Export__ToThreePoint(origin),
                'RightM'           => self.Na__Export__ToThreeVector(basis['xaxis']),
                'DownM'            => self.Na__Export__ToThreeVector(down),
                'NormalM'          => self.Na__Export__ToThreeVector(basis['zaxis']),
                'SketchUp'         => { 'OriginIn' => origin, 'Right' => basis['xaxis'], 'Down' => down,
                                        'Normal' => basis['zaxis'], 'PixelSizeIn' => pixel,
                                        'Cx0In' => frame['cx0'], 'Cy1In' => frame['cy1'], 'EyeIn' => basis['eye'] }
            }
        end

        def self.Na__Export__ToThreePoint(point)
            x, y, z = point.map(&:to_f)
            [x * NA_METRES_PER_INCH, z * NA_METRES_PER_INCH, -y * NA_METRES_PER_INCH]
        end

        def self.Na__Export__ToThreeVector(vector)
            x, y, z = vector.map(&:to_f)
            [x, z, -y]
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals
    # -------------------------------------------------------------------------

        def self.na_refuse(text)
            { 'ok' => false, 'problem' => text.to_s }
        end

        # Every cloud of the plan is still loaded, the same one, in the place the
        # plan was made for.
        def self.na_plan_current?(session, plan)
            slots = self.na_plan_slots(session, plan)
            layers = plan['layers'] || []
            return false if slots.empty? || slots.length != layers.length
            slots.each_with_index.all? do |slot, index|
                cloud = slot.cloud
                cloud && cloud.native_cloud && Na__NativeEngine.Na__Native__CloudLive?(cloud.native_cloud) &&
                    cloud.native_generation == plan['nativeGeneration'] &&
                    cloud.native_generation == Na__NativeEngine.Na__Native__Generation &&
                    cloud.local_to_model == layers[index]['localToModel']
            end
        end

        # The slots of the plan's layers, in its order (nil ones left out).
        def self.na_plan_slots(session, plan)
            Array(plan['cloudIds']).map { |id| Na__CloudSet.Na__Slots__Find(session, id) }.compact
        end

        # [[{ 'slot', 'entry' }], nil] for every cloud the scene shows, in the
        # model's order, or [nil, why the scene cannot be exported].
        def self.na_layers(session, scene, name)
            entries = scene['clouds'] || {}
            shown = Na__CloudSet.Na__Slots__All(session).select { |slot| entries[slot.id] && entries[slot.id]['visible'] != false }
            return [nil, "No point cloud is shown in \"#{name}\". Switch one on in the viewer, update the scene, then export again."] if shown.empty?
            missing = shown.reject { |slot| slot.cloud && slot.cloud.native_cloud && slot.cloud.bounds }
            unless missing.empty?
                names = missing.map(&:name)
                single = Na__CloudSet.Na__Slots__All(session).length == 1
                return [nil, single ? 'No point cloud is loaded. Reload Point Cloud in the viewer, then export again.' :
                                      "#{names.join(' and ')} #{names.length == 1 ? 'is' : 'are'} not loaded. Reload in the viewer (View tab), then export again."]
            end
            return [nil, "\"#{name}\" shows #{shown.length} point clouds; at most #{Na__NativeEngine::NA_MAX_LAYERS} can be drawn at once."] if shown.length > Na__NativeEngine::NA_MAX_LAYERS
            [shown.map { |slot| { 'slot' => slot, 'entry' => entries[slot.id] } }, nil]
        end

        # What the plan keeps about one layer.
        def self.na_layer_record(layer)
            slot  = layer['slot']
            entry = layer['entry']
            cloud = slot.cloud
            clip  = entry['clip'] && entry['clip']['enabled'] ? entry['clip'] : nil
            mode  = (entry['display'] || {})['colourMode'].to_s
            mode  = 'rgb' unless %w[black cloud].include?(mode)
            colour = Na__ImageRenderer.Na__Image__ColourParams(slot, mode)
            {
                'cloudId'        => slot.id,
                'name'           => slot.name,
                'colourMode'     => mode,
                'monoRgb'        => colour[1, 3],
                'opacityPercent' => (entry['display'] || {})['opacityPercent'].to_i,
                'clip'           => clip ? { 'min' => clip['min'], 'max' => clip['max'] } : nil,
                'localToModel'   => cloud.local_to_model,
                'cloud'          => self.na_cloud_record(slot, cloud)
            }
        end

        def self.na_config(options)
            read = ->(key, fallback) { (options[key] || Na__SceneStore.Na__Scenes__Config('export', key) || fallback) }
            {
                'pxPerPaperMm'   => [[read.call('pxPerPaperMm', 12).to_f, 1.0].max, 40.0].min,
                'tileSizePx'     => [[read.call('tileSizePx', 2048).to_i, 256].max, 8192].min,
                'maxMegapixels'  => [[read.call('maxMegapixels', 160).to_f, 1.0].max, 1000.0].min,
                'framePaddingPx' => [[read.call('framePaddingPx', 4).to_f, 0.0].max, 64.0].min
            }
        end

        # The perspective frame: the camera's whole view at the scene's image
        # width and saved aspect ratio (fixed when the scene was saved, so the
        # same export comes out of either computer).
        def self.na_perspective_frame(scene, camera, config)
            aspect = camera.aspect_ratio.to_f > 0 ? camera.aspect_ratio.to_f : scene.dig('view', 'aspect').to_f
            aspect = 1.5 unless aspect > 0.05 && aspect < 20
            width = (scene.dig('export', 'imageWidthPx') || Na__SceneStore.Na__Scenes__Config('defaultImageWidthPx') || 4000).to_i
            height = [(width / aspect).round, 1].max
            factor = nil
            if width * height > config['maxMegapixels'] * 1_000_000.0
                factor = Math.sqrt(config['maxMegapixels'] * 1_000_000.0 / (width * height)) * 0.98
                width = [(width * factor).floor, 1].max
                height = [(width / aspect).round, 1].max
            end
            exact = width.to_f / height                                 # the image's own aspect, after rounding
            t = Math.tan(camera.fov.to_f * Math::PI / 360.0)
            return { 'problem' => 'The scene camera has no usable field of view.' } unless t > 1e-6 && t.finite?
            if camera.fov_is_height?
                scale_x, scale_y = 1.0 / (t * exact), 1.0 / t
                fov_v = camera.fov.to_f
            else
                scale_x, scale_y = 1.0 / t, exact / t
                fov_v = 2.0 * Math.atan(t / exact) * 180.0 / Math::PI
            end
            frame = { 'kind' => 'perspective', 'widthPx' => width, 'heightPx' => height, 'aspect' => exact,
                      'scaleX' => scale_x, 'scaleY' => scale_y, 'fovVerticalDeg' => fov_v }
            frame['pointSizeFactor'] = factor if factor
            frame
        end

        # Each layer's cloud box, cut by its clip box in the scene when it clips,
        # joined. nil when no layer's box and clip box overlap.
        def self.na_visible_bounds(layers)
            boxes = layers.map do |layer|
                box = layer['slot'].cloud.bounds
                lo = box.min.to_a.map(&:to_f)
                hi = box.max.to_a.map(&:to_f)
                clip = layer['entry']['clip']
                if clip && clip['enabled']
                    lo = (0..2).map { |i| [lo[i], clip['min'][i].to_f].max }
                    hi = (0..2).map { |i| [hi[i], clip['max'][i].to_f].min }
                    next nil unless (0..2).all? { |i| hi[i] > lo[i] }
                end
                [lo, hi]
            end.compact
            return nil if boxes.empty?
            [(0..2).map { |i| boxes.map { |box| box[0][i] }.min }, (0..2).map { |i| boxes.map { |box| box[1][i] }.max }]
        end

        def self.na_cloud_record(slot, cloud)
            part = slot.record && slot.record['link'].is_a?(Hash) ? slot.record['link'] : {}
            {
                'cloudId'     => slot.id,
                'name'        => slot.name,
                'fileName'    => part['fileName'] || File.basename(cloud.source_path.to_s),
                'contentKey'  => part['contentKey'] || (cloud.las_info || {})['contentKey'],
                'fingerprint' => part['fingerprint'],
                'totalPoints' => cloud.total_points.to_i,
                'sourceUnit'  => cloud.source_unit
            }
        rescue StandardError
            { 'cloudId' => slot.id, 'fileName' => File.basename(cloud.source_path.to_s), 'totalPoints' => cloud.total_points.to_i }
        end

        # Floats rounded so float noise never changes a revision key.
        def self.na_rounded(value)
            case value
            when Float then value.round(6)
            when Array then value.map { |item| self.na_rounded(item) }
            when Hash  then value.keys.sort.each_with_object({}) { |key, hash| hash[key] = self.na_rounded(value[key]) }
            else value
            end
        end

        def self.na_sub(a, b)
            [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
        end

        def self.na_dot(a, b)
            a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
