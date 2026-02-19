#===============================================================================
# Override pbRandom to use deterministic Random instance during PvP battles
#===============================================================================
# During PvP battles, pbRandom uses PvPRNGSync.battle_rng (Random.new instance)
# instead of global rand(), ensuring perfect determinism across both clients.
#
# This mirrors the Coop approach in 101_Coop_BattleRNG_Override.rb
# Note: 101_ loads before 126_, so Coop's alias exists first, then PvP wraps it.
# Since you can't be in Coop and PvP at the same time, the chain works fine.
#===============================================================================

class PokeBattle_Battle
  # Alias the current pbRandom (may be original or already wrapped)
  alias pvp_rng_original_pbRandom pbRandom unless method_defined?(:pvp_rng_original_pbRandom)

  def pbRandom(x)
    # During PvP battles, use isolated Random instance for determinism
    if defined?(PvPBattleState) && PvPBattleState.in_pvp_battle?
      if defined?(PvPRNGSync) && PvPRNGSync.battle_rng
        return PvPRNGSync.battle_rng.rand(x)
      end
    end

    # Fallback to original/next-in-chain implementation
    pvp_rng_original_pbRandom(x)
  end
end

if defined?(MultiplayerDebug)
  MultiplayerDebug.info("PVP-RNG-OVERRIDE", "Battle pbRandom override loaded - uses Random.new for PvP determinism")
end
