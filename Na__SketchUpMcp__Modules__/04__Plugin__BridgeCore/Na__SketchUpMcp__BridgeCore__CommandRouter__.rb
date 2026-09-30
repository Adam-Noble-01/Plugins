# =============================================================================
# NA SKETCHUP MCP - BRIDGE CORE - COMMAND ROUTER
# =============================================================================
#
# FILE       : Na__SketchUpMcp__BridgeCore__CommandRouter__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__CommandRouter
# PURPOSE    : Route each request to its handler with the safety rules applied:
#              read-only gate, API availability, one undo step per call,
#              abort on failure, atomic batches
# CREATED    : 2026
#
# CONFIG-FIRST DESIGN NOTE:
# Which handler a tool runs, whether it changes the model and its undo name all
# come from the tool registry JSON (handler_key, mutates, operation, title).
# This file only maps handler keys to Ruby methods.
#
# UNDO CONTRACT:
# Every model-changing call is exactly one SketchUp operation named
# "MCP: <tool title>", so the user can Ctrl+Z any agent action and read in
# Edit > Undo what it was. Any exception aborts the operation: the model is
# left exactly as it was. A batch is ONE operation for all its steps.
#
# BATCH REFERENCES:
# A string argument "$<step>.<path>" is replaced by a value from an earlier
# step's result, e.g. "$0.id" or "$1.created_ids.0". This lets an agent build
# and then transform a solid in one round trip and one undo step.
#
# =============================================================================

module Na__SketchUpMcp
    module Na__CommandRouter

# -----------------------------------------------------------------------------
# REGION | Handler Routes (handler_key -> [module, method])
# -----------------------------------------------------------------------------

        NA_HANDLER_ROUTES = {
            'ping'                  => [:Na__Handlers__Status,       :Na__Handlers__Status__Ping],
            'api_probe'             => [:Na__Handlers__Status,       :Na__Handlers__Status__ApiProbe],
            'sketchup_status'       => [:Na__Handlers__Status,       :Na__Handlers__Status__Status],
            'model_info'            => [:Na__Handlers__Model,        :Na__Handlers__Model__Info],
            'model_settings'        => [:Na__Handlers__Model,        :Na__Handlers__Model__Settings],
            'model_file'            => [:Na__Handlers__ModelFile,    :Na__Handlers__ModelFile__File],
            'model_purge'           => [:Na__Handlers__Model,        :Na__Handlers__Model__Purge],
            'entity_query'          => [:Na__Handlers__Query,        :Na__Handlers__Query__EntityQuery],
            'entity_get'            => [:Na__Handlers__Query,        :Na__Handlers__Query__EntityGet],
            'outliner_tree'         => [:Na__Handlers__Query,        :Na__Handlers__Query__OutlinerTree],
            'collection_list'       => [:Na__Handlers__Collections,  :Na__Handlers__Collections__List],
            'selection_get'         => [:Na__Handlers__Selection,    :Na__Handlers__Selection__Get],
            'selection_set'         => [:Na__Handlers__Selection,    :Na__Handlers__Selection__Set],
            'context_set'           => [:Na__Handlers__Selection,    :Na__Handlers__Selection__ContextSet],
            'geometry_measure'      => [:Na__Handlers__Measure,      :Na__Handlers__Measure__Measure],
            'geometry_draw'         => [:Na__Handlers__Geometry,     :Na__Handlers__Geometry__Draw],
            'geometry_create_solid' => [:Na__Handlers__Primitives,   :Na__Handlers__Primitives__CreateSolid],
            'geometry_create_mesh'  => [:Na__Handlers__Geometry,     :Na__Handlers__Geometry__CreateMesh],
            'geometry_extrude'      => [:Na__Handlers__Geometry,     :Na__Handlers__Geometry__Extrude],
            'geometry_edit'         => [:Na__Handlers__GeometryEdit, :Na__Handlers__GeometryEdit__Edit],
            'solid_boolean'         => [:Na__Handlers__Booleans,     :Na__Handlers__Booleans__Boolean],
            'annotation_create'     => [:Na__Handlers__Annotations,  :Na__Handlers__Annotations__Create],
            'image_place'           => [:Na__Handlers__Annotations,  :Na__Handlers__Annotations__ImagePlace],
            'section_plane'         => [:Na__Handlers__Annotations,  :Na__Handlers__Annotations__SectionPlane],
            'group_create'          => [:Na__Handlers__Components,   :Na__Handlers__Components__GroupCreate],
            'component_place'       => [:Na__Handlers__Components,   :Na__Handlers__Components__Place],
            'component_manage'      => [:Na__Handlers__Components,   :Na__Handlers__Components__Manage],
            'asset_library'         => [:Na__Handlers__AssetLibrary, :Na__Handlers__AssetLibrary__Read],
            'asset_library_edit'    => [:Na__Handlers__AssetLibrary, :Na__Handlers__AssetLibrary__Edit],
            'entity_transform'      => [:Na__Handlers__EntityEdit,   :Na__Handlers__EntityEdit__Transform],
            'entity_delete'         => [:Na__Handlers__EntityEdit,   :Na__Handlers__EntityEdit__Delete],
            'entity_set_properties' => [:Na__Handlers__EntityEdit,   :Na__Handlers__EntityEdit__SetProperties],
            'attributes_get'        => [:Na__Handlers__Attributes,   :Na__Handlers__Attributes__Get],
            'attributes_set'        => [:Na__Handlers__Attributes,   :Na__Handlers__Attributes__Set],
            'material_manage'       => [:Na__Handlers__Materials,    :Na__Handlers__Materials__Manage],
            'material_apply'        => [:Na__Handlers__Materials,    :Na__Handlers__Materials__Apply],
            'tag_manage'            => [:Na__Handlers__Tags,         :Na__Handlers__Tags__Manage],
            'scene_manage'          => [:Na__Handlers__Scenes,       :Na__Handlers__Scenes__Manage],
            'view_get'              => [:Na__Handlers__View,         :Na__Handlers__View__Get],
            'view_set'              => [:Na__Handlers__View,         :Na__Handlers__View__Set],
            'view_capture'          => [:Na__Handlers__View,         :Na__Handlers__View__Capture],
            'sketchup_send_action'  => [:Na__Handlers__Actions,      :Na__Handlers__Actions__SendAction],
            'model_undo'            => [:Na__Handlers__Actions,      :Na__Handlers__Actions__Undo],
            'ruby_eval'             => [:Na__Handlers__Ruby,         :Na__Handlers__Ruby__Eval]
        }.freeze

        # Bridge commands that are not MCP tools in the registry.
        NA_INTERNAL_COMMANDS = {
            'ping'      => { 'name' => 'ping', 'title' => 'Ping', 'handler_key' => 'ping', 'mutates' => false },
            'api_probe' => { 'name' => 'api_probe', 'title' => 'API Probe', 'handler_key' => 'api_probe', 'mutates' => false }
        }.freeze

        # Never allowed inside batch_execute, with the reason an agent is told.
        NA_BATCH_FORBIDDEN = {
            'batch_execute' => 'batches cannot nest',
            'model_file'    => 'opening, saving, importing and exporting replace or leave the model; call model_file on its own',
            'context_set'   => 'changing the open group splits SketchUp\'s undo operation, so the batch could not be rolled back; call context_set before the batch',
            'asset_library' => 'it opens library files in its own operation, which would end the batch\'s undo operation; call it on its own',
            'asset_library_edit' => 'it changes files on disk in its own operations, which cannot be rolled back with the batch; call it on its own'
        }.freeze

        NA_REFERENCE = /\A\$(\d+)((?:\.[A-Za-z0-9_]+)*)\z/.freeze

        # A call slower than this is reported (clients such as Claude Desktop give up near 60 s),
        # unless its handler already explained why (ctx[:slow_reported]).
        NA_SLOW_CALL_MS = 15_000

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dispatch (one request from the socket)
# -----------------------------------------------------------------------------

        def self.Na__CommandRouter__Dispatch(request)
            started = na_clock
            command = request['command'].to_s
            params = request['params'].is_a?(Hash) ? request['params'] : {}
            ctx = na_new_context(params)

            result = if command == 'batch_execute'
                         na_run_batch(params, ctx)
                     else
                         na_run_tool(na_tool_definition(command), params, ctx, true)
                     end

            elapsed = na_elapsed_ms(started)
            if elapsed > NA_SLOW_CALL_MS && !ctx[:slow_reported]
                ctx[:warnings] << "This call ran #{(elapsed / 1000.0).round(1)} s inside SketchUp. Some clients give up at about 60 s, " \
                                  'so split heavy work into smaller calls.'
            end
            Na__ActivityLog.Na__ActivityLog__Record(command, elapsed, true, na_outcome_text(result))
            response = { 'id' => request['id'], 'ok' => true, 'result' => result, 'elapsed_ms' => elapsed }
            response['warnings'] = ctx[:warnings].uniq unless ctx[:warnings].empty?
            response['undo'] = ctx[:undo_name] if ctx[:undo_name]
            response
        rescue Na__McpError => error
            elapsed = na_elapsed_ms(started)
            Na__ActivityLog.Na__ActivityLog__Record(request['command'], elapsed, false, error.message)
            { 'id' => request['id'], 'ok' => false, 'error' => error.na_to_hash, 'elapsed_ms' => elapsed }
        rescue StandardError, ScriptError => error
            elapsed = na_elapsed_ms(started)
            Na__ActivityLog.Na__ActivityLog__Record(request['command'], elapsed, false, "#{error.class}: #{error.message}")
            { 'id' => request['id'], 'ok' => false, 'elapsed_ms' => elapsed,
              'error' => { 'code' => 'sketchup_error', 'message' => "#{error.class}: #{error.message}",
                           'hint' => 'SketchUp raised an exception; the operation was aborted and the model is unchanged.',
                           'details' => { 'backtrace' => na_short_backtrace(error) } } }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Operation Wrapping (public: handlers use it for partial operations)
# -----------------------------------------------------------------------------

        # Runs the block inside one undo operation unless one is already open for this request.
        def self.Na__CommandRouter__WithOperation(ctx, operation_name)
            return yield if ctx[:in_operation]

            model = ctx[:model]
            model.start_operation(operation_name, true)
            ctx[:in_operation] = true
            begin
                result = yield
                model.commit_operation
                ctx[:undo_name] = operation_name
                result
            rescue Exception
                model.abort_operation
                raise
            ensure
                ctx[:in_operation] = false
            end
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Tool Execution
# -----------------------------------------------------------------------------

        def self.na_tool_definition(command)
            tool = NA_INTERNAL_COMMANDS[command] || Na__ConfigLoader.Na__ConfigLoader__ToolByName(command)
            return tool if tool && tool['runs_on'] != 'server'

            raise Na__McpError.new('unknown_command', "Unknown bridge command '#{command}'.",
                                   'The MCP server and this SketchUp bridge may be different versions: reload the plugin and restart the MCP server.')
        end

        def self.na_run_tool(tool, params, ctx, wrap_operation)
            na_check_available(tool)
            na_check_safety(tool)
            method_owner, method_name = na_route(tool)

            call = -> { Na__SketchUpMcp.const_get(method_owner).public_send(method_name, params, ctx) }
            return call.call unless wrap_operation && na_tool_wraps_operation?(tool)

            self.Na__CommandRouter__WithOperation(ctx, "MCP: #{tool['title'] || tool['name']}") { call.call }
        end

        def self.na_route(tool)
            route = NA_HANDLER_ROUTES[tool['handler_key'] || tool['name']]
            return route if route

            raise Na__McpError.new('unknown_command', "No handler registered for '#{tool['name']}'.",
                                   'Reload the plugin; the registry and the bridge code are out of step.')
        end

        def self.na_tool_wraps_operation?(tool)
            tool['mutates'] == true && tool['operation'] != false
        end

        def self.na_check_available(tool)
            missing = Na__ApiSelfTest.Na__ApiSelfTest__MissingDependencyFor(tool['name'])
            return unless missing

            raise Na__McpError.new('unsupported', "#{tool['name']} is unavailable in this SketchUp: #{missing} does not exist here.",
                                   'Solid tools need SketchUp Pro/Studio; newer API features need a newer SketchUp. Use another tool or ruby_eval.')
        end

        def self.na_check_safety(tool)
            if tool['mutates'] == true && Na__ConfigLoader.Na__ConfigLoader__ReadOnlyMode
                raise Na__McpError.new('read_only', "The SketchUp bridge is in read-only mode; #{tool['name']} changes the model.",
                                       'Ask the user to switch off read-only mode in Extensions > Na SketchUp MCP > Status Dialog.')
            end
            return unless tool['name'] == 'ruby_eval' && !Na__ConfigLoader.Na__ConfigLoader__AllowRubyEval

            raise Na__McpError.new('eval_disabled', 'ruby_eval is switched off in the SketchUp bridge.',
                                   'Use the dedicated tools, or ask the user to allow Ruby evaluation in the Status Dialog.')
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Batch Execution
# -----------------------------------------------------------------------------

        def self.na_run_batch(params, ctx)
            steps = Na__Params.Na__Params__Array(params, 'steps', nil, required: true, min_items: 1, max_items: 200)
            atomic = Na__Params.Na__Params__Boolean(params, 'atomic', true)
            stop_on_error = Na__Params.Na__Params__Boolean(params, 'stop_on_error', true)
            tools = steps.each_with_index.map { |step, index| na_batch_tool(step, index, atomic) }
            mutating = tools.any? { |tool| tool['mutates'] == true }
            operation_name = "MCP: #{Na__Params.Na__Params__String(params, 'operation_name', "Batch (#{steps.length} steps)")}"

            na_check_safety({ 'name' => 'batch_execute', 'mutates' => mutating })
            results = []
            runner = -> { na_run_batch_steps(steps, tools, results, ctx, atomic, stop_on_error) }
            mutating ? self.Na__CommandRouter__WithOperation(ctx, operation_name, &runner) : runner.call

            {
                'steps'     => results,
                'completed' => results.count { |entry| entry['ok'] },
                'failed'    => results.count { |entry| !entry['ok'] },
                'atomic'    => atomic
            }
        end

        def self.na_batch_tool(step, index, atomic)
            unless step.is_a?(Hash) && step['tool'].is_a?(String)
                raise Na__McpError.new('invalid_params', "steps[#{index}] must be {\"tool\": \"...\", \"arguments\": {...}}.", nil)
            end

            name = step['tool']
            reason = NA_BATCH_FORBIDDEN[name]
            reason = nil if name == 'context_set' && !atomic
            raise Na__McpError.new('invalid_params', "steps[#{index}]: #{name} is not allowed in a batch: #{reason}.", nil) if reason

            na_tool_definition(name)
        end

        def self.na_run_batch_steps(steps, tools, results, ctx, atomic, stop_on_error)
            steps.each_with_index do |step, index|
                started = na_clock
                begin
                    arguments = na_resolve_references(step['arguments'] || {}, results, index)
                    step_ctx = na_step_context(ctx, arguments)
                    result = na_run_tool(tools[index], arguments, step_ctx, false)
                    ctx[:warnings].concat(step_ctx[:warnings].map { |text| "step #{index}: #{text}" })
                    ctx[:slow_reported] ||= step_ctx[:slow_reported]
                    entry = { 'step' => index, 'tool' => tools[index]['name'], 'ok' => true, 'result' => result,
                              'elapsed_ms' => na_elapsed_ms(started) }
                    # Kept on the step too: when an atomic batch fails, only details.steps reaches the agent.
                    entry['warnings'] = step_ctx[:warnings] unless step_ctx[:warnings].empty?
                    results << entry
                rescue Na__McpError, StandardError, ScriptError => error
                    failure = error.is_a?(Na__McpError) ? error.na_to_hash : { 'code' => 'sketchup_error', 'message' => "#{error.class}: #{error.message}" }
                    results << { 'step' => index, 'tool' => tools[index]['name'], 'ok' => false, 'error' => failure }
                    if atomic
                        raise Na__McpError.new('operation_failed',
                                               "Batch step #{index} (#{tools[index]['name']}) failed: #{failure['message']} Every step was undone (atomic batch).",
                                               failure['hint'] || 'Fix that step and send the batch again, or pass atomic:false to keep the steps that succeed.',
                                               { 'steps' => results })
                    end
                    break if stop_on_error
                end
            end
        end

        def self.na_step_context(ctx, arguments)
            step_unit = arguments.key?('units') ? Na__Units.Na__Units__Resolve(arguments['units'], ctx[:model]) : ctx[:unit]
            ctx.merge(unit: step_unit, warnings: [], to_world_cache: {}, path_cache: {})
        end

        def self.na_resolve_references(value, results, current_index)
            case value
            when Hash
                value.each_with_object({}) { |(key, item), resolved| resolved[key] = na_resolve_references(item, results, current_index) }
            when Array
                value.map { |item| na_resolve_references(item, results, current_index) }
            when String
                match = NA_REFERENCE.match(value)
                match ? na_reference_value(match, results, current_index, value) : value
            else
                value
            end
        end

        def self.na_reference_value(match, results, current_index, text)
            step_index = match[1].to_i
            entry = results.find { |candidate| candidate['step'] == step_index }
            unless step_index < current_index && entry && entry['ok']
                raise Na__McpError.new('invalid_params', "Reference #{text} points at step #{step_index}, which has not succeeded before this step.",
                                       'A reference can only use an earlier, successful step.')
            end

            match[2].split('.').reject(&:empty?).reduce(entry['result']) do |node, key|
                found = node.is_a?(Array) && key =~ /\A\d+\z/ ? node[key.to_i] : (node.is_a?(Hash) ? node[key] : nil)
                if found.nil?
                    raise Na__McpError.new('invalid_params', "Reference #{text}: '#{key}' not found in step #{step_index}'s result.",
                                           "Step #{step_index} returned keys: #{node.is_a?(Hash) ? node.keys.join(', ') : node.class}.")
                end

                found
            end
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Context and Small Helpers
# -----------------------------------------------------------------------------

        def self.na_new_context(params)
            model = Sketchup.active_model
            unless model
                raise Na__McpError.new('context_error', 'SketchUp has no active model.', 'Open or create a model in SketchUp first.')
            end

            {
                model: model,
                unit: Na__Units.Na__Units__Resolve(params['units'], model),
                warnings: [],
                in_operation: false,
                undo_name: nil,
                to_world_cache: {},
                path_cache: {}
            }
        end

        def self.na_clock
            Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

        def self.na_elapsed_ms(started)
            ((na_clock - started) * 1000.0).round(1)
        end

        def self.na_outcome_text(result)
            return '' unless result.is_a?(Hash)

            %w[message summary].each { |key| return result[key].to_s if result[key] }
            result['id'] ? "id #{result['id']}" : result.keys.first(6).join(', ')
        end

        def self.na_short_backtrace(error)
            (error.backtrace || []).reject { |line| line.include?('/Tools/') }.first(8)
        end

# endregion -------------------------------------------------------------------

    end # module Na__CommandRouter
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
