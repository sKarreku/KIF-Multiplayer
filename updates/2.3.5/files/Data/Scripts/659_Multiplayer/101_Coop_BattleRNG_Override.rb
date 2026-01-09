#===============================================================================
# Override pbRandom to use deterministic Random instance during coop battles
#===============================================================================
# During coop battles, pbRandom uses CoopRNGSync.battle_rng (Random.new instance)
# instead of global rand(), ensuring perfect determinism across all clients
#===============================================================================

class PokeBattle_Battle
  alias coop_original_pbRandom pbRandom

  def pbRandom(x)
    # During coop battles, use isolated Random instance
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      if defined?(CoopRNGSync) && CoopRNGSync.battle_rng
        return CoopRNGSync.battle_rng.rand(x)
      end
    end

    # Fallback to original implementation (global rand)
    coop_original_pbRandom(x)
  end
end

##MultiplayerDebug.info("COOP-RNG-OVERRIDE", "Battle pbRandom override loaded - uses Random.new for determinism")
