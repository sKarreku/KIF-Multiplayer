#===============================================================================
# Co-op Pokedex Registration Fix - DISABLED
#===============================================================================
# This file previously duplicated catch processing logic, causing non-catchers
# to see prompts and lose Pokemon. Processing is now handled by 029_Coop_StorePokemon_Alias.rb
# which properly filters by SID before calling the original method.
#
# This file is kept for reference but disabled to prevent conflicts.
#===============================================================================

# DISABLED - functionality moved to 029_Coop_StorePokemon_Alias.rb

##MultiplayerDebug.info("MODULE-POKEDEX", "Co-op pokedex fix DISABLED - see 029_Coop_StorePokemon_Alias.rb")
