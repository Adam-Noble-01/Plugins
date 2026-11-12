# =============================================================================
# NA PROFILE TOOLS - MCP OPERATIONS - TRACES (READS, PATHS, MODEL EDITS)
# =============================================================================
#
# FILE       : Na__ProfileTracer__McpOperations__Traces__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__McpOperations
# AUTHOR     : Noble Architecture
# PURPOSE    : The trace half of the seam: reading traces and paths, and every
#              model edit (create, set_path, set_placement, swap_profile,
#              set_local_profile, revert_local, regenerate, recreate, rename,
#              delete), each through the plugin's own engines with
#              wrap_in_operation: false so the MCP owns the one undo step
# CREATED    : 11-Nov-2026 (v1.6.17)
#
# THE COORDINATE RULE, AS THE PLUGIN KEEPS IT:
#   A trace's own space (parent space) is WORLD SPACE AS BUILT: the build pins
#   the new trace so its world placement is the identity, and the stored
#   StartPoint, PathRuns and the swept solid all live in it. A trace built
#   here into a CLOSED container gets the pin that container needs (its
#   reported-to-world, inverted), so it is exactly what the dialog would have
#   built with that container open. Reverse then puts a mirror about the top
#   of the trace's bounds on top of the pin.
#   Reading: world = world_of(trace) * stored point, which is where Edit Path
#   draws the red line (a reversed trace's line is mirrored with it).
#   set_path takes world points through the inverse of the same transform, so
#   a path read and written back is unchanged.
#
# TRACES ARE NAMED by id: a persistent id of the trace or of anything inside it
# (its solid, a face), or its ProfileTraceId ("NPT0005").
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer
    module Na__McpOperations

# -----------------------------------------------------------------------------
# REGION | Finding Traces
# -----------------------------------------------------------------------------

        NA_TRACE_ID_PATTERN = /\ANPT\d{4}\z/.freeze unless defined?(NA_TRACE_ID_PATTERN)

        # One trace from a persistent id (of it or anything in it) or an NPT id.
        def self.na_trace_from_reference(params, reference, label = 'id')
            model = self.na_model(params)
            text  = reference.to_s.strip
            self.na_refuse('invalid_params', "#{label} is empty.", 'Pass a persistent id (profile_tracer {action: "traces"} lists them) or a trace id such as NPT0005.') if text.empty?

            if text.match?(NA_TRACE_ID_PATTERN)
                matches = self.na_all_traces(model).select { |group| Na__DataSerializer.Na__DataSerializer__ReadTraceId(group) == text }
                self.na_refuse('not_found', "No trace carries the id #{text}.", 'profile_tracer {action: "traces"} lists every trace.') if matches.empty?
                if matches.length > 1
                    self.na_refuse('invalid_params', "#{matches.length} traces carry #{text} (unrepaired copies).",
                                   'Name one by its persistent id instead.', { 'ids' => matches.map(&:persistent_id) })
                end
                return matches.first
            end

            unless text.match?(/\A\d+\z/)
                self.na_refuse('invalid_params', "#{label} '#{text}' is neither a persistent id nor a trace id (NPT0000).", nil)
            end
            entity = model.find_entity_by_persistent_id(text.to_i)
            self.na_refuse('not_found', "Nothing in the model has the persistent id #{text}.", 'Ids change only when an object is deleted; list again.') unless entity
            group = Na__DataSerializer.Na__DataSerializer__ResolveTraceParentForEntity(entity)
            unless group
                self.na_refuse('wrong_type', "#{text} is not a Profile Trace or part of one.",
                               'profile_tracer {action: "traces"} lists the traces in the model.')
            end
            group
        end

        # Every trace named by ids (or id / trace_id), deduplicated.
        def self.na_traces_from_params(params, single: false)
            references = []
            references.concat(Array(params['ids'])) if params['ids'].is_a?(Array)
            references << params['id'] if self.na_has?(params, 'id')
            references << params['trace_id'] if self.na_has?(params, 'trace_id')
            if references.empty?
                self.na_refuse('invalid_params', 'Say which trace: id (persistent id), ids, or trace_id (NPT0005).',
                               'profile_tracer {action: "traces"} lists them.')
            end
            self.na_refuse('invalid_params', "At most #{NA_MAX_IDS} traces per call.", nil) if references.length > NA_MAX_IDS
            groups = references.map { |reference| self.na_trace_from_reference(params, reference) }.uniq
            if single && groups.length != 1
                self.na_refuse('invalid_params', "This action takes one trace; #{groups.length} were named.", 'Call it once per trace.')
            end
            groups
        end

        # An open trace reports world coordinates for its own contents, so the
        # stored path would be misread: the caller closes it first, outside the
        # undo step (changing the open group splits an operation).
        def self.na_require_closed(model, group)
            path = Array(model.active_path)
            return unless path.include?(group)
            self.na_refuse('context_error', "Trace #{Na__DataSerializer.Na__DataSerializer__ReadTraceId(group)} is open for editing.",
                           'Close it first: context_set {action: "close"} until the trace is no longer in the active path, then call again.')
        end

        def self.na_require_no_edit_path(group)
            return unless Na__DataSerializer.Na__DataSerializer__FindEditPathGroup(group)
            self.na_refuse('context_error', "Trace #{Na__DataSerializer.Na__DataSerializer__ReadTraceId(group)} has an Edit Path line open or waiting.",
                           'Finish it (regenerate) or discard it in SketchUp (right-click the trace: Finish / Discard Path Edit) first.')
        end

        # Definition coordinates of an instance -> world. The MCP hands over
        # its own resolver (open contexts, shared definitions); without it the
        # placements up the chain are multiplied, right only when nothing is open.
        def self.na_world(params, instance)
            resolver = params['world_of']
            return resolver.call(instance) if resolver.respond_to?(:call)
            transform = instance.transformation
            current = instance
            16.times do
                parent = Na__DataSerializer.Na__DataSerializer__ContainingInstance(current)
                break unless parent
                transform = parent.transformation * transform
                current = parent
            end
            transform
        end

        # The instances from the root down to the one holding entity.
        def self.na_container_path(params, entity)
            resolver = params['path_of']
            return Array(resolver.call(entity)) if resolver.respond_to?(:call)
            path = []
            current = entity
            16.times do
                parent = Na__DataSerializer.Na__DataSerializer__ContainingInstance(current)
                break unless parent
                path.unshift(parent)
                current = parent
            end
            path
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Read - traces / trace
# -----------------------------------------------------------------------------

        def self.na_read_traces(params)
            model  = self.na_model(params)
            traces = self.na_all_traces(model)
            query  = self.na_text(params, 'query', '').downcase
            key    = self.na_text(params, 'profile_key', '')
            within = self.na_has?(params, 'within_id') ? params['within_id'].to_i : nil

            rows = []
            traces.each do |group|
                payload = Na__DataSerializer.Na__DataSerializer__ReadParentPayload(group) || {}
                next if !key.empty? && payload['ProfileKey'] != key
                next if !query.empty? && ![group.name, payload['ProfileKey'], payload['LocalProfileName'], payload['ProfileTraceId']].join(' ').downcase.include?(query)
                if within
                    path = self.na_container_path(params, group)
                    next unless path.any? { |instance| instance.persistent_id == within }
                end
                rows << group
            end

            total  = rows.length
            offset = self.na_offset(params)
            limit  = self.na_limit(params, 50, 500)
            page   = (rows[offset, limit] || []).map { |group| self.na_trace_summary(params, group, detail: false) }
            {
                'traces'      => page,
                'total'       => total,
                'offset'      => offset,
                'next_offset' => offset + page.length < total ? offset + page.length : nil,
                'summary'     => "#{total} trace(s)#{query.empty? && key.empty? && within.nil? ? '' : ' match'}; #{page.length} returned."
            }
        end

        def self.na_read_trace(params)
            group = self.na_traces_from_params(params, single: true).first
            result = self.na_trace_summary(params, group, detail: true)
            if self.na_bool(params, 'include_profile_json', false)
                record = Na__DataSerializer.Na__DataSerializer__LocalProfileRecord(group)
                result['profile_json'] = record ? record.dig('profileData', 'assetData') : nil
            end
            result
        end

        def self.na_trace_summary(params, group, detail: false)
            dict    = group.attribute_dictionary(Na__DataSerializer::NA_PROFILE_TRACE_DICT)
            payload = Na__DataSerializer.Na__DataSerializer__ReadParentPayload(group) || {}
            world   = self.na_world(params, group)
            path    = Na__RegenEngine.Na__RegenEngine__StoredPathRuns(group, payload)
            runs    = path[:isValid] ? Array(path[:runs]) : []
            world_runs = runs.map do |run|
                { points: Array(run[:ordered_points]).map { |point| point.transform(world) }, closed: run[:is_closed_loop] == true }
            end
            length = world_runs.sum { |run| self.na_polyline_length(run[:points], run[:closed]) }
            container = self.na_container_path(params, group)
            toggles = payload['ToggleStates'].is_a?(Hash) ? payload['ToggleStates'].select { |_, value| value == true }.keys : []
            typed = Na__SwapEngine.Na__SwapEngine__TypedPathOffsets(payload)

            row = {
                'id'            => group.persistent_id,
                'trace_id'      => payload['ProfileTraceId'],
                'name'          => group.name.to_s,
                'container'     => container.map { |instance| { 'id' => instance.persistent_id, 'name' => instance.name.to_s.empty? ? instance.definition.name.to_s : instance.name.to_s } },
                'profile'       => {
                    'key'        => payload['ProfileKey'],
                    'source'     => payload['ProfileSource'],
                    'local_name' => payload['ProfileSource'] == 'local' ? payload['LocalProfileName'] : nil
                },
                'reverse'       => payload['ReverseDirection'] == true,
                'rotation_step' => payload['RotationStep'].to_i,
                'toggles_on'    => toggles,
                'origin_offset_mm' => payload['OriginOffset'] ? [payload['OriginOffset']['y'], payload['OriginOffset']['z']] : nil,
                'offsets_mm'    => { 'start' => typed['start'], 'end' => typed['end'] },
                'runs'          => runs.length,
                'closed'        => !runs.empty? && runs.all? { |run| run[:is_closed_loop] == true },
                'path_length'   => self.na_out(length, params, 1),
                'bounds'        => self.na_world_bounds(group, world, params),
                'solid'         => self.na_solid_stats(group, params)
            }
            row['path_problem'] = path[:reason] unless path[:isValid]
            return row unless detail

            row['path'] = world_runs.map { |run| { 'closed' => run[:closed], 'points' => run[:points].map { |point| self.na_point_out(point, params) } } }
            start_point = payload['StartPoint']
            row['start_point'] = start_point ? self.na_point_out(start_point.transform(world), params) : nil
            row['schema']      = payload['SchemaVersion']
            row['created_at']  = dict ? dict['CreatedAt'].to_s : nil
            row['edit_path_open'] = !Na__DataSerializer.Na__DataSerializer__FindEditPathGroup(group).nil?
            row['legacy_helpers'] = !Na__DataSerializer.Na__DataSerializer__FindHelpersSubGroup(group).nil?
            row['shared_definition'] = group.definition.instances.length > 1
            row['world_placement'] = { 'origin' => self.na_point_out(world.origin, params), 'mirrored' => self.na_mirrored?(world) }
            if payload['ProfileSource'] == 'local'
                record = Na__DataSerializer.Na__DataSerializer__LocalProfileRecord(group)
                facts = record ? self.na_shape_facts(record.dig('profileData', 'assetData')) : nil
                row['local_profile'] = facts ? { 'name' => payload['LocalProfileName'], 'size_mm' => facts['size_mm'], 'extent_mm' => facts['extent_mm'], 'vertices' => facts['vertices'] } : { 'unreadable' => true }
            end
            row
        end

        def self.na_mirrored?(transform)
            x = transform.xaxis
            y = transform.yaxis
            z = transform.zaxis
            (x * y).dot(z) < 0
        end

        def self.na_polyline_length(points, closed)
            total = 0.0
            points.each_cons(2) { |a, b| total += a.distance(b) }
            total += points.last.distance(points.first) if closed && points.length > 2
            total
        end

        def self.na_world_bounds(group, world, params)
            box = group.definition.bounds
            return nil if box.empty?
            corners = (0..7).map { |index| box.corner(index).transform(world) }
            minimum = [0, 1, 2].map { |axis| corners.map { |corner| corner.to_a[axis] }.min }
            maximum = [0, 1, 2].map { |axis| corners.map { |corner| corner.to_a[axis] }.max }
            {
                'min'  => minimum.map { |value| self.na_out(value, params) },
                'max'  => maximum.map { |value| self.na_out(value, params) },
                'size' => [0, 1, 2].map { |axis| self.na_out(maximum[axis] - minimum[axis], params) }
            }
        end

        # The swept solid's health: faces, edges, manifold, volume, and its
        # edge colours (unpainted edges show as "none").
        def self.na_solid_stats(group, params)
            solid = Na__DataSerializer.Na__DataSerializer__FindSolidSubGroup(group)
            return { 'missing' => true } unless solid
            containers = [solid] + solid.entities.grep(Sketchup::Group).select(&:valid?)
            faces = 0
            edges = []
            containers.each do |container|
                faces += container.entities.grep(Sketchup::Face).length
                edges.concat(container.entities.grep(Sketchup::Edge))
            end
            colours = Hash.new(0)
            edges.each { |edge| colours[edge.material ? edge.material.display_name.to_s : 'none'] += 1 }
            stats = {
                'faces'    => faces,
                'edges'    => edges.length,
                'soft'     => edges.count(&:soft?),
                'smooth'   => edges.count(&:smooth?),
                'runs'     => containers.length - 1 > 0 ? containers.length - 1 : 1,
                'manifold' => solid.manifold?,
                'edge_colours' => colours
            }
            if solid.manifold?
                per = self.na_per_inch(params)
                stats['volume'] = (solid.volume.abs * per * per * per).round(1)
            end
            stats
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Paths (from points or edges)
# -----------------------------------------------------------------------------

        # [{ points: [Point3d world], closed: true/false/nil }] from 'path_runs'
        # (the handler's points) or 'path_segments' (its edges).
        def self.na_runs_from_params(params, required: true)
            closed = params.key?('closed') && !params['closed'].nil? ? self.na_bool(params, 'closed') : nil
            if params['path_runs'].is_a?(Array) && !params['path_runs'].empty?
                return params['path_runs'].map { |points| { points: Array(points), closed: closed, from: 'points' } }
            end
            if params['path_segments'].is_a?(Array) && !params['path_segments'].empty?
                arrays = params['path_segments'].map { |segment| segment.map { |point| [point.x.to_f, point.y.to_f, point.z.to_f] } }
                chains = self.Na__McpPath__Chains(arrays)
                self.na_refuse('invalid_params', 'The edges make no run of two or more points.', 'Pass the edges of one continuous path.') if chains[:runs].empty?
                return chains[:runs].map do |run|
                    { points: run[:points].map { |xyz| Geom::Point3d.new(*xyz) }, closed: closed.nil? ? run[:closed] : closed,
                      from: 'edges', branches: chains[:branches] }
                end
            end
            return [] unless required
            self.na_refuse('invalid_params', 'Say where the path runs: path (world points) or path_edge_ids (edges in the model).',
                           'path is [[x,y,z], ...] for one run, or [[[x,y,z], ...], ...] for several.')
        end

        # FUNCTION | Chains From Loose Segments (pure; offline tested)
        # ------------------------------------------------------------
        # segments: [[[x,y,z], [x,y,z]], ...] in any order and direction.
        # Returns { runs: [{ points:, closed: }], branches: n, skipped: n }:
        # maximal runs between ends and branch points, then the loops left over.
        # Zero-length segments (a stray vertex) are skipped.
        def self.Na__McpPath__Chains(segments, tolerance = 0.001)
            key_of = ->(point) { point.map { |value| (value / tolerance).round } }
            points = {}
            links  = {}
            skipped = 0
            list = []
            segments.each do |a, b|
                ka = key_of.call(a)
                kb = key_of.call(b)
                if ka == kb
                    skipped += 1
                    next
                end
                index = list.length
                list << [ka, kb]
                points[ka] ||= a
                points[kb] ||= b
                (links[ka] ||= []) << [kb, index]
                (links[kb] ||= []) << [ka, index]
            end
            used = {}
            runs = []
            walk = lambda do |start, first_link|
                chain = [start]
                current = start
                link = first_link
                loop do
                    other, index = link
                    used[index] = true
                    chain << other
                    break if other == start
                    break unless links[other].length == 2
                    link = links[other].find { |_, next_index| !used[next_index] }
                    break unless link
                    current = other
                end
                chain
            end
            # open runs: from every end or branch point
            links.keys.each do |key|
                next if links[key].length == 2
                links[key].each do |link|
                    next if used[link[1]]
                    chain = walk.call(key, link)
                    runs << { points: chain.map { |k| points[k] }, closed: false }
                end
            end
            # what is left is closed loops
            list.each_with_index do |(ka, _kb), index|
                next if used[index]
                link = links[ka].find { |_, link_index| link_index == index }
                chain = walk.call(ka, link)
                closed = chain.first == chain.last
                chain.pop if closed
                runs << { points: chain.map { |k| points[k] }, closed: closed }
            end
            { runs: runs, branches: links.count { |_, ends| ends.length > 2 }, skipped: skipped }
        end
        # ---------------------------------------------------------------

        # A run as the plugin's own Interactive mode reads it: points merged,
        # a loop closed or not, and an open run turned to the canonical
        # direction (negative along its dominant axis), so Reverse means the
        # same whichever way the run was given.
        def self.na_path_data(points, closed)
            data = Na__ProfilePlacementEngine.Na__Engine__BuildPathDataFromInteractivePoints(points, closed)
            self.na_refuse('invalid_params', 'A run needs two or more distinct points (three for a loop).', nil) unless data
            if data[:is_closed_loop] && data[:ordered_points].length < 3
                self.na_refuse('invalid_params', 'A closed loop needs three or more distinct points.', nil)
            end
            data
        end

        def self.na_read_check_path(params)
            runs = self.na_runs_from_params(params, required: true)
            rows = runs.map do |run|
                data = Na__ProfilePlacementEngine.Na__Engine__BuildPathDataFromInteractivePoints(run[:points], run[:closed])
                next { 'ok' => false, 'reason' => 'fewer than two distinct points' } unless data
                points = data[:ordered_points]
                zs = points.map(&:z)
                warnings = []
                if !data[:is_closed_loop] && points.length >= 3 && points.first.distance(points.last) < 5.mm
                    warnings << 'its ends meet: pass closed: true to sweep it as a loop'
                end
                points.each_cons(3).each_with_index do |(a, b, c), index|
                    u = b - a
                    v = c - b
                    next if u.length < 0.001 || v.length < 0.001
                    warnings << "points #{index + 1} and #{index + 2} turn back on themselves" if u.angle_between(v) > 179.9.degrees
                end
                {
                    'ok'        => true,
                    'closed'    => data[:is_closed_loop],
                    'points'    => points.length,
                    'segments'  => data[:is_closed_loop] ? points.length : points.length - 1,
                    'length'    => self.na_out(self.na_polyline_length(points, data[:is_closed_loop]), params, 1),
                    'start'     => self.na_point_out(points.first, params),
                    'end'       => self.na_point_out(points.last, params),
                    'given_order_reversed' => data[:input_reversed] == true,
                    'z_range'   => [self.na_out(zs.min, params), self.na_out(zs.max, params)],
                    'level'     => (zs.max - zs.min) < 0.5.mm,
                    'swept_points' => points.map { |point| self.na_point_out(point, params) },
                    'warnings'  => warnings
                }
            end
            branches = runs.first ? runs.first[:branches].to_i : 0
            {
                'runs'     => rows,
                'branches' => branches,
                'summary'  => "#{rows.length} run(s), #{rows.count { |row| row['closed'] }} closed#{branches > 0 ? ", #{branches} branch point(s): each branch sweeps as its own run" : ''}. " \
                              'Open runs sweep in the canonical direction (negative along their main axis); Reverse puts the profile on the other side.'
            }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Placement Settings
# -----------------------------------------------------------------------------

        # The placement keys a call gave, normalised. Only given keys appear.
        def self.na_settings(params)
            settings = {}
            if self.na_has?(params, 'rotation_step')
                step = self.na_number(params, 'rotation_step').to_i
                self.na_refuse('invalid_params', 'rotation_step is 0, 1, 2 or 3 (quarter turns of the profile).', nil) unless (0..3).cover?(step)
                settings[:rotation_step] = step
            end
            if self.na_has?(params, 'toggles')
                toggles = params['toggles']
                self.na_refuse('invalid_params', "toggles is an object of #{NA_TOGGLE_KEYS.join(', ')}.", nil) unless toggles.is_a?(Hash)
                unknown = toggles.keys.map(&:to_s) - NA_TOGGLE_KEYS
                self.na_refuse('invalid_params', "Unknown toggle(s) #{unknown.join(', ')}.", "Use #{NA_TOGGLE_KEYS.join(', ')}.") unless unknown.empty?
                settings[:toggles] = toggles.each_with_object({}) { |(key, value), list| list[key.to_s] = value == true }
            end
            if params.key?('origin_offset')
                value = params['origin_offset']
                settings[:origin_offset] = if value.nil?
                                               nil
                                           elsif value.is_a?(Array) && value.length == 2 && value.all? { |number| number.is_a?(Numeric) }
                                               value.all?(&:zero?) ? nil : { 'y' => value[0].to_f, 'z' => value[1].to_f }
                                           else
                                               self.na_refuse('invalid_params', 'origin_offset is [y, z] in mm (the profile point that rides on the path), or null to clear it.', nil)
                                           end
            end
            settings[:start_offset] = self.na_number(params, 'start_offset', nil, min: -50_000, max: 50_000) if self.na_has?(params, 'start_offset')
            settings[:end_offset]   = self.na_number(params, 'end_offset', nil, min: -50_000, max: 50_000) if self.na_has?(params, 'end_offset')
            settings[:reverse]      = self.na_bool(params, 'reverse') if self.na_has?(params, 'reverse')
            settings
        end

        def self.na_full_toggles(given = nil)
            NA_TOGGLE_KEYS.each_with_object({}) { |key, list| list[key] = given.is_a?(Hash) && given[key] == true }
        end

        # A container's pin: nil at the active context (the plugin's own
        # identity pin is right there), else its reported-to-world, inverted.
        def self.na_pin_for(to_world)
            return nil if to_world.nil? || to_world.identity?
            to_world.inverse
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Edit - create
# -----------------------------------------------------------------------------

        def self.na_edit_create(params)
            model     = self.na_model(params)
            container = params['container']
            unless container.is_a?(Hash) && container[:entities]
                self.na_refuse('internal_error', 'The MCP did not say where to build.', 'Update Na SketchUp MCP (1.0.24 or newer) and reload it.')
            end
            runs     = self.na_runs_from_params(params, required: true)
            source   = self.na_profile_source(params, required: true)
            source   = self.na_apply_profile_edit(source, params['profile_edit'], params['local_name']) if params['profile_edit'].is_a?(Hash)
            settings = self.na_settings(params)
            name     = self.na_text(params, 'name', '').strip
            tag      = self.na_tag(model, params)

            target  = { entities: container[:entities], to_world: container[:to_world] }
            wrapper = nil
            edge_material = self.na_edge_material(model, params)
            reference_edges = []
            if params['wrapper'].is_a?(Hash)
                wrapper, target, reference_edges = self.na_make_wrapper(model, container, params['wrapper'], runs, edge_material)
            elsif self.na_bool(params, 'reference_path', false)
                reference_edges = self.na_draw_reference_path(target, runs, edge_material)
            end

            group = self.na_build_trace(model, target, runs, source, settings)
            group.name = name unless name.empty?
            (wrapper || group).layer = tag if tag

            result = self.na_trace_summary(params, group, detail: false)
            result['created'] = true
            result['wrapper'] = { 'id' => wrapper.persistent_id, 'name' => wrapper.name } if wrapper
            result['reference_path_edge_ids'] = reference_edges.map(&:persistent_id) unless reference_edges.empty?
            result['profile_used'] = { 'source' => source[:kind], 'name' => source[:name], 'local' => source[:local], 'edits' => source[:edits] }.compact
            result['summary'] = "Built #{result['trace_id']} \"#{group.name}\" along #{runs.length} run(s), #{result['path_length']} long; " \
                                "solid #{result['solid']['manifold'] ? 'closed' : 'NOT closed'} (#{result['solid']['faces']} faces)."
            result
        end

        # The one place a trace is swept: the plugin's own builder, pinned for
        # the target container, a local profile stamped on, extra runs swept by
        # the regeneration engine. Returns the trace group.
        def self.na_build_trace(model, target, runs, source, settings)
            datas = runs.map { |run| self.na_path_data(run[:points], run[:closed]) }
            first = datas.first
            offsets = { 'start' => settings[:start_offset].to_f, 'end' => settings[:end_offset].to_f }
            result = Na__GeometryBuilders.Na__Geometry__BuildProfileAlongPath(
                model:                 model,
                profile_data:          self.na_sweep_record(source),
                path_data:             first,
                start_point:           first[:ordered_points].first,
                rotation_step:         settings[:rotation_step].to_i,
                toggle_states:         self.na_full_toggles(settings[:toggles]),
                reverse_direction:     settings[:reverse] == true,
                origin_offset:         settings[:origin_offset],
                path_offsets:          Na__ProfilePlacementEngine.Na__Engine__TraversalPathOffsets(offsets, first[:input_reversed]),
                offset_ends_swapped:   first[:input_reversed] == true && !first[:is_closed_loop],
                target_entities:       target[:entities],
                parent_transformation: self.na_pin_for(target[:to_world]),
                wrap_in_operation:     false
            )
            unless result['isBuilt']
                self.na_refuse('operation_failed', "The sweep failed: #{result['reason']}",
                               'Check the path (profile_tracer {action: "check_path"}) and the profile; nothing was built.')
            end
            group = result['group']
            Na__DataSerializer.Na__DataSerializer__WriteLocalProfile(group, source[:asset], source[:name]) if source[:local]

            if datas.length > 1
                Na__DataSerializer.Na__DataSerializer__WritePathRuns(group, datas.map { |data| { ordered_points: data[:ordered_points], is_closed_loop: data[:is_closed_loop] } })
                unless Na__RegenEngine.Na__RegenEngine__RegenerateTrace(group, wrap_in_operation: false)
                    self.na_refuse('operation_failed', "The extra runs would not sweep: #{Na__RegenEngine.Na__RegenEngine__LastFailure}", 'Check each run with check_path; nothing was built.')
                end
            end
            group
        end

        # Adam's pattern (SUB__Orangery__ParapetWall__StoneCapping): a named
        # group holding the reference path as loose edges and the trace. Its
        # origin sits at the path's lowest corner (or 'origin'), world axes.
        def self.na_make_wrapper(model, container, spec, runs, edge_material = nil)
            name = spec['name'].to_s.strip
            self.na_refuse('invalid_params', 'wrapper.name is required (e.g. SUB__Orangery__ParapetWall__StoneCapping).', nil) if name.empty?
            all = runs.flat_map { |run| run[:points] }
            origin = if spec['origin'].is_a?(Geom::Point3d)
                         spec['origin']
                     else
                         Geom::Point3d.new(all.map(&:x).min, all.map(&:y).min, all.map(&:z).min)
                     end
            wrapper = container[:entities].add_group
            wrapper.name = name
            to_world = container[:to_world] || Geom::Transformation.new
            wrapper.transformation = to_world.inverse * Geom::Transformation.translation(origin - ORIGIN)
            target = { entities: wrapper.entities, to_world: to_world * wrapper.transformation }
            edges = spec['reference_path'] == false ? [] : self.na_draw_reference_path(target, runs, edge_material)
            [wrapper, target, edges]
        end

        # The path as loose edges beside the trace: the reference Adam (or an
        # agent) can select again in Path Selection Mode.
        # Returns the edges drawn, painted with edge_material when one is given
        # (Adam's edge-colour gate counts an unpainted edge as unfinished).
        def self.na_draw_reference_path(target, runs, edge_material = nil)
            inverse = target[:to_world] ? target[:to_world].inverse : Geom::Transformation.new
            edges = []
            runs.each do |run|
                local = run[:points].map { |point| point.transform(inverse) }
                pairs = local.each_cons(2).to_a
                pairs << [local.last, local.first] if run[:closed] == true && local.length > 2
                pairs.each do |a, b|
                    next if a.distance(b) <= 0.001
                    edge = target[:entities].add_line(a, b)
                    edges << edge if edge
                end
            end
            edges.each { |edge| edge.material = edge_material } if edge_material
            edges
        end

        def self.na_edge_material(model, params)
            return nil unless self.na_has?(params, 'reference_path_material')
            material = model.materials[params['reference_path_material'].to_s]
            self.na_refuse('not_found', "There is no material '#{params['reference_path_material']}' for the reference path.",
                           'Use an edge material already in the model, e.g. MTE102__LineColour__SoftBlack__L20.') unless material
            material
        end

        def self.na_tag(model, params)
            return nil unless self.na_has?(params, 'tag')
            layer = model.layers[params['tag'].to_s]
            self.na_refuse('not_found', "There is no tag '#{params['tag']}'.", 'Create it first (tag_manage), or leave tag out.') unless layer
            layer
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Edit - set_path / regenerate
# -----------------------------------------------------------------------------

        def self.na_edit_set_path(params)
            model = self.na_model(params)
            group = self.na_traces_from_params(params, single: true).first
            self.na_require_closed(model, group)
            self.na_require_no_edit_path(group)
            runs = self.na_runs_from_params(params, required: true)
            inverse = self.na_world(params, group).inverse
            datas = runs.map { |run| self.na_path_data(run[:points].map { |point| point.transform(inverse) }, run[:closed]) }

            dict = group.attribute_dictionary(Na__DataSerializer::NA_PROFILE_TRACE_DICT, true)
            before = %w[PathRuns PathPoints StartPoint StartOffset EndOffset OffsetEndsSwapped IsClosedLoop].each_with_object({}) { |key, list| list[key] = dict[key] }
            Na__DataSerializer.Na__DataSerializer__WritePathRuns(group, datas.map { |data| { ordered_points: data[:ordered_points], is_closed_loop: data[:is_closed_loop] } })
            dict['StartPoint']   = Na__DataSerializer.Na__DataSerializer__SerialisePoint(datas.first[:ordered_points].first)
            dict['IsClosedLoop'] = (datas.first[:is_closed_loop] == true).to_s
            settings = self.na_settings(params)
            if settings.key?(:start_offset) || settings.key?(:end_offset)
                typed = { 'start' => settings[:start_offset].to_f, 'end' => settings[:end_offset].to_f }
                swapped = datas.first[:input_reversed] == true && !datas.first[:is_closed_loop]
                dict['StartOffset']       = Na__DataSerializer.Na__DataSerializer__SerialiseOffsetMm(swapped ? typed['end'] : typed['start'])
                dict['EndOffset']         = Na__DataSerializer.Na__DataSerializer__SerialiseOffsetMm(swapped ? typed['start'] : typed['end'])
                dict['OffsetEndsSwapped'] = swapped.to_s
            end

            unless Na__RegenEngine.Na__RegenEngine__RegenerateTrace(group, wrap_in_operation: false)
                before.each { |key, value| value.nil? ? dict.delete_key(key) : dict[key] = value }
                self.na_refuse('operation_failed', "The new path would not sweep: #{Na__RegenEngine.Na__RegenEngine__LastFailure}",
                               'Check it with profile_tracer {action: "check_path"}; the trace keeps its old path.')
            end
            result = self.na_trace_summary(params, group, detail: false)
            result['summary'] = "#{result['trace_id']} now follows #{datas.length} run(s), #{result['path_length']} long."
            result
        end

        def self.na_edit_regenerate(params)
            model  = self.na_model(params)
            groups = self.na_traces_from_params(params)
            done = []
            groups.each do |group|
                self.na_require_closed(model, group)
                unless Na__RegenEngine.Na__RegenEngine__RegenerateTrace(group, wrap_in_operation: false)
                    self.na_refuse('operation_failed', "#{Na__DataSerializer.Na__DataSerializer__ReadTraceId(group)} would not rebuild: #{Na__RegenEngine.Na__RegenEngine__LastFailure}",
                                   'Nothing was changed (the whole call is undone).', { 'rebuilt_before_failure' => done })
                end
                done << Na__DataSerializer.Na__DataSerializer__ReadTraceId(group)
            end
            { 'regenerated' => done, 'traces' => groups.map { |group| self.na_trace_summary(params, group) }, 'summary' => "#{done.length} trace(s) rebuilt from their stored path and profile." }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Edit - set_placement / swap_profile (the swap engine)
# -----------------------------------------------------------------------------

        def self.na_edit_set_placement(params)
            settings = self.na_settings(params)
            if settings.key?(:reverse)
                self.na_refuse('invalid_params', 'reverse cannot be changed in place: it is baked into the trace\'s placement.',
                               'Use profile_tracer_edit {action: "recreate", id, reverse: true|false}.')
            end
            self.na_refuse('invalid_params', 'Give a setting to change: rotation_step, toggles, origin_offset, start_offset or end_offset.', nil) if settings.empty?
            self.na_swap(params, '', settings, 'placement')
        end

        def self.na_edit_swap_profile(params)
            key = self.na_text(params, 'profile_key', '').strip
            self.na_refuse('invalid_params', 'swap_profile needs profile_key (a library profile).', 'For a reshaped or drawn profile use set_local_profile.') if key.empty?
            self.na_source_from_library(key)
            settings = self.na_settings(params)
            self.na_refuse('invalid_params', 'reverse cannot be changed by a swap.', 'Use recreate.') if settings.key?(:reverse)
            self.na_swap(params, key, settings, 'profile')
        end

        # Through Na__SwapEngine__SwapOneTrace: the dictionary patch, the
        # rename, the rebuild and the roll back on failure are the dialog's.
        def self.na_swap(params, key, settings, what)
            model  = self.na_model(params)
            groups = self.na_traces_from_params(params)
            done   = []
            groups.each do |group|
                self.na_require_closed(model, group)
                self.na_require_no_edit_path(group)
                payload = Na__DataSerializer.Na__DataSerializer__ReadParentPayload(group) || {}
                request = {}
                request['rotationStep'] = settings[:rotation_step] if settings.key?(:rotation_step)
                if settings.key?(:toggles)
                    request['toggleStates'] = self.na_full_toggles(payload['ToggleStates']).merge(settings[:toggles])
                end
                request['originOffset'] = settings[:origin_offset] if settings.key?(:origin_offset)
                if settings.key?(:start_offset) || settings.key?(:end_offset)
                    typed = Na__SwapEngine.Na__SwapEngine__TypedPathOffsets(payload)
                    request['startOffset'] = settings.key?(:start_offset) ? settings[:start_offset] : typed['start']
                    request['endOffset']   = settings.key?(:end_offset) ? settings[:end_offset] : typed['end']
                end
                overrides = Na__SwapEngine.Na__SwapEngine__NormaliseOverrides(request, !key.empty?)
                trace_id  = payload['ProfileTraceId'].to_s
                outcome   = Na__SwapEngine.Na__SwapEngine__SwapOneTrace(model, trace_id, key, overrides, wrap_in_operation: false, parent_group: group)
                unless outcome[:isSwapped]
                    self.na_refuse('operation_failed', "#{trace_id}: #{outcome[:reason]}", 'The whole call is undone.', { 'done_before_failure' => done })
                end
                done << trace_id
            end
            label = what == 'profile' ? "now on #{key}" : 'placement changed'
            { 'changed' => done, 'traces' => groups.map { |group| self.na_trace_summary(params, group) }, 'summary' => "#{done.length} trace(s) #{label} and rebuilt." }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Edit - set_local_profile / revert_local
# -----------------------------------------------------------------------------

        # The trace's own profile, as Draw Profile's Update This Trace and Live
        # write it. Without a source, profile_edit reshapes the profile the
        # trace already shows.
        def self.na_edit_set_local_profile(params)
            model  = self.na_model(params)
            groups = self.na_traces_from_params(params)
            shared = self.na_profile_source(params, required: false)
            unless shared || params['profile_edit'].is_a?(Hash)
                self.na_refuse('invalid_params', 'Give a profile source, or a profile_edit to reshape the profile the trace has now.',
                               'e.g. profile_edit: {stretch: [{axis: "z", at: 50, by: 30}]}')
            end
            done = []
            groups.each do |group|
                self.na_require_closed(model, group)
                self.na_require_no_edit_path(group)
                source = shared || self.na_source_from_trace(params.merge('profile_from' => group.persistent_id.to_s))
                source = self.na_apply_profile_edit(source, params['profile_edit'], params['local_name']) if params['profile_edit'].is_a?(Hash)
                name = self.na_text(params, 'local_name', '').strip
                name = source[:name].to_s if name.empty?
                trace_id = Na__DataSerializer.Na__DataSerializer__ReadTraceId(group)
                outcome = Na__DrawProfile__TraceBridge.Na__TraceBridge__ApplyLocalToOne(model, trace_id, source[:asset], name,
                                                                                        wrap_in_operation: false, parent_group: group)
                self.na_refuse('operation_failed', outcome[:reason].to_s, 'The whole call is undone.', { 'done_before_failure' => done }) unless outcome[:ok]
                done << trace_id
            end
            {
                'changed' => done,
                'traces'  => groups.map { |group| self.na_trace_summary(params, group) },
                'summary' => "#{done.length} trace(s) rebuilt with their own local profile. The library is unchanged."
            }
        end

        def self.na_edit_revert_local(params)
            model  = self.na_model(params)
            groups = self.na_traces_from_params(params)
            reverted  = []
            unchanged = []
            groups.each do |group|
                self.na_require_closed(model, group)
                trace_id = Na__DataSerializer.Na__DataSerializer__ReadTraceId(group)
                outcome = Na__DrawProfile__TraceBridge.Na__TraceBridge__RevertLocalOne(model, group, wrap_in_operation: false)
                self.na_refuse('operation_failed', "#{trace_id}: #{outcome[:reason]}", 'The whole call is undone.') unless outcome[:ok]
                (outcome[:unchanged] ? unchanged : reverted) << trace_id
            end
            { 'reverted' => reverted, 'already_library' => unchanged, 'summary' => "#{reverted.length} trace(s) back on their library profile." }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Edit - recreate / rename / delete
# -----------------------------------------------------------------------------

        # A fresh build of a trace from its own data, with overrides: the only
        # way to change reverse (baked into the placement) or to move a trace
        # into another container. Its name and trace id are kept.
        def self.na_edit_recreate(params)
            model = self.na_model(params)
            group = self.na_traces_from_params(params, single: true).first
            self.na_require_closed(model, group)
            self.na_require_no_edit_path(group)
            payload  = Na__DataSerializer.Na__DataSerializer__ReadParentPayload(group) || {}
            trace_id = payload['ProfileTraceId'].to_s
            world    = self.na_world(params, group)
            path     = Na__RegenEngine.Na__RegenEngine__StoredPathRuns(group, payload)
            self.na_refuse('operation_failed', "#{trace_id} has no path to rebuild along: #{path[:reason]}", nil) unless path[:isValid]

            # The path as it was picked: the placement without the Reverse flip
            # (recomputed the way the build made it, from the trace's bounds).
            as_built = world
            if payload['ReverseDirection'] == true
                bounds = Geom::BoundingBox.new
                bounds.add(group.definition.bounds)
                path[:runs].each { |run| run[:ordered_points].each { |point| bounds.add(point) } }
                as_built = world * Na__GeometryBuilders.Na__Geometry__BuildReverseFlipTransform(bounds).inverse
            end
            runs = if params['path_runs'].is_a?(Array) || params['path_segments'].is_a?(Array)
                       self.na_runs_from_params(params, required: true)
                   else
                       path[:runs].map { |run| { points: run[:ordered_points].map { |point| point.transform(as_built) }, closed: run[:is_closed_loop] } }
                   end

            source = self.na_profile_source(params, required: false) ||
                     self.na_source_from_trace(params.merge('profile_from' => group.persistent_id.to_s))
            source = self.na_apply_profile_edit(source, params['profile_edit'], params['local_name']) if params['profile_edit'].is_a?(Hash)
            typed = Na__SwapEngine.Na__SwapEngine__TypedPathOffsets(payload)
            settings = {
                rotation_step: payload['RotationStep'].to_i,
                toggles:       payload['ToggleStates'],
                origin_offset: payload['OriginOffset'],
                start_offset:  typed['start'],
                end_offset:    typed['end'],
                reverse:       payload['ReverseDirection'] == true
            }.merge(self.na_settings(params))

            target = if params['container'].is_a?(Hash) && params['container'][:entities] && self.na_has?(params, 'parent_id')
                         { entities: params['container'][:entities], to_world: params['container'][:to_world] }
                     else
                         { entities: group.parent.entities, to_world: world * group.transformation.inverse }
                     end
            name  = self.na_text(params, 'name', group.name.to_s)
            layer = group.layer
            group.erase!
            fresh = self.na_build_trace(model, target, runs, source, settings)
            Na__DataSerializer.Na__DataSerializer__RestampTraceId(fresh, trace_id) if trace_id.match?(NA_TRACE_ID_PATTERN)
            fresh.name  = name
            fresh.layer = layer
            result = self.na_trace_summary(params, fresh)
            result['recreated'] = true
            result['summary'] = "#{trace_id} rebuilt from scratch (reverse #{settings[:reverse] ? 'on' : 'off'}); new persistent id #{fresh.persistent_id}."
            result
        end

        def self.na_edit_rename(params)
            group = self.na_traces_from_params(params, single: true).first
            name = self.na_text(params, 'name', '').strip
            self.na_refuse('invalid_params', 'rename needs name.', nil) if name.empty?
            before = group.name.to_s
            group.name = name
            { 'id' => group.persistent_id, 'trace_id' => Na__DataSerializer.Na__DataSerializer__ReadTraceId(group), 'name' => name, 'was' => before,
              'summary' => "Renamed \"#{before}\" to \"#{name}\"." }
        end

        def self.na_edit_delete(params)
            model  = self.na_model(params)
            groups = self.na_traces_from_params(params)
            groups.each { |group| self.na_require_closed(model, group) }
            gone = groups.map { |group| { 'id' => group.persistent_id, 'trace_id' => Na__DataSerializer.Na__DataSerializer__ReadTraceId(group), 'name' => group.name.to_s } }
            groups.each { |group| group.erase! if group.valid? }
            { 'deleted' => gone, 'summary' => "#{gone.length} trace(s) erased (one undo brings them back)." }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Edit - open_dialog / reload (no model change)
# -----------------------------------------------------------------------------

        # Never through Na__PublicApi__OpenDialog: its failure path shows a
        # message box, and a modal stops the MCP bridge.
        def self.na_edit_open_dialog(params)
            model = self.na_model(params)
            selected = nil
            if self.na_has?(params, 'id') || self.na_has?(params, 'trace_id')
                selected = self.na_traces_from_params(params, single: true).first
                model.selection.clear
                model.selection.add(selected)
            end
            Na__ProfileTools__ProfilePathTracer.Na__Runtime__EnsureUnifiedGeometryBuilders
            Na__Observers.Na__Observers__InstallOnce
            Na__DialogManager.Na__Dialog__Show
            {
                'open'     => Na__DialogManager.Na__Dialog__Visible?,
                'selected' => selected ? selected.persistent_id : nil,
                'summary'  => selected ? "Dialog open with #{Na__DataSerializer.Na__DataSerializer__ReadTraceId(selected)} selected: Draw Profile's From Model (or Edit Profile on the Apply tab) binds it, in Live mode." : 'Dialog open.'
            }
        rescue Na__McpOperationsError
            raise
        rescue StandardError => error
            self.na_refuse('operation_failed', "The dialog did not open: #{error.message}", 'Open it from the toolbar instead.')
        end

        def self.na_edit_reload(_params)
            result = Na__PluginReloader.Na__Reload__PluginFiles(Na__ProfileTools__ProfilePathTracer::NA_PLUGIN_ROOT)
            {
                'reloaded' => result['isSuccess'] == true,
                'ruby_files' => result['rubyFileCount'],
                'issues'   => result['issues'],
                'summary'  => result['statusMessage'].to_s
            }
        end

# endregion -------------------------------------------------------------------

    end # module Na__McpOperations
end # module Na__ProfileTools__ProfilePathTracer

# =============================================================================
# END OF FILE
# =============================================================================
