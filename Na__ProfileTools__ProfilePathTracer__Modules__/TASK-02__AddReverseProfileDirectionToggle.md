# OBJECTIVE : Add a reverse profile direction toggle to the plugin
@SketchUp-2026__LocalPluginsFolder/Na__ProfileTools__ProfilePathTracer__Modules__ 

## Current Problem
- There is no easy way to reverse the profile as the profile direction is based on the winding order of the paths which cant easily be understoon by SketchUp users without specialised knowledge.

## Solution 
- Add a new reverse profile direction toggle to the plugin.
- Add the button left of the generate profile button in the Apply Profile Tab.

## Workings 
- Make a specific function for this 
- I've tested the method in sketchup manually and it works so dont reinvent the wheel trying to prove me wrong etc or iomplementing a different method. follow these steps:

Action: User presses the reverse profile direction toggle button
1. Before tracing a profile flip the profiles rotation to 180 degrees. (This is already possible with the existing code)
2. The profile is then traced as normal.
3. Select the profile group created and flip by scaling the group by -1 on the Z axis.