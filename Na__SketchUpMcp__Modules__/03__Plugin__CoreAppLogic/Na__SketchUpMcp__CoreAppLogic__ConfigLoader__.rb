# =============================================================================
# NA SKETCHUP MCP - CORE CONFIG LOADER
# =============================================================================
#
# FILE       : Na__SketchUpMcp__CoreAppLogic__ConfigLoader__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__ConfigLoader
# PURPOSE    : Read AppConfig JSON, per-user overrides and the tool registry
# CREATED    : 2026
#
# CONFIG-FIRST DESIGN NOTE:
# The tool registry JSON is the single source of truth for every MCP tool:
# the Python server reads names, descriptions and input schemas from it, and
# this bridge reads handler routes, the mutates flag, undo names and the API
# dependencies from the SAME file. Add a tool by adding a registry entry and a
# handler method; never hardcode tool metadata in Ruby.
#
# =============================================================================

require 'json'
require 'fileutils'

module Na__SketchUpMcp
    module Na__ConfigLoader

# -----------------------------------------------------------------------------
# REGION | App Config (AppConfig JSON deep-merged with user overrides)
# -----------------------------------------------------------------------------

        def self.Na__ConfigLoader__AppConfig
            @na_app_config ||= na_deep_merge(na_read_json(Na__PathResolver.Na__PathResolver__AppConfigFilePath),
                                             self.Na__ConfigLoader__UserSettings)
        end

        # Dig into the merged config: Na__ConfigLoader__Get('bridge', 'port', 8385)
        def self.Na__ConfigLoader__Get(*keys, default_value)
            value = keys.reduce(self.Na__ConfigLoader__AppConfig) do |node, key|
                node.is_a?(Hash) ? node[key.to_s] : nil
            end
            value.nil? ? default_value : value
        end

        def self.Na__ConfigLoader__BridgeVersion
            self.Na__ConfigLoader__Get('metadata', 'bridge_version', '0.0.0')
        end

        def self.Na__ConfigLoader__ReadOnlyMode
            self.Na__ConfigLoader__Get('safety', 'read_only_mode', false) == true
        end

        def self.Na__ConfigLoader__AllowRubyEval
            self.Na__ConfigLoader__Get('safety', 'allow_ruby_eval', true) == true
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Per-User Settings (toggled from the status dialog)
# -----------------------------------------------------------------------------

        def self.Na__ConfigLoader__UserSettings
            path = Na__PathResolver.Na__PathResolver__UserSettingsFilePath
            return {} unless File.exist?(path)

            na_read_json(path)
        rescue StandardError => error
            puts "[Na__SketchUpMcp] User settings unreadable, using defaults: #{error.class}: #{error.message}"
            {}
        end

        # section_name / key_name mirror the AppConfig layout, e.g. ('safety', 'read_only_mode').
        def self.Na__ConfigLoader__SaveUserSetting(section_name, key_name, value)
            settings = self.Na__ConfigLoader__UserSettings
            settings[section_name.to_s] ||= {}
            settings[section_name.to_s][key_name.to_s] = value

            Na__PathResolver.Na__PathResolver__EnsureDirectory(Na__PathResolver.Na__PathResolver__UserConfigDirectory)
            File.write(Na__PathResolver.Na__PathResolver__UserSettingsFilePath, JSON.pretty_generate(settings))
            self.Na__ConfigLoader__InvalidateCache
            true
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Tool Registry (shared with the Python MCP server)
# -----------------------------------------------------------------------------

        def self.Na__ConfigLoader__ToolRegistry
            @na_tool_registry ||= na_read_json(Na__PathResolver.Na__PathResolver__ToolRegistryFilePath)
        end

        def self.Na__ConfigLoader__Tools
            self.Na__ConfigLoader__ToolRegistry.fetch('tools', [])
        end

        def self.Na__ConfigLoader__ToolByName(tool_name)
            @na_tools_by_name ||= self.Na__ConfigLoader__Tools.each_with_object({}) do |tool, lookup|
                lookup[tool['name']] = tool
            end
            @na_tools_by_name[tool_name.to_s]
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Cache Control
# -----------------------------------------------------------------------------

        def self.Na__ConfigLoader__InvalidateCache
            @na_app_config = nil
            @na_tool_registry = nil
            @na_tools_by_name = nil
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Helpers
# -----------------------------------------------------------------------------

        def self.na_read_json(path)
            JSON.parse(File.read(path, encoding: 'UTF-8'))
        end

        def self.na_deep_merge(base_hash, override_hash)
            base_hash.merge(override_hash) do |_key, base_value, override_value|
                if base_value.is_a?(Hash) && override_value.is_a?(Hash)
                    na_deep_merge(base_value, override_value)
                else
                    override_value
                end
            end
        end

# endregion -------------------------------------------------------------------

    end # module Na__ConfigLoader
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
