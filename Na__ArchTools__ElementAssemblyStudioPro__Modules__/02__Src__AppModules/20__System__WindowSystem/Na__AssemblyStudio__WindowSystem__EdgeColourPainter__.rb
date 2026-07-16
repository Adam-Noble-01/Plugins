# frozen_string_literal: true

# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - WINDOW SYSTEM - EDGE COLOUR PAINTER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__WindowSystem__EdgeColourPainter__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__WindowSystem
# MODULE     : Na__EdgeColourPainter
# AUTHOR     : Noble Architecture
# PURPOSE    : Final post-build / post-fuse pass that paints assembly edges
#              from config edge_colour_*_id keys for TrueVision hierarchy.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../02__AppData/Na__AssemblyStudio__AppData__EdgeColourManager__'

module Na__AssemblyStudio
module Na__WindowSystem
    module Na__EdgeColourPainter

        DebugTools        = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        EdgeColourManager = Na__AssemblyStudio::Na__AppData::Na__EdgeColourManager

        # Glass always uses Dark Grey — not exposed in Edge Colours UI.
        NA_GLASS_EDGE_COLOUR_ID = EdgeColourManager::NA_DEFAULT_DARK_GREY_KEY

        NA_DEFAULT_PART_IDS = {
            'frame'         => 'MTE102__LineColour__SoftBlack__L20',
            'casement'      => 'MTE103__LineColour__DarkGrey__L40',
            'glazebar'      => 'MTE103__LineColour__DarkGrey__L40',
            'leaded'        => 'MTE104__LineColour__MidGrey__L60',
            'fielded_panel' => 'MTE103__LineColour__DarkGrey__L40',
            'glass'         => NA_GLASS_EDGE_COLOUR_ID
        }.freeze

        NA_CONFIG_KEYS = {
            'frame'         => 'edge_colour_frame_id',
            'casement'      => 'edge_colour_casement_id',
            'glazebar'      => 'edge_colour_glazebar_id',
            'leaded'        => 'edge_colour_leaded_id',
            'fielded_panel' => 'edge_colour_fielded_panel_id'
        }.freeze

        # FUNCTION | Apply Assembly Edge Colours After Create / Fuse
        # ------------------------------------------------------------
        # @param entities [Sketchup::Entities]
        # @param config   [Hash] windowConfiguration / door config
        # @return [Integer] groups painted
        def self.na_apply_assembly_edge_colours(entities, config)
            return 0 unless entities
            return 0 unless config.is_a?(Hash)

            part_ids = na_resolve_part_ids(config)
            painted = 0

            na_each_named_group(entities) do |group|
                part = na_part_for_group_name(group.name.to_s)
                next unless part

                mte_id = part_ids[part]
                next unless mte_id

                EdgeColourManager.na_apply_or_clear_edge_colour_on_group(group, mte_id)
                painted += 1
            end

            DebugTools.na_debug_geometry("EdgeColourPainter: painted #{painted} groups")
            painted
        rescue StandardError => e
            DebugTools.na_debug_error('EdgeColourPainter: apply failed', e)
            0
        end
        # ---------------------------------------------------------------

        # FUNCTION | Resolve Part MTE Ids From Config (With Defaults)
        # ------------------------------------------------------------
        def self.na_resolve_part_ids(config)
            ids = NA_CONFIG_KEYS.each_with_object({}) do |(part, key), memo|
                raw = config[key] || config[key.to_sym]
                raw = NA_DEFAULT_PART_IDS[part] if raw.nil? || raw.to_s.empty?
                memo[part] = raw.to_s
            end
            ids['glass'] = NA_GLASS_EDGE_COLOUR_ID
            ids
        end
        private_class_method :na_resolve_part_ids
        # ---------------------------------------------------------------

        # HELPER | Map Group Name To Edge-Colour Part Key
        # ------------------------------------------------------------
        def self.na_part_for_group_name(name)
            return nil if name.nil? || name.empty?

            return 'leaded' if name.start_with?('Na_LeadedGlass_') || name.include?('LeadedGlass')
            return 'glass' if name.start_with?('Na_Glass_') ||
                              name.end_with?('__Glass') ||
                              name.include?('__Glass__')
            return 'glazebar' if name.start_with?('Na_GlazeBar_') || name.include?('GlazeBar')
            return 'fielded_panel' if name.include?('PanelLinework') ||
                                       name.include?('PanelGeometry') ||
                                       name.match?(/__Field__\d{3}/)
            return 'casement' if name.start_with?('Na_Casement_') ||
                                   name.include?('LeafJoinery') ||
                                   name.match?(/__Leaf\d{3}__(?:Stile|Rail|Field)/) ||
                                   name.start_with?('Na_DoorPanel_')
            return 'frame' if name.start_with?('Na_Frame_') ||
                                name.start_with?('Na_Mullion_') ||
                                name.start_with?('Na_Transom_')

            nil
        end
        private_class_method :na_part_for_group_name
        # ---------------------------------------------------------------

        # HELPER | Yield Every Named Group / Component Instance Recursively
        # ------------------------------------------------------------
        def self.na_each_named_group(entities, &block)
            return unless entities && block

            entities.each do |entity|
                case entity
                when Sketchup::Group
                    block.call(entity) if entity.name && !entity.name.empty?
                    na_each_named_group(entity.entities, &block) if entity.valid?
                when Sketchup::ComponentInstance
                    block.call(entity) if entity.name && !entity.name.empty?
                    if entity.valid? && entity.definition
                        na_each_named_group(entity.definition.entities, &block)
                    end
                end
            end
        end
        private_class_method :na_each_named_group
        # ---------------------------------------------------------------

    end # module Na__EdgeColourPainter
end # module Na__WindowSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
