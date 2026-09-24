# =============================================================================
# NA INSERT PRIMATIVES - DEEP FILLET TOOL
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnFilletTool__.rb
# NAMESPACE  : Na__InsertPrimatives
# CLASS      : DrawnFilletTool  <  DrawnChamferTool
# AUTHOR     : Noble Architecture
# PURPOSE    : Round any edge to a true radius, at any nesting depth, the way
#              Deep Chamfer chamfers one
# CREATED    : 2026
#
# DESCRIPTION:
# - Hover an edge, click to grab it, drag into the corner — the arc follows
#   the cursor — then click (or press Enter, or type a radius) to cut it.
#   SHIFT+click banks edges and one drag rounds them all; where two banked
#   edges meet at a square corner the fillets mitre like a picture frame.
# - Everything but the curve is shared: the chamfer tool supplies the deep
#   pick, the bank, the drag, CTRL vertex snapping, grid snapping, one undo
#   step per group, retype and double-click repeat; the profile sweep mixin
#   (DrawnProfileSweepTool) plans, builds, mitres and previews the arc and
#   carries it through the retype ghost. This class is the fillet's radius,
#   its sides, TAB, and its words.
#
# THE SIZE IS THE RADIUS:
# - A true radius at any corner angle (see the geometry file). On a square
#   corner the fillet starts r back along each face; on any other it starts
#   wherever an arc of that radius touches.
#
# SIDES — AUTOMATIC UNLESS TYPED:
# - The arc takes 6 sides under R10, 12 up to R200, 24 up to R2000 and 48
#   beyond (Na__DrawnFillet__AutoSides). Typing "##s" sets the sides of the
#   fillet in hand: mid-drag it re-draws the preview, straight after a cut it
#   re-cuts that fillet, and with nothing grabbed it waits for the next one.
#   A typed count belongs to the fillet it was typed for — it stays with it
#   through retyped radii, and the next fillet goes back to automatic.
#
# TAB — ROUND OR COVE:
# - TAB swaps the round-over for a cove of the same radius (a quarter hollow
#   meeting both faces square) — mid-drag on the preview, or straight after a
#   cut by re-cutting it. The choice is remembered between sessions.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../31__System__DeepChamfer/Na__InsertPrimatives__DrawnChamferTool__'
require_relative '../06__Tools__DrawnShared/Na__InsertPrimatives__DrawnProfileSweepTool__'
require_relative 'Na__InsertPrimatives__DrawnFillet__Geometry__'
require_relative 'Na__InsertPrimatives__DrawnFillet__Revise__'

module Na__InsertPrimatives

    # @delegate: Na__InsertPrimatives__DrawnFillet__Geometry__.rb
    # @delegate: Na__InsertPrimatives__DrawnFillet__Revise__.rb
    # @delegate: ../06__Tools__DrawnShared/Na__InsertPrimatives__DrawnProfileSweepTool__.rb

    # -----------------------------------------------------------------------------
    # REGION | Deep Fillet Tool Class
    # -----------------------------------------------------------------------------

    # CLASS | Round Any Edge to a Radius at Any Nesting Depth
    # ------------------------------------------------------------
    class DrawnFilletTool < DrawnChamferTool

        include Na__InsertPrimatives::DrawnFilletRevise                       # <-- Over the chamfer's revise half: memory and wording
        include Na__InsertPrimatives::DrawnProfileSweepTool                   # <-- Last, so it sits first: plan, build, mitre, preview, ghost

        # INITIALIZE | Tool Constructor
        # ------------------------------------------------------------
        def initialize
            super
            @na_fl_sides_typed = nil                                          # <-- "##s" for the fillet in hand; nil is automatic
        end
        # ---------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Identity
        # -----------------------------------------------------------------------------

        # FUNCTION | Status Bar Title
        # ------------------------------------------------------------
        def na_drawn__tool_title
            'Deep Fillet'
        end
        # ---------------------------------------------------------------

        # FUNCTION | Popup Menu Highlight Key
        # ------------------------------------------------------------
        def na_drawn__mode_key
            :drawn_fillet
        end
        # ---------------------------------------------------------------

        # FUNCTION | Console Banner Hint Lines
        # ------------------------------------------------------------
        def na_drawn__activation_hints
            [
                'Hover an edge, click to grab it, drag into the corner (the arc follows the cursor), click to cut',
                'SHIFT+click banks edges, then one drag rounds them all — square corners mitre',
                'Reaches edges inside groups and components without opening them',
                "Radius snaps to the #{Na__InsertPrimatives.Na__DrawnSettings__GridStepLabel} grid — hold CTRL for vertex snapping",
                'Sides are automatic: 6 under R10, 12 to R200, 24 to R2000, 48 beyond',
                'VCB: 40 sets R40 | +5 | -5 | 12s sets the sides of the fillet in hand',
                'TAB swaps round-over and cove — mid-drag, or straight after a cut to re-cut it',
                'After cutting, keep typing: 60 re-cuts at R60, 24s re-cuts it with 24 sides',
                'Double-click an edge to round it at the last radius placed (remembered in the model)',
                'The edge must border exactly two faces'
            ]
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Cut Hooks — the Fillet's Words and Curve
        # -----------------------------------------------------------------------------

        # FUNCTION | What the Cut Is Called, for Messages and Undo Names
        # ------------------------------------------------------------
        def na_drawn__cut_title
            'Fillet'
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Cut With Its Article, for Messages
        # ------------------------------------------------------------
        def na_drawn__cut_phrase
            'a fillet'
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Cut as a Verb, for Messages
        # ------------------------------------------------------------
        def na_drawn__cut_verb
            'fillet'
        end
        # ---------------------------------------------------------------

        # FUNCTION | Solve One Edge at a World Radius
        # Plan, build and mitre come from DrawnProfileSweepTool.
        # ------------------------------------------------------------
        def na_drawn__solve_cut(target, setback)
            Na__InsertPrimatives.Na__DrawnFillet__Solve(
                target, setback, na_drawn__fillet_kind, na_drawn__fillet_sides(setback)
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | Read the Drag as a Radius, With the Arc Under the Cursor
        # The chamfer reads the drag so its chord passes under the cursor. For
        # a round the arc's nearest point to the corner sits r(1/sin(half) - 1)
        # along the bisector, so that is what the travel is divided by; a
        # cove's deepest point is its radius from the edge, so the travel IS
        # the radius.
        # ------------------------------------------------------------
        def na_drawn__size_from_travel(travel)
            return travel.to_f if na_drawn__fillet_kind == :cove

            sin_half = Math.sqrt([1.0 - (@na_ch_cos_half.to_f ** 2), 0.0].max)
            reach    = sin_half > 0.0 ? (1.0 / sin_half) - 1.0 : 0.0
            reach > 1.0e-6 ? travel.to_f / reach : travel.to_f
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Fillet Settings
        # -----------------------------------------------------------------------------

        # FUNCTION | Round-Over or Cove
        # A rebuild answers with the kind the fillet it is rebuilding was cut
        # as, so a retype never quietly swaps it because TAB was pressed in
        # between. Only TAB's own re-cut asks for the other kind, on purpose.
        # ------------------------------------------------------------
        def na_drawn__fillet_kind
            replaying = @na_revise_replaying
            return (replaying[:kind] == :cove ? :cove : :round) if replaying && replaying.key?(:kind)

            Na__InsertPrimatives.Na__DrawnSettings__FilletCove? ? :cove : :round
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Typed Side Count for This Fillet, or nil for Automatic
        # A rebuild wears the count its record was cut with; anything else
        # wears whatever was typed for the fillet in hand.
        # ------------------------------------------------------------
        def na_drawn__fillet_sides_typed
            replaying = @na_revise_replaying
            return replaying[:sides_typed] if replaying && replaying.key?(:sides_typed)

            @na_fl_sides_typed
        end
        # ---------------------------------------------------------------

        # FUNCTION | How Many Sides a Fillet of This Radius Is Cut With
        # ------------------------------------------------------------
        def na_drawn__fillet_sides(radius)
            na_drawn__fillet_sides_typed || Na__InsertPrimatives.Na__DrawnFillet__AutoSides(radius)
        end
        # ---------------------------------------------------------------

        # FUNCTION | What Shapes a Fillet Besides Its Radius
        # Merged into the retype record by the shared capture, and compared to
        # tell when the replay ghost is a different curve.
        # ------------------------------------------------------------
        def na_drawn__profile_state
            {
                :kind        => na_drawn__fillet_kind,
                :sides_typed => na_drawn__fillet_sides_typed,
                :sides       => na_drawn__fillet_sides(@na_size_d)
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | How a Radius Reads in Labels
        # ------------------------------------------------------------
        def na_drawn__size_text(value)
            "R#{Na__InsertPrimatives.Na__DrawnFormat__Mm(value).abs}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Sides Fragment for the Status Line and Summary
        # ------------------------------------------------------------
        def na_drawn__sides_text(radius)
            typed = na_drawn__fillet_sides_typed
            "#{na_drawn__fillet_sides(radius)} sides #{typed ? '(typed)' : '(auto)'}"
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Retype — the Typed Sides Belong to One Fillet
        # -----------------------------------------------------------------------------

        # FUNCTION | Arm the Retype, Then Let the Next Fillet Go Back to Automatic
        # The shared capture has already merged :sides_typed into the record, so
        # the fillet just cut keeps its count through any retyped radius. Only a
        # fresh cut clears it — a rebuild is the same fillet, still in hand.
        # ------------------------------------------------------------
        def na_revise__capture(members, solves, ops)
            super
            @na_fl_sides_typed = nil unless @na_revise_replaying
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | TAB — Round-Over or Cove
        # -----------------------------------------------------------------------------

        # FUNCTION | What TAB Does in This Tool
        # ------------------------------------------------------------
        def na_drawn__tab_hint
            'TAB round/cove'
        end
        # ---------------------------------------------------------------

        # FUNCTION | TAB Swaps Round-Over and Cove — Live, or on the One Just Cut
        # The setting always swaps, so the next fillet follows it. Mid-drag the
        # preview re-solves; straight after a cut, the fillet just made is re-cut
        # as the other kind through the same undo-and-rebuild a typed radius
        # uses, handed a copy of its record that asks for the new kind.
        # ------------------------------------------------------------
        def na_drawn__cycle_plane_lock(view)
            kind    = Na__InsertPrimatives.Na__DrawnSettings__ToggleFilletCove ? :cove : :round
            name    = kind == :cove ? 'cove' : 'round-over'
            message = nil

            if @na_state == :picking_depth
                na_drawn__refresh_solve
                message = "Fillet is now a #{name}"
            elsif na_revise__available?
                record  = @na_revise_record
                recut   = na_revise__rebuild_at(record.merge(:kind => kind), record[:value], view)
                message = "Fillet re-cut as a #{name}" if recut
            else
                message = "The next fillet will be a #{name}"
            end

            na_revise__notice(message) if message
            @na_last_status_text = nil
            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
            true
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Preview
        # -----------------------------------------------------------------------------

        # FUNCTION | Draw the Fillet and Its Summary Card
        # ------------------------------------------------------------
        def na_drawn__draw_preview(view)
            solve = @na_ch_solve
            lines = []

            if solve
                kind    = solve[:kind] == :cove ? 'cove' : 'round-over'
                back_mm = Na__InsertPrimatives.Na__DrawnFormat__Mm(solve[:setback_world]).abs
                edge_mm = Na__InsertPrimatives.Na__DrawnFormat__Mm(solve[:edge_len_world]).abs
                lines << "Fillet #{na_drawn__size_text(@na_size_d)} · #{na_drawn__sides_text(@na_size_d)}"
                lines << "#{kind} (TAB swaps) · #{back_mm} mm back on each face · edge #{edge_mm} mm"
            end

            na_drawn__draw_profile_preview(view, lines)
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
                size = Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_size_d).abs
                text = na_drawn__locked?(:d) ? "[R#{size}]" : "R#{size}"
                sides = na_drawn__sides_text(@na_size_d)
                return "Fillet #{text} · #{sides} — CORNER PROBLEM: #{@na_ch_mitre_note}" if @na_ch_mitre_note
                return "Fillet #{text} · #{sides} — release or click to cut"
            end

            adjust = na_revise__status_hint
            typed  = @na_fl_sides_typed ? " — next fillet #{@na_fl_sides_typed} sides (typed)" : ''

            if @na_ch_target
                return 'Edge borders more than two faces — pick another' unless @na_ch_target[:face_count] == 2
                return "Click to grab this edge#{typed}#{na_drawn__focus_hint}#{adjust}"
            end

            if @na_ch_multi.any?
                return "#{@na_ch_multi.length} edge#{@na_ch_multi.length == 1 ? '' : 's'} banked — SHIFT+click adds, click one to round them all#{typed}#{adjust}"
            end

            "Hover an edge to round it, at any nesting depth#{typed}#{na_drawn__focus_hint}#{adjust}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Measurements Box Label and Live Value
        # ------------------------------------------------------------
        def na_drawn__vcb_label_and_value
            return ['Fillet radius', na_revise__vcb_value] if @na_state != :picking_depth

            ['Fillet radius', na_drawn__format_sizes([@na_size_d])]
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Measurements Box Entry
        # -----------------------------------------------------------------------------

        # FUNCTION | A Radius Pins and Cuts; "##s" Sets the Sides of This Fillet
        # With a cut still open to retyping, "##s" re-cuts that fillet with the
        # new count at its own radius, through the same undo-and-rebuild a typed
        # radius uses. Mid-drag it re-draws the preview. With nothing grabbed it
        # waits for the next fillet. Anything else is the chamfer's entry.
        # ------------------------------------------------------------
        def na_drawn__handle_vcb_text(text, view)
            segments = Na__InsertPrimatives.Na__DrawnVcb__SegmentEntry(text)
            return super unless segments

            count = Na__InsertPrimatives.Na__DrawnFillet__ClampSides(segments)

            if na_revise__available?
                record = @na_revise_record
                recut  = na_revise__rebuild_at(record.merge(:sides_typed => count), record[:value], view)
                na_revise__notice("Fillet re-cut with #{count} sides") if recut
                return recut
            end

            @na_fl_sides_typed = count
            na_drawn__refresh_solve if @na_state == :picking_depth

            where = @na_state == :picking_depth ? 'this fillet' : 'the next fillet'
            na_revise__notice("#{count} sides for #{where} — the one after goes back to automatic")
            view.invalidate if view
            true
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Console Report
        # -----------------------------------------------------------------------------

        # FUNCTION | Console Report for a Completed Fillet
        # The chamfer tool calls this after a single-edge cut.
        # ------------------------------------------------------------
        def na_drawn__log_chamfer(target, solve)
            Na__InsertPrimatives.Na__Debug__Puts "\n"
            Na__InsertPrimatives.Na__Debug__Puts '----------------------------------------'
            Na__InsertPrimatives.Na__Debug__Puts 'DEEP FILLET CUT'
            Na__InsertPrimatives.Na__Debug__Puts "Target : #{Na__InsertPrimatives.Na__DeepPick__PathLabel(target)}"
            Na__InsertPrimatives.Na__Debug__Puts "Radius : #{na_drawn__size_text(@na_size_d)} #{solve[:kind] == :cove ? 'cove' : 'round-over'}, #{solve[:facets]} sides"
            Na__InsertPrimatives.Na__Debug__Puts "Setback: #{Na__InsertPrimatives.Na__DrawnFormat__Mm(solve[:setback_world]).abs}mm back on each face"
            Na__InsertPrimatives.Na__Debug__Puts "Edge   : #{Na__InsertPrimatives.Na__DrawnFormat__Mm(solve[:edge_len_world]).abs}mm long"
            Na__InsertPrimatives.Na__Debug__Puts "Instances affected: #{target[:shared_count]}"
            Na__InsertPrimatives.Na__Debug__Puts "Grid   : #{Na__InsertPrimatives.Na__DrawnSettings__GridStepLabel}"
            Na__InsertPrimatives.Na__Debug__Puts '----------------------------------------'
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnFilletTool class

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Public Entry Point
    # -----------------------------------------------------------------------------

    # FUNCTION | Activate the Deep Fillet Tool (Hotkey Entry Point)
    # ------------------------------------------------------------
    # Bind in Preferences -> Shortcuts against the Extensions menu item, or call
    # directly: Na__InsertPrimatives.Na__InsertPrimatives__DeepFillet
    # ------------------------------------------------------------
    def self.Na__InsertPrimatives__DeepFillet
        Na__InsertPrimatives.Na__ModeSwitch__ActivateDrawnFilletTool
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP FILLET TOOL MODULE
# =============================================================================
