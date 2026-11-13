# =============================================================================
# NA NOBLE DRAWING TOOLS - DEEP STRETCH TOOL
# =============================================================================
#
# FILE       : Na__NobleDrawingTools__DrawnStretchTool__.rb
# NAMESPACE  : Na__NobleDrawingTools
# CLASS      : DrawnStretchTool (a DrawnScaleTool)
# AUTHOR     : Noble Architecture
# PURPOSE    : Deep Scale with Stretch Planes locked on, on a shortcut of its
#              own: every grip stretches, and nothing can make it scale
# CREATED    : 2026
#
# DESCRIPTION:
# - Asked for 13-Nov-2026: a key that starts the tool in stretch only, where
#   the other scale modes can only be had by leaving it, so a stretch can
#   never become a scale by a slip of the hand.
# - Everything is Deep Scale's: the grips, the planes and placing them, the
#   dimensions, typing, CTRL, TAB About Centre, the handle bar, a selection of
#   several objects, the commit. Only the switches between scaling and
#   stretching are taken away, through one question every one of them asks,
#   na_scale__stretch_only?:
#     Stretch Planes   always on (na_scale__planes_on?), and never written to
#                      the stored switch, so Deep Scale finds it as it was left
#     SHIFT+TAB, the Planes button, the STRETCH pill, the popup's Stretch Planes
#     and Grips Scale, the UNIFORM and NON-UNIFORM pills and the mode commands
#                      refused with a beep and a line saying how to scale
#     a commit         refused if any axis would scale (one too thin to hold a
#                      plane), rather than distort it
# - SHIFT on a grip still moves every axis together: that is still a stretch.
# - Its command is NA_DeepStretch, Extensions > Na__NobleDrawingTools > Deep
#   Stretch, for a key of its own in Preferences > Shortcuts.
# - The right-click popup has a button of its own (5.2.42), under Deep Scale,
#   with its own icon (a block opened at a band, Icon__NobleDrawingTools__
#   DeepStretch__.svg, drawn by the vector-graphic-artist skill's generator).
#   Its mode key is :drawn_stretch, so that button lights while it runs. It
#   declares no options of its own: it shows Deep Scale's, the same stored
#   settings, less Stretch Planes and Grips Scale, which it cannot change.
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__NobleDrawingTools__DrawnScaleTool__'

module Na__NobleDrawingTools

    # -----------------------------------------------------------------------------
    # REGION | Deep Stretch Tool Class
    # -----------------------------------------------------------------------------

    # CLASS | Deep Scale That Only Stretches
    # ------------------------------------------------------------
    class DrawnStretchTool < DrawnScaleTool

        NA_STRETCH_HIDDEN_OPTIONS = %w[scale_planes scale_grip_mode].freeze  # <-- The two switches to scaling: refused here, so not offered

        # FUNCTION | Status Bar Title
        # ------------------------------------------------------------
        def na_drawn__tool_title
            'Deep Stretch'
        end
        # ---------------------------------------------------------------

        # FUNCTION | Popup Menu Highlight Key: Its Own Button
        # ------------------------------------------------------------
        def na_drawn__mode_key
            :drawn_stretch
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Popup's Options: Deep Scale's, Less the Switches to Scaling
        # ------------------------------------------------------------
        # The same stored settings as Deep Scale (handles, About Centre, the
        # dimensions, Clear Stretch Planes), declared once under :drawn_scale.
        # ------------------------------------------------------------
        def Na__DrawnMode__ToolOptions
            Na__NobleDrawingTools.Na__ToolOptions__Describe(:drawn_scale).reject do |option|
                NA_STRETCH_HIDDEN_OPTIONS.include?(option[:id].to_s)
            end
        rescue StandardError
            []
        end
        # ---------------------------------------------------------------

        # FUNCTION | Nothing May Scale Here
        # ------------------------------------------------------------
        def na_scale__stretch_only?
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Console Banner Hint Lines
        # ------------------------------------------------------------
        def na_drawn__activation_hints
            [
                'Deep Stretch: Deep Scale locked to stretching — every grip stretches, so frames and details keep their size',
                'To scale instead, leave it (Space) and use Deep Scale: SHIFT+TAB, UNIFORM and NON-UNIFORM are refused here',
                'Select a group or component first, or several (SHIFT+click adds another, again takes it out), or hover one and click it',
                'Each axis stretches at a plane through its centre until you place your own: click a dashed centre line, or hold CTRL over the object',
                'Drag a diamond to move a plane; SHIFT drops a mirrored pair; DEL or a double-click removes one you placed',
                'Drag a grip to stretch, release or click again to place — one undo step. SHIFT moves every axis together',
                'Click a dimension and type its size: 1200, +50, -25 — it stretches at once',
                "Sizes snap to the #{Na__NobleDrawingTools.Na__DrawnSettings__GridStepLabel} grid; hold CTRL to snap the grip to a point instead; TAB stretches about the centre",
                'Give it its own key: Preferences > Shortcuts, Extensions > Na__NobleDrawingTools > Deep Stretch'
            ]
        end
        # ---------------------------------------------------------------

    end # End DrawnStretchTool class

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Public Entry Point
    # -----------------------------------------------------------------------------

    # FUNCTION | Activate the Deep Stretch Tool (Hotkey Entry Point)
    # ------------------------------------------------------------
    def self.Na__NobleDrawingTools__DeepStretch
        Na__NobleDrawingTools.Na__ModeSwitch__ActivateDrawnStretchTool
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__NobleDrawingTools module

# =============================================================================
# END OF DEEP STRETCH TOOL
# =============================================================================
