# =============================================================================
# NA INSERT PRIMATIVES - DEEP SCALE TOOL
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnScaleTool__.rb
# NAMESPACE  : Na__InsertPrimatives
# CLASS      : DrawnScaleTool
# AUTHOR     : Noble Architecture
# PURPOSE    : Scale any group or component by its grips, type its size into
#              its dimensions, or stretch it between cut planes
# CREATED    : 2026
#
# DESCRIPTION:
# - Select a group or component and start the tool, or start it and click
#   one. Its own box is drawn in blue with SketchUp's 26 grips; drag one to
#   scale, release (or click again) to place. One undo step.
# - Double-click inside the object to take the part under the cursor
#   instead — a sash in a window, a panel in a door — without opening
#   anything. BKSP comes back out a level. That is the "Deep" in the name:
#   the same reach every other tool in this plugin has.
# - Loose geometry too (5.2.9): select edges and faces, or several objects,
#   and start the tool, or click loose geometry to take it and everything
#   connected to it. It is boxed in the axes the user is drawing in — the
#   open group's own, however deep — and scaled where it lies. Nothing is
#   saved for it, so it has no stretch planes.
#
# CONTROL HANDLES:
# - The bar at the top left chooses which grips are shown: All, Faces,
#   Corners, or one axis. One click, remembered between sessions, and the
#   same setting as the right-click menu's Handles. The ARROW keys pick one
#   axis for a moment (Right X, Left Y, Up Z, Down lets go), as they lock an
#   axis in every tool here.
#
# SHOW DIMENSIONS:
# - The size is drawn on three edges. Click a dimension and type: 1200 sets
#   it, +50 / -25 change it, 1.5x scales it. It resizes at once. With no
#   dimension clicked the measurements box takes X,Y,Z in order.
#
# STRETCH PLANES:
# - Switched on (Planes on the bar, SHIFT+TAB, or the right-click menu), each
#   axis gets a dashed centre line. Click one to drop a cut plane and drag it
#   into place: it snaps to points, and to edges and faces square across the
#   axis. Every click adds another; SHIFT drops a mirrored pair. Or hold CTRL
#   anywhere over the object — Planes on or off — and click where the plane
#   should go. The planes are saved with the object. A line of help under
#   the bar says what to do next (Planes file).
# - A grip on an axis with planes then STRETCHES the object at the planes
#   instead of scaling everything in it, so frames, holes and details keep
#   their size. Live preview while dragging, one undo step. See the Field
#   file for exactly how, and the Commit file for how it reaches the model.
#
# KEYS:
#   drag a grip   SHIFT uniform / free, CTRL snap to a point, TAB about centre
#   switches      TAB About Centre, SHIFT+TAB Stretch Planes, ARROWS one
#                 axis's grips for a moment; every switch is also a Shortcuts
#                 command (Keys file). No single letters: SketchUp's own
#                 shortcuts take those before a tool sees them (5.2.6).
#   CTRL (held)   a stretch plane offered under the cursor; click to add it
#   typed         1200 | +50 | -25 | 1.5x | X,Y,Z — mm unless it says cm or m
#   ESC           cancels a drag, then lets go of a typed dimension, then of
#                 the object, then leaves the tool
#
# THE PREVIEW (the established system, DrawnPreviewGraphics):
# - Nothing in the model changes until the release. The new box is drawn
#   in the preview amber over the faded blue of the old one, every edge of
#   the object follows the drag as an amber ghost, the planes ride along to
#   where the stretch takes them, and the dimensions read the live size.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../06__Tools__DrawnShared/Na__InsertPrimatives__DrawnToolShared__'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnDeepPick__'
require_relative 'Na__InsertPrimatives__DrawnScale__Frame__'
require_relative 'Na__InsertPrimatives__DrawnScale__Field__'
require_relative 'Na__InsertPrimatives__DrawnScale__Commit__'
require_relative 'Na__InsertPrimatives__DrawnScale__Preview__'
require_relative 'Na__InsertPrimatives__DrawnScale__Planes__'
require_relative 'Na__InsertPrimatives__DrawnScale__Overlay__'
require_relative 'Na__InsertPrimatives__DrawnScale__Keys__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Option Ids (declared in the ToolOptions table)
    # -----------------------------------------------------------------------------

    NA_SCALE_OPTION_HANDLES = 'scale_handles'.freeze
    NA_SCALE_OPTION_PLANES  = 'scale_planes'.freeze
    NA_SCALE_OPTION_CENTRE  = 'scale_about_centre'.freeze
    NA_SCALE_OPTION_DIMS    = 'scale_dimensions'.freeze
    NA_SCALE_OPTION_SIZE    = 'scale_dim_size'.freeze
    NA_SCALE_OPTION_OFFSET  = 'scale_dim_offset'.freeze
    NA_SCALE_OPTION_CLEAR   = 'scale_clear_planes'.freeze

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Deep Scale Tool Class
    # -----------------------------------------------------------------------------

    # CLASS | Scale, Type and Stretch Any Group or Component
    # ------------------------------------------------------------
    class DrawnScaleTool

        include Na__InsertPrimatives::DrawnToolShared
        include Na__InsertPrimatives::DrawnScalePlanes
        include Na__InsertPrimatives::DrawnScaleOverlay
        include Na__InsertPrimatives::DrawnScaleKeys                          # <-- After DrawnToolShared, so its key handlers sit in front of the shared ones

        NA_SCALE_GRIP_HIT_PX   = 9.0
        NA_SCALE_MESSAGE_SECS  = 5.0                                          # <-- A result stays in the status line this long

        # INITIALIZE | Tool Constructor
        # ------------------------------------------------------------
        def initialize
            na_drawn__init_shared_state
            na_scale__init_state
        end
        # ---------------------------------------------------------------

        # FUNCTION | Every Instance Variable Deep Scale Adds to the Shared Set
        # ------------------------------------------------------------
        def na_scale__init_state
            @na_sc_target       = nil                                         # <-- { :instance, :path } — what is being scaled
            @na_sc_frame        = nil                                         # <-- Its box: see the Frame file
            @na_sc_grips        = []
            @na_sc_planes       = nil                                         # <-- Its saved stretch planes, local inches per axis
            @na_sc_ghost        = nil                                         # <-- Its edges, read when a drag starts
            @na_sc_ghost_key    = nil
            @na_sc_hover        = nil                                         # <-- What the cursor is over: :bar :dim :grip :handle :line :object
            @na_sc_hover_object = nil                                         # <-- Another object under the cursor, offered for a click
            @na_sc_plane_hover  = nil                                         # <-- The plane a click on a centre line would drop
            @na_sc_drag         = nil                                         # <-- A grip being dragged
            @na_sc_plane_drag   = nil                                         # <-- A plane being placed or moved
            @na_sc_active_dim   = nil                                         # <-- The axis the next typed size goes to
            @na_sc_active_plane = nil                                         # <-- The plane the next typed distance moves
            @na_sc_focus        = nil                                         # <-- :dimension or :plane — which of the two typing goes to
            @na_sc_sides        = {}                                          # <-- Per axis, the end the last drag held still
            @na_sc_bar          = []
            @na_sc_dims         = []
            @na_sc_message      = nil
            @na_sc_last_placed  = nil                                         # <-- The plane the last press dropped, for the double-click guard
            @na_sc_seen_axes    = nil                                         # <-- Which axes the view shows, from the last grip layout
            @na_sc_typed        = nil                                         # <-- The measurements box as it is being typed (Keys file)
        end
        # ---------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Identity
        # -----------------------------------------------------------------------------

        # FUNCTION | Status Bar Title
        # ------------------------------------------------------------
        def na_drawn__tool_title
            'Deep Scale'
        end
        # ---------------------------------------------------------------

        # FUNCTION | Popup Menu Highlight Key, and the Key Its Options Are Declared Under
        # ------------------------------------------------------------
        def na_drawn__mode_key
            :drawn_scale
        end
        # ---------------------------------------------------------------

        # FUNCTION | Console Banner Hint Lines
        # ------------------------------------------------------------
        def na_drawn__activation_hints
            [
                'Select a group or component first, or hover one and click it',
                'Loose geometry works too: select it first, or click it to take everything connected to it — boxed in the open group\'s own axes, no stretch planes',
                'Double-click inside it to take the part under the cursor; BKSP comes back out',
                'Drag a grip to scale, release or click again to place — one undo step',
                "Sizes snap to the #{Na__InsertPrimatives.Na__DrawnSettings__GridStepLabel} grid; hold CTRL to snap the grip to a point instead",
                'SHIFT frees a corner grip, or makes a face or edge grip uniform; TAB scales about the centre',
                'Handle bar (top left): All, Faces, Corners, X, Y, Z — remembered; ARROWS pick one axis for a moment',
                'TAB About Centre, SHIFT+TAB Stretch Planes — no single letters: SketchUp keeps those for its own tools',
                'Every switch is also a command for Preferences > Shortcuts: Extensions > Na__InsertPrimitives > Deep Scale Options',
                'Click a dimension and type its size: 1200, +50, -25, 1.5x — it resizes at once',
                'With nothing clicked the measurements box takes X,Y,Z in order: 1200,,2400 leaves Y alone',
                'Planes: click a dashed centre line, or hold CTRL over the object, to add a stretch plane — every click adds another',
                'SHIFT drops a mirrored pair; drag a diamond to move a plane; DEL or a double-click removes it',
                'A grip on an axis with planes stretches the object AT the planes: frames and details keep their size',
                'Right-click for dimension size and offset, and Clear Stretch Planes'
            ]
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Settings (the ToolOptions Table)
        # -----------------------------------------------------------------------------

        # FUNCTION | The Handle Set in Force — an Arrow Lock Outranks the Stored One
        # ------------------------------------------------------------
        def na_scale__handle_set
            return @na_axis_lock.to_s if @na_axis_lock

            Na__InsertPrimatives.Na__ToolOptions__Value(NA_SCALE_OPTION_HANDLES).to_s
        end
        # ---------------------------------------------------------------

        # FUNCTION | Stretch Planes Switched On — and Something to Keep Them On?
        # Loose geometry has no definition to save planes with, so for it they
        # are off whatever the switch says (5.2.9).
        # ------------------------------------------------------------
        def na_scale__planes_on?
            return false if @na_sc_frame && @na_sc_frame[:loose]

            Na__InsertPrimatives.Na__ToolOptions__Enabled?(NA_SCALE_OPTION_PLANES)
        end
        # ---------------------------------------------------------------

        # FUNCTION | About Centre Switched On?
        # ------------------------------------------------------------
        def na_scale__centre_on?
            Na__InsertPrimatives.Na__ToolOptions__Enabled?(NA_SCALE_OPTION_CENTRE)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Show Dimensions Switched On?
        # ------------------------------------------------------------
        def na_scale__dims_on?
            Na__InsertPrimatives.Na__ToolOptions__Enabled?(NA_SCALE_OPTION_DIMS)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Dimension Text Size
        # ------------------------------------------------------------
        def na_scale__dim_size
            size = Na__InsertPrimatives.Na__ToolOptions__Value(NA_SCALE_OPTION_SIZE).to_i
            size > 0 ? size : 13
        end
        # ---------------------------------------------------------------

        # FUNCTION | How Far the Dimensions Stand Off the Object, in Pixels
        # ------------------------------------------------------------
        def na_scale__dim_offset
            offset = Na__InsertPrimatives.Na__ToolOptions__Value(NA_SCALE_OPTION_OFFSET).to_f
            offset > 0.0 ? offset : 24.0
        end
        # ---------------------------------------------------------------

        # FUNCTION | An Option Changed From the Popup, the Bar or a Key
        # A drag in hand follows the change at once, as Drawn Volume's
        # Subtraction does (5.1.23): a switch that waits for the next drag
        # reads as a switch that did nothing.
        # ------------------------------------------------------------
        def na_scale__after_option_changed(_option_id = nil)
            model = Sketchup.active_model
            view  = model ? model.active_view : nil

            @na_sc_plane_hover = nil unless na_scale__planes_on?
            na_drawn__update_cursor(view, @na_last_mouse_x, @na_last_mouse_y) if view && (@na_sc_drag || @na_sc_frame)

            @na_last_status_text = nil
            @na_last_vcb_text    = nil
            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Popup's Option Buttons — Clear Stretch Planes Is Done Here
        # ------------------------------------------------------------
        def Na__DrawnMode__ToggleToolOption(option_id)
            id = option_id.to_s

            if id == NA_SCALE_OPTION_CLEAR
                count = na_scale__clear_planes
                na_scale__say(
                    if count.nil?      then 'Take an object first — there are no planes to clear'
                    elsif count.zero?  then "#{@na_sc_frame[:name]} has no stretch planes"
                    else                    "#{count} stretch plane#{count == 1 ? '' : 's'} cleared from #{@na_sc_frame[:name]}"
                    end
                )
                na_scale__after_option_changed(id)
                return { :caption => Na__InsertPrimatives.Na__ToolOptions__CaptionFor(id), :enabled => false }
            end

            result = super
            @na_axis_lock = nil if id == NA_SCALE_OPTION_HANDLES                 # <-- A handle set chosen in the menu is the newer decision
            na_scale__after_option_changed(id)
            result
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | SketchUp Tool API — Life Cycle
        # -----------------------------------------------------------------------------

        # ACTIVATE | Take the Selected Object, If There Is Exactly One
        # ------------------------------------------------------------
        def activate
            @na_ctrl_held  = false
            @na_shift_held = false
            @na_axis_lock  = nil
            Na__InsertPrimatives.Na__Scale__SetActiveTool(self)               # <-- The Shortcuts commands act on this one
            na_drawn__reset_pick_state
            na_drawn__print_activation_banner
            na_scale__take_selection

            @na_last_status_text = nil
            na_drawn__update_status_text
            na_drawn__refresh_vcb

            model = Sketchup.active_model
            model.active_view.invalidate if model
        end
        # ---------------------------------------------------------------

        # DEACTIVATE | Leaving the Tool
        # ------------------------------------------------------------
        def deactivate(view)
            Na__InsertPrimatives.Na__Scale__SetActiveTool(nil) if Na__InsertPrimatives.Na__Scale__ActiveTool.equal?(self)
            super
        end
        # ---------------------------------------------------------------

        # RESUME | Back From Orbit or Another Interruption
        # ------------------------------------------------------------
        def resume(view)
            super
            na_scale__refresh_frame
            na_drawn__update_status_text
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | The Object Being Scaled
        # -----------------------------------------------------------------------------

        # FUNCTION | Take an Object to Scale
        # ------------------------------------------------------------
        # select puts it in SketchUp's selection too, which is what clicking
        # an object with the native Scale tool does. Only possible for an
        # object in the open context: a part reached by double-clicking down
        # cannot be selected without opening its parent.
        # ------------------------------------------------------------
        def na_scale__take(instance, path, select = true)
            if instance.respond_to?(:locked?) && instance.locked?
                UI.beep
                na_scale__say("#{Na__InsertPrimatives.Na__DeepPick__InstanceName(instance)} is locked")
                return false
            end

            frame = Na__InsertPrimatives.Na__ScaleFrame__Build(instance, path)

            unless frame
                UI.beep
                na_scale__say("#{Na__InsertPrimatives.Na__DeepPick__InstanceName(instance)} has nothing in it to scale")
                return false
            end

            na_scale__adopt({ :instance => instance, :path => path }, frame)
            na_scale__select(instance, path) if select

            shared = frame[:definition].instances.length
            copies = shared > 1 ? " — one of #{shared} copies; a stretch makes it unique" : ''
            na_scale__say("#{Na__InsertPrimatives.Na__ScaleFrame__Label(frame)} #{na_scale__sizes_text(frame[:world_lengths])} mm — drag a grip, or click a dimension and type#{copies}")
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Take Loose Geometry, or Several Objects at Once, to Scale
        # ------------------------------------------------------------
        # 5.2.9. Edges and faces with no group or component around them have
        # no definition to keep stretch planes on, so this is the plain mode:
        # the grips, the dimensions and typed sizes, boxed in the axes the user
        # is drawing in (Na__ScaleFrame__ContextAxes), and a commit that moves
        # the points where they lie. Stretch Planes stays out of it.
        # ------------------------------------------------------------
        def na_scale__take_loose(entities, select = true)
            model = Sketchup.active_model
            return false unless model

            frame = Na__InsertPrimatives.Na__ScaleFrame__BuildLoose(model, entities)

            unless frame
                UI.beep
                na_scale__say('That geometry has nothing to scale — it is a point, flat every way')
                return false
            end

            na_scale__adopt({ :loose => true, :entities => frame[:entities], :context => frame[:context] }, frame)

            if select
                model.selection.clear
                model.selection.add(frame[:entities])
            end

            na_scale__say("#{frame[:name]} #{na_scale__sizes_text(frame[:world_lengths])} mm — drag a grip, or click a dimension and type (no stretch planes: those need a group or component)")
            true
        rescue StandardError => error
            Na__InsertPrimatives.Na__Debug__Puts "NA DEEP SCALE: loose geometry not taken — #{error.message}"
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Hold a New Target and Its Frame, Starting Clean
        # ------------------------------------------------------------
        def na_scale__adopt(target, frame)
            na_scale__cancel_drag
            na_scale__cancel_plane_drag

            @na_sc_target       = target
            @na_sc_frame        = frame
            @na_sc_grips        = Na__InsertPrimatives.Na__ScaleFrame__Grips(frame)
            @na_sc_planes       = na_scale__planes_of(frame)
            @na_sc_ghost        = nil
            @na_sc_ghost_key    = nil
            @na_sc_hover        = nil
            @na_sc_hover_object = nil
            @na_sc_plane_hover  = nil
            @na_sc_active_dim   = nil
            @na_sc_active_plane = nil
            @na_sc_focus        = nil
            @na_sc_sides        = {}
            @na_sc_seen_axes    = nil
            @na_sc_typed        = nil
            @na_last_vcb_text   = nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Stretch Planes a Frame Carries — None for Loose Geometry
        # ------------------------------------------------------------
        def na_scale__planes_of(frame)
            return Na__InsertPrimatives.Na__ScalePlanes__Empty if frame.nil? || frame[:loose]

            Na__InsertPrimatives.Na__ScalePlanes__Read(frame[:definition])
        end
        # ---------------------------------------------------------------

        # FUNCTION | Put the Object in SketchUp's Selection, When It Can Be
        # ------------------------------------------------------------
        def na_scale__select(instance, path)
            model = Sketchup.active_model
            return false unless model

            depth = Na__InsertPrimatives.Na__DeepPick__Instances(path).length
            return false unless depth == Na__InsertPrimatives.Na__ScaleFrame__OpenDepth(model) + 1

            model.selection.clear
            model.selection.add(instance)
            true
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Take What the User Had Selected
        # ------------------------------------------------------------
        # One group or component is that object, planes and all. Anything else
        # — loose edges and faces, or several objects — is taken whole as loose
        # geometry (5.2.9).
        # ------------------------------------------------------------
        def na_scale__take_selection
            model = Sketchup.active_model
            return false unless model

            picked = model.selection.to_a
            return false if picked.empty?

            if picked.length == 1 && (picked.first.is_a?(Sketchup::Group) || picked.first.is_a?(Sketchup::ComponentInstance))
                instance = picked.first
                return na_scale__take(instance, Na__InsertPrimatives.Na__DeepPick__AbsolutePath([instance]), false)
            end

            na_scale__take_loose(picked, false)
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Let Go of the Object
        # ------------------------------------------------------------
        def na_scale__release
            na_scale__cancel_drag
            na_scale__cancel_plane_drag

            @na_sc_target       = nil
            @na_sc_frame        = nil
            @na_sc_grips        = []
            @na_sc_planes       = nil
            @na_sc_ghost        = nil
            @na_sc_ghost_key    = nil
            @na_sc_hover        = nil
            @na_sc_plane_hover  = nil
            @na_sc_active_dim   = nil
            @na_sc_active_plane = nil
            @na_sc_focus        = nil
            @na_axis_lock       = nil
            @na_sc_typed        = nil
            @na_last_vcb_text   = nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Keep the Frame True to the Model
        # ------------------------------------------------------------
        # Asked on every mouse move and every draw, and cheap: a commit, an
        # undo, a redo or an edit made with another tool all change the
        # fingerprint, and the frame is rebuilt from the model as it now is.
        # Never mid-drag — the drag is measured against the frame it started
        # from. The planes are read again every time, because an undone plane
        # changes nothing the fingerprint looks at.
        # ------------------------------------------------------------
        def na_scale__refresh_frame
            return false unless @na_sc_target
            return false if @na_sc_drag || @na_sc_plane_drag
            return na_scale__refresh_loose if @na_sc_target[:loose]

            instance = @na_sc_target[:instance]
            path     = @na_sc_target[:path]

            unless instance && instance.valid? && Na__InsertPrimatives.Na__ScaleFrame__PathLive?(path)
                na_scale__release
                na_scale__say('The object is no longer there — hover another and click it')
                return false
            end

            @na_sc_planes = Na__InsertPrimatives.Na__ScalePlanes__Read(instance.definition)
            fingerprint   = Na__InsertPrimatives.Na__ScaleFrame__Fingerprint(instance, path)
            return false if @na_sc_frame && @na_sc_frame[:fingerprint] == fingerprint

            na_scale__rebuild_frame
        end
        # ---------------------------------------------------------------

        # FUNCTION | Keep a Loose Frame True to the Model
        # ------------------------------------------------------------
        # Let go of when the geometry has gone, or when the user has opened or
        # closed a group since: the entities are only scalable from the
        # context they sit in.
        # ------------------------------------------------------------
        def na_scale__refresh_loose
            model = Sketchup.active_model
            alive = model && @na_sc_target[:entities].any?(&:valid?) &&
                    Na__InsertPrimatives.Na__DeepPick__SameContext?(model.active_path, @na_sc_target[:context])

            unless alive
                na_scale__release
                na_scale__say('The geometry is no longer there, or another group is open — select it again')
                return false
            end

            fingerprint = Na__InsertPrimatives.Na__ScaleFrame__LooseFingerprint(model, @na_sc_target[:entities])
            return false if @na_sc_frame && @na_sc_frame[:fingerprint] == fingerprint

            na_scale__rebuild_frame
        end
        # ---------------------------------------------------------------

        # FUNCTION | Build the Frame Again From the Model
        # ------------------------------------------------------------
        def na_scale__rebuild_frame
            return false unless @na_sc_target

            frame =
                if @na_sc_target[:loose]
                    Na__InsertPrimatives.Na__ScaleFrame__BuildLoose(Sketchup.active_model, @na_sc_target[:entities])
                else
                    Na__InsertPrimatives.Na__ScaleFrame__Build(@na_sc_target[:instance], @na_sc_target[:path])
                end

            unless frame
                na_scale__release
                return false
            end

            @na_sc_frame  = frame
            @na_sc_grips  = Na__InsertPrimatives.Na__ScaleFrame__Grips(frame)
            @na_sc_planes = na_scale__planes_of(frame)
            @na_sc_ghost  = nil
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Does the Held Object's Path Run Through This One?
        # True for the held object itself and for anything it sits inside, so
        # a click on the body of a part reached by double-clicking down does
        # not hand the tool back the object around it. Loose geometry holds no
        # object, so a click on one takes it.
        # ------------------------------------------------------------
        def na_scale__holds?(path)
            return false unless @na_sc_target
            return false if @na_sc_target[:loose]

            held      = Na__InsertPrimatives.Na__DeepPick__Instances(@na_sc_target[:path])
            candidate = Na__InsertPrimatives.Na__DeepPick__Instances(path)
            return false if candidate.empty? || candidate.length > held.length

            candidate.each_with_index.all? { |instance, index| instance == held[index] }
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Loose Face or Edge of the Open Context Under the Cursor, or nil
        # ------------------------------------------------------------
        # A pick path one long is an entity of the open context itself: not
        # inside any group or component.
        # ------------------------------------------------------------
        def na_scale__loose_at(view, x, y)
            helper = view.pick_helper
            helper.do_pick(x, y)

            count = helper.count.to_i
            count = NA_DEEP_PICK_MAX_PATHS if count > NA_DEEP_PICK_MAX_PATHS

            count.times do |index|
                path = helper.path_at(index)
                next unless path && path.length == 1

                leaf = path.first
                next unless leaf.is_a?(Sketchup::Face) || leaf.is_a?(Sketchup::Edge)
                next unless Na__InsertPrimatives.Na__ScaleFrame__Visible?(leaf)

                return leaf
            end

            nil
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is This Loose Entity Part of What Is Held Already?
        # ------------------------------------------------------------
        def na_scale__holds_loose?(entity)
            @na_sc_target && @na_sc_target[:loose] && @na_sc_target[:entities].include?(entity) ? true : false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Double-Click Inside — Take the Part Under the Cursor
        # ------------------------------------------------------------
        def na_scale__drill_down(view, x, y)
            return false unless @na_sc_target
            return false if @na_sc_target[:loose]

            held   = Na__InsertPrimatives.Na__DeepPick__Instances(@na_sc_target[:path])
            helper = view.pick_helper
            helper.do_pick(x, y)

            count = helper.count.to_i
            count = NA_DEEP_PICK_MAX_PATHS if count > NA_DEEP_PICK_MAX_PATHS

            count.times do |index|
                path = Na__InsertPrimatives.Na__DeepPick__Instances(
                    Na__InsertPrimatives.Na__DeepPick__AbsolutePath(helper.path_at(index))
                )
                next unless path.length > held.length
                next unless held.each_with_index.all? { |instance, position| path[position] == instance }

                child = path[held.length]
                next if child.respond_to?(:locked?) && child.locked?
                next unless Na__InsertPrimatives.Na__ScaleFrame__Visible?(child)

                return na_scale__take(child, path[0..held.length], false)
            end

            UI.beep
            na_scale__say("Nothing inside #{@na_sc_frame ? @na_sc_frame[:name] : 'it'} under the cursor — every part of it here is loose geometry")
            false
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | BKSP — Back Out to the Object Around the Held Part
        # ------------------------------------------------------------
        def na_scale__step_up
            return false unless @na_sc_target
            return false if @na_sc_target[:loose]

            held = Na__InsertPrimatives.Na__DeepPick__Instances(@na_sc_target[:path])
            return false unless held.length > Na__InsertPrimatives.Na__ScaleFrame__OpenDepth + 1

            parent_path = held[0...-1]
            na_scale__take(parent_path.last, parent_path, true)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | SketchUp Tool API — Mouse
        # -----------------------------------------------------------------------------

        # ON MOUSE MOVE | Hover, or Follow a Drag
        # ------------------------------------------------------------
        def onMouseMove(flags, x, y, view)
            na_drawn__sync_modifier(flags)
            na_scale__refresh_frame
            na_drawn__update_cursor(view, x, y)
            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate
        end
        # ---------------------------------------------------------------

        # FUNCTION | The One Place the Cursor Is Read — Mouse Moves and Held Keys
        # ------------------------------------------------------------
        # The shared key handlers call this when CTRL or SHIFT goes down or
        # up with the mouse still, so a drag re-solves the instant a key
        # changes what it means.
        # ------------------------------------------------------------
        def na_drawn__update_cursor(view, x, y)
            @na_last_mouse_x = x
            @na_last_mouse_y = y
            return false unless view

            return na_scale__update_plane_drag(view, x, y) if @na_sc_plane_drag
            return na_scale__update_drag(view, x, y) if @na_sc_drag

            na_scale__update_hover(view, x, y)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Work Out What the Cursor Is Over
        # ------------------------------------------------------------
        # The bar first (it sits on top of everything), then CTRL's plane
        # offer — the key is held to say "a plane, here", so it outranks what
        # is under the cursor — then the grips — a few pixels each, so they
        # win wherever a dimension's label happens to reach — then the
        # dimensions, the planes, and only then another object in the model,
        # which is the one question that costs a pick.
        # ------------------------------------------------------------
        def na_scale__update_hover(view, x, y)
            @na_sc_hover        = nil
            @na_sc_hover_object = nil
            @na_sc_plane_hover  = nil

            if @na_sc_frame
                button = na_scale__bar_at(view, x, y)
                return @na_sc_hover = { :kind => :bar, :id => button[:id] } if button

                if @na_ctrl_held
                    axis = na_scale__ctrl_axis(view, x, y)
                    return na_scale__offer_plane(view, axis, x, y, true) if axis
                end

                grip = na_scale__grip_at(view, x, y)
                return @na_sc_hover = { :kind => :grip, :grip => grip } if grip

                dim = na_scale__dim_at(view, x, y)
                return @na_sc_hover = { :kind => :dim, :axis => dim[:axis] } if dim

                if na_scale__planes_on?
                    handle = na_scale__handle_at(view, x, y)
                    return @na_sc_hover = handle.merge(:kind => :handle) if handle

                    axis = na_scale__line_at(view, x, y)
                    return na_scale__offer_plane(view, axis, x, y) if axis
                end
            end

            object = Na__InsertPrimatives.Na__DeepPick__InstanceAt(view, x, y)

            unless object
                loose = na_scale__loose_at(view, x, y)
                return nil unless loose && !na_scale__holds_loose?(loose)

                return @na_sc_hover = { :kind => :loose, :id => loose.entityID }
            end

            return nil if @na_sc_frame && na_scale__holds?(object[:path])

            @na_sc_hover_object = object
            @na_sc_hover        = { :kind => :object }
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Cursor Is on a Centre Line, or CTRL Is Held — Show the Plane a Click Would Add
        # ------------------------------------------------------------
        def na_scale__offer_plane(view, axis, x, y, ctrl = false)
            @na_sc_hover = { :kind => :line, :axis => axis, :ctrl => ctrl }

            snapped = na_scale__plane_snap(view, axis, x, y)
            return @na_sc_hover unless snapped

            offer = { :axis => axis, :u => snapped[0], :how => snapped[1] }

            if @na_shift_held
                twin = na_scale__mirror_value(axis, snapped[0])
                offer[:twin] = twin unless na_scale__same_plane?(axis, twin, snapped[0])
            end

            @na_sc_plane_hover = offer
            @na_sc_hover
        end
        # ---------------------------------------------------------------

        # ON LEFT BUTTON DOWN | Press What Is Under the Cursor, or Place a Drag
        # ------------------------------------------------------------
        def onLButtonDown(flags, x, y, view)
            @na_vcb_typing_active = false
            @na_sc_typed          = nil                                    # <-- A click abandons the entry, and its mirror
            na_drawn__sync_modifier(flags)
            na_scale__refresh_frame
            @na_last_mouse_x = x
            @na_last_mouse_y = y

            if @na_sc_drag
                na_scale__update_drag(view, x, y)                             # <-- The second click of click-move-click places it
                na_scale__commit_drag(view)
            else
                na_scale__press(view, x, y)
            end

            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Press With No Drag Running
        # ------------------------------------------------------------
        def na_scale__press(view, x, y)
            @na_sc_last_placed = nil                                          # <-- Only the press that drops a plane may set it again

            if @na_sc_frame
                button = na_scale__bar_at(view, x, y)
                return na_scale__bar_click(view, button) if button

                if @na_ctrl_held
                    axis = na_scale__ctrl_axis(view, x, y)
                    return na_scale__begin_ctrl_plane(view, axis, x, y) if axis
                end

                grip = na_scale__grip_at(view, x, y)
                return na_scale__begin_drag(view, grip, x, y) if grip

                dim = na_scale__dim_at(view, x, y)
                return na_scale__dim_click(view, dim) if dim

                if na_scale__planes_on?
                    handle = na_scale__handle_at(view, x, y)
                    return na_scale__begin_move_plane(view, handle, x, y) if handle

                    axis = na_scale__line_at(view, x, y)
                    return na_scale__begin_new_plane(view, axis, x, y) if axis
                end
            end

            object = Na__InsertPrimatives.Na__DeepPick__InstanceAt(view, x, y)

            # Loose geometry under the cursor (no group around it): that face
            # or edge and everything connected to it, as Select > Connected
            # would take them (5.2.9).
            unless object
                loose = na_scale__loose_at(view, x, y)
                return na_scale__take_loose(loose.all_connected, true) if loose && !na_scale__holds_loose?(loose)
            end

            # Empty space lets go of whatever was taking the typing, and keeps
            # the object: a stray click should not cost the user their place.
            unless object
                @na_sc_focus        = nil
                @na_sc_active_dim   = nil
                @na_sc_active_plane = nil
                return false
            end

            return false if @na_sc_frame && na_scale__holds?(object[:path])

            na_scale__take(object[:instance], object[:path], true)
        end
        # ---------------------------------------------------------------

        # FUNCTION | CTRL+Click — Add a Plane Where the Offer Stands
        # ------------------------------------------------------------
        # A plane is the point of the key, so with Stretch Planes off it is
        # switched on first: a plane placed and then ignored by the grips
        # would be a plane that did nothing.
        # ------------------------------------------------------------
        def na_scale__begin_ctrl_plane(view, axis, x, y)
            unless na_scale__planes_on?
                Na__InsertPrimatives.Na__ToolOptions__SetValue(NA_SCALE_OPTION_PLANES, true)
                Na__InsertPrimatives.Na__RightClickPopup__RefreshOption(NA_SCALE_OPTION_PLANES)
                na_scale__after_option_changed(NA_SCALE_OPTION_PLANES)
            end

            na_scale__begin_new_plane(view, axis, x, y)
        end
        # ---------------------------------------------------------------

        # ON LEFT BUTTON UP | Press-Drag-Release Places a Scale or a Plane
        # ------------------------------------------------------------
        # A grip pressed and let go without travelling stays held, so
        # click-move-click works as it does in every tool here.
        # ------------------------------------------------------------
        def onLButtonUp(flags, x, y, view)
            na_drawn__sync_modifier(flags)

            if @na_sc_plane_drag
                na_scale__update_plane_drag(view, x, y)
                na_scale__release_plane_drag(view)
            elsif @na_sc_drag && @na_sc_drag[:pressed]
                @na_sc_drag[:pressed] = false
                travelled = (x.to_f - @na_sc_drag[:press_x].to_f).abs + (y.to_f - @na_sc_drag[:press_y].to_f).abs

                if travelled >= NA_DRAWN_DRAG_MIN_PX
                    na_scale__update_drag(view, x, y)
                    na_scale__commit_drag(view)
                end
            end

            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate
        end
        # ---------------------------------------------------------------

        # ON LEFT BUTTON DOUBLE CLICK | Place, Remove a Plane, or Go Inside
        # ------------------------------------------------------------
        # A double click arrives as Down, Up, DoubleClick, Up, so by now the
        # first Down has done its work: it picked up a grip (still held, not
        # moved), or dropped and saved a plane, or did nothing on the body.
        # ------------------------------------------------------------
        def onLButtonDoubleClick(flags, x, y, view)
            na_drawn__sync_modifier(flags)
            na_scale__refresh_frame

            if @na_sc_drag
                if @na_sc_drag[:moved]
                    na_scale__update_drag(view, x, y)
                    na_scale__commit_drag(view)
                    na_scale__after_mouse(view)
                    return true
                end

                na_scale__cancel_drag                                         # <-- A grip double-clicked is not a scale
            end

            if @na_sc_frame && na_scale__planes_on?
                handle = na_scale__handle_at(view, x, y)

                if handle
                    na_scale__remove_plane(handle[:axis], handle[:u]) unless na_scale__just_placed?(handle)
                    na_scale__after_mouse(view)
                    return true
                end
            end

            if @na_sc_frame
                object = Na__InsertPrimatives.Na__DeepPick__InstanceAt(view, x, y)
                na_scale__drill_down(view, x, y) if object && na_scale__holds?(object[:path])
            end

            na_scale__after_mouse(view)
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Status, Measurements Box and Redraw After a Mouse Event
        # ------------------------------------------------------------
        def na_scale__after_mouse(view)
            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
        end
        # ---------------------------------------------------------------

        # ON CANCEL | ESC Steps Back One Thing at a Time
        # ------------------------------------------------------------
        # A plane or a grip being dragged, then the typing focus or an arrow
        # lock, then the object itself, then the tool. An undo or a reselect
        # of the tool (reason 1 and 2) only drops a drag: the frame refresh
        # sees whatever the undo changed.
        # ------------------------------------------------------------
        def onCancel(reason, view)
            @na_vcb_typing_active = false

            # ESC empties the box, so the mirror goes too — and that is all
            # this ESC does: the dimension or plane being typed into stays
            # chosen, and the next ESC lets go of it.
            if reason == 0 && na_scale__typing?
                @na_sc_typed      = nil
                @na_last_vcb_text = nil
                na_scale__after_mouse(view)
                return
            end

            @na_sc_typed = nil

            if @na_sc_plane_drag
                na_scale__cancel_plane_drag
            elsif @na_sc_drag
                na_scale__cancel_drag
            elsif reason != 0
                nil
            elsif @na_sc_focus || @na_sc_active_dim || @na_axis_lock
                @na_sc_focus        = nil
                @na_sc_active_dim   = nil
                @na_sc_active_plane = nil
                @na_axis_lock       = nil
            elsif @na_sc_target
                na_scale__release
                na_scale__say('Let go — hover a group or component and click it')
            else
                na_drawn__schedule_exit_tool
            end

            na_scale__refresh_frame
            @na_last_vcb_text = nil
            na_scale__after_mouse(view)
        end
        # ---------------------------------------------------------------

        # ON RETURN | Enter on an Empty Measurements Box Places a Held Drag
        # ------------------------------------------------------------
        def onReturn(view)
            return false unless @na_sc_drag

            na_scale__commit_drag(view)
            na_scale__after_mouse(view)
            true
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Grips and the Drag
        # -----------------------------------------------------------------------------

        # FUNCTION | The Grips the Handle Set Shows, Each With Its Place on Screen
        # ------------------------------------------------------------
        # Then thinned for the view. An axis seen end-on (Y in a front
        # elevation) cannot be pulled by a grip, and every grip that pulls it
        # sits exactly on top of one that does not: the front corner on the
        # elevation's corner, the front face's middle on nothing at all. So a
        # grip that only pulls end-on axes is left out, and one that pulls an
        # end-on axis as well is left out wherever an honest grip — one whose
        # every axis can be seen — stands on the same spot. In a 3D view
        # every axis can be seen and nothing is thinned.
        # ------------------------------------------------------------
        def na_scale__visible_grips(view)
            frame = @na_sc_frame
            return [] unless frame

            set   = na_scale__handle_set
            spans = Na__InsertPrimatives.Na__ScaleFrame__ScreenSpans(view, frame)
            @na_sc_seen_axes = (0..2).map { |n| frame[:usable][n] && spans[n] >= NA_SCALE_MIN_EDGE_PIXELS }

            entries = @na_sc_grips.map do |grip|
                next nil unless Na__InsertPrimatives.Na__ScaleFrame__GripInSet?(frame, grip, set)

                seen = grip[:axes].select { |axis| @na_sc_seen_axes[NA_SCALE_AXIS_INDEX[axis]] }
                next nil if seen.empty?

                screen = Na__InsertPrimatives.Na__ScalePreview__Screen(view, grip[:world])
                next nil unless screen

                {
                    :grip   => grip,
                    :screen => screen,
                    :front  => Na__InsertPrimatives.Na__ScaleFrame__GripFacing?(view, frame, grip),
                    :honest => seen.length == grip[:axes].length
                }
            end.compact

            honest = entries.select { |entry| entry[:honest] }

            entries.reject do |entry|
                next false if entry[:honest]

                honest.any? do |other|
                    (other[:screen].x - entry[:screen].x).abs < 3.0 && (other[:screen].y - entry[:screen].y).abs < 3.0
                end
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Grip Under the Cursor — the Near Side Wins Every Tie
        # ------------------------------------------------------------
        def na_scale__grip_at(view, x, y)
            best = nil

            na_scale__visible_grips(view).each do |entry|
                dx   = entry[:screen].x - x
                dy   = entry[:screen].y - y
                dist = Math.sqrt((dx * dx) + (dy * dy))
                next if dist > NA_SCALE_GRIP_HIT_PX

                rank = [entry[:front] ? 0 : 1, dist]
                best = [rank, entry[:grip]] if best.nil? || (rank <=> best[0]) < 0
            end

            best ? best[1] : nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Does This Grip Scale Uniformly Right Now?
        # ------------------------------------------------------------
        # A grip that pulls every axis that can be seen is a corner — in 3D
        # the corner of the box, on a flat panel the corner of the panel, in
        # an elevation the corner of the elevation — and is uniform by
        # default, the way SketchUp's corners are. Face and edge grips are
        # free. SHIFT swaps either way. A uniform scale scales every axis the
        # object has, seen or not, as SketchUp's does.
        # ------------------------------------------------------------
        def na_scale__uniform?(grip)
            seen = @na_sc_seen_axes || @na_sc_frame[:usable]
            need = (0..2).select { |n| seen[n] }.map { |n| NA_SCALE_AXES[n] }
            full = grip[:axes].length > 1 && (need - grip[:axes]).empty?

            full ^ (@na_shift_held ? true : false)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Which End of an Axis a Grip Holds Still
        # ------------------------------------------------------------
        def na_scale__side_for(grip, index, centre)
            return :centre if centre

            sign = grip[:signs][index]
            return :min if sign > 0
            return :max if sign < 0

            :centre                                                           # <-- An axis a uniform face grip carries along with it
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Ghost of the Object, Read Once per Frame
        # ------------------------------------------------------------
        def na_scale__ghost
            key = @na_sc_frame ? @na_sc_frame[:fingerprint] : nil
            return @na_sc_ghost if @na_sc_ghost && @na_sc_ghost_key == key

            @na_sc_ghost     = @na_sc_frame[:loose] ? Na__InsertPrimatives.Na__ScaleFrame__CollectGhostLoose(@na_sc_frame) :
                                                      Na__InsertPrimatives.Na__ScaleFrame__CollectGhost(@na_sc_frame[:definition])
            @na_sc_ghost_key = key
            @na_sc_ghost
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Smallest World Length Each Stretching Axis Can Take
        # Empty with Stretch Planes off: a plain scale only has to stay above
        # nothing.
        # ------------------------------------------------------------
        def na_scale__stretch_limits
            limits = {}
            frame  = @na_sc_frame
            return limits unless frame && na_scale__planes_on?

            # Asked several times a frame while a size is being typed, and the
            # answer only changes with the object or its planes.
            key = [frame[:fingerprint], @na_sc_planes]
            return @na_sc_limits[1] if @na_sc_limits && @na_sc_limits[0] == key

            ghost = nil

            NA_SCALE_AXES.each_with_index do |axis, n|
                inside = Na__InsertPrimatives.Na__ScalePlanes__Inside(frame, axis, (@na_sc_planes || {})[axis])
                next if inside.empty?

                ghost ||= na_scale__ghost
                coords  = (ghost[:points] + ghost[:extra]).map { |point| point[n].to_f }
                keep    = NA_SCALE_MIN_GAP.to_f / frame[:scales][n]                # <-- Never closed all the way: the commit refuses that too
                delta   = Na__InsertPrimatives.Na__ScaleField__StretchMinDelta(inside, frame[:centre][n], frame[:local_lengths][n], coords, keep)
                limits[axis] = (frame[:local_lengths][n] + delta) * frame[:scales][n]
            end

            @na_sc_limits = [key, limits]
            limits
        end
        # ---------------------------------------------------------------

        # FUNCTION | Pick Up a Grip
        # ------------------------------------------------------------
        def na_scale__begin_drag(view, grip, x, y)
            na_scale__ghost

            @na_sc_drag = {
                :grip    => grip,
                :press_x => x,
                :press_y => y,
                :pressed => true,
                :moved   => false,
                :factors => {},
                :sides   => {},
                :field   => nil,
                :lengths => @na_sc_frame[:world_lengths].dup,
                :limits  => na_scale__stretch_limits,
                :cursor  => grip[:world],
                :how     => nil,
                :uniform => false
            }

            @na_state           = :picking_depth
            @na_sc_focus        = nil
            @na_sc_active_plane = nil
            @na_sc_plane_hover  = nil
            @na_sc_active_dim   = grip[:axes].length == 1 ? grip[:axes].first : nil

            na_scale__update_drag(view, x, y)
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Drop the Grip Without Changing Anything
        # ------------------------------------------------------------
        def na_scale__cancel_drag
            return false unless @na_sc_drag

            @na_sc_drag = nil
            @na_state   = :idle
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Where the Grip Has Been Pulled To, in World Space
        # ------------------------------------------------------------
        # CTRL hands the question to SketchUp's inference, so the grip lands
        # on a point of the model. Otherwise the cursor ray is brought onto
        # the path the grip can travel: the line it runs along (a face grip,
        # or any uniform pull), the plane it slides in (an edge grip), or the
        # plane facing the camera through it (a free corner).
        #
        # Returns [point, how] or nil when the answer would be behind the eye.
        # ------------------------------------------------------------
        def na_scale__drag_point(view, x, y, grip, uniform, centre)
            frame = @na_sc_frame

            if @na_ctrl_held
                @na_ip.pick(view, x, y)
                return [@na_ip.position, 'vertex'] if @na_ip.valid? && @na_ip.position
            end

            ray    = view.pickray(x, y)
            anchor = Na__InsertPrimatives.Na__ScaleFrame__AnchorLocal(frame, grip, centre).transform(frame[:world])
            start  = grip[:world]

            if uniform || grip[:axes].length == 1
                direction = uniform ? (start - anchor) : frame[:dirs][NA_SCALE_AXIS_INDEX[grip[:axes].first]]
                return nil unless direction.length > 0.0

                closest = Geom.closest_points([start, direction], ray)
                return nil unless closest && closest[0]
                return nil unless (closest[1] - ray[0]).dot(ray[1]) > 0.0

                return [closest[0], nil]
            end

            normal =
                if grip[:axes].length == 2
                    first, second = grip[:axes].map { |axis| frame[:dirs][NA_SCALE_AXIS_INDEX[axis]] }
                    first.cross(second)
                else
                    view.camera.direction
                end

            normal = view.camera.direction if normal.length.zero? || normal.normalize.dot(ray[1]).abs < 0.05
            point  = Geom.intersect_line_plane(ray, [start, normal])
            return nil unless point && (point - ray[0]).dot(ray[1]) > 0.0

            [point, nil]
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Follow the Cursor With the Held Grip
        # ------------------------------------------------------------
        # Nothing changes until the mouse has really moved: a grip pressed on
        # a box that is not on the grid would otherwise snap it there on the
        # spot, and a double-click on a grip would resize the object.
        #
        # Sizes, not travel, snap to the grid: a door 1049 wide drags to
        # 1050, 1055, 1060 — the number that ends up on the drawing.
        # ------------------------------------------------------------
        def na_scale__update_drag(view, x, y)
            drag  = @na_sc_drag
            frame = @na_sc_frame
            return false unless drag && frame

            travelled     = (x.to_f - drag[:press_x].to_f).abs + (y.to_f - drag[:press_y].to_f).abs
            drag[:moved]  = true if travelled >= NA_DRAWN_DRAG_MIN_PX
            return false unless drag[:moved]

            grip    = drag[:grip]
            centre  = na_scale__centre_on?
            uniform = na_scale__uniform?(grip)
            picked  = na_scale__drag_point(view, x, y, grip, uniform, centre)
            return false unless picked

            point, how = picked
            snap       = !@na_ctrl_held
            factors    = {}
            sides      = {}

            if uniform
                anchor = Na__InsertPrimatives.Na__ScaleFrame__AnchorLocal(frame, grip, centre).transform(frame[:world])
                span   = grip[:world] - anchor
                factor = (point - anchor).dot(span) / span.dot(span)
                factor = na_scale__snap_uniform(factor) if snap
                factor = na_scale__clamp_uniform(factor, drag[:limits])

                NA_SCALE_AXES.each_with_index do |axis, n|
                    next unless frame[:usable][n]

                    factors[axis] = factor
                    sides[axis]   = na_scale__side_for(grip, n, centre)
                end
            else
                local = point.transform(frame[:inverse])

                grip[:axes].each do |axis|
                    n      = NA_SCALE_AXIS_INDEX[axis]
                    sign   = grip[:signs][n]
                    anchor = centre ? frame[:centre][n] : (sign > 0 ? frame[:min][n] : frame[:max][n])
                    length = (local[n] - anchor) * sign * (centre ? 2.0 : 1.0) * frame[:scales][n]
                    length = Na__InsertPrimatives.Na__DrawnGrid__SnapDistance(length) if snap
                    length = na_scale__clamp_length(axis, length, drag[:limits])

                    factors[axis] = length / frame[:world_lengths][n]
                    sides[axis]   = na_scale__side_for(grip, n, centre)
                end
            end

            planes = na_scale__planes_on? ? @na_sc_planes : nil
            field  = Na__InsertPrimatives.Na__ScaleField__Build(frame, factors, sides, planes)
            mins, maxs = Na__InsertPrimatives.Na__ScaleField__Box(field, frame)

            drag[:factors] = factors
            drag[:sides]   = sides
            drag[:field]   = field
            drag[:uniform] = uniform
            drag[:how]     = how
            drag[:cursor]  = point
            drag[:lengths] = (0..2).map { |n| (maxs[n] - mins[n]) * frame[:scales][n] }
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Round a Uniform Factor So the Longest Side Lands on the Grid
        # ------------------------------------------------------------
        def na_scale__snap_uniform(factor)
            frame   = @na_sc_frame
            longest = frame[:world_lengths].each_with_index.select { |_length, n| frame[:usable][n] }.map(&:first).max.to_f
            return factor unless longest > 0.0

            Na__InsertPrimatives.Na__DrawnGrid__SnapDistance(longest * factor) / longest
        end
        # ---------------------------------------------------------------

        # FUNCTION | Keep a Uniform Factor Above Every Axis's Floor
        # ------------------------------------------------------------
        def na_scale__clamp_uniform(factor, limits)
            frame = @na_sc_frame
            floor = 0.0

            NA_SCALE_AXES.each_with_index do |axis, n|
                next unless frame[:usable][n]

                least = [NA_SCALE_MIN_WORLD.to_f, (limits[axis] || 0.0).to_f].max
                need  = least / frame[:world_lengths][n]
                floor = need if need > floor
            end

            factor < floor ? floor : factor
        end
        # ---------------------------------------------------------------

        # FUNCTION | Keep One Axis's New Length Above Its Floor
        # The floor is a millimetre, or for a stretching axis the size at
        # which its slices would start to pass through each other.
        # ------------------------------------------------------------
        def na_scale__clamp_length(axis, length, limits)
            least = [NA_SCALE_MIN_WORLD.to_f, (limits[axis] || 0.0).to_f].max
            length < least ? least : length
        end
        # ---------------------------------------------------------------

        # FUNCTION | Place the Drag
        # ------------------------------------------------------------
        def na_scale__commit_drag(_view)
            drag = @na_sc_drag
            return false unless drag

            field = drag[:field]

            if field.nil? || Na__InsertPrimatives.Na__ScaleField__Identity?(field)
                na_scale__cancel_drag
                return false
            end

            na_scale__cancel_drag
            result = na_scale__commit_field(field, drag[:sides])

            if result[:success] && drag[:grip][:axes].length == 1 && !drag[:uniform]
                @na_sc_active_dim = drag[:grip][:axes].first                  # <-- Type straight after and it corrects what was just placed
                @na_sc_focus      = :dimension
            end

            result[:success]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Put a Field Into the Model and Say What Happened
        # ------------------------------------------------------------
        def na_scale__commit_field(field, sides)
            model  = Sketchup.active_model
            frame  = @na_sc_frame
            label  = Na__InsertPrimatives.Na__ScaleFrame__Label(frame)
            after  = nil

            if field[:stretch]
                mins, maxs = Na__InsertPrimatives.Na__ScaleField__Box(field, frame)
                after      = Na__InsertPrimatives.Na__ScalePlanes__Prune(
                    Na__InsertPrimatives.Na__ScaleField__PlanesAfter(field, @na_sc_planes), mins, maxs
                )
            end

            result = Na__InsertPrimatives.Na__ScaleCommit__Run(model, frame, field, after)

            unless result[:success]
                UI.beep
                na_scale__say("Deep Scale did not change #{label} — #{result[:error] || 'nothing to change'}")
                Na__InsertPrimatives.Na__Debug__Puts "NA DEEP SCALE: commit failed — #{result[:error]}"
                return result
            end

            sides.each { |axis, side| @na_sc_sides[axis] = side }
            na_scale__rebuild_frame
            na_scale__report(result, label)
            result
        end
        # ---------------------------------------------------------------

        # FUNCTION | Say What a Commit Did
        # ------------------------------------------------------------
        def na_scale__report(result, label)
            frame = @na_sc_frame
            sizes = frame ? na_scale__sizes_text(frame[:world_lengths]) : '?'
            verb  = result[:mode] == :stretch ? 'Stretched' : 'Scaled'
            notes = []
            notes << 'made unique' if result[:unique].to_i > 0
            notes << "#{result[:opened]} part#{result[:opened].to_i == 1 ? '' : 's'} inside stretched too" if result[:opened].to_i > 0

            tail = notes.empty? ? '' : " (#{notes.join(', ')})"
            na_scale__say("#{verb} #{label} to #{sizes} mm#{tail} — type a size to adjust, Ctrl+Z to undo")
            Na__InsertPrimatives.Na__Debug__Puts(
                "NA DEEP SCALE: #{verb.downcase} #{label} to #{sizes} mm — #{result[:moved]} vertices moved, " \
                "#{result[:rigid]} parts carried, #{result[:opened]} opened, #{result[:unique]} made unique"
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | Three World Lengths as "W x D x H", Skipping a Flat Axis
        # ------------------------------------------------------------
        def na_scale__sizes_text(lengths)
            frame = @na_sc_frame

            lengths.each_with_index.map do |length, n|
                next nil if frame && !frame[:usable][n]

                Na__InsertPrimatives.Na__DrawnFormat__Mm(length).to_s
            end.compact.join(' x ')
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Keys — Arrows, TAB and BKSP
        # -----------------------------------------------------------------------------

        # FUNCTION | ARROWS Show One Axis's Grips for a Moment
        # ------------------------------------------------------------
        # Right X, Left Y, Up Z, Down lets go; the same arrow again lets go
        # too. The locked axis also takes the next typed value, so RIGHT,
        # 1200, Enter makes the object 1200 wide.
        # ------------------------------------------------------------
        def na_drawn__apply_axis_lock(axis, view)
            @na_axis_lock = (axis.nil? || @na_axis_lock == axis) ? nil : axis
            frame         = @na_sc_frame

            if @na_axis_lock && frame && !frame[:usable][NA_SCALE_AXIS_INDEX[@na_axis_lock]]
                na_scale__say("#{frame[:name]} is flat on #{@na_axis_lock.to_s.upcase} — there is nothing to scale along it")
                @na_axis_lock = nil
            elsif @na_axis_lock
                @na_sc_active_dim = @na_axis_lock
                @na_sc_focus      = :dimension
            elsif @na_sc_focus == :dimension
                @na_sc_active_dim = nil
                @na_sc_focus      = nil
            end

            na_drawn__update_cursor(view, @na_last_mouse_x, @na_last_mouse_y) unless @na_sc_drag || @na_sc_plane_drag
            @na_last_vcb_text = nil
            na_scale__after_mouse(view)
        end
        # ---------------------------------------------------------------

        # FUNCTION | TAB Switches About Centre
        # ------------------------------------------------------------
        # In place of the shape tools' plane cycling. A drag in hand re-solves
        # at once, so TAB mid-drag swaps between one end and both.
        # ------------------------------------------------------------
        def na_drawn__cycle_plane_lock(view)
            Na__InsertPrimatives.Na__ToolOptions__Toggle(NA_SCALE_OPTION_CENTRE)
            Na__InsertPrimatives.Na__RightClickPopup__RefreshOption(NA_SCALE_OPTION_CENTRE)
            na_scale__say(Na__InsertPrimatives.Na__ToolOptions__CaptionFor(NA_SCALE_OPTION_CENTRE))

            na_drawn__update_cursor(view, @na_last_mouse_x, @na_last_mouse_y)
            @na_last_vcb_text = nil
            na_scale__after_mouse(view)
        end
        # ---------------------------------------------------------------

        # FUNCTION | What TAB Does in This Tool
        # ------------------------------------------------------------
        def na_drawn__tab_hint
            'TAB about centre  SHIFT+TAB planes'
        end
        # ---------------------------------------------------------------

        # FUNCTION | BKSP / DEL — Remove a Plane, or Come Back Out a Level
        # ------------------------------------------------------------
        def na_drawn__step_back(view)
            hover = @na_sc_hover

            if @na_sc_plane_drag
                na_scale__cancel_plane_drag
            elsif @na_sc_drag
                na_scale__cancel_drag
            elsif hover && hover[:kind] == :handle
                na_scale__remove_plane(hover[:axis], hover[:u])
                @na_sc_hover = nil
            elsif @na_sc_focus == :plane && @na_sc_active_plane
                na_scale__remove_plane(@na_sc_active_plane[:axis], @na_sc_active_plane[:u])
            elsif na_scale__step_up
                nil
            elsif @na_sc_focus || @na_axis_lock
                @na_sc_focus      = nil
                @na_sc_active_dim = nil
                @na_axis_lock     = nil
            end

            @na_last_vcb_text = nil
            na_scale__after_mouse(view)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is the InputPoint What Is Placing Something Right Now?
        # Only then is its marker honest: a plane being dragged, a grip on
        # CTRL, or a plane on offer that is snapping to geometry.
        # ------------------------------------------------------------
        def na_drawn__inference_visible?
            return true if @na_sc_plane_drag
            return true if @na_sc_drag && @na_ctrl_held
            return true if @na_sc_plane_hover && @na_sc_plane_hover[:how] != 'grid'

            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | CTRL+SHIFT Is Not Vertex-Then-Grid Here
        # SHIFT is the uniform switch, so CTRL+SHIFT is a uniform scale to a
        # point — exactly what the two keys say on their own.
        # ------------------------------------------------------------
        def na_drawn__vertex_grid_supported?
            false
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Measurements Box Entry
        # -----------------------------------------------------------------------------

        # FUNCTION | A Typed Value Resizes at Once
        # ------------------------------------------------------------
        # In order of what the user last pointed at:
        #   a plane just placed or moved   its distance from the low end
        #   a grip being dragged           the grip's axes, in X Y Z order
        #   a clicked dimension            that axis
        #   nothing                        X,Y,Z in order
        # ------------------------------------------------------------
        def na_drawn__handle_vcb_text(text, view)
            @na_sc_typed = nil

            if na_scale__typing_plane?
                return na_scale__type_plane(text, view)
            end

            raise ArgumentError, 'hover a group or component and click it first' unless @na_sc_frame

            field, sides = na_scale__typed_field(text)
            raise ArgumentError, 'that is already its size' if Na__InsertPrimatives.Na__ScaleField__Identity?(field)

            axis = @na_sc_drag && @na_sc_drag[:grip][:axes].length == 1 ? @na_sc_drag[:grip][:axes].first : @na_sc_active_dim
            na_scale__cancel_drag
            result = na_scale__commit_field(field, sides)

            if result[:success] && axis
                @na_sc_active_dim = axis
                @na_sc_focus      = :dimension
            end

            result[:success]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Does Typing Go to a Plane Right Now?
        # ------------------------------------------------------------
        def na_scale__typing_plane?
            @na_sc_plane_drag || (@na_sc_focus == :plane && @na_sc_active_plane) ? true : false
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Field an Entry Asks For, and the Ends It Holds: [field, sides]
        # ------------------------------------------------------------
        # One reading for both the Enter and the live mirror, so what the
        # preview shows while typing is exactly what Enter will do. Raises
        # ArgumentError for an entry that cannot be read, or a shrink the
        # planes have no room for.
        # ------------------------------------------------------------
        def na_scale__typed_field(text)
            frame  = @na_sc_frame
            tokens = Na__InsertPrimatives.Na__ScaleVcb__ParseEntry(text)

            factors, sides =
                if @na_sc_drag && @na_sc_drag[:moved]
                    na_scale__typed_for_drag(tokens)
                elsif @na_sc_active_dim
                    na_scale__typed_for_axis(@na_sc_active_dim, tokens)
                else
                    na_scale__typed_in_order(tokens)
                end

            na_scale__check_limits(factors)

            planes = na_scale__planes_on? ? @na_sc_planes : nil
            [Na__InsertPrimatives.Na__ScaleField__Build(frame, factors, sides, planes), sides]
        end
        # ---------------------------------------------------------------

        # FUNCTION | What Is Being Typed, Laid Over the Dimensions It Goes To
        # ------------------------------------------------------------
        # Returns nil when nothing is typed. Otherwise :texts, the typed token
        # per axis it will land on — the last one with a caret, being the one
        # still growing — and :field when the entry already reads as a size
        # (nil while it does not yet: "1.", "12c", a lone "-").
        # ------------------------------------------------------------
        def na_scale__typed_state
            return nil unless na_scale__typing?

            text  = @na_sc_typed
            frame = @na_sc_frame
            return { :text => text, :texts => {}, :field => nil } if frame.nil? || na_scale__typing_plane?

            parts = text.split(',', -1)
            axes  =
                if @na_sc_drag && @na_sc_drag[:moved]
                    @na_sc_drag[:uniform] ? [@na_sc_drag[:grip][:axes].first] : @na_sc_drag[:grip][:axes]
                elsif @na_sc_active_dim
                    [@na_sc_active_dim]
                else
                    NA_SCALE_AXES
                end

            parts = [text] if axes.length == 1
            texts = {}

            parts.each_with_index do |part, index|
                axis = axes[index]
                next unless axis

                last = index == parts.length - 1
                next if part.strip.empty? && !last

                texts[axis] = last ? "[#{part.strip}|]" : "[#{part.strip}]"
            end

            field = nil
            note  = nil

            begin
                field, _sides = na_scale__typed_field(text)
                field = nil if Na__InsertPrimatives.Na__ScaleField__Identity?(field)
            rescue ArgumentError => error
                note = error.message
            end

            { :text => text, :texts => texts, :field => field, :note => note }
        end
        # ---------------------------------------------------------------

        # FUNCTION | The End a Typed Value Holds Still
        # About Centre if it is on; otherwise whichever end the last drag on
        # that axis held, so a correction typed after a drag to the right
        # keeps growing to the right. Never a centre the switch no longer asks for.
        # ------------------------------------------------------------
        def na_scale__typed_side(axis)
            return :centre if na_scale__centre_on?

            side = @na_sc_sides[axis]
            side == :max ? :max : :min
        end
        # ---------------------------------------------------------------

        # FUNCTION | Typed Mid-Drag — the Grip's Own Axes
        # ------------------------------------------------------------
        def na_scale__typed_for_drag(tokens)
            drag    = @na_sc_drag
            grip    = drag[:grip]
            frame   = @na_sc_frame
            centre  = na_scale__centre_on?
            factors = {}
            sides   = {}

            if drag[:uniform]
                given = tokens.compact
                raise ArgumentError, 'a uniform scale takes one value' if given.length > 1
                raise ArgumentError, 'no value entered' if given.empty?

                axis   = grip[:axes].first
                factor = Na__InsertPrimatives.Na__ScaleVcb__Factor(
                    given.first, frame[:world_lengths][NA_SCALE_AXIS_INDEX[axis]], axis.to_s.upcase
                )

                NA_SCALE_AXES.each_with_index do |each_axis, n|
                    next unless frame[:usable][n]

                    factors[each_axis] = factor
                    sides[each_axis]   = na_scale__side_for(grip, n, centre)
                end

                return [factors, sides]
            end

            if tokens.length > grip[:axes].length
                names = grip[:axes].map { |axis| axis.to_s.upcase }.join(',')
                raise ArgumentError, "this grip takes #{grip[:axes].length == 1 ? 'one value' : names}"
            end

            tokens.each_with_index do |token, index|
                next if token.nil?

                axis = grip[:axes][index]
                n    = NA_SCALE_AXIS_INDEX[axis]
                factors[axis] = Na__InsertPrimatives.Na__ScaleVcb__Factor(token, frame[:world_lengths][n], axis.to_s.upcase)
                sides[axis]   = na_scale__side_for(grip, n, centre)
            end

            [factors, sides]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Typed With a Dimension Clicked — That One Axis
        # ------------------------------------------------------------
        def na_scale__typed_for_axis(axis, tokens)
            raise ArgumentError, "the #{axis.to_s.upcase} dimension takes one value" if tokens.length > 1

            frame  = @na_sc_frame
            n      = NA_SCALE_AXIS_INDEX[axis]
            factor = Na__InsertPrimatives.Na__ScaleVcb__Factor(tokens[0], frame[:world_lengths][n], axis.to_s.upcase)
            raise ArgumentError, 'no value entered' if factor.nil?

            [{ axis => factor }, { axis => na_scale__typed_side(axis) }]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Typed With Nothing Clicked — X,Y,Z in Order
        # ------------------------------------------------------------
        def na_scale__typed_in_order(tokens)
            raise ArgumentError, 'type up to three sizes, X,Y,Z' if tokens.length > 3

            frame   = @na_sc_frame
            factors = {}
            sides   = {}

            tokens.each_with_index do |token, n|
                next if token.nil?

                axis = NA_SCALE_AXES[n]
                raise ArgumentError, "#{frame[:name]} is flat on #{axis.to_s.upcase} — leave that place empty" unless frame[:usable][n]

                factors[axis] = Na__InsertPrimatives.Na__ScaleVcb__Factor(token, frame[:world_lengths][n], axis.to_s.upcase)
                sides[axis]   = na_scale__typed_side(axis)
            end

            raise ArgumentError, 'no value entered' if factors.empty?

            [factors, sides]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Refuse a Typed Shrink the Planes Have No Room For
        # A drag is held at the limit; a typed value cannot be, so it is
        # refused with the size that would fit.
        # ------------------------------------------------------------
        def na_scale__check_limits(factors)
            frame  = @na_sc_frame
            limits = na_scale__stretch_limits

            factors.each do |axis, factor|
                limit = limits[axis]
                next unless limit

                wanted = frame[:world_lengths][NA_SCALE_AXIS_INDEX[axis]] * factor.to_f
                next unless wanted < limit - 0.0001

                raise ArgumentError, "the #{axis.to_s.upcase} planes only leave room to shrink to " \
                                     "#{Na__InsertPrimatives.Na__DrawnFormat__Mm(limit)} mm — move a plane or add one"
            end
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | SketchUp Tool API — Draw
        # -----------------------------------------------------------------------------

        # DRAW | The Object's Box, Its Grips, Dimensions and Planes, or the Drag
        # ------------------------------------------------------------
        def draw(view)
            na_scale__refresh_frame
            @na_ip.draw(view) if na_drawn__inference_visible? && @na_ip && @na_ip.valid?

            na_scale__draw_hover_object(view)

            frame = @na_sc_frame
            return unless frame

            # Typing outranks the mouse: an entry that already reads as a
            # size is previewed exactly as Enter will apply it, drag or not.
            typed = na_scale__typed_state
            texts = typed ? typed[:texts] : {}

            if typed && typed[:field]
                na_scale__draw_change(view, typed[:field], texts, nil)
                return
            end

            if @na_sc_drag && @na_sc_drag[:field]
                na_scale__draw_change(view, @na_sc_drag[:field], texts, @na_sc_drag)
                return
            end

            Na__InsertPrimatives.Na__ScalePreview__DrawBoxOutline(
                view, Na__InsertPrimatives.Na__ScaleFrame__BoxEdges(frame), NA_SCALE_BOX_COLOR, 2
            )

            na_scale__draw_planes(view) if na_scale__planes_on? || na_scale__ctrl_offer?
            na_scale__layout_dims(view, nil, nil, nil, [], texts)
            na_scale__draw_dims(view)
            na_scale__draw_grips(view)                                        # <-- Over the dimensions: the grips take the click where the two meet
            na_scale__draw_bar(view)
            na_scale__draw_plane_hint(view)
            na_scale__draw_grip_label(view)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Another Object Under the Cursor, Offered in Blue
        # ------------------------------------------------------------
        def na_scale__draw_hover_object(view)
            object = @na_sc_hover_object
            return unless object && object[:instance] && object[:instance].valid?

            quads = Na__InsertPrimatives.Na__DeepPick__InstanceBoxQuads(object[:instance], object[:transformation])
            return unless quads

            Na__InsertPrimatives.Na__DrawnPreview__DrawTargetHighlight(
                view, quads[0], quads[1], true, [object[:name].to_s, 'click to scale it']
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Grips: Far Side, Near Side, Then the Hovered One on Top
        # ------------------------------------------------------------
        def na_scale__draw_grips(view)
            hover   = @na_sc_hover && @na_sc_hover[:kind] == :grip ? @na_sc_hover[:grip] : nil
            entries = na_scale__visible_grips(view).sort_by { |entry| entry[:front] ? 1 : 0 }
            hot     = nil

            entries.each do |entry|
                if hover && entry[:grip][:codes] == hover[:codes]
                    hot = entry
                elsif entry[:front]
                    Na__InsertPrimatives.Na__ScalePreview__DrawGrip(view, entry[:screen], NA_SCALE_GRIP_PIXELS, NA_SCALE_GRIP_COLOR)
                else
                    Na__InsertPrimatives.Na__ScalePreview__DrawGrip(view, entry[:screen], NA_SCALE_GRIP_BACK_PIXELS, NA_SCALE_GRIP_BACK_COLOR, true)
                end
            end

            Na__InsertPrimatives.Na__ScalePreview__DrawGrip(view, hot[:screen], NA_SCALE_GRIP_HOT_PIXELS, NA_SCALE_GRIP_HOT_COLOR) if hot
        end
        # ---------------------------------------------------------------

        # FUNCTION | What the Hovered Grip Will Do
        # ------------------------------------------------------------
        def na_scale__draw_grip_label(view)
            hover = @na_sc_hover
            return unless hover && hover[:kind] == :grip

            Na__InsertPrimatives.Na__ScalePreview__DrawWorldLabel(view, hover[:grip][:world], na_scale__grip_lines(hover[:grip]))
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Grip Described in a Line or Two
        # ------------------------------------------------------------
        def na_scale__grip_lines(grip)
            uniform = na_scale__uniform?(grip)
            names   = grip[:axes].map { |axis| axis.to_s.upcase }.join(' + ')
            centre  = na_scale__centre_on? ? ' about centre' : ''
            lines   = [uniform ? "Scale uniform#{centre}" : "Scale #{names}#{centre}"]

            stretching = grip[:axes].select do |axis|
                na_scale__planes_on? &&
                    !Na__InsertPrimatives.Na__ScalePlanes__Inside(@na_sc_frame, axis, (@na_sc_planes || {})[axis]).empty?
            end
            lines << "stretches #{stretching.map { |axis| axis.to_s.upcase }.join(' + ')} at the planes" unless stretching.empty?
            lines << (uniform ? 'SHIFT: one axis at a time' : 'SHIFT: uniform') if grip[:axes].length > 1 || uniform
            lines
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Change on Its Way: Old Box Faded, New Box in Amber, Ghost, Planes, Sizes
        # ------------------------------------------------------------
        # The same picture for a grip being dragged and for a size being
        # typed. texts carries what is typed, shown in the dimensions it
        # goes to; drag, when there is one, puts the grip and its label at
        # the grip's new place, and without one the label sits on the box.
        # ------------------------------------------------------------
        def na_scale__draw_change(view, field, texts, drag)
            frame      = @na_sc_frame
            mins, maxs = Na__InsertPrimatives.Na__ScaleField__Box(field, frame)
            lengths    = (0..2).map { |n| (maxs[n] - mins[n]) * frame[:scales][n] }
            live       = NA_SCALE_AXES.reject { |axis| field[axis][:mode] == :fixed }

            Na__InsertPrimatives.Na__ScalePreview__DrawBoxOutline(
                view, Na__InsertPrimatives.Na__ScaleFrame__BoxEdges(frame), NA_SCALE_OLD_BOX_COLOR, 1, '-'
            )

            near, far = Na__InsertPrimatives.Na__ScaleFrame__BoxQuads(frame, mins, maxs)
            drawn     = Na__InsertPrimatives.Na__DrawnPreview__DrawFilledBoxOnTop(view, near, far, NA_SCALE_NEW_FILL_COLOR, NA_SCALE_NEW_BORDER_COLOR)
            Na__InsertPrimatives.Na__DrawnPreview__DrawFilledBox(view, near, far, NA_SCALE_NEW_FILL_COLOR, NA_SCALE_NEW_BORDER_COLOR) unless drawn

            na_scale__ghost
            na_scale__draw_ghost(view, field)
            na_scale__draw_planes(view, field) if na_scale__planes_on?

            na_scale__layout_dims(view, mins, maxs, lengths, live, texts || {})
            na_scale__draw_dims(view)

            if drag
                moved  = Na__InsertPrimatives.Na__ScaleField__MapPoint(field, drag[:grip][:local]).transform(frame[:world])
                screen = Na__InsertPrimatives.Na__ScalePreview__Screen(view, moved)
                Na__InsertPrimatives.Na__ScalePreview__DrawGrip(view, screen, NA_SCALE_GRIP_HOT_PIXELS, NA_SCALE_GRIP_HOT_COLOR) if screen
                Na__InsertPrimatives.Na__ScalePreview__DrawWorldLabel(view, moved, na_scale__drag_lines)
            else
                corner = Geom::Point3d.new(maxs[0], mins[1], maxs[2]).transform(frame[:world])
                Na__InsertPrimatives.Na__ScalePreview__DrawWorldLabel(view, corner, na_scale__change_lines(field, lengths) + ['Enter applies it, ESC cancels'])
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Field Described: Each Axis's New Size, and How It Stretches
        # ------------------------------------------------------------
        def na_scale__change_lines(field, lengths)
            frame = @na_sc_frame
            lines = []

            NA_SCALE_AXES.each_with_index do |axis, n|
                spec = field[axis]
                next if spec[:mode] == :fixed

                before = Na__InsertPrimatives.Na__DrawnFormat__Mm(frame[:world_lengths][n])
                after  = Na__InsertPrimatives.Na__DrawnFormat__Mm(lengths[n])
                change = after - before
                line   = "#{axis.to_s.upcase} #{after} mm (#{change >= 0 ? '+' : ''}#{change})"

                if spec[:mode] == :stretch
                    count = spec[:planes].length
                    each  = Na__InsertPrimatives.Na__DrawnFormat__Mm((spec[:delta] / count) * frame[:scales][n])
                    line += " at #{count} plane#{count == 1 ? '' : 's'}, #{each >= 0 ? '+' : ''}#{each} each"
                end

                lines << line
            end

            lines
        end
        # ---------------------------------------------------------------

        # FUNCTION | Every Edge of the Object Where the Change Is Taking It
        # Too many edges to project every frame and the amber box stands in.
        # ------------------------------------------------------------
        def na_scale__draw_ghost(view, field)
            ghost = @na_sc_ghost
            return false unless ghost && ghost[:drawable]

            world  = @na_sc_frame[:world]
            points = ghost[:points].map { |point| Na__InsertPrimatives.Na__ScaleField__MapPoint(field, point).transform(world) }

            Na__InsertPrimatives.Na__ScalePreview__DrawGhost(view, points, ghost[:segments])
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Label Beside the Grip While It Is Dragged
        # Empty until the mouse has really moved: a grip only pressed has no
        # field yet, and nothing to say about one.
        # ------------------------------------------------------------
        def na_scale__drag_lines
            drag  = @na_sc_drag
            frame = @na_sc_frame
            field = drag ? drag[:field] : nil
            return [] unless field && frame

            lines = []

            drag[:factors].keys.each do |axis|
                n      = NA_SCALE_AXIS_INDEX[axis]
                before = Na__InsertPrimatives.Na__DrawnFormat__Mm(frame[:world_lengths][n])
                after  = Na__InsertPrimatives.Na__DrawnFormat__Mm(drag[:lengths][n])
                change = after - before
                lines << "#{axis.to_s.upcase} #{after} mm (#{change >= 0 ? '+' : ''}#{change})"
            end

            lines = ["Uniform #{format('%.3f', drag[:factors].values.first.to_f)}x — #{lines.join('  ')}"] if drag[:uniform] && !drag[:factors].empty?

            NA_SCALE_AXES.each_with_index do |axis, n|
                spec = field[axis]
                next unless spec && spec[:mode] == :stretch

                count = spec[:planes].length
                each  = Na__InsertPrimatives.Na__DrawnFormat__Mm((spec[:delta] / count) * frame[:scales][n])
                lines << "#{axis.to_s.upcase} stretches at #{count} plane#{count == 1 ? '' : 's'}, #{each >= 0 ? '+' : ''}#{each} each"
            end

            lines << 'about centre' if na_scale__centre_on?
            lines << 'CTRL: snapped to a point' if drag[:how] == 'vertex'
            lines
        end
        # ---------------------------------------------------------------

        # GET EXTENTS | Keep the Box, the Drag and the Planes Inside the Draw Bounds
        # ------------------------------------------------------------
        def getExtents
            bounds = Geom::BoundingBox.new
            frame  = @na_sc_frame

            if frame
                # The planes stand 8% proud of the box: a tenth all round covers them.
                pad  = (0..2).map { |n| (frame[:max][n] - frame[:min][n]) * 0.1 }
                lo   = (0..2).map { |n| frame[:min][n] - pad[n] }
                hi   = (0..2).map { |n| frame[:max][n] + pad[n] }
                Na__InsertPrimatives.Na__ScaleFrame__BoxQuads(frame, lo, hi).flatten.each { |point| bounds.add(point) }

                typed = na_scale__typed_state

                [@na_sc_drag ? @na_sc_drag[:field] : nil, typed ? typed[:field] : nil].compact.each do |field|
                    mins, maxs = Na__InsertPrimatives.Na__ScaleField__Box(field, frame)
                    Na__InsertPrimatives.Na__ScaleFrame__BoxQuads(frame, mins, maxs).flatten.each { |point| bounds.add(point) }
                end
            end

            object = @na_sc_hover_object
            if object && object[:instance] && object[:instance].valid?
                quads = Na__InsertPrimatives.Na__DeepPick__InstanceBoxQuads(object[:instance], object[:transformation])
                quads.flatten.each { |point| bounds.add(point) } if quads
            end

            bounds
        rescue StandardError
            Geom::BoundingBox.new
        end
        # ---------------------------------------------------------------

        # FUNCTION | Never Reached — Deep Scale Draws Everything in draw
        # ------------------------------------------------------------
        def na_drawn__draw_preview(_view)
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Never Reached — There Is No Rectangle Stage
        # ------------------------------------------------------------
        def na_drawn__advance_from_b(_view)
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Shared Stage Completion Places a Held Drag
        # ------------------------------------------------------------
        def na_drawn__advance_from_depth(view)
            na_scale__commit_drag(view)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Status and Measurements Box
        # -----------------------------------------------------------------------------

        # FUNCTION | Show a Result in the Status Line for a Few Seconds
        # ------------------------------------------------------------
        # The composed line is rewritten whenever it changes, which after a
        # commit is at once, so a result written straight to the status bar
        # would be gone before anyone read it. Held here, it is part of the
        # composed line until it has had time to be seen — or until the
        # cursor moves on to something else, which is the newer question.
        # ------------------------------------------------------------
        def na_scale__say(text)
            @na_sc_message       = { :text => text.to_s, :at => Time.now, :hover => na_scale__hover_signature }
            @na_last_status_text = nil
            Sketchup::set_status_text(text.to_s, SB_PROMPT)
        end
        # ---------------------------------------------------------------

        # FUNCTION | What the Cursor Is Over, Reduced to Something Comparable
        # ------------------------------------------------------------
        def na_scale__hover_signature
            hover = @na_sc_hover
            return nil unless hover

            case hover[:kind]
            when :grip   then [:grip, hover[:grip][:codes]]
            when :handle then [:handle, hover[:axis], hover[:index]]
            when :object then [:object, @na_sc_hover_object ? @na_sc_hover_object[:instance].entityID : nil]
            else              [hover[:kind], hover[:axis] || hover[:id]]
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is a Said Result Still the Thing to Show?
        # ------------------------------------------------------------
        def na_scale__message_current?
            message = @na_sc_message
            return false unless message
            return false unless (Time.now - message[:at]).to_f < NA_SCALE_MESSAGE_SECS

            message[:hover] == na_scale__hover_signature
        end
        # ---------------------------------------------------------------

        # FUNCTION | Compose the Whole Status Line
        # ------------------------------------------------------------
        def na_drawn__update_status_text
            composed = "#{na_drawn__tool_title} | #{na_drawn__status_detail} | #{na_scale__mode_summary} | #{na_scale__key_hint}"
            return if composed == @na_last_status_text

            Sketchup::set_status_text(composed, SB_PROMPT)
            @na_last_status_text = composed
        end
        # ---------------------------------------------------------------

        # FUNCTION | Middle Section of the Status Bar Line
        # ------------------------------------------------------------
        def na_drawn__status_detail
            typing = na_scale__typing_detail
            return typing if typing
            return @na_sc_message[:text] if na_scale__message_current?

            frame = @na_sc_frame
            hover = @na_sc_hover

            unless frame
                return "#{@na_sc_hover_object[:name]} — click to scale it" if @na_sc_hover_object
                return 'Loose geometry — click to scale it and everything connected to it' if hover && hover[:kind] == :loose

                return "Select what to scale, or hover a group, a component or loose geometry and click it#{na_drawn__focus_hint}"
            end

            if @na_sc_plane_drag
                drag      = @na_sc_plane_drag
                value     = drag[:planes][drag[:axis]][drag[:index]]
                low, high = Na__InsertPrimatives.Na__ScalePlanes__DistancesMm(frame, drag[:axis], value)
                return "#{drag[:axis].to_s.upcase} plane #{low} | #{high} mm — release to set it"
            end

            if @na_sc_drag
                lines = na_scale__drag_lines
                return lines.empty? ? 'Drag the grip — release or click to place' : "#{lines.join(' · ')} — release or click to place"
            end

            label = Na__InsertPrimatives.Na__ScaleFrame__Label(frame)

            case hover && hover[:kind]
            when :grip   then "#{na_scale__grip_lines(hover[:grip]).first} — drag to scale #{label}"
            when :dim    then "Click to type the #{hover[:axis].to_s.upcase} size of #{label}"
            when :bar    then (@na_sc_bar.find { |button| button[:id] == hover[:id] } || {})[:tip].to_s
            when :line
                axis = hover[:axis].to_s.upcase
                one  = "#{axis == 'X' ? 'an' : 'a'} #{axis}"
                hover[:ctrl] ? "CTRL: click to add #{one} stretch plane here — ARROWS pick the axis, SHIFT a mirrored pair" :
                               "Click to add #{one} stretch plane here and drag it into place — SHIFT for a mirrored pair"
            when :handle then "#{hover[:axis].to_s.upcase} plane — drag to move it, DEL or double-click to remove it"
            when :object then "#{@na_sc_hover_object[:name]} — click to scale it instead"
            when :loose  then 'Loose geometry — click to scale it and everything connected to it instead'
            else
                typing = @na_sc_focus == :dimension && @na_sc_active_dim ? " — typing sets #{@na_sc_active_dim.to_s.upcase}" : ''
                "#{label} #{na_scale__sizes_text(frame[:world_lengths])} mm — drag a grip, or click a dimension and type#{typing}"
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Status Line While an Entry Is Being Typed, or nil
        # ------------------------------------------------------------
        def na_scale__typing_detail
            typed = na_scale__typed_state
            return nil unless typed

            text = typed[:text]
            return "Typing #{text} — the plane's distance from the low end; Enter sets it, ESC cancels" if na_scale__typing_plane?
            return "Typing #{text} — Enter applies it, ESC cancels" unless @na_sc_frame

            if typed[:field]
                frame      = @na_sc_frame
                mins, maxs = Na__InsertPrimatives.Na__ScaleField__Box(typed[:field], frame)
                lengths    = (0..2).map { |n| (maxs[n] - mins[n]) * frame[:scales][n] }
                return "Typing #{text} → #{na_scale__change_lines(typed[:field], lengths).join(' · ')} — Enter applies it, ESC cancels"
            end

            limit = typed[:note].to_s.include?('room to shrink') ? " — #{typed[:note]}" : ''
            "Typing #{text}#{limit} — Enter applies it, ESC cancels"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Never Write Over What Is Being Typed
        # ------------------------------------------------------------
        # Writing the box while the user types into it replaces their text,
        # so the live value waits until the entry is done or abandoned.
        # ------------------------------------------------------------
        def na_drawn__refresh_vcb
            return false if na_scale__typing?

            super
        end
        # ---------------------------------------------------------------

        # FUNCTION | Status Fragment for the Switches in Force
        # ------------------------------------------------------------
        def na_scale__mode_summary
            handles =
                if @na_axis_lock
                    "Handles: #{@na_axis_lock.to_s.upcase} only (DOWN releases)"
                else
                    Na__InsertPrimatives.Na__ToolOptions__CaptionFor(NA_SCALE_OPTION_HANDLES)
                end

            parts = [handles]
            parts << 'STRETCH PLANES' if na_scale__planes_on?
            parts << 'ABOUT CENTRE'   if na_scale__centre_on?
            parts <<
                if @na_ctrl_held && @na_sc_drag      then 'CTRL point snap'
                elsif @na_ctrl_held && @na_sc_frame  then 'CTRL add a plane'
                else                                      "Grid #{Na__InsertPrimatives.Na__DrawnSettings__GridStepLabel}"
                end
            parts.join(' | ')
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Keys That Matter for What Is Happening
        # ------------------------------------------------------------
        def na_scale__key_hint
            kind = @na_sc_hover ? @na_sc_hover[:kind] : nil

            return 'SHIFT mirror  type a distance  ESC cancel' if @na_sc_plane_drag
            return 'SHIFT uniform  CTRL point snap  TAB about centre  type a size  ESC cancel' if @na_sc_drag
            return 'click a group or component  ESC exit' unless @na_sc_frame
            return 'click adds a plane  SHIFT mirrored pair  ARROWS axis  ESC let go' if kind == :line
            return 'drag to move  SHIFT with its mirror  DEL remove  ESC let go' if kind == :handle

            'CTRL add a plane  SHIFT+TAB planes  TAB centre  ARROWS one axis  SHIFT uniform  dbl-click inside  ESC let go'
        end
        # ---------------------------------------------------------------

        # FUNCTION | Measurements Box Label and Live Value
        # ------------------------------------------------------------
        def na_drawn__vcb_label_and_value
            frame = @na_sc_frame
            return ['Size X,Y,Z', ''] unless frame

            plane = @na_sc_plane_drag ? { :axis => @na_sc_plane_drag[:axis], :u => @na_sc_plane_drag[:planes][@na_sc_plane_drag[:axis]][@na_sc_plane_drag[:index]] } :
                                        (@na_sc_focus == :plane ? @na_sc_active_plane : nil)

            if plane
                low, _high = Na__InsertPrimatives.Na__ScalePlanes__DistancesMm(frame, plane[:axis], plane[:u])
                return ["Plane #{plane[:axis].to_s.upcase} from low end", low.to_s]
            end

            if @na_sc_drag && @na_sc_drag[:moved] && @na_sc_drag[:field]
                drag = @na_sc_drag
                axes = drag[:uniform] ? NA_SCALE_AXES.select.with_index { |_axis, n| frame[:usable][n] } : drag[:grip][:axes]
                text = axes.map { |axis| Na__InsertPrimatives.Na__DrawnFormat__Mm(drag[:lengths][NA_SCALE_AXIS_INDEX[axis]]).to_s }.join(',')
                return [axes.length == 1 ? "Length #{axes.first.to_s.upcase}" : "Size #{axes.map { |axis| axis.to_s.upcase }.join(',')}", text]
            end

            if @na_sc_active_dim
                n = NA_SCALE_AXIS_INDEX[@na_sc_active_dim]
                return ["Length #{@na_sc_active_dim.to_s.upcase}", Na__InsertPrimatives.Na__DrawnFormat__Mm(frame[:world_lengths][n]).to_s]
            end

            ['Size X,Y,Z', frame[:world_lengths].map { |length| Na__InsertPrimatives.Na__DrawnFormat__Mm(length).to_s }.join(',')]
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnScaleTool class

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Public Entry Point
    # -----------------------------------------------------------------------------

    # FUNCTION | Activate the Deep Scale Tool (Hotkey Entry Point)
    # ------------------------------------------------------------
    def self.Na__InsertPrimatives__DeepScale
        Na__InsertPrimatives.Na__ModeSwitch__ActivateDrawnScaleTool
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP SCALE TOOL
# =============================================================================
