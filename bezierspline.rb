=begin
#------------------------------------------------------------------------------------------------------------
#************************************************************************************************************
#  © 2007-2017 - Designed as of December 2007 by Fredo6

# Permission to use this software for any purpose and without fee is hereby granted
# Distribution of this software for any purpose is subject to:
#  - the expressed, written consent of the author
#  - the inclusion of the present copyright notice in all copies.

# THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
#-----------------------------------------------------------------------------
# Name			:  bezierspline.rb
# Original Date	:  10 Dec 2007
# Description	:  A tool to create and edit Bezier, Cubic Bezier, Polyline and other mathematical curves.
#------------------------------------------------------------------------------------------------------------
#************************************************************************************************************
=end

require 'sketchup.rb' 
require 'extensions.rb' 

module Bezierspline

@@name = "BezierSpline"
@@version = "2.2a"
folder = "bezierspline"
@@sdate = "22 Apr 21"
@@creator = "Fredo6"

file__ = __FILE__
file__ = file__.force_encoding("UTF-8") if defined?(Encoding)
file__ = file__.gsub(/\\/, '/')

path = File.join(File.dirname(file__), folder, "bezierspline_main.rb") 
if Sketchup.get_locale == "FR"
	@@description = "Courbes de Bezier et Splines" 
else
	@@description = "Bezier and Splines Curves" 
end	
ext = SketchupExtension.new("BezierSpline", path) 
ext.creator = @@creator 
ext.version = @@version + " - " + @@sdate 
ext.copyright = "Fredo6 - © 2007-2021" 
ext.description = @@description
Sketchup.register_extension ext, true

def Bezierspline.get_name ; @@name ; end
def Bezierspline.get_date ; @@sdate ; end
def Bezierspline.get_version ; @@version ; end

def Bezierspline.register_plugin_for_LibFredo6 
	{	
		:name => @@name,
		:author => @@creator,
		:version => @@version,
		:date => @@sdate,	
		:description => @@description,
		:link_info => "http://sketchucation.com/forums/viewtopic.php?f=323&t=13563#p100509"
	}
end

end #Module Bezierspline


