#===============================================================================
# MODULE: Multiplayer Options Submenu
#===============================================================================
# Adds a "Multiplayer" submenu to the KurayOptionsScene that contains:
# - Family System toggle (on/off)
# - Family Abilities & Type Infusion toggle (when family is on)
# - Family Assignment Rate (1% to 100%)
# - Family Font toggle
# - Coop Battle Timeout Disabler
# - Sync Multiplayer Settings with Player
# - Sync ALL Settings with Player
#===============================================================================

#===============================================================================
# Add Multiplayer settings to PokemonSystem
#===============================================================================
class PokemonSystem
  # Multiplayer-specific settings
  attr_accessor :mp_family_enabled           # Family System on/off
  attr_accessor :mp_family_abilities_enabled # Family Abilities & Type Infusion on/off
  attr_accessor :mp_family_rate              # Family assignment rate (0-100, default 1)
  attr_accessor :mp_family_font_enabled      # Family font rendering on/off
  attr_accessor :mp_coop_timeout_disabled    # Coop battle timeout disabled on/off

  # Initialize multiplayer settings if not already set
  alias mp_options_original_initialize initialize unless method_defined?(:mp_options_original_initialize)
  def initialize
    mp_options_original_initialize
    # Set defaults for multiplayer options
    @mp_family_enabled = 1           # On by default
    @mp_family_abilities_enabled = 1 # On by default
    @mp_family_rate = 1              # 1% default
    @mp_family_font_enabled = 1      # On by default
    @mp_coop_timeout_disabled = 0    # Off by default (timeout enabled)
  end
end

#===============================================================================
# Multiplayer Options Scene
#===============================================================================
class MultiplayerOptScene < PokemonOption_Scene
  def initialize
    @changedColor = false
    @kuray_menu = false
    @needs_refresh = false
  end

  # Flag to indicate menu needs to refresh after settings sync
  def needs_refresh?
    @needs_refresh
  end

  def set_needs_refresh
    @needs_refresh = true
  end

  def pbStartScene(inloadscreen = false)
    super
    @sprites["option"].nameBaseColor = Color.new(100, 180, 255)
    @sprites["option"].nameShadowColor = Color.new(50, 90, 130)
    @changedColor = true
    for i in 0...@PokemonOptions.length
      @sprites["option"][i] = (@PokemonOptions[i].get || 0)
    end
    @sprites["title"] = Window_UnformattedTextPokemon.newWithSize(
      _INTL("Multiplayer Options"), 0, 0, Graphics.width, 64, @viewport)
    @sprites["textbox"].text = _INTL("Customize multiplayer features")

    pbFadeInAndShow(@sprites) { pbUpdate }
  end

  def pbFadeInAndShow(sprites, visiblesprites = nil)
    return if !@changedColor
    super
  end

  def pbGetOptions(inloadscreen = false)
    options = []

    # Family System toggle
    options << EnumOption.new(_INTL("Family System"),
      [_INTL("Off"), _INTL("On")],
      proc { $PokemonSystem.mp_family_enabled || 0 },
      proc { |value|
        $PokemonSystem.mp_family_enabled = value
        apply_family_system_toggle(value == 1)
      },
      ["Disable Family System (re-enter menu to show options)",
       "Enable Family System (re-enter menu to show options)"]
    )

    # Only show these if Family System is enabled
    if ($PokemonSystem.mp_family_enabled || 0) == 1
      # Family Abilities & Type Infusion toggle
      options << EnumOption.new(_INTL("Family Abilities"),
        [_INTL("Off"), _INTL("On")],
        proc { $PokemonSystem.mp_family_abilities_enabled || 0 },
        proc { |value|
          $PokemonSystem.mp_family_abilities_enabled = value
          apply_family_abilities_toggle(value == 1)
        },
        ["Disable Family Talents and Type Infusion",
         "Enable Family Talents and Type Infusion"]
      )

      # Family Assignment Rate slider
      options << SliderOption.new(_INTL("Family Rate"),
        1, 100, 1,
        proc { $PokemonSystem.mp_family_rate || 1 },
        proc { |value|
          $PokemonSystem.mp_family_rate = value
          apply_family_rate(value)
        },
        "Chance for shiny Pokemon to get a Family (1-100%)"
      )

      # Family Font toggle
      options << EnumOption.new(_INTL("Family Font"),
        [_INTL("Off"), _INTL("On")],
        proc { $PokemonSystem.mp_family_font_enabled || 0 },
        proc { |value| $PokemonSystem.mp_family_font_enabled = value },
        ["Use default font for Family Pokemon names",
         "Use unique Family fonts for Pokemon names"]
      )
    end

    # Separator (visual only via description)
    options << EnumOption.new(_INTL("--- Coop ---"),
      [_INTL("-")],
      proc { 0 },
      proc { |value| },
      "Coop Battle Settings"
    )

    # Coop Battle Timeout Disabler
    options << EnumOption.new(_INTL("Coop Timeout"),
      [_INTL("Enabled"), _INTL("Disabled")],
      proc { $PokemonSystem.mp_coop_timeout_disabled || 0 },
      proc { |value|
        $PokemonSystem.mp_coop_timeout_disabled = value
        broadcast_timeout_setting(value == 1)
      },
      ["Normal battle timeouts (120 seconds)",
       "No timeout in Coop battles (all squad members must agree)"]
    )

    # Separator
    options << EnumOption.new(_INTL("--- Sync ---"),
      [_INTL("-")],
      proc { 0 },
      proc { |value| },
      "Settings Synchronization"
    )

    # Sync Multiplayer Settings button
    options << ButtonOption.new(_INTL("Sync MP Settings"),
      proc {
        @kuray_menu = true
        open_sync_mp_settings()
      },
      "Copy another player's Multiplayer settings"
    )

    # Sync ALL Settings button
    options << ButtonOption.new(_INTL("Sync ALL Settings"),
      proc {
        @kuray_menu = true
        open_sync_all_settings()
      },
      "Copy ALL settings from another player (with confirmation)"
    )

    return options
  end

  #-----------------------------------------------------------------------------
  # Apply Family System toggle
  #-----------------------------------------------------------------------------
  def apply_family_system_toggle(enabled)
    # Update the config module constant dynamically
    if defined?(PokemonFamilyConfig)
      # We can't change constants directly, so we use a class variable approach
      PokemonFamilyConfig.set_system_enabled(enabled) if PokemonFamilyConfig.respond_to?(:set_system_enabled)
    end

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("MP-OPTIONS", "Family System #{enabled ? 'ENABLED' : 'DISABLED'}")
    end
    # Note: User must re-enter menu to see/hide conditional Family options
  end

  #-----------------------------------------------------------------------------
  # Apply Family Abilities toggle
  #-----------------------------------------------------------------------------
  def apply_family_abilities_toggle(enabled)
    if defined?(PokemonFamilyConfig)
      PokemonFamilyConfig.set_talent_infusion_enabled(enabled) if PokemonFamilyConfig.respond_to?(:set_talent_infusion_enabled)
    end

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("MP-OPTIONS", "Family Abilities #{enabled ? 'ENABLED' : 'DISABLED'}")
    end
  end

  #-----------------------------------------------------------------------------
  # Apply Family Rate
  #-----------------------------------------------------------------------------
  def apply_family_rate(rate)
    if defined?(PokemonFamilyConfig)
      PokemonFamilyConfig.set_assignment_chance(rate / 100.0) if PokemonFamilyConfig.respond_to?(:set_assignment_chance)
    end

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("MP-OPTIONS", "Family Rate set to #{rate}%")
    end
  end

  #-----------------------------------------------------------------------------
  # Broadcast timeout setting to squad
  #-----------------------------------------------------------------------------
  def broadcast_timeout_setting(disabled)
    if defined?(MultiplayerClient) && MultiplayerClient.instance_variable_get(:@connected)
      # Broadcast to squad members
      message = "MP_TIMEOUT_SETTING:#{disabled ? 1 : 0}"
      MultiplayerClient.send_data(message) rescue nil
    end

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("MP-OPTIONS", "Coop Timeout #{disabled ? 'DISABLED' : 'ENABLED'}")
    end
  end

  #-----------------------------------------------------------------------------
  # Open player selection for syncing MP settings
  #-----------------------------------------------------------------------------
  def open_sync_mp_settings
    return unless @kuray_menu
    @kuray_menu = false

    unless defined?(MultiplayerClient) && MultiplayerClient.instance_variable_get(:@connected)
      pbMessage(_INTL("You must be connected to multiplayer to sync settings."))
      return
    end

    # Get list of online players
    players = get_online_players()
    if players.empty?
      pbMessage(_INTL("No other players online."))
      return
    end

    # Show player selection
    player_names = players.map { |p| p[:name] }
    player_names << _INTL("Cancel")

    choice = pbMessage(_INTL("Sync Multiplayer settings from:"), player_names)
    return if choice >= players.length  # Cancel

    selected_player = players[choice]
    request_mp_settings_sync(selected_player[:sid])
  end

  #-----------------------------------------------------------------------------
  # Open player selection for syncing ALL settings
  #-----------------------------------------------------------------------------
  def open_sync_all_settings
    return unless @kuray_menu
    @kuray_menu = false

    unless defined?(MultiplayerClient) && MultiplayerClient.instance_variable_get(:@connected)
      pbMessage(_INTL("You must be connected to multiplayer to sync settings."))
      return
    end

    # Get list of online players
    players = get_online_players()
    if players.empty?
      pbMessage(_INTL("No other players online."))
      return
    end

    # Show player selection
    player_names = players.map { |p| p[:name] }
    player_names << _INTL("Cancel")

    choice = pbMessage(_INTL("Sync ALL settings from:"), player_names)
    return if choice >= players.length  # Cancel

    selected_player = players[choice]

    # Confirmation
    if pbConfirmMessage(_INTL("This will overwrite ALL your settings with {1}'s settings. Continue?", selected_player[:name]))
      request_all_settings_sync(selected_player[:sid])
    end
  end

  #-----------------------------------------------------------------------------
  # Get list of online players
  #-----------------------------------------------------------------------------
  def get_online_players
    return [] unless defined?(MultiplayerClient)
    return [] unless MultiplayerClient.instance_variable_get(:@connected)

    # Request player list from server
    MultiplayerClient.send_data("REQ_PLAYERS") rescue nil

    # Wait for response (up to 2 seconds with visual feedback)
    start_time = Time.now
    timeout = 2.0
    player_list = nil

    while Time.now - start_time < timeout
      Graphics.update
      Input.update
      player_list = MultiplayerClient.instance_variable_get(:@player_list) rescue []
      break if player_list && !player_list.empty?
    end

    players = []
    my_sid = MultiplayerClient.session_id rescue nil
    my_name = $Trainer ? $Trainer.name : nil

    if player_list && !player_list.empty?
      player_list.each do |player_entry|
        # Skip if it's our own entry (check by name or SID)
        next if my_name && player_entry.to_s.downcase.include?(my_name.to_s.downcase)
        next if my_sid && player_entry.to_s.include?(my_sid.to_s)

        # Extract SID if format is "Name (SID)" or just use the entry as both
        if player_entry =~ /^(.+)\s*\((\d+)\)$/
          name = $1.strip
          sid = $2
        else
          name = player_entry.to_s
          sid = player_entry.to_s
        end

        players << { sid: sid, name: name }
      end
    end

    players
  end

  #-----------------------------------------------------------------------------
  # Request MP settings from another player
  #-----------------------------------------------------------------------------
  def request_mp_settings_sync(target_sid)
    if defined?(MultiplayerClient)
      # Clear any pending message
      MultiplayerSettingsSync.clear_pending_message if defined?(MultiplayerSettingsSync)

      # Format: MP_SETTINGS_REQUEST:<target_sid>|<sync_type>
      # Server will route to target and add our SID
      message = "MP_SETTINGS_REQUEST:#{target_sid}|MP"
      MultiplayerClient.send_data(message) rescue nil

      # Wait for response with timeout
      if wait_for_sync_response(3.0)
        # Refresh the menu UI to show new values
        refresh_options
      end
    end
  end

  #-----------------------------------------------------------------------------
  # Request ALL settings from another player
  #-----------------------------------------------------------------------------
  def request_all_settings_sync(target_sid)
    if defined?(MultiplayerClient)
      # Clear any pending message
      MultiplayerSettingsSync.clear_pending_message if defined?(MultiplayerSettingsSync)

      # Format: MP_SETTINGS_REQUEST:<target_sid>|<sync_type>
      # Server will route to target and add our SID
      message = "MP_SETTINGS_REQUEST:#{target_sid}|ALL"
      MultiplayerClient.send_data(message) rescue nil

      # Wait for response with timeout
      if wait_for_sync_response(3.0)
        # Refresh the menu UI to show new values
        refresh_options
      end
    end
  end

  #-----------------------------------------------------------------------------
  # Wait for sync response and display result message
  #-----------------------------------------------------------------------------
  def wait_for_sync_response(timeout_seconds)
    return false unless defined?(MultiplayerSettingsSync)

    start_time = Time.now
    while Time.now - start_time < timeout_seconds
      Graphics.update
      Input.update

      # Check if we got a response
      msg = MultiplayerSettingsSync.pending_sync_message
      if msg
        MultiplayerSettingsSync.clear_pending_message
        pbMessage(msg)
        # Signal that menu needs to refresh to show new values
        @needs_refresh = true
        return true
      end

      # Small sleep to avoid busy-waiting
      sleep(0.05)
    end

    # Timeout
    pbMessage(_INTL("Settings sync timed out. Please try again."))
    return false
  end

  #-----------------------------------------------------------------------------
  # Refresh the menu to show updated values
  #-----------------------------------------------------------------------------
  def refresh_options
    return unless @sprites && @sprites["option"]

    # Re-read values from $PokemonSystem into the UI
    for i in 0...@PokemonOptions.length
      @sprites["option"][i] = (@PokemonOptions[i].get || 0)
    end
  end
end

#===============================================================================
# Note: Multiplayer Options is accessed from the main Multiplayer menu
# (in 003_UI_Connect.rb) when connected to a server.
# This keeps all multiplayer-related options in one place.
#===============================================================================

#===============================================================================
# Network handlers for settings sync
#===============================================================================
module MultiplayerSettingsSync
  module_function

  # Handle incoming settings request
  def handle_settings_request(requester_sid, sync_type)
    return unless defined?(MultiplayerClient)

    if sync_type == "MP"
      # Send only multiplayer settings
      settings = get_mp_settings()
      json = SafeJSON.dump(settings) rescue MiniJSON.dump(settings)
      message = "MP_SETTINGS_RESPONSE:#{requester_sid}|MP|#{json}"
      MultiplayerClient.send_data(message) rescue nil
    elsif sync_type == "ALL"
      # Send all settings - use MiniJSON.dump directly since options_to_json returns string keys
      settings = options_to_json() rescue {}
      json = MiniJSON.dump(settings) rescue "{}"
      message = "MP_SETTINGS_RESPONSE:#{requester_sid}|ALL|#{json}"
      MultiplayerClient.send_data(message) rescue nil
    end
  end

  # Pending message to show on main thread (can't call pbMessage from network thread)
  @pending_sync_message = nil

  def self.pending_sync_message
    @pending_sync_message
  end

  def self.pending_sync_message=(msg)
    @pending_sync_message = msg
  end

  def self.clear_pending_message
    @pending_sync_message = nil
  end

  # Handle incoming settings response
  def handle_settings_response(sync_type, json_data)
    begin
      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("MP-SYNC", "handle_settings_response called: type=#{sync_type}, data_len=#{json_data.to_s.length}")
      end

      if sync_type == "MP"
        settings = SafeJSON.load(json_data) rescue MiniJSON.parse(json_data)
        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("MP-SYNC", "Parsed MP settings: #{settings.inspect}")
        end
        apply_mp_settings(settings)
        # Queue message for main thread instead of showing directly
        MultiplayerSettingsSync.pending_sync_message = _INTL("Multiplayer settings synchronized!")
        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("MP-SYNC", "MP settings applied successfully")
        end
      elsif sync_type == "ALL"
        # Parse JSON properly instead of using dangerous eval
        settings = MiniJSON.parse(json_data) rescue nil
        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("MP-SYNC", "Parsed ALL settings: #{settings ? 'OK' : 'FAILED'}")
        end
        if settings
          options_load_json(settings)
          MultiplayerSettingsSync.pending_sync_message = _INTL("All settings synchronized!")
        else
          MultiplayerSettingsSync.pending_sync_message = _INTL("Failed to parse settings data.")
        end
      end
    rescue => e
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error("MP-SYNC", "Failed to apply settings: #{e.message}")
        MultiplayerDebug.error("MP-SYNC", "Backtrace: #{e.backtrace.first(3).join(' | ')}")
      end
      MultiplayerSettingsSync.pending_sync_message = _INTL("Failed to synchronize settings.")
    end
  end

  # Get current multiplayer settings as hash
  def get_mp_settings
    {
      :mp_family_enabled => $PokemonSystem.mp_family_enabled,
      :mp_family_abilities_enabled => $PokemonSystem.mp_family_abilities_enabled,
      :mp_family_rate => $PokemonSystem.mp_family_rate,
      :mp_family_font_enabled => $PokemonSystem.mp_family_font_enabled,
      :mp_coop_timeout_disabled => $PokemonSystem.mp_coop_timeout_disabled
    }
  end

  # Apply multiplayer settings from hash
  def apply_mp_settings(settings)
    return unless settings.is_a?(Hash)

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("MP-SYNC", "apply_mp_settings BEFORE: family=#{$PokemonSystem.mp_family_enabled}, abilities=#{$PokemonSystem.mp_family_abilities_enabled}, rate=#{$PokemonSystem.mp_family_rate}, font=#{$PokemonSystem.mp_family_font_enabled}, timeout=#{$PokemonSystem.mp_coop_timeout_disabled}")
    end

    # Use key? to check existence, not value truthiness (0 is a valid value)
    $PokemonSystem.mp_family_enabled = settings[:mp_family_enabled] if settings.key?(:mp_family_enabled)
    $PokemonSystem.mp_family_abilities_enabled = settings[:mp_family_abilities_enabled] if settings.key?(:mp_family_abilities_enabled)
    $PokemonSystem.mp_family_rate = settings[:mp_family_rate] if settings.key?(:mp_family_rate)
    $PokemonSystem.mp_family_font_enabled = settings[:mp_family_font_enabled] if settings.key?(:mp_family_font_enabled)
    $PokemonSystem.mp_coop_timeout_disabled = settings[:mp_coop_timeout_disabled] if settings.key?(:mp_coop_timeout_disabled)

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("MP-SYNC", "apply_mp_settings AFTER: family=#{$PokemonSystem.mp_family_enabled}, abilities=#{$PokemonSystem.mp_family_abilities_enabled}, rate=#{$PokemonSystem.mp_family_rate}, font=#{$PokemonSystem.mp_family_font_enabled}, timeout=#{$PokemonSystem.mp_coop_timeout_disabled}")
    end

    # Apply to runtime config
    if defined?(PokemonFamilyConfig)
      PokemonFamilyConfig.set_system_enabled($PokemonSystem.mp_family_enabled == 1) rescue nil
      PokemonFamilyConfig.set_talent_infusion_enabled($PokemonSystem.mp_family_abilities_enabled == 1) rescue nil
      PokemonFamilyConfig.set_assignment_chance(($PokemonSystem.mp_family_rate || 1) / 100.0) rescue nil
    end
  end
end

#===============================================================================
# Module loaded
#===============================================================================
if defined?(MultiplayerDebug)
  MultiplayerDebug.info("MP-OPTIONS", "200_UI_MultiplayerOptions.rb loaded")
  MultiplayerDebug.info("MP-OPTIONS", "Multiplayer Options submenu available in game options")
end
