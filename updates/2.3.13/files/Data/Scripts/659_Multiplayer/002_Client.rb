# ===========================================
# File: 002_Client.rb
# Purpose: TCP Client for Multiplayer Mod
#          (+ Squad client, Trading client, thread-safe UI queue, GTS client)
# Note: No 'json' gem required. Uses MiniJSON (subset) below for non-Pokémon payloads.
#       Co-op parties use Marshal + Hex (binary-safe) exclusively.
# ===========================================

require 'socket'
begin
  require 'digest'
rescue
  # digest may not exist on some builds; we’ll fall back to a simple hash
end

# -------- Tiny binary<->hex codec (no stdlib deps) ----------
module BinHex
  module_function
  def encode(str)
    return "" if str.nil? || str.empty?
    str.unpack('H*')[0] || ""
  end
  def decode(hex)
    return "" if hex.nil? || hex.empty?
    [hex].pack('H*')
  end
end
# ------------------------------------------------------------

# ============================================================================
# SafeMarshal - Secure Marshal wrapper for co-op data (LAN-only)
# ============================================================================
# Security: Class whitelist + size limits + deep validation
# Why Marshal: Pokemon objects complex, JSON lib unavailable, MiniJSON too slow
# Risk mitigation: Squad-only (trusted), size caps, whitelist blocks RCE
# ============================================================================
module SafeMarshal
  # Whitelist: Only allow Pokemon game objects and safe Ruby types
  # Note: Built lazily to avoid load-order issues with game constants
  def self.allowed_classes
    @allowed_classes ||= begin
      base = [
        Array, Hash, String, Symbol, Integer, Float,
        TrueClass, FalseClass, NilClass, Time
      ]
      # Add Fixnum/Bignum if they exist (Ruby < 2.4)
      base << Fixnum if defined?(Fixnum)
      base << Bignum if defined?(Bignum)
      # Add Pokemon classes if defined
      base << Pokemon if defined?(Pokemon)
      base << Pokemon::Move if defined?(Pokemon::Move)
      base << PokeBattle_Move if defined?(PokeBattle_Move)
      base << Player if defined?(Player)
      base << NPCTrainer if defined?(NPCTrainer)
      base
    end
  end

  # Size limits (prevent memory exhaustion attacks)
  MAX_PARTY_SIZE = 500_000      # 500KB for party data
  MAX_BATTLE_INVITE_SIZE = 2_000_000  # 2MB for battle invite (multiple parties + foes)

  module_function

  # Dump with SHA256 checksum for tamper detection
  def dump_with_checksum(obj)
    raw = Marshal.dump(obj)
    checksum = Digest::SHA256.hexdigest(raw)
    "#{checksum}:#{BinHex.encode(raw)}"
  end

  # Load with checksum verification
  def load_with_checksum(data, max_size:)
    checksum, hex = data.split(':', 2)
    raise "Invalid checksum format" if checksum.nil? || hex.nil?
    raise "Invalid checksum length" unless checksum.length == 64

    raw = BinHex.decode(hex)
    computed = Digest::SHA256.hexdigest(raw)

    unless checksum == computed
      raise "Checksum mismatch - data tampered (expected: #{checksum[0..7]}..., got: #{computed[0..7]}...)"
    end

    load(raw, max_size: max_size)
  end

  # Safe load with class whitelist validation
  def load(data, max_size:)
    # Size check
    if data.bytesize > max_size
      raise "Marshal data too large: #{data.bytesize} bytes (max #{max_size})"
    end

    # Unmarshal with Ruby 2.1+ permitted_classes (if available)
    # Fallback to regular Marshal.load for older Ruby
    if Marshal.respond_to?(:load) && Marshal.method(:load).arity > 1
      # Ruby 3.1+ supports permitted_classes parameter
      begin
        Marshal.load(data, permitted_classes: allowed_classes)
      rescue ArgumentError
        # Fallback if permitted_classes not supported
        Marshal.load(data)
      end
    else
      # Older Ruby - just load and validate after
      Marshal.load(data)
    end
  end

  # Validate that an object only contains allowed classes
  def validate(obj, depth = 0)
    # Prevent infinite recursion
    return true if depth > 50

    case obj
    when Array
      obj.each { |item| validate(item, depth + 1) }
    when Hash
      obj.each_pair { |k, v| validate(k, depth + 1); validate(v, depth + 1) }
    when Pokemon
      validate_pokemon(obj, depth)
    when NPCTrainer
      validate_npc_trainer(obj, depth)
    else
      # Check if object's class is in the whitelist
      unless allowed_classes.include?(obj.class)
        raise "Unsafe class in Marshal data: #{obj.class}"
      end
    end
    true
  end

  # Strict validation for Pokemon objects
  def validate_pokemon(pkmn, depth)
    return true unless defined?(Pokemon) && pkmn.is_a?(Pokemon)

    # Validate moves array
    if pkmn.respond_to?(:moves)
      moves = pkmn.moves rescue []
      raise "Pokemon moves must be Array" unless moves.is_a?(Array)
      moves.each do |move|
        next if move.nil?
        valid_move = false
        valid_move = true if defined?(Pokemon::Move) && move.is_a?(Pokemon::Move)
        valid_move = true if defined?(PokeBattle_Move) && move.is_a?(PokeBattle_Move)
        raise "Invalid move object in Pokemon: #{move.class}" unless valid_move
      end
    end

    # Validate numeric fields are in valid ranges
    if pkmn.respond_to?(:hp)
      hp = pkmn.hp rescue 0
      raise "Pokemon HP out of range: #{hp}" unless hp.is_a?(Integer) && hp >= 0 && hp <= 9999
    end

    if pkmn.respond_to?(:level)
      level = pkmn.level rescue 1
      raise "Pokemon level out of range: #{level}" unless level.is_a?(Integer) && level >= 1 && level <= 100
    end

    # Validate species is valid
    if pkmn.respond_to?(:species)
      species = pkmn.species rescue nil
      raise "Pokemon species invalid" unless species.is_a?(Symbol) || species.is_a?(Integer) || species.nil?
    end

    # Recursively validate nested objects (item, ability, etc.)
    if pkmn.respond_to?(:moves)
      moves = pkmn.moves rescue []
      moves.compact.each { |m| validate(m, depth + 1) }
    end

    true
  end

  # Strict validation for NPCTrainer objects
  def validate_npc_trainer(trainer, depth)
    return true unless defined?(NPCTrainer) && trainer.is_a?(NPCTrainer)

    # Validate party is array of Pokemon
    if trainer.respond_to?(:party)
      party = trainer.party rescue []
      raise "Trainer party must be Array" unless party.is_a?(Array)
      raise "Trainer party too large: #{party.length}" if party.length > 6
      party.compact.each do |pkmn|
        unless pkmn.is_a?(Pokemon)
          raise "Invalid Pokemon in trainer party: #{pkmn.class}"
        end
        validate_pokemon(pkmn, depth + 1)
      end
    end

    # Validate name is string
    if trainer.respond_to?(:name)
      name = trainer.name rescue ""
      raise "Trainer name must be String" unless name.is_a?(String)
      raise "Trainer name too long: #{name.length}" if name.length > 100
    end

    true
  end
end

# ---------------- MiniJSON (very small JSON subset) ----------------
# Supports: Hash (string keys), Array, String (with \" and \\ escapes), Integer/Float,
# true/false, null. Just enough for trade/GTS payloads. Co-op parties DO NOT use this.
module MiniJSON
  module_function

  def dump(obj)
    case obj
    when Hash
      parts = []
      obj.each_pair { |k,v| parts << '"' + esc(k.to_s) + '":' + dump(v) }
      '{' + parts.join(',') + '}'
    when Array
      '[' + obj.map { |v| dump(v) }.join(',') + ']'
    when String
      '"' + esc(obj) + '"'
    when Integer, Float
      obj.to_s
    when TrueClass
      'true'
    when FalseClass
      'false'
    when NilClass
      'null'
    else
      '"' + esc(obj.to_s) + '"'
    end
  end

  def parse(str)
    @s = str.to_s
    @i = 0
    val = read_value
    skip_ws
    val
  end

  # --- internals ---
  def esc(s)
    s.gsub(/["\\]/) { |m| (m == '"') ? '\"' : '\\\\' }
  end

  def skip_ws
    @i += 1 while @i < @s.length && @s[@i] =~ /\s/
  end

  def read_value
    skip_ws
    return nil if @i >= @s.length
    ch = @s[@i,1]
    case ch
    when '{' then read_object
    when '[' then read_array
    when '"' then read_string
    when 't' then read_true
    when 'f' then read_false
    when 'n' then read_null
    else          read_number
    end
  end

  def read_object
    obj = {}
    @i += 1 # skip {
    skip_ws
    return obj if @s[@i,1] == '}' && (@i += 1)
    loop do
      key = read_string
      skip_ws
      @i += 1 if @s[@i,1] == ':'  # skip :
      val = read_value
      obj[key] = val
      skip_ws
      if @s[@i,1] == '}'
        @i += 1
        break
      end
      @i += 1 if @s[@i,1] == ','  # skip ,
      skip_ws
    end
    obj
  end

  def read_array
    arr = []
    @i += 1 # skip [
    skip_ws
    return arr if @s[@i,1] == ']' && (@i += 1)
    loop do
      arr << read_value
      skip_ws
      if @s[@i,1] == ']'
        @i += 1
        break
      end
      @i += 1 if @s[@i,1] == ','  # skip ,
      skip_ws
    end
    arr
  end

  def read_string
    out = ''
    @i += 1 # skip opening "
    while @i < @s.length
      ch = @s[@i,1]
      @i += 1
      if ch == '"'
        break
      elsif ch == '\\'
        esc = @s[@i,1]; @i += 1
        case esc
        when '"';  out << '"'
        when '\\'; out << '\\'
        when '/';  out << '/'
        when 'b';  out << "\b"
        when 'f';  out << "\f"
        when 'n';  out << "\n"
        when 'r';  out << "\r"
        when 't';  out << "\t"
        else        out << esc.to_s
        end
      else
        out << ch
      end
    end
    out
  end

  def read_true
    @i += 4 # true
    true
  end

  def read_false
    @i += 5 # false
    false
  end

  def read_null
    @i += 4 # null
    nil
  end

  def read_number
    start = @i
    @i += 1 while @i < @s.length && @s[@i,1] =~ /[-+0-9.eE]/
    num = @s[start...@i]
    if num.include?('.') || num.include?('e') || num.include?('E')
      num.to_f
    else
      begin
        Integer(num)
      rescue
        0
      end
    end
  end
end
# -------------------------------------------------------------------

###MultiplayerDebug.info("C-000", "Client module loaded successfully.")

module MultiplayerClient
  SERVER_PORT        = 12975
  CONNECTION_TIMEOUT = 5.0   # seconds

  @socket        = nil
  @listen_thread = nil
  @sync_thread   = nil
  @connected     = false
  @session_id    = nil
  @player_list   = []
  @players       = {}
  @name_sent     = false
  @in_battle = false
  @player_busy = false


  # --- Squad client state ---
  @squad                   = nil  # { leader:"SIDx", members:[{sid:,name:}, ...] }
  @invite_queue            = []   # [{sid:"SIDx", name:"Name"}]
  @invite_prompt_active    = false
  @pending_invite_from_sid = nil

  # --- Trading client state ---
  @trade        = nil
  @trade_mutex  = Mutex.new
  @queue_mutex  = Mutex.new

  # --- UI message queue ---
  @toast_queue  = []

  # --- Trade event queue for UI ---
  @_trade_event_q = []

  # --- GTS client state (simplified - uses platinum UUID) ---
  @_gts_event_q    = []   # push events to UI layer
  @gts_last_error  = nil
  @platinum_uuid   = nil  # Full platinum UUID for GTS ownership checks

  # --- Co-op party cache (Marshal objects) ---
  @coop_remote_party = {}  # { "SID" => Array<Pokemon> }

  # --- Marshal rate limiter (DoS prevention) ---
  @marshal_rate_limiter = Hash.new { |h, k| h[k] = { count: 0, reset_at: Time.now + 1 } }

  # --- Co-op battle invitation queue ---
  @coop_battle_queue = []  # [{ from_sid:, foes:, allies:, encounter_type: }]
  # --- Co-op battle sync tracking (for initiator waiting for allies) ---
  @coop_battle_joined_sids = []  # Array of SIDs that have joined the current battle


  # -------------------------------------------
  # Helpers
  # -------------------------------------------
  def self.int_or_str(v)
    return v if v.nil?
    v.to_s =~ /\A-?\d+\z/ ? v.to_i : v
  end

  def self.parse_kv_csv(s)
    h = {}
    s.to_s.split(",").each do |pair|
      k, v = pair.split("=", 2)
      next if !k || !v
      h[k.to_sym] = int_or_str(v)
    end
    h
  end
  # --- Busy (battle) state ---
  def self.mark_battle(on)
    @in_battle   = !!on
    @player_busy = @in_battle   # keep a local alias if other code uses it
    ##MultiplayerDebug.info("C-STATE", "in_battle=#{@in_battle}")

    # broadcast busy=1/0 so squadmates' HUD and injector can see it
    begin
      send_data("SYNC:busy=#{@in_battle ? 1 : 0}")
      ##MultiplayerDebug.info("C-BUSY", "Sent busy=#{@in_battle ? 1 : 0}")
    rescue => e
      ##MultiplayerDebug.warn("C-BUSY", "Failed to send busy flag: #{e.message}")
    end
  end

  def self.in_battle?
    !!@in_battle
  end
  
  def self.player_busy?(sid = nil)
    sid = (sid || @session_id).to_s
    return !!@in_battle if sid == @session_id.to_s
    h = @players[sid] rescue nil
    !!(h && h[:busy].to_i == 1)
  end

  # GTS auth functions removed - now uses platinum UUID automatically

  def self.enqueue_toast(msg)
    @queue_mutex.synchronize { @toast_queue << { text: msg.to_s } }
    ##MultiplayerDebug.info("C-TOAST", "Enqueued toast: #{msg}")
  end
  def self.dequeue_toast; @queue_mutex.synchronize { @toast_queue.shift } end
  def self.toast_pending?; @queue_mutex.synchronize { !@toast_queue.empty? } end

  # Check and update Marshal operation rate limit (DoS prevention)
  def self.check_marshal_rate_limit(sid)
    sid = sid.to_s
    limit = @marshal_rate_limiter[sid]

    # Reset counter if window expired
    if Time.now > limit[:reset_at]
      limit[:count] = 0
      limit[:reset_at] = Time.now + 1
    end

    # Increment and check limit
    limit[:count] += 1
    if limit[:count] > 50
      ##MultiplayerDebug.warn("MARSHAL-RATE", "Rate limit exceeded for #{sid}: #{limit[:count]}/s")
      return false
    end

    true
  end

  def self.find_name_for_sid(sid)
    sid = sid.to_s
    if @players[sid] && @players[sid][:name]; return @players[sid][:name].to_s; end
    if @squad && @squad[:members].is_a?(Array)
      m = @squad[:members].find { |mm| mm[:sid].to_s == sid }
      return m[:name].to_s if m
    end
    sid
  end

  def self.local_trainer_snapshot
    name =
      if defined?($Trainer) && $Trainer && $Trainer.respond_to?(:name)
        ($Trainer.name || "Unknown").to_s
      else
        "Unknown"
      end

    clothes =
      if defined?($Trainer) && $Trainer && $Trainer.respond_to?(:clothes)
        ($Trainer.clothes || "001").to_s
      elsif defined?($Trainer) && $Trainer.respond_to?(:outfit)
        ($Trainer.outfit || "001").to_s
      else
        "001"
      end

    hat  = (defined?($Trainer) && $Trainer && $Trainer.respond_to?(:hat))  ? ($Trainer.hat  || "000").to_s : "000"
    hair = (defined?($Trainer) && $Trainer && $Trainer.respond_to?(:hair)) ? ($Trainer.hair || "000").to_s : "000"

    skin_tone     = (defined?($Trainer) && $Trainer && $Trainer.respond_to?(:skin_tone))     ? ($Trainer.skin_tone     || 0).to_i : 0
    hair_color    = (defined?($Trainer) && $Trainer && $Trainer.respond_to?(:hair_color))    ? ($Trainer.hair_color    || 0).to_i : 0
    hat_color     = (defined?($Trainer) && $Trainer && $Trainer.respond_to?(:hat_color))     ? ($Trainer.hat_color     || 0).to_i : 0
    clothes_color = (defined?($Trainer) && $Trainer && $Trainer.respond_to?(:clothes_color)) ? ($Trainer.clothes_color || 0).to_i : 0

    map_id = (defined?($game_map)    && $game_map)    ? $game_map.map_id : 0
    x      = (defined?($game_player) && $game_player && $game_player.x) ? $game_player.x : 0
    y      = (defined?($game_player) && $game_player && $game_player.y) ? $game_player.y : 0
    face   = (defined?($game_player) && $game_player) ? $game_player.direction : 2

    # Movement state flags (surf, dive, bike, run, fish)
    surf = (defined?($PokemonGlobal) && $PokemonGlobal && $PokemonGlobal.surfing) ? 1 : 0
    dive = (defined?($PokemonGlobal) && $PokemonGlobal && $PokemonGlobal.diving) ? 1 : 0
    bike = (defined?($PokemonGlobal) && $PokemonGlobal && $PokemonGlobal.bicycle) ? 1 : 0
    run = (defined?($game_player) && $game_player && $game_player.move_speed > 3) ? 1 : 0
    fish = (defined?($PokemonGlobal) && $PokemonGlobal && $PokemonGlobal.fishing) ? 1 : 0

    {
      name: name, clothes: clothes, hat: hat, hair: hair,
      skin_tone: skin_tone, hair_color: hair_color, hat_color: hat_color, clothes_color: clothes_color,
      map: map_id, x: x, y: y, face: face,
      surf: surf, dive: dive, bike: bike, run: run, fish: fish
    }
  end

  # --- Identity persistence & account key (removed - uses platinum UUID) ---
  # Legacy gts_uid methods removed - GTS now uses platinum UUID directly

  def self.ensure_store_dir
    dir = File.join("Data","Multiplayer")
    Dir.mkdir("Data") unless File.exist?("Data") rescue nil
    Dir.mkdir(dir)    unless File.exist?(dir)    rescue nil
  end

  def self.compute_account_key_material
    if defined?($Trainer) && $Trainer
      if $Trainer.respond_to?(:public_id) && $Trainer.public_id
        return "PUBID:#{($Trainer.public_id).to_i}"
      elsif $Trainer.respond_to?(:id) && $Trainer.id
        return "TID:#{($Trainer.id).to_i}"
      elsif $Trainer.respond_to?(:name)
        return "NAME:#{($Trainer.name || 'Player')}"
      end
    end
    "ANON"
  end

  def self.account_key
    return @_account_key if @_account_key
    src = "GTS|" + compute_account_key_material
    begin
      if defined?(Digest) && Digest.respond_to?(:SHA256)
        @_account_key = Digest::SHA256.hexdigest(src)
      elsif defined?(Digest) && Digest.const_defined?("SHA1")
        @_account_key = Digest::SHA1.hexdigest(src)
      else
        h = 0
        src.each_byte { |b| h = (h * 131 + b) & 0x7fffffff }
        @_account_key = "H#{h}"
      end
    rescue
      @_account_key = "FALLBACK_" + src.gsub(/[^A-Za-z0-9]/,'')[0,24]
    end
    @_account_key
  end

  # ===========================================
  # === Co-op Party Snapshot (Marshal+Hex)   ===
  # ===========================================
  # STRICT:
  # - ALWAYS send Marshal.dump($Trainer.party) encoded to hex (single line).
  # - ABORT send on marshal error.
  # - ONLY cache remote party on successful Marshal.load of decoded hex.
  # - Packet key: "COOP_PARTY_PUSH_HEX:<hex>"

  def self._party_snapshot_marshal_hex!
    raise "Trainer/party unavailable" unless defined?($Trainer) && $Trainer && $Trainer.respond_to?(:party)

    # Debug: Log current party state
    MultiplayerDebug.info("PARTY-SNAPSHOT", "=" * 70) if defined?(MultiplayerDebug)
    MultiplayerDebug.info("PARTY-SNAPSHOT", "Creating fresh party snapshot") if defined?(MultiplayerDebug)
    MultiplayerDebug.info("PARTY-SNAPSHOT", "  Party size: #{$Trainer.party.length}") if defined?(MultiplayerDebug)
    $Trainer.party.each_with_index do |pkmn, i|
      if pkmn
        family_info = pkmn.respond_to?(:family) ? "Family=#{pkmn.family} Sub=#{pkmn.subfamily}" : "No family attrs"
        MultiplayerDebug.info("PARTY-SNAPSHOT", "  [#{i}] #{pkmn.name} Lv.#{pkmn.level} #{family_info}") if defined?(MultiplayerDebug)
      else
        MultiplayerDebug.info("PARTY-SNAPSHOT", "  [#{i}] nil") if defined?(MultiplayerDebug)
      end
    end

    raw = Marshal.dump($Trainer.party) # Array<Pokemon> object graph
    hex = BinHex.encode(raw)
    ##MultiplayerDebug.info("PARTY-SNAPSHOT", "Marshal size=#{raw.bytesize} → hex_len=#{hex.length}")
    ##MultiplayerDebug.info("PARTY-SNAPSHOT", "=" * 70)
    hex
  end

  def self.coop_push_party_now!
    begin
      hex = _party_snapshot_marshal_hex!
      send_data("COOP_PARTY_PUSH_HEX:#{hex}")
      ##MultiplayerDebug.info("C-COOP", "Sent COOP_PARTY_PUSH_HEX (marshal payload)")
    rescue => e
      ##MultiplayerDebug.error("C-COOP", "Marshal snapshot SEND ABORT: #{e.class}: #{e.message}")
    end
  end

  def self._handle_coop_party_push_hex(from_sid, hex)
    begin
      # Rate limiting check
      unless check_marshal_rate_limit(from_sid)
        ##MultiplayerDebug.warn("PARTY-RECEIVE", "Dropped party from #{from_sid} - rate limit exceeded")
        return
      end

      ##MultiplayerDebug.info("PARTY-RECEIVE-DEBUG", "STEP 1: Starting decode for SID#{from_sid}, hex_len=#{hex.length}")
      raw  = BinHex.decode(hex.to_s)
      ##MultiplayerDebug.info("PARTY-RECEIVE-DEBUG", "STEP 2: BinHex decoded, raw_len=#{raw.length}")

      # SAFE MARSHAL: Size limit + class whitelist validation
      list = SafeMarshal.load(raw, max_size: SafeMarshal::MAX_PARTY_SIZE)
      ##MultiplayerDebug.info("PARTY-RECEIVE-DEBUG", "STEP 3: SafeMarshal loaded, list_size=#{list ? list.length : 'nil'}")
      SafeMarshal.validate(list)
      ##MultiplayerDebug.info("PARTY-RECEIVE-DEBUG", "STEP 4: SafeMarshal validated")

      unless list.is_a?(Array) && list.all? { |p| p.is_a?(Pokemon) }
        raise "Decoded payload is not Array<Pokemon> (#{list.class})"
      end
      ##MultiplayerDebug.info("PARTY-RECEIVE-DEBUG", "STEP 5: Verified Array<Pokemon>")

      # Debug: Log received party data
      ##MultiplayerDebug.info("PARTY-RECEIVE", "=" * 70)
      ##MultiplayerDebug.info("PARTY-RECEIVE", "Received remote party from SID#{from_sid}")
      ##MultiplayerDebug.info("PARTY-RECEIVE", "  Party size: #{list.length}")
      list.each_with_index do |pkmn, i|
        if pkmn
          ##MultiplayerDebug.info("PARTY-RECEIVE", "  [#{i}] #{pkmn.name} Lv.#{pkmn.level} HP=#{pkmn.hp}/#{pkmn.totalhp} EXP=#{pkmn.exp}")
        else
          ##MultiplayerDebug.info("PARTY-RECEIVE", "  [#{i}] nil")
        end
      end

      @coop_remote_party[from_sid.to_s] = list
      ##MultiplayerDebug.info("PARTY-RECEIVE", "CACHED remote party from SID#{from_sid} [SafeMarshal] with key='#{from_sid.to_s}'")
      ##MultiplayerDebug.info("PARTY-RECEIVE", "Cache now contains keys: #{@coop_remote_party.keys.inspect}")
      ##MultiplayerDebug.info("PARTY-RECEIVE", "=" * 70)

      # Snapshot debug logging
      SnapshotLog.log_snapshot_received(from_sid, list.length) if defined?(SnapshotLog)
    rescue => e
      ##MultiplayerDebug.error("C-COOP", "SafeMarshal PARTY LOAD ABORT from #{from_sid}: #{e.class}: #{e.message}")
      ##MultiplayerDebug.error("C-COOP", "Backtrace: #{e.backtrace[0, 5].join("\n")}")
    end
  end

  def self.remote_party(sid)
    key = sid.to_s
    ##MultiplayerDebug.info("PARTY-RETRIEVE-DEBUG", "Looking up party for SID=#{sid.inspect} (key='#{key}')")
    ##MultiplayerDebug.info("PARTY-RETRIEVE-DEBUG", "Cache keys available: #{@coop_remote_party.keys.inspect}")
    arr = @coop_remote_party[key]
    ##MultiplayerDebug.info("PARTY-RETRIEVE-DEBUG", "Result: #{arr ? "Array[#{arr.length}]" : 'nil'}")
    return [] unless arr.is_a?(Array) && arr.all? { |p| p.is_a?(Pokemon) }
    arr
  end

  # ===========================================
  # === Co-op Battle Invitation Queue
  # ===========================================
  def self._handle_coop_battle_invite(from_sid, hex)
    begin
      # Rate limiting check
      unless check_marshal_rate_limit(from_sid)
        ##MultiplayerDebug.warn("BATTLE-INVITE", "Dropped invite from #{from_sid} - rate limit exceeded")
        return
      end

      raw  = BinHex.decode(hex.to_s)

      # SAFE MARSHAL: Size limit + class whitelist validation
      data = SafeMarshal.load(raw, max_size: SafeMarshal::MAX_BATTLE_INVITE_SIZE)
      SafeMarshal.validate(data)

      unless data.is_a?(Hash)
        raise "Decoded payload is not Hash (#{data.class})"
      end

      invite = {
        from_sid: from_sid.to_s,
        foes: data[:foes] || [],
        allies: data[:allies] || [],
        encounter_type: data[:encounter_type],
        battle_id: data[:battle_id],  # MODULE 2: Include battle ID from initiator
        timestamp: Time.now  # Track when invite was received
      }

      # Clear queue and store ONLY this invite (single active invite limit)
      old_count = @coop_battle_queue.length
      @coop_battle_queue.clear
      @coop_battle_queue << invite

      if old_count > 0
        ##MultiplayerDebug.info("C-COOP", "Cleared #{old_count} old invite(s) - replaced with new invite from #{from_sid}")
      end

      ##MultiplayerDebug.info("C-COOP", "QUEUED battle invite from #{from_sid}: foes=#{invite[:foes].length} allies=#{invite[:allies].length} battle_id=#{invite[:battle_id].inspect}")
    rescue => e
      ##MultiplayerDebug.error("C-COOP", "SafeMarshal BATTLE INVITE ABORT from #{from_sid}: #{e.class}: #{e.message}")
    end
  end

  def self.coop_battle_pending?
    # Clean expired invites (>10 seconds old)
    unless @coop_battle_queue.empty?
      invite = @coop_battle_queue.first
      if invite && invite[:timestamp]
        age = Time.now - invite[:timestamp]
        if age > 10
          ##MultiplayerDebug.warn("C-COOP", "Expired old battle invite from #{invite[:from_sid]} (age: #{age.round(1)}s)")
          @coop_battle_queue.clear
        end
      end
    end

    !@coop_battle_queue.empty?
  end

  def self.dequeue_coop_battle
    @coop_battle_queue.shift
  end

  # Clear pending invites (called when initiator starts battle)
  def self.clear_pending_battle_invites
    count = @coop_battle_queue.length
    @coop_battle_queue.clear
    ##MultiplayerDebug.info("C-COOP", "Cleared #{count} pending battle invite(s)") if count > 0
  end


  # Handle COOP_BATTLE_JOINED message (ally has entered battle)
  def self._handle_coop_battle_joined(from_sid)
    begin
      sid_str = from_sid.to_s
      unless @coop_battle_joined_sids.include?(sid_str)
        @coop_battle_joined_sids << sid_str
        ##MultiplayerDebug.info("C-COOP", "Ally #{sid_str} has joined the battle (total: #{@coop_battle_joined_sids.length})")
      end
    rescue => e
      ##MultiplayerDebug.error("C-COOP", "Failed to handle COOP_BATTLE_JOINED from #{from_sid}: #{e.class}: #{e.message}")
    end
  end

  # Handle coop battle abort due to player disconnect
  def self._handle_coop_battle_abort(disconnected_sid, abort_reason)
    begin
      ##MultiplayerDebug.warn("C-COOP", "Handling COOP_BATTLE_ABORT: sid=#{disconnected_sid}, reason=#{abort_reason}")

      # Only abort if we're actually in a coop battle
      if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
        battle = CoopBattleState.battle_instance rescue nil

        if battle
          # CRITICAL: Don't call pbMessage from network thread - it will crash!
          # Instead, just set the battle decision flag. The battle loop will handle it.
          # Use decision=3 (ran away) instead of 5 to avoid whiteout behavior
          battle.instance_variable_set(:@decision, 3)

          # Store the abort reason so the battle end handler can show it
          battle.instance_variable_set(:@coop_abort_reason, abort_reason)

          # Force battle scene to end by calling pbEndBattle on the scene
          # This prevents the scene overlay from getting stuck on non-catchers
          begin
            scene = battle.instance_variable_get(:@scene)
            if scene && scene.respond_to?(:pbEndBattle)
              ##MultiplayerDebug.info("C-COOP", "Force calling pbEndBattle on scene to clean up overlay")
              # Call pbEndBattle with decision = 3 (ran away)
              scene.pbEndBattle(3) rescue MultiplayerDebug.warn("C-COOP", "Scene pbEndBattle call failed (may already be disposed)")
            end
          rescue => scene_err
            ##MultiplayerDebug.warn("C-COOP", "Failed to force scene cleanup: #{scene_err.message}")
          end

          ##MultiplayerDebug.info("C-COOP", "Set battle @decision to 3 (abort due to disconnect)")

          # Call emergency_abort for logging only (no UI interaction)
          CoopBattleState.emergency_abort(abort_reason) rescue nil
        else
          ##MultiplayerDebug.warn("C-COOP", "COOP_BATTLE_ABORT received but no battle instance found")
        end
      else
        ##MultiplayerDebug.warn("C-COOP", "COOP_BATTLE_ABORT received but not in coop battle")
      end
    rescue => e
      ##MultiplayerDebug.error("C-COOP", "Failed to handle COOP_BATTLE_ABORT: #{e.class}: #{e.message}")
      ##MultiplayerDebug.error("C-COOP", "  #{(e.backtrace || [])[0, 5].join(' | ')}")
    end
  end

  # Check if all expected allies have joined
  def self.all_allies_joined?(expected_ally_sids)
    expected_ally_sids.all? { |sid| @coop_battle_joined_sids.include?(sid.to_s) }
  end

  # Reset battle sync tracking
  def self.reset_battle_sync
    @coop_battle_joined_sids = []
    ##MultiplayerDebug.info("C-COOP", "Reset battle sync tracking")
  end

  # Get list of joined ally SIDs
  def self.joined_ally_sids
    @coop_battle_joined_sids.dup
  end

  # MODULE 4: Handle COOP_ACTION message
  def self._handle_coop_action(from_sid, battle_id, turn, hex_data)
    begin
      if defined?(CoopActionSync)
        CoopActionSync.receive_action(from_sid, battle_id, turn, hex_data)
      else
        ##MultiplayerDebug.warn("C-COOP", "CoopActionSync not defined, ignoring COOP_ACTION")
      end
    rescue => e
      ##MultiplayerDebug.error("C-COOP", "Failed to handle COOP_ACTION: #{e.class}: #{e.message}")
    end
  end

  # MODULE 4: Handle COOP_RNG_SEED message
  def self._handle_coop_rng_seed(from_sid, battle_id, turn, seed)
    begin
      if defined?(CoopRNGSync)
        CoopRNGSync.receive_seed(battle_id, turn, seed)
      else
        ##MultiplayerDebug.warn("C-COOP", "CoopRNGSync not defined, ignoring COOP_RNG_SEED")
      end
    rescue => e
      ##MultiplayerDebug.error("C-COOP", "Failed to handle COOP_RNG_SEED: #{e.class}: #{e.message}")
    end
  end

  # Handle COOP_MOVE_SYNC message
  def self._handle_coop_move_sync(from_sid, battle_id, idxParty, move_id, slot)
    begin
      if defined?(CoopMoveLearningSync)
        CoopMoveLearningSync.receive_move_sync(from_sid, battle_id, idxParty, move_id, slot)
      else
        ##MultiplayerDebug.warn("C-COOP", "CoopMoveLearningSync not defined, ignoring COOP_MOVE_SYNC")
      end
    rescue => e
      ##MultiplayerDebug.error("C-COOP", "Failed to handle COOP_MOVE_SYNC: #{e.class}: #{e.message}")
    end
  end

  # MODULE 14: Handle COOP_SWITCH message
  def self._handle_coop_switch(from_sid, battle_id, idxBattler, idxParty)
    begin
      if defined?(CoopSwitchSync)
        CoopSwitchSync.receive_switch(from_sid, battle_id, idxBattler, idxParty)
      else
        ##MultiplayerDebug.warn("C-COOP", "CoopSwitchSync not defined, ignoring COOP_SWITCH")
      end
    rescue => e
      ##MultiplayerDebug.error("C-COOP", "Failed to handle COOP_SWITCH: #{e.class}: #{e.message}")
    end
  end

  # MODULE 19: Handle COOP_RUN_INCREMENT message
  def self._handle_coop_run_increment(from_sid, battle_id, turn, new_value)
    begin
      if defined?(CoopRunAwaySync)
        CoopRunAwaySync.receive_run_increment(battle_id, turn, new_value)
      else
        ##MultiplayerDebug.warn("C-COOP", "CoopRunAwaySync not defined, ignoring COOP_RUN_INCREMENT")
      end
    rescue => e
      ##MultiplayerDebug.error("C-COOP", "Failed to handle COOP_RUN_INCREMENT: #{e.class}: #{e.message}")
    end
  end

  # MODULE 20: Handle COOP_RUN_ATTEMPTED message
  def self._handle_coop_run_attempted(from_sid, battle_id, turn)
    begin
      if defined?(CoopRunAwaySync)
        CoopRunAwaySync.mark_run_attempted
        ##MultiplayerDebug.info("C-COOP", "Marked run attempted from ally #{from_sid} (battle=#{battle_id}, turn=#{turn})")
      else
        ##MultiplayerDebug.warn("C-COOP", "CoopRunAwaySync not defined, ignoring COOP_RUN_ATTEMPTED")
      end
    rescue => e
      ##MultiplayerDebug.error("C-COOP", "Failed to handle COOP_RUN_ATTEMPTED: #{e.class}: #{e.message}")
    end
  end

  # MODULE 20: Handle COOP_RUN_SUCCESS message
  def self._handle_coop_run_success(from_sid, battle_id, turn)
    begin
      if defined?(CoopRunAwaySync)
        CoopRunAwaySync.receive_run_success(battle_id, turn)
      else
        ##MultiplayerDebug.warn("C-COOP", "CoopRunAwaySync not defined, ignoring COOP_RUN_SUCCESS")
      end
    rescue => e
      ##MultiplayerDebug.error("C-COOP", "Failed to handle COOP_RUN_SUCCESS: #{e.class}: #{e.message}")
    end
  end

  # Handle COOP_FORFEIT message (trainer battle forfeit)
  def self._handle_coop_forfeit(from_sid, battle_id, turn)
    begin
      ##MultiplayerDebug.info("COOP-FORFEIT", "Ally #{from_sid} forfeited trainer battle - ending battle immediately")

      # Get the current battle instance
      if defined?(CoopBattleState) && CoopBattleState.battle_instance
        battle = CoopBattleState.battle_instance

        # Mark as loss (will trigger whiteout in pbEndOfBattle)
        battle.decision = 2

        # Mark that we whited out (for coop battle state tracking)
        CoopBattleState.instance_variable_set(:@whiteout, true)

        ##MultiplayerDebug.info("COOP-FORFEIT", "✓ Battle decision set to 2 (loss), whiteout flag set")
      else
        ##MultiplayerDebug.warn("COOP-FORFEIT", "WARNING: Could not access battle instance")
      end
    rescue => e
      ##MultiplayerDebug.error("COOP-FORFEIT", "Failed to handle forfeit: #{e.class}: #{e.message}")
    end
  end

  # MODULE 20: Handle COOP_RUN_FAILED message
  def self._handle_coop_run_failed(from_sid, battle_id, turn, battler_idx)
    begin
      if defined?(CoopActionSync) && defined?(CoopBattleState)
        battle = CoopBattleState.battle_instance
        if battle
          CoopActionSync.receive_failed_run(battle, battle_id, turn.to_i, battler_idx.to_i)
        else
          ##MultiplayerDebug.warn("C-COOP", "No battle instance available for COOP_RUN_FAILED")
        end
      else
        ##MultiplayerDebug.warn("C-COOP", "CoopActionSync not defined, ignoring COOP_RUN_FAILED")
      end
    rescue => e
      ##MultiplayerDebug.error("C-COOP", "Failed to handle COOP_RUN_FAILED: #{e.class}: #{e.message}")
    end
  end

  # MODULE 21: Handle COOP_PLAYER_WHITEOUT message
  def self._handle_coop_player_whiteout(from_sid, battle_id, player_sid)
    begin
      if defined?(CoopBattleState)
        CoopBattleState.mark_player_whiteout(player_sid)
      else
        ##MultiplayerDebug.warn("C-COOP", "CoopBattleState not defined, ignoring COOP_PLAYER_WHITEOUT")
      end
    rescue => e
      ##MultiplayerDebug.error("C-COOP", "Failed to handle COOP_PLAYER_WHITEOUT: #{e.class}: #{e.message}")
    end
  end

  # ===========================================
  # === Connect to Server
  # ===========================================
  def self.connect(server_ip)
    if @connected
      ##MultiplayerDebug.warn("C-001", "Already connected; skipping new connection.")
      return
    end

    ##MultiplayerDebug.info("C-002", "Connecting to #{server_ip}:#{SERVER_PORT}")
    puts "[Multiplayer] Connecting to #{server_ip}:#{SERVER_PORT}..."

    begin
      start_time = Time.now
      @socket = TCPSocket.new(server_ip, SERVER_PORT)
      elapsed = (Time.now - start_time).round(3)

      # Store connection info for platinum UUID storage
      @host = server_ip
      @port = SERVER_PORT

      @connected = true
      ##MultiplayerDebug.info("C-003", "Connection established in #{elapsed}s")
      puts "[Multiplayer] Connected to server."

      start_listener
      start_sync_loop
    rescue => e
      ##MultiplayerDebug.error("C-004", "Connection failed: #{e.message}")
      puts "[Multiplayer] Connection failed — #{e.message}"
      @connected = false
      @socket = nil
    end
  end

  # ===========================================
  # === Listen for incoming data
  # ===========================================
  def self.start_listener
    return unless @socket
    ##MultiplayerDebug.info("C-005", "Starting listener thread.")
    Thread.abort_on_exception = false
    @listen_thread = Thread.new do
      Thread.current.abort_on_exception = false
      begin
        while (line = @socket.gets)
          data = line.to_s.strip

          # --- ID assignment ---
          if data.start_with?("ASSIGN_ID:")
            parts = data.split("|")
            @session_id = parts[0].split(":", 2)[1].to_s.strip
            ##MultiplayerDebug.info("C-006A", "Received session ID: #{@session_id}")

            # Check if server sent integrity hash
            if parts.length > 1 && parts[1].start_with?("VERIFY:")
              server_hash = parts[1].split(":", 2)[1].to_s.strip
              ##MultiplayerDebug.info("C-INTEGRITY", "Server requires file verification (hash: #{server_hash[0..7]}...)")

              # Calculate client's integrity hash
              client_hash = FileIntegrity.calculate_client_hash
              if client_hash.start_with?("error")
                ##MultiplayerDebug.error("C-INTEGRITY", "Failed to calculate client hash: #{client_hash}")
                send_data("FILE_VERIFY:error")
                @waiting_for_integrity = false
              else
                ##MultiplayerDebug.info("C-INTEGRITY", "Client hash calculated (hash: #{client_hash[0..7]}...)")
                send_data("FILE_VERIFY:#{client_hash}")
                @waiting_for_integrity = true
              end
            end
            next
          end

          # --- File integrity verification response ---
          if data.start_with?("INTEGRITY_OK")
            @waiting_for_integrity = false
            ##MultiplayerDebug.info("C-INTEGRITY", "File integrity verified!")
            next
          end

          if data.start_with?("INTEGRITY_FAIL:")
            reason = data.sub("INTEGRITY_FAIL:", "").strip
            puts "[Multiplayer] Connection rejected: #{reason}"
            ##MultiplayerDebug.error("C-INTEGRITY", "Connection rejected: #{reason}")
            @waiting_for_integrity = false
            disconnect
            next
          end

          # --- Co-op battle busy (fallback for when payload not available) ---
          if data.start_with?("COOP_BATTLE_BUSY:")
            initiator_sid = data.sub("COOP_BATTLE_BUSY:", "").strip
            # This is a fallback - normally server forwards the original battle invite
            # Only happens if server lost the payload (shouldn't occur in practice)
            ##MultiplayerDebug.info("C-COOP-QUEUE", "Battle busy fallback from #{initiator_sid}")
            next
          end

          # --- PONG response (ping tracking) ---
          if data.start_with?("{") && data.include?('"seq"') && data.include?('"timestamp"')
            begin
              # Parse JSON PONG response
              msg = MiniJSON.parse(data)
              if msg && msg["seq"] && msg["timestamp"]
                seq = msg["seq"].to_i
                original_time = msg["timestamp"].to_f

                # Calculate RTT
                if original_time > 0
                  rtt = ((Time.now.to_f - original_time) * 1000).round

                  # Store in ping tracker
                  if defined?(PingTracker)
                    MultiplayerClient.my_last_ping = rtt if MultiplayerClient.respond_to?(:my_last_ping=)
                    my_sid = @session_id
                    PingTracker.set_ping(my_sid, rtt) if my_sid
                    ##MultiplayerDebug.info("PING", "PONG received ##{seq}, RTT: #{rtt}ms")
                  end
                end
              end
            rescue => e
              ##MultiplayerDebug.error("PING", "Error processing PONG: #{e.message}")
            end
            next
          end

          # --- Player list (from server sweep) ---
          if data.start_with?("PLAYERS:")
            @player_list = data.sub("PLAYERS:", "").split(",").map(&:strip)
            ##MultiplayerDebug.info("C-PL01", "Updated player list: #{@player_list.join(', ')}")
            next
          end

          # --- Squad: state update ---
          if data.start_with?("SQUAD_STATE:")
            prev = @squad ? Marshal.load(Marshal.dump(@squad)) : nil
            body = data.sub("SQUAD_STATE:", "")
            if body == "NONE"
              @squad = nil
              ##MultiplayerDebug.info("C-SQUAD", "Squad state = NONE")

              # CRITICAL: Clear stale coop battle state when leaving squad
              # Without this, vanilla battles after leaving squad act like coop battles
              if defined?(CoopBattleState) && CoopBattleState.in_coop_battle?
                CoopBattleState.end_battle
                ##MultiplayerDebug.info("C-SQUAD", "Cleared stale coop battle state after leaving squad")
              end

              # CRITICAL: Clear pending battle invitations when leaving squad
              # Without this, player might auto-join phantom battles from old invitations
              if @coop_battle_queue && @coop_battle_queue.any?
                cleared_count = @coop_battle_queue.length
                @coop_battle_queue.clear
                ##MultiplayerDebug.info("C-SQUAD", "Cleared #{cleared_count} pending battle invitation(s) after leaving squad")
              end
            else
              leader, members_csv = body.split("|", 2)
              leader = leader.to_s.strip
              members = []
              if members_csv && !members_csv.empty?
                members_csv.split(",").each do |chunk|
                  sid,name = chunk.split("|",2)
                  members << { sid: (sid||"").to_s.strip, name: (name||"").to_s }
                end
              end
              @squad = { leader: leader, members: members }
              ##MultiplayerDebug.info("C-SQUAD", "Squad state updated: leader=#{leader}, members=#{members.map{|m|m[:sid]}.join('/')}")

              # Push party snapshot when joining squad (prevent race condition)
              if prev.nil? && @squad && @squad[:members].any?
                begin
                  coop_push_party_now! if respond_to?(:coop_push_party_now!)
                  ##MultiplayerDebug.info("C-SQUAD", "Pushed party snapshot on squad join")
                rescue => e
                  ##MultiplayerDebug.error("C-SQUAD", "Failed to push party on join: #{e.message}")
                end
              end

              begin
                my = @session_id.to_s
                if prev.nil? && @squad && @squad[:members].any?
                  if @squad[:leader] == my
                    enqueue_toast(_INTL("You are the squad leader."))
                  else
                    other = @squad[:members].find { |m| m[:sid] != my }
                    name  = other ? other[:name] : find_name_for_sid(@squad[:leader])
                    enqueue_toast(_INTL("You joined {1}'s squad.", name))
                  end
                elsif prev && @squad
                  prev_ids = prev[:members].map{|m|m[:sid]}
                  now_ids  = @squad[:members].map{|m|m[:sid]}
                  added = now_ids - prev_ids
                  if added.any? && @squad[:leader] == my
                    nm = @squad[:members].find{|m| m[:sid]==added.first}
                    enqueue_toast(_INTL("{1} joined your squad.", nm ? nm[:name] : added.first))
                  end
                  if prev[:leader] != @squad[:leader] && @squad[:leader] == my
                    enqueue_toast(_INTL("You are now the squad leader."))
                  end
                end
              rescue => e
                ##MultiplayerDebug.warn("C-SQUAD", "Toast diff err: #{e.message}")
              end
            end
            next
          end

          # ======================================
          # === CHAT SYSTEM ===
          # ======================================

          # --- CHAT: Global ---
          if data.start_with?("CHAT_GLOBAL:")
            parts = data.sub("CHAT_GLOBAL:", "").split(":", 3)
            if parts.length == 3
              sid, name, text = parts
              ChatNetwork.handle_global(sid, name, text) if defined?(ChatNetwork)
              ##MultiplayerDebug.info("C-CHAT", "Global from #{sid}: #{text[0..30]}...")
            end
            next
          end

          # --- CHAT: Trade ---
          if data.start_with?("CHAT_TRADE:")
            parts = data.sub("CHAT_TRADE:", "").split(":", 3)
            if parts.length == 3
              sid, name, text = parts
              ChatNetwork.handle_trade(sid, name, text) if defined?(ChatNetwork)
              ##MultiplayerDebug.info("C-CHAT", "Trade from #{sid}: #{text[0..30]}...")
            end
            next
          end

          # --- CHAT: Squad ---
          if data.start_with?("CHAT_SQUAD:")
            parts = data.sub("CHAT_SQUAD:", "").split(":", 3)
            if parts.length == 3
              sid, name, text = parts
              ChatNetwork.handle_squad(sid, name, text) if defined?(ChatNetwork)
              ##MultiplayerDebug.info("C-CHAT", "Squad from #{sid}: #{text[0..30]}...")
            end
            next
          end

          # --- CHAT: PM ---
          if data.start_with?("CHAT_PM:")
            parts = data.sub("CHAT_PM:", "").split(":", 3)
            if parts.length == 3
              sid, name, text = parts
              ChatNetwork.handle_pm(sid, name, text) if defined?(ChatNetwork)
              ##MultiplayerDebug.info("C-CHAT", "PM from #{sid}: #{text[0..30]}...")
            end
            next
          end

          # --- CHAT: PM Error ---
          if data.start_with?("CHAT_PM_ERROR:")
            error_msg = data.sub("CHAT_PM_ERROR:", "")
            ChatNetwork.handle_pm_error(error_msg) if defined?(ChatNetwork)
            next
          end

          # --- CHAT: Blocked ---
          if data.start_with?("CHAT_BLOCKED:")
            sid = data.sub("CHAT_BLOCKED:", "")
            ChatNetwork.handle_blocked(sid) if defined?(ChatNetwork)
            next
          end

          # --- CHAT: Block Confirmation ---
          if data.start_with?("CHAT_BLOCK_CONFIRM")
            pbMessage("You already blocked them!") if defined?(ChatNetwork)
            next
          end

          # --- Squad: invite incoming ---
          if data.start_with?("SQUAD_INVITE:")
            payload = data.sub("SQUAD_INVITE:", "")
            from_sid, from_name = payload.split("|", 2)
            enqueue_invite((from_sid||"").to_s.strip, (from_name||"").to_s)
            ##MultiplayerDebug.info("C-SQUAD", "[NET] Invite received from #{from_sid}")
            next
          end

          # --- Squad: acks/errors/info (toasts) ---
          if data.start_with?("SQUAD_INVITE_SENT:")
            target_sid = data.split(":",2)[1]
            ##MultiplayerDebug.info("C-SQUAD", "Server ack: invite sent to #{target_sid}")
            next
          end

          if data.start_with?("SQUAD_DECLINED:")
            who = data.split(":",2)[1]
            ##MultiplayerDebug.info("C-SQUAD", "Invite declined by #{who}")
            enqueue_toast(_INTL("Your invite was declined."))
            next
          end

          if data.start_with?("SQUAD_INVITE_EXPIRED:")
            who = data.split(":",2)[1]
            ##MultiplayerDebug.info("C-SQUAD", "Invite expired/missing for #{who}")
            enqueue_toast(_INTL("Your invite could not be accepted."))
            next
          end

          if data.start_with?("SQUAD_INFO:KICKED")
            ##MultiplayerDebug.info("C-SQUAD", "You were kicked from your squad.")
            enqueue_toast(_INTL("You were kicked from your squad."))
            next
          end

          if data.start_with?("SQUAD_ERROR:")
            err = data.split(":",2)[1].to_s
            ##MultiplayerDebug.warn("C-SQUAD", "[NET] Error: #{err}")
            human =
              case err
              when "INVALID_TARGET"   then _INTL("Invalid target.")
              when "INVITEE_BUSY"     then _INTL("That player already has a pending invite.")
              when "INVITEE_IN_SQUAD" then _INTL("That player is already in a squad.")
              when "SQUAD_FULL"       then _INTL("Your squad is full.")
              when "NOT_LEADER"       then _INTL("Only the squad leader can do that.")
              when "NOT_IN_SQUAD"     then _INTL("That player isn’t in your squad.")
              when "ALREADY_IN_SQUAD" then _INTL("You are already in a squad.")
              when "SQUAD_NOT_FOUND"  then _INTL("Squad not found.")
              when "INVITE_EXPIRED"   then _INTL("This invite could not be accepted.")
              when "TARGET_OFFLINE"   then _INTL("That player is offline.")
              else _INTL("Squad error: {1}", err)
              end
            enqueue_toast(human)
            next
          end

          # =======================
          # === TRADING: flow ===
          # =======================
          if data.start_with?("TRADE_INVITE:")
            body = data.sub("TRADE_INVITE:", "")
            from_sid, from_name = body.split("|", 2)
            from_sid  = (from_sid || "").to_s
            from_name = (from_name || "").to_s
            enqueue_toast(_INTL("{1} is requesting a trade.", from_name.empty? ? from_sid : from_name))
            ##MultiplayerDebug.info("C-TRADE", "Invite received from #{from_sid} (#{from_name})")
            push_trade_event(type: :invite, data: { from_sid: from_sid, from_name: from_name })
            next
          end

          if data.start_with?("TRADE_INVITE_SENT:")
            target_sid = data.split(":",2)[1].to_s
            ##MultiplayerDebug.info("C-TRADE", "Invite sent to #{target_sid}")
            enqueue_toast(_INTL("Trade invite sent."))
            next
          end

          if data.start_with?("TRADE_DECLINED:")
            who = data.split(":",2)[1].to_s
            ##MultiplayerDebug.info("C-TRADE", "Invite was declined by #{who}")
            enqueue_toast(_INTL("Your trade invite was declined."))
            next
          end

          if data.start_with?("TRADE_START:")
            rest = data.sub("TRADE_START:", "")
            parts = rest.split("|")
            tid = parts[0]
            a_pair = parts[1]
            b_pair = parts[2]
            plat_pair = parts[3] # PLATINUM=amount

            a_sid = a_pair.split("=",2)[1]
            b_sid = b_pair.split("=",2)[1]
            my_platinum = plat_pair ? plat_pair.split("=",2)[1].to_i : 0

            my    = @session_id.to_s
            @trade_mutex.synchronize do
              @trade = {
                id: tid.to_s,
                a_sid: a_sid.to_s,
                b_sid: b_sid.to_s,
                offers: { my: {}, their: {} },
                ready:  { my: false, their: false },
                confirm:{ my: false, their: false },
                state: "active",
                exec_payload: nil
              }
            end
            other_sid = (my == a_sid) ? b_sid : a_sid
            other_name = find_name_for_sid(other_sid)
            ##MultiplayerDebug.info("C-TRADE", "Started trade #{tid} with #{other_sid}(#{other_name}), you have #{my_platinum} Pt")
            enqueue_toast(_INTL("Trade started with {1}. You have {2} Platinum.", (other_name && other_name!="") ? other_name : other_sid, my_platinum))
            push_trade_event(type: :start, data: { trade_id: tid.to_s, other_sid: other_sid.to_s, other_name: (other_name || other_sid).to_s, my_platinum: my_platinum })
            next
          end

          if data.start_with?("TRADE_UPDATE:")
            body = data.sub("TRADE_UPDATE:", "")
            tid, who_sid, json = body.split("|", 3)
            begin
              offer = json && json.size>0 ? MiniJSON.parse(json) : {}
              # Backward compatibility: normalize "money" to "platinum"
              if offer["money"] && !offer["platinum"]
                offer["platinum"] = offer["money"]
              end
            rescue => e
              ##MultiplayerDebug.warn("C-TRADE", "Bad JSON in TRADE_UPDATE: #{e.message}")
              offer = {}
            end
            my = @session_id.to_s
            @trade_mutex.synchronize do
              next unless @trade && @trade[:id] == tid
              if who_sid.to_s == my
                @trade[:offers][:my] = offer
                @trade[:ready][:my]    = false
                @trade[:confirm][:my]  = false
              else
                @trade[:offers][:their] = offer
                @trade[:ready][:their]   = false
                @trade[:confirm][:their] = false
              end
            end
            ##MultiplayerDebug.info("C-TRADE", "Offer update in #{tid} from #{who_sid}")
            push_trade_event(type: :update, data: { trade_id: tid.to_s, from_sid: who_sid.to_s, offer: offer })
            next
          end

          if data.start_with?("TRADE_READY:")
            body = data.sub("TRADE_READY:", "")
            tid, who_sid, val = body.split("|", 3)
            is_true = (val.to_s == "true" || val.to_s == "ON")
            my = @session_id.to_s
            ##MultiplayerDebug.info("TRADE-DBG", "=== TRADE_READY RECEIVED ===")
            ##MultiplayerDebug.info("TRADE-DBG", "  tid=#{tid}, who=#{who_sid}, ready=#{is_true}")
            @trade_mutex.synchronize do
              next unless @trade && @trade[:id] == tid
              if who_sid.to_s == my
                @trade[:ready][:my]   = is_true
                @trade[:confirm][:my] = false unless is_true
              else
                @trade[:ready][:their]   = is_true
                @trade[:confirm][:their] = false unless is_true
              end
              ##MultiplayerDebug.info("TRADE-DBG", "  my_ready=#{@trade[:ready][:my]}, their_ready=#{@trade[:ready][:their]}")
              ##MultiplayerDebug.info("TRADE-DBG", "  my_confirm=#{@trade[:confirm][:my]}, their_confirm=#{@trade[:confirm][:their]}")
            end
            ##MultiplayerDebug.info("C-TRADE", "Ready(#{is_true}) in #{tid} by #{who_sid}")
            push_trade_event(type: :ready, data: { trade_id: tid.to_s, sid: who_sid.to_s, ready: is_true })
            next
          end

          if data.start_with?("TRADE_CONFIRM:")
            body = data.sub("TRADE_CONFIRM:", "")
            tid, who_sid, _ = body.split("|", 3)
            my = @session_id.to_s
            ##MultiplayerDebug.info("TRADE-DBG", "=== TRADE_CONFIRM RECEIVED ===")
            ##MultiplayerDebug.info("TRADE-DBG", "  tid=#{tid}, who=#{who_sid}")
            @trade_mutex.synchronize do
              next unless @trade && @trade[:id] == tid
              if who_sid.to_s == my
                @trade[:confirm][:my] = true
              else
                @trade[:confirm][:their] = true
              end
              ##MultiplayerDebug.info("TRADE-DBG", "  my_confirm=#{@trade[:confirm][:my]}, their_confirm=#{@trade[:confirm][:their]}")
            end
            ##MultiplayerDebug.info("C-TRADE", "Confirm in #{tid} by #{who_sid}")
            push_trade_event(type: :confirm, data: { trade_id: tid.to_s, sid: who_sid.to_s })
            next
          end

          if data.start_with?("TRADE_EXECUTE:")
            body = data.sub("TRADE_EXECUTE:", "")
            ##MultiplayerDebug.info("TRADE-DBG", "=== TRADE_EXECUTE RECEIVED ===")
            ##MultiplayerDebug.info("TRADE-DBG", "  Raw body (first 200 chars): #{body[0, 200]}")

            # Server sends: "T3|{}|{...}" (pipe-delimited: tid|my_final_json|their_final_json)
            parts = body.split("|", 3)
            tid = parts[0].to_s
            my_final_json = parts[1].to_s
            their_final_json = parts[2].to_s

            ##MultiplayerDebug.info("TRADE-DBG", "  Parsed pipe format: tid=#{tid}")
            payload = { my_final: {}, their_final: {} }
            begin
              # Parse JSON strings for each player's final offer
              payload[:my_final]    = my_final_json.size > 0    ? MiniJSON.parse(my_final_json)    : {}
              payload[:their_final] = their_final_json.size > 0 ? MiniJSON.parse(their_final_json) : {}
              ##MultiplayerDebug.info("TRADE-DBG", "  my_final parsed: #{payload[:my_final].inspect}")
              ##MultiplayerDebug.info("TRADE-DBG", "  their_final parsed: #{payload[:their_final].inspect}")
            rescue => e
              ##MultiplayerDebug.error("C-TRADE", "EXECUTE payload parse failed: #{e.class}: #{e.message}")
              ##MultiplayerDebug.error("TRADE-DBG", "  my_final_json: #{my_final_json}")
              ##MultiplayerDebug.error("TRADE-DBG", "  their_final_json: #{their_final_json}")
              payload = { my_final: {}, their_final: {} }
            end
            @trade_mutex.synchronize do
              if @trade && @trade[:id] == tid
                @trade[:state] = "executing"
                @trade[:exec_payload] = payload
              end
            end
            ##MultiplayerDebug.info("C-TRADE", "EXECUTE received for #{tid} (payload ready)")
            enqueue_toast(_INTL("Trade confirmed. Finalizing..."))
            push_trade_event(type: :execute, data: { trade_id: tid.to_s, payload: payload })
            next
          end

          if data.start_with?("TRADE_COMPLETE:")
            tid = data.split(":",2)[1].to_s
            @trade_mutex.synchronize do
              if @trade && @trade[:id] == tid
                @trade[:state] = "complete"
              end
            end
            ##MultiplayerDebug.info("C-TRADE", "Trade #{tid} complete")
            enqueue_toast(_INTL("Trade complete."))
            push_trade_event(type: :complete, data: { trade_id: tid.to_s })
            next
          end

          if data.start_with?("TRADE_ABORT:")
            body = data.sub("TRADE_ABORT:", "")
            tid, reason = body.split("|", 2)
            reason ||= "ABORTED"
            ##MultiplayerDebug.info("TRADE-DBG", "=== TRADE_ABORT RECEIVED ===")
            ##MultiplayerDebug.info("TRADE-DBG", "  tid=#{tid}, reason=#{reason}")
            @trade_mutex.synchronize do
              if @trade && @trade[:id] == tid
                @trade[:state] = "aborted"
                ##MultiplayerDebug.info("TRADE-DBG", "  Setting state to 'aborted'")
              else
                ##MultiplayerDebug.warn("TRADE-DBG", "  No matching trade found (expected #{tid}, have #{@trade ? @trade[:id] : 'nil'})")
              end
            end
            ##MultiplayerDebug.warn("C-TRADE", "Trade #{tid} aborted: #{reason}")
            enqueue_toast(_INTL("Trade aborted: {1}", reason.to_s))
            push_trade_event(type: :abort, data: { trade_id: tid.to_s, reason: reason.to_s })
            next
          end

          if data.start_with?("TRADE_ERROR:")
            err = data.split(":", 2)[1].to_s
            ##MultiplayerDebug.warn("C-TRADE", "Server error: #{err}")
            human =
              case err
              when "INVALID_TARGET"     then _INTL("Invalid trade target.")
              when "TARGET_OFFLINE"     then _INTL("That player is offline.")
              when "TARGET_BUSY"        then _INTL("That player is already trading.")
              when "BUSY"               then _INTL("You are already trading.")
              when "NO_SESSION"         then _INTL("No active trade.")
              when "NOT_PARTICIPANT"    then _INTL("You are not part of this trade.")
              when "BAD_DECISION"       then _INTL("Invalid response.")
              when "REQUESTER_OFFLINE"  then _INTL("Requester went offline.")
              when "BAD_JSON"           then _INTL("Invalid offer data.")
              when "NOT_READY"          then _INTL("You must mark Ready first.")
              else _INTL("Trade error: {1}", err)
              end
            enqueue_toast(human)
            push_gts_event(type: :err, data: { err: err.to_s })
            next
          end

          # =========================
          # === GTS: Client side ===
          # =========================
          if data.start_with?("GTS_OK:")
            begin
              obj = MiniJSON.parse(data.sub("GTS_OK:", "")) || {}
            rescue => e
              ##MultiplayerDebug.warn("C-GTS", "Bad GTS_OK json: #{e.message}")
              next
            end
            act = (obj["action"] || "").to_s
            case act
            when "GTS_REGISTER"
              # Store platinum UUID for GTS ownership checks
              uuid = obj.dig("payload", "uuid")
              if uuid
                @platinum_uuid = uuid
                @gts_uid = uuid  # Keep for backward compatibility
                ##MultiplayerDebug.info("C-GTS", "GTS registered with UUID: #{uuid[0..7]}...")
              end
              enqueue_toast(_INTL("GTS: Ready to trade!"))

            when "GTS_LIST"
              ##MultiplayerDebug.info("GTS-DBG", "=== GTS_LIST OK (002_Client) ===")
              ##MultiplayerDebug.info("GTS-DBG", "  obj.keys = #{obj.keys.inspect}")
              ##MultiplayerDebug.info("GTS-DBG", "  obj['payload'] = #{obj['payload'].inspect}")
              enqueue_toast(_INTL("GTS: Listing created."))

            when "GTS_CANCEL"
              ##MultiplayerDebug.info("C-GTS", "Cancel ACK received; waiting for GTS_RETURN to restore/list remove.")

            when "GTS_WALLET_SNAPSHOT"
              bal = (obj["payload"] && obj["payload"]["wallet"]).to_i
              if bal > 0
                begin
                  MultiplayerClient.gts_wallet_claim
                rescue => e
                  ##MultiplayerDebug.warn("C-GTS", "wallet_claim send failed: #{e.message}")
                end
              else
                enqueue_toast(_INTL("GTS: Wallet balance $0."))
              end

            when "GTS_WALLET_CLAIM"
              claimed = (obj["payload"] && obj["payload"]["claimed"]).to_i
              if claimed > 0
                begin
                  if defined?(TradeUI) && TradeUI.respond_to?(:add_money)
                    TradeUI.add_money(claimed)
                  elsif defined?($Trainer) && $Trainer && $Trainer.respond_to?(:money=)
                    $Trainer.money = ($Trainer.money || 0) + claimed
                  end
                rescue => e
                  ##MultiplayerDebug.warn("C-GTS", "adding claimed money failed: #{e.message}")
                end
                begin
                  TradeUI.autosave_safely if defined?(TradeUI)
                rescue; end
              end
              enqueue_toast(_INTL("GTS: Claimed ${1}.", claimed))
            end

            push_gts_event(type: :ok, data: obj)
            next
          end

          if data.start_with?("GTS_ERR:")
            begin
              obj = MiniJSON.parse(data.sub("GTS_ERR:", "")) || {}
            rescue => e
              ##MultiplayerDebug.warn("C-GTS", "Bad GTS_ERR json: #{e.message}")
              next
            end
            @gts_last_error = obj
            code = (obj["code"] || "ERR").to_s
            case code
            when "BAD_JSON"       then enqueue_toast(_INTL("GTS: Invalid request."))
            when "UNAVAILABLE"    then enqueue_toast(_INTL("GTS: Register first."))
            when "LISTING_GONE"   then enqueue_toast(_INTL("GTS: Listing not available."))
            when "NOT_OWNER"      then enqueue_toast(_INTL("GTS: You don't own that listing."))
            when "ESCROW_ERROR"   then enqueue_toast(_INTL("GTS: Listing is locked."))
            when "BAD_REQUEST"    then enqueue_toast(_INTL("GTS: Bad request."))
            else                         enqueue_toast(_INTL("GTS: Error ({1}).", code))
            end
            push_gts_event(type: :err, data: obj)
            next
          end

          if data.start_with?("GTS_RETURN:")
            begin
              obj = MiniJSON.parse(data.sub("GTS_RETURN:", "")) || {}
            rescue => e
              ##MultiplayerDebug.warn("C-GTS", "Bad GTS_RETURN json: #{e.message}")
              next
            end
            lid  = (obj["listing_id"] || "").to_s
            kind = (obj["kind"] || "").to_s
            pay  = obj["payload"]

            ok, reason = gts_apply_return(kind, pay)
            if ok
              send_data("GTS_RETURN_OK:#{lid}")
              enqueue_toast(_INTL("GTS: Listing canceled."))
            else
              send_data("GTS_RETURN_FAIL:#{lid}|#{reason.to_s}")
              enqueue_toast(_INTL("GTS: Cancel failed ({1}).", reason.to_s))
            end
            next
          end

          if data.start_with?("GTS_EXECUTE:")
            begin
              body = data.sub("GTS_EXECUTE:", "")
              obj  = MiniJSON.parse(body) || {}
            rescue => e
              ##MultiplayerDebug.error("C-GTS", "EXECUTE parse failed: #{e.message}")
              next
            end
            lid   = (obj["listing_id"] || "").to_s
            kind  = (obj["kind"] || "").to_s
            price = (obj["price"] || 0).to_i
            ok, reason = gts_apply_execution(kind, obj["payload"], price)
            if ok
              send_data("GTS_EXECUTE_OK:#{lid}")
              begin
                TradeUI.autosave_safely if defined?(TradeUI)
              rescue; end
              enqueue_toast(_INTL("GTS: Purchase complete."))
            else
              send_data("GTS_EXECUTE_FAIL:#{lid}|#{reason.to_s}")
              enqueue_toast(_INTL("GTS: Purchase failed ({1}).", reason.to_s))
            end
            next
          end

          # ===========================================
          # === Wild Battle Platinum Rewards =========
          # ===========================================
          if data.start_with?("WILD_PLAT_OK:")
            parts = data.sub("WILD_PLAT_OK:", "").split(":")
            reward = parts[0].to_i
            new_balance = parts[1].to_i

            # Accumulate rewards during battle instead of showing immediately
            @wild_platinum_accumulated ||= 0
            @wild_platinum_accumulated += reward

            # Update cached balance with server-provided value (server-authoritative)
            if defined?($PokemonGlobal) && $PokemonGlobal
              $PokemonGlobal.platinum_balance = new_balance
              ##MultiplayerDebug.info("WILD-PLAT", "Accumulated platinum: +#{reward} (total pending: #{@wild_platinum_accumulated})")
            end
            next
          end

          if data.start_with?("WILD_PLAT_ERR:")
            # Silent error handling - don't spam user with rate limit messages
            error = data.sub("WILD_PLAT_ERR:", "")
            ##MultiplayerDebug.warn("WILD-PLAT", "Error: #{error}")
            next
          end

          # --- Co-op: server asks us to push our party snapshot now ---
          if data.start_with?("COOP_PARTY_PUSH_NOW")
            ##MultiplayerDebug.info("C-COOP", "[NET] Received COOP_PARTY_PUSH_NOW → pushing Marshal snapshot")
            coop_push_party_now!
            next
          end

          # --- FROM:SID|... wrapper (server broadcast) ---
          if data.start_with?("FROM:")
            begin
              from_sid, payload = data.split("|", 2)
              sid = from_sid.split(":", 2)[1]
              next if sid.nil? || sid == @session_id

              # Debug log for COOP_BATTLE_ABORT to verify server sends it
              if payload && payload.start_with?("COOP_BATTLE_ABORT:")
                ##MultiplayerDebug.warn("C-COOP-DBG", "Received COOP_BATTLE_ABORT message from #{sid}: #{payload[0, 150]}")
              end

              if payload.start_with?("SYNC:")
                kv = parse_kv_csv(payload.sub("SYNC:", ""))
                @players[sid] ||= {}
                @players[sid].merge!(kv)
                # Track last activity time for disconnect detection
                @players[sid][:last_sync_time] = Time.now

              elsif payload.start_with?("NAME:")
                pname = payload.sub("NAME:", "")
                @players[sid] ||= {}
                @players[sid][:name] = pname
                ##MultiplayerDebug.info("C-NAME-RCV", "NAME from #{sid}: #{pname}")

              elsif payload.start_with?("COOP_PARTY_PUSH_HEX:")
                hex = payload.sub("COOP_PARTY_PUSH_HEX:", "")
                ##MultiplayerDebug.info("C-COOP", "[NET] COOP_PARTY_PUSH_HEX from #{sid} (hex_len=#{hex.length})")
                _handle_coop_party_push_hex(sid, hex)

              elsif payload.start_with?("COOP_BTL_START:")
                hex = payload.sub("COOP_BTL_START:", "")
                ##MultiplayerDebug.info("C-COOP", "[NET] COOP_BTL_START from #{sid} (hex_len=#{hex.length})")
                _handle_coop_battle_invite(sid, hex)
              elsif payload.start_with?("COOP_BATTLE_JOINED:")
                ##MultiplayerDebug.info("C-COOP", "[NET] COOP_BATTLE_JOINED from #{sid}")
                _handle_coop_battle_joined(sid)

              # MODULE 4: New coop sync messages
              elsif payload.start_with?("COOP_ACTION:")
                # Format: COOP_ACTION:<battle_id>|<turn>|<hex_data>
                parts = payload.sub("COOP_ACTION:", "").split("|", 3)
                if parts.length == 3
                  battle_id, turn, hex = parts
                  ##MultiplayerDebug.info("C-COOP", "[NET] COOP_ACTION from #{sid}: battle=#{battle_id}, turn=#{turn}, hex_len=#{hex.length}")
                  _handle_coop_action(sid, battle_id, turn.to_i, hex)

                  # Send ACK back to server
                  begin
                    send_data("COOP_ACTION_ACK:#{battle_id}|#{turn}|#{sid}")
                    ##MultiplayerDebug.info("C-COOP-ACK", "Sent ACK for action: battle=#{battle_id}, turn=#{turn}, from=#{sid}")
                  rescue => e
                    ##MultiplayerDebug.error("C-COOP-ACK", "Failed to send ACK: #{e.message}")
                  end
                end

              elsif payload.start_with?("COOP_RNG_SEED:")
                # Format: COOP_RNG_SEED:<battle_id>|<turn>|<seed>
                parts = payload.sub("COOP_RNG_SEED:", "").split("|", 3)
                if parts.length == 3
                  battle_id, turn, seed = parts
                  ##MultiplayerDebug.info("SEED-NET-PARSE", "Raw network message received:")
                  ##MultiplayerDebug.info("SEED-NET-PARSE", "  Full payload: #{payload}")
                  ##MultiplayerDebug.info("SEED-NET-PARSE", "  Parsed: battle_id=#{battle_id}, turn=#{turn}, seed=#{seed}")
                  ##MultiplayerDebug.info("SEED-NET-PARSE", "  Types: #{battle_id.class}, #{turn.class}, #{seed.class}")
                  ##MultiplayerDebug.info("SEED-NET-PARSE", "  Calling _handle_coop_rng_seed(#{sid}, #{battle_id}, #{turn.to_i}, #{seed.to_i})")
                  _handle_coop_rng_seed(sid, battle_id, turn.to_i, seed.to_i)
                end

              elsif payload.start_with?("COOP_RNG_SEED_ACK:")
                # Format: COOP_RNG_SEED_ACK:<battle_id>|<turn>
                parts = payload.sub("COOP_RNG_SEED_ACK:", "").split("|", 2)
                if parts.length == 2
                  battle_id, turn = parts
                  ##MultiplayerDebug.info("C-COOP", "[NET] COOP_RNG_SEED_ACK from #{sid}: battle=#{battle_id}, turn=#{turn}")
                  # Acknowledgment received (for future use)
                end

              elsif payload.start_with?("COOP_BATTLE_ABORT:")
                # Format: COOP_BATTLE_ABORT:<disconnected_sid>|<abort_reason>
                parts = payload.sub("COOP_BATTLE_ABORT:", "").split("|", 2)
                if parts.length == 2
                  disconnected_sid, abort_reason = parts
                  ##MultiplayerDebug.warn("C-COOP", "[NET] COOP_BATTLE_ABORT from #{sid}: disconnected=#{disconnected_sid}, reason=#{abort_reason}")
                  _handle_coop_battle_abort(disconnected_sid, abort_reason)
                end

              elsif payload.start_with?("COOP_MOVE_SYNC:")
                # Format: COOP_MOVE_SYNC:<battle_id>|<idxParty>|<move_id>|<slot>
                parts = payload.sub("COOP_MOVE_SYNC:", "").split("|", 4)
                if parts.length == 4
                  battle_id, idxParty, move_id, slot = parts
                  ##MultiplayerDebug.info("C-COOP", "[NET] COOP_MOVE_SYNC from #{sid}: battle=#{battle_id}, party=#{idxParty}, move=#{move_id}, slot=#{slot}")
                  _handle_coop_move_sync(sid, battle_id, idxParty.to_i, move_id.to_sym, slot.to_i)
                end

              elsif payload.start_with?("COOP_SWITCH:")
                # Format: COOP_SWITCH:<battle_id>|<idxBattler>|<idxParty>
                parts = payload.sub("COOP_SWITCH:", "").split("|", 3)
                if parts.length == 3
                  battle_id, idxBattler, idxParty = parts
                  ##MultiplayerDebug.info("C-COOP", "[NET] COOP_SWITCH from #{sid}: battle=#{battle_id}, battler=#{idxBattler}, party=#{idxParty}")
                  _handle_coop_switch(sid, battle_id, idxBattler.to_i, idxParty.to_i)
                end

              elsif payload.start_with?("COOP_RUN_INCREMENT:")
                # Format: COOP_RUN_INCREMENT:<battle_id>|<turn>|<new_value>
                parts = payload.sub("COOP_RUN_INCREMENT:", "").split("|", 3)
                if parts.length == 3
                  battle_id, turn, new_value = parts
                  ##MultiplayerDebug.info("C-COOP", "[NET] COOP_RUN_INCREMENT from #{sid}: battle=#{battle_id}, turn=#{turn}, new_value=#{new_value}")
                  _handle_coop_run_increment(sid, battle_id, turn.to_i, new_value)
                end

              elsif payload.start_with?("COOP_RUN_ATTEMPTED:")
                # Format: COOP_RUN_ATTEMPTED:<battle_id>|<turn>
                parts = payload.sub("COOP_RUN_ATTEMPTED:", "").split("|", 2)
                if parts.length == 2
                  battle_id, turn = parts
                  ##MultiplayerDebug.info("C-COOP", "[NET] COOP_RUN_ATTEMPTED from #{sid}: battle=#{battle_id}, turn=#{turn}")
                  _handle_coop_run_attempted(sid, battle_id, turn.to_i)
                end

              elsif payload.start_with?("COOP_RUN_SUCCESS:")
                # Format: COOP_RUN_SUCCESS:<battle_id>|<turn>
                parts = payload.sub("COOP_RUN_SUCCESS:", "").split("|", 2)
                if parts.length == 2
                  battle_id, turn = parts
                  ##MultiplayerDebug.info("C-COOP", "[NET] COOP_RUN_SUCCESS from #{sid}: battle=#{battle_id}, turn=#{turn}")
                  _handle_coop_run_success(sid, battle_id, turn.to_i)
                end

              elsif payload.start_with?("COOP_FORFEIT:")
                # Format: COOP_FORFEIT:<battle_id>|<turn>
                parts = payload.sub("COOP_FORFEIT:", "").split("|", 2)
                if parts.length == 2
                  battle_id, turn = parts
                  ##MultiplayerDebug.info("C-COOP", "[NET] COOP_FORFEIT from #{sid}: battle=#{battle_id}, turn=#{turn}")
                  _handle_coop_forfeit(sid, battle_id, turn.to_i)
                end

              elsif payload.start_with?("COOP_RUN_FAILED:")
                # Format: COOP_RUN_FAILED:<battle_id>|<turn>|<battler_idx>
                parts = payload.sub("COOP_RUN_FAILED:", "").split("|", 3)
                if parts.length == 3
                  battle_id, turn, battler_idx = parts
                  ##MultiplayerDebug.info("C-COOP", "[NET] COOP_RUN_FAILED from #{sid}: battle=#{battle_id}, turn=#{turn}, battler=#{battler_idx}")
                  _handle_coop_run_failed(sid, battle_id, turn, battler_idx)
                end

              elsif payload.start_with?("COOP_PLAYER_WHITEOUT:")
                # Format: COOP_PLAYER_WHITEOUT:<battle_id>|<player_sid>
                parts = payload.sub("COOP_PLAYER_WHITEOUT:", "").split("|", 2)
                if parts.length == 2
                  battle_id, player_sid = parts
                  ##MultiplayerDebug.info("C-COOP", "[NET] COOP_PLAYER_WHITEOUT from #{sid}: battle=#{battle_id}, player=#{player_sid}")
                  _handle_coop_player_whiteout(sid, battle_id, player_sid.to_i)
                end

              # === TRAINER BATTLE SYNC MESSAGES ===
              elsif payload.start_with?("COOP_TRAINER_SYNC_WAIT:")
                # Format: COOP_TRAINER_SYNC_WAIT:<battle_id>|<trainer_data_hex>|<map_id>|<event_id>
                parts = payload.sub("COOP_TRAINER_SYNC_WAIT:", "").split("|", 4)
                if parts.length == 4
                  battle_id, trainer_hex, map_id, event_id = parts
                  ##MultiplayerDebug.info("C-COOP-TRAINER", "[NET] COOP_TRAINER_SYNC_WAIT from #{sid}: battle=#{battle_id}, map=#{map_id}, event=#{event_id}, hex_len=#{trainer_hex.length}")
                  _handle_coop_trainer_sync_wait(sid, battle_id, trainer_hex, map_id.to_i, event_id.to_i)
                end

              elsif payload.start_with?("COOP_TRAINER_JOINED:")
                # Format: COOP_TRAINER_JOINED:<battle_id>|<joined_sid>
                parts = payload.sub("COOP_TRAINER_JOINED:", "").split("|", 2)
                if parts.length == 2
                  battle_id, joined_sid = parts
                  ##MultiplayerDebug.info("C-COOP-TRAINER", "[NET] COOP_TRAINER_JOINED from #{sid}: battle=#{battle_id}, joined=#{joined_sid}")
                  # CRITICAL: Keep joined_sid as string (e.g., "SID2"), don't convert to int
                  _handle_coop_trainer_joined(sid, battle_id, joined_sid)
                end

              elsif payload.start_with?("COOP_TRAINER_READY:")
                # Format: COOP_TRAINER_READY:<battle_id>
                battle_id = payload.sub("COOP_TRAINER_READY:", "")
                ##MultiplayerDebug.info("C-COOP-TRAINER", "[NET] COOP_TRAINER_READY from #{sid}: battle=#{battle_id}")
                _handle_coop_trainer_ready(sid, battle_id, true)

              elsif payload.start_with?("COOP_TRAINER_UNREADY:")
                # Format: COOP_TRAINER_UNREADY:<battle_id>
                battle_id = payload.sub("COOP_TRAINER_UNREADY:", "")
                ##MultiplayerDebug.info("C-COOP-TRAINER", "[NET] COOP_TRAINER_UNREADY from #{sid}: battle=#{battle_id}")
                _handle_coop_trainer_ready(sid, battle_id, false)

              elsif payload.start_with?("COOP_TRAINER_START_BATTLE:")
                # Format: COOP_TRAINER_START_BATTLE:<battle_id>
                battle_id = payload.sub("COOP_TRAINER_START_BATTLE:", "")
                ##MultiplayerDebug.info("C-COOP-TRAINER", "[NET] COOP_TRAINER_START_BATTLE from #{sid}: battle=#{battle_id}")
                _handle_coop_trainer_start_battle(sid, battle_id)

              elsif payload.start_with?("COOP_TRAINER_CANCELLED:")
                # Format: COOP_TRAINER_CANCELLED:<battle_id>
                battle_id = payload.sub("COOP_TRAINER_CANCELLED:", "")
                ##MultiplayerDebug.info("C-COOP-TRAINER", "[NET] COOP_TRAINER_CANCELLED from #{sid}: battle=#{battle_id}")
                _handle_coop_trainer_cancelled(sid, battle_id)
              end
            rescue => e
              ##MultiplayerDebug.error("C-FROMERR", "Failed to parse FROM wrapper: #{e.message}")
            end
            next
          end

          # --- Platinum: Auth token assignment ---
          if data.start_with?("AUTH_TOKEN:")
            token = data.sub("AUTH_TOKEN:", "").strip
            server_key = "#{@host}:#{@port}"
            MultiplayerPlatinum.store_token(server_key, token)
            ##MultiplayerDebug.info("C-PLATINUM", "Received auth token for #{server_key}")
            next
          end

          # --- Platinum: UUID assignment ---
          if data.start_with?("PLATINUM_UUID:")
            uuid = data.sub("PLATINUM_UUID:", "").strip
            @platinum_uuid = uuid
            @gts_uid = uuid  # Backward compatibility

            # Save UUID to local file (per-server)
            begin
              server_key = "#{@host}:#{@port}"
              if defined?(PlatinumUUIDStorage)
                PlatinumUUIDStorage.set_uuid(server_key, uuid)
                ##MultiplayerDebug.info("C-PLATINUM", "Received + saved platinum UUID: #{uuid[0..7]}... for #{server_key}")
              else
                ##MultiplayerDebug.warn("C-PLATINUM", "Received UUID but PlatinumUUIDStorage not available")
              end
            rescue => e
              ##MultiplayerDebug.warn("C-PLATINUM", "Failed to save UUID: #{e.message}")
            end
            next
          end

          # --- Platinum: Auth OK ---
          if data == "AUTH_OK"
            ##MultiplayerDebug.info("C-PLATINUM", "Authentication successful")
            next
          end

          # --- Platinum: Auth failed ---
          if data.start_with?("AUTH_FAIL:")
            reason = data.sub("AUTH_FAIL:", "").strip
            ##MultiplayerDebug.warn("C-PLATINUM", "Authentication failed: #{reason}")
            # Server will likely kick us, just log it
            next
          end

          # --- Platinum: Balance response ---
          if data.start_with?("PLATINUM_BAL:")
            balance = data.sub("PLATINUM_BAL:", "").to_i
            MultiplayerPlatinum.set_balance(balance)
            ##MultiplayerDebug.info("C-PLATINUM", "Balance updated: #{balance} Pt")
            next
          end

          # --- Platinum: Transaction success ---
          if data.start_with?("PLATINUM_OK:")
            new_balance = data.sub("PLATINUM_OK:", "").to_i
            MultiplayerPlatinum.set_transaction_result(:SUCCESS)
            MultiplayerPlatinum.set_balance(new_balance)
            ##MultiplayerDebug.info("C-PLATINUM", "Transaction succeeded, new balance: #{new_balance} Pt")
            next
          end

          # --- Platinum: Transaction error ---
          if data.start_with?("PLATINUM_ERR:")
            error_msg = data.sub("PLATINUM_ERR:", "").strip
            if error_msg.include?("Insufficient")
              MultiplayerPlatinum.set_transaction_result(:INSUFFICIENT)
            else
              MultiplayerPlatinum.set_transaction_result(:ERROR)
            end
            ##MultiplayerDebug.warn("C-PLATINUM", "Transaction failed: #{error_msg}")
            next
          end

          # --- Server asks us to provide our details now ---
          if data == "REQ_DETAILS"
            begin
              snap = local_trainer_snapshot
              send_data("DETAILS:#{@session_id}|#{snap[:name]}|#{snap[:map]}|#{snap[:x]}|#{snap[:y]}|#{snap[:clothes]}|#{snap[:hat]}|#{snap[:hair]}|#{snap[:skin_tone]}|#{snap[:hair_color]}|#{snap[:hat_color]}|#{snap[:clothes_color]}")
              ##MultiplayerDebug.info("C-DET01", "Responded with DETAILS(extended) for #{@session_id}: #{snap[:name]}")
            rescue => e
              ##MultiplayerDebug.error("C-DETERR", "Failed to send DETAILS: #{e.message}")
            end
            next
          end

          ##MultiplayerDebug.info("C-006", "Received: #{data}")
        end

        handle_connection_loss("Server stopped responding")
      rescue => e
        ##MultiplayerDebug.error("C-007", "Listener error: #{e.message}")
        handle_connection_loss("Network error")
      ensure
        @connected = false
        @socket = nil
      end
    end
  end

  # ===========================================
  # === Start periodic player synchronization
  # ===========================================
  def self.start_sync_loop
    return unless @connected
    if @sync_thread && @sync_thread.alive?
      ##MultiplayerDebug.warn("C-SYNC00", "Sync thread already running.")
      return
    end

    ##MultiplayerDebug.info("C-SYNC01", "Starting player synchronization thread.")
    @sync_thread = Thread.new do
      Thread.current.abort_on_exception = false
      @last_sync_state = {}  # Track previous state (empty = send full state on first sync)
      @last_heartbeat = Time.now - 10  # Force immediate first heartbeat
      loop do
        break unless @connected
        begin
          snap = local_trainer_snapshot

          # Use delta compression to send only changed fields
          delta = DeltaCompression.calculate_delta(@last_sync_state, snap)

          # Send if there are changes OR if heartbeat timeout (send heartbeat every 2 seconds)
          needs_heartbeat = (Time.now - @last_heartbeat) >= 2.0
          if DeltaCompression.has_changes?(delta) || needs_heartbeat
            # Encode delta for network transmission
            delta_encoded = DeltaCompression.encode_delta(delta)
            packet = "SYNC:#{delta_encoded}"
            send_data(packet, rate_limit_type: :SYNC)

            # Update last state and heartbeat time
            @last_sync_state = snap.dup
            @last_heartbeat = Time.now
          end

          # Only send NAME after integrity verification completes (if required)
          unless @name_sent
            if @waiting_for_integrity
              # Don't send NAME yet - waiting for integrity verification
              ##MultiplayerDebug.info("C-INTEGRITY", "Delaying NAME until integrity verification completes")
            else
              send_data("NAME:#{snap[:name]}")
              @name_sent = true

              # Send AUTH request for platinum system
              begin
                server_key = "#{@host}:#{@port}"
                token = MultiplayerPlatinum.get_token(server_key)
                tid = $Trainer.id rescue 0

                # Load existing UUID from local file (if available)
                existing_uuid = nil
                if defined?(PlatinumUUIDStorage)
                  existing_uuid = PlatinumUUIDStorage.get_uuid(server_key)
                end

                if token && !token.empty?
                  # Include UUID in AUTH if we have one
                  if existing_uuid && !existing_uuid.empty?
                    send_data("AUTH:#{tid}:#{token}:#{existing_uuid}")
                    ##MultiplayerDebug.info("C-PLATINUM", "Sent AUTH with token + UUID #{existing_uuid[0..7]}...")
                  else
                    send_data("AUTH:#{tid}:#{token}")
                    ##MultiplayerDebug.info("C-PLATINUM", "Sent AUTH with token (no UUID)")
                  end
                else
                  # New player or no token - include UUID if we have one
                  if existing_uuid && !existing_uuid.empty?
                    send_data("AUTH:#{tid}:NEW:#{existing_uuid}")
                    ##MultiplayerDebug.info("C-PLATINUM", "Sent AUTH as new player with UUID #{existing_uuid[0..7]}...")
                  else
                    send_data("AUTH:#{tid}:NEW")
                    ##MultiplayerDebug.info("C-PLATINUM", "Sent AUTH as new player (no UUID)")
                  end
                end
              rescue => e
                ##MultiplayerDebug.warn("C-PLATINUM", "Failed to send AUTH: #{e.message}")
              end
            end
          end
        rescue => e
          ##MultiplayerDebug.error("C-SYNC03", "Sync loop error: #{e.message}")
        end

        # Distance-based update rate: adjust sleep based on nearest player
        sleep_interval = calculate_adaptive_sleep_interval(snap)
        sleep(sleep_interval)
      end
      ##MultiplayerDebug.warn("C-SYNC99", "Sync loop terminated.")
    end
  end

  # Calculate adaptive sleep interval based on nearest player distance
  # @param local_pos [Hash] Local player snapshot
  # @return [Float] Sleep interval in seconds
  def self.calculate_adaptive_sleep_interval(local_pos)
    # Get all remote player positions from MultiplayerClient.players
    remote_positions = {}
    @players.each do |sid, data|
      next unless data && data[:x] && data[:y] && data[:map]
      remote_positions[sid] = {
        x: data[:x],
        y: data[:y],
        map: data[:map]
      }
    end

    # If no remote players, use slow update rate (1 Hz)
    return 1.0 if remote_positions.empty?

    # Find nearest player
    min_distance = Float::INFINITY
    remote_positions.each do |sid, remote_pos|
      distance = DistanceBasedUpdates.calculate_distance(local_pos, remote_pos)
      min_distance = distance if distance < min_distance
    end

    # Get recommended interval based on nearest player
    DistanceBasedUpdates.get_update_interval(min_distance)
  rescue => e
    ##MultiplayerDebug.error("C-DIST", "Distance calculation error: #{e.message}")
    0.1  # Fallback to 10 Hz
  end

  # ===========================================
  # === Stop synchronization thread
  # ===========================================
  def self.stop_sync_loop
    if @sync_thread && @sync_thread.alive?
      ##MultiplayerDebug.warn("C-SYNC98", "Stopping player sync thread.")
      @sync_thread.kill rescue nil
      @sync_thread = nil
    end
  end

  # ===========================================
  # === Send Data (with rate limiting)
  # ===========================================
  def self.send_data(message, rate_limit_type: nil)
    unless @connected && @socket
      ##MultiplayerDebug.warn("C-009", "Tried to send while disconnected.")
      return false
    end

    # Rate limiting (if enabled and type specified)
    if rate_limit_type && defined?(RateLimit)
      unless RateLimit.can_send?(rate_limit_type)
        ##MultiplayerDebug.warn("C-RATE", "Rate limited: #{rate_limit_type} (#{RateLimit.current_rate(rate_limit_type)}/s)")
        return false
      end
    end

    begin
      @socket.puts(message)
      ###MultiplayerDebug.info("C-010", "Sent: #{message}")
      return true
    rescue => e
      ##MultiplayerDebug.error("C-011", "Send failed: #{e.message}")
      handle_connection_loss("Server unreachable during send")
      return false
    end
  end

  # ===========================================
  # === Public send_message wrapper (for Platinum API)
  # ===========================================
  def self.send_message(message)
    send_data(message, rate_limit_type: :GENERAL)
  end

  # ===========================================
  # === Disconnect & loss handling
  # ===========================================
  def self.disconnect
    return unless @socket
    ##MultiplayerDebug.warn("C-012", "Disconnecting from server.")
    begin
      @socket.close
    rescue => e
      ##MultiplayerDebug.error("C-013", "Error closing socket: #{e.message}")
    end
    stop_sync_loop
    @connected = false
    @socket    = nil
    @name_sent = false
  end

  def self.handle_connection_loss(reason = "Connection lost")
    begin
      stop_sync_loop
    rescue => e
      ##MultiplayerDebug.warn("C-020A", "Failed stopping sync loop: #{e.message}")
    end
    ##MultiplayerDebug.warn("C-020", "#{reason}. Multiplayer disabled.")
    $multiplayer_disconnect_notice = true
    begin
      disconnect
    rescue => e
      ##MultiplayerDebug.warn("C-020B", "Disconnect raised: #{e.message}")
    end
    # Cleanup: clear cached co-op parties on loss
    @coop_remote_party = {}
  end

  # ===========================================
  # === Public Accessors (players & squad)
  # ===========================================
  def self.players; @players; end
  def self.session_id; @session_id; end
  def self.platinum_uuid; @platinum_uuid; end

  # ---- Squad accessors for UI ----
  def self.squad; @squad; end
  def self.in_squad?
    !!(@squad && @squad[:members].is_a?(Array) && !@squad[:members].empty?)
  end
  def self.is_leader?
    return false unless @squad && @session_id
    @squad[:leader].to_s.strip == @session_id.to_s.strip
  end
  def self.request_squad_state; send_data("REQ_SQUAD"); end
  def self.invite_player(sid); send_data("SQUAD_INVITE:#{sid}"); end
  def self.leave_squad; send_data("SQUAD_LEAVE"); end
  def self.kick_from_squad(sid); send_data("SQUAD_KICK:#{sid}"); end
  def self.transfer_leadership(sid); send_data("SQUAD_TRANSFER:#{sid}"); end

  # ===========================================
  # === Invite Queue API (Squad)
  # ===========================================
  def self.enqueue_invite(from_sid, from_name)
    from_sid = from_sid.to_s.strip
    if @invite_prompt_active
      if @pending_invite_from_sid == from_sid
        ##MultiplayerDebug.info("C-SQUAD", "Invite refresh ignored (already prompting for #{from_sid})")
      else
        send_data("SQUAD_RESP:#{from_sid}|DECLINE")
        ##MultiplayerDebug.info("C-SQUAD", "Auto-declined invite from #{from_sid} (busy with #{@pending_invite_from_sid})")
      end
      return
    end
    already = @invite_queue.any? { |i| i[:sid] == from_sid }
    unless already
      @invite_queue <<({ sid: from_sid, name: from_name.to_s })
      ##MultiplayerDebug.info("C-SQUAD", "Queued invite from #{from_sid}")
    end
  end
  def self.peek_next_invite; @invite_queue[0]; end
  def self.pop_next_invite
    inv = @invite_queue.shift
    if inv
      @invite_prompt_active    = true
      @pending_invite_from_sid = inv[:sid]
    end
    inv
  end
  def self.finish_invite_prompt
    @invite_prompt_active    = false
    @pending_invite_from_sid = nil
  end
  def self.invite_prompt_active?; @invite_prompt_active; end
  def self.send_squad_response(inviter_sid, decision_upcase)
    inviter_sid = inviter_sid.to_s.strip
    decision    = decision_upcase.to_s.upcase == "ACCEPT" ? "ACCEPT" : "DECLINE"
    send_data("SQUAD_RESP:#{inviter_sid}|#{decision}")
    ##MultiplayerDebug.info("C-SQUAD", "Invite decision sent: #{decision} for inviter #{inviter_sid}")
    request_squad_state if decision == "ACCEPT"
  end

  # ===========================================
  # === Trading: Public API for UI layer
  # ===========================================
  def self.trade_invite(target_sid);  send_data("TRADE_REQ:#{target_sid}"); end
  def self.trade_accept(requester_sid); send_data("TRADE_RESP:#{requester_sid}|ACCEPT"); end
  def self.trade_decline(requester_sid); send_data("TRADE_RESP:#{requester_sid}|DECLINE"); end

  def self.trade_update_offer(offer_hash)
    @trade_mutex.synchronize do
      return unless @trade && @trade[:id]
      begin
        json = MiniJSON.dump(offer_hash || {})
      rescue => e
        ##MultiplayerDebug.warn("C-TRADE", "Offer JSON encode failed: #{e.message}")
        json = "{}"
      end
      send_data("TRADE_UPDATE:#{@trade[:id]}|#{json}")
    end
  end

  def self.trade_set_ready(on)
    @trade_mutex.synchronize do
      return unless @trade && @trade[:id]
      send_data("TRADE_READY:#{@trade[:id]}|#{on ? "ON" : "OFF"}")
    end
  end

  def self.trade_confirm
    @trade_mutex.synchronize do
      return unless @trade && @trade[:id]
      ##MultiplayerDebug.info("TRADE-DBG", "=== TRADE_CONFIRM SENT ===")
      ##MultiplayerDebug.info("TRADE-DBG", "  trade_id=#{@trade[:id]}")
      send_data("TRADE_CONFIRM:#{@trade[:id]}")
    end
  end

  def self.trade_cancel
    @trade_mutex.synchronize do
      return unless @trade && @trade[:id]
      ##MultiplayerDebug.info("TRADE-DBG", "=== TRADE_CANCEL CALLED ===")
      ##MultiplayerDebug.info("TRADE-DBG", "  trade_id=#{@trade[:id]}")
      ##MultiplayerDebug.info("TRADE-DBG", "  Sending: TRADE_CANCEL:#{@trade[:id]}")
      begin
        send_data("TRADE_CANCEL:#{@trade[:id]}")
        ##MultiplayerDebug.info("TRADE-DBG", "  TRADE_CANCEL sent successfully")
      rescue => e
        ##MultiplayerDebug.error("TRADE-DBG", "  TRADE_CANCEL send failed: #{e.class}: #{e.message}")
        raise
      end
    end
  end

  def self.trade_execute_ok
    @trade_mutex.synchronize do
      return unless @trade && @trade[:id]
      send_data("TRADE_EXECUTE_OK:#{@trade[:id]}")
    end
  end

  def self.trade_execute_fail(reason="EXECUTION_FAILED")
    @trade_mutex.synchronize do
      return unless @trade && @trade[:id]
      send_data("TRADE_EXECUTE_FAIL:#{@trade[:id]}|#{reason.to_s}")
    end
  end

  # --- Trading: Accessors for UI ---
  def self.trade_active?
    @trade_mutex.synchronize { !!@trade && (@trade[:state] == "active" || @trade[:state] == "executing") }
  end
  def self.trade_state
    @trade_mutex.synchronize { @trade ? Marshal.load(Marshal.dump(@trade)) : nil }
  end
  def self.trade_peer_sid
    @trade_mutex.synchronize do
      next nil unless @trade && @session_id
      (@trade[:a_sid] == @session_id) ? @trade[:b_sid] : @trade[:a_sid]
    end
  end
  def self.trade_peer_name
    sid = trade_peer_sid
    sid ? find_name_for_sid(sid) : nil
  end
  def self.trade_exec_payload
    @trade_mutex.synchronize do
      return nil unless @trade && @trade[:exec_payload]
      Marshal.load(Marshal.dump(@trade[:exec_payload]))
    end
  end
  def self.trade_clear_if_final
    @trade_mutex.synchronize do
      if @trade && (%w[complete aborted].include?(@trade[:state]))
        @trade = nil
      end
    end
  end

  # --- Trade event queue API (for UI) ---
  def self.push_trade_event(ev)
    @_trade_event_q << ev
  rescue => e
    ##MultiplayerDebug.warn("C-TRADE", "push_trade_event failed: #{e.message}")
  end
  def self.trade_events_pending?; !@_trade_event_q.empty?; end
  def self.next_trade_event; @_trade_event_q.shift; end

  # ===========================================
  # === GTS: Public API (client -> server) ===
  # ===========================================
  # Simplified GTS - no uid/api_key needed (uses platinum UUID server-side)
  # gts_register removed - GTS now auto-registers on first use

  def self.gts_snapshot(since_rev=nil)
    d = {}; d["since_rev"] = since_rev if since_rev
    payload = { "action"=>"GTS_SNAPSHOT", "data"=> d }
    send_data("GTS:#{MiniJSON.dump(payload)}")
  end

  def self.gts_list_item(item_id, qty, price_money)
    data = { "kind"=>"item", "item_id"=> item_id.to_s, "item_qty"=> qty.to_i, "price_money"=> price_money.to_i }
    payload = { "action"=>"GTS_LIST", "data"=> data }
    send_data("GTS:#{MiniJSON.dump(payload)}")
  end

  def self.gts_list_pokemon(pokemon_json, price_money)
    data = { "kind"=>"pokemon", "pokemon_json"=> pokemon_json, "price_money"=> price_money.to_i }
    payload = { "action"=>"GTS_LIST", "data"=> data }
    send_data("GTS:#{MiniJSON.dump(payload)}")
  end

  def self.gts_cancel(listing_id)
    data = { "listing_id"=> listing_id.to_s }
    payload = { "action"=>"GTS_CANCEL", "data"=> data }
    send_data("GTS:#{MiniJSON.dump(payload)}")
  end

  def self.gts_buy(listing_id)
    payload = { "action"=>"GTS_BUY", "data"=> { "listing_id"=> listing_id.to_s } }
    send_data("GTS:#{MiniJSON.dump(payload)}")
  end

  # --- GTS event queue (for UI) ---
  def self.push_gts_event(ev)
    @_gts_event_q << ev
  rescue => e
    ##MultiplayerDebug.warn("C-GTS", "push_gts_event failed: #{e.message}")
  end
  def self.gts_events_pending?; !@_gts_event_q.empty?; end
  def self.next_gts_event; @_gts_event_q.shift; end

  # ===========================================
  # === Wild Battle Platinum Rewards =========
  # ===========================================
  def self.report_wild_platinum(wild_species, wild_level, wild_catch_rate, wild_stage, active_battler_levels, active_battler_stages, battler_index)
    return unless @connected

    # Include battle context for coop battles
    battle_id = nil
    is_coop = false
    if defined?(CoopBattleState) && CoopBattleState.active?
      battle_id = CoopBattleState.battle_id
      is_coop = CoopBattleState.in_coop_battle?
    end

    data = {
      "wild_species" => wild_species.to_s,
      "wild_level" => wild_level,
      "wild_catch_rate" => wild_catch_rate,
      "wild_stage" => wild_stage,
      "active_battler_levels" => active_battler_levels,
      "active_battler_stages" => active_battler_stages,
      "battler_index" => battler_index,
      "battle_id" => battle_id,
      "is_coop" => is_coop
    }

    send_data("WILD_PLATINUM:#{MiniJSON.dump(data)}")
  rescue => e
    ##MultiplayerDebug.warn("WILD-PLAT", "Failed to send wild platinum report: #{e.message}")
  end

  # --- Buyer-side execution (apply purchase locally) ---
  def self.gts_apply_execution(kind, payload, price_money)
    # Pay the price first
    if price_money.to_i > 0
      if defined?(TradeUI) && TradeUI.respond_to?(:has_money?) && !TradeUI.has_money?(price_money)
        return [false, "NO_MONEY"]
      end
      if defined?(TradeUI) && TradeUI.respond_to?(:add_money)
        ok = TradeUI.add_money(-price_money)
        return [false, "MONEY_SUB_FAIL"] unless ok
      else
        return [false, "MONEY_API"] unless defined?($Trainer) && $Trainer && $Trainer.respond_to?(:money)
        return [false, "NO_MONEY"] if ($Trainer.money || 0) < price_money.to_i
        $Trainer.money = ($Trainer.money || 0) - price_money.to_i
      end
    end

    case kind.to_s
    when "item"
      item_id = payload && payload["item_id"]
      qty     = payload && payload["qty"]
      sym = (defined?(TradeUI) && TradeUI.respond_to?(:item_sym)) ? TradeUI.item_sym(item_id) : (item_id.to_s.to_sym)
      q   = (qty || 0).to_i
      return [false, "BAD_ITEM"] if sym.nil? || q <= 0

      if defined?(TradeUI)
        return [false, "BAG_FULL"] unless TradeUI.bag_can_add?(sym, q)
        return [false, "ITEM_ADD_FAIL"] unless TradeUI.bag_add(sym, q)
      else
        if defined?($PokemonBag) && $PokemonBag && $PokemonBag.respond_to?(:pbCanStore?)
          return [false, "BAG_FULL"] unless $PokemonBag.pbCanStore?(sym, q)
          return [false, "ITEM_ADD_FAIL"] unless $PokemonBag.pbStoreItem(sym, q)
        else
          return [false, "BAG_API"]
        end
      end
      [true, nil]

    when "pokemon"
      pj = payload
      return [false, "BAD_POKEMON"] unless pj.is_a?(Hash) || pj.is_a?(String)
      if defined?(TradeUI) && TradeUI.respond_to?(:party_count)
        return [false, "PARTY_FULL"] if TradeUI.party_count >= 6
        ok = TradeUI.add_pokemon_from_json(pj)
        return [false, "POKEMON_ADD_FAIL"] unless ok
        [true, nil]
      else
        [false, "POKEMON_API"]
      end

    else
      [false, "UNKNOWN_KIND"]
    end
  rescue => e
    ##MultiplayerDebug.error("C-GTS", "gts_apply_execution failed: #{e.class}: #{e.message}")
    [false, "EXCEPTION"]
  end

  def self.gts_apply_return(kind, payload)
    autosave = lambda do
      if defined?(TradeUI) && TradeUI.respond_to?(:autosave_safely)
        TradeUI.autosave_safely
      elsif defined?(GTSUI) && GTSUI.respond_to?(:autosave_safely)
        GTSUI.autosave_safely
      end
    end

    case kind.to_s
    when "item"
      item_id = payload && payload["item_id"]
      qty     = payload && payload["qty"]
      sym = (defined?(TradeUI) && TradeUI.respond_to?(:item_sym)) ? TradeUI.item_sym(item_id) : (item_id.to_s.to_sym)
      q   = (qty || 0).to_i
      return [false, "BAD_ITEM"] if sym.nil? || q <= 0

      if defined?(TradeUI)
        return [false, "BAG_FULL"]      if TradeUI.respond_to?(:bag_can_add?) && !TradeUI.bag_can_add?(sym, q)
        return [false, "ITEM_ADD_FAIL"] unless TradeUI.respond_to?(:bag_add)   && TradeUI.bag_add(sym, q)
      elsif defined?($PokemonBag) && $PokemonBag && $PokemonBag.respond_to?(:pbCanStore?)
        return [false, "BAG_FULL"]      unless $PokemonBag.pbCanStore?(sym, q)
        return [false, "ITEM_ADD_FAIL"] unless $PokemonBag.pbStoreItem(sym, q)
      else
        return [false, "BAG_API"]
      end

      autosave.call
      [true, nil]

    when "pokemon"
      pj = payload
      cap = (defined?(Settings) && Settings.const_defined?(:MAX_PARTY_SIZE)) ? Settings::MAX_PARTY_SIZE : 6

      if defined?(TradeUI)
        full =
          if TradeUI.respond_to?(:party_full?)
            TradeUI.party_full?
          elsif TradeUI.respond_to?(:party_count)
            TradeUI.party_count >= cap
          else
            false
          end
        return [false, "PARTY_FULL"] if full

        ok = TradeUI.respond_to?(:add_pokemon_from_json) && TradeUI.add_pokemon_from_json(pj)
        return [false, "POKEMON_ADD_FAIL"] unless ok

        autosave.call
        [true, nil]
      elsif defined?($Trainer) && $Trainer
        full =
          if $Trainer.respond_to?(:party_full?)
            $Trainer.party_full?
          elsif $Trainer.respond_to?(:party_count)
            $Trainer.party_count >= cap
          else
            false
          end
        return [false, "PARTY_FULL"] if full
        [false, "POKEMON_API"]
      else
        [false, "POKEMON_API"]
      end

    else
      [false, "UNKNOWN_KIND"]
    end
  rescue => e
    ##MultiplayerDebug.error("C-GTS", "gts_apply_return failed: #{e.class}: #{e.message}")
    [false, "EXCEPTION"]
  end

  #-----------------------------------------------------------------------------
  # Trainer Battle Sync Handlers (Stub methods - actual logic in 065_Coop_TrainerHook.rb)
  #-----------------------------------------------------------------------------

  def self._handle_coop_trainer_sync_wait(sender_sid, battle_id, trainer_hex, map_id, event_id)
    # Store active sync wait data for detection when pbTrainerBattle is called
    @active_trainer_sync_wait = {
      sender_sid: sender_sid,
      battle_id: battle_id,
      trainer_hex: trainer_hex,
      map_id: map_id,
      event_id: event_id,
      timestamp: Time.now
    }
    ##MultiplayerDebug.info("C-COOP-TRAINER", "Stored sync wait: battle=#{battle_id}, map=#{map_id}, event=#{event_id}")
  end

  def self._handle_coop_trainer_joined(sender_sid, battle_id, joined_sid)
    # Store joined ally info for wait screen update
    @trainer_battle_allies ||= {}
    @trainer_battle_allies[battle_id] ||= []
    @trainer_battle_allies[battle_id] << joined_sid unless @trainer_battle_allies[battle_id].include?(joined_sid)
    ##MultiplayerDebug.info("C-COOP-TRAINER", "Ally #{joined_sid.inspect} (type=#{joined_sid.class}) joined battle #{battle_id}")
    ##MultiplayerDebug.info("C-COOP-TRAINER-DEBUG", "Current allies for #{battle_id}: #{@trainer_battle_allies[battle_id].inspect}")
  end

  def self._handle_coop_trainer_ready(sender_sid, battle_id, is_ready)
    # Store ready state for wait screen
    @trainer_ready_states ||= {}
    @trainer_ready_states[battle_id] ||= {}
    @trainer_ready_states[battle_id][sender_sid] = is_ready
    ##MultiplayerDebug.info("C-COOP-TRAINER", "Player #{sender_sid} ready state: #{is_ready} for battle #{battle_id}")
  end

  def self._handle_coop_trainer_start_battle(sender_sid, battle_id)
    # Signal that initiator is ready to start battle
    @trainer_battle_start_signal = {
      battle_id: battle_id,
      timestamp: Time.now
    }
    ##MultiplayerDebug.info("C-COOP-TRAINER", "Battle start signal received for #{battle_id}")
  end

  def self._handle_coop_trainer_cancelled(sender_sid, battle_id)
    # Initiator cancelled/started solo - clear sync wait if it matches
    if @active_trainer_sync_wait && @active_trainer_sync_wait[:battle_id] == battle_id
      ##MultiplayerDebug.info("C-COOP-TRAINER", "Clearing sync wait for cancelled battle #{battle_id}")
      @active_trainer_sync_wait = nil
    end

    # Also mark battle as cancelled so late joiners can handle it
    @trainer_battle_cancelled ||= {}
    @trainer_battle_cancelled[battle_id] = Time.now
    ##MultiplayerDebug.info("C-COOP-TRAINER", "Marked battle #{battle_id} as cancelled by #{sender_sid}")
  end

  # Accessor methods for trainer battle data
  def self.active_trainer_sync_wait
    @active_trainer_sync_wait
  end

  def self.clear_trainer_sync_wait
    @active_trainer_sync_wait = nil
  end

  def self.is_battle_cancelled?(battle_id)
    @trainer_battle_cancelled ||= {}
    cancelled_time = @trainer_battle_cancelled[battle_id]
    return false unless cancelled_time

    # Consider cancelled if within last 120 seconds
    (Time.now - cancelled_time) < 120
  end

  def self.trainer_battle_allies(battle_id)
    @trainer_battle_allies ||= {}
    @trainer_battle_allies[battle_id] || []
  end

  def self.trainer_ready_states(battle_id)
    @trainer_ready_states ||= {}
    @trainer_ready_states[battle_id] || {}
  end

  def self.trainer_battle_start_signal
    @trainer_battle_start_signal
  end

  def self.clear_trainer_battle_start_signal
    @trainer_battle_start_signal = nil
  end
end

##MultiplayerDebug.info("C-015", "Client module initialization complete.")
##MultiplayerDebug.info("C-COOP", "Co-op party cache ready (Marshal/Hex). Waiting for COOP_PARTY_PUSH_NOW / COOP_PARTY_PUSH_HEX.")
