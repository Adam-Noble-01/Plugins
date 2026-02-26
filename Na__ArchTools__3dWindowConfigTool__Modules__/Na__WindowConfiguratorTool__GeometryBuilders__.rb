# =============================================================================
# NA WINDOW CONFIGURATOR TOOL - GEOMETRY BUILDERS
# =============================================================================
#
# FILE       : Na__WindowConfiguratorTool__GeometryBuilders__.rb
# NAMESPACE  : Na__WindowConfiguratorTool
# MODULE     : Na__GeometryBuilders
# AUTHOR     : Noble Architecture
# PURPOSE    : High-level geometry builder functions for window elements
# CREATED    : 2026
# VERSION    : 0.2.3b
#
# DESCRIPTION:
# - High-level builders that compose low-level GeometryHelpers primitives
# - Domain-specific functions for frame, mullion, casement, glass, glaze bars, cill
# - Handles joinery conventions (stiles full height, rails inset)
# - Manages Y-offset for frame wall inset feature
# - Material management (get or create)
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__WindowConfiguratorTool__DebugTools__'
require_relative 'Na__WindowConfiguratorTool__GeometryHelpers__'

module Na__WindowConfiguratorTool
    module Na__GeometryBuilders

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools = Na__WindowConfiguratorTool::Na__DebugTools
        GeometryHelpers = Na__WindowConfiguratorTool::Na__GeometryHelpers

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Material Management
# -----------------------------------------------------------------------------

        # FUNCTION | Get or Create Material
        # ------------------------------------------------------------
        # Creates a new material or updates the color of an existing one.
        # @param name [String] Material name
        # @param color [Sketchup::Color] Material color
        # @return [Sketchup::Material] The material
        def self.na_get_or_create_material(name, color)
            materials = Sketchup.active_model.materials
            material = materials[name]
            
            unless material
                material = materials.add(name)
            end
            
            # Always update color to reflect current selection
            material.color = color
            material.alpha = color.alpha / 255.0 if color.alpha < 255
            
            return material
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Frame Builders
# -----------------------------------------------------------------------------

        # FUNCTION | Create Frame Geometry (Outer Frame)
        # ------------------------------------------------------------
        # JOINERY CONVENTION: Stiles (vertical) span full height, 
        # Rails (horizontal) are inset between stiles.
        # This matches real window construction.
        # Each piece is created as a separate named group for easy identification.
        # 
        # @param entities [Sketchup::Entities] Target entities collection
        # @param width [Float] Overall window width
        # @param height [Float] Overall window height
        # @param thickness [Float] Frame member thickness
        # @param depth [Float] Frame depth (Y direction)
        # @param material [Sketchup::Material] Material to apply
        # @param wall_inset [Float] Y offset for frame (pushes into wall reveal)
        def self.na_create_frame_geometry(entities, width, height, thickness, depth, material, wall_inset = 0)
            DebugTools.na_debug_geometry("Creating outer frame: #{width.to_mm.round}x#{height.to_mm.round}mm, wall_inset: #{wall_inset.to_mm.round}mm")
            
            # Left stile - FULL HEIGHT (Z = 0 to height)
            GeometryHelpers.na_create_frame_stile(entities, "Left", 0, wall_inset, 0, thickness, depth, height, material)
            
            # Right stile - FULL HEIGHT (Z = 0 to height) at X = width - thickness
            GeometryHelpers.na_create_frame_stile(entities, "Right", width - thickness, wall_inset, 0, thickness, depth, height, material)
            
            # Bottom rail - INSET between stiles (X = thickness to width - thickness), at Z = 0
            GeometryHelpers.na_create_frame_rail(entities, "Bottom", thickness, wall_inset, 0, width - (2 * thickness), depth, thickness, material)
            
            # Top rail - INSET between stiles (X = thickness to width - thickness), at Z = height - thickness
            GeometryHelpers.na_create_frame_rail(entities, "Top", thickness, wall_inset, height - thickness, width - (2 * thickness), depth, thickness, material)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Create Mullion Geometry (Vertical Divider)
        # ------------------------------------------------------------
        # @param entities [Sketchup::Entities] Target entities collection
        # @param mullion_index [Integer] Index of this mullion (1-based)
        # @param x_pos [Float] X position for the mullion
        # @param inner_height [Float] Height of the inner window area (between top/bottom rails)
        # @param mullion_width [Float] Width of the mullion
        # @param depth [Float] Depth of the mullion (Y direction)
        # @param frame_thickness [Float] Thickness of the outer frame (for Z offset)
        # @param material [Sketchup::Material] Material to apply
        # @param wall_inset [Float] Y offset for frame
        def self.na_create_mullion_geometry(entities, mullion_index, x_pos, inner_height, mullion_width, depth, frame_thickness, material, wall_inset = 0)
            DebugTools.na_debug_geometry("Creating mullion #{mullion_index} at X=#{x_pos.to_mm.round}mm")
            
            # Mullion spans from bottom frame rail to top frame rail
            GeometryHelpers.na_create_mullion(entities, mullion_index, x_pos, wall_inset, frame_thickness, mullion_width, depth, inner_height, material)
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Casement Builders
# -----------------------------------------------------------------------------

        # FUNCTION | Create Casement Geometry (Legacy - uniform thickness)
        # ------------------------------------------------------------
        # JOINERY CONVENTION: Stiles (vertical) span full height, 
        # Rails (horizontal) are inset between stiles.
        # This matches real window construction.
        # Each piece is created as a separate named group for easy identification.
        # 
        # @param opening_index [Integer] Index of the opening (0-based)
        # @param cas_width [Float] Casement width
        # @param cas_height [Float] Casement height
        # @param thickness [Float] Uniform casement member thickness
        # @param depth [Float] Casement depth (Y direction)
        # @param offset_x [Float] X offset from frame origin
        # @param offset_z [Float] Z offset from frame origin
        # @param material [Sketchup::Material] Material to apply
        # @param wall_inset [Float] Y offset for frame
        # @param casement_inset [Float] Casement inset from frame face
        def self.na_create_casement_geometry(entities, opening_index, cas_width, cas_height, thickness, depth, offset_x, offset_z, material, wall_inset = 0, casement_inset = 10.mm)
            DebugTools.na_debug_geometry("Creating casement #{opening_index} at offset (#{offset_x.to_mm.round}, #{offset_z.to_mm.round})")
            
            y_offset = wall_inset + casement_inset
            
            # Left stile - FULL HEIGHT of casement
            GeometryHelpers.na_create_casement_stile(entities, opening_index, "Left", offset_x, y_offset, offset_z, thickness, depth, cas_height, material)
            
            # Right stile - FULL HEIGHT of casement
            GeometryHelpers.na_create_casement_stile(entities, opening_index, "Right", offset_x + cas_width - thickness, y_offset, offset_z, thickness, depth, cas_height, material)
            
            # Bottom rail - INSET between stiles
            GeometryHelpers.na_create_casement_rail(entities, opening_index, "Bottom", offset_x + thickness, y_offset, offset_z, cas_width - (2 * thickness), depth, thickness, material)
            
            # Top rail - INSET between stiles
            GeometryHelpers.na_create_casement_rail(entities, opening_index, "Top", offset_x + thickness, y_offset, offset_z + cas_height - thickness, cas_width - (2 * thickness), depth, thickness, material)
        end
        # ---------------------------------------------------------------
        
        # FUNCTION | Create Casement Geometry with Individual Sizes
        # ------------------------------------------------------------
        # JOINERY CONVENTION: Stiles (vertical) span full height, 
        # Rails (horizontal) are inset between stiles.
        # This version supports different widths for each rail and stile.
        # 
        # @param opening_index [Integer] Index of the opening (0-based)
        # @param cas_width [Float] Total casement width
        # @param cas_height [Float] Total casement height
        # @param top_rail [Float] Top rail thickness
        # @param bottom_rail [Float] Bottom rail thickness
        # @param left_stile [Float] Left stile thickness
        # @param right_stile [Float] Right stile thickness
        # @param depth [Float] Casement depth (Y direction)
        # @param offset_x [Float] X offset from frame origin
        # @param offset_z [Float] Z offset from frame origin
        # @param material [Sketchup::Material] Material to apply
        # @param wall_inset [Float] Y offset for frame
        # @param casement_inset [Float] Casement inset from frame face
        def self.na_create_casement_geometry_individual(entities, opening_index, cas_width, cas_height, top_rail, bottom_rail, left_stile, right_stile, depth, offset_x, offset_z, material, wall_inset = 0, casement_inset = 10.mm)
            DebugTools.na_debug_geometry("Creating casement #{opening_index} with individual sizes at offset (#{offset_x.to_mm.round}, #{offset_z.to_mm.round})")
            DebugTools.na_debug_geometry("  - Top Rail: #{top_rail.to_mm.round}mm, Bottom Rail: #{bottom_rail.to_mm.round}mm")
            DebugTools.na_debug_geometry("  - Left Stile: #{left_stile.to_mm.round}mm, Right Stile: #{right_stile.to_mm.round}mm")
            
            y_offset = wall_inset + casement_inset
            
            # Left stile - FULL HEIGHT of casement
            GeometryHelpers.na_create_casement_stile(entities, opening_index, "Left", offset_x, y_offset, offset_z, left_stile, depth, cas_height, material)
            
            # Right stile - FULL HEIGHT of casement
            GeometryHelpers.na_create_casement_stile(entities, opening_index, "Right", offset_x + cas_width - right_stile, y_offset, offset_z, right_stile, depth, cas_height, material)
            
            # Bottom rail - INSET between stiles (width excludes both stiles)
            rail_width = cas_width - left_stile - right_stile
            GeometryHelpers.na_create_casement_rail(entities, opening_index, "Bottom", offset_x + left_stile, y_offset, offset_z, rail_width, depth, bottom_rail, material)
            
            # Top rail - INSET between stiles (positioned at top minus rail height)
            GeometryHelpers.na_create_casement_rail(entities, opening_index, "Top", offset_x + left_stile, y_offset, offset_z + cas_height - top_rail, rail_width, depth, top_rail, material)
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Glass and Glaze Bar Builders
# -----------------------------------------------------------------------------

        # FUNCTION | Create Glass Geometry
        # ------------------------------------------------------------
        # @param opening_index [Integer] Index of the opening (0-based)
        # @param glass_width [Float] Glass width
        # @param glass_height [Float] Glass height
        # @param thickness [Float] Glass thickness
        # @param offset_x [Float] X offset
        # @param offset_z [Float] Z offset
        # @param frame_depth [Float] Frame depth (for centering glass when direct-glazed)
        # @param material [Sketchup::Material] Material to apply
        # @param wall_inset [Float] Y offset for frame
        # @param casement_depth [Float, nil] Casement depth (when glass inside casement, centers on casement)
        # @param casement_inset [Float, nil] Casement inset from frame face
        def self.na_create_glass_geometry(entities, opening_index, glass_width, glass_height, thickness, offset_x, offset_z, frame_depth, material, wall_inset = 0, casement_depth = nil, casement_inset = nil)
            DebugTools.na_debug_geometry("Creating glass pane #{opening_index}: #{glass_width.to_mm.round}x#{glass_height.to_mm.round}mm")
            
            if casement_depth && casement_inset
                # Glass centered on casement midpoint
                y_offset = wall_inset + casement_inset + (casement_depth - thickness) / 2.0
            else
                # Direct-glazed: center glass in frame depth
                y_offset = wall_inset + (frame_depth - thickness) / 2.0
            end
            
            GeometryHelpers.na_create_glass_pane(entities, opening_index, offset_x, y_offset, offset_z, glass_width, thickness, glass_height, material)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Create Glaze Bar Geometry
        # ------------------------------------------------------------
        # @param opening_index [Integer] Index of the opening (0-based)
        # @param glass_width [Float] Glass width
        # @param glass_height [Float] Glass height
        # @param h_bars [Integer] Number of horizontal bars
        # @param v_bars [Integer] Number of vertical bars
        # @param bar_width [Float] Bar width
        # @param glass_thickness [Float] Glass thickness
        # @param offset_x [Float] X offset
        # @param offset_z [Float] Z offset
        # @param frame_depth [Float] Frame depth
        # @param material [Sketchup::Material] Material to apply
        # @param wall_inset [Float] Y offset for frame
        # @param casement_depth [Float, nil] Casement depth (when bars inside casement)
        # @param casement_inset [Float, nil] Casement inset from frame face
        # @param glazebar_inset [Float] Glaze bar inset from front/back of casement (or frame)
        def self.na_create_glazebar_geometry(entities, opening_index, glass_width, glass_height, h_bars, v_bars, bar_width, glass_thickness, offset_x, offset_z, frame_depth, material, wall_inset = 0, casement_depth = nil, casement_inset = nil, glazebar_inset = 0)
            DebugTools.na_debug_geometry("Creating glaze bars for opening #{opening_index}: #{h_bars}H x #{v_bars}V")
            
            if casement_depth && casement_inset
                # Bars inset from casement faces
                y_offset = wall_inset + casement_inset + glazebar_inset
                bar_depth = casement_depth - (2 * glazebar_inset)
            else
                # Direct-glazed: inset from frame depth
                y_offset = wall_inset + glazebar_inset
                bar_depth = frame_depth - (2 * glazebar_inset)
            end
            bar_depth = [bar_depth, glass_thickness].max
            
            # Horizontal bars
            if h_bars > 0
                section_height = glass_height / (h_bars + 1)
                (1..h_bars).each do |i|
                    bar_z = offset_z + (section_height * i) - (bar_width / 2)
                    GeometryHelpers.na_create_glaze_bar_horizontal(entities, opening_index, i, offset_x, y_offset, bar_z, glass_width, bar_depth, bar_width, material)
                end
            end
            
            # Vertical bars
            if v_bars > 0
                section_width = glass_width / (v_bars + 1)
                (1..v_bars).each do |i|
                    bar_x = offset_x + (section_width * i) - (bar_width / 2)
                    GeometryHelpers.na_create_glaze_bar_vertical(entities, opening_index, i, bar_x, y_offset, offset_z, bar_width, bar_depth, glass_height, material)
                end
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Cill Builder
# -----------------------------------------------------------------------------

        # FUNCTION | Create Cill Geometry
        # ------------------------------------------------------------
        # The cill extends from the wall face (not from the inset frame).
        # When frame_wall_inset > 0, the cill still starts at the front of the wall.
        # 
        # @param entities [Sketchup::Entities] Target entities collection
        # @param width [Float] Cill width (matches window width)
        # @param cill_projection [Float] Cill projection from frame
        # @param cill_height [Float] Cill height
        # @param frame_depth [Float] Frame depth
        # @param material [Sketchup::Material] Material to apply
        # @param wall_inset [Float] Y offset for frame (cill extends through this)
        def self.na_create_cill_geometry(entities, width, cill_projection, cill_height, frame_depth, material, wall_inset = 0)
            DebugTools.na_debug_geometry("Creating cill: #{width.to_mm.round}mm wide, #{cill_projection.to_mm.round}mm projection, wall_inset: #{wall_inset.to_mm.round}mm")
            
            # Cill sits below window (negative Z) and projects forward (negative Y)
            # Cill starts at wall face (Y=0, not at wall_inset) and extends to back of frame
            cill_x = 0
            cill_y = -cill_projection
            cill_z = -cill_height
            cill_depth = cill_projection + wall_inset + frame_depth  # Projects front and extends through inset to back of frame
            
            GeometryHelpers.na_create_cill(entities, cill_x, cill_y, cill_z, width, cill_depth, cill_height, material)
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__GeometryBuilders
end # module Na__WindowConfiguratorTool

# =============================================================================
# END OF FILE
# =============================================================================
