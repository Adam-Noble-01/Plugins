# =============================================================================
# NA SKETCHUP MCP - BRIDGE HELPERS - TRANSPLANT (A SOLID KEEPS ITS ID THROUGH A BOOLEAN)
# =============================================================================
#
# FILE       : Na__SketchUpMcp__BridgeHelpers__Transplant__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Transplant
# PURPOSE    : Put a boolean result's geometry back into the ORIGINAL group, so
#              its persistent id, name, tag, material, attributes and axes
#              survive (solid_boolean keep_id, 1.0.41)
# CREATED    : 25-Nov-2026
#
# WHY:
# SketchUp's solid tools always return a NEW group. Adam's walls and roofs are
# known by their ids (the Agent Outliner's notes and history, scenes, other
# sessions' claims and ledgers), so the whitecard kits booleaned a COPY and moved
# the result's faces back into the original (L692). Three kits carried their own
# copy of that code (existing_dormers, existing_roofs, bargeboards_gablets).
#
# HOW (the kits' proven route, then L1465's fallback):
#   1. faces: the target is cleared and every result face is added again
#      through result -> target (Na__Coordinates__SiblingToSibling), its holes
#      cut, its normal turned to the result's, its materials, tag and hidden
#      flag kept.
#   2. explode: when a face will not add again (a sliver face: "face N not
#      added"), or the re-added faces do not close into the result's solid, or a
#      face is textured (re-adding loses its texture positioning), the result's
#      definition is placed in the cleared target and exploded, which keeps
#      every face, UV and soft edge.
#   Either way the target must come out a solid of the result's volume, or this
#   raises and the router's abort leaves the model as it was.
#
# EDGE COLOURS (L1152: Adam repaints edges by hand, and a blanket colour wipes it):
#   - Each target edge is recorded, in the target's own coordinates, with its
#     material and its faces' normals, before the target is cleared.
#   - A new edge lying on an old edge between the same face planes takes the old
#     edge's material (no material included).
#   - Any other edge keeps the result's own edge material (the tools' colours),
#     or, with none, the target's most common edge material (Soft Black on a
#     whitecard), as the kits painted "the rest".
#   The lookup is a grid of cubic cells (Na__Transplant__BuildIndex): an old
#   edge is filed under the cells of points every half cell along it, and a new
#   edge looks in the 27 cells round its midpoint, which must lie on the old
#   edge, so no old edge that could hold it is missed. The index is pure Ruby on
#   plain arrays, checked offline by BridgeCore.
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Transplant

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        # Inches a point may sit off an old edge and still be on it (about 0.05 mm).
        NA_ON_EDGE_TOLERANCE = 0.002

        # Two face normals face the same way above this dot product (the kits' value).
        NA_SAME_NORMAL_DOT = 0.99999

        # About this many grid cells along the target's diagonal; never under NA_MIN_CELL inches.
        NA_CELLS_ALONG_DIAGONAL = 64.0
        NA_MIN_CELL = 0.1

        # The target's volume must match the result's to this fraction, plus this many cubic inches.
        NA_VOLUME_RELATIVE = 1.0e-6
        NA_VOLUME_ABSOLUTE = 0.01

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Transplant (SketchUp)
# -----------------------------------------------------------------------------

        # target and result: groups in ONE parent collection, result a solid, neither
        # open for editing. Replaces target's geometry with result's and erases result.
        # Returns a report; raises Na__McpError when the target cannot be made the result.
        def self.Na__Transplant__Into(target, result)
            to_target = Na__Coordinates.Na__Coordinates__SiblingToSibling(result, target)
            old_edges = na_edge_records(target.entities.grep(Sketchup::Edge), nil, true)
            default_material = self.Na__Transplant__MostCommon(old_edges.map { |record| record[:material] })
            result_faces = result.entities.grep(Sketchup::Face)
            result_edges = na_edge_records(result.entities.grep(Sketchup::Edge), to_target, false)
            expected_volume = result.volume.to_f
            report = { 'method' => nil }

            if result_faces.any? { |face| na_textured?(face) }
                report['fallback'] = 'a result face is textured, so it was placed and exploded to keep its texture positioning'
            else
                failure = na_by_faces(target, result_faces, to_target)
                failure ||= 'the re-added faces did not close into the result\'s solid' unless na_matches?(target, expected_volume)
                if failure
                    report['fallback'] = "#{failure}, so the result was placed and exploded instead (L1465)"
                else
                    report['method'] = 'faces'
                end
            end

            unless report['method']
                na_by_explode(target, result, to_target)
                report['method'] = 'explode'
                unless na_matches?(target, expected_volume)
                    raise Na__McpError.new('operation_failed',
                                           "keep_id: the result could not be put back into target #{target.persistent_id} as a solid of its volume " \
                                           "(#{Na__SolidHealth.Na__SolidHealth__Describe(target)}). Nothing was changed.",
                                           'Run solid_boolean without keep_id (the result gets a new id), or simplify the cutters ' \
                                           '(let them pass 1 mm beyond the faces they cut).')
                end
            end

            report['edge_colours'] = na_paint_edges(target, old_edges, report['method'] == 'faces' ? result_edges : nil, default_material)
            result.erase! if result.valid?
            report['faces'] = target.entities.grep(Sketchup::Face).length
            report['edges'] = target.entities.grep(Sketchup::Edge).length
            report
        end

        # Route 1: every result face added again into the cleared target. Returns nil,
        # or why a face would not add (the caller then explodes instead).
        def self.na_by_faces(target, result_faces, to_target)
            records = result_faces.map { |face| na_face_record(face, to_target) }
            entities = target.entities
            entities.clear!
            made = {}
            records.each_with_index do |record, index|
                face = na_add_face(entities, record[:outer])
                return "result face #{index + 1} of #{records.length} would not add again (a sliver or degenerate face)" unless face

                made[face] = true
                record[:holes].each do |hole|
                    filler = na_add_face(entities, hole)
                    # A hole another result face fills is already one of the faces made: never erase that.
                    filler.erase! if filler && filler != face && !made[filler]
                end
                return "result face #{index + 1} of #{records.length} was lost while its holes were cut" unless face.valid?

                face.reverse! if face.normal.dot(record[:normal]) < 0.0
                face.material = record[:material]
                face.back_material = record[:back_material]
                face.layer = record[:layer] if record[:layer]
                face.hidden = true if record[:hidden]
            end
            nil
        end

        # Route 2 (L1465): the result's definition placed in the cleared target and exploded.
        def self.na_by_explode(target, result, to_target)
            entities = target.entities
            entities.clear!
            entities.add_instance(result.definition, to_target).explode
        end

        def self.na_face_record(face, to_target)
            {
                outer: face.outer_loop.vertices.map { |vertex| to_target * vertex.position },
                holes: face.loops.reject(&:outer?).map { |loop| loop.vertices.map { |vertex| to_target * vertex.position } },
                # A vector carried by the linear part keeps the side of the true normal under any
                # placement ((M n) . (M^-T n) = n . n > 0), which is all the orientation test needs.
                normal: face.normal.transform(to_target),
                material: face.material, back_material: face.back_material, layer: face.layer, hidden: face.hidden?
            }
        end

        def self.na_add_face(entities, points)
            face = entities.add_face(points)
            face && face.valid? ? face : nil
        rescue ArgumentError
            nil
        end

        def self.na_textured?(face)
            [face.material, face.back_material].any? { |material| material && material.texture }
        end

        def self.na_matches?(target, expected_volume)
            return false unless target.manifold?

            (target.volume.to_f - expected_volume).abs <= (NA_VOLUME_RELATIVE * expected_volume.abs) + NA_VOLUME_ABSOLUTE
        end

        # Edges as plain records: a and b (float arrays, the target's coordinates), the
        # material and flags, and (with_normals) their faces' unit normals.
        def self.na_edge_records(edges, transform, with_normals)
            edges.map do |edge|
                a = edge.start.position
                b = edge.end.position
                a = transform * a if transform
                b = transform * b if transform
                record = { a: na_floats(a), b: na_floats(b), material: edge.material, soft: edge.soft?, smooth: edge.smooth?,
                           hidden: edge.hidden?, layer: edge.layer }
                record[:normals] = edge.faces.map { |face| Na__LinearMath.Na__LinearMath__Normalize(na_floats(face.normal)) } if with_normals
                record
            end
        end

        def self.na_floats(point_or_vector)
            point_or_vector.to_a.map(&:to_f)
        end

        # Each edge of the transplanted target: an old edge's colour where it lies on
        # one between the same face planes, else its own result colour, else the default.
        # result_edges nil (the explode route): the edges already carry the result's flags.
        def self.na_paint_edges(target, old_edges, result_edges, default_material)
            cell = self.Na__Transplant__CellSize(target.definition.bounds.diagonal.to_f)
            old_index = self.Na__Transplant__BuildIndex(old_edges, cell)
            result_index = result_edges ? self.Na__Transplant__BuildIndex(result_edges, cell) : nil
            counts = { 'kept' => 0, 'from_result' => 0, 'default' => 0 }

            target.entities.grep(Sketchup::Edge).each do |edge|
                a = na_floats(edge.start.position)
                b = na_floats(edge.end.position)
                normals = edge.faces.map { |face| Na__LinearMath.Na__LinearMath__Normalize(na_floats(face.normal)) }
                from_result = result_index ? self.Na__Transplant__Find(result_index, a, b, nil) : nil
                if from_result
                    edge.soft = from_result[:soft]
                    edge.smooth = from_result[:smooth]
                    edge.hidden = from_result[:hidden]
                    edge.layer = from_result[:layer] if from_result[:layer]
                end
                own = result_index ? (from_result && from_result[:material]) : edge.material
                old = self.Na__Transplant__Find(old_index, a, b, normals)
                if old
                    edge.material = old[:material]
                    counts['kept'] += 1
                elsif own
                    edge.material = own
                    counts['from_result'] += 1
                else
                    edge.material = default_material
                    counts['default'] += 1
                end
            end
            counts['default_material'] = default_material ? default_material.display_name : nil
            counts
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Edge Lookup (pure Ruby on plain arrays; BridgeCore checks it)
# -----------------------------------------------------------------------------

        def self.Na__Transplant__CellSize(diagonal)
            [diagonal.to_f / NA_CELLS_ALONG_DIAGONAL, NA_MIN_CELL].max
        end

        # records: [{a: [x, y, z], b: [x, y, z], normals: [[x, y, z], ...] or nil, ...}]
        def self.Na__Transplant__BuildIndex(records, cell)
            cells = Hash.new { |hash, key| hash[key] = [] }
            records.each_with_index do |record, index|
                na_segment_cells(record[:a], record[:b], cell).each { |key| cells[key] << index }
            end
            { cell: cell, cells: cells, records: records }
        end

        # The record whose segment holds a..b (both ends on it) and, when normals is
        # given, whose faces face the same ways; nil when none does.
        def self.Na__Transplant__Find(index, a, b, normals, tolerance = NA_ON_EDGE_TOLERANCE)
            middle = [0, 1, 2].map { |axis| (a[axis] + b[axis]) / 2.0 }
            centre = na_cell_key(middle, index[:cell])
            seen = {}
            [-1, 0, 1].each do |dx|
                [-1, 0, 1].each do |dy|
                    [-1, 0, 1].each do |dz|
                        key = [centre[0] + dx, centre[1] + dy, centre[2] + dz]
                        next unless index[:cells].key?(key)

                        index[:cells][key].each do |record_index|
                            next if seen[record_index]

                            seen[record_index] = true
                            record = index[:records][record_index]
                            next unless self.Na__Transplant__OnSegment(a, record[:a], record[:b], tolerance)
                            next unless self.Na__Transplant__OnSegment(b, record[:a], record[:b], tolerance)
                            next if normals && !self.Na__Transplant__SameNormals(normals, record[:normals] || [])

                            return record
                        end
                    end
                end
            end
            nil
        end

        def self.Na__Transplant__OnSegment(point, start_point, end_point, tolerance = NA_ON_EDGE_TOLERANCE)
            along = Na__LinearMath.Na__LinearMath__Subtract(end_point, start_point)
            length_squared = Na__LinearMath.Na__LinearMath__Dot(along, along)
            offset = Na__LinearMath.Na__LinearMath__Subtract(point, start_point)
            return Na__LinearMath.Na__LinearMath__Length(offset) < tolerance if length_squared < 1.0e-12

            fraction = Na__LinearMath.Na__LinearMath__Dot(offset, along) / length_squared
            slack = tolerance / Math.sqrt(length_squared)
            return false if fraction < -slack || fraction > 1.0 + slack

            nearest = Na__LinearMath.Na__LinearMath__Add(start_point, Na__LinearMath.Na__LinearMath__Scale(along, fraction))
            Na__LinearMath.Na__LinearMath__Length(Na__LinearMath.Na__LinearMath__Subtract(point, nearest)) < tolerance
        end

        # The same number of faces, each facing the way one of the old faces faced.
        def self.Na__Transplant__SameNormals(normals, old_normals)
            normals.length == old_normals.length &&
                normals.all? { |normal| old_normals.any? { |old| Na__LinearMath.Na__LinearMath__Dot(normal, old) > NA_SAME_NORMAL_DOT } }
        end

        # The commonest value (nil counts as a value); nil for an empty list.
        def self.Na__Transplant__MostCommon(values)
            return nil if values.empty?

            tally = Hash.new(0)
            values.each { |value| tally[value] += 1 }
            tally.max_by { |_value, count| count }.first
        end

        # The cells of points every half cell along a..b, its ends included.
        def self.na_segment_cells(a, b, cell)
            length = Na__LinearMath.Na__LinearMath__Length(Na__LinearMath.Na__LinearMath__Subtract(b, a))
            steps = [(length / (cell * 0.5)).ceil, 1].max
            (0..steps).map do |step|
                fraction = step.to_f / steps
                na_cell_key([0, 1, 2].map { |axis| a[axis] + ((b[axis] - a[axis]) * fraction) }, cell)
            end.uniq
        end

        def self.na_cell_key(point, cell)
            point.map { |value| (value / cell).floor }
        end

# endregion -------------------------------------------------------------------

    end # module Na__Transplant
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
