# =============================================================================
# NA COMPONENT EDITOR TOOLS - MCP OPERATIONS | MAIN
# =============================================================================
#
# FILE       : Na__ComponentEditorTools__McpOperations__Main__.rb
# NAMESPACE  : Na__ComponentEditorTools::Na__McpOperations
# PURPOSE    : The entry point the Na SketchUp MCP bridge calls so an agent can
#              use the component library the way Adam does in the Gallery and
#              Index tabs: browse it, check names, take the next free code,
#              save, rename, move and update assets, and apply or revert
#              whole tidy plans.
# CREATED    : 2026
#
# THE SEAM (Na SketchUp MCP -> this module):
#   Na__ComponentEditorTools::Na__McpOperations.Na__ComponentEditorTools__McpRead(action, params)
#   Na__ComponentEditorTools::Na__McpOperations.Na__ComponentEditorTools__McpEdit(action, params)
# params are the MCP tool's JSON arguments (string keys); for save the bridge
# adds 'definition_object', the definition it resolved from the open model.
# Each call returns a Hash of plain JSON data, or raises
# Na__McpOperationsError(code, message, hint, details), which the bridge turns
# into its own refusal. Codes follow the bridge's list: invalid_params,
# not_found, wrong_type, file_error, operation_failed, unsupported.
#
# FILES IN THIS FOLDER:
#   ...__Main__.rb        this seam and the error type
#   ...__Convention__.rb  names and codes (07__UserData/...LibraryConvention__.json)
#   ...__Catalogue__.rb   overview, browse, get, next_code, check_name, audit
#   ...__Plan__.rb        checked, journaled, revertible changes on disk
#   ...__AssetOps__.rb    save, rename, move, update, archive, create_folder, refresh
#   ...__Archive__.rb     date-stamped zips into 00__Archive, proved before use
#
# SAFETY:
# Library files are opened through Na__LibrarySafeLoad (an operation that is
# always aborted), so reading or editing the library never changes the open
# model; only save with rename_in_model does, as one undo step. Every change
# on disk is journaled with byte copies of the files it rewrites, and nothing
# is ever deleted. Never call these from inside another open operation.
#
# =============================================================================

module Na__ComponentEditorTools

# -----------------------------------------------------------------------------
# REGION | Error Type
# -----------------------------------------------------------------------------

    class Na__McpOperationsError < StandardError

        def initialize(code, message_text, hint_text = nil, details = nil)
            super(message_text)
            @na_code    = code.to_s
            @na_hint    = hint_text
            @na_details = details
        end

        def na_code
            @na_code
        end

        def na_hint
            @na_hint
        end

        def na_details
            @na_details
        end

    end

# endregion -------------------------------------------------------------------

    module Na__McpOperations

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_MCP_OPERATIONS_VERSION = '1.0.0'.freeze
        NA_READ_ACTIONS = %w[overview browse get next_code check_name audit].freeze
        NA_EDIT_ACTIONS = %w[save rename move update archive create_folder apply_plan revert refresh].freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | The Seam
# -----------------------------------------------------------------------------

        # asset_library (read-only).
        def self.Na__ComponentEditorTools__McpRead(action, params)
            arguments = self.Na__ComponentEditorTools__Arguments(params)
            result = case action.to_s
                     when 'overview'   then Na__McpCatalogue.Na__ComponentEditorTools__Overview(arguments)
                     when 'browse'     then Na__McpCatalogue.Na__ComponentEditorTools__Browse(arguments)
                     when 'get'        then Na__McpCatalogue.Na__ComponentEditorTools__Get(arguments)
                     when 'next_code'  then Na__McpCatalogue.Na__ComponentEditorTools__NextCode(arguments)
                     when 'check_name' then Na__McpCatalogue.Na__ComponentEditorTools__CheckName(arguments)
                     when 'audit'      then Na__McpCatalogue.Na__ComponentEditorTools__Audit(arguments)
                     else
                         raise Na__McpOperationsError.new('invalid_params', "Unknown asset_library action '#{action}'.",
                                                          "Use one of: #{NA_READ_ACTIONS.join(', ')}.")
                     end
            self.Na__ComponentEditorTools__Stamped(result)
        rescue Na__LibraryInUseError => error
            raise Na__McpOperationsError.new('context_error', error.message, 'Work from a model that does not use this component.')
        end

        # asset_library_edit (changes library files; never the model unless asked).
        def self.Na__ComponentEditorTools__McpEdit(action, params)
            arguments = self.Na__ComponentEditorTools__Arguments(params)
            result = case action.to_s
                     when 'save'          then Na__McpAssetOps.Na__ComponentEditorTools__Save(arguments)
                     when 'rename'        then Na__McpAssetOps.Na__ComponentEditorTools__Rename(arguments)
                     when 'move'          then Na__McpAssetOps.Na__ComponentEditorTools__Move(arguments)
                     when 'update'        then Na__McpAssetOps.Na__ComponentEditorTools__Update(arguments)
                     when 'archive'       then Na__McpAssetOps.Na__ComponentEditorTools__Archive(arguments)
                     when 'create_folder' then Na__McpAssetOps.Na__ComponentEditorTools__CreateFolder(arguments)
                     when 'apply_plan'    then Na__McpLibraryPlan.Na__ComponentEditorTools__ApplyPlan(arguments)
                     when 'revert'        then Na__McpLibraryPlan.Na__ComponentEditorTools__Revert(arguments)
                     when 'refresh'       then Na__McpAssetOps.Na__ComponentEditorTools__Refresh(arguments)
                     else
                         raise Na__McpOperationsError.new('invalid_params', "Unknown asset_library_edit action '#{action}'.",
                                                          "Use one of: #{NA_EDIT_ACTIONS.join(', ')}.")
                     end
            self.Na__ComponentEditorTools__Stamped(result)
        rescue Na__LibraryInUseError => error
            raise Na__McpOperationsError.new('context_error', error.message,
                                             'Pass allow_in_use: true to write from the placed copy, or work from a model that does not use it.')
        rescue SystemCallError, IOError => error
            raise Na__McpOperationsError.new('file_error', "#{error.class}: #{error.message}",
                                             'A file may be open in another SketchUp window or read-only. The journal shows what finished.')
        end

        def self.Na__ComponentEditorTools__McpInfo
            {
                'version'      => NA_MCP_OPERATIONS_VERSION,
                'read_actions' => NA_READ_ACTIONS,
                'edit_actions' => NA_EDIT_ACTIONS,
                'library_root' => Na__UserConfig.Na__ComponentEditorTools__LibraryPath
            }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Helpers
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__Arguments(params)
            params.is_a?(Hash) ? params.each_with_object({}) { |(key, value), copy| copy[key.to_s] = value } : {}
        end

        def self.Na__ComponentEditorTools__Stamped(result)
            result.is_a?(Hash) ? result.merge('library_tools' => NA_MCP_OPERATIONS_VERSION) : result
        end

# endregion -------------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
