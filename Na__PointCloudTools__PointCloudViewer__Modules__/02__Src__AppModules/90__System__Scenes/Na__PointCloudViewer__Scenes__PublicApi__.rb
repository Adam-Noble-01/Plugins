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
# API 2 (19-Oct-2026): each SceneList row carries 'pagePid', the SketchUp
#   scene's Page#persistent_id, so TrueVision Sync's Scene Sync can match a
#   point cloud scene to the synced scene of the same page. The version
#   constant is guarded for hot reload, so a session reloaded from API 1 still
#   answers 1: callers test for the key itself.
#
# API 3 (19-Oct-2026): Na__PublicApi__ReorderScenes, so TrueVision Sync's
#   Point Cloud tab can drag the scenes into a new order in the same record
#   the Scenes tab reorders. Callers test respond_to?, for the same reason.
#
# API 4 (v0.10.0): several point clouds per model. SceneList gains 'clouds'
#   (every cloud of the model: id, name, colour, loaded, file, content key) and
#   'allCloudsLoaded'; each row gains 'cloudIds' and 'cloudNames' (the clouds
#   the scene shows). 'cloudLoaded' means at least one cloud is loaded, and
#   'cloudName' joins the names; a scene whose clouds are not all loaded is
#   refused by PlanSceneExport with a sentence naming them. A plan gains
#   'cloudIds' and 'layers' (one record per cloud: cloudId, name, cloud,
#   clip, colourMode, monoRgb, localToModel, opacityPercent); its top-level
#   'cloud', 'clip' and 'colourMode' still describe the first (for a one-cloud
#   scene, the only) cloud, exactly as before. ReloadPointCloud reloads every
#   cloud that is not loaded. Callers test the keys.
#
# =============================================================================

module Na__PointCloudViewer

    NA_SCENES_API_VERSION = 4 unless defined?(NA_SCENES_API_VERSION)

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
        slots = Na__CloudSet.Na__Slots__All(session)
        loaded = slots.select { |slot| slot.cloud && slot.cloud.native_cloud }
        {
            'ok'            => true,
            'apiVersion'    => NA_SCENES_API_VERSION,
            'viewerVersion' => self.Na__PublicApi__Version,
            'storeId'       => (session.scenes_meta || {})['storeId'],
            'revision'      => payload['revision'],
            'readonly'      => payload['readonly'],
            'problem'       => payload['problem'],
            'cloudLoaded'   => !loaded.empty?,
            'allCloudsLoaded' => !slots.empty? && loaded.length == slots.length,
            'cloudName'     => slots.empty? ? nil : (loaded.empty? ? slots : loaded).map(&:name).join(' + '),
            'cloudLinked'   => slots.any? { |slot| %w[saved legacy].include?(slot.record_state) },
            'clouds'        => slots.map { |slot| self.na_api_cloud(slot) },   # <-- API 4
            'scenes'        => payload['scenes'].map do |row|
                scene = Na__SceneStore.Na__Scenes__Find(session, row['id'])
                shown = (row['clouds'] || []).select { |cloud| cloud['visible'] }
                row.merge('opacityPercent' => scene ? Na__SceneStore.Na__Scenes__DefaultOpacity(scene) : nil,
                          'updatedEpoch'   => scene ? scene['updatedEpoch'] : nil,
                          'pagePid'        => scene ? scene.dig('page', 'pid') : nil,   # <-- API 2: the SketchUp scene this point cloud scene belongs to
                          'cloudIds'       => shown.map { |cloud| cloud['id'] },          # <-- API 4: the clouds the scene shows
                          'cloudNames'     => shown.map { |cloud| cloud['name'] })
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

    # API 3. The Scenes tab's drag to reorder: scene_ids is every scene id, top
    # to bottom, saved as one undoable operation. nil = done, else a reason.
    def self.Na__PublicApi__ReorderScenes(model, scene_ids)
        session = self.na_api_session(model)
        return 'The point cloud viewer is not available for this model.' unless session
        problem = Na__SceneStore.Na__Scenes__Reorder(session, scene_ids)
        Na__DialogManager.Na__Dialog__PushState if Na__DialogManager.Na__Dialog__Visible?
        problem
    rescue StandardError => error
        Na__DebugTools.Na__Debug__Error('Public API: the new scene order could not be saved.', error)
        "The new order could not be saved (#{error.message})."
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

    # Starts the viewer's own Reload (asynchronous, with its own progress in
    # the viewer's window) for every cloud of the model that is not loaded.
    # nil = started, else the reason.
    def self.Na__PublicApi__ReloadPointCloud(model = Sketchup.active_model)
        session = self.na_api_session(model)
        return 'The point cloud viewer is not available for this model.' unless session
        return 'A point cloud task is already running.' if Na__AsyncJobs.Na__Jobs__Busy?
        return 'This model has no point cloud link to reload.' if Na__CloudSet.Na__Slots__All(session).none?(&:record)
        self.Na__PublicApi__OpenDialog
        Na__ModelLink.Na__Link__ReloadAll(session)
    rescue StandardError => error
        Na__DebugTools.Na__Debug__Error('Public API: Reload Point Cloud could not start.', error)
        "Reload Point Cloud could not start (#{error.message})."
    end

    # API 4: one cloud of the model, as other plugins see it.
    def self.na_api_cloud(slot)
        link = slot.record ? slot.record['link'] : nil
        {
            'id'          => slot.id,
            'name'        => slot.name,
            'colour'      => Na__CloudSet.Na__Slots__HexColour(slot.colour),
            'loaded'      => slot.cloud && slot.cloud.native_cloud ? true : false,
            'visible'     => slot.visible ? true : false,
            'linked'      => %w[saved legacy].include?(slot.record_state),
            'fileName'    => link ? link['fileName'] : (slot.cloud ? slot.cloud.label : nil),
            'contentKey'  => link ? link['contentKey'] : nil,
            'totalPoints' => slot.cloud ? slot.cloud.total_points : (link ? link['pointCount'] : nil),
            'sourceUnit'  => slot.cloud ? slot.cloud.source_unit : (link ? link['sourceUnit'] : nil)
        }
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
