# =============================================================================
# TRUEVISION3D - GLB BUILDER UTILITY - PATH RESOLVER
# =============================================================================
#
# FILE       : Na__TrueVision__GlbBuilder__PathResolver__.rb
# NAMESPACE  : TrueVision3D::GlbBuilderUtility
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Centralise all plugin-internal path resolution
# CREATED    : 19-Sep-2026
#
# DESCRIPTION:
# - Exposes helpers for the UI asset files and the brand / toolbar icon assets.
# - Mirrors the ValeVision Cloud Sync PathResolver so both plugins resolve their
#   own assets the same way.
# - Does NOT resolve project or model paths.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 19-Sep-2026 - Version 2.8.0
# - Initial path resolver, added alongside the ValeVision-style UI rebuild.
#
# =============================================================================

module TrueVision3D
    module GlbBuilderUtility

    # -----------------------------------------------------------------------------
    # REGION | Root Paths
    # -----------------------------------------------------------------------------

        # FUNCTION | Resolve The Modules Root Directory
        # ---------------------------------------------------------------
        def self.Na__PathResolver__ModulesRoot
            File.expand_path(__dir__)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Resolve The SketchUp Plugins Root Directory
        # ---------------------------------------------------------------
        # The top-level loader script lives here, one level above the modules.
        # ---------------------------------------------------------------
        def self.Na__PathResolver__PluginRoot
            File.expand_path(File.join(self.Na__PathResolver__ModulesRoot, '..'))
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | User Interface Asset Paths
    # -----------------------------------------------------------------------------

        # FUNCTION | Resolve The User Interface Directory
        # ---------------------------------------------------------------
        def self.Na__PathResolver__UiDirectory
            File.join(self.Na__PathResolver__ModulesRoot, '05__Plugin__UserInterface')
        end
        # ---------------------------------------------------------------

        # FUNCTION | Resolve The HtmlDialog Layout Template Path
        # ---------------------------------------------------------------
        def self.Na__PathResolver__UiLayoutFilePath
            File.join(self.Na__PathResolver__UiDirectory, 'Na__TrueVision__GlbBuilder__UiLayout__.html')
        end
        # ---------------------------------------------------------------

        # FUNCTION | Resolve The Stylesheet Path
        # ---------------------------------------------------------------
        def self.Na__PathResolver__UiStylesheetFilePath
            File.join(self.Na__PathResolver__UiDirectory, 'Na__TrueVision__GlbBuilder__Styles__.css')
        end
        # ---------------------------------------------------------------

        # FUNCTION | Resolve The UI Bridge Script Path
        # ---------------------------------------------------------------
        def self.Na__PathResolver__UiBridgeFilePath
            File.join(self.Na__PathResolver__UiDirectory, 'Na__TrueVision__GlbBuilder__UiBridge__.js')
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Brand and Icon Asset Paths
    # -----------------------------------------------------------------------------

        # FUNCTION | Resolve The Assets Directory
        # ---------------------------------------------------------------
        def self.Na__PathResolver__AssetsDirectory
            File.join(self.Na__PathResolver__ModulesRoot, '06__Assets')
        end
        # ---------------------------------------------------------------

        # FUNCTION | Resolve The Bundled Open Sans Font Directory
        # ---------------------------------------------------------------
        def self.Na__PathResolver__FontDirectory
            File.join(self.Na__PathResolver__AssetsDirectory, 'Fonts')
        end
        # ---------------------------------------------------------------

        # FUNCTION | Resolve The Noble Architecture Horizontal Logo Path
        # ---------------------------------------------------------------
        # Bundled fallback only. The dialog header pulls the canonical copy from
        # noble-architecture.com first; see Na__PathResolver__BrandLogoRemoteUrl.
        # ---------------------------------------------------------------
        def self.Na__PathResolver__BrandLogoFilePath
            File.join(self.Na__PathResolver__AssetsDirectory, 'Na__TrueVision__GlbBuilder__BrandLogo__Horizontal__.png')
        end
        # ---------------------------------------------------------------

        # FUNCTION | Resolve The Canonical Remote Brand Logo URL
        # ---------------------------------------------------------------
        def self.Na__PathResolver__BrandLogoRemoteUrl
            'https://www.noble-architecture.com/na-apps/01__Assets__NaApps__CommonAssets/' \
            'NaApps__CommonGraphics/NaBrandGraphic__CompanyLogo__w2048xh500px__.png'
        end
        # ---------------------------------------------------------------

        # FUNCTION | Resolve The Noble Architecture Square Toolbar Icon (Large)
        # ---------------------------------------------------------------
        def self.Na__PathResolver__ToolbarIconLargeFilePath
            File.join(self.Na__PathResolver__AssetsDirectory, 'Na__TrueVision__GlbBuilder__ToolbarIcon__NaSquare__.png')
        end
        # ---------------------------------------------------------------

        # FUNCTION | Resolve The Noble Architecture Square Toolbar Icon (Small)
        # ---------------------------------------------------------------
        def self.Na__PathResolver__ToolbarIconSmallFilePath
            File.join(self.Na__PathResolver__AssetsDirectory, 'Na__TrueVision__GlbBuilder__ToolbarIcon__NaSquare__32px__.png')
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | File URI Helpers
    # -----------------------------------------------------------------------------

        # FUNCTION | Convert An Absolute Disk Path To A Browser file:/// URI
        # ---------------------------------------------------------------
        # HtmlDialog runs a Chromium host, so backslashes and spaces must be
        # normalised before a local asset will resolve. Returns an empty string
        # when the path is missing so the caller can fall back cleanly.
        # ---------------------------------------------------------------
        def self.Na__PathResolver__FileUriFor(disk_path, require_exists: true)
            return '' if disk_path.nil? || disk_path.to_s.empty?
            return '' if require_exists && !File.exist?(disk_path)

            forward_path = disk_path.to_s.tr('\\', '/').sub(/\A\/+/, '')
            'file:///' + forward_path.gsub(' ', '%20')
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

    end  # module GlbBuilderUtility
end  # module TrueVision3D

# =============================================================================
# END OF FILE
# =============================================================================
