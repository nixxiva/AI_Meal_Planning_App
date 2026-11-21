abort "Isolated test boot requires RAILS_ENV=test" unless ENV["RAILS_ENV"] == "test"

require "active_support"
require "active_support/encrypted_file"
require "fileutils"
require "net/http"
require "securerandom"
require "tmpdir"
require "yaml"

directory = Dir.mktmpdir("meal-planner-credentials.")
owner_pid = Process.pid
at_exit { FileUtils.remove_entry_secure(directory) if Process.pid == owner_pid }

credentials_path = File.join(directory, "credentials.yml.enc")
key_path = File.join(directory, "unused.key")
ENV["RAILS_MASTER_KEY"] = ActiveSupport::EncryptedFile.generate_key
ENV["SECRET_KEY_BASE"] = SecureRandom.hex(64)
credentials = ActiveSupport::EncryptedFile.new(content_path: credentials_path,
  key_path: key_path, env_key: "RAILS_MASTER_KEY", raise_if_missing_key: true)
credentials.write({ "devise_jwt_secret_key" => SecureRandom.hex(64),
  "nutritionix" => { "app_id" => "isolated", "app_key" => "isolated" },
  "openai" => { "api_key" => "isolated" } }.to_yaml)

Net::HTTP.prepend(Module.new do
  def connect
    raise "External HTTP is disabled in isolated tests; stub the provider"
  end
end)

require_relative "../../config/application"
Rails.application.config.credentials.content_path = credentials_path
Rails.application.config.credentials.key_path = key_path
Rails.application.config.active_record.dump_schema_after_migration = false
