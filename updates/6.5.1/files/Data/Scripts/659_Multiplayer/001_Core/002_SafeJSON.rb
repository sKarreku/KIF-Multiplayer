#===============================================================================
# MODULE: SafeJSON - JSON-based Serializer for Network Data
#===============================================================================
# Replaces Marshal.dump/load with JSON for security.
# Marshal can execute arbitrary code on load - JSON cannot.
#
# Handles Ruby-specific types that JSON doesn't support natively:
#   - Symbols (:UseMove) -> {"__sym__": "UseMove"}
#   - nil in arrays -> null (native JSON)
#
# Usage:
#   SafeJSON.dump(data)  -> JSON string
#   SafeJSON.load(json)  -> Ruby object (with symbols restored)
#===============================================================================

module SafeJSON
  module_function

  #-----------------------------------------------------------------------------
  # Dump Ruby object to JSON string
  #-----------------------------------------------------------------------------
  def dump(obj)
    json_safe = to_json_safe(obj)
    result = MiniJSON.dump(json_safe)

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("SAFE-JSON", "dump: #{obj.inspect} -> #{result.length} chars")
    end

    result
  end

  #-----------------------------------------------------------------------------
  # Load JSON string back to Ruby object
  #-----------------------------------------------------------------------------
  def load(json_str)
    return nil if json_str.nil? || json_str.empty?

    begin
      parsed = MiniJSON.parse(json_str)
      result = from_json_safe(parsed)

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("SAFE-JSON", "load: #{json_str.length} chars -> #{result.inspect}")
      end

      result
    rescue => e
      if defined?(MultiplayerDebug)
        MultiplayerDebug.error("SAFE-JSON", "load failed: #{e.message}")
        MultiplayerDebug.error("SAFE-JSON", "  input: #{json_str[0..100]}...")
      end
      nil
    end
  end

  #-----------------------------------------------------------------------------
  # Convert Ruby object to JSON-safe structure
  #-----------------------------------------------------------------------------
  def to_json_safe(obj)
    case obj
    when Symbol
      # Convert symbol to tagged hash
      { "__sym__" => obj.to_s }
    when Hash
      # Convert hash (handle both string and symbol keys)
      result = {}
      obj.each do |k, v|
        # Convert symbol keys to strings with marker
        key_str = k.is_a?(Symbol) ? "__symkey__#{k}" : k.to_s
        result[key_str] = to_json_safe(v)
      end
      result
    when Array
      obj.map { |v| to_json_safe(v) }
    when String, Integer, Float, TrueClass, FalseClass, NilClass
      obj
    else
      # Unknown type - convert to string with type marker
      if defined?(MultiplayerDebug)
        MultiplayerDebug.warn("SAFE-JSON", "Unknown type #{obj.class}, converting to string")
      end
      { "__unknown__" => obj.to_s, "__class__" => obj.class.to_s }
    end
  end

  #-----------------------------------------------------------------------------
  # Convert JSON-safe structure back to Ruby object
  #-----------------------------------------------------------------------------
  def from_json_safe(obj)
    case obj
    when Hash
      # Check for symbol marker
      if obj.key?("__sym__")
        return obj["__sym__"].to_sym
      end

      # Check for unknown type marker (just return as string)
      if obj.key?("__unknown__")
        return obj["__unknown__"]
      end

      # Regular hash - restore symbol keys
      result = {}
      obj.each do |k, v|
        # Restore symbol keys
        key = k.start_with?("__symkey__") ? k.sub("__symkey__", "").to_sym : k
        result[key] = from_json_safe(v)
      end
      result
    when Array
      obj.map { |v| from_json_safe(v) }
    else
      obj
    end
  end

  #-----------------------------------------------------------------------------
  # Test the serializer (call from debug console)
  #-----------------------------------------------------------------------------
  def self.test
    test_cases = [
      # Simple values
      { input: 42, name: "integer" },
      { input: "hello", name: "string" },
      { input: true, name: "boolean" },
      { input: nil, name: "nil" },

      # Symbols (the main challenge)
      { input: :UseMove, name: "symbol" },
      { input: :SwitchOut, name: "symbol2" },

      # Arrays with symbols (like battle choices)
      { input: [:UseMove, 0, nil, 1], name: "choice array" },
      { input: [:SwitchOut, 2, nil, -1], name: "switch array" },
      { input: [:Run, nil, nil, nil], name: "run array" },

      # Hash with symbol keys (like action data)
      { input: { :turn => 5, :choice => [:UseMove, 0, nil, 1] }, name: "action hash" },

      # Nested structures
      { input: { "turn" => 3, "choice" => [:UseItem, 15, 0, nil] }, name: "mixed hash" },
    ]

    puts "=" * 60
    puts "SafeJSON Test Suite"
    puts "=" * 60

    passed = 0
    failed = 0

    test_cases.each do |tc|
      input = tc[:input]
      name = tc[:name]

      begin
        json = dump(input)
        output = load(json)

        if output == input
          puts "[PASS] #{name}: #{input.inspect}"
          passed += 1
        else
          puts "[FAIL] #{name}"
          puts "  Input:  #{input.inspect}"
          puts "  JSON:   #{json}"
          puts "  Output: #{output.inspect}"
          failed += 1
        end
      rescue => e
        puts "[ERROR] #{name}: #{e.message}"
        failed += 1
      end
    end

    puts "=" * 60
    puts "Results: #{passed} passed, #{failed} failed"
    puts "=" * 60

    failed == 0
  end
end

#-------------------------------------------------------------------------------
# Module loaded successfully
#-------------------------------------------------------------------------------
if defined?(MultiplayerDebug)
  MultiplayerDebug.info("SAFE-JSON", "=" * 60)
  MultiplayerDebug.info("SAFE-JSON", "001_SafeJSON.rb loaded")
  MultiplayerDebug.info("SAFE-JSON", "JSON-based serializer ready (replaces Marshal for security)")
  MultiplayerDebug.info("SAFE-JSON", "  SafeJSON.dump(obj) -> JSON string")
  MultiplayerDebug.info("SAFE-JSON", "  SafeJSON.load(json) -> Ruby object")
  MultiplayerDebug.info("SAFE-JSON", "  SafeJSON.test -> Run test suite")
  MultiplayerDebug.info("SAFE-JSON", "=" * 60)
end
