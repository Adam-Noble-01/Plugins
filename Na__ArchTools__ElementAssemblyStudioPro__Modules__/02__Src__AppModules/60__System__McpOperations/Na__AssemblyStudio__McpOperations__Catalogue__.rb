# frozen_string_literal: true

# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - MCP OPERATIONS - CATALOGUE, PRODUCTS, VALUES
# =============================================================================
#
# FILE       : Na__AssemblyStudio__McpOperations__Catalogue__.rb
# NAMESPACE  : Na__AssemblyStudio
# MODULE     : Na__McpOperations
# AUTHOR     : Noble Architecture
# CREATED    : 11-Nov-2026 (V2.6.0)
# PURPOSE    : What every setting means, what each product starts from, and
#              which values are allowed, for agents.
#
# THE ONE SOURCE
#   02__AppData/Na__AssemblyStudio__ParameterCatalogue__.json is generated
#   from the dialog's own control files by
#   65__Dev__DevTools/Na__AssemblyStudio__DevTools__ParameterCatalogue__.js
#   (label, unit, type, range, step, default, options, section, what it
#   needs). Nothing here retypes a range: a value outside the dialog's range
#   is REFUSED, never clamped.
#
# PRODUCTS (the 'type' an agent passes)
#   casement, sash, single, double, bifold, sliding   windows and exterior doors (one flat config)
#   interior_door                                     interior doors (Na__DoorConfig__ keys)
#   base, drawers, wall, tall, wardrobe               cabinets (Na__CabinetConfig__ keys)
#   Door and cabinet keys may be given without their prefix.
#
# WHAT A NEW ELEMENT STARTS FROM (what the dialog would send)
#   window family  control defaults, then the Ruby defaults over them, then the
#                  product switch the product strip makes (MainUiLogic
#                  na_applyProductModeChange: sash rails, door sizes, 'EQ').
#   interior door  the dialog's own starting config (control defaults + its
#                  material ids), NOT the Ruby NA_DEFAULT_DOOR_CONFIG.
#   cabinet        the Ruby defaults with control defaults filling gaps, then
#                  the product switch (LayoutMap na_select_product).
#   A preset or a placed element is laid over the control defaults, as the
#   dialog does when it applies a preset or loads a selection.
#
# =============================================================================

require 'json'

module Na__AssemblyStudio
module Na__McpOperations

# -----------------------------------------------------------------------------
# REGION | Catalogue - Constants
# -----------------------------------------------------------------------------

    NA_CATALOGUE_FILE = File.expand_path('../02__AppData/Na__AssemblyStudio__ParameterCatalogue__.json', __dir__)

    # The product strip of each tab, keyed as agents pass it.
    NA_PRODUCTS = {
        'casement'      => { 'system' => 'window_family', 'family' => 'Window',       'type' => 'Casement',     'category' => 'Window',        'mode' => nil },
        'sash'          => { 'system' => 'window_family', 'family' => 'Window',       'type' => 'SlidingSash',  'category' => 'Window',        'mode' => 'sliding_sash_window' },
        'single'        => { 'system' => 'window_family', 'family' => 'ExteriorDoor', 'type' => 'Single',       'category' => 'ExteriorDoors', 'mode' => 'ext_single_door_mode' },
        'double'        => { 'system' => 'window_family', 'family' => 'ExteriorDoor', 'type' => 'Double',       'category' => 'ExteriorDoors', 'mode' => 'double_door_mode' },
        'bifold'        => { 'system' => 'window_family', 'family' => 'ExteriorDoor', 'type' => 'MultiFold',    'category' => 'ExteriorDoors', 'mode' => 'multifold_mode' },
        'sliding'       => { 'system' => 'window_family', 'family' => 'ExteriorDoor', 'type' => 'Sliding',      'category' => 'ExteriorDoors', 'mode' => 'sliding_mode' },
        'interior_door' => { 'system' => 'interior_door', 'family' => 'InteriorDoor', 'type' => 'InteriorDoor' },
        'base'          => { 'system' => 'cabinet',       'family' => 'Cabinet',      'type' => 'Base' },
        'drawers'       => { 'system' => 'cabinet',       'family' => 'Cabinet',      'type' => 'Drawers' },
        'wall'          => { 'system' => 'cabinet',       'family' => 'Cabinet',      'type' => 'Wall' },
        'tall'          => { 'system' => 'cabinet',       'family' => 'Cabinet',      'type' => 'Tall' },
        'wardrobe'      => { 'system' => 'cabinet',       'family' => 'Cabinet',      'type' => 'Wardrobe' }
    }.freeze

    NA_SYSTEM_LABELS = {
        'window_family' => 'windows and exterior doors',
        'interior_door' => 'interior doors',
        'cabinet'       => 'cabinets'
    }.freeze

    # Flags the product strip writes; agents choose a product with 'type'.
    NA_MODE_FLAGS     = %w[door_mode ext_single_door_mode sliding_mode multifold_mode double_door_mode sliding_sash_window].freeze
    NA_PRODUCT_FIELDS = (NA_MODE_FLAGS + %w[ui_element_category ui_window_type ui_exterior_door_type]).freeze

    NA_KEY_PREFIX = { 'interior_door' => 'Na__DoorConfig__', 'cabinet' => 'Na__CabinetConfig__' }.freeze

    # The config block inside each system's payload.
    NA_CONFIG_BLOCK = {
        'window_family' => 'windowConfiguration',
        'interior_door' => 'Na__DoorConfiguration',
        'cabinet'       => 'Na__CabinetConfiguration'
    }.freeze

    # Overall size keys (kept when a preset is re-applied to a placed element).
    NA_SIZE_KEYS = {
        'window_family' => %w[width_mm height_mm],
        'interior_door' => %w[Na__DoorConfig__OpeningWidth_mm Na__DoorConfig__OpeningHeight_mm Na__DoorConfig__WallDepth_mm],
        'cabinet'       => %w[Na__CabinetConfig__Width_mm]
    }.freeze

    # MainUiLogic na_applySlidingSashCasementDefaults (WindowSystem, L539):
    # what switching the product strip to Sliding Sash sets.
    NA_SASH_SWITCH_VALUES = {
        'casement_sizes_individual'      => true,
        'casement_top_rail_mm'           => 60,
        'casement_bottom_rail_mm'        => 70,
        'sliding_sash_overlap_mm'        => 40,
        'top_sash_bottom_rail_mm'        => 60,
        'bottom_sash_top_rail_override'  => false,
        'bottom_sash_top_rail_mm'        => 60,
        'meeting_rail_position_override' => false,
        'meeting_rail_offset_mm'         => 0,
        'casement_left_stile_mm'         => 40,
        'casement_right_stile_mm'        => 40
    }.freeze

    # MainUiLogic na_applyDoorModeDefaultDimensions (L1932): [width, height].
    NA_DOOR_SWITCH_SIZES = {
        'single'  => [1000, 2100],
        'double'  => [1800, 2100],
        'bifold'  => [3000, 2100],
        'sliding' => [3000, 2100]
    }.freeze

    # MainUiLogic na_applyWidthSliderRange (L1903): Width widens to 8000 for
    # the multi-leaf door sets, 4000 otherwise.
    NA_WIDE_PRODUCTS  = %w[double bifold sliding].freeze
    NA_WIDE_WIDTH_MAX = 8000

    # What an agent must know about a setting that its control does not say.
    NA_TRANSOM_NOTE = 'Given and stored from the BOTTOM of the clear frame opening to the underside of the transom; ' \
                      'the dialog box shows it from the top. Setting transoms from 0 to 1 seeds transom 1 as the dialog does.'
    NA_PARAMETER_NOTES = {
        'transom_1_y_mm'                   => NA_TRANSOM_NOTE,
        'transom_2_y_mm'                   => NA_TRANSOM_NOTE,
        'transom_3_y_mm'                   => NA_TRANSOM_NOTE,
        'double_door_active_leaf_width_mm' => "'EQ' for equal leaves, or the active leaf's width in mm (both leaves at least 300).",
        'casement_overrides'               => 'Per Casement Settings: an object keyed "opening:cell:panel" (e.g. "0:0:0"), each holding the fields in the catalogue pattern (left_stile_mm, ...).',
        'removed_casements'                => 'Casements clicked off in the preview: a list of "opening:cell:panel" keys.'
    }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Catalogue - Loading
# -----------------------------------------------------------------------------

    # FUNCTION | The Parameter Catalogue (Re-Read When the File Changes)
    # ------------------------------------------------------------
    def self.na_catalogue
        mtime = File.exist?(NA_CATALOGUE_FILE) ? File.mtime(NA_CATALOGUE_FILE) : nil
        unless mtime
            na_refuse('not_found', "The parameter catalogue is missing: #{NA_CATALOGUE_FILE}.",
                      'Run node 65__Dev__DevTools/Na__AssemblyStudio__DevTools__ParameterCatalogue__.js, then try again.')
        end
        return @na_catalogue if @na_catalogue && @na_catalogue_mtime == mtime

        @na_catalogue = JSON.parse(File.read(NA_CATALOGUE_FILE, encoding: 'UTF-8'))
        @na_catalogue_mtime = mtime
        @na_catalogue
    end
    # ---------------------------------------------------------------

    def self.na_system_catalogue(system)
        na_catalogue.fetch('systems', {})[system] || {}
    end
    private_class_method :na_system_catalogue

    def self.na_controls(system)
        na_system_catalogue(system)['controls'] || {}
    end
    private_class_method :na_controls

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Products
# -----------------------------------------------------------------------------

    # FUNCTION | The Product an Agent Named, or a Refusal Listing Them
    # ------------------------------------------------------------
    # @return [Array(String, Hash)] [product key, product row]
    def self.na_product(key)
        wanted = key.to_s.strip.downcase.tr(' -', '__')
        wanted = 'interior_door' if %w[interior interiordoor door_interior].include?(wanted)
        wanted = 'sash' if %w[sliding_sash slidingsash].include?(wanted)
        wanted = 'bifold' if %w[multifold folding].include?(wanted)
        product = NA_PRODUCTS[wanted]
        return [wanted, product] if product

        na_refuse('invalid_params', "Unknown type '#{key}'.", "Use one of: #{NA_PRODUCTS.keys.join(', ')}.")
    end
    # ---------------------------------------------------------------

    # FUNCTION | Which Product a Set of Values Builds
    # ------------------------------------------------------------
    # Window family: the LayoutMap's na_active_product (first true flag).
    # Cabinets: the cabinet LayoutMap's na_active_product.
    def self.na_product_of_values(system, values)
        case system
        when 'window_family'
            return 'double'  if values['double_door_mode'] == true
            return 'single'  if values['ext_single_door_mode'] == true
            return 'bifold'  if values['multifold_mode'] == true
            return 'sliding' if values['sliding_mode'] == true
            return 'sash'    if values['sliding_sash_window'] == true

            'casement'
        when 'cabinet'
            type = values['Na__CabinetConfig__UnitType'].to_s
            return 'wall' if type == 'Wall'
            return (values['Na__CabinetConfig__TowerInterior'] == 'Hanging' ? 'wardrobe' : 'tall') if type == 'Tower'

            values['Na__CabinetConfig__BaseFrontLayout'] == 'Drawers' ? 'drawers' : 'base'
        else
            'interior_door'
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Set the Mode Flags and Product Keys for a Window-Family Product
    # ------------------------------------------------------------
    # MainUiLogic na_setProduct + na_syncModeFlagsFromHierarchy: exactly one
    # flag true (none for a casement), door_mode always false.
    def self.na_apply_product_flags!(values, product_key)
        product = NA_PRODUCTS.fetch(product_key)
        NA_MODE_FLAGS.each { |flag| values[flag] = false }
        values[product['mode']] = true if product['mode']
        values['ui_element_category'] = product['category']
        if product['category'] == 'ExteriorDoors'
            values['ui_exterior_door_type'] = product['type']
        else
            values['ui_window_type'] = product['type']
        end
        values
    end
    # ---------------------------------------------------------------

    # FUNCTION | What the Product Strip Does When It Switches From a Casement
    # ------------------------------------------------------------
    # MainUiLogic na_applyProductModeChange: Sliding Sash sets the sash rails;
    # a door sets its standard size (and 'EQ' leaves for a double). Moving
    # between two door types also carries shared settings across in the
    # dialog; a new element here always starts from the casement defaults,
    # so that step has nothing to carry.
    def self.na_switch_window_product!(values, product_key)
        na_apply_product_flags!(values, product_key)
        if product_key == 'sash'
            values.merge!(NA_SASH_SWITCH_VALUES)
        elsif NA_DOOR_SWITCH_SIZES.key?(product_key)
            values['width_mm'], values['height_mm'] = NA_DOOR_SWITCH_SIZES[product_key]
            values['double_door_active_leaf_width_mm'] = 'EQ' if product_key == 'double'
        end
        values
    end
    # ---------------------------------------------------------------

    # FUNCTION | What the Cabinet Product Strip Sets
    # ------------------------------------------------------------
    # Cabinetry LayoutMap na_select_product, from the defaults.
    def self.na_switch_cabinet_product!(block, product_key)
        k = NA_KEY_PREFIX['cabinet']
        defaults = na_system_catalogue('cabinet')['product_defaults'] || {}
        case product_key
        when 'base', 'drawers'
            block[k + 'UnitType'] = 'Base'
            if product_key == 'drawers'
                block[k + 'BaseFrontLayout'] = 'Drawers'
            elsif block[k + 'BaseFrontLayout'] == 'Drawers'
                block[k + 'BaseFrontLayout'] = 'Doors'
            end
        when 'wall'
            block[k + 'UnitType'] = 'Wall'
        else
            block[k + 'UnitType']      = 'Tower'
            block[k + 'TowerInterior'] = product_key == 'wardrobe' ? 'Hanging' : 'Shelves'
        end
        (defaults[product_key] || {}).each { |key, value| block[key] = value }
        block
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Starting Payloads
# -----------------------------------------------------------------------------

    # FUNCTION | Load a System's Lazy Modules
    # ------------------------------------------------------------
    def self.na_require_modules_for(system)
        case system
        when 'window_family'
            Na__AssemblyStudio::Na__ExteriorSingleDoorSystem.na_require_modules
            Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem.na_require_modules
            Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem.na_require_sliding_modules
            Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem.na_require_bifold_modules
        when 'interior_door'
            Na__AssemblyStudio::Na__InteriorDoorSystem.na_require_door_modules
        when 'cabinet'
            Na__AssemblyStudio::Na__InteriorCabinetrySystem.na_require_modules
        end
    end
    private_class_method :na_require_modules_for
    # ---------------------------------------------------------------

    # FUNCTION | The Payload a New Element of One Product Starts From
    # ------------------------------------------------------------
    # @return [Hash] the full payload (metadata, components, configuration)
    def self.na_fresh_root(product_key)
        system = NA_PRODUCTS.fetch(product_key)['system']
        na_require_modules_for(system)
        defaults = na_deep_copy(na_system_catalogue(system)['dialog_defaults'] || {})
        case system
        when 'window_family'
            root = na_deep_copy(Na__AssemblyStudio::Na__WindowSystem::Na__Defaults.na_default_config)
            values = defaults.merge(root['windowConfiguration'] || {})
            na_switch_window_product!(values, product_key)
            root['windowConfiguration'] = values
            root
        when 'interior_door'
            root = na_deep_copy(Na__AssemblyStudio::Na__InteriorDoorSystem.na_default_door_config)
            root['Na__DoorConfiguration'] = defaults
            root
        else
            root = na_deep_copy(Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__Defaults.na_default_config)
            block = defaults.merge(root['Na__CabinetConfiguration'] || {})
            na_switch_cabinet_product!(block, product_key)
            root['Na__CabinetConfiguration'] = block
            root
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Preset's or a Placed Element's Values Over the Dialog's Defaults
    # ------------------------------------------------------------
    # As the dialog applies a preset or loads a selection: every control
    # default first, then the stored values on top.
    def self.na_over_dialog_defaults(system, values)
        na_deep_copy(na_system_catalogue(system)['dialog_defaults'] || {}).merge(na_deep_copy(values || {}))
    end
    private_class_method :na_over_dialog_defaults
    # ---------------------------------------------------------------

    # FUNCTION | A Fresh Payload Carrying Given Config Values
    # ------------------------------------------------------------
    def self.na_root_with_values(product_key, values)
        system = NA_PRODUCTS.fetch(product_key)['system']
        root = na_fresh_root(product_key)
        root[NA_CONFIG_BLOCK[system]] = values
        root
    end
    private_class_method :na_root_with_values
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Values - Checking (Refuse, Never Clamp)
# -----------------------------------------------------------------------------

    # FUNCTION | The Stored Key for a Key an Agent Wrote
    # ------------------------------------------------------------
    # Door and cabinet keys may come without their prefix.
    def self.na_full_key(system, key)
        key = key.to_s.strip
        prefix = NA_KEY_PREFIX[system]
        return key if prefix.nil? || key.start_with?(prefix)

        prefix + key
    end
    private_class_method :na_full_key
    # ---------------------------------------------------------------

    # FUNCTION | Check an Agent's Values Against the Dialog's Own Rules
    # ------------------------------------------------------------
    # Unknown keys, wrong types, values outside the dialog's range and
    # options it does not offer are all refused together, naming each.
    # @param base [Hash] the values the overrides land on (for keys the
    #     dialog has no control for: removal lists, per-casement overrides)
    # @return [Array(Hash, Array<String>)] [checked values (full keys), warnings]
    def self.na_check_values(system, product_key, base, overrides)
        return [{}, []] if overrides.nil? || overrides.empty?

        unless overrides.is_a?(Hash)
            na_refuse('invalid_params', 'values must be an object of setting keys and values.', 'e.g. {"width_mm": 1200, "mullions": 1}.')
        end

        controls = na_controls(system)
        defaults = na_system_catalogue(system)['dialog_defaults'] || {}
        known    = controls.keys | defaults.keys | base.keys
        problems = []
        warnings = []
        checked  = {}
        overrides.each do |raw_key, value|
            key = na_full_key(system, raw_key)
            if system == 'window_family' && NA_PRODUCT_FIELDS.include?(key)
                problems << "#{key}: the product is chosen with type (#{NA_PRODUCTS.select { |_k, row| row['system'] == 'window_family' }.keys.join(', ')}), not with this flag"
                next
            end
            unless known.include?(key)
                problems << "#{raw_key}: not a setting of #{NA_SYSTEM_LABELS[system]}#{na_suggest(key, known)}"
                next
            end

            control = controls[key]
            reason = control ? na_check_control(control, key, value, product_key) : na_check_like(base.key?(key) ? base[key] : defaults[key], value)
            if reason
                problems << "#{key}: #{reason}"
                next
            end

            products = control && control['products']
            if products.is_a?(Array) && !products.empty? && !products.include?(na_layout_product(system, product_key, base.merge(checked)))
                warnings << "#{key} is a #{products.join('/')} setting: it changes nothing on a #{product_key.tr('_', ' ')}."
            end
            checked[key] = value
        end

        unless problems.empty?
            na_refuse('invalid_params',
                      "#{problems.length} value#{problems.length == 1 ? '' : 's'} refused (nothing changed): #{problems.first(5).join(' | ')}" \
                      "#{problems.length > 5 ? " | and #{problems.length - 5} more" : ''}",
                      'Ranges, options and meanings: entity_studio parameters with type and keys. Out-of-range values are refused, never clamped.',
                      { 'problems' => problems })
        end
        [checked, warnings]
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | One Value Against Its Control
    # ------------------------------------------------------------
    # @return [String, nil] why it is refused, or nil
    def self.na_check_control(control, key, value, product_key)
        case control['type'].to_s
        when 'slider', 'number', 'range', 'stepper'
            min, max = na_range(control, key, product_key)
            return "must be a number#{na_range_text(min, max, control['unit'])}" unless value.is_a?(Numeric)
            return "#{value} is outside#{na_range_text(min, max, control['unit'])}" if (min && value < min) || (max && value > max)

            nil
        when 'eq_number'
            return nil if value.to_s.strip.casecmp?('EQ')

            value.is_a?(Numeric) ? nil : "must be a width in mm or 'EQ' (equal leaves)"
        when 'toggle', 'checkbox', 'switchgroup'
            [true, false].include?(value) ? nil : 'must be true or false'
        when 'expandable'
            control.key?('default') ? na_check_like(control['default'], value) : ([true, false].include?(value) ? nil : 'must be true or false')
        when 'select', 'binary_toggle', 'multiway_toggle'
            options = na_option_values(control)
            options = na_runtime_options(key) if options.empty?
            return na_check_like(control['default'], value) if options.nil? || options.empty?
            return nil if options.include?(value)

            "#{value.inspect} is not offered: #{options.first(12).map(&:inspect).join(', ')}#{options.length > 12 ? " and #{options.length - 12} more (entity_studio assets)" : ''}"
        when 'material_cards'
            value.is_a?(String) && !value.strip.empty? ? nil : 'must be a material id (entity_studio assets kind: finishes)'
        else
            na_check_like(control['default'], value)
        end
    end
    private_class_method :na_check_control
    # ---------------------------------------------------------------

    # HELPER FUNCTION | A Value Must Be the Same Kind as Its Reference
    # ------------------------------------------------------------
    def self.na_check_like(reference, value)
        case reference
        when nil then nil
        when Numeric then value.is_a?(Numeric) ? nil : 'must be a number'
        when true, false then [true, false].include?(value) ? nil : 'must be true or false'
        when String then value.is_a?(String) ? nil : 'must be text'
        when Array then value.is_a?(Array) ? nil : 'must be a list'
        when Hash then value.is_a?(Hash) ? nil : 'must be an object'
        end
    end
    private_class_method :na_check_like
    # ---------------------------------------------------------------

    # HELPER FUNCTION | A Control's Range for One Product
    # ------------------------------------------------------------
    def self.na_range(control, key, product_key)
        min = control['min']
        max = control['max']
        max = NA_WIDE_WIDTH_MAX if key == 'width_mm' && NA_WIDE_PRODUCTS.include?(product_key)
        [min, max]
    end
    private_class_method :na_range
    # ---------------------------------------------------------------

    def self.na_range_text(min, max, unit)
        return '' unless min || max

        unit = unit.to_s.empty? ? '' : " #{unit}"
        " #{min.nil? ? '...' : min} to #{max.nil? ? '...' : max}#{unit}"
    end
    private_class_method :na_range_text

    # HELPER FUNCTION | Options the Dialog Fills From Ruby at Runtime
    # ------------------------------------------------------------
    # Asset dropdowns are empty in the control files: the dialog fills them
    # from the asset libraries, so the same lists are read here.
    # @return [Array<String>, nil] nil when the key has no runtime list
    def self.na_runtime_options(key)
        case key
        when 'Na__DoorConfig__HandleAssetKey'
            na_handle_keys('interior') + na_handle_keys('exterior')
        when /\A(single|double)_door_handle_asset_key\z/
            na_handle_keys('exterior')
        when 'Na__DoorConfig__ArchitraveProfileKey'
            na_require_modules_for('interior_door')
            Array(Na__AssemblyStudio::Na__InteriorDoorSystem::Na__AssetLibrary.na_list_assets(:architraves))
        when 'Na__CabinetConfig__LegAssetKey'
            na_require_modules_for('cabinet')
            Array(Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__AssetLibrary.na_list(:legs))
        end
    rescue StandardError
        nil
    end
    private_class_method :na_runtime_options

    def self.na_handle_keys(kind)
        Dir.glob(File.join(NA_ASSET_LIBRARY, NA_HANDLE_FOLDERS.fetch(kind), '*.json'))
           .map { |path| File.basename(path, '.json').sub(/__\z/, '') }
           .reject { |key| key.start_with?('_') }
    end
    private_class_method :na_handle_keys
    # ---------------------------------------------------------------

    # HELPER FUNCTION | The Values a Select Offers
    # ------------------------------------------------------------
    def self.na_option_values(control)
        Array(control['options']).map { |option| option.is_a?(Hash) ? option['value'] : option }.compact
    end
    private_class_method :na_option_values
    # ---------------------------------------------------------------

    # HELPER FUNCTION | The Layout's Product Key for a Product (Per System)
    # ------------------------------------------------------------
    # Interior door controls are tagged single / double (DoorType).
    def self.na_layout_product(system, product_key, values)
        return values['Na__DoorConfig__DoorType'].to_s.downcase if system == 'interior_door'

        product_key
    end
    private_class_method :na_layout_product
    # ---------------------------------------------------------------

    # HELPER FUNCTION | " (did you mean ...?)" for a Mistyped Key
    # ------------------------------------------------------------
    def self.na_suggest(key, known)
        wanted = key.downcase
        tokens = wanted.split(/_+/).reject { |token| token.length < 3 || token == 'mm' || token.start_with?('na') }
        scored = known.map do |candidate|
            text = candidate.downcase
            shared = tokens.count { |token| text.include?(token) }
            [candidate, na_levenshtein(wanted, text) - shared * 4]
        end
        best = scored.sort_by { |row| row[1] }.first(3).map(&:first)
        best.empty? ? '' : " (did you mean #{best.join(', ')}?)"
    end
    private_class_method :na_suggest
    # ---------------------------------------------------------------

    def self.na_levenshtein(a, b)
        previous = (0..b.length).to_a
        a.each_char.with_index(1) do |char_a, i|
            current = [i]
            b.each_char.with_index(1) do |char_b, j|
                current << [previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (char_a == char_b ? 0 : 1)].min
            end
            previous = current
        end
        previous.last
    end
    private_class_method :na_levenshtein

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Read Action - parameters
# -----------------------------------------------------------------------------

    # FUNCTION | What Each Setting Means, Its Range and Its Starting Value
    # ------------------------------------------------------------
    # With no filter: the sections of the product's tab, with their keys.
    # With query / section / keys: the matching settings in full.
    def self.na_parameters(params)
        product_key, product = na_product(params['type'] || 'casement')
        system   = product['system']
        catalogue = na_system_catalogue(system)
        controls = catalogue['controls'] || {}
        start    = na_fresh_root(product_key)[NA_CONFIG_BLOCK[system]] || {}
        layout   = na_layout_product(system, product_key, start)

        applies = lambda do |row|
            list = row['products']
            !list.is_a?(Array) || list.empty? || list.include?(layout)
        end

        keys    = Array(params['keys']).map { |key| na_full_key(system, key) }
        query   = params['query'].to_s.strip.downcase
        section = params['section'].to_s.strip.downcase
        filtered = !(keys.empty? && query.empty? && section.empty?)

        unless filtered
            sections = (catalogue['sections'] || []).filter_map do |row|
                ids = Array(row['items']).select { |id| controls[id] && applies.call(controls[id]) }
                next nil if ids.empty?

                { 'section' => row['key'], 'title' => row['title'], 'count' => ids.length, 'keys' => ids }
            end
            return {
                'type'     => product_key,
                'system'   => system,
                'sections' => sections,
                'products' => NA_PRODUCTS.select { |_key, row| row['system'] == system }.keys,
                'summary'  => "#{product_key}: #{sections.sum { |row| row['count'] }} settings in #{sections.length} sections. " \
                              'Pass query, section or keys for ranges, options, meanings and starting values.'
            }
        end

        words = query.split(/\s+/)
        rows = controls.select do |id, row|
            next false unless applies.call(row) || keys.include?(id)
            next keys.include?(id) unless keys.empty?
            next false unless section.empty? || row['section'].to_s.downcase == section
            next true if words.empty?

            haystack = [id.tr('_', ' '), row['label'], row['keywords'], row['section_title'], row['group'], row['needs']].join(' ').downcase
            words.all? { |word| haystack.include?(word) }
        end
        missing = keys - rows.keys
        limit = (params['limit'] || 60).to_i.clamp(1, 400)
        listed = rows.first(limit).map { |id, row| na_parameter_row(id, row, product_key, start) }
        missing.each do |key|
            next unless start.key?(key)

            listed << { 'key' => key, 'value' => start[key], 'note' => 'Stored with the element but has no control in the dialog.' }
        end
        {
            'type'       => product_key,
            'system'     => system,
            'count'      => rows.length,
            'parameters' => listed,
            'unknown'    => missing.reject { |key| start.key?(key) },
            'summary'    => "#{rows.length} #{product_key} setting#{rows.length == 1 ? '' : 's'}#{rows.length > limit ? " (first #{limit} shown)" : ''}."
        }
    end
    private_class_method :na_parameters
    # ---------------------------------------------------------------

    # HELPER FUNCTION | One Setting, as an Agent Needs It
    # ------------------------------------------------------------
    def self.na_parameter_row(id, row, product_key, start)
        min, max = na_range(row, id, product_key)
        options = row['options']
        if (options.nil? || Array(options).empty?) && %w[select binary_toggle multiway_toggle].include?(row['type'].to_s)
            runtime = na_runtime_options(id)
            options = runtime.map { |key| { 'value' => key } } if runtime && !runtime.empty?
        end
        out = {
            'key'     => id,
            'label'   => row['label'],
            'type'    => row['type'],
            'unit'    => row['unit'].to_s.empty? ? nil : row['unit'],
            'min'     => min,
            'max'     => max,
            'step'    => row['step'],
            'start'   => start.key?(id) ? start[id] : row['default'],
            'options' => options,
            'section' => row['section'],
            'tier'    => row['tier'],
            'needs'   => row['needs'],
            'parent'  => row['parent'],
            'products' => row['products'],
            'options_from' => row['options_from'],
            'note'    => NA_PARAMETER_NOTES[id]
        }
        out.compact
    end
    private_class_method :na_parameter_row
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__McpOperations
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
