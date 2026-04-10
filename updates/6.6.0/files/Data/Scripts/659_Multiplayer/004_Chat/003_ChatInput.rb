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
  # 0x20 (Space) is first so dead key + space resolves correctly via ToUnicodeEx
  # 0xC1 = OEM_ABNT_C1 (dedicated / key on Brazilian ABNT2 keyboards)
  # 0xC2 = OEM_ABNT_C2 (decimal separator key on Brazilian ABNT2 keyboards)
  # 0x60..0x69 = Numpad 0-9
  # 0x6A..0x6F = Numpad *, +, separator, -, ., /
  VK_KEYS = [0x20] +                                   # Space (handles dead key + space for accents)
             (0x30..0x39).to_a + (0x41..0x5A).to_a +  # 0-9, A-Z
             (0x60..0x6F).to_a +                       # Numpad 0-9 and operators (*, +, -, ., /)
             [0xBA, 0xBB, 0xBC, 0xBD, 0xBE, 0xBF,     # Common symbols
              0xC0, 0xC1, 0xC2,                         # Grave/tilde, ABNT C1, ABNT C2
              0xDB, 0xDC, 0xDD, 0xDE]                   # Brackets, backslash, quote

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

        # Check modifier keys via GetAsyncKeyState
        shift_pressed  = (GetAsyncKeyState.call(0x10) & 0x8000) != 0  # VK_SHIFT
        lshift_pressed = (GetAsyncKeyState.call(0xA0) & 0x8000) != 0  # VK_LSHIFT
        rshift_pressed = (GetAsyncKeyState.call(0xA1) & 0x8000) != 0  # VK_RSHIFT
        altgr_pressed  = (GetAsyncKeyState.call(0xA5) & 0x8000) != 0  # VK_RMENU (AltGr)
        ctrl_pressed   = (GetAsyncKeyState.call(0x11) & 0x8000) != 0  # VK_CONTROL
        lctrl_pressed  = (GetAsyncKeyState.call(0xA2) & 0x8000) != 0  # VK_LCONTROL

        # Set the high bit (0x80) if the key is pressed (this is what ToUnicodeEx expects)
        kbd_state[0x10] = shift_pressed  ? 0x80.chr : 0x00.chr  # VK_SHIFT
        kbd_state[0xA0] = lshift_pressed ? 0x80.chr : 0x00.chr  # VK_LSHIFT
        kbd_state[0xA1] = rshift_pressed ? 0x80.chr : 0x00.chr  # VK_RSHIFT

        # AltGr (Right Alt) support — critical for non-US keyboards (Brazilian, French, German, etc.)
        # Windows internally treats AltGr as Ctrl+Alt, so we must set both VK_RMENU and VK_CONTROL
        if altgr_pressed
          kbd_state[0x12] = 0x80.chr  # VK_MENU
          kbd_state[0xA5] = 0x80.chr  # VK_RMENU
          kbd_state[0x11] = 0x80.chr  # VK_CONTROL
          kbd_state[0xA2] = 0x80.chr  # VK_LCONTROL
        else
          kbd_state[0x11] = ctrl_pressed  ? 0x80.chr : 0x00.chr  # VK_CONTROL
          kbd_state[0xA2] = lctrl_pressed ? 0x80.chr : 0x00.chr  # VK_LCONTROL
        end

        # Debug log
        ##MultiplayerDebug.info("CHAT-INPUT-SHIFT", "VK=0x#{vk.to_s(16)} Shift=#{shift_pressed} AltGr=#{altgr_pressed}") if defined?(MultiplayerDebug)

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
    # F10: Toggle deploy
    if ChatInputHotkeys.f10_trigger?
      if defined?(ChatState)
        # If typing, cancel first
        if $chat_window && $chat_window.input_mode
          $chat_window.input_mode = false
          $chat_window.clear_input
          Input.text_input = false rescue nil
        end
        ChatState.toggle_deploy
      end
    end

    # F11: Cycle tabs (and reset scroll)
    if ChatInputHotkeys.f11_trigger?
      if defined?(ChatTabs) && ChatState.deployed
        ChatTabs.cycle_next
        ChatState.unread_clear(ChatTabs.current_tab_name)
        $chat_window.reset_scroll if $chat_window
        $chat_window.mark_tabs_dirty if $chat_window
        $chat_window.mark_messages_dirty if $chat_window
      end
    end

    # Up/Down: Scroll messages
    if ChatInputHotkeys.up_trigger? && ChatState.deployed
      $chat_window.scroll_up if $chat_window
    end
    if ChatInputHotkeys.down_trigger? && ChatState.deployed
      $chat_window.scroll_down if $chat_window
    end

    # T: Open input (only if deployed, on overworld, not in menu/battle)
    if ChatInputHotkeys.t_trigger?
      if defined?(ChatState) && ChatState.deployed &&
         $scene && $scene.is_a?(Scene_Map) &&
         !$game_temp.in_menu &&
         !$game_temp.in_battle &&
         !$game_player.move_route_forcing
        open_chat_input
      end
    end

    # ── Mouse input ──────────────────────────────────────
    _handle_mouse if $chat_window
  end

  def self._handle_mouse
    return unless $chat_window
    mx = (Input.mouse_x rescue nil)
    my = (Input.mouse_y rescue nil)
    return unless mx && my

    clicked = (Input.trigger?(Input::MOUSELEFT)  rescue false)
    rclick  = (Input.trigger?(Input::MOUSERIGHT) rescue false)
    mw      = (Input.mouse_wheel rescue 0).to_i

    cw = $chat_window
    px = cw.panel_x
    py = cw.panel_y
    hx = cw.handle_x
    hy = cw.handle_y

    # ── Context menu interaction (highest priority) ────
    if cw.ctx_open?
      cx = cw.instance_variable_get(:@ctx_sprite).x
      cy = cw.instance_variable_get(:@ctx_sprite).y
      ctx_h = ChatWindow::CTX_PAD * 2 + 16 + cw.ctx_items.length * ChatWindow::CTX_ITEM_H

      over_ctx = mx >= cx && mx < cx + ChatWindow::CTX_W &&
                 my >= cy && my < cy + ctx_h
      if over_ctx
        # Hover detection on items
        rel_y = my - cy - ChatWindow::CTX_PAD - 16
        if rel_y >= 0
          idx = (rel_y / ChatWindow::CTX_ITEM_H).to_i
          idx = nil if idx >= cw.ctx_items.length
          cw.ctx_hover = idx
        else
          cw.ctx_hover = nil
        end

        # Click on item
        if clicked && cw.ctx_hover
          _execute_ctx_action(cw.ctx_hover, cw.ctx_sid, cw.ctx_name)
          cw.close_context_menu
        end
        return
      else
        # Click outside context menu = close it
        if clicked || rclick
          cw.close_context_menu
        end
        cw.ctx_hover = nil
        return if cw.ctx_open?  # still open if no click
      end
    end

    # ── Handle hover/click ─────────────────────────────
    over_handle = mx >= hx && mx < hx + ChatWindow::HANDLE_W &&
                  my >= hy && my < hy + ChatWindow::HANDLE_H
    cw.mouse_over_handle = over_handle

    if clicked && over_handle
      if cw.input_mode
        cw.input_mode = false
        cw.clear_input
        Input.text_input = false rescue nil
      end
      ChatState.toggle_deploy
      return
    end

    # Everything below requires the panel to be deployed
    return unless ChatState.deploy_progress > 0.9

    # ── Panel hover detection ──────────────────────────
    over_panel = mx >= px && mx < px + ChatWindow::PANEL_W &&
                 my >= py && my < py + ChatWindow::PANEL_H
    cw.mouse_over_panel = over_panel

    # ── Right-click on message = context menu ──────────
    if rclick
      msg_x = px + ChatWindow::MSG_PAD
      msg_y = py + ChatWindow::MSG_Y
      if mx >= msg_x && mx < msg_x + ChatWindow::MSG_W &&
         my >= msg_y && my < msg_y + ChatWindow::MSG_H
        # Find which SID was clicked
        rel_y = my - msg_y
        hit = cw.msg_sid_map.find { |entry| rel_y >= entry[:y] && rel_y < entry[:y] + entry[:h] }
        if hit
          cw.open_context_menu(hit[:sid], hit[:name], mx, my)
          return
        end
      end
    end

    # ── Tab click/hover ────────────────────────────────
    tabs = ChatTabs.tab_list rescue []
    unless tabs.empty?
      tab_w = [(ChatWindow::PANEL_W / tabs.length).to_i, 50].max
      tab_y = py
      if my >= tab_y && my < tab_y + ChatWindow::TAB_H && mx >= px && mx < px + tabs.length * tab_w
        tab_idx = ((mx - px) / tab_w).to_i
        tab_idx = nil if tab_idx >= tabs.length
        cw.hover_tab = tab_idx

        if clicked && tab_idx
          ChatState.active_tab_index = tab_idx
          ChatState.unread_clear(tabs[tab_idx])
          cw.reset_scroll
          cw.mark_tabs_dirty
          cw.mark_messages_dirty
        end

        # Right-click on a PM tab closes it
        if rclick && tab_idx
          tab_key = tabs[tab_idx]
          if ChatTabs.has_pm_tab?(tab_key)
            ChatTabs.close_pm_tab(tab_key)
            # Clamp active tab if it got cut off the end
            new_list = ChatTabs.tab_list
            if ChatState.active_tab_index >= new_list.length
              ChatState.active_tab_index = new_list.length - 1
            end
            cw.hover_tab = nil
            cw.reset_scroll
            cw.mark_tabs_dirty
            cw.mark_messages_dirty
            return
          end
        end
      else
        cw.hover_tab = nil
      end
    end

    # ── Input area click ───────────────────────────────
    inp_x = px + ChatWindow::MSG_PAD
    inp_y = py + ChatWindow::INPUT_Y
    if clicked && !cw.input_mode &&
       mx >= inp_x && mx < inp_x + ChatWindow::INPUT_W &&
       my >= inp_y && my < inp_y + ChatWindow::INPUT_H
      if $scene && $scene.is_a?(Scene_Map) &&
         !$game_temp.in_menu && !$game_temp.in_battle &&
         !$game_player.move_route_forcing
        open_chat_input
      end
    end

    # ── Scroll wheel over messages ─────────────────────
    if mw != 0
      msg_x = px + ChatWindow::MSG_PAD
      msg_y = py + ChatWindow::MSG_Y
      if mx >= msg_x && mx < msg_x + ChatWindow::MSG_W &&
         my >= msg_y && my < msg_y + ChatWindow::MSG_H
        if mw > 0
          cw.scroll_up(2)
        else
          cw.scroll_down(2)
        end
      end
    end
  end

  # ── Context menu action execution ───────────────────
  def self._execute_ctx_action(idx, sid, name)
    return unless defined?(MultiplayerClient) && sid

    case idx
    when 0  # View Profile
      uuid = _uuid_for_sid(sid)
      if uuid && defined?(MultiplayerUI::ProfilePanel)
        MultiplayerUI::ProfilePanel.open(uuid: uuid)
      else
        ChatMessages.add_message("Global", "SYSTEM", "System", "Profile not available for #{name}.")
      end
    when 1  # Send PM
      _open_pm_tab_and_focus(sid, name)
    when 2  # Invite to Squad
      MultiplayerClient.invite_player(sid) rescue nil
    when 3  # Battle Request
      MultiplayerClient.pvp_invite(sid) rescue nil
    when 4  # Request Trade
      MultiplayerClient.trade_invite(sid) rescue nil
    when 5  # Inspect Party
      if defined?(MultiplayerUI::PartyInspect)
        MultiplayerUI::PartyInspect.open(sid)
      end
    end
  end

  # Open (or focus) a PM tab with this player and jump to input.
  def self._open_pm_tab_and_focus(sid, name)
    return unless defined?(ChatTabs) && defined?(ChatState)

    # Open the PM tab if it doesn't exist yet (no-op if already open)
    unless ChatTabs.has_pm_tab?(sid)
      opened = ChatTabs.open_pm_tab(sid, name.to_s)
      unless opened
        ChatMessages.add_message("Global", "SYSTEM", "System",
          "Cannot open PM with #{name} (PM tab limit reached).") if defined?(ChatMessages)
        return
      end
    end

    # Switch active tab to this PM
    tab_key = ChatTabs.pm_tab_name(sid)
    list = ChatTabs.tab_list
    idx = list.index(sid)
    if idx
      ChatState.active_tab_index = idx
      ChatState.unread_clear(tab_key) if ChatState.respond_to?(:unread_clear)
    end

    # Ensure chat is deployed & start typing
    ChatState.deployed = true
    $chat_window.reset_scroll if $chat_window
    $chat_window.mark_tabs_dirty if $chat_window && $chat_window.respond_to?(:mark_tabs_dirty)
    $chat_window.mark_messages_dirty if $chat_window && $chat_window.respond_to?(:mark_messages_dirty)

    open_chat_input if $chat_window
  end

  # ── UUID lookup from SID via player list ────────────
  def self._uuid_for_sid(sid)
    return nil unless defined?(MultiplayerClient)
    list = MultiplayerClient.instance_variable_get(:@player_list) rescue nil
    # Request player list if not yet fetched
    if !list || !list.is_a?(Array) || list.empty?
      MultiplayerClient.send_data("REQ_PLAYERS") rescue nil
      return nil
    end

    list.each do |entry|
      entry_sid, _name, uuid = MultiplayerUI.parse_player_entry(entry)
      next unless entry_sid
      if entry_sid.upcase == sid.to_s.upcase
        return uuid if uuid && !uuid.empty?
      end
    end
    nil
  end

  def self.handle_typing_mode
    # Ensure SDL text input is enabled (routes IME / Unicode events)
    Input.text_input = true rescue nil

    # Pull composed text from SDL (handles IME, clipboard paste, dead keys, Unicode)
    composed = (Input.gets rescue nil)
    if composed && !composed.empty?
      # Strip control chars that might slip through (newline/tab/etc.)
      composed = composed.gsub(/[\r\n\t]/, "")
      unless composed.empty?
        current_text = $chat_window.get_input_text
        remaining = 150 - current_text.length
        if remaining > 0
          $chat_window.set_input_text(current_text + composed[0, remaining])
        end
      end
    end

    # Handle backspace
    if ChatInputHotkeys.backspace_trigger?
      current_text = $chat_window.get_input_text
      # Unicode-safe trim: drop last grapheme (codepoint)
      if current_text.length > 0
        $chat_window.set_input_text(current_text[0...-1])
      end
    end

    # Handle Enter - submit message
    if ChatInputHotkeys.return_trigger?
      text = $chat_window.get_input_text
      $chat_window.input_mode = false
      $chat_window.clear_input
      Input.text_input = false rescue nil

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
      Input.text_input = false rescue nil
      return
    end

    # Click outside panel = cancel input
    mx = (Input.mouse_x rescue nil)
    my = (Input.mouse_y rescue nil)
    clicked = (Input.trigger?(Input::MOUSELEFT) rescue false)
    if clicked && mx && my
      px = $chat_window.panel_x
      py = $chat_window.panel_y
      unless mx >= px && mx < px + ChatWindow::PANEL_W &&
             my >= py && my < py + ChatWindow::PANEL_H
        $chat_window.input_mode = false
        $chat_window.clear_input
        Input.text_input = false rescue nil
      end
    end
  end

  def self.open_chat_input
    return unless defined?(ChatTabs) && defined?(ChatCommands) && defined?(ChatNetwork)

    begin
      $chat_window.input_mode = true
      $chat_window.reset_scroll
      $chat_window.clear_input

      # Enable SDL text input (IME, Unicode, clipboard paste)
      Input.text_input = true rescue nil
      # Drain any stale text buffered from before (e.g. the "t" keypress that opened chat)
      (Input.gets rescue nil)

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
