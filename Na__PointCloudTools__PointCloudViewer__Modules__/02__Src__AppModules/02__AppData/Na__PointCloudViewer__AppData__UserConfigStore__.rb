# =============================================================================
# NA POINT CLOUD VIEWER - APP DATA - USER CONFIG STORE
# =============================================================================
#
# FILE       : Na__PointCloudViewer__AppData__UserConfigStore__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__UserConfigStore
# PURPOSE    : USER CONFIG layer - per-user, per-PC preferences in
#              91__UserConfig__LocalOnly/ (git-ignored). Small, readable JSON
#              with a schema + version so later versions can migrate it.
#
# NOT STORED HERE: anything a model needs to display its cloud correctly on
# another computer (clip box, clip scenes, later transform and units). That is
# the MODEL layer and travels with the .skp.
#
# =============================================================================

module Na__PointCloudViewer
    module Na__UserConfigStore

    # -------------------------------------------------------------------------
    # REGION | Schema
    # -------------------------------------------------------------------------

        NA_SCHEMA         = 'Na__PointCloudViewer__UserConfig'.freeze
        NA_SCHEMA_VERSION = 3

        @na_data = nil unless defined?(@na_data)

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        def self.Na__UserConfig__Get(section, key, fallback = nil)
            node = self.na_data[section.to_s]
            value = node.is_a?(Hash) ? node[key.to_s] : nil
            value.nil? ? fallback : value
        end

        def self.Na__UserConfig__Set(section, key, value)
            data = self.na_data
            data[section.to_s] = {} unless data[section.to_s].is_a?(Hash)
            data[section.to_s][key.to_s] = value
            self.na_write(data)
            value
        end

        def self.Na__UserConfig__ClearCache
            @na_data = nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals
    # -------------------------------------------------------------------------

        def self.na_data
            @na_data ||= self.na_migrate(Na__SafeFileWriter.Na__SafeFile__ReadJson(Na__AssetResolver.Na__Paths__UserConfigFile))
        end

        # A file from a newer plugin version is left untouched on disk and
        # ignored in memory rather than downgraded.
        #   v1/v2 -> v3 (0.4.0): drop the 'dev' section. It held the benchmark-era
        #   render choices and visual-check notes, which no longer exist.
        def self.na_migrate(raw)
            fresh = { 'schema' => NA_SCHEMA, 'schemaVersion' => NA_SCHEMA_VERSION }
            return fresh unless raw.is_a?(Hash) && raw['schema'] == NA_SCHEMA
            return fresh if raw['schemaVersion'].to_i > NA_SCHEMA_VERSION
            raw.reject { |key, _| key == 'dev' }.merge('schemaVersion' => NA_SCHEMA_VERSION)
        end

        def self.na_write(data)
            Na__SafeFileWriter.Na__SafeFile__WriteJson(Na__AssetResolver.Na__Paths__UserConfigFile, data)
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('User config could not be saved.', error)
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
