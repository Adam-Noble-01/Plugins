class D5NativeStubFunction
  def call(*_args)
    0
  end
end

if D5Platform.d5_render_supported?
module D5dllFunc
  # [Not Used]
  def self.release
    if !@dll_closed
      @lib_d5plugin.close
      @lib_progressbar.close
      GC.start # 立即垃圾回收
      @dll_closed = true
    end
  end

  # load D5Plugin.dll & ProgressBar.dll
  @lib_d5plugin = Fiddle.dlopen("D5Plugin.dll")
  @lib_progressbar = Fiddle.dlopen("ProgressBar.dll")
  @dll_closed = false

  #function in D5Plugin.dll

  MUTEX_OF_SEND = Mutex.new

  # D5EntityType
  ET_CAMERA = 0
  ET_LIGHT = 1
  ET_SCENE = 2
  ET_META = 3
  ET_ANIM_CAMERA = 4
  ET_SOLAR_POSITION = 5

  # void _CALL D5SetEntityIntProperty(void* session, D5EntityType type, const wchar_t* id, const wchar_t* name, int value);
  D5SetEntityIntProperty = Fiddle::Function.new(
    @lib_d5plugin['D5SetEntityIntProperty'],
    [Fiddle::TYPE_VOIDP,Fiddle::TYPE_INT,Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP,Fiddle::TYPE_INT],
    Fiddle::TYPE_VOID
  )
  D5SetEntityFloatProperty = Fiddle::Function.new(
    @lib_d5plugin['D5SetEntityFloatProperty'],
    [Fiddle::TYPE_VOIDP,Fiddle::TYPE_INT,Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP,Fiddle::TYPE_FLOAT],
    Fiddle::TYPE_VOID
  )
  D5SetEntityFloatArrayProperty = Fiddle::Function.new(
    @lib_d5plugin['D5SetEntityFloatArrayProperty'],
    [Fiddle::TYPE_VOIDP,Fiddle::TYPE_INT,Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP,Fiddle::TYPE_SIZE_T],
    Fiddle::TYPE_VOID
  )
  D5SetEntityStringProperty = Fiddle::Function.new(
    @lib_d5plugin['D5SetEntityStringProperty'],
    [Fiddle::TYPE_VOIDP,Fiddle::TYPE_INT,Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_VOID
  )
  D5ResetEntityProperty = Fiddle::Function.new(
    @lib_d5plugin['D5ResetEntityProperty'],
    [Fiddle::TYPE_VOIDP,Fiddle::TYPE_INT,Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_VOID
  )
  D5DeleteEntityProperty = Fiddle::Function.new(
    @lib_d5plugin['D5DeleteEntityProperty'],
    [Fiddle::TYPE_VOIDP,Fiddle::TYPE_INT,Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_VOID
  )

  D5AddLight = Fiddle::Function.new(
    @lib_d5plugin['D5AddLight'],
    [Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_VOID
  )
  D5DeleteLight = Fiddle::Function.new(
    @lib_d5plugin['D5DeleteLight'],
    [Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_VOID
  )
  D5ClearLights = Fiddle::Function.new(
    @lib_d5plugin['D5ClearLights'],
    [Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_VOID
  )
  D5AddMaterial  = Fiddle::Function.new(
    @lib_d5plugin['D5AddMaterial'],
    [Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_VOID
  )

  D5SetPathElementName = Fiddle::Function.new(
    @lib_d5plugin['D5SetPathElementName'],
    [Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_VOID
  )
  D5DeletePathElementName  = Fiddle::Function.new(
    @lib_d5plugin['D5DeletePathElementName'],
    [Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_VOID
  )
  D5ClearPathElementNames = Fiddle::Function.new(
    @lib_d5plugin['D5ClearPathElementNames'],
    [Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_VOID
  )

  D5SendMetaData = Fiddle::Function.new(
    @lib_d5plugin['D5SendMetaData'],
    [Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_VOID
  )
  D5GetMetaData = Fiddle::Function.new(
    @lib_d5plugin['D5GetMetaDataV2'],
    [Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP,Fiddle::TYPE_INT],
    Fiddle::TYPE_INT
  )
  D5SendCamera = Fiddle::Function.new(
    @lib_d5plugin['D5SendCamera'],
    [Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_VOID
  )
  D5SendSolarPosition = Fiddle::Function.new(
    @lib_d5plugin['D5SendSolarPosition'],
    [Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_VOID
  )
  D5SendScenesJson = Fiddle::Function.new(
    @lib_d5plugin['D5SendScenesJson'],
    [Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_VOID
  )
  D5SendScenes = Fiddle::Function.new(
    @lib_d5plugin['D5SendScenes'],
    [Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_VOID
  )
  D5SendScenesV3 = Fiddle::Function.new(
    @lib_d5plugin['D5SendScenesV3'],
    [Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_VOID
  )
  D5SendScenesJsonV3 = Fiddle::Function.new(
    @lib_d5plugin['D5SendScenesJsonV3'],
    [Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_VOID
  )
  D5SendLights = Fiddle::Function.new(
    @lib_d5plugin['D5SendLights'],
    [Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_VOID
  )

  D5BeginNode = Fiddle::Function.new(
    @lib_d5plugin['D5BeginNode'],
    [Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_VOID
  )
  D5BeginNodeHint = Fiddle::Function.new(
    @lib_d5plugin['D5BeginNodeHint'],
    [Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP,Fiddle::TYPE_SIZE_T,Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_VOID
  )
  D5EndNode = Fiddle::Function.new(
    @lib_d5plugin['D5EndNode'],
    [Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_VOID
  )
  D5DuplicateNode = Fiddle::Function.new(
    @lib_d5plugin['D5DuplicateNode'],
    [Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_VOID
  )
  D5DeleteNode = Fiddle::Function.new(
    @lib_d5plugin['D5DeleteNode'],
    [Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_VOID
  )


  SendLightsDataXml = Fiddle::Function.new(
    @lib_d5plugin['SendLightsDataXml'],
    [Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_VOID
  )

  Set_model_filepath = Fiddle::Function.new(
    @lib_d5plugin['SetModelFilePath'],
    [Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_VOID
  )

  Get_send_model_type = Fiddle::Function.new(
    @lib_d5plugin['GetSendModelType'],
    [Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_INT
  )

  Connect = Fiddle::Function.new(
    @lib_d5plugin['D5RawSyncConnect'],
    [Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_INT
  )
  D5SetDccPluginInfo = Fiddle::Function.new(
    @lib_d5plugin['D5SetDccPluginInfo'],
    [Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_VOID
  )


  StartLinkD5Render = Fiddle::Function.new(
    @lib_d5plugin['StartLinkD5Render'],
    [Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_INT
  )
  GetD5RenderStatus = Fiddle::Function.new(
    @lib_d5plugin['GetD5RenderStatus'],
    [Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_INT
  )
  DisConnect = Fiddle::Function.new(
    @lib_d5plugin['DisConnect'],
    [Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_VOID
  )


  # 0 represents false and 1 represents true
  Has_connected = Fiddle::Function.new(
    @lib_d5plugin['HasConnected'],
    [Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_INT
  )
  Create_model = Fiddle::Function.new(
    @lib_d5plugin['CreateSession'],
    [],
    Fiddle::TYPE_VOIDP
  )
  Set_texture_folder = Fiddle::Function.new(
    @lib_d5plugin['SetTextureFolder'],
    [Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_VOID
  )
  Add_material = Fiddle::Function.new(
    @lib_d5plugin['AddMaterial'],
    [Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_VOID
  )
  Start_send = Fiddle::Function.new(
    @lib_d5plugin['D5SendRaw'],# D5SendRaw D5SendOptimize D5SendGroup
    [Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_VOID
  )

  Add_Proxy_Model = Fiddle::Function.new(
    @lib_d5plugin['D5AddProxyModel'],
    [Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_VOID
  )

  Send_Proxy_Model = Fiddle::Function.new(
    @lib_d5plugin['D5SendProxyModel'],
    [Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_VOID
  )


  Save_to_file = Fiddle::Function.new(
    @lib_d5plugin['SaveToFile'],
    [Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_VOID
  )
  Destroy_model = Fiddle::Function.new(
    @lib_d5plugin['DestroySession'],
    [Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_VOID
  )
  # Deprecated
  Set_cameraTransformFov = Fiddle::Function.new(
    @lib_d5plugin['SendCameraTransformFov'],
    [Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP,Fiddle::TYPE_FLOAT],
    Fiddle::TYPE_VOID
  )
  # Deprecated
  Add_scenes = Fiddle::Function.new(
    @lib_d5plugin['AddScene'],
    [Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP,Fiddle::TYPE_FLOAT],
    Fiddle::TYPE_VOID
  )
  # Deprecated
  Start_sendScenes = Fiddle::Function.new(
    @lib_d5plugin['SendScenes'],
    [Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_VOID
  )
  Delete_node = Fiddle::Function.new(
    @lib_d5plugin['MaxDeleteNode'],
    [Fiddle::TYPE_VOIDP,Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_VOID
  )
  # 0 represents false and 1 represents true
  Set_d5render_path = Fiddle::Function.new(
    @lib_d5plugin['SetD5RenderPath'],
    [Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_INT
  )
  D5Render_windowSize = Fiddle::Function.new(
    @lib_d5plugin['D5RenderWindowSize'],
    [],
    Fiddle::TYPE_INT
  )
  D5GetRenderVersion = Fiddle::Function.new(
    @lib_d5plugin['D5GetRenderVersion'],
    [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
    Fiddle::TYPE_INT
  )
  D5GetCid = Fiddle::Function.new(
    @lib_d5plugin['D5GetCid'],
    [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
    Fiddle::TYPE_INT
  )
  D5IsUpdateAllowed = Fiddle::Function.new(
    @lib_d5plugin['D5IsUpdateAllowed'],
    [],
    Fiddle::TYPE_INT
  )

  #function in ProgressBar.dll
  Start_progress = Fiddle::Function.new(
    @lib_progressbar['startProgress'],
    [Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_INT
  )
  Update_progress = Fiddle::Function.new(
    @lib_progressbar['updateProgress'],
    [Fiddle::TYPE_INT,Fiddle::TYPE_INT,Fiddle::TYPE_VOIDP], #currentFaceNumber, totalFaceNumber,percentContent:60%
    Fiddle::TYPE_INT
  )
  End_progress = Fiddle::Function.new(
    @lib_progressbar['endProgress'],
    [],
    Fiddle::TYPE_INT
  )
end
else
module D5dllFunc
  MUTEX_OF_SEND = Mutex.new

  ET_CAMERA = 0
  ET_LIGHT = 1
  ET_SCENE = 2
  ET_META = 3
  ET_ANIM_CAMERA = 4
  ET_SOLAR_POSITION = 5

  def self.release; end

  def self.const_missing(name)
    const_set(name, D5NativeStubFunction.new)
  end
end
end

