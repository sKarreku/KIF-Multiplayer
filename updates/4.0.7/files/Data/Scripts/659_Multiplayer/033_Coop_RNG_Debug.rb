#===============================================================================
# MODULE 16: RNG Debug Logging (ENABLED FOR DEBUGGING)
#===============================================================================
# Adds logging to track RNG calls during battle to debug desyncs
# To disable, wrap lines 9-200 in =begin...=end comment block
#===============================================================================

module CoopRNGDebug
  @rand_call_count = 0
  @current_turn = 0
  @current_phase = "UNKNOWN"
  @phase_start_count = 0
  @call_history = []  # Store all calls for post-battle analysis
  @phase_history = []  # Track phase transitions
  @logging_active = false  # Prevent re-entrant logging

  # Phase markers
  def self.set_phase(phase_name)
    old_phase = @current_phase
    @current_phase = phase_name
    @phase_start_count = @rand_call_count

    phase_info = {
      turn: @current_turn,
      phase: phase_name,
      start_count: @phase_start_count,
      timestamp: Time.now.to_f
    }
    @phase_history << phase_info

    ##MultiplayerDebug.info("COOP-RNG-PHASE", ">>> PHASE CHANGE: #{old_phase} -> #{phase_name} [Turn #{@current_turn}, Call ##{@rand_call_count}]")
  end

  def self.reset_counter(turn)
    @current_turn = turn
    @rand_call_count = 0
    @phase_start_count = 0
    @current_phase = "TURN_START"

    # Log phase history summary from previous turn
    if @phase_history.any?
      ##MultiplayerDebug.info("COOP-RNG-SUMMARY", "=== Turn #{turn-1} Phase Summary ===")
      @phase_history.each do |ph|
        ##MultiplayerDebug.info("COOP-RNG-SUMMARY", "  #{ph[:phase]}: Started at call ##{ph[:start_count]}")
      end
      @phase_history = []
    end

    ##MultiplayerDebug.info("COOP-RNG-COUNT", "=== TURN #{turn}: RNG counter reset ===")
  end

  def self.increment
    @rand_call_count += 1
  end

  def self.report
    ##MultiplayerDebug.info("COOP-RNG-COUNT", "=== TURN #{@current_turn} COMPLETE: Total rand() calls = #{@rand_call_count} ===")
  end

  # Get current count (for checkpoints)
  def self.current_count
    @rand_call_count
  end

  # Get count in current phase
  def self.phase_count
    @rand_call_count - @phase_start_count
  end

  # Export call history for comparison
  def self.export_history
    @call_history.dup
  end

  # Clear history
  def self.clear_history
    @call_history = []
    @phase_history = []
  end

  # Add a call to history
  def self.record_call(args, result, caller_info)
    @call_history << {
      call_num: @rand_call_count,
      turn: @current_turn,
      phase: @current_phase,
      phase_call_num: phase_count,
      args: args,
      result: result,
      caller: caller_info,
      timestamp: Time.now.to_f
    }
  end

  # Checkpoint marker (for manual verification points)
  def self.checkpoint(name)
    role = defined?(CoopBattleState) && CoopBattleState.am_i_initiator? ? "INIT" : "NON-INIT"
    ##MultiplayerDebug.info("COOP-RNG-CHECKPOINT", ">>> CHECKPOINT [#{name}] Turn=#{@current_turn} Phase=#{@current_phase} Count=#{@rand_call_count} Role=#{role}")
  end
end

# Wrap srand to detect seed changes
module Kernel
  alias coop_original_srand srand

  def srand(seed = nil)
    result = coop_original_srand(seed)

    # Log ALL srand calls during coop battles (including from RNG sync)
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      caller_info = caller[0..2].map { |c| c.gsub(/.*Scripts\//, "") }.join(" <- ")
      role = CoopBattleState.am_i_initiator? ? "INIT" : "NON"
      RNGLog.write("[SRAND][#{role}] srand(#{seed.inspect}) prev=#{result} FROM: #{caller_info}") if defined?(RNGLog)
    end

    result
  end
end

# Wrap rand to log RNG calls
module Kernel
  alias coop_original_rand rand

  def rand(*args)
    result = coop_original_rand(*args)

    # Only log during coop battles
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      CoopRNGDebug.increment

      # Get detailed context
      turn = CoopRNGDebug.instance_variable_get(:@current_turn)
      phase = CoopRNGDebug.instance_variable_get(:@current_phase)
      call_num = CoopRNGDebug.instance_variable_get(:@rand_call_count)
      phase_call = CoopRNGDebug.phase_count
      role = CoopBattleState.am_i_initiator? ? "INIT" : "NON-INIT"

      # Get caller information
      caller_location = caller[0]
      short_location = "unknown"
      method_name = "unknown"

      if caller_location
        # Shorten file paths for readability
        short_location = caller_location.gsub(/.*Scripts\//, "")

        # Extract method name if possible
        if caller_location =~ /in `([^']+)'/
          method_name = $1
        elsif caller[1] =~ /in `([^']+)'/
          method_name = $1
        end
      end

      # Record to history
      CoopRNGDebug.record_call(args, result, short_location)

      # Compact logging format
      log_msg = "[T#{turn}][#{phase}][##{call_num}][#{role}] rand(#{args.inspect})=#{result} #{short_location}"
      RNGLog.write(log_msg) if defined?(RNGLog)
    end

    result
  end
end

# Also wrap pbRandom if it exists (Pokemon Essentials RNG method)
class PokeBattle_Battle
  alias coop_debug_pbRandom pbRandom if method_defined?(:pbRandom)

  def pbRandom(x)
    result = coop_debug_pbRandom(x)

    # Log pbRandom calls too (with re-entrancy guard)
    if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
      # Prevent infinite recursion from logging code calling RNG methods
      return result if CoopRNGDebug.instance_variable_get(:@logging_active)

      begin
        CoopRNGDebug.instance_variable_set(:@logging_active, true)

        CoopRNGDebug.increment  # CRITICAL: Increment counter for pbRandom too!

        turn = CoopRNGDebug.instance_variable_get(:@current_turn)
        phase = CoopRNGDebug.instance_variable_get(:@current_phase)
        call_num = CoopRNGDebug.instance_variable_get(:@rand_call_count)
        phase_call = CoopRNGDebug.phase_count
        role = CoopBattleState.am_i_initiator? ? "INIT" : "NON-INIT"

        caller_location = caller[0]
        short_location = caller_location ? caller_location.gsub(/.*Scripts\//, "") : "unknown"

        log_msg = "[T#{turn}][#{phase}][##{call_num}][#{role}] pbRandom(#{x})=#{result} #{short_location}"
        RNGLog.write(log_msg) if defined?(RNGLog)
      ensure
        CoopRNGDebug.instance_variable_set(:@logging_active, false)
      end
    end

    result
  end
end if defined?(PokeBattle_Battle)

##MultiplayerDebug.info("MODULE-16", "RNG debug module loaded (ENHANCED logging ENABLED)")
