# =============================================================================
# NA NOBLE3D MODELLING TOOLS - PDF VECTOR IMPORTER - RUN ENTRYPOINT
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__PdfVectorImporter__Run__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__PdfVectorImporter
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Public execution entrypoint for the PDF Vector Importer tool.
# CREATED    : 2026
#
# WORKFLOW:
# 1. Prompt the user to select a PDF file.
# 2. Read and decode its page content streams.
# 3. Detect vector linework - if none exists, inform the user and stop.
# 4. Prompt for page (if multi-page), scale factor and curve smoothness.
# 5. Convert the selected page to edges, flattened to XY and centred at origin.
# 6. Report the import result.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__PdfVectorImporter

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_PDF_IMPORTER__TITLE       = 'Na Noble3d - PDF Vector Importer'.freeze
        NA_PDF_IMPORTER__FILE_FILTER = 'PDF Files|*.pdf||'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Entry Point
# -----------------------------------------------------------------------------

        # FUNCTION | Run the PDF Vector Importer Workflow
        # ------------------------------------------------------------
        def self.Na__PdfVectorImporter__Run
            model = Sketchup.active_model
            return na_result(false, 'No active model available.') unless model

            file_path = UI.openpanel('Select PDF File to Import', '', NA_PDF_IMPORTER__FILE_FILTER)
            return na_result(false, 'PDF import cancelled.') unless file_path
            unless File.file?(file_path)
                UI.messagebox('The selected file could not be found.')
                return na_result(false, 'File not found.')
            end

            Sketchup.status_text = 'Reading PDF file...'
            read_result = Na__PdfVectorImporter__PdfReader.Na__PdfVectorImporter__ReadPages(file_path)
            pages       = read_result[:pages] || []
            Sketchup.status_text = ''

            return na_report_unreadable(read_result) if pages.empty?

            pages_with_vectors = na_pages_with_vector_data(pages)
            return na_report_no_vector_data if pages_with_vectors.empty?

            params = na_prompt_import_parameters(pages.length, pages_with_vectors)
            return na_result(false, 'PDF import cancelled.') unless params

            na_import_selected_page(file_path, pages, params)
        rescue => error
            Sketchup.status_text = ''
            message = "PDF import error: #{error.class}: #{error.message}"
            puts "[Na__PdfVectorImporter] #{message}"
            puts error.backtrace.first(8).join("\n") if error.backtrace
            UI.messagebox(message)
            na_result(false, message)
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Import Orchestration
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Parse and Build Geometry for the Selected Page
        # ------------------------------------------------------------
        def self.na_import_selected_page(file_path, pages, params)
            page_index = params[:page_index]
            content    = pages[page_index]

            Sketchup.status_text = 'Converting PDF vectors...'
            parsed    = Na__PdfVectorImporter__ContentParser.Na__PdfVectorImporter__ParsePolylines(content, params[:segments])
            polylines = parsed[:polylines]
            Sketchup.status_text = ''

            if polylines.nil? || polylines.empty?
                UI.messagebox("No importable vector lines were found on page #{page_index + 1}.")
                return na_result(false, 'No vector lines on selected page.')
            end

            group_name = na_group_name_for(file_path, page_index)
            result     = Na__PdfVectorImporter__GeometryBuilder.Na__PdfVectorImporter__BuildCenteredGroup(
                polylines, params[:scale], group_name
            )

            na_report_build_result(result, page_index, pages.length, params)
            result
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Vector Detection
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Return Indices of Pages Containing Importable Vector Data
        # ------------------------------------------------------------
        def self.na_pages_with_vector_data(pages)
            indices = []
            pages.each_with_index do |content, index|
                next unless Na__PdfVectorImporter__ContentParser.Na__PdfVectorImporter__ContentHasVectorData?(content)

                parsed = Na__PdfVectorImporter__ContentParser.Na__PdfVectorImporter__ParsePolylines(content, 2)
                indices << index if parsed[:polylines] && !parsed[:polylines].empty?  # <-- Confirm painted geometry, not clip-only
            end
            indices
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | User Prompts
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Prompt for Page, Scale and Curve Smoothness
        # ------------------------------------------------------------
        def self.na_prompt_import_parameters(page_count, pages_with_vectors)
            default_steps = Na__PdfVectorImporter__ContentParser::DEFAULT_BEZIER_STEPS
            default_page  = pages_with_vectors.first + 1

            if page_count > 1
                vector_pages = pages_with_vectors.map { |index| index + 1 }.join(', ')
                prompts  = ["Page to import (1-#{page_count}):", 'Scale factor (1.0 = native PDF size):', 'Curve smoothness (segments per curve):']
                defaults = [default_page, 1.0, default_steps]
                title    = "#{NA_PDF_IMPORTER__TITLE}  |  Vector pages: #{vector_pages}"
                results  = UI.inputbox(prompts, defaults, title)
                return nil unless results

                {
                    page_index: na_clamp_int(results[0], 1, page_count) - 1,
                    scale:      na_positive_float(results[1], 1.0),
                    segments:   na_clamp_int(results[2], 2, 200)
                }
            else
                prompts  = ['Scale factor (1.0 = native PDF size):', 'Curve smoothness (segments per curve):']
                defaults = [1.0, default_steps]
                results  = UI.inputbox(prompts, defaults, NA_PDF_IMPORTER__TITLE)
                return nil unless results

                {
                    page_index: pages_with_vectors.first,
                    scale:      na_positive_float(results[0], 1.0),
                    segments:   na_clamp_int(results[1], 2, 200)
                }
            end
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Result Reporting
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Report an Unreadable or Empty PDF
        # ------------------------------------------------------------
        def self.na_report_unreadable(read_result)
            message = read_result[:message]
            message = 'No readable content was found in this PDF.' if message.nil? || message.empty? || message == 'OK'
            UI.messagebox("No vector data could be read from this PDF.\n\n#{message}")
            na_result(false, 'No readable pages.')
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Report a PDF With No Vector Linework
        # ------------------------------------------------------------
        def self.na_report_no_vector_data
            UI.messagebox(
                "No vector data was found in this PDF.\n\n" \
                "The file appears to contain no vector linework. It may be a scanned or image-only PDF, " \
                "contain only text, or use an unsupported encoding (such as encryption or LZW compression)."
            )
            na_result(false, 'No vector data found.')
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Report the Geometry Build Result
        # ------------------------------------------------------------
        def self.na_report_build_result(result, page_index, page_count, params)
            if result[:success]
                puts "[Na__PdfVectorImporter] Imported page #{page_index + 1}/#{page_count} | " \
                     "edges: #{result[:edge_count]} | paths: #{result[:path_count]} | " \
                     "scale: #{params[:scale]} | segments: #{params[:segments]}"
                UI.messagebox(
                    "PDF vector import complete.\n\n" \
                    "Page: #{page_index + 1} of #{page_count}\n" \
                    "Edges created: #{result[:edge_count]}\n" \
                    "Paths imported: #{result[:path_count]}\n\n" \
                    "Linework was flattened to the XY plane and centred on the origin."
                )
            else
                UI.messagebox("PDF import failed.\n\n#{result[:message]}")
            end
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Value Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Clamp a Value to an Integer Range
        # ------------------------------------------------------------
        def self.na_clamp_int(value, minimum, maximum)
            integer_value = value.to_i
            integer_value = minimum if integer_value < minimum
            integer_value = maximum if integer_value > maximum
            integer_value
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Return a Positive Float or a Fallback
        # ------------------------------------------------------------
        def self.na_positive_float(value, fallback)
            float_value = value.to_f
            float_value > 0.0 ? float_value : fallback
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build a Group Name from the File and Page
        # ------------------------------------------------------------
        def self.na_group_name_for(file_path, page_index)
            base_name = File.basename(file_path, '.*')
            "Na__PdfImport__#{base_name}__p#{page_index + 1}"
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build Standard Result Hash
        # ------------------------------------------------------------
        def self.na_result(success_flag, message_text)
            { success: !!success_flag, message: message_text.to_s }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__PdfVectorImporter
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
