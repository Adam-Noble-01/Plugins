# =============================================================================
# NA INSERT PRIMATIVES - DEEP NESTED FACE PICKING
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnDeepPick__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Pick a face at any nesting depth, with the transformation maths
#              needed to push it without entering its group or component
# CREATED    : 2026
#
# DESCRIPTION:
# - Native Push/Pull only sees faces in the current editing context: to reach a
#   face inside a group you must double-click your way in first. PickHelper's
#   leaf_at / transformation_at pair hands back the deepest face under the
#   cursor together with the accumulated transformation to world space, which is
#   all that is needed to work on it in place.
#
# THE TWO COORDINATE SPACES:
# - A face lives in its own definition's local space. Its normal, its vertices
#   and the distance argument to pushpull are all local. The cursor and every
#   preview are world. transformation_at bridges the two.
# - A scaled instance makes those two disagree on distance. Transforming the
#   unit local normal gives a vector whose LENGTH is the scale factor along that
#   direction, so a world push distance divided by it is the local distance
#   pushpull actually wants. Skip that and a push inside a scaled component
#   overshoots by exactly the scale factor.
#
# EDITING IN PLACE IS SHARED EDITING:
# - Pushing a face inside a definition used more than once changes every
#   instance. That is correct SketchUp behaviour and not something to silently
#   work around, so the instance count is reported and the caller warns.
#
# =============================================================================

require 'sketchup.rb'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Picking Constants
    # -----------------------------------------------------------------------------

    NA_DEEP_PICK_MAX_PATHS = 32                                               # <-- Depth guard on a crowded pick

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Face Picking
    # -----------------------------------------------------------------------------

    # FUNCTION | Find the Deepest Face Under the Cursor
    # Returns a hash carrying the face, its instance path, the transformation to
    # world space and the scale factor along its normal — or nil when the cursor
    # is not over a face.
    # ------------------------------------------------------------
    def self.Na__DeepPick__FaceAt(view, x, y)
        helper = view.pick_helper
        helper.do_pick(x, y)

        count = helper.count
        return nil if count.nil? || count.zero?

        limit = count < NA_DEEP_PICK_MAX_PATHS ? count : NA_DEEP_PICK_MAX_PATHS
        index = 0

        while index < limit
            leaf = helper.leaf_at(index)

            if leaf.is_a?(Sketchup::Face)
                return Na__InsertPrimatives.Na__DeepPick__BuildTarget(
                    leaf, helper.path_at(index), helper.transformation_at(index)
                )
            end

            index += 1
        end

        nil
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Assemble Everything the Push Tool Needs About a Face
    # ------------------------------------------------------------
    def self.Na__DeepPick__BuildTarget(face, path, transformation)
        xform        = transformation || Geom::Transformation.new
        world_normal = face.normal.transform(xform)
        scale        = world_normal.length.to_f
        scale        = 1.0 if scale <= 0.0

        {
            :face           => face,
            :path           => path,
            :transformation => xform,
            :world_normal   => world_normal.normalize,
            :normal_scale   => scale,                                         # <-- World distance / this = local distance
            :locked         => Na__InsertPrimatives.Na__DeepPick__PathLocked?(path),
            :depth          => Na__InsertPrimatives.Na__DeepPick__NestingDepth(path),
            :shared_count   => Na__InsertPrimatives.Na__DeepPick__SharedInstanceCount(path)
        }
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Path Inspection
    # -----------------------------------------------------------------------------

    # FUNCTION | Instances Along a Pick Path, Outermost First
    # ------------------------------------------------------------
    def self.Na__DeepPick__Instances(path)
        return [] unless path.is_a?(Array)

        path.select do |entity|
            entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | How Many Groups or Components Deep the Face Sits
    # ------------------------------------------------------------
    def self.Na__DeepPick__NestingDepth(path)
        Na__InsertPrimatives.Na__DeepPick__Instances(path).length
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is Anything on the Path Locked?
    # ------------------------------------------------------------
    def self.Na__DeepPick__PathLocked?(path)
        Na__InsertPrimatives.Na__DeepPick__Instances(path).any? do |instance|
            instance.respond_to?(:locked?) && instance.locked?
        end
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | How Many Instances Share the Definition Being Edited
    # More than one means a push here changes every copy in the model.
    # ------------------------------------------------------------
    def self.Na__DeepPick__SharedInstanceCount(path)
        innermost = Na__InsertPrimatives.Na__DeepPick__Instances(path).last
        return 1 unless innermost && innermost.respond_to?(:definition)

        definition = innermost.definition
        return 1 unless definition

        count = definition.instances.length
        count < 1 ? 1 : count
    rescue StandardError
        1
    end
    # ---------------------------------------------------------------

    # FUNCTION | Force Every Definition on the Path to Re-Measure Itself
    # A definition caches its bounding box, and editing its entities from OUTSIDE
    # the editing context does not always dirty that cache. The push then really
    # has happened — the model holds the new geometry and will happily pick it —
    # but the viewport keeps drawing the old shape until something else forces a
    # rebuild. That is the "nothing happened, then a second later it did, and
    # meanwhile I could select invisible faces" behaviour.
    #
    # Innermost first, because an outer definition's bounds depend on the inner
    # ones having been recomputed already.
    # ------------------------------------------------------------
    def self.Na__DeepPick__InvalidateDefinitions(path)
        instances = Na__InsertPrimatives.Na__DeepPick__Instances(path).reverse

        instances.each do |instance|
            next unless instance.respond_to?(:definition)

            definition = instance.definition
            next unless definition && definition.respond_to?(:invalidate_bounds)

            definition.invalidate_bounds
        end

        instances.length
    rescue StandardError
        0
    end
    # ---------------------------------------------------------------

    # FUNCTION | Readable Description of Where the Face Lives
    # ------------------------------------------------------------
    def self.Na__DeepPick__PathLabel(target)
        return 'model' unless target

        depth = target[:depth].to_i
        return 'model context' if depth.zero?

        instances = Na__InsertPrimatives.Na__DeepPick__Instances(target[:path])
        innermost = instances.last
        name      = ''

        begin
            name = innermost.name.to_s
            name = innermost.definition.name.to_s if name.empty? && innermost.respond_to?(:definition)
        rescue StandardError
            name = ''
        end

        label = name.empty? ? 'unnamed' : name
        "#{label} (#{depth} deep)"
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Geometry Extraction
    # -----------------------------------------------------------------------------

    # FUNCTION | Triangles of a Face in World Space
    # Taken from the face's own PolygonMesh rather than its outer loop, so holes
    # and concave outlines shade correctly instead of being filled over.
    # ------------------------------------------------------------
    def self.Na__DeepPick__WorldTriangles(face, xform)
        return [] unless face && face.valid?

        mesh      = face.mesh
        triangles = []

        mesh.polygons.each do |polygon|
            next unless polygon.length == 3

            points = polygon.map { |index| mesh.point_at(index.abs).transform(xform) }
            triangles << points
        end

        triangles
    rescue StandardError
        []
    end
    # ---------------------------------------------------------------

    # FUNCTION | Outer Loop of a Face in World Space
    # ------------------------------------------------------------
    def self.Na__DeepPick__WorldOuterLoop(face, xform)
        return [] unless face && face.valid?

        face.outer_loop.vertices.map { |vertex| vertex.position.transform(xform) }
    rescue StandardError
        []
    end
    # ---------------------------------------------------------------

    # FUNCTION | Area of a Face in World Square Metres
    # ------------------------------------------------------------
    def self.Na__DeepPick__WorldAreaM2(face, xform)
        return '0.00' unless face && face.valid?

        area_mm2 = face.area(xform) * NA_DRAWN_INCH_TO_MM * NA_DRAWN_INCH_TO_MM
        format('%.2f', area_mm2 / 1_000_000.0)
    rescue StandardError
        '0.00'
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP NESTED FACE PICKING MODULE
# =============================================================================
