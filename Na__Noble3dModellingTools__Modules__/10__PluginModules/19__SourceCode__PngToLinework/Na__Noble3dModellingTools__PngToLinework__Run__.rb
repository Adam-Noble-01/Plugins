# =============================================================================
# NA NOBLE3D MODELLING TOOLS - PNG TO LINEWORK - RUN ENTRYPOINT
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__PngToLinework__Run__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__PngToLinework
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Public execution entrypoint for the PNG To Linework tool.
# CREATED    : 2026
#
# WORKFLOW:
# 1. Prompt the user to select a PNG file via the OS file picker.
# 2. Validate the PNG header and confirm a proper alpha channel exists.
# 3. Open the trace dialog and push the image as a base64 data URI.
# 4. The dialog traces the image to polylines with a live SVG preview.
# 5. On "Create & Place" the polylines become a component of edges which is
#    placed with the crosshair / 5mm-snap placement tool.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__PngToLinework

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_PNG_TO_LINEWORK__TITLE       = 'Na Noble3d - PNG To Linework'.freeze
        NA_PNG_TO_LINEWORK__FILE_FILTER = 'PNG Files|*.png||'.freeze
        NA_PNG_TO_LINEWORK__PREFS_KEY   = 'Na__Noble3dModellingTools__PngToLinework'.freeze
        NA_PNG_TO_LINEWORK__MAX_BYTES   = 25 * 1024 * 1024                    # <-- 25MB guard against huge data-URI pushes
        NA_PNG_SIGNATURE                = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A].pack('C*').freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Entry Point
# -----------------------------------------------------------------------------

        # FUNCTION | Run the PNG To Linework Workflow
        # ------------------------------------------------------------
        def self.Na__PngToLinework__Run
            model = Sketchup.active_model
            return na_result(false, 'No active model available.') unless model

            image_payload = self.Na__PngToLinework__PickAndValidatePng
            return na_result(false, 'PNG selection cancelled.') unless image_payload

            Na__PngToLinework__DialogManager.Na__PngToLinework__DialogManager__ShowDialog(image_payload)
            na_result(true, 'PNG To Linework dialog opened.')
        rescue => error
            message = "PNG To Linework error: #{error.class}: #{error.message}"
            puts "[Na__PngToLinework] #{message}"
            puts error.backtrace.first(8).join("\n") if error.backtrace
            UI.messagebox(message)
            na_result(false, message)
        end
        # ------------------------------------------------------------

        # FUNCTION | Pick a PNG File, Validate Alpha, and Build the JS Payload
        # ------------------------------------------------------------
        def self.Na__PngToLinework__PickAndValidatePng
            default_dir = Sketchup.read_default(NA_PNG_TO_LINEWORK__PREFS_KEY, 'last_dir', '')
            file_path   = UI.openpanel('Select PNG File to Trace', default_dir, NA_PNG_TO_LINEWORK__FILE_FILTER)
            return nil unless file_path
            unless File.file?(file_path)
                UI.messagebox('The selected file could not be found.')
                return nil
            end

            if File.size(file_path) > NA_PNG_TO_LINEWORK__MAX_BYTES
                UI.messagebox("This PNG is larger than 25MB.\nPlease use a smaller export of the image.")
                return nil
            end

            png_bytes = File.binread(file_path)
            header    = na_parse_png_header(png_bytes)

            unless header
                UI.messagebox('This file is not a valid PNG.')
                return nil
            end

            unless header[:has_alpha]
                UI.messagebox(
                    "This PNG has no alpha channel (no transparent background).\n\n" \
                    "PNG To Linework traces the transparent background boundary, so the\n" \
                    "image must be a proper transparent-background PNG export."
                )
                return nil
            end

            Sketchup.write_default(NA_PNG_TO_LINEWORK__PREFS_KEY, 'last_dir', File.dirname(file_path))

            {
                file_name:    File.basename(file_path),
                pixel_width:  header[:width],
                pixel_height: header[:height],
                data_uri:     "data:image/png;base64,#{[png_bytes].pack('m0')}"
            }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | PNG Header Validation
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Parse PNG Signature, IHDR, and Alpha Capability
        # ------------------------------------------------------------
        def self.na_parse_png_header(png_bytes)
            return nil unless png_bytes && png_bytes.bytesize > 33
            return nil unless png_bytes[0, 8] == NA_PNG_SIGNATURE

            ihdr_length = png_bytes[8, 4].unpack1('N')
            ihdr_type   = png_bytes[12, 4]
            return nil unless ihdr_type == 'IHDR' && ihdr_length >= 13

            width      = png_bytes[16, 4].unpack1('N')
            height     = png_bytes[20, 4].unpack1('N')
            color_type = png_bytes[25, 1].unpack1('C')
            return nil if width.zero? || height.zero?

            has_alpha = [4, 6].include?(color_type) || na_png_has_trns_chunk?(png_bytes)

            { width: width, height: height, color_type: color_type, has_alpha: has_alpha }
        rescue StandardError
            nil
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Scan PNG Chunks for a tRNS Transparency Chunk
        # ------------------------------------------------------------
        def self.na_png_has_trns_chunk?(png_bytes)
            offset = 8
            while offset + 8 <= png_bytes.bytesize
                chunk_length = png_bytes[offset, 4].unpack1('N')
                chunk_type   = png_bytes[offset + 4, 4]
                return true  if chunk_type == 'tRNS'
                return false if chunk_type == 'IDAT' || chunk_type == 'IEND'  # <-- tRNS must precede IDAT per PNG spec

                offset += 12 + chunk_length
            end
            false
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Result Helper
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Build Standard Result Hash
        # ------------------------------------------------------------
        def self.na_result(success_flag, message_text)
            { success: !!success_flag, message: message_text.to_s }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__PngToLinework
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
