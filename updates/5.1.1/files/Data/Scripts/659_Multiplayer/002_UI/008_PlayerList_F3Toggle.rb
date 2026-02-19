# ===========================================
# File: 048_UI_PlayerList_F3Toggle.rb
# Purpose: Add F3 hotkey to toggle Player List
# ===========================================

##MultiplayerDebug.info("UI-F3", "Player List F3 toggle loaded.")

module PlayerListF3Compat
  module_function
  begin
    GetAsyncKeyState = Win32API.new('user32', 'GetAsyncKeyState', ['i'], 'i')
    GetForegroundWindow = Win32API.new('user32', 'GetForegroundWindow', [], 'i')
    GetWindowThreadProcessId = Win32API.new('user32', 'GetWindowThreadProcessId', ['i', 'p'], 'i')
  rescue
    GetAsyncKeyState = nil
    GetForegroundWindow = nil
    GetWindowThreadProcessId = nil
  end

  VK_F3 = 0x72

  # Check if the game window is the active foreground window
  def window_active?
    return true unless GetForegroundWindow && GetWindowThreadProcessId

    begin
      foreground = GetForegroundWindow.call
      return true if foreground == 0  # Fallback if can't get window

      # Get process ID of foreground window
      process_id = [0].pack('L')
      GetWindowThreadProcessId.call(foreground, process_id)
      foreground_pid = process_id.unpack('L')[0]

      # Compare with current process ID
      current_pid = Process.pid
      return foreground_pid == current_pid
    rescue
      true  # Fallback to allowing inputs if check fails
    end
  end

  def f3_trigger?
    return false unless GetAsyncKeyState
    return false unless window_active?  # Only process if window is active
    (GetAsyncKeyState.call(VK_F3) & 0x01) != 0
  rescue
    false
  end
end

module Input
  unless defined?(update_multiplayer_f3_playerlist)
    class << Input
      alias update_multiplayer_f3_playerlist update
    end
  end

  def self.update
    update_multiplayer_f3_playerlist

    # F3: Toggle Player List
    if PlayerListF3Compat.f3_trigger?
      begin
        # Check if Player List is already open - if so, request close
        if MultiplayerUI.instance_variable_get(:@playerlist_open)
          ##MultiplayerDebug.info("UI-F3-CLOSE", "F3 pressed - requesting Player List close")
          MultiplayerUI.instance_variable_set(:@playerlist_close_requested, true)
        # Only open Player List if connected and on overworld map
        elsif MultiplayerClient.instance_variable_get(:@connected) &&
           $scene && $scene.is_a?(Scene_Map) &&
           !$game_temp.in_menu &&
           !$game_temp.in_battle &&
           !$game_player.move_route_forcing
          ##MultiplayerDebug.info("UI-F3-OPEN", "F3 pressed - opening Player List")
          MultiplayerUI.openPlayerList
        elsif !MultiplayerClient.instance_variable_get(:@connected)
          ##MultiplayerDebug.info("UI-F3-SKIP", "F3 pressed but not connected")
        else
          ##MultiplayerDebug.info("UI-F3-SKIP", "F3 pressed but not on overworld map")
        end
      rescue => e
        ##MultiplayerDebug.error("UI-F3-ERR", "F3 Player List error: #{e.message}")
      end
    end
  end
end

##MultiplayerDebug.info("UI-F3-OK", "F3 Player List toggle hooked successfully.")
