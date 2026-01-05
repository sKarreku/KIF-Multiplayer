# ===========================================
# Chat System - UI Rendering
# All rendering: background, tabs, messages
# ===========================================

class ChatWindow
  def initialize
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99999  # Always on top

    # Halved size: 190x140 (from 380x280)
    @width = 250
    @height = 160

    # Position: bottom-left, above Coop HUD (which is at bottom)
    @base_x = 10
    @base_y = Graphics.height - @height - 60  # 60px from bottom for Coop HUD

    # Background sprite
    @bg_sprite = Sprite.new(@viewport)
    @bg_sprite.bitmap = Bitmap.new(@width, @height)
    @bg_sprite.bitmap.fill_rect(0, 0, @width, @height, Color.new(40, 40, 40, 230))  # Dark semi-transparent
    @bg_sprite.x = @base_x
    @bg_sprite.y = @base_y

    # Tab bar sprite
    @tabs_sprite = Sprite.new(@viewport)
    @tabs_sprite.bitmap = Bitmap.new(@width, 20)
    @tabs_sprite.x = @base_x
    @tabs_sprite.y = @base_y

    # Message area sprite
    @messages_sprite = Sprite.new(@viewport)
    @messages_sprite.bitmap = Bitmap.new(@width - 10, @height - 40)
    @messages_sprite.x = @base_x + 5
    @messages_sprite.y = @base_y + 22

    # Input line sprite (at bottom)
    @input_sprite = Sprite.new(@viewport)
    @input_sprite.bitmap = Bitmap.new(@width - 10, 18)
    @input_sprite.x = @base_x + 5
    @input_sprite.y = @base_y + @height - 20

    @last_update = Time.now.to_f
    @input_text = ""
    @input_mode = false
    @scroll_offset = 0  # For viewing older messages

    # Hide by default (ChatState.visible is false by default)
    @bg_sprite.visible = false
    @tabs_sprite.visible = false
    @messages_sprite.visible = false
    @input_sprite.visible = false
  end

  def update
    return unless defined?(ChatState)

    # Control visibility
    visible = ChatState.visible
    @bg_sprite.visible = visible
    @tabs_sprite.visible = visible
    @messages_sprite.visible = visible
    @input_sprite.visible = visible

    return unless visible

    # Adjust opacity based on input mode
    target_opacity = @input_mode ? 230 : 130
    @bg_sprite.opacity = target_opacity
    @tabs_sprite.opacity = target_opacity
    @messages_sprite.opacity = target_opacity
    @input_sprite.opacity = target_opacity

    # Throttle updates to 100ms
    now = Time.now.to_f
    return if now - @last_update < 0.1

    draw_tabs
    draw_messages
    draw_input
    @last_update = now
  end

  def draw_tabs
    return unless defined?(ChatTabs)

    @tabs_sprite.bitmap.clear

    tabs = ChatTabs.tab_list
    active_idx = ChatState.active_tab_index

    tabs.each_with_index do |tab_name, i|
      tab_width = 60
      x_pos = i * (tab_width + 2)
      is_active = (i == active_idx)

      # Background color (Windows XP style)
      if is_active
        @tabs_sprite.bitmap.fill_rect(x_pos, 0, tab_width, 20, Color.new(200, 230, 255))  # Light blue
      else
        @tabs_sprite.bitmap.fill_rect(x_pos, 0, tab_width, 20, Color.new(180, 180, 180))  # Gray
      end

      # Border
      @tabs_sprite.bitmap.fill_rect(x_pos + tab_width, 0, 2, 20, Color.new(100, 100, 100))  # Separator

      # Text
      @tabs_sprite.bitmap.font.color = is_active ? Color.new(0, 0, 0) : Color.new(80, 80, 80)
      @tabs_sprite.bitmap.font.size = 14
      @tabs_sprite.bitmap.font.bold = is_active

      # Truncate tab name if too long
      display_name = tab_name.length > 8 ? tab_name[0..7] : tab_name
      @tabs_sprite.bitmap.draw_text(x_pos, 2, tab_width, 18, display_name, 1)  # Center align
    end
  end

  def draw_messages
    return unless defined?(ChatTabs) && defined?(ChatMessages)

    @messages_sprite.bitmap.clear

    tab = ChatTabs.current_tab_name
    messages = ChatMessages.get_messages(tab)

    # Take last 50 messages max
    messages = messages.last(50)

    line_height = 14
    max_y = @height - 60  # Leave room at bottom
    max_width = @width - 16

    # Convert all messages to wrapped lines first
    all_lines = []
    messages.each do |msg|
      header = "#{msg[:sid]}/#{msg[:name]} : "
      text = msg[:text]
      wrapped = wrap_text(header + text, max_width)

      wrapped.each do |line|
        all_lines << { line: line, is_owner: msg[:is_owner] }
      end
    end

    # Calculate which lines to show based on scroll
    total_lines = all_lines.length
    visible_lines = (max_y / line_height).to_i

    # Show the most recent lines, minus the scroll offset
    start_index = [total_lines - visible_lines - @scroll_offset, 0].max
    end_index = [start_index + visible_lines, total_lines].min

    y_offset = 0
    all_lines[start_index...end_index].each do |line_data|
      break if y_offset >= max_y

      # Server owner gets different color (gold)
      color = line_data[:is_owner] ? Color.new(255, 200, 0) : Color.new(220, 220, 220)
      @messages_sprite.bitmap.font.color = color
      @messages_sprite.bitmap.font.size = 11
      @messages_sprite.bitmap.font.bold = false

      @messages_sprite.bitmap.draw_text(2, y_offset, max_width, line_height, line_data[:line], 0)
      y_offset += line_height
    end

    # Draw scroll indicator if scrolled
    if @scroll_offset > 0
      @messages_sprite.bitmap.font.color = Color.new(255, 255, 0)
      @messages_sprite.bitmap.font.size = 10
      @messages_sprite.bitmap.draw_text(2, @height - 60, @width - 14, 12, "↑ #{@scroll_offset}", 0)
    end
  end

  def wrap_text(text, max_width)
    return [text] if text.length == 0

    lines = []
    current_line = ""

    text.split(" ").each do |word|
      test_line = current_line.empty? ? word : "#{current_line} #{word}"

      # Estimate width (rough approximation: 6 pixels per char at size 11)
      if test_line.length * 6 > max_width
        lines << current_line unless current_line.empty?
        current_line = word
      else
        current_line = test_line
      end
    end

    lines << current_line unless current_line.empty?
    lines
  end

  def draw_input
    @input_sprite.bitmap.clear

    # Background
    @input_sprite.bitmap.fill_rect(0, 0, @width - 10, 18, Color.new(60, 60, 60, 200))

    return unless @input_mode  # Only draw text/cursor when in input mode

    # Calculate scroll offset for long text
    @input_sprite.bitmap.font.size = 12
    max_width = @width - 18
    char_width = 7  # Approximate width per char
    visible_chars = (max_width / char_width).to_i

    display_text = @input_text
    scroll_offset = 0

    if @input_text.length > visible_chars
      scroll_offset = @input_text.length - visible_chars
      display_text = @input_text[scroll_offset..-1]
    end

    # Input text
    @input_sprite.bitmap.font.color = Color.new(255, 255, 255)
    @input_sprite.bitmap.font.bold = false
    @input_sprite.bitmap.draw_text(4, 2, max_width, 14, display_text, 0)

    # Blinking cursor - calculate actual text width
    if (Time.now.to_f * 2).to_i % 2 == 0
      text_width = @input_sprite.bitmap.text_size(display_text).width
      cursor_x = 4 + text_width
      @input_sprite.bitmap.fill_rect(cursor_x, 3, 2, 12, Color.new(255, 255, 255))
    end
  end

  def set_input_text(text)
    @input_text = text
  end

  def get_input_text
    @input_text
  end

  def clear_input
    @input_text = ""
  end

  def input_mode
    @input_mode
  end

  def input_mode=(val)
    @input_mode = val
  end

  def scroll_up
    # Scroll up by 3 lines at a time
    @scroll_offset += 3

    # Calculate max scroll based on total wrapped lines
    tab = ChatTabs.current_tab_name
    messages = ChatMessages.get_messages(tab)
    messages = messages.last(50)

    max_width = @width - 16
    total_lines = 0
    messages.each do |msg|
      header = "#{msg[:sid]}/#{msg[:name]} : "
      text = msg[:text]
      wrapped = wrap_text(header + text, max_width)
      total_lines += wrapped.length
    end

    line_height = 14
    max_y = @height - 60
    visible_lines = (max_y / line_height).to_i
    max_scroll = [total_lines - visible_lines, 0].max

    @scroll_offset = [@scroll_offset, max_scroll].min
  end

  def scroll_down
    # Scroll down by 3 lines at a time
    @scroll_offset = [@scroll_offset - 3, 0].max
  end

  def reset_scroll
    @scroll_offset = 0
  end

  def dispose
    @bg_sprite.dispose if @bg_sprite
    @tabs_sprite.dispose if @tabs_sprite
    @messages_sprite.dispose if @messages_sprite
    @input_sprite.dispose if @input_sprite
    @viewport.dispose if @viewport

    @bg_sprite = nil
    @tabs_sprite = nil
    @messages_sprite = nil
    @input_sprite = nil
    @viewport = nil
  end
end

# Hook into Scene_Map update
class Scene_Map
  unless defined?(chat_scene_update_original)
    alias chat_scene_update_original update
  end

  def update
    chat_scene_update_original
    $chat_window.update if $chat_window
  end
end

# Initialize/cleanup on connect/disconnect
module MultiplayerClient
  class << self
    unless defined?(chat_connect_hook_original)
      alias chat_connect_hook_original connect
    end

    def connect(server_ip)
      result = chat_connect_hook_original(server_ip)
      if @connected
        begin
          $chat_window = ChatWindow.new
          $chat_initialized = true
          ##MultiplayerDebug.info("CHAT-UI", "Chat window initialized")
        rescue => e
          ##MultiplayerDebug.error("CHAT-UI", "Failed to initialize chat: #{e.message}")
        end
      end
      result
    end

    unless defined?(chat_disconnect_hook_original)
      alias chat_disconnect_hook_original disconnect
    end

    def disconnect
      chat_disconnect_hook_original
      if $chat_window
        begin
          $chat_window.dispose
          $chat_window = nil
          $chat_initialized = false
          ChatState.reset if defined?(ChatState)
          ChatTabs.reset if defined?(ChatTabs)
          ChatMessages.reset if defined?(ChatMessages)
          ChatBlockList.reset if defined?(ChatBlockList)
          ##MultiplayerDebug.info("CHAT-UI", "Chat window disposed")
        rescue => e
          ##MultiplayerDebug.error("CHAT-UI", "Failed to dispose chat: #{e.message}")
        end
      end
    end
  end
end

##MultiplayerDebug.info("CHAT-UI", "Chat UI module loaded")
