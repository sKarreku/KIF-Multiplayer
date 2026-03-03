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
    result = seed.nil? ? coop_original_srand : coop_original_srand(seed)

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

#===============================================================================
# MODULE 17: RNG Log Comparison Utilities
#===============================================================================
# Utilities for comparing RNG call logs between initiator and non-initiator
# to identify where desyncs occur
#===============================================================================

module CoopRNGComparison
  #-----------------------------------------------------------------------------
  # Print a summary of RNG calls grouped by phase
  #-----------------------------------------------------------------------------
  def self.print_summary
    return unless defined?(CoopRNGDebug)

    history = CoopRNGDebug.export_history
    return if history.empty?

    role = defined?(CoopBattleState) && CoopBattleState.am_i_initiator? ? "INITIATOR" : "NON-INITIATOR"

    ##MultiplayerDebug.info("RNG-SUMMARY", "=" * 80)
    ##MultiplayerDebug.info("RNG-SUMMARY", "RNG CALL SUMMARY (#{role})")
    ##MultiplayerDebug.info("RNG-SUMMARY", "=" * 80)

    # Group by turn and phase
    by_turn = {}
    history.each do |call|
      turn = call[:turn]
      phase = call[:phase]
      by_turn[turn] ||= {}
      by_turn[turn][phase] ||= []
      by_turn[turn][phase] << call
    end

    # Print summary
    by_turn.each do |turn, phases|
      ##MultiplayerDebug.info("RNG-SUMMARY", "")
      ##MultiplayerDebug.info("RNG-SUMMARY", "Turn #{turn}:")

      phases.each do |phase, calls|
        ##MultiplayerDebug.info("RNG-SUMMARY", "  #{phase}: #{calls.length} calls")

        # Show first 3 and last 3 calls in this phase
        if calls.length <= 6
          calls.each do |c|
            ##MultiplayerDebug.info("RNG-SUMMARY", "    [#{c[:call_num]}] #{c[:args].inspect} = #{c[:result]} @ #{c[:caller]}")
          end
        else
          calls[0, 3].each do |c|
            ##MultiplayerDebug.info("RNG-SUMMARY", "    [#{c[:call_num]}] #{c[:args].inspect} = #{c[:result]} @ #{c[:caller]}")
          end
          ##MultiplayerDebug.info("RNG-SUMMARY", "    ... (#{calls.length - 6} more calls)")
          calls[-3..-1].each do |c|
            ##MultiplayerDebug.info("RNG-SUMMARY", "    [#{c[:call_num]}] #{c[:args].inspect} = #{c[:result]} @ #{c[:caller]}")
          end
        end
      end
    end

    ##MultiplayerDebug.info("RNG-SUMMARY", "")
    ##MultiplayerDebug.info("RNG-SUMMARY", "Total RNG calls: #{history.length}")
    ##MultiplayerDebug.info("RNG-SUMMARY", "=" * 80)
  end

  #-----------------------------------------------------------------------------
  # Generate a detailed RNG call report to file
  # This can be shared between players to compare
  #-----------------------------------------------------------------------------
  def self.export_to_file(filename = nil)
    return unless defined?(CoopRNGDebug)

    history = CoopRNGDebug.export_history
    return if history.empty?

    role = defined?(CoopBattleState) && CoopBattleState.am_i_initiator? ? "INITIATOR" : "NON-INITIATOR"
    filename ||= "rng_log_#{role}_#{Time.now.to_i}.txt"

    begin
      File.open(filename, "w") do |f|
        f.puts "=" * 80
        f.puts "RNG CALL LOG - #{role}"
        f.puts "Generated: #{Time.now}"
        f.puts "Total Calls: #{history.length}"
        f.puts "=" * 80
        f.puts ""

        history.each do |call|
          f.puts "[Call ##{call[:call_num]}][Turn #{call[:turn]}][Phase #{call[:phase]}][Phase Call ##{call[:phase_call_num]}]"
          f.puts "  rand(#{call[:args].inspect}) = #{call[:result]}"
          f.puts "  Caller: #{call[:caller]}"
          f.puts ""
        end
      end

      ##MultiplayerDebug.info("RNG-EXPORT", "RNG log exported to: #{filename}")
      puts "[RNG DEBUG] Log exported to: #{filename}"
      return filename
    rescue => e
      ##MultiplayerDebug.error("RNG-EXPORT", "Failed to export log: #{e.message}")
      return nil
    end
  end

  #-----------------------------------------------------------------------------
  # Manual comparison helper: Shows side-by-side view of two log files
  # Usage: Copy both players' log files, then call this method
  #-----------------------------------------------------------------------------
  def self.compare_files(file1, file2)
    begin
      lines1 = File.readlines(file1)
      lines2 = File.readlines(file2)

      puts "=" * 100
      puts "RNG LOG COMPARISON"
      puts "File 1: #{file1} (#{lines1.length} lines)"
      puts "File 2: #{file2} (#{lines2.length} lines)"
      puts "=" * 100
      puts ""

      # Find first divergence
      diverge_line = nil
      [lines1.length, lines2.length].min.times do |i|
        if lines1[i] != lines2[i]
          diverge_line = i
          break
        end
      end

      if diverge_line
        puts "FIRST DIVERGENCE AT LINE #{diverge_line + 1}:"
        puts ""
        puts "File 1:"
        puts lines1[[diverge_line - 2, 0].max .. [diverge_line + 2, lines1.length - 1].min].join
        puts ""
        puts "File 2:"
        puts lines2[[diverge_line - 2, 0].max .. [diverge_line + 2, lines2.length - 1].min].join
        puts ""
        puts "=" * 100
      else
        puts "NO DIVERGENCE FOUND - Logs are identical!"
        puts "=" * 100
      end

    rescue => e
      puts "Error comparing files: #{e.message}"
    end
  end

  #-----------------------------------------------------------------------------
  # Quick check: Compare RNG call counts at checkpoints
  # This can be called during battle to detect desyncs early
  #-----------------------------------------------------------------------------
  def self.verify_checkpoint_counts(checkpoint_name, expected_count)
    return unless defined?(CoopRNGDebug)

    actual_count = CoopRNGDebug.current_count
    role = defined?(CoopBattleState) && CoopBattleState.am_i_initiator? ? "INIT" : "NON-INIT"

    if actual_count == expected_count
      ##MultiplayerDebug.info("RNG-VERIFY", "[✓] Checkpoint '#{checkpoint_name}': #{actual_count} calls (MATCH) [#{role}]")
      return true
    else
      ##MultiplayerDebug.error("RNG-VERIFY", "[✗] Checkpoint '#{checkpoint_name}': Expected #{expected_count}, got #{actual_count} (DESYNC!) [#{role}]")
      ##MultiplayerDebug.error("RNG-VERIFY", ">>> DESYNC DETECTED AT: #{checkpoint_name}")

      # Print recent history
      history = CoopRNGDebug.export_history
      if history.length > 0
        ##MultiplayerDebug.error("RNG-VERIFY", "Last 10 RNG calls:")
        history[-10..-1].to_a.each do |call|
          ##MultiplayerDebug.error("RNG-VERIFY", "  [#{call[:call_num]}] #{call[:args].inspect} = #{call[:result]} @ #{call[:caller]}")
        end
      end

      return false
    end
  end
end

# Add a shortcut command for debugging
class PokeBattle_Battle
  def rng_summary
    CoopRNGComparison.print_summary
  end

  def rng_export
    filename = CoopRNGComparison.export_to_file
    pbMessage("RNG log exported to: #{filename}") if filename
  end
end if defined?(PokeBattle_Battle)

##MultiplayerDebug.info("MODULE-17", "RNG log comparison utilities loaded")
