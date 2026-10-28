# =============================================================================
# NA INSERT PRIMATIVES - DRAWN PLANE TOOL
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnPlaneTool__.rb
# NAMESPACE  : Na__InsertPrimatives
# CLASS      : DrawnPlaneTool
# AUTHOR     : Noble Architecture
# PURPOSE    : Click-and-drag rectangle primitive locked to the shared voxel grid
# CREATED    : 2026
#
# DESCRIPTION:
# - Press, drag, release (or click, move, click) to sweep out a rectangle. Both
#   corners land on the shared voxel lattice, so every plane drawn this way sits
#   on a rounded grid coordinate with grid-multiple dimensions.
# - The drawing plane comes from the drag itself: the axis the cursor travels
#   least along becomes the plane normal. TAB locks it to XY / XZ / YZ when the
#   inference is not what you want.
# - The measurements box pins one axis at a time. Type the size you know, keep
#   dragging the one you do not, then either click or type again to finish. An
#   entry typed straight after a plane is drawn corrects that plane in place.
#
# MEASUREMENTS BOX:
#   350         pin the width at 350, keep dragging the height
#   ,1610       pin the height, keep dragging the width
#   350,1610    pin both and place immediately
#   +100        pin the width at its live size plus 100
#   2.4m,600mm  suffixes mm | cm | m, bare numbers are mm
#   BKSP        release the last pinned axis and go back to dragging it
#
# POPUP SUBMENU OPTIONS (see Na__InsertPrimatives__AppData__ToolOptions__.rb):
#   Face         on: the plane is a face. Off: the four edges only, no face.
#                The same setting as the click-to-place Plane's Plane Faces.
#   Transparent  the new group CONTAINER is painted with the indexed material
#                MAT011__ModelingUtility__Transparent, as Drawn Volume does.
#   2D Orbit Lock  on (default): in a parallel view, AltGr / Ctrl+Alt cannot
#                orbit or pan the camera (SketchUp 2027's touchpad gestures);
#                the middle mouse, the Pan tool and the wheel work as ever.
#                Shared with Drawn Volume. See Camera__ParallelDrawingGuard__
#                and Camera__AltGrFilter__.
#
# CHANGING YOUR MIND MID-DRAG:
#   Either option can be switched from the popup with the rectangle still on
#   the cursor (click a corner, right-click, switch, carry on). The drag is
#   kept, the preview shows what will now be built (outline only, or a
#   see-through fill) and the click places it with the options as they stand.
#   A plane already placed keeps its own face and paint: a size typed after
#   drawing corrects its size only.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../06__Tools__DrawnShared/Na__InsertPrimatives__DrawnToolShared__'
require_relative '../06__Tools__DrawnShared/Na__InsertPrimatives__Camera__ParallelDrawingGuard__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Drawn Plane Tool Class
    # -----------------------------------------------------------------------------

    # CLASS | Click-and-Drag Rectangle Primitive Tool
    # ------------------------------------------------------------
    class DrawnPlaneTool

        include Na__InsertPrimatives::DrawnToolShared
        prepend Na__InsertPrimatives::ParallelDrawingGuard                     # <-- Holds a 2D view still against AltGr / Ctrl+Alt orbit (SketchUp 2027)

        # INITIALIZE | Tool Constructor
        # ------------------------------------------------------------
        def initialize
            na_drawn__init_shared_state
        end
        # ---------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Identity
        # -----------------------------------------------------------------------------

        # FUNCTION | Status Bar Title
        # ------------------------------------------------------------
        def na_drawn__tool_title
            'Drawn Plane'
        end
        # ---------------------------------------------------------------

        # FUNCTION | Popup Menu Highlight Key
        # ------------------------------------------------------------
        def na_drawn__mode_key
            :drawn_plane
        end
        # ---------------------------------------------------------------

        # FUNCTION | Console Banner Hint Lines
        # ------------------------------------------------------------
        def na_drawn__activation_hints
            hints = [
                'Click and drag a rectangle, or click once then click again',
                'Both corners snap to the voxel grid — hold CTRL to snap to vertices instead',
                'Hold CTRL+SHIFT to snap to a vertex and then round it onto the grid',
                'TAB cycles the drawing plane: Auto > XY > XZ > YZ',
                'VCB: 350 pins the width | ,1610 pins the height | 350,1610 places it',
                'A pinned axis stops following the drag — BKSP releases it again',
                'Type straight after drawing to correct the plane in place',
                'Right-click for the menu — Face and Transparent sit under this tool, and switch mid-drag'
            ]

            hints << 'FACE OFF: new planes are the four edges only' unless na_plane__faces_option?
            hints << 'TRANSPARENT ON: new planes are painted MAT011__ModelingUtility__Transparent' if na_plane__transparent_option?
            hints
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Options — Read Fresh Every Time
        # -----------------------------------------------------------------------------
        #
        # Never cached on the tool: the popup can switch either one in the
        # middle of a drag, and the preview, the status line and the commit all
        # have to agree with the button the user has just clicked.

        # FUNCTION | Is the Plane Built as a Face (Off = Edges Only)?
        # ------------------------------------------------------------
        def na_plane__faces_option?
            Na__InsertPrimatives.Na__DrawnSettings__PlaneFacesEnabled?
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is the Transparent Material Option Switched On?
        # ------------------------------------------------------------
        def na_plane__transparent_option?
            Na__InsertPrimatives.Na__ToolOptions__Enabled?('plane_transparent')
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Material Name a New Plane's Container Is Painted With
        # ------------------------------------------------------------
        def na_plane__container_material
            na_plane__transparent_option? ? NA_STD_MAT_TRANSPARENT : nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Options in Words, or nil When Both Are at Their Defaults
        # ------------------------------------------------------------
        def na_plane__option_words
            words = []
            words << 'Edges only'  unless na_plane__faces_option?
            words << 'Transparent' if na_plane__transparent_option?
            words.empty? ? nil : words
        end
        # ---------------------------------------------------------------

        # FUNCTION | Status Fragment Naming the Options That Are Not the Default
        # ------------------------------------------------------------
        # The shared summary names every toggle that is ON, which for a Face
        # that is on by default would put "FACE" on every status line. What
        # is worth saying is the unusual state, so this says EDGES ONLY.
        # ------------------------------------------------------------
        def na_drawn__option_summary
            words = na_plane__option_words
            words ? " | #{words.map { |word| word.upcase }.join('+')}" : ''
        rescue StandardError
            ''
        end
        # ---------------------------------------------------------------

        # FUNCTION | An Option Switched From the Popup — the Drag in Hand Follows
        # ------------------------------------------------------------
        # The shared toggle stores the option and redraws. The preview and the
        # commit read the options fresh, so the rectangle on the cursor is
        # already what the next click builds; this brings the status line and
        # the measurements box up to date at once rather than on the next mouse
        # move, and says the drag was kept.
        # ------------------------------------------------------------
        def Na__DrawnMode__ToggleToolOption(option_id)
            result = super

            @na_last_status_text = nil
            na_drawn__update_status_text
            na_drawn__refresh_vcb

            if @na_state == :picking_b
                caption = result.is_a?(Hash) ? result[:caption] : result.to_s
                Sketchup::set_status_text("#{caption} — the plane on the cursor follows, click to place it", SB_PROMPT)
                @na_last_status_text = nil                                    # <-- So the next mouse move puts the full line back
            end

            model = Sketchup.active_model
            model.active_view.invalidate if model
            result
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Drag Completion
        # -----------------------------------------------------------------------------

        # FUNCTION | Base Rectangle Settled — Build the Plane
        # ------------------------------------------------------------
        def na_drawn__advance_from_b(view)
            na_drawn__commit_plane(view)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Depth Stage Is Never Reached by This Tool
        # ------------------------------------------------------------
        def na_drawn__advance_from_depth(view)
            false
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Preview
        # -----------------------------------------------------------------------------

        # FUNCTION | Draw the Rectangle as It Will Be Built, and Its Dimensions
        # ------------------------------------------------------------
        # Face off draws the four edges and nothing between them; Transparent
        # thins the fill. Both are read on every frame, so a switch made in
        # the popup mid-drag shows on the rectangle at once.
        # ------------------------------------------------------------
        def na_drawn__draw_preview(view)
            points = na_drawn__rectangle_points
            return unless points

            unless na_drawn__rectangle_valid?
                Na__InsertPrimatives.Na__DrawnPreview__DrawOutline(view, points, NA_DRAWN_PLANE_BORDER_COLOR)
                return
            end

            if na_plane__faces_option?
                fill = na_plane__transparent_option? ? NA_DRAWN_PLANE_GLASS_FILL : NA_DRAWN_PLANE_FILL_COLOR
                Na__InsertPrimatives.Na__DrawnPreview__DrawFilledQuad(view, points, fill, NA_DRAWN_PLANE_BORDER_COLOR)
            else
                Na__InsertPrimatives.Na__DrawnPreview__DrawLoop(view, points, NA_DRAWN_PLANE_BORDER_COLOR)
            end

            Na__InsertPrimatives.Na__DrawnPreview__LabelRectangle(
                view, points, @na_size_u, @na_size_v, na_drawn__locked?(:u), na_drawn__locked?(:v)
            )

            words = na_plane__option_words
            Na__InsertPrimatives.Na__DrawnPreview__SummarisePlane(
                view, points[2], @na_size_u, @na_size_v, words ? words.join(' + ') : nil
            )
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Status and Measurements Box
        # -----------------------------------------------------------------------------

        # FUNCTION | Middle Section of the Status Bar Line
        # ------------------------------------------------------------
        def na_drawn__status_detail
            if @na_state == :picking_b
                width_mm  = Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_size_u).abs
                height_mm = Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_size_v).abs
                width_txt  = na_drawn__locked?(:u) ? "[#{width_mm}]"  : width_mm.to_s
                height_txt = na_drawn__locked?(:v) ? "[#{height_mm}]" : height_mm.to_s
                return "W #{width_txt} x H #{height_txt} mm — release or click to place"
            end

            return 'Type W,H to correct the plane just drawn' if na_drawn__revise_available?
            'Click and drag out a rectangle'
        end
        # ---------------------------------------------------------------

        # FUNCTION | Measurements Box Label and Live Value
        # ------------------------------------------------------------
        def na_drawn__vcb_label_and_value
            return ['Plane W,H', ''] if @na_state == :idle && !na_drawn__revise_available?

            ['Plane W,H', na_drawn__format_sizes([@na_size_u, @na_size_v])]
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Measurements Box Entry
        # -----------------------------------------------------------------------------

        # FUNCTION | Apply a Typed Size to the Live Drag or the Last Plane
        # ------------------------------------------------------------
        def na_drawn__handle_vcb_text(text, view)
            tokens = Na__InsertPrimatives.Na__DrawnVcb__ParseEntry(text)
            raise ArgumentError, 'plane takes one value (square) or W,H' if tokens.length > 2

            case @na_state
            when :picking_b
                na_drawn__apply_typed_sizes(tokens)
                return true unless na_drawn__all_locked?([:u, :v])            # <-- One axis named: pin it, leave the other on the drag
                na_drawn__commit_plane(view)

            when :idle
                unless na_drawn__revise_available?
                    UI.beep
                    Sketchup::set_status_text('Click a start corner before typing a size', SB_PROMPT)
                    return false
                end

                # Revise has no drag, so "the axis still under the mouse" means
                # nothing here. Clearing the pins keeps a typed entry strictly
                # positional: 350 is always the width, ,1610 always the height.
                na_drawn__clear_locks
                na_drawn__apply_typed_sizes(tokens)
                na_drawn__revise_plane(view)

            else
                UI.beep
                false
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Resolve Typed Tokens Against the Live Width and Height
        # Each named slot is also pinned, so the drag stops moving it while the
        # unnamed one keeps following the mouse.
        # ------------------------------------------------------------
        def na_drawn__apply_typed_sizes(tokens)
            tokens = na_drawn__align_single_token(tokens, [:u, :v])
            sizes  = Na__InsertPrimatives.Na__DrawnVcb__ResolveAgainst(tokens, [@na_size_u, @na_size_v])
            Na__InsertPrimatives.Na__DrawnVcb__ValidatePositive(sizes, ['Width', 'Height'])

            @na_size_u = sizes[0]
            @na_size_v = sizes[1]

            Na__InsertPrimatives.Na__DrawnVcb__NamedSlots(tokens).each do |index|
                na_drawn__lock_slot(index.zero? ? :u : :v)
            end

            sizes
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Geometry Commit and Revise
        # -----------------------------------------------------------------------------

        # FUNCTION | Build the Plane Group from the Current Drag State
        # ------------------------------------------------------------
        def na_drawn__commit_plane(view)
            unless na_drawn__rectangle_valid?
                UI.beep
                Sketchup::set_status_text('Rectangle has no area — drag further before releasing', SB_PROMPT)
                return false
            end

            origin      = @na_point_a
            plane_key   = @na_plane_key
            width_len   = na_drawn__signed_u
            height_len  = na_drawn__signed_v
            build_faces = na_plane__faces_option?                            # <-- Read at the click, so a mid-drag switch counts
            material    = na_plane__container_material

            # The material name goes IN to the create call, as it does for the
            # volume, so the paint and the plane are one Ctrl+Z.
            group = Na__InsertPrimatives.Na__DrawnGeom__CreatePlane(
                origin, plane_key, width_len, height_len, view, build_faces, material
            )

            unless group
                UI.beep
                Sketchup::set_status_text('Could not create a plane here', SB_PROMPT)
                return false
            end

            @na_last_record = {
                :group     => group,
                :origin    => origin,
                :plane_key => plane_key,
                :sign_u    => @na_sign_u,
                :sign_v    => @na_sign_v,
                :faces     => build_faces                                     # <-- A typed correction keeps the plane's own face
            }

            na_drawn__reset_pick_state
            na_drawn__arm_revise
            na_drawn__log_plane('DRAWN PLANE CREATED', origin, plane_key, width_len, height_len, build_faces, material)
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Rebuild the Last Plane at the Same Anchor
        # ------------------------------------------------------------
        def na_drawn__revise_plane(view)
            record = @na_last_record
            return false unless record

            width_len   = @na_size_u.to_f.abs * record[:sign_u].to_f
            height_len  = @na_size_v.to_f.abs * record[:sign_v].to_f

            # The face the plane was BUILT with, not the option as it stands
            # now: switching Face off for the next plane must not strip the
            # one just drawn when its size is corrected. The paint needs no
            # such care — it is on the group, and clear! leaves the group.
            build_faces = record.key?(:faces) ? record[:faces] : na_plane__faces_option?

            rebuilt = Na__InsertPrimatives.Na__DrawnGeom__RebuildPlane(
                record[:group], record[:origin], record[:plane_key],
                width_len, height_len, view, build_faces
            )

            unless rebuilt
                UI.beep
                Sketchup::set_status_text('Could not rebuild that plane', SB_PROMPT)
                return false
            end

            na_drawn__arm_revise                                               # <-- Keep revising while the mouse stays put
            painted = record[:group].material ? record[:group].material.name : nil
            na_drawn__log_plane('DRAWN PLANE ADJUSTED', record[:origin], record[:plane_key], width_len, height_len, build_faces, painted)
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Console Report for a Created or Adjusted Plane
        # ------------------------------------------------------------
        def na_drawn__log_plane(headline, origin, plane_key, width_len, height_len, build_faces, material = nil)
            Na__InsertPrimatives.Na__Debug__Puts "\n"
            Na__InsertPrimatives.Na__Debug__Puts '----------------------------------------'
            Na__InsertPrimatives.Na__Debug__Puts headline
            Na__InsertPrimatives.Na__Debug__Puts "Anchor: #{Na__InsertPrimatives.Na__DrawnFormat__PointMm(origin)}"
            Na__InsertPrimatives.Na__Debug__Puts "Plane : #{NA_DRAWN_PLANE_LABELS[plane_key]}"
            Na__InsertPrimatives.Na__Debug__Puts "Size  : #{Na__InsertPrimatives.Na__DrawnFormat__Mm(width_len).abs}mm x #{Na__InsertPrimatives.Na__DrawnFormat__Mm(height_len).abs}mm"
            Na__InsertPrimatives.Na__Debug__Puts "Area  : #{Na__InsertPrimatives.Na__DrawnFormat__AreaM2(width_len, height_len)} m2"
            Na__InsertPrimatives.Na__Debug__Puts "Faces : #{build_faces ? 'Enabled' : 'Disabled — edges only'}"
            Na__InsertPrimatives.Na__Debug__Puts "Paint : #{material || 'none'}"
            Na__InsertPrimatives.Na__Debug__Puts "Grid  : #{Na__InsertPrimatives.Na__DrawnSettings__GridStepLabel}"
            Na__InsertPrimatives.Na__Debug__Puts '----------------------------------------'
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnPlaneTool class

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Public Entry Point
    # -----------------------------------------------------------------------------

    # FUNCTION | Activate the Drawn Plane Tool (Hotkey Entry Point)
    # ------------------------------------------------------------
    # Bind in Preferences -> Shortcuts against the Plugins menu item, or call
    # directly: Na__InsertPrimatives.Na__InsertPrimatives__DrawPlane
    # ------------------------------------------------------------
    def self.Na__InsertPrimatives__DrawPlane
        Na__InsertPrimatives.Na__ModeSwitch__ActivateDrawnPlaneTool
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DRAWN PLANE TOOL MODULE
# =============================================================================
