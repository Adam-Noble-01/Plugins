# =============================================================================
# NA INSERT PRIMATIVES - DEEP CHAMFER / FILLET / OGEE HOT SWAP
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnChamfer__HotSwap__.rb
# NAMESPACE  : Na__InsertPrimatives::DrawnChamferHotSwap
# AUTHOR     : Noble Architecture
# PURPOSE    : Switch between Chamfer, Fillet and Ogee from the right-click menu
#              without losing the edges or the drag in hand
# CREATED    : 2026
#
# DESCRIPTION:
# - The three edge tools are one tool with three profiles, but the menu started
#   a fresh tool for each, so choosing Fillet halfway through a chamfer threw
#   away the banked edges and the drag and meant picking every edge again.
# - Now the running tool packs up what it holds and the new one unpacks it as
#   it starts:
#     the bank           every banked edge (preselected or SHIFT-picked),
#                        re-checked against the new profile; any it cannot cut
#                        is left out and counted
#     the drag           the same driver edge grabbed again at the same press
#                        point, so the whole batch is live under the new
#                        profile straight away: the preview simply redraws
#     the size           carried as the number it was (a 15 chamfer becomes an
#                        R15 fillet, a 15 ogee), trimmed to the new profile's
#                        own limit if it is over it; a typed size stays pinned
# - Nothing held, and the menu switches exactly as before. Picking the tool
#   already running keeps everything and says so.
# - The retype of a cut already made is not carried: that cut belongs to the
#   tool that made it.
#
# HOST CONTRACT — included by DrawnChamferTool after DrawnChamferLimit. Its
# activate calls na_hs__apply when a handover is pending, instead of reading
# the selection.
#
# =============================================================================

require 'sketchup.rb'

module Na__InsertPrimatives

    module DrawnChamferHotSwap

        # -----------------------------------------------------------------------------
        # REGION | The Menu Buttons
        # -----------------------------------------------------------------------------

        # FUNCTION | Deep Chamfer From the Menu
        # ------------------------------------------------------------
        def Na__DrawnMode__SetChamferMode
            na_hs__swap_to(:DrawnChamferTool) || super
        end
        # ---------------------------------------------------------------

        # FUNCTION | Deep Fillet From the Menu
        # ------------------------------------------------------------
        def Na__DrawnMode__SetFilletMode
            na_hs__swap_to(:DrawnFilletTool) || super
        end
        # ---------------------------------------------------------------

        # FUNCTION | Deep Ogee From the Menu
        # ------------------------------------------------------------
        def Na__DrawnMode__SetOgeeMode
            na_hs__swap_to(:DrawnOgeeTool) || super
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Handing Over
        # -----------------------------------------------------------------------------

        # FUNCTION | Switch to Another Profile Tool, Carrying What Is Held
        # false when there is nothing worth carrying: the caller then switches
        # the ordinary way.
        # ------------------------------------------------------------
        def na_hs__swap_to(class_name)
            return false unless Na__InsertPrimatives.const_defined?(class_name)

            klass    = Na__InsertPrimatives.const_get(class_name)
            snapshot = na_hs__snapshot
            return false unless snapshot

            if instance_of?(klass)
                na_revise__notice("Already #{na_drawn__tool_title} — the edges in hand are kept")
                return true
            end

            model = Sketchup.active_model
            return false unless model

            tool = klass.new
            tool.na_hs__receive(snapshot)
            model.select_tool(tool)
            true
        rescue StandardError => error
            Na__InsertPrimatives.Na__Debug__Puts "NA HOT SWAP: #{error.message} — switching the ordinary way"
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Everything the Next Profile Needs, or nil When Nothing Is Held
        # ------------------------------------------------------------
        def na_hs__snapshot
            dragging = @na_state == :picking_depth && @na_ch_target && @na_ch_target[:edge] && @na_ch_target[:edge].valid?
            bank     = (@na_ch_multi || []).select { |banked| banked[:edge] && banked[:edge].valid? }
            return nil unless dragging || bank.any?

            {
                :from        => na_drawn__tool_title,
                :bank        => bank,
                :ps_active   => @na_ps_active ? true : false,
                :ps_skipped  => @na_ps_skipped.to_i,
                :dragging    => dragging ? true : false,
                :driver      => dragging ? @na_ch_target : nil,
                :size        => @na_size_d.to_f,
                :locked      => na_drawn__locked?(:d),
                :press       => [@na_press_x, @na_press_y],
                :mouse       => [@na_last_mouse_x, @na_last_mouse_y],
                :travel_zero => @na_ch_travel_zero.to_f
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Hold a Handover Until This Tool Starts
        # ------------------------------------------------------------
        def na_hs__receive(snapshot)
            @na_hs_pending = snapshot
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is a Handover Waiting?
        # ------------------------------------------------------------
        def na_hs__pending?
            !@na_hs_pending.nil?
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Taking Over
        # -----------------------------------------------------------------------------

        # FUNCTION | Unpack a Handover as This Tool Starts
        # ------------------------------------------------------------
        # The bank first, re-checked against THIS profile. Then the drag: the
        # driver is grabbed again at the press point it was grabbed at, which
        # rebuilds the corner frame, the batch and this profile's limit, and the
        # carried size is laid over it. The mouse position is put back last, so
        # the next move measures from where the cursor really is.
        # ------------------------------------------------------------
        def na_hs__apply
            snapshot       = @na_hs_pending
            @na_hs_pending = nil
            return false unless snapshot

            model = Sketchup.active_model
            view  = model ? model.active_view : nil
            left  = 0

            snapshot[:bank].each do |banked|
                next unless banked[:edge] && banked[:edge].valid?

                if banked[:face_count] == 2 && na_drawn__solve_member(banked, 1.0)
                    @na_ch_multi << banked unless na_drawn__multi_index_of(banked)
                else
                    left += 1
                end
            end

            @na_ps_active  = snapshot[:ps_active] && @na_ch_multi.any?
            @na_ps_skipped = snapshot[:ps_skipped].to_i

            grabbed = snapshot[:dragging] && view && na_hs__regrab(view, snapshot)

            @na_last_mouse_x, @na_last_mouse_y = snapshot[:mouse]

            na_revise__notice(na_hs__summary(snapshot, grabbed, left))
            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
            true
        rescue StandardError => error
            Na__InsertPrimatives.Na__Debug__Puts "NA HOT SWAP: could not take over (#{error.message})"
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Grab the Driver Again and Lay the Carried Size Over It
        # ------------------------------------------------------------
        def na_hs__regrab(view, snapshot)
            driver = snapshot[:driver]
            return false unless driver && driver[:edge] && driver[:edge].valid?

            press_x, press_y = snapshot[:press]
            @na_last_mouse_x = press_x
            @na_last_mouse_y = press_y
            return false unless na_drawn__grab_edge(view, press_x, press_y, driver)

            @na_drag_press_active = false                                     # <-- The button is up by now: click-move-click from here
            @na_ch_travel_zero    = snapshot[:travel_zero].to_f

            size = snapshot[:size].to_f
            size = @na_ch_max_size.to_f if @na_ch_max_size && size > @na_ch_max_size.to_f

            @na_size_d = size
            @na_sign_d = 1.0
            na_drawn__lock_slot(:d) if snapshot[:locked]
            na_drawn__refresh_solve
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Say What Came Across
        # ------------------------------------------------------------
        def na_hs__summary(snapshot, grabbed, left)
            count = grabbed ? @na_ch_batch.length : @na_ch_multi.length
            edges = "#{count} edge#{count == 1 ? '' : 's'}"
            lost  = left > 0 ? " — #{left} could not take #{na_drawn__cut_phrase} and #{left == 1 ? 'was' : 'were'} left out" : ''

            if grabbed
                "#{snapshot[:from]} → #{na_drawn__tool_title}: the same #{edges}, previewed as #{na_drawn__cut_phrase}#{lost}"
            elsif snapshot[:dragging]
                "#{snapshot[:from]} → #{na_drawn__tool_title}: the edge being dragged cannot take #{na_drawn__cut_phrase} — #{edges} still banked#{lost}"
            else
                "#{snapshot[:from]} → #{na_drawn__tool_title}: #{edges} still banked#{lost}"
            end
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnChamferHotSwap module

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP CHAMFER / FILLET / OGEE HOT SWAP
# =============================================================================
