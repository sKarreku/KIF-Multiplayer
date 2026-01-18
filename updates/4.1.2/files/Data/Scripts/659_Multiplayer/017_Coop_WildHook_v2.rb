# ===========================================
# File: 017_Coop_WildHook_v2.rb
# Purpose: Co-op wild battles (hook pbBattleOnStepTaken for early intervention)
# Notes : Hooks BEFORE pbWildBattle/pbDoubleWildBattle/pbTripleWildBattle
#         so we can control battle size and foe generation.
#         0 allies → vanilla; 1 ally → double; 2 allies → triple.
# ===========================================

##MultiplayerDebug.info("COOP-HOOK-V2", "Loading new pbBattleOnStepTaken hook...")

# ----- Small logging helpers -----
module CoopLogUtil
  def self.bt(e, n = 8)
    begin
      arr = (e.backtrace || [])[0, n]
      arr ? (" bt=" + arr.join(" | ")) : ""
    rescue
      ""
    end
  end

  def self.dex_name(p)
    return "nil" unless p
    begin
      s = (p.respond_to?(:speciesName) ? p.speciesName : p.species).to_s
      l = p.respond_to?(:level) ? p.level : "?"
      hp = p.respond_to?(:hp) ? p.hp : "?"
      thp = p.respond_to?(:totalhp) ? p.totalhp : "?"
      st = (p.respond_to?(:status) ? p.status.to_s : "-")
      "#{s}/L#{l}/HP#{hp}/#{thp}/ST=#{st}"
    rescue
      "<?>"
    end
  end
end

# ----- Ally discovery + foe expansion -----
module CoopWildHook
  TAG = "COOP-V2"

  # Broadcast battle invitation to allies
  def self.broadcast_battle_invite(foe_party, allies, encounter_type, battle_id = nil)
    begin
      unless defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:send_data)
        ##MultiplayerDebug.warn(TAG, "Cannot broadcast: MultiplayerClient missing")
        return
      end

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info(TAG, "=" * 70)
        MultiplayerDebug.info(TAG, "BROADCAST BATTLE INVITE START")
        MultiplayerDebug.info(TAG, "  Foes: #{foe_party.length}")
        MultiplayerDebug.info(TAG, "  Allies: #{allies.length}")
        MultiplayerDebug.info(TAG, "  Encounter type: #{encounter_type}")
        MultiplayerDebug.info(TAG, "  Battle ID: #{battle_id}")
      end

      # Use PokemonSerializer for JSON-based serialization (replaces Marshal for security)
      if defined?(PokemonSerializer)
        if defined?(MultiplayerDebug)
          MultiplayerDebug.info(TAG, "  Using PokemonSerializer (JSON-safe)")
        end

        # Serialize using PokemonSerializer
        invite_payload = PokemonSerializer.serialize_battle_invite(foe_party, allies, encounter_type, battle_id)

        # Convert to JSON string
        json_str = MiniJSON.dump(invite_payload)

        if defined?(MultiplayerDebug)
          MultiplayerDebug.info(TAG, "  JSON serialized: #{json_str.length} chars")
        end

        # Send as JSON (no BinHex needed for JSON)
        MultiplayerClient.send_data("COOP_BTL_START_JSON:#{json_str}")

        if defined?(MultiplayerDebug)
          MultiplayerDebug.info(TAG, "  Sent COOP_BTL_START_JSON message")
          MultiplayerDebug.info(TAG, "BROADCAST BATTLE INVITE END (JSON)")
          MultiplayerDebug.info(TAG, "=" * 70)
        end
      #else
        ## Fallback to old Marshal method if PokemonSerializer not available
        ## COMMENTED OUT FOR TESTING - JSON-only mode
        #if defined?(MultiplayerDebug)
        #  MultiplayerDebug.warn(TAG, "  PokemonSerializer not available, falling back to Marshal")
        #end
        #
        ## Serialize ally list (SIDs + names + current party with HP)
        #allies_data = allies.map do |a|
        #  {
        #    sid: a[:sid].to_s,
        #    name: a[:name].to_s,
        #    party: a[:party]
        #  }
        #end
        #
        #invite_payload = {
        #  foes: foe_party,
        #  allies: allies_data,
        #  encounter_type: encounter_type,
        #  battle_id: battle_id
        #}
        #
        #raw = Marshal.dump(invite_payload)
        #hex = BinHex.encode(raw) if defined?(BinHex)
        #
        #unless hex && hex.length > 0
        #  if defined?(MultiplayerDebug)
        #    MultiplayerDebug.error(TAG, "BinHex encoding failed")
        #  end
        #  return
        #end
        #
        #MultiplayerClient.send_data("COOP_BTL_START:#{hex}")
        #
        #if defined?(MultiplayerDebug)
        #  MultiplayerDebug.info(TAG, "  Sent COOP_BTL_START (Marshal fallback)")
        #  MultiplayerDebug.info(TAG, "BROADCAST BATTLE INVITE END (Marshal)")
        #  MultiplayerDebug.info(TAG, "=" * 70)
        #end
      end

      # Note: If another player started first, server auto-joins us to their battle
      # Server sends COOP_BTL_START from first initiator, our client handles it like normal invite
    rescue => e
      ##MultiplayerDebug.error(TAG, "broadcast_battle_invite ERROR: #{e.class}: #{e.message}#{CoopLogUtil.bt(e)}")
    end
  end

  # Returns up to 'limit' eligible nearby squadmates with non-empty parties.
  # [{ sid:, name:, party:[Pokemon] }, ...]
  def self.pick_nearby_allies(limit = 2)
    out = []
    begin
      unless defined?(MultiplayerClient) && MultiplayerClient.instance_variable_get(:@connected) && MultiplayerClient.in_squad?
        ##MultiplayerDebug.info(TAG, "Not connected/in squad → no allies.")
        return out
      end
      unless MultiplayerClient.respond_to?(:remote_party)
        ##MultiplayerDebug.error(TAG, "MultiplayerClient.remote_party missing.")
        return out
      end

      squad   = MultiplayerClient.squad
      my_sid  = MultiplayerClient.session_id.to_s
      my_map  = ($game_map.map_id rescue nil)
      my_x    = ($game_player.x   rescue nil)
      my_y    = ($game_player.y   rescue nil)
      players = (MultiplayerClient.players rescue {}) || {}

      (squad[:members] || []).each_with_index do |m, idx|
        sid  = (m[:sid]  || "").to_s
        name = (m[:name] || "ALLY").to_s
        next if sid.empty? || sid == my_sid

        pinfo     = players[sid] rescue nil
        same_map  = pinfo && pinfo[:map].to_i == my_map.to_i
        dx        = (pinfo ? pinfo[:x].to_i : 9999) - (my_x || 0)
        dy        = (pinfo ? pinfo[:y].to_i : 9999) - (my_y || 0)
        dist      = dx.abs + dy.abs
        in_range  = dist <= 12

        # Check busy flag
        busy = begin
          if MultiplayerClient.respond_to?(:player_busy?)
            MultiplayerClient.player_busy?(sid)
          else
            (pinfo && pinfo[:busy].to_i == 1)
          end
        rescue
          false
        end

        ##MultiplayerDebug.info(TAG, "scan idx=#{idx} sid=#{sid} name=#{name} map_ok=#{same_map} dist=#{dist} in_range=#{in_range} busy=#{busy}")
        next unless same_map && in_range && !busy

        party = MultiplayerClient.remote_party(sid)
        unless party.is_a?(Array) && party.all? { |p| p.is_a?(Pokemon) }
          ##MultiplayerDebug.warn(TAG, "remote_party invalid for #{sid}")
          next
        end
        if party.empty?
          ##MultiplayerDebug.info(TAG, "remote_party empty for #{sid}")
          next
        end

        # Debug: Log party snapshot being used
        ##MultiplayerDebug.info("PARTY-USAGE", "=" * 70)
        ##MultiplayerDebug.info("PARTY-USAGE", "Using cached party for ally SID#{sid}")
        ##MultiplayerDebug.info("PARTY-USAGE", "  Party size: #{party.length}")
        party.each_with_index do |pkmn, i|
          if pkmn
            ##MultiplayerDebug.info("PARTY-USAGE", "  [#{i}] #{pkmn.name} Lv.#{pkmn.level} HP=#{pkmn.hp}/#{pkmn.totalhp} EXP=#{pkmn.exp}")
          else
            ##MultiplayerDebug.info("PARTY-USAGE", "  [#{i}] nil")
          end
        end
        ##MultiplayerDebug.info("PARTY-USAGE", "=" * 70)

        out << { sid: sid, name: name, party: party }
        break if out.length >= limit
      end
    rescue => e
      ##MultiplayerDebug.error(TAG, "pick_nearby_allies ERROR #{e.class}: #{e.message}#{CoopLogUtil.bt(e)}")
    end
    ##MultiplayerDebug.info(TAG, "Found #{out.length} eligible allies")
    out
  end

  # Handle received battle invitation (non-initiator joins battle)
  def self._handle_coop_battle_join(invite)
    begin
      ##MultiplayerDebug.info(TAG, "JOIN: Entering battle from #{invite[:from_sid]}")

      # Check if transaction was cancelled before we start
      if defined?(CoopBattleTransaction) && CoopBattleTransaction.cancelled?
        if defined?(MultiplayerDebug)
          MultiplayerDebug.warn(TAG, "JOIN: Battle transaction cancelled, aborting join")
        end
        CoopBattleTransaction.reset
        return
      end

      # Join the transaction (thread-safe tracking)
      if defined?(CoopBattleTransaction) && invite[:battle_id]
        CoopBattleTransaction.join(invite[:battle_id], invite[:from_sid].to_s)
      end

      # === VALIDATE INVITATION ===
      unless invite[:foes].is_a?(Array) && invite[:foes].length > 0
        ##MultiplayerDebug.error(TAG, "JOIN: Invalid foes data")
        return
      end
      unless invite[:allies].is_a?(Array) && invite[:allies].length > 0
        ##MultiplayerDebug.error(TAG, "JOIN: Invalid allies data")
        return
      end

      # === USE FOE PARTY FROM INVITATION ===
      # Foes are now serialized as complete Pokemon objects (not just species/level)
      # This ensures all players fight the exact same wild Pokemon
      foeParty = invite[:foes]
      unless foeParty.is_a?(Array) && foeParty.all? { |p| p.is_a?(Pokemon) }
        ##MultiplayerDebug.error(TAG, "JOIN: Invalid foes data (expected Array<Pokemon>)")
        return
      end

      if foeParty.empty?
        ##MultiplayerDebug.error(TAG, "JOIN: No foes in invitation")
        return
      end

      ##MultiplayerDebug.info(TAG, "JOIN: Received #{foeParty.length} foes from initiator")
      foeParty.each_with_index do |pkmn, i|
        ##MultiplayerDebug.info(TAG, "JOIN: Foe #{i+1}: #{CoopLogUtil.dex_name(pkmn)}")
      end

      # === FIND MY ROLE IN THIS BATTLE ===
      my_sid = MultiplayerClient.session_id.to_s
      my_ally_entry = invite[:allies].find { |a| a[:sid].to_s == my_sid }

      unless my_ally_entry
        ##MultiplayerDebug.warn(TAG, "JOIN: I'm not in the ally list (sid=#{my_sid}), aborting")
        return
      end

      # === RECONSTRUCT PLAYER SIDE ===
      # Allies list from invite includes the initiator + other allies
      # We need to put the initiator first, then add allies including ourselves

      trainer_type = :YOUNGSTER
      playerTrainers = []
      playerParty = []
      playerPartyStarts = []

      # Find initiator (should be in allies list or is the from_sid)
      initiator_sid = invite[:from_sid].to_s
      initiator_entry = invite[:allies].find { |a| a[:sid].to_s == initiator_sid }

      # Add initiator first
      if initiator_entry
        # Use party from invite (has current HP), fallback to cached remote_party
        initiator_party = initiator_entry[:party] || MultiplayerClient.remote_party(initiator_sid)
        if !initiator_party || initiator_party.empty?
          ##MultiplayerDebug.warn(TAG, "JOIN: Initiator party empty (#{initiator_sid}), using placeholder")
          # Can't proceed without initiator's party
          return
        end

        npc = NPCTrainer.new(initiator_entry[:name].to_s, trainer_type)
        npc.id = initiator_sid  # Keep for RNG sync and other systems
        npc.multiplayer_sid = initiator_sid  # For coop capture SID tracking
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

        start_idx = playerParty.length
        playerTrainers << npc
        playerPartyStarts << start_idx

        # Add party with padding to MAX_PARTY_SIZE (6 slots)
        max_size = defined?(Settings::MAX_PARTY_SIZE) ? Settings::MAX_PARTY_SIZE : 6
        initiator_party.each { |p| playerParty << p }
        (max_size - initiator_party.length).times { playerParty << nil }

        ##MultiplayerDebug.info(TAG, "JOIN: Added initiator: name=#{initiator_entry[:name]} sid=#{initiator_sid} mons=#{initiator_party.length}")
      end

      # Add other allies (including myself)
      invite[:allies].each do |ally_data|
        sid = ally_data[:sid].to_s
        name = ally_data[:name].to_s
        next if sid == initiator_sid # Already added initiator

        # Get party (for myself, use $Trainer.party; for others, use party from invite with current HP)
        if sid == my_sid
          party = $Trainer.party rescue []
          ##MultiplayerDebug.info(TAG, "JOIN: Adding self: sid=#{sid} mons=#{party.length}")
        else
          # Use party from invite (has current HP), fallback to cached remote_party
          party = ally_data[:party] || MultiplayerClient.remote_party(sid)
          if !party || party.empty?
            ##MultiplayerDebug.warn(TAG, "JOIN: Skipping ally #{sid} (no party data)")
            next
          end
          ##MultiplayerDebug.info(TAG, "JOIN: Adding ally: name=#{name} sid=#{sid} mons=#{party.length}")
        end

        next if party.empty?

        start_idx = playerParty.length

        if sid == my_sid
          # Use real trainer for myself
          playerTrainers << $Trainer
        else
          # Use NPC for remote ally
          npc = NPCTrainer.new(name, trainer_type)
          npc.id = sid  # Keep for RNG sync and other systems
          npc.multiplayer_sid = sid  # For coop capture SID tracking
          npc.party = party

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

          playerTrainers << npc
        end

        playerPartyStarts << start_idx

        # Add party with padding to MAX_PARTY_SIZE (6 slots)
        max_size = defined?(Settings::MAX_PARTY_SIZE) ? Settings::MAX_PARTY_SIZE : 6
        party.each { |p| playerParty << p }
        (max_size - party.length).times { playerParty << nil }
      end

      ##MultiplayerDebug.info(TAG, "JOIN: Total trainers=#{playerTrainers.length} party_size=#{playerParty.length}")

      # === SET BATTLE RULES ===
      battle_size = playerTrainers.length
      if battle_size >= 3
        setBattleRule("triple")
        ##MultiplayerDebug.info(TAG, "JOIN: Set battle rule: TRIPLE")
      elsif battle_size >= 2
        setBattleRule("double")
        ##MultiplayerDebug.info(TAG, "JOIN: Set battle rule: DOUBLE")
      end

      # === CREATE BATTLE ===
      $PokemonTemp.encounterType = invite[:encounter_type] if invite[:encounter_type]
      scene = pbNewBattleScene
      battle = PokeBattle_Battle.new(scene, playerParty, foeParty, playerTrainers, nil)
      battle.party1starts = playerPartyStarts

      # Clear any stale RNG seeds from buffer
      if defined?(CoopRNGSync)
        CoopRNGSync.reset_sync_state
        ##MultiplayerDebug.info("COOP-BATTLE-START", "Cleared RNG seed buffer for new battle (non-initiator)")
      end

      # CRITICAL FIX: Sync RNG seed IMMEDIATELY after battle creation
      # This prevents desyncs from encounter_triggered? being called different number of times
      # Use turn -1 to indicate "battle start" seed (before turn 0)
      if defined?(CoopRNGSync) && defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
        ##MultiplayerDebug.info("COOP-RNG-INIT", "Syncing initial RNG seed (non-initiator)...")
        success = CoopRNGSync.sync_seed_as_receiver(battle, -1, 5, true)
        unless success
          ##MultiplayerDebug.error("COOP-RNG-INIT", "Failed to sync initial RNG seed!")
        end
      end

      ##MultiplayerDebug.info(TAG, "JOIN: Battle created: trainers=#{playerTrainers.length} party1starts=#{playerPartyStarts.inspect}")

      pbPrepareBattle(battle)
      $PokemonTemp.clearBattleRules

      # Defensive: Initialize heart_gauges if not set by onStartBattle event
      if defined?($PokemonTemp) && !$PokemonTemp.heart_gauges
        $PokemonTemp.heart_gauges = []
        $Trainer.party.each_with_index { |pkmn, i| $PokemonTemp.heart_gauges[i] = pkmn.heart_gauge if pkmn }
        ##MultiplayerDebug.info(TAG, "JOIN: Initialized heart_gauges defensively")
      end

      # Mark busy
      if defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:mark_battle)
        MultiplayerClient.mark_battle(true)
        ##MultiplayerDebug.info(TAG, "JOIN: Marked battle busy=true")
      end

      # === SEND BATTLE JOINED MESSAGE ===
      # Tell the initiator (and other allies) that we've entered the battle
      begin
        initiator_sid = invite[:from_sid].to_s
        if defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:send_data)
          MultiplayerClient.send_data("COOP_BATTLE_JOINED:#{initiator_sid}")
          ##MultiplayerDebug.info(TAG, "JOIN: Sent COOP_BATTLE_JOINED to initiator #{initiator_sid}")
        end
      rescue => e
        ##MultiplayerDebug.warn(TAG, "JOIN: Failed to send COOP_BATTLE_JOINED: #{e.message}")
      end

      # === WAIT FOR OTHER NON-INITIATORS TO JOIN ===
      # Non-initiators should wait for OTHER non-initiators who haven't joined yet
      # Don't wait for the initiator (they've already started and are waiting for us)
      my_sid = MultiplayerClient.session_id.to_s
      initiator_sid = invite[:from_sid].to_s

      # Filter out: myself, initiator, and anyone who has already sent COOP_BATTLE_JOINED
      joined_sids = MultiplayerClient.instance_variable_get(:@coop_battle_joined_sids) || []
      other_non_initiators = (invite[:allies] || []).select do |a|
        sid = a[:sid].to_s
        sid != my_sid && sid != initiator_sid && !joined_sids.include?(sid)
      end

      if other_non_initiators.length > 0
        ##MultiplayerDebug.info(TAG, "JOIN: Waiting for #{other_non_initiators.length} other non-initiators to join...")
        expected_allies_for_sync = other_non_initiators.map { |a| { sid: a[:sid], name: a[:name] } }

        # Show sync screen and wait
        all_joined = pbCoopWaitForAllies(expected_allies_for_sync)

        unless all_joined
          ##MultiplayerDebug.warn(TAG, "JOIN: Not all non-initiators joined → fallback to solo battle")
          # Reset transaction state
          CoopBattleTransaction.reset if defined?(CoopBattleTransaction)
          # Clear busy flag
          MultiplayerClient.mark_battle(false) if defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:mark_battle)

          # SOLO FALLBACK: Fight the first foe alone instead of aborting
          # This prevents the non-initiator from being stuck with no battle
          if foeParty && foeParty.length > 0
            solo_foe = [foeParty.first]  # Just fight the first Pokemon
            if defined?(MultiplayerDebug)
              MultiplayerDebug.info(TAG, "JOIN: Starting solo battle against #{solo_foe.first.name rescue 'unknown'}")
            end
            $PokemonTemp.encounterType = invite[:encounter_type]
            pbWildBattleCore(*solo_foe)
          end

          $PokemonTemp.encounterType = nil
          $PokemonTemp.forceSingleBattle = false
          return
        end

        ##MultiplayerDebug.info(TAG, "JOIN: All non-initiators synced! Starting co-op battle")
      else
        ##MultiplayerDebug.info(TAG, "JOIN: No other non-initiators to wait for - starting battle")
      end

      # === INITIALIZE BATTLE STATE TRACKING (Non-Initiator) ===
      if defined?(CoopBattleState)
        # Extract ally info from invitation
        ally_sids = (invite[:allies] || []).map { |a| a[:sid].to_s }.reject { |sid| sid == MultiplayerClient.session_id.to_s }
        ally_names_hash = Hash[(invite[:allies] || []).map { |a| [a[:sid].to_s, a[:name].to_s] }]

        received_battle_id = invite[:battle_id]
        ##MultiplayerDebug.info(TAG, "JOIN: Received battle ID from invite: #{received_battle_id.inspect}")

        CoopBattleState.create_battle(
          is_initiator: false,
          ally_sids: ally_sids,
          battle_id: received_battle_id,  # Received from initiator
          ally_names: ally_names_hash,
          encounter_type: invite[:encounter_type],
          map_id: ($game_map.map_id rescue nil),
          foe_count: foeParty.length
        )

        ##MultiplayerDebug.info(TAG, "JOIN: Battle state initialized (Non-Initiator): #{CoopBattleState.battle_id}")

        # Register battle instance for run away sync
        CoopBattleState.register_battle_instance(battle)
        ##MultiplayerDebug.info(TAG, "JOIN: Battle instance registered with CoopBattleState")
      end

      # === RUN BATTLE ===
      decision = 0
      canLose = false

      begin
        pbBattleAnimation(pbGetWildBattleBGM(foeParty), (foeParty.length == 1) ? 0 : 2, foeParty) {
          pbSceneStandby {
            decision = battle.pbStartBattle
          }
          pbAfterBattle(decision, canLose)
        }
      rescue => e
        # CRASH PROTECTION: Default to forfeit (draw) instead of win on error
        if defined?(MultiplayerDebug)
          MultiplayerDebug.error(TAG, "JOIN: Battle crashed! #{e.class}: #{e.message}")
          MultiplayerDebug.error(TAG, "JOIN: Backtrace: #{e.backtrace.first(5).join("\n")}")
        end
        decision = 3  # Forfeit/draw - not a win
        pbMessage(_INTL("The battle ended due to an error."))
      end
      Input.update

      ##MultiplayerDebug.info(TAG, "JOIN: Battle ended: decision=#{decision}")

      # Remove nil entries from $Trainer.party (leftover from coop battle padding)
      # This prevents crashes in egg hatching and other systems that iterate over party
      $Trainer.party.compact!
      ##MultiplayerDebug.info(TAG, "JOIN: Cleaned party - removed nil padding")

      # Clear busy flag
      if defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:mark_battle)
        MultiplayerClient.mark_battle(false)
        ##MultiplayerDebug.info(TAG, "JOIN: Marked battle busy=false")
      end

      # === CLEANUP ===
      $PokemonTemp.encounterType = nil
      $PokemonTemp.encounterTriggered = true
      $PokemonTemp.forceSingleBattle = false
      EncounterModifier.triggerEncounterEnd if defined?(EncounterModifier)

      return decision

    rescue => e
      ##MultiplayerDebug.error(TAG, "JOIN CRASH: #{e.class}: #{e.message}#{CoopLogUtil.bt(e)}")
      # Ensure busy flag cleared even on crash
      begin
        if defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:mark_battle) && MultiplayerClient.in_battle?
          MultiplayerClient.mark_battle(false)
          ##MultiplayerDebug.info(TAG, "JOIN: Ensured busy=false after error")
        end
      rescue; end
      return nil
    end
  end

  # Generate additional foes to match target_size, avoiding duplicate species
  def self.expand_foes!(foe_party, target_size, encounter_type)
    return unless foe_party.is_a?(Array)
    target_size = [[target_size, 1].max, 3].min
    ##MultiplayerDebug.info(TAG, "Expanding foes: current=#{foe_party.length} target=#{target_size}")

    existing_species = foe_party.map { |p| p.species rescue nil }.compact
    attempts = 0
    max_attempts = 20

    while foe_party.length < target_size && attempts < max_attempts
      attempts += 1

      # Try to generate a new encounter
      begin
        extra_encounter = kurayEncounterInit(encounter_type) if defined?(kurayEncounterInit)
        if !extra_encounter && defined?($PokemonEncounters)
          extra_encounter = $PokemonEncounters.choose_wild_pokemon(encounter_type)
        end

        if extra_encounter && extra_encounter[0] && extra_encounter[1]
          extra_encounter = EncounterModifier.trigger(extra_encounter) if defined?(EncounterModifier)
          extra_pkmn = pbGenerateWildPokemon(extra_encounter[0], extra_encounter[1])

          # Check for duplicate species
          if existing_species.include?(extra_pkmn.species)
            ##MultiplayerDebug.info(TAG, "  Attempt #{attempts}: duplicate species #{extra_pkmn.species} → retry")
            next
          end

          foe_party << extra_pkmn
          existing_species << extra_pkmn.species
          ##MultiplayerDebug.info(TAG, "  Added foe #{foe_party.length}/#{target_size}: #{CoopLogUtil.dex_name(extra_pkmn)}")
        else
          # Fallback: clone first foe's species at different level
          base = foe_party[0]
          if base
            level_offset = rand(3) - 1 # -1, 0, or +1
            new_level = [[base.level + level_offset, 1].max, 100].min
            extra_pkmn = pbGenerateWildPokemon(base.species, new_level)
            foe_party << extra_pkmn
            existing_species << extra_pkmn.species
            ##MultiplayerDebug.info(TAG, "  Fallback clone: #{CoopLogUtil.dex_name(extra_pkmn)}")
          end
        end
      rescue => e
        ##MultiplayerDebug.warn(TAG, "  Foe generation attempt #{attempts} failed: #{e.class}: #{e.message}")
        # Last resort: clone first foe
        if foe_party[0] && foe_party.length < target_size
          cloned = pbGenerateWildPokemon(foe_party[0].species, foe_party[0].level)
          foe_party << cloned
          ##MultiplayerDebug.info(TAG, "  Emergency clone added")
        end
      end
    end

    if foe_party.length < target_size
      ##MultiplayerDebug.warn(TAG, "Could not reach target size (#{foe_party.length}/#{target_size})")
    end
  end
end

# ----- Re-entrancy guard -----
$__coop_wild_hook_v2_running = false unless defined?($__coop_wild_hook_v2_running)

# ----- Global Events hook (mark busy for ALL battles) -----
unless defined?($__coop_busy_flag_events_installed)
  $__coop_busy_flag_events_installed = true
  begin
    if defined?(Events) && !$__kif_busy_hooks_installed
      $__kif_busy_hooks_installed = true
      Events.onStartBattle += proc { |_s,_| MultiplayerClient.mark_battle(true) if defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:mark_battle) }
      if Events.respond_to?(:onEndBattle)
        Events.onEndBattle += proc { |_s,_| MultiplayerClient.mark_battle(false) if defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:mark_battle) }
      end
      ##MultiplayerDebug.info("COOP-V2", "Installed global busy flag handlers on Events.")
    end
  rescue => e
    ##MultiplayerDebug.warn("COOP-V2", "Failed installing global busy flag handlers: #{e.class}: #{e.message}")
  end
end

# ===========================================
# === Hook pbBattleOnStepTaken (NEW APPROACH)
# ===========================================
if defined?(Kernel) && (method(:pbBattleOnStepTaken) rescue true)
  unless defined?(pbBattleOnStepTaken_vanilla_for_coop)
    ##MultiplayerDebug.info("COOP-V2", "Aliasing vanilla pbBattleOnStepTaken → pbBattleOnStepTaken_vanilla_for_coop")
    alias pbBattleOnStepTaken_vanilla_for_coop pbBattleOnStepTaken
  end

  def pbBattleOnStepTaken(repel_active)
    # Re-entrancy guard
    if $__coop_wild_hook_v2_running
      ##MultiplayerDebug.warn("COOP-V2", "Re-entry detected → VANILLA")
      return pbBattleOnStepTaken_vanilla_for_coop(repel_active)
    end
    $__coop_wild_hook_v2_running = true

    begin
      # Check if co-op is possible
      coop_ok = defined?(MultiplayerClient) &&
                MultiplayerClient.instance_variable_get(:@connected) &&
                MultiplayerClient.in_squad?

      ##MultiplayerDebug.info("COOP-V2", "HOOK ENTER coop_ok=#{coop_ok}")

      # === CHECK FOR PENDING BATTLE INVITATION (non-initiators) ===
      if coop_ok && defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:coop_battle_pending?) && MultiplayerClient.coop_battle_pending?
        invite = MultiplayerClient.dequeue_coop_battle
        if invite
          ##MultiplayerDebug.info("COOP-V2", "Processing battle invitation from #{invite[:from_sid]}")
          return CoopWildHook._handle_coop_battle_join(invite)
        end
      end

      if !coop_ok
        ##MultiplayerDebug.info("COOP-V2", "No co-op context → vanilla")
        return pbBattleOnStepTaken_vanilla_for_coop(repel_active)
      end

      # === PREVENT CASCADING ENCOUNTERS ===
      # If we're already in a battle transaction (joining another player's battle),
      # don't trigger a new encounter - it would cause state confusion
      if defined?(CoopBattleTransaction) && CoopBattleTransaction.active?
        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("COOP-V2", "Already in battle transaction - ignoring new encounter")
        end
        return
      end

      # === VANILLA PREFLIGHT CHECKS (copied from original) ===
      return if $Trainer.able_pokemon_count == 0
      return if !$PokemonEncounters.encounter_possible_here?
      encounter_type = $PokemonEncounters.encounter_type
      return if !encounter_type
      return if !$PokemonEncounters.encounter_triggered?(encounter_type, repel_active)

      ##MultiplayerDebug.info("COOP-V2", "Encounter triggered: type=#{encounter_type}")
      # Defensive: Clear my own busy flag if stuck from previous battle/crash
      # This must happen BEFORE ally detection, otherwise we might still be marked busy from a crash
      begin
        if defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:in_battle?) && MultiplayerClient.respond_to?(:mark_battle)
          if MultiplayerClient.in_battle?
            ##MultiplayerDebug.warn("COOP-V2", "Clearing stuck busy flag from previous battle")
            MultiplayerClient.mark_battle(false)
          end
        end
      rescue => e
        ##MultiplayerDebug.warn("COOP-V2", "Failed to clear busy flag: #{e.message}")
      end

      # === SIMULTANEOUS INITIATOR CHECK ===
      # Before initiating, check if we just received an invite from another player
      # If so, defer to their battle instead of creating a competing one
      if defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:coop_battle_pending?) && MultiplayerClient.coop_battle_pending?
        invite = MultiplayerClient.dequeue_coop_battle
        if invite
          if defined?(MultiplayerDebug)
            MultiplayerDebug.info("COOP-V2", "Simultaneous initiator detected - deferring to #{invite[:from_sid]}'s battle")
          end
          return CoopWildHook._handle_coop_battle_join(invite)
        end
      end

      # Check for nearby allies FIRST (before waiting)
      # This prevents unnecessary 500ms wait when player is alone in squad
      allies = CoopWildHook.pick_nearby_allies(2)
      ally_count = allies.length

      if ally_count == 0
        # No allies → launch vanilla battle immediately (no wait)
        ##MultiplayerDebug.info("COOP-V2", "No eligible allies → vanilla (no wait)")
        $PokemonTemp.forceSingleBattle = true
        return pbBattleOnStepTaken_vanilla_for_coop(repel_active)
      end

      # Push initiator's party snapshot FIRST before nudging allies
      # This ensures allies have fresh snapshot of initiator's party before battle starts
      begin
        MultiplayerClient.coop_push_party_now! if MultiplayerClient.respond_to?(:coop_push_party_now!)
        ##MultiplayerDebug.info("COOP-V2", "Pushed initiator party snapshot before battle")
      rescue => e
        ##MultiplayerDebug.warn("COOP-V2", "Failed to push initiator snapshot: #{e.message}")
      end

      # We have allies - nudge them to push party snapshots (non-blocking)
      ally_sids = allies.map { |a| a[:sid].to_s }

      # CRITICAL: Clear cached parties for allies BEFORE nudging
      # This forces wait loop to actually wait for FRESH data instead of using stale cache
      ally_sids.each do |sid|
        old_party = MultiplayerClient.instance_variable_get(:@coop_remote_party)[sid.to_s]
        MultiplayerDebug.info("COOP-V2-CACHE", "Clearing cached party for #{sid}: had #{old_party ? old_party.length : 0} Pokemon") if defined?(MultiplayerDebug)
        MultiplayerClient.instance_variable_get(:@coop_remote_party).delete(sid.to_s)
      end
      MultiplayerDebug.info("COOP-V2", "Cleared #{ally_sids.length} cached parties before nudge") if defined?(MultiplayerDebug)

      begin
        MultiplayerClient.send_data("COOP_PARTY_PUSH_NOW:")
        ##MultiplayerDebug.info("COOP-V2", "Sent COOP_PARTY_PUSH_NOW nudge to #{ally_count} allies")
        SnapshotLog.log_nudge_sent(ally_sids) if defined?(SnapshotLog)
      rescue => e
        ##MultiplayerDebug.warn("COOP-V2", "Nudge failed: #{e.message}")
      end

      # Wait for fresh party data to arrive (2000ms = ~120 frames at 60 FPS)
      # This gives allies time to respond to the nudge before we snapshot their party
      wait_frames = 120
      wait_start_time = Time.now
      early_exit = false
      SnapshotLog.log_wait_start(ally_sids) if defined?(SnapshotLog)

      wait_frames.times do |frame|
        Graphics.update if defined?(Graphics)
        Input.update if defined?(Input)
        sleep(0.016)  # ~16ms per frame

        # Check if battle was cancelled by another player
        if defined?(CoopBattleTransaction) && CoopBattleTransaction.cancelled?
          if defined?(MultiplayerDebug)
            MultiplayerDebug.warn("COOP-V2", "Battle cancelled during party wait - aborting")
          end
          CoopBattleTransaction.reset
          MultiplayerClient.mark_battle(false) if defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:mark_battle)
          return
        end

        # Allow ESC to cancel during party wait (before sync screen)
        if Input.trigger?(Input::BACK)
          if defined?(MultiplayerDebug)
            MultiplayerDebug.info("COOP-V2", "User cancelled during party wait - broadcasting cancel")
          end
          CoopBattleTransaction.cancel("user_cancelled") if defined?(CoopBattleTransaction)
          MultiplayerClient.mark_battle(false) if defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:mark_battle)
          return pbBattleOnStepTaken_vanilla_for_coop(repel_active)
        end

        # Check if all parties are ready (early exit)
        all_ready = ally_sids.all? do |sid|
          party = MultiplayerClient.remote_party(sid) rescue []
          has_data = party && !party.empty?

          # Debug first 5 frames
          if frame < 5 && defined?(MultiplayerDebug)
            family_info = if has_data && party[0].respond_to?(:family)
              "Family=#{party[0].family}"
            else
              "no data"
            end
            MultiplayerDebug.info("COOP-V2-WAIT", "Frame #{frame}: SID#{sid} #{family_info}")
          end

          has_data
        end

        if all_ready
          actual_wait_ms = ((Time.now - wait_start_time) * 1000).round
          MultiplayerDebug.info("COOP-V2", "All #{ally_sids.length} snapshots ready in #{actual_wait_ms}ms (early exit)") if defined?(MultiplayerDebug)

          # Log what we got
          ally_sids.each do |sid|
            party = MultiplayerClient.remote_party(sid) rescue []
            if party && party[0] && party[0].respond_to?(:family)
              MultiplayerDebug.info("COOP-V2-FINAL", "Using party from SID#{sid}: #{party[0].name} Family=#{party[0].family}") if defined?(MultiplayerDebug)
            end
          end

          SnapshotLog.log_wait_complete(actual_wait_ms, ally_sids.length, ally_sids.length, false) if defined?(SnapshotLog)
          early_exit = true
          break
        end

        # Log snapshot status every 30 frames (500ms)
        if defined?(SnapshotLog) && frame % 30 == 0
          ready_sids = []
          pending_sids = []
          ally_sids.each do |sid|
            party = MultiplayerClient.remote_party(sid) rescue []
            if party && !party.empty?
              ready_sids << sid
            else
              pending_sids << sid
            end
          end
          elapsed_ms = ((Time.now - wait_start_time) * 1000).round
          SnapshotLog.log_wait_check(frame, ready_sids, pending_sids, elapsed_ms)
        end
      end

      # Log wait completion (only if didn't early exit)
      if !early_exit && defined?(SnapshotLog)
        total_ms = ((Time.now - wait_start_time) * 1000).round
        ready_count = ally_sids.count do |sid|
          party = MultiplayerClient.remote_party(sid) rescue []
          party && !party.empty?
        end
        timed_out = ready_count < ally_sids.length
        SnapshotLog.log_wait_complete(total_ms, ready_count, ally_sids.length, timed_out)
      end

      # CRITICAL: Refresh ally party data with fresh cache after wait
      # The allies array was built BEFORE the cache clear, so it has stale party references
      allies.each do |ally|
        fresh_party = MultiplayerClient.remote_party(ally[:sid]) rescue []
        if fresh_party && !fresh_party.empty?
          ally[:party] = fresh_party
          MultiplayerDebug.info("COOP-V2-REFRESH", "Refreshed party for #{ally[:sid]}: #{fresh_party[0].name} Family=#{fresh_party[0].respond_to?(:family) ? fresh_party[0].family : 'N/A'}") if defined?(MultiplayerDebug)
        else
          MultiplayerDebug.warn("COOP-V2-REFRESH", "Failed to refresh party for #{ally[:sid]} - using stale data") if defined?(MultiplayerDebug)
        end
      end

      ##MultiplayerDebug.info("COOP-V2", "Co-op battle starting with #{ally_count} allies")

      # === SET ENCOUNTER TYPE ===
      $PokemonTemp.encounterType = encounter_type

      # === GENERATE FIRST FOE (like vanilla does) ===
      encounter = kurayEncounterInit(encounter_type)
      $game_switches[SWITCH_FORCE_FUSE_NEXT_POKEMON] = false if defined?(SWITCH_FORCE_FUSE_NEXT_POKEMON)
      encounter = EncounterModifier.trigger(encounter) if defined?(EncounterModifier)

      # Check if encounter is allowed
      if defined?($PokemonEncounters) && $PokemonEncounters.respond_to?(:allow_encounter?)
        if !$PokemonEncounters.allow_encounter?(encounter, repel_active)
          ##MultiplayerDebug.info("COOP-V2", "Encounter not allowed → aborting")
          $PokemonTemp.encounterType = nil
          $PokemonTemp.forceSingleBattle = false
          EncounterModifier.triggerEncounterEnd if defined?(EncounterModifier)
          return
        end
      end

      # Build foe party
      foeParty = []
      first_foe = pbGenerateWildPokemon(encounter[0], encounter[1])
      # IMPORTANT: Force shiny calculation and cache it BEFORE sending to allies
      # This prevents desync due to different trainer IDs on different clients
      first_foe.shiny?  # Forces @shiny to be set based on initiator's trainer ID
      foeParty << first_foe
      ##MultiplayerDebug.info("COOP-V2", "First foe: #{CoopLogUtil.dex_name(first_foe)} shiny=#{first_foe.shiny?}")

      # Expand foes to match player count
      total_players = 1 + ally_count
      CoopWildHook.expand_foes!(foeParty, total_players, encounter_type)

      # Force shiny calculation for all expanded foes too
      foeParty.each { |pkmn| pkmn.shiny? if pkmn }

      # === BROADCAST BATTLE INVITATION TO ALLIES ===
      # Build complete participant list: initiator + allies
      my_party = ($Trainer.party rescue [])
      my_info = {
        sid: MultiplayerClient.session_id.to_s,
        name: (defined?($Trainer) && $Trainer && $Trainer.respond_to?(:name) ? $Trainer.name : "Host").to_s,
        party: my_party
      }
      all_participants = [my_info] + allies

      # Generate battle ID before broadcasting (initiator generates, others receive)
      battle_id = nil
      if defined?(CoopBattleState)
        battle_id = CoopBattleState.generate_battle_id
        ##MultiplayerDebug.info("COOP-V2", "Generated battle ID: #{battle_id.inspect}")
        ##MultiplayerDebug.info("COOP-V2", "Broadcasting battle ID to allies: #{battle_id.inspect}")
      else
        ##MultiplayerDebug.error("COOP-V2", "CoopBattleState NOT DEFINED! Cannot generate battle ID")
      end

      # Start battle transaction (thread-safe coordination)
      ally_sids = allies.map { |a| a[:sid].to_s }
      if defined?(CoopBattleTransaction)
        CoopBattleTransaction.start(battle_id, ally_sids)
      end

      ##MultiplayerDebug.info("COOP-V2", "About to broadcast with battle_id=#{battle_id.inspect}")
      CoopWildHook.broadcast_battle_invite(foeParty, all_participants, encounter_type, battle_id)
      ##MultiplayerDebug.info("COOP-V2", "Broadcasted battle invite with ID: #{battle_id.inspect}")

      # Note: If another player started first, server auto-joins us to their battle
      # Our encounter gets cancelled and we join theirs as non-initiator

      # Clear initiator's own pending invites (battle is starting)
      if defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:clear_pending_battle_invites)
        MultiplayerClient.clear_pending_battle_invites
      end

      # === BUILD PLAYER SIDE ===
      trainer_type = :YOUNGSTER
      playerTrainers = [$Trainer]
      playerParty = []
      max_size = defined?(Settings::MAX_PARTY_SIZE) ? Settings::MAX_PARTY_SIZE : 6
      $Trainer.party.each { |p| playerParty << p }
      (max_size - $Trainer.party.length).times { playerParty << nil }
      playerPartyStarts = [0]

      ##MultiplayerDebug.info("COOP-V2", "Player party: #{$Trainer.party.length} Pokémon")

      # Add allies
      allies.each_with_index do |ally, i|
        start_idx = playerParty.length

        # Log party HP for debugging
        ##MultiplayerDebug.info("COOP-V2", "Ally ##{i+1} party HP before battle:")
        ally[:party].each_with_index do |pkmn, pi|
          if pkmn
            ##MultiplayerDebug.info("COOP-V2", "  Mon #{pi+1}: #{CoopLogUtil.dex_name(pkmn)}")
          end
        end

        npc = NPCTrainer.new(ally[:name].to_s, trainer_type)
        npc.id = ally[:sid].to_s  # Keep for RNG sync and other systems
        npc.multiplayer_sid = ally[:sid].to_s  # For coop capture SID tracking
        npc.party = ally[:party]

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
        def npc.badge_count; 0; end

        playerTrainers << npc
        playerPartyStarts << start_idx

        # Add party with padding to MAX_PARTY_SIZE (6 slots)
        max_size = defined?(Settings::MAX_PARTY_SIZE) ? Settings::MAX_PARTY_SIZE : 6
        ally[:party].each { |p| playerParty << p }
        (max_size - ally[:party].length).times { playerParty << nil }

        ##MultiplayerDebug.info("COOP-V2", "Added ally ##{i+1}: name=#{ally[:name]} sid=#{ally[:sid]} mons=#{ally[:party].length} start=#{start_idx}")
      end

      # === SET BATTLE RULES ===
      desired_size = [[1 + ally_count, 1].max, 3].min
      if desired_size >= 3
        setBattleRule("triple")
        ##MultiplayerDebug.info("COOP-V2", "Set battle rule: TRIPLE")
      elsif desired_size >= 2
        setBattleRule("double")
        ##MultiplayerDebug.info("COOP-V2", "Set battle rule: DOUBLE")
      end

      # === CREATE BATTLE ===
      scene = pbNewBattleScene
      battle = PokeBattle_Battle.new(scene, playerParty, foeParty, playerTrainers, nil)
      battle.party1starts = playerPartyStarts

      # Clear any stale RNG seeds from buffer
      if defined?(CoopRNGSync)
        CoopRNGSync.reset_sync_state
        ##MultiplayerDebug.info("COOP-BATTLE-START", "Cleared RNG seed buffer for new battle (initiator)")
      end

      # CRITICAL FIX: Sync RNG seed IMMEDIATELY after battle creation
      # This prevents desyncs from encounter_triggered? being called different number of times
      # Use turn -1 to indicate "battle start" seed (before turn 0)
      if defined?(CoopRNGSync) && defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
        ##MultiplayerDebug.info("COOP-RNG-INIT", "Syncing initial RNG seed (initiator)...")
        CoopRNGSync.sync_seed_as_initiator(battle, -1, true)
      end

      ##MultiplayerDebug.info("COOP-V2", "Battle created: trainers=#{playerTrainers.length} party1starts=#{playerPartyStarts.inspect}")

      pbPrepareBattle(battle)
      $PokemonTemp.clearBattleRules

      # Defensive: Initialize heart_gauges if not set by onStartBattle event
      if defined?($PokemonTemp) && !$PokemonTemp.heart_gauges
        $PokemonTemp.heart_gauges = []
        $Trainer.party.each_with_index { |pkmn, i| $PokemonTemp.heart_gauges[i] = pkmn.heart_gauge if pkmn }
        ##MultiplayerDebug.info("COOP-V2", "Initialized heart_gauges defensively")
      end

      # Mark all participants as busy
      if defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:mark_battle)
        MultiplayerClient.mark_battle(true)
        ##MultiplayerDebug.info("COOP-V2", "Marked battle busy=true")
      end

      # === WAIT FOR ALLIES TO SYNC (initiator only) ===
      if ally_count > 0
        ##MultiplayerDebug.info("COOP-V2", "Waiting for #{ally_count} allies to sync...")

        # Prepare expected ally list (sid + name only, no party data)
        expected_allies_for_sync = allies.map { |a| { sid: a[:sid], name: a[:name] } }

        # Show sync screen and wait
        all_joined = pbCoopWaitForAllies(expected_allies_for_sync)

        unless all_joined
          ##MultiplayerDebug.warn("COOP-V2", "Not all allies joined → fallback to vanilla 1v1")
          # Reset transaction state
          CoopBattleTransaction.reset if defined?(CoopBattleTransaction)
          # Clear busy and return to vanilla
          MultiplayerClient.mark_battle(false) if defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:mark_battle)
          return pbBattleOnStepTaken_vanilla_for_coop(repel_active)
        end

        ##MultiplayerDebug.info("COOP-V2", "All allies synced! Starting co-op battle")
      end

      # === INITIALIZE BATTLE STATE TRACKING (Initiator) ===
      if defined?(CoopBattleState)
        ally_sids = allies.map { |a| a[:sid].to_s }
        ally_names_hash = Hash[allies.map { |a| [a[:sid].to_s, a[:name].to_s] }]

        CoopBattleState.create_battle(
          is_initiator: true,
          ally_sids: ally_sids,
          battle_id: battle_id,  # Use pre-generated ID
          ally_names: ally_names_hash,
          encounter_type: encounter_type,
          map_id: ($game_map.map_id rescue nil),
          foe_count: foeParty.length
        )

        ##MultiplayerDebug.info("COOP-V2", "Battle state initialized (Initiator): #{CoopBattleState.battle_id}")

        # Register battle instance for run away sync
        CoopBattleState.register_battle_instance(battle)
        ##MultiplayerDebug.info("COOP-V2", "Battle instance registered with CoopBattleState")
      end

      # === RUN BATTLE ===
      decision = 0
      outcomeVar = 1
      canLose = false

      begin
        pbBattleAnimation(pbGetWildBattleBGM(foeParty), (foeParty.length == 1) ? 0 : 2, foeParty) {
          pbSceneStandby {
            decision = battle.pbStartBattle
          }
          pbAfterBattle(decision, canLose)
        }
      rescue => e
        # CRASH PROTECTION: Default to forfeit (draw) instead of win on error
        if defined?(MultiplayerDebug)
          MultiplayerDebug.error("COOP-V2", "Battle crashed! #{e.class}: #{e.message}")
          MultiplayerDebug.error("COOP-V2", "Backtrace: #{e.backtrace.first(5).join("\n")}")
        end
        decision = 3  # Forfeit/draw - not a win
        pbMessage(_INTL("The battle ended due to an error."))
      end
      Input.update

      ##MultiplayerDebug.info("COOP-V2", "Battle ended: decision=#{decision}")

      # Remove nil entries from $Trainer.party (leftover from coop battle padding)
      # This prevents crashes in egg hatching and other systems that iterate over party
      $Trainer.party.compact!
      ##MultiplayerDebug.info("COOP-V2", "Cleaned party - removed nil padding")

      # Clear busy flag
      if defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:mark_battle)
        MultiplayerClient.mark_battle(false)
        ##MultiplayerDebug.info("COOP-V2", "Marked battle busy=false")
      end

      # === CLEANUP ===
      $PokemonTemp.encounterType = nil
      $PokemonTemp.encounterTriggered = true
      $PokemonTemp.forceSingleBattle = false
      EncounterModifier.triggerEncounterEnd if defined?(EncounterModifier)

      return decision

    rescue => e
      ##MultiplayerDebug.error("COOP-V2", "HOOK CRASH #{e.class}: #{e.message}#{CoopLogUtil.bt(e)} → VANILLA")
      return pbBattleOnStepTaken_vanilla_for_coop(repel_active)
    ensure
      # Safety: ensure all state is cleared even if something raised
      begin
        if defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:mark_battle) && MultiplayerClient.in_battle?
          MultiplayerClient.mark_battle(false)
          ##MultiplayerDebug.info("COOP-V2", "Ensured busy=false in ensure block")
        end
        # Reset transaction state on any exit
        CoopBattleTransaction.reset if defined?(CoopBattleTransaction)
      rescue; end
      $__coop_wild_hook_v2_running = false
      ##MultiplayerDebug.info("COOP-V2", "HOOK EXIT")
    end
  end

  ##MultiplayerDebug.info("COOP-V2", "Successfully hooked pbBattleOnStepTaken")
else
  ##MultiplayerDebug.error("COOP-V2", "pbBattleOnStepTaken NOT FOUND; hook skipped.")
end

# ===========================================
# === OLD APPROACH (kept for reference, commented out)
# ===========================================
=begin
# This was the original approach that didn't work because pbWildBattleCore
# is called AFTER battle rules are already set by pbWildBattle/pbDoubleWildBattle/pbTripleWildBattle

if defined?(Kernel) && (method(:pbWildBattleCore) rescue true)
  unless defined?(pbWildBattleCore_vanilla_for_coop)
    ##MultiplayerDebug.info("COOP-INJECT", "Aliasing vanilla pbWildBattleCore → pbWildBattleCore_vanilla_for_coop")
    alias pbWildBattleCore_vanilla_for_coop pbWildBattleCore
  end

  def pbWildBattleCore(*args)
    if $__coop_wild_hook_running
      ##MultiplayerDebug.warn("COOP-INJECT", "Re-entry detected → VANILLA")
      return pbWildBattleCore_vanilla_for_coop(*args)
    end
    $__coop_wild_hook_running = true

    begin
      coop_ok = defined?(MultiplayerClient) &&
                MultiplayerClient.instance_variable_get(:@connected) &&
                MultiplayerClient.in_squad?
      ##MultiplayerDebug.info("COOP-INJECT", "HOOK ENTER coop_ok=#{coop_ok}")

      # ... rest of old implementation ...

      return pbWildBattleCore_vanilla_for_coop(*args)
    ensure
      $__coop_wild_hook_running = false
    end
  end
end
=end

##MultiplayerDebug.info("COOP-V2", "Hook loaded successfully. Co-op wild battles enabled.")
