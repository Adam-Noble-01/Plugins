# =============================================================================
# NA SKETCHUP MCP - HANDLERS - AGENT OUTLINER
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__AgentOutliner__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__AgentOutliner
# PURPOSE    : agent_outliner, agent_outliner_edit
# CREATED    : 10-Nov-2026
#
# A THIN SEAM:
# The rules live in Adam's Agent Outliner (Na Noble3d Modelling Tools:
# 10__PluginModules/36__SourceCode__AgentOutliner/06__McpOperations). These
# handlers only check the action, drop keys sent as null, hand over the open
# model, move the seam's warnings onto the response, and turn its refusals
# (Na__AgentOutliner::Na__McpOperationsError: code, message, hint, details)
# into Na__McpError. Without the Agent Outliner both tools refuse and name the
# fix.
#
# WHAT IT GIVES AGENTS:
# - agent_outliner (read): summary, inbox (what Adam flagged or asked),
#   changes (what Adam or agents changed, since a cursor), thread, prefixes
#   (what CAD__FrontElevation and the other standard names mean, and which
#   objects carry them), find (the Outliner's search language); from
#   1.0.23 threads (every thread, open or resolved, waiting on an agent or
#   on Adam) and flags (every flagged object by type, Do Not Touch too);
#   from 1.0.25 tags; from 1.0.31 tag_tree (Adam's Tree by Tag view: tag
#   folders, tags, and each tag's objects as trees, with tag and depth);
#   from 1.0.32 category_tree (his Group by Category view: the naming
#   categories, their prefixes, and each prefix's objects as trees, with
#   prefix and depth; Agent Outliner 0.1.18).
# - agent_outliner_edit: comment, reply, resolve, reopen, flag, unflag,
#   acknowledge, name; from 1.0.23 strip (a standard prefix taken off).
#
# THE WAITING NOTICE (1.0.28):
# Na__Handlers__AgentOutliner__Notice is not a tool. The CommandRouter calls it
# after every tool and puts its answer on the response as 'outliner' while
# anything in the Agent Outliner waits for an agent (Adam's comment, an inbox
# flag), so an agent busy modelling hears him on its next call. The seam
# (Agent Outliner 0.1.9) caches it per model, so a call costs no scan. An
# older Agent Outliner, a missing one or any fault gives nil: no notice, never
# an error. A server before 1.0.28 drops the 'outliner' key, so for a request
# that does not list 'outliner' in its features (1.0.29) the router also adds
# Na__Handlers__AgentOutliner__NoticeLine to the warnings, which every server
# shows: sessions started before the update hear Adam without a restart.
#
# UNDO:
# agent_outliner_edit has "operation": false: the seam opens one
# "MCP: Agent Outliner Edit" step only when it writes the model (a comment,
# flag, status or name). acknowledge writes nothing into the model (what an
# agent has read is kept on this PC), so it adds no undo step. The edit tool is
# in NA_BATCH_FORBIDDEN; the read tool changes nothing.
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Handlers__AgentOutliner

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_READ_ACTIONS  = %w[summary inbox changes thread threads flags prefixes find tags tag_tree category_tree].freeze
        NA_EDIT_ACTIONS  = %w[comment reply resolve reopen flag unflag acknowledge name strip tag].freeze
        NA_PARTNER_ERROR = 'Na__AgentOutliner::Na__McpOperationsError'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | agent_outliner / agent_outliner_edit
# -----------------------------------------------------------------------------

        def self.Na__Handlers__AgentOutliner__Read(params, ctx)
            action = Na__Params.Na__Params__Enum(params, 'action', NA_READ_ACTIONS, nil, required: true)
            operations = na_operations
            na_forward(ctx) { operations.Na__AgentOutliner__McpRead(action, na_arguments(params, ctx)) }
        end

        def self.Na__Handlers__AgentOutliner__Edit(params, ctx)
            action = Na__Params.Na__Params__Enum(params, 'action', NA_EDIT_ACTIONS, nil, required: true)
            operations = na_operations
            result = na_forward(ctx) { operations.Na__AgentOutliner__McpEdit(action, na_arguments(params, ctx)) }
            ctx[:undo_name] = result['undo'] if result.is_a?(Hash) && result['undo']
            result
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | The Waiting Notice (1.0.28: on every tool's answer, not a tool)
# -----------------------------------------------------------------------------

        # FUNCTION | What Waits for an Agent in the Agent Outliner, or nil
        # ------------------------------------------------------------
        # A Hash (waiting, from, at, ago, where, text, pictures, threads, read,
        # note) while anything waits; nil when nothing does, when the Agent
        # Outliner is missing or older than 0.1.9, or on any fault.
        def self.Na__Handlers__AgentOutliner__Notice(model)
            return nil unless model && defined?(::Na__AgentOutliner::Na__McpOperations) &&
                              ::Na__AgentOutliner::Na__McpOperations.respond_to?(:Na__AgentOutliner__McpNotice)

            notice = ::Na__AgentOutliner::Na__McpOperations.Na__AgentOutliner__McpNotice(model)
            notice.is_a?(Hash) && !notice.empty? ? notice : nil
        rescue StandardError, ScriptError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Notice as One Warning Line (for a server before 1.0.28)
        # ------------------------------------------------------------
        def self.Na__Handlers__AgentOutliner__NoticeLine(notice)
            count   = notice['waiting'].to_i
            details = ["#{count} waiting", notice['where'], notice['ago']].compact.reject { |part| part.to_s.empty? }
            details << "#{notice['pictures']} picture#{notice['pictures'].to_i == 1 ? '' : 's'}" if notice['pictures']
            "#{notice['from'] || 'Adam'} WROTE TO YOU in the Agent Outliner (#{details.join(', ')}): \"#{notice['text']}\" " \
                "Read it before your next change: #{notice['read'] || 'agent_outliner {action: "inbox"}'}; then reply or acknowledge."
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Helpers
# -----------------------------------------------------------------------------

        # The Agent Outliner seam, or a refusal that names the fix.
        def self.na_operations
            if defined?(::Na__AgentOutliner::Na__McpOperations) &&
               ::Na__AgentOutliner::Na__McpOperations.respond_to?(:Na__AgentOutliner__McpRead)
                return ::Na__AgentOutliner::Na__McpOperations
            end

            raise Na__McpError.new('unsupported',
                                   'The outliner tools need Na Noble3d Modelling Tools with the Agent Outliner (0.1.0 or newer).',
                                   'Install or update Na Noble3d Modelling Tools, then use its Reload Plugin Data (or restart SketchUp).')
        end

        # The call's arguments without 'action' and without keys sent as null,
        # plus the open model (the seam never reaches for Sketchup.active_model
        # when the MCP has one).
        def self.na_arguments(params, ctx)
            arguments = params.each_with_object({}) do |(key, value), list|
                next if key.to_s == 'action' || !Na__Params.Na__Params__Has(params, key)

                list[key.to_s] = value
            end
            arguments['model_object'] = ctx[:model]
            arguments
        end

        # Runs the seam call, moves its warnings onto the response and turns
        # its refusals into Na__McpError.
        def self.na_forward(ctx)
            result = yield
            if result.is_a?(Hash)
                Array(result.delete('warnings')).each { |text| ctx[:warnings] << text.to_s }
            end
            result
        rescue Na__McpError
            raise
        rescue StandardError => error
            raise unless error.class.name.to_s == NA_PARTNER_ERROR

            raise Na__McpError.new(error.na_code, error.message, error.na_hint, error.na_details)
        end

# endregion -------------------------------------------------------------------

    end # module Na__Handlers__AgentOutliner
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
