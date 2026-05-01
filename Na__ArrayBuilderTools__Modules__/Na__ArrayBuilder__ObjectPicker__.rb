# =============================================================================
# NA ARRAY BUILDER TOOLS - OBJECT PICKER TOOL
# =============================================================================
#
# FILE       : Na__ArrayBuilder__ObjectPicker__.rb
# NAMESPACE  : Na__ArrayBuilderTools::Na__ArrayBuilder__ObjectPicker
# AUTHOR     : Noble Architecture
# PURPOSE    : Modal SketchUp tool that lets the user click a Group or
#              ComponentInstance in the model. The picked entity is
#              validated, normalised to a Sketchup::ComponentDefinition,
#              stored in Na__ArrayBuilder__ObjectRegistry, and reported
#              back to the dialog so the UI can display its info.
# CREATED    : 2026
# VERSION    : 0.0.3
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__ArrayBuilder__ObjectRegistry__'

module Na__ArrayBuilderTools

# =============================================================================
# REGION | Object Picker Tool Class
# =============================================================================

    class Na__ArrayBuilder__ObjectPicker

        # FUNCTION | Initialise Picker With Dialog Callback Target
        # ------------------------------------------------------------
        # @param dialog_manager [Module] Receives na_send_object_picked /
        #                                na_send_status_to_dialog calls
        def initialize(dialog_manager)
            @na_dialog_manager = dialog_manager
            @na_hover_entity   = nil
        end
        # ---------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Tool Lifecycle Callbacks
# -----------------------------------------------------------------------------

        # FUNCTION | Tool Activated
        # ------------------------------------------------------------
        def activate
            Na__ObjectPicker__UpdateStatusText()
            Sketchup.active_model.active_view.invalidate
        end
        # ---------------------------------------------------------------

        # FUNCTION | Tool Deactivated
        # ------------------------------------------------------------
        def deactivate(view)
            view.invalidate
        end
        # ---------------------------------------------------------------

        # FUNCTION | Cancel Handler (ESC)
        # ------------------------------------------------------------
        def onCancel(_reason, _view)
            @na_dialog_manager.na_send_status_to_dialog(
                "info",
                "Object pick cancelled"
            )
            Sketchup.active_model.select_tool(nil)
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Mouse Interaction
# -----------------------------------------------------------------------------

        # FUNCTION | Mouse Move Handler (Hover Highlight)
        # ------------------------------------------------------------
        def onMouseMove(_flags, x, y, view)
            @na_hover_entity = Na__ObjectPicker__PickTopLevelInstance(view, x, y)
            view.invalidate
        end
        # ---------------------------------------------------------------

        # FUNCTION | Left Mouse Button Down Handler
        # ------------------------------------------------------------
        def onLButtonDown(_flags, x, y, view)
            picked = Na__ObjectPicker__PickTopLevelInstance(view, x, y)

            unless picked
                @na_dialog_manager.na_send_status_to_dialog(
                    "warning",
                    "Click a Group or Component (faces / edges are not arrayable)"
                )
                return
            end

            Na__ObjectPicker__StoreAndReport(picked)
            Sketchup.active_model.select_tool(nil)
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Drawing
# -----------------------------------------------------------------------------

        # FUNCTION | Draw Handler (Hover Highlight Box)
        # ------------------------------------------------------------
        def draw(view)
            return unless @na_hover_entity && @na_hover_entity.valid?

            bb = @na_hover_entity.bounds
            return if bb.nil? || bb.empty?

            view.line_width    = 2
            view.drawing_color = Sketchup::Color.new(74, 144, 217, 220)
            Na__ObjectPicker__DrawBoundingBoxWireframe(view, bb)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Get Extents
        # ------------------------------------------------------------
        def getExtents
            bb = Geom::BoundingBox.new
            bb.add(@na_hover_entity.bounds) if @na_hover_entity && @na_hover_entity.valid?
            bb
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

        private

# -----------------------------------------------------------------------------
# REGION | Pick Helpers
# -----------------------------------------------------------------------------

        # FUNCTION | Pick Top-Level Group or ComponentInstance Under Cursor
        # ------------------------------------------------------------
        # Walks the pick path returned by Sketchup::PickHelper#path_at(0)
        # and returns the first Group / ComponentInstance encountered
        # (i.e. the outermost container in the active entities). Returns
        # nil for empty picks or picks that do not resolve to a valid
        # group / component instance.
        def Na__ObjectPicker__PickTopLevelInstance(view, x, y)
            ph = view.pick_helper
            return nil if ph.do_pick(x, y) < 1

            path = ph.path_at(0)
            return nil unless path

            path.each do |entity|
                if entity.is_a?(Sketchup::Group) ||
                   entity.is_a?(Sketchup::ComponentInstance)
                    return entity
                end
            end

            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Resolve Entity to a Sketchup::ComponentDefinition
        # ------------------------------------------------------------
        # Both Sketchup::Group (via Group#definition, SU 2018+) and
        # Sketchup::ComponentInstance expose a #definition accessor.
        def Na__ObjectPicker__ResolveDefinition(entity)
            return nil unless entity
            entity.definition if entity.respond_to?(:definition)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Resolve a Human-Readable Display Name for the Entity
        # ------------------------------------------------------------
        # Prefers the instance name, falls back to the definition name,
        # then to a generic label. Keeps UI predictable when groups are
        # unnamed.
        def Na__ObjectPicker__ResolveDisplayName(entity, component_def)
            instance_name = entity.respond_to?(:name) ? entity.name.to_s : ''
            return instance_name unless instance_name.empty?

            def_name = component_def && component_def.respond_to?(:name) ? component_def.name.to_s : ''
            return def_name unless def_name.empty?

            entity.is_a?(Sketchup::Group) ? '<Unnamed Group>' : '<Unnamed Component>'
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Registry + Dialog Reporting
# -----------------------------------------------------------------------------

        # FUNCTION | Store Picked Entity and Notify Dialog
        # ------------------------------------------------------------
        def Na__ObjectPicker__StoreAndReport(entity)
            component_def = Na__ObjectPicker__ResolveDefinition(entity)

            unless component_def && component_def.valid?
                @na_dialog_manager.na_send_status_to_dialog(
                    "error",
                    "Picked entity has no usable component definition"
                )
                return
            end

            display_name = Na__ObjectPicker__ResolveDisplayName(entity, component_def)

            Na__ArrayBuilder__ObjectRegistry.Na__Registry__SetDefinition(
                component_def, display_name
            )

            bounds = Na__ArrayBuilder__ObjectRegistry.Na__Registry__GetBoundsMm
            unless bounds
                @na_dialog_manager.na_send_status_to_dialog(
                    "error",
                    "Picked object has no measurable bounds"
                )
                Na__ArrayBuilder__ObjectRegistry.Na__Registry__Clear
                return
            end

            @na_dialog_manager.na_send_object_picked(
                display_name,
                bounds[:unit_width_mm],
                bounds[:unit_depth_mm],
                bounds[:unit_height_mm]
            )

            @na_dialog_manager.na_send_status_to_dialog(
                "success",
                "Selected: #{display_name}"
            )
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Status Bar
# -----------------------------------------------------------------------------

        # FUNCTION | Update SketchUp Status Bar Text
        # ------------------------------------------------------------
        def Na__ObjectPicker__UpdateStatusText
            Sketchup.status_text =
                "Array Builder: Click a Group or Component to use as the array unit | ESC to cancel"
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Drawing Helpers
# -----------------------------------------------------------------------------

        # FUNCTION | Draw Wireframe Box for a Geom::BoundingBox
        # ------------------------------------------------------------
        # Uses the documented BoundingBox#corner indexing:
        #   0..3 = bottom face (Z min), 4..7 = top face (Z max).
        def Na__ObjectPicker__DrawBoundingBoxWireframe(view, bb)
            c = (0..7).map { |i| bb.corner(i) }

            view.draw_line(c[0], c[1])
            view.draw_line(c[1], c[3])
            view.draw_line(c[3], c[2])
            view.draw_line(c[2], c[0])

            view.draw_line(c[4], c[5])
            view.draw_line(c[5], c[7])
            view.draw_line(c[7], c[6])
            view.draw_line(c[6], c[4])

            view.draw_line(c[0], c[4])
            view.draw_line(c[1], c[5])
            view.draw_line(c[2], c[6])
            view.draw_line(c[3], c[7])
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # class Na__ArrayBuilder__ObjectPicker

# endregion ===================================================================

end # module Na__ArrayBuilderTools

# =============================================================================
# END OF FILE
# =============================================================================
