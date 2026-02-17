=begin
(c) TIG 2012-2016
Script:
TIG-splitTOOLS.rb
###
Makes a Tools menu submenu and toolbar 'Split Tools' which run the 
following tools:-
-SplitUp
http://forums.sketchucation.com/viewtopic.php?p=377338#p377338
-SplitDonut
http://forums.sketchucation.com/viewtopic.php?p=386601#p386601
-SplitSausage
http://forums.sketchucation.com/viewtopic.php?p=386610#p386610
See there respective threads...
Download and install each of the individual tools as desired...
If you don't have a tool installed then there'll be no button/menu-item.

Note that older versions of SplitUp may also have a menu item in 'Plugins'.

From v1.2 the code includes for a potential of 3 additional EEby... tools 
-extrudeEdgesByOffset
-extrudeEdgesByVector
-extrudeEdgesByVectorToObject
to be added to the toolbar/menu, to activate them remove the leading 
'#' from a tool's line.  #eeo=true... >>> eeo=true... etc
You'll need the 'ExtrusionTools' [zipped] EEby... toolset installing for 
these EEby... tools to be successfully added... 
http://forums.sketchucation.com/viewtopic.php?p=217663#p217663

Note the installation files come in a ZIP or RBZ archive; 
the the file 'TIG-splitTOOLS.rb' goes into the Plugins folder and the 
folder 'TIG-splitTOOLS' [containing the PNG files for the toolbar buttons] 
also goes into the Plugins folder...
###
Donations: by PayPal.com to info @ revitrev.org
###
Version:
1.0 20120218 First issue.
1.1 20120219 Typo is large icon names fixed [24].
NOTE: The SplitUp tool no longer has a Plugins menu item by default and 
SplitDonut and SplitSausage now conclude with all of the new edges selected 
so now you can choose to use Entity Info to smooth/soften or hide them etc 
as desired...
1.2 20120219 Three EEby... tools added to the toolbar/menu, ~lines#57-59, 
             to activate them remove the leading '#' from a tool's line.
2.0 20160818 Signed for v2016 and all files combined into SplitTOOLS RBZ.
=end
require 'sketchup.rb'
### check for files.
module TIG
def self.splitTOOLS()
  ###
  dir=File.dirname(__FILE__)
  ###
  sup=sdo=ssa=false
  sup=true if File.exist?(File.join(dir, 'SplitUp.rb'))
  sdo=true if File.exist?(File.join(dir, 'TIG-splitdonut.rb'))
  ssa=true if File.exist?(File.join(dir, 'TIG-splitsausage.rb'))
  ###
  eeo=eev=evo=false
  ### To add a EEby... tool remove leading '#' #eeo=true... >>> eeo=true...
  #eeo=true if File.exist?(File.join(dir, 'extrudeEdgesByOffset.rb'))
  #eev=true if File.exist?(File.join(dir, 'extrudeEdgesByVector.rb'))
  #evo=true if File.exist?(File.join(dir, 'extrudeEdgesByVectorToObject.rb'))
  ###
  unless file_loaded?(File.basename(__FILE__))
    if sup or sdo or ssa or eeo or eev or evo
      toolbar=UI::Toolbar.new('Split Tools')
      toolbar.restore if toolbar.get_last_state==TB_VISIBLE
      menu=UI.menu('Tools').add_submenu('Split Tools...')
    else
      return nil
    end
    if sup
      cmd=UI::Command.new('SplitUp'){SplitUp.new()}
      cmd.tooltip=('SplitUp')
      cmd.status_bar_text=('SplitUp: Splits selected quads or quad-donuts into smaller quads...')
      cmd.small_icon=File.join(File.dirname(__FILE__), 'TIG-SplitTOOLS', 'SplitUp-16.png')
      cmd.large_icon=File.join(File.dirname(__FILE__), 'TIG-SplitTOOLS', 'SplitUp-24.png')
      toolbar.add_item(cmd)
      menu.add_item(cmd)
    end
    if sdo
      cmd=UI::Command.new('SplitDonut'){TIG.splitdonut()}
      cmd.tooltip=('SplitDonut')
      cmd.status_bar_text=('SplitDonut: Splits selected \'donut\' faces into quads...')
      cmd.small_icon=File.join(File.dirname(__FILE__), 'TIG-SplitTOOLS', 'SplitDonut-16.png')
      cmd.large_icon=File.join(File.dirname(__FILE__), 'TIG-SplitTOOLS', 'SplitDonut-24.png')
      toolbar.add_item(cmd)
      menu.add_item(cmd)
    end
    if ssa
      cmd=UI::Command.new('SplitSausage'){TIG.splitsausage()}
      cmd.tooltip=('SplitSausage')
      cmd.status_bar_text=('SplitSausage: Splits selected \'sausage\' face into quads using selected edge as its \'seed\'...')
      cmd.small_icon=File.join(File.dirname(__FILE__), 'TIG-SplitTOOLS', 'SplitSausage-16.png')
      cmd.large_icon=File.join(File.dirname(__FILE__), 'TIG-SplitTOOLS', 'SplitSausage-24.png')
      toolbar.add_item(cmd)
      menu.add_item(cmd)
    end
    if eeo
      cmd=UI::Command.new('Extrude Edges by Offset'){extrudeEdgesByOffset()}
      cmd.tooltip=('Extrude Edges by Offset')
      cmd.status_bar_text=('Extrude Edges by Offset: Preselect Edges, Run Tool, Enter Offset, Yes|No Options...')
      cmd.small_icon=File.join(File.dirname(__FILE__), 'TIGtools', 'extrudeEdgesByOffset16x16.png')
      cmd.large_icon=File.join(File.dirname(__FILE__), 'TIGtools', 'extrudeEdgesByOffset24x24.png')
      toolbar.add_item(cmd)
      menu.add_item(cmd)
    end
    if eev
      cmd=UI::Command.new('Extrude Edges by Vector'){extrudeEdgesByVector()}
      cmd.tooltip=('Extrude Edges by Vector')
      cmd.status_bar_text=('Extrude Edges by Vector: Pre-Select Edges/Curves/Face, Pick Vector Start & End...')
      cmd.small_icon=File.join(File.dirname(__FILE__), 'TIGtools', 'extrudeEdgesByVector16x16.png')
      cmd.large_icon=File.join(File.dirname(__FILE__), 'TIGtools', 'extrudeEdgesByVector24x24.png')
      toolbar.add_item(cmd)
      menu.add_item(cmd)
    end
    if evo
      cmd=UI::Command.new('Extrude Edges by Vector to Object'){extrudeEdgesByVectorToObject()}
      cmd.tooltip=('Extrude Edges by Vector to Object')
      cmd.status_bar_text=('Extrude Edges by Vector to Object: Pre-Select Edges/Curves/Face, Pick Vector Start & End...')
      cmd.small_icon=File.join(File.dirname(__FILE__), 'TIGtools', 'extrudeEdgesByVectorToObject16x16.png')
      cmd.large_icon=File.join(File.dirname(__FILE__), 'TIGtools', 'extrudeEdgesByVectorToObject24x24.png')
      toolbar.add_item(cmd)
      menu.add_item(cmd)
    end
  end
  file_loaded(File.basename(__FILE__))
end#def

end#module
###
TIG.splitTOOLS()
###