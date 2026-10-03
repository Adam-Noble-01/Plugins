# =============================================================================
# NA POINT CLOUD VIEWER - APP UTILS - SAFE FILE WRITER
# =============================================================================
#
# FILE       : Na__PointCloudViewer__AppUtils__SafeFileWriter__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__SafeFileWriter
# PURPOSE    : Transactional writes: write `<target>.tmp`, then rename over the
#              target. A crash or failure leaves either the old file or no
#              file, never a half-written one. The `.napc` point cache will
#              follow the same rule.
#
# =============================================================================

module Na__PointCloudViewer
    module Na__SafeFileWriter

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        def self.Na__SafeFile__WriteJson(path, data)
            self.Na__SafeFile__WriteText(path, JSON.pretty_generate(data))
        end

        def self.Na__SafeFile__WriteText(path, text)
            FileUtils.mkdir_p(File.dirname(path))
            temp_path = "#{path}.tmp"
            File.open(temp_path, 'wb') { |file| file.write(text) }
            self.na_replace(temp_path, path)
            path
        ensure
            File.delete(temp_path) if temp_path && File.exist?(temp_path)
        end

        def self.Na__SafeFile__ReadJson(path)
            return nil unless File.exist?(path)
            parsed = JSON.parse(File.read(path, encoding: 'UTF-8'))
            parsed.is_a?(Hash) ? parsed : nil
        rescue JSON::ParserError, SystemCallError => error
            Na__DebugTools.Na__Debug__Warn("Could not read #{File.basename(path)}: #{error.message}")
            nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals
    # -------------------------------------------------------------------------

        # Windows rename refuses to replace an open/locked target on some
        # setups; fall back to delete-then-rename so the write still lands.
        def self.na_replace(temp_path, path)
            File.rename(temp_path, path)
        rescue SystemCallError
            File.delete(path) if File.exist?(path)
            File.rename(temp_path, path)
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
