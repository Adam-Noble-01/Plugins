# frozen_string_literal: true

module D5Localize
  @info = {} # Hash.new
  @error = {} # Hash.new
  def self.info(key)
    value = @info[key]
    if value.nil?
      value = key #"default info"
    end
    return value
  end
  def self.error(key)
    value = @error[key]
    if value.nil?
      value = key #"default error"
    end
    return value
  end

  # error_code 0-6 represent SUCCESS,NOT_INSTALLED,NOT_OPEN,UNSUPPORTED_VERSION,RENDER_BUSY,USER_CANCEL,UNKNOWN_ERROR
  CONNECT_KEY=[
    "SUCCESS", # 0
    "NOT_INSTALLED",
    "NOT_OPEN",
    "UNSUPPORTED_VERSION",
    "RENDER_BUSY",
    "RENDER_BUSY_UPDATING",
    "USER_CANCEL",
    "UNKNOWN_ERROR",
    "NETWORK_ERROR"
  ]
  def self.connect_enum_to_key(enum)
    enum_range = 0..8 # include 8
    if enum_range.include?(enum)
      return CONNECT_KEY[enum]
    end
  end

  def self.local_file_to_hash(filename)
    string_file = File.join(D5Converter::D5RESOURCE_PATH, Sketchup.get_locale, filename)
    if !File.exist?(string_file)
      string_file = File.join(D5Converter::D5RESOURCE_PATH, "en-US", filename)# 未适配的语言环境下使用英文资源
    end
    if !File.exist?(string_file)
      UI.messagebox("Can't find localization strings for D5Render")
    end

    hash = Hash.new
    File.open(string_file) {|f|
      string = f.read # This returns a string even if the file is empty.
      string.gsub!(/\r\n?/, "\n")
      string.each_line do |line|
        line = line.gsub("\n","")
        key_value = line.split('==')
        hash[key_value[0]] = key_value[1]
      end
    }
    return hash
  end

  def self.init
    #从文件初始化string的key和value
    @info = self.local_file_to_hash("/D5Render.strings")
    #初始化要用到的报错string的值
    @error = self.local_file_to_hash("/D5ErrorText.strings")
  end
end