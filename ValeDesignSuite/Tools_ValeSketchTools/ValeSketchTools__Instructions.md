TOOL | Window Panel Sketcher
-----------------------------------------------------------------------------
FILE       :  ValeSketchTools_WindowPanelSketcher.rb
NAMESPACE  :  ValeDesignSuite::SketchTools::WindowPanelSketcher
MODULE     :  WindowPanelSketcher
AUTHOR     :  Adam Noble - Noble Architecture
PURPOSE    :  SketchUp tool for creating window panel configurations from "Sketches"    
CREATED    :  09-Jul-2025

YOUR ROLE - Expert SketchUp RubyScript Dev with 20 years experience.
Constraints : All Code Must Be Skletchup Ruby Api 2025+ So Double Check All Methods And Functions Never Assume Anything.


DESCRIPTION
- The tool is designed to take a simple plan and will create the necessary offsets and glazed bar divisions.
- The tool infers the glazing bar amounts and positions from the users selection.
- Uses a "Low Poly" reference panel to create the high poly window panel. 
- The low poly remains in the scene and is not deleted, instead added to a helper tag the tag switched off showing the high poly rendition. 
- The tool acts dynamically meaning any updates to the low poly reference will be reflected in the high poly window panel version.
-----------------------------------------------------------------------------
DESIGN GOAL
- Create a tool that allows for rapid creation of window panels from a simple sketch plan.
- Allows user to work on only a basic set of rectangles and lines but the generates a High Poly Window Panel.
- Allows dynamic editing of the original low poly reference and the high poly window panel will update automatically.
- This allows for rapid iteration and testing of different panel configurations, without getting bogged down in offsets and panel divisions etc.
-----------------------------------------------------------------------------
DYNAMIC MANAGEMENT OF LOW POLY WINDOW PANELS
- Persistance is very important, if the low poly window panels are adjusted, the high poly window panels must be adjusted to match.
- We can achieve this by using even observers as used with some on of the other scripts in Vale Design Suite tools.
- This ties each individual panel to a high poly window panel.
- If two groups are specifically named the same the observer will be triggered and all panels with that name updated.
 - This is useful in some cases as we can have a single observer for all identical panels.
 - This is also useful because orangeries tend to have identical panels. or usually a mix of identical and different panels.
 - Ensuring the system can handle identical panels and edit them all at once will save a lot of time
 - So if the groups name is identical, edit them all, if name is unique any changes made to the low poly reference will only effect that panel.
- The Users selection must be grouped and the group instance name must be set to `01_10_LowPolyWindowPanel__01` , `01_10_LowPolyWindowPanel__02` etc.
- A helper tag `01_10_Helper__LowPolyWindowPanels` is to be created and objects placed in it.
-----------------------------------------------------------------------------
Step 01 |  Selection 
*(See Attached Image Image For Visual Reference)*
- User Selects "Panel" 
- Consisting Of  N. Faces.
- Each Face represents a pane
- Division are calulcations are based on this
- Selection is grouped and named `01_10_LowPolyWindowPanel__01` , `01_10_LowPolyWindowPanel__02` etc.
- The helper tag `01_10_Helper__LowPolyWindowPanels` if it does not exist in the model
- This low poly reference group is created and placed in to the helper tag. 
- The helper tag is switched off (if not already) which reveals the high poly version of the window panel.
- The High poly version has a corresponding name `01_10_HighPolyWindowPanel__01` , `01_10_HighPolyWindowPanel__02` etc.
  - Note "High" Simply replaces "Low" in the name, this ties the two renditions of the same panel together. 
  - Note this is is critical for the observer to work correctly other wise the dynamic system will not work. 
Important Note:
- My reference image shows the input reference selection contains 12 faces, this is the abstracted version of the panel.
 - This means as shown in the the reference image there would be 2 Vertical Glazed Bars and 3 Horizontal Glazed Bars.
 - This means as shown in the the reference image there would be 12 glass panes between the glazed bars and frame elements once offset.
- The Edges effectively represent the glazing bars and the faces represent the glass. 
- Note it does not include any of the frame elements thickness or glazed bars thicknesses at this stage.
-----------------------------------------------------------------------------
Step 02 |  High Poly Window Panel Processing - Offset Standardised Frame Dimensions
*(See Attached Image Image For Visual Reference)*
- Vale Garden Houses use a standardised timber profile system so the will be constants declared at the top of the script.
  - Frame section profile sizes whilst coded as constants may be changed on a rare occasions, hence ease of access in the code near the top.
- Offsets Left Window Style 65mm
- Offsets Left Window Style 65mm
- Offsets Top Head Rail 95mm
- Offsets Bottom Base Rail 75mm
- This sets the bounds of the inner frame and the region occupied by the glazed bars and glass panes.
-----------------------------------------------------------------------------
Step 03 |  High Poly Window Panel Processing - Create The Glazed Bar Divisions
*(See Attached Image Image For Visual Reference)*
S- Offset Glazed Bars To Suit the low poly ref.
- Glazed Bars all 26mm
  - Add a Constant at the top of the script for the glazed bar thickness, it changes on a rare occasion.
  - (+13mm) + (-13mm) from each C/L  (Or to match the vales from the constant /2 etc)
- Glazed bar lines are based on the reference however must allow for the offset of the frames.
  - This is why the offset step was conducted first before this operation creating the actual inner rectangle for setting out the glazed bar center lines.
- When the new Glazed bar centre lines are created the are then offset out to create the actual glazed bar lines.
- The glazed panels are now the new individual rectangles between the glazed bars once set out and offset.
-----------------------------------------------------------------------------
Step 04 |  Group Each Glazed Panel
*(See Attached Image Image For Visual Reference)*
- Select each inner rectangle
- Group the face and 4 edges
- Name group <ParentName__GlazingPanel-01>
  - Continue Numbering to suit, in this case up to 12
- Apply Glazing Material to each Group
  -  `20_31__Glass__StandardWindowGlass`
    - R = 218
    - G = 229
    - B = 240 
- These are all nested within the main group we already created.
-----------------------------------------------------------------------------
Step 05 |  Create The Main Panel Frame Group
*(See Attached Image Image For Visual Reference)*
- Select the remainder & group.
- Name group <ParentName__WindowPanelFramework>
  - Apply framework material to group.
  -  `85_10__DefaultOrangeryPaint__OffWhite
      - R = 214
      - G = 210
      - B = 199  
- This is nested within the main group we already created
-----------------------------------------------------------------------------
!!CRITICAL COORDINATE SYSTEM NOTES!!
- See the first image of the supplied image showing how axis should be set in each group. (Defining object local space axis)
- Set the X, Y, Z Here in each group
(LOCAL COORDINATE SYSTEM!!)
- +Z (Blue Axis)  =  Height
- +X (Red Axis )  =  Width











---


# TOOL | Window Panel Sketcher
# -----------------------------------------------------------------------------
#
# FILE       :  ValeSketchTools_WindowPanelSketcher.rb
# NAMESPACE  :  ValeDesignSuite::SketchTools::WindowPanelSketcher
# MODULE     :  WindowPanelSketcher
# AUTHOR     :  Adam Noble - Noble Architecture
# PURPOSE    :  SketchUp tool for creating window panel configurations from "Sketches"    
# CREATED    :  09-Jul-2025
#
# DESCRIPTION
# - The tool is designed to take a simple plan and will create the necessary offsets and glazed bar divisions.
# - The tool infers the glazing bar amounts and positions from the users selection.
# - Uses a "Low Poly" reference panel to create the high poly window panel. 
# - The low poly remains in the scene and is not deleted, instead added to a helper tag the tag switched off showing the high poly rendition. 
# - The tool acts dynamically meaning any updates to the low poly reference will be reflected in the high poly window panel version.
#
# -----------------------------------------------------------------------------
# DESIGN GOAL
# - Create a tool that allows for rapid creation of window panels from a simple sketch plan.
# - Allows user to work on only a basic set of rectangles and lines but the generates a High Poly Window Panel.
# - Allows dynamic editing of the original low poly reference and the high poly window panel will update automatically.
# - This allows for rapid iteration and testing of different panel configurations, without getting bogged down in offsets and panel divisions etc.
#
# -----------------------------------------------------------------------------
#
# DYNAMIC MANAGEMENT OF LOW POLY WINDOW PANELS
# - Persistance is very important, if the low poly window panels are adjusted, the high poly window panels must be adjusted to match.
# - We can achieve this by using even observers as used with some on of the other scripts in Vale Design Suite tools.
# - This ties each individual panel to a high poly window panel.
# - If two groups are specifically named the same the observer will be triggered and all panels with that name updated.
#  - This is useful in some cases as we can have a single observer for all identical panels.
#  - This is also useful because orangeries tend to have identical panels. or usually a mix of identical and different panels.
#  - Ensuring the system can handle identical panels and edit them all at once will save a lot of time
#  - So if the groups name is identical, edit them all, if name is unique any changes made to the low poly reference will only effect that panel.
# - The Users selection must be grouped and the group instance name must be set to `01_10_LowPolyWindowPanel__01` , `01_10_LowPolyWindowPanel__02` etc.
# - A helper tag `01_10_Helper__LowPolyWindowPanels` is to be created and objects placed in it.
#
# -----------------------------------------------------------------------------
# Step 01 |  Selection 
# *(See Attached Image Image For Visual Reference)*
# - User Selects "Panel" 
# - Consisting Of  N. Faces.
# - Each Face represents a pane
# - Division are calulcations are based on this
# - Selection is grouped and named `01_10_LowPolyWindowPanel__01` , `01_10_LowPolyWindowPanel__02` etc.
# - The helper tag `01_10_Helper__LowPolyWindowPanels` if it does not exist in the model
# - This low poly reference group is created and placed in to the helper tag. 
# - The helper tag is switched off (if not already) which reveals the high poly version of the window panel.
# - The High poly version has a corresponding name `01_10_HighPolyWindowPanel__01` , `01_10_HighPolyWindowPanel__02` etc.
#   - Note "High" Simply replaces "Low" in the name, this ties the two renditions of the same panel together. 
#   - Note this is is critical for the observer to work correctly other wise the dynamic system will not work. 
# Important Note:
# - My reference image shows the input reference selection contains 12 faces, this is the abstracted version of the panel.
#  - This means as shown in the the reference image there would be 2 Vertical Glazed Bars and 3 Horizontal Glazed Bars.
#  - This means as shown in the the reference image there would be 12 glass panes between the glazed bars and frame elements once offset.
# - The Edges effectively represent the glazing bars and the faces represent the glass. 
# - Note it does not include any of the frame elements thickness or glazed bars thicknesses at this stage.
#
# -----------------------------------------------------------------------------
# Step 02 |  High Poly Window Panel Processing - Offset Standardised Frame Dimensions
# *(See Attached Image Image For Visual Reference)*
# - Vale Garden Houses use a standardised timber profile system so the will be constants declared at the top of the script.
#   - Frame section profile sizes whilst coded as constants may be changed on a rare occasions, hence ease of access in the code near the top.
# - Offsets Left Window Style 65mm
# - Offsets Left Window Style 65mm
# - Offsets Top Head Rail 95mm
# - Offsets Bottom Base Rail 75mm
# - This sets the bounds of the inner frame and the region occupied by the glazed bars and glass panes.
#
# -----------------------------------------------------------------------------
# Step 03 |  High Poly Window Panel Processing - Create The Glazed Bar Divisions
# *(See Attached Image Image For Visual Reference)*
# S- Offset Glazed Bars To Suit the low poly ref.
# - Glazed Bars all 26mm
#   - Add a Constant at the top of the script for the glazed bar thickness, it changes on a rare occasion.
#   - (+13mm) + (-13mm) from each C/L  (Or to match the vales from the constant /2 etc)
# - Glazed bar lines are based on the reference however must allow for the offset of the frames.
#   - This is why the offset step was conducted first before this operation creating the actual inner rectangle for setting out the glazed bar center lines.
# - When the new Glazed bar centre lines are created the are then offset out to create the actual glazed bar lines.
# - The glazed panels are now the new individual rectangles between the glazed bars once set out and offset.
#
# -----------------------------------------------------------------------------
# Step 04 |  Group Each Glazed Panel
# *(See Attached Image Image For Visual Reference)*
# - Select each inner rectangle
# - Group the face and 4 edges
# - Name group <ParentName__GlazingPanel-01>
#   - Continue Numbering to suit, in this case up to 12
# - Apply Glazing Material to each Group
#   -  `20_31__Glass__StandardWindowGlass`
#     - R = 218
#     - G = 229
#     - B = 240 
# - These are all nested within the main group we already created.
#
# -----------------------------------------------------------------------------
# Step 05 |  Create The Main Panel Frame Group
# *(See Attached Image Image For Visual Reference)*
# - Select the remainder & group.
# - Name group <ParentName__WindowPanelFramework>
#   - Apply framework material to group.
#   -  `85_10__DefaultOrangeryPaint__OffWhite
#       - R = 214
#       - G = 210
#       - B = 199  
# - This is nested within the main group we already created.

# -----------------------------------------------------------------------------
# !!CRITICAL COORDINATE SYSTEM NOTES!!
# - See the first image of the supplied image showing how axis should be set in each group. (Defining object local space axis)
# - Set the X, Y, Z Here in each group
# (LOCAL COORDINATE SYSTEM!!)
# - +Z (Blue Axis)  =  Height
# - +X (Red Axis )  =  Width