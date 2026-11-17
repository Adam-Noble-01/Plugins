# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - OPERATION SCOPE (one undo step for a whole job)
# =============================================================================
#
# FILE       : Na__AssemblyStudio__AppCore__OperationScope__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__AppCore
# MODULE     : Na__OperationScope
# AUTHOR     : Noble Architecture
# PURPOSE    : Lets one pipeline call other pipelines and still leave ONE undo
#              step. SketchUp has no nested operations: a start_operation while
#              another is open commits the open one, so a run of twelve windows
#              built through the window pipeline was twelve undo steps.
# CREATED    : 16-Nov-2026 (V2.7.0)
#
# HOW IT WORKS
# - Every build pipeline opens, commits and aborts its undo step through
#   na_start / na_commit / na_abort instead of calling the model directly.
# - Outside an embed block they pass straight through to the model, so each
#   pipeline is one undo step with its own name, exactly as before.
# - Inside Na__OperationScope.na_embed { ... } they do nothing: the caller has
#   already opened the step, and everything built inside joins it. A failure
#   inside raises through to the caller, which aborts the whole step.
# - After each real commit the listeners registered with na_on_commit are
#   told. They only schedule work (a timer), never build in the call.
#
# RULES
# - Only the outermost caller opens the real operation (through na_start,
#   BEFORE na_embed) and only it commits or aborts.
# - Never rescue-and-continue inside an embed block: a pipeline that failed
#   has aborted nothing, so its half-built geometry is still in the open step.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'

module Na__AssemblyStudio
    module Na__AppCore
        module Na__OperationScope

# -----------------------------------------------------------------------------
# REGION | State
# -----------------------------------------------------------------------------

            @na_embed_depth      ||= 0                                           # <-- Kept through Reload Scripts
            @na_commit_listeners ||= {}                                          # <-- name => Proc, told after each real commit

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Told After a Real Commit
# -----------------------------------------------------------------------------

            # FUNCTION | Register a Listener Told After Each Real (Outermost) Commit
            # ------------------------------------------------------------
            # The Assembly Run system uses one to notice that a panel of a
            # run was rebuilt in its own tab at a size the run does not give
            # it. A listener must only SCHEDULE work (a timer): the pipeline
            # that committed is still running. Registered by name, so a
            # reload replaces it instead of adding another.
            def self.na_on_commit(name, &block)
                @na_commit_listeners[name] = block if name && block_given?
            end
            # ---------------------------------------------------------------

            # HELPER FUNCTION | Tell Every Listener; None May Break the Pipeline
            # ------------------------------------------------------------
            def self.na_tell_commit_listeners
                @na_commit_listeners.each_value do |listener|
                    begin
                        listener.call
                    rescue StandardError => e
                        puts "[Na__OperationScope] commit listener failed: #{e.message}"
                    end
                end
            end
            private_class_method :na_tell_commit_listeners
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Embedding
# -----------------------------------------------------------------------------

            # FUNCTION | Is a Caller's Operation Already Open Around This Code
            # ------------------------------------------------------------
            def self.na_embedded?
                @na_embed_depth.to_i > 0
            end
            # ---------------------------------------------------------------

            # FUNCTION | Run a Block Whose Pipelines Join the Caller's Open Step
            # ------------------------------------------------------------
            # @yield the work; every na_start / na_commit / na_abort inside is a no-op
            # @return the block's value
            def self.na_embed
                @na_embed_depth = @na_embed_depth.to_i + 1
                yield
            ensure
                @na_embed_depth = [@na_embed_depth.to_i - 1, 0].max
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - The Three Calls a Pipeline Makes
# -----------------------------------------------------------------------------

            # FUNCTION | Open an Undo Step (Unless a Caller Already Has)
            # ------------------------------------------------------------
            # Same arguments as Sketchup::Model#start_operation.
            # @return [Boolean] true when this call opened a real operation
            def self.na_start(model, name, disable_ui = true, next_transparent = false, transparent = false)
                return false if na_embedded?
                model.start_operation(name, disable_ui, next_transparent, transparent)
                true
            end
            # ---------------------------------------------------------------

            # FUNCTION | Commit the Undo Step (Unless It Is the Caller's)
            # ------------------------------------------------------------
            def self.na_commit(model)
                return false if na_embedded?
                model.commit_operation
                na_tell_commit_listeners
                true
            end
            # ---------------------------------------------------------------

            # FUNCTION | Abort the Undo Step (Unless It Is the Caller's)
            # ------------------------------------------------------------
            # Embedded, the pipeline's own raise carries the failure out to
            # the caller, whose abort removes everything built in the step.
            def self.na_abort(model)
                return false if na_embedded?
                model.abort_operation
                true
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

        end
    end
end

# =============================================================================
# END OF FILE
# =============================================================================
