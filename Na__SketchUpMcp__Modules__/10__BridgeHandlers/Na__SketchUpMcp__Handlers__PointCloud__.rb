# =============================================================================
# NA SKETCHUP MCP - HANDLERS - POINT CLOUD VIEWER
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__PointCloud__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__PointCloud
# PURPOSE    : point_cloud_state, point_cloud_clip, point_cloud_view,
#              point_cloud_slice, point_cloud_fit (1.0.14, viewer 0.14.2),
#              point_cloud_check (1.0.15, viewer 0.14.3),
#              point_cloud_heightmap (1.0.16, viewer 0.14.4); a slice frame
#              for point_cloud_slice and point_cloud_heightmap (1.0.19, 0.14.6)
# CREATED    : 09-Nov-2026 (1.0.9); points and density 09-Nov-2026 (1.0.12,
#              viewer 0.14.0, engine ABI 9)
#
# A THIN SEAM:
# The rules live in Adam's Na Point Cloud Viewer (0.13.1 or newer:
# 02__Src__AppModules/95__System__McpOperations). These handlers only read the
# call's lengths into model inches (Na__Units), turn entity ids into world
# bounds for a clip box "around" them, pick a capture path for images, call
# Na__PointCloudViewer::Na__McpOperations, and turn its refusals
# (Na__McpOperationsError: code, message, hint, details) into Na__McpError.
# The seam multiplies every length it returns by per_inch, so results come
# back in the call's units. Without the viewer, every tool refuses and names
# the fix.
#
# UNDO:
# point_cloud_state and point_cloud_slice do not mutate. point_cloud_view
# changes view settings only (never the model, no undo step). point_cloud_clip
# has "operation": false: the viewer writes the cloud's record in its own
# undo operation ("Point Cloud: ..."), and SketchUp does not nest operations,
# so it is also not allowed in batch_execute.
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Handlers__PointCloud

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_CLIP_ACTIONS  = %w[box around on off scene].freeze
        NA_SLICE_ACTIONS = %w[count histogram points image density].freeze
        NA_SEAM_ACTION   = { 'box' => 'clip_box', 'around' => 'clip_box', 'on' => 'clip_on', 'off' => 'clip_off', 'scene' => 'clip_scene' }.freeze
        NA_VIEW_KEYS     = %w[shown point_size_px opacity_percent colour_mode point_budget overlay reload].freeze
        NA_PARTNER_ERROR = 'Na__PointCloudViewer::Na__McpOperationsError'.freeze
        NA_MAX_OVERLAY_EDGES = 200_000
        NA_MAX_CHECK_TRIANGLES = 300_000
        NA_GRID_ONLY_KEYS = %w[resolution contour colours overlay_ids overlay_clip].freeze
        NA_PROFILE_ONLY_KEYS = %w[path width step exaggeration].freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | point_cloud_state / point_cloud_clip / point_cloud_view / point_cloud_slice
# -----------------------------------------------------------------------------

        def self.Na__Handlers__PointCloud__State(params, ctx)
            operations = na_operations
            arguments = na_arguments(ctx)
            arguments['clouds'] = na_clouds(params) if Na__Params.Na__Params__Has(params, 'clouds')
            na_forward(ctx) { operations.Na__PointCloudViewer__McpRead('state', arguments) }
        end

        def self.Na__Handlers__PointCloud__Clip(params, ctx)
            action = Na__Params.Na__Params__Enum(params, 'action', NA_CLIP_ACTIONS, nil, required: true)
            operations = na_operations
            arguments = na_arguments(ctx)
            arguments['clouds'] = na_clouds(params) if Na__Params.Na__Params__Has(params, 'clouds')
            arguments['label'] = Na__Params.Na__Params__String(params, 'label') if Na__Params.Na__Params__Has(params, 'label')
            case action
            when 'box'
                na_box(params, ctx, arguments)
            when 'around'
                arguments['around'] = na_bounds_of(params, ctx)
                if Na__Params.Na__Params__Has(params, 'margin')
                    arguments['margin'] = Na__Units.Na__Units__ToInches(params['margin'], ctx[:unit], 'margin')
                end
            when 'scene'
                arguments['cloud'] = Na__Params.Na__Params__String(params, 'cloud') if Na__Params.Na__Params__Has(params, 'cloud')
                arguments['scene'] = Na__Params.Na__Params__String(params, 'scene', nil, required: true)
            end
            result = na_forward(ctx) { operations.Na__PointCloudViewer__McpEdit(NA_SEAM_ACTION[action], arguments) }
            ctx[:undo_name] = result['undo_step'] if result.is_a?(Hash) && result['undo_step']
            result
        end

        def self.Na__Handlers__PointCloud__View(params, ctx)
            operations = na_operations
            arguments = na_arguments(ctx)
            arguments['clouds'] = na_clouds(params) if Na__Params.Na__Params__Has(params, 'clouds')
            # A key sent as null is not given (1.0.17): shown: null must not hide every cloud.
            NA_VIEW_KEYS.each { |key| arguments[key] = params[key] if Na__Params.Na__Params__Has(params, key) }
            arguments['colour_mode'] = Na__Params.Na__Params__String(params, 'colour_mode') if Na__Params.Na__Params__Has(params, 'colour_mode')
            %w[shown overlay reload].each do |key|
                arguments[key] = Na__Params.Na__Params__Boolean(params, key) if Na__Params.Na__Params__Has(params, key)
            end
            na_forward(ctx) { operations.Na__PointCloudViewer__McpEdit('view', arguments) }
        end

        def self.Na__Handlers__PointCloud__Slice(params, ctx)
            action = Na__Params.Na__Params__Enum(params, 'action', NA_SLICE_ACTIONS, nil, required: true)
            operations = na_operations
            na_require_action(operations, action)
            arguments = na_arguments(ctx)
            arguments['cloud'] = Na__Params.Na__Params__String(params, 'cloud') if Na__Params.Na__Params__Has(params, 'cloud')
            na_box(params, ctx, arguments)
            arguments['frame'] = na_frame(params, ctx, operations) if Na__Params.Na__Params__Has(params, 'frame')
            if Na__Params.Na__Params__Has(params, 'overlay_ids')
                unless %w[image density].include?(action)
                    raise Na__McpError.new('invalid_params', "overlay_ids draws over an image; #{action} has none.", 'Use it with action image or density.')
                end
                unless operations::NA_READ_ACTIONS.include?('composite')
                    raise Na__McpError.new('unsupported', 'overlay_ids needs Na Point Cloud Viewer 0.14.1 or newer.',
                                           'Update the Point Cloud Viewer, use its Reload Plugin (Settings), then call again.')
                end
                arguments['overlay_segments'] = na_overlay_segments(params, ctx)
                arguments['overlay_clip'] = Na__Params.Na__Params__Boolean(params, 'overlay_clip', false)
            end
            case action
            when 'histogram'
                arguments['axis'] = Na__Params.Na__Params__Enum(params, 'axis', %w[x y z], nil, required: true)
                arguments['bin'] = Na__Units.Na__Units__PositiveLength(Na__Params.Na__Params__Required(params, 'bin'), ctx[:unit], 'bin')
                arguments['peak_share'] = Na__Params.Na__Params__Number(params, 'peak_share', 0.2, min: 0.0, max: 1.0)
            when 'points'
                arguments['limit'] = Na__Params.Na__Params__Integer(params, 'limit', nil, min: 1, max: 5_000_000) if Na__Params.Na__Params__Has(params, 'limit')
                arguments['out_path'] = na_npz_path(params) if Na__Params.Na__Params__Has(params, 'save_path')
            when 'image', 'density'
                arguments['view'] = Na__Params.Na__Params__Enum(params, 'view', %w[top front back left right], nil, required: true)
                arguments['resolution'] = Na__Units.Na__Units__PositiveLength(Na__Params.Na__Params__Required(params, 'resolution'), ctx[:unit], 'resolution')
                if Na__Params.Na__Params__Has(params, 'grid')
                    arguments['grid'] = Na__Units.Na__Units__ToInches(params['grid'], ctx[:unit], 'grid')
                end
                if action == 'image'
                    arguments['point_size_px'] = Na__Params.Na__Params__Integer(params, 'point_size_px', 1, min: 1, max: 10)
                else
                    arguments['scale'] = Na__Params.Na__Params__Enum(params, 'scale', %w[log linear], 'log')
                end
                arguments['out_path'] = Na__Handlers__View.na_capture_path(params, 'png')
            end
            result = na_forward(ctx) { operations.Na__PointCloudViewer__McpRead(action, arguments) }
            result['keep_file'] = Na__Params.Na__Params__Has(params, 'save_path') if result.is_a?(Hash) && result.key?('image_file')
            result
        end

# endregion -------------------------------------------------------------------

        # point_cloud_check (1.0.15): the model's faces become world triangles
        # here (the coordinate rule stays in Na__Serializer), each labelled with
        # its part; the seam measures the cloud against them.
        def self.Na__Handlers__PointCloud__Check(params, ctx)
            operations = na_operations
            unless operations.const_defined?(:NA_READ_ACTIONS) && operations::NA_READ_ACTIONS.include?('check')
                raise Na__McpError.new('unsupported', 'point_cloud_check needs Na Point Cloud Viewer 0.14.3 or newer.',
                                       'Update the Point Cloud Viewer, use its Reload Plugin (Settings), then call again.')
            end
            arguments = na_arguments(ctx)
            arguments['cloud'] = Na__Params.Na__Params__String(params, 'cloud') if Na__Params.Na__Params__Has(params, 'cloud')
            triangles, parts, low, high = na_check_model(params, ctx)
            arguments['triangles'] = triangles
            arguments['parts'] = parts
            if Na__Params.Na__Params__Has(params, 'min') || Na__Params.Na__Params__Has(params, 'max')
                na_box(params, ctx, arguments)
            else
                margin = Na__Params.Na__Params__Has(params, 'margin') ? Na__Units.Na__Units__ToInches(params['margin'], ctx[:unit], 'margin') : 100.0 / 25.4
                raise Na__McpError.new('invalid_params', 'margin must be 0 or more.', 'Pass e.g. 100 (mm).') if margin < 0
                arguments['min'] = low.map { |value| value - margin }
                arguments['max'] = high.map { |value| value + margin }
            end
            %w[tolerance reach].each do |key|
                arguments[key] = Na__Units.Na__Units__PositiveLength(params[key], ctx[:unit], key) if Na__Params.Na__Params__Has(params, key)
            end
            arguments['sample'] = Na__Params.Na__Params__Integer(params, 'sample', 20_000, min: 100, max: 100_000)
            if Na__Params.Na__Params__Has(params, 'view')
                arguments['view'] = Na__Params.Na__Params__Enum(params, 'view', %w[top front back left right], nil, required: true)
                arguments['resolution'] = Na__Units.Na__Units__PositiveLength(Na__Params.Na__Params__Required(params, 'resolution'), ctx[:unit], 'resolution')
                arguments['grid'] = Na__Units.Na__Units__ToInches(params['grid'], ctx[:unit], 'grid') if Na__Params.Na__Params__Has(params, 'grid')
                arguments['point_size_px'] = Na__Params.Na__Params__Integer(params, 'point_size_px', 2, min: 1, max: 10)
                # The edges only dress the heatmap: none to draw, or too many, never refuses the check (1.0.17).
                arguments['edges'] = na_overlay_segments(params, ctx, 'ids', required: false)
                arguments['out_path'] = Na__Handlers__View.na_capture_path(params, 'png')
            end
            result = na_forward(ctx) { operations.Na__PointCloudViewer__McpRead('check', arguments) }
            result['keep_file'] = Na__Params.Na__Params__Has(params, 'save_path') if result.is_a?(Hash) && result.key?('image_file')
            result
        end

        # [triangles, parts, low, high]: every face shown under ids as world
        # triangles [a, b, c, outward normal, part] (inches), the parts
        # [{ 'name', 'id' }] (each group or component shown directly inside an
        # id, and the id itself for its loose faces), and the triangles'
        # bounds. Shown as SketchUp draws it (na_shown?): a hidden group, a
        # hidden face or one on a hidden tag inside an id is left out (1.0.17);
        # an id itself is measured even when hidden, with a warning.
        def self.na_check_model(params, ctx)
            ids = Na__Params.Na__Params__IdArray(params, 'ids')
            entities = Na__EntityResolver.Na__EntityResolver__RequireEntities(ctx[:model], ids, 'ids')
            budget = Na__Traversal.Na__Traversal__NewBudget
            triangles = []
            parts = []
            new_part = lambda do |entity|
                parts << { 'name' => Na__EntityResolver.Na__EntityResolver__DisplayName(entity), 'id' => entity.persistent_id }
                parts.length - 1
            end
            add_face = lambda do |face, path, part|
                world = Na__Serializer.Na__Serializer__ToWorld(ctx, path)
                transform = world[:transform]
                normal = Na__Serializer.na_world_normal(face.normal, world)
                mesh = face.mesh(0)
                corners = mesh.points.map { |point| (transform * point).to_a.map(&:to_f) }
                mesh.polygons.each do |polygon|
                    next unless polygon.length == 3
                    a, b, c = polygon.map { |index| corners[index.abs - 1] }
                    triangles << [a, b, c, normal, part]
                end
                if triangles.length > NA_MAX_CHECK_TRIANGLES
                    raise Na__McpError.new('invalid_params', "The model holds more than #{NA_MAX_CHECK_TRIANGLES} triangles.", 'Check a smaller group, or its parts one at a time.')
                end
            end
            entities.each do |entity|
                path = Na__Serializer.Na__Serializer__ContainerPath(ctx, entity)
                unless na_shown?(entity)
                    ctx[:warnings] << "ids: #{Na__EntityResolver.Na__EntityResolver__DisplayName(entity)} is hidden in the model; it was measured because you named it."
                end
                if entity.is_a?(Sketchup::Face)
                    add_face.call(entity, path, new_part.call(entity))
                elsif Na__EntityResolver.Na__EntityResolver__IsInstance(entity)
                    inside = path + [entity]
                    own = nil
                    entity.definition.entities.each do |child|
                        next unless na_shown?(child)
                        if child.is_a?(Sketchup::Face)
                            own ||= new_part.call(entity)
                            add_face.call(child, inside, own)
                        elsif Na__EntityResolver.Na__EntityResolver__IsInstance(child)
                            part = new_part.call(child)
                            na_walk_shown(child.definition.entities, inside + [child], budget) do |item, item_path|
                                add_face.call(item, item_path, part) if item.is_a?(Sketchup::Face)
                            end
                        end
                    end
                else
                    raise Na__McpError.new('wrong_type', "Entity #{entity.persistent_id} is a #{Na__EntityResolver.Na__EntityResolver__TypeName(entity)}, which has no faces.",
                                           'Pass groups, components or faces.')
                end
            end
            ctx[:warnings] << 'ids: the walk stopped at the traversal limit, so some faces are missing.' if budget[:truncated]
            raise Na__McpError.new('wrong_type', 'ids holds no visible faces to check against.', 'Pass groups, components or faces.') if triangles.empty?
            low = [0, 1, 2].map { |axis| triangles.map { |t| [t[0][axis], t[1][axis], t[2][axis]].min }.min }
            high = [0, 1, 2].map { |axis| triangles.map { |t| [t[0][axis], t[1][axis], t[2][axis]].max }.max }
            [triangles, parts, low, high]
        end

        # point_cloud_heightmap (1.0.16): heights per cell of a box (grid) or
        # along a path (profile). Lengths, the path and file names are read
        # here; the binning, statistics and pictures are the seam's
        # (Na__McpHeight, viewer 0.14.4).
        def self.Na__Handlers__PointCloud__Heightmap(params, ctx)
            action = Na__Params.Na__Params__Enum(params, 'action', %w[grid profile], 'grid')
            stray = (action == 'grid' ? NA_PROFILE_ONLY_KEYS : NA_GRID_ONLY_KEYS).select { |key| Na__Params.Na__Params__Has(params, key) }
            unless stray.empty?
                raise Na__McpError.new('invalid_params', "#{stray.join(', ')} #{stray.length == 1 ? 'is' : 'are'} for action #{action == 'grid' ? 'profile' : 'grid'}.",
                                       action == 'grid' ? 'Pass action: "profile" to read heights along a path.' : 'Leave them out, or use action grid.')
            end
            operations = na_operations
            unless operations.const_defined?(:NA_READ_ACTIONS) && operations::NA_READ_ACTIONS.include?('heightmap')
                raise Na__McpError.new('unsupported', 'point_cloud_heightmap needs Na Point Cloud Viewer 0.14.4 or newer.',
                                       'Update the Point Cloud Viewer, use its Reload Plugin (Settings), then call again.')
            end
            arguments = na_arguments(ctx)
            arguments['cloud'] = Na__Params.Na__Params__String(params, 'cloud') if Na__Params.Na__Params__Has(params, 'cloud')
            arguments['view'] = Na__Params.Na__Params__Enum(params, 'view', %w[top front back left right], 'top')
            if Na__Params.Na__Params__Has(params, 'stats')
                arguments['stats'] = Na__Params.Na__Params__Array(params, 'stats', nil, min_items: 1, max_items: 8).map do |stat|
                    next stat if stat.is_a?(String)
                    raise Na__McpError.new('invalid_params', "stats holds #{stat.inspect}; each is a name such as \"p2\", \"median\" or \"max\".", 'Pass e.g. ["p2", "p50", "p98"].')
                end
            end
            arguments['show'] = Na__Params.Na__Params__String(params, 'show') if Na__Params.Na__Params__Has(params, 'show')
            arguments['sample'] = Na__Params.Na__Params__Integer(params, 'sample', 1_000_000, min: 1_000, max: 5_000_000)
            arguments['frame'] = na_frame(params, ctx, operations) if Na__Params.Na__Params__Has(params, 'frame')
            if action == 'grid'
                na_box(params, ctx, arguments)
                arguments['resolution'] = if Na__Params.Na__Params__Has(params, 'resolution')
                                              Na__Units.Na__Units__PositiveLength(params['resolution'], ctx[:unit], 'resolution')
                                          else
                                              50.0 / 25.4
                                          end
                arguments['contour'] = Na__Units.Na__Units__ToInches(params['contour'], ctx[:unit], 'contour') if Na__Params.Na__Params__Has(params, 'contour')
                arguments['colours'] = Na__Params.Na__Params__Boolean(params, 'colours', false)
                if Na__Params.Na__Params__Has(params, 'overlay_ids')
                    arguments['overlay_segments'] = na_overlay_segments(params, ctx)
                    arguments['overlay_clip'] = Na__Params.Na__Params__Boolean(params, 'overlay_clip', false)
                end
                arguments['file_path'] = na_save_path(params, %w[.npz .asc]) if Na__Params.Na__Params__Has(params, 'save_path')
            else
                points = Na__Params.Na__Params__Array(params, 'path', nil, required: true, min_items: 2, max_items: 50)
                arguments['path'] = points.each_with_index.map { |point, index| Na__Units.Na__Units__Point(point, ctx[:unit], "path[#{index}]").to_a.map(&:to_f) }
                %w[width step].each do |key|
                    arguments[key] = Na__Units.Na__Units__PositiveLength(params[key], ctx[:unit], key) if Na__Params.Na__Params__Has(params, key)
                end
                if Na__Params.Na__Params__Has(params, 'exaggeration')
                    arguments['exaggeration'] = Na__Params.Na__Params__Number(params, 'exaggeration', nil, min: 0.1, max: 100.0)
                end
                na_box(params, ctx, arguments) if Na__Params.Na__Params__Has(params, 'min') || Na__Params.Na__Params__Has(params, 'max')
                arguments['file_path'] = na_save_path(params, %w[.csv .npz]) if Na__Params.Na__Params__Has(params, 'save_path')
            end
            arguments['out_path'] = na_image_path(params)
            result = na_forward(ctx) { operations.Na__PointCloudViewer__McpRead(action == 'grid' ? 'heightmap' : 'profile', arguments) }
            result['keep_file'] = Na__Params.Na__Params__Has(params, 'image_path') if result.is_a?(Hash) && result.key?('image_file')
            result
        end

        # point_cloud_fit (1.0.14): lengths read here, everything else in the
        # viewer's seam (Na__McpFit), as for the other point cloud tools.
        def self.Na__Handlers__PointCloud__Fit(params, ctx)
            shape = Na__Params.Na__Params__Enum(params, 'shape', %w[plane line circle cylinder box], nil, required: true)
            operations = na_operations
            unless operations.const_defined?(:NA_READ_ACTIONS) && operations::NA_READ_ACTIONS.include?('fit')
                raise Na__McpError.new('unsupported', 'point_cloud_fit needs Na Point Cloud Viewer 0.14.2 or newer.',
                                       'Update the Point Cloud Viewer, use its Reload Plugin (Settings), then call again.')
            end
            arguments = na_arguments(ctx)
            arguments['shape'] = shape
            arguments['cloud'] = Na__Params.Na__Params__String(params, 'cloud') if Na__Params.Na__Params__Has(params, 'cloud')
            na_box(params, ctx, arguments)
            %w[tolerance max_radius].each do |key|
                next unless Na__Params.Na__Params__Has(params, key)
                arguments[key] = Na__Units.Na__Units__PositiveLength(params[key], ctx[:unit], key)
            end
            arguments['orientation'] = Na__Params.Na__Params__Enum(params, 'orientation', %w[any horizontal vertical], 'any')
            arguments['axis'] = Na__Params.Na__Params__Enum(params, 'axis', %w[x y z], 'z')
            arguments['trim'] = Na__Params.Na__Params__Number(params, 'trim', 1.0, min: 0.0, max: 20.0)
            arguments['sample'] = Na__Params.Na__Params__Integer(params, 'sample', 20_000, min: 100, max: 200_000)
            na_forward(ctx) { operations.Na__PointCloudViewer__McpRead('fit', arguments) }
        end

# -----------------------------------------------------------------------------
# REGION | Helpers
# -----------------------------------------------------------------------------

        # World segments [[a, b], ...] (model inches) of every edge the entities
        # named by key hold: an edge, a face's edges, everything shown inside a
        # group or component at any depth. Soft edges, and edges hidden or on a
        # hidden tag (or inside a hidden group), are left out, as SketchUp leaves
        # them out of its view. The coordinate rule stays in Na__Serializer /
        # Na__Coordinates. required: false (the check's heatmap) turns "none to
        # draw" and "too many" into a warning and no edges.
        def self.na_overlay_segments(params, ctx, key = 'overlay_ids', required: true)
            ids = Na__Params.Na__Params__IdArray(params, key)
            entities = Na__EntityResolver.Na__EntityResolver__RequireEntities(ctx[:model], ids, key)
            budget = Na__Traversal.Na__Traversal__NewBudget
            segments = []
            add = lambda do |edge, path|
                next if edge.soft? || !na_shown?(edge)
                world = Na__Serializer.Na__Serializer__ToWorld(ctx, path)[:transform]
                segments << [(world * edge.start.position).to_a.map(&:to_f), (world * edge.end.position).to_a.map(&:to_f)]
            end
            entities.each do |entity|
                path = Na__Serializer.Na__Serializer__ContainerPath(ctx, entity)
                if entity.is_a?(Sketchup::Edge)
                    add.call(entity, path)
                elsif entity.is_a?(Sketchup::Face)
                    entity.edges.each { |edge| add.call(edge, path) }
                elsif Na__EntityResolver.Na__EntityResolver__IsInstance(entity)
                    na_walk_shown(entity.definition.entities, path + [entity], budget) do |child, child_path|
                        add.call(child, child_path) if child.is_a?(Sketchup::Edge)
                    end
                end
                next unless segments.length > NA_MAX_OVERLAY_EDGES
                unless required
                    ctx[:warnings] << "The model's edges were left off the picture: #{key} holds more than #{NA_MAX_OVERLAY_EDGES} of them."
                    return []
                end
                raise Na__McpError.new('invalid_params', "#{key} holds more than #{NA_MAX_OVERLAY_EDGES} edges.", 'Pass the smaller groups that matter for this picture.')
            end
            ctx[:warnings] << "#{key}: the walk stopped at the traversal limit, so some edges are missing." if budget[:truncated]
            if segments.empty?
                unless required
                    ctx[:warnings] << "#{key} holds no visible edges, so none are drawn over the picture."
                    return []
                end
                raise Na__McpError.new('wrong_type', "#{key} holds no visible edges to draw.", 'Pass groups, components, faces or edges (ids from entity_query or outliner_tree).')
            end
            segments
        end

        # Shown as SketchUp draws it: not hidden, its tag on, and every tag
        # folder above that tag on. (A hidden parent is handled by the walk,
        # which never goes into one.)
        def self.na_shown?(entity)
            return false if entity.respond_to?(:hidden?) && entity.hidden?
            layer = entity.respond_to?(:layer) ? entity.layer : nil
            return true unless layer
            return false unless layer.visible?
            folder = layer.respond_to?(:folder) ? layer.folder : nil
            while folder
                return false unless folder.visible?
                folder = folder.folder
            end
            true
        end

        # Every entity shown inside entities, with its container path, going
        # into shown groups and components only (64 deep at most), within the
        # traversal budget: Na__Traversal__Walk's rules plus na_shown?.
        def self.na_walk_shown(entities, path, budget, depth = 0, &block)
            entities.each do |entity|
                if budget[:remaining] <= 0
                    budget[:truncated] = true
                    return
                end
                budget[:remaining] -= 1
                budget[:visited] += 1
                next unless na_shown?(entity)
                yield(entity, path)
                next unless depth < 64 && Na__EntityResolver.Na__EntityResolver__IsInstance(entity)
                na_walk_shown(entity.definition.entities, path + [entity], budget, depth + 1, &block)
                return if budget[:truncated]
            end
        end

        # The viewer's seam, or a refusal that names the fix.
        def self.na_operations
            if defined?(::Na__PointCloudViewer::Na__McpOperations) &&
               ::Na__PointCloudViewer::Na__McpOperations.respond_to?(:Na__PointCloudViewer__McpRead)
                return ::Na__PointCloudViewer::Na__McpOperations
            end

            raise Na__McpError.new('unsupported',
                                   'The point cloud tools need Na Point Cloud Viewer 0.13.1 or newer, loaded in this SketchUp.',
                                   'Install or update the Point Cloud Viewer, then use its Reload Plugin (or restart SketchUp).')
        end

        # points and density (1.0.12) need the viewer's 0.14.0 seam (engine ABI 9).
        def self.na_require_action(operations, action)
            known = operations.const_defined?(:NA_READ_ACTIONS) ? operations::NA_READ_ACTIONS : []
            return if known.include?(action)

            viewer = ::Na__PointCloudViewer.respond_to?(:Na__PublicApi__Version) ? ::Na__PointCloudViewer.Na__PublicApi__Version : 'an older version'
            raise Na__McpError.new('unsupported', "point_cloud_slice #{action} needs Na Point Cloud Viewer 0.14.0 or newer; this SketchUp has #{viewer}.",
                                   'Update the Point Cloud Viewer, use its Reload Plugin (Settings), then call again.')
        end

        # save_path for points: a .npz in a folder that exists; never replaces a
        # file unless overwrite is true.
        def self.na_npz_path(params)
            path = File.expand_path(Na__Params.Na__Params__String(params, 'save_path', nil, required: true))
            path += '.npz' if File.extname(path).empty?
            unless File.extname(path).casecmp?('.npz')
                raise Na__McpError.new('invalid_params', "points are saved as a .npz, not #{File.extname(path)}.", 'Give save_path a .npz name.')
            end
            raise Na__McpError.new('file_error', "Folder does not exist: #{File.dirname(path)}.", 'Create it, or pass another save_path.') unless File.directory?(File.dirname(path))
            if File.exist?(path) && !Na__Params.Na__Params__Boolean(params, 'overwrite', false)
                raise Na__McpError.new('file_error', "#{path} already exists.", 'Pass overwrite: true or choose another save_path.')
            end
            path
        end

        # save_path for a heightmap or profile: one of allowed (the first when no
        # extension is given), in a folder that exists; never replaces a file
        # unless overwrite is true.
        def self.na_save_path(params, allowed)
            path = File.expand_path(Na__Params.Na__Params__String(params, 'save_path', nil, required: true))
            path += allowed.first if File.extname(path).empty?
            unless allowed.any? { |ext| File.extname(path).casecmp?(ext) }
                raise Na__McpError.new('invalid_params', "save_path must end #{allowed.join(' or ')}, not #{File.extname(path)}.", "Give save_path a #{allowed.join(' or ')} name.")
            end
            raise Na__McpError.new('file_error', "Folder does not exist: #{File.dirname(path)}.", 'Create it, or pass another save_path.') unless File.directory?(File.dirname(path))
            if File.exist?(path) && !Na__Params.Na__Params__Boolean(params, 'overwrite', false)
                raise Na__McpError.new('file_error', "#{path} already exists.", 'Pass overwrite: true or choose another save_path.')
            end
            path
        end

        # Where the heightmap's picture goes: image_path (a .png) to keep it, or
        # a capture the server deletes once it has returned it.
        def self.na_image_path(params)
            return Na__Handlers__View.na_capture_path({}, 'png') unless Na__Params.Na__Params__Has(params, 'image_path')
            path = Na__Params.Na__Params__String(params, 'image_path', nil, required: true)
            extension = File.extname(path)
            unless extension.empty? || extension.casecmp?('.png')
                raise Na__McpError.new('invalid_params', "image_path is a .png, not #{extension}.", 'Give image_path a .png name.')
            end
            Na__Handlers__View.na_capture_path({ 'save_path' => path, 'overwrite' => params['overwrite'] }.compact, 'png')
        end

        # frame (1.0.19, viewer 0.14.6): the origin from the call's units into
        # inches, angle and axes as given (the seam makes them square and unit);
        # id alone: that group's or component's world origin and axes, through
        # the coordinate rules in Na__Serializer.
        def self.na_frame(params, ctx, operations)
            unless operations.const_defined?(:NA_FEATURES) && operations::NA_FEATURES.include?('frame')
                raise Na__McpError.new('unsupported', 'frame needs Na Point Cloud Viewer 0.14.6 or newer.',
                                       'Update the Point Cloud Viewer, use its Reload Plugin (Settings), then call again.')
            end
            spec = Na__Params.Na__Params__Hash(params, 'frame', nil, required: true)
            if Na__Params.Na__Params__Has(spec, 'id')
                others = %w[origin angle x_axis y_axis].select { |key| Na__Params.Na__Params__Has(spec, key) }
                unless others.empty?
                    raise Na__McpError.new('invalid_params', "frame id takes no #{others.join(', ')}: the group's own origin and axes make the frame.",
                                           'Pass frame {id} alone, or origin with angle or axes.')
                end
                entity = Na__EntityResolver.Na__EntityResolver__RequireEntities(ctx[:model], [spec['id']], 'frame.id').first
                unless Na__EntityResolver.Na__EntityResolver__IsInstance(entity)
                    raise Na__McpError.new('wrong_type', "frame id #{spec['id']} is a #{Na__EntityResolver.Na__EntityResolver__TypeName(entity)}, which has no axes.",
                                           'Pass a group or component.')
                end
                world = Na__Serializer.Na__Serializer__ToWorld(ctx, Na__Serializer.Na__Serializer__ContainerPath(ctx, entity) + [entity])[:transform]
                return { 'origin' => world.origin.to_a.map(&:to_f), 'x_axis' => world.xaxis.to_a.map(&:to_f), 'y_axis' => world.yaxis.to_a.map(&:to_f) }
            end
            frame = {}
            frame['origin'] = Na__Units.Na__Units__Point(spec['origin'], ctx[:unit], 'frame.origin').to_a.map(&:to_f) if Na__Params.Na__Params__Has(spec, 'origin')
            %w[angle x_axis y_axis].each { |key| frame[key] = spec[key] if Na__Params.Na__Params__Has(spec, key) }
            frame
        end

        # What every seam call gets: how many of the call's units make an inch.
        def self.na_arguments(ctx)
            { 'per_inch' => 1.0 / Na__Units::NA_INCHES_PER_UNIT.fetch(ctx[:unit]) }
        end

        def self.na_clouds(params)
            clouds = Na__Params.Na__Params__Array(params, 'clouds', nil, min_items: 1, max_items: 16)
            clouds.map do |cloud|
                next cloud.to_s if cloud.is_a?(String) && !cloud.strip.empty?

                raise Na__McpError.new('invalid_params', "clouds holds #{cloud.inspect}; each must be a cloud id or name.",
                                       'Read them with point_cloud_state, e.g. "pc_264338fa".')
            end
        end

        # min and max in the call's units -> model inches.
        def self.na_box(params, ctx, arguments)
            minimum = Na__Units.Na__Units__Point(Na__Params.Na__Params__Required(params, 'min'), ctx[:unit], 'min')
            maximum = Na__Units.Na__Units__Point(Na__Params.Na__Params__Required(params, 'max'), ctx[:unit], 'max')
            arguments['min'] = minimum.to_a
            arguments['max'] = maximum.to_a
        end

        # [[min], [max]] in model inches: the world bounds of the entities named
        # by ids, at any depth of nesting.
        def self.na_bounds_of(params, ctx)
            ids = Na__Params.Na__Params__IdArray(params, 'ids')
            entities = Na__EntityResolver.Na__EntityResolver__RequireEntities(ctx[:model], ids, 'ids')
            corners = Na__Serializer.Na__Serializer__WorldBoundsOfMany(entities, ctx)
            return corners.map { |point| point.to_a.map(&:to_f) } if corners

            raise Na__McpError.new('wrong_type', 'None of those ids has bounds to fit a clip box round.',
                                   'Pass groups, components, faces or edges (ids from entity_query or outliner_tree).')
        end

        # Runs the seam call, moves its warnings onto the response, adds the
        # units and turns its refusals into Na__McpError.
        def self.na_forward(ctx)
            result = yield
            if result.is_a?(Hash)
                Array(result.delete('warnings')).each { |text| ctx[:warnings] << text.to_s }
                result['units'] = ctx[:unit]
            end
            result
        rescue Na__McpError
            raise
        rescue StandardError => error
            raise unless error.class.name.to_s == NA_PARTNER_ERROR

            raise Na__McpError.new(error.na_code, error.message, error.na_hint, error.na_details)
        end

# endregion -------------------------------------------------------------------

    end # module Na__Handlers__PointCloud
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
