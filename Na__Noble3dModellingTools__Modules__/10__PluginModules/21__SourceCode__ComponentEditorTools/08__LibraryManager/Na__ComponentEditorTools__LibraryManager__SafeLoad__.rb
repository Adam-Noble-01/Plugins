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

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # Loads file_path inside an operation that is always aborted, yields
        # (definition, load_info) and returns the block's value.
        # load_info: in_use (the file was already loaded in the model), instances,
        # loaded_name, name_changed_on_load (SketchUp added a "#n" suffix).
        # allow_in_use: false refuses a file whose component is placed in the
        # open model, because edits would be written from the model's copy.
        def self.Na__ComponentEditorTools__WithTemporaryDefinition(file_path, purpose_text, allow_in_use: true)
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

            model.start_operation("Na Library - #{purpose_text}", true)
            begin
                definition = model.definitions.load(clean_path)
                raise "Could not load a component definition from: #{clean_path}" unless definition

                loaded_name = definition.name.to_s
                load_info = {
                    in_use:               !existing.nil?,
                    instances:            existing ? existing.count_instances : 0,
                    loaded_name:          loaded_name,
                    name_changed_on_load: !(loaded_name =~ NA_MANGLED_NAME).nil?
                }
                yield(definition, load_info)
            ensure
                model.abort_operation
            end
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

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
