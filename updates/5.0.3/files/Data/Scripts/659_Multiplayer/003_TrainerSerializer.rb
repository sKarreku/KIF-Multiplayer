#===============================================================================
# MODULE: TrainerSerializer - JSON-based Trainer Serialization for Network
#===============================================================================
# Replaces Marshal.dump/load for Trainer/NPCTrainer objects with JSON.
# Uses PokemonSerializer for the trainer's party.
#
# SECURITY: This module avoids Marshal which can execute arbitrary code.
# JSON can only represent data, not executable code.
#
# Usage:
#   TrainerSerializer.serialize(trainer)   -> Hash (JSON-safe)
#   TrainerSerializer.deserialize(data)    -> NPCTrainer
#   TrainerSerializer.to_hex(trainer)      -> String (hex-encoded JSON)
#   TrainerSerializer.from_hex(hex)        -> NPCTrainer
#===============================================================================

module TrainerSerializer
  TAG = "TRAINER-SERIAL"

  module_function

  #-----------------------------------------------------------------------------
  # Serialize a Trainer/NPCTrainer to JSON-safe Hash
  #-----------------------------------------------------------------------------
  def serialize(trainer)
    return nil unless trainer.is_a?(Trainer)

    begin
      if defined?(MultiplayerDebug)
        MultiplayerDebug.info(TAG, "=" * 60)
        MultiplayerDebug.info(TAG, "SERIALIZE START: #{trainer.name} (#{trainer.trainer_type})")
        MultiplayerDebug.info(TAG, "  Party size: #{trainer.party.length}")
      end

      # Serialize the party using PokemonSerializer
      party_data = []
      if defined?(PokemonSerializer) && trainer.party.is_a?(Array)
        party_data = PokemonSerializer.serialize_party(trainer.party)
      end

      # Build trainer data hash
      data = {
        "trainer_type" => trainer.trainer_type.to_s,
        "name" => trainer.name.to_s,
        "id" => trainer.id,
        "language" => trainer.language,
        "party" => party_data,
        "sprite_override" => trainer.sprite_override,
        "lowest_difficulty" => trainer.lowest_difficulty,
        "selected_difficulty" => trainer.selected_difficulty,
        "game_mode" => trainer.game_mode
      }

      # NPCTrainer-specific fields
      if trainer.is_a?(NPCTrainer)
        data["is_npc"] = true
        data["items"] = serialize_items(trainer.items)
        data["lose_text"] = trainer.lose_text
      else
        data["is_npc"] = false
      end

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info(TAG, "  Serialized #{data.keys.length} fields")
        MultiplayerDebug.info(TAG, "  Party serialized: #{party_data.compact.length} Pokemon")
        MultiplayerDebug.info(TAG, "SERIALIZE END: Success")
        MultiplayerDebug.info(TAG, "=" * 60)
      end

      return data

    rescue => e
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error(TAG, "SERIALIZE ERROR: #{e.class}: #{e.message}")
        MultiplayerDebug.error(TAG, "  Backtrace: #{e.backtrace.first(5).join(' | ')}")
      end
      return nil
    end
  end

  #-----------------------------------------------------------------------------
  # Deserialize a Hash back to NPCTrainer object
  #-----------------------------------------------------------------------------
  def deserialize(data)
    return nil unless data.is_a?(Hash)

    begin
      if defined?(MultiplayerDebug)
        MultiplayerDebug.info(TAG, "=" * 60)
        MultiplayerDebug.info(TAG, "DESERIALIZE START")
        MultiplayerDebug.info(TAG, "  Data keys: #{data.keys.length}")
      end

      # Extract fields (support both string and symbol keys)
      trainer_type = data["trainer_type"] || data[:trainer_type]
      name = data["name"] || data[:name]
      id = data["id"] || data[:id]
      language = data["language"] || data[:language]
      party_data = data["party"] || data[:party] || []
      sprite_override = data["sprite_override"] || data[:sprite_override]
      lowest_difficulty = data["lowest_difficulty"] || data[:lowest_difficulty]
      selected_difficulty = data["selected_difficulty"] || data[:selected_difficulty]
      game_mode = data["game_mode"] || data[:game_mode]
      is_npc = data["is_npc"] || data[:is_npc]
      items_data = data["items"] || data[:items] || []
      lose_text = data["lose_text"] || data[:lose_text]

      # Convert trainer_type to symbol
      trainer_type = trainer_type.to_sym if trainer_type.is_a?(String)

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info(TAG, "  Trainer type: #{trainer_type}")
        MultiplayerDebug.info(TAG, "  Name: #{name}")
        MultiplayerDebug.info(TAG, "  Is NPC: #{is_npc}")
      end

      # Create trainer object
      trainer = if is_npc
        NPCTrainer.new(name, trainer_type, sprite_override)
      else
        Trainer.new(name, trainer_type, sprite_override)
      end

      # Set ID and language
      trainer.instance_variable_set(:@id, id) if id
      trainer.instance_variable_set(:@language, language) if language

      # Set difficulty settings
      trainer.instance_variable_set(:@lowest_difficulty, lowest_difficulty) if lowest_difficulty
      trainer.instance_variable_set(:@selected_difficulty, selected_difficulty) if selected_difficulty
      trainer.instance_variable_set(:@game_mode, game_mode) if game_mode

      # Deserialize party using PokemonSerializer
      if defined?(PokemonSerializer) && party_data.is_a?(Array)
        trainer.party = PokemonSerializer.deserialize_party(party_data)
      else
        trainer.party = []
      end

      # NPCTrainer-specific fields
      if trainer.is_a?(NPCTrainer)
        trainer.items = deserialize_items(items_data)
        trainer.lose_text = lose_text
      end

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info(TAG, "  Party restored: #{trainer.party.length} Pokemon")
        MultiplayerDebug.info(TAG, "DESERIALIZE END: Success - #{trainer.name}")
        MultiplayerDebug.info(TAG, "=" * 60)
      end

      return trainer

    rescue => e
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error(TAG, "DESERIALIZE ERROR: #{e.class}: #{e.message}")
        MultiplayerDebug.error(TAG, "  Backtrace: #{e.backtrace.first(5).join(' | ')}")
      end
      return nil
    end
  end

  #-----------------------------------------------------------------------------
  # Serialize to hex-encoded JSON string (for network transfer)
  #-----------------------------------------------------------------------------
  def to_hex(trainer)
    return "" unless trainer.is_a?(Trainer)

    begin
      data = serialize(trainer)
      return "" unless data

      # Convert to JSON
      json_str = if defined?(MiniJSON)
        MiniJSON.dump(data)
      else
        data.to_s  # Fallback (not ideal)
      end

      # Hex encode
      hex = if defined?(BinHex)
        BinHex.encode(json_str)
      else
        json_str.unpack('H*').first
      end

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info(TAG, "to_hex: JSON=#{json_str.length} chars -> hex=#{hex.length} chars")
      end

      return hex

    rescue => e
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error(TAG, "to_hex ERROR: #{e.class}: #{e.message}")
      end
      return ""
    end
  end

  #-----------------------------------------------------------------------------
  # Deserialize from hex-encoded JSON string
  #-----------------------------------------------------------------------------
  def from_hex(hex)
    return nil unless hex.is_a?(String) && hex.length > 0

    begin
      # Hex decode
      json_str = if defined?(BinHex)
        BinHex.decode(hex)
      else
        [hex].pack('H*')
      end

      # Parse JSON
      data = if defined?(MiniJSON)
        MiniJSON.parse(json_str)
      else
        nil  # Can't parse without MiniJSON
      end

      return nil unless data.is_a?(Hash)

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info(TAG, "from_hex: hex=#{hex.length} chars -> JSON=#{json_str.length} chars")
      end

      return deserialize(data)

    rescue => e
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error(TAG, "from_hex ERROR: #{e.class}: #{e.message}")
        MultiplayerDebug.error(TAG, "  Backtrace: #{e.backtrace.first(3).join(' | ')}")
      end
      return nil
    end
  end

  #-----------------------------------------------------------------------------
  # Serialize items array (symbols to strings)
  #-----------------------------------------------------------------------------
  def serialize_items(items)
    return [] unless items.is_a?(Array)
    items.map do |item|
      if item.is_a?(Symbol)
        { "__sym__" => item.to_s }
      else
        item.to_s
      end
    end
  end

  #-----------------------------------------------------------------------------
  # Deserialize items array (strings back to symbols)
  #-----------------------------------------------------------------------------
  def deserialize_items(items_data)
    return [] unless items_data.is_a?(Array)
    items_data.map do |item|
      if item.is_a?(Hash) && item["__sym__"]
        item["__sym__"].to_sym
      elsif item.is_a?(String)
        # Try to convert to symbol if it looks like an item ID
        item.to_sym
      else
        item
      end
    end
  end

  #-----------------------------------------------------------------------------
  # Test the serializer (call from debug console)
  #-----------------------------------------------------------------------------
  def self.test
    puts "=" * 60
    puts "TrainerSerializer Test Suite"
    puts "=" * 60

    begin
      # Create a test NPCTrainer
      test_trainer = NPCTrainer.new("Test", :YOUNGSTER)
      test_trainer.party << Pokemon.new(:RATTATA, 5)
      test_trainer.party << Pokemon.new(:PIDGEY, 7)
      test_trainer.items = [:POTION, :ANTIDOTE]
      test_trainer.lose_text = "You beat me!"

      puts "[TEST] Created test NPCTrainer: #{test_trainer.name}"
      puts "[TEST] Party: #{test_trainer.party.length} Pokemon"
      puts "[TEST] Items: #{test_trainer.items.inspect}"

      # Serialize
      serialized = serialize(test_trainer)
      if serialized
        puts "[TEST] Serialization successful"
        puts "[TEST] Serialized keys: #{serialized.keys.inspect}"
      else
        puts "[FAIL] Serialization returned nil"
        return false
      end

      # Convert to hex and back
      hex = to_hex(test_trainer)
      puts "[TEST] Hex encoded: #{hex.length} chars"

      restored = from_hex(hex)
      if restored
        puts "[TEST] Deserialization successful"
        puts "[TEST] Restored: #{restored.name} (#{restored.trainer_type})"
        puts "[TEST] Party: #{restored.party.length} Pokemon"
        puts "[TEST] Items: #{restored.items.inspect}"
        puts "[TEST] Lose text: #{restored.lose_text}"

        # Verify
        if restored.name == test_trainer.name &&
           restored.trainer_type == test_trainer.trainer_type &&
           restored.party.length == test_trainer.party.length
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
  MultiplayerDebug.info("TRAINER-SERIAL", "=" * 60)
  MultiplayerDebug.info("TRAINER-SERIAL", "003_TrainerSerializer.rb loaded")
  MultiplayerDebug.info("TRAINER-SERIAL", "JSON-based Trainer serialization ready")
  MultiplayerDebug.info("TRAINER-SERIAL", "  TrainerSerializer.serialize(trainer) -> Hash")
  MultiplayerDebug.info("TRAINER-SERIAL", "  TrainerSerializer.deserialize(data) -> NPCTrainer")
  MultiplayerDebug.info("TRAINER-SERIAL", "  TrainerSerializer.to_hex(trainer) -> String")
  MultiplayerDebug.info("TRAINER-SERIAL", "  TrainerSerializer.from_hex(hex) -> NPCTrainer")
  MultiplayerDebug.info("TRAINER-SERIAL", "  TrainerSerializer.test -> Run test suite")
  MultiplayerDebug.info("TRAINER-SERIAL", "=" * 60)
end
