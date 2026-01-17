#===============================================================================
# MODULE: PokemonSerializer - JSON-based Pokemon Serialization for Network
#===============================================================================
# Replaces Marshal.dump/load for Pokemon objects with JSON serialization.
# Uses the existing Pokemon#to_json and Pokemon#load_json methods.
#
# SECURITY: This module avoids Marshal which can execute arbitrary code.
# JSON can only represent data, not executable code.
#
# Usage:
#   PokemonSerializer.serialize_pokemon(pokemon) -> Hash (JSON-safe)
#   PokemonSerializer.deserialize_pokemon(data)  -> Pokemon
#   PokemonSerializer.serialize_party(party)     -> Array of Hashes
#   PokemonSerializer.deserialize_party(data)    -> Array of Pokemon
#===============================================================================

module PokemonSerializer
  TAG = "PKM-SERIAL"

  module_function

  #-----------------------------------------------------------------------------
  # Serialize a single Pokemon to JSON-safe Hash
  #-----------------------------------------------------------------------------
  def serialize_pokemon(pokemon)
    return nil unless pokemon.is_a?(Pokemon)

    begin
      if defined?(MultiplayerDebug)
        MultiplayerDebug.info(TAG, "=" * 60)
        MultiplayerDebug.info(TAG, "SERIALIZE START: #{pokemon.name} (#{pokemon.species})")
        MultiplayerDebug.info(TAG, "  Level: #{pokemon.level}, HP: #{pokemon.hp}/#{pokemon.totalhp}")
        MultiplayerDebug.info(TAG, "  Shiny: #{pokemon.shiny?}, Form: #{pokemon.form}")
      end

      # Use Pokemon's built-in to_json method (returns Hash with moves included)
      data = pokemon.to_json

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info(TAG, "  to_json returned Hash with #{data.keys.length} keys")
        MultiplayerDebug.info(TAG, "  Moves: #{data['moves'] ? data['moves'].length : 0} moves")
        data['moves'].each_with_index do |m, i|
          MultiplayerDebug.info(TAG, "    Move #{i}: #{m['id']} PP=#{m['pp']}/#{m['ppup']}")
        end if data['moves']
      end

      # Convert symbols to strings for JSON compatibility
      json_safe = convert_to_json_safe(data)

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info(TAG, "  Converted to JSON-safe format")
        MultiplayerDebug.info(TAG, "SERIALIZE END: Success")
        MultiplayerDebug.info(TAG, "=" * 60)
      end

      return json_safe

    rescue => e
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error(TAG, "SERIALIZE ERROR: #{e.class}: #{e.message}")
        MultiplayerDebug.error(TAG, "  Backtrace: #{e.backtrace.first(5).join(' | ')}")
      end
      return nil
    end
  end

  #-----------------------------------------------------------------------------
  # Deserialize a Hash back to Pokemon object
  #-----------------------------------------------------------------------------
  def deserialize_pokemon(data)
    return nil unless data.is_a?(Hash)

    begin
      if defined?(MultiplayerDebug)
        MultiplayerDebug.info(TAG, "=" * 60)
        MultiplayerDebug.info(TAG, "DESERIALIZE START")
        MultiplayerDebug.info(TAG, "  Data keys: #{data.keys.length}")
        MultiplayerDebug.info(TAG, "  Sample keys: #{data.keys.first(5).inspect}")
      end

      # Convert JSON data back to Ruby types
      # IMPORTANT: Pokemon's load_json expects STRING keys, not symbols!
      # So we use a special conversion that keeps string keys but restores symbol VALUES
      ruby_data = convert_from_json_safe_keep_string_keys(data)

      # Get species - look for both string and symbol key just in case
      species = ruby_data['species'] || ruby_data[:species]
      level = ruby_data['level'] || ruby_data[:level] || 1
      hp_value = ruby_data['hp'] || ruby_data[:hp]
      totalhp_value = ruby_data['totalhp'] || ruby_data[:totalhp]

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info(TAG, "  Species: #{species} (#{species.class})")
        MultiplayerDebug.info(TAG, "  Level: #{level}, HP: #{hp_value}/#{totalhp_value}")
      end

      # Species needs to be a symbol for Pokemon.new
      species = species.to_sym if species.is_a?(String)

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info(TAG, "  Creating Pokemon: species=#{species}, level=#{level}")
      end

      # Create new Pokemon with basic data (without moves initially)
      # Pass nil for owner - it will create a default owner which load_json can then update
      pokemon = Pokemon.new(species, level, nil, false, false)

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info(TAG, "  Base Pokemon created: #{pokemon.name}")
        MultiplayerDebug.info(TAG, "  Default owner: #{pokemon.owner.name rescue 'N/A'}")
      end

      # Ensure moves array in data has string keys for move IDs
      moves_data = ruby_data['moves'] || ruby_data[:moves] || []
      if moves_data.is_a?(Array)
        moves_data = moves_data.map do |m|
          next nil unless m.is_a?(Hash)
          # Ensure move ID is a symbol (load_json expects this)
          move_id = m['id'] || m[:id]
          move_id = move_id.to_sym if move_id.is_a?(String)
          {
            'id' => move_id,
            'pp' => m['pp'] || m[:pp],
            'ppup' => m['ppup'] || m[:ppup]
          }
        end.compact
        ruby_data['moves'] = moves_data
      end

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info(TAG, "  Moves prepared: #{moves_data.length} moves")
        moves_data.each_with_index do |m, i|
          MultiplayerDebug.info(TAG, "    Move #{i}: id=#{m['id']} (#{m['id'].class})")
        end
      end

      # Load all the JSON data into the Pokemon using its built-in method
      # This handles most attributes including moves
      pokemon.load_json(ruby_data)

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info(TAG, "  load_json completed")
        MultiplayerDebug.info(TAG, "  Moves after load_json: #{pokemon.moves.length}")
        pokemon.moves.each_with_index do |m, i|
          MultiplayerDebug.info(TAG, "    Move #{i}: #{m.id} PP=#{m.pp}")
        end
      end

      # CRITICAL FIX: Convert IV and EV hash keys from strings to symbols
      # load_json sets @iv and @ev with string keys (e.g. "HP", "ATTACK")
      # but calc_stats expects symbol keys (e.g. :HP, :ATTACK)
      if pokemon.iv.is_a?(Hash)
        fixed_iv = {}
        pokemon.iv.each do |k, v|
          key = k.is_a?(String) ? k.to_sym : k
          fixed_iv[key] = v.to_i rescue 0
        end
        pokemon.instance_variable_set(:@iv, fixed_iv)

        if defined?(MultiplayerDebug)
          MultiplayerDebug.info(TAG, "  Fixed IV keys: #{fixed_iv.keys.inspect}")
        end
      end

      if pokemon.ev.is_a?(Hash)
        fixed_ev = {}
        pokemon.ev.each do |k, v|
          key = k.is_a?(String) ? k.to_sym : k
          fixed_ev[key] = v.to_i rescue 0
        end
        pokemon.instance_variable_set(:@ev, fixed_ev)

        if defined?(MultiplayerDebug)
          MultiplayerDebug.info(TAG, "  Fixed EV keys: #{fixed_ev.keys.inspect}")
        end
      end

      # Also fix ivMaxed if present
      if pokemon.ivMaxed.is_a?(Hash)
        fixed_ivMaxed = {}
        pokemon.ivMaxed.each do |k, v|
          key = k.is_a?(String) ? k.to_sym : k
          fixed_ivMaxed[key] = v
        end
        pokemon.instance_variable_set(:@ivMaxed, fixed_ivMaxed)
      end

      # Force recalculate stats to ensure consistency
      pokemon.calc_stats

      # Restore HP after calc_stats (calc_stats may reset it to full)
      if hp_value
        pokemon.hp = hp_value.to_i

        if defined?(MultiplayerDebug)
          MultiplayerDebug.info(TAG, "  HP restored: #{pokemon.hp}/#{pokemon.totalhp}")
        end
      end

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info(TAG, "  Final HP: #{pokemon.hp}/#{pokemon.totalhp}")
        MultiplayerDebug.info(TAG, "  Final moves count: #{pokemon.moves.length}")
        MultiplayerDebug.info(TAG, "DESERIALIZE END: Success - #{pokemon.name}")
        MultiplayerDebug.info(TAG, "=" * 60)
      end

      return pokemon

    rescue => e
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error(TAG, "DESERIALIZE ERROR: #{e.class}: #{e.message}")
        MultiplayerDebug.error(TAG, "  Backtrace: #{e.backtrace.first(5).join(' | ')}")
      end
      return nil
    end
  end

  #-----------------------------------------------------------------------------
  # Serialize a party (array of Pokemon)
  #-----------------------------------------------------------------------------
  def serialize_party(party)
    return [] unless party.is_a?(Array)

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info(TAG, "=" * 70)
      MultiplayerDebug.info(TAG, "SERIALIZE PARTY START: #{party.length} Pokemon")
    end

    result = []
    party.each_with_index do |pokemon, i|
      if pokemon.is_a?(Pokemon)
        if defined?(MultiplayerDebug)
          MultiplayerDebug.info(TAG, "  [#{i}] Serializing: #{pokemon.name} Lv.#{pokemon.level}")
        end
        serialized = serialize_pokemon(pokemon)
        if serialized
          result << serialized
        else
          if defined?(MultiplayerDebug)
            MultiplayerDebug.warn(TAG, "  [#{i}] Serialization returned nil!")
          end
          result << nil
        end
      else
        if defined?(MultiplayerDebug)
          MultiplayerDebug.info(TAG, "  [#{i}] nil slot")
        end
        result << nil
      end
    end

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info(TAG, "SERIALIZE PARTY END: #{result.compact.length} valid Pokemon")
      MultiplayerDebug.info(TAG, "=" * 70)
    end

    return result
  end

  #-----------------------------------------------------------------------------
  # Deserialize a party (array of Pokemon data)
  #-----------------------------------------------------------------------------
  def deserialize_party(data)
    return [] unless data.is_a?(Array)

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info(TAG, "=" * 70)
      MultiplayerDebug.info(TAG, "DESERIALIZE PARTY START: #{data.length} entries")
    end

    result = []
    data.each_with_index do |pokemon_data, i|
      if pokemon_data.is_a?(Hash)
        if defined?(MultiplayerDebug)
          MultiplayerDebug.info(TAG, "  [#{i}] Deserializing: species=#{pokemon_data['species']}")
        end
        pokemon = deserialize_pokemon(pokemon_data)
        if pokemon
          result << pokemon
          if defined?(MultiplayerDebug)
            MultiplayerDebug.info(TAG, "  [#{i}] Success: #{pokemon.name} HP=#{pokemon.hp}/#{pokemon.totalhp}")
          end
        else
          if defined?(MultiplayerDebug)
            MultiplayerDebug.warn(TAG, "  [#{i}] Deserialization returned nil!")
          end
        end
      else
        if defined?(MultiplayerDebug)
          MultiplayerDebug.info(TAG, "  [#{i}] nil/invalid entry")
        end
      end
    end

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info(TAG, "DESERIALIZE PARTY END: #{result.length} valid Pokemon")
      MultiplayerDebug.info(TAG, "=" * 70)
    end

    return result
  end

  #-----------------------------------------------------------------------------
  # Convert Ruby Hash/Array to JSON-safe format (symbols -> tagged strings)
  #-----------------------------------------------------------------------------
  def convert_to_json_safe(obj)
    case obj
    when Symbol
      # Tag symbols for later restoration
      { "__sym__" => obj.to_s }
    when Hash
      result = {}
      obj.each do |k, v|
        # Convert symbol keys to tagged strings
        key_str = k.is_a?(Symbol) ? "__symkey__#{k}" : k.to_s
        result[key_str] = convert_to_json_safe(v)
      end
      result
    when Array
      obj.map { |v| convert_to_json_safe(v) }
    when String, Integer, Float, TrueClass, FalseClass, NilClass
      obj
    else
      # Unknown type - convert to string with warning
      if defined?(MultiplayerDebug)
        MultiplayerDebug.warn(TAG, "Unknown type in convert_to_json_safe: #{obj.class}")
      end
      obj.to_s
    end
  end

  #-----------------------------------------------------------------------------
  # Convert JSON-safe format back to Ruby types (tagged strings -> symbols)
  #-----------------------------------------------------------------------------
  def convert_from_json_safe(obj)
    case obj
    when Hash
      # Check for symbol marker
      if obj.key?("__sym__")
        return obj["__sym__"].to_sym
      end

      # Regular hash - restore symbol keys
      result = {}
      obj.each do |k, v|
        # Restore symbol keys
        key = k.to_s.start_with?("__symkey__") ? k.to_s.sub("__symkey__", "").to_sym : k
        result[key] = convert_from_json_safe(v)
      end
      result
    when Array
      obj.map { |v| convert_from_json_safe(v) }
    else
      obj
    end
  end

  #-----------------------------------------------------------------------------
  # Convert JSON-safe format back to Ruby types, but KEEP STRING KEYS
  # This is needed for Pokemon's load_json which expects string keys
  #-----------------------------------------------------------------------------
  def convert_from_json_safe_keep_string_keys(obj)
    case obj
    when Hash
      # Check for symbol marker - restore to actual symbol
      if obj.key?("__sym__")
        return obj["__sym__"].to_sym
      end

      # Regular hash - KEEP string keys (don't convert __symkey__ back)
      # Only restore symbol VALUES, not keys
      result = {}
      obj.each do |k, v|
        # Remove __symkey__ prefix but keep as STRING
        key = k.to_s.start_with?("__symkey__") ? k.to_s.sub("__symkey__", "") : k.to_s
        result[key] = convert_from_json_safe_keep_string_keys(v)
      end
      result
    when Array
      obj.map { |v| convert_from_json_safe_keep_string_keys(v) }
    else
      obj
    end
  end

  #-----------------------------------------------------------------------------
  # Serialize battle invite payload (foes + allies)
  # This is the main entry point for coop battle invitations
  #-----------------------------------------------------------------------------
  def serialize_battle_invite(foe_party, allies_data, encounter_type, battle_id)
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info(TAG, "=" * 80)
      MultiplayerDebug.info(TAG, "SERIALIZE BATTLE INVITE START")
      MultiplayerDebug.info(TAG, "  Foes: #{foe_party.length}")
      MultiplayerDebug.info(TAG, "  Allies: #{allies_data.length}")
      MultiplayerDebug.info(TAG, "  Encounter type: #{encounter_type}")
      MultiplayerDebug.info(TAG, "  Battle ID: #{battle_id}")
    end

    # Serialize foe party
    foes_serialized = serialize_party(foe_party)

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info(TAG, "  Foes serialized: #{foes_serialized.compact.length} valid")
    end

    # Serialize allies (each ally has sid, name, party)
    allies_serialized = allies_data.map do |ally|
      if defined?(MultiplayerDebug)
        MultiplayerDebug.info(TAG, "  Serializing ally: #{ally[:name]} (SID: #{ally[:sid]})")
      end

      ally_party_serialized = serialize_party(ally[:party] || [])

      {
        "sid" => ally[:sid].to_s,
        "name" => ally[:name].to_s,
        "party" => ally_party_serialized
      }
    end

    # Build final payload
    payload = {
      "foes" => foes_serialized,
      "allies" => allies_serialized,
      "encounter_type" => convert_to_json_safe(encounter_type),
      "battle_id" => battle_id
    }

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info(TAG, "  Payload built successfully")
      MultiplayerDebug.info(TAG, "SERIALIZE BATTLE INVITE END")
      MultiplayerDebug.info(TAG, "=" * 80)
    end

    return payload
  end

  #-----------------------------------------------------------------------------
  # Deserialize battle invite payload
  #-----------------------------------------------------------------------------
  def deserialize_battle_invite(data)
    return nil unless data.is_a?(Hash)

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info(TAG, "=" * 80)
      MultiplayerDebug.info(TAG, "DESERIALIZE BATTLE INVITE START")
      MultiplayerDebug.info(TAG, "  Data keys: #{data.keys.inspect}")
    end

    # Deserialize foe party
    foes_data = data["foes"] || data[:foes] || []
    foes = deserialize_party(foes_data)

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info(TAG, "  Foes deserialized: #{foes.length}")
      foes.each_with_index do |foe, i|
        MultiplayerDebug.info(TAG, "    Foe #{i}: #{foe.name} Lv.#{foe.level} HP=#{foe.hp}/#{foe.totalhp}")
      end
    end

    # Deserialize allies
    allies_data_raw = data["allies"] || data[:allies] || []
    allies = allies_data_raw.map do |ally_data|
      if defined?(MultiplayerDebug)
        MultiplayerDebug.info(TAG, "  Deserializing ally: #{ally_data['name']} (SID: #{ally_data['sid']})")
      end

      ally_party = deserialize_party(ally_data["party"] || ally_data[:party] || [])

      {
        sid: ally_data["sid"] || ally_data[:sid],
        name: ally_data["name"] || ally_data[:name],
        party: ally_party
      }
    end

    # Restore encounter type
    encounter_type_raw = data["encounter_type"] || data[:encounter_type]
    encounter_type = convert_from_json_safe(encounter_type_raw)

    # Get battle ID
    battle_id = data["battle_id"] || data[:battle_id]

    result = {
      foes: foes,
      allies: allies,
      encounter_type: encounter_type,
      battle_id: battle_id
    }

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info(TAG, "  Result:")
      MultiplayerDebug.info(TAG, "    Foes: #{result[:foes].length}")
      MultiplayerDebug.info(TAG, "    Allies: #{result[:allies].length}")
      MultiplayerDebug.info(TAG, "    Encounter type: #{result[:encounter_type]}")
      MultiplayerDebug.info(TAG, "    Battle ID: #{result[:battle_id]}")
      MultiplayerDebug.info(TAG, "DESERIALIZE BATTLE INVITE END")
      MultiplayerDebug.info(TAG, "=" * 80)
    end

    return result
  end

  #-----------------------------------------------------------------------------
  # Test the serializer (call from debug console)
  #-----------------------------------------------------------------------------
  def self.test
    puts "=" * 60
    puts "PokemonSerializer Test Suite"
    puts "=" * 60

    # Create a test Pokemon
    begin
      test_pokemon = Pokemon.new(:PIKACHU, 25)
      puts "[TEST] Created test Pokemon: #{test_pokemon.name} Lv.#{test_pokemon.level}"
      puts "[TEST] HP: #{test_pokemon.hp}/#{test_pokemon.totalhp}"
      puts "[TEST] Moves: #{test_pokemon.moves.map(&:id).join(', ')}"

      # Serialize
      serialized = serialize_pokemon(test_pokemon)
      if serialized
        puts "[TEST] Serialization successful"
        puts "[TEST] Serialized keys: #{serialized.keys.length}"
      else
        puts "[FAIL] Serialization returned nil"
        return false
      end

      # Convert to JSON string and back (simulates network transfer)
      json_str = MiniJSON.dump(serialized)
      puts "[TEST] JSON string length: #{json_str.length} chars"

      parsed = MiniJSON.parse(json_str)
      puts "[TEST] Parsed back from JSON"

      # Deserialize
      restored = deserialize_pokemon(parsed)
      if restored
        puts "[TEST] Deserialization successful"
        puts "[TEST] Restored: #{restored.name} Lv.#{restored.level}"
        puts "[TEST] HP: #{restored.hp}/#{restored.totalhp}"
        puts "[TEST] Moves: #{restored.moves.map(&:id).join(', ')}"

        # Verify
        if restored.species == test_pokemon.species &&
           restored.level == test_pokemon.level
          puts "[PASS] Basic properties match"
        else
          puts "[FAIL] Properties don't match"
          return false
        end
      else
        puts "[FAIL] Deserialization returned nil"
        return false
      end

      puts "=" * 60
      puts "[PASS] All tests passed!"
      puts "=" * 60
      return true

    rescue => e
      puts "[ERROR] Test failed: #{e.class}: #{e.message}"
      puts e.backtrace.first(5).join("\n")
      return false
    end
  end
end

#===============================================================================
# Module loaded
#===============================================================================
if defined?(MultiplayerDebug)
  MultiplayerDebug.info("PKM-SERIAL", "=" * 60)
  MultiplayerDebug.info("PKM-SERIAL", "002_PokemonSerializer.rb loaded")
  MultiplayerDebug.info("PKM-SERIAL", "JSON-based Pokemon serialization ready")
  MultiplayerDebug.info("PKM-SERIAL", "  PokemonSerializer.serialize_pokemon(pkmn) -> Hash")
  MultiplayerDebug.info("PKM-SERIAL", "  PokemonSerializer.deserialize_pokemon(data) -> Pokemon")
  MultiplayerDebug.info("PKM-SERIAL", "  PokemonSerializer.serialize_party(party) -> Array")
  MultiplayerDebug.info("PKM-SERIAL", "  PokemonSerializer.deserialize_party(data) -> Array")
  MultiplayerDebug.info("PKM-SERIAL", "  PokemonSerializer.serialize_battle_invite(...) -> Hash")
  MultiplayerDebug.info("PKM-SERIAL", "  PokemonSerializer.deserialize_battle_invite(data) -> Hash")
  MultiplayerDebug.info("PKM-SERIAL", "  PokemonSerializer.test -> Run test suite")
  MultiplayerDebug.info("PKM-SERIAL", "=" * 60)
end
