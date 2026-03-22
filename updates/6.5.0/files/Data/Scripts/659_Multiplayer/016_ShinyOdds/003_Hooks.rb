#===============================================================================
# MODULE: Shiny Odds Tracking — Creation Hooks
#===============================================================================
# Hooks into all Pokemon creation/catch points to stamp shiny odds.
# Runs AFTER Family assignment (016 loads after 008) so family data is
# already set on the Pokemon when we stamp.
#
# Hook points:
#   1. Wild catches   — pbRecordAndStoreCaughtPokemon (context :wild)
#   2. Breeding       — pbDayCareGenerateEgg (context :breeding)
#   3. K-eggs         — kurayeggs_triggereggitem + pbAddPokemon (context :kegg)
#   4. Cases          — KIFCases.award_pokemon (context :default)
#===============================================================================

# ── 1. Wild catch hook ──────────────────────────────────────────────────────
class PokeBattle_Battle
  alias shiny_odds_original_pbRecordAndStoreCaughtPokemon pbRecordAndStoreCaughtPokemon

  def pbRecordAndStoreCaughtPokemon
    # Save refs before chain processes & clears @caughtPokemon
    caught_refs = @caughtPokemon.dup

    # Run chain: Family assigns → Coop processes → Vanilla stores & clears
    shiny_odds_original_pbRecordAndStoreCaughtPokemon

    # Stamp odds on caught shinies — only when connected to server
    return unless defined?(MultiplayerClient) && MultiplayerClient.instance_variable_get(:@connected)
    caught_refs.each do |pkmn|
      next unless pkmn.shiny? || (pkmn.respond_to?(:fakeshiny?) && pkmn.fakeshiny?)
      next if pkmn.shiny_catch_odds  # already stamped (shouldn't happen)
      ShinyOddsTracker.catch_context = :wild
      _stamp_shiny_odds(pkmn)
      ShinyOddsTracker.reset_context
    end
  end

  private

  def _stamp_shiny_odds(pkmn)
    pkmn.shiny_catch_odds = ShinyOddsTracker.calculate_odds

    # Stamp family rate if this shiny has a family assigned
    if pkmn.respond_to?(:has_family_data?) && pkmn.has_family_data?
      pkmn.family_catch_rate = ShinyOddsTracker.calculate_family_rate
    end

    # Request server stamp (async)
    ShinyOddsTracker.request_server_stamp(pkmn)
  end
end

# ── 2. Breeding hook ────────────────────────────────────────────────────────
# Hook pbDayCareGenerateEgg to stamp breeding odds on shiny eggs.
# The egg's shininess is determined during generation (Masuda + Charm rerolls).
alias shiny_odds_original_pbDayCareGenerateEgg pbDayCareGenerateEgg

def pbDayCareGenerateEgg
  # Skip shiny odds stamping when offline
  unless defined?(MultiplayerClient) && MultiplayerClient.instance_variable_get(:@connected)
    shiny_odds_original_pbDayCareGenerateEgg
    return
  end

  # Calculate extra rerolls BEFORE the egg is generated
  # (same logic as the daycare code: +5 Masuda, +2 Shiny Charm)
  extra_rolls = 0
  if $PokemonGlobal.daycare[0][0] && $PokemonGlobal.daycare[1][0]
    father = $PokemonGlobal.daycare[0][0]
    mother = $PokemonGlobal.daycare[1][0]
    extra_rolls += 5 if father.owner.language != mother.owner.language
    extra_rolls += 2 if GameData::Item.exists?(:SHINYCHARM) && ($PokemonBag.pbHasItem?(:SHINYCHARM) rescue false)
  end

  ShinyOddsTracker.catch_context = :breeding
  ShinyOddsTracker.breeding_extra_rolls = extra_rolls

  # Find party size before generation to identify the new egg after
  party_before = $Trainer.party.length

  shiny_odds_original_pbDayCareGenerateEgg

  # The new egg is the last Pokemon in the party (if party grew)
  if $Trainer.party.length > party_before
    egg = $Trainer.party.last
    if egg && (egg.shiny? || (egg.respond_to?(:fakeshiny?) && egg.fakeshiny?))
      egg.shiny_catch_odds = ShinyOddsTracker.calculate_odds
      ShinyOddsTracker.request_server_stamp(egg)
    end
  end

  ShinyOddsTracker.reset_context
end

# ── 3. K-egg hook ───────────────────────────────────────────────────────────
# Hook kurayeggs_triggereggitem to stamp K-egg odds on shiny Pokemon.
# 201_Kuray loads before 659_Multiplayer, so the method always exists.
#
# K-eggs use pbAddPokemon which sends to PC if party is full, so we can't
# rely on party size. Instead, hook pbAddPokemon to stamp during :kegg context.
alias shiny_odds_original_pbAddPokemon pbAddPokemon

def pbAddPokemon(pkmn, level = 1, see_form = true, dontRandomize = false, variableToSave = nil)
  result = shiny_odds_original_pbAddPokemon(pkmn, level, see_form, dontRandomize, variableToSave)

  # Stamp shiny odds on any Pokemon added while in :kegg context
  # Only when connected and pbAddPokemon succeeded
  if result && ShinyOddsTracker.catch_context == :kegg && pkmn.is_a?(Pokemon)
    if defined?(MultiplayerClient) && MultiplayerClient.instance_variable_get(:@connected)
      if pkmn.shiny? || (pkmn.respond_to?(:fakeshiny?) && pkmn.fakeshiny?)
        unless pkmn.shiny_catch_odds  # not already stamped
          pkmn.shiny_catch_odds = ShinyOddsTracker.calculate_odds
          ShinyOddsTracker.request_server_stamp(pkmn)
        end
      end
    end
  end

  result
end

begin
  alias shiny_odds_original_kurayeggs_triggereggitem kurayeggs_triggereggitem

  def kurayeggs_triggereggitem(id, itemid)
    ShinyOddsTracker.catch_context = :kegg
    shiny_odds_original_kurayeggs_triggereggitem(id, itemid)
    ShinyOddsTracker.reset_context
  end
rescue NameError
  # kurayeggs_triggereggitem not defined (K-eggs not installed)
end

# ── 4. Case hook ────────────────────────────────────────────────────────────
# Hook KIFCases.award_pokemon for PokéCase drops.
if defined?(KIFCases)
  module KIFCases
    class << self
      alias shiny_odds_original_award_pokemon award_pokemon

      def award_pokemon(species_sym)
        pkmn = shiny_odds_original_award_pokemon(species_sym)

        if defined?(MultiplayerClient) && MultiplayerClient.instance_variable_get(:@connected)
          if pkmn && (pkmn.shiny? || (pkmn.respond_to?(:fakeshiny?) && pkmn.fakeshiny?))
            ShinyOddsTracker.catch_context = :default
            pkmn.shiny_catch_odds = ShinyOddsTracker.calculate_odds
            ShinyOddsTracker.request_server_stamp(pkmn)
            ShinyOddsTracker.reset_context
          end
        end

        pkmn
      end
    end
  end
end

# ── 5. Shedinja duplicate hook ────────────────────────────────────────────
# When Nincada evolves, pbDuplicatePokemon clones the original (which may
# be a fused shiny). The clone inherits all stamp data — strip it so the
# duplicate doesn't display odds it didn't earn.
class PokemonEvolutionScene
  class << self
    alias shiny_odds_original_pbDuplicatePokemon pbDuplicatePokemon

    def pbDuplicatePokemon(pkmn, new_species)
      shiny_odds_original_pbDuplicatePokemon(pkmn, new_species)
      # The duplicate is the last Pokemon in the party
      duped = $Trainer.party.last
      return unless duped
      duped.shiny_catch_odds    = nil if duped.respond_to?(:shiny_catch_odds=)
      duped.family_catch_rate   = nil if duped.respond_to?(:family_catch_rate=)
      duped.shiny_odds_stamped  = false if duped.respond_to?(:shiny_odds_stamped=)
      duped.shiny_catch_context = nil if duped.respond_to?(:shiny_catch_context=)
    end
  end
end
