# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - INTERIOR DOOR SYSTEM - PANEL DESIGN BUILDER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__InteriorDoorSystem__PanelDesignBuilder__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__InteriorDoorSystem
# MODULE     : Na__PanelDesignBuilder
# AUTHOR     : Noble Architecture
# PURPOSE    : Orchestrates the door panel design subsystem - reads the
#              configuration, dispatches to the requested style builder,
#              wraps the resulting linework in a tidy nested group, and
#              paints every edge with the canonical dark-grey edge colour.
# CREATED    : 03-May-2026
#
# DESCRIPTION:
# - Single public entry: na_build_panel_design(config, mod_entities).
# - Adds Na__DoorPanel__DesignContainer inside the MOD group with two
#   child groups: Na__PanelDesign__FrontFace + Na__PanelDesign__BackFace.
# - Each face group hosts the inner-perimeter rectangle (always) plus
#   the style-specific subdivisions, all as Sketchup::Edge instances
#   (no faces) so the door panel solid is never co-planar split.
# - Edge linework sits NA_FACE_PROJECTION_OFFSET_MM in front of / behind
#   the panel face (along Y) to avoid Z-fighting against the panel
#   solid in the SketchUp view.
# - All edges are painted with the resolved dark-grey edge colour
#   (MTE103__LineColour__DarkGrey__L40) via Na__EdgeColourManager.
#
# SUPPORTED STYLES (driven by Na__DoorConfig__PanelDesignStyle):
#   * "None"               -> design subsystem is skipped entirely
#   * "VerticalNarrow"     -> Na__PanelDesignStyles__VerticalNarrow
#   * "ClassicalSixPanel"  -> Na__PanelDesignStyles__ClassicalSixPanel
#   * "FourPanel"          -> Na__PanelDesignStyles__FourPanel
#   * "HorizontalThree"    -> Na__PanelDesignStyles__HorizontalThree
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../02__AppData/Na__AssemblyStudio__AppData__EdgeColourManager__'
require_relative 'Na__AssemblyStudio__InteriorDoorSystem__GeometryHelpers__'
require_relative 'Na__AssemblyStudio__InteriorDoorSystem__PanelDesignFrame__'
require_relative 'Na__AssemblyStudio__InteriorDoorSystem__PanelStyle__VerticalNarrow__'
require_relative 'Na__AssemblyStudio__InteriorDoorSystem__PanelStyle__ClassicalSix__'
require_relative 'Na__AssemblyStudio__InteriorDoorSystem__PanelStyle__FourPanel__'
require_relative 'Na__AssemblyStudio__InteriorDoorSystem__PanelStyle__HorizontalThree__'

module Na__AssemblyStudio
module Na__InteriorDoorSystem
    module Na__PanelDesignBuilder

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools         = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        EdgeColourManager  = Na__AssemblyStudio::Na__AppData::Na__EdgeColourManager
        GeometryHelpers    = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__GeometryHelpers
        PanelDesignFrame   = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__PanelDesignFrame
        StyleVerticalNarrow    = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__PanelDesignStyles__VerticalNarrow
        StyleClassicalSixPanel = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__PanelDesignStyles__ClassicalSixPanel
        StyleFourPanel         = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__PanelDesignStyles__FourPanel
        StyleHorizontalThree   = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__PanelDesignStyles__HorizontalThree

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

        # CONSTANTS | Group Names
        # ------------------------------------------------------------
        NA_GROUP_NAME_DESIGN_CONTAINER = "Na__DoorPanel__DesignContainer".freeze
        NA_GROUP_NAME_FRONT_FACE       = "Na__PanelDesign__FrontFace".freeze
        NA_GROUP_NAME_BACK_FACE        = "Na__PanelDesign__BackFace".freeze
        # ---------------------------------------------------------------

        # CONSTANTS | Anti-Z-Fighting Projection Offset
        # ------------------------------------------------------------
        # Linework is pushed this many mm AWAY from the panel face
        # along Y to keep it visually flush but render-stable.
        NA_FACE_PROJECTION_OFFSET_MM = 0.5
        # ---------------------------------------------------------------

        # CONSTANTS | Style Dispatch Table
        # ------------------------------------------------------------
        NA_STYLE_NONE              = "None".freeze
        NA_STYLE_VERTICAL_NARROW   = "VerticalNarrow".freeze
        NA_STYLE_CLASSICAL_SIX     = "ClassicalSixPanel".freeze
        NA_STYLE_FOUR_PANEL        = "FourPanel".freeze
        NA_STYLE_HORIZONTAL_THREE  = "HorizontalThree".freeze
        # ---------------------------------------------------------------

        # CONSTANTS | Configuration Keys + Defaults
        # ------------------------------------------------------------
        NA_KEY_ENABLED          = "Na__DoorConfig__PanelDesignEnabled".freeze
        NA_KEY_STYLE            = "Na__DoorConfig__PanelDesignStyle".freeze
        NA_KEY_STILE_W          = "Na__DoorConfig__PanelDesignStileWidth_mm".freeze
        NA_KEY_TOP_RAIL         = "Na__DoorConfig__PanelDesignTopRail_mm".freeze
        NA_KEY_BOTTOM_RAIL      = "Na__DoorConfig__PanelDesignBottomRail_mm".freeze
        NA_KEY_VERTICAL_PANE_W  = "Na__DoorConfig__PanelDesignVerticalPaneWidth_mm".freeze
        NA_KEY_EDGE_COLOUR_ID   = "Na__DoorConfig__PanelDesignEdgeColourId".freeze

        NA_DEFAULT_STILE_W          = 95.0
        NA_DEFAULT_TOP_RAIL         = 100.0
        NA_DEFAULT_BOTTOM_RAIL      = 200.0
        NA_DEFAULT_VERTICAL_PANE_W  = 90.0
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Build the Door Panel Design Inside the MOD Group
        # ------------------------------------------------------------
        # Idempotent against the supplied entities collection: the
        # caller is expected to be inside a model.start_operation, and
        # the geometry engine clears the definition entities before
        # calling this on update, so we never need to remove an
        # existing design container ourselves.
        #
        # Skips silently when:
        #   * mod_entities is nil/invalid
        #   * Na__DoorConfig__PanelDesignEnabled is false
        #   * Na__DoorConfig__PanelDesignStyle is "None" or unknown
        #   * the inner perimeter would be inverted (sliders too aggressive)
        #
        # @param config [Hash] Na__DoorConfiguration block
        # @param mod_entities [Sketchup::Entities] Target MOD group entities
        # @return [Sketchup::Group, nil] The container group (or nil when skipped)
        def self.na_build_panel_design(config, mod_entities)
            return nil unless mod_entities
            return nil unless na_design_enabled?(config)

            style_key = na_resolve_style_key(config)
            return nil if style_key == NA_STYLE_NONE

            geometry = na_compute_panel_geometry(config)
            return nil if geometry[:panel_w_mm] <= 0 || geometry[:panel_h_mm] <= 0

            layout = na_build_layout(config, geometry)

            container = mod_entities.add_group
            container.name = NA_GROUP_NAME_DESIGN_CONTAINER

            front_face = container.entities.add_group
            front_face.name = NA_GROUP_NAME_FRONT_FACE
            na_build_face(front_face.entities, layout, style_key, config, geometry[:front_y_mm])

            back_face = container.entities.add_group
            back_face.name = NA_GROUP_NAME_BACK_FACE
            na_build_face(back_face.entities, layout, style_key, config, geometry[:back_y_mm])

            edge_colour_id = na_resolve_edge_colour_id(config)
            EdgeColourManager.na_apply_edge_colour_to_group(container, edge_colour_id)

            DebugTools.na_debug_geometry(
                "PanelDesignBuilder: built '#{style_key}' design (front Y=#{geometry[:front_y_mm].round(1)}mm, back Y=#{geometry[:back_y_mm].round(1)}mm)"
            )
            container
        rescue StandardError => e
            DebugTools.na_debug_error("PanelDesignBuilder: build failed", e)
            nil
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Geometry Resolution
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Resolve the Panel Geometry From the Door Configuration
        # ------------------------------------------------------------
        # Mirrors the panel-solid math from
        # Na__GeometryBuilders.na_build_panel so the design lives on
        # the same six panel faces. Returns the panel origin (X, Z)
        # plus the panel size (W, H) plus the front/back Y planes
        # (offset slightly outwards to avoid Z-fighting).
        def self.na_compute_panel_geometry(config)
            opening_w_mm   = config["Na__DoorConfig__OpeningWidth_mm"].to_f
            opening_h_mm   = config["Na__DoorConfig__OpeningHeight_mm"].to_f
            lining_t_mm    = config["Na__DoorConfig__LiningThickness_mm"].to_f
            panel_t_mm     = config["Na__DoorConfig__PanelThickness_mm"].to_f
            floor_clear_mm = config["Na__DoorConfig__PanelFloorClearance_mm"].to_f

            panel_w_mm     = opening_w_mm - 2 * lining_t_mm
            panel_h_mm     = (opening_h_mm - lining_t_mm) - floor_clear_mm

            panel_y_mm     = GeometryHelpers.na_panel_y_origin_mm(config)       # <-- Panel front face Y
            front_y_mm     = panel_y_mm - NA_FACE_PROJECTION_OFFSET_MM
            back_y_mm      = panel_y_mm + panel_t_mm + NA_FACE_PROJECTION_OFFSET_MM

            {
                :panel_origin_x_mm => lining_t_mm,
                :panel_origin_z_mm => floor_clear_mm,
                :panel_w_mm        => panel_w_mm,
                :panel_h_mm        => panel_h_mm,
                :panel_t_mm        => panel_t_mm,
                :front_y_mm        => front_y_mm,
                :back_y_mm         => back_y_mm
            }
        end
        private_class_method :na_compute_panel_geometry
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Build the Layout Hash for All Style Builders
        # ------------------------------------------------------------
        def self.na_build_layout(config, geometry)
            stile_w        = na_config_number(config, NA_KEY_STILE_W,      NA_DEFAULT_STILE_W)
            top_rail       = na_config_number(config, NA_KEY_TOP_RAIL,     NA_DEFAULT_TOP_RAIL)
            bottom_rail    = na_config_number(config, NA_KEY_BOTTOM_RAIL,  NA_DEFAULT_BOTTOM_RAIL)
            inner_rail_t   = na_config_number(config, NA_KEY_INNER_RAIL_T, NA_DEFAULT_INNER_RAIL_T)

            PanelDesignFrame.na_compute_layout(
                geometry[:panel_origin_x_mm], geometry[:panel_origin_z_mm],
                geometry[:panel_w_mm],        geometry[:panel_h_mm],
                stile_w, top_rail, bottom_rail, inner_rail_t
            )
        end
        private_class_method :na_build_layout
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Per-Face Build + Style Dispatch
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Build the Linework for a Single Panel Face
        # ------------------------------------------------------------
        # Always draws the inner-perimeter rectangle, then dispatches
        # to the requested style for its specific subdivisions.
        def self.na_build_face(face_entities, layout, style_key, config, y_mm)
            PanelDesignFrame.na_draw_inner_perimeter(face_entities, layout, y_mm)
            na_dispatch_style(style_key, face_entities, layout, config, y_mm)
        end
        private_class_method :na_build_face
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Dispatch to the Requested Style Module
        # ------------------------------------------------------------
        def self.na_dispatch_style(style_key, face_entities, layout, config, y_mm)
            case style_key
            when NA_STYLE_VERTICAL_NARROW
                preferred_pane_w = na_config_number(config, NA_KEY_VERTICAL_PANE_W, NA_DEFAULT_VERTICAL_PANE_W)
                StyleVerticalNarrow.na_build_face_lines(face_entities, layout, preferred_pane_w, y_mm)
            when NA_STYLE_CLASSICAL_SIX
                StyleClassicalSixPanel.na_build_face_lines(face_entities, layout, y_mm)
            when NA_STYLE_FOUR_PANEL
                StyleFourPanel.na_build_face_lines(face_entities, layout, y_mm)
            when NA_STYLE_HORIZONTAL_THREE
                StyleHorizontalThree.na_build_face_lines(face_entities, layout, y_mm)
            else
                DebugTools.na_debug_warn("PanelDesignBuilder: unknown style '#{style_key}', drawing perimeter only")
                0
            end
        end
        private_class_method :na_dispatch_style
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Configuration Parsing
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Resolve Whether the Design Subsystem Is Enabled
        # ------------------------------------------------------------
        def self.na_design_enabled?(config)
            return false unless config.is_a?(Hash)
            value = config[NA_KEY_ENABLED]
            return true if value.nil?                                           # <-- Treat missing as enabled
            value == true || value.to_s.downcase == "true"
        end
        private_class_method :na_design_enabled?
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Resolve the Panel Design Style Key
        # ------------------------------------------------------------
        def self.na_resolve_style_key(config)
            value = config[NA_KEY_STYLE]
            return NA_STYLE_NONE if value.nil? || value.to_s.strip.empty?
            value.to_s
        end
        private_class_method :na_resolve_style_key
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Resolve the Edge Colour ID (Defaults to Dark Grey)
        # ------------------------------------------------------------
        def self.na_resolve_edge_colour_id(config)
            value = config[NA_KEY_EDGE_COLOUR_ID]
            return EdgeColourManager::NA_DEFAULT_DARK_GREY_KEY if value.nil? || value.to_s.strip.empty?
            value.to_s
        end
        private_class_method :na_resolve_edge_colour_id
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Read a Numeric Configuration Value With Fallback
        # ------------------------------------------------------------
        def self.na_config_number(config, key, fallback)
            value = config[key]
            return fallback.to_f if value.nil?
            Float(value)
        rescue ArgumentError, TypeError
            fallback.to_f
        end
        private_class_method :na_config_number
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__PanelDesignBuilder
end # module Na__InteriorDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
