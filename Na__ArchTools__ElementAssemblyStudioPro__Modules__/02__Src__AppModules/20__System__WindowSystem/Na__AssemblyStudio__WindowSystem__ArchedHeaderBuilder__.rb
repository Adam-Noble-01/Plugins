# frozen_string_literal: true

# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - WINDOW SYSTEM - ARCHED HEADER BUILDER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__WindowSystem__ArchedHeaderBuilder__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__WindowSystem
# MODULE     : Na__ArchedHeaderBuilder
# AUTHOR     : Noble Architecture
# PURPOSE    : Arched header rails for window casements and exterior door
#              leaves: the arc, the outlines it makes, and the solids built
#              from them. Shared by the window engine, all four door composers
#              and the DXF exporters.
# CREATED    : 03-Nov-2026
#
# DESCRIPTION:
# - The top of the rail stays flat and the glass takes the arched head. The
#   crown of the arc sits where the flat glass top was, so the rail keeps its
#   set depth at the centre. The arc falls away from there by the Arch Height,
#   and the rail deepens towards the stiles to fill the corners.
# - A SEGMENTAL arc (a rise under half the glass width) keeps the joinery rule:
#   stiles full height, the rail between them.
# - A TRUE ARCH (a rise of half the glass width, a semicircle) meets the stiles
#   at a tangent, which would leave a rail between them a long feather edge. So
#   it makes a special head rail: one piece across the full casement width,
#   sitting on stiles that stop at the springing line.
# - An arch never takes the glass below its least side height, so a short pane
#   gets the tallest segmental arc that fits it.
# - The layout functions work in the caller's units: inches for windows,
#   millimetres for doors. Mirrored in JS by Na__ArchMath.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'

module Na__AssemblyStudio
module Na__WindowSystem
    module Na__ArchedHeaderBuilder

# -----------------------------------------------------------------------------
# REGION | Module References & Constants
# -----------------------------------------------------------------------------

        DebugTools = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools

        NA_ARCH_MIN_RISE_MM       = 20.0                                       # <-- The slider's floor
        NA_ARCH_DEFAULT_RISE_MM   = 60.0                                       # <-- A slight segmental arc
        NA_ARCH_SEGMENT_CHOICES   = [12, 24, 48].freeze
        NA_ARCH_MIN_SIDE_MM       = 20.0                                       # <-- Glass kept at each side, under the springing line
        NA_ARCH_MIN_LIMIT_MM      = 1.0                                        # <-- Less room than this: no arch at all
        NA_ARCH_TRUE_TOLERANCE_MM = 0.5                                        # <-- This close to half the width reads as a true arch
        NA_ARCH_SMOOTH_ANGLE_DEG  = 22.0                                       # <-- The soften limit the Gothic tracery uses
        NA_MM_TO_INCH             = 1.0 / 25.4

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Reading the Settings
# -----------------------------------------------------------------------------

        # FUNCTION | Read the Arched Header Settings From a Config
        # ------------------------------------------------------------
        # An absent switch reads as off, so every element saved before the
        # feature existed rebuilds as it was.
        #
        # @param config [Hash] Window or door configuration
        # @param prefix [String] '' for windows, 'single_door_' and so on for doors
        # @return [Hash, nil] { rise_mm:, true_arch:, segments: }, nil when off
        def self.na_settings(config, prefix = '')
            return nil unless config.is_a?(Hash) && config["#{prefix}arched_header_enabled"] == true

            segments = config["#{prefix}arched_header_segments"].to_i
            {
                rise_mm:   [(config["#{prefix}arched_header_height_mm"] || NA_ARCH_DEFAULT_RISE_MM).to_f, NA_ARCH_MIN_RISE_MM].max,
                true_arch: config["#{prefix}arched_header_true_arch"] == true,
                segments:  NA_ARCH_SEGMENT_CHOICES.include?(segments) ? segments : NA_ARCH_SEGMENT_CHOICES.first
            }
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | The Arc
# -----------------------------------------------------------------------------

        # FUNCTION | Resolve the Arch Over One Glass Rectangle
        # ------------------------------------------------------------
        # Mirrors Na__ArchMath.na_resolve.
        #
        # @param settings [Hash, nil] From na_settings
        # @param x, z, width, height [Float] The glass as if it were flat
        # @param units_per_mm [Float] 1.0 when the caller works in millimetres, NA_MM_TO_INCH in inches
        # @return [Hash, nil] Nil when there is no room for an arch
        def self.na_resolve(settings, x, z, width, height, units_per_mm = 1.0)
            return nil unless settings && width.to_f > 0 && height.to_f > 0

            half  = width.to_f / 2.0
            limit = [half, height.to_f - (NA_ARCH_MIN_SIDE_MM * units_per_mm)].min
            return nil unless limit >= NA_ARCH_MIN_LIMIT_MM * units_per_mm

            wanted  = settings[:true_arch] ? half : settings[:rise_mm] * units_per_mm
            rise    = [wanted, limit].min
            radius  = ((half * half) + (rise * rise)) / (2.0 * rise)
            crown_z = z.to_f + height.to_f

            arch = {
                left:        x.to_f,
                right:       x.to_f + width.to_f,
                crown_z:     crown_z,
                springing_z: crown_z - rise,
                rise:        rise,
                radius:      radius,
                centre_x:    x.to_f + half,
                centre_z:    crown_z - radius,
                segments:    settings[:segments],
                true_arch:   rise >= half - (NA_ARCH_TRUE_TOLERANCE_MM * units_per_mm)
            }
            arch[:points] = na_arc_points(arch)
            arch
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Tessellate the Arc, Left Springing to Right Springing
        # ------------------------------------------------------------
        # The segment count is even, so one point is the crown itself and the
        # rail's retained depth is exact.
        def self.na_arc_points(arch)
            half       = (arch[:right] - arch[:left]) / 2.0
            half_angle = Math.atan2(half, arch[:radius] - arch[:rise])
            count      = arch[:segments]
            points = (0..count).map do |index|
                angle = half_angle * ((2.0 * index / count) - 1.0)
                [arch[:centre_x] + (arch[:radius] * Math.sin(angle)), arch[:centre_z] + (arch[:radius] * Math.cos(angle))]
            end
            points[0]  = [arch[:left], arch[:springing_z]]
            points[-1] = [arch[:right], arch[:springing_z]]
            points
        end
        private_class_method :na_arc_points
        # ---------------------------------------------------------------

        # FUNCTION | The Same Arch in Other Units
        # ------------------------------------------------------------
        # Door layouts resolve in millimetres; their solids and lead build in
        # inches.
        def self.na_scale(arch, factor)
            return nil unless arch

            arch.merge(
                left:        arch[:left] * factor,
                right:       arch[:right] * factor,
                crown_z:     arch[:crown_z] * factor,
                springing_z: arch[:springing_z] * factor,
                rise:        arch[:rise] * factor,
                radius:      arch[:radius] * factor,
                centre_x:    arch[:centre_x] * factor,
                centre_z:    arch[:centre_z] * factor,
                points:      arch[:points].map { |x, z| [x * factor, z * factor] }
            )
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Trimming Members to the Arch
# -----------------------------------------------------------------------------

        # FUNCTION | Highest Point of the Arc Over a Span of X
        # ------------------------------------------------------------
        # Measured on the true circle, which is never below the facets, so a
        # bar stopped here runs just into the rail and leaves no gap.
        def self.na_top_over(arch, left_x, right_x)
            centre  = arch[:centre_x]
            nearest = if left_x > centre then left_x - centre
                      elsif right_x < centre then centre - right_x
                      else 0.0
                      end
            return arch[:springing_z] if nearest >= (arch[:right] - arch[:left]) / 2.0

            arch[:centre_z] + Math.sqrt([(arch[:radius] * arch[:radius]) - (nearest * nearest), 0.0].max)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Height of a Vertical Member Under the Arch
        # ------------------------------------------------------------
        # @return [Float, nil] The member's height, nil when the arch leaves none
        def self.na_trim_height(arch, left_x, right_x, start_z, height)
            return height unless arch

            trimmed = [na_top_over(arch, left_x, right_x) - start_z, height].min
            trimmed > 0 ? trimmed : nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Run of a Horizontal Member Under the Arch
        # ------------------------------------------------------------
        # bottom_z is the member's underside, where the arch is widest, so its
        # ends run just into the rail.
        #
        # @return [Array, nil] [start_x, width], nil when it lies above the arch
        def self.na_trim_run(arch, start_x, width, bottom_z)
            return [start_x, width] unless arch
            return [start_x, width] if bottom_z <= arch[:springing_z]
            return nil if bottom_z >= arch[:crown_z]

            drop     = bottom_z - arch[:centre_z]
            half_run = Math.sqrt([(arch[:radius] * arch[:radius]) - (drop * drop), 0.0].max)
            left     = [start_x, arch[:centre_x] - half_run].max
            right    = [start_x + width, arch[:centre_x] + half_run].min
            right > left ? [left, right - left] : nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Height of the Stiles Under the Head
        # ------------------------------------------------------------
        # A true arch's head rail sits on the stiles. A segmental rail fits
        # between them, so they stay full height.
        def self.na_stile_height(arch, bottom_z, full_height)
            return full_height unless arch && arch[:true_arch]

            arch[:springing_z] - bottom_z
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Outlines
# -----------------------------------------------------------------------------

        # FUNCTION | Outline of the Header Rail
        # ------------------------------------------------------------
        # Clockwise from the top left, seen from outside. The flat top, then
        # the arc back from right to left. A true arch's special head runs out
        # over the stiles along the springing line.
        #
        # @param outer_left, outer_right [Float] The casement or leaf's outer edges
        # @param top_z [Float] The top of the casement or leaf
        # @return [Array] [x, z] pairs
        def self.na_head_outline(arch, outer_left, outer_right, top_z)
            return [[arch[:left], top_z], [arch[:right], top_z]] + arch[:points].reverse unless arch[:true_arch]

            [[outer_left, top_z], [outer_right, top_z], [outer_right, arch[:springing_z]]] +
                arch[:points].reverse +
                [[outer_left, arch[:springing_z]]]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Outline of the Glass
        # ------------------------------------------------------------
        # @return [Array] [x, z] pairs, anticlockwise from the bottom left, seen from outside
        def self.na_glass_outline(arch, bottom_z)
            [[arch[:left], bottom_z], [arch[:right], bottom_z]] + arch[:points].reverse
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Solids
# -----------------------------------------------------------------------------

        # FUNCTION | Build the Header Rail
        # ------------------------------------------------------------
        # All arguments in inches. Group naming is the caller's, so the rail
        # keeps the name FuseParts and the edge painter already look for.
        def self.na_create_head(entities, group_name, arch, outer_left, outer_right, top_z, y, depth, material)
            na_create_prism(entities, group_name, na_head_outline(arch, outer_left, outer_right, top_z), y, depth, material)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Build the Glass
        # ------------------------------------------------------------
        # All arguments in inches.
        def self.na_create_glass(entities, group_name, arch, bottom_z, y, depth, material)
            na_create_prism(entities, group_name, na_glass_outline(arch, bottom_z), y, depth, material)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Build a Door Leaf's Header Rail From Its mm Layout
        # ------------------------------------------------------------
        def self.na_create_leaf_head(entities, group_name, arch_mm, leaf, material)
            na_create_head(
                entities, group_name, na_scale(arch_mm, NA_MM_TO_INCH),
                leaf[:origin_x_mm] * NA_MM_TO_INCH,
                (leaf[:origin_x_mm] + leaf[:width_mm]) * NA_MM_TO_INCH,
                (leaf[:origin_z_mm] + leaf[:height_mm]) * NA_MM_TO_INCH,
                leaf[:origin_y_mm] * NA_MM_TO_INCH,
                leaf[:thickness_mm] * NA_MM_TO_INCH,
                material
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | Build a Door Leaf's Glass From Its mm Layout
        # ------------------------------------------------------------
        def self.na_create_leaf_glass(entities, group_name, arch_mm, bottom_z_mm, y_mm, depth_mm, material)
            na_create_glass(
                entities, group_name, na_scale(arch_mm, NA_MM_TO_INCH),
                bottom_z_mm * NA_MM_TO_INCH, y_mm * NA_MM_TO_INCH, depth_mm * NA_MM_TO_INCH, material
            )
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Extrude an X-Z Outline Into a Solid Through +Y
        # ------------------------------------------------------------
        # Every face is drawn and then turned against the outward direction its
        # outline edge gives, as Na__GeometryHelpers.na_create_horned_cill does:
        # a box's "away from the centre" test is wrong on a curved soffit.
        def self.na_create_prism(entities, group_name, outline, y, depth, material)
            group = entities.add_group
            group.name = group_name
            group_entities = group.entities

            front = outline.map { |x, z| Geom::Point3d.new(x, y, z) }
            back  = outline.map { |x, z| Geom::Point3d.new(x, y + depth, z) }
            turn  = na_signed_area(outline) > 0 ? 1.0 : -1.0

            faces = [
                [group_entities.add_face(front), Geom::Vector3d.new(0, -1, 0)],
                [group_entities.add_face(back), Geom::Vector3d.new(0, 1, 0)]
            ]
            outline.each_index do |i|
                j = (i + 1) % outline.length
                faces << [group_entities.add_face(front[i], front[j], back[j], back[i]),
                          Geom::Vector3d.new(turn * (outline[j][1] - outline[i][1]), 0, turn * (outline[i][0] - outline[j][0]))]
            end

            faces.each do |face, outward|
                next unless face && face.valid?
                face.reverse! if face.normal % outward < 0
                next unless material
                face.material = material
                face.back_material = material
            end
            na_soften_arc_edges(group)

            DebugTools.na_debug_geometry("Created arched solid: #{group_name}")
            group
        end
        private_class_method :na_create_prism
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Signed Area of an X-Z Outline (Positive = Anticlockwise)
        # ------------------------------------------------------------
        def self.na_signed_area(outline)
            sum = 0.0
            outline.each_index do |i|
                x1, z1 = outline[i]
                x2, z2 = outline[(i + 1) % outline.length]
                sum += (x1 * z2) - (x2 * z1)
            end
            sum / 2.0
        end
        private_class_method :na_signed_area
        # ---------------------------------------------------------------

        # FUNCTION | Soften the Facets of an Arched Soffit
        # ------------------------------------------------------------
        # So the arc reads as a curve. Also run after Fuse Parts, whose boolean
        # results lose the flags. 12 segments on a semicircle is 15 degrees a
        # facet, inside the limit; the rail's square edges are well outside it.
        def self.na_soften_arc_edges(group)
            return unless group && group.valid?

            limit = NA_ARCH_SMOOTH_ANGLE_DEG * Math::PI / 180.0
            group.entities.grep(Sketchup::Edge).each do |edge|
                next unless edge.valid?
                faces = edge.faces
                next unless faces.length == 2
                next unless faces[0].normal.angle_between(faces[1].normal) <= limit

                edge.soft = true
                edge.smooth = true
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is This Group an Arched Solid (More Faces Than a Box)
        # ------------------------------------------------------------
        # Lets Fuse Parts skip the soften walk on square casements. Asked
        # before the boolean, which consumes the group.
        def self.na_arched_solid?(group)
            return false unless group && group.valid?

            group.entities.grep(Sketchup::Face).length > 6
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__ArchedHeaderBuilder
end # module Na__WindowSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
