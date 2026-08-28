# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - WINDOW SYSTEM - GEOMETRY ENGINE
# =============================================================================
#
# FILE       : Na__AssemblyStudio__WindowSystem__GeometryEngine__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__WindowSystem
# MODULE     : Na__GeometryEngine
# AUTHOR     : Noble Architecture
# PURPOSE    : Orchestrates window geometry creation and updates
# CREATED    : 2026
# VERSION    : 0.9.0
#
# DESCRIPTION:
# - High-level orchestration for creating and updating window geometry
# - Parses configuration and converts units (mm to inches)
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
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../02__AppData/Na__AssemblyStudio__AppData__MaterialManager__'
require_relative 'Na__AssemblyStudio__WindowSystem__DataSerializer__'
require_relative 'Na__AssemblyStudio__WindowSystem__GeometryBuilders__'
require_relative 'Na__AssemblyStudio__WindowSystem__LeadedGlassBuilder__'
require_relative 'Na__AssemblyStudio__WindowSystem__SashHornBuilder__'
require_relative '../31__System__ExteriorSingleDoorSystem/Na__AssemblyStudio__ExtSingleDoor__PanelInterface__'

module Na__AssemblyStudio
module Na__WindowSystem
    module Na__GeometryEngine

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        MaterialManager = Na__AssemblyStudio::Na__AppData::Na__MaterialManager
        DataSerializer = Na__AssemblyStudio::Na__WindowSystem::Na__DataSerializer
        GeometryHelpers = Na__AssemblyStudio::Na__WindowSystem::Na__GeometryHelpers
        GeometryBuilders = Na__AssemblyStudio::Na__WindowSystem::Na__GeometryBuilders
        LeadedGlassBuilder = Na__AssemblyStudio::Na__WindowSystem::Na__LeadedGlassBuilder
        SashHornBuilder = Na__AssemblyStudio::Na__WindowSystem::Na__SashHornBuilder
        InsertionFrame   = Na__AssemblyStudio::Na__GeometryHelpers::Na__InsertionFrame                  # <-- Wall-aware insertion transform helper
        # Door panel construction crosses the WindowSystem<->ExteriorSingleDoorSystem
        # contract via the PanelInterface module rather than touching the
        # builder directly.
        DoorPanelInterface = lambda do
            Na__AssemblyStudio::Na__ExteriorSingleDoorSystem::PanelInterface
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Constants (access from parent module)
# -----------------------------------------------------------------------------

        def self.constants_from_parent
            parent = Na__AssemblyStudio::Na__WindowSystem
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
        # When `multifold_mode == true` the call is delegated to the
        # Bifold Door system's GeometryEngine; when `sliding_mode == true`
        # the call is delegated to the Sliding Door system (Phase-3b).
        # Both modes are mutually exclusive at the JS layer; if both
        # somehow arrive true together the bifold path wins.
        #
        # @param config [Hash] Window configuration
        # @param window_id [String] Pre-generated window ID (e.g., "AWN001")
        # @param insertion_frame [Hash, Geom::Point3d, nil] Optional insertion frame.
        #     Preferred shape is a Hash from the MeasurementTool with
        #     :origin_in + :xaxis/:yaxis/:zaxis so the window is rotated
        #     onto the wall. A bare Geom::Point3d is still accepted (the
        #     model's active drawing axes provide orientation). When nil
        #     the caller engages the placement tool.
        # @return [Sketchup::ComponentInstance, nil] The created component instance
        def self.na_create_window_geometry(config, window_id = nil, insertion_frame = nil)
            DebugTools.na_debug_method("GeometryEngine.na_create_window_geometry")

            bifold_instance = na_dispatch_bifold_create(config, insertion_frame)
            return bifold_instance if bifold_instance

            sliding_instance = na_dispatch_sliding_create(config, insertion_frame)
            return sliding_instance if sliding_instance

            double_door_instance = na_dispatch_exterior_double_door_create(config, insertion_frame)
            return double_door_instance if double_door_instance

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
                
                insertion_transform = na_resolve_window_insertion_transform(insertion_frame)
                instance = entities.add_instance(component_def, insertion_transform)
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
        # When `multifold_mode == true` the update is delegated to the
        # Bifold Door system's GeometryEngine (Phase-3a). The instance
        # must already be a bifold ADR component; switching modes
        # in-place is not supported (delete + recreate instead).
        #
        # @param instance [Sketchup::ComponentInstance] Existing window instance
        # @param config [Hash] Window configuration
        def self.na_update_window_geometry(instance, config)
            DebugTools.na_debug_method("GeometryEngine.na_update_window_geometry")

            return unless instance && instance.valid?

            return if na_dispatch_bifold_update(instance, config)
            return if na_dispatch_sliding_update(instance, config)
            return if na_dispatch_exterior_double_door_update(instance, config)

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

        # HELPER FUNCTION | Resolve the Insertion Transform for a New Window
        # ------------------------------------------------------------
        # Priority: full measurement frame (origin + axes) > origin only
        # (orientation taken from `Sketchup.active_model.axes`) > active
        # drawing axes (placement tool fallback) > IDENTITY.
        #
        # @param insertion_frame [Hash, Geom::Point3d, nil]
        # @return [Geom::Transformation]
        def self.na_resolve_window_insertion_transform(insertion_frame)
            transform = InsertionFrame.na_resolve_insertion_transform(insertion_frame)

            if InsertionFrame.na_frame_has_orientation?(insertion_frame)
                DebugTools.na_debug_geometry(
                    "Inserting window with measured frame: origin=#{insertion_frame[:origin_in].inspect} " \
                    "xaxis=#{insertion_frame[:xaxis].inspect}"
                )
            elsif (origin = InsertionFrame.na_extract_origin(insertion_frame))
                DebugTools.na_debug_geometry(
                    "Inserting window at measured Point A (axis-aware): #{origin.inspect}"
                )
            else
                DebugTools.na_debug_geometry("Inserting window at model drawing axes (placement tool fallback)")
            end

            transform
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Bifold + Sliding Mode Dispatch (Phase 3a / 3b)
# -----------------------------------------------------------------------------

        # FUNCTION | Delegate Create to Bifold Engine When multifold_mode Is True
        # ------------------------------------------------------------
        # Lazy-loads the ExtFold modules and forwards to
        # `Na__ExteriorMultiFoldingDoorSystem::Na__GeometryEngine`.
        # Returns the created instance when dispatch applied, nil
        # otherwise (caller falls through to the standard window path).
        def self.na_dispatch_bifold_create(config, insertion_frame)
            return nil unless config.is_a?(Hash)
            return nil unless config["multifold_mode"] == true
            return nil unless defined?(Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem)

            Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem.na_require_bifold_modules
            engine = Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::Na__GeometryEngine

            DebugTools.na_debug_geometry("Window->Bifold dispatch: na_create_window_geometry forwarded to Bifold engine")
            engine.na_build_bifold_door(config, nil, insertion_frame)
        rescue StandardError => e
            DebugTools.na_debug_error("WindowSystem -> Bifold dispatch (create) failed", e)
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Delegate Update to Bifold Engine When multifold_mode Is True
        # ------------------------------------------------------------
        # Returns true when dispatch applied (caller short-circuits the
        # standard window path), false otherwise.
        def self.na_dispatch_bifold_update(instance, config)
            return false unless instance && instance.valid?
            return false unless config.is_a?(Hash)
            return false unless config["multifold_mode"] == true
            return false unless defined?(Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem)

            Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem.na_require_bifold_modules
            engine = Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::Na__GeometryEngine

            DebugTools.na_debug_geometry("Window->Bifold dispatch: na_update_window_geometry forwarded to Bifold engine")
            engine.na_update_bifold_door(instance, config)
            true
        rescue StandardError => e
            DebugTools.na_debug_error("WindowSystem -> Bifold dispatch (update) failed", e)
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Delegate Create to Sliding Engine When sliding_mode Is True
        # ------------------------------------------------------------
        # Lazy-loads the ExtSlide modules and forwards to
        # `Na__ExteriorSlidingDoorSystem::Na__GeometryEngine`. Returns
        # the created instance when dispatch applied, nil otherwise
        # (caller falls through to the standard window path).
        def self.na_dispatch_sliding_create(config, insertion_frame)
            return nil unless config.is_a?(Hash)
            return nil unless config["sliding_mode"] == true
            return nil unless defined?(Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem)

            Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem.na_require_sliding_modules
            engine = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::Na__GeometryEngine

            DebugTools.na_debug_geometry("Window->Sliding dispatch: na_create_window_geometry forwarded to Sliding engine")
            engine.na_build_sliding_door(config, nil, insertion_frame)
        rescue StandardError => e
            DebugTools.na_debug_error("WindowSystem -> Sliding dispatch (create) failed", e)
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Delegate Update to Sliding Engine When sliding_mode Is True
        # ------------------------------------------------------------
        # Returns true when dispatch applied (caller short-circuits the
        # standard window path), false otherwise.
        def self.na_dispatch_sliding_update(instance, config)
            return false unless instance && instance.valid?
            return false unless config.is_a?(Hash)
            return false unless config["sliding_mode"] == true
            return false unless defined?(Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem)

            Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem.na_require_sliding_modules
            engine = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::Na__GeometryEngine

            DebugTools.na_debug_geometry("Window->Sliding dispatch: na_update_window_geometry forwarded to Sliding engine")
            engine.na_update_sliding_door(instance, config)
            true
        rescue StandardError => e
            DebugTools.na_debug_error("WindowSystem -> Sliding dispatch (update) failed", e)
            false
        end
        # ---------------------------------------------------------------

        # @delegate: ../34__System__ExteriorDoubleDoorSystem/Na__AssemblyStudio__ExtDouble__GeometryEngine__.rb
        def self.na_dispatch_exterior_double_door_create(config, insertion_frame)
            return nil unless config.is_a?(Hash)
            return nil unless config["double_door_mode"] == true
            return nil unless defined?(Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem)

            Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem.na_require_modules
            engine = Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem::Na__GeometryEngine
            engine.na_build_exterior_double_door(config, nil, insertion_frame)
        rescue StandardError => e
            DebugTools.na_debug_error("WindowSystem -> Exterior Double Door dispatch (create) failed", e)
            nil
        end
        # ---------------------------------------------------------------

        def self.na_dispatch_exterior_double_door_update(instance, config)
            return false unless instance && instance.valid?
            return false unless config.is_a?(Hash)
            return false unless config["double_door_mode"] == true
            return false unless defined?(Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem)

            Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem.na_require_modules
            engine = Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem::Na__GeometryEngine
            engine.na_update_exterior_double_door(instance, config)
            true
        rescue StandardError => e
            DebugTools.na_debug_error("WindowSystem -> Exterior Double Door dispatch (update) failed", e)
            false
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
            sash_horns_enabled = config["sash_horns_enabled"] != false
            sash_horn_type = (config["sash_horn_type"] || "1").to_s
            
            # Flags
            show_casements = config["show_casements"] != false
            has_cill = config["has_cill"] != false
            use_individual_sizes = config["casement_sizes_individual"] == true
            sliding_sash_window = config["sliding_sash_window"] == true
            door_mode = config["door_mode"] == true

            # Door panel parameters
            door_panel_height = (config["door_panel_height_mm"] || 400).to_f * mm_to_inch
            door_panel_columns = (config["door_panel_columns"] || 1).to_i.clamp(1, 4)
            door_panel_rows = (config["door_panel_rows"] || 1).to_i.clamp(1, 3)
            door_panel_rail_width = (config["door_panel_rail_width_mm"] || 30).to_f * mm_to_inch
            door_panel_stile_width = (config["door_panel_stile_width_mm"] || 30).to_f * mm_to_inch
            door_mid_rail_width = (config["door_mid_rail_width_mm"] || 150).to_f * mm_to_inch
            door_base_rail_width = (config["door_base_rail_width_mm"] || 200).to_f * mm_to_inch
            door_panel_margin = (config["door_panel_margin_mm"] || 30).to_f * mm_to_inch
            door_panel_recess_depth = (config["door_panel_recess_depth_mm"] || 8).to_f * mm_to_inch
            door_panel_trim_width = (config["door_panel_trim_width_mm"] || 5).to_f * mm_to_inch
            door_panel_trim_depth = (config["door_panel_trim_depth_mm"] || 3).to_f * mm_to_inch
            door_panel_moulding_inset = (config["door_panel_moulding_inset_mm"] || 5).to_f * mm_to_inch
            door_panel_show_trim = config["door_panel_show_trim"] == true
            
            # Casements per opening (backward compat: twin_casements true â†’ 2)
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

            # Advanced glazebar options (Margin Glazing + Gothic Arch).
            # Booleans pass through untouched; dimensional values convert mm->inches.
            # The amount slider stays as an integer (1..8).
            glazebar_margin_enabled       = config["glazebar_margin_enabled"] == true
            glazebar_margin_offset        = (config["glazebar_margin_offset_mm"] || 0).to_f * mm_to_inch
            glazebar_gothic_arch_enabled  = config["glazebar_gothic_arch_enabled"] == true
            glazebar_gothic_arch_amount   = [[(config["glazebar_gothic_arch_amount"] || 2).to_i, 1].max, 8].min   # <-- V1.9.4 Allow single lancet arch (was clamped to 2 minimum)
            glazebar_gothic_arch_height   = (config["glazebar_gothic_arch_height_mm"] || 0).to_f * mm_to_inch
            # Keep the mm value too so the tessellation count helper can
            # branch on the human-readable height without re-converting.
            glazebar_gothic_arch_height_mm = (config["glazebar_gothic_arch_height_mm"] || 0).to_f
            # Uniform vertical nudge for horizontal bars. Positive = up.
            # Stored in both inches (for direct addition to Z positions)
            # and mm (for diagnostics + parity with other glazebar keys).
            glazebar_horizontal_offset_mm = (config["glazebar_horizontal_offset_mm"] || 0).to_f
            glazebar_horizontal_offset    = glazebar_horizontal_offset_mm * mm_to_inch

            # Per-bar offsets (glazebar_h_offset_N_mm / glazebar_v_offset_N_mm,
            # N = 1-based bar index). Applied AFTER the spacing math, on top
            # of the uniform offset. Horizontal bars: positive = up (+Z).
            # Vertical bars: positive = right (+X). Converted to inches here.
            #
            # V1.9.5 - The pool is gated on the Glaze Bar Offsets toggle.
            # Explicit false drops every nudge so the geometry matches what
            # the panel shows; an absent key is a pre-V1.9.5 config that
            # never had the toggle, so its nudges stay live.
            glazebar_offsets_enabled = config["glazebar_offsets_enabled"] != false
            glazebar_h_bar_offsets = glazebar_offsets_enabled ? (1..h_bars).map { |i| (config["glazebar_h_offset_#{i}_mm"] || 0).to_f * mm_to_inch } : []
            glazebar_v_bar_offsets = glazebar_offsets_enabled ? (1..v_bars).map { |i| (config["glazebar_v_offset_#{i}_mm"] || 0).to_f * mm_to_inch } : []

            # Leaded glass overlay (outer glass face; does not trim glass)
            leaded_resolved = LeadedGlassBuilder.na_resolve_leaded_params(config)
            leaded_disabled_cells = config["leaded_disabled_cells"].is_a?(Array) ? config["leaded_disabled_cells"].map(&:to_s) : []
            
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
            top_sash_bottom_rail = (config["top_sash_bottom_rail_mm"] || cas_bottom_rail.to_mm).to_f * mm_to_inch
            bottom_sash_top_rail_override = config["bottom_sash_top_rail_override"] == true
            bottom_sash_top_rail = if bottom_sash_top_rail_override
                (config["bottom_sash_top_rail_mm"] || cas_top_rail.to_mm).to_f * mm_to_inch
            else
                cas_top_rail
            end
            # Signed nudge for the meeting rail away from the 50/50 split.
            # Positive drives the meeting rail UP (shorter top sash);
            # negative drives it DOWN. Zero when the override is off.
            meeting_rail_offset = if config["meeting_rail_position_override"] == true
                (config["meeting_rail_offset_mm"] || 0).to_f * mm_to_inch
            else
                0.0
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
                sash_horns_enabled: sash_horns_enabled,
                sash_horn_type: sash_horn_type,
                cas_top_rail: cas_top_rail,
                cas_bottom_rail: cas_bottom_rail,
                top_sash_bottom_rail: top_sash_bottom_rail,
                bottom_sash_top_rail_override: bottom_sash_top_rail_override,
                meeting_rail_offset: meeting_rail_offset,
                bottom_sash_top_rail: bottom_sash_top_rail,
                cas_left_stile: cas_left_stile,
                cas_right_stile: cas_right_stile,
                show_casements: show_casements,
                sliding_sash_window: sliding_sash_window,
                door_mode: door_mode,
                door_panel_height: door_panel_height,
                door_panel_columns: door_panel_columns,
                door_panel_rows: door_panel_rows,
                door_panel_rail_width: door_panel_rail_width,
                door_panel_stile_width: door_panel_stile_width,
                door_mid_rail_width: door_mid_rail_width,
                door_base_rail_width: door_base_rail_width,
                door_panel_margin: door_panel_margin,
                door_panel_recess_depth: door_panel_recess_depth,
                door_panel_trim_width: door_panel_trim_width,
                door_panel_trim_depth: door_panel_trim_depth,
                door_panel_moulding_inset: door_panel_moulding_inset,
                door_panel_show_trim: door_panel_show_trim,
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
                glazebar_margin_enabled: glazebar_margin_enabled,
                glazebar_margin_offset: glazebar_margin_offset,
                glazebar_gothic_arch_enabled: glazebar_gothic_arch_enabled,
                glazebar_gothic_arch_amount: glazebar_gothic_arch_amount,
                glazebar_gothic_arch_height: glazebar_gothic_arch_height,
                glazebar_gothic_arch_height_mm: glazebar_gothic_arch_height_mm,
                glazebar_horizontal_offset: glazebar_horizontal_offset,
                glazebar_horizontal_offset_mm: glazebar_horizontal_offset_mm,
                glazebar_h_bar_offsets: glazebar_h_bar_offsets,
                glazebar_v_bar_offsets: glazebar_v_bar_offsets,
                leaded_glass_enabled: leaded_resolved[:enabled],
                horizontal_leaded_bars: leaded_resolved[:h_bars],
                vertical_leaded_bars: leaded_resolved[:v_bars],
                leaded_width: leaded_resolved[:width],
                leaded_depth: leaded_resolved[:depth],
                leaded_centre_lines_only: leaded_resolved[:centre_lines],
                leaded_mte_id: leaded_resolved[:mte_id],
                leaded_disabled_cells: leaded_disabled_cells,
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
            # Create outer frame (skip in frameless mode)
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

            # Create each opening (full height; door panels live inside casements)
            (0...params[:num_openings]).each do |i|
                na_create_opening(entities, i, params, frame_material, glass_material)
            end

            # Create cill
            if params[:has_cill] && params[:frame_bottom_thickness] > 0
                GeometryBuilders.na_create_cill_geometry(
                    entities, params[:width], params[:cill_depth], params[:cill_height],
                    params[:frame_depth], cill_material, params[:frame_wall_inset]
                )
            end

            na_apply_cill_lift(entities, params)                                # <-- V1.7.1: shift everything up so the cill sits ON the floor (fixes pre-existing Z bug)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Lift the Window So the Cill Sits ON Top of the Floor (V1.7.1)
        # ------------------------------------------------------------
        # Pre-V1.7.1 the cill geometry occupied the negative-Z slab below
        # the frame (z = -cill_height to 0). When the user dropped the
        # component at floor level the cill ended up below the floor and
        # the entire window was effectively cill_height too low - they
        # had to manually nudge it up to close the gap at the head.
        #
        # V1.7.1: Post-process the definition by translating every entity
        # up by cill_height when the cill is enabled. The cill ends up
        # at z = 0..H (sitting on the floor), the frame moves up to
        # z = H..H+frame_h (sitting on the cill), and every casement /
        # mullion / glaze bar rises with it so the relative geometry
        # stays consistent.
        def self.na_apply_cill_lift(entities, params)
            return unless entities
            return unless params[:has_cill]
            return unless params[:frame_bottom_thickness] > 0

            cill_height_in = params[:cill_height].to_f
            return if cill_height_in <= 0.0

            translation = Geom::Transformation.translation(Geom::Vector3d.new(0.0, 0.0, cill_height_in))
            targets     = entities.to_a
            return if targets.empty?

            entities.transform_entities(translation, targets)
        rescue StandardError => e
            DebugTools.na_debug_error("WindowSystem na_apply_cill_lift failed", e)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Create Single Opening (Casement + Glass + Glaze Bars)
        # ------------------------------------------------------------
        # Creates geometry for one opening with N casement panels and optional transoms.
        # Supports 1-6 casements per opening (bifold/concertina panels).
        # Respects removed casements and removed transom segments.
        def self.na_create_opening(entities, opening_index, params, frame_material, glass_material)
            opening_x = params[:frame_left_thickness] + (opening_index * (params[:opening_width] + params[:mullion_width]))
            opening_layout = na_get_opening_layout(opening_index, opening_x, params)
            show_casements = params[:show_casements]                                                                # <-- Master casement visibility (per-panel removal handled inside dispatch)

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
                if show_casements && params[:sliding_sash_window]
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
                        show_casements,
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

        # FUNCTION | Check Whether a Casement Panel Is Removed
        # ------------------------------------------------------------
        # Legacy-aware: bare-integer entries (e.g. 0) match every panel of that opening.
        # New-format entries are exact "openingIndex:cellIndex:panelIndex" strings.
        def self.na_panel_casement_removed?(removed_casements, opening_index, cell_index, panel_index)
            return false unless removed_casements.is_a?(Array)
            return true if removed_casements.include?("#{opening_index}:#{cell_index}:#{panel_index}")              # <-- New per-panel key
            return true if removed_casements.include?(opening_index)                                                # <-- Legacy bare-integer match
            removed_casements.any? do |entry|
                next false if entry.nil?
                next false if entry.is_a?(String) && entry.include?(':')
                Integer(entry.to_s) == opening_index rescue false                                                   # <-- Legacy stringified integer match
            end
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
        # The fifth-from-right argument is the master `show_casements` flag; per-panel
        # removal (`removed_casements`) is resolved inline for each panel.
        def self.na_create_multi_casement_opening(entities, opening_index, cell_index, opening_x, opening_z, opening_height, show_casements, params, frame_material, glass_material)
            num_panels = params[:casements_per_opening]
            panel_width = params[:opening_width] / num_panels.to_f

            (0...num_panels).each do |p|
                panel_x = opening_x + (p * panel_width)
                panel_id = "#{opening_index}_#{cell_index}_P#{p}"
                panel_has_casement = show_casements && !na_panel_casement_removed?(                                 # <-- Per-panel removal lookup
                    params[:removed_casements],
                    opening_index,
                    cell_index,
                    p
                )

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
                    panel_has_casement,
                    params[:frame_wall_inset],
                    params,
                    frame_material,
                    glass_material
                )
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Resolve Meeting Rail Height Within a Sash Cell
        # ------------------------------------------------------------
        # Returns the height of the bottom sash zone measured up from the
        # cell floor - i.e. where the meeting rail sits inside the cell.
        # offset is signed and in inches: positive drives the meeting rail
        # UP (shorter top sash), negative drives it DOWN. Clamped so
        # neither sash falls below 10% of the cell height. An offset of 0
        # returns the exact 50/50 split so legacy models are unchanged.
        # Mirrors SvgGenerator.na_resolveMeetingRailHeight (2D preview) so
        # the built geometry matches what the user saw in the dialog.
        def self.na_resolve_meeting_rail_height(cell_height, offset)
            height_value = cell_height.to_f
            centre_split = height_value / 2.0
            offset_value = offset.to_f
            return centre_split if offset_value == 0.0
            [[centre_split + offset_value, height_value * 0.10].max, height_value * 0.90].min
        end
        # ---------------------------------------------------------------

        # FUNCTION | Create Sliding Sash Opening Cell
        # ------------------------------------------------------------
        # Creates two vertically stacked casements per horizontal panel.
        # Bottom sash is set back by one casement depth to simulate sliding overlap.
        def self.na_create_sliding_sash_opening(entities, opening_index, cell_index, opening_x, opening_z, opening_height, params, frame_material, glass_material)
            num_panels = params[:casements_per_opening]
            panel_width = params[:opening_width] / num_panels.to_f
            meeting_rail_y = na_resolve_meeting_rail_height(opening_height, params[:meeting_rail_offset])
            bottom_sash_height = meeting_rail_y                                                              # <-- Cell floor up to the meeting rail
            top_sash_height = opening_height.to_f - meeting_rail_y                                           # <-- Meeting rail up to the cell head
            sash_overlap = [params[:sliding_sash_overlap].to_f, top_sash_height - 1.mm.to_f].min             # <-- Bottom sash tucks up into the top sash
            sash_overlap = [sash_overlap, 0.0].max

            (0...num_panels).each do |p|
                panel_x = opening_x + (p * panel_width)
                base_panel_id = "#{opening_index}_#{cell_index}_P#{p}"
                top_panel_id = "#{base_panel_id}_Top"
                bottom_panel_id = "#{base_panel_id}_Bottom"
                panel_has_casement = params[:show_casements] && !na_panel_casement_removed?(                        # <-- Same key shared by both sashes
                    params[:removed_casements],
                    opening_index,
                    cell_index,
                    p
                )

                na_render_opening_panel_geometry(
                    entities,
                    top_panel_id,
                    opening_index,
                    cell_index,
                    p,
                    0,
                    panel_x,
                    opening_z + meeting_rail_y,
                    panel_width,
                    top_sash_height,
                    panel_has_casement,
                    params[:frame_wall_inset],
                    params,
                    frame_material,
                    glass_material
                )

                if panel_has_casement && params[:sash_horns_enabled]
                    SashHornBuilder.na_build_sash_horns(
                        entities,
                        top_panel_id,
                        panel_x,
                        opening_z + meeting_rail_y,
                        panel_width,
                        params,
                        frame_material
                    )
                end

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
                    bottom_sash_height + sash_overlap,
                    panel_has_casement,
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
        # Shared panel renderer for standard, sliding sash, and door modes.
        # In door mode with casement, builds a full-height door with mid-rail,
        # glass in upper zone, and solid panel content in lower zone.
        def self.na_render_opening_panel_geometry(entities, panel_id, opening_index, cell_index, panel_index, sash_index, panel_x, panel_z, panel_width, panel_height, panel_has_casement, panel_wall_inset, params, frame_material, glass_material)
            if panel_has_casement && params[:door_mode]
                na_render_door_casement_geometry(
                    entities, panel_id, opening_index, cell_index, panel_index, sash_index,
                    panel_x, panel_z, panel_width, panel_height,
                    panel_wall_inset, params, frame_material, glass_material
                )
            elsif panel_has_casement
                top_rail = na_effective_panel_top_rail(sash_index, params)
                bottom_rail = na_effective_panel_bottom_rail(sash_index, params)

                GeometryBuilders.na_create_casement_geometry_individual(
                    entities, panel_id, panel_width, panel_height,
                    top_rail, bottom_rail, params[:cas_left_stile], params[:cas_right_stile],
                    params[:casement_depth], panel_x, panel_z, frame_material, panel_wall_inset, params[:casement_inset]
                )

                glass_offset_x = panel_x + params[:cas_left_stile]
                glass_offset_z = panel_z + bottom_rail
                glass_w = panel_width - params[:cas_left_stile] - params[:cas_right_stile]
                glass_h = panel_height - top_rail - bottom_rail

                GeometryBuilders.na_create_glass_geometry(
                    entities, panel_id, glass_w, glass_h, params[:glass_thickness],
                    glass_offset_x, glass_offset_z, params[:frame_depth], glass_material,
                    panel_wall_inset, params[:casement_depth], params[:casement_inset]
                )

                if params[:h_bars] > 0 || params[:v_bars] > 0 || params[:glazebar_gothic_arch_enabled]
                    GeometryBuilders.na_create_glazebar_geometry(
                        entities, panel_id, glass_w, glass_h, params[:h_bars], params[:v_bars],
                        params[:bar_width], params[:glass_thickness], glass_offset_x, glass_offset_z,
                        params[:frame_depth], frame_material, panel_wall_inset,
                        params[:casement_depth], params[:casement_inset], params[:glazebar_inset],
                        params[:removed_glazebars], opening_index, cell_index, panel_index, sash_index,
                        na_advanced_glazebar_hash(params)
                    )
                end

                na_create_leaded_for_glass(
                    entities, panel_id, glass_w, glass_h, glass_offset_x, glass_offset_z,
                    panel_wall_inset, params[:glass_thickness], params[:frame_depth],
                    params[:casement_depth], params[:casement_inset], params,
                    opening_index, cell_index, panel_index, sash_index
                )
            else
                GeometryBuilders.na_create_glass_geometry(
                    entities, panel_id, panel_width, panel_height, params[:glass_thickness],
                    panel_x, panel_z, params[:frame_depth], glass_material, panel_wall_inset
                )

                if params[:h_bars] > 0 || params[:v_bars] > 0 || params[:glazebar_gothic_arch_enabled]
                    GeometryBuilders.na_create_glazebar_geometry(
                        entities, panel_id, panel_width, panel_height, params[:h_bars], params[:v_bars],
                        params[:bar_width], params[:glass_thickness], panel_x, panel_z,
                        params[:frame_depth], frame_material, panel_wall_inset,
                        nil, nil, params[:glazebar_inset],
                        params[:removed_glazebars], opening_index, cell_index, panel_index, sash_index,
                        na_advanced_glazebar_hash(params)
                    )
                end

                na_create_leaded_for_glass(
                    entities, panel_id, panel_width, panel_height, panel_x, panel_z,
                    panel_wall_inset, params[:glass_thickness], params[:frame_depth],
                    nil, nil, params,
                    opening_index, cell_index, panel_index, sash_index
                )
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Pack Advanced Glazebar Params Into A Hash
        # ------------------------------------------------------------
        # Single source of truth for the hash GeometryBuilders consumes.
        # Centralised so the three call sites in this file all stay in
        # lockstep when keys are added or renamed.
        def self.na_advanced_glazebar_hash(params)
            {
                margin_enabled:  params[:glazebar_margin_enabled],
                margin_offset:   params[:glazebar_margin_offset],
                arch_enabled:    params[:glazebar_gothic_arch_enabled],
                arch_amount:     params[:glazebar_gothic_arch_amount],
                arch_height:     params[:glazebar_gothic_arch_height],
                arch_height_mm:  params[:glazebar_gothic_arch_height_mm],
                h_offset:        params[:glazebar_horizontal_offset],                          # <-- inches
                h_offset_mm:     params[:glazebar_horizontal_offset_mm],                       # <-- mm (for diagnostics)
                h_bar_offsets:   params[:glazebar_h_bar_offsets],                              # <-- inches; per-bar vertical nudges (positive = up)
                v_bar_offsets:   params[:glazebar_v_bar_offsets]                               # <-- inches; per-bar horizontal nudges (positive = right)
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Create Leaded Glass Overlay For One Glass Pane
        # ------------------------------------------------------------
        # Lead lines are laid out per glazing cell between the FINAL glaze
        # bar centerlines (offsets included) so lead never crosses a bar.
        # The panel context (opening/cell/panel/sash) keys the per-cell
        # disabled set toggled from the SVG preview.
        def self.na_create_leaded_for_glass(
            entities, panel_id, glass_w, glass_h, offset_x, offset_z,
            wall_inset, glass_thickness, frame_depth, casement_depth, casement_inset, params,
            opening_index = 0, cell_index = 0, panel_index = 0, sash_index = 0
        )
            leaded = LeadedGlassBuilder.na_resolve_leaded_params_from_engine(params)
            return unless leaded[:enabled]
            return if leaded[:h_bars] <= 0 && leaded[:v_bars] <= 0

            y_front = LeadedGlassBuilder.na_glass_outer_face_y(
                wall_inset, glass_thickness, frame_depth, casement_depth, casement_inset
            )

            bar_layout = GeometryBuilders.na_compute_final_bar_positions(
                offset_x, offset_z, glass_w, glass_h,
                params[:h_bars], params[:v_bars], params[:bar_width],
                na_advanced_glazebar_hash(params)
            )
            grid = {
                h_positions: bar_layout[:h_positions],
                v_positions: bar_layout[:v_positions],
                bar_width: params[:bar_width],
                effective_glass_height: bar_layout[:effective_glass_height],
                panel_context: { opening: opening_index, cell: cell_index, panel: panel_index, sash: sash_index },
                disabled_cells: params[:leaded_disabled_cells]
            }

            LeadedGlassBuilder.na_create_leaded_glass_geometry(
                entities, panel_id, glass_w, glass_h, offset_x, offset_z, y_front, leaded, grid: grid
            )
        end
        private_class_method :na_create_leaded_for_glass
        # ---------------------------------------------------------------

        # FUNCTION | Resolve Panel Bottom Rail
        # ------------------------------------------------------------
        def self.na_effective_panel_bottom_rail(sash_index, params)
            if params[:sliding_sash_window] && sash_index == 0
                return params[:top_sash_bottom_rail]
            end

            params[:cas_bottom_rail]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Resolve Panel Top Rail
        # ------------------------------------------------------------
        def self.na_effective_panel_top_rail(sash_index, params)
            if params[:sliding_sash_window] && sash_index == 1
                return params[:bottom_sash_top_rail]
            end

            params[:cas_top_rail]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Render Door Casement Geometry
        # ------------------------------------------------------------
        # Builds a full-height door casement with:
        # - Stiles spanning full height
        # - Top rail, bottom rail, and mid-rail at the glass/panel junction
        # - Glass + glaze bars in the upper (glazed) zone
        # - Solid door panel content in the lower zone
        def self.na_render_door_casement_geometry(entities, panel_id, opening_index, cell_index, panel_index, sash_index, panel_x, panel_z, panel_width, panel_height, panel_wall_inset, params, frame_material, glass_material)
            mid_rail_w = params[:door_mid_rail_width]
            base_rail_w = params[:door_base_rail_width]
            door_panel_h = [params[:door_panel_height], panel_height - params[:cas_top_rail] - mid_rail_w - base_rail_w - 50.mm].min
            door_panel_h = [door_panel_h, 0].max

            y_offset = panel_wall_inset + params[:casement_inset]
            cas_depth = params[:casement_depth]

            # Casement stiles -- full height
            GeometryHelpers.na_create_casement_stile(entities, panel_id, "Left", panel_x, y_offset, panel_z, params[:cas_left_stile], cas_depth, panel_height, frame_material)
            GeometryHelpers.na_create_casement_stile(entities, panel_id, "Right", panel_x + panel_width - params[:cas_right_stile], y_offset, panel_z, params[:cas_right_stile], cas_depth, panel_height, frame_material)

            rail_clear_width = panel_width - params[:cas_left_stile] - params[:cas_right_stile]

            # Base rail (bottom of the door)
            GeometryHelpers.na_create_casement_rail(entities, panel_id, "Bottom", panel_x + params[:cas_left_stile], y_offset, panel_z, rail_clear_width, cas_depth, base_rail_w, frame_material)

            # Top rail
            GeometryHelpers.na_create_casement_rail(entities, panel_id, "Top", panel_x + params[:cas_left_stile], y_offset, panel_z + panel_height - params[:cas_top_rail], rail_clear_width, cas_depth, params[:cas_top_rail], frame_material)

            # Mid-rail at the junction between panel and glass zones
            mid_rail_z = panel_z + base_rail_w + door_panel_h
            GeometryHelpers.na_create_casement_rail(entities, panel_id, "Mid", panel_x + params[:cas_left_stile], y_offset, mid_rail_z, rail_clear_width, cas_depth, mid_rail_w, frame_material)

            # Upper zone: glass + glaze bars
            glass_x = panel_x + params[:cas_left_stile]
            glass_z = mid_rail_z + mid_rail_w
            glass_w = rail_clear_width
            glass_h = panel_height - params[:cas_top_rail] - mid_rail_w - door_panel_h - base_rail_w

            if glass_h > 0 && glass_w > 0
                GeometryBuilders.na_create_glass_geometry(
                    entities, panel_id, glass_w, glass_h, params[:glass_thickness],
                    glass_x, glass_z, params[:frame_depth], glass_material,
                    panel_wall_inset, cas_depth, params[:casement_inset]
                )

                if params[:h_bars] > 0 || params[:v_bars] > 0 || params[:glazebar_gothic_arch_enabled]
                    GeometryBuilders.na_create_glazebar_geometry(
                        entities, panel_id, glass_w, glass_h, params[:h_bars], params[:v_bars],
                        params[:bar_width], params[:glass_thickness], glass_x, glass_z,
                        params[:frame_depth], frame_material, panel_wall_inset,
                        cas_depth, params[:casement_inset], params[:glazebar_inset],
                        params[:removed_glazebars], opening_index, cell_index, panel_index, sash_index,
                        na_advanced_glazebar_hash(params)
                    )
                end

                na_create_leaded_for_glass(
                    entities, panel_id, glass_w, glass_h, glass_x, glass_z,
                    panel_wall_inset, params[:glass_thickness], params[:frame_depth],
                    cas_depth, params[:casement_inset], params,
                    opening_index, cell_index, panel_index, sash_index
                )
            end

            # Lower zone: door panel content (inside casement stiles, between base rail and mid-rail)
            inner_panel_x = panel_x + params[:cas_left_stile]
            inner_panel_z = panel_z + base_rail_w
            inner_panel_w = rail_clear_width
            inner_panel_h = door_panel_h

            if inner_panel_h > 0 && inner_panel_w > 0
                context = Na__AssemblyStudio::Na__ExteriorSingleDoorSystem::DoorPanelContext.new(
                    entities, panel_id,
                    inner_panel_x, inner_panel_z, inner_panel_w, inner_panel_h,
                    params[:casement_depth], params[:frame_wall_inset], params[:casement_inset],
                    params, frame_material
                )
                DoorPanelInterface.call.na_build_panel(context)
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__GeometryEngine
end # module Na__WindowSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
