#===============================================================================
# COOP DEBUG HOOKS - Inject logging into send/receive paths
#===============================================================================
# Purpose: Hook into MultiplayerClient to log all coop messages
#          for the CoopDebugWindow diagnostic system
#===============================================================================

# Only load if both CoopDebugWindow and MultiplayerClient are defined
if defined?(CoopDebugWindow) && defined?(MultiplayerClient)

  module MultiplayerClient
    class << self
      # Alias the original send_data method if not already aliased
      unless method_defined?(:_debug_hook_send_data)
        alias _debug_hook_send_data send_data
      end

      # Override send_data to log coop messages
      def send_data(message, **opts)
        # Log to debug window if it's a coop message
        if CoopDebugWindow.enabled? && message.is_a?(String)
          log_outgoing_message(message)
        end

        # Call original
        _debug_hook_send_data(message, **opts)
      end

      def log_outgoing_message(message)
        # Parse message type
        coop_types = [
          "COOP_BTL_START_JSON",
          "COOP_BTL_START",
          "COOP_BATTLE_JOINED",
          "COOP_BATTLE_CANCEL",
          "COOP_BATTLE_END",
          "COOP_ACTION",
          "COOP_RNG_SEED",
          "COOP_RNG_SEED_ACK",
          "COOP_SWITCH",
          "COOP_PARTY_PUSH_HEX",
          "COOP_PARTY_PUSH_NOW",
          "COOP_PARTY_REQ",
          "COOP_PARTY_RESP",
          "COOP_RUN_RESULT",
          "COOP_MOVE_SYNC"
        ]

        coop_types.each do |type|
          if message.start_with?("#{type}:")
            payload = message.sub("#{type}:", "")
            target_sids = get_current_ally_sids
            CoopDebugWindow.log_sent(type, target_sids, payload.length)
            return
          elsif message == type
            target_sids = get_current_ally_sids
            CoopDebugWindow.log_sent(type, target_sids, 0)
            return
          end
        end
      end

      def get_current_ally_sids
        if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
          CoopBattleState.get_ally_sids
        else
          # Try to get from squad
          squad = @squad rescue nil
          if squad && squad[:members]
            my_sid = session_id.to_s
            squad[:members].map { |m| m[:sid].to_s }.reject { |sid| sid == my_sid }
          else
            ["unknown"]
          end
        end
      end
    end
  end

  #=============================================================================
  # Hook into message processing to log received messages
  #=============================================================================

  # Create a wrapper module for receive logging
  module CoopDebugReceiveHooks
    TRACKED_PREFIXES = [
      "COOP_BTL_START_JSON",
      "COOP_BTL_START",
      "COOP_BATTLE_JOINED",
      "COOP_BATTLE_CANCEL",
      "COOP_BATTLE_BUSY",
      "COOP_ACTION",
      "COOP_RNG_SEED",
      "COOP_RNG_SEED_ACK",
      "COOP_SWITCH",
      "COOP_PARTY_PUSH_HEX",
      "COOP_PARTY_PUSH_NOW",
      "COOP_PARTY_REQ",
      "COOP_PARTY_RESP",
      "COOP_RUN_RESULT",
      "COOP_MOVE_SYNC",
      "COOP_BATTLE_ABORT"
    ]

    def self.log_received_message(from_sid, payload)
      return unless CoopDebugWindow.enabled?

      TRACKED_PREFIXES.each do |prefix|
        if payload.start_with?("#{prefix}:")
          data = payload.sub("#{prefix}:", "")
          CoopDebugWindow.log_received(prefix, from_sid, data.length)
          return
        elsif payload == prefix
          CoopDebugWindow.log_received(prefix, from_sid, 0)
          return
        end
      end
    end
  end

  #=============================================================================
  # Hook into the network thread message handler
  # This is done by patching the _handle_from_message method if it exists,
  # or by adding logging to individual handlers
  #=============================================================================

  module MultiplayerClient
    class << self
      # Add a generic receive logger that can be called from handlers
      def debug_log_receive(message_type, from_sid, payload_size = 0)
        CoopDebugReceiveHooks.log_received_message(from_sid, "#{message_type}:#{' ' * payload_size}")
      end
    end
  end

  #=============================================================================
  # Patch specific handler methods to add logging
  #=============================================================================

  # Patch _handle_coop_battle_invite
  if MultiplayerClient.respond_to?(:_handle_coop_battle_invite)
    module MultiplayerClient
      class << self
        alias _debug_hook_handle_coop_battle_invite _handle_coop_battle_invite

        def _handle_coop_battle_invite(from_sid, hex_data)
          CoopDebugWindow.log_received("COOP_BTL_START", from_sid, hex_data.to_s.length) if CoopDebugWindow.enabled?
          _debug_hook_handle_coop_battle_invite(from_sid, hex_data)
        end
      end
    end
  end

  # Patch _handle_coop_battle_invite_json
  if MultiplayerClient.respond_to?(:_handle_coop_battle_invite_json)
    module MultiplayerClient
      class << self
        alias _debug_hook_handle_coop_battle_invite_json _handle_coop_battle_invite_json

        def _handle_coop_battle_invite_json(from_sid, json_data)
          CoopDebugWindow.log_received("COOP_BTL_START_JSON", from_sid, json_data.to_s.length) if CoopDebugWindow.enabled?
          _debug_hook_handle_coop_battle_invite_json(from_sid, json_data)
        end
      end
    end
  end

  # Patch _handle_coop_battle_joined
  if MultiplayerClient.respond_to?(:_handle_coop_battle_joined)
    module MultiplayerClient
      class << self
        alias _debug_hook_handle_coop_battle_joined _handle_coop_battle_joined

        def _handle_coop_battle_joined(from_sid)
          CoopDebugWindow.log_received("COOP_BATTLE_JOINED", from_sid, 0) if CoopDebugWindow.enabled?
          _debug_hook_handle_coop_battle_joined(from_sid)
        end
      end
    end
  end

  puts "[COOP-DEBUG] Debug hooks installed for MultiplayerClient"
end

#===============================================================================
# Hook into CoopActionSync to log action sync events
#===============================================================================
if defined?(CoopDebugWindow) && defined?(CoopActionSync)
  module CoopActionSync
    class << self
      # Alias wait_for_all_actions if not already
      unless method_defined?(:_debug_hook_wait_for_all_actions)
        alias _debug_hook_wait_for_all_actions wait_for_all_actions
      end

      def wait_for_all_actions(battle, timeout_seconds = 30)
        if CoopDebugWindow.enabled? && defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
          ally_sids = CoopBattleState.get_ally_sids
          turn = battle.turnCount + 1
          CoopDebugWindow.log_expecting("COOP_ACTION", ally_sids, timeout_seconds)
          CoopDebugWindow.log_info("ACTION_SYNC", "Turn #{turn}: Waiting for #{ally_sids.length} allies")
        end

        result = _debug_hook_wait_for_all_actions(battle, timeout_seconds)

        if CoopDebugWindow.enabled?
          if result
            CoopDebugWindow.log_info("ACTION_SYNC", "Turn #{battle.turnCount + 1}: Sync COMPLETE")
          else
            missing = @expected_sids.reject { |sid| @pending_actions.key?(sid.to_s) } rescue []
            CoopDebugWindow.log_timeout("COOP_ACTION", missing)
            CoopDebugWindow.log_info("ACTION_SYNC", "Turn #{battle.turnCount + 1}: Sync FAILED - missing: #{missing.join(',')}")
          end
        end

        result
      end

      # Alias receive_action if not already
      unless method_defined?(:_debug_hook_receive_action)
        alias _debug_hook_receive_action receive_action
      end

      def receive_action(from_sid, battle_id, turn, hex_data)
        if CoopDebugWindow.enabled?
          CoopDebugWindow.log_received("COOP_ACTION", from_sid, hex_data.to_s.length)
          CoopDebugWindow.log_info("ACTION", "Received from #{from_sid} for turn #{turn}")
        end

        _debug_hook_receive_action(from_sid, battle_id, turn, hex_data)
      end
    end
  end

  puts "[COOP-DEBUG] Debug hooks installed for CoopActionSync"
end

#===============================================================================
# Hook into CoopRNGSync to log RNG sync events
#===============================================================================
if defined?(CoopDebugWindow) && defined?(CoopRNGSync)
  module CoopRNGSync
    class << self
      # Alias sync methods if not already
      unless method_defined?(:_debug_hook_sync_seed_as_initiator)
        if method_defined?(:sync_seed_as_initiator)
          alias _debug_hook_sync_seed_as_initiator sync_seed_as_initiator

          def sync_seed_as_initiator(battle, turn, wait_for_ack = true)
            if CoopDebugWindow.enabled?
              ally_sids = CoopBattleState.get_ally_sids rescue []
              CoopDebugWindow.log_info("RNG_SYNC", "Sending seed for turn #{turn}")
            end

            result = _debug_hook_sync_seed_as_initiator(battle, turn, wait_for_ack)

            if CoopDebugWindow.enabled?
              if result
                CoopDebugWindow.log_info("RNG_SYNC", "Turn #{turn}: RNG sync SUCCESS (initiator)")
              else
                CoopDebugWindow.log_info("RNG_SYNC", "Turn #{turn}: RNG sync FAILED (initiator)")
              end
            end

            result
          end
        end
      end

      unless method_defined?(:_debug_hook_sync_seed_as_receiver)
        if method_defined?(:sync_seed_as_receiver)
          alias _debug_hook_sync_seed_as_receiver sync_seed_as_receiver

          def sync_seed_as_receiver(battle, turn, timeout_seconds = 5, send_ack = true)
            if CoopDebugWindow.enabled?
              CoopDebugWindow.log_expecting("COOP_RNG_SEED", ["initiator"], timeout_seconds)
              CoopDebugWindow.log_info("RNG_SYNC", "Waiting for seed for turn #{turn}")
            end

            result = _debug_hook_sync_seed_as_receiver(battle, turn, timeout_seconds, send_ack)

            if CoopDebugWindow.enabled?
              if result
                CoopDebugWindow.log_info("RNG_SYNC", "Turn #{turn}: RNG sync SUCCESS (receiver)")
              else
                CoopDebugWindow.log_timeout("COOP_RNG_SEED", ["initiator"])
                CoopDebugWindow.log_info("RNG_SYNC", "Turn #{turn}: RNG sync TIMEOUT (receiver)")
              end
            end

            result
          end
        end
      end
    end
  end

  puts "[COOP-DEBUG] Debug hooks installed for CoopRNGSync"
end

#===============================================================================
# Hook into SyncScreen to log ally join events
#===============================================================================
if defined?(CoopDebugWindow)
  # Override pbCoopWaitForAllies if it exists
  if defined?(pbCoopWaitForAllies)
    alias _debug_hook_pbCoopWaitForAllies pbCoopWaitForAllies

    def pbCoopWaitForAllies(expected_allies)
      if CoopDebugWindow.enabled?
        ally_sids = expected_allies.map { |a| a[:sid].to_s }
        CoopDebugWindow.log_expecting("COOP_BATTLE_JOINED", ally_sids, 30)
        CoopDebugWindow.log_info("SYNC_SCREEN", "Waiting for #{expected_allies.length} allies to join")
      end

      result = _debug_hook_pbCoopWaitForAllies(expected_allies)

      if CoopDebugWindow.enabled?
        if result
          CoopDebugWindow.log_info("SYNC_SCREEN", "All allies joined successfully!")
        else
          # Find who didn't join
          joined_sids = MultiplayerClient.joined_ally_sids rescue []
          missing = expected_allies.reject { |a| joined_sids.include?(a[:sid].to_s) }
          missing_names = missing.map { |a| "#{a[:name]}(#{a[:sid]})" }
          CoopDebugWindow.log_timeout("COOP_BATTLE_JOINED", missing.map { |a| a[:sid] })
          CoopDebugWindow.log_info("SYNC_SCREEN", "FAILED - Missing: #{missing_names.join(', ')}")
        end
      end

      result
    end
  end

  puts "[COOP-DEBUG] Debug hooks installed for SyncScreen"
end

#===============================================================================
# Add F10 check to battle update loop
#===============================================================================
if defined?(PokeBattle_Battle)
  class PokeBattle_Battle
    alias _debug_hook_pbUpdate pbUpdate if method_defined?(:pbUpdate) && !method_defined?(:_debug_hook_pbUpdate)

    def pbUpdate(cw = nil)
      # Update debug window
      CoopDebugWindow.update if defined?(CoopDebugWindow) && CoopDebugWindow.enabled?

      # Call original
      _debug_hook_pbUpdate(cw) if respond_to?(:_debug_hook_pbUpdate)
    end
  end
end

#===============================================================================
# Hook into CoopBattleTransaction to log transaction events
#===============================================================================
if defined?(CoopDebugWindow) && defined?(CoopBattleTransaction)
  module CoopBattleTransaction
    class << self
      unless method_defined?(:_debug_hook_start)
        alias _debug_hook_start start

        def start(battle_id, expected_ally_sids, initiator_sid = nil)
          if CoopDebugWindow.enabled?
            CoopDebugWindow.log_info("TXN", "START: #{battle_id}")
            CoopDebugWindow.log_info("TXN", "Expected allies: #{expected_ally_sids.join(', ')}")
          end
          _debug_hook_start(battle_id, expected_ally_sids, initiator_sid)
        end
      end

      unless method_defined?(:_debug_hook_join)
        alias _debug_hook_join join

        def join(battle_id, initiator_sid)
          if CoopDebugWindow.enabled?
            CoopDebugWindow.log_info("TXN", "JOIN: #{battle_id} (initiator: #{initiator_sid})")
          end
          _debug_hook_join(battle_id, initiator_sid)
        end
      end

      unless method_defined?(:_debug_hook_cancel)
        alias _debug_hook_cancel cancel

        def cancel(reason = nil, broadcast = true)
          if CoopDebugWindow.enabled?
            CoopDebugWindow.log_info("TXN", "CANCEL: #{reason || 'no reason'}")
          end
          _debug_hook_cancel(reason, broadcast)
        end
      end
    end
  end

  puts "[COOP-DEBUG] Debug hooks installed for CoopBattleTransaction"
end

#===============================================================================
# CRITICAL: Add diagnostic logging to the non-initiator wait logic
# This helps identify the 3-player deadlock issue
#===============================================================================
module Coop3PlayerDiagnostics
  def self.log_join_sync_state(tag, my_sid, initiator_sid, invite_allies, joined_sids)
    return unless defined?(CoopDebugWindow) && CoopDebugWindow.enabled?

    CoopDebugWindow.log_info(tag, "=== JOIN SYNC STATE ===")
    CoopDebugWindow.log_info(tag, "My SID: #{my_sid}")
    CoopDebugWindow.log_info(tag, "Initiator SID: #{initiator_sid}")
    CoopDebugWindow.log_info(tag, "All allies in invite: #{invite_allies.map { |a| a[:sid] }.join(', ')}")
    CoopDebugWindow.log_info(tag, "Already joined SIDs: #{joined_sids.join(', ')}")

    # Calculate who we're waiting for
    other_non_initiators = invite_allies.select do |a|
      sid = a[:sid].to_s
      sid != my_sid && sid != initiator_sid && !joined_sids.include?(sid)
    end

    if other_non_initiators.length > 0
      waiting_for = other_non_initiators.map { |a| "#{a[:name]}(#{a[:sid]})" }.join(', ')
      CoopDebugWindow.log_info(tag, "WAITING FOR: #{waiting_for}")
      CoopDebugWindow.log_info(tag, "!!! POTENTIAL DEADLOCK if they're also waiting for us !!!")
    else
      CoopDebugWindow.log_info(tag, "No other non-initiators to wait for - proceeding")
    end
  end

  def self.log_joined_received(from_sid)
    return unless defined?(CoopDebugWindow) && CoopDebugWindow.enabled?

    joined_sids = MultiplayerClient.instance_variable_get(:@coop_battle_joined_sids) || [] rescue []
    CoopDebugWindow.log_info("JOINED", "Received JOINED from #{from_sid}")
    CoopDebugWindow.log_info("JOINED", "Current joined list: #{joined_sids.join(', ')}")
  end
end

puts "[COOP-DEBUG] All debug hooks installed successfully"
