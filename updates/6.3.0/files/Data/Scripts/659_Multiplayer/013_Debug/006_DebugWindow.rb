#===============================================================================
# COOP DEBUG WINDOW - 3-Player Squad Battle Diagnostics
#===============================================================================
# Purpose: Track and display all sync messages sent, received, and expected
#          to diagnose 3-player squad battle synchronization issues
#
# Usage:
#   - Press F10 during a coop battle to toggle the debug window
#   - The window shows real-time message flow between all 3 players
#   - Color coded: GREEN = received, YELLOW = pending, RED = timeout/missing
#===============================================================================

module CoopDebugWindow
  # Configuration
  MAX_LOG_ENTRIES = 50
  WINDOW_WIDTH = 450
  WINDOW_HEIGHT = 400
  TOGGLE_KEY = Input::F10 rescue 0x79  # F10 key

  # State
  @enabled = false
  @visible = false
  @viewport = nil
  @sprites = {}
  @log_entries = []
  @expected_messages = {}  # { message_type => { sid => { expected_at: Time, received: bool } } }
  @stats = {
    sent: 0,
    received: 0,
    dropped: 0,
    timeouts: 0
  }

  # Message types we track
  MESSAGE_TYPES = [
    "COOP_BTL_START_JSON",
    "COOP_BATTLE_JOINED",
    "COOP_ACTION",
    "COOP_RNG_SEED",
    "COOP_RNG_SEED_ACK",
    "COOP_SWITCH",
    "COOP_PARTY_PUSH_HEX",
    "COOP_BATTLE_CANCEL",
    "COOP_RUN_RESULT"
  ]

  #-----------------------------------------------------------------------------
  # Enable/Disable
  #-----------------------------------------------------------------------------
  def self.enable
    @enabled = true
    @log_entries = []
    @expected_messages = {}
    @stats = { sent: 0, received: 0, dropped: 0, timeouts: 0 }
    log_internal("DEBUG", "CoopDebugWindow ENABLED")
  end

  def self.disable
    @enabled = false
    hide
    log_internal("DEBUG", "CoopDebugWindow DISABLED")
  end

  def self.enabled?
    @enabled
  end

  #-----------------------------------------------------------------------------
  # Toggle visibility (F10)
  #-----------------------------------------------------------------------------
  def self.toggle
    if @visible
      hide
    else
      show
    end
  end

  def self.check_toggle_input
    if Input.trigger?(TOGGLE_KEY)
      toggle
    end
  end

  #-----------------------------------------------------------------------------
  # Show/Hide window
  #-----------------------------------------------------------------------------
  def self.show
    return unless @enabled
    return if @visible

    @visible = true
    create_sprites
    update_display
  end

  def self.hide
    return unless @visible

    @visible = false
    dispose_sprites
  end

  #-----------------------------------------------------------------------------
  # Log a sent message
  #-----------------------------------------------------------------------------
  def self.log_sent(message_type, target_sids, payload_size = 0)
    return unless @enabled

    @stats[:sent] += 1
    targets = target_sids.is_a?(Array) ? target_sids.join(",") : target_sids.to_s
    entry = {
      time: Time.now,
      direction: :SENT,
      type: message_type,
      targets: targets,
      size: payload_size,
      color: Color.new(100, 200, 255)  # Light blue for sent
    }
    add_log_entry(entry)

    # Track expected responses
    track_expected_response(message_type, target_sids)
  end

  #-----------------------------------------------------------------------------
  # Log a received message
  #-----------------------------------------------------------------------------
  def self.log_received(message_type, from_sid, payload_size = 0)
    return unless @enabled

    @stats[:received] += 1
    entry = {
      time: Time.now,
      direction: :RECV,
      type: message_type,
      from: from_sid.to_s,
      size: payload_size,
      color: Color.new(100, 255, 100)  # Green for received
    }
    add_log_entry(entry)

    # Mark as received in expected messages
    mark_received(message_type, from_sid)
  end

  #-----------------------------------------------------------------------------
  # Log an expected message (that we're waiting for)
  #-----------------------------------------------------------------------------
  def self.log_expecting(message_type, from_sids, timeout_seconds = 30)
    return unless @enabled

    sids = from_sids.is_a?(Array) ? from_sids : [from_sids]
    entry = {
      time: Time.now,
      direction: :WAIT,
      type: message_type,
      from: sids.join(","),
      timeout: timeout_seconds,
      color: Color.new(255, 255, 100)  # Yellow for waiting
    }
    add_log_entry(entry)

    # Track in expected messages
    @expected_messages[message_type] ||= {}
    sids.each do |sid|
      @expected_messages[message_type][sid.to_s] = {
        expected_at: Time.now,
        timeout: timeout_seconds,
        received: false
      }
    end
  end

  #-----------------------------------------------------------------------------
  # Log a timeout (expected message not received)
  #-----------------------------------------------------------------------------
  def self.log_timeout(message_type, missing_sids)
    return unless @enabled

    @stats[:timeouts] += 1
    sids = missing_sids.is_a?(Array) ? missing_sids : [missing_sids]
    entry = {
      time: Time.now,
      direction: :TIMEOUT,
      type: message_type,
      from: sids.join(","),
      color: Color.new(255, 100, 100)  # Red for timeout
    }
    add_log_entry(entry)
  end

  #-----------------------------------------------------------------------------
  # Log a dropped/blocked message
  #-----------------------------------------------------------------------------
  def self.log_dropped(message_type, reason, from_sid = nil)
    return unless @enabled

    @stats[:dropped] += 1
    entry = {
      time: Time.now,
      direction: :DROP,
      type: message_type,
      from: from_sid.to_s,
      reason: reason,
      color: Color.new(255, 150, 50)  # Orange for dropped
    }
    add_log_entry(entry)
  end

  #-----------------------------------------------------------------------------
  # Log custom debug info
  #-----------------------------------------------------------------------------
  def self.log_info(tag, message)
    return unless @enabled

    entry = {
      time: Time.now,
      direction: :INFO,
      type: tag,
      message: message,
      color: Color.new(200, 200, 200)  # Gray for info
    }
    add_log_entry(entry)
  end

  #-----------------------------------------------------------------------------
  # Get current status summary
  #-----------------------------------------------------------------------------
  def self.get_status
    pending_count = 0
    @expected_messages.each do |type, sids|
      sids.each do |sid, data|
        pending_count += 1 unless data[:received]
      end
    end

    {
      sent: @stats[:sent],
      received: @stats[:received],
      dropped: @stats[:dropped],
      timeouts: @stats[:timeouts],
      pending: pending_count,
      log_count: @log_entries.length
    }
  end

  #-----------------------------------------------------------------------------
  # Get pending messages (not yet received)
  #-----------------------------------------------------------------------------
  def self.get_pending_messages
    pending = []
    @expected_messages.each do |type, sids|
      sids.each do |sid, data|
        next if data[:received]
        elapsed = Time.now - data[:expected_at]
        pending << {
          type: type,
          sid: sid,
          elapsed: elapsed.round(1),
          timeout: data[:timeout]
        }
      end
    end
    pending
  end

  #-----------------------------------------------------------------------------
  # Clear all logs and state
  #-----------------------------------------------------------------------------
  def self.clear
    @log_entries = []
    @expected_messages = {}
    @stats = { sent: 0, received: 0, dropped: 0, timeouts: 0 }
    update_display if @visible
  end

  #-----------------------------------------------------------------------------
  # Internal: Add log entry
  #-----------------------------------------------------------------------------
  def self.add_log_entry(entry)
    @log_entries.unshift(entry)  # Add to front (newest first)
    @log_entries = @log_entries.first(MAX_LOG_ENTRIES)  # Trim old entries
    update_display if @visible
  end

  def self.log_internal(tag, message)
    puts "[COOP-DEBUG] [#{tag}] #{message}"
  end

  #-----------------------------------------------------------------------------
  # Internal: Track expected response
  #-----------------------------------------------------------------------------
  def self.track_expected_response(sent_type, target_sids)
    # Map sent message to expected response
    response_map = {
      "COOP_BTL_START_JSON" => "COOP_BATTLE_JOINED",
      "COOP_RNG_SEED" => "COOP_RNG_SEED_ACK",
      "COOP_ACTION" => nil  # Actions are bidirectional, tracked separately
    }

    expected_type = response_map[sent_type]
    return unless expected_type

    sids = target_sids.is_a?(Array) ? target_sids : [target_sids]
    @expected_messages[expected_type] ||= {}
    sids.each do |sid|
      @expected_messages[expected_type][sid.to_s] = {
        expected_at: Time.now,
        timeout: 30,
        received: false
      }
    end
  end

  #-----------------------------------------------------------------------------
  # Internal: Mark message as received
  #-----------------------------------------------------------------------------
  def self.mark_received(message_type, from_sid)
    sid_str = from_sid.to_s
    if @expected_messages[message_type] && @expected_messages[message_type][sid_str]
      @expected_messages[message_type][sid_str][:received] = true
    end
  end

  #-----------------------------------------------------------------------------
  # Sprite management
  #-----------------------------------------------------------------------------
  def self.create_sprites
    dispose_sprites  # Clean up any existing sprites

    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height) rescue nil
    return unless @viewport
    @viewport.z = 99999

    # Background
    @sprites[:bg] = Sprite.new(@viewport)
    @sprites[:bg].bitmap = Bitmap.new(WINDOW_WIDTH, WINDOW_HEIGHT)
    @sprites[:bg].bitmap.fill_rect(0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, Color.new(0, 0, 0, 220))
    draw_border(@sprites[:bg].bitmap, 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, Color.new(100, 100, 100))
    @sprites[:bg].x = Graphics.width - WINDOW_WIDTH - 10
    @sprites[:bg].y = 10
    @sprites[:bg].z = 99999

    # Title
    @sprites[:title] = Sprite.new(@viewport)
    @sprites[:title].bitmap = Bitmap.new(WINDOW_WIDTH - 20, 24)
    @sprites[:title].bitmap.font.bold = true
    @sprites[:title].bitmap.font.size = 18
    @sprites[:title].bitmap.font.color = Color.new(255, 255, 255)
    @sprites[:title].bitmap.draw_text(0, 0, WINDOW_WIDTH - 20, 24, "3-Player Coop Debug (F10 toggle)", 0)
    @sprites[:title].x = @sprites[:bg].x + 10
    @sprites[:title].y = @sprites[:bg].y + 5
    @sprites[:title].z = 100000

    # Stats line
    @sprites[:stats] = Sprite.new(@viewport)
    @sprites[:stats].bitmap = Bitmap.new(WINDOW_WIDTH - 20, 20)
    @sprites[:stats].bitmap.font.size = 14
    @sprites[:stats].x = @sprites[:bg].x + 10
    @sprites[:stats].y = @sprites[:bg].y + 28
    @sprites[:stats].z = 100000

    # Pending section header
    @sprites[:pending_header] = Sprite.new(@viewport)
    @sprites[:pending_header].bitmap = Bitmap.new(WINDOW_WIDTH - 20, 18)
    @sprites[:pending_header].bitmap.font.bold = true
    @sprites[:pending_header].bitmap.font.size = 14
    @sprites[:pending_header].bitmap.font.color = Color.new(255, 255, 100)
    @sprites[:pending_header].bitmap.draw_text(0, 0, WINDOW_WIDTH - 20, 18, "PENDING MESSAGES:", 0)
    @sprites[:pending_header].x = @sprites[:bg].x + 10
    @sprites[:pending_header].y = @sprites[:bg].y + 50
    @sprites[:pending_header].z = 100000

    # Pending messages (up to 5 lines)
    5.times do |i|
      key = "pending_#{i}".to_sym
      @sprites[key] = Sprite.new(@viewport)
      @sprites[key].bitmap = Bitmap.new(WINDOW_WIDTH - 20, 16)
      @sprites[key].bitmap.font.size = 12
      @sprites[key].x = @sprites[:bg].x + 15
      @sprites[key].y = @sprites[:bg].y + 68 + (i * 16)
      @sprites[key].z = 100000
    end

    # Log section header
    @sprites[:log_header] = Sprite.new(@viewport)
    @sprites[:log_header].bitmap = Bitmap.new(WINDOW_WIDTH - 20, 18)
    @sprites[:log_header].bitmap.font.bold = true
    @sprites[:log_header].bitmap.font.size = 14
    @sprites[:log_header].bitmap.font.color = Color.new(150, 200, 255)
    @sprites[:log_header].bitmap.draw_text(0, 0, WINDOW_WIDTH - 20, 18, "MESSAGE LOG:", 0)
    @sprites[:log_header].x = @sprites[:bg].x + 10
    @sprites[:log_header].y = @sprites[:bg].y + 155
    @sprites[:log_header].z = 100000

    # Log entries (up to 12 lines)
    12.times do |i|
      key = "log_#{i}".to_sym
      @sprites[key] = Sprite.new(@viewport)
      @sprites[key].bitmap = Bitmap.new(WINDOW_WIDTH - 20, 16)
      @sprites[key].bitmap.font.size = 11
      @sprites[key].x = @sprites[:bg].x + 10
      @sprites[key].y = @sprites[:bg].y + 173 + (i * 18)
      @sprites[key].z = 100000
    end
  end

  def self.dispose_sprites
    return unless @sprites
    @sprites.each_value do |sprite|
      next unless sprite
      sprite.bitmap.dispose if sprite.bitmap && !sprite.bitmap.disposed?
      sprite.dispose unless sprite.disposed?
    end
    @sprites = {}
    @viewport.dispose if @viewport && !@viewport.disposed?
    @viewport = nil
  end

  def self.draw_border(bitmap, x, y, width, height, color)
    bitmap.fill_rect(x, y, width, 2, color)
    bitmap.fill_rect(x, y + height - 2, width, 2, color)
    bitmap.fill_rect(x, y, 2, height, color)
    bitmap.fill_rect(x + width - 2, y, 2, height, color)
  end

  #-----------------------------------------------------------------------------
  # Update display
  #-----------------------------------------------------------------------------
  def self.update_display
    return unless @visible && @sprites[:stats]

    # Update stats
    status = get_status
    @sprites[:stats].bitmap.clear
    @sprites[:stats].bitmap.font.color = Color.new(200, 200, 200)
    stats_text = "Sent:#{status[:sent]} Recv:#{status[:received]} Drop:#{status[:dropped]} Timeout:#{status[:timeouts]} Pending:#{status[:pending]}"
    @sprites[:stats].bitmap.draw_text(0, 0, WINDOW_WIDTH - 20, 20, stats_text, 0)

    # Update pending messages
    pending = get_pending_messages
    5.times do |i|
      key = "pending_#{i}".to_sym
      sprite = @sprites[key]
      next unless sprite && sprite.bitmap

      sprite.bitmap.clear
      if pending[i]
        p = pending[i]
        color = p[:elapsed] > (p[:timeout] / 2.0) ? Color.new(255, 150, 50) : Color.new(255, 255, 100)
        sprite.bitmap.font.color = color
        text = "#{p[:type]} from SID#{p[:sid]} - #{p[:elapsed]}s / #{p[:timeout]}s"
        sprite.bitmap.draw_text(0, 0, WINDOW_WIDTH - 30, 16, text, 0)
      end
    end

    # Update log entries
    12.times do |i|
      key = "log_#{i}".to_sym
      sprite = @sprites[key]
      next unless sprite && sprite.bitmap

      sprite.bitmap.clear
      entry = @log_entries[i]
      next unless entry

      sprite.bitmap.font.color = entry[:color] || Color.new(200, 200, 200)
      time_str = entry[:time].strftime("%H:%M:%S")

      text = case entry[:direction]
      when :SENT
        "#{time_str} >> SENT #{entry[:type]} to #{entry[:targets]} (#{entry[:size]}b)"
      when :RECV
        "#{time_str} << RECV #{entry[:type]} from #{entry[:from]} (#{entry[:size]}b)"
      when :WAIT
        "#{time_str} ?? WAIT #{entry[:type]} from #{entry[:from]}"
      when :TIMEOUT
        "#{time_str} !! TIMEOUT #{entry[:type]} from #{entry[:from]}"
      when :DROP
        "#{time_str} XX DROP #{entry[:type]} - #{entry[:reason]}"
      when :INFO
        "#{time_str} ## [#{entry[:type]}] #{entry[:message]}"
      else
        "#{time_str} -- #{entry[:type]}"
      end

      # Truncate if too long
      text = text[0, 60] + "..." if text.length > 63
      sprite.bitmap.draw_text(0, 0, WINDOW_WIDTH - 20, 16, text, 0)
    end
  end

  #-----------------------------------------------------------------------------
  # Update (call every frame during battle)
  #-----------------------------------------------------------------------------
  def self.update
    return unless @enabled

    check_toggle_input

    # Check for timed out messages
    check_timeouts

    # Refresh display
    update_display if @visible
  end

  def self.check_timeouts
    now = Time.now
    @expected_messages.each do |type, sids|
      sids.each do |sid, data|
        next if data[:received]
        next if data[:timeout_logged]

        elapsed = now - data[:expected_at]
        if elapsed > data[:timeout]
          log_timeout(type, [sid])
          data[:timeout_logged] = true
        end
      end
    end
  end
end

#===============================================================================
# Auto-enable during coop battles
#===============================================================================
# Hook into CoopBattleState to auto-enable/disable debug window
if defined?(CoopBattleState)
  class << CoopBattleState
    alias _debug_window_create_battle create_battle

    def create_battle(**args)
      result = _debug_window_create_battle(**args)

      # Enable debug window for any coop battle with allies
      if args[:ally_sids] && args[:ally_sids].length > 0
        CoopDebugWindow.enable
        CoopDebugWindow.log_info("BATTLE", "Started #{args[:is_initiator] ? 'as INITIATOR' : 'as NON-INITIATOR'}")
        CoopDebugWindow.log_info("BATTLE", "Allies: #{args[:ally_sids].join(', ')}")
        CoopDebugWindow.log_info("BATTLE", "Battle ID: #{result}")
      end

      result
    end

    alias _debug_window_end_battle end_battle

    def end_battle
      if CoopDebugWindow.enabled?
        status = CoopDebugWindow.get_status
        CoopDebugWindow.log_info("BATTLE", "Ended - Sent:#{status[:sent]} Recv:#{status[:received]} Drops:#{status[:dropped]} Timeouts:#{status[:timeouts]}")
      end

      _debug_window_end_battle

      # Keep enabled briefly to review final state, then disable
      # (User can still toggle with F10)
    end
  end
end

#===============================================================================
# Helper function to dump full sync state
#===============================================================================
def pbDumpCoopSyncState
  return unless defined?(CoopDebugWindow)

  puts "=" * 70
  puts "[COOP-DEBUG] FULL SYNC STATE DUMP"
  puts "=" * 70

  # Battle state
  if defined?(CoopBattleState)
    puts "CoopBattleState:"
    puts "  in_coop_battle?: #{CoopBattleState.in_coop_battle?}"
    puts "  am_i_initiator?: #{CoopBattleState.am_i_initiator?}"
    puts "  battle_id: #{CoopBattleState.battle_id}"
    puts "  ally_sids: #{CoopBattleState.get_ally_sids.inspect}"
  end

  # Transaction state
  if defined?(CoopBattleTransaction)
    puts "CoopBattleTransaction:"
    puts "  active?: #{CoopBattleTransaction.active?}"
    puts "  pending?: #{CoopBattleTransaction.pending?}"
    puts "  cancelled?: #{CoopBattleTransaction.cancelled?}"
    puts "  transaction_id: #{CoopBattleTransaction.transaction_id}"
    puts "  ready_count: #{CoopBattleTransaction.ready_count}/#{CoopBattleTransaction.expected_count}"
  end

  # Joined SIDs
  if defined?(MultiplayerClient)
    joined = MultiplayerClient.instance_variable_get(:@coop_battle_joined_sids) || []
    puts "MultiplayerClient:"
    puts "  joined_ally_sids: #{joined.inspect}"
    puts "  session_id: #{MultiplayerClient.session_id}"
  end

  # Action sync state
  if defined?(CoopActionSync)
    stats = CoopActionSync.export_sync_stats rescue {}
    puts "CoopActionSync:"
    puts "  current_turn: #{CoopActionSync.current_turn}"
    puts "  sync_complete: #{stats[:sync_complete]}"
    puts "  expected_count: #{stats[:expected_count]}"
    puts "  received_count: #{stats[:received_count]}"
    puts "  pending_sids: #{stats[:pending_sids].inspect}"
    puts "  received_sids: #{stats[:received_sids].inspect}"
  end

  # Debug window state
  status = CoopDebugWindow.get_status
  puts "CoopDebugWindow:"
  puts "  enabled?: #{CoopDebugWindow.enabled?}"
  puts "  sent: #{status[:sent]}"
  puts "  received: #{status[:received]}"
  puts "  dropped: #{status[:dropped]}"
  puts "  timeouts: #{status[:timeouts]}"
  puts "  pending: #{status[:pending]}"

  # Pending messages
  pending = CoopDebugWindow.get_pending_messages
  if pending.length > 0
    puts "  PENDING MESSAGES:"
    pending.each do |p|
      puts "    #{p[:type]} from SID#{p[:sid]} - #{p[:elapsed]}s elapsed"
    end
  end

  puts "=" * 70
end

puts "[COOP-DEBUG] CoopDebugWindow module loaded - Press F10 to toggle during coop battles"
puts "[COOP-DEBUG] Use pbDumpCoopSyncState() in console to dump full sync state"
