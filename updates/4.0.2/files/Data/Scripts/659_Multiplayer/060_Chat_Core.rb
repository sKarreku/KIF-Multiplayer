# ===========================================
# Chat System - Core Module
# All state, messages, tabs, blocks, commands, network
# ===========================================

# === ChatState: Visibility and active tab ===
module ChatState
  @visible = false  # Hidden by default, toggle with F10
  @active_tab_index = 0

  def self.visible; @visible; end
  def self.visible=(v); @visible = v; end
  def self.toggle_visibility; @visible = !@visible; end

  def self.active_tab_index; @active_tab_index; end
  def self.active_tab_index=(idx); @active_tab_index = idx; end

  def self.reset
    @visible = false  # Hidden by default on reset
    @active_tab_index = 0
  end
end

# === ChatMessages: Message storage (150 char limit, 100 buffer) ===
module ChatMessages
  @messages = {
    "Global" => [],
    "Trade" => []
  }
  @pm_messages = {}  # { "SID123" => [...] }

  MAX_CHARS = 150
  MAX_BUFFER = 100

  def self.add_message(tab_key, sid, name, text, is_owner: false)
    text = text.to_s[0..MAX_CHARS-1]
    msg = { sid: sid, name: name, text: text, is_owner: is_owner }

    if tab_key == "Global" || tab_key == "Trade"
      @messages[tab_key] ||= []
      @messages[tab_key] << msg
      @messages[tab_key].shift if @messages[tab_key].length > MAX_BUFFER
    else
      # PM or Squad
      @pm_messages[tab_key] ||= []
      @pm_messages[tab_key] << msg
      @pm_messages[tab_key].shift if @pm_messages[tab_key].length > MAX_BUFFER
    end
  end

  def self.get_messages(tab_key)
    if tab_key == "Global" || tab_key == "Trade"
      @messages[tab_key] || []
    else
      @pm_messages[tab_key] || []
    end
  end

  def self.clear_pm_messages(sid)
    @pm_messages.delete(sid)
  end

  def self.reset
    @messages = { "Global" => [], "Trade" => [] }
    @pm_messages = {}
  end
end

# === ChatTabs: Tab list, cycling, PM tabs (max 2) ===
module ChatTabs
  @pm_tabs = {}  # { "SID123" => "PlayerName" }
  MAX_PM_TABS = 2

  def self.tab_list
    base = ["Global", "Trade"]
    base << "Squad" if in_squad?
    base + @pm_tabs.keys
  end

  def self.current_tab_name
    list = tab_list
    idx = ChatState.active_tab_index
    idx = 0 if idx >= list.length
    list[idx]
  end

  def self.cycle_next
    list = tab_list
    idx = (ChatState.active_tab_index + 1) % list.length
    ChatState.active_tab_index = idx
  end

  def self.open_pm_tab(sid, name)
    return false if @pm_tabs.length >= MAX_PM_TABS
    return true if @pm_tabs.key?(sid)  # Already open

    # Don't open a tab for your own SID
    my_sid = MultiplayerClient.instance_variable_get(:@session_id) rescue nil
    return false if sid == my_sid

    @pm_tabs[sid] = name
    true
  end

  def self.close_pm_tab(sid)
    @pm_tabs.delete(sid)
    ChatMessages.clear_pm_messages(sid)
  end

  def self.has_pm_tab?(sid)
    @pm_tabs.key?(sid)
  end

  def self.pm_tab_name(sid)
    name = @pm_tabs[sid]
    "#{sid}/#{name}"
  end

  def self.in_squad?
    defined?(MultiplayerClient) && MultiplayerClient.in_squad?
  end

  def self.reset
    @pm_tabs = {}
  end
end

# === ChatBlockList: Block list management ===
module ChatBlockList
  @block_list = []
  @block_all = false

  def self.blocked?(sid)
    @block_all || @block_list.include?(sid)
  end

  def self.add(sid)
    return false if @block_list.include?(sid)
    @block_list << sid
    true
  end

  def self.remove(sid)
    @block_list.delete(sid)
  end

  def self.block_all
    @block_all = true
  end

  def self.unblock_all
    @block_all = false
    @block_list.clear
  end

  def self.already_blocked?(sid)
    @block_list.include?(sid)
  end

  def self.reset
    @block_list = []
    @block_all = false
  end
end

# === ChatCommands: Command parsing ===
module ChatCommands
  def self.parse(text)
    return nil unless text.start_with?("/")

    case text
    when /^\/w\s+"?([^"\s]+)"?\s+(.+)$/
      { type: :whisper, sid: $1, message: $2 }
    when /^\/c\s+"?([^"\s]+)"?$/
      { type: :close_pm, sid: $1 }
    when /^\/b\s+"?([^"\s]+)"?$/
      { type: :block, sid: $1 }
    when /^\/u\s+"?([^"\s]+)"?$/
      { type: :unblock, sid: $1 }
    when /^\/ball$/
      { type: :block_all }
    when /^\/uall$/
      { type: :unblock_all }
    when /^\/turnoff\s+platinum$/i
      { type: :turnoff_platinum }
    when /^\/turnon\s+platinum$/i
      { type: :turnon_platinum }
    when /^\/turnoff\s+autobattle$/i
      { type: :turnoff_autobattle }
    when /^\/turnon\s+autobattle$/i
      { type: :turnon_autobattle }
    else
      nil  # Invalid command
    end
  end

  def self.sanitize(text)
    text.to_s.gsub(/[\r\n\x00|]/, "").strip[0..149]
  end
end

# === ChatNetwork: Send/receive network messages ===
module ChatNetwork
  def self.send_message(text)
    return unless defined?(MultiplayerClient)

    tab = ChatTabs.current_tab_name
    clean = ChatCommands.sanitize(text)
    return if clean.empty?

    if tab == "Global"
      MultiplayerClient.send_data("CHAT_GLOBAL:#{clean}")
    elsif tab == "Trade"
      MultiplayerClient.send_data("CHAT_TRADE:#{clean}")
    elsif tab == "Squad"
      MultiplayerClient.send_data("CHAT_SQUAD:#{clean}")
    elsif tab.start_with?("SID")
      sid = tab.split("/")[0]

      # Add the sent message to our own PM tab immediately (echo it locally)
      my_sid = MultiplayerClient.instance_variable_get(:@session_id) rescue "Unknown"
      my_name = MultiplayerClient.instance_variable_get(:@player_name) rescue "You"
      ChatMessages.add_message(sid, my_sid, my_name, clean)

      MultiplayerClient.send_data("CHAT_PM:#{sid}:#{clean}")
    end
  end

  def self.send_command(cmd)
    return unless defined?(MultiplayerClient)

    case cmd[:type]
    when :whisper
      # Open PM tab if it doesn't exist
      unless ChatTabs.has_pm_tab?(cmd[:sid])
        # Get the player name from the server's player list if possible
        player_name = get_player_name(cmd[:sid]) || cmd[:sid]
        ChatTabs.open_pm_tab(cmd[:sid], player_name)
      end

      # Add the sent message to our own PM tab immediately (echo it locally)
      clean = ChatCommands.sanitize(cmd[:message])
      my_sid = MultiplayerClient.instance_variable_get(:@session_id) rescue "Unknown"
      my_name = MultiplayerClient.instance_variable_get(:@player_name) rescue "You"
      ChatMessages.add_message(cmd[:sid], my_sid, my_name, clean)

      MultiplayerClient.send_data("CHAT_PM:#{cmd[:sid]}:#{clean}")
    when :close_pm
      ChatTabs.close_pm_tab(cmd[:sid])
    when :block
      if ChatBlockList.already_blocked?(cmd[:sid])
        # Already blocked - add message to Global chat
        ChatMessages.add_message("Global", "SYSTEM", "System", "You already blocked #{cmd[:sid]}")
      else
        ChatBlockList.add(cmd[:sid])
        ChatTabs.close_pm_tab(cmd[:sid])
        MultiplayerClient.send_data("CHAT_BLOCK:#{cmd[:sid]}")
        # Confirmation message
        ChatMessages.add_message("Global", "SYSTEM", "System", "Blocked #{cmd[:sid]}")
      end
    when :unblock
      ChatBlockList.remove(cmd[:sid])
      MultiplayerClient.send_data("CHAT_UNBLOCK:#{cmd[:sid]}")
      ChatMessages.add_message("Global", "SYSTEM", "System", "Unblocked #{cmd[:sid]}")
    when :block_all
      ChatBlockList.block_all
      MultiplayerClient.send_data("CHAT_BLOCK_ALL")
      ChatMessages.add_message("Global", "SYSTEM", "System", "Blocked all incoming PMs")
    when :unblock_all
      ChatBlockList.unblock_all
      MultiplayerClient.send_data("CHAT_UNBLOCK_ALL")
      ChatMessages.add_message("Global", "SYSTEM", "System", "Unblocked all PMs")
    when :turnoff_platinum
      MultiplayerClient.instance_variable_set(:@platinum_toast_enabled, false)
      ChatMessages.add_message("Global", "SYSTEM", "System", "Platinum toast notifications disabled")
    when :turnon_platinum
      MultiplayerClient.instance_variable_set(:@platinum_toast_enabled, true)
      ChatMessages.add_message("Global", "SYSTEM", "System", "Platinum toast notifications enabled")
    when :turnoff_autobattle
      if defined?($PokemonSystem) && $PokemonSystem
        $PokemonSystem.autobattler = 0
        ChatMessages.add_message("Global", "SYSTEM", "System", "Autobattle disabled")
      end
    when :turnon_autobattle
      if defined?($PokemonSystem) && $PokemonSystem
        $PokemonSystem.autobattler = 1
        ChatMessages.add_message("Global", "SYSTEM", "System", "Autobattle enabled")
      end
    end
  end

  def self.get_player_name(sid)
    # Try to get player name from MultiplayerClient's player list
    return nil unless defined?(MultiplayerClient)

    # Check if there's a method to get player info
    if MultiplayerClient.respond_to?(:get_player_by_sid)
      player = MultiplayerClient.get_player_by_sid(sid)
      return player[:name] if player && player[:name]
    end

    # Fallback: just use SID
    nil
  end

  # Handlers for incoming messages (called from 002_Client.rb listener)
  def self.handle_global(sid, name, text)
    is_owner = check_if_owner(sid)
    ChatMessages.add_message("Global", sid, name, text, is_owner: is_owner)
  end

  def self.handle_trade(sid, name, text)
    is_owner = check_if_owner(sid)
    ChatMessages.add_message("Trade", sid, name, text, is_owner: is_owner)
  end

  def self.handle_squad(sid, name, text)
    ChatMessages.add_message("Squad", sid, name, text)
  end

  def self.handle_pm(sid, name, text)
    return if ChatBlockList.blocked?(sid)

    unless ChatTabs.has_pm_tab?(sid)
      success = ChatTabs.open_pm_tab(sid, name)
      return unless success
    end

    ChatMessages.add_message(sid, sid, name, text)
  end

  def self.handle_pm_error(error_msg)
    # Add error message to the PM tab instead of popup (safe from network thread)
    ChatMessages.add_message("Global", "SYSTEM", "System", "PM Error: #{error_msg}")
  end

  def self.handle_blocked(sid)
    # Silently close the PM tab when blocked (safe from network thread)
    ChatTabs.close_pm_tab(sid)
    # Add notification to Global chat
    ChatMessages.add_message("Global", "SYSTEM", "System", "Player #{sid} has blocked you.")
  end

  def self.check_if_owner(sid)
    # Server owner detection (compare IPs)
    # TODO: Implement IP comparison with server IP
    false
  end
end
