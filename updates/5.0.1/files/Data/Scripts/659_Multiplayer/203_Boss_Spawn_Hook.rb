#===============================================================================
# MODULE 4: Boss Pokemon System - Spawn Hook
#===============================================================================
# Hooks into wild encounters to check for boss spawn (1/50 chance).
# Server validates the boss battle to prevent client-side manipulation.
#
# Integration: This module provides a function to call from 017_Coop_WildHook_v2.rb
# after line 913 (EncounterModifier.trigger).
#
# Test: Set BossConfig.set_spawn_chance(1), walk in grass.
#       Check server logs for BOSS_BATTLE_START.
#===============================================================================

MultiplayerDebug.info("BOSS", "Loading 203_Boss_Spawn_Hook.rb...") if defined?(MultiplayerDebug)

module BossSpawnHook
  #=============================================================================
  # Check if this encounter should be a boss
  #=============================================================================
  # Returns: Boss Pokemon if spawning, nil otherwise
  # Call this AFTER EncounterModifier.trigger, BEFORE pbGenerateWildPokemon
  #
  # Parameters:
  #   encounter        - [species, level] from normal encounter
  #   player_count     - Number of players (1-3)
  #   player_parties   - Array of player party arrays
  #   family_enabled   - Whether family system is enabled
  #   initiator_sid    - Session ID of initiator (for server tracking)
  #
  def self.check_boss_spawn(encounter, player_count, player_parties, family_enabled, initiator_sid = nil)
    MultiplayerDebug.info("BOSS-SPAWN", "  check_boss_spawn called") if defined?(MultiplayerDebug)

    unless BossConfig.enabled?
      MultiplayerDebug.info("BOSS-SPAWN", "  ABORT: BossConfig.enabled? = false") if defined?(MultiplayerDebug)
      return nil
    end

    unless encounter && encounter[0]
      MultiplayerDebug.info("BOSS-SPAWN", "  ABORT: Invalid encounter = #{encounter.inspect}") if defined?(MultiplayerDebug)
      return nil
    end

    # Roll for boss spawn
    spawn_chance = BossConfig.get_spawn_chance
    roll = rand(spawn_chance)
    MultiplayerDebug.info("BOSS-SPAWN", "  Spawn roll: #{roll} / #{spawn_chance} (need 0 to spawn)") if defined?(MultiplayerDebug)

    unless roll == 0
      MultiplayerDebug.info("BOSS-SPAWN", "  ABORT: Roll failed (#{roll} != 0)") if defined?(MultiplayerDebug)
      return nil
    end

    MultiplayerDebug.info("BOSS-SPAWN", "  ROLL SUCCESS! Generating boss...") if defined?(MultiplayerDebug)

    # Generate boss Pokemon
    boss = BossGenerator.create(player_count, player_parties, family_enabled)

    unless boss
      MultiplayerDebug.info("BOSS-SPAWN", "  ABORT: BossGenerator.create returned nil") if defined?(MultiplayerDebug)
      return nil
    end

    MultiplayerDebug.info("BOSS-SPAWN", "  Boss generated: #{boss.species} Lv#{boss.level}") if defined?(MultiplayerDebug)

    # Generate battle ID
    battle_id = generate_battle_id

    # Store battle ID on boss
    boss.boss_battle_id = battle_id

    # Register with server
    register_boss_battle(boss, battle_id, initiator_sid)

    MultiplayerDebug.info("BOSS-SPAWN", "  Boss ready: #{boss.species} Lv#{boss.level} ID=#{battle_id}") if defined?(MultiplayerDebug)

    boss
  end

  #=============================================================================
  # Force Boss Spawn (for debugging/scripted events)
  #=============================================================================
  def self.force_spawn(player_count, player_parties, family_enabled, initiator_sid = nil, species = nil)
    boss = if species
      BossGenerator.create_specific(species, BossGenerator.calculate_level(player_parties), player_count, family_enabled)
    else
      BossGenerator.create(player_count, player_parties, family_enabled)
    end

    return nil unless boss

    battle_id = generate_battle_id
    boss.boss_battle_id = battle_id
    register_boss_battle(boss, battle_id, initiator_sid)

    MultiplayerDebug.info("BOSS", "Forced boss spawn: #{boss.species} Lv#{boss.level} ID=#{battle_id}") if defined?(MultiplayerDebug)

    boss
  end

  #=============================================================================
  # Generate Unique Battle ID
  #=============================================================================
  def self.generate_battle_id
    timestamp = Time.now.to_i
    random = rand(100000)
    "BOSS-#{timestamp}-#{random}"
  end

  #=============================================================================
  # Register Boss Battle with Server
  #=============================================================================
  def self.register_boss_battle(boss, battle_id, initiator_sid)
    return unless defined?(MultiplayerClient)

    payload = {
      "battle_id" => battle_id,
      "species" => boss.species.to_s,
      "level" => boss.level,
      "initiator" => initiator_sid || MultiplayerClient.session_id.to_s,
      "loot_options" => serialize_loot_options(boss.boss_loot_options)
    }

    json_str = MiniJSON.dump(payload) rescue payload.to_s
    MultiplayerClient.send_data("BOSS_BATTLE_START:#{json_str}")
  end

  #=============================================================================
  # Serialize Loot Options for Network
  #=============================================================================
  def self.serialize_loot_options(options)
    options.map do |opt|
      {
        "rarity" => opt[:rarity].to_s,
        "item" => opt[:item].to_s,
        "qty" => opt[:qty]
      }
    end
  end

  #=============================================================================
  # Deserialize Loot Options from Network
  #=============================================================================
  def self.deserialize_loot_options(data)
    data.map do |opt|
      {
        rarity: opt["rarity"].to_sym,
        item: opt["item"].to_sym,
        qty: opt["qty"].to_i
      }
    end
  end

  #=============================================================================
  # Create Boss from Network Data (for non-initiators)
  #=============================================================================
  def self.create_from_network(data, player_count)
    species = data["species"].to_sym rescue :CHARIZARD
    level = data["level"].to_i rescue 50
    battle_id = data["battle_id"]
    loot_options = deserialize_loot_options(data["loot_options"]) rescue BossConfig.generate_loot_options

    boss = BossGenerator.create_specific(species, level, player_count, false)
    boss.boss_battle_id = battle_id
    boss.boss_data[:loot_options] = loot_options

    boss
  end
end

#===============================================================================
# Solo Play Hook: Hook pbWildBattle for Boss Spawning
#===============================================================================
# This ensures bosses can spawn even when playing solo (not in co-op)

# Store original method reference
unless defined?($boss_pbWildBattle_original)
  $boss_pbWildBattle_original = method(:pbWildBattle) rescue nil
end

if $boss_pbWildBattle_original
  def pbWildBattle(species, level, outcomeVar = 1, canRun = true, canLose = false)
    MultiplayerDebug.info("BOSS-SPAWN", "=== pbWildBattle HOOK ===") if defined?(MultiplayerDebug)
    MultiplayerDebug.info("BOSS-SPAWN", "  Original: species=#{species}, level=#{level}") if defined?(MultiplayerDebug)

    # Check for boss spawn (solo play - 1 player)
    if defined?(BossSpawnHook) && defined?(BossConfig) && BossConfig.enabled?
      MultiplayerDebug.info("BOSS-SPAWN", "  Boss system enabled, checking spawn...") if defined?(MultiplayerDebug)

      encounter = [species, level]
      player_parties = [($Trainer.party rescue [])]
      family_enabled = defined?(PokemonFamilyConfig) && PokemonFamilyConfig.system_enabled?
      initiator_sid = defined?(MultiplayerClient) ? MultiplayerClient.session_id.to_s : nil

      boss = BossSpawnHook.check_boss_spawn(encounter, 1, player_parties, family_enabled, initiator_sid)

      if boss
        MultiplayerDebug.info("BOSS-SPAWN", "  BOSS SPAWNED! Using boss instead: #{boss.species} Lv#{boss.level}") if defined?(MultiplayerDebug)
        MultiplayerDebug.info("BOSS-SPAWN", "  Shiny: #{boss.shiny?}, Family: #{boss.family rescue 'N/A'}, is_boss?: #{boss.is_boss?}") if defined?(MultiplayerDebug)

        # Store the boss Pokemon in a global for the battle to use
        $boss_current_pokemon = boss

        # Set battle rules for boss
        setBattleRule("cannotRun")
        setBattleRule("canLose") if canLose
        setBattleRule("outcomeVar", outcomeVar) if outcomeVar != 1

        # Start boss battle - PASS THE POKEMON OBJECT DIRECTLY so it uses our boss
        # (passing species, level would create a new Pokemon internally)
        decision = pbWildBattleCore(boss)
        Events.onWildBattleEnd.trigger(nil, boss.species, boss.level, decision) if defined?(Events) && Events.respond_to?(:onWildBattleEnd)

        # Clear temp boss
        $boss_current_pokemon = nil

        return (decision != 2 && decision != 5)
      else
        MultiplayerDebug.info("BOSS-SPAWN", "  No boss spawn, using normal encounter") if defined?(MultiplayerDebug)
      end
    else
      MultiplayerDebug.info("BOSS-SPAWN", "  Boss system not enabled/available") if defined?(MultiplayerDebug)
    end

    # Call original
    $boss_pbWildBattle_original.call(species, level, outcomeVar, canRun, canLose)
  end

  MultiplayerDebug.info("BOSS", "pbWildBattle hook installed for solo boss spawning") if defined?(MultiplayerDebug)
end

#===============================================================================
# Integration Hook for 017_Coop_WildHook_v2.rb
#===============================================================================
# Add this call after line 913 in pbBattleOnStepTaken_coop:
#
# encounter = EncounterModifier.trigger(encounter) if defined?(EncounterModifier)
#
# # === BOSS SPAWN CHECK ===
# if defined?(BossSpawnHook) && BossConfig.enabled?
#   total_players = 1 + ally_count
#   all_parties = [my_party] + allies.map { |a| a[:party] }
#   family_enabled = defined?(PokemonFamilyConfig) && PokemonFamilyConfig.system_enabled?
#
#   boss = BossSpawnHook.check_boss_spawn(
#     encounter,
#     total_players,
#     all_parties,
#     family_enabled,
#     MultiplayerClient.session_id.to_s
#   )
#
#   if boss
#     # Boss spawned - use boss instead of normal encounter
#     foeParty = [boss]
#     # Skip normal foe generation (lines 928-940)
#     # Continue to broadcast section with modified foeParty
#   end
# end
# # === END BOSS SPAWN CHECK ===

#===============================================================================
# Debug Commands
#===============================================================================
if defined?(MenuHandlers)
  MenuHandlers.add(:debug_menu, :force_boss_encounter, {
    "name" => "Force Boss Encounter",
    "parent" => :main,
    "description" => "Force a boss encounter on next wild battle",
    "effect" => proc {
      # Temporarily set spawn chance to 1
      old_chance = BossConfig.get_spawn_chance
      BossConfig.set_spawn_chance(1)
      pbMessage("Boss spawn chance set to 1/1. Walk into grass for guaranteed boss.")
      pbMessage("Spawn chance will reset to #{old_chance} after encounter.")

      # Store old chance to restore after encounter
      $PokemonTemp.boss_debug_restore_chance = old_chance
    }
  })

  MenuHandlers.add(:debug_menu, :spawn_boss_now, {
    "name" => "Spawn Boss Battle Now",
    "parent" => :main,
    "description" => "Immediately start a boss battle",
    "effect" => proc {
      family_enabled = defined?(PokemonFamilyConfig) && PokemonFamilyConfig.system_enabled?
      boss = BossSpawnHook.force_spawn(1, [$Trainer.party], family_enabled)

      if boss
        pbMessage("Starting boss battle against #{boss.speciesName} Lv#{boss.level}")
        MultiplayerDebug.info("BOSS-DEBUG", "Shiny: #{boss.shiny?}, Family: #{boss.family rescue 'N/A'}, is_boss?: #{boss.is_boss?}") if defined?(MultiplayerDebug)

        # Set battle rules
        setBattleRule("cannotRun")
        setBattleRule("cannotLose")

        # Start battle - pass the boss Pokemon object directly
        pbWildBattleCore(boss)
      else
        pbMessage("Failed to generate boss.")
      end
    }
  })
end
