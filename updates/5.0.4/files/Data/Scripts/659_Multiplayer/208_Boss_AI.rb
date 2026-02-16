#===============================================================================
# MODULE 9: Boss Pokemon System - Custom AI
#===============================================================================
# Smart boss AI with:
#   - Dynamic moveset: full learnset pool, picks best 4 each turn
#   - Threat tracking (who's dealing the most damage to the boss)
#   - Move memory (remembers ineffective move types per Pokemon)
#   - Target scoring (damage %, kill potential, setup punishment, spread balance)
#   - Move filtering (no setup, no healing, no protect, recharge/2turn penalized)
#   - Adapts to player behavior without setting up itself
#   - Full debug logging via MultiplayerDebug
#
# Dynamic Moveset (each turn):
#   POOL_PICK_SCORE = base_power/4                    (0-40)
#                   + stab_bonus                      (0 or 20)
#                   + super_effective_coverage         (0 or 30)
#                   + spread_bonus                     (0 or 15)
#                   - recharge_penalty                 (0 or 20)
#                   - two_turn_penalty                 (0 or 25)
#                   - accuracy_penalty                 (0 or 15)
#                   - memory_ineffective_all           (0 or 40)
#                   - type_redundancy                  (heavy, greedy dedup)
#
# Target Scoring (per move × target):
#   TARGET_SCORE = base_damage_pct                    (0-120)
#                + threat_ratio × 40                  (0-40)
#                + kill_bonus                         (0 or 50)
#                + setup_stages × 10                  (0-60)
#                - focus_penalty                      (0-30, ignored if can KO)
#                * memory_check                       (=> 2 if type was ineffective)
#
# Move Modifiers:
#   Recharge (Hyper Beam etc) × 0.3
#   Two-turn (Dig, Fly etc)   × 0.3
#   Self-targeting non-damaging  = 0 (setup, heal, protect)
#   Spread (AllNearFoes)        × 1.3
#
# Move Memory:
#   When a boss's damaging move has no effect on a target (ability immunity,
#   type immunity not caught by AI), it remembers the move TYPE per Pokemon
#   (personalID). Persists across switches. Two-turn charging turns excluded.
#
# Test: Encounter boss, observe move choices via MultiplayerDebug logs.
#===============================================================================

MultiplayerDebug.info("BOSS-AI", "Loading 208_Boss_AI.rb...") if defined?(MultiplayerDebug)

#===============================================================================
# Boss Threat Tracker - Records damage dealt by each battler to the boss
#===============================================================================
module BossThreatTracker
  @threat_data    = {}  # attacker_index => total_threat_points
  @target_history = {}  # target_index   => [turn1, turn2, ...]

  #-----------------------------------------------------------------------------
  # Record HP damage dealt to the boss
  #-----------------------------------------------------------------------------
  def self.record_damage(attacker_index, amount, turn)
    @threat_data[attacker_index] ||= 0
    @threat_data[attacker_index] += amount
    MultiplayerDebug.info("BOSS-THREAT", "Battler #{attacker_index} dealt #{amount} HP damage (total: #{@threat_data[attacker_index]})") if defined?(MultiplayerDebug)
  end

  #-----------------------------------------------------------------------------
  # Record shield hits (each shield broken = 50 threat points)
  #-----------------------------------------------------------------------------
  def self.record_shield_hit(attacker_index, shields_broken)
    @threat_data[attacker_index] ||= 0
    @threat_data[attacker_index] += shields_broken * 50
    MultiplayerDebug.info("BOSS-THREAT", "Battler #{attacker_index} broke #{shields_broken} shield(s) (total: #{@threat_data[attacker_index]})") if defined?(MultiplayerDebug)
  end

  #-----------------------------------------------------------------------------
  # Record which target the boss attacked (for spread balance)
  #-----------------------------------------------------------------------------
  def self.record_target(target_index, turn)
    @target_history[target_index] ||= []
    @target_history[target_index] << turn
    MultiplayerDebug.info("BOSS-THREAT", "Boss targeted battler #{target_index} on turn #{turn}") if defined?(MultiplayerDebug)
  end

  #-----------------------------------------------------------------------------
  # Get threat ratio for a specific attacker (0.0 to 1.0)
  #-----------------------------------------------------------------------------
  def self.get_threat_ratio(attacker_index)
    total = @threat_data.values.sum.to_f
    return 0.0 if total <= 0
    (@threat_data[attacker_index] || 0) / total
  end

  #-----------------------------------------------------------------------------
  # Get how many consecutive turns the boss hit the same target
  #-----------------------------------------------------------------------------
  def self.get_consecutive_hits(target_index, current_turn)
    history = @target_history[target_index] || []
    count = 0
    turn = current_turn - 1
    while history.include?(turn) && count < 3
      count += 1
      turn -= 1
    end
    count
  end

  #-----------------------------------------------------------------------------
  # Reset all tracking data (call on battle end)
  #-----------------------------------------------------------------------------
  def self.reset
    @threat_data    = {}
    @target_history = {}
    MultiplayerDebug.info("BOSS-THREAT", "Threat data reset") if defined?(MultiplayerDebug)
  end

  #-----------------------------------------------------------------------------
  # Debug: Print current threat summary
  #-----------------------------------------------------------------------------
  def self.debug_summary
    return unless defined?(MultiplayerDebug)
    total = @threat_data.values.sum.to_f
    @threat_data.each do |idx, pts|
      ratio = total > 0 ? (pts / total * 100).round(1) : 0
      MultiplayerDebug.info("BOSS-THREAT", "  Battler #{idx}: #{pts} pts (#{ratio}% of total)")
    end
    @target_history.each do |idx, turns|
      MultiplayerDebug.info("BOSS-THREAT", "  Target #{idx} hit on turns: #{turns.join(', ')}")
    end
  end
end

#===============================================================================
# Boss Move Memory - Tracks move types that had no effect on specific Pokemon
#===============================================================================
# When a boss's damaging move is completely ineffective against a target
# (ability immunity like Lightning Rod, Flash Fire, etc.), record the move type.
# The boss will avoid that move type against that Pokemon in future turns.
# Memory persists across switches (keyed by personalID).
# Two-turn charging turns are excluded (doing nothing on charge is expected).
#===============================================================================
module BossMoveMemory
  @memory = {}  # { "ownerID_personalID" => [:TYPE1, :TYPE2, ...] }

  #-----------------------------------------------------------------------------
  # Unique key per Pokemon: owner trainer ID + personalID
  # Ensures coop players' Pokemon with same personalID don't collide
  #-----------------------------------------------------------------------------
  def self.pokemon_key(pokemon)
    owner_id = pokemon.owner&.id rescue 0
    "#{owner_id}_#{pokemon.personalID}"
  end

  #-----------------------------------------------------------------------------
  # Record that a move type had no effect on a target Pokemon
  #-----------------------------------------------------------------------------
  def self.record_no_effect(target_pokemon, move_type)
    key = pokemon_key(target_pokemon)
    @memory[key] ||= []
    unless @memory[key].include?(move_type)
      @memory[key] << move_type
      MultiplayerDebug.info("BOSS-MEMORY", "Recorded: #{move_type} ineffective vs #{target_pokemon.speciesName} [#{key}]") if defined?(MultiplayerDebug)
    end
  end

  #-----------------------------------------------------------------------------
  # Check if a move type was previously ineffective against a target Pokemon
  #-----------------------------------------------------------------------------
  def self.was_ineffective?(target_pokemon, move_type)
    key = pokemon_key(target_pokemon)
    @memory[key]&.include?(move_type) || false
  end

  #-----------------------------------------------------------------------------
  # Check if a move type is ineffective vs ALL active foes (for pool scoring)
  #-----------------------------------------------------------------------------
  def self.ineffective_vs_all_foes?(move_type, battle, user_index)
    any_foe = false
    all_blocked = true
    battle.eachOtherSideBattler(user_index) do |t|
      next if t.fainted?
      any_foe = true
      unless was_ineffective?(t.pokemon, move_type)
        all_blocked = false
        break
      end
    end
    any_foe && all_blocked
  end

  #-----------------------------------------------------------------------------
  # Reset all memory (call on battle end)
  #-----------------------------------------------------------------------------
  def self.reset
    @memory = {}
    MultiplayerDebug.info("BOSS-MEMORY", "Move memory reset") if defined?(MultiplayerDebug)
  end

  #-----------------------------------------------------------------------------
  # Debug: Print current memory
  #-----------------------------------------------------------------------------
  def self.debug_summary
    return unless defined?(MultiplayerDebug)
    return if @memory.empty?
    @memory.each do |pid, types|
      MultiplayerDebug.info("BOSS-MEMORY", "  Pokemon ##{pid}: ineffective types = #{types.join(', ')}")
    end
  end
end

#===============================================================================
# Boss Move Pool - Build full learnset as battle-ready moves
#===============================================================================
class PokeBattle_Battler
  attr_accessor :boss_move_pool  # Array of PokeBattle_Move objects

  alias boss_ai_pool_pbInitialize pbInitialize

  def pbInitialize(pkmn, idxParty, batonPass = false)
    boss_ai_pool_pbInitialize(pkmn, idxParty, batonPass)
    return unless pkmn&.is_boss?
    build_boss_move_pool
  end

  def build_boss_move_pool
    @boss_move_pool = []
    move_ids = []

    # Level-up moves at or below current level
    @pokemon.getMoveList.each do |m|
      level, move_id = m[0], m[1]
      next if level > @level
      move_ids << move_id unless move_ids.include?(move_id)
    end

    # TM/Tutor moves
    species_data = GameData::Species.get(@pokemon.species)
    if species_data.respond_to?(:tutor_moves)
      species_data.tutor_moves.each do |mid|
        move_ids << mid unless move_ids.include?(mid)
      end
    end

    # Egg moves
    if species_data.respond_to?(:egg_moves)
      species_data.egg_moves.each do |mid|
        move_ids << mid unless move_ids.include?(mid)
      end
    end

    # BST-based BP cap for filtering
    bp_cap = @pokemon.boss_move_bp_cap

    # Create PokeBattle_Move objects from valid move IDs
    move_ids.each do |move_id|
      next unless GameData::Move.exists?(move_id)
      begin
        # Pre-filter: skip damaging moves that exceed BP cap
        move_data = GameData::Move.get(move_id)
        if (move_data.category == 0 || move_data.category == 1) && move_data.base_damage > bp_cap
          MultiplayerDebug.info("BOSS-AI", "  Pool filter: #{move_id} (BP:#{move_data.base_damage} > cap:#{bp_cap})") if defined?(MultiplayerDebug)
          next
        end

        pokemon_move = Pokemon::Move.new(move_id)
        battle_move = PokeBattle_Move.from_pokemon_move(@battle, pokemon_move)
        @boss_move_pool << battle_move
      rescue => e
        MultiplayerDebug.info("BOSS-AI", "  Pool skip: #{move_id} (#{e.message})") if defined?(MultiplayerDebug)
      end
    end

    MultiplayerDebug.info("BOSS-AI", "Built move pool: #{@boss_move_pool.length} moves for #{@pokemon.speciesName} (BP cap: #{bp_cap})") if defined?(MultiplayerDebug)
    if defined?(MultiplayerDebug)
      @boss_move_pool.each do |m|
        MultiplayerDebug.info("BOSS-AI", "  Pool: #{m.name} (#{m.type}, BP:#{m.baseDamage}, #{m.damagingMove? ? 'dmg' : 'status'})")
      end
    end
  end
end

#===============================================================================
# Threat Tracking Hook - Records damage dealt to bosses after each hit
#===============================================================================
class PokeBattle_Battler
  alias boss_ai_track_pbProcessMoveHit pbProcessMoveHit

  def pbProcessMoveHit(move, user, targets, hitNum, skipAccuracyCheck)
    # Snapshot boss state BEFORE the hit
    boss_snapshots = {}
    targets.each do |t|
      next unless t.pokemon&.is_boss?
      boss_snapshots[t.index] = {
        hp:      t.hp,
        shields: t.pokemon.boss_shields
      }
    end

    # Execute original hit processing
    result = boss_ai_track_pbProcessMoveHit(move, user, targets, hitNum, skipAccuracyCheck)

    # Record damage AFTER the hit (only on first hit to avoid double-counting multi-hit)
    if hitNum == 0
      boss_snapshots.each do |idx, before|
        target = @battle.battlers[idx]
        next unless target&.pokemon&.is_boss?

        hp_lost = before[:hp] - target.hp
        shields_lost = before[:shields] - target.pokemon.boss_shields

        if hp_lost > 0
          BossThreatTracker.record_damage(user.index, hp_lost, @battle.turnCount)
        end
        if shields_lost > 0
          BossThreatTracker.record_shield_hit(user.index, shields_lost)
        end
      end
    end

    #---------------------------------------------------------------------------
    # Boss Move Memory: detect when boss's own damaging move had no effect
    # Only on first hit (hitNum==0) to avoid duplicate recording for multi-hit
    # Excludes two-turn charging turns (doing nothing on charge is expected)
    #---------------------------------------------------------------------------
    if hitNum == 0 && user.is_boss? && move.damagingMove? && defined?(BossMoveMemory)
      # Check if this is a two-turn move's charging turn (skip recording)
      is_charging = move.respond_to?(:chargingTurnMove?) && move.chargingTurnMove? &&
                    user.effects[PBEffects::TwoTurnAttack] == move.id
      unless is_charging
        targets.each do |t|
          next if t.fainted?
          next unless t.pokemon
          # unaffected = type/ability immunity (NOT accuracy miss)
          if t.damageState.unaffected && !t.damageState.missed
            move_type = move.calcType || move.type
            BossMoveMemory.record_no_effect(t.pokemon, move_type)
          end
        end
      end
    end

    result
  end
end

#===============================================================================
# Battle End Cleanup - Reset threat tracking
#===============================================================================
class PokeBattle_Battle
  alias boss_ai_pbEndOfBattle pbEndOfBattle

  def pbEndOfBattle
    BossThreatTracker.reset
    BossMoveMemory.reset
    boss_ai_pbEndOfBattle
  end
end

#===============================================================================
# Boss AI - Custom Move Selection
#===============================================================================
class PokeBattle_AI

  # Recharge moves: boss loses a turn, devastating penalty
  BOSS_RECHARGE_FUNCTION = "0C2"

  # Protection function codes
  BOSS_PROTECT_FUNCTIONS = %w[0AA 0AB 14B 168 16A]

  #=============================================================================
  # Override: Intercept boss battlers for custom AI
  #=============================================================================
  alias boss_ai_pbDefaultChooseEnemyCommand pbDefaultChooseEnemyCommand

  def pbDefaultChooseEnemyCommand(idxBattler)
    user = @battle.battlers[idxBattler]
    if user&.is_boss?
      MultiplayerDebug.info("BOSS-AI", "=== Boss AI Decision (Turn #{@battle.turnCount}) ===") if defined?(MultiplayerDebug)
      BossThreatTracker.debug_summary
      BossMoveMemory.debug_summary
      boss_choose_move(idxBattler)
      return
    end
    boss_ai_pbDefaultChooseEnemyCommand(idxBattler)
  end

  #=============================================================================
  # Dynamic Moveset: Pick best 4 moves from pool each turn
  #=============================================================================
  def boss_refresh_moves(idxBattler)
    user = @battle.battlers[idxBattler]
    pool = user.boss_move_pool
    return unless pool && pool.length > 4

    # Don't refresh if Encored (must keep current moves for Encore to work)
    if user.effects[PBEffects::Encore] > 0
      MultiplayerDebug.info("BOSS-AI", "  [REFRESH] Skipped: Encored") if defined?(MultiplayerDebug)
      return
    end

    MultiplayerDebug.info("BOSS-AI", "  [REFRESH] Scoring #{pool.length} moves from pool...") if defined?(MultiplayerDebug)

    # Score each move in the pool for "pick priority"
    scored_pool = pool.map do |move|
      pick_score = boss_pool_pick_score(move, user)
      [move, pick_score]
    end

    # Greedy selection: pick top 4 while penalizing type redundancy
    selected = []
    selected_types = []

    4.times do
      # Apply redundancy penalty to remaining moves
      scored_pool.each do |entry|
        move, base = entry[0], entry[1]
        if move.damagingMove? && selected_types.include?(move.type)
          entry[1] = [base * 0.4, base - 30].min  # Heavy penalty for same-type
        end
      end

      # Sort by score descending and pick best
      scored_pool.sort_by! { |e| -e[1] }
      best = scored_pool.shift
      break unless best && best[1] > -50

      selected << best[0]
      selected_types << best[0].type if best[0].damagingMove?
    end

    # Assign to battler's move slots
    if selected.length > 0
      selected.each_with_index { |move, i| user.moves[i] = move }
      # Trim excess if somehow more than 4
      user.moves.slice!(4..-1) if user.moves.length > 4

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("BOSS-AI", "  [REFRESH] Selected moves:")
        selected.each_with_index do |m, i|
          MultiplayerDebug.info("BOSS-AI", "    Slot #{i}: #{m.name} (#{m.type}, BP:#{m.baseDamage})")
        end
      end
    end
  end

  #=============================================================================
  # Pool Pick Score: How valuable is this move for the current battle state?
  #=============================================================================
  def boss_pool_pick_score(move, user)
    score = 0

    # Self-KO moves: never pick (Self-Destruct, Explosion, Memento, etc.)
    if BossConfig.boss_banned_move?(move.id)
      return -100
    end

    # BST-based BP cap: skip damaging moves that exceed the cap
    bp_cap = user.boss_move_bp_cap
    if move.damagingMove? && move.baseDamage > bp_cap
      MultiplayerDebug.info("BOSS-AI", "    Pool: #{move.name} (BP:#{move.baseDamage}) exceeds BP cap #{bp_cap}") if defined?(MultiplayerDebug)
      return -100
    end

    # Sleep-dependent moves (Dream Eater, Nightmare): only pick if a foe is asleep
    if boss_requires_sleeping_target?(move)
      has_sleeping = false
      @battle.eachOtherSideBattler(user.index) do |t|
        next if t.fainted?
        has_sleeping = true if t.status == :SLEEP
      end
      unless has_sleeping
        MultiplayerDebug.info("BOSS-AI", "    Pool: #{move.name} requires sleeping target - no valid targets") if defined?(MultiplayerDebug)
        return -100
      end
    end

    # Non-damaging self-targeting: never pick (setup, heal, protect)
    if !move.damagingMove?
      target_data = move.pbTarget(user)
      if target_data.id == :User
        return -100
      end
      # Ally-targeting: never pick
      if [:NearAlly, :UserOrNearAlly, :AllAllies, :UserAndAllies].include?(target_data.id)
        return -100
      end
      # Protection: never pick
      if BOSS_PROTECT_FUNCTIONS.include?(move.function)
        return -100
      end
      # Status/utility moves targeting foes: low priority in pool pick
      # Boss should heavily prefer damaging moves; at most 1 status move per refresh
      score += 15
      return score
    end

    # --- Damaging moves below ---

    # Base power contribution (0-40)
    score += [move.baseDamage / 4, 40].min

    # STAB bonus (+20)
    if user.pbHasType?(move.type)
      score += 20
    end

    # Coverage: super effective against any player Pokemon (+30)
    @battle.eachOtherSideBattler(user.index) do |target|
      next if target.fainted?
      # Use AI type calc for accuracy
      type_mod = pbCalcTypeMod(move.type, user, target)
      if Effectiveness.super_effective?(type_mod)
        score += 30
        MultiplayerDebug.info("BOSS-AI", "    Pool: #{move.name} is SE vs #{target.name}") if defined?(MultiplayerDebug)
        break
      end
    end

    # Spread move bonus (+15)
    target_data = move.pbTarget(user)
    if boss_is_spread_move?(target_data)
      score += 15
    end

    # Move Memory: if this type was ineffective vs ALL active foes, heavy penalty
    if defined?(BossMoveMemory) && BossMoveMemory.ineffective_vs_all_foes?(move.type, @battle, user.index)
      score -= 40
      MultiplayerDebug.info("BOSS-AI", "    Pool: #{move.name} (#{move.type}) ineffective vs all foes (-40)") if defined?(MultiplayerDebug)
    end

    # Recharge penalty (-20)
    if move.function == BOSS_RECHARGE_FUNCTION
      score -= 20
    end

    # Two-turn move penalty (-25) — boss wastes a turn charging
    if move.respond_to?(:chargingTurnMove?) && move.chargingTurnMove?
      score -= 25
      MultiplayerDebug.info("BOSS-AI", "    Pool: #{move.name} is two-turn move (-25)") if defined?(MultiplayerDebug)
    end

    # Accuracy penalty for low-accuracy moves
    if move.accuracy > 0 && move.accuracy < 80
      score -= 15
    end

    score
  end

  #=============================================================================
  # Boss Move Selection - Score every move × target, pick the best
  #=============================================================================
  def boss_choose_move(idxBattler)
    user = @battle.battlers[idxBattler]

    # Refresh moveset from pool each turn (adaptive coverage)
    boss_refresh_moves(idxBattler)

    # Gather all valid move × target combinations with scores
    choices = []  # [move_index, score, target_index, debug_info]

    user.eachMoveWithIndex do |move, i|
      next unless @battle.pbCanChooseMove?(idxBattler, i, false)

      # Get move modifier (0 = blocked, 0.3 = penalized, 1.0 = normal, 1.3 = bonus)
      move_mod = boss_move_modifier(move, user)
      if move_mod <= 0
        MultiplayerDebug.info("BOSS-AI", "  [BLOCKED] #{move.name} (modifier=0)") if defined?(MultiplayerDebug)
        next
      end

      target_data = move.pbTarget(user)

      if boss_is_spread_move?(target_data)
        #-----------------------------------------------------------------------
        # Spread move: sum scores across all foe targets
        #-----------------------------------------------------------------------
        total_score = 0
        debug_parts = []
        @battle.eachOtherSideBattler(idxBattler) do |target|
          next if target.fainted?
          t_score = boss_calc_target_score(move, user, target)
          total_score += t_score
          debug_parts << "#{target.name}=#{t_score}"
        end
        total_score = (total_score * move_mod).to_i
        debug_info = "#{move.name} (spread×#{move_mod}): #{debug_parts.join(' + ')} = #{total_score}"
        choices << [i, total_score, -1, debug_info]
        MultiplayerDebug.info("BOSS-AI", "  #{debug_info}") if defined?(MultiplayerDebug)

      elsif boss_targets_foe?(target_data)
        #-----------------------------------------------------------------------
        # Single-target foe move: score against each foe, pick best
        #-----------------------------------------------------------------------
        @battle.eachOtherSideBattler(idxBattler) do |target|
          next if target.fainted?
          t_score = boss_calc_target_score(move, user, target)
          final_score = (t_score * move_mod).to_i
          debug_info = "#{move.name} vs #{target.name} (×#{move_mod}): #{final_score}"
          choices << [i, final_score, target.index, debug_info]
          MultiplayerDebug.info("BOSS-AI", "  #{debug_info}") if defined?(MultiplayerDebug)
        end

      else
        #-----------------------------------------------------------------------
        # Field/side move (hazards, weather, terrain): flat score
        #-----------------------------------------------------------------------
        score = boss_score_field_move(move, user)
        score = (score * move_mod).to_i
        debug_info = "#{move.name} (field): #{score}"
        choices << [i, score, -1, debug_info]
        MultiplayerDebug.info("BOSS-AI", "  #{debug_info}") if defined?(MultiplayerDebug)
      end
    end

    #---------------------------------------------------------------------------
    # Pick the best choice (deterministic - boss always picks optimal)
    #---------------------------------------------------------------------------
    if choices.empty?
      MultiplayerDebug.info("BOSS-AI", "  No valid moves! Using Struggle.") if defined?(MultiplayerDebug)
      @battle.pbAutoChooseMove(idxBattler)
      return
    end

    choices.sort_by! { |c| -c[1] }
    best = choices[0]

    # Small randomness: if top 2 moves are within 10% of each other, pick randomly
    if choices.length > 1 && choices[1][1] >= best[1] * 0.9
      top_choices = choices.select { |c| c[1] >= best[1] * 0.9 }
      best = top_choices[rand(top_choices.length)]
      MultiplayerDebug.info("BOSS-AI", "  Multiple good choices (#{top_choices.length}), randomized.") if defined?(MultiplayerDebug)
    end

    MultiplayerDebug.info("BOSS-AI", "  >>> CHOSEN: #{best[3]}") if defined?(MultiplayerDebug)

    @battle.pbRegisterMove(idxBattler, best[0], false)
    @battle.pbRegisterTarget(idxBattler, best[2]) if best[2] >= 0

    # Record targeting for spread balance
    BossThreatTracker.record_target(best[2], @battle.turnCount) if best[2] >= 0
  end

  #=============================================================================
  # THE FORMULA: Score a move against a specific target
  #=============================================================================
  def boss_calc_target_score(move, user, target)
    score = 0
    dmg_pct = 0
    kill_bonus = 0
    threat_bonus = 0
    setup_bonus = 0
    focus_penalty = 0

    #---------------------------------------------------------------------------
    # 0. Sleep-dependent moves: worthless against non-sleeping targets
    #---------------------------------------------------------------------------
    if boss_requires_sleeping_target?(move) && target.status != :SLEEP
      MultiplayerDebug.info("BOSS-AI", "    [#{target.name}] #{move.name} requires sleep - target not asleep => 1") if defined?(MultiplayerDebug)
      return 1
    end

    #---------------------------------------------------------------------------
    # 0b. Move Memory: if this move type previously had no effect, nearly worthless
    #---------------------------------------------------------------------------
    if move.damagingMove? && defined?(BossMoveMemory)
      if BossMoveMemory.was_ineffective?(target.pokemon, move.calcType || move.type)
        MultiplayerDebug.info("BOSS-AI", "    [#{target.name}] #{move.name} (#{move.type}) remembered as ineffective => 2") if defined?(MultiplayerDebug)
        return 2
      end
    end

    #---------------------------------------------------------------------------
    # 1. Base Damage Percentage (0-120 for damaging, 0-80 for status)
    #---------------------------------------------------------------------------
    if move.damagingMove?
      dmg_pct = boss_estimate_damage_pct(move, user, target)
      score += dmg_pct

      # 2. Kill Bonus (+50 if can KO this target)
      if dmg_pct >= 100
        kill_bonus = 50
        score += kill_bonus
      end
    else
      # Status move score based on utility
      status_score = boss_score_status_move(move, user, target)
      score += status_score
    end

    #---------------------------------------------------------------------------
    # 3. Threat Bonus (0-40): Prioritize the player dealing the most damage
    #---------------------------------------------------------------------------
    threat_ratio = BossThreatTracker.get_threat_ratio(target.index)
    threat_bonus = (threat_ratio * 40).to_i
    score += threat_bonus

    #---------------------------------------------------------------------------
    # 4. Setup Punishment (0-60): Punish targets boosting offensive stats
    #---------------------------------------------------------------------------
    setup_stages = boss_count_setup_stages(target)
    setup_bonus = [setup_stages * 10, 60].min
    score += setup_bonus

    #---------------------------------------------------------------------------
    # 5. Focus Penalty (0-30): Spread damage, unless going for the kill
    #---------------------------------------------------------------------------
    if kill_bonus == 0
      consecutive = BossThreatTracker.get_consecutive_hits(target.index, @battle.turnCount)
      focus_penalty = [consecutive * 15, 30].min
      score -= focus_penalty
    end

    final_score = [score, 1].max

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("BOSS-AI", "    [#{target.name}] dmg=#{dmg_pct} kill=#{kill_bonus} threat=#{threat_bonus} setup=#{setup_bonus} focus=-#{focus_penalty} => #{final_score}")
    end

    final_score
  end

  #=============================================================================
  # Estimate damage as % of target's current HP
  #=============================================================================
  def boss_estimate_damage_pct(move, user, target)
    # Check immunity first
    return 0 if pbCheckMoveImmunity(100, move, user, target, PBTrainerAI.bestSkill)

    # Use existing AI damage estimation at max skill
    baseDmg = pbMoveBaseDamage(move, user, target, PBTrainerAI.bestSkill)
    realDmg = pbRoughDamage(move, user, target, PBTrainerAI.bestSkill, baseDmg)

    # Factor in accuracy
    accuracy = pbRoughAccuracy(move, user, target, PBTrainerAI.bestSkill)
    realDmg = (realDmg * accuracy / 100.0).to_i

    # Convert to percentage of target's remaining HP
    pct = target.hp > 0 ? (realDmg * 100.0 / target.hp).to_i : 0
    [pct, 120].min  # Cap at 120%
  end

  #=============================================================================
  # Score non-damaging moves that target a foe
  #=============================================================================
  def boss_score_status_move(move, user, target)
    score = 0

    # Status condition moves: great if target has no status
    if target.status == :NONE
      # Check if move can inflict a real status condition (common function codes)
      status_funcs = %w[
        006 007 00A 00B 00C 00D 00E 00F
        068 069 06D 06E 06F 070 071 072
      ]
      if status_funcs.include?(move.function)
        score = 60
        MultiplayerDebug.info("BOSS-AI", "    [STATUS] #{move.name} can inflict status on #{target.name} (no current status)") if defined?(MultiplayerDebug)
      else
        score = 20  # Stat debuffs (String Shot, Growl, etc.) - low priority
        MultiplayerDebug.info("BOSS-AI", "    [STATUS] #{move.name} is a utility/debuff move (low priority)") if defined?(MultiplayerDebug)
      end
    else
      score = 5  # Target already has a status, much less useful
      MultiplayerDebug.info("BOSS-AI", "    [STATUS] #{target.name} already statused, low priority") if defined?(MultiplayerDebug)
    end

    # Bonus for targeting a setup sweeper with disruption (Taunt, Encore, etc.)
    if boss_count_setup_stages(target) > 0
      score += 15
    end

    score
  end

  #=============================================================================
  # Score field/side moves (entry hazards, weather, terrain, screens)
  #=============================================================================
  def boss_score_field_move(move, user)
    score = 30  # Base score for field moves

    # Entry hazards: check if already set
    case move.function
    when "103"  # Spikes
      layers = user.pbOpposingSide.effects[PBEffects::Spikes] rescue 0
      score = layers < 3 ? 50 : 0
    when "104"  # Toxic Spikes
      layers = user.pbOpposingSide.effects[PBEffects::ToxicSpikes] rescue 0
      score = layers < 2 ? 50 : 0
    when "105"  # Stealth Rock
      has_rocks = user.pbOpposingSide.effects[PBEffects::StealthRock] rescue false
      score = has_rocks ? 0 : 60
    when "106"  # Sticky Web
      has_web = user.pbOpposingSide.effects[PBEffects::StickyWeb] rescue false
      score = has_web ? 0 : 50
    end

    MultiplayerDebug.info("BOSS-AI", "    [FIELD] #{move.name}: score=#{score}") if defined?(MultiplayerDebug)
    score
  end

  #=============================================================================
  # Move Modifier: Filter out bad moves, penalize risky ones, bonus spread
  #=============================================================================
  def boss_move_modifier(move, user)
    func = move.function

    #---------------------------------------------------------------------------
    # Self-KO moves: blocked (boss should never kill itself)
    #---------------------------------------------------------------------------
    if BossConfig.boss_banned_move?(move.id)
      MultiplayerDebug.info("BOSS-AI", "    [MOD] #{move.name}: self-KO move (×0)") if defined?(MultiplayerDebug)
      return 0
    end

    #---------------------------------------------------------------------------
    # Recharge moves (Hyper Beam, Giga Impact): heavily penalized
    # Boss can't afford to lose a turn recharging
    #---------------------------------------------------------------------------
    if func == BOSS_RECHARGE_FUNCTION
      MultiplayerDebug.info("BOSS-AI", "    [MOD] #{move.name}: recharge move (×0.3)") if defined?(MultiplayerDebug)
      return 0.3
    end

    #---------------------------------------------------------------------------
    # Two-turn moves (Dig, Fly, Solar Beam, etc.): heavily penalized
    # Boss wastes a turn charging — same penalty as recharge moves
    #---------------------------------------------------------------------------
    if move.respond_to?(:chargingTurnMove?) && move.chargingTurnMove?
      MultiplayerDebug.info("BOSS-AI", "    [MOD] #{move.name}: two-turn move (×0.3)") if defined?(MultiplayerDebug)
      return 0.3
    end

    #---------------------------------------------------------------------------
    # Protection moves: blocked (boss shouldn't stall)
    #---------------------------------------------------------------------------
    if BOSS_PROTECT_FUNCTIONS.include?(func)
      MultiplayerDebug.info("BOSS-AI", "    [MOD] #{move.name}: protection move (×0)") if defined?(MultiplayerDebug)
      return 0
    end

    #---------------------------------------------------------------------------
    # Non-damaging self-targeting moves: blocked
    # Catches ALL of: setup, healing, protection, self-buffs
    # Boss adapts through attacks and status, never sets up
    #---------------------------------------------------------------------------
    if !move.damagingMove?
      target_data = move.pbTarget(user)
      if target_data.id == :User
        MultiplayerDebug.info("BOSS-AI", "    [MOD] #{move.name}: self-targeting status move (×0)") if defined?(MultiplayerDebug)
        return 0
      end
      # Also block ally-targeting moves (boss has no allies worth buffing)
      if [:NearAlly, :UserOrNearAlly, :AllAllies, :UserAndAllies, :UserOrNearAlly].include?(target_data.id)
        MultiplayerDebug.info("BOSS-AI", "    [MOD] #{move.name}: ally-targeting move (×0)") if defined?(MultiplayerDebug)
        return 0
      end
    end

    #---------------------------------------------------------------------------
    # Spread moves in multi-battle: bonus for hitting multiple targets
    # Only damaging spread moves get the bonus (status moves like String Shot don't)
    #---------------------------------------------------------------------------
    if move.damagingMove? && boss_is_spread_move?(move.pbTarget(user))
      MultiplayerDebug.info("BOSS-AI", "    [MOD] #{move.name}: spread damaging move (×1.3)") if defined?(MultiplayerDebug)
      return 1.3
    end

    1.0  # Default: no modification
  end

  #=============================================================================
  # Helper: Count target's positive offensive stat stages (ATK + SPATK + SPD)
  #=============================================================================
  def boss_count_setup_stages(target)
    stages = 0
    stages += target.stages[:ATTACK] if target.stages[:ATTACK] > 0
    stages += target.stages[:SPECIAL_ATTACK] if target.stages[:SPECIAL_ATTACK] > 0
    stages += target.stages[:SPEED] if target.stages[:SPEED] > 0
    stages
  end

  #=============================================================================
  # Helper: Check if a move targets all foes (spread)
  #=============================================================================
  def boss_is_spread_move?(target_data)
    [:AllNearFoes, :AllFoes, :AllNearOthers, :AllBattlers].include?(target_data.id)
  end

  #=============================================================================
  # Helper: Check if a move targets a single foe
  #=============================================================================
  def boss_targets_foe?(target_data)
    [:NearFoe, :Foe, :RandomNearFoe, :NearOther, :Other].include?(target_data.id)
  end

  #=============================================================================
  # Helper: Check if a move requires the target to be asleep
  # Dream Eater (10C), Nightmare (0BE)
  #=============================================================================
  BOSS_SLEEP_REQUIRED_FUNCTIONS = %w[10C 0BE]

  def boss_requires_sleeping_target?(move)
    BOSS_SLEEP_REQUIRED_FUNCTIONS.include?(move.function)
  end
end

MultiplayerDebug.info("BOSS-AI", "Boss AI system loaded") if defined?(MultiplayerDebug)
