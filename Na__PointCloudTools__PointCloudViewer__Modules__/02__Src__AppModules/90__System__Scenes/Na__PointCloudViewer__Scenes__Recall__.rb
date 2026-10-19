# =============================================================================
# NA POINT CLOUD VIEWER - SCENES - RECALL AND DIALOG PAYLOAD
# =============================================================================
#
# FILE       : Na__PointCloudViewer__Scenes__Recall__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__SceneRecall
# PURPOSE    : Pressing a point cloud scene: SketchUp moves to its scene, then
#              the viewer takes back every setting the scene holds (point
#              budget, size, opacity, colour, show or hide, clip box). Also
#              builds the Scenes tab's payload.
#
# ORDER: the SketchUp scene is selected first with the user's own transition
#   setting (an interactive recall may animate; nothing here waits for it). The
#   viewer settings are applied at once and do not depend on the camera. The
#   clip box is model data, so changing it is ONE undoable operation; an
#   unchanged clip box writes nothing.
#
# READ ONLY ON THE SKETCHUP SIDE: selecting a scene is the only thing done to
#   SketchUp, exactly as clicking its tab would. The scene is never updated.
#
# =============================================================================

module Na__PointCloudViewer
    module Na__SceneRecall

    # -------------------------------------------------------------------------
    # REGION | Recall
    # -------------------------------------------------------------------------

        # Returns nil, or a plain-English reason (shown as a warning).
        def self.Na__Scenes__Recall(session, scene_id, view)
            scene = Na__SceneStore.Na__Scenes__Find(session, scene_id)
            return 'That point cloud scene no longer exists.' unless scene
            model = session.model
            page = Na__SceneStore.Na__Scenes__ResolvePage(model, scene)
            unless page
                return "The SketchUp scene \"#{scene.dig('page', 'name')}\" no longer exists, so nothing was changed. " \
                       'Relink this point cloud scene to another SketchUp scene, or remove it.'
            end

            begin
                model.pages.selected_page = page
            rescue StandardError => error
                return "SketchUp could not show the scene \"#{page.name}\" (#{error.message}). Nothing was changed."
            end

            settings = scene['settings']
            Na__RenderController.Na__Render__ApplySettings(session, settings.slice(*Na__SceneStore::NA_SETTING_KEYS), view)
            Na__ModelRegistry.Na__Registry__SetVisible(settings['visible'] != false)
            self.na_apply_clip(session, scene, page.name.to_s)
            session.scene_active_id = scene['id']
            nil
        end

        # The scene's clip box replaces the current one. No box saved with the
        # scene means clipping off (the box itself is kept, as Full Cloud does).
        def self.na_apply_clip(session, scene, name)
            Na__ClipBox.Na__Clip__Ensure(session)
            Na__ClipBox.Na__Clip__StopEditing(session) if session.clip_editing
            wanted  = scene['clip']
            current = session.clip
            if wanted.nil?
                return if current.nil? || !current['enabled']
                session.clip['enabled'] = false
            else
                same = current && (current['enabled'] ? true : false) == wanted['enabled'] &&
                       (0..2).all? { |i| (current['min'][i] - wanted['min'][i]).abs < 1e-6 && (current['max'][i] - wanted['max'][i]).abs < 1e-6 }
                return if same
                session.clip = { 'enabled' => wanted['enabled'] ? true : false, 'min' => wanted['min'].dup, 'max' => wanted['max'].dup }
                session.clip_active_scene = nil
            end
            Na__ClipBox.Na__Clip__Save(session, "Point Cloud: Scene #{name}")
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Dialog Payload
    # -------------------------------------------------------------------------

        def self.Na__Scenes__Payload(session, model, view)
            return { 'isAvailable' => false } unless session && model
            Na__SceneStore.Na__Scenes__Ensure(session)
            pages        = Na__SceneStore.Na__Scenes__AllPages(model)
            by_pid       = pages.each_with_object({}) { |info, hash| hash[info['pid']] = info }
            bound_pids   = session.scenes.map { |scene| scene.dig('page', 'pid').to_i }
            selected_pid = Na__SceneStore.Na__Scenes__SelectedPagePid(model)
            link_cloud   = self.na_link_cloud(model)
            display      = Na__UnitContract.Na__Units__ModelDisplay(model)

            {
                'isAvailable'       => true,
                'hasCloud'          => !session.cloud.nil?,
                'readonly'          => session.scenes_readonly ? true : false,
                'problem'           => session.scenes_problem,
                'activeId'          => session.scene_active_id,
                'revision'          => (session.scenes_meta || {})['revision'].to_i,
                'pages'             => pages.map do |info|
                    info.merge('isBound' => bound_pids.include?(info['pid']), 'isSelected' => info['pid'] == selected_pid)
                end,
                'scenes'            => session.scenes.map do |scene|
                    self.na_scene_payload(session, scene, by_pid, bound_pids, pages, selected_pid, link_cloud, display, view)
                end,
                'viewTypes'         => Na__SceneStore.Na__Scenes__ViewTypes,
                'scalePresets'      => Na__SceneStore.Na__Scenes__ScalePresets,
                'imageWidthPresets' => Na__SceneStore.Na__Scenes__ImageWidthPresets,
                'pointSizeMaxPx'    => (Na__SceneStore.Na__Scenes__Config('exportPointSizeMaxPx') || 32).to_i,
                'pxPerPaperMm'      => (Na__SceneStore.Na__Scenes__Config('export', 'pxPerPaperMm') || 12).to_f
            }
        end

        def self.na_scene_payload(session, scene, by_pid, bound_pids, pages, selected_pid, link_cloud, display, view)
            pid    = scene.dig('page', 'pid').to_i
            info   = by_pid[pid]
            status = if info.nil? then 'missing'
                     elsif !info['usesCamera'] then 'noCamera'
                     else 'linked'
                     end
            suggestion = nil
            if status == 'missing'
                hint = scene.dig('page', 'name').to_s
                suggestion = pages.find { |page| !bound_pids.include?(page['pid']) && page['name'].casecmp?(hint) }
            end
            perspective = info ? info['perspective'] : scene.dig('export', 'scale').nil?
            active      = session.scene_active_id == scene['id']
            scale       = scene.dig('export', 'scale')
            {
                'id'                 => scene['id'],
                'name'               => info ? info['name'] : scene.dig('page', 'name').to_s,
                'status'             => status,
                'relinkPid'          => suggestion ? suggestion['pid'] : nil,
                'relinkName'         => suggestion ? suggestion['name'] : nil,
                'isSelectedInSketchUp' => pid == selected_pid,
                'viewType'           => scene['viewType'],
                'viewTypeLabel'      => Na__SceneStore.Na__Scenes__ViewTypeLabel(scene['viewType']),
                'projection'         => perspective ? 'perspective' : 'parallel',
                'scale'              => scale,
                'scaleLabel'         => scale ? Na__SceneStore.Na__Scenes__ScaleLabel(scale) : nil,
                'imageWidthPx'       => scene.dig('export', 'imageWidthPx'),
                'pointSizePx'        => scene.dig('export', 'pointSizePx'),
                'exportPointSizePx'  => Na__SceneStore.Na__Scenes__ExportPointSize(scene, perspective),
                'warnings'           => self.na_warnings(scene, info, status, link_cloud),
                'isActive'           => active,
                'isModified'         => active && status != 'missing' && Na__SceneStore.Na__Scenes__Differs?(session, scene, view),
                'summary'            => self.na_summary(scene, display),
                'updatedText'        => self.na_time_text(scene['updatedEpoch'])
            }
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Warn("A point cloud scene could not be shown: #{error.message}")
            { 'id' => scene['id'], 'name' => scene.dig('page', 'name').to_s, 'status' => 'missing', 'warnings' => [], 'summary' => '' }
        end

        # Plain sentences, no dashes. Each one is something the user can act on.
        def self.na_warnings(scene, info, status, link_cloud)
            list = []
            if status == 'noCamera'
                list << 'This SketchUp scene does not save a camera position, so it cannot be exported. Tick Camera Location in its scene properties and update the scene.'
            end
            if info && status != 'missing'
                dz = info['direction'] ? info['direction'][2].to_f : 0.0
                case scene['viewType']
                when 'plan', 'siteplan'
                    noun = scene['viewType'] == 'siteplan' ? 'site plan' : 'plan'
                    list << "A #{noun} needs Parallel Projection. This scene is in perspective." if info['perspective']
                    list << "A #{noun} should look straight down. This scene's camera is tilted, so the image will not sit square on a #{noun} drawing." if !info['perspective'] && dz > -0.9999
                when 'elevation'
                    list << 'An elevation needs Parallel Projection. This scene is in perspective.' if info['perspective']
                    list << 'An elevation should look level. This scene\'s camera is tilted, so the image will not sit square on an elevation.' if !info['perspective'] && dz.abs > 1e-4
                when 'section'
                    list << 'A section needs Parallel Projection. This scene is in perspective.' if info['perspective']
                end
            end
            saved = scene['cloud']
            if saved && link_cloud && saved['contentKey'] && link_cloud['contentKey'] && saved['contentKey'] != link_cloud['contentKey']
                list << "Saved while the model used #{saved['fileName']}; it now uses #{link_cloud['fileName']}. The settings still apply."
            end
            list
        end

        def self.na_summary(scene, display)
            settings = scene['settings']
            colour = settings['colourMode'] == 'black' ? 'Monochrome' : 'RGB'
            parts = ["#{colour}, #{settings['pointSizePx']} px dots, #{settings['opacityPercent']} % opacity, " \
                     "#{self.na_int_text(settings['pointBudget'])} point budget"]
            parts << 'Cloud hidden' if settings['visible'] == false
            clip = scene['clip']
            if clip.nil?
                parts << 'No clip box'
            else
                size = (0..2).map { |i| format('%.1f', (clip['max'][i] - clip['min'][i]).to_f * 0.0254) }.join(' x ')
                parts << "Clip #{clip['enabled'] ? 'on' : 'off'} (#{size} m)"
            end
            "#{parts.join('. ')}."
        end

        def self.na_int_text(value)
            value.to_i.to_s.reverse.scan(/\d{1,3}/).join(',').reverse
        end

        def self.na_time_text(epoch)
            epoch.to_f > 0 ? Time.at(epoch.to_f).strftime('Saved %d %b %Y %H:%M') : ''
        end

        def self.na_link_cloud(model)
            link = Na__ModelLink.Na__Link__Read(model)
            link ? link['cloud'] : nil
        rescue StandardError
            nil
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
