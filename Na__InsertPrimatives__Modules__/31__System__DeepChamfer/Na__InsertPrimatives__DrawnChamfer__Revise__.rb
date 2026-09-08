# =============================================================================
# NA INSERT PRIMATIVES - DEEP CHAMFER REVISE
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnChamfer__Revise__.rb
# NAMESPACE  : Na__InsertPrimatives::DrawnChamferRevise
# AUTHOR     : Noble Architecture
# PURPOSE    : The chamfer half of the shared revise contract — capture,
#              re-acquire, rebuild, repeat and the ghost
# CREATED    : 2026
#
# DESCRIPTION:
# - DrawnReviseShared (06__Tools__DrawnShared) owns the mechanics every
#   modifier tool has in common. This module supplies what only a chamfer
#   knows:
#     * what to remember about a cut so it can be made again — the edge is
#       GONE once it is chamfered, so it is remembered by where its two ends
#       were, in the definition's own space
#     * how to find that edge again once the cut has been undone: the one
#       edge in the same collection whose ends sit on those two points
#     * how to run the commit path wearing the cut's targets, for one edge or
#       for a whole SHIFT-banked batch
#     * what a leading sign means when a setback is retyped
#     * what the sweeping ghost looks like
#
# THE SIGN IS ARITHMETIC HERE:
# - A setback has no direction to reverse, so the push tool's "minus turns it
#   round" reading would be meaningless. Instead the sign keeps the meaning it
#   has everywhere else in the plugin: "+5" is five more than the placed
#   setback, "-5" is five less, and a bare "50" is fifty.
#
# A BATCH MAY BE SEVERAL UNDO STEPS:
# - Edges banked across different groups are cut one operation per group, so
#   the record carries how many operations landed and the retype undoes that
#   many. Edges whose group refused the cut were never changed, and are not in
#   the record.
#
# THE GHOST IS THE SOLVE, SCALED:
# - Every chamfer point is the corner vertex plus an offset that grows in
#   proportion to the setback — including a mitred corner, whose plane
#   intersection scales the same way — so one solve at the placed setback
#   describes the cut at EVERY setback. The ghost interpolates by scaling
#   those offsets, and draws with the same cut-face painter the live drag uses.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../06__Tools__DrawnShared/Na__InsertPrimatives__DrawnRevise__'
require_relative '../03__AppUtils/Na__InsertPrimatives__DrawnVcbArithmetic__'
require_relative 'Na__InsertPrimatives__DrawnChamfer__Geometry__'

module Na__InsertPrimatives

    module DrawnChamferRevise

        # -----------------------------------------------------------------------------
        # REGION | Host Contract — Identity and Wording
        # -----------------------------------------------------------------------------

        # FUNCTION | Where the Last Setback Lives in the Model Dictionary
        # ------------------------------------------------------------
        def na_revise__memory_key
            NA_TOOL_MEMORY_CHAMFER_KEY
        end
        # ---------------------------------------------------------------

        # FUNCTION | What the Operation Is Called in Messages
        # ------------------------------------------------------------
        def na_revise__noun
            'chamfer'
        end
        # ---------------------------------------------------------------

        # FUNCTION | What Gets Grabbed, in Messages
        # ------------------------------------------------------------
        def na_revise__target_noun
            'an edge'
        end
        # ---------------------------------------------------------------

        # FUNCTION | What a Leading Sign Means When Retyping
        # ------------------------------------------------------------
        def na_revise__sign_hint
            ' (+5 / -5 adjust it)'
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Capture
        # -----------------------------------------------------------------------------

        # FUNCTION | Remember Each Edge About to Be Cut by Where Its Ends Are
        # Read BEFORE the cut, while the edges still exist. Positions are
        # definition-local and cloned — the cut erases the vertices, so a live
        # handle would be worthless a moment later.
        # ------------------------------------------------------------
        def na_revise__snapshot_members(targets, model)
            targets.map do |target|
                edge = target[:edge]
                next nil unless edge && edge.valid?

                parent   = edge.parent
                entities = parent.respond_to?(:entities) ? parent.entities : model.active_entities
                next nil unless entities

                {
                    :target   => target,
                    :entities => entities,
                    :v0       => edge.start.position.clone,
                    :v1       => edge.end.position.clone
                }
            end.compact
        rescue StandardError
            []
        end
        # ---------------------------------------------------------------

        # FUNCTION | Arm the Retype After a Successful Cut
        # `solves` are the final solved shapes the cut was built from (mitre
        # patches included) and feed the ghost; `ops` is how many operations
        # the cut took. During a rebuild the ghost is carried forward so every
        # retype sweeps from the same solved geometry.
        # ------------------------------------------------------------
        def na_revise__capture(members, solves, ops)
            return na_revise__forget if members.nil? || members.empty? || ops.to_i < 1

            model     = Sketchup.active_model
            replaying = @na_revise_replaying
            ghost     = replaying ? replaying[:ghost] : na_revise__build_ghost(solves)

            counts = members.map { |member| [member[:entities], na_revise__entity_count(member[:entities])] }

            na_revise__arm({
                :members   => members,
                :counts    => counts,
                :ops       => ops.to_i,
                :value     => @na_size_d.to_f.abs,
                :user_path => (model && model.respond_to?(:active_path) ? model.active_path : nil),
                :ghost     => ghost
            })
        rescue StandardError => error
            Na__InsertPrimatives.Na__Debug__Puts "NA CHAMFER: retype not armed — #{error.message}"
            na_revise__forget
        end
        # ---------------------------------------------------------------

        # FUNCTION | Copy the Solved World Points Out for the Ghost
        # ------------------------------------------------------------
        def na_revise__build_ghost(solves)
            shapes = (solves || []).compact.map do |solve|
                world = solve[:world]
                next nil unless world.is_a?(Hash)

                copied = {}
                world.each { |key, point| copied[key] = point ? point.clone : nil }

                { :world => copied, :mitre0 => solve[:mitre0], :mitre1 => solve[:mitre1] }
            end.compact

            { :from_setback => @na_size_d.to_f.abs, :solves => shapes }
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Host Contract — Re-Acquire After the Undo
        # -----------------------------------------------------------------------------

        # FUNCTION | The Edge Whose Ends Sit on Two Recorded Points, or nil
        # Either way round: an undo is under no obligation to hand the edge
        # back with the same start and end it had.
        # ------------------------------------------------------------
        def na_revise__edge_between(entities, v0, v1)
            return nil unless entities && v0 && v1

            entities.grep(Sketchup::Edge).find do |edge|
                next false unless edge.valid?

                start_point = edge.start.position
                end_point   = edge.end.position

                (Na__InsertPrimatives.Na__DrawnChamfer__SamePoint?(start_point, v0) &&
                 Na__InsertPrimatives.Na__DrawnChamfer__SamePoint?(end_point, v1)) ||
                (Na__InsertPrimatives.Na__DrawnChamfer__SamePoint?(start_point, v1) &&
                 Na__InsertPrimatives.Na__DrawnChamfer__SamePoint?(end_point, v0))
            end
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Find Every Recorded Edge Again Where the Undo Put It Back
        # All or nothing: a batch that cannot be fully re-found is not rebuilt
        # in part.
        # ------------------------------------------------------------
        def na_revise__reacquire(record)
            targets = []

            record[:members].each do |member|
                edge = na_revise__edge_between(member[:entities], member[:v0], member[:v1])
                return nil unless edge

                faces = edge.faces
                return nil unless faces.length == 2

                targets << member[:target].merge(:edge => edge, :faces => faces, :face_count => faces.length)
            end

            targets.empty? ? nil : targets
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Host Contract — Rebuild and Repeat
        # -----------------------------------------------------------------------------

        # FUNCTION | Run the Commit Path Again at a Setback
        # ------------------------------------------------------------
        def na_revise__rebuild(record, targets, value, view)
            placed = false

            na_revise__wearing(record, targets, value) do
                placed = na_drawn__commit_chamfer(view)
            end

            placed ? true : false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Wear the Targets and Setback the Recorded Cut Was Made With
        # The commit path takes the single-edge route when the batch holds one
        # target and the grouped route otherwise, exactly as it does off a drag.
        # ------------------------------------------------------------
        def na_revise__wearing(record, targets, value)
            @na_revise_replaying = record
            @na_ch_target        = targets.first
            @na_ch_batch         = targets
            @na_ch_batch_solves  = []
            @na_size_d           = value.to_f.abs
            @na_sign_d           = 1.0

            yield
        ensure
            @na_revise_replaying = nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Read a Typed Setback, Relative to the Placed One If Signed
        # ------------------------------------------------------------
        def na_revise__parse_retype(text, record)
            tokens = Na__InsertPrimatives.Na__DrawnVcb__ParseEntry(text)
            raise ArgumentError, 'chamfer takes a single setback' if tokens.length > 1

            token = tokens[0]
            raise ArgumentError, 'no setback entered' if token.nil?

            setback = Na__InsertPrimatives.Na__DrawnVcb__ApplyToken(token, record[:value])

            unless Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(setback)
                raise ArgumentError,
                      "setback would be #{Na__InsertPrimatives.Na__DrawnFormat__Mm(setback)}mm — must be positive"
            end

            setback.to_f.abs
        end
        # ---------------------------------------------------------------

        # FUNCTION | Cut the Grabbed Edge (and Any Banked With It) at the Remembered Setback
        # ------------------------------------------------------------
        def na_revise__apply_repeat(value, view)
            @na_size_d = value.to_f.abs
            @na_sign_d = 1.0
            na_drawn__lock_slot(:d)
            na_drawn__refresh_solve
            na_drawn__commit_chamfer(view)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Host Contract — The Ghost
        # -----------------------------------------------------------------------------

        # FUNCTION | A Solved Shape Re-Scaled to Another Setback
        # Each offset point is pulled toward or pushed away from its own corner
        # vertex by the ratio of the two setbacks. v0 and v1 do not move.
        # ------------------------------------------------------------
        def na_revise__scaled_world(world, scale)
            v0 = world[:v0]
            v1 = world[:v1]
            return nil unless v0 && v1

            scaled = { :v0 => v0, :v1 => v1 }

            [[:a0, v0], [:b0, v0], [:corner0, v0], [:a1, v1], [:b1, v1], [:corner1, v1]].each do |key, base|
                point = world[key]
                next unless point

                scaled[key] = Geom::Point3d.new(
                    base.x.to_f + ((point.x.to_f - base.x.to_f) * scale),
                    base.y.to_f + ((point.y.to_f - base.y.to_f) * scale),
                    base.z.to_f + ((point.z.to_f - base.z.to_f) * scale)
                )
            end

            scaled
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw Every Recorded Cut at an Interpolated Setback
        # ------------------------------------------------------------
        def na_revise__draw_ghost(view, ghost, value, from_value, to_value)
            from_setback = ghost[:from_setback].to_f
            return false unless from_setback > 0.0

            scale = value.to_f.abs / from_setback
            label_anchor = nil

            (ghost[:solves] || []).each do |solve|
                scaled = na_revise__scaled_world(solve[:world], scale)
                next unless scaled

                na_drawn__draw_cut_faces(view, { :world => scaled, :mitre0 => solve[:mitre0], :mitre1 => solve[:mitre1] })
                label_anchor ||= scaled[:a1]
            end

            return false unless label_anchor

            from_mm = Na__InsertPrimatives.Na__DrawnFormat__Mm(from_value).abs
            to_mm   = Na__InsertPrimatives.Na__DrawnFormat__Mm(to_value).abs

            Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(
                view, label_anchor,
                ["Chamfer #{from_mm} → #{to_mm} mm"],
                14, -26, NA_DRAWN_TEXT_ACCENT_COLOR
            )
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Every Point the Ghost Occupies at a Setback, for the Extents
        # ------------------------------------------------------------
        def na_revise__ghost_points(ghost, value)
            from_setback = ghost[:from_setback].to_f
            return [] unless from_setback > 0.0

            scale  = value.to_f.abs / from_setback
            points = []

            (ghost[:solves] || []).each do |solve|
                scaled = na_revise__scaled_world(solve[:world], scale)
                next unless scaled

                points.concat(scaled.values.compact)
            end

            points
        rescue StandardError
            []
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnChamferRevise module

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP CHAMFER REVISE MODULE
# =============================================================================
