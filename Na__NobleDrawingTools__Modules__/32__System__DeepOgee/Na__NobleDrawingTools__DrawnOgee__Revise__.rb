# =============================================================================
# NA NOBLE DRAWING TOOLS - DEEP OGEE REVISE
# =============================================================================
#
# FILE       : Na__NobleDrawingTools__DrawnOgee__Revise__.rb
# NAMESPACE  : Na__NobleDrawingTools::DrawnOgeeRevise
# AUTHOR     : Noble Architecture
# PURPOSE    : Where Deep Ogee's retype and repeat differ from the chamfer's
# CREATED    : 2026
#
# DESCRIPTION:
# - Deep Ogee inherits the chamfer's whole revise half (DrawnChamferRevise):
#   an ogee edge is remembered, found again after an undo and rebuilt exactly
#   the way a chamfered one is. The profile-aware capture and the ghost are
#   shared by every profile tool (06__Tools__DrawnShared, DrawnProfileSweep-
#   Tool). What is left here is what an ogee means:
#     * its own remembered size in the model dictionary
#     * its name in messages
#     * "48s" typed after a cut re-cuts the same ogee smoother, at its size
#
# WHICH WAY ROUND A REBUILD CUTS:
# - The tool's profile state ({ :flip, :sides }) is merged into the retype
#   record by the shared capture, so a retype rebuilds the ogee the way round
#   it was cut, whatever TAB has done since — and TAB straight after a cut
#   rebuilds it the other way on purpose, by handing the rebuild a copy of
#   the record that says so.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../31__System__DeepChamfer/Na__NobleDrawingTools__DrawnChamfer__Revise__'
require_relative '../03__AppUtils/Na__NobleDrawingTools__DrawnVcbArithmetic__'

module Na__NobleDrawingTools

    # @delegate: ../06__Tools__DrawnShared/Na__NobleDrawingTools__DrawnProfileSweepTool__.rb

    module DrawnOgeeRevise

        # -----------------------------------------------------------------------------
        # REGION | Host Contract — Identity and Wording
        # -----------------------------------------------------------------------------

        # FUNCTION | Where the Last Size Lives in the Model Dictionary
        # ------------------------------------------------------------
        def na_revise__memory_key
            NA_TOOL_MEMORY_OGEE_KEY
        end
        # ---------------------------------------------------------------

        # FUNCTION | What the Operation Is Called in Messages
        # ------------------------------------------------------------
        def na_revise__noun
            'ogee'
        end
        # ---------------------------------------------------------------

        # FUNCTION | What a Leading Sign Means When Retyping — and TAB
        # ------------------------------------------------------------
        def na_revise__sign_hint
            ' (+5 / -5 adjust it, TAB turns it round)'
        end
        # ---------------------------------------------------------------

        # FUNCTION | Read a Typed Size, Relative to the Placed One If Signed
        # "48s" is not a size: it sets the curve's smoothness and hands back
        # the placed size, so the rebuild re-cuts the same ogee with more facets.
        # ------------------------------------------------------------
        def na_revise__parse_retype(text, record)
            segments = Na__NobleDrawingTools.Na__DrawnVcb__SegmentEntry(text)
            if segments
                Na__NobleDrawingTools.Na__DrawnSettings__SetCircleSegments(segments)
                return record[:value].to_f.abs
            end

            tokens = Na__NobleDrawingTools.Na__DrawnVcb__ParseEntry(text)
            raise ArgumentError, 'ogee takes a single size' if tokens.length > 1

            token = tokens[0]
            raise ArgumentError, 'no size entered' if token.nil?

            size = Na__NobleDrawingTools.Na__DrawnVcb__ApplyToken(token, record[:value])

            unless Na__NobleDrawingTools.Na__DrawnGeom__ValidDimension?(size)
                raise ArgumentError,
                      "size would be #{Na__NobleDrawingTools.Na__DrawnFormat__Mm(size)}mm — must be positive"
            end

            size.to_f.abs
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnOgeeRevise module

end # End Na__NobleDrawingTools module

# =============================================================================
# END OF DEEP OGEE REVISE MODULE
# =============================================================================
