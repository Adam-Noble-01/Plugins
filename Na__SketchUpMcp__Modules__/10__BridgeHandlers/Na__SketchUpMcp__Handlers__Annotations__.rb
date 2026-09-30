# =============================================================================
# NA SKETCHUP MCP - HANDLERS - ANNOTATIONS, IMAGES, SECTION PLANES
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__Annotations__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__Annotations
# PURPOSE    : annotation_create (leader text, 3D text, linear and radial
#              dimensions, guide lines and points), image_place, section_plane
# CREATED    : 2026
#
# 3D TEXT IS GEOMETRY:
# Entities#add_3d_text writes edges and faces at the collection's origin on its
# XY plane and returns only true/false. So 3D text is always built in its own
# group and placed afterwards with the same position/axes/rotation contract as
# geometry_create_solid.
#
# @delegate: Na__SketchUpMcp__BridgeHelpers__Creation__.rb (parent, coords)
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Handlers__Annotations

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_KINDS = %w[text text_3d dimension_linear dimension_radial guide_line guide_point].freeze
        NA_SECTION_ACTIONS = %w[create activate deactivate update].freeze
        NA_IMAGE_EXTENSIONS = %w[.png .jpg .jpeg .bmp .tif .tiff .gif .psd .tga].freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | annotation_create
# -----------------------------------------------------------------------------

        def self.Na__Handlers__Annotations__Create(params, ctx)
            kind = Na__Params.Na__Params__Enum(params, 'kind', NA_KINDS, nil, required: true)
            return na_text_3d(params, ctx) if kind == 'text_3d'

            prepared = Na__Creation.Na__Creation__Prepare(params.merge('wrap_in' => 'none'), ctx, 'none')
            unit = ctx[:unit]
            created = case kind
                      when 'text'             then na_leader_text(params, prepared, unit)
                      when 'dimension_linear' then na_linear_dimension(params, prepared, unit)
                      when 'dimension_radial' then na_radial_dimension(params, ctx)
                      when 'guide_line'       then na_guide_line(params, prepared, unit)
                      when 'guide_point'      then prepared[:entities].add_cpoint(Na__Creation.Na__Creation__Point(Na__Params.Na__Params__Required(params, 'point'), prepared, unit, 'point'))
                      end
            unless created
                raise Na__McpError.new('operation_failed', "SketchUp did not create the #{kind}.", 'Check the points are distinct and valid.')
            end

            Na__Creation.Na__Creation__ApplyCommonProperties([created], params.reject { |key, _value| key == 'material' }, ctx, false)
            summary = Na__Serializer.Na__Serializer__Summary(created, ctx, nil, true)
            summary['kind'] = kind
            summary
        end

        def self.na_leader_text(params, prepared, unit)
            text = Na__Params.Na__Params__String(params, 'text', nil, required: true)
            point = Na__Creation.Na__Creation__Point(Na__Params.Na__Params__Required(params, 'point'), prepared, unit, 'point')
            offset_values = params['leader_vector'] || [300, 300, 300].map { |millimetres| millimetres / 25.4 / Na__Units::NA_INCHES_PER_UNIT.fetch(unit) }
            offset = prepared[:input_to_reported] * Na__Units.Na__Units__Offset(offset_values, unit, 'leader_vector')
            note = prepared[:entities].add_text(text, point, offset)
            note.display_leader = false if note && Na__Params.Na__Params__Boolean(params, 'leader', true) == false
            note
        end

        def self.na_linear_dimension(params, prepared, unit)
            start_point = Na__Creation.Na__Creation__Point(Na__Params.Na__Params__Required(params, 'start'), prepared, unit, 'start')
            end_point = Na__Creation.Na__Creation__Point(Na__Params.Na__Params__Required(params, 'end'), prepared, unit, 'end')
            if start_point.distance(end_point) < 1.0e-6
                raise Na__McpError.new('invalid_params', 'start and end are the same point.', nil)
            end

            offset_values = params['offset_vector'] || [0, -500 / 25.4 / Na__Units::NA_INCHES_PER_UNIT.fetch(unit), 0]
            offset = prepared[:input_to_reported] * Na__Units.Na__Units__Offset(offset_values, unit, 'offset_vector')
            prepared[:entities].add_dimension_linear(start_point, end_point, offset)
        end

        def self.na_radial_dimension(params, ctx)
            edge = Na__EntityResolver.Na__EntityResolver__RequireOfClass(ctx[:model], Na__Params.Na__Params__Integer(params, 'arc_edge_id', nil, required: true), Sketchup::Edge, 'arc_edge_id')
            curve = edge.curve
            unless curve.is_a?(Sketchup::ArcCurve)
                raise Na__McpError.new('wrong_type', "Edge #{edge.persistent_id} is not part of an arc or circle.", 'Pass an edge of a circle or arc (entity_get shows curve.arc).')
            end

            container_path = Na__Serializer.Na__Serializer__ContainerPath(ctx, edge)
            to_world = Na__Coordinates.Na__Coordinates__ReportedToWorld(ctx[:model], container_path)
            leader_point = if params['leader_point']
                               to_world.inverse * Na__Units.Na__Units__Point(params['leader_point'], ctx[:unit], 'leader_point')
                           else
                               curve.center.offset(curve.xaxis, curve.radius * 1.5)
                           end
            edge.parent.entities.add_dimension_radial(curve, leader_point)
        end

        def self.na_guide_line(params, prepared, unit)
            stipple = Na__Params.Na__Params__Enum(params, 'stipple', ['-', '.', '_', '-.-', ''], '-')
            start_point = Na__Creation.Na__Creation__Point(Na__Params.Na__Params__Required(params, 'start'), prepared, unit, 'start')
            if params['end']
                end_point = Na__Creation.Na__Creation__Point(params['end'], prepared, unit, 'end')
                prepared[:entities].add_cline(start_point, end_point, stipple)
            else
                direction = Na__Creation.Na__Creation__Direction(Na__Params.Na__Params__Required(params, 'direction'), prepared, 'direction')
                prepared[:entities].add_cline(start_point, direction, stipple)
            end
        end

        def self.na_text_3d(params, ctx)
            text = Na__Params.Na__Params__String(params, 'text', nil, required: true)
            unit = ctx[:unit]
            height = Na__Units.Na__Units__PositiveLength(Na__Params.Na__Params__Required(params, 'height'), unit, 'height')
            extrusion = Na__Params.Na__Params__Has(params, 'extrusion') ? Na__Units.Na__Units__ToInches(params['extrusion'], unit, 'extrusion') : 0.0
            alignment = { 'left' => TextAlignLeft, 'center' => TextAlignCenter, 'right' => TextAlignRight }.fetch(
                Na__Params.Na__Params__Enum(params, 'align', %w[left center right], 'left')
            )

            wrap = params['wrap_in'] == 'component' ? 'component' : 'group'
            prepared = Na__Creation.Na__Creation__Prepare(params.merge('wrap_in' => wrap), ctx, 'group')
            made = prepared[:entities].add_3d_text(text, alignment, Na__Params.Na__Params__String(params, 'font', 'Arial'),
                                                   Na__Params.Na__Params__Boolean(params, 'bold', false), Na__Params.Na__Params__Boolean(params, 'italic', false),
                                                   height, 0.0, 0.0, Na__Params.Na__Params__Boolean(params, 'filled', true), extrusion)
            raise Na__McpError.new('operation_failed', 'SketchUp could not create that 3D text.', 'Check the font name is installed.') unless made

            placement = Na__Handlers__Primitives.Na__Handlers__Primitives__InputPlacement(params, unit, [0.0, 0.0, 0.0])
            prepared[:wrapper].transformation = prepared[:input_to_reported] * placement
            words = text.strip.gsub(/\s+/, ' ')
            words = "#{words[0, 40]}..." if words.length > 40
            result = Na__Creation.Na__Creation__Finish(prepared, params, ctx, [], kind: "3D text \"#{words}\"", name_size: false)
            result['kind'] = 'text_3d'
            result
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | image_place
# -----------------------------------------------------------------------------

        def self.Na__Handlers__Annotations__ImagePlace(params, ctx)
            path = File.expand_path(Na__Params.Na__Params__String(params, 'path', nil, required: true))
            raise Na__McpError.new('file_error', "Image not found: #{path}.", nil) unless File.file?(path)
            unless NA_IMAGE_EXTENSIONS.include?(File.extname(path).downcase)
                raise Na__McpError.new('invalid_params', "#{File.extname(path)} is not an image type SketchUp places.", "Use one of: #{NA_IMAGE_EXTENSIONS.join(' ')}.")
            end

            unit = ctx[:unit]
            prepared = Na__Creation.Na__Creation__Prepare(params.merge('wrap_in' => 'none'), ctx, 'none')
            origin = Na__Creation.Na__Creation__Point(params['position'] || [0, 0, 0], prepared, unit, 'position')
            width = Na__Creation.Na__Creation__Length(Na__Params.Na__Params__Required(params, 'width'), prepared, unit, 'width')
            height = Na__Params.Na__Params__Has(params, 'height') ? Na__Creation.Na__Creation__Length(params['height'], prepared, unit, 'height') : 0.0

            image = prepared[:entities].add_image(path, origin, width, height)
            raise Na__McpError.new('operation_failed', 'SketchUp could not place that image.', 'Check the file is a readable image.') unless image

            na_orient_image(image, origin, params, prepared)
            Na__Creation.Na__Creation__ApplyCommonProperties([image], params.reject { |key, _value| key == 'material' }, ctx, false)
            return Na__Serializer.Na__Serializer__Summary(image, ctx, prepared[:container][:path], true) unless Na__Params.Na__Params__Boolean(params, 'as_textured_face', false)

            na_explode_image(image, prepared, ctx)
        end

        # The image lands flat on the XY plane at origin; turn it onto the requested plane.
        def self.na_orient_image(image, origin, params, prepared)
            return unless params['normal'] || params['x_axis']

            normal = Na__Creation.Na__Creation__Direction(params['normal'] || [0, 0, 1], prepared, 'normal', normal: true)
            x_axis = params['x_axis'] ? Na__Creation.Na__Creation__Direction(params['x_axis'], prepared, 'x_axis') : (normal.parallel?(Geom::Vector3d.new(0, 0, 1)) ? Geom::Vector3d.new(1, 0, 0) : normal.axes[0])
            y_axis = normal * x_axis
            orient = Geom::Transformation.axes(origin, x_axis, y_axis, normal) * Geom::Transformation.translation(origin.vector_to(Geom::Point3d.new(0, 0, 0)))
            image.transform!(orient)
        end

        # Image#explode returns [] in current SketchUp, so the new entities are found by difference.
        def self.na_explode_image(image, prepared, ctx)
            before = prepared[:entities].to_a
            image.explode
            created = prepared[:entities].to_a - before
            faces = created.grep(Sketchup::Face)
            result = { 'textured_face_ids' => faces.map(&:persistent_id), 'created' => created.length }
            result['faces'] = faces.first(4).map { |face| Na__Serializer.Na__Serializer__Summary(face, ctx, prepared[:container][:path], false) }
            result
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | section_plane
# -----------------------------------------------------------------------------

        def self.Na__Handlers__Annotations__SectionPlane(params, ctx)
            action = Na__Params.Na__Params__Enum(params, 'action', NA_SECTION_ACTIONS, nil, required: true)
            case action
            when 'create'     then na_section_create(params, ctx)
            when 'activate'   then na_section_activate(params, ctx)
            when 'deactivate' then na_section_deactivate(params, ctx)
            when 'update'     then na_section_update(params, ctx)
            end
        end

        def self.na_section_create(params, ctx)
            prepared = Na__Creation.Na__Creation__Prepare(params.merge('wrap_in' => 'none'), ctx, 'none')
            point = Na__Creation.Na__Creation__Point(Na__Params.Na__Params__Required(params, 'point'), prepared, ctx[:unit], 'point')
            normal = Na__Creation.Na__Creation__Direction(Na__Params.Na__Params__Required(params, 'normal'), prepared, 'normal', normal: true)
            section = prepared[:entities].add_section_plane(point, normal)
            raise Na__McpError.new('operation_failed', 'SketchUp could not create the section plane.', nil) unless section

            na_name_section(section, params)
            if section.name.to_s.strip.empty?
                section.name = Na__Creation.Na__Creation__SectionName(params['point'], params['normal'], ctx[:unit])
                ctx[:warnings] << "No name was given, so the Outliner shows \"#{section.name}\". Pass name so the user can find it."
            end
            section.activate if Na__Params.Na__Params__Boolean(params, 'activate', true)
            Na__Serializer.Na__Serializer__Summary(section, ctx, prepared[:container][:path], true).merge('summary' => 'Section plane created.')
        end

        def self.na_section_activate(params, ctx)
            section = na_require_section(params, ctx)
            section.activate
            { 'id' => section.persistent_id, 'active' => section.active?, 'summary' => 'Section plane activated.' }
        end

        def self.na_section_deactivate(params, ctx)
            entities = if Na__Params.Na__Params__Has(params, 'id')
                           na_require_section(params, ctx).parent.entities
                       else
                           Na__Coordinates.Na__Coordinates__ResolveContainer(ctx[:model], params['parent_id'], nil, ctx[:warnings])[:entities]
                       end
            entities.active_section_plane = nil
            { 'deactivated' => true, 'summary' => 'Section cut switched off in that context.' }
        end

        def self.na_section_update(params, ctx)
            section = na_require_section(params, ctx)
            na_name_section(section, params)
            if Na__Params.Na__Params__Boolean(params, 'flip', false)
                plane = section.get_plane
                section.set_plane(plane.map { |value| -value })
            end
            Na__Serializer.Na__Serializer__Summary(section, ctx, nil, true).merge('summary' => 'Section plane updated.')
        end

        def self.na_require_section(params, ctx)
            Na__EntityResolver.Na__EntityResolver__RequireOfClass(ctx[:model], Na__Params.Na__Params__Integer(params, 'id', nil, required: true), Sketchup::SectionPlane, 'id')
        end

        def self.na_name_section(section, params)
            section.name = params['name'].to_s if params['name']
            return unless params['symbol']

            symbol = params['symbol'].to_s
            raise Na__McpError.new('invalid_params', 'symbol must be 3 characters or fewer.', nil) if symbol.length > 3

            section.symbol = symbol
        end

# endregion -------------------------------------------------------------------

    end # module Na__Handlers__Annotations
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
