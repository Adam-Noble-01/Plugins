# =============================================================================
# NA NOBLE3D MODELLING TOOLS - GROUPS TO COMPONENT - PICKER TOOL
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__GroupsToComponent__PickerTool__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__GroupsToComponent::Na__GroupsToComponent__PickerTool
# PURPOSE    : Interactive tool for selecting the inference group
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__GroupsToComponent

# -----------------------------------------------------------------------------
# REGION | Picker Tool Class
# -----------------------------------------------------------------------------

        # CLASS | GroupsToComponentPickerTool - Inference Group Selection
        # ------------------------------------------------------------
        class Na__GroupsToComponent__PickerTool

            NA_HIGHLIGHT_COLOR = Sketchup::Color.new(255, 140, 0, 180)

            # INITIALIZE | Tool Constructor
            # ------------------------------------------------------------
            def initialize(candidate_groups, on_pick_callback)
                @candidate_groups   = Array(candidate_groups).select { |group| group&.valid? }
                @on_pick_callback   = on_pick_callback
                @candidate_id_set   = @candidate_groups.map(&:persistent_id)
                @hovered_group      = nil
                @ip                 = Sketchup::InputPoint.new
            end
            # ------------------------------------------------------------

            # ACTIVATE | Called When Tool Is Activated
            # ------------------------------------------------------------
            def activate
                Sketchup.status_text = 'Click the group to use as the component template. Press Esc to cancel.'
            end
            # ------------------------------------------------------------

            # DEACTIVATE | Called When Tool Is Deselected
            # ------------------------------------------------------------
            def deactivate(view)
                Sketchup.status_text = ''
                @hovered_group = nil
                view.invalidate
            end
            # ------------------------------------------------------------

            # ON MOUSE MOVE | Track Group Under Cursor
            # ------------------------------------------------------------
            def onMouseMove(_flags, x, y, view)
                @ip.pick(view, x, y)
                @hovered_group = na_group_under_cursor(view, x, y)
                view.invalidate
            end
            # ------------------------------------------------------------

            # ON LEFT BUTTON DOWN | Confirm Inference Group Selection
            # ------------------------------------------------------------
            def onLButtonDown(_flags, x, y, view)
                picked_group = na_group_under_cursor(view, x, y)

                unless picked_group
                    UI.beep
                    Sketchup.status_text = 'Click one of the selected groups. Press Esc to cancel.'
                    return
                end

                Sketchup.status_text = ''
                view.model.select_tool(nil)
                @on_pick_callback.call(picked_group) if @on_pick_callback.respond_to?(:call)
            end
            # ------------------------------------------------------------

            # ON CANCEL | Handle Tool Cancellation
            # ------------------------------------------------------------
            def onCancel(_reason, view)
                Sketchup.status_text = ''
                view.model.select_tool(nil)
                @on_pick_callback.call(nil) if @on_pick_callback.respond_to?(:call)
            end
            # ------------------------------------------------------------

            # DRAW | Highlight Candidate Group Under Cursor
            # ------------------------------------------------------------
            def draw(view)
                return unless @hovered_group&.valid?

                bounds = @hovered_group.bounds
                return unless bounds.valid?

                view.drawing_color = NA_HIGHLIGHT_COLOR
                view.line_width    = 2
                view.line_stipple  = ''

                pts = (0..7).map { |index| bounds.corner(index) }
                view.draw(GL_LINE_LOOP, pts[0], pts[1], pts[3], pts[2])
                view.draw(GL_LINE_LOOP, pts[4], pts[5], pts[7], pts[6])
                view.draw(GL_LINES, pts[0], pts[4], pts[1], pts[5], pts[2], pts[6], pts[3], pts[7])
            end
            # ------------------------------------------------------------

            # GET EXTENTS | Report Overlay Bounds for Drawing
            # ------------------------------------------------------------
            def getExtents
                bounds = Geom::BoundingBox.new
                bounds.add(@hovered_group.bounds) if @hovered_group&.valid?
                bounds
            end
            # ------------------------------------------------------------

            private

            # HELPER FUNCTION | Resolve Candidate Group Under Cursor
            # ------------------------------------------------------------
            def na_group_under_cursor(view, x, y)
                pick_helper = view.pick_helper
                pick_helper.do_pick(x, y)
                picked_entity = pick_helper.best_picked
                return nil unless picked_entity

                na_resolve_candidate_group(picked_entity)
            end
            # ------------------------------------------------------------

            # HELPER FUNCTION | Walk Entity Hierarchy to Find Candidate Group
            # ------------------------------------------------------------
            def na_resolve_candidate_group(entity)
                current = entity

                12.times do
                    break unless current

                    if current.is_a?(Sketchup::Group) &&
                       current.valid? &&
                       @candidate_id_set.include?(current.persistent_id)
                        return current
                    end

                    current = current.respond_to?(:parent) ? current.parent : nil
                end

                nil
            end
            # ------------------------------------------------------------

        end # class Na__GroupsToComponent__PickerTool

# endregion -------------------------------------------------------------------

    end # module Na__GroupsToComponent
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
