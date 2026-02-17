module CURIC
  class << self
    attr_accessor :check_ruby_encoder_loaded
  end
  # @check_ruby_encoder_loaded = false

  module RubyEncoderHelper
    def self.show
      @dialog.close if @dialog && @dialog.visible?
      @dialog = UI::HtmlDialog.new(
        {
          :dialog_title => "Curic Load Error - Missing RubyEncoder",
          :scrollable => true,
          :resizable => true,
          :width => 600,
          :height => 800,
          :min_width => 500,
          :min_height => 700
        })

      html = <<-HTML
      <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>RubyEncoder Loader Instructions</title>
        <style>
          body {
            font-family: Arial, sans-serif;
            margin: 20px;
            padding: 0;
            background-color: #f4f4f4;
          }
          .container {
            background-color: #fff;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
          }
          h2, h3 {
            color: #333;
          }
          p, a {
            color: #666;
            text-decoration: none;
          }
          .instruction, .button {
            background-color: #eee;
            padding: 10px;
            border-left: 3px solid #007BFF;
            margin: 20px 0;
          }
          .button {
            display: flex;
            justify-content: space-around;
          }

          .button a {
            display: inline-block;
            background-color: #007BFF;
            color: #fff;
            padding: 10px 20px;
            border-radius: 5px;
            transition: background-color 0.3s;
          }
          .button a:hover {
            background-color: #0056b3;
          }
          .img-wrap {
            text-align: center;
            margin-top: 20px;
          }
          img {
            max-width: 100%;
            height: auto;
          }
        </style>
        </head>
        <body>
        <div class="container">
          <h2>Welcome to Curic Plugins</h2>
          <p>To ensure the security and integrity of our software, Curic plugins utilize RubyEncoder technology. RubyEncoder helps to protect and encrypt our Ruby code, ensuring that the plugins you use are safe and genuine. Please follow the instructions below if you encounter any loading issues.</p>

          <h3>Important Notice for Plugin Users</h3>
          <p>If you are encountering issues loading our SketchUp plugin, it might be due to the RubyEncoder not being properly loaded. Please follow the instructions below to resolve the issue.</p>

          <div class="instruction">
            <h3>General Instructions</h3>
            <p>Make sure the RubyEncoder loader (RGLoader) is present in the expected directory. If missing, reinstall the plugin to ensure all components are correctly installed.</p>
          </div>

          <div class="instruction" id="mac-instructions">
            <h3>Instructions for macOS Users</h3>
            <p>To grant the necessary permissions for the RubyEncoder loader on macOS, please follow these steps:</p>
            <ol>
              <li>Open Settings and go to Security & Privacy.</li>
              <li>Scroll down to the Security section. You will see a message like: "rgloader32.darwin bundle was blocked from use because it is not from an identified developer."</li>
              <li>Click on "Allow Anyway," and you may be prompted to enter your password.</li>
              <li>After granting permission, you might need to restart SketchUp for the changes to take effect.</li>
            </ol>
            <p>Please refer to the screenshots below for a visual guide through the process:</p>

            <!-- Example place for images, replace src with your actual screenshot paths -->
            <div class="img-wrap">
              <img src="https://curic.io/su_plugins/resources/rubyencoder_load_error1.png" alt="Security & Privacy Settings">
              <img src="https://curic.io/su_plugins/resources/rubyencoder_load_error2.png" alt="Adding RubyEncoder Loader">
            </div>

            <p>After restart SketchUp, if you see a prompt saying "rgloader32.darwin.bundle" cannot be opened because Apple cannot check it for malicious software, click on "Open" to proceed.</p>

            <div class="img-wrap">
              <img src="https://curic.io/su_plugins/resources/rubyencoder_load_error3.png" alt="Open Loader">
            </div>
          </div>

          <div class="button">
            <a href="https://curic.io" target="_blank">Visit Curic Home</a>
            <a href="mailto:curic4su@gmail.com" target="_blank">Support</a>
          </div>

          <p>Note: The name "rgloader32" may vary depending on the version of SketchUp you are using. You only need to grant permission once.</p>
          <p>If you've followed these steps and are still experiencing issues, please contact our support team for further assistance.</p>
        </div>
        </body>
        </html>
      HTML

      @dialog.add_action_callback("action") do
        #
      end

      @dialog.set_html(html)
      @dialog.center
      @dialog.show
    end
  end

  unless file_loaded?(__FILE__)
    UI.start_timer(10, false) do
      next if @check_ruby_encoder_loaded

      RubyEncoderHelper.show unless defined?(RGLoader)

      @check_ruby_encoder_loaded = true
    end
    file_loaded(__FILE__)
  end
end
