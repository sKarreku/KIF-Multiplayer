#===============================================================================
# pbAfterBattle Alias - Fix nil Pokemon crash in coop battles
#===============================================================================
# Wraps pbAfterBattle to skip nil entries in $Trainer.party
# This prevents crashes when coop battles add nil padding to party arrays
#===============================================================================

# Save original method
alias coop_original_pbAfterBattle pbAfterBattle

def pbAfterBattle(decision, canLose)
  # Remove nil entries from $Trainer.party before calling original
  # This prevents crash when iterating over party with nil Pokemon
  # CRITICAL: Don't restore nils - evolution check (Events.onEndBattle) runs AFTER
  # and crashes when accessing nil party entries
  $Trainer.party.compact!  # Remove nils in-place

  # Call original pbAfterBattle with cleaned party
  coop_original_pbAfterBattle(decision, canLose)
end

##MultiplayerDebug.info("MODULE-99", "pbAfterBattle alias loaded - prevents nil Pokemon crash")
