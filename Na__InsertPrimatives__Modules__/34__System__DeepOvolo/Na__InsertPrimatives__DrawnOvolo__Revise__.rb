# =============================================================================
# NA INSERT PRIMATIVES - DEEP OVOLO REVISE
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnOvolo__Revise__.rb
# NAMESPACE  : Na__InsertPrimatives::DrawnOvoloRevise
# AUTHOR     : Noble Architecture
# PURPOSE    : Where Deep Ovolo's retype and repeat differ from the chamfer's
# CREATED    : 2026
#
# DESCRIPTION:
# - Deep Ovolo inherits the chamfer's whole revise half (DrawnChamferRevise),
#   and the profile-aware capture and ghost every profile tool shares
#   (DrawnProfileSweepTool). What is left here is what an ovolo means:
#     * its own remembered radius in the model dictionary
#     * its name in messages — ovolo or cavetto, as the cut was made
#     * a placed size that reads as a radius AND a step ("R40 + 5 mm step")
#     * the radius part of a typed entry, for the shared parse
# - A typed step after a cut ("40,5", ",2") is the tool's own retype, which
#   hands the rebuild a copy of the record wearing the new step — the same
#   way Deep Fillet re-sides a fillet. "48s" re-cuts the same moulding with
#   a smoother arc, at its own size.
#
# WHAT A REBUILD WEARS:
# - The tool's profile state ({ :kind, :step, :sides }) is merged into the
#   retype record by the shared capture, so a retyped radius rebuilds the
#   moulding as it was cut — the same kind, the same step — whatever TAB or a
#   typed step has done since.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../31__System__DeepChamfer/Na__InsertPrimatives__DrawnChamfer__Revise__'
require_relative '../03__AppUtils/Na__InsertPrimatives__DrawnVcbArithmetic__'
require_relative 'Na__InsertPrimatives__DrawnOvolo__Geometry__'

module Na__InsertPrimatives

    # @delegate: ../06__Tools__DrawnShared/Na__InsertPrimatives__DrawnProfileSweepTool__.rb

    module DrawnOvoloRevise

        # -----------------------------------------------------------------------------
        # REGION | Host Contract — Identity and Wording
        # -----------------------------------------------------------------------------

        # FUNCTION | Where the Last Radius Lives in the Model Dictionary
        # ------------------------------------------------------------
        def na_revise__memory_key
            NA_TOOL_MEMORY_OVOLO_KEY
        end
        # ---------------------------------------------------------------

        # FUNCTION | What the Operation Is Called in Messages
        # The cut that was made, while it can still be retyped; otherwise the
        # kind the next cut will be.
        # ------------------------------------------------------------
        def na_revise__noun
            record = @na_revise_record
            kind   = record && record[:kind] ? record[:kind] : na_drawn__ovolo_kind
            kind == :cavetto ? 'cavetto' : 'ovolo'
        end
        # ---------------------------------------------------------------

        # FUNCTION | What a Leading Sign Means When Retyping — and the Rest
        # ------------------------------------------------------------
        def na_revise__sign_hint
            ' (40,5 sets radius and step, +5 / -5 the radius, ,2 the step, TAB ovolo/cavetto)'
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Size as "R40"
        # ------------------------------------------------------------
        def na_revise__value_label(value)
            "R#{Na__InsertPrimatives.Na__DrawnFormat__Mm(value).abs}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Placed Moulding as "R40 + 5 mm step"
        # ------------------------------------------------------------
        def na_revise__placed_label(record)
            "#{na_revise__value_label(record[:value])} + #{na_ov__mm_text(record[:step])} step"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Read the Radius a Typed Entry Asks For
        # The shared retype path calls this (the size check, and "48s"); a step
        # in the entry is the tool's own retype's business. "48s" is not a size:
        # it sets the arc's smoothness and hands back the placed radius.
        # ------------------------------------------------------------
        def na_revise__parse_retype(text, record)
            segments = Na__InsertPrimatives.Na__DrawnVcb__SegmentEntry(text)
            if segments
                Na__InsertPrimatives.Na__DrawnSettings__SetCircleSegments(segments)
                return record[:value].to_f.abs
            end

            entry  = Na__InsertPrimatives.Na__DrawnOvolo__ParseEntry(text)
            radius = entry[:radius] ? Na__InsertPrimatives.Na__DrawnVcb__ApplyToken(entry[:radius], record[:value]) : record[:value].to_f

            unless Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(radius)
                raise ArgumentError,
                      "radius would be #{Na__InsertPrimatives.Na__DrawnFormat__Mm(radius)}mm — must be positive"
            end

            radius.to_f.abs
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Length in mm to One Decimal Place, Without a Trailing ".0"
        # Steps are small, so the whole-millimetre rounding the radius uses
        # would turn a 0.5 step into "1".
        # ------------------------------------------------------------
        def na_ov__mm_text(value)
            "#{na_ov__mm_number(value)} mm"
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Same Number Bare, for the Measurements Box ("5", "0.5")
        # ------------------------------------------------------------
        def na_ov__mm_number(value)
            mm = (value.to_f * NA_DRAWN_INCH_TO_MM).abs.round(1)
            mm == mm.round ? mm.round.to_s : mm.to_s
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnOvoloRevise module

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP OVOLO REVISE MODULE
# =============================================================================
