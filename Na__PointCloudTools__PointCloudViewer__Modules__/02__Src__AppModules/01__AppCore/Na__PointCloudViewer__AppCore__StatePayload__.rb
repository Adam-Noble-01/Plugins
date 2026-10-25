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
# SEVERAL CLOUDS (v0.10.0): 'clouds' lists every cloud of the model (the cloud
#   bar and the View tab's list); 'cloud', 'render' (the look), 'units',
#   'clip', 'transform' and 'clean' describe the ACTIVE cloud, the one the
#   tabs work on, and each names it (cloudId, cloudName). The point budget in
#   'render' is the shared one.
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
            slot    = session ? Na__CloudSet.Na__Slots__Active(session) : nil
            source_unit = slot && slot.cloud ? slot.cloud.source_unit : (slot && slot.record ? slot.record.dig('link', 'sourceUnit') : nil)
            {
                'plugin'       => { 'name' => Na__ConfigLoader.Na__Config__GetOr('Na Point Cloud Viewer', 'plugin', 'name'),
                                    'version' => Na__PointCloudViewer.Na__PublicApi__Version },
                'units'        => Na__UnitContract.Na__Units__SummaryPayload(model, source_unit),
                'overlay'      => self.na_overlay_payload(model),
                'clouds'       => Na__CloudSet.Na__Slots__Payload(session, model),
                'cloud'        => self.na_cloud_payload(slot),
                'render'       => self.na_render_payload(session, slot),
                'clip'         => Na__ClipBox.Na__Clip__Payload(slot, model),
                'transform'    => Na__Placement.Na__Placement__Payload(slot, model),
                'link'         => Na__ModelLink.Na__Link__Payload(session, model),
                'clean'        => Na__CleanPreview.Na__Clean__Payload(slot, model),
                'scenes'       => self.na_scenes_payload(session, model),
                'job'          => { 'isRunning' => Na__AsyncJobs.Na__Jobs__Busy?, 'title' => Na__AsyncJobs.Na__Jobs__ActiveTitle },
                'paths'        => {
                    'cacheFolder'    => Na__AssetResolver.Na__Paths__CacheFolder,
                    'userConfigFile' => Na__AssetResolver.Na__Paths__UserConfigFile
                },
                'pointCaches'  => Na__PointCache.Na__Cache__Stats,
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

        # The active cloud.
        def self.na_cloud_payload(slot)
            return { 'isLoaded' => false, 'inModel' => false } unless slot
            cloud = slot.cloud
            base = { 'inModel' => true, 'id' => slot.id, 'name' => slot.name, 'colour' => Na__CloudSet.Na__Slots__HexColour(slot.colour),
                     'colourName' => Na__CloudStore.Na__Store__ColourName(slot.colour), 'visible' => slot.visible ? true : false }
            return base.merge('isLoaded' => false) unless cloud
            base.merge(
                'isLoaded'    => true,
                'label'       => cloud.label,
                'totalPoints' => cloud.total_points,
                'sizeText'    => cloud.bounds ? self.na_bounds_text(cloud.bounds) : '',
                'sourcePath'  => cloud.source_path,
                'sourceUnit'  => Na__UnitContract.Na__Units__SourceUnitLabel(cloud.source_unit),
                'colourBits'  => cloud.las_info ? cloud.las_info['colourBits'] : nil,
                'timings'     => cloud.timings
            )
        end

        # The shared budget, the active cloud's look, and how the budget is
        # spread over the clouds on show in the last frame.
        def self.na_render_payload(session, slot)
            settings = session ? session.settings.dup : Na__RenderSettings.Na__Settings__Defaults
            settings.merge!(slot.display) if slot && slot.display
            drawn = session ? Na__CloudSet.Na__Slots__Drawn(session) : []
            {
                'settings'      => settings,
                'limits'        => Na__RenderSettings.Na__Settings__Limits,
                'budgetPresets' => Na__ConfigLoader.Na__Config__GetOr([], 'render', 'budgetPresets'),
                'fault'         => session ? session.fault : nil,
                'shownPoints'   => drawn.sum { |each_slot| each_slot.cloud.total_points.to_i },
                'shownCount'    => drawn.length,
                'layers'        => drawn.map do |each_slot|
                    stats = each_slot.layer_stats || {}
                    { 'id' => each_slot.id, 'name' => each_slot.name, 'colour' => Na__CloudSet.Na__Slots__HexColour(each_slot.colour),
                      'totalPoints' => each_slot.cloud.total_points, 'share' => stats['share'], 'drawn' => stats['onScreen'] }
                end
            }
        end

        # A fault here must never stop the rest of the dialog from painting.
        def self.na_scenes_payload(session, model)
            Na__SceneRecall.Na__Scenes__Payload(session, model, model.active_view)
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('The Scenes tab could not be built.', error)
            { 'isAvailable' => false, 'problem' => "The point cloud scenes could not be shown (#{error.message})." }
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
