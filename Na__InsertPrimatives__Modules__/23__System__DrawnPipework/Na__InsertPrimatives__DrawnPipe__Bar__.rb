# =============================================================================
# NA INSERT PRIMATIVES - DRAWN PIPE BAR
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnPipe__Bar__.rb
# NAMESPACE  : Na__InsertPrimatives::DrawnPipeBar
# AUTHOR     : Noble Architecture
# PURPOSE    : The Pipework tool's bar at the top left of the view: the actions
#              of the moment, and the spec to click and type into
# CREATED    : 2026
#
# DESCRIPTION:
# - Deep Scale's handle bar, drawn by the same functions so the two look and
#   behave alike (Na__ScalePreview__BarLayout / __DrawBar / __InRect?): it
#   stands at a fixed place, blue is the slot being typed into, green is on.
# - LEFT, what can be done now:
#     route    Build
#     resize   Edit Path (one pipe)
#     edit     Finish  Discard  |  Move  Line (SketchUp's own tools, for the
#              red line)
#     drawing  Finish  Close Loop  Back
#     after    Edit Path (the pipe just built)
# - RIGHT, the spec: Ø, R, sides and Bore. Click one and it turns blue in
#   brackets: a plain number typed next goes to it (100 Enter is a 100
#   diameter), and it stays armed for the next try until clicked again or
#   ESC. Bore Off turns the bore on and arms it; clicking an armed bore makes
#   the pipe solid again. Caps closes or opens the ends.
# - What the spec buttons change depends on the mode: the next pipe (drawing,
#   route), each selected pipe (resize), or the pipe being re-routed (edit,
#   applied at once to the preview and built at the finish).
# - The same bar shows over SketchUp's Select tool when pipes are selected
#   (DrawnPipe__Watch__): the overlay draws it through a DrawnPipeTool in its
#   bar role, which is pushed over Select while the cursor is on it.
#
# HOST CONTRACT (DrawnPipeTool):
#   @na_pipe_mode, @na_pipe_resize, @na_pipe_edit, @na_pipe_built,
#   @na_pipe_points, @na_pipe_slot, @na_pipe_hover
#   na_pipe__drawing?, na_pipe__revise_available?, na_pipe__build_route,
#   na_pipe__finish, na_pipe__step_back, na_pipe__apply_text, na_pipe__say,
#   na_pipe__caps_option?, na_pipe__after_setting_changed, na_pipe__reread
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__InsertPrimatives__DrawnPipe__Spec__'
require_relative 'Na__InsertPrimatives__DrawnPipe__Build__'
require_relative 'Na__InsertPrimatives__DrawnPipe__Edit__'

module Na__InsertPrimatives

    # =============================================================================
    # MODULE | Pipework Tool Bar
    # =============================================================================

    module DrawnPipeBar

        NA_PIPE_BAR_SLOT_NAMES = {
            :diameter => 'Diameter',
            :bend     => 'Bend radius',
            :sides    => 'Sides',
            :inner    => 'Bore'
        }.freeze

        # -----------------------------------------------------------------------------
        # REGION | What the Bar Shows
        # -----------------------------------------------------------------------------

        # FUNCTION | The Spec the Bar Is Showing and Changing
        # ------------------------------------------------------------
        def na_pipe__bar_spec
            pipe = na_pipe__bar_pipe
            spec = pipe ? Na__InsertPrimatives.Na__DrawnPipe__StoredSpec(pipe) : nil
            spec || Na__InsertPrimatives.Na__DrawnPipe__CurrentSpec
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Pipe the Bar Is Changing, or nil for the Next Pipe
        # ------------------------------------------------------------
        def na_pipe__bar_pipe
            case @na_pipe_mode
            when :edit   then @na_pipe_edit ? @na_pipe_edit[:pipe] : nil
            when :resize then @na_pipe_resize.find { |pipe| pipe.valid? }
            else              nil
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Are the Ends Closed, for What the Bar Is Changing?
        # Read on its own, not through StoredRoute: the bar over the Select
        # tool asks every frame, and the route is every point of the pipe.
        # ------------------------------------------------------------
        def na_pipe__bar_caps?
            pipe = na_pipe__bar_pipe
            return na_pipe__caps_option? unless pipe

            caps = pipe.get_attribute(NA_DRAWN_PIPE_DICTIONARY, 'Caps')
            caps.nil? ? true : (caps ? true : false)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Every Button, Left to Right
        # ------------------------------------------------------------
        def na_pipe__bar_entries
            entries = na_pipe__bar_actions
            entries << { :gap => true } unless entries.empty?

            spec = na_pipe__bar_spec
            bend = spec[:bend].to_f > 0.0 ? "R #{Na__InsertPrimatives.Na__DrawnPipe__FormatMm(spec[:bend])}" : 'Mitred'

            entries << na_pipe__slot_entry(:diameter, "Ø #{Na__InsertPrimatives.Na__DrawnPipe__FormatMm(spec[:diameter])}",
                                           'Diameter — click, then type it and press Enter')
            entries << na_pipe__slot_entry(:bend, bend,
                                           'Bend radius, to the centre of the pipe — click, then type it; 0 mitres the corners')
            entries << na_pipe__slot_entry(:sides, "#{spec[:sides]} sides",
                                           'Facets round the pipe — click, then type a number (the popup\'s Circle Sides too)')
            entries << na_pipe__bore_entry(spec)
            entries << { :gap => true }

            caps_tip = spec[:inner].to_f > 0.0 ? 'Caps — a hollow pipe\'s ends are its walls, so this waits for a solid one' :
                                                 'Caps — close the ends (off: open tubes, for ends hidden in walls)'
            entries << { :id => 'caps', :text => 'Caps', :state => na_pipe__bar_caps? ? :on : :plain, :tip => caps_tip }
            entries
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Actions of the Moment
        # ------------------------------------------------------------
        def na_pipe__bar_actions
            case @na_pipe_mode
            when :route
                [{ :id => 'build', :text => 'Build', :state => :plain, :tip => 'Build the pipe along the selected edges (Enter)' }]
            when :resize
                return [] unless @na_pipe_resize.length == 1

                [{ :id => 'edit_path', :text => 'Edit Path', :state => :plain, :tip => 'Re-route this pipe: its path comes out as a red line to edit with any tool' }]
            when :edit
                [
                    { :id => 'finish',  :text => 'Finish',  :state => :plain, :tip => 'Rebuild the pipe along the red line now (Enter, or click outside the pipe)' },
                    { :id => 'discard', :text => 'Discard', :state => :plain, :tip => 'Throw the red line away: the pipe keeps the route it had' },
                    { :gap => true },
                    { :id => 'move',    :text => 'Move',    :state => :plain, :tip => 'SketchUp\'s Move tool, to drag the line\'s points (the pipe follows)' },
                    { :id => 'line',    :text => 'Line',    :state => :plain, :tip => 'SketchUp\'s Line tool, to draw the route on from a point' }
                ]
            else
                if na_pipe__drawing?
                    actions = [{ :id => 'run_finish', :text => 'Finish', :state => :plain, :tip => 'Build the run as drawn (Enter, or double click)' }]
                    actions << { :id => 'run_close', :text => 'Close Loop', :state => :plain, :tip => 'Join the last point to the first and build a loop' } if @na_pipe_points.length >= 3
                    actions << { :id => 'run_back', :text => 'Back', :state => :plain, :tip => 'Take back the last point (BKSP)' }
                    actions
                elsif na_pipe__revise_available? && @na_pipe_built.length == 1
                    [{ :id => 'edit_path', :text => 'Edit Path', :state => :plain, :tip => 'Re-route the pipe just built: its path comes out as a red line' }]
                else
                    []
                end
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | One Spec Button, Blue and Bracketed While It Is Armed
        # ------------------------------------------------------------
        def na_pipe__slot_entry(slot, text, tip)
            armed = @na_pipe_slot == slot
            {
                :id    => "slot:#{slot}",
                :text  => armed ? "[#{text}]" : text,
                :state => armed ? :mode : :plain,
                :tip   => armed ? "Type the #{NA_PIPE_BAR_SLOT_NAMES[slot].downcase} and press Enter — click again to stop" : tip
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Bore Button: Off, On (Green) or Armed (Blue)
        # ------------------------------------------------------------
        def na_pipe__bore_entry(spec)
            inner = spec[:inner].to_f
            armed = @na_pipe_slot == :inner

            if inner <= 0.0
                return { :id => 'bore', :text => 'Bore Off', :state => :plain,
                         :tip => 'Solid — click for a true, hollow pipe, then type its internal diameter' }
            end

            text = "Bore #{Na__InsertPrimatives.Na__DrawnPipe__FormatMm(inner)}"
            {
                :id    => 'bore',
                :text  => armed ? "[#{text}]" : text,
                :state => armed ? :mode : :on,
                :tip   => armed ? 'Type the internal diameter and press Enter — click again for a solid pipe' :
                                  'Internal diameter — click, then type it (5w types a wall instead)'
            }
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Layout, Hit and Draw
        # -----------------------------------------------------------------------------

        # FUNCTION | Can the Bar Be Drawn? (Deep Scale's Renderer Is Loaded)
        # ------------------------------------------------------------
        def na_pipe__bar_ready?
            Na__InsertPrimatives.respond_to?(:Na__ScalePreview__BarLayout) &&
                Na__InsertPrimatives.respond_to?(:Na__ScalePreview__DrawBar)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Lay the Bar Out for This View
        # ------------------------------------------------------------
        def na_pipe__bar_layout(view)
            @na_pipe_bar = na_pipe__bar_ready? ? Na__InsertPrimatives.Na__ScalePreview__BarLayout(view, na_pipe__bar_entries) : []
        rescue StandardError
            @na_pipe_bar = []
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Button Under the Cursor, or nil
        # ------------------------------------------------------------
        def na_pipe__bar_at(view, x, y)
            na_pipe__bar_layout(view)
            (@na_pipe_bar || []).find { |button| Na__InsertPrimatives.Na__ScalePreview__InRect?(button[:rect], x, y) }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw the Bar, and the Hovered Button's Tip Under It
        # ------------------------------------------------------------
        def na_pipe__draw_bar(view)
            return unless na_pipe__bar_ready?

            na_pipe__bar_layout(view)
            Na__InsertPrimatives.Na__ScalePreview__DrawBar(view, @na_pipe_bar, @na_pipe_hover)
            return unless @na_pipe_hover

            button = @na_pipe_bar.find { |entry| entry[:id] == @na_pipe_hover }
            return unless button && button[:tip]

            Na__InsertPrimatives.Na__DrawnPreview__DrawScreenText(
                view, button[:rect][0], button[:rect][3] + 8, button[:tip], NA_DRAWN_TEXT_ACCENT_COLOR
            )
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Clicks
        # -----------------------------------------------------------------------------

        # FUNCTION | A Bar Button Was Clicked
        # ------------------------------------------------------------
        def na_pipe__bar_click(view, button)
            id = button[:id].to_s

            case id
            when 'build'      then na_pipe__build_route
            when 'edit_path'  then na_pipe__bar_edit_path
            when 'finish'     then na_pipe__bar_finish
            when 'discard'    then na_pipe__bar_discard
            when 'move'       then Sketchup.send_action('selectMoveTool:')
            when 'line'       then Sketchup.send_action('selectLineTool:')
            when 'run_finish' then na_pipe__finish(view, false)
            when 'run_close'  then na_pipe__finish(view, true)
            when 'run_back'   then na_pipe__step_back
            when 'caps'       then na_pipe__bar_caps
            when 'bore'       then na_pipe__bar_bore
            else
                na_pipe__bar_arm(id.sub('slot:', '').to_sym) if id.start_with?('slot:')
            end

            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Arm a Spec Slot for the Next Typed Value (Again to Let Go)
        # ------------------------------------------------------------
        def na_pipe__bar_arm(slot)
            return unless NA_PIPE_BAR_SLOT_NAMES.key?(slot)

            @na_pipe_slot      = (@na_pipe_slot == slot) ? nil : slot
            @na_last_vcb_label = nil
            @na_last_vcb_text  = nil

            if @na_pipe_slot
                na_pipe__say("Type the #{NA_PIPE_BAR_SLOT_NAMES[slot].downcase} and press Enter — it applies at once")
            else
                na_pipe__say("#{NA_PIPE_BAR_SLOT_NAMES[slot]} let go — typing works as before")
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Bore: Off Turns It On and Arms It; Armed Turns It Off
        # ------------------------------------------------------------
        def na_pipe__bar_bore
            spec = na_pipe__bar_spec

            if spec[:inner].to_f > 0.0
                return na_pipe__bar_arm(:inner) unless @na_pipe_slot == :inner

                @na_pipe_slot = nil
                return na_pipe__apply_text('0i')
            end

            wall  = Na__InsertPrimatives.Na__DrawnPipe__RememberedWallMm
            inner = spec[:diameter].to_f * NA_DRAWN_INCH_TO_MM - 2.0 * wall
            inner = spec[:diameter].to_f * NA_DRAWN_INCH_TO_MM * 0.8 unless inner > 0.0

            na_pipe__apply_text("#{inner.round(1)}i")
            @na_pipe_slot = :inner
            @na_last_vcb_label = nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Caps: the Next Pipe's Option, or Each Pipe's Own
        # ------------------------------------------------------------
        def na_pipe__bar_caps
            pipe = na_pipe__bar_pipe
            unless pipe
                Na__InsertPrimatives.Na__ToolOptions__Toggle(DrawnPipeTool::NA_PIPE_CAPS_OPTION)
                Na__InsertPrimatives.Na__RightClickPopup__RefreshOption(DrawnPipeTool::NA_PIPE_CAPS_OPTION) if Na__InsertPrimatives.respond_to?(:Na__RightClickPopup__RefreshOption)
                na_pipe__after_setting_changed
                return na_pipe__say(na_pipe__caps_option? ? 'End Caps on: new pipes are solid to their ends' : 'End Caps off: new pipes are open tubes')
            end

            wanted = !na_pipe__bar_caps?
            model  = Sketchup.active_model

            if @na_pipe_mode == :edit
                model.start_operation('Pipework Caps', true)
                pipe.set_attribute(NA_DRAWN_PIPE_DICTIONARY, 'Caps', wanted)
                model.commit_operation
                return na_pipe__say("Caps #{wanted ? 'on' : 'off'} — the pipe is built that way at the finish")
            end

            targets = @na_pipe_resize.select { |group| group.valid? && !Na__InsertPrimatives.Na__DrawnPipe__EditGroupOf(group) }
            model.start_operation('Pipework Caps', true)
            targets.each do |group|
                Na__InsertPrimatives.Na__DrawnPipe__RebuildGroup(group, Na__InsertPrimatives.Na__DrawnPipe__StoredSpec(group), nil, wanted)
            end
            model.commit_operation
            na_pipe__say("Caps #{wanted ? 'on' : 'off'} on #{targets.length} pipe#{targets.length == 1 ? '' : 's'}")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Edit Path From the Bar
        # ------------------------------------------------------------
        def na_pipe__bar_edit_path
            pipe = @na_pipe_mode == :resize ? @na_pipe_resize.first : @na_pipe_built.find { |group| group.valid? }
            return false unless pipe

            result = Na__InsertPrimatives.Na__DrawnPipe__EditOpen(pipe)
            na_pipe__reread if result[:ok]
            result[:ok]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Finish the Edit From the Bar
        # ------------------------------------------------------------
        def na_pipe__bar_finish
            return false unless @na_pipe_edit

            result = Na__InsertPrimatives.Na__DrawnPipe__EditFinishNow(@na_pipe_edit[:pipe])
            na_pipe__reread
            result[:ok]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Discard the Edit From the Bar
        # ------------------------------------------------------------
        def na_pipe__bar_discard
            return false unless @na_pipe_edit

            result = Na__InsertPrimatives.Na__DrawnPipe__EditDiscard(@na_pipe_edit[:pipe])
            na_pipe__reread
            result[:ok]
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnPipeBar module

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DRAWN PIPE BAR
# =============================================================================
