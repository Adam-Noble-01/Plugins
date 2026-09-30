# =============================================================================
# NA SKETCHUP MCP - HANDLERS - STATUS
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__Status__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__Status
# PURPOSE    : sketchup_status, plus the internal ping and api_probe commands
# CREATED    : 2026
#
# Every handler in 10__BridgeHandlers has the same shape:
#   def self.Na__Handlers__<Domain>__<Tool>(params, ctx) -> Hash (JSON-safe)
# params: the tool arguments (string keys). ctx: { model:, unit:, warnings:, ... }
# Handlers raise Na__McpError to refuse; the router aborts the undo operation.
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Handlers__Status

# -----------------------------------------------------------------------------
# REGION | sketchup_status
# -----------------------------------------------------------------------------

        def self.Na__Handlers__Status__Status(params, ctx)
            model = ctx[:model]
            report = {
                'sketchup' => na_sketchup_facts,
                'bridge'   => na_bridge_facts,
                'model'    => na_model_facts(model, ctx),
                'units'    => ctx[:unit]
            }

            self_test = Na__ApiSelfTest.Na__ApiSelfTest__Report
            report['api_self_test'] = { 'checked' => self_test['checked'], 'unavailable_tools' => self_test['unavailable_tools'] }
            report['extensions'] = na_extensions if Na__Params.Na__Params__Boolean(params, 'include_extensions', false)
            report
        end

        def self.na_sketchup_facts
            {
                'version'      => Sketchup.version.to_s,
                'is_pro'       => Sketchup.is_pro?,
                'platform'     => Sketchup.platform.to_s,
                'ruby_version' => RUBY_VERSION
            }
        end

        def self.na_bridge_facts
            status = Na__SocketServer.Na__SocketServer__Status
            status.merge(
                'version'         => Na__ConfigLoader.Na__ConfigLoader__BridgeVersion,
                'read_only_mode'  => Na__ConfigLoader.Na__ConfigLoader__ReadOnlyMode,
                'allow_ruby_eval' => Na__ConfigLoader.Na__ConfigLoader__AllowRubyEval
            )
        end

        def self.na_model_facts(model, ctx)
            active_path = Na__Coordinates.Na__Coordinates__ActivePath(model)
            {
                'title'           => model.title.to_s,
                'path'            => model.path.to_s,
                'modified'        => model.modified?,
                'active_context'  => active_path.map { |instance| Na__Serializer.Na__Serializer__InstanceLabel(instance) },
                'selection_count' => model.selection.length,
                'active_tool'     => model.tools.active_tool_name.to_s,
                'active_scene'    => model.pages.selected_page ? model.pages.selected_page.name : nil,
                'length_unit_of_model' => Na__Units.Na__Units__ModelLengthUnit(model)
            }
        end

        def self.na_extensions
            Sketchup.extensions.map do |extension|
                {
                    'name'    => extension.name.to_s,
                    'version' => extension.version.to_s,
                    'creator' => extension.creator.to_s,
                    'loaded'  => extension.loaded?
                }
            end
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Commands (ping, api_probe)
# -----------------------------------------------------------------------------

        def self.Na__Handlers__Status__Ping(_params, ctx)
            {
                'pong'             => true,
                'pid'              => Process.pid,
                'sketchup_version' => Sketchup.version.to_s,
                'bridge_version'   => Na__ConfigLoader.Na__ConfigLoader__BridgeVersion,
                'model_title'      => ctx[:model].title.to_s,
                'model_path'       => ctx[:model].path.to_s
            }
        end

        # params: signatures => ["Sketchup::Face#pushpull", "Sketchup.send_action", ...]
        def self.Na__Handlers__Status__ApiProbe(params, _ctx)
            signatures = Na__Params.Na__Params__Array(params, 'signatures', nil, required: true, max_items: 500)
            results = signatures.each_with_object({}) do |signature, lookup|
                lookup[signature.to_s] = Na__ApiSelfTest.Na__ApiSelfTest__Probe(signature)
            end
            { 'results' => results }
        end

# endregion -------------------------------------------------------------------

    end # module Na__Handlers__Status
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
