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
#   Overlay#draw -> Na__Render__Draw: the cloud as one textured quad (see
#   ImageRenderer), then the clip box cage while it is being edited, then the
#   Move gimbal or Rotate protractor while one of them is active. Nothing here
#   parses, sorts or allocates points.
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
            Na__ImageRenderer.Na__Image__Draw(session, view) if session.cloud
            Na__ClipBox.Na__Clip__DrawCage(session, view) if session.clip_editing
            session.transform_tool.na_draw_overlay(view) if session.transform_tool
        rescue StandardError => error
            session.fault = "#{error.class}: #{error.message}"
            Na__DebugTools.Na__Debug__Error('Point cloud drawing failed and has been paused. Change a setting or reload the plugin to retry.', error)
        end

        def self.Na__Render__Extents(session)
            session.extents || session.empty_bounds
        end

        # Cloud bounds, plus the clip box while its cage is drawn and the
        # points a transform tool draws at, so the camera's near and far
        # planes never cut any of them off.
        def self.Na__Render__RefreshExtents(session)
            box = Geom::BoundingBox.new
            box.add(session.cloud.bounds.min, session.cloud.bounds.max) if session.cloud && session.cloud.bounds
            if session.clip_editing && session.clip
                box.add(Geom::Point3d.new(*session.clip['min']), Geom::Point3d.new(*session.clip['max']))
            end
            extra = session.transform_tool ? session.transform_tool.na_extent_points : []
            box.add(*extra) unless extra.empty?
            session.extents = box.empty? ? nil : box
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | State Changes (outside draw)
    # -------------------------------------------------------------------------

        def self.Na__Render__InstallCloud(session, cloud, view)
            self.na_release_native(session, view)
            session.cloud = cloud
            session.fault = nil
            self.Na__Render__RefreshExtents(session)
            view.invalidate if view
        end

        def self.Na__Render__ClearCloud(session, view)
            Na__Placement.Na__Placement__Detach(session)
            self.na_release_native(session, view)
            session.cloud = nil
            session.fault = nil
            self.Na__Render__RefreshExtents(session)
            view.invalidate if view
        end

        # Returns the list of keys that actually changed.
        def self.Na__Render__ApplySettings(session, partial, view)
            before = session.settings
            after  = Na__RenderSettings.Na__Settings__Merge(before, partial)
            session.settings = after
            session.fault    = nil
            view.invalidate if view
            changed = Na__RenderSettings.Na__Settings__ChangedKeys(before, after)
            Na__UserConfigStore.Na__UserConfig__Set('render', 'lastSettings', after) unless changed.empty?
            changed
        end

        # Keeps the current view direction and frames what is visible: the
        # cloud, or only the part inside the clip box while clipping is on.
        def self.Na__Render__ZoomToCloud(session, view)
            return false unless session && session.cloud && session.cloud.bounds
            camera = view.camera
            bounds = self.na_visible_bounds(session)
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

        def self.na_visible_bounds(session)
            bounds = session.cloud.bounds
            return bounds unless Na__ClipBox.Na__Clip__IsActive?(session)
            cloud_min = bounds.min.to_a
            cloud_max = bounds.max.to_a
            lo = (0..2).map { |i| [cloud_min[i], session.clip['min'][i]].max }
            hi = (0..2).map { |i| [cloud_max[i], session.clip['max'][i]].min }
            return bounds unless (0..2).all? { |i| hi[i] > lo[i] }
            Geom::BoundingBox.new.add(Geom::Point3d.new(*lo), Geom::Point3d.new(*hi))
        end

        # Texture + engine memory of the outgoing cloud, freed now rather than
        # whenever Ruby's GC gets round to it (a LAS cloud is hundreds of MB).
        def self.na_release_native(session, view)
            Na__ImageRenderer.Na__Image__Release(session, view)
            old = session.cloud
            Na__NativeEngine.Na__Native__CloudRelease(old.native_cloud) if old && old.native_cloud
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
