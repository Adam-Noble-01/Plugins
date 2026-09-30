# =============================================================================
# NA SKETCHUP MCP - BRIDGE HELPERS - COORDINATES (THE COORDINATE RULE)
# =============================================================================
#
# FILE       : Na__SketchUpMcp__BridgeHelpers__Coordinates__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Coordinates
# PURPOSE    : Carry points and transformations between world space and any
#              container at any nesting depth, open or closed
# CREATED    : 2026
#
# THE RULE (SketchUp API team, via the InsertPrimatives 5.1.2 devlog research):
#   "In the active drawing context and all its parent coordinate systems all
#    coordinates are global. In all other coordinate systems they are local."
#
# ONE FORMULA FOR EVERY CASE:
# Every value SketchUp reports inside a container is the container's true
# (definition-local) value, multiplied by a correction when that definition is
# currently OPEN for editing:
#     reported = open_placement(definition) * local        (open definition)
#     reported = local                                     (closed definition)
# open_placement comes from the open instance's own #transformation, which the
# API reports in world space. The same correction applies to a child instance's
# #transformation, because that value is stored in its parent's entities.
#
# From that:
#   true(instance)        = open_placement(parent_def)^-1 * instance.transformation
#   placement(path)       = true(i1) * true(i2) * ... * true(ik)     (definition -> world)
#   reported_to_world(P)  = placement(P) * open_placement(last_def)^-1
#
# Checks against the devlog table:
#   - the active context: placement = its world placement, correction = the same,
#     so reported_to_world = identity. Work there is entirely in world space.
#   - a closed group inside the open one: its #transformation is already world,
#     reported_to_world = that transformation.
#   - a closed group elsewhere: the plain product of #transformation values.
#   - another instance of a definition that is open elsewhere: its entities
#     report the OPEN copy's world coordinates, and the correction removes them.
#
# CONSEQUENCES FOR CALLERS:
#   - points into container C:          reported = reported_to_world(C)^-1 * world
#   - a world transform T for C's items: reported = W^-1 * T * W
#   - a new group in any container:     pin it to identity FIRST (Na__Coordinates__PinGroupToIdentity)
#   - Face#pushpull takes a scalar in definition units (believed; measured only at
#     the root): divide the world distance by the scale along the normal.
#
# @delegate: Na__SketchUpMcp__BridgeHelpers__LinearMath__.rb (all plain-array maths)
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Coordinates

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_MAX_PATH_DEPTH = 64

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Reading Transformation Parts (documented API only)
# -----------------------------------------------------------------------------

        def self.Na__Coordinates__Identity
            Geom::Transformation.new
        end

        def self.Na__Coordinates__OriginArray(transformation)
            origin = Geom::Point3d.new(0, 0, 0).transform(transformation)
            [origin.x.to_f, origin.y.to_f, origin.z.to_f]
        end

        # The 3x3 linear part as [column_x, column_y, column_z]. Built from point
        # differences so SketchUp's homogeneous (w) scale is divided out correctly.
        def self.Na__Coordinates__LinearColumns(transformation)
            origin = self.Na__Coordinates__OriginArray(transformation)
            [[1, 0, 0], [0, 1, 0], [0, 0, 1]].map do |axis|
                tip = Geom::Point3d.new(*axis).transform(transformation)
                [tip.x.to_f - origin[0], tip.y.to_f - origin[1], tip.z.to_f - origin[2]]
            end
        end

        def self.Na__Coordinates__Decompose(transformation)
            Na__LinearMath.Na__LinearMath__DecomposePlacement(
                self.Na__Coordinates__OriginArray(transformation),
                self.Na__Coordinates__LinearColumns(transformation)
            )
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Open Contexts
# -----------------------------------------------------------------------------

        def self.Na__Coordinates__ActivePath(model)
            model.active_path || []
        end

        def self.Na__Coordinates__InstanceIsOpen(model, instance)
            self.Na__Coordinates__ActivePath(model).include?(instance)
        end

        # { ComponentDefinition => world placement of its open instance }
        def self.na_open_placements(model)
            self.Na__Coordinates__ActivePath(model).each_with_object({}) do |instance, lookup|
                lookup[instance.definition] = instance.transformation
            end
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Placement and Reported-to-World
# -----------------------------------------------------------------------------

        # Definition coordinates of path.last's definition -> world. [] -> identity.
        def self.Na__Coordinates__PlacementForPath(model, path)
            open_placements = na_open_placements(model)
            placement = self.Na__Coordinates__Identity
            parent_definition = nil

            path.each do |instance|
                parent_correction = parent_definition ? open_placements[parent_definition] : nil
                true_transformation = parent_correction ? parent_correction.inverse * instance.transformation : instance.transformation
                placement = placement * true_transformation
                parent_definition = instance.definition
            end
            placement
        end

        # Coordinates as REPORTED by entities inside path.last's definition -> world.
        def self.Na__Coordinates__ReportedToWorld(model, path)
            return self.Na__Coordinates__Identity if path.empty?

            placement = self.Na__Coordinates__PlacementForPath(model, path)
            correction = na_open_placements(model)[path.last.definition]
            correction ? placement * correction.inverse : placement
        end

        # World placement of an instance reached through container_path.
        def self.Na__Coordinates__InstanceWorldPlacement(model, container_path, instance)
            self.Na__Coordinates__PlacementForPath(model, container_path + [instance])
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Path Discovery
# -----------------------------------------------------------------------------

        # The instance path (root -> ... -> instance whose definition holds the entity).
        # Root entities return []. Warnings explain any ambiguity.
        def self.Na__Coordinates__ContainerPathForEntity(model, entity, warnings = nil)
            parent = entity.parent
            return [] if parent.nil? || parent.is_a?(Sketchup::Model)

            na_path_to_definition(model, parent, warnings, 0)
        end

        # ids: persistent ids of Group/ComponentInstance from the root, each nested in the previous.
        def self.Na__Coordinates__PathFromIds(model, ids)
            path = ids.map do |persistent_id|
                entity = Na__EntityResolver.Na__EntityResolver__Find(model, persistent_id)
                unless entity && Na__EntityResolver.Na__EntityResolver__IsInstance(entity)
                    raise Na__McpError.new('invalid_params', "path id #{persistent_id} is not a Group or ComponentInstance.",
                                           'A path lists the persistent ids of the groups/components from the model root down to the container.')
                end

                entity
            end
            na_validate_chain(path)
            path
        end

        def self.na_validate_chain(path)
            path.each_with_index do |instance, index|
                expected_parent = index.zero? ? nil : path[index - 1].definition
                actual_parent = instance.parent
                chained = index.zero? ? actual_parent.is_a?(Sketchup::Model) : actual_parent == expected_parent
                next if chained

                raise Na__McpError.new('invalid_params', "path is broken at index #{index}: #{instance.persistent_id} is not inside the previous instance.",
                                       'Give ids from the model root downwards, each one nested in the one before it (outliner_tree shows the nesting).')
            end
        end

        def self.na_path_to_definition(model, definition, warnings, depth)
            if depth > NA_MAX_PATH_DEPTH
                raise Na__McpError.new('operation_failed', 'Nesting deeper than 64 levels; cannot resolve the instance path.', nil)
            end

            active_path = self.Na__Coordinates__ActivePath(model)
            active_path.each_with_index do |instance, index|
                return active_path[0..index] if instance.definition == definition
            end

            instances = definition.instances
            if instances.empty?
                warnings << "Definition '#{definition.name}' has no instances; coordinates are its own local axes." if warnings
                return []
            end

            if instances.length > 1 && warnings
                warnings << "Definition '#{definition.name}' is used #{instances.length} times; world values use its first " \
                            "instance (id #{instances.first.persistent_id}). Pass 'path' to choose another copy."
            end
            na_path_to_instance(model, instances.first, warnings, depth + 1)
        end

        def self.na_path_to_instance(model, instance, warnings, depth)
            parent = instance.parent
            return [instance] if parent.nil? || parent.is_a?(Sketchup::Model)

            na_path_to_definition(model, parent, warnings, depth) + [instance]
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Container Resolution (where new geometry goes)
# -----------------------------------------------------------------------------

        # parent_id: nil -> active context, 0 -> model root, else a Group/ComponentInstance id.
        # path_ids:  optional explicit path ending at that instance (for shared definitions).
        # Returns { entities:, path:, to_world:, owner:, label: }
        def self.Na__Coordinates__ResolveContainer(model, parent_id, path_ids = nil, warnings = nil)
            if parent_id.nil?
                path = self.Na__Coordinates__ActivePath(model)
                return na_container_hash(model.active_entities, path, self.Na__Coordinates__ReportedToWorld(model, path),
                                         path.last, path.empty? ? 'model root (active context)' : "active context (#{path.length} deep)")
            end

            if parent_id.to_i.zero?
                return na_container_hash(model.entities, [], self.Na__Coordinates__Identity, nil, 'model root')
            end

            instance = Na__EntityResolver.Na__EntityResolver__RequireInstance(model, parent_id, 'parent_id')
            path = if path_ids && !path_ids.empty?
                       explicit = self.Na__Coordinates__PathFromIds(model, path_ids)
                       explicit = explicit + [instance] unless explicit.last == instance
                       na_validate_chain(explicit)
                       explicit
                   else
                       self.Na__Coordinates__ContainerPathForEntity(model, instance, warnings) + [instance]
                   end

            na_container_hash(instance.definition.entities, path, self.Na__Coordinates__ReportedToWorld(model, path), instance,
                              "inside #{Na__EntityResolver.Na__EntityResolver__TypeName(instance)} #{Na__EntityResolver.Na__EntityResolver__DisplayName(instance).inspect} (id #{instance.persistent_id})")
        end

        def self.na_container_hash(entities, path, to_world, owner, label)
            { entities: entities, path: path, to_world: to_world, owner: owner, label: label }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Conversions
# -----------------------------------------------------------------------------

        def self.Na__Coordinates__WorldToReported(point, to_world)
            to_world.inverse * point
        end

        def self.Na__Coordinates__ReportedToWorldPoint(point, to_world)
            to_world * point
        end

        # A world-space transformation expressed in a container's reported space.
        def self.Na__Coordinates__WorldTransformToReported(world_transformation, to_world)
            to_world.inverse * world_transformation * to_world
        end

        # Axis-aligned world box around a reported-space bounding box. [min, max] in inches.
        def self.Na__Coordinates__WorldBoundsArrays(bounds, to_world)
            return nil if bounds.nil? || bounds.empty?

            corners = (0..7).map { |index| to_world * bounds.corner(index) }
            minimum = [0, 1, 2].map { |axis| corners.map { |corner| corner.to_a[axis].to_f }.min }
            maximum = [0, 1, 2].map { |axis| corners.map { |corner| corner.to_a[axis].to_f }.max }
            [minimum, maximum]
        end

        # A new group made in any container starts at an unknown placement (inside an
        # open group it inherits the open group's). Pin it so its axes are the
        # container's axes before any point goes in.
        def self.Na__Coordinates__PinGroupToIdentity(group)
            group.transformation = self.Na__Coordinates__Identity
            group
        end

        # World distance -> the scalar Face#pushpull expects for a face inside path.last.
        def self.Na__Coordinates__PushPullScale(model, face, path)
            return 1.0 if path.empty?

            placement = self.Na__Coordinates__PlacementForPath(model, path)
            to_world = self.Na__Coordinates__ReportedToWorld(model, path)
            definition_to_reported = to_world.inverse * placement
            normal = face.normal
            reported_normal = [normal.x.to_f, normal.y.to_f, normal.z.to_f]
            definition_normal = Na__LinearMath.Na__LinearMath__TransposeTimesVector(
                self.Na__Coordinates__LinearColumns(definition_to_reported), reported_normal
            )
            Na__LinearMath.Na__LinearMath__ScaleAlongNormal(self.Na__Coordinates__LinearColumns(placement), definition_normal)
        end

# endregion -------------------------------------------------------------------

    end # module Na__Coordinates
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
