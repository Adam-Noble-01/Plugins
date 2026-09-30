# =============================================================================
# NA SKETCHUP MCP - HANDLERS - RUBY EVAL
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__Ruby__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__Ruby
# PURPOSE    : ruby_eval: run Ruby inside SketchUp for anything the dedicated
#              tools do not cover
# CREATED    : 2026
#
# THE ESCAPE HATCH, WITH RAILS:
# - One undo step: by default the code runs inside "MCP: <operation_name>" and
#   any exception aborts it, so a failed script leaves the model untouched.
# - Output captured: puts/p/print and warn are returned, not lost in the Ruby
#   Console.
# - No modal hangs: UI.messagebox / inputbox / openpanel / savepanel /
#   select_directory are answered automatically while the code runs (a modal
#   dialog would block this bridge until someone clicked it). The call says so.
# - SyntaxError and exit are caught (they are not StandardErrors).
# - Code runs on SketchUp's main thread and cannot be interrupted; loops must
#   end on their own.
# - Locals ready to use: model, entities (active), selection, view.
# - The Python server lints the code against the SketchUp API index before it
#   gets here and returns unknown method names as warnings (ruby_api_lookup).
# - Disabled when "Allow Ruby eval" is off, and in read-only mode.
#
# =============================================================================

require 'stringio'

module Na__SketchUpMcp
    module Na__Handlers__Ruby

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_EVAL_FILENAME = '(mcp ruby_eval)'
        NA_MAX_CODE_CHARS = 200_000

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | ruby_eval
# -----------------------------------------------------------------------------

        def self.Na__Handlers__Ruby__Eval(params, ctx)
            code = Na__Params.Na__Params__String(params, 'code', nil, required: true)
            if code.length > NA_MAX_CODE_CHARS
                raise Na__McpError.new('invalid_params', "code is #{code.length} characters; the limit is #{NA_MAX_CODE_CHARS}.", 'Split the work into several calls.')
            end

            max_chars = Na__Params.Na__Params__Integer(params, 'max_result_chars',
                                                       Na__ConfigLoader.Na__ConfigLoader__Get('defaults', 'eval_max_result_chars', 20_000).to_i, min: 100, max: 200_000)
            transaction = Na__Params.Na__Params__Boolean(params, 'transaction', true)
            operation_name = "MCP: #{Na__Params.Na__Params__String(params, 'operation_name', 'Ruby')}"
            stdout = StringIO.new
            stderr = StringIO.new
            result = nil

            run = lambda do
                na_with_captured_io(stdout, stderr) do
                    na_with_modal_guards(ctx) do
                        result = na_binding(ctx[:model]).eval(code, NA_EVAL_FILENAME, 1)
                    end
                end
            end

            begin
                transaction ? Na__CommandRouter.Na__CommandRouter__WithOperation(ctx, operation_name) { run.call } : run.call
            rescue SystemExit
                raise Na__McpError.new('eval_error', 'The code called exit; that is not allowed inside SketchUp.', 'Return a value instead.',
                                       { 'stdout' => na_trim(stdout.string, max_chars) })
            rescue ScriptError, StandardError => error
                raise Na__McpError.new('eval_error', "#{error.class}: #{error.message}",
                                       transaction ? 'The operation was aborted; the model is unchanged.' : 'transaction was false, so changes made before the error remain (Ctrl+Z each one).',
                                       { 'backtrace' => na_eval_backtrace(error), 'stdout' => na_trim(stdout.string, max_chars), 'stderr' => na_trim(stderr.string, max_chars) })
            end

            na_result_hash(result, stdout, stderr, max_chars)
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Evaluation Environment
# -----------------------------------------------------------------------------

        # A fresh top-level binding each call, with the usual locals.
        def self.na_binding(model)
            context = TOPLEVEL_BINDING.dup
            context.local_variable_set(:model, model)
            context.local_variable_set(:entities, model.active_entities)
            context.local_variable_set(:selection, model.selection)
            context.local_variable_set(:view, model.active_view)
            context
        end

        def self.na_with_captured_io(stdout, stderr)
            original_stdout = $stdout
            original_stderr = $stderr
            $stdout = stdout
            $stderr = stderr
            yield
        ensure
            $stdout = original_stdout
            $stderr = original_stderr
        end

        # Modal UI answered automatically for the duration of the eval.
        def self.na_with_modal_guards(ctx)
            answers = { messagebox: IDOK, inputbox: false, openpanel: nil, savepanel: nil, select_directory: nil }
            originals = {}
            answers.each do |name, answer|
                next unless UI.respond_to?(name)

                originals[name] = UI.method(name)
                UI.define_singleton_method(name) do |*_arguments|
                    ctx[:warnings] << "UI.#{name} was called during ruby_eval and answered #{answer.inspect} automatically (no dialog shown)."
                    answer
                end
            end
            yield
        ensure
            originals.each { |name, original| UI.define_singleton_method(name, original) }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Result Shaping
# -----------------------------------------------------------------------------

        def self.na_result_hash(result, stdout, stderr, max_chars)
            hash = {
                'result'       => na_trim(result.inspect, max_chars),
                'result_class' => result.class.name
            }
            hash['value'] = Na__Serializer.Na__Serializer__JsonSafe(result, max_chars) if na_plain_value?(result)
            hash['stdout'] = na_trim(stdout.string, max_chars) unless stdout.string.empty?
            hash['stderr'] = na_trim(stderr.string, max_chars) unless stderr.string.empty?
            hash
        end

        def self.na_plain_value?(value, depth = 0)
            return false if depth > 6

            case value
            when nil, true, false, Numeric, String, Symbol then true
            when Array then value.length <= 5000 && value.all? { |item| na_plain_value?(item, depth + 1) }
            when Hash then value.length <= 5000 && value.all? { |key, item| (key.is_a?(String) || key.is_a?(Symbol)) && na_plain_value?(item, depth + 1) }
            else false
            end
        end

        def self.na_trim(text, max_chars)
            text = text.to_s
            return text if text.length <= max_chars

            text[0, max_chars] + " ...[#{text.length - max_chars} more characters]"
        end

        def self.na_eval_backtrace(error)
            lines = (error.backtrace || []).select { |line| line.include?(NA_EVAL_FILENAME) }
            lines = [error.message.lines.first.to_s.strip] if lines.empty? && error.is_a?(SyntaxError)
            lines.first(8)
        end

# endregion -------------------------------------------------------------------

    end # module Na__Handlers__Ruby
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
