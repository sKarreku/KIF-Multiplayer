#===============================================================================
# Co-op Battle Scene Safety Hook
#===============================================================================
# Prevents crashes when battle scene tries to show windows on nil sprites
# This can happen after captures when the scene is in a transitional state
#===============================================================================

class PokeBattle_Scene
  alias coop_safety_original_pbShowWindow pbShowWindow
  alias coop_safety_original_pbDisplayPausedMessage pbDisplayPausedMessage

  def pbShowWindow(windowType)
    # In coop battles, safely handle nil sprites that may occur after captures
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      # Check if sprites exist before trying to set visibility
      return unless @sprites
      return unless @sprites["messageBox"]

      # Proceed with original method only if sprites are valid
      coop_safety_original_pbShowWindow(windowType)
    else
      # Not in coop, use original behavior
      coop_safety_original_pbShowWindow(windowType)
    end
  end

  def pbDisplayPausedMessage(msg)
    # In coop battles, safely handle nil sprites
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      return unless @sprites
      return unless @sprites["messageWindow"]
    end

    coop_safety_original_pbDisplayPausedMessage(msg)
  end
end

class PokeBattle_Battle
  alias coop_safety_original_pbDisplayPaused pbDisplayPaused

  def pbDisplayPaused(msg, &block)
    # In coop battles, safely handle scene errors during exp gain after captures
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      # Check if scene and sprites are still valid
      return unless @scene
      return unless @scene.instance_variable_get(:@sprites)

      begin
        coop_safety_original_pbDisplayPaused(msg, &block)
      rescue NoMethodError => e
        # Log the error but don't crash - scene might be in transitional state
        ##MultiplayerDebug.warn("SCENE-SAFETY", "Suppressed scene error: #{e.message}")
        return
      end
    else
      coop_safety_original_pbDisplayPaused(msg, &block)
    end
  end
end

##MultiplayerDebug.info("MODULE-SCENE-SAFETY", "Co-op battle scene safety hook loaded")
