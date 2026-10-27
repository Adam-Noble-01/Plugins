# =============================================================================
# NA POINT CLOUD VIEWER - VIEWPORT - RENDER CONTROLLER
# =============================================================================
#
# FILE       : Na__PointCloudViewer__Viewport__RenderController__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__RenderController
# PURPOSE    : The overlay's draw path, plus the entry points that change what
#              it draws (install/clear a cloud, apply settings, zoom, extents).
#
# DRAW CONTRACT (performance-critical):
#   Overlay#draw -> Na__Render__Draw: every cloud on show as one textured quad
#   (see ImageRenderer), then the active cloud's Crop and Cut boxes while the
#   Clean tab shows them, then the clip box cage of the cloud being edited,
#   then the box the Draw Clip Box tool is drawing (v0.13.0), then the Move
#   gimbal or Rotate protractor while one of them is active, then (with
#   several clouds) the label naming the cloud the tool works on.
#   Nothing here parses, sorts or allocates points.
#
# NO SNAPPING:
#   Overlays are not pickable and do not feed the inference engine. Nothing
#   here creates entities, InputPoints or pick targets.
#
# =============================================================================

module Na__PointCloudViewer
    module Na__RenderController

    # -------------------------------------------------------------------------
    # REGION | Draw (called by Overlay#draw - keep minimal)
    # -------------------------------------------------------------------------

        def self.Na__Render__Draw(session, view)
            return if session.fault
            slots = Na__CloudSet.Na__Slots__All(session)
            Na__ImageRenderer.Na__Image__Draw(session, view) if slots.any? { |slot| slot.visible && slot.cloud }
            Na__CleanBoxes.Na__Boxes__DrawCages(session, view)
            slots.each { |slot| Na__ClipBox.Na__Clip__DrawCage(slot, view) if slot.clip_editing }
            session.clip_draw_tool.na_draw_overlay(view) if session.clip_draw_tool
            session.transform_tool.na_draw_overlay(view) if session.transform_tool
            Na__CloudSet.Na__Slots__DrawToolLabel(session, view) if slots.length > 1
        rescue StandardError => error
            session.fault = "#{error.class}: #{error.message}"
            Na__DebugTools.Na__Debug__Error('Point cloud drawing failed and has been paused. Change a setting or reload the plugin to retry.', error)
        end

        def self.Na__Render__Extents(session)
            session.extents || session.empty_bounds
        end

        # Every cloud on show, plus the clip box while its cage is drawn, the
        # Crop and Cut boxes while they are drawn and the points a transform
        # tool or the Draw Clip Box tool draws at, so the camera's near and far
        # planes never cut any of them off.
        def self.Na__Render__RefreshExtents(session)
            return unless session
            box = Geom::BoundingBox.new
            Na__CloudSet.Na__Slots__All(session).each do |slot|
                box.add(slot.cloud.bounds.min, slot.cloud.bounds.max) if slot.visible && slot.cloud && slot.cloud.bounds
                if slot.clip_editing && slot.clip
                    box.add(Geom::Point3d.new(*slot.clip['min']), Geom::Point3d.new(*slot.clip['max']))
                end
                corners = Na__CleanBoxes.Na__Boxes__ExtentPoints(slot)
                box.add(*corners) unless corners.empty?
            end
            extra = session.transform_tool ? session.transform_tool.na_extent_points : []
            extra += session.clip_draw_tool.na_extent_points if session.clip_draw_tool
            box.add(*extra) unless extra.empty?
            session.extents = box.empty? ? nil : box
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | State Changes (outside draw)
    # -------------------------------------------------------------------------

        def self.Na__Render__InstallCloud(slot, cloud, view)
            Na__CleanPreview.Na__Clean__Reset(slot) if defined?(Na__CleanPreview)
            self.na_release_native(slot)
            slot.cloud = cloud
            slot.session.fault = nil
            self.Na__Render__RefreshExtents(slot.session)
            view.invalidate if view
        end

        def self.Na__Render__ClearCloud(slot, view)
            Na__CleanPreview.Na__Clean__Reset(slot) if defined?(Na__CleanPreview)
            Na__Placement.Na__Placement__Detach(slot)
            self.na_release_native(slot)
            slot.cloud = nil
            slot.layer_stats = nil
            session = slot.session
            session.fault = nil
            Na__ImageRenderer.Na__Image__Release(session, view) if Na__CloudSet.Na__Slots__Loaded(session).empty?
            self.Na__Render__RefreshExtents(session)
            view.invalidate if view
        end

        # The shared point budget goes to the session; the look (size, opacity,
        # colour) to `slot`, the cloud being set up (the active one). Both are
        # remembered for this user. Returns the list of keys that changed.
        def self.Na__Render__ApplySettings(session, partial, view, slot = nil)
            partial = {} unless partial.is_a?(Hash)
            before = session.settings
            after  = Na__RenderSettings.Na__Settings__Merge(before, partial)
            session.settings = after
            session.fault    = nil
            changed = Na__RenderSettings.Na__Settings__ChangedKeys(before, after)
            changed &= Na__RenderSettings::NA_SHARED_KEYS if slot
            if slot
                display_part = partial.select { |key, _| Na__RenderSettings::NA_DISPLAY_KEYS.include?(key) }
                changed |= Na__CloudSet.Na__Slots__ApplyDisplay(slot, display_part) unless display_part.empty?
            end
            Na__UserConfigStore.Na__UserConfig__Set('render', 'lastSettings', after) unless changed.empty?
            view.invalidate if view
            changed
        end

        # Keeps the current view direction and frames what is visible: the
        # cloud, or only the part inside its clip box while clipping is on.
        # slots: the clouds to frame (one, or every cloud on show).
        def self.Na__Render__ZoomToCloud(session_or_slot, view, slots = nil)
            slots ||= session_or_slot.is_a?(Na__CloudSlot) ? [session_or_slot] : Na__CloudSet.Na__Slots__Drawn(session_or_slot)
            boxes = Array(slots).select { |slot| slot && slot.cloud && slot.cloud.bounds }.map { |slot| self.na_visible_bounds(slot) }.compact
            return false if boxes.empty?
            bounds = Geom::BoundingBox.new
            boxes.each { |box| bounds.add(box.min, box.max) }
            camera = view.camera
            centre = bounds.center
            radius = bounds.diagonal.to_f / 2.0
            back   = camera.direction.reverse
            if camera.perspective?
                half_fov = (camera.fov.to_f / 2.0) * Math::PI / 180.0
                eye = centre.offset(back, radius / Math.sin(half_fov) * 1.05)
                view.camera = Sketchup::Camera.new(eye, centre, camera.up, true, camera.fov)
            else
                eye = centre.offset(back, radius * 3.0)
                parallel = Sketchup::Camera.new(eye, centre, camera.up, false)
                parallel.height = radius * 2.1
                view.camera = parallel
            end
            true
        end

        # The cloud's model box, cut by its clip box while clipping is on.
        def self.na_visible_bounds(slot)
            bounds = slot.cloud.bounds
            return bounds unless Na__ClipBox.Na__Clip__IsActive?(slot)
            cloud_min = bounds.min.to_a
            cloud_max = bounds.max.to_a
            lo = (0..2).map { |i| [cloud_min[i], slot.clip['min'][i]].max }
            hi = (0..2).map { |i| [cloud_max[i], slot.clip['max'][i]].min }
            return bounds unless (0..2).all? { |i| hi[i] > lo[i] }
            Geom::BoundingBox.new.add(Geom::Point3d.new(*lo), Geom::Point3d.new(*hi))
        end

        # Engine memory of the outgoing cloud, freed now rather than whenever
        # Ruby's GC gets round to it (a LAS cloud is hundreds of MB).
        def self.na_release_native(slot)
            old = slot.cloud
            Na__NativeEngine.Na__Native__CloudRelease(old.native_cloud) if old && old.native_cloud
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
