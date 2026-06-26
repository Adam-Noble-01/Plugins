// =============================================================================
// ValeDesignSuite - [Tool/Module Name]
// =============================================================================
//
// THIS FILE :  ValeDesignSuite_Tools_FrameworkConfigurator_Logic.js
// NAMESPACE :  ValeDesignSuite
// MODULE    :  FrameworkConfigurator
// AUTHOR    :  Adam Noble - Vale Garden Houses
// TYPE      :  JavaScript
// PURPOSE   :  2D Plan View For Setting Out Framework & Panels For A VGH Orangery / Conservatory
// CREATED   :  21-May-2025
//
// DESCRIPTION:
// - This file contains the JavaScript logic for the 2D Framework Configurator view.
// - This script provides the core logic for the 2D Framework Configurator view.
// - It handles canvas drawing, user interactions, and communication with the Ruby backend for data operations.
// - This Ruby Interaction is Critical for the tool to read / write data to SketchUps Model Dictionaries & Components.
//
// DESIGN OF TOOL INTERFACE
// ----------------------
// - The tool interface is designed to be a 2D drawing area that allows the user to create Vale Orangery / Conservatory outer framework.
// - The graphical representation of the framework is a 2D top down view of the framework.
// - This allows for quick and forgiving setting out in an abstract manner before delving into the 3D model and its complexities.
// - The framework is made up of a series of nodes and panel lines.
//   - Nodes are items such as columns, upright framework elements etc
//   - Panel Lines are the panels between the framework nodes, which are the glazed panels of the orangery / conservatory such as doors, windows, or blanking panels etc.
// - The user can add nodes and lines by clicking and dragging on the canvas. 
// - The nodes and lines can be moved around on the canvas by dragging them.
// 
// IMPORTANT CONSIDERATIONS: 
// - This tool is designed to be used in conjunction with the following scripts.
//   - ValeDesignSuite_Core_MainUserInterface.rb
//   - ValeDesignSuite_Tools_FrameworkToolsSketchUpLogic.rb
//   - ValeDesignSuite_Core_PluginScript.rb
//
// -----------------------------------------------------------------------------
//
// DEVELOPMENT LOG:
// 21-May-2025 - Version 0.0.1 - Initial Development
// - Initial Development of the JavaScript logic for the 2D Framework Configurator view.
//
// =============================================================================


// #region =======================================================================
// - - - - - - - - - - - IIFE MODULE DEFINITION  - - - - - - - - - - - - - - - -
// ===============================================================================
const app = (function() {

    // #region -----------------------------------------------------------------------
    // - - - - - - - - - - - NODE TYPE CONFIGURATION JSON - - - - - - - - - - - - -
    // -----------------------------------------------------------------------------
    
    // MODULE VARIABLES | Node Type Configuration (Loaded from Ruby)
    // ------------------------------------------------------------
    let NODE_TYPES_CONFIG = null;                                            // <-- Will be loaded from Ruby as single source of truth
    // endregion ----------------------------------------------------

    // FUNCTION | Load Node Types Configuration from Ruby
    // ---------------------------------------------------------------
    function loadNodeTypesConfig() {
        if (window.sketchup && window.sketchup.get_node_types_config) {
            console.log("Loading node types configuration from Ruby...");
            window.sketchup.get_node_types_config();                        // <-- Request from Ruby
        } else {
            console.error("Cannot load node types config - Ruby interface not available");
            // Fallback to prevent errors - this should not happen in production
            NODE_TYPES_CONFIG = {
                "nodeTypes": [
                    {
                        "NodeTypeId": "Column_CornerColumn",
                        "NodeTypeName": "Corner Column",
                        "DefaultDimensions": { "Width_mm": 290, "Depth_mm": 94, "Height_mm": 2000 },
                        "DisplayProperties": { "UIDisplayName": "Corner Column", "UIShortName": "Corner" }
                    }
                ]
            };
            console.warn("Using fallback node types configuration");
        }
    }
    // ---------------------------------------------------------------

    // CALLBACK | Receive Node Types Configuration from Ruby
    // ---------------------------------------------------------------
    function setNodeTypesConfig(configJson) {
        try {
            NODE_TYPES_CONFIG = JSON.parse(configJson);                     // <-- Parse JSON from Ruby
            console.log("Successfully loaded node types configuration from Ruby");
            console.log(`Loaded ${NODE_TYPES_CONFIG.nodeTypes ? NODE_TYPES_CONFIG.nodeTypes.length : 0} node types`);
            
            // **NEW**: Automatically refresh option arrays when config is loaded
            const optionArrays = generateNodeOptionArrays();
            optionTexts = optionArrays.optionTexts;
            optionNodeTypes = optionArrays.optionNodeTypes;
            console.log("Refreshed option arrays with", optionTexts.length, "node types");
            
        } catch (e) {
            console.error("Error parsing node types config from Ruby:", e);
            // Keep existing config if parsing fails
        }
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Get Node Type Configuration from JSON
    // ---------------------------------------------------------------
    function getNodeTypeConfig(nodeTypeId) {
        if (!NODE_TYPES_CONFIG || !NODE_TYPES_CONFIG.nodeTypes) {
            console.warn("Node types config not loaded yet, using fallback");
            return {
                "NodeTypeId": nodeTypeId,
                "NodeTypeName": "Default Column",
                "DefaultDimensions": { "Width_mm": 290, "Depth_mm": 94, "Height_mm": 2000 },
                "DisplayProperties": { "UIDisplayName": "Default", "UIShortName": "Def" }
            };
        }
        
        for (let nodeType of NODE_TYPES_CONFIG.nodeTypes) {
            if (nodeType.NodeTypeId === nodeTypeId) {
                return nodeType;                                             // <-- Return matching node type config
            }
        }
        
        // Return default corner column config if type not found
        console.log(`Node type '${nodeTypeId}' not found, using default`);
        return NODE_TYPES_CONFIG.nodeTypes[0];                              // <-- Return first (corner column) as default
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Generate Option Arrays from JSON Configuration
    // ---------------------------------------------------------------
    function generateNodeOptionArrays() {
        const optionTexts = [];                                              // <-- Initialize option texts array
        const optionNodeTypes = [];                                          // <-- Initialize option node types array
        
        if (NODE_TYPES_CONFIG && NODE_TYPES_CONFIG.nodeTypes) {
            NODE_TYPES_CONFIG.nodeTypes.forEach(nodeType => {
                const displayName = nodeType.DisplayProperties?.UIDisplayName || nodeType.NodeTypeName;
                optionTexts.push(displayName);                              // <-- Add display name to texts
                optionNodeTypes.push(nodeType.NodeTypeId);                  // <-- Add node type ID to types
            });
        } else {
            // Fallback options if config not loaded
            console.warn("Node types config not loaded, using fallback options");
            optionTexts.push("Corner Column", "290mm Column", "390mm Column", "100mm Column");
            optionNodeTypes.push("Column_CornerColumn", "Column_290mm", "Column_390mm", "Column_100mm");
        }
        
        return { optionTexts, optionNodeTypes };                            // <-- Return both arrays
    }
    // ---------------------------------------------------------------

    // #endregion

    // #region -----------------------------------------------------------------------
    // - - - - - - - - - - - MODULE SCOPED VARIABLES - - - - - - - - - - - - - - -
    // -----------------------------------------------------------------------------
    let scale                      =  1.0;       // Initial zoom level
    const frameworkThicknessMM     =  94;        // mm
    let frameworkMetadata          =  [];        // Added for metadata
    let frameworkNodes             =  [];        // Renamed from nodes
    let frameworkPanelLines        =  [];        // Renamed from lines
    let canvas, ctx, canvasContainer;            // canvasContainer made IIFE-scoped
    let isDragging                 =  false;       
    let dragTarget                 =  null;        
    let offsetX, offsetY;                        // For dragging nodes
    let lengthClickRegions         =    [];      // For clickable length inputs
    let currentLineEditContext     =  null;      // To store context for the custom prompt for lengths
    let currentPromptSaveCallback  =  null;      // To store the callback for the generic custom prompt
    let activeFrameworkComponentID =  null;      // To store the entityID of the SketchUp selected component

    // NODE OPTIONS | User configurable variables for node options
    // ------------------------------------------------------------
    let selectedNodeForOptions    =   null;
    let optionsVisible            =  false;
    let optionClickRegions        =  [];
    let optionTexts               =  [];  // <-- Will be populated from loaded config
    let optionNodeTypes           =  [];  // <-- Will be populated from loaded config
    let potentialDragTarget       =  null;      // For differentiating click from drag
    let mouseDownPoint            =  null;      // To store {x, y} of mousedown canvas coordinates

    // NAVIGATION CONTROL | Panning state variables
    let isPanning                 =  false;
    let lastPanX                  =  0;
    let lastPanY                  =  0;
    let viewOffsetX               =  0;       // Canvas view X offset for panning
    let viewOffsetY               =  0;       // Canvas view Y offset for panning

    // Define colors from CSS variables for JS usage
    let nodeColor, nodeTextColor, lineColor, gridColor;
    
    // PANEL CLICK REGIONS | Store clickable panel regions for interaction
    let panelClickRegions = [];
    // #endregion

    // CSS VARIABLES | Fetch and store CSS custom properties for use in canvas drawing
    // -------------------------------------------------------------------------------
    function fetchCssVariables() {
        const styles   =  getComputedStyle(document.documentElement);
        nodeColor      =  styles.getPropertyValue('--ValeSecondaryButtonBg').trim() || '#172b3a';
        nodeTextColor  =  styles.getPropertyValue('--ValeSecondaryButtonText').trim() || '#ffffff';
        lineColor      =  styles.getPropertyValue('--ValeHighlightColor').trim() || '#006600';
        gridColor      =  '#cccccc'; // Or make this a CSS var too if desired
    }
    // -------------------------------------------------------------------------------


    // CANVAS RESIZE | Perform canvas resize based on container dimensions
    // ---------------------------------------------------------------------
    function _performCanvasResize() { 
        if (!canvasContainer || !canvas || !ctx) {
            console.warn("_performCanvasResize: canvas, ctx, or canvasContainer not ready.");
            if (canvas) {
            canvas.width = canvas.width || 100; 
            canvas.height = canvas.height || 100;
            console.log("Canvas resized to fallback by _performCanvasResize: " + canvas.width + "x" + canvas.height);
            if (ctx) requestAnimationFrame(draw); 
            }
            return;
        }

        const style = getComputedStyle(canvasContainer);
        if (!style) {
            console.warn("_performCanvasResize: could not get computed style for canvasContainer.");
            canvas.width = Math.max(1, canvas.width || 100); 
            canvas.height = Math.max(1, canvas.height || 100);
            console.log("Canvas resized to fallback by _performCanvasResize (no style): " + canvas.width + "x" + canvas.height);
            requestAnimationFrame(draw);
            return;
        }

        const paddingX = parseFloat(style.paddingLeft) + parseFloat(style.paddingRight);
        const paddingY = parseFloat(style.paddingTop) + parseFloat(style.paddingBottom);

        const containerWidth = typeof canvasContainer.clientWidth === 'number' ? canvasContainer.clientWidth : 0;
        const containerHeight = typeof canvasContainer.clientHeight === 'number' ? canvasContainer.clientHeight : 0;
        const pX = !isNaN(paddingX) ? paddingX : 0;
        const pY = !isNaN(paddingY) ? paddingY : 0;

        let newWidth = containerWidth - pX;
        let newHeight = containerHeight - pY;

        canvas.width = Math.max(1, newWidth);
        canvas.height = Math.max(1, newHeight);
        
        console.log("Canvas resized via _performCanvasResize() to: " + canvas.width + "x" + canvas.height +
                    " (container: " + containerWidth + "x" + containerHeight +
                    ", padding: " + pX + ", " + pY + ")");
        requestAnimationFrame(draw);
    }
    // ---------------------------------------------------------------------------


    // #region -----------------------------------------------------------------------
    // - - - - - - - - - - - PANEL INTERACTION HANDLING - - - - - - - - - - - - - -
    // -----------------------------------------------------------------------------

    // FUNCTION | Handle Panel Click for Configuration
    // ---------------------------------------------------------------
    function handlePanelClick(panelId, panelIndex) {
        console.log(`Panel clicked: ${panelId} (index: ${panelIndex})`);
        
        // Check if we have an active framework component
        if (!activeFrameworkComponentID) {
            console.warn("No active framework component selected");
            showSaveStatusMessage("Please select a framework component first", false);
            return;
        }
        
        // Call Ruby backend to handle panel configuration
        if (window.sketchup && window.sketchup.handle_framework_panel_click) {
            console.log(`Requesting panel configuration for: ${panelId}`);
            showSaveStatusMessage(`Opening configuration for panel ${panelId}...`, true);
            window.sketchup.handle_framework_panel_click(panelId, activeFrameworkComponentID);
        } else {
            console.error("sketchup.handle_framework_panel_click is not available");
            showSaveStatusMessage("Panel configuration not available", false);
        }
    }
    // ---------------------------------------------------------------

    // FUNCTION | Check if Point is Inside Panel Click Region
    // ---------------------------------------------------------------
    function isPointInPanelRegion(x, y, panelRegion) {
        return x >= panelRegion.x && 
               x <= panelRegion.x + panelRegion.width &&
               y >= panelRegion.y && 
               y <= panelRegion.y + panelRegion.height;
    }
    // ---------------------------------------------------------------

    // #endregion


    // INITIALIZATION | Set up canvas, context, event listeners, and initial state
    // ---------------------------------------------------------------------------
    function init() {
        canvas = document.getElementById('drawing-canvas');
        if (!canvas) {
            console.error("FrameworkConfigurator_Logic.js: Canvas element #drawing-canvas not found!");
            return;
        }
        
        canvasContainer = document.getElementById('canvas-container'); 
        if (!canvasContainer) {
            console.error("FrameworkConfigurator_Logic.js: Canvas container #canvas-container not found!");
            // It's not critical to return here, as _performCanvasResize can handle a missing container
            // but it will warn and use fallback canvas dimensions.
        }

        // Initialize ctx before calling _performCanvasResize for the first time
        ctx = canvas.getContext('2d');
        if (!ctx) {
            console.error("FrameworkConfigurator_Logic.js: Failed to get 2D context from canvas!");
            return;
        }
        
        // Initialize view offsets for panning
        viewOffsetX = 0;
        viewOffsetY = 0;
        
        _performCanvasResize(); // Initial resize call using the new function name
        
        fetchCssVariables(); 
        
        // **NEW**: Load node types configuration from Ruby
        loadNodeTypesConfig();
        
        // **NEW**: Initialize option arrays from loaded configuration
        const optionArrays = generateNodeOptionArrays();
        optionTexts = optionArrays.optionTexts;
        optionNodeTypes = optionArrays.optionNodeTypes;
        
        window.addEventListener('resize', _performCanvasResize); // Use the new function name for window resize too

        // Initial state: a corner node
        // Initialize frameworkMetadata with a default entry if appropriate, or leave empty
        frameworkMetadata.push({
          FrameworkUniqueId: "VFW_Initial", // Example default ID
          FrameworkName: "DefaultFramework",
          FrameworkNotes: "Initial empty framework",
          FrameworkLength: 0, // Will be calculated or set later
          FrameworkWidth: 0,
          FrameworkHeight: 0
        });

        const startNodeId = "ND_" + Date.now(); // Prefix to match new ID scheme
        const startNodeWidth = 290; // Corner column width
        frameworkNodes.push({ 
          NodeUniqueId: startNodeId, // Updated property name
          x: 0, // Position left edge at origin - center will be calculated in coordinate transformation
          y: 0, // Framework nodes are positioned linearly along X-axis, Y=0
          NodeType: 'Column_CornerColumn', // Updated property name 
          NodeName: 'Start Corner', // Example, adjust as per your full structure
          NodeStyle: "", // Default empty style
          NodeNotes: "Starting corner column at origin", // Default notes
          NodePosX: 0, // Model position X
          NodePosY: 0, // Model position Y
          NodePosZ: 0, // Model position Z
          NodeSizeX: startNodeWidth, // Node width in mm (corner column)
          NodeSizeY: 94, // Node depth in mm
          NodeSizeZ: 2000, // Node height in mm
          NodeHeadHeight: 2000, // Head height
          NodeUsCillHeight: 0, // Cill height
          NodeRotationX: 0, // Rotation quaternion X
          NodeRotationY: 0, // Rotation quaternion Y
          NodeRotationZ: 0, // Rotation quaternion Z
          NodeRotationW: 1 // Rotation quaternion W
          // Add other new node properties with default values if needed
        });
        
        addEventListeners();
        setupCustomPromptListeners(); // Ensure prompt listeners are set up
        requestAnimationFrame(draw); // Initial draw
    }
    
    // #region -----------------------------------------------------------------------
    // - - - - - - - - - - - UNIT CONVERSION UTILITIES - - - - - - - - - - - - - -
    // -----------------------------------------------------------------------------
    function mmToPixels(mm) {
      return mm * scale;
    }

    function pixelsToMm(px) {
      return px / scale;
    }
    // #endregion

    // GRID DRAWING | Draws a reference grid on the canvas (currently commented out)
    // ----------------------------------------------------------------------------
    function drawGrid() {
      ctx.strokeStyle = '#e8e8e8'; // Much fainter grid color
      ctx.lineWidth = 0.3; // Thinner lines
      const gridSizeMm = 100;
      const step = mmToPixels(gridSizeMm);

      // Draw vertical grid lines across entire canvas
      const startX = Math.floor(-viewOffsetX / step) * step;
      const endX = canvas.width - viewOffsetX;
      for (let x = startX; x <= endX; x += step) {
          ctx.beginPath();
          ctx.moveTo(x, -viewOffsetY);
          ctx.lineTo(x, canvas.height - viewOffsetY);
          ctx.stroke();
      }
      
      // Draw horizontal grid lines across entire canvas
      const startY = Math.floor(-viewOffsetY / step) * step;
      const endY = canvas.height - viewOffsetY;
      for (let y = startY; y <= endY; y += step) {
          ctx.beginPath();
          ctx.moveTo(-viewOffsetX, y);
          ctx.lineTo(canvas.width - viewOffsetX, y);
          ctx.stroke();
      }
      
      // Draw origin crosshair (0,0 marker)
      const originX = mmToPixels(0);
      const originY = mmToPixels(200); // Framework visual Y position
      const crosshairSize = 20; // Size of crosshair in pixels
      
      ctx.strokeStyle = '#ff0000'; // Red color for origin marker
      ctx.lineWidth = 2;
      
      // Draw horizontal line of crosshair
      ctx.beginPath();
      ctx.moveTo(originX - crosshairSize, originY);
      ctx.lineTo(originX + crosshairSize, originY);
      ctx.stroke();
      
      // Draw vertical line of crosshair
      ctx.beginPath();
      ctx.moveTo(originX, originY - crosshairSize);
      ctx.lineTo(originX, originY + crosshairSize);
      ctx.stroke();
      
      // Add origin label
      ctx.fillStyle = '#ff0000';
      ctx.font = 'bold 12px Arial';
      ctx.textAlign = 'left';
      ctx.textBaseline = 'bottom';
      ctx.fillText('(0,0)', originX + 5, originY - 5);
    }

    // MAIN DRAW FUNCTION | Clears and redraws all elements on the canvas
    // ------------------------------------------------------------------
    function draw() {
      if (!ctx || !canvas || canvas.width <= 0 || canvas.height <= 0) {
          console.warn("draw: canvas, ctx not ready or canvas has invalid dimensions.");
          return;
      }

      // Clear click regions at start of each draw
      lengthClickRegions = [];
      panelClickRegions = [];  // <-- Clear panel click regions
      optionClickRegions = [];

      // Save context for pan transformation
      ctx.save();
      ctx.translate(viewOffsetX, viewOffsetY);

      // Clear canvas
      ctx.clearRect(-viewOffsetX, -viewOffsetY, canvas.width, canvas.height);

      drawGrid();

      // Draw Lines (Panels)
      frameworkPanelLines.forEach(line => {
          const fromNode = frameworkNodes.find(n => n.NodeUniqueId === line.from_node_id);
          const toNode = frameworkNodes.find(n => n.NodeUniqueId === line.to_node_id);

          if (fromNode && toNode) {
              // Framework visual Y position (fixed for horizontal framework display)
              const frameworkVisualY = 200; // Fixed Y position for framework display
              
              // Get node widths
              const fromNodeWidth = fromNode.NodeSizeX || 290;
              const toNodeWidth = toNode.NodeSizeX || 290;
              
              // Calculate panel position between outer edges of nodes
              // node.x now represents the LEFT EDGE of each node
              const panelStartX = fromNode.x + fromNodeWidth; // Right edge of from node
              const panelEndX = toNode.x; // Left edge of to node
              const actualPanelLength = panelEndX - panelStartX;
              
              // Ensure panel length is positive (no overlap)
              if (actualPanelLength <= 0) {
                  console.warn(`Panel ${line.PanelUniqueId} has negative or zero length: ${actualPanelLength}mm`);
                  return; // Skip drawing this panel
              }
              
              // Panel visualization (outer box) - positioned at the left edge of the panel space
              const panelXstartPx = mmToPixels(panelStartX);
              const panelYtopPx = mmToPixels(frameworkVisualY - frameworkThicknessMM / 2);
              const panelWidthPx = mmToPixels(actualPanelLength);
              const panelHeightPx = mmToPixels(frameworkThicknessMM);

              // Draw panel background with hover effect capability
              ctx.fillStyle = '#f0f8ff';  // Light blue background for panels
              ctx.fillRect(panelXstartPx, panelYtopPx, panelWidthPx, panelHeightPx);
              
              ctx.strokeStyle = lineColor;
              ctx.lineWidth = 1.5;
              ctx.strokeRect(panelXstartPx, panelYtopPx, panelWidthPx, panelHeightPx);

              // Add visual indicator for window panels
              if (line.PanelType === 'Window_Panel' || !line.PanelType) {  // Default to Window_Panel if not specified
                  // Draw small window icon or indicator
                  const iconSize = Math.min(panelWidthPx * 0.1, panelHeightPx * 0.3, 20);
                  const iconX = panelXstartPx + (panelWidthPx / 2) - (iconSize / 2);
                  const iconY = panelYtopPx + (panelHeightPx / 2) - (iconSize / 2);
                  
                  // Store panel click region ONLY for the icon area
                  panelClickRegions.push({
                      panelId: line.PanelUniqueId,
                      panelIndex: frameworkPanelLines.indexOf(line),
                      x: iconX,
                      y: iconY,
                      width: iconSize,
                      height: iconSize,
                      panelType: line.PanelType || 'Window_Panel'
                  });
                  
                  ctx.fillStyle = '#4a90e2';  // Blue for window indicator
                  ctx.fillRect(iconX, iconY, iconSize, iconSize);
                  ctx.strokeStyle = '#2c5aa0';
                  ctx.lineWidth = 1;
                  ctx.strokeRect(iconX, iconY, iconSize, iconSize);
                  
                  // Draw cross pattern for window panes
                  ctx.beginPath();
                  ctx.moveTo(iconX + iconSize/2, iconY);
                  ctx.lineTo(iconX + iconSize/2, iconY + iconSize);
                  ctx.moveTo(iconX, iconY + iconSize/2);
                  ctx.lineTo(iconX + iconSize, iconY + iconSize/2);
                  ctx.stroke();
                  
                  // Add "Click to configure" text hint
                  ctx.font = '10px Arial';
                  ctx.fillStyle = '#666';
                  ctx.textAlign = 'center';
                  ctx.textBaseline = 'top';
                  ctx.fillText('Click', iconX + iconSize/2, iconY + iconSize + 2);
              }

              // Center line visualization
              ctx.strokeStyle = lineColor;
              ctx.lineWidth = 1.5;
              ctx.beginPath();
              ctx.moveTo(panelXstartPx, mmToPixels(frameworkVisualY));
              ctx.lineTo(panelXstartPx + panelWidthPx, mmToPixels(frameworkVisualY));
              ctx.stroke();
              
              // Length input box visualization
              const inputBoxWidthMm = 70;
              const inputBoxHeightMm = 25;
              const inputBoxGapMm = 10;

              const boxXmm = panelStartX + (actualPanelLength / 2) - (inputBoxWidthMm / 2);
              const boxYmm = frameworkVisualY + (frameworkThicknessMM / 2) + inputBoxGapMm;
              
              const boxXpx = mmToPixels(boxXmm);
              const boxYpx = mmToPixels(boxYmm);
              const boxWidthPx = mmToPixels(inputBoxWidthMm);
              const boxHeightPx = mmToPixels(inputBoxHeightMm);

              ctx.fillStyle = '#f9f9f9';
              ctx.fillRect(boxXpx, boxYpx, boxWidthPx, boxHeightPx);
              ctx.strokeStyle = '#aaaaaa';
              ctx.strokeRect(boxXpx, boxYpx, boxWidthPx, boxHeightPx);

              // Draw length text
              ctx.fillStyle = nodeColor;
              ctx.font = `bold ${mmToPixels(10)}px ${getComputedStyle(document.documentElement).getPropertyValue('--FontType_ValeStandardText').trim()}`;
              ctx.textAlign = 'center';
              ctx.textBaseline = 'middle';
              ctx.fillText(line.length_mm + "mm", boxXpx + boxWidthPx / 2, boxYpx + boxHeightPx / 2);
              
              // Store click region for length input
              lengthClickRegions.push({
                  lineId: line.PanelUniqueId,
                  x: boxXpx, y: boxYpx, width: boxWidthPx, height: boxHeightPx,
                  lineIndex: frameworkPanelLines.indexOf(line)
              });
          }
      });

      // Draw Nodes
      const frameworkVisualY = 200;                                         // <-- Fixed Y position for framework display
      frameworkNodes.forEach(node => {
        // Get node type configuration for dimensions
        const nodeTypeConfig = getNodeTypeConfig(node.NodeType);            // <-- Get node type configuration
        const nodeWidthMm = nodeTypeConfig ? nodeTypeConfig.DefaultDimensions.Width_mm : 290;  // <-- Get width from config
        const nodeDepthMm = 94;                                             // <-- Fixed depth for all columns (frame thickness)
        
        // Calculate rectangle position and dimensions
        // node.x now represents the LEFT EDGE of the node, not the center
        const nodeXpx = mmToPixels(node.x);                                 // <-- Left edge position
        const nodeYpx = mmToPixels(frameworkVisualY - (nodeDepthMm / 2));   // <-- Center on framework line
        const nodeWidthPx = mmToPixels(nodeWidthMm);                        // <-- Convert width to pixels
        const nodeDepthPx = mmToPixels(nodeDepthMm);                        // <-- Convert depth to pixels
        
        // Draw node rectangle
        ctx.fillStyle = nodeColor;                                          // <-- Set fill color
        ctx.fillRect(nodeXpx, nodeYpx, nodeWidthPx, nodeDepthPx);           // <-- Draw filled rectangle
        
        // Draw node border
        ctx.strokeStyle = nodeTextColor;                                    // <-- Set border color
        ctx.lineWidth = 2;                                                  // <-- Set border width
        ctx.strokeRect(nodeXpx, nodeYpx, nodeWidthPx, nodeDepthPx);         // <-- Draw rectangle border
        
        // Draw node label (e.g., type initials) at the CENTER of the node
        ctx.fillStyle = nodeTextColor;                                      // <-- Set text color
        const fontSizePx = Math.max(8, Math.min(mmToPixels(12), 18));       // <-- Dynamic font size with limits
        ctx.font = `bold ${fontSizePx}px ${getComputedStyle(document.documentElement).getPropertyValue('--FontType_ValeStandardText').trim()}`;
        ctx.textAlign = 'center';                                           // <-- Center text horizontally
        ctx.textBaseline = 'middle';                                        // <-- Center text vertically
        const label = node.NodeType.split('_').pop().substring(0,3).toUpperCase();  // <-- Extract type label
        ctx.fillText(label, mmToPixels(node.x + nodeWidthMm/2), mmToPixels(frameworkVisualY));      // <-- Draw label at node center
      });

      // Draw Node Options if visible
      if (optionsVisible && selectedNodeForOptions) {
        drawNodeOptions(selectedNodeForOptions);
      }

      // Restore context to undo pan transformation for next frame clear
      ctx.restore();
    }
    
    // NODE TYPE OPTIONS DRAWING | Draws interactive options for a selected node
    // -------------------------------------------------------------------------
    function drawNodeOptions(node) {
      const frameworkVisualY = 200;                                         // <-- Fixed Y position for framework display
      const optionBubbleRadiusMm = 25;                                      // <-- Increased radius for better clickability
      const optionBubbleSpacingMm = 15;                                     // <-- Spacing between bubbles
      
      // Get node dimensions for proper positioning
      const nodeTypeConfig = getNodeTypeConfig(node.NodeType);             // <-- Get node type configuration
      const nodeDepthMm = 94;                                              // <-- Fixed depth for all columns (frame thickness)
      const nodeHalfDepthMm = nodeDepthMm / 2;                             // <-- Calculate half depth
      const optionsYOffsetMm = nodeHalfDepthMm + optionBubbleSpacingMm + optionBubbleRadiusMm;  // <-- Y offset from node edge

      const totalOptionsWidthMm = (optionTexts.length * (2 * optionBubbleRadiusMm)) + ((optionTexts.length - 1) * optionBubbleSpacingMm);
      // node.x now represents the LEFT EDGE, so calculate center for options positioning
      const nodeCenterX = node.x + (nodeTypeConfig ? nodeTypeConfig.DefaultDimensions.Width_mm : 290) / 2;
      let currentXmm = nodeCenterX - (totalOptionsWidthMm / 2) + optionBubbleRadiusMm;  // <-- Calculate starting X position
      const yPosMm = frameworkVisualY - optionsYOffsetMm;                   // <-- Position options above the framework line

      const optionBubbleColor = '#e0e0e0';                                  // <-- Lighter grey for options
      const optionBubbleTextColor = '#172b3a';                              // <-- Dark blue text, like nodes

      optionTexts.forEach((text, index) => {
        const xPx = mmToPixels(currentXmm);                                 // <-- Convert X position to pixels
        const yPx = mmToPixels(yPosMm);                                     // <-- Convert Y position to pixels
        const radiusPx = mmToPixels(optionBubbleRadiusMm);                  // <-- Convert radius to pixels

        // Draw bubble
        ctx.beginPath();                                                    // <-- Begin path for circle
        ctx.arc(xPx, yPx, radiusPx, 0, 2 * Math.PI);                       // <-- Draw circle
        ctx.fillStyle = optionBubbleColor;                                  // <-- Set fill color
        ctx.fill();                                                         // <-- Fill circle
        ctx.strokeStyle = nodeColor;                                        // <-- Border color same as node fill
        ctx.lineWidth = 1.5;                                                // <-- Set border width
        ctx.stroke();                                                       // <-- Draw border

        // Draw text (shortened if necessary, e.g., first word or initials)
        // For "Corner Column" -> "Corner", "290mm Column" -> "290mm", "390mm Column" -> "390mm"
        let displayText = text;                                             // <-- Initialize display text
        if (text === "Corner Column") displayText = "Corner";              // <-- Shorten corner column text
        else if (text.includes("mm Column")) displayText = text.split(" ")[0];  // <-- Extract width for column types

        const fontSizePx = Math.max(8, Math.min(mmToPixels(10), 16));       // <-- Calculate font size
        ctx.font = `bold ${fontSizePx}px ${getComputedStyle(document.documentElement).getPropertyValue('--FontType_ValeStandardText').trim()}`;
        ctx.fillStyle = optionBubbleTextColor;                              // <-- Set text color
        ctx.textAlign = 'center';                                           // <-- Center text horizontally
        ctx.textBaseline = 'middle';                                        // <-- Center text vertically
        ctx.fillText(displayText, xPx, yPx);                                // <-- Draw text

        // Store click region
        optionClickRegions.push({
          x: xPx, y: yPx, radius: radiusPx,                                 // <-- Store click region
          optionType: optionNodeTypes[index],                               // <-- Store option type
          nodeId: node.NodeUniqueId                                         // <-- Store which node these options belong to
        });

        currentXmm += (2 * optionBubbleRadiusMm) + optionBubbleSpacingMm;   // <-- Move to next option position
      });
    }

    // NODE MANAGEMENT | Functions for adding and manipulating nodes and lines
    // -----------------------------------------------------------------------
    function addNode() {
      if (frameworkNodes.length === 0) {
          // Add the first node if none exist
          const firstNodeId = "ND_" + Date.now(); // Prefix to match new ID scheme
          const firstNodeWidth = 290; // Corner column width
          frameworkNodes.push({ 
              NodeUniqueId: firstNodeId, // Updated property name
              x: 0, // Position left edge at origin - center will be calculated in coordinate transformation
              y: 0, // Framework nodes are positioned linearly along X-axis, Y=0
              NodeType: 'Column_CornerColumn', // Updated property name
              NodeName: 'Start', // Example, adjust as per your full structure
              NodeStyle: "", // Default empty style
              NodeNotes: "Starting corner column at origin", // Default notes
              NodePosX: 0, // Model position X
              NodePosY: 0, // Model position Y
              NodePosZ: 0, // Model position Z
              NodeSizeX: firstNodeWidth, // Node width in mm (corner column)
              NodeSizeY: 94, // Node depth in mm
              NodeSizeZ: 2000, // Node height in mm
              NodeHeadHeight: 2000, // Head height
              NodeUsCillHeight: 0, // Cill height
              NodeRotationX: 0, // Rotation quaternion X
              NodeRotationY: 0, // Rotation quaternion Y
              NodeRotationZ: 0, // Rotation quaternion Z
              NodeRotationW: 1 // Rotation quaternion W
              // Add other new node properties with default values if needed
          });
      } else {
          // Add a new node and a line connecting to the previous node
          const lastNode = frameworkNodes[frameworkNodes.length - 1];
          const newLineId = "PL_" + Date.now(); // Prefix for Panel Lines
          const defaultSpacingMm = 1000; // Default spacing between node centers

          const newNodeId = "ND_" + Date.now(); // Prefix for Nodes
          const newNode = {
            NodeUniqueId: newNodeId, // Updated property name
            x: lastNode.x + defaultSpacingMm, 
            y: 0, // Framework nodes are positioned linearly along X-axis, Y=0
            NodeType: 'Column_290mm', // Updated property name - use standard column for intermediate nodes
            NodeName: 'Node-' + (frameworkNodes.length + 1), // Example name
            NodeStyle: "", // Default empty style
            NodeNotes: "Intermediate framework node", // Default notes
            NodePosX: 0, // Model position X (will be calculated)
            NodePosY: 0, // Model position Y (will be calculated)
            NodePosZ: 0, // Model position Z
            NodeSizeX: 290, // Node width in mm
            NodeSizeY: 94, // Node depth in mm
            NodeSizeZ: 2000, // Node height in mm
            NodeHeadHeight: 2000, // Head height
            NodeUsCillHeight: 0, // Cill height
            NodeRotationX: 0, // Rotation quaternion X
            NodeRotationY: 0, // Rotation quaternion Y
            NodeRotationZ: 0, // Rotation quaternion Z
            NodeRotationW: 1 // Rotation quaternion W
            // Add other new node properties with default values if needed
          };
          frameworkNodes.push(newNode); // Adjusted to frameworkNodes
          
          // Calculate panel length between outer edges of nodes
          const lastNodeWidth = lastNode.NodeSizeX || 290;
          const newNodeWidth = newNode.NodeSizeX || 290;
          
          // Panel spans from right edge of last node to left edge of new node
          const lastNodeRightEdge = lastNode.x + (lastNodeWidth / 2);
          const newNodeLeftEdge = newNode.x - (newNodeWidth / 2);
          const actualPanelLength = newNodeLeftEdge - lastNodeRightEdge;
          
          frameworkPanelLines.push({ // Adjusted to frameworkPanelLines
              PanelUniqueId: newLineId, // Updated property name
              from_node_id: lastNode.NodeUniqueId, // Adjusted to NodeUniqueId
              to_node_id: newNodeId,
              length_mm: Math.max(100, actualPanelLength), // Ensure minimum panel length
              PanelType: 'Window_Panel', // Updated property name
              PanelDivisionsX: 1, // Default 1 vertical division (1 glaze bar)
              PanelDivisionsY: 1, // Default 1 horizontal division (1 glaze bar)
              PanelName: `Panel-${frameworkPanelLines.length + 1}`, // Default panel name
              PanelStyle: "", // Default empty style
              PanelNotes: "Default window panel with 1x1 glazing divisions"
              // Add other new panel line properties with default values if needed
          });
      }
      console.log("FrameworkNodes:", JSON.stringify(frameworkNodes));
      console.log("FrameworkPanelLines:", JSON.stringify(frameworkPanelLines));
      requestAnimationFrame(draw);
      
      // REAL-TIME UPDATE | Trigger automatic save after adding node
      // ---------------------------------------------------------------
      triggerRealTimeUpdate();
      // ---------------------------------------------------------------
    }

    // ZOOM FUNCTIONALITY | Handles zooming in and out of the canvas
    // ----------------------------------------------------------------
    function zoom(factor, mouseX_view_param, mouseY_view_param) {
      const rect = canvas.getBoundingClientRect();
      // Use parameters if provided (e.g., from wheel event), otherwise center of canvas
      const mouseX_view = mouseX_view_param !== undefined ? mouseX_view_param : (rect.width / 2);
      const mouseY_view = mouseY_view_param !== undefined ? mouseY_view_param : (rect.height / 2);

      // World coordinates under mouse before zoom
      const worldX_before_zoom = (mouseX_view - viewOffsetX) / scale;
      const worldY_before_zoom = (mouseY_view - viewOffsetY) / scale;

      // Apply zoom
      scale *= factor;
      scale = Math.max(0.2, Math.min(scale, 5)); // Clamp scale factor

      // Adjust viewOffset so the point under the mouse stays the same in world space
      viewOffsetX = mouseX_view - (worldX_before_zoom * scale);
      viewOffsetY = mouseY_view - (worldY_before_zoom * scale);
      
      console.log("Zoom level: ", scale, "View Offset:", viewOffsetX, viewOffsetY);
      requestAnimationFrame(draw);
    }
    
    // EVENT LISTENERS | Sets up canvas event handling for interactions
    // ----------------------------------------------------------------
    function addEventListeners() {
      if (!canvas) return;
      // Wheel event for zooming
      canvas.addEventListener('wheel', function(event) {
        event.preventDefault();
        const zoomIntensity = 1.1;
        const delta = event.deltaY < 0 ? zoomIntensity : 1 / zoomIntensity;
        // Pass mouse coordinates relative to canvas for zoom centering
        const rect = canvas.getBoundingClientRect();
        zoom(delta, event.clientX - rect.left, event.clientY - rect.top);
      });

      // Mousedown event for dragging nodes or clicking length inputs
      canvas.addEventListener('mousedown', function(event) {
          const rect = canvas.getBoundingClientRect();
          const clickXpx_view = event.clientX - rect.left; // Click X relative to canvas viewport
          const clickYpx_view = event.clientY - rect.top; // Click Y relative to canvas viewport

          // Middle mouse button for panning
          if (event.button === 1) { // Middle mouse button
              isPanning = true;
              lastPanX = event.clientX;
              lastPanY = event.clientY;
              canvas.style.cursor = 'grabbing';
              event.preventDefault();
              return; // Panning initiated, do nothing else
          }

          // If not middle mouse button, proceed with left-click logic (node interaction, etc.)
          // Transform click coordinates from view space to world space (scaled pixels)
          const clickXpx_world = clickXpx_view - viewOffsetX;
          const clickYpx_world = clickYpx_view - viewOffsetY;
          
          mouseDownPoint = { x: clickXpx_world, y: clickYpx_world }; // Store world-space mousedown point

          // Check for clicks on node options first
          if (optionsVisible && selectedNodeForOptions) {
              for (let i = 0; i < optionClickRegions.length; i++) {
                  const region = optionClickRegions[i];
                  // region.x, region.y are world pixel coordinates
                  const dist = Math.sqrt(Math.pow(clickXpx_world - region.x, 2) + Math.pow(clickYpx_world - region.y, 2));
                  if (dist < region.radius) {
                      const targetNode = frameworkNodes.find(n => n.NodeUniqueId === region.nodeId);
                      if (targetNode) {
                          targetNode.NodeType = region.optionType;
                          console.log(`Node ${targetNode.NodeUniqueId} type changed to ${region.optionType}`);
                      }
                      optionsVisible = false;
                      selectedNodeForOptions = null;
                      potentialDragTarget = null;
                      requestAnimationFrame(draw);
                      return; // Option click handled
                  }
              }
          }

          // Check for clicks on length input regions
          for (const region of lengthClickRegions) {
              // region.x, region.y are world pixel coordinates
              if (clickXpx_world >= region.x && clickXpx_world <= region.x + region.width &&
                  clickYpx_world >= region.y && clickYpx_world <= region.y + region.height) {
                  handleLengthInput(region.lineIndex);
                  return; // Click handled, no need to check for node dragging
              }
          }
          
          // Check for node dragging if no length input was clicked
          // Convert world pixel click to world mm for node hit detection
          const mouseXmm = pixelsToMm(clickXpx_world);                      // <-- Convert click X to mm
          const mouseYmm = pixelsToMm(clickYpx_world);                      // <-- Convert click Y to mm

          let clickedOnNode = null;                                         // <-- Initialize clicked node
          for (let i = frameworkNodes.length - 1; i >= 0; i--) {           // <-- Check nodes in reverse order
              const node = frameworkNodes[i];                              // <-- Get current node
              
              // Get node type configuration for dimensions
              const nodeTypeConfig = getNodeTypeConfig(node.NodeType);     // <-- Get node type configuration
              const nodeWidthMm = nodeTypeConfig ? nodeTypeConfig.DefaultDimensions.Width_mm : 290;  // <-- Get width from config
              const nodeDepthMm = 94;                                      // <-- Fixed depth for all columns (frame thickness)
              
              // Calculate rectangle bounds for hit detection
              // node.x now represents the LEFT EDGE of the node
              const nodeLeftMm = node.x;                                    // <-- Left edge
              const nodeRightMm = node.x + nodeWidthMm;                     // <-- Right edge
              const nodeTopMm = 200 - (nodeDepthMm / 2);                   // <-- Calculate top edge (frameworkVisualY - half depth)
              const nodeBottomMm = 200 + (nodeDepthMm / 2);                // <-- Calculate bottom edge (frameworkVisualY + half depth)
              
              // Check if click is within rectangle bounds
              if (mouseXmm >= nodeLeftMm && mouseXmm <= nodeRightMm &&     // <-- Check horizontal bounds
                  mouseYmm >= nodeTopMm && mouseYmm <= nodeBottomMm) {     // <-- Check vertical bounds
                  clickedOnNode = node;                                     // <-- Set clicked node
                  break;                                                    // <-- Exit loop when node found
              }
          }

          if (clickedOnNode) {
              if (optionsVisible && selectedNodeForOptions === clickedOnNode) {
                  // Clicked same node whose options are visible: toggle off
                  optionsVisible = false;
                  selectedNodeForOptions = null;
                  potentialDragTarget = null; // Clear potential drag as it was a toggle-off click
              } else {
                  // Clicked a node, show its options
                  selectedNodeForOptions = clickedOnNode;
                  optionsVisible = true;
                  potentialDragTarget = clickedOnNode; // This node might be dragged
              }
              isDragging = false; // Not dragging yet, just a click/option toggle
              requestAnimationFrame(draw);
              return; // Node click handled (either for options or setting up potential drag)
          }
          
          // If clicked on empty canvas space, hide options
          if (optionsVisible) {
              optionsVisible = false;
              selectedNodeForOptions = null;
          }
          potentialDragTarget = null; // Clear potential drag if clicked on empty space
          requestAnimationFrame(draw);
      });

      // Mousemove event for dragging
      canvas.addEventListener('mousemove', function(event) {
          if (isPanning) {
              const dx = event.clientX - lastPanX;
              const dy = event.clientY - lastPanY;
              viewOffsetX += dx;
              viewOffsetY += dy;
              lastPanX = event.clientX;
              lastPanY = event.clientY;
              requestAnimationFrame(draw);
              return; // Panning handled, do nothing else
          }

          // Check if hovering over panel icons for cursor change
          const rect = canvas.getBoundingClientRect();
          const mouseX_view = event.clientX - rect.left;
          const mouseY_view = event.clientY - rect.top;
          const mouseX_world = mouseX_view - viewOffsetX;
          const mouseY_world = mouseY_view - viewOffsetY;
          
          let hoveringOverPanel = false;
          for (let region of panelClickRegions) {
              if (isPointInPanelRegion(mouseX_world, mouseY_world, region)) {
                  hoveringOverPanel = true;
                  break;
              }
          }
          
          // Set cursor based on what we're hovering over
          if (!isDragging && !isPanning) {
              if (hoveringOverPanel) {
                  canvas.style.cursor = 'pointer';
              } else {
                  canvas.style.cursor = 'default';
              }
          }

          // Node dragging logic (only if not panning)
          if (potentialDragTarget && !isDragging) { // Mouse down on a node, check if drag started
              const rect = canvas.getBoundingClientRect();
              // Current mouse in view space
              const currentMouseXpx_view = event.clientX - rect.left;
              const currentMouseYpx_view = event.clientY - rect.top;
              // mouseDownPoint is already in world space pixels
              const distX = currentMouseXpx_view - (mouseDownPoint.x + viewOffsetX); // Compare view-space distance
              const distY = currentMouseYpx_view - (mouseDownPoint.y + viewOffsetY); // Compare view-space distance

              const dragThreshold = 5; // Pixels to move before it's considered a drag

              if (Math.sqrt(distX * distX + distY * distY) > dragThreshold) {
                  isDragging = true;
                  dragTarget = potentialDragTarget;
                  // Calculate offset from node center to actual mousedown point in mm
                  // mouseDownPoint is in world pixels, convert to mm. dragTarget.x/y are in mm.
                  offsetX = pixelsToMm(mouseDownPoint.x) - dragTarget.x;
                  offsetY = pixelsToMm(mouseDownPoint.y) - dragTarget.y;
                  
                  optionsVisible = false; // Hide options when dragging starts
                  selectedNodeForOptions = null; 
                  canvas.style.cursor = 'grabbing';
              }
          }

          if (isDragging && dragTarget) {
              const rect = canvas.getBoundingClientRect();
              // Mouse position in view space
              const mouseX_view = event.clientX - rect.left;
              const mouseY_view = event.clientY - rect.top;
              
              // Convert to world space pixels
              const mouseX_world_px = mouseX_view - viewOffsetX;
              // const mouseY_world_px = mouseY_view - viewOffsetY; // Y-dragging currently disabled

              // Convert world space pixels to world space mm for node position update
              dragTarget.x = pixelsToMm(mouseX_world_px) - offsetX; 
              // dragTarget.y = pixelsToMm(mouseY_world_px) - offsetY; // Uncomment if y-dragging is needed
              
              updateLineLengthsFromNodeMove(dragTarget);
              requestAnimationFrame(draw);
          }
      });

      // Mouseup event to stop dragging
      canvas.addEventListener('mouseup', function(event) {
          if (event.button === 1 && isPanning) { // Middle mouse button release
              isPanning = false;
              // Determine cursor based on whether a draggable item is under mouse
              // For simplicity, set to 'grab' or 'default'. A more precise check could be done.
              canvas.style.cursor = 'grab'; // Or check if over a node: 'grab', else 'default'
              return; // Panning stopped.
          }

          // Existing left-click mouseup logic
          if (isDragging) {
              updateLineLengthsFromNodeMove(dragTarget); // Final update
              canvas.style.cursor = 'grab'; // Or check if over a node: 'grab', else 'default'
          }
          // If it was just a click on a node without dragging, options are already handled by mousedown.
          // Reset dragging state variables
          isDragging = false;
          dragTarget = null;
          potentialDragTarget = null;
          mouseDownPoint = null;
          // Do not hide options here, mousedown handles visibility toggle or empty space click.
          requestAnimationFrame(draw); // Redraw to reflect final state
      });

      // Mouseleave event to also stop dragging if mouse exits canvas
       canvas.addEventListener('mouseleave', function() {
          if (isDragging) {
              // updateLineLengthsFromNodeMove(dragTarget); // Optional: update on mouse leave
              isDragging = false;
              dragTarget = null;
              potentialDragTarget = null;
              mouseDownPoint = null;
              canvas.style.cursor = 'default';
              requestAnimationFrame(draw); // Redraw to reflect any state changes
          }
          if (isPanning) { // Also stop panning if mouse leaves canvas with middle button down
              isPanning = false;
              canvas.style.cursor = 'default'; // Or 'grab' if that's the general state
              // No redraw needed unless viewOffset changed, which it doesn't on mouseleave for panning
          }
      });

      // Update canvas click handler to include panel clicks
      canvas.addEventListener('click', (e) => {
          if (isDragging) return; // Don't process clicks during drag operations

          const rect = canvas.getBoundingClientRect();
          const x = e.clientX - rect.left - viewOffsetX;
          const y = e.clientY - rect.top - viewOffsetY;

          // Check for panel clicks first (higher priority)
          for (let region of panelClickRegions) {
              if (isPointInPanelRegion(x, y, region)) {
                  console.log(`Panel clicked: ${region.panelId} (${region.panelType})`);
                  
                  // Only handle window panels for configuration
                  if (region.panelType === 'Window_Panel') {
                      handlePanelClick(region.panelId, region.panelIndex);
                      return; // Exit early to prevent other click handlers
                  } else {
                      showSaveStatusMessage(`Panel type "${region.panelType}" not configurable yet`, false);
                      return;
                  }
              }
          }

          // Check for length input clicks
          for (let region of lengthClickRegions) {
              if (x >= region.x && x <= region.x + region.width &&
                  y >= region.y && y <= region.y + region.height) {
                  handleLengthInput(region.lineIndex);
                  return;
              }
          }

          // ... existing click handling for nodes and options ...
      });
    }

    // #region -----------------------------------------------------------------------
    // - - - - - - - - - - - CUSTOM PROMPT HANDLING - - - - - - - - - - - - - - -
    // -----------------------------------------------------------------------------
    function handleLengthInput(lineIndex) {
        const line = frameworkPanelLines[lineIndex]; // Adjusted to frameworkPanelLines
        if (!line) {
            console.error("handleLengthInput: Line not found for index", lineIndex);
            return;
        }
        currentLineEditContext = { lineIndex: lineIndex, originalLength: line.length_mm }; // Keep this for length-specific context
        showCustomPrompt(
            `Enter new length for panel (mm):\n(Currently ${line.length_mm}mm)`,
            line.length_mm,
            'number',
            (newLengthStr) => { // This is the onSaveCallback for lengths
                const parsedLength = parseFloat(newLengthStr);
                if (!isNaN(parsedLength) && parsedLength > 0) {
                    const lineToUpdate = frameworkPanelLines[currentLineEditContext.lineIndex];
                    lineToUpdate.length_mm = Math.round(parsedLength);
                    recalculateNodePositionsFromLine(currentLineEditContext.lineIndex);
                    requestAnimationFrame(draw);
                    hideCustomPrompt();
                    
                    // REAL-TIME UPDATE | Trigger automatic save after manual length change
                    // ---------------------------------------------------------------
                    triggerRealTimeUpdate();
                    // ---------------------------------------------------------------
                } else {
                    alert("Invalid length. Please enter a positive number.");
                }
            }
        );
    }

    function showCustomPrompt(message, defaultValue, inputType = 'text', onSaveCallback) {
        const promptOverlay = document.getElementById('custom-prompt-overlay');
        const promptMessage = document.getElementById('custom-prompt-message');
        const promptInput = document.getElementById('custom-prompt-input');
        if (!promptOverlay || !promptMessage || !promptInput) {
            console.error("Custom prompt elements not found!");
            return;
        }
        promptMessage.innerHTML = message.replace(/\n/g, '<br>');
        promptInput.value = defaultValue;
        promptInput.type = inputType; // Set input type dynamically
        currentPromptSaveCallback = onSaveCallback; // Store the specific save callback

        promptOverlay.style.display = 'flex';
        promptInput.focus();
        promptInput.select();
    }

    function hideCustomPrompt() {
        const promptOverlay = document.getElementById('custom-prompt-overlay');
        if (promptOverlay) promptOverlay.style.display = 'none';
        currentLineEditContext = null; // Clear length-specific context
        currentPromptSaveCallback = null; // Clear the generic save callback
    }

        // FUNCTIONS | Show Save Status Message
        // ----------------------------------------------------------------
        function showSaveStatusMessage(message, isSuccess) {
            let statusDiv = document.getElementById('saveStatusMessage');
            if (!statusDiv) {
            statusDiv = document.createElement('div');
            statusDiv.id = 'saveStatusMessage';
            // Apply basic styling; more advanced styling can be done in CSS
            statusDiv.style.position = 'fixed';
            statusDiv.style.top = '80px';
            statusDiv.style.left = '50%';
            statusDiv.style.transform = 'translateX(-50%)';
            statusDiv.style.padding = '10px 20px';
            statusDiv.style.borderRadius = '5px';
            statusDiv.style.color = 'white';
            statusDiv.style.zIndex = '10000'; // Ensure it's on top
            statusDiv.style.opacity = '0';
            statusDiv.style.transition = 'opacity 0.5s ease-in-out';
            document.body.appendChild(statusDiv);
            }

            statusDiv.textContent = message;
            statusDiv.style.backgroundColor = isSuccess ? 'green' : 'red';

            // Fade in
            setTimeout(() => {
            statusDiv.style.opacity = '1';
            }, 10); // Short delay to ensure transition triggers

            // Fade out after 3 seconds
            setTimeout(() => {
            statusDiv.style.opacity = '0';
            // Optional: remove the element after fade out
            // setTimeout(() => {
            //   if (statusDiv.parentNode) {
            //     statusDiv.parentNode.removeChild(statusDiv);
            //   }
            // }, 500); // Match transition duration
            }, 3000);
        }
        // ----------------------------------------------------------------

    function setupCustomPromptListeners() {
      const saveButton = document.getElementById('custom-prompt-save');
      const cancelButton = document.getElementById('custom-prompt-cancel');
      const inputField = document.getElementById('custom-prompt-input');

      if (!saveButton || !cancelButton || !inputField) {
          console.error("Custom prompt button/input elements not found for listeners!");
          return;
      }

      saveButton.addEventListener('click', () => {
          if (typeof currentPromptSaveCallback === 'function') {
              currentPromptSaveCallback(inputField.value);
              // hideCustomPrompt() should be called by the callback if save is successful
          } else {
              // Fallback or error if no callback is defined (should not happen if showCustomPrompt is used correctly)
              console.warn('Custom prompt save clicked, but no save callback was defined.');
              hideCustomPrompt(); // Hide it anyway
          }
      });

      cancelButton.addEventListener('click', () => {
          hideCustomPrompt();
      });

      inputField.addEventListener('keypress', function(event) {
          if (event.key === 'Enter') {
              event.preventDefault(); // Prevent form submission if wrapped in a form
              saveButton.click(); // Trigger save action
          }
      });
    }
    // #endregion

    // DATA CONSISTENCY | Functions to update model data after interactions
    // --------------------------------------------------------------------
    function updateLineLengthsFromNodeMove(movedNode) {
        frameworkPanelLines.forEach(line => {
            const fromNode = frameworkNodes.find(n => n.NodeUniqueId === line.from_node_id);
            const toNode = frameworkNodes.find(n => n.NodeUniqueId === line.to_node_id);
            if (!fromNode || !toNode) return;

            // Only update if the moved node is part of this line segment
            if (line.from_node_id === movedNode.NodeUniqueId || line.to_node_id === movedNode.NodeUniqueId) {
                // Calculate panel length between outer edges of nodes
                const fromNodeWidth = fromNode.NodeSizeX || 290;
                const toNodeWidth = toNode.NodeSizeX || 290;
                
                // Panel spans from right edge of from node to left edge of to node
                const fromNodeRightEdge = fromNode.x + (fromNodeWidth / 2);
                const toNodeLeftEdge = toNode.x - (toNodeWidth / 2);
                const actualPanelLength = toNodeLeftEdge - fromNodeRightEdge;
                
                line.length_mm = Math.round(Math.max(100, actualPanelLength)); // Ensure minimum length
            }
        });
        
        // After updating lengths, we might need to reposition subsequent nodes if the layout is strictly sequential.
        // This is important if dragging a node should "push" or "pull" other nodes.
        const lineStartingFromMovedNode = frameworkPanelLines.find(l => l.from_node_id === movedNode.NodeUniqueId);
        if (lineStartingFromMovedNode) {
            recalculateNodePositionsFromLine(frameworkPanelLines.indexOf(lineStartingFromMovedNode));
        }
        // If a node is moved, the line ending at it has its length changed.
        // The line starting from it might also need its connected node (to_node) re-evaluated.
        const lineEndingAtMovedNode = frameworkPanelLines.find(l => l.to_node_id === movedNode.NodeUniqueId);
        if (lineEndingAtMovedNode) {
            // The length of lineEndingAtMovedNode is updated. Its from_node is static.
            // We need to ensure nodes AFTER this segment are correctly positioned.
            // If lineEndingAtMovedNode's to_node (the movedNode) is also a from_node for another line,
            // then that next line's to_node needs to be updated.
            // This is handled by the lineStartingFromMovedNode check if the moved node is a 'from' node.
            // If the moved node is a 'to' node, we may need to trigger recalc for the line it *starts* if any.
            // The current logic seems to try to cover this.
            recalculateNodePositionsFromLine(frameworkPanelLines.indexOf(lineEndingAtMovedNode));
        }
        
        // REAL-TIME UPDATE | Trigger automatic save after node movement
        // ---------------------------------------------------------------
        triggerRealTimeUpdate();
        // ---------------------------------------------------------------
    }
    
    function recalculateNodePositionsFromLine(changedLineIndex) {
        if (changedLineIndex < 0 || changedLineIndex >= frameworkPanelLines.length) return;

        // Start from the first node at origin (left edge at x=0)
        let currentX = 0; // First node's left edge at origin
        
        // First, ensure the first node is properly positioned
        if (frameworkNodes.length > 0) {
            const firstNode = frameworkNodes[0];
            const firstNodeWidth = firstNode.NodeSizeX || 290;
            // First node's left edge should be at 0, so center is at half width
            firstNode.x = 0; // Left edge position (coordinate transformation will handle center positioning)
            currentX = firstNodeWidth; // Right edge of first node
        }
        
        // Now position all subsequent nodes based on panel lengths
        for (let i = 0; i < frameworkPanelLines.length; i++) {
            const line = frameworkPanelLines[i];
            const fromNode = frameworkNodes.find(n => n.NodeUniqueId === line.from_node_id);
            const toNode = frameworkNodes.find(n => n.NodeUniqueId === line.to_node_id);
            
            if (fromNode && toNode) {
                const toNodeWidth = toNode.NodeSizeX || 290;
                
                // Position the to_node so its left edge is at currentX + panel length
                toNode.x = currentX + line.length_mm; // Left edge position
                
                // Update current position to right edge of this node
                currentX = toNode.x + toNodeWidth;
            }
        }
        
        // REAL-TIME UPDATE | Trigger automatic save after position recalculation
        // ---------------------------------------------------------------
        triggerRealTimeUpdate();
        // ---------------------------------------------------------------
    }

    // REAL-TIME UPDATE | Function to trigger automatic saves
    // ---------------------------------------------------------------
    function triggerRealTimeUpdate() {
        // Only trigger real-time updates if we have an active component
        if (activeFrameworkComponentID && window.sketchup && window.sketchup.save_data_to_model) {
            console.log("Framework Configurator: Triggering real-time update...");
            
            // Debounce the updates to avoid too many rapid saves
            if (window.realTimeUpdateTimeout) {
                clearTimeout(window.realTimeUpdateTimeout);
            }
            
            window.realTimeUpdateTimeout = setTimeout(() => {
                // Get the AssemblyID from Ruby if available
                if (window.sketchup && window.sketchup.get_assembly_id_for_component) {
                    window.sketchup.get_assembly_id_for_component({ 
                        entityID: activeFrameworkComponentID,
                        callback: "app.updateMetadataAndSaveRealTime"
                    });
                }
            }, 250); // 250ms debounce delay
        }
    }
    // ---------------------------------------------------------------

    // DOM INITIALIZATION | Ensures init is called after DOM is ready
    // ---------------------------------------------------------------
    if (document.readyState === 'loading') { // Loading hasn't finished yet
      document.addEventListener('DOMContentLoaded', init);
    } else {  // `DOMContentLoaded` has already fired
      init();
    }

    // #region =======================================================================
    // - - - - - - - - - - - PUBLIC API & EXPORTS  - - - - - - - - - - - - - - - -
    // ===============================================================================
    return {
      // ACTIONS
      addNode: addNode,
      zoomIn: () => zoom(1.2),
      zoomOut: () => zoom(1 / 1.2),
      showSaveStatusMessage: showSaveStatusMessage, // Expose the new function
      
      // DATA ACCESS
      getFrameworkData: () => {
        return {
          frameworkMetadata: frameworkMetadata,
          frameworkNodes: frameworkNodes,
          frameworkPanelLines: frameworkPanelLines
        };
      },
      
      // DATA PERSISTENCE (Communication with Ruby)
      saveConfiguration: () => {
        console.log("Attempting to save configuration...");
        console.log("JS saveConfiguration: activeFrameworkComponentID is:", activeFrameworkComponentID);
        
        // Check if there's an active component ID
        if (!activeFrameworkComponentID) {
          // Instead of saving to global dictionary, prompt to create a component
          if (confirm("No active component selected. Would you like to create a new framework component to save this data?")) {
            app.handleCreateNewFrameworkAssembly();
            return; // Exit as the create new framework flow will handle the save
          } else {
            app.showSaveStatusMessage('Save cancelled - must have a component selected', false);
            return; // User cancelled, do not proceed with save
          }
        }
        
        // If we're here, we have an activeFrameworkComponentID
        // Get the AssemblyID from Ruby if available
        if (window.sketchup && window.sketchup.get_assembly_id_for_component) {
          window.sketchup.get_assembly_id_for_component({ 
            entityID: activeFrameworkComponentID,
            callback: "app.updateMetadataAndSave"
          });
          return; // Exit and wait for callback
        } else {
          app.showSaveStatusMessage('Error: Unable to get component information', false);
          console.error("sketchup.get_assembly_id_for_component is not available.");
        }
      },
      
      // New callback method to update metadata with correct AssemblyID and then save
      updateMetadataAndSave: (assemblyID) => {
        console.log(`JavaScript: Received AssemblyID from Ruby: ${assemblyID}`);
        
        if (assemblyID && frameworkMetadata && frameworkMetadata.length > 0) {
          // Update the metadata with the correct AssemblyID
          frameworkMetadata[0].FrameworkUniqueId = assemblyID;
          console.log(`JavaScript: Updated frameworkMetadata[0].FrameworkUniqueId to: ${frameworkMetadata[0].FrameworkUniqueId}`);
        }
        
        // Now perform the save with updated metadata
        const dataToSave = {
          frameworkMetadata: frameworkMetadata,
          frameworkNodes: frameworkNodes,
          frameworkPanelLines: frameworkPanelLines
        };
        console.log("JS updateMetadataAndSave: Sending this data to Ruby's save_data_to_model:", JSON.stringify(dataToSave, null, 2));
        
        if (window.sketchup && window.sketchup.save_data_to_model) {
          window.sketchup.save_data_to_model(dataToSave);
        } else {
          console.error("sketchup.save_data_to_model is not available.");
        }
      },

      // REAL-TIME UPDATE | Callback for real-time saves (silent, no status message)
      // ---------------------------------------------------------------
      updateMetadataAndSaveRealTime: (assemblyID) => {
        console.log(`JavaScript: Real-time update - Received AssemblyID from Ruby: ${assemblyID}`);
        
        if (assemblyID && frameworkMetadata && frameworkMetadata.length > 0) {
          // Update the metadata with the correct AssemblyID
          frameworkMetadata[0].FrameworkUniqueId = assemblyID;
          console.log(`JavaScript: Real-time update - Updated frameworkMetadata[0].FrameworkUniqueId to: ${frameworkMetadata[0].FrameworkUniqueId}`);
        }
        
        // Now perform the save with updated metadata (silent save for real-time)
        const dataToSave = {
          frameworkMetadata: frameworkMetadata,
          frameworkNodes: frameworkNodes,
          frameworkPanelLines: frameworkPanelLines
        };
        console.log("JS updateMetadataAndSaveRealTime: Sending real-time data to Ruby's save_data_to_model");
        
        if (window.sketchup && window.sketchup.save_data_to_model) {
          window.sketchup.save_data_to_model(dataToSave);
        } else {
          console.error("sketchup.save_data_to_model is not available for real-time update.");
        }
      },
      // ---------------------------------------------------------------

      requestLoadConfiguration: () => {
        console.log("Requesting to load configuration...");
        
        if (window.sketchup && activeFrameworkComponentID) {
          // If a component is currently selected and active, use the component-specific loader
          console.log(`Loading data for component ID: ${activeFrameworkComponentID}`);
          window.sketchup.request_load_data_for_component({ entityID: activeFrameworkComponentID });
        } else {
          // Instead of loading from global data, prompt the user
          if (confirm("No component is selected. Would you like to create a new framework component?")) {
            app.handleCreateNewFrameworkAssembly();
          } else {
            app.showSaveStatusMessage('Load cancelled - must have a component selected', false);
          }
        }
      },
      // Called by Ruby to load data into the JS app
      loadData: (loadedData, entityIDFromLoad = null) => {
          console.log("JavaScript: loadData called with data:", loadedData ? "Data Present" : "No Data", "EntityID from load:", entityIDFromLoad);

          if (entityIDFromLoad && loadedData) { // If this load was for a specific component and successful
              activeFrameworkComponentID = entityIDFromLoad;
              console.log(`JavaScript: activeFrameworkComponentID confirmed/set to ${activeFrameworkComponentID} by component-specific load.`);
          }
          // Note: activeFrameworkComponentID is nulled by sketchupSelectionChanged(null) for deselections.
          // We don't null it here unless it's an explicit clear operation passed via loadedData.

          if (!loadedData) {
              console.warn("app.loadData: No data received or data is null/undefined.");
              // Initialize with default empty structure if nothing valid is passed
              frameworkMetadata = [{ FrameworkUniqueId: "VFW_Empty", FrameworkName: "EmptyFramework", FrameworkNotes: "Loaded empty", FrameworkLength: 0, FrameworkWidth: 0, FrameworkHeight: 0 }];
              frameworkNodes = [];
              frameworkPanelLines = [];
          } else {
              frameworkMetadata = loadedData.frameworkMetadata || [{ FrameworkUniqueId: "VFW_Default", FrameworkName: "DefaultFramework", FrameworkNotes: "Default on partial load", FrameworkLength: 0, FrameworkWidth: 0, FrameworkHeight: 0 }];
              frameworkNodes = loadedData.frameworkNodes || [];
              frameworkPanelLines = loadedData.frameworkPanelLines || [];
              console.log(`JavaScript: Loaded data - Metadata count: ${frameworkMetadata.length}, Nodes: ${frameworkNodes.length}, Panel Lines: ${frameworkPanelLines.length}`);
          }

          // Reset pan and zoom on load
          scale = 1.0; 
          viewOffsetX = 0;
          viewOffsetY = 0;

          // Update the Current Framework Element Name display
          const frameworkNameElement = document.getElementById('currentFrameworkElementName');
          if (frameworkNameElement) {
              let displayName = "N/A"; // Default display name
              if (loadedData && loadedData.sketchup_instance_name) {
                  displayName = loadedData.sketchup_instance_name;
                  console.log(`JavaScript: Using SketchUp instance name for display: "${displayName}"`);
              } else if (frameworkMetadata && frameworkMetadata.length > 0 && frameworkMetadata[0].FrameworkName) {
                  displayName = frameworkMetadata[0].FrameworkName;
                  console.log(`JavaScript: Falling back to FrameworkName from metadata for display: "${displayName}"`);
              }

              const newNameText = "Current Framework Element : " + displayName;
              frameworkNameElement.textContent = newNameText;
              console.log(`JavaScript: Updated framework name display to: "${newNameText}"`);

              // Show a loading success message
              if (typeof app.showSaveStatusMessage === 'function') {
                  // Use the most relevant name for the success message
                  const messageName = (loadedData && loadedData.sketchup_instance_name) ? loadedData.sketchup_instance_name :
                                      (frameworkMetadata && frameworkMetadata.length > 0 && frameworkMetadata[0].FrameworkName) ? frameworkMetadata[0].FrameworkName :
                                      "Data";
                  app.showSaveStatusMessage(`Successfully loaded "${messageName}"`, true);
              }
          } else {
              console.error("JavaScript: Could not find currentFrameworkElementName element to update!");
          }

          // Reset pan and zoom before recalculating and drawing
          scale = 1.0;
          viewOffsetX = 0;
          viewOffsetY = 0;

          if (frameworkPanelLines.length > 0 && frameworkNodes.length > 0) { // Guard: ensure nodes exist before recalc
              recalculateNodePositionsFromLine(0); 
          }
          requestAnimationFrame(draw);
          console.log("JavaScript: Data loading complete, canvas redrawn");
      },

      // NEW METHOD: Clear canvas and reset state
      clearCanvas: () => {
        console.log("JavaScript: Clearing canvas and resetting state");
        activeFrameworkComponentID = null;
        frameworkMetadata = [{ FrameworkUniqueId: "VFW_Empty", FrameworkName: "N/A (Canvas Cleared)", FrameworkNotes: "Canvas cleared by user", FrameworkLength: 0, FrameworkWidth: 0, FrameworkHeight: 0 }];
        frameworkNodes = [];
        frameworkPanelLines = [];
        
        // Reset pan and zoom
        scale = 1.0;
        viewOffsetX = 0;
        viewOffsetY = 0;
        
        // Update the Current Framework Element Name display
        const frameworkNameElement = document.getElementById('currentFrameworkElementName');
        if (frameworkNameElement) {
          frameworkNameElement.textContent = "Current Framework Element : N/A (Canvas Cleared)";
        }
        
        // Tell SketchUp to clear the selection if that callback is available
        if (window.sketchup && window.sketchup.clear_selection) {
          window.sketchup.clear_selection();
        }
        
        // Show confirmation message
        if (typeof app.showSaveStatusMessage === 'function') {
          app.showSaveStatusMessage('Canvas cleared', true);
        }
        
        requestAnimationFrame(draw);
      },

      handleCreateNewFrameworkAssembly: () => {
        // Check if there's anything on the canvas to save
        if (frameworkNodes.length === 0) {
          // If canvas is empty, prompt the user to add content first
          alert("Please add at least one element to the framework before creating a new assembly.");
          return;
        }
        
        showCustomPrompt(
          "Enter a name for the new framework assembly:",
          "MyFrameworkAssembly",
          'text',
          (assemblyName) => { // This is the onSaveCallback for creating a new framework
            if (assemblyName && assemblyName.trim() !== "") {
              if (window.sketchup && window.sketchup.handle_create_new_framework_assembly) {
                console.log(`JavaScript: Requesting creation of new framework: ${assemblyName}`);
                // Show loading message
                app.showSaveStatusMessage(`Creating new framework "${assemblyName}"...`, true);
                
                // Instead of just sending the name, send the full framework data with the name
                const dataToSave = {
                  name: assemblyName,
                  frameworkMetadata: [{
                    FrameworkName: assemblyName,
                    FrameworkNotes: "Created from canvas",
                    FrameworkLength: 0,
                    FrameworkWidth: 0,
                    FrameworkHeight: 0
                  }],
                  frameworkNodes: frameworkNodes,
                  frameworkPanelLines: frameworkPanelLines
                };
                
                // Pass the full data to Ruby
                window.sketchup.handle_create_new_framework_assembly(dataToSave);
                hideCustomPrompt(); // Hide prompt after attempting to create
              } else {
                console.error("sketchup.handle_create_new_framework_assembly is not available.");
                alert("Error: SketchUp communication for creating framework is not available.");
              }
            } else {
              alert("Framework name cannot be empty.");
              // Do not hide the prompt, let user correct or cancel
            }
          }
        );
      },

      sketchupSelectionChanged: (entityID) => {
        console.log(`JavaScript: sketchupSelectionChanged called with entityID: ${entityID}`);
        const frameworkNameElement = document.getElementById('currentFrameworkElementName');
        
        // Add debug to check if we have the framework name element
        if (!frameworkNameElement) {
          console.error("JavaScript: currentFrameworkElementName element not found in DOM!");
        } else {
          console.log(`JavaScript: Current framework name before update: "${frameworkNameElement.textContent}"`);
        }

        if (entityID) {
          if (activeFrameworkComponentID !== entityID) {
            console.log(`JavaScript: Component selection changed from ${activeFrameworkComponentID} to ${entityID}`);
            // Tentatively set for immediate UI feedback, but rely on loadData to confirm with entityIDFromLoad
            activeFrameworkComponentID = entityID; 
            if (frameworkNameElement) {
              frameworkNameElement.textContent = `Loading Framework ID: ${entityID}...`; 
              console.log(`JavaScript: Updated UI to loading state for component ${entityID}`);
            }
            console.log(`JavaScript: Active framework component ID tentatively set to: ${entityID}. Requesting data load.`);
            if (window.sketchup && window.sketchup.request_load_data_for_component) {
              console.log(`JavaScript: Calling request_load_data_for_component for entityID: ${activeFrameworkComponentID}`);
              // Pass entityID so it can be returned to loadData
              window.sketchup.request_load_data_for_component({ entityID: activeFrameworkComponentID, originalEntityIDForJS: activeFrameworkComponentID });
            } else {
              console.error("JavaScript: sketchup.request_load_data_for_component is not available.");
              if (frameworkNameElement) {
                frameworkNameElement.textContent = "Error: Cannot load component data.";
                console.log("JavaScript: Updated UI to error state - cannot load component data");
              }
              // Ensure metadata reflects error or N/A state
              frameworkMetadata = [{ FrameworkUniqueId: "VFW_Error", FrameworkName: "N/A (Error Loading)", FrameworkNotes: "Error loading component data", FrameworkLength: 0, FrameworkWidth: 0, FrameworkHeight: 0 }];
              app.loadData(null); // Call loadData to refresh UI to N/A state
            }
          } else {
            console.log(`JavaScript: Same component ID ${entityID} re-confirmed. No new load triggered.`);
          }
        } else { // entityID is null or undefined (nothing selected or selection cleared)
          console.log(`JavaScript: Selection cleared or non-framework component selected (entityID is null)`);
          if (activeFrameworkComponentID !== null || (frameworkMetadata.length > 0 && frameworkMetadata[0].FrameworkName !== "N/A (No component selected)")) {
            console.log(`JavaScript: Need to reset UI - previous activeFrameworkComponentID: ${activeFrameworkComponentID}`);
            activeFrameworkComponentID = null; // Clear active ID
            // Reset local data to a clean "nothing selected" state
            frameworkMetadata = [{ FrameworkUniqueId: "VFW_None", FrameworkName: "N/A (No component selected)", FrameworkNotes: "No component selected", FrameworkLength: 0, FrameworkWidth: 0, FrameworkHeight: 0 }];
            frameworkNodes = [];
            frameworkPanelLines = [];
            
            // Reset pan and zoom state as well
            scale = 1.0;
            viewOffsetX = 0;
            viewOffsetY = 0;

            if (frameworkNameElement) {
              frameworkNameElement.textContent = "Current Framework Element : N/A (No component selected)";
              console.log("JavaScript: Reset UI to 'No component selected' state");
            }
            requestAnimationFrame(draw); 
            console.log("JavaScript: Active framework component cleared. UI reset to N/A.");
          } else {
            console.log("JavaScript: Already in 'no selection' state, no UI update needed");
          }
        }
      },

      // CANVAS UTILITIES
      resizeCanvasMethod: _performCanvasResize, // Expose internal resize for specific calls
      forceResizeCanvas: function() { 
          console.log("app.forceResizeCanvas() called");
          // Ensure view offset is maintained or reset appropriately during a forced resize.
          // For now, it will be maintained as _performCanvasResize only redraws.
          // If a reset of pan/zoom is desired on forceResize, add it here.
          if (canvasContainer && canvas) { 
              this.resizeCanvasMethod(); 
          } else {
              console.warn("forceResizeCanvas called but canvas/container not ready.");
          }
      },

      // #region -----------------------------------------------------------------------
      // - - - - - - - - - - - PANEL INTERACTION HANDLING - - - - - - - - - - - - - -
      // -----------------------------------------------------------------------------

      // PANEL CLICK REGIONS | Store clickable panel regions for interaction
      panelClickRegions: [],

      // FUNCTION | Handle Panel Click for Configuration
      // ---------------------------------------------------------------
      handlePanelClick: handlePanelClick,

      // FUNCTION | Check if Point is Inside Panel Click Region
      // ---------------------------------------------------------------
      isPointInPanelRegion: isPointInPanelRegion,

      // #endregion
      
      // NODE TYPES CONFIGURATION | Callback for receiving config from Ruby
      // ---------------------------------------------------------------
      setNodeTypesConfig: setNodeTypesConfig,
      
      // FUNCTION | Refresh Option Arrays after Config Load
      // ---------------------------------------------------------------
      refreshOptionArrays: () => {
        const optionArrays = generateNodeOptionArrays();
        optionTexts = optionArrays.optionTexts;
        optionNodeTypes = optionArrays.optionNodeTypes;
        console.log("Refreshed option arrays with", optionTexts.length, "node types");
      }

      // #endregion
    };

})(); 
// #endregion
