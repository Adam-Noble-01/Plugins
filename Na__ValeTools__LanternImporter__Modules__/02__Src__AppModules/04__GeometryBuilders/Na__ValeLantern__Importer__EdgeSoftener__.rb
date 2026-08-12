# =============================================================================
# VALE LANTERN IMPORTER - EDGE SOFTENER
# =============================================================================
#
# FILE       : Na__ValeLantern__Importer__EdgeSoftener__.rb
# NAMESPACE  : Na__ValeLantern::Na__Importer
# MODULE     : Na__EdgeSoftener
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Soften and smooth the shallow edges of one built prism, from the
#              per family rule in the plugin config.
#
# DESCRIPTION:
# - This is SketchUp's own Soften Edges panel, applied at build time from a table
#   instead of by hand on a selection. Nothing here computes geometry; it reads
#   the angle between two faces that already exist and sets two flags.
# - Runs on a component definition's entities, so where four hip beams share one
#   definition the pass runs once and all four are softened.
#
# -----------------------------------------------------------------------------
#
# WHAT PROBLEM THIS SOLVES:
#
# An extruded aluminium section is not flat. A glaze bar cap has a shallow crown,
# a lead flashing has a rolled edge, a cornice has a curve, and each of those
# arrives from the exporter as a run of short straight facets - because that is
# what a swept polyline section IS. add_face gives every one of those facet
# boundaries SketchUp's default hard, visible edge, so a member that should read
# as one smooth surface reads as a bundle of pinstripes running its whole length.
#
# The coplanar merge pass upstream cannot help: those facets are genuinely not
# coplanar, they are a few degrees apart. Erasing their edges would collapse the
# curve. Softening them keeps the geometry and stops drawing the lines.
#
# -----------------------------------------------------------------------------
#
# WHY BOTH soft AND smooth, AND WHY THAT IS NOT ONE THING:
#
# SketchUp's three edge flags are commonly conflated because the Soften Edges
# slider writes two of them together. They are not the same:
#
#   soft     the edge is not drawn AND its two faces merge into one Surface
#            entity. Does not by itself change how the surface is shaded, so a
#            soft-only curve is a faceted surface with no lines on it - the
#            facets still read as flat panels catching light differently.
#   smooth   the shading blends across the edge. ON ITS OWN THE EDGE STAYS
#            VISIBLE; SketchUp only hides it as well because the slider sets
#            soft at the same time.
#   hidden   Edit > Hide. Not drawn, no surface merge, shading unchanged.
#
# So removing the lines needs soft, and making the result look like a curve
# rather than a fan of flats needs smooth. The config carries them as two fields
# because they are two decisions, and SmoothNormals mirrors the panel's own
# checkbox.
#
# -----------------------------------------------------------------------------
#
# WHY THIS RUNS LAST, AFTER MERGE AND ORIENT:
#
# Two hard dependencies on the passes before it, both in the prism builder:
#
#   1  The coplanar MERGE must have run first. Otherwise the vertex-every-few-
#      millimetres edges down a genuinely flat face are still there, and this
#      pass would softly hide them instead of the merge erasing them outright -
#      leaving a Surface entity spanning a flat face for no reason, which makes
#      every later selection and push-pull behave oddly.
#
#   2  The ORIENT pass must have run first. The angle between two face normals
#      only means the real dihedral angle when both faces are wound the same way
#      out of the solid. On a shell that came out inside in, half the normals
#      point the other way and a shallow 5 degree facet boundary reads as 175
#      degrees - so nothing would be softened, or the wrong things would be.
#
# NAMING CONVENTION:
# - Importer namespace Na__Importer / na_ prefixes.
#
# =============================================================================

require 'sketchup.rb'

module Na__ValeLantern
    module Na__Importer
        module Na__EdgeSoftener

# -----------------------------------------------------------------------------
# REGION | Module References and Constants
# -----------------------------------------------------------------------------

            DebugTools   = Na__ValeLantern::Na__Importer::Na__DebugTools
            ConfigLoader = Na__ValeLantern::Na__Importer::Na__ConfigLoader

            NA_COPLANAR_DOT_LIMIT = 0.99999                                                         # <-- Two normals above this are the same plane, about 0.26 degrees apart
            NA_DEGREES_TO_RADIANS = Math::PI / 180.0
            NA_MAX_ANGLE_DEGREES  = 179.9                                                           # <-- Above this every edge in the shell qualifies, which is never meant

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Softening — Public API
# -----------------------------------------------------------------------------

            # FUNCTION | Soften the shallow edges of one entities collection
            # ------------------------------------------------------------
            # @param entities [Sketchup::Entities] A built prism's own entities
            # @param rule [Hash] One row from the config's SoftenEdges.Rules
            # @return [Integer] How many edges were softened
            def self.na_soften(entities, rule)
                return 0 unless entities
                return 0 unless rule.is_a?(Hash)
                return 0 unless rule['Soften'] == true

                limit_cos = na_angle_limit_cosine(rule['AngleDegrees'])
                return 0 if limit_cos.nil?

                set_smooth      = rule.fetch('SmoothNormals', true) != false
                allow_coplanar  = rule['SoftenCoplanar'] == true
                softened        = 0

                entities.grep(Sketchup::Edge).each do |edge|
                    next unless edge.valid?

                    faces = edge.faces
                    next unless faces.length == 2                                                   # <-- A naked edge has nothing to blend into; three faces is not a surface
                    next unless faces[0].valid? && faces[1].valid?

                    dot = na_normal_dot(faces[0], faces[1])
                    next if dot.nil?
                    next if dot > NA_COPLANAR_DOT_LIMIT && !allow_coplanar                          # <-- The merge pass owns coplanar edges
                    next if dot < limit_cos                                                         # <-- Sharper than the threshold: a real arris, left hard

                    edge.soft   = true
                    edge.smooth = true if set_smooth
                    softened   += 1
                end

                softened

            rescue StandardError => e
                DebugTools.na_detail("Edge softening refused: #{e.class}: #{e.message}")
                0
            end
            # ---------------------------------------------------------------

            # FUNCTION | Soften one entities collection from its part's TagKey
            # ------------------------------------------------------------
            # The form the prism builder calls: hand it the part's tag key and it
            # finds the rule itself, so no builder carries a copy of the table.
            #
            # @param entities [Sketchup::Entities] A built prism's own entities
            # @param tag_key [String, nil] The part's TagKey
            # @return [Integer] How many edges were softened
            def self.na_soften_for_tag(entities, tag_key)
                rule = ConfigLoader.na_soften_rule_for(tag_key)
                return 0 unless rule.is_a?(Hash) && rule['Soften'] == true

                softened = na_soften(entities, rule)
                if softened > 0 && DebugTools.na_verbose?
                    DebugTools.na_detail(
                        "Softened #{softened} edge(s) at #{rule['AngleDegrees']} deg for '#{tag_key}'"
                    )
                end
                softened
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal — Angle Arithmetic
# -----------------------------------------------------------------------------

            # HELPER FUNCTION | The dot product an edge must beat to be softened
            # ------------------------------------------------------------
            # The rule is stated in degrees between the two face normals, exactly
            # as the Soften Edges panel reads it. Comparing cosines rather than
            # angles means one cos() here instead of an acos() per edge, and a
            # divided lantern has tens of thousands of edges.
            #
            # cos is monotonically DECREASING over 0 to 180 degrees, so a smaller
            # angle is a LARGER dot product - which is why the test at the call
            # site rejects a dot BELOW the limit.
            #
            # @return [Float, nil] nil when the angle is not a usable threshold
            def self.na_angle_limit_cosine(angle_degrees)
                angle = angle_degrees.to_f
                return nil unless angle > 0.0
                return nil if angle > NA_MAX_ANGLE_DEGREES

                Math.cos(angle * NA_DEGREES_TO_RADIANS)
            end
            private_class_method :na_angle_limit_cosine

            # HELPER FUNCTION | Dot product of two face normals
            # ------------------------------------------------------------
            def self.na_normal_dot(face_a, face_b)
                face_a.normal.dot(face_b.normal)
            rescue StandardError
                nil
            end
            private_class_method :na_normal_dot

# endregion -------------------------------------------------------------------

        end
    end
end
