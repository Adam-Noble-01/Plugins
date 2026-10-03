# =============================================================================
# NA POINT CLOUD VIEWER - VIEWPORT - IMAGE RENDERER
# =============================================================================
#
# FILE       : Na__PointCloudViewer__Viewport__ImageRenderer__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__ImageRenderer
# PURPOSE    : Draws the cloud as ONE textured screen quad. The native engine
#              rasterises the points for the current camera into a PNG; Ruby
#              loads it as a texture and draws it with view.draw2d.
#
# WHY: SketchUp's own point drawing costs ~2.3 us per point per frame
#   (100k points = 3 fps). A textured quad costs ~0.5 ms at any point count.
#
# FRAME POLICY:
#   - Camera, viewport, settings, clip box and placement unchanged -> reuse the
#     texture. That is every redraw while you model with ordinary tools.
#   - Camera moving, a clip face being dragged, or the cloud being moved or
#     rotated -> half-resolution renders, with at most movingBudgetMax points.
#   - Still for settleSeconds -> one full-resolution render of the full budget.
#
# CROP: the image covers only the screen rectangle of what can be visible
#   (the cloud's box, or its part inside the clip box), not the whole
#   viewport. Every stage scales with pixels: raster resolve, PNG, file, and
#   SketchUp's own decode and upload, which is the largest of them. Off
#   screen: nothing is rendered or drawn.
#
# TEXTURE UVS: plain Arrays. Geom::Vector3d UVs (as the API docs suggest)
# make SketchUp sample the texture's single average colour.
#
# =============================================================================

module Na__PointCloudViewer
    module Na__ImageRenderer

    # -------------------------------------------------------------------------
    # REGION | Constants + State
    # -------------------------------------------------------------------------

        NA_QUAD_UVS = [[0, 1, 0], [1, 1, 0], [1, 0, 0], [0, 0, 0]].freeze   # image row 0 = top
        NA_WHITE    = Sketchup::Color.new(255, 255, 255) unless defined?(NA_WHITE)
        NA_IDENTITY_TRANSFORM = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0].freeze

        class Na__ImageState
            attr_accessor :native_cloud, :image_rep, :texture_id, :texture_view, :rendered_key,
                          :last_camera_key, :last_move_ms, :settle_armed, :png_path, :quad
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Draw
    # -------------------------------------------------------------------------

        def self.Na__Image__Draw(session, view)
            state = self.na_state(session)
            self.na_check_native_cloud(session, state)

            camera_key = self.na_camera_key(view)
            now_ms     = Na__PerfStats.Na__Perf__NowMs
            if state.last_camera_key && camera_key != state.last_camera_key
                state.last_move_ms = now_ms
                self.na_arm_settle(view, state)
            end
            state.last_camera_key = camera_key

            scale = self.na_wanted_scale(state, now_ms)
            key   = [camera_key, self.na_settings_key(session), scale]
            if key != state.rendered_key || !state.texture_view.equal?(view)
                self.na_render_texture(session, view, state, scale)
                state.rendered_key = key
            end
            return unless state.quad && state.texture_id      # the cloud is off screen

            view.drawing_color = NA_WHITE
            view.draw2d(GL_QUADS, state.quad, texture: state.texture_id, uvs: NA_QUAD_UVS)
        end

        # Something other than the camera is changing every frame (a clip face
        # drag, a move or rotate): render at the reduced scale until it settles.
        def self.Na__Image__NoteInteraction(session, view)
            state = self.na_state(session)
            state.last_move_ms = Na__PerfStats.Na__Perf__NowMs
            self.na_arm_settle(view, state)
        end

        def self.Na__Image__Release(session, view)
            state = session.image_state
            return unless state
            view.release_texture(state.texture_id) if view && state.texture_id && state.texture_view.equal?(view)
            state.texture_id   = nil
            state.rendered_key = nil
            state.native_cloud = nil
            state.quad         = nil
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Warn("Image renderer release warning: #{error.message}")
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Render to Texture
    # -------------------------------------------------------------------------

        # Raises when the engine is missing or was swapped since the import: the
        # RenderController turns that into a visible "drawing paused" message.
        def self.na_check_native_cloud(session, state)
            raise Na__NativeEngine.na_unavailable_error unless Na__NativeEngine.Na__Native__EnsureLoaded
            cloud = session.cloud
            if cloud.native_generation != Na__NativeEngine.Na__Native__Generation
                raise 'The native renderer was reloaded after this cloud was imported. Import the LAS again.'
            end
            return if state.native_cloud.equal?(cloud.native_cloud)
            state.native_cloud = cloud.native_cloud
            state.rendered_key = nil
        end

        def self.na_render_texture(session, view, state, scale)
            settings = session.settings
            vw = view.vpwidth.to_f
            vh = view.vpheight.to_f
            rect = self.na_screen_rect(session, view, vw, vh, settings['pointSizePx'].to_f)
            unless rect
                state.quad = nil
                state.texture_view = view
                return
            end

            # Output pixels: the whole view at this scale, and the part rendered.
            full_w = [(vw * scale).round, 1].max
            full_h = [(vh * scale).round, 1].max
            crop_x = [(rect[0] * full_w / vw).floor, 0].max
            crop_y = [(rect[1] * full_h / vh).floor, 0].max
            width  = [[(rect[2] * full_w / vw).ceil, full_w].min - crop_x, 1].max
            height = [[(rect[3] * full_h / vh).ceil, full_h].min - crop_y, 1].max

            params = self.na_camera_params(view.camera, vw, vh) + [
                width, height,
                [settings['pointSizePx'].to_f * scale, 1.0].max,
                settings['opacityPercent'].to_f / 100.0,
                settings['colourMode'] == 'black' ? 1 : 0,
                *Na__ConfigLoader.Na__Config__GetOr([0, 0, 0], 'render', 'monochromeRgb'),
                self.na_budget(session, scale),
                Na__ConfigLoader.Na__Config__GetOr(0.5, 'render', 'nativeImage', 'nearInches').to_f
            ] + (session.cloud.local_to_model || NA_IDENTITY_TRANSFORM) + Na__ClipBox.Na__Clip__RenderParams(session) +
                [full_w, full_h, crop_x, crop_y]

            Na__NativeEngine.Na__Native__RenderPng(state.native_cloud, params, self.na_png_path(state))
            state.image_rep ||= Sketchup::ImageRep.new
            state.image_rep.load_file(state.png_path)
            texture = view.load_texture(state.image_rep)
            view.release_texture(state.texture_id) if state.texture_id && state.texture_view.equal?(view)
            state.texture_id   = texture
            state.texture_view = view
            # Image pixels back to view coordinates.
            x0 = crop_x * vw / full_w
            y0 = crop_y * vh / full_h
            x1 = (crop_x + width) * vw / full_w
            y1 = (crop_y + height) * vh / full_h
            state.quad = [Geom::Point3d.new(x0, y0, 0), Geom::Point3d.new(x1, y0, 0), Geom::Point3d.new(x1, y1, 0), Geom::Point3d.new(x0, y1, 0)]
        end

        # The settled frame draws the whole budget; a moving one at most
        # movingBudgetMax (still an even sample: points are stored shuffled).
        def self.na_budget(session, scale)
            budget = [session.settings['pointBudget'].to_i, session.cloud.total_points].min
            full = Na__ConfigLoader.Na__Config__GetOr(1.0, 'render', 'nativeImage', 'fullScale').to_f
            return budget if scale >= full
            cap = Na__ConfigLoader.Na__Config__GetOr(0, 'render', 'nativeImage', 'movingBudgetMax').to_i
            cap > 0 ? [budget, cap].min : budget
        end

        # View rectangle [x0, y0, x1, y1] that can hold visible points: the box
        # of the cloud (or of its part inside the clip box) projected, plus the
        # point size. The whole view when only some corners are behind the
        # camera (no safe rectangle then); nil when the box is entirely behind
        # the camera or off screen.
        def self.na_screen_rect(session, view, vw, vh, size_px)
            bounds = Na__RenderController.na_visible_bounds(session)
            whole = [0.0, 0.0, vw, vh]
            return whole unless bounds && !bounds.empty?
            lo = bounds.min.to_a
            hi = bounds.max.to_a
            camera = view.camera
            eye = camera.eye.to_a
            axis = camera.zaxis.to_a
            near = Na__ConfigLoader.Na__Config__GetOr(0.5, 'render', 'nativeImage', 'nearInches').to_f
            corners = [0, 1].product([0, 1], [0, 1]).map do |ix, iy, iz|
                [ix.zero? ? lo[0] : hi[0], iy.zero? ? lo[1] : hi[1], iz.zero? ? lo[2] : hi[2]]
            end
            if camera.perspective?
                behind = corners.count { |corner| (0..2).sum { |i| (corner[i] - eye[i]) * axis[i] } <= near }
                return nil if behind == corners.length
                return whole if behind > 0
            end
            xs = []
            ys = []
            corners.each do |corner|
                screen = view.screen_coords(Geom::Point3d.new(*corner))
                xs << screen.x
                ys << screen.y
            end
            pad = size_px + 2.0
            x0 = [xs.min - pad, 0.0].max
            y0 = [ys.min - pad, 0.0].max
            x1 = [xs.max + pad, vw].min
            y1 = [ys.max + pad, vh].min
            x1 > x0 && y1 > y0 ? [x0, y0, x1, y1] : nil
        end

        # Same maths verified against View#screen_coords (0.0 px error).
        def self.na_camera_params(camera, vw, vh)
            aspect = camera.aspect_ratio.to_f > 0.0 ? camera.aspect_ratio.to_f : vw / vh
            if camera.perspective?
                t = Math.tan(camera.fov.to_f * Math::PI / 360.0)
                sx, sy = camera.fov_is_height? ? [1.0 / (t * aspect), 1.0 / t] : [1.0 / t, aspect / t]
            else
                half = camera.height.to_f / 2.0
                sx, sy = 1.0 / (half * aspect), 1.0 / half
            end
            camera.eye.to_a + camera.xaxis.to_a + camera.yaxis.to_a + camera.zaxis.to_a +
                [camera.perspective? ? 1 : 0, sx, sy]
        end

        def self.na_png_path(state)
            state.png_path ||= begin
                folder = File.join(Na__AssetResolver.Na__Paths__CacheFolder, '00__RenderScratch')
                FileUtils.mkdir_p(folder)
                File.join(folder, "Na__PointCloudViewer__Frame__#{Process.pid}__#{state.object_id}.png")
            end
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Keys, Scale, Settle Timer
    # -------------------------------------------------------------------------

        def self.na_camera_key(view)
            camera = view.camera
            key = camera.eye.to_a + camera.target.to_a + camera.up.to_a + [camera.perspective?, view.vpwidth, view.vpheight]
            key << (camera.perspective? ? camera.fov : camera.height)
            key
        end

        def self.na_settings_key(session)
            settings = session.settings
            [settings['pointSizePx'], settings['opacityPercent'], settings['colourMode'], settings['pointBudget'],
             session.cloud.object_id, session.cloud.local_to_model, Na__ClipBox.Na__Clip__Key(session)]
        end

        def self.na_wanted_scale(state, now_ms)
            full    = Na__ConfigLoader.Na__Config__GetOr(1.0, 'render', 'nativeImage', 'fullScale').to_f
            reduced = Na__ConfigLoader.Na__Config__GetOr(0.5, 'render', 'nativeImage', 'movingScale').to_f
            settle  = Na__ConfigLoader.Na__Config__GetOr(0.25, 'render', 'nativeImage', 'settleSeconds').to_f * 1000.0
            state.last_move_ms && (now_ms - state.last_move_ms) < settle ? reduced : full
        end

        # One pending timer at a time; when it fires after things have been still
        # long enough, invalidate so draw renders the full-scale frame.
        def self.na_arm_settle(view, state)
            return if state.settle_armed
            state.settle_armed = true
            settle = Na__ConfigLoader.Na__Config__GetOr(0.25, 'render', 'nativeImage', 'settleSeconds').to_f
            UI.start_timer(settle, false) { Na__PointCloudViewer::Na__ImageRenderer.na_settle_tick(view, state) }
        end

        def self.na_settle_tick(view, state)
            state.settle_armed = false
            settle_ms = Na__ConfigLoader.Na__Config__GetOr(0.25, 'render', 'nativeImage', 'settleSeconds').to_f * 1000.0
            if state.last_move_ms && Na__PerfStats.Na__Perf__NowMs - state.last_move_ms < settle_ms
                self.na_arm_settle(view, state)
            else
                state.last_move_ms = nil
                view.invalidate
            end
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Warn("Settle timer warning: #{error.message}")
        end

        def self.na_state(session)
            session.image_state ||= Na__ImageState.new
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
