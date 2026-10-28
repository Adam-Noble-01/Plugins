# =============================================================================
# NA INSERT PRIMATIVES - DRAWN PIPE WATCH (THE BAR ON SELECTION)
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnPipe__Watch__.rb
# NAMESPACE  : Na__InsertPrimatives
# CLASS      : DrawnPipeSelectionObserver < Sketchup::SelectionObserver
# AUTHOR     : Noble Architecture
# PURPOSE    : The Pipework bar, top left, whenever pipes are selected (or a
#              pipe's path is out to edit) with SketchUp's Select tool — and
#              clickable there, without starting the Pipework tool first
# CREATED    : 2026 (5.2.11)
#
# HOW IT APPEARS:
# - A selection observer rides on the active model. Its callbacks only mark
#   the answer "which pipes are selected" stale and ask for one deferred
#   refresh; they read nothing and change nothing (SketchUp's safe-observer
#   advice). The refresh, from a timer, counts the selected pipes, switches
#   the pipe overlay on if there are any, and redraws.
# - The pipe overlay (DrawnPipe__Overlay__) then draws the bar while:
#     the option "Bar on Selection" is on (popup > Pipework, or Extensions)
#     the Select tool is the active tool
#     a pipe is selected, or a pipe's path is out as a red line
# - Selection callbacks are known to miss changes, and clearing by clicking
#   empty space calls onSelectionCleared, not onSelectionBulkChange. Every
#   callback is answered alike, and the draw checks the selection's count
#   against the one counted (Selection#length is a constant-time count), so
#   a missed callback costs one recount, never a stale bar.
# - Any transaction (commit, undo, redo) marks the answer stale too: a
#   resized pipe is still selected but its spec has moved.
#
# HOW IT IS CLICKED:
# - An overlay cannot take a click. When the cursor comes onto the bar with
#   no mouse button down, the Pipework tool is PUSHED over the Select tool in
#   its bar role: the same tool and the same buttons, so everything behaves
#   as it does inside the tool. It pops itself when the cursor leaves the
#   bar (unless a spec is armed for typing), on ESC, or on a click away, and
#   Select carries on with its selection untouched.
# - Only over the Select tool. Pushed over a Move or a Line half way through
#   (no button is down between their clicks) it would break them.
#
# MODELS (SketchUp 2027 opens several in tabs):
# - One model is watched: the active one. The Edit module's app observer
#   moves the watch on every model opened, created or switched to, and
#   AppObserver#onCloseModel (2027) lets go of a closed one. The answer is
#   kept with the model it was counted for, so a tab switch can never show
#   another model's pipes.
#
# COORDINATES:
# - Screen only. Tool and Overlay mouse events agree on the kind of pixel
#   (physical integers before SketchUp 2025, logical floats from it), and
#   both lay the bar out with the same function, so the rectangles the
#   overlay tests are the ones the tool draws.
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__InsertPrimatives__DrawnPipe__Route__'
require_relative 'Na__InsertPrimatives__DrawnPipe__Edit__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Watch Constants and State
    # -----------------------------------------------------------------------------

    NA_DRAWN_PIPE_AUTO_BAR_OPTION = 'pipe_auto_bar'
    NA_DRAWN_PIPE_SELECT_TOOL_ID  = 21022                                     # <-- SketchUp's Select tool, as Tools#active_tool_id names it
    NA_DRAWN_PIPE_BAR_LEAVE_PX    = 4.0                                       # <-- The cursor must be this far off the bar before it lets go
    NA_DRAWN_PIPE_MOUSE_BUTTONS   = (defined?(MK_LBUTTON) ? MK_LBUTTON : 1) |
                                    (defined?(MK_RBUTTON) ? MK_RBUTTON : 2) |
                                    (defined?(MK_MBUTTON) ? MK_MBUTTON : 16)

    # Kept across Reload Plugin Data, so an observer already on a model is
    # found and replaced rather than doubled.
    @na_pipe_watch_model    = nil   unless defined?(@na_pipe_watch_model)
    @na_pipe_watch_observer = nil   unless defined?(@na_pipe_watch_observer)
    @na_pipe_watch_answer   = nil   unless defined?(@na_pipe_watch_answer)
    @na_pipe_watch_timer    = nil   unless defined?(@na_pipe_watch_timer)
    @na_pipe_watch_shown    = false unless defined?(@na_pipe_watch_shown)
    @na_pipe_bar_tool       = nil   unless defined?(@na_pipe_bar_tool)
    @na_pipe_bar_drawn      = false unless defined?(@na_pipe_bar_drawn)
    @na_pipe_bar_mouse      = nil   unless defined?(@na_pipe_bar_mouse)
    @na_pipe_bar_pushing    = false unless defined?(@na_pipe_bar_pushing)
    @na_pipe_bar_popping    = false unless defined?(@na_pipe_bar_popping)

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | The Option
    # -----------------------------------------------------------------------------

    # FUNCTION | Is the Bar Shown on Selection?
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__AutoBarOn?
        Na__InsertPrimatives.Na__ToolOptions__Enabled?(NA_DRAWN_PIPE_AUTO_BAR_OPTION)
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Switch the Bar on Selection On or Off (Extensions Menu, Shortcut)
    # ------------------------------------------------------------
    def self.Na__InsertPrimatives__TogglePipeAutoBar
        Na__InsertPrimatives.Na__ToolOptions__Toggle(NA_DRAWN_PIPE_AUTO_BAR_OPTION)
        Na__InsertPrimatives.Na__RightClickPopup__RefreshOption(NA_DRAWN_PIPE_AUTO_BAR_OPTION) if Na__InsertPrimatives.respond_to?(:Na__RightClickPopup__RefreshOption)

        on = Na__InsertPrimatives.Na__DrawnPipe__AutoBarOn?
        Na__InsertPrimatives.Na__DrawnPipe__WatchStale
        Sketchup::set_status_text(on ? 'Pipework bar on selection: on — select a pipe to see it' :
                                       'Pipework bar on selection: off — the bar shows inside the Pipework tool only', SB_PROMPT)
        on
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Watching the Active Model's Selection
    # -----------------------------------------------------------------------------

    # FUNCTION | Watch a Model's Selection (Letting Go of Any Watched Before)
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__WatchModel(model)
        return false unless model && model.respond_to?(:selection)
        return true if model.equal?(@na_pipe_watch_model) && @na_pipe_watch_observer

        Na__InsertPrimatives.Na__DrawnPipe__UnwatchModel

        observer = DrawnPipeSelectionObserver.new
        model.selection.add_observer(observer)
        @na_pipe_watch_model    = model
        @na_pipe_watch_observer = observer
        Na__InsertPrimatives.Na__DrawnPipe__WatchStale
        true
    rescue StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "DRAWN PIPE WATCH: selection observer not attached — #{error.message}"
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Let Go of the Watched Model
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__UnwatchModel
        if @na_pipe_watch_model && @na_pipe_watch_observer
            begin
                @na_pipe_watch_model.selection.remove_observer(@na_pipe_watch_observer)
            rescue StandardError
                nil                                                           # <-- A closed model's selection is gone with it
            end
        end

        @na_pipe_watch_model    = nil
        @na_pipe_watch_observer = nil
        @na_pipe_watch_answer   = nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Model Was Closed: Forget It If It Was the One Watched
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__WatchClosed(model)
        return unless model && model.equal?(@na_pipe_watch_model)

        @na_pipe_watch_model    = nil                                         # <-- No remove_observer: the model and its observers go together
        @na_pipe_watch_observer = nil
        @na_pipe_watch_answer   = nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Which Model Is Watched (for Checks)
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__WatchedModel
        @na_pipe_watch_model
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | The Answer: Which Pipes Are Selected
    # -----------------------------------------------------------------------------

    # FUNCTION | The Answer Is Out of Date: Refresh It Once, Soon
    # ------------------------------------------------------------
    # Any number of callbacks in a burst (a selection of a thousand, one by
    # one) make one refresh. Called from observer callbacks, so it only
    # forgets and schedules.
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__WatchStale
        @na_pipe_watch_answer = nil
        return if @na_pipe_watch_timer

        @na_pipe_watch_timer = UI.start_timer(0, false) do
            @na_pipe_watch_timer = nil
            Na__InsertPrimatives.Na__DrawnPipe__WatchRefresh
        end
    rescue StandardError
        @na_pipe_watch_timer = nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Count Again Now; Switch the Overlay On If There Is a Bar to Show
    # ------------------------------------------------------------
    # Redraws only when there is a bar to show or one to take away: most
    # transactions in a model have nothing to do with pipes.
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__WatchRefresh
        model = Sketchup.active_model
        return unless model

        pipes = Na__InsertPrimatives.Na__DrawnPipe__SelectedPipes(model)
        shown = Na__InsertPrimatives.Na__DrawnPipe__AutoBarOn? &&
                (!pipes.empty? || !Na__InsertPrimatives.Na__DrawnPipe__OpenEdit(model).nil?)
        was   = @na_pipe_watch_shown
        @na_pipe_watch_shown = shown

        Na__InsertPrimatives.Na__DrawnPipe__OverlayEnable(model) if shown && Na__InsertPrimatives.respond_to?(:Na__DrawnPipe__OverlayEnable)
        model.active_view.invalidate if (shown || was) && model.active_view
    rescue StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "DRAWN PIPE WATCH: refresh failed — #{error.message}"
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Pipes Selected in a Model, From the Answer If It Still Holds
    # ------------------------------------------------------------
    # The answer holds while it was counted for this model and the selection
    # still has the count it had. Pipes erased since are dropped on the way
    # out, so nothing handed on is ever a deleted entity.
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__SelectedPipes(model)
        return [] unless model

        selection = model.selection
        count     = selection.length.to_i
        answer    = @na_pipe_watch_answer

        unless answer && answer[:model].equal?(model) && answer[:count] == count
            pipes  = count > 0 ? selection.grep(Sketchup::Group).select { |group| Na__InsertPrimatives.Na__DrawnPipe__IsPipe?(group) } : []
            answer = { :model => model, :count => count, :pipes => pipes }
            @na_pipe_watch_answer = answer
        end

        answer[:pipes].select { |pipe| pipe.valid? }
    rescue StandardError
        []
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | The Bar Over the Select Tool
    # -----------------------------------------------------------------------------

    # FUNCTION | The One Pipework Tool That Serves the Bar (Made Once, Reused)
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__BarTool
        @na_pipe_bar_tool = DrawnPipeTool.new(:bar) unless @na_pipe_bar_tool.is_a?(DrawnPipeTool)
        @na_pipe_bar_tool
    end
    # ---------------------------------------------------------------

    # FUNCTION | What the Bar Would Show in This Model Now, or nil for No Bar
    # ------------------------------------------------------------
    # { :open => the open path edit or nil, :pipes => the selected pipes }.
    # Only over SketchUp's Select tool: any other tool is its own business,
    # and the Pipework tool draws its own bar.
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__AutoBarState(model, open = :unread)
        return nil unless model && Na__InsertPrimatives.Na__DrawnPipe__AutoBarOn?
        return nil unless model.tools.active_tool_id.to_i == NA_DRAWN_PIPE_SELECT_TOOL_ID

        open  = Na__InsertPrimatives.Na__DrawnPipe__OpenEdit(model) if open == :unread
        pipes = open ? [] : Na__InsertPrimatives.Na__DrawnPipe__SelectedPipes(model)
        return nil unless open || !pipes.empty?

        { :open => open, :pipes => pipes }
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Draw the Bar From the Overlay, When There Is One to Show
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__AutoBarDraw(view, open = :unread)
        state              = Na__InsertPrimatives.Na__DrawnPipe__AutoBarState(view.model, open)
        @na_pipe_bar_drawn = !state.nil?
        return false unless state

        tool = Na__InsertPrimatives.Na__DrawnPipe__BarTool
        tool.na_pipe__bar_present(state[:open], state[:pipes])
        tool.na_pipe__draw_bar(view)
        true
    rescue StandardError
        @na_pipe_bar_drawn = false
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Cursor Moved Over the View: Onto the Bar, Hand Over to the Tool
    # ------------------------------------------------------------
    # Called from the overlay's onMouseMove, so as cheap as it can be: it
    # does nothing unless the last frame drew the bar, and away from the
    # bar's box it lays nothing out (the box is the last frame's layout). A
    # button held down is a drag (a rubber band, an orbit) passing over, not
    # a visit.
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__AutoBarMouse(flags, x, y, view)
        return false unless @na_pipe_bar_drawn
        return false if (flags.to_i & NA_DRAWN_PIPE_MOUSE_BUTTONS) != 0

        tool = Na__InsertPrimatives.Na__DrawnPipe__BarTool
        if Na__InsertPrimatives.Na__DrawnPipe__BarClear?(tool.na_pipe__bar_buttons, x, y)
            view.invalidate if tool.na_pipe__bar_hover(nil)
            return false
        end

        button = tool.na_pipe__bar_at(view, x, y)
        view.invalidate if tool.na_pipe__bar_hover(button ? button[:id] : nil)
        return false unless button

        @na_pipe_bar_mouse = [x, y]
        Na__InsertPrimatives.Na__DrawnPipe__BarPush(view.model)
        true
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Where the Cursor Was When the Bar Was Reached (for the Tool's First Frame)
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__BarMouse
        @na_pipe_bar_mouse
    end
    # ---------------------------------------------------------------

    # FUNCTION | Push the Bar's Tool Over the Select Tool — Soon, Not From the Callback
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__BarPush(model)
        return false if @na_pipe_bar_pushing

        @na_pipe_bar_pushing = true
        UI.start_timer(0, false) do
            @na_pipe_bar_pushing = false

            begin
                tools = model.tools
                if model.equal?(Sketchup.active_model) && tools.active_tool_id.to_i == NA_DRAWN_PIPE_SELECT_TOOL_ID
                    tools.push_tool(Na__InsertPrimatives.Na__DrawnPipe__BarTool)
                end
            rescue StandardError => error
                Na__InsertPrimatives.Na__Debug__Puts "DRAWN PIPE WATCH: bar not opened — #{error.message}"
            end
        end
        true
    rescue StandardError
        @na_pipe_bar_pushing = false
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Pop the Bar's Tool, Back to Select — Soon, and Only If It Is on Top
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__BarPop(tool)
        return false if @na_pipe_bar_popping

        @na_pipe_bar_popping = true
        UI.start_timer(0, false) do
            @na_pipe_bar_popping = false

            begin
                model = Sketchup.active_model
                model.tools.pop_tool if model && model.tools.active_tool.equal?(tool)
            rescue StandardError => error
                Na__InsertPrimatives.Na__Debug__Puts "DRAWN PIPE WATCH: bar not closed — #{error.message}"
            end
        end
        true
    rescue StandardError
        @na_pipe_bar_popping = false
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is a Screen Point Clear of the Bar by the Let-Go Margin?
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__BarClear?(buttons, x, y)
        return true if buttons.nil? || buttons.empty?

        margin = NA_DRAWN_PIPE_BAR_LEAVE_PX
        rects  = buttons.map { |button| button[:rect] }.compact
        return true if rects.empty?

        left   = rects.map { |rect| rect[0] }.min - margin
        top    = rects.map { |rect| rect[1] }.min - margin
        right  = rects.map { |rect| rect[2] }.max + margin
        bottom = rects.map { |rect| rect[3] }.max + margin

        x.to_f < left || x.to_f > right || y.to_f < top || y.to_f > bottom
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # =============================================================================
    # REGION | Observer Class
    # =============================================================================
    # Every callback says the same thing: the selection moved. onSelectedRemoved
    # is the old spelling SketchUp still calls on some versions.

    # CLASS | The Active Model's Selection Moved
    # ------------------------------------------------------------
    class DrawnPipeSelectionObserver < Sketchup::SelectionObserver
        def onSelectionBulkChange(_selection);       na_pipe__moved; end
        def onSelectionCleared(_selection);          na_pipe__moved; end
        def onSelectionAdded(_selection, _entity);   na_pipe__moved; end
        def onSelectionRemoved(_selection, _entity); na_pipe__moved; end
        def onSelectedRemoved(_selection, _entity);  na_pipe__moved; end

        def na_pipe__moved
            Na__InsertPrimatives.Na__DrawnPipe__WatchStale
        rescue StandardError
            nil
        end
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DRAWN PIPE WATCH
# =============================================================================
