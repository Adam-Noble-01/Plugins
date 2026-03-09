#
# Name: 	MeshWrapper and Gridding Extension
# Date :		1.0 02-08-2016
# Copyright (c) 2016 Cadman Inc. <cadman@livewirenet.com>
# Copyright (c) 2016 Mark Carvalho 
#
# Author :		Cadman Inc
# Usage/Desc:	Create a manifold volume Mesh Wrapped around an existing object.
#							Also Projects a Mesh upon an existing surface or object.
#							Includes a Seam Zipper tool that creates a mesh to fill a hole 
#							in a mesh or joining two mesh edges together		
#
=begin

Copyright © 2016 mark carvalho <markjcarvalho@gmail.com>, Cadman Inc.
Name: 	MeshWrapper and Gridding Extension
Date :	02-08-2016
Version: 1.0

   Ruby Script End User License Agreement

   This is a License Agreement is between you and Cadman Inc.

   If you download, acquire or purchase a Ruby Script or any freeware or any other
   product (collectively "Scripts") from Cadman Inc, then you hereby accept and
   agree to all of the following terms and conditions:

   Cadman Inc hereby
   grants you a permanent, worldwide, non-exclusive, non-transferable,
   non-sublicensable use license with respect to its rights in the Scripts.

   You may not alter, publish, market, distribute, give, transfer, sell or
   sublicense the Scripts or any part of the Scripts.

   All Scripts are provided "as is" and without any express or implied warranties,
   including, without limitation, the implied warranties of merchantability and
   fitness for a particular purpose.

   This License Agreement is governed by the laws of the State of Colorado and the
   United States of America.

   You agree to submit to the jurisdiction of the Courts in Denver, Colorado, 
   United States of America, to resolve any dispute, of any kind
   whatsoever, arising out of, involving or relating to this License Agreement.

=end
# See License.txt for details.

require "sketchup"

module CMSU
class CM_Grid

version = Sketchup.version.to_f
if version < 14
 	UI.messagebox("MeshWrapper tools only work with SketchUp 2014 and above.")
else

	ext_dir =
  	File.join(File.dirname(__FILE__), "Cadman_MeshWrapper")

	extension =
  	SketchupExtension.new("MeshWrapper", File.join(ext_dir, "main"))

	extension.version = 
 	 File.read(File.join(ext_dir, "version.txt")).strip
#  	"1.0"

	extension.creator =
  	"Cadman, Inc. Mark Carvalho"

	extension.copyright =
  	"2016 - Mark Carvalho"

# A sentence or even a paragraph would be appropriate here.
	extension.description =
  	"--\tCreate a manifold volume Mesh Wrapped around an existing object. " +
  	"Use in preparation for polygon decimation processing." +
#  	"\n--\tProject a Mesh upon an existing surface or object. " +
  	"\n--\tSeam Zipper tool that creates a mesh to fill a hole in " +
  	"a mesh or, joining two mesh edges together" +
		"\n--\tDraw a center line(s) by " +
  	"selecting three points for each vertex. Clicking the same point " +
  	"twice selects that point as the next vertex." +  	
  	"\n--\tSeveral mesh editing tools "

	Sketchup.register_extension(extension, true)

end #if

#end of modules
end
end
