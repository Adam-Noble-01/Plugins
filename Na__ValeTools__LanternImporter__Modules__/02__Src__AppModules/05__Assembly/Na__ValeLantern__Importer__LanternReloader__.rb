# =============================================================================
# VALE LANTERN IMPORTER - LANTERN RELOADER
# =============================================================================
#
# FILE       : Na__ValeLantern__Importer__LanternReloader__.rb
# NAMESPACE  : Na__ValeLantern::Na__Importer
# MODULE     : Na__LanternReloader
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Rebuild a lantern that is already in the model from an updated
#              build file, without moving it.
#
# DESCRIPTION:
# - Finds the lantern to reload, asks for the new file, and replaces the geometry
#   INSIDE its component definition. The instance is never touched.
# - Owns the operation. Clearing the old geometry, releasing the definitions it
#   left behind and building the new payload all have to succeed or fail
#   together, and this is the only module that can see all three.
#
# -----------------------------------------------------------------------------
#
# WHY THIS IS THE ROBUST WAY TO REGENERATE IN PLACE:
#
# The obvious approach - delete the lantern, import the new file, move it back -
# fails at every step that matters. The user has moved and rotated the lantern
# onto a roof, so its transform has to be measured and reapplied, and any
# rounding in that round trip is a lantern a millimetre out of position. The
# lantern may have been copied three times along a roof, and only one of those
# copies would be replaced. Anything else in the model glued or aligned to it
# loses its reference. And the undo stack ends up holding a delete and an import
# as separate steps.
#
# Replacing the CONTENTS of the definition sidesteps all of it. A component
# instance is a definition plus a transform; rebuilding the definition changes
# what is drawn and leaves the transform alone, so:
#
#   - the lantern does not move, because nothing that positions it was touched
#   - EVERY copy of it regenerates at once, each one where it stands
#   - its name, its tag, its material and its attributes survive
#   - the whole thing is one undo step
#
# This is also why the import builds a component rather than a group. A group has
# a definition too and this works on one, which is what lets a lantern imported
# before version 1.4.0 still be reloaded - but a group cannot carry the second
# and third copies that make the rest of the argument.
#
# -----------------------------------------------------------------------------
#
# THE ORDER OF THE REBUILD IS NOT ARBITRARY:
#
#   1  COLLECT the definitions the previous build created, by walking the root
#      definition before anything is destroyed. After the clear there is nothing
#      left to walk.
#   2  CLEAR the root definition's entities.
#   3  RELEASE the collected definitions that no longer carry a single instance
#      anywhere in the model, OUTERMOST FIRST, so an assembly definition goes
#      before the part definitions nested inside it and each one is genuinely
#      unused by the time it is tested.
#   4  BUILD the new payload into the emptied definition.
#
# Step 3 must come BEFORE step 4, and not only to keep the Component browser from
# growing by thirty entries on every reload. Definition names are unique in a
# model, so a name still taken by the old build forces the new one onto
# Name__2, then Name__3, and a lantern reloaded five times would carry five
# generations of suffix. Releasing first hands the names back.
#
# NAMING CONVENTION:
# - Importer namespace Na__Importer / na_ prefixes.
#
# =============================================================================

require 'sketchup.rb'

module Na__ValeLantern
    module Na__Importer
        module Na__LanternReloader

# -----------------------------------------------------------------------------
# REGION | Module References and Constants
# -----------------------------------------------------------------------------

            DebugTools    = Na__ValeLantern::Na__Importer::Na__DebugTools
            ConfigLoader  = Na__ValeLantern::Na__Importer::Na__ConfigLoader
            PayloadReader = Na__ValeLantern::Na__Importer::Na__PayloadReader
            ModelComposer = Na__ValeLantern::Na__Importer::Na__ModelComposer
            Main          = Na__ValeLantern::Na__Importer::Na__Main

            NA_ATTRIBUTE_DICTIONARY = 'VghLantern'.freeze
            NA_RECORD_ROOT          = 'ValeLanternRoot'.freeze
            NA_OPERATION_NAME       = 'Reload Vale Lantern'.freeze
            NA_PICKER_TITLE         = 'Select the updated Vale Lantern build file'.freeze

            NA_MAX_TREE_DEPTH       = 12                                                            # <-- The hierarchy is three deep; this is a runaway guard, not a limit
            NA_DIALOG_TITLE         = 'Reload Lantern Json'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Reload — Public API
# -----------------------------------------------------------------------------

            # FUNCTION | Rebuild one lantern in place from an updated build file
            # ------------------------------------------------------------
            # @param file_path [String, nil] Skip the picker by passing a path
            # @param target [Sketchup::ComponentInstance, Sketchup::Group, nil]
            #        Skip the target resolution by passing the root container
            # @return [Boolean] true when a lantern was rebuilt
            def self.na_reload(file_path = nil, target = nil)
                model = Sketchup.active_model
                unless model
                    DebugTools.na_error('There is no open model to reload into.')
                    return false
                end

                unless ConfigLoader.na_reload_in_place?
                    DebugTools.na_error('Reload in place is switched off in the importer config.')
                    return false
                end

                container = target || na_resolve_target(model)
                return false if container.nil?

                definition = na_definition_of(container)
                if definition.nil?
                    DebugTools.na_error('That lantern carries no component definition and cannot be rebuilt in place.')
                    return false
                end

                chosen = file_path || na_ask_for_file(container, definition)
                if chosen.nil?
                    DebugTools.na_info('Reload cancelled.')
                    return false
                end

                payload = PayloadReader.na_read_payload(chosen)
                return false if payload.nil?

                return false unless na_identity_agrees?(container, definition, payload)

                na_rebuild(model, container, definition, payload, chosen)
            end
            # ---------------------------------------------------------------

            # FUNCTION | The lantern the current selection points at, or nil
            # ------------------------------------------------------------
            # NON INTERACTIVE AND CHEAP, which is the whole point of it existing
            # separately from na_resolve_target. The context menu handler runs on
            # EVERY right click in SketchUp, so it can neither open a dialog to
            # decide what to show nor walk the model to find out.
            #
            # It therefore answers only from what the user has already pointed at -
            # the selection, then the open edit context - and never falls back to
            # scanning for the model's only lantern. That is the correct answer for
            # a context menu as well as the fast one: a right click on empty space
            # is not a request to reload something elsewhere in the model.
            #
            # @param examine_limit [Integer, nil] Stop after this many selected
            #        entities. A right click must not lag behind a selection of
            #        forty thousand faces, and a lantern being reloaded is always
            #        within the first few of a deliberate selection.
            # @return [Sketchup::ComponentInstance, Sketchup::Group, nil]
            def self.na_selected_lantern(examine_limit = nil)
                model = Sketchup.active_model
                return nil unless model

                from_selection = na_root_from_selection(model, examine_limit)
                return from_selection if from_selection

                na_root_from_active_path(model)
            rescue StandardError
                nil
            end
            # ---------------------------------------------------------------

            # FUNCTION | The build file a lantern was last built from, if it is still there
            # ------------------------------------------------------------
            # Returns nil rather than a dead path, so a caller offering to rebuild
            # from it never offers a file that has since been moved or deleted.
            #
            # @return [String, nil]
            def self.na_source_file_for(container)
                return nil unless container
                return nil unless ConfigLoader.na_remembers_source_file?

                path = na_read_stamp(container, na_definition_of(container), 'SourceFilePath').to_s
                return nil if path.empty?
                return nil unless File.exist?(path)

                path
            rescue StandardError
                nil
            end
            # ---------------------------------------------------------------

            # FUNCTION | A readable one line description of one lantern
            # ------------------------------------------------------------
            # Public so the context menu can name what it is about to act on.
            def self.na_describe(root)
                definition = na_definition_of(root)
                name       = root.name.to_s
                name       = definition.name.to_s if name.empty? && definition

                title = na_read_stamp(root, definition, 'LanternTitle').to_s
                code  = na_read_stamp(root, definition, 'ProjectCode').to_s

                detail = [code, title].reject { |value| value.empty? }.join(' ')
                detail.empty? ? name : "#{name}  (#{detail})"
            rescue StandardError
                'Vale Lantern'
            end
            # ---------------------------------------------------------------

            # FUNCTION | Every Vale lantern root container in the model
            # ------------------------------------------------------------
            # Found by walking the DEFINITIONS rather than the entities. A lantern
            # dropped inside somebody's building group is nested arbitrarily deep,
            # and definitions are a flat list of everything the model holds however
            # deeply it is placed - so this costs one pass whatever the model looks
            # like.
            #
            # Both the definition and its instances are tested, because a lantern
            # imported before version 1.4.0 carries the stamp on its group and not
            # on the group's definition.
            #
            # @return [Array] Root containers, instances and groups alike
            def self.na_find_lantern_roots(model)
                found = []
                seen  = {}

                model.definitions.each do |definition|
                    next if definition.deleted?

                    definition_is_root = na_stamped_root?(definition)

                    definition.instances.each do |instance|
                        next unless instance.valid?
                        next unless definition_is_root || na_stamped_root?(instance)
                        next if seen.key?(instance.entityID)

                        seen[instance.entityID] = true
                        found << instance
                    end
                end

                found
            rescue StandardError => e
                DebugTools.na_error("The model could not be searched for lanterns: #{e.message}")
                []
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal — The Rebuild Itself
# -----------------------------------------------------------------------------

            # HELPER FUNCTION | Clear, release and rebuild, as one operation
            # ------------------------------------------------------------
            def self.na_rebuild(model, container, definition, payload, source_path)
                choices  = na_choices_for(container, definition, source_path)
                placings = na_placement_count(definition)

                DebugTools.na_reset_tally
                model.start_operation(NA_OPERATION_NAME, true)

                begin
                    previous = na_collect_child_definitions(definition)

                    # Entities#clear! answers false on a collection that was
                    # already empty as well as on one it could not clear, and an
                    # empty root definition is a real state - a previous reload
                    # that failed part way through leaves one. The emptiness is
                    # therefore tested rather than inferred from the return.
                    if definition.entities.length > 0 && !definition.entities.clear!
                        model.abort_operation
                        DebugTools.na_error('The existing lantern geometry could not be cleared. The model is unchanged.')
                        return false
                    end

                    released = na_release_definitions(model, previous)
                    DebugTools.na_info("Previous build cleared; #{released} of #{previous.length} definition(s) released.")

                    na_rename_root(model, container, definition, payload)

                    expected = ModelComposer.na_rebuild(definition, container, payload, choices)
                    if expected.nil?
                        model.abort_operation
                        DebugTools.na_error('Nothing was built. The lantern is unchanged.')
                        return false
                    end

                    model.commit_operation
                    DebugTools.na_report_summary(expected)
                    DebugTools.na_info("Reload complete: #{definition.name} - #{placings} placement(s) updated in place.")
                    true

                rescue StandardError => e
                    model.abort_operation
                    DebugTools.na_error("Reload aborted (#{e.class}): #{e.message}")
                    DebugTools.na_error(e.backtrace.first(6).join("\n    ")) if e.backtrace
                    false
                end
            end
            private_class_method :na_rebuild

            # HELPER FUNCTION | Every definition nested under one container definition
            # ------------------------------------------------------------
            # PRE ORDER, parents before children, which is the order they have to
            # be released in. Only definitions this plugin stamped are collected: a
            # finial shared with another Noble Architecture tool, or anything the
            # user has dropped inside the lantern themselves, is not this routine's
            # to delete.
            def self.na_collect_child_definitions(definition, seen = {}, depth = 0)
                return [] if depth > NA_MAX_TREE_DEPTH
                return [] if definition.nil? || definition.deleted?

                found = []

                definition.entities.each do |entity|
                    next unless entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)

                    child = na_definition_of(entity)
                    next if child.nil? || child.deleted?
                    next if seen.key?(child.entityID)

                    seen[child.entityID] = true
                    found << child if na_definition_is_ours?(child)
                    found.concat(na_collect_child_definitions(child, seen, depth + 1))
                end

                found
            rescue StandardError => e
                DebugTools.na_detail("Definition tree could not be walked: #{e.message}")
                []
            end
            private_class_method :na_collect_child_definitions

            # HELPER FUNCTION | Remove the definitions nothing places any more
            # ------------------------------------------------------------
            # count_used_instances rather than count_instances, because after the
            # clear a part definition's instances survive inside assembly
            # definitions that are themselves unused. count_used_instances reads
            # through that nesting and answers zero; count_instances would answer
            # four and nothing would ever be released.
            #
            # Deliberately NOT model.definitions.purge_unused, which would take the
            # user's own unused components with it.
            def self.na_release_definitions(model, definitions)
                return 0 unless ConfigLoader.na_reload_removes_orphans?

                released = 0

                definitions.each do |definition|
                    next if definition.nil? || definition.deleted?
                    next unless na_definition_is_ours?(definition)
                    next unless na_placement_count(definition).zero?

                    begin
                        model.definitions.remove(definition)
                        released += 1
                    rescue StandardError => e
                        DebugTools.na_detail("Definition could not be released: #{e.message}")
                    end
                end

                released
            end
            private_class_method :na_release_definitions

            # HELPER FUNCTION | How many times a definition actually appears
            # ------------------------------------------------------------
            def self.na_placement_count(definition)
                return 0 if definition.nil? || definition.deleted?
                return definition.count_used_instances if definition.respond_to?(:count_used_instances)
                return definition.count_instances      if definition.respond_to?(:count_instances)
                definition.instances.length
            rescue StandardError
                0
            end
            private_class_method :na_placement_count

            # HELPER FUNCTION | Whether this plugin created a definition
            # ------------------------------------------------------------
            # Keyed on RecordType, which the registry and the composer stamp on
            # every definition they make. Deliberately NOT matched on the name: a
            # user is free to rename a component, and a name match would also
            # catch anything they had built and named to look like ours.
            #
            # Authored finial definitions carry an AssetId and no RecordType, so
            # they are never released - which is right, because they are reused by
            # name across imports and shared with the rest of the toolchain.
            def self.na_definition_is_ours?(definition)
                record = definition.get_attribute(NA_ATTRIBUTE_DICTIONARY, 'RecordType')
                !record.nil? && record.to_s != NA_RECORD_ROOT                                        # <-- Never the root: it is the thing being rebuilt
            rescue StandardError
                false
            end
            private_class_method :na_definition_is_ours?

            # HELPER FUNCTION | Rename the root to match the incoming payload
            # ------------------------------------------------------------
            # A lantern renamed in the web application should be renamed here, or
            # the model quietly disagrees with the drawing. A name another
            # definition already holds - a second lantern from the same project -
            # is left alone and reported rather than forced onto a suffix.
            def self.na_rename_root(model, container, definition, payload)
                model_block = payload['Model']
                return unless model_block.is_a?(Hash)

                target = model_block['RootGroupName'].to_s
                return if target.empty?
                return if definition.name == target

                existing = model.definitions[target]
                if existing && existing != definition
                    DebugTools.na_warn("'#{target}' is already the name of another component - the lantern keeps the name '#{definition.name}'.")
                    return
                end

                previous        = definition.name
                definition.name = target
                container.name  = target if container.is_a?(Sketchup::ComponentInstance)             # <-- A Group's name IS its definition name, already set above
                DebugTools.na_info("Lantern renamed from '#{previous}' to '#{target}'.")

            rescue StandardError => e
                DebugTools.na_warn("The lantern could not be renamed: #{e.message}")
            end
            private_class_method :na_rename_root

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal — Target Resolution
# -----------------------------------------------------------------------------

            # HELPER FUNCTION | Work out which lantern the user means
            # ------------------------------------------------------------
            # In order of how explicit the user has been about it: what they have
            # selected, what they are currently inside, then whatever the model
            # holds - and only ASK when the model holds more than one and they
            # have said nothing.
            def self.na_resolve_target(model)
                selected = na_root_from_selection(model)
                return selected if selected

                open_context = na_root_from_active_path(model)
                return open_context if open_context

                roots = na_find_lantern_roots(model)

                if roots.empty?
                    DebugTools.na_error(
                        'No Vale lantern was found in this model. Use Import Lantern Build File to bring one in first.'
                    )
                    return nil
                end

                return roots.first if roots.length == 1

                na_ask_which_lantern(roots)
            end
            private_class_method :na_resolve_target

            # HELPER FUNCTION | A lantern root reachable from the selection
            # ------------------------------------------------------------
            # Selecting a single glaze bar and asking for a reload is a perfectly
            # clear instruction, so a selected entity is walked UP to the lantern
            # that contains it rather than rejected for not being a root.
            #
            # @param examine_limit [Integer, nil] Stop after this many entities.
            #        nil for the menu driven path, where the user is waiting on a
            #        result and correctness beats latency; a small cap for the
            #        context menu, where nobody is waiting and a right click must
            #        not stall behind a huge selection.
            def self.na_root_from_selection(model, examine_limit = nil)
                selection = model.selection
                return nil if selection.nil? || selection.empty?

                examined = 0
                selection.each do |entity|
                    return nil if examine_limit && examined >= examine_limit
                    examined += 1

                    root = na_ascend_to_root(entity)
                    return root if root
                end

                nil
            rescue StandardError
                nil
            end
            private_class_method :na_root_from_selection

            # HELPER FUNCTION | A lantern root in the open edit context
            # ------------------------------------------------------------
            # Somebody who has double clicked into a lantern to look at a part has
            # named it as clearly as somebody who selected it.
            def self.na_root_from_active_path(model)
                path = model.active_path
                return nil unless path.is_a?(Array)

                path.reverse_each do |entity|
                    return entity if na_is_root?(entity)
                end

                nil
            rescue StandardError
                nil
            end
            private_class_method :na_root_from_active_path

            # HELPER FUNCTION | Climb from an entity to the lantern containing it
            # ------------------------------------------------------------
            # An entity's parent is its ComponentDefinition, and a definition can
            # be placed in more than one spot, so the climb branches. It stops at
            # the first root it reaches, which on the only hierarchy that exists
            # here is the only one there is.
            def self.na_ascend_to_root(entity, depth = 0)
                return nil if entity.nil? || depth > NA_MAX_TREE_DEPTH
                return entity if na_is_root?(entity)

                parent = entity.parent
                return nil unless parent.is_a?(Sketchup::ComponentDefinition)

                parent.instances.each do |instance|
                    found = na_ascend_to_root(instance, depth + 1)
                    return found if found
                end

                nil
            rescue StandardError
                nil
            end
            private_class_method :na_ascend_to_root

            # HELPER FUNCTION | Whether one entity is a lantern root
            # ------------------------------------------------------------
            def self.na_is_root?(entity)
                return false unless entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)
                return true if na_stamped_root?(entity)

                definition = na_definition_of(entity)
                !definition.nil? && na_stamped_root?(definition)
            rescue StandardError
                false
            end
            private_class_method :na_is_root?

            # HELPER FUNCTION | Whether one entity carries the root stamp
            # ------------------------------------------------------------
            def self.na_stamped_root?(entity)
                entity.get_attribute(NA_ATTRIBUTE_DICTIONARY, 'RecordType').to_s == NA_RECORD_ROOT
            rescue StandardError
                false
            end
            private_class_method :na_stamped_root?

            # HELPER FUNCTION | The definition behind a group or an instance
            # ------------------------------------------------------------
            def self.na_definition_of(entity)
                return nil unless entity
                return nil unless entity.respond_to?(:definition)
                entity.definition
            rescue StandardError
                nil
            end
            private_class_method :na_definition_of

            # HELPER FUNCTION | Ask which of several lanterns to reload
            # ------------------------------------------------------------
            # The labels are numbered because UI.inputbox hands back the chosen
            # STRING rather than its index, and two lanterns of the same title in
            # one model would otherwise be indistinguishable to the lookup.
            def self.na_ask_which_lantern(roots)
                labels = roots.each_with_index.map { |root, index| "#{index + 1}  #{na_describe(root)}" }

                answer = UI.inputbox(
                    ['Lantern to reload'],
                    [labels.first],
                    [labels.join('|')],
                    NA_DIALOG_TITLE
                )
                return nil unless answer.is_a?(Array) && answer[0]

                chosen = labels.index(answer[0])
                return nil if chosen.nil?

                roots[chosen]
            rescue StandardError => e
                DebugTools.na_error("The lantern could not be chosen: #{e.message}")
                nil
            end
            private_class_method :na_ask_which_lantern

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal — File Choice and Identity
# -----------------------------------------------------------------------------

            # HELPER FUNCTION | Ask for the build file, opening where it came from
            # ------------------------------------------------------------
            # The picker is ALWAYS shown, even when the lantern remembers exactly
            # which file it was built from. A reload replaces geometry somebody has
            # positioned and may have copied, and doing that off a remembered path
            # without showing it is the kind of convenience that is only ever
            # noticed when it was wrong.
            def self.na_ask_for_file(container, definition)
                remembered = na_read_stamp(container, definition, 'SourceFilePath').to_s
                start_dir  = nil

                if ConfigLoader.na_remembers_source_file? && !remembered.empty?
                    folder    = File.dirname(remembered)
                    start_dir = folder if File.directory?(folder)
                end

                chosen = Main.na_ask_for_file(NA_PICKER_TITLE, start_dir)
                Main.na_remember_directory(chosen) if chosen
                chosen
            end
            private_class_method :na_ask_for_file

            # HELPER FUNCTION | Check the file is for the lantern being reloaded
            # ------------------------------------------------------------
            # Reloading one lantern's file over another is a legitimate thing to
            # want - it is how you swap an orangery lantern for a kitchen one in
            # place - but it is far more often a wrong file picked in a hurry, so
            # it asks rather than refusing or proceeding quietly.
            def self.na_identity_agrees?(container, definition, payload)
                return true unless ConfigLoader.na_reload_confirms_different_lantern?

                existing = na_read_stamp(container, definition, 'LanternId').to_s
                incoming = (payload['Lantern'] || {})['Id'].to_s
                return true if existing.empty? || incoming.empty?
                return true if existing == incoming

                existing_title = na_read_stamp(container, definition, 'LanternTitle').to_s
                incoming_title = (payload['Lantern'] || {})['Title'].to_s

                answer = UI.messagebox(
                    "This build file is for a different lantern.\n\n" \
                    "In the model : #{existing_title} (#{existing})\n" \
                    "In the file  : #{incoming_title} (#{incoming})\n\n" \
                    'Rebuild the lantern in the model from this file anyway?',
                    MB_YESNO
                )

                return true if answer == IDYES

                DebugTools.na_info('Reload cancelled - the build file is for a different lantern.')
                false
            rescue StandardError => e
                DebugTools.na_warn("The lantern identity could not be checked: #{e.message}")
                true                                                                                # <-- A check that cannot run must not block the reload
            end
            private_class_method :na_identity_agrees?

            # HELPER FUNCTION | The build choices to rebuild with
            # ------------------------------------------------------------
            # Read back off the lantern itself, so one imported with its
            # construction linework reloads with its construction linework and one
            # imported without does not silently gain it.
            #
            # A lantern imported before version 1.4.0 carries neither stamp and
            # falls to the metal alone, which is what those imports built.
            def self.na_choices_for(container, definition, source_path)
                unless ConfigLoader.na_reload_preserves_choices?
                    return { :BuildModel => true, :BuildSettingOut => false, :SourceFilePath => source_path }
                end

                {
                    :BuildModel      => na_read_stamp(container, definition, 'BuiltModel')      != false,
                    :BuildSettingOut => na_read_stamp(container, definition, 'BuiltSettingOut') == true,
                    :SourceFilePath  => source_path
                }
            end
            private_class_method :na_choices_for

            # HELPER FUNCTION | Read one stamp off the instance, then the definition
            # ------------------------------------------------------------
            # The instance is asked first because that is where a lantern imported
            # before version 1.4.0 carries everything.
            def self.na_read_stamp(container, definition, key)
                value = container.get_attribute(NA_ATTRIBUTE_DICTIONARY, key) if container
                return value unless value.nil?
                return nil if definition.nil?

                definition.get_attribute(NA_ATTRIBUTE_DICTIONARY, key)
            rescue StandardError
                nil
            end
            private_class_method :na_read_stamp

# endregion -------------------------------------------------------------------

        end
    end
end
