# =============================================================================
# NA AGENT OUTLINER - MODEL DATA - NAMING (QUICK NAME AND RENAME)
# =============================================================================
#
# FILE       : Na__AgentOutliner__ModelData__Naming__.rb
# NAMESPACE  : Na__AgentOutliner::Na__Naming
# MODULE     : Na__Naming (module functions)
# AUTHOR     : Noble Architecture
# PURPOSE    : Give objects their standard names quickly (CAD__FrontElevation,
#              REF__SideElevation ...), rename one or many, and strip a
#              standard prefix again
# CREATED    : 10-Nov-2026
#
# DESCRIPTION:
# - NAMES, NOT TAGS. Quick Name only ever sets an object's NAME (the instance
#   name of a group or component, the name of a section plane). It never
#   touches its tag: Adam, 10-Nov-2026, "I said Tag should have said Name so
#   it can name groups quickly, tag is something different".
# - TWO MODES per prefix (Configure tab):
#     replace : the name becomes exactly the label   (CAD__FrontElevation)
#     prefix  : label + "__" + the name it had        (REF__SideElevation)
#   A name that already starts with any standard label has that label swapped,
#   never stacked (no CAD__FrontElevation__CAD__RearElevation). SketchUp's
#   placeholder names (Group, Component#3) count as no name at all.
# - Components are renamed by their INSTANCE name, as SketchUp's Outliner
#   does; the definition (shared by every copy) is never renamed here.
# - Images carry no name in SketchUp's API, so they are refused with that
#   reason rather than skipped silently.
# - One undo step per click, named for what it did.
#
# =============================================================================

module Na__AgentOutliner
    module Na__Naming

# -----------------------------------------------------------------------------
# REGION | Matching
# -----------------------------------------------------------------------------

        # FUNCTION | The Standard Prefix a Name Starts With (longest wins), or nil
        # ------------------------------------------------------------
        def self.Na__Naming__MatchPrefix(name, prefixes)
            text = name.to_s
            return nil if text.empty?

            Array(prefixes).select do |entry|
                label = entry['label'].to_s
                entry['mode'] != 'face' && !label.empty? && (text.casecmp(label).zero? || text.downcase.start_with?("#{label.downcase}__"))
            end.max_by { |entry| entry['label'].length }
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Name With Any Standard Prefix Taken Off ('' when nothing is left)
        # ------------------------------------------------------------
        def self.Na__Naming__Tail(name, prefixes)
            text = name.to_s.strip
            return '' if Na__AgentOutliner::Na__Walker.Na__Walker__GenericName?(text)

            entry = self.Na__Naming__MatchPrefix(text, prefixes)
            return text unless entry

            text[entry['label'].length..-1].to_s.sub(/\A_+/, '')
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Name an Object Gets From a Prefix Entry
        # ------------------------------------------------------------
        def self.Na__Naming__Compose(current_name, entry, prefixes, front: '')
            label = entry['label'].to_s
            return self.Na__Naming__ComposeFace(current_name, label, front) if entry['mode'] == 'face'
            return label if entry['mode'] == 'replace'

            tail = self.Na__Naming__Tail(current_name, prefixes)
            tail.empty? ? label : "#{label}__#{tail}"
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Writing (each call is ONE undo step)
# -----------------------------------------------------------------------------

        # FUNCTION | Quick Name: Apply One Standard Prefix to Several Objects
        # ------------------------------------------------------------
        # Returns { 'renamed' => [{id, from, to}], 'unchanged' => n, 'refused' => [reasons] }.
        def self.Na__Naming__Apply(model, entities, entry, operation_name: nil)
            raise ArgumentError, 'That naming prefix is not in the standards any more.' unless entry

            prefixes = Na__AgentOutliner::Na__ConfigStore.Na__Standards__Prefixes
            front = self.Na__Naming__FrontFaces(model)
            plan = self.na_plan(entities) do |entity|
                self.Na__Naming__Compose(Na__AgentOutliner::Na__Walker.Na__Walker__Name(entity), entry, prefixes, front: front)
            end
            label = entry['mode'] == 'face' ? "Face #{[entry['label'], self.Na__Naming__CardinalFor(entry['label'], front)].compact.join('__')}" : entry['label']
            self.na_commit(model, plan, operation_name || "Agent Outliner: Name #{label}")
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Elevation Faces (Adam's standard, 11-Nov-2026)
# -----------------------------------------------------------------------------
#
# A building's sides are named for SketchUp's default orthographic views: Front
# (faces -Y), Back (+Y), Left (-X), Right (+X), Top (+Z). The face is a SEGMENT
# inside a name, never a prefix: SUB__Orangery__DoorHandle__Front__01,
# SUB__LineworkDetailing__Left__Doors. When Adam gives the model a real-world
# orientation (which way Front faces), every face word carries its cardinal
# straight after it: Front__South, Left__West ("a relative model and a real-world
# cardinal, two reference points"). The orientation is stored on the model.

        # FUNCTION | The Face Words, the Cardinals, and Where the Orientation Lives
        # ------------------------------------------------------------
        def self.Na__Naming__Faces
            %w[Front Back Left Right Top]
        end

        def self.Na__Naming__Cardinals
            %w[North East South West]
        end

        def self.na_orientation_dict
            'Na__AgentOutliner__Orientation'
        end
        # ---------------------------------------------------------------

        # FUNCTION | Which Way the Model's Front Faces ('' when Adam has not said)
        # ------------------------------------------------------------
        def self.Na__Naming__FrontFaces(model)
            return '' unless model

            value = model.get_attribute(self.na_orientation_dict, 'front_faces', '').to_s
            self.Na__Naming__Cardinals.include?(value) ? value : ''
        end
        # ---------------------------------------------------------------

        # FUNCTION | Set Which Way the Front Faces (one undo step; '' clears it)
        # ------------------------------------------------------------
        def self.Na__Naming__SetFrontFaces(model, cardinal)
            value = cardinal.to_s.strip.capitalize
            raise ArgumentError, "Front can face North, East, South or West (or nothing), not #{cardinal}." unless value.empty? || self.Na__Naming__Cardinals.include?(value)
            return value if value == self.Na__Naming__FrontFaces(model)

            Na__AgentOutliner.Na__Model__WithOperation(model, value.empty? ? 'Agent Outliner: Clear Orientation' : "Agent Outliner: Front Faces #{value}") do
                if value.empty?
                    model.delete_attribute(self.na_orientation_dict, 'front_faces') if model.attribute_dictionary(self.na_orientation_dict)
                else
                    model.set_attribute(self.na_orientation_dict, 'front_faces', value)
                end
            end
            value
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Cardinal a Face Points To, Given Which Way Front Faces (nil for none)
        # ------------------------------------------------------------
        # Clockwise North, East, South, West. Front faces `front`; Left is a
        # quarter turn on from it (Front South -> Left West), Back a half turn,
        # Right three quarters (Front South -> Right East). Top has none.
        def self.Na__Naming__CardinalFor(face, front)
            turns = { 'Front' => 0, 'Left' => 1, 'Back' => 2, 'Right' => 3 }[face.to_s]
            start = self.Na__Naming__Cardinals.index(front.to_s)
            return nil unless turns && start

            self.Na__Naming__Cardinals[(start + turns) % 4]
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Face and Cardinal a Name Carries ([face or nil, cardinal or nil])
        # ------------------------------------------------------------
        def self.Na__Naming__ParseFace(name)
            parts = name.to_s.split('__')
            index = parts.index { |part| self.Na__Naming__Faces.include?(part) }
            return [nil, nil] unless index

            following = parts[index + 1]
            [parts[index], self.Na__Naming__Cardinals.include?(following) ? following : nil]
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Name With Its Face Set (swapped in place, or put before a trailing number)
        # ------------------------------------------------------------
        #   SUB__Orangery__DoorHandle__01          + Front        -> SUB__Orangery__DoorHandle__Front__01
        #   SUB__Orangery__DoorHandle__Left__01    + Front        -> SUB__Orangery__DoorHandle__Front__01
        #   SUB__LineworkDetailing__Front__Doors   + Left, South  -> SUB__LineworkDetailing__Left__West__Doors
        #   (no name)                              + Top          -> Top
        def self.Na__Naming__ComposeFace(current_name, face, front)
            text = current_name.to_s.strip
            text = '' if Na__AgentOutliner::Na__Walker.Na__Walker__GenericName?(text)
            insert = [face.to_s, self.Na__Naming__CardinalFor(face, front)].compact
            trailing = text.end_with?('__')
            parts = text.sub(/_+\z/, '').split('__').reject(&:empty?)
            index = parts.index { |part| self.Na__Naming__Faces.include?(part) }
            if index
                stop = index + 1
                stop += 1 if parts[stop] && self.Na__Naming__Cardinals.include?(parts[stop])
                parts[index...stop] = insert
            elsif parts[0] == 'SUB' && parts[1] == 'LineworkDetailing' && parts.length > 2
                parts.insert(2, *insert)                                  # SUB__LineworkDetailing__<Face>__<Feature>
            else
                at = parts.length
                at -= 1 if at > 0 && parts[at - 1].match?(/\A\d+\z/)
                parts.insert(at, *insert)                                 # SUB__<Building>__<Asset>__<Face>__NN
            end
            result = parts.join('__')
            trailing && !result.empty? ? "#{result}__" : result
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Writing, Continued (strip, rename, find and replace)
# -----------------------------------------------------------------------------

        # FUNCTION | Take Any Standard Prefix Off Several Objects
        # ------------------------------------------------------------
        def self.Na__Naming__Strip(model, entities, operation_name: nil)
            prefixes = Na__AgentOutliner::Na__ConfigStore.Na__Standards__Prefixes
            plan = self.na_plan(entities) do |entity|
                name = Na__AgentOutliner::Na__Walker.Na__Walker__Name(entity)
                self.Na__Naming__MatchPrefix(name, prefixes) ? self.Na__Naming__Tail(name, prefixes) : name
            end
            self.na_commit(model, plan, operation_name || 'Agent Outliner: Strip Prefix')
        end
        # ---------------------------------------------------------------

        # FUNCTION | Rename Objects to One Name (Several Get __01, __02 ...)
        # ------------------------------------------------------------
        def self.Na__Naming__Rename(model, entities, new_name)
            name = new_name.to_s.strip
            raise ArgumentError, 'A name cannot have a line break.' if name.include?("\n")
            raise ArgumentError, 'A name can be up to 200 characters.' if name.length > 200

            count = entities.length
            plan = self.na_plan(entities) do |_entity, index|
                count > 1 && !name.empty? ? format('%s__%02d', name, index + 1) : name
            end
            self.na_commit(model, plan, count > 1 ? 'Agent Outliner: Rename Objects' : 'Agent Outliner: Rename')
        end
        # ---------------------------------------------------------------

        # FUNCTION | Find and Replace in Several Names (plain text or a pattern)
        # ------------------------------------------------------------
        def self.Na__Naming__Replace(model, entities, find, replace, use_pattern: false)
            raise ArgumentError, 'Say what to find.' if find.to_s.empty?

            pattern = if use_pattern
                          begin
                              Regexp.new(find.to_s)
                          rescue RegexpError => error
                              raise ArgumentError, "That pattern does not read: #{error.message}"
                          end
                      else
                          Regexp.new(Regexp.escape(find.to_s), Regexp::IGNORECASE)
                      end
            plan = self.na_plan(entities) do |entity|
                Na__AgentOutliner::Na__Walker.Na__Walker__Name(entity).gsub(pattern) { replace.to_s }
            end
            self.na_commit(model, plan, 'Agent Outliner: Find and Replace Names')
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Helpers
# -----------------------------------------------------------------------------

        # Works out every new name BEFORE the undo step opens: refusals are
        # collected, objects already named so are counted, and nothing is
        # written when there is nothing to change.
        def self.na_plan(entities)
            renames   = []
            refused   = []
            unchanged = 0
            Array(entities).each_with_index do |entity, index|
                unless entity && entity.valid?
                    refused << 'An object no longer exists (it was erased or undone).'
                    next
                end
                unless entity.respond_to?(:name=)
                    refused << "#{Na__AgentOutliner::Na__Walker.Na__Walker__DisplayName(entity)} cannot be named in SketchUp (#{entity.typename})."
                    next
                end

                target = yield(entity, index).to_s
                current = Na__AgentOutliner::Na__Walker.Na__Walker__Name(entity)
                if current == target
                    unchanged += 1
                else
                    renames << [entity, current, target]
                end
            end
            { renames: renames, refused: refused, unchanged: unchanged }
        end

        def self.na_commit(model, plan, operation_name)
            unless plan[:renames].empty?
                Na__AgentOutliner.Na__Model__WithOperation(model, operation_name) do
                    plan[:renames].each { |entity, _from, to| entity.name = to }
                end
            end
            {
                'renamed'   => plan[:renames].map { |entity, from, to| { 'id' => entity.persistent_id, 'from' => from, 'to' => to } },
                'unchanged' => plan[:unchanged],
                'refused'   => plan[:refused]
            }
        end

# endregion -------------------------------------------------------------------

    end # module Na__Naming
end # module Na__AgentOutliner

# =============================================================================
# END OF FILE
# =============================================================================
