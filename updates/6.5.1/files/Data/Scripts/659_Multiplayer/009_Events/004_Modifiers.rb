#===============================================================================
# MODULE: Event System - Modifier Registry
#===============================================================================
# Pluggable architecture for challenge and reward modifiers.
# Each modifier is a self-contained registration with hooks.
#
# Usage:
#   EventModifierRegistry.register_challenge(:no_switching) { |ctx| ... }
#   EventModifierRegistry.execute_challenge(:no_switching, context) -> true/false
#   EventModifierRegistry.register_reward(:blessing) { |ctx| ... }
#   EventModifierRegistry.execute_reward(:blessing, context) -> value
#===============================================================================

module EventModifierRegistry
  TAG = "EVENT-MODS"

  # Challenge modifier definitions: { id => lambda }
  CHALLENGE_MODIFIERS = {}

  # Reward modifier definitions: { id => lambda }
  REWARD_MODIFIERS = {}

  # Modifier metadata for UI display
  MODIFIER_INFO = {}

  #---------------------------------------------------------------------------
  # Shiny Event Reward Pool (weighted selection)
  # Weight represents probability out of total pool (100)
  #---------------------------------------------------------------------------
  SHINY_REWARD_POOL = {
    "blessing" => {
      weight: 30,
      reward_type: :passive,
      tradeable: false,
      name: "Blessing",
      description: "x100 shiny chance for 30s on map entry"
    },
    "pity" => {
      weight: 30,
      reward_type: :end_of_event,
      tradeable: false,
      name: "Pity",
      description: "Eligible players: next encounter guaranteed shiny"
    },
    "shiny_egg" => {
      weight: 10,
      reward_type: :item,
      tradeable: true,
      name: "Shiny Egg",
      description: "100% shiny, base stage, <500 BST",
      icon: :POKEBALL  # Use pokeball icon for now
    },
    "fusion" => {
      weight: 15,
      reward_type: :end_of_event,
      tradeable: false,
      name: "Fusion",
      description: "Eligible players: next fusion has shiny part"
    },
    "squad_scaling" => {
      weight: 13,
      reward_type: :passive,
      tradeable: false,
      name: "Squad Scaling",
      description: "x1/x2/x3 shiny chance for 1/2/3 players in Squad"
    },
    "shiny_loot" => {
      weight: 1,
      reward_type: :item,
      tradeable: true,
      name: "Shiny Loot",
      description: "Shooting Star Charm - x1.5 final shiny chance (permanent)",
      icon: :POKEBALL  # Use pokeball icon for now
    },
    "shiny_legendary_egg" => {
      weight: 1,
      reward_type: :item,
      tradeable: true,
      name: "Shiny Legendary Egg",
      description: "500+ BST line, base stage, 100% shiny, can be legendaries",
      icon: :POKEBALL  # Use pokeball icon for now
    }
  }

  #---------------------------------------------------------------------------
  # Challenge Modifier Pool for Shiny Events
  #---------------------------------------------------------------------------
  SHINY_CHALLENGE_POOL = {
    "no_switching" => { weight: 15, name: "No Switching", description: "Cannot switch Pokemon during battle" },
    "fusion_only" => { weight: 10, name: "Fusion Only", description: "Only fused Pokemon in party allowed" },
    "mono_type" => { weight: 10, name: "Mono-Type", description: "All party Pokemon must share a common type" },
    "limited_party" => { weight: 15, name: "Limited Party", description: "Maximum 3 Pokemon allowed in party" },
    "one_chance" => { weight: 10, name: "One Chance", description: "Fail to catch a shiny = no more shinies this event" },
    "mono_ball" => { weight: 10, name: "Mono-Ball", description: "Can only use one type of Poke Ball during event" },
    "no_stalling" => { weight: 10, name: "No Stalling", description: "Cannot use healing moves" },
    "time_limit" => { weight: 5, name: "Time Limit", description: "Battle has a turn limit (2-5 turns)" },
    "status_immunity" => { weight: 5, name: "Status Immunity", description: "Shiny foes cannot suffer status effects" },
    "burning_clock" => { weight: 5, name: "Burning Clock", description: "All Pokemon lose 1/8 HP at end of each turn" },
    "weather_roulette" => { weight: 3, name: "Weather Roulette", description: "Weather changes randomly at end of each turn" },
    "stat_flux" => { weight: 2, name: "Stat Flux", description: "Random stat changes at end of each turn" }
  }

  module_function

  #---------------------------------------------------------------------------
  # Registration
  #---------------------------------------------------------------------------

  # Register a challenge modifier
  # Block receives context hash, returns true if action is allowed
  def register_challenge(id, info = {}, &block)
    id_str = id.to_s
    CHALLENGE_MODIFIERS[id_str] = block
    MODIFIER_INFO[id_str] = info.merge(type: :challenge)

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info(TAG, "Registered challenge modifier: #{id_str}")
    end
  end

  # Register a reward modifier
  # Block receives context hash, returns reward value/multiplier/item
  def register_reward(id, info = {}, &block)
    id_str = id.to_s
    REWARD_MODIFIERS[id_str] = block
    MODIFIER_INFO[id_str] = info.merge(type: :reward)

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info(TAG, "Registered reward modifier: #{id_str}")
    end
  end

  #---------------------------------------------------------------------------
  # Execution
  #---------------------------------------------------------------------------

  # Execute a challenge modifier check
  # Returns true if action is allowed, false if blocked
  def execute_challenge(id, context = {})
    id_str = id.to_s
    mod = CHALLENGE_MODIFIERS[id_str]
    return true unless mod  # Unknown modifier = allowed

    begin
      result = mod.call(context)
      return result
    rescue => e
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error(TAG, "Challenge #{id_str} error: #{e.message}")
      end
      return true  # On error, allow action
    end
  end

  # Execute a reward modifier
  # Returns reward value (multiplier, item, etc.) or nil
  def execute_reward(id, context = {})
    id_str = id.to_s
    mod = REWARD_MODIFIERS[id_str]
    return nil unless mod  # Unknown modifier = no reward

    begin
      result = mod.call(context)
      return result
    rescue => e
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error(TAG, "Reward #{id_str} error: #{e.message}")
      end
      return nil
    end
  end

  # Execute all active challenge modifiers for an action
  # Returns { allowed: bool, blockers: [modifier_ids] }
  def check_all_challenges(action, context = {})
    return { allowed: true, blockers: [] } unless defined?(EventSystem)

    blockers = []
    active_mods = EventSystem.active_challenge_modifiers

    active_mods.each do |mod_id|
      ctx = context.merge(action: action)
      unless execute_challenge(mod_id, ctx)
        blockers << mod_id
      end
    end

    { allowed: blockers.empty?, blockers: blockers }
  end

  # Execute all active reward modifiers and collect results
  # Returns array of { id: mod_id, result: value }
  def collect_all_rewards(context = {})
    return [] unless defined?(EventSystem)

    rewards = []
    active_mods = EventSystem.active_reward_modifiers

    active_mods.each do |mod_id|
      result = execute_reward(mod_id, context)
      if result
        rewards << { id: mod_id, result: result }
      end
    end

    rewards
  end

  #---------------------------------------------------------------------------
  # Info & Debug
  #---------------------------------------------------------------------------

  def get_modifier_info(id)
    MODIFIER_INFO[id.to_s]
  end

  def list_challenge_modifiers
    CHALLENGE_MODIFIERS.keys
  end

  def list_reward_modifiers
    REWARD_MODIFIERS.keys
  end

  #---------------------------------------------------------------------------
  # Pool-based Selection & Lookup
  #---------------------------------------------------------------------------

  # Get reward info from pool (for shiny events)
  def get_shiny_reward_info(id)
    SHINY_REWARD_POOL[id.to_s]
  end

  # Get challenge info from pool (for shiny events)
  def get_shiny_challenge_info(id)
    SHINY_CHALLENGE_POOL[id.to_s]
  end

  # List all shiny rewards with their info
  def list_shiny_rewards
    SHINY_REWARD_POOL.map do |id, info|
      { id: id, name: info[:name], weight: info[:weight], type: info[:reward_type] }
    end
  end

  # List all shiny challenges with their info
  def list_shiny_challenges
    SHINY_CHALLENGE_POOL.map do |id, info|
      { id: id, name: info[:name], weight: info[:weight] }
    end
  end

  # Weighted random selection from a pool
  def weighted_select(pool)
    total_weight = pool.values.sum { |info| info[:weight] }
    roll = rand(total_weight)

    cumulative = 0
    pool.each do |id, info|
      cumulative += info[:weight]
      return id if roll < cumulative
    end

    pool.keys.first  # Fallback
  end

  # Roll random rewards for a shiny event (1-2 rewards)
  def roll_shiny_rewards(count = 2)
    selected = []
    available = SHINY_REWARD_POOL.dup

    count.times do
      break if available.empty?
      id = weighted_select(available)
      selected << id
      available.delete(id)  # No duplicates
    end

    selected
  end

  # Roll random challenges for a shiny event (2-3 challenges)
  def roll_shiny_challenges(count = 3)
    selected = []
    available = SHINY_CHALLENGE_POOL.dup

    count.times do
      break if available.empty?
      id = weighted_select(available)
      selected << id
      available.delete(id)  # No duplicates
    end

    selected
  end

  # Check if a reward ID is valid
  def valid_shiny_reward?(id)
    SHINY_REWARD_POOL.key?(id.to_s)
  end

  # Check if a challenge ID is valid
  def valid_shiny_challenge?(id)
    SHINY_CHALLENGE_POOL.key?(id.to_s)
  end

  def debug_status
    puts "=" * 60
    puts "EventModifierRegistry Status"
    puts "=" * 60
    puts "Challenge modifiers registered: #{CHALLENGE_MODIFIERS.length}"
    CHALLENGE_MODIFIERS.keys.each { |k| puts "  - #{k}" }
    puts ""
    puts "Reward modifiers registered: #{REWARD_MODIFIERS.length}"
    REWARD_MODIFIERS.keys.each { |k| puts "  - #{k}" }
    puts ""
    puts "Shiny Reward Pool: #{SHINY_REWARD_POOL.length} rewards"
    SHINY_REWARD_POOL.each { |k, v| puts "  - #{k} (#{v[:weight]}%): #{v[:name]}" }
    puts ""
    puts "Shiny Challenge Pool: #{SHINY_CHALLENGE_POOL.length} challenges"
    SHINY_CHALLENGE_POOL.each { |k, v| puts "  - #{k} (#{v[:weight]}%): #{v[:name]}" }
    puts "=" * 60
  end
end

#===============================================================================
# Challenge Modifier Implementations
#===============================================================================

# No Switching - Cannot switch Pokemon during battle
EventModifierRegistry.register_challenge(:no_switching,
  name: "No Switching",
  description: "Cannot switch Pokemon during battle"
) do |ctx|
  ctx[:action] != :switch
end

# Fusion Only - Can only use fused Pokemon
EventModifierRegistry.register_challenge(:fusion_only,
  name: "Fusion Only",
  description: "Only fused Pokemon in party allowed"
) do |ctx|
  pokemon = ctx[:pokemon]
  next true unless pokemon  # No pokemon context = allow
  pokemon.respond_to?(:isFusion?) && pokemon.isFusion?
end

# Mono Type - All party Pokemon must share a type
EventModifierRegistry.register_challenge(:mono_type,
  name: "Mono-Type",
  description: "All party Pokemon must share a common type"
) do |ctx|
  party = ctx[:party]
  next true unless party  # No party context = allow

  # Find common type
  common_types = nil
  party.compact.each do |pkmn|
    pkmn_types = [pkmn.type1, pkmn.type2].compact
    if common_types.nil?
      common_types = pkmn_types
    else
      common_types = common_types & pkmn_types
    end
  end

  !common_types.nil? && !common_types.empty?
end

# Limited Party - Max 3 Pokemon in party
EventModifierRegistry.register_challenge(:limited_party,
  name: "Limited Party",
  description: "Maximum 3 Pokemon allowed in party"
) do |ctx|
  party = ctx[:party]
  next true unless party
  party.compact.length <= 3
end

# One Chance - Only one catch attempt per shiny encounter
EventModifierRegistry.register_challenge(:one_chance,
  name: "One Chance",
  description: "Fail to catch a shiny = no more shinies this event"
) do |ctx|
  next true unless ctx[:action] == :catch
  next true unless ctx[:target_shiny]  # Only applies to shiny targets

  # Check if already failed
  if defined?(ShinyEventModifiers)
    !ShinyEventModifiers.one_chance_failed?
  else
    true
  end
end

# Mono Ball - Can only use one type of Poke Ball
EventModifierRegistry.register_challenge(:mono_ball,
  name: "Mono-Ball",
  description: "Can only use one type of Poke Ball during event"
) do |ctx|
  next true unless ctx[:action] == :catch
  ball = ctx[:ball]
  next true unless ball

  if defined?(ShinyEventModifiers)
    current = ShinyEventModifiers.get_mono_ball_type
    if current.nil?
      # First ball used, will be set by the catch handler
      true
    else
      current == ball
    end
  else
    true
  end
end

# No Stalling - Cannot use healing moves
EventModifierRegistry.register_challenge(:no_stalling,
  name: "No Stalling",
  description: "Cannot use healing moves"
) do |ctx|
  ctx[:action] != :heal_move
end

# Time Limit - Battle must complete within turn limit
EventModifierRegistry.register_challenge(:time_limit,
  name: "Time Limit",
  description: "Battle has a turn limit (2-5 turns)"
) do |ctx|
  # This is enforced by battle system, not modifier check
  # Return true to allow action, battle system handles timeout
  true
end

# Status Immunity - Foe shinies cannot suffer status effects
EventModifierRegistry.register_challenge(:status_immunity,
  name: "Status Immunity",
  description: "Shiny foes cannot suffer status effects"
) do |ctx|
  # This is applied in battle damage calculation
  true
end

# Burning Clock - All active Pokemon lose 1/8 HP each turn
EventModifierRegistry.register_challenge(:burning_clock,
  name: "Burning Clock",
  description: "All Pokemon lose 1/8 HP at end of each turn"
) do |ctx|
  # This is applied in battle end-of-turn effects
  true
end

# Weather Roulette - Weather changes at end of each turn
EventModifierRegistry.register_challenge(:weather_roulette,
  name: "Weather Roulette",
  description: "Weather changes randomly at end of each turn"
) do |ctx|
  true
end

# Stat Flux - Random stat changes at end of turn
EventModifierRegistry.register_challenge(:stat_flux,
  name: "Stat Flux",
  description: "Random stat changes at end of each turn"
) do |ctx|
  true
end

#===============================================================================
# Reward Modifier Implementations
#===============================================================================
# Note: These are execution handlers. The randomness is in SELECTION of modifiers,
# not in their execution. Once a modifier is active, it should work consistently.
#===============================================================================

# Blessing - x100 shiny chance for 30s on map entry (passive, buff-based)
EventModifierRegistry.register_reward(:blessing,
  name: "Blessing",
  description: "x100 shiny chance for 30s on map entry",
  weight: 30,
  reward_type: :passive
) do |ctx|
  # Blessing grants a 30-second x100 buff when entering the event map
  { type: :blessing_buff, duration: 30, shiny_multiplier: 100 }
end

# Pity - Next encounter guaranteed shiny (end-of-event reward for eligible players)
EventModifierRegistry.register_reward(:pity,
  name: "Pity",
  description: "Eligible players: next encounter guaranteed shiny",
  weight: 30,
  reward_type: :end_of_event
) do |ctx|
  # Grants guaranteed shiny on next wild encounter (given at event end to eligible players)
  { type: :pity_shiny, guaranteed: true }
end

# Shiny Egg - 100% shiny, base stage, <500 BST (item reward)
EventModifierRegistry.register_reward(:shiny_egg,
  name: "Shiny Egg",
  description: "100% shiny, base stage, <500 BST",
  weight: 10,
  reward_type: :item,
  tradeable: true
) do |ctx|
  # Returns item data - actual egg generation handled by reward system
  { type: :item, item_type: :shiny_egg, bst_max: 500, shiny: true, base_stage: true, tradeable: true }
end

# Fusion - Next wild fusion has at least one shiny part (end-of-event reward)
EventModifierRegistry.register_reward(:fusion,
  name: "Fusion",
  description: "Eligible players: next fusion has shiny part",
  weight: 15,
  reward_type: :end_of_event
) do |ctx|
  # Grants shiny fusion buff (given at event end to eligible players)
  { type: :fusion_buff, shiny_part: true }
end

# Squad Scaling - Multiplied shiny chance based on squad size (passive, continuous)
EventModifierRegistry.register_reward(:squad_scaling,
  name: "Squad Scaling",
  description: "x1/x2/x3 shiny chance for 1/2/3 players in Squad",
  weight: 13,
  reward_type: :passive
) do |ctx|
  # Calculate multiplier based on current squad size
  multiplier = 1
  if defined?(MultiplayerClient)
    squad = MultiplayerClient.squad rescue nil
    if squad && squad[:members]
      multiplier = [squad[:members].length, 3].min  # Cap at x3
    end
  end
  { type: :multiplier, value: multiplier }
end

# Shiny Loot - Shooting Star Charm (permanent item, x1.5 shiny chance while owned)
EventModifierRegistry.register_reward(:shiny_loot,
  name: "Shiny Loot",
  description: "Shooting Star Charm - x1.5 final shiny chance (permanent)",
  weight: 1,
  reward_type: :item,
  tradeable: true
) do |ctx|
  # Returns item data for Shooting Star Charm
  { type: :item, item_type: :shooting_star_charm, item_id: :SHOOTINGSTARCHARM, tradeable: true, rare: true }
end

# Shiny Legendary Egg - 500+ BST, base stage, 100% shiny, can be legendaries (item reward)
EventModifierRegistry.register_reward(:shiny_legendary_egg,
  name: "Shiny Legendary Egg",
  description: "500+ BST line, base stage, 100% shiny, can be legendaries",
  weight: 1,
  reward_type: :item,
  tradeable: true
) do |ctx|
  # Returns item data - uses K-Eggs system for generation
  { type: :item, item_type: :shiny_legendary_egg, bst_min: 500, shiny: true, base_stage: true,
    include_legendaries: true, tradeable: true, rare: true }
end

#===============================================================================
# Module loaded
#===============================================================================
if defined?(MultiplayerDebug)
  MultiplayerDebug.info("EVENT-MODS", "=" * 60)
  MultiplayerDebug.info("EVENT-MODS", "153_Event_Modifiers.rb loaded")
  MultiplayerDebug.info("EVENT-MODS", "Modifier registry initialized")
  MultiplayerDebug.info("EVENT-MODS", "  Challenge modifiers: #{EventModifierRegistry::CHALLENGE_MODIFIERS.length}")
  MultiplayerDebug.info("EVENT-MODS", "  Reward modifiers: #{EventModifierRegistry::REWARD_MODIFIERS.length}")
  MultiplayerDebug.info("EVENT-MODS", "=" * 60)
end
