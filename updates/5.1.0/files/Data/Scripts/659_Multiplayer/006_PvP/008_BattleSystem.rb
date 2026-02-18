# ===========================================
# File: 008_BattleSystem.rb
# Purpose: PvP Battle System - Action, Switch, Forfeit Sync + Battle Aliases
# Merged from: 127_PvP_ActionSync.rb, 128_PvP_BattleAliases.rb,
#              129_PvP_SwitchSync.rb, 130_PvP_ForfeitSync.rb,
#              131_PvP_SwitchPhase_Alias.rb
# ===========================================
# Structure: Modules first (helpers), then class aliases (which call helpers)
#   1. PvPActionSync   - Action serialization & exchange
#   2. PvPSwitchSync   - Switch choice synchronization
#   3. PvPForfeitSync  - Forfeit handling
#   4. PokeBattle_Battle aliases - Command/Attack/Switch phase hooks + pbRun
#===============================================================================

#===============================================================================
# MODULE: PvPActionSync - Action Serialization & Exchange
#===============================================================================
# Handles collection, serialization, exchange, and synchronization of player
# battle actions between both PvP participants.
#
# CRITICAL: Target Index Mirroring for PvP
# =========================================
# In PvP battles, each player sees themselves as "side 0" (even indices: 0, 2, 4...)
# and the opponent as "side 1" (odd indices: 1, 3, 5...).
#
# Translation formula: swap even<->odd within the same "slot pair"
#   Index 0 <-> Index 1 (first slot on each side)
#   Index 2 <-> Index 3 (second slot on each side)
#   General: new_index = index XOR 1 (flip the lowest bit)
#===============================================================================

module PvPActionSync
  # Opponent's choice
  @opponent_choice = nil
  @choice_received = false
  @choice_wait_start_time = nil
  @current_turn = 0
  @choice_buffer = {}  # Buffer for choices that arrived early: { turn => choice }

  #-----------------------------------------------------------------------------
  # Mirror a battler index for PvP (swap sides)
  #-----------------------------------------------------------------------------
  def self.mirror_battler_index(index)
    return nil if index.nil?
    return -1 if index == -1  # -1 means "no target" or "self", keep as-is

    # XOR with 1 flips the lowest bit: 0<->1, 2<->3, 4<->5, etc.
    index ^ 1
  end

  #-----------------------------------------------------------------------------
  # Convert a choice array to serializable format
  # IMPORTANT: Target indices are MIRRORED for the opponent's perspective!
  #-----------------------------------------------------------------------------
  def self.serialize_choice(choice, battler)
    return nil unless choice && choice.length > 0

    action_type = choice[0]
    serializable_choice = [action_type]

    case action_type
    when :UseMove
      # choice = [:UseMove, move_index, move_object, target_index, priority]
      # We need: [:UseMove, move_index, nil, target_index, priority]
      # CRITICAL: Mirror target_index for opponent's perspective!
      # CRITICAL: Include priority (choice[4]) to ensure same turn order on both clients!
      move_index = choice[1]
      target_index = choice[3] if choice.length > 3
      move_priority = choice[4] if choice.length > 4
      mirrored_target = mirror_battler_index(target_index)

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-ACTION", "Serializing move: target #{target_index} -> mirrored #{mirrored_target}, priority=#{move_priority}")
      end

      serializable_choice = [:UseMove, move_index, nil, mirrored_target, move_priority]

    when :UseItem
      # choice = [:UseItem, item_id, item_target_index, move_target_index]
      # Mirror item_target_index (index 2) for opponent's perspective
      item_target = choice[2]
      mirrored_item_target = mirror_battler_index(item_target)

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-ACTION", "Serializing item: target #{item_target} -> mirrored #{mirrored_item_target}")
      end

      serializable_choice = [choice[0], choice[1], mirrored_item_target, choice[3]]

    when :SwitchOut
      # choice = [:SwitchOut, party_index, nil, -1]
      # party_index is relative to the player's own party, no mirroring needed
      serializable_choice = choice[0..3]

    when :Run
      # choice = [:Run, nil, nil, nil]
      serializable_choice = [:Run, nil, nil, nil]

    else
      # For any other action type, try to copy without the move object
      serializable_choice = choice.dup
      serializable_choice[2] = nil if serializable_choice.length > 2
    end

    serializable_choice
  end

  #-----------------------------------------------------------------------------
  # Reconstruct choice with move object from serialized format
  #-----------------------------------------------------------------------------
  def self.deserialize_choice(serialized_choice, battler)
    return nil unless serialized_choice && serialized_choice.length > 0

    action_type = serialized_choice[0]

    case action_type
    when :UseMove
      # Reconstruct: [:UseMove, move_index, move_object, target_index, priority]
      move_index = serialized_choice[1]
      target_index = serialized_choice[3]
      move_priority = serialized_choice[4] if serialized_choice.length > 4

      # Get the actual move object from the battler
      if battler && battler.moves && move_index && move_index < battler.moves.length
        move_object = battler.moves[move_index]
        return [:UseMove, move_index, move_object, target_index, move_priority]
      else
        return serialized_choice
      end

    else
      # Other actions don't need reconstruction
      return serialized_choice
    end
  end

  #-----------------------------------------------------------------------------
  # Extract all my actions from battle (supports 1v1, 2v2, 3v3)
  # In PvP, player's battlers are at EVEN indices (0, 2, 4...)
  # Returns a hash: { battler_index => serialized_choice }
  #-----------------------------------------------------------------------------
  def self.extract_my_actions(battle)
    actions = {}

    # Player's battlers are at even indices: 0, 2, 4...
    battle.battlers.each_with_index do |battler, idx|
      next unless battler
      next if idx.odd?  # Skip opponent's battlers (odd indices)

      choice = battle.choices[idx]
      if choice && choice.length > 0 && choice[0] != :None
        serializable = serialize_choice(choice, battler)
        actions[idx] = serializable

        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("PVP-ACTION", "Extracted action for battler #{idx}: #{serializable.inspect}")
        end
      end
    end

    actions.empty? ? nil : actions
  end

  #-----------------------------------------------------------------------------
  # Legacy single-action extraction (for backward compatibility)
  #-----------------------------------------------------------------------------
  def self.extract_my_action(battle)
    actions = extract_my_actions(battle)
    return nil unless actions && !actions.empty?

    # Return the first action found
    actions.values.first
  end

  #-----------------------------------------------------------------------------
  # Wait for opponent's actions and apply them to battle
  #-----------------------------------------------------------------------------
  def self.wait_for_opponent_action(battle, timeout_seconds = 120)
    return false unless defined?(PvPBattleState)
    return false unless PvPBattleState.in_pvp_battle?

    battle_id = PvPBattleState.battle_id
    turn_num = battle.turnCount + 1

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-ACTION", "Waiting for opponent's actions: turn=#{turn_num}")
    end

    # Send ALL my actions (for 2v2/3v3, this includes multiple battlers)
    my_actions = extract_my_actions(battle)
    if my_actions && !my_actions.empty?
      send_actions(battle_id, turn_num, my_actions)
    else
      if defined?(MultiplayerDebug)
        MultiplayerDebug.warn("PVP-ACTION", "No actions to send (might be fine for some situations)")
      end
    end

    # Set expected turn
    @current_turn = turn_num

    # Check if choice already in buffer
    if @choice_buffer[turn_num]
      @opponent_choice = @choice_buffer[turn_num]
      @choice_received = true
      @choice_buffer.delete(turn_num)
      @choice_wait_start_time = Time.now

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-ACTION", "Retrieved choices from buffer: #{@opponent_choice.inspect}")
      end
    else
      # Reset state
      @choice_received = false
      @opponent_choice = nil
      @choice_wait_start_time = Time.now

      # Wait for opponent's action
      timeout_time = Time.now + timeout_seconds

      while !@choice_received && Time.now < timeout_time
        # Check if opponent forfeited during our wait
        if defined?(PvPForfeitSync) && PvPForfeitSync.opponent_forfeited?
          if defined?(MultiplayerDebug)
            MultiplayerDebug.info("PVP-ACTION", "Opponent forfeited - stopping wait")
          end
          return true  # Return success, battle will end via decision
        end

        Graphics.update if defined?(Graphics)
        Input.update if defined?(Input)
        sleep(0.016)  # ~60 FPS
      end
    end

    # Check if opponent forfeited (could have happened during buffer check)
    if defined?(PvPForfeitSync) && PvPForfeitSync.opponent_forfeited?
      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-ACTION", "Opponent forfeited - battle ending")
      end
      return true
    end

    # Check if received
    if @choice_received && @opponent_choice
      # Apply opponent's actions
      return apply_opponent_actions(battle, @opponent_choice)
    else
      # Timeout
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error("PVP-ACTION", "Action sync timeout after #{timeout_seconds}s")
      end
      return false
    end
  end

  #-----------------------------------------------------------------------------
  # Apply opponent's actions to battle
  #-----------------------------------------------------------------------------
  def self.apply_opponent_actions(battle, opponent_data)
    if opponent_data.is_a?(Hash)
      # New format: { battler_idx => choice }
      opponent_data.each do |their_battler_idx, choice|
        # Mirror the index: their battler 0 is our battler 1, their 2 is our 3, etc.
        our_battler_idx = mirror_battler_index(their_battler_idx.to_i)
        battler = battle.battlers[our_battler_idx]

        if battler
          full_choice = deserialize_choice(choice, battler)
          battle.choices[our_battler_idx] = full_choice

          if defined?(MultiplayerDebug)
            MultiplayerDebug.info("PVP-ACTION", "Applied opponent's action: their idx #{their_battler_idx} -> our idx #{our_battler_idx}: #{full_choice.inspect}")
          end
        else
          if defined?(MultiplayerDebug)
            MultiplayerDebug.warn("PVP-ACTION", "No battler at mirrored index #{our_battler_idx}")
          end
        end
      end
      return true
    else
      # Legacy format: single choice array - apply to first opponent battler (index 1)
      opponent_battler_idx = 1
      battler = battle.battlers[opponent_battler_idx]

      if battler
        full_choice = deserialize_choice(opponent_data, battler)
        battle.choices[opponent_battler_idx] = full_choice

        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("PVP-ACTION", "Applied legacy opponent action to battler #{opponent_battler_idx}: #{full_choice.inspect}")
        end
        return true
      else
        if defined?(MultiplayerDebug)
          MultiplayerDebug.error("PVP-ACTION", "Opponent battler not found at index #{opponent_battler_idx}")
        end
        return false
      end
    end
  end

  #-----------------------------------------------------------------------------
  # Send all my actions to opponent (for 2v2/3v3)
  #-----------------------------------------------------------------------------
  def self.send_actions(battle_id, turn_num, actions)
    begin
      data = {
        :turn => turn_num,
        :actions => actions
      }

      json_str = SafeJSON.dump(data)

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-ACTION", "Serialized #{actions.size} actions with SafeJSON: #{json_str.length} chars")
      end

      message = "PVP_CHOICE:#{battle_id}|#{json_str}"
      MultiplayerClient.send_data(message, rate_limit_type: :CHOICE) if defined?(MultiplayerClient)

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-ACTION", "Sent #{actions.size} actions to opponent: turn=#{turn_num}")
        actions.each do |idx, choice|
          MultiplayerDebug.info("PVP-ACTION", "  Battler #{idx}: #{choice.inspect}")
        end
      end

      return true
    rescue => e
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error("PVP-ACTION", "Failed to send actions: #{e.message}")
        MultiplayerDebug.error("PVP-ACTION", "  Backtrace: #{e.backtrace.first(3).join(' | ')}")
      end
      return false
    end
  end

  #-----------------------------------------------------------------------------
  # Send single action to opponent (legacy, for backward compatibility)
  #-----------------------------------------------------------------------------
  def self.send_action(battle_id, turn_num, choice)
    send_actions(battle_id, turn_num, { 0 => choice })
  end

  #-----------------------------------------------------------------------------
  # Receive opponent's actions from network
  #-----------------------------------------------------------------------------
  def self.receive_action(battle_id, json_data)
    begin
      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-ACTION-NET", "Receiving action data: #{json_data.to_s.length} chars")
      end

      data = SafeJSON.load(json_data.to_s)

      unless data.is_a?(Hash)
        raise "Decoded action data is not a Hash (got #{data.class})"
      end

      turn = data[:turn]

      actions_data = nil
      if data[:actions]
        actions_data = data[:actions]
        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("PVP-ACTION-NET", "Parsed #{actions_data.size} actions for turn #{turn}")
        end
      elsif data[:choice]
        actions_data = data[:choice]
        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("PVP-ACTION-NET", "Parsed legacy choice for turn #{turn}: #{actions_data.inspect}")
        end
      else
        raise "No :actions or :choice found in data"
      end

      # Validate battle context
      if defined?(PvPBattleState)
        unless PvPBattleState.battle_id == battle_id
          if defined?(MultiplayerDebug)
            MultiplayerDebug.warn("PVP-ACTION", "Battle ID mismatch")
          end
          return false
        end
      end

      # Check if this is for the current turn
      if @current_turn > 0 && turn.to_i == @current_turn
        @opponent_choice = actions_data
        @choice_received = true

        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("PVP-ACTION", "Stored opponent's actions for turn #{turn}")
        end
      else
        # Buffer for later (action arrived before wait_for_opponent_action was called)
        @choice_buffer[turn.to_i] = actions_data

        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("PVP-ACTION", "Buffered actions for turn #{turn}")
        end
      end

      return true
    rescue => e
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error("PVP-ACTION", "Failed to receive action: #{e.message}")
        MultiplayerDebug.error("PVP-ACTION", "  Backtrace: #{e.backtrace.first(3).join(' | ')}")
      end
      return false
    end
  end

  #-----------------------------------------------------------------------------
  # Reset action sync state
  #-----------------------------------------------------------------------------
  def self.reset_sync_state
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-ACTION", "Resetting action sync state")
    end

    @opponent_choice = nil
    @choice_received = false
    @choice_wait_start_time = nil
    @current_turn = 0
    @choice_buffer = {}
  end
end

if defined?(MultiplayerDebug)
  MultiplayerDebug.info("PVP-ACTION", "PvP action sync module loaded")
end

#===============================================================================
# MODULE: PvPSwitchSync - Switch Choice Synchronization
#===============================================================================
# Handles synchronization of Pokemon switches when a Pokemon faints in PvP battles.
# Prevents desync by ensuring both clients use the same switch choice.
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
        MultiplayerDebug.error("PVP-SWITCH", "PvPBattleState not defined!")
      end
      return
    end

    unless PvPBattleState.in_pvp_battle?
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error("PVP-SWITCH", "Not in PvP battle!")
      end
      return
    end

    unless defined?(MultiplayerClient)
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error("PVP-SWITCH", "MultiplayerClient not defined!")
      end
      return
    end

    battle_id = PvPBattleState.battle_id

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-SWITCH", "  Battle ID: #{battle_id}")
    end

    # In PvP, we only send party index (battler index is irrelevant)
    message = "PVP_SWITCH:#{battle_id}|#{idxParty}"

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-SWITCH", "  Message: #{message}")
      MultiplayerDebug.info("PVP-SWITCH", "Calling MultiplayerClient.send_data...")
    end

    begin
      MultiplayerClient.send_data(message, rate_limit_type: :SWITCH)
      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-SWITCH", "Switch choice sent successfully: party=#{idxParty}")
      end
    rescue => e
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error("PVP-SWITCH", "Failed to send: #{e.message}")
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

    # Store the switch choice
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
        MultiplayerDebug.error("PVP-SWITCH", "PvPBattleState not defined!")
      end
      return nil
    end

    unless PvPBattleState.in_pvp_battle?
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error("PVP-SWITCH", "Not in PvP battle!")
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
        MultiplayerDebug.info("PVP-SWITCH", "Switch choice already available: #{choice}")
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
        MultiplayerDebug.info("PVP-SWITCH", "Received switch choice: #{choice} (waited #{wait_duration}s)")
      end

      return choice
    else
      # Timeout
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error("PVP-SWITCH", "Switch choice timeout after #{timeout_seconds}s")
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

#===============================================================================
# MODULE: PvPForfeitSync - Forfeit Handling
#===============================================================================
# Handles forfeits in PvP battles. When a player forfeits:
# - Sends PVP_FORFEIT message to opponent
# - Opponent receives it and ends battle immediately (they win)
# - Prevents the "waiting for action" bug when one player forfeits
#===============================================================================

module PvPForfeitSync
  @forfeit_received = false
  @forfeit_from = nil

  #-----------------------------------------------------------------------------
  # Send forfeit to opponent
  #-----------------------------------------------------------------------------
  def self.send_forfeit(battle_id)
    return unless defined?(MultiplayerClient)
    return unless defined?(PvPBattleState) && PvPBattleState.in_pvp_battle?

    message = "PVP_FORFEIT:#{battle_id}"
    MultiplayerClient.send_data(message)

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-FORFEIT", "Sent forfeit to opponent")
    end
  end

  #-----------------------------------------------------------------------------
  # Receive forfeit from opponent (called from network handler)
  #-----------------------------------------------------------------------------
  def self.receive_forfeit(battle_id)
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-FORFEIT", "Received forfeit from opponent!")
    end

    # Validate battle context
    if defined?(PvPBattleState)
      unless PvPBattleState.battle_id == battle_id
        if defined?(MultiplayerDebug)
          MultiplayerDebug.warn("PVP-FORFEIT", "Battle ID mismatch - ignoring forfeit")
        end
        return false
      end
    end

    @forfeit_received = true
    @forfeit_from = PvPBattleState.opponent_sid

    # Immediately end the battle - we WIN because opponent forfeited
    if defined?(PvPBattleState) && PvPBattleState.battle_instance
      battle = PvPBattleState.battle_instance

      # Decision 1 = Win for player
      battle.decision = 1

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-FORFEIT", "Battle decision set to 1 (win) - opponent forfeited")
      end
    else
      if defined?(MultiplayerDebug)
        MultiplayerDebug.warn("PVP-FORFEIT", "No battle instance to set decision on")
      end
    end

    true
  end

  #-----------------------------------------------------------------------------
  # Check if opponent forfeited (called from action sync wait loop)
  #-----------------------------------------------------------------------------
  def self.opponent_forfeited?
    @forfeit_received
  end

  #-----------------------------------------------------------------------------
  # Reset forfeit state (called when battle ends)
  #-----------------------------------------------------------------------------
  def self.reset
    @forfeit_received = false
    @forfeit_from = nil
  end
end

if defined?(MultiplayerDebug)
  MultiplayerDebug.info("PVP-FORFEIT", "PvP forfeit sync module loaded")
end

#===============================================================================
# CLASS: PokeBattle_Battle - PvP Battle Phase Aliases
#===============================================================================
# Hooks into battle phases to inject PvP synchronization:
# 1. pbCommandPhaseLoop - Skip AI for opponent NPCTrainer (action from network)
# 2. pbCommandPhase - Player action -> Action sync -> RNG sync -> AI phase
# 3. pbAttackPhase - Execute attacks (RNG already synced), reset sync state
# 4. pbSwitchInBetween - Synchronize Pokemon switch choices when fainted
# 5. pbOnActiveOne - Resync RNG before switch-in effects
# 6. pbRun - Handle forfeit in PvP battles
#
# CRITICAL: RNG sync happens BEFORE AI phase in command phase, NOT in attack phase!
#===============================================================================

class PokeBattle_Battle
  # Save original methods
  unless defined?(pvp_original_pbCommandPhase)
    alias pvp_original_pbCommandPhase pbCommandPhase
  end

  unless defined?(pvp_original_pbCommandPhaseLoop)
    alias pvp_original_pbCommandPhaseLoop pbCommandPhaseLoop
  end

  unless defined?(pvp_original_pbAttackPhase)
    alias pvp_original_pbAttackPhase pbAttackPhase
  end

  unless defined?(pvp_original_pbSwitchInBetween)
    alias pvp_original_pbSwitchInBetween pbSwitchInBetween
  end

  unless defined?(pvp_original_pbOnActiveOne)
    alias pvp_original_pbOnActiveOne pbOnActiveOne if method_defined?(:pbOnActiveOne)
  end

  alias pvp_original_pbRun pbRun unless method_defined?(:pvp_original_pbRun)

  #-----------------------------------------------------------------------------
  # Command Phase Loop - Skip AI for opponent NPCTrainer (action from network)
  #-----------------------------------------------------------------------------
  def pbCommandPhaseLoop(isPlayer)
    # Check if PvP battle in AI phase
    in_pvp = defined?(PvPBattleState) && PvPBattleState.in_pvp_battle?

    if !isPlayer && in_pvp
      # AI PHASE IN PVP
      # Opponent NPCTrainer already has action from network (set in wait_for_opponent_action)
      # Just skip them - their @choices[idx] is already set

      idxBattler = -1
      loop do
        break if @decision != 0
        idxBattler += 1
        break if idxBattler >= @battlers.length

        next if !@battlers[idxBattler] || pbOwnedByPlayer?(idxBattler) != isPlayer

        # Check if this is opponent's NPCTrainer
        trainer = pbGetOwnerFromBattlerIndex(idxBattler)
        if trainer && trainer.is_a?(NPCTrainer)
          # Check if this is the opponent (not ally)
          is_opposing = opposes?(idxBattler)
          if is_opposing
            # Opponent NPC - their action already set from network, SKIP AI
            if defined?(MultiplayerDebug)
              MultiplayerDebug.info("PVP-AI", "Skipping AI for opponent battler #{idxBattler} (action from network)")
            end
            next
          end
        end

        # Skip if action already chosen
        next if @choices[idxBattler][0] != :None
        next if !pbCanShowCommands?(idxBattler)

        # Run AI for any other battlers (shouldn't happen in 1v1 PvP)
        @battleAI.pbDefaultChooseEnemyCommand(idxBattler)
      end
    else
      # Not PvP AI phase - call original
      pvp_original_pbCommandPhaseLoop(isPlayer)
    end
  end

  #-----------------------------------------------------------------------------
  # Command Phase - Player selects action + wait for opponent + AI phase
  #-----------------------------------------------------------------------------
  def pbCommandPhase
    # Check if we're in a PvP battle
    in_pvp = defined?(PvPBattleState) && PvPBattleState.in_pvp_battle?

    unless in_pvp
      # Normal battle - call original
      return pvp_original_pbCommandPhase
    end

    # === PVP BATTLE: Extended command phase (mirrors coop pattern) ===
    @scene.pbBeginCommandPhase

    # Reset choices if commands can be shown
    @battlers.each_with_index do |b, i|
      next if !b
      pbClearChoice(i) if pbCanShowCommands?(i)
    end

    # Reset Mega Evolution choices
    for side in 0...2
      @megaEvolution[side].each_with_index do |megaEvo, i|
        @megaEvolution[side][i] = -1 if megaEvo >= 0
      end
    end

    # 1. PLAYER ACTION SELECTION (use vanilla loop)
    pbCommandPhaseLoop(true)

    # Check if battle ended during command selection
    if @decision != 0
      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-COMMAND", "Battle ended during command phase (decision=#{@decision})")
      end
      return
    end

    # 2. ACTION SYNCHRONIZATION
    # Wait for opponent's action and apply it
    if defined?(PvPActionSync)
      @scene.pbDisplayMessage(_INTL("Waiting for opponent..."), true)

      success = PvPActionSync.wait_for_opponent_action(self, 120)

      # Clear waiting message
      @scene.instance_variable_set(:@briefMessage, false) if @scene
      cw = @scene.sprites["messageWindow"] rescue nil
      if cw
        cw.text = ""
        cw.visible = false
      end

      # Check if opponent forfeited during action sync
      if defined?(PvPForfeitSync) && PvPForfeitSync.opponent_forfeited?
        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("PVP-COMMAND", "Opponent forfeited during action sync - we win!")
        end
        pbDisplay(_INTL("Your opponent forfeited!"))
        return  # @decision already set by PvPForfeitSync
      end

      unless success
        if defined?(MultiplayerDebug)
          MultiplayerDebug.error("PVP-COMMAND", "Action sync failed or timed out")
        end
        pbDisplay(_INTL("Connection lost. Ending battle..."))
        @decision = 3  # Forfeit
        return
      end

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-COMMAND", "Action sync complete")
      end
    end

    # Check if battle ended during action sync (includes forfeit)
    if @decision != 0
      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-COMMAND", "Battle ended during action sync (decision=#{@decision})")
      end
      return
    end

    # 3. RNG SYNCHRONIZATION (BEFORE AI PHASE!)
    # This ensures deterministic move execution on both clients
    if defined?(PvPRNGSync)
      rng_sync_turn = @turnCount + 1

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-COMMAND", "Syncing RNG seed before AI phase: turn=#{rng_sync_turn}")
      end

      success = false

      if PvPBattleState.is_initiator?
        success = PvPRNGSync.sync_seed_as_initiator(self, rng_sync_turn)
      else
        success = PvPRNGSync.sync_seed_as_receiver(self, rng_sync_turn, 5)
      end

      unless success
        if defined?(MultiplayerDebug)
          MultiplayerDebug.error("PVP-COMMAND", "RNG sync failed")
        end
        pbDisplay(_INTL("RNG sync failed!"))
        @decision = 3  # Forfeit
        return
      end

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-COMMAND", "RNG sync complete")
      end
    end

    # 4. AI ACTION SELECTION
    # Call AI phase (opponent's action already set by wait_for_opponent_action)
    pbCommandPhaseLoop(false)
  end

  #-----------------------------------------------------------------------------
  # Attack Phase - Execute attacks (RNG already synced in command phase)
  #-----------------------------------------------------------------------------
  def pbAttackPhase
    # Check if we're in a PvP battle
    in_pvp = defined?(PvPBattleState) && PvPBattleState.in_pvp_battle?

    unless in_pvp
      # Normal battle - call original
      return pvp_original_pbAttackPhase
    end

    # === PVP BATTLE: Just execute attack phase ===
    # RNG was already synced in command phase, no need to sync again

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-ATTACK", "Executing attack phase (RNG already synced)")
    end

    # Execute attack phase with synchronized RNG
    pvp_original_pbAttackPhase

    # Reset sync state after turn completes
    PvPActionSync.reset_sync_state if defined?(PvPActionSync)
    PvPRNGSync.reset_sync_state if defined?(PvPRNGSync)
    PvPSwitchSync.reset if defined?(PvPSwitchSync)
  end

  #-----------------------------------------------------------------------------
  # Switch In Between - Synchronize Pokemon switch choices when fainted
  #-----------------------------------------------------------------------------
  def pbSwitchInBetween(idxBattler, canCancel = false, canChooseCurrent = false)
    # If not in PvP battle, use original behavior
    unless defined?(PvPBattleState) && PvPBattleState.in_pvp_battle?
      return pvp_original_pbSwitchInBetween(idxBattler, canCancel, canChooseCurrent)
    end

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-SWITCH-PHASE", "=== SWITCH IN BETWEEN ===")
      MultiplayerDebug.info("PVP-SWITCH-PHASE", "  Battler Index: #{idxBattler}")
    end

    battler = @battlers[idxBattler]
    owner = pbGetOwnerFromBattlerIndex(idxBattler)

    # Determine if this is opponent's Pokemon
    is_opponent = false
    opponent_sid = PvPBattleState.opponent_sid

    if owner.is_a?(NPCTrainer) && owner.respond_to?(:id)
      # Check if this NPCTrainer is the opponent
      is_opponent = (owner.id.to_s == opponent_sid.to_s)
    end

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-SWITCH-PHASE", "  Owner: #{owner.class.name}")
      MultiplayerDebug.info("PVP-SWITCH-PHASE", "  Is Opponent: #{is_opponent}")
    end

    if is_opponent
      # OPPONENT'S POKEMON - Wait for their switch choice
      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-SWITCH-PHASE", "Waiting for opponent's switch choice...")
      end

      idxPartyNew = PvPSwitchSync.wait_for_switch(idxBattler, 120) if defined?(PvPSwitchSync)

      # Check if opponent forfeited (returns -1)
      if idxPartyNew == -1
        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("PVP-SWITCH-PHASE", "Opponent forfeited during switch - we win!")
        end
        pbDisplay(_INTL("Your opponent forfeited!"))
        return -1  # Signal no switch needed, battle ending
      elsif idxPartyNew.nil?
        # Timeout - fallback to auto-switch
        if defined?(MultiplayerDebug)
          MultiplayerDebug.error("PVP-SWITCH-PHASE", "Timeout! Using fallback auto-switch")
        end
        idxPartyNew = pvp_original_pbSwitchInBetween(idxBattler, canCancel, canChooseCurrent)
      else
        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("PVP-SWITCH-PHASE", "Received opponent's choice: party index #{idxPartyNew}")
        end
      end

      return idxPartyNew

    else
      # MY POKEMON - Get my choice and send it to opponent
      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-SWITCH-PHASE", "My Pokemon switching, choosing and broadcasting...")
      end

      begin
        idxPartyNew = pvp_original_pbSwitchInBetween(idxBattler, canCancel, canChooseCurrent)

        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("PVP-SWITCH-PHASE", "pbSwitchInBetween returned: #{idxPartyNew.inspect}")
        end

        if idxPartyNew >= 0
          if defined?(MultiplayerDebug)
            MultiplayerDebug.info("PVP-SWITCH-PHASE", "My choice: party index #{idxPartyNew}, sending to opponent...")
          end

          if defined?(PvPSwitchSync)
            PvPSwitchSync.send_switch_choice(idxBattler, idxPartyNew)
            if defined?(MultiplayerDebug)
              MultiplayerDebug.info("PVP-SWITCH-PHASE", "Switch choice sent successfully")
            end
          else
            if defined?(MultiplayerDebug)
              MultiplayerDebug.error("PVP-SWITCH-PHASE", "PvPSwitchSync not defined!")
            end
          end
        else
          if defined?(MultiplayerDebug)
            MultiplayerDebug.warn("PVP-SWITCH-PHASE", "No valid switch available (returned #{idxPartyNew})")
          end
        end

        return idxPartyNew
      rescue => e
        if defined?(MultiplayerDebug)
          MultiplayerDebug.error("PVP-SWITCH-PHASE", "Exception in MY switch: #{e.message}")
          MultiplayerDebug.error("PVP-SWITCH-PHASE", "Backtrace: #{e.backtrace.first(5).join('\n')}")
        end
        raise
      end
    end
  end

  #-----------------------------------------------------------------------------
  # pbOnActiveOne - Resync RNG before switch-in effects
  #-----------------------------------------------------------------------------
  def pbOnActiveOne(battler)
    if defined?(PvPBattleState) && PvPBattleState.in_pvp_battle?
      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-SWITCH-PHASE", "Switch-in effects for battler #{battler.index} (#{battler.pokemon.name})")
      end

      # CRITICAL: Resync RNG seed BEFORE switch-in effects
      # This ensures abilities, entry hazards, and items trigger identically
      # Skip at Turn 0 to preserve initial seed
      # ONLY resync when it's MY Pokemon switching in (to avoid double-sync race condition)
      # ALSO skip for voluntary switches (they don't need RNG sync, only forced switches when Pokemon faint)
      owner = pbGetOwnerFromBattlerIndex(battler.index)
      is_my_pokemon = owner && !owner.is_a?(NPCTrainer)  # My Pokemon = Player-owned, not NPCTrainer

      # Simple detection: Check if we're in the attack phase
      # Voluntary switches happen BEFORE attack phase (during command phase)
      # Forced switches happen AFTER attack phase (when Pokemon faint)
      is_in_attack_phase = defined?(@phase) && (@phase == :attack || @phase == 4)

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-SWITCH-PHASE", "  In attack phase: #{is_in_attack_phase}")
        MultiplayerDebug.info("PVP-SWITCH-PHASE", "  @phase: #{defined?(@phase) ? @phase : 'undefined'}")
      end

      # Only sync RNG for switches during/after attack phase (forced switches)
      # Skip sync for switches during command phase (voluntary switches)
      if defined?(PvPRNGSync) && @turnCount > 0 && is_my_pokemon && is_in_attack_phase
        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("PVP-SWITCH-PHASE", "Resyncing RNG before MY switch-in effects...")
        end

        # Use negative sync ID to avoid collision with turn numbers
        sync_id = -((@turnCount * 100) + battler.index + 1)

        if PvPBattleState.is_initiator?
          PvPRNGSync.sync_seed_as_initiator(self, sync_id)
        else
          success = PvPRNGSync.sync_seed_as_receiver(self, sync_id, 3)
          unless success
            if defined?(MultiplayerDebug)
              MultiplayerDebug.error("PVP-SWITCH-PHASE", "RNG resync failed before switch-in!")
            end
          end
        end

        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("PVP-SWITCH-PHASE", "RNG resynced (sync_id=#{sync_id})")
        end
      elsif defined?(PvPRNGSync) && @turnCount > 0 && !is_my_pokemon
        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("PVP-SWITCH-PHASE", "Opponent's switch-in, waiting for RNG resync from them...")
        end
        # Opponent will trigger the resync on their end
      end
    end

    # Call original (triggers entry hazards, abilities, etc.)
    pvp_original_pbOnActiveOne(battler)
  end

  #-----------------------------------------------------------------------------
  # pbRun - Handle forfeit in PvP battles
  #-----------------------------------------------------------------------------
  def pbRun(idxBattler, duringBattle = false)
    # If not in PvP battle, use original/coop behavior
    unless defined?(PvPBattleState) && PvPBattleState.in_pvp_battle?
      return pvp_original_pbRun(idxBattler, duringBattle)
    end

    battler = @battlers[idxBattler]

    # Only player's battlers can forfeit (not opponent's)
    if battler.opposes?
      return pvp_original_pbRun(idxBattler, duringBattle)
    end

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-FORFEIT", "Player chose to forfeit PvP battle")
    end

    # Broadcast forfeit to opponent
    battle_id = PvPBattleState.battle_id
    PvPForfeitSync.send_forfeit(battle_id)

    # Small delay to allow message to send
    sleep(0.05)

    # Display forfeit message
    pbDisplay(_INTL("{1} forfeited the battle!", pbPlayer.name))

    # Mark as loss (opponent wins)
    @decision = 2

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-FORFEIT", "Battle decision set to 2 (loss)")
    end

    return 1  # Return success (forfeit always succeeds)
  end
end

if defined?(MultiplayerDebug)
  MultiplayerDebug.info("PVP-ALIASES", "PvP battle system loaded (actions, switches, forfeit, phase aliases)")
end
