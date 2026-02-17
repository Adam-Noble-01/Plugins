=begin
  Copyright 2014-2017 (c), TIG 
  [Based on EEbyVector]
  All Rights Reserved.
  THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED 
  WARRANTIES,INCLUDING,WITHOUT LIMITATION,THE IMPLIED WARRANTIES OF 
  MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
###
    extrudeEdgesByVectorToObject.rb
###
    A Tool that Extrudes Selected Edges along a Picked Vector, 
    similar to extrudeEdgesByVector - which is itself similar to 
    Sketchup's PushPull for a Face, BUT it extrudes only the Edges, AND 
    these Edges need NOT be connected to each other or coplanar, and the 
    Vector can be in any direction.
    However, with this Tool IF there is a Object [i.e. a face/edge either 
    in the active_entities or a group/instance] intersected by this Vector 
    then the extrusion is limited to the face of that object at that point 
    of the edge's vertex; otherwise it extrudes is up to the Vector's end.
    Any 'hits' are shown by a 'red' dot displayed on the object[s].
    If both projected ends of an edge do not intersect with an object, or 
    with the same face in the object, then there will still be complete 
    intersection lines formed around the object[s] in the extruded form, 
    with additional vertices added etc as required.
    
    This tool is useful in extruding wall edges up to roof soffits or down 
    onto uneven terrains; or edges sideways to other non-orthogonal faces.
    
###
Usage:  
    Select any number of Edges, Curves etc to be Extruded - 
    Anything else in the Selection, such as Faces, will be ignored.
        
    Run the Tool from Plugins > 'Extrude Edges by Vector to Object'.
    or click on 'Extrude Edges by Vector to Object' in the 
    'Extrusion Tools' Toolbar.
    [Activate this Toolbar from View > Toolbars if it's not loaded]
    
    Now follow the prompts on the VCB.
    Firstly: Pick any Point that will be the 'Start of the Vector' - 
     it need NOT be connected to any of the selected Edges.
    Secondly: Pick any Point that will be the 'End of the Vector' - 
     again this can be anywhere.
    As you move the mouse to Pick this Second Point you will see a
    'ghost' outline of the 'slab' of Edges that will be extruded.
    Note that if there are intervening objects such as faces or edges 
    [either in the current active_entities or within groups or 
    component-instances], then the final extrusion will stop at these.
    
    
Result:
    When you Pick the Second Point the Edges will extrude and make 
    new Edges and Faces - stopping at the vector's farthest extent OR at 
    faces/edges in intervening Objects [if any].
    Any Smoothed Edges in the selection will give Smoothed Edges to 
    the newly extruded Faces.
    Any Curves in the selection will also give Smoothed Edges to the new 
    Faces.
    The new Faces are consistently Oriented - **although non-continuous 
    edge-sets might produce oppositely oriented face-sets, however, these 
    are easily corrected afterwards by using right-click context-menu item 
    'reverse' on a selected face or faces and then 'orient', if needed.
    The extrusion's new Geometry - Edges and Faces - including a copy of 
    the original selected Edges is made inside a Group.
    
Next:
    On Completion there are two dialogs offering Yes/No Options-
    First: 'Reverse Extrusion's Faces'
     if you answer 'Yes' then all of the new Faces are Reversed
     [**see above about orientation of non-continuous edge-sets' faces].
    Second: 'Explode Extrusion's Group'
     if you answer 'Yes' then the newly made Geometry will merge into 
     the main active_entities' Geometry.
    The Extrusion will 'undo' in one step...

Note:
    Selected edges that intersect with themselves should be avoided as they 
    are unlikely to give the projected form required... so do them in parts 
    to avoid this self-intersecting.
    
Donations:
    Are welcome by PayPal to info @ revitrev.org.
    
Version:
    1.0 20110524 First release.
    1.1 20110528 New algorithm added for the intersecting with objects: now 
                 walls extend to soffits with additional apex vertices and 
                 so on so it extrudes fully to the faces/edges.
                 'Ghost' extrusions now show intersections as red dots.
                 The original selection is kept, unless the is group 
                 exploded.  ES lingvos updated by Defisto [thanks].
    1.2 20110528 Traps added for rare glitches with faced edge-selection.
    1.3 20110528 Undo fixed if reversed faces etc.
    1.4 20110528 Fixed glitch with commit & extruding edges inside group.
	2.0 20130520 Becomes part of ExtrudeTools Extension.
=end
#-----------------------------------------------------------------------------

module ExtrudeTools
###
toolname="extrudeEdgesByVectorToObject"
cmd=UI::Command.new(db("Extrude Edges by Vector to Object")){Sketchup.active_model.select_tool(ExtrudeTools::ExtrudeEdgesByVectorToObject.new())}
cmd.tooltip=db("Extrude Edges by Vector to Object")
cmd.status_bar_text="..."
cmd.small_icon=File.join(EXTOOLS, "#{toolname}16x16.png")
cmd.large_icon=File.join(EXTOOLS, "#{toolname}24x24.png")
SUBMENU.add_item(cmd)
TOOLBAR.add_item(cmd)
###
class ExtrudeEdgesByVectorToObject

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
  @toolname="extrudeEdgesByVectorToObject"
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
      Sketchup::set_status_text((db("Extrude Edges by Vector to Object"))+(db(": Reverse Extrusion's Faces ?")), SB_PROMPT)
      if UI.messagebox((db("Extrude Edges by Vector to Object"))+(db(": Reverse Extrusion's Faces ?")),MB_YESNO,"")==6 ### 6=YES 7=NO
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
      Sketchup::set_status_text((db("Extrude Edges by Vector to Object"))+(db(": Explode Extrusion's Group ?")), SB_PROMPT)
      if UI.messagebox((db("Extrude Edges by Vector to Object"))+(db(": Explode Extrusion's Group ?")),MB_YESNO,"")==6 ### 6=YES 7=NO
        @group.explode
      end#if
      ##
      view.model.commit_operation
      ###
    end#if
    @group=nil #######################
    view.invalidate if @drawn
    Sketchup::set_status_text((""), SB_PROMPT)
    return nil
end

def onLButtonDoubleClick(flags, x, y, view)
  self.deactivate(view)
  Sketchup.send_action("selectSelectionTool:")
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
            Sketchup::set_status_text((db("Extrude Edges by Vector to Object: Pick Second Point of Vector...")), SB_PROMPT)
            @xdown = x
            @ydown = y
        end
    else
        if( @ip2.valid? )
            self.create_geometry(@ip1.position, @ip2.position, view)
            self.deactivate(view)###
            Sketchup.send_action("selectSelectionTool:")
        end
    end
    view.lock_inference
end

# The onLButtonUp method is called when the user releases the left mouse button.
def onLButtonUp(flags, x, y, view)
    if( @dragging && @ip2.valid? )
        self.create_geometry(@ip1.position, @ip2.position,view)
        self.deactivate(view)###
        Sketchup.send_action("selectSelectionTool:")
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
        UI.messagebox((db("Extrude Edges by Vector to Object: Cannot Convert "))+text+(db(" to a Length.")))
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
    self.deactivate(view)###
    Sketchup.send_action("selectSelectionTool:")
end


def draw(view)
    return if @made
    if @ip1.valid?
        if @ip1.display?
            @ip1.draw(view)
            @drawn = true
            view.draw_points(@ip1.position, 8, 1, "black")
        end
        if @ip2.valid?
            @ip2.draw(view) if @ip2.display?
            view.set_color_from_line(@ip1, @ip2)
            self.draw_geometry(@ip1.position, @ip2.position, view)
            @drawn = true
        end
    end
    view.draw_points(@ip2.position, 8, 1, "black")
end

# onCancel is called when the user hits the escape key
def onCancel(flag, view)
    self.deactivate(view)
    Sketchup.send_action("selectSelectionTool:")
    return nil
end


# Reset the tool back to its initial state
def reset(view)
    
    @made=false
    
    model=Sketchup.active_model
    
    @ss=[]
    model.selection.each{|e|@ss<< e if e.class == Sketchup::Edge}
    if @ss.empty? 
      UI.messagebox(db("Extrude Edges by Vector to Object: No Edge in Selection."))
      self.deactivate(view)
      Sketchup.send_action("selectSelectionTool:")
      return nil
    end#if

    @state = 0
    
    Sketchup::set_status_text((db("Extrude Edges by Vector to Object: Pick First Point of Vector...")), SB_PROMPT)
    
    @ip1.clear
    @ip2.clear
    
    if view
        view.tooltip = nil
        view.invalidate if @drawn
    end
    
    @drawn = false
    @dragging = false
end


# Create new geometry when the user has selected two points.
def create_geometry(p1, p2, view)

@made=true
view.invalidate
model = view.model

if Sketchup.version.to_i > 6
	model.start_operation((db("Extrude Edges by Vector to Object")), true)
  ### 'false' is best to see results as UI/msgboxes...
else
	model.start_operation((db("Extrude Edges by Vector to Object")))
end  

dx = p2.x - p1.x
dy = p2.y - p1.y
dz = p2.z - p1.z
=begin
model.selection.clear
=end
cverts=[]
edges=[]
@ss.each{|e|
  cverts << e.curve.vertices if e.curve and not cverts.include?(e.curve.vertices)
  edges << e if not e.curve
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
edges.each{|e|ssa << group.entities.add_line(e.start.position,e.end.position)}
cpoints.each{|pts|ssa << group.entities.add_curve(pts)}
ssa.flatten!

ve=p1.vector_to(p2) ###
tr=Geom::Transformation.translation(ve)

points=[]
edges.each{|e|points << [e.start.position,e.end.position]}
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
cpoints.each{|pints|
  pts=[]
  pints.each{|point|
    pt=point.clone
    pt.transform!(tr)
    pts << pt
  }
  cpoints_top << pts
}
cpoints_top.each{|pts|clones << group.entities.add_curve(pts)}

clones.flatten!

clverts=[]
clones.each{|e|clverts << [e.vertices[0].position,e.vertices[1].position]}

exfaces=[]
group.entities.each{|e|exfaces << e if e.class==Sketchup::Face}

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
group.entities.each{|e|allfaces << e if e.class==Sketchup::Face}
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
=begin
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
=end
### remember original edges
oedges=[]; group.entities.each{|e| oedges << e if e.class==Sketchup::Edge }
### intersect with model
group.entities.intersect_with(true, group.transformation, group.entities, group.transformation, true, model.entities.to_a) ###
### get new edges
aedges=[]; group.entities.each{|e| aedges << e if e.class==Sketchup::Edge }
nedges=aedges-oedges### new edges
### get new vertices
nverts=[]; nedges.each{|e| nverts << e.vertices }
nverts.flatten!
nverts.uniq!
### add top projecting edges
vedges=[]
nverts.each{|v| vedges << group.entities.add_line(v.position, v.position.offset(ve)) }
### split if needed
group.entities.intersect_with(true, group.transformation, group.entities, group.transformation, true, group.entities.to_a)
### erase unfaced bits
group.entities.to_a.each{|e| e.erase! if e.valid? and e.class==Sketchup::Edge and not e.faces[0]}
### again get edges, without original lines
aedges=[]; group.entities.each{|e| aedges << e if e.class==Sketchup::Edge}
### get 'original' edges in selection...
nsedges=[]
opoints=[]
osedges=[]
@ss.each{|e|
  if e.valid? and e.class==Sketchup::Edge
    opoints << [e.vertices[0].position, e.vertices[1].position]
    osedges << e
  end#if
}
ofaces=[]
overts=[]
osedges.each{|e|
  ofaces << e.faces
  overts << e.vertices
}
ofaces.flatten!
ofaces.uniq!
overts.flatten!
overts.uniq!
oxedges=[]
ofaces.each{|e|oxedges << e.edges}
oxedges.flatten!
oxedges.uniq!
aedges.each{|e|
  opoints.each{|pts|
      if e.vertices[0].position==pts[0] and e.vertices[1].position==pts[1]
        nsedges << e ### as it's a 'matching edge'
      end#if
      if e.vertices[0].position==pts[1] and e.vertices[1].position==pts[0]
        nsedges << e ### as it's a 'matching edge'
      end#if
  }
}
###
par=[]
par=[model.active_entities.parent] if model.active_entities.parent != model
###
nedges=aedges-nsedges
vr=ve.reverse
nedges.dup.each{|e| nedges.delete(e) if e.line[1].samedirection?(ve) or e.line[1].samedirection?(vr) or e.line[1].parallel?(ve) or e.line[1].parallel?(vr) or e.line[1].normalize==ve.normalize or e.line[1].normalize==vr.normalize or e.line[1].cross(ve).length==0 or e.line[1].cross(vr).length==0 }
### i.e. only look at edges not parallel with extrusion vector
### now project from centre of each nedge
togos=[]
nedges.each{|e|
  next if not e.valid?
  tp=e.start.position.offset(e.line[1],e.length/2)
  rayt=model.raytest([tp,vr])
  next if not rayt
  togo=true
  (nsedges+osedges+ofaces+overts+oxedges+par).compact.uniq.each{|ee|
    if rayt[1].include?(ee)
      togo=false
      break
    end#if
  }
  togos << e if togo
}
### test...
#togos.each{|e|group.entities.add_cpoint(e.start.position.offset(e.line[1],e.length/2))}
### erase unwanted egdes
group.entities.erase_entities(togos)
### erase unfaced again
group.entities.to_a.each{|e| e.erase! if e.valid? and e.class==Sketchup::Edge and not e.faces[0] }
###
begin
  view.refresh
rescue
  ###v<8
end
###

end#def

# Draw the temp geometry
def draw_geometry(p1, p2, view)
    view.line_stipple="."
    view.draw_line(p1, p2, "black")
    points=[]
    edges=[]
    @ss.each{|e|
      next if e.class!=Sketchup::Edge
      points << [e.start.position, e.end.position]
      edges << e
    }
    vector=p1.vector_to(p2)
    tr=Geom::Transformation.translation(vector)
    points_top=[]
    points.each{|pts|points_top << [pts[0].clone.transform!(tr), pts[1].clone.transform!(tr)]}
    points_top.each{|pts|view.draw_line(pts[0], pts[1], "orange")}
    0.upto(points.length-1) do |i|
      view.draw_line(points[i][0], points_top[i][0], "orange")
      view.draw_line(points[i][1], points_top[i][1], "orange")
    end#do
    points_hit=[]
    points.each{|pts|
      ps=pts[0]
      pe=pts[1]
      begin
        rayt=nil
        rayt=view.model.raytest([ps, vector]) if ps
        ###edges?
        points_hit << rayt[0] if rayt and ps and ps.distance(rayt[0])<=p1.distance(p2)
        rayt=nil
        rayt=view.model.raytest([pe, vector]) if pe
        ###edges?
        points_hit << rayt[0] if rayt and pe and pe.distance(rayt[0])<=p1.distance(p2)
      rescue Exception => e
        ###
      end
    }
    view.draw_points(points_hit, 4, 2, "red") if points_hit[0]
end

end # class ExtrudeEdgesByVectorToObject

end#module
