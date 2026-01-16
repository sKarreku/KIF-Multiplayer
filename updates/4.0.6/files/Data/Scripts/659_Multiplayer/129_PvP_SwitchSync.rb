# ===========================================
# File: 129_PvP_SwitchSync.rb
# Purpose: PvP Battle Switch Synchronization
# Phase: 6 - Switch Synchronization
# ===========================================
# Handles synchronization of Pokemon switches when a Pokemon faints in PvP battles.
# Prevents desync by ensuring both clients use the same switch choice.
# Adapted from CoopSwitchSync (030_Coop_SwitchSync.rb) for PvP battles.
#===============================================================================

module PvPSwitchSync
  # Pending switch choice from opponent
  @opponent_switch = nil
  @switch_received = false
  @switch_wait_start_time = nil

  #-----------------------------------------------------------------------------
  # Send my switch choice to opponent
  #-----------------------------------------------------------------------------
  def self.send_switch_choice(idxBattler, idxParty)
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-SWITCH", "=== SENDING SWITCH CHOICE ===")
      MultiplayerDebug.info("PVP-SWITCH", "  idxBattler: #{idxBattler}")
      MultiplayerDebug.info("PVP-SWITCH", "  idxParty: #{idxParty}")
    end

    unless defined?(PvPBattleState)
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error("PVP-SWITCH", "✗ PvPBattleState not defined!")
      end
      return
    end

    unless PvPBattleState.in_pvp_battle?
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error("PVP-SWITCH", "✗ Not in PvP battle!")
      end
      return
    end

    unless defined?(MultiplayerClient)
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error("PVP-SWITCH", "✗ MultiplayerClient not defined!")
      end
      return
    end

    battle_id = PvPBattleState.battle_id

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-SWITCH", "  Battle ID: #{battle_id}")
    end

    # In PvP, we only send party index (battler index is irrelevant - opponent knows their opponent's battler)
    message = "PVP_SWITCH:#{battle_id}|#{idxParty}"

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-SWITCH", "  Message: #{message}")
      MultiplayerDebug.info("PVP-SWITCH", "Calling MultiplayerClient.send_data...")
    end

    begin
      MultiplayerClient.send_data(message, rate_limit_type: :SWITCH)
      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-SWITCH", "✓ Switch choice sent successfully: party=#{idxParty}")
      end
    rescue => e
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error("PVP-SWITCH", "✗ Failed to send: #{e.message}")
        MultiplayerDebug.error("PVP-SWITCH", "Backtrace: #{e.backtrace.first(5).join('\n')}")
      end
      raise
    end
  end

  #-----------------------------------------------------------------------------
  # Receive switch choice from opponent (called from network handler)
  #-----------------------------------------------------------------------------
  def self.receive_switch(battle_id, idxParty)
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-SWITCH-NET", "Received switch: party=#{idxParty}")
    end

    # Validate battle context
    if defined?(PvPBattleState)
      current_battle_id = PvPBattleState.battle_id
      unless current_battle_id == battle_id
        if defined?(MultiplayerDebug)
          MultiplayerDebug.warn("PVP-SWITCH", "Battle ID mismatch")
        end
        return false
      end
    end

    # Store the switch choice (PvP only has one opponent, so we don't need to check battler index)
    @opponent_switch = idxParty.to_i
    @switch_received = true

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-SWITCH", "Stored opponent switch choice: party index #{idxParty}")
    end

    true
  end

  #-----------------------------------------------------------------------------
  # Wait for opponent's switch choice
  # Returns: party index to switch to, or nil on timeout
  #-----------------------------------------------------------------------------
  def self.wait_for_switch(idxBattler, timeout_seconds = 120)
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-SWITCH", "=== WAITING FOR SWITCH CHOICE ===")
      MultiplayerDebug.info("PVP-SWITCH", "  idxBattler: #{idxBattler}")
      MultiplayerDebug.info("PVP-SWITCH", "  Timeout: #{timeout_seconds}s")
    end

    unless defined?(PvPBattleState)
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error("PVP-SWITCH", "✗ PvPBattleState not defined!")
      end
      return nil
    end

    unless PvPBattleState.in_pvp_battle?
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error("PVP-SWITCH", "✗ Not in PvP battle!")
      end
      return nil
    end

    # Reset state
    @switch_received = false
    @switch_wait_start_time = Time.now

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-SWITCH", "  Initial @opponent_switch: #{@opponent_switch.inspect}")
    end

    # Check if we already have the switch choice
    if @opponent_switch
      choice = @opponent_switch
      @opponent_switch = nil
      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-SWITCH", "✓ Switch choice already available: #{choice}")
      end
      return choice
    end

    # Wait loop
    timeout_time = Time.now + timeout_seconds

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-SWITCH", "Starting wait loop...")
    end

    loop_count = 0
    while !@switch_received && Time.now < timeout_time
      # Check if opponent forfeited during our wait
      if defined?(PvPForfeitSync) && PvPForfeitSync.opponent_forfeited?
        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("PVP-SWITCH", "Opponent forfeited - stopping wait")
        end
        return -1  # Return special value to indicate forfeit
      end

      Graphics.update if defined?(Graphics)
      Input.update if defined?(Input)
      sleep(0.016)  # ~60 FPS
      loop_count += 1

      # Log every 60 frames (~1 second)
      if loop_count % 60 == 0 && defined?(MultiplayerDebug)
        elapsed = (Time.now - @switch_wait_start_time).round(1)
        MultiplayerDebug.info("PVP-SWITCH", "Still waiting... (#{elapsed}s elapsed)")
      end
    end

    # Check if opponent forfeited
    if defined?(PvPForfeitSync) && PvPForfeitSync.opponent_forfeited?
      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-SWITCH", "Opponent forfeited - battle ending")
      end
      return -1
    end

    # Check if received
    if @switch_received && @opponent_switch
      choice = @opponent_switch
      @opponent_switch = nil
      wait_duration = (Time.now - @switch_wait_start_time).round(3)

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-SWITCH", "✓ Received switch choice: #{choice} (waited #{wait_duration}s)")
      end

      return choice
    else
      # Timeout
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error("PVP-SWITCH", "✗ Switch choice timeout after #{timeout_seconds}s")
        MultiplayerDebug.error("PVP-SWITCH", "  @switch_received: #{@switch_received}")
        MultiplayerDebug.error("PVP-SWITCH", "  @opponent_switch: #{@opponent_switch.inspect}")
      end

      return nil
    end
  end

  #-----------------------------------------------------------------------------
  # Reset switch sync state
  #-----------------------------------------------------------------------------
  def self.reset
    @opponent_switch = nil
    @switch_received = false
    @switch_wait_start_time = nil

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-SWITCH", "Switch sync state reset")
    end
  end
end

if defined?(MultiplayerDebug)
  MultiplayerDebug.info("PVP-SWITCH", "PvP switch sync module loaded")
end
