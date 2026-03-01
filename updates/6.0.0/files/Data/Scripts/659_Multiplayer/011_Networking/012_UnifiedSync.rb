#===============================================================================
# STABILITY MODULE 10: Unified Sync Overrides
#===============================================================================
# FINAL overrides for action sync and RNG sync wait loops.
# Loads AFTER 902, 903, 906, 908 — last definition wins, no alias chains.
#
# - Action sync: infinite wait loop, heartbeat disconnect detection
# - RNG sync:    infinite wait loop, heartbeat disconnect detection
# - No timeouts anywhere — battle only proceeds when all data is received
#   or heartbeat detects a disconnected ally
#
# 902/903 still handle mutex wrapping on write paths (receive_action, etc.)
# This file only replaces the two wait-loop methods.
#===============================================================================

#===============================================================================
# CoopActionSync.wait_for_all_actions — clean override
#===============================================================================
if defined?(CoopActionSync)
  module CoopActionSync
    # Ensure mutex exists (902 should have created it, but be safe)
    @stability_mutex ||= DebugMutex.new("ActionSync")

    class << self
      def wait_for_all_actions(battle, timeout_seconds = nil)
        return true unless defined?(CoopBattleState)
        return true unless CoopBattleState.in_coop_battle?

        ally_sids = CoopBattleState.get_ally_sids
        return true if ally_sids.empty?

        battle_id = CoopBattleState.battle_id
        turn_num  = battle.turnCount + 1

        StabilityDebug.separator("ACTION SYNC T#{turn_num}") if defined?(StabilityDebug)
        StabilityDebug.info("ACT-SYNC", "Waiting for #{ally_sids.length} allies: #{ally_sids.join(', ')} [910 infinite]") if defined?(StabilityDebug)

        # Reset heartbeat tracking for this turn — clears stale timestamps
        # from previous turn so allies aren't falsely flagged as disconnected
        # while they're still picking moves
        CoopHeartbeat.initialize_allies(ally_sids) if defined?(CoopHeartbeat)

        # Send my actions first
        my_actions = extract_my_actions(battle)
        unless send_my_actions(battle, my_actions)
          StabilityDebug.error("ACT-SYNC", "Failed to send my actions!") if defined?(StabilityDebug)
          return false
        end

        # Initialize sync state (mutex-protected)
        @stability_mutex.synchronize do
          @expected_sids  = ally_sids.dup
          @sync_complete  = false
          @sync_start_time = Time.now
          @current_turn   = turn_num

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

          check_sync_complete
        end

        # Instant sync if everything arrived early
        if @stability_mutex.synchronize { @sync_complete }
          StabilityDebug.info("ACT-SYNC", "All actions already received — instant sync") if defined?(StabilityDebug)
          return true
        end

        # HUD
        if defined?(CoopBattleDebugHUD)
          CoopBattleDebugHUD.reset_action_status
          CoopBattleDebugHUD.update_turn(turn_num)
          CoopBattleDebugHUD.set_message("Waiting for #{ally_sids.length} allies...")
        end

        #-----------------------------------------------------------------------
        # INFINITE WAIT LOOP — no timeout, heartbeat handles disconnects
        #-----------------------------------------------------------------------
        frame_count = 0
        loop do
          break if @stability_mutex.synchronize { @sync_complete }

          Graphics.update if defined?(Graphics)
          Input.update    if defined?(Input)

          # Battle ended externally (e.g. ally ran)
          if battle.decision != 0
            StabilityDebug.info("ACT-SYNC", "Battle ended during sync (decision=#{battle.decision})") if defined?(StabilityDebug)
            return true
          end

          CoopBattleDebugHUD.check_toggle_input if defined?(CoopBattleDebugHUD)

          frame_count += 1

          # Status log every ~1s
          if frame_count % 60 == 0
            elapsed = (Time.now - (@stability_mutex.synchronize { @sync_start_time } || Time.now)).round(1)
            pending_count, total_count, missing = @stability_mutex.synchronize do
              m = @expected_sids.reject { |sid| @pending_actions.key?(sid.to_s) }
              [@pending_actions.length, @expected_sids.length, m]
            end
            StabilityDebug.info("ACT-SYNC", "#{elapsed}s elapsed, #{pending_count}/#{total_count} received, missing: #{missing.join(', ')}") if defined?(StabilityDebug)
            if defined?(MultiplayerDebug) && elapsed >= 2.0
              MultiplayerDebug.info("COOP-SYNC", "Waiting... #{elapsed}s, #{pending_count}/#{total_count}, missing: #{missing.join(', ')}")
            end
          end

          # Heartbeat every ~5s
          if defined?(CoopHeartbeat) && frame_count % 300 == 0
            CoopHeartbeat.send_heartbeat(battle_id, turn_num)
            check_heartbeat_disconnects if respond_to?(:check_heartbeat_disconnects)
          end

          sleep(0.016)
        end

        # Post-loop
        is_complete = @stability_mutex.synchronize { @sync_complete }
        if is_complete
          duration = (Time.now - (@stability_mutex.synchronize { @sync_start_time } || Time.now)).round(3)
          StabilityDebug.info("ACT-SYNC", "Sync COMPLETE in #{duration}s") if defined?(StabilityDebug)
          CoopBattleDebugHUD.set_message("Sync complete! (#{duration}s)") if defined?(CoopBattleDebugHUD)
          true
        else
          missing = @stability_mutex.synchronize do
            @expected_sids.reject { |sid| @pending_actions.key?(sid.to_s) }
          end
          StabilityDebug.error("ACT-SYNC", "Sync FAILED! Missing: #{missing.join(', ')}") if defined?(StabilityDebug)
          CoopBattleDebugHUD.set_message("Sync failed! Missing: #{missing.join(', ')}") if defined?(CoopBattleDebugHUD)
          false
        end
      end
    end
  end

  StabilityDebug.info("UNIFIED", "CoopActionSync.wait_for_all_actions overridden [910]") if defined?(StabilityDebug)
end

#===============================================================================
# CoopRNGSync.sync_seed_as_receiver — clean override
#===============================================================================
if defined?(CoopRNGSync)
  module CoopRNGSync
    # Ensure mutex exists (903 should have created it, but be safe)
    @rng_mutex ||= DebugMutex.new("RNGSync")

    class << self
      def sync_seed_as_receiver(battle, turn_num = nil, timeout_seconds = nil, reset_counter = true)
        return true unless defined?(CoopBattleState)
        return true unless CoopBattleState.in_coop_battle?

        battle_id = CoopBattleState.battle_id
        turn_num  = turn_num || battle.turnCount

        StabilityDebug.info("RNG-SYNC", "Receiver waiting for seed: turn=#{turn_num} [910 infinite]") if defined?(StabilityDebug)

        # Reset heartbeat tracking — clears stale timestamps from previous turn
        ally_sids = (CoopBattleState.get_ally_sids rescue [])
        CoopHeartbeat.initialize_allies(ally_sids) if defined?(CoopHeartbeat) && !ally_sids.empty?

        # Check seed buffer first (mutex-protected)
        found_in_buffer = false
        @rng_mutex.synchronize do
          @expected_turn = turn_num

          if @seed_buffer[turn_num]
            @current_seed   = @seed_buffer[turn_num]
            @seed_received  = true
            @seed_buffer.delete(turn_num)
            @seed_wait_start_time = Time.now
            found_in_buffer = true
            StabilityDebug.info("RNG-SYNC", "Found seed in buffer: #{@current_seed}") if defined?(StabilityDebug)
          else
            @seed_received  = false
            @current_seed   = nil
            @seed_wait_start_time = Time.now
          end
        end

        #-----------------------------------------------------------------------
        # INFINITE WAIT LOOP — no timeout, heartbeat handles disconnects
        #-----------------------------------------------------------------------
        unless found_in_buffer
          frame_count = 0

          loop do
            break if @rng_mutex.synchronize { @seed_received }

            Graphics.update if defined?(Graphics)
            Input.update    if defined?(Input)

            frame_count += 1

            # Status log every ~1s
            if frame_count % 60 == 0
              elapsed = (Time.now - (@rng_mutex.synchronize { @seed_wait_start_time } || Time.now)).round(1)
              StabilityDebug.info("RNG-SYNC", "Still waiting... #{elapsed}s") if defined?(StabilityDebug)
            end

            # Heartbeat every ~5s + disconnect check
            if defined?(CoopHeartbeat) && frame_count % 300 == 0
              CoopHeartbeat.send_heartbeat(battle_id, turn_num)
              ally_sids = (CoopBattleState.get_ally_sids rescue [])
              disconnected = CoopHeartbeat.check_disconnected(ally_sids)
              unless disconnected.empty?
                StabilityDebug.warn("RNG-SYNC", "Ally disconnected during RNG wait: #{disconnected.join(', ')}") if defined?(StabilityDebug)
                break
              end
            end

            sleep(0.016)
          end
        end

        # Apply result
        received, seed = @rng_mutex.synchronize { [@seed_received, @current_seed] }

        if received && seed
          begin
            @battle_rng = Random.new(seed)
            prev = srand(seed)
            StabilityDebug.info("RNG-SYNC", "Applied seed: srand(#{seed}), prev=#{prev}") if defined?(StabilityDebug)

            if defined?(RNGLog)
              role = CoopBattleState.am_i_initiator? ? "INIT" : "NON"
              caller_info = caller[0..2].map { |c| c.gsub(/.*Scripts\//, "") }.join(" <- ")
              RNGLog.write("[SEED][#{role}][T#{turn_num}] srand(#{seed})+Random.new prev=#{prev} FROM: #{caller_info}")
            end
          rescue => e
            StabilityDebug.error("RNG-SYNC", "Failed to apply seed: #{e.class}: #{e.message}") if defined?(StabilityDebug)
            return false
          end

          begin
            MultiplayerClient.send_data("COOP_RNG_SEED_ACK:#{battle_id}|#{turn_num}") if defined?(MultiplayerClient)
          rescue; end

          CoopBattleDebugHUD.update_rng_seed(seed) if defined?(CoopBattleDebugHUD)

          if reset_counter && defined?(CoopRNGDebug)
            CoopRNGDebug.reset_counter(turn_num)
          end

          wait_dur = (Time.now - (@rng_mutex.synchronize { @seed_wait_start_time } || Time.now)).round(3)
          StabilityDebug.info("RNG-SYNC", "Seed sync complete in #{wait_dur}s") if defined?(StabilityDebug)

          @rng_mutex.synchronize { @expected_turn = nil }
          true
        else
          StabilityDebug.error("RNG-SYNC", "Sync FAILED! seed_received=#{received}") if defined?(StabilityDebug)
          CoopBattleDebugHUD.set_message("RNG SYNC FAILED!") if defined?(CoopBattleDebugHUD)
          false
        end
      end
    end
  end

  StabilityDebug.info("UNIFIED", "CoopRNGSync.sync_seed_as_receiver overridden [910]") if defined?(StabilityDebug)
end

StabilityDebug.info("UNIFIED", "Module 910_UnifiedSync loaded") if defined?(StabilityDebug)
