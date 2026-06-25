# =============================================================================
# VALEDESIGNSUITE - VALEVISION CLOUD SYNC CONFIG LOADER
# =============================================================================
#
# FILE       : Na__ValeVisionCloudSync__CoreAppLogic__ConfigLoader__.rb
# NAMESPACE  : Na__ValeVisionCloudSync::Na__ConfigLoader
# PURPOSE    : Load and normalize the UiCommandRegistry and AppConfig JSON
# CREATED    : 25-Jun-2026
#
# DESCRIPTION:
# - Reads Na__ValeVisionCloudSync__CoreAppData__UiCommandRegistry__.json for
#   dialog and command settings, and AppConfig__.json for sync operation
#   settings (paths, image export params, Python orchestrator, CDN URLs).
# - Merges against hardcoded defaults so the plugin is safe even if JSON
#   files are missing.
#
# =============================================================================

require 'json'

module Na__ValeVisionCloudSync
    module Na__ConfigLoader

# -----------------------------------------------------------------------------
# REGION | Default Configuration
# -----------------------------------------------------------------------------

        NA_DEFAULT_REGISTRY = {
            'extension_name'         => 'ValeVision Cloud Sync',
            'dialog_title'           => 'ValeVision Cloud Sync',
            'dialog_preferences_key' => 'Na__ValeVisionCloudSync',
            'dialog_width'           => 560,
            'dialog_height'          => 660,
            'dialog_resizable'       => true,
            'tabs'                   => [
                { 'tab_id' => 'export',   'tab_name' => 'Export',   'tab_order' => 10, 'tab_description' => 'Sync scenes to ValeVision 3D.' },
                { 'tab_id' => 'settings', 'tab_name' => 'Settings', 'tab_order' => 90, 'tab_description' => 'Project path and plugin maintenance.' }
            ],
            'commands'               => [],
            'settings'               => {
                'model_dictionary_name' => 'ValeVision__CloudExport',
                'status_element_id'     => 'naVvcsStatus'
            }
        }.freeze

        NA_DEFAULT_APP_CONFIG = {
            'image_export'         => {
                'width'              => 6000,
                'height'             => 4000,
                'antialias'          => true,
                'compression'        => 0.9,
                'transparent'        => false,
                'scale_factor'       => 2.0,
                'scene_prefix_regex' => '^IMG\d{2,3}'
            },
            'project_subfolders'   => {
                'project_data'      => '00__ProjectData',
                'reference_files'   => '01__ReferenceFiles',
                'sketchup'          => '02__SketchUp',
                'content_delivered' => '10__ContentDelivered__Local',
                'glb_sync'          => '10__ContentDelivered__Local/ValeVision__GlbFileSync',
                'glb_archives'      => '10__ContentDelivered__Local/ValeVision__GlbFileSync/00__ArchivedModels'
            },
            'edition_folder_prefix' => 'VisDpt__Whitecard__',
            'python'               => {
                'orchestrator_script' => 'Tools__DevUtils/AutomationUtil__SyncSingleProject__ToCloudAndWeb__Main__.py',
                'whitecardopedia_root' => 'D:/10_CoreLib__ValeCodebase/WebApps/Whitecardopedia'
            },
            'cdn'                  => {
                'r2_base_url'     => 'https://cdn.noble-architecture.com/VaApps/Projects',
                'github_base_url' => 'https://raw.githubusercontent.com/noble-architecture/noble-architecture.github.io/main/na-project-portal'
            }
        }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Config Access — UiCommandRegistry
# -----------------------------------------------------------------------------

        def self.Na__ValeVisionCloudSync__RegistryHash
            return @na_cached_registry if @na_cached_registry

            registry_path = Na__PathResolver.Na__ValeVisionCloudSync__UiCommandRegistryFilePath
            parsed = {}
            parsed = JSON.parse(File.read(registry_path)) if File.exist?(registry_path)

            @na_cached_registry = na_deep_merge_hashes(NA_DEFAULT_REGISTRY, parsed)
        rescue => error
            puts "[Na__ValeVisionCloudSync] Registry load warning: #{error.class}: #{error.message}"
            @na_cached_registry = NA_DEFAULT_REGISTRY.dup
        end

        def self.Na__ValeVisionCloudSync__InvalidateConfigCache
            @na_cached_registry = nil
            @na_cached_app_config = nil
        end

        def self.Na__ValeVisionCloudSync__ExtensionName
            self.Na__ValeVisionCloudSync__RegistryHash.fetch('extension_name', NA_DEFAULT_REGISTRY['extension_name'])
        end

        def self.Na__ValeVisionCloudSync__DialogTitle
            self.Na__ValeVisionCloudSync__RegistryHash.fetch('dialog_title', self.Na__ValeVisionCloudSync__ExtensionName)
        end

        def self.Na__ValeVisionCloudSync__DialogPreferencesKey
            self.Na__ValeVisionCloudSync__RegistryHash.fetch('dialog_preferences_key', 'Na__ValeVisionCloudSync')
        end

        def self.Na__ValeVisionCloudSync__DialogWidth
            self.Na__ValeVisionCloudSync__RegistryHash.fetch('dialog_width', 560).to_i
        end

        def self.Na__ValeVisionCloudSync__DialogHeight
            self.Na__ValeVisionCloudSync__RegistryHash.fetch('dialog_height', 660).to_i
        end

        def self.Na__ValeVisionCloudSync__DialogResizable
            self.Na__ValeVisionCloudSync__RegistryHash.fetch('dialog_resizable', true)
        end

        def self.Na__ValeVisionCloudSync__Tabs
            self.Na__ValeVisionCloudSync__RegistryHash.fetch('tabs', [])
        end

        def self.Na__ValeVisionCloudSync__Commands
            self.Na__ValeVisionCloudSync__RegistryHash.fetch('commands', [])
        end

        def self.Na__ValeVisionCloudSync__Settings
            self.Na__ValeVisionCloudSync__RegistryHash.fetch('settings', {})
        end

        def self.Na__ValeVisionCloudSync__ModelDictionaryName
            self.Na__ValeVisionCloudSync__Settings.fetch('model_dictionary_name', 'ValeVision__CloudExport')
        end

        def self.Na__ValeVisionCloudSync__CommandById(command_id)
            self.Na__ValeVisionCloudSync__Commands.find { |cmd| cmd['command_id'] == command_id.to_s }
        end

        def self.Na__ValeVisionCloudSync__HotkeyVisibleCommands
            self.Na__ValeVisionCloudSync__Commands.select { |cmd| cmd['expose_to_hotkeys'] }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Config Access — AppConfig (sync operation settings)
# -----------------------------------------------------------------------------

        def self.Na__ValeVisionCloudSync__AppConfig
            return @na_cached_app_config if @na_cached_app_config

            app_config_path = Na__PathResolver.Na__ValeVisionCloudSync__AppConfigFilePath
            parsed = {}
            parsed = JSON.parse(File.read(app_config_path)) if File.exist?(app_config_path)

            @na_cached_app_config = na_deep_merge_hashes(NA_DEFAULT_APP_CONFIG, parsed)
        rescue => error
            puts "[Na__ValeVisionCloudSync] AppConfig load warning: #{error.class}: #{error.message}"
            @na_cached_app_config = NA_DEFAULT_APP_CONFIG.dup
        end

        def self.Na__ValeVisionCloudSync__ImageExportConfig
            self.Na__ValeVisionCloudSync__AppConfig.fetch('image_export', NA_DEFAULT_APP_CONFIG['image_export'])
        end

        def self.Na__ValeVisionCloudSync__ProjectSubfolders
            self.Na__ValeVisionCloudSync__AppConfig.fetch('project_subfolders', NA_DEFAULT_APP_CONFIG['project_subfolders'])
        end

        def self.Na__ValeVisionCloudSync__EditionFolderPrefix
            self.Na__ValeVisionCloudSync__AppConfig.fetch('edition_folder_prefix', 'VisDpt__Whitecard__')
        end

        def self.Na__ValeVisionCloudSync__PythonConfig
            self.Na__ValeVisionCloudSync__AppConfig.fetch('python', NA_DEFAULT_APP_CONFIG['python'])
        end

        def self.Na__ValeVisionCloudSync__CdnConfig
            self.Na__ValeVisionCloudSync__AppConfig.fetch('cdn', NA_DEFAULT_APP_CONFIG['cdn'])
        end

        def self.Na__ValeVisionCloudSync__ScenePrefixRegex
            pattern = self.Na__ValeVisionCloudSync__ImageExportConfig.fetch('scene_prefix_regex', '^IMG\d{2,3}')
            Regexp.new(pattern)
        rescue => error
            puts "[Na__ValeVisionCloudSync] Scene prefix regex error: #{error.message}; using fallback."
            /^IMG\d{2,3}/
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Helpers
# -----------------------------------------------------------------------------

        def self.na_deep_merge_hashes(base_hash, override_hash)
            return base_hash unless override_hash.is_a?(Hash)

            merged = base_hash.dup
            override_hash.each do |key, override_value|
                base_value = merged[key]
                merged[key] = if base_value.is_a?(Hash) && override_value.is_a?(Hash)
                    na_deep_merge_hashes(base_value, override_value)
                else
                    override_value
                end
            end
            merged
        end

# endregion -------------------------------------------------------------------

    end # module Na__ConfigLoader
end # module Na__ValeVisionCloudSync

# =============================================================================
# END OF FILE
# =============================================================================
