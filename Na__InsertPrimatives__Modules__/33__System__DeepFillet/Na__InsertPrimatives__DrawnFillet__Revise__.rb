# =============================================================================
# NA INSERT PRIMATIVES - DEEP FILLET REVISE
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnFillet__Revise__.rb
# NAMESPACE  : Na__InsertPrimatives::DrawnFilletRevise
# AUTHOR     : Noble Architecture
# PURPOSE    : Where Deep Fillet's retype and repeat differ from the chamfer's
# CREATED    : 2026
#
# DESCRIPTION:
# - Deep Fillet inherits the chamfer's whole revise half (DrawnChamferRevise),
#   and the profile-aware capture and ghost every profile tool shares
#   (DrawnProfileSweepTool). What is left here is what a fillet means:
#     * its own remembered radius in the model dictionary
#     * its name in messages
#     * a typed radius, relative to the placed one when signed
#
# WHAT A REBUILD WEARS:
# - The tool's profile state ({ :kind, :sides_typed, :sides }) is merged into
#   the retype record by the shared capture. A retyped radius rebuilds with
#   the record's kind and its TYPED side count — nil when the sides were
#   automatic, so a fillet retyped from R5 to R500 takes the R500 count, and
#   one given "24s" keeps 24 at any radius. "##s" and TAB after a cut are
#   handled by the tool, which hands the rebuild a copy of the record asking
#   for the new count or kind.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../31__System__DeepChamfer/Na__InsertPrimatives__DrawnChamfer__Revise__'
require_relative '../03__AppUtils/Na__InsertPrimatives__DrawnVcbArithmetic__'

module Na__InsertPrimatives

    # @delegate: ../06__Tools__DrawnShared/Na__InsertPrimatives__DrawnProfileSweepTool__.rb

    module DrawnFilletRevise

        # -----------------------------------------------------------------------------
        # REGION | Host Contract — Identity and Wording
        # -----------------------------------------------------------------------------

        # FUNCTION | Where the Last Radius Lives in the Model Dictionary
        # ------------------------------------------------------------
        def na_revise__memory_key
            NA_TOOL_MEMORY_FILLET_KEY
        end
        # ---------------------------------------------------------------

        # FUNCTION | What the Operation Is Called in Messages
        # ------------------------------------------------------------
        def na_revise__noun
            'fillet'
        end
        # ---------------------------------------------------------------

        # FUNCTION | What a Leading Sign Means When Retyping — and the Rest
        # ------------------------------------------------------------
        def na_revise__sign_hint
            ' (+5 / -5 adjust it, 12s re-sides it, TAB swaps round and cove)'
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Size as "R40"
        # ------------------------------------------------------------
        def na_revise__value_label(value)
            "R#{Na__InsertPrimatives.Na__DrawnFormat__Mm(value).abs}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Read a Typed Radius, Relative to the Placed One If Signed
        # Side counts never reach here — the tool takes "##s" first.
        # ------------------------------------------------------------
        def na_revise__parse_retype(text, record)
            tokens = Na__InsertPrimatives.Na__DrawnVcb__ParseEntry(text)
            raise ArgumentError, 'fillet takes a single radius' if tokens.length > 1

            token = tokens[0]
            raise ArgumentError, 'no radius entered' if token.nil?

            radius = Na__InsertPrimatives.Na__DrawnVcb__ApplyToken(token, record[:value])

            unless Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(radius)
                raise ArgumentError,
                      "radius would be #{Na__InsertPrimatives.Na__DrawnFormat__Mm(radius)}mm — must be positive"
            end

            radius.to_f.abs
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnFilletRevise module

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP FILLET REVISE MODULE
# =============================================================================
