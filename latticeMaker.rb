=begin
  Copyright 2010-2019 (c), TIG
  All Rights Reserved.
  THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED 
  WARRANTIES,INCLUDING,WITHOUT LIMITATION,THE IMPLIED WARRANTIES OF 
  MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
###
  latticeMaker.rb
###
Description:
  Takes a Selection of Faces and makes a Lattice, offset by a frame's given 
  width and depth, and pane inset, you can also assign limited Materials 
  to the frame/pane for ease of future selection/manipulation.
  It is similar to EEbyRailsToLattice BUT works on selected Surfaces/Faces...
###
Usage:
  Make a 3D Mesh - perhaps using EEbyRails or other tools - remember that 
  Faces need not be triangulated if all Edges' Vertices are 'coplanar', so 
  using similar profiles/rails will allow 'quad faces'.  You can also 
  manually draw over faces to sub-divide them as required.
  Edit the Group and Select the Faces to be converted into a Lattice - 
  any Edges etc in the Selection are ignored so you don't need to be too 
  careful.  Note that the Selected Faces and their Edges that are not 
  required by non-selected Faces will be deleted and replaced by the new 
  Lattice Group - if you want to keep them make a copy of the original mesh 
  to one side beforehand...
  Note that a Lattice frame is made in the direction away from a Face's 
  'front', so if you want the frames and pane to be formed in the other 
  direction 'Reverse' the Selected Faces beforehand.
  
  Run 'Lattice Maker', from the Plugins Menu.
  You are then prompted to chose the 'Lattice Properties':
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
  
  The Faces' edges are now offset to suit, then pushpulled to suit and the 
  materials applied.
  Note that faces that are too small to have a 'pane' are made 'solid'.
  The operation is one-step undo-able.
  
Version:
  1.0 20100511 First release.
  1.1 20101023 Pane 'thickness' option added.
               EN-US/FR/ES Lingvo files added in ../Plugins/TIGtools/ folder.
  1.2 20101027 ES lingvo updated by Defisto. Zip now contains deBabelizer.rb
  1.3 20130528 Optimized for v2013.
  1.4 20131206 Future-proofed.
  1.5 20140304 Future-proofed again.
  1.6 20140904 More future-proofing.
  2.0 20190626 Settings now remembered during a session.
               Context-menu added.
               Signed & lingvo files moved into its /latticeMaker subfolder.
  2.1 20190627 Trapped glitch for faces with slightly non-planar vertices.
  2.2 20191204 Trapped for 0 dim input freezing future entries to integers,
=end

#require('sketchup.rb')
load('deBabelizer.rb')

module TIG

  class LatticeMaker
  
    @@wid,@@dep,@@ins,@@thk,@@defa,@@pane = nil,nil,nil,nil,nil,nil

    def db(string)
      dir=File.dirname(__FILE__)+"/latticeMaker"
      toolname="latticeMaker" 
      locale=Sketchup.get_locale.upcase
      path = dir+"/"+toolname+locale+".lingvo"
      if ! File.exist?(path)
        return string
      else
        begin
          deBabelizer(string, path)
        rescue
          return string
        end
      end 
    end#db
    
    def LatticeMaker::db(string) ### for use in menu etc
      dir=File.dirname(__FILE__)+"/latticeMaker"
      toolname="latticeMaker"
      locale=Sketchup.get_locale.upcase
      path = dir+"/"+toolname+locale+".lingvo"
      if ! File.exist?(path)
        return string
      else
        begin
          deBabelizer(string, path)
        rescue
          return string
        end
      end 
    end#db
   
    def activate
      @model=Sketchup.active_model
      @ents=@model.active_entities
      @sel=@model.selection
      @sela=@sel.to_a
      @sel.clear
      if Sketchup.version.to_i > 6
        @model.start_operation((db("Lattice Maker")), true)
        ### 'false' is best to see results as UI/msgboxes...
      else
        @model.start_operation((db("Lattice Maker")))
      end
      ###
      offset_faces(@sela)
      ###
      @model.commit_operation
      deactivate()
      ###
    end#activate
    
    def deactivate(view=nil)
      ### view.invalidate if view ###
      Sketchup.send_action("selectSelectionTool:")
      return nil
    end#deactivate
    
    def face_offset(face=nil, dist=0)
      return nil if ! face || ! face.valid?
      return nil if (! ((dist.class==Float || dist.class==Length) && dist != 0))
      verts=face.outer_loop.vertices
      norm=face.normal
      pts=[]
      verts.each_index{|i|
        pt=verts[i].position
        vec1=pt.vector_to(verts[i-(verts.length-1)].position).normalize
        vec2=pt.vector_to(verts[i-1].position).normalize
        ang=vec1.angle_between(vec2)/2.0
        vec3=(vec1+vec2).normalize
		    if vec1.parallel?(vec2)
          ang=90.degrees 
          tpa=pt.offset(vec1)
          tr=Geom::Transformation.rotation(pt, norm, ang)
          tpa.transform!(tr)
          vec3=pt.vector_to(tpa)
        end
        if vec3 && vec3.valid? && vec3.length>0
          vec3.length=0.5.mm ### increased tolerance
          tpt=pt.offset(vec3)
          if dist > 0 ### ensure start at internal corner is extl.
            if face.classify_point(tpt) == Sketchup::Face::PointInside
              vec3.reverse!
            end
          else ### < 0 should be intl.
            if face.classify_point(tpt) != Sketchup::Face::PointInside
              vec3.reverse!
            end
          end
          vec3.length=(dist/Math::sin(ang)).abs
          pts << pt.offset(vec3)
        end#if
      }
      ###
      if pts[2]
        begin
          plane = face.plane
          #ppts = []
          #pts.each{|pt| ppt=pt.project_to_plane(plane); ppts << ppt }
          ppts = pts
          face.parent.entities.add_face(ppts)
        rescue
          UI.beep
          puts "Despite trying to force a fix, some of the selected face-vertices were NOT exactly coplanar!\nThe pane creation will probably be missed!!\n\n#{pts}\n\n#{plane}\n\ndist=#{dist}\n\n\n\n"
          ppts.each{|pt| puts "#{pt} = #{pt.on_plane?(plane)}"}
          puts
          begin
          
          rescue
          
          end
        end
      end
      ###
    end#face_offset
    
    def offset_faces(ents=nil)
      @msg=(db("Lattice Properties"))
      Sketchup::set_status_text(@msg)
      if ! ents
        return nil
      else
        titl=(db("Lattice Properties"))
        defa=(db("<Default>"))
        none=(db("<None>"))
        glas=(db("'Glass'"))
        mats1=defa+"|Red|Orange|Yellow|Green|Blue|Violet|Black|White|Gray|"
        mats2=defa+"|"+none+"|"+glas+"|Red|Orange|Yellow|Green|Blue|Violet|Black|White|Gray|"
        prom1=(db("Width: "))
        prom2=(db("Depth: "))
        prom3=(db("Pane Inset: "))
        prom3a=(db("Pane Thickness: "))
        prom4=(db("Lattice Material: "))
        prom5=(db("Pane Material: "))
        ###
        @@wid=2.inch if !@@wid && @model.options["UnitsOptions"]["LengthUnit"]<2
        @@dep=2.inch if !@@dep && @model.options["UnitsOptions"]["LengthUnit"]<2
        @@ins=1.inch if !@@ins && @model.options["UnitsOptions"]["LengthUnit"]<2
        @@thk=0.25.inch if !@@thk && @model.options["UnitsOptions"]["LengthUnit"]<2
        #
        @@wid=50.mm if !@@wid && @model.options["UnitsOptions"]["LengthUnit"]>1
        @@dep=50.mm if !@@dep && @model.options["UnitsOptions"]["LengthUnit"]>1
        @@ins=25.mm if !@@ins && @model.options["UnitsOptions"]["LengthUnit"]>1
        @@thk=5.mm if !@@thk && @model.options["UnitsOptions"]["LengthUnit"]>1
        ###
        @@defa=defa unless @@defa
        @@pane=none unless @@pane
        ###
        results=inputbox([prom1,prom2,prom3,prom3a,prom4,prom5], [@@wid,@@dep,@@ins,@@thk,@@defa,@@pane], ["","","","",mats1,mats2], titl)
        return nil unless results
        # save settings
        @msg=(db("Processing"))
        Sketchup::set_status_text(@msg)
        width=results[0]
        depth=results[1]
        pinset=results[2]
        pthick=results[3]
        frame=results[4]
        pane=results[5]
        ###
        width=@@wid if width<=0
        depth=@@dep if depth<0
        pinset=0.0.mm if pinset<0
        pinset=depth if pinset >depth
        pinset=depth if pane == none
        pthick=0.0.mm if pane == none
        if pthick < 0.0.mm
          if pthick.abs > pinset
            pthick= -pinset
          end#if
        end#if
        if pthick > depth-pinset
          pthick=depth-pinset
        end#if
        ###
        @@wid,@@dep,@@ins,@@thk,@@defa,@@pane = width,depth,pinset,pthick,frame,pane
        ###
        mats=[]
        @model.materials.each{|m|mats<< m.display_name}
        ### this traps for 'simlar' names matching...
        ### make missing materials.....................
        frame=nil if frame==defa
        if frame && ! mats.include?(frame)
          mat=@model.materials.add(frame)
          mat.color=frame ### e.g. 'Gray'
        end#if
        pane=nil if pane==defa
        if pane==glas && ! mats.include?(pane)
          mat=@model.materials.add(glas)
          mat.color=[150,200,250]
          mat.alpha=0.30
        elsif pane && pane != none && ! mats.include?(pane)
          mat=@model.materials.add(pane)
          mat.color=pane ### e.g. 'Gray'
        end#if
        ###
        ofaces=[]; ents.to_a.each{|e|ofaces<< e if e.class==Sketchup::Face}
        return nil if ! ofaces[0]
        entities=ofaces[0].parent.entities
        group=entities.add_group(ofaces)
        ents=group.entities 
        ofaces=[]; ents.to_a.each{|e|ofaces<< e if e.class==Sketchup::Face}
        ###
        ofaces.each{|face| face_offset(face, -(width.to_l)) }
        pfaces=[]
        ents.to_a.each{|e|pfaces << e if e.class==Sketchup::Face && e.valid? && ! ofaces.include?(e)}
        ### remove floating faces
        @msgx=@msg
        pfaces.each{|e|
          e.erase! if e.edges[0].faces.length==1
          @msgx=@msgx+"."
          Sketchup::set_status_text(@msgx)
        }
        Sketchup::set_status_text(@msg);@msgx=@msg
        ents.to_a.each{|e|
          e.erase! if e.class==Sketchup::Edge && e.faces.length==0
          @msgx=@msgx+"."
          Sketchup::set_status_text(@msgx)
        }
        ###
        pfaces=[]
        ents.to_a.each{|e|pfaces << e if e.class==Sketchup::Face && e.valid? && ! ofaces.include?(e)}
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
            newfaces.each{|e|tfaces<< e if e.valid? && (e.normal==norm || e.normal.reverse==norm)}
            tfaces[-1].reverse! if tfaces[-1].normal!=norm
            if @@thk!=0
              tfaces[-1].pushpull(-@@thk, true)
              nowfaces=[]
              ents.to_a.each{|e|nowfaces<< e if e.class==Sketchup::Face}
              newfaces= nowfaces - allfaces
              tfaces[-1].reverse! if tfaces[-1].normal!=norm
              newfaces.each{|e|tfaces<< e if e.valid? && (e.normal==norm || e.normal.reverse==norm)}
              newfaces.each{|e|e.erase! if e.valid? && ! (e.normal==norm || e.normal.reverse==norm)}
            end#if
            @msgx=@msgx+"."
            Sketchup::set_status_text(@msgx)
          }
          pfaces=tfaces
        end#if
        ### make '3d' with back
        Sketchup::set_status_text(@msg);@msgx=@msg
        ofaces.each{|face|
          face.pushpull(-(depth.to_l), true)
          face.reverse!
          @msgx=@msgx+"."
          Sketchup::set_status_text(@msgx)
        }
        ###
        faces=[]
        ents.to_a.each{|e|faces<< e if e.class==Sketchup::Face}
        ffaces= faces - pfaces
        Sketchup::set_status_text(@msg)
        @msgx=@msg
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
          Sketchup::set_status_text(@msg)
          @msgx=@msg
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
    
  end#class

  ### menu ################
  unless file_loaded?(__FILE__)
    textstring = LatticeMaker::db("Lattice Maker")
    instructions = LatticeMaker::db(": Select Faces. Set Parameters. Makes a Lattice...")
    cmd=UI::Command.new(textstring+"..."){ Sketchup.active_model.select_tool(LatticeMaker.new) }
    cmd.status_bar_text=textstring+instructions
    UI.menu("Plugins").add_item(cmd)
    UI.add_context_menu_handler{|menu| menu.add_item(cmd) }
    file_loaded(__FILE__)
  end

end#module