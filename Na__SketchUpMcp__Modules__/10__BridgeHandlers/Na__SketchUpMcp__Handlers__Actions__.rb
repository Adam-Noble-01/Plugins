# =============================================================================
# NA SKETCHUP MCP - HANDLERS - ACTIONS AND UNDO
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__Actions__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__Actions
# PURPOSE    : model_undo (Sketchup.undo / Sketchup.redo) and
#              sketchup_send_action (validated Sketchup.send_action names)
# CREATED    : 2026
#
# UNDO IS SYNCHRONOUS, SEND_ACTION IS NOT:
# Sketchup.undo (6.0) and Sketchup.redo (2021.0) act immediately. They are
# never wrapped in an operation (the registry marks model_undo operation:false),
# because undoing inside an open operation would undo that operation instead.
# Sketchup.send_action queues the action and SketchUp runs it after this call
# returns; it is deprecated from SketchUp 2026.2 (release notes) and kept only
# for things no dedicated tool covers, such as activating a native tool for the
# user. Only the named actions documented in the stubs are accepted: the list is
# the enum in this tool's registry schema, generated from Sketchup.send_action's
# doc comment. The numeric codes (officially unsupported) are refused.
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Handlers__Actions

# -----------------------------------------------------------------------------
# REGION | model_undo
# -----------------------------------------------------------------------------

        def self.Na__Handlers__Actions__Undo(params, _ctx)
            action = Na__Params.Na__Params__Enum(params, 'action', %w[undo redo], 'undo')
            steps = Na__Params.Na__Params__Integer(params, 'steps', 1, min: 1, max: 50)
            if action == 'redo' && !Sketchup.respond_to?(:redo)
                raise Na__McpError.new('unsupported', 'Sketchup.redo needs SketchUp 2021 or newer.', nil)
            end

            steps.times { action == 'undo' ? Sketchup.undo : Sketchup.redo }
            { 'action' => action, 'steps' => steps, 'summary' => "#{action.capitalize} x#{steps}." }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | sketchup_send_action
# -----------------------------------------------------------------------------

        def self.Na__Handlers__Actions__SendAction(params, _ctx)
            action = Na__Params.Na__Params__String(params, 'action', nil, required: true)
            allowed = na_allowed_actions
            unless allowed.include?(action)
                close = allowed.select { |name| name.downcase.include?(action.delete(':').downcase[0, 6].to_s) }.first(8)
                raise Na__McpError.new('invalid_params', "'#{action}' is not a documented send_action name.",
                                       close.empty? ? 'See the enum in this tool\'s schema.' : "Did you mean: #{close.join(', ')}?")
            end

            result = Sketchup.send_action(action)
            { 'action' => action, 'queued' => result ? true : false,
              'note' => 'SketchUp runs it just after this call returns; send_action is deprecated from SketchUp 2026.2.' }
        end

        # The enum of this tool's registry schema (single source of truth).
        def self.na_allowed_actions
            tool = Na__ConfigLoader.Na__ConfigLoader__ToolByName('sketchup_send_action') || {}
            tool.dig('input_schema', 'properties', 'action', 'enum') || []
        end

# endregion -------------------------------------------------------------------

    end # module Na__Handlers__Actions
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
