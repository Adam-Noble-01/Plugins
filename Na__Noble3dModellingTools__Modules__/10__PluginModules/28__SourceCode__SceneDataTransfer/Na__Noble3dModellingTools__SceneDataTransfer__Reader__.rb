# =============================================================================
# NA NOBLE3D MODELLING TOOLS - SCENE DATA TRANSFER - EXTERNAL MODEL READER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__SceneDataTransfer__Reader__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__SceneDataTransfer__Reader
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Pull a serialised scene payload out of a .skp file on disk
#              without opening that file as the active model.
# CREATED    : 2026
#
# THIS IS THE LOAD-BEARING FILE OF THE WHOLE TOOL.
#
# WHY THERE IS NO SIMPLER ROUTE:
# There is no Ruby API that reads a model-level attribute dictionary out of an
# unopened .skp. The only Ruby call that reads anything at all from a file on
# disk is Sketchup::Skp.read_guid, which returns a GUID and nothing else.
# Reading arbitrary data properly would require a compiled C extension against
# SUModelCreateFromFile. Sketchup.open_file is not an option either: on Windows
# there is one document window, so opening the source model would CLOSE the
# model the user is working in.
#
# WHAT THIS FILE DOES INSTEAD:
# Sketchup::DefinitionList#load pulls a .skp into the current model as a single
# ComponentDefinition whose entities are the source model's root entities. The
# payload was deliberately written onto a carrier ComponentDefinition with a
# placed instance, because definition-level dictionaries DO survive that trip
# even though model-level ones do not. So the probe is:
#
#   copy to temp -> definitions.load -> find carrier -> read -> unwind
#
# THE FOUR TRAPS THIS CODE DEFENDS AGAINST:
#
#   1. PATH CACHING. DefinitionList#load associates a definition with the path
#      it came from and refuses to reload an unmodified path, silently handing
#      back a STALE definition on the second read. Every probe therefore copies
#      the source file to a uniquely named file in Sketchup.temp_dir and loads
#      from there.
#
#   2. MODEL POLLUTION. Loading the source model drags in all of its nested
#      definitions and materials. The probe runs inside an operation that is
#      ALWAYS aborted, never committed, and the definition count is compared
#      before and after so any leak is reported rather than hidden.
#
#   3. THE UNDO CORRUPTION BUG. Removing a definition inside an operation and
#      then calling Sketchup.undo is a documented crash. This code aborts the
#      operation and never calls undo.
#
#   4. allow_newer. Its documented default of true is wrong - it really
#      defaults to false, so a source file saved in a newer SketchUp would
#      raise. The keyword is passed explicitly, with a fallback for releases
#      that predate it.
#
# =============================================================================

require 'fileutils'

module Na__Noble3dModellingTools
    module Na__SceneDataTransfer__Reader

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_PROBE_OPERATION_NAME = 'NA Read External Scene Data'.freeze
        NA_TEMP_PREFIX          = 'Na__SceneDataTransfer__Probe__'.freeze

        NA_ROUTE_LOCAL_MODEL    = 'local_model'.freeze                              # <-- Source file is the model already open
        NA_ROUTE_CARRIER        = 'embedded_carrier'.freeze                         # <-- Read through definitions.load

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Read API
# -----------------------------------------------------------------------------

        # FUNCTION | Read the Scene Payload Out of an External .skp File
        # ------------------------------------------------------------
        # Returns { success, message, route, payload, header, diagnostics }
        def self.Na__SceneDataTransfer__ReadExternalModel(target_model, source_path)
            return na_result(false, 'No active SketchUp model.') unless target_model

            clean_path = source_path.to_s.strip
            validation = na_validate_source_path(clean_path)
            return validation unless validation['success']

            if na_is_same_file(clean_path, target_model.path.to_s)
                return na_read_from_open_model(target_model)                        # <-- No probe needed, it is already open
            end

            na_probe_external_file(target_model, clean_path)
        rescue => error
            na_result(false, "Could not read the source model: #{error.class}: #{error.message}")
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Probe Implementation
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Load, Read and Unwind an External Model
        # ------------------------------------------------------------
        def self.na_probe_external_file(target_model, source_path)
            temp_path = na_copy_to_temp(source_path)
            return na_result(false, 'Could not stage a temporary copy of the source model.') unless temp_path

            definitions_before = target_model.definitions.count
            loaded_definition  = nil
            payload            = nil
            payload_entity     = nil
            probe_error        = nil

            target_model.start_operation(NA_PROBE_OPERATION_NAME, true)
            begin
                loaded_definition = na_load_definition(target_model, temp_path)
                raise 'SketchUp could not load the source model as a component.' unless loaded_definition

                payload_entity = Na__SceneDataTransfer__Carrier.Na__SceneDataTransfer__FindPayloadEntity(loaded_definition)
                payload        = Na__SceneDataTransfer__Codec.Na__SceneDataTransfer__ReadPayload(payload_entity) if payload_entity
            rescue => error
                probe_error = error
            ensure
                na_discard_definition(target_model, loaded_definition)
                na_abort_quietly(target_model)
                na_delete_temp(temp_path)
            end

            definitions_after = target_model.definitions.count
            diagnostics       = na_diagnostics(definitions_before, definitions_after, source_path)

            return na_result(false, "Could not read the source model: #{probe_error.message}", 'diagnostics' => diagnostics) if probe_error
            return na_no_payload_result(source_path, diagnostics) if payload.nil?

            na_result(
                true,
                na_success_message(payload, source_path),
                'route'       => NA_ROUTE_CARRIER,
                'payload'     => payload,
                'header'      => na_header_from_payload(payload),
                'diagnostics' => diagnostics
            )
        end
        private_class_method :na_probe_external_file
        # ------------------------------------------------------------

        # HELPER FUNCTION | Call DefinitionList#load With the Right Keyword Support
        # ------------------------------------------------------------
        def self.na_load_definition(target_model, temp_path)
            target_model.definitions.load(temp_path, allow_newer: true)
        rescue ArgumentError
            target_model.definitions.load(temp_path)                                # <-- Releases predating the allow_newer keyword
        end
        private_class_method :na_load_definition
        # ------------------------------------------------------------

        # HELPER FUNCTION | Read the Payload Straight Off the Already-Open Model
        # ------------------------------------------------------------
        def self.na_read_from_open_model(target_model)
            payload = Na__SceneDataTransfer__Codec.Na__SceneDataTransfer__ReadPayload(target_model)
            return na_result(false, 'The model you picked is the one already open, and it has no captured scene data.') unless payload

            na_result(
                true,
                'Read the captured scene data straight from the model that is already open.',
                'route'       => NA_ROUTE_LOCAL_MODEL,
                'payload'     => payload,
                'header'      => na_header_from_payload(payload),
                'diagnostics' => { 'definitions_leaked' => 0, 'probe_used' => false }
            )
        end
        private_class_method :na_read_from_open_model
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Cleanup Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Drop the Loaded Definition Before the Abort
        # ------------------------------------------------------------
        # Belt and braces. abort_operation is the documented way to unwind
        # temporary model changes, but it is not documented as unwinding
        # DefinitionList#load specifically, so the definition is removed first.
        # Never commit and then undo - that sequence is a documented crash.
        def self.na_discard_definition(target_model, loaded_definition)
            return unless loaded_definition

            return unless loaded_definition.valid?

            if target_model.definitions.respond_to?(:remove)
                target_model.definitions.remove(loaded_definition)
            else
                loaded_definition.entities.clear!                                   # <-- SketchUp auto-purges an emptied definition
            end
        rescue => error
            puts "[Na__SceneDataTransfer] Probe definition cleanup warning: #{error.class}: #{error.message}"
        end
        private_class_method :na_discard_definition
        # ------------------------------------------------------------

        # HELPER FUNCTION | Abort the Probe Operation Without Raising
        # ------------------------------------------------------------
        def self.na_abort_quietly(target_model)
            target_model.abort_operation
        rescue => error
            puts "[Na__SceneDataTransfer] Probe abort warning: #{error.class}: #{error.message}"
        end
        private_class_method :na_abort_quietly
        # ------------------------------------------------------------

        # HELPER FUNCTION | Compare the Definition Count Either Side of the Probe
        # ------------------------------------------------------------
        # If abort_operation fully unwinds the load, the delta is zero. Any other
        # number is surfaced rather than swallowed, because a silent leak would
        # grow the user's model every time they read a source file.
        def self.na_diagnostics(definitions_before, definitions_after, source_path)
            leaked = definitions_after - definitions_before

            if leaked > 0
                puts "[Na__SceneDataTransfer] WARNING: the probe left #{leaked} definition(s) behind after abort_operation."
            end

            {
                'definitions_before' => definitions_before,
                'definitions_after'  => definitions_after,
                'definitions_leaked' => leaked,
                'probe_used'         => true,
                'source_size_bytes'  => (File.size(source_path) rescue 0)
            }
        end
        private_class_method :na_diagnostics
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Temporary File Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Stage a Uniquely Named Copy in the SketchUp Temp Folder
        # ------------------------------------------------------------
        # The unique name is the whole point. DefinitionList#load caches against
        # the source path, so reusing a filename returns the previous, stale
        # definition instead of re-reading the file.
        def self.na_copy_to_temp(source_path)
            temp_root = Sketchup.temp_dir.to_s
            return nil if temp_root.empty?

            unique_stamp = "#{Time.now.to_i}_#{rand(100_000)}_#{object_id}"
            temp_path    = File.join(temp_root, "#{NA_TEMP_PREFIX}#{unique_stamp}.skp")

            FileUtils.cp(source_path, temp_path)
            File.exist?(temp_path) ? temp_path : nil
        rescue => error
            puts "[Na__SceneDataTransfer] Temp copy error: #{error.class}: #{error.message}"
            nil
        end
        private_class_method :na_copy_to_temp
        # ------------------------------------------------------------

        # HELPER FUNCTION | Delete the Staged Copy
        # ------------------------------------------------------------
        def self.na_delete_temp(temp_path)
            return unless temp_path && File.exist?(temp_path)

            File.delete(temp_path)
        rescue => error
            puts "[Na__SceneDataTransfer] Temp cleanup warning: #{error.class}: #{error.message}"
        end
        private_class_method :na_delete_temp
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Validation and Messaging
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Check the Chosen Path Before Doing Any Work
        # ------------------------------------------------------------
        def self.na_validate_source_path(source_path)
            return na_result(false, 'Choose a source SketchUp model first.')            if source_path.empty?
            return na_result(false, "That file no longer exists:\n#{source_path}")      unless File.exist?(source_path)
            return na_result(false, 'The source must be a .skp SketchUp model file.')   unless File.extname(source_path).downcase == '.skp'
            return na_result(false, 'The source file is empty.')                        if File.size(source_path).zero?

            na_result(true, 'Source path is valid.')
        rescue => error
            na_result(false, "Could not inspect that file: #{error.message}")
        end
        private_class_method :na_validate_source_path
        # ------------------------------------------------------------

        # HELPER FUNCTION | Compare Two Paths as the Same File on Disk
        # ------------------------------------------------------------
        def self.na_is_same_file(first_path, second_path)
            return false if first_path.to_s.empty? || second_path.to_s.empty?

            File.expand_path(first_path).casecmp(File.expand_path(second_path)).zero?
        rescue
            false
        end
        private_class_method :na_is_same_file
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build the Message for a File With No Captured Data
        # ------------------------------------------------------------
        def self.na_no_payload_result(source_path, diagnostics)
            na_result(
                false,
                "#{File.basename(source_path)} has no captured scene data.\n\n" \
                'Open that model, run Scene Data Transfer, press Capture Scene Data, then save it.',
                'diagnostics' => diagnostics
            )
        end
        private_class_method :na_no_payload_result
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build the Success Message
        # ------------------------------------------------------------
        def self.na_success_message(payload, source_path)
            scene_count = Array(payload['scenes']).length
            domains     = Array(payload['domains_captured']).join(', ')

            "Read #{scene_count} #{scene_count == 1 ? 'scene' : 'scenes'} from " \
            "#{File.basename(source_path)} (#{domains})."
        end
        private_class_method :na_success_message
        # ------------------------------------------------------------

        # HELPER FUNCTION | Derive a Header Summary From a Decoded Payload
        # ------------------------------------------------------------
        def self.na_header_from_payload(payload)
            source = payload['source'] || {}

            {
                'schema_version'    => payload['schema_version'].to_s,
                'captured_at'       => payload['captured_at'].to_s,
                'captured_by'       => payload['captured_by'].to_s,
                'source_model_name' => source['name'].to_s,
                'source_model_path' => source['path'].to_s,
                'sketchup_version'  => source['sketchup_version'].to_s,
                'source_viewport'   => source['viewport'] || {},
                'scene_count'       => Array(payload['scenes']).length,
                'domains_captured'  => Array(payload['domains_captured'])
            }
        rescue
            {}
        end
        private_class_method :na_header_from_payload
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build the Standard Result Hash
        # ------------------------------------------------------------
        def self.na_result(success_flag, message_text, extra = {})
            { 'success' => !!success_flag, 'message' => message_text.to_s }.merge(extra)
        end
        private_class_method :na_result
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__SceneDataTransfer__Reader
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
