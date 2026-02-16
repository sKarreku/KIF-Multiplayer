#===============================================================================
# MODULE 21: Spectator Mode - Allow Fainted Players to Spectate
#===============================================================================
# When a player's Pokemon all faint in a coop battle, they should enter
# spectator mode and watch their allies continue fighting, rather than causing
# the entire team to lose.
#
# Solution:
# - Override pbAllFainted? to only return true if ALL trainers on the side faint
# - Track which trainers have all their Pokemon fainted
# - Allow battle to continue with remaining trainers
#===============================================================================

class PokeBattle_Battle
  # Override pbAllFainted? to check individual trainers in coop battles
  alias coop_original_pbAllFainted? pbAllFainted?

  def pbAllFainted?(idxBattler=0)
    # If not in coop battle, use original behavior
    unless defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      return coop_original_pbAllFainted?(idxBattler)
    end

    # In coop battles, check if ALL trainers on this side have fainted
    # Not just if there are no able Pokemon in total
    side = (idxBattler % 2)
    able_counts = pbAbleTeamCounts(side)

    # If able_counts is nil or empty, no Pokemon are able
    return true if !able_counts || able_counts.empty?

    # Check if at least ONE trainer still has able Pokemon
    able_counts.each do |count|
      return false if count && count > 0
    end

    # All trainers have no able Pokemon
    ##MultiplayerDebug.info("COOP-SPECTATOR", "All trainers on side #{side} have fainted")
    return true
  end

  # Check if a specific trainer has all their Pokemon fainted
  def pbTrainerAllFainted?(idxBattler)
    return false unless defined?(CoopBattleState) && CoopBattleState.in_coop_battle?

    side = (idxBattler % 2)
    idxOwner = pbGetOwnerIndexFromBattlerIndex(idxBattler)

    able_counts = pbAbleTeamCounts(side)
    return true if !able_counts || able_counts[idxOwner].nil? || able_counts[idxOwner] == 0

    return false
  end
end

##MultiplayerDebug.info("MODULE-21", "Spectator mode loaded - players can spectate after fainting")
