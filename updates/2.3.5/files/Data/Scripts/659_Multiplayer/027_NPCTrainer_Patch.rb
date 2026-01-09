#===============================================================================
# NPCTrainer Patches - Missing Methods
#===============================================================================
# Adds missing methods to NPCTrainer that vanilla battle code expects
# These methods exist on Player but not on NPCTrainer
#===============================================================================

class NPCTrainer
  # Multiplayer session ID for remote players
  attr_accessor :multiplayer_sid

  # Check if a species is owned (in pokedex)
  # For remote players, we don't have access to their pokedex, so return false
  # This prevents errors when battle code checks owned? status
  def owned?(species)
    return false
  end

  # Ensure pokedex exists and has required methods
  # This patches the dummy pokedex that's created in 017_Coop_WildHook_v2.rb
  def pokedex
    unless @pokedex
      # Create a more complete dummy pokedex
      @pokedex = Class.new do
        def register(*args); end
        def seen?(*args); false; end
        def owned?(*args); false; end
        def set_owned(*args); end  # Add missing method
        def get_owned(*args); 0; end
      end.new
    end
    return @pokedex
  end
end

##MultiplayerDebug.info("MODULE-11", "NPCTrainer patches loaded - added owned? and pokedex methods")
