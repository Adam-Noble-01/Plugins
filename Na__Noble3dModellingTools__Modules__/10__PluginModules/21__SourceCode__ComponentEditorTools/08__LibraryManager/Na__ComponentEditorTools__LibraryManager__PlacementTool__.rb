# =============================================================================
# NA COMPONENT EDITOR TOOLS - LIBRARY MANAGER | PLACEMENT
# =============================================================================
#
# FILE       : Na__ComponentEditorTools__LibraryManager__PlacementTool__.rb
# NAMESPACE  : Na__ComponentEditorTools::Na__LibraryPlacementTool
# PURPOSE    : Puts a library .skp into the model. Insert At Cursor hands it to
#              SketchUp's own component placement tool, then lets Tab turn what it
#              placed; Insert At Axis adds it at the drawing axes origin.
# CREATED    : 2026
#
# WHY SKETCHUP'S OWN TOOL (0.6.6, as the PainterlyNPR Asset Library places):
#   This was a Ruby tool that added a real instance and moved it on every mouse
#   move, outside any operation. Each move was its own undo step, the InputPoint
#   picked the instance under the cursor, and a tool change left it stranded.
#   Model#place_component previews without touching the model, infers and glues
#   as SketchUp does everywhere else, and Esc or a tool change leaves nothing.
#
# TAB TURNS IT, JUST AFTER THE CLICK (0.6.7):
#   SketchUp's tool passes no keys to Ruby, so Tab cannot work while it previews.
#   A ToolsObserver sees the tool end: a new instance of the definition means it
#   was placed, none means it was cancelled. A small Ruby tool then takes Tab until
#   the next click, Enter, Esc or tool change. It writes only when Tab is pressed,
#   never on a mouse move.
#
# COORDINATES (the coordinate rule, Adam's global CLAUDE.md):
#   Insert At Cursor computes no transformation, so there is nothing to convert
#   twice: SketchUp places into the active context where the person clicks.
#   Insert At Axis gives add_instance model.axes, which is world, and points given
#   to add_instance are world in the active context. No conversion either.
#   The Tab turn reads the instance's own transformation and gives the rotation to
#   its parent's transform_entities: both are world in an open context and local
#   otherwise, so they always agree. It turns about the instance's own blue axis,
#   so a component glued to a wall stays on the wall.
#
# UNDO CONTRACT:
#   Insert At Cursor: "Na Library - Load <file>" the first time a file enters this
#   model, then SketchUp's own step for the placement. A file already in the model
#   adds only the placement. Operations do not nest, so the load is committed
#   before the tool starts. Each Tab appends to the placement's step, so one Ctrl+Z
#   takes the placement and its turns together.
#   Insert At Axis: one step, whether or not it had to load the file.
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

            model      = Sketchup.active_model
            definition = self.na_definition_for_placement(model, component_path.to_s)
            return { ok: false, message: 'Could not load component definition.' } unless definition

            self.na_stop_watching_placement                                                             # <-- A card clicked while another places: that placement is over, whatever comes next
            return { ok: false, message: "SketchUp would not start placing \"#{definition.name}\"." } unless model.place_component(definition, false)

            Sketchup.focus                                                                              # <-- The card was clicked in the dialog: Esc and the arrow locks belong to the tool now
            self.na_watch_placement(model, definition)
            { ok: true, message: "\"#{definition.name}\": click in the model to place it, then Tab turns it. Esc cancels." }
        rescue => error
            { ok: false, message: "#{error.class}: #{error.message}" }
        end

        def self.Na__ComponentEditorTools__InsertAtAxis(component_path, dialog_handle = nil)
            return { ok: false, message: 'No library component path provided.' } if component_path.to_s.empty?
            return { ok: false, message: 'File not found.' } unless File.exist?(component_path.to_s)

            self.na_stop_watching_placement                                                             # <-- This copy must not be mistaken for one placed with the tool
            model     = Sketchup.active_model
            axes      = model.axes
            transform = Geom::Transformation.axes(axes.origin, axes.xaxis, axes.yaxis, axes.zaxis)

            model.start_operation("Insert At Axis: #{File.basename(component_path.to_s, '.*')}", true)
            definition = Na__LibrarySafeLoad.Na__ComponentEditorTools__LoadedDefinitionFor(model, component_path.to_s) ||
                         model.definitions.load(component_path.to_s)
            unless definition
                model.abort_operation
                return { ok: false, message: 'Could not load component definition.' }
            end

            model.active_entities.add_instance(definition, transform)
            model.commit_operation

            { ok: true, message: "\"#{definition.name}\" placed at axes origin." }
        rescue => error
            model.abort_operation rescue nil
            { ok: false, message: "#{error.class}: #{error.message}" }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internals
# -----------------------------------------------------------------------------

        # The definition already loaded from this file, else the file loaded as one
        # named undo step. A file already in the model adds no step and reads no disk.
        def self.na_definition_for_placement(model, component_path)
            existing = Na__LibrarySafeLoad.Na__ComponentEditorTools__LoadedDefinitionFor(model, component_path)
            return existing if existing

            model.start_operation("Na Library - Load #{File.basename(component_path, '.*')}", true)
            begin
                definition = model.definitions.load(component_path)
            rescue Exception                                                                            # <-- Anything at all: abort, then raise it on
                model.abort_operation
                raise
            end
            definition ? model.commit_operation : model.abort_operation
            definition
        end

        def self.na_watch_placement(model, definition)
            @na_placement_watch = Na__ComponentEditorTools__PlacementWatch.new(model, definition)
            model.tools.add_observer(@na_placement_watch)
        end

        def self.na_stop_watching_placement
            watch = @na_placement_watch
            return unless watch

            @na_placement_watch = nil
            watch.model.tools.remove_observer(watch) if watch.model.valid?
        end

        # Runs from a timer, never from the observer callback: SketchUp is still
        # switching tools during the callback.
        def self.na_placement_ended(watch)
            return unless watch.equal?(@na_placement_watch)                                             # <-- Another card was clicked since, or a second event got here first

            self.na_stop_watching_placement
            instance = watch.placed_instance
            if instance
                watch.model.select_tool(Na__ComponentEditorTools__PlacedTurnStep.new(instance))
                Na__DialogManager.Na__ComponentEditorTools__PushStatus("\"#{instance.definition.name}\" placed. Tab turns it 90 degrees; click or Esc finishes.", 'info')
            else
                Na__DialogManager.Na__ComponentEditorTools__PushStatus('Placement cancelled.', 'info')
            end
        rescue => error
            puts "Na Library placement: #{error.class}: #{error.message}"                               # <-- The component is already placed: losing the Tab step must not trouble anyone
        end

# endregion -------------------------------------------------------------------

    end

# =============================================================================
# REGION | Placement Watch
# =============================================================================

    # Says when SketchUp's placement tool has ended, and what it left behind.
    class Na__ComponentEditorTools__PlacementWatch < Sketchup::ToolsObserver

        NA_PLACING_TOOL_ID = 21013                                                                      # <-- ComponentTool, measured in SketchUp 27.0: Tools#active_tool_id during place_component

        attr_reader :model

        def initialize(model, definition)
            super()
            @model            = model
            @definition       = definition
            @instances_before = definition.instances
        end

        def onActiveToolChanged(_tools, _tool_name, tool_id)
            return if tool_id == NA_PLACING_TOOL_ID

            UI.start_timer(0, false) { Na__LibraryPlacementTool.na_placement_ended(self) }
        end

        def placed_instance
            return nil unless @definition.valid?

            (@definition.instances - @instances_before).last
        end

    end

# endregion ===================================================================

# =============================================================================
# REGION | Tab Turn Step
# =============================================================================

    # Active from the placing click until the next click, Enter, Esc or tool change.
    # There is no onMouseMove on purpose: nothing here may write as the pointer moves.
    class Na__ComponentEditorTools__PlacedTurnStep

        NA_TAB_KEY      = 9
        NA_TURN_DEGREES = 90
        NA_STATUS_TEXT  = 'Tab turns it 90 degrees. Click, Enter or Esc finishes. Ctrl+Z removes it.'

        def initialize(instance)
            @instance = instance
        end

        def activate
            selection = Sketchup.active_model.selection
            selection.clear
            selection.add(@instance)                                                                    # <-- Shows what Tab will turn, and M or Q carry straight on with it
            Sketchup.status_text = NA_STATUS_TEXT
        end

        def resume(_view)
            Sketchup.status_text = NA_STATUS_TEXT                                                       # <-- Back from an orbit or a pan
        end

        def deactivate(_view)
            Na__DialogManager.Na__ComponentEditorTools__PushStatus('', 'info')
        end

        def onKeyDown(key, repeat, _flags, _view)
            return false unless key == NA_TAB_KEY

            na_turn if repeat == 1                                                                      # <-- Holding Tab turns it once, not until the key comes up
            true
        end

        def onReturn(_view)
            na_finish
        end

        def onCancel(_reason, _view)
            na_finish                                                                                   # <-- Esc keeps the component; an undo removes it right after this
        end

        # This click ends the step and does what the Select tool's click would have.
        def onLButtonDown(_flags, x, y, view)
            pick = view.pick_helper
            pick.do_pick(x, y)
            selection = Sketchup.active_model.selection
            selection.clear
            selection.add(pick.best_picked) if pick.best_picked
            na_finish
        end

    private

        def na_turn
            return na_finish unless @instance.valid?                                                    # <-- Deleted from a menu while this step was up

            model     = Sketchup.active_model
            placement = @instance.transformation
            turn      = Geom::Transformation.rotation(placement.origin, placement.zaxis, NA_TURN_DEGREES.degrees)

            model.start_operation('Turn Placed Component', true, false, true)                           # <-- Transparent: appends to the placement, so one undo takes both
            @instance.parent.entities.transform_entities(turn, [@instance])
            model.commit_operation
        rescue => error
            model.abort_operation rescue nil
            puts "Na Library placement: #{error.class}: #{error.message}"
        end

        def na_finish
            Sketchup.active_model.select_tool(nil)
        end

    end

# endregion ===================================================================

end

# =============================================================================
# END OF FILE
# =============================================================================
