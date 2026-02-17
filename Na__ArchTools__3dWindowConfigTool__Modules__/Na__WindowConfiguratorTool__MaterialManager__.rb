# =============================================================================
# NA WINDOW CONFIGURATOR TOOL - MATERIAL MANAGER
# =============================================================================
#
# FILE       : Na__WindowConfiguratorTool__MaterialManager__.rb
# NAMESPACE  : Na__WindowConfiguratorTool
# MODULE     : Na__MaterialManager
# AUTHOR     : Noble Architecture
# PURPOSE    : Centralized material library management
# CREATED    : 2026-02-16
# VERSION    : 1.0.0
#
# DESCRIPTION:
# - Loads materials library from JSON configuration
# - Creates and manages standard SketchUp materials
# - Provides material lookup by ID or SketchUp name
# - Prevents material proliferation by reusing standard materials
# - Supports material property updates (color, opacity, roughness)
# - Handles special "Default" material (returns nil = SketchUp default)
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix
#
# =============================================================================

require 'sketchup.rb'
require 'json'

module Na__WindowConfiguratorTool
    module Na__MaterialManager

# -----------------------------------------------------------------------------
# REGION | Module Variables
# -----------------------------------------------------------------------------

        @na_materials_library = nil                     # Parsed JSON library
        @na_material_cache = {}                         # Cache of created SketchUp materials

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Initialization
# -----------------------------------------------------------------------------

        # FUNCTION | Load Materials Library
        # ------------------------------------------------------------
        # Loads and parses the materials library JSON file.
        # 
        # @param library_path [String] Path to the materials library JSON file
        # @return [Hash, nil] Parsed materials library or nil if error
        def self.na_load_materials_library(library_path)
            begin
                unless File.exist?(library_path)
                    puts "ERROR: Materials library not found: #{library_path}"
                    return nil
                end
                
                json_content = File.read(library_path)
                parsed = JSON.parse(json_content)
                
                @na_materials_library = parsed["Na__AppConfig__MaterialsLibrary"]
                
                if @na_materials_library.nil?
                    puts "ERROR: Invalid materials library structure"
                    return nil
                end
                
                puts "SUCCESS: Loaded materials library with #{na_count_materials} materials"
                return @na_materials_library
                
            rescue JSON::ParserError => e
                puts "ERROR: Failed to parse materials library JSON: #{e.message}"
                return nil
            rescue => e
                puts "ERROR: Failed to load materials library: #{e.message}"
                return nil
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Initialize Standard Materials
        # ------------------------------------------------------------
        # Creates all standard materials from the library in SketchUp.
        # Should be called once at plugin initialization.
        # 
        # @param library_path [String] Path to the materials library JSON file
        # @return [Boolean] Success status
        def self.na_initialize_standard_materials(library_path)
            begin
                # Load library if not already loaded
                if @na_materials_library.nil?
                    na_load_materials_library(library_path)
                    return false if @na_materials_library.nil?
                end
                
                # Check if active model exists
                model = Sketchup.active_model
                unless model
                    puts "WARNING: No active model - materials will be initialized when needed"
                    return false
                end
                
                materials = model.materials
                
                created_count = 0
                
                # Iterate through all material series
                @na_materials_library.each do |series_name, series_materials|
                    series_materials.each do |material_id, material_props|
                        sketchup_name = material_props["SketchUpName"]
                        
                        # Skip if invalid or default marker
                        next if sketchup_name.nil? || 
                                sketchup_name == "N/A Assigned By SketchUp" || 
                                sketchup_name == "__SKETCHUP_DEFAULT__" ||
                                material_props["IsDefault"] == true
                        
                        # Create or update material
                        material = na_create_or_update_material(sketchup_name, material_props)
                        
                        if material
                            @na_material_cache[material_id] = material
                            created_count += 1
                        end
                    end
                end
                
                puts "SUCCESS: Initialized #{created_count} standard materials"
                return true
                
            rescue => e
                puts "ERROR: Failed to initialize standard materials: #{e.message}"
                puts e.backtrace.join("\n")
                return false
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Material Creation and Management
# -----------------------------------------------------------------------------

        # FUNCTION | Create or Update Material
        # ------------------------------------------------------------
        # Creates a new SketchUp material or updates an existing one.
        # 
        # @param name [String] SketchUp material name
        # @param properties [Hash] Material properties from JSON
        # @return [Sketchup::Material, nil] Created/updated material
        def self.na_create_or_update_material(name, properties)
            begin
                # Skip creating material for SketchUp default
                return nil if name == "__SKETCHUP_DEFAULT__"
                
                model = Sketchup.active_model
                return nil unless model
                
                materials = model.materials
                material = materials[name]
                
                # Create if doesn't exist
                unless material
                    material = materials.add(name)
                end
                
                # Parse and apply base color
                base_color = properties["BaseColor"]
                if base_color
                    color = na_parse_rgb_string(base_color)
                    material.color = color if color
                end
                
                # Apply opacity/alpha
                opacity = properties["Opacity"]
                if opacity
                    material.alpha = opacity.to_f
                end
                
                # Note: PbrRoughness is stored for future use but not applied to SketchUp material
                # as it's intended for downstream rendering engines
                
                return material
                
            rescue => e
                puts "ERROR: Failed to create/update material '#{name}': #{e.message}"
                return nil
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Parse RGB String
        # ------------------------------------------------------------
        # Parses RGB string format "rgb(r, g, b)" into Sketchup::Color.
        # 
        # @param rgb_string [String] RGB string (e.g., "rgb(255, 255, 255)")
        # @return [Sketchup::Color, nil] Parsed color or nil if invalid
        def self.na_parse_rgb_string(rgb_string)
            return nil if rgb_string.nil? || rgb_string.empty?
            
            # Match rgb(r, g, b) format with flexible whitespace
            match = rgb_string.match(/rgb\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)/)
            
            if match
                r = match[1].to_i
                g = match[2].to_i
                b = match[3].to_i
                return Sketchup::Color.new(r, g, b)
            end
            
            puts "WARNING: Invalid RGB format: #{rgb_string}"
            return nil
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Material Lookup
# -----------------------------------------------------------------------------

        # FUNCTION | Get Material by ID
        # ------------------------------------------------------------
        # Retrieves a material by its library ID (e.g., "MAT101__GenericGlass").
        # Returns cached material if available, otherwise searches library.
        # Creates material on-demand if not found (lazy initialization).
        # Special case: Returns nil for MAT001__Default (SketchUp default material).
        # 
        # @param material_id [String] Material ID from library
        # @return [Sketchup::Material, nil] Material or nil if not found/default
        def self.na_get_material_by_id(material_id)
            return nil if material_id.nil? || material_id.empty?
            
            # Check cache first
            if @na_material_cache.key?(material_id)
                material = @na_material_cache[material_id]
                return material if material && material.valid?
            end
            
            # Ensure library is loaded
            if @na_materials_library.nil?
                puts "WARNING: Materials library not loaded - materials cannot be created"
                return nil
            end
            
            # Search library and create material on-demand
            @na_materials_library.each do |series_name, series_materials|
                if series_materials.key?(material_id)
                    material_props = series_materials[material_id]
                    
                    # Special case: Handle SketchUp default material
                    if material_props["IsDefault"] == true || 
                       material_props["SketchUpName"] == "__SKETCHUP_DEFAULT__"
                        puts "Returning nil for SketchUp default material (#{material_id})"
                        return nil  # nil = SketchUp default
                    end
                    
                    sketchup_name = material_props["SketchUpName"]
                    
                    # Check if model exists
                    model = Sketchup.active_model
                    return nil unless model
                    
                    # Try to get existing material
                    material = model.materials[sketchup_name]
                    
                    # Create on-demand if doesn't exist
                    if material.nil?
                        puts "Creating material on-demand: #{sketchup_name}"
                        material = na_create_or_update_material(sketchup_name, material_props)
                    end
                    
                    # Cache for future lookups
                    @na_material_cache[material_id] = material if material
                    
                    return material
                end
            end
            
            puts "WARNING: Material not found: #{material_id}"
            return nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Get Material by SketchUp Name
        # ------------------------------------------------------------
        # Retrieves a material by its SketchUp material name.
        # 
        # @param sketchup_name [String] SketchUp material name
        # @return [Sketchup::Material, nil] Material or nil if not found
        def self.na_get_material_by_sketchup_name(sketchup_name)
            return nil if sketchup_name.nil? || sketchup_name.empty?
            
            model = Sketchup.active_model
            return nil unless model
            
            materials = model.materials
            return materials[sketchup_name]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Get Material ID from SketchUp Name
        # ------------------------------------------------------------
        # Reverse lookup: finds the library ID for a given SketchUp material name.
        # 
        # @param sketchup_name [String] SketchUp material name
        # @return [String, nil] Material ID or nil if not found
        def self.na_get_material_id_from_name(sketchup_name)
            return nil if sketchup_name.nil? || @na_materials_library.nil?
            
            @na_materials_library.each do |series_name, series_materials|
                series_materials.each do |material_id, material_props|
                    if material_props["SketchUpName"] == sketchup_name
                        return material_id
                    end
                end
            end
            
            return nil
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Utility Functions
# -----------------------------------------------------------------------------

        # FUNCTION | Count Materials
        # ------------------------------------------------------------
        # Counts the total number of materials in the library.
        # 
        # @return [Integer] Total material count
        def self.na_count_materials
            return 0 if @na_materials_library.nil?
            
            count = 0
            @na_materials_library.each do |series_name, series_materials|
                count += series_materials.count
            end
            return count
        end
        # ---------------------------------------------------------------

        # FUNCTION | Get All Material IDs
        # ------------------------------------------------------------
        # Returns an array of all material IDs in the library.
        # 
        # @return [Array<String>] Array of material IDs
        def self.na_get_all_material_ids
            ids = []
            return ids if @na_materials_library.nil?
            
            @na_materials_library.each do |series_name, series_materials|
                ids.concat(series_materials.keys)
            end
            return ids
        end
        # ---------------------------------------------------------------

        # FUNCTION | Clean Up Old Materials (Utility)
        # ------------------------------------------------------------
        # Removes legacy per-window materials (Na_Frame_Wood_AWN*, etc.).
        # Use with caution - prompts user before deletion.
        # 
        # @return [Integer] Number of materials removed
        def self.na_cleanup_old_materials
            model = Sketchup.active_model
            return 0 unless model
            
            materials = model.materials
            
            patterns = [
                /^Na_Frame_Wood_AWN\d+$/,
                /^Na_Glass_AWN\d+$/,
                /^Na_Cill_Stone_AWN\d+$/
            ]
            
            to_remove = []
            
            materials.each do |material|
                patterns.each do |pattern|
                    if material.name.match?(pattern)
                        to_remove << material
                        break
                    end
                end
            end
            
            if to_remove.empty?
                puts "INFO: No legacy materials found to clean up"
                return 0
            end
            
            # Prompt user
            result = UI.messagebox(
                "Found #{to_remove.count} legacy per-window materials.\n\nRemove them?",
                MB_YESNO
            )
            
            if result == IDYES
                removed_count = 0
                to_remove.each do |material|
                    begin
                        materials.remove(material)
                        removed_count += 1
                    rescue => e
                        puts "WARNING: Failed to remove material '#{material.name}': #{e.message}"
                    end
                end
                
                puts "SUCCESS: Removed #{removed_count} legacy materials"
                return removed_count
            else
                puts "INFO: Material cleanup cancelled by user"
                return 0
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__MaterialManager
end # module Na__WindowConfiguratorTool

# =============================================================================
# END OF FILE
# =============================================================================
