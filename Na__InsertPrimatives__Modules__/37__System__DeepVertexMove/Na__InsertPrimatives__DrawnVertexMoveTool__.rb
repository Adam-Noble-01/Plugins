# =============================================================================
# NA INSERT PRIMATIVES - DEEP VERTEX MOVE TOOL
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnVertexMoveTool__.rb
# NAMESPACE  : Na__InsertPrimatives
# CLASS      : DrawnVertexMoveTool
# AUTHOR     : Noble Architecture
# PURPOSE    : Pick vertices at any nesting depth inside the selected items and
#              move or stretch them with a three-arrow gimbal, on the voxel grid
# CREATED    : 2026
#
# DESCRIPTION:
# - Select groups, components or loose geometry and start the tool. That
#   selection is the SCOPE: only the vertices inside those items, at any depth,
#   can be picked, so only they can move. Started with nothing selected, the
#   tool picks the scope first (see DrawnVertexMoveSelect).
# - Drag a box to add vertices, SHIFT+box to remove them; click a vertex to add
#   it, SHIFT+click to remove it; double-click a face to add its corners. The
#   unpicked vertices show as muted red squares, smaller as the view zooms in.
# - The gimbal sits in the middle of the picks, drawn as the Point Cloud
#   Viewer's Move gimbal is. Drag an arrow to move along it, or the centre
#   square to move freely; release, or click again, to place. One undo step.
#   Box the end of a box and pull an arrow, and the box stretches.
# - Or press on a pick itself and drag: the picks move FROM that vertex, so
#   with CTRL it is that vertex that lands on the point SketchUp infers.
# - ALT+drag the centre square to put the gimbal's base point on a vertex, as
#   a 3D cursor is placed elsewhere; the picks stay put, and every move then
#   goes "from THIS point to that one" (DrawnVertexMoveBasePoint).
#
# THE SUBMENU (DrawnVertexMoveFilters):
# - Visible Only: a box or a click takes only what the camera can see.
# - In a parallel (2D) view only: Depth Limit and Depth Plane. A box takes
#   only the vertices within that depth behind the first visible plane, or
#   behind a face picked as the plane, so boxing a window reveal in an
#   elevation leaves the rest of the building alone.
#
# SNAP MODES — the same three Deep Push/Pull has:
#   nothing     the move snaps to the grid step (5 mm unless the popup's Snap
#               Grid says otherwise): an arrow's travel is rounded, a free
#               move's offset is rounded along each axis
#   CTRL        the move is read off the vertex the inference finds, exactly
#   CTRL+SHIFT  the vertex decides, then the travel is rounded to the grid,
#               with the orange mark showing the correction
#   The picks' centre is what lines up with the vertex, so a single vertex
#   lands on it and a picked face end lines up with it along the arrow.
#
# OTHER KEYS:
# - ARROWS lock a running move to an axis (Right red, Left green, Up blue,
#   Down lets go). TAB swaps the gimbal between the drawing axes and the axes
#   of the group the picks share, so a rotated window stretches along its own
#   width. BKSP takes the last pick back. ESC cancels a move, then clears the
#   picks, then leaves.
# - The measurements box takes a distance while dragging, or X,Y,Z to move by
#   an offset along the gimbal's axes. Straight after a move a typed value
#   corrects that move, as Push/Pull's does: 1200 makes it 1200, -1200 turns
#   it round.
#
# COORDINATES: every point in this tool is WORLD. The scope walk turns each
# vertex's local position into world once (DrawnVertexMoveScope), the drag
# and the preview never leave world, and the commit hands world straight to
# an opened context or brings it into a closed one (DrawnVertexMoveCommit).
#
# =============================================================================

require 'sketchup.rb'
require_relative '../06__Tools__DrawnShared/Na__InsertPrimatives__DrawnToolShared__'
require_relative '../06__Tools__DrawnShared/Na__InsertPrimatives__DrawnRevise__Watch__'
require_relative '../03__AppUtils/Na__InsertPrimatives__DrawnVcbArithmetic__'
require_relative 'Na__InsertPrimatives__DrawnVertexMove__Scope__'
require_relative 'Na__InsertPrimatives__DrawnVertexMove__Gimbal__'
require_relative 'Na__InsertPrimatives__DrawnVertexMove__Commit__'
require_relative 'Na__InsertPrimatives__DrawnVertexMove__Select__'
require_relative 'Na__InsertPrimatives__DrawnVertexMove__Filters__'
require_relative 'Na__InsertPrimatives__DrawnVertexMove__BasePoint__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Deep Vertex Move Tool Class
    # -----------------------------------------------------------------------------

    # CLASS | Move or Stretch Vertices at Any Nesting Depth
    # ------------------------------------------------------------
    class DrawnVertexMoveTool

        include Na__InsertPrimatives::DrawnToolShared
        include Na__InsertPrimatives::DrawnVertexMoveSelect
        include Na__InsertPrimatives::DrawnVertexMoveFilters                  # <-- After the shared mixin, so its submenu overrides sit over it
        include Na__InsertPrimatives::DrawnVertexMoveBasePoint                # <-- Last, so its ALT key handlers run before the shared ones

        NA_VM_MAX_DRAWN_POINTS     = 60_000                                   # <-- Candidates drawn as squares up to this many
        NA_VM_MAX_RUBBER_EDGES     = 20_000                                   # <-- Edges stretched in the preview
        NA_VM_SELECTION_FOLLOW_MAX = 2_000                                    # <-- A bigger selection is compared by size only
        NA_VM_NOTICE_DELAY_S       = 0.1

        # The unpicked vertices: a muted red square at the Vertex Size the menu
        # sets when the scope fills NA_VM_DOT_REF_SHARE of the view's diagonal.
        # Zooming scales it on a log curve, about 8% per doubling of the zoom:
        # a little smaller zoomed in, a little bigger zoomed out, and never
        # outside NA_VM_DOT_MIN_SHARE .. NA_VM_DOT_MAX_SHARE of the base.
        NA_VM_CANDIDATE_COLOUR     = Sketchup::Color.new(131,  10,  10)
        NA_VM_DOT_BASE_PX          = { 'small' => 5.0, 'medium' => 8.0, 'large' => 11.0 }.freeze
        NA_VM_DOT_LOG_GAIN         = 0.12                                     # <-- Size change per e-fold of zoom (0.083 per doubling)
        NA_VM_DOT_MIN_SHARE        = 0.6
        NA_VM_DOT_MAX_SHARE        = 1.5
        NA_VM_DOT_REF_SHARE        = 0.4

        NA_VM_PICKED_FILL          = Sketchup::Color.new(255, 150,  30)
        NA_VM_PICKED_BORDER        = Sketchup::Color.new(110,  55,   0)
        NA_VM_HOVER_COLOUR         = Sketchup::Color.new(  0, 110, 235)
        NA_VM_GHOST_COLOUR         = Sketchup::Color.new(120, 120, 120)

        # INITIALIZE | Tool Constructor
        # ------------------------------------------------------------
        def initialize
            na_drawn__init_shared_state
            na_vm__init_state
        end
        # ---------------------------------------------------------------

        # FUNCTION | Create Every Instance Variable This Tool Relies On
        # ------------------------------------------------------------
        def na_vm__init_state
            @na_vm_phase         = :vertices                                  # <-- :scope while picking what to work in
            @na_vm_scope         = nil
            @na_vm_scope_serial  = 0                                          # <-- Bumped on every walk; the screen cache keys on it
            @na_vm_roots         = []
            @na_vm_selection_ids = []                                         # <-- The selection the scope was read from, sorted ids
            @na_vm_selected      = {}                                         # <-- key => candidate, in pick order
            @na_vm_history       = []
            @na_vm_frame_mode    = :drawing
            @na_vm_frame         = nil
            @na_vm_origin        = nil
            @na_vm_hover         = nil                                        # <-- :x / :y / :z / :free under the cursor
            @na_vm_hover_vertex  = nil
            @na_vm_scope_hover   = nil
            @na_vm_box           = nil
            @na_vm_drag          = nil
            @na_vm_record        = nil                                        # <-- The last move, while a typed value may still correct it
            @na_vm_busy          = false                                      # <-- Our own commit or retype is running
            @na_vm_dirty         = false                                      # <-- The model changed under the picks
            @na_vm_refresh_due   = false
            @na_vm_watch         = nil
            @na_vm_watched       = nil
            @na_vm_projection    = nil
            @na_vm_dots          = nil                                        # <-- The unpicked squares' points, rebuilt when the picks change
            @na_vm_hover_grab    = nil                                        # <-- A pick under the cursor that a press would take hold of
            na_vm__init_filters
            na_vm__init_base_point
        end
        # ---------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Identity
        # -----------------------------------------------------------------------------

        # FUNCTION | Status Bar Title
        # ------------------------------------------------------------
        def na_drawn__tool_title
            'Deep Vertex Move'
        end
        # ---------------------------------------------------------------

        # FUNCTION | Popup Menu Highlight Key
        # ------------------------------------------------------------
        def na_drawn__mode_key
            :drawn_vertex_move
        end
        # ---------------------------------------------------------------

        # FUNCTION | Console Banner Hint Lines
        # ------------------------------------------------------------
        def na_drawn__activation_hints
            [
                'Select groups, components or loose geometry first: only the vertices inside them can move',
                'Started with nothing selected: click or box the items to work in, then ENTER or double-click',
                'Drag a box to add vertices, SHIFT+box removes; click a vertex to add it, SHIFT+click removes it',
                'Double-click a face to add its corners — the quick way to take the end of a box',
                'Drag a red, green or blue arrow to move along it, or the centre square to move freely',
                'Press on a pick and drag: the picks move from that vertex (CTRL lands it on a point, CTRL+SHIFT rounds)',
                'ALT+drag the centre square onto a vertex: the base point moves, not the picks — then move from there to the target',
                'Right-click menu: Visible Only; in 2D views Depth Limit and Depth Plane for elevations',
                "Moves snap to the #{Na__InsertPrimatives.Na__DrawnSettings__GridStepLabel} grid — CTRL snaps to a vertex, CTRL+SHIFT snaps to it and rounds",
                'ARROWS lock a running move to an axis: Right red, Left green, Up blue, Down lets go',
                "TAB swaps the gimbal between the drawing axes and the axes of the group the picks share",
                'VCB: a distance while dragging, or X,Y,Z to move by an offset; straight after a move, type to correct it',
                'BKSP takes the last pick back — ESC cancels a move, then clears the picks, then leaves the tool'
            ]
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | SketchUp Tool API — Life Cycle
        # -----------------------------------------------------------------------------

        # ACTIVATE | Read the Selection as the Scope, Then Announce the Tool
        # ------------------------------------------------------------
        def activate
            na_vm__attach_watch
            na_vm__adopt_selection
            super
        end
        # ---------------------------------------------------------------

        # DEACTIVATE | Stop Watching the Model and Clear the Overlay
        # ------------------------------------------------------------
        def deactivate(view)
            na_vm__detach_watch
            na_vm__end_drag
            @na_vm_box = nil
            super
        end
        # ---------------------------------------------------------------

        # RESUME | Catch Up With Anything That Changed While Away
        # ------------------------------------------------------------
        def resume(view)
            super
            na_vm__refresh_if_dirty
            view.invalidate if view
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Watching the Model
        # -----------------------------------------------------------------------------
        #
        # An undo, a redo or another tool's edit moves vertices under the picks
        # and can take some away. The same watch the modifier tools ride
        # (DrawnReviseWatch) reports every transaction here; the scope is walked
        # again a beat later, and the picks carried across by
        # Na__VertexMove__Remap. A transaction that is not ours also closes the
        # chance to correct the last move by typing.

        # FUNCTION | Ride the Model While the Tool Is Active
        # ------------------------------------------------------------
        def na_vm__attach_watch
            model = Sketchup.active_model
            return false unless model

            na_vm__detach_watch
            @na_vm_watch ||= Na__InsertPrimatives::DrawnReviseWatch.new(self)
            model.add_observer(@na_vm_watch)
            @na_vm_watched = model
            true
        rescue StandardError => error
            Na__InsertPrimatives.Na__Debug__Puts "NA VERTEX MOVE: could not watch the model — #{error.message}"
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Stop Riding the Model
        # ------------------------------------------------------------
        def na_vm__detach_watch
            model = @na_vm_watched
            @na_vm_watched = nil
            return false unless model && @na_vm_watch

            model.remove_observer(@na_vm_watch)
            true
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Transaction Landed (Called by DrawnReviseWatch)
        # ------------------------------------------------------------
        def na_revise__on_transaction(_kind)
            return false if @na_vm_busy

            @na_vm_dirty  = true
            @na_vm_record = nil
            @na_vm_pivot  = nil                                               # <-- An undo moves the picks back, but not a placed base point: start it afresh
            na_vm__schedule_refresh
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Walk the Scope Again on the Next Tick
        # ------------------------------------------------------------
        # Not inside the observer: the transaction is still settling there.
        # ------------------------------------------------------------
        def na_vm__schedule_refresh
            return false if @na_vm_refresh_due

            @na_vm_refresh_due = true
            UI.start_timer(0, false) do
                begin
                    @na_vm_refresh_due = false
                    na_vm__refresh_if_dirty
                    model = Sketchup.active_model
                    model.active_view.invalidate if model
                rescue StandardError => error
                    Na__InsertPrimatives.Na__Debug__Puts "NA VERTEX MOVE: refresh failed — #{error.message}"
                end
            end
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Walk the Scope Again If the Model Changed Under It
        # ------------------------------------------------------------
        def na_vm__refresh_if_dirty
            return false unless @na_vm_dirty
            return false if @na_vm_busy

            @na_vm_dirty = false
            na_vm__end_drag if @na_vm_drag                                    # <-- Its preview was measured on geometry that has moved
            return false unless @na_vm_phase == :vertices

            na_vm__rescope(@na_vm_roots)
            true
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Scope
        # -----------------------------------------------------------------------------

        # FUNCTION | Take the Current Selection as the Scope
        # ------------------------------------------------------------
        # Nothing selected — or nothing in it with a vertex to move — leaves the
        # tool picking the scope instead.
        # ------------------------------------------------------------
        def na_vm__adopt_selection
            model = Sketchup.active_model
            roots = model ? model.selection.to_a : []

            @na_vm_selected = {}
            @na_vm_history  = []
            @na_vm_record   = nil
            @na_vm_pivot    = nil                                             # <-- A new scope starts from the middle of its picks

            if roots.empty?
                na_vm__enter_scope_phase
                return false
            end

            @na_vm_phase         = :vertices
            @na_vm_selection_ids = roots.map(&:entityID).sort
            na_vm__rescope(roots)

            return true unless @na_vm_scope[:candidates].empty?

            na_vm__enter_scope_phase
            locked = @na_vm_scope[:locked].to_i
            na_vm__notice(
                locked > 0 ? "Everything selected is locked (#{locked}) — pick something else to work in" :
                             'Nothing selected has vertices that can move — pick a group, component or face'
            )
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Go Back to Picking the Scope
        # ------------------------------------------------------------
        def na_vm__enter_scope_phase
            @na_vm_phase      = :scope
            @na_vm_scope      = nil
            @na_vm_roots      = []
            @na_vm_projection = nil
            @na_vm_origin     = nil
            @na_vm_frame      = nil
            @na_vm_hover      = nil
            @na_vm_hover_vertex = nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | ENTER or a Double-Click in the Scope Picker: Start Picking Vertices
        # ------------------------------------------------------------
        def na_vm__confirm_scope
            model = Sketchup.active_model
            return false unless model

            if model.selection.length.zero?
                UI.beep
                na_vm__notice('Nothing picked yet — click a group, component or face to work in')
                return false
            end

            na_vm__adopt_selection
        end
        # ---------------------------------------------------------------

        # FUNCTION | Walk the Scope, Carrying the Picks Across
        # ------------------------------------------------------------
        # `offset` is given straight after a move, so a pick is looked for
        # where it went rather than where it was.
        # ------------------------------------------------------------
        def na_vm__rescope(roots, offset = nil)
            model   = Sketchup.active_model
            carried = @na_vm_selected.values

            @na_vm_roots         = (roots || []).select { |entity| entity && entity.valid? }
            @na_vm_scope         = Na__InsertPrimatives.Na__VertexMove__CollectScope(model, @na_vm_roots)
            @na_vm_scope_serial += 1
            @na_vm_projection    = nil
            @na_vm_selected      = Na__InsertPrimatives.Na__VertexMove__Remap(@na_vm_scope, carried, offset, !offset.nil?)
            na_vm__picks_changed
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Scope Follows the Selection
        # ------------------------------------------------------------
        # Click another group in the Outliner while the tool runs and that is
        # the scope now. An emptied selection keeps the scope: there is no way
        # to say "nothing" that the user would mean.
        # ------------------------------------------------------------
        def na_vm__follow_selection
            return false unless @na_vm_phase == :vertices
            return false if @na_vm_drag || @na_vm_busy

            model = Sketchup.active_model
            return false unless model

            selection = model.selection
            count     = selection.length.to_i
            return false if count.zero?
            return false if count > NA_VM_SELECTION_FOLLOW_MAX && count == @na_vm_selection_ids.length

            ids = selection.to_a.map(&:entityID).sort
            return false if ids == @na_vm_selection_ids

            @na_vm_selection_ids = ids
            @na_vm_record        = nil
            @na_vm_pivot         = nil
            na_vm__rescope(selection.to_a)
            na_vm__notice("Scope follows the selection — #{@na_vm_scope[:roots].length} item#{@na_vm_scope[:roots].length == 1 ? '' : 's'}, #{@na_vm_selected.length} picks kept")
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Picks Changed — Re-Aim the Gimbal
        # ------------------------------------------------------------
        def na_vm__picks_changed
            @na_vm_dots  = nil
            entries      = @na_vm_selected.values
            @na_vm_frame = Na__InsertPrimatives.Na__VertexMove__Frame(Sketchup.active_model, @na_vm_scope, entries, @na_vm_frame_mode)
            @na_vm_origin =
                if entries.empty?
                    nil
                else
                    @na_vm_pivot || Na__InsertPrimatives.Na__VertexMove__Centre(entries.map { |entry| entry[:world] }, @na_vm_frame[:axes])   # <-- A placed base point wins
                end

            @na_last_status_text = nil
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | SketchUp Tool API — Mouse
        # -----------------------------------------------------------------------------

        # ON MOUSE MOVE | Hover, Box or Drag
        # ------------------------------------------------------------
        def onMouseMove(flags, x, y, view)
            na_drawn__sync_modifier(flags)
            @na_last_mouse_x = x
            @na_last_mouse_y = y

            na_vm__refresh_if_dirty
            na_vm__follow_selection
            na_drawn__update_cursor(view, x, y)

            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate
        end
        # ---------------------------------------------------------------

        # ON LEFT BUTTON DOWN | Take a Gimbal Handle, Place a Move, or Start a Box
        # ------------------------------------------------------------
        def onLButtonDown(flags, x, y, view)
            @na_vcb_typing_active = false
            na_drawn__sync_modifier(flags)
            @na_last_mouse_x = x
            @na_last_mouse_y = y
            na_vm__refresh_if_dirty

            if @na_vm_plane_armed && @na_vm_phase == :vertices
                na_vm__pick_plane(view, x, y)                                  # <-- Depth Plane was clicked in the menu: this click names the plane
            elsif @na_vm_pivot_drag
                na_vm__set_pivot(view, x, y)                                   # <-- The second click of an ALT click-move-click
            elsif @na_vm_drag
                @na_drag_press_active = false
                na_vm__update_drag(view, x, y)
                na_vm__commit_drag(view)                                       # <-- The second click of click-move-click
            else
                handle = na_vm__handle_at(view, x, y)
                grab   = (handle || na_vm__removing?) ? nil : na_vm__grab_at(view, x, y)

                if handle == :free && na_vm__alt_down?(flags)
                    na_vm__start_pivot_drag(view, x, y)                        # <-- ALT on the centre square: the base point, not the picks
                elsif handle
                    na_vm__start_drag(view, handle, x, y)
                elsif grab
                    na_vm__start_drag(view, :vertex, x, y, grab)               # <-- Press on a pick and drag: the picks move from that vertex
                else
                    na_vm__start_box(x, y)
                end
            end

            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate
        end
        # ---------------------------------------------------------------

        # ON LEFT BUTTON UP | Press-Drag-Release Places a Move; a Box Is Applied
        # ------------------------------------------------------------
        def onLButtonUp(flags, x, y, view)
            na_drawn__sync_modifier(flags)

            if @na_vm_pivot_drag
                na_vm__release_pivot_drag(view, x, y)                          # <-- Placed if it travelled, else click-move-click
            elsif @na_vm_drag
                return unless @na_drag_press_active

                @na_drag_press_active = false
                travelled = (x.to_f - @na_press_x.to_f).abs + (y.to_f - @na_press_y.to_f).abs

                if travelled < NA_DRAWN_DRAG_MIN_PX
                    # A click on a gimbal handle starts click-move-click. A
                    # click on a pick is just a click: a second click on a
                    # vertex just picked must never leave the picks on the
                    # mouse, and in a 2D view it takes the vertex behind.
                    if @na_vm_drag[:handle] == :vertex
                        na_vm__end_drag
                        na_vm__click_vertex(view, x, y)
                    end

                    na_drawn__update_status_text
                    na_drawn__refresh_vcb
                    view.invalidate
                    return
                end

                na_vm__update_drag(view, x, y)
                na_vm__commit_drag(view)
            elsif @na_vm_box
                na_vm__finish_box(view, x, y)
            end

            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate
        end
        # ---------------------------------------------------------------

        # ON LEFT BUTTON DOUBLE CLICK | Place, Confirm the Scope, or Take a Face
        # ------------------------------------------------------------
        def onLButtonDoubleClick(flags, x, y, view)
            na_drawn__sync_modifier(flags)

            if @na_vm_drag
                na_vm__commit_drag(view) if @na_vm_drag[:offset].length.to_f >= NA_VM_MIN_MOVE
            elsif @na_vm_phase == :scope
                na_vm__confirm_scope
            else
                na_vm__double_click_face(view, x, y)
            end

            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Re-Read the Cursor for Whatever Is Running
        # ------------------------------------------------------------
        # The shared key handlers call this when CTRL or SHIFT goes down or up
        # with the mouse still, so a snap mode change shows at once.
        # ------------------------------------------------------------
        def na_drawn__update_cursor(view, x, y)
            @na_last_mouse_x = x
            @na_last_mouse_y = y

            if @na_vm_pivot_drag
                na_vm__update_pivot_drag(view, x, y)
            elsif @na_vm_drag
                na_vm__update_drag(view, x, y)
            elsif @na_vm_box
                na_vm__update_box(view, x, y)
            else
                na_vm__update_hover(view, x, y)
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | What Is Under the Cursor While Nothing Is Held
        # ------------------------------------------------------------
        def na_vm__update_hover(view, x, y)
            if @na_vm_phase == :scope
                @na_vm_scope_hover  = na_vm__scope_entity_at(view, x, y)
                @na_vm_hover        = nil
                @na_vm_hover_vertex = nil
                return
            end

            @na_vm_scope_hover  = nil
            @na_vm_hover        = na_vm__handle_at(view, x, y)
            @na_vm_hover_grab   = (@na_vm_hover || na_vm__removing?) ? nil : na_vm__grab_at(view, x, y)
            @na_vm_hover_vertex = (@na_vm_hover || @na_vm_hover_grab) ? nil : na_vm__vertex_at(view, x, y, false, @na_shift_held ? :picked : :unpicked)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is a Press Asking to Remove Rather Than to Hold?
        # ------------------------------------------------------------
        # SHIFT on its own removes. With CTRL as well it is CTRL+SHIFT, the
        # vertex-then-grid snap, so a pick pressed with both is held and moved.
        # ------------------------------------------------------------
        def na_vm__removing?
            @na_shift_held && !@na_ctrl_held
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Pick Under the Cursor That a Press Would Take Hold Of
        # ------------------------------------------------------------
        def na_vm__grab_at(view, x, y)
            return nil unless @na_vm_phase == :vertices
            return nil if @na_vm_selected.empty?

            na_vm__vertex_at(view, x, y, true)
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Gimbal Handle Under the Cursor, or nil
        # ------------------------------------------------------------
        def na_vm__handle_at(view, x, y)
            return nil unless @na_vm_phase == :vertices && @na_vm_origin && @na_vm_frame

            Na__InsertPrimatives.Na__VertexMove__GimbalHit(view, @na_vm_origin, @na_vm_frame[:axes], x, y)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | The Drag
        # -----------------------------------------------------------------------------

        # FUNCTION | Take a Handle: an Arrow, the Centre Square, or a Pick Itself
        # ------------------------------------------------------------
        # An arrow measures along its own line through the gimbal, from where it
        # was grabbed, so taking it by the tip does not jump. The centre square
        # slides on the frame plane that faces the camera most squarely.
        #
        # A pick taken by itself (:vertex) moves freely too, but measured from
        # THAT vertex: it is what lines up with whatever CTRL points at, as the
        # point picked first does in SketchUp's own Move. Its inference starts
        # from the vertex itself, so SketchUp offers the lines along its own
        # edges and along the axes through it. The gimbal still rides on the
        # middle of the picks.
        # ------------------------------------------------------------
        def na_vm__start_drag(view, handle, x, y, grab = nil)
            axes   = @na_vm_frame[:axes]
            centre = @na_vm_origin
            origin = grab ? grab[:world] : centre

            drag = {
                :handle  => handle,
                :origin  => origin,                                           # <-- What the move is measured from
                :centre  => centre,                                           # <-- Where the gimbal rides
                :axes    => axes,
                :frame   => @na_vm_frame[:label],
                :entries => @na_vm_selected.values,
                :offset  => Geom::Vector3d.new(0, 0, 0),
                :travel  => 0.0
            }

            if handle == :free || handle == :vertex
                drag[:normal] = axes[Na__InsertPrimatives.Na__VertexMove__FacingIndex(view, axes)]
                drag[:grab]   = Na__InsertPrimatives.Na__VertexMove__PlaneHit(view, origin, drag[:normal], x, y) || origin
            elsif !na_vm__aim_drag_axis(view, drag, handle, x, y)
                UI.beep
                na_vm__notice('That arrow points straight at you — orbit a little, or use another')
                return false
            end

            drag[:edges] = na_vm__rubber_edges(drag[:entries])

            @na_vm_drag           = drag
            @na_state             = :picking_depth                            # <-- The shared InputPoint pick reads from the gimbal while not idle
            @na_point_a           = origin
            @na_ip_origin         = na_vm__inference_origin(view, origin, grab)
            @na_axis_lock         = nil
            @na_cursor_raw        = nil
            @na_cursor_snapped    = nil
            @na_drag_press_active = true
            @na_press_x           = x
            @na_press_y           = y
            @na_vm_hover          = handle
            @na_vm_hover_vertex   = nil
            @na_vm_record         = nil                                       # <-- Taking hold of something else ends the chance to correct the last move
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | The InputPoint CTRL's Inference Is Measured From
        # ------------------------------------------------------------
        # For a pick taken by itself, an InputPoint picked ON that vertex, so
        # SketchUp knows the geometry it belongs to and offers its edges'
        # directions as well as the axes. Anywhere else, or if the pick lands
        # somewhere other than the vertex, a bare point does.
        # ------------------------------------------------------------
        def na_vm__inference_origin(view, origin, grab)
            if grab
                screen = view.screen_coords(origin)
                picked = Sketchup::InputPoint.new
                picked.pick(view, screen.x.to_i, screen.y.to_i)
                position = picked.position

                return picked if position && position.distance(origin).to_f < NA_VM_MATCH_TOL * 10.0
            end

            Sketchup::InputPoint.new(origin)
        rescue StandardError
            Sketchup::InputPoint.new(origin)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Measure the Drag Along One Frame Axis From Here On
        # ------------------------------------------------------------
        # The offset already in hand is carried, so locking or releasing an
        # axis mid-drag never jumps.
        # ------------------------------------------------------------
        def na_vm__aim_drag_axis(view, drag, key, x, y)
            axis  = drag[:axes][NA_VM_AXIS_KEYS.index(key)]
            param = Na__InsertPrimatives.Na__VertexMove__AxisParam(view, drag[:origin], axis, x, y)
            return false unless param

            drag[:axis]       = axis
            drag[:axis_key]   = key
            drag[:grab_param] = param - drag[:offset].dot(axis).to_f
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Follow the Cursor With the Snap the Keys Ask For
        # ------------------------------------------------------------
        def na_vm__update_drag(view, x, y)
            drag = @na_vm_drag
            return false unless drag

            @na_cursor_raw     = nil
            @na_cursor_snapped = nil
            mode               = na_drawn__snap_mode

            drag[:axis] ? na_vm__track_axis(view, drag, mode, x, y) : na_vm__track_free(view, drag, mode, x, y)
        end
        # ---------------------------------------------------------------

        # FUNCTION | An Arrow Drag: a Signed Travel Along the Axis
        # ------------------------------------------------------------
        # Plain: the pick ray's closest point on the axis, from the grab, rounded.
        # CTRL: the inferred point, measured from the gimbal along the axis.
        # CTRL+SHIFT: the same, rounded — the TRAVEL is rounded, as Push/Pull
        # rounds its distance, so picks that start on the grid end on it.
        # ------------------------------------------------------------
        def na_vm__track_axis(view, drag, mode, x, y)
            axis = drag[:axis]
            raw  = nil

            unless mode == :grid
                point = na_drawn__input_point_position(view, x, y)
                if point
                    raw            = (point - drag[:origin]).dot(axis).to_f
                    @na_cursor_raw = point
                end
            end

            if raw.nil?
                param = Na__InsertPrimatives.Na__VertexMove__AxisParam(view, drag[:origin], axis, x, y)
                return false unless param                                     # <-- Hold the last good travel

                raw = param - drag[:grab_param]
            end

            travel        = na_drawn__snap_distance(raw).to_f
            drag[:travel] = travel
            drag[:offset] = Na__InsertPrimatives.Na__VertexMove__Scale(axis, travel)

            @na_cursor_snapped = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(@na_cursor_raw, axis, travel - raw) if @na_cursor_raw
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Free Drag: an Offset Rounded Along Each Frame Axis
        # ------------------------------------------------------------
        # Plain: where the pick ray meets the facing frame plane, from the grab.
        # CTRL: the inferred point, so the gimbal lands exactly on it.
        # CTRL+SHIFT: the same with each component rounded to the grid.
        # ------------------------------------------------------------
        def na_vm__track_free(view, drag, mode, x, y)
            axes = drag[:axes]

            if mode == :grid
                point = Na__InsertPrimatives.Na__VertexMove__PlaneHit(view, drag[:origin], drag[:normal], x, y)
                return false unless point

                raw = point - drag[:grab]
            else
                point = na_drawn__input_point_position(view, x, y)
                return false unless point

                raw            = point - drag[:origin]
                @na_cursor_raw = point
            end

            values        = Na__InsertPrimatives.Na__VertexMove__Components(raw, axes).map { |value| na_drawn__snap_distance(value).to_f }
            drag[:offset] = Na__InsertPrimatives.Na__VertexMove__FromComponents(values, axes)
            drag[:travel] = drag[:offset].length.to_f

            @na_cursor_snapped = drag[:origin] + drag[:offset] if @na_cursor_raw
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Place the Drag
        # ------------------------------------------------------------
        def na_vm__commit_drag(view)
            drag = @na_vm_drag
            return false unless drag

            na_vm__end_drag

            if drag[:offset].length.to_f < NA_VM_MIN_MOVE
                na_vm__notice('Nothing moved — the drag came back to where it started')
                return false
            end

            na_vm__move(view, drag[:entries], drag[:offset], na_vm__describe_drag(drag))
        end
        # ---------------------------------------------------------------

        # FUNCTION | Let Go of the Drag Without Placing It
        # ------------------------------------------------------------
        def na_vm__end_drag
            @na_vm_drag           = nil
            @na_state             = :idle
            @na_point_a           = nil
            @na_axis_lock         = nil
            @na_drag_press_active = false
            @na_cursor_raw        = nil
            @na_cursor_snapped    = nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Make the Move, Then Carry the Picks to Where They Went
        # ------------------------------------------------------------
        def na_vm__move(view, entries, offset, description)
            model = Sketchup.active_model
            return false unless model

            user_path    = model.respond_to?(:active_path) ? model.active_path : nil
            pivot_before = @na_vm_pivot
            @na_vm_busy  = true
            tally        = nil

            begin
                tally = Na__InsertPrimatives.Na__VertexMove__Apply(model, @na_vm_roots, entries, offset)
            ensure
                @na_vm_busy = false
            end

            @na_vm_dirty = false
            na_vm__carry_pivot(offset) if tally[:success]                    # <-- A placed base point travels with the picks
            na_vm__rescope(@na_vm_roots, tally[:success] ? offset : nil)

            unless tally[:success]
                @na_vm_record = nil
                UI.beep
                na_vm__notice("Nothing moved — #{tally[:errors].first || 'SketchUp refused the move'}")
                Na__InsertPrimatives.Na__Debug__Puts "NA VERTEX MOVE: refused — #{tally[:errors].join(' | ')}"
                return false
            end

            @na_vm_record = {
                :entries      => @na_vm_selected.values,
                :offset       => offset,
                :ops          => tally[:ops],
                :user_path    => user_path,
                :pivot_before => pivot_before,                                # <-- Where a retype puts the base point back before moving again
                :description  => description
            }

            na_vm__notice(na_vm__move_report(tally, description))
            Na__InsertPrimatives.Na__Debug__Puts "NA VERTEX MOVE: #{tally[:moved]} moved #{description}, " \
                                                 "#{tally[:ops]} op(s), #{tally[:entered]} opened, #{tally[:folded]} fold line(s), " \
                                                 "#{tally[:missed]} missed#{tally[:errors].empty? ? '' : ", errors: #{tally[:errors].join(' | ')}"}"
            view.invalidate if view
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | What a Finished Move Says in the Status Bar
        # ------------------------------------------------------------
        def na_vm__move_report(tally, description)
            moved = tally[:moved]
            text  = "Moved #{moved} vert#{moved == 1 ? 'ex' : 'ices'} #{description}"
            text += " — #{tally[:folded]} fold line#{tally[:folded] == 1 ? '' : 's'} keep bent faces flat" if tally[:folded] > 0
            text += " — #{tally[:missed]} could not be found" if tally[:missed] > 0
            text += " — #{tally[:errors].length} group#{tally[:errors].length == 1 ? '' : 's'} refused: #{tally[:errors].first}" unless tally[:errors].empty?
            "#{text} — type a distance to correct it"
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Edges the Preview Stretches
        # ------------------------------------------------------------
        # Every edge with a picked end, once per context: [near, near_moves,
        # far, far_moves] in world, so a frame only adds the offset.
        # ------------------------------------------------------------
        def na_vm__rubber_edges(entries)
            moving = {}
            entries.each { |entry| moving[[entry[:context][:key], entry[:vertex]]] = entry }

            seen  = {}
            edges = []

            entries.each do |entry|
                vertex  = entry[:vertex]
                context = entry[:context]
                next unless vertex && vertex.valid?

                vertex.edges.each do |edge|
                    mark = [context[:key], edge]
                    next if seen[mark]

                    seen[mark] = true
                    other      = edge.other_vertex(vertex)
                    partner    = moving[[context[:key], other]]
                    far        = partner ? partner[:world] : na_vm__world_of(other, context)

                    edges << [entry[:world], true, far, !partner.nil?]
                    return edges if edges.length >= NA_VM_MAX_RUBBER_EDGES
                end
            end

            edges
        rescue StandardError
            []
        end
        # ---------------------------------------------------------------

        # FUNCTION | Where a Vertex Stands in the World, Given Its Context
        # ------------------------------------------------------------
        def na_vm__world_of(vertex, context)
            context[:open] ? vertex.position : vertex.position.transform(context[:transformation])
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Drag in Words: "300 mm along red" or "120, -40, 0 mm"
        # ------------------------------------------------------------
        def na_vm__describe_drag(drag)
            frame = drag[:frame].to_s == 'drawing' ? '' : " (#{drag[:frame]} axes)"

            if drag[:axis]
                "#{Na__InsertPrimatives.Na__DrawnFormat__Mm(drag[:travel])} mm along #{NA_VM_AXIS_LABELS[drag[:axis_key]]}#{frame}"
            else
                "by #{na_vm__components_text(drag[:offset], drag[:axes], ', ')} mm#{frame}"
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | An Offset as Whole Millimetres Along the Frame
        # ------------------------------------------------------------
        def na_vm__components_text(offset, axes, separator = ',')
            Na__InsertPrimatives.Na__VertexMove__Components(offset, axes).map do |value|
                Na__InsertPrimatives.Na__DrawnFormat__Mm(value).to_s
            end.join(separator)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Overrides — Keys
        # -----------------------------------------------------------------------------

        # FUNCTION | ARROWS Lock a Running Move to an Axis; DOWN Lets Go
        # ------------------------------------------------------------
        def na_drawn__apply_axis_lock(axis, view)
            drag = @na_vm_drag
            return false unless drag                                          # <-- Nothing to lock until something is moving

            x = @na_last_mouse_x
            y = @na_last_mouse_y

            if axis.nil? || axis == @na_axis_lock
                @na_axis_lock = nil

                if drag[:handle] == :free || drag[:handle] == :vertex
                    hit          = Na__InsertPrimatives.Na__VertexMove__PlaneHit(view, drag[:origin], drag[:normal], x, y)
                    drag[:axis]  = nil
                    drag[:axis_key] = nil
                    drag[:grab]  = hit ? hit - drag[:offset] : drag[:origin]
                else
                    na_vm__aim_drag_axis(view, drag, drag[:handle], x, y)
                end
            elsif na_vm__aim_drag_axis(view, drag, axis, x, y)
                @na_axis_lock = axis
            else
                UI.beep
                na_vm__notice('That axis points straight at you — orbit a little first')
                return false
            end

            na_vm__update_drag(view, x, y)
            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | TAB Swaps the Gimbal Between the Drawing and Group Axes
        # ------------------------------------------------------------
        def na_drawn__cycle_plane_lock(view)
            if @na_vm_drag
                UI.beep
                na_vm__notice('Place or cancel the move before swapping the axes')
                return false
            end

            @na_vm_frame_mode = @na_vm_frame_mode == :local ? :drawing : :local
            na_vm__picks_changed

            label = @na_vm_frame ? @na_vm_frame[:label] : 'drawing'
            na_vm__notice(
                @na_vm_frame_mode == :local ? "Gimbal on the #{label} axes — TAB for the drawing axes" :
                                              'Gimbal on the drawing axes — TAB for the axes of the group the picks share'
            )
            view.invalidate if view
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | BKSP: Drop the Drag or the Box, Else Take the Last Pick Back
        # ------------------------------------------------------------
        def na_drawn__step_back(view)
            if @na_vm_drag
                na_vm__end_drag
            elsif @na_vm_box
                @na_vm_box = nil
            elsif @na_vm_phase == :vertices && !na_vm__pick_step_back
                UI.beep
            end

            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
        end
        # ---------------------------------------------------------------

        # ON CANCEL | ESC: the Move, Then the Picks, Then the Tool
        # ------------------------------------------------------------
        # Reason 2 is an undo while the tool is active: the model moved, so the
        # drag is dropped and the scope is walked again.
        # ------------------------------------------------------------
        def onCancel(reason, view)
            @na_vcb_typing_active = false

            if reason == 2
                na_revise__on_transaction(:undo)
                na_vm__end_drag
                @na_vm_box = nil
            elsif @na_vm_plane_armed
                @na_vm_plane_armed = false
                na_vm__notice('No plane picked — the depth stays measured as it was')
            elsif na_vm__cancel_pivot_drag
                na_vm__notice('Base point left where it was')
            elsif @na_vm_drag
                na_vm__end_drag
                na_vm__notice('Move cancelled — nothing changed')
            elsif @na_vm_box
                @na_vm_box = nil
            elsif @na_vm_phase == :vertices && na_vm__reset_pivot
                na_vm__notice('Base point back in the middle of the picks — ESC again clears the picks')
            elsif @na_vm_phase == :vertices && !@na_vm_selected.empty?
                cleared = na_vm__pick_clear
                na_vm__notice("Cleared #{cleared} pick#{cleared == 1 ? '' : 's'} — BKSP brings them back, ESC again leaves the tool")
            elsif reason == 0
                na_drawn__schedule_exit_tool
            end

            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
        end
        # ---------------------------------------------------------------

        # ON RETURN | Enter Places a Held Move, or Starts Picking Vertices
        # ------------------------------------------------------------
        def onReturn(view)
            handled =
                if @na_vm_drag
                    na_vm__commit_drag(view)
                    true
                elsif @na_vm_phase == :scope
                    na_vm__confirm_scope
                    true
                else
                    false
                end

            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
            handled
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Measurements Box Entry
        # -----------------------------------------------------------------------------

        # FUNCTION | A Distance, or X,Y,Z — Into the Drag, or Correcting the Last Move
        # ------------------------------------------------------------
        # Two readings of a sign, as in Push/Pull, and on purpose:
        # - WHILE DRAGGING the direction is the mouse's. A bare 300 is 300 that
        #   way, and +50 / -25 add to or take from the live distance.
        # - AFTER A MOVE there is no drag to be relative to, so the sign names
        #   the direction: 1200 makes the move 1200, -1200 turns it round.
        # X,Y,Z is always signed components along the gimbal's axes; an empty
        # slot keeps what the drag holds (or 0 after a move).
        # ------------------------------------------------------------
        def na_drawn__handle_vcb_text(text, view)
            raise ArgumentError, 'pick what to work in first, then ENTER' if @na_vm_phase == :scope

            tokens = Na__InsertPrimatives.Na__DrawnVcb__ParseEntry(text)
            raise ArgumentError, 'type a distance, or X,Y,Z' if tokens.compact.empty?
            raise ArgumentError, 'three values at most — X,Y,Z' if tokens.length > 3

            return na_vm__type_into_drag(tokens, view) if @na_vm_drag

            if @na_vm_selected.empty?
                UI.beep
                na_vm__notice('Pick some vertices first — drag a box round them')
                return false
            end

            record = @na_vm_record
            axes   = @na_vm_frame[:axes]

            if tokens.length == 1
                unless record
                    UI.beep
                    na_vm__notice('Drag an arrow first, or type X,Y,Z to move by an offset')
                    return false
                end

                sign, magnitude = tokens[0]
                distance        = sign == :minus ? -magnitude.to_f : magnitude.to_f
                raise ArgumentError, 'a move of zero' if distance.abs < NA_VM_MIN_MOVE

                offset = Na__InsertPrimatives.Na__VertexMove__Scale(record[:offset].normalize, distance)
                return na_vm__retype(offset, view, "#{Na__InsertPrimatives.Na__DrawnFormat__Mm(distance)} mm")
            end

            offset = na_vm__offset_from_tokens(tokens, [0.0, 0.0, 0.0], axes)
            raise ArgumentError, 'a move of zero' if offset.length.to_f < NA_VM_MIN_MOVE

            description = "by #{na_vm__components_text(offset, axes, ', ')} mm"
            return na_vm__retype(offset, view, description) if record

            na_vm__move(view, @na_vm_selected.values, offset, description)
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Typed Value While Dragging — Pins It and Places
        # ------------------------------------------------------------
        def na_vm__type_into_drag(tokens, view)
            drag = @na_vm_drag

            if tokens.length == 1
                token = tokens[0]

                if drag[:axis]
                    live      = drag[:travel].to_f
                    magnitude = Na__InsertPrimatives.Na__DrawnVcb__ResolveAgainst([token], [live.abs])[0]
                    Na__InsertPrimatives.Na__DrawnVcb__ValidatePositive([magnitude], ['Distance'])

                    drag[:travel] = live < 0.0 ? -magnitude : magnitude
                    drag[:offset] = Na__InsertPrimatives.Na__VertexMove__Scale(drag[:axis], drag[:travel])
                else
                    live = drag[:offset]
                    raise ArgumentError, 'move the mouse to show which way first, or type X,Y,Z' if live.length.to_f < NA_VM_MIN_MOVE

                    magnitude = Na__InsertPrimatives.Na__DrawnVcb__ResolveAgainst([token], [live.length.to_f])[0]
                    Na__InsertPrimatives.Na__DrawnVcb__ValidatePositive([magnitude], ['Distance'])

                    drag[:offset] = Na__InsertPrimatives.Na__VertexMove__Scale(live.normalize, magnitude)
                end
            else
                live          = Na__InsertPrimatives.Na__VertexMove__Components(drag[:offset], drag[:axes])
                drag[:offset] = na_vm__offset_from_tokens(tokens, live, drag[:axes])
                drag[:axis]   = nil                                           # <-- Components are a free move, whatever was grabbed
                raise ArgumentError, 'a move of zero' if drag[:offset].length.to_f < NA_VM_MIN_MOVE
            end

            na_vm__commit_drag(view)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Typed X,Y,Z to a World Offset Along the Frame
        # ------------------------------------------------------------
        def na_vm__offset_from_tokens(tokens, live, axes)
            values = (0..2).map do |index|
                token = tokens[index]
                next live[index].to_f if token.nil?

                sign, magnitude = token
                sign == :minus ? -magnitude.to_f : magnitude.to_f
            end

            Na__InsertPrimatives.Na__VertexMove__FromComponents(values, axes)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Correct the Last Move: Take It Back and Make It Again
        # ------------------------------------------------------------
        # The Push/Pull way (DrawnReviseShared): undo our own step(s), stand the
        # user back where they were, find the picks where they stood before,
        # and move them by the new offset. The watch closes the record the
        # moment anything else lands, so the undo can only ever take ours.
        # ------------------------------------------------------------
        def na_vm__retype(offset, view, description)
            record = @na_vm_record
            model  = Sketchup.active_model
            return false unless record && model

            @na_vm_busy = true
            begin
                record[:ops].to_i.times { Sketchup.undo }
                na_vm__restore_context(model, record[:user_path])
            rescue StandardError => error
                @na_vm_record = nil
                UI.beep
                na_vm__notice("Could not take the last move back — #{error.message}")
                return false
            ensure
                @na_vm_busy = false
            end

            @na_vm_dirty = false
            @na_vm_pivot = record[:pivot_before]                              # <-- The base point goes back with the move it rode
            na_vm__rescope(@na_vm_roots)
            entries = @na_vm_selected.values

            if entries.empty?
                @na_vm_record = nil
                UI.beep
                na_vm__notice('Could not find the picks again after taking the move back — Redo puts it back')
                return false
            end

            na_vm__move(view, entries, offset, description)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Put the User Back in the Context They Were In
        # ------------------------------------------------------------
        def na_vm__restore_context(model, wanted)
            return false unless model.respond_to?(:active_path=)
            return false if Na__InsertPrimatives.Na__DeepPick__SameContext?(model.active_path, wanted)

            model.active_path = wanted
            true
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Say Something the Composed Status Line Will Not Wipe
        # ------------------------------------------------------------
        def na_vm__notice(message)
            UI.start_timer(NA_VM_NOTICE_DELAY_S, false) do
                begin
                    Sketchup::set_status_text(message, SB_PROMPT)
                    @na_last_status_text = message
                rescue StandardError
                    nil
                end
            end
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Status and Measurements Box
        # -----------------------------------------------------------------------------

        # FUNCTION | Middle Section of the Status Bar Line
        # ------------------------------------------------------------
        def na_drawn__status_detail
            return na_vm__scope_status if @na_vm_phase == :scope
            return 'Click the face the depth is measured from — ESC keeps the first visible plane' if @na_vm_plane_armed
            return na_vm__pivot_status if @na_vm_pivot_drag

            drag = @na_vm_drag
            if drag
                typed = drag[:axis] ? 'a distance' : 'a distance or X,Y,Z'
                place = drag[:handle] == :vertex ? 'release to place' : 'release or click to place'
                return "Move #{na_vm__describe_drag(drag)} — #{place}, or type #{typed}#{na_vm__shared_note(drag[:entries])}"
            end

            box = @na_vm_box
            if box && box[:active]
                count = (box[:hits] || []).length
                return @na_shift_held ? "SHIFT box — #{count} to remove" : "Box — #{count} to add, SHIFT to remove instead"
            end

            picked = @na_vm_selected.length
            return 'Drag a box round the vertices to move — click one to add it, SHIFT removes, double-click a face for its corners' if picked.zero?
            return 'Drag this vertex to move the picks from it — CTRL snaps it to a point, CTRL+SHIFT then rounds' if @na_vm_hover_grab
            return 'ALT+drag the base point onto a vertex — the picks stay put; moves then go from there' if @na_vm_hover == :free && na_vm__alt_down?

            base   = @na_vm_pivot ? ' from the placed base point (ESC resets it)' : ''
            hover  = @na_vm_hover == :free ? ' — ALT+drag sets the base point' : ''
            retype = @na_vm_record ? " — moved #{@na_vm_record[:description]}, type to correct it" : ''
            "#{picked} vert#{picked == 1 ? 'ex' : 'ices'} — drag an arrow to move along it, the centre square or a pick to move freely#{base}#{hover}#{retype}#{na_vm__shared_note(@na_vm_selected.values)}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | What the Scope Picker Says
        # ------------------------------------------------------------
        def na_vm__scope_status
            model  = Sketchup.active_model
            picked = model ? model.selection.length.to_i : 0
            start  = picked > 0 ? " — #{picked} picked, ENTER or double-click to start" : ''

            "Pick what to work in: click a group, component or face, box adds, SHIFT removes#{start}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Say So When the Picks Sit in a Definition With Copies
        # ------------------------------------------------------------
        def na_vm__shared_note(entries)
            entry  = entries.find { |candidate| candidate[:context][:shared] }
            shared = entry ? entry[:context][:shared] : nil
            shared ? " — inside #{shared[:name]}, which has #{shared[:count]} copies" : ''
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Scope, Where the Shape Tools Name Their Plane
        # ------------------------------------------------------------
        def na_drawn__plane_description
            scope = @na_vm_scope
            return 'No scope yet' unless scope && @na_vm_phase == :vertices

            items = scope[:roots].length
            text  = "Scope #{items} item#{items == 1 ? '' : 's'}, #{scope[:candidates].length} vertices"
            text += ", #{scope[:locked]} locked skipped" if scope[:locked] > 0
            text += ', CUT SHORT' if scope[:truncated]
            text += ' (too many to show)' if scope[:candidates].length > NA_VM_MAX_DRAWN_POINTS
            text + na_vm__depth_status
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Depth Limit, While It Is in Force (2D Views Only)
        # ------------------------------------------------------------
        def na_vm__depth_status
            model = Sketchup.active_model
            depth = model ? na_vm__depth_in_force(model.active_view) : nil
            return '' unless depth

            from = @na_vm_depth_plane ? 'the picked plane' : 'the first visible plane'
            " | DEPTH #{Na__InsertPrimatives.Na__DrawnFormat__Mm(depth)} mm from #{from}"
        rescue StandardError
            ''
        end
        # ---------------------------------------------------------------

        # FUNCTION | What TAB Does in This Tool
        # ------------------------------------------------------------
        def na_drawn__tab_hint
            return 'TAB axes: drawing' unless @na_vm_frame_mode == :local

            "TAB axes: #{@na_vm_frame ? @na_vm_frame[:label] : 'group'}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Measurements Box Label and Live Value
        # ------------------------------------------------------------
        def na_drawn__vcb_label_and_value
            drag = @na_vm_drag
            if drag
                return ['Distance', Na__InsertPrimatives.Na__DrawnFormat__Mm(drag[:travel]).abs.to_s] if drag[:axis]

                return ['Offset', na_vm__components_text(drag[:offset], drag[:axes])]
            end

            return ['', ''] if @na_vm_phase == :scope
            return ['Distance', Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_vm_record[:offset].length).to_s] if @na_vm_record

            ['Offset', '']
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Unused Stages
        # -----------------------------------------------------------------------------

        # FUNCTION | Never Reached — There Is No Rectangle Stage
        # ------------------------------------------------------------
        def na_drawn__advance_from_b(view)
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Shared Enter and Double-Click Paths Place a Held Move
        # ------------------------------------------------------------
        def na_drawn__advance_from_depth(view)
            na_vm__commit_drag(view)
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Preview Is Drawn by draw Below
        # ------------------------------------------------------------
        def na_drawn__draw_preview(view)
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | No Shared Preview Points — getExtents Is Taken Over
        # ------------------------------------------------------------
        def na_drawn__preview_points
            []
        end
        # ---------------------------------------------------------------

        # FUNCTION | No Axis Ray — the Gimbal Draws Its Own Guide
        # ------------------------------------------------------------
        def na_drawn__axis_ray_origin
            nil
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Draw
        # -----------------------------------------------------------------------------

        # DRAW | Candidates, Picks, the Box, the Gimbal and a Running Move
        # ------------------------------------------------------------
        def draw(view)
            if @na_vm_phase == :scope
                na_vm__draw_scope_hover(view)
                na_vm__draw_box(view)
                return
            end

            na_vm__draw_depth_plane(view)
            na_vm__draw_candidates(view)

            if @na_vm_drag
                na_vm__draw_drag(view)
                return
            end

            na_vm__draw_squares(view, @na_vm_selected.values.map { |entry| entry[:world] }, na_vm__pick_half(view), NA_VM_PICKED_FILL, NA_VM_PICKED_BORDER)
            na_vm__draw_hover_vertex(view)
            na_vm__draw_box(view)

            return unless @na_vm_origin && @na_vm_frame

            if @na_vm_pivot_drag
                na_vm__draw_pivot_drag(view)                                  # <-- The base point on its way; the picks stay put
                return
            end

            na_vm__draw_pivot_mark(view)
            Na__InsertPrimatives.Na__VertexMove__DrawGimbal(view, @na_vm_origin, @na_vm_frame[:axes], @na_vm_hover)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Every Unpicked Vertex in Scope as a Muted Red Square
        # ------------------------------------------------------------
        # The picks are left out: they carry their own orange square, drawn on
        # top. SketchUp draws a tool's points over the model, faces or not, so
        # with Visible Only on the squares behind a face are filtered out here
        # (DrawnVertexMoveFilters#na_vm__sight_for). A scope too big to draw
        # says so in the status bar instead.
        # ------------------------------------------------------------
        def na_vm__draw_candidates(view)
            points = na_vm__dot_points(view)
            return if points.empty?

            view.draw_points(points, na_vm__dot_px(view).round, 2, NA_VM_CANDIDATE_COLOUR)
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Squares' Points, Rebuilt When the Picks or the Sightings Change
        # ------------------------------------------------------------
        def na_vm__dot_points(view = nil)
            scope = @na_vm_scope
            return [] unless scope
            return [] if scope[:candidates].length > NA_VM_MAX_DRAWN_POINTS

            view ||= Sketchup.active_model.active_view
            sight  = na_vm__visible_only? ? na_vm__sight_for(view) : nil
            cache  = @na_vm_dots
            return cache[:points] if cache && cache[:serial] == @na_vm_scope_serial && cache[:sight].equal?(sight)

            shown  = scope[:candidates].reject { |candidate| @na_vm_selected.key?(candidate[:key]) }
            shown  = shown.select { |candidate| sight[candidate[:key]] } if sight
            points = shown.map { |candidate| candidate[:world] }

            @na_vm_dots = { :serial => @na_vm_scope_serial, :sight => sight, :points => points }
            points
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Vertex Size the Menu Sets, in Pixels
        # ------------------------------------------------------------
        def na_vm__dot_base_px
            NA_VM_DOT_BASE_PX[Na__InsertPrimatives.Na__ToolOptions__Value(NA_VM_OPTION_DOT_SIZE).to_s] || NA_VM_DOT_BASE_PX['medium']
        end
        # ---------------------------------------------------------------

        # FUNCTION | How Big the Unpicked Squares Are, in Pixels
        # ------------------------------------------------------------
        # The base size when the scope's box fills NA_VM_DOT_REF_SHARE of the
        # view's diagonal. Zoomed in on it the squares get smaller, zoomed out
        # bigger, on a log curve: 5.2.7's straight inverse doubled or halved
        # them for every doubling of the zoom and hit both clamps at once in
        # use, too big far away and too small up close. One size for every
        # square, measured at the middle of the scope.
        # ------------------------------------------------------------
        def na_vm__dot_px(view)
            base  = na_vm__dot_base_px
            scope = @na_vm_scope
            return base unless scope && scope[:min]

            low      = Geom::Point3d.new(*scope[:min])
            high     = Geom::Point3d.new(*scope[:max])
            diagonal = low.distance(high).to_f
            return base unless diagonal > 0.0

            middle = Geom::Point3d.new((low.x + high.x) * 0.5, (low.y + high.y) * 0.5, (low.z + high.z) * 0.5)
            per_px = view.pixels_to_model(1.0, middle).to_f
            return base unless per_px > 0.0

            zoom  = (NA_VM_DOT_REF_SHARE * Math.hypot(view.vpwidth, view.vpheight)) / (diagonal / per_px)
            sized = base * (1.0 + (NA_VM_DOT_LOG_GAIN * Math.log(zoom)))
            sized.clamp(base * NA_VM_DOT_MIN_SHARE, base * NA_VM_DOT_MAX_SHARE)
        rescue StandardError
            na_vm__dot_base_px
        end
        # ---------------------------------------------------------------

        # FUNCTION | Half the Side of a Pick's Square — Never Smaller Than the Rest
        # ------------------------------------------------------------
        def na_vm__pick_half(view)
            [4.0, (na_vm__dot_px(view) * 0.5) + 1.0].max
        end
        # ---------------------------------------------------------------

        # FUNCTION | Ring the Vertex a Click Would Take, or the Pick a Press Would Hold
        # ------------------------------------------------------------
        # Blue to add, red with SHIFT to remove, amber on a pick: press and
        # drag it to move the picks from there.
        # ------------------------------------------------------------
        def na_vm__draw_hover_vertex(view)
            candidate = @na_vm_hover_grab || @na_vm_hover_vertex
            return unless candidate
            return unless Na__InsertPrimatives.Na__DrawnPreview__InFrontOfCamera?(view, candidate[:world])

            screen  = view.screen_coords(candidate[:world])
            half    = na_vm__pick_half(view) + 4.0
            corners = [[-half, -half], [half, -half], [half, half], [-half, half]].map do |dx, dy|
                Geom::Point3d.new(screen.x.to_f + dx, screen.y.to_f + dy, 0)
            end

            colour =
                if @na_vm_hover_grab then NA_VM_HOT_COLOUR
                elsif @na_shift_held then NA_VM_BOX_DROP_BORDER
                else                      NA_VM_HOVER_COLOUR
                end

            view.line_stipple  = ''
            view.line_width    = 2
            view.drawing_color = colour
            view.draw2d(GL_LINE_LOOP, corners)
            view.line_width    = 1
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Running Move: Guide, Stretched Edges, Picks, Gimbal, Label
        # ------------------------------------------------------------
        def na_vm__draw_drag(view)
            drag   = @na_vm_drag
            offset = drag[:offset]

            if drag[:axis]
                Na__InsertPrimatives.Na__VertexMove__DrawAxisGuide(view, drag[:origin], drag[:axis], drag[:axis_key])
            else
                Na__InsertPrimatives.Na__VertexMove__DrawStartMark(view, drag[:origin])
            end

            na_vm__draw_rubber(view, drag, offset)

            na_vm__draw_squares(view, drag[:entries].map { |entry| entry[:world] }, 2.5, NA_VM_GHOST_COLOUR, nil)
            na_vm__draw_squares(view, drag[:entries].map { |entry| entry[:world] + offset }, na_vm__pick_half(view), NA_VM_PICKED_FILL, NA_VM_PICKED_BORDER)

            @na_ip.draw(view) if @na_ctrl_held && @na_ip && @na_ip.valid?
            na_drawn__draw_grid_correction(view)                              # <-- CTRL+SHIFT only; the mixin decides

            gimbal = (drag[:centre] || drag[:origin]) + offset
            hot    = drag[:axis] ? drag[:axis_key] : :free
            Na__InsertPrimatives.Na__VertexMove__DrawGimbal(view, gimbal, drag[:axes], hot)

            # A pick taken by itself is ringed where it now stands: it is the
            # point that lines up with whatever CTRL points at.
            if drag[:handle] == :vertex
                landed = drag[:origin] + offset
                na_vm__draw_squares(view, [landed], na_vm__pick_half(view) + 3.0, NA_VM_HOT_COLOUR, NA_VM_PICKED_BORDER)
            end

            lines = ["Move #{na_vm__describe_drag(drag)}", "#{drag[:entries].length} vert#{drag[:entries].length == 1 ? 'ex' : 'ices'}"]
            Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(view, gimbal, lines, 18, 16)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Every Edge With a Picked End, Drawn Where the Move Takes It
        # ------------------------------------------------------------
        def na_vm__draw_rubber(view, drag, offset)
            edges = drag[:edges]
            return if edges.nil? || edges.empty?

            points = []
            edges.each do |near, near_moves, far, far_moves|
                points << (near_moves ? near + offset : near)
                points << (far_moves ? far + offset : far)
            end

            view.line_stipple  = ''
            view.line_width    = 2
            view.drawing_color = NA_DRAWN_VOLUME_BORDER_COLOR
            view.draw(GL_LINES, points)
            view.line_width    = 1
        end
        # ---------------------------------------------------------------

        # GET EXTENTS | Keep the Scope, the Picks and the Move Inside the View Bounds
        # ------------------------------------------------------------
        def getExtents
            bounds = Geom::BoundingBox.new
            scope  = @na_vm_scope

            if scope && scope[:min]
                bounds.add(Geom::Point3d.new(*scope[:min]))
                bounds.add(Geom::Point3d.new(*scope[:max]))
            end

            bounds.add(@na_vm_origin) if @na_vm_origin
            bounds.add(@na_cursor_raw) if @na_cursor_raw

            drag = @na_vm_drag
            if drag
                bounds.add(drag[:origin] + drag[:offset])
                bounds.add(drag[:centre] + drag[:offset]) if drag[:centre]
                drag[:entries].each { |entry| bounds.add(entry[:world] + drag[:offset]) }
            end

            plane = @na_vm_depth_plane
            plane[:loop].each { |point| bounds.add(point) } if plane && plane[:loop]

            bounds.add(@na_vm_scope_hover.bounds) if @na_vm_scope_hover && @na_vm_scope_hover.valid?
            bounds
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnVertexMoveTool class

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Public Entry Point
    # -----------------------------------------------------------------------------

    # FUNCTION | Activate the Deep Vertex Move Tool (Hotkey Entry Point)
    # ------------------------------------------------------------
    def self.Na__InsertPrimatives__DeepVertexMove
        Na__InsertPrimatives.Na__ModeSwitch__ActivateDrawnVertexMoveTool
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP VERTEX MOVE TOOL MODULE
# =============================================================================
