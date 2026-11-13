# =============================================================================
# NA NOBLE3D MODELLING TOOLS - TO SCALE ORTHO TEXTURE MAKER - POINT CLOUD ORTHO BUTTON
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__ToScaleOrthoTextureMaker__PointCloudOrthoButton__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__ToScaleOrthoTextureMaker__PointCloudOrthoButton
# PURPOSE    : The Ortho tab's Point Cloud Ortho Plane button (13-Nov-2026): reads
#              the dialog's settings (millimetres), works out the frame from the
#              mode, and calls the ONE build path,
#              Na__ToScaleOrthoTextureMaker__PointCloudOrtho__Make, exactly as the
#              Na SketchUp MCP tool point_cloud_ortho_plane does.
#
# MODES:
# - view : the current view, which must be in Parallel Projection (a scene such
#          as PC__Topdown, or a standard view). The picture is what it shows.
# - face : click a face (nested groups too); the picture is square to it, the
#          face plus a margin.
# - wall : click two points along a wall face in plan, then a point on the side
#          you look from. The picture runs the wall's length plus a margin, and
#          as high as the cloud reaches in the slab.
# - clip : the active cloud's clip box, level or turned (viewer 0.14.8): the
#          picture is square to its front face, its size and slab the box's.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__ToScaleOrthoTextureMaker__PointCloudOrthoButton

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_MM = 25.4 unless const_defined?(:NA_MM)
        NA_MODES = %w[view face wall clip].freeze unless const_defined?(:NA_MODES)
        NA_FACE_MARGIN_MM = 250.0 unless const_defined?(:NA_FACE_MARGIN_MM)
        NA_WALL_MARGIN_MM = 500.0 unless const_defined?(:NA_WALL_MARGIN_MM)

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Run the Button With the Dialog's Settings
        # ------------------------------------------------------------
        # settings (from the dialog): mode, behind_mm, front_mm, resolution_mm,
        # fill, background, placement, offset_mm, name. Reports through
        # report.call(type, message): 'busy' while a pick waits, then 'success'
        # or 'error'.
        def self.Na__ToScaleOrthoTextureMaker__PointCloudOrthoButton__Run(settings, report)
            core = Na__ToScaleOrthoTextureMaker__PointCloudOrtho
            available, reason = core.Na__ToScaleOrthoTextureMaker__PointCloudOrtho__Available
            return report.call('error', reason) unless available

            mode = settings['mode'].to_s
            return report.call('error', "Unknown mode '#{mode}'.") unless NA_MODES.include?(mode)

            case mode
            when 'view'
                frame, u, v = core.Na__ToScaleOrthoTextureMaker__PointCloudOrtho__FrameCamera(Sketchup.active_model.active_view)
                na_make(settings, frame, u, v, report)
            when 'face'
                report.call('busy', 'Click a face to square the picture to it (Esc cancels).')
                Sketchup.active_model.select_tool(Na__PickTool.new('face') { |picked| na_from_face(settings, picked, report) })
            when 'wall'
                report.call('busy', 'Click two points along the wall face in plan, then one on the side you look from (Esc cancels).')
                Sketchup.active_model.select_tool(Na__PickTool.new('wall') { |picked| na_from_wall(settings, picked, report) })
            when 'clip'
                frame, u, v, depth, cloud_name = core.Na__ToScaleOrthoTextureMaker__PointCloudOrtho__FrameClip
                settings = settings.merge('name' => "#{cloud_name.gsub(/\W+/, '')}ClipBox") if settings['name'].to_s.strip.empty?
                na_make(settings, frame, u, v, report, depth)
            end
        rescue Na__PointCloudOrthoError => error
            report.call('error', na_error_text(error))
        rescue StandardError => error
            report.call('error', "Point Cloud Ortho Plane failed: #{error.class}: #{error.message}")
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | From a Pick to a Plane
# -----------------------------------------------------------------------------

        def self.na_from_face(settings, picked, report)
            core = Na__ToScaleOrthoTextureMaker__PointCloudOrtho
            frame, u, v = core.Na__ToScaleOrthoTextureMaker__PointCloudOrtho__FrameFace(picked[:points], picked[:normal], picked[:direction], NA_FACE_MARGIN_MM / NA_MM)
            na_make(settings, frame, u, v, report)
        rescue Na__PointCloudOrthoError => error
            report.call('error', na_error_text(error))
        rescue StandardError => error
            report.call('error', "Point Cloud Ortho Plane failed: #{error.class}: #{error.message}")
        end

        def self.na_from_wall(settings, picked, report)
            core = Na__ToScaleOrthoTextureMaker__PointCloudOrtho
            frame, length = core.Na__ToScaleOrthoTextureMaker__PointCloudOrtho__FrameWall(picked[:a].to_a, picked[:b].to_a, picked[:side].to_a)
            margin = NA_WALL_MARGIN_MM / NA_MM
            u = [-margin, length + margin]
            report.call('busy', 'Finding how high the cloud reaches along the wall...')
            v = core.Na__ToScaleOrthoTextureMaker__PointCloudOrtho__AutoV(frame, u, na_depth(settings))
            na_make(settings, frame, u, v, report)
        rescue Na__PointCloudOrthoError => error
            report.call('error', na_error_text(error))
        rescue StandardError => error
            report.call('error', "Point Cloud Ortho Plane failed: #{error.class}: #{error.message}")
        end

        def self.na_make(settings, frame, u, v, report, depth = nil)
            core = Na__ToScaleOrthoTextureMaker__PointCloudOrtho
            report.call('busy', 'Capturing the point cloud...')
            spec = {
                'frame'      => frame,
                'u'          => u,
                'v'          => v,
                'depth'      => depth || na_depth(settings),
                'resolution' => na_mm(settings['resolution_mm'], 10.0),
                'fill'       => settings['fill'] != false,
                'background' => settings['background'].to_s.empty? ? 'white' : settings['background'].to_s,
                'placement'  => settings['placement'].to_s.empty? ? 'front' : settings['placement'].to_s,
                'offset'     => na_mm(settings['offset_mm'], 0.0),
                'name'       => settings['name'].to_s
            }
            result = core.Na__ToScaleOrthoTextureMaker__PointCloudOrtho__Make(spec)
            report.call('success', na_success_text(result))
            result
        end

        def self.na_depth(settings)
            [na_mm(settings['behind_mm'], 1000.0), na_mm(settings['front_mm'], 1000.0)]
        end

        def self.na_mm(value, fallback)
            number = value.is_a?(Numeric) ? value.to_f : (value.to_s.strip.empty? ? fallback : Float(value.to_s))
            number / NA_MM
        rescue ArgumentError
            fallback / NA_MM
        end

        def self.na_success_text(result)
            mm = ->(inches) { (inches.to_f * NA_MM).round }
            front = Array(result['in_front_of'])
            parts = []
            parts << "Made #{result['name']}" if result['placed']
            parts << "#{result['pixels'][0]} x #{result['pixels'][1]} px at #{(result['resolution'].to_f * NA_MM).round(2)} mm a pixel"
            parts << "dots #{result['dot_px'].to_f.round(1)} px" if result['dot_px']
            parts << "#{result['pixels_covered_percent']}% covered"
            parts << (front.empty? ? 'on its own plane' : "#{mm.call(result['plane_depth'])} mm out, in front of #{front.join(', ')}") if result['placed']
            parts << "pixel map within #{result['calibration_px']} px" if result['calibration_px']
            text = parts.join('; ') + ". Saved #{File.basename(result['png'].to_s)}."
            Array(result['warnings']).each { |warning| text += " Note: #{warning}" }
            text
        end

        def self.na_error_text(error)
            hint = error.respond_to?(:na_hint) && error.na_hint ? " #{error.na_hint}" : ''
            "#{error.message}#{hint}"
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Pick Tool (a face, or a wall by three clicks)
# -----------------------------------------------------------------------------

        class Na__PickTool
            def initialize(mode, &done)
                @mode = mode
                @done = done
                @ip = Sketchup::InputPoint.new
                @points = []
            end

            def activate
                na_status
                Sketchup.active_model.active_view.invalidate
            end

            def deactivate(view)
                view.invalidate
            end

            def resume(view)
                na_status
                view.invalidate
            end

            def onCancel(_reason, view)
                if @points.empty?
                    Sketchup.active_model.select_tool(nil)
                else
                    @points.clear
                    na_status
                end
                view.invalidate
            end

            def onMouseMove(_flags, x, y, view)
                @ip.pick(view, x, y)
                view.tooltip = @ip.tooltip if @ip.valid?
                view.invalidate
            end

            def onLButtonDown(_flags, x, y, view)
                @mode == 'face' ? na_pick_face(x, y, view) : na_pick_wall_point(x, y, view)
            end

            def draw(view)
                @ip.draw(view) if @ip.display?
                return if @mode == 'face'

                points = @points + (@ip.valid? && @points.length < 3 ? [@ip.position] : [])
                return if points.length < 2

                view.line_width = 2
                view.drawing_color = 'red'
                view.draw(GL_LINE_STRIP, points[0, 2])
                return unless points.length >= 3

                middle = Geom.linear_combination(0.5, points[0], 0.5, points[1])
                view.drawing_color = 'blue'
                view.draw(GL_LINES, [middle, points[2]])
            end

            def getExtents
                box = Geom::BoundingBox.new
                @points.each { |point| box.add(point) }
                box.add(@ip.position) if @ip.valid?
                box
            end

            def na_pick_face(x, y, view)
                helper = view.pick_helper
                helper.do_pick(x, y)
                face = helper.picked_face
                return UI.beep unless face

                transformation = Geom::Transformation.new
                helper.count.times do |index|
                    next unless helper.leaf_at(index) == face

                    transformation = helper.transformation_at(index)
                    break
                end
                points = face.outer_loop.vertices.map { |vertex| vertex.position.transform(transformation) }
                normal = face.normal.transform(transformation)
                direction = view.camera.direction
                Sketchup.active_model.select_tool(nil)
                @done.call(points: points, normal: normal, direction: direction)
            end

            def na_pick_wall_point(x, y, view)
                @ip.pick(view, x, y)
                return UI.beep unless @ip.valid?

                @points << @ip.position
                if @points.length == 3
                    picked = { a: @points[0], b: @points[1], side: @points[2] }
                    Sketchup.active_model.select_tool(nil)
                    @done.call(picked)
                else
                    na_status
                    view.invalidate
                end
            end

            def na_status
                Sketchup.status_text = if @mode == 'face'
                                           'Point Cloud Ortho Plane: click a face. Esc cancels.'
                                       else
                                           ['Point Cloud Ortho Plane: click the first end of the wall face.',
                                            'Click the other end of the wall face.',
                                            'Click a point on the side you look from.'][@points.length].to_s + ' Esc starts again.'
                                       end
            end
        end

# endregion -------------------------------------------------------------------

    end # module Na__ToScaleOrthoTextureMaker__PointCloudOrthoButton
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
