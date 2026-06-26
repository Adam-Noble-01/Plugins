# =============================================================================
# 02_-_ValeDesignSuite_-_Development-Log.txt
# =============================================================================

### THIS FILE :  02_-_ValeDesignSuite_-_Development-Log.txt
### AUTHOR    :  Adam Noble - Vale Garden Houses
### TYPE      :  Text Document
### PURPOSE   :  Development Log For ValeDesignSuite SketchUpPlugin

## ---------------------------------------------------------------------------
## DEVELOPMENT LOG:
## ---------------------------------------------------------------------------


## -----------------------------------------------------------------------------

**06-Nov-2025 - Version 0.8.5 - Added Image Carousel and Notes App Utilities**

- Added Image Carousel utility (`Util__SketchUpModel__InBuiltImageViewingCaraselApp__HtmlDialogue.rb`)
- Added Notes App utility (`Util__SketchUpModel__InBuiltNotesApp__HtmlDialogue.rb`)
- Updated main menu to include new utilities

## -----------------------------------------------------------------------------


## -----------------------------------------------------------------------------

**15-Aug-2025 - Version 0.8.4 - Roof Lantern Tool Major Updates**

### TO BE, BUT NOT YET IMPLEMENTED "TO DO LIST"

#### Major Roof Lantern Script Refactor, Restructure And Logically Revaluate Structure And Process Flow.
- Roof Lantern Tool Refactored to be better structured, currently its a mess.
- The script has been added to several times and is no consistent with my coding style and conventions.
- Regions should have 3 line breaks between, functions and methods 2 line breaks between, and must have headers underlined and a hyphen line after each block.
- New Logical regions need to be added and the code better modularised.
 - 1. Header Region   =   As Is
 - 2. Embedded Json   =   Not used by script, but provides a Method and function index for the script for keeping track of what is available.
 - 3. Main Global Scope Constants        =   Self Explanatory 
 - 4. Main Global Scope Variables        =   Self Explanatory 
 - 5. Global Helper Functions            =   Self Explanatory  -  Contains Generalised helper functions used over and over throughout declaring them early.
 - 6. Global Math Functions              =   Self Explanatory  -  Contains functions used over and over throughout declaring them early.
 - 7. 2D Processing Functions            =   Contains functions related to handling and processing the 2D Aspects.
 - 8. 2D Roof Angle Triangle Functions   =   All elements related to the creation of the 2d roof triangles.
                                             - The indicate the pitch angles of the glazed bars (rafters) and the hip timbers 
                                             - These are important and are to be used extensively in the 3D Generation Functions.
                                             - The hypotoneuse line of the trangles becomes a paths for the 3D Generation Functions.
 - 9. 3D Generation Functions            =   The Functions for generating each of the elements required.
                                             - The 3D Generation Functions are the main functions that generate the 3D elements.
                                             - They are the main functions that are called by the script to generate the 3D elements.
                                             - Create Sub Code groups with titles making it clear which 3d element is being created.
                                             - Ensure all generated elements are encapsulated in their own named groups.
 - 10. Material Assignment Functions     =   Not yet implemented save as a placeholder for now.
 - 20. Final Assembly Functions          =   Puts everything together to assemble the final rooflight, effectively the main method.
 - 30. Debug & Reporting                 =   Move all error handling and reporting here to keep the rest of the code lean.
 - 40. Event Handling & Callbacks / API  =   All elements related to interfacing with the main VDS User interface menu etc. 
 - 50. Entry Point Functions             =   Entry point for the script, this is the main method that is called by the script.


# Add Json System for profiles and components etc.
- Now the basic framework is in place we need to embellish the framework with mouldings, profiles, components, etc.
- We already have a robust system for loading and managing profiles, see `ADD_FOLDER_NAME`
  - This contains `SketchUpToJson.rb-tbc` and `JsonToSketchUp.rb-tbc`
- Json Loader for profiles and components etc.

## -----------------------------------------------------------------------------


## -----------------------------------------------------------------------------

**15-Aug-2025 - Version 0.8.3 - Added Development Utilities**
- Hot-reload functionality for ValeDesignSuite Ruby scripts during development.
- Allows developers to reload all .rb files without restarting SketchUp.
- Provides comprehensive error handling and reporting for script loading issues.
- Created a new UI Menu Page for Development Utilities.
- Button for new page added to main UI menu Last in the grid.

## -----------------------------------------------------------------------------


## -----------------------------------------------------------------------------

**05-Jun-2025 - Version 0.8.2 - Added Component Browser Tool**
- Added Component Browser Tool
- Build out of the Component Browser Tool user interface
- Build and debugged drag and drop functionality for component placement into the model
- Ensured that the Component Browser Tool is working as expected


## -----------------------------------------------------------------------------


**26-May-2025 - Version 0.6.2 - Debug System Implementation**
- Comprehensive Debug System Implementation
  - Global debug configuration system with JSON-based settings
  - Conditional debug output to prevent console spam
  - Categorized debug messages with prefixes (FW, NODE, PANEL, ASSEMBLY, SERIAL, UI)
  - Timestamped debug output for better tracking
  - Performance timing functionality for operation analysis

- Debug Configuration Management
  - Created Config_FrameworkConfigurator_DebugSettings.json for persistent settings
  - Implemented ValeDesignSuite_Core_DebugConfiguration.rb for core debug functionality
  - Added ValeDesignSuite_Tools_FrameworkDebugTools.rb as framework-specific wrapper
  - Menu integration for easy debug mode control via SketchUp interface

- Debug System Features
  - DEBUG_MODE setting to enable/disable all debug output globally
  - REALTIME_UPDATE_DELAY configuration for UI update timing
  - MIN_PANEL_LENGTH setting for framework validation
  - Multiple control methods: menu, code, and configuration file
  - Error handling with stack trace logging

- Code Migration and Updates
  - Updated all existing debug tools to use new conditional system
  - Migrated ValeDesignSuite_Core_PluginDebuggingAndDiagnosticTools.rb
  - Updated ValeDesignSuite_Tools_FrameworkToolsDebugTools.rb
  - Modified ValeDesignSuite_Core_PluginScript.rb to integrate debug menu
  - Replaced direct puts statements with conditional debug calls

- Developer Experience Improvements
  - Added debug timing wrapper for performance analysis
  - Implemented debug_selection utility for component analysis
  - Created debug_assembly_data for framework data inspection
  - Added comprehensive error logging with context information
  - Menu items: "Toggle Debug Mode" and "Show Debug Status"

- Documentation and Examples
  - Updated README.md with comprehensive debug system documentation
  - Added usage examples for all debug functions
  - Included migration guide from old debug system
  - Documented all debug control methods and configuration options


## -----------------------------------------------------------------------------

**26-May-2025 - Version 0.5.0 - Major Development Update**
- Window Configurator Tool Implementation
  - Core window configuration functionality built
  - Basic UI controls and dimension management
  - Initial window component generation system

- Framework Configurator Development
  - Main editor interface established
  - Basic 2D view implementation
  - Core configuration controls added
  - Initial framework generation system

- UI/UX Improvements
  - Enhanced main user interface
  - Added placeholder buttons for future tools
  - Improved navigation structure
  - Refined visual hierarchy

- Project Structure Reorganization
  - Created dedicated asset management system
  - Established data file organization
  - Implemented configuration file structure
  - Organized tools into logical groupings

- Framework Tools Refactoring
  - Moved framework tools to dedicated directory
  - Restructured framework-related scripts
  - Updated file references and dependencies
  - Improved code organization and maintainability

- Code Base Improvements
  - Comprehensive code refactoring
  - Enhanced error handling
  - Improved code documentation
  - Streamlined development workflow


## -----------------------------------------------------------------------------


**21-May-2025 - Version 0.1.0 - Initial Development**
- Basic project structure setup.
- Simple Vale branded HTML / CSS / JS UI Setup and integration with SketchUpRuby Environment .
- Roof Lantern Tool script ported from previous plugin and built into the new plugin UI.
- Main tool selection menu page created.
- Concept for the Framework configurator 2D View implemented in HTML / CSS / JavaScript.


=============================================================================

