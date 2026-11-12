# =============================================================================
# NA AGENT OUTLINER - MODEL DATA - ENTITY ACTIONS
# =============================================================================
#
# FILE       : Na__AgentOutliner__ModelData__EntityActions__.rb
# NAMESPACE  : Na__AgentOutliner::Na__EntityActions
# MODULE     : Na__EntityActions (module functions)
# AUTHOR     : Noble Architecture
# PURPOSE    : What a row click does in the model: find the object a row
#              stands for, select it (opening its group as SketchUp's Outliner
#              does, or selecting its top-level container), zoom to it, hide,
#              show, lock and unlock
# CREATED    : 10-Nov-2026
#
# DESCRIPTION:
# - ROWS ARE PATHS. The page sends the persistent ids from the root down to
#   the row ([building, ground floor, wall]), because an object inside a
#   component placed three times appears three times. Each path is checked
#   link by link: every object must sit inside the definition of the one
#   above it, or the path is stale and refused.
# - SELECTING A NESTED OBJECT: SketchUp can only select inside the open
#   context, so by default its parent group is opened (Model#active_path=),
#   exactly as SketchUp's Outliner does. active_path= is its own undo step in
#   SketchUp and is called outside any operation. A locked parent cannot be
#   opened (ArgumentError): the top-level object is selected instead, and the
#   status says why.
# - HIDE, SHOW, LOCK and UNLOCK are one named undo step each.
#
# =============================================================================

module Na__AgentOutliner
    module Na__EntityActions

# -----------------------------------------------------------------------------
# REGION | Resolving Rows
# -----------------------------------------------------------------------------

        # FUNCTION | A Row's Path of Persistent Ids to Entities (nil when stale)
        # ------------------------------------------------------------
        def self.Na__Actions__ResolvePath(model, pid_path)
            ids = Array(pid_path).map(&:to_i)
            return nil if ids.empty? || ids.any? { |id| id <= 0 }

            entities = ids.map { |id| self.Na__Actions__FindById(model, id) }
            return nil if entities.any?(&:nil?)

            container = nil                                                              # <-- nil = the model root (compared by class: a model may have several Ruby wrappers)
            entities.each do |entity|
                parent = entity.parent
                linked = container.nil? ? parent.is_a?(Sketchup::Model) : (parent == container || parent.equal?(container))
                return nil unless linked

                container = entity.respond_to?(:definition) && !entity.is_a?(Sketchup::Image) ? entity.definition : false
            end
            entities
        end
        # ---------------------------------------------------------------

        # FUNCTION | One Object by Persistent Id (nil when gone)
        # ------------------------------------------------------------
        # The tracker's live map answers first (no search); SketchUp's own
        # lookup (2020.2+) is the fallback.
        def self.Na__Actions__FindById(model, pid)
            entity = Na__AgentOutliner::Na__Tracker.Na__Tracker__EntityById(model, pid)
            return entity if entity && entity.valid?
            return nil unless model.respond_to?(:find_entity_by_persistent_id)

            found = model.find_entity_by_persistent_id(pid.to_i)
            found = found.first if found.is_a?(Array)
            found && found.valid? && Na__AgentOutliner::Na__Walker.Na__Walker__Kind(found) ? found : nil
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Select and Zoom
# -----------------------------------------------------------------------------

        # FUNCTION | Select the Rows' Objects in the Model
        # ------------------------------------------------------------
        # mode: 'open_context' (open the parent group, like SketchUp's
        # Outliner) or 'top_level' (select the root-level container).
        # Returns { 'selected' => n, 'note' => text or nil }.
        def self.Na__Actions__Select(model, pid_paths, mode: 'open_context', zoom: false)
            paths = Array(pid_paths).map { |path| self.Na__Actions__ResolvePath(model, path) }.compact
            raise ArgumentError, 'Those rows are out of date: press Refresh.' if paths.empty?

            note = nil
            if mode == 'top_level'
                context = []
                targets = paths.map(&:first).uniq
            else
                context = paths.first[0...-1]
                same    = paths.select { |path| self.na_same_path?(path[0...-1], context) }
                note    = "Selected the #{same.length} that share the first one's group; SketchUp can only select inside one open group at a time." if same.length < paths.length
                targets = same.map(&:last).uniq
            end

            unless self.na_same_path?(Array(model.active_path), context)
                begin
                    model.active_path = context.empty? ? nil : context
                rescue ArgumentError
                    context = []
                    targets = paths.map(&:first).uniq
                    note    = 'A group on the way is locked, so the top-level object is selected instead.'
                    model.active_path = nil unless Array(model.active_path).empty?
                end
            end

            selection = model.selection
            selection.clear
            selection.add(targets)
            model.active_view.zoom(targets) if zoom
            { 'selected' => targets.length, 'note' => note }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Zoom the View to the Rows' Objects (selection unchanged)
        # ------------------------------------------------------------
        # View#zoom frames entities by their bounds; for nested objects the
        # top-level container is framed, which always contains them.
        def self.Na__Actions__Zoom(model, pid_paths)
            paths = Array(pid_paths).map { |path| self.Na__Actions__ResolvePath(model, path) }.compact
            raise ArgumentError, 'Those rows are out of date: press Refresh.' if paths.empty?

            active  = Array(model.active_path)
            targets = paths.map do |path|
                inside = active.length < path.length && self.na_same_path?(path[0, active.length], active)
                inside ? path[active.length] : path.first
            end.uniq
            model.active_view.zoom(targets)
            { 'zoomed' => targets.length }
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Hide, Show, Lock, Unlock (each ONE undo step)
# -----------------------------------------------------------------------------

        # FUNCTION | Hide or Show Objects
        # ------------------------------------------------------------
        def self.Na__Actions__SetHidden(model, entities, hidden)
            todo = Array(entities).select { |entity| entity && entity.valid? && entity.hidden? != hidden }
            return 0 if todo.empty?

            Na__AgentOutliner.Na__Model__WithOperation(model, hidden ? 'Agent Outliner: Hide' : 'Agent Outliner: Show') do
                todo.each { |entity| entity.hidden = hidden }
            end
            todo.length
        end
        # ---------------------------------------------------------------

        # FUNCTION | Lock or Unlock Groups and Components
        # ------------------------------------------------------------
        def self.Na__Actions__SetLocked(model, entities, locked)
            todo = Array(entities).select do |entity|
                entity && entity.valid? && entity.respond_to?(:locked=) && entity.locked? != locked
            end
            return 0 if todo.empty?

            Na__AgentOutliner.Na__Model__WithOperation(model, locked ? 'Agent Outliner: Lock' : 'Agent Outliner: Unlock') do
                todo.each { |entity| entity.locked = locked }
            end
            todo.length
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Tag (ONE undo step; 0.1.5)
# -----------------------------------------------------------------------------

        # FUNCTION | The Tag Shown With This Name, or nil ('' or "Untagged" is Untagged)
        # ------------------------------------------------------------
        # Names as SketchUp shows them (display_name), exact first, then any case.
        def self.Na__Actions__FindTag(model, name)
            text   = name.to_s.strip
            layer0 = model.layers[0]
            return layer0 if text.empty? || text.casecmp('untagged').zero?

            named = lambda do |layer|
                !layer.equal?(layer0) && layer != layer0 && Na__AgentOutliner::Na__Walker.Na__Walker__TagName(layer, layer0)
            end
            model.layers.find { |layer| (shown = named.call(layer)) && shown == text } ||
                model.layers.find { |layer| (shown = named.call(layer)) && shown.casecmp(text).zero? }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Put Objects on a Tag
        # ------------------------------------------------------------
        # create: true makes a missing tag in the same undo step; otherwise a
        # missing tag is refused (ArgumentError) and nothing changes. Returns
        # {'count', 'tag' (as shown, '' for Untagged), 'created'}.
        def self.Na__Actions__SetTag(model, entities, name, create: false, operation_name: nil)
            text  = name.to_s.strip
            layer = self.Na__Actions__FindTag(model, text)
            if layer.nil?
                raise ArgumentError, "There is no tag named #{text}. Choose one of the model's tags, or make it (create)." unless create
                raise ArgumentError, 'A tag name is 255 characters at most.' if text.length > 255
                raise ArgumentError, 'Layer0 is Untagged: choose Untagged instead.' if text.casecmp('layer0').zero?
            end

            todo = Array(entities).select do |entity|
                entity && entity.valid? && entity.respond_to?(:layer=) && (layer.nil? || entity.layer != layer)
            end
            shown = layer ? Na__AgentOutliner::Na__Walker.Na__Walker__TagName(layer, model.layers[0]) : text
            return { 'count' => 0, 'tag' => shown, 'created' => false } if todo.empty? && layer

            created = false
            Na__AgentOutliner.Na__Model__WithOperation(model, operation_name || 'Agent Outliner: Tag') do
                if layer.nil?
                    layer   = model.layers.add(text)
                    created = true
                end
                todo.each { |entity| entity.layer = layer }
            end
            { 'count' => todo.length, 'tag' => text.empty? || layer == model.layers[0] ? '' : Na__AgentOutliner::Na__Walker.Na__Walker__TagName(layer, model.layers[0]), 'created' => created }
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Helpers
# -----------------------------------------------------------------------------

        def self.na_same_path?(left, right)
            left = Array(left)
            right = Array(right)
            left.length == right.length && left.each_index.all? { |index| left[index] == right[index] || left[index].equal?(right[index]) }
        end

# endregion -------------------------------------------------------------------

    end # module Na__EntityActions
end # module Na__AgentOutliner

# =============================================================================
# END OF FILE
# =============================================================================
