# ===========================================
# File: 124_UI_PvP_Settings.rb
# Purpose: PvP Battle Settings UI (Text-based with visual styling)
# Phase: 3 - Settings synchronization and UI
# ===========================================

class Scene_PvPSettings
  def initialize(is_initiator, opponent_name)
    @is_initiator = is_initiator
    @opponent_name = opponent_name
    @settings = PvPBattleState.settings.dup
    @current_index = 0  # Cursor position (0-5: settings, 6: confirm)
    @disposed = false
  end

  def main
    setup_ui()
    pbFadeInAndShow(@sprites) { update }

    loop do
      Graphics.update
      Input.update
      update_input()
      feed_events()
      break if @disposed
    end

    pbFadeOutAndHide(@sprites) { update }
    dispose_sprites()

    # Start battle AFTER UI is fully closed
    if @start_battle_after_close
      if defined?(pbPvPBattle)
        pbPvPBattle()
      else
        pbMessage(_INTL("PvP battle function not loaded!"))
        PvPBattleState.reset()
        MultiplayerClient.clear_pvp_state()
      end
    end
  end

  private

  def setup_ui
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99999
    @sprites = {}

    # Semi-transparent background
    @sprites["bg"] = Sprite.new(@viewport)
    @sprites["bg"].bitmap = Bitmap.new(Graphics.width, Graphics.height)
    @sprites["bg"].bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0, 180))

    # Main window background (centered)
    window_width = 480
    window_height = 360
    window_x = (Graphics.width - window_width) / 2
    window_y = (Graphics.height - window_height) / 2

    @sprites["window"] = Sprite.new(@viewport)
    @sprites["window"].bitmap = Bitmap.new(window_width, window_height)
    @sprites["window"].x = window_x
    @sprites["window"].y = window_y

    # Draw window background (styled like GTS/Trade windows)
    draw_window_background(@sprites["window"].bitmap, window_width, window_height)

    # Title text
    @sprites["title"] = Sprite.new(@viewport)
    @sprites["title"].bitmap = Bitmap.new(window_width, 48)
    @sprites["title"].x = window_x
    @sprites["title"].y = window_y + 8
    pbSetSystemFont(@sprites["title"].bitmap)

    title_text = @is_initiator ? "PvP Battle Setup" : "Battle Invitation from #{@opponent_name}"
    text_color = Color.new(248, 248, 248)
    shadow_color = Color.new(40, 40, 40)
    pbDrawTextPositions(@sprites["title"].bitmap, [
      [title_text, window_width / 2, 8, 2, text_color, shadow_color]
    ])

    # Settings display area
    @sprites["settings"] = Sprite.new(@viewport)
    @sprites["settings"].bitmap = Bitmap.new(window_width - 32, 320)
    @sprites["settings"].x = window_x + 16
    @sprites["settings"].y = window_y + 60

    refresh_settings_display()
  end

  def draw_window_background(bitmap, width, height)
    # Dark blue background (GTS style)
    base_color = Color.new(30, 50, 80)
    bitmap.fill_rect(0, 0, width, height, base_color)

    # Border
    border_color = Color.new(80, 120, 160)
    bitmap.fill_rect(0, 0, width, 4, border_color)  # Top
    bitmap.fill_rect(0, height - 4, width, 4, border_color)  # Bottom
    bitmap.fill_rect(0, 0, 4, height, border_color)  # Left
    bitmap.fill_rect(width - 4, 0, 4, height, border_color)  # Right

    # Title bar separator
    bitmap.fill_rect(8, 48, width - 16, 2, border_color)
  end

  def refresh_settings_display()
    bitmap = @sprites["settings"].bitmap
    bitmap.clear
    pbSetSystemFont(bitmap)

    text_color = Color.new(248, 248, 248)
    highlight_bg = Color.new(60, 100, 160, 120)
    shadow_color = Color.new(40, 40, 40)

    y_offset = 10
    line_height = 45

    # Draw each setting with cursor highlight
    draw_setting_line(bitmap, "Battle Size:", format_battle_size(@settings["battle_size"]), y_offset, 0, text_color, shadow_color, highlight_bg)
    y_offset += line_height

    draw_setting_line(bitmap, "Party Size:", format_party_size(@settings["party_size"]), y_offset, 1, text_color, shadow_color, highlight_bg)
    y_offset += line_height

    draw_setting_line(bitmap, "Held Items:", @settings["held_items"] ? "Allowed" : "Disabled", y_offset, 2, text_color, shadow_color, highlight_bg)
    y_offset += line_height

    draw_setting_line(bitmap, "Battle Items:", @settings["battle_items"] ? "Allowed" : "Disabled", y_offset, 3, text_color, shadow_color, highlight_bg)
    y_offset += line_height

    draw_setting_line(bitmap, "Level Cap:", format_level_cap(@settings["level_cap"]), y_offset, 4, text_color, shadow_color, highlight_bg)
    y_offset += line_height + 10

    # Confirm button
    draw_confirm_button(bitmap, y_offset, highlight_bg, text_color, shadow_color)
  end

  def draw_setting_line(bitmap, label, value, y, index, text_color, shadow_color, highlight_bg)
    # Highlight if cursor is on this setting
    if @current_index == index && @is_initiator
      bitmap.fill_rect(10, y - 2, bitmap.width - 20, 38, highlight_bg)
    end

    # Label (left aligned)
    pbDrawTextPositions(bitmap, [
      [label, 20, y, 0, text_color, shadow_color]
    ])

    # Value (right aligned)
    value_color = Color.new(120, 200, 255)
    pbDrawTextPositions(bitmap, [
      [value, bitmap.width - 20, y, 1, value_color, shadow_color]
    ])
  end

  def draw_confirm_button(bitmap, y, highlight_bg, text_color, shadow_color)
    # Highlight if cursor is on confirm button
    if @current_index == 5 && @is_initiator
      bitmap.fill_rect(10, y - 2, bitmap.width - 20, 38, highlight_bg)
    end

    # Draw "Confirm Settings" centered
    confirm_text = "Confirm Settings"
    pbDrawTextPositions(bitmap, [
      [confirm_text, bitmap.width / 2, y, 2, text_color, shadow_color]
    ])
  end

  def update_input
    return if @disposed
    return unless @is_initiator  # Only initiator can navigate

    # Cancel (X or Escape)
    if Input.trigger?(Input::BACK)
      pbPlayCancelSE
      cancel_pvp()
      return
    end

    # Navigate cursor up
    if Input.trigger?(Input::UP)
      @current_index = (@current_index - 1) % 6
      pbPlayCursorSE
      refresh_settings_display()
    end

    # Navigate cursor down
    if Input.trigger?(Input::DOWN)
      @current_index = (@current_index + 1) % 6
      pbPlayCursorSE
      refresh_settings_display()
    end

    # Change setting value (C or Enter)
    if Input.trigger?(Input::USE)
      if @current_index == 5
        # Confirm Settings button
        pbPlayDecisionSE
        handle_confirm()
      else
        # Cycle setting value
        pbPlayDecisionSE
        cycle_setting(@current_index)
        refresh_settings_display()
      end
    end
  end

  def cycle_setting(index)
    case index
    when 0  # Battle Size
      sizes = ["1v1", "2v2", "3v3"]
      idx = sizes.index(@settings["battle_size"])
      @settings["battle_size"] = sizes[(idx + 1) % sizes.length]
      broadcast_settings()

    when 1  # Party Size
      sizes = ["full", "pick4", "pick3"]
      idx = sizes.index(@settings["party_size"])
      @settings["party_size"] = sizes[(idx + 1) % sizes.length]
      broadcast_settings()

    when 2  # Held Items
      @settings["held_items"] = !@settings["held_items"]
      broadcast_settings()

    when 3  # Battle Items
      @settings["battle_items"] = !@settings["battle_items"]
      broadcast_settings()

    when 4  # Level Cap
      caps = ["none", "level50"]
      idx = caps.index(@settings["level_cap"])
      @settings["level_cap"] = caps[(idx + 1) % caps.length]
      broadcast_settings()
    end
  end

  def broadcast_settings
    PvPBattleState.update_settings(@settings)
    MultiplayerClient.pvp_update_settings(PvPBattleState.battle_id, @settings)
  end

  def handle_confirm
    # Check if Pick mode is active
    if @settings["party_size"] == "pick3" || @settings["party_size"] == "pick4"
      # IMPORTANT: Send battle start signal FIRST (before opening party selection UI)
      # This ensures receiver knows to wait, and we can safely block on UI
      if @is_initiator
        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("PVP-SETTINGS-UI", "Sending battle start signal before party selection")
        end
        MultiplayerClient.pvp_start_battle(PvPBattleState.battle_id, @settings)
      end

      open_party_selection()
    else
      # Full party mode - start battle immediately
      start_battle()
    end
  end

  def open_party_selection
    # Use Pokemon Essentials' party selection screen (like Battle Frontier)
    required_count = @settings["party_size"] == "pick3" ? 3 : 4

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-SETTINGS-UI", "Opening party selection for Pick #{required_count}")
    end

    # Create ruleset for party selection
    ruleset = PokemonRuleSet.new
    ruleset.setNumber(required_count)  # Must select exactly this many
    ruleset.addPokemonRule(NonEggRestriction.new)  # No eggs allowed

    # Open party selection screen (like Battle Frontier)
    chosen_party = nil
    pbFadeOutIn {
      scene = PokemonParty_Scene.new
      screen = PokemonPartyScreen.new(scene, $Trainer.party)
      chosen_party = screen.pbPokemonMultipleEntryScreenEx(ruleset)
    }

    if chosen_party && chosen_party.length == required_count
      # Convert Pokemon objects back to indices
      selections = []
      chosen_party.each do |chosen_pkmn|
        idx = $Trainer.party.index(chosen_pkmn)
        selections << idx if idx
      end

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-SETTINGS-UI", "Selected #{selections.length} Pokemon: indices #{selections.inspect}")
      end

      PvPBattleState.set_my_selections(selections)

      # Close settings screen and signal battle start
      # (For initiator, battle start was already sent before party selection)
      @disposed = true
      @start_battle_after_close = true
    else
      # User cancelled
      if defined?(MultiplayerDebug)
        MultiplayerDebug.warn("PVP-SETTINGS-UI", "Party selection cancelled")
      end
      pbMessage(_INTL("You must select {1} Pokémon to continue.", required_count))
    end
  end

  def start_battle
    # Initiator: Send battle start signal to receiver (only for Full Party mode)
    # For Pick modes, signal is sent BEFORE party selection to avoid blocking
    if @is_initiator
      MultiplayerClient.pvp_start_battle(PvPBattleState.battle_id, @settings)
    end

    # Close settings screen and signal battle start
    @disposed = true
    @start_battle_after_close = true
  end

  def cancel_pvp
    if pbConfirmMessage(_INTL("Cancel this battle?"))
      MultiplayerClient.pvp_cancel(PvPBattleState.battle_id) if defined?(MultiplayerClient.pvp_cancel)
      PvPBattleState.reset()
      MultiplayerClient.clear_pvp_state()
      @disposed = true
    end
  end

  def feed_events
    return if @disposed

    while MultiplayerClient.pvp_events_pending?
      # CRITICAL: Re-check @disposed inside loop!
      # open_party_selection() may set @disposed = true, and we must stop
      # consuming events to avoid losing :party_received for pbPvPBattle()
      break if @disposed

      ev = MultiplayerClient.next_pvp_event
      next unless ev

      case ev[:type]
      when :settings_update
        @settings = ev[:data].dup
        PvPBattleState.update_settings(@settings)
        refresh_settings_display()

      when :start_battle
        # Receiver: Opponent has confirmed settings, start battle
        unless @is_initiator
          # Update battle_id to match initiator's
          if ev[:data][:battle_id]
            PvPBattleState.instance_variable_set(:@battle_id, ev[:data][:battle_id])
          end

          # Update settings if provided
          if ev[:data][:settings]
            @settings = ev[:data][:settings].dup
            PvPBattleState.update_settings(@settings)
          end

          # Check if Pick mode is active - receiver needs to select Pokemon too
          if @settings["party_size"] == "pick3" || @settings["party_size"] == "pick4"
            open_party_selection()
          else
            @disposed = true
            @start_battle_after_close = true
          end
        end

      when :abort, :cancelled
        pbMessage(_INTL("Battle cancelled by opponent."))
        @disposed = true

      when :declined
        pbMessage(_INTL("Opponent declined the battle."))
        @disposed = true
      end
    end
  end

  def update
    return if @disposed
    @sprites.each_value { |sprite| sprite.update if sprite && !sprite.disposed? }
  end

  def dispose_sprites
    return unless @sprites
    @sprites.each_value { |sprite| sprite.dispose if sprite && !sprite.disposed? }
    @sprites.clear
    @viewport.dispose if @viewport && !@viewport.disposed?
  end

  # Helper formatting methods
  def format_battle_size(size)
    size.upcase
  end

  def format_party_size(size)
    case size
    when "full" then "Full Party"
    when "pick4" then "Pick 4"
    when "pick3" then "Pick 3"
    else size
    end
  end

  def format_level_cap(cap)
    case cap
    when "none" then "No Cap"
    when "level50" then "Level 50"
    else cap
    end
  end
end

if defined?(MultiplayerDebug)
  MultiplayerDebug.info("PVP-SETTINGS-UI", "PvP settings UI loaded")
end
