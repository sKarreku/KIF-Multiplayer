#===============================================================================
# Multiplayer Menu Busy State Hook
# Marks player as "busy" when in any menu (party, bag, PC, etc.)
# Also marks player as "busy" when in NPC dialogue or not on overworld
# This prevents coop wild battles from trying to sync with unavailable players
#===============================================================================

# Helper to safely mark menu state
def mp_mark_menu_safe(state)
  return unless defined?(MultiplayerClient)
  begin
    MultiplayerClient.mark_menu(state)
  rescue
    # Silently ignore if not connected or method fails
  end
end

# Helper to safely mark event state (NPC dialogue, cutscene, not on overworld)
def mp_mark_event_safe(state)
  return unless defined?(MultiplayerClient)
  begin
    MultiplayerClient.mark_event(state)
  rescue
    # Silently ignore if not connected or method fails
  end
end

# Check if player is currently in an event (NPC dialogue, cutscene, etc.)
def mp_check_in_event?
  # Check if message window is showing (NPC dialogue)
  if $game_temp && $game_temp.respond_to?(:message_window_showing)
    return true if $game_temp.message_window_showing
  end

  # Use the game's built-in pbMapInterpreterRunning? if available
  if defined?(pbMapInterpreterRunning?)
    return true if pbMapInterpreterRunning?
  end

  # Fallback: Check interpreter directly
  if $game_system && $game_system.respond_to?(:map_interpreter)
    interp = $game_system.map_interpreter
    return true if interp && interp.respond_to?(:running?) && interp.running?
  end

  false
end

# Check if player is on the overworld (Scene_Map)
def mp_on_overworld?
  return false unless $scene
  $scene.is_a?(Scene_Map)
end

# Hook pbFadeOutIn to detect when player enters/exits menus
# Almost ALL menus in Pokemon Essentials use this function for screen transitions
if defined?(pbFadeOutIn)
  alias mp_original_pbFadeOutIn pbFadeOutIn

  def pbFadeOutIn(z = 99999, nofadeout = false)
    # Mark player as busy (entering menu)
    mp_mark_menu_safe(true)

    begin
      # Call original (runs the menu)
      mp_original_pbFadeOutIn(z, nofadeout) { yield if block_given? }
    ensure
      # Mark player as not busy (exiting menu)
      mp_mark_menu_safe(false)
    end
  end
end

# Also hook Scene_Map.call_menu for the pause menu specifically
# This catches cases where the pause menu might not use pbFadeOutIn
class Scene_Map
  if method_defined?(:call_menu)
    alias mp_original_call_menu call_menu

    def call_menu
      # Mark player as busy
      mp_mark_menu_safe(true)

      begin
        mp_original_call_menu
      ensure
        # Mark player as not busy
        mp_mark_menu_safe(false)
      end
    end
  end

end

# Hook into Graphics.update to detect event/dialogue state
# This runs every frame regardless of current scene
if defined?(Graphics)
  class << Graphics
    alias mp_original_update update

    def update
      mp_original_update

      # Determine if player is in an event/dialogue or not on overworld
      if mp_on_overworld?
        # On overworld: check if in NPC dialogue or event script
        in_event = mp_check_in_event?
      else
        # Not on overworld (battle scene excluded, shops, Pokemon centers, etc.)
        # Mark as busy unless we're in a scene that already handles busy state
        in_event = true
      end

      mp_mark_event_safe(in_event)

      # Play queued server gift animation when on overworld and not busy
      if defined?(ServerGiftAnimation) &&
         ServerGiftAnimation.pending? &&
         !ServerGiftAnimation.playing? &&
         mp_on_overworld? &&
         defined?(MultiplayerClient) &&
         !MultiplayerClient.player_busy?
        ServerGiftAnimation.play_next
      end
    end
  end
end
