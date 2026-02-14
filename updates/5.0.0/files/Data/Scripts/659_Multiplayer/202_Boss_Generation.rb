#===============================================================================
# MODULE 3: Boss Pokemon System - Generation
#===============================================================================
# Creates fully-evolved boss Pokemon with family, stats, items, and full moveset.
#
# Test: Debug console:
#   boss = BossGenerator.create(1, [$Trainer.party], true)
#   boss.is_boss?  # => true
#   boss.species   # => random fully-evolved
#   boss.boss_data[:loot_options].length  # => 3
#===============================================================================

MultiplayerDebug.info("BOSS", "Loading 202_Boss_Generation.rb...") if defined?(MultiplayerDebug)

module BossGenerator
  #=============================================================================
  # Get All Fully-Evolved Species (Base Forms Only)
  #=============================================================================
  def self.get_evolved_pool
    return @evolved_pool if @evolved_pool && !@evolved_pool.empty?

    @evolved_pool = []
    GameData::Species.each do |species|
      next if species.form != 0  # Base form only

      # Check if this species has any forward evolutions
      evos = species.get_evolutions(true)  # exclude_invalid = true
      next unless evos.empty?  # No further evolutions = fully evolved

      # Skip special Pokemon (mythical, ultra beasts, etc.) - optional filter
      # next if species.flags&.include?("Mythical")

      @evolved_pool << species.id
    end

    # Ensure pool is not empty
    if @evolved_pool.empty?
      # Fallback: just use some strong Pokemon
      @evolved_pool = [:CHARIZARD, :BLASTOISE, :VENUSAUR, :DRAGONITE, :TYRANITAR]
    end

    @evolved_pool
  end

  #=============================================================================
  # Clear Cached Pool (call if species data changes)
  #=============================================================================
  def self.clear_cache
    @evolved_pool = nil
  end

  #=============================================================================
  # Calculate Boss Level from Player Parties
  #=============================================================================
  def self.calculate_level(parties)
    levels = parties.flatten.compact.select { |p| p.respond_to?(:level) }.map(&:level)
    return 50 if levels.empty?  # Default level if no valid Pokemon

    avg = levels.sum.to_f / levels.length
    [(avg + BossConfig::LEVEL_BONUS).round, 100].min
  end

  #=============================================================================
  # Get All Learnable Moves for a Species
  #=============================================================================
  def self.get_all_moves(species_id, form = 0)
    species_data = GameData::Species.get_species_form(species_id, form)
    return [] unless species_data

    all_moves = []

    # Level-up moves (array of [level, move_id])
    species_data.moves.each { |level, move| all_moves << move }

    # Tutor moves
    all_moves.concat(species_data.tutor_moves) if species_data.tutor_moves

    # Egg moves
    all_moves.concat(species_data.egg_moves) if species_data.egg_moves

    # Remove duplicates and invalid moves
    all_moves.uniq.select { |m| GameData::Move.exists?(m) }
  end

  #=============================================================================
  # Create Boss Pokemon
  #=============================================================================
  def self.create(player_count, player_parties, family_enabled = false)
    MultiplayerDebug.info("BOSS-SPAWN", "    BossGenerator.create called (players=#{player_count}, family=#{family_enabled})") if defined?(MultiplayerDebug)

    # Pick random fully-evolved species
    pool = get_evolved_pool
    MultiplayerDebug.info("BOSS-SPAWN", "    Evolved pool size: #{pool.length}") if defined?(MultiplayerDebug)

    species = pool.sample
    MultiplayerDebug.info("BOSS-SPAWN", "    Selected species: #{species}") if defined?(MultiplayerDebug)

    # Calculate level from player parties
    level = calculate_level(player_parties)
    MultiplayerDebug.info("BOSS-SPAWN", "    Calculated level: #{level}") if defined?(MultiplayerDebug)

    # Create base Pokemon
    begin
      pkmn = Pokemon.new(species, level)
      MultiplayerDebug.info("BOSS-SPAWN", "    Pokemon created: #{pkmn.species}") if defined?(MultiplayerDebug)
    rescue => e
      MultiplayerDebug.info("BOSS-SPAWN", "    ERROR creating Pokemon: #{e.message}") if defined?(MultiplayerDebug)
      return nil
    end

    # Mark as boss and set up boss data
    begin
      pkmn.make_boss!(player_count)
      MultiplayerDebug.info("BOSS-SPAWN", "    make_boss! complete, is_boss?=#{pkmn.is_boss?}") if defined?(MultiplayerDebug)
    rescue => e
      MultiplayerDebug.info("BOSS-SPAWN", "    ERROR in make_boss!: #{e.message}") if defined?(MultiplayerDebug)
      return nil
    end

    # Apply stat multipliers via IVs/nature boost (stats recalculated later)
    # We'll handle actual stat modification in battle via multipliers
    pkmn.iv[:HP] = 31
    pkmn.iv[:ATTACK] = 31
    pkmn.iv[:DEFENSE] = 31
    pkmn.iv[:SPECIAL_ATTACK] = 31
    pkmn.iv[:SPECIAL_DEFENSE] = 31
    pkmn.iv[:SPEED] = 31

    # Random held item from curated pool
    pkmn.item = BossConfig.random_held_item

    # Gather ALL learnable moves
    pkmn.boss_all_moves = get_all_moves(species, pkmn.form)

    # Set standard 4 moves (best offensive moves for AI)
    assign_best_moves(pkmn)

    # Assign family if the system is enabled
    MultiplayerDebug.info("BOSS-SPAWN", "    Family assignment check:") if defined?(MultiplayerDebug)
    MultiplayerDebug.info("BOSS-SPAWN", "      family_enabled param: #{family_enabled}") if defined?(MultiplayerDebug)
    MultiplayerDebug.info("BOSS-SPAWN", "      PokemonFamilyConfig defined?: #{defined?(PokemonFamilyConfig)}") if defined?(MultiplayerDebug)
    if defined?(PokemonFamilyConfig)
      MultiplayerDebug.info("BOSS-SPAWN", "      PokemonFamilyConfig.system_enabled?: #{PokemonFamilyConfig.system_enabled?}") if defined?(MultiplayerDebug)
    end

    if family_enabled && defined?(PokemonFamilyConfig) && PokemonFamilyConfig.system_enabled?
      MultiplayerDebug.info("BOSS-SPAWN", "    Calling assign_boss_family...") if defined?(MultiplayerDebug)
      assign_boss_family(pkmn)
      MultiplayerDebug.info("BOSS-SPAWN", "    After assign_boss_family: shiny=#{pkmn.shiny?}, family=#{pkmn.family rescue 'N/A'}") if defined?(MultiplayerDebug)
    else
      MultiplayerDebug.info("BOSS-SPAWN", "    SKIPPING family assignment (family system disabled)") if defined?(MultiplayerDebug)
    end

    pkmn
  end

  #=============================================================================
  # Assign Random Family to Boss (and make shiny)
  #=============================================================================
  # The family system's ability_id/ability2_id getters automatically handle
  # dual abilities when family/subfamily are set. We just need to:
  # 1. Make the Pokemon shiny
  # 2. Set family and subfamily attributes
  # The family talent will be added as ability2, keeping the base ability intact.
  #=============================================================================
  def self.assign_boss_family(pkmn)
    # Check if Pokemon class has family attributes (from 100_Family_Pokemon_Patch.rb)
    unless pkmn.respond_to?(:family=)
      MultiplayerDebug.info("BOSS", "Pokemon doesn't have family= method, skipping family assignment") if defined?(MultiplayerDebug)
      return
    end

    # Make boss shiny FIRST (required for family system to work)
    pkmn.shiny = true

    # Random family (0-7)
    family_id = rand(8)

    # Random subfamily within family (4 per family) - weighted selection
    subfamily_base = family_id * 4
    weights = (0..3).map { |i| PokemonFamilyConfig::SUBFAMILIES[subfamily_base + i][:weight] rescue 25 }
    total_weight = weights.sum
    roll = rand(total_weight)
    cumulative = 0
    local_subfamily = 0
    weights.each_with_index do |w, i|
      cumulative += w
      if roll < cumulative
        local_subfamily = i
        break
      end
    end

    # Set family attributes (correct attribute names: family, subfamily, family_assigned_at)
    # The family system's ability_id and ability2_id getter overrides will automatically
    # handle the dual ability system based on these attributes.
    pkmn.family = family_id
    pkmn.subfamily = local_subfamily if pkmn.respond_to?(:subfamily=)
    pkmn.family_assigned_at = Time.now.to_i if pkmn.respond_to?(:family_assigned_at=)

    # Log the assignment
    if defined?(MultiplayerDebug)
      family_name = PokemonFamilyConfig::FAMILIES[family_id][:name] rescue "Family #{family_id}"
      global_subfamily = family_id * 4 + local_subfamily
      subfamily_name = PokemonFamilyConfig::SUBFAMILIES[global_subfamily][:name] rescue "Subfamily #{local_subfamily}"
      talent = PokemonFamilyConfig.get_family_talent(family_id) rescue nil
      talent_name = talent ? (GameData::Ability.get(talent).name rescue talent.to_s) : "None"

      MultiplayerDebug.info("BOSS", "Assigned boss family:")
      MultiplayerDebug.info("BOSS", "  Family: #{family_name} (#{family_id})")
      MultiplayerDebug.info("BOSS", "  Subfamily: #{subfamily_name} (local: #{local_subfamily})")
      MultiplayerDebug.info("BOSS", "  Shiny: #{pkmn.shiny?}")
      MultiplayerDebug.info("BOSS", "  Family Talent: #{talent_name}")
      MultiplayerDebug.info("BOSS", "  Base Ability: #{GameData::Ability.get(pkmn.ability_id).name rescue 'Unknown'}")

      # Check if ability2 is set (family talent as second ability)
      if pkmn.respond_to?(:ability2_id) && pkmn.ability2_id
        MultiplayerDebug.info("BOSS", "  Ability 2: #{GameData::Ability.get(pkmn.ability2_id).name rescue 'Unknown'}")
      end
    end

    # DO NOT manually set pkmn.ability here!
    # The family system's ability_id and ability2_id getter overrides handle everything.
    # Setting pkmn.ability would override the base ability instead of adding a second one.
  end

  #=============================================================================
  # Assign Best 4 Moves Based on Power/Coverage
  #=============================================================================
  def self.assign_best_moves(pkmn)
    all_moves = pkmn.boss_all_moves
    return if all_moves.empty?

    # Score moves by power, category, and type coverage
    scored = all_moves.map do |move_id|
      move_data = GameData::Move.get(move_id)
      score = 0

      # Prefer damaging moves
      if move_data.category == 0 || move_data.category == 1  # Physical or Special
        score += move_data.base_damage

        # STAB bonus
        if pkmn.hasType?(move_data.type)
          score += 40
        end

        # Prefer high accuracy
        score += (move_data.accuracy - 50) / 2 if move_data.accuracy > 0
      else
        # Status moves get lower priority but still useful
        score += 30
      end

      { move: move_id, score: score }
    end

    # Sort by score descending, take top 4
    best_moves = scored.sort_by { |m| -m[:score] }.first(4)

    # Clear and assign moves
    pkmn.moves.clear
    best_moves.each do |m|
      pkmn.learn_move(m[:move])
    end
  end

  #=============================================================================
  # Create Boss From Specific Species (for testing/scripted encounters)
  #=============================================================================
  def self.create_specific(species, level, player_count = 1, family_enabled = false)
    pkmn = Pokemon.new(species, level)
    pkmn.make_boss!(player_count)

    pkmn.iv[:HP] = 31
    pkmn.iv[:ATTACK] = 31
    pkmn.iv[:DEFENSE] = 31
    pkmn.iv[:SPECIAL_ATTACK] = 31
    pkmn.iv[:SPECIAL_DEFENSE] = 31
    pkmn.iv[:SPEED] = 31

    pkmn.item = BossConfig.random_held_item
    pkmn.boss_all_moves = get_all_moves(species, pkmn.form)
    assign_best_moves(pkmn)

    if family_enabled && defined?(PokemonFamilyConfig) && PokemonFamilyConfig.system_enabled?
      assign_boss_family(pkmn)
    end

    pkmn
  end

  #=============================================================================
  # Debug: Test Boss Generation
  #=============================================================================
  def self.test
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("BOSS-TEST", "=== Boss Generator Test ===")
      MultiplayerDebug.info("BOSS-TEST", "Evolved pool size: #{get_evolved_pool.length}")
      MultiplayerDebug.info("BOSS-TEST", "Sample species: #{get_evolved_pool.sample(5).join(', ')}")
    end

    fake_party = [Pokemon.new(:PIKACHU, 30), Pokemon.new(:CHARIZARD, 50)]
    boss = create(1, [fake_party], true)

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("BOSS-TEST", "Boss species: #{boss.species}")
      MultiplayerDebug.info("BOSS-TEST", "Boss level: #{boss.level}")
      MultiplayerDebug.info("BOSS-TEST", "Boss is_boss?: #{boss.is_boss?}")
      MultiplayerDebug.info("BOSS-TEST", "Boss HP phase: #{boss.boss_hp_phase}")
      MultiplayerDebug.info("BOSS-TEST", "Boss shields: #{boss.boss_shields}")
      MultiplayerDebug.info("BOSS-TEST", "Boss item: #{boss.item}")
      MultiplayerDebug.info("BOSS-TEST", "Boss moves: #{boss.moves.map(&:id).join(', ')}")
      MultiplayerDebug.info("BOSS-TEST", "Boss all moves count: #{boss.boss_all_moves.length}")
      MultiplayerDebug.info("BOSS-TEST", "Boss loot options: #{boss.boss_loot_options.inspect}")
      MultiplayerDebug.info("BOSS-TEST", "Boss shiny?: #{boss.shiny?}")
      MultiplayerDebug.info("BOSS-TEST", "Boss family: #{boss.family rescue 'N/A'}")
      MultiplayerDebug.info("BOSS-TEST", "Boss subfamily: #{boss.subfamily rescue 'N/A'}")
      MultiplayerDebug.info("BOSS-TEST", "=== Test Complete ===")
    end

    boss
  end
end

#===============================================================================
# Debug Menu Integration
#===============================================================================
if defined?(MenuHandlers)
  MenuHandlers.add(:debug_menu, :test_boss_generator, {
    "name" => "Test Boss Generator",
    "parent" => :main,
    "description" => "Test boss Pokemon generation",
    "effect" => proc {
      BossGenerator.test
      pbMessage("Boss generator test complete. Check debug logs.")
    }
  })
end
