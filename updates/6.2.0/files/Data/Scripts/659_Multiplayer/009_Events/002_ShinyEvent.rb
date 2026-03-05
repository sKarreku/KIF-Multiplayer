#===============================================================================
# MODULE: Event System - Shiny Event Hooks
#===============================================================================
# Hooks into the shiny? calculation to apply event multipliers.
# Uses $PokemonSystem.shinyodds which is the base shiny threshold (XOR-based).
#
# Base shiny calculation (in 014_Pokemon/001_Pokemon.rb):
#   d = (personalID ^ owner.id) bits -> d < shinyodds = shiny
#
# Event multiplier: Temporarily increase shinyodds during calculation.
#===============================================================================

class Pokemon
  # Store original shiny? method if not already aliased
  unless method_defined?(:event_original_shiny?)
    alias event_original_shiny? shiny?
  end

  # Override shiny? to apply event multipliers and reward modifiers
  def shiny?
    # If shiny is already cached (not nil), return it
    # This prevents re-rolling once a Pokemon has been determined
    return @shiny unless @shiny.nil?

    # IMPORTANT: Only apply event bonuses to NEWLY CREATED Pokemon
    # Don't apply to Pokemon that were obtained before the event started
    # Check if we should apply event modifiers (active event + on event map + new Pokemon)
    on_event_map = should_apply_event_bonuses? && is_newly_created_pokemon?

    # Check for Pity buff (guaranteed shiny, end-of-event reward for eligible players)
    # Only triggers if player received the buff from /giveeventrewards
    if on_event_map && defined?(EventRewards) && EventRewards.has_buff?(get_player_id, :pity)
      EventRewards.consume_buff(get_player_id, :pity)
      update_ui_modifier_state("pity", :inactive)
      log_shiny_reward("Pity triggered - guaranteed shiny!")
      @shiny = true
      return true
    end

    # Calculate total multiplier from various sources (only if on event map)
    total_multiplier = on_event_map ? calculate_shiny_multiplier : 1

    if total_multiplier > 1
      # Temporarily boost shinyodds for this calculation
      original_odds = $PokemonSystem.shinyodds

      # Calculate boosted odds (capped at 65535 to prevent overflow)
      boosted_odds = [original_odds * total_multiplier, 65535].min.to_i

      # Apply boosted odds temporarily
      $PokemonSystem.shinyodds = boosted_odds

      # Run original calculation with boosted odds
      result = event_original_shiny?

      # Restore original odds
      $PokemonSystem.shinyodds = original_odds

      # Log if shiny was obtained during event
      if result && defined?(MultiplayerDebug)
        MultiplayerDebug.info("EVENT-SHINY", "Shiny rolled with x#{total_multiplier} boost! (odds: #{boosted_odds})")
      end

      return result
    end

    # No multipliers, use normal calculation
    event_original_shiny?
  end

  private

  # Calculate total shiny multiplier from all sources
  def calculate_shiny_multiplier
    multiplier = 1.0

    # Base event multiplier
    if defined?(EventSystem) && EventSystem.has_active_event?("shiny")
      event_mult = EventSystem.get_modifier_multiplier("shiny_multiplier", "shiny")
      multiplier *= event_mult if event_mult > 1
    end

    # Blessing buff (x100 for 30s on map entry) - passive reward
    if defined?(EventRewards) && EventRewards.has_buff?(get_player_id, :blessing)
      multiplier *= 100
      update_ui_modifier_state("blessing", :active)
      log_shiny_reward("Blessing buff active - x100 multiplier applied")
    end

    # Squad Scaling reward (x1/x2/x3 based on squad size)
    if defined?(EventRewards)
      squad_mult = EventRewards.get_squad_scaling_multiplier
      if squad_mult > 1
        multiplier *= squad_mult
        update_ui_modifier_state("squad_scaling", :active)
      end
    end

    # Shooting Star Charm (permanent x1.5 when owned)
    if defined?(EventRewards) && EventRewards.has_shooting_star_charm?
      multiplier *= 1.5
    end

    multiplier.to_i.clamp(1, 1000)  # Cap at 1000x to prevent overflow (allows x100 blessing + x10 event)
  end

  # Get current player ID for buff lookups
  def get_player_id
    if defined?(MultiplayerClient)
      MultiplayerClient.instance_variable_get(:@player_name) rescue "local"
    else
      "local"
    end
  end

  # Update UI modifier state
  def update_ui_modifier_state(mod_id, state)
    if defined?(EventUIManager)
      case state
      when :active
        EventUIManager.activate_modifier(mod_id)
      when :inactive
        EventUIManager.deactivate_modifier(mod_id)
      end
    end
  end

  # Log shiny reward event
  def log_shiny_reward(message)
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("EVENT-SHINY", message)
    end
  end

  # Check if we should apply event bonuses (active event + on event map)
  def should_apply_event_bonuses?
    return false unless defined?(EventSystem)
    return false unless EventSystem.has_active_event?("shiny")

    event = EventSystem.primary_event
    return false unless event

    # Global event = always apply
    return true if event[:map] == "global" || event[:map].to_s == "0"

    # Check if player is on the event map
    return false unless defined?($game_map) && $game_map

    current_map = $game_map.map_id
    event_map = event[:map].to_i rescue 0
    return true if event_map == 0  # Global

    current_map == event_map
  end

  # Check if this Pokemon is "newly created" (during current event)
  # This prevents applying event bonuses to Pokemon obtained before the event
  def is_newly_created_pokemon?
    return true unless defined?(EventSystem)

    event = EventSystem.primary_event
    return true unless event  # No event = default behavior

    # If Pokemon has a time_received attribute, check against event start
    if respond_to?(:timeReceived) && timeReceived
      event_start = event[:start_time].to_i
      pokemon_time = timeReceived.to_i rescue 0
      return pokemon_time >= event_start
    end

    # Alternative: check obtain_time (some versions use this)
    if respond_to?(:obtain_time) && obtain_time
      event_start = event[:start_time].to_i
      pokemon_time = obtain_time.to_i rescue 0
      return pokemon_time >= event_start
    end

    # If we can't determine when the Pokemon was obtained,
    # check if we're in a wild battle context (newly generated)
    if defined?($PokemonTemp) && $PokemonTemp
      in_battle = $PokemonTemp.respond_to?(:in_battle) ? $PokemonTemp.in_battle : false
      # If in battle and this appears to be wild Pokemon, treat as new
      return true if in_battle
    end

    # Default: assume it's a new Pokemon if we can't determine otherwise
    # (This is the safest assumption during normal gameplay when
    # encountering wild Pokemon)
    true
  end
end

#===============================================================================
# Challenge Modifier Effects for Shiny Events
#===============================================================================
module ShinyEventModifiers
  TAG = "SHINY-MODS"

  # Mono-ball tracking (for mono_ball modifier)
  @mono_ball_type = nil

  # Catch attempt tracking (for one_chance modifier)
  @catch_attempted_this_battle = false

  # Failed shiny catch tracking (for one_chance modifier)
  @one_chance_failed = false

  module_function

  #---------------------------------------------------------------------------
  # Check if an action is allowed given active challenge modifiers
  #---------------------------------------------------------------------------
  def action_allowed?(action, context = {})
    return true unless defined?(EventSystem)
    return true unless EventSystem.has_active_event?("shiny")

    case action
    when :switch
      # No Switching modifier
      if EventSystem.has_challenge_modifier?("no_switching")
        return false
      end

    when :heal_move
      # No Stalling modifier prevents healing moves
      if EventSystem.has_challenge_modifier?("no_stalling")
        return false
      end

    when :catch
      # Mono Ball modifier - only one ball type allowed
      if EventSystem.has_challenge_modifier?("mono_ball")
        ball = context[:ball]
        if @mono_ball_type.nil?
          @mono_ball_type = ball  # First ball used sets the type
        elsif @mono_ball_type != ball
          return false  # Different ball type not allowed
        end
      end

      # One Chance modifier - fail a shiny catch = no more shinies
      if EventSystem.has_challenge_modifier?("one_chance")
        if @one_chance_failed
          return false  # Already failed a shiny catch
        end
      end
    end

    true
  end

  #---------------------------------------------------------------------------
  # Party Validation for Modifier Requirements
  #---------------------------------------------------------------------------

  # Check if party meets Fusion-Only requirement
  def party_meets_fusion_requirement?(party)
    return true unless defined?(EventSystem)
    return true unless EventSystem.has_challenge_modifier?("fusion_only")

    party.compact.all? do |pkmn|
      pkmn.respond_to?(:isFusion?) && pkmn.isFusion?
    end
  end

  # Check if party meets Limited Party requirement (max 3)
  def party_meets_size_requirement?(party)
    return true unless defined?(EventSystem)
    return true unless EventSystem.has_challenge_modifier?("limited_party")

    party.compact.length <= 3
  end

  # Check if party meets Mono-Type requirement
  def party_meets_mono_type_requirement?(party)
    return true unless defined?(EventSystem)
    return true unless EventSystem.has_challenge_modifier?("mono_type")

    return true if party.compact.empty?

    # Get all types in party
    all_types = []
    party.compact.each do |pkmn|
      all_types << pkmn.type1 if pkmn.type1
      all_types << pkmn.type2 if pkmn.type2
    end
    all_types = all_types.compact.uniq

    # Find a type that all Pokemon share
    party.compact.each do |pkmn|
      pkmn_types = [pkmn.type1, pkmn.type2].compact
      all_types = all_types & pkmn_types  # Intersection
    end

    # If any common type remains, party is valid
    !all_types.empty?
  end

  # Check all party requirements
  def party_valid_for_shiny_event?(party)
    return true unless defined?(EventSystem)
    return true unless EventSystem.has_active_event?("shiny")

    valid = true
    reasons = []

    unless party_meets_fusion_requirement?(party)
      valid = false
      reasons << "Fusion-Only: All party members must be fusions"
    end

    unless party_meets_size_requirement?(party)
      valid = false
      reasons << "Limited Party: Maximum 3 Pokemon allowed"
    end

    unless party_meets_mono_type_requirement?(party)
      valid = false
      reasons << "Mono-Type: All Pokemon must share a common type"
    end

    { valid: valid, reasons: reasons }
  end

  #---------------------------------------------------------------------------
  # Catch Tracking
  #---------------------------------------------------------------------------

  def mark_catch_attempted
    @catch_attempted_this_battle = true
  end

  def catch_attempted?
    @catch_attempted_this_battle
  end

  def mark_shiny_catch_failed
    @one_chance_failed = true
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info(TAG, "One Chance: Shiny catch failed, no more shinies for this event")
    end
  end

  def one_chance_failed?
    @one_chance_failed
  end

  #---------------------------------------------------------------------------
  # Reset Functions (call at battle start/end)
  #---------------------------------------------------------------------------

  def reset_battle_state
    @catch_attempted_this_battle = false
    # Note: Don't reset @mono_ball_type - it persists for the event duration
    # Note: Don't reset @one_chance_failed - it persists for the event duration
  end

  def reset_event_state
    @mono_ball_type = nil
    @catch_attempted_this_battle = false
    @one_chance_failed = false
  end

  def get_mono_ball_type
    @mono_ball_type
  end

  #---------------------------------------------------------------------------
  # Debug
  #---------------------------------------------------------------------------

  def debug_status
    puts "=" * 50
    puts "ShinyEventModifiers Status"
    puts "=" * 50
    puts "Mono ball type: #{@mono_ball_type || 'not set'}"
    puts "Catch attempted this battle: #{@catch_attempted_this_battle}"
    puts "One chance failed: #{@one_chance_failed}"

    if defined?(EventSystem) && EventSystem.has_active_event?("shiny")
      puts "Active challenge modifiers: #{EventSystem.active_challenge_modifiers.join(', ')}"
      puts "Active reward modifiers: #{EventSystem.active_reward_modifiers.join(', ')}"
    else
      puts "No shiny event active"
    end
    puts "=" * 50
  end
end

#===============================================================================
# Reward Modifier Tracking
#===============================================================================
module ShinyRewardTracker
  TAG = "SHINY-REWARD"

  @shinies_caught_during_event = 0
  @shinies_fainted_during_event = 0
  @event_start_time = nil
  @last_map_id = nil

  module_function

  # Called when a shiny is caught during an event
  def on_shiny_caught
    return unless defined?(EventSystem) && EventSystem.has_active_event?("shiny")

    # Only track if on event map
    event = EventSystem.primary_event
    return unless event
    return unless on_event_map?(event)

    @shinies_caught_during_event += 1

    # Record for participation tracking
    if defined?(EventRewards)
      player_id = get_player_id
      EventRewards.record_shiny_encounter(event[:id], player_id, :caught)
    end

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info(TAG, "Shiny caught during event on event map! Total: #{@shinies_caught_during_event}")
    end
  end

  # Called when a shiny is fainted during an event
  def on_shiny_fainted
    return unless defined?(EventSystem) && EventSystem.has_active_event?("shiny")

    # Only track if on event map
    event = EventSystem.primary_event
    return unless event
    return unless on_event_map?(event)

    @shinies_fainted_during_event += 1

    # Record for participation tracking
    if defined?(EventRewards)
      player_id = get_player_id
      EventRewards.record_shiny_encounter(event[:id], player_id, :fainted)
    end

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info(TAG, "Shiny fainted during event on event map! Total fainted: #{@shinies_fainted_during_event}")
    end
  end

  # Check if player is on the event map
  def on_event_map?(event)
    return true if event[:map] == "global" || event[:map].to_s == "0"
    return false unless defined?($game_map) && $game_map

    current_map = $game_map.map_id
    event_map = event[:map].to_i rescue 0
    return true if event_map == 0  # Global

    current_map == event_map
  end

  def shinies_caught
    @shinies_caught_during_event
  end

  def shinies_fainted
    @shinies_fainted_during_event
  end

  # Check Pity modifier - bonus if few catches during event
  def pity_bonus_earned?
    return false unless defined?(EventSystem)
    return false unless EventSystem.has_reward_modifier?("pity")

    # Pity bonus if caught less than 2 shinies during event
    @shinies_caught_during_event < 2
  end

  # Calculate Squad Scaling bonus multiplier
  def squad_scaling_multiplier
    return 1.0 unless defined?(EventSystem)
    return 1.0 unless EventSystem.has_reward_modifier?("squad_scaling")
    return 1.0 unless defined?(MultiplayerClient)

    squad = MultiplayerClient.squad rescue nil
    return 1.0 unless squad && squad[:members]

    squad_size = squad[:members].length
    # x1/x2/x3 for 1/2/3 players
    [squad_size, 3].min
  end

  # Called when player enters a new map - triggers Blessing if active
  def on_map_entry(map_id)
    return if map_id == @last_map_id  # Same map, no trigger
    @last_map_id = map_id

    return unless defined?(EventSystem)
    return unless EventSystem.has_active_event?("shiny")
    return unless EventSystem.has_reward_modifier?("blessing")

    # Check if we're on the event map
    event = EventSystem.primary_event
    return unless event
    return unless on_event_map?(event)

    # Apply Blessing buff on map entry (only on event map)
    # Use silent=false to show chat message on first activation
    if defined?(EventRewards)
      player_id = get_player_id
      EventRewards.apply_blessing_on_map_entry(player_id, false)

      # Update UI to show blessing as active
      if defined?(EventUIManager)
        EventUIManager.activate_modifier("blessing")
      end
    end
  end

  # Called to grant Pity buff (guaranteed next shiny)
  def grant_pity_buff
    return unless defined?(EventRewards)

    player_id = get_player_id
    EventRewards.add_buff(player_id, :pity, 3600, {})  # 1 hour duration

    if defined?(EventUIManager)
      EventUIManager.activate_modifier("pity")
    end

    if defined?(ChatMessages)
      ChatMessages.add_message("Global", "SYSTEM", "System", "Pity activated! Your next encounter is guaranteed shiny!")
    end
  end

  # Called to grant Fusion Shiny buff
  def grant_fusion_shiny_buff
    return unless defined?(EventRewards)

    player_id = get_player_id
    EventRewards.add_buff(player_id, :fusion_shiny, 3600, {})  # 1 hour duration

    if defined?(EventUIManager)
      EventUIManager.activate_modifier("fusion")
    end

    if defined?(ChatMessages)
      ChatMessages.add_message("Global", "SYSTEM", "System", "Fusion buff activated! Next wild fusion will have a shiny part!")
    end
  end

  # Get player ID
  def get_player_id
    if defined?(MultiplayerClient)
      MultiplayerClient.instance_variable_get(:@player_name) rescue "local"
    else
      "local"
    end
  end

  # Reset at event start
  def reset
    @shinies_caught_during_event = 0
    @shinies_fainted_during_event = 0
    @event_start_time = Time.now
    @last_map_id = nil
  end

  def debug_status
    puts "ShinyRewardTracker:"
    puts "  Shinies caught: #{@shinies_caught_during_event}"
    puts "  Shinies fainted: #{@shinies_fainted_during_event}"
    puts "  Pity bonus earned: #{pity_bonus_earned?}"
    puts "  Squad scaling multiplier: #{squad_scaling_multiplier}"
  end
end

#===============================================================================
# Wild Fusion Shiny Hook - Apply fusion buff to wild fusions
#===============================================================================
# This hook triggers when any wild Pokemon is created and checks if:
# 1. The Pokemon is a fusion
# 2. The player has the fusion shiny buff active
# If both are true, force one part of the fusion to be shiny
#===============================================================================
Events.onWildPokemonCreate += proc { |_sender, e|
  pokemon = e[0]
  next unless pokemon

  # Check if this is a fusion Pokemon
  next unless pokemon.respond_to?(:isFusion?) && pokemon.isFusion?

  # Check if fusion buff is available for this player (end-of-event reward)
  # Fusion buff is granted via /giveeventrewards to eligible players
  next unless defined?(EventRewards)

  player_id = if defined?(MultiplayerClient)
    MultiplayerClient.instance_variable_get(:@player_name) rescue "local"
  else
    "local"
  end

  next unless EventRewards.has_buff?(player_id, :fusion_shiny)

  # Check if we're on the event map (fusion buff only works on event map)
  if defined?(EventSystem)
    event = EventSystem.primary_event
    if event && event[:map] != "global" && event[:map].to_s != "0"
      # Non-global event, check map
      if defined?($game_map) && $game_map
        event_map = event[:map].to_i rescue 0
        if event_map != 0 && $game_map.map_id != event_map
          next  # Not on event map, skip fusion buff
        end
      end
    end
  end

  # Fusion buff is active! Make at least one part shiny
  # Randomly choose which part (head or body) to make shiny
  if rand(2) == 0
    # Make head shiny - use global functions kurayRNGforChannels and kurayKRSmake
    pokemon.head_shiny = true
    pokemon.head_shinyhue = rand(0..360) - 180
    pokemon.head_shinyr = kurayRNGforChannels rescue rand(-50..50)
    pokemon.head_shinyg = kurayRNGforChannels rescue rand(-50..50)
    pokemon.head_shinyb = kurayRNGforChannels rescue rand(-50..50)
    pokemon.head_shinykrs = kurayKRSmake rescue [0, 0, 0]

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("EVENT-SHINY", "Fusion buff: Made HEAD shiny! hue=#{pokemon.head_shinyhue}")
    end
  else
    # Make body shiny - use global functions kurayRNGforChannels and kurayKRSmake
    pokemon.body_shiny = true
    pokemon.body_shinyhue = rand(0..360) - 180
    pokemon.body_shinyr = kurayRNGforChannels rescue rand(-50..50)
    pokemon.body_shinyg = kurayRNGforChannels rescue rand(-50..50)
    pokemon.body_shinyb = kurayRNGforChannels rescue rand(-50..50)
    pokemon.body_shinykrs = kurayKRSmake rescue [0, 0, 0]

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("EVENT-SHINY", "Fusion buff: Made BODY shiny! hue=#{pokemon.body_shinyhue}")
    end
  end

  # Consume the buff (single use)
  EventRewards.consume_buff(player_id, :fusion_shiny)

  # Update UI to show buff as consumed
  if defined?(EventUIManager)
    EventUIManager.deactivate_modifier("fusion")
  end

  # Notify the player
  if defined?(ChatMessages)
    ChatMessages.add_message("Global", "SYSTEM", "System", "Fusion buff triggered! This wild fusion has a shiny part!")
  end
}

#===============================================================================
# Scene_Map Hooks - Trigger reward effects on map change
#===============================================================================
class Scene_Map
  unless method_defined?(:shiny_reward_original_transfer_player)
    alias shiny_reward_original_transfer_player transfer_player if method_defined?(:transfer_player)
  end

  def transfer_player(*args)
    # Call original
    result = shiny_reward_original_transfer_player(*args) if defined?(shiny_reward_original_transfer_player)

    # Trigger map entry rewards
    if defined?(ShinyRewardTracker) && defined?($game_map) && $game_map
      ShinyRewardTracker.on_map_entry($game_map.map_id)
    end

    # Check for pending UI investigations
    if defined?(EventUIManager)
      EventUIManager.check_pending_investigations
    end

    result
  end
end

#===============================================================================
# Battle Hooks - Track shiny caught/fainted for eligibility
#===============================================================================

# Hook into PokeBattle_Battler to track when wild shinies faint
class PokeBattle_Battler
  unless method_defined?(:event_shiny_original_pbFaint)
    alias event_shiny_original_pbFaint pbFaint
  end

  def pbFaint(showMessage = true)
    # Check if this is a wild Pokemon and it's shiny before it faints
    if @battle && @battle.wildBattle? && opposes? && @pokemon && @pokemon.shiny?
      # This is a wild shiny being fainted
      if defined?(ShinyRewardTracker)
        ShinyRewardTracker.on_shiny_fainted
        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("EVENT-SHINY", "Wild shiny fainted! Tracking for eligibility.")
        end
      end
    end

    # Call original method
    event_shiny_original_pbFaint(showMessage)
  end
end

# Hook into PokeBattle_Battle to track when shinies are caught
class PokeBattle_Battle
  unless method_defined?(:event_shiny_original_pbRecordAndStoreCaughtPokemon)
    alias event_shiny_original_pbRecordAndStoreCaughtPokemon pbRecordAndStoreCaughtPokemon
  end

  def pbRecordAndStoreCaughtPokemon
    # Track caught shinies for event eligibility BEFORE storing
    @caughtPokemon.each do |pkmn|
      if pkmn.shiny? && defined?(ShinyRewardTracker)
        ShinyRewardTracker.on_shiny_caught
        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("EVENT-SHINY", "Shiny caught: #{pkmn.species}! Tracking for eligibility.")
        end
      end
    end

    # Call original method
    event_shiny_original_pbRecordAndStoreCaughtPokemon
  end
end

#===============================================================================
# Module loaded
#===============================================================================
if defined?(MultiplayerDebug)
  MultiplayerDebug.info("EVENT-SHINY", "=" * 60)
  MultiplayerDebug.info("EVENT-SHINY", "151_Event_Shiny.rb loaded")
  MultiplayerDebug.info("EVENT-SHINY", "Shiny event hooks installed:")
  MultiplayerDebug.info("EVENT-SHINY", "  Pokemon.shiny? - applies all multipliers/buffs")
  MultiplayerDebug.info("EVENT-SHINY", "  ShinyEventModifiers - challenge modifier checks")
  MultiplayerDebug.info("EVENT-SHINY", "  ShinyRewardTracker - participation & rewards")
  MultiplayerDebug.info("EVENT-SHINY", "  Events.onWildPokemonCreate - fusion shiny hook")
  MultiplayerDebug.info("EVENT-SHINY", "  PokeBattle_Battler.pbFaint - shiny faint tracking")
  MultiplayerDebug.info("EVENT-SHINY", "  PokeBattle_Battle.pbRecordAndStoreCaughtPokemon - shiny catch tracking")
  MultiplayerDebug.info("EVENT-SHINY", "Passive rewards supported:")
  MultiplayerDebug.info("EVENT-SHINY", "  Blessing - x100 shiny for 30s on map entry")
  MultiplayerDebug.info("EVENT-SHINY", "  Pity - guaranteed next shiny")
  MultiplayerDebug.info("EVENT-SHINY", "  Fusion - next wild fusion has shiny part")
  MultiplayerDebug.info("EVENT-SHINY", "  Squad Scaling - x1/x2/x3 for squad size")
  MultiplayerDebug.info("EVENT-SHINY", "  Shooting Star Charm - x1.5 when owned")
  MultiplayerDebug.info("EVENT-SHINY", "Scene_Map hooks: map transfer triggers rewards")
  MultiplayerDebug.info("EVENT-SHINY", "=" * 60)
end
