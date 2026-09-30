# =============================================================================
# NA SKETCHUP MCP - BRIDGE HELPERS - CREATION
# =============================================================================
#
# FILE       : Na__SketchUpMcp__BridgeHelpers__Creation__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Creation
# PURPOSE    : Where new geometry goes, in which frame its points are read,
#              and the finishing touches (name, tag, material, component)
# CREATED    : 2026
#
# THE CREATION CONTRACT (every geometry tool follows it):
#   parent_id  omitted -> the active context (the open group, else the root)
#              0       -> the model root, even while a group is open
#              <id>    -> inside that group/component's definition
#   coords     "world" (default) -> points are model-axis positions
#              "local"           -> points are in the parent's own axes
#   wrap_in    "group" (default for solids) -> a new group holds the geometry,
#                 so it can never merge with ("stick to") existing geometry
#              "component" -> the same, converted to a component instance
#              "none"      -> geometry goes straight into the parent
#
# input_to_reported maps an input point into the coordinates the target
# entities report (Na__Coordinates explains "reported"). A new wrapper group is
# pinned to the identity first, so it shares the parent's reported frame and
# the same transform serves both the wrapped and the unwrapped cases.
#
# NOTHING LANDS IN THE OUTLINER AS PLAIN "Group":
# The user finds agent-made objects by name in the Outliner. Every group or
# component the bridge makes gets the agent's name, or else one built from
# its kind and world size ("Box 1200 x 600 x 150"), and the agent is warned so
# it names the next one itself.
#
# @delegate: Na__SketchUpMcp__BridgeHelpers__Coordinates__.rb (the coordinate rule)
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Creation

# -----------------------------------------------------------------------------
# REGION | Prepare
# -----------------------------------------------------------------------------

        # Returns { entities:, input_to_reported:, wrapper:, container:, coords:, path: }
        # path is the instance path whose definition holds the new geometry.
        def self.Na__Creation__Prepare(params, ctx, default_wrap)
            model = ctx[:model]
            container = Na__Coordinates.Na__Coordinates__ResolveContainer(
                model, params['parent_id'], Na__Params.Na__Params__IdArray(params, 'path', required: false), ctx[:warnings]
            )
            wrap = Na__Params.Na__Params__Enum(params, 'wrap_in', %w[group component none], default_wrap)
            coords = Na__Params.Na__Params__Enum(params, 'coords', %w[world local], 'world')

            input_to_reported = if coords == 'world'
                                    container[:to_world].inverse
                                else
                                    container[:to_world].inverse * Na__Coordinates.Na__Coordinates__PlacementForPath(model, container[:path])
                                end

            prepared = { container: container, coords: coords, input_to_reported: input_to_reported, wrap: wrap }
            if wrap == 'none'
                prepared.merge(entities: container[:entities], wrapper: nil, path: container[:path])
            else
                wrapper = container[:entities].add_group
                Na__Coordinates.Na__Coordinates__PinGroupToIdentity(wrapper)
                prepared.merge(entities: wrapper.entities, wrapper: wrapper, path: container[:path] + [wrapper])
            end
        end

        # An input point (wire units, input frame) -> a Point3d in the target's reported frame.
        def self.Na__Creation__Point(values, prepared, unit, label)
            prepared[:input_to_reported] * Na__Units.Na__Units__Point(values, unit, label)
        end

        def self.Na__Creation__Points(list, prepared, unit, label, min_points = 2)
            unless list.is_a?(Array) && list.length >= min_points
                raise Na__McpError.new('invalid_params', "#{label} needs at least #{min_points} points.", nil)
            end

            list.each_with_index.map { |values, index| self.Na__Creation__Point(values, prepared, unit, "#{label}[#{index}]") }
        end

        # An input direction (unitless) carried into the reported frame, normalised. For normals pass normal: true.
        def self.Na__Creation__Direction(values, prepared, label, normal: false)
            direction = Na__Units.Na__Units__Direction(values, label)
            columns = Na__Coordinates.Na__Coordinates__LinearColumns(prepared[:input_to_reported])
            vector = [direction.x.to_f, direction.y.to_f, direction.z.to_f]
            carried = normal ? Na__LinearMath.Na__LinearMath__InverseTransposeTimesVector(columns, vector) : Na__LinearMath.Na__LinearMath__MatrixTimesVector(columns, vector)
            Geom::Vector3d.new(*Na__LinearMath.Na__LinearMath__Normalize(carried || vector))
        end

        # A length in the input frame -> the reported frame (they differ only inside scaled containers).
        def self.Na__Creation__Length(value, prepared, unit, label)
            inches = Na__Units.Na__Units__PositiveLength(value, unit, label)
            columns = Na__Coordinates.Na__Coordinates__LinearColumns(prepared[:input_to_reported])
            scale = Na__LinearMath.Na__LinearMath__Determinant(columns).abs**(1.0 / 3.0)
            scale > 1.0e-12 ? inches * scale : inches
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Face Orientation and Push/Pull
# -----------------------------------------------------------------------------

        # Make face.normal agree with an expected normal given in the reported frame.
        def self.Na__Creation__OrientFace(face, expected_normal)
            normal = face.normal
            dot = (normal.x * expected_normal.x) + (normal.y * expected_normal.y) + (normal.z * expected_normal.z)
            face.reverse! if dot < 0
            face
        end

        # Right-hand-rule normal of reported points, as a Vector3d.
        def self.Na__Creation__WindingNormal(points)
            Geom::Vector3d.new(*Na__LinearMath.Na__LinearMath__PolygonNormal(points.map { |point| [point.x.to_f, point.y.to_f, point.z.to_f] }))
        end

        # Push a face by a distance given in the input frame (world or local).
        def self.Na__Creation__PushPull(face, distance_inches, prepared, ctx)
            scale = prepared[:coords] == 'world' ? Na__Coordinates.Na__Coordinates__PushPullScale(ctx[:model], face, prepared[:path]) : 1.0
            ctx[:warnings] << "Push/pull distance divided by #{scale.round(4)} (scaled container)." if (scale - 1.0).abs > 1.0e-6
            face.pushpull(distance_inches / scale)
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Finish (wrapper properties, component conversion, summary)
# -----------------------------------------------------------------------------

        # Applies name/tag/material, converts to a component when asked, and returns the
        # wrapper (or nil) plus a summary. created: entities made directly (for wrap none).
        # kind names an unnamed wrapper ("Box" -> "Box 1200 x 600 x 150"); name_size false
        # leaves the size off (3D text is named by its words).
        def self.Na__Creation__Finish(prepared, params, ctx, created, kind: 'Group', name_size: true)
            model = ctx[:model]
            wrapper = prepared[:wrapper]

            if wrapper && wrapper.entities.length.zero?
                wrapper.erase!
                raise Na__McpError.new('operation_failed', 'SketchUp created no geometry from those points.',
                                       'Check the points are distinct, not all on one line, and (for faces) planar.')
            end

            if wrapper && prepared[:wrap] == 'component'
                wrapper = wrapper.to_component
                definition_name = params['definition_name'] || params['name']
                wrapper.definition.name = definition_name.to_s if definition_name && !definition_name.to_s.empty?
                wrapper.definition.description = params['description'].to_s if params['description']
            end

            targets = wrapper ? [wrapper] : created.select { |entity| entity.valid? && entity.is_a?(Sketchup::Drawingelement) }
            self.Na__Creation__ApplyCommonProperties(targets, params, ctx, wrapper.nil?)
            self.Na__Creation__EnsureName(wrapper, params, kind, ctx, with_size: name_size) if wrapper

            result = if wrapper
                         Na__Serializer.Na__Serializer__Summary(wrapper, ctx, prepared[:container][:path], true)
                     else
                         na_loose_result(created, ctx, prepared)
                     end
            result['parent'] = prepared[:container][:label]
            result
        end

        # name / tag / material for new or edited entities. Materials on loose geometry go
        # on faces only; tags on loose geometry are allowed but warned about.
        def self.Na__Creation__ApplyCommonProperties(entities, params, ctx, loose)
            model = ctx[:model]
            if params['name'] && !loose
                entities.each { |entity| entity.name = params['name'].to_s if entity.respond_to?(:name=) }
            end
            if params['tag']
                layer = Na__EntityResolver.Na__EntityResolver__ResolveTag(model, params['tag'], true, ctx[:warnings])
                entities.each { |entity| entity.layer = layer if entity.respond_to?(:layer=) }
                ctx[:warnings] << 'Tagged loose edges/faces; SketchUp practice is to tag the group and keep geometry Untagged.' if loose && layer != model.layers[0]
            end
            return unless params.key?('material')

            material = Na__EntityResolver.Na__EntityResolver__ResolveMaterial(model, params['material'], ctx[:warnings])
            entities.each do |entity|
                next if loose && !entity.is_a?(Sketchup::Face)

                entity.material = material if entity.respond_to?(:material=)
            end
        end

        def self.na_loose_result(created, ctx, prepared)
            live = created.select(&:valid?)
            faces = live.grep(Sketchup::Face)
            edges = live.grep(Sketchup::Edge)
            result = {
                'wrapped'  => false,
                'face_ids' => faces.first(100).map(&:persistent_id),
                'edge_ids' => edges.first(200).map(&:persistent_id),
                'counts'   => { 'faces' => faces.length, 'edges' => edges.length }
            }
            bounds = Na__Serializer.Na__Serializer__WorldBoundsOfMany(live, ctx)
            result['bounds'] = Na__Handlers__Selection.Na__Handlers__Selection__BoundsHash(bounds, ctx[:unit]) if bounds
            result['units'] = ctx[:unit]
            result
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Outliner Names
# -----------------------------------------------------------------------------

        # Decimals kept in a generated name: "1200" in mm, "1.2" in m.
        NA_NAME_DECIMALS = { 'mm' => 0, 'cm' => 1, 'm' => 3, 'in' => 2, 'ft' => 2, 'yd' => 2 }.freeze

        # Names an unnamed group/component so the user can find it in the Outliner. The
        # agent's name always wins. A component named only through definition_name keeps
        # an empty instance name, because the Outliner already shows "<definition>".
        # Otherwise a group gets "<kind> <size>" and a component's definition gets it
        # (SketchUp shows "<Box 1200 x 600 x 150>"). Returns the generated name, or nil.
        def self.Na__Creation__EnsureName(instance, params, kind, ctx, with_size: true)
            return nil unless instance && instance.valid? && Na__EntityResolver.Na__EntityResolver__IsInstance(instance)
            return nil unless instance.name.to_s.strip.empty?
            return nil if instance.is_a?(Sketchup::ComponentInstance) && !params['definition_name'].to_s.strip.empty?

            size = with_size ? self.Na__Creation__SizeText(Na__Serializer.Na__Serializer__WorldBoundsOfMany([instance], ctx), ctx[:unit]) : ''
            name = size.empty? ? kind.to_s : "#{kind} #{size}"
            if instance.is_a?(Sketchup::Group)
                instance.name = name
            else
                # A definition name must be unique; SketchUp adds " #1" etc. itself when it is not.
                instance.definition.name = name
                name = instance.definition.name
            end
            ctx[:warnings] << "No name was given, so the Outliner shows \"#{name}\". Pass name (as the user would call it, " \
                              'e.g. "Wall - North") on every create call so the user can find it.'
            name
        end

        # World size corners (inches, from Na__Serializer) -> "1200 x 600 x 150" in the unit,
        # without axes that round to zero (a flat face reads "1200 x 600"); non-mm units say so.
        def self.Na__Creation__SizeText(corners, unit)
            return '' unless corners

            sizes = [0, 1, 2].map { |axis| Na__Units.Na__Units__FromInches(corners[1][axis] - corners[0][axis], unit) }
            parts = sizes.map { |value| self.Na__Creation__CompactNumber(value, unit) }.reject { |text| text == '0' }
            return '' if parts.empty?

            unit == 'mm' ? parts.join(' x ') : "#{parts.join(' x ')} #{unit}"
        end

        # 1200.0004 -> "1200" (mm), 1.25 -> "1.25" (m): the precision a person would type.
        def self.Na__Creation__CompactNumber(value, unit)
            rounded = value.to_f.round(NA_NAME_DECIMALS.fetch(unit, 2))
            rounded = 0 if rounded.zero?
            rounded == rounded.to_i ? rounded.to_i.to_s : rounded.to_s
        end

        # A section plane's Outliner name from its input point and normal: "Plan section at 1200"
        # for a horizontal cut, "Section at x = 3000" for an axis-aligned vertical one. Only a
        # fallback: SketchUp 2026 names new section planes "Section 1", "Section 2"... itself
        # (seen live 30-Sep-2026), and that name is kept.
        def self.Na__Creation__SectionName(point_values, normal_values, unit)
            normal = Array(normal_values).map(&:to_f)
            length = Math.sqrt(normal.sum { |value| value * value })
            return 'Section plane' if normal.length != 3 || length < 1.0e-12

            axis = (0..2).max_by { |index| normal[index].abs }
            return 'Section plane' if normal[axis].abs / length < 0.999

            offset = self.Na__Creation__CompactNumber(Array(point_values)[axis].to_f, unit)
            offset = "#{offset} #{unit}" unless unit == 'mm'
            axis == 2 ? "Plan section at #{offset}" : "Section at #{%w[x y z][axis]} = #{offset}"
        end

# endregion -------------------------------------------------------------------

    end # module Na__Creation
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
