# =============================================================================
# NA POINT CLOUD VIEWER - APP CORE - STATE PAYLOAD
# =============================================================================
#
# FILE       : Na__PointCloudViewer__AppCore__StatePayload__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__StatePayload
# PURPOSE    : Builds the JSON-safe state pushed to the dialog. The HTML holds
#              no model data of its own: Ruby pushes state, JS renders it, so
#              any change (settings, overlay panel toggle, undo, model switch)
#              is a repaint, never a set_html.
#
# =============================================================================

module Na__PointCloudViewer
    module Na__StatePayload

    # -------------------------------------------------------------------------
    # REGION | Full State
    # -------------------------------------------------------------------------

        def self.Na__State__Build
            model   = Sketchup.active_model
            session = Na__ModelRegistry.Na__Registry__ActiveSession
            source_unit = session && session.cloud ? session.cloud.source_unit : nil
            {
                'plugin'       => { 'name' => Na__ConfigLoader.Na__Config__GetOr('Na Point Cloud Viewer', 'plugin', 'name'),
                                    'version' => Na__PointCloudViewer.Na__PublicApi__Version },
                'units'        => Na__UnitContract.Na__Units__SummaryPayload(model, source_unit),
                'overlay'      => self.na_overlay_payload(model),
                'cloud'        => self.na_cloud_payload(session),
                'render'       => self.na_render_payload(session),
                'clip'         => Na__ClipBox.Na__Clip__Payload(session, model),
                'transform'    => Na__Placement.Na__Placement__Payload(session, model),
                'link'         => Na__ModelLink.Na__Link__Payload(session, model),
                'job'          => { 'isRunning' => Na__AsyncJobs.Na__Jobs__Busy?, 'title' => Na__AsyncJobs.Na__Jobs__ActiveTitle },
                'paths'        => {
                    'cacheFolder'    => Na__AssetResolver.Na__Paths__CacheFolder,
                    'userConfigFile' => Na__AssetResolver.Na__Paths__UserConfigFile
                },
                'nativeEngine' => self.na_native_payload,
                'ui'           => { 'activeTab' => Na__UserConfigStore.Na__UserConfig__Get('ui', 'activeTab', 'view') },
                'log'          => Na__DebugTools.Na__Debug__RecentEntries(30)
            }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Sections
    # -------------------------------------------------------------------------

        def self.na_overlay_payload(model)
            overlay = Na__ModelRegistry.Na__Registry__FindOverlay(model)
            {
                'isRegistered' => overlay ? true : false,
                'isVisible'    => overlay ? overlay.enabled? : false,
                'overlayId'    => Na__ModelRegistry.Na__Registry__OverlayId
            }
        end

        def self.na_cloud_payload(session)
            cloud = session ? session.cloud : nil
            return { 'isLoaded' => false } unless cloud
            {
                'isLoaded'    => true,
                'label'       => cloud.label,
                'totalPoints' => cloud.total_points,
                'sizeText'    => cloud.bounds ? self.na_bounds_text(cloud.bounds) : '',
                'sourcePath'  => cloud.source_path,
                'sourceUnit'  => Na__UnitContract.Na__Units__SourceUnitLabel(cloud.source_unit),
                'colourBits'  => cloud.las_info ? cloud.las_info['colourBits'] : nil,
                'timings'     => cloud.timings
            }
        end

        def self.na_render_payload(session)
            {
                'settings'      => session ? session.settings : Na__RenderSettings.Na__Settings__Defaults,
                'limits'        => Na__RenderSettings.Na__Settings__Limits,
                'budgetPresets' => Na__ConfigLoader.Na__Config__GetOr([], 'render', 'budgetPresets'),
                'fault'         => session ? session.fault : nil
            }
        end

        # Status only: never loads the DLL just to report on it.
        def self.na_native_payload
            status = Na__NativeEngine.Na__Native__Status
            message = if !status['isBuilt'] then 'Not built. Run the build script in 02__Src__NativeEngine/03__BuildScripts.'
                      elsif status['error'] then status['error']
                      elsif !status['isLoaded'] then "Ready (built #{status['binaryTime']}). Loads when a cloud is drawn."
                      elsif status['isStale'] then "A newer build (#{status['binaryTime']}) is on disk. Reload Plugin swaps it in."
                      else "Running on #{status['threads']} threads (built #{status['binaryTime']})."
                      end
            status.merge('message' => message)
        end

        # Size in metres regardless of model units: a site is read in metres.
        def self.na_bounds_text(bounds)
            metres_per_inch = 0.0254
            [bounds.width, bounds.height, bounds.depth].map { |inches| format('%.1f m', inches.to_f * metres_per_inch) }.join(' x ')
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
