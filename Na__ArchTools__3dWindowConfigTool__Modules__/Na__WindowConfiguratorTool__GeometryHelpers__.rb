# =============================================================================
# NA WINDOW CONFIGURATOR TOOL - GEOMETRY HELPERS
# =============================================================================
#
# FILE       : Na__WindowConfiguratorTool__GeometryHelpers__.rb
# NAMESPACE  : Na__WindowConfiguratorTool
# MODULE     : Na__GeometryHelpers
# AUTHOR     : Noble Architecture
# PURPOSE    : Helper functions for creating grouped window geometry elements
# CREATED    : 2026
# VERSION    : 0.2.0
#
# DESCRIPTION:
# - Provides helper functions for creating named groups for window elements
# - Each window piece (rail, stile, mullion, etc.) is wrapped in its own group
# - Enables easy identification and manipulation of individual elements
# - Supports face orientation correction for all created geometry
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix
# - Group names follow pattern: "Na_{ElementType}_{SubPart}"
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__WindowConfiguratorTool__DebugTools__'

module Na__WindowConfiguratorTool
    module Na__GeometryHelpers

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools = Na__WindowConfiguratorTool::Na__DebugTools

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Group Creation Helpers
# -----------------------------------------------------------------------------

        # FUNCTION | Create Named Group
        # ------------------------------------------------------------
        # Creates a named group and yields to a block for adding geometry.
        # 
        # @param entities [Sketchup::Entities] Parent entities collection
        # @param name [String] Name for the group
        # @yield [Sketchup::Entities] The group's entities for adding geometry
        # @return [Sketchup::Group] The created group
        def self.na_create_named_group(entities, name)
            group = entities.add_group
            group.name = name
            yield group.entities if block_given?
            DebugTools.na_debug_geometry("Created group: #{name}")
            group
        end
        # ---------------------------------------------------------------

        # FUNCTION | Create Box in Named Group
        # ------------------------------------------------------------
        # Creates a box geometry inside a named group.
        # Uses the correct winding order for outward-facing normals.
        # 
        # @param entities [Sketchup::Entities] Parent entities collection
        # @param group_name [String] Name for the group
        # @param x [Float] X position (left edge)
        # @param y [Float] Y position (front edge)
        # @param z [Float] Z position (bottom edge)
        # @param width [Float] Width in X direction
        # @param depth [Float] Depth in Y direction
        # @param height [Float] Height in Z direction
        # @param material [Sketchup::Material] Material to apply
        # @return [Sketchup::Group] The created group containing the box
        def self.na_create_grouped_box(entities, group_name, x, y, z, width, depth, height, material)
            return nil if width <= 0 || depth <= 0 || height <= 0
            
            group = entities.add_group
            group.name = group_name
            group_entities = group.entities
            
            # Define all 8 corners of the box at FINAL coordinates
            p1 = Geom::Point3d.new(x, y, z)                          # Front-left-bottom
            p2 = Geom::Point3d.new(x + width, y, z)                  # Front-right-bottom
            p3 = Geom::Point3d.new(x + width, y + depth, z)          # Back-right-bottom
            p4 = Geom::Point3d.new(x, y + depth, z)                  # Back-left-bottom
            p5 = Geom::Point3d.new(x, y, z + height)                 # Front-left-top
            p6 = Geom::Point3d.new(x + width, y, z + height)         # Front-right-top
            p7 = Geom::Point3d.new(x + width, y + depth, z + height) # Back-right-top
            p8 = Geom::Point3d.new(x, y + depth, z + height)         # Back-left-top
            
            # Calculate box center for normal direction checking
            center = Geom::Point3d.new(x + width/2.0, y + depth/2.0, z + height/2.0)
            
            # Create all 6 faces - CCW winding when viewed from outside for outward normals
            faces = []
            faces << group_entities.add_face(p4, p3, p2, p1)  # Bottom
            faces << group_entities.add_face(p5, p6, p7, p8)  # Top
            faces << group_entities.add_face(p1, p2, p6, p5)  # Front
            faces << group_entities.add_face(p3, p4, p8, p7)  # Back
            faces << group_entities.add_face(p4, p1, p5, p8)  # Left
            faces << group_entities.add_face(p2, p3, p7, p6)  # Right
            
            # Verify and fix face orientations - ensure normals point outward
            faces.compact.each do |face|
                next unless face.valid?
                face_center = face.bounds.center
                face_normal = face.normal
                outward_vec = face_center - center
                face.reverse! if outward_vec % face_normal < 0
            end
            
            # Apply material
            if material
                faces.compact.each do |f|
                    next unless f.valid?
                    f.material = material
                    f.back_material = material
                end
            end
            
            DebugTools.na_debug_geometry("Created grouped box: #{group_name}")
            group
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Frame Element Helpers
# -----------------------------------------------------------------------------

        # FUNCTION | Create Frame Stile (Vertical Member)
        # ------------------------------------------------------------
        def self.na_create_frame_stile(entities, side, x, y, z, thickness, depth, height, material)
            group_name = "Na_Frame_#{side}_Stile"
            na_create_grouped_box(entities, group_name, x, y, z, thickness, depth, height, material)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Create Frame Rail (Horizontal Member)
        # ------------------------------------------------------------
        def self.na_create_frame_rail(entities, position, x, y, z, width, depth, thickness, material)
            group_name = "Na_Frame_#{position}_Rail"
            na_create_grouped_box(entities, group_name, x, y, z, width, depth, thickness, material)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Create Mullion
        # ------------------------------------------------------------
        def self.na_create_mullion(entities, index, x, y, z, width, depth, height, material)
            group_name = "Na_Mullion_#{index}"
            na_create_grouped_box(entities, group_name, x, y, z, width, depth, height, material)
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Casement Element Helpers
# -----------------------------------------------------------------------------

        # FUNCTION | Create Casement Stile (Vertical Member)
        # ------------------------------------------------------------
        def self.na_create_casement_stile(entities, opening_index, side, x, y, z, thickness, depth, height, material)
            group_name = "Na_Casement_#{opening_index}_#{side}_Stile"
            na_create_grouped_box(entities, group_name, x, y, z, thickness, depth, height, material)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Create Casement Rail (Horizontal Member)
        # ------------------------------------------------------------
        def self.na_create_casement_rail(entities, opening_index, position, x, y, z, width, depth, thickness, material)
            group_name = "Na_Casement_#{opening_index}_#{position}_Rail"
            na_create_grouped_box(entities, group_name, x, y, z, width, depth, thickness, material)
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Glazing Element Helpers
# -----------------------------------------------------------------------------

        # FUNCTION | Create Glass Pane
        # ------------------------------------------------------------
        def self.na_create_glass_pane(entities, opening_index, x, y, z, width, depth, height, material)
            group_name = "Na_Glass_#{opening_index}"
            na_create_grouped_box(entities, group_name, x, y, z, width, depth, height, material)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Create Horizontal Glaze Bar
        # ------------------------------------------------------------
        def self.na_create_glaze_bar_horizontal(entities, opening_index, bar_index, x, y, z, width, depth, height, material)
            group_name = "Na_GlazeBar_#{opening_index}_H#{bar_index}"
            na_create_grouped_box(entities, group_name, x, y, z, width, depth, height, material)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Create Vertical Glaze Bar
        # ------------------------------------------------------------
        def self.na_create_glaze_bar_vertical(entities, opening_index, bar_index, x, y, z, width, depth, height, material)
            group_name = "Na_GlazeBar_#{opening_index}_V#{bar_index}"
            na_create_grouped_box(entities, group_name, x, y, z, width, depth, height, material)
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Cill Element Helper
# -----------------------------------------------------------------------------

        # FUNCTION | Create Cill
        # ------------------------------------------------------------
        def self.na_create_cill(entities, x, y, z, width, depth, height, material)
            group_name = "Na_Cill"
            na_create_grouped_box(entities, group_name, x, y, z, width, depth, height, material)
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__GeometryHelpers
end # module Na__WindowConfiguratorTool

# =============================================================================
# END OF FILE
# =============================================================================
