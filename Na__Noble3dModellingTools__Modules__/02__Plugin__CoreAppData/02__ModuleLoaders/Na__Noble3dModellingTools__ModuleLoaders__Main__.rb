# =============================================================================
# NA NOBLE3D MODELLING TOOLS - FEATURE MODULE LOADERS
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__ModuleLoaders__Main__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__ModuleLoaders
# PURPOSE    : Load all feature script modules under 10__PluginModules
# CREATED    : 2026
#
# CONFIG-FIRST DESIGN NOTE:
# Feature modules may be required here, but tool tabs, grouping, labels, command
# IDs, ordering, and hotkey visibility belong in the JSON command registry. Avoid
# adding UI layout rules or button placement logic to this loader.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__ModuleLoaders

# -----------------------------------------------------------------------------
# REGION | Feature Module Loading
# -----------------------------------------------------------------------------

        def self.Na__Noble3dModellingTools__LoadFeatureModules
            return true if @na_feature_modules_loaded

            require_relative '../../10__PluginModules/01__SourceCode__SelectQuadFaceRings/Na__Noble3dModellingTools__SelectQuadFaceRings__Loader__'
            require_relative '../../10__PluginModules/02__SourceCode__LatticeMaker/Na__Noble3dModellingTools__LatticeMaker__Loader__'
            require_relative '../../10__PluginModules/03__SourceCode__AutoGroupUtility/Na__Noble3dModellingTools__AutoGroupUtility__Loader__'
            require_relative '../../10__PluginModules/04__SourceCode__AutoGroupFaceIslands/Na__Noble3dModellingTools__AutoGroupFaceIslands__Loader__'
            require_relative '../../10__PluginModules/05__SourceCode__ConvertComponentsToGroups/Na__Noble3dModellingTools__ConvertComponentsToGroups__Loader__'
            require_relative '../../10__PluginModules/06__SourceCode__InsertComponentInPlace/Na__Noble3dModellingTools__InsertComponentInPlace__Loader__'
            require_relative '../../10__PluginModules/07__SourceCode__CreateBoundingBox/Na__Noble3dModellingTools__CreateBoundingBox__Loader__'
            require_relative '../../10__PluginModules/08__SourceCode__MaterialUtils/Na__Noble3dModellingTools__MaterialUtils__Loader__'
            require_relative '../../10__PluginModules/09__SourceCode__TagUtils/Na__Noble3dModellingTools__TagUtils__Loader__'
            require_relative '../../10__PluginModules/10__SourceCode__WebStatus/Na__Noble3dModellingTools__WebStatus__Loader__'
            require_relative '../../10__PluginModules/11__SourceCode__SelectedHierarchyTagReporter/Na__Noble3dModellingTools__SelectedHierarchyTagReporter__Loader__'
            require_relative '../../10__PluginModules/12__SourceCode__CullEdgesBelowThreshold/Na__Noble3dModellingTools__CullEdgesBelowThreshold__Loader__'
            require_relative '../../10__PluginModules/13__SourceCode__OrthoMirrorTool/Na__Noble3dModellingTools__OrthoMirrorTool__Loader__'
            require_relative '../../10__PluginModules/14__SourceCode__ImageCarousel/Na__Noble3dModellingTools__ImageCarousel__Loader__'
            require_relative '../../10__PluginModules/15__SourceCode__Flatten3dTo2d/Na__Noble3dModellingTools__Flatten3dTo2d__Loader__'
            require_relative '../../10__PluginModules/16__SourceCode__PdfVectorImporter/Na__Noble3dModellingTools__PdfVectorImporter__Loader__'
            require_relative '../../10__PluginModules/17__SourceCode__GroupsToComponent/Na__Noble3dModellingTools__GroupsToComponent__Loader__'
            require_relative '../../10__PluginModules/18__SourceCode__MultipleOffsetTool/Na__Noble3dModellingTools__MultipleOffsetTool__Loader__'

            @na_feature_modules_loaded = true
            true
        rescue LoadError, SyntaxError => error
            puts "[Na__Noble3dModellingTools] Module loader file error: #{error.class}: #{error.message}"
            puts error.backtrace.first(10).join("\n") if error.backtrace
            false
        rescue StandardError => error
            puts "[Na__Noble3dModellingTools] Module loader runtime error: #{error.class}: #{error.message}"
            puts error.backtrace.first(10).join("\n") if error.backtrace
            false
        end

        def self.Na__Noble3dModellingTools__ResetModuleLoadState
            @na_feature_modules_loaded = false
        end

# endregion -------------------------------------------------------------------

    end # module Na__ModuleLoaders
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
