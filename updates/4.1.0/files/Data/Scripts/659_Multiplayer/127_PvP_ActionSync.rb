# ===========================================
# File: 127_PvP_ActionSync.rb
# Purpose: PvP Battle Action Synchronization
# Phase: 5 - Action Synchronization
# ===========================================
# Handles collection, serialization, exchange, and synchronization of player
# battle actions between both PvP participants.
# Adapted from CoopActionSync (021_Coop_ActionSync.rb) for PvP battles.
#
# CRITICAL: Target Index Mirroring for PvP
# =========================================
# In PvP battles, each player sees themselves as "side 0" (even indices: 0, 2, 4...)
# and the opponent as "side 1" (odd indices: 1, 3, 5...).
#
# Example 2v2 battle layout:
#   Client A sees: [0]=Lugia(mine), [1]=Bidoof(opp), [2]=Garchomp(mine), [3]=Charmander(opp)
#   Client B sees: [0]=Bidoof(mine), [1]=Lugia(opp), [2]=Charmander(mine), [3]=Garchomp(opp)
#
# When Client A targets Charmander (index 3), we must translate:
#   - Client A's index 3 (opponent's second Pokemon)
#   - = Client B's index 2 (their own second Pokemon)
#
# Translation formula: swap even<->odd within the same "slot pair"
#   Index 0 <-> Index 1 (first slot on each side)
#   Index 2 <-> Index 3 (second slot on each side)
#   Index 4 <-> Index 5 (third slot on each side)
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
  # In PvP, each player sees themselves at even indices and opponent at odd.
  # When sending to opponent, their even indices are our odd indices and vice versa.
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
      move_priority = choice[4] if choice.length > 4  # Priority calculated in pbCalculatePriority
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
      move_priority = serialized_choice[4] if serialized_choice.length > 4  # Priority from opponent

      # Get the actual move object from the battler
      if battler && battler.moves && move_index && move_index < battler.moves.length
        move_object = battler.moves[move_index]
        # Include priority in reconstructed choice to ensure consistent turn order
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
        # Store with the MIRRORED index so opponent knows which of THEIR battlers this targets
        # Actually, we store our battler index and mirror it when opponent applies
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
  # Used when only one action needs to be sent
  #-----------------------------------------------------------------------------
  def self.extract_my_action(battle)
    actions = extract_my_actions(battle)
    return nil unless actions && !actions.empty?

    # Return the first action found
    actions.values.first
  end

  #-----------------------------------------------------------------------------
  # Wait for opponent's actions and apply them to battle
  # Supports 1v1, 2v2, and 3v3 battles
  #-----------------------------------------------------------------------------
  def self.wait_for_opponent_action(battle, timeout_seconds = 120)
    return false unless defined?(PvPBattleState)
    return false unless PvPBattleState.in_pvp_battle?

    battle_id = PvPBattleState.battle_id
    turn_num = battle.turnCount + 1  # Same as coop: use next turn number

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
      # @opponent_choice can be either:
      # - A Hash { battler_idx => choice } for multi-battler battles
      # - An Array [action_type, ...] for legacy single-battler format
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
  # Handles both legacy single-action format and new multi-action format
  #-----------------------------------------------------------------------------
  def self.apply_opponent_actions(battle, opponent_data)
    if opponent_data.is_a?(Hash)
      # New format: { battler_idx => choice }
      # The battler_idx is from OPPONENT'S perspective, so we need to mirror it
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
      # Opponent's battlers are at odd indices: 1, 3, 5...
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
  # actions = { battler_idx => serialized_choice }
  #-----------------------------------------------------------------------------
  def self.send_actions(battle_id, turn_num, actions)
    begin
      # Serialize actions using SafeJSON (no Marshal for security)
      # Send as hash: { turn: N, actions: { idx => choice, ... } }
      data = {
        :turn => turn_num,
        :actions => actions
      }

      # Use SafeJSON instead of Marshal for security
      json_str = SafeJSON.dump(data)

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-ACTION", "Serialized #{actions.size} actions with SafeJSON: #{json_str.length} chars")
      end

      # Send to opponent
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
    # Wrap single choice in actions hash format
    send_actions(battle_id, turn_num, { 0 => choice })
  end

  #-----------------------------------------------------------------------------
  # Receive opponent's actions from network
  # Handles both new format (:actions hash) and legacy format (:choice array)
  #-----------------------------------------------------------------------------
  def self.receive_action(battle_id, json_data)
    begin
      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-ACTION-NET", "Receiving action data: #{json_data.to_s.length} chars")
      end

      # Deserialize action using SafeJSON (no Marshal for security)
      data = SafeJSON.load(json_data.to_s)

      unless data.is_a?(Hash)
        raise "Decoded action data is not a Hash (got #{data.class})"
      end

      turn = data[:turn]

      # Handle both new format (:actions) and legacy format (:choice)
      actions_data = nil
      if data[:actions]
        # New format: { turn: N, actions: { idx => choice, ... } }
        actions_data = data[:actions]
        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("PVP-ACTION-NET", "Parsed #{actions_data.size} actions for turn #{turn}")
        end
      elsif data[:choice]
        # Legacy format: { turn: N, choice: [...] }
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
