#===============================================================================
# MODULE: Couch Co-op Configuration
#===============================================================================
# Manages couch co-op mode settings (enabled/disabled, input mode)
# Saves settings to couch_coop_settings.txt for persistence
#===============================================================================

module CouchCoopConfig
  SETTINGS_FILE = "couch_coop_settings.txt"

  @enabled = false
  @input_mode = "keyboard"  # "keyboard" or "controller"

  # Load settings from file
  def self.load_settings
    return unless File.exist?(SETTINGS_FILE)

    begin
      File.open(SETTINGS_FILE, "r") do |f|
        f.each_line do |line|
          line = line.strip
          next if line.empty? || line.start_with?("#")

          key, value = line.split(":", 2)
          next unless key && value

          case key.strip
          when "enabled"
            @enabled = (value.strip.downcase == "true")
          when "mode"
            mode = value.strip.downcase
            @input_mode = mode if ["keyboard", "controller"].include?(mode)
          end
        end
      end

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("COUCH-COOP", "Settings loaded: enabled=#{@enabled}, mode=#{@input_mode}")
      end
    rescue => e
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error("COUCH-COOP", "Error loading settings: #{e.message}")
      end
    end
  end

  # Save settings to file
  def self.save_settings
    begin
      File.open(SETTINGS_FILE, "w") do |f|
        f.puts "# Couch Co-op Mode Settings"
        f.puts "# Auto-generated - Do not edit manually unless you know what you're doing"
        f.puts "enabled:#{@enabled}"
        f.puts "mode:#{@input_mode}"
      end

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("COUCH-COOP", "Settings saved: enabled=#{@enabled}, mode=#{@input_mode}")
      end
    rescue => e
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error("COUCH-COOP", "Error saving settings: #{e.message}")
      end
    end
  end

  # Check if couch co-op mode is enabled
  def self.enabled?
    @enabled
  end

  # Get current input mode
  def self.input_mode
    @input_mode
  end

  # Enable couch co-op mode with specified input mode
  def self.enable(mode)
    mode = mode.to_s.downcase
    return false unless ["keyboard", "controller"].include?(mode)

    @enabled = true
    @input_mode = mode
    save_settings

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("COUCH-COOP", "Enabled with mode: #{mode}")
    end

    true
  end

  # Disable couch co-op mode
  def self.disable
    @enabled = false
    save_settings

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("COUCH-COOP", "Disabled")
    end

    true
  end
end

# Load settings on startup
CouchCoopConfig.load_settings

if defined?(MultiplayerDebug)
  MultiplayerDebug.info("COUCH-COOP-CONFIG", "=" * 60)
  MultiplayerDebug.info("COUCH-COOP-CONFIG", "Couch Co-op Config module loaded")
  MultiplayerDebug.info("COUCH-COOP-CONFIG", "Current status: #{CouchCoopConfig.enabled? ? 'Enabled' : 'Disabled'}")
  MultiplayerDebug.info("COUCH-COOP-CONFIG", "Current mode: #{CouchCoopConfig.input_mode}")
  MultiplayerDebug.info("COUCH-COOP-CONFIG", "=" * 60)
end
