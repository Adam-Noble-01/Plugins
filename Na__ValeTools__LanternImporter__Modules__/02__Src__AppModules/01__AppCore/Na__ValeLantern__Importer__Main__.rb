# =============================================================================
# VALE LANTERN IMPORTER - APPLICATION CORE
# =============================================================================
#
# FILE       : Na__ValeLantern__Importer__Main__.rb
# NAMESPACE  : Na__ValeLantern::Na__Importer
# MODULE     : Na__Main
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : The importer's entry point. Requires the module chain in order,
#              opens the file picker, and hands the payload to the composer.
#
# DESCRIPTION:
# - Three steps and nothing else: ask for a file, read it, build it. Everything
#   between those is somebody else's module.
# - Every step reports through the Ruby console. An import that does nothing must
#   never do it silently.
#
# -----------------------------------------------------------------------------
#
# HOW IT IS RUN:
#
#   From the Ruby console, one line:
#       Na__ValeLantern.na_import
#
#   Or from Extensions > Vale Lantern Importer > Import Lantern Build File.
#
#   Both reach the same routine. There is no dialog and no options panel,
#   because every decision the import makes is already carried in the payload -
#   which is the point of exporting a build recipe rather than a configuration.
#
# -----------------------------------------------------------------------------
#
# LOAD ORDER MATTERS, AND IS ENFORCED HERE:
#
# Each module resolves its dependencies into constants at load time - a pattern
# taken from Element Assembly Studio Pro, where it makes every call site read as
# a plain module name rather than a fully qualified path. The cost of that is
# that a module loaded before its dependency raises a NameError immediately, so
# the order below is a contract rather than a convenience:
#
#     Units, DebugTools     no dependencies
#     DataLibBridge         DebugTools  (plus the optional Na__DataLib install)
#     TagManager            DebugTools, DataLibBridge
#     MaterialManager       DebugTools
#     PayloadReader         DebugTools
#     PrismBuilder          DebugTools, Units, TagManager, MaterialManager
#     MeshBuilder           the same four
#     LineBuilder           DebugTools, Units, TagManager, DataLibBridge
#     ModelComposer         everything above
#
# NAMING CONVENTION:
# - Importer namespace Na__Importer / na_ prefixes.
#
# =============================================================================

require 'sketchup.rb'

module Na__ValeLantern
    module Na__Importer
        module Na__Main

# -----------------------------------------------------------------------------
# REGION | Module Chain
# -----------------------------------------------------------------------------

            NA_MODULE_ROOT = File.expand_path(File.join(File.dirname(__FILE__), '..')).freeze

            NA_MODULE_CHAIN = [
                '03__AppUtils/Na__ValeLantern__Importer__Units__',
                '03__AppUtils/Na__ValeLantern__Importer__DebugTools__',
                '02__AppData/Na__ValeLantern__Importer__DataLibBridge__',
                '03__AppUtils/Na__ValeLantern__Importer__TagManager__',
                '03__AppUtils/Na__ValeLantern__Importer__MaterialManager__',
                '02__AppData/Na__ValeLantern__Importer__PayloadReader__',
                '04__GeometryBuilders/Na__ValeLantern__Importer__PrismBuilder__',
                '04__GeometryBuilders/Na__ValeLantern__Importer__MeshBuilder__',
                '04__GeometryBuilders/Na__ValeLantern__Importer__LineBuilder__',
                '05__Assembly/Na__ValeLantern__Importer__ModelComposer__'
            ].freeze

            # FUNCTION | Load every module in dependency order
            # ------------------------------------------------------------
            # `load` rather than `require` so re-running the loader picks up an
            # edited module without restarting SketchUp, which is the whole
            # reason the console paste is a one line loader rather than a paste
            # of the source itself.
            #
            # Warnings are silenced across the chain and restored afterwards.
            # Every module resolves its collaborators into module level constants
            # at load time, so a reload re-assigns each of them and Ruby says so
            # about twenty times. Those warnings are correct and completely
            # uninteresting, and they would bury the import report that is the
            # only reason anyone is reading this console.
            def self.na_load_modules
                original_verbose = $VERBOSE
                $VERBOSE = nil

                NA_MODULE_CHAIN.each do |relative_path|
                    absolute = File.join(NA_MODULE_ROOT, "#{relative_path}.rb")
                    unless File.exist?(absolute)
                        puts "[Vale Lantern] ERROR: module missing - #{absolute}"
                        return false
                    end
                    load absolute
                end

                # A reload is how an edited local DataLib copy is picked up, so
                # the standard is forgotten here rather than surviving as a stale
                # lookup from before the edit.
                if defined?(Na__ValeLantern::Na__Importer::Na__DataLibBridge)
                    Na__ValeLantern::Na__Importer::Na__DataLibBridge.na_reset
                end

                true

            rescue Exception => e
                puts "[Vale Lantern] ERROR: module chain failed to load (#{e.class}): #{e.message}"
                puts e.backtrace.first(8).join("\n    ") if e.backtrace
                false

            ensure
                $VERBOSE = original_verbose
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Import Routine — Public API
# -----------------------------------------------------------------------------

            NA_PICKER_TITLE   = 'Select a Vale Lantern build file'.freeze
            NA_PICKER_FILTER  = 'JSON Files|*.json||'.freeze
            NA_SETTINGS_KEY   = 'Na__ValeLantern__Importer'.freeze
            NA_LAST_DIR_KEY   = 'LastImportDirectory'.freeze

            # FUNCTION | Run one import, from file picker to finished model
            # ------------------------------------------------------------
            # The three collaborators are resolved into LOCAL variables rather
            # than constants: Ruby forbids a constant assignment inside a method
            # body, and this file is loaded before the modules it names exist, so
            # a constant at module level would not work either.
            #
            # @param file_path [String, nil] Skip the picker by passing a path
            # @param choices [Hash] { :BuildModel, :BuildSettingOut }
            # @return [Boolean] true when a lantern was built
            def self.na_import(file_path = nil, choices = {})
                debug_tools    = Na__ValeLantern::Na__Importer::Na__DebugTools
                payload_reader = Na__ValeLantern::Na__Importer::Na__PayloadReader
                model_composer = Na__ValeLantern::Na__Importer::Na__ModelComposer

                unless Sketchup.active_model
                    puts '[Vale Lantern] ERROR: there is no open model to import into.'
                    return false
                end

                chosen = file_path || na_ask_for_file
                if chosen.nil?
                    debug_tools.na_info('Import cancelled.')
                    return false
                end

                na_remember_directory(chosen)

                payload = payload_reader.na_read_payload(chosen)
                return false if payload.nil?

                root = model_composer.na_compose(payload, choices)
                if root.nil?
                    debug_tools.na_error('Nothing was built. The model is unchanged.')
                    return false
                end

                na_frame_result(root)
                debug_tools.na_info("Import complete: #{root.name}")
                true
            end
            # ---------------------------------------------------------------

            # FUNCTION | Import the metal and the construction linework together
            # ------------------------------------------------------------
            # The setting out lands in its own assembly on its own dash styled
            # tags, so it can be switched off the moment it has been read without
            # disturbing anything else.
            def self.na_import_with_setout(file_path = nil)
                na_import(file_path, { :BuildModel => true, :BuildSettingOut => true })
            end
            # ---------------------------------------------------------------

            # FUNCTION | Import the construction linework alone
            # ------------------------------------------------------------
            # For checking a model that is already in front of you: bring in the
            # datums and derivation triangles on their own, drop them over the
            # existing lantern, and any disagreement is visible without measuring.
            def self.na_import_setout_only(file_path = nil)
                na_import(file_path, { :BuildModel => false, :BuildSettingOut => true })
            end
            # ---------------------------------------------------------------

            # FUNCTION | Run one import with per part console reporting
            # ------------------------------------------------------------
            # The routine to reach for when a part has come out wrong: it names
            # every prism as it is built, every coplanar merge and every face the
            # API refused, which is a lot of output and exactly what is wanted
            # when four hundred parts have produced one bad one.
            #
            # Verbosity is turned off again in an ensure block, so a raise part
            # way through cannot leave every later import shouting.
            def self.na_import_verbose(file_path = nil, choices = {})
                debug_tools = Na__ValeLantern::Na__Importer::Na__DebugTools
                debug_tools.na_set_verbose(true)
                begin
                    na_import(file_path, choices)
                ensure
                    debug_tools.na_set_verbose(false)
                end
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal — File Picker and Result Framing
# -----------------------------------------------------------------------------

            # HELPER FUNCTION | Open the OS file picker at the last used folder
            # ------------------------------------------------------------
            # UI.openpanel returns nil on cancel, and on some platforms has
            # historically returned the string 'Cancel' instead, so both are
            # treated as a cancellation.
            def self.na_ask_for_file
                start_dir = Sketchup.read_default(NA_SETTINGS_KEY, NA_LAST_DIR_KEY, nil)
                start_dir = nil unless start_dir && File.directory?(start_dir)

                chosen = UI.openpanel(NA_PICKER_TITLE, start_dir, NA_PICKER_FILTER)
                return nil if chosen.nil? || chosen.to_s.empty? || chosen == 'Cancel'
                return nil unless File.exist?(chosen)

                chosen
            end
            private_class_method :na_ask_for_file

            # HELPER FUNCTION | Remember the folder the file came from
            # ------------------------------------------------------------
            # A build file is downloaded to the same folder every time, so
            # reopening the picker there saves the same four clicks on every
            # import of the working day.
            def self.na_remember_directory(file_path)
                Sketchup.write_default(NA_SETTINGS_KEY, NA_LAST_DIR_KEY, File.dirname(file_path))
            rescue StandardError
                nil                                                                                 # <-- A preference that will not save is not worth a message
            end
            private_class_method :na_remember_directory

            # HELPER FUNCTION | Select the new lantern and zoom to it
            # ------------------------------------------------------------
            # The lantern lands at the model origin, which on a model that
            # already holds a building can be a long way off screen. Selecting it
            # also means the first thing the user does - move it into place - is
            # one drag away.
            def self.na_frame_result(root_group)
                model = Sketchup.active_model
                return unless model && root_group && root_group.valid?

                model.selection.clear
                model.selection.add(root_group)
                model.active_view.zoom(root_group)
            rescue StandardError => e
                Na__ValeLantern::Na__Importer::Na__DebugTools.na_detail("Could not frame the result: #{e.message}")
            end
            private_class_method :na_frame_result

# endregion -------------------------------------------------------------------

        end
    end
end

# -----------------------------------------------------------------------------
# REGION | Namespace Convenience Entry Points
# -----------------------------------------------------------------------------

module Na__ValeLantern

    # FUNCTION | The short form typed into the Ruby console
    # ------------------------------------------------------------
    # Na__ValeLantern.na_import is what goes in the documentation and on the
    # menu item, because the fully qualified path is four modules deep and
    # nobody should have to type it.
    #
    # Builds the metal alone. That is what an import means to anybody who has
    # not asked for anything else, and the construction linework is a deliberate
    # second choice rather than something that arrives whether you wanted it or
    # not.
    def self.na_import(file_path = nil, choices = {})
        Na__ValeLantern::Na__Importer::Na__Main.na_import(file_path, choices)
    end

    # FUNCTION | Metal and construction linework together
    # ------------------------------------------------------------
    def self.na_import_with_setout(file_path = nil)
        Na__ValeLantern::Na__Importer::Na__Main.na_import_with_setout(file_path)
    end

    # FUNCTION | Construction linework alone, to check an existing model
    # ------------------------------------------------------------
    def self.na_import_setout_only(file_path = nil)
        Na__ValeLantern::Na__Importer::Na__Main.na_import_setout_only(file_path)
    end

    # FUNCTION | The same import with per part console reporting
    # ------------------------------------------------------------
    def self.na_import_verbose(file_path = nil, choices = {})
        Na__ValeLantern::Na__Importer::Na__Main.na_import_verbose(file_path, choices)
    end

end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Chain Load on Require
# -----------------------------------------------------------------------------

Na__ValeLantern::Na__Importer::Na__Main.na_load_modules

# endregion -------------------------------------------------------------------
