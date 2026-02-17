require 'sketchup.rb'

#Changelog

#1.0.1

#fixes for SketchUp 2014 compatibility

#1.0
#no changes


#RC1
#fixed planar projections on perpendicular faces
#pre-selected triangular faces are now remapped to remove distorted textures when using the triangulation function
#UV texture material is now named 'SketchUV Texture'
#now only updating the status bar every 0.5 seconds
#double-clicking on a vertex now aligns the camera to the vertex normal


#beta2
#better triangulation algorithm
#always softening/smoothing edges when triangulating (also setting cast shadow to false)
#automatically switch to view hidden geometry after triangulating
#automatically remapping UVs after triangulating to remove distorted perspective textures
#fixed spherical mapping at poles (was not always working properly)
#TT quad-face quads are produced by triangulating
#pressing enter now resets the path select tool
#hardening edges is now un-doable
#reworked icons
#non-textured materials are now overwritten by the UV material when applying mapping (except tube mapping)
#if tube mapping fails, the operation no longer aborts (this can help the user determine the face that caused tube mapping to fail)
#status bar now updates progress when triangulating

#beta1
#first release


#TODO

#improve triangulation? (support quadface?)
#support quadface tools for tube mapping?
#improve box mapping?
#improve tube mapping UI?
#use anchor to select spherical and cylindrical axis direction?
#improve nudging? (need to test more)
#improve loop selection to handle 90 degree angles?  favour co-planar edges?
#support sandbox quads?
#add split donut?
#add more instructions to tube fail message
#ask to select and group quads?

#bugs
#UV transform fail on n-gons (maybe only certain cases - draped)
#nudging fail (only after UVs have been uniformly scaled?)
#multiple scale transformation bugger up UVs

#Version 0.1

#initial release


module DM
module SketchUV

this_dir=File.dirname(__FILE__)
#Fix for ruby 2.0
if this_dir.respond_to?(:force_encoding)
	this_dir=this_dir.dup.force_encoding("UTF-8")
end
PATH=this_dir

#Fix for SketchUP 2014 - Set moved to Sketchup::Set
if defined?(Sketchup::Set)
 Set = Sketchup::Set
end

class DM_UVTool

def initialize
	@dict="DM_UVTools"
    @xdown = 0
    @ydown = 0
	@nudge=0.05
	@scale_nudge=1.05
	@rotate_nudge=1
	#@grid=Sketchup.read_default(@dict,'grid',true)
	@grid=false
	plugins=PATH
	rotate_icon = File.join(plugins,"rotate.png")
	@rotate_icon=UI.create_cursor(rotate_icon,12,12)
	@state0_status_text="Click vertex to set UV anchor point. Click-drag to spin view.  Enter value to rotate UVs. (Precede with * or / to scale UVs.)"
	@state1_status_text="Click anchor edge to set U direction for tube mapping.  Use arrow keys plus CTRL or SHIFT to transform UVs."
	@vcb_text="Rot | Scale"
end

def activate
    Sketchup::set_status_text("UV Transform", SB_VCB_LABEL)
	@ip1 = Sketchup::InputPoint.new
	@ip = Sketchup::InputPoint.new
	@anchor = Sketchup::InputPoint.new
    self.reset(nil)
end

def deactivate(view)
   view.invalidate
end

def onSetCursor

set_cursor()

end

def set_cursor

vert=@ip.vertex
edge=@ip.edge
face=@ip.face
if (vert==nil) and (edge==nil) and (face==nil)
	UI.set_cursor(@rotate_icon)
else
	UI.set_cursor(0)
end

end
#####
 def onLButtonDoubleClick(flags, x, y, view)
 

 face=@ip.face
 vertex=@ip.vertex
 a_ents=Sketchup.active_model.active_entities
 
 if vertex!=nil
	return if (vertex.parent.entities!=(a_ents))
	align_camera(view,vertex)
	return
end

 if face!=nil
	return if (face.parent.entities!=(Sketchup.active_model.active_entities))
	align_camera(view,face)
end
 
 end
###

def align_camera(view,e)

cam=view.camera
eye=cam.eye
up=cam.up

if e.class==Sketchup::Face
	face=e
	verts=face.vertices
	pos=verts.collect {|v| v.position}
	normal=face.normal
	box=Geom::BoundingBox.new
	box.add(pos)
	cent=box.center
end
if e.class==Sketchup::Vertex
	v_faces=e.faces
	num_faces=v_faces.length.to_f
	return if num_faces==0.0
	normal=[0.0,0.0,0.0]
	v_faces.each {|f|
		normal.x+=f.normal.x
		normal.y+=f.normal.y
		normal.z+=f.normal.z
	}
	
	normal=Geom::Vector3d.new((normal.x)/num_faces,(normal.y)/num_faces,(normal.z)/num_faces)
	cent=e.position
end
dist=(cent-eye).length  #distance from camera to face
normal.length=dist
new_eye=cent.offset(normal)

if up.parallel?(normal)
	up=Y_AXIS
end
cam.set(new_eye,cent,up)
cam.perspective=false

end

def getMenu(menu)

ents=Sketchup.active_model.selection
menu.add_item("Planar Map (View)") {(UVtools.new.planar_map(ents))}
menu.add_item("Spherical Map (View)") {(UVtools.new.spherical_map(ents))}
menu.add_item("Cylindrical Map (View)") {(UVtools.new.cylindrical_map2(ents))}
menu.add_item("Box Map") {(UVtools.new.box_map(ents))}
menu.add_item("Tube Map") {(tube_map(ents))}
menu.add_item("Quad Face Map") {(UVtools.new.quad_face_map(ents))}
menu.add_separator
menu.add_item("Triangulate") {triangulate()}
menu.add_item("Save UVs") {(store_uvs(ents))}
menu.add_item("Load UVs") {(position_map(ents))}
menu.add_separator
menu.add_item("Export UVs")  { UVtools.start_bridge()}
menu.add_item("Import UVs") { UVtools.return_bridge() }


end

####

def tube_map(ents)

unless @anchor_vertex
	UI.messagebox("You must first click on a vertex to select the origin of the UV map")
	return
end

unless @u_edge
	UI.messagebox("You must click on an adjacent edge to set the U direction.")
	return
end

UVtools.new.tube_map(ents,@anchor_vertex,@u_edge,@v_edge)


end

#####
def onMouseMove(flags, x, y, view)
	
	@ip.pick(view,x,y)
	if( @ip != @ip1 )
        view.invalidate if( @ip.display? or @ip1.display? )
        @ip1.copy! @ip
        view.tooltip = @ip1.tooltip
		
     end
	 
    if( @state == 0 )
     #
    else
		#p @dragging
        if @dragging==true
			rotate_view(x,y,view)
		end
        if( (x-@xdown).abs > 10 || (y-@ydown).abs > 10 )
            @dragging = true
        end
    end
	@x=x
	@y=y
end

def onLButtonDown(flags, x, y, view)

	
    if( @state == 0 )
        if(x!=nil) and (y!=nil)
            @state = 1
            @xdown = x
            @ydown = y
        end
    end
	view.invalidate
end

# The onLButtonUp method is called when the user releases the left mouse button.
def onLButtonUp(flags, x, y, view)
	@state=0
    if(@dragging)
        self.reset(view)
    else
		@ip1.pick(view,x,y)
		if @ip1.vertex
			@anchor.copy! @ip1
			@u_edge=nil
			@anchor_vertex=@ip1.vertex
			Sketchup.set_status_text(@state1_status_text)		
		end
		if @ip1.edge and @anchor_vertex
			@u_edge=@ip1.edge if @anchor_vertex.edges.index(@ip1.edge)
		end
	end
	view.invalidate
end

def get_offset(view,x,y)


offset_scale=4.0
#calculate the default offset
tw=Sketchup.create_texture_writer
pickray=view.pickray(x,y)
rt=Sketchup.active_model.raytest(pickray)
u_offset=0.05

begin
	if rt
		pos=rt[0]
		ent=rt[1].last  #should usually be a face
		sc=[x,y,0]
		if ent.class==Sketchup::Face
			uvh=ent.get_UVHelper(true,false,tw)
			uv1=uvh.get_front_UVQ(pos)
			sc.x+=4
			pickray=view.pickray(sc.x,sc.y)
			rt=Sketchup.active_model.raytest(pickray)
			pos=rt[0]
			ent=rt[1].last
			uv2=uvh.get_front_UVQ(pos)
			u_offset=(uv2-uv1).length
		end
	end
rescue
	u_offset=0.05
	raise
end

@nudge=u_offset*offset_scale
@scale_nudge=1.0+@nudge


end

def get_origin(ents)

origin=nil
if @anchor.valid?
		if @anchor.vertex
			vert=@anchor.vertex
			pos=vert.position
			tw=Sketchup.create_texture_writer
			uvs=[0,0,0]
			faces=vert.faces
			faces.delete_if {|face| !ents.contains?(face)}
			faces.delete_if {|face| face.material==nil}
			faces.delete_if {|face| face.material.texture==nil}
			faces=[faces[0]] unless faces.empty?
			faces.each {|f|
				#uvh=f.get_UVHelper(true,false,tw)
				#uv=uvh.get_front_UVQ(pos)
				#uvs[0]+=uv[0]
				#uvs[1]+=uv[1]
				#uvs[2]+=uv[2]
				
				mesh=f.mesh 5
				p_index=mesh.point_index(pos)
				uv=mesh.uv_at(p_index,1)
				uvw=uv[2]
				uv=uv.to_a
				uv=uv.collect {|point| point/uvw}
				uvs[0]+=uv[0]
				uvs[1]+=uv[1]
				uvs[2]+=uv[2]
			}
			num=faces.length.to_f
			if num>0
				origin=[uvs[0]/num,uvs[1]/num,uvs[2]/num]
			else
				origin=nil
			end
		end
	end

return origin

end

def onKeyDown(key, repeat, flags, view)
	ents=Sketchup.active_model.selection
	get_offset(view,@x,@y)
	origin=get_origin(ents)
	
	if ( key == VK_LEFT && repeat==1) #down arrow
		UVtools.new.offset_uvs(ents,@nudge,0.0) unless (@shift_down or @copy_down)
		UVtools.new.scale_uvs(ents,@scale_nudge,1.0,origin) if @shift_down
		UVtools.new.rotate_uvs(ents,-@rotate_nudge,origin) if @copy_down
	elsif (key == VK_RIGHT && repeat ==1 ) #up arrow
		UVtools.new.offset_uvs(ents,-@nudge,0.0) unless (@shift_down or @copy_down)
		UVtools.new.scale_uvs(ents,(1/@scale_nudge),1.0,origin) if @shift_down
		UVtools.new.rotate_uvs(ents,@rotate_nudge,origin) if @copy_down
	elsif (key == VK_DOWN && repeat ==1 ) #left arrow
		UVtools.new.offset_uvs(ents,0.0,@nudge) unless (@shift_down or @copy_down)
		UVtools.new.scale_uvs(ents,1.0,@scale_nudge,origin) if @shift_down
		UVtools.new.rotate_uvs(ents,-@rotate_nudge,origin) if @copy_down
	elsif (key == VK_UP && repeat ==1 ) #right arrow
		UVtools.new.offset_uvs(ents,0.0,-@nudge) unless (@shift_down or @copy_down)
		UVtools.new.scale_uvs(ents,1.0,(1/@scale_nudge),origin) if @shift_down
		UVtools.new.rotate_uvs(ents,@rotate_nudge,origin) if @copy_down
	elsif ( key == VK_SHIFT) #&& repeat == 1 )
		@shift_down=true
	elsif ( key == VK_CONTROL )
		@copy_down=true
	end
end

def resume(view)

view.invalidate

end

def onKeyUp(key, repeat, flags, view)
	case key
	when VK_SHIFT
		@shift_down=false
	when VK_CONTROL
		@copy_down=false
	when 9,15  #catch the tab key
		if @grid==false
			@grid=true
		else
			@grid=false
		end
		view.invalidate
	end
end

def onUserText(text, view)


cmd=text[0]

ents=Sketchup.active_model.selection
origin=get_origin(ents)

case cmd
	when 42,47,"*","\/"  # */ scale
		text=text[1..text.length]
		return if text==nil
		val=text.to_f
		return if val==0.0
		val=1.0/val if (cmd==47||cmd=="\/")
		if text[-1]==117||text[-1]=="u" #u
			UVtools.new.scale_uvs(ents,val,1.0,origin)
		elsif text[-1]==118||text[-1]=="v" #v
			UVtools.new.scale_uvs(ents,1.0,val,origin)
		else
			UVtools.new.scale_uvs(ents,val,val,origin)
		end
	else
		val=text.to_f
		UVtools.new.rotate_uvs(ents,val,origin)
end
    self.reset(view)
end

def draw_grid(view)

return if @grid==false
 view.drawing_color=[75,75,75]
 height=view.vpheight.to_f
 width=view.vpwidth.to_f
 
 divs=8.0

 h_step=height/divs
 w_step=h_step
 
 x_start=(width/2.0)-(height/2.0)
 x_end=(width/2.0)+(height/2.0)
 
divs=divs.to_i
 (divs+1).times {|i|
	if (i%4)==0
		view.line_width=1
		view.line_stipple=""
	else
		view.line_width=1
		view.line_stipple="."
	end
	x=w_step*(i)+x_start
	y=h_step*(i)
	view.draw2d(GL_LINES,[[x,0,0],[x,height,0],[x_start,y,0],[x_end,y,0]])
 }
 
  

end


def draw(view)

draw_grid(view)
l_width=5

if( @ip1.valid? )
	if( @ip1.display? and @ip1.vertex)
		@ip1.draw(view)
	end
end

if (@anchor.valid?)
	if (@anchor.display?)
		view.draw_points([@anchor.position],10,1,"red")
		#p @anchor.edge
		if @u_edge and @u_edge.valid?
			edge1=@u_edge
			view.drawing_color="red"
			view.line_width=l_width
			view.draw_line([edge1.start.position,edge1.end.position])
			if @anchor_vertex and @anchor_vertex.valid?
				vert=@anchor.vertex
				edges=vert.edges
				f1=@u_edge.faces[0]
				f2=@u_edge.faces[1]
				@v_edge=nil
				edges.each {|e|
					if ((e.common_face(@u_edge)) and (e!=@u_edge))
						f=e.common_face(@u_edge)
						vec1=@u_edge.other_vertex(vert).position-vert.position
						vec2=e.other_vertex(vert).position-vert.position
						if vec1.cross(vec2).samedirection?(f.normal)
							@v_edge=e
						end
					end
				}
			end
			if @v_edge
				edge1=@v_edge
				view.drawing_color="green"
				view.line_width=l_width
				view.draw_line([edge1.start.position,edge1.end.position])
			end
		end
	end
end


end

def onCancel(flag, view)
    self.reset(view)
end

def reset(view)
    @state = 0
    
    # Display a prompt on the status bar
    Sketchup::set_status_text(@state0_status_text, SB_PROMPT)
    Sketchup::set_status_text(@vcb_text, SB_VCB_LABEL)   
    if( view )
        view.tooltip = nil
        view.invalidate if @drawn
    end
    
	@u_edge=nil
	@v_edge=nil
	@anchor_vertex=nil
    @drawn = false
    @dragging = false
end

def rotate_view(x,y,view)

v_center_y=view.vpheight*0.5
v_center_x=view.vpwidth*0.5

x=x-v_center_x
y=y-v_center_y

x1=@x-v_center_x
y1=@y-v_center_y

a1=Math.atan2(y.to_f,x.to_f)
a2=Math.atan2(y1.to_f,x1.to_f)

angle=a2-a1

cam=view.camera
cam_trans=Geom::Transformation.new(cam.xaxis, cam.yaxis, cam.zaxis, cam.eye)
rot_trans=Geom::Transformation.rotation(cam.eye,cam.direction,angle)

yaxis=cam.yaxis

yaxis=yaxis.transform(rot_trans)

#cam_trans=cam_trans*rot_trans

cam.set(cam.eye,cam.direction,yaxis)

end

#####
def store_uvs(ents)

UVtools.start_operation("Store UVs")

face=0
tw=Sketchup.create_texture_writer

t=Time.now
last_update=Time.now
ents=ents.find_all {|e| e.class==Sketchup::Face}
for e in ents
	mat=e.material
	next if mat==nil
	next if mat.texture==nil
	verts=e.outer_loop.vertices
	points=verts.collect {|v| v.position}
	uvh=e.get_UVHelper(true,false,tw)
	uvs=points.collect {|p| uvh.get_front_UVQ(p)}
	for i in (0..uvs.length-1)
		uvs[i]=uvs[i].to_a  #converts the Point 3D objects to arrays so they won't be transformed
		uv_w=uvs[i].z
		uvs[i].x=uvs[i].x/uv_w
		uvs[i].y=uvs[i].y/uv_w
		uvs[i].z=uvs[i].z/uv_w
	end
	e.set_attribute 'uv_tools','uvs',uvs
	t=Time.now
	face+=1
	if (t-last_update)>0.5
		Sketchup.set_status_text("Stored uvs for #{face} faces.")
		last_update=Time.now
	end
		
end  #for
Sketchup.set_status_text(nil)
UVtools.commit_operation
UI.messagebox("Saved UVs for #{face} faces.")

end  #store_uvs

##
def position_map(entities)

UVtools.start_operation("Load UVs")
face=0
failed=0
key="uvs"
t=Time.now
last_update=Time.now

for e in entities
	next if e.material==nil
	if (e.valid?) and (e.class==Sketchup::Face)
		
		uvs=e.get_attribute 'uv_tools',key  
		#UI.messagebox(uvs)
		if uvs
			pos=[]
			verts=e.outer_loop.vertices
			points=verts.collect {|v| v.position}
			index=0
			points.each_index {|i|
				pos.push(points[i]) 
				pos.push(uvs[i])	
			}
			begin
				try_pos=pos[index..(index+7)]
				e.position_material e.material, try_pos, true
				face=face+1
				t=Time.now
				if (t-last_update)>0.5
					Sketchup.set_status_text("Loaded uvs for #{face} faces")
					last_update=Time.now
				end
			rescue  #this is required because SketchUp sometimes fails to position the texture properly
				#raise
				index+=1
				if pos[index+7]
					#p "retry"
					retry  #try to postion texture again using next polygon in the face
				else
					failed=failed+1
				end
			end
	
			
		end
	end
end
Sketchup.set_status_text(nil)
UVtools.commit_operation

if failed>0
	stext="Unable to load UVs for #{failed} faces.
Loaded UVs for #{face} faces."
else
	stext="Loaded UVs for #{face} faces."
end

UI.messagebox(stext)


end  #end position map

def triangulate()

selection=Sketchup.active_model.selection
t=Time.now
last_update=Time.now
faces=selection.find_all {|f| f.class==Sketchup::Face}
if faces.empty?
	UI.messagebox("You must first select at least one face.")
	return
end

if selection.length==0
	UI.messagebox("You must first make a selection.")
else
	#UVtools.start_operation("Triangulate",true)
	UVtools.start_operation("Triangulate")
	ents=Sketchup.active_model.active_entities
	t_group=ents.add_group
	t_group_ents=t_group.entities
	new_faces=[]
	new_edges=[]
	face=0
	selection.to_a.each {|e|
		if e.class==Sketchup::Face and e.valid?
			#new_faces.concat(triangulate_face(e,ents))
			t=Time.now
			face+=1
			new_edges.concat(triangulate_face(e,t_group_ents))
			if (t-last_update)>0.5
				Sketchup.set_status_text("Processing Face - #{face}")
				last_update=Time.now
			end
		end
	}
	count=0
	new_edge_set=Set.new
	new_edges.each {|edge|
		#next unless (edge.class==Sketchup::Edge)
		t=Time.now
		count+=1
		new_edge=ents.add_line(edge)
		new_edge_set.insert(new_edge) if new_edge
		if (t-last_update)>0.5
			Sketchup.set_status_text("Adding Edge - #{count}")
			last_update=Time.now
		end
	}
	new_edges=new_edge_set.to_a
	
	new_faces=Set.new
	count=0
	new_edges.each {|edge|
		t=Time.now
		count+=1
		if (t-last_update)>0.5
			Sketchup.set_status_text("Smoothing Edges - #{count}")
			last_update=Time.now
		end
		edge.soft=true;edge.smooth=true;edge.casts_shadows=false
		edge_faces=edge.faces
		edge_faces.each {|ef| new_faces.insert(ef)}
	}
	
	
	Sketchup.set_status_text("Remapping UVs...")
	remap(new_faces.to_a)
	
	#remap the original selected triangular faces
	tri_faces=selection.to_a.find_all {|e| ((e.class==Sketchup::Face) and (e.vertices.length==3))}
	remap(tri_faces)
	
	Sketchup.set_status_text("Done.")
	UVtools.commit_operation
	
	selection.clear
	Sketchup.active_model.rendering_options["DrawHidden"]=true
	
end

end
###
def fast_tri(faces)

model=Sketchup.active_model
ents=model.active_entities
face_verts={}
face_uvs={}
faces.each {|f|
	verts=f.vertices
	#norm=f.normal
	face_verts[f]=[] if not face_verts[f]
	verts.each {|v|	face_verts[f].push(v)}
}

face_verts.each {|f,verts|
		pos=verts.collect {|v| v.position}
		plane=Geom::fit_plane_to_points(pos)
		nor=Geom::Vector3d.new(plane[0],plane[1],plane[2])
		nor.length=0.1
		trans1=Geom::Transformation.new(nor)
		trans2=Geom::Transformation.new(nor.reverse)
		verts.each {|v|	ents.transform_entities(trans1,[v])}
		verts.each {|v|	ents.transform_entities(trans2,[v])}
		#ents.transform_entities(trans1,[verts[0]])
		#ents.transform_entities(trans2,[verts[0]])
}

new_faces=Set.new
face_verts.each_value {|verts|
	verts.each {|v| 
		faces=v.faces
		faces.each {|f| new_faces.insert(f)}
	}
}
new_faces=new_faces.to_a
non_tris=new_faces.find_all {|f| f.edges.length>3}

return new_faces

end
##
def remap(faces)

model=Sketchup.active_model
#model.start_operation("Remap",true)
ents=model.active_entities
#faces=model.selection.find_all {|e| e.class==Sketchup::Face}
tw=Sketchup.create_texture_writer
face=0
failed=0

faces.each {|e|
	mat=e.material
	next if mat==nil
	next if mat.texture==nil
	verts=e.outer_loop.vertices
	points=verts.collect {|v| v.position}
	index=0
	uvh=e.get_UVHelper(true,false,tw)
	uvs=points.collect {|p| uvh.get_front_UVQ(p)}
	for i in (0..uvs.length-1)
		uvs[i]=uvs[i].to_a  #converts the Point 3D objects to arrays so they won't be transformed
		uv_w=uvs[i].z
		uvs[i].x=uvs[i].x/uv_w
		uvs[i].y=uvs[i].y/uv_w
		uvs[i].z=1.0
	end
	pos=[]
	points.each_index {|i|
		pos.push(points[i]) 
		pos.push(uvs[i])	
	}
	begin
		try_pos=pos[index..(index+7)]
		e.position_material e.material, try_pos, true
		face=face+1
		#Sketchup.set_status_text("Loaded uvs for #{face} faces")
	rescue  #this is required because SketchUp sometimes fails to position the texture properly
		#raise
		index+=1
		if pos[index+7]
			#p "retry"
			retry  #try to postion texture again using next polygon in the face
		else
			failed=failed+1
		end
	end
}
#model.commit_operation

end

####
def centroid(verts)

cent=[0.0,0.0,0.0]
num_verts=verts.length.to_f

verts.each {|v|
	v=v.position if v.class==Sketchup::Vertex
	cent[0]+=v.x
	cent[1]+=v.y
	cent[2]+=v.z
}
cent[0]/=num_verts
cent[1]/=num_verts
cent[2]/=num_verts

return cent

end
########
def triangulate_face(f,ents)

edges=[]
loops=f.loops

if loops.length==1 and loops[0].convex?
	verts=f.vertices
	num_verts=verts.length
	if num_verts==3
		polymesh=nil
	elsif num_verts==4
		polymesh=f.mesh
	else
		polymesh=f.mesh
	end
else
	polymesh=f.mesh
end


if polymesh
	#new_faces=Set.new
	#edges=Set.new
	#front_mat=f.material
	#back_mat=f.back_material
	#ents.erase_entities(f)
	polys=polymesh.polygons
	polys.each {|poly|
		begin
			#new_face=nil
			#new_face=ents.add_face(polymesh.point_at(poly[0]),polymesh.point_at(poly[1]),polymesh.point_at(poly[2]))
			#ents.add_faces_from_mesh(polymesh)
			edges.push([polymesh.point_at(poly[0]),polymesh.point_at(poly[1])]) if poly[0]<0
			edges.push([polymesh.point_at(poly[1]),polymesh.point_at(poly[2])]) if poly[1]<0
			edges.push([polymesh.point_at(poly[2]),polymesh.point_at(poly[0])]) if poly[2]<0
			
			#e1=(ents.add_line(polymesh.point_at(poly[0]),polymesh.point_at(poly[1])))
			#e2=(ents.add_line(polymesh.point_at(poly[1]),polymesh.point_at(poly[2])))
			#e3=(ents.add_line(polymesh.point_at(poly[2]),polymesh.point_at(poly[0])))
			
			#edges.insert(e1) if e1
			#edges.insert(e2) if e2
			#edges.insert(e3) if e3
			#if new_face
			#	new_faces.insert(new_face)		
			#	new_face.material=front_mat
			#	new_face.back_material=back_mat
			#end
		rescue
			p polymesh.point_at(poly[0]),polymesh.point_at(poly[1]),polymesh.point_at(poly[2])
			raise
		end
	}
	#p new_faces.to_a
	
end

return edges
#return new_faces.to_a

end



end  #class


class UVtools

@@selected_faces=[]

def initialize
	@points=[]
	@box=nil
end

###
def self.start_operation(name)

if Sketchup.version.split(".")[0].to_i>=7
	Sketchup.active_model.start_operation(name,true)
else
	Sketchup.active_model.start_operation(name)
end

end

####
def self.commit_operation()


Sketchup.active_model.commit_operation

end

###

def get_uv_material()

mat_name="SketchUV Texture"
mats=Sketchup.active_model.materials
uv_mat=mats[mat_name]
plugins=PATH
path=File.join(plugins,"texture_grid.jpg")
if uv_mat==nil
	uv_mat=mats.add(mat_name)
	uv_mat.texture=path
	#uv_mat.texture.size=12.0
end

if uv_mat.texture==nil
	UI.messagebox("Unable to find UV texture grid in path #{path}.")
end

return uv_mat

end

####
def offset_uvs(faces,u_offset,v_offset)


UVtools.start_operation("Offset UVs")
faces=get_faces(faces)
tw=Sketchup.create_texture_writer
vec=Geom::Vector3d.new(u_offset,v_offset,0)



faces.each {|f|
	mat=f.material
	next if mat==nil
	next if mat.texture==nil
	verts=f.vertices
	points=verts.collect {|v| v.position}
	uvh=f.get_UVHelper(true,false,tw)
	uvs=points.collect {|p| uvh.get_front_UVQ(p)}
	uvs.each {|uv|
		uv[0]=uv[0]/uv[2]
		uv[1]=uv[1]/uv[2]
		#uv[2]=uv[2]/uv[2]
		uv[2]=1.0
	}
	#mesh=f.mesh 5
	#uvs=mesh.uvs(true)
	trans=Geom::Transformation.translation(vec)
	uvs.each {|uv| uv.transform!(trans)}
	if points.length==3
		pt_array=[points[0],uvs[0],points[1],uvs[1],points[2],uvs[2]]
	else
		pt_array=[points[0],uvs[0],points[1],uvs[1],points[2],uvs[2],points[3],uvs[3]]
	end
	begin
		f.position_material(mat,pt_array,true)
	rescue
		next
	end
}
tw=nil
UVtools.commit_operation
end
###
def get_center_uvs(faces,tw)

box=Geom::BoundingBox.new
faces.each {|f|
	mesh=f.mesh 5
	uvs=mesh.uvs(true)
	uvs.each {|uv| box.add(uv)}
}
return box.center
end

def get_center_uvs_void(faces,tw)

box=Geom::BoundingBox.new
faces.each {|f|
	verts=f.vertices
	points=verts.collect {|v| v.position}
	uvh=f.get_UVHelper(true,false,tw)
	uvs=points.collect {|p| uvh.get_front_UVQ(p)}
	uvs.each {|uv| box.add(uv)}
}
return box.center
end
###
def rotate_uvs(faces,angle,origin=nil)

angle=angle.degrees
UVtools.start_operation("Rotate UVs")
faces=get_faces(faces)
tw=Sketchup.create_texture_writer
origin=get_center_uvs(faces,tw) if origin==nil
axis=Geom::Vector3d.new(0,0,1)

faces.each {|f|
	mat=f.material
	next if mat==nil
	next if mat.texture==nil
	verts=f.vertices
	points=verts.collect {|v| v.position}
	uvh=f.get_UVHelper(true,false,tw)
	uvs=points.collect {|p| uvh.get_front_UVQ(p)}
	uvs.each {|uv|
		uv[0]=uv[0]/uv[2]
		uv[1]=uv[1]/uv[2]
		#uv[2]=uv[2]/uv[2]
		uv[2]=1.0
	}
	#mesh=f.mesh 5
	#uvs=mesh.uvs(true)
	trans=Geom::Transformation.rotation(origin,axis,angle)
	uvs.each {|uv| uv.transform!(trans)}
	if points.length==3
		pt_array=[points[0],uvs[0],points[1],uvs[1],points[2],uvs[2]]
	else
		pt_array=[points[0],uvs[0],points[1],uvs[1],points[2],uvs[2],points[3],uvs[3]]
	end
	begin
		f.position_material(mat,pt_array,true)
	rescue
		next
	end
}
tw=nil
UVtools.commit_operation
end
###
def scale_uvs(faces,u_scale,v_scale,origin=nil)

UVtools.start_operation("Scale UVs")
faces=get_faces(faces)
tw=Sketchup.create_texture_writer
origin=get_center_uvs(faces,tw) if origin==nil
origin.z=1.0
faces.each {|f|
	mat=f.material
	next if mat==nil
	next if mat.texture==nil
	verts=f.vertices
	points=verts.collect {|v| v.position}
	uvh=f.get_UVHelper(true,false,tw)
	uvs=points.collect {|p| uvh.get_front_UVQ(p)}
	uvs.each {|uv|
		uv[0]=uv[0]/uv[2]
		uv[1]=uv[1]/uv[2]
		#uv[2]=uv[2]/uv[2]
		uv[2]=1.0
	}
	#mesh=f.mesh 5
	#uvs=mesh.uvs(true)
	trans=Geom::Transformation.scaling(origin,u_scale,v_scale,1.0)
	uvs.each {|uv| uv.transform!(trans)}
	#uvs.each {|uv| uv[0]=uv[0]*u_scale;uv[1]=uv[1]*v_scale;uv[2]=uv[2]*v_scale}
	if points.length==3
		pt_array=[points[0],uvs[0],points[1],uvs[1],points[2],uvs[2]]
	else
		pt_array=[points[0],uvs[0],points[1],uvs[1],points[2],uvs[2],points[3],uvs[3]]
	end
	begin
		f.position_material(mat,pt_array,true)
	rescue
		next
	end
}
tw=nil
UVtools.commit_operation
end
######################
def get_bounds(ents)


all_points=[]
ents.each {|e|
	if e.class==Sketchup::Face
		all_points.push(e.vertices)
	end
}

return if all_points.empty?

all_points.flatten!
all_points.uniq!

box=Geom::BoundingBox.new
all_points.each {|v| box.add(v.position)}

@box=box

end

######################
def get_center(ents)  #returns the bounding box center of the selection

get_bounds(ents)
return @box.center

end

######################
def get_zmax_min(ents)  

get_bounds(ents)
return [@box.max.z,@box.min.z]

end

########################
def get_spherical_uv2(p,c,axis,default)  

pi=Math::PI

proj_point=p.project_to_line(axis)
vec=(proj_point-p).reverse

angle=Math.atan2(vec.cross(default).length,vec.dot(default))

axis_vec=axis[1].reverse
trip=axis_vec.dot(vec.cross(default))
if trip<0.0
	angle=-angle
end

v=p-c
v=c-p  

theta=axis_vec.angle_between(v)

v=1.0-(theta/pi)

if angle<0.0 
	angle=2*pi+angle
end

u=(angle/(2*pi))

return [u,v,0.0]

end
########################
def get_spherical_uv(p,c)  #p is the point we want to get the uvs for, c is the spherical center

pi=Math::PI
dx=p.x-c.x
dy=p.y-c.y
dz=p.z-c.z

theta=Math.acos(dz/(Math.sqrt(dx**2+dy**2+dz**2)))
phi=Math.atan2(dy,dx)

v=1.0-(theta/pi)

if phi<0.0 
	phi=2*pi+phi
end

u=(phi/(2*pi))

return [u,v,0.0]

end

#####
def get_cylindrical_uv2(p,z_extents,axis,default)

#c=Geom::Point3d.new(@box.center)

pi=Math::PI
#dx=p.x-c.x
#dy=p.y-c.y
proj_point=p.project_to_line(axis)
vec=(proj_point-p) #the vector from this point to the closest point on the axis

#angle=Math.atan2(length(cross(v,default)),dot(v,default))
angle=Math.atan2(vec.cross(default).length,vec.dot(default))

axis_vec=axis[1].reverse
trip=axis_vec.dot(vec.cross(default))
if trip<0.0
	angle=-angle
end

zmax=z_extents[0]
zmin=z_extents[1]

view=Sketchup.active_model.active_view
sc=view.screen_coords(p)

dz=(sc.y-zmin)/(zmax-zmin)
dz=1-dz

v=dz

if angle<0.0 
	angle=2*pi+angle
	#phi=-phi
end

u=angle/(2*pi)

return [u,v,0.0]

end
########################
def get_cylindrical_uv(p,z_extents)  #p is the point we want to get the uvs for, ymin is the base of the cylinder

c=Geom::Point3d.new(@box.center)

pi=Math::PI
dx=p.x-c.x
dy=p.y-c.y

zmax=z_extents[0]
zmin=z_extents[1]
dz=(p.z-zmin)/(zmax-zmin)


phi=Math.atan2(dy,dx)

v=dz

if phi<0.0 
	phi=2*pi+phi
	#phi=-phi
end

u=phi/(2*pi)

return [u,v,0.0]

end

##########################
def validate_uvs(uvs)

u_arr=uvs.collect {|p| p.x}
u_max=u_arr.max
u_arr.each_index {|i|
	if u_arr[i]!=u_max
		if (u_max-u_arr[i])>0.8  #check for overlap
			#p "overlapped"
			u_arr[i]+=1.0
		end
	end
}

uvs.each_index {|i| uvs[i].x=u_arr[i]}  #modify the original uv array to fix the overlap

return uvs

end

##############################
def resize_uvs(uvs,mat)

tex=mat.texture
return if tex==nil

h=tex.height
w=tex.width

new_uvs=[]
uvs.each_index {|i|
	new_uvs[i]=Geom::Point3d.new(0,0,0)
	new_uvs[i].x=uvs[i].x*w
	new_uvs[i].y=uvs[i].y*h
	new_uvs[i].z=uvs[i].z
}

return new_uvs

end

###
def quad_face_map(ents)

faces=ents.find_all {|f| f.class==Sketchup::Face}
faces=faces.find_all {|f| f.edges.length==4}
faces=faces.find_all {|f| f.outer_loop.convex?}  #ensures no colinear edges
if faces.empty?
	UI.messagebox("You must first select at least one valid quad face.")
	return
end

UVtools.start_operation("Quad Face Map")
mat=get_uv_material()

uv0=[0,0,1]
uv1=[1,0,1]
uv2=[1,1,1]
uv3=[0,1,1]
uvs=[uv0,uv1,uv2,uv3]

faces.each {|f|
	material=f.material ? f.material : mat
	material=mat if material.texture==nil
	loop_verts=f.outer_loop.vertices
	points=loop_verts.collect {|v| v.position}
	pt_array=[points[0],uvs[0],points[1],uvs[1],points[2],uvs[2],points[3],uvs[3]]
	f.position_material(material,pt_array,true)
}

UVtools.commit_operation

end

####

def tube_map(faces,v_origin,u_edge,v_edge)

UVtools.start_operation("Tube Map")

begin
faces=faces.find_all {|f| f.class==Sketchup::Face}



#set the material to the common faces material if it has a texture
f=u_edge.common_face(v_edge)
if f
	mat=f.material
end
if mat and (mat.texture!=nil)
	#
else
	mat=get_uv_material()
end

#faces.each {|f| f.material=mat}

sel=Sketchup.active_model.selection
tex_width=mat.texture.width
tex_height=mat.texture.height

uv0=[0,0,1]
uv1=[1,0,1]
uv2=[1,1,1]
uv3=[0,1,1]
uvs=[uv0,uv1,uv2,uv3]

current_u_vertex=v_origin
current_v_vertex=v_origin
first_vertex=v_origin

ring_edges=get_ring_edges(v_edge,u_edge,current_v_vertex)

#store the cap face is there is one
if ring_edges.length>2 #if so, we could have a cap face
	cap_face=ring_edges[0].common_face(ring_edges[1])
end

ring_edges.each {|ring_edge|
	ring_edge_faces=ring_edge.faces
	ring_edge_faces.each {|ref|
		if ref.edges.length>4
			split_fm_poly(ref,ring_edge) unless ref==cap_face
		end
	}
}
	
current_u_val=0.0
current_v_val=0.0
u_values=[]
v_values=[]
v_edge_index=0

ring_edges.each {|ring_edge|
	
	ring_edge_length=ring_edge.length.to_f
	v_offset=ring_edge_length/tex_height
	
	if v_values[v_edge_index]==nil
		v_values[v_edge_index]=current_v_val
	end
	next_v_val=current_v_val+v_offset
	if v_values[v_edge_index+1]==nil
		v_values[v_edge_index+1]=next_v_val
	end
	
	
	
	current_u_val=0.0
	u_edges=get_loop_edges(u_edge,first_vertex)
	#sel.add(u_edges)
	v_edge=ring_edge
	current_u_vertex=first_vertex
	u_edge_index=0
	face=nil
	u_edges.each {|edge|
		edge_length=edge.length.to_f
		u_offset=edge_length/tex_width
		if u_values[u_edge_index]==nil
			u_values[u_edge_index]=current_u_val
		end
		next_u_val=current_u_val+u_offset 
		if u_values[u_edge_index+1]==nil
			u_values[u_edge_index+1]=next_u_val
		end
		#p u_values[u_edge_index]
		#p u_values[u_edge_index+1]
		face=edge.common_face(v_edge)
		next if face==nil
		loop=face.outer_loop
		loop_verts=loop.vertices #an ordered array of vertices we hope
		edge_uses=loop.edgeuses
		shift=loop_verts.index(current_u_vertex)
		uvs[0]=[u_values[u_edge_index],v_values[v_edge_index],1]
		uvs[1]=[u_values[u_edge_index+1],v_values[v_edge_index],1]
		uvs[2]=[u_values[u_edge_index+1],v_values[v_edge_index+1],1]
		uvs[3]=[u_values[u_edge_index],v_values[v_edge_index+1],1]
		#uvs[0]=[u_values[u_edge_index],0,1]
		#uvs[1]=[u_values[u_edge_index+1],0,1]
		#uvs[2]=[u_values[u_edge_index+1],1,1]
		#uvs[3]=[u_values[u_edge_index],1,1]
		#p uvs
		#p shift
		if shift!=0
			shift_uvs=shift_array(uvs,shift)
		else
			shift_uvs=uvs.dup
		end
		points=loop_verts.collect {|v| v.position}
		#p points
		#p shift_uvs
		#next if points.length!=4
		pt_array=[points[0],shift_uvs[0],points[1],shift_uvs[1],points[2],shift_uvs[2],points[3],shift_uvs[3]]
		face.position_material(mat,pt_array,true)
		sel.add(face)
		
		edge_use=edge_uses.find {|eu| eu.edge==edge}
		v_edge=edge_use.next.edge
		current_u_vertex=edge.other_vertex(current_u_vertex)
		u_edge_index+=1
		current_u_val=next_u_val
		#UI.messagebox("test")
	}

	first_vertex=ring_edge.other_vertex(first_vertex)
	current_u_edges=first_vertex.edges
	u_edge=current_u_edges.find {|e| ((e.common_face(u_edges[0])) and (!ring_edges.index(e)))}
	
	v_edge_index+=1
	current_v_val=next_v_val

	
}  #end ring edges each
rescue	
	#Sketchup.active_model.abort_operation
	UI.messagebox("Unable to perform Tube Mapping.  Try the following:
Ensure the connected faces do not contain holes.
Ensure there are no internal hidden faces.
Select only the quad faces and make a group.
Try tube mapping the faces within the new group.")
	raise 
end #begin
UVtools.commit_operation

end

###
def self.select_loop()

sel=Sketchup.active_model.selection.first
unless sel.class==Sketchup::Edge
	UI.messagebox("You must first select a single edge in a quad-based mesh.")
end

end

###
def split_fm_poly(face,edge)

begin
model=Sketchup.active_model
model.start_operation("Split Poly")
ents=model.active_entities
t_group=ents.add_group()
g_ents=t_group.entities

avoid=[]
num_steps=(face.edges.length-4)/2.0
num_steps=num_steps.to_i
#num_steps=((num_steps+0.5).to_i)

s_vert=edge.start
e_vert=edge.end

s_edges=(s_vert.edges)-[edge]
s_edge=s_edges.find {|e| e.used_by?(face)}

e_edges=(e_vert.edges)-[edge]
e_edge=e_edges.find {|e| e.used_by?(face)}

cv1=s_edge.other_vertex(s_vert)
cv2=e_edge.other_vertex(e_vert)
c_edge1=s_edge
c_edge2=e_edge

avoid.push(c_edge1)
avoid.push(c_edge2)

num_steps.times {

g_ents.add_line(cv1,cv2)

c_edges1=cv1.edges.delete_if {|e| avoid.include?(e)}
c_edges2=cv2.edges.delete_if {|e| avoid.include?(e)}

c_edge1=c_edges1.find {|e| e.used_by?(face)}
c_edge2=c_edges2.find {|e| e.used_by?(face)}

cv1=c_edge1.other_vertex(cv1)
cv2=c_edge2.other_vertex(cv2)

avoid.push(c_edge1)
avoid.push(c_edge2)

}
t_group.explode

rescue
	model.abort_operation
	#raise

end

end

####

def shift_array(arr,shift)

len=arr.length
shifted=[]
arr.each_index {|index|
	new_pos=(index+shift)%len
	shifted[new_pos]=arr[index]
}
return shifted

end
###
def get_loop_edges(edge,s_vert)

loop_edges=[]
loop_edges.push(edge)

e_vert=edge.other_vertex(s_vert)
count=0
found_next_edge=true
while (found_next_edge)
	found_next_edge=false
	count+=1
	edge_faces=edge.faces  #these faces cannot be used by the 'next' edge
	#p edge_faces
	e_vert_edges=e_vert.edges
	e_vert_edges.each {|eve|
		#eve_faces=eve.faces
		#if ((eve_faces.include?(edge_faces[0])) or (eve_faces.include?(edge_faces[1])) or (loop_edges.include?(eve)))
		if ((eve.common_face(edge)) or (loop_edges.include?(eve)))
			#
		else
			edge=eve
			loop_edges.push(edge)
			e_vert=edge.other_vertex(e_vert)
			found_next_edge=true
		end
	}
	
	break if count==200

end

return loop_edges
Sketchup.active_model.selection.clear
Sketchup.active_model.selection.add(loop_edges)

end
###
def get_ring_edges(v_edge,u_edge,s_vert)



edge=v_edge
ring_edges=[]
ring_edges.push(edge)


e_vert=edge.other_vertex(s_vert)
count=0
found_next_edge=true

while (found_next_edge)
	found_next_edge=false
	count+=1
	uv_face=edge.common_face(u_edge)  #get the face that is common to both edges
	uv_loop_edges=uv_face.outer_loop.edges
	u_edge=uv_loop_edges.find {|e| (e.used_by?(e_vert)) and (e!=edge)}  #found the next u_edge
	
	edge_faces=edge.faces 
	#p edge_faces
	e_vert_edges=e_vert.edges 
	
	e_vert_edges.each {|eve|
		#eve_faces=eve.faces
		#if ((eve_faces.include?(edge_faces[0])) or (eve_faces.include?(edge_faces[1])) or (ring_edges.include?(eve)))
		if (eve.common_face(u_edge)) and (eve!=u_edge) and (!ring_edges.include?(eve)) #and ((eve.faces&edge_faces).empty?)
			edge=eve
			ring_edges.push(edge)
			e_vert=edge.other_vertex(e_vert)
			found_next_edge=true
		end
	}
	break if count==200

end

return ring_edges
Sketchup.active_model.selection.clear
Sketchup.active_model.selection.add(ring_edges)

end
####
def box_map(faces)

faces=faces.find_all {|f| f.class==Sketchup::Face}
if faces.empty?
	UI.messagebox("You must first select at least one face.")
	return
end

UVtools.start_operation("Box Map")
mat=get_uv_material()

box=Geom::BoundingBox.new
faces.each {|f|
	verts=f.vertices
	verts.each {|v| box.add(v.position)}
}
ents=Sketchup.active_model.active_entities
p1=[box.min.x,box.min.y,box.min.z]
p2=[box.max.x,box.min.y,box.min.z]
p3=[box.max.x,box.max.y,box.min.z]
p4=[box.min.x,box.max.y,box.min.z]
p5=[box.min.x,box.min.y,box.max.z]
p6=[box.max.x,box.min.y,box.max.z]
p7=[box.max.x,box.max.y,box.max.z]
p8=[box.min.x,box.max.y,box.max.z]

max_size=[box.width,box.height,box.depth].max
offset_x=Geom::Vector3d.new(max_size,0,0)
offset_y=Geom::Vector3d.new(0,max_size,0)
offset_z=Geom::Vector3d.new(0,0,max_size)

box.add(box.min.offset(offset_x))
box.add(box.min.offset(offset_y))
box.add(box.min.offset(offset_z))


p1=[box.min.x,box.min.y,box.min.z]
p2=[box.max.x,box.min.y,box.min.z]
p3=[box.max.x,box.max.y,box.min.z]
p4=[box.min.x,box.max.y,box.min.z]
p5=[box.min.x,box.min.y,box.max.z]
p6=[box.max.x,box.min.y,box.max.z]
p7=[box.max.x,box.max.y,box.max.z]
p8=[box.min.x,box.max.y,box.max.z]

group=ents.add_group
ents=group.entities
f1=ents.add_face(p1,p2,p3,p4) #bottom face
f2=ents.add_face(p5,p6,p7,p8) #top face
f3=ents.add_face(p1,p5,p8,p4) #left face
f4=ents.add_face(p2,p3,p7,p6) #right face
f5=ents.add_face(p1,p2,p6,p5)  #front face
f6=ents.add_face(p4,p8,p7,p3)  #back face

f1.reverse! unless f1.normal.samedirection?(Z_AXIS.reverse)
f2.reverse! unless f2.normal.samedirection?(Z_AXIS)
f3.reverse! unless f3.normal.samedirection?(X_AXIS.reverse)
f4.reverse! unless f4.normal.samedirection?(X_AXIS)
f5.reverse! unless f5.normal.samedirection?(Y_AXIS.reverse)
f6.reverse! unless f6.normal.samedirection?(Y_AXIS)

uv0=[0,0,1]
uv1=[1,0,1]
uv2=[1,1,1]
uv3=[0,1,1]

#TODO - make box to use continuous UVs where possible
f1.position_material(mat,[p4,uv0,p3,uv1,p2,uv2,p1,uv3],true)
f2.position_material(mat,[p5,uv0,p6,uv1,p7,uv2,p8,uv3],true)
f3.position_material(mat,[p4,uv0,p1,uv1,p5,uv2,p8,uv3],true)
f4.position_material(mat,[p2,uv0,p3,uv1,p7,uv2,p6,uv3],true)
f5.position_material(mat,[p1,uv0,p2,uv1,p6,uv2,p5,uv3],true)
f6.position_material(mat,[p3,uv0,p4,uv1,p8,uv2,p7,uv3],true)

tw=Sketchup.create_texture_writer
uvh1=f1.get_UVHelper(true,false,tw)
uvh2=f2.get_UVHelper(true,false,tw)
uvh3=f3.get_UVHelper(true,false,tw)
uvh4=f4.get_UVHelper(true,false,tw)
uvh5=f5.get_UVHelper(true,false,tw)
uvh6=f6.get_UVHelper(true,false,tw)

p1=[]
p2=[]
p3=[]
p4=[]
p5=[]
p6=[]

theta=45.degrees


faces.each {|f|
	a1=f.normal.angle_between(f1.normal)
	a2=f.normal.angle_between(f2.normal)
	a3=f.normal.angle_between(f3.normal)
	a4=f.normal.angle_between(f4.normal)
	a5=f.normal.angle_between(f5.normal)
	a6=f.normal.angle_between(f6.normal)
	
	arr=[a1,a2,a3,a4,a5,a6]
	min_angle=arr.min
	index=arr.index(min_angle)
	
	case index
	when 0
		p1.push(f)
	when 1
		p2.push(f)
	when 2
		p3.push(f)
	when 3
		p4.push(f)
	when 4
		p5.push(f)
	when 5
		p6.push(f)
	end
	
}

project_box(p1,mat,uvh1)
project_box(p2,mat,uvh2)
project_box(p3,mat,uvh3)
project_box(p4,mat,uvh4)
project_box(p5,mat,uvh5)
project_box(p6,mat,uvh6)
	
ents.erase_entities([group])

UVtools.commit_operation

end

def project_box(faces,mat,uvh)

faces.each {|f|
	material=f.material ? f.material : mat
	material=mat if material.texture==nil
	verts=f.vertices
	points=verts.collect {|v| v.position}
	uvs=points.collect {|p| uvh.get_front_UVQ(p)}
	if points.length==3
		pt_array=[points[0],uvs[0],points[1],uvs[1],points[2],uvs[2]]
	else
		pt_array=[points[0],uvs[0],points[1],uvs[1],points[2],uvs[2],points[3],uvs[3]]
	end
	begin
		f.position_material(material,pt_array,true)
	rescue
		next
	end
}

end
 
########
def planar_map(faces)

faces=faces.find_all {|f| f.class==Sketchup::Face}
if faces.empty?
	UI.messagebox("You must first select at least one face.")
	return
end

UVtools.start_operation("Planar Map")

mat=get_uv_material()

view=Sketchup.active_model.active_view
camera=view.camera
screen_coords_x=Hash.new
screen_coords_y=Hash.new
box=Geom::BoundingBox.new
verts=get_verts(faces)
verts.each {|v|
	coords=view.screen_coords(v.position)
	screen_coords_x[v]=coords.x
	screen_coords_y[v]=coords.y
	box.add(v.position)
}

min_x=screen_coords_x.values.min
max_x=screen_coords_x.values.max

min_y=screen_coords_y.values.min
max_y=screen_coords_y.values.max

camera_dir=camera.direction
plane=[box.center,camera_dir]
pickray1=view.pickray(min_x,max_y)  #u=0,v=0
pickray2=view.pickray(max_x,max_y)  #u=1,v=0
pickray3=view.pickray(max_x,min_y)  #u=1,v=1
pickray4=view.pickray(min_x,min_y)  #u=0,v=1

pt1=Geom.intersect_line_plane(pickray1,plane)
pt2=Geom.intersect_line_plane(pickray2,plane)
pt3=Geom.intersect_line_plane(pickray3,plane)
pt4=Geom.intersect_line_plane(pickray4,plane)

uvs=[]
uv1=Geom::Point3d.new(0,0,1)
uv2=Geom::Point3d.new(1,0,1)
uv3=Geom::Point3d.new(1,1,1)
uv4=Geom::Point3d.new(0,1,0)

pt_array=[pt1,uv1,pt2,uv2,pt3,uv3,pt4,uv4]

ents=Sketchup.active_model.active_entities
group=ents.add_group
g_ents=group.entities
face=g_ents.add_face(pt1,pt2,pt3,pt4)
face.position_material(mat,pt_array,true)
tw=Sketchup.create_texture_writer
uv_help=face.get_UVHelper(true,true,tw)

faces.each {|f|
	material=f.material ? f.material : mat
	next if material==nil
	material=mat if material.texture==nil
	points=f.vertices.collect {|v| v.position}
	if f.normal.perpendicular?(camera_dir)
		#rotate the face points a very small amount and get the UVs for those points
		rot_vec=camera_dir.cross(f.normal)
		#get the point in the face that is closest to the camera eye (this will be used as the rotation point)
		eye=camera.eye
		dist_arr=points.collect {|p| p.distance(eye)}
		min_dist=dist_arr.min
		index=dist_arr.index(min_dist)
		rot_point=points[index]
		rot_trans=Geom::Transformation.rotation(rot_point,rot_vec,0.001)
		points=points.collect {|p| p.transform(rot_trans)}
	end
	front_uvs=points.collect {|p| uv_help.get_front_UVQ(p)}
	
	if points.length==3
		pt_array=[points[0],front_uvs[0],points[1],front_uvs[1],points[2],front_uvs[2]]
	else
		pt_array=[points[0],front_uvs[0],points[1],front_uvs[1],points[2],front_uvs[2],points[3],front_uvs[3]]
	end
	begin
		f.position_material(material,pt_array,true)
	rescue
		next
	end
}

ents.erase_entities([group])


UVtools.commit_operation
end


########
def get_verts(faces)

verts=Set.new
faces.each {|e|
	face_verts=e.vertices
	face_verts.each {|v| verts.insert(v)}
}

return verts.to_a

end
#########################
def spherical_map(faces)  #performs spherical mapping

faces=get_faces(faces)
if faces.empty?
	UI.messagebox("You must first select at least one face.")
	return
end
UVtools.start_operation("Spherical Map")
center=get_center(faces)
mat=get_uv_material()

view=Sketchup.active_model.active_view
camera=view.camera
up_axis=camera.up

verts=get_verts(faces)

x_axis=camera.xaxis
axis_line=[center,up_axis]
i=0
faces.each {|f|
	adjust=false
	uvs=[]
	pts=[]
	material=f.material ? f.material : mat
	material=mat if material.texture==nil
	verts=f.vertices
	#pts=verts.collect {|v| v.position}
	verts.each {|v|
		pt=v.position
		pts.push(pt)
		uv=get_spherical_uv2(pt,center,axis_line,x_axis)
		if verts.length==3
			#if uv[0]==0.0 and ((uv[1]>0.99) or (uv[1]<0.01))
			if ((uv[1]>0.99) or (uv[1]<0.01))
				adjust=true
				edges=v.edges
				common_edges=edges.find_all {|e| e.used_by?(f)}
				#p common_edges
				#common_edges.delete(nil)
				v2=common_edges[0].other_vertex(v)
				v3=common_edges[1].other_vertex(v)
				v2_uv=get_spherical_uv2(v2.position,center,axis_line,x_axis)
				v3_uv=get_spherical_uv2(v3.position,center,axis_line,x_axis)
				u_arr=[v2_uv.x,v3_uv.x]
				max=u_arr.max
				min=u_arr.min
				if (max-min).abs>0.8
					index=u_arr.index(min)
					u_arr[index]+=1.0
				end
				avg_u=(u_arr[0]+u_arr[1])/2.0
				uv[0]=avg_u
			end
		end
		uvs.push(uv)
	}
				
	#uvs=pts.collect {|p| get_spherical_uv(p,origin)}
	uvs=validate_uvs(uvs)    #fixes the 'overlap' problem
	#uvs=resize_uvs(uvs,material)  #resize the uvs based on texture size
	if pts.length==3
		pt_array=[pts[0],uvs[0],pts[1],uvs[1],pts[2],uvs[2]]
	else
		pt_array=[pts[0],uvs[0],pts[1],uvs[1],pts[2],uvs[2],pts[3],uvs[3]]
	end
	begin
		f.position_material(material,pt_array,true)
		#f.reverse! if adjust==true
		#f.position_material(material,pt_array,false)
	rescue
		p pt_array
		#raise
		next
	end
	
}

UVtools.commit_operation
end	

####
def cylindrical_map2(faces)  #performs spherical mapping

faces=get_faces(faces)
if faces.empty?
	UI.messagebox("You must first select at least one face.")
	return
end

UVtools.start_operation("Cylindrical Map")
mat=get_uv_material()
center=get_center(faces)
view=Sketchup.active_model.active_view
camera=view.camera
up_axis=camera.up
screen_coords_x=Hash.new
screen_coords_y=Hash.new
box=Geom::BoundingBox.new
verts=get_verts(faces)
verts.each {|v|
	coords=view.screen_coords(v.position)
	screen_coords_x[v]=coords.x
	screen_coords_y[v]=coords.y
	box.add(v.position)
}

min_y=screen_coords_y.values.min
max_y=screen_coords_y.values.max

z_extents=[max_y,min_y]
x_axis=camera.xaxis
axis_line=[center,up_axis]

faces.each {|f|
	material=f.material ? f.material : mat
	material=mat if material.texture==nil
	verts=f.vertices
	pts=verts.collect {|v| v.position}
	uvs=pts.collect {|p| get_cylindrical_uv2(p,z_extents,axis_line,x_axis)}
	uvs=validate_uvs(uvs)    #fixes the 'overlap' problem
	#uvs=resize_uvs(uvs,material)  #resize the uvs based on texture size
	if pts.length==3
		pt_array=[pts[0],uvs[0],pts[1],uvs[1],pts[2],uvs[2]]
	else
		pt_array=[pts[0],uvs[0],pts[1],uvs[1],pts[2],uvs[2],pts[3],uvs[3]]
	end
	begin
		f.position_material(material,pt_array,true)
		#f.position_material(material,pt_array,false)
	rescue
		p pt_array
		#raise
		next
	end
	
}

UVtools.commit_operation



end
#########################
def cylindrical_map(faces)  #performs spherical mapping

UVtools.start_operation("Cylindrical Map")
faces=get_faces(faces)
z_extents=get_zmax_min(faces)

faces.each {|f|
	material=f.material
	verts=f.vertices
	pts=verts.collect {|v| v.position}
	uvs=pts.collect {|p| get_cylindrical_uv(p,z_extents)}
	uvs=validate_uvs(uvs)    #fixes the 'overlap' problem
	#uvs=resize_uvs(uvs,material)  #resize the uvs based on texture size
	if pts.length==3
		pt_array=[pts[0],uvs[0],pts[1],uvs[1],pts[2],uvs[2]]
	else
		pt_array=[pts[0],uvs[0],pts[1],uvs[1],pts[2],uvs[2],pts[3],uvs[3]]
	end
	begin
		f.position_material(material,pt_array,true)
		#f.position_material(material,pt_array,false)
	rescue
		p pt_array
		raise
	end
	
}

UVtools.commit_operation
end	

############################
def get_faces(ents)

return ents.find_all {|e| e.class==Sketchup::Face}

end


######new in UVTools Pro
#collect the selected faces and export to OBJ
	def self.start_bridge()
	
	@@selected_faces=[]
	begin
		sel=Sketchup.active_model.selection
		sel_faces=self.get_faces(sel)
		@@selected_faces=sel_faces
		@materials=sel_faces.collect {|f| f.material}
		@materials.uniq!
		return if sel.length==nil
		if @materials.length>1
			UI.messagebox("Warning: Selected faces contain more than one material. Unexpected results may occur when importing UVs.")
		end
		if @materials.index(nil)!=nil
			UI.messagebox("You must assign a material to the all of selected faces prior to export.")
			return
		end
		textures=@materials.collect {|mat| mat.texture}
		textures.delete(nil)
		
		if textures.empty?
			UI.messagebox("Warning: Selected faces should have a textured material assigned for proper import/export of UVs.")
		end
		
		obj_path=self.get_obj_path
		
		return if obj_path==nil
			
		mtl_path=File.join(File.dirname(obj_path),"su_uv_export.mtl")
		
		self.export_mtl(mtl_path,@materials)
		self.export_obj_faces(obj_path,sel_faces)
		
	rescue
		UI.messagebox("Unable to export UVs.")
		raise
	end
	
	UI.messagebox("OBJ exported to #{obj_path}.  Open this file with an external UV mapping aplication and then save it using the same path and filename when you have finished UV mapping.  Then, use the import command.")
	
	end
	
	#################
	def self.return_bridge()
	
	begin
		#sel=Sketchup.active_model.selection
		#sel_faces=self.get_faces(sel)
		sel_faces=@@selected_faces
		return if sel_faces.length==nil
		
		obj_path=self.get_obj_path
		num_failed=self.obj_uv_imp(sel_faces,obj_path)
	rescue
		UI.messagebox("Unable to import UVs from OBJ.")
		raise
	end
	UI.messagebox("UV import successful. #{num_failed} faces failed.")
	
	end

	######################
	def self.export_obj_faces(path,faces)
	
	@face_mesh=self.build_mesh(faces)
	@tw=Sketchup.create_texture_writer
	@v_index=0
	@uv_index=0
	@f_index=0
	out=File.new(path,"w")
	out.puts "# Alias OBJ Model file"
	out.puts "# Exported using Whaat's UV Tools"
	out.puts ""
	out.puts "mtllib su_uv_export.mtl"
	out.puts ""
	out.puts "g selected_faces"
	out.puts ""
	out.puts "vn 0 0 1"
	#self.export_vert_normals(out)
	self.export_verts(out)
	faces.each {|f|
		self.export_face(out,f)
	}
	
	out.close
	@tw=nil
	
	end
	
	####create mtl file
	def self.export_mtl(path,materials)
	
	#p path
	obj_path=self.get_obj_path
	out=File.new(path,"w")
	out.puts "#"
	out.puts "# Alias OBJ Material File"
	out.puts "# Exported using Whaat's UV Tools"
	out.puts ""
	@materials.each {|mat|
		if mat!=nil
			color=mat.color
			r=color.red.to_f/255.0
			g=color.green.to_f/255.0
			b=color.blue.to_f/255.0
			out.puts "newmtl #{mat.display_name}"
			out.puts "Ka 0.000000 0.000000 0.000000"
			out.puts "Kd #{r} #{g} #{b}"
			out.puts "Ks 0.330000 0.330000 0.330000"
			if mat.texture!=nil
				f_name=File.basename(mat.texture.filename)
				tex_path=File.join(File.dirname(obj_path),f_name)
				self.save_mat_texture(mat,tex_path)
				out.puts "map_Kd #{f_name}"
			end
		else
			r=0.8
			g=0.8
			b=0.8
			out.puts "newmtl Default"
			out.puts "Ka 0.000000 0.000000 0.000000"
			out.puts "Kd #{r} #{g} #{b}"
			out.puts "Ks 0.330000 0.330000 0.330000"
		end
	}
	out.close()
	
	end
	
	
	#export all the vertices in the face mesh
	def self.export_verts(out)
	
	scale=1.0
	pt=Geom::Point3d.new(0,0,0)
	vec=Geom::Vector3d.new(1,0,0)
	angle=-90.0.degrees
	
	obj_trans=Geom::Transformation.rotation(pt,vec,angle)
	pts=@face_mesh.points
	pts=pts.collect {|p| p.transform(obj_trans)}  #rotate all points by 90 degrees
	pts.each {|p|
		out.puts "v #{p.x.to_f*scale} #{p.y.to_f*scale} #{p.z.to_f}"
	}
	
	end
		
	#acquire all faces in an array of entities
	def self.get_faces(ents)
	
	faces=[]
	faces=ents.find_all {|e| e.class==Sketchup::Face}
	return faces
	
	end
	
	#create a mesh
	def self.build_mesh(faces)
	
	mesh=Geom::PolygonMesh.new
	for f in faces
		verts=f.outer_loop.vertices
		verts.each {|v|
			mesh.add_point(v.position)
		}
	end
	
	return mesh

	end
	
	#export vertices, uvs, and face
	def self.export_face(out,f)
	if f.material==nil
		mat_name="Default"
	else
		mat_name=f.material.display_name
	end
	
	out.puts "usemtl #{mat_name}"
	mesh=f.mesh 5
	verts=f.outer_loop.vertices
	#v_indices=verts.collect {|v| @face_mesh.point_index(v.position)}
	uvh=f.get_UVHelper(true,false,@tw)
	face=["f"]  #array will hold the indices of the vertices and uvs
	#face=[]
	verts.each {|v|
		pos=v.position
		uv=uvh.get_front_UVQ(pos)
		uvz=uv.z.to_f
		#out.puts "v #{pos.x.to_f} #{pos.y.to_f} #{pos.z.to_f}"
		#@v_index+=1
		#out.puts "vt #{uv.x.to_f} #{uv.y.to_f}"
		out.puts "vt #{(uv.x.to_f)/uvz} #{(uv.y.to_f)/uvz}"
		@uv_index+=1
		face.push("#{@face_mesh.point_index(pos)}\/#{@uv_index}\/1")
		#face.push("#{@face_mesh.point_index(pos)}\/#{@uv_index}")
	}
	#face.push("f")
	#face.reverse!
	out.puts face.join(" ")
	@f_index+=1
	out.puts ""
	
	end
	#export vertices, uvs, and face
	def self.export_face_void(out,f)
	
	mesh=f.mesh 5
	verts=f.outer_loop.vertices
	uvh=f.get_UVHelper(true,false,@tw)
	face=["f"]  #array will hold the indices of the vertices and uvs
	verts.each {|v|
		pos=v.position
		uv=uvh.get_front_UVQ(pos)
		out.puts "v #{pos.x.to_f} #{pos.y.to_f} #{pos.z.to_f}"
		@v_index+=1
		out.puts "vt #{uv.x.to_f} #{uv.y.to_f}"
		@uv_index+=1
		face.push("#{@v_index}\/#{@uv_index}\/1")
	}
	
	out.puts face.join(" ")
	@f_index+=1
	out.puts ""
	
	end
		
		
   def self.obj_uv_imp(faces,obj_path)
   version=Sketchup.version
	UVtools.start_operation("Import OBJ uvs")
    	 failed=0
	@current_mat=nil
      @groups = {}
      @vertices = []
	   @uvs=[]
      @normals = []
      @faces = []
	  @mats=[]
	  face_index=0
      errors = Hash.new(0)
      face_verts = Hash.new(0)

      #f = UI.openpanel "Select .obj file", "", "*.obj"
      #return unless f
	  
	 f=obj_path
	  #f="C:\\Users\\Dale\\Desktop\\OBJ\\uv_bridge_out.obj"
	  obj_dir=File.dirname(f)
      line_cnt = g_cnt = 0
	  lines = IO.readlines(f)
	  num_lines=lines.length
	  t=Time.now
		last_update=Time.now
		
      lines.each do |line|
	 line_cnt += 1
	 t=Time.now
	 if (t-last_update)>0.5
		 Sketchup.set_status_text("Processed #{line_cnt} of #{num_lines} lines")
		last_update=Time.now
	end
	
	 next if line[0] == ?#
	    line.strip!
	 values = line.split
	 next if values.length == 0
	 cmd = values.shift

	 case cmd
	 when "mtllib"
		#mtl_path=File.join(obj_dir,values[0])
		#@mats=self.mtl_imp(mtl_path)  #import all the materials in the MTL file
	 when "usemtl"
		#mat_name=values[0]
		#@current_mat=@mats.find {|mat| mat.name==mat_name}  
	 when "v"
	   #v = values.map { |e| Float(e) * scale }
	    #@vertices << v
	   #mesh.add_point v if use_mesh
	when "vt"
		uvw=values.map{ |e| e.to_f }
		@uvs.push(uvw)

	 when "g"
	    #
	 when "f"
	    face = []
		face_index+=1
		face_uvs=[]
	    values.each do |v|
	       w = v.split("/")
	       face << Integer(w[0])
		    face_uvs.push(w[1].to_i)
	    end
	    #verts = face.map { |v| @vertices[v-1] }
		face_uvs=face_uvs.collect {|index| @uvs[index-1]}
	    #face_verts[verts.length] += 1
	    @faces << face
	   
	   begin
	      		current_face=faces[face_index-1]
				verts=current_face.outer_loop.vertices.collect {|v| v.position}
				#verts.reverse!
				l = verts.length
				current_mat=current_face.material
				if current_mat!=nil
					pt_array=[]
					pt_array=[verts[0],face_uvs[0],verts[1],face_uvs[1],verts[2],face_uvs[2]] if l==3
					pt_array=[verts[0],face_uvs[0],verts[1],face_uvs[1],verts[2],face_uvs[2],verts[3],face_uvs[3]] if l>3
					current_face.position_material(current_mat,pt_array,true)
				end
	       
	    rescue
	      #p "failed"
		  failed+=1
	    end
	 end
      end # case
	Sketchup.set_status_text(nil)
	   UVtools.commit_operation
	   return failed
   end
  
########################  
def self.save_mat_texture(mat,path)
  
UVtools.start_operation("Save Texture")
tw=Sketchup.create_texture_writer
entities = Sketchup.active_model.active_entities
helper_group=entities.add_group
if (mat.respond_to?(:texture) and mat.texture !=nil)
	helper_group.material=mat
	tw.load(helper_group)
	status = tw.write(helper_group, path)
end	

#entities.erase_entities helper_group
Sketchup.active_model.abort_operation
tw=nil
if status==0   #write successful so apply the image to the dialog
	return path
else
	return nil
end

end  

###get the default path to write the OBJ to
def self.get_obj_path

path=Sketchup.read_default("UVTools","objPath",nil)
if path==nil
	path=self.set_obj_path()
end
return path

obj_name="su_uv_bridge.obj"
on_mac=((Object::RUBY_PLATFORM =~ /mswin/i)||(Object::RUBY_PLATFORM =~ /mingw/i)) ? false : ((Object::RUBY_PLATFORM =~ /darwin/i) ? true : :other)

if on_mac
	path=File.join(ENV['HOME'],"Library","Application Support","UVTools")
else
	path=File.join(ENV['APPDATA'])
	if path.respond_to?(:force_encoding)
		path=path.dup.force_encoding('UTF-8')
	end
	path=File.join(path,"UVTools")
end

Dir.mkdir(path) unless FileTest.exist?(path)

return File.join(path,obj_name)

end
####
def self.set_obj_path()

result=UI.savepanel("Set OBJ Export Path","","")
return nil if not result
export_path=File.join(File.dirname(result),File.basename(result,".*")+".obj")
export_path.gsub!(/\\/,"\/")
Sketchup.write_default("UVTools","objPath",export_path)
return export_path

end

end
#class
########
class DM_PathSelectTool

def initialize

@state0_status_text="Click an edge to add to the path selection.  Press Enter or Return to harden selected edges."
@model=Sketchup.active_model
@ph=@model.active_view.pick_helper
@chain=Chain.new
@sel=@model.selection
@sel.clear
@last_click_time=Time.now
plugins=PATH
icon = File.join(plugins,"path_select.png")
@icon=UI.create_cursor(icon,7,4)

end


def activate
    self.reset(nil)
end

def deactivate(view)
   view.invalidate
end

###
def onSetCursor

UI.set_cursor(@icon)

end
###
def onReturn(view)

@sel.add(@chain.edges) unless @chain.length==0
edges=@sel.find_all {|e| e.class==Sketchup::Edge}
UVtools.start_operation("Harden Edges")
edges.each {|edge| edge.soft=false;edge.smooth=false}
UVtools.commit_operation

self.reset(view)

end
###
def weld(pts)

ents=Sketchup.active_model.active_entities
t_group=ents.add_group
g_ents=t_group.entities
g_ents.add_curve(pts)
t_group.explode


end
####
def onMouseMove(flags, x, y, view)
	
	@ph.do_pick(x,y)
	best=@ph.best_picked
	if best.class==Sketchup::Edge
		@hover_edge=best
	end
	return if @hover_edge==nil
	unless @hover_edge.parent.entities==@model.active_entities
		@hover_edge=nil
	end
	view.invalidate if @hover_edge
	
end

###
def onLButtonDown(flags, x, y, view)
	
	#first check that user is hovering over an edge
	if @hover_edge!=nil
		@picked_edge=@hover_edge
				
		#if nothing has been added to the chain
		if @chain.length==0
			@chain.add(@picked_edge)
			@sel.add(@picked_edge)
		else
			path=@chain.get_path(@picked_edge)
			
			if path
				@chain.add(@picked_edge)
				path[1].each {|e| @sel.add(e)}
				@sel.add(@chain.edges)
			end
		end
	end
	view.invalidate
end

####
 def onLButtonDoubleClick(flags, x, y, view)

#p "double_click"
if @picked_edge.class==Sketchup::Edge
	@sel.clear
	@chain.clear
	@chain.add_smartpath(@picked_edge)
	@chain.edges.each {|e| @sel.add(e)}
	view.invalidate
	@sel.add(@chain.edges)
	self.reset(view)
end

end
###
def resume(view)

view.invalidate

end

def draw(view)


if @hover_edge and @hover_edge.valid?
	view.drawing_color="orange"
	view.line_width=6
	verts=@hover_edge.vertices
	view.draw_line(verts[0].position,verts[1].position)
	if @chain.length>0
		path=@chain.get_path(@hover_edge)
		if path
			view.drawing_color="green"
			path_edges=path[1]
			path_edges.each {|e| view.draw_line(e.start.position,e.end.position)}
		end
	end
end

if @chain.length>0
	view.drawing_color="blue"
	edges=@chain.edges
	edges.each {|e| view.draw_line(e.start.position,e.end.position)} if edges
end
		


end
###
def onCancel(flag, view)
    self.reset(view)
end
###
def reset(view)

    @chain=Chain.new
    # Display a prompt on the status bar
    Sketchup::set_status_text(@state0_status_text, SB_PROMPT)
 
    if( view )
        view.invalidate if @drawn
    end
    
end

end #class


#####
class Chain

def initialize

@ents=nil
@chain_vertices=[]

end

###
def validate()

p @chain_vertices
@chain_vertices.delete_if {|v| !v.valid?}
edges=self.edges()
if edges
	
	vert_length=(edges.length)+1
	@chain_vertices=@chain_vertices[0..vert_length]
else
	self.clear
end

end
#
def loop?

if @chain_vertices.length>2
	if @chain_vertices.last.common_edge(@chain_vertices.first)
		return true
	end
end
return false

end
###
def clear

@chain_vertices=[]

end
##
def edges()

chain_edges=[]
return nil if @chain_vertices.length<2
@chain_vertices.delete_if {|v| !v.valid?}
(self.length-1).times {|i|
	chain_edges.push(@chain_vertices[i].common_edge(@chain_vertices[i+1]))
}
nil_index=chain_edges.index(nil)
if nil_index
	chain_edges=chain_edges[0..(nil_index-1)]
	@chain_vertices=@chain_vertices[0..nil_index]
end
if nil_index==0
	chain_edges=nil
	self.clear
end

return chain_edges

end
##
def add(edge) 

if @chain_vertices.empty?
	@chain_vertices.concat(edge.vertices)
	return
end

s_edge=self.start_edge

if self.length==2 #special case where we don't know the direction of the chain yet
	current_vert=nil
else
	current_vert=self.end_vert
end

path=self.find_path(s_edge,edge,@chain_vertices,current_vert)
if path
	new_verts=path[0]
	#check if we have to swap the first two vertices based on the path that was found
	if self.length==2
		unless new_verts[0].common_edge(@chain_vertices[1])
			temp=@chain_vertices[0]
			@chain_vertices[0]=@chain_vertices[1]
			@chain_vertices[1]=temp
		end
	end
	@chain_vertices.concat(path[0])
	
end

end

###
def length

return @chain_vertices.length
	
end
###
def start_vert

if @chain_vertices.length>0
	return @chain_vertices[0]
end

end

###
def end_vert

if @chain_vertices.length>0
	return @chain_vertices[-1]
end

end
####
def end_edge

if @chain_vertices.length>=2
	return @chain_vertices[-1].common_edge(@chain_vertices[-2])
else
	return nil
end

end
#####
def start_edge

if @chain_vertices.length>=2
	return @chain_vertices[0].common_edge(@chain_vertices[1])
else
	return nil
end

end

def get_path(edge)

return nil if self.start_edge==nil
if self.length==2 #special case where we don't know the direction of the chain yet
	current_vert=nil
else
	current_vert=self.end_vert
end
path=find_path(self.start_edge,edge,@chain_vertices,current_vert)
return path

end
###
def add_smartpath(edge)

#we must have an empty chain to use this function
unless @chain_vertices.empty?
	return
end

s_edge=edge
@chain_vertices.push(s_edge.start)
@chain_vertices.push(s_edge.end)


path=self.find_smartpath(s_edge,[s_edge.end],s_edge.end)

if path
	new_verts=path[0]
	#check if we have to swap the first two vertices based on the path that was found
	#if self.length==2
	#	unless new_verts[0].common_edge(@chain_vertices[1])
	#		temp=@chain_vertices[0]
	#		@chain_vertices[0]=@chain_vertices[1]
	#		@chain_vertices[1]=temp
	#	end
	#end
	@chain_vertices.concat(new_verts)
end


#if we haven't found a closed loop, try to find a path in the other direction as well
unless self.loop?

	path2=self.find_smartpath(s_edge,@chain_vertices,s_edge.start)

	if path2
		#p path2
		new_verts=path2[0]
		if self.length>2 #occurs if path was added above
			new_verts.reverse!
			@chain_vertices=new_verts+@chain_vertices
		elsif self.length==2 #no path was added above so swap the first two vertices so
			#unless new_verts[0].common_edge(@chain_vertices[0])
				temp=@chain_vertices[0]
				@chain_vertices[0]=@chain_vertices[1]
				@chain_vertices[1]=temp
			#end
			@chain_vertices.concat(new_verts)
		end
	end
end #unless

end
###returns the path edges between the start and end edges
def find_smartpath(s_edge,avoid_vertices=[],current_vert=nil)

avoid=avoid_vertices.dup
path_verts=[]
path_edges=[]

middle_edges=[]  #the edges that are between the current end of the chain and the new edge
middle_vertices=[]  #the vertices that are between the start and end edges

#find the vertex on the start edge that is closest to the midpoint of the end edge
if current_vert==nil
	current_vert=s_edge.end
end

s_vec=current_vert.position-(s_edge.other_vertex(current_vert)).position  #the vector of the start edge

next_vert=nil
next_edge=nil
target_vec=s_vec
count=0
plane=nil

#now crawl along the vertices to find the path
while (current_vert!=nil)
	plane=nil
	current_edges=current_vert.edges
	current_edges.delete_if {|e| avoid.include?(e.other_vertex(current_vert))}
	pts=path_verts.collect {|v| v.position}
	if plane
		plane=Geom.fit_plane_to_points([s_edge.start.position,s_edge.end.position]+pts)
	end
	angle=(Math::PI/2.01)
	prod=1000000.0
	next_vert=nil
	next_edge=nil
	current_edges.each {|e|
		edge_vec=e.other_vertex(current_vert).position-current_vert.position
		target_angle=edge_vec.angle_between(target_vec)
		dist_to_plane=1.0
		dist_to_plane=(e.other_vertex(current_vert).position.distance_to_plane(plane)) if plane!=nil
		target_prod=target_angle*dist_to_plane
		#target_prod=target_angle
		#target_prod=dist_to_plane if plane
		#target_prod=target_angle unless plane
		#p target_angle
		if target_prod<prod
			angle=target_angle
			prod=target_prod
			next_vert=e.other_vertex(current_vert)
			next_edge=e
		end
	}
	if next_vert
		#p next_vert
		next_vert=nil if next_vert==current_vert  #no path was found
		next_vert=nil if (angle>=(Math::PI/2.01))  #stop at 90 degree angle
	end
	if next_vert
		avoid.push(current_vert)
		path_verts.push(next_vert)
		target_vec=next_vert.position-current_vert.position
		middle_edges.push(next_edge)
		next_vert=nil if next_vert.used_by?(s_edge)  #we found a closed loop so exit the loop
	end
	current_vert=next_vert
	
	count+=1
	break if count==500

end #while

if path_verts.length>0 #i.e. we found a path using the above loop
	return [path_verts,middle_edges]
else
	return nil
end

end

###returns the path edges between the start and end edges
def find_path(s_edge,e_edge,avoid_vertices=[],current_vert=nil)

avoid=avoid_vertices.dup
path_verts=[]
path_edges=[]
#if @vertices.length==0
#	@vertices.push(edge.start)
#	@vertices.push(edge.end)
#	@chain_edges.push(edge)
#	return [edge]
#end


middle_edges=[]  #the edges that are between the current end of the chain and the new edge
middle_vertices=[]  #the vertices that are between the start and end edges

return nil if s_edge.parent.entities!=e_edge.parent.entities
return nil unless s_edge.all_connected.include?(e_edge)

s_vec=s_edge.end.position-s_edge.start.position  #the vector of the 
e_edge_midpoint=Geom.linear_combination(0.5,e_edge.start.position, 0.5, e_edge.end.position)

#find the vertex on the start edge that is closest to the midpoint of the end edge
if current_vert==nil
	distance_to_verts=[(e_edge_midpoint-s_edge.start.position).length,(e_edge_midpoint-s_edge.end.position).length]
	min_dist=distance_to_verts.min
	if distance_to_verts.index(min_dist)==0
		current_vert=s_edge.start
	else
		current_vert=s_edge.end
	end
end

#find the vertex on the end edge that is closet to the start 
distance_to_verts=[(current_vert.position-e_edge.start.position).length,(current_vert.position-e_edge.end.position).length]
min_dist=distance_to_verts.min
if distance_to_verts.index(min_dist)==0
	target_vert=e_edge.start
else
	target_vert=e_edge.end
end

next_vert=nil
next_edge=nil
target_vec=target_vert.position-current_vert.position
count=0

#now crawl along the vertices to find the path to the target vert
while ((current_vert!=nil) and (current_vert!=target_vert))
	current_edges=current_vert.edges
	current_edges.delete_if {|e| avoid.include?(e.other_vertex(current_vert))}
	angle=Math::PI
	current_edges.each {|e|
		edge_vec=e.other_vertex(current_vert).position-current_vert.position
		target_angle=edge_vec.angle_between(target_vec)
		#p target_angle
		if target_angle<=angle
			angle=target_angle
			next_vert=e.other_vertex(current_vert)
			next_edge=e
		end
	}
	#p angle
	#p next_vert
	if next_vert
		next_vert=nil if next_vert==current_vert  #no path was found
	end
	if next_vert
		avoid.push(next_vert)
		path_verts.push(next_vert)
		current_vert=next_vert
		target_vec=target_vert.position-current_vert.position
		middle_edges.push(next_edge)
		#current_vert=nil if current_vert==target_vert
	end
	
	count+=1
	break if count==100

end #while

if current_vert==target_vert #i.e. we found a path using the above loop
	path_verts.push(e_edge.other_vertex(target_vert))
	return [path_verts,middle_edges]
else
	#p "return nil"
	return nil
end

end

####
def start

return @vertices[0]

end
###
def end

return @vertices.last

end

###
def end_edge

return nil unless @vertices.length>1
return @vertices.last.common_edge(@vertices[-2])

end

###
def points

return @chain_vertices.collect {|v| v.position}

end

end #class



plugins=PATH
icon1=File.join(plugins,"uv_icon.png")
icon1b=File.join(plugins,"uv_icon16.png")
icon2=File.join(plugins,"path_select_tb.png")
icon2b=File.join(plugins,"path_select_tb16.png")

tb = UI::Toolbar.new("SketchUV")
cmd1 = UI::Command.new("SketchUV"){(Sketchup.active_model.select_tool(DM_UVTool.new))}
cmd1.small_icon = icon1b
cmd1.large_icon = icon1
cmd1.tooltip = cmd1.status_bar_text = "SketchUV Mapping Tools"

cmd2 = UI::Command.new("Path Select Tool"){Sketchup.active_model.select_tool(DM_PathSelectTool.new)}
cmd2.small_icon = icon2b
cmd2.large_icon = icon2
cmd2.tooltip = cmd2.status_bar_text = "Path Select Tool"

tb.add_item(cmd1)
tb.add_item(cmd2)
tb.show

menu = UI.menu("Plugins").add_submenu("SketchUV")
menu.add_item(cmd1)
#menu.add_item("Triangulate")  { DM_UVTool.new.triangulate() }
menu.add_item(cmd2)
#menu.add_item("Export UVs to OBJ")  { UVtools.start_bridge()}
#menu.add_item("Import UVs from OBJ") { UVtools.return_bridge() }
menu.add_item("Set UV OBJ Path") {UVtools.set_obj_path() }

end #module SketchUV
end #module DM