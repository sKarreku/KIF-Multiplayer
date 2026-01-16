# ===========================================
# File: 126_PvP_RNGSync.rb
# Purpose: PvP Battle RNG Seed Synchronization
# Phase: 5 - RNG Synchronization
# ===========================================
# Ensures deterministic random number generation across both PvP players by
# synchronizing the RNG seed before each turn's attack phase.
# Adapted from CoopRNGSync (022_Coop_RNGSync.rb) for PvP battles.
#===============================================================================

module PvPRNGSync
  # Received seed state
  @current_seed = nil
  @seed_received = false
  @seed_wait_start_time = nil
  @expected_turn = nil
  @seed_buffer = {}  # Buffer for seeds that arrived early: { turn => seed }

  #-----------------------------------------------------------------------------
  # Generate RNG seed (initiator only)
  #-----------------------------------------------------------------------------
  def self.generate_seed(turn_num)
    time_component = (Time.now.to_f * 1000).to_i
    turn_component = turn_num * 1000
    micro_component = Time.now.usec

    # Mix components and ensure positive 31-bit integer
    seed = (time_component + turn_component + micro_component) & 0x7FFFFFFF

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-RNG-SEED", "Turn #{turn_num}: Generated seed #{seed}")
    end

    seed
  end

  #-----------------------------------------------------------------------------
  # Initiator: Generate seed and send to opponent
  #-----------------------------------------------------------------------------
  def self.sync_seed_as_initiator(battle, turn_num = nil)
    return true unless defined?(PvPBattleState)
    return true unless PvPBattleState.in_pvp_battle?

    battle_id = PvPBattleState.battle_id
    opponent_sid = PvPBattleState.opponent_sid
    turn_num = turn_num || battle.turnCount

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-RNG", "Syncing RNG seed as initiator: turn=#{turn_num}")
    end

    # Generate seed
    seed = generate_seed(turn_num)
    @current_seed = seed

    # Send to opponent
    begin
      message = "PVP_RNG_SEED:#{battle_id}|#{turn_num}|#{seed}"
      MultiplayerClient.send_data(message, rate_limit_type: :RNG) if defined?(MultiplayerClient)

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-RNG", "Sent seed to opponent: battle=#{battle_id}, turn=#{turn_num}, seed=#{seed}")
      end
    rescue => e
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error("PVP-RNG", "Failed to send seed: #{e.message}")
      end
      return false
    end

    # Apply seed locally
    begin
      @battle_rng = Random.new(seed)
      srand(seed)

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-RNG", "Applied seed locally: #{seed}")
      end
    rescue => e
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error("PVP-RNG", "Failed to apply seed: #{e.message}")
      end
      return false
    end

    true
  end

  #-----------------------------------------------------------------------------
  # Receiver: Wait for and apply seed from initiator
  #-----------------------------------------------------------------------------
  def self.sync_seed_as_receiver(battle, turn_num = nil, timeout_seconds = 5)
    return true unless defined?(PvPBattleState)
    return true unless PvPBattleState.in_pvp_battle?

    battle_id = PvPBattleState.battle_id
    turn_num = turn_num || battle.turnCount

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-RNG", "Waiting for RNG seed as receiver: turn=#{turn_num}")
    end

    # Set expected turn
    @expected_turn = turn_num

    # Check if seed already in buffer
    if @seed_buffer[turn_num]
      @current_seed = @seed_buffer[turn_num]
      @seed_received = true
      @seed_buffer.delete(turn_num)
      @seed_wait_start_time = Time.now

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-RNG", "Retrieved seed from buffer: #{@current_seed}")
      end
    else
      # Reset state
      @seed_received = false
      @current_seed = nil
      @seed_wait_start_time = Time.now

      # Wait for seed
      timeout_time = Time.now + timeout_seconds

      while !@seed_received && Time.now < timeout_time
        # Check if opponent forfeited during our wait
        if defined?(PvPForfeitSync) && PvPForfeitSync.opponent_forfeited?
          if defined?(MultiplayerDebug)
            MultiplayerDebug.info("PVP-RNG", "Opponent forfeited - stopping wait")
          end
          return true  # Return success, battle will end via decision
        end

        Graphics.update if defined?(Graphics)
        Input.update if defined?(Input)
        sleep(0.016)  # ~60 FPS
      end
    end

    # Check if opponent forfeited
    if defined?(PvPForfeitSync) && PvPForfeitSync.opponent_forfeited?
      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-RNG", "Opponent forfeited - battle ending")
      end
      return true
    end

    # Check if received
    if @seed_received && @current_seed
      # Apply seed
      begin
        @battle_rng = Random.new(@current_seed)
        srand(@current_seed)

        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("PVP-RNG", "Applied seed from initiator: #{@current_seed}")
        end
      rescue => e
        if defined?(MultiplayerDebug)
          MultiplayerDebug.error("PVP-RNG", "Failed to apply seed: #{e.message}")
        end
        return false
      end

      # Send acknowledgment
      begin
        ack_message = "PVP_RNG_SEED_ACK:#{battle_id}|#{turn_num}"
        MultiplayerClient.send_data(ack_message) if defined?(MultiplayerClient)
      rescue => e
        if defined?(MultiplayerDebug)
          MultiplayerDebug.warn("PVP-RNG", "Failed to send ACK: #{e.message}")
        end
      end

      @expected_turn = nil
      true
    else
      # Timeout
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error("PVP-RNG", "RNG seed timeout after #{timeout_seconds}s")
      end
      false
    end
  end

  #-----------------------------------------------------------------------------
  # Receive seed from initiator (called from network handler)
  #-----------------------------------------------------------------------------
  def self.receive_seed(battle_id, turn, seed)
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-RNG-NET", "Received seed: battle=#{battle_id}, turn=#{turn}, seed=#{seed}")
    end

    # Validate battle context
    if defined?(PvPBattleState)
      unless PvPBattleState.battle_id == battle_id
        if defined?(MultiplayerDebug)
          MultiplayerDebug.warn("PVP-RNG", "Battle ID mismatch: expected #{PvPBattleState.battle_id}, got #{battle_id}")
        end
        return false
      end
    end

    # Check if we're waiting for this turn
    if @expected_turn && @expected_turn == turn.to_i
      @current_seed = seed.to_i
      @seed_received = true

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-RNG", "Stored seed immediately: #{@current_seed}")
      end
    else
      # Buffer for later
      @seed_buffer[turn.to_i] = seed.to_i

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-RNG", "Buffered seed for turn #{turn}: #{seed}")
      end
    end

    true
  end

  #-----------------------------------------------------------------------------
  # Reset RNG sync state
  #-----------------------------------------------------------------------------
  def self.reset_sync_state
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-RNG", "Resetting RNG sync state")
    end

    @current_seed = nil
    @seed_received = false
    @seed_wait_start_time = nil
    @expected_turn = nil
    @seed_buffer = {}
  end

  #-----------------------------------------------------------------------------
  # Get current seed (for debugging)
  #-----------------------------------------------------------------------------
  def self.current_seed
    @current_seed
  end

  #-----------------------------------------------------------------------------
  # Get battle RNG instance
  #-----------------------------------------------------------------------------
  def self.battle_rng
    @battle_rng
  end
end

if defined?(MultiplayerDebug)
  MultiplayerDebug.info("PVP-RNG", "PvP RNG sync module loaded")
end
