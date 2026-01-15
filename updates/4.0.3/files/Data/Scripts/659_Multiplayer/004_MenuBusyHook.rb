#===============================================================================
# Multiplayer Menu Busy State Hook
# Marks player as "busy" when in any menu (party, bag, PC, etc.)
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
