#===============================================================================
# STABILITY MODULE 3: Thread-Safe CoopRNGSync
#===============================================================================
# Problem: receive_seed() is called from the NETWORK LISTENER thread.
#          sync_seed_as_receiver() is called from the GAME thread.
#          Both access @seed_buffer, @current_seed, @seed_received,
#          @expected_turn without any synchronization.
#
# Solution: Add a module-level mutex and wrap all shared state access.
#===============================================================================

if defined?(CoopRNGSync)
  module CoopRNGSync
    @rng_mutex = DebugMutex.new("RNGSync")

    class << self
      def rng_mutex
        @rng_mutex
      end
    end

    #---------------------------------------------------------------------------
    # Wrap receive_seed (WRITE path - network thread)
    #---------------------------------------------------------------------------
    class << self
      alias _receive_seed_unsynced receive_seed

      def receive_seed(battle_id, turn, seed)
        @rng_mutex.synchronize do
          StabilityDebug.info("RNG-MUTEX", "receive_seed ENTER turn=#{turn} seed=#{seed}") if defined?(StabilityDebug)
          result = _receive_seed_unsynced(battle_id, turn, seed)
          StabilityDebug.info("RNG-MUTEX", "receive_seed EXIT result=#{result}") if defined?(StabilityDebug)
          result
        end
      end
    end

    #---------------------------------------------------------------------------
    # Wrap sync_seed_as_receiver (READ/WRITE path - game thread)
    # Same approach as ActionSync: can't hold mutex during wait loop,
    # protect individual state accesses instead.
    #---------------------------------------------------------------------------
    class << self
      alias _sync_seed_receiver_unsynced sync_seed_as_receiver

      def sync_seed_as_receiver(battle, turn_num = nil, timeout_seconds = nil, reset_counter = true)
        return true unless defined?(CoopBattleState)
        return true unless CoopBattleState.in_coop_battle?

        battle_id = CoopBattleState.battle_id
        turn_num = turn_num || battle.turnCount

        StabilityDebug.info("RNG-SYNC", "Receiver waiting for seed: turn=#{turn_num} (no timeout, heartbeat-based)") if defined?(StabilityDebug)

        # Set expected turn + check buffer (mutex-protected)
        found_in_buffer = false
        @rng_mutex.synchronize do
          @expected_turn = turn_num

          if @seed_buffer[turn_num]
            @current_seed = @seed_buffer[turn_num]
            @seed_received = true
            @seed_buffer.delete(turn_num)
            @seed_wait_start_time = Time.now
            found_in_buffer = true
            StabilityDebug.info("RNG-SYNC", "Found seed in buffer: #{@current_seed}") if defined?(StabilityDebug)
          else
            @seed_received = false
            @current_seed = nil
            @seed_wait_start_time = Time.now
          end
        end

        # Wait loop if not found in buffer
        # Always wait forever - heartbeat handles disconnect detection.
        # timeout_seconds parameter is kept for API compat but ignored.
        unless found_in_buffer
          frame_count = 0

          loop do
            break if @rng_mutex.synchronize { @seed_received }

            Graphics.update if defined?(Graphics)
            Input.update if defined?(Input)

            frame_count += 1
            if frame_count % 60 == 0
              elapsed = (Time.now - (@rng_mutex.synchronize { @seed_wait_start_time } || Time.now)).round(1)
              StabilityDebug.info("RNG-SYNC", "Still waiting... #{elapsed}s") if defined?(StabilityDebug)
            end

            # Heartbeat: send every ~5s + check for disconnected allies
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

        # Check result (mutex-protected read)
        received, seed = @rng_mutex.synchronize { [@seed_received, @current_seed] }

        if received && seed
          # Apply seed (no mutex needed - only game thread does this)
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

          # Send ACK
          begin
            MultiplayerClient.send_data("COOP_RNG_SEED_ACK:#{battle_id}|#{turn_num}") if defined?(MultiplayerClient)
          rescue; end

          # Update HUD
          CoopBattleDebugHUD.update_rng_seed(seed) if defined?(CoopBattleDebugHUD)

          # Reset counter
          if reset_counter && defined?(CoopRNGDebug)
            CoopRNGDebug.reset_counter(turn_num)
          end

          wait_dur = (Time.now - (@rng_mutex.synchronize { @seed_wait_start_time } || Time.now)).round(3)
          StabilityDebug.info("RNG-SYNC", "Seed sync complete in #{wait_dur}s") if defined?(StabilityDebug)

          # Clear expected turn
          @rng_mutex.synchronize { @expected_turn = nil }
          true
        else
          StabilityDebug.error("RNG-SYNC", "TIMEOUT after #{timeout_seconds}s! seed_received=#{received}") if defined?(StabilityDebug)
          CoopBattleDebugHUD.set_message("RNG SEED TIMEOUT!") if defined?(CoopBattleDebugHUD)
          false
        end
      end
    end

    #---------------------------------------------------------------------------
    # Wrap reset_sync_state (WRITE path)
    #---------------------------------------------------------------------------
    class << self
      alias _reset_sync_state_rng_unsynced reset_sync_state

      def reset_sync_state
        @rng_mutex.synchronize do
          StabilityDebug.info("RNG-MUTEX", "reset_sync_state") if defined?(StabilityDebug)
          _reset_sync_state_rng_unsynced
        end
      end
    end
  end

  StabilityDebug.info("THREAD-SAFE", "CoopRNGSync mutex protection applied") if defined?(StabilityDebug)
else
  StabilityDebug.warn("THREAD-SAFE", "CoopRNGSync not defined - skipping mutex patch") if defined?(StabilityDebug)
end
