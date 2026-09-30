# =============================================================================
# NA INSERT PRIMATIVES - DEEP CHAMFER PRESELECTED EDGES
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnChamfer__Preselect__.rb
# NAMESPACE  : Na__InsertPrimatives::DrawnChamferPreselect
# AUTHOR     : Noble Architecture
# PURPOSE    : Loose edges selected BEFORE the tool starts become the edges it
#              cuts: no hunting for them with the deep picker
# CREATED    : 2026
#
# DESCRIPTION:
# - Deep Chamfer, Deep Fillet and Deep Ogee reach into groups by hovering, and
#   several edges are gathered by SHIFT-banking them one at a time. For loose
#   geometry, which the user can already select with every native tool, that is
#   the long way round: select the edges first, then start the tool.
# - So on activation the selection is read ONCE:
#     edges (loose, in the open context)   they become the bank: drawn in the
#                                          bank colour, and every drag cuts them
#     a group or component anywhere in it  nothing changes: the deep picker runs
#                                          exactly as before, biased to the
#                                          selected group as it always was
#     nothing selected                     nothing changes
#   Faces in the selection are ignored; only its edges are candidates. An edge
#   that cannot be cut (not two faces, or two faces too near flat) is left out
#   and counted, so the status line can say how many were.
#
# WHILE THE SELECTION IS THE BANK:
# - Press anywhere and drag. The selected edge NEAREST the press drives the
#   measurement and every other one rides along at the same size, with the
#   whole batch previewed and mitred as a SHIFT bank always was. The drag is
#   measured from where the press landed, so pressing a little off the edge
#   does not open the cut with a jump.
# - SHIFT+click still adds or removes any edge, at any depth. BKSP un-banks the
#   newest, ESC clears the bank and puts the deep picker back. A successful cut
#   empties the bank, as it always did, and the retype stays open on the cut.
#
# HOST CONTRACT — included by DrawnChamferTool after DrawnChamferRevise. The
# host calls na_ps__adopt_selection from activate, routes an idle hover and an
# idle click through na_ps__active?, and reads @na_ch_travel_zero in its drag.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnDeepPick__'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnQuadRings__'

module Na__InsertPrimatives

    module DrawnChamferPreselect

        # -----------------------------------------------------------------------------
        # REGION | State
        # -----------------------------------------------------------------------------

        # FUNCTION | Nothing Preselected Yet
        # ------------------------------------------------------------
        def na_ps__init_state
            @na_ps_active  = false
            @na_ps_skipped = 0
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is the Selection Still the Bank?
        # Ends by itself when the bank empties: a cut, ESC, or BKSP to the last.
        # ------------------------------------------------------------
        def na_ps__active?
            return false unless @na_ps_active

            @na_ch_multi.delete_if { |banked| banked[:edge].nil? || !banked[:edge].valid? }
            @na_ps_active = false if @na_ch_multi.empty?
            @na_ps_active
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Reading the Selection
        # -----------------------------------------------------------------------------

        # FUNCTION | Bank the Selected Loose Edges, If the Selection Is Loose Edges
        # Returns how many were banked.
        # ------------------------------------------------------------
        def na_ps__adopt_selection
            @na_ps_active  = false
            @na_ps_skipped = 0

            model = Sketchup.active_model
            return 0 unless model

            selected = model.selection.to_a
            return 0 if selected.empty?

            # A group or component in the selection says "work in there", and the
            # deep picker already reads it that way. Leave everything to it.
            return 0 if selected.any? { |entity| entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance) }

            edges = selected.grep(Sketchup::Edge)
            return 0 if edges.empty?

            path = Na__InsertPrimatives.Na__DeepPick__ContextPath

            edges.each do |edge|
                next unless edge.valid?

                target = Na__InsertPrimatives.Na__DeepPick__BuildEdgeTarget(edge, path, nil)

                if target[:locked] || target[:face_count] != 2 || !na_drawn__solve_member(target, 1.0)
                    @na_ps_skipped += 1
                    next
                end

                @na_ch_multi << target unless na_drawn__multi_index_of(target)
            end

            @na_ps_active = @na_ch_multi.any?
            na_ps__announce(edges.length)
            @na_ch_multi.length
        rescue StandardError => error
            Na__InsertPrimatives.Na__Debug__Puts "NA #{na_drawn__cut_title.upcase}: the selection could not be read (#{error.message}) — deep picking as usual"
            @na_ps_active = false
            0
        end
        # ---------------------------------------------------------------

        # FUNCTION | Say What the Selection Became
        # A beat late, so the activation status line does not wipe it.
        # ------------------------------------------------------------
        def na_ps__announce(selected_count)
            count   = @na_ch_multi.length
            skipped = na_ps__skipped_note

            message =
                if @na_ps_active
                    "#{count} selected edge#{count == 1 ? '' : 's'} ready to #{na_drawn__cut_verb} — press and drag anywhere#{skipped}"
                else
                    "None of the #{selected_count} selected edge#{selected_count == 1 ? '' : 's'} can take #{na_drawn__cut_phrase} " \
                    '(each needs two faces at an angle) — hover an edge instead'
                end

            Na__InsertPrimatives.Na__Debug__Puts "NA #{na_drawn__cut_title.upcase}: #{message}"
            na_revise__notice(message)
        end
        # ---------------------------------------------------------------

        # FUNCTION | ", 2 left out (not two faces at an angle)", or ''
        # ------------------------------------------------------------
        def na_ps__skipped_note
            return '' if @na_ps_skipped.to_i.zero?

            ", #{@na_ps_skipped} left out (not two faces at an angle)"
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Hover and Grab
        # -----------------------------------------------------------------------------

        # FUNCTION | The Banked Edge Nearest the Cursor on Screen
        # The one a press here would drive the drag from. Falls back to the
        # first when none can be projected, so a press always has a driver.
        # ------------------------------------------------------------
        def na_ps__nearest(view, x, y)
            best      = nil
            best_dist = nil

            @na_ch_multi.each do |banked|
                edge  = banked[:edge]
                next unless edge && edge.valid?

                xform = banked[:transformation]
                px    = Na__InsertPrimatives.Na__QuadRings__ScreenDistance(
                    view, edge.start.position.transform(xform), edge.end.position.transform(xform), x, y
                )
                next unless px
                next unless best_dist.nil? || px < best_dist

                best      = banked
                best_dist = px
            end

            best || @na_ch_multi.first
        end
        # ---------------------------------------------------------------

        # FUNCTION | Press Anywhere: Grab the Nearest Selected Edge
        # The drag is zeroed where the press landed, so a press beside the
        # edge rather than on it starts the cut at nothing, not at the gap.
        # ------------------------------------------------------------
        def na_ps__grab(view, x, y)
            driver = na_ps__nearest(view, x, y)
            return false unless driver

            return false unless na_drawn__grab_edge(view, x, y, driver)

            start = na_drawn__corner_plane_point(view, x, y)
            @na_ch_travel_zero = start ? (start - @na_ch_anchor).dot(@na_ch_bisector).to_f : 0.0
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Line the Driver's Hover Label Gains
        # ------------------------------------------------------------
        def na_ps__highlight_note
            count = @na_ch_multi.length
            "drives #{count} selected edge#{count == 1 ? '' : 's'} — press and drag"
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Status Line While the Selection Is the Bank
        # ------------------------------------------------------------
        def na_ps__status_detail
            count = @na_ch_multi.length
            "#{count} selected edge#{count == 1 ? '' : 's'} — press and drag anywhere to #{na_drawn__cut_verb} them all " \
            "(nearest drives), SHIFT+click adds or removes, ESC back to hovering#{na_ps__skipped_note}#{na_revise__status_hint}"
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnChamferPreselect module

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP CHAMFER PRESELECTED EDGES
# =============================================================================
