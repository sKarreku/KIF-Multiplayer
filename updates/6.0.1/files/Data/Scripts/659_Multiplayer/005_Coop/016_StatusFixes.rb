# =============================================================================
# Co-op Status Effect Fixes
# =============================================================================
# Fixes status synchronization issues in coop battles.
#
# Root cause: Each client has separate Pokemon object copies from party snapshots.
# Fix: In coop battles, store statusCount purely in Battler (which IS synchronized).
#
# Source files merged:
#   996_Coop_StatusCount_Fix.rb      → Battler statusCount fix (REAL FIX)
#   997_Pokemon_StatusCount_Debug.rb → Pokemon statusCount passthrough
#   999_StatusDebug.rb               → Attack/move phase passthroughs
# =============================================================================

# --- Battler statusCount fix (from 996) ---
class PokeBattle_Battler
  # Override getter
  def statusCount
    @statusCount
  end

  # Override setter to skip Pokemon sync in coop
  alias coop_statuscount_fix_original_statusCount= statusCount=

  def statusCount=(value)
    @statusCount = value
    # Skip Pokemon sync in coop battles - Pokemon objects are per-client copies
    if !defined?(CoopBattleState) || !CoopBattleState.in_coop_battle?
      @pokemon.statusCount = value if @pokemon
    end
    @battle.scene.pbRefreshOne(@index)
  end

  # Override initialization to NOT read statusCount from Pokemon in coop
  alias coop_statuscount_fix_original_pbInitPokemon pbInitPokemon

  def pbInitPokemon(pkmn, idxParty)
    coop_statuscount_fix_original_pbInitPokemon(pkmn, idxParty)
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      # In coop battles, statusCount stays in Battler - reset to 0 on switch-in
      @statusCount = 0
    end
  end
end

# --- Pokemon statusCount passthrough (from 997) ---
class Pokemon
  alias status_count_debug_original_statusCount= statusCount=

  def statusCount=(value)
    status_count_debug_original_statusCount=(value)
  end
end

# --- Attack/move phase passthroughs (from 999) ---
class PokeBattle_Battle
  alias status_debug_original_pbAttackPhaseMoves pbAttackPhaseMoves

  def pbAttackPhaseMoves
    status_debug_original_pbAttackPhaseMoves
  end
end

class PokeBattle_Battler
  alias status_debug_original_pbUseMove pbUseMove

  def pbUseMove(choice, specialUsage = false)
    status_debug_original_pbUseMove(choice, specialUsage)
  end
end
