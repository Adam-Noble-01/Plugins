# frozen_string_literal: true

module D5HelpCenter
  CN_HELP_CENTER_URL = 'https://docs.d5render.cn/db41/f410'
  GLOBAL_HELP_CENTER_URL = 'https://docs.d5render.com/d5-lite/lite-user-manual'
  DEFAULT_HELP_CENTER_URL = CN_HELP_CENTER_URL

  ENVIRONMENT_URLS = {
    0 => CN_HELP_CENTER_URL, # dev
    1 => CN_HELP_CENTER_URL, # test
    2 => CN_HELP_CENTER_URL, # pre
    3 => CN_HELP_CENTER_URL, # cn
    4 => GLOBAL_HELP_CENTER_URL, # usa
    5 => GLOBAL_HELP_CENTER_URL # stg
  }.freeze

  ENVIRONMENT_NAME_TO_ID = {
    'dev' => 0,
    'test' => 1,
    'pre' => 2,
    'cn' => 3,
    'usa' => 4,
    'stg' => 5
  }.freeze

  def self.help_center_url(environment = D5Converter::ENVIRONMENT)
    environment_id = normalize_environment(environment)
    url = ENVIRONMENT_URLS[environment_id]
    return url unless url.nil?

    warn_unknown_environment(environment)
    DEFAULT_HELP_CENTER_URL
  end

  def self.normalize_environment(environment)
    return environment if environment.is_a?(Integer)

    environment_name = environment.to_s.downcase
    return ENVIRONMENT_NAME_TO_ID[environment_name] if ENVIRONMENT_NAME_TO_ID.key?(environment_name)

    Integer(environment)
  rescue ArgumentError, TypeError
    nil
  end
  private_class_method :normalize_environment

  def self.warn_unknown_environment(environment)
    environment_name = environment_name(environment)
    message = "unknown Lite build environment for help center URL: #{environment_name}. use default URL."

    if defined?(D5Message) && D5Message.respond_to?(:d5_puts)
      D5Message.d5_puts(message, 1)
    else
      puts message
    end
  end
  private_class_method :warn_unknown_environment

  def self.environment_name(environment)
    environment_id = normalize_environment(environment)
    if defined?(D5Converter::ENV_STRING) &&
       D5Converter::ENV_STRING.respond_to?(:key?) &&
       D5Converter::ENV_STRING.key?(environment_id)
      return D5Converter::ENV_STRING[environment_id]
    end

    environment.inspect
  end
  private_class_method :environment_name
end
