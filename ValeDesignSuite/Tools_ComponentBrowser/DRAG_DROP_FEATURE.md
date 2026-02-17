# Vale Component Browser - Drag & Drop Feature

## Overview
The Vale Component Browser now supports intuitive drag-and-drop functionality with live preview, similar to SketchUp's native component browser.

## How It Works

### User Experience
1. **Drag Initiation**: Click and drag any component from the browser
2. **Live Preview**: A semi-transparent preview of the component follows your cursor in the SketchUp viewport
3. **Smart Inference**: The preview snaps to SketchUp's inference points (endpoints, midpoints, faces, etc.)
4. **Placement**: Click to place the component at the desired location
5. **Multiple Placement**: Hold Shift while clicking to place multiple copies
6. **Cancellation**: Press Esc at any time to cancel the operation

### Visual Feedback
- Components show a "grab" cursor on hover
- Dragging components become semi-transparent in the browser
- The browser window automatically dims during drag operations
- Live preview in the viewport shows exact component geometry

## Technical Implementation

### Ruby Side
- **DragPreviewTool**: Enhanced tool class that creates and manages the preview instance
- **Drag Detection**: JavaScript communicates drag start to Ruby via action callbacks
- **Preview Management**: Temporary instance is created and moved in real-time
- **Operation Handling**: Proper undo/redo support with operation wrapping

### JavaScript Side
- **Drag Events**: HTML5 drag API detects drag start/end
- **Dialog State**: Browser minimizes opacity during drag for better viewport visibility
- **Drag Cancellation**: Detects if drag ends within dialog to cancel operation

### Key Features
1. **Cross-platform**: Works on both Windows and Mac
2. **Performance**: Efficient preview updates using SketchUp's native transformation methods
3. **Compatibility**: Falls back to click-to-place on older SketchUp versions
4. **Clean UI**: Seamless integration with existing browser interface

## Code Structure

```ruby
# New drag preview tool
class DragPreviewTool
  # Creates temporary instance on activation
  # Moves instance with mouse movement
  # Handles placement or cancellation
end

# Enhanced callbacks
add_action_callback("start_component_drag") # Triggered on drag start
add_action_callback("cancel_drag")          # Triggered on drag cancel
```

## Usage Example

```ruby
# Load the component browser
require 'Tools_ComponentBrowser/ValeDesignSuite_Tools_ComponentBrowser.rb'

# Initialize browser with drag-drop support
ValeDesignSuite::Tools::ComponentBrowser.init
```

## Benefits Over Click-to-Insert
1. **Intuitive**: Natural drag-and-drop metaphor
2. **Visual**: See exactly what you're placing before committing
3. **Efficient**: Faster workflow for placing multiple components
4. **Professional**: Matches behavior of native SketchUp tools 