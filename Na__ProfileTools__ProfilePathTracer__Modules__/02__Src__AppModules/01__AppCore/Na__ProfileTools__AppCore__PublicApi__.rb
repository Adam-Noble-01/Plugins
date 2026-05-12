# =============================================================================
# NA PROFILE TOOLS - APP CORE - PUBLIC API
# =============================================================================
#
# FILE       : Na__ProfileTools__AppCore__PublicApi__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer
# PURPOSE    : Public entry points used by loader and other ecosystem plugins
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer

    # -------------------------------------------------------------------------
    # REGION | Public API - Dialog
    # -------------------------------------------------------------------------

    def self.Na__PublicApi__OpenDialog
        Na__ProfileTools__ProfilePathTracer.Na__Runtime__EnsureUnifiedGeometryBuilders
        Na__Observers.Na__Observers__InstallOnce
        Na__DialogManager.Na__Dialog__Show
    rescue => error
        Na__DebugTools.Na__Debug__Error('Unable to open dialog.', error)
        UI.messagebox("Na Profile Path Tracer failed to open.\n\n#{error.message}")
    end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public API - Headless Execution
    # -------------------------------------------------------------------------

    def self.Na__PublicApi__RunHeadless(config_hash = {})
        Na__HeadlessRunner.Na__Headless__Run(config_hash)
    end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public API - Reload
    # -------------------------------------------------------------------------

    def self.Na__PublicApi__ReloadPluginFiles
        Na__PluginReloader.Na__Reload__PluginFiles(NA_PLUGIN_ROOT)
    end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public API - Roundtrip Validation
    # -------------------------------------------------------------------------

    def self.Na__PublicApi__RunRoundtripValidation(profile_key, selected_entities = nil)
        profile_record = Na__ProfileLibrary.Na__ProfileLibrary__FindByKey(profile_key)
        unless profile_record
            return { 'isValid' => false, 'reason' => "Profile not found: #{profile_key}" }
        end

        source_stats = self.Na__PublicApi__CollectProfileEdgeStats(profile_record)
        result = {
            'isValid' => true,
            'profileKey' => profile_key,
            'sourceStats' => source_stats,
            'generation' => nil,
            'generatedStats' => nil,
            'comparison' => nil
        }

        model = Sketchup.active_model
        return result unless model

        path_entities = selected_entities || model.selection.to_a
        return result if Array(path_entities).empty?

        build_result = Na__ProfilePlacementEngine.Na__Engine__BuildFromSelection(profile_key, path_entities, {})
        result['generation'] = build_result
        return result unless build_result['isBuilt'] == true

        generated_group = self.Na__PublicApi__FindGeneratedGroup(model, build_result['groupName'])
        generated_stats = self.Na__PublicApi__CollectGroupEdgeStats(generated_group)
        result['generatedStats'] = generated_stats
        result['comparison'] = self.Na__PublicApi__CompareEdgeStats(source_stats, generated_stats)
        result
    rescue => error
        { 'isValid' => false, 'reason' => "Roundtrip validation failed: #{error.message}" }
    end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Validation Helpers
    # -------------------------------------------------------------------------

    def self.Na__PublicApi__CollectProfileEdgeStats(profile_record)
        mesh_edges = Array(profile_record.dig('profileData', 'assetData', 'Na__Asset__Mesh3D', 'Na__Geometry__Edges'))
        {
            'edgeCount'    => mesh_edges.length,
            'softCount'    => mesh_edges.count { |edge| edge['IsSoft'] == true },
            'smoothCount'  => mesh_edges.count { |edge| edge['IsSmooth'] == true },
            'hiddenCount'  => mesh_edges.count { |edge| edge['IsHidden'] == true },
            'colouredCount' => mesh_edges.count { |edge| edge['EdgeMaterialName'].to_s.strip.length > 0 || edge['EdgeColourId'].to_s.strip.length > 0 }
        }
    end

    def self.Na__PublicApi__FindGeneratedGroup(model, group_name)
        groups = model.active_entities.grep(Sketchup::Group)
        return groups.last if group_name.to_s.strip.empty?
        groups.reverse.find { |group| group.name.to_s == group_name.to_s }
    end

    def self.Na__PublicApi__CollectGroupEdgeStats(group)
        return nil unless group && group.valid?
        edges = group.entities.grep(Sketchup::Edge)
        {
            'edgeCount'    => edges.length,
            'softCount'    => edges.count(&:soft?),
            'smoothCount'  => edges.count(&:smooth?),
            'hiddenCount'  => edges.count(&:hidden?),
            'colouredCount' => edges.count { |edge| !edge.material.nil? }
        }
    end

    def self.Na__PublicApi__CompareEdgeStats(source_stats, generated_stats)
        return nil unless source_stats.is_a?(Hash) && generated_stats.is_a?(Hash)
        {
            'softDelta'     => generated_stats['softCount'].to_i    - source_stats['softCount'].to_i,
            'smoothDelta'   => generated_stats['smoothCount'].to_i  - source_stats['smoothCount'].to_i,
            'hiddenDelta'   => generated_stats['hiddenCount'].to_i  - source_stats['hiddenCount'].to_i,
            'colouredDelta' => generated_stats['colouredCount'].to_i - source_stats['colouredCount'].to_i
        }
    end

    # endregion ----------------------------------------------------------------

end

# =============================================================================
# END OF FILE
# =============================================================================
