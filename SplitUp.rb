=begin
#-----------------------------------------------------------------------
Copyright 2011-2016 TIG & Rich O'Brien (c)
Permission to use, copy, modify, and distribute this software for 
any purpose and without fee is hereby granted, provided that the above
copyright notice appear in all copies.
This software is provided "as is" and without any express or
implied warranties, including, without limitation, the implied
warranties of merchantability and fitness for a particular purpose.
Name:
  SplitUp.rb
Usage:
  Splits selected 'quad faces' into the specified number of parts.
  Use in Ruby Console or other code, thus:
  SplitUp.new(2) [or more sloppily SplitUp.new 2]
  as shown here 2 is the number of divisions wanted.
  OR use Tools > Split Tools... > submenu item SplitUp and enter the 
  division number in the dialog [default=1 >> NO splits]
  [The Plugins menu item is now disabled by default from v1.5 but see end 
  of the main code IF you want to re-enable it...]
  If any selected face is not a quad OR a quad with one quad-hole - 
  then the face and probably all of its connected neighbours should first be 
  'Quadrilateralized' - i.e. split up into quads - a message tells you this, 
  but you may still continue...
  New edges are softened/smoothed.
  It returns the number of faces processed and made [n,nn]
  It's one step undoable.
Donations:
  By PayPal.com to info @ revitrev.org
Version:
  1.0 20110717 First issue.
  1.1 20110718 Now works on quads and quads with one quad hole.
               Plugins menu item and dialog added.
  1.2 20110718 Softened/smoothed new edges.
  1.3 20110719 Glitches with smoothing etc fixed.
  1.4 20111111 Overhauled and less error prone.
  1.5 20120219 Plugins menu item disabled; 
               now in Tools > Split Tools submenu.
	2.0 20160818 Signed for v2016 and combined into SplitTOOLS RBZ.
=end
require 'sketchup.rb'
###
module SplitUp
  def self.new(num=0)
    @type=num
    @model=Sketchup.active_model
    @ents=@model.active_entities
    @ss=@model.selection
    return nil if not self.valid_selection?()
	if num==0
      self.process() if self.dialog()
      return nil###
	else
      @num=num
      self.process()
      return [@faces.length, @tfaces.length*@num*@num]
    end
  end
  def self.valid_selection?()
    if @ss.empty?
      if @type==0
        UI.messagebox("SplitUp: No selection!")
      else
        UI.beep
        puts "SplitUp: No selection!"
      end
      return nil
    end
    @faces=[]
    @ss.each{|e|@faces << e if e.class==Sketchup::Face}
    if not @faces[0]
      if @type==0
        UI.messagebox("SplitUp: No faces in selection!")
      else
        UI.beep
        puts "SplitUp: No faces in selection!"
      end
      return nil
    end
    @faces.each{|face|
      if face.outer_loop.edges.length!=4 or face.loops.length>2 or (face.loops.length!=1 and (face.loops-[face.outer_loop])[0].edges.length!=4)
        if @type==0
          UI.messagebox("SplitUp: Some faces in selection do not have 4 edges!\nSuggest you use 'Quadrilateralizer' on all required faces.")
        else
          UI.beep
          puts "SplitUp: Some faces in selection do not have 4 edges!\nSuggest you use 'Quadrilateralizer' on all required faces."
        end
        break
      end#if
    }
    return true
  end
  def self.dialog()
    @num=1 if not @num
    results=UI.inputbox(["Divisions: "],[@num],"SplitUp")
    return nil if not results
    @num=results[0]
    return @num
  end
  def self.process()
    begin
      @model.start_operation("SplitUp: "+@num.to_s, true)
    rescue
      @model.start_operation("SplitUp: "+@num.to_s)
    end
    @ss.clear
    ###
    self.clone_faces()
    @tfaces.each{|gp|
      face=nil
      gp.entities.each{|e|face=e if e.class==Sketchup::Face}
      self.splitter(face)
      begin
       @model.active_view.refresh
      rescue
        ###
      end
    }
    @ents.erase_entities(@tfaces)
    ###
    @model.commit_operation
  end
  def self.clone_faces()
    @divs=[]
    @tfaces=[]
    @faces.each{|face|
      next if face.outer_loop.edges.length!=4 or face.loops.length>2 or (face.loops.length!=1 and (face.loops-[face.outer_loop])[0].edges.length!=4)
      gp=@ents.add_group()
      hole=nil
      if face.loops.length>1
        hole=gp.entities.add_face((face.loops-[face.outer_loop])[0].vertices)
      end
      fo=gp.entities.add_face(face.outer_loop.vertices)
      if hole and hole.valid?
        hole.erase!
        ### divide into 4 faces
        ol=fo.outer_loop
        il=(fo.loops-[fo.outer_loop])[0]
        olvs=ol.vertices
        ilvs=il.vertices
        olvs.each{|v|
          p0=v.position
          p1=ilvs[0].position
          di=p0.distance(p1)
          vi=ilvs[0]
          ilvs.each{|i|
            if p0.distance(i.position) < di
              p1=i.position
              di=p0.distance(p1)
              vi=i
            end
          }
          gp.entities.add_line(p0,p1)
          ll=@ents.add_line(p0,p1)
          ll.smooth=true
          ll.soft=true
          @divs << [p0.to_a, p1.to_a]
          ilvs=ilvs-[vi]
        }
        @divs.uniq!
        gps=[]
        hfaces=[]
        gp.entities.each{|e|hfaces << e if e.class==Sketchup::Face}
        ###
        hfaces.each{|f|
          g=gp.entities.add_group()
          g.entities.add_face(f.vertices)
          gps << g
        }
        edges2go=[]
        hfaces.each{|f|edges2go << f.edges}
        edges2go.flatten!
        edges2go.uniq!
        gp.entities.erase_entities(edges2go)
        gps.each{|g|@tfaces << g}
        gp.explode
      else
        @tfaces << gp
      end
    }
  end
  def self.splitter(face)
    pts=[]
    edges=face.edges
    edges.each{|e|
      ps=e.start.position
      pe=e.end.position
      ve=e.line[1]
      di=e.length
      ds=di/@num
      ptx=[]
      1.upto(@num-1){|i|
        pt=ps.offset(ve, ds*i)
        e=e.split(pt)
        ptx << pt
      }
      pts << ptx
    }
    edges=face.edges
    nedges=[]
    begin
      (@num-1).times{|i|
        nedges << @ents.add_line(pts[0][i], pts[2][-i-1])
        nedges << @ents.add_line(pts[1][i], pts[3][-i-1])
      }
    rescue Exception => e
      puts e ### should never happen!
    end 
    tr=Geom::Transformation.new()
    nnedges=@ents.intersect_with(true, tr, @ents, tr, true, nedges)
    sedges=nedges+nnedges
    sedges.uniq!
    sedges.each{|e|
      next unless e.valid?
      e.smooth=true
      e.soft=true
    }
  end
  ### remove the '#' in front of the next 4 lines starting #unless ...
  ###  to re-enable the Plugins menu item
  #unless file_loaded?(File.basename(__FILE__))
    #UI.menu("Plugins").add_item("SplitUp"){SplitUp.new()}
  #end#if
  #file_loaded(File.basename(__FILE__))
  ###
end#module
###