# =============================================================================
# VALE LANTERN IMPORTER - PAYLOAD READER
# =============================================================================
#
# FILE       : Na__ValeLantern__Importer__PayloadReader__.rb
# NAMESPACE  : Na__ValeLantern::Na__Importer
# MODULE     : Na__PayloadReader
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Read a build payload off disk and satisfy itself the file is one
#              of ours before a single face is built.
#
# DESCRIPTION:
# - Reads UTF-8 JSON, parses it, and checks the schema stamp, the units and the
#   shape of the Model block.
# - Refuses rather than repairs. A file that fails a check here has come from
#   somewhere unexpected, and building three quarters of a lantern out of it is
#   worse than building none.
#
# -----------------------------------------------------------------------------
#
# THE VERSION RULE:
#
# The payload carries SchemaVersion as MAJOR.MINOR.PATCH. This importer refuses
# a MAJOR it was not written against, and accepts any MINOR or PATCH.
#
# That split is the whole point of the numbering. A new part Kind or a new
# optional field is a MINOR bump: an older importer ignores what it does not
# recognise and still builds a correct - if slightly less complete - lantern,
# which is far better than refusing to open the file at all. A field that
# CHANGES MEANING is a MAJOR bump, and there an older importer would build
# something confidently wrong, so it must not try.
#
# NAMING CONVENTION:
# - Importer namespace Na__Importer / na_ prefixes.
#
# =============================================================================

require 'sketchup.rb'
require 'json'

module Na__ValeLantern
    module Na__Importer
        module Na__PayloadReader

# -----------------------------------------------------------------------------
# REGION | Module References and Contract Constants
# -----------------------------------------------------------------------------

            DebugTools = Na__ValeLantern::Na__Importer::Na__DebugTools

            NA_EXPECTED_SCHEMA        = 'VghLantern__SketchUpExport__Payload'.freeze
            NA_SUPPORTED_MAJOR        = 1                                                           # <-- Raise only when a field changes meaning
            NA_EXPECTED_UNITS         = 'mm'.freeze
            NA_REQUIRED_MODEL_KEYS    = %w[RootGroupName Tags Materials Assemblies].freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | File Reading — Public API
# -----------------------------------------------------------------------------

            # FUNCTION | Read and validate one payload file
            # ------------------------------------------------------------
            # @param file_path [String] Absolute path to the JSON payload
            # @return [Hash, nil] The parsed payload, or nil with the reason reported
            def self.na_read_payload(file_path)
                unless file_path && File.exist?(file_path)
                    DebugTools.na_error("File not found: #{file_path}")
                    return nil
                end

                raw = na_read_text(file_path)
                return nil if raw.nil?

                payload = na_parse_json(raw, file_path)
                return nil if payload.nil?

                return nil unless na_payload_is_valid?(payload, file_path)

                na_report_header(payload, file_path)
                payload
            end
            # ---------------------------------------------------------------

            # FUNCTION | How many parts the payload says it carries
            # ------------------------------------------------------------
            # Read from the Summary rather than counted, so the closing report
            # compares what was built against what the EXPORTER thought it sent.
            # The two disagreeing is exactly the failure worth surfacing.
            def self.na_expected_part_count(payload)
                summary = payload['Summary']
                return 0 unless summary.is_a?(Hash)
                summary['TotalPartCount'].to_i
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal — Reading and Parsing
# -----------------------------------------------------------------------------

            # HELPER FUNCTION | Read a file as UTF-8, stripping any byte order mark
            # ------------------------------------------------------------
            # A BOM is invisible in an editor and makes JSON.parse fail on the
            # very first character with a message that names no cause at all.
            def self.na_read_text(file_path)
                text = File.read(file_path, :encoding => 'UTF-8')
                text = text[1..-1] if !text.empty? && text[0].ord == 0xFEFF                          # <-- Tested by codepoint; a literal BOM in this source would be invisible too
                text
            rescue StandardError => e
                DebugTools.na_error("Could not read the file (#{e.class}): #{e.message}")
                nil
            end
            private_class_method :na_read_text

            # HELPER FUNCTION | Parse the JSON, reporting where it broke
            # ------------------------------------------------------------
            def self.na_parse_json(raw_text, file_path)
                JSON.parse(raw_text)
            rescue JSON::ParserError => e
                DebugTools.na_error("#{File.basename(file_path)} is not valid JSON: #{e.message}")
                nil
            rescue StandardError => e
                DebugTools.na_error("Could not parse the file (#{e.class}): #{e.message}")
                nil
            end
            private_class_method :na_parse_json

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal — Validation
# -----------------------------------------------------------------------------

            # HELPER FUNCTION | Check the schema stamp, the units and the Model block
            # ------------------------------------------------------------
            def self.na_payload_is_valid?(payload, file_path)
                unless payload.is_a?(Hash)
                    DebugTools.na_error("#{File.basename(file_path)} is not a payload object.")
                    return false
                end

                meta = payload['Meta']
                unless meta.is_a?(Hash)
                    DebugTools.na_error('The file carries no Meta block - this is not a Vale lantern build file.')
                    return false
                end

                unless meta['Schema'] == NA_EXPECTED_SCHEMA
                    DebugTools.na_error("Wrong schema: expected '#{NA_EXPECTED_SCHEMA}', found '#{meta['Schema']}'.")
                    return false
                end

                return false unless na_version_is_supported?(meta['SchemaVersion'])

                unless meta['Units'].to_s == NA_EXPECTED_UNITS
                    DebugTools.na_error("Payload units are '#{meta['Units']}'; this importer only reads '#{NA_EXPECTED_UNITS}'.")
                    return false
                end

                na_model_block_is_valid?(payload['Model'])
            end
            private_class_method :na_payload_is_valid?

            # HELPER FUNCTION | Accept any minor of the supported major
            # ------------------------------------------------------------
            def self.na_version_is_supported?(version_string)
                version = version_string.to_s
                if version.empty?
                    DebugTools.na_error('The payload carries no SchemaVersion.')
                    return false
                end

                major = version.split('.').first.to_i
                if major != NA_SUPPORTED_MAJOR
                    DebugTools.na_error(
                        "Payload schema #{version} is not readable by this importer, which was written for major version #{NA_SUPPORTED_MAJOR}. " \
                        'Update the Vale Lantern Importer plugin.')
                    return false
                end

                true
            end
            private_class_method :na_version_is_supported?

            # HELPER FUNCTION | Check the Model block carries what the builders need
            # ------------------------------------------------------------
            def self.na_model_block_is_valid?(model_block)
                unless model_block.is_a?(Hash)
                    DebugTools.na_error('The payload carries no Model block.')
                    return false
                end

                missing = NA_REQUIRED_MODEL_KEYS.reject { |key| model_block.key?(key) }
                unless missing.empty?
                    DebugTools.na_error("The Model block is missing: #{missing.join(', ')}.")
                    return false
                end

                unless model_block['Assemblies'].is_a?(Array)
                    DebugTools.na_error('Model.Assemblies is not a list.')
                    return false
                end

                true
            end
            private_class_method :na_model_block_is_valid?

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal — Reporting
# -----------------------------------------------------------------------------

            # HELPER FUNCTION | Announce what is about to be built
            # ------------------------------------------------------------
            # Printed before the build rather than after, so a run that hangs or
            # crashes still leaves behind a record of which file it was reading.
            def self.na_report_header(payload, file_path)
                meta    = payload['Meta']    || {}
                project = payload['Project'] || {}
                lantern = payload['Lantern'] || {}

                DebugTools.na_info('=============================================')
                DebugTools.na_info("Vale Lantern Importer - #{File.basename(file_path)}")
                DebugTools.na_info("  Project    : #{project['Code']} #{project['Name']}")
                DebugTools.na_info("  Lantern    : #{lantern['Title']} (#{lantern['RoofForm']})")
                DebugTools.na_info("  Size       : #{lantern['WidthMm']} x #{lantern['DepthMm']} mm at #{lantern['PitchDegrees']} deg")
                DebugTools.na_info("  Exported   : #{meta['ExportedAtLocal']} by #{meta['ExportedBy']}")
                DebugTools.na_info("  App / Schema: #{meta['AppVersion']} / #{meta['SchemaVersion']}")
                DebugTools.na_info('=============================================')

                na_report_export_warnings(payload)
            end
            private_class_method :na_report_header

            # HELPER FUNCTION | Repeat the exporter's own reservations
            # ------------------------------------------------------------
            # The solver's warnings travel in the file. A lantern that exported
            # with a warning about, say, an unbuildable pane width will import
            # perfectly happily, and the console is where that has to be said.
            def self.na_report_export_warnings(payload)
                summary  = payload['Summary']
                return unless summary.is_a?(Hash)

                warnings = summary['Warnings']
                return unless warnings.is_a?(Array) && !warnings.empty?

                DebugTools.na_warn("The exporter recorded #{warnings.length} warning(s) against this lantern:")
                warnings.each { |warning| DebugTools.na_warn("    #{warning}") }
            end
            private_class_method :na_report_export_warnings

# endregion -------------------------------------------------------------------

        end
    end
end
