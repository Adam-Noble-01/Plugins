# =============================================================================
# NA MEASUREMENT TOOLS - TWO-POINT OPENING TOOL
# =============================================================================
#
# FILE       : Na__MeasurementTools__TwoPointOpeningTool__.rb
# NAMESPACE  : Na__MeasurementTools
# AUTHOR     : Noble Architecture
# PURPOSE    : Tool-agnostic two-click measurement tool for wall openings.
# CREATED    : 01-May-2026
#
# DESCRIPTION:
# - Captures Point A (base corner) and Point B (opposite corner) of a
#   rectangular opening in the SketchUp viewport.
# - Calculates width along the dominant horizontal axis and height along Z.
# - Sends the resulting measurement back to a host module by calling
#   `host.na_send_measurement_to_dialog(width_mm, adjusted_height_mm, ax, ay, az)`.
# - Uses a tool-agnostic DebugTools resolver so the same module can be
#   shared between the Window Configurator and the Interior Door
#   Configurator without depending on either tool's logger directly.
#
# RELOCATION HISTORY:
# - 0.11.4 (01-May-2026) : Forked from
#       Na__WindowConfiguratorTool__MeasureOpeningTool__.rb
#       and re-namespaced under Na__MeasurementTools so any sibling tool
#       can instantiate it without a circular require on the window tool.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'

# -----------------------------------------------------------------------------
# REGION | Tool-Agnostic Logger Resolver
# -----------------------------------------------------------------------------
# The original tools each depended directly on their host's DebugTools
# module. Now that the measurement tools live outside both sibling tools,
# we wrap whichever DebugTools module loaded first in a thin proxy class
# that:
#   1. Forwards calls to the real DebugTools when the underlying method
#      exists (so debug output still routes through the host's prefixes).
#   2. Silently swallows calls that the real DebugTools does not support
#      (e.g. the window logger has no na_debug_measure / na_debug_door,
#      and the door logger has no na_debug_window / na_debug_placement).
#   3. Never raises, so a future host that adds new specialised debug
#      method names cannot break the measurement tools.
# This makes the tools genuinely tool-agnostic regardless of load order.
# -----------------------------------------------------------------------------

module Na__MeasurementTools

# =============================================================================
# REGION | Internal Logger Proxy Class
# =============================================================================

    # CLASS | Tool-Agnostic DebugTools Proxy
    # ------------------------------------------------------------
    # Forwards all `na_debug_*` calls to the wrapped DebugTools module
    # when implemented, otherwise silently no-ops. Implements
    # respond_to_missing? so callers querying capability also see the
    # proxy as fully featured.
    class Na__DebugToolsProxy

        # FUNCTION | Initialize the Proxy
        # ------------------------------------------------------------
        # @param logger [Module, nil] Real DebugTools module, or nil for silent shim
        def initialize(logger)
            @logger = logger
        end
        # ---------------------------------------------------------------

        # FUNCTION | Method Forwarder with Silent Fallback
        # ------------------------------------------------------------
        def method_missing(name, *args, &block)
            return nil if @logger.nil?
            return nil unless @logger.respond_to?(name)
            @logger.public_send(name, *args, &block)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Capability Check (Always True for `na_*` Methods)
        # ------------------------------------------------------------
        def respond_to_missing?(_name, _include_private = false)
            true
        end
        # ---------------------------------------------------------------

    end # class Na__DebugToolsProxy

# endregion ===================================================================


    # HELPER FUNCTION | Resolve the Best Available Debug Logger
    # ------------------------------------------------------------
    # Returns a proxy wrapping the first DebugTools module that has been
    # loaded. The proxy guarantees no `na_debug_*` call ever raises, even
    # when the wrapped module lacks that specific method (e.g. the window
    # DebugTools has no na_debug_measure / na_debug_door, and the door
    # DebugTools has no na_debug_window / na_debug_placement).
    def self.na_resolve_debug_tools
        logger = if defined?(::Na__WindowConfiguratorTool::Na__DebugTools)
                     ::Na__WindowConfiguratorTool::Na__DebugTools
                 elsif defined?(::Na__InteriorDoorConfigurator::Na__DebugTools)
                     ::Na__InteriorDoorConfigurator::Na__DebugTools
                 else
                     nil
                 end
        Na__DebugToolsProxy.new(logger)
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# =============================================================================
# REGION | Two-Point Opening Tool Class
# =============================================================================

    class Na__TwoPointOpeningTool

        # MODULE CONSTANTS | Conversion and Visual Style
        # ------------------------------------------------------------
        NA_MM_TO_INCH                = 1.0 / 25.4                              # <-- Millimetre to inch conversion
        NA_INCH_TO_MM                = 25.4                                    # <-- Inverse conversion
        NA_OVERLAY_FILL_COLOR        = Sketchup::Color.new(  0, 120, 255,  80) # <-- Blue overlay fill
        NA_OVERLAY_BORDER_COLOR      = Sketchup::Color.new(  0, 120, 255, 200) # <-- Blue overlay border
        NA_POINT_A_COLOR             = Sketchup::Color.new(  0, 200,   0)      # <-- Point A marker
        NA_DIMENSION_TEXT_COLOR      = Sketchup::Color.new(255, 255, 255)      # <-- Dimension label colour
        NA_CROSSHAIR_SIZE            = 100.mm                                  # <-- Crosshair span
        NA_GRID_SIZE                 = 1.mm                                    # <-- Snap grid resolution
        # ---------------------------------------------------------------

        # FUNCTION | Initialize the Two-Point Opening Tool
        # ------------------------------------------------------------
        # @param dialog_host [Module] Host module exposing
        #        `na_send_measurement_to_dialog(width_mm, height_mm, ax, ay, az)`
        #        and `na_send_measure_cancelled_to_dialog`.
        # @param cill_height_mm [Numeric] Cill height to deduct from the raw
        #        height (defaults to 50mm if nil).
        # @param frame_bottom_thickness_mm [Numeric] Bottom frame thickness
        #        used to disable the cill deduction when zero.
        def initialize(dialog_host, cill_height_mm, frame_bottom_thickness_mm = 50)
            @dialog_host                = dialog_host
            @frame_bottom_thickness_mm  = frame_bottom_thickness_mm || 50
            @is_bottom_frameless        = @frame_bottom_thickness_mm == 0
            @cill_height_mm             = @is_bottom_frameless ? 0 : (cill_height_mm || 50)

            @ip                         = Sketchup::InputPoint.new
            @ip_start                   = Sketchup::InputPoint.new

            @point_a                    = nil
            @current_point              = nil
            @state                      = :picking_point_a

            @debug_tools                = Na__MeasurementTools.na_resolve_debug_tools
            @debug_tools.na_debug_method(
                "Na__TwoPointOpeningTool initialized " \
                "(cill_height=#{@cill_height_mm}mm, " \
                "frame_bottom_thickness=#{@frame_bottom_thickness_mm}mm, " \
                "bottom_frameless=#{@is_bottom_frameless})"
            )
        end
        # ---------------------------------------------------------------

# endregion ===================================================================


# =============================================================================
# REGION | Sketchup::Tool Lifecycle Hooks
# =============================================================================

        # FUNCTION | Tool Activated
        # ------------------------------------------------------------
        def activate
            @debug_tools.na_debug_method("Na__TwoPointOpeningTool activated")
            @state = :picking_point_a
            na_update_status_text
            Sketchup.active_model.active_view.invalidate
        end
        # ---------------------------------------------------------------

        # FUNCTION | Tool Deactivated
        # ------------------------------------------------------------
        def deactivate(view)
            @debug_tools.na_debug_method("Na__TwoPointOpeningTool deactivated")
            view.invalidate
        end
        # ---------------------------------------------------------------

# endregion ===================================================================


# =============================================================================
# REGION | Mouse and Cancel Handlers
# =============================================================================

        # FUNCTION | Mouse Move Handler
        # ------------------------------------------------------------
        def onMouseMove(flags, x, y, view)
            @ip.pick(view, x, y)
            return unless @ip.valid?

            @current_point = na_round_to_grid(@ip.position)
            na_update_status_text
            view.invalidate
        end
        # ---------------------------------------------------------------

        # FUNCTION | Left Mouse Button Down Handler
        # ------------------------------------------------------------
        def onLButtonDown(flags, x, y, view)
            @ip.pick(view, x, y)
            return unless @ip.valid?

            clicked_point = na_round_to_grid(@ip.position)

            if @state == :picking_point_a
                @point_a       = clicked_point
                @ip_start.copy!(@ip)
                @state         = :picking_point_b
                @debug_tools.na_debug_info("Point A set: #{na_point_to_mm_string(@point_a)}")
                na_update_status_text
                view.invalidate

            elsif @state == :picking_point_b
                @current_point = clicked_point
                @debug_tools.na_debug_info("Point B set: #{na_point_to_mm_string(@current_point)}")

                na_complete_measurement
                Sketchup.active_model.select_tool(nil)
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Cancel Handler (ESC Key)
        # ------------------------------------------------------------
        def onCancel(reason, view)
            @debug_tools.na_debug_info("Measure Opening cancelled")
            if @dialog_host.respond_to?(:na_send_measure_cancelled_to_dialog)
                @dialog_host.na_send_measure_cancelled_to_dialog
            end
            view.invalidate
        end
        # ---------------------------------------------------------------

# endregion ===================================================================


# =============================================================================
# REGION | Draw Handler
# =============================================================================

        # FUNCTION | Draw Overlay Geometry for the Active State
        # ------------------------------------------------------------
        def draw(view)
            if @state == :picking_point_a && @current_point
                na_draw_crosshair(view, @current_point)
            end

            return unless @point_a && @current_point && @state == :picking_point_b

            pts = na_calculate_rect_points(@point_a, @current_point)

            view.drawing_color = NA_OVERLAY_FILL_COLOR
            view.draw(GL_QUADS, pts)

            view.drawing_color = NA_OVERLAY_BORDER_COLOR
            view.line_width    = 2
            view.draw(GL_LINE_LOOP, pts)

            na_draw_crosshair(view, @point_a, NA_POINT_A_COLOR)

            na_draw_dimension_text(view, @point_a, @current_point)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Get Extents (prevents draw clipping)
        # ------------------------------------------------------------
        def getExtents
            bb = Geom::BoundingBox.new
            bb.add(@point_a)        if @point_a
            bb.add(@current_point)  if @current_point
            bb
        end
        # ---------------------------------------------------------------

# endregion ===================================================================


        private

# =============================================================================
# REGION | Geometry Helpers
# =============================================================================

        # HELPER FUNCTION | Calculate Rectangle Points for Overlay
        # ------------------------------------------------------------
        # Determines the 4 corners of the rectangle based on Point A and Point B.
        # Uses the dominant horizontal axis (X or Y) and the Z axis to form the plane.
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
        # ---------------------------------------------------------------

# endregion ===================================================================


# =============================================================================
# REGION | Drawing Primitives
# =============================================================================

        # HELPER FUNCTION | Draw a Three-Axis Crosshair at a World Point
        # ------------------------------------------------------------
        def na_draw_crosshair(view, point, color = nil)
            size              = NA_CROSSHAIR_SIZE * 0.5
            view.line_width   = 1

            view.drawing_color = color || Sketchup::Color.new(255, 0, 0)
            view.draw_line(point.offset(X_AXIS, -size), point.offset(X_AXIS, size))

            view.drawing_color = color || Sketchup::Color.new(0, 255, 0)
            view.draw_line(point.offset(Y_AXIS, -size), point.offset(Y_AXIS, size))

            view.drawing_color = color || Sketchup::Color.new(0, 0, 255)
            view.draw_line(point.offset(Z_AXIS, -size), point.offset(Z_AXIS, size))
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Draw the Width / Height Dimension Label
        # ------------------------------------------------------------
        def na_draw_dimension_text(view, pt_a, pt_b)
            width_mm, height_mm = na_calculate_dimensions_mm(pt_a, pt_b)
            adjusted_height_mm  = [height_mm - @cill_height_mm, 0].max

            label  = "W: #{width_mm.round}mm  |  H: #{height_mm.round}mm"
            label += "  (Adj: #{adjusted_height_mm.round}mm)" if @cill_height_mm > 0

            screen_pt          = view.screen_coords(pt_b)
            view.drawing_color = NA_DIMENSION_TEXT_COLOR
            view.draw_text(Geom::Point3d.new(screen_pt.x + 15, screen_pt.y - 25, 0), label)
        end
        # ---------------------------------------------------------------

# endregion ===================================================================


# =============================================================================
# REGION | Dimension Math
# =============================================================================

        # HELPER FUNCTION | Calculate Width and Height in Millimetres
        # ------------------------------------------------------------
        # @return [Array<Integer>] [width_mm, height_mm]
        def na_calculate_dimensions_mm(pt_a, pt_b)
            dx = (pt_b.x - pt_a.x).abs
            dy = (pt_b.y - pt_a.y).abs
            dz = (pt_b.z - pt_a.z).abs

            width_in  = [dx, dy].max
            height_in = dz

            [(width_in * NA_INCH_TO_MM).round, (height_in * NA_INCH_TO_MM).round]
        end
        # ---------------------------------------------------------------

# endregion ===================================================================


# =============================================================================
# REGION | Completion and Status
# =============================================================================

        # HELPER FUNCTION | Send Final Measurement to the Host Dialog
        # ------------------------------------------------------------
        # The host receives the cill-adjusted height plus Point A in inches
        # so it can cache Point A as the next placement origin.
        def na_complete_measurement
            width_mm, height_mm = na_calculate_dimensions_mm(@point_a, @current_point)
            adjusted_height_mm  = [height_mm - @cill_height_mm, 100].max

            @debug_tools.na_debug_success(
                "Measurement complete: Width=#{width_mm}mm, " \
                "Raw Height=#{height_mm}mm, Cill Deduction=#{@cill_height_mm}mm, " \
                "Adjusted Height=#{adjusted_height_mm}mm, BottomFrameless=#{@is_bottom_frameless}"
            )

            return unless @dialog_host.respond_to?(:na_send_measurement_to_dialog)
            @dialog_host.na_send_measurement_to_dialog(
                width_mm, adjusted_height_mm,
                @point_a.x, @point_a.y, @point_a.z
            )
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Update the SketchUp Status Bar Text
        # ------------------------------------------------------------
        def na_update_status_text
            if @state == :picking_point_a
                if @current_point
                    pos_str = na_point_to_mm_string(@current_point)
                    Sketchup.status_text = "Measure Opening: Click to set Point A (base corner) at #{pos_str} | ESC to cancel"
                else
                    Sketchup.status_text = "Measure Opening: Click to set Point A (base corner) | ESC to cancel"
                end
            elsif @state == :picking_point_b
                if @current_point
                    width_mm, height_mm = na_calculate_dimensions_mm(@point_a, @current_point)
                    adjusted_height_mm  = [height_mm - @cill_height_mm, 0].max
                    Sketchup.status_text = "Measure Opening: Click to set Point B | W:#{width_mm}mm H:#{adjusted_height_mm}mm | ESC to cancel"
                else
                    Sketchup.status_text = "Measure Opening: Move cursor to set Point B | ESC to cancel"
                end
            end
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Round a Point to the 1mm Grid
        # ------------------------------------------------------------
        def na_round_to_grid(point)
            Geom::Point3d.new(
                (point.x / NA_GRID_SIZE).round * NA_GRID_SIZE,
                (point.y / NA_GRID_SIZE).round * NA_GRID_SIZE,
                (point.z / NA_GRID_SIZE).round * NA_GRID_SIZE
            )
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Format a Point as an mm Triplet String
        # ------------------------------------------------------------
        def na_point_to_mm_string(point)
            x_mm = (point.x * NA_INCH_TO_MM).round
            y_mm = (point.y * NA_INCH_TO_MM).round
            z_mm = (point.z * NA_INCH_TO_MM).round
            "X:#{x_mm}mm Y:#{y_mm}mm Z:#{z_mm}mm"
        end
        # ---------------------------------------------------------------

# endregion ===================================================================

    end # class Na__TwoPointOpeningTool

# endregion -------------------------------------------------------------------

end # module Na__MeasurementTools

# =============================================================================
# END OF FILE
# =============================================================================
