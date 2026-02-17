=begin
  Copyright 2014-2017 (c), TIG
  All Rights Reserved.
  THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED 
  WARRANTIES,INCLUDING,WITHOUT LIMITATION,THE IMPLIED WARRANTIES OF 
  MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
###
  extrudeEdgesByRails.rb
###
  Extrudes an 'initial-profile' curve along one or two other 'rail' 
  curves to form a faced-mesh group, a final 'melding-profile' curve 
  option can control the mesh's final form.
###
Usage:
  Make 2, 3 or 4 'curves' (Arcs/Beziers/PolyLines/Welded-Edges etc).
   These will represent the 'Initial-Profile', the first 'Rail', 
   the second 'Rail' and the 'Melding-Profile' - these last two 
   curves are optional - see below...
   The 'Initial-Profile' should share a common end vertex with each of 
   the 'Rails': but if it doesn't it will be scaled to fit between 
   these Rails and that might then have unexpected results...
   If you pick Rail-1 and then click on it again it will be used as 
   Rail-2***, as if it were at the other end of the Initial-Profile.
   Then you are asked for the 'Melding-Profile': you can pick on 
   the 'Initial-Profile' again to form a simpler mesh from just 
   that one Curve, with it being proportionally scaled and rotated 
   at each of the Rails' nodes - this method gives you little 
   control over the rotation of the Final Profile as this is 
   calculated to rules automatically derived from the Rails' 
   relative node positions etc:  however, if you pick on a 
   different Curve [note that it can't be one of the Rails] that 
   will then be used for the Final Profile at the Rails' end nodes; 
   so using a 'Melding-Profile' like this means that all of the 
   intermediate Profiles will have a proportional 'melding' 
   between the 'Initial-Profile' and the [Final] 'Melding-Profile' 
   along the Rails' intermediate nodes: with this method you can 
   determine the 'morphing' of the Profiles along the Rails from 
   an initial form to a final one, or alternatively you can use 
   the same shaped 'profiles' for both, but with different 
   rotations/scaling, so that you can then effectively 'lathe' a 
   profile along non-circular rails and be sure that the initial 
   and end profiles will be formed and located as you want them...
   
   Looped curves for the profile or the rails are allowed, 
   but they can give unexpected results... also don't try a 
   melding-profile with looped rails unless you want the unexpected!
   
  Run the Tool from Plugins > 'Extrude Edges by Rails'.
   or click on Toolbar 'Extrude Edges by Rails'.
   Activate this Toolbar from View > Toolbars if not loaded.
   Follow the prompts on the VCB.
   Pick the Curves in the order instructed...
   First pick the 'Initial-Profile', then pick the other two 'Rails'.
   You aren't allowed to pick the same Curve twice in this set of 3
   unless Rail-1 is also to be used as Rail-2***.
   Fourthly you pick a 'Melding-Profile', or you can pick the 
   'Initial-Profile' again for a simpler mesh form without a fixed 
   final-profile form etc.
   After selecting these curves it auto-runs the mesh-maker...
   A grouped triangulated mesh is made based on these curves...
   Then there are dialogs asking for Yes/No replies...
    If you want to 'reverse' rail-1's direction.
     [usful if the mesh is 'twisted', when the rails go in 
     opposite directions...]
     Note that this dialog is omitted if Rail-1==Rail-2.
    If you want to 'reverse' the faces in the mesh.
    If you want to 'Quad' faces [i.e. smooth just the diagonals]
     If you want to erase any 'coplanar edges' in the mesh.
     If you want to 'intersect' the mesh with itself.
     If you want to 'smooth' the edges in the mesh. 
    If you want to delete the original curves.
   You can Undo these steps individually immediately afterwards...
    
   NOTE:
   Multi-segmented curves increase processing time exponentially... 
   ... the mesh WILL eventually be made, but the screen might
   'white out' and it might appear to stop for several minutes...  
   but it is working...
   Rails/Profiles with the same number of segments/edges or with 
   them as simple 'multiples' will produce the fewest facets.  
   It is sensible to 'match' the segments in profiles/rails, 
   otherwise a mesh can become VERY faceted or possibly uneven - 
   and also it might take ages to make.  
   For example, for two rails their segments for each part of a 
   profile are dictated by the most segmented rail's total number:
   10 + 10 segments=10 x 2 = 20 facets
   10 + 9  segments=10 x 2 = 20 facets
   10 + 5  segments=10 x 2 = 20 facets
   10 + 2  segments=10 x 2 = 20 facets
   10 + 1  segments=10 x 2 = 20 facets
   The lesser segmented rail will always have some of its segments 
   re-divided to match the more segmented rail's total number. This 
   division is spaced evenly for rails that are segmented as 
   multiples, but this can only approximate to 'even' otherwise...
   The same applies to the profile/melding-profile's segmentation.
   
   For a rail/profile that is to be 'linear' draw an Edge & Divide 
   it as needed equivalent to the number of 'facets' required or to 
   match its opposite rail/profile, then 'Weld' the pieces together 
   into one 'straight' curve.
   If you want a single Edge as a rail/profile then make a 
   single segment Polyline with BZ Tools, or make a Curve out of 
   two edges [with Weld etc] and split the Curve with another 
   perpendicular Edge and Erase this and the unwanted Edge in the 
   Curve - then you have a Curve with a single Edge - alternatively 
   Divide the Edge into two and get a seam in the mesh - you can 
   always use a 'Erase-Coplanar-Edges' tool to minimize the 
   divisions later or you can always add back any lost triangulation 
   by using the 'Triangulate Quad Faces' tool...
   Occasionally Curves made from welded/re-welded/re-re-welded[!]/etc 
   have vertices in an order that can be unexpectedly convoluted 
   and create weird results - if you remake the Curve from scratch 
   it should be OK.  Sometimes cutting and pasting-in-place or 
   grouping and exploding a problem curve can also fix it for use...
   If you want a simple circular 'Lathed' shape use 'extrudeEdgesByLathe' 
   - it will give different results from 'byRails' mesh.
   
Donations:
   Are welcome [by PayPal], please use 'TIGdonations.htm' in the 
   ../Plugins/TIGtools/ folder.
   
Version:
   1.0 20091116 First release.
   1.1 20091120 Glitch fixed with [most] ordered points. 
                Can now double-click on one rail = so used as both.
                Debabelizer added, with ExtrudeEdgesbyRails.lingvo 
                in TIGtools folder.
   1.2 20091210 Rotation of Profiles adjusted to Rail 2 Vertices.
   x2.0 20091229 Fourth 'Melding-Profile' Curve option added.
                Segmentation algorithm improved to optimize facets 
                and minimize the 'spitting' of rails/profiles.
   x2.1 20100107 General speed improvements and tidying up.
                Toolbar added and Tooltip Text added to command. 
                Outliner clash minimized with start+commit changes.
                Undo's step back through Smoothing, Reversing etc.
                Rare incomplete coplanar edge deletion fixed.
                Faces orientation fixed if has a flat face at zero.
   x2.2 20100114 Toolbar now 'Extrusion Tools', with related Tools.
                Connected rails one-profile mesh twist glitches fixed.
                Erase coplanar edges - tolerance adjusted.
                Lingvo files updated for Toolbar text.
                French lingvo file updated [thanks to 'Pilou']
                Spanish lingvo file updated [thanks mainly to 'Defisto']
                Chinese lingvo file added [thanks to 'Arc'].
   x2.3 20100121 Typo preventing Plugin Menu item working corrected.
   x2.4 20100123 Minor glitch in picking order of curves resolved.
                FR lingvo file updated by Pilou.
   x2.5 20100124 Menu typo glitch fixed.
   x2.6 20100206 Resume VCB msg fixed.
   x2.7 20100216 All extrusion-tools now in one in Plugins sub-menu.
   x2.8 20100218 Rare glitch with helical rails fixed.
   x2.9 20100220 Color coding of picked curves added.
                Profile=Cyan
                Rail1=Magenta
                Rail2=DarkVioletRed
                MeldingProfile=DarkCyan
   x3.0 20100222 Tooltips etc now deBabelized properly.
   x3.1 20100312 Erasure of original curves glitch fixed.
   x3.2 20100330 Rare glitch with make_mesh/make_shell fixed.
   x3.3 20111003 Quad Faces option added [smoothed diagonals].
   x3.4 20111004 Quad Faces adjusted to hide diagonals too.
   x3.5 20111023 Smooth now ignores edges with only one face.
   x3.6 20111113 Quad Faces option adjusted to Thomthom's latest specs.
   
   2.0 20130520 Becomes part of ExtrudeTools Extension.
=end
###
module ExtrudeTools
###
toolname="extrudeEdgesByRails"
cmd=UI::Command.new(db("Extrude Edges by Rails")){Sketchup.active_model.select_tool(ExtrudeTools::ExtrudeEdgesByRails.new())}
cmd.tooltip=db("Extrude Edges by Rails")
cmd.status_bar_text="..."
cmd.small_icon=File.join(EXTOOLS, "#{toolname}16x16.png")
cmd.large_icon=File.join(EXTOOLS, "#{toolname}24x24.png")
SUBMENU.add_item(cmd)
TOOLBAR.add_item(cmd)
###
class ExtrudeEdgesByRails

include ExtrudeTools

class Sketchup::Face
 def orient_connected_faces
    @connected_faces=[]
	self.all_connected.each{|e|
	  if e.class==Sketchup::Face
		e.edges.each{|edge|
		  if edge.faces[1]
            @connected_faces << e
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
    msg=""#(db("Orienting Faces"))
    ###
	while @awaiting_faces[0]
      msg=msg+"."
	  @processed_faces.each{|face|
        if not @done_faces.include?(face)
	      Sketchup::set_status_text(msg)
		  @face=face
          face_flip
        end#if
	  }
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

  def initialize()
    ###
	@toolname="extrudeEdgesByRails"
	###
  end#initialize
  
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
    @ents=@model.active_entities
    @sel=@model.selection
    @sel.clear
		if Sketchup.version.to_i > 6
			@model.start_operation((db("Extrude Edges by Rails")), true)
			### 'false' is best to see results as UI/msgboxes...
		else
			@model.start_operation((db("Extrude Edges by Rails")))
		end
    @state=0 ### counter for selecting 3 curves
    @profile=nil
    @mprofile=nil ###v2.4 typo fix
    @rail1=nil
    @rail2=nil
    @msg=(db("Extrude Edges by Rails: Select the 'Profile' Curve..."))
    Sketchup::set_status_text(@msg)
  end#activate
  
  def reset()
    ###
  end#reset
  
  def deactivate(view)
    ###view.invalidate if view ###
    Sketchup.send_action("selectSelectionTool:")
  end#deactivate
  
def resume(view)
  Sketchup::set_status_text(@msg)
  view.invalidate
end
  
  def onMouseMove(flags,x,y,view)
    case @state
     when 0 ### getting the profile
      #view.invalidate
      view.tooltip=(db("Pick Profile"))
     when 1 ###getting the 1st rail
      #view.invalidate
      view.tooltip=(db("Pick 1st Rail"))
     when 2 ### getting the 2nd rail
      #view.invalidate
      view.tooltip=(db("Pick 2nd Rail"))
     when 3 ### getting the melding rofile
      #view.invalidate
      view.tooltip=(db("Pick Melding Profile"))
    end#case
  end#onMouseMove

  def onLButtonDown(flags,x,y,view)
    ph=view.pick_helper
    ph.do_pick(x,y)
    best=ph.best_picked
    if best and best.valid?
      case @state
       when 0
        if best.class==Sketchup::Edge and best.curve
          @sel.add(best.curve.edges)
          @profile=best
          @msg=(db("Extrude Edges by Rails: Select the 1st 'Rail' Curve..."))
          Sketchup::set_status_text(@msg)
          @state=1
        else
          UI.beep
          view.invalidate
          view.tooltip=(db("Pick Profile"))
        end#if
       when 1
        if best.class==Sketchup::Edge and best.curve and not @profile.curve.edges.include?(best.curve.edges[0])
          @sel.add(best.curve.edges)
          @rail1=best
          @msg=(db("Extrude Edges by Rails: Select the 2nd 'Rail' Curve..."))
          Sketchup::set_status_text(@msg)
          @state=2
        else
          UI.beep if @profile.curve.edges.include?(best.curve.edges[0])
          view.invalidate
          view.tooltip= db("Pick 1st Rail")
        end#if
       when 2
        if best.class==Sketchup::Edge and best.curve and not @profile.curve.edges.include?(best.curve.edges[0]) ###and not @rail1.curve.edges.include?(best.curve.edges[0])
          @sel.add(best.curve.edges)
          @rail2=best
          @msg=(db("Extrude Edges by Rails: Select the 'Melding-Profile' Curve..."))
          Sketchup::set_status_text(@msg)
          @state=3
        else
          UI.beep if @profile.curve.edges.include?(best.curve.edges[0])
          view.invalidate
          view.tooltip=(db("Pick 2nd Rail"))
        end#if
        ###
       when 3 ### melding profile
        if best.class==Sketchup::Edge and best.curve and not @rail1.curve.edges.include?(best.curve.edges[0]) and not @rail2.curve.edges.include?(best.curve.edges[0])
          @sel.add(best.curve.edges)
          @mprofile=best
          @state=4
          #view.invalidate
          if @rail1.curve==@rail2.curve
            @msg=(db("Extrude Edges by Rails: Making Mesh from Profile and 1 Rail."))
            Sketchup::set_status_text(@msg)
						### flip so always 2 rails
						rail1=@rail1
						rail2=@rail2
						profile=@profile
						mprofile=@mprofile
						@rail1=profile
						@rail2=mprofile
						@profile=rail1
						@mprofile=rail2
						###
          else
            @msg=(db("Extrude Edges by Rails: Making Mesh from Profile and 2 Rails."))
            Sketchup::set_status_text(@msg)
          end#if
					###
          self.make_mesh()
					###
        else
          UI.beep if @rail1.curve.edges.include?(best.curve.edges[0])or @rail2.curve.edges.include?(best.curve.edges[0])
          view.invalidate
          view.tooltip=(db("Pick Melding Profile"))
        end#if
      end#case
    end#if
  end#onLButtonDown
  
  def draw(view)
    view.line_width=7
    if @profile
      view.drawing_color="cyan"
      @profile.curve.edges.each{|e|view.draw_line(e.start.position,e.end.position)}
    end#if
    if @rail1
      view.drawing_color="magenta"
      @rail1.curve.edges.each{|e|view.draw_line(e.start.position,e.end.position)}
    end#if
    if @rail2
      view.drawing_color="mediumvioletred"
      @rail2.curve.edges.each{|e|view.draw_line(e.start.position,e.end.position)}
    end#if
    if @mprofile
      view.drawing_color="darkcyan"
      @mprofile.curve.edges.each{|e|view.draw_line(e.start.position,e.end.position)}
    end#if
  end#draw
  
  def make_mesh()
    
    @profile_edges=@profile.curve.edges
    @rail1_edges=@rail1.curve.edges
    @rail2_edges=@rail2.curve.edges
    @mprofile_edges=@mprofile.curve.edges
    ### v2... find most segmented rail & profile
    if @profile_edges.length >= @mprofile_edges.length
      max=@profile_edges.length
      min=@mprofile_edges.length
      is_p=true
    else
      max=@mprofile_edges.length
      min=@profile_edges.length
      is_p=false
    end#if
    ### work out divisions of other lesser segmented profile edges and the remainder
    div=(max/min) ### every min edge gets divided up by this
    rem=(max-(div*min)) ### this is how many edges get div+1 divisions
    ### work out which edges get extra division ------------------------
    if rem==0
      xdivs=[]
    elsif (rem.to_f/min.to_f)==0.5
      xdivs=[];ctr=-1
      (min.to_f/2.0).round.to_i.times{ctr=ctr+2;xdivs<<ctr}
      ### e.g. [1,3,5]
    elsif (rem.to_f/min.to_f)<0.5
      xdivs=[]
      step=(min.to_f/rem.to_f).to_f
      rem.times{|i|xdivs<<1+(step*i.to_f).to_i}
      ### e.g. [1,3]
    elsif (rem.to_f/min.to_f)>0.5
      xdivs=[]
      min.times{|i|;xdivs<<i}
      idivs=[]
      inv=min-rem-1
      step=(min.to_f/inv.to_f).to_f
      inv.times{|i|idivs<<1+(step*i.to_f).to_i}
      xdivs=xdivs-idivs
      ### e.g. [0,2,4]
    end#if
    ###--------------------------------------
    divpoints=[]
    undivpoints=[]
    if is_p
      ppoints=order_points(@mprofile_edges)
      tpoints=order_points(@profile_edges)
    else
      ppoints=order_points(@profile_edges)
      tpoints=order_points(@mprofile_edges)
    end#if
    0.upto(ppoints.length-2) do |i|
      pts=ppoints[i]
      pte=ppoints[i+1]
      len=pts.distance(pte)
      vec=pte-pts
      ptx=pts.clone
      divpoints<<ptx
      ddiv=div
      ddiv=div+1 if xdivs.include?(i+1)
      ddiv.to_i.times{|j|
        dis=len*j.to_f/ddiv.to_f
        ptn=pts.offset(vec,dis)
        ptx=ptn.clone
        divpoints<<ptx if ptx != divpoints.last
      }
      ptx=pte.clone
      divpoints<<ptx
    end#do
    divpoints.uniq!
    0.upto(tpoints.length-2) do |i|
      pts=tpoints[i]
      pte=tpoints[i+1]
      len=pts.distance(pte)
      vec=pte-pts
      ptx=pts.clone
      undivpoints<<ptx
      ddiv=1
      ddiv.to_i.times{|j|
        dis=len*j.to_f/ddiv.to_f
        ptn=pts.offset(vec,dis)
        ptx=ptn.clone
        undivpoints<<ptx if ptx != undivpoints.last
      }
      ptx=pte.clone
      undivpoints<<ptx
    end#do
    undivpoints.uniq!
    if is_p
      @gpm=@ents.add_group() ### melding profile group
      @gpm.entities.add_curve(divpoints)
      @gp=@ents.add_group()### profile group
      @gp.entities.add_curve(undivpoints)
    else
      @gp=@ents.add_group() ### profile group
      @gp.entities.add_curve(divpoints)
      @gpm=@ents.add_group()### melding profile group
      @gpm.entities.add_curve(undivpoints)
    end#if
    ### now have 2 properly divided profiles
    ### ------------------------------------------------------------ ###
    ### ditto for rails...
    if @rail1_edges.length >= @rail2_edges.length
      max=@rail1_edges.length
      min=@rail2_edges.length
      is_r=true
    else
      max=@rail2_edges.length
      min=@rail1_edges.length
      is_r=false
    end#if
    ### work out divisions of other lesser segmented profile edges and the remainder
    div=(max/min) ### every min edge gets divided up by this
    rem=(max-(div*min)) ### this is how many edges get div+1 divisions
    ### work out which edges get extra division ------------------------
    if rem==0
      xdivs=[]
    elsif (rem.to_f/min.to_f)==0.5
      xdivs=[];ctr=-1
      (min.to_f/2.0).round.to_i.times{ctr=ctr+2;xdivs<<ctr}
      ### e.g. [1,3,5]
    elsif (rem.to_f/min.to_f)<0.5
      xdivs=[]
      step=(min.to_f/rem.to_f).to_f
      rem.times{|i|xdivs<<1+(step*i.to_f).to_i}
      ### e.g. [1,3]
    elsif (rem.to_f/min.to_f)>0.5
      xdivs=[]
      min.times{|i|;xdivs<<i}
      idivs=[]
      inv=min-rem-1
      step=(min.to_f/inv.to_f).to_f
      inv.times{|i|idivs<<1+(step*i.to_f).to_i}
      xdivs=xdivs-idivs
      ### e.g. [0,2,4]
    end#if
    ###--------------------------------------
    divpoints=[]
    undivpoints=[]
    if is_r
      ppoints=order_points(@rail2_edges)
      tpoints=order_points(@rail1_edges)
    else
      ppoints=order_points(@rail1_edges)
      tpoints=order_points(@rail2_edges)
    end#if
    0.upto(ppoints.length-2) do |i|
      pts=ppoints[i]
      pte=ppoints[i+1]
      len=pts.distance(pte)
      vec=pte-pts
      ptx=pts.clone
      divpoints<<ptx
      ddiv=div
      ddiv=div+1 if xdivs.include?(i+1)
      ddiv.to_i.times{|j|
        dis=len*j.to_f/ddiv.to_f
        ptn=pts.offset(vec,dis)
        ptx=ptn.clone
        divpoints<<ptx if ptx != divpoints.last
      }
      ptx=pte.clone
      divpoints<<ptx
    end#do
    divpoints.uniq!
    0.upto(tpoints.length-2) do |i|
      pts=tpoints[i]
      pte=tpoints[i+1]
      len=pts.distance(pte)
      vec=pte-pts
      ptx=pts.clone
      undivpoints<<ptx
      ddiv=1
      ddiv.to_i.times{|j|
        dis=len*j.to_f/ddiv.to_f
        ptn=pts.offset(vec,dis)
        ptx=ptn.clone
        undivpoints<<ptx if ptx != undivpoints.last
      }
      ptx=pte.clone
      undivpoints<<ptx
    end#do
    undivpoints.uniq!
    if is_r
      @gp2=@ents.add_group() ###
      @gp2.entities.add_curve(divpoints)
      @gp1=@ents.add_group()### profile group
      @gp1.entities.add_curve(undivpoints)
    else
      @gp1=@ents.add_group() ### profile group
      @gp1.entities.add_curve(divpoints)
      @gp2=@ents.add_group()###
      @gp2.entities.add_curve(undivpoints)
    end#if
    ### now have 2 properly divided rails
    
    ### now we make edges ,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,
    @tprofile_edges=@gp.entities.to_a
    @tmprofile_edges=@gpm.entities.to_a
    @trail1_edges=@gp1.entities.to_a
    @trail2_edges=@gp2.entities.to_a
    
    points=order_points(@tprofile_edges)
    pointsm=order_points(@tmprofile_edges)
    points1=order_points(@trail1_edges)
    points2=order_points(@trail2_edges)

    ### find if looped...
    if @profile_edges[0].curve.vertices.length != @profile_edges[0].curve.vertices.uniq.length
      looped=true
    else
      looped=false
    end#if
    ### melding profile
    if @mprofile_edges[0].curve.vertices.length != @mprofile_edges[0].curve.vertices.uniq.length
      loopedm=true
    else
      loopedm=false
    end#if
    ###
    if @rail1_edges[0].curve.vertices.length != @rail1_edges[0].curve.vertices.uniq.length
      looped1=true
    else
      looped1=false
    end#if
    ###
    if @rail2_edges[0].curve.vertices.length != @rail2_edges[0].curve.vertices.uniq.length
      looped2=true
    else
      looped2=false
    end#if
    ###
    ### now use if they're looped etc
    verts=@tprofile_edges[0].curve.vertices
    vertsm=@tmprofile_edges[0].curve.vertices
    verts1=@trail1_edges[0].curve.vertices
    verts2=@trail2_edges[0].curve.vertices
    ###
    if looped ### find nearest point to looped1
      dists=[]
      verts.each{|v|p=v.position.to_a
        verts1.each{|v1|
          p1=v1.position.to_a
          dists<<[p.distance(p1),p,p1]
        }
      }
      dists.sort!
      near=dists[0][1]
      ### split points at 'near' and duplicate on end
      index=points.index(near)
      points=points[index..-1]+points[0..index]
    end#if
    ###
    if loopedm ### find nearest point to looped1
      dists=[]
      vertsm.each{|v|p=v.position.to_a
        verts1.each{|v1|
          p1=v1.position.to_a
          dists<<[p.distance(p1),p,p1]
        }
      }
      dists.sort!
      near=dists[0][1]
      ### split pointsm at 'near' and duplicate on end
      index=pointsm.index(near)
      pointsm=pointsm[index..-1]+pointsm[0..index]
    end#if
    if looped1 ### find nearest point to end_points
      dists=[]
      verts1.each{|v|p=v.position.to_a
        verts.each{|v1|
          p1=v1.position.to_a
          dists<<[p.distance(p1),p,p1]
        }
      }
      dists.sort!
      near=dists[0][1]
      ### split points1 at 'near' and put a duplicate on end
      index=points1.index(near)
      points1=points1[index..-1]+points1[0..index]
    end#if
    if looped2 ### find nearest point to end_points
      dists=[]
      verts2.each{|v|p=v.position.to_a
        verts.each{|v1|
          p1=v1.position.to_a
          dists<<[p.distance(p1),p,p1]
        }
      }
      dists.sort!
      near=dists[0][1]
      ### split points2 at 'near' and duplicate on end
      index=points2.index(near)
      points2=points2[index..-1]+points2[0..index]
    end#if
    ###
    ### check if need to reverse any point lists ???
    ###
    if points[0].distance(points1[0])>points[0].distance(points1[-1])
      points1.reverse!
    end#if
    if points[-1].distance(points2[0])>points[-1].distance(points2[-1])
      points2.reverse!
    end#if
    ###
    if points[0].distance(points1[0])>points[0].distance(points2[0])
      points.reverse! if @rail1.curve != @rail2.curve
    end#if
    ###
    if pointsm[0].distance(points1[-1])>pointsm[0].distance(points2[-1])
      pointsm.reverse! if @profile.curve != @mprofile.curve
    end#if
    ###############
    if points[0].distance(points1[0])>points[0].distance(points1[-1])
      points1.reverse!
    end#if
    if points[-1].distance(points2[0])>points[-1].distance(points2[-1])
      points2.reverse!
    end#if
    if pointsm[0].distance(points1[-1])>pointsm[0].distance(points2[-1])
      pointsm.reverse! if @profile.curve != @mprofile.curve
    end#if
    ### ???
    if @rail1.curve == @rail2.curve
      if points[0].distance(points1[0])>points[0].distance(points1[-1])
        points1.reverse!
      end#if
      if points[-1].distance(points2[0])>points[-1].distance(points2[-1])
        points2.reverse!
      end#if
      if points1[0].distance(points2[0])>points1[0].distance(points2[-1])
        points2.reverse!
      end#if
    end#if
    ### ensure reversed properly
    if @profile.curve == @mprofile.curve
      if points != pointsm
        pointsm.reverse!
      end#if
    end#if
    ### check for touching rails and ensure both ends start at right place
    if points1[0]==points2[0] and @rail1.curve != @rail2.curve
      points1.reverse!
      points2.reverse!
      if points1[0] != points[0]
        points.reverse!
      end#if
    elsif points1[-1]==points2[-1] and @rail1.curve != @rail2.curve
      if points1[0] != points[0]
        points1.reverse!
        points2.reverse!
      end#if
    elsif points1[0] == points2[-1] or points1[-1] == points2[0] and @rail1.curve != @rail2.curve
      if points1[0] == points[0]
        points2.reverse!
      else
        points1.reverse!
      end#if
    end#if
    ###    
    tpoints1=[]
    points1.each{|p|tpoints1<<p.to_a}
    points1=tpoints1.uniq
    points1=points1<<points1[0] if looped1
    
    tpoints2=[]
    points2.each{|p|tpoints2<<p.to_a}
    points2=tpoints2.uniq
    points2=points2<<points2[0] if looped2
    
    ### if EITHER rail1 OR rail2 might be reversed so == 'twisted' ?
    ### allow to reverse rail-1 after we see what mesh is like...
    
    #################
    self.make_shell(points,points1,points2,pointsm)
    #################
    group=@shell
    gents=group.entities
    ###

    ### if a rail is reversed in the other one=a twist
   if @rail1.curve != @rail2.curve ###################
    @model.commit_operation ### see results
    @msg=(db("Extrude Edges by Rails: Reverse Rail-1's Direction ?"))
    Sketchup::set_status_text(@msg)
    if UI.messagebox((db("Extrude Edges by Rails:"))+"\n\n"+(db("Reverse Rail-1's Direction ?"))+"\n\n"+(db("This is only necessary with twisted meshes..."))+"\n\n",MB_YESNO,"")==6 ### 6=YES 7=NO
      if Sketchup.version.to_i > 6
				@model.start_operation((db("Extrude Edges by Rails: Reversing Rail-1's Direction...")), true)
				### 'false' is best to see results as UI/msgboxes...
			else
				@model.start_operation((db("Extrude Edges by Rails: Reversing Rail-1's Direction...")))
			end
      @msg=(db("Extrude Edges by Rails: Reversing Rail-1's Direction..."))
      Sketchup::set_status_text(@msg)
      group.erase! if group.valid? ###
      @shell=@ents.add_group()###remake group
      ### rebuild one of rails points
     @trail1_edges=@trail1_edges.reverse
     points1=order_points(@trail1_edges)
     if @rail1_edges[0].curve.vertices.length != @rail1_edges[0].curve.vertices.uniq.length
       looped1=true
     else
       looped1=false
     end#if
     if looped1 ### find nearest point to end_points
      dists=[]
      verts1.each{|v|p=v.position.to_a
        verts.each{|v1|
          p1=v1.position.to_a
          dists<<[p.distance(p1),p,p1]
        }
      }
      dists.sort!
      near=dists[0][1]
      ### split points1 at 'near' and duplicate on end
      index=points1.index(near)
      points1=points1[index..-1]+points1[0..index]
     end#if
     ###
     ### NO NEED to check if need to reverse any point lists ???
     ###
      tpoints1=[]
      points1.each{|p|tpoints1<<p.to_a}
      points1=tpoints1.uniq
      points1=points1<<points1[0] if looped1
      ###
      self.make_shell(points,points1,points2,pointsm)
      ###
      @msg=(db("Extrude Edges by Rails: Reversing Rail-1's Direction..."))
      Sketchup::set_status_text(@msg)
      group=@shell
      gents=group.entities
      @msg=(db("Extrude Edges by Rails: Formating Mesh... Please Wait..."))
      Sketchup::set_status_text(@msg)
    else
      if Sketchup.version.to_i > 6
				@model.start_operation((db("Extrude Edges by Rails: Formating Mesh... Please Wait..")), true)
				### 'false' is best to see results as UI/msgboxes...
			else
				@model.start_operation(db("Extrude Edges by Rails: Formating Mesh... Please Wait.."))
			end
      @msg=(db("Extrude Edges by Rails: Formating Mesh... Please Wait..."))
      Sketchup::set_status_text(@msg)
    end#if
   end#if reverse rail?
    ###
    @msg=(db("Extrude Edges by Rails: Formating Mesh... Please Wait..."))
    Sketchup::set_status_text(@msg)
    ### remove temp 'split' groups etc
    @gp.erase! if @gp.valid?
    @gpm.erase! if @gpm.valid?
    @gp1.erase! if @gp1.valid?
    @gp2.erase! if @gp2.valid?
    ###
    @model.commit_operation
     
    ### Tidying up at end...
#=begin ### remove this leading # here AND at #=end below, ~Line491 near end, to skip extra tools
    
    faces=[];gents.each{|e|faces<<e if e.class==Sketchup::Face}
    
    ### [re]orient faces if one is flat and at zero
    faces.each{|face|
      if face.normal.z.abs==1.0 and face.bounds.min.z==0.0
        face.orient_connected_faces
        break ### only needs doing once
      end#if
    }
    
    ### reverse faces ?
    @msg=((db("Extrude Edges by Rails: Reverse "))+faces.length.to_s+(db(" Faces ?")))
    Sketchup::set_status_text(@msg)
  if UI.messagebox((db("Extrude Edges by Rails:"))+"\n\n"+(db("Reverse Faces ?"))+"\n\n\n\n",MB_YESNO,"")==6 ### 6=YES 7=NO 
    ### pause here so we see result...
		if Sketchup.version.to_i > 6
			@model.start_operation((db("Extrude Edges by Rails: Reversing Face ")), true)
			### 'false' is best to see results as UI/msgboxes...
		else
			@model.start_operation((db("Extrude Edges by Rails: Reversing Face ")))
		end
    tick=1
    faces.each{|e|
      e.reverse!
      @msg=((db("Extrude Edges by Rails: Reversing Face "))+tick.to_s+(db(" of "))+faces.length.to_s)
      Sketchup::set_status_text(@msg)
      tick+=1
    }
    @model.commit_operation
  end#if
  ### QUADS ?
  quads=false
  if UI.messagebox((db("Extrude Edges by Rails:"))+"\n\n"+(db("Quad Faces ?"))+"\n\n\n\n",MB_YESNO,"")==6 ### 6=YES 7=NO 
    quads=true
    ### pause here so we see result...
		if Sketchup.version.to_i > 6
			@model.start_operation((db("Extrude Edges by Rails: Quad Face ")), true)
			### 'false' is best to see results as UI/msgboxes...
		else
			@model.start_operation((db("Extrude Edges by Rails: Quad Face ")))
		end
    tick=0
		tr=gents.parent.instances[0].transformation.inverse
    @diags.each{|a|
      tick+=1
      @msg=((db("Extrude Edges by Rails: Quad Face "))+tick.to_s+(db(" of "))+@diags.length.to_s)
      Sketchup::set_status_text(@msg)
			begin
				e=gents.add_line(a[0].transform(tr), a[1].transform(tr))
			rescue
				next
			end
			next unless e && e.valid?
      e.smooth=true
      e.soft=true
      e.casts_shadows=false
    }
    @model.commit_operation
  end#if
  ###
  if not quads
    @msg=(db("Extrude Edges by Rails: Erase Coplanar Edges ?"))
    Sketchup::set_status_text(@msg)
  if UI.messagebox((db("Extrude Edges by Rails:"))+"\n\n"+(db("Erase Coplanar Edges ?"))+"\n\n\n\n",MB_YESNO,"")==6 ### 6=YES 7=NO
    ### pause here so we see result...
		if Sketchup.version.to_i > 6
			@model.start_operation((db("Extrude Edges by Rails: Erase Coplanar Edges ?")), true)
			### 'false' is best to see results as UI/msgboxes...
		else
			@model.start_operation((db("Extrude Edges by Rails: Erase Coplanar Edges ?")))
		end
    counter=0
    4.times do ### to make sure we got all of them !
     gents.to_a.each{|e|
      if e.valid? and e.class==Sketchup::Edge
       if not e.faces[0]
         e.erase!
         counter+=1
         @msg=((db("Extrude Edges by Rails: Coplanar Edges Erased= "))+counter.to_s)
         Sketchup::set_status_text(@msg)
       elsif e.faces.length==2 and e.faces[0].normal.dot(e.faces[1].normal)> 0.99999999999 ####
         e.erase!
         counter+=1
         @msg=((db("Extrude Edges by Rails: Coplanar Edges Erased= "))+counter.to_s)
         Sketchup::set_status_text(@msg)
       end#if
      end#if
     }
    end#times
    @model.commit_operation
  end#if 
    ### intersect with self
    @msg=(db("Extrude Edges by Rails: Intersect Mesh with Self ?"))
    Sketchup::set_status_text(@msg)
  if UI.messagebox((db("Extrude Edges by Rails:"))+"\n\n"+(db("Intersect Mesh with Self ?"))+"\n\n"+(db("This is only necessary with convoluted meshes...")),MB_YESNO,"")==6 ### 6=YES 7=NO
    ### pause here so we see result...
		if Sketchup.version.to_i > 6
			@model.start_operation((db("Extrude Edges by Rails: Intersect Mesh with Self ?")), true)
			### 'false' is best to see results as UI/msgboxes...
		else
			@model.start_operation((db("Extrude Edges by Rails: Intersect Mesh with Self ?")))
		end
      @msg=(db("Extrude Edges by Rails: Intersecting Mesh with Self... Please Wait..."))
      Sketchup::set_status_text(@msg)
      gentsa1=group.entities.to_a
      gnum1=gents.length
      group.entities.intersect_with(true,group.transformation,group,group.transformation,true,group)
      gentsa2=group.entities.to_a
      gnum2=gents.length
      @model.commit_operation
  end#intersect
    ###
    
    ### smooth edges ?
    edges=[];gents.each{|e|edges<<e if e.class==Sketchup::Edge and e.faces[1]}
    @msg=((db("Extrude Edges by Rails: Smooth "))+edges.length.to_s+(db(" Edges ?")))
    Sketchup::set_status_text(@msg)
		if yn=UI.messagebox((db("Extrude Edges by Rails:"))+"\n\n"+(db("Smooth Edges ?"))+"\n\n\n\n",MB_YESNO,"")==6 ### 6=YES 7=NO
			### pause here so we see result...
			if Sketchup.version.to_i > 6
				@model.start_operation((db("Extrude Edges by Rails: Smoothing Edge ")), true)
				### 'false' is best to see results as UI/msgboxes...
			else
				@model.start_operation((db("Extrude Edges by Rails: Smoothing Edge ")))
			end
		tick=1
		edges.each{|e|
			e.soft=true
			e.smooth=true
			@msg=((db("Extrude Edges by Rails: Smoothing Edge "))+tick.to_s+(db(" of "))+edges.length.to_s)
			Sketchup::set_status_text(@msg)
			tick+=1
		}
		gpx=@model.active_entities.add_group(group)
		group.explode
		group=gpx
		gents=group.entities
		@model.commit_operation
  end#if
  ###
  end#quads ###
  ###  
    ### erase original curves ?
    @msg=(db("Extrude Edges by Rails: Erase Original Curves ?"))
    Sketchup::set_status_text(@msg)
  if UI.messagebox((db("Extrude Edges by Rails:"))+"\n\n"+(db("Erase Original Curves ?"))+"\n\n\n\n",MB_YESNO,"")==6 ### 6=YES 7=NO  
    if Sketchup.version.to_i > 6
			@model.start_operation((db("Extrude Edges by Rails: Erase Original Curves ?")), true)
			### 'false' is best to see results as UI/msgboxes...
		else
			@model.start_operation((db("Extrude Edges by Rails: Erase Original Curves ?")))
		end
    @profile_edges.each{|e|e.erase! if e.valid?}
    @mprofile_edges.each{|e|e.erase! if e.valid?}
    @rail1_edges.each{|e|e.erase! if e.valid?}
    @rail2_edges.each{|e|e.erase! if e.valid?}
    @model.commit_operation
  end#if
  
#=end ### remove this leading # AND above at #=begin ~Line432 to stop extra tools running
    Sketchup::set_status_text("")
    ###
    Sketchup.send_action "selectSelectionTool:"
    ### done
  end#make_mesh
  
  
  def order_points(edges)
    verts=[]
	edges.each{|edge|verts<<edge.vertices}
	verts.flatten!
    ### Find end vertex
	vertsShort=[]
	vertsLong=[]
	verts.each{|v|
	  if vertsLong.include?(v)
		vertsShort<<(v)
	  else
		vertsLong<<(v)
	  end#if
	}
	if not startVert=(vertsLong-vertsShort).first
		startVert=vertsLong.first
		closed=true
		startEdge=startVert.edges.first
	else
		closed=false
		startEdge=(edges & startVert.edges).first
	end
    #Sort vertices, limited to those of edges
	if startVert==startEdge.start
		ordered_points=[startVert]
		counter=0
		while ordered_points.length < verts.length
			edges.each{|edge|
			  if edge.end==ordered_points.last
				ordered_points<<edge.start
			  elsif edge.start==ordered_points.last
				ordered_points<<edge.end
			  end
			}
			counter+=1
			if counter > verts.length
				ordered_points.reverse!
				reversed=true
			end#if
		end#while
	else
		ordered_points=[startVert]
		counter=0
		while ordered_points.length < verts.length
			edges.each{|edge|
			  if edge.end==ordered_points.last
				ordered_points<<edge.start
			  elsif edge.start==ordered_points.last
				ordered_points<<edge.end
			  end
			}
			counter+=1
			if counter > verts.length
				ordered_points.reverse!
				reversed=true
			end
		end
	end
	ordered_points.uniq!
	ordered_points.reverse! if reversed
    #Convert vertices to points
	ordered_points.collect!{|x|x.position}
	if closed
		ordered_points<<ordered_points[0]
	else
		closed=true
	end
    return ordered_points
  end#order_points
  

  def make_shell(points,points1,points2,pointsm)
    @shell=@ents.add_group()
    sents=@shell.entities
    msg=(db("Extrude Edges by Rails: "))
    Sketchup::set_status_text(msg)
    ###
    ### make a cpoint profile
    cprofile=sents.add_group()
    cents=cprofile.entities
    points.each_with_index{|p,ii|
			x=cents.add_cpoint(p)
			x.set_attribute('ee','ee',ii)
		}
    trc=Geom::Transformation.new(ORIGIN-points[0])
    cprofile.transform!(trc)
    #@ents.add_text("p0",points[0])
    ### make a cpoint mprofile
		if @rail1.curve == @rail2.curve && @profile.curve != @mprofile.curve
			pn=nil
			if points[0]==pointsm[0]
				pn=points[0]
			elsif points[0]==pointsm[-1]
				pn=points[0]
			elsif points[-1]==pointsm[0]
				pn=points[-1]
			elsif points[-1]==pointsm[-1]
				pn=points[-1]
			end
			if pn
				p pn
				pointsm.each_with_index{|p,ii|
					pointsm[ii]=pn
				}
				p pointsm
			end
		end
    cmprofile=sents.add_group()
    cments=cmprofile.entities
    pointsm.each_with_index{|p,ii|
			x=cments.add_cpoint(p)
			x.set_attribute('ee','ee',ii)
		}
    trcm=Geom::Transformation.new(ORIGIN-pointsm[0])
    cmprofile.transform!(trcm)
    #@ents.add_text("m0",points[0])
    ###
    pmsg=(db("Making Profile "))
    ofmsg=(db(" of "))
    fmsg=(db("Making Face "))
    profiles=[]
    mprofiles=[]
    ###
		defcp=cents.parent
		defcmp=cments.parent
    ###
    0.upto(points1.length-1) do |i|
      xmsg=msg+pmsg+(i+1).to_s+ofmsg+points1.length.to_s
      Sketchup::set_status_text(xmsg)
      ang=0.0
      tgp=nil
     begin
      #@ents.add_text("r1="+i.to_s,points1[i])
      #@ents.add_text("r2="+i.to_s,points2[i])
      #tgp=cprofile.copy
			tgp=sents.add_instance(defcp, trc)
			tgp.make_unique if defcp.instances[1]
			###
      p=points1[i]
      tr=Geom::Transformation.new(p)
      tgp.transform!(tr)
      tents=tgp.explode
			xtents=[]
			(points.length).times{|ii|
				tents.each{|x|
					j=x.get_attribute('ee','ee')
					if j==ii
						xtents << x
						break
					end
				}
			}
      tgp=sents.add_group()
      xtents.each_with_index{|e,ii|
        x=tgp.entities.add_cpoint(e.position)
				x.set_attribute('ee','ee',ii)
        e.erase! if e.valid?
      }
      #tgpm=cmprofile.copy
			tgpm=sents.add_instance(defcmp, trcm)
			tgpm.make_unique if defcmp.instances[1]
			###
      p=points1[i]
      tr=Geom::Transformation.new(p)
      tgpm.transform!(tr)
      tments=tgpm.explode
			xtments=[]
			(points.length).times{|ii|
				tments.each{|x|
					j=x.get_attribute('ee','ee')
					if j==ii
						xtments << x
						break
					end
				}
			}
      tgpm=sents.add_group()
      xtments.each_with_index{|e,ii|
        x=tgpm.entities.add_cpoint(e.position)
				x.set_attribute('ee','ee',ii)
        e.erase! if e.valid?
      }
      ###
      if @rail1.curve == @rail2.curve
        ang=0.0
        angm=0.0
      else
        ang=(points[0].vector_to(points[-1])).angle_between(points1[i].vector_to(points2[i]))
        angm=(pointsm[0].vector_to(pointsm[-1])).angle_between(points1[i].vector_to(points2[i]))
      end#if
      ###
      if @rail1.curve != @rail2.curve
        norm=(points[0].vector_to(points[-1])).cross(points1[i].vector_to(points2[i]))
        if ang.radians==180.0 or (ang==0 and i != 0 and i != points1.length-1)
          norm=[0,0,1]
        end#if 180
        begin
          if ang != 0 and norm.length != 0
            tr=Geom::Transformation.rotation(points1[i],norm,ang)
            tgp.transform!(tr)
          end#if
        rescue
           puts "EE error 1"
        end#begin
      end#if
      ###
      if @rail1.curve != @rail2.curve
        norm=(pointsm[0].vector_to(pointsm[-1])).cross(points1[i].vector_to(points2[i]))
        if angm.radians==180.0 or (angm==0 and i != 0 and i != points1.length-1)
          norm=[0,0,1]
        end#if 180
        begin
          if angm != 0 and norm.length != 0
            tr=Geom::Transformation.rotation(points1[i],norm,angm)
            tgpm.transform!(tr)
          end#if
        rescue
          puts "EE error 2"
        end#begin
      end#if
      ###
      ### scale profile to suit
      len=(points[0].distance(points[-1]))
      dis=len
      dis=(points1[i].distance(points2[i]))if @rail1.curve != @rail2.curve
      if dis != 0.0
        tr=Geom::Transformation.scaling(points1[i],(dis/len))
        tgp.transform!(tr)
        ### reform
        tents=tgp.explode
				xtents=[]
				(points.length).times{|ii|
					tents.each{|x|
						j=x.get_attribute('ee','ee')
						if j==ii
							xtents << x
							break
						end
					}
				}
				tgp=sents.add_group()
				xtents.each_with_index{|e,ii|
					x=tgp.entities.add_cpoint(e.position)
					x.set_attribute('ee','ee',ii)
					e.erase! if e.valid?
				}
      else #dis == 0.0 ### stops bugsplats if rails share a common point !!!
				tgp.erase!
				pn=points1[-1]
				tgp=sents.add_group()
				(points.length).times{|ii|
					x=tgp.entities.add_cpoint(pn)
					x.set_attribute('ee','ee',ii)
				}
      end#if
      ### scale melding profile to suit
      len=(pointsm[0].distance(pointsm[-1]))
      dis=len
      dis=(points1[i].distance(points2[i]))if @rail1.curve != @rail2.curve
      if dis != 0.0
        tr=Geom::Transformation.scaling(points1[i],(dis/len))
        tgpm.transform!(tr)
        ### reform
        tments=tgpm.explode
				xtments=[]
				(pointsm.length).times{|ii|
					tments.each{|x|
						j=x.get_attribute('ee','ee')
						if j==ii
							xtments << x
							break
						end
					}
				}
				tgpm=sents.add_group()
				xtments.each_with_index{|e,ii|
					x=tgpm.entities.add_cpoint(e.position)
					x.set_attribute('ee','ee',ii)
					e.erase! if e.valid?
				}
      else #dis == 0.0 ### stops bugsplats if rails share a common point !!!
				tgpm.erase!
				pn=points1[-1]
				tgpm=sents.add_group()
				(points.length).times{|ii|
					x=tgpm.entities.add_cpoint(pn)
					x.set_attribute('ee','ee',ii)
				}
      end#if
      profiles<<tgp
      mprofiles<<tgpm
     rescue Exception => e
      puts "EEE"
      puts e
      tgp.erase! if tgp && tgp.valid?
      tgpm.erase! if tgpm && tgpm.valid?
			tents.each{|t| t.erase! if t.valid? }
			tments.each{|t| t.erase! if t.valid? }
     end#begin
    end#do
		#puts profiles.length
		#puts mprofiles.length
    ###
    cprofile.erase!
    cmprofile.erase!
    profiles.uniq!
    mprofiles.uniq!
    #################### now meld profile and melding profile ##########
    meldedprofiles=[]#profiles[0]]### 1st is pure profile
    plen=profiles.length-1
    0.upto(plen) do |i|
      prof1=profiles[i]
      profm=mprofiles[i]
      ents1=prof1.explode
			xtents=[]
			(points.length).times{|ii|
				ents1.each{|x|
					j=x.get_attribute('ee','ee')
					if j==ii
						xtents << x
						break
					end
				}
			}
			ents1=xtents
			###
      entsm=profm.explode
			xtments=[]
			(points.length).times{|ii|
				entsm.each{|x|
					j=x.get_attribute('ee','ee')
					if j==ii
						xtments << x
						break
					end
				}
			}
			entsm=xtments
			###
      tempg=sents.add_group()
      tents=tempg.entities
      propn=(i.to_f)/(plen.to_f)
      0.upto(ents1.length-1) do |j|
        p0=ents1[j].position
        p1=entsm[j].position
        dis=p0.distance(p1)
        if p0.vector_to(p1).length !=0
          pn=p0.offset(p0.vector_to(p1), dis*propn)
        else
          pn=p0
        end#if
        x=tents.add_cpoint(pn)
				#x.set_attribute('ee','ee',i) ### ?
        ents1[j].erase! if ents1[j].valid?
        entsm[j].erase! if entsm[j].valid?
      end#do
      meldedprofiles<<tempg
    end#do
    #meldedprofiles<<mprofiles[-1]###last is pure mprofile ?
    #################### swap profiles around...
    xprofiles=profiles
    profiles=meldedprofiles
		#p profiles[0].entities.to_a
    ####################
    @diags=[]
    ### now use cpoints to draw mesh
    facecount=(points.length-1)*(points1.length-2)*2
    count=1
    ###
    0.upto(profiles.length-2) do |i|
      count=count+((profiles[i].entities.length-2)*2)
      xmsg=msg+fmsg+count.to_s+ofmsg+facecount.to_s
      Sketchup::set_status_text(xmsg)
      0.upto(profiles[i].entities.length-2) do |j|
        pents=profiles[i].entities
        begin
          if pents[j].position == pents[j+1].position
            ### starts at a common point
            sents.add_face(pents[j].position, profiles[i+1].entities[j].position, profiles[i+1].entities[j+1].position)
          else ### NOT starts at a common point
            if profiles[i+1].entities[j].position == profiles[i+1].entities[j+1].position
              ### BUT it ends at one
              sents.add_face(pents[j].position, profiles[i+1].entities[j+1].position, pents[j+1].position)
            else
              ### NO common point so draw 2 triangular faces [usual case]
              f1=sents.add_face(pents[j].position, profiles[i+1].entities[j].position, profiles[i+1].entities[j+1].position)
              f2=sents.add_face(pents[j].position, profiles[i+1].entities[j+1].position, pents[j+1].position)
              es1=f1.edges
              es2=f2.edges
              @diags << [(es1-(es1-es2))[0].start.position, (es1-(es1-es2))[0].end.position] ### the common edge
            end#if
          end#if
        rescue Exception => e
          ### nothing ?
					p 'EE?'
					p e
        end
				#break
      end#do
			#break
    end#do
		#p 999
		#return
    ### remove temp cpoints
    profiles.each{|e|e.erase! if e.valid?}
    xprofiles.each{|e|e.erase! if e.valid?}
    mprofiles.each{|e|e.erase! if e.valid?}
    ###
    Sketchup::set_status_text("")
  end#make_shell

end#class

end#module
