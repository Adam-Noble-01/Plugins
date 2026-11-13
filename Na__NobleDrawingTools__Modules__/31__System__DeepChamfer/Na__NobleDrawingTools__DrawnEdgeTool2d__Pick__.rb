# =============================================================================
# NA NOBLE DRAWING TOOLS - EDGE TOOLS 2D | CORNER PICK AND CAMERA SWITCH
# =============================================================================
#
# FILE       : Na__NobleDrawingTools__DrawnEdgeTool2d__Pick__.rb
# NAMESPACE  : Na__NobleDrawingTools
# AUTHOR     : Noble Architecture
# PURPOSE    : Find the edge running into the screen behind a corner, and pick
#              the 2D or 3D edge tool the camera calls for
# CREATED    : 2026
#
# DESCRIPTION:
# - In an elevation the edge you want to round is END-ON to the camera. It
#   draws as a POINT, the corner of the profile you can see, so there is no
#   line to hover, and the 3D pick grabs one of the profile's own lines
#   instead: the end of the moulding rather than its length.
# - So the 2D pick looks for a CORNER. The geometry under the cursor (the deep
#   edge pick, then the deep face pick, so a selected group, the open context
#   and locks all rule exactly as they do in 3D) offers its vertices. The one
#   nearest the cursor, within NA_ET2D_CORNER_PX, that has an edge running
#   into the screen wins, and that edge is the one cut. Two corners stacked on
#   the same pixel go to the one nearer the camera.
# - THE WHOLE RUN COMES WITH IT. An edge split along its length (a line drawn
#   across a face, a joint) is several edges in a row behind one corner, and
#   cutting the first alone would stop the cut part way along. Every edge that
#   carries the arris straight on (Na__ProfileSweep__Continuation, the very
#   test the sweep uses for its through joints) rides along, so the cut runs
#   the full length the corner stands for and meets itself full width.
# - Away from every corner the ordinary edge under the cursor is offered, as in
#   3D: a line in an elevation is an edge too, and an isometric parallel view
#   has no end-on edges at all.
#
# CAMERA SWITCHING IS AUTOMATIC (as Deep Push Pull's):
# - Deep Chamfer, Deep Fillet, Deep Ogee and Deep Ovolo each keep one command,
#   one shortcut and one popup button. Whichever starts a tool asks the camera
#   first, and while one runs an idle mouse move asks again: click a 2D scene
#   tab and the 2D variant takes over on the next move, orbit into perspective
#   and the 3D one comes back. Banked edges ride across (the profile hot swap's
#   own snapshot); a handover never happens mid-drag.
#
# REUSED, NOT COPIED:
# - The camera questions (parallel or not, which way it looks, how far a
#   direction lies across the screen) are Deep Push Pull 2D's, from its pick
#   file. One answer to "is this a 2D view" for every 2D tool.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../04__GeometryHelpers/Na__NobleDrawingTools__DrawnDeepPick__'
require_relative '../04__GeometryHelpers/Na__NobleDrawingTools__DrawnProfileSweep__'
require_relative '../30__System__DeepPushPull/Na__NobleDrawingTools__DrawnPushPull2d__Pick__'
require_relative 'Na__NobleDrawingTools__DrawnChamfer__Geometry__'

module Na__NobleDrawingTools

    # -----------------------------------------------------------------------------
    # REGION | Constants
    # -----------------------------------------------------------------------------

    NA_ET2D_CORNER_PX     = 12.0                                              # <-- The cursor this close to a corner takes the edge behind it
    NA_ET2D_END_ON_FACTOR = 0.1736                                            # <-- sin 10 deg: an edge this near the line of sight runs into the screen (provisional)
    NA_ET2D_STACK_PX      = 1.5                                               # <-- Two corners this close on screen are stacked; the nearer the camera wins
    NA_ET2D_RUN_MAX       = 64                                                # <-- A guard on the walk along a run, not a limit anyone should meet

    # Each profile's 3D tool and its 2D variant. The hot swap, the menu
    # commands and the camera handover all find a tool's profile and its
    # sibling here, so the four profiles stay one tool to the user.
    NA_ET2D_CLASSES = {
        :chamfer => [:DrawnChamferTool, :DrawnChamfer2dTool],
        :fillet  => [:DrawnFilletTool,  :DrawnFillet2dTool],
        :ogee    => [:DrawnOgeeTool,    :DrawnOgee2dTool],
        :ovolo   => [:DrawnOvoloTool,   :DrawnOvolo2dTool]
    }.freeze

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Which Tool the Camera Wants
    # -----------------------------------------------------------------------------

    # FUNCTION | A Class in This Namespace by Name, or nil While It Is Not Loaded
    # ------------------------------------------------------------
    def self.Na__EdgeTool2d__Class(name)
        return nil unless Na__NobleDrawingTools.const_defined?(name, false)

        Na__NobleDrawingTools.const_get(name, false)
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Profile a Running Edge Tool Cuts, 2D or 3D, or nil
    # instance_of?, not is_a?: every 2D variant IS its 3D profile by
    # inheritance, and every profile is a DrawnChamferTool.
    # ------------------------------------------------------------
    def self.Na__EdgeTool2d__ProfileOf(tool)
        return nil unless tool

        NA_ET2D_CLASSES.each do |profile, names|
            names.each do |name|
                klass = Na__NobleDrawingTools.Na__EdgeTool2d__Class(name)
                return profile if klass && tool.instance_of?(klass)
            end
        end

        nil
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Class a Profile Wants Under This Camera
    # The 3D tool on any doubt: a camera that cannot be read is no reason to
    # hand over the specialised variant, and it is the one that always worked.
    # ------------------------------------------------------------
    def self.Na__EdgeTool2d__WantedClass(profile, view)
        names = NA_ET2D_CLASSES[profile]
        return nil unless names

        if view && Na__NobleDrawingTools.Na__PushPull2d__ParallelCamera?(view)
            flat = Na__NobleDrawingTools.Na__EdgeTool2d__Class(names[1])
            return flat if flat
        end

        Na__NobleDrawingTools.Na__EdgeTool2d__Class(names[0])
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Profile Class Swapped for Its Sibling If the Camera Wants It
    # The hot swap names the 3D classes; this keeps a swap in a 2D view in 2D.
    # Anything that is not an edge tool comes back unchanged.
    # ------------------------------------------------------------
    def self.Na__EdgeTool2d__ClassForCamera(klass)
        profile = NA_ET2D_CLASSES.keys.find do |key|
            NA_ET2D_CLASSES[key].any? { |name| Na__NobleDrawingTools.Na__EdgeTool2d__Class(name) == klass }
        end
        return klass unless profile

        model  = Sketchup.active_model
        wanted = Na__NobleDrawingTools.Na__EdgeTool2d__WantedClass(profile, model ? model.active_view : nil)
        wanted || klass
    rescue StandardError
        klass
    end
    # ---------------------------------------------------------------

    # FUNCTION | A New Tool of This Profile for the Current Camera, or nil
    # ------------------------------------------------------------
    def self.Na__EdgeTool2d__NewToolForCamera(model, profile)
        wanted = Na__NobleDrawingTools.Na__EdgeTool2d__WantedClass(profile, model ? model.active_view : nil)
        wanted ? wanted.new : nil
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Swap Tools When the Camera No Longer Matches
    # ------------------------------------------------------------
    # Called first in the edge tools' mouse move. Returns true when a handover
    # was scheduled, and the caller returns at once: the tool is about to be
    # replaced, so there is nothing worth drawing.
    #
    # Only while idle: a handover mid-drag would drop the edge in hand. The
    # caller passes its own state in rather than this reaching into it.
    #
    # Deferred by a timer, as Deep Push Pull's is: select_tool inside a mouse
    # callback tears down the very object whose callback is on the stack. One
    # tick later it is a plain tool change.
    #
    # What is banked rides across in the profile hot swap's own snapshot, so
    # edges picked in 3D can be cut in an elevation and the other way round.
    # Nothing banked and the new tool starts the ordinary way, reading the
    # selection as any start does.
    # ------------------------------------------------------------
    def self.Na__EdgeTool2d__HandoverIfCameraFlipped(tool, view, state)
        return false unless tool && view
        return false unless state == :idle
        return false if @na_et2d_handover_pending

        profile = Na__NobleDrawingTools.Na__EdgeTool2d__ProfileOf(tool)
        return false unless profile

        wanted = Na__NobleDrawingTools.Na__EdgeTool2d__WantedClass(profile, view)
        return false if wanted.nil? || tool.instance_of?(wanted)

        @na_et2d_handover_pending = true
        parallel = Na__NobleDrawingTools.Na__PushPull2d__ParallelCamera?(view)

        Sketchup::set_status_text(
            parallel ? 'Parallel camera — switching to the 2D corner pick' :
                       'Perspective camera — switching back to the 3D edge pick',
            SB_PROMPT
        )
        Na__NobleDrawingTools.Na__Debug__Puts "NA EDGE TOOLS: camera is #{parallel ? 'parallel (2D)' : 'perspective (3D)'} — swapping #{profile}"

        snapshot = tool.respond_to?(:na_hs__snapshot) ? tool.na_hs__snapshot : nil   # <-- Read now, while the tool still holds it

        UI.start_timer(0, false) do
            begin
                model = Sketchup.active_model
                if model
                    fresh = wanted.new
                    fresh.na_hs__receive(snapshot) if snapshot && fresh.respond_to?(:na_hs__receive)
                    model.select_tool(fresh)
                end
            rescue StandardError => swap_error
                Na__NobleDrawingTools.Na__Debug__Puts "NA EDGE TOOLS: camera handover failed — #{swap_error.message}"
            ensure
                @na_et2d_handover_pending = false
            end
        end

        true
    rescue StandardError
        @na_et2d_handover_pending = false
        false
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Screen and Depth Measures
    # -----------------------------------------------------------------------------

    # FUNCTION | Does a World Direction Run Into the Screen?
    # ------------------------------------------------------------
    def self.Na__EdgeTool2d__EndOn?(direction, camera_dir)
        return false unless direction && camera_dir && direction.length > 0

        Na__NobleDrawingTools.Na__PushPull2d__ScreenFactor(direction.normalize, camera_dir) < NA_ET2D_END_ON_FACTOR
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | How Far a World Point Lies Along the Line of Sight
    # Smaller is nearer the camera. Under a parallel camera every pixel looks
    # the same way, so this one number orders anything stacked on a pixel.
    # ------------------------------------------------------------
    def self.Na__EdgeTool2d__Depth(view, point)
        camera = view.camera
        (point - camera.eye).dot(camera.direction.normalize).to_f
    rescue StandardError
        0.0
    end
    # ---------------------------------------------------------------

    # FUNCTION | An Edge's Two Ends in World Space
    # The target's transformation is the pick's own bridge to world: the
    # identity for an edge in the open context, which already reports world.
    # ------------------------------------------------------------
    def self.Na__EdgeTool2d__WorldEnds(edge, xform)
        xform ||= Geom::Transformation.new
        [edge.start.position.transform(xform), edge.end.position.transform(xform)]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Does an Edge Target Run Into the Screen in This View?
    # ------------------------------------------------------------
    def self.Na__EdgeTool2d__TargetEndOn?(view, target)
        return false unless target && target[:edge] && target[:edge].valid?

        camera = Na__NobleDrawingTools.Na__PushPull2d__CameraDirection(view)
        ends   = Na__NobleDrawingTools.Na__EdgeTool2d__WorldEnds(target[:edge], target[:transformation])
        Na__NobleDrawingTools.Na__EdgeTool2d__EndOn?(ends[1] - ends[0], camera)
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | The End of an Edge Target Nearer the Camera, World
    # ------------------------------------------------------------
    def self.Na__EdgeTool2d__NearEnd(view, target)
        ends = Na__NobleDrawingTools.Na__EdgeTool2d__WorldEnds(target[:edge], target[:transformation])

        Na__NobleDrawingTools.Na__EdgeTool2d__Depth(view, ends[0]) <= Na__NobleDrawingTools.Na__EdgeTool2d__Depth(view, ends[1]) ? ends[0] : ends[1]
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Corner to Edge Resolution
    # -----------------------------------------------------------------------------

    # FUNCTION | What the Cursor Offers Under a Parallel Camera
    # ------------------------------------------------------------
    # Returns { :target => edge target or nil, :reason => :corner / :edge,
    # :refusal => why nothing, when nothing }. A corner's target carries
    # :arris (see ArrisFrom); a plain edge's is the deep pick's own.
    # ------------------------------------------------------------
    def self.Na__EdgeTool2d__ResolveAt(view, x, y)
        camera_dir = Na__NobleDrawingTools.Na__PushPull2d__CameraDirection(view)
        return { :target => nil, :refusal => 'The camera could not be read' } unless camera_dir

        edge_target = Na__NobleDrawingTools.Na__DeepPick__EdgeAt(view, x, y)
        face_target = Na__NobleDrawingTools.Na__DeepPick__FaceAt(view, x, y)
        seeds       = []

        if edge_target && edge_target[:edge] && edge_target[:edge].valid?
            seeds << { :vertices => edge_target[:edge].vertices, :path => edge_target[:path], :transformation => edge_target[:transformation] }
        end

        if face_target && face_target[:face] && face_target[:face].valid?
            seeds << { :vertices => face_target[:face].vertices, :path => face_target[:path], :transformation => face_target[:transformation] }
        end

        corner = Na__NobleDrawingTools.Na__EdgeTool2d__CornerAt(view, x, y, seeds, camera_dir)

        if corner
            arris = Na__NobleDrawingTools.Na__EdgeTool2d__ArrisFrom(view, corner, camera_dir)
            return { :target => arris, :reason => :corner } if arris
        end

        return { :target => edge_target, :reason => :edge } if edge_target

        {
            :target  => nil,
            :refusal => seeds.empty? ? 'Hover a corner — the edge running into the screen behind it is the one cut' :
                                       'Nothing runs into the screen here — hover a corner, or a line to cut that edge'
        }
    rescue StandardError => error
        Na__NobleDrawingTools.Na__Debug__Puts "NA EDGE TOOLS 2D: corner pick failed — #{error.message}"
        { :target => nil, :refusal => 'Nothing could be picked here' }
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Corner Nearest the Cursor With an Edge Running Into the Screen
    # ------------------------------------------------------------
    # seeds are vertex lists, each with the path and transformation of the
    # pick it came from: an edge's vertices and its edges all live in that
    # pick's definition, so the same bridge to world serves them all. nil when
    # no corner within reach has anything behind it.
    # ------------------------------------------------------------
    def self.Na__EdgeTool2d__CornerAt(view, x, y, seeds, camera_dir)
        best  = nil
        reach = Na__NobleDrawingTools.Na__EdgeTool2d__CornerReachPx(view)

        seeds.each do |seed|
            xform = seed[:transformation] || Geom::Transformation.new

            seed[:vertices].each do |vertex|
                next unless vertex && vertex.valid?

                world  = vertex.position.transform(xform)
                screen = view.screen_coords(world)
                px     = Math.sqrt(((screen.x.to_f - x.to_f) ** 2) + ((screen.y.to_f - y.to_f) ** 2))
                next if px > reach

                into = vertex.edges.select do |edge|
                    next false unless edge.valid?

                    ends = Na__NobleDrawingTools.Na__EdgeTool2d__WorldEnds(edge, xform)
                    Na__NobleDrawingTools.Na__EdgeTool2d__EndOn?(ends[1] - ends[0], camera_dir)
                end
                next if into.empty?

                candidate = {
                    :world          => world,
                    :px             => px,
                    :depth          => Na__NobleDrawingTools.Na__EdgeTool2d__Depth(view, world),
                    :edges          => into,
                    :path           => seed[:path],
                    :transformation => xform
                }

                best = candidate if Na__NobleDrawingTools.Na__EdgeTool2d__BetterCorner?(candidate, best)
            end
        end

        best
    end
    # ---------------------------------------------------------------

    # FUNCTION | How Near the Cursor a Corner Must Be, in This View's Pixels
    # ------------------------------------------------------------
    # Mouse positions and screen_coords are physical pixels; the reach is
    # meant to the eye, so a high-DPI screen scales it, as the drag scrub
    # scales its span (DrawnChamferScrub).
    # ------------------------------------------------------------
    def self.Na__EdgeTool2d__CornerReachPx(view)
        return NA_ET2D_CORNER_PX unless UI.respond_to?(:scale_factor)

        factor =
            begin
                UI.scale_factor(view)
            rescue ArgumentError, TypeError
                UI.scale_factor                                               # <-- Older SketchUp: the one-argument form is missing
            end

        factor.to_f > 0.0 ? NA_ET2D_CORNER_PX * factor.to_f : NA_ET2D_CORNER_PX
    rescue StandardError
        NA_ET2D_CORNER_PX
    end
    # ---------------------------------------------------------------

    # FUNCTION | Nearer the Cursor Wins; Stacked on One Pixel, Nearer the Camera
    # ------------------------------------------------------------
    def self.Na__EdgeTool2d__BetterCorner?(candidate, best)
        return true if best.nil?
        return candidate[:px] < best[:px] if (candidate[:px] - best[:px]).abs > NA_ET2D_STACK_PX

        candidate[:depth] < best[:depth]
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Edge Behind a Corner, With Its Whole Run, as One Target
    # ------------------------------------------------------------
    # The driver is the run's member nearest the camera, so the grab, the
    # crosshair and the labels sit on the corner the user can see. It carries
    #   :arris => { :corner        the visible corner, world
    #               :far           the run's far end, world
    #               :length_world  the run's length
    #               :members       every edge target in the run, the driver's own included
    #               :face_dirs     the two faces' directions away from the corner, world
    #               :convex        true when the faces fold away from the camera side }
    # which the 2D tools read; the 3D code never looks for it.
    # ------------------------------------------------------------
    def self.Na__EdgeTool2d__ArrisFrom(view, corner, camera_dir)
        path  = corner[:path]
        xform = corner[:transformation]

        first = corner[:edges].min_by do |edge|
            ends = Na__NobleDrawingTools.Na__EdgeTool2d__WorldEnds(edge, xform)
            Na__NobleDrawingTools.Na__PushPull2d__ScreenFactor((ends[1] - ends[0]).normalize, camera_dir)
        end
        return nil unless first

        run     = Na__NobleDrawingTools.Na__EdgeTool2d__Run(first, path, xform)
        members = run.map { |edge| Na__NobleDrawingTools.Na__DeepPick__BuildEdgeTarget(edge, path, xform) }

        driver     = nil
        near_point = nil
        near_depth = nil
        far_point  = nil
        far_depth  = nil

        members.each do |member|
            Na__NobleDrawingTools.Na__EdgeTool2d__WorldEnds(member[:edge], xform).each do |point|
                depth = Na__NobleDrawingTools.Na__EdgeTool2d__Depth(view, point)

                if near_depth.nil? || depth < near_depth
                    near_depth = depth
                    near_point = point
                    driver     = member
                end

                if far_depth.nil? || depth > far_depth
                    far_depth = depth
                    far_point = point
                end
            end
        end
        return nil unless driver

        face_dirs, convex = Na__NobleDrawingTools.Na__EdgeTool2d__CornerFrame(driver)

        driver.merge(
            :arris => {
                :corner       => near_point,
                :far          => far_point,
                :length_world => near_point.distance(far_point).to_f,
                :members      => members,
                :face_dirs    => face_dirs,
                :convex       => convex
            }
        )
    end
    # ---------------------------------------------------------------

    # FUNCTION | Every Edge Carrying the Arris Straight On From One Edge
    # ------------------------------------------------------------
    # Walks out from both ends through Na__ProfileSweep__Continuation, the
    # sweep's own test for an arris running on. A member must border exactly
    # two faces and still make a corner (the chamfer solve answers): past a
    # point where the faces flatten into one plane there is no arris left to
    # cut, and the run stops there rather than carrying a refusal along.
    # ------------------------------------------------------------
    def self.Na__EdgeTool2d__Run(first, path, xform)
        run = [first]

        [first.start, first.end].each do |from|
            current = first
            vertex  = from

            while run.length < NA_ET2D_RUN_MAX
                following = Na__NobleDrawingTools.Na__ProfileSweep__Continuation(current, vertex)
                break unless following && following.valid? && !run.include?(following)
                break unless following.faces.length == 2

                probe_target = Na__NobleDrawingTools.Na__DeepPick__BuildEdgeTarget(following, path, xform)
                break unless Na__NobleDrawingTools.Na__DrawnChamfer__Solve(probe_target, 1.0)

                run << following
                vertex  = following.other_vertex(vertex)
                current = following
            end
        end

        run
    rescue StandardError
        [first]
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Two Faces' World Directions Away From an Edge, and Its Fold
    # ------------------------------------------------------------
    # From the chamfer's own solve at a token setback: a0 and b0 lie on the
    # two faces, square off the edge, so they point the way each face runs.
    # Convex as the sweep decides it (the bisector against face A's normal).
    # [nil, true] for an edge that makes no corner.
    # ------------------------------------------------------------
    def self.Na__EdgeTool2d__CornerFrame(target)
        probe = Na__NobleDrawingTools.Na__DrawnChamfer__Solve(target, 1.0)
        return [nil, true] unless probe

        world = probe[:world]
        dirs  = [world[:a0] - world[:v0], world[:b0] - world[:v0]]
        return [nil, true] unless dirs.all? { |direction| direction.length > 0 }

        face_a = target[:faces] ? target[:faces][0] : nil
        convex = face_a ? probe[:bisector_local].dot(face_a.normal) < 0.0 : true

        [dirs.map(&:normalize), convex]
    rescue StandardError
        [nil, true]
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__NobleDrawingTools module

# =============================================================================
# END OF EDGE TOOLS 2D PICK
# =============================================================================
