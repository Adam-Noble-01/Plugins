# =============================================================================
# NA WINDOW CONFIGURATOR TOOL - GEOMETRY ENGINE
# =============================================================================
#
# FILE       : Na__WindowConfiguratorTool__GeometryEngine__.rb
# NAMESPACE  : Na__WindowConfiguratorTool
# MODULE     : Na__GeometryEngine
# AUTHOR     : Noble Architecture
# PURPOSE    : Orchestrates window geometry creation and updates
# CREATED    : 2026
# VERSION    : 0.9.0
#
# DESCRIPTION:
# - High-level orchestration for creating and updating window geometry
# - Parses configuration and converts units (mm → inches)
# - Calculates opening layouts (mullions, casement counts)
# - Delegates actual geometry creation to GeometryBuilders module
# - Handles multi-casement openings (1-6 panels per opening)
# - Supports per-opening casement removal
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__WindowConfiguratorTool__DebugTools__'
require_relative 'Na__WindowConfiguratorTool__MaterialManager__'
require_relative 'Na__WindowConfiguratorTool__DataSerializer__'
require_relative 'Na__WindowConfiguratorTool__GeometryBuilders__'

module Na__WindowConfiguratorTool
    module Na__GeometryEngine

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools = Na__WindowConfiguratorTool::Na__DebugTools
        MaterialManager = Na__WindowConfiguratorTool::Na__MaterialManager
        DataSerializer = Na__WindowConfiguratorTool::Na__DataSerializer
        GeometryBuilders = Na__WindowConfiguratorTool::Na__GeometryBuilders

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Constants (access from parent module)
# -----------------------------------------------------------------------------

        def self.constants_from_parent
            parent = Na__WindowConfiguratorTool
            {
                mm_to_inch: parent::NA_MM_TO_INCH,
                default_width: parent::NA_DEFAULT_WIDTH,
                default_height: parent::NA_DEFAULT_HEIGHT,
                default_frame_thickness: parent::NA_DEFAULT_FRAME_THICKNESS,
                default_frame_top_thickness: parent::NA_DEFAULT_FRAME_TOP_THICKNESS,
                default_frame_bottom_thickness: parent::NA_DEFAULT_FRAME_BOTTOM_THICKNESS,
                default_frame_left_thickness: parent::NA_DEFAULT_FRAME_LEFT_THICKNESS,
                default_frame_right_thickness: parent::NA_DEFAULT_FRAME_RIGHT_THICKNESS,
                default_casement_width: parent::NA_DEFAULT_CASEMENT_WIDTH,
                default_casement_depth: parent::NA_DEFAULT_CASEMENT_DEPTH,
                default_casement_inset: parent::NA_DEFAULT_CASEMENT_INSET,
                default_glass_thickness: parent::NA_DEFAULT_GLASS_THICKNESS,
                default_glaze_bar_width: parent::NA_DEFAULT_GLAZE_BAR_WIDTH,
                default_glazebar_inset: parent::NA_DEFAULT_GLAZEBAR_INSET,
                default_cill_depth: parent::NA_DEFAULT_CILL_DEPTH,
                default_cill_height: parent::NA_DEFAULT_CILL_HEIGHT,
                default_frame_depth: parent::NA_DEFAULT_FRAME_DEPTH,
                default_frame_wall_inset: parent::NA_DEFAULT_FRAME_WALL_INSET,
                default_mullion_count: parent::NA_DEFAULT_MULLION_COUNT,
                default_mullion_width: parent::NA_DEFAULT_MULLION_WIDTH,
                default_transom_count: parent::NA_DEFAULT_TRANSOM_COUNT,
                default_transom_width: parent::NA_DEFAULT_TRANSOM_WIDTH,
                default_transom_1_y: parent::NA_DEFAULT_TRANSOM_1_Y,
                default_transom_2_y: parent::NA_DEFAULT_TRANSOM_2_Y,
                default_transom_3_y: parent::NA_DEFAULT_TRANSOM_3_Y,
                default_frame_material_id: parent::NA_DEFAULT_FRAME_MATERIAL_ID,
                default_glass_material_id: parent::NA_DEFAULT_GLASS_MATERIAL_ID,
                default_cill_material_id: parent::NA_DEFAULT_CILL_MATERIAL_ID
            }
        end
        # ---------------------------------------------------------------


# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Window Creation
# -----------------------------------------------------------------------------

        # FUNCTION | Create Window Geometry
        # ------------------------------------------------------------
        # Creates a new window component with all specified geometry.
        # Each window gets a unique definition and instance name: AWN001__Window__
        # 
        # @param config [Hash] Window configuration
        # @param window_id [String] Pre-generated window ID (e.g., "AWN001")
        # @return [Sketchup::ComponentInstance, nil] The created component instance
        def self.na_create_window_geometry(config, window_id = nil)
            DebugTools.na_debug_method("GeometryEngine.na_create_window_geometry")
            
            model = Sketchup.active_model
            entities = model.active_entities
            constants = constants_from_parent
            
            # Generate window ID if not provided
            window_id ||= DataSerializer.na_generate_next_window_id
            
            begin
                # Extract and convert configuration values
                params = na_parse_config(config, constants)
                
                DebugTools.na_debug_geometry("Creating window: #{params[:width].to_mm.round}mm x #{params[:height].to_mm.round}mm, #{params[:num_openings]} opening(s), casements_per_opening: #{params[:casements_per_opening]}, frame_depth: #{params[:frame_depth].to_mm.round}mm, wall_inset: #{params[:frame_wall_inset].to_mm.round}mm")
                
                # Create component definition with unique AWN name
                component_name = "#{window_id}__Window__"
                definitions = model.definitions
                component_def = definitions.add(component_name)
                window_entities = component_def.entities
                
                # Get materials from MaterialManager
                frame_material = MaterialManager.na_get_material_by_id(params[:frame_material_id])
                glass_material = MaterialManager.na_get_material_by_id(constants[:default_glass_material_id])
                
                # Cill material: use frame material if paint_cill is true, otherwise use Sapele timber
                if params[:paint_cill]
                    cill_material = frame_material
                    # Note: frame_material can be nil (SketchUp Default), which is valid
                else
                    cill_material = MaterialManager.na_get_material_by_id(constants[:default_cill_material_id])
                    # Warn if Sapele timber failed to load, but allow nil (will use SketchUp default)
                    if cill_material.nil?
                        DebugTools.na_debug_warn("Default cill material (Sapele) not found, using SketchUp default")
                    end
                end
                
                # Safety check: Only glass is strictly required
                # Frame and cill can both be nil (nil = SketchUp Default material)
                unless glass_material
                    DebugTools.na_debug_error("Failed to load glass material - cannot create window without glass")
                    return nil
                end
                
                # Build window geometry
                na_build_window_elements(window_entities, params, frame_material, glass_material, cill_material)
                
                # Add component instance at origin and set its name
                instance = entities.add_instance(component_def, IDENTITY)
                instance.name = component_name
                
                DebugTools.na_debug_geometry("Created window component: #{component_name}")
                return instance
                
            rescue => e
                DebugTools.na_debug_error("Error in na_create_window_geometry", e)
                return nil
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Update Window Geometry
        # ------------------------------------------------------------
        # Updates existing window component by clearing and rebuilding geometry.
        # 
        # @param instance [Sketchup::ComponentInstance] Existing window instance
        # @param config [Hash] Window configuration
        def self.na_update_window_geometry(instance, config)
            DebugTools.na_debug_method("GeometryEngine.na_update_window_geometry")
            
            return unless instance && instance.valid?
            
            constants = constants_from_parent
            
            begin
                # Clear existing geometry in the definition
                definition = instance.definition
                definition.entities.clear!
                
                # Extract and convert configuration values
                params = na_parse_config(config, constants)
                
                window_entities = definition.entities
                
                # Get materials from MaterialManager
                frame_material = MaterialManager.na_get_material_by_id(params[:frame_material_id])
                glass_material = MaterialManager.na_get_material_by_id(constants[:default_glass_material_id])
                
                # Cill material: use frame material if paint_cill is true, otherwise use Sapele timber
                if params[:paint_cill]
                    cill_material = frame_material
                    # Note: frame_material can be nil (SketchUp Default), which is valid
                else
                    cill_material = MaterialManager.na_get_material_by_id(constants[:default_cill_material_id])
                    # Warn if Sapele timber failed to load, but allow nil (will use SketchUp default)
                    if cill_material.nil?
                        DebugTools.na_debug_warn("Default cill material (Sapele) not found, using SketchUp default")
                    end
                end
                
                # Safety check: Only glass is strictly required
                # Frame and cill can both be nil (nil = SketchUp Default material)
                unless glass_material
                    DebugTools.na_debug_error("Failed to load glass material - cannot update window without glass")
                    return
                end
                
                # Build window geometry
                na_build_window_elements(window_entities, params, frame_material, glass_material, cill_material)
                
                DebugTools.na_debug_geometry("Updated window geometry (casements_per_opening: #{params[:casements_per_opening]}, frame_depth: #{params[:frame_depth].to_mm.round}mm, wall_inset: #{params[:frame_wall_inset].to_mm.round}mm)")
                
            rescue => e
                DebugTools.na_debug_error("Error in na_update_window_geometry", e)
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Find Target for Live Update
        # ------------------------------------------------------------
        # Returns the window component to update for live mode, checking:
        # 1. Stored window component (from previous selection/creation)
        # 2. Current model selection (if it's a Na Window)
        # 
        # @param stored_component [Sketchup::ComponentInstance, nil] Previously stored component
        # @return [Sketchup::ComponentInstance, nil] The target window or nil
        def self.na_find_live_update_target(stored_component)
            # First, check if we have a valid stored component
            if stored_component && stored_component.valid?
                return stored_component
            end
            
            # Second, check the current selection
            model = Sketchup.active_model
            selection = model.selection
            
            return nil if selection.empty?
            
            # Look for a Na Window component in selection
            selection.each do |entity|
                if entity.is_a?(Sketchup::ComponentInstance)
                    window_id = DataSerializer.na_get_window_id_from_instance(entity)
                    if window_id
                        # Found a valid Na Window
                        return entity
                    end
                end
            end
            
            nil
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Helper Functions
# -----------------------------------------------------------------------------

        private

        # FUNCTION | Resolve Effective Frame Thicknesses
        # ------------------------------------------------------------
        def self.na_resolve_effective_frame_thicknesses(config, constants)
            mm_to_inch = constants[:mm_to_inch]
            uniform_frame_thickness_mm = config.key?("frame_thickness_mm") ? config["frame_thickness_mm"] : constants[:default_frame_thickness]
            use_advanced_frame_controls = config["advanced_frame_controls"] == true

            resolve_frame_side_thickness = lambda do |side_key|
                mm_value = if use_advanced_frame_controls && config.key?(side_key)
                    config[side_key]
                else
                    uniform_frame_thickness_mm
                end

                [mm_value.to_f, 0.0].max * mm_to_inch
            end

            top_thickness = resolve_frame_side_thickness.call("frame_top_thickness_mm")
            bottom_thickness = resolve_frame_side_thickness.call("frame_bottom_thickness_mm")
            left_thickness = resolve_frame_side_thickness.call("frame_left_thickness_mm")
            right_thickness = resolve_frame_side_thickness.call("frame_right_thickness_mm")

            {
                use_advanced_frame_controls: use_advanced_frame_controls,
                uniform: [uniform_frame_thickness_mm.to_f, 0.0].max * mm_to_inch,
                top: top_thickness,
                bottom: bottom_thickness,
                left: left_thickness,
                right: right_thickness,
                fully_frameless: top_thickness <= 0 && bottom_thickness <= 0 && left_thickness <= 0 && right_thickness <= 0
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Parse Configuration
        # ------------------------------------------------------------
        # Extracts and converts all config values from hash to internal units.
        # 
        # @param config [Hash] Raw configuration from JSON
        # @param constants [Hash] Module constants
        # @return [Hash] Parsed parameters ready for geometry creation
        def self.na_parse_config(config, constants)
            mm_to_inch = constants[:mm_to_inch]
            
            # Extract basic values
            width = (config["width_mm"] || constants[:default_width]).to_f * mm_to_inch
            height = (config["height_mm"] || constants[:default_height]).to_f * mm_to_inch
            effective_frame_thicknesses = na_resolve_effective_frame_thicknesses(config, constants)
            casement_width = (config["casement_width_mm"] || constants[:default_casement_width]).to_f * mm_to_inch
            casement_depth = (config["casement_depth_mm"] || constants[:default_casement_depth]).to_f * mm_to_inch
            casement_inset = (config["casement_inset_mm"] || constants[:default_casement_inset]).to_f * mm_to_inch
            sliding_sash_overlap = (config["sliding_sash_overlap_mm"] || 20).to_f * mm_to_inch
            
            # Flags
            show_casements = config["show_casements"] != false
            has_cill = config["has_cill"] != false
            use_individual_sizes = config["casement_sizes_individual"] == true
            sliding_sash_window = config["sliding_sash_window"] == true
            
            # Casements per opening (backward compat: twin_casements true → 2)
            if config.key?("twin_casements") && !config.key?("casements_per_opening")
                casements_per_opening = config["twin_casements"] == true ? 2 : 1
            else
                casements_per_opening = (config["casements_per_opening"] || 1).to_i.clamp(1, 6)
            end
            
            # Mullions
            num_mullions = (config["mullions"] || constants[:default_mullion_count]).to_i
            mullion_width = (config["mullion_width_mm"] || constants[:default_mullion_width]).to_f * mm_to_inch
            transom_count = (config["transoms"] || constants[:default_transom_count]).to_i.clamp(0, 3)
            transom_width = (config["transom_width_mm"] || constants[:default_transom_width]).to_f * mm_to_inch
            transom_bottoms = [
                (config["transom_1_y_mm"] || constants[:default_transom_1_y]).to_f * mm_to_inch,
                (config["transom_2_y_mm"] || constants[:default_transom_2_y]).to_f * mm_to_inch,
                (config["transom_3_y_mm"] || constants[:default_transom_3_y]).to_f * mm_to_inch
            ].first(transom_count)
            
            # Glass and glaze bars
            glass_thickness = (config["glass_thickness_mm"] || constants[:default_glass_thickness]).to_f * mm_to_inch
            h_bars = (config["horizontal_glaze_bars"] || 0).to_i
            v_bars = (config["vertical_glaze_bars"] || 0).to_i
            bar_width = (config["glaze_bar_width_mm"] || constants[:default_glaze_bar_width]).to_f * mm_to_inch
            glazebar_inset = (config["glazebar_inset_mm"] || constants[:default_glazebar_inset]).to_f * mm_to_inch
            
            # Cill
            cill_depth = (config["cill_depth_mm"] || constants[:default_cill_depth]).to_f * mm_to_inch
            cill_height = (config["cill_height_mm"] || constants[:default_cill_height]).to_f * mm_to_inch
            
            # Frame
            frame_depth = (config["frame_depth_mm"] || constants[:default_frame_depth]).to_f * mm_to_inch
            frame_wall_inset = (config["frame_wall_inset_mm"] || constants[:default_frame_wall_inset]).to_f * mm_to_inch
            
            # Materials - get material IDs from config
            frame_material_id = config["frame_material_id"] || constants[:default_frame_material_id]
            
            # Paint Cill toggle
            paint_cill = config["paint_cill"] == true
            
            # Removed casements
            removed_casements = config["removed_casements"] || []
            removed_transom_segments = config["removed_transom_segments"] || []
            removed_glazebars = config["removed_glazebars"] || []
            
            # Individual casement sizes
            if use_individual_sizes
                cas_top_rail = (config["casement_top_rail_mm"] || casement_width.to_mm).to_f * mm_to_inch
                cas_bottom_rail = (config["casement_bottom_rail_mm"] || casement_width.to_mm).to_f * mm_to_inch
                cas_left_stile = (config["casement_left_stile_mm"] || casement_width.to_mm).to_f * mm_to_inch
                cas_right_stile = (config["casement_right_stile_mm"] || casement_width.to_mm).to_f * mm_to_inch
            else
                cas_top_rail = cas_bottom_rail = cas_left_stile = cas_right_stile = casement_width
            end
            
            # Calculate opening layout
            num_openings = num_mullions + 1
            inner_width = width - effective_frame_thicknesses[:left] - effective_frame_thicknesses[:right]
            inner_height = height - effective_frame_thicknesses[:top] - effective_frame_thicknesses[:bottom]
            total_mullion_width = num_mullions * mullion_width
            available_width = inner_width - total_mullion_width
            opening_width = available_width / num_openings
            
            # Return parsed parameters hash
            {
                width: width,
                height: height,
                frame_thickness: effective_frame_thicknesses[:bottom],
                frame_top_thickness: effective_frame_thicknesses[:top],
                frame_bottom_thickness: effective_frame_thicknesses[:bottom],
                frame_left_thickness: effective_frame_thicknesses[:left],
                frame_right_thickness: effective_frame_thicknesses[:right],
                frame_fully_frameless: effective_frame_thicknesses[:fully_frameless],
                frame_depth: frame_depth,
                frame_wall_inset: frame_wall_inset,
                frame_material_id: frame_material_id,
                paint_cill: paint_cill,
                casement_width: casement_width,
                casement_depth: casement_depth,
                casement_inset: casement_inset,
                sliding_sash_overlap: sliding_sash_overlap,
                cas_top_rail: cas_top_rail,
                cas_bottom_rail: cas_bottom_rail,
                cas_left_stile: cas_left_stile,
                cas_right_stile: cas_right_stile,
                show_casements: show_casements,
                sliding_sash_window: sliding_sash_window,
                casements_per_opening: casements_per_opening,
                removed_casements: removed_casements,
                removed_transom_segments: removed_transom_segments,
                removed_glazebars: removed_glazebars,
                num_mullions: num_mullions,
                mullion_width: mullion_width,
                transom_count: transom_count,
                transom_width: transom_width,
                transom_bottoms: transom_bottoms,
                num_openings: num_openings,
                inner_width: inner_width,
                inner_height: inner_height,
                opening_width: opening_width,
                glass_thickness: glass_thickness,
                h_bars: h_bars,
                v_bars: v_bars,
                bar_width: bar_width,
                glazebar_inset: glazebar_inset,
                has_cill: has_cill,
                cill_depth: cill_depth,
                cill_height: cill_height
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Build Window Elements
        # ------------------------------------------------------------
        # Creates all window geometry elements using GeometryBuilders.
        # Handles frame, mullions, openings (with casements/glass/glaze bars), and cill.
        # 
        # @param entities [Sketchup::Entities] Target entities collection
        # @param params [Hash] Parsed parameters from na_parse_config
        # @param frame_material [Sketchup::Material] Frame material
        # @param glass_material [Sketchup::Material] Glass material
        # @param cill_material [Sketchup::Material] Cill material
        def self.na_build_window_elements(entities, params, frame_material, glass_material, cill_material)
            # Create outer frame (skip in frameless mode when frame_thickness is 0)
            unless params[:frame_fully_frameless]
                GeometryBuilders.na_create_frame_geometry(
                    entities,
                    params[:width],
                    params[:height],
                    {
                        top: params[:frame_top_thickness],
                        bottom: params[:frame_bottom_thickness],
                        left: params[:frame_left_thickness],
                        right: params[:frame_right_thickness]
                    },
                    params[:frame_depth], frame_material, params[:frame_wall_inset]
                )
            end
            
            # Create mullions
            (1..params[:num_mullions]).each do |m|
                mullion_x = params[:frame_left_thickness] + (m * params[:opening_width]) + ((m - 1) * params[:mullion_width])
                GeometryBuilders.na_create_mullion_geometry(
                    entities, m, mullion_x, params[:inner_height], params[:mullion_width], 
                    params[:frame_depth], params[:frame_bottom_thickness], frame_material, params[:frame_wall_inset]
                )
            end
            
            # Create each opening
            (0...params[:num_openings]).each do |i|
                na_create_opening(entities, i, params, frame_material, glass_material)
            end
            
            # Create cill (skip in frameless mode -- no cill without a frame)
            if params[:has_cill] && params[:frame_bottom_thickness] > 0
                GeometryBuilders.na_create_cill_geometry(
                    entities, params[:width], params[:cill_depth], params[:cill_height], 
                    params[:frame_depth], cill_material, params[:frame_wall_inset]
                )
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Create Single Opening (Casement + Glass + Glaze Bars)
        # ------------------------------------------------------------
        # Creates geometry for one opening with N casement panels and optional transoms.
        # Supports 1-6 casements per opening (bifold/concertina panels).
        # Respects removed casements and removed transom segments.
        def self.na_create_opening(entities, opening_index, params, frame_material, glass_material)
            opening_x = params[:frame_left_thickness] + (opening_index * (params[:opening_width] + params[:mullion_width]))
            opening_has_casement = params[:show_casements] && !params[:removed_casements].include?(opening_index)
            opening_layout = na_get_opening_layout(opening_index, opening_x, params)

            opening_layout[:transom_segments].each do |segment|
                GeometryBuilders.na_create_transom_geometry(
                    entities,
                    "#{opening_index}_#{segment[:transom_index]}",
                    segment[:x],
                    segment[:z],
                    segment[:width],
                    segment[:height],
                    params[:frame_depth],
                    frame_material,
                    params[:frame_wall_inset]
                )
            end

            opening_layout[:cells].each_with_index do |cell, cell_index|
                cell_id_prefix = "#{opening_index}_#{cell_index}"

                if opening_has_casement && params[:sliding_sash_window]
                    na_create_sliding_sash_opening(
                        entities,
                        opening_index,
                        cell_index,
                        cell[:x],
                        cell[:z],
                        cell[:height],
                        params,
                        frame_material,
                        glass_material
                    )
                else
                    na_create_multi_casement_opening(
                        entities,
                        opening_index,
                        cell_index,
                        cell[:x],
                        cell[:z],
                        cell[:height],
                        opening_has_casement,
                        params,
                        frame_material,
                        glass_material
                    )
                end
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Check Whether a Transom Segment Is Removed
        # ------------------------------------------------------------
        def self.na_transom_segment_removed?(params, opening_index, transom_index)
            params[:removed_transom_segments].include?("#{opening_index}:#{transom_index}")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Build Opening Layout
        # ------------------------------------------------------------
        def self.na_get_opening_layout(opening_index, opening_x, params)
            cells = []
            transom_segments = []
            cell_bottom = 0
            opening_z = params[:frame_bottom_thickness]

            params[:transom_bottoms].each_with_index do |transom_bottom, transom_index|
                next if na_transom_segment_removed?(params, opening_index, transom_index)

                cell_height = transom_bottom - cell_bottom
                if cell_height > 0
                    cells << {
                        x: opening_x,
                        z: opening_z + cell_bottom,
                        width: params[:opening_width],
                        height: cell_height
                    }
                end

                transom_segments << {
                    x: opening_x,
                    z: opening_z + transom_bottom,
                    width: params[:opening_width],
                    height: params[:transom_width],
                    transom_index: transom_index
                }

                cell_bottom = transom_bottom + params[:transom_width]
            end

            top_cell_height = params[:inner_height] - cell_bottom
            if top_cell_height > 0
                cells << {
                    x: opening_x,
                    z: opening_z + cell_bottom,
                    width: params[:opening_width],
                    height: top_cell_height
                }
            end

            {
                cells: cells,
                transom_segments: transom_segments
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Create Multi-Casement Opening Cell
        # ------------------------------------------------------------
        # Unified method for creating N casement panels within one transom-bounded cell.
        def self.na_create_multi_casement_opening(entities, opening_index, cell_index, opening_x, opening_z, opening_height, opening_has_casement, params, frame_material, glass_material)
            num_panels = params[:casements_per_opening]
            panel_width = params[:opening_width] / num_panels.to_f

            (0...num_panels).each do |p|
                panel_x = opening_x + (p * panel_width)
                panel_id = "#{opening_index}_#{cell_index}_P#{p}"

                na_render_opening_panel_geometry(
                    entities,
                    panel_id,
                    opening_index,
                    cell_index,
                    p,
                    0,
                    panel_x,
                    opening_z,
                    panel_width,
                    opening_height,
                    opening_has_casement,
                    params[:frame_wall_inset],
                    params,
                    frame_material,
                    glass_material
                )
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Create Sliding Sash Opening Cell
        # ------------------------------------------------------------
        # Creates two vertically stacked casements per horizontal panel.
        # Bottom sash is set back by one casement depth to simulate sliding overlap.
        def self.na_create_sliding_sash_opening(entities, opening_index, cell_index, opening_x, opening_z, opening_height, params, frame_material, glass_material)
            num_panels = params[:casements_per_opening]
            panel_width = params[:opening_width] / num_panels.to_f
            sash_height = opening_height / 2.0
            sash_overlap = [params[:sliding_sash_overlap], sash_height - 1.mm].min
            sash_overlap = [sash_overlap, 0].max

            (0...num_panels).each do |p|
                panel_x = opening_x + (p * panel_width)
                base_panel_id = "#{opening_index}_#{cell_index}_P#{p}"
                top_panel_id = "#{base_panel_id}_Top"
                bottom_panel_id = "#{base_panel_id}_Bottom"

                na_render_opening_panel_geometry(
                    entities,
                    top_panel_id,
                    opening_index,
                    cell_index,
                    p,
                    0,
                    panel_x,
                    opening_z + sash_height,
                    panel_width,
                    sash_height,
                    true,
                    params[:frame_wall_inset],
                    params,
                    frame_material,
                    glass_material
                )

                na_render_opening_panel_geometry(
                    entities,
                    bottom_panel_id,
                    opening_index,
                    cell_index,
                    p,
                    1,
                    panel_x,
                    opening_z,
                    panel_width,
                    sash_height + sash_overlap,
                    true,
                    params[:frame_wall_inset] + params[:casement_depth],
                    params,
                    frame_material,
                    glass_material
                )
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Render Opening Panel Geometry
        # ------------------------------------------------------------
        # Shared panel renderer for standard and sliding sash modes.
        def self.na_render_opening_panel_geometry(entities, panel_id, opening_index, cell_index, panel_index, sash_index, panel_x, panel_z, panel_width, panel_height, panel_has_casement, panel_wall_inset, params, frame_material, glass_material)
            if panel_has_casement
                GeometryBuilders.na_create_casement_geometry_individual(
                    entities, panel_id, panel_width, panel_height,
                    params[:cas_top_rail], params[:cas_bottom_rail], params[:cas_left_stile], params[:cas_right_stile],
                    params[:casement_depth], panel_x, panel_z, frame_material, panel_wall_inset, params[:casement_inset]
                )

                glass_offset_x = panel_x + params[:cas_left_stile]
                glass_offset_z = panel_z + params[:cas_bottom_rail]
                glass_w = panel_width - params[:cas_left_stile] - params[:cas_right_stile]
                glass_h = panel_height - params[:cas_top_rail] - params[:cas_bottom_rail]

                GeometryBuilders.na_create_glass_geometry(
                    entities, panel_id, glass_w, glass_h, params[:glass_thickness],
                    glass_offset_x, glass_offset_z, params[:frame_depth], glass_material,
                    panel_wall_inset, params[:casement_depth], params[:casement_inset]
                )

                if params[:h_bars] > 0 || params[:v_bars] > 0
                    GeometryBuilders.na_create_glazebar_geometry(
                        entities, panel_id, glass_w, glass_h, params[:h_bars], params[:v_bars],
                        params[:bar_width], params[:glass_thickness], glass_offset_x, glass_offset_z,
                        params[:frame_depth], frame_material, panel_wall_inset,
                        params[:casement_depth], params[:casement_inset], params[:glazebar_inset],
                        params[:removed_glazebars], opening_index, cell_index, panel_index, sash_index
                    )
                end
            else
                GeometryBuilders.na_create_glass_geometry(
                    entities, panel_id, panel_width, panel_height, params[:glass_thickness],
                    panel_x, panel_z, params[:frame_depth], glass_material, panel_wall_inset
                )

                if params[:h_bars] > 0 || params[:v_bars] > 0
                    GeometryBuilders.na_create_glazebar_geometry(
                        entities, panel_id, panel_width, panel_height, params[:h_bars], params[:v_bars],
                        params[:bar_width], params[:glass_thickness], panel_x, panel_z,
                        params[:frame_depth], frame_material, panel_wall_inset,
                        nil, nil, params[:glazebar_inset],
                        params[:removed_glazebars], opening_index, cell_index, panel_index, sash_index
                    )
                end
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__GeometryEngine
end # module Na__WindowConfiguratorTool

# =============================================================================
# END OF FILE
# =============================================================================
