# Vale Design Suite

## Version: 0.8.3  -  15-Aug-2025

# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# !!WARNING!! THIS DOCUMENT IS OUTDATED AND NEEDS TO BE UPDATED!!
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

## Overview
The Vale Design Suite is a comprehensive SketchUp plugin for creating and managing 3D models for Vale Garden Houses. This plugin provides a suite of tools to automate and streamline the creation of garden rooms, orangeries, and conservatories.

## Core Components

### Main Interface
- `ValeDesignSuite_Core_MainUserInterface.rb`: Main user interface and control center
- `ValeDesignSuite_Core_PluginScript.rb`: Core plugin functionality
- `ValeDesignSuite_Core_PluginDebuggingAndDiagnosticTools.rb`: Debugging and development utilities

### Tools
- [Framework Tools](Tools_FrameworkTools/README.md): Comprehensive framework creation and management tools
- [Roof Lantern Tools](Tools_RoofLanternConfigurator/README.md): Roof lantern generation and configuration
- [Window Panel Tools](Tools_WindowPanelConfigurator/README.md): Window and panel configuration
- [Component Browser](Tools_ComponentBrowser/): Vale component library browser with folder navigation

### Configuration
- `Config_PluginConfigFiles/`: Plugin configuration files and dependencies
- `Config_ValeProductData/`: Product data and configurations

### Assets
- `Assets_PluginAssets/`: Plugin assets and resources
- `Assets_ValeBrandAssets/`: Brand assets and resources

### Development
- `00_DEV_-_Developer-Utilities/`: Development utilities and tools
- `01_DEV_-_Testing-&-Concept-Scripts/`: Testing and concept scripts

## Dynamic Configuration System

### Overview
The Vale Design Suite features a dynamic configuration system that loads default settings from external JSON files. This allows for easy customization of framework assemblies, nodes, and panels without modifying code.

### Configuration Files
The following JSON configuration files control default settings:

#### Framework Tools Configuration Files
Located in `Tools_FrameworkTools/`:
- `ValeDesignSuite_Config_FrameworkConfigurator_DefaultAssemblyConfig.json`: Assembly container properties
- `ValeDesignSuite_Config_FrameworkConfigurator_DefaultNodeConfig.json`: Node structural properties  
- `ValeDesignSuite_Config_FrameworkConfigurator_DefaultPanelConfig.json`: Panel infill properties

#### Debug Configuration File
Located in `Config_PluginConfigFiles/`:
- `Config_FrameworkConfigurator_DebugSettings.json`: Debug system settings

### Configuration Structure

#### Assembly Configuration
```json
{
  "metadata": {
    "file_name": "ValeDesignSuite_Config_FrameworkConfigurator_DefaultAssemblyConfig.json",
    "description": "Default configuration settings for Framework Assembly creation",
    "author": "Adam Noble - Noble Architecture",
    "version": "1.0.0"
  },
  "assembly_defaults": {
    "name": "Framework_Assembly",
    "dimensions": {
      "length_mm": 2400,
      "height_mm": 2100,
      "depth_mm": 150
    },
    "material_properties": {
      "default_material": "Wood_Pine",
      "frame_thickness_mm": 44
    },
    "container_properties": {
      "max_nodes": 50,
      "max_panels": 100
    }
  }
}
```

#### Node Configuration
```json
{
  "metadata": {
    "file_name": "ValeDesignSuite_Config_FrameworkConfigurator_DefaultNodeConfig.json",
    "description": "Default configuration settings for Framework Node creation",
    "version": "1.0.0"
  },
  "node_defaults": {
    "name": "Framework_Node",
    "node_type": "corner",
    "dimensions": {
      "width_mm": 70,
      "height_mm": 70,
      "depth_mm": 44
    },
    "material_properties": {
      "default_material": "Wood_Pine"
    }
  },
  "node_types": {
    "corner": {
      "description": "Corner connection node",
      "max_connections": 2
    }
  }
}
```

#### Panel Configuration
```json
{
  "metadata": {
    "file_name": "ValeDesignSuite_Config_FrameworkConfigurator_DefaultPanelConfig.json",
    "description": "Default configuration settings for Framework Panel creation",
    "version": "1.0.0"
  },
  "panel_defaults": {
    "name": "Framework_Panel",
    "panel_type": "solid",
    "dimensions": {
      "length_mm": 600,
      "height_mm": 600,
      "thickness_mm": 18
    },
    "material_properties": {
      "default_material": "Plywood_Birch"
    }
  },
  "panel_types": {
    "solid": {
      "description": "Solid panel with no openings",
      "transparency": 0
    },
    "glazed": {
      "description": "Glass or transparent panel",
      "transparency": 90
    }
  }
}
```

### Configuration Behavior

#### Loading Process
1. **Primary**: Scripts attempt to load from external JSON files
2. **Fallback**: If JSON files are missing or corrupted, scripts use hardcoded defaults
3. **Validation**: All loaded configurations are validated for required properties
4. **Conversion**: JSON data is converted to internal formats for backward compatibility

#### Customization Workflow
1. **Locate** the appropriate JSON configuration file
2. **Edit** the desired properties (dimensions, materials, constraints)
3. **Save** the file with valid JSON syntax
4. **Restart** SketchUp or reload the plugin to apply changes
5. **Test** new configurations by creating framework components

#### Safety Features
- **Fallback Defaults**: System remains functional with corrupted/missing JSON files
- **Error Logging**: JSON parsing errors are logged through the debug system
- **Validation**: Invalid configurations are rejected with safe fallbacks
- **Backward Compatibility**: Legacy configurations continue to work

### Affected Scripts
The following scripts load from external JSON configuration files:

#### Primary Configuration Scripts
- `ValeDesignSuite_Tools_FrameworkNodeConfigurator.rb`: Loads node defaults
- `ValeDesignSuite_Tools_FrameworkIntegratedWindowPanelConfigurator.rb`: Loads panel defaults
- `ValeDesignSuite_Tools_FrameworkToolsSketchUpLogic.rb`: Loads assembly, node, and panel defaults

#### Integration Scripts
- `ValeDesignSuite_Tools_FrameworkIntegratedNodeConfigurator.rb`: Uses node configuration system
- `ValeDesignSuite_Tools_FrameworkCoordinationManager.rb`: Coordinates configuration-based positioning

### Configuration Examples

#### Customizing Default Node Dimensions
```json
// In DefaultNodeConfig.json
"node_defaults": {
  "dimensions": {
    "width_mm": 100,    // Changed from 70mm
    "height_mm": 100,   // Changed from 70mm
    "depth_mm": 44      // Unchanged
  }
}
```

#### Adding New Panel Types
```json
// In DefaultPanelConfig.json
"panel_types": {
  "custom_mesh": {
    "description": "Custom perforated mesh panel",
    "transparency": 60,
    "structural_contribution": "medium"
  }
}
```

#### Modifying Assembly Constraints
```json
// In DefaultAssemblyConfig.json
"assembly_defaults": {
  "container_properties": {
    "max_nodes": 100,     // Increased from 50
    "max_panels": 200     // Increased from 100
  }
}
```

## Debug System

### Overview
The Vale Design Suite includes a comprehensive debug system that provides conditional logging and diagnostic tools. This system prevents console spam while maintaining detailed debugging capabilities when needed.

### Key Features
- **Global Debug Switch**: Enable/disable all debug output with a single setting
- **Categorized Output**: Different prefixes for different operations (NODE, PANEL, ASSEMBLY, etc.)
- **Timestamped Messages**: All debug messages include timestamps for better tracking
- **Performance Timing**: Built-in timing functionality for performance analysis
- **Menu Integration**: Easy toggle via SketchUp's menu system
- **Persistent Settings**: Configuration saved to JSON file

### Debug Configuration Files
- `Config_FrameworkConfigurator_DebugSettings.json`: Main debug configuration file
- `ValeDesignSuite_Core_DebugConfiguration.rb`: Core debug configuration module
- `ValeDesignSuite_Tools_FrameworkDebugTools.rb`: Framework-specific debug wrapper

### Debug Settings
```json
{
  "DEBUG_MODE": false,              // Enable/disable debug output
  "REALTIME_UPDATE_DELAY": 500,     // Delay for real-time updates (ms)
  "MIN_PANEL_LENGTH": 100           // Minimum panel length (mm)
}
```

### Usage Examples

#### Basic Debug Logging
```ruby
# At the top of your file
require_relative 'Tools_FrameworkTools/ValeDesignSuite_Tools_FrameworkDebugTools'
DebugTools = ValeDesignSuite::Tools::FrameworkDebugTools

# In your methods
DebugTools.debug_log("General framework message")          # [FW] prefix
DebugTools.debug_node("Node operation message")            # [NODE] prefix
DebugTools.debug_panel("Panel operation message")          # [PANEL] prefix
DebugTools.debug_assembly("Assembly operation message")    # [ASSEMBLY] prefix
DebugTools.debug_serializer("Serializer operation")       # [SERIAL] prefix
DebugTools.debug_ui("UI operation message")               # [UI] prefix
```

#### Conditional Debug Blocks
```ruby
# Only execute expensive debug operations when needed
return unless DebugTools.debug_mode?

DebugTools.debug_log("Starting detailed analysis...")
# Expensive debug operations here
```

#### Performance Timing
```ruby
result = DebugTools.debug_timing("Framework generation") do
  # Your time-consuming operation here
  generate_framework(nodes, panels)
end
# Outputs: "Framework generation completed in 125.3ms"
```

#### Error Handling
```ruby
begin
  # Your code
rescue => e
  DebugTools.debug_error("Failed to create framework", e)
end
```

### Debug Control Methods

#### Via Menu
- **Plugins > Vale Design Suite > Debug Tools > Toggle Debug Mode**
- **Plugins > Vale Design Suite > Debug Tools > Show Debug Status**

#### Via Code
```ruby
DebugTools.enable_debug     # Turn on debug mode
DebugTools.disable_debug    # Turn off debug mode
DebugTools.toggle_debug     # Toggle current state
```

#### Via Configuration File
Edit `Config_FrameworkConfigurator_DebugSettings.json` and set `DEBUG_MODE` to `true` or `false`.

### Migration from Old Debug System
```ruby
# OLD WAY (always outputs):
puts "Creating framework assembly..."
puts "Assembly ID: #{assembly_id}"

# NEW WAY (only when DEBUG_MODE is true):
DebugTools.debug_assembly("Creating framework assembly...")
DebugTools.debug_assembly("Assembly ID: #{assembly_id}")
```

## Directory Structure

### Main Directories
- `Tools_FrameworkTools/`: Framework tools and related components
- `Tools_RoofLanternConfigurator/`: Roof lantern configuration tools
- `Tools_WindowPanelConfigurator/`: Window panel configuration tools
- `PluginDocumentation/`: Plugin documentation and design documents
- `Config_ValeProductData/`: Product data and configurations
- `Assets_ValeBrandAssets/`: Brand assets and resources
- `Config_PluginConfigFiles/`: Plugin configuration files
- `Assets_PluginAssets/`: Plugin assets and resources
- `00_DEV_-_Developer-Utilities/`: Development utilities
- `01_DEV_-_Testing-&-Concept-Scripts/`: Testing and concept scripts

## Features

### Core Functionality
- Interactive 3D model creation
- Automated component generation
- Real-time preview and updates
- Customizable configurations via external JSON files

### Tools
- Framework generation and management
- Roof lantern creation and configuration
- Window and panel configuration
- Material management
- Component library browser with thumbnail preview and drag-and-drop

### Debug and Development
- Comprehensive debug logging system
- Performance timing and analysis
- Component and model diagnostics
- Script dependency validation
- Path and asset verification

## Development

### Requirements
- SketchUp 2026
- Ruby API
- WebDialog support

### Setup
1. Install SketchUp 2026
2. Place plugin files in SketchUp plugins directory
3. Restart SketchUp
4. Access through Extensions menu

### Debug Setup for Developers
1. Enable debug mode via menu: **Plugins > Vale Design Suite > Debug Tools > Toggle Debug Mode**
2. Or edit `Config_FrameworkConfigurator_DebugSettings.json` and set `"DEBUG_MODE": true`
3. Debug messages will appear in the Ruby Console with timestamps and categories
4. Use appropriate debug methods in your code for categorized output

### Configuration Setup for Developers
1. **Locate** configuration files in `Tools_FrameworkTools/` directory
2. **Modify** JSON files to customize default behaviors
3. **Test** changes by creating new framework components
4. **Validate** JSON syntax to ensure proper loading
5. **Document** any custom configurations for team members

## Documentation
- [Framework Tools Documentation](Tools_FrameworkTools/README.md)
- [Roof Lantern Tools Documentation](Tools_RoofLanternConfigurator/README.md)
- [Window Panel Tools Documentation](Tools_WindowPanelConfigurator/README.md)
- Component Browser Documentation (integrated tool)
- [Plugin Design Document](PluginDocumentation/01_-_ValeDesignSuite_-_MasterPluginDesignDocument.txt)
- [Development Log](PluginDocumentation/02_-_ValeDesignSuite_-_Development-Log.txt)
- [Coding Conventions](PluginDocumentation/03_-_ValeDesignSuite_-_ProjectCodingConventions.txt)

## Support
For issues and feature requests, please contact the development team through the appropriate channels.

## License
Proprietary - Vale Garden Houses 