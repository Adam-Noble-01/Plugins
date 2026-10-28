# =============================================================================
# NA INSERT PRIMATIVES - DEEP SCALE OVERLAY (HANDLE BAR AND DIMENSIONS)
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnScale__Overlay__.rb
# NAMESPACE  : Na__InsertPrimatives::DrawnScaleOverlay
# AUTHOR     : Noble Architecture
# PURPOSE    : The on-screen handle bar and the dimensions you click to type
# CREATED    : 2026
#
# DESCRIPTION:
# - CONTROL HANDLES. On a door 40 thick and 900 wide every grip on the thin
#   side sits on top of another, and picking the right one is a guess. The
#   bar at the top left of the view decides which grips are offered: All,
#   Faces, Corners, or one axis. One click, and the choice is remembered
#   between sessions (it is the Handles option of the right-click menu, so
#   the two always agree). The arrow keys pick one axis for a moment without
#   changing what is remembered, the way they lock an axis in every tool.
# - The bar also carries Planes (Stretch Planes, SHIFT+TAB), Centre (About
#   Centre, TAB) and Dims (Show Dimensions), green when on, as in the popup.
#   Under it, a line of help for the planes (Planes file).
# - SHOW DIMENSIONS. The object's size is drawn on three of its edges,
#   outside its outline, in the axis colours. Click one and it turns orange
#   in brackets: the next value typed is that axis's new size, applied at
#   once. During a drag the dimensions the drag is changing read the live
#   size in the preview's amber.
#
# HOST CONTRACT (DrawnScaleTool):
#   @na_sc_frame, @na_sc_drag, @na_sc_active_dim, @na_axis_lock
#   na_scale__handle_set, na_scale__planes_on?, na_scale__centre_on?,
#   na_scale__dims_on?, na_scale__dim_size, na_scale__dim_offset,
#   na_scale__after_option_changed, na_scale__say
#
# =============================================================================

require 'sketchup.rb'

module Na__InsertPrimatives

    # =============================================================================
    # MODULE | Deep Scale Handle Bar and Dimensions
    # =============================================================================

    module DrawnScaleOverlay

        NA_SCALE_BAR_HANDLES = [
            ['all',     'All',     'Every grip: corners, edges and faces'],
            ['faces',   'Faces',   'Face grips only, one axis per grip'],
            ['corners', 'Corners', 'Corner grips only: uniform scale, SHIFT to free it'],
            ['x',       'X',       'Only the two grips that pull X (red); RIGHT ARROW for a moment'],
            ['y',       'Y',       'Only the two grips that pull Y (green); LEFT ARROW for a moment'],
            ['z',       'Z',       'Only the two grips that pull Z (blue); UP ARROW for a moment']
        ].freeze

        # -----------------------------------------------------------------------------
        # REGION | Handle Bar
        # -----------------------------------------------------------------------------

        # FUNCTION | The Bar's Buttons and the State Each Is In
        # ------------------------------------------------------------
        # The handle set in force is the arrow lock while one is held, so the
        # bar never shows one thing while the grips do another.
        # ------------------------------------------------------------
        def na_scale__bar_entries
            stored  = Na__InsertPrimatives.Na__ToolOptions__Value(NA_SCALE_OPTION_HANDLES).to_s
            showing = @na_axis_lock ? @na_axis_lock.to_s : stored
            entries = NA_SCALE_BAR_HANDLES.map do |value, text, tip|
                { :id => "handles:#{value}", :text => text, :state => (showing == value ? :mode : :plain), :tip => tip }
            end

            entries << { :gap => true }
            entries << {
                :id    => NA_SCALE_OPTION_PLANES,
                :text  => 'Planes',
                :state => na_scale__planes_on? ? :on : :plain,
                :tip   => @na_sc_frame && @na_sc_frame[:loose] ?
                          'Stretch Planes need a group or component to be saved with — loose geometry scales whole' :
                          'SHIFT+TAB — Stretch Planes: grips stretch at the cut planes; click a centre line, or hold CTRL, to add one'
            }
            entries << {
                :id    => NA_SCALE_OPTION_CENTRE,
                :text  => 'Centre',
                :state => na_scale__centre_on? ? :on : :plain,
                :tip   => 'TAB — About Centre: both sides move at once'
            }
            entries << {
                :id    => NA_SCALE_OPTION_DIMS,
                :text  => 'Dims',
                :state => na_scale__dims_on? ? :on : :plain,
                :tip   => 'Show Dimensions: click one and type the exact size'
            }

            entries
        end
        # ---------------------------------------------------------------

        # FUNCTION | Lay the Bar Out for This View
        # ------------------------------------------------------------
        def na_scale__layout_bar(view)
            @na_sc_bar = Na__InsertPrimatives.Na__ScalePreview__BarLayout(view, na_scale__bar_entries)
        rescue StandardError
            @na_sc_bar = []
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Bar Button Under the Cursor, or nil
        # ------------------------------------------------------------
        def na_scale__bar_at(view, x, y)
            na_scale__layout_bar(view)
            (@na_sc_bar || []).find { |button| Na__InsertPrimatives.Na__ScalePreview__InRect?(button[:rect], x, y) }
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Bar Button Was Clicked
        # ------------------------------------------------------------
        # A handle set chosen here is the remembered one, so any arrow lock
        # is let go: the click is the newer decision.
        # ------------------------------------------------------------
        def na_scale__bar_click(view, button)
            id = button[:id].to_s

            if id.start_with?('handles:')
                value = id.sub('handles:', '')
                Na__InsertPrimatives.Na__ToolOptions__SetValue(NA_SCALE_OPTION_HANDLES, value)
                Na__InsertPrimatives.Na__RightClickPopup__RefreshOption(NA_SCALE_OPTION_HANDLES)
                @na_axis_lock = nil

                na_scale__say(Na__InsertPrimatives.Na__ToolOptions__CaptionFor(NA_SCALE_OPTION_HANDLES))
                return true
            end

            Na__InsertPrimatives.Na__ToolOptions__Toggle(id)
            Na__InsertPrimatives.Na__RightClickPopup__RefreshOption(id)
            na_scale__after_option_changed(id)

            na_scale__say(Na__InsertPrimatives.Na__ToolOptions__CaptionFor(id))
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw the Bar and the Hovered Button's Tip
        # ------------------------------------------------------------
        def na_scale__draw_bar(view)
            na_scale__layout_bar(view)
            hover = @na_sc_hover && @na_sc_hover[:kind] == :bar ? @na_sc_hover[:id] : nil

            Na__InsertPrimatives.Na__ScalePreview__DrawBar(view, @na_sc_bar, hover)
            return unless hover

            button = @na_sc_bar.find { |entry| entry[:id] == hover }
            return unless button && button[:tip]

            Na__InsertPrimatives.Na__DrawnPreview__DrawScreenText(
                view, button[:rect][0], button[:rect][3] + 8, button[:tip], NA_DRAWN_TEXT_ACCENT_COLOR
            )
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Dimensions
        # -----------------------------------------------------------------------------

        # FUNCTION | Lay the Three Dimensions Out for the Box Being Shown
        # ------------------------------------------------------------
        # mins / maxs and lengths are the box the dimensions describe — the
        # object's own, or the one a drag is about to make. live names the
        # axes the drag is changing. typed holds what is being typed into the
        # measurements box, per axis it will land on: those dimensions show
        # the typed text instead of the size, so the box is mirrored where
        # the eye already is.
        # ------------------------------------------------------------
        def na_scale__layout_dims(view, mins = nil, maxs = nil, lengths = nil, live = [], typed = {})
            @na_sc_dims = []
            frame = @na_sc_frame
            return @na_sc_dims unless frame && na_scale__dims_on?

            lo     = mins    || frame[:min]
            hi     = maxs    || frame[:max]
            sizes  = lengths || frame[:world_lengths]
            size   = na_scale__dim_size
            offset = na_scale__dim_offset

            NA_SCALE_AXES.each_with_index do |axis, n|
                next unless frame[:usable][n]

                layout = Na__InsertPrimatives.Na__ScalePreview__DimensionLayout(view, frame, lo, hi, axis, offset)
                next unless layout

                text = (typed || {})[axis] || "#{Na__InsertPrimatives.Na__DrawnFormat__Mm(sizes[n])} mm"

                # The text sits ON the dimension line, so half of it reaches
                # back towards the object. On a vertical edge that half is
                # wider than the offset and the label would lie over the
                # object and its grips; the line is pushed out until it clears.
                width, height = Na__InsertPrimatives.Na__ScalePreview__TextSize(view, text, size, true)
                reach = (layout[:out][0].abs * ((width * 0.5) + NA_SCALE_PILL_PAD_X)) +
                        (layout[:out][1].abs * ((height * 0.5) + NA_SCALE_PILL_PAD_Y)) + 6.0

                if reach > offset
                    wider  = Na__InsertPrimatives.Na__ScalePreview__DimensionLayout(view, frame, lo, hi, axis, reach)
                    layout = wider if wider
                end

                rect = Na__InsertPrimatives.Na__ScalePreview__PillRect(view, layout, text, size)

                @na_sc_dims << {
                    :axis   => axis,
                    :layout => layout,
                    :rect   => rect,
                    :text   => text,
                    :live   => live.include?(axis),
                    :typed  => (typed || {}).key?(axis)
                }
            end

            @na_sc_dims
        rescue StandardError
            @na_sc_dims = []
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Dimension Under the Cursor, or nil
        # ------------------------------------------------------------
        def na_scale__dim_at(view, x, y)
            na_scale__layout_dims(view)
            (@na_sc_dims || []).find { |dim| Na__InsertPrimatives.Na__ScalePreview__InRect?(dim[:rect], x, y) }
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Dimension Was Clicked — It Takes the Next Typed Value
        # A second click on the same one lets it go again.
        # ------------------------------------------------------------
        def na_scale__dim_click(view, dim)
            axis = dim[:axis]

            if @na_sc_active_dim == axis && @na_sc_focus == :dimension
                @na_sc_active_dim = nil
                @na_sc_focus      = nil
                na_scale__say('Dimension released — a typed X,Y,Z sets the sizes in order')
                return true
            end

            @na_sc_active_dim   = axis
            @na_sc_focus        = :dimension
            @na_sc_active_plane = nil
            @na_last_vcb_text   = nil

            na_scale__say(
                "Type the new #{axis.to_s.upcase} size and press Enter — 1200, +50, -25, 1.5x — it resizes at once"
            )
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw the Dimensions Laid Out Last
        # ------------------------------------------------------------
        def na_scale__draw_dims(view)
            size  = na_scale__dim_size
            hover = @na_sc_hover && @na_sc_hover[:kind] == :dim ? @na_sc_hover[:axis] : nil

            (@na_sc_dims || []).each do |dim|
                state =
                    if dim[:typed]
                        :typing
                    elsif dim[:live]
                        :live
                    elsif @na_sc_focus == :dimension && @na_sc_active_dim == dim[:axis]
                        :active
                    elsif hover == dim[:axis]
                        :hover
                    else
                        :plain
                    end

                Na__InsertPrimatives.Na__ScalePreview__DrawDimension(view, dim[:layout], dim[:rect], dim[:text], size, state)
            end
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnScaleOverlay module

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP SCALE OVERLAY (HANDLE BAR AND DIMENSIONS)
# =============================================================================
