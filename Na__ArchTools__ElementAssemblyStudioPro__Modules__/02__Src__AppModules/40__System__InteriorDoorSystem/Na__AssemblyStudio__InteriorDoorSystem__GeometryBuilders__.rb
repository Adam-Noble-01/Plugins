# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - INTERIOR DOOR SYSTEM - GEOMETRY BUILDERS
# =============================================================================
#
# FILE       : Na__AssemblyStudio__InteriorDoorSystem__GeometryBuilders__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__InteriorDoorSystem
# MODULE     : Na__GeometryBuilders
# AUTHOR     : Noble Architecture
# PURPOSE    : Mid-level builders that compose the door lining, panel and
#              swing using the low-level GeometryHelpers primitives.
# CREATED    : 01-May-2026
#
# DESCRIPTION:
# - Mirrors the role of Na__AssemblyStudio::Na__WindowSystem::Na__GeometryBuilders.
# - Each builder accepts a parsed configuration hash + a target entities
#   collection and returns the named SketchUp::Group it created.
# - All inputs are millimetres; conversion to inches happens inside the
#   GeometryHelpers primitives, never here.
# - Builders never modify the model directly; they only add geometry inside
#   the entities collection passed in. Callers handle operation transactions.
#
# COORDINATE SYSTEM (door-local):
# - Origin = bottom-front-left corner of the structural opening.
# - X+ runs left -> right across the opening width.
# - Y+ runs front -> back through the wall depth.
# - Z+ runs upwards.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative 'Na__AssemblyStudio__InteriorDoorSystem__GeometryHelpers__'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__TagManager__'

module Na__AssemblyStudio
module Na__InteriorDoorSystem
    module Na__GeometryBuilders

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools      = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        GeometryHelpers = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__GeometryHelpers
        TagManager      = Na__AssemblyStudio::Na__AppUtils::Na__TagManager

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Lining (U-Shaped Frame)
# -----------------------------------------------------------------------------

        # FUNCTION | Build the Three Lining Sections (Jamb-L, Head, Jamb-R)
        # ------------------------------------------------------------
        # Returns a wrapper group named "Na__Lining__Container" that owns
        # the three child groups so the assembly composer can move them
        # together. Optional fusion is performed by the FuseLiningParts
        # module after this builder returns.
        #
        # @param config [Hash] Parsed door configuration (Na__DoorConfiguration)
        # @param entities [Sketchup::Entities] Target entities (component def)
        # @param material [Sketchup::Material, nil] Optional lining material
        # @return [Hash] { :container => Group, :jamb_l => Group, :head => Group, :jamb_r => Group }
        def self.na_build_lining(config, entities, material = nil)
            opening_w_mm    = config["Na__DoorConfig__OpeningWidth_mm"].to_f      # <-- Structural opening width
            opening_h_mm    = config["Na__DoorConfig__OpeningHeight_mm"].to_f     # <-- Structural opening height
            wall_depth_mm   = config["Na__DoorConfig__WallDepth_mm"].to_f         # <-- Wall depth = lining depth
            lining_t_mm     = config["Na__DoorConfig__LiningThickness_mm"].to_f   # <-- Lining thickness (35mm default)
            face_offset_mm  = config["Na__DoorConfig__LiningFaceOffset_mm"].to_f  # <-- Optional inset from front face

            container       = entities.add_group
            container.name  = "Na__Lining__Container"
            container_ents  = container.entities

            jamb_l = na_build_lining_jamb_left(  container_ents, opening_h_mm, wall_depth_mm, lining_t_mm, face_offset_mm, material)
            jamb_r = na_build_lining_jamb_right( container_ents, opening_w_mm, opening_h_mm, wall_depth_mm, lining_t_mm, face_offset_mm, material)
            head   = na_build_lining_head(       container_ents, opening_w_mm, opening_h_mm, wall_depth_mm, lining_t_mm, face_offset_mm, material)

            DebugTools.na_debug_geometry("Built lining (W=#{opening_w_mm}mm, H=#{opening_h_mm}mm, D=#{wall_depth_mm}mm, t=#{lining_t_mm}mm)")
            { :container => container, :jamb_l => jamb_l, :head => head, :jamb_r => jamb_r }
        end
        # ---------------------------------------------------------------

        # SUB FUNCTION | Build Left Jamb Section
        # ------------------------------------------------------------
        def self.na_build_lining_jamb_left(entities, opening_h_mm, wall_depth_mm, lining_t_mm, face_offset_mm, material)
            origin_mm = [0, face_offset_mm, 0]                                   # <-- Bottom-front-left corner
            size_mm   = [lining_t_mm, wall_depth_mm, opening_h_mm]               # <-- Width x Depth x Height
            GeometryHelpers.na_create_lining_section(entities, origin_mm, size_mm, "Na__Lining__Jamb_L", material)
        end
        private_class_method :na_build_lining_jamb_left
        # ---------------------------------------------------------------

        # SUB FUNCTION | Build Right Jamb Section
        # ------------------------------------------------------------
        def self.na_build_lining_jamb_right(entities, opening_w_mm, opening_h_mm, wall_depth_mm, lining_t_mm, face_offset_mm, material)
            origin_mm = [opening_w_mm - lining_t_mm, face_offset_mm, 0]
            size_mm   = [lining_t_mm, wall_depth_mm, opening_h_mm]
            GeometryHelpers.na_create_lining_section(entities, origin_mm, size_mm, "Na__Lining__Jamb_R", material)
        end
        private_class_method :na_build_lining_jamb_right
        # ---------------------------------------------------------------

        # SUB FUNCTION | Build Head (Top Section, Spanning Between Jambs)
        # ------------------------------------------------------------
        def self.na_build_lining_head(entities, opening_w_mm, opening_h_mm, wall_depth_mm, lining_t_mm, face_offset_mm, material)
            origin_mm = [lining_t_mm, face_offset_mm, opening_h_mm - lining_t_mm]
            size_mm   = [opening_w_mm - 2 * lining_t_mm, wall_depth_mm, lining_t_mm]
            GeometryHelpers.na_create_lining_section(entities, origin_mm, size_mm, "Na__Lining__Head", material)
        end
        private_class_method :na_build_lining_head
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Door Panel
# -----------------------------------------------------------------------------

        # FUNCTION | Build the Door Panel Inside the Lining
        # ------------------------------------------------------------
        # Panel sits flush with the front face of the lining (Y = face_offset)
        # and is sized to the inner opening minus a small running clearance.
        # Floor clearance is applied at Z = panel_floor_clearance_mm.
        #
        # @param config [Hash] Door configuration
        # @param entities [Sketchup::Entities] Target entities (e.g. MOD group)
        # @param material [Sketchup::Material, nil] Optional panel material
        # @return [Sketchup::Group, nil] The panel group
        def self.na_build_panel(config, entities, material = nil)
            opening_w_mm     = config["Na__DoorConfig__OpeningWidth_mm"].to_f
            opening_h_mm     = config["Na__DoorConfig__OpeningHeight_mm"].to_f
            wall_depth_mm    = config["Na__DoorConfig__WallDepth_mm"].to_f
            lining_t_mm      = config["Na__DoorConfig__LiningThickness_mm"].to_f
            panel_t_mm       = config["Na__DoorConfig__PanelThickness_mm"].to_f
            face_offset_mm   = config["Na__DoorConfig__LiningFaceOffset_mm"].to_f
            floor_clear_mm   = config["Na__DoorConfig__PanelFloorClearance_mm"].to_f

            panel_w_mm       = opening_w_mm - 2 * lining_t_mm                    # <-- Inner opening width
            panel_h_mm       = (opening_h_mm - lining_t_mm) - floor_clear_mm     # <-- Inner opening height minus clearance

            return nil if panel_w_mm <= 0 || panel_h_mm <= 0

            panel_y_mm       = face_offset_mm + (wall_depth_mm - panel_t_mm) / 2.0  # <-- Centre panel inside lining depth
            origin_mm        = [lining_t_mm, panel_y_mm, floor_clear_mm]
            size_mm          = [panel_w_mm, panel_t_mm, panel_h_mm]

            DebugTools.na_debug_geometry("Build panel: w=#{panel_w_mm}mm h=#{panel_h_mm}mm t=#{panel_t_mm}mm")
            GeometryHelpers.na_create_door_panel_solid(entities, origin_mm, size_mm, material)
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - 2D Door Swing
# -----------------------------------------------------------------------------

        # FUNCTION | Build the 2D Door Swing Arc Group
        # ------------------------------------------------------------
        # The swing pivots around the hinge edge of the door panel and
        # arcs to the open position. Rendered as 2D linework on the
        # :door_swing tag (DataLib: 02__Linetype__DoorSwings).
        #
        # @param config [Hash] Door configuration
        # @param entities [Sketchup::Entities] Target entities (e.g. MOD group)
        # @return [Sketchup::Group, nil]
        def self.na_build_swing(config, entities)
            opening_w_mm    = config["Na__DoorConfig__OpeningWidth_mm"].to_f
            wall_depth_mm   = config["Na__DoorConfig__WallDepth_mm"].to_f
            lining_t_mm     = config["Na__DoorConfig__LiningThickness_mm"].to_f
            panel_t_mm      = config["Na__DoorConfig__PanelThickness_mm"].to_f
            face_offset_mm  = config["Na__DoorConfig__LiningFaceOffset_mm"].to_f
            swing_side      = (config["Na__DoorConfig__SwingSide"] || "Left").downcase.to_sym
            swing_direction = (config["Na__DoorConfig__SwingDirection"] || "Inward").downcase.to_sym

            inner_w_mm      = opening_w_mm - 2 * lining_t_mm
            radius_mm       = inner_w_mm                                          # <-- Swing radius = panel width
            return nil if radius_mm <= 0

            hinge_x_mm      = (swing_side == :left) ? lining_t_mm : (opening_w_mm - lining_t_mm)
            hinge_y_mm      = face_offset_mm + (wall_depth_mm - panel_t_mm) / 2.0  # <-- Match panel centre
            hinge_pt_mm     = [hinge_x_mm, hinge_y_mm]

            DebugTools.na_debug_geometry("Build swing: side=#{swing_side} dir=#{swing_direction} r=#{radius_mm}mm")
            GeometryHelpers.na_build_2d_swing_arc(entities, hinge_pt_mm, radius_mm, swing_side, swing_direction)
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__GeometryBuilders
end # module Na__InteriorDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
