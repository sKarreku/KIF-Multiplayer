#===============================================================================
# Fix: pbLoseMoney crash with NPCTrainers in coop battles
#===============================================================================
# Prevents crash when pbLoseMoney is called with NPCTrainer as pbPlayer
# Only actual Player objects should lose money
#===============================================================================

class PokeBattle_Battle
  alias coop_original_pbLoseMoney pbLoseMoney

  def pbLoseMoney
    # In coop battles, pbPlayer might return an NPCTrainer
    # Only call original if pbPlayer is actually a Player
    return unless pbPlayer.is_a?(Player)

    coop_original_pbLoseMoney
  end
end

##MultiplayerDebug.info("MODULE-23", "pbLoseMoney fix loaded - prevents NPCTrainer crash")
