=begin
  Copyright 2014-2017 (c), TIG
  All Rights Reserved.
  THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED 
  WARRANTIES,INCLUDING,WITHOUT LIMITATION,THE IMPLIED WARRANTIES OF 
  MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
###
  extrudeEdgesByRailsByFace.rb
###
  Extrudes a Face along a set of curves to form a FollowMe-like 
  extrusions groups within a group: the curves are formed using a 
  preselected face.
###
Usage:
  Preselect a Face and Run this Tool, 'Extrude Edges by Rails by Face', 
  from the Plugins Menu, or the Extrusions Toolbar...
  Note that the Face's rotation is also reflected in the extruded forms.
  Some forms like circles will always extrude similarly - others not.
  The path ends nearest to the face will be used, so asymmetrical faces 
  should be placed nearest to the side requiring that orientation.
  See EEbyFace for more details on this...
  You are then prompted to pick some curves to be used in forming the 
  'mesh' - a Profile, Rail1, Rail2 and a Melding-Profile - 
  please see EEbyRails for more details on this...
  You are then prompted to choose 'Ribs from Profile', 'Ribs from Rail' 
  or 'Ribs from Profile and Rails' [i.e. a 'grid'] - 'Choose option, 
  Cancel' exits the tool, OK starts making the 'ribs'...
  A copy of the Face is added to each Rib's Path end, rotated so that 
  its normal is parallel to the vector of the first edge in each Path.
  The Path can be looped, but it might give unexpected results.
  The Face's bounding-box center is used as the 'snap-point' at each 
  path's end, unless was a Cpoint [GuidePoint] in the selection - if so 
  then that is used as the Face's 'snap-point' instead...
  Note that Cpoints placed non-planar with the Face or remote from it 
  may give unexpected extrusions - perhaps even Bugsplats !
  Ribs are then extruded based on the nodes of the profiles/rails...
  The VCB message ticks as each is made - note that complex faces and 
  profile/rail curves might take sometime to complete all of the ribs.
  Each rib's geometry is individually grouped and all ribs are also 
  grouped together.
  A closing dialog asks if you want to delete the originally selected 
  curves.
  Note that the ribs are made in a single step so if the Face is not 
  oriented so as to make ribs as desired, simply undo and rotate the 
  Face/add cpoint as desired and re-run...

Donations:
   Are welcome [by PayPal], please use 'TIGdonations.htm' in the 
   ../Plugins/TIGtools/ folder.
   
Version:
   1.0 20100211 First release.
   1.1 20100215 Extrusion form now consistent, Pilou updated FR lingvo.
   1.2 20100216 All extrusion-tools now in one in Plugins sub-menu.
   1.3 20100218 Rare glitch with helical rails fixed.
   1.4 20100220 Glitch on some text in db fixed.
   1.5 20100220 Glitch with number of Rail-Ribs fixed.
                Color coding of picked curves added.
                Profile=Cyan
                Rail1=Magenta
                Rail2=DarkVioletRed
                MeldingProfile=DarkCyan
                FaceEdges=Orange
   1.6 20100221 Glitch with selections and color-coding location fixed.
   1.7 20100222 Tooltips etc now deBabelized properly.
   1.8 20100312 Erasure of original curves glitch fixed.
   1.9 20100330 Rare glitch with self.xxx fixed.
   x2.0 20101030 Non-flat face trapped.
   x2.1 20101102 No face selected trapped.
   x2.2 20111207 Group.copy replaced to avoid rogue script clashes.
   2.0 20130520 Becomes part of ExtrudeTools Extension.
=end

module ExtrudeTools
###
toolname="extrudeEdgesByRailsByFace"
cmd=UI::Command.new(db("Extrude Edges by Rails by Face")){Sketchup.active_model.select_tool(ExtrudeTools::ExtrudeEdgesByRailsByFace.new())}
cmd.tooltip=db("Extrude Edges by Rails by Face")
cmd.status_bar_text="..."
cmd.small_icon=File.join(EXTOOLS, "#{toolname}16x16.png")
cmd.large_icon=File.join(EXTOOLS, "#{toolname}24x24.png")
SUBMENU.add_item(cmd)
TOOLBAR.add_item(cmd)
###
class ExtrudeEdgesByRailsByFace

include ExtrudeTools

  def initialize()
    ###
		@toolname="extrudeEdgesByRailsByFace"
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
    selection=@sel
    selected_faces=[]
    selected_cpoints=[]
    selection.each{|e|
      selected_faces<< e if e.class==Sketchup::Face
      selected_cpoints<< e if e.class==Sketchup::ConstructionPoint
    }
    @face=nil
    @face=selected_faces[0] if selected_faces[0]
    if ! @face || @face.normal.z.abs != 1
        UI.messagebox(db("Select a 'Flat' Face [and perhaps a Cpoint] BEFORE using."))
        Sketchup.send_action("selectSelectionTool:")
        return nil
    end#if
		#p @face
    ###selection.clear
    @cpoint=nil
    @cpoint=selected_cpoints[0]if selected_cpoints[0]
		if Sketchup.version.to_i > 6
			@model.start_operation((db("Extrude Edges by Rails by Face")), true)
			### 'false' is best to see results as UI/msgboxes...
		else
			@model.start_operation((db("Extrude Edges by Rails by Face")))
		end
		###
		@org = [@face]
		@org << @cpoint if @cpoint
		@orgg = @ents.add_group(@org)
		tmpg = @ents.add_instance(@orgg.entities.parent, @orgg.transformation)
		exx = tmpg.explode
		@face = exx.grep(Sketchup::Face)[0]
		@cpoint = exx.grep(Sketchup::ConstructionPoint)[0]
		###
    @state=0 ### counter for selecting curves
    @profile=nil
    @mprofile=nil ###v2.4 typo fix
    @rail1=nil
    @rail2=nil
    Sketchup::set_status_text(db("Extrude Edges by Rails by Face: Select the 'Profile' Curve..."))
		@xray=@model.rendering_options["ModelTransparency"]
  end#activate
  
  def reset
    ###
  end#reset
  
  def deactivate(view=nil)
    view.invalidate if view
    #@group.erase! if ! @done && @group && @group.valid?
    #Sketchup.send_action("selectSelectionTool:")
    return
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
          Sketchup::set_status_text(db("Extrude Edges by Rails by Face: Select the 1st 'Rail' Curve..."))
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
          Sketchup::set_status_text(db("Extrude Edges by Rails by Face: Select the 2nd 'Rail' Curve..."))
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
          Sketchup::set_status_text(db("Extrude Edges by Rails by Face: Select the 'Melding-Profile' Curve..."))
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
            Sketchup::set_status_text(db("Extrude Edges by Rails by Face: Making Mesh from Profile and 1 Rail."))
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
            Sketchup::set_status_text(db("Extrude Edges by Rails by Face: Making Mesh from Profile and 2 Rails."))
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
		if @state < 4
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
			if @face
				view.drawing_color="orange"
				@face.edges.each{|e|view.draw_line(e.start.position,e.end.position)}
			end#if
		elsif @state >= 4 && @originals && @originals.valid?
			view.line_width=7
			if @profile
				view.drawing_color="red"
				@profile.curve.edges.each{|e|view.draw_line(e.start.position.transform(@originals.transformation), e.end.position.transform(@originals.transformation))}
			end#if
			if @rail1
				view.drawing_color="red"
				@rail1.curve.edges.each{|e|view.draw_line(e.start.position.transform(@originals.transformation), e.end.position.transform(@originals.transformation))}
			end#if
			if @rail2
				view.drawing_color="red"
				@rail2.curve.edges.each{|e|view.draw_line(e.start.position.transform(@originals.transformation), e.end.position.transform(@originals.transformation))}
			end#if
			if @mprofile
				view.drawing_color="red"
				@mprofile.curve.edges.each{|e|view.draw_line(e.start.position.transform(@originals.transformation), e.end.position.transform(@originals.transformation))}
			end#if
		end
  end#draw
  
  def make_mesh()
    ###
    @state=4
    ###
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
    if points1[0]==points2[0] && @rail1.curve != @rail2.curve
      points1.reverse!
      points2.reverse!
      if points1[0] != points[0]
        points.reverse!
      end#if
    elsif points1[-1]==points2[-1] && @rail1.curve != @rail2.curve
      if points1[0] != points[0]
        points1.reverse!
        points2.reverse!
      end#if
    elsif points1[0] == points2[-1] || (points1[-1] == points2[0] && @rail1.curve != @rail2.curve)
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
    @original_edges = []
		@original_edges << @profile.curve.edges
		@original_edges << @mprofile.curve.edges
		@original_edges << @rail1.curve.edges
		@original_edges << @rail2.curve.edges
		@original_edges.flatten!
		@original_edges.compact!
		@original_edges.uniq!
    ###
    #################
    self.make_shell(points,points1,points2,pointsm)
    #################
    ###
    group=nil
    group=@shell if @shell && @shell.valid?
    gents=group.entities if group
    ###
    #
    ###
    Sketchup::set_status_text(db("Extrude Edges by Rails by Face: Formating Ribs... Please Wait..."))if group
    ### remove temp 'split' groups etc
    @gp.erase! if @gp && @gp.valid?
    @gpm.erase! if @gpm && @gpm.valid?
    @gp1.erase! if @gp1 && @gp1.valid?
    @gp2.erase! if @gp2 && @gp2.valid?
    ###
		self.final_tidy() if @shell && @shell.valid?
		###
    #@model.rendering_options["ModelTransparency"]=true
    ### Tidying up at end...
		#@state=5
    ### erase original curves ? ALWAYS ??
		###
    #Sketchup::set_status_text(db("Extrude Edges by Rails by Face: Erase Original Curves ?"))
		#if group && UI.messagebox((db("Extrude Edges by Rails by Face:"))+"\n\n"+(db("Erase Original Curves ?"))+"\n\n\n\n",MB_YESNO,"")==6 ### 6=YES 7=NO  
			#@originals.erase! if @originals && @originals.valid?
		#else
			#@originals.entities.each{|e| p  e; p e.valid? }
			#xxx=@originals.explode.grep(Sketchup::Edge) if @originals && @originals.valid?
		#end#if
		###
		#@model.rendering_options["ModelTransparency"] = @xray
		###
		begin
			@originals.explode if @originals && @originals.valid?
		rescue
		end
		###
		@model.commit_operation
		###
    Sketchup::set_status_text("")
		@model.active_view.invalidate
    ###
    Sketchup.send_action("selectSelectionTool:")
    return nil
    ### done
  end#make_mesh
  
	def final_tidy()
		### add copy of face/cpoint back into shell group and erase it
		tmpg = @shell.entities.add_instance(@orgg.entities.parent, @orgg.transformation*@shell.transformation.inverse)
		exx = tmpg.explode
		face = exx.grep(Sketchup::Face)[0]
		edges = face.edges
		xgeom = [face]
		xgeom << face.edges
		xgeom << @shell.entities.grep(Sketchup::ConstructionPoint)
		xgeom.flatten!
		xgeom.uniq!
		xgeom.compact!
		@shell.entities.erase_entities(xgeom) if xgeom[0]
		### explode original face/cpoint group back as it was
		@orgg.explode if @orgg && @orgg.valid?
		###
	end

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
    @msg= db("Extrude Edges by Rails by Face: ")
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
    0.upto(plen){|i|
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
      0.upto(ents1.length-1){|j|
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
      }#do
      meldedprofiles<<tempg
    }#do
    #meldedprofiles<<mprofiles[-1]###last is pure mprofile ?
    #################### swap profiles around...
    xprofiles=profiles
    profiles=meldedprofiles
    ####################
		@state=4
    ### dialog to get rib type
    #'Ribs from Profile' 'Ribs from Rail'  'Ribs from Profile and Rails'
    title=(db("Extrusion Type"))
    Sketchup::set_status_text(title)
    prmpt=(db("Rib from: "))
    prompts=[prmpt]
    ppps1=(db("Profiles"))
    ppps2=(db("Profiles & Rails"))+"        "
    ppps3=(db("Rails"))
    ppps=[ppps1,ppps2,ppps3].join("|")
    popups=[ppps]
    values=[ppps2]
    results = inputbox(prompts,values,popups,title)
    unless results ### tidy up and exit
      profiles.each{|e|e.erase! if e.valid?}
      xprofiles.each{|e|e.erase! if e.valid?}
      mprofiles.each{|e|e.erase! if e.valid?}
      @shell.erase! if @shell && @shell.valid?
			@model.abort_operation
      self.deactivate(@model.active_view)
      return nil
    end#if
		###
    ### safeguard originals from being overwritten
    @originals = @ents.add_group(@original_edges)
    ###
    rib_type=results[0]
    ###
    ### now use cpoints to draw 'ribs'
    point_count=(profiles.length) -1
    point1_count=(profiles[0].entities.to_a.length) -1
    ribcount=(points.length)*(points1.length)
    ribs=[]
    ###
   if rib_type==ppps1 || rib_type==ppps2
    ###
    rmsg=rmsg+"."
    Sketchup::set_status_text(rmsg)
    ###
    0.upto(point_count){|i|
      begin
        ### add rib
        pts=[]
				profiles[i].entities.each{|e|pts<< e.position if e.class==Sketchup::ConstructionPoint}
        gp=sents.add_group()
        gp.entities.add_curve(pts)
      rescue Exception => e
        puts "EE Error 3"
				p e
        ### nothing ?
      end
      ###
      ribs<< gp
      ###
    }#do
   end#if
	 #p ribs
   ###
   if rib_type==ppps3 || rib_type==ppps2
    ###
    rmsg2=rmsg2+"."
    Sketchup::set_status_text(rmsg2)
    ###
    0.upto(point1_count){|i|
      begin
        ### add rib
        pts=[]
				profiles.each{|prof|pts<< prof.entities[i].position if prof.entities[i].class==Sketchup::ConstructionPoint}
        gp=sents.add_group()
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
    }
   end#if
	 #p ribs
    ### add face extrusion
    newents=[]
    ###
		#p 555
    ribs = @shell.explode.grep(Sketchup::Group)
		#p 222
    ###
    ribs.compact!
    ###
    total=ribs.length
    counter=1
    ###
		#p ribs
    ribs.each{|rib|
			#p rib
			next unless rib.valid?
      entsIN=@ents.to_a
      ###
      #ribedges=rib.entities.to_a
			#p 666
			xxx = rib.explode
      ribedges = xxx.grep(Sketchup::Edge)
			next unless ribedges[0]
			#p 999
      ### add face cpoint and rib's path to selection and extrude
      @sel.clear
			#p @face
      @sel.add(@face)if @face && @face.valid?
      @sel.add(@cpoint)if @cpoint && @face.valid?
      ribedges.each{|e| @sel.add(e) if e.valid? }
      ###
      @msg=(db("Making Extrusion "))
      @msg=@msg+counter.to_s+(db( "of" ))+total.to_s if total>1
      Sketchup::set_status_text(@msg)
      ###
      self.make_ribs() if ribedges[0] #################################
			begin
				@model.active_view.refresh
			rescue
				@model.active_view.invalidate
			end
      ###
      ribedges.each{|e| e.erase! if e.valid? && e.faces.length==0 }
      ###
      ents=@ents.to_a - entsIN
      newents << ents
      ###
      counter+=1
      ###
    }### end ribs
    ###
		#p newents
		#return
		#puts
    newents.flatten!
		newents.uniq!
    tnnents=[]
    newents.each{|e|
			exp=[]
			exp=e.explode if e.valid? && e.is_a?(Sketchup::Group)
			((exp.grep(Sketchup::Edge))+(exp.grep(Sketchup::Edge))).each{|ee| tnnents << ee if ee.valid? }
		}
		tnnents.flatten!
		tnnents.uniq!
		#p tnnents
		#p tnnents.length
		tnnents.dup.each{|e|
			next unless e.valid?
			e.erase! unless e.is_a?(Sketchup::Edge) || e.is_a?(Sketchup::Face)
		}
		#p tnnents.length
		#return
		tnnents.dup.each{|e| tnnents.delete(e) unless e.parent.entities==@ents }
    ### tidy up
		#pars = []
		#tnnents.each{|e| pars << e.parent unless pars.include?(e.parent) }
		#p pars
		#p @ents
		#puts
		#p ents=[]
		#tnnents.each{|e| ents << e.parent.entities unless ents.include?(e.parent.entities) }
		#p ents
    @shell = @ents.add_group(tnnents)
    ### remove loose edges
    @shell.entities.to_a.each{|e| e.erase! if e.valid? && e.class==Sketchup::Edge && e.faces.length==0 }
    ###
    profiles.each{|e|e.erase! if e.valid?}
    xprofiles.each{|e|e.erase! if e.valid?}
    mprofiles.each{|e|e.erase! if e.valid?}
    ###
    ###
    Sketchup::set_status_text("")
		p 'Made shell'
    ###
  end#make_shell

############ 'activate' from EEbyFace tool
def make_ribs()
  #Sketchup.active_model.select_tool(ExtrudeEdgesByFace.new)
  #@model=Sketchup.active_model
  @entities=@model.active_entities
  selection=@model.selection
	#p 123000
  @selected=selection.to_a
  selected_faces=[]
  selected_edges=[]
  selected_cpoints=[]
  selection.each{|e|
    selected_faces<< e if e.class==Sketchup::Face
    selected_edges<< e if e.class==Sketchup::Edge
    selected_cpoints<< e if e.class==Sketchup::ConstructionPoint
  }
	#p 123123
	#p selected_faces
  #@face=nil
  #@face=selected_faces[0]
	#p @face
  @edges=[]
  selected_edges.each{|e| @edges << e if @face && ! e.faces.include?(@face) }
	#p 111
	#p @edges
	#p 888
  ###
  selection.clear
  ###
  @cpoint=nil
  @cpoint=selected_cpoints[0]if selected_cpoints[0]
  @face_copy=nil
  @group=nil
  @gents=nil
  @face_group=nil
  @done=nil
  @msg=""
  Sketchup::set_status_text(@msg)
  @model.active_view.invalidate
  self.copy_edges_and_face()
  self.locate_face()
  self.make_extrusion()
  @model.active_view.invalidate
end

def copy_edges_and_face()
  ents=@face.edges 
	ents << @face
  ents=ents << @cpoint if @cpoint
  tface_group=@entities.add_group(ents)
  deftface=tface_group.entities.parent
  #@face_group=tface_group.copy
  @face_group=@entities.add_instance(deftface, tface_group.transformation)
  @face_group.make_unique if deftface.instances[0]
  #p 444000
	exx = tface_group.explode
	###
	@face = exx.grep(Sketchup::Face)[0]
	@cpoint = exx.grep(Sketchup::ConstructionPoint)[0]
  ###
	#p 444
  ents=@edges
	#p 888000
  temp_group=@entities.add_group(ents)
  deftg=temp_group.entities.parent
  #egroup=temp_group.copy
  egroup=@entities.add_instance(deftg, temp_group.transformation)
  ###
  temp_group.explode
  @group=@entities.add_group([@face_group, egroup])
  egroup.explode
  @gents=@group.entities
  @gedges=@gents.to_a-[@face_group]
  face=nil
	cpoint=nil
  @face_group.entities.each{|e|
    face=e if e.class==Sketchup::Face
    cpoint=e if @cpoint && e.class==Sketchup::ConstructionPoint
  }
  bbc=face.bounds.center.transform!(@face_group.transformation)
  cpp=cpoint.position.transform!(@face_group.transformation) if cpoint
  ### face up always
  facenormal=face.normal
  face.reverse! if facenormal.z == -1.0
  ###
  if cpoint
    @snap_point=cpp
  else
    @snap_point=bbc
  end#if
  ### get an end point to place face
  sps=[];eps=[]
  @gedges.each{|e|
    if e.start.edges.length==1
      sps<< e.start.position
      eps<< e.end.position
    end#if
    if e.end.edges.length==1
      sps<< e.end.position
      eps<< e.start.position
    end#if
  }
  ### get sp/ep nearest face snap-point
  @sp=nil;@ep=nil
  if sps[0]
    dist=sps[0].distance(@snap_point)
    @sp=sps[0];@ep=eps[0]
    0.upto(sps.length-1){|i|
      if sps[i].distance(@snap_point)<dist
        @sp=sps[i]
        @ep=eps[i]
        dist=sps[i].distance(@snap_point)
      end#if
    }
  elsif eps[0]
    dist=eps[0].distance(@snap_point)
    @sp=sps[0];@ep=eps[0]
    0.upto(eps.length-1){|i|
      if eps[i].distance(@snap_point)<dist
        @sp=sps[i]
        @ep=eps[i]
        dist=eps[i].distance(@snap_point)
      end#if
    }
    if @sp.distance(@snap_point)>@ep.distance(@snap_point)
      @sp=@ep=@sp
    end#if
  else ### ==looped
    sps=[];eps=[]
    @gedges.each{|e|
      sps<< e.start.position
      eps<< e.end.position
    }
    @sp=sps[0];@ep=eps[0]
    dist=@sp.distance(@snap_point)
    0.upto(sps.length-1){|i|
      if sps[i].distance(@snap_point)<dist
        @sp=sps[i]
        @ep=eps[i]
        dist=@sp.distance(@snap_point)
      end#if
    }
    @sp.offset!(@sp.vector_to(@ep),@sp.distance(@ep)/2)
    ###
  end#if
end

def locate_face()
  face=@face_group.entities.grep(Sketchup::Face)[0]
  facenormal=face.normal
  ###
  ### translate face group to end of path
  tr=Geom::Transformation.translation(@snap_point.vector_to(@sp))
  @face_group.transform!(tr)
  ###
  edge_vector=@sp.vector_to(@ep)
  flat_vector=@sp.vector_to([@ep.x,@ep.y,@sp.z])
  flat_angle=Y_AXIS.angle_between(flat_vector)
  tr=Geom::Transformation.rotation(@sp,Z_AXIS,90.degrees)
  perp_flat_vector=flat_vector.transform(tr)
  tilt_angle=flat_vector.angle_between(edge_vector)
  tilt_angle= -tilt_angle if @sp.z<@ep.z
  ### check various orientations and locate/rotate face to suit
  if @sp.x==@ep.x && @sp.y==@ep.y ###vertical
    if @sp.z<@ep.z ### flip & rotate face
      tr=Geom::Transformation.rotation(@sp,X_AXIS,180.degrees)
    end#if
  elsif @sp.x>=@ep.x && @sp.y>=@ep.y
    tr=Geom::Transformation.rotation(@sp,Z_AXIS,-360.degrees+flat_angle)
    @face_group.transform!(tr)
    tr=Geom::Transformation.rotation(@sp,perp_flat_vector,-90.degrees)
    @face_group.transform!(tr)
    tr=Geom::Transformation.rotation(@sp,perp_flat_vector,tilt_angle)
    @face_group.transform!(tr)
  elsif @sp.x>=@ep.x && @sp.y<@ep.y
    tr=Geom::Transformation.rotation(@sp,Z_AXIS,-360.degrees+flat_angle)
    @face_group.transform!(tr)
    tr=Geom::Transformation.rotation(@sp,perp_flat_vector,-90.degrees)
    @face_group.transform!(tr)
    tr=Geom::Transformation.rotation(@sp,perp_flat_vector,tilt_angle)
    @face_group.transform!(tr)
  elsif @sp.x<=@ep.x && @sp.y<@ep.y
    tr=Geom::Transformation.rotation(@sp,Z_AXIS,-flat_angle)
    @face_group.transform!(tr)
    tr=Geom::Transformation.rotation(@sp,perp_flat_vector,-90.degrees)
    @face_group.transform!(tr)
    tr=Geom::Transformation.rotation(@sp,perp_flat_vector,tilt_angle)
    @face_group.transform!(tr)
  else
    tr=Geom::Transformation.rotation(@sp,Z_AXIS,-flat_angle)
    @face_group.transform!(tr)
    tr=Geom::Transformation.rotation(@sp,perp_flat_vector,-90.degrees)
    @face_group.transform!(tr)
    tr=Geom::Transformation.rotation(@sp,perp_flat_vector,tilt_angle)
    @face_group.transform!(tr)
  end#if
  ###
end

def make_extrusion()
  #@face_copy=nil
  #@cpoint_copy=nil
  #@face_group.entities.each{|e|
    #@face_copy=e if e.class==Sketchup::Face
    #@cpoint_copy=e if e.class==Sketchup::ConstructionPoint
  #}
  exx = @face_group.explode
	@face_copy=exx.grep(Sketchup::Face)[0]
	@cpoint_copy=exx.grep(Sketchup::ConstructionPoint)[0]
  ###
  @cpoint_copy.erase! if @cpoint_copy && @cpoint_copy.valid?
  ###
  fme=nil
  begin
    fme=@face_copy.followme(@gedges) #################################
  rescue
    fme=nil
  end
  if ! fme
		#p 123
		#p @selected
    @model.selection.add(@selected) if @selected[0].valid?
		#p 456
		#p @gents
    @model.selection.add(@gents.to_a) if @gents[0].valid?
    @msg=(db("Error: Extrusion NOT Possible..."))
    Sketchup::set_status_text(@msg)
    UI.messagebox(@msg)
    ###
    @done=false
    ###
  else
    ### flip right side out
    faces=@gents.grep(Sketchup::Face)
    maxface=faces[0]
    faces.each{|face|maxface=face if face.bounds.max.z >= maxface.bounds.max.z && face.bounds.min.z >= maxface.bounds.min.z}
    mfbbc=(maxface.vertices[0].position.offset(maxface.vertices[0].position.vector_to(maxface.vertices[2].position),(maxface.vertices[0].position.distance(maxface.vertices[2].position))/2)).transform!(@group.transformation)
    raytest1=@model.raytest(mfbbc, maxface.normal)
    if raytest1 && raytest1[1].include?(@group) #&& raytest1[0].distance(mfbbc)>0.05.mm
      faces.each{|face|face.reverse!}
    elsif raytest1 && ! raytest1[1].include?(@group)
      raytest2=@model.raytest(raytest1[0], maxface.normal)
      if raytest2 && raytest2[1].include?(@group)
        faces.each{|face|face.reverse!}
      end#if
    end#if
    ###
    @gents.to_a.each{|e|
      e.erase! if e.valid? && e.class==Sketchup::Edge && e.faces.length==0
      e.erase! if e.valid? && e.class==Sketchup::ConstructionLine
    }
    @done=true
    ###
  end#if
  ###
  #self.deactivate(@model.active_view)
	@model.active_view.invalidate
  ###
end
    
end#class -----------------------------------

end#module

