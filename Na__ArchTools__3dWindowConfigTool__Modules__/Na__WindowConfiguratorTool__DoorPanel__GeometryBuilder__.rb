# =============================================================================
# NA WINDOW CONFIGURATOR TOOL - DOOR PANEL GEOMETRY BUILDER
# =============================================================================
#
# FILE       : Na__WindowConfiguratorTool__DoorPanel__GeometryBuilder__.rb
# NAMESPACE  : Na__WindowConfiguratorTool
# MODULE     : Na__DoorPanelGeometryBuilder
# AUTHOR     : Noble Architecture
# PURPOSE    : Creates solid door panel geometry inside a casement frame
# CREATED    : 2026
# VERSION    : 0.3.0
#
# DESCRIPTION:
# - Builds the solid panel content that sits inside a door casement frame
# - Recess depth controls the inset of panels from both front and back faces
#   e.g. casement_depth=80mm, recess_depth=10mm => panel is 60mm deep, 10mm
#   back from front face and 10mm forward from back face
# - Margin border fills the perimeter at full casement depth (flush with frame)
# - Grid dividers also at full casement depth (form the raised frame between cells)
# - Recessed panels sit behind the frame surface by recess_depth on each side
# - Trim/moulding sits on both front and back recess shelves
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix
# - Group names: Na_DoorPanel_{panel_id}_* and Na_DoorTrim_{panel_id}_*
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__WindowConfiguratorTool__DebugTools__'
require_relative 'Na__WindowConfiguratorTool__GeometryHelpers__'

module Na__WindowConfiguratorTool
    module Na__DoorPanelGeometryBuilder

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools = Na__WindowConfiguratorTool::Na__DebugTools
        GeometryHelpers = Na__WindowConfiguratorTool::Na__GeometryHelpers

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Create Door Panel Section Inside a Casement
        # ------------------------------------------------------------
        def self.na_create_door_panel_section(entities, panel_id, panel_x, panel_z, panel_width, panel_height, params, frame_material)
            DebugTools.na_debug_geometry("Creating door panel for #{panel_id}: #{panel_width.to_mm.round}x#{panel_height.to_mm.round}mm")

            margin = params[:door_panel_margin]
            columns = params[:door_panel_columns]
            rows = params[:door_panel_rows]
            rail_width = params[:door_panel_rail_width]
            stile_width = params[:door_panel_stile_width]
            recess_depth = params[:door_panel_recess_depth]
            trim_width = params[:door_panel_trim_width]
            trim_depth = params[:door_panel_trim_depth]
            moulding_inset = params[:door_panel_moulding_inset] || 0
            show_trim = params[:door_panel_show_trim] != false
            casement_depth = params[:casement_depth]
            y_offset = params[:frame_wall_inset] + params[:casement_inset]

            # Margin border: fills the perimeter at full casement depth (flush with frame)
            na_create_margin_border(
                entities, panel_id,
                panel_x, y_offset, panel_z,
                panel_width, panel_height,
                margin, casement_depth, frame_material
            )

            grid_x = panel_x + margin
            grid_z = panel_z + margin
            grid_width = panel_width - (2 * margin)
            grid_height = panel_height - (2 * margin)

            return if grid_width <= 0 || grid_height <= 0

            # Grid dividers at full casement depth (raised frame between cells)
            na_create_grid_dividers(
                entities, panel_id,
                grid_x, y_offset, grid_z,
                grid_width, grid_height,
                columns, rows,
                stile_width, rail_width,
                casement_depth, frame_material
            )

            cell_positions = na_calculate_cell_positions(
                grid_x, grid_z, grid_width, grid_height,
                columns, rows, stile_width, rail_width
            )

            cell_positions.each_with_index do |cell, cell_idx|
                na_create_recessed_panel(
                    entities, panel_id, cell_idx,
                    cell[:x], y_offset, cell[:z],
                    cell[:width], cell[:height],
                    casement_depth, recess_depth,
                    frame_material
                )

                if show_trim && trim_width > 0 && trim_depth > 0
                    na_create_panel_trim(
                        entities, panel_id, cell_idx,
                        cell[:x], y_offset, cell[:z],
                        cell[:width], cell[:height],
                        casement_depth, recess_depth,
                        trim_width, trim_depth, moulding_inset,
                        frame_material
                    )
                end
            end

            DebugTools.na_debug_geometry("Door panel complete for #{panel_id}")
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Helpers
# -----------------------------------------------------------------------------

        private

        # FUNCTION | Create Margin Border
        # ------------------------------------------------------------
        # Four border pieces at full casement depth filling the margin
        # area between casement stiles/rails and the panel grid.
        # Stiles full height, rails inset (joinery convention).
        def self.na_create_margin_border(entities, panel_id, x, y, z, width, height, margin, depth, material)
            return if margin <= 0

            clear_width = width - (2 * margin)
            return if clear_width <= 0

            GeometryHelpers.na_create_grouped_box(
                entities, "Na_DoorPanel_#{panel_id}_Margin_Left",
                x, y, z, margin, depth, height, material
            )
            GeometryHelpers.na_create_grouped_box(
                entities, "Na_DoorPanel_#{panel_id}_Margin_Right",
                x + width - margin, y, z, margin, depth, height, material
            )
            GeometryHelpers.na_create_grouped_box(
                entities, "Na_DoorPanel_#{panel_id}_Margin_Bottom",
                x + margin, y, z, clear_width, depth, margin, material
            )
            GeometryHelpers.na_create_grouped_box(
                entities, "Na_DoorPanel_#{panel_id}_Margin_Top",
                x + margin, y, z + height - margin, clear_width, depth, margin, material
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | Create Internal Grid Dividers
        # ------------------------------------------------------------
        # At full casement depth so they sit proud of the recessed panels.
        def self.na_create_grid_dividers(entities, panel_id, grid_x, y, grid_z, grid_width, grid_height, columns, rows, stile_width, rail_width, depth, material)
            total_stile_width = [columns - 1, 0].max * stile_width
            total_rail_height = [rows - 1, 0].max * rail_width
            cell_area_width = grid_width - total_stile_width
            cell_area_height = grid_height - total_rail_height
            cell_width = columns > 0 ? cell_area_width / columns.to_f : grid_width
            cell_height = rows > 0 ? cell_area_height / rows.to_f : grid_height

            (1...columns).each do |col|
                stile_x = grid_x + (col * cell_width) + ((col - 1) * stile_width)
                GeometryHelpers.na_create_grouped_box(
                    entities, "Na_DoorPanel_#{panel_id}_Stile_#{col}",
                    stile_x, y, grid_z, stile_width, depth, grid_height, material
                )
            end

            (1...rows).each do |row|
                rail_z = grid_z + (row * cell_height) + ((row - 1) * rail_width)
                GeometryHelpers.na_create_grouped_box(
                    entities, "Na_DoorPanel_#{panel_id}_Rail_#{row}",
                    grid_x, y, rail_z, grid_width, depth, rail_width, material
                )
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Calculate Cell Positions
        # ------------------------------------------------------------
        def self.na_calculate_cell_positions(grid_x, grid_z, grid_width, grid_height, columns, rows, stile_width, rail_width)
            total_stile_width = [columns - 1, 0].max * stile_width
            total_rail_height = [rows - 1, 0].max * rail_width
            cell_area_width = grid_width - total_stile_width
            cell_area_height = grid_height - total_rail_height
            cell_width = columns > 0 ? cell_area_width / columns.to_f : grid_width
            cell_height = rows > 0 ? cell_area_height / rows.to_f : grid_height

            cells = []
            (0...rows).each do |row|
                cell_z = grid_z + (row * (cell_height + rail_width))
                (0...columns).each do |col|
                    cell_x = grid_x + (col * (cell_width + stile_width))
                    cells << { x: cell_x, z: cell_z, width: cell_width, height: cell_height }
                end
            end
            cells
        end
        # ---------------------------------------------------------------

        # FUNCTION | Create Recessed Panel
        # ------------------------------------------------------------
        # Panel is inset by recess_depth from both front and back faces.
        # e.g. casement_depth=80mm, recess_depth=10mm => 60mm deep panel
        # sitting 10mm back from front and 10mm forward from back.
        def self.na_create_recessed_panel(entities, panel_id, cell_index, x, y, z, width, height, casement_depth, recess_depth, material)
            panel_y = y + recess_depth
            panel_depth = casement_depth - (2 * recess_depth)
            panel_depth = [panel_depth, 1.mm].max

            GeometryHelpers.na_create_grouped_box(
                entities, "Na_DoorPanel_#{panel_id}_Panel_#{cell_index}",
                x, panel_y, z, width, panel_depth, height, material
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | Create Panel Trim / Moulding
        # ------------------------------------------------------------
        # Trim sits on the recess shelf on BOTH the front and back faces.
        # Front trim: at y_offset + moulding_inset
        # Back trim: at y_offset + casement_depth - moulding_inset - trim_depth
        def self.na_create_panel_trim(entities, panel_id, cell_index, cell_x, y, cell_z, cell_width, cell_height, casement_depth, recess_depth, trim_width, trim_depth, moulding_inset, material)
            trim_d = [trim_depth, recess_depth - moulding_inset].min
            trim_d = [trim_d, 1.mm].max

            front_trim_y = y + moulding_inset
            back_trim_y = y + casement_depth - moulding_inset - trim_d

            na_create_trim_ring(entities, "Na_DoorTrim_#{panel_id}_#{cell_index}_F", cell_x, front_trim_y, cell_z, cell_width, cell_height, trim_width, trim_d, material)
            na_create_trim_ring(entities, "Na_DoorTrim_#{panel_id}_#{cell_index}_B", cell_x, back_trim_y, cell_z, cell_width, cell_height, trim_width, trim_d, material)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Create Single Trim Ring (4 strips)
        # ------------------------------------------------------------
        def self.na_create_trim_ring(entities, prefix, x, y, z, width, height, trim_width, trim_depth, material)
            GeometryHelpers.na_create_grouped_box(
                entities, "#{prefix}_Bottom",
                x, y, z,
                width, trim_depth, trim_width, material
            )
            GeometryHelpers.na_create_grouped_box(
                entities, "#{prefix}_Top",
                x, y, z + height - trim_width,
                width, trim_depth, trim_width, material
            )

            inner_height = height - (2 * trim_width)
            return if inner_height <= 0

            GeometryHelpers.na_create_grouped_box(
                entities, "#{prefix}_Left",
                x, y, z + trim_width,
                trim_width, trim_depth, inner_height, material
            )
            GeometryHelpers.na_create_grouped_box(
                entities, "#{prefix}_Right",
                x + width - trim_width, y, z + trim_width,
                trim_width, trim_depth, inner_height, material
            )
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__DoorPanelGeometryBuilder
end # module Na__WindowConfiguratorTool

# =============================================================================
# END OF FILE
# =============================================================================
