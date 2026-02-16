#===============================================================================
# MODULE: Event System - Reward Distribution
#===============================================================================
# Handles participant tracking, reward distribution, and item generation
# for server events. Works with K-Eggs system for egg generation.
#
# Usage:
#   EventRewards.record_shiny_encounter(event_id, player_id, :fainted/:caught)
#   EventRewards.eligible_for_rewards?(event_id, player_id)
#   EventRewards.distribute_rewards(event_id)
#   EventRewards.give_item_reward(player, reward_data)
#===============================================================================

module EventRewards
  TAG = "EVENT-REWARDS"

  # Participant tracking: { event_id => { player_id => { fainted: n, caught: n } } }
  @participants = {}
  @participants_mutex = Mutex.new

  # Active passive buffs: { player_id => [{ buff_type, expires_at, data }] }
  @active_buffs = {}
  @buffs_mutex = Mutex.new

  # Track one-time rewards that have been used: { player_id => { blessing: true, ... } }
  @used_rewards = {}
  @used_rewards_mutex = Mutex.new

  module_function

  #---------------------------------------------------------------------------
  # Participant Tracking
  #---------------------------------------------------------------------------

  # Record a shiny encounter (fainted or caught)
  def record_shiny_encounter(event_id, player_id, outcome)
    return unless event_id && player_id

    @participants_mutex.synchronize do
      @participants[event_id] ||= {}
      @participants[event_id][player_id] ||= { fainted: 0, caught: 0 }

      case outcome
      when :fainted
        @participants[event_id][player_id][:fainted] += 1
      when :caught
        @participants[event_id][player_id][:caught] += 1
      end

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info(TAG, "Recorded #{outcome} for player #{player_id} in event #{event_id}")
      end
    end
  end

  # Check if player is eligible for rewards (fainted or caught at least one shiny)
  def eligible_for_rewards?(event_id, player_id)
    @participants_mutex.synchronize do
      return false unless @participants[event_id]
      return false unless @participants[event_id][player_id]

      data = @participants[event_id][player_id]
      data[:fainted] > 0 || data[:caught] > 0
    end
  end

  # Get participation stats for a player
  def get_participation(event_id, player_id)
    @participants_mutex.synchronize do
      return { fainted: 0, caught: 0 } unless @participants[event_id]
      @participants[event_id][player_id] || { fainted: 0, caught: 0 }
    end
  end

  # Get all eligible participants for an event
  def get_eligible_participants(event_id)
    @participants_mutex.synchronize do
      return [] unless @participants[event_id]

      @participants[event_id].select do |player_id, data|
        data[:fainted] > 0 || data[:caught] > 0
      end.keys
    end
  end

  # Clear participation data for an event (call when event ends)
  def clear_event(event_id)
    @participants_mutex.synchronize do
      @participants.delete(event_id)
    end
  end

  #---------------------------------------------------------------------------
  # Passive Buff Management
  #---------------------------------------------------------------------------

  # Add a passive buff to a player
  def add_buff(player_id, buff_type, duration, data = {})
    expires_at = Time.now + duration

    @buffs_mutex.synchronize do
      @active_buffs[player_id] ||= []
      @active_buffs[player_id] << {
        type: buff_type,
        expires_at: expires_at,
        data: data,
        active: true
      }
    end

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info(TAG, "Added #{buff_type} buff for player #{player_id} (#{duration}s)")
    end
  end

  # Check if player has an active buff of a specific type
  def has_buff?(player_id, buff_type)
    cleanup_expired_buffs(player_id)

    @buffs_mutex.synchronize do
      return false unless @active_buffs[player_id]
      @active_buffs[player_id].any? { |b| b[:type] == buff_type && b[:active] }
    end
  end

  # Get buff data for a specific type
  def get_buff(player_id, buff_type)
    cleanup_expired_buffs(player_id)

    @buffs_mutex.synchronize do
      return nil unless @active_buffs[player_id]
      @active_buffs[player_id].find { |b| b[:type] == buff_type && b[:active] }
    end
  end

  # Consume a single-use buff (like Pity)
  def consume_buff(player_id, buff_type)
    @buffs_mutex.synchronize do
      return false unless @active_buffs[player_id]

      buff = @active_buffs[player_id].find { |b| b[:type] == buff_type && b[:active] }
      if buff
        buff[:active] = false
        return true
      end
      false
    end
  end

  # Clean up expired buffs for a player
  def cleanup_expired_buffs(player_id)
    now = Time.now

    @buffs_mutex.synchronize do
      return unless @active_buffs[player_id]
      @active_buffs[player_id].reject! { |b| b[:expires_at] < now }
    end
  end

  # Clear all buffs for a player
  def clear_buffs(player_id)
    @buffs_mutex.synchronize do
      @active_buffs.delete(player_id)
    end
  end

  #---------------------------------------------------------------------------
  # One-Time Reward Tracking (for rewards like Blessing that shouldn't repeat)
  #---------------------------------------------------------------------------

  # Mark a reward as used for a player
  def mark_reward_used(player_id, reward_type)
    @used_rewards_mutex.synchronize do
      @used_rewards[player_id] ||= {}
      @used_rewards[player_id][reward_type] = true
    end
  end

  # Check if a reward was already used
  def reward_used?(player_id, reward_type)
    @used_rewards_mutex.synchronize do
      return false unless @used_rewards[player_id]
      @used_rewards[player_id][reward_type] == true
    end
  end

  # Clear used rewards for a player (call when event ends or player leaves)
  def clear_used_rewards(player_id)
    @used_rewards_mutex.synchronize do
      @used_rewards.delete(player_id)
    end
  end

  # Clear all used rewards (call when event ends)
  def clear_all_used_rewards
    @used_rewards_mutex.synchronize do
      @used_rewards.clear
    end
  end

  #---------------------------------------------------------------------------
  # Reward Distribution
  #---------------------------------------------------------------------------

  # Distribute rewards to all eligible participants
  # Returns { distributed: n, results: [{ player_id, rewards: [...] }] }
  def distribute_rewards(event_id)
    return { distributed: 0, results: [] } unless defined?(EventSystem)

    event = EventSystem.active_events[event_id]
    return { distributed: 0, results: [], error: "Event not found" } unless event

    eligible = get_eligible_participants(event_id)
    return { distributed: 0, results: [], error: "No eligible participants" } if eligible.empty?

    reward_modifiers = event[:reward_modifiers] || []
    return { distributed: 0, results: [], error: "No reward modifiers" } if reward_modifiers.empty?

    results = []

    eligible.each do |player_id|
      player_rewards = []

      reward_modifiers.each do |mod_id|
        reward_info = EventModifierRegistry.get_shiny_reward_info(mod_id)
        next unless reward_info

        # Item rewards are given at event end
        if reward_info[:reward_type] == :item
          player_rewards << {
            id: mod_id,
            name: reward_info[:name],
            type: :item,
            data: EventModifierRegistry.execute_reward(mod_id, { player_id: player_id })
          }
        end
      end

      results << { player_id: player_id, rewards: player_rewards }
    end

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info(TAG, "Distributed rewards to #{results.length} participants")
    end

    { distributed: results.length, results: results }
  end

  #---------------------------------------------------------------------------
  # Item Reward Generation (uses K-Eggs patterns)
  #---------------------------------------------------------------------------

  # Give an item reward to the current player
  # reward_data should have: { item_type, bst_min/max, shiny, base_stage, etc. }
  def give_item_reward(reward_data)
    return { success: false, error: "No reward data" } unless reward_data

    case reward_data[:item_type]
    when :shiny_egg
      give_shiny_egg(reward_data)
    when :shiny_legendary_egg
      give_shiny_legendary_egg(reward_data)
    when :shooting_star_charm
      give_shooting_star_charm(reward_data)
    else
      { success: false, error: "Unknown item type: #{reward_data[:item_type]}" }
    end
  end

  # Generate and give a shiny egg (<500 BST, base stage)
  def give_shiny_egg(reward_data)
    begin
      bst_max = reward_data[:bst_max] || 500

      # Find eligible Pokemon (base stage, <500 BST)
      candidates = []
      (1..NB_POKEMON).each do |i|
        species = GameData::Species.get(i) rescue next
        bst = calcBaseStatsSum(species.id) rescue 0
        next if bst >= bst_max

        # Check if base stage (no prevolutions)
        # A base stage Pokemon typically has no baby form and isn't an evolution
        evolutions = species.evolutions rescue []
        has_prevo = species.respond_to?(:get_previous_species) ? species.get_previous_species != species.id : false

        # Skip if it has a previous evolution (not base stage)
        next if has_prevo

        candidates << { species: species.id, bst: bst, catch_rate: species.catch_rate }
      end

      return { success: false, error: "No eligible Pokemon found" } if candidates.empty?

      # Weighted selection by catch rate
      total_weight = candidates.sum { |c| c[:catch_rate] }
      roll = rand(total_weight)
      cumulative = 0

      selected = nil
      candidates.each do |c|
        cumulative += c[:catch_rate]
        if roll < cumulative
          selected = c[:species]
          break
        end
      end

      selected ||= candidates.first[:species]

      # Create the Pokemon
      pokemon = Pokemon.new(selected, 1)
      pokemon.shiny = true  # Force shiny

      # Make it an egg
      pokemon.name = _INTL("Egg")
      pokemon.steps_to_hatch = pokemon.species_data.hatch_steps rescue 5120
      pokemon.hatched_map = 0
      pokemon.obtain_method = 1
      pokemon.obtain_text = "Shiny Event Egg"
      pokemon.time_form_set = nil
      pokemon.form = 0 if pokemon.isSpecies?(:SHAYMIN)
      pokemon.heal

      # Give to player
      pbAddPokemon(pokemon, 1, true, true) if defined?(pbAddPokemon)

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info(TAG, "Gave Shiny Egg: #{selected}")
      end

      { success: true, pokemon: selected, type: :shiny_egg }
    rescue => e
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error(TAG, "Shiny egg error: #{e.message}")
      end
      { success: false, error: e.message }
    end
  end

  # Generate and give a shiny legendary egg (500+ BST, can be legendaries)
  def give_shiny_legendary_egg(reward_data)
    begin
      bst_min = reward_data[:bst_min] || 500

      # Find eligible Pokemon (base stage, 500+ BST, including legendaries)
      candidates = []

      # First try legendaries
      if defined?(LEGENDARIES_LIST) && LEGENDARIES_LIST.is_a?(Array)
        LEGENDARIES_LIST.each do |legendary_id|
          species = GameData::Species.get(legendary_id) rescue next
          bst = calcBaseStatsSum(species.id) rescue 0
          next if bst < bst_min
          candidates << { species: species.id, bst: bst, catch_rate: species.catch_rate }
        end
      end

      # Also include high BST non-legendaries
      (1..NB_POKEMON).each do |i|
        species = GameData::Species.get(i) rescue next
        bst = calcBaseStatsSum(species.id) rescue 0
        next if bst < bst_min

        # Skip if already in candidates
        next if candidates.any? { |c| c[:species] == species.id }

        # Check if base stage
        has_prevo = species.respond_to?(:get_previous_species) ? species.get_previous_species != species.id : false
        next if has_prevo

        candidates << { species: species.id, bst: bst, catch_rate: species.catch_rate }
      end

      return { success: false, error: "No eligible Pokemon found" } if candidates.empty?

      # Weighted selection (lower catch rate = rarer = lower weight, so more valuable)
      # Invert catch rate for selection (rarer Pokemon more likely)
      max_catch = candidates.map { |c| c[:catch_rate] }.max
      weighted = candidates.map { |c| { species: c[:species], weight: max_catch - c[:catch_rate] + 3 } }

      total_weight = weighted.sum { |c| c[:weight] }
      roll = rand(total_weight)
      cumulative = 0

      selected = nil
      weighted.each do |c|
        cumulative += c[:weight]
        if roll < cumulative
          selected = c[:species]
          break
        end
      end

      selected ||= candidates.first[:species]

      # Create the Pokemon
      pokemon = Pokemon.new(selected, 1)
      pokemon.shiny = true  # Force shiny

      # Make it an egg
      pokemon.name = _INTL("Egg")
      pokemon.steps_to_hatch = pokemon.species_data.hatch_steps rescue 10240
      pokemon.hatched_map = 0
      pokemon.obtain_method = 1
      pokemon.obtain_text = "Legendary Shiny Event Egg"
      pokemon.time_form_set = nil
      pokemon.form = 0 if pokemon.isSpecies?(:SHAYMIN)
      pokemon.heal

      # Give to player
      pbAddPokemon(pokemon, 1, true, true) if defined?(pbAddPokemon)

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info(TAG, "Gave Shiny Legendary Egg: #{selected}")
      end

      { success: true, pokemon: selected, type: :shiny_legendary_egg }
    rescue => e
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error(TAG, "Legendary egg error: #{e.message}")
      end
      { success: false, error: e.message }
    end
  end

  # Give a Shooting Star Charm item
  def give_shooting_star_charm(reward_data)
    begin
      item_id = reward_data[:item_id] || :SHOOTINGSTARCHARM

      # Check if item exists, if not use a placeholder
      if defined?(GameData::Item) && GameData::Item.exists?(item_id)
        pbReceiveItem(item_id) if defined?(pbReceiveItem)
        { success: true, item: item_id, type: :shooting_star_charm }
      else
        # Item doesn't exist yet - give a message
        if defined?(pbMessage)
          pbMessage(_INTL("You would receive a Shooting Star Charm, but the item isn't registered yet!"))
        end
        { success: false, error: "Item not registered: #{item_id}" }
      end
    rescue => e
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error(TAG, "Shooting Star Charm error: #{e.message}")
      end
      { success: false, error: e.message }
    end
  end

  #---------------------------------------------------------------------------
  # Passive Reward Application (called during gameplay)
  #---------------------------------------------------------------------------

  # Apply blessing buff on map entry (call from map transfer hooks or UI update)
  # Only grants ONCE per event - does not renew after expiration
  # silent: true to suppress chat message
  def apply_blessing_on_map_entry(player_id, silent = false)
    return unless defined?(EventSystem)
    return unless EventSystem.has_reward_modifier?("blessing")

    # Check if blessing was already used this event (one-time only)
    return if reward_used?(player_id, :blessing)

    # Check if already has an active blessing buff
    existing = get_buff(player_id, :blessing)
    if existing && existing[:active]
      remaining = (existing[:expires_at] - Time.now).to_i rescue 0
      return if remaining > 0  # Still active, don't re-grant
    end

    # Mark blessing as used (won't grant again even after expiration)
    mark_reward_used(player_id, :blessing)

    # Add 30-second shiny buff (x100 multiplier)
    add_buff(player_id, :blessing, 30, { shiny_multiplier: 100 })

    # Show message on activation
    if !silent && defined?(ChatMessages)
      ChatMessages.add_message("Global", "SYSTEM", "System", "Blessing activated! x100 shiny chance for 30 seconds!")
    end
  end

  # Check if pity reward should trigger (guaranteed shiny on next encounter)
  def should_trigger_pity?(player_id)
    has_buff?(player_id, :pity)
  end

  # Consume pity buff after triggering
  def consume_pity(player_id)
    consume_buff(player_id, :pity)
  end

  # Check if fusion buff is active (next fusion has shiny part)
  def should_trigger_fusion_shiny?(player_id)
    has_buff?(player_id, :fusion_shiny)
  end

  # Consume fusion buff after triggering
  def consume_fusion_shiny(player_id)
    consume_buff(player_id, :fusion_shiny)
  end

  # Get squad scaling multiplier
  def get_squad_scaling_multiplier
    return 1 unless defined?(EventSystem)
    return 1 unless EventSystem.has_reward_modifier?("squad_scaling")

    multiplier = 1
    if defined?(MultiplayerClient)
      squad = MultiplayerClient.squad rescue nil
      if squad && squad[:members]
        multiplier = [squad[:members].length, 3].min  # Cap at x3
      end
    end

    multiplier
  end

  # Check if player has Shooting Star Charm (permanent x1.5 multiplier)
  def has_shooting_star_charm?
    return false unless defined?($bag) || defined?($PokemonBag)

    bag = $bag || $PokemonBag rescue nil
    return false unless bag

    # Check for the charm item
    bag.has?(:SHOOTINGSTARCHARM) rescue false
  end

  #---------------------------------------------------------------------------
  # Debug
  #---------------------------------------------------------------------------

  def debug_status
    puts "=" * 60
    puts "EventRewards Status"
    puts "=" * 60

    puts "Participants by event:"
    @participants_mutex.synchronize do
      @participants.each do |event_id, players|
        puts "  Event #{event_id}: #{players.length} participants"
        players.each do |player_id, data|
          puts "    #{player_id}: fainted=#{data[:fainted]}, caught=#{data[:caught]}"
        end
      end
    end

    puts ""
    puts "Active buffs:"
    @buffs_mutex.synchronize do
      @active_buffs.each do |player_id, buffs|
        active = buffs.select { |b| b[:active] }
        puts "  #{player_id}: #{active.length} active buffs"
        active.each do |b|
          remaining = (b[:expires_at] - Time.now).to_i
          puts "    #{b[:type]}: #{remaining}s remaining"
        end
      end
    end

    puts "=" * 60
  end
end

#===============================================================================
# Module loaded
#===============================================================================
if defined?(MultiplayerDebug)
  MultiplayerDebug.info("EVENT-REWARDS", "=" * 60)
  MultiplayerDebug.info("EVENT-REWARDS", "157_Event_Rewards.rb loaded")
  MultiplayerDebug.info("EVENT-REWARDS", "Reward distribution system ready")
  MultiplayerDebug.info("EVENT-REWARDS", "  EventRewards.record_shiny_encounter(event_id, player_id, outcome)")
  MultiplayerDebug.info("EVENT-REWARDS", "  EventRewards.eligible_for_rewards?(event_id, player_id)")
  MultiplayerDebug.info("EVENT-REWARDS", "  EventRewards.distribute_rewards(event_id)")
  MultiplayerDebug.info("EVENT-REWARDS", "  EventRewards.give_item_reward(reward_data)")
  MultiplayerDebug.info("EVENT-REWARDS", "=" * 60)
end
