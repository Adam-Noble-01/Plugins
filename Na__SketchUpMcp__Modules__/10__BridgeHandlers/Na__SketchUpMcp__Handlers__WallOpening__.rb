# =============================================================================
# NA SKETCHUP MCP - HANDLERS - WALL OPENING EDIT
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__WallOpening__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__WallOpening
# PURPOSE    : wall_opening_edit - cut or fill rectangular openings in a
#              manifold wall solid with tag/material/edge-colour preservation,
#              manifoldness + volume-delta verification, and automatic rollback.
# CREATED    : 26-Nov-2026 (1.0.44)
#
# HOW IT WORKS
#   - Validates that wall_id is a closed manifold Group with outward normals.
#   - Captures the wall's dominant edge material (falling back to SSOT
#     MTE102__LineColour__SoftBlack__L20) and dominant front/back face material.
#   - Converts each opening spec (either an axis-aligned world box {min, max}
#     or a wall-plane opening {plane, span, z} with automatic overcut past both
#     wall faces) into a clean manifold prism in the wall's parent coordinates.
#   - Runs sequential SketchUp solid subtract (cut) or union (fill) on a copy
#     of the wall, verifying manifold? at every step.
#   - Repaints any newly cut reveal faces and nil reveal edges so zero unpainted
#     edges or unpainted backfaces remain.
#   - Transplants the verified solid back into the wall (keep_id: true, default)
#     preserving persistent_id, name, tag, material and attributes.
#   - Verifies final manifold?, positive signed volume, non-zero volume delta
#     (unless allow_noop: true) and optional expected_volume_delta; any failure
#     raises Na__McpError so Na__CommandRouter aborts and rolls back cleanly.
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Handlers__WallOpening

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_OPERATIONS            = %w[cut fill].freeze
        NA_AXES                  = %w[x y z].freeze
        NA_PLANE_AXES            = %w[x y].freeze
        NA_DEFAULT_OVERCUT_MM    = 10.0
        NA_DEFAULT_EDGE_MATERIAL = 'MTE102__LineColour__SoftBlack__L20'.freeze
        NA_CUBIC_MM_PER_IN3      = 25.4**3

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | wall_opening_edit
# -----------------------------------------------------------------------------

        def self.Na__Handlers__WallOpening__Edit(params, ctx)
            model = ctx[:model]
            unit  = ctx[:unit]

            wall_id = Na__Params.Na__Params__Integer(params, 'wall_id', nil, required: true)
            wall    = Na__EntityResolver.Na__EntityResolver__RequireInstance(model, wall_id, 'wall_id')
            na_validate_wall(wall, model)

            raw_openings = Na__Params.Na__Params__Array(params, 'openings', nil, required: true, min_items: 1, max_items: 40)
            default_plane = Na__Params.Na__Params__Has(params, 'plane') ? na_parse_plane(params['plane'], unit, 'plane') : nil
            default_overcut_in = Na__Params.Na__Params__Has(params, 'overcut') ?
                                     Na__Units.Na__Units__NonNegative(params['overcut'], unit, 'overcut') :
                                     (NA_DEFAULT_OVERCUT_MM / 25.4)
            keep_id       = Na__Params.Na__Params__Boolean(params, 'keep_id', true)
            allow_noop    = Na__Params.Na__Params__Boolean(params, 'allow_noop', false)
            repaint_all   = Na__Params.Na__Params__Boolean(params, 'repaint_all_edges', false)

            specs = raw_openings.each_with_index.map do |entry, idx|
                na_parse_opening(entry, idx, default_plane, default_overcut_in, unit)
            end

            container_path = if Na__Params.Na__Params__Has(params, 'path')
                                 Na__Coordinates.Na__Coordinates__PathFromIds(model, Na__Params.Na__Params__IdArray(params, 'path'))
                             else
                                 Na__Coordinates.Na__Coordinates__ContainerPathForEntity(model, wall, ctx[:warnings])
                             end
            parent_to_world = Na__Coordinates.Na__Coordinates__ReportedToWorld(model, container_path)
            parent_det      = na_transform_det(parent_to_world)
            wall_to_world   = parent_to_world * wall.transformation

            before_vol_mm3 = (wall.volume.to_f * parent_det * NA_CUBIC_MM_PER_IN3).round(2)
            edge_mat       = na_resolve_edge_material(model, wall, params, ctx)
            face_mat       = na_resolve_face_material(model, wall, params)

            # Work on a sibling copy inside wall.parent.entities so wall is untouched until transplant.
            parent_ents = wall.parent.entities
            working     = keep_id ? wall.copy : wall
            properties  = keep_id ? nil : na_capture_properties(wall)

            applied = []
            specs.each_with_index do |spec, idx|
                box_group = na_create_world_box(parent_ents, parent_to_world, spec[:min], spec[:max])
                unless box_group && box_group.valid? && box_group.manifold?
                    box_group.erase! if box_group && box_group.valid?
                    raise Na__McpError.new('operation_failed', "Could not construct manifold cutter box for openings[#{idx}].",
                                           'Check that opening dimensions are positive and non-degenerate.')
                end

                result = spec[:operation] == 'fill' ? working.union(box_group) : box_group.subtract(working)
                unless result && result.valid?
                    raise Na__McpError.new('operation_failed',
                                           "SketchUp solid #{spec[:operation]} returned nil on wall #{wall_id} at openings[#{idx}]. The operation was rolled back.",
                                           'Increase overcut (default 10 mm) so the cutter clears both wall faces cleanly, or verify the box overlaps the wall.')
                end
                unless result.manifold?
                    raise Na__McpError.new('operation_failed',
                                           "Wall #{wall_id} became non-manifold after openings[#{idx}] (#{Na__SolidHealth.Na__SolidHealth__Describe(result)}). The operation was rolled back.",
                                           'Ensure the opening box does not lie coplanar with an existing edge or sliver face; increase overcut or adjust coordinates by >= 1 mm.')
                end
                working = result
                applied << {
                    'index'     => idx,
                    'operation' => spec[:operation],
                    'min'       => spec[:min].map { |v| Na__Units.Na__Units__FromInches(v, unit).round(2) },
                    'max'       => spec[:max].map { |v| Na__Units.Na__Units__FromInches(v, unit).round(2) },
                    'box_vol_mm3' => (((spec[:max][0] - spec[:min][0]) * (spec[:max][1] - spec[:min][1]) * (spec[:max][2] - spec[:min][2])) * NA_CUBIC_MM_PER_IN3).round(1)
                }
            end

            # Paint newly cut reveal faces and nil edges before transplant.
            na_paint_faces(working, face_mat) if face_mat
            painted_edges = na_paint_edges(working, edge_mat, repaint_all) if edge_mat

            if keep_id
                transplant = Na__Transplant.Na__Transplant__Into(wall, working)
                ctx[:warnings] << "keep_id: #{transplant['fallback']}." if transplant['fallback']
                target_out = wall
                # Re-ensure zero nil edges after transplant in case edge-colour restore left any new seam nil.
                na_paint_edges(target_out, edge_mat, false) if edge_mat
            else
                na_restore_properties(working, properties)
                target_out = working
            end

            unless target_out.valid? && target_out.manifold?
                raise Na__McpError.new('operation_failed',
                                       "Final wall solid #{wall_id} failed manifold verification (#{Na__SolidHealth.Na__SolidHealth__Describe(target_out)}). Rolled back.",
                                       'Check the opening coordinates against adjacent wall edges and retry.')
            end
            signed_vol = Na__SolidHealth.Na__SolidHealth__SignedVolume(target_out.definition.entities.grep(Sketchup::Face))
            if signed_vol <= 0.0
                raise Na__McpError.new('operation_failed',
                                       "Final wall solid #{wall_id} ended inside-out (negative signed volume). Rolled back.",
                                       'Verify the input wall has outward-facing normals before cutting.')
            end

            after_vol_mm3  = (target_out.volume.to_f * parent_det * NA_CUBIC_MM_PER_IN3).round(2)
            delta_vol_mm3  = (after_vol_mm3 - before_vol_mm3).round(2)

            if !allow_noop && delta_vol_mm3.abs < 1.0
                raise Na__McpError.new('operation_failed',
                                       "Wall #{wall_id} volume did not change (delta #{delta_vol_mm3} mm3): the opening box(es) missed the wall solid. Rolled back.",
                                       'Check the wall bounds with geometry_measure bounds or pass allow_noop: true if a zero-change check is intended.')
            end

            if Na__Params.Na__Params__Has(params, 'expected_volume_delta_mm3')
                expected = Na__Params.Na__Params__Number(params, 'expected_volume_delta_mm3', nil, required: true)
                tol_pct  = Na__Params.Na__Params__Number(params, 'volume_tolerance_pct', 5.0, min: 0.01, max: 100.0)
                allowed  = [expected.abs * (tol_pct / 100.0), 100.0].max
                if (delta_vol_mm3 - expected).abs > allowed
                    raise Na__McpError.new('operation_failed',
                                           "Volume delta #{delta_vol_mm3} mm3 differed from expected #{expected} mm3 by more than #{tol_pct}%. Rolled back.",
                                           'Check wall thickness, existing openings overlap, or expected_volume_delta_mm3 sign (negative for cuts, positive for fills).')
                end
            end

            unpainted = target_out.definition.entities.grep(Sketchup::Edge).count { |edge| edge.material.nil? }
            {
                'wall_id'            => target_out.persistent_id,
                'name'               => target_out.name.to_s,
                'kept_id'            => keep_id,
                'manifold'           => target_out.manifold?,
                'openings_applied'   => applied.length,
                'openings'           => applied,
                'before_volume_mm3'  => before_vol_mm3,
                'after_volume_mm3'   => after_vol_mm3,
                'volume_delta_mm3'   => delta_vol_mm3,
                'edge_material'      => edge_mat ? edge_mat.name : nil,
                'edges_painted'      => painted_edges.to_i,
                'unpainted_edges'    => unpainted,
                'summary'            => "Applied #{applied.length} wall opening edit(s) to #{target_out.name.empty? ? "id #{target_out.persistent_id}" : target_out.name}: " \
                                        "manifold solid, volume delta #{delta_vol_mm3.round} mm3, #{unpainted} unpainted edges."
            }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Pure Spec Resolution (tested offline in Tests__BridgeCore)
# -----------------------------------------------------------------------------

        # Resolves a single opening specification into world-inch {operation:, min: [x,y,z], max: [x,y,z]}.
        # Pure maths helper — called directly by BridgeCore unit tests.
        def self.Na__Handlers__WallOpening__ResolveOpeningBox(spec, default_plane, default_overcut_in, to_inches)
            op = spec['operation'] ? spec['operation'].to_s : 'cut'
            unless NA_OPERATIONS.include?(op)
                raise Na__McpError.new('invalid_params', "Invalid opening operation '#{op}'.", "Use 'cut' or 'fill'.")
            end

            overcut_in = spec.key?('overcut') && !spec['overcut'].nil? ? to_inches.call(spec['overcut'], 'overcut') : default_overcut_in
            overcut_in = 0.0 if op == 'fill' && !(spec.key?('overcut') && !spec['overcut'].nil?)

            if spec['min'] && spec['max']
                pmin = spec['min'].map { |v| to_inches.call(v, 'min') }
                pmax = spec['max'].map { |v| to_inches.call(v, 'max') }
                if pmin.length != 3 || pmax.length != 3
                    raise Na__McpError.new('invalid_params', 'min and max must each be 3 numbers [x, y, z].', nil)
                end
                bmin = [0, 1, 2].map { |i| [pmin[i], pmax[i]].min }
                bmax = [0, 1, 2].map { |i| [pmin[i], pmax[i]].max }
                if spec['through_axis']
                    idx = NA_AXES.index(spec['through_axis'].to_s.downcase)
                    raise Na__McpError.new('invalid_params', "through_axis must be 'x', 'y' or 'z'.", nil) unless idx

                    bmin[idx] -= overcut_in
                    bmax[idx] += overcut_in
                end
                na_check_box_positive(bmin, bmax)
                return { operation: op, min: bmin, max: bmax }
            end

            plane = spec['plane'] || default_plane
            unless plane && spec['span'] && spec['z']
                raise Na__McpError.new('invalid_params',
                                       'Each opening needs either {min, max} or {plane (or top-level plane), span: [u0, u1], z: [z0, z1]}.',
                                       'Example: plane: {axis: "x", value: 9110, depth: 250, outside: [1, 0, 0]}, span: [5995, 7195], z: [1215, 2890].')
            end

            span = spec['span']
            zr   = spec['z']
            unless span.is_a?(Array) && span.length == 2 && zr.is_a?(Array) && zr.length == 2
                raise Na__McpError.new('invalid_params', 'span and z must each be a 2-number range [start, end].', nil)
            end

            u0, u1 = span.map { |v| to_inches.call(v, 'span') }.minmax
            z0, z1 = zr.map { |v| to_inches.call(v, 'z') }.minmax

            axis     = plane[:axis]
            val_in   = plane[:value_in]
            depth_in = plane[:depth_in]
            out_sign = plane[:out_sign]

            # Outer face is at val_in; inner face is val_in - out_sign * depth_in.
            inner_in = val_in - out_sign * depth_in
            t0, t1   = [val_in, inner_in].minmax
            t0      -= overcut_in
            t1      += overcut_in

            bmin, bmax = if axis == 'x'
                             [[t0, u0, z0], [t1, u1, z1]]
                         else
                             [[u0, t0, z0], [u1, t1, z1]]
                         end
            na_check_box_positive(bmin, bmax)
            { operation: op, min: bmin, max: bmax }
        end

        def self.na_check_box_positive(bmin, bmax)
            (0..2).each do |i|
                next if (bmax[i] - bmin[i]) > 1.0e-4

                raise Na__McpError.new('invalid_params', "Opening box has zero thickness along #{'XYZ'[i]}.",
                                       'Ensure span, z, and wall depth (or min/max) have strictly distinct start and end values.')
            end
        end
        private_class_method :na_check_box_positive

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers
# -----------------------------------------------------------------------------

        def self.na_validate_wall(wall, model)
            unless wall.is_a?(Sketchup::Group)
                raise Na__McpError.new('wrong_type', "wall_id #{wall.persistent_id} is a component instance, not a group.",
                                       'wall_opening_edit edits a wall Group solid (make a unique group first if needed).')
            end
            if Na__Coordinates.Na__Coordinates__InstanceIsOpen(model, wall)
                raise Na__McpError.new('context_error', "Wall #{wall.persistent_id} is open for editing.",
                                       'Close it first with context_set {action: "close_all"}.')
            end
            unless wall.manifold?
                raise Na__McpError.new('invalid_params', "Wall #{wall.persistent_id} is not a manifold solid: #{Na__SolidHealth.Na__SolidHealth__Describe(wall)}.",
                                       'Repair holes or stray edges before cutting openings.')
            end
            signed = Na__SolidHealth.Na__SolidHealth__SignedVolume(wall.definition.entities.grep(Sketchup::Face))
            return if signed > 0.0

            raise Na__McpError.new('invalid_params', "Wall #{wall.persistent_id} is inside-out (negative signed volume).",
                                   "Reverse its faces first with geometry_edit {operation: \"reverse_faces\", ids: [#{wall.persistent_id}]}.")
        end
        private_class_method :na_validate_wall

        def self.na_parse_plane(raw, unit, label)
            unless raw.is_a?(Hash)
                raise Na__McpError.new('invalid_params', "#{label} must be an object.", nil)
            end
            axis = Na__Params.Na__Params__Enum(raw, 'axis', NA_PLANE_AXES, nil, required: true)
            val_in = if Na__Params.Na__Params__Has(raw, 'value_mm')
                         Na__Params.Na__Params__Number(raw, 'value_mm', nil, required: true) / 25.4
                     else
                         Na__Units.Na__Units__ToInches(Na__Params.Na__Params__Required(raw, 'value'), unit, "#{label}.value")
                     end
            depth_in = if Na__Params.Na__Params__Has(raw, 'depth_mm')
                           Na__Params.Na__Params__Number(raw, 'depth_mm', nil, required: true, min: 1.0) / 25.4
                       else
                           Na__Units.Na__Units__Positive(Na__Params.Na__Params__Required(raw, 'depth'), unit, "#{label}.depth")
                       end
            out_vec = Na__Units.Na__Units__Direction(Na__Params.Na__Params__Required(raw, 'outside'), "#{label}.outside")
            comp = axis == 'x' ? out_vec.x : out_vec.y
            if comp.abs < 0.5
                raise Na__McpError.new('invalid_params', "#{label}.outside must point along ±#{axis.upcase}.",
                                       "e.g. #{axis == 'x' ? '[1, 0, 0] or [-1, 0, 0]' : '[0, 1, 0] or [0, -1, 0]'}.")
            end
            { axis: axis, value_in: val_in, depth_in: depth_in, out_sign: comp >= 0 ? 1.0 : -1.0 }
        end
        private_class_method :na_parse_plane

        def self.na_parse_opening(entry, idx, default_plane, default_overcut_in, unit)
            unless entry.is_a?(Hash)
                raise Na__McpError.new('invalid_params', "openings[#{idx}] must be an object.", nil)
            end
            local_spec = entry.dup
            if Na__Params.Na__Params__Has(entry, 'plane')
                local_spec['plane'] = na_parse_plane(entry['plane'], unit, "openings[#{idx}].plane")
            end
            converter = lambda { |v, lbl| Na__Units.Na__Units__ToInches(v, unit, "openings[#{idx}].#{lbl}") }
            Na__Handlers__WallOpening__ResolveOpeningBox(local_spec, default_plane, default_overcut_in, converter)
        end
        private_class_method :na_parse_opening

        def self.na_create_world_box(parent_ents, parent_to_world, bmin, bmax)
            inv = parent_to_world.inverse
            x0, y0, z0 = bmin
            x1, y1, z1 = bmax
            corners = [
                [x0, y0, z0], [x1, y0, z0], [x1, y1, z0], [x0, y1, z0],
                [x0, y0, z1], [x1, y0, z1], [x1, y1, z1], [x0, y1, z1]
            ].map { |c| inv * Geom::Point3d.new(c[0], c[1], c[2]) }

            grp = parent_ents.add_group
            ge  = grp.entities
            faces = [
                ge.add_face(corners[0], corners[3], corners[2], corners[1]),
                ge.add_face(corners[4], corners[5], corners[6], corners[7]),
                ge.add_face(corners[0], corners[1], corners[5], corners[4]),
                ge.add_face(corners[2], corners[3], corners[7], corners[6]),
                ge.add_face(corners[0], corners[4], corners[7], corners[3]),
                ge.add_face(corners[1], corners[2], corners[6], corners[5])
            ].compact

            signed = Na__SolidHealth.Na__SolidHealth__SignedVolume(faces)
            faces.each(&:reverse!) if signed < 0.0
            grp
        end
        private_class_method :na_create_world_box

        def self.na_resolve_edge_material(model, wall, params, ctx)
            if Na__Params.Na__Params__Has(params, 'edge_material')
                name = Na__Params.Na__Params__String(params, 'edge_material', nil, required: true)
                mat = model.materials[name]
                return mat if mat

                ctx[:warnings] << "edge_material '#{name}' was not found in model materials; falling back to wall's dominant edge material."
            end

            counts = Hash.new(0)
            wall.definition.entities.grep(Sketchup::Edge).each do |edge|
                counts[edge.material] += 1 if edge.material
            end
            return counts.max_by { |_m, c| c }.first unless counts.empty?

            model.materials[NA_DEFAULT_EDGE_MATERIAL]
        end
        private_class_method :na_resolve_edge_material

        def self.na_resolve_face_material(model, wall, params)
            if Na__Params.Na__Params__Has(params, 'face_material')
                name = Na__Params.Na__Params__String(params, 'face_material', nil, required: true)
                return model.materials[name] if model.materials[name]
            end
            counts = Hash.new(0)
            wall.definition.entities.grep(Sketchup::Face).each do |face|
                counts[face.material] += 1 if face.material
            end
            counts.empty? ? nil : counts.max_by { |_m, c| c }.first
        end
        private_class_method :na_resolve_face_material

        def self.na_paint_faces(group, mat)
            group.definition.entities.grep(Sketchup::Face).each do |face|
                face.material      = mat if face.material.nil?
                face.back_material = mat if face.back_material.nil?
            end
        end
        private_class_method :na_paint_faces

        def self.na_paint_edges(group, mat, repaint_all)
            count = 0
            group.definition.entities.grep(Sketchup::Edge).each do |edge|
                next unless repaint_all || edge.material.nil?

                edge.material = mat
                count += 1
            end
            count
        end
        private_class_method :na_paint_edges

        def self.na_transform_det(tr)
            det = (tr.xaxis * tr.yaxis).dot(tr.zaxis).abs
            det > 1.0e-9 ? det : 1.0
        end
        private_class_method :na_transform_det

        def self.na_capture_properties(target)
            attrs = []
            (target.attribute_dictionaries || []).each do |dict|
                pairs = []
                dict.each_pair { |k, v| pairs << [k, v] }
                attrs << [dict.name, pairs]
            end
            {
                name: target.name.to_s, layer: target.layer, material: target.material,
                casts_shadows: target.casts_shadows?, receives_shadows: target.receives_shadows?,
                attributes: attrs
            }
        end
        private_class_method :na_capture_properties

        def self.na_restore_properties(target, props)
            return unless props

            target.name             = props[:name]
            target.layer            = props[:layer] if props[:layer]
            target.material         = props[:material] if props[:material]
            target.casts_shadows    = props[:casts_shadows]
            target.receives_shadows = props[:receives_shadows]
            props[:attributes].each do |dict_name, pairs|
                pairs.each { |k, v| target.set_attribute(dict_name, k, v) }
            end
        end
        private_class_method :na_restore_properties

# endregion -------------------------------------------------------------------

    end # module Na__Handlers__WallOpening
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
