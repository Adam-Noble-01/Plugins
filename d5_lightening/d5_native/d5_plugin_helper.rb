module D5dllFuncHelper
  def self.get_render_version
    version_str = "".ljust(32,"0")
    version_str.encode! "utf-16le"
    version_length = D5dllFunc::D5GetRenderVersion.call(version_str,32) # version_length包含字符串截止符
    version_str.encode! "utf-8"
    version_length > 0 ? version_str.slice(0...(version_length-1)) : ""
  end

  def self.get_cid
    cid_str = ""
    cid_length = D5dllFunc::D5GetCid.call(cid_str,0) # version_length包含字符串截止符
    cid_str = "".ljust(cid_length,"0")
    D5dllFunc::D5GetCid.call(cid_str,cid_length) # version_length包含字符串截止符
    cid_length > 0 ? cid_str.slice(0...(cid_length-1)) : ""
  end

  # @return String. Can be empty when failed to get metadata.
  def self.get_model_metadata(model)
    # 获取Actor上一次联动版本信息 metadata["dccPluginInfo"]
    json_str_length = D5dllFunc::D5GetMetaData.call(model, 0, 0)
    d5data_json_str = "".ljust(json_str_length, " ")
    d5data_json_str.encode! "utf-16le"
    D5dllFunc::D5GetMetaData.call(model, d5data_json_str, json_str_length)
    d5data_json_str.encode! "utf-8"
    d5data_json_str.slice!(-1) # 最后一位是字符串截止符，需删掉

    metadata_json_str = ""
    if !d5data_json_str.empty?
      d5data_json = JSON.parse d5data_json_str
      metadata_json_str = d5data_json["metadata"] if d5data_json.is_a?(Hash)
      metadata_json_str = "" if !metadata_json_str.is_a?(String)
    end
    metadata_json_str
  end

  # @return String. Can be empty when no info.
  def self.get_model_dcc_plugin_info(model)
    metadata_json_str = get_model_metadata model
    dcc_plugin_info = ""
    if !metadata_json_str.empty?
      metadata_json = JSON.parse metadata_json_str
      dcc_plugin_info = metadata_json["dccPluginInfo"]  if metadata_json.is_a?(Hash) # can be nil
      dcc_plugin_info = "" if !dcc_plugin_info.is_a?(String)
    end
    dcc_plugin_info
  end

  # @return Hash:{"dcc"=>"","ver"=>"","env"=>"" }
  def self.parse_dcc_plugin_info(dcc_plugin_info)
    infos = dcc_plugin_info.split('-')
    if infos.count >= 3
      {"dcc"=>infos[0],"ver"=>infos[1],"env"=>infos[2] }
    else
      {"dcc"=>"","ver"=>"","env"=>"" }
    end
  end

  # @return String. Can be empty when no info.
  def self.get_model_dcc_data_version(model)
    metadata_json_str = get_model_metadata model
    if !metadata_json_str.empty?
      metadata_json = JSON.parse metadata_json_str
      metadata_json["dccDataVer"]  if metadata_json.is_a?(Hash) # can be nil
    else
      nil
    end
  end
end

