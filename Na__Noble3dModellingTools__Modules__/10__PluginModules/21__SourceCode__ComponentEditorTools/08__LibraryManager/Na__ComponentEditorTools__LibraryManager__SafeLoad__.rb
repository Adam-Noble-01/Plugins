# =============================================================================
# NA COMPONENT EDITOR TOOLS - LIBRARY MANAGER | SAFE DEFINITION LOAD
# =============================================================================
#
# FILE       : Na__ComponentEditorTools__LibraryManager__SafeLoad__.rb
# NAMESPACE  : Na__ComponentEditorTools::Na__LibrarySafeLoad
# PURPOSE    : Load a library .skp into the open model to read or edit it, and
#              leave that model exactly as it was afterwards.
# CREATED    : 2026
#
# WHY THIS EXISTS (checked live in SketchUp 2026.2 on 30-Sep-2026):
# - DefinitionList#load brings every nested definition with it (20 for the
#   fleur-de-lis finial). Removing only the top definition afterwards leaves
#   the rest behind as orphans in whatever model is open.
# - Loading a path that is already loaded returns the SAME definition, placed
#   instances and all. DefinitionList#remove on it deletes those instances.
# - A name clash (even with a name SketchUp still reserves from an earlier
#   rename in the session) renames the loaded definition, e.g. "...Type-01"
#   becomes "...Type-#1". Saving it back writes that "#1" into the file. This
#   is how "#1" / "#4" names got into several library files.
#
# THE RULE:
# Every load runs inside start_operation ... abort_operation. The abort takes
# the definition and everything that came with it back out, and reverts any
# rename or attribute edit made to a definition that was already in the model.
# save_as and save_thumbnail write to disk, so their files survive the abort.
# Never call this while another operation is open (an MCP batch or a
# router-wrapped tool): SketchUp does not nest operations.
#
# UNSEEN BY THE AGENT OUTLINER (17-Nov-2026):
# The load and abort run inside Na__AgentOutliner::Na__Observers__Quietly when
# the Agent Outliner is loaded. Its change tracker took SketchUp's persistent id
# notices, one per entity the load renumbers and the abort renumbers back: the
# sofa arrangement 18_1339 read in 108 s watched against 0.9 s unwatched, and
# the Gallery's Refresh of the whole library ran for about 2 hours. The model
# is as it was afterwards, so there is nothing for the tracker to record.
#
# FILES SAVED BY A NEWER SKETCHUP (SketchUp 2027 files read in 2026):
# DefinitionList#load refuses them unless allow_newer: true (it reads the
# header first: 8 ms). Reads pass allow_newer: true. Anything that saves the
# file back must not (what the older version cannot hold would be lost): it
# gets an error that names the version the file was saved with.
#
# =============================================================================

require 'fileutils'

module Na__ComponentEditorTools

# -----------------------------------------------------------------------------
# REGION | Error Raised For A Library File That Is Placed In The Open Model
# -----------------------------------------------------------------------------

    class Na__LibraryInUseError < StandardError

        def initialize(message_text, definition_name, instance_count)
            super(message_text)
            @na_definition_name = definition_name.to_s
            @na_instance_count  = instance_count.to_i
        end

        def na_definition_name
            @na_definition_name
        end

        def na_instance_count
            @na_instance_count
        end

    end

# endregion -------------------------------------------------------------------

    module Na__LibrarySafeLoad

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        # SketchUp's unique-name suffix, e.g. "Chair#1".
        NA_MANGLED_NAME = /#\d+\z/.freeze

        # DefinitionList#load's refusal of a file saved by a newer SketchUp:
        # "Model is of a newer model version that can be opened, but some
        # information might be lost. Use `allow_newer: true` option to load the file."
        NA_NEWER_VERSION = /newer model version/i.freeze unless defined?(NA_NEWER_VERSION)

        # The version a .skp was saved with, from its header, e.g. "{27.0.267}".
        NA_FILE_VERSION = /\{(\d+\.\d+\.\d+)\}/.freeze unless defined?(NA_FILE_VERSION)

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # Loads file_path inside an operation that is always aborted, yields
        # (definition, load_info) and returns the block's value.
        # load_info: in_use (the file was already loaded in the model), instances,
        # loaded_name, name_changed_on_load (SketchUp added a "#n" suffix),
        # newer_version (saved by a newer SketchUp, read with allow_newer).
        # allow_in_use: false refuses a file whose component is placed in the
        # open model, because edits would be written from the model's copy.
        # allow_newer: true reads a file saved by a newer SketchUp. Only for
        # reads: a file saved back from here would lose what this version
        # cannot hold, so without it such a file raises with its version.
        def self.Na__ComponentEditorTools__WithTemporaryDefinition(file_path, purpose_text, allow_in_use: true, allow_newer: false)
            model = Sketchup.active_model
            raise 'SketchUp has no active model.' unless model

            clean_path = file_path.to_s
            raise "File not found: #{clean_path}" unless File.file?(clean_path)

            existing = self.Na__ComponentEditorTools__LoadedDefinitionFor(model, clean_path)
            if existing && !allow_in_use
                raise Na__LibraryInUseError.new(
                    "#{File.basename(clean_path)} is loaded in the open model as '#{existing.name}' " \
                    "(#{existing.count_instances} placed). Library edits would be written from that copy.",
                    existing.name, existing.count_instances
                )
            end

            self.Na__ComponentEditorTools__UnseenByTracker do
                model.start_operation("Na Library - #{purpose_text}", true)
                begin
                    definition, newer = self.na_load(model, clean_path, allow_newer)
                    raise "Could not load a component definition from: #{clean_path}" unless definition

                    loaded_name = definition.name.to_s
                    load_info = {
                        in_use:               !existing.nil?,
                        instances:            existing ? existing.count_instances : 0,
                        loaded_name:          loaded_name,
                        name_changed_on_load: !(loaded_name =~ NA_MANGLED_NAME).nil?,
                        newer_version:        newer
                    }
                    yield(definition, load_info)
                ensure
                    model.abort_operation
                end
            end
        end

        # Runs the block inside the Agent Outliner's quiet load when it is loaded
        # (see UNSEEN BY THE AGENT OUTLINER above), otherwise just runs it.
        def self.Na__ComponentEditorTools__UnseenByTracker(&block)
            tracker = defined?(::Na__AgentOutliner::Na__Observers) ? ::Na__AgentOutliner::Na__Observers : nil
            return yield unless tracker && tracker.respond_to?(:Na__Observers__Quietly)

            tracker.Na__Observers__Quietly(&block)
        end

        # For a load whose component stays in the model (Insert At Cursor, Insert
        # At Axis): wrap only the DefinitionList#load call. The Agent Outliner
        # records the operation as usual, but SketchUp sends no id notice for each
        # entity the load brings in (they are all new): placing the sofa
        # arrangement 18_1339 took 20.7 s with them and 0.98 s without, the same
        # 42 objects recorded (17-Nov-2026). Without the Agent Outliner it just runs.
        def self.Na__ComponentEditorTools__WithoutIdNotices(&block)
            tracker = defined?(::Na__AgentOutliner::Na__Observers) ? ::Na__AgentOutliner::Na__Observers : nil
            return yield unless tracker && tracker.respond_to?(:Na__Observers__WithoutIdNotices)

            tracker.Na__Observers__WithoutIdNotices(&block)
        end

        # The SketchUp version a .skp was saved with ("27.0.267"), read from its
        # header, or nil when the header cannot be read.
        def self.Na__ComponentEditorTools__FileVersion(file_path)
            head = File.binread(file_path.to_s, 128)
            return nil unless head

            text  = head.force_encoding(Encoding::UTF_16LE).encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: '')
            match = text.match(NA_FILE_VERSION)
            match ? match[1] : nil
        rescue StandardError
            nil
        end

        # The definition already loaded from this file, or nil.
        def self.Na__ComponentEditorTools__LoadedDefinitionFor(model, file_path)
            target = self.Na__ComponentEditorTools__PathKey(file_path)
            return nil if target.empty?

            model.definitions.find do |definition|
                next false if definition.group? || definition.image?

                self.Na__ComponentEditorTools__PathKey(definition.path) == target
            end
        end

        # Names a definition and proves the name held. Inside an aborted operation
        # (move_clash_aside: true) a visible definition that already owns the name
        # is renamed out of the way first; the abort gives it its name back.
        def self.Na__ComponentEditorTools__ApplyName(model, definition, intended_name, move_clash_aside: false)
            wanted = intended_name.to_s
            raise 'A definition name cannot be empty.' if wanted.strip.empty?
            return definition.name if definition.name == wanted

            clash = model.definitions.find { |other| !other.equal?(definition) && other.name == wanted }
            if clash
                raise "The open model already has a definition named '#{wanted}'." unless move_clash_aside

                clash.name = model.definitions.unique_name("Na__TempAside__#{wanted}")
            end

            definition.name = wanted
            return definition.name if definition.name == wanted

            raise "SketchUp would not use the name '#{wanted}' (it gave '#{definition.name}'): the name is still " \
                  'reserved in this SketchUp session. Run this again from a new SketchUp window (File > New).'
        end

        # Case-insensitive, slash-normalised path used to compare file paths on Windows.
        def self.Na__ComponentEditorTools__PathKey(path_text)
            clean = path_text.to_s.strip
            return '' if clean.empty?

            File.expand_path(clean).tr('\\', '/').downcase
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Helpers
# -----------------------------------------------------------------------------

        # [definition, newer_version]. A file saved by a newer SketchUp is read
        # with allow_newer when allowed, otherwise refused with its version.
        def self.na_load(model, path, allow_newer)
            [model.definitions.load(path), false]
        rescue RuntimeError => error
            raise unless error.message.to_s =~ NA_NEWER_VERSION
            raise self.na_newer_message(path) unless allow_newer

            [model.definitions.load(path, allow_newer: true), true]
        end

        def self.na_newer_message(path)
            version = self.Na__ComponentEditorTools__FileVersion(path)
            saved   = version ? "SketchUp 20#{version.to_i} (#{version})" : 'a newer SketchUp'
            "#{File.basename(path)} was saved by #{saved}. This SketchUp #{Sketchup.version.to_i + 2000} can read it " \
            'but not save it back without losing what it cannot hold: change it in that version.'
        end

# endregion -------------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
