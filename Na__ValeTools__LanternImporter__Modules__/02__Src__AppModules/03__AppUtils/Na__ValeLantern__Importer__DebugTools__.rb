# =============================================================================
# VALE LANTERN IMPORTER - DEBUG AND REPORTING TOOLS
# =============================================================================
#
# FILE       : Na__ValeLantern__Importer__DebugTools__.rb
# NAMESPACE  : Na__ValeLantern::Na__Importer
# MODULE     : Na__DebugTools
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Console reporting for the import, plus the running tally of what
#              was built and what was refused.
#
# DESCRIPTION:
# - An import either produces a lantern or it does not, and when it does not the
#   Ruby console is the only place anyone will look. Every module reports
#   through here so the output reads as one report rather than as scattered puts
#   calls in six different voices.
# - The tally is what the summary at the end is built from. A part that fails to
#   build is counted and named rather than raised, because one bad prism out of
#   four hundred should not cost the other three hundred and ninety nine.
#
# NAMING CONVENTION:
# - Importer namespace Na__Importer / na_ prefixes.
#
# =============================================================================

module Na__ValeLantern
    module Na__Importer
        module Na__DebugTools

# -----------------------------------------------------------------------------
# REGION | Module State
# -----------------------------------------------------------------------------

            @na_verbose  = false                                                                    # <-- Geometry-level chatter, off unless asked for
            @na_failures = []                                                                       # <-- Named part failures, reported at the end
            @na_counts   = {}                                                                       # <-- What was built, by kind

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Verbosity — Public API
# -----------------------------------------------------------------------------

            # FUNCTION | Turn per-part geometry reporting on or off
            # ------------------------------------------------------------
            def self.na_set_verbose(state)
                @na_verbose = (state == true)
            end
            # ---------------------------------------------------------------

            # FUNCTION | Whether per-part reporting is on
            # ------------------------------------------------------------
            def self.na_verbose?
                @na_verbose == true
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Reporting — Public API
# -----------------------------------------------------------------------------

            # FUNCTION | Report a headline step
            # ------------------------------------------------------------
            def self.na_info(message)
                puts "[Vale Lantern] #{message}"
            end
            # ---------------------------------------------------------------

            # FUNCTION | Report a per-part detail, only when verbose
            # ------------------------------------------------------------
            def self.na_detail(message)
                puts "[Vale Lantern]   #{message}" if @na_verbose
            end
            # ---------------------------------------------------------------

            # FUNCTION | Report something the import worked around
            # ------------------------------------------------------------
            def self.na_warn(message)
                puts "[Vale Lantern] WARNING: #{message}"
            end
            # ---------------------------------------------------------------

            # FUNCTION | Report something the import could not do at all
            # ------------------------------------------------------------
            def self.na_error(message)
                puts "[Vale Lantern] ERROR: #{message}"
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Tally — Public API
# -----------------------------------------------------------------------------

            # FUNCTION | Reset the tally at the start of an import
            # ------------------------------------------------------------
            def self.na_reset_tally
                @na_failures = []
                @na_counts   = {}
            end
            # ---------------------------------------------------------------

            # FUNCTION | Count one successfully built thing
            # ------------------------------------------------------------
            def self.na_count(kind)
                @na_counts[kind] = (@na_counts[kind] || 0) + 1
            end
            # ---------------------------------------------------------------

            # FUNCTION | Record one named part that could not be built
            # ------------------------------------------------------------
            def self.na_record_failure(part_name, reason)
                @na_failures << { :Name => part_name.to_s, :Reason => reason.to_s }
            end
            # ---------------------------------------------------------------

            # FUNCTION | How many parts failed
            # ------------------------------------------------------------
            def self.na_failure_count
                @na_failures.length
            end
            # ---------------------------------------------------------------

            # FUNCTION | Print the closing report for an import
            # ------------------------------------------------------------
            # The failures are listed in full rather than summarised: a run that
            # dropped six parts is a run somebody has to go and look at, and the
            # names are what tells them where.
            def self.na_report_summary(expected_part_count)
                na_info('---------------------------------------------')
                @na_counts.keys.sort.each do |kind|
                    na_info("  #{kind}: #{@na_counts[kind]}")
                end

                built = @na_counts.values.inject(0) { |sum, value| sum + value }
                na_info("  Total built: #{built} of #{expected_part_count} in the payload")

                if @na_failures.empty?
                    na_info('  No parts refused.')
                else
                    na_warn("#{@na_failures.length} part(s) refused:")
                    @na_failures.each do |failure|
                        na_warn("    #{failure[:Name]} - #{failure[:Reason]}")
                    end
                end
                na_info('---------------------------------------------')
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

        end
    end
end
