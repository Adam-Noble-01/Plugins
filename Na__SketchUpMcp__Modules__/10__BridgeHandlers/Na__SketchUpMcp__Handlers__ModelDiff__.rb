# =============================================================================
# NA SKETCHUP MCP - HANDLERS - MODEL DIFF (model_snapshot, model_diff)
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__ModelDiff__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__ModelDiff
# PURPOSE    : Measure two versions of the same thing against each other: what
#              an agent built against Adam's redraw, a model before and after he
#              tidied it, this window against a saved snapshot of another. So
#              his silent fixes (repainted edges, a moved wall, a bed made a
#              line) are found by measurement and become lessons
# CREATED    : 12-Nov-2026 (1.0.30)
#
# WHAT A SNAPSHOT HOLDS (always in mm and litres, whatever the call's unit):
# per object: name, definition, tag, world bounds, manifold and volume, counts,
# edge and face material tallies, its plan footprint (every face looking
# straight up, by level, as world loops) and the same for its direct children.
# Saved as JSON, a snapshot from one window or one moment can be compared in
# another: model_snapshot save_path in window A, then model_diff with
# {snapshot: path} in window B.
#
# COMPARISON (Na__PlanGeometry): plan overlap (IoU) by scanline, outline
# distance (Hausdorff, medians, the worst spot), bounds, volume, tallies;
# children paired by name, then by best overlap.
#
# Read-only: no undo step. A snapshot file is written only to save_path.
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Handlers__ModelDiff

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_SNAPSHOT_KIND   = 'Na__SketchUpMcp__Snapshot'.freeze
        NA_MM_PER_INCH     = 25.4
        NA_LITRES_PER_IN3  = (25.4**3) / 1.0e6
        NA_MAX_LOOP_POINTS = 2000

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | model_snapshot
# -----------------------------------------------------------------------------

        def self.Na__Handlers__ModelDiff__Snapshot(params, ctx)
            model = ctx[:model]
            ids = Na__Params.Na__Params__IdArray(params, 'ids', required: true)
            depth = Na__Params.Na__Params__Integer(params, 'child_depth', 1, min: 0, max: 3)
            objects = ids.map { |id| self.Na__Handlers__ModelDiff__ObjectSnapshot(Na__EntityResolver.Na__EntityResolver__RequireInstance(model, id, 'ids'), ctx, depth) }
            snapshot = { 'kind' => NA_SNAPSHOT_KIND, 'version' => 1, 'units' => 'mm', 'volume_units' => 'L',
                         'model' => model.title, 'model_path' => model.path, 'label' => params['label'].to_s,
                         'taken' => Time.now.strftime('%Y-%m-%dT%H:%M:%S%z'), 'objects' => objects }
            out = { 'objects' => objects.map { |object| na_object_brief(object) }, 'units' => 'mm' }
            if Na__Params.Na__Params__Has(params, 'save_path')
                path = File.expand_path(params['save_path'].to_s)
                raise Na__McpError.new('file_error', "Folder does not exist: #{File.dirname(path)}.", nil) unless File.directory?(File.dirname(path))
                if File.exist?(path) && !Na__Params.Na__Params__Boolean(params, 'overwrite', false)
                    raise Na__McpError.new('file_error', "#{path} already exists.", 'Pass overwrite: true or choose another save_path.')
                end

                File.write(path, JSON.generate(snapshot))
                out['saved_to'] = path
                out['summary'] = "Snapshot of #{objects.length} object(s) saved. Compare it anywhere with model_diff {a: {snapshot: \"#{path}\"}, b: {id: ...}}."
            else
                out['snapshot'] = snapshot if Na__Params.Na__Params__Boolean(params, 'include_data', false)
                out['summary'] = "Snapshot of #{objects.length} object(s) taken (pass save_path to keep it for model_diff)."
            end
            out
        end

        # FUNCTION | One Object's Snapshot (mm, litres)
        # ------------------------------------------------------------
        def self.Na__Handlers__ModelDiff__ObjectSnapshot(instance, ctx, depth)
            path = Na__Serializer.Na__Serializer__ContainerPath(ctx, instance)
            world = Na__Serializer.Na__Serializer__ToWorld(ctx, path)
            corners = Na__Serializer.Na__Serializer__TightWorldBounds(instance, ctx, world)
            facts = { 'manifold' => instance.respond_to?(:manifold?) ? instance.manifold? : false }
            if facts['manifold']
                parent_scale = Na__LinearMath.Na__LinearMath__Determinant(world[:columns]).abs
                facts['volume_l'] = (instance.volume.to_f * parent_scale * NA_LITRES_PER_IN3).round(3)
            end

            tallies = { edges: Hash.new(0), faces: Hash.new(0) }
            counts = { 'faces' => 0, 'edges' => 0, 'soft_edges' => 0, 'hidden_edges' => 0, 'instances' => 0 }
            levels = Hash.new { |hash, key| hash[key] = { 'z' => key, 'area_m2' => 0.0, 'loops' => [] } }
            budget = Na__Traversal.Na__Traversal__NewBudget
            Na__Traversal.Na__Traversal__Walk(instance.definition.entities, path + [instance], 12, budget) do |entity, entity_path, _depth|
                case entity
                when Sketchup::Edge
                    counts['edges'] += 1
                    counts['soft_edges'] += 1 if entity.soft?
                    counts['hidden_edges'] += 1 if entity.hidden?
                    tallies[:edges][entity.material ? entity.material.display_name : '(default)'] += 1
                when Sketchup::Face
                    counts['faces'] += 1
                    tallies[:faces][entity.material ? entity.material.display_name : '(default)'] += 1
                    entity_world = Na__Serializer.Na__Serializer__ToWorld(ctx, entity_path)
                    normal = Na__Serializer.Na__Serializer__WorldNormal(entity.normal, entity_world)
                    next unless normal[2] > 0.99

                    loops = entity.loops.map do |loop|
                        loop.vertices.first(NA_MAX_LOOP_POINTS).map do |vertex|
                            point = entity_world[:transform] * vertex.position
                            [(point.x.to_f * NA_MM_PER_INCH).round(1), (point.y.to_f * NA_MM_PER_INCH).round(1), point.z.to_f * NA_MM_PER_INCH]
                        end
                    end
                    z = loops.first.first[2].round
                    level = levels[z]
                    level['area_m2'] += Na__PlanGeometry.Na__PlanGeometry__Area(loops.first).abs / 1.0e6 -
                                        loops.drop(1).sum { |hole| Na__PlanGeometry.Na__PlanGeometry__Area(hole).abs / 1.0e6 }
                    loops.each { |points| level['loops'] << points.map { |point| [point[0], point[1]] } }
                else
                    counts['instances'] += 1 if Na__EntityResolver.Na__EntityResolver__IsInstance(entity)
                end
            end

            object = {
                'id' => instance.persistent_id, 'name' => instance.name.to_s, 'definition' => instance.definition.name.to_s,
                'type' => Na__EntityResolver.Na__EntityResolver__TypeName(instance),
                'tag' => Na__EntityResolver.Na__EntityResolver__TagDisplayName(instance.layer),
                'bounds' => corners ? { 'min' => corners[0].map { |value| (value * NA_MM_PER_INCH).round(1) },
                                        'max' => corners[1].map { |value| (value * NA_MM_PER_INCH).round(1) } } : nil,
                'counts' => counts, 'edge_materials' => tallies[:edges], 'face_materials' => tallies[:faces],
                'levels' => levels.values.sort_by { |level| level['z'] }.map { |level| level.merge('area_m2' => level['area_m2'].round(4)) }
            }.merge(facts)
            object['truncated'] = true if budget[:truncated]
            if depth > 0
                object['children'] = instance.definition.entities.select { |entity| Na__EntityResolver.Na__EntityResolver__IsInstance(entity) }
                                                                 .map { |child| self.Na__Handlers__ModelDiff__ObjectSnapshot(child, ctx, depth - 1) }
            end
            object
        end
        # ---------------------------------------------------------------

        def self.na_object_brief(object)
            {
                'id' => object['id'], 'name' => object['name'], 'bounds' => object['bounds'], 'volume_l' => object['volume_l'],
                'manifold' => object['manifold'], 'plan_area_m2' => object['levels'].sum { |level| level['area_m2'] }.round(3),
                'levels_z' => object['levels'].map { |level| level['z'] }, 'edge_materials' => object['edge_materials'],
                'children' => Array(object['children']).map { |child| child['name'].to_s.empty? ? child['definition'] : child['name'] }
            }.compact
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | model_diff
# -----------------------------------------------------------------------------

        def self.Na__Handlers__ModelDiff__Diff(params, ctx)
            a = na_side(Na__Params.Na__Params__Hash(params, 'a', nil, required: true), ctx, 'a')
            b = na_side(Na__Params.Na__Params__Hash(params, 'b', nil, required: true), ctx, 'b')
            out = { 'a' => na_label(a), 'b' => na_label(b), 'units' => 'mm', 'volume_units' => 'L' }
            out.merge!(na_compare(a, b))
            children_a = Array(a['children'])
            children_b = Array(b['children'])
            unless children_a.empty? && children_b.empty?
                pairs, only_a, only_b = na_pair_children(children_a, children_b)
                out['children'] = pairs.map { |child_a, child_b| { 'a' => na_label(child_a), 'b' => na_label(child_b) }.merge(na_compare(child_a, child_b)) }
                out['only_in_a'] = only_a.map { |child| na_label(child) } unless only_a.empty?
                out['only_in_b'] = only_b.map { |child| na_label(child) } unless only_b.empty?
            end
            out['summary'] = na_summary(out)
            out
        end

        # A side is {id} (live, this window) or {snapshot: path, object: name or id} (a saved snapshot).
        def self.na_side(spec, ctx, label)
            if spec.key?('id')
                instance = Na__EntityResolver.Na__EntityResolver__RequireInstance(ctx[:model], spec['id'], "#{label}.id")
                return self.Na__Handlers__ModelDiff__ObjectSnapshot(instance, ctx, spec.fetch('child_depth', 1).to_i.clamp(0, 3))
            end
            unless spec['snapshot']
                raise Na__McpError.new('invalid_params', "#{label} needs id (an object in this window) or snapshot (a file from model_snapshot save_path).", nil)
            end

            path = File.expand_path(spec['snapshot'].to_s)
            raise Na__McpError.new('file_error', "No snapshot file at #{path}.", 'Take one with model_snapshot {ids, save_path}.') unless File.file?(path)

            data = JSON.parse(File.read(path))
            unless data.is_a?(Hash) && data['kind'] == NA_SNAPSHOT_KIND && data['objects'].is_a?(Array)
                raise Na__McpError.new('file_error', "#{path} is not a model_snapshot file.", nil)
            end

            objects = data['objects']
            chosen = if spec.key?('object')
                         wanted = spec['object']
                         objects.find { |object| object['id'] == wanted || object['name'] == wanted.to_s }
                     else
                         objects.first
                     end
            raise Na__McpError.new('not_found', "#{label}: no object #{spec['object'].inspect} in #{path}.", "It holds: #{objects.map { |object| object['name'] }.join(', ')}.") unless chosen

            chosen.merge('snapshot' => path, 'snapshot_model' => data['model'], 'snapshot_taken' => data['taken'])
        rescue JSON::ParserError => error
            raise Na__McpError.new('file_error', "#{spec['snapshot']} is not valid JSON: #{error.message}", nil)
        end

        def self.na_label(object)
            { 'id' => object['id'], 'name' => object['name'].to_s.empty? ? "<#{object['definition']}>" : object['name'],
              'snapshot' => object['snapshot'], 'model' => object['snapshot_model'], 'taken' => object['snapshot_taken'] }.compact
        end

        def self.na_loops(object)
            Array(object['levels']).flat_map { |level| level['loops'] }
        end

        # FUNCTION | Compare Two Object Snapshots
        # ------------------------------------------------------------
        def self.na_compare(a, b)
            out = {}
            if a['bounds'] && b['bounds']
                size_a = [0, 1, 2].map { |axis| b_round(a['bounds']['max'][axis] - a['bounds']['min'][axis]) }
                size_b = [0, 1, 2].map { |axis| b_round(b['bounds']['max'][axis] - b['bounds']['min'][axis]) }
                out['bounds'] = { 'a' => a['bounds'], 'b' => b['bounds'], 'size_a' => size_a, 'size_b' => size_b,
                                  'min_moved' => [0, 1, 2].map { |axis| b_round(b['bounds']['min'][axis] - a['bounds']['min'][axis]) },
                                  'max_moved' => [0, 1, 2].map { |axis| b_round(b['bounds']['max'][axis] - a['bounds']['max'][axis]) } }
            end
            out['volume_l'] = { 'a' => a['volume_l'], 'b' => b['volume_l'],
                                'change' => a['volume_l'] && b['volume_l'] ? (b['volume_l'] - a['volume_l']).round(3) : nil }.compact
            out['manifold'] = { 'a' => a['manifold'], 'b' => b['manifold'] }
            out['counts'] = { 'a' => a['counts'], 'b' => b['counts'] }
            out['edge_materials'] = na_tally_change(a['edge_materials'], b['edge_materials'])
            out['face_materials'] = na_tally_change(a['face_materials'], b['face_materials'])

            loops_a = na_loops(a)
            loops_b = na_loops(b)
            if !loops_a.empty? && !loops_b.empty?
                plan = Na__PlanGeometry.Na__PlanGeometry__CompareFootprints(loops_a, loops_b)
                extent = (loops_a + loops_b).flatten(1)
                span = [extent.map { |p| p[0] }.max - extent.map { |p| p[0] }.min, extent.map { |p| p[1] }.max - extent.map { |p| p[1] }.min].max
                perimeter = (loops_a + loops_b).sum { |loop| Na__PlanGeometry.Na__PlanGeometry__PolylineLength(loop.map { |p| [p[0], p[1], 0.0] }, true) }
                step = [[span / 400.0, perimeter / 3000.0].max, 5.0].max
                distance = Na__PlanGeometry.Na__PlanGeometry__OutlineDistance(loops_a, loops_b, step)
                out['plan'] = {
                    'area_a_m2' => (plan[:area_a] / 1.0e6).round(3), 'area_b_m2' => (plan[:area_b] / 1.0e6).round(3),
                    'overlap_m2' => (plan[:overlap] / 1.0e6).round(3), 'only_a_m2' => ((plan[:area_a] - plan[:overlap]) / 1.0e6).round(3),
                    'only_b_m2' => ((plan[:area_b] - plan[:overlap]) / 1.0e6).round(3), 'iou' => plan[:iou].round(3)
                }
                if distance
                    out['plan']['outline_mm'] = { 'max' => distance[:hausdorff].round, 'a_to_b_median' => distance[:a_to_b_median].round,
                                                  'b_to_a_median' => distance[:b_to_a_median].round, 'sample_step' => step.round(1),
                                                  'worst_point_of_a' => distance[:worst_a] && distance[:worst_a].map { |value| value.round } }
                end
                out['levels'] = { 'a' => Array(a['levels']).map { |level| level['z'] }, 'b' => Array(b['levels']).map { |level| level['z'] } }
            elsif loops_a.empty? != loops_b.empty?
                out['plan'] = { 'note' => "Only #{loops_a.empty? ? 'b' : 'a'} has faces looking straight up; the other is lines or walls only." }
            end
            out
        end
        # ---------------------------------------------------------------

        def self.b_round(value)
            value.to_f.round(1)
        end

        def self.na_tally_change(a, b)
            a ||= {}
            b ||= {}
            changes = (a.keys | b.keys).sort.map { |key| [key, { 'a' => a[key].to_i, 'b' => b[key].to_i }] }.reject { |_key, value| value['a'] == value['b'] }
            changes.empty? ? 'same' : changes.to_h
        end

        # Children paired by name first, then by the best plan overlap.
        def self.na_pair_children(list_a, list_b)
            pairs = []
            rest_a = list_a.dup
            rest_b = list_b.dup
            list_a.each do |child|
                next if child['name'].to_s.empty?

                match = rest_b.find { |other| other['name'] == child['name'] }
                next unless match

                pairs << [child, match]
                rest_a.delete(child)
                rest_b.delete(match)
            end
            scored = rest_a.product(rest_b).map do |child_a, child_b|
                loops_a = na_loops(child_a)
                loops_b = na_loops(child_b)
                iou = loops_a.empty? || loops_b.empty? ? 0.0 : Na__PlanGeometry.Na__PlanGeometry__CompareFootprints(loops_a, loops_b, 300)[:iou]
                [iou, child_a, child_b]
            end
            scored.sort_by { |iou, _a, _b| -iou }.each do |iou, child_a, child_b|
                next if iou <= 0.0 || !rest_a.include?(child_a) || !rest_b.include?(child_b)

                pairs << [child_a, child_b]
                rest_a.delete(child_a)
                rest_b.delete(child_b)
            end
            [pairs, rest_a, rest_b]
        end

        def self.na_summary(out)
            parts = []
            plan = out['plan']
            if plan && plan['iou']
                parts << "Plan overlap #{(plan['iou'] * 100).round} % (IoU); #{plan['area_a_m2']} m2 vs #{plan['area_b_m2']} m2"
                parts << "outlines up to #{plan['outline_mm']['max']} mm apart (median #{plan['outline_mm']['a_to_b_median']})" if plan['outline_mm']
            end
            volume = out['volume_l']
            parts << "volume #{volume['a']} L vs #{volume['b']} L" if volume['a'] && volume['b']
            parts << 'edge colours changed' unless out['edge_materials'] == 'same'
            parts << "#{Array(out['children']).length} child pair(s)" if out['children']
            parts << "only in a: #{out['only_in_a'].map { |item| item['name'] }.join(', ')}" if out['only_in_a']
            parts << "only in b: #{out['only_in_b'].map { |item| item['name'] }.join(', ')}" if out['only_in_b']
            parts.empty? ? 'Nothing to compare in plan; see counts and materials.' : "#{parts.join('; ')}."
        end

# endregion -------------------------------------------------------------------

    end # module Na__Handlers__ModelDiff
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
