#Eneroth Fog Tool

#Author: Julia Christina Eneroth, eneroth3@gmail.com

#Copyright Julia Christina Eneroth (eneroh3)

module Ene_Fog

class FogTool

  @@status_texts = [
    "Select fog start. Tab = Skip.",
    "Select fog end. Tab = Skip."
  ]
  @@labels = [
    "Distance from Camera",
    "Thickness"
  ]
    
  #Tool methods called by Sketchup
  
  def initialize
  
    @ip = Sketchup::InputPoint.new
    @step = 0
    
  end#def
  
  def activate
    
    view = Sketchup.active_model.active_view
    
    ss = Sketchup.active_model.selection
    ss.clear

    self.promt_enable_fog view
    self.reset! view
    
  end#def
  
  def enableVCB?
  
    true
    
  end#def
  
  def draw(view)
  
    @ip.draw view if @ip.valid?
  
  end#def
  
  def onMouseMove(flags, x, y, view)
  
    
    @ip.pick view, x, y
    ph = view.pick_helper
    
    ph.do_pick x, y
    entity = ph.best_picked
    ss = Sketchup.active_model.selection
    ss.clear
    if entity.class == Sketchup::SectionPlane
      #Outline hovered section plane by selecting it
      ss.add entity
      #Save point to @ip. @ip is used instead of separate @point or @distance variable to keep code cleaner
      #plane = entity.get_plane
      #plane = self.format_plane plane
      #@ip = Sketchup::InputPoint.new plane[0]
      #There's actually no point in saving position since it's already retained from the input point
    end
    point = @ip.position
    
    distance = self.distance_to_camera point
    
    #For step 1 fog thickness and not distance to camera is shown in VCB
    if @step == 1
      ro = view.model.rendering_options
      distance -= ro["FogStartDist"]
    end
    
    Sketchup.vcb_value = distance.to_l.to_s
    
    view.invalidate
  
  end#def
  
  def onLButtonDown(flags, x, y, view)
    
    point = @ip.position
    
    distance = self.distance_to_camera point
    self.set_distance distance, view
  
  end#def
  
  def onUserText(text, view)
  
    begin
      distance = text.to_l
    rescue
      UI.messagebox "#{text} could not be turned into a length."
      return
    end
    
    #For step 1 fog thickness and not distance to camera is entered 
    if @step == 1
      ro = Sketchup.active_model.rendering_options
      distance += ro["FogStartDist"]
    end
    
    self.set_distance distance, view
    
  end#def
  
  def onKeyUp(key, repeat, flags, view)
    #I think I've read somewhere that Mac doesn't call onKeyDown for tab.
  
    #A normal if could be used but of habit I make a case that would work for more keys.
    case key
    when 9#=tab
      #Toggle between steps
      @step = 1 - @step
      self.show_step
    end
  
  end#def
  
  def getMenu(menu)
  
    ro = Sketchup.active_model.rendering_options
    
    item = menu.add_item("Fog") { ro["DisplayFog"] = !ro["DisplayFog"] }
    menu.set_validation_proc(item) { ro["DisplayFog"] ? MF_CHECKED : MF_UNCHECKED}
    
    menu.add_item("Fog Window...") { UI.show_inspector "Fog" }
    
  end#def
  
  def resume(view)
  
    self.show_step
    
  end#def
  
  #Own methods called internally
  
  def reset!(view)
  
    @step = 0
    self.show_step
    view.invalidate
    
    true
  
  end#def
  
  def show_step
    #Update VCB label and status text for current step
  
    Sketchup.status_text = @@status_texts[@step]
    Sketchup.vcb_label = @@labels[@step]
    
    ro = Sketchup.active_model.rendering_options
    if @step == 0
      Sketchup.vcb_value = ro["FogStartDist"].to_l.to_s
    else
      Sketchup.vcb_value = (ro["FogEndDist"] - ro["FogStartDist"]).to_l.to_s
    end
    
    true
    
  end#def
  
  def promt_enable_fog(view)
    #Ask if user wants to enable fog if it isn't already enabled
  
    ro = view.model.rendering_options
    unless ro["DisplayFog"]
      ro["DisplayFog"] = UI.messagebox("Enable Fog?", MB_YESNO) == IDYES
    end
    
    true
    
  end#def
  
  def distance_to_camera(point, view = nil)
    #Get distance from point to camera plane
    
    view ||= Sketchup.active_model.active_view
    cam = view.camera
    cam_plane = [cam.eye, cam.target - cam.eye]
    
    point.distance_to_plane cam_plane
  
  end

  def format_plane(plane)
    #Some methods return a plane as a 4 float array.
    #This methods turns plane into a Point3d and a Vector3d.
    
    return plane if plane.length == 2
    
    x, y, z, d = plane
    vector = Geom::Vector3d.new(x, y, z)
    point = Geom::Point3d.new.offset(vector.reverse, d)
    
    [point, vector]
    
  end#def
  
  def set_distance(distance, view)
    #Set either fog start or fog end distance to camera depending on @stage
  
    ro = view.model.rendering_options
    
    #For just 2 steps an if-else would work fine but out of habit I make a case which also would work for multiple steps.
    case @step
    when 0
      #Set fog start distance 
      ro["FogStartDist"] = distance# if distance < ro["FogEndDist"]
      @step += 1
      self.show_step
    when 1
      #Set fog end distance
      ro["FogEndDist"] = distance
      self.promt_enable_fog view
      self.reset! view
    end
    
    true
    
  end#def
  
end#class

menu = UI.menu "Tools"
menu.add_item("Fog Tool"){ Sketchup.active_model.select_tool FogTool.new}

end#module