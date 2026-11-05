# =============================================================================
# NA NOBLE DRAWING TOOLS - APPCORE PATH RESOLVER
# =============================================================================
#
# FILE       : Na__NobleDrawingTools__AppCore__PathResolver__.rb
# NAMESPACE  : Na__NobleDrawingTools::Na__PathResolver
# AUTHOR     : Noble Architecture
# PURPOSE    : Resolve the modules root and plugin root from nested AppCore
# CREATED    : 2026
#
# =============================================================================

module Na__NobleDrawingTools

    module Na__PathResolver

        # -----------------------------------------------------------------------------
        # REGION | Root Paths
        # -----------------------------------------------------------------------------

        # FUNCTION | Folder Holding Numbered Plugin Modules
        # ------------------------------------------------------------
        def self.Na__NobleDrawingTools__ModulesRoot
            @na_modules_root ||= File.expand_path('..', __dir__)
        end
        # ---------------------------------------------------------------


        # FUNCTION | SketchUp Plugins Folder (Parent of Modules)
        # ------------------------------------------------------------
        def self.Na__NobleDrawingTools__PluginRoot
            @na_plugin_root ||= File.expand_path(
                '..',
                Na__NobleDrawingTools::Na__PathResolver.Na__NobleDrawingTools__ModulesRoot
            )
        end
        # ---------------------------------------------------------------


        # FUNCTION | Expand a Path Relative to the Modules Root
        # ------------------------------------------------------------
        def self.Na__NobleDrawingTools__ModulesFile(relative_path)
            File.expand_path(
                File.join(
                    Na__NobleDrawingTools::Na__PathResolver.Na__NobleDrawingTools__ModulesRoot,
                    relative_path
                )
            ).tr('\\', '/')
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end

end

# =============================================================================
# END OF FILE
# =============================================================================
