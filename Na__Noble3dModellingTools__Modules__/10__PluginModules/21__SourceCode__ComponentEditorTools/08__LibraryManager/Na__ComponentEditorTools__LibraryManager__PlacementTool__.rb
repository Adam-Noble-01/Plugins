# =============================================================================
# NA COMPONENT EDITOR TOOLS - LIBRARY MANAGER | PLACEMENT TOOL
# =============================================================================
#
# FILE       : Na__ComponentEditorTools__LibraryManager__PlacementTool__.rb
# NAMESPACE  : Na__ComponentEditorTools::Na__LibraryPlacementTool
# PURPOSE    : Interactive Tool that loads a .skp component definition and
#              allows the user to click-to-place it in the model. The instance
#              is oriented to the model drawing axes. Tab rotates 90 degrees
#              around the drawing Z axis. Escape cancels and removes the ghost.
# CREATED    : 2026
#
# Placement axis logic follows the InsertionFrame pattern from:
# Na__ArchTools__ElementAssemblyStudioPro__Modules__/02__Src__AppModules/
# 04__GeometryHelpers/Na__AssemblyStudio__GeometryHelpers__InsertionFrame__.rb
#
# =============================================================================

module Na__ComponentEditorTools
    module Na__LibraryPlacementTool

# -----------------------------------------------------------------------------
# REGION | Public Entry Point
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__StartPlacement(component_path, dialog_handle = nil)
            return { ok: false, message: 'No library component path provided.' } if component_path.to_s.empty?
            return { ok: false, message: 'File not found.' } unless File.exist?(component_path.to_s)

            model = Sketchup.active_model
            definition = model.definitions.load(component_path.to_s)
            return { ok: false, message: 'Could not load component definition.' } unless definition

            model.select_tool(Na__ComponentEditorTools__LibraryPlacementToolImpl.new(definition, component_path.to_s, dialog_handle))
            { ok: true, message: "Click in the model to place \"#{definition.name}\"." }
        rescue => error
            { ok: false, message: "#{error.class}: #{error.message}" }
        end

# endregion -------------------------------------------------------------------

    end

# =============================================================================
# REGION | Tool Implementation
# =============================================================================

    class Na__ComponentEditorTools__LibraryPlacementToolImpl

        NA_GRID_SIZE       = 1.inch
        NA_CURSOR_ICON_STR = 'default'

        def initialize(definition, source_path, dialog_handle)
            @definition      = definition
            @source_path     = source_path
            @dialog_handle   = dialog_handle
            @instance        = nil
            @input_point     = Sketchup::InputPoint.new
            @rotation_deg    = 0
            @current_origin  = ORIGIN
            @axes_transform         = nil
            @axes_inverse_transform = nil
            @axes_zaxis             = nil
        end

        def activate
            model = Sketchup.active_model
            return unless model

            axes = model.axes
            @axes_zaxis             = axes.zaxis
            @axes_transform         = Geom::Transformation.axes(ORIGIN, axes.xaxis, axes.yaxis, axes.zaxis)
            @axes_inverse_transform = @axes_transform.inverse

            initial_origin = ORIGIN
            transform = self.na_build_transform(initial_origin)
            @instance = model.active_entities.add_instance(@definition, transform)

            Sketchup.status_text = "Click to place \"#{@definition.name}\". Tab = rotate 90°. Esc = cancel."
        end

        def deactivate(view)
            view.invalidate
        end

        def onMouseMove(_flags, x, y, view)
            @input_point.pick(view, x, y)
            @current_origin = na_snap_to_grid(@input_point.position)
            transform = na_build_transform(@current_origin)
            @instance.transformation = transform if @instance && @instance.valid?
            view.invalidate
        end

        def onLButtonDown(_flags, _x, _y, _view)
            return unless @instance && @instance.valid?

            Sketchup.active_model.select_tool(nil)
            @instance = nil
            na_notify_dialog('Component placed.')
        end

        def onKeyDown(key, _repeat, _flags, _view)
            case key
            when 9
                na_advance_rotation
                return true
            when 27
                na_cancel
                return true
            end
            false
        end

        def onCancel(_reason, _view)
            na_cancel
        end

        def draw(view)
            @input_point.draw(view)
        end

        def getExtents
            model = Sketchup.active_model
            return Geom::BoundingBox.new unless model

            model.active_entities.each.inject(Geom::BoundingBox.new) do |bb, e|
                bb.add(e.bounds) rescue bb
            end
        end

    private

        def na_build_transform(origin)
            model = Sketchup.active_model
            axes  = model.axes
            rotation_transform = Geom::Transformation.rotation(ORIGIN, axes.zaxis, @rotation_deg.degrees)
            axes_at_origin     = Geom::Transformation.axes(ORIGIN, axes.xaxis, axes.yaxis, axes.zaxis)
            translation        = Geom::Transformation.new(origin)
            translation * axes_at_origin * rotation_transform
        end

        def na_advance_rotation
            @rotation_deg = (@rotation_deg + 90) % 360
            transform = na_build_transform(@current_origin)
            @instance.transformation = transform if @instance && @instance.valid?
        end

        def na_snap_to_grid(world_point)
            return world_point unless @axes_inverse_transform && @axes_transform

            local_pt = world_point.transform(@axes_inverse_transform)
            snapped  = Geom::Point3d.new(
                (local_pt.x / NA_GRID_SIZE).round * NA_GRID_SIZE,
                (local_pt.y / NA_GRID_SIZE).round * NA_GRID_SIZE,
                local_pt.z
            )
            snapped.transform(@axes_transform)
        end

        def na_cancel
            if @instance && @instance.valid?
                @instance.erase! rescue nil
            end
            @instance = nil
            Sketchup.active_model.select_tool(nil)
        end

        def na_notify_dialog(message_text)
            return unless @dialog_handle && @dialog_handle.respond_to?(:visible?) && @dialog_handle.visible?

            Na__UiBridge.Na__ComponentEditorTools__ExecuteJsonFunction(
                @dialog_handle,
                'Na__ComponentEditorTools__ReceiveStatus',
                { message: message_text, variant: 'success' }
            )
        end

    end

# endregion ===================================================================

end

# =============================================================================
# END OF FILE
# =============================================================================
