# frozen_string_literal: true

Sketchup.require File.join D5Converter::D5RESOURCE_PATH, 'D5Localize'
Sketchup.require File.join D5Converter::D5RESOURCE_PATH, 'D5Message'
require 'fileutils'

module D5Config
  # 从配置文件中获取 d5安装路径
  def D5Config.d5_render_folder
    stringfile = File.join D5Converter::D5RESOURCE_PATH,"/d5_render_folder.strings"
    string =""
    if File.file?(stringfile)
      File.open(stringfile){|f|
        string = f.read
      }
    end
    return string
  end

  # 向配置文件写入 d5安装路径
  def D5Config.set_d5_render_folder input
    stringfile = File.join D5Converter::D5RESOURCE_PATH,"/d5_render_folder.strings"
    aFile = File.new(stringfile, "w+")
    if aFile
      aFile.syswrite(input)
    else
      #puts "Unable to open file!"
    end
  end

  # 从配置文件中获取贴图导出路径
  def D5Config.texture_folder
    string_file = File.join D5Converter::D5RESOURCE_PATH,"d5_texture_folder.strings"
    expired_string_file = File.join File.dirname(D5Converter::D5RESOURCE_PATH),"su_to_d5render","d5_expired.strings"
    folder_path =""
    # 从旧目录恢复配置文件
    if !File.file?(string_file) && File.file?(expired_string_file)
      D5Message::d5_puts "Copy 'd5_texture_folder.strings' from 'su_to_d5render'"
      FileUtils.copy expired_string_file, string_file
    end
    if File.file?(string_file)
      File.open(string_file){|f|
        folder_path = f.read
      }
    end

    # make sure dir valid
    if !folder_path.empty?
      begin
        FileUtils.makedirs(folder_path) unless File.exist? folder_path
      rescue
        # reset when fail
        unless File.exist? folder_path
          folder_path = ""
          self.set_texture_folder ""
          puts "Invalid texture folder, reset to default value."
        end
      end
    end

    return folder_path
  end

  #写入…
  def D5Config.set_texture_folder input
    string_file = File.join D5Converter::D5RESOURCE_PATH,"d5_texture_folder.strings"
    aFile = File.new(string_file, "w+")
    if aFile
      aFile.syswrite(input)
    else
      #puts "Unable to open file!"
    end
  end

  DEFAULT_CONFIG = "{ \"firstSync\": true, \"lightSyncMode\": \"xml\",\"LiveSyncOn\": true }"
  def D5Config.load_d5_config
    conf_file_path = File.join D5Converter::D5RESOURCE_PATH,"D5LiveSync.conf"
    expired_conf_file_path = File.join File.dirname(D5Converter::D5RESOURCE_PATH),"su_to_d5render","D5LiveSync.conf"
    config_content = ""
    # 从旧目录恢复配置文件
    if !File.file?(conf_file_path) && File.file?(expired_conf_file_path)
      D5Message::d5_puts "Copy 'D5LiveSync.conf' from 'su_to_d5render'"
      FileUtils.copy expired_conf_file_path, conf_file_path
    end
    if File.file?(conf_file_path)
        File.open(conf_file_path){|f|
            config_content = f.read
        }
    end
    if config_content.empty?
      config_content = DEFAULT_CONFIG
    end
    begin
      config = JSON.parse(config_content)
    rescue
      config = JSON.parse(DEFAULT_CONFIG)
    end
    config
  end

  def D5Config.load_d5_config_item(key,default_value = nil)
    config = D5Config.load_d5_config
    config[key].nil? ? default_value : config[key]
  end

  def D5Config.save_d5_config(config_content)
    conf_file_path = File.join D5Converter::D5RESOURCE_PATH,"D5LiveSync.conf"
    File.open(conf_file_path, "w"){|f|
      f.syswrite config_content
      #D5Message.d5_puts("Settings: Config is saved as \"#{config_content}\".")
    }
  end
  def D5Config.save_d5_config_item(key,value)
    config = D5Config.load_d5_config
    config[key] = value
    config_content = JSON.generate(config)
    D5Config.save_d5_config config_content
  end
  def D5Config.save_d5_config_items(key_value_map)
    config = D5Config.load_d5_config
    key_value_map.each{ |key,value| config[key] = value }
    config_content = JSON.generate(config)
    D5Config.save_d5_config config_content
  end
end
