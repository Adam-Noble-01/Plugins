# =============================================================================
# NA PAINTERLYNPR ASSETS - NPR VIEWPORT - USER CONFIG
# =============================================================================
#
# FILE       : Na__PainterlyAssets__NprViewport__UserConfig__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__ViewportConfig
# PURPOSE    : The NPR windows' own per-PC data file,
#              91__UserConfig__LocalOnly/Na__PainterlyAssets__UserConfig__NprViewport__.json
#              (git-ignored): whether live updates start on, and a local
#              PainterlyNPR folder to run instead of the GitHub cache while the
#              engine itself is being worked on.
# CREATED    : 01-Nov-2026
#
# NOT STORED HERE: a project's look (the engine's settings) lives with its
# cache in 92__UserProjects__ProjectCache, and the downloaded engine in
# 93__RemoteCache__CoreEngine.
#
# =============================================================================

module Na__PainterlyAssets
    module Na__ViewportConfig

    # -------------------------------------------------------------------------
    # REGION | Schema
    # -------------------------------------------------------------------------

        NA_SCHEMA         = 'Na__PainterlyAssets__UserConfig__NprViewport'.freeze unless defined?(NA_SCHEMA)
        NA_SCHEMA_VERSION = 1                                                    unless defined?(NA_SCHEMA_VERSION)
        NA_DEFAULTS       = {
            'live'   => { 'onWhenOpened' => true, 'onWhenOpenedNote' => 'Adam, 01-Nov-2026: "It should be live by default when you open it".' },
            'engine' => { 'localOverrideFolder' => '', 'localOverrideFolderNote' => 'A local Na__PainterlyNPR folder to run instead of the GitHub cache (for working on the engine itself). Empty: the cache, always.' }
        }.freeze unless defined?(NA_DEFAULTS)

        @na_data = nil unless defined?(@na_data)

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        def self.Na__ViewportConfig__Get(section, key, fallback = nil)
            node  = self.na_data[section.to_s]
            value = node.is_a?(Hash) ? node[key.to_s] : nil
            value.nil? ? fallback : value
        end

        def self.Na__ViewportConfig__Set(section, key, value)
            data = self.na_data
            data[section.to_s] = {} unless data[section.to_s].is_a?(Hash)
            data[section.to_s][key.to_s] = value
            Na__SafeFileWriter.Na__SafeFile__WriteJson(Na__PainterlyAssets::NA_VIEWPORT_CONFIG_FILE, data, 4)
            value
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('The NPR viewport config could not be saved.', error)
            value
        end

        def self.Na__ViewportConfig__ClearCache
            @na_data = nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals
    # -------------------------------------------------------------------------

        # The file is written with its defaults the first time, so the choices
        # it offers can be read (and changed) by hand.
        def self.na_data
            return @na_data if @na_data
            raw = Na__SafeFileWriter.Na__SafeFile__ReadJson(Na__PainterlyAssets::NA_VIEWPORT_CONFIG_FILE)
            if raw.is_a?(Hash) && raw['schema'] == NA_SCHEMA && raw['schemaVersion'].to_i <= NA_SCHEMA_VERSION
                @na_data = JSON.parse(JSON.generate(NA_DEFAULTS)).merge(raw) { |_k, base, mine| base.is_a?(Hash) && mine.is_a?(Hash) ? base.merge(mine) : mine }
            else
                @na_data = { 'schema' => NA_SCHEMA, 'schemaVersion' => NA_SCHEMA_VERSION }.merge(JSON.parse(JSON.generate(NA_DEFAULTS)))
                begin
                    Na__SafeFileWriter.Na__SafeFile__WriteJson(Na__PainterlyAssets::NA_VIEWPORT_CONFIG_FILE, @na_data, 4) unless raw
                rescue StandardError => error
                    Na__DebugTools.Na__Debug__Warn("The NPR viewport config could not be written: #{error.message}")
                end
            end
            @na_data
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
