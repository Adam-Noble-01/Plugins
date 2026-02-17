=begin
  Copyright 2014-2017 (c), TIG
  All Rights Reserved.
  THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED 
  WARRANTIES,INCLUDING,WITHOUT LIMITATION,THE IMPLIED WARRANTIES OF 
  MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
###
  extrudeEdgesByRailsToLattice.rb
###
Description:
  Takes a set of curves [Profiles/Rails/Both] and forms 'Lattice' groups.  
  The Lattice can be plain curve 'lines' only, i.e. a set of profiles, 
  rails or both, that you can use for other purposes later; or it can be 
  made as a 3D form offset by frame given width and depth, and pane inset, 
  you can also assign limited materials to the frame/pane for ease of 
  future selection/manipulation.
###
Usage:
  Run 'Extrude Edges by Rails to Lattice', from the Plugins Menu, or the 
  Extrusions Toolbar...
  You are then prompted to pick 2/3/4 curves to be used in forming the 
  'Lattice' - a Profile, Rail1, Rail2 [this can be Rail1 again] and a 
  Melding-Profile [can be the Profile again] - please see EEbyRails for 
  more details on this...
  A dialog then prompts you to choose 'from Profiles', 'from Rails', 
  'from Diagonals' or 'from Profiles/Rails' [i.e. default = full 'grid'].
  Choose option: 'Cancel' exits, 'OK' continues.
  If you chose Lattice 'from Profiles' or 'from Rails' or 'from Diagonals' 
  then the result can only be curves as lines: these are now made - 
  they are grouped to avoid intersecting with other geometry.
  Note that the order in which you pick rail-1 and rail-2 determines the 
  direction of any 'diagonals' it will make.
  If you chose a Lattice 'from Profiles/Rails' you are next prompted to 
  choose a 'form' for the Lattice - as 'Lines' or as '3D'.
  Choose option: 'Cancel' exits, 'OK' continues...
  If you chose 'Lines' then a set of curves as lines only are made, 
  the profiles and rails sets are individually grouped and grouped 
  separately so the do not intersect with each other or other geometry.
  If you chose '3D' a dialog now asks for the 'Lattice Properties':
'Width' - default is 50mm/2" - this is the width centered on the 
  lines so it's effectively a 100mm/4" 'frame' overall where faces abut.
  [if <=0 it defaults]
'Depth' - default is 50mm/2", this is measured 'in' from the face 
  [if==0 there is no 'depth', if <0 it defaults].
'Pane Inset' - the amount the pane is inset from the frame's top-face - 
  default is 25.mm/1" [if ==0 there is no 'inset', if <0 it defaults; 
  it can never be more than the depth, and reverts to that if it is].
'Pane Thickness' - the thickness of the pane measured inset from the 
  pane's top face - default is 5mm/0.25" [if ==0 the pane is 'one sided' 
  (facing 'out'), if <0 it is 'outset', this -ve 'outset' cannot be > the 
  pane_inset, the pane_thickness is limited to the frame_depth-pane_inset].
  It is best to give the pane a thickness if it is to be seen from both 
  sides and the lattice might be exported to a 3rd party renderer.
'Lattice Material' - default is <Default> - additional choices are 'Red', 
  'Orange', 'Yellow', 'Green', 'Blue', 'Violet', 'Black', 'White' or 'Gray'.
'Pane Material' - default is <None>** - additional choices are <Default>, 
  "Glass"***, 'Red', 'Orange', 'Yellow', 'Green', 'Blue', 'Violet', 
  'Black', 'White', 'Gray'.
  **Note: if Pane Material == <None> then the faces that would form them 
  become 'holes' in the final lattice.
  ***The 'Glass' material will be made if it doesn't exist - it is colored 
  'bluish-light-gray' with 30% opacity.
  A faced mesh is made [like EEbyRails] with triangulation to ensure that 
  any twisted shapes get 'faced'.
  You are asked if you want to 'Reverse Faces' - Yes/No: important as the 
  mesh depth/insets etc are from the 'top', i.e. front face of the mesh.
  If there are any 'Coplanar Edges' then they are highlighted and you can 
  choose to erase them Yes/No: removing them will result in some 
  non-triangular lattice panes. 
  The Faces' edges are now offset to suit, then pushpulled to suit and the 
  materials applied.
  Note that faces too small to have a 'pane' are made 'solid'.
  A closing dialog asks if you want to delete the originally selected 
  curves - Yes/No.

Donations:
   Are welcome [by PayPal], please use 'TIGdonations.htm' in the 
   ../Plugins/TIGtools/ folder.
   
Version:
   1.0 20100428 First release.
   1.1 20100429 Glitches with display fixed, included 'offset.rb' updated 
                to latest version and trapped for a fail.
   1.2 20100430 Minor tweaks to text for lingvo files. New ES=Defisto and 
                FR=DidierBur + Pilou.  Flat faces at z=0 auto-reversed.
   1.3 20100504 Offset now reworked and 'in class'. Pane has back_material.
   1.4 20100506 'Diagonals' option added.
   1.5 20100507 Glitch with Line only versions Grouping fixed.
   1.6 20100517 All lingvo files updates - adjusted ES by Defisto.
   1.7 20101023 Pane thickness added and lingvos updated.
   1.8 20101027 Missing db on 'Processing...' corrected.
   1.9 20110812 Inputbox code improved.
   x2.0 20111207 Group.copy replaced to avoid clashes with rogue scripts.
   2.0 20130520 Becomes part of ExtrudeTools Extension.
=end

module ExtrudeTools
###
toolname="extrudeEdgesByRailsToLattice"
cmd=UI::Command.new(db("Extrude Edges by Rails to Lattice")){Sketchup.active_model.select_tool(ExtrudeTools::ExtrudeEdgesByRailsToLattice.new())}
cmd.tooltip=db("Extrude Edges by Rails to Lattice")
cmd.status_bar_text="..."
cmd.small_icon=File.join(EXTOOLS, "#{toolname}16x16.png")
cmd.large_icon=File.join(EXTOOLS, "#{toolname}24x24.png")
SUBMENU.add_item(cmd)
TOOLBAR.add_item(cmd)
###
class ExtrudeEdgesByRailsToLattice

include ExtrudeTools

  def initialize()
    ###
	@toolname="extrudeEdgesByRailsToLattice"
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
		@model.start_operation((db("Extrude Edges by Rails To Lattice")), true)
    ### 'false' is best to see results as UI/msgboxes...
	else
		@model.start_operation((db("Extrude Edges by Rails To Lattice")))
	end  
    @state=0 ### counter for selecting curves
    @profile=nil
    @mprofile=nil
    @rail1=nil
    @rail2=nil
    Sketchup::set_status_text(db("Extrude Edges by Rails To Lattice: Select the 'Profile' Curve..."))
  end#activate
  
  def reset
    ###
  end#reset
  
  def deactivate(view=nil)
    ### view.invalidate if view ###
    Sketchup.send_action("selectSelectionTool:")
    return nil
  end#deactivate
  
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
          Sketchup::set_status_text(db("Extrude Edges by Rails To Lattice: Select the 1st 'Rail' Curve..."))
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
          Sketchup::set_status_text(db("Extrude Edges by Rails To Lattice: Select the 2nd 'Rail' Curve..."))
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
          Sketchup::set_status_text(db("Extrude Edges by Rails To Lattice: Select the 'Melding-Profile' Curve..."))
          @state=3
        else
          UI.beep if @profile.curve.edges.include?(best.curve.edges[0])
          view.invalidate
          view.tooltip=(db("Pick 2nd Rail"))
        end#if
        ###
       when 3 ### melding profile
        if best.class==Sketchup::Edge and best.curve and not @rail1.curve.edges.include?(best.curve.edges[0])and not @rail2.curve.edges.include?(best.curve.edges[0])
          @sel.add(best.curve.edges)
          @mprofile=best
          view.invalidate
          if @rail1.curve==@rail2.curve
            Sketchup::set_status_text(db("Extrude Edges by Rails To Lattice: Making Mesh from Profile and 1 Rail."))
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
            Sketchup::set_status_text(db("Extrude Edges by Rails To Lattice: Making Mesh from Profile and 2 Rails."))
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
    return nil if @state>3
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
    
    @state=4
    
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
      ppoints=self.order_points(@mprofile_edges)
      tpoints=self.order_points(@profile_edges)
    else
      ppoints=self.order_points(@profile_edges)
      tpoints=self.order_points(@mprofile_edges)
    end#if
    0.upto((ppoints.length)-2) do |i|
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
    0.upto((tpoints.length)-2) do |i|
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
      ppoints=self.order_points(@rail2_edges)
      tpoints=self.order_points(@rail1_edges)
    else
      ppoints=self.order_points(@rail1_edges)
      tpoints=self.order_points(@rail2_edges)
    end#if
    0.upto((ppoints.length)-2) do |i|
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
    0.upto((tpoints.length)-2) do |i|
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
    
    points=self.order_points(@tprofile_edges)
    pointsm=self.order_points(@tmprofile_edges)
    points1=self.order_points(@trail1_edges)
    points2=self.order_points(@trail2_edges)

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
    
    ### save curves till end
    @original_edges=@profile.curve.edges+@mprofile.curve.edges+@rail1.curve.edges+@rail2.curve.edges
    ###
    #################
    self.make_shell(points,points1,points2,pointsm)
    #################
    ###
    group=nil
    group=@shell if @shell and @shell.valid?
    gents=group.entities if group
    ###
    #
    ###
    Sketchup::set_status_text(db("Extrude Edges by Rails To Lattice: Formating Lattice... Please Wait..."))if group
    ### remove temp 'split' groups etc
    @gp.erase! if @gp and @gp.valid?
    @gpm.erase! if @gpm and @gpm.valid?
    @gp1.erase! if @gp1 and @gp1.valid?
    @gp2.erase! if @gp2 and @gp2.valid?
    ###
    @model.commit_operation 
    ### Tidying up at end...    
    ### erase original curves ?
    Sketchup::set_status_text(db("Extrude Edges by Rails To Lattice: Erase Original Curves ?"))
    @model.active_view.invalidate ###
  if Sketchup.version.to_i > 6
		@model.start_operation((db("Extrude Edges by Rails To Lattice: Erase Original Curves ?")), true)
    ### 'false' is best to see results as UI/msgboxes...
	else
		@model.start_operation(db("Extrude Edges by Rails To Lattice: Erase Original Curves ?"))
	end
  if group and UI.messagebox((db("Extrude Edges by Rails To Lattice:"))+"\n\n"+(db("Erase Original Curves ?"))+"\n\n\n\n",MB_YESNO,"")==6 ### 6=YES 7=NO 
    @originals.erase! if @originals.valid?
  else ### explode protecting group back as it was...
    @originals.explode if @originals and @originals.valid?
  end#if
  @model.commit_operation
  ###
    Sketchup::set_status_text("")
    ###
    Sketchup.send_action "selectSelectionTool:"
    return nil
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
    @msg= db("Extrude Edges by Rails To Lattice:")
    Sketchup::set_status_text(@msg)
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
    profiles=[]
    mprofiles=[]
		defcp=cents.parent
		defcmp=cments.parent
		###
    0.upto((points1.length)-1) do |i|
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
        if ang.radians==180.0 or (ang==0 and i != 0 and i != (points1.length)-1)
          norm=[0,0,1]
        end#if 180
        begin
          if ang != 0 and norm.length != 0
            tr=Geom::Transformation.rotation(points1[i],norm,ang)
            tgp.transform!(tr)
          end#if
        rescue Exception => e
           puts "EE error 1"
					 p e
        end#begin
      end#if
      ###
      if @rail1.curve != @rail2.curve
        norm=(pointsm[0].vector_to(pointsm[-1])).cross(points1[i].vector_to(points2[i]))
        if angm.radians==180.0 or (angm==0 and i != 0 and i != (points1.length)-1)
          norm=[0,0,1]
        end#if 180
        begin
          if angm != 0 and norm.length != 0
            tr=Geom::Transformation.rotation(points1[i],norm,angm)
            tgpm.transform!(tr)
          end#if
        rescue Exception => e
          puts "EE error 2"
					p e
        end#begin
      end#if
			#p points
			#puts
			#p pointsm
			#puts
      ### scale profile to suit
      len=(points[0].distance(points[-1]))
      dis=len
      dis=(points1[i].distance(points2[i]))if @rail1.curve != @rail2.curve
      if dis != 0.0
        tr=Geom::Transformation.scaling(points1[i],(dis/len))
        tgp.transform!(tr)
        ### reform
				#p tgp
        tents=tgp.explode
				#p tents
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
			p e
      tgp.erase! if tgp and tgp.valid?
      tgpm.erase! if tgpm and tgpm.valid?
     end#begin
    end#do
    ###
    cprofile.erase!
    cmprofile.erase!
    profiles.uniq!
    mprofiles.uniq!
		#p profiles
		#p profiles[0]
		#p profiles[0].entities.to_a
    #################### now meld profile and melding profile ##########
    meldedprofiles=[]#profiles[0]]### 1st is pure profile
    rmsg= ""
    rmsg2=""
    rmsg3=""
    plen=(profiles.length)-1
    0.upto(plen) do |i|
      ###
      rmsg=rmsg+"."
      Sketchup::set_status_text(rmsg)
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
		#p profiles[0]
		#p profiles[0].entities.to_a
    ####################
    ### dialog to get lattice type
    title=(db("Extrusion Type"))
    Sketchup::set_status_text(title)
    prmpt=(db("Lattice from:"))
    prompts=[prmpt]
    ppps1=(db("Profiles"))
    ppps2=(db("Profiles/Rails"))
    ppps3=(db("Rails"))
    ppps4=(db("Diagonals"))
    ppps=[ppps1,ppps2,ppps3,ppps4].join("|")
    popups=[ppps]
    values=[ppps2]
    results=inputbox(prompts,values,popups,title)
    if not results ### tidy up and exit
      profiles.each{|e|e.erase! if e.valid?}
      xprofiles.each{|e|e.erase! if e.valid?}
      mprofiles.each{|e|e.erase! if e.valid?}
      @shell.erase! if @shell and @shell.valid?
      self.deactivate(@model.active_view)
      return nil
    end#if
    ### safeguard originals from being overwritten
    @originals=@ents.add_group(@original_edges.flatten)
    ###
    lattice_type=results[0]
    ###
    ### NOW get type and process as mesh with offsets IF ppps2
    if lattice_type==ppps2
      ### dialog to get lattice type
      title=(db("Lattice Type"))
      Sketchup::set_status_text(title)
      prmpt=(db("Lattice as:"))
      prompts=[prmpt]
      xppps1=(db("Lines"))
      xppps2=(db("3D"))
      xppps=[xppps1,xppps2].join("|")
      popups=[xppps]
      values=[xppps1]
      results=inputbox(prompts,values,popups,title)
      lattice_type2=results[0]
      if lattice_type2==xppps2 ### 3d
        ###
        @shell.erase! if @shell and @shell.valid?
        profiles.each{|e|e.erase! if e.valid?}
        xprofiles.each{|e|e.erase! if e.valid?}
        mprofiles.each{|e|e.erase! if e.valid?}
        ###
        self.make_lattice(points,points1,points2,pointsm)
        ###
        @model.commit_operation
        ###
        self.deactivate(@model.active_view)
        return nil
        ###
      else ### lines only...
        ### carry on with rest of the defn...
      end#if
    end#if
    ###
    ### now use cpoints to draw 'ribs'
    point_count=(profiles.length) -1
    point1_count=(profiles[0].entities.to_a.length) -1
    ###
   if lattice_type==ppps1 or lattice_type==ppps2
    ribs=[]
    tgp=@shell
    tgp=sents.add_group() if lattice_type==ppps2 ###
    ###
    rmsg=rmsg+"."
    Sketchup::set_status_text(rmsg)
    ###
    0.upto(point_count) do |i|
      begin
        ### add rib
				#p profiles[i]
				#p profiles[i].entities.to_a
        pts=[]
				profiles[i].entities.each{|e|pts<< e.position if e.class==Sketchup::ConstructionPoint}
        gp=tgp.entities.add_group()
        gp.entities.add_curve(pts)
      rescue Exception => e
        puts "EE Error 3"
				p e
        ### nothing ?
      end
      ###
      ribs<< gp
      ###
    end#do
   end#if
    ###
   if lattice_type==ppps3 or lattice_type==ppps2
    ribs=[]
    tgp=@shell ###
    tgp=sents.add_group() if lattice_type==ppps2 ###
    ###
    rmsg2=rmsg2+"."
    Sketchup::set_status_text(rmsg2)
    ###
    0.upto(point1_count) do |i|
      begin
        ### add rib
        pts=[];profiles.each{|prof|pts<< prof.entities[i].position if prof.entities[i].class==Sketchup::ConstructionPoint}
        gp=tgp.entities.add_group()
        gp.entities.add_curve(pts.reverse!)
        ###
      rescue Exception => e
        puts "EE Error 4"
				p e
        ### nothing ?
      end
      ###
      ribs<< gp
      ###
    end#do
   end#if
   ###
   if lattice_type==ppps4 ########## diagonals
     ribs=[]
    tgp=@shell ###
    ###
    rmsg3=rmsg3+"."
    Sketchup::set_status_text(rmsg3)
    ###
    ppts=[]
    ###
    begin
     profiles.each{|profile|
        pts=[]
        profile.entities.each{|e|pts<< e.position if e.class==Sketchup::ConstructionPoint}
        ppts<<pts
     }
     ### ppts is now a list of all points split by profile
     alldpts=[]
     ### do profiles[0]
     0.upto(point1_count-1) do |i|
       pts=[ppts[0][i]]
       c=i
       0.upto(point_count) do |j|
         pts<< ppts[j][c] if ppts[j] and ppts[j][c]
         c+=1
       end#do j
       alldpts<< pts if pts and pts[1]
     end#do i
     ### do rest
     1.upto(point_count-1) do |i|
       pts=[ppts[i][0]]
       c=i
       0.upto(point_count) do |j|
         pts<< ppts[c][j] if ppts[c] and ppts[c][j]
         c+=1
       end#do j
       alldpts<< pts if pts and pts[1]
     end#do i
			 ###   
			 alldpts.compact!
     rescue Exception => e
			puts "EE Error 666"
			puts e
			### nothing ?
     end#begin
     ### alldpts is a list of points making the diagonals
     alldpts.each{|ps|
       if ps[1]
         gp=tgp.entities.add_group()
         gp.entities.add_curve(ps)
         ribs<< gp if gp.entities[0]
       end#if
     }
     ###
   end#if
    ###
    profiles.each{|e|e.erase! if e.valid?}
    xprofiles.each{|e|e.erase! if e.valid?}
    mprofiles.each{|e|e.erase! if e.valid?}
    ###
    Sketchup::set_status_text("")
    ###
  end#make_shell
  
  
  
  def make_lattice(points,points1,points2,pointsm)
    @shell=@ents.add_group()
    sents=@shell.entities
    msg=(db("Extrude Edges by Rails To Lattice:"))
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
        rescue Exception => e
           puts "EE error 1"
					 p e
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
        rescue Exception => e
          puts "EE error 2"
					p e
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
    ####################
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
            sents.add_face(pents[j].position ,profiles[i+1].entities[j].position,profiles[i+1].entities[j+1].position)
          else ### NOT starts at a common point
            if profiles[i+1].entities[j].position == profiles[i+1].entities[j+1].position
              ### BUT it ends at one
              sents.add_face(pents[j].position ,profiles[i+1].entities[j+1].position,pents[j+1].position)
            else
              ### NO common point so draw 2 triangular faces [usual case]
              sents.add_face(pents[j].position ,profiles[i+1].entities[j].position,profiles[i+1].entities[j+1].position)
              sents.add_face(pents[j].position ,profiles[i+1].entities[j+1].position,pents[j+1].position)
            end#if
          end#if
        rescue Exception => e
          ### nothing ?
					puts "EE 3d"
					p e
        end
      end#do
    end#do
    ###
    @model.active_view.invalidate
    Sketchup::set_status_text(db("Processing... Please Wait..."))
    ### remove temp cpoints
    profiles.each{|e|e.erase! if e.valid?}
    xprofiles.each{|e|e.erase! if e.valid?}
    mprofiles.each{|e|e.erase! if e.valid?}
    ### @shell is mesh group
    ### auto-reverse any flat faces with z=0
    sents.to_a.each{|e|e.reverse! if e.class==Sketchup::Face and e.normal.z==-1 and e.bounds.max.z==0}
    ### check for coplanar edges
    cpedges=[]
    4.times do ### to make sure we got all of them !
     sents.to_a.each{|e|
      if e.valid? and e.class==Sketchup::Edge
       if not e.faces[0]
         cpedges << e
       elsif e.faces.length==2 and e.faces[0].normal.dot(e.faces[1].normal)> 0.99999999999
         cpedges << e
       end#if
      end#if
     }
    end#times
    ###
    @model.commit_operation
    ###
    if cpedges[0]
      @sel.clear
      @sel.add(cpedges)
      if UI.messagebox((db("Extrude Edges by Rails To Lattice:"))+"\n\n"+(db("Erase Highlighted Coplanar Edges ?"))+"\n\n",MB_YESNO,"")==6 ### 6=YES 7=NO
      ### pause here so we see result...
			if Sketchup.version.to_i > 6
				@model.start_operation((db("Extrude Edges by Rails To Lattice: Erase Highlighted Coplanar Edges ?")), true)
        ### 'false' is best to see results as UI/msgboxes...
			else
				@model.start_operation((db("Extrude Edges by Rails To Lattice: Erase Highlighted Coplanar Edges ?")))
			end#if
       cpedges.each{|e|e.erase! if e.valid?}
       @model.commit_operation
      end#if
    end#if
    @sel.clear ###
    ### REVERSE FACES ~~~~~~~~~~
    faces=[];sents.each{|e|faces<<e if e.class==Sketchup::Face}
    @msg=((db("Extrude Edges by Rails To Lattice: Reverse "))+faces.length.to_s+(db(" Faces ?")))
    Sketchup::set_status_text(@msg)
  if UI.messagebox((db("Extrude Edges by Rails To Lattice:"))+"\n\n"+(db("Reverse Faces ?"))+"\n\n\n\n",MB_YESNO,"")==6 ### 6=YES 7=NO 
    ### pause here so we see result...
	if Sketchup.version.to_i > 6
		@model.start_operation((db("Extrude Edges by Rails To Lattice: Reversing Face ")), true)
    ### 'false' is best to see results as UI/msgboxes...
	else
		@model.start_operation((db("Extrude Edges by Rails To Lattice: Reversing Face ")))
	end
    tick=1
    faces.each{|e|
      e.reverse!
      @msg=((db("Extrude Edges by Rails To Lattice: Reversing Face "))+tick.to_s+(db(" of "))+faces.length.to_s)
      Sketchup::set_status_text(@msg)
      tick+=1
    }
    @model.commit_operation
  end#if 
    ###
    if Sketchup.version.to_i > 6
		@model.start_operation((db("Extrude Edges by Rails To Lattice: Offsetting ")), true)
        ### 'false' is best to see results as UI/msgboxes...
	else
		@model.start_operation((db("Extrude Edges by Rails To Lattice: Offsetting ")))
	end
    ###
    begin
      self.offset_faces(sents)
    rescue Exception => e
      puts "Offset Error."
      puts e
    end
    ### @model.commit_operation
    ###
    Sketchup::set_status_text("")
  end#make_lattice
  
  def face_offset(face=nil, dist=0)
    return nil if not face or not face.valid?
	  return nil if (not ((dist.class==Float || dist.class==Length) && dist!=0))
    pi=Math::PI
	  verts=face.outer_loop.vertices
	  pts=[]
	0.upto(verts.length-1) do |i|
		vec1=(verts[i].position-verts[i-(verts.length-1)].position).normalize
		vec2=(verts[i].position-verts[i-1].position).normalize
		vec3=(vec1+vec2).normalize
		if vec3.valid?
			ang=vec1.angle_between(vec2)/2
			ang=pi/2 if vec1.parallel?(vec2)
			vec3.length=dist/Math::sin(ang)
			t=Geom::Transformation.new(vec3)
			if pts.length > 0
				if not (vec2.parallel?(pts.last.vector_to(verts[i].position.transform(t))))
					t=Geom::Transformation.new(vec3.reverse)
				end#if
			end#if
			pts.push(verts[i].position.transform(t))
		end#if
	end#upto
	face.parent.entities.add_face(pts) if pts[2]
  end#face_offset
  
  def offset_faces(ents)
    @msg=(db("Lattice Properties"))
    Sketchup::set_status_text(@msg)
    if not ents
      return nil
    else
      titl=(db("Lattice Properties"))
      defa=(db("<Default>"))
      none=(db("<None>"))
      glas=(db("'Glass'"))
      mats1=defa+"|Red|Orange|Yellow|Green|Blue|Violet|Black|White|Gray|"
      mats2=defa+"|"+none+"|"+glas+"|Red|Orange|Yellow|Green|Blue|Violet|Black|White|Gray|"
      mats1a=mats1
      mats2a=mats2
      prom1=(db("Width: "))
      prom2=(db("Depth: "))
      prom3=(db("Pane Inset: "))
      prom3a=(db("Pane Thickness: "))
      prom4=(db("Lattice Material: "))
      prom5=(db("Pane Material: "))
      wid=2.inch if @model.options["UnitsOptions"]["LengthUnit"]<2
      dep=2.inch if @model.options["UnitsOptions"]["LengthUnit"]<2
      ins=1.inch if @model.options["UnitsOptions"]["LengthUnit"]<2
      thk=0.25.inch if @model.options["UnitsOptions"]["LengthUnit"]<2
      wid=50.mm if @model.options["UnitsOptions"]["LengthUnit"]>1
      dep=50.mm if @model.options["UnitsOptions"]["LengthUnit"]>1
      ins=25.mm if @model.options["UnitsOptions"]["LengthUnit"]>1
      thk=5.mm if @model.options["UnitsOptions"]["LengthUnit"]>1
      ###
      results=inputbox([prom1,prom2,prom3,prom3a,prom4,prom5],[wid,dep,ins,thk,defa,none],["","","","",mats1a,mats2a],titl)
      return nil if not results
      @msg=(db("Processing"))
      Sketchup::set_status_text(@msg)
      width=results[0]
      depth=results[1]
      pinset=results[2]
      pthick=results[3]
      frame=results[4]
      pane=results[5]
      ###
      width=wid if width<=0
      depth=dep if depth<0
      pinset=0.0 if pinset<0
      pinset=depth if pinset >depth
      pinset=depth if pane==none
      pthick=0 if pane==none
      if pthick <0
        if pthick.abs > pinset
          pthick= -pinset
        end#if
      end#if
      if pthick > depth-pinset
        pthick=depth-pinset
      end#if
      ###
      mats=[];@model.materials.each{|m|mats<< m.display_name}
      ### this traps for 'simlar' names matching...
      ### make missing materials.....................
      frame=nil if frame==defa
      if frame and not mats.include?(frame)
        mat=@model.materials.add(frame)
        mat.color=frame ### e.g. 'Gray'
      end#if
      pane=nil if pane==defa
      if pane==glas and not mats.include?(pane)
        mat=@model.materials.add(glas)
        mat.color=[150,200,250]
        mat.alpha=0.30
      elsif pane and pane != none and not mats.include?(pane)
        mat=@model.materials.add(pane)
        mat.color=pane ### e.g. 'Gray'
      end#if
      ###
      ofaces=[]
      ents.to_a.each{|e|ofaces<< e if e.class==Sketchup::Face}
      ofaces.each{|face|self.face_offset(face, -(width.to_l))}
      pfaces=[]
      ents.to_a.each{|e|pfaces << e if e.class==Sketchup::Face and e.valid? and not ofaces.include?(e)}
      ### remove floating faces
      @msgx=@msg
      pfaces.each{|e|
        e.erase! if e.edges[0].faces.length==1
        @msgx=@msgx+"."
        Sketchup::set_status_text(@msgx)
      }
      Sketchup::set_status_text(@msg);@msgx=@msg
      ents.to_a.each{|e|
        e.erase! if e.class==Sketchup::Edge and e.faces.length==0
        @msgx=@msgx+"."
        Sketchup::set_status_text(@msgx)
      }
      ###
      pfaces=[]
      ents.to_a.each{|e|pfaces << e if e.class==Sketchup::Face and e.valid? and not ofaces.include?(e)}
      if depth>0
        tfaces=[]
        Sketchup::set_status_text(@msg);@msgx=@msg
        pfaces.each{|face|
          norm=face.normal
          allfaces=[]
          ents.to_a.each{|e|allfaces<< e if e.class==Sketchup::Face}
          face.pushpull(-(pinset.to_l))
          nowfaces=[]
          ents.to_a.each{|e|nowfaces<< e if e.class==Sketchup::Face}
          newfaces= nowfaces - allfaces
          newfaces.each{|e|tfaces<< e if e.valid? and (e.normal==norm or e.normal.reverse==norm)}
          tfaces[-1].reverse! if tfaces[-1].normal!=norm
          if pthick!=0
            tfaces[-1].pushpull(-(pthick.to_l),true)
            nowfaces=[]
            ents.to_a.each{|e|nowfaces<< e if e.class==Sketchup::Face}
            newfaces= nowfaces - allfaces
            tfaces[-1].reverse! if tfaces[-1].normal!=norm
            newfaces.each{|e|tfaces<< e if e.valid? and (e.normal==norm or e.normal.reverse==norm)}
            newfaces.each{|e|e.erase! if e.valid? and not (e.normal==norm or e.normal.reverse==norm)}
          end#if
          @msgx=@msgx+"."
          Sketchup::set_status_text(@msgx)
        }
        pfaces=tfaces
      end#if
      ### make '3d' with back
      Sketchup::set_status_text(@msg);@msgx=@msg
      ofaces.each{|face|
        face.pushpull(-(depth.to_l),true)
        face.reverse!
        @msgx=@msgx+"."
        Sketchup::set_status_text(@msgx)
      }
      ###
      faces=[]
      ents.to_a.each{|e|faces<< e if e.class==Sketchup::Face}
      ffaces= faces - pfaces
      Sketchup::set_status_text(@msg);@msgx=@msg
      ffaces.each{|e|
        e.material=frame if e.valid?
        @msgx=@msgx+"."
        Sketchup::set_status_text(@msgx)
      }
      if pane == none
        Sketchup::set_status_text(@msg);@msgx=@msg
        pfaces.each{|e|
          e.erase! if e.valid?
          @msgx=@msgx+"."
          Sketchup::set_status_text(@msgx)
        }
      else
        Sketchup::set_status_text(@msg);@msgx=@msg
        pfaces.each{|e|
          e.material=pane if e.valid?
          e.back_material=pane if e.valid? ###
          @msgx=@msgx+"."
          Sketchup::set_status_text(@msgx)
        }
      end#if
    end#if
    Sketchup::set_status_text("")
  end#offset_faces
    
end#class -----------------------------------

end#module

