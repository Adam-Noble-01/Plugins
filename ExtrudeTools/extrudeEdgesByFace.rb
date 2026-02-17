=begin
  Copyright 2014-2018 (c), TIG
  All Rights Reserved.
  THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED 
  WARRANTIES,INCLUDING,WITHOUT LIMITATION,THE IMPLIED WARRANTIES OF 
  MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
###
  extrudeEdgesByFace.rb
###
  Extrudes a Face along a set of curves/edges to form a FollowMe-like 
  extrusion in a group.
###
Usage:
  Draw [or use] a Face that is 'flat'.
  [facing-up/down is not important as it is always assumed to face 'up']
  Faces that are not 'flat' are not allowed...
  The Face's rotation around the Z_AXIS is reflected in the final 
  extrusion - noticeable if the shape is asymmetrical.
  The Face's Y_AXIS is taken as the Face's initial vertical [Z_AXIS] 
  alignment.
  If the Path's first-edge is vertical then the Face is left aligned to 
  its Y_AXIS.
  You can also use an optional Cpoint [Guide] to be used as an 
  alternative "snap-point"**.
  Preselect the Face [and Cpoint if desired] and a set of Curves/Edges 
  that are joined end to end [note that the Face's edges will be 
  ignored if they were also selected, as will any other selected faces] 
  - these edges will form the extrusion's Path.
  The Face will be extruded along the Path from the Path's end vertex 
  that is nearest the Face's 'snap-point'** - this only becomes 
  important if the Face is asymetrical about the Y_AXIS center/snap-
  point, as there are then two possible extruded forms - which will be 
  mirror images of each other: so place the Face nearest the required 
  end in such cases...
  Having made the Selection Run the Tool: 'Extrude Edges by Face', 
  from the Plugins Menu, or its button on the Extrusions Toolbar...
  If the selected edges 'branch' or are disconnected then there is a 
  warning dialog: answer 'Yes' to try and make some sensible paths from 
  the selection [each Path will then be processed separately] or answer 
  'No' to reselect a suitable single path.
  The edge-set is copied into a group as the extrusion's 'Path'.  
  A copy of the Face is added to the end** of the Path, it is rotated 
  so that its normal is parallel to the vector of the first edge in the Path.
  If the Path is looped its nearesr vertex is used as the start.
  Note that convolutd looped paths using an asymetrical face may not 
  join the extrusion's 'ends' back together as expected [just as with a 
  normal 'FollowMe']...
  The Face's 'snap-point' is moved to the Path's end [this is the Face's 
  bounding-box center or if in selected the Cpoint#* as appropriate].
  #*Note that a Cpoint placed non-planar with the Face or remote from it 
  may give unexpected extrusions - perhaps even Bugsplats !
  Finally the extrusion/s is/are made in a single step: if the Face is 
  not oriented as desired, then one-step undo and Rotate/Flip Face or 
  move it t nearer the other end of the path or add/move the Cpoint etc 
  as needed: then re-run...

Donations:
   Are welcome [by PayPal], please use 'TIGdonations.htm' in the 
   ../Plugins/TIGtools/ folder.
   
Version:
   1.0 20100212 First release.
   1.1 20100212 Typo db fixed in def().
   1.2 20100215 Extrusion form now consistent, Pilou updated FR lingvo.
   1.3 20100216 All extrusion-tools now in one in Plugins sub-menu.
   1.4 20100222 Tooltips etc now deBabelized properly.
   1.5 20100312 Edge variables changed for EEbyRailsByFace compatibility.
   1.6 20100330 Rare glitch with self.xxx fixed.
   1.7 20101027 No suitable face in selection trapped with error message.
   1.8 20111207 Group.copy replaced to avoid clashes with rogue scripts.
   2.0 20130520 Becomes part of ExtrudeTools Extension.

=end

module ExtrudeTools

###
toolname="extrudeEdgesByFace"
cmd=UI::Command.new(db("Extrude Edges by Face")){Sketchup.active_model.select_tool(ExtrudeTools::ExtrudeEdgesByFace.new(true))}
cmd.tooltip=db("Extrude Edges by Face")
cmd.status_bar_text="..."
cmd.small_icon=File.join(EXTOOLS, "#{toolname}16x16.png")
cmd.large_icon=File.join(EXTOOLS, "#{toolname}24x24.png")
SUBMENU.add_item(cmd)
TOOLBAR.add_item(cmd)
###

class ExtrudeEdgesByFace

include ExtrudeTools

def extrudeEdgesByFace()
  ###
  @model=Sketchup.active_model
  @entities=@model.active_entities
  ### check selection
  selection=@model.selection
  selected_faces=[]
  selected_edges=[]
  selected_cpoints=[]
  selection.each{|e|
    selected_faces<< e if e.class==Sketchup::Face
    selected_edges<< e if e.class==Sketchup::Edge
    selected_cpoints<< e if e.class==Sketchup::ConstructionPoint
  }
  @face=selected_faces[0]
  @edges=[]
  selected_edges.each{|e|@edges<< e if @face && ! e.faces.include?(@face)}
  flat=true
	flat=false if @face && @face.normal.z.abs != 1.0
  if ! @face || ! @edges[0] || ! flat
    UI.messagebox(db("Select a 'Flat' Face and Edge(s) BEFORE using."))
    Sketchup.send_action("selectSelectionTool:")
    return nil
  end#if
  ###
  selection.clear
  ###
  bbmin=@face.bounds.min
  @cpoint=nil
  @cpoint=selected_cpoints[0] if selected_cpoints[0]
  ### move selection into a temp group ? 
  ### check for problems
  verts=[]
  @edges.each{|e| verts << e.vertices[0]<<e.vertices[1] }
  verts.uniq!
  edges1=0
  edges3=0
  verts.each{|v|
    edges1 +=1 if v.edges.length==1
    edges3 +=1 if v.edges.length>=3
  }
  if edges1>2 || edges3>0 || verts.length > 1+@edges.length ### two ends or branched or connected by unselected edge
    msg=((db("Path is Discontinuous or Branched."))+"\n\n"+(db("Yes = Process Extrusions in Pieces"))+"\n\n"+(db("No = Exit...")));Sketchup::set_status_text(msg)
    UI.beep
    reply=UI.messagebox(msg,MB_YESNO)### 6=YES 7=NO
    #@gp.explode if reply==7
    return nil if reply==7
		branched=true
	else
		branched=false
  end#if
  ###
  if Sketchup.version.to_i > 6
    @model.start_operation((db("Extrude Edges by Face")), true)
  else
    @model.start_operation((db("Extrude Edges by Face")))
  end
	###
	#p 123
	self.copy_edges_and_face()
  ###
	self.relocate_face()
	###
  ### split into sets if branched
	if branched
		@edge_sets=[]
		@oedges=@edges.dup
		while @edges[0]
			split(@edges)
		end
		@edge_sets.uniq!
		@edge_sets.compact!
		p @edge_sets.length
		p @edge_sets
	else ### NOT branched
		@edge_sets = [@edges]
	end
	###
	total=@edge_sets.length
  counter=1
  @edge_sets.each{|edge_set|
		next unless edge_set && edge_set[0]
		@msg=(db("Making Extrusion "))
		@msg=@msg+counter.to_s+(db( "of" ))+total.to_s if total>1
		Sketchup::set_status_text(@msg)
		counter+=1
		###
		begin
			###
			@sedges = edge_set
			###
			self.locate_face()
			###
			self.make_extrusion()
			#p 100
		rescue Exception => err
			p 666
			p err
			@model.selection.add edge_set
		end
  }
  ###
  @model.commit_operation
	###
end#def

def split(eds)
	ueds=[]
	ok=0
	vn=0
	eds.each{|ed|
		next unless @edges.include?(ed)
		ueds << ed
		@edges = @edges - [ed]
		ed.vertices.each{|v|
			ok=0
			es = v.edges - [ed]
			vn+=1 unless es[0] 
			es.each{|e|
				unless @edges.include?(e)
					vn+=1
					next
				end
				ok+=1
				break if ok > 1
				ueds << e
				#@edges = @edges - [e]
			}
		}
		break if ok > 1
		break if vn > 1
	}
	@edge_sets << ueds
end

def initialize(opt=false)
	@toolname="extrudeEdgesByFace"
	@opt=opt
	extrudeEdgesByFace() if @opt
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

def enableVCB?
  return true
end

def activate
  @model=Sketchup.active_model
  @entities=@model.active_entities
  selection=@model.selection
  selected_faces=[]
  selected_edges=[]
  selected_cpoints=[]
  selection.each{|e|
    selected_faces << e if e.class==Sketchup::Face
    selected_edges << e if e.class==Sketchup::Edge
    selected_cpoints << e if e.class==Sketchup::ConstructionPoint
  }
  @face=nil
  @face=selected_faces[0]
  @edges=[]
  selected_edges.each{|e|@edges << e if @face && ! e.faces.include?(@face)}
  flat=false
	flat=true if @face && @face.normal.z.abs==1
  if ! flat || ! @edges[0]
    UI.messagebox((db("Extrude Edges by Face:"))+"\n\n"+(db("Select a 'Flat' Face and Edge(s) BEFORE using."))) unless @opt
    Sketchup.send_action("selectSelectionTool:")
    return nil
  end#if
  ###
  selection.clear
  ###
  @cpoint=nil
  @cpoint=selected_cpoints[0] if selected_cpoints[0]
  @face_copy=nil
  @group=nil
  @gents=nil
  @face_group=nil
  @done=nil
  @msg=""
  Sketchup::set_status_text(@msg)
end

def resume(view)
  Sketchup::set_status_text(@msg)
  view.invalidate
end

def deactivate(view=nil)
  view.invalidate if view
  @group.erase! if ! @done && @group && @group.valid?
  Sketchup.send_action("selectSelectionTool:")
  return
end

def onCancel(reason,view)
  self.deactivate(view)
end

def copy_edges_and_face()
  ents = @face.edges
	ents << @face
  ents << @cpoint if @cpoint
  @face_group=@entities.add_group(ents)
  @temp_group = @entities.add_group( [@face_group] + [@edges] )
	@edges = @temp_group.entities.grep(Sketchup::Edge)
	@face_group = @temp_group.entities.grep(Sketchup::Group)
	@face = @face_group.entities.grep(Sketchup::Face)[0]
	@cpoint = @face_group.entities.grep(Sketchup::ConstructionPoint)[0] if @cpoint
	###
  bbc = @face.bounds.center.transform!(@face_group.transformation)
  cpp = @cpoint.position.transform!(@face_group.transformation) if @cpoint
  ### face up always
  facenormal = @face.normal
  @face.reverse! if facenormal.z == -1.0
  ###
  if @cpoint
    @snap_point=cpp
  else
    @snap_point=bbc
  end#if
end
###
def relocate_face()
  ### get an end point to place face
  sps=[]
	eps=[]
  @edges.each{|e|
		next unless e.valid?
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
  @sp=nil
	@ep=nil
  if sps[0]
    dist=sps[0].distance(@snap_point)
    @sp=sps[0];@ep=eps[0]
    0.upto(sps.length-1) do |i|
      if sps[i].distance(@snap_point)<dist
        @sp=sps[i]
        @ep=eps[i]
        dist=sps[i].distance(@snap_point)
      end#if
    end#do
  elsif eps[0]
    dist=eps[0].distance(@snap_point)
    @sp=sps[0];@ep=eps[0]
    0.upto(eps.length-1) do |i|
      if eps[i].distance(@snap_point)<dist
        @sp=sps[i]
        @ep=eps[i]
        dist=eps[i].distance(@snap_point)
      end#if
    end#do
    if @sp.distance(@snap_point)>@ep.distance(@snap_point)
      @sp=@ep=@sp
    end#if
  else ### ==looped
    sps=[]
		eps=[]
    @edges.each{|e|
			next unless e.valid?
      sps << e.start.position
      eps << e.end.position
    }
    @sp=sps[0]
		@ep=eps[0]
    dist = @sp.distance(@snap_point)
    0.upto(sps.length-1) do |i|
      if sps[i].distance(@snap_point) < dist
        @sp=sps[i]
        @ep=eps[i]
        dist=@sp.distance(@snap_point)
      end#if
    end#do
    @sp.offset!(@sp.vector_to(@ep),@sp.distance(@ep)/2)
    ###
  end#if
end

def locate_face()
	###
  #facenormal=@face.normal
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
	#p @gedges
  exx = @face_group.explode
	@face_copy = exx.grep(Sketchup::Face)[0]
	@cpoint_copy = exx.grep(Sketchup::ConstructionPoint)[0]
  ###
  @cpoint_copy.erase! if @cpoint_copy && @cpoint_copy.valid?
  ###
  fme=nil
  begin
    fme=@face_copy.followme(@gedges) #################################
  rescue Exception => err
    p 999
		p err
		fme=nil
  end
  if ! fme
    @msg=(db("Error: Extrusion NOT Possible..."))
    Sketchup::set_status_text(@msg)
    UI.messagebox(@msg)
    ###
    @done=false
    ###
  else
    ### flip right side out
    faces=[]
    @gents.each{|e|faces << e if e.class==Sketchup::Face}
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
  self.deactivate(@model.active_view)
end

def draw(view)
  if @ip && @ip.valid? && @ip.display?
    @ip.draw(view)
    @displayed=true
  else
    @displayed=false
  end#if
end
  
end#class -----------------------------------

end#module
