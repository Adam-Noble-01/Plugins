# =============================================================================
# NA INSERT PRIMATIVES - DEEP VERTEX MOVE - THE BASE POINT (ALT+DRAG)
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnVertexMove__BasePoint__.rb
# NAMESPACE  : Na__InsertPrimatives::DrawnVertexMoveBasePoint
# AUTHOR     : Noble Architecture
# PURPOSE    : Put the gimbal's base point on a vertex with ALT+drag, the way a
#              3D cursor is placed in other software, so a move can say "from
#              THIS point to that one"
# CREATED    : 2026
#
# DESCRIPTION:
# - Hold ALT and press on the gimbal's centre square, drag, and let go: the
#   base point goes where SketchUp's inference puts it — a vertex, an edge, a
#   midpoint — and the picks do not move. ALT+click, move, click works too.
# - Every move then measures from it. Drag the centre square with CTRL onto
#   another vertex and everything moves from the base point to that vertex;
#   drag an arrow and its travel runs along the axis through the base point.
# - The base point travels with the picks, so after a move it stands where it
#   was taken to, ready for the next. ESC puts it back in the middle of the
#   picks (before ESC clears the picks), and so does a new scope or an undo.
#
# READING ALT (see the 5.1.24 and 5.2.12 devlog entries):
# - The mouse flags never carry ALT on Windows, and key-ups can go to the menu
#   bar, so the press asks Windows itself whether ALT is down at that moment,
#   through the Camera guard's read-only user32 reader
#   (Na__CameraGuard__KeyDown?). Where that cannot answer, the tool's own ALT
#   key-down counts for NA_VM_ALT_FRESH_S.
# - A bare ALT is swallowed while the gimbal is up, as Push/Pull's SHIFT+ALT
#   swallows it, so letting go of it does not wake the menu bar in the middle
#   of placing the base point. Ctrl+Alt is passed on: it is SketchUp 2027's
#   touchpad orbit.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnGridSnap__'
require_relative '../05__PreviewGraphics/Na__InsertPrimatives__DrawnPreviewGraphics__'
require_relative 'Na__InsertPrimatives__DrawnVertexMove__Gimbal__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Base Point Constants
    # -----------------------------------------------------------------------------

    NA_VM_ALT_KEY      = defined?(ALT_MODIFIER_KEY)  ? ALT_MODIFIER_KEY  : 18
    NA_VM_ALT_MASK     = defined?(ALT_MODIFIER_MASK) ? ALT_MODIFIER_MASK : 32
    NA_VM_VK_MENU      = 0x12                                                 # <-- ALT, as user32 names it
    NA_VM_ALT_FRESH_S  = 2.0                                                  # <-- A tracked ALT counts this long after it was last seen
    NA_VM_WINDOWS      = (RUBY_PLATFORM =~ /mswin|mingw|cygwin/) ? true : false   # <-- On Windows the mask bit is XBUTTON1, never ALT

    # endregion -------------------------------------------------------------------


    module DrawnVertexMoveBasePoint

        NA_VM_BASE_COLOUR = Sketchup::Color.new(255, 196, 0)

        # -----------------------------------------------------------------------------
        # REGION | State
        # -----------------------------------------------------------------------------

        # FUNCTION | Create Every Instance Variable the Base Point Relies On
        # ------------------------------------------------------------
        def na_vm__init_base_point
            @na_vm_pivot      = nil                                           # <-- The placed base point (world), or nil: the middle of the picks
            @na_vm_pivot_drag = nil                                           # <-- { :from, :point, :press_x, :press_y, :pressed }
            @na_vm_alt_at     = nil                                           # <-- When the tool last saw ALT go down (the no-user32 fallback)
            @na_vm_alt_used   = false                                         # <-- An ALT press placed or began a base point
        end
        # ---------------------------------------------------------------

        # FUNCTION | Has a Base Point Been Placed?
        # ------------------------------------------------------------
        def na_vm__pivot_placed?
            !@na_vm_pivot.nil?
        end
        # ---------------------------------------------------------------

        # FUNCTION | Back to the Middle of the Picks
        # ------------------------------------------------------------
        def na_vm__reset_pivot
            return false unless @na_vm_pivot

            @na_vm_pivot = nil
            na_vm__picks_changed
            true
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | ALT
        # -----------------------------------------------------------------------------

        # FUNCTION | Is ALT Down at This Moment?
        # ------------------------------------------------------------
        # The flags first, for a platform that does report it; then Windows'
        # own key state; then, where neither can say, the tool's own key-down
        # within the last NA_VM_ALT_FRESH_S.
        # ------------------------------------------------------------
        def na_vm__alt_down?(flags = 0)
            return true if (flags.to_i & NA_VM_ALT_MASK) != 0 && !NA_VM_WINDOWS

            state = Na__InsertPrimatives.respond_to?(:Na__CameraGuard__KeyDown?) ? Na__InsertPrimatives.Na__CameraGuard__KeyDown?(NA_VM_VK_MENU) : nil
            return state unless state.nil?

            @na_vm_alt_at ? (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @na_vm_alt_at) < NA_VM_ALT_FRESH_S : false
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # ON KEY DOWN | Track ALT; Swallow a Bare ALT While the Gimbal Is Up
        # ------------------------------------------------------------
        def onKeyDown(key, repeat, flags, view)
            return super unless key == NA_VM_ALT_KEY

            @na_vm_alt_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            na_drawn__update_cursor(view, @na_last_mouse_x, @na_last_mouse_y)
            @na_last_status_text = nil
            na_drawn__update_status_text
            view.invalidate if view

            na_vm__swallow_alt?
        end
        # ---------------------------------------------------------------

        # ON KEY UP | ALT Let Go — Swallowed the Same Way It Went Down
        # ------------------------------------------------------------
        def onKeyUp(key, repeat, flags, view)
            return super unless key == NA_VM_ALT_KEY

            swallow       = na_vm__swallow_alt? || @na_vm_alt_used
            @na_vm_alt_at = nil
            @na_vm_alt_used = false
            @na_last_status_text = nil
            na_drawn__update_status_text
            view.invalidate if view
            swallow
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is a Bare ALT Ours Right Now?
        # ------------------------------------------------------------
        # While the gimbal is up ALT means "place the base point", and letting
        # it go must not open the menu bar. Ctrl+Alt is SketchUp 2027's
        # touchpad orbit and is never taken.
        # ------------------------------------------------------------
        def na_vm__swallow_alt?
            return false if @na_ctrl_held

            (@na_vm_phase == :vertices && !@na_vm_origin.nil?) || !@na_vm_pivot_drag.nil?
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Dragging the Base Point
        # -----------------------------------------------------------------------------

        # FUNCTION | ALT on the Centre Square: Take Hold of the Base Point
        # ------------------------------------------------------------
        def na_vm__start_pivot_drag(view, x, y)
            from = @na_vm_origin
            return false unless from

            @na_vm_pivot_drag = { :from => from, :point => from, :press_x => x, :press_y => y, :pressed => true }
            @na_vm_alt_used   = true
            @na_ip_origin     = Sketchup::InputPoint.new(from)
            @na_vm_hover      = :free
            @na_vm_record     = nil                                           # <-- Placing a base point is the "something else" that ends a retype
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Base Point Follows SketchUp's Inference, Exactly
        # ------------------------------------------------------------
        # A vertex, an edge, a midpoint, a face: wherever the inference lands,
        # with the axes through the old base point offered as well. No grid:
        # the point is meant to sit on the thing it was taken to.
        # ------------------------------------------------------------
        def na_vm__update_pivot_drag(view, x, y)
            drag = @na_vm_pivot_drag
            return false unless drag

            @na_ip.pick(view, x, y, @na_ip_origin)
            point = @na_ip.valid? ? @na_ip.position : nil
            drag[:point] = point if point
            true
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Let Go (or the Second Click): the Base Point Is Placed
        # ------------------------------------------------------------
        def na_vm__set_pivot(view, x, y)
            drag = @na_vm_pivot_drag
            return false unless drag

            na_vm__update_pivot_drag(view, x, y)
            @na_vm_pivot_drag = nil
            @na_vm_pivot      = drag[:point]
            na_vm__picks_changed

            na_vm__notice('Base point placed — drag the centre square with CTRL onto the target to move everything from here to there. ESC puts it back')
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Release After a Press: Placed if It Travelled, Else Click-Move-Click
        # ------------------------------------------------------------
        def na_vm__release_pivot_drag(view, x, y)
            drag = @na_vm_pivot_drag
            return false unless drag && drag[:pressed]

            drag[:pressed] = false
            travelled = (x.to_f - drag[:press_x].to_f).abs + (y.to_f - drag[:press_y].to_f).abs
            return false if travelled < Na__InsertPrimatives::DrawnToolShared::NA_DRAWN_DRAG_MIN_PX

            na_vm__set_pivot(view, x, y)
        end
        # ---------------------------------------------------------------

        # FUNCTION | ESC While Placing: Leave the Base Point Where It Was
        # ------------------------------------------------------------
        def na_vm__cancel_pivot_drag
            return false unless @na_vm_pivot_drag

            @na_vm_pivot_drag = nil
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Move Was Made: the Base Point Went With the Picks
        # ------------------------------------------------------------
        def na_vm__carry_pivot(offset)
            @na_vm_pivot = @na_vm_pivot + offset if @na_vm_pivot && offset
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Drawing and Words
        # -----------------------------------------------------------------------------

        # FUNCTION | The Base Point on Its Way: Ghost Gimbal, Leader, Inference
        # ------------------------------------------------------------
        def na_vm__draw_pivot_drag(view)
            drag = @na_vm_pivot_drag
            return unless drag

            Na__InsertPrimatives.Na__DrawnPreview__DrawGuideLine(view, drag[:from], drag[:point])
            Na__InsertPrimatives.Na__VertexMove__DrawStartMark(view, drag[:from])
            @na_ip.draw(view) if @na_ip && @na_ip.valid?
            Na__InsertPrimatives.Na__VertexMove__DrawGimbal(view, drag[:point], @na_vm_frame[:axes], :free)
            Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(view, drag[:point], ['Base point', 'release to place it here'], 18, 16)
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Placed Base Point Is Ringed, So It Reads as Placed
        # ------------------------------------------------------------
        def na_vm__draw_pivot_mark(view)
            point = @na_vm_pivot
            return unless point && !@na_vm_drag && !@na_vm_pivot_drag
            return unless Na__InsertPrimatives.Na__DrawnPreview__InFrontOfCamera?(view, point)

            screen  = view.screen_coords(point)
            corners = (0...16).map do |step|
                angle = step * Math::PI / 8.0
                Geom::Point3d.new(screen.x.to_f + (Math.cos(angle) * 11.0), screen.y.to_f + (Math.sin(angle) * 11.0), 0)
            end

            view.line_stipple  = ''
            view.line_width    = 2
            view.drawing_color = NA_VM_BASE_COLOUR
            view.draw2d(GL_LINE_LOOP, corners)
            view.line_width    = 1
        end
        # ---------------------------------------------------------------

        # FUNCTION | What the Status Line Says While Placing
        # ------------------------------------------------------------
        def na_vm__pivot_status
            return nil unless @na_vm_pivot_drag

            place = @na_vm_pivot_drag[:pressed] ? 'release' : 'click'
            "Base point — drag it onto a vertex, #{place} to place it there; the picks stay put. ESC leaves it where it was"
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnVertexMoveBasePoint module

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP VERTEX MOVE BASE POINT MODULE
# =============================================================================
