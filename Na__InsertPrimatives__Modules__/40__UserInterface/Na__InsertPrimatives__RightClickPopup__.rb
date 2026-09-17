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
# - The placement is read back with get_position / get_size (SketchUp 2021.1+)
#   in the moment before the popup closes — the only moment it is certain to
#   still have one. A popup closed by its own X is remembered on a best-effort
#   basis, because by the time SketchUp says it closed the window may be gone.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../02__AppData/Na__InsertPrimatives__AppData__UserConfigLoader__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Popup Sizing Constants
    # -----------------------------------------------------------------------------

    NA_POPUP_WIDTH            = 216
    NA_POPUP_FALLBACK_HEIGHT  = 560                                           # <-- Opens generous, then shrinks to fit
    NA_POPUP_CHROME_ALLOWANCE = 52                                            # <-- Title bar plus clear space under the last button
    NA_POPUP_CURSOR_OFFSET_PX = 20                                            # <-- At-cursor mode opens just off the click, never under it
    NA_POPUP_MIN_WIDTH        = 160                                           # <-- Below these a remembered size is a glitch, not a choice
    NA_POPUP_MIN_HEIGHT       = 120
    NA_POPUP_MAX_COORDINATE   = 32_000                                        # <-- A remembered position beyond this is garbage, not a monitor

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | UserConfig Keys
    # -----------------------------------------------------------------------------

    NA_POPUP_CONFIG_KEY       = 'Na__RightClickMenu__Config'.freeze
    NA_POPUP_ANCHOR_MODE_KEY  = 'Na__RightClickMenu__AnchorMode'.freeze
    NA_POPUP_POSITION_KEY     = 'Na__RightClickMenu__Position'.freeze
    NA_POPUP_SIZE_KEY         = 'Na__RightClickMenu__Size'.freeze
    NA_POPUP_X_KEY            = 'Na__Position__X'.freeze
    NA_POPUP_Y_KEY            = 'Na__Position__Y'.freeze
    NA_POPUP_WIDTH_KEY        = 'Na__Size__Width'.freeze
    NA_POPUP_HEIGHT_KEY       = 'Na__Size__Height'.freeze
    NA_POPUP_ANCHOR_ANCHORED  = 'anchored'.freeze
    NA_POPUP_ANCHOR_CURSOR    = 'cursor'.freeze

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Popup Lifecycle
    # -----------------------------------------------------------------------------

    # FUNCTION | Show Primitive Popup Menu
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__ShowPrimitiveMenu(tool_instance, x, y)
        Na__InsertPrimatives.Na__RightClickPopup__CloseMenu()

        placement = Na__InsertPrimatives.Na__RightClickPopup__Placement(x, y)

        dialog = UI::HtmlDialog.new(
            dialog_title: "Primitive Menu",
            preferences_key: "Na__InsertPrimatives__RightClickPopup",
            scrollable: false,
            resizable: true,
            width: placement[:width],
            height: placement[:height],
            style: UI::HtmlDialog::STYLE_UTILITY
        )

        @na_right_click_popup            = dialog
        @na_right_click_popup_remembered = false

        dialog.set_html(Na__InsertPrimatives.Na__RightClickPopup__BuildHtml(tool_instance))
        Na__InsertPrimatives.Na__RightClickPopup__InstallCallbacks(dialog, tool_instance)
        dialog.set_on_closed { Na__InsertPrimatives.Na__RightClickPopup__OnClosed(dialog) }
        dialog.set_position(placement[:x], placement[:y])
        dialog.show
        dialog.bring_to_front
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

    # FUNCTION | The Remembered [width, height]; Height nil Means Fit to Content
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__RememberedSize
        width  = Na__InsertPrimatives.Na__UserConfig__Get(NA_POPUP_CONFIG_KEY, NA_POPUP_SIZE_KEY, NA_POPUP_WIDTH_KEY)
        height = Na__InsertPrimatives.Na__UserConfig__Get(NA_POPUP_CONFIG_KEY, NA_POPUP_SIZE_KEY, NA_POPUP_HEIGHT_KEY)

        width  = (width.is_a?(Numeric)  && width.to_i  >= NA_POPUP_MIN_WIDTH)  ? width.to_i  : NA_POPUP_WIDTH
        height = (height.is_a?(Numeric) && height.to_i >= NA_POPUP_MIN_HEIGHT) ? height.to_i : nil

        [width, height]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Where and How Big the Popup Opens This Time
    # Anchored with a remembered spot: there. Anchored without one (the first
    # ever open, or after a reset), or At Cursor: just off the click.
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__Placement(x, y)
        width, height = Na__InsertPrimatives.Na__RightClickPopup__RememberedSize
        position      = Na__InsertPrimatives.Na__RightClickPopup__Anchored? ?
                        Na__InsertPrimatives.Na__RightClickPopup__RememberedPosition : nil

        left, top = position || [x.to_i + NA_POPUP_CURSOR_OFFSET_PX, y.to_i + NA_POPUP_CURSOR_OFFSET_PX]

        {
            :x      => left,
            :y      => top,
            :width  => width,
            :height => height || NA_POPUP_FALLBACK_HEIGHT
        }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Read the Popup's Position and Size Back Into UserConfig
    # Both are validated before they are kept: a window that is already on
    # its way out answers with zeros or nonsense, and a remembered position
    # of 0,0 is far more likely to be that than a real choice.
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__RememberPlacement(dialog)
        return false unless dialog

        position = dialog.respond_to?(:get_position) ? dialog.get_position : nil
        size     = dialog.respond_to?(:get_size)     ? dialog.get_size     : nil

        body = Na__InsertPrimatives.Na__UserConfig__Load
        menu = body[NA_POPUP_CONFIG_KEY]
        menu = body[NA_POPUP_CONFIG_KEY] = {} unless menu.is_a?(Hash)
        changed = false

        if position.is_a?(Array) && position.length == 2 &&
           position.all? { |value| Na__InsertPrimatives.Na__RightClickPopup__SaneCoordinate?(value) } &&
           !(position[0].to_i.zero? && position[1].to_i.zero?)
            menu[NA_POPUP_POSITION_KEY] = {
                NA_POPUP_X_KEY => position[0].to_i,
                NA_POPUP_Y_KEY => position[1].to_i
            }
            changed = true
        end

        if size.is_a?(Array) && size.length == 2 &&
           size[0].to_i >= NA_POPUP_MIN_WIDTH && size[1].to_i >= NA_POPUP_MIN_HEIGHT
            menu[NA_POPUP_SIZE_KEY] = {
                NA_POPUP_WIDTH_KEY  => size[0].to_i,
                NA_POPUP_HEIGHT_KEY => size[1].to_i
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

        menu[NA_POPUP_POSITION_KEY] = { NA_POPUP_X_KEY => nil, NA_POPUP_Y_KEY => nil }
        menu[NA_POPUP_SIZE_KEY]     = { NA_POPUP_WIDTH_KEY => NA_POPUP_WIDTH, NA_POPUP_HEIGHT_KEY => nil }

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

        remembered = Na__InsertPrimatives.Na__RightClickPopup__RememberPlacement(dialog)
        @na_right_click_popup = nil
        remembered
    rescue StandardError
        false
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
        # Fired once the page has laid out, so the window ends up exactly as tall
        # as its buttons need plus clear space at the base. A remembered height
        # TALLER than that is the user's own resize and is kept; a shorter one
        # would clip the last button, so the content wins.
        dialog.add_action_callback("reportContentHeight") do |_action_context, content_height|
            begin
                measured = content_height.to_i

                if measured > 0
                    width, remembered = Na__InsertPrimatives.Na__RightClickPopup__RememberedSize
                    fitted = measured + NA_POPUP_CHROME_ALLOWANCE
                    height = (remembered && remembered > fitted) ? remembered : fitted
                    dialog.set_size(width, height)
                end
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

        dialog.add_action_callback("setChamferMode") do |_action_context|
            Na__InsertPrimatives.Na__RightClickPopup__RunAction(tool_instance) do
                tool_instance.Na__DrawnMode__SetChamferMode()
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

        dialog.add_action_callback("exitPrimitiveTool") do |_action_context|
            Na__InsertPrimatives.Na__RightClickPopup__RunAction(tool_instance) do
                tool_instance.Na__PrimitiveMode__ScheduleExitTool()
            end
        end
    end
    # ---------------------------------------------------------------


    # FUNCTION | Run Popup Action Safely
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__RunAction(tool_instance)
        Na__InsertPrimatives.Na__RightClickPopup__CloseMenu()

        UI.start_timer(0, false) do
            begin
                yield if tool_instance
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

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF RIGHT CLICK POPUP
# =============================================================================
