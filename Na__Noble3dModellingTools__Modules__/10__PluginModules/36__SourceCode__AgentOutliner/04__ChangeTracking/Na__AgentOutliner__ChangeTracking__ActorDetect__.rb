# =============================================================================
# NA AGENT OUTLINER - CHANGE TRACKING - ACTOR DETECT (ADAM OR AN AGENT?)
# =============================================================================
#
# FILE       : Na__AgentOutliner__ChangeTracking__ActorDetect__.rb
# NAMESPACE  : Na__AgentOutliner::Na__ActorDetect
# MODULE     : Na__ActorDetect (module functions)
# AUTHOR     : Noble Architecture
# PURPOSE    : Tell whether the change SketchUp is reporting right now was made
#              by an agent through the Na SketchUp MCP or by Adam, and which
#              MCP handler made it
# CREATED    : 10-Nov-2026
#
# DESCRIPTION:
# - HOW: the MCP bridge runs every request synchronously on SketchUp's main
#   thread (its socket pump calls Na__CommandRouter__Dispatch from a timer),
#   and SketchUp calls observers synchronously inside the operation that
#   caused them. So while an agent's request is changing the model, the MCP
#   plugin's own files are on the Ruby call stack; while Adam works with
#   SketchUp's tools, or any other plugin, they are not. The stack is read
#   with Kernel#caller_locations, which needs nothing from the MCP plugin and
#   survives its reloads.
# - THE MARKERS are folder names (engine.agent_stack_markers in the app
#   config, default Na__SketchUpMcp__Modules__), so another agent bridge can
#   be added without code.
# - WHICH TOOL: the first stack frame named Na__Handlers__<Family>__<Action> is
#   the MCP handler (Primitives__CreateSolid, Ruby__Eval ...).
# - COST: the stack is read once when an operation starts and reused for
#   every event inside it; events outside any operation read it once per
#   timer tick. A thousand edges added in one step cost one stack read.
# - UNDO AND REDO (0.1.11): their notices arrive inside the call that undid
#   (an agent's model_undo, or Adam's Ctrl+Z) and before the entity events
#   the undo raises, which come outside any operation (traced live in
#   SketchUp 2027). Na__Actor__UndoRedo reads the stack there, drops an
#   answer held from an operation (none is open across an undo) and holds
#   its own for those events. A held tick answer also expires after
#   NA_TICK_MAX_S, so a lost clearing timer can never leave one standing. In
#   the Assembly Studio testbed a stale answer made an agent's undo and redo
#   Adam's for two minutes.
# - LIMIT (documented): work an MCP handler defers to a later timer, and
#   Sketchup.send_action, run after the request returns, so they read as
#   Adam's. Edits through ruby_eval run inside the request and read as the
#   agent's.
#
# =============================================================================

module Na__AgentOutliner
    module Na__ActorDetect

        NA_NOT_AGENT_CALLS = %w[bridge_start bridge_stop reload setting ping api_probe].freeze unless defined?(NA_NOT_AGENT_CALLS)

# -----------------------------------------------------------------------------
# REGION | Constants and State
# -----------------------------------------------------------------------------

        NA_HANDLER_LABEL = /Na__Handlers__([A-Za-z0-9]+__[A-Za-z0-9]+)/.freeze unless defined?(NA_HANDLER_LABEL)
        NA_TICK_MAX_S    = 0.5 unless defined?(NA_TICK_MAX_S)                           # <-- A held tick answer older than this is read again (0.1.11)
        NA_TICK_LOST_S   = 2.0 unless defined?(NA_TICK_LOST_S)                          # <-- A clearing timer this late is taken as lost, and booked again (0.1.11)

        @na_transaction   = nil   unless defined?(@na_transaction)                      # <-- The answer for the operation now open
        @na_tick          = nil   unless defined?(@na_tick)                             # <-- The answer for events outside any operation, this tick only
        @na_tick_at       = 0.0   unless defined?(@na_tick_at)                          # <-- When it was read (0.1.11)
        @na_tick_timer    = false unless defined?(@na_tick_timer)
        @na_tick_timer_at = 0.0   unless defined?(@na_tick_timer_at)                    # <-- When its clearing timer was booked (0.1.11)

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | An Operation Started: Read the Stack Once
        # ------------------------------------------------------------
        def self.Na__Actor__TransactionStart
            @na_transaction = self.Na__Actor__FromStack
        end
        # ---------------------------------------------------------------

        # FUNCTION | An Operation Ended (Committed or Aborted): Hand Back Its Actor
        # ------------------------------------------------------------
        # The stack is read again at the commit: when an operation started with
        # no observer attached, the commit still knows who closed it.
        def self.Na__Actor__TransactionEnd
            answer = @na_transaction || self.Na__Actor__FromStack
            @na_transaction = nil
            answer
        end
        # ---------------------------------------------------------------

        # FUNCTION | Who Is Changing the Model Right Now?
        # ------------------------------------------------------------
        # Returns { 'by' => 'agent' or 'user', 'tool' => handler name or nil }.
        def self.Na__Actor__Current
            return @na_transaction if @na_transaction
            return @na_tick if @na_tick && (self.na_clock - @na_tick_at.to_f) <= NA_TICK_MAX_S

            self.na_hold_tick(self.Na__Actor__FromStack)
        end
        # ---------------------------------------------------------------

        # FUNCTION | An Undo or Redo: Who Pressed It? (read once, held for its events)
        # ------------------------------------------------------------
        # Called from onTransactionUndo / onTransactionRedo, which arrive inside
        # the call that undid and before the entity events it raises. No
        # operation is open across an undo, so an answer still held from one is
        # stale: dropped. The stack is read now and held for the events that
        # follow (0.1.11).
        def self.Na__Actor__UndoRedo
            @na_transaction = nil if @na_transaction                                    # <-- No operation is open across an undo or redo
            pressed_by = self.Na__Actor__FromStack
            self.na_hold_tick(pressed_by)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Read the Call Stack
        # ------------------------------------------------------------
        def self.Na__Actor__FromStack
            markers = self.na_markers
            agent   = false
            tool    = nil
            (caller_locations(1) || []).each do |location|
                path = location.path.to_s
                agent ||= markers.any? { |marker| path.include?(marker) }
                if agent && tool.nil?
                    match = location.label.to_s.match(NA_HANDLER_LABEL)
                    tool = match[1] if match
                end
                break if agent && tool
            end
            { 'by' => agent ? 'agent' : 'user', 'tool' => tool }
        rescue StandardError => error
            Na__AgentOutliner::Na__DebugTools.Na__Debug__Warn("Reading the call stack failed: #{error.message}")
            { 'by' => 'user', 'tool' => nil }
        end
        # ---------------------------------------------------------------

        # FUNCTION | The MCP Activity Log's Newest Agent Call (nil without the MCP)
        # ------------------------------------------------------------
        # 0.1.10: the bridge's own lines (bridge_start, bridge_stop, reload, a
        # setting) and the pings every MCP server sends to find its windows are
        # not an agent calling: Adam's 13:58 Send read "last call 13:57:24
        # (bridge_start)" while no agent was working.
        def self.Na__Actor__LastMcpActivity
            return nil unless defined?(::Na__SketchUpMcp::Na__ActivityLog) &&
                              ::Na__SketchUpMcp::Na__ActivityLog.respond_to?(:Na__ActivityLog__Entries)

            ::Na__SketchUpMcp::Na__ActivityLog.Na__ActivityLog__Entries.find { |entry| !NA_NOT_AGENT_CALLS.include?(entry['tool'].to_s) }
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Seconds Since an Activity Log Time ('HH:MM:SS', today), nil if unreadable
        # ------------------------------------------------------------
        def self.Na__Actor__SecondsAgo(clock, now = Time.now)
            match = clock.to_s.match(/\A(\d{1,2}):(\d{2}):(\d{2})\z/)
            return nil unless match

            at = Time.new(now.year, now.month, now.day, match[1].to_i, match[2].to_i, match[3].to_i)
            seconds = now - at
            seconds += 86_400 if seconds < -60                                         # <-- Logged before midnight
            [seconds, 0].max
        rescue ArgumentError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is the Na SketchUp MCP Loaded, and Which Version?
        # ------------------------------------------------------------
        def self.Na__Actor__McpStatus
            loaded = defined?(::Na__SketchUpMcp) ? true : false
            version = nil
            if loaded && defined?(::Na__SketchUpMcp::Na__ConfigLoader) &&
               ::Na__SketchUpMcp::Na__ConfigLoader.respond_to?(:Na__ConfigLoader__Get)
                version = ::Na__SketchUpMcp::Na__ConfigLoader.Na__ConfigLoader__Get('metadata', 'bridge_version', nil)
            end
            running = false
            if loaded && defined?(::Na__SketchUpMcp::Na__SocketServer) &&
               ::Na__SketchUpMcp::Na__SocketServer.respond_to?(:Na__SocketServer__Running)
                running = ::Na__SketchUpMcp::Na__SocketServer.Na__SocketServer__Running ? true : false
            end
            seam = loaded && defined?(::Na__SketchUpMcp::Na__Handlers__AgentOutliner) ? true : false
            { 'loaded' => loaded, 'version' => version.to_s, 'running' => running, 'tools' => seam, 'last' => self.Na__Actor__LastMcpActivity }
        rescue StandardError => error
            { 'loaded' => false, 'version' => '', 'running' => false, 'tools' => false, 'last' => nil, 'error' => error.message }
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Helpers
# -----------------------------------------------------------------------------

        def self.na_markers
            markers = Na__AgentOutliner::Na__ConfigStore.Na__Config__Engine('agent_stack_markers', ['Na__SketchUpMcp__Modules__'])
            Array(markers).map(&:to_s).reject(&:empty?)
        end

        # Holds an answer for the rest of this tick and books ONE timer to let it
        # go. A clearing timer booked over NA_TICK_LOST_S ago that never ran is
        # taken as lost and booked again (0.1.11).
        def self.na_hold_tick(answer)
            now = self.na_clock
            @na_tick    = answer
            @na_tick_at = now
            if !@na_tick_timer || (now - @na_tick_timer_at.to_f) > NA_TICK_LOST_S
                @na_tick_timer    = true
                @na_tick_timer_at = now
                UI.start_timer(0, false) do
                    Na__AgentOutliner::Na__ActorDetect.na_clear_tick
                end
            end
            answer
        end

        def self.na_clear_tick
            @na_tick       = nil
            @na_tick_timer = false
        end

        def self.na_clock
            Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

# endregion -------------------------------------------------------------------

    end # module Na__ActorDetect
end # module Na__AgentOutliner

# =============================================================================
# END OF FILE
# =============================================================================
