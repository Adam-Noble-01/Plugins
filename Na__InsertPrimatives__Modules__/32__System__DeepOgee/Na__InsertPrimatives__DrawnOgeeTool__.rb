# =============================================================================
# NA INSERT PRIMATIVES - DEEP OGEE TOOL
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnOgeeTool__.rb
# NAMESPACE  : Na__InsertPrimatives
# CLASS      : DrawnOgeeTool  <  DrawnChamferTool
# AUTHOR     : Noble Architecture
# PURPOSE    : Run a classical ogee moulding along any edge, at any nesting
#              depth, the way Deep Chamfer runs a chamfer
# CREATED    : 2026
#
# DESCRIPTION:
# - Deep Chamfer with a different cut. Hover an edge, click to grab it, drag
#   into the corner to size the moulding, then click (or press Enter, or type
#   a size) to cut it. SHIFT+click banks edges and one drag moulds them all;
#   where two banked edges meet at a square corner the profiles MITRE like a
#   picture frame, so the four top edges of a box or a table top are one pass.
# - Everything but the curve is shared: the chamfer tool supplies the deep
#   pick, the SHIFT bank, the corner-plane drag, CTRL vertex snapping, grid
#   snapping, one undo step per group, retype and double-click repeat; the
#   profile sweep mixin (DrawnProfileSweepTool) plans, builds, mitres and
#   previews any profile and carries it through the retype ghost. This class
#   is the ogee's curve, TAB, and its words.
#
# THE SIZE:
# - The setback on each face, exactly as a chamfer's: a 40 ogee starts 40
#   back along one face and finishes 40 down the other. The profile itself
#   is described in Na__InsertPrimatives__DrawnOgee__Geometry__.rb.
#
# TAB — TURN IT ROUND:
# - An ogee has a way round: it rolls over off one face and finishes in a
#   crisp lip on the other. By default the face nearer horizontal rolls. TAB
#   turns that round for every edge being cut — mid-drag it flips the
#   preview, and straight after a cut it re-cuts that ogee the other way.
#   The choice is remembered between sessions.
#
# SMOOTHNESS:
# - Each quarter arc is a quarter of the Circle Sides setting: 24 gives 12
#   facets. "48s" in the measurements box doubles it, before a cut or after.
#
# CORNERS:
# - Two moulded edges meeting at a square corner mitre. Three meeting at one
#   corner (all three edges of a box corner) are refused with a message; the
#   curved three-way junction is not built yet.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../31__System__DeepChamfer/Na__InsertPrimatives__DrawnChamferTool__'
require_relative '../06__Tools__DrawnShared/Na__InsertPrimatives__DrawnProfileSweepTool__'
require_relative 'Na__InsertPrimatives__DrawnOgee__Geometry__'
require_relative 'Na__InsertPrimatives__DrawnOgee__Revise__'

module Na__InsertPrimatives

    # @delegate: Na__InsertPrimatives__DrawnOgee__Geometry__.rb
    # @delegate: Na__InsertPrimatives__DrawnOgee__Revise__.rb
    # @delegate: ../06__Tools__DrawnShared/Na__InsertPrimatives__DrawnProfileSweepTool__.rb
    # @delegate: ../04__GeometryHelpers/Na__InsertPrimatives__DrawnProfileSweep__.rb

    # -----------------------------------------------------------------------------
    # REGION | Deep Ogee Tool Class
    # -----------------------------------------------------------------------------

    # CLASS | Mould an Ogee on Any Edge at Any Nesting Depth
    # ------------------------------------------------------------
    class DrawnOgeeTool < DrawnChamferTool

        include Na__InsertPrimatives::DrawnOgeeRevise                         # <-- Over the chamfer's revise half: memory and wording
        include Na__InsertPrimatives::DrawnProfileSweepTool                   # <-- Last, so it sits first: plan, build, mitre, preview, ghost

        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Identity
        # -----------------------------------------------------------------------------

        # FUNCTION | Status Bar Title
        # ------------------------------------------------------------
        def na_drawn__tool_title
            'Deep Ogee'
        end
        # ---------------------------------------------------------------

        # FUNCTION | Popup Menu Highlight Key
        # ------------------------------------------------------------
        def na_drawn__mode_key
            :drawn_ogee
        end
        # ---------------------------------------------------------------

        # FUNCTION | Console Banner Hint Lines
        # ------------------------------------------------------------
        def na_drawn__activation_hints
            [
                'Hover an edge, click to grab it, drag into the corner, click to cut the moulding',
                'SHIFT+click banks edges, then one drag moulds them all — square corners mitre',
                'Reaches edges inside groups and components without opening them',
                "Size snaps to the #{Na__InsertPrimatives.Na__DrawnSettings__GridStepLabel} grid — hold CTRL for vertex snapping",
                'TAB turns the ogee round — mid-drag, or straight after a cut to re-cut it the other way',
                "VCB: 40 | +5 | -5 sizes it   48s smooths the curve (now #{Na__InsertPrimatives.Na__DrawnSettings__CircleSegments} sides)",
                'After cutting, keep typing: 60 resizes the ogee, +5 / -5 adjust it',
                'Double-click an edge to mould it at the last size placed (remembered in the model)',
                'The edge must border exactly two faces'
            ]
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Cut Hooks — the Ogee's Words and Curve
        # -----------------------------------------------------------------------------

        # FUNCTION | What the Cut Is Called, for Messages and Undo Names
        # ------------------------------------------------------------
        def na_drawn__cut_title
            'Ogee'
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Cut With Its Article, for Messages
        # ------------------------------------------------------------
        def na_drawn__cut_phrase
            'an ogee'
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Cut as a Verb, for Messages
        # ------------------------------------------------------------
        def na_drawn__cut_verb
            'mould'
        end
        # ---------------------------------------------------------------

        # FUNCTION | Solve One Edge at a World Size
        # Plan, build and mitre come from DrawnProfileSweepTool.
        # ------------------------------------------------------------
        def na_drawn__solve_cut(target, setback)
            Na__InsertPrimatives.Na__DrawnOgee__Solve(
                target, setback, na_drawn__ogee_flipped?, na_drawn__ogee_arc_segments
            )
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Profile Settings
        # -----------------------------------------------------------------------------

        # FUNCTION | Is the Ogee Turned Round?
        # A rebuild answers with the way round the ogee it is rebuilding was cut,
        # so a retype never quietly turns an ogee round because TAB was pressed
        # in between. Only TAB's own re-cut asks for the other way, on purpose,
        # by handing the rebuild a record that says so.
        # ------------------------------------------------------------
        def na_drawn__ogee_flipped?
            replaying = @na_revise_replaying
            return (replaying[:flip] ? true : false) if replaying && replaying.key?(:flip)

            Na__InsertPrimatives.Na__DrawnSettings__OgeeFlipped?
        end
        # ---------------------------------------------------------------

        # FUNCTION | Facets per Quarter Arc, From the Circle Sides Setting
        # ------------------------------------------------------------
        def na_drawn__ogee_arc_segments
            sides = Na__InsertPrimatives.Na__DrawnSettings__CircleSegments.to_f
            [(sides / 4.0).round, NA_OGEE_MIN_ARC_SEGMENTS].max
        end
        # ---------------------------------------------------------------

        # FUNCTION | What Shapes an Ogee Besides Its Size
        # Merged into the retype record by the shared capture, and compared to
        # tell when the replay ghost is a different curve.
        # ------------------------------------------------------------
        def na_drawn__profile_state
            { :flip => na_drawn__ogee_flipped?, :sides => Na__InsertPrimatives.Na__DrawnSettings__CircleSegments }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Which Face the Driver's Ogee Rolls Off, in Words
        # ------------------------------------------------------------
        def na_drawn__roll_face_label(target, solve)
            return 'face' unless target && solve && target[:faces] && target[:faces].length == 2

            face   = solve[:roll_on_a] ? target[:faces][0] : target[:faces][1]
            normal = face.normal.transform(target[:transformation])
            return 'face' unless normal.length > 0

            level = normal.z.to_f / normal.length.to_f
            return 'top'       if level > 0.7
            return 'underside' if level < -0.7

            'side face'
        rescue StandardError
            'face'
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | TAB — Turn the Ogee Round
        # -----------------------------------------------------------------------------

        # FUNCTION | What TAB Does in This Tool
        # ------------------------------------------------------------
        def na_drawn__tab_hint
            'TAB turn round'
        end
        # ---------------------------------------------------------------

        # FUNCTION | TAB Turns the Ogee Round — Live, or on the One Just Cut
        # The setting always flips, so the next cut follows it. Mid-drag the
        # preview re-solves on the spot. Straight after a cut, while the retype
        # is still open, the ogee just made is re-cut the other way round through
        # the same undo-and-rebuild a typed size uses — handed a copy of its
        # record that asks for the new way round.
        # ------------------------------------------------------------
        def na_drawn__cycle_plane_lock(view)
            flipped = Na__InsertPrimatives.Na__DrawnSettings__ToggleOgeeFlip
            message = nil

            if @na_state == :picking_depth
                na_drawn__refresh_solve
                message = 'Ogee turned round — it now rolls off the other face'
            elsif na_revise__available?
                record  = @na_revise_record
                recut   = na_revise__rebuild_at(record.merge(:flip => flipped), record[:value], view)
                message = 'Ogee turned round — the one just cut has been re-cut the other way' if recut
            else
                message = 'Ogee turned round for the next cut'
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

        # FUNCTION | Draw the Moulding and Its Summary Card
        # ------------------------------------------------------------
        def na_drawn__draw_preview(view)
            solve = @na_ch_solve
            lines = []

            if solve
                size_mm = Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_size_d).abs
                edge_mm = Na__InsertPrimatives.Na__DrawnFormat__Mm(solve[:edge_len_world]).abs
                lines << "Ogee #{size_mm} mm · #{solve[:facets]} facets"
                lines << "rolls off the #{na_drawn__roll_face_label(@na_ch_target, solve)} (TAB turns it) · edge #{edge_mm} mm"
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
                text = na_drawn__locked?(:d) ? "[#{size}]" : size.to_s
                return "Ogee #{text} mm — CORNER PROBLEM: #{@na_ch_mitre_note}" if @na_ch_mitre_note
                return "Ogee #{text} mm — release or click to cut"
            end

            adjust = na_revise__status_hint

            if @na_ch_target
                return 'Edge borders more than two faces — pick another' unless @na_ch_target[:face_count] == 2
                return "Click to grab this edge#{na_drawn__focus_hint}#{adjust}"
            end

            if @na_ch_multi.any?
                return "#{@na_ch_multi.length} edge#{@na_ch_multi.length == 1 ? '' : 's'} banked — SHIFT+click adds, click one to mould them all#{adjust}"
            end

            "Hover an edge to mould an ogee on it, at any nesting depth#{na_drawn__focus_hint}#{adjust}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Measurements Box Label and Live Value
        # ------------------------------------------------------------
        def na_drawn__vcb_label_and_value
            return ['Ogee size', na_revise__vcb_value] if @na_state != :picking_depth

            ['Ogee size', na_drawn__format_sizes([@na_size_d])]
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Measurements Box Entry
        # -----------------------------------------------------------------------------

        # FUNCTION | A Size Pins and Cuts; "48s" Sets the Smoothness
        # "48s" is not a size. With a cut still open to retyping it re-cuts that
        # ogee smoother at its own size (the revise half reads it); mid-drag it
        # re-solves the preview; otherwise it is simply the setting for the
        # next cut. Anything else is the chamfer's entry, word for word.
        # ------------------------------------------------------------
        def na_drawn__handle_vcb_text(text, view)
            segments = Na__InsertPrimatives.Na__DrawnVcb__SegmentEntry(text)
            return super unless segments
            return na_revise__retype(text, view) if na_revise__available?

            count = Na__InsertPrimatives.Na__DrawnSettings__SetCircleSegments(segments)
            na_drawn__refresh_solve if @na_state == :picking_depth
            na_revise__notice("Ogee curve: #{count} circle sides — #{na_drawn__ogee_arc_segments * 2} facets")
            view.invalidate if view
            true
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Console Report
        # -----------------------------------------------------------------------------

        # FUNCTION | Console Report for a Completed Ogee
        # The chamfer tool calls this after a single-edge cut.
        # ------------------------------------------------------------
        def na_drawn__log_chamfer(target, solve)
            Na__InsertPrimatives.Na__Debug__Puts "\n"
            Na__InsertPrimatives.Na__Debug__Puts '----------------------------------------'
            Na__InsertPrimatives.Na__Debug__Puts 'DEEP OGEE CUT'
            Na__InsertPrimatives.Na__Debug__Puts "Target : #{Na__InsertPrimatives.Na__DeepPick__PathLabel(target)}"
            Na__InsertPrimatives.Na__Debug__Puts "Size   : #{Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_size_d).abs}mm on each face"
            Na__InsertPrimatives.Na__Debug__Puts "Profile: #{solve[:facets]} facets, rolls off the #{na_drawn__roll_face_label(target, solve)}#{na_drawn__ogee_flipped? ? ' (turned round)' : ''}"
            Na__InsertPrimatives.Na__Debug__Puts "Edge   : #{Na__InsertPrimatives.Na__DrawnFormat__Mm(solve[:edge_len_world]).abs}mm long"
            Na__InsertPrimatives.Na__Debug__Puts "Instances affected: #{target[:shared_count]}"
            Na__InsertPrimatives.Na__Debug__Puts "Grid   : #{Na__InsertPrimatives.Na__DrawnSettings__GridStepLabel}"
            Na__InsertPrimatives.Na__Debug__Puts '----------------------------------------'
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnOgeeTool class

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Public Entry Point
    # -----------------------------------------------------------------------------

    # FUNCTION | Activate the Deep Ogee Tool (Hotkey Entry Point)
    # ------------------------------------------------------------
    # Bind in Preferences -> Shortcuts against the Extensions menu item, or call
    # directly: Na__InsertPrimatives.Na__InsertPrimatives__DeepOgee
    # ------------------------------------------------------------
    def self.Na__InsertPrimatives__DeepOgee
        Na__InsertPrimatives.Na__ModeSwitch__ActivateDrawnOgeeTool
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP OGEE TOOL MODULE
# =============================================================================
