# =============================================================================
# NA SKETCHUP MCP - HANDLERS - SKETCH INTAKE (sketch_read, input_pick, proposal_preview)
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__SketchIntake__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__SketchIntake
# PURPOSE    : The ways Adam gives an agent intent fast, and the gate before an
#              agent builds from a site photo:
#              - sketch_read: rough lines and notes he drew, read as clean
#                polylines (lines and fitted arcs) plus the numbers he wrote
#              - input_pick: he clicks points in SketchUp and the agent gets
#                them, snapped by SketchUp's own inference
#              - proposal_preview: the agent draws a 2D proposal in red, posts
#                a top-view picture to the Agent Outliner and waits for him
# CREATED    : 12-Nov-2026 (1.0.30)
#
# COORDINATES:
# Everything an agent sends and receives is world space. Selected and nested
# edges go to world through Na__Serializer__ToWorld (the coordinate rule lives
# there); InputPoint#position is always world; a proposal is a new group at the
# model root pinned to the identity, so world in = world out.
#
# UNDO:
# sketch_read and input_pick never change the model. proposal_preview draws and
# clears in one "MCP: Proposal Preview" step each; it has "operation": false
# because its question to Adam is written by the Agent Outliner in that
# plugin's own undo step, which cannot sit inside ours.
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Handlers__SketchIntake

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_PROPOSAL_PREFIX   = 'PROPOSAL__'.freeze
        NA_PROPOSAL_DICT     = 'Na__SketchUpMcp__Proposal'.freeze
        NA_PROPOSAL_COLOUR   = '#E8412C'.freeze
        NA_MAX_OUT_POINTS    = 4000
        NA_PICK_ACTIONS      = %w[start result wait cancel].freeze
        NA_PROPOSAL_ACTIONS  = %w[draw status wait clear list].freeze
        NA_NUMBER_PATTERN    = /(-?\d[\d,]*(?:\.\d+)?)\s*(mm|cm|m)?(?![A-Za-z])/.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Shared: World Segments, Texts and Dimensions From Ids or the Selection
# -----------------------------------------------------------------------------

        # FUNCTION | Collect a Sketch in World Inches
        # ------------------------------------------------------------
        # sources: entities (edges, faces, groups/components, texts, dimensions).
        # Groups and components are looked into (hidden ones skipped). Returns
        # { segments: [[[x,y,z],[x,y,z]], ...], texts: [...], dimensions: [...] }.
        def self.Na__Handlers__SketchIntake__WorldSketch(sources, ctx, max_depth = 8)
            sketch = { segments: [], texts: [], dimensions: [], seen: {} }
            budget = Na__Traversal.Na__Traversal__NewBudget
            sources.each do |entity|
                path = Na__Serializer.Na__Serializer__ContainerPath(ctx, entity)
                na_collect(entity, path, ctx, sketch)
                next unless Na__EntityResolver.Na__EntityResolver__IsInstance(entity)

                Na__Traversal.Na__Traversal__Walk(entity.definition.entities, path + [entity], max_depth, budget) do |child, child_path, _depth|
                    na_collect(child, child_path, ctx, sketch) unless child.respond_to?(:hidden?) && child.hidden?
                end
            end
            sketch
        end
        # ---------------------------------------------------------------

        def self.na_collect(entity, path, ctx, sketch)
            world = Na__Serializer.Na__Serializer__ToWorld(ctx, path)[:transform]
            case entity
            when Sketchup::Edge
                return if sketch[:seen][[entity, path.map(&:persistent_id)]]

                sketch[:seen][[entity, path.map(&:persistent_id)]] = true
                a = world * entity.start.position
                b = world * entity.end.position
                sketch[:segments] << [[a.x.to_f, a.y.to_f, a.z.to_f], [b.x.to_f, b.y.to_f, b.z.to_f]]
            when Sketchup::Face
                entity.edges.each { |edge| na_collect(edge, path, ctx, sketch) }
            when Sketchup::Text
                point = world * entity.point
                sketch[:texts] << { text: entity.text.to_s, point: point }
            when Sketchup::DimensionLinear
                a = world * entity.start[1]
                b = world * entity.end[1]
                sketch[:dimensions] << { text: entity.text.to_s, start: a, end: b }
            end
        end

        # Numbers written in a note, in the call's unit ("1100" in a mm call, "1.1m", "1,130 bed").
        def self.na_numbers(text, unit)
            text.to_s.scan(NA_NUMBER_PATTERN).map do |digits, suffix|
                value = digits.delete(',').to_f
                inches = suffix ? Na__Units.Na__Units__ToInches("#{value}#{suffix}", unit) : Na__Units.Na__Units__ToInches(value, unit)
                Na__Units.Na__Units__FromInches(inches, unit).round(3)
            end
        end

        def self.na_round_point(values)
            values.map { |value| value.to_f.round(1) + 0.0 }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | sketch_read
# -----------------------------------------------------------------------------

        def self.Na__Handlers__SketchIntake__Read(params, ctx)
            model = ctx[:model]
            unit = ctx[:unit]
            sources = if Na__Params.Na__Params__Has(params, 'ids')
                          Na__EntityResolver.Na__EntityResolver__RequireEntities(model, Na__Params.Na__Params__IdArray(params, 'ids', required: true), 'ids')
                      else
                          model.selection.to_a
                      end
            if sources.empty?
                raise Na__McpError.new('invalid_params', 'Nothing to read: the selection is empty and no ids were given.',
                                       'Ask Adam to select the lines he drew (and any notes), or pass ids.')
            end

            snap = Na__Units.Na__Units__PositiveLength(params.fetch('snap', Na__Units.Na__Units__FromInches(5.0 / 25.4, unit)), unit, 'snap')
            tolerance = Na__Units.Na__Units__PositiveLength(params.fetch('tolerance', Na__Units.Na__Units__FromInches(15.0 / 25.4, unit)), unit, 'tolerance')
            mm_per_inch = 25.4
            sketch = self.Na__Handlers__SketchIntake__WorldSketch(sources, ctx)
            chains = Na__PlanGeometry.Na__PlanGeometry__ChainSegments(sketch[:segments], snap)

            polylines = chains.each_with_index.map do |chain, index|
                points = chain['points']
                ring = chain['closed'] ? points + [points.first] : points
                runs = Na__PlanGeometry.Na__PlanGeometry__SplitRuns(ring.map { |p| [p[0], p[1]] }, tolerance)
                clean = Na__PlanGeometry.Na__PlanGeometry__CleanPath(ring.map { |p| [p[0], p[1]] }, runs, mm_per_inch)
                clean.pop if chain['closed'] && clean.length > 1 && Na__PlanGeometry.na_dist(clean.first, clean.last) < 1.0e-6
                zs = points.map { |p| p[2] }
                z_mid = (zs.min + zs.max) / 2.0
                out = {
                    'index'      => index,
                    'closed'     => chain['closed'],
                    'length'     => Na__Units.Na__Units__FromInches(Na__PlanGeometry.Na__PlanGeometry__PolylineLength(points, chain['closed']), unit).round(1),
                    'z_range'    => [Na__Units.Na__Units__FromInches(zs.min, unit).round(1), Na__Units.Na__Units__FromInches(zs.max, unit).round(1)],
                    'raw_points' => points.length,
                    'runs'       => runs.map { |run| na_run_out(run, ring, unit) },
                    'clean_path' => clean.first(NA_MAX_OUT_POINTS).map { |p| na_round_point(Na__Units.Na__Units__PointOut(Geom::Point3d.new(p[0], p[1], z_mid), unit)) }
                }
                out['note'] = 'Not flat: z varies along it; runs are fitted in plan.' if (zs.max - zs.min) > snap
                out
            end

            texts = sketch[:texts].map do |text|
                planar = [text[:point].x.to_f, text[:point].y.to_f]
                nearest = chains.each_with_index.map do |chain, index|
                    ring = chain['closed'] ? chain['points'] + [chain['points'].first] : chain['points']
                    distance = ring.each_cons(2).map { |a, b| Na__PlanGeometry.Na__PlanGeometry__PointSegmentDistance(planar, a, b) }.min || Float::INFINITY
                    [index, distance]
                end.min_by { |pair| pair[1] }
                item = { 'text' => text[:text], 'point' => na_round_point(Na__Units.Na__Units__PointOut(text[:point], unit)),
                         'numbers' => na_numbers(text[:text], unit) }
                if nearest && nearest[1].finite?
                    item['near_polyline'] = nearest[0]
                    item['distance'] = Na__Units.Na__Units__FromInches(nearest[1], unit).round(1)
                end
                item
            end
            dimensions = sketch[:dimensions].map do |dimension|
                { 'text' => dimension[:text], 'length' => Na__Units.Na__Units__FromInches(dimension[:start].distance(dimension[:end]), unit).round(1),
                  'start' => na_round_point(Na__Units.Na__Units__PointOut(dimension[:start], unit)),
                  'end' => na_round_point(Na__Units.Na__Units__PointOut(dimension[:end], unit)) }
            end

            {
                'polylines'  => polylines,
                'texts'      => texts,
                'dimensions' => dimensions,
                'counts'     => { 'segments' => sketch[:segments].length, 'polylines' => polylines.length, 'texts' => texts.length, 'dimensions' => dimensions.length },
                'snap'       => Na__Units.Na__Units__FromInches(snap, unit).round(3),
                'tolerance'  => Na__Units.Na__Units__FromInches(tolerance, unit).round(3),
                'units'      => unit,
                'summary'    => "#{polylines.length} polyline(s) from #{sketch[:segments].length} edge(s); #{texts.length} note(s), #{dimensions.length} dimension(s). " \
                                'clean_path is ready for geometry_offset_band path; say the numbers back to Adam before building.'
            }
        end

        def self.na_run_out(run, ring, unit)
            item = { 'type' => run['type'],
                     'from' => na_round_point(Na__Units.Na__Units__PointOut(Geom::Point3d.new(*ring[run['from']]), unit)),
                     'to'   => na_round_point(Na__Units.Na__Units__PointOut(Geom::Point3d.new(*ring[run['to']]), unit)),
                     'max_deviation' => Na__Units.Na__Units__FromInches(run['max_dev'], unit).round(2),
                     'length' => Na__Units.Na__Units__FromInches(Na__PlanGeometry.Na__PlanGeometry__PolylineLength(ring[run['from']..run['to']]), unit).round(1) }
            if run['type'] == 'arc'
                z = ring[run['from']][2]
                item['center'] = na_round_point(Na__Units.Na__Units__PointOut(Geom::Point3d.new(run['center'][0], run['center'][1], z), unit))
                item['radius'] = Na__Units.Na__Units__FromInches(run['radius'], unit).round(1)
                item['sweep_degrees'] = (run['sweep'] * 180.0 / Math::PI).round(2)
            end
            item
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | input_pick: Adam Clicks Points, the Agent Gets Them
# -----------------------------------------------------------------------------

        # State of every pick by id; only one waits at a time.
        @na_picks = {}
        @na_next_pick = 0

        class << self
            attr_reader :na_picks
        end

        # A SketchUp tool that collects clicked points with full inference.
        # Click adds a point, Backspace removes the last, Enter or a double-click
        # finishes, Esc cancels. Positions are InputPoint#position: world, always.
        class Na__PickTool
            def initialize(state)
                @state = state
                @input = Sketchup::InputPoint.new
                @last = Sketchup::InputPoint.new
            end

            def activate
                na_status
                Sketchup.active_model.active_view.invalidate
            end

            def deactivate(view)
                if @state[:status] == 'waiting'
                    @state[:status] = 'cancelled'
                    @state[:reason] = 'Adam switched to another tool'
                end
                view.invalidate
            end

            def resume(_view)
                na_status
            end

            def onMouseMove(_flags, x, y, view)
                @last.valid? ? @input.pick(view, x, y, @last) : @input.pick(view, x, y)
                view.tooltip = @input.tooltip if @input.valid?
                view.invalidate
            end

            def onLButtonDown(_flags, x, y, view)
                @last.valid? ? @input.pick(view, x, y, @last) : @input.pick(view, x, y)
                return unless @input.valid?

                @state[:points] << @input.position
                @last.copy!(@input)
                na_status
                view.invalidate
                na_finish(view) if @state[:max_points] && @state[:points].length >= @state[:max_points]
            end

            def onLButtonDoubleClick(_flags, _x, _y, view)
                na_finish(view) if @state[:points].length >= @state[:min_points]
            end

            def onReturn(view)
                na_finish(view) if @state[:points].length >= @state[:min_points]
            end

            def onKeyDown(key, _repeat, _flags, view)
                return false unless key == 8 && !@state[:points].empty?

                @state[:points].pop
                @last.clear if @state[:points].empty?
                na_status
                view.invalidate
                true
            end

            def onCancel(_reason, view)
                @state[:status] = 'cancelled'
                @state[:reason] = 'Adam pressed Esc'
                Sketchup.active_model.select_tool(nil)
                view.invalidate
            end

            def getExtents
                bounds = Geom::BoundingBox.new
                @state[:points].each { |point| bounds.add(point) }
                bounds.add(@input.position) if @input.valid?
                bounds
            end

            def draw(view)
                points = @state[:points]
                view.line_width = 2
                view.drawing_color = 'red'
                view.draw(GL_LINE_STRIP, points + (@input.valid? && @state[:mode] != 'points' ? [@input.position] : [])) if points.length >= 1 && @state[:mode] != 'points'
                view.draw(GL_LINE_STRIP, [points.last, points.first]) if @state[:mode] == 'polygon' && points.length > 2
                view.draw_points(points, 8, 2, 'red') unless points.empty?
                @input.draw(view) if @input.valid? && @input.display?
            end

            def na_status
                count = @state[:points].length
                Sketchup.status_text = "#{@state[:prompt]}  (#{count} picked: click to add, Backspace to undo, Enter or double-click to finish, Esc to cancel)"
                Sketchup.vcb_label = 'Points'
                Sketchup.vcb_value = count.to_s
            end

            def na_finish(view)
                @state[:status] = 'done'
                Sketchup.active_model.select_tool(nil)
                view.invalidate
            end
        end

        def self.Na__Handlers__SketchIntake__Pick(params, ctx)
            action = Na__Params.Na__Params__Enum(params, 'action', NA_PICK_ACTIONS, 'start')
            case action
            when 'start'
                na_pick_start(params, ctx)
            when 'cancel'
                state = na_pick_state(params)
                if state[:status] == 'waiting'
                    state[:status] = 'cancelled'
                    state[:reason] = 'the agent cancelled it'
                    ctx[:model].select_tool(nil)
                end
                na_pick_out(state, ctx)
            else
                na_pick_out(na_pick_state(params), ctx)
            end
        end

        def self.na_pick_start(params, ctx)
            mode = Na__Params.Na__Params__Enum(params, 'mode', %w[points polyline polygon], 'polyline')
            prompt = Na__Params.Na__Params__String(params, 'prompt', nil, required: true)
            max_points = Na__Params.Na__Params__Integer(params, 'max_points', nil, min: 1, max: 1000)
            round_to = Na__Params.Na__Params__Has(params, 'round_to') ? Na__Units.Na__Units__PositiveLength(params['round_to'], ctx[:unit], 'round_to') : nil
            @na_picks.each_value do |state|
                next unless state[:status] == 'waiting'

                state[:status] = 'cancelled'
                state[:reason] = 'a newer pick replaced it'
            end
            @na_next_pick += 1
            id = "pick_#{@na_next_pick}"
            state = { id: id, status: 'waiting', mode: mode, prompt: prompt, points: [], max_points: max_points,
                      min_points: mode == 'polygon' ? 3 : (mode == 'polyline' ? 2 : 1), round_to: round_to, started: Time.now }
            @na_picks[id] = state
            ctx[:model].select_tool(Na__PickTool.new(state))
            out = na_pick_out(state, ctx)
            out['summary'] = "Waiting for Adam in SketchUp: \"#{prompt}\". Tell him in chat what to click, then call input_pick {action: \"wait\", pick_id: \"#{id}\"}."
            out
        end

        def self.na_pick_state(params)
            id = Na__Params.Na__Params__String(params, 'pick_id', nil)
            state = id ? @na_picks[id] : @na_picks.values.last
            raise Na__McpError.new('not_found', "No pick #{id || 'has been started'}.", 'Start one with input_pick {action: "start", prompt: ...}.') unless state

            state
        end

        def self.na_pick_out(state, ctx)
            unit = ctx[:unit]
            points = state[:points].map do |point|
                values = Na__Units.Na__Units__PointOut(point, unit)
                if state[:round_to]
                    step = Na__Units.Na__Units__FromInches(state[:round_to], unit)
                    values = values.map { |value| ((value / step).round * step).round(6) }
                end
                na_round_point(values)
            end
            out = { 'pick_id' => state[:id], 'status' => state[:status], 'mode' => state[:mode], 'prompt' => state[:prompt],
                    'points' => points, 'count' => points.length, 'units' => unit,
                    'waited_s' => (Time.now - state[:started]).round(1) }
            out['reason'] = state[:reason] if state[:reason]
            out['closed'] = true if state[:mode] == 'polygon'
            out
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | proposal_preview: Draw It in Red, Show Adam, Wait for His Word
# -----------------------------------------------------------------------------

        def self.Na__Handlers__SketchIntake__Proposal(params, ctx)
            action = Na__Params.Na__Params__Enum(params, 'action', NA_PROPOSAL_ACTIONS, nil, required: true)
            case action
            when 'draw'   then na_proposal_draw(params, ctx)
            when 'clear'  then na_proposal_clear(params, ctx)
            when 'list'   then { 'proposals' => na_proposals(ctx[:model]).map { |group| na_proposal_out(group, ctx) } }
            else               na_proposal_status(params, ctx)
            end
        end

        def self.na_proposal_name(params)
            name = Na__Params.Na__Params__String(params, 'name', nil, required: true).strip
            name = name.sub(/\A#{NA_PROPOSAL_PREFIX}/, '')
            raise Na__McpError.new('invalid_params', 'name is empty.', 'Name the proposal as Adam would call it, e.g. "PlantingBed".') if name.empty?

            "#{NA_PROPOSAL_PREFIX}#{name}"
        end

        def self.na_proposals(model)
            model.entities.grep(Sketchup::Group).select { |group| group.name.to_s.start_with?(NA_PROPOSAL_PREFIX) }
        end

        def self.na_find_proposal(model, name)
            na_proposals(model).find { |group| group.name == name }
        end

        def self.na_proposal_draw(params, ctx)
            model = ctx[:model]
            unit = ctx[:unit]
            name = na_proposal_name(params)
            lines = Na__Params.Na__Params__Array(params, 'lines', nil, required: true, min_items: 1, max_items: 2000)
            labels = Na__Params.Na__Params__Array(params, 'labels', [], max_items: 200)
            colour = Na__Params.Na__Params__String(params, 'colour', NA_PROPOSAL_COLOUR)
            # z: draw every point at this height, e.g. just above the paving, so solids never hide the lines.
            flat_z = Na__Params.Na__Params__Has(params, 'z') ? Na__Units.Na__Units__ToInches(params['z'], unit, 'z') : nil
            lift = ->(point) { flat_z ? Geom::Point3d.new(point.x, point.y, flat_z) : point }
            group = nil
            Na__CommandRouter.Na__CommandRouter__WithOperation(ctx, 'MCP: Proposal Preview') do
                old = na_find_proposal(model, name)
                old.erase! if old
                group = model.entities.add_group
                Na__Coordinates.Na__Coordinates__PinGroupToIdentity(group)
                group.name = name
                material = Na__EntityResolver.Na__EntityResolver__ResolveMaterial(model, colour, ctx[:warnings])
                lines.each_with_index do |line, index|
                    unless line.is_a?(Hash) && line['points'].is_a?(Array) && line['points'].length >= 2
                        raise Na__McpError.new('invalid_params', "lines[#{index}] needs points (two or more).", 'Pass {"points": [[x, y, z], ...], "closed": true}.')
                    end

                    points = line['points'].each_with_index.map { |values, k| na_root_point(model, lift.call(Na__Units.Na__Units__Point(values, unit, "lines[#{index}].points[#{k}]"))) }
                    points << points.first if line['closed'] == true && points.length > 2
                    edges = Array(points.length > 2 ? group.entities.add_curve(points) : group.entities.add_edges(points)).compact
                    edges.each { |edge| edge.material = material }
                end
                labels.each_with_index do |label, index|
                    next unless label.is_a?(Hash) && label['text'] && label['point']

                    group.entities.add_text(label['text'].to_s, na_root_point(model, lift.call(Na__Units.Na__Units__Point(label['point'], unit, "labels[#{index}].point"))))
                end
                group.set_attribute(NA_PROPOSAL_DICT, 'created', Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'))
                group.set_attribute(NA_PROPOSAL_DICT, 'note', params['note'].to_s) if params['note']
            end

            out = na_proposal_out(group, ctx)
            unless params['capture'] == false
                capture = Na__Handlers__View.Na__Handlers__View__Capture(
                    { 'zoom_ids' => [group.persistent_id], 'standard_view' => 'top', 'width' => params.fetch('width', 1000), 'height' => params.fetch('height', 700),
                      'save_path' => na_proposal_capture_path(name) }, ctx
                )
                out['capture'] = capture
            end
            if params['ask']
                out['asked'] = na_proposal_ask(group, params, ctx, out['capture'])
            else
                out['next'] = 'Show Adam the picture (chat, or agent_outliner_edit comment with images) and get his yes before building anything from it.'
            end
            out
        end

        # A world point -> a point for the root's entities. The root is a parent of any open
        # group, so its coordinates read as world; this keeps the rule in one place.
        def self.na_root_point(model, point)
            Na__Coordinates.Na__Coordinates__ReportedToWorld(model, []).inverse * point
        end

        def self.na_proposal_capture_path(name)
            directory = Na__PathResolver.Na__PathResolver__EnsureDirectory(Na__PathResolver.Na__PathResolver__CapturesDirectory)
            File.join(directory, "#{name}__#{Time.now.strftime('%Y%m%d_%H%M%S')}.png")
        end

        def self.na_proposal_ask(group, params, ctx, capture)
            text = params['ask'].to_s
            images = capture && (capture['image_file'] || capture['saved_to']) ? [capture['image_file'] || capture['saved_to']] : []
            arguments = { 'action' => 'comment', 'ids' => [group.persistent_id], 'text' => text,
                          'author' => params['author'] || 'Agent (proposal)' }
            arguments['images'] = images unless images.empty?
            result = Na__Handlers__AgentOutliner.Na__Handlers__AgentOutliner__Edit(arguments, ctx)
            group.set_attribute(NA_PROPOSAL_DICT, 'asked', Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'))
            ctx[:undo_name] = 'MCP: Proposal Preview, then MCP: Agent Outliner Edit (the question)'
            { 'question' => text, 'outliner' => result,
              'next' => "Adam answers beside #{group.name} in the Agent Outliner (or in chat). Call proposal_preview {action: \"wait\", name: \"#{group.name}\"} " \
                        'to wait for him, and build nothing until he says yes.' }
        rescue Na__McpError => error
            ctx[:warnings] << "Could not post the question to the Agent Outliner (#{error.message}); ask Adam in chat instead."
            { 'question' => text, 'posted' => false }
        end

        def self.na_proposal_status(params, ctx)
            model = ctx[:model]
            name = na_proposal_name(params)
            group = na_find_proposal(model, name)
            raise Na__McpError.new('not_found', "No proposal #{name} in this model.", 'proposal_preview {action: "list"} shows them.') unless group

            out = na_proposal_out(group, ctx)
            begin
                read = Na__Handlers__AgentOutliner.Na__Handlers__AgentOutliner__Read({ 'action' => 'thread', 'ids' => [group.persistent_id] }, ctx)
                thread = Array(read['threads']).first || {}
                entries = Array((thread['thread'] || {})['entries'])
                last_agent = entries.rindex { |entry| entry['by'] == 'agent' }
                replies = entries.each_with_index.select { |entry, index| entry['by'] == 'user' && (last_agent.nil? || index > last_agent) }.map(&:first)
                out['replies'] = replies.map { |entry| { 'text' => entry['text'], 'at' => entry['at'], 'images' => entry['images'] }.compact }
                out['answered'] = !replies.empty?
                out['thread_status'] = (thread['thread'] || {})['status']
            rescue Na__McpError => error
                out['answered'] = false
                out['note'] = "The Agent Outliner could not be read (#{error.message}); ask Adam in chat."
            end
            out
        end

        def self.na_proposal_clear(params, ctx)
            model = ctx[:model]
            targets = if Na__Params.Na__Params__Boolean(params, 'all', false)
                          na_proposals(model)
                      else
                          [na_find_proposal(model, na_proposal_name(params))].compact
                      end
            names = targets.map(&:name)
            Na__CommandRouter.Na__CommandRouter__WithOperation(ctx, 'MCP: Proposal Preview (clear)') { targets.each(&:erase!) } unless targets.empty?
            { 'cleared' => names, 'summary' => names.empty? ? 'No proposal to clear.' : "Cleared #{names.join(', ')}." }
        end

        def self.na_proposal_out(group, ctx)
            bounds = Na__Serializer.Na__Serializer__WorldBoundsOfMany([group], ctx)
            out = { 'id' => group.persistent_id, 'name' => group.name, 'created' => group.get_attribute(NA_PROPOSAL_DICT, 'created'),
                    'asked' => group.get_attribute(NA_PROPOSAL_DICT, 'asked'),
                    'edges' => group.entities.grep(Sketchup::Edge).length, 'labels' => group.entities.grep(Sketchup::Text).length }
            out['bounds'] = Na__Handlers__Selection.Na__Handlers__Selection__BoundsHash(bounds, ctx[:unit]) if bounds
            out.compact
        end

# endregion -------------------------------------------------------------------

    end # module Na__Handlers__SketchIntake
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
