#===============================================================================
# MODULE 18: Target Selection Synchronization
#===============================================================================
# Fixes target selection desync by ensuring battler arrays are sorted in
# deterministic order before random selection.
#
# Problem: When pbAddTargetRandomFoe builds a choices array, the order of
# battlers can differ between clients, causing pbRandom(N) to select different
# targets even though the random number is the same.
#
# Solution: Sort choices array by battler index before random selection.
#===============================================================================

class PokeBattle_Battler
  # Override pbAddTargetRandomFoe to sort choices deterministically
  alias coop_original_pbAddTargetRandomFoe pbAddTargetRandomFoe if method_defined?(:pbAddTargetRandomFoe)

  def pbAddTargetRandomFoe(targets,user,_move,nearOnly=true)
    # If not in coop battle, use original behavior
    unless defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      return coop_original_pbAddTargetRandomFoe(targets,user,_move,nearOnly)
    end

    # Build choices array
    choices = []
    user.eachOpposing do |b|
      next if nearOnly && !user.near?(b)
      pbAddTarget(choices,user,b,_move,nearOnly)
    end

    if choices.length > 0
      # CRITICAL FIX: Sort choices by battler index for deterministic order
      choices.sort! { |a, b| a.index <=> b.index }

      # Log the choice selection for debugging
      if defined?(RNGLog)
        role = CoopBattleState.am_i_initiator? ? "INIT" : "NON"
        choice_indices = choices.map { |c| c.index }.inspect
        RNGLog.write("[TGT][#{role}] u#{user.index} choices=#{choice_indices}")
      end

      # Now select randomly - same order on all clients means same target!
      random_index = @battle.pbRandom(choices.length)
      selected_target = choices[random_index]

      if defined?(RNGLog)
        role = CoopBattleState.am_i_initiator? ? "INIT" : "NON"
        RNGLog.write("[TGT][#{role}] u#{user.index} rand(#{choices.length})=#{random_index} -> b#{selected_target.index}")
      end

      pbAddTarget(targets,user,selected_target,_move,nearOnly)
    end
  end

  # Override pbAddTargetRandomAlly to sort choices deterministically
  alias coop_original_pbAddTargetRandomAlly pbAddTargetRandomAlly if method_defined?(:pbAddTargetRandomAlly)

  def pbAddTargetRandomAlly(targets,user,_move,nearOnly=true)
    # If not in coop battle, use original behavior
    unless defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      return coop_original_pbAddTargetRandomAlly(targets,user,_move,nearOnly)
    end

    # Build choices array
    choices = []
    user.eachAlly do |b|
      next if nearOnly && !user.near?(b)
      pbAddTarget(choices,user,b,_move,nearOnly)
    end

    if choices.length > 0
      # CRITICAL FIX: Sort choices by battler index for deterministic order
      choices.sort! { |a, b| a.index <=> b.index }

      # Log the choice selection for debugging
      if defined?(RNGLog)
        role = CoopBattleState.am_i_initiator? ? "INIT" : "NON"
        choice_indices = choices.map { |c| c.index }.inspect
        RNGLog.write("[TGT][#{role}] u#{user.index} ally_choices=#{choice_indices}")
      end

      # Now select randomly - same order on all clients means same target!
      random_index = @battle.pbRandom(choices.length)
      selected_target = choices[random_index]

      if defined?(RNGLog)
        role = CoopBattleState.am_i_initiator? ? "INIT" : "NON"
        RNGLog.write("[TGT][#{role}] u#{user.index} rand(#{choices.length})=#{random_index} -> ally_b#{selected_target.index}")
      end

      pbAddTarget(targets,user,selected_target,_move,nearOnly)
    end
  end
end

##MultiplayerDebug.info("MODULE-18", "Target selection synchronization loaded - choices sorted by battler index")
