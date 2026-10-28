# =============================================================================
# NA INSERT PRIMATIVES - DEEP VERTEX MOVE - VISIBLE ONLY AND THE 2D DEPTH LIMIT
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnVertexMove__Filters__.rb
# NAMESPACE  : Na__InsertPrimatives::DrawnVertexMoveFilters
# AUTHOR     : Noble Architecture
# PURPOSE    : Decide which of the vertices under a box or a click may be taken:
#              only the ones the camera can see, and in a 2D view only the ones
#              within a set depth behind the first visible plane
# CREATED    : 2026
#
# DESCRIPTION:
# - VISIBLE ONLY (the tool's submenu, any view): a vertex is kept only if the
#   line of sight from the camera reaches it before any face. Model#raytest
#   finds the first thing on that line; a hit within NA_VM_VISIBLE_TOL of the
#   vertex is the vertex's own geometry, so it counts as seen. Hidden
#   geometry and hidden tags do not block the view (raytest's WYSIWYG flag).
# - DEPTH LIMIT (the submenu, parallel views only): in an elevation the box
#   sees straight through the building, so boxing a window reveal takes the
#   back wall with it. With a depth set, the box keeps only the vertices
#   within that depth behind the plane the depth is measured from:
#     - the PICKED plane, if one has been picked (Depth Plane in the menu,
#       then click the face), so every box measures from the same wall face;
#     - otherwise the FIRST VISIBLE PLANE of the box itself: the front-most
#       vertex it takes, so boxing a reveal measures from the wall face round
#       the opening.
#   Depth is measured along the line of sight, away from the camera. A picked
#   face that is not square to the view is honoured as the slanted plane it is.
# - Both options are read fresh on every box, so a change in the menu takes
#   at the next pick. The depth options are only listed while the camera is in
#   parallel projection, and the limit only applies there: orbit into
#   perspective and every box sees the whole depth again.
#
# SPEED:
# - One raytest per vertex, cached per camera and per scope walk, so a box
#   dragged out over the same vertices asks each of them once. A box over
#   more than NA_VM_VISIBLE_LIVE_LIMIT vertices checks them on release only.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnDeepPick__'
require_relative '../05__PreviewGraphics/Na__InsertPrimatives__DrawnPreviewGraphics__'
require_relative 'Na__InsertPrimatives__DrawnVertexMove__Scope__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Filter Constants
    # -----------------------------------------------------------------------------

    NA_VM_OPTION_VISIBLE      = 'vertex_visible_only'.freeze
    NA_VM_OPTION_DOT_SIZE     = 'vertex_dot_size'.freeze
    NA_VM_OPTION_DEPTH        = 'vertex_depth_limit'.freeze
    NA_VM_OPTION_PLANE        = 'vertex_depth_plane'.freeze
    NA_VM_OPTIONS_2D_ONLY     = [NA_VM_OPTION_DEPTH, NA_VM_OPTION_PLANE].freeze

    NA_VM_VISIBLE_TOL         = 0.02                                          # <-- Inches (0.5 mm); a hit this near the vertex is its own face
    NA_VM_VISIBLE_LIVE_LIMIT  = 4_000                                         # <-- More vertices than this in a box are checked on release only
    NA_VM_SIGHT_DRAW_LIMIT    = 3_000                                         # <-- Above this every square is drawn, seen or not
    NA_VM_SIGHT_SETTLE_S      = 0.2                                           # <-- The camera has stopped when it has not moved for this long
    NA_VM_DEPTH_TOL           = 0.02                                          # <-- Inches; a vertex ON the plane is inside the depth
    NA_VM_SIGHT_BACKOFF       = 1.0e6                                         # <-- Inches; where a parallel view's sight line starts

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Pure Maths (Module Level)
    # -----------------------------------------------------------------------------

    # FUNCTION | Can the Camera See This World Point?
    # ------------------------------------------------------------
    # The sight line runs from the eye in perspective, and from far in front
    # along the view direction in a parallel view. The point is seen when the
    # first thing that line meets is the point itself, give or take the
    # tolerance. A failed raytest answers "seen": a filter that cannot
    # measure must not swallow the user's box.
    # ------------------------------------------------------------
    def self.Na__VertexMove__Visible?(model, view, point)
        camera = view.camera

        if camera.perspective?
            origin = camera.eye
            sight  = point - origin
            reach  = sight.length.to_f
            return true if reach < NA_VM_VISIBLE_TOL

            sight = sight.normalize
        else
            sight  = camera.direction.normalize
            origin = point.offset(sight.reverse, NA_VM_SIGHT_BACKOFF)
            reach  = NA_VM_SIGHT_BACKOFF
        end

        hit = model.raytest([origin, sight], true)
        return true unless hit

        (hit[0] - origin).dot(sight).to_f >= reach - NA_VM_VISIBLE_TOL - (reach * 1.0e-7)
    rescue StandardError
        true
    end
    # ---------------------------------------------------------------

    # FUNCTION | How Far Behind a Plane a Point Lies, Along the Line of Sight
    # ------------------------------------------------------------
    # From the point, back toward the camera, to the plane: positive when the
    # plane stands between the camera and the point. A plane with no normal,
    # or one seen edge-on, is taken square to the view through its point.
    # ------------------------------------------------------------
    def self.Na__VertexMove__DepthBehind(view, plane, point)
        sight  = view.camera.direction.normalize
        normal = plane[:normal]
        offset = point - plane[:point]

        if normal
            facing = sight.dot(normal).to_f
            return offset.dot(normal).to_f / facing if facing.abs > 1.0e-6
        end

        offset.dot(sight).to_f
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Candidate Nearest the Camera, Along the Line of Sight
    # ------------------------------------------------------------
    def self.Na__VertexMove__FrontMost(view, candidates)
        sight = view.camera.direction.normalize
        eye   = view.camera.eye

        candidates.min_by { |candidate| (candidate[:world] - eye).dot(sight).to_f }
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Depth Limit Set in the Menu, in Inches, or nil for Off
    # ------------------------------------------------------------
    def self.Na__VertexMove__DepthLimit
        value = Na__InsertPrimatives.Na__ToolOptions__Value(NA_VM_OPTION_DEPTH).to_s
        return nil if value.empty? || value == 'off'

        millimetres = value.to_f
        millimetres > 0.0 ? millimetres.mm : nil
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # =============================================================================
    # MODULE | The Filters as the Tool Uses Them
    # =============================================================================

    module DrawnVertexMoveFilters

        NA_VM_PLANE_FILL   = Sketchup::Color.new(131,  10,  10,  28)
        NA_VM_PLANE_BORDER = Sketchup::Color.new(131,  10,  10, 200)

        # -----------------------------------------------------------------------------
        # REGION | State
        # -----------------------------------------------------------------------------

        # FUNCTION | Create Every Instance Variable the Filters Rely On
        # ------------------------------------------------------------
        def na_vm__init_filters
            @na_vm_seen          = nil                                        # <-- { :signature, :serial, :flags => key => true/false }
            @na_vm_sight         = nil                                        # <-- The whole scope's answers, for the squares: { :signature, :serial, :visible }
            @na_vm_sight_due     = false
            @na_vm_sight_wait    = nil                                        # <-- The camera a pending re-scan is waiting to see settle
            @na_vm_plane_armed   = false                                      # <-- The next click picks the depth plane
            @na_vm_depth_plane   = nil                                        # <-- { :point, :normal, :label, :triangles, :loop }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is the Camera in Parallel Projection?
        # ------------------------------------------------------------
        def na_vm__parallel?(view)
            view && !view.camera.perspective?
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is Visible Only Switched On?
        # ------------------------------------------------------------
        # @na_vm_sight_off stands it down for one live count of a very big box.
        # ------------------------------------------------------------
        def na_vm__visible_only?
            return false if @na_vm_sight_off

            Na__InsertPrimatives.Na__ToolOptions__Enabled?(NA_VM_OPTION_VISIBLE)
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Depth Limit in Force in This View, in Inches, or nil
        # ------------------------------------------------------------
        def na_vm__depth_in_force(view)
            return nil unless na_vm__parallel?(view)

            Na__InsertPrimatives.Na__VertexMove__DepthLimit
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Applying the Filters
        # -----------------------------------------------------------------------------

        # FUNCTION | Can the Camera See This Candidate? (Cached per Camera)
        # ------------------------------------------------------------
        def na_vm__seen?(view, candidate)
            signature = na_vm__camera_signature(view)
            cache     = @na_vm_seen

            unless cache && cache[:signature] == signature && cache[:serial] == @na_vm_scope_serial
                cache = @na_vm_seen = { :signature => signature, :serial => @na_vm_scope_serial, :flags => {} }
            end

            flags = cache[:flags]
            key   = candidate[:key]
            return flags[key] if flags.key?(key)

            flags[key] = Na__InsertPrimatives.Na__VertexMove__Visible?(Sketchup.active_model, view, candidate[:world])
        end
        # ---------------------------------------------------------------

        # FUNCTION | Which Vertices in Scope the Camera Sees, for the Squares
        # ------------------------------------------------------------
        # Tool drawing is not hidden by faces, so with Visible Only on the
        # squares are filtered here, or the ones behind a face would still be
        # offered. Returns key => true for every seen vertex, or nil when the
        # scope is too big to raytest on the draw path (every square is then
        # drawn, as with the option off).
        #
        # SketchUp redraws on every frame of an orbit, so the scan is not run
        # on every frame: while the camera moves the last answer stands, and
        # the scope is scanned again once the camera has been still for
        # NA_VM_SIGHT_SETTLE_S. The first answer for a scope is scanned at once.
        # ------------------------------------------------------------
        def na_vm__sight_for(view)
            scope = @na_vm_scope
            return nil unless scope
            return nil if scope[:candidates].length > NA_VM_SIGHT_DRAW_LIMIT

            signature = na_vm__camera_signature(view)
            sight     = @na_vm_sight

            if sight.nil? || sight[:serial] != @na_vm_scope_serial
                na_vm__scan_sight(view, signature)
                return @na_vm_sight[:visible]
            end

            na_vm__schedule_sight(signature) unless sight[:signature] == signature
            @na_vm_sight[:visible]                                            # <-- Re-read: the scan may already have landed
        end
        # ---------------------------------------------------------------

        # FUNCTION | Raytest Every Vertex in Scope From the Camera as It Stands
        # ------------------------------------------------------------
        # The box and the click read the same answers afterwards, so a box
        # drawn once the camera has settled raytests nothing.
        # ------------------------------------------------------------
        def na_vm__scan_sight(view, signature)
            model   = Sketchup.active_model
            visible = {}
            flags   = {}

            @na_vm_scope[:candidates].each do |candidate|
                seen = Na__InsertPrimatives.Na__VertexMove__Visible?(model, view, candidate[:world])
                flags[candidate[:key]]   = seen
                visible[candidate[:key]] = true if seen
            end

            @na_vm_sight = { :signature => signature, :serial => @na_vm_scope_serial, :visible => visible }
            @na_vm_seen  = { :signature => signature, :serial => @na_vm_scope_serial, :flags => flags }
            @na_vm_dots  = nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Scan Again Once the Camera Has Come to Rest
        # ------------------------------------------------------------
        # One timer at a time. When it fires on the same camera it was set on,
        # the camera has been still for the whole wait: scan and redraw.
        # Otherwise wait again on the camera as it now stands.
        # ------------------------------------------------------------
        def na_vm__schedule_sight(signature)
            @na_vm_sight_wait = signature
            return if @na_vm_sight_due

            @na_vm_sight_due = true
            UI.start_timer(NA_VM_SIGHT_SETTLE_S, false) do
                begin
                    @na_vm_sight_due = false
                    model = Sketchup.active_model

                    if model && @na_vm_scope && na_vm__visible_only?
                        view = model.active_view
                        now  = na_vm__camera_signature(view)

                        if now == @na_vm_sight_wait
                            na_vm__scan_sight(view, now)
                            view.invalidate
                        else
                            na_vm__schedule_sight(now)
                        end
                    end
                rescue StandardError => error
                    Na__InsertPrimatives.Na__Debug__Puts "NA VERTEX MOVE: sight scan failed — #{error.message}"
                end
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Of the Candidates Under a Box, the Ones It May Take
        # ------------------------------------------------------------
        # Returns [kept, report]: report counts what each filter left out and
        # names the plane the depth was measured from, so the status line can
        # say why a box took fewer than it covered.
        # ------------------------------------------------------------
        def na_vm__filter_picks(view, candidates)
            report = { :hidden => 0, :deep => 0, :from => nil, :depth => nil }
            kept   = candidates

            if na_vm__visible_only?
                seen            = kept.select { |candidate| na_vm__seen?(view, candidate) }
                report[:hidden] = kept.length - seen.length
                kept            = seen
            end

            depth = na_vm__depth_in_force(view)
            if depth && !kept.empty?
                plane, from = na_vm__depth_reference(view, kept)
                within      = kept.select do |candidate|
                    behind = Na__InsertPrimatives.Na__VertexMove__DepthBehind(view, plane, candidate[:world])
                    behind >= -NA_VM_DEPTH_TOL && behind <= depth + NA_VM_DEPTH_TOL
                end

                report[:deep]  = kept.length - within.length
                report[:from]  = from
                report[:depth] = depth
                kept           = within
            end

            [kept, report]
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Plane a Box's Depth Is Measured From
        # ------------------------------------------------------------
        # The picked plane when there is one, else the box's first visible
        # plane: square to the view through its front-most vertex.
        # ------------------------------------------------------------
        def na_vm__depth_reference(view, candidates)
            plane = @na_vm_depth_plane
            return [plane, plane[:label]] if plane

            front = Na__InsertPrimatives.Na__VertexMove__FrontMost(view, candidates)
            [{ :point => front[:world], :normal => nil }, 'the first visible plane']
        end
        # ---------------------------------------------------------------

        # FUNCTION | Could a Single Click Take This Candidate?
        # ------------------------------------------------------------
        # Clicks honour Visible Only, and in a 2D view with a picked plane the
        # depth too. A click has no box to find a first visible plane in, so
        # without a picked plane it is left to the front-most-wins tie-break.
        # ------------------------------------------------------------
        def na_vm__clickable?(view, candidate)
            return false if na_vm__visible_only? && !na_vm__seen?(view, candidate)

            depth = na_vm__depth_in_force(view)
            return true unless depth && @na_vm_depth_plane

            behind = Na__InsertPrimatives.Na__VertexMove__DepthBehind(view, @na_vm_depth_plane, candidate[:world])
            behind >= -NA_VM_DEPTH_TOL && behind <= depth + NA_VM_DEPTH_TOL
        end
        # ---------------------------------------------------------------

        # FUNCTION | What the Filters Left Out, in Words — Empty When Nothing
        # ------------------------------------------------------------
        def na_vm__filter_note(report)
            parts = []
            parts << "#{report[:hidden]} hidden behind faces left out" if report[:hidden].to_i > 0
            if report[:depth]
                depth = Na__InsertPrimatives.Na__DrawnFormat__Mm(report[:depth])
                parts << "#{report[:deep]} deeper than #{depth} mm behind #{report[:from]} left out" if report[:deep].to_i > 0
            end

            parts.empty? ? '' : " (#{parts.join(', ')})"
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Picking the Depth Plane
        # -----------------------------------------------------------------------------

        # FUNCTION | The Next Click Picks the Plane the Depth Is Measured From
        # ------------------------------------------------------------
        def na_vm__arm_plane_pick
            @na_vm_plane_armed = true
            na_vm__notice('Click the face the depth is measured from — a wall face, say. ESC keeps the first visible plane')
        end
        # ---------------------------------------------------------------

        # FUNCTION | Take the Face Under the Cursor as the Depth Plane
        # ------------------------------------------------------------
        # The same deep pick Push/Pull uses, so it is the face under the cursor
        # at whatever depth, in world space: its plane through the point the
        # pick ray meets it at.
        # ------------------------------------------------------------
        def na_vm__pick_plane(view, x, y)
            @na_vm_plane_armed = false

            target = Na__InsertPrimatives.Na__DeepPick__FaceAt(view, x, y)
            unless target && target[:face] && target[:face].valid?
                UI.beep
                na_vm__notice('No face there — the depth stays measured from the first visible plane')
                return false
            end

            loop  = Na__InsertPrimatives.Na__DeepPick__WorldOuterLoop(target[:face], target[:transformation])
            ray   = view.pickray(x, y)
            point = Geom.intersect_line_plane(ray, [loop.first, target[:world_normal]]) || loop.first

            @na_vm_depth_plane = {
                :point     => point,
                :normal    => target[:world_normal],
                :label     => "the picked plane (#{Na__InsertPrimatives.Na__DeepPick__PathLabel(target)})",
                :loop      => loop,
                :triangles => Na__InsertPrimatives.Na__DeepPick__WorldTriangles(target[:face], target[:transformation])
            }

            depth = Na__InsertPrimatives.Na__VertexMove__DepthLimit
            reach = depth ? "#{Na__InsertPrimatives.Na__DrawnFormat__Mm(depth)} mm behind it" : 'a depth from the menu'
            na_vm__notice("Depth plane picked — boxes take only what lies within #{reach}")
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Shade the Picked Depth Plane While the Limit Is in Force
        # ------------------------------------------------------------
        def na_vm__draw_depth_plane(view)
            plane = @na_vm_depth_plane
            return unless plane && na_vm__depth_in_force(view)

            Na__InsertPrimatives.Na__DrawnPreview__DrawTriangles(view, plane[:triangles], NA_VM_PLANE_FILL)
            Na__InsertPrimatives.Na__DrawnPreview__DrawLoop(view, plane[:loop], NA_VM_PLANE_BORDER, 2)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | The Tool's Submenu
        # -----------------------------------------------------------------------------

        # FUNCTION | This Tool's Options as the Popup Lists Them
        # ------------------------------------------------------------
        # The depth options exist only in a parallel view, where a box sees
        # through the whole building. The plane button names the plane in
        # force and what a click on it will do.
        # ------------------------------------------------------------
        def Na__DrawnMode__ToolOptions
            model    = Sketchup.active_model
            view     = model ? model.active_view : nil
            parallel = na_vm__parallel?(view)

            super.reject { |option| !parallel && NA_VM_OPTIONS_2D_ONLY.include?(option[:id]) }.map do |option|
                option[:id] == NA_VM_OPTION_PLANE ? option.merge(:caption => na_vm__plane_caption) : option
            end
        rescue StandardError
            []
        end
        # ---------------------------------------------------------------

        # FUNCTION | What the Depth Plane Button Says
        # ------------------------------------------------------------
        def na_vm__plane_caption
            return 'Depth Plane: click a face…' if @na_vm_plane_armed
            return 'Depth Plane: Picked (click to clear)' if @na_vm_depth_plane

            'Depth Plane: First Visible (click to pick)'
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Click in the Submenu
        # ------------------------------------------------------------
        # The plane button is an action: it arms the pick, or clears a plane
        # already picked. Visible Only and the depth step as every option does;
        # the cached sightings are thrown away either way.
        # ------------------------------------------------------------
        def Na__DrawnMode__ToggleToolOption(option_id)
            id = option_id.to_s

            if id == NA_VM_OPTION_PLANE
                if @na_vm_depth_plane || @na_vm_plane_armed
                    @na_vm_depth_plane = nil
                    @na_vm_plane_armed = false
                    na_vm__notice('Depth measured from the first visible plane of each box again')
                else
                    na_vm__arm_plane_pick
                end

                na_vm__options_changed
                return { :caption => na_vm__plane_caption, :enabled => !@na_vm_depth_plane.nil? }
            end

            result = super
            na_vm__options_changed
            result
        end
        # ---------------------------------------------------------------

        # FUNCTION | Redraw After an Option Changed
        # ------------------------------------------------------------
        def na_vm__options_changed
            @na_vm_seen          = nil
            @na_vm_sight         = nil
            @na_vm_dots          = nil
            @na_last_status_text = nil
            model = Sketchup.active_model
            model.active_view.invalidate if model
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnVertexMoveFilters module

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP VERTEX MOVE FILTERS MODULE
# =============================================================================
