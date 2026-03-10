#===============================================================================
# MODULE: Coop Battle Transaction Manager
#===============================================================================
# Provides thread-safe coordination for 3+ player coop battles.
# Solves race conditions when:
# - One player cancels (ESC) while others are joining
# - Multiple players trigger encounters simultaneously
# - Network messages arrive out of order
#===============================================================================

module CoopBattleTransaction
  # Thread safety
  @mutex = Mutex.new

  # Transaction state
  @state = nil           # nil, :pending, :confirmed, :cancelled
  @transaction_id = nil  # Battle ID
  @initiator_sid = nil   # Who started this transaction

  # Participants tracking
  @expected_sids = []    # SIDs we expect to join
  @ready_sids = []       # SIDs that sent READY

  # Timing
  @start_time = nil
  @cancel_reason = nil

  #-----------------------------------------------------------------------------
  # Start a new transaction (initiator only)
  #-----------------------------------------------------------------------------
  def self.start(battle_id, expected_ally_sids, initiator_sid = nil)
    @mutex.synchronize do
      # Reject if already in a pending transaction
      if @state == :pending
        if defined?(MultiplayerDebug)
          MultiplayerDebug.warn("COOP-TXN", "Rejected start - already pending: #{@transaction_id}")
        end
        return false
      end

      @state = :pending
      @transaction_id = battle_id
      @initiator_sid = initiator_sid || (defined?(MultiplayerClient) ? MultiplayerClient.session_id : nil)
      @expected_sids = expected_ally_sids.dup
      @ready_sids = []
      @start_time = Time.now
      @cancel_reason = nil

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("COOP-TXN", "Started transaction: #{battle_id}")
        MultiplayerDebug.info("COOP-TXN", "  Expected allies: #{@expected_sids.join(', ')}")
      end

      true
    end
  end

  #-----------------------------------------------------------------------------
  # Join a transaction (non-initiator)
  #-----------------------------------------------------------------------------
  def self.join(battle_id, initiator_sid)
    @mutex.synchronize do
      # If we have a different pending transaction, cancel it first
      if @state == :pending && @transaction_id != battle_id
        if defined?(MultiplayerDebug)
          MultiplayerDebug.warn("COOP-TXN", "Replacing transaction #{@transaction_id} with #{battle_id}")
        end
      end

      @state = :pending
      @transaction_id = battle_id
      @initiator_sid = initiator_sid
      @expected_sids = []  # Non-initiator doesn't track others
      @ready_sids = []
      @start_time = Time.now
      @cancel_reason = nil

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("COOP-TXN", "Joined transaction: #{battle_id} (initiator: #{initiator_sid})")
      end

      true
    end
  end

  #-----------------------------------------------------------------------------
  # Mark a participant as ready
  #-----------------------------------------------------------------------------
  def self.mark_ready(sid)
    @mutex.synchronize do
      return false unless @state == :pending

      unless @ready_sids.include?(sid.to_s)
        @ready_sids << sid.to_s
        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("COOP-TXN", "Participant ready: #{sid} (#{@ready_sids.length}/#{@expected_sids.length})")
        end
      end

      # Return true if all expected participants are ready
      all_ready?
    end
  end

  #-----------------------------------------------------------------------------
  # Check if all expected participants are ready
  #-----------------------------------------------------------------------------
  def self.all_ready?
    return false unless @state == :pending
    return true if @expected_sids.empty?  # Non-initiator doesn't track
    @ready_sids.length >= @expected_sids.length
  end

  #-----------------------------------------------------------------------------
  # Cancel the transaction
  #-----------------------------------------------------------------------------
  def self.cancel(reason = nil, broadcast = true)
    battle_id = nil

    @mutex.synchronize do
      return if @state.nil? || @state == :cancelled

      battle_id = @transaction_id
      @state = :cancelled
      @cancel_reason = reason

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("COOP-TXN", "Transaction CANCELLED: #{battle_id}")
        MultiplayerDebug.info("COOP-TXN", "  Reason: #{reason || 'none'}") if reason
      end
    end

    # Broadcast cancellation outside mutex to avoid deadlock
    if broadcast && battle_id && defined?(MultiplayerClient)
      begin
        msg = "COOP_BATTLE_CANCEL:#{battle_id}|#{reason || 'cancelled'}"
        MultiplayerClient.send_data(msg)
      rescue => e
        if defined?(MultiplayerDebug)
          MultiplayerDebug.warn("COOP-TXN", "Failed to broadcast cancel: #{e.message}")
        end
      end
    end
  end

  #-----------------------------------------------------------------------------
  # Receive cancellation from network
  #-----------------------------------------------------------------------------
  def self.receive_cancel(battle_id, reason)
    @mutex.synchronize do
      # Only process if it's our current transaction
      if @transaction_id == battle_id && @state == :pending
        @state = :cancelled
        @cancel_reason = reason

        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("COOP-TXN", "Received CANCEL for #{battle_id}: #{reason}")
        end
        return true
      end
      false
    end
  end

  #-----------------------------------------------------------------------------
  # Confirm the transaction (all ready, proceed to battle)
  #-----------------------------------------------------------------------------
  def self.confirm
    @mutex.synchronize do
      return false unless @state == :pending

      @state = :confirmed

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("COOP-TXN", "Transaction CONFIRMED: #{@transaction_id}")
      end

      true
    end
  end

  #-----------------------------------------------------------------------------
  # Reset the transaction state
  #-----------------------------------------------------------------------------
  def self.reset
    @mutex.synchronize do
      if defined?(MultiplayerDebug) && @transaction_id
        MultiplayerDebug.info("COOP-TXN", "Transaction RESET (was: #{@state}, id: #{@transaction_id})")
      end

      @state = nil
      @transaction_id = nil
      @initiator_sid = nil
      @expected_sids = []
      @ready_sids = []
      @start_time = nil
      @cancel_reason = nil
    end
  end

  #-----------------------------------------------------------------------------
  # State queries (thread-safe)
  #-----------------------------------------------------------------------------
  def self.pending?
    @mutex.synchronize { @state == :pending }
  end

  def self.cancelled?
    @mutex.synchronize { @state == :cancelled }
  end

  def self.confirmed?
    @mutex.synchronize { @state == :confirmed }
  end

  # Check if we're in any active transaction (pending or confirmed)
  # Use this to prevent cascading encounters while joining a battle
  def self.active?
    @mutex.synchronize { @state == :pending || @state == :confirmed }
  end

  def self.transaction_id
    @mutex.synchronize { @transaction_id }
  end

  def self.cancel_reason
    @mutex.synchronize { @cancel_reason }
  end

  def self.ready_count
    @mutex.synchronize { @ready_sids.length }
  end

  def self.expected_count
    @mutex.synchronize { @expected_sids.length }
  end

  #-----------------------------------------------------------------------------
  # Check for timeout (call from main loop)
  #-----------------------------------------------------------------------------
  def self.check_timeout(timeout_seconds = 30)
    @mutex.synchronize do
      return false unless @state == :pending && @start_time

      if Time.now - @start_time > timeout_seconds
        if defined?(MultiplayerDebug)
          MultiplayerDebug.warn("COOP-TXN", "Transaction TIMEOUT after #{timeout_seconds}s")
        end
        @state = :cancelled
        @cancel_reason = "timeout"
        return true
      end
      false
    end
  end
end

if defined?(MultiplayerDebug)
  MultiplayerDebug.info("COOP-TXN", "Coop Battle Transaction module loaded")
end
