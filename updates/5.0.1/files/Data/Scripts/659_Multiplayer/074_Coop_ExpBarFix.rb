#===============================================================================
# Co-op Battle EXP Bar Fix
#===============================================================================
# Prevents crash when trying to animate exp bar for battlers that don't have
# dataBox sprites (e.g., remote players' Pokemon in co-op battles after capture)
#===============================================================================

class PokeBattle_Scene
  alias coop_expbar_original_pbEXPBar pbEXPBar

  def pbEXPBar(battler, startExp, endExp, tempExp1, tempExp2)
    return if startExp > endExp
    return if !battler

    # Check if dataBox exists before trying to animate
    dataBox = @sprites["dataBox_#{battler.index}"]
    return if !dataBox

    # DataBox exists, proceed with original behavior
    startExpLevel = tempExp1 - startExp
    endExpLevel   = tempExp2 - startExp
    expRange      = endExp - startExp
    dataBox.animateExp(startExpLevel, endExpLevel, expRange)
    while dataBox.animatingExp; pbUpdate; end
  end
end

##MultiplayerDebug.info("MODULE-EXPBAR", "Co-op exp bar fix loaded - prevents crash on missing dataBox")
