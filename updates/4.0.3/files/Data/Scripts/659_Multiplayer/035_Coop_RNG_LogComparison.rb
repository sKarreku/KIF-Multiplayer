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
