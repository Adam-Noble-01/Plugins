# frozen_string_literal: true

# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - MCP OPERATIONS - ASSEMBLY RUNS
# =============================================================================
#
# FILE       : Na__AssemblyStudio__McpOperations__Runs__.rb
# NAMESPACE  : Na__AssemblyStudio
# MODULE     : Na__McpOperations
# AUTHOR     : Noble Architecture
# CREATED    : 16-Nov-2026 (V2.7.0)
# PURPOSE    : What an agent may do with the Assembly Run Studio through
#              Adam's Na SketchUp MCP plugin (tools assembly_run and
#              assembly_run_edit): read runs and their layouts, build a run
#              along a path, rebuild it with new settings, legs or panel
#              types, make a panel unique, recode it, give a span another
#              type or another product, turn the run inside out, and edit
#              the path.
#
# ENTRY POINTS:
# - Na__McpOperations.Na__AssemblyStudio__McpRunRead(action, params)
#     status, parameters, columns, runs, inspect, layout
# - Na__McpOperations.Na__AssemblyStudio__McpRunEdit(action, params)
#     build, update, set_path, flip_side, make_unique, recode, set_span_type,
#     rename, edit_path, finish_path_edit, discard_path_edit, open_dialog
#
# WHAT IT REUSES (no second copy of any rule):
# - Every build and edit runs Na__AssemblyRunSystem::Na__RunPipelines, the
#   calls the Assembly Run Studio tab makes. One undo step each.
# - Every layout comes from Na__AssemblyRunSystem::Na__LayoutResolver: a
#   dry run shows exactly what a build would place.
# - A panel type's element starts from this seam's own planner
#   (na_build_plan): the product's start, a preset and values, each value
#   checked as a single build's is.
#
# THE AGENT'S WORDS AND THE RUN'S STORED DATA
# - Agents write short, lower-case keys (panel_types, legs, fill, column);
#   the run stores Na__RunConfig__ keys. na_run_config! is the one place the
#   first becomes the second. settings uses the stored short names as they
#   are (Height_mm, FuseFramework, JointColumn ...): parameters lists them.
# - Legs and spans are numbered from 1 for agents (as the layout's keys,
#   L1S2); the run's data and the pipelines count from 0.
#
# PARAMS ARRIVE STRING-KEYED, lengths in millimetres. The MCP handler adds
# 'instance_object' (the run), 'path_points' ([Point3d] world inches) and
# 'side_point' (Point3d).
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require_relative '../55__System__AssemblyRunSystem/Na__AssemblyStudio__AssemblyRun__Init__'

module Na__AssemblyStudio
module Na__McpOperations

# -----------------------------------------------------------------------------
# REGION | Runs - Constants
# -----------------------------------------------------------------------------

    NA_RUN_READ_ACTIONS = %w[status parameters columns runs inspect layout].freeze
    NA_RUN_EDIT_ACTIONS = %w[build update set_path flip_side make_unique recode set_span_type rename
                             edit_path finish_path_edit discard_path_edit open_dialog].freeze

    # What each run setting means (the key is its short stored name).
    NA_RUN_SETTING_NOTES = {
        'Height_mm'         => 'Frames: from the run\'s base to the top of the frames. A panel type\'s element is this tall, less its sill.',
        'FuseFramework'     => 'Frames: true has the run build the frame members as ONE solid: one mullion between two spans, a jamb where a span meets anything else, and the head and bottom rail of every window (windows are then built frameless, as their casements and glass; doors keep their own head and threshold). A fused run always joins its cills.',
        'JoinCills'         => 'Frames: true (the start) builds ONE cill along the run and ONE internal window board, each mitred round every corner, in place of each panel\'s own; posts, blocks and corner posts stand on the cill. A gap, a library column or a panel on a sill height breaks them; a door breaks the board.',
        'CillHeight_mm'     => 'Frames, a joined cill: its height (0 for none). The panels stand on it.',
        'CillProjection_mm' => 'Frames, a joined cill: how far it stands proud of the framework face. It reaches back to the back of the posts (fused) or of the frames.',
        'MullionWidth_mm'   => 'Fused framework: the mullion between two spans.',
        'JambWidth_mm'      => 'Fused framework: the jamb where a span meets a column, a corner or the run\'s end (0 for none).',
        'PostDepth_mm'      => 'Frames: depth of mullions, jambs, infill blocks and corner posts (a frame\'s depth).',
        'PostInset_mm'      => 'Frames: how far those sit behind the framework face (a frame\'s wall inset).',
        'JointColumn'       => 'What stands between two spans that follow each other: None, Infill, Vale260, Vale290 or Gap.',
        'JointWidth_mm'     => 'Width of an Infill or Gap joint, and of a leg item\'s column given no width.',
        'EndColumn'         => 'What stands at each free end of an open run: None, Infill, Vale260, Vale290 or Gap.',
        'EndWidth_mm'       => 'Width of an Infill or Gap end column.',
        'CornerColumn'      => 'What stands at every corner unless corners says otherwise. Frames: Post, Vale260, Vale290, Open. Cabinets: CornerUnit, Blind, Open.',
        'CornerPostSize_mm' => 'Frames: the side of a square corner post (never less than the post depth).',
        'UnitDepth_mm'      => 'Cabinets: carcass depth, for corners and infill blocks.',
        'FrontAllowance_mm' => 'Cabinets: fronts and handles in front of the carcass, cleared by the second leg at a Blind corner.',
        'CornerUnitLeg_mm'  => 'Cabinets: the length of each arm of an L-shaped corner unit, along its wall.',
        'FillerHeight_mm'   => 'Cabinets: how tall an infill block stands.'
    }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

    # FUNCTION | Read-Only Actions (assembly_run)
    # ------------------------------------------------------------
    # @return [Hash] string-keyed result with a 'summary'
    def self.Na__AssemblyStudio__McpRunRead(action, params)
        params = {} unless params.is_a?(Hash)
        na_run_modules
        case action.to_s
        when 'status'     then na_run_status
        when 'parameters' then na_run_parameters(params)
        when 'columns'    then na_run_columns
        when 'runs'       then na_run_list
        when 'inspect'    then na_run_inspect(params)
        when 'layout'     then na_run_layout(params)
        else
            na_refuse('invalid_params', "Unknown assembly_run action '#{action}'.", "Use one of: #{NA_RUN_READ_ACTIONS.join(', ')}.")
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Changing Actions (assembly_run_edit)
    # ------------------------------------------------------------
    # @return [Hash] string-keyed result with a 'summary'
    def self.Na__AssemblyStudio__McpRunEdit(action, params)
        params = {} unless params.is_a?(Hash)
        na_run_modules
        case action.to_s
        when 'build'             then na_run_build(params)
        when 'update'            then na_run_update(params)
        when 'set_path'          then na_run_set_path(params)
        when 'flip_side'         then na_run_flip_side(params)
        when 'make_unique'       then na_run_panel_edit(params, :unique)
        when 'recode'            then na_run_panel_edit(params, :recode)
        when 'set_span_type'     then na_run_panel_edit(params, :set_type)
        when 'rename'            then na_run_rename(params)
        when 'edit_path'         then na_run_edit_path(params)
        when 'finish_path_edit'  then na_run_close_path_edit(:finish)
        when 'discard_path_edit' then na_run_close_path_edit(:discard)
        when 'open_dialog'       then na_run_open_dialog(params)
        else
            na_refuse('invalid_params', "Unknown assembly_run_edit action '#{action}'.", "Use one of: #{NA_RUN_EDIT_ACTIONS.join(', ')}.")
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Runs - The Run System's Modules
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Load the Run System and the Element Systems It Builds
    # ------------------------------------------------------------
    def self.na_run_modules
        Na__AssemblyStudio::Na__AssemblyRunSystem.na_require_modules
        na_require_modules_for('window_family')
        na_require_modules_for('cabinet')
    end
    private_class_method :na_run_modules
    # ---------------------------------------------------------------

    def self.na_run_system;    Na__AssemblyStudio::Na__AssemblyRunSystem;                      end
    def self.na_run_defaults;  Na__AssemblyStudio::Na__AssemblyRunSystem::Na__Defaults;        end
    def self.na_run_pipelines; Na__AssemblyStudio::Na__AssemblyRunSystem::Na__RunPipelines;    end
    def self.na_run_resolver;  Na__AssemblyStudio::Na__AssemblyRunSystem::Na__LayoutResolver;  end
    def self.na_run_serializer; Na__AssemblyStudio::Na__AssemblyRunSystem::Na__DataSerializer; end
    private_class_method :na_run_system, :na_run_defaults, :na_run_pipelines, :na_run_resolver, :na_run_serializer

    # HELPER FUNCTION | Refuse a Change to a Value a Run Sets on Its Panel
    # ------------------------------------------------------------
    # Called by the element update (entity_studio_edit update). A panel of
    # a run takes its width and height (and, fused, its side frames) from
    # the run: changed on the element they would overlap the neighbours,
    # so the change is refused before anything is built, naming the fix.
    # Everything else on the panel may change, and changes every span of
    # its type. Costs one attribute read for an element that is no panel.
    def self.na_run_refuse_owned!(instance, element, changes)
        return unless instance.get_attribute('Na__AssemblyRunMemberInfo', 'RunID')
        na_run_modules
        sync  = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__MemberSync
        state = sync.na_state_of(instance)
        return unless state

        hit = changes.map { |change| change['key'] } & sync.na_owned_keys(state[:system], state[:fuse], state[:type])
        return if hit.empty?
        na_refuse('invalid_params',
                  "#{element['id']} is panel type #{state[:type][:code]} of run #{state[:run_id]}, which sets #{hit.join(', ')}.",
                  'Change the run instead: assembly_run_edit update (panel_types width / height / sill, settings, or a new path). ' \
                  'Every other value of the panel can be set here, and changes every span of its type.')
    end
    private_class_method :na_run_refuse_owned!

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Runs - Read Actions
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | What the Run Studio Offers, and What Is in the Model
    # ------------------------------------------------------------
    def self.na_run_status
        defaults = na_run_defaults
        runs     = na_run_serializer.na_all_runs
        editing  = na_run_system::Na__PathEditor.na_editing_run_id
        {
            'version'       => na_app_version,
            'modes'         => defaults::NA_MODES,
            'products'      => defaults::NA_MODE_PRODUCTS,
            'column_kinds'  => defaults::NA_COLUMN_KINDS_BY_MODE,
            'corner_kinds'  => defaults::NA_CORNER_KINDS_BY_MODE,
            'infill_modes'  => defaults::NA_INFILL_MODES,
            'library_columns' => na_run_system::Na__ColumnLibrary.na_list,
            'runs_in_model' => runs.length,
            'path_edit_open' => editing,
            'dialog_open'   => na_dialog_open?,
            'summary'       => "Assembly Run Studio (Element Assembly Studio Pro #{na_app_version}): modes #{defaults::NA_MODES.join(' and ')}; " \
                               "#{runs.length} run#{runs.length == 1 ? '' : 's'} in this model#{editing ? "; #{editing}'s path is open for editing" : ''}. " \
                               'A run is one master component: spans (a window, door set or cabinet each, by panel type) and columns set out along a path.'
        }
    end
    private_class_method :na_run_status
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Every Run Setting: Meaning, Limits, Start per Mode
    # ------------------------------------------------------------
    def self.na_run_parameters(params)
        defaults = na_run_defaults
        query    = params['query'].to_s.strip.downcase
        starts   = defaults::NA_MODES.each_with_object({}) { |mode, all| all[mode] = defaults.na_default_config(mode)[defaults::NA_KEY_CONFIGURATION] }
        rows = NA_RUN_SETTING_NOTES.filter_map do |key, note|
            next nil unless query.empty? || "#{key} #{note}".downcase.include?(query)
            low, high = defaults::NA_LIMITS[key]
            { 'key' => key, 'meaning' => note, 'min' => low, 'max' => high,
              'start' => starts.transform_values { |config| config[defaults.na_key(key)] } }.compact
        end
        {
            'settings'    => rows,
            'panel_type'  => 'code (A, B2 ...), product, preset (a preset code), values (the product\'s own settings: entity_studio parameters), ' \
                             'width (mm; leave out to share the leg), height (Frames; leave out for the run\'s height less the sill), sill (mm above the run\'s base). ' \
                             'Another product on a type already built builds every span of it again from that product\'s start.',
            'leg'         => 'items: [{span: "A"}, {column: "Infill" | "Vale260" | "Vale290" | "Gap", width}] in order along the leg; ' \
                             'or fill: {type, count} (Frames) / {type, infill: End | Start | Both | Equal, standard_width, min_infill} (Cabinets).',
            'summary'     => "#{rows.length} run setting#{rows.length == 1 ? '' : 's'}. A panel type\'s own settings are its product\'s: read them with entity_studio parameters."
        }
    end
    private_class_method :na_run_parameters
    # ---------------------------------------------------------------

    # HELPER FUNCTION | The Library Columns a Run Can Stand
    # ------------------------------------------------------------
    def self.na_run_columns
        rows = na_run_system::Na__ColumnLibrary.na_list
        missing = rows.reject { |row| row['available'] }
        {
            'columns'  => rows,
            'folder'   => na_run_system::Na__ColumnLibrary.na_folder,
            'warnings' => missing.empty? ? [] : ["#{missing.map { |row| row['kind'] }.join(', ')}: the column file is missing from the plugin's asset folder."],
            'summary'  => rows.map { |row| "#{row['kind']}: #{row['width_mm'].round} inline, #{row['corner_leg_mm'].round} each way at a corner" }.join('; ') +
                          '. Every one is stretched from 2000 to the run\'s height.'
        }
    end
    private_class_method :na_run_columns
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Every Run in the Model
    # ------------------------------------------------------------
    def self.na_run_list
        rows = na_run_serializer.na_all_runs.map do |instance|
            loaded = na_run_pipelines.na_pipeline_load(instance)
            layout = na_run_pipelines.na_layout(loaded[:root])
            {
                'instance_id' => instance.persistent_id,
                'id'          => loaded[:id],
                'name'        => instance.name,
                'mode'        => layout[:mode],
                'legs'        => layout[:legs].length,
                'spans'       => layout[:span_count],
                'panel_types' => layout[:types].values.select { |type| type[:count].to_i > 0 }.map { |type| "#{type[:code]} x#{type[:count]}" },
                'length_mm'   => layout[:total_length].round(1),
                'copies'      => instance.definition.instances.length,
                'origin'      => na_mm(na_run_origin(instance))
            }
        end
        {
            'runs'    => rows,
            'summary' => rows.empty? ? 'No assembly runs in this model.' :
                         "#{rows.length} run#{rows.length == 1 ? '' : 's'}: " + rows.map { |row| "#{row['id']} (#{row['mode']}, #{row['spans']} spans)" }.join(', ') + '.'
        }
    end
    private_class_method :na_run_list
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Where a Run Stands in Its Parent, Open or Closed
    # ------------------------------------------------------------
    # A component open for editing reports an identity transformation;
    # its real placement is then the model's edit transform.
    def self.na_run_origin(instance)
        model = Sketchup.active_model
        return model.edit_transform.origin if Array(model.active_path).last == instance
        instance.transformation.origin
    end
    private_class_method :na_run_origin
    # ---------------------------------------------------------------

    # HELPER FUNCTION | One Run: Its Stored Data, Layout and Spans
    # ------------------------------------------------------------
    def self.na_run_inspect(params)
        instance, loaded = na_require_run(params)
        layout = na_run_pipelines.na_layout(loaded[:root])
        na_run_result(instance, loaded[:id], loaded[:root], layout, nil).merge(
            'configuration' => na_run_stored_config(loaded[:root]),
            'layout'        => na_run_resolver.na_report(layout),
            'summary'       => "#{loaded[:id]} #{instance.name}: #{layout[:mode]}, #{layout[:legs].length} leg#{layout[:legs].length == 1 ? '' : 's'}, " \
                               "#{layout[:span_count]} spans of #{layout[:types].values.count { |type| type[:count].to_i > 0 }} panel types."
        )
    end
    private_class_method :na_run_inspect
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Resolve a Run Without Building It
    # ------------------------------------------------------------
    # The same inputs as build (the path may be given in the run's own plan
    # as path_local when no model points are in hand).
    def self.na_run_layout(params)
        root = na_run_defaults.na_default_config(na_run_mode(params, nil))
        na_run_config!(root, params)
        na_run_apply_path!(root, params)
        layout = na_run_pipelines.na_layout(root)
        {
            'ok'       => layout[:errors].empty?,
            'layout'   => na_run_resolver.na_report(layout),
            'warnings' => layout[:warnings],
            'summary'  => na_run_layout_summary(layout)
        }
    end
    private_class_method :na_run_layout
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Runs - Edit Actions
# -----------------------------------------------------------------------------

    # FUNCTION | Build a New Run Along a Path
    # ------------------------------------------------------------
    def self.na_run_build(params)
        root  = na_run_defaults.na_default_config(na_run_mode(params, nil))
        na_run_config!(root, params)
        frame = na_run_apply_path!(root, params)
        layout = na_run_pipelines.na_layout(root)
        na_run_refuse_layout(layout) unless layout[:errors].empty?
        if params['dry_run'] == true
            return { 'dry_run' => true, 'layout' => na_run_resolver.na_report(layout), 'warnings' => layout[:warnings],
                     'summary' => "Would build: #{na_run_layout_summary(layout)}" }
        end

        transform = frame ? frame[:transform] : Sketchup.active_model.axes.transformation
        report = na_run_guard('built') { na_run_pipelines.na_pipeline_create(root, transform, name: params['name'].to_s.strip) }
        na_run_result(report[:instance], report[:run_id], report[:root], report[:layout], report, 'Create Assembly Run').merge(
            'summary' => "Built #{report[:run_id]} #{report[:instance].name}: #{na_run_layout_summary(report[:layout])}" \
                         "#{frame && frame[:reversed] ? ' The path was turned round so the side given is on its right.' : ''}"
        )
    end
    private_class_method :na_run_build
    # ---------------------------------------------------------------

    # FUNCTION | Rebuild a Run With Changed Settings, Legs or Panel Types
    # ------------------------------------------------------------
    # What the call leaves out stays as the run has it.
    def self.na_run_update(params)
        instance, loaded = na_require_run(params)
        root = na_deep_copy(loaded[:root])
        na_run_refuse_mode_change(params, root)
        na_run_config!(root, params)
        na_run_apply_path!(root, params, instance) if params['path_points'] || params['path_local']
        layout = na_run_pipelines.na_layout(root)
        na_run_refuse_layout(layout) unless layout[:errors].empty?
        if params['dry_run'] == true
            return { 'dry_run' => true, 'id' => loaded[:id], 'layout' => na_run_resolver.na_report(layout), 'warnings' => layout[:warnings],
                     'summary' => "Would rebuild #{loaded[:id]}: #{na_run_layout_summary(layout)}" }
        end

        name   = params.key?('name') ? params['name'].to_s.strip : Na__AssemblyStudio::Na__GeometryHelpers::Na__ComponentNameSuffix::NA_KEEP
        report = na_run_guard('rebuilt') { na_run_pipelines.na_pipeline_update(instance, root, name: name) }
        na_run_result(instance, loaded[:id], report[:root], report[:layout], report, 'Update Assembly Run').merge(
            'summary' => "Rebuilt #{loaded[:id]}: #{na_run_layout_summary(report[:layout])}"
        )
    end
    private_class_method :na_run_update
    # ---------------------------------------------------------------

    # FUNCTION | Give a Run a New Path
    # ------------------------------------------------------------
    # path: model points (the run keeps its placement; the points are read
    # in its own plan). path_local: the run's own plan, mm.
    def self.na_run_set_path(params)
        instance, loaded = na_require_run(params)
        root = na_deep_copy(loaded[:root])
        unless params['path_points'] || params['path_local']
            na_refuse('invalid_params', 'set_path needs path (model points) or path_local (the run\'s own plan, mm).', 'To edit it by hand in SketchUp instead, use edit_path.')
        end
        na_run_apply_path!(root, params, instance)
        layout = na_run_pipelines.na_layout(root)
        na_run_refuse_layout(layout) unless layout[:errors].empty?
        report = na_run_guard('rebuilt') { na_run_pipelines.na_pipeline_update(instance, root, operation_name: 'Edit Run Path') }
        na_run_result(instance, loaded[:id], report[:root], report[:layout], report, 'Edit Run Path').merge(
            'summary' => "#{loaded[:id]} rebuilt along its new path: #{na_run_layout_summary(report[:layout])}"
        )
    end
    private_class_method :na_run_set_path
    # ---------------------------------------------------------------

    # FUNCTION | Turn a Run Inside Out (V2.7.2)
    # ------------------------------------------------------------
    # The elements are seen from the right of the path. A run built facing
    # the wrong way is put right by storing its path the other way round,
    # where it lies: the run keeps its placement, every element faces the
    # other way and stands on the other side of the line, and the legs are
    # numbered from the other end.
    def self.na_run_flip_side(params)
        instance, loaded = na_require_run(params)
        if na_run_system::Na__PathEditor.na_editing_run_id == loaded[:id]
            na_refuse('context_error', "#{loaded[:id]}'s path is open for editing as a red line.", 'finish_path_edit or discard_path_edit first, then flip_side.')
        end
        if params['dry_run'] == true
            root = na_deep_copy(loaded[:root])
            na_run_path_guard { na_run_system::Na__RunEdits.na_flip_side!(root[na_run_defaults::NA_KEY_CONFIGURATION]) }
            layout = na_run_pipelines.na_layout(root)
            na_run_refuse_layout(layout) unless layout[:errors].empty?
            return { 'dry_run' => true, 'id' => loaded[:id], 'layout' => na_run_resolver.na_report(layout), 'warnings' => layout[:warnings],
                     'summary' => "Would turn #{loaded[:id]} inside out: #{na_run_layout_summary(layout)}" }
        end

        report = na_run_guard('rebuilt') { na_run_pipelines.na_pipeline_flip_side(instance) }
        na_run_result(instance, loaded[:id], report[:root], report[:layout], report, 'Flip Run Inside Out').merge(
            'side_flipped' => report[:edit],
            'summary'      => "#{loaded[:id]} is turned inside out: its elements face the other way and stand on the other side of its path. " \
                              "The path is stored the other way round, so the legs are numbered from the other end: #{na_run_layout_summary(report[:layout])}"
        )
    end
    private_class_method :na_run_flip_side
    # ---------------------------------------------------------------

    # FUNCTION | Make a Panel Unique, Recode a Type, or Change a Span's Type or Product
    # ------------------------------------------------------------
    def self.na_run_panel_edit(params, edit)
        instance, loaded = na_require_run(params)
        pipelines = na_run_pipelines
        report, undo, said =
            case edit
            when :unique
                leg, span = na_run_span_of(params)
                done = na_run_guard('changed') { pipelines.na_pipeline_make_unique(instance, leg, span, params['code']) }
                [done, 'Make Panel Unique', "Leg #{leg + 1} span #{span + 1} is now panel type #{done[:edit]}, on its own (a copy of the type it was)."]
            when :recode
                if params['from'].to_s.strip.empty? || params['to'].to_s.strip.empty?
                    na_refuse('invalid_params', 'recode needs from (the code it has) and to (the code to give it).', 'e.g. from: "A", to: "W1".')
                end
                done = na_run_guard('changed') { pipelines.na_pipeline_recode(instance, params['from'], params['to']) }
                [done, 'Recode Panel Type', "Panel type #{params['from'].to_s.upcase} is now #{done[:edit]}."]
            else
                leg, span = na_run_span_of(params)
                product   = params['product'].to_s.strip.downcase
                if !product.empty?
                    # Another product (V2.7.2): code, when given, names the new type.
                    done  = na_run_guard('changed') { pipelines.na_pipeline_set_span_product(instance, leg, span, product, params['code']) }
                    label = na_run_system::Na__RunEdits.na_product_label(product)
                    [done, "Change Panel to #{label}",
                     done[:edit][:made] ? "Leg #{leg + 1} span #{span + 1} is now panel type #{done[:edit][:code]}, #{label}: a new type, built from that product's starting values." :
                                          "Panel type #{done[:edit][:code]} is now #{label} (leg #{leg + 1} span #{span + 1} was its only span), built from that product's starting values."]
                else
                    if params['code'].to_s.strip.empty?
                        na_refuse('invalid_params', 'set_span_type needs code (a panel type already on the run) or product (the span becomes that product).',
                                  'List the types with assembly_run inspect and the products with assembly_run status.')
                    end
                    done = na_run_guard('changed') { pipelines.na_pipeline_set_span_type(instance, leg, span, params['code']) }
                    [done, 'Change Panel Type', "Leg #{leg + 1} span #{span + 1} is now panel type #{params['code'].to_s.upcase}."]
                end
            end
        edit_made = report[:edit].is_a?(Hash) ? report[:edit].transform_keys(&:to_s) : report[:edit]
        na_run_result(instance, loaded[:id], report[:root], report[:layout], report, undo).merge('edit' => edit_made, 'summary' => said)
    end
    private_class_method :na_run_panel_edit
    # ---------------------------------------------------------------

    # FUNCTION | Give a Run a Name Tail
    # ------------------------------------------------------------
    def self.na_run_rename(params)
        instance, loaded = na_require_run(params)
        full = na_run_guard('renamed') { na_run_pipelines.na_pipeline_rename(instance, params['name'].to_s.strip) }
        { 'instance_object' => instance, 'id' => loaded[:id], 'name' => full, 'undo_name' => 'Rename Assembly Run', 'summary' => "#{loaded[:id]} is now named #{full}." }
    end
    private_class_method :na_run_rename
    # ---------------------------------------------------------------

    # FUNCTION | Open a Run's Path as a Red Line for Adam to Edit
    # ------------------------------------------------------------
    def self.na_run_edit_path(params)
        instance, loaded = na_require_run(params)
        opened = begin
                     na_run_system::Na__PathEditor.na_open(instance)
                 rescue StandardError => error
                     na_refuse('context_error', error.message, 'Close open groups with context_set (or open the one holding the run), then edit_path again. An agent changing a path itself should use set_path.')
                 end
        {
            'instance_object' => instance, 'id' => loaded[:id], 'path_edit_open' => true,
            'path_local' => opened[:points], 'closed' => opened[:closed],
            'summary' => "#{loaded[:id]}'s path is drawn as a red line inside it and is open for editing. It rebuilds when the line's group is left " \
                         '(or on finish_path_edit); discard_path_edit throws the line away.'
        }
    end
    private_class_method :na_run_edit_path
    # ---------------------------------------------------------------

    # FUNCTION | Finish or Discard the Open Path Edit
    # ------------------------------------------------------------
    def self.na_run_close_path_edit(how)
        editor = na_run_system::Na__PathEditor
        run_id = editor.na_editing_run_id
        na_refuse('context_error', 'No run\'s path is open for editing.', 'Open one with assembly_run_edit edit_path.') unless run_id
        result = how == :finish ? editor.na_finish : editor.na_discard
        na_refuse('operation_failed', result[:message], nil) if result[:status] == :failed
        {
            'id' => run_id, 'status' => result[:status].to_s, 'path_edit_open' => !editor.na_editing_run_id.nil?,
            'instance_object' => result[:report] ? result[:report][:instance] : nil,
            'summary' => result[:message]
        }.compact
    end
    private_class_method :na_run_close_path_edit
    # ---------------------------------------------------------------

    # FUNCTION | Open the Dialog on the Assembly Run Studio Tab (Showing a Run)
    # ------------------------------------------------------------
    def self.na_run_open_dialog(params)
        was_open = na_dialog_open?
        Na__AssemblyStudio.na_init unless was_open
        shown = nil
        if params['instance_object'] || !params['run_id'].to_s.strip.empty?                    # <-- run_id as well (V2.7.3: it was ignored and the tab showed no run)
            instance, loaded = na_require_run(params)
            selection = Sketchup.active_model.selection
            selection.clear
            selection.add(instance)
            coordinator = Na__AssemblyStudio::Na__AppCore::Na__SelectionCoordinator
            if was_open
                coordinator.na_dispatch_selection(selection)
            else
                UI.start_timer(2.0, false) { coordinator.na_dispatch_selection(Sketchup.active_model.selection) }
            end
            shown = loaded[:id]
        else
            manager = Na__AssemblyStudio::Na__AppCore::Na__DialogManager
            was_open ? manager.na_request_tab_switch('runs') : UI.start_timer(2.0, false) { manager.na_request_tab_switch('runs') }
        end
        {
            'dialog_open' => na_dialog_open?, 'showing' => shown,
            'summary' => "Element Assembly Studio dialog open on Assembly Run Studio#{shown ? ", showing #{shown}" : ''}." \
                         "#{was_open ? '' : ' Its page loads a moment after this call returns.'}"
        }
    end
    private_class_method :na_run_open_dialog
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Runs - The Agent's Words Into the Run's Stored Data
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | The Mode a Call Names (or the Run's, or Frames)
    # ------------------------------------------------------------
    def self.na_run_mode(params, fallback)
        defaults = na_run_defaults
        given    = params['mode'].to_s.strip
        return fallback || defaults::NA_MODE_FRAMES if given.empty?
        mode = defaults::NA_MODES.find { |name| name.casecmp?(given) }
        return mode if mode
        na_refuse('invalid_params', "mode is '#{given}'; it must be #{defaults::NA_MODES.join(' or ')}.", 'Frames: windows and exterior doors. Cabinets: fitted units.')
    end
    private_class_method :na_run_mode
    # ---------------------------------------------------------------

    # HELPER FUNCTION | An Update May Not Turn Frames Into Cabinets
    # ------------------------------------------------------------
    def self.na_run_refuse_mode_change(params, root)
        defaults = na_run_defaults
        current  = root[defaults::NA_KEY_CONFIGURATION][defaults.na_key('Mode')].to_s
        return if params['mode'].to_s.strip.empty? || na_run_mode(params, current) == current
        na_refuse('invalid_params', "This run is a #{current} run; an update keeps its mode.", 'Build a new run in the other mode instead.')
    end
    private_class_method :na_run_refuse_mode_change
    # ---------------------------------------------------------------

    # FUNCTION | Write a Call's settings, panel_types, legs and corners Into a Root
    # ------------------------------------------------------------
    # Everything given is merged onto what the root holds; unknown names
    # are refused together, with the names that would do.
    def self.na_run_config!(root, params)
        defaults = na_run_defaults
        config   = (root[defaults::NA_KEY_CONFIGURATION] ||= {})
        problems = []

        (params['settings'].is_a?(Hash) ? params['settings'] : {}).each do |key, value|
            short = key.to_s.sub(/\A#{Regexp.escape(defaults::NA_CONFIG_KEY_PREFIX)}/, '')
            unless NA_RUN_SETTING_NOTES.key?(short)
                problems << "settings.#{key}: not a run setting. They are #{NA_RUN_SETTING_NOTES.keys.join(', ')}."
                next
            end
            config[defaults.na_key(short)] = value
        end

        na_run_types!(config, params['panel_types'], problems) if params.key?('panel_types')
        Array(params['remove_types']).each do |code|
            rows = config[defaults.na_key('PanelTypes')] || []
            rows.reject! { |row| row['Code'].to_s.casecmp?(code.to_s.strip) } || (problems << "remove_types: there is no panel type '#{code}'.")
        end
        na_run_legs!(config, params['legs'], problems) if params.key?('legs')
        if params.key?('corners')
            config[defaults.na_key('Corners')] = Array(params['corners']).map { |kind| kind.to_s.strip.empty? ? {} : { 'Column' => kind.to_s.strip } }
        end
        return config if problems.empty?

        na_refuse('invalid_params', "The run's description has #{problems.length} problem#{problems.length == 1 ? '' : 's'}: #{problems.join(' | ')}",
                  'assembly_run parameters lists every setting, panel type field and leg form.', { 'problems' => problems })
    end
    private_class_method :na_run_config!
    # ---------------------------------------------------------------

    # SUB FUNCTION | panel_types: Add New Codes, Change the Ones Named
    # ------------------------------------------------------------
    def self.na_run_types!(config, given, problems)
        defaults = na_run_defaults
        rows = (config[defaults.na_key('PanelTypes')] ||= [])
        Array(given).each_with_index do |type, index|
            unless type.is_a?(Hash) && !type['code'].to_s.strip.empty?
                problems << "panel_types[#{index}]: needs a code (A, B, C ...)."
                next
            end
            unknown = type.keys - %w[code product preset values width height sill label]
            problems << "panel_types[#{index}] (#{type['code']}): unknown field#{unknown.length == 1 ? '' : 's'} #{unknown.join(', ')}. Use code, product, preset, values, width, height, sill, label." unless unknown.empty?
            code = type['code'].to_s.strip.upcase
            row  = rows.find { |item| item['Code'].to_s.strip.upcase == code }
            unless row
                if type['product'].to_s.strip.empty? && type['preset'].to_s.strip.empty?
                    problems << "panel_types[#{index}] (#{code}): a new panel type needs a product (or a preset)."
                    next
                end
                rows << (row = { 'Code' => code })
            end
            # Another product (V2.7.2): the type is built again from that
            # product's start (with any preset and values given here), by the
            # one rule the tab uses. Without one, a built type's settings stay
            # its element's.
            changing = type.key?('product') && !row['Product'].to_s.empty? && type['product'].to_s.strip.downcase != row['Product'].to_s
            if row['ElementId'] && !changing && (type.key?('preset') || type.key?('values'))
                problems << "panel_types[#{index}] (#{code}): this type is already built (#{row['ElementId']}). Its settings are its element's: change them with " \
                            "entity_studio_edit update on one of its spans (every span of the type follows). Here its width, height, sill and label change, " \
                            "or its product (it is then built again from that product's start, with any preset and values given)."
                next
            end
            if changing
                begin
                    na_run_system::Na__RunEdits.na_set_type_product!(config, code, type['product'])
                rescue ArgumentError => error
                    problems << "panel_types[#{index}] (#{code}): #{error.message}"
                    next
                end
            elsif type.key?('product') || type.key?('preset')
                row['Product'] = na_run_product(type, problems, index)
            end
            row['PresetCode']    = type['preset'].to_s.strip if type.key?('preset')
            row['Values']        = type['values'] if type['values'].is_a?(Hash)
            row['Width_mm']      = type['width'] if type.key?('width')
            row['Height_mm']     = type['height'] if type.key?('height')
            row['SillHeight_mm'] = type['sill'] if type.key?('sill')
            row['Label']         = type['label'].to_s if type.key?('label')
        end
    end
    private_class_method :na_run_types!
    # ---------------------------------------------------------------

    # HELPER FUNCTION | A Panel Type's Product (Named, or Its Preset's)
    # ------------------------------------------------------------
    def self.na_run_product(type, problems, index)
        named = type['product'].to_s.strip.downcase
        return named unless named.empty?
        record = na_preset_record(type['preset'])
        na_product_of_preset(na_system_of_family(record['productFamily']), record)
    rescue Na__AssemblyStudio::Na__McpOperationsError => error
        problems << "panel_types[#{index}]: #{error.message}"
        ''
    end
    private_class_method :na_run_product
    # ---------------------------------------------------------------

    # SUB FUNCTION | legs: One Entry per Leg (Nil Keeps the Leg as It Is)
    # ------------------------------------------------------------
    def self.na_run_legs!(config, given, problems)
        defaults = na_run_defaults
        rows = (config[defaults.na_key('Legs')] ||= [])
        Array(given).each_with_index do |leg, index|
            next if leg.nil?
            unless leg.is_a?(Hash) && (leg['items'].is_a?(Array) || leg['fill'].is_a?(Hash))
                problems << "legs[#{index}]: needs items (a list) or fill (a rule); null keeps the leg as it is."
                next
            end
            if leg['items'].is_a?(Array)
                rows[index] = { 'Items' => leg['items'].each_with_index.filter_map { |item, place| na_run_item(item, index, place, problems) } }
            else
                fill = leg['fill']
                rows[index] = { 'Fill' => {
                    'PanelType' => fill['type'].to_s.strip.upcase, 'Count' => fill['count'], 'Infill' => fill['infill'],
                    'StandardWidth_mm' => fill['standard_width'], 'MinInfillWidth_mm' => fill['min_infill']
                }.compact }
                problems << "legs[#{index}].fill: needs type (a panel type code)." if fill['type'].to_s.strip.empty?
            end
        end
        rows.map! { |row| row.is_a?(Hash) ? row : {} }
    end
    private_class_method :na_run_legs!
    # ---------------------------------------------------------------

    # HELPER FUNCTION | One Leg Item: {span: "A"} | {column: "Infill", width} | {gap: 600}
    # ------------------------------------------------------------
    def self.na_run_item(item, leg_index, place, problems)
        defaults = na_run_defaults
        if item.is_a?(Hash) && !item['span'].to_s.strip.empty?
            { 'Kind' => defaults::NA_ITEM_SPAN, 'PanelType' => item['span'].to_s.strip.upcase }
        elsif item.is_a?(Hash) && item.key?('gap')
            { 'Kind' => defaults::NA_ITEM_COLUMN, 'Column' => defaults::NA_COLUMN_GAP, 'Width_mm' => item['gap'] }
        elsif item.is_a?(Hash) && !item['column'].to_s.strip.empty?
            kind = defaults::NA_COLUMN_KINDS.find { |name| name.casecmp?(item['column'].to_s.strip) } || item['column'].to_s.strip
            { 'Kind' => defaults::NA_ITEM_COLUMN, 'Column' => kind, 'Width_mm' => item['width'] }.compact
        else
            problems << "legs[#{leg_index}].items[#{place}]: write {span: \"A\"}, {column: \"Infill\" | \"Vale260\" | \"Vale290\" | \"Gap\", width} or {gap: 600}."
            nil
        end
    end
    private_class_method :na_run_item
    # ---------------------------------------------------------------

    # FUNCTION | A Call's Path Into the Root (and the Run's Placement)
    # ------------------------------------------------------------
    # path (model points) for a new run gives its placement too; for a run
    # already placed the points are read in its own plan. path_local is the
    # run's own plan as it is.
    # @return [Hash, nil] the world path frame of a new run
    def self.na_run_apply_path!(root, params, instance = nil)
        defaults = na_run_defaults
        config   = root[defaults::NA_KEY_CONFIGURATION]
        closed   = params.key?('closed') ? params['closed'] == true : config[defaults.na_key('PathClosed')] == true
        edits    = na_run_system::Na__RunEdits

        if params['path_points']
            points = params['path_points']
            na_refuse('invalid_params', 'path needs at least two points.', 'e.g. [[0, 0, 0], [3600, 0, 0]].') if points.length < 2
            if instance
                inverse = instance.transformation.inverse
                local   = points.map { |point| moved = point.transform(inverse); [moved.x.to_mm, moved.y.to_mm] }
                na_run_path_guard { edits.na_set_path!(config, local, closed) }
                return nil
            end
            frame = na_run_path_guard { na_run_pipelines.na_world_path_frame(points, params['side_point'], closed) }
            na_run_path_guard { edits.na_set_path!(config, frame[:points], closed) }
            return frame
        end
        if params['path_local']
            na_run_path_guard { edits.na_set_path!(config, params['path_local'], closed) }
        elsif params.key?('closed')
            config[defaults.na_key('PathClosed')] = closed
        end
        nil
    end
    private_class_method :na_run_apply_path!
    # ---------------------------------------------------------------

    # HELPER FUNCTION | A Path Problem as a Refusal
    # ------------------------------------------------------------
    def self.na_run_path_guard
        yield
    rescue ArgumentError => error
        na_refuse('invalid_params', error.message, 'Give the path\'s corners in order, at floor level; side is any point on the side the elements are seen from.')
    end
    private_class_method :na_run_path_guard
    # ---------------------------------------------------------------

    # HELPER FUNCTION | leg and span (Numbered From 1), or a Key Like L1S2
    # ------------------------------------------------------------
    # @return [Array(Integer, Integer)] zero-based
    def self.na_run_span_of(params)
        key = params['span_key'].to_s.strip.upcase.match(/\AL(\d+)S(\d+)\z/)
        leg, span = key ? [key[1].to_i, key[2].to_i] : [params['leg'].to_i, params['span'].to_i]
        return [leg - 1, span - 1] if leg >= 1 && span >= 1
        na_refuse('invalid_params', 'Say which span: leg and span (both numbered from 1), or span_key such as "L1S2".', 'assembly_run inspect lists every span with its key.')
    end
    private_class_method :na_run_span_of
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Runs - Results and Refusals
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | The Run the Handler Resolved (or the One Named), or a Refusal
    # ------------------------------------------------------------
    # @return [Array] [instance, { :id, :root }]
    def self.na_require_run(params)
        instance = params['instance_object']
        if instance.nil? && !params['run_id'].to_s.strip.empty?
            wanted   = params['run_id'].to_s.strip.upcase
            instance = na_run_serializer.na_all_runs.find { |run| na_run_serializer.na_get_id_from_instance(run) == wanted }
            na_refuse('not_found', "There is no run #{wanted} in this model.", 'List them with assembly_run runs.') unless instance
        end
        loaded = instance ? na_run_pipelines.na_pipeline_load(instance) : nil
        return [instance, loaded] if loaded

        na_refuse(instance ? 'wrong_type' : 'invalid_params',
                  instance ? "#{instance.definition.name} is not an assembly run." : 'This action needs a run: instance_id or run_id (e.g. "ARN001").',
                  'List the runs with assembly_run runs.')
    end
    private_class_method :na_require_run
    # ---------------------------------------------------------------

    # HELPER FUNCTION | A Layout's Errors as One Refusal
    # ------------------------------------------------------------
    def self.na_run_refuse_layout(layout)
        na_refuse('invalid_params', "The run cannot be built: #{layout[:errors].join(' | ')}",
                  'Nothing was changed. Check a description first with assembly_run layout, or dry_run: true.', { 'errors' => layout[:errors] })
    end
    private_class_method :na_run_refuse_layout
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Run a Pipeline, Turning Its Failures Into Refusals
    # ------------------------------------------------------------
    def self.na_run_guard(verb)
        yield
    rescue Na__AssemblyStudio::Na__McpOperationsError
        raise
    rescue Na__AssemblyStudio::Na__AssemblyRunSystem::Na__RunLayoutError => error
        na_refuse('invalid_params', error.message, 'Nothing was changed.', { 'errors' => error.na_errors })
    rescue ArgumentError => error
        na_refuse('invalid_params', error.message, 'Nothing was changed. assembly_run inspect shows the run\'s spans and panel types.')
    rescue StandardError => error
        na_refuse('operation_failed', "The run could not be #{verb}: #{error.message}",
                  'Nothing was left behind (the step was aborted). Check the panel types\' values, or read the Ruby Console.')
    end
    private_class_method :na_run_guard
    # ---------------------------------------------------------------

    # HELPER FUNCTION | What a Build, Rebuild or Inspect Reports
    # ------------------------------------------------------------
    def self.na_run_result(instance, run_id, root, layout, report, undo_name = nil)
        defaults = na_run_defaults
        rows     = Array(root[defaults::NA_KEY_CONFIGURATION][defaults.na_key('PanelTypes')])
        types = layout[:types].values.map do |type|
            row = rows.find { |item| item['Code'].to_s.upcase == type[:code] } || {}
            { 'code' => type[:code], 'product' => type[:product], 'element_id' => row['ElementId'], 'spans' => type[:count],
              'width_mm' => type[:width] && type[:width].round(1), 'height_mm' => type[:height] && type[:height].round(1),
              'sill_mm' => type[:sill], 'keys' => type[:spans], 'made_by_fill' => type[:auto] ? true : nil, 'shelved' => (type[:count].to_i.zero? && row['SeedRoot'] ? true : nil) }.compact
        end
        members = na_run_serializer.na_members(instance.definition).map do |member|
            leg  = member.get_attribute(defaults::NA_MEMBER_DICT, defaults::NA_MEMBER_KEY_LEG).to_i
            span = member.get_attribute(defaults::NA_MEMBER_DICT, defaults::NA_MEMBER_KEY_SPAN).to_i
            { 'key' => "L#{leg + 1}S#{span + 1}", 'panel_type' => member.get_attribute(defaults::NA_MEMBER_DICT, defaults::NA_MEMBER_KEY_TYPE),
              'instance_id' => member.persistent_id, 'element' => member.definition.name }
        end
        {
            'instance_object' => instance,
            'id'              => run_id,
            'name'            => instance.name,
            'mode'            => layout[:mode],
            'copies'          => instance.definition.instances.length,
            'panel_types'     => types,
            'spans'           => members,
            'counts'          => report ? report[:counts].transform_keys(&:to_s) : nil,
            'undo_name'       => undo_name,
            'warnings'        => report ? report[:warnings] : layout[:warnings]
        }.compact
    end
    private_class_method :na_run_result
    # ---------------------------------------------------------------

    # HELPER FUNCTION | A Run's Stored Configuration, Without the Bulky Seeds
    # ------------------------------------------------------------
    def self.na_run_stored_config(root)
        defaults = na_run_defaults
        config   = na_deep_copy(root[defaults::NA_KEY_CONFIGURATION] || {})
        Array(config[defaults.na_key('PanelTypes')]).each { |row| row['SeedRoot'] = '(kept: this type\'s element settings)' if row['SeedRoot'] }
        config
    end
    private_class_method :na_run_stored_config
    # ---------------------------------------------------------------

    # HELPER FUNCTION | A Layout in One Sentence
    # ------------------------------------------------------------
    def self.na_run_layout_summary(layout)
        return "#{layout[:errors].length} problem#{layout[:errors].length == 1 ? '' : 's'}: #{layout[:errors].join(' | ')}" unless layout[:errors].empty?
        types = layout[:types].values.select { |type| type[:count].to_i > 0 }
        legs  = layout[:legs].map do |leg|
            "leg #{leg[:index] + 1} (#{leg[:length].round}mm): " + Array(leg[:items]).map { |item|
                item[:kind] == 'Span' ? item[:type] : "#{item[:role].downcase} #{item[:width].round}"
            }.join(', ')
        end
        "#{layout[:mode]}, #{layout[:span_count]} span#{layout[:span_count] == 1 ? '' : 's'}; " +
            types.map { |type| "#{type[:code]} = #{type[:product]} #{type[:width].round(1)}mm x#{type[:count]}" }.join(', ') + '; ' + legs.join('; ') + '.' +
            (layout[:warnings].empty? ? '' : " Note: #{layout[:warnings].join(' ')}")
    end
    private_class_method :na_run_layout_summary
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__McpOperations
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
