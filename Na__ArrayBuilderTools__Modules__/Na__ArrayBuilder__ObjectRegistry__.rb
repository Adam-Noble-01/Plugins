# =============================================================================
# NA ARRAY BUILDER TOOLS - OBJECT REGISTRY
# =============================================================================
#
# FILE       : Na__ArrayBuilder__ObjectRegistry__.rb
# NAMESPACE  : Na__ArrayBuilderTools::Na__ArrayBuilder__ObjectRegistry
# AUTHOR     : Noble Architecture
# PURPOSE    : In-memory store for the user-picked source object used by
#              the 'object' array type. Holds a reference to the picked
#              ComponentDefinition, a display name, the picked instance's
#              per-axis scale, and exposes derived placement info (scaled
#              bounds, anchor offsets) for the dialog UI, the preview
#              maths and the geometry builder.
# CREATED    : 2026
# VERSION    : 0.1.0
#
# DESCRIPTION:
# - Single-responsibility module: state container only, no UI/tool logic.
# - Both Sketchup::Group and Sketchup::ComponentInstance are normalised
#   to a single Sketchup::ComponentDefinition (Group#definition, SU 2018+).
# - The picked INSTANCE's per-axis scale (transformation axis lengths) is
#   captured at pick time so the arrayed copies match the size the user
#   actually picked, not the raw definition size. Mirrored / sheared
#   instances are not reproduced (scale magnitudes only).
# - Bounds use the definition's local-axis bounding box; under the
#   official BoundingBox API the method names are counter-intuitive:
#     width  -> X extent  (forward along path, local +X)
#     height -> Y extent  (lateral,            local +Y)
#     depth  -> Z extent  (vertical,           local +Z)
#
# =============================================================================

require 'sketchup.rb'

module Na__ArrayBuilderTools
    module Na__ArrayBuilder__ObjectRegistry

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_INCH_TO_MM = 25.4

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module State
# -----------------------------------------------------------------------------

        @na_definition   = nil
        @na_display_name = ''
        @na_scale        = [1.0, 1.0, 1.0]

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Mutators
# -----------------------------------------------------------------------------

        # FUNCTION | Store the Picked Component Definition
        # ------------------------------------------------------------
        # @param component_def [Sketchup::ComponentDefinition] Source definition
        # @param display_name  [String] Human-readable label for the dialog
        # @param scale         [Array<Float>] Per-axis scale of the picked
        #                      instance's transformation (defaults to 1:1:1)
        def self.Na__Registry__SetDefinition(component_def, display_name, scale = [1.0, 1.0, 1.0])
            @na_definition   = component_def
            @na_display_name = display_name.to_s
            @na_scale        = self.Na__Registry__SanitiseScale(scale)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Clear the Stored Definition
        # ------------------------------------------------------------
        def self.Na__Registry__Clear
            @na_definition   = nil
            @na_display_name = ''
            @na_scale        = [1.0, 1.0, 1.0]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Sanitise a Per-Axis Scale Triplet
        # ------------------------------------------------------------
        # Degenerate (near-zero) or malformed inputs fall back to 1.0 so
        # the placement transform can never collapse.
        def self.Na__Registry__SanitiseScale(scale)
            values = Array(scale).map(&:to_f)
            return [1.0, 1.0, 1.0] if values.length != 3
            values.map { |s| s.abs < 1.0e-9 ? 1.0 : s.abs }
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Accessors
# -----------------------------------------------------------------------------

        # FUNCTION | Get Stored Component Definition
        # ------------------------------------------------------------
        # @return [Sketchup::ComponentDefinition, nil]
        def self.Na__Registry__GetDefinition
            @na_definition
        end
        # ---------------------------------------------------------------

        # FUNCTION | Get Stored Display Name
        # ------------------------------------------------------------
        # @return [String]
        def self.Na__Registry__GetDisplayName
            @na_display_name
        end
        # ---------------------------------------------------------------

        # FUNCTION | Validate Stored Definition Is Still Usable
        # ------------------------------------------------------------
        # @return [Boolean] true when a definition is set and not deleted
        def self.Na__Registry__IsValid?
            !@na_definition.nil? && @na_definition.valid?
        end
        # ---------------------------------------------------------------

        # FUNCTION | Get Full Placement Info (Scaled, in Inches)
        # ------------------------------------------------------------
        # Everything the preview maths and the geometry builder need to
        # place the unit by its bounding-box faces:
        #   :definition    -> the source ComponentDefinition
        #   :scale         -> [sx, sy, sz] captured at pick time
        #   :width/:depth/:height -> scaled bbox spans (X / Y / Z)
        #   :scaled_min_x  -> scaled X of the leading bbox face
        #   :scaled_min_y / :scaled_max_y -> scaled lateral bbox faces
        #   :scaled_min_z / :scaled_max_z -> scaled vertical bbox faces
        #   :scaled_center -> scaled bbox centre (Geom::Point3d)
        # All values are in definition-local axes, pre-multiplied by the
        # captured scale. Returns nil when no valid definition is stored.
        def self.Na__Registry__GetPlacementInfo
            return nil unless self.Na__Registry__IsValid?

            bb = @na_definition.bounds
            return nil if bb.nil? || bb.empty?

            sx, sy, sz = @na_scale
            min = bb.min
            max = bb.max

            {
                definition:    @na_definition,
                scale:         @na_scale.dup,
                width:         (max.x - min.x) * sx,
                depth:         (max.y - min.y) * sy,
                height:        (max.z - min.z) * sz,
                scaled_min_x:  min.x * sx,
                scaled_min_y:  min.y * sy,
                scaled_max_y:  max.y * sy,
                scaled_min_z:  min.z * sz,
                scaled_max_z:  max.z * sz,
                scaled_center: Geom::Point3d.new(
                    (min.x + max.x) * 0.5 * sx,
                    (min.y + max.y) * 0.5 * sy,
                    (min.z + max.z) * 0.5 * sz
                )
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Get Derived Bounding-Box Dimensions in Millimetres
        # ------------------------------------------------------------
        # Scaled spans converted to mm, mapped onto the array-builder's
        # existing config keys so the dialog and the path-tool maths can
        # reuse the same fields. Returns nil when no valid definition is
        # stored.
        #
        # @return [Hash{Symbol => Float}, nil]
        def self.Na__Registry__GetBoundsMm
            info = self.Na__Registry__GetPlacementInfo
            return nil unless info

            {
                unit_width_mm:  info[:width]  * NA_INCH_TO_MM,
                unit_depth_mm:  info[:depth]  * NA_INCH_TO_MM,
                unit_height_mm: info[:height] * NA_INCH_TO_MM
            }
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__ArrayBuilder__ObjectRegistry
end # module Na__ArrayBuilderTools

# =============================================================================
# END OF FILE
# =============================================================================
