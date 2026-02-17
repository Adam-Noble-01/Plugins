# Copyright 2013, Trimble Navigation Limited

# This software is provided as an example of using the Ruby interface
# to SketchUp.

# Permission to use, copy, modify, and distribute this software for 
# any purpose and without fee is hereby granted, provided that the above
# copyright notice appear in all copies.

# THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
#-----------------------------------------------------------------------------
# Name        :   Grid Tool 1.0
# Description :   A tool to create grids.
# Menu Item   :   Tools->Grid
# Context Menu:   None
# Date        :   4/2/2013
# Type        :   Tool
#-----------------------------------------------------------------------------

# Creates a grid

require 'sketchup.rb'
require 'su_grid/parametric.rb'

#=============================================================================

module Sketchup::Samples::Grid

class Grid < Sketchup::Samples::Parametric

def create_entities(data, container)

    dx = data["dx"].to_l
    dy = data["dy"].to_l
    nx = data["nx"].to_i
    ny = data["ny"].to_i
    
    # create the vertical lines
    pt = Geom::Point3d.new ORIGIN
    pt2 = pt + [0, dy*ny, 0]
    offset = [dx, 0, 0]
    for i in 0..nx do
        container.add_cline pt, pt2, "..."
        pt += offset
        pt2 += offset
    end
    
    # create the horizontal lines
    pt.set!(ORIGIN)
    pt2 = pt + [dx*nx, 0, 0]
    offset = [0, dy, 0]
    for i in 0..ny do
        container.add_cline pt, pt2, "..."
        pt += offset
        pt2 += offset
    end
    
end

def default_parameters
    defaults = {"dx" => 8.feet, "dy" => 8.feet, "nx" => 4, "ny" => 4}
    defaults
end

end # class Grid

#=============================================================================

class GridTool

@@dx = 1.feet
@@dy = 1.feet

def initialize
    @ip = Sketchup::InputPoint.new
    @ip1 = Sketchup::InputPoint.new
    reset
end

def reset
    @pts = []
    @state = 0
    @ip1.clear
    @drawn = false
    Sketchup::set_status_text "Click for start point"
    @shift_down_time = Time.now
    @nx = 0
    @ny = 0
end

def activate
    self.reset
    @drawn = false
    Sketchup::set_status_text "Spacing", SB_VCB_LABEL
    Sketchup::set_status_text "#{@@dx}", SB_VCB_VALUE
end

def deactivate(view)
    view.invalidate if @drawn
end

def set_current_point(x, y, view)
    if( !@ip.pick(view, x, y, @ip1) )
        return false
    end
    need_draw = true
    
    # Set the tooltip that will be displayed
    view.tooltip = @ip.tooltip
        
    # Compute points
    case @state
    when 0
        @pts[0] = @ip.position
        @pts[4] = @pts[0]
        need_draw = @ip.display? || @drawn
    when 1
        @pts[1] = @ip.position
    when 2
        pt1 = @ip.position
        pt2 = pt1.project_to_line @pts
        vec = pt1 - pt2
        @pts[2] = @pts[1] + vec
        @pts[3] = @pts[0] + vec
    end

    view.invalidate if need_draw
end

def onMouseMove(flags, x, y, view)
    self.set_current_point(x, y, view)
end

def create_grid
    # check for zero size
    if( @nx > 0 && @ny > 0 )
        data = {}
        data["nx"] = @nx
        data["ny"] = @ny
        data["dx"] = @@dx
        data["dy"] = @@dy
        
        # compute the transformation to move it to the right location
        origin = @pts[0]
        xaxis = @pts[1] - @pts[0]
        yaxis = @pts[3] - @pts[0]
        zaxis = xaxis.cross(yaxis)
        t = Geom::Transformation.axes(origin, xaxis, yaxis, zaxis)
        
        # Create the grid
        grid = Grid.new data, t
        
    end
end

def increment_state
    @state += 1
    case @state
    when 1
        @ip1.copy! @ip
        Sketchup::set_status_text "Click for second point"
    when 2
        @ip1.clear
        @pts[2] = @pts[1]
        @pts[3] = @pts[0]
        Sketchup::set_status_text "Click for third point"
    when 3
        self.create_grid
    end
end

def onLButtonDown(flags, x, y, view)
    self.set_current_point(x, y, view)
    self.increment_state
    view.lock_inference
end

def onLButtonUp(flags, x, y, view)
    Sketchup.active_model.select_tool nil if @state == 3
end

def onCancel(flag, view)
    view.invalidate if @drawn
    self.reset
end

# This is called when the user types a value into the VCB
def onUserText(text, view)
    #TODO: Add parsing for different values fo dx and dy
    # The user can enter values for dx and dy
    # The user may type in something that we can't parse as a length
    # so we set up some exception handling to trap that
    begin
        value = text.to_l
    rescue
        # Error parsing the text
        UI.beep
        value = nil
        Sketchup::set_status_text "", SB_VCB_VALUE
    end
    return if !value
    
    if( value > 0.0 )
        @@dx = value
        @@dy = value
        view.invalidate
    end
end

def getExtents
    bb = Geom::BoundingBox.new
    case @state
    when 0
        # We are getting the first point
        if( @ip.valid? && @ip.display? )
            bb.add @ip.position
        end
    when 1
        bb.add @pts[0]
        bb.add @pts[1]
    when 2
        bb.add @pts
    end
    bb
end

def draw_grid(view)

    # round the length to an even number of grid squares
    xvec = @pts[1] - @pts[0]
    width = xvec.length
    @nx = (width / @@dx).to_i
    width = @nx * @@dx
    xvec.length = width if( width > 0 )

    if( @state > 1 )
        yvec = @pts[3] - @pts[0]
        height = yvec.length
        @ny = (height / @@dy).to_i
        height = @ny * @@dy
        yvec.length = height if( height > 0 )
    else
        @ny = 0
    end

    # Check for special cases where there is not really anything to draw
    if( @ny < 1 )
        return if @nx < 1
        
        # Draw a single line to avoid confusion in the case where
        # we are just starting to drag out the grid
        view.draw(GL_LINE_STRIP, @pts[0], @pts[1])
        
        # Draw tick marks
        offset = xvec.clone
        viewdir = view.camera.direction
        vec = offset.cross viewdir
        return if vec.length == 0.0
        vec.length = view.pixels_to_model 6, @pts[0]
        offset.length = @@dx
        pt1 = @pts[0]
        pt2 = pt1 + vec
        view.line_stipple = 0
        for i in 0..@nx do
            view.draw(GL_LINE_STRIP, pt1, pt2)
            pt1 += offset
            pt2 += offset
        end
        
        return
        
    elsif( @nx < 1 )
        view.draw(GL_LINE_STRIP, @pts[0], @pts[3])
        return
    end
    
    view.drawing_color = "black"
    
    # draw the vertical lines
    pt1 = @pts[0]
    pt2 = pt1 + yvec
    offset = xvec.clone
    offset.length = @@dx
    for i in 0..@nx do
        view.draw(GL_LINE_STRIP, pt1, pt2)
        pt1 += offset
        pt2 += offset
    end
    
    # draw the horizontal lines
    pt1 = @pts[0]
    pt2 = pt1 + xvec
    offset = yvec
    offset.length = @@dy
    for i in 0..@ny do
        view.draw(GL_LINE_STRIP, pt1, pt2)
        pt1 += offset
        pt2 += offset
    end
    
    true
end

def draw(view)
    @drawn = false
    
    # Show the current input point
    if( @ip.valid? && @ip.display? )
        @ip.draw(view)
        @drawn = true
    end

    # show the rectangle
    view.line_stipple = "..."
    if( @state == 1 )
        # just draw a line from the start to the end point
        view.set_color_from_line(@ip1, @ip)
        #inference_locked = view.inference_locked?
        #view.line_width = 3 if inference_locked
        @drawn = draw_grid(view)
        #view.line_width = 1 if inference_locked
    elsif( @state > 1 )
        @drawn = draw_grid(view)
    end
    view.line_stipple = 0
end

def onKeyDown(key, rpt, flags, view)
    if( key == CONSTRAIN_MODIFIER_KEY )
        @shift_down_time = Time.now
        
        # if we already have an inference lock, then unlock it
        if( view.inference_locked? )
            view.lock_inference
        elsif( @state == 1 )
            view.lock_inference @ip, @ip1
        else
            view.lock_inference @ip
        end
    end
end

def onKeyUp(key, rpt, flags, view)
    if( key == CONSTRAIN_MODIFIER_KEY &&
        view.inference_locked? &&
        (Time.now - @shift_down_time) > 0.5 )
        view.lock_inference
    end
end

end # class GridTool

#=============================================================================

if (not $grid_loaded)
    command = UI::Command.new("Grid") {
        Sketchup.active_model.select_tool(Sketchup::Samples::Grid::GridTool.new)
    }
    command.status_bar_text = "Create 2-dimensional grids."

    menu = UI.menu("Tools")
    menu.add_separator
    menu.add_item(command)
    $grid_loaded = true
end

end # module Sketchup::Samples::Grid
