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
            Na__Log__Puts "    Resetting module state for new export..."
            
            # Clear all mapping variables
            @material_map           = {}                                          # <-- Material to index mapping
            @texture_map            = {}                                          # <-- Texture to index mapping
            @image_map              = {}                                          # <-- Image data mapping
            @texture_cache          = {}                                          # <-- Texture cache
            
            # Clear validation and layer data
            @validation_errors      = []                                          # <-- Validation error messages
            @excluded_layers        = []                                          # <-- Array of excluded layer names
            @linework_hidden_layers = []                                          # <-- Array of linework-hidden layer names
            
            # Clear any progress tracking
            @last_reported_percentage = nil                                       # <-- Reset progress tracking
            
            Na__Log__Puts "    Module state reset complete"
        end
        # ---------------------------------------------------------------
    
        # FUNCTION | Initialize GLB Export Process
        # ------------------------------------------------------------
        def self.Na__ExportCore__StartExport
            model = Sketchup.active_model                                         # Get active model
            
            # Check if there's anything to export using correct SketchUp API
            if model.active_entities.length == 0
                UI.messagebox("No entities to export in the current model.")      # Alert user
                return false
            end
            
            self.Na__ExportCore__ResetState                                            # Comprehensive state reset
            self.Na__ExportCore__IdentifyExcludedLayers(model)                         # Identify layers to exclude

            FileUtils.mkdir_p(@texture_cache_folder) unless Dir.exist?(@texture_cache_folder)
            
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

        # HELPER FUNCTION | Check if Layer Should Be Treated as Untagged
        # ---------------------------------------------------------------
        def self.Na__Helpers__LayerTreatedAsUntagged?(layer_name)
            return false unless @treat_as_untagged_layers
            @treat_as_untagged_layers.include?(layer_name)
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Check if Layer Has Linework Hidden in Export
        # ---------------------------------------------------------------
        # Returns true for layers whose edges are suppressed in linework
        # GLBs but whose mesh geometry is exported normally.
        # ---------------------------------------------------------------
        def self.Na__Helpers__LayerLineworkHidden?(layer_name)
            return false unless @linework_hidden_layers
            @linework_hidden_layers.include?(layer_name)
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Return a Readable Entity Label
        # ---------------------------------------------------------------
        def self.Na__Helpers__EntityLabel(entity)
            if entity.respond_to?(:name) && entity.name && !entity.name.empty?
                entity.name
            elsif entity.respond_to?(:definition) && entity.definition
                entity.definition.name
            else
                entity.class.to_s
            end
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Warn if Orbit Helper Export Looks Contaminated
        # ---------------------------------------------------------------
        def self.Na__ExportCore__WarnIfOrbitHelperLooksContaminated(entity)
            suspicious_names = []
            self.Na__ExportCore__CollectSuspiciousOrbitDescendants(entity, suspicious_names)
            return if suspicious_names.empty?

            label = self.Na__Helpers__EntityLabel(entity)
            Na__Log__Warn "  WARNING: OrbitHelperCube export candidate '#{label}' contains model-like descendants: #{suspicious_names.first(8).join(', ')}"
            Na__Log__Warn "  WARNING: Check the SketchUp tag assignment. Only the small orbit helper cube should be on '01__OrbitHelperCube'."
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Collect Suspicious Orbit Helper Descendants
        # ---------------------------------------------------------------
        def self.Na__ExportCore__CollectSuspiciousOrbitDescendants(entity, suspicious_names, depth = 0)
            return if depth > MAX_NESTING_DEPTH
            return unless entity.respond_to?(:definition) && entity.definition

            entity.definition.entities.each do |child|
                next unless child.respond_to?(:layer)

                child_label = self.Na__Helpers__EntityLabel(child)
                child_layer = child.layer.name
                tag_match   = child_layer.match(/^(\d{2})__/)
                tag_number  = tag_match ? tag_match[1].to_i : nil

                if child_label.start_with?('ADR') || child_label.start_with?('AWN') || (tag_number && tag_number != 1)
                    suspicious_names << "#{child_label} [#{child_layer}]"
                end

                if child.is_a?(Sketchup::Group) || child.is_a?(Sketchup::ComponentInstance)
                    self.Na__ExportCore__CollectSuspiciousOrbitDescendants(child, suspicious_names, depth + 1)
                end
            end
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Extract Project Prefix from SketchUp Filename
        # ---------------------------------------------------------------
        def self.Na__Helpers__ExtractProjectPrefix(model)
            model_path = model.path
            
            if model_path.nil? || model_path.empty?
                Na__Log__Puts "  No project prefix - model not saved yet"
                return ""
            end
            
            filename = File.basename(model_path)
            match    = filename.match(/^([^_]+)__/)
            
            if match
                prefix = "#{match[1]}__"
                Na__Log__Puts "  Project prefix detected: '#{prefix}'"
                return prefix
            else
                Na__Log__Puts "  No project prefix found in filename: #{filename}"
                return ""
            end
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Cleanup Texture Cache
        # ---------------------------------------------------------------
        def self.Na__Helpers__CleanupTextureCache
            return unless @texture_cache_folder && Dir.exist?(@texture_cache_folder)

            Dir.glob(File.join(@texture_cache_folder, "*")).each do |file|
                File.delete(file) if File.file?(file)
            end

            Dir.rmdir(@texture_cache_folder) if Dir.exist?(@texture_cache_folder) && Dir.empty?(@texture_cache_folder)
            Na__Log__Puts "      Cleaned up texture cache folder"
        rescue => e
            Na__Log__Warn "      Texture cache cleanup warning: #{e.message}"
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
            total_entities = self.Na__ExportCore__CountAllEntities(model.active_entities)
            checked_entities = 0
            
            Na__Log__Puts "Smart validation: Checking #{total_entities} leaf containers (ignoring parent containers)..."
            Na__Log__Puts "  -> Only validating groups/components that contain raw geometry"
            Na__Log__Puts "  -> Skipping parent containers that only hold nested objects"
            Na__Log__Puts "  -> Maximum nesting depth: #{MAX_NESTING_DEPTH} levels"
            
            validate_result = self.Na__ExportCore__ValidateEntitiesRecursive(model.active_entities, checked_entities, total_entities)
            
            if @validation_errors.any?
                Na__Log__Warn "\n=== VALIDATION ERRORS ==="
                @validation_errors.each { |error| Na__Log__Warn "  - #{error}" }
                Na__Log__Warn "\nNote: Only leaf containers (containing raw geometry) are validated."
                Na__Log__Warn "Parent containers that only hold nested objects are ignored."
                Na__Log__Warn "=== END VALIDATION ERRORS ==="
                return false
            end
            
            Na__Log__Puts "\n✓ All leaf containers validated successfully!"
            Na__Log__Puts "  -> #{total_entities} leaf containers checked"
            Na__Log__Puts "  -> Parent containers automatically skipped"
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
                        if entity.manifold?
                            checked_count += 1
                            self.Na__ExportCore__ReportProgress("Validating", checked_count, total_count)
                            Na__Log__Puts "      ✓ Leaf group '#{entity.name || 'Unnamed'}' is solid"
                        else
                            entity_name = entity.name && !entity.name.empty? ? entity.name : 'Unnamed'
                            @validation_errors << "Group '#{entity_name}' contains geometry but is not solid"
                        end
                    else
                        Na__Log__Puts "      -> Skipping parent group '#{entity.name || 'Unnamed'}' (contains only nested containers)"
                    end
                    
                    checked_count = self.Na__ExportCore__ValidateEntitiesRecursive(entity.entities, checked_count, total_count, depth + 1)
                    
                when Sketchup::ComponentInstance
                    if self.Na__ExportCore__IsLeafContainer?(entity)
                        if entity.manifold?
                            checked_count += 1
                            self.Na__ExportCore__ReportProgress("Validating", checked_count, total_count)
                            Na__Log__Puts "      ✓ Leaf component '#{entity.name || entity.definition.name || 'Unnamed'}' is solid"
                        else
                            entity_name = entity.name && !entity.name.empty? ? entity.name : (entity.definition.name || 'Unnamed')
                            @validation_errors << "Component '#{entity_name}' contains geometry but is not solid"
                        end
                    else
                        Na__Log__Puts "      -> Skipping parent component '#{entity.name || entity.definition.name || 'Unnamed'}' (contains only nested containers)"
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
                Na__Log__Puts "#{operation}: #{percentage}% complete (#{current}/#{total})"
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
            @excluded_layers          = []                                         # Reset excluded layers array
            @treat_as_untagged_layers = []                                         # Reset treat-as-untagged array
            @linework_hidden_layers   = []                                         # Reset linework-hidden array

            exclusion_pattern        = self.Na__ExportConfig__ExclusionPattern
            fully_excluded_names     = self.Na__ExportConfig__FullyExcludedTagNames
            treat_as_untagged_names  = self.Na__ExportConfig__TreatAsUntaggedTagNames
            linework_hidden_names    = self.Na__ExportConfig__LineworkHiddenTagNames

            model.layers.each do |layer|
                if layer.name =~ exclusion_pattern || fully_excluded_names.include?(layer.name)
                    @excluded_layers << layer.name
                elsif treat_as_untagged_names.include?(layer.name)
                    @treat_as_untagged_layers << layer.name
                elsif linework_hidden_names.include?(layer.name)
                    @linework_hidden_layers << layer.name
                end
            end

            Na__Log__Puts "    Excluded layers: #{@excluded_layers.join(', ')}"           if @excluded_layers.any?
            Na__Log__Puts "    Treat-as-untagged layers: #{@treat_as_untagged_layers.join(', ')}" if @treat_as_untagged_layers.any?
            Na__Log__Puts "    Linework-hidden layers: #{@linework_hidden_layers.join(', ')}"     if @linework_hidden_layers.any?
        end
        # ---------------------------------------------------------------
    
        # SUB FUNCTION | Organize Entities by Tag Ranges
        # ---------------------------------------------------------------
        def self.Na__ExportCore__OrganizeEntitiesByTags(model)
            tag_groups   = {}
            found_layers = {}
            
            Na__Log__Puts "\n=== Analyzing model layers ==="
            
            model.active_entities.each do |entity|
                next if self.Na__Helpers__EntityExcluded?(entity)
                next unless entity.respond_to?(:layer)
                
                layer_name = entity.layer.name
                found_layers[layer_name] ||= 0
                found_layers[layer_name] += 1
                
                tag_match  = layer_name.match(/^(\d{2})__/)
                next unless tag_match
                
                tag_number = tag_match[1].to_i
                
                active_skip_ranges = self.Na__ExportConfig__SkipRanges
                if active_skip_ranges.include?(tag_number)
                    Na__Log__Puts "  Skipping layer '#{layer_name}' (tag #{tag_number} is in ignored range)"
                    next
                end
                
                active_tag_ranges = self.Na__ExportConfig__TagRanges
                active_tag_ranges.each do |group_name, range|
                    range_arr = range.is_a?(Range) ? range.to_a : Array(range)
                    if range_arr.include?(tag_number)
                        tag_groups[group_name] ||= []
                        tag_groups[group_name] << entity
                        Na__Log__Puts "  Found entity on layer '#{layer_name}' -> #{group_name}.glb"
                        self.Na__ExportCore__WarnIfOrbitHelperLooksContaminated(entity) if group_name == "01__OrbitHelperCube"
                        break
                    end
                end
            end
            
            Na__Log__Puts "\n=== All layers in model ==="
            found_layers.each do |layer_name, count|
                Na__Log__Puts "  '#{layer_name}' (#{count} entities)"
            end
            Na__Log__Puts "=========================\n"
            
            tag_groups.delete_if { |_, entities| entities.length == 0 }
            tag_groups
        end
        # ---------------------------------------------------------------
    
    # endregion -------------------------------------------------------------------
    


    # -----------------------------------------------------------------------------
    # REGION | Storey Container Detection and Organization
    # -----------------------------------------------------------------------------

        # FUNCTION | Detect Storey Containers at Model Root Level
        # ---------------------------------------------------------------
        # Scans root-level entities for groups/components tagged with
        # storey tags (90-93). Returns a hash mapping storey names to
        # arrays of container entities, because projects may split a
        # single storey across multiple root groups.
        #
        # @param model [Sketchup::Model] Active SketchUp model
        # @return [Hash] { "Storey__GroundFloor" => [entity, ...], ... } or {}
        # ---------------------------------------------------------------
        def self.Na__ExportCore__DetectStoreyContainers(model)
            storey_containers = {}                                                 # <-- Storey name => [entities] mapping

            Na__Log__Puts "\n=== Scanning for Storey Containers ==="

            model.active_entities.each do |entity|
                next if self.Na__Helpers__EntityExcluded?(entity)
                next unless entity.respond_to?(:layer)
                next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

                layer_name = entity.layer.name
                tag_match  = layer_name.match(/^(\d{2})__/)
                next unless tag_match

                tag_number = tag_match[1].to_i

                active_storey_range = self.Na__ExportConfig__StoreyTagRange
                active_storey_map   = self.Na__ExportConfig__StoreyTagMap
                if active_storey_range.include?(tag_number)
                    storey_name = active_storey_map[tag_number]
                    if storey_name
                        storey_containers[storey_name] ||= []
                        storey_containers[storey_name] << entity
                        entity_label = entity.name && !entity.name.empty? ? entity.name : layer_name
                        Na__Log__Puts "  ✓ Storey container detected: '#{entity_label}' -> #{storey_name} (#{storey_containers[storey_name].length})"
                    end
                end
            end

            if storey_containers.any?
                total_containers = storey_containers.values.map(&:length).sum
                storey_containers.each do |storey_name, containers|
                    if containers.length > 1
                        Na__Log__Warn "  WARNING: #{storey_name} has #{containers.length} root containers; exporting them as one merged storey."
                    end
                end
                Na__Log__Puts "  Found #{storey_containers.length} storey key(s), #{total_containers} container(s)"
            else
                Na__Log__Puts "  No storey containers found - using flat export mode"
            end
            Na__Log__Puts "=== End Storey Scan ==="

            storey_containers
        end
        # ---------------------------------------------------------------

        # FUNCTION | Organize Storey Children by Element Tags
        # ---------------------------------------------------------------
        # Recurses into one or more storey container entities and groups
        # their children by tag numbers using the storey element tag map.
        # Returns a hash mapping element names to arrays of child entities.
        #
        # @param storey_entities [Array<Sketchup::Entity>] Storey container groups/components
        # @param storey_name     [String]                  e.g. "Storey__GroundFloor"
        # @return [Hash] { "ProposedWalls" => [entities...], ... }
        # ---------------------------------------------------------------
        def self.Na__ExportCore__OrganizeStoreyChildrenByTags(storey_entities, storey_name)
            element_groups = {}                                                    # <-- Element name => [entities] mapping
            containers     = Array(storey_entities).compact

            Na__Log__Puts "  Organizing children of #{storey_name} (#{containers.length} container(s))..."

            containers.each_with_index do |storey_entity, index|
                entity_label = self.Na__Helpers__EntityLabel(storey_entity)
                Na__Log__Puts "    Container #{index + 1}: #{entity_label}"

                definition     = storey_entity.respond_to?(:definition) ? storey_entity.definition : storey_entity
                child_entities = definition.entities

                child_entities.each do |child|
                    next if self.Na__Helpers__EntityExcluded?(child)
                    next unless child.respond_to?(:layer)
                    next unless child.is_a?(Sketchup::Group) || child.is_a?(Sketchup::ComponentInstance)

                    child_layer = child.layer.name
                    tag_match   = child_layer.match(/^(\d{2})__/)
                    next unless tag_match

                    tag_number         = tag_match[1].to_i
                    active_element_map = self.Na__ExportConfig__StoreyElementTagMap
                    element_name       = active_element_map[tag_number]

                    if element_name
                        element_groups[element_name] ||= []
                        element_groups[element_name] << child
                        Na__Log__Puts "    Found child on layer '#{child_layer}' -> #{storey_name}__#{element_name}"
                    else
                        Na__Log__Puts "    Skipping child on layer '#{child_layer}' (tag #{tag_number} not in storey element map)"
                    end
                end
            end

            element_groups.delete_if { |_, entities| entities.length == 0 }

            Na__Log__Puts "  #{storey_name}: #{element_groups.length} element group(s) found"
            element_groups
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Resolve Merged Storey Transform
        # ---------------------------------------------------------------
        # Duplicate storey root groups should normally share the same
        # transform. We use the first transform for the merged export and
        # warn if subsequent containers differ.
        # ---------------------------------------------------------------
        def self.Na__ExportCore__ResolveMergedStoreyTransform(storey_entities, storey_name)
            containers = Array(storey_entities).compact
            return nil if containers.empty?

            first_transform = containers.first.transformation
            first_signature = first_transform.to_a.map { |value| value.to_f.round(6) }

            containers.drop(1).each_with_index do |entity, index|
                signature = entity.transformation.to_a.map { |value| value.to_f.round(6) }
                if signature != first_signature
                    Na__Log__Warn "  WARNING: #{storey_name} container #{index + 2} has a different transform; merged export uses container 1 transform."
                end
            end

            first_transform
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------



    # -----------------------------------------------------------------------------
    # REGION | Export Orchestration
    # -----------------------------------------------------------------------------
    
        # FUNCTION | Perform GLB Export with Configuration
        # ---------------------------------------------------------------
        def self.Na__ExportCore__PerformExport(export_dir)
            model = Sketchup.active_model

            self.Na__ExportCore__ResetState
            self.Na__ExportCore__IdentifyExcludedLayers(model)

            # Open the log session now that we have the export directory
            self.Na__Log__OpenSession(export_dir)

            log_path = nil
            begin
                project_prefix    = self.Na__Helpers__ExtractProjectPrefix(model)
                tag_groups        = self.Na__ExportCore__OrganizeEntitiesByTags(model)
                storey_containers = self.Na__ExportCore__DetectStoreyContainers(model)
                has_storeys       = storey_containers.any?

                if has_storeys
                    Na__Log__Puts "\n=== Storey Mode Active ==="
                    Na__Log__Puts "Storey containers will be exported per-element, not as flat groups."

                    storey_containers.each do |_storey_name, storey_entities|
                        Array(storey_entities).each do |storey_entity|
                            tag_groups.each { |_, entities| entities.delete(storey_entity) }
                        end
                    end
                    tag_groups.delete_if { |_, entities| entities.length == 0 }
                end
                
                if tag_groups.length == 0 && !has_storeys
                    Na__Log__Warn "\n=== NO ENTITIES FOUND WITH PROPER TAG RANGES ==="
                    Na__Log__Warn "Please ensure your top-level objects are on tags using the '##__' prefix format:"
                    
                    active_skip_ranges = self.Na__ExportConfig__SkipRanges
                    skip_tags = active_skip_ranges.map { |v| v.to_s.rjust(2, '0') }.join(", ")
                    Na__Log__Warn "  #{skip_tags} = Ignored (not exported)"
                    
                    active_tag_ranges = self.Na__ExportConfig__TagRanges
                    active_tag_ranges.each do |group_name, range|
                        range_arr   = range.is_a?(Range) ? range.to_a : Array(range)
                        range_label = range_arr.map { |v| v.to_s.rjust(2, '0') }.join(", ")
                        Na__Log__Warn "  #{range_label} = #{group_name}.glb"
                    end
                    
                    UI.messagebox("No entities found with valid '##__' tag prefixes for export.\n\nPlease check the Ruby Console for required tag naming.")
                    return false
                end
                
                Na__Log__Puts "\n=== Export Plan ==="

                tag_groups.each do |base_filename, entities|
                    Na__Log__Puts "  #{project_prefix}#{base_filename}#{MESH_MODEL_SUFFIX}.glb - #{entities.length} top-level entities"
                    if base_filename != "01__OrbitHelperCube"
                        Na__Log__Puts "  #{project_prefix}#{base_filename}#{LINEWORK_MODEL_SUFFIX}.glb - #{entities.length} top-level entities"
                    end
                end

                storey_export_plan = {}
                if has_storeys
                    storey_containers.each do |storey_name, storey_entities|
                        element_groups = self.Na__ExportCore__OrganizeStoreyChildrenByTags(storey_entities, storey_name)
                        storey_export_plan[storey_name] = element_groups

                        element_groups.each do |element_name, entities|
                            base_filename = "#{storey_name}__#{element_name}"
                            Na__Log__Puts "  #{project_prefix}#{base_filename}#{MESH_MODEL_SUFFIX}.glb - #{entities.length} entities"
                            Na__Log__Puts "  #{project_prefix}#{base_filename}#{LINEWORK_MODEL_SUFFIX}.glb - #{entities.length} entities"
                        end
                    end
                end
                Na__Log__Puts "=== End Export Plan ==="
                
                mesh_success     = 0
                linework_success = 0

                # PHASE 1: Export flat (non-storey) tag groups
                tag_groups.each do |base_filename, entities|
                    Na__Log__Puts "\nExporting series: #{project_prefix}#{base_filename}..."

                    mesh_filepath = File.join(export_dir, "#{project_prefix}#{base_filename}#{MESH_MODEL_SUFFIX}.glb")
                    if self.Na__GlbEngine__ExportEntitiesToGlb(entities, mesh_filepath)
                        mesh_success += 1
                    else
                        Na__Log__Warn "  ERROR: Failed to export mesh #{project_prefix}#{base_filename}#{MESH_MODEL_SUFFIX}.glb"
                    end

                    if base_filename == "01__OrbitHelperCube"
                        Na__Log__Puts "  Skipping linework export for OrbitHelperCube (mesh only)"
                    else
                        linework_filepath = File.join(export_dir, "#{project_prefix}#{base_filename}#{LINEWORK_MODEL_SUFFIX}.glb")
                        if self.Na__LineworkEngine__ExportLineworkToGlb(entities, linework_filepath)
                            linework_success += 1
                        else
                            Na__Log__Warn "  ERROR: Failed to export linework #{project_prefix}#{base_filename}#{LINEWORK_MODEL_SUFFIX}.glb"
                        end
                    end
                end

                # PHASE 2: Export storey-based element groups
                if has_storeys
                    Na__Log__Puts "\n=== Exporting Storey-Based Models ==="
                    storey_export_plan.each do |storey_name, element_groups|
                        Na__Log__Puts "\n--- #{storey_name} ---"

                        storey_entities  = storey_containers[storey_name]
                        storey_transform = self.Na__ExportCore__ResolveMergedStoreyTransform(storey_entities, storey_name)

                        element_groups.each do |element_name, entities|
                            base_filename = "#{storey_name}__#{element_name}"
                            Na__Log__Puts "\nExporting storey series: #{project_prefix}#{base_filename}..."

                            mesh_filepath = File.join(export_dir, "#{project_prefix}#{base_filename}#{MESH_MODEL_SUFFIX}.glb")
                            if self.Na__GlbEngine__ExportEntitiesToGlb(entities, mesh_filepath, storey_transform)
                                mesh_success += 1
                            else
                                Na__Log__Warn "  ERROR: Failed to export mesh #{project_prefix}#{base_filename}#{MESH_MODEL_SUFFIX}.glb"
                            end

                            linework_filepath = File.join(export_dir, "#{project_prefix}#{base_filename}#{LINEWORK_MODEL_SUFFIX}.glb")
                            if self.Na__LineworkEngine__ExportLineworkToGlb(entities, linework_filepath, storey_transform)
                                linework_success += 1
                            else
                                Na__Log__Warn "  ERROR: Failed to export linework #{project_prefix}#{base_filename}#{LINEWORK_MODEL_SUFFIX}.glb"
                            end
                        end
                    end
                    Na__Log__Puts "\n=== End Storey Export ==="
                end

                success_count = mesh_success + linework_success

                self.Na__Helpers__CleanupTextureCache

                if success_count > 0
                    self.Na__Helpers__OpenFolder(export_dir)
                    storey_msg = has_storeys ? " (includes storey-based exports)" : ""
                    log_path   = self.Na__Log__CloseSession
                    log_notice = log_path ? "\n\nExport log: #{File.basename(log_path)}" : ""
                    UI.messagebox("GLB export completed!#{storey_msg}\n\n#{success_count} files (#{mesh_success} mesh + #{linework_success} linework) exported to:\n#{export_dir}#{log_notice}")
                else
                    log_path = self.Na__Log__CloseSession
                    UI.messagebox("Export failed. Please check the Ruby Console for errors.")
                end

            rescue => e
                Na__Log__Warn "GLB Export Error: #{e.message}\n#{e.backtrace.join("\n")}"
                log_path = self.Na__Log__CloseSession
                UI.messagebox("Export error: #{e.message}\n\nCheck the Ruby Console for details.")
                false
            ensure
                log_path ||= self.Na__Log__CloseSession
            end
        end
        # ---------------------------------------------------------------
    
    # endregion -------------------------------------------------------------------
    
    


    end  # module GlbBuilderUtility
end  # module TrueVision3D
