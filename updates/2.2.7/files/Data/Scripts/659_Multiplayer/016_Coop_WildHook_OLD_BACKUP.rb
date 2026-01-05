# ===========================================
# File: 016_Coop_WildHook.rb
# Purpose: Co-op wild battles (double/triple) by injecting NPCTrainer allies
# Notes : 0 allies → vanilla; 1 ally → double; 2 allies → triple.
#         Allies are always NPCTrainer (no $PokemonGlobal.partner).
#         Trainer type forced to :YOUNGSTER.
# ===========================================
=begin
# ----- Small logging helpers -----
module CoopLogUtil
  $__coop_wild_hook_running = false
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

##MultiplayerDebug.info("COOP-HOOK", "Wild battle hook (ally NPCTrainer build) loaded.")

# ----- Ally discovery + foe expansion -----
module CoopWildHook
  TAG = "COOP-INJECT"

  # Returns up to 'limit' eligible nearby squadmates with non-empty parties.
  # [{ sid:, name:, party:[Pokemon] }, ...]
  def self.pick_nearby_allies(limit = 2)
    out = []
    begin
      unless defined?(MultiplayerClient) && MultiplayerClient.instance_variable_get(:@connected) && MultiplayerClient.in_squad?
        ##MultiplayerDebug.warn(TAG, "Not connected/in squad → no allies.")
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

        # Prefer a direct API if you’ve added one (player_busy?), otherwise look at pinfo[:busy]
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

        out << { sid: sid, name: name, party: party }
        break if out.length >= limit
      end
    rescue => e
      ##MultiplayerDebug.error(TAG, "pick_nearby_allies ERROR #{e.class}: #{e.message}#{CoopLogUtil.bt(e)}")
    end
    out
  end

  # Expand foeParty to target size (1..3) by rolling encounters or cloning species/level.
  def self.expand_foes!(foe_party, target_size)
    return unless foe_party.is_a?(Array)
    target_size = [[target_size, 1].max, 3].min
    ##MultiplayerDebug.info(TAG, "Foe expansion target=#{target_size} current=#{foe_party.length}")

    roll_extra = lambda {
      if defined?($PokemonEncounters) && $PokemonEncounters
        enc_type =
          if $PokemonEncounters.respond_to?(:encounter_type)
            $PokemonEncounters.encounter_type
          elsif defined?(pbEncounterType)
            pbEncounterType
          end
        begin
          pair = $PokemonEncounters.choose_wild_pokemon(enc_type) if $PokemonEncounters.respond_to?(:choose_wild_pokemon)
          if pair && pair[0] && pair[1]
            sp = GameData::Species.get(pair[0]).id
            lv = pair[1]
            mon = pbGenerateWildPokemon(sp, lv)
            ##MultiplayerDebug.info(TAG, "  Extra foe via encounters: #{CoopLogUtil.dex_name(mon)}")
            return mon
          end
        rescue => e2
          ##MultiplayerDebug.warn(TAG, "  choose_wild_pokemon failed: #{e2.class}: #{e2.message}")
        end
      end
      nil
    }

    existing_species = foe_party.map { |p| p.species rescue nil }.compact
    attempts = 0
    while foe_party.length < target_size && attempts < 12
      attempts += 1
      extra = roll_extra.call
      if !extra
        base = foe_party[0]; break unless base
        extra = pbGenerateWildPokemon(base.species, base.level)
        ##MultiplayerDebug.info(TAG, "  Fallback extra foe (clone species)")
      end
      if existing_species.include?(extra.species) && attempts < 12
        ##MultiplayerDebug.info(TAG, "  Extra foe duplicate species → retry (#{attempts})")
        next
      end
      foe_party << extra
      existing_species << extra.species
      ##MultiplayerDebug.info(TAG, "  Added extra foe (#{foe_party.length}/#{target_size})")
    end
  end
end

# ----- Re-entrancy guard -----
$__coop_wild_hook_running = false unless defined?($__coop_wild_hook_running)

# ----- Global Events hook (mark busy for ALL battles, including vanilla) -----
unless defined?($__coop_busy_flag_events_installed)
  $__coop_busy_flag_events_installed = true
  begin
    if defined?(Events) && !$__kif_busy_hooks_installed
      $__kif_busy_hooks_installed = true
      Events.onStartBattle += proc { |_s,_| MultiplayerClient.mark_battle(true) if defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:mark_battle) }
      if Events.respond_to?(:onEndBattle)
        Events.onEndBattle   += proc { |_s,_| MultiplayerClient.mark_battle(false) if defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:mark_battle) }
      end
      ##MultiplayerDebug.info("COOP-HOOK", "Installed global busy flag handlers on Events.")
    end
  rescue => e
    ##MultiplayerDebug.warn("COOP-HOOK", "Failed installing global busy flag handlers: #{e.class}: #{e.message}")
  end
end

# ----- Hook pbWildBattleCore -----
if defined?(Kernel) && (method(:pbWildBattleCore) rescue true)
  unless defined?(pbWildBattleCore_vanilla_for_coop)
    ##MultiplayerDebug.info("COOP-HOOK", "Aliasing vanilla pbWildBattleCore → pbWildBattleCore_vanilla_for_coop")
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

      # Ask allies to push party snapshots (non-blocking)
      if coop_ok
        begin
          MultiplayerClient.send_data("COOP_PARTY_PUSH_NOW:")
        rescue => e
          ##MultiplayerDebug.warn("COOP-INJECT", "nudge failed: #{e.message}")
        end
      end

      allies = coop_ok ? CoopWildHook.pick_nearby_allies(2) : []
      ally_count = allies.length
      ##MultiplayerDebug.info("COOP-INJECT", "eligible_allies=#{ally_count}")

      # 0 allies → vanilla
      return pbWildBattleCore_vanilla_for_coop(*args) if ally_count == 0

      # ----- VANILLA PREFLIGHT (copied structure) -----
      outcomeVar = $PokemonTemp.battleRules["outcomeVar"] || 1
      canLose    = $PokemonTemp.battleRules["canLose"] || false
      if $Trainer.able_pokemon_count == 0 || ($DEBUG && Input.press?(Input::CTRL))
        pbMessage(_INTL("SKIPPING BATTLE...")) if $Trainer.pokemon_count > 0
        pbSet(outcomeVar,1)
        $PokemonTemp.clearBattleRules
        $PokemonGlobal.nextBattleBGM       = nil
        $PokemonGlobal.nextBattleME        = nil
        $PokemonGlobal.nextBattleCaptureME = nil
        $PokemonGlobal.nextBattleBack      = nil
        $PokemonTemp.forced_alt_sprites    = nil
        pbMEStop
        return 1
      end
      $PokemonSystem.is_in_battle = true
      Events.onStartBattle.trigger(nil)

      # Generate wild foes exactly like vanilla:
      foeParty = []
      sp = nil
      args.each_with_index do |arg, i|
        if arg.is_a?(Pokemon)
          foeParty << arg
          ##MultiplayerDebug.info("COOP-INJECT", "args[#{i}] Pokemon → ADD #{CoopLogUtil.dex_name(arg)}")
        elsif arg.is_a?(Array)
          species = GameData::Species.get(arg[0]).id
          pkmn = pbGenerateWildPokemon(species, arg[1])
          foeParty << pkmn
          ##MultiplayerDebug.info("COOP-INJECT", "args[#{i}] [species,level]=[#{arg[0]},#{arg[1]}] → GEN #{CoopLogUtil.dex_name(pkmn)}")
        elsif sp
          species = GameData::Species.get(sp).id
          pkmn = pbGenerateWildPokemon(species, arg)
          foeParty << pkmn
          ##MultiplayerDebug.info("COOP-INJECT", "args[#{i}] (level for prev specie=#{sp}) → GEN #{CoopLogUtil.dex_name(pkmn)}")
          sp = nil
        else
          sp = arg
          ##MultiplayerDebug.info("COOP-INJECT", "args[#{i}] specie token set=#{sp}")
        end
      end
      if sp
        msg = _INTL("Expected a level after being given {1}, but one wasn't found.", sp)
        ##MultiplayerDebug.error("COOP-INJECT", "ARG ERROR: #{msg}")
        raise msg
      end

      # ----- Build player side with NPCTrainer allies -----
      trainer_type = :YOUNGSTER
      playerTrainers    = [$Trainer]
      playerParty       = []
      $Trainer.party.each { |p| playerParty << p }
      playerPartyStarts = [0]

      # Add allies in order; compute starts in between
      allies.each_with_index do |ally, i|
        start_idx = playerParty.length
        npc = NPCTrainer.new(ally[:name].to_s, trainer_type)
        npc.id    = ally[:sid].to_s
        npc.party = ally[:party]
        playerTrainers << npc
        playerPartyStarts << start_idx
        ally[:party].each { |p| playerParty << p }
        ##MultiplayerDebug.info("COOP-INJECT", "Added Ally##{i} → name=#{ally[:name]} id=#{ally[:sid]} mons=#{ally[:party].length} start=#{start_idx}")
      end

      # Desired size: 1 + allies (max 3)
      desired_size = [[1 + ally_count, 1].max, 3].min
      if !$PokemonTemp.battleRules["size"]
        setBattleRule(desired_size >= 3 ? "triple" : "double")
        ##MultiplayerDebug.info("COOP-INJECT", "setBattleRule(#{desired_size >= 3 ? 'triple' : 'double'})")
      end

      # Mirror foe side size
      CoopWildHook.expand_foes!(foeParty, desired_size)

      # ----- Create scene/battle and run -----
      scene  = pbNewBattleScene
      battle = PokeBattle_Battle.new(scene, playerParty, foeParty, playerTrainers, nil)
      battle.party1starts = playerPartyStarts
      ##MultiplayerDebug.info("COOP-INJECT", "party1starts=#{playerPartyStarts.inspect} trainers=#{playerTrainers.length}")

      pbPrepareBattle(battle)
      $PokemonTemp.clearBattleRules

      # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
      # Flip "busy" flag ON for the duration of the battle (and guarantee OFF)
      if defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:mark_battle)
        MultiplayerClient.mark_battle(true)
      end
      # <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

      decision = 0
      pbBattleAnimation(pbGetWildBattleBGM(foeParty), (foeParty.length==1) ? 0 : 2, foeParty) {
        pbSceneStandby {
          decision = battle.pbStartBattle
        }
        pbAfterBattle(decision, canLose)
      }
      Input.update
      pbSet(outcomeVar, decision)

      # Clear busy after battle finishes
      if defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:mark_battle)
        MultiplayerClient.mark_battle(false)
      end

      return decision

    rescue => e
      ##MultiplayerDebug.error("COOP-INJECT", "HOOK CRASH #{e.class}: #{e.message}#{CoopLogUtil.bt(e)} → VANILLA")
      return pbWildBattleCore_vanilla_for_coop(*args)
    ensure
      # Safety: ensure busy flag is cleared even if something raised
      begin
        if defined?(MultiplayerClient) && MultiplayerClient.respond_to?(:mark_battle) && MultiplayerClient.in_battle?
          MultiplayerClient.mark_battle(false)
        end
      rescue; end
      $__coop_wild_hook_running = false
      ##MultiplayerDebug.info("COOP-INJECT", "HOOK EXIT")
    end
  end
else
  ##MultiplayerDebug.error("COOP-HOOK", "pbWildBattleCore NOT FOUND; hook skipped.")
end
=end