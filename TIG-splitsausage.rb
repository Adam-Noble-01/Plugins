=begin
(c) TIG 2012-2016
Script:
TIG-splitsausage.rb
###
Splits a 'sausage' shaped face, made with followme etc into 'quads' 
[four-sided faces].
Select ONE face and ONE edge that you want to be the 'seed' for the 
'quads' vertices, typically this will be the 'end' edge.
Lines are then added between 'matching' vertices along the 'sausage' to 
divide its face into 'quads'...
If the 'sausage' has an uneven number of vertices then the last facet will 
be a triangle
Type into the Ruby Console: TIG.splitsausage
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
             Now in Tools > Split Tools submenu. http://forums.sketchucation.com/viewtopic.php?p=386658#p386658
2.0 20160818 Signed for v2016 and combined into SplitTOOLS RBZ.
=end
require 'sketchup.rb'
module TIG
def self.splitsausage()
  model=Sketchup.active_model
  ents=model.active_entities
  ss=model.selection
  face=nil
  ss.each{|e|
    next unless e.class==Sketchup::Face
    face = e
    break
  }
  if not face
    UI.messagebox("TIG.splitsausage:\nYou must select ONE face.")
    return
  end
  edge=nil
  face.edges.each{|e|
    if ss.to_a.include?(e)
      edge=e
      break
    end
  }
  if not edge
    UI.messagebox("TIG.splitsausage:\nYou must select ONE edge belonging to the selected face.")
    return
  end
  model.start_operation("TIG.splitsausage")
  tgp=ents.add_group()
  tents=tgp.entities
  used=[]
  steps=(face.edges.length-4)/2.0
  steps=((steps+0.5).to_i)-1
  vs=edge.start
  ve=edge.end
  es=(vs.edges-[edge])[0]
  (vs.edges-[edge]).each{|e|es=e if e.faces.include?(face)}
  ee=(ve.edges-[edge])[0]
  (ve.edges-[edge]).each{|e|ee=e if e.faces.include?(face)}
  esv=es.other_vertex(vs)
  eev=ee.other_vertex(ve)
  nedges=[]
  nedges << tents.add_line(esv, eev)
  used << es << ee
  steps.times{
    es=(esv.edges-[es])[0]
    (esv.edges-[es]).each{|e|es=e if e.faces.include?(face) and not used.include?(e)}
    ee=(eev.edges-[ee])[0]
    (eev.edges-[ee]).each{|e|ee=e if e.faces.include?(face) and not used.include?(e)}
    esv=es.other_vertex(esv)
    eev=ee.other_vertex(eev)
    nedges << tents.add_line(esv, eev)
    used << es
    used << ee
  }
  tgp.explode
  ss.clear
  ss.add(nedges)
  model.commit_operation
end
end