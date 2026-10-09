# =============================================================================
# NA INSERT PRIMATIVES - DEEP CHAMFER SCRUB DRAG
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnChamfer__Scrub__.rb
# NAMESPACE  : Na__InsertPrimatives::DrawnChamferScrub
# AUTHOR     : Noble Architecture
# PURPOSE    : The size drag of Chamfer, Fillet, Ogee and Ovolo: it opens at a
#              quarter of the largest cut, and the mouse scrubs it up and down
# CREATED    : 2026
#
# DESCRIPTION:
# - The drag used to follow the cursor into the corner: the cut grew as the
#   mouse moved along the bisector, into the material. On the top edge of a
#   box seen from above, "into the material" is DOWN the screen, so pulling
#   the mouse down made the cut bigger — the opposite of every slider and
#   scrub control. Asked for: "mouse down = less chamfer, mouse drag up =
#   more chamfer", starting from a 25% chamfer of what the faces allow.
# - So the drag is now a vertical scrub, the same on every edge in every view:
#     grab        the preview opens at 25% of the largest cut the faces allow
#                 (DrawnChamferLimit measures it), already showing the cut
#     drag up     more, toward the full size
#     drag down   less, down to nothing
#   then drag or type to taste. Which way the edge runs on screen no longer
#   matters at all.
#
# THE CURVE (a fraction of the largest cut, against pixels dragged):
#   linear from nothing to 75%, then easing onto 100%, which it reaches with
#   no slope and never passes:
#     u = opening + (pixels up) / span
#     f = u                        u <= 0.75
#     f = 0.75 + t - t^2           t = u - 0.75, up to 0.5
#     f = 1                        beyond
#   span is 320 logical pixels: from the 25% opening, 80 px down closes the
#   cut, 160 px up reaches 75%, and the last quarter takes 160 px more — the
#   fine end of the drag, where the last few millimetres matter. Pixels, not
#   model units, so the drag feels the same zoomed in on a 5 mm arris or out
#   on a 300 mm plinth.
#
# GRID:
# - The result snaps to the grid, as before. A grid coarser than the whole
#   cut (a 25 mm step on a 10 mm corner) is ignored, so a small corner still
#   scrubs smoothly instead of jumping between nothing and everything.
#
# CTRL:
# - Vertex snapping is unchanged and absolute: the inferred vertex's place
#   along the bisector sets the size, exactly as before.
#
# NO LIMIT:
# - On the rare corner whose faces cannot be measured, the drag opens at the
#   last size used (or 40 pixels' worth) and moves a pixel's worth of model
#   per pixel, with no ceiling.
#
# REBASING:
# - Anything that sets the size from outside the drag — a profile swapped in
#   from the menu or the keyboard, TAB changing the limit — rebases the
#   scrub, so the next mouse move carries on from that size without a jump.
#
# HOST CONTRACT — included by DrawnChamferTool. The host calls na_sc__begin
# from its grab (after measuring @na_ch_max_size) and na_sc__size_at from its
# cursor update, and reads @na_ch_max_size, @na_ch_anchor and the revise
# memory.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnGridSnap__'

module Na__InsertPrimatives

    module DrawnChamferScrub

        # -----------------------------------------------------------------------------
        # REGION | Scrub Constants
        # -----------------------------------------------------------------------------

        NA_SC_OPENING     = 0.25                                              # <-- The preview opens at this fraction of the largest cut
        NA_SC_KNEE        = 0.75                                              # <-- Linear up to here, easing beyond
        NA_SC_TAIL        = 2.0 * (1.0 - NA_SC_KNEE)                          # <-- How much drag the ease takes to land on 100% (0.5 span)
        NA_SC_SPAN_PX     = 320.0                                             # <-- Logical pixels of drag from nothing to 100%, before the ease
        NA_SC_FALLBACK_PX = 40.0                                              # <-- No limit and no memory: open at this many pixels' worth

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | The Curve
        # -----------------------------------------------------------------------------

        # FUNCTION | Fraction of the Largest Cut for a Scrub Position
        # ------------------------------------------------------------
        def na_sc__curve(u)
            u = u.to_f
            return 0.0 if u <= 0.0
            return u if u <= NA_SC_KNEE

            t = u - NA_SC_KNEE
            return 1.0 if t >= NA_SC_TAIL

            NA_SC_KNEE + t - ((t * t) / (2.0 * NA_SC_TAIL))
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Scrub Position That Gives a Fraction
        # The inverse of na_sc__curve, so a size set from outside the drag can
        # be carried on from without a jump.
        # ------------------------------------------------------------
        def na_sc__curve_inverse(fraction)
            fraction = fraction.to_f
            return 0.0 if fraction <= 0.0
            return fraction if fraction <= NA_SC_KNEE
            return NA_SC_KNEE + NA_SC_TAIL if fraction >= 1.0

            room = 1.0 - ((2.0 * (fraction - NA_SC_KNEE)) / NA_SC_TAIL)
            NA_SC_KNEE + (NA_SC_TAIL * (1.0 - Math.sqrt([room, 0.0].max)))
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Screen and Grid
        # -----------------------------------------------------------------------------

        # FUNCTION | Physical Pixels per Logical Pixel on This View's Monitor
        # Mouse positions arrive in physical pixels, so the span is scaled to
        # keep the drag the same length to the eye on a high-DPI screen.
        # ------------------------------------------------------------
        def na_sc__scale_factor(view)
            return 1.0 unless UI.respond_to?(:scale_factor)

            factor =
                begin
                    UI.scale_factor(view)
                rescue ArgumentError, TypeError
                    UI.scale_factor                                           # <-- Older SketchUp: the one-argument form is missing
                end

            factor.to_f > 0.0 ? factor.to_f : 1.0
        rescue StandardError
            1.0
        end
        # ---------------------------------------------------------------

        # FUNCTION | Model Inches One Mouse Pixel Is Worth at the Grab Point
        # Only the no-limit fallback drags in model units.
        # ------------------------------------------------------------
        def na_sc__pixel_world(view)
            return 0.04 unless view && @na_ch_anchor                         # <-- About a millimetre, if the view cannot say

            size = view.pixels_to_model(1.0, @na_ch_anchor).to_f / na_sc__scale_factor(view)
            size > 0.0 ? size : 0.04
        rescue StandardError
            0.04
        end
        # ---------------------------------------------------------------

        # FUNCTION | Snap a Scrubbed Size, Unless the Grid Is Coarser Than the Cut
        # ------------------------------------------------------------
        def na_sc__snap(raw)
            max = @na_ch_max_size
            if max && max.to_f > 0.0 && Na__InsertPrimatives.Na__DrawnGrid__StepInches > max.to_f
                return raw.to_f                                               # <-- One grid step would swallow the whole corner
            end

            na_drawn__snap_distance(raw).to_f
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Opening, Rebasing and Reading the Scrub
        # -----------------------------------------------------------------------------

        # FUNCTION | The Size the Preview Opens At
        # A quarter of the largest cut, on the grid; one grid step when the
        # quarter rounds away to nothing. Nothing at all when the faces allow
        # nothing (a step too wide for a narrow face). With no limit measured,
        # the last size used, or a few pixels' worth.
        # ------------------------------------------------------------
        def na_sc__opening_size(view)
            max = @na_ch_max_size

            unless max.nil?
                return 0.0 unless max.to_f > 0.0

                raw     = max.to_f * NA_SC_OPENING
                snapped = na_sc__snap(raw)
                return snapped if snapped > 0.0 && snapped <= max.to_f

                return [Na__InsertPrimatives.Na__DrawnGrid__StepInches, max.to_f].min
            end

            if respond_to?(:na_revise__memory?) && na_revise__memory?
                return @na_revise_memory.to_f.abs
            end

            worth    = NA_SC_FALLBACK_PX * na_sc__scale_factor(view) * na_sc__pixel_world(view)
            snapped  = na_sc__snap(worth)
            snapped > 0.0 ? snapped : worth
        end
        # ---------------------------------------------------------------

        # FUNCTION | Start the Scrub Where the Press Landed; Returns the Opening Size
        # ------------------------------------------------------------
        def na_sc__begin(view, press_y)
            @na_sc_span  = NA_SC_SPAN_PX * na_sc__scale_factor(view)
            @na_sc_pixel = na_sc__pixel_world(view)

            opening = na_sc__opening_size(view)
            na_sc__rebase(press_y, opening)
            opening
        end
        # ---------------------------------------------------------------

        # FUNCTION | Carry the Scrub On From a Size Set Outside the Drag
        # The size at screen height y becomes this one, so the next mouse move
        # moves from here. Without a measured limit the scrub runs in model
        # units, and its base is the size itself.
        # ------------------------------------------------------------
        def na_sc__rebase(y, size)
            @na_sc_y0 = y.to_f
            max       = @na_ch_max_size

            @na_sc_u0 =
                if max && max.to_f > 0.0
                    na_sc__curve_inverse(size.to_f / max.to_f)
                else
                    size.to_f
                end
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Scrubbed Size at a Screen Height, Snapped and Clamped
        # Up the screen is more (screen y grows downward). nil before a scrub
        # has begun, so a stray call changes nothing.
        # ------------------------------------------------------------
        def na_sc__size_at(view, y)
            return nil unless @na_sc_y0 && @na_sc_u0

            span = @na_sc_span || (NA_SC_SPAN_PX * na_sc__scale_factor(view))
            up   = @na_sc_y0 - y.to_f
            max  = @na_ch_max_size

            raw =
                if max.nil?
                    @na_sc_u0 + (up * (@na_sc_pixel || na_sc__pixel_world(view)))
                elsif max.to_f > 0.0
                    max.to_f * na_sc__curve(@na_sc_u0 + (up / span))
                else
                    0.0                                                       # <-- The faces allow nothing; the status line says why
                end

            size = na_sc__snap(raw)
            size = max.to_f if max && size > max.to_f
            size = 0.0 if size < 0.0
            size
        end
        # ---------------------------------------------------------------

        # FUNCTION | Forget the Scrub
        # ------------------------------------------------------------
        def na_sc__clear
            @na_sc_y0    = nil
            @na_sc_u0    = nil
            @na_sc_span  = nil
            @na_sc_pixel = nil
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnChamferScrub module

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP CHAMFER SCRUB DRAG
# =============================================================================
