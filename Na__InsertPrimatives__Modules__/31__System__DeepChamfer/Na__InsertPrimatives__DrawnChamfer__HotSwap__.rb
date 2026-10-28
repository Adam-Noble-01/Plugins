# =============================================================================
# NA INSERT PRIMATIVES - DEEP CHAMFER / FILLET / OGEE / OVOLO HOT SWAP
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnChamfer__HotSwap__.rb
# NAMESPACE  : Na__InsertPrimatives::DrawnChamferHotSwap
# AUTHOR     : Noble Architecture
# PURPOSE    : Switch between Chamfer, Fillet, Ogee and Ovolo from the right-click
#              menu, SHIFT+TAB or the tools' own menu commands, without losing
#              the edges or the drag in hand
# CREATED    : 2026
#
# DESCRIPTION:
# - The edge tools are one tool with four profiles, but the menu started a
#   fresh tool for each, so choosing Fillet halfway through a chamfer threw
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
#                        own limit if it is over it; a typed size stays pinned;
#                        the scrub carries on from it without a jump
# - Nothing held, and the switch is the ordinary one. Asking for the tool
#   already running keeps everything and says so.
# - The retype of a cut already made is not carried: that cut belongs to the
#   tool that made it.
#
# THREE WAYS TO SWITCH (5.2.9):
#   right-click menu    Deep Chamfer / Deep Fillet / Deep Ogee / Deep Ovolo
#   SHIFT+TAB           the next profile: Chamfer, Fillet, Ogee, Ovolo, and
#                       round again (the plugin's second-switch key, as in
#                       Drawn Volume and Deep Scale). TAB on its own stays each
#                       profile's own switch: round or cove, turn round,
#                       ovolo or cavetto
#   menu commands       Extensions > Na__InsertPrimitives > Deep Chamfer and
#                       the rest, bound to keys in Preferences > Shortcuts.
#                       Pressed while one of the four runs, a command hands
#                       over like the menu instead of starting empty
#
# WHY NOT C R O G V ANY MORE (5.2.9):
# - 5.1.22 took those letters typed on their own. They never got the chance:
#   SketchUp's own shortcuts (C Circle, R Rectangle, O Orbit, G Make
#   Component) are handled by the application before a tool sees the key, and
#   nothing a tool returns from onKeyDown stops them. Deep Scale's letters
#   failed the same way (5.2.6).
#
# HOST CONTRACT — included by DrawnChamferTool after DrawnChamferScrub, so its
# key handlers sit in front of the shared ones and fall back to them with
# super. Its activate registers the tool (Na__HotSwap__SetActiveTool) and
# calls na_hs__apply when a handover is pending, instead of reading the
# selection.
#
# =============================================================================

require 'sketchup.rb'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | The Running Edge Tool (Module Level, for the Menu Commands)
    # -----------------------------------------------------------------------------

    NA_HS_PROFILE_ORDER = [:chamfer, :fillet, :ogee, :ovolo].freeze           # <-- SHIFT+TAB steps through these, in the menu's order
    NA_HS_TAB_HELD_S    = 1.5                                                 # <-- A switching TAB counts as held this long past its last repeat

    # FUNCTION | The TAB That Switched the Profile Is Down, or Was Let Go
    # ------------------------------------------------------------
    # Kept on the module, not the tool: the repeats of a held TAB arrive at
    # the NEW tool, which never saw the key go down and may not know SHIFT is
    # held either. Each repeat keeps it held; a key-up lets it go, and a
    # key-up lost to a change of focus cannot keep it held for long.
    # ------------------------------------------------------------
    def self.Na__HotSwap__TabDown(down)
        @na_hs_tab_at = down ? Time.now : nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is the TAB That Switched the Profile Still Held?
    # ------------------------------------------------------------
    def self.Na__HotSwap__TabDown?
        at = @na_hs_tab_at
        at ? (Time.now - at).to_f < NA_HS_TAB_HELD_S : false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Remember Which Edge Tool Is Running (nil When None)
    # ------------------------------------------------------------
    def self.Na__HotSwap__SetActiveTool(tool)
        @na_hs_active_tool = tool
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Edge Tool Running Now, or nil
    # ------------------------------------------------------------
    def self.Na__HotSwap__ActiveTool
        tool = @na_hs_active_tool
        tool.is_a?(Na__InsertPrimatives::DrawnChamferTool) ? tool : nil
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Profile's Menu Command, Pressed While an Edge Tool Runs
    # ------------------------------------------------------------
    # Deep Chamfer, Deep Fillet, Deep Ogee and Deep Ovolo in the Extensions
    # menu are the commands a key is bound to in Preferences > Shortcuts.
    # With one of the four already running, the command hands the edges and
    # the drag across as the right-click menu does. false when none is
    # running: the command then starts its tool the ordinary way.
    # ------------------------------------------------------------
    def self.Na__HotSwap__ToProfile(profile)
        tool = Na__InsertPrimatives.Na__HotSwap__ActiveTool
        return false unless tool

        tool.na_hs__switch_profile(profile)
    rescue StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "NA HOT SWAP: the #{profile} command could not hand over (#{error.message})"
        false
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    module DrawnChamferHotSwap

        NA_HS_TAB_KEY        = 9                                              # <-- No VK_TAB constant in the SketchUp API
        NA_HS_PROFILE_CLASS  = { :chamfer => :DrawnChamferTool, :fillet => :DrawnFilletTool, :ogee => :DrawnOgeeTool, :ovolo => :DrawnOvoloTool }.freeze

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

        # FUNCTION | Deep Ovolo From the Menu
        # ------------------------------------------------------------
        def Na__DrawnMode__SetOvoloMode
            na_hs__swap_to(:DrawnOvoloTool) || super
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | SHIFT+TAB — the Next Profile
        # -----------------------------------------------------------------------------

        # ON KEY DOWN | SHIFT+TAB Steps to the Next Profile
        # ------------------------------------------------------------
        # Chamfer, Fillet, Ogee, Ovolo and round again, carrying the edges and
        # the drag. One step per press: the repeats of a held TAB are
        # swallowed until it is let go (Na__HotSwap__TabDown), so it neither
        # races round the four nor falls through to the new profile's own TAB.
        # SHIFT comes from the mouse flags, the one modifier they are always
        # right about; the key flags carry the scan code on Windows and are not
        # read. Not with CTRL down, which is the hand on the vertex snap.
        # ------------------------------------------------------------
        def onKeyDown(key, repeat, flags, view)
            if key == NA_HS_TAB_KEY && Na__InsertPrimatives.Na__HotSwap__TabDown?
                Na__InsertPrimatives.Na__HotSwap__TabDown(true)               # <-- A repeat of the press that switched: still held
                return true
            end

            return super unless key == NA_HS_TAB_KEY && @na_shift_held && !@na_ctrl_held

            Na__InsertPrimatives.Na__HotSwap__TabDown(true)
            na_hs__switch_profile(na_hs__next_profile)
            true
        end
        # ---------------------------------------------------------------

        # ON KEY UP | TAB Let Go; Everything Else to the Shared Handler
        # ------------------------------------------------------------
        # Defined either way rather than deleted: Reload Plugin Data loads this
        # file again without removing anything, so 5.1.22's ALT-tracking
        # key-up would otherwise live on in a running SketchUp until a restart.
        # ------------------------------------------------------------
        def onKeyUp(key, repeat, flags, view)
            Na__InsertPrimatives.Na__HotSwap__TabDown(false) if key == NA_HS_TAB_KEY
            super
        end
        # ---------------------------------------------------------------

        # ON USER TEXT | Left to the Shared Handler (the Same Reason)
        # A letter typed into the box is no longer a profile: "r" on its own is
        # just an entry the tool cannot read, and says so as any other would.
        # ------------------------------------------------------------
        def onUserText(text, view)
            super
        end
        # ---------------------------------------------------------------

        # DEACTIVATE | The Menu Commands Forget This Tool
        # ------------------------------------------------------------
        def deactivate(view)
            Na__InsertPrimatives.Na__HotSwap__SetActiveTool(nil) if Na__InsertPrimatives.Na__HotSwap__ActiveTool.equal?(self)
            super
        end
        # ---------------------------------------------------------------

        # FUNCTION | This Tool's Own Profile
        # ------------------------------------------------------------
        def na_hs__profile
            NA_HS_PROFILE_CLASS.each do |profile, class_name|
                next unless Na__InsertPrimatives.const_defined?(class_name)

                return profile if instance_of?(Na__InsertPrimatives.const_get(class_name))
            end

            :chamfer
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Profile SHIFT+TAB Goes To From This One
        # ------------------------------------------------------------
        def na_hs__next_profile
            order = Na__InsertPrimatives::NA_HS_PROFILE_ORDER
            order[(order.index(na_hs__profile).to_i + 1) % order.length]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Switch to a Profile — SHIFT+TAB, or Its Menu Command
        # ------------------------------------------------------------
        # The same handover as the right-click menu: the edges and the drag come
        # across. The profile already running keeps everything and says so
        # (Deep Ovolo answers its own command by turning a cavetto back into an
        # ovolo).
        # ------------------------------------------------------------
        def na_hs__switch_profile(profile)
            class_name = NA_HS_PROFILE_CLASS[profile]
            return false unless class_name && Na__InsertPrimatives.const_defined?(class_name)

            return na_hs__same_profile(profile) if instance_of?(Na__InsertPrimatives.const_get(class_name))

            case profile                                                      # <-- self. receivers: a bare capitalised name parses as a constant
            when :chamfer then self.Na__DrawnMode__SetChamferMode
            when :fillet  then self.Na__DrawnMode__SetFilletMode
            when :ogee    then self.Na__DrawnMode__SetOgeeMode
            when :ovolo   then self.Na__DrawnMode__SetOvoloMode
            end

            true
        rescue StandardError => error
            Na__InsertPrimatives.Na__Debug__Puts "NA HOT SWAP: could not switch to #{profile} (#{error.message})"
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Profile Already Running, Asked For Again
        # ------------------------------------------------------------
        def na_hs__same_profile(_profile)
            na_revise__notice("Already #{na_drawn__tool_title} — SHIFT+TAB steps to the next profile, keeping the edges")
            true
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
                :mouse       => [@na_last_mouse_x, @na_last_mouse_y]
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

            size = snapshot[:size].to_f
            size = @na_ch_max_size.to_f if @na_ch_max_size && size > @na_ch_max_size.to_f
            size = 0.0 if size < 0.0

            @na_size_d = size
            @na_sign_d = 1.0
            na_sc__rebase(snapshot[:mouse][1], size)                          # <-- The scrub carries on from this size, from where the cursor is
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
