=begin
(c) TIG 2012 - 2016
Script:
TIG-splitdonut.rb
###
Splits 'donut' shaped faces made with followme etc into 'quads' [four-sided 
faces].
Select some faces to process.
All other selected entities and any non-compliant faces are discarded.
Only those faces with an outer-loop and just one inner-loop which both have 
the same number of vertices are processed.
Lines are then added between 'matching' vertices to divide the 'donut' face 
into 'quads' [four-sided faces]...
Type into the Ruby Console: TIG.splitdonut
OR use Tools > Split Tools... submenu item.
It is one step undoable.
###
Donations: by PayPal.com to info @ revitrev.org
###
Version:
1.0 20120218 First issue.
1.1 20120219 At the end all new Edges added are selected to let you to use 
             Entity Info to set them soft/smooth or hidden etc as desired.
             Error messages added in incorrect selection.
             Now in Tools > Split Tools submenu
2.0 20160818 Signed for v2016 and combined into splitTOOLS RBZ.
=end
require 'sketchup.rb'
module TIG
def self.splitdonut()
  model=Sketchup.active_model
  ents=model.active_entities
  ss=model.selection
  faces=[]
  ss.each{|e|
    next unless e.class==Sketchup::Face and e.loops.length==2 and e.loops[0].vertices.length==e.loops[1].vertices.length
    faces << e
  }
  if not faces[0]
    UI.messagebox("TIG.splitdonut:\nYou must select at least ONE 'donut' face.")
    return
  end
  model.start_operation("TIG.splitdonut")
  nedges=[]
  faces.each{|face|
    oloop=face.outer_loop
    ops=[]; oloop.vertices.each{|v|ops << v.position}
    iloop=(face.loops-[oloop])[0]
    ips=[]; iloop.vertices.each{|v|ips << v.position}
    ips.reverse!
    op=ops[0]
    ip=ips[0]
    dd=1000000
    ix=0
    ips.each_with_index{|p, i|
      if op.distance(p) < dd
        dd=op.distance(p)
        ip=p
        ix=i
      end
    }
    if ix == ips.length-1
      ips=[ips[-1]]+ips[0..-2]
    elsif ix != 0
      ips=ips[ix..-1]+ips[0..(ix-1)] 
    end
    ops.each_with_index{|p, i|
      nedges << ents.add_line(p, ips[i])
    }
    tr=Geom::Transformation.new()
    ents.intersect_with(true, tr, ents, tr, true, [face])
  }
  ss.clear
  ss.add(nedges)
  model.commit_operation
end
end