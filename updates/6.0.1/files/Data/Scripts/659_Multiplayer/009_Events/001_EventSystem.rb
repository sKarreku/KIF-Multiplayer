#===============================================================================
# MODULE: Event System - Core
#===============================================================================
# Central event state management, timer tracking, and network handlers.
# Provides hooks for other modules to query active events and modifiers.
#
# Usage:
#   EventSystem.has_active_event?(:shiny)        -> Boolean
#   EventSystem.get_modifier_multiplier(:shiny_multiplier) -> Integer
#   EventSystem.has_challenge_modifier?(:no_switching) -> Boolean
#   EventSystem.time_remaining("EVT_SHINY_1")    -> Integer (seconds)
#   EventSystem.active_events                    -> Hash (copy)
#===============================================================================

module EventSystem
  TAG = "EVENT-SYSTEM"

  # Event state cache
  @active_events = {}  # { event_id => event_data }
  @event_mutex = Mutex.new
  @last_sync = 0

  # Notification queue (for UI thread)
  @notification_queue = []
  @notification_mutex = Mutex.new

  # TV info cache (for :television notifications)
  @tv_info = nil
  @tv_revealed_at = nil

  module_function

  #---------------------------------------------------------------------------
  # Event State Accessors
  #---------------------------------------------------------------------------

  # Get a copy of all active events
  def active_events
    @event_mutex.synchronize { @active_events.dup }
  end

  # Get events of a specific type
  def events_of_type(type)
    type_str = type.to_s
    @event_mutex.synchronize do
      @active_events.values.select { |ev| ev[:type].to_s == type_str }
    end
  end

  # Check if any event of given type is active
  def has_active_event?(type)
    type_str = type.to_s
    @event_mutex.synchronize do
      @active_events.values.any? { |ev| ev[:type].to_s == type_str }
    end
  end

  # Get a multiplier value from active events' effects
  # Returns 1 if no matching effect found
  def get_modifier_multiplier(modifier_type, event_type = nil)
    modifier_str = modifier_type.to_s
    event_type_str = event_type ? event_type.to_s : nil

    @event_mutex.synchronize do
      @active_events.values.each do |ev|
        # Skip if event_type specified and doesn't match
        next if event_type_str && ev[:type].to_s != event_type_str

        # Search effects array
        (ev[:effects] || []).each do |effect|
          effect_type = effect[:type] || effect["type"]
          if effect_type.to_s == modifier_str
            return effect[:value] || effect["value"] || 1
          end
        end
      end

      1  # Default: no multiplier
    end
  end

  # Check if a specific challenge modifier is active
  def has_challenge_modifier?(modifier)
    modifier_str = modifier.to_s
    @event_mutex.synchronize do
      @active_events.values.any? do |ev|
        mods = ev[:challenge_modifiers] || []
        mods.any? { |m| m.to_s == modifier_str }
      end
    end
  end

  # Check if a specific reward modifier is active
  def has_reward_modifier?(modifier)
    modifier_str = modifier.to_s
    @event_mutex.synchronize do
      @active_events.values.any? do |ev|
        mods = ev[:reward_modifiers] || []
        mods.any? { |m| m.to_s == modifier_str }
      end
    end
  end

  # Get all active challenge modifiers
  def active_challenge_modifiers
    @event_mutex.synchronize do
      mods = []
      @active_events.values.each do |ev|
        mods.concat(ev[:challenge_modifiers] || [])
      end
      mods.uniq
    end
  end

  # Get all active reward modifiers
  def active_reward_modifiers
    @event_mutex.synchronize do
      mods = []
      @active_events.values.each do |ev|
        mods.concat(ev[:reward_modifiers] || [])
      end
      mods.uniq
    end
  end

  # Get time remaining for a specific event (in seconds)
  def time_remaining(event_id)
    @event_mutex.synchronize do
      ev = @active_events[event_id]
      return 0 unless ev
      remaining = ev[:end_time].to_i - Time.now.to_i
      [remaining, 0].max
    end
  end

  # Get the primary (first) active event, if any
  def primary_event
    @event_mutex.synchronize do
      @active_events.values.first
    end
  end

  #---------------------------------------------------------------------------
  # Network Handlers (called from 002_Client.rb)
  #---------------------------------------------------------------------------

  # Handle EVENT_STATE message from server
  def handle_event_state(json_str)
    begin
      return unless defined?(MiniJSON)

      events = MiniJSON.parse(json_str)
      return unless events.is_a?(Array)

      @event_mutex.synchronize do
        @active_events.clear

        events.each do |ev|
          next unless ev.is_a?(Hash)

          event_data = {
            id: ev["id"],
            type: ev["type"].to_s,
            map: ev["map"],
            start_time: ev["start_time"].to_i,
            end_time: ev["end_time"].to_i,
            description: ev["description"].to_s,
            effects: ev["effects"] || [],
            challenge_modifiers: (ev["challenge_modifiers"] || []).map(&:to_s),
            reward_modifiers: (ev["reward_modifiers"] || []).map(&:to_s)
          }

          @active_events[event_data[:id]] = event_data
        end

        @last_sync = Time.now.to_i
      end

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info(TAG, "Synced #{events.length} active events")
      end
    rescue => e
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error(TAG, "Failed to parse event state: #{e.class}: #{e.message}")
      end
    end
  end

  # Handle EVENT_NOTIFY message from server
  def handle_event_notify(type, message)
    @notification_mutex.synchronize do
      @notification_queue << {
        type: type.to_s.downcase.to_sym,
        message: message.to_s,
        timestamp: Time.now
      }
    end

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info(TAG, "Received #{type} notification: #{message[0..50]}...")
    end
  end

  # Handle EVENT_END message from server
  def handle_event_end(event_id, event_type)
    @event_mutex.synchronize do
      @active_events.delete(event_id)
    end

    # Clear reward tracking for this event
    if defined?(EventRewards)
      EventRewards.clear_event(event_id)
      EventRewards.clear_all_used_rewards
    end

    @notification_mutex.synchronize do
      @notification_queue << {
        type: :event_end,
        message: "The #{event_type} event has ended.",
        event_id: event_id,
        event_type: event_type,
        timestamp: Time.now
      }
    end

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info(TAG, "Event ended: #{event_id} (#{event_type})")
    end
  end

  # Handle EVENT_TV_AVAILABLE message from server
  def handle_tv_available(preview)
    @tv_info = preview
    @tv_revealed_at = Time.now

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info(TAG, "TV info available: #{preview}")
    end
  end

  #---------------------------------------------------------------------------
  # Notification Queue (for UI consumption)
  #---------------------------------------------------------------------------

  # Pop the next notification from the queue
  def dequeue_notification
    @notification_mutex.synchronize { @notification_queue.shift }
  end

  # Check if notifications are pending
  def notification_pending?
    @notification_mutex.synchronize { !@notification_queue.empty? }
  end

  # Get all pending notifications (without removing)
  def peek_notifications
    @notification_mutex.synchronize { @notification_queue.dup }
  end

  # Clear all notifications
  def clear_notifications
    @notification_mutex.synchronize { @notification_queue.clear }
  end

  #---------------------------------------------------------------------------
  # TV System
  #---------------------------------------------------------------------------

  def tv_info_available?
    !@tv_info.nil?
  end

  def get_tv_info
    @tv_info
  end

  def clear_tv_info
    @tv_info = nil
    @tv_revealed_at = nil
  end

  #---------------------------------------------------------------------------
  # Request Events from Server
  #---------------------------------------------------------------------------

  def request_sync
    return unless defined?(MultiplayerClient)
    return unless MultiplayerClient.instance_variable_get(:@connected)

    MultiplayerClient.send_data("REQ_EVENTS") rescue nil

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info(TAG, "Requested event sync from server")
    end
  end

  #---------------------------------------------------------------------------
  # Admin Commands (for debug console)
  #---------------------------------------------------------------------------

  def admin_create_event(event_type)
    return unless defined?(MultiplayerClient)
    return unless MultiplayerClient.instance_variable_get(:@connected)

    MultiplayerClient.send_data("ADMIN_EVENT_CREATE:#{event_type}") rescue nil

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info(TAG, "Requested creation of #{event_type} event")
    end
  end

  def admin_end_event(event_id)
    return unless defined?(MultiplayerClient)
    return unless MultiplayerClient.instance_variable_get(:@connected)

    MultiplayerClient.send_data("ADMIN_EVENT_END:#{event_id}") rescue nil

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info(TAG, "Requested end of event #{event_id}")
    end
  end

  #---------------------------------------------------------------------------
  # Debug/Test Methods
  #---------------------------------------------------------------------------

  def debug_status
    puts "=" * 60
    puts "EventSystem Status"
    puts "=" * 60

    events = active_events
    if events.empty?
      puts "No active events"
    else
      events.each do |id, ev|
        remaining = time_remaining(id)
        puts "Event: #{id}"
        puts "  Type: #{ev[:type]}"
        puts "  Description: #{ev[:description]}"
        puts "  Time remaining: #{remaining}s"
        puts "  Challenge modifiers: #{ev[:challenge_modifiers].join(', ')}"
        puts "  Reward modifiers: #{ev[:reward_modifiers].join(', ')}"
        puts ""
      end
    end

    puts "Pending notifications: #{peek_notifications.length}"
    puts "TV info available: #{tv_info_available?}"
    puts "=" * 60
  end
end

#===============================================================================
# Module loaded
#===============================================================================
if defined?(MultiplayerDebug)
  MultiplayerDebug.info("EVENT-SYSTEM", "=" * 60)
  MultiplayerDebug.info("EVENT-SYSTEM", "150_Event_System.rb loaded")
  MultiplayerDebug.info("EVENT-SYSTEM", "Event system core module ready")
  MultiplayerDebug.info("EVENT-SYSTEM", "  EventSystem.has_active_event?(type)")
  MultiplayerDebug.info("EVENT-SYSTEM", "  EventSystem.get_modifier_multiplier(type)")
  MultiplayerDebug.info("EVENT-SYSTEM", "  EventSystem.has_challenge_modifier?(mod)")
  MultiplayerDebug.info("EVENT-SYSTEM", "  EventSystem.request_sync")
  MultiplayerDebug.info("EVENT-SYSTEM", "  EventSystem.debug_status")
  MultiplayerDebug.info("EVENT-SYSTEM", "=" * 60)
end
