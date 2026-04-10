#===============================================================================
# MODULE 13: Coop Battle Switch Synchronization
#===============================================================================
# Handles synchronization of Pokemon switches when a Pokemon faints in coop battles
# Prevents desync by ensuring all clients use the same switch choice
#===============================================================================

module CoopSwitchSync
  # Pending switch choices from remote players
  @pending_switches = {}  # { sid => party_index }
  @expected_switch_sid = nil
  @switch_received = false
  @switch_wait_start_time = nil

  #-----------------------------------------------------------------------------
  # Send my switch choice to all allies
  #-----------------------------------------------------------------------------
  def self.send_switch_choice(idxBattler, idxParty)
    return unless defined?(CoopBattleState)
    return unless CoopBattleState.in_coop_battle?
    return unless defined?(MultiplayerClient)

    battle_id = CoopBattleState.battle_id
    my_sid = MultiplayerClient.session_id.to_s

    message = "COOP_SWITCH:#{battle_id}|#{idxBattler}|#{idxParty}"
    MultiplayerClient.send_data(message, rate_limit_type: :SWITCH)

    ##MultiplayerDebug.info("COOP-SWITCH", "Sent switch choice: battler=#{idxBattler}, party=#{idxParty}")
  end

  #-----------------------------------------------------------------------------
  # Receive switch choice from remote player (called from network handler)
  #-----------------------------------------------------------------------------
  def self.receive_switch(from_sid, battle_id, idxBattler, idxParty)
    ##MultiplayerDebug.info("COOP-SWITCH", "Received switch from #{from_sid}: battler=#{idxBattler}, party=#{idxParty}")

    # Validate battle context
    if defined?(CoopBattleState)
      current_battle_id = CoopBattleState.battle_id
      unless current_battle_id == battle_id
        ##MultiplayerDebug.warn("COOP-SWITCH", "Battle ID mismatch: expected #{current_battle_id}, got #{battle_id}")
        return false
      end
    end

    # Store the switch choice
    @pending_switches[from_sid.to_s] = idxParty.to_i
    @switch_received = true if @expected_switch_sid == from_sid.to_s

    ##MultiplayerDebug.info("COOP-SWITCH", "Stored switch choice from #{from_sid}: party index #{idxParty}")

    true
  end

  #-----------------------------------------------------------------------------
  # Wait for remote player's switch choice
  # Returns: party index to switch to, or nil on timeout
  #-----------------------------------------------------------------------------
  def self.wait_for_switch(sid, timeout_seconds = 30)
    return nil unless defined?(CoopBattleState)
    return nil unless CoopBattleState.in_coop_battle?

    ##MultiplayerDebug.info("COOP-SWITCH", "=" * 70)
    ##MultiplayerDebug.info("COOP-SWITCH", "WAITING FOR SWITCH CHOICE")
    ##MultiplayerDebug.info("COOP-SWITCH", "  From: #{sid}")
    ##MultiplayerDebug.info("COOP-SWITCH", "  Timeout: #{timeout_seconds}s")
    ##MultiplayerDebug.info("COOP-SWITCH", "=" * 70)

    # Reset state
    @expected_switch_sid = sid.to_s
    @switch_received = false
    @switch_wait_start_time = Time.now

    # Check if we already have the switch choice
    if @pending_switches.key?(sid.to_s)
      choice = @pending_switches[sid.to_s]
      @pending_switches.delete(sid.to_s)
      ##MultiplayerDebug.info("COOP-SWITCH", "Switch choice already available: #{choice}")
      return choice
    end

    # Wait loop
    timeout_time = Time.now + timeout_seconds
    frame_count = 0

    while !@switch_received && Time.now < timeout_time
      # Update graphics
      Graphics.update if defined?(Graphics)
      Input.update if defined?(Input)

      # Periodic logging
      frame_count += 1
      if frame_count % 60 == 0
        elapsed = (Time.now - @switch_wait_start_time).round(1)
        ##MultiplayerDebug.info("COOP-SWITCH", "Still waiting for switch choice... #{elapsed}s elapsed")
      end

      sleep(0.016)  # ~60 FPS
    end

    # Check if received
    if @switch_received && @pending_switches.key?(sid.to_s)
      choice = @pending_switches[sid.to_s]
      @pending_switches.delete(sid.to_s)
      wait_duration = (Time.now - @switch_wait_start_time).round(3)

      ##MultiplayerDebug.info("COOP-SWITCH", "=" * 70)
      ##MultiplayerDebug.info("COOP-SWITCH", "SWITCH CHOICE RECEIVED")
      ##MultiplayerDebug.info("COOP-SWITCH", "  Party Index: #{choice}")
      ##MultiplayerDebug.info("COOP-SWITCH", "  Wait Duration: #{wait_duration}s")
      ##MultiplayerDebug.info("COOP-SWITCH", "=" * 70)

      return choice
    else
      # Timeout
      ##MultiplayerDebug.error("COOP-SWITCH", "=" * 70)
      ##MultiplayerDebug.error("COOP-SWITCH", "SWITCH CHOICE TIMEOUT")
      ##MultiplayerDebug.error("COOP-SWITCH", "  Timeout: #{timeout_seconds}s")
      ##MultiplayerDebug.error("COOP-SWITCH", "  No response from #{sid}")
      ##MultiplayerDebug.error("COOP-SWITCH", "=" * 70)

      return nil
    end
  end

  #-----------------------------------------------------------------------------
  # Reset switch sync state
  #-----------------------------------------------------------------------------
  def self.reset
    @pending_switches = {}
    @expected_switch_sid = nil
    @switch_received = false
    @switch_wait_start_time = nil

    ##MultiplayerDebug.info("COOP-SWITCH", "Switch sync state reset")
  end
end

##MultiplayerDebug.info("MODULE-13", "CoopSwitchSync loaded successfully")
