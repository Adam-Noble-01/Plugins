=begin
(c) TIG 2013-2017
ALL RIGHTS RESERVED

extrudeEdgesByLathe.rb

First Select a 'polyline', i.e. an arc of welded curves/arcs/lines etc.
OR a Face [then the Face's Edges will be used]
Choose the tool 'Extrude Edges by Lathe' on the Plugins menu 
or type 'extrudeEdgesByLathe' in the Ruby Console
or use the 'Extrude Edges by Lathe' on the 'Extrusion Tools' Toolbar.
You are prompted to pick the arc's center-point.  
The VCB reports the dynamic point -e.g. [1.234,56.789,0.0].
You must then pick a second-point to set the axis-of-rotation - 
for example, picking a second-point vertically above the center-point 
(using inference and shift when blue etc) it would be the Z-axis [blue].
The VCB reports the dynamic vector - e.g. [0.0,0.0,1.0] == Z-axis.
Input the arc's swept-angle in degrees (-ve=clockwise) e.g. '90' or '-90'
and/or the number of the arc's segments with an 's' suffix e.g. '24s' ...
the initial defaults are 45.0 & 9s.
The 'ghost' display changes to show what you've set...
Any changes are remembered for that model, across sessions.
IF you enter '0' [zero] as the swept angle you are then prompted to 
pick two points to set the rotation angle dynamically - typically the 
first one will be on the 'profile' and the second where you want the 
sweep to end.
A guide 15 degree-step 'protractor' is drawn at the center-point.
To pick swept-angles greater <> 180 degrees toggle <Alt> key.
To pick swept-angles 'c/clockwise' toggle <Shift> key.
These toggles may be used together.
The 'ghost' display changes to show what you've picked...
You can keep changing settings etc until you are happy with the result.
To confirm press 'Ctrl' or double-click the mouse to make the mesh...
The selected polyline's [or face's] edges are then swept around an arc: 
using the picked center, about the selected axis-of-rotation.
The edges are divided and 'faced'.
The faces will be triangulated if necessary.
If a Face is the source then the geometry has 'end-faces' - 
unless the swept arc >=360 degrees.
If a 'looped' polyline curve is the source there are no 'end-faces'.
You are asked if you want to remove coplanar faces, Yes/No...
Faces are auto-oriented.
You are asked if you want to reverse the faces, Yes/No...
You are asked if you want to smooth-edges, Yes/No...
The faced geometry is made inside a group.
The original face/edges remain unchanged.
The result is a 'true' 'Followme' swept shape unlike the built-in 
'FollowMe' tool's results...

Donations:
        Are welcome [by PayPal], please use 'TIGdonations.htm' in the 
        ../Plugins/TIGtools/ folder.
        
Version:
20090915 1.0 First issue
20090916 1.1 Pick cursor/inferencing improved, choose 'axis' added.
20090917 1.2 'Round' error fixed. Operation optimized for v7 users.
20090918 1.3 Soft/Smooth Edges option added.
20090919 1.4 Inference-locking glitch fixed on repeated lathes.
20090920 1.5 Smooth bug with Reverse Faces fixed.
20090924 1.6 Removal of Coplanar Edges now Optional. Superfluous face removal improved.
20100114 x2.0 Rename extrudeEdgesByLathe, Final Explode Group and Toolbar added.
             DeBabelized and 'Extrusion Tools' Toolbar added.
20100120 x2.1 ES lingvo file updated by Defisto.
20100121 x2.2 Typo preventing Plugin Menu item working corrected.
20100121 x2.3 FR lingvo file updated by Pilou.
20100123 x2.4 FR lingvo file updated by Pilou.
20100206 x2.5 Resume VCB text improved.
20100216 x2.6 All extrusion-tools now in one in Plugins sub-menu.
20100222 x2.7 Tooltips etc now deBabelized properly.
20100609 x2.8 Glitch fixed on completion stages.
20100330 x2.9 Dialog replaced with VCB input, e.g. 45 or 9s - soft @end
             ability to select rotation angle by picking 2 points added.
             Settings now remembered properly with model across sessions.
20100330 x3.0 Lingvo files updated to match recent changes.
20100331 x3.1 Beep removed at start.
20101027 x3.2 Undoes better.
20111020 x3.3 Start_operation now deBabelized.
20111023 x3.4 Smooth now ignores edges with only one face.
20111102 x3.5 Fixed Picked-Angle's messy undo. Smoothed-edges stop @90º.

2.0 20130520 Becomes part of ExtrudeTools Extension.

=end
###
module ExtrudeTools
###
toolname="extrudeEdgesByLathe"
cmd=UI::Command.new(db("Extrude Edges by Lathe")){Sketchup.active_model.select_tool(ExtrudeTools::ExtrudeEdgesByLathe.new())}
cmd.tooltip=db("Extrude Edges by Lathe")
cmd.status_bar_text="..."
cmd.small_icon=File.join(EXTOOLS, "#{toolname}16x16.png")
cmd.large_icon=File.join(EXTOOLS, "#{toolname}24x24.png")
SUBMENU.add_item(cmd)
TOOLBAR.add_item(cmd)
###
class ExtrudeEdgesByLathe

include ExtrudeTools

def roundup(n=0, x=0)
    (n*10**x).round.to_f/10**x
end

def initialize()
  @toolname="extrudeEdgesByLathe"
  @ip=nil
  @ip1=nil
  @ip2=nil
  @ip3=nil
  @ip4=nil
  @state=nil
  @center=nil
  @axis=nil
  @curve=nil
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
  @model=Sketchup.active_model
  @state=0
  @curve=@model.selection[0]
  @face=nil
  if not @curve
    UI.messagebox(db("Extrude Edges by Lathe: Select a Polyline OR a Face..."))
    self.deactivate(@model.active_view)
    return nil
  end#if
  if not @curve.class==Sketchup::Edge or not @curve.curve
    ###check to see if it's a Fsce
    @face=nil;@model.selection.each{|e|
      if e.class==Sketchup::Face
        @face=e
        break
      end#if
    }
    if not @face
      UI.messagebox(db("Extrude Edges by Lathe: Select a Polyline OR a Face..."))
      self.deactivate(@model.active_view)
      return nil
    end#if
  end#if
  @msg=(db("Extrude Edges by Lathe: Settings..."))
  Sketchup::set_status_text(@msg)
  Sketchup.set_status_text("",SB_VCB_VALUE)                
  Sketchup.set_status_text("", SB_VCB_LABEL)
  @angle=@model.get_attribute("ExtrudeEdgesByLathe","angle",45.0)
  @segs=@model.get_attribute("ExtrudeEdgesByLathe","segs",9)
  @state=1
  @ip=nil
  @ip1=nil
  @ip2=nil
  @ip3=nil
  @ip4=nil
  @ip=Sketchup::InputPoint.new
  @ip1=Sketchup::InputPoint.new
  @ip2=Sketchup::InputPoint.new
  @ip3=Sketchup::InputPoint.new
  @ip4=Sketchup::InputPoint.new
  @pickangle=false
  @alt=false
  @shift=false
  @msg=(db("Extrude Edges by Lathe:  Pick the Arc's Center-Point..."))
  Sketchup::set_status_text(@msg)
  Sketchup.set_status_text((db("Lathe Center")), SB_VCB_LABEL)
  Sketchup.set_status_text("",SB_VCB_VALUE)
  ###UI.beep
end#def

def deactivate(view)
  view.invalidate if view
  @ip=nil 
  @ip1=nil
  @ip2=nil
  @ip3=nil
  @ip4=nil
  @center=nil
  @axis=nil
  @angle_start=nil
  @angle_end=nil
  @curve=nil
  @state=nil
  @pickangle=false
  @alt=false
  @shift=false
  @prot.erase! if @prot and @prot.valid? ###
  Sketchup::set_status_text("")
  Sketchup::set_status_text("",SB_VCB_LABEL)
  Sketchup::set_status_text("",SB_VCB_VALUE)
  Sketchup.send_action("selectSelectionTool:")
  return nil
end#def

def onCancel(flag,view)
  self.deactivate(view)
  Sketchup.send_action("selectSelectionTool:")
  return nil
end#def

def resume(view)
  Sketchup::set_status_text(@msg)
  view.invalidate
end

def onMouseMove(flags,x,y,view)
  @ip.pick(view,x,y)
  view.lock_inference
  view.tooltip=(db("Lathe Center Point: "))+@ip.tooltip
  case @state
   when 1
    @msg=(db("Extrude Edges by Lathe:  Pick the Arc's Center-Point..."))
    Sketchup::set_status_text(@msg)
    Sketchup.set_status_text((db("Lathe Center")),SB_VCB_LABEL)
    if @ip.valid? and @ip!=@ip1
      @ip1.copy!(@ip)
      view.invalidate
      xyz=@ip1.position
      xyztxt="["+roundup(xyz.x, 3).to_s+","+roundup(xyz.y, 3).to_s+","+roundup(xyz.z, 3).to_s+"]"
      Sketchup.set_status_text(xyztxt,SB_VCB_VALUE)
    end#if
   when 2
    @msg=(db("Extrude Edges by Lathe:  Pick a Second Point to Set the Axis of Rotation..."))
    Sketchup::set_status_text(@msg)
    Sketchup.set_status_text((db("Lathe Axis")),SB_VCB_LABEL)
    @ip2.pick(view,x,y,@ip1)
    if @ip2.valid? and @ip2!=@ip1
      view.invalidate
      xyz=(@ip2.position-@ip1.position).normalize
      xyztxt="["+roundup(xyz.x, 3).to_s+","+roundup(xyz.y, 3).to_s+","+roundup(xyz.z, 3).to_s+"]"
      Sketchup.set_status_text(xyztxt,SB_VCB_VALUE)
    end#if
   when 3
     if not @pickangle
       @msg=(db("Extrude Edges by Lathe:  Angle/Segments (e.g. 45 or 9s): 0=Pick-Angle: <Ctrl>/double-click to confirm..."))
       Sketchup::set_status_text(@msg)
       Sketchup.set_status_text((db("Angle/Segments")),SB_VCB_LABEL)
       Sketchup::set_status_text(@angle.to_s, SB_VCB_VALUE)
       view.invalidate
     else ### dynamically pick the angle points...
       @msg=(db("Extrude Edges by Lathe:  Pick the Point for the Start of Angle: Toggles <Alt><>180deg/<Shift>C/Clockwise, or Type Angle..."))
       Sketchup::set_status_text(@msg)
       Sketchup.set_status_text((""),SB_VCB_LABEL)
       if @ip.valid? and @ip!=@ip1 and @ip!=@ip2
         @ip3.copy!(@ip)
         view.invalidate
         xyz=@ip3.position
         xyztxt="["+roundup(xyz.x, 3).to_s+","+roundup(xyz.y, 3).to_s+","+roundup(xyz.z, 3).to_s+"]"
         Sketchup.set_status_text(xyztxt,SB_VCB_VALUE)
       end#if
     end#if
   when 4
     if not @pickangle
       @msg=(db("Extrude Edges by Lathe:  Angle/Segments (e.g. 45 or 9s): 0=Pick-Angle: <Ctrl>/double-click to confirm..."))
       Sketchup::set_status_text(@msg)
       Sketchup.set_status_text((db("Angle/Segments")),SB_VCB_LABEL)
       Sketchup::set_status_text(@angle.to_s, SB_VCB_VALUE)
       view.invalidate
     else ### dynamically pick the angle points...
       @msg=(db("Extrude Edges by Lathe:  Pick the Point for the End of Angle: Toggles <Alt><>180deg/<Shift>C/Clockwise, or Type Angle..."))
       Sketchup::set_status_text(@msg)
       Sketchup.set_status_text((db("Angle")),SB_VCB_LABEL)
       Sketchup.set_status_text(@swept_angle.to_s,SB_VCB_VALUE)
       #####///////////////
       if @ip.valid? and @ip!=@ip1 and @ip!=@ip2 and @ip!=@ip3
         @ip4.copy!(@ip)
         view.invalidate
         @angle_end=@ip4.position #########################???????????
         view.invalidate
         #self.get_plane_angle()
         ### work out angle and report it ?
         ### FIX FOR >180 degrees !!!!!!!!!
       end#if
     end#if
   else
     Sketchup::set_status_text("")
     view.invalidate
  end#case
end#def

def draw(view)
  if @ip1 and @ip1.valid? and @ip1.display?
   if @state<=2
    view.tooltip=(db("Lathe Center Point: "))+@ip1.tooltip
    p1=@ip1.position
    view.draw_points([p1],16,1,"orange")
    @ip1.draw(view)
    if @ip2 and @ip2.valid? and @ip2!=@ip1 and @state==2
      view.tooltip=(db("Lathe Axis Point: "))+@ip2.tooltip
      @ip2.draw(view)if @ip2.display?
      begin
        p2=@ip2.position
        view.set_color_from_line(@ip1,@ip2)
        view.draw_polyline([p1,p2])
        view.draw_points([p2],16,1,"orange")
      rescue
        ###
      end
    end#if
   elsif @pickangle ### we'll pick angle...
     if @state==3
       view.tooltip=(db("Start Angle: "))+@ip3.tooltip
       p1=@center
       @ip3.draw(view)
       if @ip3 and @ip3.valid? and @ip3!=@ip2 and @ip3!=@ip1
         view.tooltip=(db("Start Angle: "))+@ip3.tooltip
         @ip3.draw(view)if @ip3.display?
         begin
           p2=@ip3.position
           view.set_color_from_line(@ip1,@ip3)
           view.draw_polyline([p1,p2])
           view.draw_points([p2],8,1,"magenta")
         rescue
           ###
         end
       end#if
     elsif @state==4
       view.tooltip=(db("Angle"))###+@ip4.tooltip
       p1=@center
       @ip4.draw(view)
       if @ip4 and @ip4.valid? and @ip4!=@ip1 and @ip4!=@ip2 and @ip4!=@ip3
         view.tooltip=(db("Angle: "))+@ip4.tooltip
         @ip4.draw(view)if @ip4.display?
         begin
           p2=@ip4.position
           view.set_color_from_line(@ip1,@ip4)
           view.draw_polyline([p1,p2])
           view.draw_points([p2],8,1,"magenta")
         rescue
           ###
         end
       end#if
     end#if
    end#if
  end#if
  if @state >2 and @state <5
    self.draw_ghost(view)
  end#if
end#def draw

def onKeyDown(key,repeat,flags,view)
    if key==CONSTRAIN_MODIFIER_KEY and repeat==1
        @shift_down_time=Time.now
        if view.inference_locked?
            view.lock_inference
        elsif @state==1 and @ip1.valid?
            view.lock_inference @ip1
        elsif @state==2 and @ip2.valid?
            view.lock_inference @ip2, @ip1
        elsif @state==3 and @ip3.valid?
            view.lock_inference @ip3, @ip1
        elsif @state==4 and @ip4.valid?
            view.lock_inference @ip4, @ip1
        end
    end
    if key==VK_CONTROL  ### Ctrl == make mesh
      @state=5
      self.create_geometry()
    end#if
    if key==VK_ALT  ### Alt toggles == <>180degrees
      if @alt
        @alt=false
      else
        @alt=true
      end#if
    end#if
    if key==VK_SHIFT  ### Shift == c/clockwise
      if @shift
        @shift=false
      else
        @shift=true
      end#if
    end#if
end#def

def onKeyUp(key, repeat, flags, view)
    if key==CONSTRAIN_MODIFIER_KEY and view.inference_locked? and (Time.now - @shift_down_time) > 0.5
        view.lock_inference
    end
    view.invalidate
end#def

def onLButtonDown(flags,x,y,view)
  if @state==1 ###center
    @ip1.pick view,x,y
    if @ip1.valid?
      @center=@ip1.position
      @ip.clear
      @state=2
    end#if
  elsif @state==2 ###axis
    @ip2.pick view,x,y
    if @ip2.valid? and @ip2!=@ip1
      @axis=@ip2.position
      view.invalidate
      @state=3
    end#if
  elsif @state==3 ### angle start ###############
    @msg=(db("Extrude Edges by Lathe:  Angle/Segments (e.g. 45 or 9s): <Ctrl>/double-click to confirm..."))
    Sketchup::set_status_text(@msg)
    Sketchup.set_status_text((db("Angle/Segments")),SB_VCB_LABEL)
    Sketchup::set_status_text(@angle.to_s, SB_VCB_VALUE)
    if @pickangle
       @msg=(db("Extrude Edges by Lathe:  Pick the Point for the Start of Angle: Toggles <Alt><>180deg/<Shift>C/Clockwise, or Type Angle..."))
       Sketchup::set_status_text(@msg)
       Sketchup.set_status_text((db("Angle")),SB_VCB_LABEL)
       Sketchup.set_status_text("",SB_VCB_VALUE)
    end#if
    @ip3.pick view,x,y
    if @pickangle and @ip3.valid? and @ip3!=@ip1 and @ip3!=@ip2
      @angle_start=@ip3.position
      @angle_start.class
      view.invalidate
      @state=4
    end#if
  elsif @state==4 ### angle end #################
    @msg=(db("Extrude Edges by Lathe:  Angle/Segments (e.g. 45 or 9s): <Ctrl>/double-click to confirm..."))
    Sketchup::set_status_text(@msg)
    Sketchup.set_status_text((db("Angle/Segments")),SB_VCB_LABEL)
    Sketchup::set_status_text(@angle.to_s, SB_VCB_VALUE)
    if @pickangle
       @msg=(db("Extrude Edges by Lathe:  Pick the Point for the End of Angle: Toggles <Alt><>180deg/<Shift>C/Clockwise, or Type Angle..."))
       Sketchup::set_status_text(@msg)
       Sketchup.set_status_text((db("Angle")),SB_VCB_LABEL)
       Sketchup.set_status_text(@swept_angle.to_s,SB_VCB_VALUE) if @swept_angle
    end#if
    @ip4.pick view,x,y
    if @pickangle and @ip4.valid? and @ip4!=@ip1 and @ip4!=@ip2 and @ip4!=@ip3
      @angle_end=@ip4.position
      view.invalidate
      self.get_plane_angle()
      @state=3 ### to loop
      @prot.erase! if @prot and @prot.valid? ###
    end#if
    view.invalidate
  end#if
end#def

def onLButtonUp(flags,x,y,view)
  view.invalidate if view
end

def enableVCB?
   return true
end

def onUserText(text,view)
  if text=~/s$/ ### it's segements
    begin
      value=text.to_i
    rescue ### Error parsing the text
        UI.beep
        puts (db"Cannot convert ")+text+(db" to an Integer")
        value=nil
        Sketchup::set_status_text("",SB_VCB_VALUE)
    end
    return if not value
    if value==0.0
      UI.messagebox(db("Segments cannot be zero !"))
    else
      @segs=value
    end#if
  else ### it's an angle
    begin
        value=text.to_f
    rescue ### Error parsing the text
        UI.beep
        puts (db"Cannot convert ")+text+(db" to an Angle")
        value=nil
        Sketchup::set_status_text("",SB_VCB_VALUE)
    end
    return if not value
    if value==0.0 ### TO SORT !!!!!!!!!!!!!
      @pickangle=true
      if Sketchup.version.to_i >= 7
        @model.start_operation((db("ExtrudeEdgesByLathe")), true)
      else
        @model.start_operation((db("ExtrudeEdgesByLathe")))
      end
      self.make_protractor()
      self.place_protractor()
      #UI.messagebox("Angle cannot be zero !")
    else
      @angle=value
      @pickangle=false
    end#if
  end#if
end

def onLButtonDoubleClick(flags, x, y, view)
    @state=5
    self.create_geometry()
end

def make_protractor()
  ents=@model.active_entities
  @prot=ents.add_group()
  pents=@prot.entities
  rad=@center.distance(@axis)
  circ1=pents.add_circle(@center,[0,0,1],rad,24)
  circ2=pents.add_circle(@center,[0,0,1],rad/1.5,24)
  pverts=[];pends1=[]
  circ1.each{|e|
    pverts << e.vertices[0].position.to_a << e.vertices[1].position.to_a
    pends1 << [e.vertices[0].position.to_a, e.vertices[1].position.to_a]
  }
  pends2=[]
  circ2.each{|e|pends2 << [e.vertices[0].position.to_a, e.vertices[1].position.to_a] }
  pverts.uniq!
  pents.to_a.each{|e|e.erase! if e.valid?}
  pends1.each{|a|pents.add_cline(a[0], a[1]) }
  pends2.each{|a|pents.add_cline(a[0], a[1]) }
  pverts.each{|p|pents.add_cline(@center, p) }
end

def place_protractor()
  ### translate prot group to end of path
  tr=Geom::Transformation.translation(@center.vector_to(@center))
  @prot.transform!(tr)
  ###
  @vector=@center.vector_to(@axis)
  flat_vector=@center.vector_to([@axis.x,@axis.y,@center.z])
  flat_angle=Y_AXIS.angle_between(flat_vector)
  tr=Geom::Transformation.rotation(@center,Z_AXIS,90.degrees)
  perp_flat_vector=flat_vector.transform(tr)
  tilt_angle=flat_vector.angle_between(@vector)
  tilt_angle= -tilt_angle if @center.z<@axis.z
  ### check various orientations and locate/rotate prot to suit
  if @center.x==@axis.x and @center.y==@axis.y ###vertical
    if @center.z<@axis.z ### flip & rotate face
      tr=Geom::Transformation.rotation(@center,X_AXIS,180.degrees)
    end#if
  elsif @center.x>=@axis.x and @center.y>=@axis.y
    tr=Geom::Transformation.rotation(@center,Z_AXIS,-360.degrees+flat_angle)
    @prot.transform!(tr)
    tr=Geom::Transformation.rotation(@center,perp_flat_vector,-90.degrees)
    @prot.transform!(tr)
    tr=Geom::Transformation.rotation(@center,perp_flat_vector,tilt_angle)
    @prot.transform!(tr)
  elsif @center.x>=@axis.x and @center.y<@axis.y
    tr=Geom::Transformation.rotation(@center,Z_AXIS,-360.degrees+flat_angle)
    @prot.transform!(tr)
    tr=Geom::Transformation.rotation(@center,perp_flat_vector,-90.degrees)
    @prot.transform!(tr)
    tr=Geom::Transformation.rotation(@center,perp_flat_vector,tilt_angle)
    @prot.transform!(tr)
  elsif @center.x<=@axis.x and @center.y<@axis.y
    tr=Geom::Transformation.rotation(@center,Z_AXIS,-flat_angle)
    @prot.transform!(tr)
    tr=Geom::Transformation.rotation(@center,perp_flat_vector,-90.degrees)
    @prot.transform!(tr)
    tr=Geom::Transformation.rotation(@center,perp_flat_vector,tilt_angle)
    @prot.transform!(tr)
  else
    tr=Geom::Transformation.rotation(@center,Z_AXIS,-flat_angle)
    @prot.transform!(tr)
    tr=Geom::Transformation.rotation(@center,perp_flat_vector,-90.degrees)
    @prot.transform!(tr)
    tr=Geom::Transformation.rotation(@center,perp_flat_vector,tilt_angle)
    @prot.transform!(tr)
  end#if
  @plane=[@center,@vector]
end

def get_plane_angle()
  line=[@angle_end, @vector]
  @angle_end_point=Geom.intersect_line_plane(line, @plane) if @angle_end
  if @state==4
    @swept_angle=(@center.vector_to(@angle_start)).angle_between(@center.vector_to(@ip.position)).radians
    @swept_angle= 360-@swept_angle if @alt
    @swept_angle= -@swept_angle if @shift
  elsif @state>4
    @swept_angle=(@center.vector_to(@angle_start)).angle_between(@center.vector_to(@angle_end_point)).radians if @angle_end_point ###
    @swept_angle= 360-@swept_angle if @alt
    @swept_angle= -@swept_angle if @shift
  end#if
end

def draw_ghost(view)
  ### ghost of form
  if @pickangle ### calc' angle from the points picked
    self.get_plane_angle()
    angle=@swept_angle
  else
    angle=@angle
  end#if
  segs=@segs
  center=@center
  axis=@axis-@center
  points=[]
  (segs+1).times do |i|###copy curve_edge-set points and and rotate them
    pts=[]
    angle=0 if not angle
    tr=Geom::Transformation.rotation(center,axis,(i)*(angle.degrees)/segs)
    if not @face
      @curve.curve.vertices.each{|v|
        pt=v.position
        pt.transform!(tr)
        pts<<pt
      }
    else
      @face.loops.each{|loop|
        first=nil
        loop.vertices.each{|v|
          pt=v.position
          pt.transform!(tr)
          first=pt if not first
          pts<<pt
        }
        pts<<first if first ###close loop
      }
    end#if
    points<<pts
  end#times
  view.drawing_color="darkcyan"
  #view.line_stipple="."
  points.each{|pts|
    pts.each{|pt|
      ptnext=pts[pts.index(pt)+1]
      view.draw_line(pt,ptnext)if ptnext
    }
  }
  points.each{|pts|
    pts.length.times do |i|
      pt=pts[i]
      ptnext=points[points.index(pts)+1][i]if points[points.index(pts)+1]
      ptup=points[points.index(pts)+1][i+1]if points[points.index(pts)+1]
      if ptnext
        view.draw_line(pt,ptnext)
        if ptup
          view.draw_line(pt,ptup)### = the diagonal
        end#if
      end#if
    end#do
  }
  ###
end

def create_geometry()
  Sketchup.set_status_text("",SB_VCB_VALUE)
  Sketchup.set_status_text("",SB_VCB_LABEL)
 if not @pickangle
  if Sketchup.version.to_i >= 7
    @model.start_operation((db("ExtrudeEdgesByLathe")), true)
  else
    @model.start_operation((db("ExtrudeEdgesByLathe")))
  end
 end
  entities=@model.active_entities
  if @pickangle ### calc' angle from the points picked
    @angle=@swept_angle
  end#if
  angle=@angle
  segs=@segs
  center=@center
  axis=@axis-@center
  points=[]
  (segs+1).times do |i|###copy curve_edge-set points and and rotate them
    pts=[]
    tr=Geom::Transformation.rotation(center,axis,(i)*(angle.degrees)/segs)
    if not @face
      @curve.curve.vertices.each{|v|
        pt=v.position
        pt.transform!(tr)
        pts<<pt
      }
    else
      @face.loops.each{|loop|
        first=nil
        loop.vertices.each{|v|
          pt=v.position
          pt.transform!(tr)
          first=pt if not first
          pts<<pt
        }
        pts<<first if first ###close loop
      }
    end#if
    points<<pts
  end#times
  group=entities.add_group()
  gents=group.entities
  ### points is array of arrays of all points
  if not @face
    len=@curve.curve.vertices.length
  else
    len=0;@face.loops.each{|loop|loop.vertices.each{|v|len+=1}}
  end#if
  vlines=[]
  num=1
  points.each{|pts|
    pts.each{|pt|
      ptnext=pts[pts.index(pt)+1]
      vline=gents.add_line(pt,ptnext)if ptnext
      vlines<<vline if vline
      @msg=((db("Extrude Edges by Lathe: Making Primary Lines "))+(num.to_s)+(db(" of "))+((segs*len).to_s))
      Sketchup::set_status_text(@msg)
      num+=1
    }
  }
  lines=[]
  num=1
  points.each{|pts|
    pts.length.times do |i|
      pt=pts[i]
      ptnext=points[points.index(pts)+1][i]if points[points.index(pts)+1]
      ptup=points[points.index(pts)+1][i+1]if points[points.index(pts)+1]
      if ptnext
        line=gents.add_line(pt,ptnext)
        lines<<line
        if ptup
          lineup=gents.add_line(pt,ptup)### = the diagonal
        end#if
        @msg=((db("Extrude Edges by Lathe: Making Secondary Lines "))+(num.to_s)+(db(" of "))+(((1+segs)*len).to_s))
        Sketchup::set_status_text(@msg)
      num+=1
      end#if
    end#do
  }
  GC.start ### ### ###
  num=1
  lines.each{|e| ### make faces
    if e and e.valid?
      @msg=((db("Extrude Edges by Lathe: Making Faces "))+(num.to_s)+(db(" of "))+((1+segs)*len).to_s)
      Sketchup::set_status_text(@msg)
      e.find_faces
      num+=1
    end#if
  }
  @msg=(db("Extrude Edges by Lathe: Tidying Faces"))
  ### check faces have 3 sides if not erase them...
  segs.times do |this|
    Sketchup::set_status_text(@msg)
    gents.each{|e|if @angle>=360
        e.erase! if e.class==Sketchup::Face and e.edges.length>3
        e.find_faces if e.class==Sketchup::Edge and e.faces.length==1
      end#if
    }
    @msg=@msg+"."
  end#times
  ### tidy faceless edges...
  group.entities.to_a.each{|e|e.erase! if e.class==Sketchup::Edge and not e.faces[0]}
  ###
  ### set @model attributes for next time used...
  @model.set_attribute("ExtrudeEdgesByLathe","angle",@angle)
  @model.set_attribute("ExtrudeEdgesByLathe","segs",@segs)
  ###
  ### make gable-end faces last
  if @face and @angle<360
    vlines.first.find_faces if vlines.first.valid?
    vlines.last.find_faces if vlines.last.valid?
  end#if
  ### orient faces...
  faces=[];gents.each{|e|faces<<e if e.class==Sketchup::Face}
  faces.reverse! if faces[0] and faces[0].normal.z<0
  while faces[0]
    face=faces[0]
    face.reverse! if face.normal.z<=0
    face.orient_connected_lathed_faces
    connected=[];face.all_connected.each{|e|connected.push(e)if e.kind_of?(Sketchup::Face)}
    faces=faces-connected-[face]
  end#while
  ###
  @model.commit_operation
  ###
  ### remove coplanar edges ?
  @msg=((db("Extrude Edges by Lathe: Remove Coplanar Edges ?")))
  Sketchup::set_status_text(@msg)
  cop=UI.messagebox((db("Extrude Edges by Lathe: Remove Coplanar Edges ?"))+"\n\n",MB_YESNO,"")### 6=YES 7=NO
  if cop==6
    if Sketchup.version.to_i >= 7
      @model.start_operation((db("ExtrudeEdgesByLathe")), true)
    else
      @model.start_operation((db("ExtrudeEdgesByLathe")))
    end
    edges=[]
    gents.each{|e|edges<<e if e.class==Sketchup::Edge}
    @msg=(db("Extrude Edges by Lathe: Removing Coplanar Edges"))
    4*segs.times do |this|
      edges.each{|e|
        e.erase! if e.valid? and e.faces.length==2 and e.faces[0].normal.dot(e.faces[1].normal) > 0.999999999999
        e.erase! if e.valid? and not e.faces[0]
      }
      Sketchup::set_status_text(@msg)
      @msg=@msg+"."
    end#times
    ### tidy faceless edges...
    group.entities.to_a.each{|e|e.erase! if e.class==Sketchup::Edge and not e.faces[0]}
    @model.commit_operation
  end#if
  ###
  ### reverse faces ?
  @msg=(db("Extrude Edges by Lathe: Reverse Faces ?"))
  Sketchup::set_status_text(@msg)
  rev=UI.messagebox((db("Extrude Edges by Lathe: Reverse Faces ?"))+"\n\n",MB_YESNO,"")### 6=YES 7=NO
  if rev==6
    if Sketchup.version.to_i >= 7
      @model.start_operation((db("ExtrudeEdgesByLathe")), true)
    else
      @model.start_operation((db("ExtrudeEdgesByLathe")))
    end
    faces=[];gents.each{|e|faces<<e if e.class==Sketchup::Face}
    num=1
    faces.each{|face|
      @msg=((db("Extrude Edges by Lathe: Reversing Faces "))+(num.to_s)+(db(" of "))+(faces.length.to_s))
      Sketchup::set_status_text(@msg)
      face.reverse!
      num+=1
    }
    @model.commit_operation
  end#if
  @model.active_view.invalidate ### ???
  if UI.messagebox((db("Extrude Edges by Lathe: Smooth Edges ?")),MB_YESNO,"")==6 ### 6=YES 7=NO
    if Sketchup.version.to_i >= 7
      @model.start_operation((db("ExtrudeEdgesByLathe")), true)
    else
      @model.start_operation((db("ExtrudeEdgesByLathe")))
    end
    gents.each{|e|
      next unless e.class==Sketchup::Edge
      if e.faces[1] and e.faces[0].normal.angle_between(e.faces[1].normal)<89.999.degrees
        e.soft=true
        e.smooth=true
      end#if
    }
    gpx=entities.add_group(group)
    group.explode
    group=gpx
    @model.commit_operation
  end#if
  ###
  @msg=(db("Extrude Edges by Lathe: Explode Group ?"))
  Sketchup::set_status_text(@msg)
  if UI.messagebox((db("Extrude Edges by Lathe: Explode Group ?")),MB_YESNO,"")==6 ### 6=YES 7=NO
    if Sketchup.version.to_i >= 7
      @model.start_operation((db("ExtrudeEdgesByLathe")), true)
    else
      @model.start_operation((db("ExtrudeEdgesByLathe")))
    end
    group.explode
    @model.commit_operation
  end#if
  ###
  self.deactivate(@model.active_view)
  ###
end#def

end#class

class Sketchup::Face
 def orient_connected_lathed_faces
    @connected_faces=[]
	self.all_connected.each{|e|
	  if e.class==Sketchup::Face
		e.edges.each{|edge|
		  if edge.faces[1]
            @connected_faces<<e
            break
          end#if
        }
	  end#if
	}
    @connected_faces=[self] + @connected_faces 
    @connected_faces.uniq!
	@awaiting_faces=@connected_faces
    @processed_faces=[self]
    @done_faces=[]
    @msg=""
    ###
    longstop=256;count=0
	while @awaiting_faces[0]
      @msg=@msg+"."
	  @processed_faces.each{|face|
        if not @done_faces.include?(face)
	      Sketchup::set_status_text(@msg)
		  @face=face
          face_flip
        end#if
	  }
      count+=1
      if count==longstop
       puts("Extrude Edges by Lathe: orient faces aborted.")
       break
     end#if
    end#while
	Sketchup::set_status_text("")
 end#def
 def face_flip
    @awaiting_faces=@awaiting_faces-[@face]
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
    @done_faces<<@face
 end#def
end#class
end#module
