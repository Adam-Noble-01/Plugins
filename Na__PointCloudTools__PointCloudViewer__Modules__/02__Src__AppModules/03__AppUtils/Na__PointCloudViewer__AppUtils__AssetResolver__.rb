# =============================================================================
# NA POINT CLOUD VIEWER - APP UTILS - ASSET RESOLVER
# =============================================================================
#
# FILE       : Na__PointCloudViewer__AppUtils__AssetResolver__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__AssetResolver
# PURPOSE    : Resolves brand assets and the plugin's local data folders.
#              Every path is built from NA_MODULES_ROOT at run time - nothing
#              machine-specific is stored (the studio PC and the other
#              computer keep the repo at different paths).
#
# =============================================================================

module Na__PointCloudViewer
    module Na__AssetResolver

    # -------------------------------------------------------------------------
    # REGION | Brand Assets
    # -------------------------------------------------------------------------

        NA_TOOLBAR_ICON_FILE = 'Na__PointCloudViewer__Brand__CustomToolbarIcon__.png'.freeze
        NA_LOGO_FILE         = 'Na__PointCloudViewer__Brand__NobleLogo__.png'.freeze
        NA_COMMON_LOGO_FILE  = 'IMG01__PNG__NaCompanyLogo.png'.freeze

        def self.Na__Assets__ToolbarIconPath
            File.join(Na__PointCloudViewer::NA_ASSETS_ROOT, NA_TOOLBAR_ICON_FILE)
        end

        # Local copy first; the shared dependency folder is the fallback.
        def self.Na__Assets__LogoPath
            local = File.join(Na__PointCloudViewer::NA_ASSETS_ROOT, NA_LOGO_FILE)
            return local if File.exist?(local)
            common = File.expand_path(File.join(Na__PointCloudViewer::NA_MODULES_ROOT, '..', 'Na__Common__PluginDependencies', NA_COMMON_LOGO_FILE))
            File.exist?(common) ? common : local
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Local Data Folders
    # -------------------------------------------------------------------------

        # 90__AppCache__PointCloudCache/: render scratch images, native shadow
        # copies, later the .napc caches. Git-ignored; rebuildable from the LAS.
        def self.Na__Paths__CacheFolder
            folder_name = Na__ConfigLoader.Na__Config__GetOr('90__AppCache__PointCloudCache', 'paths', 'cacheFolder')
            File.join(Na__PointCloudViewer::NA_MODULES_ROOT, folder_name)
        end

        # 91__UserConfig__LocalOnly/ - per-user, per-PC settings. Git-ignored.
        def self.Na__Paths__UserConfigFolder
            folder_name = Na__ConfigLoader.Na__Config__GetOr('91__UserConfig__LocalOnly', 'paths', 'userConfigFolder')
            File.join(Na__PointCloudViewer::NA_MODULES_ROOT, folder_name)
        end

        def self.Na__Paths__UserConfigFile
            file_name = Na__ConfigLoader.Na__Config__GetOr('Na__PointCloudViewer__UserConfig__.json', 'paths', 'userConfigFile')
            File.join(self.Na__Paths__UserConfigFolder, file_name)
        end

        # Opens a folder in Windows Explorer, creating it first so the user
        # never lands on an error for an empty cache.
        def self.Na__Paths__OpenInExplorer(folder)
            FileUtils.mkdir_p(folder)
            system('explorer', folder.tr('/', '\\'))
            true
        end

        def self.Na__Paths__FolderSizeBytes(folder)
            return 0 unless File.directory?(folder)
            Dir.glob(File.join(folder, '**', '*')).sum { |path| File.file?(path) ? File.size(path) : 0 }
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
