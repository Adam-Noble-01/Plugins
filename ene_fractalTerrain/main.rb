#Eneroth Fractal Terrain Eroder

module Ene_FractalTerrain

def self.find_vertex_normal(vertex)
  #Returns the average normal from faces bounded by vertex
  
  faces = []
  vertex.edges.each { |e| faces += e.faces }
  faces.uniq!
  normal = Geom::Vector3d.new
  faces.each { |f| normal += f.normal }

  normal

end#def

def self.find_vertex_edges_av_length(vertex)#NOTE: not in use
  #Returns the average length of edges bound by vertex
  
  l = 0
  vertex.edges.each { |e| l += e.length }
  l /= vertex.edges.length.to_f
  
  l.to_l  

end#def

def self.find_vertex_edges_shortest_length(vertex)
  #Returns the shortest length of edges bound by vertex
  
  vertex.edges.map { |e| e.length }.sort[0]

end#def

def self.fractalize_faces(polygons = [], iterations = nil, move_countours = false)

  #Get faces
  if polygons.empty?
    polygons = Sketchup.active_model.selection.select { |e| e.class == Sketchup::Face }
  end#unless
  if polygons.empty?
    UI.messagebox "No faces selected"
    return
  end

  #Get iterations
  unless iterations
    results = UI.inputbox ["Iterations", "Pointyness", "Move Contours"], [2, 0.5, "No"], [nil, nil, "Yes|No"], "Fractal Erode"
    return unless results
    iterations = results[0].to_i
    pointyness = results[1].to_f
    move_countours = results[2] == "Yes"
  end#unless
  return if iterations < 1
  iteration_warning = 4
  return if iterations > iteration_warning && UI.messagebox("More than #{iteration_warning.to_s} iterations may take a long time to process without adding much to the results.", MB_OKCANCEL) == 2
  
  Sketchup.active_model.start_operation "Erode"
  
  context = polygons[0].parent.entities
  
  #Backup original polygons
  backup_group = context.add_group polygons
  backup_layer = Sketchup.active_model.layers.add "Backuped terrain source"
  backup_layer.visible = false
  backup_group.layer = backup_layer
  
  #NOTE: BUG: if face(s) is inner loop of other face the hole will be lost and new entities will not connect
  
  #Create triangles from polygons
  triangles = []
  polygons.each do |p|
    mesh = p.mesh
    mesh.transform! backup_group.transformation
    
    #API docs error
    #This should work:
    #triangles += context.add_faces_from_mesh(mesh, 12, p.material, p.back_material)
    
    #But this has to be done instead:
    cache = context.to_a
    context.add_faces_from_mesh(mesh, 12, p.material, p.back_material)
    new_entities = context.to_a - cache
    triangles += new_entities.select { |e| e.class == Sketchup::Face }
  end#each
  
  #Split each triangle to 4 new by drawing lines between edges' midpoints
  #Move points
  #Repeat
  1.upto(iterations) do
  
    #List points to draw lines between.
    #Each element is an array of 3 points
    points_to_connect = []
    triangles.each do |t|
      points_to_connect << t.edges.map { |e| Geom::linear_combination 0.5, e.start.position, 0.5, e.end.position }
    end#each
    
    #Create new triangles
    triangles = []
    points_to_connect.each do |i|
      new_edges = context.add_edges(i + [i[0]])
      new_edges.each do |e|
        triangles += e.faces
         e.soft = e.smooth = true
      end#each
    end#each
    triangles.uniq!
    
    #Move vertices.
    vertices = triangles.map { |t| t.vertices }.flatten.compact.uniq
    vertices.each do |v|
       

      edges = v.edges
      next if edges.any? { |e| e.faces.size < 2 } && !move_countours
      faces = edges.map { |e| e.faces }.flatten.uniq
      next unless (faces - triangles).empty?
      
    
      vector = self.find_vertex_normal(v)
      vector.length = self.find_vertex_edges_shortest_length(v)*(0.5-rand)*pointyness
      trans = Geom::Transformation.translation(vector)
      context.transform_entities trans, [v]
      
    end#each
  
  end#each
  
  Sketchup.active_model.commit_operation
  Sketchup.active_model.selection.clear

end#def

#Menus and toolbars
file = File.basename(__FILE__)
unless file_loaded?(file)

  menu = UI.menu("Plugins")
  menu.add_item("Erode") { self.fractalize_faces }
  
end#unless

end#module