# =============================================================================
# NA INSERT PRIMATIVES - RIGHT CLICK POPUP
# =============================================================================
#
# FILE       : Na__InsertPrimatives__RightClickPopup__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Reliable primitive menu fallback for empty viewport right-clicks
# CREATED    : 2026
#
# DESCRIPTION:
# - One popup serves every primitive tool in the plugin. The running mode is highlighted.
# - Switching between the click-to-place tool and the click-and-drag tools swaps
#   the active SketchUp tool, which is why all of them implement the same small
#   menu interface (see Na__InsertPrimatives::PrimitiveModeSwitching).
# - The snap grid button cycles in place without closing the popup, so stepping
#   from 5mm to 100mm does not need four trips through the context menu.
#
# THE MENU STAYS WHERE YOU PUT IT:
# - A menu that opens wherever the cursor happens to be cannot be learned: the
#   buttons are somewhere new on every right-click and the hand never gets to
#   memorise them. So by default the popup is ANCHORED. It opens at the cursor
#   the first time only; after that it opens wherever it was last left — drag
#   it by its title bar to where you want it and it stays there, at whatever
#   size you made it, across right-clicks, tools and sessions.
# - Placement lives in UserConfig (Na__InsertPrimatives__UserConfig__Main.json),
#   the per-user document, never in AppConfig. The Menu button at the foot of
#   the popup flips between Anchored and At Cursor. Extensions >
#   Na__InsertPrimitives > Reset Menu Position puts it back at the cursor, for
#   the day a monitor is unplugged and the remembered spot no longer exists.
# - The POSITION is read back with get_position (SketchUp 2021.1+) in the
#   moment before the popup closes — the only moment it is certain to still
#   have one. A popup closed by its own X is remembered on a best-effort
#   basis, because by the time SketchUp says it closed the window may be gone.
#
# THE SIZE IS THE PAGE'S OWN, MEASURED BY THE PAGE (5.2.16):
# - The size used to go round get_size -> UserConfig -> set_size. Those are
#   not the same units: get_size is the outer frame in LOGICAL pixels, set_size
#   is documented only as "pixels", and the content-fit grew the window
#   whenever any tool's menu was taller than the remembered height, then
#   remembered THAT. Every rebuild (each tool switch with Menu Opens: With
#   Any Tool) could only ratchet it taller, until it covered the VCB.
# - Now the page reports window.innerWidth / innerHeight (its content area,
#   CSS pixels) and that is the only size ever stored, the moment the user
#   finishes a resize. On open the window is steered until the page says it
#   is that size: a closed loop, so the units of set_size no longer matter.
# - The content never grows the window. A menu taller than the size you gave
#   it scrolls. Only the very first open (nothing remembered) fits the
#   buttons, and never past the foot of the screen's work area.
# - No preferences_key: SketchUp's own size memory restored a grown size
#   before ours was applied. One memory, ours.
#
# ON RIGHT-CLICK, OR OPEN WITH ANY TOOL:
# - By default the menu appears only on a right-click. The Menu Opens button
#   at its foot switches it to stay open whenever any Insert Primitives tool
#   is running: it comes up as a tool starts, is rebuilt for each tool picked
#   from it, and closes when the last tool exits. Stored in UserConfig with
#   the placement, so the choice holds across sessions.
# - Closing it by its X while a tool runs is respected: it stays shut until
#   the next tool starts, or the next right-click.
# - Every tool reports its activate / deactivate through a small module
#   prepended on each tool class (Na__InsertPrimatives__RightClickPopup__Persist__.rb),
#   so no tool has to remember to call it.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../02__AppData/Na__InsertPrimatives__AppData__UserConfigLoader__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Popup Sizing Constants
    # -----------------------------------------------------------------------------

    NA_POPUP_WIDTH            = 216                                           # <-- Outer width of the first ever open
    NA_POPUP_FALLBACK_HEIGHT  = 560                                           # <-- Opens generous, then fits its buttons
    NA_POPUP_CHROME_GUESS     = [16, 39].freeze                               # <-- Frame and title bar, until a popup has measured them
    NA_POPUP_CURSOR_OFFSET_PX = 20                                            # <-- At-cursor mode opens just off the click, never under it
    NA_POPUP_MIN_CONTENT_W    = 140                                           # <-- Below these a reported size is a glitch, not a choice
    NA_POPUP_MIN_CONTENT_H    = 100
    NA_POPUP_SCREEN_MARGIN_PX = 48                                            # <-- A first fit stops this far above the work area's foot (status bar, VCB)
    NA_POPUP_FIT_TOLERANCE_PX = 3                                             # <-- Close enough: the page is the size asked for
    NA_POPUP_FIT_PASSES       = 4                                             # <-- Steering steps before the fit gives up
    NA_POPUP_FIT_WINDOW_S     = 3.0                                           # <-- Resizes this soon after opening may be the fit's own
    NA_POPUP_MAX_COORDINATE   = 32_000                                        # <-- A remembered position beyond this is garbage, not a monitor
    NA_POPUP_REBUILD_DELAY_S  = 0.15                                          # <-- A replacement popup is built this long after the old one closed
    NA_POPUP_PERSIST_DELAY_S  = 0.3                                           # <-- Open With Any Tool: after the old window has gone and the new tool has settled
    NA_POPUP_PERSIST_FALLBACK = [240, 160].freeze                             # <-- Where it opens with no remembered spot and no click to open beside

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | UserConfig Keys
    # -----------------------------------------------------------------------------

    NA_POPUP_CONFIG_KEY       = 'Na__RightClickMenu__Config'.freeze
    NA_POPUP_ANCHOR_MODE_KEY  = 'Na__RightClickMenu__AnchorMode'.freeze
    NA_POPUP_POSITION_KEY     = 'Na__RightClickMenu__Position'.freeze
    NA_POPUP_CONTENT_SIZE_KEY = 'Na__RightClickMenu__ContentSize'.freeze
    NA_POPUP_LEGACY_SIZE_KEY  = 'Na__RightClickMenu__Size'.freeze            # <-- Outer size, before 5.2.16: dropped on the next write
    NA_POPUP_X_KEY            = 'Na__Position__X'.freeze
    NA_POPUP_Y_KEY            = 'Na__Position__Y'.freeze
    NA_POPUP_WIDTH_KEY        = 'Na__Size__Width'.freeze
    NA_POPUP_HEIGHT_KEY       = 'Na__Size__Height'.freeze
    NA_POPUP_ANCHOR_ANCHORED  = 'anchored'.freeze
    NA_POPUP_ANCHOR_CURSOR    = 'cursor'.freeze
    NA_POPUP_SHOW_MODE_KEY    = 'Na__RightClickMenu__ShowMode'.freeze
    NA_POPUP_SHOW_RIGHT_CLICK = 'right_click'.freeze
    NA_POPUP_SHOW_WITH_TOOL   = 'with_tool'.freeze

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Popup Lifecycle
    # -----------------------------------------------------------------------------

    # FUNCTION | Show Primitive Popup Menu
    # ------------------------------------------------------------
    # NEVER TORN DOWN AND REBUILT IN ONE PASS (5.2.6):
    # - SketchUp 2027 runs its own context-menu loop for a right-click, and
    #   the timer that opens this popup fires inside it. Three of the four
    #   crash dumps of 27 Oct 2026 died in a repaint in exactly that loop,
    #   on a window already freed. Closing one browser window and building
    #   another in the same pass is the step that frees windows there.
    # - So a popup already standing open for the same tool is brought to the
    #   click as it is, and one open for another tool is closed now and its
    #   replacement built on a later tick. Never both at once.
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__ShowPrimitiveMenu(tool_instance, x, y)
        # A right-click is proof the tool is running, and an explicit ask for
        # the menu, so it also lifts a dismissal by the X (Open With Any Tool).
        @na_popup_live_tool      = tool_instance
        @na_popup_dismissed_tool = nil

        dialog = @na_right_click_popup

        if dialog && dialog.visible?
            if @na_right_click_popup_tool.equal?(tool_instance)
                Na__InsertPrimatives.Na__RightClickPopup__MoveToClick(dialog, x, y)
                dialog.bring_to_front
                return dialog
            end

            Na__InsertPrimatives.Na__RightClickPopup__CloseMenu()
            UI.start_timer(NA_POPUP_REBUILD_DELAY_S, false) do
                Na__InsertPrimatives.Na__RightClickPopup__BuildMenu(tool_instance, x, y)
            end
            return nil
        end

        Na__InsertPrimatives.Na__RightClickPopup__BuildMenu(tool_instance, x, y)
    rescue StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "PRIMITIVE POPUP: not shown — #{error.message}"
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Bring an Open Popup to the Click — At Cursor Mode Only
    # Anchored, it stays where the user left it, as it would on a reopen.
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__MoveToClick(dialog, x, y)
        return false if Na__InsertPrimatives.Na__RightClickPopup__Anchored?

        dialog.set_position(x.to_i + NA_POPUP_CURSOR_OFFSET_PX, y.to_i + NA_POPUP_CURSOR_OFFSET_PX)
        true
    end
    # ---------------------------------------------------------------

    # FUNCTION | Build and Show a New Popup for One Tool
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__BuildMenu(tool_instance, x, y)
        placement = Na__InsertPrimatives.Na__RightClickPopup__Placement(x, y)

        # No preferences_key: SketchUp's own memory of the size would be laid
        # over ours before the page could report (THE SIZE IS THE PAGE'S OWN).
        dialog = UI::HtmlDialog.new(
            dialog_title: "Primitive Menu",
            scrollable: false,
            resizable: true,
            width: placement[:width],
            height: placement[:height],
            style: UI::HtmlDialog::STYLE_UTILITY
        )

        @na_right_click_popup            = dialog
        @na_right_click_popup_tool       = tool_instance
        @na_right_click_popup_remembered = false
        @na_popup_request                = [placement[:width], placement[:height]]   # <-- What set_size was last asked, in its own units
        @na_popup_fit                    = nil
        @na_popup_laid_out               = false

        dialog.set_html(Na__InsertPrimatives.Na__RightClickPopup__BuildHtml(tool_instance))
        Na__InsertPrimatives.Na__RightClickPopup__InstallCallbacks(dialog, tool_instance)
        dialog.set_on_closed { Na__InsertPrimatives.Na__RightClickPopup__OnClosed(dialog) }
        dialog.set_position(placement[:x], placement[:y])
        dialog.show
        dialog.bring_to_front
        dialog
    end
    # ---------------------------------------------------------------


    # FUNCTION | Read the Active Mode Key from Any Primitive Tool
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__ActiveModeKey(tool_instance)
        return nil unless tool_instance.respond_to?(:Na__DrawnMode__ActiveModeKey)

        tool_instance.Na__DrawnMode__ActiveModeKey
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------


    # FUNCTION | Read the Current Snap Grid Label
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__GridLabel(tool_instance)
        if tool_instance.respond_to?(:Na__DrawnMode__GridStepLabel)
            return tool_instance.Na__DrawnMode__GridStepLabel
        end

        Na__InsertPrimatives.Na__DrawnSettings__GridStepLabel
    rescue StandardError
        '5mm'
    end
    # ---------------------------------------------------------------


    # FUNCTION | Make a String Safe Inside a Single-Quoted JavaScript Literal
    # execute_script builds JS by string concatenation, so a caption carrying an
    # apostrophe would otherwise end the literal early and take the call with it.
    # ------------------------------------------------------------
    # The block form of gsub is used deliberately: in the string form a
    # replacement of "\\'" is read as the back-reference for "everything after
    # the match", so the obvious spelling silently does something else.
    def self.Na__RightClickPopup__JsString(text)
        text.to_s.gsub(/[\\'\r\n]/) do |character|
            case character
            when '\\'  then '\\\\'
            when "'"   then "\\'"
            when "\r"  then ''
            else            ' '
            end
        end
    end
    # ---------------------------------------------------------------


    # FUNCTION | Read the Current Circle Segment Count
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__SegmentsLabel(tool_instance)
        if tool_instance.respond_to?(:Na__DrawnMode__CircleSegmentsLabel)
            return tool_instance.Na__DrawnMode__CircleSegmentsLabel
        end

        Na__InsertPrimatives.Na__DrawnSettings__CircleSegments.to_s
    rescue StandardError
        '24'
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Placement Memory (UserConfig)
    # -----------------------------------------------------------------------------

    # FUNCTION | Anchored, or At the Cursor?
    # Anything that is not explicitly 'cursor' reads as anchored, so a missing
    # or misspelt value gets the default rather than a menu that wanders.
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__AnchorMode
        mode = Na__InsertPrimatives.Na__UserConfig__Get(NA_POPUP_CONFIG_KEY, NA_POPUP_ANCHOR_MODE_KEY).to_s
        mode == NA_POPUP_ANCHOR_CURSOR ? NA_POPUP_ANCHOR_CURSOR : NA_POPUP_ANCHOR_ANCHORED
    end
    # ---------------------------------------------------------------

    # FUNCTION | Does the Menu Open Where It Was Last Left?
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__Anchored?
        Na__InsertPrimatives.Na__RightClickPopup__AnchorMode == NA_POPUP_ANCHOR_ANCHORED
    end
    # ---------------------------------------------------------------

    # FUNCTION | Flip Between Anchored and At Cursor; Returns the New Mode
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__ToggleAnchorMode
        mode = Na__InsertPrimatives.Na__RightClickPopup__Anchored? ? NA_POPUP_ANCHOR_CURSOR : NA_POPUP_ANCHOR_ANCHORED
        Na__InsertPrimatives.Na__UserConfig__Set(mode, NA_POPUP_CONFIG_KEY, NA_POPUP_ANCHOR_MODE_KEY)
        mode
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Menu Button's Caption for a Mode
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__AnchorLabel(mode = nil)
        current = mode || Na__InsertPrimatives.Na__RightClickPopup__AnchorMode
        current == NA_POPUP_ANCHOR_ANCHORED ? 'Menu: Anchored (drag to move)' : 'Menu: At Cursor'
    end
    # ---------------------------------------------------------------

    # FUNCTION | On Right-Click Only, or Open With Any Tool?
    # Anything that is not explicitly 'with_tool' reads as right-click, the default.
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__ShowMode
        mode = Na__InsertPrimatives.Na__UserConfig__Get(NA_POPUP_CONFIG_KEY, NA_POPUP_SHOW_MODE_KEY).to_s
        mode == NA_POPUP_SHOW_WITH_TOOL ? NA_POPUP_SHOW_WITH_TOOL : NA_POPUP_SHOW_RIGHT_CLICK
    end
    # ---------------------------------------------------------------

    # FUNCTION | Does the Menu Stay Open While Any Tool Runs?
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__Persistent?
        Na__InsertPrimatives.Na__RightClickPopup__ShowMode == NA_POPUP_SHOW_WITH_TOOL
    end
    # ---------------------------------------------------------------

    # FUNCTION | Flip Between Right-Click and With Any Tool; Returns the New Mode
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__ToggleShowMode
        mode = Na__InsertPrimatives.Na__RightClickPopup__Persistent? ? NA_POPUP_SHOW_RIGHT_CLICK : NA_POPUP_SHOW_WITH_TOOL
        Na__InsertPrimatives.Na__UserConfig__Set(mode, NA_POPUP_CONFIG_KEY, NA_POPUP_SHOW_MODE_KEY)
        mode
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Menu Opens Button's Caption for a Mode
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__ShowModeLabel(mode = nil)
        current = mode || Na__InsertPrimatives.Na__RightClickPopup__ShowMode
        current == NA_POPUP_SHOW_WITH_TOOL ? 'Menu Opens: With Any Tool' : 'Menu Opens: On Right-Click'
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is a Screen Coordinate Plausibly on Some Monitor?
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__SaneCoordinate?(value)
        value.is_a?(Numeric) && value.to_i.abs <= NA_POPUP_MAX_COORDINATE
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Remembered [x, y], or nil When Nothing Usable Is Stored
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__RememberedPosition
        left = Na__InsertPrimatives.Na__UserConfig__Get(NA_POPUP_CONFIG_KEY, NA_POPUP_POSITION_KEY, NA_POPUP_X_KEY)
        top  = Na__InsertPrimatives.Na__UserConfig__Get(NA_POPUP_CONFIG_KEY, NA_POPUP_POSITION_KEY, NA_POPUP_Y_KEY)

        return nil unless Na__InsertPrimatives.Na__RightClickPopup__SaneCoordinate?(left)
        return nil unless Na__InsertPrimatives.Na__RightClickPopup__SaneCoordinate?(top)

        [left.to_i, top.to_i]
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Remembered Content [width, height] in CSS Pixels; nil = Not Set
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__RememberedContentSize
        width  = Na__InsertPrimatives.Na__UserConfig__Get(NA_POPUP_CONFIG_KEY, NA_POPUP_CONTENT_SIZE_KEY, NA_POPUP_WIDTH_KEY)
        height = Na__InsertPrimatives.Na__UserConfig__Get(NA_POPUP_CONFIG_KEY, NA_POPUP_CONTENT_SIZE_KEY, NA_POPUP_HEIGHT_KEY)

        width  = (width.is_a?(Numeric)  && width.to_i  >= NA_POPUP_MIN_CONTENT_W) ? width.to_i  : nil
        height = (height.is_a?(Numeric) && height.to_i >= NA_POPUP_MIN_CONTENT_H) ? height.to_i : nil

        [width, height]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Keep the Size the User Just Gave the Menu (Content, CSS Pixels)
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__RememberContentSize(width, height)
        return false unless width.to_i >= NA_POPUP_MIN_CONTENT_W && height.to_i >= NA_POPUP_MIN_CONTENT_H
        return false if Na__InsertPrimatives.Na__RightClickPopup__RememberedContentSize == [width.to_i, height.to_i]

        Na__InsertPrimatives.Na__UserConfig__Set(
            { NA_POPUP_WIDTH_KEY => width.to_i, NA_POPUP_HEIGHT_KEY => height.to_i },
            NA_POPUP_CONFIG_KEY, NA_POPUP_CONTENT_SIZE_KEY
        )
    end
    # ---------------------------------------------------------------

    # FUNCTION | Where and How Big the Popup Opens This Time
    # Anchored with a remembered spot: there. Anchored without one (the first
    # ever open, or after a reset), or At Cursor: just off the click. The size
    # is only a first guess (remembered content plus the frame last measured);
    # the page's report steers it to the exact size (Na__RightClickPopup__OnLayout).
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__Placement(x, y)
        content_w, content_h = Na__InsertPrimatives.Na__RightClickPopup__RememberedContentSize
        chrome_w, chrome_h   = @na_popup_chrome || NA_POPUP_CHROME_GUESS
        position             = Na__InsertPrimatives.Na__RightClickPopup__Anchored? ?
                               Na__InsertPrimatives.Na__RightClickPopup__RememberedPosition : nil

        left, top = position || [x.to_i + NA_POPUP_CURSOR_OFFSET_PX, y.to_i + NA_POPUP_CURSOR_OFFSET_PX]

        {
            :x      => left,
            :y      => top,
            :width  => content_w ? content_w + chrome_w : NA_POPUP_WIDTH,
            :height => content_h ? content_h + chrome_h : NA_POPUP_FALLBACK_HEIGHT
        }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Read the Popup's Position Back Into UserConfig
    # Validated before it is kept: a window that is already on its way out
    # answers with zeros or nonsense, and a remembered position of 0,0 is far
    # more likely to be that than a real choice. The SIZE is not read here:
    # the page reports it as the user resizes (THE SIZE IS THE PAGE'S OWN).
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__RememberPlacement(dialog)
        return false unless dialog

        position = dialog.respond_to?(:get_position) ? dialog.get_position : nil

        body = Na__InsertPrimatives.Na__UserConfig__Load
        menu = body[NA_POPUP_CONFIG_KEY]
        menu = body[NA_POPUP_CONFIG_KEY] = {} unless menu.is_a?(Hash)
        changed = !menu.delete(NA_POPUP_LEGACY_SIZE_KEY).nil?

        if position.is_a?(Array) && position.length == 2 &&
           position.all? { |value| Na__InsertPrimatives.Na__RightClickPopup__SaneCoordinate?(value) } &&
           !(position[0].to_i.zero? && position[1].to_i.zero?)
            menu[NA_POPUP_POSITION_KEY] = {
                NA_POPUP_X_KEY => position[0].to_i,
                NA_POPUP_Y_KEY => position[1].to_i
            }
            changed = true
        end

        changed ? Na__InsertPrimatives.Na__UserConfig__Write : false
    rescue StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "PRIMITIVE POPUP: placement not remembered — #{error.message}"
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Forget the Remembered Placement (Extensions Menu Entry Point)
    # The escape hatch for a position that is no longer on any screen.
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__ResetPlacement
        Na__InsertPrimatives.Na__RightClickPopup__CloseMenu()

        body = Na__InsertPrimatives.Na__UserConfig__Load
        menu = body[NA_POPUP_CONFIG_KEY]
        menu = body[NA_POPUP_CONFIG_KEY] = {} unless menu.is_a?(Hash)

        menu[NA_POPUP_POSITION_KEY]     = { NA_POPUP_X_KEY => nil, NA_POPUP_Y_KEY => nil }
        menu[NA_POPUP_CONTENT_SIZE_KEY] = { NA_POPUP_WIDTH_KEY => nil, NA_POPUP_HEIGHT_KEY => nil }
        menu.delete(NA_POPUP_LEGACY_SIZE_KEY)

        written = Na__InsertPrimatives.Na__UserConfig__Write
        Sketchup::set_status_text('Primitive menu position reset — it opens at the cursor next time', SB_PROMPT)
        written
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Popup Closed on Its Own — Remember It If We Have Not Already
    # Only the popup that is still current is listened to: a stale one whose
    # close notification arrives after a replacement has opened must not
    # overwrite the replacement's placement with a dead window's answers.
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__OnClosed(dialog)
        return false if @na_right_click_popup_remembered
        return false unless dialog.equal?(@na_right_click_popup)

        # Closed by its X, not by us: in Open With Any Tool it stays shut for
        # this tool, rather than springing back on the next mode switch.
        @na_popup_dismissed_tool = @na_right_click_popup_tool

        remembered = Na__InsertPrimatives.Na__RightClickPopup__RememberPlacement(dialog)
        @na_right_click_popup = nil
        remembered
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Sizing From the Page's Own Report
    # -----------------------------------------------------------------------------

    # FUNCTION | The Page Laid Out or Was Resized: Fit It, or Remember the User's Size
    # ------------------------------------------------------------
    # 'load' starts the fit. A 'resize' soon after is the fit's own echo and
    # steers it on; any other 'resize' is the user's drag of the frame, and
    # its content size is what gets remembered — the same quantity the fit
    # aims at, so remembering it can never move the target.
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__OnLayout(dialog, inner_w, inner_h, needed, avail_bottom, screen_y, reason)
        return false unless dialog.equal?(@na_right_click_popup)
        return false unless inner_w > 0 && inner_h > 0

        if reason == 'load'
            Na__InsertPrimatives.Na__RightClickPopup__LearnChrome(dialog, inner_w, inner_h)
            @na_popup_laid_out = true
            @na_popup_fit = {
                :target  => Na__InsertPrimatives.Na__RightClickPopup__TargetContentSize(inner_w, needed, avail_bottom, screen_y),
                :passes  => 0,
                :started => Process.clock_gettime(Process::CLOCK_MONOTONIC)
            }
            return Na__InsertPrimatives.Na__RightClickPopup__FitStep(dialog, inner_w, inner_h)
        end

        return false unless @na_popup_laid_out

        fit = @na_popup_fit
        if fit && (Process.clock_gettime(Process::CLOCK_MONOTONIC) - fit[:started]) < NA_POPUP_FIT_WINDOW_S
            return Na__InsertPrimatives.Na__RightClickPopup__FitStep(dialog, inner_w, inner_h)
        end

        @na_popup_fit = nil
        Na__InsertPrimatives.Na__RightClickPopup__RememberContentSize(inner_w, inner_h)
    end
    # ---------------------------------------------------------------

    # FUNCTION | How Big the Frame and Title Bar Are (for the Next Opening Guess)
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__LearnChrome(dialog, inner_w, inner_h)
        return false unless dialog.respond_to?(:get_size)

        outer = dialog.get_size
        return false unless outer.is_a?(Array) && outer.length == 2

        chrome = [outer[0].to_i - inner_w, outer[1].to_i - inner_h]
        return false unless chrome[0].between?(0, 80) && chrome[1].between?(0, 120)

        @na_popup_chrome = chrome
        true
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Content Size This Opening Aims For
    # ------------------------------------------------------------
    # The user's own size when there is one, scrolled if the buttons need
    # more. Otherwise (the first open, or after Reset Menu Position) as tall
    # as the buttons. Either way never past the foot of the work area, less a
    # margin so it stays clear of SketchUp's status bar and VCB.
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__TargetContentSize(inner_w, needed, avail_bottom, screen_y)
        saved_w, saved_h = Na__InsertPrimatives.Na__RightClickPopup__RememberedContentSize

        width  = saved_w || inner_w
        height = saved_h || (needed > 0 ? needed : NA_POPUP_FALLBACK_HEIGHT)

        chrome_h = (@na_popup_chrome || NA_POPUP_CHROME_GUESS)[1]
        room     = avail_bottom - screen_y - chrome_h - NA_POPUP_SCREEN_MARGIN_PX
        height   = [height, room].min if avail_bottom > 0 && room >= NA_POPUP_MIN_CONTENT_H

        [[width, NA_POPUP_MIN_CONTENT_W].max, [height, NA_POPUP_MIN_CONTENT_H].max]
    end
    # ---------------------------------------------------------------

    # FUNCTION | One Step of Steering the Window Until the Page Is the Target Size
    # ------------------------------------------------------------
    # set_size takes the OUTER size in its own units; the page reports its
    # INNER size in CSS pixels. Each step asks for the last request plus the
    # error, scaled by how far the page actually moved for the last change
    # asked (1 until measured), so a frame of any size and any display scaling
    # converge in a step or two. A window that will not reach the target (a
    # monitor too small) stops trying after NA_POPUP_FIT_PASSES.
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__FitStep(dialog, inner_w, inner_h)
        fit = @na_popup_fit
        return false unless fit

        target_w, target_h = fit[:target]
        error   = [target_w - inner_w, target_h - inner_h]
        settled = error.all? { |value| value.abs <= NA_POPUP_FIT_TOLERANCE_PX }

        if settled || fit[:passes] >= NA_POPUP_FIT_PASSES
            @na_popup_fit = nil
            return true
        end

        request = @na_popup_request || [NA_POPUP_WIDTH, NA_POPUP_FALLBACK_HEIGHT]
        gain    = fit[:gain] || [1.0, 1.0]

        if fit[:last_inner] && fit[:last_request]
            gain = [0, 1].map do |axis|
                moved = [inner_w, inner_h][axis] - fit[:last_inner][axis]
                asked = request[axis] - fit[:last_request][axis]
                ratio = moved.zero? ? nil : asked.to_f / moved
                (ratio && ratio > 0.4 && ratio < 4.0) ? ratio : gain[axis]
            end
        end

        asked = [(request[0] + (error[0] * gain[0])).round, (request[1] + (error[1] * gain[1])).round]

        fit[:gain]         = gain
        fit[:last_inner]   = [inner_w, inner_h]
        fit[:last_request] = request
        fit[:passes]      += 1
        @na_popup_request  = asked

        dialog.set_size(asked[0], asked[1])
        true
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Open With Any Tool
    # -----------------------------------------------------------------------------

    # FUNCTION | A Tool Has Started: Note It, and Open the Menu If Asked To
    # ------------------------------------------------------------
    # Called from every tool's activate (the Persist module). The menu is
    # built on a later tick, never inside activate: the old tool's deactivate
    # has just closed a window in this same pass (NEVER TORN DOWN AND REBUILT
    # IN ONE PASS, above).
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__ToolActivated(tool_instance)
        @na_popup_live_tool      = tool_instance
        @na_popup_dismissed_tool = nil
        Na__InsertPrimatives.Na__RightClickPopup__SchedulePersistentShow
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Tool Has Stopped: Forget It (Its Deactivate Closes the Menu)
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__ToolDeactivated(tool_instance)
        @na_popup_live_tool = nil if @na_popup_live_tool.equal?(tool_instance)
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Tool the Menu Belongs To Right Now, Noted If Not Yet Known
    # ------------------------------------------------------------
    # A tool started before the Persist module was installed (a session that
    # was running across a reload) never reported itself; the popup's own tool
    # is running, so it stands in.
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__NoteLiveTool(tool_instance)
        @na_popup_live_tool ||= tool_instance
    end
    # ---------------------------------------------------------------

    # FUNCTION | Open the Menu on a Later Tick, Once, If Open With Any Tool Is On
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__SchedulePersistentShow
        return false unless Na__InsertPrimatives.Na__RightClickPopup__Persistent?
        return true if @na_popup_persist_pending

        @na_popup_persist_pending = true
        UI.start_timer(NA_POPUP_PERSIST_DELAY_S, false) do
            @na_popup_persist_pending = false
            Na__InsertPrimatives.Na__RightClickPopup__EnsurePersistentOpen
        end
        true
    end
    # ---------------------------------------------------------------

    # FUNCTION | Make Sure the Menu Is Open for the Running Tool
    # ------------------------------------------------------------
    # Nothing to do with no tool running, after a close by the X for this
    # tool, or with the menu already open for it. Anchored, it opens where it
    # was last left; at the cursor there is no click, so it opens there too.
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__EnsurePersistentOpen
        return nil unless Na__InsertPrimatives.Na__RightClickPopup__Persistent?

        tool = @na_popup_live_tool
        return nil unless tool
        return nil if tool.equal?(@na_popup_dismissed_tool)

        # Only for the tool SketchUp says is running (Tools#active_tool, 2023+):
        # a tool that stopped without reporting must not get a menu.
        tools = Sketchup.active_model ? Sketchup.active_model.tools : nil
        return nil if tools && tools.respond_to?(:active_tool) && !tools.active_tool.equal?(tool)

        dialog = @na_right_click_popup
        return dialog if dialog && dialog.visible? && @na_right_click_popup_tool.equal?(tool)

        left, top = Na__InsertPrimatives.Na__RightClickPopup__RememberedPosition || NA_POPUP_PERSIST_FALLBACK
        Na__InsertPrimatives.Na__RightClickPopup__ShowPrimitiveMenu(
            tool,
            left - NA_POPUP_CURSOR_OFFSET_PX,
            top  - NA_POPUP_CURSOR_OFFSET_PX
        )
    rescue StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "PRIMITIVE POPUP: not kept open — #{error.message}"
        nil
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # @delegate: Na__InsertPrimatives__RightClickPopup__Html__.rb


    # -----------------------------------------------------------------------------
    # REGION | Dialog Callbacks
    # -----------------------------------------------------------------------------

    # FUNCTION | Install Primitive Popup Callbacks
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__InstallCallbacks(dialog, tool_instance)
        # The page's own size (content area, CSS pixels), the height its
        # buttons need, and the foot of the screen's work area: on load, and
        # after every resize settles (THE SIZE IS THE PAGE'S OWN).
        dialog.add_action_callback("reportLayout") do |_action_context, inner_w, inner_h, needed, avail_bottom, screen_y, reason|
            begin
                Na__InsertPrimatives.Na__RightClickPopup__OnLayout(
                    dialog, inner_w.to_i, inner_h.to_i, needed.to_i, avail_bottom.to_i, screen_y.to_i, reason.to_s
                )
            rescue StandardError => error
                Na__InsertPrimatives.Na__Debug__Puts "PRIMITIVE POPUP RESIZE FAILED: #{error.message}"
            end
        end

        dialog.add_action_callback("setCubeMode") do |_action_context|
            Na__InsertPrimatives.Na__RightClickPopup__RunAction(tool_instance) do
                tool_instance.Na__PrimitiveMode__SetCubeMode()
            end
        end

        dialog.add_action_callback("setPlaneMode") do |_action_context|
            Na__InsertPrimatives.Na__RightClickPopup__RunAction(tool_instance) do
                tool_instance.Na__PrimitiveMode__SetPlaneMode()
            end
        end

        dialog.add_action_callback("setDrawnPlaneMode") do |_action_context|
            Na__InsertPrimatives.Na__RightClickPopup__RunAction(tool_instance) do
                tool_instance.Na__DrawnMode__SetDrawnPlaneMode()
            end
        end

        dialog.add_action_callback("setDrawnVolumeMode") do |_action_context|
            Na__InsertPrimatives.Na__RightClickPopup__RunAction(tool_instance) do
                tool_instance.Na__DrawnMode__SetDrawnVolumeMode()
            end
        end

        dialog.add_action_callback("setDrawnCylinderMode") do |_action_context|
            Na__InsertPrimatives.Na__RightClickPopup__RunAction(tool_instance) do
                tool_instance.Na__DrawnMode__SetDrawnCylinderMode()
            end
        end

        dialog.add_action_callback("setStairMode") do |_action_context|
            Na__InsertPrimatives.Na__RightClickPopup__RunAction(tool_instance) do
                tool_instance.Na__DrawnMode__SetStairMode()
            end
        end

        dialog.add_action_callback("setPipeMode") do |_action_context|
            Na__InsertPrimatives.Na__RightClickPopup__RunAction(tool_instance) do
                tool_instance.Na__DrawnMode__SetPipeMode()
            end
        end

        dialog.add_action_callback("setPitchedRoofMode") do |_action_context|
            Na__InsertPrimatives.Na__RightClickPopup__RunAction(tool_instance) do
                tool_instance.Na__DrawnMode__SetPitchedRoofMode()
            end
        end

        dialog.add_action_callback("setHippedRoofMode") do |_action_context|
            Na__InsertPrimatives.Na__RightClickPopup__RunAction(tool_instance) do
                tool_instance.Na__DrawnMode__SetHippedRoofMode()
            end
        end

        dialog.add_action_callback("setPushPullMode") do |_action_context|
            Na__InsertPrimatives.Na__RightClickPopup__RunAction(tool_instance) do
                tool_instance.Na__DrawnMode__SetPushPullMode()
            end
        end

        dialog.add_action_callback("setProjectMode") do |_action_context|
            Na__InsertPrimatives.Na__RightClickPopup__RunAction(tool_instance) do
                tool_instance.Na__DrawnMode__SetProjectMode()
            end
        end

        dialog.add_action_callback("setChamferMode") do |_action_context|
            Na__InsertPrimatives.Na__RightClickPopup__RunAction(tool_instance) do
                tool_instance.Na__DrawnMode__SetChamferMode()
            end
        end

        dialog.add_action_callback("setFilletMode") do |_action_context|
            Na__InsertPrimatives.Na__RightClickPopup__RunAction(tool_instance) do
                tool_instance.Na__DrawnMode__SetFilletMode()
            end
        end

        dialog.add_action_callback("setOgeeMode") do |_action_context|
            Na__InsertPrimatives.Na__RightClickPopup__RunAction(tool_instance) do
                tool_instance.Na__DrawnMode__SetOgeeMode()
            end
        end

        dialog.add_action_callback("setOvoloMode") do |_action_context|
            Na__InsertPrimatives.Na__RightClickPopup__RunAction(tool_instance) do
                tool_instance.Na__DrawnMode__SetOvoloMode()
            end
        end

        dialog.add_action_callback("setScaleMode") do |_action_context|
            Na__InsertPrimatives.Na__RightClickPopup__RunAction(tool_instance) do
                tool_instance.Na__DrawnMode__SetScaleMode()
            end
        end

        dialog.add_action_callback("setVertexMoveMode") do |_action_context|
            Na__InsertPrimatives.Na__RightClickPopup__RunAction(tool_instance) do
                tool_instance.Na__DrawnMode__SetVertexMoveMode()
            end
        end

        dialog.add_action_callback("togglePlaneFaces") do |_action_context|
            Na__InsertPrimatives.Na__RightClickPopup__RunAction(tool_instance) do
                tool_instance.Na__PrimitiveMode__TogglePlaneFaces()
            end
        end

        # A tool option toggles in place: the submenu is the reason the option is
        # reachable at all, and closing the menu to reopen it for the second of
        # a pair would undo the point of putting them together.
        dialog.add_action_callback("toggleToolOption") do |_action_context, option_id|
            begin
                unless tool_instance.respond_to?(:Na__DrawnMode__ToggleToolOption)
                    Na__InsertPrimatives.Na__Debug__Puts 'PRIMITIVE POPUP: this tool has no options to toggle'
                    next
                end

                result  = tool_instance.Na__DrawnMode__ToggleToolOption(option_id)
                caption = result.is_a?(Hash) ? result[:caption] : result.to_s
                enabled = result.is_a?(Hash) ? result[:enabled] : false

                dialog.execute_script(
                    "naApplyOption('#{Na__InsertPrimatives.Na__RightClickPopup__JsString(option_id)}', " \
                    "'#{Na__InsertPrimatives.Na__RightClickPopup__JsString(caption)}', " \
                    "#{enabled ? 'true' : 'false'});"
                )
            rescue StandardError => error
                Na__InsertPrimatives.Na__Debug__Puts "PRIMITIVE POPUP OPTION TOGGLE FAILED: #{error.message}"
            end
        end

        # Cycling the grid keeps the popup open and rewrites its own button, so
        # stepping 5mm -> 100mm does not need four passes through right-click.
        dialog.add_action_callback("cycleGridStep") do |_action_context|
            begin
                label = tool_instance.Na__DrawnMode__CycleGridStep()
                dialog.execute_script("document.getElementById('gridBtn').textContent = 'Snap Grid: #{label}';")
            rescue StandardError => error
                Na__InsertPrimatives.Na__Debug__Puts "PRIMITIVE POPUP GRID CYCLE FAILED: #{error.message}"
            end
        end

        # Segments cycle in place too, for the same reason as the grid step.
        dialog.add_action_callback("cycleCircleSegments") do |_action_context|
            begin
                count = tool_instance.Na__DrawnMode__CycleCircleSegments()
                dialog.execute_script("document.getElementById('sidesBtn').textContent = 'Circle Sides: #{count}';")
            rescue StandardError => error
                Na__InsertPrimatives.Na__Debug__Puts "PRIMITIVE POPUP SEGMENT CYCLE FAILED: #{error.message}"
            end
        end

        # The anchor flips in place as well: the popup stays open, and where
        # it is standing right now becomes the anchored spot the moment it
        # closes, so "put it here and pin it" is one drag and one click.
        dialog.add_action_callback("toggleMenuAnchor") do |_action_context|
            begin
                mode  = Na__InsertPrimatives.Na__RightClickPopup__ToggleAnchorMode
                label = Na__InsertPrimatives.Na__RightClickPopup__AnchorLabel(mode)
                dialog.execute_script("document.getElementById('anchorBtn').textContent = '#{label}';")
                Sketchup::set_status_text(
                    mode == NA_POPUP_ANCHOR_ANCHORED ? 'Primitive menu anchored — it opens where you leave it' :
                                                       'Primitive menu follows the cursor',
                    SB_PROMPT
                )
            rescue StandardError => error
                Na__InsertPrimatives.Na__Debug__Puts "PRIMITIVE POPUP ANCHOR TOGGLE FAILED: #{error.message}"
            end
        end

        # Right-click only, or open whenever a tool runs. Flips in place like
        # the anchor; switched on, it takes effect from the next tool picked.
        dialog.add_action_callback("toggleMenuShowMode") do |_action_context|
            begin
                Na__InsertPrimatives.Na__RightClickPopup__NoteLiveTool(tool_instance)
                mode  = Na__InsertPrimatives.Na__RightClickPopup__ToggleShowMode
                label = Na__InsertPrimatives.Na__RightClickPopup__ShowModeLabel(mode)
                dialog.execute_script(
                    "document.getElementById('showModeBtn').textContent = " \
                    "'#{Na__InsertPrimatives.Na__RightClickPopup__JsString(label)}';"
                )
                Sketchup::set_status_text(
                    mode == NA_POPUP_SHOW_WITH_TOOL ? 'Primitive menu stays open while any Insert Primitives tool is in use' :
                                                      'Primitive menu opens on right-click',
                    SB_PROMPT
                )
            rescue StandardError => error
                Na__InsertPrimatives.Na__Debug__Puts "PRIMITIVE POPUP SHOW MODE TOGGLE FAILED: #{error.message}"
            end
        end

        dialog.add_action_callback("exitPrimitiveTool") do |_action_context|
            Na__InsertPrimatives.Na__RightClickPopup__RunAction(tool_instance) do
                tool_instance.Na__PrimitiveMode__ScheduleExitTool()
            end
        end
    end
    # ---------------------------------------------------------------


    # FUNCTION | Run Popup Action Safely
    # ------------------------------------------------------------
    # The popup is closed on the timer too, not from inside its own
    # callback: the browser window is not destroyed while it is still
    # delivering the click that asked for it (5.2.6). With Open With Any Tool
    # on it comes back on a later tick, for whichever tool is now running:
    # a switch inside one tool (Cube to Plane) starts no tool to bring it.
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__RunAction(tool_instance)
        UI.start_timer(0, false) do
            begin
                Na__InsertPrimatives.Na__RightClickPopup__NoteLiveTool(tool_instance)
                Na__InsertPrimatives.Na__RightClickPopup__CloseMenu()
                yield if tool_instance
                Na__InsertPrimatives.Na__RightClickPopup__SchedulePersistentShow
            rescue StandardError => error
                Na__InsertPrimatives.Na__Debug__Puts "PRIMITIVE POPUP ACTION FAILED: #{error.message}"
            end
        end
    end
    # ---------------------------------------------------------------


    # FUNCTION | Close Primitive Popup Menu
    # Remembers where the popup stands FIRST — the last moment it is certain
    # to have a position — then closes it.
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__CloseMenu
        dialog = @na_right_click_popup
        return unless dialog && dialog.visible?

        Na__InsertPrimatives.Na__RightClickPopup__RememberPlacement(dialog)
        @na_right_click_popup_remembered = true
        dialog.close
    rescue
        @na_right_click_popup = nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Rewrite One Option Button If the Menu Is Standing Open
    # ------------------------------------------------------------
    # For an option switched from the keyboard (Drawn Volume's SHIFT+TAB).
    # The menu stays open after an option toggle, so it can be sitting beside
    # the model while the keys flip the option underneath it.
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__RefreshOption(option_id)
        dialog = @na_right_click_popup
        return false unless dialog && dialog.visible?

        caption = Na__InsertPrimatives.Na__ToolOptions__CaptionFor(option_id)
        enabled = Na__InsertPrimatives.Na__ToolOptions__Enabled?(option_id)

        dialog.execute_script(
            "naApplyOption('#{Na__InsertPrimatives.Na__RightClickPopup__JsString(option_id)}', " \
            "'#{Na__InsertPrimatives.Na__RightClickPopup__JsString(caption)}', " \
            "#{enabled ? 'true' : 'false'});"
        )
        true
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF RIGHT CLICK POPUP
# =============================================================================
