# =============================================================================
# NA AGENT OUTLINER - CHAT PICK TOOL
# =============================================================================
#
# FILE       : Na__AgentOutliner__ModelData__ChatPick__.rb
# NAMESPACE  : Na__AgentOutliner::Na__ChatPick
# MODULE     : Na Agent Outliner (Na Noble3d Modelling Tools)
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : The Chat composer's pick button: a SketchUp tool that waits for
#              a click in the viewport and puts that object in the message, as
#              "NAME (id 12345)", where the text cursor was. "Hey, this object."
# CREATED    : 11-Nov-2026 (0.1.8)
#
# DESCRIPTION:
# - WHICH OBJECT: the deepest group or component under the cursor that has a
#   name of its own (SUB__Orangery__RoofLantern__Top__02, not the unnamed bar
#   group inside it, nor the building around it). Right-click (or Up) steps out
#   to the object around it, Down steps back in, and Ctrl takes the part right
#   under the cursor, named or not. The highlight and its label always show
#   what a click takes. Modifiers come from the mouse flags: the button leaves
#   the keyboard with the dialog, so Up and Down only work once the viewport
#   has it.
# - COORDINATES: PickHelper#path_at starts at the active entities, whose
#   transformations are world whether a group is open or not; each deeper
#   instance is relative to its parent. The highlight multiplies the path's
#   transformations from the first, never Model#edit_transform (that would
#   convert twice), and View#draw takes the world points. The matrices are
#   multiplied here from Transformation#to_a (column-major, the last element
#   carrying a uniform scale), so the maths is checked offline.
# - A CLICK tells the dialog ('chatPicked') and pops the tool, back to the tool
#   in use before. Shift+click tells it and stays for more. Esc, or choosing
#   another tool, cancels. The selection is never changed.
#
# =============================================================================

module Na__AgentOutliner
    module Na__ChatPick

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_HOVER_RGB  = [217, 119, 6].freeze unless defined?(NA_HOVER_RGB)              # <-- Adam's amber: he is the one pointing
        NA_PICKED_RGB = [22, 163, 74].freeze unless defined?(NA_PICKED_RGB)             # <-- Already in the message (Shift+click)
        NA_EDGES      = [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7],
                         [0, 4], [1, 5], [2, 6], [3, 7]].freeze unless defined?(NA_EDGES)  # <-- Corner bits: 1 = x max, 2 = y max, 4 = z max
        NA_IDENTITY   = [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0].freeze unless defined?(NA_IDENTITY)
        NA_HINT       = 'Agent Outliner: click an object to put it in the chat.  Right-click or Up: the object around it.  ' \
                        'Down: the one inside.  Ctrl: the part under the cursor.  Shift+click: several.  Esc: cancel.'.freeze unless defined?(NA_HINT)

        @na_tool    = nil unless defined?(@na_tool)
        @na_running = false unless defined?(@na_running)

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Start and Stop (the dialog's pick button)
# -----------------------------------------------------------------------------

        # FUNCTION | Start Picking: the Tool Goes on Top of the Model's Tool Stack
        # ------------------------------------------------------------
        def self.Na__Pick__Start(model)
            raise ArgumentError, 'No model is open.' unless model
            return true if self.Na__Pick__Active?

            tool = PickTool.new
            @na_tool = tool
            model.tools.push_tool(tool)
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Stop Picking (the button pressed again): back to the tool before
        # ------------------------------------------------------------
        def self.Na__Pick__Stop(model)
            return false unless model && self.Na__Pick__Active?

            tools = model.tools
            on_top = tools.respond_to?(:active_tool) ? tools.active_tool.equal?(@na_tool) : true
            tools.pop_tool if on_top
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is the Pick Tool Running?
        # ------------------------------------------------------------
        def self.Na__Pick__Active?
            @na_running ? true : false
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | What Is Under the Cursor, and Which Object a Click Takes
# -----------------------------------------------------------------------------

        # FUNCTION | The Pick Path Under the Cursor, Through SketchUp's Best Pick
        # ------------------------------------------------------------
        # Returns { 'path' => [entities from the active ones down], 'candidates'
        # => [the groups, components, pictures and section planes on it] }, or
        # nil over empty space or loose geometry.
        def self.Na__Pick__At(view, x, y)
            helper = view.pick_helper
            helper.do_pick(x, y)
            best = helper.best_picked
            return nil unless best

            paths = []
            helper.count.times do |index|
                path = helper.path_at(index)
                paths << path if path.is_a?(Array) && !path.empty? && path.first.equal?(best)
            end
            on_face = paths.select { |path| path.last.is_a?(Sketchup::Face) }
            path = on_face.max_by(&:length) || paths.max_by(&:length) || [best]           # <-- The face under the cursor, as deep as it goes
            candidates = path.select { |entity| Na__AgentOutliner::Na__Walker.Na__Walker__Kind(entity) }
            return nil if candidates.empty?

            { 'path' => path, 'candidates' => candidates }
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Candidate a Plain Click Takes: the Deepest With a Name of Its Own
        # ------------------------------------------------------------
        def self.Na__Pick__DefaultIndex(candidates)
            named = candidates.rindex { |entity| !Na__AgentOutliner::Na__Walker.Na__Walker__Name(entity).empty? }
            return named if named

            candidates.rindex { |entity| entity.is_a?(Sketchup::ComponentInstance) } || 0
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Candidate With Steps In or Out Applied (deep: the innermost)
        # ------------------------------------------------------------
        def self.Na__Pick__Index(candidates, offset, deep)
            last = candidates.length - 1
            return last if deep

            (self.Na__Pick__DefaultIndex(candidates) + offset.to_i).clamp(0, last)
        end
        # ---------------------------------------------------------------

        # FUNCTION | What the Dialog Gets for One Object
        # ------------------------------------------------------------
        def self.Na__Pick__Info(entity)
            pid  = entity.persistent_id
            name = Na__AgentOutliner::Na__Walker.Na__Walker__DisplayName(entity)
            kind = Na__AgentOutliner::Na__Walker.Na__Walker__Kind(entity)
            { 'pid' => pid, 'name' => name, 'kind' => kind, 'type' => Na__AgentOutliner::Na__Walker::NA_TYPE_NAMES[kind], 'text' => "#{name} (id #{pid})" }
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | The Highlight Box, in World Coordinates
# -----------------------------------------------------------------------------

        # FUNCTION | The Eight World Corners of One Candidate's Box
        # ------------------------------------------------------------
        # path: the pick path from the active entities. A group or component is
        # boxed by its definition's bounds through every transformation from the
        # first instance to itself; a picture or section plane by its own bounds
        # through the instances around it. Corner bits: 1 x max, 2 y max, 4 z max.
        def self.Na__Pick__BoxCorners(path, entity)
            position = path.index { |item| item.equal?(entity) }
            return [] unless position

            chain = path[0...position].select { |item| item.is_a?(Sketchup::Group) || item.is_a?(Sketchup::ComponentInstance) }
            if entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
                chain += [entity]
                box = entity.definition.bounds
            else
                box = entity.bounds
            end
            return [] if box.nil? || box.empty?

            matrix = self.Na__Pick__Compose(chain.map { |item| item.transformation.to_a })
            low  = box.min.to_a
            high = box.max.to_a
            (0..7).map do |corner|
                local = [(corner & 1).zero? ? low[0] : high[0],
                         (corner & 2).zero? ? low[1] : high[1],
                         (corner & 4).zero? ? low[2] : high[2]]
                self.Na__Pick__Apply(matrix, local)
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Matrices Multiplied in Order (column-major, as Transformation#to_a)
        # ------------------------------------------------------------
        # Compose([a, b, c]) = a * b * c: c applies first, then b, then a.
        def self.Na__Pick__Compose(matrices)
            matrices.reduce(NA_IDENTITY) do |left, right|
                (0..15).map do |slot|
                    column = slot / 4
                    row    = slot % 4
                    (0..3).sum { |k| left[(k * 4) + row].to_f * right[(column * 4) + k].to_f }
                end
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | One Point Through a Matrix, w Divided Out
        # ------------------------------------------------------------
        # SketchUp keeps a uniform scale in the last element (scaling(2) has 0.5
        # there), so the homogeneous w must be divided out.
        def self.Na__Pick__Apply(matrix, point)
            x, y, z = point.map(&:to_f)
            w = (matrix[3] * x) + (matrix[7] * y) + (matrix[11] * z) + matrix[15]
            w = 1.0 if w.abs < 1e-12
            [((matrix[0] * x) + (matrix[4] * y) + (matrix[8] * z) + matrix[12]) / w,
             ((matrix[1] * x) + (matrix[5] * y) + (matrix[9] * z) + matrix[13]) / w,
             ((matrix[2] * x) + (matrix[6] * y) + (matrix[10] * z) + matrix[14]) / w]
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Telling the Dialog
# -----------------------------------------------------------------------------

        # The tool calls these; done: the button lets go; cancelled: nothing more comes.
        def self.na_report(items, done:, cancelled: false)
            Na__AgentOutliner::Na__DialogManager.Na__Dialog__Send('chatPicked', { 'items' => items, 'done' => done, 'cancelled' => cancelled })
            return unless done && !cancelled && Na__AgentOutliner::Na__DialogManager.Na__Dialog__Visible?

            Na__AgentOutliner::Na__DialogManager.Na__Dialog__Deferred { Na__AgentOutliner::Na__DialogManager.Na__Dialog__Show }   # <-- Back to the message, ready to type
        end

        def self.na_tool_started(tool)
            @na_tool    = tool
            @na_running = true
        end

        # Another tool chosen (or the window closed) before a pick: the button lets go.
        def self.na_tool_ended(tool, finished)
            return unless tool.equal?(@na_tool)

            @na_tool    = nil
            @na_running = false
            self.na_report([], done: true, cancelled: true) unless finished
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | The Tool
# -----------------------------------------------------------------------------

        # CLASS | Click an Object to Mention It in the Chat
        # ------------------------------------------------------------
        class PickTool
            def initialize
                @hover  = nil                                                           # <-- { 'path', 'candidates' } under the cursor
                @offset = 0                                                             # <-- Steps out (negative) or in from the default
                @deep   = false                                                         # <-- Ctrl held: the part right under the cursor
                @boxes  = []                                                            # <-- World corners of objects already taken with Shift
                @x      = 0
                @y      = 0
                @done   = false
            end

            def activate
                Na__AgentOutliner::Na__ChatPick.na_tool_started(self)
                Sketchup.status_text = NA_HINT
            end

            def deactivate(view)
                view.invalidate
                Na__AgentOutliner::Na__ChatPick.na_tool_ended(self, @done)
            end

            def resume(view)
                Sketchup.status_text = NA_HINT
                view.invalidate
            end

            def suspend(view)
                view.invalidate
            end

            def onCancel(_reason, view)
                @done = true
                Na__AgentOutliner::Na__ChatPick.na_report([], done: true, cancelled: true)
                view.model.tools.pop_tool
            end

            def onMouseMove(flags, x, y, view)
                @x = x
                @y = y
                @deep = (flags & COPY_MODIFIER_MASK) != 0
                hover = Na__AgentOutliner::Na__ChatPick.Na__Pick__At(view, x, y)
                @offset = 0 unless self.na_same_stack?(hover, @hover)                    # <-- A new object under the cursor starts at its default again
                @hover = hover
                view.invalidate
            end

            def onLButtonDown(flags, x, y, view)
                @deep = (flags & COPY_MODIFIER_MASK) != 0
                hover = Na__AgentOutliner::Na__ChatPick.Na__Pick__At(view, x, y)
                @offset = 0 unless self.na_same_stack?(hover, @hover)
                @hover = hover
                entity = self.na_target
                unless entity
                    Sketchup.status_text = 'Agent Outliner: nothing to pick there. Click a group, component, picture or section plane (Esc cancels).'
                    return
                end

                info = Na__AgentOutliner::Na__ChatPick.Na__Pick__Info(entity)
                if (flags & CONSTRAIN_MODIFIER_MASK) != 0
                    @boxes << Na__AgentOutliner::Na__ChatPick.Na__Pick__BoxCorners(@hover['path'], entity)
                    Na__AgentOutliner::Na__ChatPick.na_report([info], done: false)
                    view.invalidate
                    return
                end

                @done = true
                Na__AgentOutliner::Na__ChatPick.na_report([info], done: true)
                view.model.tools.pop_tool
            end

            # One level out each right-click; past the outermost it goes back to the innermost.
            def onRButtonDown(_flags, x, y, view)
                @hover ||= Na__AgentOutliner::Na__ChatPick.Na__Pick__At(view, x, y)
                return unless @hover

                candidates = @hover['candidates']
                default = Na__AgentOutliner::Na__ChatPick.Na__Pick__DefaultIndex(candidates)
                index = Na__AgentOutliner::Na__ChatPick.Na__Pick__Index(candidates, @offset, false)
                @offset = index.positive? ? @offset - 1 : (candidates.length - 1) - default
                view.invalidate
            end

            def onKeyDown(key, _repeat, _flags, view)
                return false unless @hover

                candidates = @hover['candidates']
                default = Na__AgentOutliner::Na__ChatPick.Na__Pick__DefaultIndex(candidates)
                case key
                when VK_UP   then @offset = [@offset - 1, -default].max
                when VK_DOWN then @offset = [@offset + 1, (candidates.length - 1) - default].min
                else return false
                end
                view.invalidate
                true
            end

            def draw(view)
                @boxes.each { |corners| self.na_draw_box(view, corners, NA_PICKED_RGB) }
                entity = self.na_target
                return unless entity

                self.na_draw_box(view, Na__AgentOutliner::Na__ChatPick.Na__Pick__BoxCorners(@hover['path'], entity), NA_HOVER_RGB)
                view.draw_text(Geom::Point3d.new(@x + 18, @y + 20, 0), self.na_label(entity),
                               size: 11, bold: true, color: Sketchup::Color.new(*NA_HOVER_RGB))
            end

            def getExtents
                box = Geom::BoundingBox.new
                model = Sketchup.active_model
                box.add(model.bounds) if model
                corners = @boxes.flatten(1)
                entity = self.na_target
                corners += Na__AgentOutliner::Na__ChatPick.Na__Pick__BoxCorners(@hover['path'], entity) if entity
                corners.each { |corner| box.add(Geom::Point3d.new(*corner)) }
                box
            end

            # The object a click takes now, or nil.
            def na_target
                return nil unless @hover

                candidates = @hover['candidates']
                candidates[Na__AgentOutliner::Na__ChatPick.Na__Pick__Index(candidates, @offset, @deep)]
            end

            def na_label(entity)
                candidates = @hover['candidates']
                index = candidates.index { |item| item.equal?(entity) }.to_i
                info  = Na__AgentOutliner::Na__ChatPick.Na__Pick__Info(entity)
                "#{info['name']}   #{info['type']}, level #{index + 1} of #{candidates.length}"
            end

            def na_same_stack?(left, right)
                return false unless left && right

                left['candidates'].length == right['candidates'].length &&
                    left['candidates'].each_index.all? { |index| left['candidates'][index].equal?(right['candidates'][index]) }
            end

            def na_draw_box(view, corners, rgb)
                return if corners.nil? || corners.length < 8

                points = NA_EDGES.flat_map { |(from, to)| [Geom::Point3d.new(*corners[from]), Geom::Point3d.new(*corners[to])] }
                view.line_stipple  = ''
                view.line_width    = 3
                view.drawing_color = Sketchup::Color.new(*rgb)
                view.draw(GL_LINES, points)
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__ChatPick
end # module Na__AgentOutliner

# =============================================================================
# END OF FILE
# =============================================================================
