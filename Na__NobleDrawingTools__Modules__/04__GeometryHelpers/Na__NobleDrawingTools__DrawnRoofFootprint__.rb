# =============================================================================
# NA NOBLE DRAWING TOOLS - DRAWN ROOF FOOTPRINT
# =============================================================================
#
# FILE       : Na__NobleDrawingTools__DrawnRoofFootprint__.rb
# NAMESPACE  : Na__NobleDrawingTools
# AUTHOR     : Noble Architecture
# PURPOSE    : A selected face as the plan of a hipped roof: reads it, works out
#              the eaves and the roof over them, and builds the solid
# CREATED    : 2026
#
# DESCRIPTION:
# - The bridge between SketchUp and DrawnRoofSkeleton, which only knows numbers.
#   A FOOTPRINT is the face read into a frame of its own: an origin on the face,
#   u and v in its plane and n square to it, and the face's loops as plain [x, y]
#   in that frame. After that nothing goes back to the face, so an undo or a DEL
#   cannot pull the plan out from under a drag.
# - The preview and the builder both take their points from the same few
#   functions here, so what is drawn on screen is what lands in the model.
#
# COORDINATES (the Coordinate Rule):
# - A selected face is in the open context, so its vertices read WORLD whatever
#   is open, however it is moved, turned, scaled or nested. The frame is therefore
#   a world frame and there is no edit_transform anywhere in this file. The roof
#   group is pinned to the world identity and the world points go straight in,
#   exactly as the rectangle roofs do.
# - The face's normal is worked out from those same world positions rather than
#   asked of the face, so it cannot disagree with them in a scaled group.
#
# FACE DIRECTIONS:
# - The rectangle roofs turn their faces outward from the group's centre. That is
#   only true of convex solids, and a roof with valleys is not one. Here each
#   face already knows which way it should look: up for a slope, down for an
#   underside, out from the wall line for a fascia.
#
# THE FACE IS LEFT ALONE:
# - The roof is a new group standing on it. Nothing is added to the face's own
#   context but that group, and the face is never edited or removed.
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__NobleDrawingTools__DrawnGridSnap__'
require_relative 'Na__NobleDrawingTools__DrawnRoofGeometry__'
require_relative 'Na__NobleDrawingTools__DrawnRoofSkeleton__'

module Na__NobleDrawingTools

    NA_ROOF_SLIVER_AREA = 0.1                                                 # <-- Square inches, about 65 sq mm; see AddRoof

    # -----------------------------------------------------------------------------
    # REGION | Reading a Face
    # -----------------------------------------------------------------------------

    # FUNCTION | Twice-Area Vector of a Loop of World Points
    # ------------------------------------------------------------
    # Newell's method. Unlike a cross product at one corner it is right at an
    # inside corner, and its length is twice the loop's area.
    # ------------------------------------------------------------
    def self.Na__DrawnRoofFootprint__AreaVector(points)
        x = 0.0
        y = 0.0
        z = 0.0
        count = points.length

        count.times do |index|
            a = points[index]
            b = points[(index + 1) % count]
            x += (a.y.to_f - b.y.to_f) * (a.z.to_f + b.z.to_f)
            y += (a.z.to_f - b.z.to_f) * (a.x.to_f + b.x.to_f)
            z += (a.x.to_f - b.x.to_f) * (a.y.to_f + b.y.to_f)
        end

        Geom::Vector3d.new(x, y, z)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Which of Several Selected Faces Is the Plan?
    # ------------------------------------------------------------
    # A triple click takes every face of a box. Flat on plan beats anything else,
    # then the largest, and of a top and a bottom the same size, the top.
    # ------------------------------------------------------------
    def self.Na__DrawnRoofFootprint__ChooseFace(faces)
        faces.max_by do |face|
            points = face.outer_loop.vertices.map { |vertex| vertex.position }
            vector = Na__NobleDrawingTools.Na__DrawnRoofFootprint__AreaVector(points)
            length = vector.length.to_f
            flat   = length > 0.0 && (vector.z.to_f.abs / length) > 0.999 ? 1 : 0

            [flat, (length * 0.5).round(1), points.first.z.to_f]
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Read a Face as a Footprint
    # ------------------------------------------------------------
    # n is the face's normal, turned to point up if it points down: a face on the
    # ground usually does. u runs along the longest edge, so a square-cornered plan
    # comes out square to its frame however it is turned, which keeps the numbers
    # the solver sees as clean as they can be.
    # Returns nil for a face with no area.
    # ------------------------------------------------------------
    def self.Na__DrawnRoofFootprint__FromFace(face)
        return nil unless face && face.valid?

        outer = face.outer_loop.vertices.map { |vertex| vertex.position }
        return nil if outer.length < 3

        vector = Na__NobleDrawingTools.Na__DrawnRoofFootprint__AreaVector(outer)
        return nil unless vector.length.to_f > 0.0

        up = vector.normalize
        up = up.reverse if up.z.to_f < -1.0e-9
        up = Geom::Vector3d.new(0, 0, 1) if up.x.to_f.abs < 1.0e-9 && up.y.to_f.abs < 1.0e-9

        origin  = outer.first
        longest = Na__NobleDrawingTools.Na__DrawnRoofFootprint__LongestChord(outer)
        return nil unless longest

        lean   = longest.dot(up).to_f
        across = Geom::Vector3d.new(longest.x - (up.x * lean), longest.y - (up.y * lean), longest.z - (up.z * lean))
        return nil unless across.length.to_f > 0.0

        u_axis = across.normalize
        v_axis = up.cross(u_axis).normalize

        frame = { :origin => origin, :u => u_axis, :v => v_axis, :n => up }

        plan_outer = outer.map { |point| Na__NobleDrawingTools.Na__DrawnRoofFootprint__ToPlan(frame, point) }
        plan_outer = plan_outer.reverse if Na__NobleDrawingTools.Na__DrawnRoofSkeleton__SignedArea(plan_outer) < 0.0
        plan_outer = Na__NobleDrawingTools.Na__DrawnRoofSkeleton__CleanLoop(plan_outer)
        return nil if plan_outer.length < 3

        plan_holes = face.loops.reject { |loop_entity| loop_entity.outer? }.map do |loop_entity|
            hole = loop_entity.vertices.map { |vertex| Na__NobleDrawingTools.Na__DrawnRoofFootprint__ToPlan(frame, vertex.position) }
            hole = hole.reverse if Na__NobleDrawingTools.Na__DrawnRoofSkeleton__SignedArea(hole) > 0.0
            Na__NobleDrawingTools.Na__DrawnRoofSkeleton__CleanLoop(hole)
        end

        plan_holes = plan_holes.select { |hole| hole.length >= 3 }
        loops      = [plan_outer] + plan_holes
        sides      = loops.inject(0) { |sum, plan_loop| sum + plan_loop.length }

        frame.merge(
            :loops     => loops,
            :sides     => sides,
            :area      => loops.inject(0.0) { |sum, plan_loop| sum + Na__NobleDrawingTools.Na__DrawnRoofSkeleton__SignedArea(plan_loop) },
            :courtyards => plan_holes.length,
            :eaves_memo => {},
            :roof_memo  => {},
            :note      => nil
        )
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Longest Edge of a Loop of World Points, as a Vector
    # ------------------------------------------------------------
    def self.Na__DrawnRoofFootprint__LongestChord(points)
        best   = nil
        length = 0.0

        points.each_with_index do |point, index|
            step = points[(index + 1) % points.length] - point
            next unless step.length.to_f > length

            length = step.length.to_f
            best   = step
        end

        best
    end
    # ---------------------------------------------------------------

    # FUNCTION | A World Point in a Footprint's Frame: [x, y]
    # ------------------------------------------------------------
    def self.Na__DrawnRoofFootprint__ToPlan(footprint, point)
        step = point - footprint[:origin]
        [step.dot(footprint[:u]).to_f, step.dot(footprint[:v]).to_f]
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Point in a Footprint's Frame, at a Height, in World
    # ------------------------------------------------------------
    def self.Na__DrawnRoofFootprint__ToWorld(footprint, x, y, height)
        origin = footprint[:origin]
        u_axis = footprint[:u]
        v_axis = footprint[:v]
        n_axis = footprint[:n]

        Geom::Point3d.new(
            origin.x.to_f + (u_axis.x.to_f * x) + (v_axis.x.to_f * y) + (n_axis.x.to_f * height),
            origin.y.to_f + (u_axis.y.to_f * x) + (v_axis.y.to_f * y) + (n_axis.y.to_f * height),
            origin.z.to_f + (u_axis.z.to_f * x) + (v_axis.z.to_f * y) + (n_axis.z.to_f * height)
        )
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Middle of a Footprint's Plan: [x, y]
    # ------------------------------------------------------------
    def self.Na__DrawnRoofFootprint__Middle(footprint)
        low, high = Na__NobleDrawingTools.Na__DrawnRoofFootprint__PlanBox(footprint)
        [(low[0] + high[0]) * 0.5, (low[1] + high[1]) * 0.5]
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Box Round a Footprint's Plan: [[low x, low y], [high x, high y]]
    # ------------------------------------------------------------
    def self.Na__DrawnRoofFootprint__PlanBox(footprint)
        xs = footprint[:loops].first.map { |point| point[0] }
        ys = footprint[:loops].first.map { |point| point[1] }
        [[xs.min, ys.min], [xs.max, ys.max]]
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Eaves and Roof
    # -----------------------------------------------------------------------------

    # FUNCTION | The Eaves: the Plan Pushed Out by the Soffit, Ready to Draw
    # ------------------------------------------------------------
    # Worked out once per soffit and kept. The soffit drag lands on the same grid
    # steps over and over, and the plan never changes. nil if it cannot be done.
    # ------------------------------------------------------------
    def self.Na__DrawnRoofFootprint__Eaves(footprint, soffit = 0.0)
        memo = footprint[:eaves_memo]
        key  = (soffit.to_f.abs * 10_000.0).round
        return memo[key] if memo.key?(key)

        memo.clear if memo.length > 64

        loops = Na__NobleDrawingTools.Na__DrawnRoofSkeleton__Offset(footprint[:loops], soffit.to_f.abs)

        memo[key] =
            if loops
                {
                    :loops  => loops,
                    :sides  => loops.inject(0) { |sum, plan_loop| sum + plan_loop.length },
                    :area   => loops.inject(0.0) { |sum, plan_loop| sum + Na__NobleDrawingTools.Na__DrawnRoofSkeleton__SignedArea(plan_loop) },
                    :groups => Na__NobleDrawingTools.Na__DrawnRoofSkeleton__GroupLoops(loops).map do |group|
                        group.merge(:triangles => Na__NobleDrawingTools.Na__DrawnRoofSkeleton__Triangulate(group[:outer], group[:holes]))
                    end
                }
            end
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Roof Over the Eaves, at a Slope of One
    # ------------------------------------------------------------
    # Kept per soffit too. The pitch only stretches the answer upward, so a drag
    # of the rise costs no solving at all. nil if no roof passes the checks.
    # ------------------------------------------------------------
    def self.Na__DrawnRoofFootprint__Solution(footprint, soffit = 0.0)
        memo = footprint[:roof_memo]
        key  = (soffit.to_f.abs * 10_000.0).round
        return memo[key] if memo.key?(key)

        memo.clear if memo.length > 64

        eaves = Na__NobleDrawingTools.Na__DrawnRoofFootprint__Eaves(footprint, soffit)
        memo[key] = eaves && Na__NobleDrawingTools.Na__DrawnRoofSkeleton__Solve(eaves[:loops])
    end
    # ---------------------------------------------------------------

    # FUNCTION | How Many Ridges, Hips and Valleys a Roof Has, as Words
    # ------------------------------------------------------------
    def self.Na__DrawnRoofFootprint__LineWords(solution)
        tally = Hash.new(0)
        solution[:lines].each { |line| tally[line[:kind]] += 1 }

        [[:ridge, 'ridge', 'ridges'], [:hip, 'hip', 'hips'], [:valley, 'valley', 'valleys']].map do |kind, one, many|
            "#{tally[kind]} #{tally[kind] == 1 ? one : many}"
        end.join('  ·  ')
    end
    # ---------------------------------------------------------------

    # FUNCTION | Roof Volume in Cubic Metres
    # ------------------------------------------------------------
    def self.Na__DrawnRoofFootprint__VolumeM3(solution, rise)
        height = solution[:height].to_f
        return format('%.3f', 0.0) unless height > 0.0

        cubic_inches = solution[:volume].to_f * (rise.to_f.abs / height)
        format('%.3f', cubic_inches * (NA_DRAWN_INCH_TO_MM**3) / 1_000_000_000.0)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Plinth Volume in Cubic Metres
    # ------------------------------------------------------------
    def self.Na__DrawnRoofFootprint__PlinthVolumeM3(eaves, fascia)
        cubic_inches = eaves[:area].to_f.abs * fascia.to_f.abs
        format('%.3f', cubic_inches * (NA_DRAWN_INCH_TO_MM**3) / 1_000_000_000.0)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Distance Past the Wall Line, and Which Way Is Out
    # ------------------------------------------------------------
    # The soffit drag on a plan of any shape. Nearest the middle of a wall, it is
    # the square distance from that wall. Past a corner it is the larger of the two
    # overshoots, so the eaves corner follows the cursor square rather than on a
    # round, as it does for the rectangle. Inside the plan the reach comes out
    # negative by itself, and reads as no soffit. Returns [reach, axis, direction]:
    # outward is axis x direction.
    # ------------------------------------------------------------
    def self.Na__DrawnRoofFootprint__OutsideReach(footprint, point)
        x, y = Na__NobleDrawingTools.Na__DrawnRoofFootprint__ToPlan(footprint, point)
        best = nil

        footprint[:loops].each do |plan_loop|
            count = plan_loop.length

            count.times do |index|
                a      = plan_loop[index]
                b      = plan_loop[(index + 1) % count]
                run_x  = b[0] - a[0]
                run_y  = b[1] - a[1]
                square = (run_x * run_x) + (run_y * run_y)
                next unless square > 0.0

                along = (((x - a[0]) * run_x) + ((y - a[1]) * run_y)) / square
                along = 0.0 if along < 0.0
                along = 1.0 if along > 1.0

                off_x    = x - (a[0] + (along * run_x))
                off_y    = y - (a[1] + (along * run_y))
                distance = Math.sqrt((off_x * off_x) + (off_y * off_y))
                next if best && distance >= best[:distance]

                best = { :distance => distance, :loop => plan_loop, :index => index, :along => along }
            end
        end

        return [0.0, footprint[:n], 0.0] unless best

        plan_loop = best[:loop]
        count     = plan_loop.length
        edges     = [best[:index]]

        edges << ((best[:index] - 1) % count)  if best[:along] <= 0.0                      # <-- At a corner, both walls have a say
        edges << ((best[:index] + 1) % count)  if best[:along] >= 1.0

        reach, out_x, out_y = edges.map do |index|
            a      = plan_loop[index]
            b      = plan_loop[(index + 1) % count]
            run_x  = b[0] - a[0]
            run_y  = b[1] - a[1]
            length = Math.sqrt((run_x * run_x) + (run_y * run_y))
            right  = [run_y / length, -run_x / length]                        # <-- The plan is on the left of its loops

            [((x - a[0]) * right[0]) + ((y - a[1]) * right[1]), right[0], right[1]]
        end.max_by(&:first)

        u_axis = footprint[:u]
        v_axis = footprint[:v]
        axis   = Geom::Vector3d.new(
            (u_axis.x.to_f * out_x) + (v_axis.x.to_f * out_y),
            (u_axis.y.to_f * out_x) + (v_axis.y.to_f * out_y),
            (u_axis.z.to_f * out_x) + (v_axis.z.to_f * out_y)
        )

        [reach, axis, 1.0]
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Middle of the Longest Wall and Which Way It Faces
    # ------------------------------------------------------------
    # Where the soffit dimension is drawn. Returns [x, y, out x, out y].
    # ------------------------------------------------------------
    def self.Na__DrawnRoofFootprint__LongestWall(footprint)
        plan_loop = footprint[:loops].first
        count     = plan_loop.length
        best      = nil
        longest   = 0.0

        count.times do |index|
            a      = plan_loop[index]
            b      = plan_loop[(index + 1) % count]
            run_x  = b[0] - a[0]
            run_y  = b[1] - a[1]
            length = Math.sqrt((run_x * run_x) + (run_y * run_y))
            next unless length > longest

            longest = length
            best    = [(a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5, run_y / length, -run_x / length]
        end

        best
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | In World, for Drawing and Building Alike
    # -----------------------------------------------------------------------------

    # FUNCTION | Plan Loops at One Height, in World
    # ------------------------------------------------------------
    def self.Na__DrawnRoofFootprint__LoopsInWorld(footprint, loops, height)
        loops.map do |plan_loop|
            plan_loop.map { |point| Na__NobleDrawingTools.Na__DrawnRoofFootprint__ToWorld(footprint, point[0], point[1], height) }
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | One Eaves Group at One Height, in World
    # ------------------------------------------------------------
    def self.Na__DrawnRoofFootprint__GroupInWorld(footprint, group, height)
        convert = lambda { |point| Na__NobleDrawingTools.Na__DrawnRoofFootprint__ToWorld(footprint, point[0], point[1], height) }

        {
            :outer     => group[:outer].map(&convert),
            :holes     => group[:holes].map { |hole| hole.map(&convert) },
            :triangles => group[:triangles].map { |triangle| triangle.map(&convert) }
        }
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Roof's Faces and Lines, in World
    # ------------------------------------------------------------
    # base is the height of the eaves in the frame, rise the height of the top of
    # the roof above them. A point's own height is its t x rise / the highest t.
    # ------------------------------------------------------------
    def self.Na__DrawnRoofFootprint__RoofInWorld(footprint, solution, base, rise)
        height = solution[:height].to_f
        slope  = height > 0.0 ? rise.to_f.abs / height : 0.0

        convert = lambda do |point|
            Na__NobleDrawingTools.Na__DrawnRoofFootprint__ToWorld(footprint, point[0], point[1], base.to_f + (point[2].to_f * slope))
        end

        {
            :faces => solution[:faces].map do |face|
                {
                    :outer     => face[:outer].map(&convert),
                    :holes     => face[:holes].map { |hole| hole.map(&convert) },
                    :triangles => face[:triangles].map { |triangle| triangle.map(&convert) }
                }
            end,
            :lines => solution[:lines].map do |line|
                { :a => convert.call(line[:a]), :b => convert.call(line[:b]), :kind => line[:kind], :top => [line[:a][2], line[:b][2]].max }
            end
        }
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Building the Solid
    # -----------------------------------------------------------------------------

    # FUNCTION | Add One Face, Looking the Right Way
    # ------------------------------------------------------------
    # axis is the way the face should look. If SketchUp refuses the loop, which it
    # can for a loop a hair out of flat, the same face goes in as its triangles:
    # one line more on the roof is a better answer than no roof.
    # Returns false only if nothing could be added.
    # ------------------------------------------------------------
    def self.Na__DrawnRoofFootprint__AddFace(entities, outer, holes, triangles, axis)
        face = Na__NobleDrawingTools.Na__DrawnRoofFootprint__TryFace(entities, outer)

        if face
            Na__NobleDrawingTools.Na__DrawnRoofFootprint__FaceLook(face, axis)    # <-- Before the holes, which leave it looking the same way

            holes.each do |hole|
                inside = Na__NobleDrawingTools.Na__DrawnRoofFootprint__TryFace(entities, hole)
                inside.erase! if inside && inside.valid?
            end

            return true
        end

        built = 0

        triangles.each do |triangle|
            part = Na__NobleDrawingTools.Na__DrawnRoofFootprint__TryFace(entities, triangle)
            next unless part

            Na__NobleDrawingTools.Na__DrawnRoofFootprint__FaceLook(part, axis)
            built += 1
        end

        built > 0
    end
    # ---------------------------------------------------------------

    # FUNCTION | add_face, With a Refusal Reading as nil
    # ------------------------------------------------------------
    def self.Na__DrawnRoofFootprint__TryFace(entities, points)
        entities.add_face(points)
    rescue ArgumentError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Turn a Face to Look Along an Axis
    # ------------------------------------------------------------
    def self.Na__DrawnRoofFootprint__FaceLook(face, axis)
        return unless face && face.valid?

        face.reverse! if face.normal.dot(axis) < 0.0
    end
    # ---------------------------------------------------------------

    # FUNCTION | Add the Plinth: Its Top, Its Underside and a Fascia Round Every Loop
    # ------------------------------------------------------------
    def self.Na__DrawnRoofFootprint__AddPlinth(entities, footprint, eaves, fascia)
        up   = footprint[:n]
        down = up.reverse

        eaves[:groups].each do |group|
            top    = Na__NobleDrawingTools.Na__DrawnRoofFootprint__GroupInWorld(footprint, group, fascia)
            bottom = Na__NobleDrawingTools.Na__DrawnRoofFootprint__GroupInWorld(footprint, group, 0.0)

            return false unless Na__NobleDrawingTools.Na__DrawnRoofFootprint__AddFace(entities, top[:outer], top[:holes], top[:triangles], up)
            return false unless Na__NobleDrawingTools.Na__DrawnRoofFootprint__AddFace(entities, bottom[:outer], bottom[:holes], bottom[:triangles], down)

            ([group[:outer]] + group[:holes]).each do |plan_loop|
                count = plan_loop.length

                count.times do |index|
                    a = plan_loop[index]
                    b = plan_loop[(index + 1) % count]
                    return false unless Na__NobleDrawingTools.Na__DrawnRoofFootprint__AddFasciaPanel(entities, footprint, a, b, fascia)
                end
            end
        end

        true
    end
    # ---------------------------------------------------------------

    # FUNCTION | Add One Upright Panel of the Fascia
    # ------------------------------------------------------------
    def self.Na__DrawnRoofFootprint__AddFasciaPanel(entities, footprint, a, b, fascia)
        low_a  = Na__NobleDrawingTools.Na__DrawnRoofFootprint__ToWorld(footprint, a[0], a[1], 0.0)
        low_b  = Na__NobleDrawingTools.Na__DrawnRoofFootprint__ToWorld(footprint, b[0], b[1], 0.0)
        high_b = Na__NobleDrawingTools.Na__DrawnRoofFootprint__ToWorld(footprint, b[0], b[1], fascia)
        high_a = Na__NobleDrawingTools.Na__DrawnRoofFootprint__ToWorld(footprint, a[0], a[1], fascia)

        u_axis = footprint[:u]
        v_axis = footprint[:v]
        out_x  = b[1] - a[1]                                                  # <-- The plan is on the left, so out is on the right
        out_y  = a[0] - b[0]
        out    = Geom::Vector3d.new(
            (u_axis.x.to_f * out_x) + (v_axis.x.to_f * out_y),
            (u_axis.y.to_f * out_x) + (v_axis.y.to_f * out_y),
            (u_axis.z.to_f * out_x) + (v_axis.z.to_f * out_y)
        )

        Na__NobleDrawingTools.Na__DrawnRoofFootprint__AddFace(
            entities, [low_a, low_b, high_b, high_a], [],
            [[low_a, low_b, high_b], [low_a, high_b, high_a]], out
        )
    end
    # ---------------------------------------------------------------

    # FUNCTION | Add the Roof's Slopes and the Underside They Stand On
    # ------------------------------------------------------------
    # A plan a hair out of square can leave a sliver of a face, narrower than
    # SketchUp can hold. If SketchUp refuses one the roof goes on without it and the
    # report says it is not solid, rather than the whole roof being refused for a
    # sliver nobody could see. Refused faces of any size do refuse the roof.
    # ------------------------------------------------------------
    def self.Na__DrawnRoofFootprint__AddRoof(entities, footprint, eaves, solution, base, rise)
        up    = footprint[:n]
        world = Na__NobleDrawingTools.Na__DrawnRoofFootprint__RoofInWorld(footprint, solution, base, rise)

        world[:faces].each_with_index do |face, index|
            next if Na__NobleDrawingTools.Na__DrawnRoofFootprint__AddFace(entities, face[:outer], face[:holes], face[:triangles], up)
            return false if Na__NobleDrawingTools.Na__DrawnRoofSkeleton__SignedArea(solution[:faces][index][:outer]).abs > NA_ROOF_SLIVER_AREA
        end

        eaves[:groups].each do |group|
            under = Na__NobleDrawingTools.Na__DrawnRoofFootprint__GroupInWorld(footprint, group, base)
            return false unless Na__NobleDrawingTools.Na__DrawnRoofFootprint__AddFace(entities, under[:outer], under[:holes], under[:triangles], up.reverse)
        end

        true
    end
    # ---------------------------------------------------------------

    # FUNCTION | Fill an Empty Roof Group
    # ------------------------------------------------------------
    # plinth is nil for a roof alone, whose faces go straight into the group, or
    # { :fascia, :soffit }, for 02__FasciaSoffit and 02__RoofMass as children. The
    # same arrangement as the rectangle roofs.
    # ------------------------------------------------------------
    def self.Na__DrawnRoofFootprint__FillGroup(group, footprint, rise, plinth)
        soffit   = plinth ? plinth[:soffit].to_f.abs : 0.0
        fascia   = plinth ? plinth[:fascia].to_f.abs : 0.0
        eaves    = Na__NobleDrawingTools.Na__DrawnRoofFootprint__Eaves(footprint, soffit)
        solution = Na__NobleDrawingTools.Na__DrawnRoofFootprint__Solution(footprint, soffit)
        return false unless eaves && solution

        unless plinth
            return Na__NobleDrawingTools.Na__DrawnRoofFootprint__AddRoof(group.entities, footprint, eaves, solution, 0.0, rise)
        end

        board = Na__NobleDrawingTools.Na__DrawnRoof__AddChildGroup(group, NA_DRAWN_ROOF_PLINTH_GROUP_NAME)
        return false unless Na__NobleDrawingTools.Na__DrawnRoofFootprint__AddPlinth(board.entities, footprint, eaves, fascia)

        mass = Na__NobleDrawingTools.Na__DrawnRoof__AddChildGroup(group, NA_DRAWN_ROOF_MASS_GROUP_NAME)
        Na__NobleDrawingTools.Na__DrawnRoofFootprint__AddRoof(mass.entities, footprint, eaves, solution, fascia, rise)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Create the Roof Group Over a Footprint
    # ------------------------------------------------------------
    def self.Na__DrawnRoofFootprint__CreateRoof(footprint, rise, plinth = nil)
        return nil unless footprint
        return nil unless Na__NobleDrawingTools.Na__DrawnGeom__ValidDimension?(rise)
        return nil unless Na__NobleDrawingTools.Na__DrawnRoof__PlinthBuildable?(plinth)

        model = Sketchup.active_model
        model.start_operation('Draw Roof', true)

        begin
            group      = model.active_entities.add_group
            group.name = NA_DRAWN_ROOF_GROUP_NAMES[:hip]
            Na__NobleDrawingTools.Na__DrawnGeom__PinGroupToWorld(group)        # <-- World loops into a closed group: see DrawnGeometry

            unless Na__NobleDrawingTools.Na__DrawnRoofFootprint__FillGroup(group, footprint, rise, plinth)
                model.abort_operation
                return nil
            end

            model.commit_operation
            group
        rescue StandardError
            model.abort_operation
            nil
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Rebuild a Roof Group Over the Same Footprint
    # ------------------------------------------------------------
    def self.Na__DrawnRoofFootprint__RebuildRoof(group, footprint, rise, plinth = nil)
        return false unless group && group.valid? && footprint
        return false unless Na__NobleDrawingTools.Na__DrawnGeom__ValidDimension?(rise)
        return false unless Na__NobleDrawingTools.Na__DrawnRoof__PlinthBuildable?(plinth)

        model = Sketchup.active_model
        model.start_operation('Adjust Drawn Roof', true)

        begin
            group.transformation = Geom::Transformation.new
            group.entities.clear!

            unless Na__NobleDrawingTools.Na__DrawnRoofFootprint__FillGroup(group, footprint, rise, plinth)
                model.abort_operation
                return false
            end

            model.commit_operation
            true
        rescue StandardError
            model.abort_operation
            false
        end
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__NobleDrawingTools module

# =============================================================================
# END OF DRAWN ROOF FOOTPRINT MODULE
# =============================================================================
