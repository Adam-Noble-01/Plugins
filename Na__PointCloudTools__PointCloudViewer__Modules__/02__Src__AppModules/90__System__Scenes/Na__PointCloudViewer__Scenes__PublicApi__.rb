# =============================================================================
# NA POINT CLOUD VIEWER - SCENES - PUBLIC API (for other Noble plugins)
# =============================================================================
#
# FILE       : Na__PointCloudViewer__Scenes__PublicApi__.rb
# NAMESPACE  : Na__PointCloudViewer (module functions Na__PublicApi__*)
# PURPOSE    : What TrueVision Sync (the GLB Builder) calls to list the point
#              cloud scenes, change their export settings and render them.
#
# ONE SOURCE OF TRUTH: the scenes live in this plugin's model dictionary
#   (Na__PointCloudViewer__Scenes). Other plugins never write it directly;
#   they call here, so both dialogs edit the same record through the same
#   checks and undo names, and each dialog repaints when the other changes it.
#   Change detection needs no observer: the store's 'revision' and each
#   scene's 'updatedEpoch' change on every write.
#
# CONTRACT: every function answers plain Ruby data (Hash / Array / String /
#   Numeric / true / false / nil), never raises to the caller, and checks
#   Na__PublicApi__ScenesApiVersion. Callers must check it before relying on a
#   key added later.
#
# =============================================================================

module Na__PointCloudViewer

    NA_SCENES_API_VERSION = 1 unless defined?(NA_SCENES_API_VERSION)

    # -------------------------------------------------------------------------
    # REGION | Public API
    # -------------------------------------------------------------------------

    def self.Na__PublicApi__ScenesApiVersion
        NA_SCENES_API_VERSION
    end

    # Everything a sync dialog needs to show the scenes. Nothing is loaded and
    # nothing is written.
    def self.Na__PublicApi__SceneList(model = Sketchup.active_model)
        session = self.na_api_session(model)
        return { 'ok' => false, 'problem' => 'The point cloud viewer is not available for this model.' } unless session
        view = model.active_view
        payload = Na__SceneRecall.Na__Scenes__Payload(session, model, view)
        cloud = session.cloud
        link = Na__ModelLink.Na__Link__Read(model)
        {
            'ok'            => true,
            'apiVersion'    => NA_SCENES_API_VERSION,
            'viewerVersion' => self.Na__PublicApi__Version,
            'storeId'       => (session.scenes_meta || {})['storeId'],
            'revision'      => payload['revision'],
            'readonly'      => payload['readonly'],
            'problem'       => payload['problem'],
            'cloudLoaded'   => cloud && cloud.native_cloud ? true : false,
            'cloudName'     => cloud ? cloud.label.to_s : (link ? link.dig('cloud', 'fileName').to_s : nil),
            'cloudLinked'   => link ? true : false,
            'scenes'        => payload['scenes'].map do |row|
                scene = Na__SceneStore.Na__Scenes__Find(session, row['id'])
                row.merge('opacityPercent' => scene ? scene.dig('settings', 'opacityPercent') : nil,
                          'updatedEpoch'   => scene ? scene['updatedEpoch'] : nil)
            end,
            'viewTypes'         => payload['viewTypes'],
            'scalePresets'      => payload['scalePresets'],
            'imageWidthPresets' => payload['imageWidthPresets'],
            'pointSizeMaxPx'    => payload['pointSizeMaxPx'],
            'pxPerPaperMm'      => payload['pxPerPaperMm']
        }
    rescue StandardError => error
        Na__DebugTools.Na__Debug__Error('Public API: the scene list could not be built.', error)
        { 'ok' => false, 'problem' => "The point cloud scenes could not be read (#{error.message})." }
    end

    # Same change as the Scenes tab: one undoable operation. values may hold
    # viewType, scale, imageWidthPx, pointSizePx. nil = done, else a reason.
    def self.Na__PublicApi__SetSceneExport(model, scene_id, values)
        session = self.na_api_session(model)
        return 'The point cloud viewer is not available for this model.' unless session
        problem = Na__SceneStore.Na__Scenes__SetExport(session, scene_id, values.is_a?(Hash) ? values : {})
        Na__DialogManager.Na__Dialog__PushState if Na__DialogManager.Na__Dialog__Visible?
        problem
    rescue StandardError => error
        Na__DebugTools.Na__Debug__Error('Public API: scene export settings could not be saved.', error)
        "The change could not be saved (#{error.message})."
    end

    # { 'ok' => true, 'plan' => {...} } or { 'ok' => false, 'problem' => text }.
    # The plan is plain data, including 'revisionKey' (same inputs, same key).
    def self.Na__PublicApi__PlanSceneExport(model, scene_id, options = {})
        session = self.na_api_session(model)
        return { 'ok' => false, 'problem' => 'The point cloud viewer is not available for this model.' } unless session
        Na__SceneImageExport.Na__Export__Plan(session, scene_id, options.is_a?(Hash) ? options : {})
    end

    # Renders the plan's tiles as PNG files into out_dir. The block, if given,
    # is called with (done, total) after each tile.
    def self.Na__PublicApi__RenderSceneTiles(model, plan, out_dir, &progress)
        session = self.na_api_session(model)
        return { 'ok' => false, 'problem' => 'The point cloud viewer is not available for this model.' } unless session
        Na__SceneImageExport.Na__Export__RenderTiles(session, plan, out_dir, &progress)
    end

    # Where the image sits in the model (TrueVision's placement record).
    def self.Na__PublicApi__SceneFrameRecord(plan)
        Na__SceneImageExport.Na__Export__FrameRecord(plan)
    rescue StandardError => error
        Na__DebugTools.Na__Debug__Error('Public API: the frame record could not be built.', error)
        nil
    end

    # Model point (inches) -> [u, v] image pixels, or nil (behind a camera).
    def self.Na__PublicApi__ScenePixelFor(plan, point)
        Na__SceneImageExport.Na__Export__ModelToPixel(plan, point.to_a.map(&:to_f))
    rescue StandardError
        nil
    end

    # Starts the viewer's own Reload Point Cloud (asynchronous, with its own
    # progress in the viewer's window). nil = started, else the reason.
    def self.Na__PublicApi__ReloadPointCloud(model = Sketchup.active_model)
        session = self.na_api_session(model)
        return 'The point cloud viewer is not available for this model.' unless session
        return 'A point cloud task is already running.' if Na__AsyncJobs.Na__Jobs__Busy?
        self.Na__PublicApi__OpenDialog
        Na__ModelLink.Na__Link__Reload(session)
    rescue StandardError => error
        Na__DebugTools.Na__Debug__Error('Public API: Reload Point Cloud could not start.', error)
        "Reload Point Cloud could not start (#{error.message})."
    end

    def self.na_api_session(model)
        return nil unless model && model == Sketchup.active_model
        overlay = Na__ModelRegistry.Na__Registry__EnsureOverlay(model)
        overlay && overlay.respond_to?(:na_session) ? overlay.na_session : nil
    end

    # endregion ----------------------------------------------------------------

end

# =============================================================================
# END OF FILE
# =============================================================================
