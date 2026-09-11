# =============================================================================
# NA NOBLE3D MODELLING TOOLS - GROUP / COMPONENT CONVERTER - SHAPE MATCHER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__GroupComponentConverter__ShapeMatcher__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__GroupComponentConverter__ShapeMatcher
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Decide whether two groups hold the same geometry however they
#              are moved or rotated, and find the rigid move between them, so
#              common groups can become instances of one shared component
# CREATED    : 2026
#
# WHY NOT SELECT SIMILAR'S TEST ALONE:
# - Select Similar compares sorted, scale-adjusted local bounding boxes. That
#   is right for choosing what to select, but two groups can share a bounding
#   box with different geometry inside, and it gives no rotation. Replacing a
#   group with another group's component needs both: proof of identical
#   geometry, and the exact move that puts the component where the group was.
#
# METHOD:
# 1. Record   - per definition, read once: vertices (with edge counts), edge
#               midpoints, face centroids / normals / areas, and nested
#               placements, plus a key that ignores position and rotation
#               (counts, total area, edge length, spread about the centroid,
#               material and tag tallies, nested keys).
# 2. Bucket   - only records with equal keys are compared.
# 3. Register - try the pure translation between centroids first (same
#               orientation, the common case). Otherwise build a frame from
#               the centroid, the rarest far vertex and the rarest off-axis
#               vertex (rarity by distance and edge count), and try every
#               candidate frame in the other group.
# 4. Verify   - a candidate move must land every vertex, edge midpoint, face
#               (normal, area, materials, tag, hidden) and nested placement on
#               its counterpart within 0.002" (about 0.05 mm). Counts are
#               equal from the key, so a full landing is a one-to-one match.
#
# Only proper rotations are produced, so a mirrored copy of a chiral shape
# never merges. A shape with a mirror plane is congruent to its mirror image
# by a rotation, so that one merges correctly.
#
# Records hold plain values only - points, vectors, transformations, ids - so
# a template stays comparable after its own definition has been converted.
# Prototype: 61 synthetic checks (rotations, mirrors, symmetric boxes, a UV
# sphere, a 60 x 60 grid, nested-only and single-edge groups) before the port.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__GroupComponentConverter__ShapeMatcher

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_POSITION_TOLERANCE      = 0.002
        NA_GRID_CELL               = 0.008
        NA_MIN_ANCHOR_DISTANCE     = 0.02
        NA_NORMAL_TOLERANCE        = 1.0e-6
        NA_MATRIX_TOLERANCE        = 1.0e-6
        NA_AREA_RATIO_TOLERANCE    = 1.0e-4
        NA_AXIS_TIP_LENGTH         = 1.0
        NA_MAX_NESTED_RECORD_DEPTH = 4
        NA_MAX_FRAMES              = 512
        NA_TRANSLATION_INDICES     = [12, 13, 14].freeze
        NA_NESTED_ORIGIN_LABEL     = -1
        NA_NESTED_X_TIP_LABEL      = -2
        NA_NESTED_Y_TIP_LABEL      = -3

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Matching API
# -----------------------------------------------------------------------------

        # FUNCTION | Work Counter That Caps a Preview's Matching Effort
        # ------------------------------------------------------------
        # @param limit [Integer, nil] Units of work allowed; nil is unlimited
        # ------------------------------------------------------------
        def self.Na__GroupComponentConverter__ShapeMatcher__NewWork(limit)
            { units: 0, limit: limit, exhausted: false }
        end
        # ------------------------------------------------------------

        # FUNCTION | Shape Record for a Definition, Built Once Per Run
        # ------------------------------------------------------------
        # @param definition [Sketchup::ComponentDefinition]
        # @param cache      [Hash] Records by definition entityID
        # @param work       [Hash] From NewWork
        # @param depth      [Integer] Nested record depth
        # @return [Hash, nil] nil when unreadable or the work cap is hit
        # ------------------------------------------------------------
        def self.Na__GroupComponentConverter__ShapeMatcher__Record(definition, cache, work, depth = 0)
            return nil unless definition && definition.valid?

            definition_id = definition.entityID
            return cache[definition_id] if cache.key?(definition_id)
            return nil if work[:exhausted]

            record = na_build_record(definition, cache, work, depth)
            cache[definition_id] = record if record
            record
        rescue => error
            puts "[Na__GroupComponentConverter] Shape record warning: #{error.class}: #{error.message}"
            cache[definition_id] = nil if definition_id
            nil
        end
        # ------------------------------------------------------------

        # FUNCTION | Rigid Move Placing the Template's Geometry Onto the Member's
        # ------------------------------------------------------------
        # @param template [Hash] Record of the group that owns the component
        # @param member   [Hash] Record of the group that would join it
        # @param work     [Hash] From NewWork
        # @return [Geom::Transformation, nil] Offset in local space, so the
        #         member's instance goes at member.transformation * offset
        # ------------------------------------------------------------
        def self.Na__GroupComponentConverter__ShapeMatcher__Register(template, member, work)
            return nil unless template && member
            return Geom::Transformation.new if template[:definition_id] == member[:definition_id]
            return nil unless template[:key] == member[:key]
            return nil if work[:exhausted]

            shift = Geom::Transformation.translation(member[:centroid] - template[:centroid])
            return shift if na_verify(template, member, shift, work)

            na_register_by_anchors(template, member, work)
        rescue => error
            puts "[Na__GroupComponentConverter] Shape registration warning: #{error.class}: #{error.message}"
            nil
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Record Building
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Read One Definition Into a Plain-Value Record
        # ------------------------------------------------------------
        def self.na_build_record(definition, cache, work, depth)
            parts = {
                vertex_points: {},
                vertex_degree: {},
                faces:         [],
                edges:         [],
                nested:        [],
                area_total:    0.0,
                edge_total:    0.0,
                face_styles:   Hash.new(0),
                edge_styles:   Hash.new(0)
            }

            definition.entities.each do |entity|
                return nil unless na_spend(work, 1)

                na_read_entity(entity, parts, cache, work, depth)
            end
            return nil if work[:exhausted]

            na_finish_record(definition.entityID, parts)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Add One Entity to the Record Being Built
        # ------------------------------------------------------------
        def self.na_read_entity(entity, parts, cache, work, depth)
            case entity
            when Sketchup::Face
                face_entry = na_face_entry(entity)
                parts[:faces] << face_entry
                parts[:area_total] += face_entry[:area]
                parts[:face_styles][face_entry[:style]] += 1
            when Sketchup::Edge
                edge_entry = na_edge_entry(entity, parts[:vertex_points], parts[:vertex_degree])
                parts[:edges] << edge_entry
                parts[:edge_total] += edge_entry[:length]
                parts[:edge_styles][edge_entry[:flags]] += 1
            when Sketchup::Group, Sketchup::ComponentInstance
                parts[:nested] << na_nested_entry(entity, cache, work, depth)
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Centroid, Anchor Cloud and Position-Free Key
        # ------------------------------------------------------------
        # The cloud is every vertex plus three points per nested placement
        # (origin and two axis tips), so a group holding only components
        # still has a frame to register against.
        # ------------------------------------------------------------
        def self.na_finish_record(definition_id, parts)
            vertices = []
            labels   = []
            parts[:vertex_points].each do |vertex_id, point|
                vertices << point
                labels << parts[:vertex_degree][vertex_id]
            end

            cloud = vertices.dup
            parts[:nested].each do |entry|
                cloud.push(entry[:point], entry[:x_tip], entry[:y_tip])
                labels.push(NA_NESTED_ORIGIN_LABEL, NA_NESTED_X_TIP_LABEL, NA_NESTED_Y_TIP_LABEL)
            end

            centroid  = cloud.empty? ? Geom::Point3d.new(0, 0, 0) : na_average_point(cloud)
            distances = cloud.map { |point| point.distance(centroid).to_f }

            {
                definition_id: definition_id,
                key:           na_record_key(vertices, distances, parts),
                vertices:      vertices,
                edges:         parts[:edges],
                faces:         parts[:faces],
                nested:        parts[:nested],
                cloud:         cloud,
                labels:        labels,
                centroid:      centroid,
                distances:     distances
            }
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Key That Ignores Position and Rotation
        # ------------------------------------------------------------
        def self.na_record_key(vertices, distances, parts)
            nested_keys = parts[:nested].map { |entry| "#{entry[:key]}~#{entry[:style]}" }.sort

            [
                "v#{vertices.length}",
                "e#{parts[:edges].length}",
                "f#{parts[:faces].length}",
                "n#{parts[:nested].length}",
                parts[:area_total].round(2),
                parts[:edge_total].round(3),
                distances.sum.round(2),
                na_tally_key(parts[:face_styles]),
                na_tally_key(parts[:edge_styles]),
                nested_keys.join(',')
            ].join('|').hash
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Centroid, Normal, Area and Paint of One Face
        # ------------------------------------------------------------
        def self.na_face_entry(face)
            {
                point:  na_average_point(face.outer_loop.vertices.map(&:position)),
                normal: face.normal,
                area:   face.area.to_f,
                style:  "#{na_id(face.material)}/#{na_id(face.back_material)}/#{na_id(face.layer)}/#{face.hidden? ? 1 : 0}"
            }
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Midpoint, Length and Display Flags of One Edge
        # ------------------------------------------------------------
        def self.na_edge_entry(edge, vertex_points, vertex_degree)
            start_point = na_remember_vertex(edge.start, vertex_points, vertex_degree)
            end_point   = na_remember_vertex(edge.end, vertex_points, vertex_degree)

            {
                point:  Geom.linear_combination(0.5, start_point, 0.5, end_point),
                length: edge.length.to_f,
                flags:  "#{edge.soft? ? 1 : 0}#{edge.smooth? ? 1 : 0}#{edge.hidden? ? 1 : 0}/" \
                        "#{na_id(edge.layer)}/#{na_id(edge.material)}"
            }
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Remember a Vertex Once, With Its Edge Count
        # ------------------------------------------------------------
        def self.na_remember_vertex(vertex, vertex_points, vertex_degree)
            vertex_id = vertex.entityID
            vertex_points[vertex_id] ||= vertex.position
            vertex_degree[vertex_id] ||= vertex.edges.length
            vertex_points[vertex_id]
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Placement, Paint and Equivalence Key of a Nested Container
        # ------------------------------------------------------------
        def self.na_nested_entry(instance, cache, work, depth)
            transformation = instance.transformation
            definition     = instance.definition
            nested_record  = nil
            if depth < NA_MAX_NESTED_RECORD_DEPTH
                nested_record = self.Na__GroupComponentConverter__ShapeMatcher__Record(definition, cache, work, depth + 1)
            end

            {
                point:          transformation.origin,
                x_tip:          transformation * Geom::Point3d.new(NA_AXIS_TIP_LENGTH, 0, 0),
                y_tip:          transformation * Geom::Point3d.new(0, NA_AXIS_TIP_LENGTH, 0),
                transformation: transformation,
                definition_id:  definition.entityID,
                key:            nested_record ? nested_record[:key] : "definition:#{definition.entityID}",
                record:         nested_record,
                style:          "#{na_id(instance.material)}/#{na_id(instance.layer)}/#{instance.hidden? ? 1 : 0}"
            }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Registration
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Try Every Candidate Frame in the Member
        # ------------------------------------------------------------
        def self.na_register_by_anchors(template, member, work)
            anchor = na_anchor(template)
            return nil if anchor[:degenerate]

            template_inverse = anchor[:frame].inverse
            frames_tried = 0

            na_indices_at_distance(member, anchor[:f_distance]).each do |f_index|
                next unless member[:labels][f_index] == anchor[:f_label]

                f_point = member[:cloud][f_index]
                if anchor[:collinear]
                    frame = na_collinear_frame(member[:centroid], f_point)
                    next unless frame

                    offset = frame * template_inverse
                    return offset if na_verify(template, member, offset, work)

                    next
                end

                na_indices_at_distance(member, anchor[:h_distance]).each do |h_index|
                    next if h_index == f_index
                    next unless member[:labels][h_index] == anchor[:h_label]

                    h_point = member[:cloud][h_index]
                    next unless (h_point.distance(f_point).to_f - anchor[:h_to_f]).abs <= NA_POSITION_TOLERANCE

                    frames_tried += 1
                    return nil if frames_tried > NA_MAX_FRAMES || work[:exhausted]

                    frame = na_frame(member[:centroid], f_point, h_point)
                    next unless frame

                    offset = frame * template_inverse
                    return offset if na_verify(template, member, offset, work)
                end
            end

            nil
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Anchor Frame of a Template, Worked Out Once
        # ------------------------------------------------------------
        def self.na_anchor(record)
            record[:anchor] ||= na_compute_anchor(record)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Centroid, Rarest Far Point, Rarest Off-Axis Point
        # ------------------------------------------------------------
        # Rarity is counted per class of distance and edge count, so a
        # symmetric shape still anchors on a point with few look-alikes
        # (the poles of a sphere, the corners of a grid).
        # ------------------------------------------------------------
        def self.na_compute_anchor(record)
            cloud     = record[:cloud]
            centroid  = record[:centroid]
            distances = record[:distances]
            labels    = record[:labels]

            far_indices = cloud.each_index.select { |index| distances[index] > NA_MIN_ANCHOR_DISTANCE }
            return { degenerate: true } if far_indices.empty?

            f_index = na_pick_rarest(far_indices, distances) { |index| [na_cell(distances[index]), labels[index]] }
            f_point = cloud[f_index]

            line_distances = {}
            cloud.each_index do |index|
                line_distance = na_distance_from_line(cloud[index], centroid, f_point)
                line_distances[index] = line_distance if line_distance > NA_MIN_ANCHOR_DISTANCE
            end

            if line_distances.empty?
                frame = na_collinear_frame(centroid, f_point)
                return { degenerate: frame.nil?, collinear: true, frame: frame,
                         f_distance: distances[f_index], f_label: labels[f_index] }
            end

            h_index = na_pick_rarest(line_distances.keys, line_distances) do |index|
                [na_cell(distances[index]), na_cell(cloud[index].distance(f_point).to_f), labels[index]]
            end
            h_point = cloud[h_index]

            {
                degenerate: false,
                collinear:  false,
                frame:      na_frame(centroid, f_point, h_point),
                f_distance: distances[f_index],
                f_label:    labels[f_index],
                h_distance: distances[h_index],
                h_label:    labels[h_index],
                h_to_f:     h_point.distance(f_point).to_f
            }
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Index From the Smallest Class, Highest Score on Ties
        # ------------------------------------------------------------
        def self.na_pick_rarest(indices, scores)
            classes = {}
            indices.each do |index|
                (classes[yield(index)] ||= []) << index
            end

            smallest = classes.values.min_by do |members|
                [members.length, -members.map { |index| scores[index] }.max]
            end
            smallest.max_by { |index| scores[index] }
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Right-Handed Frame at the Centroid From Two Anchors
        # ------------------------------------------------------------
        def self.na_frame(origin, f_point, h_point)
            x_axis = f_point - origin
            return nil if x_axis.length.to_f <= 1.0e-9

            x_axis.normalize!
            offset = h_point - origin
            along  = offset.dot(x_axis)
            y_axis = Geom::Vector3d.new(
                offset.x - (x_axis.x * along),
                offset.y - (x_axis.y * along),
                offset.z - (x_axis.z * along)
            )
            return nil if y_axis.length.to_f <= 1.0e-9

            y_axis.normalize!
            Geom::Transformation.axes(origin, x_axis, y_axis, x_axis.cross(y_axis))
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Frame for Geometry That Lies on One Line
        # ------------------------------------------------------------
        def self.na_collinear_frame(origin, f_point)
            x_axis = f_point - origin
            return nil if x_axis.length.to_f <= 1.0e-9

            x_axis.normalize!
            helper = x_axis.z.abs < 0.9 ? Geom::Vector3d.new(0, 0, 1) : Geom::Vector3d.new(1, 0, 0)
            y_axis = helper.cross(x_axis)
            y_axis.normalize!
            Geom::Transformation.axes(origin, x_axis, y_axis, x_axis.cross(y_axis))
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Verification
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | True When the Move Lands the Whole Template on the Member
        # ------------------------------------------------------------
        def self.na_verify(template, member, offset, work)
            grids = na_member_grids(member)

            na_verify_vertices(template, grids[:vertices], offset, work) &&
                na_verify_edges(template, grids[:edges], offset, work) &&
                na_verify_faces(template, grids[:faces], offset, work) &&
                na_verify_nested(template, grids[:nested], offset, work)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Every Vertex Lands on a Vertex
        # ------------------------------------------------------------
        def self.na_verify_vertices(template, grid, offset, work)
            template[:vertices].all? do |point|
                return false unless na_spend(work, 1)

                target = offset * point
                na_grid_find(grid, target) { |candidate| candidate.distance(target) <= NA_POSITION_TOLERANCE }
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Every Edge Lands on an Edge of the Same Length and Flags
        # ------------------------------------------------------------
        def self.na_verify_edges(template, grid, offset, work)
            template[:edges].all? do |edge|
                return false unless na_spend(work, 1)

                target = offset * edge[:point]
                na_grid_find(grid, target) do |candidate|
                    candidate[:flags] == edge[:flags] &&
                        (candidate[:length] - edge[:length]).abs <= NA_POSITION_TOLERANCE &&
                        candidate[:point].distance(target) <= NA_POSITION_TOLERANCE
                end
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Every Face Lands on a Face Facing the Same Way, Painted the Same
        # ------------------------------------------------------------
        def self.na_verify_faces(template, grid, offset, work)
            template[:faces].all? do |face|
                return false unless na_spend(work, 1)

                target = offset * face[:point]
                normal = offset * face[:normal]
                na_grid_find(grid, target) do |candidate|
                    candidate[:style] == face[:style] &&
                        candidate[:point].distance(target) <= NA_POSITION_TOLERANCE &&
                        candidate[:normal].dot(normal) >= 1.0 - NA_NORMAL_TOLERANCE &&
                        na_areas_match?(candidate[:area], face[:area])
                end
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Every Nested Placement Lands on an Equivalent Placement
        # ------------------------------------------------------------
        def self.na_verify_nested(template, grid, offset, work)
            template[:nested].all? do |entry|
                return false unless na_spend(work, 1)

                expected = offset * entry[:transformation]
                na_grid_find(grid, expected.origin) do |candidate|
                    candidate[:style] == entry[:style] &&
                        na_matrices_close?(expected, candidate[:transformation]) &&
                        na_nested_equivalent?(entry, candidate, work)
                end
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Same Definition, or Identical Geometry In Place
        # ------------------------------------------------------------
        def self.na_nested_equivalent?(template_entry, member_entry, work)
            return true if template_entry[:definition_id] == member_entry[:definition_id]
            return false unless template_entry[:key] == member_entry[:key]
            return false unless template_entry[:record] && member_entry[:record]

            na_verify(template_entry[:record], member_entry[:record], Geom::Transformation.new, work)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Two Transformations Within Tolerance, Entry by Entry
        # ------------------------------------------------------------
        def self.na_matrices_close?(first, second)
            first_values  = first.to_a
            second_values = second.to_a

            first_values.each_index.all? do |index|
                tolerance = NA_TRANSLATION_INDICES.include?(index) ? NA_POSITION_TOLERANCE : NA_MATRIX_TOLERANCE
                (first_values[index] - second_values[index]).abs <= tolerance
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Face Areas Equal Within a Relative Tolerance
        # ------------------------------------------------------------
        def self.na_areas_match?(first_area, second_area)
            (first_area - second_area).abs <= (NA_AREA_RATIO_TOLERANCE * [first_area, second_area].max) + 1.0e-9
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Spatial Lookup
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Grids Over a Member's Points, Built on First Use
        # ------------------------------------------------------------
        def self.na_member_grids(record)
            record[:grids] ||= {
                vertices: na_build_grid(record[:vertices]) { |point| point },
                edges:    na_build_grid(record[:edges])    { |edge| edge[:point] },
                faces:    na_build_grid(record[:faces])    { |face| face[:point] },
                nested:   na_build_grid(record[:nested])   { |entry| entry[:point] }
            }
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Bucket Items by the Grid Cell of Their Point
        # ------------------------------------------------------------
        def self.na_build_grid(items)
            grid = {}
            items.each do |item|
                (grid[na_grid_key(yield(item))] ||= []) << item
            end
            grid
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | First Item Near a Point That Passes the Block
        # ------------------------------------------------------------
        # A point within tolerance sits in the same cell or a neighbour,
        # because a cell is four tolerances wide.
        # ------------------------------------------------------------
        def self.na_grid_find(grid, point)
            key = na_grid_key(point)
            bucket = grid[key]
            if bucket
                hit = bucket.find { |item| yield(item) }
                return hit if hit
            end

            x_key, y_key, z_key = key
            (-1..1).each do |dx|
                (-1..1).each do |dy|
                    (-1..1).each do |dz|
                        next if dx.zero? && dy.zero? && dz.zero?

                        neighbour = grid[[x_key + dx, y_key + dy, z_key + dz]]
                        next unless neighbour

                        hit = neighbour.find { |item| yield(item) }
                        return hit if hit
                    end
                end
            end

            nil
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Grid Cell of a Point
        # ------------------------------------------------------------
        def self.na_grid_key(point)
            [na_cell(point.x.to_f), na_cell(point.y.to_f), na_cell(point.z.to_f)]
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Cloud Indices at a Distance From the Member's Centroid
        # ------------------------------------------------------------
        def self.na_indices_at_distance(record, distance)
            index = record[:distance_index] ||= na_build_distance_index(record[:distances])
            cell = na_cell(distance)
            found = []

            ((cell - 1)..(cell + 1)).each do |key|
                (index[key] || []).each do |cloud_index|
                    found << cloud_index if (record[:distances][cloud_index] - distance).abs <= NA_POSITION_TOLERANCE
                end
            end

            found
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Cloud Indices Bucketed by Distance Cell
        # ------------------------------------------------------------
        def self.na_build_distance_index(distances)
            index = {}
            distances.each_with_index do |distance, cloud_index|
                (index[na_cell(distance)] ||= []) << cloud_index
            end
            index
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Spend Work Units, False Once the Cap Is Passed
        # ------------------------------------------------------------
        def self.na_spend(work, amount)
            work[:units] += amount
            limit = work[:limit]
            work[:exhausted] = true if limit && work[:units] > limit
            !work[:exhausted]
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Grid Cell Index of a Length
        # ------------------------------------------------------------
        def self.na_cell(value)
            (value / NA_GRID_CELL).round
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Distance From a Point to the Line Through Two Points
        # ------------------------------------------------------------
        def self.na_distance_from_line(point, origin, through_point)
            axis = through_point - origin
            axis_length = axis.length.to_f
            return 0.0 if axis_length <= 1.0e-9

            offset = point - origin
            along = offset.dot(axis) / axis_length
            squared = (offset.length.to_f**2) - (along**2)
            squared > 0.0 ? Math.sqrt(squared) : 0.0
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Average of a List of Points
        # ------------------------------------------------------------
        def self.na_average_point(points)
            sum_x = 0.0
            sum_y = 0.0
            sum_z = 0.0
            points.each do |point|
                sum_x += point.x.to_f
                sum_y += point.y.to_f
                sum_z += point.z.to_f
            end

            count = points.length.to_f
            Geom::Point3d.new(sum_x / count, sum_y / count, sum_z / count)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Stable Text for a Count Tally
        # ------------------------------------------------------------
        def self.na_tally_key(tally_hash)
            tally_hash.map { |key, count| "#{key}x#{count}" }.sort.join(',')
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | entityID of an Optional Entity, 0 When Absent
        # ------------------------------------------------------------
        def self.na_id(entity)
            return 0 unless entity && entity.respond_to?(:entityID)

            entity.entityID
        rescue
            0
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__GroupComponentConverter__ShapeMatcher
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
