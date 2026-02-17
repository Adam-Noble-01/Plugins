=begin
  Copyright 2014-2017 (c) TIG
  All Rights Reserved.
  THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED 
  WARRANTIES,INCLUDING,WITHOUT LIMITATION,THE IMPLIED WARRANTIES OF 
  MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
###
  extrudeEdgesByOffset.rb
###
Usage:
  Select two or more Edges, Curves etc to be Offset.
  Anything else in the Selection, such as Faces, will be ignored.
  The selected edges must be 'coplanar' and should be 'connected' and not 
  'branching' - otherwise the tool might stop, or unexpected offset results 
  can occur.
        
  Run the Tool from Plugins > 'Extrude Edges by Offset'.
  or click on 'Extrude Edges by Offset' in the 'Extrusion Tools' Toolbar.
  [Activate this Toolbar from View > Toolbars if it's not loaded]
  
  If there are < 2 edges or they are not coplanar then a dialog warns and 
  the tool stops.
  A dialog opens, enter the required offset distance in current units or 
  other units with a units suffix - e.g. if you are working in 'mm' 
  entering 100 offsets 100mm but entering 4" would offset 4" [101.6mm].
  OK to continue, Cancel to stop tool.
  Entering a -ve value offsets 'inwards' rather than the default 'outwards' 
  Note that you cannot enter 0 as the value - you are warned and the dialog 
  reopens so you can retry, entering 0 again [or Cancel] stops the tool.
  The offset entered is remembered across tool uses in the same session.
  The selected edges are replicated inside a group and offset by the 
  desired distance.  A loop of edges creates an offset 'doughtnut' form; 
  a set of edges with open edges is finished with two 'square' ends.
  Faces are added to these edges and subdivision coplanar edges are added 
  across each pair of vertices. You are prompted Yes|No to reverse the 
  faces [the default is 'up'], then to erase the coplanar edges and finally 
  to explode   the group so that the new geometry merges back into the 
  active_entities' geometry.
  
Donations:
    Are welcome by PayPal to info @ revitrev.org.
    
Version:
    1.0 20110525 First release.
    1.1 20110812 Inputbox code improved.
    1.2 ? Typo fixed in dialog title, ES lingvos updated by Defisto.
	2.0 20130520 Becomes part of ExtrudeTools Extension.
=end
###
module ExtrudeTools
###
toolname="extrudeEdgesByOffset"
cmd=UI::Command.new(db("Extrude Edges by Offset")){Sketchup.active_model.select_tool(ExtrudeTools::ExtrudeEdgesByOffset.new())}
cmd.tooltip=db("Extrude Edges by Offset")
cmd.status_bar_text="..."
cmd.small_icon=File.join(EXTOOLS, "#{toolname}16x16.png")
cmd.large_icon=File.join(EXTOOLS, "#{toolname}24x24.png")
SUBMENU.add_item(cmd)
TOOLBAR.add_item(cmd)
###
class ExtrudeEdgesByOffset

include ExtrudeTools

@@dist=nil

  def db(string)
	locale=Sketchup.get_locale.upcase
	path=File.join(EXTOOLS, @toolname+locale+".lingvo")
	if File.exist?(path)
		return deBabelizer(string, path)
	else
		return string
	end
  end#def

 def initialize(dist=nil)
   @toolname="extrudeEdgesByOffset"
   if dist==0
     puts db('Extrude Edges by Offset')+db(': Offset cannot be 0!')
     return nil
   end#if
	 @model=Sketchup.active_model
   model=Sketchup.active_model
   ss=model.selection
   edges=[]
   ss.each{|e|edges << e if e.class==Sketchup::Edge}
   if not edges[1]
     if not dist
       UI.messagebox(db('Extrude Edges by Offset')+db(': Must Select >=2 Edges!'))
     else
       puts db('Extrude Edges by Offset')+db(': Must Select >=2 Edges!')
     end
     return nil
   end#if
   verts=[]
   edges.each{|e| verts << e.vertices}
   verts.flatten!
   verts.uniq!
   pts=[]
   verts.each{|v| pts << v.position}
   cop=true
   vec=Geom::Vector3d.new(0,0,0)
   edges[0..-2].each_with_index{|e,i| vec=e.line[1].cross(edges[i+1].line[1])}
   vec=Z_AXIS.clone if vec.length==0 ### all in line
   plane=[pts[0],vec]
   pts.each{|p|
     if not p.on_plane?(plane)
       cop=false
       break
     end
   }
   if not dist
     if not cop
       UI.messagebox(db('Extrude Edges by Offset')+db(': Edges must be coplanar!'))
       return nil
     end
     @@dist=0.to_l if not @@dist
     Sketchup::set_status_text((db("Extrude Edges by Offset"))+": "+(db("Distance: ")), SB_PROMPT)
     results=inputbox([db("Distance: ")],[@@dist],db("Extrude Edges by Offset")+"...")
     return nil if not results
     if results[0]==0
       UI.messagebox(db('Extrude Edges by Offset')+db(': Offset cannot be 0!')+"\n"+db("Try again")+"...")
       results=inputbox([db("Distance: ")],[@@dist],db("Extrude Edges by Offset")+"...")
       return nil if not results or results[0]==0
     end#if
     @@dist=results[0]
   else ### dist passed as arg
     if not cop
       puts db('Extrude Edge by Offset')+db(': Edges must be coplanar!')
       return nil
     end
     @@dist=dist.to_l
   end#if
   ###
   model.start_operation(db("Extrude Edges by Offset")+' '+@@dist.to_s)
   dist=@@dist
   group=model.active_entities.add_group()
   ents=group.entities
   ###
   if edges.length==verts.length ### looped
     ###
     tface=ents.add_face(pts)
     ###
	 fverts=tface.outer_loop.vertices
	 fpts=[]
		0.upto(fverts.length-1) do |a|
			vec1=(fverts[a].position-fverts[a-(fverts.length-1)].position).normalize
			vec2=(fverts[a].position-fverts[a-1].position).normalize
			vec3=(vec1+vec2).normalize
			if vec3.valid?
				ang=vec1.angle_between(vec2)/2
				ang=180.degrees if vec1.parallel?(vec2)
				vec3.length=dist/Math::sin(ang)
				t=Geom::Transformation.new(vec3)
				if fpts.length > 0
					if not (vec2.parallel?(fpts.last.vector_to(fverts[a].position.transform(t))))
						t=Geom::Transformation.new(vec3.reverse)
					end
				end
				fpts << fverts[a].position.transform(t)
			end
		end
	  nface=ents.add_face(fpts)
      tface.erase! if tface.valid? and dist>0
      nface.erase! if nface.valid? and dist<0
      face=nil; ents.each{|e|face=e if e.class==Sketchup::Face}
      face.reverse! if face.normal.z<0
      ol=face.outer_loop
      verts=ol.vertices if dist<0
      il=(face.loops-[ol])[0]
      verts=il.vertices if dist>0
      verts.each_with_index{|vert,a|
                vec1=(verts[a].position.vector_to(verts[a-(verts.length-1)].position)).normalize
				vec2=(verts[a].position.vector_to(verts[a-1].position)).normalize
				vec3=(vec1+vec2).normalize
				if vec3.valid?
					ang=vec1.angle_between(vec2)/2
					ang=90.degrees if vec1.parallel?(vec2)
					vec3.length= -dist/Math::sin(ang)
					t=Geom::Transformation.new(vec3)
                    p=verts[a].position
					pt=p.transform(t)
                    ents.add_line(p,pt)
				end
      }
      ###
      tr=Geom::Transformation.new()
      len=ents.length
      len.times{ents.intersect_with(true, tr, ents, tr, true, ents.to_a)}
      ###
      cedges=[]; ents.each{|e|cedges << e if e.class==Sketchup::Edge}
      ###
    else ### open ended
      ###
      edges.each{|e|ents.add_line(e.start.position, e.end.position)}
      edges=ents.to_a
      es=[]
      ee=[]
      se=[]
      edges.each{|e|
        if not e.start.edges[1]
          es=e.start
          ee=e.end
          se=e
          break
        elsif not e.end.edges[1]
          es=e.end
          ee=e.start
          se=e
          break
        end#if
      }
      nedges=[se]
      verts=[es,ee]
      (edges.length-1).times{
        edges.each{|e|
          next if nedges.include?(e)
          if e.start==ee
            verts << e.vertices
            ee=e.end
            nedges << e
          elsif e.end==ee
            verts << e.vertices
            ee=e.start
            nedges << e
          end
        }
      }
      verts.flatten!
      verts.uniq!
      ###
      opts=[]
      verts.each_with_index{|vert,a|
        if a==0 #special case for start vertex
				v=verts[a].position.vector_to(verts[a+1].position).normalize
				f=dist/dist.abs
				t=Geom::Transformation.rotation(verts[0].position, vec, 90.degrees*f)
				vec3=v.transform(t)
				vec3.length=dist.abs
				opts << verts[a].position.transform(vec3)
	    elsif a==verts.length-1 #special case for end vertex
				v=verts[a-1].position.vector_to(verts[a].position).normalize
				f=dist/dist.abs
				t=Geom::Transformation.rotation(verts[a].position, vec, 90.degrees*f)
				vec3=v.transform(t)
				vec3.length=dist.abs
				opts << verts[a].position.transform(vec3)
		else
				vec1=(verts[a].position.vector_to(verts[a+1].position)).normalize
				vec2=(verts[a].position.vector_to(verts[a-1].position)).normalize
				vec3=(vec1+vec2).normalize
				if vec3.valid?
					ang=vec1.angle_between(vec2)/2
					ang=90.degrees if vec1.parallel?(vec2)
					vec3.length=dist/Math::sin(ang)
					t=Geom::Transformation.new(vec3)
					if not vec2.parallel?(opts[-1].vector_to(verts[a].position.transform(t)))
					  t=Geom::Transformation.new(vec3.reverse)
					end
					opts << verts[a].position.transform(t)
				end
		end#if
      }
      begin
        nedges=ents.add_edges(opts)
      rescue
        nedges=[]
      end
      pts=[]
      verts.each{|v|pts << v.position}
      ents.erase_entities(edges)
      begin
        edges=ents.add_edges(pts)
      rescue
        edges=[]
      end
      pts.each_with_index{|p,i|ents.add_line(pts[i],opts[i])}
      ###
      tr=Geom::Transformation.new()
      len=ents.length
      len.times{ents.intersect_with(true, tr, ents, tr, true, ents.to_a)}
      ###
      cedges=[]; ents.each{|e|cedges << e if e.class==Sketchup::Edge}
      cedges.length.times{
        ents.to_a.each{|e|
          next if e.class!=Sketchup::Edge or not e.valid?
          e.find_faces
        }
      }
      ents.to_a.each{|e|e.reverse! if e.class==Sketchup::Face and e.normal.z<0}
      ###
    end#if
    ###
    ### no need to orient ??
    ### reverse?
    Sketchup::set_status_text((db("Extrude Edges by Offset"))+": "+(db("Reverse Faces ?")), SB_PROMPT)
      if UI.messagebox((db("Extrude Edges by Offset"))+": "+(db("Reverse Faces ?")),MB_YESNO,"")==6 ### 6=YES 7=NO
        ents.each{|e|e.reverse! if e.class==Sketchup::Face}
        begin
          view.refresh
        rescue
          ### <v8
        end
      end#if
    ### erase coplanar ?
    Sketchup::set_status_text((db("Extrude Edges by Offset"))+": "+(db("Erase Coplanar Edges ?")), SB_PROMPT)
      if UI.messagebox((db("Extrude Edges by Offset"))+": "+(db("Erase Coplanar Edges ?")),MB_YESNO,"")==6 ### 6=YES 7=NO
        cedges.each{|e|e.erase! if e.valid? and e.class==Sketchup::Edge and (not e.faces[0] or e.faces[1])}
        begin
          view.refresh
        rescue
          ### <v8
        end
      end#if

    ### explode?
    Sketchup::set_status_text((db("Extrude Edges by Offset"))+": "+(db("Explode Group ?")), SB_PROMPT)
      if UI.messagebox((db("Extrude Edges by Offset"))+": "+(db("Explode Group ?")),MB_YESNO,"")==6 ### 6=YES 7=NO
        group.explode
      end#if
    ###
    begin
      view.refresh
    rescue
      ### <v8
    end
    model.commit_operation
    Sketchup.send_action("selectSelectionTool:")
  end#def

end#class

end#module
