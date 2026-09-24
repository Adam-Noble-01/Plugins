# =============================================================================
# NA INSERT PRIMATIVES - DEEP CHAMFER TOOL
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnChamferTool__.rb
# NAMESPACE  : Na__InsertPrimatives
# CLASS      : DrawnChamferTool
# AUTHOR     : Noble Architecture
# PURPOSE    : Chamfer any edge at any nesting depth, on the shared voxel grid
# CREATED    : 2026
#
# DESCRIPTION:
# - Hover to highlight the edge under the cursor, click to grab it, drag toward
#   the corner to open the chamfer, click (or Enter, or a typed value) to cut.
#   Reaches edges inside groups and components without opening them, exactly as
#   Deep Push/Pull reaches faces.
# - The chamfer is symmetric IN WORLD SPACE: the same setback along each face,
#   which under a non-uniformly scaled instance means the two local setbacks are
#   solved separately from the per-direction scale — the same trap the push
#   tool's normal_scale guards against, in two directions at once.
#
# WHAT THE DRAG MEASURES:
# - The cursor is projected onto the corner bisector (the diagonal running into
#   the material between the two faces) and converted to the per-face setback,
#   which is the number a joiner actually specifies — "a 50 chamfer" is 50 off
#   each face, not 50 along the diagonal. The setback snaps to the voxel step;
#   CTRL suspends that for vertex inference, so a chamfer can be dragged to stop
#   exactly at an existing corner.
#
# LESSONS CARRIED FROM THE PUSH/PULL SAGA (built in from the start, not found):
# - The edit runs inside the edge's own context via ExecuteInContext, so the
#   display refreshes instantly and undo is one Ctrl+Z.
# - Once an edge is grabbed nothing is picked again mid-drag — the distance is
#   pure ray maths, and an unsolvable frame keeps the last good value.
# - Two states only; any state this tool cannot service snaps back to idle.
#
# CONSTRUCTION (local space, one operation) — CAPTURE, SUBSTITUTE, REBUILD:
# - The first construction assumed that an edge added on a face splits it, the
#   way the UI Line tool does. The API documentation promises NO such thing
#   (checked, not guessed — Entities#add_face carries no splitting, merging or
#   intersection behaviour at all), so erasing the corner edge destroyed every
#   face it bounded whole. v0.4.22 shipped that bug.
# - The rebuild never relies on splitting. Every face touching the corner is
#   captured as an ordered loop of positions, the corner vertices are
#   substituted with the offset points (one point on the two chamfer faces,
#   the a/b PAIR on the end faces, clipping their corners), the old faces and
#   corner edge are erased, and the faces re-added with their materials and
#   tags restored. add_face reuses the surviving coincident edges, so the
#   rebuilt shell knits back onto the untouched neighbours.
# - Every plan is built and validated BEFORE anything is erased, and any
#   failure raises — the surrounding operation aborts and the model is left
#   exactly as it was. Failing loudly beats cutting wrongly.
#
# THE OPEN-CONTEXT COORDINATE RULE (corrected in 5.1.2; see the DeepPick hub):
# - "When changing the active entities in SketchUp, the coordinate system also
#   changes" — Model#active_path=. What changes is the space the OPENED group's
#   own geometry is reported AND accepted in: global while it is open, its
#   definition's local space while it is closed. Reads are not "always local".
# - So the build transform is decided by ONE question — was the context
#   entered between reading the plan and adding it? A single cut plans BEFORE
#   entering (local, if the edge sits in a closed group) and adds AFTER, so its
#   points go through model.edit_transform, read inside the block where it is
#   the newly opened session's. A batch plans INSIDE the entered context, where
#   everything it reads is already global, so it adds with the identity. An
#   edge in the user's own context is never entered and reads and adds in the
#   same space, identity again. Getting this wrong is silent: the chamfer is
#   cut, just somewhere else.
#
# AFTER CUTTING — RETYPE, REPEAT, AND THE GHOST:
# - The measurements box stays live after a cut: type 75 and the chamfer just
#   made becomes 75; +5 and -5 adjust it. Hovering, banking more edges and the
#   right-click menu all leave that open; grabbing another edge, changing the
#   model or leaving the tool closes it. Every retype replays the cut-face
#   preview for a beat, sweeping from the old setback to the new.
# - A double-click on an edge with no drag behind it cuts it — and anything
#   banked with it — at the last setback placed, which lives in the model's
#   own attribute dictionary. Mechanics shared with Deep Push/Pull through
#   DrawnReviseShared; the chamfer-specific half is DrawnChamferRevise.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../06__Tools__DrawnShared/Na__InsertPrimatives__DrawnToolShared__'
require_relative '../06__Tools__DrawnShared/Na__InsertPrimatives__DrawnRevise__'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnDeepPick__'
require_relative 'Na__InsertPrimatives__DrawnChamfer__Geometry__'
require_relative 'Na__InsertPrimatives__DrawnChamfer__Mitre__'
require_relative 'Na__InsertPrimatives__DrawnChamfer__Revise__'

module Na__InsertPrimatives

    # @delegate: Na__InsertPrimatives__DrawnChamfer__Geometry__.rb
    # @delegate: Na__InsertPrimatives__DrawnChamfer__Mitre__.rb
    # @delegate: Na__InsertPrimatives__DrawnChamfer__Revise__.rb

    # -----------------------------------------------------------------------------
    # REGION | Deep Chamfer Tool Class
    # -----------------------------------------------------------------------------

    # CLASS | Chamfer Any Edge at Any Nesting Depth
    # ------------------------------------------------------------
    class DrawnChamferTool

        include Na__InsertPrimatives::DrawnToolShared
        include Na__InsertPrimatives::DrawnReviseShared                       # <-- After DrawnToolShared, so its life-cycle wrappers sit over the mixin's
        include Na__InsertPrimatives::DrawnChamferRevise                      # <-- The chamfer half of the revise contract

        NA_CH_HOVER_COLOR   = Sketchup::Color.new(  0, 110, 235, 235)
        NA_CH_SELECT_COLOR  = Sketchup::Color.new(226, 118,   0, 255)         # <-- Edges banked with SHIFT, waiting for the drag
        NA_CH_EDGE_WIDTH    = 5
        NA_CH_MK_SHIFT      = 4                                               # <-- Shift bit in the mouse-event flags (CTRL is 8)

        # INITIALIZE | Tool Constructor
        # ------------------------------------------------------------
        def initialize
            na_drawn__init_shared_state
            na_drawn__clear_target
            na_revise__init_state                                             # <-- No cut placed yet, so nothing to retype or repeat
            @na_ch_multi        = []                                          # <-- SHIFT-banked edge targets, surviving hover and drag-cancel
            @na_ch_batch        = []                                          # <-- Driver + banked, fixed at grab time
            @na_ch_batch_solves = []
        end
        # ---------------------------------------------------------------

        # FUNCTION | Forget the Currently Grabbed Edge
        # The SHIFT-banked selection deliberately lives OUTSIDE this reset: it
        # must survive hovering off an edge and cancelling a drag, and is only
        # emptied by a successful cut, ESC at idle, or a fresh tool.
        # ------------------------------------------------------------
        def na_drawn__clear_target
            @na_ch_target       = nil
            @na_ch_solve        = nil
            @na_ch_anchor       = nil                                         # <-- Grab point on the edge, world
            @na_ch_bisector     = nil                                         # <-- Unit world diagonal into the material
            @na_ch_edge_dir     = nil                                         # <-- Unit world direction along the edge
            @na_ch_plane_normal = nil                                         # <-- Normal of the corner measurement plane
            @na_ch_cos_half     = 1.0
            @na_ch_batch        = []
            @na_ch_batch_solves = []
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is This Target Already Banked? (Index or nil)
        # Same edge through the same instance path counts as the same pick —
        # the identical definition edge seen through a DIFFERENT instance is a
        # different chamfer and stays distinct.
        # ------------------------------------------------------------
        def na_drawn__multi_index_of(target)
            @na_ch_multi.find_index do |banked|
                banked[:edge] == target[:edge] && banked[:path] == target[:path]
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | SHIFT+Click — Bank an Edge, or Un-Bank It Again
        # Each edge is validated on the way IN, so the drag never starts with a
        # passenger that cannot be cut.
        # ------------------------------------------------------------
        def na_drawn__toggle_multi_edge(view, x, y)
            target = Na__InsertPrimatives.Na__DeepPick__EdgeAt(view, x, y)

            unless target
                UI.beep
                Sketchup::set_status_text('No edge under the cursor to add', SB_PROMPT)
                return false
            end

            existing = na_drawn__multi_index_of(target)
            if existing
                @na_ch_multi.delete_at(existing)
                Sketchup::set_status_text("Edge removed — #{@na_ch_multi.length} banked", SB_PROMPT)
                return true
            end

            if target[:locked]
                UI.beep
                Sketchup::set_status_text('That edge is inside a locked group or component', SB_PROMPT)
                return false
            end

            unless target[:face_count] == 2
                UI.beep
                Sketchup::set_status_text("#{na_drawn__cut_phrase.capitalize} needs an edge bordering exactly two faces (this one has #{target[:face_count]})", SB_PROMPT)
                return false
            end

            unless na_drawn__solve_cut(target, 1.0)
                UI.beep
                Sketchup::set_status_text("These faces are too close to flat for #{na_drawn__cut_phrase}", SB_PROMPT)
                return false
            end

            @na_ch_multi << target
            Sketchup::set_status_text("#{@na_ch_multi.length} edge#{@na_ch_multi.length == 1 ? '' : 's'} banked — SHIFT+click adds more, click one to drag them all", SB_PROMPT)
            true
        end
        # ---------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Identity
        # -----------------------------------------------------------------------------

        # FUNCTION | Status Bar Title
        # ------------------------------------------------------------
        def na_drawn__tool_title
            'Deep Chamfer'
        end
        # ---------------------------------------------------------------

        # FUNCTION | Popup Menu Highlight Key
        # ------------------------------------------------------------
        def na_drawn__mode_key
            :drawn_chamfer
        end
        # ---------------------------------------------------------------

        # FUNCTION | Console Banner Hint Lines
        # ------------------------------------------------------------
        def na_drawn__activation_hints
            [
                'Hover an edge, click to grab it, drag into the corner, click to cut',
                'SHIFT+click banks edges, then one drag cuts them all — BKSP un-banks, ESC clears',
                'Reaches edges inside groups and components without opening them',
                "Setback snaps to the #{Na__InsertPrimatives.Na__DrawnSettings__GridStepLabel} grid — hold CTRL for vertex snapping",
                'VCB: 50 | +5 | -5   (the typed setback pins and cuts)',
                'After cutting, keep typing: 75 resizes the chamfer, +5 / -5 adjust it — the preview replays the change',
                'Double-click an edge to cut it at the last setback placed (remembered in the model)',
                'The edge must border exactly two faces'
            ]
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Cut Hooks — the Seams a Profile Tool Replaces
        # -----------------------------------------------------------------------------
        #
        # Deep Ogee (32__System__DeepOgee) is this tool with a different cut: the
        # same hover, bank, drag, mitre, retype and undo, sweeping a curved
        # profile where this one sweeps a straight chord. Every place the chamfer
        # geometry or the chamfer's name is needed goes through one of these, so
        # a subclass swaps the geometry and the words and inherits the rest.
        # -----------------------------------------------------------------------------

        # FUNCTION | What the Cut Is Called, for Messages and Undo Names
        # ------------------------------------------------------------
        def na_drawn__cut_title
            'Chamfer'
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Cut With Its Article, for Messages
        # ------------------------------------------------------------
        def na_drawn__cut_phrase
            'a chamfer'
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Cut as a Verb, for Messages
        # ------------------------------------------------------------
        def na_drawn__cut_verb
            'chamfer'
        end
        # ---------------------------------------------------------------

        # FUNCTION | Solve One Edge at a World Setback
        # ------------------------------------------------------------
        def na_drawn__solve_cut(target, setback)
            Na__InsertPrimatives.Na__DrawnChamfer__Solve(target, setback)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Read the Drag's Travel Along the Bisector as a Size
        # The chord crosses the bisector at t = d * cos_half, so this puts the
        # cut plane under the cursor. A profile tool whose curve crosses the
        # bisector somewhere else answers so its own curve follows the cursor.
        # ------------------------------------------------------------
        def na_drawn__size_from_travel(travel)
            travel / @na_ch_cos_half
        end
        # ---------------------------------------------------------------

        # FUNCTION | Mitre Every Shared Corner of a Solved Batch
        # ------------------------------------------------------------
        def na_drawn__mitre_cuts(targets, solves)
            Na__InsertPrimatives.Na__DrawnChamfer__MitreBatch(targets, solves)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Plan Every Face a Single Cut Touches
        # ------------------------------------------------------------
        def na_drawn__plan_cut(target, solve)
            Na__InsertPrimatives.Na__DrawnChamfer__BuildPlans(target, solve)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Erase and Rebuild a Single Cut
        # ------------------------------------------------------------
        def na_drawn__build_cut(entities, target, solve, plans, build_transform)
            Na__InsertPrimatives.Na__DrawnChamfer__Build(entities, target, solve, plans, build_transform)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Plan Every Face a Batch Group Touches
        # ------------------------------------------------------------
        def na_drawn__plan_group(targets, solves)
            Na__InsertPrimatives.Na__DrawnChamfer__BuildGroupPlans(targets, solves)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Erase and Rebuild a Whole Batch Group
        # ------------------------------------------------------------
        def na_drawn__build_group(model, targets, solves, plans, build_transform)
            Na__InsertPrimatives.Na__DrawnChamfer__BuildGroup(model, targets, solves, plans, build_transform)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | State Containment (Push/Pull Pattern)
        # -----------------------------------------------------------------------------

        # FUNCTION | This Tool Has Exactly Two States
        # ------------------------------------------------------------
        def na_drawn__ensure_known_state
            return true if @na_state == :idle || @na_state == :picking_depth

            na_drawn__reset_pick_state
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Backspace Releases the Edge, It Does Not Half-Retreat
        # At idle with a SHIFT bank, it un-banks the newest edge instead — the
        # same newest-first peel the dimension locks use.
        # ------------------------------------------------------------
        def na_drawn__step_back(view)
            released = na_drawn__release_last_lock

            unless released
                if @na_state == :idle && @na_ch_multi.any?
                    @na_ch_multi.pop
                    Sketchup::set_status_text("Edge un-banked — #{@na_ch_multi.length} remaining", SB_PROMPT)
                else
                    na_drawn__reset_pick_state
                end
            end

            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
        end
        # ---------------------------------------------------------------

        # FUNCTION | ESC Clears the Bank Before It Leaves the Tool
        # Mid-drag ESC drops the drag but KEEPS the banked edges — abandoning
        # one drag should not cost a carefully built selection. A second ESC at
        # idle empties the bank, and only an ESC with nothing held exits.
        # ------------------------------------------------------------
        def onCancel(reason, view)
            if @na_state == :idle && @na_ch_multi.any? && reason == 0
                @na_ch_multi.clear
                Sketchup::set_status_text('Banked edges cleared', SB_PROMPT)
                na_drawn__update_status_text
                view.invalidate if view
                return
            end

            super
        end
        # ---------------------------------------------------------------

        # FUNCTION | Return to Hovering
        # ------------------------------------------------------------
        def na_drawn__reset_pick_state
            super
            na_drawn__clear_target
            @na_size_d = 0.0
            @na_sign_d = 1.0
        end
        # ---------------------------------------------------------------

        # FUNCTION | Enter Cuts the Chamfer
        # ------------------------------------------------------------
        def onReturn(view)
            return false unless na_drawn__ensure_known_state
            return false unless @na_state == :picking_depth

            na_drawn__commit_chamfer(view)
            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Double Click Cuts the Chamfer, or Repeats the Last Setback
        # The first Down of the double click has already grabbed the edge. No
        # travel since means no drag to cut, so the remembered setback is
        # applied instead — to the grabbed edge and anything banked with it.
        # ------------------------------------------------------------
        def onLButtonDoubleClick(flags, x, y, view)
            na_drawn__sync_modifier(flags)
            return false unless na_drawn__ensure_known_state
            return false unless @na_state == :picking_depth

            travelled_px = (x.to_f - @na_press_x.to_f).abs + (y.to_f - @na_press_y.to_f).abs

            if travelled_px < NA_DRAWN_DRAG_MIN_PX
                na_revise__repeat_or_refuse(view)
            else
                na_drawn__update_cursor(view, x, y)
                na_drawn__commit_chamfer(view)
            end

            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Arrow Keys Have No Meaning on a Chamfer
        # ------------------------------------------------------------
        def na_drawn__apply_axis_lock(axis, view)
            Sketchup::set_status_text("#{na_drawn__cut_phrase.capitalize} follows its own corner — axis locks are not used here", SB_PROMPT)
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | TAB Has Nothing to Cycle Here
        # ------------------------------------------------------------
        def na_drawn__cycle_plane_lock(view)
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | What TAB Does in This Tool
        # ------------------------------------------------------------
        def na_drawn__tab_hint
            ''
        end
        # ---------------------------------------------------------------

        # FUNCTION | CTRL+SHIFT Stays Plain Vertex Snapping Here
        # SHIFT is how edges are banked, so the vertex-then-grid mode the other
        # tools give CTRL+SHIFT is not offered: here it still means plain CTRL.
        # ------------------------------------------------------------
        def na_drawn__vertex_grid_supported?
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Describe the Grabbed Edge Rather Than a Drawing Plane
        # ------------------------------------------------------------
        def na_drawn__plane_description
            return 'No edge grabbed' unless @na_ch_target

            "In #{Na__InsertPrimatives.Na__DeepPick__PathLabel(@na_ch_target)}"
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Cursor Tracking — No Picking Mid-Drag
        # -----------------------------------------------------------------------------

        # FUNCTION | Measure the Drag Across the Corner Plane
        # The cursor ray is intersected with the CORNER PLANE — the plane
        # through the grab point spanned by the edge direction and the bisector
        # — and the hit's component along the bisector becomes the travel.
        # Because the bisector is exactly perpendicular to the edge, motion
        # parallel to the edge contributes nothing, and at the grab instant the
        # hit sits on the edge itself, so the chamfer starts from zero.
        #
        # The first build projected onto the bisector LINE with a closest-
        # points solve instead. That is ill-conditioned whenever the click
        # lands away from the line's anchor — grabbing near the end of a long
        # edge opened with a phantom setback of over a metre, only settling as
        # the cursor wandered toward the midpoint. A ray-plane intersection has
        # no such regime: it is stable anywhere along the edge.
        #
        # The chamfer chord crosses the bisector at t = d * cos_half, so the
        # WYSIWYG mapping — cut plane under the cursor — is d = t / cos_half.
        # The setback is what snaps to the grid. An unsolvable frame (view
        # grazing the corner plane) keeps the last good value; nothing is ever
        # re-picked unless CTRL asks for vertex inference.
        # ------------------------------------------------------------
        def na_drawn__update_cursor(view, x, y)
            @na_last_mouse_x = x
            @na_last_mouse_y = y

            return false unless @na_state == :picking_depth && @na_ch_anchor && @na_ch_bisector

            source =
                if @na_ctrl_held
                    na_drawn__input_point_position(view, x, y)                # <-- Deliberate vertex snapping only
                else
                    na_drawn__corner_plane_point(view, x, y)
                end

            return false unless source

            travel  = (source - @na_ch_anchor).dot(@na_ch_bisector).to_f
            setback = na_drawn__snap_distance(na_drawn__size_from_travel(travel)).to_f
            setback = 0.0 if setback < 0.0                                    # <-- Dragging out of the corner closes the chamfer

            return false if na_drawn__locked?(:d)

            @na_size_d = setback
            @na_sign_d = 1.0
            na_drawn__refresh_solve
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Intersect the Pick Ray with the Corner Plane
        # ------------------------------------------------------------
        def na_drawn__corner_plane_point(view, x, y)
            return nil unless @na_ch_plane_normal

            ray = view.pickray(x, y)
            hit = Geom.intersect_line_plane(ray, [@na_ch_anchor, @na_ch_plane_normal])
            return nil unless hit

            na_drawn__point_in_front_of_ray?(ray, hit) ? hit : nil
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Re-Solve the Chamfer Geometry for the Live Setback
        # ------------------------------------------------------------
        def na_drawn__refresh_solve
            @na_ch_solve        = nil
            @na_ch_batch_solves = []
            @na_ch_mitre_note   = nil
            return unless @na_ch_target && @na_size_d.to_f > 0.0

            if @na_ch_batch.length <= 1
                @na_ch_solve = na_drawn__solve_cut(@na_ch_target, @na_size_d)
                return
            end

            # The whole batch solves ALIGNED with its targets so the mitre pass
            # can pair shared corners up, then the same patched solves feed the
            # preview — the mitred quads on screen are the quads that will land.
            # A refusal here does not kill the drag: the preview falls back to
            # the unmitred shapes and the note explains what commit will say.
            all_solves = @na_ch_batch.map do |member|
                na_drawn__solve_cut(member, @na_size_d)
            end

            @na_ch_solve = all_solves[0]
            return unless @na_ch_solve

            if all_solves.all?
                @na_ch_mitre_note = na_drawn__mitre_cuts(@na_ch_batch, all_solves)
            end

            @na_ch_batch_solves = all_solves[1..-1].compact
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Mouse — Grab an Edge, Then Open the Chamfer
        # -----------------------------------------------------------------------------

        # ON MOUSE MOVE | Hover Highlight While Idle, Setback While Dragging
        # ------------------------------------------------------------
        def onMouseMove(flags, x, y, view)
            na_drawn__sync_modifier(flags)
            na_drawn__ensure_known_state
            @na_last_mouse_x = x
            @na_last_mouse_y = y

            if @na_state == :idle
                @na_ch_target = Na__InsertPrimatives.Na__DeepPick__EdgeAt(view, x, y)
            else
                na_drawn__update_cursor(view, x, y)
            end

            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate
        end
        # ---------------------------------------------------------------

        # ON LEFT BUTTON DOWN | Grab an Edge, or Cut the Chamfer
        # ------------------------------------------------------------
        def onLButtonDown(flags, x, y, view)
            @na_vcb_typing_active = false
            na_drawn__sync_modifier(flags)
            na_drawn__ensure_known_state
            @na_last_mouse_x = x
            @na_last_mouse_y = y

            case @na_state
            when :idle
                if (flags.to_i & NA_CH_MK_SHIFT) != 0
                    na_drawn__toggle_multi_edge(view, x, y)                   # <-- SHIFT banks edges; the plain click drags them all
                else
                    na_drawn__grab_edge(view, x, y)
                end
            when :picking_depth
                @na_drag_press_active = false
                na_drawn__update_cursor(view, x, y)
                na_drawn__commit_chamfer(view)
            end

            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate
        end
        # ---------------------------------------------------------------

        # FUNCTION | Take Hold of the Edge Under the Cursor
        # ------------------------------------------------------------
        def na_drawn__grab_edge(view, x, y)
            target = Na__InsertPrimatives.Na__DeepPick__EdgeAt(view, x, y)

            unless target
                UI.beep
                Sketchup::set_status_text('No edge under the cursor', SB_PROMPT)
                return false
            end

            if target[:locked]
                UI.beep
                Sketchup::set_status_text('That edge is inside a locked group or component', SB_PROMPT)
                return false
            end

            unless target[:face_count] == 2
                UI.beep
                Sketchup::set_status_text("#{na_drawn__cut_phrase.capitalize} needs an edge bordering exactly two faces (this one has #{target[:face_count]})", SB_PROMPT)
                return false
            end

            probe = na_drawn__solve_cut(target, 1.0)
            unless probe
                UI.beep
                Sketchup::set_status_text("These faces are too close to flat for #{na_drawn__cut_phrase}", SB_PROMPT)
                return false
            end

            @na_ch_target = target

            # The interactive frame, all world space. The anchor is the point on
            # the edge actually clicked (not the midpoint), so the crosshair sits
            # under the cursor and the corner plane is anchored where the drag
            # begins — with the bisector perpendicular to the edge, the position
            # along the edge changes nothing about the measurement itself.
            xform     = target[:transformation]
            world_v0  = probe[:world][:v0]
            world_v1  = probe[:world][:v1]
            midpoint  = Geom::Point3d.new(
                (world_v0.x.to_f + world_v1.x.to_f) * 0.5,
                (world_v0.y.to_f + world_v1.y.to_f) * 0.5,
                (world_v0.z.to_f + world_v1.z.to_f) * 0.5
            )

            edge_vector = world_v1 - world_v0
            if edge_vector.length == 0
                UI.beep
                Sketchup::set_status_text('This edge has no length', SB_PROMPT)
                return false
            end
            @na_ch_edge_dir = edge_vector.normalize

            @na_ch_anchor =
                begin
                    grab_ray = view.pickray(x, y)
                    on_edge  = Geom.closest_points([world_v0, @na_ch_edge_dir], grab_ray)
                    on_edge && on_edge[0] ? on_edge[0] : midpoint
                rescue StandardError
                    midpoint
                end

            @na_ch_bisector = probe[:bisector_local].transform(xform).normalize
            @na_ch_cos_half = probe[:cos_half].to_f.abs
            @na_ch_cos_half = 1.0 if @na_ch_cos_half < NA_CHAMFER_MIN_COS_HALF

            # The corner measurement plane: spanned by the edge and the
            # bisector, so a ray-plane hit is stable anywhere along the edge.
            @na_ch_plane_normal = @na_ch_edge_dir.cross(@na_ch_bisector)
            if @na_ch_plane_normal.length == 0                                # <-- Cannot happen for a valid corner, but never divide by it
                UI.beep
                Sketchup::set_status_text('This corner cannot be measured', SB_PROMPT)
                return false
            end
            @na_ch_plane_normal.normalize!

            na_drawn__clear_locks
            @na_state             = :picking_depth
            @na_size_d            = 0.0
            @na_sign_d            = 1.0
            @na_ch_solve          = nil
            @na_drag_press_active = true                                      # <-- Arms press-drag-release
            @na_press_x           = @na_last_mouse_x
            @na_press_y           = @na_last_mouse_y

            # The batch this drag will cut: the clicked edge drives the
            # measurement, every banked edge rides along at the same world
            # setback. Clicking an edge already banked does not double it.
            @na_ch_batch        = [target] + @na_ch_multi.reject do |banked|
                banked[:edge] == target[:edge] && banked[:path] == target[:path]
            end
            @na_ch_batch_solves = []

            if @na_ch_batch.length > 1
                Sketchup::set_status_text("Dragging #{@na_ch_batch.length} edges together", SB_PROMPT)
            elsif target[:shared_count].to_i > 1
                Sketchup::set_status_text(
                    "Heads up: this definition has #{target[:shared_count]} instances — #{na_drawn__cut_verb}ing changes all of them",
                    SB_PROMPT
                )
            end

            # Taking hold of an edge is the "something else" that closes the
            # measurements box on the previous cut. SHIFT-banking is not — a
            # bank is a selection, not a cut, and the retype stays open through it.
            na_revise__forget
            true
        end
        # ---------------------------------------------------------------

        # ON LEFT BUTTON UP | Press-Drag-Release Cuts Too
        # ------------------------------------------------------------
        def onLButtonUp(flags, x, y, view)
            na_drawn__sync_modifier(flags)
            return unless @na_state == :picking_depth
            return unless @na_drag_press_active

            @na_drag_press_active = false
            travelled_px = (x.to_f - @na_press_x.to_f).abs + (y.to_f - @na_press_y.to_f).abs
            return if travelled_px < NA_DRAWN_DRAG_MIN_PX

            na_drawn__update_cursor(view, x, y)
            na_drawn__commit_chamfer(view)
            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Drag Completion
        # -----------------------------------------------------------------------------

        # FUNCTION | Never Reached — This Tool Has No Rectangle Stage
        # ------------------------------------------------------------
        def na_drawn__advance_from_b(view)
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Setback Settled — Cut the Chamfer
        # ------------------------------------------------------------
        def na_drawn__advance_from_depth(view)
            na_drawn__commit_chamfer(view)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Preview
        # -----------------------------------------------------------------------------

        # FUNCTION | Points the Preview Occupies, for the Draw Extents
        # ------------------------------------------------------------
        def na_drawn__preview_points
            points = []

            if @na_ch_target && @na_ch_target[:edge] && @na_ch_target[:edge].valid?
                xform = @na_ch_target[:transformation]
                points << @na_ch_target[:edge].start.position.transform(xform)
                points << @na_ch_target[:edge].end.position.transform(xform)
            end

            if @na_ch_solve
                world = @na_ch_solve[:world]
                points.concat([world[:a0], world[:a1], world[:b0], world[:b1]])
            end

            @na_ch_batch_solves.each do |rider|
                world = rider[:world]
                points.concat([world[:a0], world[:a1], world[:b0], world[:b1]])
            end

            @na_ch_multi.each do |banked|
                next unless banked[:edge] && banked[:edge].valid?

                xform = banked[:transformation]
                points << banked[:edge].start.position.transform(xform)
                points << banked[:edge].end.position.transform(xform)
            end

            points
        end
        # ---------------------------------------------------------------

        # DRAW | Edge Highlight While Idle, Chamfer Preview While Dragging
        # ------------------------------------------------------------
        def draw(view)
            @na_ip.draw(view) if @na_ctrl_held && @na_ip && @na_ip.valid?

            na_drawn__draw_banked_edges(view)

            if @na_state == :idle
                na_drawn__draw_edge_highlight(view)
                na_revise__draw_animation(view)                               # <-- The ghost of a retyped cut sweeping to its new setback
                return
            end

            na_drawn__draw_preview(view)
            Na__InsertPrimatives.Na__DrawnPreview__DrawCrosshair(view, @na_ch_anchor, nil, NA_DRAWN_ANCHOR_COLOR)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw Every SHIFT-Banked Edge in the Selection Colour
        # Kept visible during the drag too, so the set being cut never has to be
        # held in the user's head. A banked edge that has died (undone away)
        # silently drops from the bank rather than drawing garbage.
        # ------------------------------------------------------------
        def na_drawn__draw_banked_edges(view)
            return if @na_ch_multi.empty?

            @na_ch_multi.delete_if { |banked| banked[:edge].nil? || !banked[:edge].valid? }

            view.line_stipple  = ''
            view.line_width    = NA_CH_EDGE_WIDTH
            view.drawing_color = NA_CH_SELECT_COLOR

            @na_ch_multi.each do |banked|
                xform = banked[:transformation]
                ends  = Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace([
                    banked[:edge].start.position.transform(xform),
                    banked[:edge].end.position.transform(xform)
                ])
                view.draw_line(ends[0], ends[1])
            end

            view.line_width = 2
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw a Setback Dimension Nudged Clear of the Geometry
        # Anchored at the guide-line midpoint, then pushed further along the
        # screen direction AWAY from the cut plane's centre, so the number sits
        # beside the shape instead of on top of the corner — whatever the view.
        # ------------------------------------------------------------
        def na_drawn__draw_setback_label(view, from_point, to_point, quad_centre, locked)
            midpoint = Geom::Point3d.new(
                (from_point.x.to_f + to_point.x.to_f) * 0.5,
                (from_point.y.to_f + to_point.y.to_f) * 0.5,
                (from_point.z.to_f + to_point.z.to_f) * 0.5
            )

            screen_mid    = view.screen_coords(
                Na__InsertPrimatives.Na__DrawnPreview__ToDrawPoint(midpoint)
            )
            screen_centre = view.screen_coords(
                Na__InsertPrimatives.Na__DrawnPreview__ToDrawPoint(quad_centre)
            )
            push_x        = screen_mid.x.to_f - screen_centre.x.to_f
            push_y        = screen_mid.y.to_f - screen_centre.y.to_f
            push_length   = Math.sqrt((push_x * push_x) + (push_y * push_y))

            if push_length < 1.0                                              # <-- Edge-on view: fall back to a plain sideways nudge
                push_x = 1.0
                push_y = 0.0
                push_length = 1.0
            end

            offset_px = 34.0
            Na__InsertPrimatives.Na__DrawnPreview__DrawScreenText(
                view,
                screen_mid.x.to_f + (push_x / push_length * offset_px),
                screen_mid.y.to_f + (push_y / push_length * offset_px) - 6.0,
                Na__InsertPrimatives.Na__DrawnPreview__DimensionText(@na_size_d, locked),
                Na__InsertPrimatives.Na__DrawnPreview__DimensionColor(locked)
            )
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Highlight the Edge Under the Cursor
        # ------------------------------------------------------------
        def na_drawn__draw_edge_highlight(view)
            target = @na_ch_target
            return unless target && target[:edge] && target[:edge].valid?

            xform    = target[:transformation]
            world_v0 = target[:edge].start.position.transform(xform)
            world_v1 = target[:edge].end.position.transform(xform)

            hover_ends = Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace([world_v0, world_v1])

            view.line_stipple  = ''
            view.line_width    = NA_CH_EDGE_WIDTH
            view.drawing_color = NA_CH_HOVER_COLOR
            view.draw_line(hover_ends[0], hover_ends[1])
            view.line_width    = 2

            length_mm = Na__InsertPrimatives.Na__DrawnFormat__Mm(world_v0.distance(world_v1)).abs
            usable    = target[:face_count] == 2
            second    = usable ? Na__InsertPrimatives.Na__DeepPick__PathLabel(target) : "#{target[:face_count]} faces — cannot #{na_drawn__cut_verb}"

            Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(
                view, world_v1, ["#{length_mm} mm edge", second]
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw One Cut's Wedge and Chamfer Plane
        # The wedge being cut away, shaded in the plane blue — the two face
        # slivers plus the end triangles — so what disappears reads separately
        # from the amber cut plane that replaces it. Shared by the driver and
        # every SHIFT-banked rider; only the driver carries dimensions.
        # ------------------------------------------------------------
        def na_drawn__draw_cut_faces(view, solve)
            world = solve[:world]

            Na__InsertPrimatives.Na__DrawnPreview__DrawFilledQuad(
                view, [world[:v0], world[:v1], world[:a1], world[:a0]],
                NA_DRAWN_PLANE_FILL_COLOR, NA_DRAWN_PLANE_BORDER_COLOR
            )
            Na__InsertPrimatives.Na__DrawnPreview__DrawFilledQuad(
                view, [world[:v0], world[:v1], world[:b1], world[:b0]],
                NA_DRAWN_PLANE_FILL_COLOR, NA_DRAWN_PLANE_BORDER_COLOR
            )
            # A mitred end has no cap — the two chamfer planes meet along the
            # mitre line instead, so its triangle would just stab through the
            # partner's preview (exactly the artefact reported).
            unless solve[:mitre0]
                Na__InsertPrimatives.Na__DrawnPreview__DrawFilledPolygon(
                    view, [world[:v0], world[:a0], world[:b0]],
                    NA_DRAWN_PLANE_FILL_COLOR, NA_DRAWN_PLANE_BORDER_COLOR
                )
            end
            unless solve[:mitre1]
                Na__InsertPrimatives.Na__DrawnPreview__DrawFilledPolygon(
                    view, [world[:v1], world[:a1], world[:b1]],
                    NA_DRAWN_PLANE_FILL_COLOR, NA_DRAWN_PLANE_BORDER_COLOR
                )
            end

            Na__InsertPrimatives.Na__DrawnPreview__DrawFilledPolygon(
                view, Na__InsertPrimatives.Na__DrawnChamfer__FaceLoopWorld(solve),
                NA_DRAWN_VOLUME_FILL_COLOR, NA_DRAWN_VOLUME_BORDER_COLOR
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw the Chamfer Cut Plane and Its Dimensions
        # The same solve feeds this preview and the commit, so the cut that
        # lands is exactly the one shown.
        # ------------------------------------------------------------
        def na_drawn__draw_preview(view)
            solve = @na_ch_solve

            unless solve
                na_drawn__draw_edge_highlight(view)
                return
            end

            world  = solve[:world]
            locked = na_drawn__locked?(:d)

            na_drawn__draw_cut_faces(view, solve)
            @na_ch_batch_solves.each { |rider| na_drawn__draw_cut_faces(view, rider) }

            Na__InsertPrimatives.Na__DrawnPreview__DrawGuideLine(view, world[:v0], world[:a0])
            Na__InsertPrimatives.Na__DrawnPreview__DrawGuideLine(view, world[:v0], world[:b0])

            quad_centre = Geom::Point3d.new(
                (world[:a0].x.to_f + world[:a1].x.to_f + world[:b0].x.to_f + world[:b1].x.to_f) * 0.25,
                (world[:a0].y.to_f + world[:a1].y.to_f + world[:b0].y.to_f + world[:b1].y.to_f) * 0.25,
                (world[:a0].z.to_f + world[:a1].z.to_f + world[:b0].z.to_f + world[:b1].z.to_f) * 0.25
            )
            na_drawn__draw_setback_label(view, world[:v0], world[:a0], quad_centre, locked)
            na_drawn__draw_setback_label(view, world[:v0], world[:b0], quad_centre, locked)

            width_mm = Na__InsertPrimatives.Na__DrawnFormat__Mm(solve[:width_world]).abs
            angle    = Na__InsertPrimatives.Na__DrawnFormat__Degrees(solve[:face_angle_deg])
            edge_mm  = Na__InsertPrimatives.Na__DrawnFormat__Mm(solve[:edge_len_world]).abs

            summary_lines = [
                "Chamfer #{Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_size_d).abs} mm · face #{width_mm} wide",
                "#{angle} deg to each face · edge #{edge_mm} mm"
            ]
            if @na_ch_batch.length > 1
                summary_lines << "cutting #{@na_ch_batch_solves.length + 1} of #{@na_ch_batch.length} edges together"
            end

            Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(view, world[:a1], summary_lines)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Status and Measurements Box
        # -----------------------------------------------------------------------------

        # FUNCTION | Middle Section of the Status Bar Line
        # ------------------------------------------------------------
        def na_drawn__status_detail
            if @na_state == :picking_depth
                setback = Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_size_d).abs
                text    = na_drawn__locked?(:d) ? "[#{setback}]" : setback.to_s
                return "Chamfer #{text} mm — CORNER PROBLEM: #{@na_ch_mitre_note}" if @na_ch_mitre_note
                return "Chamfer #{text} mm — release or click to cut"
            end

            adjust = na_revise__status_hint

            if @na_ch_target
                return 'Edge borders more than two faces — pick another' unless @na_ch_target[:face_count] == 2
                return "Click to grab this edge#{na_drawn__focus_hint}#{adjust}"
            end

            if @na_ch_multi.any?
                return "#{@na_ch_multi.length} edge#{@na_ch_multi.length == 1 ? '' : 's'} banked — SHIFT+click adds, click one to drag them all#{adjust}"
            end

            "Hover an edge to chamfer, at any nesting depth#{na_drawn__focus_hint}#{adjust}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Measurements Box Label and Live Value
        # At idle the box keeps the placed setback while it can still be
        # retyped, or the remembered one a double-click will repeat.
        # ------------------------------------------------------------
        def na_drawn__vcb_label_and_value
            return ['Chamfer setback', na_revise__vcb_value] if @na_state != :picking_depth

            ['Chamfer setback', na_drawn__format_sizes([@na_size_d])]
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Measurements Box Entry
        # -----------------------------------------------------------------------------

        # FUNCTION | A Typed Setback Pins and Cuts, or Corrects the Cut Just Made
        # ------------------------------------------------------------
        def na_drawn__handle_vcb_text(text, view)
            return na_revise__retype(text, view) if na_revise__available?

            unless @na_state == :picking_depth
                UI.beep
                Sketchup::set_status_text("Grab an edge before typing a setback#{na_revise__status_hint}", SB_PROMPT)
                return false
            end

            tokens = Na__InsertPrimatives.Na__DrawnVcb__ParseEntry(text)
            raise ArgumentError, "#{na_drawn__cut_title.downcase} takes a single setback" if tokens.length > 1

            setbacks = Na__InsertPrimatives.Na__DrawnVcb__ResolveAgainst(tokens, [@na_size_d])
            Na__InsertPrimatives.Na__DrawnVcb__ValidatePositive(setbacks, ['Setback'])

            @na_size_d = setbacks[0]
            na_drawn__lock_slot(:d)
            na_drawn__refresh_solve
            na_drawn__commit_chamfer(view)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Geometry Commit
        # -----------------------------------------------------------------------------

        # FUNCTION | Cut the Chamfer
        # ------------------------------------------------------------
        def na_drawn__commit_chamfer(view)
            target = @na_ch_target

            unless target && target[:edge] && target[:edge].valid?
                UI.beep
                Sketchup::set_status_text('That edge is no longer available', SB_PROMPT)
                na_drawn__reset_pick_state
                return false
            end

            unless Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(@na_size_d)
                UI.beep
                Sketchup::set_status_text('No setback — drag into the corner or type one', SB_PROMPT)
                return false
            end

            return na_drawn__commit_batch(view, @na_ch_batch) if @na_ch_batch.length > 1

            solve = na_drawn__solve_cut(target, @na_size_d)
            unless solve
                UI.beep
                Sketchup::set_status_text("This #{na_drawn__cut_title.downcase} cannot be solved here", SB_PROMPT)
                return false
            end

            # Plans are made BEFORE the context is entered: reads stay in
            # unambiguous definition-local space, and a refusal here costs
            # nothing — no context change, no operation, no erase.
            begin
                plans = na_drawn__plan_cut(target, solve)
            rescue StandardError => error
                UI.beep
                Sketchup::set_status_text("#{na_drawn__cut_title} refused: #{error.message}", SB_PROMPT)
                Na__InsertPrimatives.Na__Debug__Puts "NA #{na_drawn__cut_title.upcase} refused: #{error.message}"
                return false
            end

            model   = Sketchup.active_model
            members = na_revise__snapshot_members([target], model)           # <-- Read while the edge still exists; the cut erases it

            result = Na__InsertPrimatives.Na__DeepPick__ExecuteInContext(model, target[:path], "#{na_drawn__cut_title} Edge") do |entered|
                parent   = target[:edge].parent
                entities = parent.respond_to?(:entities) ? parent.entities : model.active_entities

                # The plans were read BEFORE this block. If the group was just
                # opened they are local and the collection now takes global, so
                # they go through edit_transform — read here, where it is the
                # newly opened session's. Nothing entered, and reads and adds
                # share one space: the identity. See the header rule.
                na_drawn__build_cut(
                    entities, target, solve, plans, na_drawn__build_transform(model, entered)
                )

                # The setback a double-click on the next edge will repeat,
                # written inside the operation so it rides in this undo step.
                na_revise__remember(model, @na_size_d)
            end

            unless result[:success]
                UI.beep
                Sketchup::set_status_text("#{na_drawn__cut_title} failed: #{result[:error]}", SB_PROMPT)
                na_revise__load_memory                                        # <-- The aborted operation rolled its memory write back too
                na_drawn__reset_pick_state
                view.invalidate if view
                return false
            end

            na_drawn__log_chamfer(target, solve)
            na_revise__capture(members, [solve], 1)                           # <-- Arm the retype while the solve is still in scope
            @na_ch_multi.clear
            na_drawn__reset_pick_state
            view.invalidate if view
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Cut Every Edge in the Batch at the Same World Setback
        # Edges are grouped by their instance path, ONE operation per context —
        # so the common case of several edges on the same group undoes in a
        # single Ctrl+Z. Within a group each edge is re-validated, re-solved and
        # RE-PLANNED inside the entered context: adjacent edges share faces, and
        # the first cut rebuilds the face the second one borders, so plans made
        # up front would hold erased references. Once the context is entered
        # every position the group reports is GLOBAL (the header rule), so the
        # solves run with the identity transform and the build adds with the
        # identity too — nothing here is read before the open and added after
        # it. Any edge failing aborts its whole group — all-or-nothing per
        # context, never a half-cut group.
        # ------------------------------------------------------------
        def na_drawn__commit_batch(view, targets)
            model      = Sketchup.active_model
            groups     = targets.group_by { |t| Na__InsertPrimatives.Na__DeepPick__Instances(t[:path]) }
            cut        = 0
            errors     = []
            members    = na_revise__snapshot_members(targets, model)          # <-- Read while every edge still exists
            cut_edges  = []                                                   # <-- The targets whose group actually cut
            cut_solves = []                                                   # <-- Their final solved shapes, for the ghost
            ops        = 0                                                    # <-- One undo step per group that landed

            groups.each_value do |group_targets|
                group_solves = []                                             # <-- Assigned inside the block, read after it

                result = Na__InsertPrimatives.Na__DeepPick__ExecuteInContext(
                    model, group_targets.first[:path], "#{na_drawn__cut_title} Edges"
                ) do |entered|
                    # Validate and solve the whole group first, then mitre any
                    # shared corners, then plan every touched face exactly once,
                    # then erase-and-rebuild in a single pass. Independent
                    # sequential cuts cannot survive edges meeting at a vertex —
                    # the first cut's stray sweep erases the second edge — so
                    # the group is treated as one construction.
                    #
                    # Entered, the edges now report global coordinates, so the
                    # transform that carried them to global a moment ago is
                    # replaced by the identity for every read below. Not
                    # entered, they report exactly as they did when picked.
                    working      = []
                    group_solves = []
                    xform_now    = entered ? Geom::Transformation.new : nil

                    group_targets.each do |member|
                        edge = member[:edge]
                        raise 'an edge vanished mid-batch' unless edge && edge.valid?

                        faces = edge.faces
                        raise 'an edge no longer borders exactly two faces' unless faces.length == 2

                        fresh = member.merge(
                            :faces          => faces,
                            :face_count     => faces.length,
                            :transformation => (xform_now || member[:transformation])
                        )
                        solve = na_drawn__solve_cut(fresh, @na_size_d)
                        raise 'an edge could not be solved at this setback' unless solve

                        working      << fresh
                        group_solves << solve
                    end

                    mitre_error = na_drawn__mitre_cuts(working, group_solves)
                    raise mitre_error if mitre_error

                    # Planned and added in the SAME space, so the identity —
                    # never edit_transform, which would carry global points
                    # through the open group's transform a second time.
                    plans = na_drawn__plan_group(working, group_solves)
                    na_drawn__build_group(
                        model, working, group_solves, plans, Geom::Transformation.new
                    )

                    # The setback a double-click on the next edge will repeat,
                    # written inside the operation so it rides in this undo step.
                    na_revise__remember(model, @na_size_d)
                end

                if result[:success]
                    cut += group_targets.length
                    ops += 1
                    cut_edges.concat(group_targets)
                    cut_solves.concat(group_solves)
                else
                    errors << result[:error]
                end
            end

            if cut.zero?
                UI.beep
                Sketchup::set_status_text("#{na_drawn__cut_title} failed: #{errors.first}", SB_PROMPT)
                Na__InsertPrimatives.Na__Debug__Puts "NA #{na_drawn__cut_title.upcase} batch failed: #{errors.join(' | ')}"
                na_revise__load_memory                                        # <-- Every operation aborted, so the memory write did too
                na_drawn__reset_pick_state
                view.invalidate if view
                return false
            end

            Na__InsertPrimatives.Na__Debug__Puts "\n"
            Na__InsertPrimatives.Na__Debug__Puts '----------------------------------------'
            Na__InsertPrimatives.Na__Debug__Puts "DEEP #{na_drawn__cut_title.upcase} BATCH CUT"
            Na__InsertPrimatives.Na__Debug__Puts "Edges  : #{cut} of #{targets.length} cut at #{Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_size_d).abs}mm"
            Na__InsertPrimatives.Na__Debug__Puts "Groups : #{groups.length} context#{groups.length == 1 ? '' : 's'} (one undo step each)"
            errors.each { |message| Na__InsertPrimatives.Na__Debug__Puts "Refused: #{message}" }
            Na__InsertPrimatives.Na__Debug__Puts '----------------------------------------'

            if errors.any?
                Sketchup::set_status_text("#{cut} edges cut — #{errors.length} group(s) refused, see console", SB_PROMPT)
            end

            # Only the edges that were actually cut are worth retyping: the ones
            # whose group refused are still standing exactly as they were.
            cut_members = members.select { |member| cut_edges.include?(member[:target]) }
            na_revise__capture(cut_members, cut_solves, ops)

            @na_ch_multi.clear
            na_drawn__reset_pick_state
            view.invalidate if view
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Transform That Carries Pre-Entry Plan Points Into the Session
        # Read INSIDE the ExecuteInContext block, where edit_transform is the
        # newly opened session's. Identity when nothing was entered: the plan
        # was read and is added in one and the same space.
        # ------------------------------------------------------------
        def na_drawn__build_transform(model, entered)
            entered ? model.edit_transform : Geom::Transformation.new
        rescue StandardError
            Geom::Transformation.new
        end
        # ---------------------------------------------------------------

        # FUNCTION | Console Report for a Completed Chamfer
        # ------------------------------------------------------------
        def na_drawn__log_chamfer(target, solve)
            Na__InsertPrimatives.Na__Debug__Puts "\n"
            Na__InsertPrimatives.Na__Debug__Puts '----------------------------------------'
            Na__InsertPrimatives.Na__Debug__Puts 'DEEP CHAMFER CUT'
            Na__InsertPrimatives.Na__Debug__Puts "Target : #{Na__InsertPrimatives.Na__DeepPick__PathLabel(target)}"
            Na__InsertPrimatives.Na__Debug__Puts "Setback: #{Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_size_d).abs}mm each face"
            Na__InsertPrimatives.Na__Debug__Puts "Face   : #{Na__InsertPrimatives.Na__DrawnFormat__Mm(solve[:width_world]).abs}mm wide at #{Na__InsertPrimatives.Na__DrawnFormat__Degrees(solve[:face_angle_deg])} deg"
            Na__InsertPrimatives.Na__Debug__Puts "Edge   : #{Na__InsertPrimatives.Na__DrawnFormat__Mm(solve[:edge_len_world]).abs}mm long"
            Na__InsertPrimatives.Na__Debug__Puts "Instances affected: #{target[:shared_count]}"
            Na__InsertPrimatives.Na__Debug__Puts "Grid   : #{Na__InsertPrimatives.Na__DrawnSettings__GridStepLabel}"
            Na__InsertPrimatives.Na__Debug__Puts '----------------------------------------'
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnChamferTool class

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Public Entry Point
    # -----------------------------------------------------------------------------

    # FUNCTION | Activate the Deep Chamfer Tool (Hotkey Entry Point)
    # ------------------------------------------------------------
    # Bind in Preferences -> Shortcuts against the Extensions menu item, or call
    # directly: Na__InsertPrimatives.Na__InsertPrimatives__DeepChamfer
    # ------------------------------------------------------------
    def self.Na__InsertPrimatives__DeepChamfer
        Na__InsertPrimatives.Na__ModeSwitch__ActivateDrawnChamferTool
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP CHAMFER TOOL MODULE
# =============================================================================
