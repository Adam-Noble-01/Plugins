=begin
  Copyright 2014-2017 (c), TIG 
  [Based on Didier Bur's original ideas in 'extrudelinetool']
  All Rights Reserved.
  THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED 
  WARRANTIES,INCLUDING,WITHOUT LIMITATION,THE IMPLIED WARRANTIES OF 
  MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
###
    extrudeEdgesByVector.rb
###
    A Tool that Extrudes Selected Edges along a Picked Vector, 
    similar to Sketchup's PushPull for a Face, BUT it extrudes only the 
    Edges, AND these Edges need not be connected to each other or 
    coplanar, and the Vector can be in any direction.
###
Usage:  
    Select any number of Edges, Curves etc to be Extruded - 
    Anything else in the Selection, such as Faces, will be ignored.
        
    Run the Tool from Plugins > 'Extrude Edges by Vector'.
    or click on 'Extrude Edges by Vector' in the 'Extrusion Tools' 
    Toolbar.
    [Activate this Toolbar from View > Toolbars if it's not loaded]
    
    Now follow the prompts on the VCB.
    Firstly: Pick any Point that will be the 'Start of the Vector' - 
     it need NOT be connected to any of the selected Edges.
    Secondly: Pick any Point that will be the 'End of the Vector' - 
     again this can be anywhere.
    As you move the mouse to Pick this Second Point you will see a
    'ghost' outline of the Edges that will be extruded.
    
Result:
    When you Pick this Second Point the Edges will extrude and make 
    new Edges and Faces.
    Any Smoothed Edges in the selection will give Smoothed Edges to 
    the new Faces.
    Any Curves in the selection will also give Smoothed Edges to the new 
    Faces.
    The new Faces are consistently Oriented.
    The extrusion's new Geometry - Edges and Faces - and a copy of 
    the original selected Edges is made inside a Group.
    
Next:
    The newly extruded Edges are now 'Selected' [highlighted] and you 
    can continue using the tool to Pick the Points for a new Vector and
    make additional extrusions based on these.
    These additional extrusions will also be created within of the same 
    Group.
    Note that once several extrusions have been made inside the 
    Group some newly extruded Edges could merge with existing ones 
    and thereby be 'split' and might be lost from the highlighted set.  
    If this happens Exit and re-select the Edges and use the Tool again.
    To Exit the Tool press <Esc> or Choose another Tool e.g. 'Select'.
    OR double-click the mouse.
    On Exit there are two dialogs offering Yes/No Options-
    Firstly: 'Reverse the Extrusion's Faces'
     - if you answer 'Yes' then all of the Faces are Reversed.
    Secondly: 'Explode the Extrusion's Group' - 
     if you answer 'Yes' then the newly made Geometry will merge into 
     the main Geometry.
    The Extrusions 'undo' backwards, in individual steps...
    
Donations:
    Are welcome [by PayPal], please use 'TIGdonations.htm' in the 
    ../Plugins/TIGtools/ folder.
    
Version:
    1.0 20100114 First release.
    1.1 20100120 FR lingvo file updated [thanks to Pilou].
    1.2 20100121 Typo preventing Plugin Menu item working corrected.
    1.3 20100123 FR lingvo file upadted again by Pilou.
    1.4 20100124 Menu typo fixed.
    1.5 20100216 All extrusion-tools now in one in Plugins sub-menu.
    1.6 20100222 Tooltips etc now deBabelized properly.
    1.7 20101027 You can now end extrusion with a 'double-click'.
    2.0 20130520 Becomes part of ExtrudeTools Extension.
=end
#-----------------------------------------------------------------------------

module ExtrudeTools
###
toolname="extrudeEdgesByVector"
cmd=UI::Command.new(db("Extrude Edges by Vector")){Sketchup.active_model.select_tool(ExtrudeTools::ExtrudeEdgesByVector.new())}
cmd.tooltip=db("Extrude Edges by Vector")
cmd.status_bar_text="..."
cmd.small_icon=File.join(EXTOOLS, "#{toolname}16x16.png")
cmd.large_icon=File.join(EXTOOLS, "#{toolname}24x24.png")
SUBMENU.add_item(cmd)
TOOLBAR.add_item(cmd)
###
class ExtrudeEdgesByVector

include ExtrudeTools

def orient_connected_faces(the_face, in_faces=[])
    abort=true
    the_face.edges.each{|e|
      if e.faces[1]
        abort=false
        break
      end#if
    }
    return nil if abort
    @connected_faces=[]
	the_face.all_connected.each{|e|
	  if e.class==Sketchup::Face
		e.edges.each{|edge|
		  if edge.faces[1]
            @connected_faces << e
            break
          end#if
        }
	  end#if
	}
	@awaiting_faces=in_faces#@connected_faces
    @processed_faces=[the_face]
    @done_faces=[]
    msg=""#(db("Orienting Faces"))
    ###
    timeout=@connected_faces.length
    timer=0
	while @awaiting_faces[0]
      msg=msg+"."
	  @processed_faces.each{|face|
        if not @done_faces.include?(face)
	      Sketchup::set_status_text(msg,SB_PROMPT)
		  @face=face
          face_flip()
        end#if
	  }
      timer+=1
      @awaiting_faces=[] if timer==timeout
    end#while
	Sketchup::set_status_text((""),SB_PROMPT)
 end#def
 def face_flip()
    @face.edges.each{|edge|
      rev1=edge.reversed_in?(@face)
      @common_faces=edge.faces-[@face]
      @common_faces.each{|face|
	    rev2=edge.reversed_in?(face)
        face.reverse! if @awaiting_faces.include?(face) and rev1==rev2
	    @awaiting_faces=@awaiting_faces-[face]
	    @processed_faces<<face
	  }
    }
    @awaiting_faces=@awaiting_faces-[@face]
    @done_faces<<@face
end#def

def getExtents
    bbox=Sketchup.active_model.bounds
    bbox.add(@ip.position)if @ip and @ip.valid?
    bbox.add(@ip1.position)if @ip1 and @ip1.valid?
    bbox.add(@ip2.position)if @ip2 and @ip2.valid?
    return bbox
end

def initialize()
    @toolname="extrudeEdgesByVector"
	@ip1 = nil
    @ip2 = nil
    @xdown = 0
    @ydown = 0
end

  def db(string)
	locale=Sketchup.get_locale.upcase
	path=File.join(EXTOOLS, @toolname+locale+".lingvo")
	if File.exist?(path)
		deBabelizer(string,path)
	else
		return string
	end
  end#def

def activate
    @ip1 = Sketchup::InputPoint.new
    @ip2 = Sketchup::InputPoint.new
    @ip = Sketchup::InputPoint.new
    @drawn = false
    @group=nil ########################
		@model=Sketchup.active_model
    self.reset(nil)
end

def deactivate(view)
    if @group and @group.valid?
      ### ### fix smoothness display glitch
      Sketchup::set_status_text((db("Extrude Edges by Vector"))+(db(": Reverse Extrusion's Faces ?")), SB_PROMPT)
      if UI.messagebox((db("Extrude Edges by Vector"))+(db(": Reverse Extrusion's Faces ?")),MB_YESNO,"")==6 ### 6=YES 7=NO
        @group.entities.each{|e|e.reverse! if e.class==Sketchup::Face}
        gp=Sketchup.active_model.active_entities.add_group(@group)
        @group.explode
        @group=gp
        begin
          view.refresh
        rescue
          ### <v8
        end
      end#if
      ###
      Sketchup::set_status_text((db("Extrude Edges by Vector"))+(db(": Explode Extrusion's Group ?")), SB_PROMPT)
      if UI.messagebox((db("Extrude Edges by Vector"))+(db(": Explode Extrusion's Group ?")),MB_YESNO,"")==6 ### 6=YES 7=NO
        @group.explode
      end#if
    end#if
    @group=nil #######################
    view.invalidate if @drawn
    Sketchup::set_status_text((""), SB_PROMPT)
    return nil
end

def onLButtonDoubleClick(flags, x, y, view)
  self.deactivate(view)
end

def onMouseMove(flags, x, y, view)
    if( @state == 0 )
       
        @ip.pick view, x, y
        if( @ip != @ip1 )
            view.invalidate if( @ip.display? or @ip1.display? )
            @ip1.copy! @ip
            view.tooltip = @ip1.tooltip
        end
    else
        @ip2.pick view, x, y, @ip1
        view.tooltip = @ip2.tooltip if( @ip2.valid? )
        view.invalidate
        
        if( @ip2.valid? )
            length = @ip1.position.distance(@ip2.position)
            Sketchup::set_status_text(length.to_s, SB_VCB_VALUE)
        end
        
        if(x-@xdown).abs > 10 || (y-@ydown).abs > 10
            @dragging = true
        end
    end
end

def onLButtonDown(flags, x, y, view)
    if( @state == 0 )
        @ip1.pick view, x, y
        if( @ip1.valid? )
            @state = 1
            Sketchup::set_status_text((db("Extrude Edges by Vector: Pick Second Point of Vector...")), SB_PROMPT)
            @xdown = x
            @ydown = y
        end
    else
        if( @ip2.valid? )
            self.create_geometry(@ip1.position, @ip2.position,view)
            self.reset(view)
        end
    end
    view.lock_inference
end

# The onLButtonUp method is called when the user releases the left mouse button.
def onLButtonUp(flags, x, y, view)
    if( @dragging && @ip2.valid? )
        self.create_geometry(@ip1.position, @ip2.position,view)
        self.reset(view)
    end
end

def onKeyDown(key, repeat, flags, view)
    if( key == CONSTRAIN_MODIFIER_KEY && repeat == 1 )
        @shift_down_time = Time.now
        if( view.inference_locked? )
            view.lock_inference
        elsif( @state == 0 && @ip1.valid? )
            view.lock_inference @ip1
        elsif( @state == 1 && @ip2.valid? )
            view.lock_inference @ip2, @ip1
        end
    end
end

def onKeyUp(key, repeat, flags, view)
    if( key == CONSTRAIN_MODIFIER_KEY &&
        view.inference_locked? &&
        (Time.now - @shift_down_time) > 0.5 )
        view.lock_inference
    end
end


def onUserText(text, view)
    return if not @state == 1
    return if not @ip2.valid?
    begin
        value = text.to_l
    rescue # Error parsing the text
        UI.beep
        UI.messagebox((db("Extrude Edges by Vector: Cannot Convert "))+text+(db(" to a Length.")))
        value = nil
        ###Sketchup::set_status_text("", SB_VCB_VALUE)
    end
    return if !value
    pt1 = @ip1.position
    vec = @ip2.position - pt1
    if( vec.length == 0.0 )
        return
    end
    vec.length = value
    #pt2 = pt1 + vec
    pt2=pt1.offset vec
    #puts(pt1.distance pt2).to_s
    self.create_geometry(pt1, pt2, view)
    self.reset(view)
end


def draw(view)
    if @ip1.valid?
        if @ip1.display?
            @ip1.draw(view)
            @drawn = true
            view.draw_points @ip1.position, 8, 1, "black"
        end
        if @ip2.valid?
            @ip2.draw(view) if @ip2.display?
            view.set_color_from_line(@ip1, @ip2)
            self.draw_geometry(@ip1.position, @ip2.position, view)
            @drawn = true
        end
    end
    view.draw_points @ip2.position, 8, 1, "black"
end

# onCancel is called when the user hits the escape key
def onCancel(flag, view)
    self.deactivate(view)
    Sketchup.send_action("selectSelectionTool:")
    return nil
end


# Reset the tool back to its initial state
def reset(view)

    model=Sketchup.active_model
    
    @ss=[]
    model.selection.each{|e|@ss<< e if e.class == Sketchup::Edge}
    if @ss.empty? 
      UI.messagebox(db("Extrude Edges by Vector: No Edge in Selection."))
      self.deactivate(view)
      Sketchup.send_action("selectSelectionTool:")
      return nil
    end#if

    @state = 0
    
    Sketchup::set_status_text((db("Extrude Edges by Vector: Pick First Point of Vector...")), SB_PROMPT)
    
    @ip1.clear
    @ip2.clear
    
    if( view )
        view.tooltip = nil
        view.invalidate if @drawn
    end
    
    @drawn = false
    @dragging = false
end

# Create new geometry when the user has selected two points.
def create_geometry(p1, p2, view)

model = Sketchup.active_model

if Sketchup.version.to_i > 6
	model.start_operation((db("Extrude Edges by Vector")), true)
  ### 'false' is best to see results as UI/msgboxes...
else
	model.start_operation((db("Extrude Edges by Vector")))
end  


dx = p2.x - p1.x
dy = p2.y - p1.y
dz = p2.z - p1.z

model.selection.clear

cverts=[]
edges=[]
@ss.each{|e|
  cverts<< e.curve.vertices if e.curve and not cverts.include?(e.curve.vertices)
  edges<< e if not e.curve
}
cpoints=[]
cverts.each{|verts|
  pts=[]
  verts.each{|vert|pts<<vert.position}
  cpoints<< pts
}
if @group and @group.valid?
  group=@group
else
  group=model.active_entities.add_group()
  @group=group
end#if
ssa=[]
edges.each{|e|ssa<<group.entities.add_line(e.start.position,e.end.position)}
cpoints.each{|pts|ssa<<group.entities.add_curve(pts)}
ssa.flatten!

tr=Geom::Transformation.translation(p1.vector_to(p2))
points=[]
edges.each{|e|points<<[e.start.position,e.end.position]}
points_top=[]
points.each{|pints|
  pts=[]
  pints.each{|point|
    pt=point.clone
    pt.transform!(tr)
    pts << pt
  }
  points_top<<pts
}

clones=[]

points_top.each{|pts|clones<<group.entities.add_line(pts)}
cpoints_top=[]
cpoints.each{|points|
  pts=[]
  points.each{|point|
    pt=point.clone
    pt.transform!(tr)
    pts << pt
  }
  cpoints_top<<pts
}
cpoints_top.each{|pts|clones<<group.entities.add_curve(pts)}

clones.flatten!

clverts=[]
clones.each{|e|clverts<<[e.vertices[0].position,e.vertices[1].position]}

exfaces=[]
group.entities.each{|e|exfaces<<e if e.class==Sketchup::Face}

0.upto(ssa.length-1) do |i|
  edge=ssa[i]
 begin
  v1 = edge.vertices[0].position
  v2 = edge.vertices[1].position
  v1_top = Geom::Point3d.new(v1.x+dx, v1.y+dy, v1.z+dz)
  v2_top = Geom::Point3d.new(v2.x+dx, v2.y+dy, v2.z+dz)
  e1=group.entities.add_line(v1, v1_top)
  e2=group.entities.add_line(v2_top, v2)
  if edge.curve or (edge.smooth? or edge.soft?)
    mid=0
    e1.start.edges.each{|e|mid=mid+1 if e.curve}
    e2.start.edges.each{|e|mid=mid+1 if e.curve}
    if mid==4
      e1.smooth = true;e1.soft = true
      e2.smooth = true;e2.soft = true
    end#if
  end#if
  e1.find_faces
 rescue
  ###
 end#begin
  i=i+1 ### next edge
end # of upto
###
allfaces=[]
group.entities.each{|e|allfaces<<e if e.class==Sketchup::Face}
newfaces=allfaces-exfaces
newfaces[0].reverse! if newfaces[0].normal.z<0 ###
orient_connected_faces(newfaces[0],newfaces) if newfaces[0] and  newfaces[0].class==Sketchup::Face
### orient faces...
###
### reform curves
group.entities.to_a.each{|e|e.explode_curve if e.valid? and e.class==Sketchup::Edge and e.curve}
###
gpx=group.entities.add_group()
cvs=[]
cpoints.each{|pts|cvs=gpx.entities.add_curve(pts)}
cvs_top=[]
cpoints_top.each{|pts|cvs_top=gpx.entities.add_curve(pts)}
gpx.explode
###
### allow for 'merged' edges in selection...
clverts.each{|verts|
  group.entities.to_a.each{|e|
    if e.valid? and e.class==Sketchup::Edge
      if (e.vertices[0].position==verts[0] or e.vertices[0].position==verts[1]) and (e.vertices[1].position==verts[0] or e.vertices[1].position==verts[1])
        model.selection.add(e)### as it's a matching edge
      end#if
    end#if
  }
}

end#def

# Draw the geometry
def draw_geometry(p1, p2, view)
    view.line_stipple="."
    view.draw_line(p1,p2,"black")
    points=[]
    @ss.each{|e|points<<[e.start.position,e.end.position]}
    tr=Geom::Transformation.translation(p1.vector_to(p2))
    points_top=[]
    points.each{|pts|points_top<<[pts[0].clone.transform!(tr),pts[1].clone.transform!(tr)]}
    points_top.each{|pts|view.draw_line(pts[0],pts[1],"orange")}
    0.upto(points.length-1) do |i|
      view.draw_line(points[i][0],points_top[i][0],"orange")
      view.draw_line(points[i][1],points_top[i][1],"orange")
    end#do
end

end # class ExtrudeEdgesByVector

end#module
