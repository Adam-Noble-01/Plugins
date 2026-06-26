# ===============================================================================
#      - - - - - -   V A L E   D E S I G N   S U I T E - - - - - -   
# ===============================================================================
#### File Name    |  01_-_ValeDesignSuite_-_MasterPluginDesignDocument.txt
#### Author       |  Adam Noble
#### Date         |  2025-05-20
#### Description  |  This is the master design document for the Vale Design Suite plugin.
#### Version      |  0.0.1


## PLUGIN OVERVIEW
## ----------------------------------------------

### Brief Description of the Plugin
- Vale Design Suite is a custom SketchUp Plugin to help with the creation of 3D models for Vale Garden Houses.
- Vale Garden Houses Design & Build Bespoke Luxury Garden Rooms, Orangeries and Conservatories.
- The company website is https://www.valegardenhouses.co.uk/
- The company is based in the UK.
- The plugin will be used to speed up the creation of 3D models for Vale Garden Houses.
- The company currently uses traditional manual methods not yet automated or utilising any 3D Software.
- The aim is to provide a suite of tools to help the company create 3D models of their products.
- The 3D Models will be used to help with the design and build of the Vale Garden Houses Projects.
- The Plugin will automate many of the manual tasks currently undertaken by the company.
- The plugin needs to be designed to be as user friendly as possible.
- The plugin needs to be designed to be as efficient as possible (Toolset efficiency).

### Brief Notes On The Plugin Environment
- The plugin will be developed using Ruby and SketchUp's Ruby API.
- The plugin will be developed in the SketchUp 2025 version.
- The plugin will be developed using the latest version the SketchUp Ruby API.
  - IMPORTANT! - SU Ruby API is frequently updated, So its critical that the plugin is developed using the latest version of Ruby.
  - Many naming and coding conventions have changed over the years, so its critical that the plugin is developed using the latest version of Ruby.

### Why Use SketchUp As The Plugin Platform?
- SketchUp is a popular 3D modelling software used by many in the UK.
- Some designers in the company are already familiar with SketchUp, as its extremely user friendly.
- SketchUp has a large community and a wealth of online resources.
- The open source nature of the Ruby API Allows for rapid development of custom plugins.
- Me (Adam Noble) have a lot of experience with Ruby and SketchUp, having developed several basic plugins in the past.



## ===============================================================================
##   -  -  -  -  VALE DESIGN SUITE - PLUGIN FUNCTIONALITY & FEATURES  -  -  -  -  
## ===============================================================================


### Core Functionality Implemented So Far
### ---------------------------------------------
0.0.1 - Basic Plugin Structure Defined
  - Created the basic plugin document `01_-_ValeDesignSuite_-_MasterPluginDesignDocument.txt`
  - Created the basic plugin folder structure
  - Created the basic plugin loader script `ValeDesignSuite_LoaderScript.rb`
  - TESTED - HTML Window correctly opens when extensions menu item triggered and reports . . . 
    "Success! The Vale Design Suite plugin has loaded successfully. Version: 0.0.1"
  - Code Checkpoint Saved

0.0.2 - Further Preliminary Plugin Development
  - Built a basic Stylesheet for the Plugin
  - Uses fonts loaded from Noble-Architecture Website
    - `https://www.noble-architecture.com/assets/AD04_-_LIBR_-_Common_-_Front-Files/`
  - Defines Vale Garden Houses colour palette for the Plugin ass CSS Variables
  - Uses CSS Variables for front size, typography and colours
    - TESTED - HTML Window correctly opens correctly and displays the Vale colours etc.
  - Code Checkpoint Saved

0.0.3 - Began Development Of Framework Generator Tool
  - 

0.0.4 - Roof Lantern Tool Enhancements & UI Integration
  - Addressed and corrected a geometric calculation issue in the Roof Lantern Generator (`ValeDesignSuite_Tools_RoofLanternTools.rb`) where glazing bar pitches were incorrect. This involved refining the use of pitch angle vs. tangent values in calculations.
  - Significantly improved user experience for the Roof Lantern Generator by integrating its parameter inputs (roof pitch, Z-offsets for components, moulding selection) directly into the main HTML UI (`ValeDesignSuite_Core_MainUserInterface.rb`).
  - This removed the previous pop-up dialog (`UI.inputbox`) for a more streamlined workflow.
  - Involved:
    - Adding HTML form elements (inputs, select) to the tool's page within the main UI.
    - Updating JavaScript to collect these parameters and pass them as a JSON string to a Ruby callback.
    - Modifying the Ruby callback in `ValeDesignSuite_Core_MainUserInterface.rb` to parse the JSON and forward parameters.
    - Adapting `ValeDesignSuite_Tools_RoofLanternTools.rb` to accept these parameters directly, bypassing the old `UI.inputbox` method.
  - TESTED - Roof Lantern tool now correctly calculates glazing bar pitches and accepts parameters from the main UI page.
  - Code Checkpoint Saved



### ---------------------------------------------
### Planned Additional Features Not Yet Implemented

*Standard Vale Orangery Framework Setting Out & Creation Tool.*
  - Notes

*Standard Vale Orangery Window & Door Creation Tool.*
  - Notes

*Standard Vale Orangery Roof Lantern Creation Tool.*
  - The Roof Lantern tool is under rudimentary development, a basic minimal feature version exists.

*Standard Vale Profile Creation Tool.*
  - The Profile tool is under rudimentary development, a basic minimal feature version exists.
  - This tool works similar to "Profile Builder" in that it allows for the creation of extruded 3D Element along paths
  - Allows the user to visually select from a catalogue of pre-defined profiles.

*Standard Reporting Tool*
  - This tool will report on the number of elements in the model.
  - The system uses a carefully defined set of numeric prefixes assigned the the entities in the model.
    - These names effectively act as a type of ID for each entity.
    - The reporting tool will use these IDs to report on the number of each type of entity in the model.


# ===============================================================================


## CODEBASE NOTES
## ----------------------------------------------
- There is NO NEED for efficiency in the codebase.
- It is more important to make the code easy to understand and maintain.
- The codebase should be designed to be easily extendable and modular.
- The codebase should be as verbose as possible, with plenty of comments to explain "why" behind the "what".
- The codebase should have items like keys and values should be be equally spaced and aligned in "columns" for easy reading.
- Variables & Constants should be clearly defined in one place within each module script and easily identifiable.
  - Variables and constants should also be be equally spaced and aligned in "columns" for easy reading.


**SketchUp / Ruby Plugin Namespace**
- This is the top level namespace for the plugin.
- This will be used to avoid conflicts with other plugins.
`ValeDesignSuite`    <-- IMPORTANT: This is used as the namespace for the plugin.


*Short Name*
- Note this is used only as shorthand and is NOT! used in the codebase.
- Used simply as an abbreviation to save time and typing.
`VDS`    <-- !Warning when using this as Ruby could interpret this as a constant

*Extensions Menu Name*
`VGH |  Vale Design Suite`



## QUIRKS RELEVANT TO THE RUBY API
## ----------------------------------------------
- SketchUp uses Inches as the default unit of measurement, 
  - therefor all measurements should be converted to Inches when storing values.
- SketchUp uses a right-handed coordinate system, where:
  - X-axis points to the right
  - Y-axis points up
  - Z-axis points out of the screen
- SketchUp uses a bottom left origin in 2D views (like top view), but in 3D space the origin is at the center of the drawing area.
- SketchUp uses a right-handed rotation system, where positive rotations are counterclockwise when looking down the axis of rotation.

### Additional Important API Quirks
**Version Compatibility**
  - The Ruby API is frequently updated, so version checking is crucial
  - Use `Sketchup.version` to check version numbers and implement version-specific code
  - Some features may only be available in newer versions (e.g., certain import options in SU 2018+)

**Operation Management**
  - Always wrap geometry modifications in `start_operation` and `commit_operation` blocks
  - This ensures proper undo/redo functionality and better performance
  - Example: `model.start_operation('Operation Name', true)`

**Entity Manipulation**
  - Vertices cannot be directly manipulated with position=
  - Use transformation operations through parent entities instead
  - Create new geometry with desired positions or use transform_entities

**Performance Considerations**
  - Group operations when manipulating large sets of geometry
  - Use `start_operation`/`commit_operation` blocks for better performance
  - Be mindful of model validity checks when making bulk changes

**Selection Handling**
  - There are known bugs with selection events
  - Use `onSelectedRemoved` instead of `onSelectionRemoved` until bugs are fixed
  - Selection events may not always fire in the expected order

**Face and Edge Management**
  - Faces have both front and back materials
  - Edges can be smooth or soft
  - Face normals must be consistent for proper rendering
  - Coplanar face merging requires careful handling

**Component and Group Behavior**
  - Components and groups have different behaviors
  - Components can be instanced, groups cannot
  - Component definitions are shared across instances
  - Groups are unique entities

**Material and Texture Handling**
  - Materials can have both color and texture properties
  - Texture coordinates (UVs) require special handling
  - Material names must be unique within the model

**Model Validity**
  - SketchUp has strict requirements for valid geometry
  - Invalid geometry can cause crashes or unexpected behavior
  - Use validity checks when creating or modifying geometry
  - Be careful with face merging and edge operations



# -----------------------------------------------------------------------------
# STRUCTURING A SKETCHUP 2025 PLUGIN DURING DEVELOPMENT
# -----------------------------------------------------------------------------

## Development Phase Best Practices
- A single Ruby file in the Plugins directory serves as the entry point
- This file acts as a manifest/loader that points to other files
- All files and dependencies are nested one level down in a dedicated directory
- Main .rb files are placed within this folder for easier editing
- The structure aligns with SketchUp's extension requirements while maintaining development efficiency

## Folder Structure for Development
- `ValeDesignSuite_LoaderScript.rb` is used as the Registrar/Loader
- This serves as a minimal entry-point Ruby script in the Plugins folder
- The script points to the subfolder `ValeDesignSuite`
- This folder contains all the plugin's Modules & Assets

## Plugin Namespace
- This is the top level module for the plugin
`ValeDesignSuite`  <-- This is the namespace for the plugin



## STRUCTURE OF THE PLUGIN
## ----------------------------------------------
`[SketchUp Plugins Directory]/ValeDesignSuite`

```markdown
`\Plugins`                                        =  This is the main folder for all SketchUp plugin on my system
  `SU_General_Plugin.rb`                          =  A generic plugin shown for reference
  `SU_General_Plugin_02.rb`                       =  A generic plugin shown for reference
  `ValeDesignSuite_LoaderScript`                  =  This is the loader/registrar file for my plugin
    `\ValeDesignSuite`                            =  This is the folder for my plugin
      `ValeDesignSuite_Core_PluginScript.rb`      =  This is the main plugin script file for the ValeDesignSuite plugin
      `ValeDesignSuite_Tools_FrameworkToolsSketchUpLogic.rb`   =  Contains the Framework Generator / Editor Toolset
      `ValeDesignSuite_Tools_FrameworkToolsConfigurator.rb`    =  Contains the Framework Configuration Interface
      `ValeDesignSuite_Tools_FrameworkToolsDataSerializer.rb`  =  Contains the Framework Data Management
      `ValeDesignSuite_Tools_RoofLanternTools.rb` =  Contains the Roof Lantern Generator / Editor Toolset
      `ValeDesignSuite_GenericExample.rbe`        =  This is the compiled Ruby file for my plugin (Note Yet Utilised)
```


## Plugin Data Handling Overview
## ----------------------------------------------
- The primary source of the data for the plugin will be the Vale Garden Houses Product Catalogue.
- This catalogue is stored in a JSON file.
    `Plugins\ValeDesignSuite\Config_ValeProductData\ValeGeneralProductData.json`
    - Note the Json file above is generic, certain product lines will have their own Json file in the same folder.
- The plugin will use SketchUp dictionaries to store the data for the products.
- This allows for use of Product and component metadata to be stored in the same place and easily updated.
- This will allow for more complex data retrieval and reporting on the data which will be very useful for the company.
    ```Notes_On_Dictionaries_Not_Yet_Confirmed
    - May also include handling to also update SketchUps Dynamic Components Dictionary
    - This ensures some level of compatibility with native SketchUp features without the Plugin.
    - I'm thinking this integration is more a case of cloning Vales custom SketchUp Dictionary with the Native SketchUp DC Dictionary.
    ```


## Development Guidelines
### Key Principles
- Maintain easy editability
- Keep structure intuitive and clear
- Centralize all files and dependencies
- Prioritize rapid development and testing

### File Types During Development
1. `.rb` Files
   - Standard Ruby source files
   - Used for all plugin code and functionality
   - Primary file type for development
   - Keeps code easily editable and debuggable

2. `.rbe` Files
   - Encrypted Ruby files
   - Used for protecting intellectual property
   - Not recommended during development phase
   - Will be used only for final distribution if code protection is needed
   - Helps prevent unauthorized access and modification

3. `.rbz` Files
   - Compressed distribution format
   - Renamed .zip files
   - NOT recommended during development
   - Will be used only for final distribution and Extension Warehouse submission
   - Standard practice for SketchUp Plugins and Extension Warehouse

### Naming Conventions
- Avoid using "Index" terminology in file names
- Use underscores `_` instead of hyphens `-` in Ruby filenames
- Follow Ruby naming conventions for files and modules
- Keep names descriptive and consistent

### Naming Levels
### -----------------------------------
#### Summary of Naming Hierarchy
- The ValeDesignSuite follows a clear naming hierarchy:
* **Level 1**  -  `ValeDesignSuite`  -  The unique namespace for the plugin
* **Level 2**  -  Categories like `Core` and `Tools` to organize different aspects
* **Level 3**  -  Specific tool names like `FrameworkTools` and `RoofLanternTools`

#### Level 1 - Items Index
`ValeDesignSuite`           =   This is the namespace for the plugin, thus unique to this plugin

#### Level 2 - Items Index
`ValeDesignSuite_Core_`     =   Core Plugin Scripts, usually loaded first and used to load other scripts.
`ValeDesignSuite_Tools_`    =   This is the folder for the Tools for the plugin, used for grouping related tools together.

#### Level 3 - Items Index
`ValeDesignSuite_Core_PluginScript.rb`       =  This is the Ruby file for the main plugin script
`ValeDesignSuite_Tools_FrameworkToolsSketchUpLogic.rb`    =  This is the Ruby file for the Framework Generator / Editor Toolset
`ValeDesignSuite_Tools_FrameworkToolsConfigurator.rb`     =  This is the Ruby file for the Framework Configuration Interface
`ValeDesignSuite_Tools_FrameworkToolsDataSerializer.rb`   =  This is the Ruby file for the Framework Data Management
`ValeDesignSuite_Tools_RoofLanternTools.rb`  =  This is the Ruby file for the Roof Lantern Generator / Editor Toolset
`ValeDesignSuite_Core_MainUserInterface.rb`  =  This is the Ruby file for the Main User Interface


## Asset & Key Sub-Folders
## ----------------------------------------------
`/ValeDesignSuite/Assets_ValeBrandAssets`   =  Contains all assets related to the Vale Garden Houses Branding
`/ValeDesignSuite/Assets_PluginAssets`      =  Contains all generic assets related to the Plugin, icons, images, etc.
`/ValeDesignSuite/Config_PluginConfigFiles` =  Contains all Json configuration files for the plugin
`/ValeDesignSuite/Config_ValeProductData`   =  Contains all Json product data files for the plugin


## Key Configuration Files
## ----------------------------------------------
`CorePluginConfigFile.json`            = Contains the core configuration for the plugin


## General Notes
## ----------------------------------------------
- SketchUp will automatically load `ValeDesignSuite_LoaderScript.rb` on startup since it's in the Plugins directory.
- In that file, I must register my extension and require the main code from the ValeDesignSuite subfolder.
- This structure isn't just recommended; it's required for SketchUp extensions.
- The Extension Warehouse and signing process expect one top-level .rb file and a same-named folder containing the rest. 
- An `.rb` that "sets up" the extension *and* a subfolder of the exact same name is the simplest proper structure.

*Why Use This Structure During Development?* 
  - It keeps my development aligned with deployment. 
  - I can work with the files directly in the Plugins folder.
  - I then manually reload them as I test, without repackaging each time. 
  - Organising code into multiple files under the ValeDesignSuite subfolder also prevents cluttering the global namespace and makes it easier for me to maintain and navigate my code.

### Ruby File Naming Conventions
*Correct Usage Of Underscores & Hyphens In Ruby File Names*
- Underscores `_` are preferred in Ruby filenames. 
- This follows Ruby naming conventions for files and modules 
- e.g. `ValeDesignSuite`, Modules under the namespace `ValeDesignSuite_ModulesMethodsOrClasses.rb` etc . . .
- Hyphens `-` are discouraged in the context of Ruby filenames because they conflict with `require` and `load`
  - Ruby treats hyphens as subtraction operators when evaluating paths unless quoted properly.
  - This means `require 'ValeDesignSuite-LoaderScript'` would raise an error unless explicitly quoted and escaped.
- CamelCase in file names is not idiomatic in Ruby. CamelCase is reserved for **class/module names**, not filenames.



### Entry-Point Ruby File
### ----------------------------------------------

- My entry-point `.rb` file in the Plugins directory serves as the manifest or loader for my plugin. 
- It's often called the **registrar file** in SketchUp parlance. This script's responsibilities are minimal but important:
- I've named the file `ValeDesignSuite_LoaderScript.rb`, and it points to the folder `ValeDesignSuite/`.

**Extension Registration**
- The loader script creates a `SketchupExtension` object and registers the ValeDesignSuite with SketchUp. 
- This allows users to see it in the Extension Manager and toggle it on/off. 
- The script points to `ValeDesignSuite_Core_PluginScript.rb` as the main file in the subfolder.

**Minimal Logic**
- I keep the loader script lightweight. 
- The main plugin logic resides in the ValeDesignSuite subfolder files like `ValeDesignSuite_Core_PluginScript.rb`, `ValeDesignSuite_Tools_FrameworkToolsSketchUpLogic.rb`, and `ValeDesignSuite_Tools_RoofLanternTools.rb`. 
- This is both for organization and because the loader script will remain unencrypted in a signed extension.



## Organizing ValeDesignSuite Code in the Subfolder
## ----------------------------------------------
- All other code files live in the **ValeDesignSuite subfolder**. 
- This keeps the implementation separate from other extensions and neatly contained.

**Current structure:**

* **Main Script**: `ValeDesignSuite_Core_PluginScript.rb` serves as the primary script which initializes the plugin's tools, UI, and functionality.

* **Tool Scripts**: 
  - `ValeDesignSuite_Tools_FrameworkToolsSketchUpLogic.rb` - Framework Generator/Editor Toolset
  - `ValeDesignSuite_Tools_FrameworkToolsConfigurator.rb` - Framework Configuration Interface
  - `ValeDesignSuite_Tools_FrameworkToolsDataSerializer.rb` - Framework Data Management
  - `ValeDesignSuite_Tools_RoofLanternTools.rb` - Roof Lantern Generator/Editor Toolset

* **Future Encrypted Files**: While `.rbe` files are mentioned in the structure (not yet utilized), these would only be relevant for distribution, not during development.

I use underscores to separate components in all files, following Ruby conventions. The only exception is the hyphenated loader script name, which has already been established.

## File Types During Development

For the ValeDesignSuite plugin:

**`.rb` files**
- These are currently used for all development work, making the code easy to edit and debug.
- All development code should be stored in `.rb` files.

**`.html` files**
- These files form the foundation of the plugin's user interface using SketchUp's WebDialog framework
- The HTML files are loaded and managed through Ruby's WebDialog class
- Key Ruby API methods used:
  ```ruby
  dialog = UI::WebDialog.new("Vale Design Suite", true, "ValeDesignSuite", 800, 600, 100, 100, true)
  dialog.set_file("path/to/interface.html")
  dialog.show
  ```

**`.css` files**
- Used for styling the plugin's interface and ensuring a professional, consistent look
- CSS files are referenced within HTML files and loaded through the WebDialog
- Best practices:
  - Use relative paths for assets
  - Implement responsive design for different screen sizes
  - Follow SketchUp's design guidelines for consistency
  - Use CSS variables for theme management

**`.js` files**
- JavaScript files handle dynamic UI interactions and business logic
- Communication between JS and Ruby is handled through:
  ```ruby
  # Ruby to JavaScript
  dialog.execute_script("functionName(parameters)")
  
  # JavaScript to Ruby
  window.location = "sketchup://command/functionName?param=value"
  ```
- Key implementation patterns:
  - Event-driven architecture
  - Asynchronous operations
  - Error handling and logging
  - State management

**`.json` files**
- Used for configuration, data storage, and communication
- Common use cases:
  - Plugin settings and preferences
  - Tool configurations
  - Data exchange between Ruby and JavaScript
  - Template definitions
- Ruby JSON handling:
  ```ruby
  require 'json'
  config = JSON.parse(File.read('config.json'))
  ```

**`.rbe` files**
- These are encrypted files that help protect the source code from being easily reverse-engineered or stolen. 
- While mentioned in the structure (ValeDesignSuite_GenericExample.rbe), they are not yet utilized during development.
- They are primarily relevant for final distribution to ensure the security and integrity of the code.
- Using `.rbe` files can deter unauthorized access and modification, providing an additional layer of protection for intellectual property.
 *Important Note To Vale Garden Houses*
 - All code should be compiled to `.rbe` files when distributing the plugin.
 - This ensures Vale retains full ownership of the code and can prevent unauthorized access and modification.

**`.rbz` files**
- This format would only be used when packaging the extension for distribution through the Extension Warehouse.
- This is basically a zipped folder renamed from `.zip` to `.rbz`

During development, working directly with the `.rb` files in the Plugins directory structure is most efficient. The encryption and packaging steps would only come into play when preparing the plugin for release.

## WebDialog Notes
**WebDialog Implementation Details**
- The WebDialog class provides a bridge between Ruby and web technologies
- Key features:
  - Full HTML5 support
  - JavaScript execution
  - Two-way communication
  - Custom protocol handling
- Security considerations:
  - Sandboxed execution
  - Limited file system access
  - Cross-origin restrictions


**Core Style Rules**
- Ensure responsive design
- Use CSS variables for theme management
- Use relative paths for assets
`/ValeDesignSuite/Assets_ValeBrandAssets` = Contains all assets related to the Vale Garden Houses Branding
- Use the dedicated /ValeDesignSuite/Assets_PluginAssets folder for all assets
- Implement responsive design for different screen sizes
- Follow SketchUp's design guidelines for consistency

**Development Workflow**
1. Create HTML structure with proper SketchUp integration points
2. Style with CSS - This style will be applied to the UI Reflecting the Vale Design Suite Branding and Style
3. Add JavaScript for interactivity
4. Implement JSON for data management
  `Placeholder For JSON Data 01` (Fill this in with the correct information)
    - This will be used to store the plugin's fixed settings, and preferences.
  `Placeholder For JSON Data 02` (Fill this in with the correct information)
    - This will be used to store the plugin's user configurable settings, and preferences.
  `Placeholder For JSON Data 03` (Fill this in with the correct information)
    - This will be used to store the plugin's data.
  `Placeholder For JSON Data 04` (Fill this in with the correct information)
    - This will be used to store the plugin's configuration.
5. Connect everything through Ruby's WebDialog

**Best Practices**
- Keep UI code separate from business logic
- Use modular JavaScript architecture
- Define helper functions after declaring the variables and constants but BEFORE the main functions.
- Implement proper error handling
- Follow SketchUp's UI guidelines

- Maintain clear communication channels between Ruby and web components


## USER INTERFACE IMPLEMENTATION DETAILS
## ----------------------------------------------

### Main User Interface
- The ValeDesignSuite_Core_PluginScript.rb file loads the main user interface from the ValeDesignSuite_Core_MainUserInterface.rb file.
- Uses the `::UI::HtmlDialog.new` method for the main interface.
- Implemented in `ValeDesignSuite_Core_MainUserInterface.rb` with HTML and CSS in one file for simplicity.
- Configured with SketchUp's HtmlDialog for a modern, responsive UI.
- Modern design, responsive layout, and consistent branding.
- Displays success message and version info.
- The main HtmlDialog is designed to be flexible, allowing for the direct embedding of tool-specific parameters 
  - (e.g., for the Roof Lantern Generator). 
This reduces reliance on secondary pop-up dialogs like `UI.inputbox`, by handling input collection via HTML forms and JavaScript;
  - Then by passing data to Ruby tool scripts via callbacks.

### HTML and CSS
- HTML includes DOCTYPE, meta charset, title, and main content.
- CSS uses `@font-face` for Open Sans fonts and CSS variables for theme management.

### UI Best Practices
- Organised and maintainable code with efficient font loading and CSS variables.
- Ensures accessibility with semantic HTML and proper heading hierarchy.


## VALE DESIGN SUITE - UNIQUE IDENTIFICATION SYSTEM
## ----------------------------------------------

### Overview
The Vale Design Suite implements a comprehensive unique identification system that ensures every component, assembly, and element within the plugin can be uniquely identified, tracked, and managed. This system is fundamental to data persistence, component relationships, and automated reporting functionality.

### Three-Tier Identification Hierarchy

#### 1. Framework Assembly IDs (VFW Series)
**Format**: `VFW001`, `VFW002`, `VFW003`, etc.
**Purpose**: Identifies complete framework assemblies (entire structural systems)
**Range**: VFW001 to VFW999 (999 unique framework assemblies possible)
**Usage**:
- Each complete orangery or conservatory framework gets a unique VFW ID
- Stored in component instance attributes for assembly-level identification
- Used by the Framework Configurator Tool for multi-assembly management
- Links to comprehensive metadata including assembly name, dimensions, notes, and creation date

**Example Framework Assembly Structure**:
```
VFW001 - "Main Orangery Framework"
├── Metadata: Assembly name, dimensions, creation date, notes
├── Nodes: ND001, ND002, ND003 (structural elements)
└── Panels: PNL001, PNL002, PNL003 (window/door panels)
```

#### 2. Panel IDs (PNL Series)
**Format**: `PNL001`, `PNL002`, `PNL003`, etc.
**Purpose**: Identifies individual panels (windows, doors, glazed sections)
**Range**: PNL001 to PNL999 (999 unique panels possible)
**Usage**:
- Each window, door, or glazed panel gets a unique PNL ID
- Used by the Window Configurator Tool for panel-specific configuration
- Can exist independently or as part of a framework assembly
- Supports sub-component identification (e.g., PNL001_LeftJamb, PNL001_Glass)

**Panel Sub-Component Naming Convention**:
```
PNL001 - "Georgian Window Panel"
├── PNL001_LeftJamb     (Frame component)
├── PNL001_RightJamb    (Frame component)
├── PNL001_TopRail      (Frame component)
├── PNL001_BottomRail   (Frame component)
├── PNL001_Glass        (Glass component)
└── PNL001_GlazeBar_01  (Glazing bar components)
```

#### 3. Node IDs (ND Series)
**Format**: `ND001`, `ND002`, `ND003`, etc.
**Purpose**: Identifies structural nodes (columns, uprights, intermediate supports)
**Range**: ND001 to ND999 (999 unique nodes possible)
**Usage**:
- Structural elements that connect panels and provide framework support
- Intermediate columns between panels
- Corner columns at framework intersections
- Upright frame sections and structural supports
- Essential for framework assembly structural integrity

**Node Types and Classifications**:
```
Corner Columns:
├── ND001 - "Front Left Corner Column"
├── ND002 - "Front Right Corner Column"
├── ND003 - "Back Left Corner Column"
└── ND004 - "Back Right Corner Column"

Intermediate Columns:
├── ND005 - "Front Center Column (290mm)"
├── ND006 - "Side Intermediate Column (390mm)"
└── ND007 - "Back Center Support Column"

Upright Frame Sections:
├── ND008 - "Left Side Frame Upright"
├── ND009 - "Right Side Frame Upright"
└── ND010 - "Center Divider Upright"
```

### Auto-Incrementing ID Generation

#### Framework Assembly ID Generation
- System scans all existing framework components in the model
- Identifies highest existing VFW number (e.g., VFW005)
- Generates next sequential ID (VFW006) for new assemblies
- Prevents ID conflicts across multiple framework assemblies
- Maintains unique identification even when assemblies are deleted

#### Panel ID Generation
- Scans all window/panel components across the entire model
- Finds highest existing PNL number regardless of framework association
- Generates next sequential PNL ID for new panels
- Ensures global uniqueness across all panels in the model
- Supports both standalone panels and framework-integrated panels

#### Node ID Generation
- Examines all structural node components in the model
- Identifies highest existing ND number across all frameworks
- Creates next sequential ND ID for new structural elements
- Maintains uniqueness across all framework assemblies
- Supports various node types (corner, intermediate, upright)

### ID System Integration with Tools

#### Framework Configurator Tool
- Creates and manages VFW assembly IDs
- Links ND node IDs to specific framework assemblies
- Maintains relationships between nodes and panels within assemblies
- Stores assembly-level metadata and configuration data
- Enables multi-framework management and selection switching

#### Window Configurator Tool
- Generates and manages PNL panel IDs
- Creates sub-component IDs linked to parent panels
- Supports standalone panel creation and framework integration
- Maintains panel-specific configuration and metadata
- Enables real-time updates and multi-panel management

#### Node Management System
- Assigns ND IDs to structural elements during framework creation
- Tracks node types, positions, and dimensional properties
- Maintains relationships between nodes and connected panels
- Supports various column types and structural configurations
- Enables structural analysis and reporting functionality

### Dictionary Storage and Data Persistence

#### Framework Assembly Data Storage
**Dictionary Name**: `ValeDesignSuite_FrameworkAssemblies_{AssemblyID}`
**Storage Location**: Component Definition
**Data Structure**:
```json
{
    "frameworkMetadata": [
        {
            "FrameworkUniqueId": "VFW001",
            "FrameworkName": "Main Orangery Framework",
            "FrameworkNotes": "Primary structural assembly",
            "FrameworkLength": 6000,
            "FrameworkWidth": 4000,
            "FrameworkHeight": 2400
        }
    ],
    "frameworkNodes": [
        {
            "NodeUniqueId": "ND001",
            "NodeName": "Front Left Corner",
            "NodeType": "Column_CornerColumn",
            "NodePosX": 0, "NodePosY": 0, "NodePosZ": 0,
            "NodeSizeX": 290, "NodeSizeY": 290, "NodeSizeZ": 2400
        }
    ],
    "frameworkPanelLines": [
        {
            "PanelLineId": "PL001",
            "ConnectedNodes": ["ND001", "ND002"],
            "AssociatedPanels": ["PNL001"],
            "LineLength": 1200
        }
    ]
}
```

#### Panel Data Storage
**Dictionary Name**: `WindowConfigurator_Config`
**Storage Location**: Component Definition
**Data Structure**: (As detailed in Window Configurator section)

#### Node Data Storage
**Dictionary Name**: `ValeDesignSuite_NodeData_{NodeID}`
**Storage Location**: Component Instance Attributes
**Data Structure**:
```json
{
    "NodeUniqueId": "ND001",
    "NodeType": "Column_CornerColumn",
    "ParentFramework": "VFW001",
    "ConnectedPanels": ["PNL001", "PNL002"],
    "StructuralProperties": {
        "LoadBearing": true,
        "MaterialType": "Timber",
        "CrossSection": "290x290mm"
    }
}
```

### Reporting and Analysis Benefits

#### Automated Component Counting
- System can automatically count all VFW assemblies in a model
- Generate reports on total panels (PNL count) across all frameworks
- Analyze node distribution and structural element quantities
- Provide material takeoffs based on component types and dimensions

#### Relationship Mapping
- Track which panels belong to which framework assemblies
- Identify structural connections between nodes and panels
- Map dependencies for assembly sequencing and construction planning
- Enable clash detection and spatial analysis

#### Data Integrity and Validation
- Ensure all components have valid, unique identifications
- Detect orphaned components not properly linked to assemblies
- Validate structural relationships and assembly completeness
- Provide data consistency checks across the entire model

### Future Enhancements

#### Extended ID Series
- **Roof Elements**: RFE001-RFE999 for roof lanterns, glazing, and structural roof components
- **Foundation Elements**: FND001-FND999 for base plates, foundations, and ground connections
- **Hardware Elements**: HWE001-HWE999 for hinges, handles, locks, and mechanical components

#### Advanced Relationship Management
- Parent-child relationships between assemblies and sub-assemblies
- Dependency tracking for assembly sequencing
- Version control for component modifications and updates
- Integration with external CAD systems and manufacturing databases

#### Enhanced Reporting Capabilities
- Automated bill of materials generation based on component IDs
- Cost estimation integration using component identification
- Manufacturing sequence optimization based on ID relationships
- Quality control tracking throughout the design and build process


## WINDOW CONFIGURATOR TOOL - DICTIONARY HANDLING

### Overview
The Window Configurator Tool implements a sophisticated dictionary-based data persistence system that stores window configuration data directly in SketchUp component definitions. This approach ensures that each window component maintains its own configuration data, enabling multi-window support and proper data management.

### Dictionary Structure
**Dictionary Name**: `WindowConfigurator_Config`
- Stored on: Component Definition (not model-level)
- Keys:
  - `window_config` - Serialized JSON configuration data
  - `window_config_formatted` - Human-readable formatted JSON for debugging

### JSON Data Structure (Version 1.2.0+)
The window configuration uses a three-tier JSON structure with metadata support:

#### 1. Window Metadata Section
```json
"windowMetadata": [
    {
        "WindowUniqueId": "PNL001",
        "WindowName": "Window_PNL001",
        "WindowVersion": "1.2.0",
        "WindowAuthor": "Adam Noble - Noble Architecture",
        "WindowDescription": "A configurable Georgian-style window component",
        "WindowNotes": "User-defined notes for special cases",
        "WindowCreatedDate": "25-May-2025",
        "WindowLastModified": "25-May-2025"
    }
]
```

#### 2. Window Components Section
```json
"windowComponents": [
    {
        "ComponentUniqueId": "PNL001_LeftJamb",
        "ComponentName": "Window_LeftJamb",
        "ComponentType": "Frame_Jamb",
        "ComponentMaterial": "natural-wood",
        "Position": { "PosX_mm": 0, "PosY_mm": 0, "PosZ_mm": 0 },
        "Dimensions": { "LenX_mm": 90, "LenY_mm": 50, "LenZ_mm": 1500 },
        "Rotation": { "RotX_deg": 0, "RotY_deg": 0, "RotZ_deg": 0 }
    }
    // Additional components (RightJamb, TopRail, BottomRail, Glass)
]
```

#### 3. Window Configuration Section
```json
"windowConfiguration": {
    "Component_Default_Width_mm": 800,
    "Component_Default_Height_mm": 1500,
    "Component_Default_FrameThickness_mm": 90,
    "Component_Default_VerticalGlazeBars": 2,
    "Component_Default_HorizontalGlazeBars": 3,
    "Component_Default_FrameColor": "natural-wood",
    "Component_UI_MinWidth_mm": 400,
    "Component_UI_MaxWidth_mm": 1600
    // Additional UI constraints
}
```

### Panel ID System
**Unique Panel Identification**: Each window receives a unique Panel ID following the pattern "PNL001", "PNL002", etc.

**Auto-incrementing Logic**:
- System scans all existing window components in the model
- Finds the highest existing Panel ID number
- Generates next sequential ID for new windows
- Ensures no ID conflicts across multiple windows

**Component Linking**: Each sub-component (jambs, rails, glass) gets a unique ID linked to the panel:
- Format: `{PanelID}_{ComponentType}`
- Examples: "PNL001_LeftJamb", "PNL001_Glass", "PNL002_TopRail"

### Dictionary Management Functions

#### Core Functions
- `save_config_to_component(component, config)` - Saves configuration to component dictionary
- `load_config_from_component(component)` - Loads configuration from component dictionary
- `generate_next_panel_id()` - Creates unique panel IDs
- `update_component_ids_with_panel_id(config, panel_id)` - Links components to panel ID

#### Real-time Updates
- Configuration changes automatically update the stored dictionary data
- Metadata timestamps are updated on each modification
- Component dimensions and positions are recalculated and stored

### Selection Observer Integration
**Multi-Window Support**: The tool implements a selection observer that:
- Detects when users select different window components
- Automatically loads the selected window's configuration into the UI
- Updates the dialog to reflect the selected window's parameters
- Enables seamless switching between multiple windows

**Observer Implementation**:
```ruby
class WindowSelectionObserver < Sketchup::SelectionObserver
    def onSelectionBulkChange(selection)
        # Detect window component selection
        # Load configuration from component dictionary
        # Update UI with loaded parameters
    end
end
```

### User Workflow
1. **Create New Window**: Button always creates new window with unique Panel ID
2. **Real-time Updates**: When window is selected, sliders update the selected window in real-time
3. **Multi-Window Management**: Users can create multiple windows and switch between them by selection
4. **Persistent Data**: All window configurations are saved with the SketchUp model

### Data Persistence Benefits
- **Model Integration**: Configuration data travels with the SketchUp model file
- **No External Dependencies**: No need for external configuration files
- **Version Control**: Model saves include all window configurations
- **Collaboration**: Teams can share models with embedded window data
- **Backup Safety**: Window configurations are preserved in model backups

### Technical Implementation Notes
- Uses JSON serialization for complex data structures
- Implements error handling for corrupted or missing dictionary data
- Provides fallback to default configuration if data cannot be loaded
- Maintains backward compatibility with older configuration formats
- Supports both formatted and compact JSON storage for debugging purposes

### Future Enhancements
- Potential integration with SketchUp's Dynamic Components dictionary for broader compatibility
- Export/import functionality for window configuration templates
- Batch operations for updating multiple windows simultaneously
- Integration with Vale's product catalog system for standardized configurations 