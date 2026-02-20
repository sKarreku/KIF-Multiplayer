#===============================================================================
# STABILITY MODULE 2: Thread-Safe CoopActionSync
#===============================================================================
# Problem: receive_action() is called from the NETWORK LISTENER thread.
#          wait_for_all_actions() is called from the GAME thread.
#          Both read/write @pending_actions, @future_actions, @sync_complete,
#          @expected_sids without any synchronization.
#
# Solution: Add a module-level mutex and wrap all shared state access.
# This file monkey-patches CoopActionSync AFTER it loads (021_Coop_ActionSync.rb)
# to inject mutex protection without modifying the original file.
#===============================================================================

if defined?(CoopActionSync)
  module CoopActionSync
    # Create the mutex (module-level, persists across resets)
    @stability_mutex = DebugMutex.new("ActionSync")

    class << self
      # Expose mutex for external use (e.g., heartbeat module)
      def stability_mutex
        @stability_mutex
      end
    end

    #---------------------------------------------------------------------------
    # Wrap receive_action (WRITE path - network thread)
    #---------------------------------------------------------------------------
    class << self
      alias _receive_action_unsynced receive_action

      def receive_action(from_sid, battle_id, turn, hex_data)
        @stability_mutex.synchronize do
          StabilityDebug.info("ACT-MUTEX", "receive_action ENTER from=#{from_sid} turn=#{turn}") if defined?(StabilityDebug)
          result = _receive_action_unsynced(from_sid, battle_id, turn, hex_data)
          StabilityDebug.info("ACT-MUTEX", "receive_action EXIT result=#{result}") if defined?(StabilityDebug)
          result
        end
      end
    end

    #---------------------------------------------------------------------------
    # Wrap receive_failed_run (WRITE path - network thread)
    #---------------------------------------------------------------------------
    class << self
      alias _receive_failed_run_unsynced receive_failed_run

      def receive_failed_run(battle, battle_id, turn, battler_idx)
        @stability_mutex.synchronize do
          StabilityDebug.info("ACT-MUTEX", "receive_failed_run ENTER battler=#{battler_idx}") if defined?(StabilityDebug)
          _receive_failed_run_unsynced(battle, battle_id, turn, battler_idx)
        end
      end
    end

    #---------------------------------------------------------------------------
    # Wrap wait_for_all_actions (READ/WRITE path - game thread)
    # NOTE: We can't hold the mutex for the entire wait loop (it would block
    # receive_action). Instead we protect individual state accesses.
    #---------------------------------------------------------------------------
    class << self
      alias _wait_for_all_actions_unsynced wait_for_all_actions

      def wait_for_all_actions(battle, timeout_seconds = nil)
        return true unless defined?(CoopBattleState)
        return true unless CoopBattleState.in_coop_battle?

        ally_sids = CoopBattleState.get_ally_sids
        return true if ally_sids.empty?

        battle_id = CoopBattleState.battle_id
        turn_num = battle.turnCount + 1

        StabilityDebug.separator("ACTION SYNC T#{turn_num}") if defined?(StabilityDebug)
        StabilityDebug.info("ACT-SYNC", "Waiting for #{ally_sids.length} allies: #{ally_sids.join(', ')} (no timeout, heartbeat-based)") if defined?(StabilityDebug)

        # Extract and send my actions first (no mutex needed - local only)
        my_actions = extract_my_actions(battle)
        unless send_my_actions(battle, my_actions)
          StabilityDebug.error("ACT-SYNC", "Failed to send my actions!") if defined?(StabilityDebug)
          return false
        end

        # Initialize sync state (mutex-protected)
        @stability_mutex.synchronize do
          @expected_sids = ally_sids.dup
          @sync_complete = false
          @sync_start_time = Time.now
          @current_turn = turn_num

          # Pull early arrivals from future queue
          ally_sids.each do |sid|
            sid_key = sid.to_s
            if @future_actions[sid_key] && @future_actions[sid_key][turn_num]
              queued = @future_actions[sid_key][turn_num]
              @pending_actions[sid_key] = queued
              @remote_player_actions[sid_key] = queued[:choices]
              @future_actions[sid_key].delete(turn_num)
              StabilityDebug.info("ACT-SYNC", "Retrieved early action from #{sid} (future queue)") if defined?(StabilityDebug)
            end
          end

          # Check if already complete
          check_sync_complete
        end

        # Early exit if all received before we started waiting
        if @stability_mutex.synchronize { @sync_complete }
          StabilityDebug.info("ACT-SYNC", "All actions already received - instant sync") if defined?(StabilityDebug)
          return true
        end

        # Reset debug HUD
        if defined?(CoopBattleDebugHUD)
          CoopBattleDebugHUD.reset_action_status
          CoopBattleDebugHUD.update_turn(turn_num)
          CoopBattleDebugHUD.set_message("Waiting for #{ally_sids.length} allies...")
        end

        # Wait loop (mutex NOT held - receive_action can write freely)
        # Always wait forever - heartbeat handles disconnect detection.
        # timeout_seconds parameter is kept for API compat but ignored.
        frame_count = 0

        loop do
          # Check sync complete (mutex-protected read)
          break if @stability_mutex.synchronize { @sync_complete }

          Graphics.update if defined?(Graphics)
          Input.update if defined?(Input)

          # Check if battle ended mid-sync
          if battle.decision != 0
            StabilityDebug.info("ACT-SYNC", "Battle ended during sync (decision=#{battle.decision})") if defined?(StabilityDebug)
            return true
          end

          # Debug HUD toggle
          CoopBattleDebugHUD.check_toggle_input if defined?(CoopBattleDebugHUD)

          # Periodic status (every ~1s)
          frame_count += 1
          if frame_count % 60 == 0
            elapsed = (Time.now - (@stability_mutex.synchronize { @sync_start_time } || Time.now)).round(1)
            pending_count, total_count, missing = @stability_mutex.synchronize do
              received = @pending_actions.keys
              missing = @expected_sids.reject { |sid| @pending_actions.key?(sid.to_s) }
              [@pending_actions.length, @expected_sids.length, missing]
            end

            StabilityDebug.info("ACT-SYNC", "#{elapsed}s elapsed, #{pending_count}/#{total_count} received, missing: #{missing.join(', ')}") if defined?(StabilityDebug)

            if defined?(MultiplayerDebug) && elapsed >= 2.0
              MultiplayerDebug.info("COOP-SYNC", "Waiting... #{elapsed}s, #{pending_count}/#{total_count}, missing: #{missing.join(', ')}")
            end
          end

          # Send heartbeat every ~5s + check for disconnected allies
          if defined?(CoopHeartbeat) && frame_count % 300 == 0
            CoopHeartbeat.send_heartbeat(battle_id, turn_num)
            check_heartbeat_disconnects if respond_to?(:check_heartbeat_disconnects)
          end

          sleep(0.016)
        end

        # Final result
        is_complete = @stability_mutex.synchronize { @sync_complete }

        if is_complete
          duration = (Time.now - (@stability_mutex.synchronize { @sync_start_time } || Time.now)).round(3)
          StabilityDebug.info("ACT-SYNC", "Sync COMPLETE in #{duration}s") if defined?(StabilityDebug)

          if defined?(CoopBattleDebugHUD)
            CoopBattleDebugHUD.set_message("Sync complete! (#{duration}s)")
          end
          return true
        else
          missing = @stability_mutex.synchronize do
            @expected_sids.reject { |sid| @pending_actions.key?(sid.to_s) }
          end
          StabilityDebug.error("ACT-SYNC", "Sync FAILED! Missing: #{missing.join(', ')}") if defined?(StabilityDebug)

          if defined?(CoopBattleDebugHUD)
            CoopBattleDebugHUD.set_message("Sync failed! Missing: #{missing.join(', ')}")
          end
          return false
        end
      end
    end

    #---------------------------------------------------------------------------
    # Wrap apply_remote_player_actions (READ path - game thread)
    #---------------------------------------------------------------------------
    class << self
      alias _apply_remote_unsynced apply_remote_player_actions

      def apply_remote_player_actions(battle)
        # Take a snapshot under mutex, then apply outside mutex
        actions_snapshot = @stability_mutex.synchronize { @remote_player_actions.dup }

        # Temporarily replace with snapshot, call original, restore
        orig = @remote_player_actions
        @remote_player_actions = actions_snapshot
        begin
          _apply_remote_unsynced(battle)
        ensure
          @remote_player_actions = orig
        end
      end
    end

    #---------------------------------------------------------------------------
    # Wrap reset methods (WRITE path - game thread)
    #---------------------------------------------------------------------------
    class << self
      alias _reset_sync_state_unsynced reset_sync_state

      def reset_sync_state
        @stability_mutex.synchronize do
          StabilityDebug.info("ACT-MUTEX", "reset_sync_state") if defined?(StabilityDebug)
          _reset_sync_state_unsynced
        end
      end

      alias _full_reset_unsynced full_reset

      def full_reset
        @stability_mutex.synchronize do
          StabilityDebug.info("ACT-MUTEX", "full_reset") if defined?(StabilityDebug)
          _full_reset_unsynced
        end
      end
    end

    #---------------------------------------------------------------------------
    # Wrap get_pending_actions (READ path)
    #---------------------------------------------------------------------------
    class << self
      alias _get_pending_unsynced get_pending_actions

      def get_pending_actions
        @stability_mutex.synchronize { _get_pending_unsynced }
      end
    end
  end

  StabilityDebug.info("THREAD-SAFE", "CoopActionSync mutex protection applied") if defined?(StabilityDebug)
else
  StabilityDebug.warn("THREAD-SAFE", "CoopActionSync not defined - skipping mutex patch") if defined?(StabilityDebug)
end
