# =============================================================================
# NA INSERT PRIMATIVES - DEEP SCALE FRAME
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnScale__Frame__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : The box Deep Scale works in: an object's own axes, its size, its
#              26 grips, and the ghost of its edges for the live preview
# CREATED    : 2026
#
# DESCRIPTION:
# - Everything Deep Scale does is measured in the object's OWN box, the
#   definition's bounds in the definition's axes, never the world-axis box
#   around it. On a door turned 30 degrees the world box is the wrong shape
#   and the wrong size; the definition box is the door.
# - A frame is a snapshot of that box: the local min / max / centre, the
#   world transformation that places it, the world length of each local axis
#   and the 26 grips SketchUp's own Scale tool would show. It is rebuilt only
#   when its fingerprint changes (a commit, an undo), never mid-drag.
#
# THE COORDINATE RULE, AS IT APPLIES HERE (see the DeepPick hub header):
# - The object is picked from the OPEN context, so the first instance on its
#   path below the open one sits directly in it and its #transformation is
#   world. Everything deeper (a target reached by double-clicking down) lives
#   in closed definitions and reports local to its parent, so the world
#   transform is that first one times each one below it, in order.
# - The object's own definition is never the open context (it is the thing
#   being picked, not the room the user is standing in), so every position
#   read inside it is definition-local. The ghost walk relies on that.
#
# LOOSE GEOMETRY (5.2.9):
# - A selection that is not one group or component — loose edges and faces,
#   or several objects at once — is boxed in the axes the user is drawing
#   in: the open group's own red, green and blue however deep it is (the
#   whole stack, Model#edit_transform), or at the root the model's drawing
#   axes. Its points sit in the open context and report world, so the box
#   is taken through the inverse of those axes. The frame carries :loose,
#   :entities and :context instead of an instance; it has no definition, so
#   nowhere to keep stretch planes, and the tool keeps them out of it.
#
# FRAME HASH:
#   :instance, :definition, :path   the object and its ABSOLUTE path
#   :world, :inverse                definition-local -> world, and back
#   :min, :max, :centre             local box, three Floats each (inches)
#   :local_lengths                  max - min per axis (inches)
#   :scales                         world length of one local unit per axis
#   :world_lengths                  local_lengths * scales
#   :dirs                           world unit vector of each local axis
#   :usable                         false for an axis the object is flat on
#   :fingerprint                    what has to change for the frame to be stale
#
# =============================================================================

require 'sketchup.rb'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Frame Constants
    # -----------------------------------------------------------------------------

    NA_SCALE_AXES            = [:x, :y, :z].freeze
    NA_SCALE_AXIS_INDEX      = { :x => 0, :y => 1, :z => 2 }.freeze
    NA_SCALE_GRIP_KINDS      = { 1 => :face, 2 => :edge, 3 => :corner }.freeze
    NA_SCALE_GHOST_DRAW_MAX  = 6_000                                          # <-- Points the live ghost projects per frame before it gives way to the box
    NA_SCALE_GHOST_SCAN_MAX  = 40_000                                         # <-- Points read for the stretch limit; past this the limit is a best guess
    NA_SCALE_GHOST_MAX_DEPTH = 16

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Paths and Transforms
    # -----------------------------------------------------------------------------

    # FUNCTION | How Many Instances Deep the User's Open Context Is
    # ------------------------------------------------------------
    def self.Na__ScaleFrame__OpenDepth(model = Sketchup.active_model)
        return 0 unless model

        path = model.active_path
        path ? path.length : 0
    rescue StandardError
        0
    end
    # ---------------------------------------------------------------

    # FUNCTION | Does an Absolute Path Still Hang Off the Open Context?
    # ------------------------------------------------------------
    # An undo can close the group the user was in, and anything can erase an
    # instance on the way down. A path that no longer starts with the open
    # context reads every transform in the wrong space, so it is refused
    # rather than drawn somewhere plausible and wrong.
    # ------------------------------------------------------------
    def self.Na__ScaleFrame__PathLive?(path)
        instances = Na__InsertPrimatives.Na__DeepPick__Instances(path)
        return false if instances.empty?
        return false unless instances.all? { |instance| instance && instance.valid? }

        model = Sketchup.active_model
        open  = model ? (model.active_path || []) : []
        return false if instances.length <= open.length

        instances[0...open.length].each_with_index.all? { |instance, index| instance.equal?(open[index]) || instance == open[index] }
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Definition-Local to World for the Instance at the End of a Path
    # ------------------------------------------------------------
    # The open context's own instances are skipped: their contents report
    # global already. The first instance below them is world, every one after
    # it is local to the one before.
    # ------------------------------------------------------------
    def self.Na__ScaleFrame__WorldTransform(path)
        return nil unless Na__InsertPrimatives.Na__ScaleFrame__PathLive?(path)

        instances = Na__InsertPrimatives.Na__DeepPick__Instances(path)
        open      = Na__InsertPrimatives.Na__ScaleFrame__OpenDepth
        xform     = Geom::Transformation.new

        instances.each_with_index do |instance, index|
            next if index < open

            xform = xform * instance.transformation
        end

        xform
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Local Direction as a World Vector, Keeping Its Length
    # Two points rather than the bare vector, the rule the push tool keeps:
    # a direction is a difference of positions, and transforming positions
    # cannot be caught out by how a translation is applied to a vector.
    # ------------------------------------------------------------
    def self.Na__ScaleFrame__WorldVector(xform, local_vector)
        origin = Geom::Point3d.new(0, 0, 0)
        ahead  = Geom::Point3d.new(local_vector.x, local_vector.y, local_vector.z)

        ahead.transform(xform) - origin.transform(xform)
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Frame Construction
    # -----------------------------------------------------------------------------

    # FUNCTION | Everything Deep Scale Needs to Know About an Object's Box
    # Returns nil for an object with nothing in it, or one whose path no
    # longer reaches it from the open context.
    # ------------------------------------------------------------
    def self.Na__ScaleFrame__Build(instance, path)
        return nil unless instance && instance.valid? && instance.respond_to?(:definition)

        world = Na__InsertPrimatives.Na__ScaleFrame__WorldTransform(path)
        return nil unless world

        definition = instance.definition
        bounds     = definition.bounds
        return nil if bounds.nil? || bounds.empty?

        min   = [bounds.min.x.to_f, bounds.min.y.to_f, bounds.min.z.to_f]
        max   = [bounds.max.x.to_f, bounds.max.y.to_f, bounds.max.z.to_f]
        frame = Na__InsertPrimatives.Na__ScaleFrame__Assemble(world, min, max)
        return nil unless frame

        frame.merge(
            :instance    => instance,
            :definition  => definition,
            :path        => path,
            :depth       => Na__InsertPrimatives.Na__DeepPick__Instances(path).length,
            :name        => Na__InsertPrimatives.Na__DeepPick__InstanceName(instance),
            :fingerprint => Na__InsertPrimatives.Na__ScaleFrame__Fingerprint(instance, path, world)
        )
    rescue StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "NA DEEP SCALE: frame not built — #{error.message}"
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Measured Part of a Frame: a Local Box and the Axes That Place It
    # ------------------------------------------------------------
    # Shared by an object's frame and a loose selection's: everything that
    # follows from world (local -> world) and the box alone. nil when an
    # axis is degenerate, or the box is flat in every direction.
    # ------------------------------------------------------------
    def self.Na__ScaleFrame__Assemble(world, min, max)
        centre = (0..2).map { |n| (min[n] + max[n]) * 0.5 }
        local  = (0..2).map { |n| max[n] - min[n] }

        units   = [Geom::Vector3d.new(1, 0, 0), Geom::Vector3d.new(0, 1, 0), Geom::Vector3d.new(0, 0, 1)]
        vectors = units.map { |unit| Na__InsertPrimatives.Na__ScaleFrame__WorldVector(world, unit) }
        scales  = vectors.map { |vector| vector.length.to_f }
        return nil if scales.any? { |scale| scale <= 0.0 }

        dirs   = vectors.map { |vector| vector.clone.normalize }
        worlds = (0..2).map { |n| local[n] * scales[n] }
        usable = worlds.map { |length| length > NA_DRAWN_MIN_DIMENSION.to_f }
        return nil unless usable.any?

        {
            :world         => world,
            :inverse       => world.inverse,
            :min           => min,
            :max           => max,
            :centre        => centre,
            :local_lengths => local,
            :scales        => scales,
            :world_lengths => worlds,
            :dirs          => dirs,
            :usable        => usable
        }
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Axes Loose Geometry Is Boxed In
    # ------------------------------------------------------------
    # The axes the user is drawing in. Inside an open group or component, its
    # own red, green and blue, however deep and however each level above it
    # is moved, turned or scaled: Model#edit_transform is that whole stack in
    # one matrix, and the open group's axis directions are the use the
    # coordinate rule allows it. At the root, the model's drawing axes, so
    # the box follows Tools > Axes as SketchUp's own Scale does.
    # ------------------------------------------------------------
    def self.Na__ScaleFrame__ContextAxes(model)
        path = model.active_path
        return model.edit_transform if path && !path.empty?
        return model.axes.transformation if model.respond_to?(:axes) && model.axes

        Geom::Transformation.new
    rescue StandardError
        Geom::Transformation.new
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Box Around Loose Geometry, in the Axes the User Is Drawing In
    # ------------------------------------------------------------
    # entities are the selection, all in the open context. Their points
    # report world there (the 5.1.2 rule), so they are taken into the axes
    # through the inverse, and the box is the min and max of what comes out.
    # ------------------------------------------------------------
    def self.Na__ScaleFrame__BuildLoose(model, entities)
        list = (entities || []).select { |entity| entity && entity.valid? }
        return nil if list.empty?

        world   = Na__InsertPrimatives.Na__ScaleFrame__ContextAxes(model)
        inverse = world.inverse
        local   = Na__InsertPrimatives.Na__ScaleFrame__LooseWorldPoints(list).map { |point| point.transform(inverse) }
        return nil if local.empty?

        min   = (0..2).map { |n| local.map { |point| point[n].to_f }.min }
        max   = (0..2).map { |n| local.map { |point| point[n].to_f }.max }
        frame = Na__InsertPrimatives.Na__ScaleFrame__Assemble(world, min, max)
        return nil unless frame

        context = model.active_path

        frame.merge(
            :loose       => true,
            :entities    => list,
            :context     => context,
            :instance    => nil,
            :definition  => nil,
            :path        => context || [],
            :depth       => context ? context.length : 0,
            :name        => Na__InsertPrimatives.Na__ScaleFrame__LooseName(list),
            :fingerprint => Na__InsertPrimatives.Na__ScaleFrame__LooseFingerprint(model, list)
        )
    rescue StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "NA DEEP SCALE: loose frame not built — #{error.message}"
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Every World Point That Bounds a Loose Selection
    # ------------------------------------------------------------
    # Edges and faces give their vertices. A group or component among them
    # gives the eight corners of its own box, in its own axes (its
    # transformation reads world in the open context). Anything else, a guide
    # or a text, gives the corners of its bounds.
    # ------------------------------------------------------------
    def self.Na__ScaleFrame__LooseWorldPoints(entities)
        points = []
        seen   = {}

        entities.each do |entity|
            next unless entity && entity.valid?

            if entity.is_a?(Sketchup::Edge) || entity.is_a?(Sketchup::Face)
                entity.vertices.each do |vertex|
                    next if seen[vertex.entityID]

                    seen[vertex.entityID] = true
                    points << vertex.position
                end
            elsif entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
                bounds = entity.definition.bounds
                next if bounds.nil? || bounds.empty?

                (0..7).each { |index| points << bounds.corner(index).transform(entity.transformation) }
            elsif entity.respond_to?(:bounds)
                bounds = entity.bounds
                next if bounds.nil? || bounds.empty?

                (0..7).each { |index| points << bounds.corner(index) }
            end
        end

        points
    end
    # ---------------------------------------------------------------

    # FUNCTION | What Has to Change for a Loose Frame to Be Out of Date
    # ------------------------------------------------------------
    # Asked on every mouse move, so it reads a sample, not the lot: how many
    # entities are left, the axes, and the first points of up to 48 of them
    # spread through the selection. A scale, an undo or a redo moves every
    # point, so any sample sees it.
    # ------------------------------------------------------------
    def self.Na__ScaleFrame__LooseFingerprint(model, entities)
        alive  = entities.select(&:valid?)
        step   = [alive.length / 48, 1].max
        sample = []

        alive.each_with_index do |entity, index|
            next unless (index % step).zero?

            first = Na__InsertPrimatives.Na__ScaleFrame__LooseWorldPoints([entity]).first
            sample << (first ? first.to_a.map { |value| value.to_f.round(6) } : nil)
        end

        [alive.length, Na__InsertPrimatives.Na__ScaleFrame__ContextAxes(model).to_a.map { |value| value.to_f.round(9) }, sample]
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | What to Call a Loose Selection: "Loose geometry (4 faces, 12 edges)"
    # ------------------------------------------------------------
    def self.Na__ScaleFrame__LooseName(entities)
        counts = Hash.new(0)

        entities.each do |entity|
            kind =
                if entity.is_a?(Sketchup::Face)                  then 'face'
                elsif entity.is_a?(Sketchup::Edge)               then 'edge'
                elsif entity.is_a?(Sketchup::Group)              then 'group'
                elsif entity.is_a?(Sketchup::ComponentInstance)  then 'component'
                else                                                  'other'
                end
            counts[kind] += 1
        end

        parts = %w[face edge group component other].map do |kind|
            counts[kind] > 0 ? "#{counts[kind]} #{kind}#{counts[kind] == 1 ? '' : 's'}" : nil
        end.compact

        loose = (counts['face'] + counts['edge']) > 0
        "#{loose ? 'Loose geometry' : 'Selection'} (#{parts.join(', ')})"
    end
    # ---------------------------------------------------------------

    # FUNCTION | What Has to Change for a Built Frame to Be Out of Date
    # ------------------------------------------------------------
    # The definition (a make_unique swaps it), its box (any stretch moves it),
    # its top-level entity count (an edit that leaves the box alone) and the
    # world placement (a scale, a move, an undo of either). Cheap enough to
    # ask on every mouse move: the bounds are SketchUp's own cache.
    # ------------------------------------------------------------
    def self.Na__ScaleFrame__Fingerprint(instance, path, world = nil)
        return nil unless instance && instance.valid?

        world      ||= Na__InsertPrimatives.Na__ScaleFrame__WorldTransform(path)
        definition = instance.definition
        bounds     = definition.bounds

        [
            definition.entityID,
            definition.entities.length,
            bounds.min.to_a.map { |value| value.to_f.round(6) },
            bounds.max.to_a.map { |value| value.to_f.round(6) },
            world ? world.to_a.map { |value| value.to_f.round(9) } : nil
        ]
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | What to Call the Object in the Status Bar
    # A target reached by double-clicking down is named with the object it
    # sits in, so "Glass in Sash" says which glass.
    # ------------------------------------------------------------
    def self.Na__ScaleFrame__Label(frame)
        return 'nothing' unless frame
        return frame[:name].to_s if frame[:loose]

        instances = Na__InsertPrimatives.Na__DeepPick__Instances(frame[:path])
        below     = instances.length - Na__InsertPrimatives.Na__ScaleFrame__OpenDepth
        return frame[:name].to_s unless below > 1

        "#{frame[:name]} in #{Na__InsertPrimatives.Na__DeepPick__InstanceName(instances[-2])}"
    rescue StandardError
        'object'
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Box Points
    # -----------------------------------------------------------------------------

    # FUNCTION | A Local Point Picked by Min / Mid / Max Codes (0 / 1 / 2) per Axis
    # ------------------------------------------------------------
    def self.Na__ScaleFrame__LocalPoint(frame, codes)
        values = (0..2).map do |n|
            case codes[n]
            when 0 then frame[:min][n]
            when 2 then frame[:max][n]
            else        frame[:centre][n]
            end
        end

        Geom::Point3d.new(values[0], values[1], values[2])
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Eight World Corners of a Local Box, as [near_quad, far_quad]
    # ------------------------------------------------------------
    # mins / maxs default to the frame's own box; the drag hands in the box
    # the field is about to make. Same corner order and winding as
    # Na__DeepPick__InstanceBoxQuads, so the shared box drawers take it.
    # ------------------------------------------------------------
    def self.Na__ScaleFrame__BoxQuads(frame, mins = nil, maxs = nil)
        lo = mins || frame[:min]
        hi = maxs || frame[:max]

        corners = (0..7).map do |index|
            Geom::Point3d.new(
                (index & 1).zero? ? lo[0] : hi[0],
                (index & 2).zero? ? lo[1] : hi[1],
                (index & 4).zero? ? lo[2] : hi[2]
            ).transform(frame[:world])
        end

        [
            [corners[0], corners[1], corners[3], corners[2]],
            [corners[4], corners[5], corners[7], corners[6]]
        ]
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Twelve Box Edges as World Point Pairs
    # ------------------------------------------------------------
    def self.Na__ScaleFrame__BoxEdges(frame, mins = nil, maxs = nil)
        near, far = Na__InsertPrimatives.Na__ScaleFrame__BoxQuads(frame, mins, maxs)
        edges     = []

        4.times do |index|
            following = (index + 1) % 4
            edges << [near[index], near[following]]
            edges << [far[index],  far[following]]
            edges << [near[index], far[index]]
        end

        edges
    end
    # ---------------------------------------------------------------

    # FUNCTION | Outward World Normal of the Box Face at One End of an Axis
    # ------------------------------------------------------------
    # Built from the other two world axes, not from the transformed local
    # normal: under a non-uniform scale a transformed normal is no longer
    # square to its face, and the facing test below would then be wrong
    # exactly on the objects people scale.
    # ------------------------------------------------------------
    def self.Na__ScaleFrame__FaceNormal(frame, axis_index, sign)
        dirs   = frame[:dirs]
        normal = dirs[(axis_index + 1) % 3].cross(dirs[(axis_index + 2) % 3])
        return dirs[axis_index] unless normal.length > 0.0

        normal.normalize!
        normal.reverse! if normal.dot(dirs[axis_index]) < 0.0
        sign < 0 ? normal.reverse : normal
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is a Box Face Turned Towards the Camera?
    # A face seen exactly edge-on is on the outline, not behind it, so it
    # counts as facing: in an elevation the grips round the outline are the
    # ones being looked at.
    # ------------------------------------------------------------
    def self.Na__ScaleFrame__FaceFacing?(view, frame, axis_index, sign, point)
        normal = Na__InsertPrimatives.Na__ScaleFrame__FaceNormal(frame, axis_index, sign)
        camera = view.camera

        towards =
            if camera.perspective?
                (camera.eye - point).normalize
            else
                camera.direction.reverse
            end

        normal.dot(towards) > -1e-6
    rescue StandardError
        true
    end
    # ---------------------------------------------------------------

    # FUNCTION | How Long Each Axis of the Box Looks on Screen, in Pixels
    # ------------------------------------------------------------
    # Measured through the middle of the box. An axis seen end-on — Y in a
    # front elevation — comes back near zero: there is nothing a grip can
    # show along it, which is what the grip filter needs to know.
    # ------------------------------------------------------------
    def self.Na__ScaleFrame__ScreenSpans(view, frame)
        (0..2).map do |n|
            low      = frame[:centre].dup
            high     = frame[:centre].dup
            low[n]   = frame[:min][n]
            high[n]  = frame[:max][n]
            ends     = Na__InsertPrimatives.Na__DrawnPreview__ScreenPoints(view, [
                Geom::Point3d.new(low[0], low[1], low[2]).transform(frame[:world]),
                Geom::Point3d.new(high[0], high[1], high[2]).transform(frame[:world])
            ])
            next 0.0 unless ends

            dx = ends[1].x - ends[0].x
            dy = ends[1].y - ends[0].y
            Math.sqrt((dx * dx) + (dy * dy))
        end
    rescue StandardError
        [100.0, 100.0, 100.0]
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Grips
    # -----------------------------------------------------------------------------

    # FUNCTION | Every Grip the Box Can Offer
    # ------------------------------------------------------------
    # 6 face grips scale one axis, 12 edge grips two, 8 corner grips three —
    # SketchUp's own 26. An axis the object is flat on has nothing to grip,
    # so a grip that would pull along it is left out; on a flat panel the
    # four edge grips round its rim become its corners.
    #
    # GRIP HASH:
    #   :codes  [0|1|2] per axis — min, middle, max
    #   :axes   the axes it pulls, in X Y Z order
    #   :signs  -1 / 0 / +1 per axis — which way is outward
    #   :kind   :face, :edge or :corner
    #   :local, :world
    # ------------------------------------------------------------
    def self.Na__ScaleFrame__Grips(frame)
        grips = []

        [0, 1, 2].product([0, 1, 2], [0, 1, 2]).each do |codes|
            next if codes == [1, 1, 1]

            indexes = (0..2).reject { |n| codes[n] == 1 }
            next unless indexes.all? { |n| frame[:usable][n] }

            local = Na__InsertPrimatives.Na__ScaleFrame__LocalPoint(frame, codes)

            grips << {
                :codes => codes,
                :axes  => indexes.map { |n| NA_SCALE_AXES[n] },
                :signs => codes.map { |code| code == 0 ? -1 : (code == 2 ? 1 : 0) },
                :kind  => NA_SCALE_GRIP_KINDS[indexes.length],
                :local => local,
                :world => local.transform(frame[:world])
            }
        end

        grips
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is a Grip Among the Ones the Handle Set Shows?
    # ------------------------------------------------------------
    # 'corners' means the grips that pull every axis the object has, so a flat
    # panel's Corners are the corners of the panel, not nothing at all.
    # ------------------------------------------------------------
    def self.Na__ScaleFrame__GripInSet?(frame, grip, set)
        case set.to_s
        when 'faces'
            grip[:kind] == :face
        when 'corners'
            grip[:axes].length == frame[:usable].count(true)
        when 'x', 'y', 'z'
            grip[:axes] == [set.to_sym]
        else
            true
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is a Grip on the Side of the Box Facing the Camera?
    # A grip on the far side is still offered, smaller and hollow, and loses
    # every tie to one on the near side: that is the grip people meant.
    # ------------------------------------------------------------
    def self.Na__ScaleFrame__GripFacing?(view, frame, grip)
        (0..2).any? do |n|
            sign = grip[:signs][n]
            next false if sign.zero?

            Na__InsertPrimatives.Na__ScaleFrame__FaceFacing?(view, frame, n, sign, grip[:world])
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Point a Grip Is Pulled Away From
    # ------------------------------------------------------------
    # The opposite grip, or the middle of the box About Centre. On an axis the
    # grip does not pull the anchor sits in the middle, which is where a
    # uniform scale from a face grip should leave the other two axes.
    # ------------------------------------------------------------
    def self.Na__ScaleFrame__AnchorLocal(frame, grip, about_centre)
        codes = grip[:codes].map do |code|
            next 1 if about_centre || code == 1

            code == 0 ? 2 : 0
        end

        Na__InsertPrimatives.Na__ScaleFrame__LocalPoint(frame, codes)
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Ghost of the Object's Edges
    # -----------------------------------------------------------------------------

    # FUNCTION | Is an Entity Drawn at All?
    # ------------------------------------------------------------
    def self.Na__ScaleFrame__Visible?(entity)
        return false if entity.hidden?

        layer = entity.respond_to?(:layer) ? entity.layer : nil
        layer.nil? || layer.visible?
    rescue StandardError
        true
    end
    # ---------------------------------------------------------------

    # FUNCTION | Every Visible Edge of the Object, Flattened Into Its Own Axes
    # ------------------------------------------------------------
    # Read once when a drag starts and reused for every frame of it: the
    # preview maps these points through the field and draws them, and the
    # stretch limit reads where they sit either side of each plane.
    #
    # Points are shared between the edges that meet at them, keyed by the
    # vertex AND the chain of instances it was reached through, because one
    # definition placed twice is two sets of points in the object.
    #
    # Soft edges are left out of the drawing (they are the facets of a curved
    # surface and would turn the ghost into fur), and so are hidden edges and
    # hidden instances. They still MOVE, though, so their points are kept in
    # :extra, which only the stretch limit reads.
    #
    # Returns { :points, :segments, :extra, :count, :drawable }. :drawable is
    # false when there are more points than a frame can afford to project.
    # ------------------------------------------------------------
    def self.Na__ScaleFrame__CollectGhost(definition)
        state = { :points => [], :index => {}, :segments => [], :extra => [], :truncated => false }

        Na__InsertPrimatives.Na__ScaleFrame__GhostWalk(
            definition.entities, Geom::Transformation.new, '', 0, true, state
        )

        {
            :points    => state[:points],
            :segments  => state[:segments],
            :extra     => state[:extra],
            :count     => state[:points].length,
            :truncated => state[:truncated],
            :drawable  => !state[:truncated] && state[:points].length <= NA_SCALE_GHOST_DRAW_MAX
        }
    rescue StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "NA DEEP SCALE: ghost not collected — #{error.message}"
        { :points => [], :segments => [], :extra => [], :count => 0, :truncated => true, :drawable => false }
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Ghost of a Loose Selection, in the Box's Axes
    # ------------------------------------------------------------
    # The same walk, over the selection itself: its edges (a selected face
    # brings its own), and any group or component in it whole. Their points
    # report world in the open context, so the walk starts from the box's
    # inverse rather than from the identity.
    # ------------------------------------------------------------
    def self.Na__ScaleFrame__CollectGhostLoose(frame)
        state = { :points => [], :index => {}, :segments => [], :extra => [], :truncated => false }
        seen  = {}
        list  = []

        frame[:entities].each do |entity|
            next unless entity.valid?

            if entity.is_a?(Sketchup::Face)
                entity.edges.each { |edge| list << edge unless seen[edge.entityID]; seen[edge.entityID] = true }
            elsif !seen[entity.entityID]
                seen[entity.entityID] = true
                list << entity
            end
        end

        Na__InsertPrimatives.Na__ScaleFrame__GhostWalk(list, frame[:inverse], '', 0, true, state)

        {
            :points    => state[:points],
            :segments  => state[:segments],
            :extra     => state[:extra],
            :count     => state[:points].length,
            :truncated => state[:truncated],
            :drawable  => !state[:truncated] && state[:points].length <= NA_SCALE_GHOST_DRAW_MAX
        }
    rescue StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "NA DEEP SCALE: loose ghost not collected — #{error.message}"
        { :points => [], :segments => [], :extra => [], :count => 0, :truncated => true, :drawable => false }
    end
    # ---------------------------------------------------------------

    # FUNCTION | One Level of the Ghost Walk
    # shown is false below a hidden instance: everything there is :extra.
    # ------------------------------------------------------------
    def self.Na__ScaleFrame__GhostWalk(entities, xform, chain, depth, shown, state)
        entities.each do |entity|
            return if state[:truncated]

            if entity.is_a?(Sketchup::Edge)
                if shown && !entity.soft? && Na__InsertPrimatives.Na__ScaleFrame__Visible?(entity)
                    first  = Na__InsertPrimatives.Na__ScaleFrame__GhostPoint(entity.start, xform, chain, state)
                    second = Na__InsertPrimatives.Na__ScaleFrame__GhostPoint(entity.end,   xform, chain, state)
                    state[:segments] << first << second
                else
                    state[:extra] << entity.start.position.transform(xform) << entity.end.position.transform(xform)
                end

                state[:truncated] = true if state[:points].length + state[:extra].length > NA_SCALE_GHOST_SCAN_MAX

            elsif entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
                next if depth >= NA_SCALE_GHOST_MAX_DEPTH

                Na__InsertPrimatives.Na__ScaleFrame__GhostWalk(
                    entity.definition.entities,
                    xform * entity.transformation,
                    "#{chain}/#{entity.entityID}",
                    depth + 1,
                    shown && Na__InsertPrimatives.Na__ScaleFrame__Visible?(entity),
                    state
                )
            end
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Index of One Vertex in the Ghost, Adding It the First Time
    # ------------------------------------------------------------
    def self.Na__ScaleFrame__GhostPoint(vertex, xform, chain, state)
        key   = "#{chain}:#{vertex.entityID}"
        found = state[:index][key]
        return found if found

        state[:points] << vertex.position.transform(xform)
        state[:index][key] = state[:points].length - 1
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP SCALE FRAME
# =============================================================================
