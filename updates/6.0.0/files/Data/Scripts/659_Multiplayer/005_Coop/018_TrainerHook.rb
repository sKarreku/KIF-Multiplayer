#===============================================================================
# MODULE: Coop Trainer Battle Hook
#===============================================================================
# Enables squad members to join trainer battles with wait screen synchronization
# - Initiator broadcasts sync wait when talking to trainer
# - Non-initiators detect sync wait and join automatically
# - Wait screen appears AFTER dialogue, RIGHT before battle
# - Battle uses initiator's trainer data (for Remix mode)
# - Each client's event script awards badges naturally (no progression sync needed)
#===============================================================================

##MultiplayerDebug.info("COOP-TRAINER", "Loading trainer battle hook...")

# Store active sync wait globally (accessed by alias)
$active_trainer_sync_wait_data = nil
$trainer_battle_wait_screen_active = false

#===============================================================================
# Alias pbTrainerBattle to add sync wait logic
#===============================================================================
module OverworldBattleAliases
  # Save original method
  class << self
    alias coop_trainer_original_pbTrainerBattle pbTrainerBattle
  end
end

#===============================================================================
# Aliased pbTrainerBattle - intercepts BEFORE battle starts
#===============================================================================
def pbTrainerBattle(
  trainerID, trainerName, endSpeech=nil,
  doubleBattle=false, trainerPartyID=0, canLose=false, outcomeVar=1,
  name_override=nil, trainer_type_override=nil
)

  ##MultiplayerDebug.info("COOP-TRAINER-HOOK", "pbTrainerBattle intercepted: #{trainerName}")

  # Check if in squad
  in_squad = defined?(MultiplayerClient) &&
             MultiplayerClient.instance_variable_get(:@connected) &&
             MultiplayerClient.in_squad?

  # Get current event context
  current_map_id = $game_map.map_id rescue nil
  current_event_id = get_current_event_id rescue nil

  ##MultiplayerDebug.info("COOP-TRAINER-HOOK", "In squad: #{in_squad}, Map: #{current_map_id}, Event: #{current_event_id}")

  # === NON-INITIATOR: Check if active sync wait exists for this trainer ===
  if in_squad && current_map_id && current_event_id
    sync_wait = MultiplayerClient.active_trainer_sync_wait

    if sync_wait &&
       sync_wait[:map_id] == current_map_id &&
       sync_wait[:event_id] == current_event_id &&
       (Time.now - sync_wait[:timestamp]) < 120  # Within 120 second window

      # Check if this battle was cancelled (initiator started solo)
      if MultiplayerClient.is_battle_cancelled?(sync_wait[:battle_id])
        ##MultiplayerDebug.info("COOP-TRAINER-HOOK", "Battle #{sync_wait[:battle_id]} was cancelled by initiator")
        MultiplayerClient.clear_trainer_sync_wait
        # Fall through to become new initiator
      else
        ##MultiplayerDebug.info("COOP-TRAINER-HOOK", "JOINING existing sync wait: #{sync_wait[:battle_id]}")

        # Send joined message + push party data immediately
        my_sid = MultiplayerClient.session_id
        MultiplayerClient.send_data("COOP_TRAINER_JOINED:#{sync_wait[:battle_id]}|#{my_sid}")

        # CRITICAL: Push party data immediately when joining (like wild battles)
        MultiplayerClient.coop_push_party_now! if MultiplayerClient.respond_to?(:coop_push_party_now!)
        ##MultiplayerDebug.info("COOP-TRAINER-HOOK", "Pushed party data immediately on join")

        # Decode trainer from sync wait (using TrainerSerializer - JSON-based)
        trainer = nil
        begin
          if defined?(TrainerSerializer)
            trainer = TrainerSerializer.from_hex(sync_wait[:trainer_hex])
          end
        rescue => e
          ##MultiplayerDebug.error("COOP-TRAINER-HOOK", "Failed to decode trainer: #{e.message}")
        end

        # Show wait screen
        show_trainer_wait_screen_as_joiner(sync_wait[:battle_id], trainer)

        # Start coop battle with initiator's trainer data
        return start_coop_trainer_battle_as_joiner(sync_wait, trainerID, trainerName, endSpeech, canLose, outcomeVar)
      end
    end
  end

  # === INITIATOR: If in squad, broadcast sync wait ===
  if in_squad
    ##MultiplayerDebug.info("COOP-TRAINER-HOOK", "INITIATING sync wait as battle initiator")

    # Generate battle ID
    battle_id = CoopBattleState.generate_battle_id

    # Load trainer data (initiator's version for Remix mode)
    trainer = pbLoadTrainer(trainerID, trainerName, trainerPartyID)

    # Serialize using TrainerSerializer (JSON-based, no Marshal)
    trainer_hex = ""
    if defined?(TrainerSerializer)
      trainer_hex = TrainerSerializer.to_hex(trainer)
    end

    if trainer_hex.empty?
      ##MultiplayerDebug.error("COOP-TRAINER-HOOK", "Failed to encode trainer data!")
      # Fallback to solo battle
      MultiplayerClient.clear_trainer_sync_wait
      return OverworldBattleAliases.coop_trainer_original_pbTrainerBattle(
        trainerID, trainerName, endSpeech, doubleBattle, trainerPartyID, canLose, outcomeVar, name_override, trainer_type_override
      )
    end

    ##MultiplayerDebug.info("COOP-TRAINER-HOOK", "Encoded trainer data: #{trainer_hex.length} chars")

    # Broadcast sync wait announcement
    MultiplayerClient.send_data("COOP_TRAINER_SYNC_WAIT:#{battle_id}|#{trainer_hex}|#{current_map_id}|#{current_event_id}")

    # Show wait screen (120 sec timeout)
    allies_joined = show_trainer_wait_screen_as_initiator(battle_id, trainer)

    # After wait screen closes
    if allies_joined.empty?
      # Solo battle (timeout or ACTION pressed)
      ##MultiplayerDebug.info("COOP-TRAINER-HOOK", "No allies joined, starting solo battle")

      # CRITICAL: Broadcast cancellation so other players don't try to join
      MultiplayerClient.send_data("COOP_TRAINER_CANCELLED:#{battle_id}")
      ##MultiplayerDebug.info("COOP-TRAINER-HOOK", "Sent COOP_TRAINER_CANCELLED to notify squad")

      MultiplayerClient.clear_trainer_sync_wait
      return OverworldBattleAliases.coop_trainer_original_pbTrainerBattle(
        trainerID, trainerName, endSpeech, doubleBattle, trainerPartyID, canLose, outcomeVar, name_override, trainer_type_override
      )
    else
      # Coop battle (2v1 or 3v1)
      ##MultiplayerDebug.info("COOP-TRAINER-HOOK", "Starting coop battle with #{allies_joined.length} allies")

      # CRITICAL: Push initiator party first (like wild battles line 642)
      begin
        MultiplayerClient.coop_push_party_now! if MultiplayerClient.respond_to?(:coop_push_party_now!)
        ##MultiplayerDebug.info("COOP-TRAINER-HOOK", "Initiator pushed own party")
      rescue => e
        ##MultiplayerDebug.warn("COOP-TRAINER-HOOK", "Initiator party push failed: #{e.message}")
      end

      # CRITICAL: Broadcast battle start signal so joiners exit wait screens
      MultiplayerClient.send_data("COOP_TRAINER_START_BATTLE:#{battle_id}")
      ##MultiplayerDebug.info("COOP-TRAINER-HOOK", "Sent COOP_TRAINER_START_BATTLE to #{allies_joined.length} allies")

      # Wait for party data (joiners pushed on join, initiator just pushed above)
      sleep(0.3)
      ##MultiplayerDebug.info("COOP-TRAINER-HOOK", "Waiting for party data sync")

      # Wait for fresh party data to arrive (500ms = ~30 frames at 60 FPS)
      wait_frames = 30
      wait_start_time = Time.now
      early_exit = false

      # DEBUG: Log what we're waiting for
      ##MultiplayerDebug.info("COOP-TRAINER-HOOK", "Waiting for party from SIDs: #{allies_joined.inspect}")

      wait_frames.times do |frame|
        Graphics.update if defined?(Graphics)
        Input.update if defined?(Input)
        sleep(0.016)  # ~16ms per frame

        # Check if all parties are ready (early exit)
        all_ready = allies_joined.all? do |sid|
          # CRITICAL: allies_joined now contains full SID strings (e.g., "SID2")
          party = MultiplayerClient.remote_party(sid) rescue []
          ##MultiplayerDebug.info("COOP-TRAINER-HOOK-DEBUG", "Frame #{frame}: sid=#{sid.inspect} party=#{party ? party.length : 'nil'}") if frame % 10 == 0
          party && !party.empty?
        end

        if all_ready
          actual_wait_ms = ((Time.now - wait_start_time) * 1000).round
          ##MultiplayerDebug.info("COOP-TRAINER-HOOK", "All #{allies_joined.length} party snapshots ready in #{actual_wait_ms}ms")
          early_exit = true
          break
        end

        # Log snapshot status every 30 frames (500ms)
        if frame % 30 == 0
          ready_count = allies_joined.count do |sid|
            # allies_joined now contains full SID strings (e.g., "SID2")
            party = MultiplayerClient.remote_party(sid) rescue []
            party && !party.empty?
          end
          elapsed_ms = ((Time.now - wait_start_time) * 1000).round
          ##MultiplayerDebug.info("COOP-TRAINER-HOOK", "Party sync: #{ready_count}/#{allies_joined.length} ready, #{elapsed_ms}ms elapsed")
        end
      end

      unless early_exit
        actual_wait_ms = ((Time.now - wait_start_time) * 1000).round
        ##MultiplayerDebug.warn("COOP-TRAINER-HOOK", "Party sync timeout after #{actual_wait_ms}ms")
      end

      # Start coop battle
      return start_coop_trainer_battle_as_initiator(battle_id, allies_joined, trainer, trainerName, endSpeech, canLose, outcomeVar)
    end
  end

  # === SOLO (not in squad): Normal vanilla battle ===
  ##MultiplayerDebug.info("COOP-TRAINER-HOOK", "Solo player, starting vanilla battle")
  return OverworldBattleAliases.coop_trainer_original_pbTrainerBattle(
    trainerID, trainerName, endSpeech, doubleBattle, trainerPartyID, canLose, outcomeVar, name_override, trainer_type_override
  )
end

#===============================================================================
# Wait Screen for Initiator
#===============================================================================
def show_trainer_wait_screen_as_initiator(battle_id, trainer)
  ##MultiplayerDebug.info("COOP-TRAINER-WAIT", "Showing initiator wait screen for #{battle_id}")

  $trainer_battle_wait_screen_active = true
  start_time = Time.now
  timeout = 120

  # Create custom wait screen
  wait_screen = CoopTrainerWaitScreen.new(battle_id, trainer, true)

  # Wait loop
  loop do
    wait_screen.update

    # Check for ACTION press (start battle)
    if Input.trigger?(Input::ACTION)
      ##MultiplayerDebug.info("COOP-TRAINER-WAIT", "ACTION pressed, starting battle now")
      break
    end

    # Check for max allies (2)
    allies_joined = MultiplayerClient.trainer_battle_allies(battle_id) rescue []
    if allies_joined.length >= 2
      ##MultiplayerDebug.info("COOP-TRAINER-WAIT", "Max allies reached")
      break
    end

    # Check for timeout
    if Time.now - start_time > timeout
      ##MultiplayerDebug.info("COOP-TRAINER-WAIT", "Timeout reached")
      break
    end

    # Update display
    wait_screen.update_display

    sleep(0.05)
  end

  # Get final ally list
  allies_joined = MultiplayerClient.trainer_battle_allies(battle_id) rescue []

  # Cleanup
  wait_screen.dispose

  $trainer_battle_wait_screen_active = false
  ##MultiplayerDebug.info("COOP-TRAINER-WAIT", "Wait screen closed, #{allies_joined.length} allies joined")

  return allies_joined
end

#===============================================================================
# Wait Screen for Joiner
#===============================================================================
def show_trainer_wait_screen_as_joiner(battle_id, trainer)
  ##MultiplayerDebug.info("COOP-TRAINER-WAIT", "Showing joiner wait screen for #{battle_id}")

  $trainer_battle_wait_screen_active = true
  start_time = Time.now
  timeout = 120

  # Create custom wait screen
  wait_screen = CoopTrainerWaitScreen.new(battle_id, trainer, false)

  # Wait for battle start signal
  loop do
    wait_screen.update

    # Check for ACTION press (toggle ready)
    if Input.trigger?(Input::ACTION)
      wait_screen.toggle_ready
    end

    # Check for start signal
    signal = MultiplayerClient.trainer_battle_start_signal
    if signal && signal[:battle_id] == battle_id
      ##MultiplayerDebug.info("COOP-TRAINER-WAIT", "Battle start signal received!")
      MultiplayerClient.clear_trainer_battle_start_signal
      break
    end

    # Check for timeout
    if Time.now - start_time > timeout
      ##MultiplayerDebug.warn("COOP-TRAINER-WAIT", "Joiner wait timeout!")
      break
    end

    # Update display
    wait_screen.update_display

    sleep(0.05)
  end

  # Cleanup
  wait_screen.dispose

  $trainer_battle_wait_screen_active = false
end

#===============================================================================
# Start Coop Trainer Battle as Initiator
#===============================================================================
def start_coop_trainer_battle_as_initiator(battle_id, ally_sids, trainer, trainer_name, end_speech, can_lose, outcome_var)
  ##MultiplayerDebug.info("COOP-TRAINER-BATTLE", "Starting coop battle as initiator: #{battle_id}")

  # Create battle state
  CoopBattleState.create_battle(
    is_initiator: true,
    ally_sids: ally_sids,
    battle_id: battle_id,
    trainer_battle: true,
    trainer_event_id: (get_current_event_id rescue nil),
    trainer_map_id: ($game_map.map_id rescue nil)
  )

  # === BUILD FOE SIDE (Trainer) ===
  foeTrainers = [trainer]
  foeParty = []
  foePartyStarts = [0]
  trainer.party.each { |pkmn| foeParty << pkmn }
  foeEndSpeeches = [end_speech || trainer.lose_text]
  foeItems = [trainer.items]

  ##MultiplayerDebug.info("COOP-TRAINER-BATTLE", "Trainer: #{trainer.name} with #{trainer.party.length} Pokemon")

  # === BUILD PLAYER SIDE (Initiator + Allies) ===
  trainer_type = :YOUNGSTER
  playerTrainers = [$Trainer]
  playerParty = []
  max_size = defined?(Settings::MAX_PARTY_SIZE) ? Settings::MAX_PARTY_SIZE : 6
  $Trainer.party.each { |pkmn| playerParty << pkmn }
  (max_size - $Trainer.party.length).times { playerParty << nil }
  playerPartyStarts = [0]

  ##MultiplayerDebug.info("COOP-TRAINER-BATTLE", "Initiator ($Trainer): #{$Trainer.party.length} Pokemon")

  # === ADD ALLIES AS NPCTRAINERS (AI-CONTROLLED) ===
  # Party data was already synced during wait screen (via COOP_PARTY_PUSH_NOW nudge)
  added_allies_count = 0
  ally_sids.sort.each_with_index do |sid, i|
    start_idx = playerParty.length

    # CRITICAL: ally_sids now contains full SID strings (e.g., "SID2")
    ally_party = MultiplayerClient.remote_party(sid) rescue []

    if !ally_party || ally_party.empty?
      ##MultiplayerDebug.warn("COOP-TRAINER-BATTLE", "Ally #{sid} has no party data after nudge, skipping")
      next
    end

    # Get ally name from squad
    ally_name = begin
      squad = MultiplayerClient.squad rescue nil
      if squad && squad[:members]
        member = squad[:members].find { |m| m[:sid].to_s == sid.to_s }
        member ? (member[:name] || "Ally") : "Ally"
      else
        "Ally"
      end
    rescue
      "Ally"
    end

    # Create NPCTrainer for ally
    npc = NPCTrainer.new(ally_name.to_s, trainer_type)
    npc.id = sid.to_s
    npc.party = ally_party

    # Add dummy pokedex with required interface (battle init requires it)
    unless npc.respond_to?(:pokedex)
      dummy_dex = Class.new do
        def register(*args); end
        def seen?(*args); false; end
        def owned?(*args); false; end
      end.new
      npc.instance_variable_set(:@pokedex, dummy_dex)
      def npc.pokedex; @pokedex; end
    end

    # Add badge_count (battle speed calculation requires it)
    def npc.badge_count; 8; end

    # Add money attribute (pbGainMoney requires it)
    npc.instance_variable_set(:@money, 0)
    def npc.money; @money; end
    def npc.money=(val); @money = val; end

    playerTrainers << npc
    playerPartyStarts << start_idx

    # Add party with padding to MAX_PARTY_SIZE (6 slots)
    ally_party.each { |pkmn| playerParty << pkmn }
    (max_size - ally_party.length).times { playerParty << nil }

    added_allies_count += 1
    ##MultiplayerDebug.info("COOP-TRAINER-BATTLE", "Added ally ##{added_allies_count}: name=#{ally_name} sid=#{sid} mons=#{ally_party.length} start=#{start_idx}")
  end

  ##MultiplayerDebug.info("COOP-TRAINER-BATTLE", "Successfully added #{added_allies_count}/#{ally_sids.length} allies")

  # === SET BATTLE RULES (before battle creation) ===
  # Count enemy trainer's Pokemon (non-nil)
  enemy_party_size = trainer.party.compact.length
  ##MultiplayerDebug.info("COOP-TRAINER-BATTLE", "Enemy trainer has #{enemy_party_size} Pokemon")

  # Count ally side (player + allies)
  ally_count = 1 + added_allies_count  # Use actual added count, not requested count

  # Left side = ally_count (always), Right side = min(enemy_party_size, ally_count)
  # Examples: 3 allies + 1 enemy poke = 3v1, 3 allies + 2 enemy pokes = 3v2, 3 allies + 3+ enemy pokes = 3v3
  enemy_count = [enemy_party_size, ally_count].min

  battle_rule = "#{ally_count}v#{enemy_count}"
  setBattleRule(battle_rule)
  ##MultiplayerDebug.info("COOP-TRAINER-BATTLE", "Set battle rule: #{battle_rule} (#{ally_count} allies vs #{enemy_party_size} enemy pokes)")

  setBattleRule("outcomeVar", outcome_var) if outcome_var != 1
  setBattleRule("canLose") if can_lose

  # === CREATE BATTLE ===
  $PokemonSystem.is_in_battle = true
  Events.onStartBattle.trigger(nil) if defined?(Events)

  scene = pbNewBattleScene
  battle = PokeBattle_Battle.new(scene, playerParty, foeParty, playerTrainers, foeTrainers)
  battle.party1starts = playerPartyStarts
  battle.party2starts = foePartyStarts
  battle.items = foeItems
  battle.endSpeeches = foeEndSpeeches

  # Clear any stale RNG seeds from buffer
  if defined?(CoopRNGSync)
    CoopRNGSync.reset_sync_state
    ##MultiplayerDebug.info("COOP-TRAINER-BATTLE", "Cleared RNG seed buffer for new trainer battle (initiator)")
  end

  # CRITICAL: Sync RNG seed IMMEDIATELY after battle creation
  # Use turn -1 to indicate "battle start" seed (before turn 0)
  if defined?(CoopRNGSync) && defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
    ##MultiplayerDebug.info("COOP-RNG-INIT", "Syncing initial RNG seed (trainer battle initiator)...")
    CoopRNGSync.sync_seed_as_initiator(battle, -1, true)
  end

  ##MultiplayerDebug.info("COOP-TRAINER-BATTLE", "Battle created: trainers=#{playerTrainers.length} vs #{foeTrainers.length}")

  # Apply battle rules BEFORE clearing them
  pbPrepareBattle(battle)
  $PokemonTemp.clearBattleRules

  # Defensive: Initialize heart_gauges if not set by onStartBattle event
  if defined?($PokemonTemp) && !$PokemonTemp.heart_gauges
    $PokemonTemp.heart_gauges = []
    $Trainer.party.each_with_index { |pkmn, i| $PokemonTemp.heart_gauges[i] = pkmn.heart_gauge if pkmn }
    ##MultiplayerDebug.info("COOP-TRAINER-BATTLE", "Initialized heart_gauges defensively")
  end

  # Mark busy
  if defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:mark_battle)
    MultiplayerClient.mark_battle(true)
    ##MultiplayerDebug.info("COOP-TRAINER-BATTLE", "Marked battle busy=true")
  end

  # Register battle instance for run away sync
  CoopBattleState.register_battle_instance(battle)
  ##MultiplayerDebug.info("COOP-TRAINER-BATTLE", "Battle instance registered with CoopBattleState")

  # === RUN BATTLE ===
  decision = 0
  pbBattleAnimation(pbGetTrainerBattleBGM(trainer), 1, [trainer]) {
    pbSceneStandby {
      decision = battle.pbStartBattle
    }
    pbAfterBattle(decision, can_lose)
  }
  Input.update

  ##MultiplayerDebug.info("COOP-TRAINER-BATTLE", "Battle ended: decision=#{decision}")

  # Set outcome variable (event scripts check this for badge award)
  pbSet(outcome_var, decision)
  ##MultiplayerDebug.info("COOP-TRAINER-BATTLE", "Set $game_variables[#{outcome_var}] = #{decision}")

  # Clear busy flag
  if defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:mark_battle)
    MultiplayerClient.mark_battle(false)
    ##MultiplayerDebug.info("COOP-TRAINER-BATTLE", "Marked battle busy=false")
  end

  # Clear sync wait
  MultiplayerClient.clear_trainer_sync_wait

  return decision
end

#===============================================================================
# Start Coop Trainer Battle as Joiner
#===============================================================================
def start_coop_trainer_battle_as_joiner(sync_wait, trainer_id, trainer_name, end_speech, can_lose, outcome_var)
  ##MultiplayerDebug.info("COOP-TRAINER-BATTLE", "Starting coop battle as joiner: #{sync_wait[:battle_id]}")

  # Decode trainer data from initiator (using TrainerSerializer - JSON-based)
  trainer_hex = sync_wait[:trainer_hex]
  ##MultiplayerDebug.info("COOP-TRAINER-BATTLE", "Decoding trainer data: #{trainer_hex.length} chars")

  trainer = nil
  begin
    if defined?(TrainerSerializer)
      trainer = TrainerSerializer.from_hex(trainer_hex)
    end
  rescue => e
    ##MultiplayerDebug.error("COOP-TRAINER-BATTLE", "Failed to decode trainer data: #{e.message}")
  end

  if trainer.nil?
    ##MultiplayerDebug.error("COOP-TRAINER-BATTLE", "Failed to decode trainer - nil result!")
    MultiplayerClient.clear_trainer_sync_wait
    return 2 # Loss
  end

  ##MultiplayerDebug.info("COOP-TRAINER-BATTLE", "Successfully decoded trainer: #{trainer.name}")

  # Get list of all allies (initiator + other joiners)
  # Initiator is the sender, other joiners are tracked by battle_id
  initiator_sid = sync_wait[:sender_sid]
  other_joiners = MultiplayerClient.trainer_battle_allies(sync_wait[:battle_id]) || []
  all_ally_sids = [initiator_sid] + other_joiners.reject { |sid| sid == initiator_sid }
  all_ally_sids.reject! { |sid| sid == MultiplayerClient.session_id } # Remove self

  ##MultiplayerDebug.info("COOP-TRAINER-BATTLE", "Allies in battle: #{all_ally_sids.inspect}")

  # Create battle state
  CoopBattleState.create_battle(
    is_initiator: false,
    ally_sids: all_ally_sids,
    battle_id: sync_wait[:battle_id],
    trainer_battle: true,
    trainer_event_id: sync_wait[:event_id],
    trainer_map_id: sync_wait[:map_id]
  )

  # === BUILD FOE SIDE (Trainer from initiator) ===
  foeTrainers = [trainer]
  foeParty = []
  foePartyStarts = [0]
  trainer.party.each { |pkmn| foeParty << pkmn }
  foeEndSpeeches = [end_speech || trainer.lose_text]
  foeItems = [trainer.items]

  ##MultiplayerDebug.info("COOP-TRAINER-BATTLE", "Trainer (from initiator): #{trainer.name} with #{trainer.party.length} Pokemon")

  # === BUILD PLAYER SIDE (Initiator + Myself + Other Joiners) ===
  trainer_type = :YOUNGSTER
  playerTrainers = []
  playerParty = []
  playerPartyStarts = []
  max_size = defined?(Settings::MAX_PARTY_SIZE) ? Settings::MAX_PARTY_SIZE : 6

  my_sid = MultiplayerClient.session_id.to_s

  # Add initiator first
  # NOTE: initiator_sid from sync_wait already has "SID" prefix from server broadcast
  initiator_party = MultiplayerClient.remote_party(initiator_sid) rescue []
  if !initiator_party || initiator_party.empty?
    ##MultiplayerDebug.warn("COOP-TRAINER-BATTLE", "Initiator party empty (sid=#{initiator_sid}), aborting")
    MultiplayerClient.clear_trainer_sync_wait
    return 2 # Loss
  end

  # Get initiator name from squad
  initiator_name = begin
    squad = MultiplayerClient.squad rescue nil
    if squad && squad[:members]
      member = squad[:members].find { |m| m[:sid].to_s == initiator_sid.to_s }
      member ? (member[:name] || "Host") : "Host"
    else
      "Host"
    end
  rescue
    "Host"
  end

  npc = NPCTrainer.new(initiator_name.to_s, trainer_type)
  npc.id = initiator_sid.to_s
  npc.party = initiator_party

  # Add dummy pokedex with required interface (battle init requires it)
  unless npc.respond_to?(:pokedex)
    dummy_dex = Class.new do
      def register(*args); end
      def seen?(*args); false; end
      def owned?(*args); false; end
    end.new
    npc.instance_variable_set(:@pokedex, dummy_dex)
    def npc.pokedex; @pokedex; end
  end

  # Add badge_count (battle speed calculation requires it)
  def npc.badge_count; 8; end

  # Add money attribute (pbGainMoney requires it)
  npc.instance_variable_set(:@money, 0)
  def npc.money; @money; end
  def npc.money=(val); @money = val; end

  start_idx = playerParty.length
  playerTrainers << npc
  playerPartyStarts << start_idx

  # Add party with padding to MAX_PARTY_SIZE (6 slots)
  initiator_party.each { |pkmn| playerParty << pkmn }
  (max_size - initiator_party.length).times { playerParty << nil }

  ##MultiplayerDebug.info("COOP-TRAINER-BATTLE", "Added initiator: name=#{initiator_name} sid=#{initiator_sid} mons=#{initiator_party.length}")

  # Add other allies (including myself) in sorted order to match initiator's ally ordering
  all_joiner_sids = [my_sid] + other_joiners.reject { |sid| sid == my_sid }
  all_joiner_sids.sort!
  all_joiner_sids.each_with_index do |sid, i|
    start_idx = playerParty.length

    # Get party (for myself, use $Trainer.party; for others, use cached remote_party)
    if sid == my_sid
      party = $Trainer.party rescue []
      ##MultiplayerDebug.info("COOP-TRAINER-BATTLE", "Adding self: sid=#{sid} mons=#{party.length}")
      playerTrainers << $Trainer
    else
      # Get ally party from cached remote_party
      # CRITICAL: sid already contains full SID string (e.g., "SID2")
      party = MultiplayerClient.remote_party(sid) rescue []
      if !party || party.empty?
        ##MultiplayerDebug.warn("COOP-TRAINER-BATTLE", "Ally #{sid} has no party data, skipping")
        next
      end

      # Get ally name from squad
      ally_name = begin
        squad = MultiplayerClient.squad rescue nil
        if squad && squad[:members]
          member = squad[:members].find { |m| m[:sid].to_s == sid.to_s }
          member ? (member[:name] || "Ally") : "Ally"
        else
          "Ally"
        end
      rescue
        "Ally"
      end

      # Create NPCTrainer for ally
      npc2 = NPCTrainer.new(ally_name.to_s, trainer_type)
      npc2.id = sid.to_s
      npc2.party = party

      # Add dummy pokedex with required interface (battle init requires it)
      unless npc2.respond_to?(:pokedex)
        dummy_dex2 = Class.new do
          def register(*args); end
          def seen?(*args); false; end
          def owned?(*args); false; end
        end.new
        npc2.instance_variable_set(:@pokedex, dummy_dex2)
        def npc2.pokedex; @pokedex; end
      end

      # Add badge_count (battle speed calculation requires it)
      def npc2.badge_count; 8; end

      # Add money attribute (pbGainMoney requires it)
      npc2.instance_variable_set(:@money, 0)
      def npc2.money; @money; end
      def npc2.money=(val); @money = val; end

      playerTrainers << npc2
      ##MultiplayerDebug.info("COOP-TRAINER-BATTLE", "Added ally: name=#{ally_name} sid=#{sid} mons=#{party.length}")
    end

    next if party.empty?

    playerPartyStarts << start_idx

    # Add party with padding to MAX_PARTY_SIZE (6 slots)
    party.each { |pkmn| playerParty << pkmn }
    (max_size - party.length).times { playerParty << nil }
  end

  # === SET BATTLE RULES (before battle creation) ===
  # Count enemy trainer's Pokemon (non-nil)
  enemy_party_size = trainer.party.compact.length
  ##MultiplayerDebug.info("COOP-TRAINER-BATTLE", "Enemy trainer has #{enemy_party_size} Pokemon")

  # Count ally side (player + allies)
  ally_count = 1 + all_ally_sids.length

  # Left side = ally_count (always), Right side = min(enemy_party_size, ally_count)
  # Examples: 3 allies + 1 enemy poke = 3v1, 3 allies + 2 enemy pokes = 3v2, 3 allies + 3+ enemy pokes = 3v3
  enemy_count = [enemy_party_size, ally_count].min

  battle_rule = "#{ally_count}v#{enemy_count}"
  setBattleRule(battle_rule)
  ##MultiplayerDebug.info("COOP-TRAINER-BATTLE", "Set battle rule: #{battle_rule} (joiner: #{ally_count} allies vs #{enemy_party_size} enemy pokes)")

  setBattleRule("outcomeVar", outcome_var) if outcome_var != 1
  setBattleRule("canLose") if can_lose

  # === CREATE BATTLE ===
  $PokemonSystem.is_in_battle = true
  Events.onStartBattle.trigger(nil) if defined?(Events)

  scene = pbNewBattleScene
  battle = PokeBattle_Battle.new(scene, playerParty, foeParty, playerTrainers, foeTrainers)
  battle.party1starts = playerPartyStarts
  battle.party2starts = foePartyStarts
  battle.items = foeItems
  battle.endSpeeches = foeEndSpeeches

  # Clear any stale RNG seeds from buffer
  if defined?(CoopRNGSync)
    CoopRNGSync.reset_sync_state
    ##MultiplayerDebug.info("COOP-TRAINER-BATTLE", "Cleared RNG seed buffer for new trainer battle (joiner)")
  end

  # CRITICAL: Sync RNG seed IMMEDIATELY after battle creation
  # Use turn -1 to indicate "battle start" seed (before turn 0)
  if defined?(CoopRNGSync) && defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
    ##MultiplayerDebug.info("COOP-RNG-INIT", "Syncing initial RNG seed (trainer battle joiner)...")
    success = CoopRNGSync.sync_seed_as_receiver(battle, -1, 5, true)
    unless success
      ##MultiplayerDebug.error("COOP-RNG-INIT", "Failed to sync initial RNG seed!")
    end
  end

  ##MultiplayerDebug.info("COOP-TRAINER-BATTLE", "Battle created: trainers=#{playerTrainers.length} vs #{foeTrainers.length}")

  # Apply battle rules BEFORE clearing them
  pbPrepareBattle(battle)
  $PokemonTemp.clearBattleRules

  # Defensive: Initialize heart_gauges if not set by onStartBattle event
  if defined?($PokemonTemp) && !$PokemonTemp.heart_gauges
    $PokemonTemp.heart_gauges = []
    $Trainer.party.each_with_index { |pkmn, i| $PokemonTemp.heart_gauges[i] = pkmn.heart_gauge if pkmn }
    ##MultiplayerDebug.info("COOP-TRAINER-BATTLE", "Initialized heart_gauges defensively")
  end

  # Mark busy
  if defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:mark_battle)
    MultiplayerClient.mark_battle(true)
    ##MultiplayerDebug.info("COOP-TRAINER-BATTLE", "Marked battle busy=true")
  end

  # Register battle instance for run away sync
  CoopBattleState.register_battle_instance(battle)
  ##MultiplayerDebug.info("COOP-TRAINER-BATTLE", "Battle instance registered with CoopBattleState")

  # === RUN BATTLE ===
  decision = 0
  pbBattleAnimation(pbGetTrainerBattleBGM(trainer), 1, [trainer]) {
    pbSceneStandby {
      decision = battle.pbStartBattle
    }
    pbAfterBattle(decision, can_lose)
  }
  Input.update

  ##MultiplayerDebug.info("COOP-TRAINER-BATTLE", "Battle ended: decision=#{decision}")

  # Set outcome variable (event scripts check this for badge award)
  pbSet(outcome_var, decision)
  ##MultiplayerDebug.info("COOP-TRAINER-BATTLE", "Set $game_variables[#{outcome_var}] = #{decision}")

  # Clear busy flag
  if defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:mark_battle)
    MultiplayerClient.mark_battle(false)
    ##MultiplayerDebug.info("COOP-TRAINER-BATTLE", "Marked battle busy=false")
  end

  # Clear sync wait
  MultiplayerClient.clear_trainer_sync_wait

  return decision
end

#===============================================================================
# Helper: Get current event ID
#===============================================================================
def get_current_event_id
  # Try to get event ID from interpreter context
  return pbMapInterpreter.get_self.id rescue nil
end

#===============================================================================
# Module Loaded
#===============================================================================
##MultiplayerDebug.info("COOP-TRAINER", "Trainer battle hook loaded successfully")
