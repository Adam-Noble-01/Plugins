# ValeDesignSuite Framework Configurator Integration

## Overview
The ValeDesignSuite Framework Configurator has been successfully integrated with the Window Panel Configurator system. This integration enables dynamic creation and configuration of framework assemblies with actual 3D geometry in SketchUp.

## Key Features

### 1. Geometry Creation
- **Automatic Geometry Generation**: When creating or updating a framework, actual 3D geometry is now generated in SketchUp
- **Node Representation**: Framework nodes (columns) are created as 3D boxes with appropriate dimensions
- **Panel Representation**: Framework panels are created as semi-transparent 3D elements between nodes
- **Material Application**: Different materials are applied to nodes and panels for visual distinction

### 2. Window Panel Integration
- **Panel Click Detection**: Click on any window panel in the 2D canvas to configure it
- **Integrated Configuration**: Window panel configurator opens with dimensions constrained to the selected panel
- **Visual Indicators**: Window panels display a small icon to indicate they are configurable
- **Panel Type Support**: Currently supports "Window_Panel" type with extensibility for other types

### 3. Data Flow Architecture

```
User Interface (JavaScript)
    ↓
Framework Configurator Logic
    ↓
Ruby Backend (SketchUp Logic)
    ↓
Framework Geometry Generator
    ↓
3D Model in SketchUp
```

## File Structure

### Core Files
- `ValeDesignSuite_Tools_FrameworkToolsSketchUpLogic.rb` - Main backend logic with geometry creation integration
- `ValeDesignSuite_Tools_FrameworkToolsGeometryGenerator.rb` - Handles 3D geometry creation
- `ValeDesignSuite_Tools_FrameworkConfigurator_Logic.js` - Frontend JavaScript with panel interaction
- `ValeDesignSuite_Core_MainUserInterface.rb` - UI callbacks and integration points
- `ValeDesignSuite_Tools_FrameworkIntegratedWindowPanelConfigurator.rb` - Window panel integration module

### Test Files
- `ValeDesignSuite_Test_FrameworkGeometryCreation.rb` - Test script for verifying geometry creation

## Usage

### Creating a Framework with Geometry
1. Open the Framework Configurator from the Vale Design Suite menu
2. Add nodes and panels using the UI
3. Click "Create New Framework" to generate the assembly with geometry
4. The 3D geometry will appear in the SketchUp model

### Configuring Window Panels
1. Select a framework component in SketchUp
2. Click on any window panel in the 2D canvas
3. The Window Panel Configurator will open with:
   - Width constrained to the panel's dimensions
   - All other configuration options available (glazing bars, colors, etc.)
4. Save changes to update the panel configuration

### Updating Framework Geometry
1. Select an existing framework component
2. Make changes in the configurator UI
3. Click "Save Data" to update both the data and geometry
4. The 3D model will reflect the changes

## Technical Details

### Geometry Creation Process
1. **Node Creation**: Each node is created as a grouped box with dimensions from the node data
2. **Panel Creation**: Panels are created as extruded rectangles between connected nodes
3. **Material Assignment**: Custom materials are applied for visual distinction
4. **Component Structure**: All geometry is created within the component definition

### Panel Interaction System
1. **Click Regions**: The canvas maintains clickable regions for each panel
2. **Visual Feedback**: Window panels show a blue window icon
3. **Constraint System**: Panel width is automatically constrained based on framework dimensions
4. **Data Persistence**: Panel configurations are stored with the framework data

### Data Storage
- Framework data is stored on component instances using SketchUp's attribute dictionaries
- Each framework has a unique Assembly ID (e.g., VFW001)
- Panel configurations are linked to their parent framework

## Testing

Run the included test script to verify the integration:

1. In SketchUp, go to Plugins → Framework Geometry Tests
2. Select "Create Test Framework with Geometry"
3. A test framework will be created with nodes and panels
4. Click on panels in the UI to test configuration

## Known Limitations

1. **Panel Types**: Currently only "Window_Panel" type is fully supported for configuration
2. **Y-Axis Movement**: Nodes can only be moved along the X-axis in the 2D view
3. **Panel Dimensions**: Panel height is fixed to framework height

## Future Enhancements

1. Support for door panels and blanking panels
2. Advanced panel configuration options (opening styles, hardware)
3. 3D preview of panel configurations
4. Export/import of framework configurations
5. Integration with other Vale Design Suite tools

## Troubleshooting

### No Geometry Appears
- Check Ruby Console for error messages
- Ensure all required files are present
- Verify that nodes and panels have valid data

### Panel Click Not Working
- Ensure a framework component is selected
- Check that the panel type is "Window_Panel"
- Verify JavaScript console for errors

### Geometry Not Updating
- Make sure to click "Save Data" after changes
- Check that the component has a valid Assembly ID
- Review Ruby Console for update errors

## API Reference

### Ruby Methods
```ruby
# Create new framework with geometry
FrameworkToolsSketchUpLogic.create_new_framework_assembly(name, nodes, panels)

# Update existing framework geometry
FrameworkToolsSketchUpLogic.update_framework_geometry(assembly_id)

# Handle panel configuration
FrameworkIntegratedWindowPanelConfigurator.handle_panel_click(panel_id, component)
```

### JavaScript Functions
```javascript
// Handle panel clicks
app.handlePanelClick(panelId, panelIndex)

// Check if point is in panel region
app.isPointInPanelRegion(x, y, panelRegion)
```

## Version History
- v1.0.0 - Initial integration of framework configurator with geometry creation
- v1.1.0 - Added window panel configurator integration
- v1.2.0 - Enhanced visual indicators and click handling 