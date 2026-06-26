# Vale Design Suite - Framework Tools

## Overview
The Framework Tools module is a comprehensive suite of tools for creating, configuring, and managing framework structures in SketchUp. This module provides a complete solution for generating and manipulating framework components, including nodes, panels, and integrated elements.

**NEW**: The Framework Tools now feature a dynamic configuration system that loads default settings from external JSON files, allowing for easy customization without code modifications.

## Core Components

### Framework Configurator
- `ValeDesignSuite_Tools_FrameworkToolsConfigurator.rb`: Main configuration interface for framework tools
- `ValeDesignSuite_Tools_FrameworkConfigurator_Logic.js`: JavaScript logic for framework configuration UI

### Framework Core Logic
- `ValeDesignSuite_Tools_FrameworkToolsSketchUpLogic.rb`: Core SketchUp-specific logic for framework manipulation
- `ValeDesignSuite_Tools_FrameworkToolsDataSerializer.rb`: Data serialization and management for framework components

### Node Management
- `ValeDesignSuite_Tools_FrameworkNodeConfigurator.rb`: Node creation and configuration tools
- `ValeDesignSuite_Tools_FrameworkIntegratedNodeConfigurator.rb`: Integrated node system management

### Panel System
- `ValeDesignSuite_Tools_FrameworkIntegratedWindowPanelConfigurator.rb`: Window and panel configuration tools

### Coordination
- `ValeDesignSuite_Tools_FrameworkCoordinationManager.rb`: Manages coordination between different framework components

### Debug Tools
- `ValeDesignSuite_Tools_FrameworkDebugTools.rb`: Framework-specific debug utilities and logging

## Dynamic Configuration System

### Overview
The Framework Tools use a dynamic configuration system that loads default settings from external JSON files. This allows users and developers to customize framework behavior without modifying Ruby code.

### Configuration Files
The following JSON configuration files control framework defaults:

#### 1. Assembly Configuration
**File**: `ValeDesignSuite_Config_FrameworkConfigurator_DefaultAssemblyConfig.json`
**Purpose**: Controls default settings for framework assembly containers

**Key Settings**:
- Assembly dimensions (length, height, depth)
- Material properties (default materials, frame thickness)
- Container properties (max nodes, max panels)
- Structural properties (load bearing, weatherproof)
- Performance settings (realtime updates, batch operations)

#### 2. Node Configuration  
**File**: `ValeDesignSuite_Config_FrameworkConfigurator_DefaultNodeConfig.json`
**Purpose**: Controls default settings for framework nodes (structural connection points)

**Key Settings**:
- Node dimensions (width, height, depth)
- Material properties (default material, grain direction)
- Connection properties (max connections, joint types)
- Node types (corner, tee, cross, inline, custom)
- Fabrication properties (CNC machinable, tolerances)

#### 3. Panel Configuration
**File**: `ValeDesignSuite_Config_FrameworkConfigurator_DefaultPanelConfig.json`
**Purpose**: Controls default settings for framework panels (infill elements)

**Key Settings**:
- Panel dimensions (length, height, thickness)
- Material properties (default material, edge treatment)
- Panel types (solid, glazed, louvered, mesh, composite)
- Infill patterns (grid, diagonal, radial, organic)
- Connection properties (attachment methods, fasteners)

### Configuration Loading Process

#### 1. Primary Loading
Scripts attempt to load configurations from JSON files in the same directory:
```ruby
config_file_path = File.join(__dir__, "ValeDesignSuite_Config_FrameworkConfigurator_DefaultNodeConfig.json")
```

#### 2. Fallback System
If JSON files are missing or corrupted, scripts use hardcoded fallback defaults:
```ruby
rescue JSON::ParserError => e
    DebugTools.debug_node("Error parsing config: #{e.message}")
    return create_fallback_configuration
```

#### 3. Format Conversion
JSON configurations are converted to internal legacy formats for backward compatibility:
```ruby
# Convert to legacy DEFAULT_CONFIG format
legacy_config = {
    "nodeMetadata" => [...],
    "nodeComponents" => [...],
    "nodeConfiguration" => {...}
}
```

### Customization Examples

#### Modifying Default Node Dimensions
Edit `ValeDesignSuite_Config_FrameworkConfigurator_DefaultNodeConfig.json`:
```json
{
  "node_defaults": {
    "dimensions": {
      "width_mm": 100,     // Changed from 70mm
      "height_mm": 100,    // Changed from 70mm  
      "depth_mm": 44       // Standard framework depth
    }
  }
}
```

#### Adding Custom Panel Types
Edit `ValeDesignSuite_Config_FrameworkConfigurator_DefaultPanelConfig.json`:
```json
{
  "panel_types": {
    "custom_perforated": {
      "description": "Custom perforated metal panel",
      "transparency": 40,
      "structural_contribution": "medium",
      "perforation_pattern": "hexagonal"
    }
  }
}
```

#### Adjusting Assembly Constraints
Edit `ValeDesignSuite_Config_FrameworkConfigurator_DefaultAssemblyConfig.json`:
```json
{
  "assembly_defaults": {
    "container_properties": {
      "max_nodes": 100,        // Increased capacity
      "max_panels": 200,       // Increased capacity
      "auto_organize": true,
      "collision_detection": true
    }
  }
}
```

### Configuration Safety Features

#### Error Handling
- **JSON Validation**: Invalid JSON files are detected and logged
- **Fallback Defaults**: System continues with safe defaults if configuration fails
- **Debug Logging**: All configuration errors are logged through the debug system

#### Backward Compatibility
- **Legacy Support**: Existing configurations continue to work
- **Format Conversion**: New JSON format is converted to legacy internal format
- **Gradual Migration**: Old hardcoded defaults remain as fallbacks

#### Validation
- **Required Properties**: Missing required properties trigger fallback behavior
- **Type Checking**: Configuration values are validated for correct types
- **Range Validation**: Dimensional values are checked against reasonable limits

## Features

### Framework Generation
- Automated framework structure creation
- Customizable node placement and configuration
- Integrated panel system management
- Real-time preview and updates
- **NEW**: Dynamic configuration loading from JSON files

### Node System
- Flexible node creation and placement
- Support for various node types and configurations
- Integrated node management system
- Automatic node coordination
- **NEW**: JSON-configurable node defaults and constraints

### Panel Management
- Window and door panel configuration
- Panel type selection and customization
- Integrated panel system coordination
- Real-time panel updates
- **NEW**: JSON-configurable panel types and properties

### Data Management
- JSON-based configuration storage
- Component data serialization
- State management and persistence
- Configuration version control
- **NEW**: External JSON configuration files for easy customization

## Usage

### Basic Framework Creation
1. Launch the Framework Tools interface
2. Select framework type and dimensions (loaded from assembly config)
3. Configure node placement (using node config defaults)
4. Add panels and glazing (using panel config defaults)
5. Apply materials and finishes

### Advanced Configuration
- Custom node placement with JSON-defined constraints
- Panel type selection from JSON-configured options
- Material assignment using JSON-defined defaults
- Framework modification within JSON-specified limits

### Configuration Customization
1. **Locate** the appropriate JSON configuration file in `Tools_FrameworkTools/`
2. **Edit** the desired properties using a text editor
3. **Validate** JSON syntax (use online JSON validators if needed)
4. **Save** the file and restart SketchUp
5. **Test** new configurations by creating framework components

## Development

### File Structure
All framework-related files are contained within the `Tools_FrameworkTools` directory for better organization and maintainability.

### Configuration Files Location
```
Tools_FrameworkTools/
├── ValeDesignSuite_Config_FrameworkConfigurator_DefaultAssemblyConfig.json
├── ValeDesignSuite_Config_FrameworkConfigurator_DefaultNodeConfig.json
├── ValeDesignSuite_Config_FrameworkConfigurator_DefaultPanelConfig.json
├── ValeDesignSuite_Tools_FrameworkNodeConfigurator.rb
├── ValeDesignSuite_Tools_FrameworkIntegratedWindowPanelConfigurator.rb
├── ValeDesignSuite_Tools_FrameworkToolsSketchUpLogic.rb
└── [other framework files...]
```

### Integration
The framework tools integrate with the main Vale Design Suite plugin through the core interface system and now support dynamic configuration loading.

### Dependencies
- SketchUp Ruby API
- JSON data structures and parsing
- WebDialog interface
- Custom UI components
- **NEW**: External JSON configuration files

### Configuration Development
When developing new features that require default settings:

1. **Add** new properties to the appropriate JSON configuration file
2. **Update** the loading logic in the corresponding Ruby script
3. **Implement** fallback defaults for backward compatibility
4. **Test** with both valid and invalid/missing JSON files
5. **Document** new configuration options

## Maintenance

### Code Organization
- All framework-related code is now centralized in the `Tools_FrameworkTools` directory
- Clear separation of concerns between different components
- Modular design for easy updates and maintenance
- **NEW**: Configuration separated from code for easy customization

### Configuration Management
- **Version Control**: JSON configuration files should be version controlled
- **Documentation**: Changes to configuration structure should be documented
- **Testing**: New configurations should be tested with various scenarios
- **Backup**: Keep backup copies of working configurations

### Documentation
- Comprehensive inline documentation
- Clear function and module organization
- Consistent coding style following Vale Design Suite conventions
- **NEW**: Configuration file documentation and examples

## Troubleshooting

### Configuration Issues
- **Missing JSON Files**: Check that configuration files exist in `Tools_FrameworkTools/`
- **Invalid JSON**: Validate JSON syntax using online tools
- **Debug Output**: Enable debug mode to see configuration loading messages
- **Fallback Behavior**: System should continue working with default values

### Common Problems
- **Syntax Errors**: Ensure proper JSON formatting (commas, brackets, quotes)
- **Missing Properties**: Required properties must be present in JSON files
- **Invalid Values**: Dimensional values should be positive numbers
- **File Permissions**: Ensure JSON files are readable by SketchUp

## Future Development
- Enhanced node system capabilities
- Additional panel types and configurations
- Improved coordination between components
- Advanced material management
- Performance optimizations
- **NEW**: Enhanced configuration validation and UI for JSON editing

## Support
For issues and feature requests, please contact the development team through the appropriate channels. 