# --------------------------------------
# REPORT ALL TAGS IN MODEL
# --------------------------------------
module Util
  def self.ReportTags
    model  = Sketchup.active_model                            # <-- Operate on the current model
        puts "\n"                                             # <-- Clean Linebreak
        puts "\n"                                             # <-- Print Title Line
        puts "-------------------------------------------"    # <-- Print Horizontal Line
        puts "- - REPORT | ALL TAGS (Layers) IN MODEL - -"    # <-- Print Horizontal Line
        puts "-------------------------------------------"    # <-- Print Horizontal Line
    layers = model.layers                                     # <-- Fetch its tag collection
        for layer in layers                                   # <-- Loop through each tag (still called layers in API)
        puts layer.name                                       # <-- Print all tag names in console
    end                                                       # <-- End of loop
  puts "----------------------------------------"             # <-- Print Horizontal Line
  end
end

# UNCOMMENT BELOW TO RUN (TESTING ETC) COMMENT OUT WHEN LOADING WITH SKETCHUP INIT
# Util.ReportTags
# --------------------------------------


# --------------------------------------
# MOVE DEEP NESTED SELECTED TAGS TO UNTAGGED
# --------------------------------------
# 1. Select Entities, Can be groups, components, geometry, etc.
# 2. Enter Command into Console "Util.MoveDeepNestedTagsToUntagged"
# 3. All selected entities will be "Untagged" and Layers will be removed.
# 4. This works recursively through all nested levels of the selection.
#    - i.e. Group containers containing children entities will be "Untagged" and Layers will be removed.
module Util
  def self.MoveDeepNestedTagsToUntagged
    model     = Sketchup.active_model                         # <-- Operate on the current model
    selection = model.selection                               # <-- Get the current selection
    untagged  = model.layers[0]                               # <-- Get the default "Untagged" layer
        puts "\n"                                             # <-- Clean Linebreak
        puts "\n"                                             # <-- Print Title Line
        puts "----------------------------------------------------"    # <-- Print Horizontal Line
        puts "- - MOVE | DEEP NESTED SELECTED TAGS TO UNTAGGED - -"    # <-- Print Horizontal Line
        puts "----------------------------------------------------"    # <-- Print Horizontal Line
        
        # Process each selected entity recursively
        for entity in selection                               # <-- Loop through each selected entity
            process_entity_recursively(entity, untagged)     # <-- Process entity and its children recursively
        end                                                   # <-- End of selection loop
        
        # Clean up empty layers
        layers_to_remove = []                                 # <-- Array to store layers that need removal
        for layer in model.layers                             # <-- Loop through each layer
            if layer != untagged && layer.entities.empty?    # <-- Check if layer is empty and not untagged
                layers_to_remove << layer                     # <-- Add to removal list
            end                                               # <-- End of layer check
        end                                                   # <-- End of layer loop
        
        for layer in layers_to_remove                         # <-- Loop through layers to remove
            model.layers.remove(layer)                        # <-- Remove the empty layer
            puts "Removed empty layer: #{layer.name}"        # <-- Print removal confirmation
        end                                                   # <-- End of removal loop
        
    puts "----------------------------------------------------"    # <-- Print Horizontal Line
  end
  
  # Helper method to process entities recursively
  def self.process_entity_recursively(entity, untagged_layer)
    # Move current entity to untagged layer
    if entity.respond_to?(:layer=)                            # <-- Check if entity has layer property
        old_layer = entity.layer                              # <-- Store the old layer reference
        entity.layer = untagged_layer                         # <-- Move entity to untagged layer
        puts "Moved #{entity.class.name} to Untagged (was: #{old_layer.name})"  # <-- Print move confirmation
    end                                                       # <-- End of layer assignment
    
    # Process children if entity is a group or component instance
    if entity.respond_to?(:definition)                        # <-- Check if entity is a component instance
        for child_entity in entity.definition.entities        # <-- Loop through component definition entities
            process_entity_recursively(child_entity, untagged_layer)  # <-- Recursively process children
        end                                                   # <-- End of component children loop
    elsif entity.respond_to?(:entities)                       # <-- Check if entity is a group
        for child_entity in entity.entities                   # <-- Loop through group entities
            process_entity_recursively(child_entity, untagged_layer)  # <-- Recursively process children
        end                                                   # <-- End of group children loop
    end                                                       # <-- End of children processing
  end
end

# UNCOMMENT BELOW TO RUN (TESTING ETC) COMMENT OUT WHEN LOADING WITH SKETCHUP INIT
# Util.MoveDeepNestedTagsToUntagged
# --------------------------------------
