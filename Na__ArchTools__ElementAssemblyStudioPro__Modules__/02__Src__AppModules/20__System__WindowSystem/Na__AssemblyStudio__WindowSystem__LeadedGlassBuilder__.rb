# frozen_string_literal: true

# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - WINDOW SYSTEM - LEADED GLASS BUILDER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__WindowSystem__LeadedGlassBuilder__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__WindowSystem
# MODULE     : Na__LeadedGlassBuilder
# AUTHOR     : Noble Architecture
# PURPOSE    : Build lead came overlay geometry on the outer glass face
#
# DESCRIPTION:
# - Sits on the outer face of the glass (stile/rail inner zone)
# - Does NOT subdivide or trim glass
# - Modes: centre-lines only (edges), flat ribbons (depth 0), extruded (1–5 mm)
# - Colours from DataLib MTE edge materials via EdgeColourManager
# - Reuses glaze-bar spacing math (na_compute_bar_positions)
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../02__AppData/Na__AssemblyStudio__AppData__EdgeColourManager__'
require_relative 'Na__AssemblyStudio__WindowSystem__GeometryBuilders__'
require_relative 'Na__AssemblyStudio__WindowSystem__GeometryHelpers__'

module Na__AssemblyStudio
module Na__WindowSystem
    module Na__LeadedGlassBuilder

# -----------------------------------------------------------------------------
# REGION | Module References & Constants
# -----------------------------------------------------------------------------

        DebugTools        = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        EdgeColourManager = Na__AssemblyStudio::Na__AppData::Na__EdgeColourManager
        GeometryBuilders  = Na__AssemblyStudio::Na__WindowSystem::Na__GeometryBuilders
        GeometryHelpers   = Na__AssemblyStudio::Na__WindowSystem::Na__GeometryHelpers

        NA_LEGACY_COLOUR_MTE_MAP = {
            'mid'   => 'MTE104__LineColour__MidGrey__L60',
            'light' => 'MTE107__LineColour__LightGrey__L85',
            'dark'  => 'MTE103__LineColour__DarkGrey__L40'
        }.freeze

        NA_DEFAULT_MTE_ID = 'MTE104__LineColour__MidGrey__L60'.freeze
        NA_MM_TO_INCH = 1.0 / 25.4

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API — Param Resolution
# -----------------------------------------------------------------------------

        # FUNCTION | Migrate Legacy leaded_colour Mid/Light/Dark → edge_colour_leaded_id
        # ------------------------------------------------------------
        def self.na_migrate_legacy_leaded_colour!(config)
            return config unless config.is_a?(Hash)

            has_edge = config.key?('edge_colour_leaded_id') || config.key?(:edge_colour_leaded_id)
            legacy = config['leaded_colour'] || config[:leaded_colour]
            if !has_edge && legacy
                mapped = NA_LEGACY_COLOUR_MTE_MAP[legacy.to_s]
                config['edge_colour_leaded_id'] = mapped if mapped
            end
            config.delete('leaded_colour')
            config.delete(:leaded_colour)
            config
        end
        # ---------------------------------------------------------------

        # FUNCTION | Resolve Leaded Glass Params From Config Hash
        # ------------------------------------------------------------
        # @param config [Hash] windowConfiguration (string keys, mm values)
        # @return [Hash] typed params (inches where dimensional)
        def self.na_resolve_leaded_params(config)
            return na_disabled_params unless config.is_a?(Hash)

            na_migrate_legacy_leaded_colour!(config)
            enabled = config['leaded_glass_enabled'] == true
            mte_id = (config['edge_colour_leaded_id'] || NA_DEFAULT_MTE_ID).to_s
            mte_id = NA_DEFAULT_MTE_ID if mte_id.empty?

            {
                enabled:       enabled,
                h_bars:        [[(config['horizontal_leaded_bars'] || 0).to_i, 0].max, 8].min,
                v_bars:        [[(config['vertical_leaded_bars'] || 0).to_i, 0].max, 8].min,
                width:         [(config['leaded_width_mm'] || 6).to_f, 2.0].max * NA_MM_TO_INCH,
                depth:         [[(config['leaded_depth_mm'] || 0).to_f, 0.0].max, 5.0].min * NA_MM_TO_INCH,
                centre_lines:  config['leaded_centre_lines_only'] == true,
                mte_id:        mte_id
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Resolve Leaded Params From Already-Parsed Engine Params
        # ------------------------------------------------------------
        def self.na_resolve_leaded_params_from_engine(params)
            return na_disabled_params unless params.is_a?(Hash)

            {
                enabled:       params[:leaded_glass_enabled] == true,
                h_bars:        (params[:horizontal_leaded_bars] || 0).to_i,
                v_bars:        (params[:vertical_leaded_bars] || 0).to_i,
                width:         (params[:leaded_width] || (6.0 * NA_MM_TO_INCH)).to_f,
                depth:         (params[:leaded_depth] || 0).to_f,
                centre_lines:  params[:leaded_centre_lines_only] == true,
                mte_id:        (params[:leaded_mte_id] || NA_DEFAULT_MTE_ID).to_s
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Glass Outer-Face Y (Exterior Face Of Glass Pane)
        # ------------------------------------------------------------
        # Mirrors GeometryBuilders.na_create_glass_geometry Y placement.
        def self.na_glass_outer_face_y(wall_inset, glass_thickness, frame_depth, casement_depth = nil, casement_inset = nil)
            if casement_depth && casement_inset
                wall_inset + casement_inset + (casement_depth - glass_thickness) / 2.0
            else
                wall_inset + (frame_depth - glass_thickness) / 2.0
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API — Geometry Creation
# -----------------------------------------------------------------------------

        # FUNCTION | Create Leaded Glass Overlay Geometry
        # ------------------------------------------------------------
        # @param naming [Hash, nil] optional { prefix: "Na__ExteriorSingleDoor" }
        #   When set, groups are named "{prefix}__LeadedGlassH/V#"
        #   Otherwise Window style: "Na_LeadedGlass_{panel_id}_H/V#"
        # @return [Array<Sketchup::Group>] created groups (may be empty)
        def self.na_create_leaded_glass_geometry(
            entities,
            panel_id,
            glass_width,
            glass_height,
            offset_x,
            offset_z,
            y_front,
            leaded_params,
            naming: nil
        )
            return [] unless entities && leaded_params.is_a?(Hash)
            return [] unless leaded_params[:enabled]
            return [] if glass_width.to_f <= 0 || glass_height.to_f <= 0

            h_bars = leaded_params[:h_bars].to_i
            v_bars = leaded_params[:v_bars].to_i
            return [] if h_bars <= 0 && v_bars <= 0

            material = EdgeColourManager.na_get_edge_material_by_id(leaded_params[:mte_id])
            centre_lines = leaded_params[:centre_lines] == true
            width = centre_lines ? 0.0 : leaded_params[:width].to_f
            depth = centre_lines ? 0.0 : leaded_params[:depth].to_f

            h_positions = GeometryBuilders.na_compute_bar_positions(offset_z, glass_height, h_bars, false, 0)
            v_positions = GeometryBuilders.na_compute_bar_positions(offset_x, glass_width, v_bars, false, 0)

            created = []

            if centre_lines
                h_positions.each_with_index do |z_center, index|
                    group = na_create_centre_line_horizontal(
                        entities, panel_id, offset_x, offset_x + glass_width, z_center, y_front, index + 1, naming
                    )
                    created << group if group
                end
                v_positions.each_with_index do |x_center, index|
                    group = na_create_centre_line_vertical(
                        entities, panel_id, offset_z, offset_z + glass_height, x_center, y_front, index + 1, naming
                    )
                    created << group if group
                end
                created.each { |g| EdgeColourManager.na_apply_edge_colour_to_group(g, leaded_params[:mte_id]) if g }
                return created
            end

            if depth <= 0
                h_positions.each_with_index do |z_center, index|
                    group = na_create_flat_ribbon_horizontal(
                        entities, panel_id, offset_x, glass_width, z_center, width, y_front, index + 1, material, naming
                    )
                    created << group if group
                end
                v_positions.each_with_index do |x_center, index|
                    group = na_create_flat_ribbon_vertical(
                        entities, panel_id, offset_z, glass_height, x_center, width, y_front, index + 1, material, naming
                    )
                    created << group if group
                end
            else
                # Extrude forward (exterior): box spans [y_front - depth, y_front]
                y_origin = y_front - depth
                h_positions.each_with_index do |z_center, index|
                    bar_z = z_center - (width / 2.0)
                    name = na_group_name(panel_id, 'H', index + 1, naming)
                    group = GeometryHelpers.na_create_grouped_box(
                        entities, name, offset_x, y_origin, bar_z, glass_width, depth, width, material
                    )
                    created << group if group
                end
                v_positions.each_with_index do |x_center, index|
                    bar_x = x_center - (width / 2.0)
                    name = na_group_name(panel_id, 'V', index + 1, naming)
                    group = GeometryHelpers.na_create_grouped_box(
                        entities, name, bar_x, y_origin, offset_z, width, depth, glass_height, material
                    )
                    created << group if group
                end
            end

            created.each do |g|
                next unless g && g.valid?
                EdgeColourManager.na_apply_edge_colour_to_group(g, leaded_params[:mte_id])
            end

            DebugTools.na_debug_geometry(
                "LeadedGlass panel #{panel_id}: #{h_bars}H x #{v_bars}V " \
                "(centre=#{centre_lines}, depth=#{(depth / NA_MM_TO_INCH).round(1)}mm)"
            )
            created
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Helpers — Naming & Modes
# -----------------------------------------------------------------------------

        def self.na_disabled_params
            {
                enabled: false,
                h_bars: 0,
                v_bars: 0,
                width: 6.0 * NA_MM_TO_INCH,
                depth: 0.0,
                centre_lines: false,
                mte_id: NA_DEFAULT_MTE_ID
            }
        end
        private_class_method :na_disabled_params

        def self.na_group_name(panel_id, axis, index, naming)
            prefix = naming.is_a?(Hash) ? naming[:prefix] : nil
            if prefix && !prefix.to_s.empty?
                "#{prefix}__LeadedGlass#{axis}#{index}"
            else
                "Na_LeadedGlass_#{panel_id}_#{axis}#{index}"
            end
        end
        private_class_method :na_group_name

        def self.na_create_centre_line_horizontal(entities, panel_id, x0, x1, z, y, index, naming)
            return nil if (x1 - x0).abs < 0.001

            group = entities.add_group
            group.name = na_group_name(panel_id, 'H', index, naming)
            p0 = Geom::Point3d.new(x0, y, z)
            p1 = Geom::Point3d.new(x1, y, z)
            group.entities.add_edges(p0, p1)
            group
        end
        private_class_method :na_create_centre_line_horizontal

        def self.na_create_centre_line_vertical(entities, panel_id, z0, z1, x, y, index, naming)
            return nil if (z1 - z0).abs < 0.001

            group = entities.add_group
            group.name = na_group_name(panel_id, 'V', index, naming)
            p0 = Geom::Point3d.new(x, y, z0)
            p1 = Geom::Point3d.new(x, y, z1)
            group.entities.add_edges(p0, p1)
            group
        end
        private_class_method :na_create_centre_line_vertical

        def self.na_create_flat_ribbon_horizontal(entities, panel_id, offset_x, glass_width, z_center, width, y, index, material, naming)
            return nil if width <= 0 || glass_width <= 0

            half = width / 2.0
            group = entities.add_group
            group.name = na_group_name(panel_id, 'H', index, naming)
            p1 = Geom::Point3d.new(offset_x, y, z_center - half)
            p2 = Geom::Point3d.new(offset_x + glass_width, y, z_center - half)
            p3 = Geom::Point3d.new(offset_x + glass_width, y, z_center + half)
            p4 = Geom::Point3d.new(offset_x, y, z_center + half)
            face = group.entities.add_face(p1, p2, p3, p4)
            if face && material
                face.material = material
                face.back_material = material
            end
            group
        end
        private_class_method :na_create_flat_ribbon_horizontal

        def self.na_create_flat_ribbon_vertical(entities, panel_id, offset_z, glass_height, x_center, width, y, index, material, naming)
            return nil if width <= 0 || glass_height <= 0

            half = width / 2.0
            group = entities.add_group
            group.name = na_group_name(panel_id, 'V', index, naming)
            p1 = Geom::Point3d.new(x_center - half, y, offset_z)
            p2 = Geom::Point3d.new(x_center + half, y, offset_z)
            p3 = Geom::Point3d.new(x_center + half, y, offset_z + glass_height)
            p4 = Geom::Point3d.new(x_center - half, y, offset_z + glass_height)
            face = group.entities.add_face(p1, p2, p3, p4)
            if face && material
                face.material = material
                face.back_material = material
            end
            group
        end
        private_class_method :na_create_flat_ribbon_vertical

# endregion -------------------------------------------------------------------

    end
end
end
