# =============================================================================
# NA PROFILE TOOLS - GEOMETRY HELPERS - UNIFIED OVERRIDES
# =============================================================================
#
# FILE       : Na__ProfileTools__GeometryHelpers__UnifiedOverrides__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__GeometryBuilders
# PURPOSE    : Unified-schema-only geometry builder. Edge materials now
#              delegate to Na__EdgeColourManager for exact RGB + no duplicates.
#
# CROSS-SECTION FIDELITY (v1.1.3):
#   Follow Me sweeps the start cap face *as-is*, so the cap MUST be perpendicular
#   to the first swept edge or the true cross-section is foreshortened by
#   cos(angle). Closed loops therefore start/end the sweep at the MIDPOINT of the
#   first segment (see Na__Geometry__BuildSweepRailPlan) so both caps are coplanar
#   and the corner miters cleanly. Open paths cap at the first vertex.
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer
    module Na__GeometryBuilders

    # -------------------------------------------------------------------------
    # REGION | Unified schema — asset blocks
    # -------------------------------------------------------------------------

        def self.Na__Geometry__ProfileType(profile_data)
            profile_data.dig('profileData', 'type').to_s
        end

        def self.Na__Geometry__UnifiedAssetData(profile_data)
            return nil unless self.Na__Geometry__ProfileType(profile_data) == 'na_unified_asset'
            asset_data = profile_data.dig('profileData', 'assetData')
            asset_data.is_a?(Hash) ? asset_data : nil
        end

        def self.Na__Geometry__UnifiedProfileBlock(profile_data)
            asset_data = self.Na__Geometry__UnifiedAssetData(profile_data)
            profile_block = asset_data ? asset_data['Na__Asset__Profile2D'] : nil
            profile_block.is_a?(Hash) ? profile_block : nil
        end

        def self.Na__Geometry__UnifiedMeshBlock(profile_data)
            asset_data = self.Na__Geometry__UnifiedAssetData(profile_data)
            mesh_block = asset_data ? asset_data['Na__Asset__Mesh3D'] : nil
            mesh_block.is_a?(Hash) ? mesh_block : nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Unified schema — vertices, faces, mesh edges
    # -------------------------------------------------------------------------

        def self.Na__Geometry__UnifiedVertexMap(profile_data)
            profile_block = self.Na__Geometry__UnifiedProfileBlock(profile_data)
            return {} unless profile_block

            vertices = Array(profile_block['Na__Geometry__Vertices'])
            vertices.each_with_object({}) do |vertex, map|
                next unless vertex.is_a?(Hash)
                vertex_id = vertex['VertexId'].to_s
                next if vertex_id.empty?
                map[vertex_id] = Geom::Point3d.new(vertex['PosY_mm'].to_f.mm, vertex['PosZ_mm'].to_f.mm, 0)
            end
        end

        def self.Na__Geometry__UnifiedFaceRecords(profile_data)
            profile_block = self.Na__Geometry__UnifiedProfileBlock(profile_data)
            return [] unless profile_block
            Array(profile_block['Na__Geometry__Faces']).select { |face| face.is_a?(Hash) }
        end

        def self.Na__Geometry__UnifiedMeshEdges(profile_data)
            mesh_block = self.Na__Geometry__UnifiedMeshBlock(profile_data)
            return [] unless mesh_block
            Array(mesh_block['Na__Geometry__Edges']).select { |edge| edge.is_a?(Hash) }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Profile 2D local points — mirrors
    # -------------------------------------------------------------------------

        def self.Na__Geometry__BuildLocalProfilePoints(profile_data)
            vertex_map = self.Na__Geometry__UnifiedVertexMap(profile_data)
            face_records = self.Na__Geometry__UnifiedFaceRecords(profile_data)
            return [] if vertex_map.empty? || face_records.empty?

            outer_ids = Array(face_records.first['OuterLoopVertices'])
            return [] if outer_ids.length < 3
            outer_ids.map { |vertex_id| vertex_map[vertex_id.to_s] }.compact
        end

        def self.Na__Geometry__ApplyMirrorToggles(local_points, toggle_states = {})
            Na__MirrorProfile.Na__Mirror__ApplyToggles(local_points, toggle_states || {})
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Path frame — sanitise path — segment tangents
    # -------------------------------------------------------------------------

        def self.Na__Geometry__BuildPathFrame(start_point, path_data)
            is_closed_loop = path_data[:is_closed_loop] == true
            ordered_points = self.Na__Geometry__BuildSanitizedPathPoints(path_data[:ordered_points] || [])
            if is_closed_loop &&
               ordered_points.length >= 3 &&
               ordered_points.first.distance(ordered_points.last) <= 0.001
                ordered_points = ordered_points[0...-1]
            end
            return nil unless ordered_points && ordered_points.length >= 2
            return nil if is_closed_loop && ordered_points.length < 3

            nearest_index = ordered_points.each_index.min_by { |index| ordered_points[index].distance(start_point) } || 0
            tangent = self.Na__Geometry__BuildStartFrameTangent(ordered_points, nearest_index, is_closed_loop)
            return nil unless tangent

            self.Na__Geometry__BuildPathFrameFromTangent(ordered_points[nearest_index], tangent)
        end

        def self.Na__Geometry__BuildStartFrameTangent(ordered_points, nearest_index, is_closed_loop)
            return nil unless ordered_points && nearest_index
            return nil if ordered_points.length < 2

            # Always orient the start cap perpendicular to the first swept edge.
            # SketchUp's follow-me sweeps the cap face as-is, so any oblique cap
            # (e.g. a corner bisector) would foreshorten the true cross-section.
            # Closed-loop seam coplanarity is handled separately in
            # Na__Geometry__BuildSweepRailPlan (midpoint start), not here.
            self.Na__Geometry__OutgoingTangentAtIndex(ordered_points, nearest_index, is_closed_loop)
        end

        def self.Na__Geometry__OutgoingTangentAtIndex(ordered_points, index, is_closed_loop)
            point_count = ordered_points.length
            return nil if point_count < 2

            if index < point_count - 1
                tangent = ordered_points[index + 1] - ordered_points[index]
            elsif is_closed_loop
                tangent = ordered_points[0] - ordered_points[index]
            else
                tangent = ordered_points[index] - ordered_points[index - 1]
            end
            return nil if tangent.length <= 0.001
            tangent.normalize!
            tangent
        end

        def self.Na__Geometry__TransformProfilePoints(local_points, frame_transform, rotation_step)
            return [] if local_points.empty? || frame_transform.nil?
            degrees = rotation_step.to_i * 90
            rotation = Geom::Transformation.rotation(frame_transform.origin, frame_transform.zaxis, degrees.degrees)
            local_points.map { |point| point.transform(frame_transform).transform(rotation) }
        end

        def self.Na__Geometry__BuildSanitizedPathPoints(ordered_points)
            points = Array(ordered_points).compact
            return [] if points.length < 2
            sanitized = [points.first]
            points[1..-1].each do |point|
                next if sanitized.last.distance(point) <= 0.001
                sanitized << point
            end
            sanitized
        end

        def self.Na__Geometry__BuildPathSegmentDirections(ordered_points)
            directions = []
            (0...(ordered_points.length - 1)).each do |index|
                tangent = ordered_points[index + 1] - ordered_points[index]
                next if tangent.length <= 0.001
                tangent.normalize!
                directions << tangent
            end
            directions
        end

        def self.Na__Geometry__BuildPathFrameFromTangent(origin_point, tangent_vector)
            return nil unless origin_point && tangent_vector
            return nil if tangent_vector.length <= 0.001

            tangent = tangent_vector.clone
            tangent.normalize!
            up = Z_AXIS
            up = X_AXIS if tangent.parallel?(up)
            x_axis = up * tangent
            x_axis = X_AXIS if x_axis.length <= 0.001
            x_axis.normalize!
            y_axis = tangent * x_axis
            y_axis.normalize!
            Geom::Transformation.axes(origin_point, x_axis, y_axis, tangent)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Preview geometry — polyline + sweep segments
    # -------------------------------------------------------------------------

        def self.Na__Geometry__BuildPreviewMiterPoint(incoming_point, incoming_tangent, outgoing_point, outgoing_tangent)
            incoming_line = [incoming_point, incoming_tangent]
            outgoing_line = [outgoing_point, outgoing_tangent]
            intersection = Geom.intersect_line_line(incoming_line, outgoing_line)
            return intersection if intersection

            closest_points = Geom.closest_points(incoming_line, outgoing_line)
            if closest_points.is_a?(Array) && closest_points.length == 2
                return Geom.linear_combination(0.5, closest_points[0], 0.5, closest_points[1])
            end

            Geom.linear_combination(0.5, incoming_point, 0.5, outgoing_point)
        rescue
            Geom.linear_combination(0.5, incoming_point, 0.5, outgoing_point)
        end

        def self.Na__Geometry__BuildPreviewProfilePolyline(profile_data:, path_data:, start_point:, rotation_step:, toggle_states: {})
            local_profile_points = self.Na__Geometry__BuildLocalProfilePoints(profile_data)
            local_profile_points = self.Na__Geometry__ApplyMirrorToggles(local_profile_points, toggle_states)
            frame_transform = self.Na__Geometry__BuildPathFrame(start_point, path_data)
            self.Na__Geometry__TransformProfilePoints(local_profile_points, frame_transform, rotation_step)
        end

        def self.Na__Geometry__BuildPreviewSweepSegments(profile_data:, path_data:, rotation_step:, toggle_states: {})
            is_closed_loop = path_data[:is_closed_loop] == true
            ordered_points = self.Na__Geometry__BuildSanitizedPathPoints(path_data[:ordered_points] || [])
            if is_closed_loop &&
               ordered_points.length >= 3 &&
               ordered_points.first.distance(ordered_points.last) <= 0.001
                ordered_points = ordered_points[0...-1]
            end
            return [] if ordered_points.length < 2
            return [] if is_closed_loop && ordered_points.length < 3

            local_profile_points = self.Na__Geometry__BuildLocalProfilePoints(profile_data)
            local_profile_points = self.Na__Geometry__ApplyMirrorToggles(local_profile_points, toggle_states)
            return [] if local_profile_points.length < 2

            segment_directions = self.Na__Geometry__BuildPathSegmentDirections(ordered_points)
            if is_closed_loop
                closing_tangent = ordered_points.first - ordered_points.last
                if closing_tangent.length > 0.001
                    closing_tangent.normalize!
                    segment_directions << closing_tangent
                end
            end
            return [] if segment_directions.empty?
            return [] if is_closed_loop && segment_directions.length < ordered_points.length

            corner_profiles = []
            last_vertex_index = ordered_points.length - 1

            (0..last_vertex_index).each do |vertex_index|
                point = ordered_points[vertex_index]
                if is_closed_loop
                    incoming_tangent = segment_directions[(vertex_index - 1) % segment_directions.length]
                    outgoing_tangent = segment_directions[vertex_index % segment_directions.length]
                else
                    incoming_tangent = vertex_index.zero? ? segment_directions[0] : segment_directions[vertex_index - 1]
                    outgoing_tangent = vertex_index == last_vertex_index ? segment_directions[-1] : segment_directions[vertex_index]
                end
                return [] unless incoming_tangent && outgoing_tangent

                incoming_frame = self.Na__Geometry__BuildPathFrameFromTangent(point, incoming_tangent)
                outgoing_frame = self.Na__Geometry__BuildPathFrameFromTangent(point, outgoing_tangent)
                return [] unless incoming_frame && outgoing_frame

                incoming_profile = self.Na__Geometry__TransformProfilePoints(local_profile_points, incoming_frame, rotation_step)
                outgoing_profile = self.Na__Geometry__TransformProfilePoints(local_profile_points, outgoing_frame, rotation_step)
                return [] if incoming_profile.empty? || outgoing_profile.empty?

                if !is_closed_loop
                    if vertex_index.zero?
                        corner_profiles << outgoing_profile
                        next
                    end
                    if vertex_index == last_vertex_index
                        corner_profiles << incoming_profile
                        next
                    end
                end

                corner_profiles << incoming_profile.each_index.map do |point_index|
                    self.Na__Geometry__BuildPreviewMiterPoint(
                        incoming_profile[point_index],
                        incoming_tangent,
                        outgoing_profile[point_index],
                        outgoing_tangent
                    )
                end
            end

            return [] if corner_profiles.length < 2
            profile_point_count = corner_profiles.first.length
            return [] if profile_point_count < 2

            closed_local_profile = corner_profiles.first.first.distance(corner_profiles.first.last) <= 0.001
            segments = []

            corner_profiles.each do |profile_points|
                last_index = profile_points.length - 1
                (0...last_index).each do |index|
                    segments << profile_points[index] << profile_points[index + 1]
                end
                segments << profile_points[last_index] << profile_points[0] unless closed_local_profile
            end

            profile_link_count = is_closed_loop ? corner_profiles.length : (corner_profiles.length - 1)
            (0...profile_link_count).each do |profile_index|
                from_profile = corner_profiles[profile_index]
                to_profile = if is_closed_loop
                                 corner_profiles[(profile_index + 1) % corner_profiles.length]
                             else
                                 corner_profiles[profile_index + 1]
                             end
                (0...profile_point_count).each do |point_index|
                    segments << from_profile[point_index] << to_profile[point_index]
                end
            end

            segments
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Solid — follow-me along path
    # -------------------------------------------------------------------------

        def self.Na__Geometry__BuildProfileAlongPath(model:, profile_data:, path_data:, start_point:, rotation_step:, toggle_states: {}, reverse_direction: false)
            return { 'isBuilt' => false, 'reason' => 'No active model.' } unless model
            unless self.Na__Geometry__ProfileType(profile_data) == 'na_unified_asset'
                return { 'isBuilt' => false, 'reason' => 'Only unified schema profiles are supported.' }
            end

            is_closed_loop = path_data[:is_closed_loop] == true
            ordered_points = self.Na__Geometry__BuildSanitizedPathPoints(path_data[:ordered_points] || [])
            if is_closed_loop &&
               ordered_points.length >= 3 &&
               ordered_points.first.distance(ordered_points.last) <= 0.001
                ordered_points = ordered_points[0...-1]
            end
            return { 'isBuilt' => false, 'reason' => 'Path must contain at least two points.' } if ordered_points.length < 2
            return { 'isBuilt' => false, 'reason' => 'Closed path must contain at least three points.' } if is_closed_loop && ordered_points.length < 3

            resolved_path_data = path_data.merge(
                ordered_points: ordered_points,
                is_closed_loop: is_closed_loop
            )

            local_profile_points = self.Na__Geometry__BuildLocalProfilePoints(profile_data)
            local_profile_points = self.Na__Geometry__ApplyMirrorToggles(local_profile_points, toggle_states)
            return { 'isBuilt' => false, 'reason' => 'Selected profile has invalid points.' } if local_profile_points.length < 3

            frame_transform = self.Na__Geometry__BuildPathFrame(start_point, resolved_path_data)
            return { 'isBuilt' => false, 'reason' => 'Path frame could not be built.' } unless frame_transform

            profile_key = profile_data['profileKey'] || 'Unnamed'
            model.start_operation('Na__ProfilePathTracer__GenerateUnifiedProfile', true)

            parent_group = model.active_entities.add_group
            parent_group.name = "Na__ProfileTrace__#{profile_key}"

            helpers_group = parent_group.entities.add_group
            helpers_group.name = 'Na__ProfileTrace__Helpers'

            solid_group = parent_group.entities.add_group
            solid_group.name = 'Na__ProfileTrace__SweptSolid'
            solid_entities = solid_group.entities

            effective_rotation_step = reverse_direction ? (rotation_step + 2) % 4 : rotation_step

            swept = self.Na__Geometry__SweepProfileIntoGroup(
                target_entities:    solid_entities,
                model:              model,
                profile_data:       profile_data,
                ordered_points:     ordered_points,
                is_closed_loop:     is_closed_loop,
                frame_transform:    frame_transform,
                rotation_step:      effective_rotation_step,
                toggle_states:      toggle_states,
                resolved_path_data: resolved_path_data
            )
            unless swept['isSwept']
                self.Na__Geometry__AbortOperationSafely(model)
                return { 'isBuilt' => false, 'reason' => swept['reason'] }
            end
            styled_edge_count = swept['styledEdgeCount']

            self.Na__Geometry__BuildHelpersSubGroup(model, helpers_group, ordered_points, is_closed_loop)

            if reverse_direction
                z_flip = Geom::Transformation.scaling(parent_group.bounds.center, 1.0, 1.0, -1.0)
                parent_group.transform!(z_flip)
                z_correction = parent_group.bounds.max.z - parent_group.bounds.min.z
                z_translate = Geom::Transformation.translation(Geom::Vector3d.new(0, 0, z_correction))
                parent_group.transform!(z_translate)
            end

            # @delegate: ../02__AppData/Na__ProfileTools__AppData__DataSerializer__
            self.Na__Geometry__StampAssemblyDictionaries(
                model, parent_group, helpers_group,
                profile_key: profile_key,
                rotation_step: rotation_step,
                toggle_states: toggle_states,
                is_closed_loop: is_closed_loop,
                start_point: start_point
            )

            model.commit_operation

            self.Na__Geometry__AutoEnableDynamicRegen(parent_group, helpers_group)

            { 'isBuilt' => true, 'groupName' => parent_group.name, 'styledEdgeCount' => styled_edge_count }
        rescue => error
            self.Na__Geometry__AbortOperationSafely(model)
            { 'isBuilt' => false, 'reason' => error.message }
        end

        def self.Na__Geometry__AutoEnableDynamicRegen(parent_group, helpers_group)
            return unless parent_group && helpers_group
            return unless helpers_group.respond_to?(:valid?) && helpers_group.valid?
            return unless defined?(Na__ObserverRegistry)

            Na__ObserverRegistry.Na__ObserverRegistry__AttachToHelpers(helpers_group)

            if defined?(Na__ContextMenuHandlers) &&
               Na__ContextMenuHandlers.respond_to?(:Na__ContextMenu__UpdateGroupNameSuffix)
                Na__ContextMenuHandlers.Na__ContextMenu__UpdateGroupNameSuffix(parent_group, true)
            end

            Na__DebugTools.Na__Debug__Info(
                "DynamicRegen auto-enabled on #{parent_group.name} (observer attached)."
            )
        rescue => error
            Na__DebugTools.Na__Debug__Warn("AutoEnableDynamicRegen failed: #{error.message}")
        end

        def self.Na__Geometry__SweepProfileIntoGroup(target_entities:, model:, profile_data:,
                                                        ordered_points:, is_closed_loop:, frame_transform:,
                                                        rotation_step:, toggle_states:, resolved_path_data:)
            sweep_plan = self.Na__Geometry__BuildSweepRailPlan(ordered_points, is_closed_loop, frame_transform)
            return { 'isSwept' => false, 'reason' => sweep_plan[:reason] } unless sweep_plan[:isValid]

            rail_points   = sweep_plan[:rail_points]
            cap_frame     = sweep_plan[:cap_frame]
            closure_plane = sweep_plan[:closure_plane]

            path_edges    = []
            path_edge_ids = []

            (0...(rail_points.length - 1)).each do |index|
                edge = target_entities.add_line(rail_points[index], rail_points[index + 1])
                if edge && edge.valid?
                    path_edges << edge
                    begin; path_edge_ids << edge.persistent_id; rescue; end
                end
            end

            face_result = self.Na__Geometry__BuildTransformedProfileFace(
                target_entities, profile_data, cap_frame, rotation_step, toggle_states
            )
            return { 'isSwept' => false, 'reason' => face_result['reason'] } unless face_result['isValid']

            profile_face = face_result['profileFace']
            profile_face.followme(path_edges)
            target_entities.erase_entities(profile_face) if profile_face.valid?

            self.Na__Geometry__RemoveClosureSeamFaces(target_entities, closure_plane)
            styled_edge_count = self.Na__Geometry__ApplyUnifiedEdgeStates(
                target_entities, model, profile_data, path_edge_ids, resolved_path_data
            )
            self.Na__Geometry__ErasePathRailEdges(target_entities, path_edges)
            { 'isSwept' => true, 'styledEdgeCount' => styled_edge_count }
        rescue => error
            { 'isSwept' => false, 'reason' => error.message }
        end

        # Builds the follow-me rail, the perpendicular cap frame and (for closed
        # loops) the closure seam plane.
        #
        # Open path : rail = the corner points as-is, cap at the first vertex.
        # Closed loop: rail starts and ends at the midpoint M of the first
        #              segment (M -> V1 -> ... -> Vn -> V0 -> M) so the start and
        #              end caps are coplanar and merge into a clean mitered seam.
        #              The cap is built at M, perpendicular to (V1 - V0), which
        #              preserves the true profile cross-section.
        def self.Na__Geometry__BuildSweepRailPlan(ordered_points, is_closed_loop, frame_transform)
            points = Array(ordered_points)
            return { isValid: false, reason: 'Path must contain at least two points.' } if points.length < 2

            unless is_closed_loop
                return {
                    isValid: true,
                    rail_points: points,
                    cap_frame: frame_transform,
                    closure_plane: nil
                }
            end

            return { isValid: false, reason: 'Closed path must contain at least three points.' } if points.length < 3

            first_vertex  = points[0]
            second_vertex = points[1]
            tangent = second_vertex - first_vertex
            return { isValid: false, reason: 'First path segment has zero length.' } if tangent.length <= 0.001
            tangent.normalize!

            midpoint = Geom.linear_combination(0.5, first_vertex, 0.5, second_vertex)
            cap_frame = self.Na__Geometry__BuildPathFrameFromTangent(midpoint, tangent)
            return { isValid: false, reason: 'Closed-loop cap frame could not be built.' } unless cap_frame

            rail_points = [midpoint] + points[1..-1] + [first_vertex, midpoint]

            {
                isValid: true,
                rail_points: rail_points,
                cap_frame: cap_frame,
                closure_plane: {
                    origin: midpoint,
                    normal: tangent,
                    ordered_points: points
                }
            }
        end

        def self.Na__Geometry__ErasePathRailEdges(target_entities, path_edges)
            to_erase = path_edges.select { |edge| edge && edge.respond_to?(:valid?) && edge.valid? }
            return if to_erase.empty?
            target_entities.erase_entities(to_erase)
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Path rail edge erasure warning: #{error.message}")
        end

        def self.Na__Geometry__AbortOperationSafely(model)
            return unless model
            model.abort_operation
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Abort operation warning: #{error.message}")
        end

        def self.Na__Geometry__BuildHelpersSubGroup(model, helpers_group, ordered_points, is_closed_loop)
            entities = helpers_group.entities
            helper_edges = []

            (0...(ordered_points.length - 1)).each do |index|
                edge = entities.add_line(ordered_points[index], ordered_points[index + 1])
                helper_edges << edge if edge && edge.valid?
            end

            if is_closed_loop
                closing_edge = entities.add_line(ordered_points[-1], ordered_points[0])
                helper_edges << closing_edge if closing_edge && closing_edge.valid?
            end

            # @delegate: ../03__AppUtils/Na__ProfileTools__AppUtils__TagApplier__
            helpers_tag = Na__TagApplier.Na__TagApplier__EnsureTagFromDataLib(model, NA_HELPERS_TAG_NAME)
            Na__TagApplier.Na__TagApplier__ApplyTagToEntity(helpers_group, helpers_tag)
            Na__TagApplier.Na__TagApplier__PaintEdgesWithMteMaterial(model, helper_edges, NA_HELPERS_MATERIAL_ID)
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Helpers sub-group build warning: #{error.message}")
        end

        def self.Na__Geometry__StampAssemblyDictionaries(model, parent_group, helpers_group,
                                                          profile_key:, rotation_step:, toggle_states:,
                                                          is_closed_loop:, start_point:)
            return unless defined?(Na__DataSerializer)

            trace_id = Na__DataSerializer.Na__DataSerializer__GenerateNextProfileTraceId(model)
            Na__DataSerializer.Na__DataSerializer__StampParent(parent_group, {
                'ProfileTraceId' => trace_id,
                'ProfileKey'     => profile_key,
                'RotationStep'   => rotation_step,
                'ToggleStates'   => toggle_states,
                'IsClosedLoop'   => is_closed_loop,
                'StartPoint'     => start_point
            })
            Na__DataSerializer.Na__DataSerializer__StampHelpers(helpers_group, trace_id)
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Assembly dictionary stamp warning: #{error.message}")
        end

        # closure_plane: { origin: M, normal: (V1 - V0), ordered_points: [...] }
        # built by Na__Geometry__BuildSweepRailPlan; nil for open paths (no seam).
        def self.Na__Geometry__RemoveClosureSeamFaces(entities, closure_plane)
            return 0 unless closure_plane.is_a?(Hash)
            return 0 unless entities

            closure_origin = closure_plane[:origin]
            closure_normal = closure_plane[:normal]
            ordered_points = Array(closure_plane[:ordered_points])
            return 0 unless closure_origin && closure_normal && closure_normal.length > 0.001
            return 0 if ordered_points.length < 3

            plane = [closure_origin, closure_normal]
            plane_distance_tolerance = 0.05.mm
            seam_radius_tolerance = self.Na__Geometry__SeamRadiusTolerance(ordered_points)

            seam_faces = entities.grep(Sketchup::Face).select do |face|
                self.Na__Geometry__FaceLiesOnClosurePlane?(face, plane, closure_normal, closure_origin, plane_distance_tolerance, seam_radius_tolerance)
            end
            return 0 if seam_faces.empty?

            entities.erase_entities(seam_faces.select(&:valid?))
            seam_faces.length
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Closure seam cleanup warning: #{error.message}")
            0
        end

        def self.Na__Geometry__FaceLiesOnClosurePlane?(face, plane, closure_normal, closure_origin, plane_distance_tolerance, seam_radius_tolerance)
            return false unless face && face.valid?
            return false unless face.normal.parallel?(closure_normal)

            outer_vertices = face.outer_loop.vertices
            return false if outer_vertices.empty?

            outer_vertices.all? do |vertex|
                position = vertex.position
                on_plane = Geom.point_plane_distance(position, plane).abs <= plane_distance_tolerance
                near_origin = position.distance(closure_origin) <= seam_radius_tolerance
                on_plane && near_origin
            end
        rescue
            false
        end

        def self.Na__Geometry__SeamRadiusTolerance(ordered_points)
            return 1.0.m if ordered_points.length < 2
            shortest_segment = nil
            (0...(ordered_points.length - 1)).each do |index|
                segment_length = ordered_points[index].distance(ordered_points[index + 1])
                next if segment_length <= 0.001
                shortest_segment = segment_length if shortest_segment.nil? || segment_length < shortest_segment
            end
            return 1.0.m unless shortest_segment
            [shortest_segment * 0.45, 1.0.m].min
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Transformed profile face
    # -------------------------------------------------------------------------

        def self.Na__Geometry__BuildTransformedProfileFace(entities, profile_data, frame_transform, rotation_step, toggle_states)
            vertex_map = self.Na__Geometry__UnifiedVertexMap(profile_data)
            face_records = self.Na__Geometry__UnifiedFaceRecords(profile_data)
            return { 'isValid' => false, 'reason' => 'Unified profile has no vertices.' } if vertex_map.empty?
            return { 'isValid' => false, 'reason' => 'Unified profile has no faces.' } if face_records.empty?

            transformed_vertices = self.Na__Geometry__TransformVertexMap(vertex_map, frame_transform, rotation_step, toggle_states)
            outer_ids = Array(face_records.first['OuterLoopVertices'])
            return { 'isValid' => false, 'reason' => 'Unified profile face has fewer than three vertices.' } if outer_ids.length < 3

            outer_points = outer_ids.map { |vertex_id| transformed_vertices[vertex_id.to_s] }.compact
            return { 'isValid' => false, 'reason' => 'Unified profile could not map transformed vertices.' } if outer_points.length < 3

            profile_face = entities.add_face(outer_points)
            return { 'isValid' => false, 'reason' => 'Could not create profile face.' } unless profile_face

            profile_face.reverse! if profile_face.normal.dot(frame_transform.zaxis) < 0
            { 'isValid' => true, 'profileFace' => profile_face }
        end

        def self.Na__Geometry__TransformVertexMap(vertex_map, frame_transform, rotation_step, toggle_states)
            local_points = vertex_map.values
            transformed_points = self.Na__Geometry__TransformProfilePoints(local_points, frame_transform, rotation_step)
            transformed_points = Na__MirrorProfile.Na__Mirror__ApplyToggles(transformed_points, toggle_states || {})

            transformed_map = {}
            vertex_map.keys.each_with_index { |vertex_id, index| transformed_map[vertex_id] = transformed_points[index] }
            transformed_map
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Edge styling
    # -------------------------------------------------------------------------

        NA_RUN_EDGE_SOFTEN_ANGLE_RADIANS = 20.0 * Math::PI / 180.0
        NA_HELPERS_TAG_NAME    = '02__ProfilePathTracer_Helpers'.freeze
        NA_HELPERS_MATERIAL_ID = 'MTE201__LineColour__Red'.freeze

        def self.Na__Geometry__ApplyUnifiedEdgeStates(entities, model, profile_data, path_edge_ids, path_data)
            style_reference = self.Na__Geometry__BuildStyleReferenceRecords(profile_data)
            return 0 if style_reference.empty?

            protected_path_edge_ids = Array(path_edge_ids).compact.uniq
            cap_planes = self.Na__Geometry__BuildPathCapPlanes(path_data)
            candidate_edges = entities.grep(Sketchup::Edge).select(&:valid?).reject do |edge|
                begin
                    protected_path_edge_ids.include?(edge.persistent_id) || self.Na__Geometry__EdgeOnCapPlane?(edge, cap_planes)
                rescue
                    true
                end
            end
            return 0 if candidate_edges.empty?

            run_edges = candidate_edges.select do |edge|
                self.Na__Geometry__ClassifyAsConnectorRunEdge?(edge)
            end
            return 0 if run_edges.empty?

            styled_count = 0
            run_edges.each do |edge|
                reference = self.Na__Geometry__FindClosestStyleReference(edge, style_reference)
                style_payload = self.Na__Geometry__BuildPerEdgeStylePayload(edge, reference)
                self.Na__Geometry__ApplyEdgeState(edge, model, style_payload)
                styled_count += 1
            end
            styled_count
        end

        def self.Na__Geometry__BuildPerEdgeStylePayload(edge, reference)
            base_payload = (reference || {}).dup
            should_soften = self.Na__Geometry__ShouldSoftenRunEdgeByAngle?(edge)
            base_payload['IsSoft']   = should_soften
            base_payload['IsSmooth'] = should_soften
            base_payload
        end

        def self.Na__Geometry__ShouldSoftenRunEdgeByAngle?(edge)
            return false unless edge && edge.valid?
            faces = Array(edge.faces).select(&:valid?)
            return false unless faces.length == 2

            angle = self.Na__Geometry__DihedralAngleBetween(faces[0], faces[1])
            return false unless angle
            angle <= NA_RUN_EDGE_SOFTEN_ANGLE_RADIANS
        rescue
            false
        end

        def self.Na__Geometry__DihedralAngleBetween(face_a, face_b)
            return nil unless face_a && face_b && face_a.valid? && face_b.valid?
            normal_a = face_a.normal
            normal_b = face_b.normal
            return nil if normal_a.length <= 0.001 || normal_b.length <= 0.001

            cos_angle = (normal_a.dot(normal_b)) / (normal_a.length * normal_b.length)
            cos_angle = -1.0 if cos_angle < -1.0
            cos_angle = 1.0 if cos_angle > 1.0
            Math.acos(cos_angle.abs)
        rescue
            nil
        end

        def self.Na__Geometry__BuildPathCapPlanes(path_data)
            return [] unless path_data.is_a?(Hash)
            return [] if path_data[:is_closed_loop] == true

            ordered_points = Array(path_data[:ordered_points]).compact
            return [] if ordered_points.length < 2

            first_tangent = ordered_points[1] - ordered_points[0]
            last_tangent = ordered_points[-1] - ordered_points[-2]
            return [] if first_tangent.length <= 0.001 || last_tangent.length <= 0.001

            first_tangent.normalize!
            last_tangent.normalize!

            [
                [ordered_points[0], first_tangent],
                [ordered_points[-1], last_tangent]
            ]
        end

        def self.Na__Geometry__EdgeOnCapPlane?(edge, cap_planes)
            return false unless edge && edge.valid?
            return false unless cap_planes.is_a?(Array) && !cap_planes.empty?

            start_point = edge.start.position
            end_point = edge.end.position
            tolerance = 0.25.mm

            cap_planes.any? do |plane|
                begin
                    start_distance = Geom.point_plane_distance(start_point, plane).abs
                    end_distance = Geom.point_plane_distance(end_point, plane).abs
                    start_distance <= tolerance && end_distance <= tolerance
                rescue
                    false
                end
            end
        end

        def self.Na__Geometry__ClassifyAsConnectorRunEdge?(edge)
            return false unless edge && edge.valid?
            return false unless edge.respond_to?(:faces)

            faces = Array(edge.faces).select(&:valid?)
            faces.length >= 2
        rescue
            false
        end

        def self.Na__Geometry__BuildStyleReferenceRecords(profile_data)
            vertex_map = self.Na__Geometry__UnifiedVertexMap(profile_data)
            mesh_edges = self.Na__Geometry__UnifiedMeshEdges(profile_data)
            return [] if vertex_map.empty? || mesh_edges.empty?

            mesh_edges.each_with_object([]) do |mesh_edge, records|
                start_vertex = vertex_map[mesh_edge['StartVertex'].to_s]
                end_vertex = vertex_map[mesh_edge['EndVertex'].to_s]
                next unless start_vertex && end_vertex

                records << {
                    'length_mm' => start_vertex.distance(end_vertex) * 25.4,
                    'IsSoft' => mesh_edge['IsSoft'] == true,
                    'IsSmooth' => mesh_edge['IsSmooth'] == true,
                    'IsHidden' => mesh_edge['IsHidden'] == true,
                    'CastsShadows' => mesh_edge['CastsShadows'] != false,
                    'EdgeMaterialName' => mesh_edge['EdgeMaterialName'].to_s,
                    'EdgeColourId' => mesh_edge['EdgeColourId'].to_s,
                    'EdgeColourHex' => mesh_edge['EdgeColourHex'].to_s
                }
            end
        end

        def self.Na__Geometry__FindClosestStyleReference(edge, style_reference)
            edge_length_mm = edge.length * 25.4
            style_reference.min_by { |reference| (reference['length_mm'].to_f - edge_length_mm).abs }
        end

        def self.Na__Geometry__ApplyEdgeState(edge, model, reference)
            edge.hidden = reference['IsHidden'] == true
            edge.soft = reference['IsSoft'] == true
            edge.smooth = reference['IsSmooth'] == true
            edge.casts_shadows = reference['CastsShadows'] == true if edge.respond_to?(:casts_shadows=)

            material = self.Na__Geometry__ResolveEdgeMaterial(model, reference)
            edge.material = material if material
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Failed applying edge state: #{error.message}")
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Edge material resolution — delegates to EdgeColourManager
    # -------------------------------------------------------------------------

        def self.Na__Geometry__ResolveEdgeMaterial(model, reference)
            material_name = reference['EdgeMaterialName'].to_s
            edge_colour_id = reference['EdgeColourId'].to_s
            edge_colour_hex = reference['EdgeColourHex'].to_s

            mte_id = edge_colour_id.empty? ? material_name : edge_colour_id
            mte_id = material_name if mte_id.empty?

            if !mte_id.empty? && defined?(Na__EdgeColourManager) &&
               Na__EdgeColourManager.respond_to?(:Na__EdgeColours__EnsureSketchUpMaterial)
                result = Na__EdgeColourManager.Na__EdgeColours__EnsureSketchUpMaterial(model, mte_id)
                return result if result
            end

            return nil if material_name.empty? && edge_colour_id.empty? && edge_colour_hex.empty?

            resolved_name = material_name
            resolved_name = "Na__ProfileEdge__#{edge_colour_hex.delete('#')}" if resolved_name.empty? && !edge_colour_hex.empty?
            return nil if resolved_name.empty?

            material = model.materials[resolved_name] || model.materials.add(resolved_name)
            rgb = self.Na__Geometry__HexToRgb(edge_colour_hex)
            material.color = Sketchup::Color.new(*rgb) if rgb
            material
        rescue
            nil
        end

        def self.Na__Geometry__HexToRgb(hex_value)
            sanitized = hex_value.to_s.strip.delete('#')
            return nil unless sanitized.length == 6
            [sanitized[0..1].to_i(16), sanitized[2..3].to_i(16), sanitized[4..5].to_i(16)]
        rescue
            nil
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
