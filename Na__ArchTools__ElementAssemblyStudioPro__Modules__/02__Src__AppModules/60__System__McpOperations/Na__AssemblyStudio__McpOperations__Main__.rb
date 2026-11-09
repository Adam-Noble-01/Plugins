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
# PURPOSE    : What an agent may do with Element Assembly Studio Pro through
#              Adam's Na SketchUp MCP plugin (tools entity_studio and
#              entity_studio_edit). The MCP handlers are thin: they resolve
#              ids and points, then call the two entry points below.
#
# ENTRY POINTS:
# - Na__McpOperations.Na__AssemblyStudio__McpRead(action, params)
#     status, list_presets, get_preset, list_handles, inspect
# - Na__McpOperations.Na__AssemblyStudio__McpEdit(action, params)
#     build, update, save_preset, refresh_preview, open_dialog, reload
# - Refusals raise Na__McpOperationsError (code, message, hint, details); the
#   MCP handler turns them into its own error with the fix named.
#
# WHAT IT REUSES (no second copy of any rule):
# - Builds and updates go through each system's own GeometryEngine, which
#   opens and commits its own undo operation, so one Ctrl+Z removes a build.
#   Only the hinged exterior doors (single, double) have a complete engine
#   outside the dialog; windows, sliding and bifold doors are refused.
# - Presets are written by the Presets Library Store (code allocation, file
#   name, pretty writer, .bak on every overwrite).
# - Gallery previews are drawn by the dialog's own SvgCapture and stored
#   through its existing na_presetsUpdateConfig callback, so they are exactly
#   what Capture Current Design would store. That needs the dialog open, and
#   it lands a moment after the call returns.
#
# PARAMS ARRIVE STRING-KEYED, lengths in millimetres. The MCP handler adds
# 'instance_object' (a resolved Sketchup::ComponentInstance) and
# 'position_point' (a Geom::Point3d in model inches) where they apply.
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

    NA_READ_ACTIONS = %w[status list_presets get_preset list_handles inspect].freeze
    NA_EDIT_ACTIONS = %w[build update save_preset refresh_preview open_dialog reload].freeze

    # Hinged exterior doors: the systems whose engines build and update
    # outside the dialog, each in its own undo operation.
    NA_HINGED_SYSTEMS = {
        'Single' => {
            :mode_key => 'ext_single_door_mode',
            :system   => :Na__ExteriorSingleDoorSystem,
            :build    => :na_build_exterior_single_door,
            :update   => :na_update_exterior_single_door
        }.freeze,
        'Double' => {
            :mode_key => 'double_door_mode',
            :system   => :Na__ExteriorDoubleDoorSystem,
            :build    => :na_build_exterior_double_door,
            :update   => :na_update_exterior_double_door
        }.freeze
    }.freeze

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
        when 'list_presets' then na_list_presets(params)
        when 'get_preset'   then na_get_preset(params)
        when 'list_handles' then na_list_handles
        when 'inspect'      then na_inspect(params)
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
        when 'save_preset'     then na_save_preset(params)
        when 'refresh_preview' then na_refresh_preview(params)
        when 'open_dialog'     then na_open_dialog
        when 'reload'          then na_reload
        else
            na_refuse('invalid_params', "Unknown entity_studio_edit action '#{action}'.", "Use one of: #{NA_EDIT_ACTIONS.join(', ')}.")
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Read Actions
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Plugin Version, Folders, Dialog State
    # ------------------------------------------------------------
    def self.na_status
        records = Store.na_scan_presets
        {
            'version'        => na_app_version,
            'modules_root'   => NA_MODULES_ROOT,
            'presets_folder' => Store.na_presets_dir,
            'preset_count'   => records.length,
            'dialog_open'    => na_dialog_open?,
            'buildable'      => NA_HINGED_SYSTEMS.keys.map { |type| "ExteriorDoor/#{type}" },
            'summary'        => "Element Assembly Studio Pro #{na_app_version}: #{records.length} presets, dialog #{na_dialog_open? ? 'open' : 'closed'}."
        }
    end
    private_class_method :na_status
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Preset Cards, Filtered by Family or Text
    # ------------------------------------------------------------
    def self.na_list_presets(params)
        family = params['family'].to_s.strip
        query = params['query'].to_s.strip.downcase
        rows = Store.na_scan_presets.select do |record|
            next false unless family.empty? || record['productFamily'].casecmp?(family)
            next true if query.empty?

            [record['presetCode'], record['displayName'], record['description'], *record['keywords']]
                .any? { |text| text.to_s.downcase.include?(query) }
        end
        presets = rows.map { |record| na_preset_card(record) }
        {
            'presets' => presets,
            'summary' => "#{presets.length} preset#{presets.length == 1 ? '' : 's'}#{family.empty? ? '' : " (#{family})"}."
        }
    end
    private_class_method :na_list_presets
    # ---------------------------------------------------------------

    # HELPER FUNCTION | One Preset With Its Values
    # ------------------------------------------------------------
    def self.na_get_preset(params)
        record = na_preset_record(params['code'])
        values = record['configValues'] || {}
        keys = Array(params['keys']).map(&:to_s)
        prefix = params['prefix'].to_s
        shown = values.select do |key, _value|
            (keys.empty? || keys.include?(key)) && (prefix.empty? || key.start_with?(prefix))
        end
        na_preset_card(record).merge(
            'description'  => record['description'],
            'value_count'  => values.length,
            'values'       => shown,
            'summary'      => "#{record['presetCode']} #{record['displayName']}: #{shown.length} of #{values.length} values."
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

    # HELPER FUNCTION | Parts of a Built Element, Solid or Not
    # ------------------------------------------------------------
    # Reports every MOD leaf group's parts and every fielded panel cell, so
    # an agent can prove panels are closed solids without ruby_eval.
    def self.na_inspect(params)
        instance = na_require_instance(params)
        definition = instance.definition
        mods = definition.entities.grep(Sketchup::Group).select { |group| group.name.match?(NA_MOD_NAME) }
        fields = []
        mod_rows = mods.map do |mod|
            parts = mod.entities.grep(Sketchup::Group).map { |group| na_part_row(group) }
            na_each_field(mod.entities) { |field| fields << na_part_row(field).merge('mod' => mod.name) }
            { 'name' => mod.name, 'tag' => mod.layer.name, 'parts' => parts }
        end
        not_solid = fields.reject { |row| row['solid'] }
        {
            'definition'   => definition.name,
            'element_type' => na_instance_type(instance),
            'mods'         => mod_rows,
            'fields'       => { 'count' => fields.length, 'all_solid' => not_solid.empty?, 'rows' => fields },
            'summary'      => "#{definition.name}: #{mods.length} MOD group#{mods.length == 1 ? '' : 's'}, " \
                              "#{fields.length} fielded panel#{fields.length == 1 ? '' : 's'}, #{not_solid.length} not solid."
        }
    end
    private_class_method :na_inspect
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Edit Actions - Build + Update
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Build a Hinged Exterior Door From a Preset and Values
    # ------------------------------------------------------------
    def self.na_build(params)
        values = na_values_from(params)
        type = na_hinged_type(values)
        spec = NA_HINGED_SYSTEMS[type]
        system = na_require_system(spec)
        na_ensure_materials
        point = params['position_point'] || Geom::Point3d.new(0, 0, 0)
        instance = system::Na__GeometryEngine.public_send(spec[:build], values, nil, point)
        unless instance.is_a?(Sketchup::ComponentInstance) && instance.valid?
            na_refuse('operation_failed', "The #{type.downcase} door engine built nothing.",
                      'Open the Ruby Console for the Element Assembly Studio error, check the values, then try again.')
        end

        fields = na_field_rows(instance)
        {
            'instance_object' => instance,
            'definition'      => instance.definition.name,
            'element_type'    => "ExteriorDoor/#{type}",
            'undo_name'       => "Create Exterior #{type} Door",
            'fields'          => { 'count' => fields.length, 'all_solid' => fields.all? { |row| row['solid'] } },
            'summary'         => "Built #{instance.definition.name} (exterior #{type.downcase} door), " \
                                 "#{fields.length} fielded panel#{fields.length == 1 ? '' : 's'}."
        }
    end
    private_class_method :na_build
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Rebuild a Placed Hinged Door With New Values
    # ------------------------------------------------------------
    def self.na_update(params)
        instance = na_require_instance(params)
        type = na_instance_type(instance)
        spec = NA_HINGED_SYSTEMS[type.to_s.split('/').last]
        unless spec
            na_refuse('wrong_type', "#{instance.definition.name} is not an exterior single or double door built by Element Assembly Studio.",
                      'Pass the instance_id of an ADR door it built, or edit this element in the dialog.')
        end

        system = na_require_system(spec)
        na_ensure_materials
        values = na_values_from(params.merge('instance_object' => instance))
        unless system::Na__GeometryEngine.public_send(spec[:update], instance, values)
            na_refuse('operation_failed', "The door engine could not rebuild #{instance.definition.name}.",
                      'Open the Ruby Console for the Element Assembly Studio error, check the values, then try again.')
        end

        fields = na_field_rows(instance)
        {
            'instance_object' => instance,
            'definition'      => instance.definition.name,
            'element_type'    => type,
            'undo_name'       => "Update Exterior #{type.split('/').last} Door",
            'fields'          => { 'count' => fields.length, 'all_solid' => fields.all? { |row| row['solid'] } },
            'summary'         => "Rebuilt #{instance.definition.name} with #{Hash(params['values']).length} changed value(s)."
        }
    end
    private_class_method :na_update
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Edit Actions - Presets + Dialog
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Write a New Preset Through the Presets Store
    # ------------------------------------------------------------
    def self.na_save_preset(params)
        name = params['name'].to_s.strip
        na_refuse('invalid_params', 'save_preset needs a name.', 'Pass name, e.g. "Traditional | Four Panel Half Glazed Door".') if name.empty?

        base = params['preset'] ? na_preset_record(params['preset']) : nil
        values = na_values_from(params)
        family, type, contract = na_product_of(values, base)
        result = Store.na_save_new_preset(
            'presetName'        => name,
            'presetDescription' => params['description'].to_s,
            'presetKeywords'    => Array(params['keywords']).map(&:to_s),
            'productFamily'     => family,
            'productType'       => type,
            'schemaContract'    => contract,
            'configValues'      => values,
            'svgPreview'        => nil
        )
        unless result['isSaved']
            na_refuse('file_error', result['statusMessage'].to_s, 'Check the presets folder is writable and the name is new.',
                      { 'reason' => result['reason'] })
        end

        preview = na_request_preview(result['presetCode'])
        {
            'code'      => result['presetCode'],
            'file'      => result['sourceFile'],
            'family'    => family,
            'type'      => type,
            'preview'   => preview,
            'warnings'  => preview == 'requested' ? [] : ['The gallery card has no picture yet: open the dialog (open_dialog), then refresh_preview.'],
            'summary'   => "Saved preset #{result['presetCode']} #{name} (#{family}/#{type}); preview #{preview}."
        }
    end
    private_class_method :na_save_preset
    # ---------------------------------------------------------------

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

    # HELPER FUNCTION | Open the Element Assembly Studio Dialog
    # ------------------------------------------------------------
    def self.na_open_dialog
        Na__AssemblyStudio.na_init unless na_dialog_open?
        {
            'dialog_open' => na_dialog_open?,
            'summary'     => 'Element Assembly Studio dialog open. Its page loads a moment after this call returns.'
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
# REGION | Internal Helpers - Values, Types, Systems
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Base Values (Preset or Placed Element) + Overrides
    # ------------------------------------------------------------
    def self.na_values_from(params)
        base = if params['preset']
                   JSON.parse(JSON.generate(na_preset_record(params['preset'])['configValues'] || {}))
               elsif params['instance_object']
                   na_instance_values(params['instance_object'])
               else
                   {}
               end
        overrides = params['values']
        if overrides && !overrides.is_a?(Hash)
            na_refuse('invalid_params', 'values must be an object of config keys and values.', 'e.g. {"single_door_panel_preset": "TwoVertical"}.')
        end

        values = base.merge(overrides || {})
        if values.empty?
            na_refuse('invalid_params', 'Nothing to build from.', 'Pass preset (a code such as EAS008), an instance_id, or a full values object.')
        end
        values
    end
    private_class_method :na_values_from
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Which Hinged Door a Window-Family Config Builds
    # ------------------------------------------------------------
    def self.na_hinged_type(values)
        type = NA_HINGED_SYSTEMS.find { |_type, spec| values[spec[:mode_key]] == true }&.first
        return type if type

        found = if values['sliding_mode'] == true then 'a sliding door'
                elsif values['multifold_mode'] == true then 'a bifold door'
                elsif values.key?('Na__DoorConfiguration') || values.key?('Na__DoorConfig__HandleAssetKey') then 'an interior door'
                else 'a window'
                end
        na_refuse('unsupported', "These values build #{found}; entity_studio_edit builds exterior single and double doors only.",
                  'Set ext_single_door_mode or double_door_mode true, or build this one from the dialog.')
    end
    private_class_method :na_hinged_type
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Family / Type / Schema Contract for a Preset File
    # ------------------------------------------------------------
    def self.na_product_of(values, base)
        if values['ui_element_category'].to_s == 'ExteriorDoors' || NA_HINGED_SYSTEMS.values.any? { |spec| values[spec[:mode_key]] == true }
            type = values['ui_exterior_door_type'].to_s
            type = NA_HINGED_SYSTEMS.find { |_type, spec| values[spec[:mode_key]] == true }&.first.to_s if type.empty?
            return ['ExteriorDoor', type.empty? ? 'Double' : type, 'windowConfiguration']
        end
        return [base['productFamily'], base['productType'], base['schemaContract']] if base && base['productFamily'] != 'Window'

        ['Window', values['ui_window_type'].to_s.empty? ? 'Casement' : values['ui_window_type'].to_s, 'windowConfiguration']
    end
    private_class_method :na_product_of
    # ---------------------------------------------------------------

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

    # HELPER FUNCTION | Load a Hinged Door System's Lazy Modules
    # ------------------------------------------------------------
    def self.na_require_system(spec)
        system = Na__AssemblyStudio.const_get(spec[:system])
        system.na_require_modules
        system
    end
    private_class_method :na_require_system
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Which Hinged Door Built This Instance
    # ------------------------------------------------------------
    # @return [String, nil] "ExteriorDoor/Single" | "ExteriorDoor/Double"
    def self.na_instance_type(instance)
        NA_HINGED_SYSTEMS.each do |type, spec|
            system = na_require_system(spec)
            return "ExteriorDoor/#{type}" if system::Na__DataSerializer.na_get_door_id_from_instance(instance)
        end
        nil
    end
    private_class_method :na_instance_type
    # ---------------------------------------------------------------

    # HELPER FUNCTION | The Full Config Stored on a Placed Hinged Door
    # ------------------------------------------------------------
    def self.na_instance_values(instance)
        type = na_instance_type(instance).to_s.split('/').last
        spec = NA_HINGED_SYSTEMS[type]
        unless spec
            na_refuse('wrong_type', "#{instance.definition.name} has no Element Assembly Studio door data.",
                      'Pass the instance_id of an exterior single or double door it built.')
        end

        system = na_require_system(spec)
        payload = system::Na__DataSerializer.na_load_from_instance(instance) || {}
        JSON.parse(JSON.generate(payload[system::NA_KEY_CONFIGURATION] || {}))
    end
    private_class_method :na_instance_values
    # ---------------------------------------------------------------

    # HELPER FUNCTION | The Instance the Handler Resolved, or a Refusal
    # ------------------------------------------------------------
    def self.na_require_instance(params)
        instance = params['instance_object']
        return instance if instance.is_a?(Sketchup::ComponentInstance) && instance.valid?

        na_refuse('invalid_params', 'This action needs instance_id: a placed element built by Element Assembly Studio.',
                  'Find it with entity_query (name_contains "ADR"), then pass its id.')
    end
    private_class_method :na_require_instance
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

        record = Store.na_scan_presets.find { |row| row['presetCode'].casecmp?(wanted) }
        return record if record

        na_refuse('not_found', "No preset #{wanted} in #{Store.na_presets_dir}.", 'List them with entity_studio list_presets.')
    end
    private_class_method :na_preset_record
    # ---------------------------------------------------------------

    # HELPER FUNCTION | A Preset's Card Fields (No Values, No Markup)
    # ------------------------------------------------------------
    def self.na_preset_card(record)
        preview = record['svgPreview'] || {}
        {
            'code'          => record['presetCode'],
            'name'          => record['displayName'],
            'family'        => record['productFamily'],
            'type'          => record['productType'],
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

# =============================================================================
# END OF FILE
# =============================================================================
