#===============================================================================
# Wild Battle Platinum Rewards - Per Pokemon Defeat
#===============================================================================
# Hooks into pbGainExpOne to award platinum for each wild Pokemon defeated
# Calculates rewards based on level, rarity, evolution stage, and stage penalty
# Server-authoritative: all calculations and credits happen server-side
#===============================================================================

# Helper: Get evolution stage of a Pokemon (1 = first, 2 = middle, 3 = final)
def get_pokemon_evolution_stage(species_id)
  return 1 unless defined?(GameData) && defined?(GameData::Species)

  species = GameData::Species.try_get(species_id)
  return 1 unless species

  baby_species = species.get_baby_species

  # First stage: is its own baby (get_baby_species returns a symbol)
  if species.species == baby_species
    return 1
  # Final stage: has no evolutions
  elsif species.get_evolutions.empty?
    return 3
  # Middle stage
  else
    return 2
  end
end

# Helper: Get catch rate of a Pokemon (0-255)
def get_pokemon_catch_rate(species_id)
  return 255 unless defined?(GameData) && defined?(GameData::Species)

  species = GameData::Species.try_get(species_id)
  return 255 unless species

  species.catch_rate || 255
end

class PokeBattle_Battle
  # Save original method
  alias platinum_reward_original_pbGainExpOne pbGainExpOne

  def pbGainExpOne(idxParty, defeatedBattler, numPartic, expShare, expAll, showMessages = true)
    # Call original first to award XP normally
    result = platinum_reward_original_pbGainExpOne(idxParty, defeatedBattler, numPartic, expShare, expAll, showMessages)

    # Only award platinum for wild battles when connected
    # Note: In coop, both clients will report - server handles deduplication
    if wildBattle? && defined?(MultiplayerClient) && MultiplayerClient.instance_variable_get(:@connected)
      begin
        # Initialize tracking hash if not exists
        @platinum_reported_battlers ||= {}

        # Get defeated battler unique key (index + species + level to handle duplicates)
        battler_key = "#{defeatedBattler.index}_#{defeatedBattler.displaySpecies}_#{defeatedBattler.level}"

        # Only report once per defeated Pokemon (pbGainExpOne is called multiple times per defeat)
        unless @platinum_reported_battlers[battler_key]
          @platinum_reported_battlers[battler_key] = true

          # Get defeated wild Pokemon data
          wild_species = defeatedBattler.displaySpecies
          wild_level = defeatedBattler.level

          # Get wild Pokemon evolution stage and catch rate
          wild_stage = get_pokemon_evolution_stage(wild_species)
          wild_catch_rate = get_pokemon_catch_rate(wild_species)

          # Collect all active player-side battlers (side 0) on the field
          active_battlers = @battlers.select { |b| b && !b.opposes? && !b.fainted? }

          # For COOP battles: Use the FIRST active battler's level/stage for calculation
          # This ensures all participants get the same platinum (based on initiator's Pokemon)
          # For SOLO battles: Still collect all active battlers (for multi-battle scenarios)
          is_coop = (defined?(CoopBattleState) && CoopBattleState.in_coop_battle?)

          if is_coop && active_battlers.length > 0
            # Use first battler only (typically the initiator's Pokemon)
            first_battler = active_battlers.first
            active_battler_levels = [first_battler.level]
            active_battler_stages = [get_pokemon_evolution_stage(first_battler.displaySpecies)]
          else
            # Solo battle: use all active battlers
            active_battler_levels = active_battlers.map { |b| b.level }
            active_battler_stages = active_battlers.map { |b| get_pokemon_evolution_stage(b.displaySpecies) }
          end

          # Only report if we have active battlers
          if active_battler_levels.length > 0
            # Report to server for platinum reward (server handles coop credit distribution)
            # Include battler index to distinguish multiple Pokemon of same species/level
            MultiplayerClient.report_wild_platinum(wild_species, wild_level, wild_catch_rate, wild_stage,
                                                     active_battler_levels, active_battler_stages, defeatedBattler.index)

            # DEBUG: Log that report was sent
            ##MultiplayerDebug.info("WILD-PLAT", "Reported defeat of #{wild_species} Lv#{wild_level} (battler #{defeatedBattler.index}) [Coop: #{is_coop}]") if defined?(MultiplayerDebug)
          end
        end
      rescue => e
        # Silent error handling - don't disrupt battle flow
        ##MultiplayerDebug.warn("WILD-PLAT", "Failed to report wild platinum: #{e.message}") if defined?(MultiplayerDebug)
      end
    end

    return result
  end
end

##MultiplayerDebug.info("MODULE-60", "Wild battle platinum reward alias loaded") if defined?(MultiplayerDebug)
