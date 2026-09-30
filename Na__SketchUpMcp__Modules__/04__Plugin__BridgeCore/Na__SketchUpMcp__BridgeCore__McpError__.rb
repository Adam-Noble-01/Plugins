# =============================================================================
# NA SKETCHUP MCP - BRIDGE ERROR TYPE
# =============================================================================
#
# FILE       : Na__SketchUpMcp__BridgeCore__McpError__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__McpError
# PURPOSE    : One error type every handler raises, carrying a machine code,
#              a plain message and a hint that names the fix
# CREATED    : 2026
#
# ERROR POLICY (refuse with the fix named, never guess):
# An agent reads these messages and decides its next call from them. So every
# refusal says what was wrong AND what to do instead, e.g.
#   "Entity 812 is a Face, not a Group or ComponentInstance."
#   hint: "Wrap the geometry first with group_create, then transform the group."
# The command router turns this into {ok:false, error:{code,message,hint}} and
# aborts the open undo operation, so a refused call never half-changes the model.
#
# CODES:
#   invalid_params    a parameter is missing, the wrong type or out of range
#   not_found         an id, name or file does not exist
#   wrong_type        an entity exists but is the wrong kind for this tool
#   context_error     the active edit context blocks the request
#   unsupported       this SketchUp build or licence lacks the feature
#   read_only         the bridge is in read-only mode
#   eval_disabled     ruby_eval is switched off in the status dialog
#   operation_failed  SketchUp refused or produced no result
#   file_error        a file could not be read or written
#
# =============================================================================

module Na__SketchUpMcp

# -----------------------------------------------------------------------------
# REGION | Error Class
# -----------------------------------------------------------------------------

    class Na__McpError < StandardError

        attr_reader :na_code, :na_hint, :na_details

        def initialize(code, message, hint = nil, details = nil)
            super(message)
            @na_code = code.to_s
            @na_hint = hint
            @na_details = details
        end

        def na_to_hash
            payload = { 'code' => @na_code, 'message' => message }
            payload['hint'] = @na_hint if @na_hint && !@na_hint.to_s.empty?
            payload['details'] = @na_details if @na_details
            payload
        end

    end # class Na__McpError

# endregion -------------------------------------------------------------------

end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
