# =============================================================================
# NA POINT CLOUD VIEWER - SCENES - RECALL AND DIALOG PAYLOAD
# =============================================================================
#
# FILE       : Na__PointCloudViewer__Scenes__Recall__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__SceneRecall
# PURPOSE    : Pressing a point cloud scene: SketchUp moves to its scene, then
#              the viewer takes back everything the scene holds: the point
#              budget and the overlay switch, and for every cloud whether it is
#              shown, its dot size, opacity and colour, and its clip box. Also
#              builds the Scenes tab's payload.
#
# ORDER: the SketchUp scene is selected first with the user's own transition
#   setting (an interactive recall may animate; nothing here waits for it). The
#   viewer settings are applied at once and do not depend on the camera. Clip
#   boxes are model data, so changing them is ONE undoable operation for every
#   cloud whose box changes; unchanged boxes write nothing.
#
# TWO WAYS IN (v0.12.0): Go To Scene (Recall) selects the SketchUp scene and
#   then applies it; pressing the SketchUp scene tab itself (Na__SceneFollow)
#   finds the scene already shown and only applies it. Both use
#   Na__Scenes__Apply, so they can never differ.
#
# SEVERAL CLOUDS (v0.10.0): a cloud the scene does not know (added to the
#   model after the scene was saved) is hidden, so the viewport shows what the
#   scene's exported picture shows. The card says so and Update adds it.
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
                Na__SceneFollow.Na__Follow__Expect(scene.dig('page', 'pid')) if defined?(Na__SceneFollow)
                model.pages.selected_page = page
            rescue StandardError => error
                return "SketchUp could not show the scene \"#{page.name}\" (#{error.message}). Nothing was changed."
            ensure
                Na__SceneFollow.Na__Follow__Expect(nil) if defined?(Na__SceneFollow)
            end

            self.Na__Scenes__Apply(session, scene, page, view)
        end

        # Everything the scene holds, given back to the viewer, WITHOUT
        # selecting the SketchUp scene: Recall has just selected it, and
        # following a scene tab (Na__SceneFollow) finds it already shown.
        # Returns nil, or a plain-English reason (shown as a warning).
        def self.Na__Scenes__Apply(session, scene, page, view)
            settings = scene['settings'] || {}
            Na__RenderController.Na__Render__ApplySettings(session, { 'pointBudget' => settings['pointBudget'] }, view)
            entries = scene['clouds'] || {}
            changed_clips = []
            Na__CloudSet.Na__Slots__All(session).each do |slot|
                entry = entries[slot.id]
                unless entry
                    slot.visible = false
                    next
                end
                slot.visible = entry['visible'] != false
                Na__CloudSet.Na__Slots__ApplyDisplay(slot, entry['display']) if entry['display'].is_a?(Hash)
                changed_clips << slot if self.na_take_clip(slot, entry['clip'])
            end
            Na__ModelRegistry.Na__Registry__SetVisible(settings['overlayOn'] != false)
            problem = self.na_save_clips(session, changed_clips, page.name.to_s)
            Na__RenderController.Na__Render__RefreshExtents(session)
            session.scene_active_id = scene['id'] unless problem
            problem
        end

        # The scene's clip box for one cloud, into the slot (not saved yet).
        # No box saved means clipping off (the box itself is kept, as Full
        # Cloud does). Returns true when the slot's box changed.
        def self.na_take_clip(slot, wanted)
            Na__ClipBox.Na__Clip__Ensure(slot)
            Na__ClipBox.Na__Clip__StopEditing(slot) if slot.clip_editing
            current = slot.clip
            if wanted.nil?
                return false if current.nil? || !current['enabled']
                slot.clip = current.merge('enabled' => false)
                return true
            end
            same = current && (current['enabled'] ? true : false) == (wanted['enabled'] ? true : false) &&
                   (0..2).all? { |i| (current['min'][i] - wanted['min'][i]).abs < 1e-6 && (current['max'][i] - wanted['max'][i]).abs < 1e-6 }
            return false if same
            slot.clip = { 'enabled' => wanted['enabled'] ? true : false, 'min' => wanted['min'].dup, 'max' => wanted['max'].dup }
            slot.clip_active_scene = nil
            true
        end

        # Every changed clip box in ONE undoable operation.
        def self.na_save_clips(session, slots, name)
            return nil if slots.empty?
            problem = Na__CloudStore.Na__Store__WriteSlots(session, slots, "Point Cloud: Scene #{name}") do |slot, record|
                record.merge!(Na__ClipBox.Na__Clip__Part(slot))
            end
            slots.each { |slot| Na__ClipBox.Na__Clip__Load(slot) } if problem
            slots.each { |slot| Na__CleanPreview.Na__Clean__Changed(slot) } if !problem && defined?(Na__CleanPreview)
            problem
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
            slots        = Na__CloudSet.Na__Slots__All(session)
            display      = Na__UnitContract.Na__Units__ModelDisplay(model)

            {
                'isAvailable'       => true,
                'hasCloud'          => slots.any?(&:cloud),
                'cloudCount'        => slots.length,
                'readonly'          => session.scenes_readonly ? true : false,
                'problem'           => session.scenes_problem,
                'activeId'          => session.scene_active_id,
                'followSceneTabs'   => defined?(Na__SceneFollow) ? Na__SceneFollow.Na__Follow__Enabled? : false,
                'revision'          => (session.scenes_meta || {})['revision'].to_i,
                'pages'             => pages.map do |info|
                    info.merge('isBound' => bound_pids.include?(info['pid']), 'isSelected' => info['pid'] == selected_pid)
                end,
                'scenes'            => session.scenes.map do |scene|
                    self.na_scene_payload(session, scene, by_pid, bound_pids, pages, selected_pid, slots, display, view)
                end,
                'viewTypes'         => Na__SceneStore.Na__Scenes__ViewTypes,
                'scalePresets'      => Na__SceneStore.Na__Scenes__ScalePresets,
                'imageWidthPresets' => Na__SceneStore.Na__Scenes__ImageWidthPresets,
                'pointSizeMaxPx'    => (Na__SceneStore.Na__Scenes__Config('exportPointSizeMaxPx') || 32).to_i,
                'pxPerPaperMm'      => (Na__SceneStore.Na__Scenes__Config('export', 'pxPerPaperMm') || 12).to_f,
                'currentSummary'    => self.na_current_summary(session, view, display)
            }
        end

        # What Update would save right now, in the same words as a scene's
        # summary, so the Update confirmation can show saved against new.
        def self.na_current_summary(session, view, display)
            self.na_summary(session, Na__SceneStore.Na__Scenes__Capture(session, view), display)
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Warn("The current point cloud settings could not be summarised: #{error.message}")
            nil
        end

        def self.na_scene_payload(session, scene, by_pid, bound_pids, pages, selected_pid, slots, display, view)
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
            entries     = scene['clouds'] || {}
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
                'clouds'             => slots.map do |slot|
                    entry = entries[slot.id]
                    { 'id' => slot.id, 'name' => slot.name, 'colour' => Na__CloudSet.Na__Slots__HexColour(slot.colour),
                      'known' => !entry.nil?, 'visible' => entry ? entry['visible'] != false : false }
                end,
                'opacityPercent'     => Na__SceneStore.Na__Scenes__DefaultOpacity(scene),
                'warnings'           => self.na_warnings(scene, info, status, slots),
                'isActive'           => active,
                'isModified'         => active && status != 'missing' && Na__SceneStore.Na__Scenes__Differs?(session, scene, view),
                'summary'            => self.na_summary(session, scene, display),
                'updatedText'        => self.na_time_text(scene['updatedEpoch'])
            }
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Warn("A point cloud scene could not be shown: #{error.message}")
            { 'id' => scene['id'], 'name' => scene.dig('page', 'name').to_s, 'status' => 'missing', 'warnings' => [], 'summary' => '', 'clouds' => [] }
        end

        # Plain sentences, no dashes. Each one is something the user can act on.
        def self.na_warnings(scene, info, status, slots)
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
            entries = scene['clouds'] || {}
            slots.each do |slot|
                entry = entries[slot.id]
                if entry.nil?
                    list << "Saved before #{slot.name} was added to the model, so it is hidden in this scene. Update the scene to include it." if slots.length > 1
                    next
                end
                saved = entry['identity'] || {}
                link = slot.record ? slot.record['link'] : nil
                if saved['contentKey'] && link && link['contentKey'] && saved['contentKey'] != link['contentKey']
                    who = slots.length > 1 ? "#{slot.name} used" : 'the model used'
                    list << "Saved while #{who} #{saved['fileName']}; it now uses #{link['fileName']}. The settings still apply."
                end
            end
            gone = entries.keys - slots.map(&:id)
            visible_gone = gone.select { |id| entries[id]['visible'] != false }
            unless visible_gone.empty?
                names = visible_gone.map { |id| (entries[id]['identity'] || {})['name'] }.compact.reject(&:empty?)
                list << "Shows #{visible_gone.length == 1 ? 'a point cloud' : "#{visible_gone.length} point clouds"} no longer in this model#{names.empty? ? '' : " (#{names.join(', ')})"}; left out of its picture."
            end
            list << 'Shows no point cloud. Switch one on and update the scene, or it exports an empty picture.' if status != 'missing' && slots.any? && entries.none? { |id, entry| entry['visible'] != false && slots.any? { |slot| slot.id == id } }
            list
        end

        # One cloud: "RGB, 2 px dots, 100 % opacity, clip on (12.0 x 8.0 x 2.4 m)".
        # Several: each cloud by name, then the shared budget. A model with one
        # cloud reads exactly as before v0.10.0.
        def self.na_summary(session, scene, display)
            settings = scene['settings'] || {}
            entries  = scene['clouds'] || {}
            slots    = Na__CloudSet.Na__Slots__All(session)
            budget   = "#{self.na_int_text(settings['pointBudget'])} point budget"
            if slots.length <= 1
                entry = slots.first ? entries[slots.first.id] : entries.values.first
                return "#{budget}." unless entry
                look = entry['display'] || {}
                parts = ["#{self.na_colour_label(look['colourMode'])}, #{look['pointSizePx']} px dots, #{look['opacityPercent']} % opacity, #{budget}"]
                parts << 'Cloud hidden' if settings['overlayOn'] == false || entry['visible'] == false
                parts << self.na_clip_text(entry['clip'])
                return "#{parts.join('. ')}."
            end
            parts = slots.map do |slot|
                entry = entries[slot.id]
                next "#{slot.name}: not in this scene (hidden)" unless entry
                next "#{slot.name}: hidden" if entry['visible'] == false
                look = entry['display'] || {}
                "#{slot.name}: #{self.na_colour_label(look['colourMode'])}, #{look['pointSizePx']} px dots, #{look['opacityPercent']} % opacity, " \
                    "#{self.na_clip_text(entry['clip']).sub(/\A(\w)/) { Regexp.last_match(1).downcase }}"
            end
            parts << "#{budget}, shared by the clouds on show"
            parts << 'All clouds hidden (overlay off)' if settings['overlayOn'] == false
            "#{parts.join('. ')}."
        end

        def self.na_colour_label(mode)
            case mode
            when 'black'   then 'Monochrome'
            when 'primary' then 'Primary colour'
            else 'RGB'
            end
        end

        def self.na_clip_text(clip)
            return 'No clip box' if clip.nil?
            size = (0..2).map { |i| format('%.1f', (clip['max'][i] - clip['min'][i]).to_f * 0.0254) }.join(' x ')
            "Clip #{clip['enabled'] ? 'on' : 'off'} (#{size} m)"
        end

        def self.na_int_text(value)
            value.to_i.to_s.reverse.scan(/\d{1,3}/).join(',').reverse
        end

        def self.na_time_text(epoch)
            epoch.to_f > 0 ? Time.at(epoch.to_f).strftime('Saved %d %b %Y %H:%M') : ''
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
