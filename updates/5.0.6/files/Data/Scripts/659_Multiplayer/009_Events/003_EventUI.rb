#===============================================================================
# MODULE: Event System - UI Components
#===============================================================================
# Persistent HUD panel showing active events near route name.
# Notification popup handling for global/local/television types.
#===============================================================================

#===============================================================================
# Event HUD Panel - Shows active event with countdown timer and modifiers
#===============================================================================
# Modifier Status Colors:
#   White  - Investigated (discovered/revealed to player)
#   Green  - Active (currently in effect)
#   Red    - Inactive (expired/used up)
#===============================================================================
class EventHUD
  # Modifier status colors
  COLOR_INVESTIGATED = Color.new(255, 255, 255)  # White
  COLOR_ACTIVE = Color.new(100, 255, 100)        # Green
  COLOR_INACTIVE = Color.new(255, 100, 100)      # Red
  COLOR_UNKNOWN = Color.new(150, 150, 150)       # Gray (not yet investigated)

  def initialize
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99990  # Below chat (99999) but above most UI

    # Panel dimensions (increased height for modifier display + eligibility)
    @width = 220
    @height = 138  # Increased to accommodate modifiers + eligibility line
    @base_x = Graphics.width - @width - 10
    @base_y = 10  # Top-right, near route name area

    # Background sprite
    @bg_sprite = Sprite.new(@viewport)
    @bg_sprite.bitmap = Bitmap.new(@width, @height)
    @bg_sprite.x = @base_x
    @bg_sprite.y = @base_y
    @bg_sprite.visible = false
    @bg_sprite.opacity = 200

    # Text sprite (overlaid on background)
    @text_sprite = Sprite.new(@viewport)
    @text_sprite.bitmap = Bitmap.new(@width - 10, @height - 10)
    @text_sprite.x = @base_x + 5
    @text_sprite.y = @base_y + 5
    @text_sprite.visible = false

    # Animation state
    @pulse_frame = 0
    @last_update = 0
    @last_event_id = nil

    # Cache last drawn state to avoid redrawing every frame
    @cached_time_str = nil
    @cached_modifiers = nil

    # Modifier investigation state (tied to notification discovery)
    # { modifier_id => :investigated/:active/:inactive }
    @modifier_states = {}
  end

  def update
    return unless defined?(EventSystem)

    events = EventSystem.active_events

    if events.empty?
      hide
      return
    end

    show

    # Throttle updates to every 500ms
    now = Time.now.to_f
    return if now - @last_update < 0.5
    @last_update = now

    # Get primary event
    event = events.values.first
    return unless event

    # Check if event changed - reset modifier states for new event
    if @last_event_id != event[:id]
      @last_event_id = event[:id]
      @cached_time_str = nil  # Force redraw
      @modifier_states.clear  # Reset modifier states for new event
    end

    draw_panel(event)
    animate_pulse
  end

  def draw_panel(event)
    return unless event

    # Calculate time remaining
    time_left = EventSystem.time_remaining(event[:id])
    time_str = format_time(time_left)

    # Check if modifiers changed (include map state and buff states in cache key)
    map_state = player_on_event_map?(event) ? "on" : "off"
    buff_state = get_passive_buff_cache_key
    current_mods = "#{(event[:reward_modifiers] || []).join(',')}_#{(event[:challenge_modifiers] || []).join(',')}_#{map_state}_#{buff_state}"

    # Skip redraw if nothing changed
    return if time_str == @cached_time_str && current_mods == @cached_modifiers
    @cached_time_str = time_str
    @cached_modifiers = current_mods

    # Determine colors based on event type
    bg_color, border_color, text_color = get_event_colors(event[:type])

    # Draw background
    @bg_sprite.bitmap.clear
    @bg_sprite.bitmap.fill_rect(0, 0, @width, @height, bg_color)

    # Draw border (2px)
    @bg_sprite.bitmap.fill_rect(0, 0, @width, 2, border_color)
    @bg_sprite.bitmap.fill_rect(0, @height - 2, @width, 2, border_color)
    @bg_sprite.bitmap.fill_rect(0, 0, 2, @height, border_color)
    @bg_sprite.bitmap.fill_rect(@width - 2, 0, 2, @height, border_color)

    # Draw text
    @text_sprite.bitmap.clear

    # Event type header - COLOR BASED ON WHETHER ON EVENT MAP
    @text_sprite.bitmap.font.size = 16
    @text_sprite.bitmap.font.bold = true

    # Check if player is on event map
    on_event_map = player_on_event_map?(event)
    if on_event_map
      @text_sprite.bitmap.font.color = COLOR_ACTIVE  # Green - on correct map
    else
      @text_sprite.bitmap.font.color = COLOR_INACTIVE  # Red - not on correct map
    end

    type_name = event[:type].to_s.upcase
    icon = get_event_icon(event[:type])
    @text_sprite.bitmap.draw_text(0, 0, @width - 10, 20, "#{icon} #{type_name} EVENT", 1)

    # Time remaining
    @text_sprite.bitmap.font.size = 14
    @text_sprite.bitmap.font.bold = false

    # Color time based on urgency
    if time_left <= 300  # 5 min or less
      @text_sprite.bitmap.font.color = Color.new(255, 100, 100)  # Red
    elsif time_left <= 900  # 15 min or less
      @text_sprite.bitmap.font.color = Color.new(255, 200, 100)  # Orange
    else
      @text_sprite.bitmap.font.color = text_color
    end

    @text_sprite.bitmap.draw_text(0, 22, @width - 10, 18, time_str, 1)

    # Draw modifier section
    draw_modifiers(event, 42)

    # Draw eligibility status
    draw_eligibility(event, @height - 23)
  end

  # Draw eligibility status at the bottom of the panel
  def draw_eligibility(event, y_offset)
    @text_sprite.bitmap.font.size = 11
    @text_sprite.bitmap.font.bold = true

    # Check eligibility
    eligible = check_eligibility(event)

    if eligible
      @text_sprite.bitmap.font.color = Color.new(100, 255, 100)  # Green
      @text_sprite.bitmap.draw_text(0, y_offset, @width - 10, 14, "Eligible: YES", 1)
    else
      @text_sprite.bitmap.font.color = Color.new(255, 100, 100)  # Red
      @text_sprite.bitmap.draw_text(0, y_offset, @width - 10, 14, "Eligible: NO", 1)
    end
  end

  # Check if player is eligible for rewards
  def check_eligibility(event)
    return false unless event
    return false unless defined?(EventRewards)

    player_id = get_player_id
    EventRewards.eligible_for_rewards?(event[:id], player_id)
  end

  # Get current player ID
  def get_player_id
    if defined?(MultiplayerClient)
      MultiplayerClient.instance_variable_get(:@player_name) rescue "local"
    else
      "local"
    end
  end

  # Check if player is on the event map
  def player_on_event_map?(event)
    return true if event[:map] == "global" || event[:map].to_s == "0"
    return false unless defined?($game_map) && $game_map

    current_map = $game_map.map_id
    event_map = event[:map].to_i rescue 0
    return true if event_map == 0  # Global

    current_map == event_map
  end

  # List of passive reward modifiers (vs item rewards)
  PASSIVE_REWARDS = %w[blessing pity fusion squad_scaling]

  # Get a cache key representing current buff states (for cache invalidation)
  def get_passive_buff_cache_key
    return "no_rewards" unless defined?(EventRewards)

    player_id = get_player_id
    keys = []

    # Blessing: include remaining seconds (rounded to force update every second)
    buff = EventRewards.get_buff(player_id, :blessing)
    if buff && buff[:active]
      remaining = (buff[:expires_at] - Time.now).to_i
      keys << "blessing:#{remaining}"
    else
      keys << "blessing:off"
    end

    # Pity
    keys << "pity:#{EventRewards.has_buff?(player_id, :pity) ? 'on' : 'off'}"

    # Fusion
    keys << "fusion:#{EventRewards.has_buff?(player_id, :fusion_shiny) ? 'on' : 'off'}"

    # Squad scaling
    keys << "squad:#{EventRewards.get_squad_scaling_multiplier}"

    keys.join("_")
  end

  # Draw modifiers with status colors
  # Passives: Green = on map + buff active, Red = not on map or consumed
  # Items: White = investigated, Red = received
  def draw_modifiers(event, y_offset)
    @text_sprite.bitmap.font.size = 10
    @text_sprite.bitmap.font.bold = false

    y = y_offset
    on_event_map = player_on_event_map?(event)

    # Rewards section
    rewards = event[:reward_modifiers] || []
    if rewards.any?
      @text_sprite.bitmap.font.color = Color.new(180, 180, 180)
      @text_sprite.bitmap.draw_text(0, y, @width - 10, 14, "Rewards:", 0)
      y += 14

      rewards.each_with_index do |mod_id, idx|
        break if idx >= 2  # Max 2 rewards shown

        # Get modifier info
        info = get_modifier_display_info(mod_id, :reward)
        display_text = info[:short_name] || mod_id.to_s

        # Check if this is a passive reward
        is_passive = PASSIVE_REWARDS.include?(mod_id.to_s.downcase)

        if is_passive
          # Passive rewards: check map and buff state
          color, timer_text = get_passive_modifier_state(mod_id, event, on_event_map)
          @text_sprite.bitmap.font.color = color

          if timer_text
            display_text = "#{display_text} (#{timer_text})"
          end
        else
          # Item rewards: use manual state tracking
          color = get_modifier_status_color(mod_id, event)
          @text_sprite.bitmap.font.color = color
        end

        @text_sprite.bitmap.draw_text(8, y, @width - 18, 12, "- #{display_text}")
        y += 12
      end
    end

    # Challenges section
    challenges = event[:challenge_modifiers] || []
    if challenges.any?
      y += 2  # Small gap
      @text_sprite.bitmap.font.color = Color.new(180, 180, 180)
      @text_sprite.bitmap.draw_text(0, y, @width - 10, 14, "Challenges:", 0)
      y += 14

      challenges.each_with_index do |mod_id, idx|
        break if idx >= 3  # Max 3 challenges shown

        info = get_modifier_display_info(mod_id, :challenge)
        # Challenges are always active when on event map
        if on_event_map
          @text_sprite.bitmap.font.color = COLOR_ACTIVE
        else
          @text_sprite.bitmap.font.color = COLOR_INACTIVE
        end

        display_text = info[:short_name] || mod_id.to_s
        @text_sprite.bitmap.draw_text(8, y, @width - 18, 12, "- #{display_text}")
        y += 12
      end
    end
  end

  # Get passive modifier state (color and optional timer)
  # Returns [color, timer_text_or_nil]
  def get_passive_modifier_state(mod_id, event, on_event_map)
    mod_str = mod_id.to_s.downcase
    player_id = get_player_id

    # Not on event map = always red with (off) label
    unless on_event_map
      return [COLOR_INACTIVE, "off"]
    end

    # Check specific passive types
    case mod_str
    when "blessing"
      # Blessing: 30s buff, granted ONCE when on event map, no renewal after expiration
      if defined?(EventRewards)
        # Check if already has an active blessing buff
        buff = EventRewards.get_buff(player_id, :blessing)
        if buff && buff[:active]
          remaining = (buff[:expires_at] - Time.now).to_i
          if remaining > 0
            return [COLOR_ACTIVE, "#{remaining}s"]
          end
        end

        # No active buff - check if we should grant it
        # Only grants ONCE per event (tracked by reward_used?)
        unless EventRewards.reward_used?(player_id, :blessing)
          # Grant blessing now (first time on event map)
          EventRewards.apply_blessing_on_map_entry(player_id, false)

          # Re-check after granting
          buff = EventRewards.get_buff(player_id, :blessing)
          if buff && buff[:active]
            remaining = (buff[:expires_at] - Time.now).to_i
            return [COLOR_ACTIVE, "#{remaining}s"]
          end
        end
      end
      # Blessing used up or not available = show (off)
      return [COLOR_INACTIVE, "off"]

    when "pity"
      # Pity: check if buff is active (single use)
      if defined?(EventRewards) && EventRewards.has_buff?(player_id, :pity)
        return [COLOR_ACTIVE, nil]
      end
      # Check manual state for when consumed
      if @modifier_states[mod_str] == :inactive
        return [COLOR_INACTIVE, nil]
      end
      # Not yet granted - red (will be granted via /giveeventrewards)
      return [COLOR_INACTIVE, nil]

    when "fusion"
      # Fusion: check if buff is active (single use)
      if defined?(EventRewards) && EventRewards.has_buff?(player_id, :fusion_shiny)
        return [COLOR_ACTIVE, nil]
      end
      # Check manual state for when consumed
      if @modifier_states[mod_str] == :inactive
        return [COLOR_INACTIVE, nil]
      end
      # Not yet granted - red
      return [COLOR_INACTIVE, nil]

    when "squad_scaling"
      # Squad scaling: always active on event map if modifier is set
      if defined?(EventRewards)
        mult = EventRewards.get_squad_scaling_multiplier
        if mult > 1
          return [COLOR_ACTIVE, "x#{mult}"]
        end
      end
      return [COLOR_ACTIVE, "x1"]

    else
      # Unknown passive - default to map-based color
      return [COLOR_ACTIVE, nil]
    end
  end

  # Get display info for a modifier
  def get_modifier_display_info(mod_id, mod_type)
    if defined?(EventModifierRegistry)
      info = if mod_type == :reward
        EventModifierRegistry.get_shiny_reward_info(mod_id)
      else
        EventModifierRegistry.get_shiny_challenge_info(mod_id)
      end

      if info
        return {
          short_name: info[:name] || mod_id.to_s.gsub('_', ' ').capitalize,
          description: info[:description]
        }
      end
    end

    { short_name: mod_id.to_s.gsub('_', ' ').capitalize, description: nil }
  end

  # Get status color for a modifier
  # White = Investigated (discovered), Green = Active, Red = Inactive
  def get_modifier_status_color(mod_id, event)
    # Check investigation state
    state = @modifier_states[mod_id.to_s]

    case state
    when :active
      COLOR_ACTIVE
    when :inactive
      COLOR_INACTIVE
    when :investigated
      COLOR_INVESTIGATED
    else
      # Determine based on event notification type
      # Global = immediately investigated (white)
      # Local/TV = might need discovery first
      # For now, default to investigated (white) if event is active
      COLOR_INVESTIGATED
    end
  end

  # Set modifier state (call from reward system when buffs activate/expire)
  def set_modifier_state(mod_id, state)
    @modifier_states[mod_id.to_s] = state
    @cached_modifiers = nil  # Force redraw
  end

  # Mark modifier as investigated (discovered by player)
  def investigate_modifier(mod_id)
    @modifier_states[mod_id.to_s] ||= :investigated
    @cached_modifiers = nil  # Force redraw
  end

  # Mark modifier as active
  def activate_modifier(mod_id)
    @modifier_states[mod_id.to_s] = :active
    @cached_modifiers = nil  # Force redraw
  end

  # Mark modifier as inactive (used/expired)
  def deactivate_modifier(mod_id)
    @modifier_states[mod_id.to_s] = :inactive
    @cached_modifiers = nil  # Force redraw
  end

  def get_event_colors(event_type)
    case event_type.to_s
    when "shiny"
      # Gold theme
      [
        Color.new(50, 40, 10, 220),      # Dark gold background
        Color.new(255, 215, 0),          # Gold border
        Color.new(255, 230, 150)         # Light gold text
      ]
    when "family"
      # Purple theme
      [
        Color.new(40, 20, 60, 220),      # Dark purple background
        Color.new(180, 100, 255),        # Purple border
        Color.new(220, 180, 255)         # Light purple text
      ]
    when "boss"
      # Crimson theme
      [
        Color.new(50, 10, 10, 220),      # Dark red background
        Color.new(220, 50, 50),          # Red border
        Color.new(255, 180, 180)         # Light red text
      ]
    else
      # Default gray theme
      [
        Color.new(40, 40, 40, 220),      # Dark gray background
        Color.new(150, 150, 150),        # Gray border
        Color.new(220, 220, 220)         # Light gray text
      ]
    end
  end

  def get_event_icon(event_type)
    case event_type.to_s
    when "shiny"  then "*"
    when "family" then "@"
    when "boss"   then "!"
    else               "?"
    end
  end

  def animate_pulse
    @pulse_frame = (@pulse_frame + 1) % 60
    pulse = 180 + (Math.sin(@pulse_frame * Math::PI / 30) * 40).to_i
    @bg_sprite.opacity = pulse
  end

  def format_time(seconds)
    return "Ending..." if seconds <= 0

    hours = seconds / 3600
    mins = (seconds % 3600) / 60
    secs = seconds % 60

    if hours > 0
      "#{hours}h #{mins}m remaining"
    elsif mins > 0
      "#{mins}m #{secs}s remaining"
    else
      "#{secs}s remaining"
    end
  end

  def show
    @bg_sprite.visible = true
    @text_sprite.visible = true
  end

  def hide
    @bg_sprite.visible = false
    @text_sprite.visible = false
    @last_event_id = nil
    @cached_time_str = nil
  end

  def visible?
    @bg_sprite.visible
  end

  def dispose
    @bg_sprite.bitmap.dispose if @bg_sprite.bitmap
    @bg_sprite.dispose if @bg_sprite
    @text_sprite.bitmap.dispose if @text_sprite.bitmap
    @text_sprite.dispose if @text_sprite
    @viewport.dispose if @viewport
  end
end

#===============================================================================
# Event Notification Popup - Shows notifications that slide in/out
#===============================================================================
class EventNotificationPopup
  def initialize
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99998  # Just below HUD

    @width = 350
    @height = 90
    @x = (Graphics.width - @width) / 2
    @y_target = 80
    @y_current = -@height

    @sprite = Sprite.new(@viewport)
    @sprite.bitmap = Bitmap.new(@width, @height)
    @sprite.x = @x
    @sprite.y = @y_current
    @sprite.visible = false

    @active = false
    @message = ""
    @display_time = 0
    @type = :global
    @state = :idle  # :idle, :sliding_in, :showing, :sliding_out
  end

  def show(type, message, duration = 5.0)
    @type = type.to_sym rescue :global
    @message = message.to_s
    @display_time = duration
    @active = true
    @y_current = -@height
    @sprite.y = @y_current
    @sprite.visible = true
    @state = :sliding_in
    draw_notification
  end

  def update
    return unless @active

    case @state
    when :sliding_in
      @y_current += 6
      if @y_current >= @y_target
        @y_current = @y_target
        @state = :showing
      end
      @sprite.y = @y_current

    when :showing
      @display_time -= Graphics.frame_rate > 0 ? 1.0 / Graphics.frame_rate : 0.016
      if @display_time <= 0
        @state = :sliding_out
      end

    when :sliding_out
      @y_current -= 6
      @sprite.y = @y_current
      if @y_current <= -@height
        @active = false
        @sprite.visible = false
        @state = :idle
      end
    end
  end

  def draw_notification
    @sprite.bitmap.clear

    # Background color based on type
    bg_color, border_color, icon = get_notification_style(@type)

    # Background
    @sprite.bitmap.fill_rect(0, 0, @width, @height, bg_color)

    # Border
    @sprite.bitmap.fill_rect(0, 0, @width, 3, border_color)
    @sprite.bitmap.fill_rect(0, @height - 3, @width, 3, border_color)
    @sprite.bitmap.fill_rect(0, 0, 3, @height, border_color)
    @sprite.bitmap.fill_rect(@width - 3, 0, 3, @height, border_color)

    # Icon
    @sprite.bitmap.font.size = 18
    @sprite.bitmap.font.bold = true
    @sprite.bitmap.font.color = Color.new(255, 255, 255)
    @sprite.bitmap.draw_text(10, 8, 50, 24, icon)

    # Type label
    @sprite.bitmap.font.size = 12
    type_label = case @type
    when :global then "GLOBAL EVENT"
    when :local then "NEARBY EVENT"
    when :television then "TV BROADCAST"
    when :event_end then "EVENT ENDED"
    else "NOTIFICATION"
    end
    @sprite.bitmap.draw_text(50, 10, @width - 60, 16, type_label)

    # Message text (word wrap)
    @sprite.bitmap.font.size = 14
    @sprite.bitmap.font.bold = false

    lines = word_wrap(@message, @width - 70)
    lines.each_with_index do |line, i|
      break if i >= 3  # Max 3 lines
      @sprite.bitmap.draw_text(50, 30 + i * 18, @width - 60, 18, line)
    end
  end

  def get_notification_style(type)
    case type
    when :global
      [
        Color.new(30, 100, 30, 240),   # Green background
        Color.new(100, 200, 100),      # Green border
        "[!]"                          # Icon
      ]
    when :local
      [
        Color.new(100, 70, 30, 240),   # Brown background
        Color.new(200, 150, 100),      # Brown border
        "[~]"                          # Icon
      ]
    when :television
      [
        Color.new(30, 30, 100, 240),   # Blue background
        Color.new(100, 100, 200),      # Blue border
        "[TV]"                         # Icon
      ]
    when :event_end
      [
        Color.new(80, 40, 40, 240),    # Dark red background
        Color.new(200, 100, 100),      # Red border
        "[X]"                          # Icon
      ]
    else
      [
        Color.new(50, 50, 50, 240),    # Gray background
        Color.new(150, 150, 150),      # Gray border
        "[?]"                          # Icon
      ]
    end
  end

  def word_wrap(text, max_width)
    return [text] unless @sprite.bitmap

    words = text.split(" ")
    lines = []
    current_line = ""

    words.each do |word|
      test = current_line.empty? ? word : "#{current_line} #{word}"
      width = @sprite.bitmap.text_size(test).width rescue test.length * 8

      if width > max_width && !current_line.empty?
        lines << current_line
        current_line = word
      else
        current_line = test
      end
    end

    lines << current_line unless current_line.empty?
    lines
  end

  def busy?
    @active
  end

  def dispose
    @sprite.bitmap.dispose if @sprite.bitmap
    @sprite.dispose if @sprite
    @viewport.dispose if @viewport
  end
end

#===============================================================================
# Event UI Manager - Global instance management
#===============================================================================
module EventUIManager
  @hud = nil
  @notification = nil
  @initialized = false
  @last_notification_check = 0

  # Track investigation state based on notification type
  # :global = immediately investigated
  # :local = investigated if on event map or adjacent
  # :television = investigated after interacting with TV
  @pending_investigations = []

  module_function

  def initialize_ui
    return if @initialized

    @hud = EventHUD.new
    @notification = EventNotificationPopup.new
    @initialized = true

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("EVENT-UI", "Event UI initialized")
    end
  end

  def update
    initialize_ui unless @initialized

    # Update HUD
    @hud.update if @hud

    # Update notification popup
    @notification.update if @notification

    # Process notification queue (throttled)
    now = Time.now.to_f
    if now - @last_notification_check >= 0.5
      @last_notification_check = now
      process_notification_queue
    end
  end

  def process_notification_queue
    return unless defined?(EventSystem)
    return unless @notification && !@notification.busy?

    if EventSystem.notification_pending?
      notif = EventSystem.dequeue_notification
      if notif
        @notification.show(notif[:type], notif[:message])

        # Handle investigation based on notification type
        handle_investigation(notif[:type])
      end
    end
  end

  # Handle modifier investigation based on notification type
  def handle_investigation(notif_type)
    return unless @hud
    return unless defined?(EventSystem)

    event = EventSystem.primary_event
    return unless event

    case notif_type
    when :global
      # Global = immediately investigate all modifiers
      investigate_all_modifiers(event)

    when :local
      # Local = investigate if player is on/near event map
      if player_near_event_map?(event)
        investigate_all_modifiers(event)
      else
        # Queue for later investigation when player enters area
        @pending_investigations << event[:id]
      end

    when :television
      # Television = needs TV interaction (handled separately)
      # Modifiers remain unknown until TV is used
    end
  end

  # Investigate all modifiers for an event
  def investigate_all_modifiers(event)
    return unless @hud

    (event[:reward_modifiers] || []).each do |mod_id|
      @hud.investigate_modifier(mod_id)
    end

    (event[:challenge_modifiers] || []).each do |mod_id|
      @hud.investigate_modifier(mod_id)
    end
  end

  # Check if player is on or near event map
  def player_near_event_map?(event)
    return true if event[:map] == "global"
    return false unless defined?($game_map) && $game_map

    event_map = event[:map].to_i rescue 0
    return true if event_map == 0  # Global

    current_map = $game_map.map_id

    # Check if on event map or within 1 map radius
    # (This would need proper map adjacency data, for now just check exact match)
    current_map == event_map
  end

  # Call when player interacts with TV (for television notification type)
  def investigate_via_television
    return unless @hud
    return unless defined?(EventSystem)

    event = EventSystem.primary_event
    return unless event

    investigate_all_modifiers(event)

    if defined?(ChatMessages)
      ChatMessages.add_message("Global", "SYSTEM", "System", "Event details revealed via TV broadcast!")
    end
  end

  # Call when player enters event map area (for local notification type)
  def check_pending_investigations
    return if @pending_investigations.empty?
    return unless defined?(EventSystem)

    event = EventSystem.primary_event
    return unless event

    if @pending_investigations.include?(event[:id]) && player_near_event_map?(event)
      investigate_all_modifiers(event)
      @pending_investigations.delete(event[:id])
    end
  end

  #---------------------------------------------------------------------------
  # Modifier State Management (exposed for reward system)
  #---------------------------------------------------------------------------

  def set_modifier_state(mod_id, state)
    @hud.set_modifier_state(mod_id, state) if @hud
  end

  def activate_modifier(mod_id)
    @hud.activate_modifier(mod_id) if @hud
  end

  def deactivate_modifier(mod_id)
    @hud.deactivate_modifier(mod_id) if @hud
  end

  def investigate_modifier(mod_id)
    @hud.investigate_modifier(mod_id) if @hud
  end

  #---------------------------------------------------------------------------
  # Standard Methods
  #---------------------------------------------------------------------------

  def show_notification(type, message, duration = 5.0)
    initialize_ui unless @initialized
    @notification.show(type, message, duration) if @notification
  end

  def hud_visible?
    @hud && @hud.visible?
  end

  def dispose
    @hud.dispose if @hud
    @notification.dispose if @notification
    @hud = nil
    @notification = nil
    @initialized = false
    @pending_investigations.clear
  end

  def debug_status
    puts "EventUIManager:"
    puts "  Initialized: #{@initialized}"
    puts "  HUD visible: #{hud_visible?}"
    puts "  Notification busy: #{@notification&.busy?}"
    puts "  Pending investigations: #{@pending_investigations.length}"
  end
end

#===============================================================================
# Integration: Request event state on connect
#===============================================================================
# Add this call after successful connection in 002_Client.rb:
# EventSystem.request_sync if defined?(EventSystem)

#===============================================================================
# Integration: Update UI in Scene_Map
#===============================================================================
# Add this call to Scene_Map's update method:
# EventUIManager.update if defined?(EventUIManager)

#===============================================================================
# Module loaded
#===============================================================================
if defined?(MultiplayerDebug)
  MultiplayerDebug.info("EVENT-UI", "=" * 60)
  MultiplayerDebug.info("EVENT-UI", "152_Event_UI.rb loaded")
  MultiplayerDebug.info("EVENT-UI", "Event UI components ready")
  MultiplayerDebug.info("EVENT-UI", "  EventUIManager.update - call in Scene_Map")
  MultiplayerDebug.info("EVENT-UI", "  EventUIManager.show_notification(type, msg)")
  MultiplayerDebug.info("EVENT-UI", "=" * 60)
end
