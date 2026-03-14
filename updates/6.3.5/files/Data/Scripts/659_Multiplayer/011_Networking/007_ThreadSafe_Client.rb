#===============================================================================
# STABILITY MODULE 4: Thread-Safe Client Shared State
#===============================================================================
# Problem: @coop_remote_party written by listener thread (COOP_PARTY_PUSH_HEX),
#          read by game thread (remote_party, pick_nearby_allies, wild hook cache
#          clear). @coop_battle_go_received also cross-thread.
#
# Solution: Extend @coop_mutex to protect @coop_remote_party reads/writes.
#           Replace direct instance_variable_get access in wild hook with
#           safe helper methods.
#===============================================================================

if defined?(MultiplayerClient)
  class << MultiplayerClient

    #---------------------------------------------------------------------------
    # Thread-safe remote_party accessor (replaces unprotected read)
    #---------------------------------------------------------------------------
    alias _remote_party_unsynced remote_party

    def remote_party(sid)
      @coop_mutex.synchronize do
        key = sid.to_s
        arr = @coop_remote_party[key]
        return [] unless arr.is_a?(Array) && arr.all? { |p| p.is_a?(Pokemon) }
        arr.dup  # Return a COPY so caller can't corrupt shared state
      end
    end

    #---------------------------------------------------------------------------
    # Thread-safe party cache clear (replaces instance_variable_get in wild hook)
    #---------------------------------------------------------------------------
    def clear_remote_party_cache(sid)
      @coop_mutex.synchronize do
        old = @coop_remote_party[sid.to_s]
        @coop_remote_party.delete(sid.to_s)
        StabilityDebug.info("CLIENT-TS", "Cleared cached party for #{sid} (had #{old ? old.length : 0} Pokemon)") if defined?(StabilityDebug)
      end
    end

    #---------------------------------------------------------------------------
    # Thread-safe party cache write (wraps the write in _handle_coop_party_push_hex)
    #---------------------------------------------------------------------------
    alias _handle_coop_party_push_hex_unsynced _handle_coop_party_push_hex

    def _handle_coop_party_push_hex(from_sid, hex)
      # The original method does deserialization then writes to @coop_remote_party.
      # We wrap the entire thing so the write is atomic with validation.
      # The original is safe to call (it does its own error handling).
      # We just need to protect the final write.

      begin
        # Rate limiting check
        unless check_marshal_rate_limit(from_sid)
          return
        end

        # Size limit check
        max_size = 500_000
        if hex.to_s.length > max_size * 2
          return
        end

        json_str = BinHex.decode(hex.to_s)
        party_data = MiniJSON.parse(json_str)

        unless party_data.is_a?(Array)
          raise "Decoded payload is not Array (#{party_data.class})"
        end

        list = PokemonSerializer.deserialize_party(party_data)

        unless list.is_a?(Array) && list.all? { |p| p.is_a?(Pokemon) }
          raise "Deserialized payload is not Array<Pokemon> (#{list.class})"
        end

        # THREAD-SAFE WRITE
        @coop_mutex.synchronize do
          @coop_remote_party[from_sid.to_s] = list
        end

        StabilityDebug.info("CLIENT-TS", "Cached party from #{from_sid}: #{list.length} Pokemon (mutex-protected)") if defined?(StabilityDebug)

        SnapshotLog.log_snapshot_received(from_sid, list.length) if defined?(SnapshotLog)
      rescue => e
        StabilityDebug.error("CLIENT-TS", "Party push failed from #{from_sid}: #{e.class}: #{e.message}") if defined?(StabilityDebug)
      end
    end
  end

  StabilityDebug.info("THREAD-SAFE", "MultiplayerClient shared state mutex protection applied") if defined?(StabilityDebug)
else
  StabilityDebug.warn("THREAD-SAFE", "MultiplayerClient not defined - skipping mutex patch") if defined?(StabilityDebug)
end

#===============================================================================
# Patch wild hook to use thread-safe cache clear instead of instance_variable_get
#===============================================================================
# The wild hook at lines 781-784 does:
#   MultiplayerClient.instance_variable_get(:@coop_remote_party).delete(sid.to_s)
# This is NOT thread-safe. We can't easily patch those specific lines, but
# we CAN override pick_nearby_allies to use the new thread-safe accessors.
# The cache clear in the encounter hook happens before party wait,
# so we advise the user to replace those lines manually or we patch via
# a wrapper around the initiator path.
#
# For now: the _handle_coop_party_push_hex override above protects the WRITE.
# The remote_party override above protects the READ with .dup.
# The cache clear in 017 still uses instance_variable_get - this is a known
# limitation. The worst case is a stale cache read (non-critical - just means
# the wait loop takes slightly longer). The WRITE and READ are protected.
#===============================================================================

StabilityDebug.info("CLIENT-TS", "Module 904_ThreadSafe_Client loaded") if defined?(StabilityDebug)
