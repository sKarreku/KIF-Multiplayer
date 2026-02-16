#===============================================================================
# MODULE 1: Coop Battle Debug HUD
#===============================================================================
# Visual debug overlay for monitoring coop battle synchronization in real-time
# Displays: connected players, turn info, action sync status, RNG seed, latency
# Toggle: Press F9 during battle
#===============================================================================

module CoopBattleDebugHUD
  # HUD State
  @enabled = false
  @visible = false
  @last_update = Time.now
  @update_interval = 0.1  # Update display every 100ms

  # Data to display
  @connected_players = []
  @current_turn = 0
  @action_sync_status = {}  # { sid => :pending | :received | :synced }
  @rng_seed = nil
  @last_sync_time = nil
  @network_latency = {}  # { sid => latency_ms }
  @last_message = ""
  @message_time = nil

  # Visual properties
  @hud_x = 10
  @hud_y = 10
  @hud_width = 400
  @hud_height = 300
  @background_color = Color.new(0, 0, 0, 180)  # Semi-transparent black
  @text_color = Color.new(255, 255, 255)       # White
  @good_color = Color.new(0, 255, 0)           # Green
  @bad_color = Color.new(255, 0, 0)            # Red
  @warning_color = Color.new(255, 255, 0)      # Yellow

  #-----------------------------------------------------------------------------
  # Initialize HUD for a coop battle
  #-----------------------------------------------------------------------------
  def self.initialize_hud(battle, ally_sids)
    @enabled = true
    @visible = true
    @current_turn = battle ? battle.turnCount : 0
    @connected_players = ally_sids.dup
    @action_sync_status = {}
    ally_sids.each { |sid| @action_sync_status[sid] = :pending }
    @rng_seed = nil
    @last_sync_time = Time.now
    @last_message = "Coop Battle Debug HUD Initialized"
    @message_time = Time.now

    ##MultiplayerDebug.info("HUD", "Debug HUD initialized for battle with #{ally_sids.length} allies")
  end

  #-----------------------------------------------------------------------------
  # Disable HUD (battle ended)
  #-----------------------------------------------------------------------------
  def self.disable_hud
    @enabled = false
    @visible = false
    ##MultiplayerDebug.info("HUD", "Debug HUD disabled")
  end

  #-----------------------------------------------------------------------------
  # Toggle HUD visibility (F9 key)
  #-----------------------------------------------------------------------------
  def self.toggle_visibility
    return unless @enabled
    @visible = !@visible
    status = @visible ? "shown" : "hidden"
    ##MultiplayerDebug.info("HUD", "Debug HUD #{status}")
  end

  #-----------------------------------------------------------------------------
  # Update HUD data
  #-----------------------------------------------------------------------------
  def self.update_turn(turn_num)
    @current_turn = turn_num
    ##MultiplayerDebug.info("HUD", "Turn updated: #{turn_num}")
  end

  def self.update_action_status(sid, status)
    @action_sync_status[sid] = status
    ##MultiplayerDebug.info("HUD", "Action status for SID#{sid}: #{status}")
  end

  def self.update_rng_seed(seed)
    @rng_seed = seed
    ##MultiplayerDebug.info("HUD", "RNG seed updated: #{seed}")
  end

  def self.update_latency(sid, latency_ms)
    @network_latency[sid] = latency_ms
  end

  def self.set_message(msg)
    @last_message = msg
    @message_time = Time.now
    ##MultiplayerDebug.info("HUD", "Message: #{msg}")
  end

  def self.mark_sync_complete
    @last_sync_time = Time.now
    @action_sync_status.keys.each { |sid| @action_sync_status[sid] = :synced }
  end

  def self.reset_action_status
    @action_sync_status.keys.each { |sid| @action_sync_status[sid] = :pending }
  end

  #-----------------------------------------------------------------------------
  # Render HUD (called from Graphics.update loop or battle scene)
  #-----------------------------------------------------------------------------
  def self.render(viewport = nil)
    return unless @enabled && @visible

    # Throttle updates
    now = Time.now
    return if (now - @last_update) < @update_interval
    @last_update = now

    # Create or update HUD viewport/sprites
    # Note: In RPG Maker XP, we'd typically create a Sprite with a Bitmap
    # For this implementation, we'll use the debug console output
    # In production, you'd create actual Sprite objects

    render_to_console
  end

  #-----------------------------------------------------------------------------
  # Render to console (fallback for text-based display)
  #-----------------------------------------------------------------------------
  def self.render_to_console
    lines = []
    lines << "=" * 60
    lines << "COOP BATTLE DEBUG HUD (Press F9 to toggle)"
    lines << "=" * 60
    lines << ""
    lines << "TURN: #{@current_turn}"
    lines << "RNG SEED: #{@rng_seed || 'Not set'}"
    lines << ""
    lines << "CONNECTED PLAYERS:"

    if @connected_players.empty?
      lines << "  (Solo battle - no sync required)"
    else
      @connected_players.each do |sid|
        status = @action_sync_status[sid] || :unknown
        latency = @network_latency[sid] || 0

        status_symbol = case status
          when :pending then "⏳"
          when :received then "✓"
          when :synced then "✓✓"
          else "?"
        end

        status_text = case status
          when :pending then "PENDING"
          when :received then "RECEIVED"
          when :synced then "SYNCED"
          else "UNKNOWN"
        end

        lines << "  #{status_symbol} SID#{sid}: #{status_text} (#{latency}ms)"
      end
    end

    lines << ""
    lines << "SYNC STATUS:"

    pending_count = @action_sync_status.values.count { |s| s == :pending }
    received_count = @action_sync_status.values.count { |s| s == :received }
    synced_count = @action_sync_status.values.count { |s| s == :synced }
    total_count = @action_sync_status.length

    if total_count > 0
      lines << "  Pending: #{pending_count}/#{total_count}"
      lines << "  Received: #{received_count}/#{total_count}"
      lines << "  Synced: #{synced_count}/#{total_count}"

      if synced_count == total_count && total_count > 0
        lines << "  ✓ ALL PLAYERS SYNCHRONIZED"
      elsif pending_count > 0
        lines << "  ⏳ Waiting for #{pending_count} player(s)..."
      end
    else
      lines << "  (No sync required)"
    end

    lines << ""

    if @last_sync_time
      elapsed = (Time.now - @last_sync_time).round(2)
      lines << "Last sync: #{elapsed}s ago"
    end

    if @last_message && @message_time
      msg_age = (Time.now - @message_time).round(1)
      if msg_age < 5.0  # Show messages for 5 seconds
        lines << ""
        lines << "MESSAGE: #{@last_message}"
      end
    end

    lines << "=" * 60

    # Output to debug log
    ##MultiplayerDebug.info("HUD-RENDER", lines.join("\n"))
  end

  #-----------------------------------------------------------------------------
  # Check for F9 keypress to toggle HUD
  #-----------------------------------------------------------------------------
  def self.check_toggle_input
    return unless @enabled

    # In RPG Maker XP, F9 is Input::F9
    # This is a placeholder - actual implementation depends on input system
    begin
      if Input.trigger?(Input::F9)
        toggle_visibility
      end
    rescue
      # Input system not available, ignore
    end
  end

  #-----------------------------------------------------------------------------
  # Get current HUD status as string (for in-game display)
  #-----------------------------------------------------------------------------
  def self.get_status_string
    return "" unless @enabled && @visible

    pending = @action_sync_status.values.count { |s| s == :pending }
    total = @action_sync_status.length

    if total == 0
      return "Turn #{@current_turn} | Solo"
    elsif pending == 0
      return "Turn #{@current_turn} | All Synced ✓"
    else
      return "Turn #{@current_turn} | Waiting #{pending}/#{total}"
    end
  end

  #-----------------------------------------------------------------------------
  # Export current state to hash (for logging/debugging)
  #-----------------------------------------------------------------------------
  def self.export_state
    {
      enabled: @enabled,
      visible: @visible,
      turn: @current_turn,
      rng_seed: @rng_seed,
      players: @connected_players,
      action_status: @action_sync_status,
      latency: @network_latency,
      last_sync: @last_sync_time ? (Time.now - @last_sync_time).round(2) : nil,
      message: @last_message
    }
  end

  #-----------------------------------------------------------------------------
  # Log full HUD state to debug system
  #-----------------------------------------------------------------------------
  def self.log_state
    state = export_state
    ##MultiplayerDebug.info("HUD-STATE", "Full state: #{state.inspect}")
  end

  #-----------------------------------------------------------------------------
  # Measure and update network latency (call when receiving message)
  #-----------------------------------------------------------------------------
  def self.record_latency(sid, sent_timestamp_ms)
    begin
      received_ms = (Time.now.to_f * 1000).to_i
      latency = received_ms - sent_timestamp_ms
      update_latency(sid, latency)
    rescue => e
      ##MultiplayerDebug.error("HUD-LATENCY", "Failed to calculate latency: #{e.message}")
    end
  end
end

#===============================================================================
# Integration hooks (to be called from battle system)
#===============================================================================

# Example usage in battle initialization:
# CoopBattleDebugHUD.initialize_hud(battle, ["SID1", "SID2"])

# Example usage in Graphics.update loop:
# CoopBattleDebugHUD.check_toggle_input
# CoopBattleDebugHUD.render

# Example usage when receiving action:
# CoopBattleDebugHUD.update_action_status("SID1", :received)

# Example usage when turn starts:
# CoopBattleDebugHUD.update_turn(battle.turnCount)

# Example usage when RNG seed is set:
# CoopBattleDebugHUD.update_rng_seed(12345678)

# Example usage when sync completes:
# CoopBattleDebugHUD.mark_sync_complete

# Example usage on battle end:
# CoopBattleDebugHUD.disable_hud

##MultiplayerDebug.info("MODULE-1", "CoopBattleDebugHUD loaded successfully")
