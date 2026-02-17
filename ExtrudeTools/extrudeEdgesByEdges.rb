=begin
  Copyright 2014-2017 (c), TIG
     All Rights Reserved.
  THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED 
  WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF 
  MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
###
     extrudeEdgesByEdges.rb 
###
     Extrudes two sets of grouped edges into a faced mesh...
###
Usage:  Make two sets of edges [from lines, arcs, curves etc].
        These represent the 'profile' and the 'path' for the mesh.
        Make a group of each set.
        Note: If the groups share a common vertex then that fixes the 
        new mesh's location, otherwise the nearest vertices are used, 
        with the new mesh located near the profile, Move it as required...
        Now Select these 2 groups.
        Run the Plugin: 'Extrude Edges by Edges'.
        It makes a grouped faced 'mesh' from these two edge-sets.
        The progress at each stage is reported along the status bar.
        When the mesh is made the view zooms to include the original 
        profile/path groups and the new mesh group.
        Then there are dialogs asking for Yes/No replies...
         If you want to 'orientate' the mesh-faces (which may not always 
        be necessary: if it's chosen then it will be done as well as 
        possible for any convoluted shapes.  
         If you want to 'reverse' the mesh-faces.  
         If you want the mesh-faces to 'intersect' with themselves 
        (This is only necessary if the mesh has convoluted re-entrant 
        surfaces).  Intersecting the mesh might compromise some later 
        triangulation...
         If you want to remove any 'coplanar edges'.  
         If you want to 'triangulate' the new faces:
        on very complex inter-penetrating meshes a triangulating error 
        message might appear - answer 'Yes' to undo triangulation, 
        'No' to keep what's been done so far...  
        Note that the triangulation 'undo' is separate within the main 
        action's 'undo'.
         Finally, if you want to delete the original two groups.
        Note:
        Large numbers of edges in the groups increase the new faces and 
        other operations exponentially, therefore only extrude the parts 
        that can be copied/exploded together later...  
        For example: 
        2 edges x 2 edges >>> group with 4 faces & 12 edges
        4 edges x 4 edges >>> group with 16 faces & 40 edges
        8 edges x 8 edges >>> group with 64 faces & 144 edges
        16 edges x 16 edges >>> group with 256 faces & 544 edges
        32 edges x 32 edges >>> group with 1024 faces & 2112 edges
        ...
        Very large groups will eventually be made but the screen can 
        'white out' and the 'counter' might appear to stop changing for 
        several minutes...  It is working.
        Use 'Smooth' and/or 'Show Hidden Geometry' on the mesh-group, 
        also 'Sandbox flip-edge' tool to re-trianglate, as desired...
        Rarely some combinations of edge groups might go into a 'loop' 
        and then SUp needs 'killing' - so save first !
        
Donations:
   Are welcome [by PayPal], please use 'TIGdonations.htm' in the 
   ../Plugins/TIGtools/ folder.
   
Version:
        1.0 20090622 First 'beta' release.
        1.1 20090625 Speed improvements - face making time ~halved, 
                     typename >> kind_of?, triangulation glitch trapped 
                     and orientation improved.
        1.2 20090625 Orientation speed optimised.
                     Glitch on groups erase fixed.
        1.3 20090626 Edges not facing in convoluted shapes trapped.
        1.4 20090707 Triangulation improved. Rare intersect glitch fixed.
        1.5 20090708 Zooms to show new group.
        1.6 20090708 Zooms to new group fixed for large models.
        1.7 20090709 Coplanar edge erasure errors trapped: 
                     0.999999 made 0.99999999 !!!
        1.8 20090808 Orienting and Triangulation speeds improved.
        x2.0 20100114 Debabelized, 'Extrusion Tools' Toolbar added.
        x2.1 20100120 Typo fixed so lingvo file works !
        x2.2 20100120 Lingvo files updated.  Thanks FR=Pilou, ES=Defisto
        x2.3 20100121 Typo preventing Plugin Menu item working corrected.
        x2.4 20100123 FR lingvo file updated by Pilou.
        x2.5 20100124 Menu typo glitch fixed.
        x2.6 20100215 Made into tool/class
        x2.7 20100216 All extrusion-tools now in one in Plugins sub-menu.
        x2.8 20100222 Tooltips etc now deBabelized properly.
        x2.9 20100428 Tool now exits gracefully.
        x3.0 20100517 ES lingvo adjusted by Defisto.
		x3.1 20111207 Group.copy replaced to avoid rogue script clashes.
		2.0 20130520 Becomes part of ExtrudeTools Extension.
=end

module ExtrudeTools
###
toolname="extrudeEdgesByEdges"
cmd=UI::Command.new(db("Extrude Edges by Edges")){Sketchup.active_model.select_tool(ExtrudeTools::ExtrudeEdgesByEdges.new())}
cmd.tooltip=db("Extrude Edges by Edges")
cmd.status_bar_text="..."
cmd.small_icon=File.join(EXTOOLS, "#{toolname}16x16.png")
cmd.large_icon=File.join(EXTOOLS, "#{toolname}24x24.png")
SUBMENU.add_item(cmd)
TOOLBAR.add_item(cmd)
###
class ExtrudeEdgesByEdges

include ExtrudeTools
###
 def triangulateEEE(thefaces,gents)###v1.8 ### based on ideas by CPhillips
   count=1
   thefaces.each{|face|
    Sketchup::set_status_text(((db("Triangulating Face "))+count.to_s+(db(" of "))+thefaces.length.to_s),SB_PROMPT)
    count+=1
    mesh=face.mesh(1)
    faces=mesh.polygons
    verts=mesh.points
    outmesh = Geom::PolygonMesh.new
    faces.each{|f|
      outmesh.add_polygon(verts[f[0].abs-1],verts[f[1].abs-1],verts[f[2].abs-1])
    }
    face.erase!
    grp=gents.add_group
    grp.entities.add_faces_from_mesh(outmesh)
    grp.entities.each{|e|
      if e.class==Sketchup::Edge
        e.soft=false
        e.smooth=false
      end#if
    }
    grp.explode
   }
 end#def triangulateEEE
###
class Sketchup::Face
 def orient_connected_faces ###v1.8
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
	      Sketchup::set_status_text(msg,SB_PROMPT)
		  @face=face
          face_flip
        end#if
	  }
    end#while
	Sketchup::set_status_text((""),SB_PROMPT)
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
end#class face

def initialize()
	###
	@toolname="extrudeEdgesByEdges"
	###
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
########### main code >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
  GC.start ### ### ###
	@model=Sketchup.active_model
  model=Sketchup.active_model
  if Sketchup.version.to_i > 6
		model.start_operation((db("Extrude Edges by Edges")), true)
    ### 'false' is best to see results as UI/msgboxes...
  else
		model.start_operation((db("Extrude Edges by Edges")))
  end  
  ents=model.active_entities
  ss=model.selection
  if ss[2] or not ss[1] or not ss[0]
    UI.messagebox(db("Select 2 Groups of Edges !  1st is 'profile' and 2nd 'path'."))
    return nil
  end#if
  if not ss[0].kind_of?(Sketchup::Group) or not ss[1].kind_of?(Sketchup::Group)
    UI.messagebox(db("Select 2 Groups of Edges !  1st is 'profile' and 2nd 'path'."))
    return nil
  end#if
  ### set groups
  gp0o=ss[0];gp1o=ss[1] ### profile + path
  ### we have 2 groups
  got_edges0=false;gp0o.entities.each{|e|got_edges0=true if e.kind_of?(Sketchup::Edge)}
  got_edges1=false;gp1o.entities.each{|e|got_edges1=true if e.kind_of?(Sketchup::Edge)}
  if not got_edges0 or not got_edges1
    UI.messagebox(db("The Groups Must Contain Edges !  1st is 'profile' and 2nd 'path'."))
    return nil
  end#if
  ### we have edges
  Sketchup::set_status_text((db("Multiplying Edges...")),SB_PROMPT)
  group=ents.add_group();gents=group.entities
  group0=gents.add_group()
  gents0=group0.entities
  group1=gents.add_group()
  gents1=group1.entities
  def0=gp0o.entities.parent
  def1=gp1o.entities.parent
  #gp0x=gp0o.copy
  #gp1x=gp1o.copy
  #gp0xx=ents.add_group(gp0x)
  #gp1xx=ents.add_group(gp1x)
  gp0xx=ents.add_group()
  gp0xx.entities.add_instance(def0, gp0o.transformation)
  gp1xx=ents.add_group()
  gp1xx.entities.add_instance(def1, gp1o.transformation)
  ###
  gx0=gp0xx.entities[0];gx0.explode if gx0.valid?
  gx1=gp1xx.entities[0];gx1.explode if gx1.valid?
  edges0=[];gp0xx.entities.each{|e|edges0.push(e)if e.valid? and e.kind_of?(Sketchup::Edge)}
  points0=[];edges0.each{|e|points0.push(e.start.position);points0.push(e.end.position)}
  points0.uniq!
  gents0.each{|e|e.erase! if e.valid? and not e.kind_of?(Sketchup::Edge)}
  edges0.each{|e|gents0.add_line(e.start.position,e.end.position)}
  edges1=[];gp1xx.entities.each{|e|edges1.push(e)if e.valid? and e.kind_of?(Sketchup::Edge)}
  points1=[];edges1.each{|e|points1.push(e.start.position);points1.push(e.end.position)}
  points1.uniq!
  gents1.each{|e|e.erase! if e.valid? and not e.kind_of?(Sketchup::Edge)}
  edges1.each{|e|gents1.add_line(e.start.position,e.end.position)}
  group0=gents[0]
  group1=gents[1]
  group0.move!(gp0xx.transformation)
  group1.move!(gp1xx.transformation)
  gp0xx.erase! if gp0xx.valid?
  gp1xx.erase! if gp1xx.valid?
  GC.start ### ### ###
  gps0=[]###v1.1
  points0.each{|point|
		t1=ORIGIN-group1.transformation.origin
		t2=Geom::Transformation.new(point)
		#gp0=group1.copy
		defg1=group1.entities.parent
		gp0=group1.parent.entities.add_instance(defg1, group1.transformation)
        gps0 << gp0 ###v1.1
		gp0.transform!(t1)
		gp0.transform!(t2)
  }
  gps1=[]###v1.1
  points1.each{|point|
		t1=ORIGIN-group0.transformation.origin
		t2=Geom::Transformation.new(point)
		#gp1=group0.copy
		defg0=group0.entities.parent
		gp1=group0.parent.entities.add_instance(defg0, group0.transformation)
        gps1 << gp1 ###v1.1
		gp1.transform!(t1)
		gp1.transform!(t2)
  }
  group.move!(group0.transformation)
  group.move!(group1.transformation)
  Sketchup::set_status_text((db("Intersecting...")),SB_PROMPT)
  group0.erase! if group0.valid? ; group1.erase! if group1.valid?
  GC.start ### ### ###
  ###v.1===
  counter=1; num=gps0.length
  gps0.each{|e|
    Sketchup::set_status_text(((db("Checking: Step "))+counter.to_s+(db(" of "))+num.to_s),SB_PROMPT)
    e.explode if e.valid?
    counter+=1
  }
  GC.start ### ### ###
  edges=[];gents.each{|e|edges.push(e)if e.kind_of?(Sketchup::Edge)}
  counter=1; num=gps1.length
  gps1.each{|e|
    Sketchup::set_status_text(((db("Making Edges: Step "))+counter.to_s+(db(" of "))+num.to_s),SB_PROMPT)
    e.explode if e.valid?
    counter+=1
  }
  GC.start ### ### ###
  counter=1; num=edges.length ### all profile edges used***
  edges.each{|e|Sketchup::set_status_text(((db("Facing Edges: Step "))+counter.to_s+(db(" of "))+num.to_s),SB_PROMPT)
    e.find_faces if e.valid?
    counter+=1
  }
  faces=[];gents.each{|e|faces.push(e)if e.kind_of?(Sketchup::Face)}
  ###
  if not faces[0]
    UI.messagebox(db("No Faces Made !"))
    group.erase!
    return nil
  end#if
  edges=[];gents.each{|e|edges.push(e)if e.kind_of?(Sketchup::Edge)and e.faces.length<=1}###v1.3
  edges.each{|e|e.find_faces if e.valid?}
  gents.each{|e|e.erase! if e.valid? and e.kind_of?(Sketchup::Edge)and e.faces.length==0}###v1.4
  ### ***ensures any one faced edges are faced OK
  ###===v1.1
  ss.clear ###v1.6
  ss.add(group) ### zoom to include group v1.5
  Sketchup.send_action("viewZoomToSelection:")
  ###
  ### orient
  Sketchup::set_status_text((db("Orient Faces ?")),SB_PROMPT)
  faces=[];gents.each{|e|faces.push(e)if e.kind_of?(Sketchup::Face)}
  if UI.messagebox((db("Orient Faces ?"))+"\n\n\n\n",MB_YESNO,"")==6 ### 6=YES 7=NO
   while faces[0]
    face=faces[0]
    face.reverse! if face.normal.z<=0###v1.2
    face.orient_connected_faces
    connected=[];face.all_connected.each{|e|connected.push(e)if e.kind_of?(Sketchup::Face)}
    faces=faces-connected-[face]
   end#while
  end#if
  ###
  ss.remove(group)### v1.6
  ###
  Sketchup::set_status_text((db("Reverse Faces ?")),SB_PROMPT)
  if UI.messagebox((db("Reverse Faces ?"))+"\n\n\n\n",MB_YESNO,"")==6 ### 6=YES 7=NO
    faces=[];gents.each{|e|faces.push(e)if e.kind_of?(Sketchup::Face)}
    num=1;tot=faces.length
    faces.each{|face|
      Sketchup::set_status_text(((db("Reversing Faces: Step "))+num.to_s+(db(" of "))+tot.to_s),SB_PROMPT)
      face.reverse!
      num=num+1
    }
  end#if
  ### intersect with self
  Sketchup::set_status_text((db("Intersect with Self ?")),SB_PROMPT)
  if UI.messagebox((db("Intersect with Self ?"))+"\n\n"+(db("This is only necessary with convoluted shapes...")),MB_YESNO,"")==6 ### 6=YES 7=NO
    Sketchup::set_status_text((db("Intersecting with Self...")),SB_PROMPT)
    gentsa1=group.entities.to_a
    gnum1=gents.length
    group.entities.intersect_with(true,group.transformation,group,group.transformation,true,group)
    gentsa2=group.entities.to_a
    gnum2=gents.length
    Sketchup::set_status_text((""),SB_PROMPT)
  end#all
  ###
  Sketchup::set_status_text((db("Erase Coplanar Edges ?")),SB_PROMPT)
  counter=0 
  if UI.messagebox((db("Erase Coplanar Edges ?"))+"\n\n\n\n",MB_YESNO,"")==6 ### 6=YES 7=NO
    edges=[];group.entities.each{|e|edges.push(e)if e.kind_of?(Sketchup::Edge)}
    edges.each{|e|
      if e.valid? and not e.faces[0]
        e.erase!
        counter+=1
        Sketchup::set_status_text(((db("Coplanar Edges Erased = "))+counter.to_s),SB_PROMPT)
      end
      if e.valid? and e.faces.length == 2
        if e.faces[0].normal.dot(e.faces[1].normal) > 0.99999999
          e.erase!
          counter+=1
          Sketchup::set_status_text(((db("Coplanar Edges Erased = "))+counter.to_s),SB_PROMPT)
        end#if
      end#if
    }
  end#if
  faces=[];gents.each{|e|faces.push(e)if e.kind_of?(Sketchup::Face)}
  Sketchup::set_status_text((""),SB_PROMPT)
  ###
  if UI.messagebox((db("Triangulate Faces ?"))+"\n\n\n\n",MB_YESNO,"")==6 ### 6=YES 7=NO
    triangulateEEE(faces,gents)
  end#if ####
  Sketchup::set_status_text((db("Erase Original Groups ?")),SB_PROMPT)
  if UI.messagebox((db("Erase Original Groups ?"))+"\n\n\n\n",MB_YESNO,"")==6 ### 6=YES 7=NO
    gp0o.erase! if gp0o.valid?
    gp1o.erase! if gp1o.valid?
  end#if
  ###
  model.commit_operation
  Sketchup.send_action("selectSelectionTool:")
end#def activate

end#class EEbyE

end#modulr
