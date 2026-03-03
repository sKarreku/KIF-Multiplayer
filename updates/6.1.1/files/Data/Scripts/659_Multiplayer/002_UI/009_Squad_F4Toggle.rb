# ===========================================
# File: 051_UI_Squad_F4Toggle.rb
# Purpose: Add F4 hotkey to toggle Squad menu
# ===========================================

##MultiplayerDebug.info("UI-F4", "Squad menu F4 toggle loaded.")

module SquadMenuF4Compat
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

  VK_F4 = 0x73

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

  def f4_trigger?
    return false unless GetAsyncKeyState
    return false unless window_active?  # Only process if window is active
    (GetAsyncKeyState.call(VK_F4) & 0x01) != 0
  rescue
    false
  end
end

module Input
  unless defined?(update_multiplayer_f4_squad)
    class << Input
      alias update_multiplayer_f4_squad update
    end
  end

  def self.update
    update_multiplayer_f4_squad

    # F4: Toggle Squad Menu
    if SquadMenuF4Compat.f4_trigger?
      begin
        # Check if Squad menu is already open - if so, request close
        if MultiplayerUI.instance_variable_get(:@squadwindow_open)
          ##MultiplayerDebug.info("UI-F4-CLOSE", "F4 pressed - requesting Squad menu close")
          MultiplayerUI.instance_variable_set(:@squadwindow_close_requested, true)
        # Only open Squad menu if connected, in squad, and on overworld map
        elsif MultiplayerClient.instance_variable_get(:@connected) &&
           MultiplayerClient.in_squad? &&
           $scene && $scene.is_a?(Scene_Map) &&
           !$game_temp.in_menu &&
           !$game_temp.in_battle &&
           !$game_player.move_route_forcing
          ##MultiplayerDebug.info("UI-F4-OPEN", "F4 pressed - opening Squad menu")
          MultiplayerUI.openSquadWindow
        elsif !MultiplayerClient.instance_variable_get(:@connected)
          ##MultiplayerDebug.info("UI-F4-SKIP", "F4 pressed but not connected")
        elsif !MultiplayerClient.in_squad?
          ##MultiplayerDebug.info("UI-F4-SKIP", "F4 pressed but not in squad")
        else
          ##MultiplayerDebug.info("UI-F4-SKIP", "F4 pressed but not on overworld map")
        end
      rescue => e
        ##MultiplayerDebug.error("UI-F4-ERR", "F4 Squad menu error: #{e.message}")
      end
    end
  end
end

##MultiplayerDebug.info("UI-F4-OK", "F4 Squad menu toggle hooked successfully.")
