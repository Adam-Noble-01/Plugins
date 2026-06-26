# =============================================================================
# Reference |  SketchUp Ruby API Materials Handling Methods 2025
# =============================================================================
#### Research Notes Compiled - 22-May-2025


## -------------------------------------------------------
## CORE PROJECT DESIGN COMMITMENTS BASED ON RESEARCH
## -------------------------------------------------------

### KEY NOTE : Material Management Strategy for ValeDesignSuite Components
`ValeDesignSuite_MaterialLibrary_<ComponentType>`     <-- REFERENCE : Material naming convention for component-specific materials.

- Given the Vale Orangery / Conservatory Framework will use standardized materials across component types.
  - i.e. Frame materials (Wood, UPVC, Aluminium) with consistent finish properties across all frame components.
- I have decided that all materials will be centrally managed and applied consistently across component definitions.
- The material data being standardized and tied to physical "Things" (component types) in the model is important.
- Multiple users will use the same library of components with consistent material applications.
  - Storing materials with consistent naming ensures that when components are saved to libraries and shared, material references remain valid.
- This means people in different departments at Vale Garden Houses will see consistent material appearances across all framework components.
- Reliable material assignment between the HTML UI Design Tool and the Ruby API / SketchUp Environment is important
  - targeting consistent material naming and properties will support this.
  - (Instance-specific material overrides can still be applied for custom variations within a single model).


### -------------------------------------------------------


## Overview of Material Handling in SketchUp Ruby API

**What are Materials in SketchUp:**
- **Materials** in SketchUp represent surface finishes – either solid colours or textured images – that can be applied to drawing elements.
- Each SketchUp **Model** contains a **Materials** collection (accessible via `model.materials`) holding all materials in that model.
- Materials can be created from scratch, loaded from files, edited (colour, texture, transparency, etc.), and assigned to entities.

**Material Assignment Targets:**
- `Sketchup::Face` (front and back sides separately)
- `Sketchup::Edge` (visible when edge render mode is "Color by Material")
- `Sketchup::Group` (container-level material)
- `Sketchup::ComponentInstance` (container-level material)
- `Sketchup::ComponentDefinition` (affects all instances)

**Material Inheritance Rules:**
- A material applied to a container (group/component) displays on any faces inside that have the default material.
- Faces with their own material **override** the container's material.
- If an entity has no material assigned (`entity.material` is `nil`), it renders with SketchUp's default material.
- Best practice is usually to paint **faces** directly rather than whole groups for more control over texture orientation.


### -------------------------------------------------------


## Material Creation and Retrieval Methods

**Creating New Materials:**
- `model.materials.add("MaterialName")`                    #<-- Creates new material with specified name
- `model.materials.add()`                                  #<-- Creates material with auto-generated unique name

**Loading Existing Materials:**
- `model.materials.load("path/to/material.skm")`           #<-- Loads material from SketchUp material file
- `model.materials.load("path/to/model.skp")`              #<-- Loads materials from SketchUp model file

**Retrieving Materials:**
- `model.materials["MaterialName"]`                        #<-- Get material by name
- `model.materials[index]`                                 #<-- Get material by index
- `model.materials.current`                                #<-- Get currently selected material in UI
- `model.materials.current = material`                     #<-- Set currently selected material in UI

**Material Collection Operations:**
- `model.materials.length`                                 #<-- Get number of materials
- `model.materials.each { |mat| ... }`                     #<-- Iterate through all materials
- `model.materials.unique_name("BaseName")`                #<-- Generate unique material name


### -------------------------------------------------------


## Material Property Management

**Basic Material Properties:**
- `material.name`                                          #<-- Get material's internal name
- `material.name = "NewName"`                              #<-- Set material's name
- `material.display_name`                                  #<-- Get material's UI display name
- `material.color`                                         #<-- Get material's base colour (Sketchup::Color)
- `material.color = [255, 0, 0]`                           #<-- Set material colour (RGB array)
- `material.color = "Red"`                                 #<-- Set material colour (color name)
- `material.color = "#FF0000"`                             #<-- Set material colour (hex code)

**Transparency Properties:**
- `material.alpha`                                         #<-- Get opacity (0.0 = transparent, 1.0 = opaque)
- `material.alpha = 0.5`                                   #<-- Set material to 50% transparent
- `material.use_alpha?`                                    #<-- Check if material uses transparency

**Material Type Information:**
- `material.materialType`                                  #<-- Get material type (0=solid, 1=textured, 2=colorized)
- `material.owner_type`                                    #<-- Get material ownership type
- Constants: `MATERIAL_SOLID`, `MATERIAL_TEXTURED`, `MATERIAL_COLORIZED_TEXTURED`


### -------------------------------------------------------


## Texture Management

**Texture Assignment:**
- `material.texture = "path/to/image.jpg"`                 #<-- Assign texture from image file
- `material.texture = ["image.jpg", 10, 10]`               #<-- Assign texture with specified size (model units)
- `material.texture = image_rep_object`                    #<-- Assign texture from ImageRep object
- `material.texture = nil`                                 #<-- Remove texture (revert to solid color)

**Texture Properties:**
- `material.texture`                                       #<-- Get Texture object (or nil)
- `texture.width`                                          #<-- Get texture width in model units
- `texture.height`                                         #<-- Get texture height in model units
- `texture.image_width`                                    #<-- Get texture width in pixels
- `texture.image_height`                                   #<-- Get texture height in pixels
- `texture.filename`                                       #<-- Get texture image file path
- `texture.average_color`                                  #<-- Get average color of texture

**Texture Operations:**
- `texture.write("output.jpg", colorize: false)`           #<-- Save texture to file
- `texture.image_rep`                                      #<-- Get ImageRep for pixel manipulation

**Texture Colorization:**
- `material.colorize_type`                                 #<-- Get colorization mode (0=none, 1=shift, 2=tint)
- `material.colorize_type = COLORIZE_TINT`                 #<-- Set colorization mode
- `material.colorize_deltas`                               #<-- Get HLS adjustment values
- Constants: `COLORIZE_SHIFT`, `COLORIZE_TINT`


### -------------------------------------------------------


## PBR (Physically-Based Rendering) Materials - SketchUp 2024+

**PBR Workflow:**
- `material.workflow`                                      #<-- Get material workflow type
- Constants: `WORKFLOW_PBR_METALLIC_ROUGHNESS`

**Metalness Properties:**
- `material.metalness_enabled?`                            #<-- Check if metalness is enabled
- `material.metalness_enabled = true`                      #<-- Enable metalness properties
- `material.metallic_factor`                               #<-- Get metallic factor (0.0-1.0)
- `material.metallic_factor = 0.8`                         #<-- Set metallic factor
- `material.metallic_texture`                              #<-- Get metallic texture map
- `material.metallic_texture = "metallic_map.jpg"`         #<-- Set metallic texture map

**Roughness Properties:**
- `material.roughness_enabled?`                            #<-- Check if roughness is enabled
- `material.roughness_enabled = true`                      #<-- Enable roughness properties
- `material.roughness_factor`                              #<-- Get roughness factor (0.0-1.0)
- `material.roughness_factor = 0.3`                        #<-- Set roughness factor
- `material.roughness_texture`                             #<-- Get roughness texture map
- `material.roughness_texture = "roughness_map.jpg"`       #<-- Set roughness texture map

**Normal Map Properties:**
- `material.normal_enabled?`                               #<-- Check if normal mapping is enabled
- `material.normal_enabled = true`                         #<-- Enable normal mapping
- `material.normal_texture`                                #<-- Get normal map texture
- `material.normal_texture = "normal_map.jpg"`             #<-- Set normal map texture
- `material.normal_style`                                  #<-- Get normal map style
- `material.normal_style = NORMAL_STYLE_OPENGL`            #<-- Set normal map style
- `material.normal_scale`                                  #<-- Get normal map scale factor
- `material.normal_scale = 1.2`                            #<-- Set normal map scale factor
- Constants: `NORMAL_STYLE_OPENGL`, `NORMAL_STYLE_DIRECTX`

**Ambient Occlusion Properties:**
- `material.ao_enabled?`                                   #<-- Check if ambient occlusion is enabled
- `material.ao_enabled = true`                             #<-- Enable ambient occlusion (requires texture first)
- `material.ao_texture`                                    #<-- Get ambient occlusion texture map
- `material.ao_texture = "ao_map.jpg"`                     #<-- Set ambient occlusion texture map
- `material.ao_strength`                                   #<-- Get AO strength factor (0.0-1.0)
- `material.ao_strength = 0.7`                             #<-- Set AO strength factor


### -------------------------------------------------------


## Material Assignment to Entities

**Face Material Assignment:**
- `face.material`                                          #<-- Get front face material
- `face.material = material`                               #<-- Set front face material
- `face.back_material`                                     #<-- Get back face material
- `face.back_material = material`                          #<-- Set back face material
- `face.material = nil`                                    #<-- Clear front face material
- `face.back_material = nil`                               #<-- Clear back face material

**Entity Material Assignment:**
- `entity.material`                                        #<-- Get entity material (groups, components, edges)
- `entity.material = material`                             #<-- Set entity material
- `entity.material = "Red"`                                #<-- Set entity material by color name
- `entity.material = [255, 0, 0]`                          #<-- Set entity material by RGB array
- `entity.material = nil`                                  #<-- Clear entity material

**Component Material Management:**
- `component_instance.material = material`                 #<-- Set material on component instance
- `component_definition.material = material`               #<-- Set material on component definition (affects all instances)


### -------------------------------------------------------


## Material Collection Management

**Material Removal:**
- `model.materials.remove(material)`                       #<-- Remove specific material (must not be in use)
- `model.materials.purge_unused`                           #<-- Remove all unused materials safely

**Material Export/Import:**
- `material.save_as("material.skm")`                       #<-- Save material to .skm file
- `material.write_thumbnail("thumb.jpg", 64)`              #<-- Write material thumbnail

**Material Validation:**
- Check if material is in use before removing
- Unpaint entities before removing materials
- Use `purge_unused` for safe bulk removal


### -------------------------------------------------------


## Code Examples

### Creating and Applying a Basic Material
```ruby
# Create new material
material = model.materials.add("CustomWood")
material.color = [139, 69, 19]                            # Set brown color
material.alpha = 1.0                                      # Fully opaque

# Apply to face
selected_face.material = material                         # Front face
selected_face.back_material = material                    # Back face (optional)
```

### Creating a Textured Material
```ruby
# Create textured material
material = model.materials.add("BrickTexture")
material.texture = ["brick.jpg", 2.m, 1.m]                # 2m x 1m texture size
material.color = [180, 160, 140]                          # Slight tint

# Apply to multiple faces
selected_faces.each { |face| face.material = material }
```

### Creating a PBR Material
```ruby
# Create PBR material
material = model.materials.add("MetalPBR")
material.color = [100, 100, 120]                          # Base color

# Enable and set metalness
material.metalness_enabled = true
material.metallic_factor = 0.9                            # Highly metallic

# Enable and set roughness
material.roughness_enabled = true
material.roughness_factor = 0.2                           # Fairly smooth

# Optional: Add normal map
material.normal_enabled = true
material.normal_texture = "metal_normal.jpg"
material.normal_style = NORMAL_STYLE_OPENGL
```

### Safe Material Removal
```ruby
# Method to safely remove a material
def remove_material_safely(material)
  return unless material
  
  # Clear material from all entities first
  model = Sketchup.active_model
  model.entities.grep(Sketchup::Face).each do |face|
    face.material = nil if face.material == material
    face.back_material = nil if face.back_material == material
  end
  
  # Clear from groups and components
  model.entities.grep(Sketchup::Group).each do |group|
    group.material = nil if group.material == material
  end
  
  # Now safe to remove
  model.materials.remove(material)
end
```


### -------------------------------------------------------


## DO'S AND DONT'S - Material Management Best Practices

*Do*
- Use descriptive and consistent naming conventions for materials to avoid conflicts and ensure clarity.
- Store materials on the `ComponentDefinition` if they should be consistent across all instances of a component type.
- Apply materials to faces directly for precise texture control and orientation.
- Check if a material with the same properties already exists before creating new ones to avoid duplicates.
- Use `model.start_operation` and `model.commit_operation` when making multiple material changes for undo/redo support.
- Test PBR properties in external rendering engines, as SketchUp's viewport doesn't fully display all PBR effects.
- Purge unused materials periodically to keep the material library clean.
- Set texture sizes in model units for consistent scale across different models.

*Don't*
- Remove materials that are currently in use without first clearing them from entities (can cause model corruption).
- Create excessive numbers of similar materials - reuse existing materials when possible.
- Apply extremely large texture images unnecessarily, as they can impact performance.
- Forget to handle both front and back face materials when needed for two-sided surfaces.
- Assume PBR properties will be visible in SketchUp's standard viewport - they're primarily for export/rendering.
- Use `materials.remove()` in loops without proper validation - use `purge_unused()` for bulk cleanup instead.
- Mix different material assignment strategies within the same component (paint faces OR paint container, not both).
- Ignore material transparency ordering issues - SketchUp has limitations with layered transparency rendering.


### -------------------------------------------------------


## Performance Considerations

**Optimization Strategies:**
- Reuse material objects instead of looking up by name repeatedly
- Batch material operations within single undo operations
- Downsize texture images if ultra-high resolution isn't necessary
- Use `disable_ui: true` in operations when processing many materials
- Consider material library size impact on file loading times

**Memory Management:**
- Purge unused materials regularly to reduce memory footprint
- Avoid storing multiple copies of identical textures
- Monitor texture file sizes and optimize when possible


### -------------------------------------------------------


## Material Observer Integration

**Setting Up Material Observers:**
```ruby
# Material collection observer
class MyMaterialsObserver < Sketchup::MaterialsObserver
  def onMaterialAdd(materials, material)
    puts "Material added: #{material.name}"
  end
  
  def onMaterialRemove(materials, material)
    puts "Material removed: #{material.name}"
  end
end

# Attach observer
model.materials.add_observer(MyMaterialsObserver.new)
```

**Individual Material Observer:**
```ruby
# Individual material observer
class MyMaterialObserver < Sketchup::MaterialObserver
  def onMaterialChange(material)
    puts "Material changed: #{material.name}"
  end
end

# Attach to specific material
material.add_observer(MyMaterialObserver.new)
```


# ===================================================================
# END OF FILE
# ===================================================================
