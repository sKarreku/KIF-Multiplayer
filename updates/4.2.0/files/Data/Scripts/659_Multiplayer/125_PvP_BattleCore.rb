# ===========================================
# File: 125_PvP_BattleCore.rb
# Purpose: PvP Battle Core - Initialize and run PvP battles
# Phase: 4 - Battle Initialization
# ===========================================

#===============================================================================
# Main PvP Battle Function (called from settings UI)
#===============================================================================
def pbPvPBattle
  if defined?(MultiplayerDebug)
    MultiplayerDebug.info("PVP-BATTLE", "╔══════════════════════════════════════════════════════════")
    MultiplayerDebug.info("PVP-BATTLE", "║ pbPvPBattle() CALLED")
    MultiplayerDebug.info("PVP-BATTLE", "╚══════════════════════════════════════════════════════════")
  end

  begin
    # Get battle state
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-BATTLE", "Retrieving battle state...")
    end

    battle_id = PvPBattleState.battle_id
    is_initiator = PvPBattleState.is_initiator?
    opponent_sid = PvPBattleState.opponent_sid
    opponent_name = PvPBattleState.opponent_name
    settings = PvPBattleState.settings
    my_selections = PvPBattleState.my_selections

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-BATTLE", "✓ Battle state retrieved")
      MultiplayerDebug.info("PVP-BATTLE", "  Battle ID: #{battle_id}")
      MultiplayerDebug.info("PVP-BATTLE", "  Initiator: #{is_initiator}")
      MultiplayerDebug.info("PVP-BATTLE", "  Opponent: #{opponent_name} (SID: #{opponent_sid})")
      MultiplayerDebug.info("PVP-BATTLE", "  Settings: #{settings.inspect}")
      MultiplayerDebug.info("PVP-BATTLE", "  My selections: #{my_selections.inspect}")
    end

    # Store original levels for restoration after battle
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-BATTLE", "Storing original Pokemon levels...")
    end

    original_levels = {}
    $Trainer.party.each_with_index do |pkmn, idx|
      next if !pkmn
      original_levels[idx] = pkmn.level
    end

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-BATTLE", "✓ Stored #{original_levels.size} Pokemon levels")
    end

    # Mark battle as active
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-BATTLE", "Marking battle as active...")
    end

    PvPBattleState.mark_battle_active

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-BATTLE", "✓ Battle marked as active")
    end
  rescue => e
    if defined?(MultiplayerDebug)
      MultiplayerDebug.error("PVP-BATTLE", "✗ FATAL: Failed during battle initialization!")
      MultiplayerDebug.error("PVP-BATTLE", "Error: #{e.message}")
      MultiplayerDebug.error("PVP-BATTLE", "Backtrace:")
      e.backtrace.each { |line| MultiplayerDebug.error("PVP-BATTLE", "  #{line}") }
    end
    PvPBattleState.reset()
    MultiplayerClient.clear_pvp_state() if defined?(MultiplayerClient)
    raise
  end

  # === PARTY EXCHANGE ===
  # Both players need to send their party to each other
  if is_initiator
    # Initiator: Give receiver a moment to enter pbPvPBattle() after receiving :start_battle event
    sleep(0.5)
    pvp_exchange_parties_as_initiator(battle_id, opponent_sid, my_selections)
  else
    pvp_exchange_parties_as_receiver(battle_id, opponent_sid, my_selections)
  end

  # === BUILD TRAINER OBJECTS ===
  # Create NPCTrainer for opponent using received party data
  trainer_type = :YOUNGSTER

  # Get opponent's party from network
  opponent_party = PvPBattleState.opponent_party
  if !opponent_party || opponent_party.empty?
    pbMessage(_INTL("Failed to receive opponent's party data!"))
    PvPBattleState.reset()
    MultiplayerClient.clear_pvp_state()
    return 2  # Loss
  end

  # Create opponent trainer
  opponent_trainer = NPCTrainer.new(opponent_name.to_s, trainer_type)
  opponent_trainer.id = opponent_sid.to_s
  opponent_trainer.party = opponent_party

  # Add dummy pokedex with required interface (battle init requires it)
  unless opponent_trainer.respond_to?(:pokedex)
    dummy_dex = Class.new do
      def register(*args); end
      def seen?(*args); false; end
      def owned?(*args); false; end
    end.new
    opponent_trainer.instance_variable_set(:@pokedex, dummy_dex)
    def opponent_trainer.pokedex; @pokedex; end
  end

  # Add badge_count (battle speed calculation requires it)
  def opponent_trainer.badge_count; 8; end

  # Add money attribute (pbGainMoney requires it)
  opponent_trainer.instance_variable_set(:@money, 0)
  def opponent_trainer.money; @money; end
  def opponent_trainer.money=(val); @money = val; end

  if defined?(MultiplayerDebug)
    MultiplayerDebug.info("PVP-BATTLE", "Opponent trainer created: #{opponent_name} with #{opponent_party.length} Pokemon")
  end

  # === BUILD BATTLE PARTIES ===
  playerTrainers = [$Trainer]
  foeTrainers = [opponent_trainer]

  # Build player party based on settings
  max_size = defined?(Settings::MAX_PARTY_SIZE) ? Settings::MAX_PARTY_SIZE : 6
  playerParty = []

  # Apply party size restrictions (Pick 3, Pick 4, or full)
  if settings["party_size"] == "pick3" || settings["party_size"] == "pick4"
    # Use selected Pokemon only
    if my_selections && my_selections.length > 0
      my_selections.each do |idx|
        playerParty << $Trainer.party[idx] if $Trainer.party[idx]
      end
    else
      # Fallback: use first N Pokemon
      limit = settings["party_size"] == "pick3" ? 3 : 4
      $Trainer.party.first(limit).each { |pkmn| playerParty << pkmn }
    end
  else
    # Full party
    $Trainer.party.each { |pkmn| playerParty << pkmn }
  end

  # Remove held items if disabled
  if !settings["held_items"]
    playerParty.each do |pkmn|
      next if !pkmn
      pkmn.item = nil
    end
  end

  # Apply level cap if set
  if settings["level_cap"] == "level50"
    playerParty.each do |pkmn|
      next if !pkmn
      if pkmn.level != 50
        # Temporarily set level to 50 (will be restored after battle)
        pkmn.level = 50
        pkmn.calc_stats
      end
    end
  end

  # Pad with nils
  (max_size - playerParty.length).times { playerParty << nil }

  # Opponent party (already filtered by opponent's selection)
  foeParty = []
  opponent_party.each { |pkmn| foeParty << pkmn }

  # Remove held items if disabled
  if !settings["held_items"]
    foeParty.each do |pkmn|
      next if !pkmn
      pkmn.item = nil
    end
  end

  # Apply level cap if set
  if settings["level_cap"] == "level50"
    foeParty.each do |pkmn|
      next if !pkmn
      if pkmn.level != 50
        pkmn.level = 50
        pkmn.calc_stats
      end
    end
  end

  # Pad with nils
  (max_size - opponent_party.length).times { foeParty << nil }

  playerPartyStarts = [0]
  foePartyStarts = [0]

  if defined?(MultiplayerDebug)
    MultiplayerDebug.info("PVP-BATTLE", "Player party: #{playerParty.compact.length} Pokemon")
    MultiplayerDebug.info("PVP-BATTLE", "Foe party: #{foeParty.compact.length} Pokemon")
    MultiplayerDebug.info("PVP-BATTLE", "Settings - Battle size: #{settings['battle_size']}, Held items: #{settings['held_items']}, Items: #{settings['battle_items']}, Level cap: #{settings['level_cap']}")
  end

  # === SET BATTLE RULES ===
  if defined?(MultiplayerDebug)
    MultiplayerDebug.info("PVP-BATTLE", "=== STARTING BATTLE RULES SETUP ===")
  end

  # Set battle size from settings (1v1, 2v2, 3v3)
  battle_size = settings["battle_size"] || "1v1"

  if defined?(MultiplayerDebug)
    MultiplayerDebug.info("PVP-BATTLE", "Setting battle size: #{battle_size}")
  end

  begin
    setBattleRule(battle_size)
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-BATTLE", "✓ Battle size rule set successfully")
    end
  rescue => e
    if defined?(MultiplayerDebug)
      MultiplayerDebug.error("PVP-BATTLE", "✗ Failed to set battle size: #{e.message}")
      MultiplayerDebug.error("PVP-BATTLE", "Backtrace: #{e.backtrace.first(5).join('\n')}")
    end
    raise
  end

  # PvP battles never give EXP or money
  if defined?(MultiplayerDebug)
    MultiplayerDebug.info("PVP-BATTLE", "Setting noexp rule")
  end

  begin
    setBattleRule("noexp")
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-BATTLE", "✓ noexp rule set successfully")
    end
  rescue => e
    if defined?(MultiplayerDebug)
      MultiplayerDebug.error("PVP-BATTLE", "✗ Failed to set noexp: #{e.message}")
    end
    raise
  end

  if defined?(MultiplayerDebug)
    MultiplayerDebug.info("PVP-BATTLE", "Setting nomoney rule")
  end

  begin
    setBattleRule("nomoney")
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-BATTLE", "✓ nomoney rule set successfully")
    end
  rescue => e
    if defined?(MultiplayerDebug)
      MultiplayerDebug.error("PVP-BATTLE", "✗ Failed to set nomoney: #{e.message}")
    end
    raise
  end

  # PvP battles can always lose (no blackout)
  if defined?(MultiplayerDebug)
    MultiplayerDebug.info("PVP-BATTLE", "Setting canLose rule")
  end

  begin
    setBattleRule("canLose")
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-BATTLE", "✓ canLose rule set successfully")
    end
  rescue => e
    if defined?(MultiplayerDebug)
      MultiplayerDebug.error("PVP-BATTLE", "✗ Failed to set canLose: #{e.message}")
    end
    raise
  end

  if defined?(MultiplayerDebug)
    MultiplayerDebug.info("PVP-BATTLE", "✓ All battle rules set: #{battle_size}, noexp, nomoney, canLose")
  end

  # === CREATE BATTLE ===
  if defined?(MultiplayerDebug)
    MultiplayerDebug.info("PVP-BATTLE", "=== STARTING BATTLE CREATION ===")
  end

  begin
    $PokemonSystem.is_in_battle = true
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-BATTLE", "✓ Set is_in_battle flag")
    end
  rescue => e
    if defined?(MultiplayerDebug)
      MultiplayerDebug.error("PVP-BATTLE", "✗ Failed to set is_in_battle: #{e.message}")
    end
    raise
  end

  begin
    Events.onStartBattle.trigger(nil) if defined?(Events)
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-BATTLE", "✓ Triggered onStartBattle event")
    end
  rescue => e
    if defined?(MultiplayerDebug)
      MultiplayerDebug.error("PVP-BATTLE", "✗ Failed to trigger event: #{e.message}")
    end
    raise
  end

  if defined?(MultiplayerDebug)
    MultiplayerDebug.info("PVP-BATTLE", "Creating battle scene...")
  end

  begin
    scene = pbNewBattleScene
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-BATTLE", "✓ Battle scene created: #{scene.class.name}")
    end
  rescue => e
    if defined?(MultiplayerDebug)
      MultiplayerDebug.error("PVP-BATTLE", "✗ Failed to create scene: #{e.message}")
      MultiplayerDebug.error("PVP-BATTLE", "Backtrace: #{e.backtrace.first(5).join('\n')}")
    end
    raise
  end

  if defined?(MultiplayerDebug)
    MultiplayerDebug.info("PVP-BATTLE", "Creating battle instance...")
    MultiplayerDebug.info("PVP-BATTLE", "  playerParty size: #{playerParty.compact.length}")
    MultiplayerDebug.info("PVP-BATTLE", "  foeParty size: #{foeParty.compact.length}")
    MultiplayerDebug.info("PVP-BATTLE", "  playerTrainers: #{playerTrainers.map(&:name).join(', ')}")
    MultiplayerDebug.info("PVP-BATTLE", "  foeTrainers: #{foeTrainers.map(&:name).join(', ')}")
  end

  begin
    battle = PokeBattle_Battle.new(scene, playerParty, foeParty, playerTrainers, foeTrainers)
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-BATTLE", "✓ Battle instance created: #{battle.class.name}")
    end
  rescue => e
    if defined?(MultiplayerDebug)
      MultiplayerDebug.error("PVP-BATTLE", "✗ Failed to create battle: #{e.message}")
      MultiplayerDebug.error("PVP-BATTLE", "Backtrace: #{e.backtrace.first(10).join('\n')}")
    end
    raise
  end

  if defined?(MultiplayerDebug)
    MultiplayerDebug.info("PVP-BATTLE", "Setting battle properties...")
  end

  begin
    battle.party1starts = playerPartyStarts
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-BATTLE", "✓ Set party1starts: #{playerPartyStarts.inspect}")
    end
  rescue => e
    if defined?(MultiplayerDebug)
      MultiplayerDebug.error("PVP-BATTLE", "✗ Failed to set party1starts: #{e.message}")
    end
    raise
  end

  begin
    battle.party2starts = foePartyStarts
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-BATTLE", "✓ Set party2starts: #{foePartyStarts.inspect}")
    end
  rescue => e
    if defined?(MultiplayerDebug)
      MultiplayerDebug.error("PVP-BATTLE", "✗ Failed to set party2starts: #{e.message}")
    end
    raise
  end

  begin
    battle.items = [[]]  # No items for opponent
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-BATTLE", "✓ Set battle items")
    end
  rescue => e
    if defined?(MultiplayerDebug)
      MultiplayerDebug.error("PVP-BATTLE", "✗ Failed to set items: #{e.message}")
    end
    raise
  end

  begin
    battle.endSpeeches = ["Good game!"]
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-BATTLE", "✓ Set end speeches")
    end
  rescue => e
    if defined?(MultiplayerDebug)
      MultiplayerDebug.error("PVP-BATTLE", "✗ Failed to set end speeches: #{e.message}")
    end
    raise
  end

  # Disable bag if battle_items is false (must be done AFTER battle creation)
  if !settings["battle_items"]
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-BATTLE", "Attempting to disable bag...")
    end

    begin
      # Try internalBattle first (correct property)
      if battle.respond_to?(:internalBattle=)
        battle.internalBattle = false
        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("PVP-BATTLE", "✓ Bag disabled via internalBattle=false")
        end
      elsif battle.respond_to?(:disableBag=)
        battle.disableBag = true
        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("PVP-BATTLE", "✓ Bag disabled via disableBag=true")
        end
      else
        if defined?(MultiplayerDebug)
          MultiplayerDebug.warn("PVP-BATTLE", "⚠ Battle object has no internalBattle or disableBag property!")
          MultiplayerDebug.warn("PVP-BATTLE", "Available methods: #{battle.methods.grep(/bag|item|internal/).join(', ')}")
        end
      end
    rescue => e
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error("PVP-BATTLE", "✗ Failed to disable bag: #{e.message}")
      end
      raise
    end
  end

  if defined?(MultiplayerDebug)
    MultiplayerDebug.info("PVP-BATTLE", "✓ Battle instance fully configured")
  end

  # CRITICAL: Sync RNG seed IMMEDIATELY after battle creation (before pbPrepareBattle)
  # Use turn -1 to indicate "battle start" seed (before turn 0)
  # This matches the Coop pattern in 017_Coop_WildHook_v2.rb and 065_Coop_TrainerHook.rb
  if defined?(PvPRNGSync) && defined?(PvPBattleState) && PvPBattleState.in_pvp_battle?
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-RNG-INIT", "Syncing initial RNG seed (turn -1)...")
    end

    if is_initiator
      PvPRNGSync.sync_seed_as_initiator(battle, -1)
      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-RNG-INIT", "✓ Initial RNG seed synced (initiator)")
      end
    else
      success = PvPRNGSync.sync_seed_as_receiver(battle, -1, 10)
      if success
        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("PVP-RNG-INIT", "✓ Initial RNG seed synced (receiver)")
        end
      else
        if defined?(MultiplayerDebug)
          MultiplayerDebug.error("PVP-RNG-INIT", "✗ Failed to sync initial RNG seed!")
        end
      end
    end
  end

  # Apply battle rules
  if defined?(MultiplayerDebug)
    MultiplayerDebug.info("PVP-BATTLE", "Preparing battle...")
  end

  begin
    pbPrepareBattle(battle)
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-BATTLE", "✓ Battle prepared successfully")
    end
  rescue => e
    if defined?(MultiplayerDebug)
      MultiplayerDebug.error("PVP-BATTLE", "✗ Failed to prepare battle: #{e.message}")
      MultiplayerDebug.error("PVP-BATTLE", "Backtrace: #{e.backtrace.first(10).join('\n')}")
    end
    raise
  end

  begin
    $PokemonTemp.clearBattleRules
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-BATTLE", "✓ Cleared battle rules")
    end
  rescue => e
    if defined?(MultiplayerDebug)
      MultiplayerDebug.error("PVP-BATTLE", "✗ Failed to clear battle rules: #{e.message}")
    end
    raise
  end

  if defined?(MultiplayerDebug)
    MultiplayerDebug.info("PVP-BATTLE", "=== BATTLE SETUP COMPLETE ===")
  end

  # Mark busy
  if defined?(MultiplayerDebug)
    MultiplayerDebug.info("PVP-BATTLE", "Marking battle as busy...")
  end

  begin
    if defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:mark_battle)
      MultiplayerClient.mark_battle(true)
      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-BATTLE", "✓ Marked battle busy=true")
      end
    end
  rescue => e
    if defined?(MultiplayerDebug)
      MultiplayerDebug.error("PVP-BATTLE", "✗ Failed to mark battle busy: #{e.message}")
    end
    raise
  end

  # Register battle instance
  if defined?(MultiplayerDebug)
    MultiplayerDebug.info("PVP-BATTLE", "Registering battle instance...")
  end

  begin
    PvPBattleState.register_battle_instance(battle)
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-BATTLE", "✓ Battle instance registered")
    end
  rescue => e
    if defined?(MultiplayerDebug)
      MultiplayerDebug.error("PVP-BATTLE", "✗ Failed to register battle: #{e.message}")
    end
    raise
  end

  # === RUN BATTLE ===
  if defined?(MultiplayerDebug)
    MultiplayerDebug.info("PVP-BATTLE", "=== STARTING BATTLE ANIMATION ===")
  end

  decision = 0

  begin
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-BATTLE", "Getting battle BGM...")
    end
    bgm = pbGetWildBattleBGM(nil)
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-BATTLE", "✓ BGM: #{bgm.inspect}")
    end
  rescue => e
    if defined?(MultiplayerDebug)
      MultiplayerDebug.error("PVP-BATTLE", "✗ Failed to get BGM: #{e.message}")
    end
    bgm = nil
  end

  begin
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-BATTLE", "Starting battle animation and battle...")
    end

    pbBattleAnimation(bgm, 0, []) {
      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("PVP-BATTLE", "✓ Battle animation started, entering scene standby...")
      end

      pbSceneStandby {
        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("PVP-BATTLE", "✓ Scene standby entered, calling battle.pbStartBattle...")
        end

        begin
          decision = battle.pbStartBattle
          if defined?(MultiplayerDebug)
            MultiplayerDebug.info("PVP-BATTLE", "✓ battle.pbStartBattle completed with decision=#{decision}")
          end
        rescue => e
          if defined?(MultiplayerDebug)
            MultiplayerDebug.error("PVP-BATTLE", "✗ battle.pbStartBattle crashed: #{e.message}")
            MultiplayerDebug.error("PVP-BATTLE", "Backtrace: #{e.backtrace.first(10).join('\n')}")
          end
          raise
        end
      }
      # No pbAfterBattle - PvP battles don't heal party
    }

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-BATTLE", "✓ Battle animation completed")
    end
  rescue => e
    if defined?(MultiplayerDebug)
      MultiplayerDebug.error("PVP-BATTLE", "✗ Battle animation/execution failed: #{e.message}")
      MultiplayerDebug.error("PVP-BATTLE", "Backtrace: #{e.backtrace.first(10).join('\n')}")
    end
    raise
  end

  begin
    Input.update
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-BATTLE", "✓ Input updated")
    end
  rescue => e
    if defined?(MultiplayerDebug)
      MultiplayerDebug.error("PVP-BATTLE", "✗ Failed to update input: #{e.message}")
    end
  end

  if defined?(MultiplayerDebug)
    MultiplayerDebug.info("PVP-BATTLE", "=== BATTLE FINISHED: decision=#{decision} ===")
  end

  # Clear busy flag
  if defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:mark_battle)
    MultiplayerClient.mark_battle(false)
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-BATTLE", "Marked battle busy=false")
    end
  end

  # Restore original levels if level cap was applied
  if settings["level_cap"] == "level50"
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-BATTLE", "Restoring original levels after level cap")
    end
    original_levels.each do |idx, original_level|
      pkmn = $Trainer.party[idx]
      next if !pkmn
      if pkmn.level != original_level
        pkmn.level = original_level
        pkmn.calc_stats
      end
    end
  end

  # Heal party after PvP battle
  if defined?(MultiplayerDebug)
    MultiplayerDebug.info("PVP-BATTLE", "Healing party after PvP battle")
  end
  pbHealAll

  # Show result message
  case decision
  when 1
    pbMessage(_INTL("You won the battle!"))
  when 2
    pbMessage(_INTL("You lost the battle!"))
  when 5
    pbMessage(_INTL("The battle ended in a draw!"))
  end

  # Clean up
  PvPBattleState.reset()
  PvPForfeitSync.reset() if defined?(PvPForfeitSync)
  PvPActionSync.reset_sync_state() if defined?(PvPActionSync)
  MultiplayerClient.clear_pvp_state()

  return decision
end

#===============================================================================
# Party Exchange Functions
#===============================================================================
def pvp_exchange_parties_as_initiator(battle_id, opponent_sid, my_selections)
  if defined?(MultiplayerDebug)
    MultiplayerDebug.info("PVP-PARTY-EXCHANGE", "Initiator sending party to #{opponent_sid}")
  end

  # Build party data to send
  settings = PvPBattleState.settings
  party_to_send = []

  # Apply party size restrictions (Pick 3, Pick 4, or full)
  if settings["party_size"] == "pick3" || settings["party_size"] == "pick4"
    # Use selected Pokemon only
    if my_selections && my_selections.length > 0
      my_selections.each do |idx|
        party_to_send << $Trainer.party[idx] if $Trainer.party[idx]
      end
    else
      # Fallback: use first N Pokemon
      limit = settings["party_size"] == "pick3" ? 3 : 4
      party_to_send = $Trainer.party.compact.first(limit)
    end
  else
    # Full party
    party_to_send = $Trainer.party.compact
  end

  # Use existing API to send party
  begin
    MultiplayerClient.pvp_send_party(battle_id, party_to_send)

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-PARTY-EXCHANGE", "Sent party: #{party_to_send.length} Pokemon (mode: #{settings['party_size']})")
    end
  rescue => e
    if defined?(MultiplayerDebug)
      MultiplayerDebug.error("PVP-PARTY-EXCHANGE", "Failed to send party: #{e.message}")
    end
  end

  # Wait for opponent's party (60 second timeout - they might be selecting Pokemon)
  wait_start = Time.now
  wait_timeout = 60.0
  last_log_time = Time.now

  loop do
    Graphics.update if defined?(Graphics)
    Input.update if defined?(Input)

    # Check for received party (event type is :party_received)
    if MultiplayerClient.pvp_events_pending?
      ev = MultiplayerClient.next_pvp_event
      if ev && ev[:type] == :party_received
        # Party already decoded by client
        opponent_party = ev[:data][:party]

        PvPBattleState.set_opponent_party(opponent_party)

        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("PVP-PARTY-EXCHANGE", "Received opponent party: #{opponent_party.length} Pokemon")
        end

        break
      else
        # Got a different event type - log it for debugging
        if defined?(MultiplayerDebug)
          MultiplayerDebug.warn("PVP-PARTY-EXCHANGE", "Got unexpected event type: #{ev[:type].inspect} (expected :party_received)")
        end
      end
    end

    # Log progress every 5 seconds
    if defined?(MultiplayerDebug) && Time.now - last_log_time >= 5.0
      elapsed = (Time.now - wait_start).round(1)
      MultiplayerDebug.info("PVP-PARTY-EXCHANGE", "Still waiting for opponent party... (#{elapsed}s elapsed)")
      last_log_time = Time.now
    end

    # Check timeout
    if Time.now - wait_start > wait_timeout
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error("PVP-PARTY-EXCHANGE", "Timeout waiting for opponent party after #{wait_timeout}s")
      end
      break
    end

    sleep(0.05)
  end
end

def pvp_exchange_parties_as_receiver(battle_id, opponent_sid, my_selections)
  if defined?(MultiplayerDebug)
    MultiplayerDebug.info("PVP-PARTY-EXCHANGE", "Receiver waiting for opponent party")
  end

  # Wait for opponent's party first (60 second timeout - they might be selecting Pokemon)
  wait_start = Time.now
  wait_timeout = 60.0
  last_log_time = Time.now

  loop do
    Graphics.update if defined?(Graphics)
    Input.update if defined?(Input)

    # Check for received party (event type is :party_received)
    if MultiplayerClient.pvp_events_pending?
      ev = MultiplayerClient.next_pvp_event
      if ev && ev[:type] == :party_received
        # Party already decoded by client
        opponent_party = ev[:data][:party]

        PvPBattleState.set_opponent_party(opponent_party)

        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("PVP-PARTY-EXCHANGE", "Received opponent party: #{opponent_party.length} Pokemon")
        end

        break
      else
        # Got a different event type - log it for debugging
        if defined?(MultiplayerDebug)
          MultiplayerDebug.warn("PVP-PARTY-EXCHANGE", "Got unexpected event type: #{ev[:type].inspect} (expected :party_received)")
        end
      end
    end

    # Log progress every 5 seconds
    if defined?(MultiplayerDebug) && Time.now - last_log_time >= 5.0
      elapsed = (Time.now - wait_start).round(1)
      MultiplayerDebug.info("PVP-PARTY-EXCHANGE", "Still waiting for opponent party... (#{elapsed}s elapsed)")
      last_log_time = Time.now
    end

    # Check timeout
    if Time.now - wait_start > wait_timeout
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error("PVP-PARTY-EXCHANGE", "Timeout waiting for opponent party after #{wait_timeout}s")
      end
      break
    end

    sleep(0.05)
  end

  # Now send our party
  if defined?(MultiplayerDebug)
    MultiplayerDebug.info("PVP-PARTY-EXCHANGE", "Receiver sending party to #{opponent_sid}")
  end

  # Build party data to send
  settings = PvPBattleState.settings
  party_to_send = []

  # Apply party size restrictions (Pick 3, Pick 4, or full)
  if settings["party_size"] == "pick3" || settings["party_size"] == "pick4"
    # Use selected Pokemon only
    if my_selections && my_selections.length > 0
      my_selections.each do |idx|
        party_to_send << $Trainer.party[idx] if $Trainer.party[idx]
      end
    else
      # Fallback: use first N Pokemon
      limit = settings["party_size"] == "pick3" ? 3 : 4
      party_to_send = $Trainer.party.compact.first(limit)
    end
  else
    # Full party
    party_to_send = $Trainer.party.compact
  end

  # Use existing API to send party
  begin
    MultiplayerClient.pvp_send_party(battle_id, party_to_send)

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("PVP-PARTY-EXCHANGE", "Sent party: #{party_to_send.length} Pokemon (mode: #{settings['party_size']})")
    end
  rescue => e
    if defined?(MultiplayerDebug)
      MultiplayerDebug.error("PVP-PARTY-EXCHANGE", "Failed to send party: #{e.message}")
    end
  end
end

#===============================================================================
# Note: Pokemon serialization is handled by the existing MultiplayerClient
# system using Marshal + BinHex encoding. The party is sent as-is with
# Pokemon objects, and the SafeMarshal system on the client side handles
# decoding and validation.
#===============================================================================

if defined?(MultiplayerDebug)
  MultiplayerDebug.info("PVP-CORE", "PvP battle core loaded")
end
