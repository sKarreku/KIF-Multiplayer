# ===========================================
# File: 003_UI_Connect.rb
# Purpose: Add "Multiplayer" button under 'KIF Settings'
# Server settings validation before saving.
# ===========================================

##MultiplayerDebug.info("UI-000", "UI module loaded successfully.")

module MultiplayerUI
  SETTINGS_FILE   = "multiplayer_settings.txt"
  DEFAULT_PORT    = 12975
  DEFAULT_IP      = ""   # No default - user must configure VPN IP

  @server_ip       = DEFAULT_IP
  @server_port     = DEFAULT_PORT
  @settings_loaded = false

  # ===========================================
  # === Load saved settings
  # ===========================================
  def self.load_settings
    return if @settings_loaded
    if File.exist?(SETTINGS_FILE)
      begin
        data = File.read(SETTINGS_FILE).strip.split(":")
        @server_ip   = data[0] if data[0] && !data[0].empty?
        @server_port = data[1].to_i if data[1]
        ##MultiplayerDebug.info("UI-001", "Loaded settings: #{@server_ip}:#{@server_port}")
      rescue => e
        ##MultiplayerDebug.error("UI-002", "Failed to read settings: #{e.message}")
      end
    else
      ##MultiplayerDebug.warn("UI-003", "No multiplayer_settings.txt found; using defaults.")
    end
    @settings_loaded = true
  end

  # ===========================================
  # === Validate if server is reachable
  # ===========================================
    def self.server_reachable?(ip, port)
    begin
        socket = TCPSocket.new(ip, port)
        socket.puts("PING")
        socket.flush

        start_time = Time.now
        reply = nil

        # Wait up to 2 seconds total for any reply containing PONG
        while (Time.now - start_time) < 2.0
        if IO.select([socket], nil, nil, 0.2)
            chunk = socket.gets
            if chunk
            ##MultiplayerDebug.info("UI-004A", "Ping reply received: #{chunk.strip}")
            if chunk.include?("PONG")
                reply = "PONG"
                break
            end
            end
        end
        end

        socket.close

        if reply == "PONG"
        ##MultiplayerDebug.info("UI-004", "Server responded correctly to PING at #{ip}:#{port}")
        return true
        else
        ##MultiplayerDebug.warn("UI-005", "Server did not respond with PONG.")
        return false
        end
    rescue => e
        ##MultiplayerDebug.warn("UI-007", "Ping failed: #{e.message}")
        return false
    end
    end




  # ===========================================
  # === Save settings (only after check)
  # ===========================================
  def self.save_settings(ip, port)
    begin
      File.open(SETTINGS_FILE, "w") { |f| f.puts("#{ip}:#{port}") }
      ##MultiplayerDebug.info("UI-006", "Saved settings: #{ip}:#{port}")
    rescue => e
      ##MultiplayerDebug.error("UI-007", "Failed to write settings: #{e.message}")
    end
  end

  # ===========================================
  # === Hook: Add Multiplayer under KIF Settings
  # ===========================================
  if defined?(PokemonOption_Scene)
    class ::PokemonOption_Scene
      alias old_pbGetOptions_multiplayer pbGetOptions unless method_defined?(:old_pbGetOptions_multiplayer)

      def pbGetOptions(inloadscreen = false)
        options = old_pbGetOptions_multiplayer(inloadscreen)
        begin
          exists = options.any? { |opt| opt.respond_to?(:name) && opt.name == _INTL("Multiplayer") }
          unless exists
            # find "KIF Settings" index
            kif_index = options.index { |opt| opt.respond_to?(:name) && opt.name == _INTL("KIF Settings") }
            insert_pos = kif_index ? kif_index + 1 : options.length

            options.insert(insert_pos,
              ButtonOption.new(
                _INTL("Multiplayer"),
                proc { MultiplayerUI.openMultiplayerMenu },
                "Configure or connect to multiplayer server."
              )
            )
            ##MultiplayerDebug.info("UI-008", "Injected Multiplayer button below KIF Settings.")
          end
        rescue => e
          ##MultiplayerDebug.error("UI-009", "Failed to insert Multiplayer button: #{e.message}")
        end
        return options
      end
    end
  else
    ##MultiplayerDebug.error("UI-010", "PokemonOption_Scene undefined — hook failed.")
  end

  # ===========================================
  # === Menu Logic
  # ===========================================
    def self.openMultiplayerMenu
    load_settings
    is_connected = MultiplayerClient.instance_variable_get(:@connected)
    connect_label = is_connected ? "Disconnect" : "Connect"

    # Build commands array - add Multiplayer Options only when connected
    commands = ["Server Settings", connect_label]
    commands << "Multiplayer Options" if is_connected
    commands << "Couch Coop Mode"
    commands << "Cancel"

    cmd = pbMessage(_INTL("Multiplayer Menu:"), commands, 0)

    # Handle commands based on position
    case cmd
    when 0
        openServerSettings
    when 1
        if is_connected
          MultiplayerClient.disconnect
          pbMessage(_INTL("Disconnected from server."))
          ##MultiplayerDebug.info("UI-018", "Disconnected manually by user.")
        else
          connectToServer
        end
    when 2
        if is_connected
          # Multiplayer Options menu
          openMultiplayerOptionsMenu
        else
          # Couch Coop (shifted because no MP Options when disconnected)
          openCouchCoopMenu
        end
    when 3
        if is_connected
          # Couch Coop when connected
          openCouchCoopMenu
        else
          # Cancel when disconnected
          ##MultiplayerDebug.info("UI-011", "Multiplayer menu closed.")
        end
    else
        ##MultiplayerDebug.info("UI-011", "Multiplayer menu closed.")
    end
    end

  # ===========================================
  # === Open Multiplayer Options submenu
  # ===========================================
  def self.openMultiplayerOptionsMenu
    pbFadeOutIn {
      scene = MultiplayerOptScene.new
      screen = PokemonOptionScreen.new(scene)
      screen.pbStartScreen
    }
  end


  def self.openServerSettings
    load_settings

    # Ask for IP
    ip = pbEnterText(_INTL("Enter Server IP:"), 0, 15, @server_ip)
    if ip.nil? || ip.empty?
      pbMessage(_INTL("No IP entered."))
      ##MultiplayerDebug.warn("UI-012", "User cancelled IP input.")
      return
    end

    # Ask for port
    port_str = pbEnterText(_INTL("Enter Server Port:"), 0, 5, @server_port.to_s)
    port = port_str.to_i
    port = DEFAULT_PORT if port <= 0

    # Check server before saving
    pbMessage(_INTL("Checking server connection..."))
    if server_reachable?(ip, port)
      @server_ip   = ip
      @server_port = port
      save_settings(@server_ip, @server_port)
      pbMessage(_INTL("Server reachable. Settings saved."))
      ##MultiplayerDebug.info("UI-013", "Valid server saved: #{@server_ip}:#{@server_port}")
    else
      pbMessage(_INTL("Server unreachable. Settings not saved."))
      ##MultiplayerDebug.warn("UI-014", "Invalid server, settings not written.")
    end
  end

  def self.connectToServer
    load_settings
    if @server_ip.nil? || @server_ip.strip.empty?
      pbMessage(_INTL("Please set the server IP first."))
      ##MultiplayerDebug.warn("UI-015", "Connect attempted without IP.")
      return
    end

    pbMessage(_INTL("Connecting to {1}:{2}...", @server_ip, @server_port))
    MultiplayerClient.connect(@server_ip)
     # === Feedback for user ===
    if MultiplayerClient.instance_variable_get(:@connected)
        pbMessage(_INTL("Successfully connected!"))
        ##MultiplayerDebug.info("UI-016A", "Successfully connected to #{@server_ip}:#{@server_port}")
    else
        pbMessage(_INTL("Failed to connect to server."))
        ##MultiplayerDebug.warn("UI-016B", "Connection attempt failed to #{@server_ip}:#{@server_port}")
    end
  end

  # ===========================================
  # === Couch Co-op Mode Menu
  # ===========================================
  def self.openCouchCoopMenu
    return unless defined?(CouchCoopConfig)

    # Check if Win32API is available
    unless defined?(CouchCoopInput) && CouchCoopInput.available?
      pbMessage(_INTL("Couch Co-op mode requires Win32API, which is not available on this system."))
      return
    end

    current_status = CouchCoopConfig.enabled? ? "Enabled (#{CouchCoopConfig.input_mode})" : "Disabled"

    commands = ["Enable Keyboard Only", "Disable", "Cancel"]
    cmd = pbMessage(_INTL("Couch Coop Mode: {1}", current_status), commands, 0)

    case cmd
    when 0
      # Enable Keyboard Only
      CouchCoopConfig.enable("keyboard")
      pbMessage(_INTL("Couch Co-op enabled. This client will only accept keyboard input, even when unfocused."))
      ##MultiplayerDebug.info("UI-COOP", "Couch co-op enabled: keyboard only")
    when 1
      # Disable
      CouchCoopConfig.disable
      pbMessage(_INTL("Couch Co-op disabled."))
      ##MultiplayerDebug.info("UI-COOP", "Couch co-op disabled")
    else
      # Cancel
      ##MultiplayerDebug.info("UI-COOP", "Couch co-op menu closed")
    end
  end
end

##MultiplayerDebug.info("UI-017", "UI initialization complete.")
