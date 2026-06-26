# =============================================================================
# Reference |  Programmatic SketchUp Dictionaries via Ruby API 2025
# =============================================================================
#### Research Notes Compiled - 22-May-2025


## -------------------------------------------------------
## CORE PROJECT DESIGN COMMITMENTS BASED ON RESEARCH
## -------------------------------------------------------

### KEY NOTE :  My Primary Prefix For Any Dictionary Will Be 
`ValeDesignSuite_FrameworkAssemblies_<ThenUniqueId>`     <-- REFERENCE : `ValeDesignSuite_Tools_FrameworkToolsDataSerializer.rb` for full details.

- Given the Vale Orangery / Conservatory Framework config tool will be creating assemblies of components that is unique.
  - i.e. a Frame Elevation section containing unique collections of Widow panels, door panels, columns, etc.
- I have decided that all of my dictionaries will be stored on the `Sketchup::ComponentDefinition`.
- The data being unique and tied to a physical "Thing" (as a component type or definition) in the model is important.
- Multiple users will use the same library of components, so data needs to be truly cross-compatible travelling between models. 
  - Storing on the `ComponentDefinition` ensures that when a component is saved to a library and shared, its core configuration data travels with it.
- This means people in different departments at Vale Garden Houses are able to use the same components (definitions) and have the same base data associated with that component type.
- Reliable interfacing between the HTML UI Design Tool and the Ruby API / SketchUp Environment is important
  - targeting the `ComponentDefinition` for shared, persistent data will support this.
  - (Instance-specific overrides can still use `ComponentInstance` dictionaries if needed for variations within a single model).


### -------------------------------------------------------


## Dictionary Creation and Usage with Component Instances

- **Attribute Dictionaries** in SketchUp are collections of key-value pairs that can be attached to various SketchUp entities, including:
  *Model-Wide Entities*
  - `Sketchup::Model`                   #<-- Stores model-wide attributes and metadata.

  *SketchUp Scene Related Entities*
  - `Sketchup::Page`                    #<-- Holds attributes for specific scene pages.
  - `Sketchup::Axes`                    #<-- Manages attributes for the model's drawing axes.
  - `Sketchup::SectionPlane`            #<-- Holds attributes for section planes.
  - `Sketchup::Image`                   #<-- Stores attributes for image entities. 

  *Fundamental Geometric Entities*
  - `Sketchup::Vertex`                  #<-- Manages attributes for vertex points.
  - `Sketchup::Edge`                    #<-- Contains attributes for individual edges.
  - `Sketchup::Face`                    #<-- Holds attributes for face entities.
  Curves and Complex Geometric Entities
  - `Sketchup::Curve`                   #<-- Stores attributes for curve entities (collections of edges).
  - `Sketchup::ArcCurve`                #<-- (Subclass of Curve)

  *Container Type Entities*
  - `Sketchup::ComponentDefinition`     #<-- Stores attributes for component definitions.
  - `Sketchup::ComponentInstance`       #<-- Holds instance-specific attributes for components.
  - `Sketchup::Group`                   #<-- Manages attributes for grouped entities.

  *Types Applied To Entities*
  - `Sketchup::Layer` (now `Tag`)       #<-- IMPORTANT AS UPDATED! - Manages attributes for layer/tag visibility and properties.
  - `Sketchup::Material`                #<-- Contains attributes related to material properties.

  *Utility Entities*
  - `Sketchup::ConstructionPoint`       #<-- Stores attributes for construction points.
  - `Sketchup::ConstructionLine`        #<-- Contains attributes for construction lines.

  *Annotation Entities*
  - `Sketchup::Text`                    #<-- Holds attributes for 3D text entities.
  - `Sketchup::Dimension`               #<-- Manages attributes for dimension entities.


### -------------------------------------------------------


- To create or access a dictionary on a **Component Instance**, use:
  - `component_instance.attribute_dictionary("YourDictionaryName", true)`
  - The `true` argument ensures the dictionary is created if it doesn't already exist.

- Alternatively, use:
`component_instance.set_attribute("YourDictionaryName", "YourKey", your_value)`
  - This method will also create the dictionary if needed, before setting the attribute.

### KEY NOTE :  Keys in these dictionaries MUST be strings.

#### Best Way to Store Data in Dictionaries
- Attribute Dictionaries can store various SketchUp-supported data types as values.
    - These include strings, numbers (Integer, Float, Length, Angle), booleans.
    - Time objects, Sketchup::Color objects,
    - Geom::Point3d and Geom::Vector3d objects,
      - & arrays containing these simple types.
- For more complex, structured data (like nested hashes or arrays that mimic JSON objects)
- The standard practice is to convert the Ruby hash/array into a JSON string before storing it.


### -------------------------------------------------------


### Parsing JSON for Component Dictionaries
- SketchUp's AttributeDictionary does not natively store or parse complex nested Ruby objects directly as rich structures.
- It primarily handles basic data types and some SketchUp-specific geometric and measurement types.

#### KEY NOTE :  Regarding the approach I've decided to take with the data storage in the ValeDesignSuite Plugins
- The ValeDesignSuite uses the `ValeDesignSuite_Tools_FrameworkToolsDataSerializer.rb`
- This file contains methods to serialize and deserialize data to and from JSON strings.
- The `ValeDesignSuite_Tools_FrameworkToolsDataSerializer.rb` file is called by other scripts as needed.

### Recommended Practice for JSON-like Data:
- In Ruby, construct your data as a Hash or an Array.
- Use 
  - `require 'json'`                                                      #<-- This loads Ruby's JSON library, enabling JSON parsing and generation.
- Convert your Ruby Hash/Array into a JSON string using 
  - `JSON.generate(your_ruby_object)`                                     #<--- This converts the Ruby object into a JSON-formatted string.
    -  or 
  - `your_ruby_object.to_json`.                                           #<--- This is an alternative method to convert the Ruby object into a JSON string.
  - `instance.set_attribute("MyDataDict", "ConfigJSON", json_string)`     #<--- This stores the JSON string as a value in the attribute dictionary.
  - `json_string = instance.get_attribute("MyDataDict", "ConfigJSON")`    #<-- This retrieves the JSON string from the attribute dictionary.
  - `ruby_object = JSON.parse(json_string)`                               #<--- This converts the JSON string back into a Ruby object, typically a Hash or Array.
  - `ruby_object = JSON.parse(json_string, symbolize_names: true)`        #<--- This converts the JSON string into a Ruby object with symbolized keys, instead of string keys.

#### Regarding "Stringify" and "Parse"
- These are the standard and generally accepted methods in Ruby for serializing and deserializing data to/from JSON format.
- If there are concerns, they usually relate to performance with extremely large or deeply nested JSON structures that are frequently modified,
  - where the overhead of full serialization/deserialization for minor changes might become noticeable.
- For most common use cases involving structured data, this approach is effective.


### -------------------------------------------------------

## Supported Ruby API Methods for Reading and Writing

*Writing Data*
- `entity.set_attribute("dictionary_name", "key_name", value)`
  - Sets a value for a given key in a named dictionary on the entity.

*Reading Data*
- `entity.get_attribute("dictionary_name", "key_name")`
  - Retrieves the value for a given key from a named dictionary.

*Accessing the value using its key from an AttributeDictionary object*
- `attribute_dictionary_object["key_name"]`

*Iterating through all key-value pairs in the dictionary*
- `attribute_dictionary_object.each { |key, value| ... }`

*Returns an array of all keys in the dictionary*
- `attribute_dictionary_object.keys`

*Returns an array of all values in the dictionary*
- `attribute_dictionary_object.values`

### -------------------------------------------------------

## Global (Model) vs. Local (Component) Dictionaries

*Dictionaries on Component Instances (Sketchup::ComponentInstance)*
- Data stored here is specific to that individual instance of a component.
  - This is suitable for properties that vary from one instance to another (e.g., a unique serial number, a specific state).

*Dictionaries on Component Definitions (Sketchup::ComponentDefinition)*
- Accessed via `component_instance.definition.set_attribute(...)`.
- Data stored here is shared by all instances of that component.
- This is ideal for attributes that define the type of component (e.g., a model number, default material).
- Attributes stored on the definition are saved with the component when it's saved as a separate .skp file.

*Dictionaries on the Model (Sketchup::Model)*
- Accessed via `Sketchup.active_model.set_attribute(...)`.
- This data is global to the entire SketchUp file and not tied to any specific component.
- Useful for plugin settings or model-wide data.

### Advantages:
- Storing instance-specific data on the ComponentInstance keeps it local to that instance.
- Storing common data on the ComponentDefinition promotes consistency among instances and ensures the data is part of the component's definition if saved/shared.
- Storing model-wide data on the Model keeps it separate from individual components.

### Limitations of Component Instance Dictionaries
- Data stored in a ComponentInstance's dictionary is tied to that specific instance.
  - If the instance is deleted, that specific data is lost.
- If the data needs to persist with the component's definition
  - (i.e., be present when the component is saved to an external file and re-imported, or be consistent across all instances of that component type),
  - it should be stored on the Sketchup::ComponentDefinition rather than the Sketchup::ComponentInstance.

### SketchUp's Handling of Dictionary Data (Storage and Retrieval)
- Attribute dictionaries and their key-value pairs are saved as part of the SketchUp model file (.skp).
- When you use the Ruby API methods like set_attribute or get_attribute, SketchUp's internal mechanisms write to or read from this data store within the model.
- The API provides an interface to this persistent data, abstracting the underlying file format details.



### -------------------------------------------------------

## DO'S AND DONT'S -  General Guidelines For Using Attribute Dictionaries

*Do*
- Use unique and descriptive names your attribute dictionaries to avoid conflicts with other extensions or SketchUp's own dictionaries.
- Store data on the `ComponentDefinition` if it should be shared by all instances or persist when the component is saved externally.
- Store data on the `ComponentInstance` for attributes that are unique to that specific instance.
- `require 'json'` when you need to serialize Ruby Hashes/Arrays into JSON strings or parse JSON strings back into Ruby objects.
- Consider the type of data you are storing. Simple types can be stored directly; complex nested data is best stored as a JSON string.

*Don't*
- Assume complex Ruby objects (custom classes, deeply nested hashes)
  - will be stored and retrieved with their full structure intact without serialization (like to JSON string).
  - Attribute Dictionaries have limitations on directly storable types.
- Forget to create the dictionary (e.g., by passing `true` as the second argument to `entity.attribute_dictionary("name", true)`)
  - if you intend to use dictionary object methods like `[]=` directly and the dictionary might not exist yet.
  - `set_attribute` handles this implicitly.
- Store excessively large, monolithic JSON strings if the data is frequently updated in small parts,
  - as this might lead to performance overhead.
  - Consider breaking down very large datasets if feasible.




# ===================================================================
# END OF FILE
# ===================================================================




