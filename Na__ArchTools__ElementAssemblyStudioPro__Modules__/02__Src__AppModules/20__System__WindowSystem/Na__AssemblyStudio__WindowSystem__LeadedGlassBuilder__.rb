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
# - PER-CELL layout: when the caller passes a grid: hash (final glaze bar
#   centerlines + bar width + optional disabled-cell keys) the lead lines
#   are laid out inside each glazing cell BETWEEN the glaze bars instead
#   of spanning the whole pane, so lead never clashes with the bars.
#   Cell keys: "opening:cell:panel:sash:col:row" (col 0 = left, row 0 = bottom).
# - ALIGNED layout (V1.8.0): when the grid also carries :reference (a pane
#   built to the window-wide casement settings), the HORIZONTAL lines are
#   laid out on that pane and each real glazing cell keeps the ones that
#   land inside it, so they run level through casements with their own
#   rails. Vertical lines always divide each cell's own width (V2.1.1).
# - LEAD LINE MARGINS (V2.2.0): with :margin_x / :margin_y set, the first
#   and last lines of each cell sit that far in from its edges and the
#   lines between divide the rest evenly (the margin glazing rule).
# - SINGLE LINES OFF (V2.2.1): grid[:removed_lines] holds the lines clicked
#   off in the window preview, keyed by cell, axis and number in the cell.
# - ARCHED HEADER (V2.5.2): with grid[:header_arch] set, each line is cut to
#   the arch, its end just inside the rail. Lines keep the positions and
#   numbers the flat pane gives them.
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
require_relative 'Na__AssemblyStudio__WindowSystem__ArchedHeaderBuilder__'

module Na__AssemblyStudio
module Na__WindowSystem
    module Na__LeadedGlassBuilder

# -----------------------------------------------------------------------------
# REGION | Module References & Constants
# -----------------------------------------------------------------------------

        DebugTools          = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        EdgeColourManager   = Na__AssemblyStudio::Na__AppData::Na__EdgeColourManager
        GeometryBuilders    = Na__AssemblyStudio::Na__WindowSystem::Na__GeometryBuilders
        GeometryHelpers     = Na__AssemblyStudio::Na__WindowSystem::Na__GeometryHelpers
        ArchedHeaderBuilder = Na__AssemblyStudio::Na__WindowSystem::Na__ArchedHeaderBuilder

        NA_LEGACY_COLOUR_MTE_MAP = {
            'mid'   => 'MTE104__LineColour__MidGrey__L60',
            'light' => 'MTE107__LineColour__LightGrey__L85',
            'dark'  => 'MTE103__LineColour__DarkGrey__L40'
        }.freeze

        NA_DEFAULT_MTE_ID = 'MTE104__LineColour__MidGrey__L60'.freeze
        NA_MM_TO_INCH = 1.0 / 25.4
        NA_LEAD_MARGIN_DEFAULT_MM = 50.0                                                         # <-- V2.2.0 Lead Line Margins until one is typed

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
        # :margin_x / :margin_y (V2.2.0, Lead Line Margins) are how far the
        # first and last vertical / horizontal lines sit in from each pane's
        # edges, or nil for the even layout (switched off, or a window saved
        # before the toggle existed). Each direction has its own switch
        # (V2.2.2, leaded_margin_x_enabled / _y_enabled); an absent one (a
        # window saved by V2.2.0 or V2.2.1) is on. Mirrors
        # na_resolveLeadMargins in the JS SVG generator.
        # @param config [Hash] windowConfiguration (string keys, mm values)
        # @return [Hash] typed params (inches where dimensional)
        def self.na_resolve_leaded_params(config)
            return na_disabled_params unless config.is_a?(Hash)

            na_migrate_legacy_leaded_colour!(config)
            enabled = config['leaded_glass_enabled'] == true
            mte_id = (config['edge_colour_leaded_id'] || NA_DEFAULT_MTE_ID).to_s
            mte_id = NA_DEFAULT_MTE_ID if mte_id.empty?
            margins_on = config['leaded_margins_enabled'] == true
            margin_x_on = margins_on && config['leaded_margin_x_enabled'] != false
            margin_y_on = margins_on && config['leaded_margin_y_enabled'] != false

            {
                enabled:       enabled,
                h_bars:        [[(config['horizontal_leaded_bars'] || 0).to_i, 0].max, 12].min,
                v_bars:        [[(config['vertical_leaded_bars'] || 0).to_i, 0].max, 12].min,
                width:         [(config['leaded_width_mm'] || 6).to_f, 2.0].max * NA_MM_TO_INCH,
                depth:         [[(config['leaded_depth_mm'] || 0).to_f, 0.0].max, 5.0].min * NA_MM_TO_INCH,
                centre_lines:  config['leaded_centre_lines_only'] == true,
                mte_id:        mte_id,
                margin_x:      margin_x_on ? na_margin_inches(config['leaded_margin_x_mm']) : nil,
                margin_y:      margin_y_on ? na_margin_inches(config['leaded_margin_y_mm']) : nil
            }
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | One Lead Line Margin, mm Config Value -> Inches (V2.2.0)
        # ------------------------------------------------------------
        # A missing value takes the control's default; never below zero.
        def self.na_margin_inches(value_mm)
            margin_mm = value_mm.nil? ? NA_LEAD_MARGIN_DEFAULT_MM : value_mm.to_f
            [margin_mm, 0.0].max * NA_MM_TO_INCH
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
                mte_id:        (params[:leaded_mte_id] || NA_DEFAULT_MTE_ID).to_s,
                margin_x:      params[:leaded_margin_x],
                margin_y:      params[:leaded_margin_y]
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
        # @param grid [Hash, nil] optional glaze bar grid context:
        #   { h_positions:, v_positions:  FINAL bar centerlines (caller units),
        #     bar_width:                  glaze bar width (caller units),
        #     effective_glass_height:    lead zone height (arch zone excluded),
        #     panel_context:             { opening:, cell:, panel:, sash: },
        #     disabled_cells:            Array of "o:c:p:s:col:row" keys,
        #     removed_lines:             optional (V2.2.1) Array of
        #                                "o:c:p:s:col:row:h|v:number" keys,
        #                                single lines clicked off,
        #     reference:                 optional (V1.8.0) { offset_z:,
        #                                h_positions:, effective_glass_height: },
        #     header_arch:               optional (V2.5.2) the arch over this
        #                                glass, in the caller's units }
        #   When present, lead lines are laid out per glazing cell between
        #   the bars; cells whose key is disabled are skipped entirely.
        #   Without it the legacy whole-pane single-cell layout applies.
        #   With :reference the horizontal lines are those of the reference
        #   pane's own rows, each cell keeping the ones inside it; vertical
        #   lines still divide each cell's own width (V2.1.1).
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
            naming: nil,
            grid: nil
        )
            return [] unless entities && leaded_params.is_a?(Hash)
            return [] unless leaded_params[:enabled]
            return [] if glass_width.to_f <= 0 || glass_height.to_f <= 0

            h_bars = leaded_params[:h_bars].to_i
            v_bars = leaded_params[:v_bars].to_i
            return [] if h_bars <= 0 && v_bars <= 0

            grid_hash = grid.is_a?(Hash) ? grid : {}
            bar_width = (grid_hash[:bar_width] || 0).to_f
            lead_zone_height = (grid_hash[:effective_glass_height] || glass_height).to_f
            column_bounds = na_compute_cell_bounds(offset_x, glass_width, grid_hash[:v_positions], bar_width)
            row_bounds = na_compute_cell_bounds(offset_z, lead_zone_height, grid_hash[:h_positions], bar_width)
            disabled_cells = grid_hash[:disabled_cells].is_a?(Array) ? grid_hash[:disabled_cells].map(&:to_s) : []
            removed_lines = grid_hash[:removed_lines].is_a?(Array) ? grid_hash[:removed_lines].map(&:to_s) : []   # <-- V2.2.1 "cell key:h|v:number"
            panel_context = grid_hash[:panel_context].is_a?(Hash) ? grid_hash[:panel_context] : nil
            multi_cell = column_bounds.length > 1 || row_bounds.length > 1
            reference_rows = na_compute_reference_lead_rows(
                grid_hash[:reference], bar_width, h_bars, leaded_params[:margin_y], leaded_params[:width]
            )
            lead_margin = [leaded_params[:width].to_f / 2.0, NA_MM_TO_INCH].max                        # <-- Keeps a line's ribbon off rails and bars

            created = []
            row_bounds.each_with_index do |row_bound, row_index|
                column_bounds.each_with_index do |column_bound, col_index|
                    next if row_bound[:size] <= 0 || column_bound[:size] <= 0

                    cell_removed = nil
                    if panel_context
                        cell_key = "#{panel_context[:opening]}:#{panel_context[:cell]}:" \
                                   "#{panel_context[:panel]}:#{panel_context[:sash]}:#{col_index}:#{row_index}"
                        next if disabled_cells.include?(cell_key)

                        prefix = "#{cell_key}:"
                        cell_removed = removed_lines.select { |key| key.start_with?(prefix) }.map { |key| key[prefix.length..] }
                    end

                    cell_panel_id = multi_cell ? "#{panel_id}_C#{col_index}_#{row_index}" : panel_id
                    cell_naming = naming
                    if multi_cell && naming.is_a?(Hash) && naming[:prefix]
                        cell_naming = naming.merge(cell_suffix: "_C#{col_index}_#{row_index}")
                    end

                    cell_positions = nil
                    if reference_rows
                        cell_positions = {                                                              # <-- No :v, so verticals stay even in this cell
                            h: na_positions_inside(reference_rows, row_bound[:start], row_bound[:size], lead_margin)
                        }
                    end

                    created.concat(
                        na_create_leaded_cell_geometry(
                            entities, cell_panel_id,
                            column_bound[:size], row_bound[:size],
                            column_bound[:start], row_bound[:start],
                            y_front, leaded_params, cell_naming,
                            positions: cell_positions,
                            removed: cell_removed,
                            header_arch: grid_hash[:header_arch]
                        )
                    )
                end
            end

            DebugTools.na_debug_geometry(
                "LeadedGlass panel #{panel_id}: #{h_bars}H x #{v_bars}V per cell " \
                "(#{column_bounds.length}x#{row_bounds.length} cells, #{disabled_cells.length} disabled)"
            )
            created
        end
        # ---------------------------------------------------------------

        # FUNCTION | Split One Axis Into Cell Segments Between Bar Edges
        # ------------------------------------------------------------
        # Mirrors Na__GlazebarMath.na_computeCellBounds in JS. Positions
        # are FINAL bar centerlines (offsets applied); segments run glass
        # edge -> bar edge, bar edge -> bar edge, ..., bar edge -> glass edge.
        def self.na_compute_cell_bounds(start, size, bar_positions, bar_width)
            positions = bar_positions.is_a?(Array) ? bar_positions.map(&:to_f).sort : []
            half_bar = [bar_width.to_f, 0.0].max / 2.0
            cells = []
            cursor = start.to_f
            positions.each do |position|
                edge = position - half_bar
                cells << { start: cursor, size: [edge - cursor, 0.0].max }
                cursor = position + half_bar
            end
            cells << { start: cursor, size: [(start.to_f + size.to_f) - cursor, 0.0].max }
            cells
        end
        # ---------------------------------------------------------------

        # FUNCTION | Lay the Aligned Lead Rows Out on a Reference Pane (V1.8.0)
        # ------------------------------------------------------------
        # Every HORIZONTAL lead centreline the reference pane would carry: its
        # glazing rows (between its own final glaze bars), each divided evenly
        # just as the per-cell layout divides a pane. Verticals are not
        # aligned (V2.1.1): every cell divides its own width, so a light with
        # no casement, or with wider stiles, spaces them across its own glass.
        # nil without a reference. margin / lead_width (V2.2.0) lay each
        # reference row out inside the Lead Line Margins, as a cell of its own
        # would be. Mirrors na_computeReferenceLeadRows in the JS SVG
        # generator.
        # @return [Array<Float>, nil] z positions
        def self.na_compute_reference_lead_rows(reference, bar_width, h_bars, margin = nil, lead_width = 0.0)
            return nil unless reference.is_a?(Hash)

            rows = na_compute_cell_bounds(reference[:offset_z], reference[:effective_glass_height], reference[:h_positions], bar_width)
            na_compute_lead_line_positions(rows, h_bars, margin, lead_width)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Lead Centrelines Across One Span (V2.2.0)
        # ------------------------------------------------------------
        # margin nil: count + 1 equal panes, as always. margin set (Lead Line
        # Margins): the first and last lines sit that far in from the span's
        # edges and the lines between divide the rest evenly, the margin
        # glazing rule. One line stays in the middle. The margin gives way
        # before the lines close up past touching (a lead width apart); a
        # span too small even for that keeps the even layout. Mirrors
        # Na__GlazebarMath.na_computeLeadPositions.
        def self.na_compute_lead_positions(start, size, count, margin = nil, lead_width = 0.0)
            line_count = [count.to_i, 0].max
            return [] if line_count <= 0 || size.to_f <= 0
            if margin.nil? || line_count < 2
                return GeometryBuilders.na_compute_bar_positions(start, size, line_count, false, 0)
            end

            max_margin = (size.to_f - ((line_count - 1) * [lead_width.to_f, 0.0].max)) / 2.0
            return GeometryBuilders.na_compute_bar_positions(start, size, line_count, false, 0) unless max_margin > 0

            GeometryBuilders.na_compute_bar_positions(start, size, line_count, true, [[margin.to_f, 0.0].max, max_margin].min)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Lead Centrelines Across a Set of Glazing Cells (V1.8.0)
        # ------------------------------------------------------------
        # Each cell is laid out by na_compute_lead_positions (margins from
        # V2.2.0). Mirrors Na__GlazebarMath.na_computeLeadLinePositions.
        def self.na_compute_lead_line_positions(cells, count, margin = nil, lead_width = 0.0)
            return [] unless cells.is_a?(Array) && count.to_i > 0

            cells.flat_map do |cell|
                next [] unless cell[:size].to_f > 0

                na_compute_lead_positions(cell[:start], cell[:size], count.to_i, margin, lead_width)
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Keep the Positions That Sit Clearly Inside One Span (V1.8.0)
        # ------------------------------------------------------------
        # A line within `margin` of the span's edge would run into a rail, a
        # stile or a glaze bar, so it is dropped rather than built half
        # buried. Mirrors Na__GlazebarMath.na_filterPositionsInside.
        def self.na_positions_inside(positions, start, size, margin)
            return [] unless positions.is_a?(Array)

            low = start.to_f + margin
            high = start.to_f + size.to_f - margin
            positions.select { |position| position > low && position < high }
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Number a Cell's Lines and Drop the Ones Clicked Off (V2.2.1)
        # ------------------------------------------------------------
        # @return [Array<Array(Float, Integer)>] [position, number from 1]
        def self.na_kept_lead_lines(positions, axis, removed)
            removed_numbers = (removed || []).map(&:to_s)
            positions.each_with_index
                     .map { |position, index| [position, index + 1] }
                     .reject { |_position, number| removed_numbers.include?("#{axis}:#{number}") }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Create Lead Lines Within One Glazing Cell
        # ------------------------------------------------------------
        # The original whole-pane drawing body, applied to one cell rect.
        # positions (V1.8.0, optional): { h: [z...], v: [x...] } already cut
        # from the aligned grid, either axis optional. An axis it does not
        # give is laid out on the cell: divided evenly, as it always was, or
        # inside the Lead Line Margins when they are on (V2.2.0).
        # removed (V2.2.1, optional): ["h:2", "v:1" ...], this cell's lines
        # clicked off in the preview, numbered from 1 as the preview numbers
        # them. They are not built; the rest keep their numbers (H1, H3).
        # header_arch (V2.5.2, optional): the arch over this glass. Each line
        # stops at it, and one that lies wholly in the rail is not built.
        def self.na_create_leaded_cell_geometry(
            entities,
            panel_id,
            glass_width,
            glass_height,
            offset_x,
            offset_z,
            y_front,
            leaded_params,
            naming,
            positions: nil,
            removed: nil,
            header_arch: nil
        )
            return [] if glass_width.to_f <= 0 || glass_height.to_f <= 0

            h_bars = leaded_params[:h_bars].to_i
            v_bars = leaded_params[:v_bars].to_i
            material = EdgeColourManager.na_get_edge_material_by_id(leaded_params[:mte_id])
            centre_lines = leaded_params[:centre_lines] == true
            width = centre_lines ? 0.0 : leaded_params[:width].to_f
            depth = centre_lines ? 0.0 : leaded_params[:depth].to_f

            lead_width = leaded_params[:width].to_f                                                     # <-- The margin clamp uses the set width, centre lines or not (as the preview does)
            h_positions = positions && positions[:h] ? positions[:h] : na_compute_lead_positions(offset_z, glass_height, h_bars, leaded_params[:margin_y], lead_width)
            v_positions = positions && positions[:v] ? positions[:v] : na_compute_lead_positions(offset_x, glass_width, v_bars, leaded_params[:margin_x], lead_width)
            half_width = width / 2.0
            h_lines = na_kept_lead_lines(h_positions, 'h', removed).filter_map do |z_center, number|     # <-- [[position, number, run start, run width] ...]
                run = ArchedHeaderBuilder.na_trim_run(header_arch, offset_x, glass_width, z_center - half_width)
                run && [z_center, number, run[0], run[1]]
            end
            v_lines = na_kept_lead_lines(v_positions, 'v', removed).filter_map do |x_center, number|     # <-- [[position, number, height] ...]
                height = ArchedHeaderBuilder.na_trim_height(header_arch, x_center - half_width, x_center + half_width, offset_z, glass_height)
                height && [x_center, number, height]
            end

            created = []

            if centre_lines
                h_lines.each do |z_center, number, run_x, run_width|
                    group = na_create_centre_line_horizontal(
                        entities, panel_id, run_x, run_x + run_width, z_center, y_front, number, naming
                    )
                    created << group if group
                end
                v_lines.each do |x_center, number, height|
                    group = na_create_centre_line_vertical(
                        entities, panel_id, offset_z, offset_z + height, x_center, y_front, number, naming
                    )
                    created << group if group
                end
                created.each { |g| EdgeColourManager.na_apply_edge_colour_to_group(g, leaded_params[:mte_id]) if g }
                return created
            end

            if depth <= 0
                h_lines.each do |z_center, number, run_x, run_width|
                    group = na_create_flat_ribbon_horizontal(
                        entities, panel_id, run_x, run_width, z_center, width, y_front, number, material, naming
                    )
                    created << group if group
                end
                v_lines.each do |x_center, number, height|
                    group = na_create_flat_ribbon_vertical(
                        entities, panel_id, offset_z, height, x_center, width, y_front, number, material, naming
                    )
                    created << group if group
                end
            else
                # Extrude forward (exterior): box spans [y_front - depth, y_front]
                y_origin = y_front - depth
                h_lines.each do |z_center, number, run_x, run_width|
                    bar_z = z_center - (width / 2.0)
                    name = na_group_name(panel_id, 'H', number, naming)
                    group = GeometryHelpers.na_create_grouped_box(
                        entities, name, run_x, y_origin, bar_z, run_width, depth, width, material
                    )
                    created << group if group
                end
                v_lines.each do |x_center, number, height|
                    bar_x = x_center - (width / 2.0)
                    name = na_group_name(panel_id, 'V', number, naming)
                    group = GeometryHelpers.na_create_grouped_box(
                        entities, name, bar_x, y_origin, offset_z, width, depth, height, material
                    )
                    created << group if group
                end
            end

            created.each do |g|
                next unless g && g.valid?
                EdgeColourManager.na_apply_edge_colour_to_group(g, leaded_params[:mte_id])
            end

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
                mte_id: NA_DEFAULT_MTE_ID,
                margin_x: nil,
                margin_y: nil
            }
        end
        private_class_method :na_disabled_params

        def self.na_group_name(panel_id, axis, index, naming)
            prefix = naming.is_a?(Hash) ? naming[:prefix] : nil
            cell_suffix = naming.is_a?(Hash) ? naming[:cell_suffix].to_s : ''
            if prefix && !prefix.to_s.empty?
                # Cell suffix rides AFTER the LeadedGlass token so the door
                # FuseParts prefix collectors ('<container>__LeadedGlass')
                # keep matching per-cell groups.
                "#{prefix}__LeadedGlass#{axis}#{index}#{cell_suffix}"
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
