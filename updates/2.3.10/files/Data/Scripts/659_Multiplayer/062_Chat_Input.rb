# ===========================================
# Chat System - Input Module
# F10 (toggle), F11 (cycle tabs), T (open input)
# ===========================================

##MultiplayerDebug.info("CHAT-INPUT", "Chat input module loading...")

module ChatInputHotkeys
  module_function

  begin
    GetAsyncKeyState = Win32API.new('user32', 'GetAsyncKeyState', ['i'], 'i')
    GetForegroundWindow = Win32API.new('user32', 'GetForegroundWindow', [], 'i')
    GetWindowThreadProcessId = Win32API.new('user32', 'GetWindowThreadProcessId', ['i', 'p'], 'i')
    GetKeyboardState = Win32API.new('user32', 'GetKeyboardState', ['p'], 'i')
    ToUnicodeEx = Win32API.new('user32', 'ToUnicodeEx', ['l', 'l', 'p', 'p', 'l', 'l', 'l'], 'l')
    GetKeyboardLayout = Win32API.new('user32', 'GetKeyboardLayout', ['l'], 'l')
    MapVirtualKeyA = Win32API.new('user32', 'MapVirtualKeyA', ['i', 'i'], 'i')
  rescue
    GetAsyncKeyState = nil
    GetForegroundWindow = nil
    GetWindowThreadProcessId = nil
    GetKeyboardState = nil
    ToUnicodeEx = nil
    GetKeyboardLayout = nil
    MapVirtualKeyA = nil
  end

  VK_F10 = 0x79
  VK_F11 = 0x7A
  VK_T = 0x54
  VK_RETURN = 0x0D
  VK_ESCAPE = 0x1B
  VK_BACK = 0x08
  VK_UP = 0x26
  VK_DOWN = 0x28
  VK_SPACE = 0x20

  # VK codes for keys we want to capture (0-9, A-Z, and symbol keys)
  VK_KEYS = (0x30..0x39).to_a + (0x41..0x5A).to_a + # 0-9, A-Z
            [0xBA, 0xBB, 0xBC, 0xBD, 0xBE, 0xBF, 0xC0, 0xDB, 0xDC, 0xDD, 0xDE] # Symbols

  @f10_last_state = false
  @f11_last_state = false
  @t_last_state = false
  @return_last_state = false
  @escape_last_state = false
  @back_last_state = false
  @up_last_state = false
  @down_last_state = false
  @char_last_states = {}  # Track all character keys

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

  def f10_trigger?
    return false unless GetAsyncKeyState
    return false unless window_active?  # Only process if window is active
    current = (GetAsyncKeyState.call(VK_F10) & 0x8000) != 0
    triggered = current && !@f10_last_state
    @f10_last_state = current
    triggered
  rescue
    false
  end

  def f11_trigger?
    return false unless GetAsyncKeyState
    return false unless window_active?  # Only process if window is active
    current = (GetAsyncKeyState.call(VK_F11) & 0x8000) != 0
    triggered = current && !@f11_last_state
    @f11_last_state = current
    triggered
  rescue
    false
  end

  def t_trigger?
    return false unless GetAsyncKeyState
    return false unless window_active?  # Only process if window is active
    current = (GetAsyncKeyState.call(VK_T) & 0x8000) != 0
    triggered = current && !@t_last_state
    @t_last_state = current
    triggered
  rescue
    false
  end

  def return_trigger?
    return false unless GetAsyncKeyState
    return false unless window_active?  # Only process if window is active
    current = (GetAsyncKeyState.call(VK_RETURN) & 0x8000) != 0
    triggered = current && !@return_last_state
    @return_last_state = current
    triggered
  rescue
    false
  end

  def escape_trigger?
    return false unless GetAsyncKeyState
    return false unless window_active?  # Only process if window is active
    current = (GetAsyncKeyState.call(VK_ESCAPE) & 0x8000) != 0
    triggered = current && !@escape_last_state
    @escape_last_state = current
    triggered
  rescue
    false
  end

  def backspace_trigger?
    return false unless GetAsyncKeyState
    return false unless window_active?  # Only process if window is active
    current = (GetAsyncKeyState.call(VK_BACK) & 0x8000) != 0
    triggered = current && !@back_last_state
    @back_last_state = current
    triggered
  rescue
    false
  end

  def up_trigger?
    return false unless GetAsyncKeyState
    return false unless window_active?  # Only process if window is active
    current = (GetAsyncKeyState.call(VK_UP) & 0x8000) != 0
    triggered = current && !@up_last_state
    @up_last_state = current
    triggered
  rescue
    false
  end

  def down_trigger?
    return false unless GetAsyncKeyState
    return false unless window_active?  # Only process if window is active
    current = (GetAsyncKeyState.call(VK_DOWN) & 0x8000) != 0
    triggered = current && !@down_last_state
    @down_last_state = current
    triggered
  rescue
    false
  end

  def space_trigger?
    return false unless GetAsyncKeyState
    return false unless window_active?
    current = (GetAsyncKeyState.call(VK_SPACE) & 0x8000) != 0
    triggered = current && !@char_last_states[VK_SPACE]
    @char_last_states[VK_SPACE] = current
    triggered
  rescue
    false
  end

  def get_char_input(skip_t = false)
    return nil unless ToUnicodeEx && GetKeyboardState && GetAsyncKeyState && MapVirtualKeyA && GetKeyboardLayout
    return nil unless window_active?

    # Get current keyboard layout
    layout = GetKeyboardLayout.call(0)

    VK_KEYS.each do |vk|
      next if skip_t && vk == VK_T  # Skip T if requested

      current = (GetAsyncKeyState.call(vk) & 0x8000) != 0
      was_pressed = @char_last_states[vk] || false
      @char_last_states[vk] = current

      if current && !was_pressed
        # Build keyboard state manually using GetAsyncKeyState for modifier keys
        kbd_state = "\x00" * 256

        # Check if Shift is pressed using GetAsyncKeyState (more reliable than GetKeyboardState)
        shift_pressed = (GetAsyncKeyState.call(0x10) & 0x8000) != 0  # VK_SHIFT
        lshift_pressed = (GetAsyncKeyState.call(0xA0) & 0x8000) != 0  # VK_LSHIFT
        rshift_pressed = (GetAsyncKeyState.call(0xA1) & 0x8000) != 0  # VK_RSHIFT

        # Set the high bit (0x80) if the key is pressed (this is what ToUnicodeEx expects)
        kbd_state[0x10] = shift_pressed ? 0x80.chr : 0x00.chr
        kbd_state[0xA0] = lshift_pressed ? 0x80.chr : 0x00.chr
        kbd_state[0xA1] = rshift_pressed ? 0x80.chr : 0x00.chr

        # Debug log
        ##MultiplayerDebug.info("CHAT-INPUT-SHIFT", "VK=0x#{vk.to_s(16)} Shift=#{shift_pressed} LShift=#{lshift_pressed} RShift=#{rshift_pressed}") if defined?(MultiplayerDebug)

        # Convert VK to scan code
        scan_code = MapVirtualKeyA.call(vk, 0)

        # Output buffer for Unicode character (4 bytes to hold wchar_t)
        buffer = "\x00\x00\x00\x00"

        # Convert to Unicode using current layout
        result = ToUnicodeEx.call(vk, scan_code, kbd_state, buffer, 2, 0, layout)

        # Verbose debug logging
        ##MultiplayerDebug.info("CHAT-INPUT-VK", "VK=0x#{vk.to_s(16)} scan=#{scan_code} result=#{result}") if defined?(MultiplayerDebug)

        if result == 1
          # Successfully converted to a single character
          begin
            # Unpack as little-endian 16-bit unsigned (UTF-16LE)
            char = buffer.unpack1('v')

            # Debug log character codepoint
            ##MultiplayerDebug.info("CHAT-INPUT-CHAR", "VK=0x#{vk.to_s(16)} char=#{char} (0x#{char.to_s(16)})") if defined?(MultiplayerDebug)

            # Skip null characters
            next if char.nil? || char == 0

            # Skip control characters EXCEPT for printable ASCII (32+) and valid Unicode
            # Allow: 32-126 (printable ASCII), 128+ (extended Unicode)
            next if char > 0 && char < 32

            # Skip invalid Unicode codepoints
            next if char > 0x10FFFF

            # Skip surrogate pairs (these are only valid in UTF-16 pairs, not standalone)
            next if char >= 0xD800 && char <= 0xDFFF

            # Convert UTF-16 codepoint to UTF-8 string
            utf8_char = [char].pack('U*').force_encoding('UTF-8')

            # Final validation
            next unless utf8_char && utf8_char.valid_encoding? && !utf8_char.empty?

            # Debug log successful conversion
            ##MultiplayerDebug.info("CHAT-INPUT-OK", "Converted VK=0x#{vk.to_s(16)} to '#{utf8_char}'") if defined?(MultiplayerDebug)

            return utf8_char
          rescue => e
            # Skip characters that can't be encoded - log without including the error message to avoid encoding errors
            ##MultiplayerDebug.info("CHAT-INPUT-ERR", "Conversion failed for VK=0x#{vk.to_s(16)} char=#{char}") if defined?(MultiplayerDebug)
            next
          end
        elsif result == -1
          # Dead key - ignore for now (would need to call twice to get accent)
          next
        elsif result > 1
          # Multiple characters returned - skip complex input
          next
        end
      end
    end

    nil
  rescue => e
    # Don't log the error message to avoid encoding errors in the logger itself
    ##MultiplayerDebug.error("CHAT-INPUT", "get_char_input error occurred") if defined?(MultiplayerDebug)
    nil
  end
end

module Input
  unless defined?(update_multiplayer_chat_input)
    class << Input
      alias update_multiplayer_chat_input update
    end
  end

  def self.update
    # Block player movement if typing
    if $chat_window && $chat_window.input_mode
      # Skip normal input update to prevent movement
      handle_typing_mode
      return
    end

    update_multiplayer_chat_input

    return unless $chat_initialized

    begin
      handle_hotkeys
    rescue => e
      ##MultiplayerDebug.error("CHAT-INPUT", "Hotkey error: #{e.message}")
    end
  end

  def self.handle_hotkeys
    # F10: Toggle visibility
    if ChatInputHotkeys.f10_trigger?
      if defined?(ChatState)
        ChatState.toggle_visibility
        vis = ChatState.visible
        ##MultiplayerDebug.info("CHAT-INPUT", "F10 pressed - toggled visibility to #{vis}")
      end
    end

    # F11: Cycle tabs (and reset scroll)
    if ChatInputHotkeys.f11_trigger?
      ChatTabs.cycle_next if defined?(ChatTabs)
      $chat_window.reset_scroll if $chat_window
      ##MultiplayerDebug.info("CHAT-INPUT", "F11 pressed - cycled tabs")
    end

    # Up/Down: Scroll messages
    if ChatInputHotkeys.up_trigger?
      $chat_window.scroll_up if $chat_window
    end

    if ChatInputHotkeys.down_trigger?
      $chat_window.scroll_down if $chat_window
    end

    # T: Open input (only if chat visible, on overworld, not in menu/battle)
    if ChatInputHotkeys.t_trigger?
      if defined?(ChatState) && ChatState.visible &&
         $scene && $scene.is_a?(Scene_Map) &&
         !$game_temp.in_menu &&
         !$game_temp.in_battle &&
         !$game_player.move_route_forcing
        open_chat_input
        ##MultiplayerDebug.info("CHAT-INPUT", "T pressed - opening chat input")
      end
    end
  end

  def self.handle_typing_mode
    # Handle character input
    char = ChatInputHotkeys.get_char_input(false)  # Don't skip T anymore - state is already cleared
    if char
      current_text = $chat_window.get_input_text
      $chat_window.set_input_text(current_text + char) if current_text.length < 150
    end

    # Handle space
    if ChatInputHotkeys.space_trigger?
      current_text = $chat_window.get_input_text
      $chat_window.set_input_text(current_text + " ") if current_text.length < 150
    end

    # Handle backspace
    if ChatInputHotkeys.backspace_trigger?
      current_text = $chat_window.get_input_text
      $chat_window.set_input_text(current_text[0...-1]) if current_text.length > 0
    end

    # Handle Enter - submit message
    if ChatInputHotkeys.return_trigger?
      text = $chat_window.get_input_text
      $chat_window.input_mode = false
      $chat_window.clear_input

      unless text.nil? || text.empty?
        cmd = ChatCommands.parse(text)
        if cmd
          ChatNetwork.send_command(cmd)
        else
          ChatNetwork.send_message(text)
        end
        ##MultiplayerDebug.info("CHAT-INPUT", "Sent: #{text[0..30]}...")
      end
    end

    # Handle Escape - cancel input
    if ChatInputHotkeys.escape_trigger?
      $chat_window.input_mode = false
      $chat_window.clear_input
    end
  end

  def self.open_chat_input
    return unless defined?(ChatTabs) && defined?(ChatCommands) && defined?(ChatNetwork)

    begin
      $chat_window.input_mode = true
      $chat_window.reset_scroll
      $chat_window.clear_input

      # Clear T key state to prevent typing "t" when opening
      ChatInputHotkeys.instance_variable_set(:@char_last_states,
        ChatInputHotkeys.instance_variable_get(:@char_last_states).merge({ChatInputHotkeys::VK_T => true}))

      ##MultiplayerDebug.info("CHAT-INPUT", "Chat input opened")
    rescue => e
      $chat_window.input_mode = false if $chat_window
      ##MultiplayerDebug.error("CHAT-INPUT", "Input error: #{e.message}")
    end
  end
end

##MultiplayerDebug.info("CHAT-INPUT", "Chat input module loaded successfully")
