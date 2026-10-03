# =============================================================================
# NA POINT CLOUD VIEWER - VIEWPORT - CLOUD OVERLAY
# =============================================================================
#
# FILE       : Na__PointCloudViewer__Viewport__CloudOverlay__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__CloudOverlay
# PURPOSE    : The Sketchup::Overlay subclass - one instance per model.
#
# WHY AN OVERLAY:
#   An overlay draws in every tool (Line, Push/Pull, Move, Tape...) without a
#   custom tool being active, is never pickable, never feeds inference and is
#   never exported. That is exactly the "3D reference image" behaviour wanted.
#
# THIN BY DESIGN:
#   Every method delegates to a module function. On hot reload the class is
#   reopened in place, so overlays already added to open models run the new
#   code immediately - nothing is removed or re-added, nothing leaks.
#
# =============================================================================

module Na__PointCloudViewer

    if defined?(Sketchup::Overlay)

        class Na__CloudOverlay < Sketchup::Overlay

            attr_reader :na_session

            def initialize
                super(
                    Na__ModelRegistry.Na__Registry__OverlayId,
                    Na__ConfigLoader.Na__Config__GetOr('Na Point Cloud Viewer', 'overlay', 'name'),
                    description: Na__ConfigLoader.Na__Config__GetOr('', 'overlay', 'description')
                )
                @na_session = Na__CloudSession.new
            end

            def draw(view)
                Na__RenderController.Na__Render__Draw(@na_session, view)
            end

            # Must cover every drawn point or SketchUp's near/far planes clip
            # the cloud. Returns a cached BoundingBox - no allocation per call.
            def getExtents
                Na__RenderController.Na__Render__Extents(@na_session)
            end

            def start
                Na__ModelRegistry.Na__Registry__OnOverlayToggled(self, true)
            end

            def stop
                Na__ModelRegistry.Na__Registry__OnOverlayToggled(self, false)
            end

        end

    end

end

# =============================================================================
# END OF FILE
# =============================================================================
