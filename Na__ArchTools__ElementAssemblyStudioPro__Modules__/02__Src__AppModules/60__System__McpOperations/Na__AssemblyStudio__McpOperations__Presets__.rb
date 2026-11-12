# frozen_string_literal: true

# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - MCP OPERATIONS - PRESETS, DXF, ASSETS
# =============================================================================
#
# FILE       : Na__AssemblyStudio__McpOperations__Presets__.rb
# NAMESPACE  : Na__AssemblyStudio
# MODULE     : Na__McpOperations
# AUTHOR     : Noble Architecture
# CREATED    : 11-Nov-2026 (V2.6.0)
# PURPOSE    : The Presets Library for every family (windows, exterior doors,
#              interior doors, cabinets), DXF export to a file, and the asset
#              lists the dialog's dropdowns and finish cards offer.
#
# PRESETS
#   Written only by the Presets Library Store: the next free EASnnn code,
#   the file name, the pretty writer and a .bak on every overwrite. A preset
#   is never deleted: archive_preset moves it into 01__Archive/ and
#   restore_preset brings it back. Adam agrees each preset's name before it
#   is saved: agents ask first.
#
# DXF
#   The dialog's Export DXF asks where to save with a modal panel; here the
#   path is given. Windows and hinged exterior doors only, as in the dialog
#   (its bifold and sliding export would draw a window).
#
# =============================================================================

require 'json'

module Na__AssemblyStudio
module Na__McpOperations

# -----------------------------------------------------------------------------
# REGION | Presets - Saving and Changing
# -----------------------------------------------------------------------------

    # FUNCTION | Save a New Preset From an Element, a Preset or a Type
    # ------------------------------------------------------------
    def self.na_save_preset(params)
        name = params['name'].to_s.strip
        na_refuse('invalid_params', 'save_preset needs a name.', 'Agree the gallery name with Adam first, e.g. "Traditional | Four Panel Half Glazed".') if name.empty?

        source = na_preset_source(params)
        result = Store.na_save_new_preset(
            'presetName'        => name,
            'presetDescription' => params['description'].to_s,
            'presetKeywords'    => Array(params['keywords']).map(&:to_s),
            'productFamily'     => source['family'],
            'productType'       => source['type'],
            'schemaContract'    => source['contract'],
            'configValues'      => source['values'],
            'svgPreview'        => nil
        )
        unless result['isSaved']
            na_refuse('file_error', result['statusMessage'].to_s, 'Check the presets folder is writable and the name is new.', { 'reason' => result['reason'] })
        end

        preview = na_request_preview(result['presetCode'])
        {
            'code'     => result['presetCode'],
            'file'     => result['sourceFile'],
            'family'   => source['family'],
            'type'     => source['type'],
            'preview'  => preview,
            'warnings' => source['warnings'] + (preview == 'requested' ? [] : ['The gallery card has no picture yet: open the dialog (open_dialog), then refresh_preview.']),
            'summary'  => "Saved preset #{result['presetCode']} #{name} (#{source['family']}/#{source['type']}, #{source['values'].length} values); preview #{preview}."
        }
    end
    private_class_method :na_save_preset
    # ---------------------------------------------------------------

    # FUNCTION | Change a Preset's Details and/or Its Values
    # ------------------------------------------------------------
    # Details: name, description, keywords (each kept unless given). Values:
    # from instance_id (its stored values) or values laid on the preset's own.
    def self.na_update_preset(params)
        record  = na_preset_record(params['code'])
        changed = []

        if %w[name description keywords].any? { |key| params.key?(key) }
            result = Store.na_update_preset_meta(
                'presetCode'        => record['presetCode'],
                'sourceFile'        => record['sourceFile'],
                'presetName'        => params.key?('name') ? params['name'].to_s : record['displayName'].to_s,
                'presetDescription' => params.key?('description') ? params['description'].to_s : record['description'].to_s,
                'presetKeywords'    => params.key?('keywords') ? Array(params['keywords']).map(&:to_s) : Array(record['keywords'])
            )
            na_refuse('file_error', result['statusMessage'].to_s, nil, { 'reason' => result['reason'] }) unless result['isSaved']
            changed << 'details'
        end

        warnings = []
        if params['instance_object'] || params['values']
            source = na_preset_source(params.merge('preset' => record['presetCode']))
            if na_system_of_family(source['family']) != na_system_of_family(record['productFamily'])
                na_refuse('invalid_params', "#{record['presetCode']} is a #{record['productFamily']} preset; those values are #{source['family']}.", 'Save them as a new preset instead.')
            end
            result = Store.na_update_preset_config(
                'presetCode'     => record['presetCode'],
                'sourceFile'     => record['sourceFile'],
                'productFamily'  => source['family'],
                'productType'    => source['type'],
                'schemaContract' => source['contract'],
                'configValues'   => source['values'],
                'svgPreview'     => nil
            )
            na_refuse('file_error', result['statusMessage'].to_s, nil, { 'reason' => result['reason'] }) unless result['isSaved']
            changed << 'values'
            warnings.concat(source['warnings'])
        end
        na_refuse('invalid_params', 'Nothing to change.', 'Pass name, description, keywords, values or instance_id.') if changed.empty?

        preview = changed.include?('values') ? na_request_preview(record['presetCode']) : 'unchanged'
        warnings << 'The gallery picture still shows the old values: open the dialog, then refresh_preview.' if preview == 'dialog_closed'
        {
            'code'     => record['presetCode'],
            'changed'  => changed,
            'preview'  => preview,
            'backup'   => "#{record['sourceFile']}.bak",
            'warnings' => warnings,
            'summary'  => "Updated preset #{record['presetCode']} (#{changed.join(' and ')}); the old file is kept as .bak."
        }
    end
    private_class_method :na_update_preset
    # ---------------------------------------------------------------

    # FUNCTION | Move a Preset Into 01__Archive (Never Deleted)
    # ------------------------------------------------------------
    def self.na_archive_preset(params)
        record = na_preset_record(params['code'])
        result = Store.na_archive_preset('presetCode' => record['presetCode'], 'sourceFile' => record['sourceFile'])
        na_refuse('file_error', result['statusMessage'].to_s, nil, { 'reason' => result['reason'] }) unless result['isSaved']

        {
            'code'    => record['presetCode'],
            'file'    => result['sourceFile'],
            'summary' => "#{record['presetCode']} #{record['displayName']} moved to the archive; restore_preset brings it back. Its code stays taken."
        }
    end
    private_class_method :na_archive_preset
    # ---------------------------------------------------------------

    # FUNCTION | Bring an Archived Preset Back
    # ------------------------------------------------------------
    def self.na_restore_preset(params)
        wanted = params['code'].to_s.strip
        record = Store.na_scan_archived_presets.find { |row| row['presetCode'].casecmp?(wanted) }
        na_refuse('not_found', "No archived preset #{wanted}.", 'List them with entity_studio list_presets archived: true.') unless record

        result = Store.na_restore_preset('presetCode' => record['presetCode'], 'sourceFile' => record['sourceFile'])
        na_refuse('file_error', result['statusMessage'].to_s, nil, { 'reason' => result['reason'] }) unless result['isSaved']

        {
            'code'    => record['presetCode'],
            'file'    => result['sourceFile'],
            'summary' => "#{record['presetCode']} #{record['displayName']} is back in the gallery."
        }
    end
    private_class_method :na_restore_preset
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Values, Family, Type and Contract for a Preset File
    # ------------------------------------------------------------
    # From instance_id (the element's stored values), else a preset, else a
    # type's starting values; values on top, checked like any build.
    def self.na_preset_source(params)
        if params['instance_object']
            _instance, element = na_require_element(params)
            system  = element['system']
            product = element['product']
            base    = na_over_dialog_defaults(system, element['root'][NA_CONFIG_BLOCK[system]])
        elsif params['preset']
            record  = na_preset_record(params['preset'])
            system  = na_system_of_family(record['productFamily'])
            product = na_product_of_preset(system, record)
            base    = na_over_dialog_defaults(system, record['configValues'])
        elsif params['type']
            product, = na_product(params['type'])
            system  = NA_PRODUCTS[product]['system']
            base    = na_fresh_root(product)[NA_CONFIG_BLOCK[system]]
        else
            na_refuse('invalid_params', 'Say where the preset values come from.', 'Pass instance_id (a placed element), preset (a code) or type, plus any values.')
        end

        checked, warnings = na_check_values(system, product, base, params['values'])
        values = base.merge(checked)
        warnings += na_dialog_side_effects!(system, base, values, checked.keys)
        values = na_json_numbers(values)
        na_apply_product_flags!(values, product) if system == 'window_family'
        errors = na_validation_errors(system, product, values)
        na_refuse('invalid_params', "The dialog would refuse these values: #{errors.join(' | ')}", nil, { 'errors' => errors }) unless errors.empty?

        row = NA_PRODUCTS[product]
        {
            'family'   => row['family'],
            'type'     => row['type'],
            'contract' => NA_CONFIG_BLOCK[system],
            'values'   => values,
            'warnings' => warnings
        }
    end
    private_class_method :na_preset_source
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | DXF Export
# -----------------------------------------------------------------------------

    # FUNCTION | Write the Dialog's DXF for an Element, a Preset or a Type
    # ------------------------------------------------------------
    def self.na_export_dxf(params)
        path = params['file'].to_s.strip
        unless path.match?(%r{\A([A-Za-z]:[\\/]|\\\\|/)}) && path.downcase.end_with?('.dxf')
            na_refuse('invalid_params', 'path must be an absolute file path ending .dxf.', 'e.g. C:/Temp/AWN001.dxf')
        end
        folder = File.dirname(path)
        na_refuse('not_found', "The folder #{folder} does not exist.", 'Create it first or choose another folder.') unless File.directory?(folder)
        if File.exist?(path) && params['overwrite'] != true
            na_refuse('file_exists', "#{File.basename(path)} already exists.", 'Pass overwrite: true to replace it, or choose another name.')
        end

        source = na_preset_source(params.merge('values' => params['values']))
        product = na_product_of_values('window_family', source['values'])
        if source['contract'] != 'windowConfiguration' || %w[bifold sliding].include?(product)
            na_refuse('unsupported', "The dialog has no DXF export for #{product == 'interior_door' || source['contract'] != 'windowConfiguration' ? source['family'] : "#{product} doors"}.",
                      'DXF covers windows and hinged exterior doors (single, double).')
        end

        callbacks = Na__AssemblyStudio::Na__WindowSystem::Na__DialogCallbacks
        content, = callbacks.na_generate_dxf_content(source['values'])
        na_refuse('operation_failed', 'The DXF exporter returned nothing for these values.', 'Read the Ruby Console for the exporter error.') if content.to_s.empty?

        File.write(path, content)
        {
            'path'    => path,
            'bytes'   => File.size(path),
            'type'    => product,
            'summary' => "Wrote #{File.basename(path)} (#{product}, #{File.size(path)} bytes)."
        }
    end
    private_class_method :na_export_dxf
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Assets (What the Dropdowns and Finish Cards Offer)
# -----------------------------------------------------------------------------

    # FUNCTION | Asset Keys and Finishes by Kind
    # ------------------------------------------------------------
    # kind: handles, architraves, hinges, cabinet_handles, cabinet_legs,
    # sash_horns, window_boards, finishes, edge_colours (all when omitted).
    def self.na_assets(params)
        kinds = Array(params['kind'] || params['kinds']).map(&:to_s)
        all = kinds.empty?
        out = {}
        if all || kinds.include?('handles')
            out['handles'] = na_list_handles['handles']
        end
        if all || kinds.include?('architraves') || kinds.include?('hinges')
            na_require_modules_for('interior_door')
            library = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__AssetLibrary
            out['architraves'] = na_asset_keys(library.na_list_assets(:architraves)) if all || kinds.include?('architraves')
            out['hinges'] = na_asset_keys(library.na_list_assets(:hinges)) if all || kinds.include?('hinges')
        end
        if all || kinds.include?('cabinet_handles') || kinds.include?('cabinet_legs')
            na_require_modules_for('cabinet')
            library = Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__AssetLibrary
            out['cabinet_handles'] = na_asset_keys(library.na_list(:handles)) if all || kinds.include?('cabinet_handles')
            out['cabinet_legs'] = na_asset_keys(library.na_list(:legs)) if all || kinds.include?('cabinet_legs')
        end
        out['sash_horns'] = na_numbered_assets(:Na__SashHornBuilder) if all || kinds.include?('sash_horns')
        out['window_boards'] = na_numbered_assets(:Na__WindowBoardBuilder) if all || kinds.include?('window_boards')
        out['finishes'] = na_finish_swatches if all || kinds.include?('finishes')
        out['edge_colours'] = na_edge_colour_swatches if all || kinds.include?('edge_colours')
        {
            'assets'  => out,
            'summary' => out.map { |kind, rows| "#{rows.is_a?(Hash) ? rows.values.sum { |list| Array(list).length } : Array(rows).length} #{kind.tr('_', ' ')}" }.join(', ') + '.'
        }
    end
    private_class_method :na_assets
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Keys (and Names When Known) From an Asset List
    # ------------------------------------------------------------
    def self.na_asset_keys(list)
        Array(list).map do |item|
            case item
            when Hash then { 'key' => (item['key'] || item[:key]).to_s, 'name' => (item['name'] || item[:name] || item['label'] || item[:label]).to_s }
            else { 'key' => item.to_s }
            end
        end
    end
    private_class_method :na_asset_keys
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Sash Horns / Window Boards (Numbered Types)
    # ------------------------------------------------------------
    def self.na_numbered_assets(builder_name)
        builder = Na__AssemblyStudio::Na__WindowSystem.const_get(builder_name)
        assets = builder.na_load_all_assets
        rows = assets.is_a?(Hash) ? assets.map { |type, data| [type, data] } : Array(assets).each_with_index.map { |data, index| [index + 1, data] }
        rows.map do |type, data|
            name = data.is_a?(Hash) ? (data['name'] || data['Na__Asset__Name'] || data.dig('meta', 'name')).to_s : ''
            { 'type' => type, 'name' => name }
        end
    rescue StandardError => error
        [{ 'error' => error.message }]
    end
    private_class_method :na_numbered_assets
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Frame and Handle Finish Swatches (as the Cards Show)
    # ------------------------------------------------------------
    def self.na_finish_swatches
        na_ensure_materials
        swatches = Na__AssemblyStudio::Na__AppData::Na__FrameFinishSwatches
        {
            'frame'           => na_swatch_rows(swatches.na_get_swatches(:frame_finish)),
            'frame_default'   => swatches.na_default_key(:frame_finish),
            'handle'          => na_swatch_rows(swatches.na_get_swatches(:handle_finish)),
            'handle_default'  => swatches.na_default_key(:handle_finish),
            'used_by'         => 'frame_material_id, single_door_leaf_material_id, double_door_leaf_material_id (frame); ' \
                                 'single_door_handle_material_id, double_door_handle_material_id (handle); interior door and cabinet *MaterialId keys'
        }
    rescue StandardError => error
        { 'error' => error.message }
    end
    private_class_method :na_finish_swatches

    def self.na_edge_colour_swatches
        swatches = Na__AssemblyStudio::Na__AppData::Na__EdgeColourSwatches
        {
            'colours'  => na_swatch_rows(swatches.na_get_swatches),
            'defaults' => swatches.na_part_defaults,
            'used_by'  => 'edge_colour_frame_id, edge_colour_casement_id, edge_colour_glazebar_id, edge_colour_leaded_id, edge_colour_fielded_panel_id, edge_colour_window_board_id'
        }
    rescue StandardError => error
        { 'error' => error.message }
    end
    private_class_method :na_edge_colour_swatches

    def self.na_swatch_rows(list)
        Array(list).map do |row|
            row.is_a?(Hash) ? { 'id' => (row[:id] || row['id']).to_s, 'label' => (row[:label] || row['label']).to_s, 'hex' => (row[:hex] || row['hex']).to_s } : { 'id' => row.to_s }
        end
    end
    private_class_method :na_swatch_rows

# endregion -------------------------------------------------------------------

end # module Na__McpOperations
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
