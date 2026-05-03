# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - GENERIC BOX PRIMITIVE
# =============================================================================
#
# FILE       : Na__AssemblyStudio__GeometryHelpers__Box__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__GeometryHelpers
# MODULE     : Na__Box
# AUTHOR     : Noble Architecture
# PURPOSE    : Single, app-wide implementation of na_create_grouped_box.
#              Consolidates implementations that formerly lived in Window and
#              Interior Door systems.
#
# DESCRIPTION:
# - Creates a SketchUp group enclosing an axis-aligned box at (x,y,z).
# - Reverses any inward-facing normals so all six faces face outward from
#   the lump centre before optional material assignment.
#
# CONTRACT   : Coordinates and dimensions are SketchUp inches. Material is
#              optional — nil preserves SketchUp defaults on faces.
#
# NAMING CONVENTION:
# - All module / method identifiers use Na__GeometryHelpers / na_ prefixes.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'

module Na__AssemblyStudio
    module Na__GeometryHelpers
        module Na__Box

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

            DebugTools = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Grouped Box — Public API
# -----------------------------------------------------------------------------

            # FUNCTION | Create a Named Box Group with Outward-Facing Normals
            # ------------------------------------------------------------
            # All eight corners are computed at final coordinates and the six
            # faces are reversed if their normals point inward. Optional
            # material is applied to front and back of each face.
            #
            # @param entities [Sketchup::Entities] Parent entities collection
            # @param group_name [String] Display name on the group
            # @param x, y, z [Float] Origin (SketchUp inches)
            # @param width, depth, height [Float] Extents (inches)
            # @param material [Sketchup::Material, nil] Optional face material
            # @return [Sketchup::Group, nil] The group or nil if degenerate
            def self.na_create_grouped_box(entities, group_name, x, y, z, width, depth, height, material = nil)
                return nil if width <= 0 || depth <= 0 || height <= 0

                group           = entities.add_group
                group.name      = group_name
                group_entities  = group.entities

                p1 = Geom::Point3d.new(x,           y,           z)
                p2 = Geom::Point3d.new(x + width,   y,           z)
                p3 = Geom::Point3d.new(x + width,   y + depth,   z)
                p4 = Geom::Point3d.new(x,           y + depth,   z)
                p5 = Geom::Point3d.new(x,           y,           z + height)
                p6 = Geom::Point3d.new(x + width,   y,           z + height)
                p7 = Geom::Point3d.new(x + width,   y + depth,   z + height)
                p8 = Geom::Point3d.new(x,           y + depth,   z + height)

                box_centre = Geom::Point3d.new(
                    x + width  / 2.0,
                    y + depth  / 2.0,
                    z + height / 2.0
                )

                faces = []
                faces << group_entities.add_face(p4, p3, p2, p1)
                faces << group_entities.add_face(p5, p6, p7, p8)
                faces << group_entities.add_face(p1, p2, p6, p5)
                faces << group_entities.add_face(p3, p4, p8, p7)
                faces << group_entities.add_face(p4, p1, p5, p8)
                faces << group_entities.add_face(p2, p3, p7, p6)

                faces.compact.each do |face|
                    next unless face.valid?
                    outward_vec = face.bounds.center - box_centre
                    face.reverse! if outward_vec % face.normal < 0
                end

                if material
                    faces.compact.each do |f|
                        next unless f.valid?
                        f.material      = material
                        f.back_material = material
                    end
                end

                DebugTools.na_debug_geometry("Created grouped box: #{group_name}")
                group
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

        end
    end
end
