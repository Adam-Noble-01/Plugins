# =============================================================================
# NA INSERT PRIMATIVES - DRAWN PRIMITIVES SHARED TOOL BEHAVIOUR
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnToolShared__.rb
# NAMESPACE  : Na__InsertPrimatives::DrawnToolShared
#              Na__InsertPrimatives::PrimitiveModeSwitching
# AUTHOR     : Noble Architecture
# PURPOSE    : Everything the Drawn Plane and Drawn Volume tools have in common —
#              drag state machine, plane inference, VCB routing, previews,
#              right-click popup and tool-to-tool mode switching
# CREATED    : 2026
#
# DESCRIPTION:
# - DrawnToolShared is mixed into both drag tools. Its methods have full access
#   to the host instance variables, all of which are created by
#   na_drawn__init_shared_state.
# - PrimitiveModeSwitching is mixed into *every* tool in the plugin, including
#   the original PrimitiveCubeTool, so the right-click popup can switch between
#   all four primitive modes from whichever tool happens to be running.
#
# DRAG STATE MACHINE:
#   :idle          waiting for the anchor click
#   :picking_b     anchor placed, rectangle following the cursor
#   :picking_depth rectangle fixed, extrusion following the cursor (volume only)
#
# Both press-drag-release and click-move-click are supported, matching the
# native Rectangle tool: a press that travels more than NA_DRAWN_DRAG_MIN_PX
# before release completes the stage, anything shorter is treated as a click and
# leaves the stage open for a second click.
#
# SUBCLASS CONTRACT — each host tool must define:
#   na_drawn__tool_title            String shown in the status bar
#   na_drawn__mode_key              :drawn_plane or :drawn_volume
#   na_drawn__activation_hints      Array<String> printed to the console
#   na_drawn__advance_from_b(view)  Called when the base rectangle is settled
#   na_drawn__handle_vcb_text(t, v) Called with a non-empty measurements entry
#   na_drawn__draw_preview(view)    Draws the shaded preview for the live state
#   na_drawn__status_detail         Middle section of the status bar text
#   na_drawn__vcb_label_and_value   [label, value] for the measurements box
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__InsertPrimatives__DrawnGridSnap__'
require_relative 'Na__InsertPrimatives__DrawnVcbArithmetic__'
require_relative 'Na__InsertPrimatives__DrawnPreviewGraphics__'
require_relative 'Na__InsertPrimatives__DrawnGeometry__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Tool Activation Helpers (Module Level)
    # -----------------------------------------------------------------------------

    # FUNCTION | Activate the Original Cube / Plane Placement Tool
    # ------------------------------------------------------------
    def self.Na__ModeSwitch__ActivateCubeTool(sub_mode = :cube)
        model = Sketchup.active_model
        return nil unless model

        tool = PrimitiveCubeTool.new
        model.select_tool(tool)
        tool.Na__PrimitiveMode__SetPlaneMode() if sub_mode == :plane
        tool
    end
    # ---------------------------------------------------------------

    # FUNCTION | Activate the Click-and-Drag Drawn Plane Tool
    # ------------------------------------------------------------
    def self.Na__ModeSwitch__ActivateDrawnPlaneTool
        model = Sketchup.active_model
        return nil unless model

        tool = DrawnPlaneTool.new
        model.select_tool(tool)
        tool
    end
    # ---------------------------------------------------------------

    # FUNCTION | Activate the Click-and-Drag Drawn Volume Tool
    # ------------------------------------------------------------
    def self.Na__ModeSwitch__ActivateDrawnVolumeTool
        model = Sketchup.active_model
        return nil unless model

        tool = DrawnVolumeTool.new
        model.select_tool(tool)
        tool
    end
    # ---------------------------------------------------------------

    # FUNCTION | Activate the Click-and-Drag Drawn Cylinder Tool
    # ------------------------------------------------------------
    def self.Na__ModeSwitch__ActivateDrawnCylinderTool
        model = Sketchup.active_model
        return nil unless model

        tool = DrawnCylinderTool.new
        model.select_tool(tool)
        tool
    end
    # ---------------------------------------------------------------

    # FUNCTION | Activate the Deep Push/Pull Tool the Camera Calls For
    # ------------------------------------------------------------
    # ONE entry point, two tools. The menu item, the keyboard shortcut and the
    # right-click popup all arrive here, so asking the camera in this one place
    # is what makes the 2D/3D split invisible to the user — there is no second
    # button to find and no second shortcut to remember.
    #
    # A perspective camera gets DrawnPushPullTool, which is untouched and still
    # does all the work. A parallel camera gets DrawnPushPull2dTool, its
    # subclass, which inverts the pick so an edge grabs the wall standing behind
    # it. The 2D module loads after this file, so the class is looked up at call
    # time and the 3D tool is the fallback if it is missing.
    # ------------------------------------------------------------
    def self.Na__ModeSwitch__ActivateDrawnPushPullTool
        model = Sketchup.active_model
        return nil unless model

        tool =
            if defined?(Na__InsertPrimatives::DrawnPushPull2dTool)
                Na__InsertPrimatives.Na__PushPull2d__NewToolForCamera(model)
            else
                DrawnPushPullTool.new
            end

        model.select_tool(tool)
        tool
    end
    # ---------------------------------------------------------------

    # FUNCTION | Activate the Deep Chamfer Tool
    # ------------------------------------------------------------
    def self.Na__ModeSwitch__ActivateDrawnChamferTool
        model = Sketchup.active_model
        return nil unless model

        tool = DrawnChamferTool.new
        model.select_tool(tool)
        tool
    end
    # ---------------------------------------------------------------

    # FUNCTION | Activate the Click-and-Drag Pitched Roof Tool
    # ------------------------------------------------------------
    def self.Na__ModeSwitch__ActivateDrawnPitchedRoofTool
        model = Sketchup.active_model
        return nil unless model

        tool = DrawnPitchedRoofTool.new
        model.select_tool(tool)
        tool
    end
    # ---------------------------------------------------------------

    # FUNCTION | Activate the Click-and-Drag Hipped Roof Tool
    # ------------------------------------------------------------
    def self.Na__ModeSwitch__ActivateDrawnHippedRoofTool
        model = Sketchup.active_model
        return nil unless model

        tool = DrawnHippedRoofTool.new
        model.select_tool(tool)
        tool
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # =============================================================================
    # MODULE | Primitive Mode Switching — Mixed Into Every Tool In The Plugin
    # =============================================================================

    module PrimitiveModeSwitching

        # FUNCTION | Switch to the Click-and-Drag Drawn Plane Tool
        # ------------------------------------------------------------
        def Na__DrawnMode__SetDrawnPlaneMode
            Na__InsertPrimatives.Na__ModeSwitch__ActivateDrawnPlaneTool
        end
        # ---------------------------------------------------------------

        # FUNCTION | Switch to the Click-and-Drag Drawn Volume Tool
        # ------------------------------------------------------------
        def Na__DrawnMode__SetDrawnVolumeMode
            Na__InsertPrimatives.Na__ModeSwitch__ActivateDrawnVolumeTool
        end
        # ---------------------------------------------------------------

        # FUNCTION | Switch to the Click-and-Drag Drawn Cylinder Tool
        # ------------------------------------------------------------
        def Na__DrawnMode__SetDrawnCylinderMode
            Na__InsertPrimatives.Na__ModeSwitch__ActivateDrawnCylinderTool
        end
        # ---------------------------------------------------------------

        # FUNCTION | Switch to the Click-and-Drag Pitched Roof Tool
        # ------------------------------------------------------------
        def Na__DrawnMode__SetPitchedRoofMode
            Na__InsertPrimatives.Na__ModeSwitch__ActivateDrawnPitchedRoofTool
        end
        # ---------------------------------------------------------------

        # FUNCTION | Switch to the Click-and-Drag Hipped Roof Tool
        # ------------------------------------------------------------
        def Na__DrawnMode__SetHippedRoofMode
            Na__InsertPrimatives.Na__ModeSwitch__ActivateDrawnHippedRoofTool
        end
        # ---------------------------------------------------------------

        # FUNCTION | Switch to the Deep Push/Pull Tool
        # ------------------------------------------------------------
        def Na__DrawnMode__SetPushPullMode
            Na__InsertPrimatives.Na__ModeSwitch__ActivateDrawnPushPullTool
        end
        # ---------------------------------------------------------------

        # FUNCTION | Switch to the Deep Chamfer Tool
        # ------------------------------------------------------------
        def Na__DrawnMode__SetChamferMode
            Na__InsertPrimatives.Na__ModeSwitch__ActivateDrawnChamferTool
        end
        # ---------------------------------------------------------------

        # FUNCTION | Advance the Circle Segment Count to the Next Value
        # ------------------------------------------------------------
        def Na__DrawnMode__CycleCircleSegments
            count = Na__InsertPrimatives.Na__DrawnSettings__CycleCircleSegments

            view = Sketchup.active_model ? Sketchup.active_model.active_view : nil
            view.invalidate if view

            Sketchup::set_status_text("Circle segments: #{count}", SB_PROMPT)
            count
        end
        # ---------------------------------------------------------------

        # FUNCTION | Current Circle Segment Count for Menu Display
        # ------------------------------------------------------------
        def Na__DrawnMode__CircleSegmentsLabel
            Na__InsertPrimatives.Na__DrawnSettings__CircleSegments.to_s
        end
        # ---------------------------------------------------------------

        # FUNCTION | Advance the Shared Snap Grid to the Next Step
        # ------------------------------------------------------------
        def Na__DrawnMode__CycleGridStep
            Na__InsertPrimatives.Na__DrawnSettings__CycleGridStepMm
            label = Na__InsertPrimatives.Na__DrawnSettings__GridStepLabel

            view = Sketchup.active_model ? Sketchup.active_model.active_view : nil
            view.invalidate if view

            Sketchup::set_status_text("Snap grid: #{label}", SB_PROMPT)
            label
        end
        # ---------------------------------------------------------------

        # FUNCTION | Current Snap Grid Label for Menu Display
        # ------------------------------------------------------------
        def Na__DrawnMode__GridStepLabel
            Na__InsertPrimatives.Na__DrawnSettings__GridStepLabel
        end
        # ---------------------------------------------------------------

    end # End PrimitiveModeSwitching module


    # =============================================================================
    # MODULE | Drawn Tool Shared Behaviour
    # =============================================================================

    module DrawnToolShared

        include Na__InsertPrimatives::PrimitiveModeSwitching

        # -----------------------------------------------------------------------------
        # REGION | Interaction Constants
        # -----------------------------------------------------------------------------

        NA_DRAWN_TAB_KEY          = 9                                          # <-- No VK_TAB constant in the SketchUp API
        NA_DRAWN_BACKSPACE_KEY    = 8

        # Windows mouse-flag bit for Ctrl, as delivered in the flags argument of
        # the mouse callbacks. Read alongside COPY_MODIFIER_KEY in the key
        # callbacks: the flags are authoritative during a drag, the key events
        # catch a press or release that happens while the mouse is still.
        NA_DRAWN_MK_CONTROL       = 8

        # SHIFT, the same way, and it can be read the same way for a reason:
        # MK_SHIFT is a genuine Windows mouse-message bit, so unlike ALT it is
        # always there in the flags a tool is handed. That is exactly why the
        # slope modifier is SHIFT — ALT had to be tracked through key events
        # alone, and a key-up eaten by the Windows menu bar left it stuck.
        #
        # Taken from SketchUp's own constants where they are there to be taken,
        # since the numbers differ by platform. The literals are the Windows
        # values, and SHIFT is SHIFT on both.
        NA_DRAWN_MK_SHIFT         = defined?(CONSTRAIN_MODIFIER_MASK) ? CONSTRAIN_MODIFIER_MASK : 4
        NA_DRAWN_SHIFT_KEY        = defined?(CONSTRAIN_MODIFIER_KEY)  ? CONSTRAIN_MODIFIER_KEY  : 16

        NA_DRAWN_SLOT_KEYS        = [:u, :v, :d].freeze
        NA_DRAWN_DRAG_MIN_PX      = 6.0                                        # <-- Below this a press-release is a click
        NA_DRAWN_REVISE_DISARM_PX = 8.0                                        # <-- Mouse travel that ends revise-last mode
        NA_DRAWN_PLANE_LOCK_CYCLE = [:auto, :xy, :xz, :yz].freeze

        # Digits, numpad and the main-row = + , - . keys. Seeing one of these
        # means a measurements-box entry is under way, which is what arms the
        # Backspace guard so a typo fix is not swallowed as a step-back.
        NA_DRAWN_VCB_ENTRY_KEYS   = ((48..57).to_a + (96..111).to_a + [187, 188, 189, 190]).freeze

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | State Initialisation
        # -----------------------------------------------------------------------------

        # FUNCTION | Create Every Instance Variable the Mixin Relies On
        # ------------------------------------------------------------
        def na_drawn__init_shared_state
            @na_ip                = Sketchup::InputPoint.new
            @na_ip_origin         = Sketchup::InputPoint.new

            @na_state             = :idle
            @na_point_a           = nil
            @na_cursor_raw        = nil
            @na_cursor_snapped    = nil

            @na_plane_lock        = :auto
            @na_plane_key         = :xy

            @na_size_u            = 0.0
            @na_size_v            = 0.0
            @na_size_d            = 0.0
            @na_sign_u            = 1.0
            @na_sign_v            = 1.0
            @na_sign_d            = 1.0

            @na_drag_press_active = false
            @na_press_x           = 0
            @na_press_y           = 0
            @na_last_mouse_x      = 0
            @na_last_mouse_y      = 0

            @na_vcb_typing_active = false
            @na_last_vcb_text     = nil
            @na_last_vcb_label    = nil
            @na_last_status_text  = nil

            @na_revise_armed      = false
            @na_revise_anchor_x   = nil
            @na_revise_anchor_y   = nil
            @na_last_record       = nil

            @na_tab_held          = false
            @na_ctrl_held         = false
            @na_shift_held        = false                                     # <-- Only the push tools read it; see Na__SlopePush__
            @na_axis_lock         = nil                                       # <-- nil / :x / :y / :z from the arrow keys
            @na_locked_slots      = {}                                        # <-- :u / :v / :d => true once typed
            @na_lock_order        = []                                        # <-- Newest last, so BKSP can peel them off
            @na_exit_scheduled    = false
            @na_popup_scheduled   = false
            @na_context_x         = 0
            @na_context_y         = 0
        end
        # ---------------------------------------------------------------

        # FUNCTION | Return to the Waiting-For-Anchor State
        # Sizes are deliberately left alone so the measurements box keeps showing
        # the last shape drawn, which is the base a relative entry acts on.
        # ------------------------------------------------------------
        def na_drawn__reset_pick_state
            @na_state             = :idle
            @na_point_a           = nil
            @na_drag_press_active = false
            na_drawn__clear_locks
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Typed Dimension Locks
        # -----------------------------------------------------------------------------

        # FUNCTION | Pin a Dimension So the Drag Stops Moving It
        # ------------------------------------------------------------
        def na_drawn__lock_slot(slot)
            return unless NA_DRAWN_SLOT_KEYS.include?(slot)

            @na_lock_order.delete(slot)
            @na_lock_order << slot
            @na_locked_slots[slot] = true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is This Dimension Pinned?
        # ------------------------------------------------------------
        def na_drawn__locked?(slot)
            @na_locked_slots[slot] == true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Release Every Pinned Dimension
        # ------------------------------------------------------------
        def na_drawn__clear_locks
            @na_locked_slots = {}
            @na_lock_order   = []
        end
        # ---------------------------------------------------------------

        # FUNCTION | Release the Most Recently Pinned Dimension
        # Returns the slot released, or nil when nothing was pinned.
        # ------------------------------------------------------------
        def na_drawn__release_last_lock
            slot = @na_lock_order.pop
            return nil unless slot

            @na_locked_slots.delete(slot)
            slot
        end
        # ---------------------------------------------------------------

        # FUNCTION | Are All of a Stage's Dimensions Pinned?
        # ------------------------------------------------------------
        def na_drawn__all_locked?(slots)
            slots.all? { |slot| na_drawn__locked?(slot) }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Index of the First Dimension Still Following the Drag
        # ------------------------------------------------------------
        def na_drawn__first_unlocked_index(slots)
            slots.each_with_index do |slot, index|
                return index unless na_drawn__locked?(slot)
            end

            0                                                                 # <-- Everything pinned: fall back to the first
        end
        # ---------------------------------------------------------------

        # FUNCTION | Point a Bare Single Value at the Next Unpinned Dimension
        # Typing 350 then 1610 should pin width then height, so a comma-free
        # entry addresses the first axis still on the drag rather than always
        # slot zero — otherwise the second value would overwrite the first pin.
        # An entry containing a comma stays strictly positional, which is what
        # makes ",1610" and "350," able to name a specific axis.
        # ------------------------------------------------------------
        def na_drawn__align_single_token(tokens, slots)
            return tokens unless tokens.length == 1

            target = na_drawn__first_unlocked_index(slots)
            return tokens if target.zero?

            Array.new(target, nil) + [tokens[0]]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Short Status Fragment Naming the Pinned Dimensions
        # ------------------------------------------------------------
        def na_drawn__lock_summary
            pinned = NA_DRAWN_SLOT_KEYS.select { |slot| na_drawn__locked?(slot) }
            return '' if pinned.empty?

            " | LOCKED #{pinned.map { |slot| slot.to_s.upcase }.join('+')} (BKSP to release)"
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | SketchUp Tool API — Life Cycle
        # -----------------------------------------------------------------------------

        # ACTIVATE | Reset State and Announce the Tool
        # ------------------------------------------------------------
        def activate
            @na_ctrl_held  = false
            @na_shift_held = false
            na_drawn__reset_pick_state
            na_drawn__disarm_revise
            na_drawn__print_activation_banner
            na_drawn__update_status_text
            na_drawn__refresh_vcb

            model = Sketchup.active_model
            model.active_view.invalidate if model
        end
        # ---------------------------------------------------------------

        # DEACTIVATE | Clear Overlays and the Measurements Box
        # ------------------------------------------------------------
        def deactivate(view)
            Na__InsertPrimatives.Na__RightClickPopup__CloseMenu()
            Sketchup::set_status_text('', SB_VCB_LABEL)
            Sketchup::set_status_text('', SB_VCB_VALUE)
            view.invalidate if view
        end
        # ---------------------------------------------------------------

        # RESUME | Restore Status Text After Another Tool Interrupted
        # ------------------------------------------------------------
        def resume(view)
            @na_vcb_typing_active = false
            @na_ctrl_held         = false                                     # <-- A key-up missed while away must not stick
            @na_shift_held        = false                                     # <-- Same again: a modifier released while away must not stick
            @na_last_vcb_text     = nil
            @na_last_vcb_label    = nil
            @na_last_status_text  = nil
            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
        end
        # ---------------------------------------------------------------

        # SUSPEND | Redraw Without Our Overlay
        # ------------------------------------------------------------
        def suspend(view)
            view.invalidate if view
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | SketchUp Tool API — Mouse
        # -----------------------------------------------------------------------------

        # ON MOUSE MOVE | Track the Cursor and Resize the Live Preview
        # ------------------------------------------------------------
        def onMouseMove(flags, x, y, view)
            na_drawn__sync_modifier(flags)
            na_drawn__disarm_revise_if_moved(x, y)
            na_drawn__update_cursor(view, x, y)
            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate
        end
        # ---------------------------------------------------------------

        # ON LEFT BUTTON DOWN | Advance the Drag State Machine
        # ------------------------------------------------------------
        def onLButtonDown(flags, x, y, view)
            @na_vcb_typing_active = false                                     # <-- A click abandons any half-typed entry
            na_drawn__sync_modifier(flags)

            case @na_state
            when :idle
                @na_ip.pick(view, x, y)
                picked = @na_ip.position
                return unless picked

                na_drawn__clear_locks                                         # <-- A fresh drag starts with nothing pinned
                @na_point_a = na_drawn__snap_point(picked)
                @na_ip_origin.copy!(@na_ip)

                @na_state             = :picking_b
                @na_plane_key         = @na_plane_lock == :auto ? @na_plane_key : @na_plane_lock
                @na_size_u            = 0.0
                @na_size_v            = 0.0
                @na_size_d            = 0.0
                @na_drag_press_active = true
                @na_press_x           = x
                @na_press_y           = y

                na_drawn__disarm_revise

            when :picking_b
                @na_drag_press_active = false
                na_drawn__update_cursor(view, x, y)
                na_drawn__advance_from_b(view)

            when :picking_depth
                @na_drag_press_active = false
                na_drawn__update_cursor(view, x, y)
                na_drawn__advance_from_depth(view)
            end

            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate
        end
        # ---------------------------------------------------------------

        # ON LEFT BUTTON UP | Complete a Press-Drag-Release Gesture
        # A release that barely moved is treated as a click, leaving the stage
        # open so click-move-click keeps working exactly like the native tools.
        # ------------------------------------------------------------
        def onLButtonUp(flags, x, y, view)
            na_drawn__sync_modifier(flags)
            was_pressed           = @na_drag_press_active
            @na_drag_press_active = false

            return unless was_pressed
            return unless @na_state == :picking_b

            travelled_px = (x.to_f - @na_press_x.to_f).abs + (y.to_f - @na_press_y.to_f).abs
            return if travelled_px < NA_DRAWN_DRAG_MIN_PX

            na_drawn__update_cursor(view, x, y)
            return unless na_drawn__rectangle_valid?

            na_drawn__advance_from_b(view)
            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate
        end
        # ---------------------------------------------------------------

        # ON RIGHT BUTTON DOWN | Remember Where the Context Click Happened
        # ------------------------------------------------------------
        def onRButtonDown(flags, x, y, view)
            @na_context_x = x
            @na_context_y = y
            false
        end
        # ---------------------------------------------------------------

        # ON RIGHT BUTTON UP | Fallback Popup for Empty Viewport Space
        # ------------------------------------------------------------
        def onRButtonUp(flags, x, y, view)
            @na_context_x = x
            @na_context_y = y
            na_drawn__schedule_popup(x, y)
            false
        end
        # ---------------------------------------------------------------

        # GET MENU | Suppress the Native Menu and Raise the HtmlDialog Popup
        # ------------------------------------------------------------
        def getMenu(menu, *args)
            if args.length >= 4
                na_drawn__schedule_popup(args[1], args[2])
            else
                na_drawn__schedule_popup(@na_context_x, @na_context_y)
            end
            nil
        end
        # ---------------------------------------------------------------

        # ON CANCEL | Step Out of a Drag, or Leave the Tool When Already Idle
        # ------------------------------------------------------------
        def onCancel(reason, view)
            @na_vcb_typing_active = false                                     # <-- ESC clears the pending entry with the box

            if @na_state != :idle
                na_drawn__reset_pick_state
                na_drawn__update_status_text
                na_drawn__refresh_vcb
                view.invalidate if view
                return
            end

            if reason == 0
                na_drawn__schedule_exit_tool
            else
                view.invalidate if view
            end
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | SketchUp Tool API — Draw
        # -----------------------------------------------------------------------------

        # DRAW | Anchor Marker, Cursor Marker and the Subclass Preview
        # ------------------------------------------------------------
        def draw(view)
            # The InputPoint markers are only honest while the InputPoint is what
            # is actually driving the cursor. On a locked plane or in the depth
            # stage the point comes from a pick ray instead, and a stray marker
            # sitting on unrelated geometry would just mislead.
            @na_ip.draw(view) if na_drawn__inference_visible? && @na_ip && @na_ip.valid?

            # Drawn before the shape so the shaded preview sits on top of it.
            Na__InsertPrimatives.Na__DrawnPreview__DrawAxisRay(view, na_drawn__axis_ray_origin, @na_axis_lock)

            if @na_state == :idle
                Na__InsertPrimatives.Na__DrawnPreview__DrawCrosshair(view, @na_cursor_snapped)
                return
            end

            na_drawn__draw_preview(view)
            Na__InsertPrimatives.Na__DrawnPreview__DrawCrosshair(view, @na_point_a, nil, NA_DRAWN_ANCHOR_COLOR)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is the InputPoint Currently Driving the Cursor?
        # ------------------------------------------------------------
        def na_drawn__inference_visible?
            return true  if @na_ctrl_held                                     # <-- Ctrl exists to show inference, so always draw it
            return true  if @na_state == :idle
            return true  if @na_state == :picking_b && @na_plane_lock == :auto
            false
        end
        # ---------------------------------------------------------------

        # GET EXTENTS | Keep the Preview Inside the Draw Bounds
        # ------------------------------------------------------------
        def getExtents
            bounds = Geom::BoundingBox.new
            bounds.add(@na_point_a)        if @na_point_a
            bounds.add(@na_cursor_snapped) if @na_cursor_snapped

            na_drawn__preview_points.each { |pt| bounds.add(pt) }
            bounds
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | SketchUp Tool API — Keyboard and Measurements Box
        # -----------------------------------------------------------------------------

        # ON KEY DOWN | Plane Lock Cycling, Step-Back and VCB Entry Tracking
        # ------------------------------------------------------------
        def onKeyDown(key, repeat, flags, view)
            # Catches Ctrl going down while the mouse is still. A repeat firing is
            # harmless here because this is a held flag, not a toggle — the
            # SKEXT-3890 double-fire that broke Tab rotation cannot bite.
            if key == COPY_MODIFIER_KEY && !@na_ctrl_held
                @na_ctrl_held = true
                na_drawn__update_cursor(view, @na_last_mouse_x, @na_last_mouse_y)
                na_drawn__update_status_text
                na_drawn__refresh_vcb
                view.invalidate if view
                return false
            end

            # SHIFT going down while the mouse is still. A supplement only: the
            # mouse flags in na_drawn__sync_modifier are the authority for
            # SHIFT, and they are trustworthy for it. This is here so the
            # preview and status line react the instant the key is pressed
            # rather than waiting for the mouse to twitch.
            if key == NA_DRAWN_SHIFT_KEY && !@na_shift_held
                @na_shift_held = true
                na_drawn__update_cursor(view, @na_last_mouse_x, @na_last_mouse_y)
                na_drawn__update_status_text
                na_drawn__refresh_vcb
                view.invalidate if view
                return false
            end

            # Arrow keys are the axis lock every SketchUp user reaches for, so
            # they are handled before anything else can swallow them.
            axis = na_drawn__axis_for_key(key)
            if axis || key == VK_DOWN
                na_drawn__apply_axis_lock(axis, view)
                return false
            end

            if key == NA_DRAWN_TAB_KEY && !@na_tab_held
                @na_tab_held = true
                na_drawn__cycle_plane_lock(view)
                return false
            end

            if key == NA_DRAWN_BACKSPACE_KEY || key == VK_DELETE
                return false if @na_vcb_typing_active                          # <-- Mid-entry this is a typo fix, not a step-back
                na_drawn__step_back(view)
                return false
            end

            @na_vcb_typing_active = true if NA_DRAWN_VCB_ENTRY_KEYS.include?(key)
            false
        end
        # ---------------------------------------------------------------

        # ON KEY UP | Release the Tab Repeat Guard
        # ------------------------------------------------------------
        def onKeyUp(key, repeat, flags, view)
            @na_tab_held = false if key == NA_DRAWN_TAB_KEY

            if key == COPY_MODIFIER_KEY && @na_ctrl_held
                @na_ctrl_held = false
                na_drawn__update_cursor(view, @na_last_mouse_x, @na_last_mouse_y)
                na_drawn__update_status_text
                na_drawn__refresh_vcb
                view.invalidate if view
            end

            if key == NA_DRAWN_SHIFT_KEY && @na_shift_held
                @na_shift_held = false
                na_drawn__update_cursor(view, @na_last_mouse_x, @na_last_mouse_y)
                na_drawn__update_status_text
                na_drawn__refresh_vcb
                view.invalidate if view
            end

            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Enable Measurements Box Input
        # ------------------------------------------------------------
        def enableVCB?
            true
        end
        # ---------------------------------------------------------------

        # ON RETURN | Enter on an EMPTY Measurements Box Confirms the Stage
        # SketchUp only routes Enter to onUserText when text is pending; with an
        # empty box it calls onReturn instead. Without this the key did nothing
        # at all, which is why Enter appeared not to close a drag.
        # ------------------------------------------------------------
        def onReturn(view)
            handled =
                case @na_state
                when :picking_b     then na_drawn__advance_from_b(view)
                when :picking_depth then na_drawn__advance_from_depth(view)
                else                     false
                end

            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
            handled ? true : false
        end
        # ---------------------------------------------------------------

        # ON LEFT BUTTON DOUBLE CLICK | Confirm the Stage
        # A double click delivers Down, Up, DoubleClick, Up — so the first Down
        # has usually already placed the shape and this arrives with nothing left
        # to do. Handling it anyway makes the gesture reliable whichever way the
        # events land, and it is a no-op once the tool is back to idle.
        # ------------------------------------------------------------
        def onLButtonDoubleClick(flags, x, y, view)
            na_drawn__sync_modifier(flags)
            return false if @na_state == :idle

            na_drawn__update_cursor(view, x, y)

            case @na_state
            when :picking_b     then na_drawn__advance_from_b(view)
            when :picking_depth then na_drawn__advance_from_depth(view)
            end

            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Route a Measurements Box Entry to the Host Tool
        # ------------------------------------------------------------
        def onUserText(text, view)
            @na_vcb_typing_active = false
            cleaned = text.to_s.strip
            return if cleaned.empty?

            na_drawn__handle_vcb_text(cleaned, view)
            na_drawn__update_status_text
            na_drawn__rearm_vcb
            view.invalidate if view
        rescue ArgumentError => error
            UI.beep
            Sketchup::set_status_text("Invalid entry — #{error.message}", SB_PROMPT)
            na_drawn__rearm_vcb
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Cursor Tracking and Plane Resolution
        # -----------------------------------------------------------------------------

        # FUNCTION | Recompute the Snapped Cursor Point for the Current Stage
        # Three different sources, each the most predictable one for its stage:
        #   idle / auto plane  InputPoint, so the cursor follows real geometry
        #   locked plane       pick ray intersected with the locked drawing plane
        #   depth stage        pick ray projected onto the extrusion axis
        # ------------------------------------------------------------
        def na_drawn__update_cursor(view, x, y)
            @na_last_mouse_x = x
            @na_last_mouse_y = y

            resolved =
                if @na_ctrl_held
                    na_drawn__input_point_position(view, x, y)                 # <-- Ctrl wants SketchUp's own inference, not a ray
                elsif @na_state == :picking_depth && @na_point_a
                    na_drawn__depth_point_from_ray(view, x, y)
                elsif @na_state == :picking_b && @na_point_a && @na_plane_lock != :auto
                    na_drawn__plane_point_from_ray(view, x, y, @na_plane_lock)
                else
                    na_drawn__input_point_position(view, x, y)
                end

            resolved ||= na_drawn__input_point_position(view, x, y)
            return unless resolved

            @na_cursor_raw     = resolved
            @na_cursor_snapped = na_drawn__snap_point(resolved)

            na_drawn__recalculate_sizes
        end
        # ---------------------------------------------------------------

        # FUNCTION | Snap a Point to the Voxel Grid Unless Ctrl Overrides It
        # Holding Ctrl hands the point straight back untouched, so whatever
        # SketchUp's InputPoint inferred — a vertex, a midpoint, an endpoint on a
        # nested component — survives instead of being rounded onto the lattice.
        # ------------------------------------------------------------
        def na_drawn__snap_point(point)
            return point if @na_ctrl_held

            Na__InsertPrimatives.Na__DrawnGrid__SnapPoint(point)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Snap a Distance to the Voxel Grid Unless Ctrl Overrides It
        # ------------------------------------------------------------
        def na_drawn__snap_distance(value)
            return value.to_f if @na_ctrl_held

            Na__InsertPrimatives.Na__DrawnGrid__SnapDistance(value)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Sync the Ctrl and Shift Overrides from a Mouse Event's Flags
        # ------------------------------------------------------------
        # The flags are the authority for both, and both can be read the same
        # plain way because MK_CONTROL and MK_SHIFT are genuine Windows
        # mouse-message bits: whatever the keyboard did, the next mouse event
        # states the truth and a key-up this tool never saw corrects itself.
        #
        # WHY THIS IS WORTH A NOTE. The slope modifier was ALT first, and there
        # is no MK_ALT — so whether a bit ever arrived was up to SketchUp, and
        # read like Ctrl a missing bit meant "ALT is up" and wiped the state the
        # key event had just set. Slope mode previewed correctly off the key
        # event and then committed as an ordinary push, because the button-down
        # that commits is itself a mouse event. Moving to SHIFT removes the
        # whole class of problem rather than working around it.
        # ------------------------------------------------------------
        def na_drawn__sync_modifier(flags)
            bits    = flags.to_i
            ctrl    = (bits & NA_DRAWN_MK_CONTROL) != 0
            shift   = (bits & NA_DRAWN_MK_SHIFT) != 0
            changed = false

            if ctrl != @na_ctrl_held
                @na_ctrl_held = ctrl
                changed       = true
            end

            if shift != @na_shift_held
                @na_shift_held = shift
                changed        = true
            end

            changed
        end
        # ---------------------------------------------------------------

        # FUNCTION | Pick a World Point Through the SketchUp InputPoint
        # Passing the anchor as a reference switches on inference from that point,
        # which is what makes dragging a vertical plane out of open space work.
        # ------------------------------------------------------------
        def na_drawn__input_point_position(view, x, y)
            if @na_state == :idle || @na_ip_origin.nil? || !@na_ip_origin.valid?
                @na_ip.pick(view, x, y)
            else
                @na_ip.pick(view, x, y, @na_ip_origin)
            end

            @na_ip.position
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Intersect the Pick Ray with the Locked Drawing Plane
        # ------------------------------------------------------------
        def na_drawn__plane_point_from_ray(view, x, y, plane_key)
            _u_axis, _v_axis, n_axis = Na__InsertPrimatives.Na__DrawnGrid__PlaneAxes(plane_key)
            ray      = view.pickray(x, y)
            solution = Geom.intersect_line_plane(ray, [@na_point_a, n_axis])

            na_drawn__point_in_front_of_ray?(ray, solution) ? solution : nil
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is a Ray Solution Actually in Front of the Camera?
        # Both Geom helpers treat a pick ray as an infinite line, so a plane or
        # axis seen nearly edge-on hands back a point far behind the eye. Left
        # unchecked that is a rectangle flipped inside out and kilometres wide,
        # so an answer behind the camera is discarded and the caller falls back
        # to the InputPoint.
        # ------------------------------------------------------------
        def na_drawn__point_in_front_of_ray?(ray, point)
            return false unless ray && point

            (point - ray[0]).dot(ray[1]) > 0.0
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Project the Pick Ray onto the Extrusion Axis
        # ------------------------------------------------------------
        def na_drawn__depth_point_from_ray(view, x, y)
            _u_axis, _v_axis, n_axis = Na__InsertPrimatives.Na__DrawnGrid__PlaneAxes(@na_plane_key)
            ray     = view.pickray(x, y)
            closest = Geom.closest_points([@na_point_a, n_axis], ray)
            return nil unless closest && closest[0]

            na_drawn__point_in_front_of_ray?(ray, closest[0]) ? closest[0] : nil
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Refresh the Live Sizes from the Snapped Cursor
        # ------------------------------------------------------------
        def na_drawn__recalculate_sizes
            return unless @na_point_a && @na_cursor_snapped

            case @na_state
            when :picking_b
                @na_plane_key = na_drawn__resolve_plane_key

                u_travel, v_travel, _n = Na__InsertPrimatives.Na__DrawnGrid__DecomposeToPlane(@na_point_a, @na_cursor_snapped, @na_plane_key)
                na_drawn__apply_planar_travel(u_travel, v_travel)

            when :picking_depth
                return if na_drawn__locked?(:d)

                _u, _v, n_travel = Na__InsertPrimatives.Na__DrawnGrid__DecomposeToPlane(@na_point_a, @na_cursor_snapped, @na_plane_key)
                @na_sign_d = n_travel < 0.0 ? -1.0 : 1.0
                @na_size_d = n_travel.abs
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Decide Which Plane the Live Drag Is Being Drawn On
        # The roof tools override this to pin the footprint to plan, where there
        # is no plane decision to make and the drag should never infer one.
        # ------------------------------------------------------------
        def na_drawn__resolve_plane_key
            return @na_plane_lock unless @na_plane_lock == :auto

            Na__InsertPrimatives.Na__DrawnGrid__InferPlaneKey(@na_point_a, @na_cursor_snapped, @na_plane_key)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Turn In-Plane Drag Travel into Live Dimensions
        # Corner-anchored tools take the two travels as width and height. The
        # cylinder overrides this to read the same travel as a radius measured
        # from a centre anchor — everything downstream keeps working because it
        # mirrors the radius back into the u/v sizes.
        # ------------------------------------------------------------
        def na_drawn__apply_planar_travel(u_travel, v_travel)
            unless na_drawn__locked?(:u)
                @na_sign_u = u_travel < 0.0 ? -1.0 : 1.0
                @na_size_u = u_travel.abs
            end

            return if na_drawn__locked?(:v)
            @na_sign_v = v_travel < 0.0 ? -1.0 : 1.0
            @na_size_v = v_travel.abs
        end
        # ---------------------------------------------------------------

        # FUNCTION | Which Axis an Arrow Key Names
        # Right / Left / Up follow SketchUp's own red / green / blue mapping.
        # ------------------------------------------------------------
        def na_drawn__axis_for_key(key)
            case key
            when VK_RIGHT then :x
            when VK_LEFT  then :y
            when VK_UP    then :z
            else               nil
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Apply an Arrow Key Axis Lock
        # Default behaviour for the shape tools: the axis names the plane it is
        # normal to, so Up (blue Z) draws on plan and Right (red X) draws on the
        # YZ side plane. Pressing the same arrow again releases it, and Down
        # always releases — both matching what the native tools do.
        #
        # The roof and push/pull tools override this because their axis decision
        # is a ridge direction and a push direction respectively.
        # ------------------------------------------------------------
        def na_drawn__apply_axis_lock(axis, view)
            @na_axis_lock  = (@na_axis_lock == axis) ? nil : axis
            @na_plane_lock = @na_axis_lock.nil? ? :auto : NA_DRAWN_AXIS_TO_PLANE[@na_axis_lock]
            @na_plane_key  = @na_plane_lock unless @na_plane_lock == :auto

            na_drawn__after_axis_lock_changed(view)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Re-Solve and Redraw After an Axis Lock Changes
        # ------------------------------------------------------------
        def na_drawn__after_axis_lock_changed(view)
            na_drawn__update_cursor(view, @na_last_mouse_x, @na_last_mouse_y) if @na_state != :idle
            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
        end
        # ---------------------------------------------------------------

        # FUNCTION | Where the Axis Ray Should Be Drawn From
        # ------------------------------------------------------------
        def na_drawn__axis_ray_origin
            @na_point_a || @na_cursor_snapped
        end
        # ---------------------------------------------------------------

        # FUNCTION | Status Fragment for the Axis Lock
        # ------------------------------------------------------------
        def na_drawn__axis_description
            return '' unless @na_axis_lock

            " | AXIS #{NA_DRAWN_AXIS_LABELS[@na_axis_lock]}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Cycle the Plane Lock and Re-Solve the Current Drag
        # ------------------------------------------------------------
        def na_drawn__cycle_plane_lock(view)
            index          = NA_DRAWN_PLANE_LOCK_CYCLE.index(@na_plane_lock) || 0
            @na_plane_lock = NA_DRAWN_PLANE_LOCK_CYCLE[(index + 1) % NA_DRAWN_PLANE_LOCK_CYCLE.length]
            @na_plane_key  = @na_plane_lock unless @na_plane_lock == :auto

            na_drawn__update_cursor(view, @na_last_mouse_x, @na_last_mouse_y) if @na_state != :idle
            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
        end
        # ---------------------------------------------------------------

        # FUNCTION | Step One Stage Backwards Through the Drag
        # ------------------------------------------------------------
        def na_drawn__step_back(view)
            # A pinned dimension is the most recent thing the user committed to,
            # so peel those off first — otherwise a mistyped lock could only be
            # escaped by abandoning the whole drag.
            released = na_drawn__release_last_lock

            if released
                na_drawn__update_cursor(view, @na_last_mouse_x, @na_last_mouse_y)
                na_drawn__update_status_text
                na_drawn__refresh_vcb
                Sketchup::set_status_text("Released #{released.to_s.upcase} — back on the drag", SB_PROMPT)
                view.invalidate if view
                return
            end

            case @na_state
            when :picking_depth
                @na_state  = :picking_b
                @na_size_d = 0.0
            when :picking_b
                na_drawn__reset_pick_state
            end

            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Shared Geometry State Helpers
        # -----------------------------------------------------------------------------

        # FUNCTION | Signed Width of the Live Rectangle
        # ------------------------------------------------------------
        def na_drawn__signed_u
            @na_size_u.to_f.abs * @na_sign_u.to_f
        end
        # ---------------------------------------------------------------

        # FUNCTION | Signed Height of the Live Rectangle
        # ------------------------------------------------------------
        def na_drawn__signed_v
            @na_size_v.to_f.abs * @na_sign_v.to_f
        end
        # ---------------------------------------------------------------

        # FUNCTION | Signed Depth of the Live Extrusion
        # ------------------------------------------------------------
        def na_drawn__signed_d
            @na_size_d.to_f.abs * @na_sign_d.to_f
        end
        # ---------------------------------------------------------------

        # FUNCTION | Does the Live Rectangle Enclose Any Area?
        # ------------------------------------------------------------
        def na_drawn__rectangle_valid?
            Na__InsertPrimatives.Na__DrawnGeom__ValidRectangle?(@na_size_u, @na_size_v)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Corner Points of the Live Rectangle
        # ------------------------------------------------------------
        def na_drawn__rectangle_points
            return nil unless @na_point_a

            Na__InsertPrimatives.Na__DrawnGrid__BuildRectPoints(
                @na_point_a, @na_plane_key, na_drawn__signed_u, na_drawn__signed_v
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | Every Point the Current Preview Occupies
        # ------------------------------------------------------------
        def na_drawn__preview_points
            points = na_drawn__rectangle_points
            return [] unless points

            return points unless @na_state == :picking_depth

            points + Na__InsertPrimatives.Na__DrawnGrid__OffsetPointsAlongNormal(points, @na_plane_key, na_drawn__signed_d)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Revise-Last-Shape Arming
        # -----------------------------------------------------------------------------

        # FUNCTION | Arm Revise Mode After a Shape Is Committed
        # ------------------------------------------------------------
        def na_drawn__arm_revise
            @na_revise_armed    = true
            @na_revise_anchor_x = @na_last_mouse_x
            @na_revise_anchor_y = @na_last_mouse_y
        end
        # ---------------------------------------------------------------

        # FUNCTION | Disarm Revise Mode
        # ------------------------------------------------------------
        def na_drawn__disarm_revise
            @na_revise_armed    = false
            @na_revise_anchor_x = nil
            @na_revise_anchor_y = nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Disarm Revise Mode Once the Mouse Deliberately Moves
        # ------------------------------------------------------------
        def na_drawn__disarm_revise_if_moved(x, y)
            return unless @na_revise_armed

            if @na_revise_anchor_x.nil? || @na_revise_anchor_y.nil?
                na_drawn__disarm_revise
                return
            end

            travelled = (x.to_f - @na_revise_anchor_x.to_f).abs + (y.to_f - @na_revise_anchor_y.to_f).abs
            na_drawn__disarm_revise if travelled > NA_DRAWN_REVISE_DISARM_PX
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is There a Live Shape Available to Revise?
        # ------------------------------------------------------------
        def na_drawn__revise_available?
            @na_revise_armed &&
                @na_last_record &&
                @na_last_record[:group] &&
                @na_last_record[:group].valid?
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Status Bar and Measurements Box
        # -----------------------------------------------------------------------------

        # FUNCTION | Human-Readable Description of the Active Plane
        # ------------------------------------------------------------
        def na_drawn__plane_description
            key   = @na_plane_lock == :auto ? @na_plane_key : @na_plane_lock
            label = NA_DRAWN_PLANE_LABELS[key] || key.to_s
            @na_plane_lock == :auto ? "Plane #{label} auto" : "Plane #{label} LOCK"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Push the Composed Status Line
        # ------------------------------------------------------------
        # Sketchup::set_status_text is a native UI call, and this runs on every
        # mouse-move event. Pushing an identical string hundreds of times a second
        # is a real source of drag — the text only actually changes when a size or
        # a mode does, so it is only sent when it differs.
        #
        # Side benefit: a transient warning pushed by another code path is no
        # longer wiped by the very next mouse move, because an unchanged composed
        # line is not re-sent over the top of it.
        def na_drawn__update_status_text
            composed =
                "#{na_drawn__tool_title} | #{na_drawn__status_detail} | " \
                "#{na_drawn__grid_description} | " \
                "#{na_drawn__plane_description}#{na_drawn__axis_description}#{na_drawn__lock_summary} | " \
                "#{na_drawn__tab_hint}  ARROWS axis  CTRL vertex  BKSP back  ESC cancel"

            return if composed == @na_last_status_text

            Sketchup::set_status_text(composed, SB_PROMPT)
            @na_last_status_text = composed
        end
        # ---------------------------------------------------------------

        # FUNCTION | Status Fragment for the Selection Focus
        # ------------------------------------------------------------
        # The deep pickers favour whatever the user has selected, which is a
        # real change to what a click will grab — so it is said out loud rather
        # than left to be discovered. Empty when nothing is selected, which is
        # also when the pickers behave exactly as they always did.
        #
        # Guarded by respond_to? because this module is mixed into every tool,
        # including the create tools that never load the deep picker.
        # ------------------------------------------------------------
        def na_drawn__focus_hint
            return '' unless Na__InsertPrimatives.respond_to?(:Na__DeepPick__FocusLabel)

            label = Na__InsertPrimatives.Na__DeepPick__FocusLabel
            label ? " — favouring #{label}" : ''
        rescue StandardError
            ''
        end
        # ---------------------------------------------------------------

        # FUNCTION | Status Fragment for the Snap State
        # ------------------------------------------------------------
        def na_drawn__grid_description
            return 'Grid OFF — CTRL vertex snap' if @na_ctrl_held

            "Grid #{Na__InsertPrimatives.Na__DrawnSettings__GridStepLabel}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | What TAB Does in This Tool
        # ------------------------------------------------------------
        def na_drawn__tab_hint
            'TAB plane'
        end
        # ---------------------------------------------------------------

        # FUNCTION | Push the Measurements Box Label and Value
        # ------------------------------------------------------------
        def na_drawn__refresh_vcb
            label, value = na_drawn__vcb_label_and_value

            unless label.to_s == @na_last_vcb_label
                Sketchup::set_status_text(label.to_s, SB_VCB_LABEL)
                @na_last_vcb_label = label.to_s
            end

            return if value.to_s == @na_last_vcb_text
            Sketchup::set_status_text(value.to_s, SB_VCB_VALUE)
            @na_last_vcb_text = value.to_s
        end
        # ---------------------------------------------------------------

        # FUNCTION | Re-Push the Measurements Box a Beat After onUserText
        # SketchUp wipes the box once an entry has been handled, so the refreshed
        # value has to be written from a timer rather than inline.
        # ------------------------------------------------------------
        def na_drawn__rearm_vcb
            UI.start_timer(0.1, false) do
                begin
                    @na_last_vcb_text = nil
                    na_drawn__refresh_vcb
                rescue StandardError
                    nil
                end
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Render a Size List as a Comma Separated mm String
        # ------------------------------------------------------------
        def na_drawn__format_sizes(values)
            values.map { |value| Na__InsertPrimatives.Na__DrawnFormat__Mm(value).abs.to_s }.join(',')
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Popup, Exit and Console Banner
        # -----------------------------------------------------------------------------

        # FUNCTION | Schedule the Right-Click Popup Outside the Event Callback
        # ------------------------------------------------------------
        def na_drawn__schedule_popup(x, y)
            return if @na_popup_scheduled
            @na_popup_scheduled = true

            UI.start_timer(0.05, false) do
                begin
                    Na__InsertPrimatives.Na__RightClickPopup__ShowPrimitiveMenu(self, x, y)
                ensure
                    @na_popup_scheduled = false
                end
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Exit the Tool Safely on the Next Tick
        # ------------------------------------------------------------
        def na_drawn__schedule_exit_tool
            return if @na_exit_scheduled
            @na_exit_scheduled = true

            UI.start_timer(0, false) do
                begin
                    model = Sketchup.active_model
                    model.select_tool(nil) if model
                ensure
                    @na_exit_scheduled = false
                end
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Exit the Tool (Popup Menu Entry Point)
        # ------------------------------------------------------------
        def Na__PrimitiveMode__ScheduleExitTool
            na_drawn__schedule_exit_tool
        end
        # ---------------------------------------------------------------

        # FUNCTION | Print the Activation Banner to the Ruby Console
        # ------------------------------------------------------------
        def na_drawn__print_activation_banner
            puts "\n"
            puts '----------------------------------------'
            puts "#{na_drawn__tool_title.upcase} ACTIVATED"
            puts "Snap grid: #{Na__InsertPrimatives.Na__DrawnSettings__GridStepLabel} voxel lattice"
            na_drawn__activation_hints.each { |hint| puts hint }
            puts '----------------------------------------'
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Popup Menu Interface Shared With PrimitiveCubeTool
        # -----------------------------------------------------------------------------

        # FUNCTION | Switch to Cube Placement Mode
        # ------------------------------------------------------------
        def Na__PrimitiveMode__SetCubeMode
            Na__InsertPrimatives.Na__ModeSwitch__ActivateCubeTool(:cube)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Switch to Click-to-Place Plane Mode
        # ------------------------------------------------------------
        def Na__PrimitiveMode__SetPlaneMode
            Na__InsertPrimatives.Na__ModeSwitch__ActivateCubeTool(:plane)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Toggle Whether Planes Are Built With Faces
        # ------------------------------------------------------------
        def Na__PrimitiveMode__TogglePlaneFaces
            enabled = !Na__InsertPrimatives.Na__DrawnSettings__PlaneFacesEnabled?
            Na__InsertPrimatives.Na__DrawnSettings__SetPlaneFacesEnabled(enabled)

            Sketchup::set_status_text("Plane faces #{enabled ? 'enabled' : 'disabled'}", SB_PROMPT)
            enabled
        end
        # ---------------------------------------------------------------

        # FUNCTION | Are Planes Built With Faces?
        # ------------------------------------------------------------
        def Na__PrimitiveMode__PlaneFacesEnabled?
            Na__InsertPrimatives.Na__DrawnSettings__PlaneFacesEnabled?
        end
        # ---------------------------------------------------------------

        # FUNCTION | Which Primitive Mode Is Running (Popup Highlight)
        # ------------------------------------------------------------
        def Na__DrawnMode__ActiveModeKey
            na_drawn__mode_key
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnToolShared module

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DRAWN PRIMITIVES SHARED TOOL BEHAVIOUR MODULE
# =============================================================================
