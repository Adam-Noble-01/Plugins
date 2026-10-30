# =============================================================================
# NA PAINTERLYNPR ASSETS - VALIDATE - RUNNER
# =============================================================================
#
# FILE       : Na__PainterlyAssets__Validate__Runner__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__ValidateRunner
# PURPOSE    : Runs PainterlyNPR's `validate` (every rule, every asset) and then
#              `index` (the file the web app reads), and turns their output
#              into the dialog's report: a summary, and each warning and error
#              as its own line with its level.
# CREATED    : 30-Oct-2026
#
# DESCRIPTION:
# - The utility prints "[warning] ...", "[error]   ..." and a closing
#   "[AssetLibrary] 26 assets, 0 errors, 0 warnings." and exits 1 on any
#   error. Anything else it prints (a traceback) is shown as an error line,
#   never dropped: an unreadable run is not a clean one.
# - `index` runs even when validate found errors, as the build utility
#   itself leaves the two separate: the index holds what is valid enough to
#   list, and the report says what is not.
#
# =============================================================================

module Na__PainterlyAssets
    module Na__ValidateRunner

    # -------------------------------------------------------------------------
    # REGION | State
    # -------------------------------------------------------------------------

        @na_last = nil unless defined?(@na_last)                                                     # <-- The last report, shown again when the dialog reopens

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        # FUNCTION | Validate the Library, Then Write Its Index
        # ------------------------------------------------------------
        # @yield [Hash] the report (always, exactly once)
        def self.Na__Validate__Run(reason = nil, &on_done)
            Na__BuildUtil.Na__BuildUtil__RunChain([['validate'], ['index']]) do |results|
                report = begin
                    Na__PainterlyAssets::Na__ValidateRunner.Na__Validate__Report(results, reason)
                rescue StandardError => error
                    Na__DebugTools.Na__Debug__Error('The validation report could not be made.', error)
                    { 'ok' => false, 'summary' => "The report could not be made: #{error.message}", 'items' => [], 'index' => nil }
                end
                @na_last = report
                on_done.call(report) if on_done
            end
        end
        # ---------------------------------------------------------------

        def self.Na__Validate__Last
            @na_last
        end

        # FUNCTION | The Report From the Two Runs (pure: the offline suites read it)
        # ------------------------------------------------------------
        def self.Na__Validate__Report(results, reason = nil)
            validate = results[0]
            index    = results[1]
            items    = []
            summary  = nil

            if validate.nil? || !validate['launched']
                message = validate ? validate['error'] : 'The validator did not run.'
                return { 'ok' => false, 'ran' => false, 'reason' => reason, 'summary' => message, 'items' => [], 'index' => nil,
                         'ranAt' => Time.now.strftime('%d-%b-%Y %H:%M:%S'), 'python' => nil }
            end

            validate['lines'].each do |line|
                if line.start_with?('[warning]')
                    items << { 'level' => 'warn', 'text' => line.sub('[warning]', '').strip }
                elsif line.start_with?('[error]')
                    items << { 'level' => 'error', 'text' => line.sub('[error]', '').strip }
                elsif line.start_with?('[AssetLibrary]')
                    summary = line.sub('[AssetLibrary]', '').strip
                else
                    items << { 'level' => 'error', 'text' => line }                                     # <-- A traceback or a stray line: shown, never dropped
                end
            end
            items << { 'level' => 'error', 'text' => validate['error'] } if validate['error']

            errors   = items.count { |item| item['level'] == 'error' }
            warnings = items.count { |item| item['level'] == 'warn' }
            {
                'ok'       => validate['ok'] && errors.zero?,
                'ran'      => true,
                'reason'   => reason,
                'summary'  => summary || "The validator ended with code #{validate['exitCode'].inspect} and no summary.",
                'errors'   => errors,
                'warnings' => warnings,
                'items'    => items,
                'index'    => index ? { 'ok' => index['ok'], 'text' => (index['lines'].last || index['error']).to_s.sub('[AssetLibrary]', '').strip } : nil,
                'seconds'  => results.compact.sum { |result| result['seconds'].to_f }.round(2),             # <-- The index run is missing when validate could not start
                'ranAt'    => Time.now.strftime('%d-%b-%Y %H:%M:%S'),
                'python'   => validate['python']
            }
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
