# =============================================================================
# NA PROFILE TOOLS - PROFILE PATH TRACER - GEOMETRY BUILDERS
# =============================================================================
#
# FILE       : Na__ProfileTools__ProfilePathTracer__GeometryBuilders__.rb
# PURPOSE    : Low-level geometry building helpers for traced profiles
# CREATED    : 2026
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer
    module Na__GeometryBuilders

    # -------------------------------------------------------------------------
    # REGION | Group Creation
    # -------------------------------------------------------------------------

        def self.Na__Geometry__CreateGroup(model, group_name)
            group = model.active_entities.add_group
            group.name = group_name
            group
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Profile Geometry Building (Scaffold)
    # -------------------------------------------------------------------------

        def self.Na__Geometry__BuildLocalProfilePoints(profile_data)
            points = profile_data.dig('profileData', 'points') || []
            points
                .select { |point| point.is_a?(Array) && point.length >= 2 }
                .map { |point| Geom::Point3d.new(point[0].to_f.mm, point[1].to_f.mm, 0) }
        end

        def self.Na__Geometry__BuildPathFrame(start_point, path_data)
            ordered_points = path_data[:ordered_points]
            return nil unless ordered_points && ordered_points.length >= 2

            nearest_index = ordered_points.each_index.min_by { |idx| ordered_points[idx].distance(start_point) } || 0
            next_index = (nearest_index + 1) % ordered_points.length
            next_index = nearest_index + 1 if !path_data[:is_closed_loop] && nearest_index == ordered_points.length - 1
            previous_index = nearest_index - 1

            tangent =
                if next_index && next_index < ordered_points.length
                    ordered_points[next_index] - ordered_points[nearest_index]
                else
                    ordered_points[nearest_index] - ordered_points[previous_index]
                end

            return nil if tangent.length <= 0.001
            tangent.normalize!

            up = Z_AXIS
            up = X_AXIS if tangent.parallel?(up)
            x_axis = up * tangent
            x_axis = X_AXIS if x_axis.length <= 0.001
            x_axis.normalize!
            y_axis = tangent * x_axis
            y_axis.normalize!

            Geom::Transformation.axes(ordered_points[nearest_index], x_axis, y_axis, tangent)
        end

        def self.Na__Geometry__TransformProfilePoints(local_points, frame_transform, rotation_step)
            return [] if local_points.empty? || frame_transform.nil?
            degrees = rotation_step.to_i * 90
            rotation = Geom::Transformation.rotation(frame_transform.origin, frame_transform.zaxis, degrees.degrees)
            local_points.map { |point| point.transform(frame_transform).transform(rotation) }
        end

        def self.Na__Geometry__BuildPreviewProfilePolyline(profile_data:, path_data:, start_point:, rotation_step:)
            local_profile_points = self.Na__Geometry__BuildLocalProfilePoints(profile_data)
            frame_transform = self.Na__Geometry__BuildPathFrame(start_point, path_data)
            self.Na__Geometry__TransformProfilePoints(local_profile_points, frame_transform, rotation_step)
        end

        def self.Na__Geometry__BuildProfileAlongPath(model:, profile_data:, path_data:, start_point:, rotation_step:)
            return { 'isBuilt' => false, 'reason' => 'No active model.' } unless model

            local_profile_points = self.Na__Geometry__BuildLocalProfilePoints(profile_data)
            return { 'isBuilt' => false, 'reason' => 'Selected profile has invalid points.' } if local_profile_points.length < 3

            frame_transform = self.Na__Geometry__BuildPathFrame(start_point, path_data)
            return { 'isBuilt' => false, 'reason' => 'Path frame could not be built.' } unless frame_transform

            transformed_profile = self.Na__Geometry__TransformProfilePoints(local_profile_points, frame_transform, rotation_step)
            return { 'isBuilt' => false, 'reason' => 'Failed to build transformed profile.' } if transformed_profile.length < 3

            ordered_points = path_data[:ordered_points] || []
            if ordered_points.length < 2
                return { 'isBuilt' => false, 'reason' => 'Path must contain at least two points.' }
            end

            model.start_operation('Na__ProfilePathTracer__GenerateProfile', true)
            group = model.active_entities.add_group
            group.name = "Na__ProfileTrace__#{profile_data['profileKey'] || 'Unnamed'}"
            entities = group.entities

            path_edges = []
            (0...(ordered_points.length - 1)).each do |index|
                edge = entities.add_line(ordered_points[index], ordered_points[index + 1])
                path_edges << edge if edge
            end

            if path_data[:is_closed_loop]
                closing_edge = entities.add_line(ordered_points[-1], ordered_points[0])
                path_edges << closing_edge if closing_edge
            end

            profile_face = entities.add_face(transformed_profile)
            unless profile_face
                model.abort_operation
                return { 'isBuilt' => false, 'reason' => 'Could not create profile face.' }
            end

            profile_face.reverse! if profile_face.normal.dot(frame_transform.zaxis) < 0
            profile_face.followme(path_edges)
            entities.erase_entities(profile_face) if profile_face.valid?

            model.commit_operation
            { 'isBuilt' => true, 'groupName' => group.name }
        rescue => error
            model.abort_operation if model
            { 'isBuilt' => false, 'reason' => error.message }
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
