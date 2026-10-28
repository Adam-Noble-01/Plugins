# =============================================================================
# NA INSERT PRIMATIVES - DRAWN PIPEWORK TOOL
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnPipeTool__.rb
# NAMESPACE  : Na__InsertPrimatives
# CLASS      : DrawnPipeTool
# AUTHOR     : Noble Architecture
# PURPOSE    : Pipework to a diameter, bend radius, sides and bore — along
#              selected edges, or drawn point by point — and changed after the
#              fact: its size from the bar, its route from a red line
# CREATED    : 2026
#
# FOUR WAYS IN — decided by what is selected, or open, when the tool starts:
#   ROUTE    edges selected. Every run through them is shown as pipe at once,
#            bends and all. Click, Enter or the bar's Build builds them;
#            typing a spec (80,110,24s) builds them at that spec. Ends,
#            junctions, closed loops and drawn arcs are all understood
#            (DrawnPipe__Route__).
#   RESIZE   pipes this tool built are selected. Type a spec, or click a spec
#            on the bar and type, and each is rebuilt from the route it keeps,
#            changing only what was typed (its own bend, sides and bore stay).
#            The bar's Edit Path re-routes one. A click draws a new run.
#   EDIT     a pipe's path is out as a red line (DrawnPipe__Edit__). The bar
#            offers Finish, Discard and SketchUp's Move and Line for the line;
#            the spec typed or clicked here applies to that pipe at once (the
#            overlay shows it) and is built at the finish. A click anywhere
#            but the line finishes, as clicking outside a group closes it.
#   DRAW     nothing usable selected. Click the start and every turn, like
#            the Line tool, with the pipe on the cursor; finish with Enter, a
#            double click, a click on the last point or the bar's Finish;
#            click the first point to close a loop (DrawnPipe__Draw__).
#
# THE SPEC (DrawnPipe__Spec__): diameter, CENTRELINE bend radius, sides, bore.
#   80,110,24s,70 | ,150 | 24s | 80d | 110r | 0r (mitred) | 70i | 5w | 0i | +20
#   The sides are the plugin's Circle Sides. A spec typed straight after
#   building changes what was just built; it is remembered for the next pipe
#   either way. The bore only reaches new pipes while Internal Diameter is on.
#
# THE BAR (DrawnPipe__Bar__): Deep Scale's top-left bar, for this tool. The
#   actions of the moment on the left; Ø, R, sides and Bore to click and type
#   into; Caps.
#
# THE BAR ON SELECTION (DrawnPipe__Watch__, 5.2.11): select pipes with
#   SketchUp's Select tool, or open a path edit, and the same bar appears
#   without starting this tool; the cursor on it pushes this class in its
#   :bar role over Select, and leaving it hands back. Popup > Pipework >
#   Bar on Selection, or Extensions, switches it off.
#
# WHAT IS BUILT (DrawnPipe__Solver__ and DrawnPipe__Build__):
#   One group per run, named 01__DrawnPipe__80mm, in one undo step for the
#   whole selection. Bends are true torus slices with no twist; legs too
#   short for their bends share the room and say so; caps close the ends of
#   a solid pipe, a hollow one ends in flat rings; the surface is smoothed,
#   mitre seams and end outlines stay crisp. Each group keeps its route and
#   spec, which is what makes it resizable and re-routable later.
#
# POPUP SUBMENU OPTIONS (Na__InsertPrimatives__AppData__ToolOptions__.rb):
#   End Caps           on: solid pipes. Off: open tubes (ends hidden in walls)
#   Erase Path         after building along a selection, erase the route's
#                      loose edges. An edge bounding a face is never erased.
#   Internal Diameter  off: solid pipes. On: true pipes with a bore (5.2.10)
#   Bar on Selection   on: the bar shows over the Select tool (5.2.11)
#
# COORDINATES:
#   World throughout, as the CLAUDE.md Coordinate Rule asks of a tool that
#   reads the selection and writes into the active context: selected
#   vertices, InputPoints and pick rays are all world, and each new group is
#   pinned to the world identity before the mesh goes in. A resize and a
#   re-route work in the group's own coordinates instead, where its stored
#   route lives.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../06__Tools__DrawnShared/Na__InsertPrimatives__DrawnToolShared__'
require_relative 'Na__InsertPrimatives__DrawnPipe__Spec__'
require_relative 'Na__InsertPrimatives__DrawnPipe__Route__'
require_relative 'Na__InsertPrimatives__DrawnPipe__Solver__'
require_relative 'Na__InsertPrimatives__DrawnPipe__Build__'
require_relative 'Na__InsertPrimatives__DrawnPipe__Preview__'
require_relative 'Na__InsertPrimatives__DrawnPipe__Draw__'
require_relative 'Na__InsertPrimatives__DrawnPipe__Edit__'
require_relative 'Na__InsertPrimatives__DrawnPipe__Bar__'

module Na__InsertPrimatives

    # @delegate: Na__InsertPrimatives__DrawnPipe__Spec__.rb
    # @delegate: Na__InsertPrimatives__DrawnPipe__Route__.rb
    # @delegate: Na__InsertPrimatives__DrawnPipe__Solver__.rb
    # @delegate: Na__InsertPrimatives__DrawnPipe__Build__.rb
    # @delegate: Na__InsertPrimatives__DrawnPipe__Preview__.rb
    # @delegate: Na__InsertPrimatives__DrawnPipe__Draw__.rb
    # @delegate: Na__InsertPrimatives__DrawnPipe__Edit__.rb
    # @delegate: Na__InsertPrimatives__DrawnPipe__Overlay__.rb
    # @delegate: Na__InsertPrimatives__DrawnPipe__Watch__.rb
    # @delegate: Na__InsertPrimatives__DrawnPipe__Bar__.rb

    # -----------------------------------------------------------------------------
    # REGION | Drawn Pipework Tool Class
    # -----------------------------------------------------------------------------

    # CLASS | Pipework Along a Selection or Drawn Point by Point
    # ------------------------------------------------------------
    class DrawnPipeTool

        include Na__InsertPrimatives::DrawnToolShared
        include Na__InsertPrimatives::DrawnPipeDraw
        include Na__InsertPrimatives::DrawnPipeBar

        NA_PIPE_CAPS_OPTION  = 'pipe_end_caps'.freeze
        NA_PIPE_ERASE_OPTION = 'pipe_erase_path'.freeze

        # INITIALIZE | Tool Constructor
        # ------------------------------------------------------------
        #   :tool  the Pipework tool, as the menu and toolbar start it
        #   :bar   the bar over SketchUp's Select tool (DrawnPipe__Watch__):
        #          pushed while the cursor is on the bar, popped when it
        #          leaves; resize and edit only, and never a run to draw
        # ------------------------------------------------------------
        def initialize(role = :tool)
            na_drawn__init_shared_state
            na_pipe__reset_run

            @na_pipe_role        = role == :bar ? :bar : :tool
            @na_pipe_mode        = :draw
            @na_pipe_runs        = []
            @na_pipe_route_edges = []
            @na_pipe_route_cache = nil
            @na_pipe_resize      = []
            @na_pipe_edit        = nil
            @na_pipe_built       = []
            @na_pipe_cursor      = nil
            @na_pipe_notes       = []
            @na_pipe_press       = nil
            @na_pipe_slot        = nil
            @na_pipe_hover       = nil
            @na_pipe_bar         = []
        end
        # ---------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Identity
        # -----------------------------------------------------------------------------

        # FUNCTION | Status Bar Title
        # ------------------------------------------------------------
        def na_drawn__tool_title
            'Pipework'
        end
        # ---------------------------------------------------------------

        # FUNCTION | Popup Menu Highlight Key
        # ------------------------------------------------------------
        def na_drawn__mode_key
            :drawn_pipe
        end
        # ---------------------------------------------------------------

        # FUNCTION | Console Banner Hint Lines
        # ------------------------------------------------------------
        def na_drawn__activation_hints
            [
                "Pipe: #{Na__InsertPrimatives.Na__DrawnPipe__SpecLabel(Na__InsertPrimatives.Na__DrawnPipe__CurrentSpec)}",
                'Edges selected: the pipe follows them — click or Enter builds, or type 80,110,24s',
                'Nothing selected: click the start and each turn; Enter, double click or the last point finishes',
                'Click the first point to close the run into a loop',
                'VCB: 80,110,24s,70 = diameter, bend radius, sides, bore | ,150 | 24s | 80d | 110r | 0r mitred | 70i | 5w',
                'While drawing: 1200 sets the leg | [x,y,z] a point | <dx,dy,dz> an offset',
                'ARROWS lock the leg to red / green / blue — SHIFT holds its direction — TAB holds the run to a plane (SHIFT+TAB back)',
                'Locked, the leg stops in line with a vertex under the cursor; CTRL keeps the lock, works exact and lines up with edges and faces too',
                'The bar, top left: click Ø, R, sides or Bore, then type — Caps — Edit Path re-routes a pipe',
                'Pipes remember their route: right-click one > Edit Pipework Path to re-route it with any tool',
                'Right-click for the menu — End Caps, Erase Path, Internal Diameter and Bar on Selection sit under this tool',
                'Bar on Selection (on): select pipes with the Select tool and this bar appears top left, ready to click'
            ]
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Options
        # -----------------------------------------------------------------------------

        # FUNCTION | Are Pipe Ends Closed?
        # ------------------------------------------------------------
        def na_pipe__caps_option?
            Na__InsertPrimatives.Na__ToolOptions__Enabled?(NA_PIPE_CAPS_OPTION)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Are the Route's Loose Edges Erased After Building?
        # ------------------------------------------------------------
        def na_pipe__erase_path_option?
            Na__InsertPrimatives.Na__ToolOptions__Enabled?(NA_PIPE_ERASE_OPTION)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Status Fragment Naming Only the Unusual Option States
        # (The bore needs no word: the spec reads Ø80/70.)
        # ------------------------------------------------------------
        def na_drawn__option_summary
            words = []
            words << 'NO CAPS'    unless na_pipe__caps_option?
            words << 'ERASE PATH' if na_pipe__erase_path_option? && @na_pipe_mode == :route
            words.empty? ? '' : " | #{words.join('+')}"
        rescue StandardError
            ''
        end
        # ---------------------------------------------------------------

        # FUNCTION | An Option Switched From the Popup
        # ------------------------------------------------------------
        def Na__DrawnMode__ToggleToolOption(option_id)
            result = super
            na_pipe__after_setting_changed
            Na__InsertPrimatives.Na__DrawnPipe__WatchStale if option_id.to_s == NA_DRAWN_PIPE_AUTO_BAR_OPTION   # <-- The bar over Select shows or goes at once
            result
        end
        # ---------------------------------------------------------------

        # FUNCTION | Circle Sides Cycled From the Popup: the Pipe Follows
        # ------------------------------------------------------------
        def Na__DrawnMode__CycleCircleSegments
            count = super
            na_pipe__after_setting_changed
            count
        end
        # ---------------------------------------------------------------

        # FUNCTION | Bring Previews, Status and Box Up to Date After Any Change
        # ------------------------------------------------------------
        def na_pipe__after_setting_changed
            @na_pipe_route_cache = nil
            na_pipe__refresh_live
            @na_last_status_text = nil
            @na_last_vcb_label   = nil
            @na_last_vcb_text    = nil
            na_drawn__update_status_text
            na_drawn__refresh_vcb

            model = Sketchup.active_model
            model.active_view.invalidate if model
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Drawing Axes' Blue, in World
        # ------------------------------------------------------------
        def na_pipe__up
            Na__InsertPrimatives.Na__DrawnGrid__AxisVectors[2]
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | SketchUp Tool API — Life Cycle
        # -----------------------------------------------------------------------------

        # ACTIVATE | Read the Selection and Choose the Mode
        # ------------------------------------------------------------
        def activate
            @na_ctrl_held  = false
            @na_shift_held = false
            @na_tab_held   = false
            @na_plane_lock = :auto
            na_pipe__reset_run
            na_drawn__disarm_revise
            na_pipe__read_selection
            return na_pipe__bar_activate if na_pipe__bar_role?

            na_drawn__print_activation_banner
            na_pipe__report_selection
            @na_last_status_text = nil
            na_drawn__update_status_text
            na_drawn__refresh_vcb

            model = Sketchup.active_model
            model.active_view.invalidate if model
        end
        # ---------------------------------------------------------------

        # DEACTIVATE | The Bar Leaves Nothing Armed Behind
        # ------------------------------------------------------------
        def deactivate(view)
            if na_pipe__bar_role?
                @na_pipe_slot  = nil
                @na_pipe_hover = nil
            end

            super
        end
        # ---------------------------------------------------------------

        # FUNCTION | Edit, Route, Resize or Draw — From What Is Open or Selected
        # ------------------------------------------------------------
        def na_pipe__read_selection
            model = Sketchup.active_model
            open  = Na__InsertPrimatives.Na__DrawnPipe__OpenEdit(model)

            @na_pipe_edit        = open
            @na_pipe_route_cache = nil
            @na_pipe_notes       = []
            @na_pipe_slot        = nil

            if open
                @na_pipe_mode        = :edit
                @na_pipe_runs        = []
                @na_pipe_route_edges = []
                @na_pipe_resize      = []
                return
            end

            found = Na__InsertPrimatives.Na__DrawnPipe__ReadSelection(model ? model.selection : nil)
            found = found.merge(:runs => [], :edges => []) if na_pipe__bar_role?   # <-- The bar is about pipes: selected edges wait for the tool

            @na_pipe_runs        = found[:runs]
            @na_pipe_route_edges = found[:edges]
            @na_pipe_resize      = found[:pipes]
            @na_pipe_notes << "#{found[:ignored]} other selected object#{found[:ignored] == 1 ? '' : 's'} ignored" if found[:ignored] > 0

            @na_pipe_mode =
                if !@na_pipe_runs.empty?
                    @na_pipe_notes << "#{@na_pipe_resize.length} selected pipe#{@na_pipe_resize.length == 1 ? '' : 's'} left alone — edges win" unless @na_pipe_resize.empty?
                    :route
                elsif !@na_pipe_resize.empty?
                    :resize
                else
                    :draw
                end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Read Again After an Edit Opened, Finished or Was Discarded
        # ------------------------------------------------------------
        def na_pipe__reread
            na_pipe__reset_run
            na_pipe__read_selection
            @na_last_status_text = nil
            @na_last_vcb_label   = nil
            @na_last_vcb_text    = nil
            na_drawn__refresh_vcb

            model = Sketchup.active_model
            model.active_view.invalidate if model
        end
        # ---------------------------------------------------------------

        # FUNCTION | Leave Route or Resize for Drawing
        # ------------------------------------------------------------
        def na_pipe__enter_draw_mode
            @na_pipe_mode        = :draw
            @na_pipe_runs        = []
            @na_pipe_route_edges = []
            @na_pipe_route_cache = nil
            @na_pipe_resize      = []
            @na_pipe_edit        = nil
            @na_pipe_notes       = []
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | The Bar Role — Over SketchUp's Select Tool (DrawnPipe__Watch__)
        # -----------------------------------------------------------------------------
        # One instance, made once, does both halves: between visits the overlay
        # draws the bar through it, and while the cursor is on the bar it is
        # pushed over Select so the bar's buttons and typing work. Resize and
        # edit only: there is never a run to draw, and a selected edge waits
        # for the Pipework tool itself.

        # FUNCTION | Is This the Bar Over the Select Tool?
        # ------------------------------------------------------------
        def na_pipe__bar_role?
            @na_pipe_role == :bar
        end
        # ---------------------------------------------------------------

        # FUNCTION | Show What the Overlay Found (No Tool Running Yet)
        # ------------------------------------------------------------
        def na_pipe__bar_present(open, pipes)
            @na_pipe_edit        = open
            @na_pipe_mode        = open ? :edit : :resize
            @na_pipe_resize      = open ? [] : pipes
            @na_pipe_runs        = []
            @na_pipe_route_edges = []
            @na_pipe_slot        = nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Button the Overlay Sees Under the Cursor; True If It Changed
        # ------------------------------------------------------------
        def na_pipe__bar_hover(id)
            changed        = @na_pipe_hover != id
            @na_pipe_hover = id
            changed
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Bar as Last Laid Out (the Overlay's Cheap First Test)
        # ------------------------------------------------------------
        def na_pipe__bar_buttons
            @na_pipe_bar || []
        end
        # ---------------------------------------------------------------

        # FUNCTION | Pushed Over Select: the Bar as It Was Drawn, and No Banner
        # ------------------------------------------------------------
        def na_pipe__bar_activate
            return if na_pipe__bar_settle

            mouse = Na__InsertPrimatives.Na__DrawnPipe__BarMouse
            @na_last_mouse_x, @na_last_mouse_y = mouse if mouse
            @na_last_status_text = nil
            @na_last_vcb_label   = nil
            @na_last_vcb_text    = nil
            na_drawn__update_status_text
            na_drawn__refresh_vcb

            model = Sketchup.active_model
            model.active_view.invalidate if model
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Cursor Moved: Off the Bar With Nothing Armed, Back to Select
        # ------------------------------------------------------------
        # A margin round the bar (Watch's let-go distance) keeps the hand-over
        # from flickering along its edge.
        # ------------------------------------------------------------
        def na_pipe__bar_track(view, x, y)
            @na_last_mouse_x = x
            @na_last_mouse_y = y
            return na_pipe__bar_leave if @na_pipe_slot.nil? && Na__InsertPrimatives.Na__DrawnPipe__BarClear?(@na_pipe_bar, x, y)

            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate
        end
        # ---------------------------------------------------------------

        # FUNCTION | Hand Back to Select (Soon: Never From Inside Its Own Event)
        # ------------------------------------------------------------
        def na_pipe__bar_leave
            @na_pipe_slot  = nil
            @na_pipe_hover = nil
            Na__InsertPrimatives.Na__DrawnPipe__BarPop(self)
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | After a Button or Enter: Still a Bar to Show? If Not, Leave
        # ------------------------------------------------------------
        # Finishing an edit with nothing left selected, say, leaves nothing
        # for the bar to change. Returns true when it left.
        # ------------------------------------------------------------
        def na_pipe__bar_settle
            showing = @na_pipe_mode == :edit || (@na_pipe_mode == :resize && !@na_pipe_resize.empty?)
            return false if showing

            na_pipe__bar_leave
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | After a Typed Entry: the Slot Is Let Go
        # ------------------------------------------------------------
        # The bar shows the new values at once. Moving off it hands back to
        # Select; staying, the next click or entry is the bar's.
        # ------------------------------------------------------------
        def na_pipe__bar_after_entry
            @na_pipe_slot      = nil
            @na_last_vcb_label = nil
            na_pipe__bar_settle
        end
        # ---------------------------------------------------------------

        # FUNCTION | ESC on the Bar: Let Go of an Armed Slot, Else Back to Select
        # ------------------------------------------------------------
        # An undo (reason 2) may have changed what is selected or open, so the
        # bar is read again.
        # ------------------------------------------------------------
        def na_pipe__bar_cancel(reason, view)
            if reason == 2
                na_pipe__reread
                return if na_pipe__bar_settle
            elsif reason == 0
                return na_pipe__bar_leave unless @na_pipe_slot

                @na_pipe_slot      = nil
                @na_last_vcb_label = nil
            end

            @na_last_status_text = nil
            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Bar's Own Right-Click Menu (Native, Over Select)
        # ------------------------------------------------------------
        # Not the plugin's popup dialog: that one belongs to a running tool,
        # and the bar hands back to Select as soon as the cursor moves off.
        # ------------------------------------------------------------
        def na_pipe__bar_menu(menu)
            menu.add_item('Pipework Tool (This Selection)') do
                Na__InsertPrimatives.Na__InsertPrimatives__DrawPipe
            end
            menu.add_item('Hide the Pipework Bar on Selection') do
                Na__InsertPrimatives.Na__InsertPrimatives__TogglePipeAutoBar if Na__InsertPrimatives.Na__DrawnPipe__AutoBarOn?
                na_pipe__bar_leave
            end
            nil
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | SketchUp Tool API — Mouse
        # -----------------------------------------------------------------------------

        # ON MOUSE MOVE | Track the Cursor, the Pipe on It, and the Bar
        # ------------------------------------------------------------
        def onMouseMove(flags, x, y, view)
            na_drawn__sync_modifier(flags)
            na_pipe__sync_direction_lock

            button         = na_pipe__bar_at(view, x, y)
            @na_pipe_hover = button ? button[:id] : nil
            return na_pipe__bar_track(view, x, y) if na_pipe__bar_role?

            if @na_pipe_mode == :draw && !button
                na_pipe__update_cursor(view, x, y)
            else
                @na_last_mouse_x = x
                @na_last_mouse_y = y
            end

            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate
        end
        # ---------------------------------------------------------------

        # ON LEFT BUTTON DOWN | The Bar First; Then Build, Place or Finish
        # ------------------------------------------------------------
        def onLButtonDown(flags, x, y, view)
            @na_vcb_typing_active = false
            na_drawn__sync_modifier(flags)
            na_pipe__sync_direction_lock

            button = na_pipe__bar_at(view, x, y)
            if button
                na_pipe__bar_click(view, button)
                na_pipe__bar_settle if na_pipe__bar_role?
            elsif na_pipe__bar_role?
                return na_pipe__bar_leave                                     # <-- A click away from the bar: back to Select
            else
                case @na_pipe_mode
                when :route
                    na_pipe__build_route
                when :resize
                    na_pipe__enter_draw_mode                                  # <-- A click is a new run; the selected pipes are left as they are
                    na_pipe__click(view, x, y)
                when :edit
                    na_pipe__edit_click(view, x, y)
                else
                    na_pipe__click(view, x, y)
                end
            end

            @na_pipe_press = (!button && na_pipe__drawing?) ? [x, y] : nil
            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Click in Edit Mode: on the Line, Say How; Anywhere Else, Finish
        # ------------------------------------------------------------
        # Clicking outside a group closes it; here the same click finishes the
        # edit, so the gesture is the one the hand already knows.
        # ------------------------------------------------------------
        def na_pipe__edit_click(view, x, y)
            if na_pipe__on_red_line?(view, x, y)
                return na_pipe__say('That is the red line — Move (on the bar) drags its points, Line draws it on; Finish when it is right')
            end

            na_pipe__bar_finish
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is the Red Line Under the Cursor?
        # Unsure counts as yes: a stray finish costs more than a hint.
        # ------------------------------------------------------------
        def na_pipe__on_red_line?(view, x, y)
            edit = @na_pipe_edit && @na_pipe_edit[:edit]
            return false unless edit && edit.valid?

            picker = view.pick_helper
            picker.do_pick(x, y)

            (0...picker.count).any? do |index|
                leaf = picker.leaf_at(index)
                leaf && leaf.respond_to?(:parent) && leaf.parent == edit.definition
            end
        rescue StandardError
            true
        end
        # ---------------------------------------------------------------

        # ON MOUSE LEAVE | Off the View: the Bar Hands Back to Select
        # ------------------------------------------------------------
        def onMouseLeave(view)
            na_pipe__bar_leave if na_pipe__bar_role? && @na_pipe_slot.nil?
            false
        end
        # ---------------------------------------------------------------

        # ON RIGHT BUTTON UP | Over Select, the Bar's Menu Is Native, Not the Popup
        # ------------------------------------------------------------
        def onRButtonUp(flags, x, y, view)
            return false if na_pipe__bar_role?

            super
        end
        # ---------------------------------------------------------------

        # GET MENU | The Bar's Own Items Over Select; the Popup Otherwise
        # ------------------------------------------------------------
        def getMenu(menu, *args)
            return na_pipe__bar_menu(menu) if na_pipe__bar_role?

            super
        end
        # ---------------------------------------------------------------

        # ON LEFT BUTTON UP | Press, Drag and Release Places a Point Too
        # ------------------------------------------------------------
        # As the Line tool: a press that travels before it is let go puts the
        # next point where it was let go. A release on the spot is a click
        # and does nothing more.
        # ------------------------------------------------------------
        def onLButtonUp(flags, x, y, view)
            press          = @na_pipe_press
            @na_pipe_press = nil
            return unless press && @na_pipe_mode == :draw && na_pipe__drawing?

            travelled = (x.to_f - press[0].to_f).abs + (y.to_f - press[1].to_f).abs
            return if travelled < NA_DRAWN_DRAG_MIN_PX

            na_drawn__sync_modifier(flags)
            na_pipe__click(view, x, y)
            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate
        end
        # ---------------------------------------------------------------

        # ON LEFT BUTTON DOUBLE CLICK | Finish the Run
        # The first click of the pair has already placed its point.
        # ------------------------------------------------------------
        def onLButtonDoubleClick(flags, x, y, view)
            return false unless @na_pipe_mode == :draw && na_pipe__drawing?

            na_pipe__finish(view, false)
            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate
            true
        end
        # ---------------------------------------------------------------

        # ON CANCEL | ESC Steps Back a Level; Undo Abandons the Run
        # ------------------------------------------------------------
        #   a spec slot armed  it is let go
        #   drawing a run      the run is dropped
        #   editing a path     the tool steps aside for SketchUp's Select tool;
        #                      the red line stays out to edit
        #   route / resize     the selection is let go and the tool draws instead
        #   drawing, idle      the tool closes
        # ------------------------------------------------------------
        def onCancel(reason, view)
            @na_vcb_typing_active = false
            return na_pipe__bar_cancel(reason, view) if na_pipe__bar_role?

            if @na_pipe_slot && reason == 0
                @na_pipe_slot      = nil
                @na_last_vcb_label = nil
            elsif na_pipe__drawing?
                na_pipe__reset_run
            elsif @na_pipe_mode == :edit
                return unless reason == 0

                na_drawn__schedule_exit_tool
                return
            elsif @na_pipe_mode != :draw
                na_pipe__enter_draw_mode
            elsif reason == 0
                na_drawn__schedule_exit_tool
                return
            end

            @na_last_status_text = nil
            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | SketchUp Tool API — Keyboard and Measurements Box
        # -----------------------------------------------------------------------------

        # ON KEY DOWN | Modifiers, Axis Locks, BKSP and Entry Tracking
        # ------------------------------------------------------------
        def onKeyDown(key, repeat, flags, view)
            if key == COPY_MODIFIER_KEY && !@na_ctrl_held
                @na_ctrl_held = true
                return na_pipe__after_key(view)
            end

            if key == NA_DRAWN_SHIFT_KEY && !@na_shift_held
                @na_shift_held = true
                return na_pipe__after_key(view)
            end

            axis = na_drawn__axis_for_key(key)
            if axis || key == VK_DOWN
                @na_axis_lock = (@na_axis_lock == axis) ? nil : axis
                @na_pipe_dir  = nil
                return na_pipe__after_key(view)
            end

            if key == NA_DRAWN_TAB_KEY
                return false if @na_tab_held || @na_pipe_mode != :draw         # <-- One step per press: a held TAB repeats
                @na_tab_held = true
                na_pipe__cycle_plane(@na_shift_held ? -1 : 1)
                return na_pipe__after_key(view)
            end

            if key == NA_DRAWN_BACKSPACE_KEY || key == VK_DELETE
                return false if @na_vcb_typing_active                          # <-- Mid-entry this is a typo fix
                na_pipe__step_back
                return na_pipe__after_key(view)
            end

            @na_vcb_typing_active = true if NA_DRAWN_VCB_ENTRY_KEYS.include?(key)
            false
        end
        # ---------------------------------------------------------------

        # ON KEY UP | Let Go of CTRL and SHIFT, and the TAB Repeat Guard
        # ------------------------------------------------------------
        def onKeyUp(key, repeat, flags, view)
            @na_tab_held = false if key == NA_DRAWN_TAB_KEY

            if key == COPY_MODIFIER_KEY && @na_ctrl_held
                @na_ctrl_held = false
                na_pipe__after_key(view)
            end

            if key == NA_DRAWN_SHIFT_KEY && @na_shift_held
                @na_shift_held = false
                na_pipe__after_key(view)
            end

            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | After a Key Changed the Locks: Re-Solve and Redraw
        # ------------------------------------------------------------
        def na_pipe__after_key(view)
            na_pipe__sync_direction_lock
            na_pipe__update_cursor(view, @na_last_mouse_x, @na_last_mouse_y) if view && @na_pipe_mode == :draw
            @na_last_status_text = nil
            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
            false
        end
        # ---------------------------------------------------------------

        # ON RETURN | Enter With an Empty Box Builds, Ends the Run, or Finishes
        # ------------------------------------------------------------
        def onReturn(view)
            handled =
                case @na_pipe_mode
                when :route then na_pipe__build_route
                when :edit  then na_pipe__bar_finish
                when :draw  then na_pipe__drawing? ? na_pipe__finish(view, false) : false
                else             false
                end

            na_pipe__bar_settle if na_pipe__bar_role?
            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
            handled ? true : false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Route a Measurements Box Entry
        # ------------------------------------------------------------
        def onUserText(text, view)
            @na_vcb_typing_active = false
            cleaned = text.to_s.strip
            return if cleaned.empty?

            kind = na_pipe__apply_text(cleaned)
            na_pipe__update_cursor(view, @na_last_mouse_x, @na_last_mouse_y) if @na_pipe_mode == :draw
            na_pipe__bar_after_entry if na_pipe__bar_role?
            na_drawn__update_status_text unless kind == :spec                  # <-- A spec says its own result; this would cover it
            na_drawn__rearm_vcb
            view.invalidate if view
        end
        # ---------------------------------------------------------------

        # FUNCTION | Apply Typed Text Where It Belongs; Returns What It Was
        # ------------------------------------------------------------
        # One door for the measurements box and the bar's buttons. A plain
        # number with a bar slot armed goes to that slot. Lengths and points
        # only mean anything while drawing. A spec is read against the spec
        # it changes: each selected pipe's own when resizing, the re-routed
        # pipe's own when editing, the next pipe's otherwise.
        # Refusals are said, never raised: the bar calls this too.
        # ------------------------------------------------------------
        def na_pipe__apply_text(text)
            text = Na__InsertPrimatives.Na__DrawnPipe__MarkForSlot(text, @na_pipe_slot)

            case @na_pipe_mode
            when :resize
                na_pipe__remember_text(text)
                na_pipe__resize_text(@na_pipe_resize, text, 'Resize Pipe')
                return :spec
            when :edit
                na_pipe__remember_text(text)
                na_pipe__edit_spec_text(text)
                return :spec
            end

            bare  = (@na_pipe_mode == :draw && na_pipe__drawing?) ? :length : :diameter
            entry = Na__InsertPrimatives.Na__DrawnPipe__ParseEntry(text, Na__InsertPrimatives.Na__DrawnPipe__CurrentSpec, bare)

            case entry[:kind]
            when :length then na_pipe__type_length(entry[:token])
            when :point
                raise ArgumentError, 'a point is typed while drawing a run — this mode follows the selection' unless @na_pipe_mode == :draw
                na_pipe__type_point(entry)
            else
                na_pipe__store_spec(entry)
                na_pipe__apply_spec(entry[:spec], text)
            end

            entry[:kind]
        rescue ArgumentError => error
            UI.beep
            Sketchup::set_status_text("Invalid entry — #{error.message}", SB_PROMPT)
            :refused
        end
        # ---------------------------------------------------------------

        # FUNCTION | Remember a Spec for the Next Pipe, and Say If the Bore Option Moved
        # ------------------------------------------------------------
        def na_pipe__store_spec(entry)
            switched = Na__InsertPrimatives.Na__DrawnPipe__StoreSpec(entry[:spec], entry[:named])
            return unless switched

            Na__InsertPrimatives.Na__RightClickPopup__RefreshOption(Na__InsertPrimatives::NA_DRAWN_PIPE_BORE_OPTION) if Na__InsertPrimatives.respond_to?(:Na__RightClickPopup__RefreshOption)
        end
        # ---------------------------------------------------------------

        # FUNCTION | What Was Typed for Existing Pipes Also Sets the Next Pipe
        # Read against the next pipe's spec, so only the slots named move; a
        # refusal here is not the user's concern (theirs is the pipe's).
        # ------------------------------------------------------------
        def na_pipe__remember_text(text)
            entry = Na__InsertPrimatives.Na__DrawnPipe__ParseEntry(text, Na__InsertPrimatives.Na__DrawnPipe__CurrentSpec, :diameter)
            na_pipe__store_spec(entry) if entry[:kind] == :spec
        rescue ArgumentError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | A New Spec for the Next Pipe: Apply It Where It Belongs
        # ------------------------------------------------------------
        #   route    build the selection at it, at once
        #   drawing  the run on the cursor follows; nothing is lost
        #   after    the pipes just built are rebuilt at it (their own read)
        #   else     the next pipe will be built at it
        # ------------------------------------------------------------
        def na_pipe__apply_spec(spec, text)
            @na_pipe_route_cache = nil
            na_pipe__refresh_live
            label = Na__InsertPrimatives.Na__DrawnPipe__SpecLabel(spec)

            if @na_pipe_mode == :route
                na_pipe__build_route
            elsif na_pipe__drawing?
                na_pipe__say("Pipe now #{label} — the run on the cursor follows")
            elsif na_pipe__revise_available?
                na_pipe__resize_text(@na_pipe_built, text, 'Adjust Pipe')
            else
                na_pipe__say("Next pipe: #{label} — click the start of the run")
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Put a Result on the Status Line and Keep It There
        # ------------------------------------------------------------
        # The composed line goes up first, so the next refresh finds nothing
        # changed and leaves the result showing until the state really moves.
        # ------------------------------------------------------------
        def na_pipe__say(text)
            na_drawn__update_status_text
            Sketchup::set_status_text(text, SB_PROMPT)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Building, Resizing and Re-Speccing an Edit
        # -----------------------------------------------------------------------------

        # FUNCTION | Build Every Run Through the Selected Edges
        # ------------------------------------------------------------
        def na_pipe__build_route
            return false if @na_pipe_runs.empty?

            built = na_pipe__commit(@na_pipe_runs, 'Pipe Along Selection', @na_pipe_route_edges)
            return false if built.empty?

            na_pipe__enter_draw_mode
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Build Runs as Pipe Groups, in One Undo Step
        # ------------------------------------------------------------
        # A run that cannot be built is reported and the rest still are. The
        # new pipes are left selected: what was built is plain to see, and
        # starting the tool again on them goes straight to resizing.
        # Returns the groups built.
        # ------------------------------------------------------------
        def na_pipe__commit(runs, operation, source_edges)
            model = Sketchup.active_model
            return [] unless model

            spec     = Na__InsertPrimatives.Na__DrawnPipe__CurrentSpec
            caps     = na_pipe__caps_option?
            built    = []
            failed   = []
            warnings = []
            many     = runs.length > 1

            model.start_operation(operation, true)

            runs.each_with_index do |run, index|
                group, solved = Na__InsertPrimatives.Na__DrawnPipe__CreateGroup(model.active_entities, run, spec, na_pipe__up, caps)
                prefix = many ? "run #{index + 1}: " : ''

                if group
                    built << group
                    warnings.concat((solved[:warnings] || []).map { |warning| prefix + warning })
                else
                    failed << prefix + solved[:message].to_s
                end
            end

            if built.empty?
                model.abort_operation
                UI.beep
                na_pipe__say("No pipe built — #{failed.first}")
                na_pipe__log('DRAWN PIPE REFUSED', [], spec, warnings, failed)
                return []
            end

            erased = (source_edges && na_pipe__erase_path_option?) ? na_pipe__erase_path(model, source_edges) : nil
            model.commit_operation

            model.selection.clear
            model.selection.add(built)

            @na_pipe_built = built
            na_drawn__arm_revise

            na_pipe__report_build(built, failed, warnings, erased, source_edges)
            na_pipe__log('DRAWN PIPE CREATED', built, spec, warnings, failed)
            built
        end
        # ---------------------------------------------------------------

        # FUNCTION | Erase the Route's Loose Edges; Returns How Many
        # ------------------------------------------------------------
        def na_pipe__erase_path(model, edges)
            loose = edges.select { |edge| edge.valid? && edge.faces.empty? }
            model.active_entities.erase_entities(loose) unless loose.empty?
            loose.length
        end
        # ---------------------------------------------------------------

        # FUNCTION | Rebuild Pipe Groups at Typed Text, Each Read Against Its Own Spec
        # ------------------------------------------------------------
        # "100" makes every selected pipe 100 across and leaves each one's own
        # bend, sides and bore wall as they were; "+20" adds 20 to each one's
        # own. A pipe whose path is out as a red line is left for that edit to
        # finish: rebuilding it now would sweep the line away. One undo step.
        # ------------------------------------------------------------
        def na_pipe__resize_text(groups, text, operation)
            model   = Sketchup.active_model
            targets = (groups || []).select { |group| group && group.valid? }
            return false unless model && !targets.empty?

            waiting = targets.select { |group| Na__InsertPrimatives.Na__DrawnPipe__EditGroupOf(group) }
            targets -= waiting

            plans  = []
            failed = []

            targets.each do |group|
                begin
                    entry = Na__InsertPrimatives.Na__DrawnPipe__ParseEntry(text, Na__InsertPrimatives.Na__DrawnPipe__StoredSpec(group), :diameter)
                    raise ArgumentError, 'type a spec — a length or a point means nothing to a built pipe' unless entry[:kind] == :spec

                    plans << [group, entry[:spec]]
                rescue ArgumentError => error
                    failed << "#{group.name}: #{error.message}"
                end
            end

            if plans.empty?
                UI.beep
                reason = failed.first || (waiting.empty? ? 'nothing to resize' : 'its path is out as a red line — finish or discard that first')
                na_pipe__say("Could not resize — #{reason}")
                return false
            end

            done  = 0
            notes = []

            model.start_operation(operation, true)

            plans.each do |group, spec|
                ok, solved = Na__InsertPrimatives.Na__DrawnPipe__RebuildGroup(group, spec)

                if ok
                    done += 1
                    notes.concat(solved[:warnings] || [])
                else
                    failed << "#{group.name}: #{solved[:message]}"
                end
            end

            if done.zero?
                model.abort_operation
                UI.beep
                na_pipe__say("Could not resize — #{failed.first}")
                return false
            end

            model.commit_operation

            label  = Na__InsertPrimatives.Na__DrawnPipe__SpecLabel(plans.first[1])
            tail   = failed.empty? ? '' : " (#{failed.length} could not be: #{failed.first})"
            tail  += " — #{waiting.length} left: its path is being edited" unless waiting.empty?
            tail  += " — #{notes.length} bend#{notes.length == 1 ? '' : 's'} adjusted to fit" unless notes.empty?
            na_pipe__say("#{done} pipe#{done == 1 ? '' : 's'} now #{label}#{tail}")

            na_pipe__log(operation.upcase, plans.map(&:first), plans.first[1], notes, failed)
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | A New Spec for the Pipe Whose Path Is Out
        # ------------------------------------------------------------
        # Stored on the pipe at once, so the overlay's preview shows it; it is
        # built when the edit finishes.
        # ------------------------------------------------------------
        def na_pipe__edit_spec_text(text)
            pipe = @na_pipe_edit && @na_pipe_edit[:pipe]
            return false unless pipe && pipe.valid?

            entry = Na__InsertPrimatives.Na__DrawnPipe__ParseEntry(text, Na__InsertPrimatives.Na__DrawnPipe__StoredSpec(pipe), :diameter)
            raise ArgumentError, 'type a spec — the red line is edited with Move and Line' unless entry[:kind] == :spec

            model = Sketchup.active_model
            model.start_operation('Pipework Path Spec', true)
            Na__InsertPrimatives.Na__DrawnPipe__StoreSpecOn(pipe, entry[:spec])
            model.commit_operation

            na_pipe__say("#{pipe.name} will be #{Na__InsertPrimatives.Na__DrawnPipe__SpecLabel(entry[:spec])} — the preview shows it; Finish builds it")
            true
        rescue ArgumentError => error
            UI.beep
            na_pipe__say("Invalid entry — #{error.message}")
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is There a Pipe Just Built That a Typed Spec Would Change?
        # ------------------------------------------------------------
        def na_pipe__revise_available?
            @na_revise_armed && @na_pipe_built.any? { |group| group && group.valid? }
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Draw
        # -----------------------------------------------------------------------------

        # DRAW | The Pipe as It Will Be Built, Then the Bar Over Everything
        # In edit mode the overlay draws the pipe: this tool only adds the bar.
        # ------------------------------------------------------------
        def draw(view)
            case @na_pipe_mode
            when :route  then na_pipe__draw_route(view)
            when :resize then na_pipe__draw_resize(view)
            when :edit   then nil
            else              na_pipe__draw_run(view)
            end

            na_pipe__draw_bar(view)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Solved Previews for Every Selected Run, Cached per Spec
        # ------------------------------------------------------------
        def na_pipe__route_previews
            spec = Na__InsertPrimatives.Na__DrawnPipe__CurrentSpec
            return @na_pipe_route_cache[:items] if @na_pipe_route_cache && @na_pipe_route_cache[:spec] == spec

            up     = na_pipe__up
            solves = @na_pipe_runs.map { |run| Na__InsertPrimatives.Na__DrawnPipe__Solve(run, spec, up) }
            quads  = solves.select { |solved| solved[:ok] }.sum { |solved| Na__InsertPrimatives.Na__DrawnPipe__QuadCount(solved) }
            shade  = quads <= NA_DRAWN_PIPE_PREVIEW_MAX_QUADS

            items = @na_pipe_runs.each_with_index.map do |run, index|
                solved = solves[index]
                {
                    :run    => run,
                    :solved => solved,
                    :quads  => (shade && solved[:ok]) ? Na__InsertPrimatives.Na__DrawnPipe__PreviewQuads(solved) : nil
                }
            end

            @na_pipe_route_cache = { :spec => spec, :items => items }
            items
        end
        # ---------------------------------------------------------------

        # FUNCTION | Route Mode: Every Run, Built or Refused, and One Card
        # ------------------------------------------------------------
        def na_pipe__draw_route(view)
            items = na_pipe__route_previews

            items.each do |item|
                solved = item[:solved]

                if solved[:ok]
                    Na__InsertPrimatives.Na__DrawnPipe__DrawSolved(view, solved, item[:quads])
                    Na__InsertPrimatives.Na__DrawnPipe__LabelCorners(view, solved)
                else
                    Na__InsertPrimatives.Na__DrawnPipe__DrawRoute(view, item[:run][:points], item[:run][:closed], NA_DRAWN_PIPE_FAILED_COLOR)
                end
            end

            first = items.first
            return unless first

            Na__InsertPrimatives.Na__DrawnPipe__DrawSummary(view, first[:run][:points].first, na_pipe__route_card(items))
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Route Mode Summary Card
        # ------------------------------------------------------------
        def na_pipe__route_card(items)
            good    = items.select { |item| item[:solved][:ok] }
            length  = good.sum { |item| item[:solved][:length].to_f }
            changed = good.sum { |item| item[:solved][:warnings].length }
            refused = items.length - good.length

            [
                Na__InsertPrimatives.Na__DrawnPipe__SpecLabel(Na__InsertPrimatives.Na__DrawnPipe__CurrentSpec),
                "#{good.length} run#{good.length == 1 ? '' : 's'} · #{Na__InsertPrimatives.Na__DrawnPipe__FormatMetres(length)} — click or Enter to build",
                changed > 0 ? "#{changed} bend#{changed == 1 ? '' : 's'} adjusted to fit (labelled)" : nil,
                refused > 0 ? "#{refused} run#{refused == 1 ? '' : 's'} cannot be piped (red)" : nil
            ]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Resize Mode: Each Selected Pipe's Stored Route, Dashed
        # Selected pipes report a world transformation (they are in the
        # active context), which carries their own stored points to world.
        # ------------------------------------------------------------
        def na_pipe__draw_resize(view)
            @na_pipe_resize.each do |group|
                next unless group.valid?

                stored = Na__InsertPrimatives.Na__DrawnPipe__StoredRoute(group)
                next unless stored

                xform  = group.transformation
                points = stored[:points].map { |point| point.transform(xform) }
                Na__InsertPrimatives.Na__DrawnPipe__DrawRoute(view, points, stored[:closed], NA_DRAWN_TEXT_LOCKED_COLOR)
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw Mode: Cursor, Locks, the Live Pipe and Its Card
        # ------------------------------------------------------------
        # SketchUp's own point marker is shown when it is what places the
        # point: free, or lined up with under a lock (then with a dotted guide
        # from it to the leg's end). Under a lock with nothing to line up
        # with, the marker would sit somewhere the point is not, so it is not.
        # ------------------------------------------------------------
        def na_pipe__draw_run(view)
            aim    = @na_pipe_aim
            line   = na_pipe__lock_line
            locked = !line.nil? || !na_pipe__lock_plane.nil?
            @na_ip.draw(view) if (!locked || aim) && @na_ip && @na_ip.valid?

            anchor = @na_pipe_points.last || @na_pipe_cursor
            Na__InsertPrimatives.Na__DrawnPreview__DrawAxisRay(view, anchor, @na_axis_lock) if @na_axis_lock
            na_pipe__draw_direction_lock(view) if @na_pipe_dir
            na_pipe__draw_plane_lock(view) unless line
            Na__InsertPrimatives.Na__DrawnPreview__DrawGuideLine(view, aim[:position], aim[:point]) if aim

            unless na_pipe__drawing?
                Na__InsertPrimatives.Na__DrawnPreview__DrawCrosshair(view, @na_pipe_cursor)
                na_drawn__draw_grid_correction(view)
                return
            end

            live = @na_pipe_live
            if live && live[:solved][:ok]
                Na__InsertPrimatives.Na__DrawnPipe__DrawSolved(view, live[:solved], live[:quads])
                Na__InsertPrimatives.Na__DrawnPipe__LabelCorners(view, live[:solved])
            end

            Na__InsertPrimatives.Na__DrawnPipe__DrawRoute(view, live ? live[:points] : @na_pipe_points, false,
                                                          live && !live[:solved][:ok] ? NA_DRAWN_PIPE_FAILED_COLOR : nil)
            na_pipe__draw_leg_label(view)
            Na__InsertPrimatives.Na__DrawnPreview__DrawCrosshair(view, @na_pipe_points.first, nil, NA_DRAWN_ANCHOR_COLOR)
            na_drawn__draw_grid_correction(view) if !locked || aim
            Na__InsertPrimatives.Na__DrawnPipe__DrawSummary(view, @na_pipe_cursor || @na_pipe_points.last, na_pipe__run_card(live))
        end
        # ---------------------------------------------------------------

        # FUNCTION | The TAB Plane: a Square Through the Last Point, in Its Pole's Colour
        # ------------------------------------------------------------
        # Sized on screen, so it reads the same near or far: XY plan is edged
        # blue, XZ front green, YZ side red, as SketchUp colours its axes.
        # ------------------------------------------------------------
        def na_pipe__draw_plane_lock(view)
            plane = na_pipe__lock_plane
            return unless plane

            origin = plane[0]
            u_axis, v_axis, _normal = Na__InsertPrimatives.Na__DrawnGrid__PlaneAxes(@na_plane_lock)
            half   = view.pixels_to_model(NA_PIPE_PLANE_PIXELS, origin).to_f
            return unless half > 0.0

            corners = [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]].map do |su, sv|
                na_pipe__along(na_pipe__along(origin, u_axis.normalize, su * half), v_axis.normalize, sv * half)
            end

            edge = NA_DRAWN_AXIS_COLORS[NA_DRAWN_AXIS_TO_PLANE.key(@na_plane_lock)] || NA_DRAWN_TEXT_LOCKED_COLOR
            fill = Sketchup::Color.new(edge.red, edge.green, edge.blue, 38)
            Na__InsertPrimatives.Na__DrawnPreview__DrawFilledQuad(view, corners, fill, edge)
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | The SHIFT Lock Line Through the Last Point
        # ------------------------------------------------------------
        def na_pipe__draw_direction_lock(view)
            last = @na_pipe_points.last
            return unless last

            span = view.pixels_to_model(2000, last).to_f
            span = 1000.0 unless span > 0.0

            view.line_stipple  = ''
            view.line_width    = 2
            view.drawing_color = NA_DRAWN_TEXT_LOCKED_COLOR
            view.draw_line(na_pipe__along(last, @na_pipe_dir, -span), na_pipe__along(last, @na_pipe_dir, span))
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Live Leg's Length at Its Middle
        # ------------------------------------------------------------
        def na_pipe__draw_leg_label(view)
            last = @na_pipe_points.last
            return unless last && @na_pipe_cursor && na_pipe__leg_length > NA_DRAWN_PIPE_MERGE_TOL

            Na__InsertPrimatives.Na__DrawnPreview__DrawEdgeLabel(
                view, last, @na_pipe_cursor,
                Na__InsertPrimatives.Na__DrawnPipe__FormatMm(na_pipe__leg_length),
                NA_DRAWN_TEXT_ACCENT_COLOR
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Draw Mode Summary Card
        # ------------------------------------------------------------
        def na_pipe__run_card(live)
            spec  = Na__InsertPrimatives.Na__DrawnPipe__SpecLabel(Na__InsertPrimatives.Na__DrawnPipe__CurrentSpec)
            return [spec, "#{@na_pipe_points.length} point#{@na_pipe_points.length == 1 ? '' : 's'}"] unless live

            solved = live[:solved]
            return [spec, "Cannot pipe this: #{solved[:message]}"] unless solved[:ok]

            bends = solved[:corners].length
            [
                spec,
                "Run #{Na__InsertPrimatives.Na__DrawnPipe__FormatMetres(solved[:length])} · #{bends} bend#{bends == 1 ? '' : 's'}",
                solved[:warnings].empty? ? nil : solved[:warnings].first
            ]
        end
        # ---------------------------------------------------------------

        # GET EXTENTS | Keep Every Preview Inside the Draw Bounds
        # ------------------------------------------------------------
        def getExtents
            bounds = Geom::BoundingBox.new
            bounds.add(@na_pipe_cursor) if @na_pipe_cursor
            @na_pipe_points.each { |point| bounds.add(point) }

            solves =
                case @na_pipe_mode
                when :route then (@na_pipe_route_cache ? @na_pipe_route_cache[:items] : []).map { |item| item[:solved] }
                when :draw  then @na_pipe_live ? [@na_pipe_live[:solved]] : []
                else             []
                end

            solves.each do |solved|
                next unless solved && solved[:ok] && solved[:box]

                solved[:box].each { |xyz| bounds.add(Geom::Point3d.new(xyz[0], xyz[1], xyz[2])) }
            end

            if @na_pipe_mode == :route
                @na_pipe_runs.each { |run| run[:points].each { |point| bounds.add(point) } }
            end

            bounds
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Status Bar and Measurements Box
        # -----------------------------------------------------------------------------

        # FUNCTION | Push the Composed Status Line (Only When It Changed)
        # ------------------------------------------------------------
        def na_drawn__update_status_text
            spec     = Na__InsertPrimatives.Na__DrawnPipe__SpecLabel(na_pipe__bar_spec)
            composed =
                "#{na_drawn__tool_title} | #{spec} | #{na_drawn__status_detail} | " \
                "#{na_drawn__grid_description}#{na_drawn__axis_description}#{na_pipe__lock_description}#{na_drawn__option_summary} | " \
                "#{na_pipe__keys_hint}"

            return if composed == @na_last_status_text

            Sketchup::set_status_text(composed, SB_PROMPT)
            @na_last_status_text = composed
        end
        # ---------------------------------------------------------------

        # FUNCTION | Middle Section of the Status Line
        # ------------------------------------------------------------
        def na_drawn__status_detail
            notes = @na_pipe_notes.empty? ? '' : " (#{@na_pipe_notes.join('; ')})"

            case @na_pipe_mode
            when :route
                runs = @na_pipe_runs.length
                "#{runs} run#{runs == 1 ? '' : 's'} from #{@na_pipe_route_edges.length} edges — click or Enter to build, or type Ø,R,sides#{notes}"
            when :resize
                count = @na_pipe_resize.length
                return "#{count} pipe#{count == 1 ? '' : 's'} selected — click Ø, R, sides or Bore on the bar and type, or type Ø,R,sides; off the bar is Select#{notes}" if na_pipe__bar_role?

                "#{count} pipe#{count == 1 ? '' : 's'} selected — type Ø,R,sides to resize, or click to draw a new run#{notes}"
            when :edit
                "Path of #{@na_pipe_edit[:pipe].name} out as a red line — Move / Line on the bar to edit it, Finish or click away to rebuild"
            else
                if na_pipe__drawing?
                    "Leg #{Na__InsertPrimatives.Na__DrawnPipe__FormatMm(na_pipe__leg_length)} mm — click to turn, Enter or double click to finish, first point closes a loop"
                elsif na_pipe__revise_available?
                    'Type Ø,R,sides to change the pipe just built — or click to start a new run'
                else
                    'Click the start of the run — or select edges first to pipe along them'
                end
            end
        rescue StandardError
            ''
        end
        # ---------------------------------------------------------------

        # FUNCTION | Status Fragment for SHIFT, the TAB Plane, and What the Leg Lines Up With
        # ------------------------------------------------------------
        def na_pipe__lock_description
            words = ''
            words += ' | DIRECTION LOCKED (SHIFT)' if @na_pipe_dir
            words += " | PLANE #{NA_DRAWN_PLANE_LABELS[@na_plane_lock]} (TAB)" if @na_pipe_mode == :draw && na_pipe__plane_chosen?

            if @na_pipe_aim
                found  = @na_pipe_aim[:tooltip].to_s.strip
                words += " | IN LINE WITH #{found.empty? ? 'the point' : found}"
            end

            words
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Keys Named at the End of the Status Line
        # ------------------------------------------------------------
        def na_pipe__keys_hint
            return 'CLICK a spec  TYPE it  ENTER apply  ESC back to Select  RIGHT-CLICK hide the bar' if na_pipe__bar_role?

            case @na_pipe_mode
            when :route  then 'CLICK / ENTER build  TYPE Ø,R,sides  ESC draw instead'
            when :resize then 'TYPE Ø,R,sides resize  CLICK new run  ESC draw instead'
            when :edit   then 'ENTER finish  TYPE Ø,R,sides  ESC hand over to Select'
            else              'ARROWS axis  SHIFT direction  TAB plane  CTRL exact + edges/faces  BKSP back  ENTER finish  ESC cancel'
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Measurements Box Label and Live Value
        # ------------------------------------------------------------
        def na_drawn__vcb_label_and_value
            spec = na_pipe__bar_spec

            if @na_pipe_slot
                value =
                    case @na_pipe_slot
                    when :sides then spec[:sides].to_s
                    else             Na__InsertPrimatives.Na__DrawnPipe__FormatMm(spec[@na_pipe_slot])
                    end
                return [DrawnPipeBar::NA_PIPE_BAR_SLOT_NAMES[@na_pipe_slot], value]
            end

            if @na_pipe_mode == :draw && na_pipe__drawing?
                return ['Leg length', Na__InsertPrimatives.Na__DrawnPipe__FormatMm(na_pipe__leg_length)]
            end

            label = spec[:inner].to_f > 0.0 ? 'Pipe Ø,R,sides,bore' : 'Pipe Ø,R,sides'
            [label, Na__InsertPrimatives.Na__DrawnPipe__SpecEntry(spec)]
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Reporting
        # -----------------------------------------------------------------------------

        # FUNCTION | Say What the Selection Was Read As
        # ------------------------------------------------------------
        def na_pipe__report_selection
            case @na_pipe_mode
            when :route
                closed = @na_pipe_runs.count { |run| run[:closed] }
                Na__InsertPrimatives.Na__Debug__Puts(
                    "Route: #{@na_pipe_runs.length} run#{@na_pipe_runs.length == 1 ? '' : 's'} " \
                    "(#{closed} closed) from #{@na_pipe_route_edges.length} selected edges"
                )
            when :resize
                Na__InsertPrimatives.Na__Debug__Puts "Resize: #{@na_pipe_resize.length} pipe group(s) selected"
            when :edit
                Na__InsertPrimatives.Na__Debug__Puts "Edit: the path of #{@na_pipe_edit[:pipe].name} is out as a red line"
            end

            @na_pipe_notes.each { |note| Na__InsertPrimatives.Na__Debug__Puts "Note: #{note}" }
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Status Line After a Build
        # ------------------------------------------------------------
        def na_pipe__report_build(built, failed, warnings, erased, source_edges)
            parts = ["Built #{built.length} pipe#{built.length == 1 ? '' : 's'}, #{Na__InsertPrimatives.Na__DrawnPipe__SpecLabel(Na__InsertPrimatives.Na__DrawnPipe__CurrentSpec)}"]
            parts << "#{warnings.length} bend#{warnings.length == 1 ? '' : 's'} adjusted to fit (see Ruby Console)" unless warnings.empty?
            parts << "#{failed.length} run#{failed.length == 1 ? '' : 's'} refused: #{failed.first}" unless failed.empty?
            parts << "#{erased} path edge#{erased == 1 ? '' : 's'} erased" if erased && erased > 0

            kept = source_edges && erased ? source_edges.length - erased : 0
            parts << "#{kept} kept (they bound faces)" if erased && kept > 0
            parts << 'type Ø,R,sides now to change it'

            na_pipe__say(parts.join(' — '))
        end
        # ---------------------------------------------------------------

        # FUNCTION | Console Report for a Build or a Resize
        # ------------------------------------------------------------
        def na_pipe__log(headline, groups, spec, warnings, failed)
            Na__InsertPrimatives.Na__Debug__Puts "\n"
            Na__InsertPrimatives.Na__Debug__Puts '----------------------------------------'
            Na__InsertPrimatives.Na__Debug__Puts headline
            Na__InsertPrimatives.Na__Debug__Puts "Spec  : #{Na__InsertPrimatives.Na__DrawnPipe__SpecLabel(spec)}"
            Na__InsertPrimatives.Na__Debug__Puts "Pipes : #{groups.length}"
            Na__InsertPrimatives.Na__Debug__Puts "Caps  : #{na_pipe__caps_option? ? 'closed' : 'open tubes'}"
            Na__InsertPrimatives.Na__Debug__Puts "Solid : #{groups.map { |group| Na__InsertPrimatives.Na__DrawnGeom__SolidState(group) }.uniq.join(', ')}" unless groups.empty?
            warnings.each { |warning| Na__InsertPrimatives.Na__Debug__Puts "Fitted: #{warning}" }
            failed.each   { |message| Na__InsertPrimatives.Na__Debug__Puts "Refused: #{message}" }
            Na__InsertPrimatives.Na__Debug__Puts '----------------------------------------'
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnPipeTool class

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Public Entry Point
    # -----------------------------------------------------------------------------

    # FUNCTION | Activate the Pipework Tool (Hotkey Entry Point)
    # ------------------------------------------------------------
    # Bind in Preferences -> Shortcuts against the Plugins menu item, or call
    # directly: Na__InsertPrimatives.Na__InsertPrimatives__DrawPipe
    # ------------------------------------------------------------
    def self.Na__InsertPrimatives__DrawPipe
        Na__InsertPrimatives.Na__ModeSwitch__ActivateDrawnPipeTool
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DRAWN PIPEWORK TOOL
# =============================================================================
