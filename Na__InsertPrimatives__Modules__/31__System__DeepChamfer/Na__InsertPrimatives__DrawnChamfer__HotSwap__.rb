# =============================================================================
# NA INSERT PRIMATIVES - DEEP CHAMFER / FILLET / OGEE / OVOLO HOT SWAP
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnChamfer__HotSwap__.rb
# NAMESPACE  : Na__InsertPrimatives::DrawnChamferHotSwap
# AUTHOR     : Noble Architecture
# PURPOSE    : Switch between Chamfer, Fillet, Ogee and Ovolo from the right-click
#              menu or a letter typed on its own, without losing the edges or
#              the drag in hand
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
# - Nothing held, and the menu switches exactly as before. Picking the tool
#   already running keeps everything and says so.
# - The retype of a cut already made is not carried: that cut belongs to the
#   tool that made it.
#
# LETTERS (5.1.22) — typed on their own, with nothing else in the box:
#     C  chamfer        R  radius (Deep Fillet)
#     O  ogee           G  ogee (oGee)
#     V  ovolo (TAB in there turns it into a cavetto)
# - On its own is the whole rule: once a number is being typed the letter is
#   part of the entry ("40r", "48s"), and SketchUp's own shortcut on the same
#   letter (C circle, R rectangle, O orbit, G component) is held off only
#   while one of these four tools is running and nothing has been typed.
# - The switch happens on the key itself — SketchUp would otherwise run its
#   shortcut before the measurements box ever saw the letter — and the Enter
#   that habit adds straight after is taken as finishing the switch, not as
#   cutting the profile just swapped in. A letter that does reach the box
#   (typed after a cleared entry) switches on Enter the ordinary way.
# - CTRL, SHIFT and ALT combinations are left to SketchUp: Ctrl+C copies,
#   Alt+V opens the View menu.
#
# HOST CONTRACT — included by DrawnChamferTool after DrawnChamferScrub. Its
# activate calls na_hs__apply when a handover is pending, instead of reading
# the selection, and its onReturn asks na_hs__enter_after_letter? first.
#
# =============================================================================

require 'sketchup.rb'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | The Enter After a Letter (Module Level, Across the Swap)
    # -----------------------------------------------------------------------------

    NA_HS_LETTER_ENTER_S = 1.5                                                # <-- An Enter this soon after a letter switch finishes the switch

    # FUNCTION | A Letter Just Switched the Profile
    # Kept on the module, not the tool: the tool that sees the Enter is the
    # new one, built a moment after the letter.
    # ------------------------------------------------------------
    def self.Na__HotSwap__MarkLetter
        @na_hs_letter_at = Time.now
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is This Enter the One Straight After a Letter? (Asked Once)
    # ------------------------------------------------------------
    def self.Na__HotSwap__TakeLetterEnter
        at               = @na_hs_letter_at
        @na_hs_letter_at = nil
        at ? (Time.now - at).to_f < NA_HS_LETTER_ENTER_S : false
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    module DrawnChamferHotSwap

        # Windows virtual-key codes, which for letters are their capitals.
        NA_HS_LETTER_KEYS    = { 67 => :chamfer, 82 => :fillet, 79 => :ogee, 71 => :ogee, 86 => :ovolo }.freeze
        NA_HS_LETTER_TEXT    = { 'c' => :chamfer, 'r' => :fillet, 'o' => :ogee, 'g' => :ogee, 'v' => :ovolo }.freeze
        NA_HS_PROFILE_CLASS  = { :chamfer => :DrawnChamferTool, :fillet => :DrawnFilletTool, :ogee => :DrawnOgeeTool, :ovolo => :DrawnOvoloTool }.freeze
        NA_HS_ALT_KEY        = defined?(ALT_MODIFIER_KEY) ? ALT_MODIFIER_KEY : 18
        NA_HS_ALT_HELD_S     = 2.0                                            # <-- A missed ALT key-up (the menu bar eats it) is forgotten after this

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
        # REGION | Letters — C R O G V Typed on Their Own
        # -----------------------------------------------------------------------------

        # ON KEY DOWN | A Profile Letter, With Nothing Typed, Swaps the Profile
        # Swallowed (true) whenever it is taken, so SketchUp's own shortcut on
        # the letter does not run as well. ALT is tracked here only to keep
        # Alt+V and friends with the Windows menu bar.
        # ------------------------------------------------------------
        def onKeyDown(key, repeat, flags, view)
            if key == NA_HS_ALT_KEY
                @na_hs_alt_at = Time.now
                return super
            end

            profile = NA_HS_LETTER_KEYS[key]
            return super unless profile && na_hs__letter_free?

            na_hs__switch_profile(profile, true) if repeat.to_i <= 1          # <-- A held key switches once, and its repeats stay swallowed
            true
        end
        # ---------------------------------------------------------------

        # ON KEY UP | ALT Released
        # ------------------------------------------------------------
        def onKeyUp(key, repeat, flags, view)
            @na_hs_alt_at = nil if key == NA_HS_ALT_KEY
            super
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is a Letter Free to Mean a Profile Right Now?
        # Not mid-entry, where it belongs to the box ("40r", "48s"), and not
        # with a modifier down, where it belongs to SketchUp. The key flags are
        # not read for this: on Windows they carry the key's scan code, whose
        # bits can look like a modifier mask.
        # ------------------------------------------------------------
        def na_hs__letter_free?
            return false if @na_vcb_typing_active
            return false if @na_ctrl_held || @na_shift_held
            return false if @na_hs_alt_at && (Time.now - @na_hs_alt_at).to_f < NA_HS_ALT_HELD_S

            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Letter That Reached the Measurements Box Switches on Enter
        # The usual route is the key itself (above). This is the other: a
        # letter typed after an entry was cleared with Backspace gets into the
        # box, and arrives here with its Enter.
        # ------------------------------------------------------------
        def onUserText(text, view)
            profile = NA_HS_LETTER_TEXT[text.to_s.strip.downcase]
            return super unless profile

            @na_vcb_typing_active = false
            na_hs__switch_profile(profile, false)
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Switch to the Profile a Letter Names
        # The same handover as the menu: the edges and the drag come across.
        # The profile already running keeps everything and says so (Deep Ovolo
        # answers V itself: it turns a cavetto back into an ovolo).
        # ------------------------------------------------------------
        def na_hs__switch_profile(profile, by_key)
            class_name = NA_HS_PROFILE_CLASS[profile]
            return false unless class_name && Na__InsertPrimatives.const_defined?(class_name)

            return na_hs__same_profile_letter(profile) if instance_of?(Na__InsertPrimatives.const_get(class_name))

            Na__InsertPrimatives.Na__DrawnSettings__SetOvoloCavetto(false) if profile == :ovolo   # <-- V is the ovolo; TAB in there gives the cavetto
            Na__InsertPrimatives.Na__HotSwap__MarkLetter if by_key

            case profile                                                      # <-- self. receivers: a bare capitalised name parses as a constant
            when :chamfer then self.Na__DrawnMode__SetChamferMode
            when :fillet  then self.Na__DrawnMode__SetFilletMode
            when :ogee    then self.Na__DrawnMode__SetOgeeMode
            when :ovolo   then self.Na__DrawnMode__SetOvoloMode
            end

            true
        rescue StandardError => error
            Na__InsertPrimatives.Na__Debug__Puts "NA HOT SWAP: the letter could not switch (#{error.message})"
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Letter for the Profile Already Running
        # ------------------------------------------------------------
        def na_hs__same_profile_letter(_profile)
            na_revise__notice("Already #{na_drawn__tool_title} — C chamfer, R radius, O ogee, V ovolo")
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is This Enter the One That Followed a Letter? (Asked Once)
        # ------------------------------------------------------------
        def na_hs__enter_after_letter?
            return false unless Na__InsertPrimatives.Na__HotSwap__TakeLetterEnter

            na_revise__notice("#{na_drawn__tool_title} — press Enter again, or click, to cut") if @na_state == :picking_depth
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
