module D5ProgressBar
  #this method is to convert the format of file path from "D:/a.text" to "D:\\a.text"
  def self.changePathFormat beforePath
    result_path = String.new
    for i in 0...(beforePath.length)
      if beforePath[i] == "/"
        result_path << "\\\\"
      else
        result_path << beforePath[i]
      end
    end
    return result_path
  end

  def self.adjust_progressBar_content(content)
    right_align_length = 44
    blank_length = right_align_length - content.length
    blank_str = " " * (blank_length > 0 ? blank_length : 0)
    (blank_str << content).encode("utf-16le")
  end

  def self.start
    input_jpg_path = File.join D5Converter::D5RESOURCE_PATH,"pictures/img_1.jpg"
    jpg_path = changePathFormat(input_jpg_path).to_s
    D5dllFunc::Start_progress.call(jpg_path.encode("utf-16le"))
    content = "0%"
    D5dllFunc::Update_progress.call(0,100,adjust_progressBar_content(content))
  end

  def self.update(current_percent, content = nil)
    content = current_percent.to_s << "%" if content.nil?
    D5dllFunc::Update_progress.call(current_percent,100,adjust_progressBar_content(content))
  end

  def self.end
    D5dllFunc::End_progress.call
  end
end

