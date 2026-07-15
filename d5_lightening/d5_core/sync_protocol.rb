# frozen_string_literal: true

class D5SyncProtocol
  VER_NORMAL = 0 # 用于D5区分实时与非实时插件
  VER_LIVE_SYNC = 1 # 用于D5区分实时与非实时插件
  PARAM_VALUES = ["","[M_Realtime]"] # todo: 设计是用方括号作为参数列表的格式：[Arg1,Arg2,...]。但客户端的参数解析尚未实现，所以非实时暂时为空。
  attr_accessor :ver
  def initialize
    @ver = VER_LIVE_SYNC
  end
  # So far the identifier consist of file_path and attached_param
  def model_file_identifier
    attached_params_str = "#{PARAM_VALUES[@ver]}"
    file_path = Sketchup.active_model.path
    file_path + attached_params_str
  end
end

module D5Conv
  SYNC_PROTOCOL = D5SyncProtocol.new
  SYNC_PROTOCOL.ver = D5SyncProtocol::VER_LIVE_SYNC # set VER_LIVE_SYNC in live-sync converter
end
