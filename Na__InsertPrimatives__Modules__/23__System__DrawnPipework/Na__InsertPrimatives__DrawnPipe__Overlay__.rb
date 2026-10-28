# =============================================================================
# NA INSERT PRIMATIVES - DRAWN PIPE OVERLAY
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnPipe__Overlay__.rb
# NAMESPACE  : Na__InsertPrimatives
# CLASS      : DrawnPipeEditOverlay < Sketchup::Overlay (SketchUp 2023+)
# AUTHOR     : Noble Architecture
# PURPOSE    : While a pipe's path is out as a red line, draw the pipe along it,
#              live, whichever tool is being used to edit it; and the Pipework
#              bar over the Select tool when pipes are selected (5.2.11)
# CREATED    : 2026
#
# WHY AN OVERLAY:
# - The line is edited with SketchUp's own Move, Line and Eraser, so the
#   Pipework tool is not running and its draw is never called. An Overlay
#   draws on every frame whatever tool is active, which is what lets the pipe
#   follow a point being dragged by the Move tool.
# - Overlays cannot be clicked. The buttons are on the Pipework tool's bar
#   (DrawnPipe__Bar__); this draws the pipe, the red line, the bends that had
#   to be fitted, and a short panel saying how to finish.
# - Over the Select tool it also draws that bar when pipes are selected or a
#   path is open (DrawnPipe__Watch__), and watches the cursor: on the bar,
#   the Pipework tool is pushed over Select to take the click.
#
# WHAT IT COSTS:
# - Next to nothing when no path is being edited: draw finds no edit on the
#   active path, and the bar is drawn from the selected pipes the watch has
#   already counted. While a path is out, the line's edges are read each
#   frame (a route is a few dozen edges) and the solve is redone only when
#   they or the pipe's spec have changed.
#
# COORDINATES:
# - Overlay drawing is global, like every View#draw. Standing in the red
#   line's group, its vertices already read global; standing one step out, in
#   the pipe, they read local to the line's group, whose transformation then
#   reads global. Nothing else is converted.
#
# LIFE CYCLE:
# - One overlay per model, added when the model is opened or created (the
#   Edit module's app observer) and enabled when a path edit starts, or when
#   pipes are selected with Bar on Selection on. Found again by its id after
#   Reload Plugin Data, which re-opens this class rather than making a new
#   one (so an overlay added before 5.2.11 gains onMouseMove at the reload,
#   though it keeps the name it was added with until the model reopens).
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__InsertPrimatives__DrawnPipe__Preview__'
require_relative 'Na__InsertPrimatives__DrawnPipe__Edit__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Overlay Constants
    # -----------------------------------------------------------------------------

    NA_DRAWN_PIPE_OVERLAY_ID   = 'noble_architecture.insert_primatives.pipework_path'   # <-- Never change: a model finds its overlay again by it
    NA_DRAWN_PIPE_OVERLAY_NAME = 'Pipework'
    NA_DRAWN_PIPE_PANEL_ORIGIN = [18, 52].freeze                              # <-- Under the Pipework bar, so the two never overlap
    NA_DRAWN_PIPE_LINE_COLOR   = Sketchup::Color.new(229, 57, 53)
    NA_DRAWN_PIPE_PANEL_COLOR  = Sketchup::Color.new(150, 30, 30)

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Overlay Class
    # -----------------------------------------------------------------------------

    if defined?(Sketchup::Overlay)

        # CLASS | The Pipe Along Its Red Line, Drawn Over Any Tool
        # ------------------------------------------------------------
        # Thin by design: everything it does is a module function, so Reload
        # Plugin Data changes what an overlay already added to a model does.
        # ------------------------------------------------------------
        class DrawnPipeEditOverlay < Sketchup::Overlay

            attr_accessor :na_pipe_cache

            def initialize
                super(
                    NA_DRAWN_PIPE_OVERLAY_ID,
                    NA_DRAWN_PIPE_OVERLAY_NAME,
                    description: 'The pipe along its red path while Edit Pipework Path is open, and the Pipework bar while pipes are selected'
                )
                @na_pipe_cache = nil
            end

            def draw(view)
                Na__InsertPrimatives.Na__DrawnPipe__OverlayDraw(self, view)
            rescue StandardError
                nil                                                           # <-- Never let the overlay break the view
            end

            def onMouseMove(flags, x, y, view)
                Na__InsertPrimatives.Na__DrawnPipe__AutoBarMouse(flags, x, y, view) if Na__InsertPrimatives.respond_to?(:Na__DrawnPipe__AutoBarMouse)
            rescue StandardError
                nil
            end

            def getExtents
                Na__InsertPrimatives.Na__DrawnPipe__OverlayExtents(self)
            rescue StandardError
                Geom::BoundingBox.new
            end

        end # End DrawnPipeEditOverlay class

    end

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Registration
    # -----------------------------------------------------------------------------

    # FUNCTION | This Model's Pipework Overlay, Added If It Has None
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__OverlayFor(model, create = true)
        return nil unless defined?(Sketchup::Overlay) && model && model.respond_to?(:overlays)

        existing = model.overlays[NA_DRAWN_PIPE_OVERLAY_ID]
        return existing if existing || !create

        overlay = DrawnPipeEditOverlay.new
        model.overlays.add(overlay)
        overlay
    rescue StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "DRAWN PIPE OVERLAY: not added — #{error.message}"
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Switch the Overlay On for a Path Edit
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__OverlayEnable(model)
        overlay = Na__InsertPrimatives.Na__DrawnPipe__OverlayFor(model)
        return false unless overlay

        overlay.enabled = true unless overlay.enabled?
        true
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Drawing
    # -----------------------------------------------------------------------------

    # FUNCTION | Draw the Edit the User Is Standing In, Then the Bar Over Select
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__OverlayDraw(overlay, view)
        open    = Na__InsertPrimatives.Na__DrawnPipe__OpenEdit(view.model)
        preview = open ? Na__InsertPrimatives.Na__DrawnPipe__OverlayPreview(overlay, open) : nil

        if preview
            preview[:items].each do |item|
                next unless item[:solved][:ok]

                Na__InsertPrimatives.Na__DrawnPipe__DrawSolved(view, item[:solved], item[:quads])
                Na__InsertPrimatives.Na__DrawnPipe__LabelCorners(view, item[:solved])
            end

            Na__InsertPrimatives.Na__DrawnPipe__OverlayDrawLine(view, preview[:segments])
            Na__InsertPrimatives.Na__DrawnPipe__OverlayDrawPanel(view, open, preview)
        end

        Na__InsertPrimatives.Na__DrawnPipe__AutoBarDraw(view, open) if Na__InsertPrimatives.respond_to?(:Na__DrawnPipe__AutoBarDraw)
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Solves for the Line as It Stands, Remade Only on a Change
    # ------------------------------------------------------------
    # Returns { :signature, :items, :segments, :spec, :box }; items are the
    # runs solved in WORLD space, the first being the one the pipe will keep.
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__OverlayPreview(overlay, open)
        pipe  = open[:pipe]
        edit  = open[:edit]
        spec  = Na__InsertPrimatives.Na__DrawnPipe__StoredSpec(pipe)
        route = Na__InsertPrimatives.Na__DrawnPipe__StoredRoute(pipe)
        return nil unless spec && route && edit && edit.valid?

        xform    = open[:inside] == :edit ? nil : edit.transformation
        edges    = edit.entities.grep(Sketchup::Edge).select(&:valid?)
        segments = edges.map do |edge|
            a = edge.start.position
            b = edge.end.position
            xform ? [a.transform(xform), b.transform(xform)] : [a, b]
        end

        signature = segments.map { |a, b| "#{Na__InsertPrimatives.Na__DrawnPipe__EditPointKey(a)}>#{Na__InsertPrimatives.Na__DrawnPipe__EditPointKey(b)}" }
                            .join('|') + "|#{spec.values.join(',')}"

        cache = overlay.na_pipe_cache
        return cache if cache && cache[:signature] == signature

        up    = Geom::Vector3d.new(route[:up][0], route[:up][1], route[:up][2]).transform(pipe.transformation)
        runs  = Na__InsertPrimatives.Na__DrawnPipe__Chains(edges).map do |run|
            xform ? run.merge(:points => run[:points].map { |point| point.transform(xform) }) : run
        end
        runs  = runs.sort_by { |run| -Na__InsertPrimatives.Na__DrawnPipe__RunLength(run) }

        items = runs.map do |run|
            solved = Na__InsertPrimatives.Na__DrawnPipe__Solve(run, spec, up)
            shade  = solved[:ok] && Na__InsertPrimatives.Na__DrawnPipe__QuadCount(solved) <= NA_DRAWN_PIPE_PREVIEW_MAX_QUADS
            { :run => run, :solved => solved, :quads => shade ? Na__InsertPrimatives.Na__DrawnPipe__PreviewQuads(solved) : nil }
        end

        box = Geom::BoundingBox.new
        segments.each { |a, b| box.add(a); box.add(b) }
        items.each { |item| (item[:solved][:box] || []).each { |xyz| box.add(Geom::Point3d.new(xyz[0], xyz[1], xyz[2])) } }

        overlay.na_pipe_cache = {
            :signature => signature,
            :items     => items,
            :segments  => segments,
            :spec      => spec,
            :box       => box
        }
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Red Line, Drawn Over Itself So It Reads in Any Style
    # A style colouring edges by tag or all alike would otherwise draw the
    # line black, and it is the one thing the user is meant to grab.
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__OverlayDrawLine(view, segments)
        return if segments.nil? || segments.empty?

        view.line_stipple  = ''
        view.line_width    = 3
        view.drawing_color = NA_DRAWN_PIPE_LINE_COLOR
        view.draw(GL_LINES, segments.flatten)
        view.line_width    = 1
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Panel Under the Bar: What Is Being Edited, and How to Finish
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__OverlayDrawPanel(view, open, preview)
        items = preview[:items]
        bar   = Na__InsertPrimatives.respond_to?(:Na__DrawnPipe__AutoBarOn?) && Na__InsertPrimatives.Na__DrawnPipe__AutoBarOn?
        lines = [
            "PIPEWORK PATH — #{open[:pipe].name} — #{Na__InsertPrimatives.Na__DrawnPipe__SpecLabel(preview[:spec])}",
            'Edit the red line with Move, Line, Eraser — any tool. Click outside the pipe to rebuild it.',
            bar ? 'With Select, the bar above: Finish, Discard, Move, Line, and the spec to click and type. Or right-click.' :
                  'Right-click: Finish / Discard / Pipework Options (the bar: diameter, bend, sides, bore).'
        ]

        if items.empty?
            lines << 'No line left: the pipe will keep the route it had.'
        else
            first = items.first[:solved]
            lines << "Cannot pipe this: #{first[:message]}" unless first[:ok]
            lines << first[:warnings].first if first[:ok] && !first[:warnings].empty?
            lines << "#{items.length - 1} more run#{items.length == 2 ? '' : 's'}: each becomes a pipe of its own." if items.length > 1
        end

        x, y = NA_DRAWN_PIPE_PANEL_ORIGIN
        Na__InsertPrimatives.Na__DrawnPreview__DrawScreenText(view, x, y, lines, NA_DRAWN_PIPE_PANEL_COLOR)
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Box the Overlay Draws In, So Nothing Is Clipped
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__OverlayExtents(overlay)
        cache = overlay.na_pipe_cache
        model = Sketchup.active_model
        return Geom::BoundingBox.new unless cache && model && Na__InsertPrimatives.Na__DrawnPipe__OpenEdit(model)

        cache[:box]
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DRAWN PIPE OVERLAY
# =============================================================================
