# =============================================================================
# NA INSERT PRIMATIVES - DEEP PROJECT TOOL
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnProjectTool__.rb
# NAMESPACE  : Na__InsertPrimatives
# CLASS      : DrawnProjectTool
# AUTHOR     : Noble Architecture
# PURPOSE    : Carry any face, at any nesting depth, on until it reaches a
#              target: the plane of another face, a point, or an object
# CREATED    : 2026
#
# DESCRIPTION:
# - Click a face — loose, or as deep inside groups and components as it
#   lives — then click what it should reach. The result is previewed before
#   the second click in the push tool's own colours: orange where the face
#   grows, red through the model where it cuts back.
# - Two clicks and no distance: the target decides how far. Wall tops run up
#   to a roof pitch, a beam end on to a raking wall, a slab edge out to a
#   boundary, each corner travelling on its own so the end face lands IN the
#   target, however the target is tilted.
# - A target that passes THROUGH the face cuts and extends (5.2.2): the
#   corners in front run out to it, the ones behind run back, and the face
#   lands flat on it.
#
# THE STAGES:
#   :idle            hover a face; click it, or press on it and drag
#   :picking_target  hover what it should reach; click (or release) to place
# Faces selected before the tool starts skip the first stage: they are all
# carried to the one target together.
#
# EVERY KEY THE PUSH TOOL TAUGHT, MEANING THE SAME THING:
#   SHIFT        along the NEIGHBOURING face's slope instead of the normal
#   SHIFT+ALT    FOLLOW: every corner along its own edge
#   ARROWS       along red (Right), green (Left) or blue (Up); again releases
#   TAB          QUADS: keep the start loop as edges; into the solid, a loop cut
#   CTRL         snap: here the target becomes SketchUp's inferred POINT
#   CTRL+SHIFT   that point's height rounded onto the grid
#   BKSP / ESC   release the newest lock / cancel
# And three of its own:
#   DOWN         parallel to the edge under the cursor, as Move's magenta
#                lock; again, or over nothing, flips the direction
#   click edge   the same by mouse, in the target stage
#   SHIFT+TAB    OBJECT mode: stop where the face first touches the object
#
# THE MEASUREMENTS BOX IS AN OFFSET:
# - There is no distance to type, so the box takes a clearance: 25 stops the
#   face 25 short of the target, -25 runs it 25 past. It stays set until it
#   is changed or BKSP releases it. After placing, typing again re-makes the
#   projection at the new offset and the ghost replays the change, exactly
#   as a retyped push does.
# - A double-click on a face carries it to the LAST target, so a run of wall
#   tops goes up to one roof plane at one double-click each.
#
# HOW IT IS BUILT (the commit module has the detail):
# - Where it can, the face is simply MOVED: when every face round it already
#   contains the travel, its corners slide along them and nothing new is
#   made. Otherwise it is pushed with pushpull and every corner then placed
#   exactly on the target. Either way it happens inside the face's own
#   editing context, the push tool's rule for a picture that is never stale.
#
# @delegate: Na__InsertPrimatives__DrawnProject__Geometry__.rb  (the maths)
# @delegate: Na__InsertPrimatives__DrawnProject__Target__.rb    (targets, directions, keys)
# @delegate: Na__InsertPrimatives__DrawnProject__Commit__.rb    (the build)
# @delegate: Na__InsertPrimatives__DrawnProject__Revise__.rb    (retype, repeat, ghost)
# @delegate: Na__InsertPrimatives__DrawnProject__Preview__.rb   (the picture)
#
# =============================================================================

require 'sketchup.rb'
require_relative '../06__Tools__DrawnShared/Na__InsertPrimatives__DrawnToolShared__'
require_relative '../06__Tools__DrawnShared/Na__InsertPrimatives__DrawnRevise__'
require_relative '../06__Tools__DrawnShared/Na__InsertPrimatives__DrawnLargeSelection__'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnDeepPick__'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnSlopePush__'
require_relative '../30__System__DeepPushPull/Na__InsertPrimatives__DrawnPushPull__Follow__'
require_relative 'Na__InsertPrimatives__DrawnProject__Geometry__'
require_relative 'Na__InsertPrimatives__DrawnProject__Target__'
require_relative 'Na__InsertPrimatives__DrawnProject__Commit__'
require_relative 'Na__InsertPrimatives__DrawnProject__Revise__'
require_relative 'Na__InsertPrimatives__DrawnProject__Preview__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Deep Project Tool Class
    # -----------------------------------------------------------------------------

    # CLASS | Carry Any Face On to a Target at Any Nesting Depth
    # ------------------------------------------------------------
    class DrawnProjectTool

        include Na__InsertPrimatives::DrawnToolShared
        include Na__InsertPrimatives::DrawnReviseShared                       # <-- After DrawnToolShared, so its life-cycle wrappers sit over the mixin's
        include Na__InsertPrimatives::DrawnProjectTarget                      # <-- Keys and axis locks sit in front of the shared handlers
        include Na__InsertPrimatives::DrawnProjectCommit
        include Na__InsertPrimatives::DrawnProjectRevise                      # <-- The projection half of the revise contract
        include Na__InsertPrimatives::DrawnProjectPreview

        NA_PJ_HOVER_FILL    = Sketchup::Color.new(  0, 140, 255,  80)         # <-- The push tool's palette, so nothing has to be learnt
        NA_PJ_HOVER_BORDER  = Sketchup::Color.new(  0, 110, 235, 235)
        NA_PJ_RESULT_FILL   = Sketchup::Color.new(255, 150,  30,  70)
        NA_PJ_RESULT_BORDER = Sketchup::Color.new(226, 118,   0, 235)
        NA_PJ_QUAD_BORDER   = Sketchup::Color.new(200,  60, 200, 255)
        NA_PJ_EDGE_COLOR    = Sketchup::Color.new(225,   0, 225, 255)         # <-- SketchUp's own magenta for "parallel to this edge"

        # INITIALIZE | Tool Constructor
        # ------------------------------------------------------------
        def initialize
            na_drawn__init_shared_state
            na_revise__init_state
            na_pj__init_target_state
            na_pj__clear_sources
        end
        # ---------------------------------------------------------------

        # FUNCTION | Forget the Faces Being Projected
        # ------------------------------------------------------------
        def na_pj__clear_sources
            @na_pj_sources     = []                                           # <-- The faces taken, in world space
            @na_pj_directed    = []                                           # <-- The same, fitted with this frame's direction
            @na_pj_solutions   = []                                           # <-- Where each one lands on this frame's target
            @na_pj_hover       = nil                                          # <-- The face under the cursor while idle
            @na_pj_preselected = false
        end
        # ---------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Identity
        # -----------------------------------------------------------------------------

        # FUNCTION | Status Bar Title
        # ------------------------------------------------------------
        def na_drawn__tool_title
            'Deep Project'
        end
        # ---------------------------------------------------------------

        # FUNCTION | Popup Menu Highlight Key
        # ------------------------------------------------------------
        def na_drawn__mode_key
            :drawn_project
        end
        # ---------------------------------------------------------------

        # FUNCTION | Console Banner Hint Lines
        # ------------------------------------------------------------
        def na_drawn__activation_hints
            [
                'Click a face — at any nesting depth — then click what it should reach',
                'A face as the target: every corner lands on its plane, so a wall top takes a roof pitch',
                'CTRL: a point instead — the face stops level with it (CTRL+SHIFT rounds that height onto the grid)',
                'SHIFT+TAB: OBJECT mode — the face stops where it first touches the group or component',
                'Click an edge, or press DOWN over one: the face travels parallel to it. DOWN again flips it',
                'ARROWS: travel along red (Right), green (Left) or blue (Up); the same arrow releases',
                'Hold SHIFT to travel along the NEIGHBOURING face — a roof runs on down its own rake',
                'Hold SHIFT+ALT to FOLLOW — every corner runs along its own edge',
                'TAB toggles QUADS — the start loop stays as edges; into the solid it cuts a loop at the target',
                'VCB: an offset — 25 stops 25 short of the target, -25 runs 25 past, BKSP releases it',
                'After placing, type again to re-make it at a new offset — the preview replays the change',
                'Double-click a face to carry it to the last target',
                'Faces selected before starting are all carried to one target'
            ]
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Life Cycle and State Containment
        # -----------------------------------------------------------------------------

        # ACTIVATE | Start Clean, Then Take On a Preselection If There Is One
        # ------------------------------------------------------------
        def activate
            super
            na_pj__forget_objects
            na_pj__read_preselection
            @na_last_status_text = nil
            na_drawn__update_status_text
            na_drawn__refresh_vcb
        end
        # ---------------------------------------------------------------

        # ON CANCEL | An Undo Changes the Model Under Every Cached Scan
        # ------------------------------------------------------------
        def onCancel(reason, view)
            if reason == 2
                na_pj__forget_objects
                @na_pj_target = nil
            end

            super
        end
        # ---------------------------------------------------------------

        # FUNCTION | This Tool Has Exactly Two States
        # ------------------------------------------------------------
        # The shared mixin drives a three-stage machine; this tool has no
        # rectangle stage and no depth stage, so any state it cannot service is
        # snapped straight back to idle rather than trusted — the same guard
        # the push tool keeps, for the same reason.
        # ------------------------------------------------------------
        def na_drawn__ensure_known_state
            return true if @na_state == :idle || @na_state == :picking_target

            na_drawn__reset_pick_state
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Return to Hovering
        # ------------------------------------------------------------
        def na_drawn__reset_pick_state
            super
            na_pj__clear_sources
            @na_pj_target     = nil
            @na_pj_edge_hover = nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Take On the Faces Selected Before the Tool Started
        # ------------------------------------------------------------
        # More than ten asks first, as the push tool does: CTRL+A and a
        # shortcut must not carry a whole model anywhere. Yes goes straight to
        # the target stage with all of them; No leaves the selection alone and
        # faces are taken one at a time; Cancel leaves the tool.
        # ------------------------------------------------------------
        def na_pj__read_preselection
            model = Sketchup.active_model
            return false unless model

            faces = model.selection.grep(Sketchup::Face).select(&:valid?)
            return false if faces.empty?

            answer = Na__InsertPrimatives.Na__LargeSelection__Ask(:faces, faces.length, na_drawn__tool_title, 'projected', 'Project')
            if answer == :cancel
                na_drawn__schedule_exit_tool
                return false
            end

            if answer != :yes
                count = Na__InsertPrimatives.Na__LargeSelection__Count(faces.length)
                na_revise__notice("The #{count} selected faces are left alone — click a face to project it")
                return false
            end

            path    = Na__InsertPrimatives.Na__DeepPick__ContextPath
            sources = faces.map do |face|
                na_pj__build_source(Na__InsertPrimatives.Na__DeepPick__BuildTarget(face, path, nil))
            end.compact
            return false if sources.empty?

            @na_pj_sources     = sources
            @na_pj_preselected = true
            @na_state          = :picking_target
            @na_point_a        = sources.first[:centroid]
            na_pj__resolve
            true
        rescue StandardError => error
            Na__InsertPrimatives.Na__Debug__Puts "NA PROJECT: the selection could not be taken on — #{error.message}"
            false
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Sources — Faces in World Space
        # -----------------------------------------------------------------------------

        # FUNCTION | Everything the Geometry Needs About One Face, in World Space
        # ------------------------------------------------------------
        # Built once per face and kept: the hover asks for it on every mouse
        # move, and triangulating at that rate is what once made the push tool
        # lag a beat behind the cursor.
        #
        # The normal is taken from the world outline (Newell's method), turned
        # to agree with the pick's own: a transformed normal is only square to
        # its face under a uniform scale, and a corner solved against a normal
        # that is not would land a little off the target in a stretched group.
        # ------------------------------------------------------------
        def na_pj__build_source(target)
            face = target && target[:face]
            return nil unless face && face.valid?

            xform = target[:transformation] || Geom::Transformation.new
            outer = face.outer_loop
            loops = [outer] + face.loops.reject { |loop| loop == outer }
            world = loops.map { |loop| loop.vertices.map { |vertex| vertex.position.transform(xform) } }
            return nil if world.empty? || world[0].length < 3

            normal   = na_pj__loop_normal(world[0], target[:world_normal])
            interior = Na__InsertPrimatives.Na__SlopePush__InteriorPoint(face)

            {
                :target      => target,
                :fingerprint => [face.entityID, face.vertices.length, face.vertices.first.position.to_a, xform.to_a],
                :loops       => world,
                :triangles   => Na__InsertPrimatives.Na__DeepPick__WorldTriangles(face, xform),
                :normal      => normal,
                :origin      => world[0][0],
                :centroid    => interior ? interior.transform(xform) : world[0][0],
                :area        => Na__InsertPrimatives.Na__DeepPick__WorldAreaM2(face, xform),
                :solid       => face.edges.all? { |edge| edge.faces.length >= 2 }
            }
        rescue StandardError => error
            Na__InsertPrimatives.Na__Debug__Puts "NA PROJECT: that face could not be read — #{error.message}"
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | A World Outline's Unit Normal, Turned to Agree With a Hint
        # ------------------------------------------------------------
        def na_pj__loop_normal(points, hint)
            x = 0.0
            y = 0.0
            z = 0.0

            points.each_with_index do |point, index|
                following = points[(index + 1) % points.length]
                x += (point.y.to_f - following.y.to_f) * (point.z.to_f + following.z.to_f)
                y += (point.z.to_f - following.z.to_f) * (point.x.to_f + following.x.to_f)
                z += (point.x.to_f - following.x.to_f) * (point.y.to_f + following.y.to_f)
            end

            normal = Geom::Vector3d.new(x, y, z)
            return hint unless normal.length.to_f > 0.0

            normal = normal.normalize
            hint && normal.dot(hint) < 0.0 ? normal.reverse : normal
        end
        # ---------------------------------------------------------------

        # FUNCTION | Fit a Source With the Motion Its Corners Travel Along
        # ------------------------------------------------------------
        # Returns a copy of the source carrying :mode, :motions (one per corner,
        # parallel to :loops), :reaches (FOLLOW only), :uniform, :words for the
        # card, :key for the contact cache, and :problem when this face cannot
        # travel this way at all. SHIFT on a face with no slope, and SHIFT+ALT
        # on one with no edges to follow, fall back to the normal and say why,
        # exactly as the push tool's do.
        # ------------------------------------------------------------
        def na_pj__direct(source)
            mode      = na_pj__mode
            direction = nil
            note      = nil
            words     = nil

            case mode
            when :edge
                direction = @na_pj_edge_lock[:direction]
                words     = "parallel to the edge in #{@na_pj_edge_lock[:name]}"
            when :axis
                direction = Na__InsertPrimatives.Na__DrawnGrid__AxisVector(@na_axis_lock)
                words     = "along #{NA_DRAWN_AXIS_LABELS[@na_axis_lock]}"
            when :follow
                rails = (source[:rails] ||= Na__InsertPrimatives.Na__FollowPush__WorldRails(source[:target]))
                return na_pj__direct_follow(source, rails) if rails[:ok]

                note = "FOLLOW off — #{rails[:reason]}"
                mode = :normal
            when :slope
                slope = na_pj__slope_of(source)
                if slope
                    direction = slope[:direction]
                    words     = "SHIFT slope — #{Na__InsertPrimatives.Na__SlopePush__Label(slope)}"
                else
                    note = 'SHIFT: no sloped neighbour here'
                    mode = :normal
                end
            end

            direction ||= source[:normal]
            words     ||= 'along the face normal'
            motion      = Na__InsertPrimatives.Na__Project__Motion(direction, source[:normal])

            source.merge(
                :mode           => mode,
                :uniform        => true,
                :motions        => source[:loops].map { |points| Array.new(points.length, motion) },
                :reaches        => nil,
                :average_motion => motion,
                :words          => words,
                :note           => note,
                :problem        => motion ? nil : na_pj__edge_on_reason(mode),
                :key            => source[:fingerprint] + [mode, motion ? motion.to_a.map { |value| value.round(9) } : nil]
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | Fit a Source With Every Corner's Own Rail (SHIFT+ALT)
        # ------------------------------------------------------------
        def na_pj__direct_follow(source, rails)
            lookup = {}
            rails[:rails].each { |rail| lookup[Na__InsertPrimatives.Na__Project__PointKey(rail[:point])] = rail }

            motions = []
            reaches = []
            problem = nil

            source[:loops].each do |points|
                row_motion = []
                row_reach  = []

                points.each do |point|
                    rail   = lookup[Na__InsertPrimatives.Na__Project__PointKey(point)] ||
                             rails[:rails].find { |candidate| candidate[:point].distance(point) < NA_FOLLOW_TOL }
                    motion = rail ? Na__InsertPrimatives.Na__Project__Motion(rail[:dir], source[:normal], 0.0) : nil
                    problem ||= 'a corner of this face has no edge to follow' unless motion

                    row_motion << (motion || source[:normal])
                    row_reach  << (rail ? rail[:inward] : 0.0)
                end

                motions << row_motion
                reaches << row_reach
            end

            all     = motions.flatten
            average = Geom::Vector3d.new(
                all.inject(0.0) { |sum, motion| sum + motion.x.to_f } / all.length,
                all.inject(0.0) { |sum, motion| sum + motion.y.to_f } / all.length,
                all.inject(0.0) { |sum, motion| sum + motion.z.to_f } / all.length
            )

            source.merge(
                :mode           => :follow,
                :uniform        => false,
                :motions        => motions,
                :reaches        => reaches,
                :average_motion => average,
                :words          => 'SHIFT+ALT FOLLOW — each corner along its own edge',
                :note           => nil,
                :problem        => problem,
                :key            => source[:fingerprint] + [:follow]
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Neighbour's Slope SHIFT Would Follow, Read Once
        # ------------------------------------------------------------
        def na_pj__slope_of(source)
            return source[:slope] if source.key?(:slope)

            source[:slope] = Na__InsertPrimatives.Na__SlopePush__Best(source[:target])
        end
        # ---------------------------------------------------------------

        # FUNCTION | Why a Direction Cannot Carry This Face
        # ------------------------------------------------------------
        def na_pj__edge_on_reason(mode)
            case mode
            when :edge  then 'the locked edge runs along this face — it cannot carry it anywhere'
            when :axis  then "this face is edge-on to #{NA_DRAWN_AXIS_LABELS[@na_axis_lock]} — it cannot travel along it"
            when :slope then 'its neighbour runs along the face'
            else             'the direction runs along the face'
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Re-Solve Every Source Against What the Cursor Offers
        # ------------------------------------------------------------
        # Cheap on purpose: a plane target is a handful of dot products per
        # corner, and an object's contact is solved once per object and
        # direction and kept on the target.
        # ------------------------------------------------------------
        def na_pj__resolve
            settings         = na_pj__settings
            @na_pj_directed  = (@na_pj_sources || []).map { |source| na_pj__direct(source) }
            @na_pj_solutions = @na_pj_directed.each_with_index.map do |source, index|
                next nil unless @na_pj_target

                solution = na_pj__solve(source, settings)
                next solution unless na_pj__cuts_back?(source, solution)

                # Cutting back into a solid: solved again knowing how far each
                # corner can run back along the solid's own edge, so a target
                # past the far end is refused in the preview, not by the click.
                reaches = na_pj__inward_reaches(source)
                next solution unless reaches

                @na_pj_directed[index] = source.merge(:reaches => reaches)
                na_pj__solve(@na_pj_directed[index], settings)
            end

            found = @na_pj_solutions.compact.find { |solution| solution[:ok] && solution[:sense] }
            @na_pj_found_sense = found[:sense] if found
            @na_pj_solutions
        end
        # ---------------------------------------------------------------

        # FUNCTION | Solve One Source, Then Ask Whether a Cut and Extend Can Be Built
        # ------------------------------------------------------------
        # A target through the face is cut and extended (5.2.2). FOLLOW always
        # can: every corner keeps to its own edge. One direction can only when
        # the faces round this one hold it, so they can lengthen on one side
        # and shorten on the other; otherwise it is refused here, with the way
        # out, rather than by the click.
        # ------------------------------------------------------------
        def na_pj__solve(source, settings)
            solution = Na__InsertPrimatives.Na__Project__Solve(source, @na_pj_target, settings)
            return solution unless solution[:ok] && solution[:way] == :mixed
            return solution unless source[:uniform]
            return solution if na_pj__stretchable?(source)

            Na__InsertPrimatives.Na__Project__Refused(NA_PROJECT_MIXED_REFUSAL)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Does Any Corner Run Back Into a Solid Along One Direction?
        # ------------------------------------------------------------
        def na_pj__cuts_back?(source, solution)
            solution && solution[:ok] && [:in, :mixed].include?(solution[:way]) &&
                source[:uniform] && source[:solid] && source[:average_motion]
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Travel in the Face's Own Space, as a Unit Direction
        # Two points carried across and subtracted, as the commit does it.
        # ------------------------------------------------------------
        def na_pj__local_direction(source)
            target  = source[:target]
            face    = target[:face]
            xform   = target[:transformation] || Geom::Transformation.new
            origin  = face.vertices.first.position
            ahead   = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(origin.transform(xform), source[:average_motion], 1.0)
            local   = ahead.transform(xform.inverse) - origin

            local.length.to_f > 0.0 ? local.normalize : nil
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Can the Corners Slide Along the Faces Round This One?
        # The commit's own test (the slope push's), asked once per face and
        # direction and kept.
        # ------------------------------------------------------------
        def na_pj__stretchable?(source)
            cache = (@na_pj_stretch_cache ||= {})
            key   = source[:key]
            return cache[key] if cache.key?(key)

            local = na_pj__local_direction(source)
            cache.clear if cache.length > 64
            cache[key] = local ? Na__InsertPrimatives.Na__SlopePush__CanStretch?(source[:target][:face], local) : false
        end
        # ---------------------------------------------------------------

        # FUNCTION | How Far Each Corner Can Run Back Along the Solid, in World Inches
        # ------------------------------------------------------------
        # The push tool's FOLLOW reach, asked along the travel instead of a
        # rail: the edges running straight back from each corner, walked
        # through any collinear pieces. A corner with no such edge answers nil
        # — nothing here says how far it may go, so nothing limits it — which
        # is the pocket in the middle of a face, cut down through its floor.
        # Read in the face's own space and measured in world, so a scaled
        # group reports the distance the user sees. Kept per face and motion.
        # ------------------------------------------------------------
        def na_pj__inward_reaches(source)
            cache = (@na_pj_reach_cache ||= {})
            key   = source[:key]
            return cache[key] if cache.key?(key)

            cache.clear if cache.length > 64
            cache[key] = na_pj__measure_reaches(source)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Walk Each Corner's Edge Back Through the Solid
        # ------------------------------------------------------------
        def na_pj__measure_reaches(source)
            target = source[:target]
            face   = target[:face]
            xform  = target[:transformation] || Geom::Transformation.new
            local  = na_pj__local_direction(source)
            return nil unless local

            outer = face.outer_loop
            loops = [outer] + face.loops.reject { |loop| loop == outer }

            loops.map do |loop|
                loop.vertices.map do |vertex|
                    own   = vertex.edges.select { |edge| edge.faces.include?(face) }
                    reach = Na__InsertPrimatives.Na__FollowPush__InwardReach(vertex, own, local)
                    next nil unless reach > 0.0

                    start = vertex.position
                    back  = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(start, local, -reach)
                    (back.transform(xform) - start.transform(xform)).length.to_f
                end
            end
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | What Every Solve Is Given
        # ------------------------------------------------------------
        def na_pj__settings
            { :offset => @na_pj_offset.to_f, :sense => @na_pj_sense, :quads => na_pj__quad_mode? }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is QUAD Mode On?
        # A rebuild answers with the setting the projection was made under, so
        # retyping an offset never adds or drops a quad line because TAB was
        # pressed in between.
        # ------------------------------------------------------------
        def na_pj__quad_mode?
            return @na_revise_replaying[:quads] if @na_revise_replaying

            Na__InsertPrimatives.Na__DrawnSettings__QuadPushEnabled?
        end
        # ---------------------------------------------------------------

        # FUNCTION | Why the Projection Under the Cursor Cannot Be Placed, or nil
        # ------------------------------------------------------------
        def na_pj__refusal
            return 'there is no face to project' if @na_pj_sources.nil? || @na_pj_sources.empty?
            return 'there is nothing under the cursor to project to' unless @na_pj_target
            return @na_pj_target[:refusal] if @na_pj_target[:refusal]

            solutions = @na_pj_solutions || []
            failed    = solutions.select { |solution| solution.nil? || !solution[:ok] }
            return nil if failed.empty? && !solutions.empty?

            reason = failed.first ? failed.first[:reason] : 'it could not be solved'
            solutions.length > 1 ? "#{failed.length} of the #{solutions.length} faces: #{reason}" : reason
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Mouse
        # -----------------------------------------------------------------------------

        # ON MOUSE MOVE | Hover a Face While Idle, the Target After That
        # ------------------------------------------------------------
        def onMouseMove(flags, x, y, view)
            na_drawn__sync_modifier(flags)
            na_drawn__ensure_known_state
            na_drawn__update_cursor(view, x, y)
            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate
        end
        # ---------------------------------------------------------------

        # FUNCTION | Re-Read Whatever the Cursor Is Over
        # ------------------------------------------------------------
        # The shared key handlers call this when CTRL or SHIFT changes with the
        # mouse still, which is what makes the preview answer the key the
        # moment it is pressed.
        # ------------------------------------------------------------
        def na_drawn__update_cursor(view, x, y)
            @na_last_mouse_x = x
            @na_last_mouse_y = y
            return false unless view

            if @na_state == :picking_target
                na_pj__track_target(view, x, y)
                na_pj__resolve
            else
                na_pj__hover_source(view, x, y)
            end

            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Track the Face Under the Cursor While Idle
        # ------------------------------------------------------------
        def na_pj__hover_source(view, x, y)
            picked = Na__InsertPrimatives.Na__DeepPick__FaceAt(view, x, y)

            if picked.nil? || picked[:locked]
                @na_pj_hover = nil
                return false
            end

            @na_pj_hover = na_pj__adopt(picked)
            !@na_pj_hover.nil?
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Cached Source for a Pick, Rebuilt Only When the Face Changed
        # ------------------------------------------------------------
        def na_pj__adopt(picked)
            face        = picked[:face]
            fingerprint = [face.entityID, face.vertices.length, face.vertices.first.position.to_a, picked[:transformation].to_a]

            if @na_pj_hover && @na_pj_hover[:fingerprint] == fingerprint
                @na_pj_hover[:target] = picked                                # <-- The fresh path, the cached geometry
                return @na_pj_hover
            end

            na_pj__build_source(picked)
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # ON LEFT BUTTON DOWN | Take a Face, or Place on the Target
        # ------------------------------------------------------------
        def onLButtonDown(flags, x, y, view)
            @na_vcb_typing_active = false
            na_drawn__sync_modifier(flags)
            na_drawn__ensure_known_state
            @na_last_mouse_x = x
            @na_last_mouse_y = y

            case @na_state
            when :idle
                # Taking a face is the "something else" that closes the retype
                # on the last projection, as it does natively. A click that
                # takes nothing leaves it open.
                taken = na_pj__grab(view, x, y)
                na_revise__forget if taken
            when :picking_target
                @na_drag_press_active = false
                na_pj__click_target(view, x, y)
            end

            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate
        end
        # ---------------------------------------------------------------

        # FUNCTION | Take Hold of the Face Under the Cursor
        # ------------------------------------------------------------
        def na_pj__grab(view, x, y)
            picked = Na__InsertPrimatives.Na__DeepPick__FaceAt(view, x, y)

            unless picked
                UI.beep
                Sketchup::set_status_text('No face under the cursor', SB_PROMPT)
                return false
            end

            # Backstop only: the picker skips locked geometry itself.
            if picked[:locked]
                UI.beep
                Sketchup::set_status_text('That face is inside a locked group or component', SB_PROMPT)
                return false
            end

            source = na_pj__adopt(picked)
            return false unless source

            @na_ip.pick(view, x, y)
            @na_point_a = @na_ip.position || source[:centroid]
            @na_ip_origin.copy!(@na_ip)

            @na_pj_sources     = [source]
            @na_pj_preselected = false
            @na_pj_target      = nil
            @na_state          = :picking_target

            # Press-drag-release works as well as click-move-click: press on
            # the face, let go over the target.
            @na_drag_press_active = true
            @na_press_x           = x
            @na_press_y           = y

            na_pj__warn_if_shared(picked)
            na_pj__track_target(view, x, y)
            na_pj__resolve
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Say So When the Projection Will Change Every Copy
        # ------------------------------------------------------------
        def na_pj__warn_if_shared(picked)
            count = picked[:shared_count].to_i
            return false if count <= 1

            Sketchup::set_status_text("Heads up: this definition has #{count} instances — projecting changes all of them", SB_PROMPT)
            @na_last_status_text = nil
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Click in the Target Stage: an Edge Sets the Direction, Anything Else Places
        # ------------------------------------------------------------
        def na_pj__click_target(view, x, y)
            na_drawn__update_cursor(view, x, y)

            return na_pj__lock_edge(@na_pj_edge_hover, view) if @na_pj_edge_hover

            unless @na_pj_target
                UI.beep
                Sketchup::set_status_text('Nothing to project to here — click a face, a point (CTRL) or an object (SHIFT+TAB)', SB_PROMPT)
                @na_last_status_text = nil
                return false
            end

            na_pj__place(view)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Place the Projection, or Say Why It Will Not Go
        # ------------------------------------------------------------
        def na_pj__place(view)
            refusal = na_pj__refusal

            if refusal
                UI.beep
                na_revise__notice("Not placed — #{refusal}")
                return false
            end

            na_pj__commit(view)
        end
        # ---------------------------------------------------------------

        # ON LEFT BUTTON UP | Press on the Face, Release Over the Target
        # ------------------------------------------------------------
        def onLButtonUp(flags, x, y, view)
            na_drawn__sync_modifier(flags)
            return unless @na_state == :picking_target
            return unless @na_drag_press_active

            @na_drag_press_active = false
            travelled_px = (x.to_f - @na_press_x.to_f).abs + (y.to_f - @na_press_y.to_f).abs
            return if travelled_px < NA_DRAWN_DRAG_MIN_PX

            na_drawn__update_cursor(view, x, y)
            na_pj__place(view) if @na_pj_target && !@na_pj_edge_hover

            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate
        end
        # ---------------------------------------------------------------

        # ON LEFT BUTTON DOUBLE CLICK | Carry the Face to the Last Target
        # ------------------------------------------------------------
        # A double click arrives as Down, Up, DoubleClick, Up, and the first
        # Down has already taken the face. If the mouse has not travelled since,
        # what a SketchUp user means is native Push/Pull's repeat — here, on to
        # the target the last projection reached.
        # ------------------------------------------------------------
        def onLButtonDoubleClick(flags, x, y, view)
            na_drawn__sync_modifier(flags)
            return false unless na_drawn__ensure_known_state
            return false unless @na_state == :picking_target
            return false if @na_pj_preselected

            travelled_px = (x.to_f - @na_press_x.to_f).abs + (y.to_f - @na_press_y.to_f).abs
            na_revise__repeat_or_refuse(view) if travelled_px < NA_DRAWN_DRAG_MIN_PX

            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
            true
        end
        # ---------------------------------------------------------------

        # ON RETURN | Enter Places on the Target Under the Cursor
        # ------------------------------------------------------------
        def onReturn(view)
            return false unless na_drawn__ensure_known_state
            return false unless @na_state == :picking_target

            na_pj__place(view)
            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
            true
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Keys — TAB and BKSP
        # -----------------------------------------------------------------------------

        # FUNCTION | TAB Toggles Quad Mode, the Push Tool's Own Setting
        # ------------------------------------------------------------
        # One preference for both tools: quads are a way of working, not a
        # property of one tool, and finding them on in one and off in the other
        # would be a surprise every time.
        # ------------------------------------------------------------
        def na_drawn__cycle_plane_lock(view)
            enabled = Na__InsertPrimatives.Na__DrawnSettings__ToggleQuadPush

            Sketchup::set_status_text(
                enabled ? 'QUAD mode ON — the start loop stays as edges; into the solid it cuts a loop at the target' :
                          'QUAD mode OFF — the projection merges into the faces it grows from',
                SB_PROMPT
            )
            @na_last_status_text = nil
            na_drawn__update_cursor(view, @na_last_mouse_x, @na_last_mouse_y)
            na_drawn__refresh_vcb
            view.invalidate if view
            enabled
        end
        # ---------------------------------------------------------------

        # FUNCTION | BKSP Releases the Newest Thing Held, Then the Face
        # ------------------------------------------------------------
        # Offset first, then an edge, then an axis — each a decision the user
        # made and may want back without abandoning the face. A preselection
        # is never dropped by BKSP; ESC does that.
        # ------------------------------------------------------------
        def na_drawn__step_back(view)
            note =
                if Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_pj_offset) != 0
                    @na_pj_offset = 0.0
                    'Offset released — the face lands on the target'
                elsif @na_pj_edge_lock
                    @na_pj_edge_lock = nil
                    @na_pj_sense     = :auto
                    'Edge released — the face travels its own way again'
                elsif @na_axis_lock
                    @na_axis_lock = nil
                    'Axis released'
                elsif @na_state == :picking_target && !@na_pj_preselected
                    na_drawn__reset_pick_state
                    'Face released'
                end

            na_drawn__update_cursor(view, @na_last_mouse_x, @na_last_mouse_y)
            @na_last_status_text = nil
            na_drawn__update_status_text
            na_drawn__refresh_vcb
            na_revise__notice(note) if note
            view.invalidate if view
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Stages This Tool Does Not Have
        # -----------------------------------------------------------------------------

        # FUNCTION | Never Reached — There Is No Rectangle Stage
        # ------------------------------------------------------------
        def na_drawn__advance_from_b(view)
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Never Reached — There Is No Depth Stage
        # ------------------------------------------------------------
        def na_drawn__advance_from_depth(view)
            false
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Preview
        # -----------------------------------------------------------------------------

        # FUNCTION | The Live Preview, for Anything That Asks the Mixin's Way
        # ------------------------------------------------------------
        def na_drawn__draw_preview(view)
            @na_state == :idle ? na_pj__draw_hover(view) : na_pj__draw_projection(view)
        end
        # ---------------------------------------------------------------

        # DRAW | Hover, Projection, Direction and the Retype Ghost
        # ------------------------------------------------------------
        def draw(view)
            @na_ip.draw(view) if @na_ctrl_held && @na_state == :picking_target && @na_ip && @na_ip.valid?
            Na__InsertPrimatives.Na__DrawnPreview__DrawAxisRay(view, na_drawn__axis_ray_origin, @na_axis_lock)

            if @na_state == :idle
                na_pj__draw_hover(view)
                na_pj__draw_direction(view)                                   # <-- An edge locked before any face was taken
                na_revise__draw_animation(view)                               # <-- The ghost of a retyped offset
                return
            end

            na_pj__draw_projection(view)
            Na__InsertPrimatives.Na__DrawnPreview__DrawCrosshair(view, @na_point_a, nil, NA_DRAWN_ANCHOR_COLOR)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Status and Measurements Box
        # -----------------------------------------------------------------------------

        # FUNCTION | Middle Section of the Status Bar Line
        # ------------------------------------------------------------
        def na_drawn__status_detail
            return na_pj__target_status if @na_state == :picking_target

            focus  = na_drawn__focus_hint
            adjust = na_revise__status_hint

            return "Face #{@na_pj_hover[:area]} m2 — click it, then click what it should reach#{focus}#{adjust}" if @na_pj_hover
            "Hover a face to project, at any nesting depth#{focus}#{adjust}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Status Line While Hunting the Target
        # ------------------------------------------------------------
        def na_pj__target_status
            count = (@na_pj_sources || []).length
            what  = count > 1 ? "#{count} faces" : 'Face'
            hover = @na_pj_edge_hover

            if hover
                return "That edge #{hover[:refusal]}" if hover[:refusal]
                return 'The locked edge — click or DOWN flips it' if @na_pj_edge_lock && @na_pj_edge_lock[:key] == hover[:key]

                return "Click (or DOWN) to travel parallel to this edge — #{Na__InsertPrimatives.Na__DrawnFormat__Mm(hover[:length]).abs} mm, #{hover[:name]}"
            end

            unless @na_pj_target
                return "#{what} taken — now hover what it should reach: a face, a point (CTRL), an object (SHIFT+TAB), or an edge for the direction"
            end

            refusal = na_pj__refusal
            return "Cannot reach #{@na_pj_target[:name]} — #{refusal}" if refusal

            travel =
                if @na_pj_solutions.any? { |solution| solution[:way] == :mixed }
                    Na__InsertPrimatives.Na__Project__CutExtendText(@na_pj_solutions)
                else
                    "#{Na__InsertPrimatives.Na__Project__TravelText(@na_pj_solutions.map { |solution| solution[:travels] })} mm"
                end
            offset = Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_pj_offset).zero? ? '' : ", #{na_pj__offset_words(@na_pj_offset)}"
            "#{what} → #{@na_pj_target[:name]}: #{travel}#{offset} — click to place"
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Snap Section Says What CTRL Does Here
        # ------------------------------------------------------------
        def na_drawn__grid_description
            case na_drawn__snap_mode
            when :vertex      then 'CTRL point target'
            when :vertex_grid then "CTRL+SHIFT point, height on the #{Na__InsertPrimatives.Na__DrawnSettings__GridStepLabel} grid"
            else                   'Lands exactly on the target'
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Plane Section Describes the Direction Instead
        # OBJECT mode is named by the option summary that follows this, as
        # every tool option is.
        # ------------------------------------------------------------
        def na_drawn__plane_description
            mode =
                case na_pj__mode
                when :edge   then 'EDGE'
                when :axis   then "AXIS #{NA_DRAWN_AXIS_LABELS[@na_axis_lock]}"
                when :follow then 'FOLLOW'
                when :slope  then 'SLOPE'
                else              'NORMAL'
                end

            sense = @na_pj_sense.is_a?(Numeric) && @na_pj_sense < 0.0 ? ' flipped' : ''
            "Direction #{mode}#{sense}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Axis Is Already Named in the Direction Section
        # ------------------------------------------------------------
        def na_drawn__axis_description
            ''
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Offset Is the One Typed Value This Tool Holds
        # ------------------------------------------------------------
        def na_drawn__lock_summary
            return '' if Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_pj_offset).zero?

            " | OFFSET #{na_pj__offset_words(@na_pj_offset)} (BKSP releases)"
        end
        # ---------------------------------------------------------------

        # FUNCTION | What TAB, SHIFT+TAB and DOWN Do in This Tool
        # ------------------------------------------------------------
        def na_drawn__tab_hint
            "TAB quads #{na_pj__quad_mode? ? 'ON' : 'OFF'}  SHIFT+TAB #{na_pj__object_mode? ? 'plane' : 'object'}  DOWN edge/flip"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Which Snap Keys This Tool Answers To
        # ------------------------------------------------------------
        def na_drawn__vertex_hint
            'CTRL point  CTRL+SHIFT point→grid'
        end
        # ---------------------------------------------------------------

        # FUNCTION | Measurements Box Label and Live Value
        # ------------------------------------------------------------
        def na_drawn__vcb_label_and_value
            ['Offset', na_revise__vcb_value]
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Typed Offset Re-Makes What Is Placed, or Is Held for the Next Click
        # ------------------------------------------------------------
        # Held, not placed: the target is wherever the cursor happens to rest
        # while typing, and an offset is not worth a projection on to that.
        # ------------------------------------------------------------
        def na_drawn__handle_vcb_text(text, view)
            return na_revise__retype(text, view) if na_revise__available?

            @na_pj_offset = na_pj__parse_offset(text)
            na_drawn__update_cursor(view, @na_last_mouse_x, @na_last_mouse_y)

            na_revise__notice(
                Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_pj_offset).zero? ?
                    'Offset cleared — the face lands on the target' :
                    "Offset #{na_pj__offset_words(@na_pj_offset)} — #{@na_state == :idle ? 'click a face, then its target' : 'click the target'}"
            )
            true
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnProjectTool class

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Public Entry Point
    # -----------------------------------------------------------------------------

    # FUNCTION | Activate the Deep Project Tool (Hotkey Entry Point)
    # ------------------------------------------------------------
    def self.Na__InsertPrimatives__DeepProject
        Na__InsertPrimatives.Na__ModeSwitch__ActivateDrawnProjectTool
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP PROJECT TOOL MODULE
# =============================================================================
