# =============================================================================
# NA PROFILE TOOLS - APPLY PROFILE - SCENE PROFILE PICKER
# =============================================================================
#
# FILE       : Na__ProfileTools__ApplyProfile__SceneProfilePicker__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__SceneProfilePicker
# PURPOSE    : Tool for picking scene geometry as profile source
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer
    class Na__SceneProfilePicker

    # -------------------------------------------------------------------------
    # REGION | Initialization
    # -------------------------------------------------------------------------

        def initialize(dialog_manager)
            @na_dialog_manager = dialog_manager
            @na_hover_entity = nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Tool Lifecycle
    # -------------------------------------------------------------------------

        def activate
            Sketchup.status_text = 'Profile Path Tracer: Click a Group/Component with one planar face | ESC to cancel'
            Sketchup.active_model.active_view.invalidate
        end

        def deactivate(view)
            view.invalidate if view
        end

        def onCancel(_reason, _view)
            if @na_dialog_manager.respond_to?(:Na__Dialog__SetStatusFromRuby)
                @na_dialog_manager.Na__Dialog__SetStatusFromRuby('Scene profile pick cancelled.')
            end
            Sketchup.active_model.select_tool(nil)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Mouse Events
    # -------------------------------------------------------------------------

        def onMouseMove(_flags, x, y, view)
            @na_hover_entity = self.Na__SceneProfilePicker__PickTopLevelInstance(view, x, y)
            view.invalidate
        end

        def onLButtonDown(_flags, x, y, view)
            picked_entity = self.Na__SceneProfilePicker__PickTopLevelInstance(view, x, y)
            unless picked_entity
                UI.beep
                @na_dialog_manager.Na__Dialog__SetStatusFromRuby('Pick a top-level Group or Component.') if @na_dialog_manager.respond_to?(:Na__Dialog__SetStatusFromRuby)
                return
            end

            result = Na__SceneProfileRegistry.Na__SceneProfileRegistry__SetFromEntity(picked_entity)
            if result['isValid']
                @na_dialog_manager.Na__Dialog__PushSceneProfileStatus if @na_dialog_manager.respond_to?(:Na__Dialog__PushSceneProfileStatus)
                @na_dialog_manager.Na__Dialog__SetStatusFromRuby(result['statusMessage']) if @na_dialog_manager.respond_to?(:Na__Dialog__SetStatusFromRuby)
            else
                UI.beep
                @na_dialog_manager.Na__Dialog__SetStatusFromRuby(result['reason']) if @na_dialog_manager.respond_to?(:Na__Dialog__SetStatusFromRuby)
            end

            view.invalidate
            Sketchup.active_model.select_tool(nil)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Draw
    # -------------------------------------------------------------------------

        def draw(view)
            return unless @na_hover_entity && @na_hover_entity.valid?

            bounds = @na_hover_entity.bounds
            return if bounds.nil? || bounds.empty?

            view.line_width = 2
            view.drawing_color = Sketchup::Color.new(74, 144, 217, 220)
            self.Na__SceneProfilePicker__DrawBoundingBoxWireframe(view, bounds)
        end

        def getExtents
            bounds = Geom::BoundingBox.new
            bounds.add(@na_hover_entity.bounds) if @na_hover_entity && @na_hover_entity.valid?
            bounds
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Helpers
    # -------------------------------------------------------------------------

        def Na__SceneProfilePicker__PickTopLevelInstance(view, x, y)
            pick_helper = view.pick_helper
            return nil if pick_helper.do_pick(x, y) < 1

            path = pick_helper.path_at(0)
            return nil unless path

            path.each do |entity|
                if entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
                    return entity
                end
            end

            nil
        end
        private :Na__SceneProfilePicker__PickTopLevelInstance

        def Na__SceneProfilePicker__DrawBoundingBoxWireframe(view, bounds)
            corners = (0..7).map { |index| bounds.corner(index) }

            view.draw_line(corners[0], corners[1])
            view.draw_line(corners[1], corners[3])
            view.draw_line(corners[3], corners[2])
            view.draw_line(corners[2], corners[0])

            view.draw_line(corners[4], corners[5])
            view.draw_line(corners[5], corners[7])
            view.draw_line(corners[7], corners[6])
            view.draw_line(corners[6], corners[4])

            view.draw_line(corners[0], corners[4])
            view.draw_line(corners[1], corners[5])
            view.draw_line(corners[2], corners[6])
            view.draw_line(corners[3], corners[7])
        end
        private :Na__SceneProfilePicker__DrawBoundingBoxWireframe

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
