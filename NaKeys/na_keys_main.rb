# Plugins/NaKeys/na_keys_main.rb  (Main)
# Complete, self-contained implementation. Independent ON/OFF toggles.
# Tested for clean load at startup (Ruby 3.x in SketchUp 2025).

require 'sketchup.rb'
require 'set'

module NaKeys
  MENU_NAME     = 'NaKeys'
  STATES_DICT   = 'NaKeys__ToggleStates'   # Stores simple boolean per toggle id
  REQUIRED_TAGS = ['06__Drawings', '05__Mirror'].freeze

  Toggle = Struct.new(:id, :tag_names, :tag_prefixes, :entity_prefixes)

  TOGGLES = [
    Toggle.new('NaKeys__ToggleDrawings',               ['06__Drawings'], [],        ['06__']),
    Toggle.new('NaKeys__ToggleMirrorPlanes',           ['05__Mirror'],   [],        ['05__Mirror__']),
    Toggle.new('NaKeys__ToggleExistingBuildingElements', [],             ['10__'], ['10__']),
    Toggle.new('NaKeys__ToggleValeGardenHouseElments',   [],             ['20__'], ['20__'])
  ].freeze

  # --------------------------------------------------------------------------
  # Public commands (bind these in Preferences → Shortcuts)
  # --------------------------------------------------------------------------
  def self.Na__KeyBindings__Toggle__Drawings
    toggle_by_id('NaKeys__ToggleDrawings')
  end

  def self.Na__KeyBindings__Toggle__MirrorPlanes
    toggle_by_id('NaKeys__ToggleMirrorPlanes')
  end

  def self.Na__KeyBindings__Toggle__ExistingBuildingElements
    toggle_by_id('NaKeys__ToggleExistingBuildingElements')
  end

  def self.Na__KeyBindings__Toggle__ValeGardenHouseElments
    toggle_by_id('NaKeys__ToggleValeGardenHouseElments')
  end

  def self.Na__KeyBindings__Toggle__DoorPositions
    toggle_door_positions
  end

  def self.Na__KeyBindings__Toggle__TransparencyScene
    toggle_transparency_scene
  end

  # --------------------------------------------------------------------------
  # Core toggle engine
  # --------------------------------------------------------------------------
  def self.toggle_by_id(command_id)
    model = Sketchup.active_model
    cfg   = TOGGLES.find { |t| t.id == command_id }
    return unless model && cfg

    model.start_operation("NaKeys Toggle #{command_id}", true)
    begin
      is_on   = !!model.get_attribute(STATES_DICT, command_id, false)
      targets = compute_targets(model, cfg)

      if is_on
        # Turning OFF: only hide items no other active toggle currently claims
        claims = active_claims(model, exclude_id: command_id)

        targets[:layers].each_value do |layer|
          next unless layer.valid?
          next if claims[:layer_ids].include?(layer.object_id)
          layer.visible = false
        end

        targets[:entities].each_value do |inst|
          next unless inst.valid?
          next if claims[:entity_ids].include?(inst.object_id)
          inst.hidden = true
        end

        # Folders are left as-is on OFF to avoid collateral hiding
        model.set_attribute(STATES_DICT, command_id, false)
      else
        # Turning ON: ensure folders, layers, and instances are shown
        targets[:folders].each_value { |folder| folder.visible = true if folder.valid? }
        targets[:layers].each_value  { |layer|  layer.visible  = true if layer.valid? }
        targets[:entities].each_value { |inst|  inst.hidden    = false if inst.valid? }

        model.set_attribute(STATES_DICT, command_id, true)
      end

      UI.refresh_inspectors
    ensure
      model.commit_operation
    end
  end

  # --------------------------------------------------------------------------
  # Door position sequential toggle
  # --------------------------------------------------------------------------
  def self.toggle_door_positions
    model = Sketchup.active_model
    return unless model

    model.start_operation("NaKeys Toggle Door Positions", true)
    begin
      # Get current door state (0 = closed, 1 = open)
      current_state = model.get_attribute(STATES_DICT, 'DoorPositions_State', 0)
      new_state = current_state == 0 ? 1 : 0

      layers = model.layers
      open_layer = layers['08__Doors__OpenPosition']
      closed_layer = layers['09__Doors__ClosedPosition']

      # Ensure layers exist
      open_layer = layers.add('08__Doors__OpenPosition') unless open_layer
      closed_layer = layers.add('09__Doors__ClosedPosition') unless closed_layer

      if new_state == 1
        # State 1: Open ON, Closed OFF
        open_layer.visible = true if open_layer.valid?
        closed_layer.visible = false if closed_layer.valid?
      else
        # State 0: Open OFF, Closed ON  
        open_layer.visible = false if open_layer.valid?
        closed_layer.visible = true if closed_layer.valid?
      end

      # Store the new state
      model.set_attribute(STATES_DICT, 'DoorPositions_State', new_state)

      UI.refresh_inspectors
    ensure
      model.commit_operation
    end
  end

  # --------------------------------------------------------------------------
  # Transparency scene toggle
  # --------------------------------------------------------------------------
  def self.toggle_transparency_scene
    model = Sketchup.active_model
    return unless model

    model.start_operation("NaKeys Toggle Transparency Scene", true)
    begin
      scene = model.pages['UT__Transparency']
      if scene
        model.pages.selected_page = scene
      end
      
      UI.refresh_inspectors
    ensure
      model.commit_operation
    end
  end

  # --------------------------------------------------------------------------
  # Target resolution and active-claim calculation
  # --------------------------------------------------------------------------
  def self.compute_targets(model, cfg)
    layers          = model.layers
    layers_by_id    = {}
    entities_by_id  = {}
    folders_by_id   = {}

    # Exact tag names
    cfg.tag_names.each do |name|
      layer = layers[name]
      next unless layer && layer.valid?
      layers_by_id[layer.object_id] = layer
      collect_parent_folders(layer, folders_by_id)
    end

    # Tag name prefixes
    layers.each do |layer|
      lname = layer.name.to_s
      next unless cfg.tag_prefixes.any? { |p| lname.start_with?(p) }
      next unless layer.valid?
      layers_by_id[layer.object_id] = layer
      collect_parent_folders(layer, folders_by_id)
    end

    # Entities by instance-name prefix (Groups and ComponentInstances)
    each_instance_recursive(model.entities) do |inst|
      iname = inst.name.to_s
      next unless cfg.entity_prefixes.any? { |p| iname.start_with?(p) }
      next unless inst.valid?

      entities_by_id[inst.object_id] = inst

      # Include the instance's tag
      layer = inst.layer
      if layer && layer.valid?
        layers_by_id[layer.object_id] = layer
        collect_parent_folders(layer, folders_by_id)
      end
    end

    { layers: layers_by_id, entities: entities_by_id, folders: folders_by_id }
  end

  def self.active_claims(model, exclude_id:)
    layer_ids  = Set.new
    entity_ids = Set.new
    folder_ids = Set.new

    dict = model.attribute_dictionary(STATES_DICT, false)
    return { layer_ids: layer_ids, entity_ids: entity_ids, folder_ids: folder_ids } unless dict

    TOGGLES.each do |t|
      next if t.id == exclude_id
      next unless !!dict[t.id]
      targets = compute_targets(model, t)
      layer_ids.merge(targets[:layers].keys)
      entity_ids.merge(targets[:entities].keys)
      folder_ids.merge(targets[:folders].keys)
    end

    { layer_ids: layer_ids, entity_ids: entity_ids, folder_ids: folder_ids }
  end

  # --------------------------------------------------------------------------
  # Helpers
  # --------------------------------------------------------------------------
  def self.each_instance_recursive(entities, &block)
    entities.grep(Sketchup::Group).each do |g|
      yield g
      each_instance_recursive(g.entities, &block)
    end
    entities.grep(Sketchup::ComponentInstance).each do |ci|
      yield ci
      each_instance_recursive(ci.definition.entities, &block)
    end
  end

  def self.collect_parent_folders(layer, folders_by_id)
    folder = layer.folder
    while folder && folder.valid?
      folders_by_id[folder.object_id] = folder
      folder = folder.folder
    end
  end

  # --------------------------------------------------------------------------
  # Startup wiring
  # --------------------------------------------------------------------------
  def self.ensure_required_tags(model)
    layers = model.layers
    REQUIRED_TAGS.each { |name| layers.add(name) unless layers[name] }
  end

  def self.install_menu_and_commands
    return if @menu_installed
    menu = UI.menu('Plugins').add_submenu(MENU_NAME)

    menu.add_item(UI::Command.new('NaKeys__ToggleDrawings')               { NaKeys.Na__KeyBindings__Toggle__Drawings })
    menu.add_item(UI::Command.new('NaKeys__ToggleMirrorPlanes')           { NaKeys.Na__KeyBindings__Toggle__MirrorPlanes })
    menu.add_item(UI::Command.new('NaKeys__ToggleExistingBuildingElements'){ NaKeys.Na__KeyBindings__Toggle__ExistingBuildingElements })
    menu.add_item(UI::Command.new('NaKeys__ToggleValeGardenHouseElments') { NaKeys.Na__KeyBindings__Toggle__ValeGardenHouseElments })
    menu.add_item(UI::Command.new('NaKeys__ToggleDoorPositions')          { NaKeys.Na__KeyBindings__Toggle__DoorPositions })
    menu.add_item(UI::Command.new('NaKeys__ToggleTransparencyScene')      { NaKeys.Na__KeyBindings__Toggle__TransparencyScene })

    @menu_installed = true
  end

  def self.activate_for_model(model)
    ensure_required_tags(model)
    install_menu_and_commands
  end

  unless file_loaded?(__FILE__)
    # Activate immediately for the current model
    activate_for_model(Sketchup.active_model)

    # Keep behaviour consistent for future models opened/created this session
    class AppHook < Sketchup::AppObserver
      def onNewModel(model)
        NaKeys.activate_for_model(model)
      end
      def onOpenModel(model)
        NaKeys.activate_for_model(model)
      end
    end
    Sketchup.add_observer(AppHook.new)

    file_loaded(__FILE__)
  end
end
