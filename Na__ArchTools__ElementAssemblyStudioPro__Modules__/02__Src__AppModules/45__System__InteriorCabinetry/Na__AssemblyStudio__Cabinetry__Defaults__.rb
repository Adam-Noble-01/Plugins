# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - INTERIOR CABINETRY SYSTEM - DEFAULTS
# =============================================================================
#
# FILE       : Na__AssemblyStudio__Cabinetry__Defaults__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__InteriorCabinetrySystem
# MODULE     : Na__Defaults
# AUTHOR     : Noble Architecture
# PURPOSE    : Every constant the cabinetry system shares: ACB ids, dictionary
#              keys, component naming, default materials, asset keys and the
#              default configuration (UK standard units).
# CREATED    : 29-Oct-2026
#
# DESCRIPTION:
# - NA_DEFAULT_CABINET_CONFIG mirrors the descriptor defaults in
#   Na__AssemblyStudio__Cabinetry__UiSystem__Config__.js. The CabinetLayout
#   spec reads both files and fails when they disagree.
# - UK standard sizes: base 720 on 150 legs x 560 deep, wall 720 x 300 deep
#   hung 1400 above the floor, tall 1970 on 150 legs x 560 deep, 600 wide.
#   Boards are 20mm (Adam's working scale); 18mm is one setting away.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

module Na__AssemblyStudio
module Na__InteriorCabinetrySystem
    module Na__Defaults

# -----------------------------------------------------------------------------
# REGION | ACB Cabinet Id System
# -----------------------------------------------------------------------------

        NA_CABINET_ID_PREFIX        = "ACB".freeze                               # <-- Assembly CaBinet (AWN windows, ADR doors)
        NA_CABINET_ID_REGEX_SOURCE  = '^ACB\d{3}$'.freeze
        NA_CABINET_ID_FORMAT        = "ACB%03d".freeze

        # Component name head: <ID>__<TypeTag>__ (fixed, machine read). The
        # optional user tail follows it (Na__ComponentNameSuffix).
        NA_TYPE_TAGS = {
            "Base"  => "BaseUnit",
            "Wall"  => "WallUnit",
            "Tower" => "TowerUnit"
        }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dictionary Keys
# -----------------------------------------------------------------------------

        NA_INFO_DICT                = "Na__CabinetConfiguratorInfo".freeze       # <-- On the ComponentInstance
        NA_KEY_CABINET_ID           = "CabinetID".freeze
        NA_DEF_DICT_PREFIX          = "Na__CabinetConfigurator_".freeze          # <-- On the ComponentDefinition, + id
        NA_KEY_METADATA             = "Na__CabinetMetadata".freeze
        NA_KEY_COMPONENTS           = "Na__CabinetComponents".freeze
        NA_KEY_CONFIGURATION        = "Na__CabinetConfiguration".freeze
        NA_CONFIG_KEY_PREFIX        = "Na__CabinetConfig__".freeze

        # SerializerBase contract (AppConfig attributeDictionaries
        # .interiorCabinetrySystem holds the same values). The definition
        # name suffix is empty: the type tag is written per unit by the
        # DataSerializer, so the head is <ID>__ for the fallback lookup.
        NA_SERIALIZER_CONFIG = {
            :instance_dict_name     => NA_INFO_DICT,
            :instance_id_attribute  => NA_KEY_CABINET_ID,
            :definition_dict_prefix => NA_DEF_DICT_PREFIX,
            :metadata_key           => NA_KEY_METADATA,
            :components_key         => NA_KEY_COMPONENTS,
            :configuration_key      => NA_KEY_CONFIGURATION,
            :id_regex               => NA_CABINET_ID_REGEX_SOURCE,
            :id_format              => NA_CABINET_ID_FORMAT,
            :definition_name_suffix => "__"
        }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Materials and Assets
# -----------------------------------------------------------------------------

        NA_DEFAULT_DOOR_MATERIAL_ID    = "MAT001__Default".freeze
        NA_DEFAULT_CARCASS_MATERIAL_ID = "MAT001__Default".freeze
        NA_DEFAULT_HANDLE_MATERIAL_ID  = "MAT615__Metal__Ironmongery__Chrome".freeze
        NA_DEFAULT_LEG_MATERIAL_ID     = "MAT304__Paint__FarrowAndBall__DownPipe".freeze  # <-- Dark charcoal, standing in for black plastic legs

        NA_DEFAULT_LEG_ASSET_KEY       = "Na__Cabinetry__Leg__Type-01__AdjustablePlinthLeg__h150mm".freeze
        NA_DEFAULT_HANDLE_ASSET_KEY    = "Na__Cabinetry__Handle__Type-01__BarHandle__cc128mm".freeze
        NA_NO_HANDLE_KEY               = "None".freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Default Cabinet Configuration (UK Standard)
# -----------------------------------------------------------------------------

        NA_DEFAULT_CABINET_CONFIGURATION = {
            "Na__CabinetConfig__UnitType"               => "Base",
            "Na__CabinetConfig__Width_mm"               => 600,
            "Na__CabinetConfig__BaseHeight_mm"          => 720,
            "Na__CabinetConfig__WallHeight_mm"          => 720,
            "Na__CabinetConfig__TowerHeight_mm"         => 1970,
            "Na__CabinetConfig__BaseDepth_mm"           => 560,
            "Na__CabinetConfig__WallDepth_mm"           => 300,
            "Na__CabinetConfig__TowerDepth_mm"          => 560,
            "Na__CabinetConfig__WallMountHeight_mm"     => 1400,
            "Na__CabinetConfig__DoorStyle"              => "Shaker",
            "Na__CabinetConfig__BaseFrontLayout"        => "Doors",
            "Na__CabinetConfig__WallFrontLayout"        => "Doors",
            "Na__CabinetConfig__TowerFrontLayout"       => "SplitDoors",
            "Na__CabinetConfig__DrawerCount"            => 3,
            "Na__CabinetConfig__HingeSide"              => "Left",
            "Na__CabinetConfig__DoorCount"              => "Auto",
            "Na__CabinetConfig__DrawerLayout"           => "Graduated",
            "Na__CabinetConfig__TopDrawerHeight_mm"     => 140,
            "Na__CabinetConfig__SplitUpperHeight_mm"    => 720,
            "Na__CabinetConfig__ShakerFrameWidth_mm"    => 70,
            "Na__CabinetConfig__GrooveOffset_mm"        => 22,
            "Na__CabinetConfig__DoorThickness_mm"       => 20,
            "Na__CabinetConfig__DoorGap_mm"             => 3,
            "Na__CabinetConfig__ShakerPanelRecess_mm"   => 6,
            "Na__CabinetConfig__GrooveWidth_mm"         => 18,
            "Na__CabinetConfig__GrooveDepth_mm"         => 12,
            "Na__CabinetConfig__BaseShelfCount"         => 1,
            "Na__CabinetConfig__WallShelfCount"         => 2,
            "Na__CabinetConfig__TowerInterior"          => "Shelves",
            "Na__CabinetConfig__TowerShelfCount"        => 4,
            "Na__CabinetConfig__HatShelfDrop_mm"        => 300,
            "Na__CabinetConfig__ShelfSetback_mm"        => 20,
            "Na__CabinetConfig__RailDropBelowShelf_mm"  => 60,
            "Na__CabinetConfig__BaseTopConstruction"    => "Rails",
            "Na__CabinetConfig__TopRailDepth_mm"        => 100,
            "Na__CabinetConfig__BackPanelThickness_mm"  => 9,
            "Na__CabinetConfig__BoardThickness_mm"      => 20,
            "Na__CabinetConfig__BackPanelInset_mm"      => 20,   # <-- The scribe: sides stand 20 proud of the back panel
            "Na__CabinetConfig__PlinthHeight_mm"        => 150,
            "Na__CabinetConfig__PlinthEnabled"          => true,
            "Na__CabinetConfig__PlinthSetback_mm"       => 40,
            "Na__CabinetConfig__LegsEnabled"            => true,
            "Na__CabinetConfig__LegAssetKey"            => NA_DEFAULT_LEG_ASSET_KEY,
            "Na__CabinetConfig__PlinthThickness_mm"     => 20,
            "Na__CabinetConfig__PlinthMatchesDoors"     => true,
            "Na__CabinetConfig__LegSideInset_mm"        => 50,
            "Na__CabinetConfig__LegBackInset_mm"        => 65,
            "Na__CabinetConfig__HandleAssetKey"         => NA_DEFAULT_HANDLE_ASSET_KEY,
            "Na__CabinetConfig__HandleMaterialId"       => NA_DEFAULT_HANDLE_MATERIAL_ID,
            "Na__CabinetConfig__HandleOrientation"      => "Auto",
            "Na__CabinetConfig__HandleEdgeInset_mm"     => 40,
            "Na__CabinetConfig__HandleEndInset_mm"      => 60,
            "Na__CabinetConfig__DoorMaterialId"         => NA_DEFAULT_DOOR_MATERIAL_ID,
            "Na__CabinetConfig__CarcassMaterialId"      => NA_DEFAULT_CARCASS_MATERIAL_ID,
            "Na__CabinetConfig__DrawerBoxesEnabled"     => true,
            "Na__CabinetConfig__LegMaterialId"          => NA_DEFAULT_LEG_MATERIAL_ID   # <-- Not shown in the dialog
        }.freeze

        NA_DEFAULT_CABINET_CONFIG = {
            NA_KEY_METADATA => [
                {
                    "Na__Cabinet__UniqueId"     => nil,
                    "Na__Cabinet__Name"         => "New Cabinet",
                    "Na__Cabinet__Description"  => "",
                    "Na__Cabinet__Notes"        => "Created with Element Assembly Studio Pro",
                    "Na__Cabinet__CreatedDate"  => nil,
                    "Na__Cabinet__LastModified" => nil
                }
            ],
            NA_KEY_COMPONENTS    => [],
            NA_KEY_CONFIGURATION => NA_DEFAULT_CABINET_CONFIGURATION
        }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | A Deep Copy of the Default Root Configuration
        # ------------------------------------------------------------
        def self.na_default_config
            Marshal.load(Marshal.dump(NA_DEFAULT_CABINET_CONFIG))
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Default of One Configuration Key (Short or Full Name)
        # ------------------------------------------------------------
        # @param key [String] "Width_mm" or "Na__CabinetConfig__Width_mm"
        def self.na_default_of(key)
            full = key.to_s.start_with?(NA_CONFIG_KEY_PREFIX) ? key.to_s : "#{NA_CONFIG_KEY_PREFIX}#{key}"
            NA_DEFAULT_CABINET_CONFIGURATION[full]
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Name Head for a Unit Type: "ACB001__BaseUnit__"
        # ------------------------------------------------------------
        def self.na_name_head(cabinet_id, unit_type)
            tag = NA_TYPE_TAGS[unit_type.to_s] || NA_TYPE_TAGS["Base"]
            "#{cabinet_id}__#{tag}__"
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__Defaults
end # module Na__InteriorCabinetrySystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
