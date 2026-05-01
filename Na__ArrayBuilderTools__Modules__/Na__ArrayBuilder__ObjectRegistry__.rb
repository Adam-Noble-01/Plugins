# =============================================================================
# NA ARRAY BUILDER TOOLS - OBJECT REGISTRY
# =============================================================================
#
# FILE       : Na__ArrayBuilder__ObjectRegistry__.rb
# NAMESPACE  : Na__ArrayBuilderTools::Na__ArrayBuilder__ObjectRegistry
# AUTHOR     : Noble Architecture
# PURPOSE    : In-memory store for the user-picked source object used by
#              the 'object' array type. Holds a reference to the picked
#              ComponentDefinition, a display name, and exposes derived
#              bounding-box dimensions in millimetres for the dialog UI
#              and the path-tool preview maths.
# CREATED    : 2026
# VERSION    : 0.0.3
#
# DESCRIPTION:
# - Single-responsibility module: state container only, no UI/tool logic.
# - Both Sketchup::Group and Sketchup::ComponentInstance are normalised
#   to a single Sketchup::ComponentDefinition (Group#definition, SU 2018+).
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

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Mutators
# -----------------------------------------------------------------------------

        # FUNCTION | Store the Picked Component Definition
        # ------------------------------------------------------------
        # @param component_def [Sketchup::ComponentDefinition] Source definition
        # @param display_name  [String] Human-readable label for the dialog
        def self.Na__Registry__SetDefinition(component_def, display_name)
            @na_definition   = component_def
            @na_display_name = display_name.to_s
        end
        # ---------------------------------------------------------------

        # FUNCTION | Clear the Stored Definition
        # ------------------------------------------------------------
        def self.Na__Registry__Clear
            @na_definition   = nil
            @na_display_name = ''
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

        # FUNCTION | Get Derived Bounding-Box Dimensions in Millimetres
        # ------------------------------------------------------------
        # Returns the current definition's local bbox spans converted to mm,
        # already mapped onto the array-builder's existing config keys so
        # the path-tool maths can reuse the same fields. Returns nil when
        # no valid definition is stored.
        #
        # @return [Hash{Symbol => Float}, nil]
        #   :unit_width_mm  -> bounds.width  (X)
        #   :unit_depth_mm  -> bounds.height (Y)
        #   :unit_height_mm -> bounds.depth  (Z)
        def self.Na__Registry__GetBoundsMm
            return nil unless self.Na__Registry__IsValid?

            bb = @na_definition.bounds
            return nil if bb.nil? || bb.empty?

            {
                unit_width_mm:  (bb.width  * NA_INCH_TO_MM).to_f,
                unit_depth_mm:  (bb.height * NA_INCH_TO_MM).to_f,
                unit_height_mm: (bb.depth  * NA_INCH_TO_MM).to_f
            }
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__ArrayBuilder__ObjectRegistry
end # module Na__ArrayBuilderTools

# =============================================================================
# END OF FILE
# =============================================================================
