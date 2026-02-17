# =============================================================================
# TRUEVISION3D - GLB BUILDER UTILITY - CORE EXPORT MODULE
# =============================================================================
#
# FILE       : Na__TrueVision__GlbBuilder__CoreExport__.rb
# NAMESPACE  : TrueVision3D::GlbBuilderUtility
# MODULE     : Core Export Logic
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Core export orchestration and validation logic
# CREATED    : 2025
#
# DESCRIPTION:
# - Export orchestration and state management
# - Model validation and entity organization
# - Tag-based export segmentation
# - Helper functions for coordinate conversion
#
# DEPENDENCIES:
# - Requires module constants from Main file
# - Requires EngineCore module for GLB writing
# - Accesses module instance variables (@material_map, @excluded_layers, etc.)
#
# =============================================================================

module TrueVision3D
    module GlbBuilderUtility
    
    # -----------------------------------------------------------------------------
    # REGION | Export State Management
    # -----------------------------------------------------------------------------
    
        # FUNCTION | Reset All Module State Variables
        # ---------------------------------------------------------------
        def self.Na__ExportCore__ResetState
            puts "    Resetting module state for new export..."
            
            # Clear all mapping variables
            @material_map           = {}                                          # <-- Material to index mapping
            @texture_map            = {}                                          # <-- Texture to index mapping
            @image_map              = {}                                          # <-- Image data mapping
            @texture_cache          = {}                                          # <-- Texture cache
            
            # Clear validation and layer data
            @validation_errors      = []                                          # <-- Validation error messages
            @excluded_layers        = []                                          # <-- Array of excluded layer names
            
            # Clear any progress tracking
            @last_reported_percentage = nil                                       # <-- Reset progress tracking
            
            puts "    Module state reset complete"
        end
        # ---------------------------------------------------------------
    
        # FUNCTION | Initialize GLB Export Process
        # ------------------------------------------------------------
        def self.Na__ExportCore__StartExport
            puts "DEBUG: Na__ExportCore__StartExport called"
            model = Sketchup.active_model                                         # Get active model
            
            # Check if there's anything to export using correct SketchUp API
            if model.active_entities.length == 0
                UI.messagebox("No entities to export in the current model.")      # Alert user
                return false
            end
            
            # Reset state at the very beginning
            puts "DEBUG: Calling Na__ExportCore__ResetState"
            self.Na__ExportCore__ResetState                                            # Comprehensive state reset
            
            puts "DEBUG: Calling Na__ExportCore__IdentifyExcludedLayers"
            self.Na__ExportCore__IdentifyExcludedLayers(model)                         # Identify layers to exclude
            
            # Virtual flattening export works with any geometry, not just manifold solids
            puts "\n=== Starting TrueVision GLB Export (Virtual Flattening) ==="   # Console header
            puts "Using non-destructive recursive traversal for world-space coordinates"
            
            # DEBUG MODE: Texture export pipeline is disabled while resolving core geometry.
            # Cache folder setup is intentionally skipped until texture exporting is re-enabled.
            puts "DEBUG: Texture export disabled; skipping texture cache folder setup."
            
            puts "DEBUG: Calling Na__UserInterface__ShowExportDialog"
            self.Na__UserInterface__ShowExportDialog                                    # Show export options dialog
        end
        # ---------------------------------------------------------------
    
    # endregion -------------------------------------------------------------------
    



    # -----------------------------------------------------------------------------
    # REGION | Helper Functions
    # -----------------------------------------------------------------------------
    
        # HELPER FUNCTION | Convert SketchUp Units to glTF
        # ---------------------------------------------------------------
        def self.Na__Helpers__ConvertInchesToMeters(x, y, z)
            # Convert from inches to meters (glTF standard)
            # We're using a root rotation for coordinate system conversion
            # so we only need unit conversion here
            [
                x * INCHES_TO_METERS,
                y * INCHES_TO_METERS,
                z * INCHES_TO_METERS
            ]
        end
        # ---------------------------------------------------------------
        
        # HELPER FUNCTION | Convert SketchUp Transformation Matrix to glTF
        # ---------------------------------------------------------------
        def self.Na__Helpers__ConvertSketchUpMatrixToGltf(transform)
            # SketchUp uses 4x4 matrix in row-major order
            # glTF expects column-major order
            # Root node handles coordinate system conversion
            
            # Convert units for translation
            origin = transform.origin
            gltf_origin = self.Na__Helpers__ConvertInchesToMeters(origin.x, origin.y, origin.z)
            
            # Build column-major matrix for glTF
            matrix = []
            4.times do |col|
                4.times do |row|
                    if row < 3 && col == 3
                        # Translation column - use converted values
                        matrix << gltf_origin[row]
                    else
                        # Other values stay as-is
                        matrix << transform.to_a[row * 4 + col]
                    end
                end
            end
            
            matrix
        end
        # ---------------------------------------------------------------
        
        # HELPER FUNCTION | Check if Entity Should Be Excluded
        # ---------------------------------------------------------------
        def self.Na__Helpers__EntityExcluded?(entity)
            return false unless entity.respond_to?(:layer)                        # Skip if no layer
            @excluded_layers.include?(entity.layer.name)                          # Check exclusion
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Extract Project Prefix from SketchUp Filename
        # ---------------------------------------------------------------
        def self.Na__Helpers__ExtractProjectPrefix(model)
            # Get the model's file path using SketchUp API
            model_path = model.path
            
            # Handle unsaved files
            if model_path.nil? || model_path.empty?
                puts "  No project prefix - model not saved yet"
                return ""
            end
            
            # Extract filename from path
            filename = File.basename(model_path)
            
            # Extract first section before "__" (e.g., "Rowbotham__" from "Rowbotham__WhiteCardModel__0.3.0__.skp")
            match = filename.match(/^([^_]+)__/)
            
            if match
                prefix = "#{match[1]}__"
                puts "  Project prefix detected: '#{prefix}'"
                return prefix
            else
                puts "  No project prefix found in filename: #{filename}"
                return ""
            end
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Cleanup Texture Cache
        # ---------------------------------------------------------------
        def self.Na__Helpers__CleanupTextureCache
            # DEBUG MODE: Texture exporting is disabled while resolving core geometry.
            # Keeping this function as a no-op preserves call compatibility.
            puts "      Texture cache cleanup bypassed (texture export disabled)."
            return

            return unless Dir.exist?(@texture_cache_folder)
            
            Dir.glob(File.join(@texture_cache_folder, "*")).each do |file|
                File.delete(file) if File.file?(file)
            end
            
            Dir.rmdir(@texture_cache_folder) if Dir.empty?(@texture_cache_folder)
            puts "      Cleaned up texture cache folder"
        end
        # ---------------------------------------------------------------
    
        # HELPER FUNCTION | Open Folder in File Explorer
        # ---------------------------------------------------------------
        def self.Na__Helpers__OpenFolder(path)
            if Sketchup.platform == :platform_win
                system("explorer \"#{path.gsub('/', '\\')}\"")                    # Windows
            elsif Sketchup.platform == :platform_osx
                system("open \"#{path}\"")                                         # macOS
            else
                puts "Please navigate to: #{path}"                                # Linux/other
            end
        end
        # ---------------------------------------------------------------
    
    # endregion -------------------------------------------------------------------



    # -----------------------------------------------------------------------------
    # REGION | Model Validation
    # -----------------------------------------------------------------------------
        
        # FUNCTION | Validate All Model Entities are Watertight - Smart Leaf Detection
        # ---------------------------------------------------------------
        def self.Na__ExportCore__ValidateModelWatertight(model)
            @validation_errors = []                                                # Clear errors
            total_entities = self.Na__ExportCore__CountAllEntities(model.active_entities)  # Count leaf containers only
            checked_entities = 0                                                   # Progress counter
            
            puts "Smart validation: Checking #{total_entities} leaf containers (ignoring parent containers)..."
            puts "  → Only validating groups/components that contain raw geometry"
            puts "  → Skipping parent containers that only hold nested objects"
            puts "  → Maximum nesting depth: #{MAX_NESTING_DEPTH} levels\n"
            
            # Validate all entities recursively with smart detection
            validate_result = self.Na__ExportCore__ValidateEntitiesRecursive(model.active_entities, checked_entities, total_entities)
            
            if @validation_errors.any?
                puts "\n=== VALIDATION ERRORS ==="
                @validation_errors.each { |error| puts "  - #{error}" }
                puts "\nNote: Only leaf containers (containing raw geometry) are validated."
                puts "Parent containers that only hold nested objects are ignored."
                puts "=== END VALIDATION ERRORS ===\n"
                return false
            end
            
            puts "\n✓ All leaf containers validated successfully!"                # Success message
            puts "  → #{total_entities} leaf containers checked"
            puts "  → Parent containers automatically skipped\n"
            true
        end
        # ---------------------------------------------------------------
        
        # SUB FUNCTION | Recursively Validate Entities - Smart Leaf Container Detection
        # ---------------------------------------------------------------
        def self.Na__ExportCore__ValidateEntitiesRecursive(entities, checked_count, total_count, depth = 0)
            return checked_count if depth > MAX_NESTING_DEPTH                      # Prevent infinite recursion
            
            entities.each do |entity|
                next if self.Na__Helpers__EntityExcluded?(entity)                       # Skip excluded
                
                case entity
                when Sketchup::Group
                    if self.Na__ExportCore__IsLeafContainer?(entity)
                        # Only validate groups that contain raw geometry (leaf containers)
                        if entity.manifold?
                            checked_count += 1
                            self.Na__ExportCore__ReportProgress("Validating", checked_count, total_count)
                            puts "      ✓ Leaf group '#{entity.name || 'Unnamed'}' is solid"
                        else
                            entity_name = entity.name && !entity.name.empty? ? entity.name : 'Unnamed'
                            @validation_errors << "Group '#{entity_name}' contains geometry but is not solid"
                        end
                    else
                        # Parent container - skip validation but traverse children
                        puts "      → Skipping parent group '#{entity.name || 'Unnamed'}' (contains only nested containers)"
                    end
                    
                    # Always traverse nested entities regardless of validation
                    checked_count = self.Na__ExportCore__ValidateEntitiesRecursive(entity.entities, checked_count, total_count, depth + 1)
                    
                when Sketchup::ComponentInstance
                    if self.Na__ExportCore__IsLeafContainer?(entity)
                        # Only validate components that contain raw geometry (leaf containers)
                        if entity.manifold?
                            checked_count += 1
                            self.Na__ExportCore__ReportProgress("Validating", checked_count, total_count)
                            puts "      ✓ Leaf component '#{entity.name || entity.definition.name || 'Unnamed'}' is solid"
                        else
                            entity_name = entity.name && !entity.name.empty? ? entity.name : (entity.definition.name || 'Unnamed')
                            @validation_errors << "Component '#{entity_name}' contains geometry but is not solid"
                        end
                    else
                        # Parent container - skip validation but traverse children
                        puts "      → Skipping parent component '#{entity.name || entity.definition.name || 'Unnamed'}' (contains only nested containers)"
                    end
                    
                    # Always traverse nested entities regardless of validation
                    definition = entity.respond_to?(:definition) ? entity.definition : entity
                    checked_count = self.Na__ExportCore__ValidateEntitiesRecursive(definition.entities, checked_count, total_count, depth + 1)
                end
            end
            
            checked_count
        end
        # ---------------------------------------------------------------
        
        # HELPER FUNCTION | Check if Container is a Leaf (Contains Raw Geometry)
        # ---------------------------------------------------------------
        def self.Na__ExportCore__IsLeafContainer?(entity)
            case entity
            when Sketchup::Group
                return self.Na__ExportCore__ContainsRawGeometry?(entity.entities)
            when Sketchup::ComponentInstance
                definition = entity.respond_to?(:definition) ? entity.definition : entity
                return self.Na__ExportCore__ContainsRawGeometry?(definition.entities)
            else
                return false
            end
        end
        # ---------------------------------------------------------------
        
        # HELPER FUNCTION | Check if Entities Collection Contains Raw Geometry
        # ---------------------------------------------------------------
        def self.Na__ExportCore__ContainsRawGeometry?(entities)
            entities.each do |entity|
                # If we find faces or edges, this is a leaf container
                return true if entity.is_a?(Sketchup::Face) || entity.is_a?(Sketchup::Edge)
                
                # If we find other entity types (curves, etc.) that represent geometry
                return true if entity.respond_to?(:curve) && entity.curve
            end
            
            # No raw geometry found - this is a parent container
            false
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Count Leaf Entities That Need Validation
        # ---------------------------------------------------------------
        def self.Na__ExportCore__CountAllEntities(entities, depth = 0)
            count = 0
            return count if depth > MAX_NESTING_DEPTH                              # Prevent infinite recursion
            
            entities.each do |entity|
                next if self.Na__Helpers__EntityExcluded?(entity)
                
                case entity
                when Sketchup::Group
                    if self.Na__ExportCore__IsLeafContainer?(entity)
                        count += 1                                                 # Only count leaf containers
                    end
                    count += self.Na__ExportCore__CountAllEntities(entity.entities, depth + 1)  # Always traverse children
                when Sketchup::ComponentInstance
                    if self.Na__ExportCore__IsLeafContainer?(entity)
                        count += 1                                                 # Only count leaf containers
                    end
                    definition = entity.respond_to?(:definition) ? entity.definition : entity
                    count += self.Na__ExportCore__CountAllEntities(definition.entities, depth + 1)  # Always traverse children
                end
            end
            count
        end
        # ---------------------------------------------------------------
        
        # HELPER FUNCTION | Report Progress to Console
        # ---------------------------------------------------------------
        def self.Na__ExportCore__ReportProgress(operation, current, total)
            percentage = (current.to_f / total * 100).to_i
            if percentage % 10 == 0 && percentage != @last_reported_percentage
                puts "#{operation}: #{percentage}% complete (#{current}/#{total})"
                @last_reported_percentage = percentage
            end
        end
        # ---------------------------------------------------------------
    
    # endregion -------------------------------------------------------------------
    


    # -----------------------------------------------------------------------------
    # REGION | Layer and Entity Management
    # -----------------------------------------------------------------------------
    
        # SUB FUNCTION | Identify Layers Matching Exclusion Pattern
        # ---------------------------------------------------------------
        def self.Na__ExportCore__IdentifyExcludedLayers(model)
            @excluded_layers = []                                                  # Reset excluded layers array
            
            model.layers.each do |layer|
                if layer.name =~ EXCLUDED_LAYER_PATTERN                           # Check against pattern
                    @excluded_layers << layer.name                                 # Add to excluded list
                end
            end
            
            puts "Excluded layers: #{@excluded_layers.join(', ')}" if @excluded_layers.any?
        end
        # ---------------------------------------------------------------
    
        # SUB FUNCTION | Organize Entities by Tag Ranges
        # ---------------------------------------------------------------
        def self.Na__ExportCore__OrganizeEntitiesByTags(model)
            tag_groups = {}                                                        # Initialize groups
            found_layers = {}                                                      # Track found layer names
            
            puts "\n=== Analyzing model layers ==="
            
            model.active_entities.each do |entity|
                next if self.Na__Helpers__EntityExcluded?(entity)                       # Skip excluded
                next unless entity.respond_to?(:layer)                             # Skip if no layer
                
                # Track all layer names found
                layer_name = entity.layer.name
                found_layers[layer_name] ||= 0
                found_layers[layer_name] += 1
                
                # Get tag number from strict tag prefix format: ##__
                tag_match = layer_name.match(/^(\d{2})__/)                        # Match two-digit prefix only
                next unless tag_match                                              # Skip if no number
                
                tag_number = tag_match[1].to_i                                    # Get tag number
                
                # Skip if in skip range
                if SKIP_RANGES.include?(tag_number)
                    puts "  Skipping layer '#{layer_name}' (tag #{tag_number} is in ignored range)"
                    next
                end
                
                # Find matching range
                TAG_RANGES.each do |group_name, range|
                    if range.is_a?(Range) && range.include?(tag_number)
                        tag_groups[group_name] ||= []
                        tag_groups[group_name] << entity
                        puts "  Found entity on layer '#{layer_name}' -> #{group_name}.glb"
                        break
                    elsif range.is_a?(Array) && range.include?(tag_number)
                        tag_groups[group_name] ||= []
                        tag_groups[group_name] << entity
                        puts "  Found entity on layer '#{layer_name}' -> #{group_name}.glb"
                        break
                    end
                end
            end
            
            # Report all layers found
            puts "\n=== All layers in model ==="
            found_layers.each do |layer_name, count|
                puts "  '#{layer_name}' (#{count} entities)"
            end
            puts "=========================\n"
            
            # Remove empty groups using correct API
            tag_groups.delete_if { |_, entities| entities.length == 0 }
            
            tag_groups
        end
        # ---------------------------------------------------------------
    
    # endregion -------------------------------------------------------------------
    


    # -----------------------------------------------------------------------------
    # REGION | Export Orchestration
    # -----------------------------------------------------------------------------
    
        # FUNCTION | Perform GLB Export with Configuration
        # ---------------------------------------------------------------
        def self.Na__ExportCore__PerformExport(export_dir)
            model = Sketchup.active_model                                         # Get active model
            
            # Reset ALL state variables before export
            self.Na__ExportCore__ResetState                                            # Comprehensive state reset
            
            # Re-identify excluded layers after reset
            self.Na__ExportCore__IdentifyExcludedLayers(model)                         # Identify layers to exclude
            
            # Extract project prefix from SketchUp filename
            project_prefix = self.Na__Helpers__ExtractProjectPrefix(model)
            
            # Get tag-based entity groups
            tag_groups = self.Na__ExportCore__OrganizeEntitiesByTags(model)            # Organize by tags
            
            if tag_groups.length == 0
                puts "\n=== NO ENTITIES FOUND WITH PROPER TAG RANGES ==="
                puts "Please ensure your top-level objects are on tags using the '##__' prefix format:"
                
                # Report ignored tag range based on SKIP_RANGES
                skip_tags = SKIP_RANGES.map { |v| v.to_s.rjust(2, '0') }.join(", ")
                puts "  #{skip_tags} = Ignored (not exported)"
                
                # Report all defined export ranges from TAG_RANGES
                TAG_RANGES.each do |group_name, range|
                    range_label =
                        if range.is_a?(Range)
                            "#{range.begin.to_s.rjust(2, '0')}-#{range.end.to_s.rjust(2, '0')}"
                        else
                            range.map { |v| v.to_s.rjust(2, '0') }.join(", ")
                        end
                    
                    puts "  #{range_label} = #{group_name}.glb"
                end
                
                puts "\nExample tag names: '01__OrbitHelperCube', '10__Existing__Walls', '30__Furniture__Chairs', '60__Scene__People'"
                puts "================================================\n"
                
                UI.messagebox("No entities found with valid '##__' tag prefixes for export.\n\nPlease check the Ruby Console for required tag naming.")
                return false
            end
            
            # Show what will be exported (twin Mesh + Linework per series)
            puts "\n=== Export Plan ==="
            tag_groups.each do |base_filename, entities|
                puts "  #{project_prefix}#{base_filename}#{MESH_MODEL_SUFFIX}.glb - #{entities.length} top-level entities"
                # Skip linework for OrbitHelperCube (mesh only needed for pivot point)
                if base_filename != "01__OrbitHelperCube"
                    puts "  #{project_prefix}#{base_filename}#{LINEWORK_MODEL_SUFFIX}.glb - #{entities.length} top-level entities"
                end
            end
            puts "=== End Export Plan ===\n"
            
            # Non-destructive export: no start_operation / abort_operation needed.
            # The virtual flattening engine never modifies the SketchUp model.
            # Twin output: Mesh + Linework GLB per tagged series.
            begin
                mesh_success = 0
                linework_success = 0
                tag_groups.each do |base_filename, entities|
                    puts "\nExporting series: #{project_prefix}#{base_filename}..."

                    # Mesh model (face geometry)
                    mesh_filepath = File.join(export_dir, "#{project_prefix}#{base_filename}#{MESH_MODEL_SUFFIX}.glb")
                    if self.Na__GlbEngine__ExportEntitiesToGlb(entities, mesh_filepath)
                        mesh_success += 1
                    else
                        puts "  ERROR: Failed to export mesh #{project_prefix}#{base_filename}#{MESH_MODEL_SUFFIX}.glb"
                    end

                    # Linework model (edge geometry) - Skip for OrbitHelperCube (mesh only needed for pivot point)
                    if base_filename == "01__OrbitHelperCube"
                        puts "  Skipping linework export for OrbitHelperCube (mesh only)"
                    else
                        linework_filepath = File.join(export_dir, "#{project_prefix}#{base_filename}#{LINEWORK_MODEL_SUFFIX}.glb")
                        if self.Na__LineworkEngine__ExportLineworkToGlb(entities, linework_filepath)
                            linework_success += 1
                        else
                            puts "  ERROR: Failed to export linework #{project_prefix}#{base_filename}#{LINEWORK_MODEL_SUFFIX}.glb"
                        end
                    end
                end

                success_count = mesh_success + linework_success

                # DEBUG MODE: Texture export pipeline is disabled while resolving core geometry.
                # No texture cache cleanup needed while texture exporting is bypassed.
                puts "DEBUG: Texture export disabled; skipping texture cache cleanup."

                # Open output folder
                if success_count > 0
                    self.Na__Helpers__OpenFolder(export_dir)                            # Open in file explorer
                    UI.messagebox("GLB export completed!\n\n#{success_count} files (#{mesh_success} mesh + #{linework_success} linework) exported to:\n#{export_dir}")
                else
                    UI.messagebox("Export failed. Please check the console for errors.")
                end
                
            rescue => e
                UI.messagebox("Export error: #{e.message}")                       # Show error message
                puts "GLB Export Error: #{e.message}\n#{e.backtrace.join("\n")}"  # Log full error
                false
            end
        end
        # ---------------------------------------------------------------
    
    # endregion -------------------------------------------------------------------
    
    


    end  # module GlbBuilderUtility
end  # module TrueVision3D
