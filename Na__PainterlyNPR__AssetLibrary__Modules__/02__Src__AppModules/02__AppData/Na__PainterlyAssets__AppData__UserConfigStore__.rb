# =============================================================================
# NA PAINTERLYNPR ASSETS - APP DATA - USER CONFIG STORE
# =============================================================================
#
# FILE       : Na__PainterlyAssets__AppData__UserConfigStore__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__UserConfigStore
# PURPOSE    : USER CONFIG layer - per-user, per-PC preferences in
#              91__UserConfig__LocalOnly/ (git-ignored): the PainterlyNPR folder
#              when it is not where the defaults look, a chosen python.exe, the
#              picture toggle and the last tab. Small, readable JSON with a
#              schema and version so a later version can migrate it.
# CREATED    : 30-Oct-2026
#
# NOT STORED HERE: anything about an asset. Assets are PainterlyNPR's files;
# a placed copy carries its own Id in the model (Na__PainterlyAssets__Asset).
#
# =============================================================================

module Na__PainterlyAssets
    module Na__UserConfigStore

    # -------------------------------------------------------------------------
    # REGION | Schema
    # -------------------------------------------------------------------------

        NA_SCHEMA         = 'Na__PainterlyAssets__UserConfig'.freeze unless defined?(NA_SCHEMA)
        NA_SCHEMA_VERSION = 1                                          unless defined?(NA_SCHEMA_VERSION)

        @na_data = nil unless defined?(@na_data)

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        def self.Na__UserConfig__Get(section, key, fallback = nil)
            node  = self.na_data[section.to_s]
            value = node.is_a?(Hash) ? node[key.to_s] : nil
            value.nil? ? fallback : value
        end

        # A nil value removes the key, so "use the default again" leaves no
        # stale override behind.
        def self.Na__UserConfig__Set(section, key, value)
            data = self.na_data
            data[section.to_s] = {} unless data[section.to_s].is_a?(Hash)
            if value.nil?
                data[section.to_s].delete(key.to_s)
            else
                data[section.to_s][key.to_s] = value
            end
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
            @na_data ||= self.na_migrate(Na__SafeFileWriter.Na__SafeFile__ReadJson(Na__PainterlyAssets::NA_USER_CONFIG_FILE))
        end

        # A file from a newer plugin version is left untouched on disk and
        # ignored in memory rather than downgraded.
        def self.na_migrate(raw)
            fresh = { 'schema' => NA_SCHEMA, 'schemaVersion' => NA_SCHEMA_VERSION }
            return fresh unless raw.is_a?(Hash) && raw['schema'] == NA_SCHEMA
            return fresh if raw['schemaVersion'].to_i > NA_SCHEMA_VERSION
            raw.merge('schemaVersion' => NA_SCHEMA_VERSION)
        end

        def self.na_write(data)
            Na__SafeFileWriter.Na__SafeFile__WriteJson(Na__PainterlyAssets::NA_USER_CONFIG_FILE, data, 4)
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('User config could not be saved.', error)
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
