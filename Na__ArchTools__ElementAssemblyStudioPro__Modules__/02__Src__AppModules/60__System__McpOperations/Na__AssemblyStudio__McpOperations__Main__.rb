# frozen_string_literal: true

# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - MCP OPERATIONS (AGENT SEAM)
# =============================================================================
#
# FILE       : Na__AssemblyStudio__McpOperations__Main__.rb
# NAMESPACE  : Na__AssemblyStudio
# MODULE     : Na__McpOperations
# AUTHOR     : Noble Architecture
# CREATED    : 09-Nov-2026 (V2.5.3)
# UPDATED    : 11-Nov-2026 (V2.6.0) Every product, every setting, openings
# PURPOSE    : What an agent may do with Element Assembly Studio Pro through
#              Adam's Na SketchUp MCP plugin (tools entity_studio and
#              entity_studio_edit). The MCP handlers are thin: they resolve
#              ids, points and walls, then call the two entry points below.
#
# ENTRY POINTS:
# - Na__McpOperations.Na__AssemblyStudio__McpRead(action, params)
#     status, parameters, elements, inspect, openings, list_presets,
#     get_preset, assets, list_handles
# - Na__McpOperations.Na__AssemblyStudio__McpEdit(action, params)
#     build, update, rename, export_dxf, save_preset, update_preset,
#     archive_preset, restore_preset, refresh_preview, open_dialog, reload
# - Refusals raise Na__McpOperationsError (code, message, hint, details); the
#   MCP handler turns them into its own error with the fix named.
#
# THE FILES OF THIS SEAM (one module, split by subject):
#   Main        entry points, status, presets reading, dialog, shared helpers
#   Catalogue   products, starting values, the parameter catalogue, value checks
#   Validation  the dialog's own build checks (twin of Viewport__Validation.js)
#   Openings    every opening in a wall, as the opening tools would measure it
#   Elements    elements, inspect, openings, build, update, rename
#   Presets     save / update / archive / restore presets, DXF, asset lists
#
# WHAT IT REUSES (no second copy of any rule):
# - Builds and updates run the dialog's own pipelines (V2.6.0): WindowSystem
#   DialogCallbacks na_pipeline_*, InteriorDoorSystem DialogRouter
#   na_pipeline_*_door, Cabinetry DialogRouter na_pipeline_*. One undo step
#   each, with the dialog's own names; the dialog's handlers call the same.
# - Settings: the generated parameter catalogue (02__AppData), read from the
#   dialog's own control files. Out-of-range values are refused, never
#   clamped.
# - Presets: the Presets Library Store (codes, file names, .bak, archive).
# - Previews: the dialog's own SvgCapture through its na_presetsUpdateConfig
#   callback (needs the dialog open; lands a moment after the call).
#
# PARAMS ARRIVE STRING-KEYED, lengths in millimetres. The MCP handler adds
# 'instance_object', 'position_point', 'direction_vector', 'opening_points'
# ({a:, b:, d:} Point3d in world inches), 'opening_report', 'run_points',
# 'wall_object', 'wall_to_world', 'outside_vector' / 'outside_point'.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'json'
require_relative '../50__System__PresetsLibrarySystem/Na__AssemblyStudio__PresetsLibrary__Store__'

module Na__AssemblyStudio

# -----------------------------------------------------------------------------
# REGION | Refusal Type
# -----------------------------------------------------------------------------

    # CLASS | A Refusal the MCP Handler Can Pass On With Its Fix
    # ------------------------------------------------------------
    class Na__McpOperationsError < StandardError
        attr_reader :na_code, :na_hint, :na_details

        def initialize(code, message, hint = nil, details = nil)
            super(message)
            @na_code = code.to_s
            @na_hint = hint
            @na_details = details
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

module Na__McpOperations

# -----------------------------------------------------------------------------
# REGION | Module References + Constants
# -----------------------------------------------------------------------------

    Store = Na__AssemblyStudio::Na__PresetsLibrarySystem::Na__Store

    NA_MODULES_ROOT  = File.expand_path('../..', __dir__)
    NA_APP_CONFIG    = File.join(NA_MODULES_ROOT, '02__Src__AppModules', '02__AppData', 'Na__AssemblyStudio__AppConfig__Main.json')
    NA_ASSET_LIBRARY = File.join(NA_MODULES_ROOT, '04__Data__AssetLibrary')

    NA_READ_ACTIONS = %w[status parameters elements inspect openings list_presets get_preset assets list_handles].freeze
    NA_EDIT_ACTIONS = %w[build update rename export_dxf save_preset update_preset archive_preset restore_preset
                         refresh_preview open_dialog reload].freeze

    NA_HANDLE_FOLDERS = {
        'exterior' => 'ExteriorDoor__Handles__',
        'interior' => 'InteriorDoor__Handles__'
    }.freeze

    NA_CAPTURE_FUNCTIONS = {
        'Window'       => 'na_capture_window_family_preview',
        'ExteriorDoor' => 'na_capture_window_family_preview',
        'InteriorDoor' => 'na_capture_interior_door_preview',
        'Cabinet'      => 'na_capture_cabinet_preview'
    }.freeze

    NA_MOD_NAME   = /\AMOD\d{3}/.freeze
    NA_FIELD_NAME = /__Field__\d{3}\z/.freeze
    NA_CUBIC_MM   = 25.4**3

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

    # FUNCTION | Read-Only Actions (entity_studio)
    # ------------------------------------------------------------
    # @return [Hash] string-keyed result with a 'summary'
    def self.Na__AssemblyStudio__McpRead(action, params)
        params = {} unless params.is_a?(Hash)
        case action.to_s
        when 'status'       then na_status
        when 'parameters'   then na_parameters(params)
        when 'elements'     then na_elements(params)
        when 'inspect'      then na_inspect(params)
        when 'openings'     then na_openings(params)
        when 'list_presets' then na_list_presets(params)
        when 'get_preset'   then na_get_preset(params)
        when 'assets'       then na_assets(params)
        when 'list_handles' then na_list_handles
        else
            na_refuse('invalid_params', "Unknown entity_studio action '#{action}'.", "Use one of: #{NA_READ_ACTIONS.join(', ')}.")
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Changing Actions (entity_studio_edit)
    # ------------------------------------------------------------
    # @return [Hash] string-keyed result with a 'summary'
    def self.Na__AssemblyStudio__McpEdit(action, params)
        params = {} unless params.is_a?(Hash)
        case action.to_s
        when 'build'           then na_build(params)
        when 'update'          then na_update(params)
        when 'rename'          then na_rename(params)
        when 'export_dxf'      then na_export_dxf(params)
        when 'save_preset'     then na_save_preset(params)
        when 'update_preset'   then na_update_preset(params)
        when 'archive_preset'  then na_archive_preset(params)
        when 'restore_preset'  then na_restore_preset(params)
        when 'refresh_preview' then na_refresh_preview(params)
        when 'open_dialog'     then na_open_dialog(params)
        when 'reload'          then na_reload
        else
            na_refuse('invalid_params', "Unknown entity_studio_edit action '#{action}'.", "Use one of: #{NA_EDIT_ACTIONS.join(', ')}.")
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Read Actions - Status, Presets, Handles
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Plugin Version, Folders, Products, Dialog State
    # ------------------------------------------------------------
    def self.na_status
        records  = Store.na_scan_presets
        archived = Store.respond_to?(:na_scan_archived_presets) ? Store.na_scan_archived_presets.length : 0
        systems  = na_catalogue.fetch('systems', {}).transform_values { |row| row['control_count'] }
        {
            'version'          => na_app_version,
            'modules_root'     => NA_MODULES_ROOT,
            'presets_folder'   => Store.na_presets_dir,
            'preset_count'     => records.length,
            'archived_presets' => archived,
            'dialog_open'      => na_dialog_open?,
            'types'            => NA_PRODUCTS.keys,
            'settings'         => systems,
            'catalogue'        => NA_CATALOGUE_FILE,
            'summary'          => "Element Assembly Studio Pro #{na_app_version}: builds #{NA_PRODUCTS.keys.join(', ')}; " \
                                  "#{systems.map { |system, count| "#{count} #{NA_SYSTEM_LABELS[system]} settings" }.join(', ')}; " \
                                  "#{records.length} presets; dialog #{na_dialog_open? ? 'open' : 'closed'}."
        }
    end
    private_class_method :na_status
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Preset Cards, Filtered by Family, Type or Text
    # ------------------------------------------------------------
    def self.na_list_presets(params)
        family = params['family'].to_s.strip
        query  = params['query'].to_s.strip.downcase
        wanted_type = params['type'] ? na_product(params['type']) : nil
        source = params['archived'] == true ? Store.na_scan_archived_presets : Store.na_scan_presets
        rows = source.select do |record|
            next false unless family.empty? || record['productFamily'].to_s.casecmp?(family)
            next false if wanted_type && !(record['productFamily'] == wanted_type[1]['family'] && record['productType'].to_s == wanted_type[1]['type'])
            next true if query.empty?

            [record['presetCode'], record['displayName'], record['description'], *record['keywords']]
                .any? { |text| text.to_s.downcase.include?(query) }
        end
        presets = rows.map { |record| na_preset_card(record) }
        {
            'presets' => presets,
            'summary' => "#{presets.length} #{params['archived'] == true ? 'archived ' : ''}preset#{presets.length == 1 ? '' : 's'}" \
                         "#{family.empty? ? '' : " (#{family})"}#{wanted_type ? " (#{wanted_type[0]})" : ''}."
        }
    end
    private_class_method :na_list_presets
    # ---------------------------------------------------------------

    # HELPER FUNCTION | One Preset With Its Values
    # ------------------------------------------------------------
    def self.na_get_preset(params)
        record = na_preset_record(params['code'])
        values = record['configValues'] || {}
        keys   = Array(params['keys']).map(&:to_s)
        prefix = params['prefix'].to_s
        shown = values.select do |key, _value|
            (keys.empty? || keys.include?(key)) && (prefix.empty? || key.start_with?(prefix))
        end
        na_preset_card(record).merge(
            'description' => record['description'],
            'value_count' => values.length,
            'values'      => shown,
            'summary'     => "#{record['presetCode']} #{record['displayName']}: #{shown.length} of #{values.length} values."
        )
    end
    private_class_method :na_get_preset
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Door Handle Assets by Key (as the Dropdowns Show Them)
    # ------------------------------------------------------------
    def self.na_list_handles
        handles = NA_HANDLE_FOLDERS.each_with_object({}) do |(kind, folder), memo|
            memo[kind] = Dir.glob(File.join(NA_ASSET_LIBRARY, folder, '*.json')).sort.filter_map do |path|
                key = File.basename(path, '.json').sub(/__\z/, '')
                next nil if key.start_with?('_')

                { 'key' => key, 'name' => na_asset_name(path), 'file' => path }
            end
        end
        {
            'handles' => handles,
            'summary' => handles.map { |kind, rows| "#{rows.length} #{kind}" }.join(', ') + ' door handles.'
        }
    end
    private_class_method :na_list_handles
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Edit Actions - Preview + Dialog
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Ask the Open Dialog to Redraw a Preset's Card Picture
    # ------------------------------------------------------------
    def self.na_refresh_preview(params)
        record = na_preset_record(params['code'])
        unless na_dialog_open?
            na_refuse('context_error', 'The Element Assembly Studio dialog is closed, and only it can draw a preset preview.',
                      'Call entity_studio_edit open_dialog, wait a moment for it to load, then refresh_preview again.')
        end

        state = na_request_preview(record['presetCode'])
        {
            'code'    => record['presetCode'],
            'preview' => state,
            'summary' => "Asked the dialog to redraw #{record['presetCode']}'s preview; confirm with entity_studio get_preset (has_preview)."
        }
    end
    private_class_method :na_refresh_preview
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Open the Dialog (and Show One Element in It)
    # ------------------------------------------------------------
    # With instance_id the element is selected and handed to the dialog's own
    # SelectionCoordinator, which loads it into its tab exactly as a click
    # would. The coordinator listens for onSelectionBulkChange (a click),
    # which Selection#add from code does not raise, so it is called here; a
    # dialog that was closed gets it once its page has had time to load.
    def self.na_open_dialog(params = {})
        was_open = na_dialog_open?
        Na__AssemblyStudio.na_init unless was_open
        shown = nil
        if params['instance_object']
            _instance, element = na_require_element(params)
            selection = Sketchup.active_model.selection
            selection.clear
            selection.add(params['instance_object'])
            coordinator = Na__AssemblyStudio::Na__AppCore::Na__SelectionCoordinator
            if was_open
                coordinator.na_dispatch_selection(selection)
            else
                UI.start_timer(2.0, false) { coordinator.na_dispatch_selection(Sketchup.active_model.selection) }
            end
            shown = element['id']
        end
        {
            'dialog_open' => na_dialog_open?,
            'showing'     => shown,
            'summary'     => "Element Assembly Studio dialog open#{shown ? ", showing #{shown} (selected#{was_open ? '' : '; it loads into the dialog about 2 s after its page opens'})" : ''}." \
                             "#{was_open ? '' : ' Its page loads a moment after this call returns.'}"
        }
    end
    private_class_method :na_open_dialog
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Adam's Reload Scripts (Code + Material Palettes)
    # ------------------------------------------------------------
    # The dialog is closed first and opened afresh afterwards. Reload
    # Scripts on its own reopens the old dialog, and on 09-Nov-2026 that
    # page sent nothing back: no preset, create or library callback reached
    # Ruby until it was closed and opened again.
    def self.na_reload
        dialog = na_dialog
        dialog.close if dialog
        Na__AssemblyStudio::Na__AppCore::Na__DialogManager.na_reload_scripts(NA_MODULES_ROOT)
        Na__AssemblyStudio.na_init if dialog
        {
            'version'     => na_app_version,
            'dialog_open' => na_dialog_open?,
            'summary'     => "Reloaded Element Assembly Studio Pro #{na_app_version} from disk#{dialog ? ' and opened a fresh dialog' : ''}. " \
                             'Methods deleted from the source survive until SketchUp restarts.'
        }
    end
    private_class_method :na_reload
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Materials, Instances, Copies
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Load the Material Library the Way Opening the Dialog Does
    # ------------------------------------------------------------
    # Every finish (glass, leaf, frame, handle) is resolved from the library
    # by id. Without it they all come back nil, which built ADR003's glass
    # with no material when it was placed before the dialog had ever opened.
    def self.na_ensure_materials
        manager = Na__AssemblyStudio::Na__AppData::Na__MaterialManager
        return if manager.na_meta

        if defined?(Na__AssemblyStudio::NA_CACHE_DIR_PATH)
            Na__DataLib__CacheData.Na__Cache__SetCacheDirOverride(Na__AssemblyStudio::NA_CACHE_DIR_PATH)
        end
        manager.na_load_materials_library
        manager.na_initialize_standard_materials
        manager.na_ensure_safety_materials
        return if manager.na_meta

        na_refuse('operation_failed', 'The Element Assembly Studio material library could not be loaded, so every finish would be blank.',
                  'Open the dialog once (entity_studio_edit open_dialog) or check the network and the DataLib cache, then build again.')
    end
    private_class_method :na_ensure_materials
    # ---------------------------------------------------------------

    # HELPER FUNCTION | The Instance the Handler Resolved, or a Refusal
    # ------------------------------------------------------------
    def self.na_require_instance(params)
        instance = params['instance_object']
        return instance if instance.is_a?(Sketchup::ComponentInstance) && instance.valid?

        na_refuse('invalid_params', 'This action needs instance_id: a placed element built by Element Assembly Studio.',
                  'List them with entity_studio elements, then pass its instance_id.')
    end
    private_class_method :na_require_instance
    # ---------------------------------------------------------------

    # HELPER FUNCTION | A Deep, Unfrozen Copy of JSON-Shaped Data
    # ------------------------------------------------------------
    def self.na_deep_copy(value)
        JSON.parse(JSON.generate(value))
    end
    private_class_method :na_deep_copy
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Numbers as the Dialog Sends Them
    # ------------------------------------------------------------
    # A value that crossed the dialog's JSON round trip is an Integer when it
    # is whole (JS writes 1200, never 1200.0). The engines and exporters rely
    # on it: the window DXF header writes "#{width}.0", so a Float 1200.0
    # came out as "1200.0.0" (11-Nov-2026). Whole floats become integers here.
    def self.na_json_numbers(value)
        case value
        when Float then value.finite? && value == value.round ? value.round : value
        when Hash then value.transform_values { |item| na_json_numbers(item) }
        when Array then value.map { |item| na_json_numbers(item) }
        else value
        end
    end
    private_class_method :na_json_numbers
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Presets, Preview, Dialog
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | One Preset Record by Code, or a Refusal
    # ------------------------------------------------------------
    def self.na_preset_record(code)
        wanted = code.to_s.strip
        na_refuse('invalid_params', 'Say which preset: pass its code, e.g. EAS008.', 'List them with entity_studio list_presets.') if wanted.empty?

        record = Store.na_scan_presets.find { |row| row['presetCode'].to_s.casecmp?(wanted) }
        return record if record

        archived = Store.respond_to?(:na_scan_archived_presets) && Store.na_scan_archived_presets.any? { |row| row['presetCode'].to_s.casecmp?(wanted) }
        na_refuse('not_found', "No preset #{wanted} in #{Store.na_presets_dir}#{archived ? ' (it is archived)' : ''}.",
                  archived ? 'Bring it back with entity_studio_edit restore_preset first.' : 'List them with entity_studio list_presets.')
    end
    private_class_method :na_preset_record
    # ---------------------------------------------------------------

    # HELPER FUNCTION | A Preset's Card Fields (No Values, No Markup)
    # ------------------------------------------------------------
    def self.na_preset_card(record)
        preview = record['svgPreview'] || {}
        system  = na_system_of_family(record['productFamily'])
        product = begin
                      na_product_of_preset(system, record)
                  rescue StandardError
                      nil
                  end
        {
            'code'          => record['presetCode'],
            'name'          => record['displayName'],
            'family'        => record['productFamily'],
            'type'          => product,
            'product_type'  => record['productType'],
            'keywords'      => record['keywords'],
            'file'          => record['sourceFile'],
            'created'       => record['createdDate'],
            'last_modified' => record['lastModified'],
            'has_preview'   => !preview['svgMarkup'].to_s.strip.empty?
        }
    end
    private_class_method :na_preset_card
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Have the Open Dialog Draw and Store a Preset Preview
    # ------------------------------------------------------------
    # The page draws the card with its own SvgCapture and sends it back
    # through its existing na_presetsUpdateConfig callback; the Store then
    # rewrites the file (keeping a .bak) and the gallery re-renders.
    # @return [String] 'requested' | 'dialog_closed'
    def self.na_request_preview(code)
        dialog = na_dialog
        return 'dialog_closed' unless dialog

        record = na_preset_record(code)
        capture = NA_CAPTURE_FUNCTIONS.fetch(record['productFamily'], NA_CAPTURE_FUNCTIONS['Window'])
        payload = {
            'presetCode'     => record['presetCode'],
            'sourceFile'     => record['sourceFile'],
            'productFamily'  => record['productFamily'],
            'productType'    => record['productType'],
            'schemaContract' => record['schemaContract'],
            'configValues'   => record['configValues']
        }
        dialog.execute_script(
            '(function(){var p=' + JSON.generate(payload) + ';' \
            'var c=window.Na__PresetsLibrary__SvgCapture;' \
            "if(!c||typeof c.#{capture}!=='function'||!window.sketchup||!window.sketchup.na_presetsUpdateConfig){return;}" \
            "p.svgPreview=c.#{capture}(p.configValues);" \
            'if(p.svgPreview&&p.svgPreview.svgMarkup){window.sketchup.na_presetsUpdateConfig(JSON.stringify(p));}})();'
        )
        'requested'
    end
    private_class_method :na_request_preview
    # ---------------------------------------------------------------

    # HELPER FUNCTION | The Dialog When It Is Showing
    # ------------------------------------------------------------
    def self.na_dialog
        return nil unless defined?(Na__AssemblyStudio::Na__AppCore::Na__DialogManager)

        dialog = Na__AssemblyStudio::Na__AppCore::Na__DialogManager.na_get_dialog
        dialog && dialog.visible? ? dialog : nil
    end
    private_class_method :na_dialog
    # ---------------------------------------------------------------

    def self.na_dialog_open?
        !na_dialog.nil?
    end
    private_class_method :na_dialog_open?
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Geometry Rows, Files, Refusals
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Every Fielded Panel Cell Under an Instance
    # ------------------------------------------------------------
    def self.na_field_rows(instance)
        rows = []
        na_each_field(instance.definition.entities) { |field| rows << na_part_row(field) }
        rows
    end
    private_class_method :na_field_rows
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Yield Every Group Named <container>__Field__NNN
    # ------------------------------------------------------------
    def self.na_each_field(entities, &block)
        entities.grep(Sketchup::Group).each do |group|
            if group.name.match?(NA_FIELD_NAME)
                block.call(group)
            else
                na_each_field(group.entities, &block)
            end
        end
    end
    private_class_method :na_each_field
    # ---------------------------------------------------------------

    # HELPER FUNCTION | One Part: Solid, Volume, Faces, Nested Groups
    # ------------------------------------------------------------
    # A group holding only groups (PanelGeometry) is a container, not a
    # failed solid: its own parts are reported on their own.
    def self.na_part_row(group)
        solid = group.manifold?
        faces = group.entities.grep(Sketchup::Face).length
        nested = group.entities.grep(Sketchup::Group).length
        {
            'name'          => group.name,
            'container'     => faces.zero? && nested > 0,
            'solid'         => solid,
            'volume_mm3'    => solid ? (group.volume * NA_CUBIC_MM).round : nil,
            'faces'         => faces,
            'nested_groups' => nested
        }
    end
    private_class_method :na_part_row
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Plugin Version From AppConfig (Read Fresh)
    # ------------------------------------------------------------
    def self.na_app_version
        JSON.parse(File.read(NA_APP_CONFIG, encoding: 'UTF-8')).dig('appConfig', 'metadata', 'version').to_s
    rescue StandardError
        'unknown'
    end
    private_class_method :na_app_version
    # ---------------------------------------------------------------

    # HELPER FUNCTION | An Asset File's Display Name
    # ------------------------------------------------------------
    def self.na_asset_name(path)
        data = JSON.parse(File.read(path, encoding: 'UTF-8'))
        found = nil
        stack = [data]
        until found || stack.empty?
            node = stack.shift
            next unless node.is_a?(Hash)

            found = node['Na__Asset__Name']
            stack.concat(node.values.select { |value| value.is_a?(Hash) })
        end
        found.to_s
    rescue StandardError
        ''
    end
    private_class_method :na_asset_name
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Raise a Refusal That Names the Fix
    # ------------------------------------------------------------
    def self.na_refuse(code, message, hint = nil, details = nil)
        raise Na__AssemblyStudio::Na__McpOperationsError.new(code, message, hint, details)
    end
    private_class_method :na_refuse
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__McpOperations
end # module Na__AssemblyStudio

# -----------------------------------------------------------------------------
# REGION | The Rest of the Seam
# -----------------------------------------------------------------------------

require_relative 'Na__AssemblyStudio__McpOperations__Catalogue__'
require_relative 'Na__AssemblyStudio__McpOperations__Validation__'
require_relative 'Na__AssemblyStudio__McpOperations__SideEffects__'
require_relative 'Na__AssemblyStudio__McpOperations__Openings__'
require_relative 'Na__AssemblyStudio__McpOperations__Elements__'
require_relative 'Na__AssemblyStudio__McpOperations__Presets__'

# endregion -------------------------------------------------------------------

# =============================================================================
# END OF FILE
# =============================================================================
