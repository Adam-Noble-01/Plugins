# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - THREE-POINT OPENING TOOL
# =============================================================================
#
# FILE       : Na__AssemblyStudio__MeasurementTools__ThreePointOpeningTool__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__MeasurementTools
# CLASS      : Na__ThreePointOpeningTool
# AUTHOR     : Noble Architecture
# PURPOSE    : SketchUp Tool — three successive picks capture opening width /
#              height plus wall depth, then notifies a dialog host callback.
#
# DESCRIPTION:
# - State machine: picking A → B (defines façade rectangle) → depth (orthogonal).
# - On-screen overlays: axis crosshair, blue W×H quad, red depth prism preview.
# - Callback symbols and status label merged from DEFAULT_CALLBACKS + ctor hash.
#
# REFACTOR NOTES (v2 / EASP)
# - Host callbacks + status_label are configurable; defaults match door protocol.
#
# NAMING CONVENTION:
# - Class Na__ThreePointOpeningTool; instance helpers prefixed na_*
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__AssemblyStudio__MeasurementTools__TwoPointOpeningTool__'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'

module Na__AssemblyStudio
    module Na__MeasurementTools

        class Na__ThreePointOpeningTool

# -----------------------------------------------------------------------------
# REGION | Module References — Constants — Default Callbacks
# -----------------------------------------------------------------------------

            DebugTools = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools

            NA_MM_TO_INCH           = 1.0 / 25.4
            NA_INCH_TO_MM           = 25.4

            NA_BLUE_FILL_COLOR      = Sketchup::Color.new(  0, 120, 255,  80)
            NA_BLUE_BORDER_COLOR    = Sketchup::Color.new(  0, 120, 255, 200)
            NA_RED_FILL_COLOR       = Sketchup::Color.new(220,  40,  40, 100)
            NA_RED_BORDER_COLOR     = Sketchup::Color.new(220,  40,  40, 220)

            NA_POINT_A_COLOR        = Sketchup::Color.new(  0, 200,   0)
            NA_DIMENSION_TEXT_COLOR = Sketchup::Color.new(255, 255, 255)
            NA_CROSSHAIR_SIZE       = 100.mm
            NA_GRID_SIZE            = 1.mm

            DEFAULT_CALLBACKS = {
                :complete     => :na_send_door_measurement_to_dialog,
                :cancel       => :na_send_door_measure_cancelled_to_dialog,
                :status_label => 'Measure Door Opening'
            }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | SketchUp Tool API — Instantiate & Life Cycle
# -----------------------------------------------------------------------------

            # FUNCTION | Attach host + merged callback routing + initialise state
            # ------------------------------------------------------------
            def initialize(dialog_host, callbacks: {})
                @dialog_host = dialog_host
                merged       = DEFAULT_CALLBACKS.merge(callbacks)
                @cb_complete  = merged[:complete]
                @cb_cancel    = merged[:cancel]
                @status_label = merged[:status_label]

                @ip            = Sketchup::InputPoint.new
                @point_a       = nil
                @point_b       = nil
                @current_point = nil
                @depth_point   = nil
                @wall_axis     = nil
                @state         = :picking_a

                DebugTools.na_debug_method("ThreePointOpeningTool initialized (complete_cb=#{@cb_complete})")
            end
            # ---------------------------------------------------------------

            def activate
                @state = :picking_a
                na_update_status_text
                Sketchup.active_model.active_view.invalidate
            end

            def deactivate(view); view.invalidate; end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | SketchUp Tool API — Mouse & Cancel
# -----------------------------------------------------------------------------

            def onMouseMove(_flags, x, y, view)
                @ip.pick(view, x, y)
                return unless @ip.valid?
                @current_point = na_round_to_grid(@ip.position)
                na_update_status_text
                view.invalidate
            end

            def onLButtonDown(_flags, x, y, view)
                @ip.pick(view, x, y)
                return unless @ip.valid?
                clicked_point = na_round_to_grid(@ip.position)

                case @state
                when :picking_a
                    @point_a   = clicked_point
                    @state     = :picking_b
                    DebugTools.na_debug_measure("Point A: #{na_point_to_mm_string(@point_a)}")
                when :picking_b
                    @point_b   = clicked_point
                    @wall_axis = na_compute_wall_axis(@point_a, @point_b)
                    @state     = :picking_depth
                    DebugTools.na_debug_measure("Point B: #{na_point_to_mm_string(@point_b)} (wall_axis=#{@wall_axis})")
                when :picking_depth
                    @depth_point = na_constrain_depth_point(clicked_point)
                    DebugTools.na_debug_measure("Depth: #{na_point_to_mm_string(@depth_point)}")
                    na_complete_measurement
                    Sketchup.active_model.select_tool(nil)
                end

                na_update_status_text
                view.invalidate
            end

            def onCancel(_reason, view)
                DebugTools.na_debug_measure('Three-point measure cancelled')
                @dialog_host.public_send(@cb_cancel) if @dialog_host.respond_to?(@cb_cancel)
                view.invalidate
            end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | SketchUp Tool API — Draw & Selection Extents
# -----------------------------------------------------------------------------

            def draw(view)
                if @state == :picking_a && @current_point
                    na_draw_crosshair(view, @current_point)
                    return
                end

                if @state == :picking_b && @point_a && @current_point
                    rect_pts = na_calculate_rect_points(@point_a, @current_point)
                    na_draw_filled_quad(view, rect_pts, NA_BLUE_FILL_COLOR, NA_BLUE_BORDER_COLOR)
                    na_draw_crosshair(view, @point_a, NA_POINT_A_COLOR)
                    na_draw_dimension_text_wh(view, @point_a, @current_point)
                    return
                end

                if @state == :picking_depth && @point_a && @point_b && @current_point
                    base_rect_pts = na_calculate_rect_points(@point_a, @point_b)
                    depth_target  = na_constrain_depth_point(@current_point)
                    box_pts_top   = na_offset_rect_to_depth(base_rect_pts, depth_target)
                    na_draw_filled_box(view, base_rect_pts, box_pts_top, NA_RED_FILL_COLOR, NA_RED_BORDER_COLOR)
                    na_draw_crosshair(view, @point_a, NA_POINT_A_COLOR)
                    na_draw_dimension_text_whd(view, @point_a, @point_b, depth_target)
                end
            end

            def getExtents
                bb = Geom::BoundingBox.new
                bb.add(@point_a)       if @point_a
                bb.add(@point_b)       if @point_b
                bb.add(@current_point) if @current_point
                bb.add(@depth_point)   if @depth_point
                bb
            end

# endregion -------------------------------------------------------------------

            private

# -----------------------------------------------------------------------------
# REGION | Geometry — Wall Axis — Rectangle — Depth Offset
# -----------------------------------------------------------------------------

            def na_compute_wall_axis(pt_a, pt_b)
                dx = (pt_b.x - pt_a.x).abs
                dy = (pt_b.y - pt_a.y).abs
                (dx >= dy) ? :x : :y
            end

            def na_constrain_depth_point(cursor)
                return cursor unless @point_a && @wall_axis
                if @wall_axis == :x
                    Geom::Point3d.new(@point_a.x, cursor.y, @point_a.z)
                else
                    Geom::Point3d.new(cursor.x, @point_a.y, @point_a.z)
                end
            end

            def na_calculate_rect_points(pt_a, pt_b)
                dx = (pt_b.x - pt_a.x).abs
                dy = (pt_b.y - pt_a.y).abs
                if dx >= dy
                    [
                        Geom::Point3d.new(pt_a.x, pt_a.y, pt_a.z),
                        Geom::Point3d.new(pt_b.x, pt_a.y, pt_a.z),
                        Geom::Point3d.new(pt_b.x, pt_a.y, pt_b.z),
                        Geom::Point3d.new(pt_a.x, pt_a.y, pt_b.z)
                    ]
                else
                    [
                        Geom::Point3d.new(pt_a.x, pt_a.y, pt_a.z),
                        Geom::Point3d.new(pt_a.x, pt_b.y, pt_a.z),
                        Geom::Point3d.new(pt_a.x, pt_b.y, pt_b.z),
                        Geom::Point3d.new(pt_a.x, pt_a.y, pt_b.z)
                    ]
                end
            end

            def na_offset_rect_to_depth(rect_pts, depth_target)
                offset_vec = depth_target - @point_a
                rect_pts.map { |pt| pt.offset(offset_vec) }
            end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Overlay Drawing — Faces — Crosshair — Dimension Labels
# -----------------------------------------------------------------------------

            def na_draw_filled_quad(view, pts, fill, border)
                view.drawing_color = fill
                view.draw(GL_QUADS, pts)
                view.drawing_color = border
                view.line_width    = 2
                view.draw(GL_LINE_LOOP, pts)
            end

            def na_draw_filled_box(view, near, far, fill, border)
                faces = [
                    near, far,
                    [near[0], near[1], far[1], far[0]],
                    [near[1], near[2], far[2], far[1]],
                    [near[2], near[3], far[3], far[2]],
                    [near[3], near[0], far[0], far[3]]
                ]
                view.drawing_color = fill
                faces.each { |face_pts| view.draw(GL_QUADS, face_pts) }
                view.drawing_color = border
                view.line_width    = 2
                view.draw(GL_LINE_LOOP, near)
                view.draw(GL_LINE_LOOP, far)
                4.times { |i| view.draw_line(near[i], far[i]) }
            end

            def na_draw_crosshair(view, point, color = nil)
                size                 = NA_CROSSHAIR_SIZE * 0.5
                view.line_width      = 1
                view.drawing_color   = color || Sketchup::Color.new(255, 0, 0)
                view.draw_line(point.offset(X_AXIS, -size), point.offset(X_AXIS, size))
                view.drawing_color   = color || Sketchup::Color.new(0, 255, 0)
                view.draw_line(point.offset(Y_AXIS, -size), point.offset(Y_AXIS, size))
                view.drawing_color   = color || Sketchup::Color.new(0, 0, 255)
                view.draw_line(point.offset(Z_AXIS, -size), point.offset(Z_AXIS, size))
            end

            def na_draw_dimension_text_wh(view, pt_a, pt_b)
                width_mm, height_mm = na_calculate_wh_mm(pt_a, pt_b)
                label = "W: #{width_mm}mm  |  H: #{height_mm}mm"
                screen_pt = view.screen_coords(pt_b)
                view.drawing_color = NA_DIMENSION_TEXT_COLOR
                view.draw_text(Geom::Point3d.new(screen_pt.x + 15, screen_pt.y - 25, 0), label)
            end

            def na_draw_dimension_text_whd(view, pt_a, pt_b, pt_d)
                width_mm, height_mm = na_calculate_wh_mm(pt_a, pt_b)
                depth_mm  = na_calculate_depth_mm(pt_a, pt_d)
                label     = "W:#{width_mm}mm  H:#{height_mm}mm  D:#{depth_mm}mm"
                screen_pt = view.screen_coords(pt_d)
                view.drawing_color = NA_DIMENSION_TEXT_COLOR
                view.draw_text(Geom::Point3d.new(screen_pt.x + 15, screen_pt.y - 25, 0), label)
            end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Derived Dimensions — mm
# -----------------------------------------------------------------------------

            def na_calculate_wh_mm(pt_a, pt_b)
                dx = (pt_b.x - pt_a.x).abs
                dy = (pt_b.y - pt_a.y).abs
                dz = (pt_b.z - pt_a.z).abs
                width_in  = [dx, dy].max
                height_in = dz
                [(width_in * NA_INCH_TO_MM).round, (height_in * NA_INCH_TO_MM).round]
            end

            def na_calculate_depth_mm(pt_a, pt_d)
                depth_in = (@wall_axis == :x) ? (pt_d.y - pt_a.y).abs : (pt_d.x - pt_a.x).abs
                (depth_in * NA_INCH_TO_MM).round
            end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Status Line — Snap Grid — Payload Dispatch
# -----------------------------------------------------------------------------

            def na_update_status_text
                case @state
                when :picking_a
                    Sketchup.status_text = "#{@status_label}: Click Point A (base corner) | ESC to cancel"
                when :picking_b
                    if @current_point
                        w, h = na_calculate_wh_mm(@point_a, @current_point)
                        Sketchup.status_text = "#{@status_label}: Click Point B | W:#{w}mm H:#{h}mm | ESC to cancel"
                    else
                        Sketchup.status_text = "#{@status_label}: Move cursor to set Point B | ESC to cancel"
                    end
                when :picking_depth
                    if @current_point
                        constrained = na_constrain_depth_point(@current_point)
                        w, h = na_calculate_wh_mm(@point_a, @point_b)
                        d    = na_calculate_depth_mm(@point_a, constrained)
                        Sketchup.status_text = "#{@status_label}: Click for wall depth | W:#{w}mm H:#{h}mm D:#{d}mm | ESC to cancel"
                    else
                        Sketchup.status_text = "#{@status_label}: Move cursor along wall depth axis | ESC to cancel"
                    end
                end
            end

            # Snap to a `NA_GRID_SIZE` lattice expressed in the active
            # drawing-axes frame so a user-rotated axes tripod (e.g.
            # aligned to an angled wall) gets a snap grid that follows
            # the wall rather than world XYZ.
            def na_round_to_grid(point)
                axes_xform = na_axes_transform
                local_pt   = point.transform(axes_xform.inverse)
                snapped_loc = Geom::Point3d.new(
                    (local_pt.x / NA_GRID_SIZE).round * NA_GRID_SIZE,
                    (local_pt.y / NA_GRID_SIZE).round * NA_GRID_SIZE,
                    (local_pt.z / NA_GRID_SIZE).round * NA_GRID_SIZE
                )
                snapped_loc.transform(axes_xform)
            end

            def na_axes_transform
                model = Sketchup.active_model
                return Geom::Transformation.new unless model
                model.axes.transformation
            end

            def na_point_to_mm_string(point)
                "X:#{(point.x * NA_INCH_TO_MM).round}mm Y:#{(point.y * NA_INCH_TO_MM).round}mm Z:#{(point.z * NA_INCH_TO_MM).round}mm"
            end

            def na_complete_measurement
                return unless @point_a && @point_b && @depth_point
                width_mm, height_mm = na_calculate_wh_mm(@point_a, @point_b)
                depth_mm            = na_calculate_depth_mm(@point_a, @depth_point)

                DebugTools.na_debug_success(
                    "Three-point complete: W=#{width_mm}mm H=#{height_mm}mm D=#{depth_mm}mm " \
                    "A=(#{(@point_a.x * NA_INCH_TO_MM).round}, #{(@point_a.y * NA_INCH_TO_MM).round}, #{(@point_a.z * NA_INCH_TO_MM).round})mm " \
                    "B=(#{(@point_b.x * NA_INCH_TO_MM).round}, #{(@point_b.y * NA_INCH_TO_MM).round}, #{(@point_b.z * NA_INCH_TO_MM).round})mm " \
                    "D=(#{(@depth_point.x * NA_INCH_TO_MM).round}, #{(@depth_point.y * NA_INCH_TO_MM).round}, #{(@depth_point.z * NA_INCH_TO_MM).round})mm"
                )

                return unless @dialog_host.respond_to?(@cb_complete)
                @dialog_host.public_send(@cb_complete,
                    width_mm, height_mm, depth_mm,
                    @point_a.x,     @point_a.y,     @point_a.z,
                    @point_b.x,     @point_b.y,     @point_b.z,
                    @depth_point.x, @depth_point.y, @depth_point.z
                )
            end

# endregion -------------------------------------------------------------------

        end

    end
end
