# =============================================================================
# NA PAINTERLYNPR ASSETS - APP DATA - CONFIG LOADER
# =============================================================================
#
# FILE       : Na__PainterlyAssets__AppData__ConfigLoader__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__ConfigLoader
# PURPOSE    : Reads the PLUGIN DEFAULT CONFIG (committed, read-only) and
#              answers nested lookups. Per-PC values are a separate layer
#              (Na__UserConfigStore); the asset library's own rules are a third
#              layer that belongs to PainterlyNPR (Na__Register reads them).
# CREATED    : 30-Oct-2026
#
# =============================================================================

module Na__PainterlyAssets
    module Na__ConfigLoader

    # -------------------------------------------------------------------------
    # REGION | State
    # -------------------------------------------------------------------------

        NA_DEFAULTS_FILE = File.join(__dir__, 'Na__PainterlyAssets__AppData__AppConfig__Defaults__.json').freeze unless defined?(NA_DEFAULTS_FILE)

        @na_defaults = nil unless defined?(@na_defaults)

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        def self.Na__Config__Defaults
            @na_defaults ||= self.na_read_defaults
        end

        def self.Na__Config__Get(*keys)
            keys.reduce(self.Na__Config__Defaults) do |node, key|
                node.is_a?(Hash) ? node[key.to_s] : nil
            end
        end

        def self.Na__Config__GetOr(fallback, *keys)
            value = self.Na__Config__Get(*keys)
            value.nil? ? fallback : value
        end

        # Hot reload calls this so edits to the defaults JSON take effect.
        def self.Na__Config__ClearCache
            @na_defaults = nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals
    # -------------------------------------------------------------------------

        def self.na_read_defaults
            parsed = JSON.parse(File.read(NA_DEFAULTS_FILE, encoding: 'UTF-8'))
            parsed.is_a?(Hash) ? parsed : {}
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('Plugin default config could not be read. Built-in fallbacks are in use.', error)
            {}
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
