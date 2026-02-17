=begin
Copyright 2014-2017 (c) TIG
[Based on some original ideas by Chris Fullmer in his 'Simple Loft']
  All Rights Reserved.
  THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED 
  WARRANTIES,INCLUDING,WITHOUT LIMITATION,THE IMPLIED WARRANTIES OF 
  MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
###
  extrudeEdgesByLoft.rb
###
  Smoothly connects a series of selected Curves with a bezier mesh.
###
Usage:
  Activate the Tool and follow the prompts.
  Select Curves in order [at least 2 are required].
  Each selected Curve is color-coded ROYGBIV as it's picked.
  You may NOT re-select the same Curve again unless it is the first one 
  that you selected [Red] and there are at least two curves already 
  highlighted.
  If you do re-select this first curve then the mesh might loop into a 
  weird convoluted 'doughnut' !
  
  Double-Click or Press <Enter> to complete the selection of the Curves.
  
  You are now prompted for the Number of Mesh Segments between each pair 
  of Curves - the initial value is based on the maximum number of 
  segments found in the Curve set.
  Press OK to accept this value, or enter a new value [>0] and press OK, 
  or press Cancel to stop the operation.
  
  The mesh is made with 'bezier' linking forms, and faces oriented.
  
  You are then prompted Yes/No to:
    To Reverse the Faces.
    Quad Faces
      Smooth the Mesh.
    Erase the Originally Selected Curves.
    
  Curves can have unequal number of segments - although keeping their  
  segmentation the same or in simple multipes can give 'smoother' forms.
  The Curves in a 'set' can be looped or open-ended as desired.
  All open-ended or all looped sets should give consistent results.
  Mixing looped and open-ended curves in the same 'set' might give 
  unexpected effects.
  It's recommended that you split loops in any mixed sets with a short 
  piece of line drawn to 'force' a combined start-point/end-point...
  The tool attempts to loft curves end_to_end without twisting - 
  however, some combinations of curves might benefit from having one 
  curve 'reversed' - if so explode it and then re-weld, or try edit-cut/
  paste_in_place...
  
###
Donations:
  Are welcome [by PayPal], please use 'TIGdonations.htm' in the 
  ../Plugins/TIGtools/ folder.
###

Version:
  1.0 20200309 First Release.
  1.1 20100309 FR lingvo updated by Didier Bur.
  1.2 20100310 Glitch with certain curve segment combinations fixed.
               Progress reporting during face orienting improved.
  1.3 20100311 ES lingvo updated by Diego-Rodriguez.
  1.4 20100312 Chinese lingvo file added by Hebeijianke
  1.5 20100330 Rare glitch with self.xxx fixed.
  1.6 20110812 Inputbox code improved.
  1.7 20111003 Quad Faces option added [smoothed diagonals].
  1.8 20111004 Quad Faces adjusted to hide diagonals too.
  1.9 20111023 Smooth now ignores edges with only one face.
  x2.0 20111113 Quad Faces option adjusted to Thomthom's latest specs.
  2.0 20130520 Becomes part of ExtrudeTools Extension.
=end
###
module ExtrudeTools
###
toolname="extrudeEdgesByLoft"
cmd=UI::Command.new(db("Extrude Edges by Loft")){Sketchup.active_model.select_tool(ExtrudeTools::ExtrudeEdgesByLoft.new())}
cmd.tooltip=db("Extrude Edges by Loft")
cmd.status_bar_text="..."
cmd.small_icon=File.join(EXTOOLS, "#{toolname}16x16.png")
cmd.large_icon=File.join(EXTOOLS, "#{toolname}24x24.png")
SUBMENU.add_item(cmd)
TOOLBAR.add_item(cmd)
###
class ExtrudeEdgesByLoft

include ExtrudeTools

class Sketchup::Face
 def orient_connected_faces_LOFT
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
    #msg=""#(db("Orienting Faces"))
    ###
	while @awaiting_faces[0]
	  @processed_faces.each{|face|
        unless @done_faces.include?(face)
	      #msg=msg+"."
          #Sketchup::set_status_text(msg)
		  @face=face
          face_flip
        end#if
	  }
    end#while
	#Sketchup::set_status_text("")
 end#def
 def face_flip
    @awaiting_faces=@awaiting_faces-[@face]
    @face.edges.each{|edge|
      rev1=edge.reversed_in?(@face)
      @common_faces=edge.faces-[@face]
      @common_faces.each{|face|
	    rev2=edge.reversed_in?(face)
        face.reverse! if @awaiting_faces.include?(face) && rev1==rev2
	    @awaiting_faces=@awaiting_faces-[face]
	    @processed_faces<<face
	  }
    }
    @done_faces<<@face
 end#def
end#class

  def initialize()
    ###
	@toolname="extrudeEdgesByLoft"
	###
  end#initialize
  
  def db(string)
	locale=Sketchup.get_locale.upcase
	path=File.join(EXTOOLS, @toolname+locale+".lingvo")
	if File.exist?(path)
		return deBabelizer(string, path)
	else
		return string
	end
  end#def

	def activate
		@model=Sketchup.active_model
		@ents=@model.active_entities
		@ss=@model.selection
		@ss.clear
		if Sketchup.version.to_i > 6
			@model.start_operation((db("Extrude Edges by Loft")), true)
			### 'false' is best to see results as UI/msgboxes...
		else
			@model.start_operation((db("Extrude Edges by Loft")))
		end#if
		@original_edges=[]
		@shapes=[]
		@shapes_edges=[]
		@start_end=[]
		@shape_normal=[]
		@first_shape=true
		@the_start_point=[]
		@the_end_point=[]
		@handles=[]
		@gps=[]
		@selected_curves=[]
		@old_start=[]
		@old_end=[]
		@shell=@ents.add_group()
		@diags=[]
		@msg=(db("Extrude Edges by Loft: Select Curves... [Double-Click or Press <Enter> to Make Mesh]"))
		Sketchup::set_status_text(@msg)
	end # activate
	
	def deactivate(view)
        ### view.invalidate if view ###
		Sketchup.send_action "selectSelectionTool:"
        return nil
	end # deactivate
    
    def resume(view)
      Sketchup::set_status_text(@msg)
      ### view.invalidate if view ###
    end #resume
	
    def onLButtonUp(flags,x,y,view)
      @msg=(db("Extrude Edges by Loft: Select Curves... [Double-Click or Press <Enter> to Make Mesh]"))
      Sketchup::set_status_text(@msg)
			ph=view.pick_helper
			ph.do_pick(x,y)
			best=ph.best_picked
			if (best.class==Sketchup::Edge && best.curve) && ((! @selected_curves[0]) || (@selected_curves[0]==best.curve && @selected_curves.length>2) or (@selected_curves[0] && ! @selected_curves[1..-1].include?(best.curve) && @selected_curves[0]!=best.curve))
				@selected_curves<< best.curve
				best_curve_edges=best.curve.edges
        best_curve_edges=self.clone_curve(best_curve_edges)
        @original_edges << best.curve.edges
				@shapes_edges << best_curve_edges
				@ss.add(best_curve_edges)
				@first_shape=false if @shapes.length > 0
				ordered_points=self.order_points(best_curve_edges)
				@shapes << ordered_points
        if @selected_curves[3] && @selected_curves[0]==@selected_curves[-1]
          self.get_segs_and_process(flags,x,y,view)
          ### we auto-stop as pick start curve as end curve
        end#if
      else
        UI.beep
        #puts (db("Extrude Edges by Loft: Select Curves... [Double-Click or Press <Enter> to Make Mesh]"))
      end#if
    end # onLButtonUp
    
   def draw(view)
     ### color code picked curves
     if @shapes
      0.upto((@shapes.length)-1) do |i|
        indx=i
        while indx > 6
          indx=i - 7
        end#while
        case indx
          when 0
            view.line_width=5
            view.drawing_color="red"
            view.draw(GL_LINE_STRIP,@shapes[i])
          when 1
            view.line_width=5
            view.drawing_color="orange"
            view.draw(GL_LINE_STRIP,@shapes[i])
          when 2
            view.line_width=5
            view.drawing_color="yellow"
            view.draw(GL_LINE_STRIP,@shapes[i])
          when 3
            view.line_width=5
            view.drawing_color="green"
            view.draw(GL_LINE_STRIP,@shapes[i])
          when 4
            view.line_width=5
            view.drawing_color="blue"
            view.draw(GL_LINE_STRIP,@shapes[i])
          when 5
            view.line_width=5
            view.drawing_color="indigo"
            view.draw(GL_LINE_STRIP,@shapes[i])
          when 6
            view.line_width=5
            view.drawing_color="violet"
            view.draw(GL_LINE_STRIP,@shapes[i])
          else
            view.line_width=5
            view.drawing_color="plum"
            view.draw(GL_LINE_STRIP,@shapes[i])
        end#case
      end#do
    end#if shapes
   end#drsw
        
    def onLButtonDoubleClick(flags,x,y,view)
        self.get_segs_and_process(view)
    end # double-click
	
	def onReturn(view)
        self.get_segs_and_process(view)
    end # return
    
    def clone_curve(edges)
      @gp=@shell.entities.add_group
      edges.each{|e|@gp.entities.add_line(e.start.position,e.end.position)}
      return @gp.entities.to_a
      @gps << @gp
    end#clone
    
    def get_segs_and_process(view)
		if @shapes.length > 1
            ###
            @gps.each{|gp|gp.erase! if gp.valid?}### remove temp curve groups
            ###
            @msg=(db("Extrude Edges by Loft"))
            Sketchup::set_status_text(@msg)
            @segs=0
            @shapes.each{|e|
              @segs=e.length-1 if e.length-1 > @segs
              @segs -=1 if e[0]==e[-1]###looped
            }
			values=[@segs]
            prompt1=(db("Segments per Section: "))
			prompts=[prompt1]
            title=@msg
			results=inputbox(prompts,values,title)
			return nil if not results
			if results[0] < 1
				UI.beep
				puts prompt1+"< 1 !"
				return nil
			end#if
			@segs=results[0]
            #############################################
            ###
            @ss.clear
            ###
            @msg=(db("Extrude Edges by Loft")+(db(": Please Wait...")))
            Sketchup::set_status_text(@msg)
            ###
            ### we adjust points so even count across all 'shapes'
            @newshapes=[]
            max=0
            @shapes.each{|shape|max=shape.length-1 if shape.length-1>max} ###-1 !
            @shapes.each{|shape|
              min=shape.length-1 ### -1
              ### work out divisions of lesser segmented profile edges and the remainder
              div=(max/min) ### every min edge gets divided up by this
              rem=(max-(div*min)) ### this is how many edges get div+1 divisions
              ### work out which edges get extra division ------------------------
              if rem==0
                xdivs=[]
              elsif (rem.to_f/min.to_f)==0.5
                xdivs=[]; ctr= -1
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
              else
                xdivs=[]
              end#if
              ###
              divpoints=[]
              0.upto(min-1) do |i| ### NOT -2?
               begin
                pts=shape[i]
                pte=shape[i+1]
                len=pts.distance(pte)
                vec=pts.vector_to(pte)
                ptx=pts.clone
                divpoints<<ptx.to_a
                ddiv=div
                ddiv=div+1 if xdivs.include?(i+1)
                ddiv.to_i.times{|j|
                    dis=len*j.to_f/ddiv.to_f
                  if vec.length>0
                    ptn=pts.offset(vec,dis)
                    ptx=ptn.clone
                    divpoints<<ptx.to_a if not ptx==divpoints.last
                  end#if
                }
                ptx=pte.clone
                divpoints<<ptx.to_a
               rescue Exception => e
                #puts e.message
                #puts "[curve_re-division]"
                ###
               end#begin
              end#do
              ###
              #@ents.add_text("S",divpoints[0],[0,0,10])
              #@ents.add_text("E",divpoints[-1],[0,0,10])
              ###
              loop=false
              loop=true if shape[0].to_a == shape[-1].to_a
              divpoints=divpoints.uniq.compact
              if divpoints.length<max and not loop
                newpoint=(Geom::Point3d.new(divpoints[0].x,divpoints[0].y,divpoints[0].z)).offset!(divpoints[0].vector_to(divpoints[1]),divpoints[0].distance(divpoints[1])/2).to_a
                divs=[divpoints[0]]+[newpoint]+divpoints[1..-1]
                divpoints=divs
              end#if
              if divpoints.length<max and not loop
                newpoint=(Geom::Point3d.new(divpoints[-1].x,divpoints[-1].y,divpoints[-1].z)).offset!(divpoints[-1].vector_to(divpoints[-2]),divpoints[-1].distance(divpoints[-2])/2).to_a
                divs=divpoints[0..-2]+[newpoint]+[divpoints[-1]]
                divpoints=divs
              end#if
              ###
              divpoints<< divpoints[0].to_a if loop #############
              ###
              @newshapes << divpoints
              divpoints=[]
            }#shapes
            ###
            @shapes=@newshapes.compact #########################
            ###
            seg_handles=[]
			start_handle=[]
			end_handle=[]
            ###
			start_handle=self.set_end_handles(@shapes[0],@shapes[1])
			###
			if @shapes.length > 2
				((@shapes.length)-2).times do |e|
					seg_handles=self.middle_handles(@shapes[e+1],@shapes[e],@shapes[e+2])
				    end_handle=seg_handles[0]
					@handles[e]=[start_handle,end_handle]
					start_handle=seg_handles[1]
				end#do
			end#if
            ###
			last_position=@handles.length
			end_handle=self.set_end_handles(@shapes[-1],@shapes[-2])
			@handles[last_position]=[start_handle,end_handle]
			###
			### process shapes
			begin
				tick=1
				0.upto(@shapes.length-2) do |i|
					@msg=(db("Mesh Section "))+tick.to_s+(db(" of "))+(@shapes.length-1).to_s
					Sketchup::set_status_text(@msg)
					###
					tgroup=self.make_shell(@shapes[i],@handles[i][0],@shapes[i+1],@handles[i][1],@segs)
					tgroup.explode
					###
					tick+=1
				end#do
				Sketchup::set_status_text("")
			rescue Exception => e
				#puts e.message
				#puts "[make_mesh_count]"
				###
			end#begin #################################################
			###
				###
				@msg=(db("Extrude Edges by Loft: Formatting Mesh - Please Wait..."))
				Sketchup::set_status_text(@msg)
				###
			temp_group=@ents.add_group(@shell)
			gents=temp_group.entities
			gents[0].explode
			### tidy some groups
			gents.to_a.each{|e|e.erase! if e.class==Sketchup::Group}
			###
    ### orient faces if one is flat and at zero
    @msg=(db("Extrude Edges by Loft: Orienting Faces - Please Wait..."))
    Sketchup::set_status_text(@msg)
    faces=[];gents.each{|e|faces<<e if e.class==Sketchup::Face}
    up=true
    faces.each{|face|
      if face.normal.z > 0 ### facing up
        face.orient_connected_faces_LOFT
        break ### only needs doing once
      end#if
      up=false
    }
    if not up
     faces.each{|face|
      if face.normal.z <= 0 ### NOT facing up
        face.reverse!
        face.orient_connected_faces_LOFT
        break ### only needs doing once
      end#if
     }
    end#if
    ###
	  @model.commit_operation
    ###
  ### Final tidy up...
  ### reverse faces ?
  faces=[];gents.each{|e|faces<<e if e.class==Sketchup::Face}
  @msg=(db("Extrude Edges by Loft: Reverse "))+faces.length.to_s+(db(" Faces ?"))
  Sketchup::set_status_text(@msg)
  rev=UI.messagebox(@msg,MB_YESNO,"")### 6=YES 7=NO
  if rev==6
    if Sketchup.version.to_i > 6
      @model.start_operation(@msg, true)
      ### 'false' is best to see results as UI/msgboxes...
		else
			@model.start_operation(@msg)
		end#if
    num=1
    faces.each{|face|
      @msg=((db("Extrude Edges by Loft: Reversing Face "))+(num.to_s)+(db(" of "))+(faces.length.to_s))
      Sketchup::set_status_text(@msg)
      face.reverse!
      num+=1
    }
    @model.commit_operation
  end#if
  ###
  ### QUADS ?
  quads=false
  if UI.messagebox((db("Extrude Edges by Loft:"))+"\n\n"+(db("Quad Faces ?"))+"\n\n\n\n",MB_YESNO,"")==6 ### 6=YES 7=NO 
    quads=true
    ### pause here so we see result...
		if Sketchup.version.to_i > 6
			@model.start_operation((db("Extrude Edges by Loft: Quad Face ")), true)
			### 'false' is best to see results as UI/msgboxes...
		else
			@model.start_operation((db("Extrude Edges by Loft: Quad Face ")))
		end
    tick=0
		tr=gents.parent.instances[0].transformation.inverse
    @diags.each{|a|
      tick+=1
      @msg=((db("Extrude Edges by Loft: Quad Face "))+tick.to_s+(db(" of "))+@diags.length.to_s)
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
  ### smooth edges ?
    edges=[];gents.each{|e|edges<<e if e.class==Sketchup::Edge and e.faces[1]}
    @msg=((db("Extrude Edges by Loft: Smooth "))+(edges.length.to_s)+(db(" Edges ?")))
    Sketchup::set_status_text(@msg)
  if yn=UI.messagebox(@msg,MB_YESNO,"")==6 ### 6=YES 7=NO
    ### pause here so we see result...
		if Sketchup.version.to_i > 6
			@model.start_operation(@msg, true)
			### 'false' is best to see results as UI/msgboxes...
		else
			@model.start_operation(@msg)
		end
      tick=1
      edges.each{|e|
        e.soft=true
        e.smooth=true
        @msg=((db("Extrude Edges by Loft: Smoothing Edge "))+tick.to_s+(db(" of "))+edges.length.to_s)
        Sketchup::set_status_text(@msg)
        tick+=1
      }
      @msg=(db("Extrude Edges by Loft: Re-Formatting Mesh - Please Wait..."))
      Sketchup::set_status_text(@msg)
      gpx=@model.active_entities.add_group(temp_group)
      temp_group.explode
      temp_group=gpx
      gents=temp_group.entities
      @model.commit_operation
  end#if
 end#if not quads
  ### erase original curves ?
    numb=@original_edges.length
    @msg=(db("Extrude Edges by Loft: Erase "))+(numb.to_s)+(db(" Original Curves ?"))
    Sketchup::set_status_text(@msg)
  if UI.messagebox(@msg,MB_YESNO,"")==6 ### 6=YES 7=NO  
    if Sketchup.version.to_i > 6
			@model.start_operation(@msg, true)
      ### 'false' is best to see results as UI/msgboxes...
		else
			@model.start_operation(@msg)
		end
    ###
    @ents.erase_entities(@original_edges.flatten)
    ###
    @model.commit_operation
  end#if
    ###########
	self.deactivate(view)
    ###########
	    else
            @msg=(db("Extrude Edges by Loft: Select at Least TWO Curves !"))
            Sketchup::set_status_text(@msg)
			UI.messagebox(@msg)
            @msg=(db("Extrude Edges by Loft: Select Curves... [Double-Click or Press <Enter> to Make Mesh]"))
            Sketchup::set_status_text(@msg)
		end#if
        ###
	end # def get_segs_and_process
    
    
	
	def middle_handles(points,prepoints,postpoints)
		points_array1=[]
		points_array2=[]
		new_vec=[]
		hz_vec=[]
		handle_vec=[]
		s1p1=[]
		s1p2=[]
		s2p1=[]
		s2p2=[]
		orig_vec1=[]
		orig_vec2=[]
		mp1=[]
		mp2=[]
		zvec=[]
		vec1=[]
		vec2=[]
		line1=[]
		line2=[]
		pt=[]
		d1=0
		d2=0		
		testpt1=[]
		points.each_index do |e|
          begin
			s1p1=points[e]
			s1p2=prepoints[e]
			s2p1=points[e]
			s2p2=postpoints[e]
			orig_vec1=s1p1.vector_to(s1p2)
			orig_vec2=s2p1.vector_to(s2p2)
			mp1=Geom.linear_combination(0.5,s1p1,0.5,s1p2)
			mp2=Geom.linear_combination(0.5,s2p1,0.5,s2p2)
			if orig_vec1.parallel?(orig_vec2)
				pt1=mp1
				pt2=mp2
			else
				zvec=orig_vec1.cross(orig_vec2)
				vec1=orig_vec1.cross(zvec)
				vec2=orig_vec2.cross(zvec)
				line1=[mp1,vec1]
				line2=[mp2,vec2]
				pt=Geom.intersect_line_line(line1,line2)
				new_vec=pt.vector_to points[e]
				hz_vec=new_vec.cross(orig_vec1)
				hz_vec.normalize!
				testpt1=points[e].clone.offset hz_vec
				handle_vec=hz_vec.cross new_vec
				testpt1=points[e].clone.offset(handle_vec)
				pt1=points[e].clone
				d1=(points[e].distance prepoints[e])/2
				d2=(points[e].distance postpoints[e])/2
				handle_vec.length=d1
				pt1.offset! handle_vec
				pt2=points[e].clone
				handle_vec.length=d2
				pt2.offset!(handle_vec.reverse!)
			end
			points_array1 << pt1.clone
			points_array2 << pt2.clone
			rescue Exception => e
				#puts e.message
				#puts e.backtrace
				#puts "[middle_handles]\n______________________"
				###
			end#begin
		end	
		return [points_array1,points_array2]
	end # middle_handles
	
	def set_end_handles(start_points,end_points)
      begin
        point_array=[]
		point2=[]
		length=0
		distance=0
		temp_group1=@ents.add_group()
		gents1=temp_group1.entities
		temp_group2=@ents.add_group()
		gents2=temp_group2.entities
		start_points.each_index do |e|
			#### --Do not remove these cpoints - they are part of the script --
			gents1.add_cpoint(start_points[e])
			gents2.add_cpoint(end_points[e])
			#### --Do not remove these cpoints - they are part of the script --
		end #do
		sppt=temp_group1.bounds.center
		eppt=temp_group2.bounds.center
		temp_group1.erase! if temp_group1.valid?
		temp_group2.erase! if temp_group2.valid?
		vec=sppt.vector_to(eppt)
        #gents2.each{|e|e.erase! if e.valid?}
		start_points.each_index do |e|
			distance=start_points[e].distance(end_points[e])
			length=distance/2
            point2=start_points[e].clone.offset!(vec,length)
			point_array << point2.to_a
		end#do
		rescue Exception => e
			#puts e.message
			#puts e.backtrace
			#puts "[set_end_handles]\n______________________"
			###
		temp_group1.erase! if temp_group1 && temp_group1.valid?
		temp_group2.erase! if temp_group2 && temp_group2.valid?
		###
      end#begin
		return point_array
	end
	
    
	def order_points(curve_edges)
		edge=[]
		allverts=[]
		temp_edge=[] 
		arc_first=true
		vert_points_array=[]
		start_vert=[]
		arc_endverts=[]
		curve_edges.each{|e|allverts << e.start << e.end}
		#allverts.uniq!
		allverts.each{|e|arc_endverts<< e if e.edges.length==1}
        ###
		if not @first_shape
          looped=false
          if arc_endverts[1]
			d1=@the_start_point.distance(arc_endverts[0].position)
			d2=@the_start_point.distance(arc_endverts[1].position)
            ###############
            d3=@the_end_point.distance(arc_endverts[0].position)
			d4=@the_end_point.distance(arc_endverts[1].position)
            ### fix for twists ################################
			if d1 > d2 && d3 < d4
              arc_endverts.reverse!
            end#if
            if d2==0 || d3==0
              arc_endverts.reverse!
            end#if
            ###
          else ### it's looped ########################
            looped=true
           ###puts "Looped Curve..."
            arc_endverts=[allverts[0],allverts[-1]]
            dis=@the_start_point.distance(arc_endverts[0].position)
            allverts.each{|v|
              if v.position.distance(@the_start_point)<dis
                start_vert=v 
                dis=v.position.distance(@the_start_point)
              end#if
            }
            breakindx=0
            0.upto((allverts.length)-1) do |i|
              if allverts[i].position.distance(@the_start_point) < dis
                breakindx=i
                dis=allverts[i].position.distance(@the_start_point)
              end#if
            end#do
            ### we now have vert nearest start pt
            tverts=allverts[breakindx..-1]+allverts[0..breakindx]
            ### repeat start at end of array
            allverts=tverts
            arc_endverts=[allverts[0],allverts[-1]]
          end#if
        else ### it IS the first curve ##########################
          unless arc_endverts[1]
            looped=true
            ###puts "Looped Curve [1st]..."
            arc_endverts=[allverts[0],allverts[-1]]
          end#if
		end#if
        ###
        #@ents.add_text("S",arc_endverts[0],[0,0,10])
        #@ents.add_text("E",arc_endverts[1],[0,0,10])
        ###
		cc=0
		start_vert=[arc_endverts[0]]
        @old_start=@the_start_point
        @old_end=@the_end_point
		@the_start_point=arc_endverts[0].position ### first run then repeats
		@the_end_point=arc_endverts[-1].position ### first run then repeats
        ###
		(curve_edges.length).times do
			vert_points_array << start_vert[0].position
			if arc_first
				edge=start_vert[0].edges
			else
				two_edges=start_vert[0].edges
				edge=two_edges-temp_edge
			end#if
			temp_edge=edge
			two_verts=edge[0].vertices
			start_vert=two_verts-start_vert
			arc_first=false
			cc+=1
		end#do
        ###
        if not @first_shape
			d1=@old_start.distance(arc_endverts[0].position)
			d2=@old_start.distance(arc_endverts[1].position)
            ### fix for twists ################################
            ###############
            d3=@old_end.distance(arc_endverts[0].position)
			d4=@old_end.distance(arc_endverts[1].position)
            ### fix for twists ################################
			if d1 > d2 && d3 < d4
              arc_endverts.reverse!
            end#if
            if d2==0 || d3==0
              arc_endverts.reverse!
            end#if
            ###
        end#if
        ###
		vert_points_array << arc_endverts[1].position
        vert_points_array << arc_endverts[0].position if looped
        #@ents.add_text("S",vert_points_array[0],[0,0,10])
        #@ents.add_text("E",vert_points_array[-1],[0,0,10])
        ###
		return vert_points_array
        ###
	end # order_points
	
	def make_shell(p0,p1,p2,p3,segs)
    begin
			temp=[]
			bc=[]
			tgroup=@shell.entities.add_group
			gents=tgroup.entities
			(p0.length).times do |cc| #### ???
				temp=self.bezier_points(p0[cc],p1[cc],p2[cc],p3[cc],segs)
				bc << temp
			end#do
		rescue Exception => e
			#puts e.message
			#puts "[make_mesh error 1]"
			###
		end#begin
    begin
			cc1=0
			cc2=0
			while cc1 < (bc.length-1) ### ???
				while cc2 < (bc[cc1].length-1) ### ???
					fp0=bc[cc1][cc2]
					fp1=bc[cc1+1][cc2]
					fp2=bc[cc1+1][cc2+1]
					fp3=bc[cc1][cc2+1]
					begin
						face1=gents.add_face([fp0,fp1,fp3])if fp0!=fp3
					rescue Exception => e
						#puts e.message
						#puts "[make_mesh error 2 face=1]"
						###
					end#begin
					begin
						face2=gents.add_face([fp1,fp2,fp3])if fp1!=fp3
					rescue Exception => e
						#puts e.message
						#puts "[make_mesh error 2 face=2]"
						###
					end#begin
					if face1 && face1.valid? && face2 && face2.valid?
						es1=face1.edges
						es2=face2.edges
						@diags << [(es1-(es1-es2))[0].start.position, (es1-(es1-es2))[0].end.position]
					end#if
					cc2+=1
				end#while
				cc1+=1
				cc2=0
			end#while
      rescue Exception => e
        #puts e.message
        #puts "[make_mesh error 3]"
        ###
      end#begin
      return tgroup
	end # make_shell
	
	def bezier_points(p0,p1,p2,p3,segs)
     points_array=[]
      begin
		np=[0,0,0]
		cx=(3*(p1[0]-p0[0]))
		bx=(3*(p3[0]-p1[0]))-cx
		ax=(p2[0]-p0[0])-cx-bx
		cy=(3*(p1[1]-p0[1]))
		by=(3*(p3[1]-p1[1]))-cy
		ay=(p2[1]-p0[1])-cy-by
		cz=(3*(p1[2]-p0[2]))
		bz=(3*(p3[2]-p1[2]))-cz
		az=(p2[2]-p0[2])-cz-bz
		(segs.to_i+1).times do |e|
			t=e/segs.to_f
			np.x=(ax*(t**3))+(bx*(t**2))+(cx*t)+p0[0]
			np.y=(ay*(t**3))+(by*(t**2))+(cy*t)+p0[1]
			np.z=(az*(t**3))+(bz*(t**2))+(cz*t)+p0[2]
			points_array << np.clone.to_a
		end#do
      rescue Exception => e
        puts e.message
        puts "[bezier error]"
        p p0
        p p1
        p p2
        p p3
        puts "___________________________________________"
      end#begin
	  return points_array
	end # bezier_points
	
end # class
end#module
###
