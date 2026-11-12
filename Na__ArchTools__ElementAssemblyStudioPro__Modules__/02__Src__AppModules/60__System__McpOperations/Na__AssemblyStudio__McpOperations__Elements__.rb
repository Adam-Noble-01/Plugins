# frozen_string_literal: true

# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - MCP OPERATIONS - ELEMENTS (BUILD, UPDATE, READ)
# =============================================================================
#
# FILE       : Na__AssemblyStudio__McpOperations__Elements__.rb
# NAMESPACE  : Na__AssemblyStudio
# MODULE     : Na__McpOperations
# AUTHOR     : Noble Architecture
# CREATED    : 11-Nov-2026 (V2.6.0)
# PURPOSE    : Every window, exterior door (single, double, bifold, sliding),
#              interior door and cabinet: find them, read them, build them
#              into an opening, and rebuild them with new values.
#
# BUILDS GO THROUGH THE DIALOG'S OWN PIPELINES
#   WindowSystem Na__DialogCallbacks.na_pipeline_create / _update (windows and
#   all four exterior doors), InteriorDoorSystem Na__DialogRouter
#   .na_pipeline_create_door / _update_door, Cabinetry Na__DialogRouter
#   .na_pipeline_create / _update / _rename. One undo step each, with the
#   dialog's own names ("Create Window", "Update Bifold Door" ...).
#
# PLACING INTO AN OPENING (what Measure Opening does, without clicking)
#   The opening gives the points the opening tools would pick: A (bottom
#   left seen from outside, on the outside face), B (top right) and D (A
#   carried through to the inside face). Windows and exterior doors take
#   InsertionFrame's 2-point frame on A and B; interior doors its 3-point
#   frame on A, B and D. With fit (default) the size the tools would send
#   is written into the values the agent did not set itself:
#     window family  width = opening width (measured ALONG the wall, so a
#                    rotated wall reads true), height = opening height less
#                    the cill when has_cill and the frame bottom is above 0
#                    (DialogCallbacks na_resolve_cill_subtraction_mm)
#     interior door  opening width, opening height, wall depth
#   Cabinets take a run (A, B and a point on the room side: RunMeasureTool
#   na_frame) and an offset along it, as Insert in Run does.
#
# COORDINATES
#   Points arrive in world inches from the MCP handler. Builds go to the
#   model root (the handler refuses a build while a group is open), so the
#   frame is world.
#
# =============================================================================

module Na__AssemblyStudio
module Na__McpOperations

# -----------------------------------------------------------------------------
# REGION | Elements - Constants
# -----------------------------------------------------------------------------

    NA_INFO_DICT_SUFFIX = 'ConfiguratorInfo'

    NA_UNDO_NAMES = {
        'casement' => 'Create Window', 'sash' => 'Create Window',
        'single' => 'Create Exterior Single Door', 'double' => 'Create Exterior Double Door',
        'bifold' => 'Create Bifold Door', 'sliding' => 'Create Sliding Door',
        'interior_door' => 'Create Interior Door'
    }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Elements - What a Placed Instance Is
# -----------------------------------------------------------------------------

    # FUNCTION | Identify a Placed Element and Read Its Stored Payload
    # ------------------------------------------------------------
    # @return [Hash, nil] { 'system', 'product', 'id', 'root' }
    def self.na_element_of(instance)
        return nil unless instance.is_a?(Sketchup::ComponentInstance) && instance.valid?
        return nil unless na_info_dict?(instance)

        na_require_modules_for('window_family')
        loaded = Na__AssemblyStudio::Na__WindowSystem::Na__DialogCallbacks.na_pipeline_load(instance)
        if loaded
            return { 'system' => 'window_family', 'product' => loaded[:product].to_s, 'id' => loaded[:id], 'root' => na_deep_copy(loaded[:config]) }
        end

        na_require_modules_for('interior_door')
        door_serializer = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__DataSerializer
        if (door_id = door_serializer.na_get_door_id_from_instance(instance))
            stored = door_serializer.na_load_door_data_from_instance(instance, door_id)
            root = stored ? na_deep_copy(stored) : na_fresh_root('interior_door')
            Na__AssemblyStudio::Na__InteriorDoorSystem::Na__DialogRouter.send(:na_normalize_architrave_config_keys!, root)
            return { 'system' => 'interior_door', 'product' => 'interior_door', 'id' => door_id, 'root' => root }
        end

        na_require_modules_for('cabinet')
        cabinet_serializer = Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__DataSerializer
        if (cabinet_id = cabinet_serializer.na_get_id_from_instance(instance))
            stored = cabinet_serializer.na_load_from_instance(instance, cabinet_id)
            root = stored ? na_deep_copy(stored) : na_fresh_root('base')
            metadata = ((root['Na__CabinetMetadata'] ||= [{}])[0] ||= {})
            metadata['Na__Cabinet__UniqueId'] = cabinet_id
            metadata['Na__Cabinet__ComponentName'] = cabinet_serializer.na_current_tail(instance, cabinet_id)
            product = na_product_of_values('cabinet', root['Na__CabinetConfiguration'] || {})
            return { 'system' => 'cabinet', 'product' => product, 'id' => cabinet_id, 'root' => root }
        end
        nil
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Does the Instance Carry Any Studio Info Dictionary
    # ------------------------------------------------------------
    def self.na_info_dict?(instance)
        dictionaries = instance.attribute_dictionaries
        return false unless dictionaries

        dictionaries.any? { |dictionary| dictionary.name.to_s.end_with?(NA_INFO_DICT_SUFFIX) }
    end
    private_class_method :na_info_dict?
    # ---------------------------------------------------------------

    # FUNCTION | The Element the Handler Resolved, or a Refusal
    # ------------------------------------------------------------
    def self.na_require_element(params)
        instance = na_require_instance(params)
        element = na_element_of(instance)
        return [instance, element] if element

        na_refuse('wrong_type', "#{instance.definition.name} was not built by Element Assembly Studio (no window, door or cabinet data on it).",
                  'Find its elements with entity_studio elements, then pass one of their instance_id values.')
    end
    private_class_method :na_require_element
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Read Actions - elements, inspect, openings
# -----------------------------------------------------------------------------

    # FUNCTION | Every Studio Element in the Model, at Any Depth
    # ------------------------------------------------------------
    def self.na_elements(params)
        wanted = params['type'] ? na_product(params['type'])[0] : nil
        query  = params['query'].to_s.strip.downcase
        rows   = []
        empty  = {}                                                            # <-- Definitions already walked that hold no element
        walk = lambda do |entities, to_world, path, depth|
            entities.each do |entity|
                next unless entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)

                world = to_world * entity.transformation
                element = entity.is_a?(Sketchup::ComponentInstance) ? na_element_of(entity) : nil
                if element
                    next if wanted && element['product'] != wanted

                    row = na_element_row(entity, element, world, path)
                    rows << row if query.empty? || [row['id'], row['name'], row['type']].any? { |text| text.to_s.downcase.include?(query) }
                    next
                end
                definition = entity.definition
                next if empty[definition] || depth >= 32

                count = rows.length
                walk.call(definition.entities, world, path + [entity.persistent_id], depth + 1)
                empty[definition] = true if rows.length == count
            end
        end
        walk.call(Sketchup.active_model.entities, Geom::Transformation.new, [], 0)

        counts = rows.group_by { |row| row['type'] }.transform_values(&:length)
        shared = rows.select { |row| row['copies'] > 1 }.map { |row| row['id'] }.uniq
        {
            'elements' => rows,
            'counts'   => counts,
            'warnings' => shared.empty? ? [] : ["#{shared.join(', ')} #{shared.length == 1 ? 'is' : 'are'} placed more than once: an update rebuilds every copy."],
            'summary'  => rows.empty? ? 'No Element Assembly Studio elements in this model.' :
                          "#{rows.length} element#{rows.length == 1 ? '' : 's'}: #{counts.map { |type, count| "#{count} #{type}" }.join(', ')}."
        }
    end
    private_class_method :na_elements
    # ---------------------------------------------------------------

    # HELPER FUNCTION | One Element Row (World Placement, Size, Copies)
    # ------------------------------------------------------------
    def self.na_element_row(instance, element, world, path)
        values = element['root'][NA_CONFIG_BLOCK[element['system']]] || {}
        box = instance.definition.bounds
        corners = (0..7).map { |index| box.corner(index).transform(world) }
        {
            'instance_id' => instance.persistent_id,
            'id'          => element['id'],
            'type'        => element['product'],
            'name'        => instance.name.to_s.empty? ? instance.definition.name : instance.name,
            'size_mm'     => na_size_of(element['system'], values),
            'origin'      => na_mm(world.origin),
            'along'       => world.xaxis.to_a.map { |value| value.round(4) },
            'bounds'      => { 'min' => na_mm(Geom::Point3d.new(corners.map(&:x).min, corners.map(&:y).min, corners.map(&:z).min)),
                               'max' => na_mm(Geom::Point3d.new(corners.map(&:x).max, corners.map(&:y).max, corners.map(&:z).max)) },
            'path'        => path,
            'copies'      => instance.definition.instances.length
        }
    end
    private_class_method :na_element_row
    # ---------------------------------------------------------------

    # HELPER FUNCTION | The Size an Element Is Set To (mm)
    # ------------------------------------------------------------
    def self.na_size_of(system, values)
        case system
        when 'window_family' then { 'width' => values['width_mm'], 'height' => values['height_mm'] }
        when 'interior_door'
            { 'width' => values['Na__DoorConfig__OpeningWidth_mm'], 'height' => values['Na__DoorConfig__OpeningHeight_mm'],
              'wall_depth' => values['Na__DoorConfig__WallDepth_mm'] }
        else
            effective = Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__LayoutResolver.na_effective(values)
            { 'width' => effective[:width], 'height' => effective[:height], 'depth' => effective[:depth], 'unit_type' => effective[:type] }.compact
        end
    rescue StandardError
        {}
    end
    private_class_method :na_size_of
    # ---------------------------------------------------------------

    # FUNCTION | One Element: Identity, Values, Parts and Solids
    # ------------------------------------------------------------
    # values: only those that differ from a new element of the same product,
    # unless all is true; keys / prefix narrow them.
    def self.na_inspect(params)
        instance, element = na_require_element(params)
        system  = element['system']
        values  = element['root'][NA_CONFIG_BLOCK[system]] || {}
        start   = na_fresh_root(element['product'])[NA_CONFIG_BLOCK[system]] || {}
        keys    = Array(params['keys']).map { |key| na_full_key(system, key) }
        prefix  = params['prefix'].to_s
        shown = values.select do |key, value|
            next keys.include?(key) unless keys.empty?
            next false unless prefix.empty? || key.start_with?(prefix) || key.start_with?(na_full_key(system, prefix))

            params['all'] == true || !start.key?(key) || start[key] != value
        end

        definition = instance.definition
        mods = definition.entities.grep(Sketchup::Group).select { |group| group.name.match?(NA_MOD_NAME) }
        fields = []
        mod_rows = mods.map do |mod|
            parts = mod.entities.grep(Sketchup::Group).map { |group| na_part_row(group) }
            na_each_field(mod.entities) { |field| fields << na_part_row(field).merge('mod' => mod.name) }
            { 'name' => mod.name, 'tag' => mod.layer.name, 'parts' => parts }
        end
        top_parts = definition.entities.grep(Sketchup::Group).reject { |group| group.name.match?(NA_MOD_NAME) }.map { |group| na_part_row(group) }
        not_solid = fields.reject { |row| row['solid'] }
        {
            'id'           => element['id'],
            'type'         => element['product'],
            'system'       => system,
            'name'         => instance.name,
            'definition'   => definition.name,
            'copies'       => definition.instances.length,
            'size_mm'      => na_size_of(system, values),
            'metadata'     => Array(element['root'][na_metadata_key(system)]).first,
            'values'       => shown,
            'value_count'  => values.length,
            'parts'        => top_parts,
            'mods'         => mod_rows,
            'fields'       => { 'count' => fields.length, 'all_solid' => not_solid.empty?, 'rows' => fields },
            'summary'      => "#{element['id']} (#{element['product'].tr('_', ' ')}): #{values.length} stored values, " \
                              "#{shown.length} shown#{params['all'] == true || !keys.empty? ? '' : ' (changed from a new one)'}; " \
                              "#{mods.length} MOD group#{mods.length == 1 ? '' : 's'}, #{top_parts.length} part#{top_parts.length == 1 ? '' : 's'}, " \
                              "#{fields.length} fielded panel#{fields.length == 1 ? '' : 's'} (#{not_solid.length} not solid)."
        }
    end
    private_class_method :na_inspect
    # ---------------------------------------------------------------

    # FUNCTION | Every Opening in a Wall, and What Would Fit It
    # ------------------------------------------------------------
    # The handler resolves the wall and its world transform.
    def self.na_openings(params)
        wall = params['wall_object']
        unless wall.is_a?(Sketchup::Group) || wall.is_a?(Sketchup::ComponentInstance)
            na_refuse('invalid_params', 'openings needs wall_id: the group or component whose faces are the wall.', 'Find it with entity_query or outliner_tree.')
        end

        found = Na__AssemblyStudio__WallOpenings(wall, params['wall_to_world'] || wall.transformation,
                                                  outside: params['outside_vector'] || params['outside_point'],
                                                  model_center: Sketchup.active_model.bounds.center)
        rows = found[:openings].each_with_index.map do |opening, index|
            {
                'index'      => index,
                'kind'       => opening[:kind],
                'width_mm'   => opening[:width].to_mm.round(1),
                'height_mm'  => opening[:height].to_mm.round(1),
                'depth_mm'   => opening[:depth].to_mm.round(1),
                'sill_z'     => opening[:sill_z].to_mm.round(1),
                'head_z'     => opening[:head_z].to_mm.round(1),
                'point_a'    => na_mm(opening[:point_a]),
                'point_b'    => na_mm(opening[:point_b]),
                'point_d'    => na_mm(opening[:point_d]),
                'centre'     => na_mm(opening[:center]),
                'suggests'   => opening[:kind] == 'notch' ? 'a door (single, double, bifold, sliding or interior_door)' : 'a window (casement or sash)'
            }
        end
        {
            'wall'      => wall.name.to_s.empty? ? wall.definition.name : wall.name,
            'thickness_mm' => found[:thickness].to_mm.round(1),
            'outside'   => found[:frame][:outside].to_a.map { |value| value.round(4) },
            'openings'  => rows,
            'summary'   => "#{rows.length} opening#{rows.length == 1 ? '' : 's'} in a #{found[:thickness].to_mm.round}mm wall, left to right seen from outside: " +
                           rows.map { |row| "#{row['index']}: #{row['kind']} #{row['width_mm'].round}x#{row['height_mm'].round} at sill #{row['sill_z'].round}" }.join('; ') + '.'
        }
    end
    private_class_method :na_openings
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Edit Actions - build
# -----------------------------------------------------------------------------

    # FUNCTION | Build Any Element From a Type or a Preset, Into an Opening
    # ------------------------------------------------------------
    def self.na_build(params)
        plan = na_build_plan(params)
        return na_plan_report(plan, 'Would build') if params['dry_run'] == true

        na_ensure_materials
        instance = case plan['system']
                   when 'window_family'
                       Na__AssemblyStudio::Na__WindowSystem::Na__DialogCallbacks.na_pipeline_create(plan['root'], plan['frame'], name: plan['name'].to_s)
                   when 'interior_door'
                       Na__AssemblyStudio::Na__InteriorDoorSystem::Na__DialogRouter.na_pipeline_create_door(plan['root'], plan['frame'])
                   else
                       Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__DialogRouter.na_pipeline_create(plan['root'], plan['transform'], 'Create Cabinet')
                   end
        na_result_for(instance, plan, 'Built')
    rescue Na__AssemblyStudio::Na__McpOperationsError
        raise
    rescue StandardError => error
        na_refuse('operation_failed', "The #{plan ? plan['product'].tr('_', ' ') : 'element'} could not be built: #{error.message}",
                  'Nothing was left behind (the build step was aborted). Check the values with dry_run, or read the Ruby Console.')
    end
    private_class_method :na_build
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Everything a Build Needs, Checked Before Anything Changes
    # ------------------------------------------------------------
    def self.na_build_plan(params)
        na_resolve_opening!(params)
        record = params['preset'] ? na_preset_record(params['preset']) : nil
        if record
            system = na_system_of_family(record['productFamily'])
            product_key = na_product_of_preset(system, record)
            if params['type'] && na_product(params['type'])[0] != product_key
                na_refuse('invalid_params', "#{record['presetCode']} is a #{product_key.tr('_', ' ')} preset, not a #{params['type']}.",
                          "Leave type out to build the preset's product, or pick a #{params['type']} preset (entity_studio list_presets).")
            end
            root = na_fresh_root(product_key)
            block = NA_CONFIG_BLOCK[system]
            root[block] = system == 'cabinet' ? root[block].merge(na_deep_copy(record['configValues'] || {})) : na_over_dialog_defaults(system, record['configValues'])
            na_apply_product_flags!(root[block], product_key) if system == 'window_family'
        else
            unless params['type']
                na_refuse('invalid_params', 'Say what to build: type, or a preset.',
                          "type is one of #{NA_PRODUCTS.keys.join(', ')}; presets are listed by entity_studio list_presets.")
            end
            product_key, = na_product(params['type'])
            system = NA_PRODUCTS[product_key]['system']
            root = na_fresh_root(product_key)
        end

        block  = NA_CONFIG_BLOCK[system]
        values = root[block]
        start  = na_deep_copy(values)
        checked, warnings = na_check_values(system, product_key, values, params['values'])
        values.merge!(checked)

        placement = na_placement(params, system, product_key, values, checked.keys)
        warnings.concat(placement['warnings'])
        fitted, = na_check_values(system, product_key, values, placement['fit']) unless placement['fit'].empty?
        values.merge!(fitted || {})
        warnings.concat(na_dialog_side_effects!(system, start, values, checked.keys))

        errors = na_validation_errors(system, product_key, values)
        unless errors.empty?
            na_refuse('invalid_params', "The dialog would refuse this #{product_key.tr('_', ' ')}: #{errors.join(' | ')}",
                      'Change the sizes or settings named, or check them first with dry_run: true.', { 'errors' => errors })
        end

        values = root[block] = na_json_numbers(values)
        name = params['name'].to_s.strip
        na_stamp_name!(system, root, name) unless name.empty?
        {
            'system' => system, 'product' => product_key, 'root' => root, 'values' => values, 'name' => name,
            'frame' => placement['frame'], 'transform' => placement['transform'], 'placement' => placement['report'],
            'fit' => placement['fit'], 'set' => checked, 'warnings' => warnings, 'preset' => record && record['presetCode']
        }
    end
    private_class_method :na_build_plan
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Where the Element Goes, and the Sizes the Opening Gives
    # ------------------------------------------------------------
    # @return [Hash] { 'frame', 'transform', 'fit' (key => value), 'report', 'warnings' }
    def self.na_placement(params, system, product_key, values, set_keys)
        warnings = []
        opening  = params['opening_points']
        fit      = {}
        report   = {}
        up       = Geom::Vector3d.new(0, 0, 1)

        if system == 'cabinet'
            run = params['run_points']
            if run
                frame = Na__AssemblyStudio::Na__MeasurementTools::Na__RunMeasureTool.na_frame(run[:a], run[:b], run[:side], up)
                na_refuse('invalid_params', 'The run is too short or vertical: point_a and point_b must be apart along the floor.', nil) unless frame
                offset = params['run_offset_mm'].to_f
                origin = frame[:origin].offset(frame[:xaxis], offset.mm)
                transform = Geom::Transformation.axes(origin, frame[:xaxis], frame[:yaxis], frame[:zaxis])
                fit['Na__CabinetConfig__Width_mm'] = frame[:length_mm].round(1) if params['fit'] == true && !set_keys.include?('Na__CabinetConfig__Width_mm')
                width = (fit['Na__CabinetConfig__Width_mm'] || Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__LayoutResolver.na_effective(values)[:width]).to_f
                if offset + width > frame[:length_mm] + 0.5
                    warnings << "This unit runs #{(offset + width - frame[:length_mm]).round}mm past the end of the #{frame[:length_mm].round}mm run."
                end
                report = { 'run_length_mm' => frame[:length_mm].round(1), 'offset_mm' => offset, 'origin' => na_mm(origin),
                           'along' => frame[:xaxis].to_a.map { |v| v.round(4) }, 'next_offset_mm' => (offset + width).round(1) }
                return { 'frame' => nil, 'transform' => transform, 'fit' => fit, 'report' => report, 'warnings' => warnings }
            end
            origin, xaxis = na_position_axes(params)
            yaxis = up * xaxis
            transform = Geom::Transformation.axes(origin, xaxis, yaxis, up)
            report = { 'origin' => na_mm(origin), 'along' => xaxis.to_a.map { |v| v.round(4) } }
            return { 'frame' => nil, 'transform' => transform, 'fit' => fit, 'report' => report, 'warnings' => warnings }
        end

        if opening
            point_a, point_b, point_d = opening.values_at(:a, :b, :d)
            frame_helper = Na__AssemblyStudio::Na__GeometryHelpers::Na__InsertionFrame
            frame = if system == 'interior_door' && point_d
                        frame_helper.na_build_measurement_frame_3pt(point_a, point_b, point_d)
                    else
                        frame_helper.na_build_measurement_frame_2pt(point_a, point_b)
                    end
            along = Geom::Vector3d.new(point_b.x - point_a.x, point_b.y - point_a.y, 0)
            width_mm  = along.length.to_mm
            height_mm = (point_b.z - point_a.z).abs.to_mm
            depth_mm  = point_d ? Geom::Vector3d.new(point_d.x - point_a.x, point_d.y - point_a.y, 0).length.to_mm : nil
            report = { 'point_a' => na_mm(point_a), 'point_b' => na_mm(point_b), 'opening_mm' => { 'width' => width_mm.round(1), 'height' => height_mm.round(1) } }
            report['opening_mm']['depth'] = depth_mm.round(1) if depth_mm
            report['wall_opening'] = params['opening_report'] if params['opening_report']

            if params['fit'] != false
                if system == 'window_family'
                    cill = na_cill_deduction_mm(values)
                    fit['width_mm']  = width_mm.round(1) unless set_keys.include?('width_mm')
                    fit['height_mm'] = (height_mm - cill).round(1) unless set_keys.include?('height_mm')
                    report['cill_deducted_mm'] = cill
                else
                    fit['Na__DoorConfig__OpeningWidth_mm']  = width_mm.round(1) unless set_keys.include?('Na__DoorConfig__OpeningWidth_mm')
                    fit['Na__DoorConfig__OpeningHeight_mm'] = height_mm.round(1) unless set_keys.include?('Na__DoorConfig__OpeningHeight_mm')
                    if depth_mm && !set_keys.include?('Na__DoorConfig__WallDepth_mm')
                        fit['Na__DoorConfig__WallDepth_mm'] = depth_mm.round(1)
                    elsif depth_mm.nil?
                        warnings << 'No depth point: the wall depth stays as set. Pass the wall (wall_id) or point_d to fit it.'
                    end
                end
            end
            unless frame_helper.na_frame_has_orientation?(frame)
                warnings << 'The opening points give no wall direction (A and B are one above the other): placed on the drawing axes.'
            end
            return { 'frame' => frame, 'transform' => nil, 'fit' => fit, 'report' => report, 'warnings' => warnings }
        end

        origin, xaxis = na_position_axes(params)
        yaxis = up * xaxis
        frame = {
            Na__AssemblyStudio::Na__GeometryHelpers::Na__InsertionFrame::NA_FRAME_KEY_ORIGIN => origin,
            Na__AssemblyStudio::Na__GeometryHelpers::Na__InsertionFrame::NA_FRAME_KEY_XAXIS  => xaxis,
            Na__AssemblyStudio::Na__GeometryHelpers::Na__InsertionFrame::NA_FRAME_KEY_YAXIS  => yaxis,
            Na__AssemblyStudio::Na__GeometryHelpers::Na__InsertionFrame::NA_FRAME_KEY_ZAXIS  => up
        }
        report = { 'origin' => na_mm(origin), 'along' => xaxis.to_a.map { |v| v.round(4) } }
        { 'frame' => frame, 'transform' => nil, 'fit' => fit, 'report' => report, 'warnings' => warnings }
    end
    private_class_method :na_placement
    # ---------------------------------------------------------------

    # HELPER FUNCTION | A Wall's Opening by Index -> the Points the Tools Would Pick
    # ------------------------------------------------------------
    # The handler passes 'opening_wall' { wall_object, wall_to_world, index,
    # outside_vector / outside_point }; this turns it into 'opening_points'.
    def self.na_resolve_opening!(params)
        spec = params['opening_wall']
        return unless spec

        wall  = spec['wall_object']
        found = Na__AssemblyStudio__WallOpenings(wall, spec['wall_to_world'], outside: spec['outside_vector'] || spec['outside_point'],
                                                 model_center: Sketchup.active_model.bounds.center)
        index = spec['index'].to_i
        opening = found[:openings][index]
        unless opening
            na_refuse('not_found', "That wall has #{found[:openings].length} opening#{found[:openings].length == 1 ? '' : 's'}" \
                                   "#{found[:openings].empty? ? '' : " (index 0 to #{found[:openings].length - 1})"}; there is no #{index}.",
                      'List them with entity_studio openings (wall_id).')
        end
        params['opening_points'] = { a: opening[:point_a], b: opening[:point_b], d: opening[:point_d] }
        params['opening_report'] = {
            'wall' => wall.name.to_s.empty? ? wall.definition.name : wall.name, 'index' => index, 'kind' => opening[:kind],
            'width_mm' => opening[:width].to_mm.round(1), 'height_mm' => opening[:height].to_mm.round(1),
            'depth_mm' => opening[:depth].to_mm.round(1), 'sill_z' => opening[:sill_z].to_mm.round(1)
        }
    end
    private_class_method :na_resolve_opening!
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Origin and Along-the-Wall Axis From position / direction
    # ------------------------------------------------------------
    def self.na_position_axes(params)
        origin = params['position_point'] || Geom::Point3d.new(0, 0, 0)
        direction = params['direction_vector'] || Geom::Vector3d.new(1, 0, 0)
        flat = Geom::Vector3d.new(direction.x, direction.y, 0)
        na_refuse('invalid_params', 'direction must run along the floor (it is the wall direction, left to right seen from outside).', 'e.g. [1, 0, 0].') if flat.length < 1.0e-6
        [origin, flat.normalize]
    end
    private_class_method :na_position_axes
    # ---------------------------------------------------------------

    # HELPER FUNCTION | What Measure Opening Takes Off the Height for the Cill
    # ------------------------------------------------------------
    def self.na_cill_deduction_mm(values)
        callbacks = Na__AssemblyStudio::Na__WindowSystem::Na__DialogCallbacks
        bottom = callbacks.send(:na_resolve_frame_bottom_thickness_mm, values)
        callbacks.send(:na_resolve_cill_subtraction_mm, values, bottom).to_f
    end
    private_class_method :na_cill_deduction_mm
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Edit Actions - update, rename
# -----------------------------------------------------------------------------

    # FUNCTION | Rebuild a Placed Element With New Values (or a Preset)
    # ------------------------------------------------------------
    # Its product never changes; its placement never moves. Every copy that
    # shares the definition is rebuilt with it, as in the dialog.
    def self.na_update(params)
        instance, element = na_require_element(params)
        system      = element['system']
        product_key = element['product']
        block       = NA_CONFIG_BLOCK[system]
        if params['type'] && na_product(params['type'])[0] != product_key
            na_refuse('invalid_params', "#{element['id']} is a #{product_key.tr('_', ' ')}; an update keeps its product.",
                      'Build a new element of the other type (and delete this one) instead.')
        end

        root   = element['root']
        before = na_over_dialog_defaults(system, root[block] || {})            # <-- What the dialog would show: its defaults fill keys never stored
        values = na_deep_copy(before)
        warnings = []

        if params['preset']
            record = na_preset_record(params['preset'])
            unless na_system_of_family(record['productFamily']) == system && na_product_of_preset(system, record) == product_key
                na_refuse('invalid_params', "#{record['presetCode']} is a #{na_product_of_preset(na_system_of_family(record['productFamily']), record).tr('_', ' ')} preset; #{element['id']} is a #{product_key.tr('_', ' ')}.",
                          'Pick a preset of the same product (entity_studio list_presets).')
            end
            kept = params['keep_size'] == false ? {} : before.slice(*NA_SIZE_KEYS[system])
            values = na_over_dialog_defaults(system, record['configValues'])
            values.merge!(kept)
            na_apply_product_flags!(values, product_key) if system == 'window_family'
        end

        Array(params['reset']).each do |raw_key|
            key = na_full_key(system, raw_key)
            start = na_fresh_root(product_key)[block] || {}
            na_refuse('invalid_params', "reset: #{raw_key} has no starting value#{na_suggest(key, start.keys)}.", nil) unless start.key?(key)
            values[key] = start[key]
        end

        checked, more = na_check_values(system, product_key, values, params['values'])
        warnings.concat(more)
        values.merge!(checked)

        na_resolve_opening!(params)
        if params['opening_points']
            placement = na_placement(params, system, product_key, values, checked.keys)
            fitted, = na_check_values(system, product_key, values, placement['fit']) unless placement['fit'].empty?
            values.merge!(fitted || {})
            warnings << 'Only the size followed the opening: an update never moves an element (build a new one to move it).'
        end
        warnings.concat(na_dialog_side_effects!(system, before, values, checked.keys))

        errors = na_validation_errors(system, product_key, values)
        unless errors.empty?
            na_refuse('invalid_params', "The dialog would refuse these values: #{errors.join(' | ')}", 'Nothing was changed.', { 'errors' => errors })
        end

        changes = (before.keys | values.keys).filter_map do |key|
            next nil if before[key] == values[key]

            { 'key' => key, 'from' => before[key], 'to' => values[key] }
        end
        copies = instance.definition.instances.length
        warnings << "#{copies} copies share this definition: all of them change." if copies > 1

        plan = { 'system' => system, 'product' => product_key, 'values' => values, 'warnings' => warnings,
                 'changes' => changes, 'id' => element['id'] }
        return na_plan_report(plan, 'Would rebuild') if params['dry_run'] == true

        if changes.empty? && params['name'].nil?
            return { 'instance_object' => instance, 'id' => element['id'], 'changes' => [], 'warnings' => warnings,
                     'summary' => "#{element['id']} already has those values: nothing rebuilt." }
        end

        root[block] = values = na_json_numbers(values)
        name = params['name'].nil? ? nil : params['name'].to_s.strip
        na_ensure_materials
        case system
        when 'window_family'
            callbacks = Na__AssemblyStudio::Na__WindowSystem::Na__DialogCallbacks
            callbacks.na_pipeline_update(instance, root, name: name.nil? ? Na__AssemblyStudio::Na__GeometryHelpers::Na__ComponentNameSuffix::NA_KEEP : name)
        when 'interior_door'
            na_stamp_name!(system, root, name) unless name.nil?
            Na__AssemblyStudio::Na__InteriorDoorSystem::Na__DialogRouter.na_pipeline_update_door(instance, root)
        else
            Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__DialogRouter.na_pipeline_update(instance, root)
            Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__DialogRouter.na_pipeline_rename(instance, name) unless name.nil?
        end

        plan['set'] = checked
        result = na_result_for(instance, plan, 'Rebuilt')
        result['changes'] = changes
        result['warnings'] = (result['warnings'] || []) + (na_dialog_open? ? ['If the dialog was showing this element it still shows the old values: select it again to reload.'] : [])
        result['summary'] = "Rebuilt #{element['id']} (#{product_key.tr('_', ' ')}): #{changes.length} value#{changes.length == 1 ? '' : 's'} changed#{copies > 1 ? ", #{copies} copies" : ''}."
        result
    rescue Na__AssemblyStudio::Na__McpOperationsError
        raise
    rescue StandardError => error
        na_refuse('operation_failed', "The rebuild failed: #{error.message}", 'The step was aborted, so the element is as it was. Read the Ruby Console for the cause.')
    end
    private_class_method :na_update
    # ---------------------------------------------------------------

    # FUNCTION | Give an Element a Name Tail (the Coded Head Stays)
    # ------------------------------------------------------------
    def self.na_rename(params)
        instance, element = na_require_element(params)
        name = params['name'].to_s.strip
        system = element['system']
        case system
        when 'window_family'
            model = Sketchup.active_model
            model.start_operation('Rename Component', true)
            begin
                Na__AssemblyStudio::Na__WindowSystem::Na__DialogCallbacks.na_pipeline_apply_name(instance, name)
                model.commit_operation
            rescue StandardError
                model.abort_operation
                raise
            end
        when 'interior_door'
            root = element['root']
            na_stamp_name!(system, root, name)
            Na__AssemblyStudio::Na__InteriorDoorSystem::Na__DialogRouter.na_pipeline_update_door(instance, root)
        else
            Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__DialogRouter.na_pipeline_rename(instance, name)
        end
        {
            'instance_object' => instance,
            'id'              => element['id'],
            'name'            => instance.name,
            'summary'         => "#{element['id']} is now named #{instance.name}."
        }
    rescue Na__AssemblyStudio::Na__McpOperationsError
        raise
    rescue StandardError => error
        na_refuse('operation_failed', "The rename failed: #{error.message}", nil)
    end
    private_class_method :na_rename
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Elements - Helpers
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | The Product a Preset Builds
    # ------------------------------------------------------------
    def self.na_product_of_preset(system, record)
        values = record['configValues'] || {}
        return na_product_of_values(system, values) unless system == 'window_family'

        from_flags = na_product_of_values(system, values)
        return from_flags unless from_flags == 'casement'

        NA_PRODUCTS.find { |_key, row| row['system'] == 'window_family' && row['type'] == record['productType'] }&.first || 'casement'
    end
    private_class_method :na_product_of_preset
    # ---------------------------------------------------------------

    def self.na_system_of_family(family)
        case family.to_s
        when 'InteriorDoor' then 'interior_door'
        when 'Cabinet' then 'cabinet'
        else 'window_family'
        end
    end
    private_class_method :na_system_of_family

    def self.na_metadata_key(system)
        { 'window_family' => 'windowMetadata', 'interior_door' => 'Na__DoorMetadata', 'cabinet' => 'Na__CabinetMetadata' }[system]
    end
    private_class_method :na_metadata_key

    # HELPER FUNCTION | Put a Name Tail Where Each System Keeps It
    # ------------------------------------------------------------
    # Window family: the component name (the pipeline applies it). Interior
    # doors: Na__Door__Description (their name tail). Cabinets:
    # Na__Cabinet__ComponentName.
    def self.na_stamp_name!(system, root, name)
        metadata = Array(root[na_metadata_key(system)]).first
        return unless metadata.is_a?(Hash)

        case system
        when 'window_family' then metadata['WindowComponentName'] = name
        when 'interior_door' then metadata['Na__Door__Description'] = name
        else metadata['Na__Cabinet__ComponentName'] = name
        end
    end
    private_class_method :na_stamp_name!
    # ---------------------------------------------------------------

    # HELPER FUNCTION | What a Dry Run Reports
    # ------------------------------------------------------------
    def self.na_plan_report(plan, verb)
        values = plan['values'] || {}
        {
            'dry_run'   => true,
            'type'      => plan['product'],
            'system'    => plan['system'],
            'preset'    => plan['preset'],
            'size_mm'   => na_size_of(plan['system'], values),
            'set'       => plan['set'],
            'fit'       => plan['fit'],
            'placement' => plan['placement'],
            'changes'   => plan['changes'],
            'warnings'  => plan['warnings'] || [],
            'summary'   => "#{verb} a #{plan['product'].tr('_', ' ')} #{na_size_text(plan['system'], values)}" \
                           "#{plan['changes'] ? " with #{plan['changes'].length} change#{plan['changes'].length == 1 ? '' : 's'}" : ''}: " \
                           'every value passed the dialog\'s checks. Nothing changed (dry run).'
        }.compact
    end
    private_class_method :na_plan_report
    # ---------------------------------------------------------------

    # HELPER FUNCTION | The Result of a Build or Rebuild, With Its Checks
    # ------------------------------------------------------------
    def self.na_result_for(instance, plan, verb)
        unless instance.is_a?(Sketchup::ComponentInstance) && instance.valid?
            na_refuse('operation_failed', "The #{plan['product'].tr('_', ' ')} engine returned nothing.", 'Read the Ruby Console for the Element Assembly Studio error.')
        end

        element = na_element_of(instance)
        values  = element ? (element['root'][NA_CONFIG_BLOCK[element['system']]] || {}) : plan['values']
        fields  = na_field_rows(instance)
        parts   = instance.definition.entities.length
        checks  = { 'entities' => parts, 'fields' => fields.length, 'fields_solid' => fields.all? { |row| row['solid'] } }
        warnings = Array(plan['warnings']).dup
        warnings << 'The element was built empty: check the Ruby Console.' if parts.zero?
        warnings << "#{fields.reject { |row| row['solid'] }.length} fielded panel(s) are not solid." unless checks['fields_solid']
        {
            'instance_object' => instance,
            'id'              => element && element['id'],
            'type'            => plan['product'],
            'definition'      => instance.definition.name,
            'name'            => instance.name,
            'size_mm'         => na_size_of(plan['system'], values),
            'set'             => plan['set'],
            'fit'             => plan['fit'],
            'placement'       => plan['placement'],
            'preset'          => plan['preset'],
            'checks'          => checks,
            'undo_name'       => verb == 'Built' ? (NA_UNDO_NAMES[plan['product']] || 'Create Cabinet') : nil,
            'warnings'        => warnings,
            'summary'         => "#{verb} #{element ? element['id'] : instance.definition.name} (#{plan['product'].tr('_', ' ')}) " \
                                 "#{na_size_text(plan['system'], values)}#{plan['preset'] ? " from #{plan['preset']}" : ''}."
        }.compact
    end
    private_class_method :na_result_for
    # ---------------------------------------------------------------

    def self.na_size_text(system, values)
        size = na_size_of(system, values)
        dims = [size['width'], size['height'], size['depth'] || size['wall_depth']].compact.map { |value| value.is_a?(Numeric) ? value.round : value }
        dims.empty? ? '' : "#{dims.join(' x ')}mm"
    end
    private_class_method :na_size_text

    def self.na_mm(point)
        point.to_a.map { |value| value.to_mm.round(1) }
    end
    private_class_method :na_mm

# endregion -------------------------------------------------------------------

end # module Na__McpOperations
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
