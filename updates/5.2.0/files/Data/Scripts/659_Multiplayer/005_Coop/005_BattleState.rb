#===============================================================================
# MODULE 2: Coop Battle State Tracking
#===============================================================================
# Manages the lifecycle and identity of cooperative battles
# Tracks: battle ID, initiator status, participating allies, battle timestamps
#===============================================================================

module CoopBattleState
  # Battle identity
  @current_battle_id = nil
  @is_initiator = false
  @is_coop_battle = false

  # Participants
  @ally_sids = []
  @ally_names = {}  # { sid => player_name }

  # Timing
  @battle_start_time = nil
  @battle_end_time = nil

  # Battle context (for debugging)
  @encounter_type = nil
  @map_id = nil
  @foe_count = 0

  # Battle instance reference (for run away sync)
  @battle_instance = nil

  # Whiteout tracking
  @player_whited_out = false

  # Trainer battle tracking (for coop trainer battles)
  @trainer_battle = false
  @trainer_event_id = nil
  @trainer_map_id = nil

  #-----------------------------------------------------------------------------
  # Generate unique battle ID
  # Format: "SID{session_id}_{timestamp_ms}"
  #-----------------------------------------------------------------------------
  def self.generate_battle_id
    session_id = MultiplayerClient.session_id || "SOLO"
    timestamp_ms = (Time.now.to_f * 1000).to_i
    battle_id = "#{session_id}_#{timestamp_ms}"
    ##MultiplayerDebug.info("COOP-STATE", "Generated battle ID: #{battle_id}")
    battle_id
  end

  #-----------------------------------------------------------------------------
  # Create/Initialize a coop battle
  # Called when initiator starts battle or non-initiator joins
  #-----------------------------------------------------------------------------
  def self.create_battle(is_initiator:, ally_sids:, battle_id: nil, ally_names: {}, encounter_type: nil, map_id: nil, foe_count: 0, trainer_battle: false, trainer_event_id: nil, trainer_map_id: nil)
    # CRITICAL: Full reset of action sync state from any previous battle
    # This ensures no stale actions from previous battles interfere
    if defined?(CoopActionSync)
      CoopActionSync.full_reset
      ##MultiplayerDebug.info("COOP-STATE", "Full reset of action sync state before battle start")
    end

    # CRITICAL: Reset RNG sync state from any previous battle
    if defined?(CoopRNGSync)
      CoopRNGSync.reset_sync_state
      ##MultiplayerDebug.info("COOP-STATE", "Cleared RNG sync state before battle start")
    end

    # Generate battle ID if not provided (initiator generates, non-initiator receives)
    @current_battle_id = battle_id || generate_battle_id
    @is_initiator = is_initiator
    @is_coop_battle = !ally_sids.empty?
    @ally_sids = ally_sids.dup
    @ally_names = ally_names.dup
    @battle_start_time = Time.now
    @battle_end_time = nil
    @encounter_type = encounter_type
    @map_id = map_id || $game_map.map_id rescue nil
    @foe_count = foe_count
    @trainer_battle = trainer_battle
    @trainer_event_id = trainer_event_id
    @trainer_map_id = trainer_map_id

    # Log battle creation
    role = is_initiator ? "Initiator" : "Non-Initiator"
    ally_list = ally_sids.empty? ? "None (Solo)" : ally_sids.join(", ")

    ##MultiplayerDebug.info("COOP-STATE", "=" * 70)
    ##MultiplayerDebug.info("COOP-STATE", "BATTLE CREATED")
    ##MultiplayerDebug.info("COOP-STATE", "  ID: #{@current_battle_id}")
    ##MultiplayerDebug.info("COOP-STATE", "  Role: #{role}")
    ##MultiplayerDebug.info("COOP-STATE", "  Coop: #{@is_coop_battle}")
    ##MultiplayerDebug.info("COOP-STATE", "  Allies: #{ally_list}")
    ##MultiplayerDebug.info("COOP-STATE", "  Encounter: #{encounter_type}")
    ##MultiplayerDebug.info("COOP-STATE", "  Map: #{@map_id}")
    ##MultiplayerDebug.info("COOP-STATE", "  Foes: #{foe_count}")
    ##MultiplayerDebug.info("COOP-STATE", "  Timestamp: #{@battle_start_time}")
    ##MultiplayerDebug.info("COOP-STATE", "=" * 70)

    # Initialize debug HUD if in coop mode - ALWAYS show it for debugging
    if @is_coop_battle && defined?(CoopBattleDebugHUD)
      CoopBattleDebugHUD.initialize_hud(nil, @ally_sids)
      CoopBattleDebugHUD.set_message("Battle started as #{role}")
      # Force HUD visible immediately for debugging
      ##MultiplayerDebug.info("COOP-STATE", "Debug HUD enabled and visible")
    end

    @current_battle_id
  end

  #-----------------------------------------------------------------------------
  # Register battle instance reference (called after battle creation)
  # This allows network handlers to access the battle to set @decision
  #-----------------------------------------------------------------------------
  def self.register_battle_instance(battle)
    @battle_instance = battle
    ##MultiplayerDebug.info("COOP-STATE", "Battle instance registered")
  end

  #-----------------------------------------------------------------------------
  # Get current battle instance
  #-----------------------------------------------------------------------------
  def self.battle_instance
    @battle_instance
  end

  #-----------------------------------------------------------------------------
  # End the current battle
  #-----------------------------------------------------------------------------
  def self.end_battle
    return unless @current_battle_id

    @battle_end_time = Time.now
    duration = (@battle_end_time - @battle_start_time).round(2)

    ##MultiplayerDebug.info("COOP-STATE", "=" * 70)
    ##MultiplayerDebug.info("COOP-STATE", "BATTLE ENDED")
    ##MultiplayerDebug.info("COOP-STATE", "  ID: #{@current_battle_id}")
    ##MultiplayerDebug.info("COOP-STATE", "  Duration: #{duration}s")
    ##MultiplayerDebug.info("COOP-STATE", "  Total Allies: #{@ally_sids.length}")
    ##MultiplayerDebug.info("COOP-STATE", "=" * 70)

    # CRITICAL: Full reset of action sync state to prevent stale data in next battle
    if defined?(CoopActionSync)
      CoopActionSync.full_reset
      ##MultiplayerDebug.info("COOP-STATE", "Full reset of action sync state after battle end")
    end

    # CRITICAL: Reset RNG sync state to prevent stale data in next battle
    if defined?(CoopRNGSync)
      CoopRNGSync.reset_sync_state
      ##MultiplayerDebug.info("COOP-STATE", "Cleared RNG sync state after battle end")
    end

    # CRITICAL: Reset switch sync state to prevent stale data in next battle
    if defined?(CoopSwitchSync)
      CoopSwitchSync.reset
      ##MultiplayerDebug.info("COOP-STATE", "Cleared switch sync state after battle end")
    end

    # CRITICAL: Reset run away sync state to prevent stale data in next battle
    if defined?(CoopRunAwaySync)
      CoopRunAwaySync.reset_state
      ##MultiplayerDebug.info("COOP-STATE", "Cleared run away sync state after battle end")
    end

    # CRITICAL: Push updated party data after battle (HP, status, etc. may have changed)
    # This ensures the next battle starts with fresh, accurate HP values
    if defined?(MultiplayerClient) && MultiplayerClient.instance_variable_get(:@connected)
      begin
        MultiplayerClient.coop_push_party_now!
        ##MultiplayerDebug.info("COOP-STATE", "Pushed party snapshot after battle end")
      rescue => e
        ##MultiplayerDebug.warn("COOP-STATE", "Failed to push party after battle: #{e.message}")
      end
    end

    # Disable debug HUD
    if defined?(CoopBattleDebugHUD)
      CoopBattleDebugHUD.disable_hud
    end

    # Reset state
    reset_state
  end

  #-----------------------------------------------------------------------------
  # Reset all battle state
  #-----------------------------------------------------------------------------
  def self.reset_state
    @current_battle_id = nil
    @is_initiator = false
    @is_coop_battle = false
    @ally_sids = []
    @ally_names = {}
    @battle_start_time = nil
    @battle_end_time = nil
    @encounter_type = nil
    @map_id = nil
    @foe_count = 0
    @battle_instance = nil
    @player_whited_out = false
    @trainer_battle = false
    @trainer_event_id = nil
    @trainer_map_id = nil

    # Clear battle queue to prevent stale invites
    if defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:clear_coop_battle_queue)
      MultiplayerClient.clear_coop_battle_queue
    end

    # Reset transaction state
    if defined?(CoopBattleTransaction)
      CoopBattleTransaction.reset
    end

    ##MultiplayerDebug.info("COOP-STATE", "Battle state reset")
  end

  #-----------------------------------------------------------------------------
  # Query methods
  #-----------------------------------------------------------------------------

  # Check if currently in a coop battle
  def self.in_coop_battle?
    @is_coop_battle && !@current_battle_id.nil?
  end

  # Check if we are the initiator
  def self.am_i_initiator?
    @is_initiator
  end

  # Get current battle ID
  def self.battle_id
    @current_battle_id
  end

  # Get list of ally SIDs
  def self.get_ally_sids
    @ally_sids.dup
  end

  # Mark that the local player has whited out (all Pokemon fainted)
  def self.mark_whiteout
    @player_whited_out = true
    ##MultiplayerDebug.info("COOP-WHITEOUT", "Player marked as whited out")
  end

  # Check if the local player whited out during this battle
  def self.did_i_whiteout?
    @player_whited_out
  end

  # Get ally count
  def self.ally_count
    @ally_sids.length
  end

  # Check if a specific SID is an ally in this battle
  def self.is_ally?(sid)
    @ally_sids.include?(sid)
  end

  # Get ally name by SID
  def self.get_ally_name(sid)
    @ally_names[sid] || "Unknown"
  end

  # Get battle duration in seconds
  def self.battle_duration
    return 0 unless @battle_start_time
    end_time = @battle_end_time || Time.now
    (end_time - @battle_start_time).round(2)
  end

  # Check if battle is active
  def self.active?
    !@current_battle_id.nil? && @battle_end_time.nil?
  end

  # Check if current battle is a trainer battle
  def self.trainer_battle?
    @trainer_battle
  end

  # Get trainer event ID
  def self.trainer_event_id
    @trainer_event_id
  end

  # Get trainer map ID
  def self.trainer_map_id
    @trainer_map_id
  end

  #-----------------------------------------------------------------------------
  # Add ally dynamically (for late joiners - future feature)
  #-----------------------------------------------------------------------------
  def self.add_ally(sid, name = nil)
    return false if @ally_sids.include?(sid)

    @ally_sids << sid
    @ally_names[sid] = name if name
    @is_coop_battle = true unless @ally_sids.empty?

    ##MultiplayerDebug.info("COOP-STATE", "Ally added: SID#{sid} (#{name || 'Unknown'})")
    ##MultiplayerDebug.info("COOP-STATE", "Total allies: #{@ally_sids.length}")

    true
  end

  #-----------------------------------------------------------------------------
  # Remove ally dynamically (for disconnects)
  #-----------------------------------------------------------------------------
  def self.remove_ally(sid)
    return false unless @ally_sids.include?(sid)

    ally_name = @ally_names[sid] || "Unknown"
    @ally_sids.delete(sid)
    @ally_names.delete(sid)
    @is_coop_battle = false if @ally_sids.empty?

    ##MultiplayerDebug.info("COOP-STATE", "Ally removed: SID#{sid} (#{ally_name})")
    ##MultiplayerDebug.info("COOP-STATE", "Remaining allies: #{@ally_sids.length}")

    # Update debug HUD
    if defined?(CoopBattleDebugHUD)
      CoopBattleDebugHUD.set_message("Ally #{sid} disconnected")
    end

    true
  end

  #-----------------------------------------------------------------------------
  # Export full state as hash (for debugging/logging)
  #-----------------------------------------------------------------------------
  def self.export_state
    {
      battle_id: @current_battle_id,
      is_initiator: @is_initiator,
      is_coop: @is_coop_battle,
      allies: @ally_sids,
      ally_names: @ally_names,
      start_time: @battle_start_time,
      end_time: @battle_end_time,
      duration: battle_duration,
      encounter_type: @encounter_type,
      map_id: @map_id,
      foe_count: @foe_count,
      active: active?
    }
  end

  #-----------------------------------------------------------------------------
  # Log current state
  #-----------------------------------------------------------------------------
  def self.log_state
    state = export_state
    ##MultiplayerDebug.info("COOP-STATE", "Current state: #{state.inspect}")
  end

  #-----------------------------------------------------------------------------
  # Validate battle context (ensure we're in the right state)
  #-----------------------------------------------------------------------------
  def self.validate_battle_context(expected_battle_id, expected_turn = nil)
    # Check if battle ID matches
    unless @current_battle_id == expected_battle_id
      ##MultiplayerDebug.warn("COOP-STATE", "Battle ID mismatch! Expected: #{expected_battle_id}, Current: #{@current_battle_id}")
      return false
    end

    # Check if battle is still active
    unless active?
      ##MultiplayerDebug.warn("COOP-STATE", "Battle #{expected_battle_id} is no longer active")
      return false
    end

    ##MultiplayerDebug.info("COOP-STATE", "Battle context validated: #{expected_battle_id}")
    true
  end

  #-----------------------------------------------------------------------------
  # Get summary string for display
  #-----------------------------------------------------------------------------
  def self.get_summary
    return "No active battle" unless @current_battle_id

    role = @is_initiator ? "Initiator" : "Participant"
    mode = @is_coop_battle ? "Coop (#{@ally_sids.length} allies)" : "Solo"
    duration = battle_duration

    "Battle #{@current_battle_id} | #{role} | #{mode} | #{duration}s"
  end

  #-----------------------------------------------------------------------------
  # Emergency abort (for critical errors)
  #-----------------------------------------------------------------------------
  def self.emergency_abort(reason = "Unknown error")
    ##MultiplayerDebug.error("COOP-STATE", "=" * 70)
    ##MultiplayerDebug.error("COOP-STATE", "EMERGENCY BATTLE ABORT")
    ##MultiplayerDebug.error("COOP-STATE", "  Battle ID: #{@current_battle_id}")
    ##MultiplayerDebug.error("COOP-STATE", "  Reason: #{reason}")
    ##MultiplayerDebug.error("COOP-STATE", "  Duration: #{battle_duration}s")
    ##MultiplayerDebug.error("COOP-STATE", "=" * 70)

    if defined?(CoopBattleDebugHUD)
      CoopBattleDebugHUD.set_message("ABORT: #{reason}")
    end

    # Don't reset state immediately - let battle cleanup handle it
    # This preserves state for debugging
  end
end

#===============================================================================
# Integration Examples
#===============================================================================

# Example: Initiator starts battle (in 017_Coop_WildHook_v2.rb)
# CoopBattleState.create_battle(
#   is_initiator: true,
#   ally_sids: nearby_allies.map { |a| a[:sid] },
#   ally_names: Hash[nearby_allies.map { |a| [a[:sid], a[:name]] }],
#   encounter_type: :Land,
#   foe_count: foes.length
# )

# Example: Non-initiator joins (in 017_Coop_WildHook_v2.rb)
# CoopBattleState.create_battle(
#   is_initiator: false,
#   ally_sids: ally_sids_from_invitation,
#   battle_id: received_battle_id,
#   encounter_type: received_encounter_type
# )

# Example: Battle ends (in 003_Battle_StartAndEnd.rb)
# CoopBattleState.end_battle

# Example: Check if in coop battle
# if CoopBattleState.in_coop_battle?
#   # Perform coop-specific logic
# end

##MultiplayerDebug.info("MODULE-2", "CoopBattleState loaded successfully")
