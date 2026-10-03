# =============================================================================
# NA POINT CLOUD VIEWER - APP DATA - CONFIG LOADER
# =============================================================================
#
# FILE       : Na__PointCloudViewer__AppData__ConfigLoader__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__ConfigLoader
# PURPOSE    : Reads the PLUGIN DEFAULT CONFIG (committed, read-only) and
#              answers nested lookups. Per-user values are a separate layer
#              (Na__UserConfigStore); per-model state (the clip box and clip
#              scenes) is a third layer stored in the model itself.
#
# =============================================================================

module Na__PointCloudViewer
    module Na__ConfigLoader

    # -------------------------------------------------------------------------
    # REGION | State
    # -------------------------------------------------------------------------

        NA_DEFAULTS_FILE = File.join(__dir__, 'Na__PointCloudViewer__AppData__AppConfig__Defaults__.json').freeze

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
