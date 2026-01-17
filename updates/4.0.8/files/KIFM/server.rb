# ===========================================
# File: server.rb
# Purpose: TCP server for KIF Multiplayer (session IDs, player list, squads, trading, GTS, co-op party sync)
# Location: Place this file inside a folder named "KIFM" next to Game.exe.
#           The "KIFM" folder will also contain:
#             - server_debug.log
#             - GTS\market.json.enc
#             - GTS\gts.key
# Run with: ruby server.rb
# ===========================================

require 'socket'
require 'thread'
require 'fileutils'
require 'securerandom'
# Do NOT require 'json' (not guaranteed to exist in your Ruby)

# ---------------- MiniJSON (very small JSON subset) ----------------
# Supports: Hash (string keys), Array, String (with \" and \\ escapes), Integer/Float,
# true/false, null. Just enough for trade payloads and GTS.
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

  # internals
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
    @i += 1 # {
    skip_ws
    return obj if @s[@i,1] == '}' && (@i += 1)
    loop do
      key = read_string
      skip_ws
      @i += 1 if @s[@i,1] == ':'  # :
      val = read_value
      obj[key] = val
      skip_ws
      if @s[@i,1] == '}'
        @i += 1
        break
      end
      @i += 1 if @s[@i,1] == ','  # ,
      skip_ws
    end
    obj
  end

  def read_array
    arr = []
    @i += 1 # [
    skip_ws
    return arr if @s[@i,1] == ']' && (@i += 1)
    loop do
      arr << read_value
      skip_ws
      if @s[@i,1] == ']'
        @i += 1
        break
      end
      @i += 1 if @s[@i,1] == ','  # ,
      skip_ws
    end
    arr
  end

  def read_string
    out = ''
    @i += 1 # opening "
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

  def read_true;  @i += 4; true  end  # true
  def read_false; @i += 5; false end  # false
  def read_null;  @i += 4; nil   end  # null

  def read_number
    start = @i
    @i += 1 while @i < @s.length && @s[@i,1] =~ /[-+0-9.eE]/
    num = @s[start...@i]
    if num.include?('.') || num.include?('e') || num.include?('E')
      num.to_f
    else
      begin Integer(num) rescue 0 end
    end
  end
end
# -------------------------------------------------------------------

PORT     = 12975
LOG_FILE = File.join(__dir__, "server_debug.log")  # <— stays beside server.rb

# ===========================================
# === Debugging System with Error Codes ===
# ===========================================
module MultiplayerDebug
  LOG_MUTEX = Mutex.new
  def self.log(code, message)
    time  = Time.now.strftime("%Y-%m-%d %H:%M:%S")
    entry = "[#{time}] [#{code}] #{message}\n"
    LOG_MUTEX.synchronize { File.open(LOG_FILE, "a") { |f| f.write(entry) } }
  rescue => e
    puts "[LOG_FAIL] #{e.message}"
  end
  def self.info(id, msg);  log("S-#{id}", msg);  end
  def self.warn(id, msg);  log("W-#{id}", msg);  end
  def self.error(id, msg); log("E-#{id}", msg);  end
end

# ===========================================
# === Server-Side Rate Limiting ===
# ===========================================
# ANTI-CHEAT FEATURES:
# - Tracks violations per client (repeated rate limit breaches)
# - Auto-kick when client exceeds rate by 3x (extreme rate)
# - Auto-kick after 5 cumulative violations (persistent abuse)
# - Returns :KICK signal to message handlers to trigger disconnect
# - Cleans up violation tracking on client disconnect
module ServerRateLimit
  SYNC_LIMIT = 30
  ACTION_LIMIT = 25
  GENERAL_LIMIT = 50
  WINDOW_SIZE = 1.0

  # Anti-cheat: Auto-kick thresholds
  VIOLATION_THRESHOLD = 5  # Kick after 5 violations
  EXTREME_RATE_MULTIPLIER = 3  # Kick if exceeding limit by 3x

  @counters = {}
  @violations = {}  # Track violations per client
  @mutex = Mutex.new

  module_function

  def allow?(client_socket, message_type)
    @mutex.synchronize do
      now = Time.now.to_f
      @counters[client_socket] ||= {}
      @counters[client_socket][message_type] ||= []
      @violations[client_socket] ||= 0

      @counters[client_socket][message_type].delete_if { |ts| now - ts > WINDOW_SIZE }

      limit = case message_type
              when :SYNC then SYNC_LIMIT
              when :ACTION, :RNG, :SWITCH, :RUN_AWAY then ACTION_LIMIT
              else GENERAL_LIMIT
              end

      current_count = @counters[client_socket][message_type].length

      if current_count < limit
        @counters[client_socket][message_type] << now
        true
      else
        # Rate limit exceeded - record violation
        @violations[client_socket] += 1

        # Auto-kick conditions:
        # 1. Extreme rate (3x over limit)
        # 2. Repeated violations (5+ times)
        if current_count >= (limit * EXTREME_RATE_MULTIPLIER) || @violations[client_socket] >= VIOLATION_THRESHOLD
          puts "[ANTI-CHEAT] Auto-kicking client for abnormal rate (#{message_type}: #{current_count}/#{limit}, violations: #{@violations[client_socket]})"
          return :KICK  # Special return value to trigger kick
        end

        false
      end
    end
  end

  def remove_client(client_socket)
    @mutex.synchronize do
      @counters.delete(client_socket)
      @violations.delete(client_socket)
    end
  end

  def get_violations(client_socket)
    @mutex.synchronize { @violations[client_socket] || 0 }
  end
end

# ===========================================
# === PureMD5 (Embedded for Server) ===
# ===========================================
# Pure Ruby MD5 implementation - no external dependencies
module PureMD5
  # MD5 constants
  S = [
    7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22,
    5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20,
    4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23,
    6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21
  ].freeze

  K = [
    0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
    0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
    0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
    0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
    0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
    0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
    0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
    0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
    0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
    0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
    0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
    0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
    0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
    0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
    0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
    0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391
  ].freeze

  module_function

  def hexdigest(string)
    msg = string.force_encoding('ASCII-8BIT') rescue string.b
    a0 = 0x67452301
    b0 = 0xefcdab89
    c0 = 0x98badcfe
    d0 = 0x10325476
    msg_len = msg.bytesize
    msg += "\x80".force_encoding('ASCII-8BIT')
    while (msg.bytesize % 64) != 56
      msg += "\x00".force_encoding('ASCII-8BIT')
    end
    msg += [msg_len * 8].pack('Q<')
    (0...msg.bytesize).step(64) do |chunk_start|
      chunk = msg[chunk_start, 64]
      m = chunk.unpack('V16')
      a = a0
      b = b0
      c = c0
      d = d0
      64.times do |i|
        if i < 16
          f = (b & c) | ((~b) & d)
          g = i
        elsif i < 32
          f = (d & b) | ((~d) & c)
          g = (5 * i + 1) % 16
        elsif i < 48
          f = b ^ c ^ d
          g = (3 * i + 5) % 16
        else
          f = c ^ (b | (~d))
          g = (7 * i) % 16
        end
        f = (f + a + K[i] + m[g]) & 0xffffffff
        a = d
        d = c
        c = b
        b = (b + left_rotate(f, S[i])) & 0xffffffff
      end
      a0 = (a0 + a) & 0xffffffff
      b0 = (b0 + b) & 0xffffffff
      c0 = (c0 + c) & 0xffffffff
      d0 = (d0 + d) & 0xffffffff
    end
    digest = [a0, b0, c0, d0].pack('V4')
    digest.unpack('H*')[0]
  end

  def left_rotate(value, shift)
    ((value << shift) | (value >> (32 - shift))) & 0xffffffff
  end
end

# ===========================================
# === FileIntegrity (Embedded for Server) ===
# ===========================================
# Calculates hash of all .rb files in a folder
module FileIntegrity
  module_function

  def calculate_hash(folder_path)
    begin
      rb_files = Dir.glob(File.join(folder_path, "*.rb")).sort
      return "empty_folder" if rb_files.empty?
      file_hashes = []
      rb_files.each do |file_path|
        begin
          # Read file with binary encoding to handle any content
          content = File.binread(file_path)
          content_hash = PureMD5.hexdigest(content)
          file_hashes << content_hash
        rescue StandardError => e
          # If file fails to hash, return error
          return "error_hashing_#{File.basename(file_path)}"
        end
      end
      # Join hashes and force to binary encoding for consistency
      combined = file_hashes.join.force_encoding('ASCII-8BIT')
      master_hash = PureMD5.hexdigest(combined)
      return master_hash
    rescue => e
      return "error_folder_access"
    end
  end

  def calculate_server_hash
    possible_paths = [
      "Data/Scripts/659_Multiplayer",
      "./Data/Scripts/659_Multiplayer",
      "../Data/Scripts/659_Multiplayer"
    ]
    scripts_path = nil
    possible_paths.each do |path|
      if Dir.exist?(path)
        scripts_path = path
        break
      end
    end
    return "error_folder_not_found" if scripts_path.nil?
    calculate_hash(scripts_path)
  end
end

# ===========================================
# === Delta Compression Module ===
# ===========================================
# Embedded version of 047_DeltaCompression.rb
# Reduces bandwidth by sending only changed fields
module DeltaCompression
  module_function

  # Compare two state hashes and return only the differences
  def calculate_delta(old_state, new_state)
    return new_state if old_state.nil? || old_state.empty?

    delta = {}
    new_state.each do |key, value|
      if !old_state.key?(key) || old_state[key] != value
        delta[key] = value
      end
    end

    delta
  end

  # Apply delta to a base state to get the new state
  def apply_delta(base_state, delta)
    return delta if base_state.nil? || base_state.empty?

    new_state = base_state.dup
    delta.each do |key, value|
      new_state[key] = value
    end

    new_state
  end

  # Encode delta for network transmission
  def encode_delta(delta)
    return "" if delta.nil? || delta.empty?

    parts = []
    delta.each do |key, value|
      parts << "#{key}=#{value}"
    end

    parts.join(",")
  end

  # Decode delta from network transmission (compatible with parse_sync_csv)
  def decode_delta(encoded)
    return {} if encoded.nil? || encoded.empty?

    delta = {}
    encoded.split(",").each do |part|
      key, value = part.split("=", 2)
      next unless key && value

      # Convert to symbol and parse value
      delta[key.to_sym] = parse_value(value.strip)
    end

    delta
  end

  # Parse value from string to appropriate type
  def parse_value(value)
    # Try integer
    return value.to_i if value =~ /\A-?\d+\z/

    # Try float
    return value.to_f if value =~ /\A-?\d+\.\d+\z/

    # Return as string
    value
  end

  # Check if delta is worth sending (has changes)
  def has_changes?(delta)
    !delta.nil? && !delta.empty?
  end
end

# ===========================================
# === IP Detection (VPN or VPS) ===
# ===========================================
def interface_is_up?(ifaddr)
  # Check if interface is actually UP (not just configured)
  # SIOCGIFFLAGS to check interface flags
  begin
    flags = ifaddr.flags rescue 0
    return (flags & Socket::IFF_UP) != 0 && (flags & Socket::IFF_RUNNING) != 0
  rescue
    # Fallback: assume up if we can't check
    return true
  end
end

def detect_radmin_ip
  # Radmin VPN uses 26.x.x.x range
  Socket.getifaddrs.each do |ifaddr|
    addr = ifaddr.addr
    next unless addr && addr.ipv4?
    ip = ifaddr.addr.ip_address
    next unless ip.start_with?("26.")  # Radmin VPN range

    # Check if interface is actually UP and running
    next unless interface_is_up?(ifaddr)

    return ip
  end
  nil
end

def detect_vpn_ip
  # Priority order: Radmin (26.x) → other private IPs → first non-localhost
  radmin_ip = detect_radmin_ip
  return radmin_ip if radmin_ip

  private_ips = []
  Socket.getifaddrs.each do |ifaddr|
    addr = ifaddr.addr
    next unless addr && addr.ipv4?
    ip = addr.ip_address
    next if ip.start_with?("127.") || ip == "0.0.0.0"
    next if ip.start_with?("26.")  # Already checked Radmin above

    # Collect other private IPs (10.x, 172.16-31.x, 192.168.x, 25.x Hamachi)
    if ip.start_with?("10.", "172.", "192.168.", "25.")
      # Check if interface is UP
      next unless interface_is_up?(ifaddr)
      private_ips << ip
    end
  end

  private_ips.first  # Return first found, or nil
end

def detect_public_ip
  # Detect first public IPv4 address (VPS scenario)
  Socket.getifaddrs.each do |ifaddr|
    addr = ifaddr.addr
    next unless addr && addr.ipv4?
    ip = addr.ip_address
    next if ip.start_with?("127.") || ip == "0.0.0.0"

    # Skip private ranges
    next if ip.start_with?("10.", "172.", "192.168.", "25.", "26.", "100.")

    return ip  # Public IP found
  end
  nil
end

def detect_server_mode
  # Returns [:vps, public_ip] or [:vpn, vpn_ip] or [:none, nil]
  public_ip = detect_public_ip
  return [:vps, public_ip] if public_ip

  vpn_ip = detect_vpn_ip
  return [:vpn, vpn_ip] if vpn_ip

  [:none, nil]
end

# ===========================================
# === GTS: Persistence & Store (host only) ===
# ===========================================
module GTSStore
  module_function

  # Base directory is a "GTS" folder next to server.rb (inside "KIFM")
  def base_dir
    File.join(__dir__, "GTS")
  end

  def ensure_dirs!
    dir = base_dir
    begin
      FileUtils.mkdir_p(dir) unless File.directory?(dir)
    rescue => e
      MultiplayerDebug.error("GTS", "Failed to create GTS dir #{dir}: #{e.message}")
    end
    dir
  end

  def key_path
    File.join(base_dir, "gts.key")
  end

  def data_path
    File.join(base_dir, "market.json.enc")
  end

  def have_openssl?
    require 'openssl'
    true
  rescue
    false
  end

  def read_or_create_key
    ensure_dirs!
    if File.exist?(key_path)
      File.binread(key_path)
    else
      key = have_openssl? ? OpenSSL::Random.random_bytes(32) : ("KIFGTS" * 8)[0,32]
      File.binwrite(key_path, key)
      key
    end
  rescue => e
    MultiplayerDebug.error("GTS", "Key read/create failed: #{e.message}")
    ("KIFGTS" * 8)[0,32]
  end

  def encrypt(plaintext)
    key = read_or_create_key
    if have_openssl?
      cipher = OpenSSL::Cipher.new('aes-256-ctr')
      cipher.encrypt
      iv = OpenSSL::Random.random_bytes(16)
      cipher.key = key
      cipher.iv  = iv
      iv + cipher.update(plaintext) + cipher.final
    else
      # XOR + Base64 (light obfuscation)
      bytes = plaintext.bytes
      k     = key.bytes
      xored = bytes.each_with_index.map { |b,i| b ^ k[i % k.length] }
      ["X" + xored.pack("C*")].pack("m")
    end
  rescue => e
    MultiplayerDebug.error("GTS", "Encrypt failed: #{e.message}")
    plaintext
  end

  def decrypt(ciphertext)
    key = read_or_create_key
    if have_openssl?
      iv  = ciphertext[0,16] || ""
      body = ciphertext[16..-1] || ""
      cipher = OpenSSL::Cipher.new('aes-256-ctr')
      cipher.decrypt
      cipher.key = key
      cipher.iv  = iv
      cipher.update(body) + cipher.final
    else
      raw = ciphertext.unpack1("m") rescue ""
      raw = raw.to_s
      raw = raw[1..-1] if raw.start_with?("X")
      bytes = raw.bytes
      k     = key.bytes
      xored = bytes.each_with_index.map { |b,i| b ^ k[i % k.length] }
      xored.pack("C*")
    end
  rescue => e
    MultiplayerDebug.error("GTS", "Decrypt failed: #{e.message}")
    ""
  end

  def atomic_write(path, bytes)
    tmp = path + ".tmp"
    File.binwrite(tmp, bytes)
    File.open(tmp, "rb") { |f| f.fsync rescue nil }
    File.rename(tmp, path)
  end
end

# ===========================================
# === Server Initialization ===
# ===========================================

# IP Whitelist Configuration (Optional)
# Empty array = allow all connections
# Add IPs to restrict access: ["123.45.67.89", "98.76.54.32"]
IP_WHITELIST = []
ALWAYS_ALLOW_LOCALHOST = true

# VPS Mode (set to true to enable VPS/Dedicated server mode)
# See README-VPS.txt for instructions
ENABLE_VPS_MODE = false

# Detect IPs - Try VPN first, fallback to VPS
vpn_ip = detect_vpn_ip
public_ip = detect_public_ip

bind_ip = nil
server_mode = nil
server_type = nil

if vpn_ip
  # VPN Mode: Preferred - bind to VPN IP
  bind_ip = vpn_ip
  server_mode = :vpn
  server_type = vpn_ip.start_with?("26.") ? "VPN (Radmin)" : "VPN"
  puts "[Server] VPN Mode - Detected #{server_type} IP: #{vpn_ip}"
  puts "[Server] Binding to #{bind_ip}:#{PORT}"
  MultiplayerDebug.info("VPN", "Starting in VPN mode on #{bind_ip}:#{PORT}")

  if IP_WHITELIST.empty?
    puts "[Server] IP whitelist: DISABLED (all VPN clients allowed)"
  else
    puts "[Server] IP whitelist: ENABLED (#{IP_WHITELIST.length} IPs allowed)"
    MultiplayerDebug.info("WHITELIST", "Allowed IPs: #{IP_WHITELIST.join(', ')}")
  end

elsif public_ip && ENABLE_VPS_MODE
  # VPS Mode: Enabled via config
  bind_ip = "0.0.0.0"
  server_mode = :vps
  server_type = "VPS/Dedicated"
  puts "[Server] VPS/Dedicated Mode - Public IP: #{public_ip}"
  puts "[Server] Binding to 0.0.0.0:#{PORT} (all interfaces)"
  puts "[Server] Players connect to: #{public_ip}:#{PORT}"
  MultiplayerDebug.info("VPS", "Starting in VPS mode on #{public_ip}")

  if IP_WHITELIST.empty?
    puts "[Server] Public server - accepting connections from anyone"
  else
    puts "[Server] IP whitelist ENABLED: #{IP_WHITELIST.length} IPs allowed"
    MultiplayerDebug.info("WHITELIST", "Allowed IPs: #{IP_WHITELIST.join(', ')}")
  end

elsif public_ip && !ENABLE_VPS_MODE
  # Public IP detected but VPS mode not enabled
  puts "[WARNING] No VPN detected (Radmin, Hamachi, ZeroTier, etc.)"
  puts "[INFO] Public IP detected: #{public_ip}"
  puts ""
  puts "If you have a VPS and want to run a public server:"
  puts "  Edit NoCoopStable.rb line 653 and set: ENABLE_VPS_MODE = true"
  puts "  See README-VPS.txt for full instructions"
  puts ""
  puts "[ERROR] Server startup aborted. Please either:"
  puts "  1. Start your VPN software (Radmin, Hamachi, etc.), OR"
  puts "  2. Enable VPS mode (see above)"
  MultiplayerDebug.error("STARTUP", "No VPN detected and VPS mode not enabled")
  exit

else
  # No network at all
  puts "[ERROR] No network interface detected. Check your connection."
  MultiplayerDebug.error("STARTUP", "No valid IP found")
  exit
end

# Start TCP server
begin
  server = TCPServer.new(bind_ip, PORT)
  puts "[Server] Server listening on #{bind_ip}:#{PORT}"
  MultiplayerDebug.info("LISTEN", "Server listening on #{bind_ip}:#{PORT}")
rescue => e
  puts "[ERROR] Could not bind to #{bind_ip}:#{PORT} — #{e.message}"
  MultiplayerDebug.error("BIND-FAIL", "Bind failed: #{e.message}")
  exit
end

# ===========================================
# === File Integrity Check
# ===========================================
@server_integrity_hash = FileIntegrity.calculate_server_hash
if @server_integrity_hash.start_with?("error")
  puts "[WARNING] Could not calculate file integrity hash: #{@server_integrity_hash}"
  MultiplayerDebug.error("INTEGRITY", "Hash calculation failed: #{@server_integrity_hash}")
  @server_integrity_hash = nil
else
  puts "[Server] File integrity check enabled (hash: #{@server_integrity_hash[0..7]}...)"
  MultiplayerDebug.info("INTEGRITY", "Hash calculated: #{@server_integrity_hash}")
end

# ===========================================
# === State
# ===========================================
clients        = []        # Array<TCPSocket>
client_ids     = {}        # { socket => "SID#" }
sid_sockets    = {}        # { "SID#" => socket }
client_data    = {}        # { socket => { id:, name:, map:, x:, y:, clothes:, ... } }
next_session   = 0

# VPN connection monitoring
last_connection_check = Time.now
CONNECTION_CHECK_INTERVAL = 5  # Check every 5 seconds if connection is still valid

# pending details for Player List
pending_details = {}

# ======================
# === Squad System ====
# ======================
SQUAD_MAX = 3

# squads: { squad_id => { leader:"SIDx", members:["SIDx", ...], created_at:Time } }
squads = {}
member_squad = {}     # { "SIDx" => squad_id }
next_squad_id = 0

# pending_invites:
# { to_sid => { from_sid:"SIDx", squad_id:Integer } }
pending_invites = {}

# ======================
# === Trading System ===
# ======================
# trades: { trade_id => { a_sid:, b_sid:, offers:{sid=>Hash}, ready:{sid=>bool}, confirm:{sid=>bool}, exec_ok:{sid=>bool}, state:String, t_last:Time } }
trades = {}
sid_active_trade = {}   # { sid => trade_id }
trade_seq = 0
TRADE_TIMEOUT_SEC = 300 # 5 minutes

# ==========================
# === ACK Resend System ====
# ==========================
# pending_acks: { "#{from_sid}|#{to_sid}|#{battle_id}|#{turn}" => { payload:, sent_at:Time, attempts:Integer } }
pending_acks = {}
ACK_TIMEOUT = 2.0  # Resend after 2 seconds
ACK_MAX_ATTEMPTS = 3  # Give up after 3 attempts

# ===============================
# === Coop Battle Queue System ==
# ===============================
# active_battles: { squad_id => { initiator_sid:, battle_type:, started_at:Time } }
active_battles = {}
BATTLE_LOCK_TIMEOUT = 35.0  # Auto-clear if no join within 35s (exceeds 30s client timeout)

# ==========================
# === PVP Wins Tracking ====
# ==========================
# pvp_wins: { platinum_uuid => win_count }
pvp_wins = {}
PVP_WINS_FILE = File.join(Dir.pwd, "KIFM", "pvp_wins.txt")

# Load PVP wins from file
if File.exist?(PVP_WINS_FILE)
  begin
    File.readlines(PVP_WINS_FILE).each do |line|
      next if line.strip.empty? || line.start_with?("#")
      uuid, count = line.strip.split("=", 2)
      next unless uuid && count
      pvp_wins[uuid] = count.to_i
    end
    puts "[Server] Loaded #{pvp_wins.length} PvP win records"
    MultiplayerDebug.info("PVP-WINS", "Loaded #{pvp_wins.length} win records from file")
  rescue => e
    puts "[WARNING] Failed to load PvP wins: #{e.message}"
    MultiplayerDebug.warn("PVP-WINS", "Failed to load wins: #{e.message}")
  end
end

# Helper to save PVP wins
def save_pvp_wins(pvp_wins)
  begin
    File.open(PVP_WINS_FILE, "w") do |f|
      f.puts "# PvP Win Counts"
      f.puts "# Format: uuid=win_count"
      pvp_wins.each do |uuid, count|
        f.puts "#{uuid}=#{count}"
      end
    end
    MultiplayerDebug.info("PVP-WINS", "Saved #{pvp_wins.length} win records to file")
  rescue => e
    MultiplayerDebug.warn("PVP-WINS", "Failed to save wins: #{e.message}")
  end
end

# ==========================
# === GTS: Host State ======
# ==========================
GTS_MUTEX = Mutex.new

gts_state = {
  "schema"   => 1,
  "rev"      => 0,
  "users"    => {},
  "listings" => [],
  "escrow"   => {},
  "audit"    => []
}
gts_listing_seq = 0
sid_to_uuid_gts = {}    # "SIDx" => platinum_uuid (for GTS session tracking)
uuid_to_sid_gts = {}    # platinum_uuid => "SIDx" (for GTS session tracking)

# ===============================
# === Platinum Currency System ==
# ===============================
PLATINUM_MUTEX = Mutex.new
PLATINUM_FILE = File.join(File.dirname(__FILE__), "platinum_accounts.json")

# Primary storage: { uuid => { tid, name, platinum, token } }
platinum_accounts = {}

# Lookup table: { token => uuid } (rebuilt on load)
token_to_uuid = {}

# Wild battle platinum rate limiter: { sid => [timestamps] }
wild_platinum_timestamps = {}

# Wild battle deduplication cache: { "species:level:timestamp" => true }
# Prevents duplicate rewards when multiple clients report same wild defeat in coop
wild_platinum_dedupe = {}

# ======================
# === Chat System ====
# ======================
CHAT_LOG_FILE = File.join(__dir__, "chat_log.txt")
CHAT_RATE_LIMIT = 5.0  # 1 message per 5 seconds
chat_last_message = {}  # { socket => Time }
chat_pm_tab_count = {}  # { sid => count }
chat_block_lists = {}   # { sid => [blocked_sids] }
chat_block_all = {}     # { sid => true/false }

def platinum_generate_uuid
  SecureRandom.uuid rescue "#{Time.now.to_i}-#{rand(999999)}"
end

def platinum_generate_token(uuid)
  # Use PureMD5 for reliable 128-bit hash (no external dependencies)
  # Falls back to timestamp+random if PureMD5 unavailable
  begin
    if defined?(PureMD5)
      PureMD5.hexdigest("#{uuid}#{Time.now.to_s}#{rand(999999)}")
    else
      sha256_hex("#{uuid}#{Time.now.to_s}#{rand(999999)}")
    end
  rescue
    # Ultimate fallback: timestamp + multiple random values
    base = "#{uuid}#{Time.now.to_i}#{rand(999999)}#{rand(999999)}"
    base.bytes.each_slice(4).map { |b| b.inject(0) { |a,c| (a << 8) | c } }.map { |n| "%08x" % n }.join[0..31]
  end
end

def platinum_save!(accounts)
  PLATINUM_MUTEX.synchronize do
    begin
      File.write(PLATINUM_FILE, MiniJSON.dump(accounts))
      MultiplayerDebug.info("PLATINUM", "Saved #{accounts.size} accounts to #{PLATINUM_FILE}")
    rescue => e
      MultiplayerDebug.error("PLATINUM", "Failed to save: #{e.message}")
    end
  end
end

def platinum_load!(accounts, token_lookup)
  PLATINUM_MUTEX.synchronize do
    begin
      if File.exist?(PLATINUM_FILE)
        data = MiniJSON.parse(File.read(PLATINUM_FILE))
        accounts.clear
        token_lookup.clear

        data.each do |uuid, account_data|
          accounts[uuid] = account_data
          token_lookup[account_data["token"]] = uuid if account_data["token"]
        end

        MultiplayerDebug.info("PLATINUM", "Loaded #{accounts.size} accounts from #{PLATINUM_FILE}")
      else
        MultiplayerDebug.info("PLATINUM", "No existing platinum file, starting fresh")
      end
    rescue => e
      MultiplayerDebug.error("PLATINUM", "Failed to load: #{e.message}")
    end
  end
end

def platinum_get_uuid_by_token(token_lookup, token)
  PLATINUM_MUTEX.synchronize { token_lookup[token] }
end

def platinum_get_balance(accounts, uuid)
  PLATINUM_MUTEX.synchronize { accounts[uuid] ? accounts[uuid]["platinum"].to_i : 0 }
end

def platinum_set_balance(accounts, uuid, amount)
  PLATINUM_MUTEX.synchronize do
    return false unless accounts[uuid]
    accounts[uuid]["platinum"] = amount.to_i
    true
  end
end

# Load platinum accounts on startup
platinum_load!(platinum_accounts, token_to_uuid)

# ===================================
# === Platinum Trading Helper Functions
# ===================================

# Extract platinum amount from offer (supports both "platinum" and legacy "money" keys)
def extract_platinum_from_offer(offer)
  amount = offer["platinum"] || offer["money"] || 0
  amount.to_i
end

# ===================================
# === Wild Battle Platinum Reward Helpers
# ===================================

# Calculate platinum reward for wild Pokemon defeat
# All GameData lookups done client-side, values sent to server
def calculate_wild_platinum(wild_level, wild_catch_rate, wild_stage, active_battler_levels, active_battler_stages)
  base = 10

  # M_level calculation
  team_avg = active_battler_levels.sum.to_f / active_battler_levels.size
  team_max = active_battler_levels.max
  diff = wild_level - team_avg
  m_level = 1.0 + (diff / (2.0 * team_max))
  m_level = [[m_level, 0.5].max, 1.5].min

  # M_rarity from catch_rate (0-255 → 1.00-1.25)
  catch_rate = wild_catch_rate.to_i.clamp(0, 255)
  m_rarity = 1.0 + (0.25 * (255 - catch_rate) / 255.0)

  # M_stage based on evolution stage
  m_stage = case wild_stage.to_i
  when 1 then 1.0
  when 2 then 1.1
  when 3 then 1.2
  else 1.0
  end

  # M_penalty: if any active battler has higher stage than wild
  max_battler_stage = active_battler_stages.max || 1
  m_penalty = (max_battler_stage > wild_stage.to_i) ? 0.75 : 1.0

  # Final calculation
  platinum = base * m_level * m_rarity * m_stage * m_penalty
  platinum.round
end

# Validate platinum balances for trade and lock amounts
def platinum_validate_trade(trades, platinum_accounts, client_data, trade_id)
  t = trades[trade_id]
  return { success: false, reason: "NO_TRADE" } unless t

  a_sid = t[:a_sid]
  b_sid = t[:b_sid]

  # Get UUIDs from client_data
  a_uuid = client_data.values.find { |h| h[:id] == a_sid }&.dig(:platinum_uuid)
  b_uuid = client_data.values.find { |h| h[:id] == b_sid }&.dig(:platinum_uuid)

  unless a_uuid && b_uuid
    return { success: false, reason: "AUTH_REQUIRED" }
  end

  # Extract platinum amounts from offers
  a_offer = t[:offers][a_sid] || {}
  b_offer = t[:offers][b_sid] || {}

  a_giving = extract_platinum_from_offer(a_offer)
  b_giving = extract_platinum_from_offer(b_offer)

  # Validate balances
  result = nil
  PLATINUM_MUTEX.synchronize do
    a_balance = platinum_accounts[a_uuid] ? platinum_accounts[a_uuid]["platinum"].to_i : 0
    b_balance = platinum_accounts[b_uuid] ? platinum_accounts[b_uuid]["platinum"].to_i : 0

    if a_giving > a_balance
      result = { success: false, reason: "INSUFFICIENT_#{a_sid}" }
      next
    end

    if b_giving > b_balance
      result = { success: false, reason: "INSUFFICIENT_#{b_sid}" }
      next
    end

    # Store validation data in trade state
    t[:platinum_uuids] ||= {}
    t[:platinum_pre_balances] ||= {}
    t[:platinum_amounts] ||= {}

    t[:platinum_uuids][a_sid] = a_uuid
    t[:platinum_uuids][b_sid] = b_uuid
    t[:platinum_pre_balances][a_sid] = a_balance
    t[:platinum_pre_balances][b_sid] = b_balance
    t[:platinum_amounts][a_sid] = a_giving
    t[:platinum_amounts][b_sid] = b_giving
    t[:platinum_locked] = true

    MultiplayerDebug.info("PLATINUM-TRADE", "Validated trade #{trade_id}: #{a_sid}(#{a_giving}Pt) <-> #{b_sid}(#{b_giving}Pt)")
  end

  result || { success: true }
end

# Execute platinum transfer atomically
def platinum_execute_trade_transfer(trades, platinum_accounts, sid_sockets, trade_id)
  t = trades[trade_id]
  return { success: false, reason: "NO_TRADE" } unless t
  return { success: false, reason: "NOT_LOCKED" } unless t[:platinum_locked]
  return { success: true } if t[:platinum_transferred] # Already done (idempotent)

  a_sid = t[:a_sid]
  b_sid = t[:b_sid]
  a_uuid = t[:platinum_uuids][a_sid]
  b_uuid = t[:platinum_uuids][b_sid]
  a_giving = t[:platinum_amounts][a_sid]
  b_giving = t[:platinum_amounts][b_sid]

  # Atomic transfer (both deductions and additions in single mutex)
  result = nil
  PLATINUM_MUTEX.synchronize do
    a_account = platinum_accounts[a_uuid]
    b_account = platinum_accounts[b_uuid]

    unless a_account && b_account
      result = { success: false, reason: "ACCOUNT_MISSING" }
      next
    end

    # Final balance check (in case of concurrent modification)
    if a_account["platinum"].to_i < a_giving
      result = { success: false, reason: "INSUFFICIENT_#{a_sid}_CONCURRENT" }
      next
    end
    if b_account["platinum"].to_i < b_giving
      result = { success: false, reason: "INSUFFICIENT_#{b_sid}_CONCURRENT" }
      next
    end

    # Execute transfer: deduct from giver, add to receiver (crossed)
    a_account["platinum"] = a_account["platinum"].to_i - a_giving + b_giving
    b_account["platinum"] = b_account["platinum"].to_i - b_giving + a_giving

    t[:platinum_transferred] = true

    MultiplayerDebug.info("PLATINUM-TRADE", "Transferred: #{trade_id} #{a_sid}(-#{a_giving}+#{b_giving}=#{a_account["platinum"]}) #{b_sid}(-#{b_giving}+#{a_giving}=#{b_account["platinum"]})")

    # Save immediately (hard commit) - must be inside the mutex to ensure atomicity
    begin
      File.write(PLATINUM_FILE, MiniJSON.dump(platinum_accounts))
      MultiplayerDebug.info("PLATINUM", "Saved #{platinum_accounts.size} accounts to #{PLATINUM_FILE}")
      result = { success: true }
    rescue => e
      MultiplayerDebug.error("PLATINUM", "Failed to save: #{e.message}")
      result = { success: false, reason: "SAVE_FAILED" }
    end
  end

  # Return early if error occurred during synchronize block
  return result if result && !result[:success]

  # Update client caches
  new_a_balance = platinum_get_balance(platinum_accounts, a_uuid)
  new_b_balance = platinum_get_balance(platinum_accounts, b_uuid)
  safe_send_sid(sid_sockets, a_sid, "PLATINUM_BAL:#{new_a_balance}")
  safe_send_sid(sid_sockets, b_sid, "PLATINUM_BAL:#{new_b_balance}")

  { success: true }
end

# Rollback platinum transfer on trade failure
def platinum_rollback_trade(trades, platinum_accounts, sid_sockets, trade_id, reason)
  t = trades[trade_id]
  return unless t
  return unless t[:platinum_locked]
  return unless t[:platinum_transferred] # Nothing to rollback

  a_sid = t[:a_sid]
  b_sid = t[:b_sid]
  a_uuid = t[:platinum_uuids][a_sid]
  b_uuid = t[:platinum_uuids][b_sid]
  a_pre = t[:platinum_pre_balances][a_sid]
  b_pre = t[:platinum_pre_balances][b_sid]

  # Restore pre-trade balances and save atomically
  PLATINUM_MUTEX.synchronize do
    # Directly set balances without calling platinum_set_balance (avoid recursive lock)
    if platinum_accounts[a_uuid]
      platinum_accounts[a_uuid]["platinum"] = a_pre.to_i
    end
    if platinum_accounts[b_uuid]
      platinum_accounts[b_uuid]["platinum"] = b_pre.to_i
    end

    # Save immediately inside mutex (avoid calling platinum_save! which would recursive lock)
    begin
      File.write(PLATINUM_FILE, MiniJSON.dump(platinum_accounts))
      MultiplayerDebug.info("PLATINUM", "Saved #{platinum_accounts.size} accounts to #{PLATINUM_FILE} (rollback)")
    rescue => e
      MultiplayerDebug.error("PLATINUM", "Failed to save during rollback: #{e.message}")
    end
  end

  # Update client caches
  safe_send_sid(sid_sockets, a_sid, "PLATINUM_BAL:#{a_pre}")
  safe_send_sid(sid_sockets, b_sid, "PLATINUM_BAL:#{b_pre}")

  MultiplayerDebug.warn("PLATINUM-TRADE", "Rolled back trade #{trade_id} (reason: #{reason})")
end

def gts_now_i; Time.now.to_i; end
def gts_bump_rev!(st); st["rev"] = (st["rev"].to_i + 1); end
def gts_new_lid(seq); seq += 1; [("L%04d" % seq), seq]; end

def sha256_hex_fallback(s)
  h = s.to_s.unpack("C*").inject(0) { |a,c| ((a * 131) ^ c) & 0xffffffff }
  ("%08x" % h) * 2
end
def sha256_hex(s)
  begin; require 'digest'; Digest::SHA256.hexdigest(s.to_s); rescue; sha256_hex_fallback(s); end
end

def gts_load!(st)
  GTSStore.ensure_dirs!
  path = GTSStore.data_path
  return st unless File.exist?(path)
  raw = File.binread(path) rescue nil
  return st unless raw && raw.bytesize > 0
  json = GTSStore.decrypt(raw)
  data = MiniJSON.parse(json) rescue nil
  return st unless data.is_a?(Hash)
  st.replace(data)
  st
rescue => e
  MultiplayerDebug.error("GTS", "Load failed: #{e.message}")
  st
end

def gts_save!(st)
  GTSStore.ensure_dirs!
  json = MiniJSON.dump(st)
  enc  = GTSStore.encrypt(json)
  GTSStore.atomic_write(GTSStore.data_path, enc)
  MultiplayerDebug.info("GTS", "Saved market rev=#{st['rev']} listings=#{st['listings'].length}")
  true
rescue => e
  MultiplayerDebug.error("GTS", "Save failed: #{e.message}")
  false
end

def gts_snapshot(st, since_rev=nil)
  # Enrich listings with seller_name from user profiles
  enriched_listings = st["listings"].map do |listing|
    enriched = listing.dup
    seller_uuid = listing["seller"]
    if seller_uuid && st["users"][seller_uuid]
      enriched["seller_name"] = st["users"][seller_uuid]["name"] || "Unknown"
    end
    enriched
  end

  if !since_rev || since_rev.to_i <= 0 || since_rev.to_i >= st["rev"].to_i
    return { "users" => st["users"], "listings" => enriched_listings, "rev" => st["rev"] }
  end
  {
    "changes"  => { "added" => enriched_listings, "updated" => [], "removed_ids" => [] },
    "base_rev" => since_rev.to_i,
    "new_rev"  => st["rev"].to_i
  }
end

def gts_cleanup_expired!(st, sid_sockets)
  now = gts_now_i
  expired = []

  st["listings"].each do |listing|
    expires_at = listing["expires_at"].to_i
    next if expires_at == 0  # Old listings without expiry
    next if expires_at > now  # Not expired yet
    next if listing["locked"]  # Skip locked listings (being purchased/canceled)

    # Listing expired - return to owner if online
    expired << listing
    seller_uuid = listing["seller"]
    seller_sid = st["users"][seller_uuid] && st["users"][seller_uuid]["last_sid"]

    if seller_sid && sid_sockets[seller_sid]
      # Owner is online - send return message
      escrow = st["escrow"][listing["id"]]
      if escrow && escrow["held"]
        ret_payload = {
          "listing_id" => listing["id"],
          "kind" => escrow["held"]["kind"],
          "payload" => escrow["held"]["payload"],
          "reason" => "expired"
        }
        safe_send_sid(sid_sockets, seller_sid, "GTS_RETURN:" + MiniJSON.dump(ret_payload))
        MultiplayerDebug.info("GTS", "Expired listing #{listing["id"]} returned to online seller (UUID: #{seller_uuid[0..7]}...)")
      end
    else
      # Owner offline - just remove from market (items lost)
      MultiplayerDebug.warn("GTS", "Expired listing #{listing["id"]} removed (seller offline, items lost)")
    end
  end

  # Remove expired listings and their escrow
  expired.each do |listing|
    st["listings"].delete(listing)
    st["escrow"].delete(listing["id"])
  end

  if expired.length > 0
    gts_bump_rev!(st)
    gts_save!(st)
    MultiplayerDebug.info("GTS", "Cleaned up #{expired.length} expired listing(s)")
  end

  expired.length
end

# Load persisted market
gts_state = gts_load!(gts_state)
# Initialize listing sequence to max existing
gts_listing_seq = gts_state["listings"].map { |l| (l["id"] || "")[/\d+/].to_i }.max || 0

# ===========================================
# === Helpers
# ===========================================
def safe_send(sock, line)
  sock.puts(line); sock.flush
rescue => e
  MultiplayerDebug.warn("SEND", "Failed to send to client: #{e.message}")
end

def safe_send_sid(sid_sockets, sid, line)
  sock = sid_sockets[sid]
  return false unless sock
  safe_send(sock, line)
  true
end

def safe_broadcast(clients, sender, message)
  clients.each do |other|
    next if other.equal?(sender)
    begin; other.puts(message); rescue => e
      MultiplayerDebug.warn("B-001", "Broadcast to a client failed: #{e.message}")
    end
  end
end

# Ensure 'busy' is parsed numerically too
NUMERIC_SYNC_KEYS = [:x, :y, :map, :face, :skin_tone, :hair_color, :hat_color, :clothes_color, :busy]

def parse_sync_csv(sync_data)
  updates = {}
  sync_data.to_s.split(",").each do |pair|
    k, v = pair.split("=", 2)
    next if k.nil?
    k = k.to_sym
    v = v.nil? ? nil : v.strip
    next if v.nil? || v == ""
    if NUMERIC_SYNC_KEYS.include?(k)
      begin; updates[k] = Integer(v); rescue; end
    else
      updates[k] = v
    end
  end
  updates
end

def find_name_by_sid(client_data, sid)
  data = client_data.values.find { |h| h[:id] == sid }
  data ? (data[:name] || "") : ""
end

def info_for_sid(client_data, sid)
  client_data.values.find { |h| h[:id].to_s == sid.to_s }
end

def squad_state_packet(squads, client_data, squad_id)
  sq = squads[squad_id]; return "SQUAD_STATE:NONE" unless sq
  leader = sq[:leader]
  parts = sq[:members].map { |sid| "#{sid}|#{find_name_by_sid(client_data, sid)}" }
  "SQUAD_STATE:#{leader}|#{parts.join(",")}"
end

# --- Co-op helpers (range gate: same map + Manhattan distance ≤ 12) ---
def coop_gate_ok?(client_data, sid_a, sid_b)
  return false if sid_a.to_s == sid_b.to_s
  ia = info_for_sid(client_data, sid_a)
  ib = info_for_sid(client_data, sid_b)
  return false unless ia && ib
  return false unless ia[:map] && ib[:map]
  return false unless ia[:x] && ia[:y] && ib[:x] && ib[:y]
  return false unless ia[:map].to_i == ib[:map].to_i
  dx = (ia[:x].to_i - ib[:x].to_i).abs
  dy = (ia[:y].to_i - ib[:y].to_i).abs
  (dx + dy) <= 12
end

def coop_recipients_for(sender_sid, squads, member_squad, client_data)
  sq_id = member_squad[sender_sid.to_s]
  return [] unless sq_id && squads[sq_id]
  squads[sq_id][:members].select { |sid| sid != sender_sid && coop_gate_ok?(client_data, sender_sid, sid) }
end

def broadcast_coop_push_now_to_squad(squads, member_squad, sid_sockets, client_data, squad_id)
  sq = squads[squad_id]; return unless sq
  sq[:members].each { |sid| safe_send_sid(sid_sockets, sid, "COOP_PARTY_PUSH_NOW") }
  MultiplayerDebug.info("COOP", "Sent COOP_PARTY_PUSH_NOW to squad #{squad_id} members=#{sq[:members].join('/')}")
end

def broadcast_squad_state_to_members(squads, member_squad, sid_sockets, client_data, squad_id)
  pkt = squad_state_packet(squads, client_data, squad_id)
  squads[squad_id][:members].each { |sid| safe_send_sid(sid_sockets, sid, pkt) }
  MultiplayerDebug.info("SQUAD", "Broadcast state for squad #{squad_id}: #{pkt}")
  broadcast_coop_push_now_to_squad(squads, member_squad, sid_sockets, client_data, squad_id)
end

def repair_membership!(squads, member_squad, sid)
  sid = sid.to_s.strip
  sq_id = member_squad[sid]
  return unless sq_id
  sq = squads[sq_id]
  if !sq || !sq[:members].include?(sid)
    member_squad.delete(sid)
    MultiplayerDebug.warn("SQUAD", "Repaired stale member_squad entry for #{sid} (was #{sq_id})")
  end
end

def abort_trade(trades, sid_active_trade, sid_sockets, platinum_accounts, trade_id, reason)
  t = trades[trade_id]
  return unless t

  # Rollback platinum if transfer occurred
  platinum_rollback_trade(trades, platinum_accounts, sid_sockets, trade_id, reason) rescue nil

  a = t[:a_sid]; b = t[:b_sid]
  safe_send_sid(sid_sockets, a, "TRADE_ABORT:#{trade_id}|#{reason}") rescue nil
  safe_send_sid(sid_sockets, b, "TRADE_ABORT:#{trade_id}|#{reason}") rescue nil
  sid_active_trade.delete(a)
  sid_active_trade.delete(b)
  trades.delete(trade_id)
  MultiplayerDebug.warn("TRADE", "Aborted trade #{trade_id} (#{a} <-> #{b}) reason=#{reason}")
end

# ===========================================
# === GTS Cleanup Timer
# ===========================================
gts_last_cleanup = Time.now.to_i

# ===========================================
# === Main Server Loop
# ===========================================
loop do
  # Run GTS cleanup every 10 minutes
  now_i = Time.now.to_i
  if now_i - gts_last_cleanup >= 600  # 10 minutes
    GTS_MUTEX.synchronize do
      gts_cleanup_expired!(gts_state, sid_sockets)
    end
    gts_last_cleanup = now_i
  end

  # Accept new clients (non-blocking)
  if IO.select([server], nil, nil, 0.01)
    begin
      client = server.accept_nonblock
      peer_ip = client.peeraddr[3] rescue "unknown"
      peer_host = client.peeraddr[2] rescue "unknown"

      # IP Whitelist Check
      if !IP_WHITELIST.empty?
        is_localhost = (peer_ip == "127.0.0.1" || peer_ip == "::1" || peer_ip == "localhost")
        is_whitelisted = IP_WHITELIST.include?(peer_ip)

        if !is_whitelisted && !(ALWAYS_ALLOW_LOCALHOST && is_localhost)
          puts "[Server] REJECTED connection from #{peer_ip} (not in whitelist)"
          MultiplayerDebug.warn("WHITELIST", "Rejected IP: #{peer_ip}")
          client.close
          next
        end
      end

      next_session += 1
      session_id = "SID#{next_session}"

      clients << client
      client_ids[client] = session_id
      sid_sockets[session_id] = client

      client_data[client] = { id: session_id, name: nil, map: nil, x: 0, y: 0, clothes: "default", last_sync_state: {} }

      # Send ASSIGN_ID with integrity hash (if available)
      if @server_integrity_hash
        safe_send(client, "ASSIGN_ID:#{session_id}|VERIFY:#{@server_integrity_hash}")
      else
        safe_send(client, "ASSIGN_ID:#{session_id}")
      end

      puts "[Server] Client #{session_id} connected from #{peer_host} (#{peer_ip})"
      MultiplayerDebug.info("002", "Client #{session_id} connected from #{peer_host} (#{peer_ip})")
    rescue => e
      MultiplayerDebug.error("003", "Accept failed: #{e.message}")
    end
  end

  # Handle incoming data
  clients.dup.each do |c|
    begin
      if IO.select([c], nil, nil, 0.01)
        data = c.gets
        if data
          data.strip!
          sid = (client_data[c] ? client_data[c][:id] : "SID?").to_s.strip

          # --- PING ---
          # Support both simple PING and timestamped PING:seq:timestamp format
          if data == "PING" || data.start_with?("PING:")
            if data.start_with?("PING:")
              # New format: PING:sequence_id:timestamp
              parts = data.split(":", 3)
              seq = parts[1]
              timestamp = parts[2]

              # Send PONG with sequence and timestamp using MiniJSON
              pong_data = MiniJSON.dump({ "seq" => seq, "timestamp" => timestamp })
              safe_send(c, pong_data)

              MultiplayerDebug.info("PING", "Responded to PING ##{seq} from #{sid}")
            else
              # Old format: simple PING
              safe_send(c, "PONG")
              MultiplayerDebug.info("PING", "Responded to simple PING from #{sid}")
            end
            next
          end

          # --- MY_PING (client reports their calculated ping) ---
          if data.start_with?("MY_PING:")
            ping_ms = data.sub("MY_PING:", "").to_i

            # Store in client_data
            if client_data[c]
              client_data[c][:ping] = ping_ms
            end

            # Broadcast to all other clients
            broadcast_data = MiniJSON.dump({ "sid" => sid, "ping" => ping_ms })
            client_data.each_pair do |other_c, other_data|
              next if other_c == c  # Don't send to self
              safe_send(other_c, broadcast_data)
            end

            MultiplayerDebug.info("PING", "#{sid} reported ping: #{ping_ms}ms, broadcasted to #{client_data.size - 1} clients")
            next
          end


          # --- FILE_VERIFY ---
          if data.start_with?("FILE_VERIFY:")
            begin
              client_hash = data.sub("FILE_VERIFY:", "").strip

              # If server has no hash, allow connection
              if @server_integrity_hash.nil?
                safe_send(c, "INTEGRITY_OK")
                MultiplayerDebug.info("INTEGRITY", "#{sid} verification skipped (server hash unavailable)")
                next
              end

              # Compare hashes
              if client_hash == @server_integrity_hash
                safe_send(c, "INTEGRITY_OK")
                MultiplayerDebug.info("INTEGRITY", "#{sid} file integrity verified (hash: #{client_hash[0..7]}...)")
              else
                safe_send(c, "INTEGRITY_FAIL:File mismatch - your game files don't match the server. Please ensure you have the same version.")
                MultiplayerDebug.error("INTEGRITY", "#{sid} hash mismatch! Client: #{client_hash[0..7]}... Server: #{@server_integrity_hash[0..7]}...")
                puts "[Server] Rejected #{sid} - file integrity mismatch"

                # Disconnect client
                c.close
                clients.delete(c)
                sid_to_delete = client_ids[c]
                client_ids.delete(c)
                sid_sockets.delete(sid_to_delete) if sid_to_delete
                client_data.delete(c)
                next
              end
            rescue => e
              MultiplayerDebug.error("INTEGRITY", "#{sid} verification error: #{e.message}")
            end
            next
          end

          # --- NAME ---
          if data.start_with?("NAME:")
            begin
              name = data.sub("NAME:", "").strip
              client_data[c][:name] = name if client_data[c]
              MultiplayerDebug.info("NAME", "Registered name '#{name}' for #{sid}")
            rescue => e
              MultiplayerDebug.error("NAME", "Failed to register name for #{sid}: #{e.message}")
            end
            next
          end

          # ==========================================
          # === PLATINUM: Authentication handshake ==
          # ==========================================
          if data.start_with?("AUTH:")
            rate_check = ServerRateLimit.allow?(c, :GENERAL)
            if rate_check == :KICK
              MultiplayerDebug.warn("PLATINUM", "Auto-kicking #{sid} for abnormal AUTH rate")
              safe_send(c, "KICK:Abnormal activity detected")
              clients.delete(c)
              client_ids.delete(c)
              sid_sockets.delete(sid)
              client_data.delete(c)
              ServerRateLimit.remove_client(c)
              c.close rescue nil
              next
            elsif !rate_check
              MultiplayerDebug.warn("RATE", "AUTH rate limit exceeded for #{sid}")
              next
            end

            begin
              parts = data.sub("AUTH:", "").split(":", 3)
              tid = parts[0].to_i
              client_token = parts[1].to_s.strip
              client_uuid = parts[2].to_s.strip if parts.length > 2

              # Store TID in client_data for later use (wild battle account creation)
              client_data[c][:tid] = tid

              # Check if client provided existing UUID
              if client_uuid && !client_uuid.empty? && client_uuid != "NEW"
                # Client has UUID from previous session - verify it exists
                account = nil
                PLATINUM_MUTEX.synchronize { account = platinum_accounts[client_uuid] }

                if account
                  # UUID exists - verify TID matches
                  if account["tid"] == tid
                    # Valid returning player with UUID
                    client_data[c][:platinum_uuid] = client_uuid

                    # Get or verify token from account
                    existing_token = account["token"]
                    if existing_token
                      # Send existing token back to client (for persistence)
                      token_to_uuid[existing_token] = client_uuid
                      safe_send(c, "AUTH_TOKEN:#{existing_token}")
                    end

                    safe_send(c, "AUTH_OK")
                    safe_send(c, "PLATINUM_UUID:#{client_uuid}")
                    MultiplayerDebug.info("PLATINUM", "#{sid} authenticated with UUID (UUID: #{client_uuid[0..7]}..., balance: #{account["platinum"]} Pt)")
                  else
                    safe_send(c, "AUTH_FAIL:Trainer ID mismatch for UUID")
                    MultiplayerDebug.warn("PLATINUM", "#{sid} auth failed: UUID TID mismatch (expected #{account["tid"]}, got #{tid})")
                  end
                  next
                else
                  # UUID doesn't exist - CREATE ACCOUNT WITH CLIENT'S UUID (not generate new one)
                  MultiplayerDebug.warn("PLATINUM", "#{sid} provided unknown UUID #{client_uuid[0..7]}... - creating new account with this UUID")

                  uuid = client_uuid  # ✅ USE CLIENT'S UUID
                  token = platinum_generate_token(uuid)

                  PLATINUM_MUTEX.synchronize do
                    platinum_accounts[uuid] = {
                      "tid" => tid,
                      "name" => client_data[c][:name] || "Unknown",
                      "platinum" => 0,
                      "token" => token
                    }
                    token_to_uuid[token] = uuid
                  end

                  platinum_save!(platinum_accounts)

                  client_data[c][:platinum_uuid] = uuid
                  safe_send(c, "AUTH_TOKEN:#{token}")
                  safe_send(c, "PLATINUM_UUID:#{uuid}")
                  MultiplayerDebug.info("PLATINUM", "#{sid} created account with client UUID (UUID: #{uuid[0..7]}...)")
                  next  # ✅ SKIP THE "NEW" FLOW BELOW
                end
              end

              if client_token == "NEW"
                # First time player - generate NEW UUID and token
                uuid = platinum_generate_uuid  # ✅ Only called if client has NO UUID
                token = platinum_generate_token(uuid)

                PLATINUM_MUTEX.synchronize do
                  platinum_accounts[uuid] = {
                    "tid" => tid,
                    "name" => client_data[c][:name] || "Unknown",
                    "platinum" => 0,
                    "token" => token
                  }
                  token_to_uuid[token] = uuid
                end

                platinum_save!(platinum_accounts)

                client_data[c][:platinum_uuid] = uuid
                safe_send(c, "AUTH_TOKEN:#{token}")
                safe_send(c, "PLATINUM_UUID:#{uuid}")
                MultiplayerDebug.info("PLATINUM", "#{sid} registered new account (UUID: #{uuid[0..7]}...)")
              else
                # Returning player - validate token
                uuid = platinum_get_uuid_by_token(token_to_uuid, client_token)

                if uuid
                  # Verify trainer ID matches (security check)
                  account = nil
                  PLATINUM_MUTEX.synchronize { account = platinum_accounts[uuid] }

                  if account && account["tid"] == tid
                    client_data[c][:platinum_uuid] = uuid
                    safe_send(c, "AUTH_OK")
                    safe_send(c, "PLATINUM_UUID:#{uuid}")
                    MultiplayerDebug.info("PLATINUM", "#{sid} authenticated (UUID: #{uuid[0..7]}..., balance: #{account["platinum"]} Pt)")
                  else
                    safe_send(c, "AUTH_FAIL:Trainer ID mismatch")
                    MultiplayerDebug.warn("PLATINUM", "#{sid} auth failed: TID mismatch")
                  end
                else
                  safe_send(c, "AUTH_FAIL:Invalid token")
                  MultiplayerDebug.warn("PLATINUM", "#{sid} auth failed: Invalid token")
                end
              end
            rescue => e
              MultiplayerDebug.error("PLATINUM", "AUTH error for #{sid}: #{e.message}")
              safe_send(c, "AUTH_FAIL:Server error")
            end
            next
          end

          # =========================================
          # === PLATINUM: Request balance
          # =========================================
          if data.start_with?("REQ_PLATINUM")
            rate_check = ServerRateLimit.allow?(c, :GENERAL)
            if rate_check == :KICK
              MultiplayerDebug.warn("PLATINUM", "Auto-kicking #{sid} for abnormal REQ_PLATINUM rate")
              safe_send(c, "KICK:Abnormal activity detected")
              clients.delete(c)
              client_ids.delete(c)
              sid_sockets.delete(sid)
              client_data.delete(c)
              ServerRateLimit.remove_client(c)
              c.close rescue nil
              next
            elsif !rate_check
              MultiplayerDebug.warn("RATE", "REQ_PLATINUM rate limit exceeded for #{sid}")
              next
            end

            begin
              uuid = client_data[c][:platinum_uuid]
              if uuid
                balance = platinum_get_balance(platinum_accounts, uuid)
                safe_send(c, "PLATINUM_BAL:#{balance}")
                MultiplayerDebug.info("PLATINUM", "#{sid} queried balance: #{balance} Pt")
              else
                safe_send(c, "PLATINUM_ERR:Not authenticated")
                MultiplayerDebug.warn("PLATINUM", "#{sid} balance request without auth")
              end
            rescue => e
              MultiplayerDebug.error("PLATINUM", "REQ_PLATINUM error for #{sid}: #{e.message}")
              safe_send(c, "PLATINUM_ERR:Server error")
            end
            next
          end

          # =========================================
          # === PLATINUM: Spend request
          # =========================================
          if data.start_with?("SPEND_PLATINUM:")
            rate_check = ServerRateLimit.allow?(c, :GENERAL)
            if rate_check == :KICK
              MultiplayerDebug.warn("PLATINUM", "Auto-kicking #{sid} for abnormal SPEND_PLATINUM rate")
              safe_send(c, "KICK:Abnormal activity detected")
              clients.delete(c)
              client_ids.delete(c)
              sid_sockets.delete(sid)
              client_data.delete(c)
              ServerRateLimit.remove_client(c)
              c.close rescue nil
              next
            elsif !rate_check
              MultiplayerDebug.warn("RATE", "SPEND_PLATINUM rate limit exceeded for #{sid}")
              next
            end

            begin
              payload = data.sub("SPEND_PLATINUM:", "")
              parts = payload.split(",", 2)
              amount = parts[0].to_i
              reason = parts[1].to_s.strip

              uuid = client_data[c][:platinum_uuid]
              if !uuid
                safe_send(c, "PLATINUM_ERR:Not authenticated")
                MultiplayerDebug.warn("PLATINUM", "#{sid} spend request without auth")
                next
              end

              if amount <= 0
                safe_send(c, "PLATINUM_ERR:Invalid amount")
                MultiplayerDebug.warn("PLATINUM", "#{sid} invalid spend amount: #{amount}")
                next
              end

              # Check balance and deduct
              success = false
              new_balance = 0

              PLATINUM_MUTEX.synchronize do
                account = platinum_accounts[uuid]
                if account
                  current_balance = account["platinum"].to_i

                  if current_balance >= amount
                    account["platinum"] = current_balance - amount
                    new_balance = account["platinum"]
                    success = true
                  end
                end
              end

              if success
                platinum_save!(platinum_accounts)
                safe_send(c, "PLATINUM_OK:#{new_balance}")
                MultiplayerDebug.info("PLATINUM", "#{sid} spent #{amount} Pt (#{reason}), new balance: #{new_balance} Pt")
              else
                safe_send(c, "PLATINUM_ERR:Insufficient balance")
                MultiplayerDebug.warn("PLATINUM", "#{sid} insufficient balance for #{amount} Pt")
              end
            rescue => e
              MultiplayerDebug.error("PLATINUM", "SPEND_PLATINUM error for #{sid}: #{e.message}")
              safe_send(c, "PLATINUM_ERR:Server error")
            end
            next
          end


          # ======================================
          # === CO-OP: Battle queue first-come-first-served
          # ======================================
          if data.start_with?("COOP_BTL_START:")
            payload = data.sub("COOP_BTL_START:", "")
            squad_id = member_squad[sid]

            # Check if squad has active battle
            if squad_id && active_battles[squad_id]
              existing = active_battles[squad_id]
              # Check timeout (auto-clear stale locks)
              if Time.now - existing[:started_at] > BATTLE_LOCK_TIMEOUT
                active_battles.delete(squad_id)
                MultiplayerDebug.info("COOP-QUEUE", "Cleared stale battle lock for squad #{squad_id}")
              elsif existing[:initiator_sid] != sid
                # Another player started battle first - auto-join them instead
                MultiplayerDebug.info("COOP-QUEUE", "Auto-joining #{sid} to #{existing[:initiator_sid]}'s battle")

                # Send the original battle invite to this player
                if existing[:payload]
                  safe_send(c, "FROM:#{existing[:initiator_sid]}|COOP_BTL_START:#{existing[:payload]}")
                  MultiplayerDebug.info("COOP-QUEUE", "Forwarded battle invite to #{sid}")
                else
                  # Fallback - just notify them
                  safe_send(c, "COOP_BATTLE_BUSY:#{existing[:initiator_sid]}")
                  MultiplayerDebug.info("COOP-QUEUE", "No payload stored, sent BUSY to #{sid}")
                end
                next
              end
            end

            # First request or timeout cleared - claim battle slot and store payload
            if squad_id
              active_battles[squad_id] = {
                initiator_sid: sid,
                battle_type: :wild,
                started_at: Time.now,
                payload: payload  # Store for late joiners
              }
              MultiplayerDebug.info("COOP-QUEUE", "#{sid} claimed battle slot for squad #{squad_id}")
            end

            # Relay to squad
            recips = coop_recipients_for(sid, squads, member_squad, client_data)
            if recips.empty?
              MultiplayerDebug.info("COOP", "No eligible recipients for COOP_BTL_START from #{sid}")
            else
              recips.each { |rsid| safe_send_sid(sid_sockets, rsid, "FROM:#{sid}|COOP_BTL_START:#{payload}") }
              MultiplayerDebug.info("COOP", "Relayed COOP_BTL_START from #{sid} -> #{recips.join('/')} len=#{payload.length}")
            end
            next
          end


          # ======================================
          # === CO-OP: Battle joined acknowledgment
          # ======================================
          if data.start_with?("COOP_BATTLE_JOINED:")
            payload = data.sub("COOP_BATTLE_JOINED:", "")
            recips = coop_recipients_for(sid, squads, member_squad, client_data)
            if recips.empty?
              MultiplayerDebug.info("COOP", "No eligible recipients for COOP_BATTLE_JOINED from #{sid}")
            else
              recips.each { |rsid| safe_send_sid(sid_sockets, rsid, "FROM:#{sid}|COOP_BATTLE_JOINED:#{payload}") }
              MultiplayerDebug.info("COOP", "Relayed COOP_BATTLE_JOINED from #{sid} -> #{recips.join('/')}")
            end
            next
          end

          # ======================================
          # === CO-OP: Battle end cleanup
          # ======================================
          if data.start_with?("COOP_BATTLE_END")
            squad_id = member_squad[sid]
            if squad_id && active_battles[squad_id]
              active_battles.delete(squad_id)
              MultiplayerDebug.info("COOP-QUEUE", "Cleared battle slot for squad #{squad_id} (battle ended by #{sid})")
            end
            next
          end

          # ======================================
          # === MODULE 4: CO-OP Action Sync (with rate limiting)
          # ======================================
          if data.start_with?("COOP_ACTION:")
            # Rate limit check with anti-cheat auto-kick
            rate_check = ServerRateLimit.allow?(c, :ACTION)
            if rate_check == :KICK
              puts "[ANTI-CHEAT] Auto-kicking #{sid} for abnormal COOP_ACTION rate"
              safe_send(c, "KICK:Abnormal activity detected - excessive ACTION messages")
              clients.delete(c)
              client_ids.delete(c)
              sid_sockets.delete(sid)
              client_data.delete(c)
              ServerRateLimit.remove_client(c)
              c.close rescue nil
              next
            elsif !rate_check
              MultiplayerDebug.warn("RATE", "COOP_ACTION rate limit exceeded for #{sid}")
              next
            end

            payload = data.sub("COOP_ACTION:", "")
            recips = coop_recipients_for(sid, squads, member_squad, client_data)
            if recips.empty?
              MultiplayerDebug.info("COOP-SYNC", "No eligible recipients for COOP_ACTION from #{sid}")
            else
              # Parse battle_id and turn from payload for ACK tracking
              parts = payload.split("|", 3)
              battle_id = parts[0] if parts.length >= 1
              turn = parts[1] if parts.length >= 2

              recips.each do |rsid|
                safe_send_sid(sid_sockets, rsid, "FROM:#{sid}|COOP_ACTION:#{payload}")

                # Track pending ACK
                if battle_id && turn
                  ack_key = "#{sid}|#{rsid}|#{battle_id}|#{turn}"
                  pending_acks[ack_key] = { payload: payload, sent_at: Time.now, attempts: 1 }
                end
              end
              MultiplayerDebug.info("COOP-SYNC", "Relayed COOP_ACTION from #{sid} -> #{recips.join('/')}, len=#{payload.length}")
            end
            next
          end

          # ======================================
          # === ACK Handler
          # ======================================
          if data.start_with?("COOP_ACTION_ACK:")
            # Format: COOP_ACTION_ACK:<battle_id>|<turn>|<from_sid>
            parts = data.sub("COOP_ACTION_ACK:", "").split("|", 3)
            if parts.length == 3
              battle_id, turn, from_sid = parts
              ack_key = "#{from_sid}|#{sid}|#{battle_id}|#{turn}"
              if pending_acks.delete(ack_key)
                MultiplayerDebug.info("COOP-ACK", "Received ACK from #{sid} for action from #{from_sid}: battle=#{battle_id}, turn=#{turn}")
              end
            end
            next
          end

          # ======================================
          # === MODULE 6: CO-OP RNG Seed Sync (with rate limiting)
          # ======================================
          if data.start_with?("COOP_RNG_SEED:")
            # Rate limit check with anti-cheat auto-kick
            rate_check = ServerRateLimit.allow?(c, :RNG)
            if rate_check == :KICK
              puts "[ANTI-CHEAT] Auto-kicking #{sid} for abnormal COOP_RNG_SEED rate"
              safe_send(c, "KICK:Abnormal activity detected - excessive RNG messages")
              clients.delete(c)
              client_ids.delete(c)
              sid_sockets.delete(sid)
              client_data.delete(c)
              ServerRateLimit.remove_client(c)
              c.close rescue nil
              next
            elsif !rate_check
              MultiplayerDebug.warn("RATE", "COOP_RNG_SEED rate limit exceeded for #{sid}")
              next
            end

            payload = data.sub("COOP_RNG_SEED:", "")
            recips = coop_recipients_for(sid, squads, member_squad, client_data)
            if recips.empty?
              MultiplayerDebug.info("COOP-RNG", "No eligible recipients for COOP_RNG_SEED from #{sid}")
            else
              recips.each { |rsid| safe_send_sid(sid_sockets, rsid, "FROM:#{sid}|COOP_RNG_SEED:#{payload}") }
              MultiplayerDebug.info("COOP-RNG", "Relayed COOP_RNG_SEED from #{sid} -> #{recips.join('/')}")
            end
            next
          end

          if data.start_with?("COOP_RNG_SEED_ACK:")
            payload = data.sub("COOP_RNG_SEED_ACK:", "")
            recips = coop_recipients_for(sid, squads, member_squad, client_data)
            if recips.empty?
              MultiplayerDebug.info("COOP-RNG", "No eligible recipients for COOP_RNG_SEED_ACK from #{sid}")
            else
              recips.each { |rsid| safe_send_sid(sid_sockets, rsid, "FROM:#{sid}|COOP_RNG_SEED_ACK:#{payload}") }
              MultiplayerDebug.info("COOP-RNG", "Relayed COOP_RNG_SEED_ACK from #{sid} -> #{recips.join('/')}")
            end
            next
          end

          # ======================================
          # === MODULE 14: CO-OP Switch Sync
          # ======================================
          if data.start_with?("COOP_SWITCH:")
            payload = data.sub("COOP_SWITCH:", "")
            recips = coop_recipients_for(sid, squads, member_squad, client_data)
            if recips.empty?
              MultiplayerDebug.info("COOP-SWITCH", "No eligible recipients for COOP_SWITCH from #{sid}")
            else
              recips.each { |rsid| safe_send_sid(sid_sockets, rsid, "FROM:#{sid}|COOP_SWITCH:#{payload}") }
              MultiplayerDebug.info("COOP-SWITCH", "Relayed COOP_SWITCH from #{sid} -> #{recips.join('/')}, payload=#{payload}")
            end
            next
          end

          if data.start_with?("COOP_MOVE_SYNC:")
            payload = data.sub("COOP_MOVE_SYNC:", "")
            recips = coop_recipients_for(sid, squads, member_squad, client_data)
            if recips.empty?
              MultiplayerDebug.info("COOP", "No eligible recipients for COOP_MOVE_SYNC from #{sid}")
            else
              recips.each { |rsid| safe_send_sid(sid_sockets, rsid, "FROM:#{sid}|COOP_MOVE_SYNC:#{payload}") }
              MultiplayerDebug.info("COOP", "Relayed COOP_MOVE_SYNC from #{sid} -> #{recips.join(',')}")
            end
            next
          end

          # ======================================
          # === CO-OP: Battle choice relay
          # ======================================
          if data.start_with?("COOP_BATTLE_CHOICE:")
            payload = data.sub("COOP_BATTLE_CHOICE:", "")
            recips = coop_recipients_for(sid, squads, member_squad, client_data)
            if recips.empty?
              MultiplayerDebug.info("COOP", "No eligible recipients for COOP_BATTLE_CHOICE from #{sid}")
            else
              recips.each { |rsid| safe_send_sid(sid_sockets, rsid, "FROM:#{sid}|COOP_BATTLE_CHOICE:#{payload}") }
              MultiplayerDebug.info("COOP", "Relayed COOP_BATTLE_CHOICE from #{sid} -> #{recips.join('/')} len=#{payload.length}")
            end
            next
          end

          # --- SYNC (with rate limiting) ---
          if data.start_with?("SYNC:")
            # Rate limit check with anti-cheat auto-kick
            rate_check = ServerRateLimit.allow?(c, :SYNC)
            if rate_check == :KICK
              puts "[ANTI-CHEAT] Auto-kicking #{sid} for abnormal SYNC rate"
              safe_send(c, "KICK:Abnormal activity detected - excessive SYNC messages")
              clients.delete(c)
              client_ids.delete(c)
              sid_sockets.delete(sid)
              client_data.delete(c)
              ServerRateLimit.remove_client(c)
              c.close rescue nil
              next
            elsif !rate_check
              MultiplayerDebug.warn("RATE", "SYNC rate limit exceeded for #{sid}")
              next
            end

            begin
              sync_data = data.sub("SYNC:", "")

              # Decode delta from client (now using delta compression)
              delta = DeltaCompression.decode_delta(sync_data)

              # Reconstruct full state by applying delta to last known state
              last_state = client_data[c][:last_sync_state] || {}
              full_state = DeltaCompression.apply_delta(last_state, delta)

              # Store reconstructed state for next delta
              client_data[c][:last_sync_state] = full_state

              # Use delta as updates (it already contains only changed fields)
              updates = delta

              # Track if player was busy before update
              was_busy = client_data[c] && client_data[c][:busy].to_i == 1

              client_data[c].merge!(updates) if client_data[c] && !updates.empty?

              # Check if player just exited battle (was busy=1, now busy=0)
              now_busy = client_data[c] && client_data[c][:busy].to_i == 1
              if was_busy && !now_busy
                # Player exited battle - check if their squad needs state broadcast
                sq_id = member_squad[sid]
                if sq_id && squads[sq_id]
                  # Check if all squad members are now out of battle
                  all_members_free = squads[sq_id][:members].all? do |member_sid|
                    member_socket = sid_sockets[member_sid]
                    member_socket.nil? || client_data[member_socket].nil? || client_data[member_socket][:busy].to_i == 0
                  end

                  if all_members_free
                    MultiplayerDebug.info("SQUAD", "All members of squad #{sq_id} exited battle - broadcasting delayed state update")
                    broadcast_squad_state_to_members(squads, member_squad, sid_sockets, client_data, sq_id)
                  end
                end
              end

              # Broadcast the RECONSTRUCTED FULL STATE (not the delta) to other clients
              # This ensures joining clients receive complete player data
              full_state_encoded = DeltaCompression.encode_delta(full_state)
              msg = "FROM:#{sid}|SYNC:#{full_state_encoded}"
              safe_broadcast(clients, c, msg)
              #MultiplayerDebug.info("BCAST", "Rebroadcasted: #{msg}")
            rescue => e
              MultiplayerDebug.error("SYNC", "Malformed SYNC packet from #{sid}: #{e.message}")
            end
            next
          end


          # --- Player list request ---
          if data == "REQ_PLAYERS"
            begin
              pending_details[c] = { started: Time.now, timeout: 1.5, data: {} }
              clients.each { |cli| safe_send(cli, "REQ_DETAILS") }
              MultiplayerDebug.info("REQPLAY", "Triggered details sweep for requester #{sid}")
            rescue => e
              MultiplayerDebug.error("REQPLAY", "Failed to trigger details sweep for #{sid}: #{e.message}")
            end
            next
          end


          # --- DETAILS response ---
          if data.start_with?("DETAILS:")
            begin
              parts   = data.sub("DETAILS:", "").split("|")
              sid_det       = (parts[0] || sid).to_s.strip
              name          = parts[1] || nil
              map           = parts[2] ? parts[2].to_i : nil
              x             = parts[3] ? parts[3].to_i : nil
              y             = parts[4] ? parts[4].to_i : nil
              clothes       = parts[5] || "default"
              hat           = parts[6] || "000"
              hair          = parts[7] || "000"
              skin_tone     = parts[8]  ? parts[8].to_i  : 0
              hair_color    = parts[9]  ? parts[9].to_i  : 0
              hat_color     = parts[10] ? parts[10].to_i : 0
              clothes_color = parts[11] ? parts[11].to_i : 0

              if client_data[c]
                client_data[c][:name]          = name
                client_data[c][:map]           = map
                client_data[c][:x]             = x
                client_data[c][:y]             = y
                client_data[c][:clothes]       = clothes
                client_data[c][:hat]           = hat
                client_data[c][:hair]          = hair
                client_data[c][:skin_tone]     = skin_tone
                client_data[c][:hair_color]    = hair_color
                client_data[c][:hat_color]     = hat_color
                client_data[c][:clothes_color] = clothes_color
              end

              pending_details.each_value do |pend|
                pend[:data][sid_det] = {
                  name: name, map: map, x: x, y: y, clothes: clothes, hat: hat, hair: hair,
                  skin_tone: skin_tone, hair_color: hair_color, hat_color: hat_color, clothes_color: clothes_color
                }
              end

              MultiplayerDebug.info("DETAILS", "Stored details for #{sid_det}: name='#{name}', map=#{map}, pos=#{x},#{y}, clothes=#{clothes}, hat=#{hat}, hair=#{hair}")
            rescue => e
              MultiplayerDebug.error("DETAILS", "Failed parsing DETAILS from #{sid}: #{e.message}")
            end
            next
          end


          # ===========================
          # === SQUAD: Commands =======
          # ===========================
          if data.start_with?("SQUAD_INVITE:")
            raw_to_sid = data.split(":", 2)[1]
            to_sid = raw_to_sid ? raw_to_sid.strip : nil
            from_sid = sid
            begin
              if to_sid.nil? || to_sid.empty? || to_sid == from_sid
                safe_send(c, "SQUAD_ERROR:INVALID_TARGET"); next
              end

              repair_membership!(squads, member_squad, to_sid)
              repair_membership!(squads, member_squad, from_sid)

              if pending_invites.key?(to_sid)
                existing = pending_invites[to_sid]
                if existing[:from_sid] != from_sid
                  safe_send(c, "SQUAD_ERROR:INVITEE_BUSY")
                  MultiplayerDebug.info("SQUAD", "Invite blocked: #{from_sid} -> #{to_sid} (busy by #{existing[:from_sid]})")
                  next
                else
                  MultiplayerDebug.info("SQUAD", "Invite refresh: #{from_sid} -> #{to_sid}")
                end
              end

              squad_id = member_squad[from_sid]
              if squad_id.nil?
                next_squad_id += 1
                squad_id = next_squad_id
                squads[squad_id] = { leader: from_sid, members: [from_sid], created_at: Time.now }
                member_squad[from_sid] = squad_id
                MultiplayerDebug.info("SQUAD", "Created new squad #{squad_id} by #{from_sid}")
              end

              sq = squads[squad_id]
              if sq[:members].length >= SQUAD_MAX
                safe_send(c, "SQUAD_ERROR:SQUAD_FULL"); next
              end
              if member_squad[to_sid]
                safe_send(c, "SQUAD_ERROR:INVITEE_IN_SQUAD"); next
              end

              pending_invites[to_sid] = { from_sid: from_sid, squad_id: squad_id }

              from_name = find_name_by_sid(client_data, from_sid)
              if safe_send_sid(sid_sockets, to_sid, "SQUAD_INVITE:#{from_sid}|#{from_name}")
                safe_send(c, "SQUAD_INVITE_SENT:#{to_sid}")
                MultiplayerDebug.info("SQUAD", "Invite queued: #{from_sid} -> #{to_sid} (squad #{squad_id})")
              else
                pending_invites.delete(to_sid)
                safe_send(c, "SQUAD_ERROR:TARGET_OFFLINE")
              end
            rescue => e
              MultiplayerDebug.error("SQUAD", "Invite error #{from_sid} -> #{to_sid}: #{e.message}")
              safe_send(c, "SQUAD_ERROR:SERVER")
            end
            next
          end


          if data.start_with?("SQUAD_RESP:")
            rest = data.split(":", 2)[1]
            parts = rest.split("|", 2)
            from_sid  = (parts[0] || "").to_s.strip   # inviter SID
            decision  = (parts[1] || "").upcase
            to_sid    = sid

            begin
              repair_membership!(squads, member_squad, to_sid)
              repair_membership!(squads, member_squad, from_sid)

              inv = pending_invites[to_sid]

              if decision == "DECLINE"
                pending_invites.delete(to_sid) if inv && inv[:from_sid] == from_sid
                safe_send_sid(sid_sockets, from_sid, "SQUAD_DECLINED:#{to_sid}")
                MultiplayerDebug.info("SQUAD", "Invite declined: #{to_sid} -> #{from_sid}")
                next
              end

              if inv.nil? || inv[:from_sid].to_s.strip != from_sid
                sq_id = member_squad[from_sid]
                if sq_id && squads[sq_id] && !member_squad[to_sid] && squads[sq_id][:members].length < SQUAD_MAX
                  squads[sq_id][:members] << to_sid
                  member_squad[to_sid] = sq_id
                  MultiplayerDebug.warn("SQUAD", "ACCEPT fallback used: #{to_sid} joined #{sq_id} (inviter #{from_sid})")
                  broadcast_squad_state_to_members(squads, member_squad, sid_sockets, client_data, sq_id)
                else
                  MultiplayerDebug.warn("SQUAD", "ACCEPT fallback failed: inv nil/mismatch for to=#{to_sid}, from=#{from_sid}")
                  safe_send_sid(sid_sockets, from_sid, "SQUAD_INVITE_EXPIRED:#{to_sid}")
                  safe_send(c, "SQUAD_ERROR:INVITE_EXPIRED")
                end
                next
              end

              squad_id = inv[:squad_id]
              pending_invites.delete(to_sid)

              if member_squad[to_sid]
                safe_send_sid(sid_sockets, from_sid, "SQUAD_ERROR:INVITEE_IN_SQUAD")
                safe_send(c, "SQUAD_ERROR:ALREADY_IN_SQUAD"); next
              end
              sq = squads[squad_id]
              unless sq
                safe_send_sid(sid_sockets, from_sid, "SQUAD_ERROR:SQUAD_NOT_FOUND")
                safe_send(c, "SQUAD_ERROR:SQUAD_NOT_FOUND"); next
              end
              if sq[:members].length >= SQUAD_MAX
                safe_send_sid(sid_sockets, from_sid, "SQUAD_ERROR:SQUAD_FULL")
                safe_send(c, "SQUAD_ERROR:SQUAD_FULL"); next
              end

              sq[:members] << to_sid
              member_squad[to_sid] = squad_id
              MultiplayerDebug.info("SQUAD", "Accepted: #{to_sid} joined squad #{squad_id}")
              broadcast_squad_state_to_members(squads, member_squad, sid_sockets, client_data, squad_id)
            rescue => e
              MultiplayerDebug.error("SQUAD", "RESP error #{to_sid} -> #{from_sid}: #{e.message}")
              safe_send(c, "SQUAD_ERROR:SERVER")
            end
            next
          end


          if data == "REQ_SQUAD"
            sid_here = sid
            begin
              sq_id = member_squad[sid_here]
              pkt = sq_id ? squad_state_packet(squads, client_data, sq_id) : "SQUAD_STATE:NONE"
              safe_send(c, pkt)
              broadcast_coop_push_now_to_squad(squads, member_squad, sid_sockets, client_data, sq_id) if sq_id
            rescue => e
              MultiplayerDebug.error("SQUAD", "REQ_SQUAD error for #{sid_here}: #{e.message}")
              safe_send(c, "SQUAD_STATE:NONE")
            end
            next
          end


          if data.start_with?("SQUAD_KICK:")
            target_sid = (data.split(":", 2)[1] || "").to_s.strip
            leader_sid = sid
            begin
              repair_membership!(squads, member_squad, target_sid)
              repair_membership!(squads, member_squad, leader_sid)

              sq_id = member_squad[leader_sid]
              if !sq_id || !squads[sq_id] || squads[sq_id][:leader] != leader_sid
                safe_send(c, "SQUAD_ERROR:NOT_LEADER"); next
              end
              if !member_squad[target_sid] || member_squad[target_sid] != sq_id
                safe_send(c, "SQUAD_ERROR:NOT_IN_SQUAD"); next
              end

              squads[sq_id][:members].delete(target_sid)
              member_squad.delete(target_sid)
              safe_send_sid(sid_sockets, target_sid, "SQUAD_INFO:KICKED")
              MultiplayerDebug.info("SQUAD", "Leader #{leader_sid} kicked #{target_sid} from squad #{sq_id}")
              broadcast_squad_state_to_members(squads, member_squad, sid_sockets, client_data, sq_id)
            rescue => e
              MultiplayerDebug.error("SQUAD", "KICK error by #{leader_sid} on #{target_sid}: #{e.message}")
              safe_send(c, "SQUAD_ERROR:SERVER")
            end
            next
          end


          if data.start_with?("SQUAD_TRANSFER:")
            target_sid = (data.split(":", 2)[1] || "").to_s.strip
            leader_sid = sid
            begin
              repair_membership!(squads, member_squad, target_sid)
              repair_membership!(squads, member_squad, leader_sid)

              sq_id = member_squad[leader_sid]
              if !sq_id || !squads[sq_id] || squads[sq_id][:leader] != leader_sid
                safe_send(c, "SQUAD_ERROR:NOT_LEADER"); next
              end
              if !member_squad[target_sid] || member_squad[target_sid] != sq_id
                safe_send(c, "SQUAD_ERROR:NOT_IN_SQUAD"); next
              end
              squads[sq_id][:leader] = target_sid
              MultiplayerDebug.info("SQUAD", "Leadership transfer in squad #{sq_id}: #{leader_sid} -> #{target_sid}")
              broadcast_squad_state_to_members(squads, member_squad, sid_sockets, client_data, sq_id)
            rescue => e
              MultiplayerDebug.error("SQUAD", "TRANSFER error by #{leader_sid} to #{target_sid}: #{e.message}")
              safe_send(c, "SQUAD_ERROR:SERVER")
            end
            next
          end


          if data == "SQUAD_LEAVE"
            leaver = sid
            begin
              repair_membership!(squads, member_squad, leaver)

              sq_id = member_squad[leaver]
              if !sq_id || !squads[sq_id]
                safe_send(c, "SQUAD_STATE:NONE"); next
              end

              squads[sq_id][:members].delete(leaver)
              member_squad.delete(leaver)
              MultiplayerDebug.info("SQUAD", "Member #{leaver} left squad #{sq_id}")

              if squads[sq_id][:leader] == leaver && squads[sq_id][:members].any?
                new_leader = squads[sq_id][:members].first
                squads[sq_id][:leader] = new_leader
                MultiplayerDebug.info("SQUAD", "Auto-transferred leadership in squad #{sq_id} to #{new_leader}")
              end

              if squads[sq_id][:members].empty?
                squads.delete(sq_id)
                MultiplayerDebug.info("SQUAD", "Disbanded squad #{sq_id} (last member left)")
                safe_send(c, "SQUAD_STATE:NONE")
              else
                broadcast_squad_state_to_members(squads, member_squad, sid_sockets, client_data, sq_id)
                safe_send(c, "SQUAD_STATE:NONE")
              end
            rescue => e
              MultiplayerDebug.error("SQUAD", "LEAVE error by #{leaver}: #{e.message}")
              safe_send(c, "SQUAD_ERROR:SERVER")
            end
            next
          end


          # ===========================
          # === PVP: Challenge System =
          # ===========================
          if data.start_with?("PVP_CHALLENGE:")
            payload = data.sub("PVP_CHALLENGE:", "")
            parts = payload.split("|", 2)
            target_sid = parts[0].to_s.strip
            hex_payload = parts[1]
            challenger_sid = sid

            if target_sid.empty? || target_sid == challenger_sid
              safe_send(c, "PVP_ERROR:INVALID_TARGET")
              next
            end

            target_sock = sid_sockets[target_sid]
            if target_sock.nil?
              safe_send(c, "PVP_ERROR:TARGET_OFFLINE")
              next
            end

            # Forward challenge to target with FROM: prefix
            safe_send(target_sock, "FROM:#{challenger_sid}|PVP_CHALLENGE:#{payload}")
            safe_send(c, "PVP_CHALLENGE_SENT:#{target_sid}")
            MultiplayerDebug.info("PVP", "Challenge #{challenger_sid} -> #{target_sid}")
            next
          end

          if data.start_with?("PVP_ACCEPT:")
            target_sid = data.sub("PVP_ACCEPT:", "").strip
            if safe_send_sid(sid_sockets, target_sid, "FROM:#{sid}|PVP_ACCEPT:#{sid}")
              MultiplayerDebug.info("PVP", "Accept #{sid} -> #{target_sid}")
            end
            next
          end

          if data.start_with?("PVP_DECLINE:")
            target_sid = data.sub("PVP_DECLINE:", "").strip
            if safe_send_sid(sid_sockets, target_sid, "FROM:#{sid}|PVP_DECLINE:#{sid}")
              MultiplayerDebug.info("PVP", "Decline #{sid} -> #{target_sid}")
            end
            next
          end

          if data.start_with?("PVP_TEAM_SELECTION:")
            payload = data.sub("PVP_TEAM_SELECTION:", "")
            parts = payload.split("|", 2)
            target_sid = parts[0].to_s.strip

            if safe_send_sid(sid_sockets, target_sid, "FROM:#{sid}|PVP_TEAM_SELECTION:#{payload}")
              MultiplayerDebug.info("PVP", "Team selection #{sid} -> #{target_sid}")
            end
            next
          end

          if data.start_with?("PVP_BATTLE_START:")
            payload = data.sub("PVP_BATTLE_START:", "")
            parts = payload.split("|", 2)
            target_sid = parts[0].to_s.strip

            if safe_send_sid(sid_sockets, target_sid, "FROM:#{sid}|PVP_BATTLE_START:#{payload}")
              MultiplayerDebug.info("PVP", "Battle start #{sid} -> #{target_sid}")
            end
            next
          end

          if data.start_with?("PVP_OUTCOME:")
            payload = data.sub("PVP_OUTCOME:", "")
            parts = payload.split("|", 3)
            battle_id = parts[0]
            winner_sid = parts[1].to_s.strip
            loser_sid = parts[2].to_s.strip

            # Update win counter for winner (server-side tracking)
            winner_sock = sid_sockets[winner_sid]
            if winner_sock && client_data[winner_sock]
              winner_uuid = client_data[winner_sock][:platinum_uuid]
              if winner_uuid && !winner_uuid.empty?
                pvp_wins[winner_uuid] ||= 0
                pvp_wins[winner_uuid] += 1
                save_pvp_wins(pvp_wins)
                MultiplayerDebug.info("PVP-WINS", "#{winner_uuid} wins: #{pvp_wins[winner_uuid]}")

                # Send win count to winner
                safe_send(winner_sock, "PVP_WIN_COUNT:#{pvp_wins[winner_uuid]}")
              else
                MultiplayerDebug.info("PVP-WINS", "Winner #{winner_sid} has no UUID - not tracking")
              end
            end

            # Send to both participants
            if safe_send_sid(sid_sockets, winner_sid, "FROM:#{sid}|PVP_OUTCOME:#{payload}")
              MultiplayerDebug.info("PVP", "Outcome sent to winner #{winner_sid}")
            end
            if safe_send_sid(sid_sockets, loser_sid, "FROM:#{sid}|PVP_OUTCOME:#{payload}")
              MultiplayerDebug.info("PVP", "Outcome sent to loser #{loser_sid}")
            end
            next
          end

          # ===========================
          # === TRADING: Commands =====
          # ===========================
          if data.start_with?("TRADE_REQ:")
            target_sid = data.split(":", 2)[1].to_s.strip
            if target_sid.empty? || target_sid == sid
              safe_send(c, "TRADE_ERROR:INVALID_TARGET")
              next
            end
            if sid_active_trade[sid]
              safe_send(c, "TRADE_ERROR:BUSY")
              next
            end
            target_sock = sid_sockets[target_sid]
            if target_sock.nil?
              safe_send(c, "TRADE_ERROR:TARGET_OFFLINE")
              next
            end
            if sid_active_trade[target_sid]
              safe_send(c, "TRADE_ERROR:TARGET_BUSY")
              next
            end
            req_name = client_data[c] ? (client_data[c][:name] || sid) : sid
            safe_send(target_sock, "TRADE_INVITE:#{sid}|#{req_name}")
            safe_send(c, "TRADE_INVITE_SENT:#{target_sid}")
            MultiplayerDebug.info("TRADE", "Invite #{sid} -> #{target_sid}")
            next
          end


          if data.start_with?("TRADE_RESP:")
            body = data.sub("TRADE_RESP:", "")
            req_sid, decision = body.split("|", 2)
            req_sid  = (req_sid || "").to_s.strip
            decision = (decision || "").to_s.upcase
            req_sock = sid_sockets[req_sid]

            if req_sock.nil?
              safe_send(c, "TRADE_ERROR:REQUESTER_OFFLINE")
              next
            end
            if sid_active_trade[sid] || sid_active_trade[req_sid]
              if decision == "ACCEPT"
                safe_send(c,       "TRADE_ERROR:BUSY")
                safe_send(req_sock,"TRADE_ERROR:TARGET_BUSY")
              else
                safe_send(req_sock,"TRADE_DECLINED:#{sid}")
              end
              next
            end

            if decision == "DECLINE"
              safe_send(req_sock, "TRADE_DECLINED:#{sid}")
              MultiplayerDebug.info("TRADE", "Declined by #{sid} for requester #{req_sid}")
              next
            end
            if decision != "ACCEPT"
              safe_send(c, "TRADE_ERROR:BAD_DECISION")
              next
            end

            trade_seq += 1
            trade_id = "T#{trade_seq}"
            trades[trade_id] = {
              a_sid: req_sid,
              b_sid: sid,
              offers: {},
              ready:  {},
              confirm:{},
              exec_ok:{},
              state: "active",
              t_last: Time.now
            }
            sid_active_trade[req_sid] = trade_id
            sid_active_trade[sid]     = trade_id

            # Get platinum balances for both players
            req_uuid = client_data.values.find { |h| h[:id] == req_sid }&.dig(:platinum_uuid)
            sid_uuid = client_data.values.find { |h| h[:id] == sid }&.dig(:platinum_uuid)
            req_platinum = req_uuid ? platinum_get_balance(platinum_accounts, req_uuid) : 0
            sid_platinum = sid_uuid ? platinum_get_balance(platinum_accounts, sid_uuid) : 0

            safe_send_sid(sid_sockets, req_sid, "TRADE_START:#{trade_id}|A=#{req_sid}|B=#{sid}|PLATINUM=#{req_platinum}")
            safe_send_sid(sid_sockets, sid,     "TRADE_START:#{trade_id}|A=#{req_sid}|B=#{sid}|PLATINUM=#{sid_platinum}")
            MultiplayerDebug.info("TRADE", "Started trade #{trade_id} between #{req_sid}(#{req_platinum}Pt) and #{sid}(#{sid_platinum}Pt)")
            next
          end


          if data.start_with?("TRADE_UPDATE:")
            body = data.sub("TRADE_UPDATE:", "")
            trade_id, json = body.split("|", 2)
            t = trades[trade_id]
            if t.nil?
              safe_send(c, "TRADE_ERROR:NO_SESSION")
              next
            end
            unless t[:a_sid] == sid || t[:b_sid] == sid
              safe_send(c, "TRADE_ERROR:NOT_PARTICIPANT")
              next
            end
            begin
              offer = json && json.size>0 ? MiniJSON.parse(json) : {}
            rescue
              safe_send(c, "TRADE_ERROR:BAD_JSON")
              next
            end
            t[:offers][sid] = offer
            t[:t_last] = Time.now
            t[:ready][sid]   = false
            t[:confirm][sid] = false
            other_sid = (t[:a_sid] == sid) ? t[:b_sid] : t[:a_sid]
            safe_send_sid(sid_sockets, other_sid, "TRADE_UPDATE:#{trade_id}|#{sid}|#{json}")
            safe_send_sid(sid_sockets, t[:a_sid], "TRADE_READY:#{trade_id}|#{sid}|false")
            safe_send_sid(sid_sockets, t[:b_sid], "TRADE_READY:#{trade_id}|#{sid}|false")
            safe_send_sid(sid_sockets, t[:a_sid], "TRADE_CONFIRM:#{trade_id}|#{sid}|false")
            safe_send_sid(sid_sockets, t[:b_sid], "TRADE_CONFIRM:#{trade_id}|#{sid}|false")
            MultiplayerDebug.info("TRADE", "Update in #{trade_id} by #{sid}")
            next
          end


          if data.start_with?("TRADE_READY:")
            body = data.sub("TRADE_READY:", "")
            trade_id, onoff = body.split("|", 2)
            t = trades[trade_id]
            if t.nil?
              safe_send(c, "TRADE_ERROR:NO_SESSION")
              next
            end
            unless t[:a_sid] == sid || t[:b_sid] == sid
              safe_send(c, "TRADE_ERROR:NOT_PARTICIPANT")
              next
            end
            val = (onoff.to_s.upcase == "ON")
            t[:ready][sid] = val
            t[:confirm][sid] = false if !val
            t[:t_last] = Time.now
            safe_send_sid(sid_sockets, t[:a_sid], "TRADE_READY:#{trade_id}|#{sid}|#{val}")
            safe_send_sid(sid_sockets, t[:b_sid], "TRADE_READY:#{trade_id}|#{sid}|#{val}")
            MultiplayerDebug.info("TRADE", "Ready #{val} for #{sid} in #{trade_id}")
            next
          end


          if data.start_with?("TRADE_CANCEL:")
            trade_id = data.split(":", 2)[1].to_s.strip
            t = trades[trade_id]
            if t
              abort_trade(trades, sid_active_trade, sid_sockets, platinum_accounts, trade_id, "CANCELLED_BY_#{sid}")
            else
              safe_send(c, "TRADE_ERROR:NO_SESSION")
            end
            next
          end


          if data.start_with?("TRADE_CONFIRM:")
            trade_id = data.split(":", 2)[1].to_s.strip
            t = trades[trade_id]
            if t.nil?
              safe_send(c, "TRADE_ERROR:NO_SESSION")
              next
            end
            unless t[:a_sid] == sid || t[:b_sid] == sid
              safe_send(c, "TRADE_ERROR:NOT_PARTICIPANT")
              next
            end
            unless t[:ready][sid]
              safe_send(c, "TRADE_ERROR:NOT_READY")
              next
            end
            t[:confirm][sid] = true
            t[:t_last] = Time.now
            safe_send_sid(sid_sockets, t[:a_sid], "TRADE_CONFIRM:#{trade_id}|#{sid}|true")
            safe_send_sid(sid_sockets, t[:b_sid], "TRADE_CONFIRM:#{trade_id}|#{sid}|true")
            MultiplayerDebug.info("TRADE", "Confirm from #{sid} in #{trade_id}")

            if t[:confirm][t[:a_sid]] && t[:confirm][t[:b_sid]]
              # Validate platinum balances before execution
              unless t[:platinum_locked]
                validation_result = platinum_validate_trade(trades, platinum_accounts, client_data, trade_id)
                unless validation_result[:success]
                  abort_trade(trades, sid_active_trade, sid_sockets, platinum_accounts, trade_id, validation_result[:reason])
                  next
                end
              end

              # Execute platinum transfer server-side BEFORE sending TRADE_EXECUTE
              transfer_result = platinum_execute_trade_transfer(trades, platinum_accounts, sid_sockets, trade_id)
              unless transfer_result[:success]
                abort_trade(trades, sid_active_trade, sid_sockets, platinum_accounts, trade_id, transfer_result[:reason])
                next
              end

              t[:state] = "executing"
              a_offer = MiniJSON.dump(t[:offers][t[:a_sid]] || {})
              b_offer = MiniJSON.dump(t[:offers][t[:b_sid]] || {})
              safe_send_sid(sid_sockets, t[:a_sid], "TRADE_EXECUTE:#{trade_id}|#{a_offer}|#{b_offer}")
              safe_send_sid(sid_sockets, t[:b_sid], "TRADE_EXECUTE:#{trade_id}|#{b_offer}|#{a_offer}")
              MultiplayerDebug.info("TRADE", "EXECUTE sent for #{trade_id} (platinum already transferred)")
            end
            next
          end


          if data.start_with?("TRADE_EXECUTE_OK:")
            trade_id = data.split(":", 2)[1].to_s.strip
            t = trades[trade_id]
            next if t.nil?
            t[:exec_ok][sid] = true
            if t[:exec_ok][t[:a_sid]] && t[:exec_ok][t[:b_sid]]
              safe_send_sid(sid_sockets, t[:a_sid], "TRADE_COMPLETE:#{trade_id}")
              safe_send_sid(sid_sockets, t[:b_sid], "TRADE_COMPLETE:#{trade_id}")
              MultiplayerDebug.info("TRADE", "COMPLETE #{trade_id}")
              sid_active_trade.delete(t[:a_sid]); sid_active_trade.delete(t[:b_sid])
              trades.delete(trade_id)
            end
            next
          end


          if data.start_with?("TRADE_EXECUTE_FAIL:")
            body = data.sub("TRADE_EXECUTE_FAIL:", "")
            trade_id, reason = body.split("|", 2)
            reason = (reason || "EXECUTION_FAILED").to_s
            abort_trade(trades, sid_active_trade, sid_sockets, platinum_accounts, trade_id, reason)
            next
          end


          # ===========================
          # === PvP: Commands =========
          # ===========================
          if data.start_with?("PVP_INVITE:")
            # Rate limit check (3 invites per second)
            unless ServerRateLimit.allow?(c, :PVP_INVITE)
              MultiplayerDebug.warn("PVP", "Rate limited PVP_INVITE from #{sid} (#{ServerRateLimit.current_rate(c, :PVP_INVITE)}/s)")
              safe_send(c, "PVP_ERROR:RATE_LIMIT")
              next
            end

            target_sid = data.sub("PVP_INVITE:", "").strip
            target_sock = sid_sockets[target_sid]

            if target_sock
              from_name = client_data[c] ? (client_data[c][:name] || "") : ""
              safe_send(target_sock, "PVP_INVITE:#{sid}|#{from_name}")
              safe_send(c, "PVP_INVITE_SENT:#{target_sid}")
              MultiplayerDebug.info("PVP", "Invite #{sid} -> #{target_sid}")
            else
              safe_send(c, "PVP_ERROR:TARGET_OFFLINE")
            end
            next
          end

          if data.start_with?("PVP_RESP:")
            # Rate limit check (3 responses per second)
            unless ServerRateLimit.allow?(c, :PVP_INVITE)
              MultiplayerDebug.warn("PVP", "Rate limited PVP_RESP from #{sid}")
              next
            end

            body = data.sub("PVP_RESP:", "")
            from_sid, response = body.split("|", 2)
            from_sock = sid_sockets[from_sid]

            if from_sock
              if response == "ACCEPT"
                safe_send(from_sock, "PVP_ACCEPTED:#{sid}")
                safe_send(c, "PVP_ACCEPTED:#{from_sid}")
                MultiplayerDebug.info("PVP", "Accepted by #{sid} for #{from_sid}")
              else
                safe_send(from_sock, "PVP_DECLINED:#{sid}")
                MultiplayerDebug.info("PVP", "Declined by #{sid} for #{from_sid}")
              end
            end
            next
          end

          if data.start_with?("PVP_SETTINGS_UPDATE:")
            body = data.sub("PVP_SETTINGS_UPDATE:", "")
            battle_id, json_settings = body.split("|", 2)

            # Broadcast to all other clients
            sid_sockets.each do |other_sid, other_sock|
              next if other_sid == sid
              safe_send(other_sock, data)
            end
            next
          end

          if data.start_with?("PVP_PARTY_SELECTION:")
            body = data.sub("PVP_PARTY_SELECTION:", "")
            battle_id, hex_indices = body.split("|", 2)

            # Store selection but don't echo (blind pick)
            # Note: Server doesn't need to persist this for Phase 1
            next
          end

          if data.start_with?("PVP_PARTY_PUSH:")
            body = data.sub("PVP_PARTY_PUSH:", "")
            battle_id, hex_party = body.split("|", 2)

            # Echo to all other clients
            sid_sockets.each do |other_sid, other_sock|
              next if other_sid == sid
              safe_send(other_sock, data)
            end
            next
          end

          if data.start_with?("PVP_START_BATTLE:")
            body = data.sub("PVP_START_BATTLE:", "")
            battle_id, json_settings = body.split("|", 2)

            # Echo to all other clients
            sid_sockets.each do |other_sid, other_sock|
              next if other_sid == sid
              safe_send(other_sock, data)
            end
            next
          end

          if data.start_with?("PVP_CANCEL:")
            battle_id = data.sub("PVP_CANCEL:", "").strip

            # Broadcast abort to all other clients
            sid_sockets.each do |other_sid, other_sock|
              next if other_sid == sid
              safe_send(other_sock, "PVP_ABORT:#{battle_id}|CANCELLED")
            end
            next
          end

          # PVP Battle Synchronization Messages (Phase 5)
          if data.start_with?("PVP_CHOICE:")
            # Echo action choices to all other clients
            sid_sockets.each do |other_sid, other_sock|
              next if other_sid == sid
              safe_send(other_sock, data)
            end
            next
          end

          if data.start_with?("PVP_RNG_SEED:")
            # Echo RNG seed to all other clients
            sid_sockets.each do |other_sid, other_sock|
              next if other_sid == sid
              safe_send(other_sock, data)
            end
            next
          end

          if data.start_with?("PVP_RNG_SEED_ACK:")
            # Echo acknowledgment to all other clients
            sid_sockets.each do |other_sid, other_sock|
              next if other_sid == sid
              safe_send(other_sock, data)
            end
            next
          end

          if data.start_with?("PVP_SWITCH:")
            # Echo switch choices to all other clients (Phase 6 - Switch Sync)
            sid_sockets.each do |other_sid, other_sock|
              next if other_sid == sid
              safe_send(other_sock, data)
            end
            next
          end

          if data.start_with?("PVP_FORFEIT:")
            # Echo forfeit to all other clients (ends battle immediately)
            sid_sockets.each do |other_sid, other_sock|
              next if other_sid == sid
              safe_send(other_sock, data)
            end
            next
          end

          # =========================================
          # === MULTIPLAYER SETTINGS SYNC ===
          # =========================================
          if data.start_with?("MP_SETTINGS_REQUEST:")
            # Forward to all other clients (target will filter by SID)
            sid_sockets.each do |other_sid, other_sock|
              next if other_sid == sid
              safe_send(other_sock, data)
            end
            next
          end

          if data.start_with?("MP_SETTINGS_RESPONSE:")
            # Forward to all clients (target will filter by their SID)
            sid_sockets.each do |other_sid, other_sock|
              next if other_sid == sid
              safe_send(other_sock, data)
            end
            next
          end

          if data.start_with?("MP_TIMEOUT_SETTING:")
            # Broadcast timeout setting to squad members
            squad_id = client_data[c][:squad_id]
            if squad_id && squads[squad_id]
              squads[squad_id].each do |member_sid|
                next if member_sid == sid
                member_sock = sid_sockets[member_sid]
                safe_send(member_sock, data) if member_sock
              end
            end
            next
          end

          # =========================================
          # === GTS: Commands (over existing TCP) ===
          # =========================================
          if data.start_with?("GTS:")
            begin
              body = data.sub("GTS:", "")
              obj  = MiniJSON.parse(body) || {}
            rescue => e
              MultiplayerDebug.warn("GTS", "Bad JSON from #{sid}: #{e.message}")
              safe_send(c, "GTS_ERR:" + MiniJSON.dump({ "action" => "UNKNOWN", "code" => "BAD_JSON", "msg" => "Invalid JSON" }))
              next
            end

            action = (obj["action"] || "").to_s.upcase
            payload= (obj["data"]   || {})
            uid    = (obj["uid"]    || "").to_s
            now    = gts_now_i

            ok = lambda do |act, pay, st|
              safe_send(c, "GTS_OK:" + MiniJSON.dump({ "action" => act, "payload" => pay, "new_rev" => st["rev"].to_i }))
            end
            err = lambda do |act, code, msg|
              safe_send(c, "GTS_ERR:" + MiniJSON.dump({ "action" => act, "code" => code, "msg" => msg }))
            end

            GTS_MUTEX.synchronize do
              # Auto-register using platinum UUID (no manual registration needed)
              if action == "GTS_REGISTER"
                platinum_uuid = client_data[c][:platinum_uuid]
                if !platinum_uuid
                  err.call(action, "NO_PLATINUM_AUTH", "Platinum account required for GTS")
                  next
                end

                name = (payload["name"] || find_name_by_sid(client_data, sid) || "Player").to_s
                now = gts_now_i

                # Create or update user record (keyed by platinum UUID)
                if !gts_state["users"][platinum_uuid]
                  gts_state["users"][platinum_uuid] = {
                    "name"       => name,
                    "created_at" => now,
                    "last_seen"  => now,
                    "last_sid"   => sid
                  }
                  MultiplayerDebug.info("GTS", "New user registered: #{name} (UUID: #{platinum_uuid[0..7]}...)")
                else
                  gts_state["users"][platinum_uuid]["name"] = name
                  gts_state["users"][platinum_uuid]["last_seen"] = now
                  gts_state["users"][platinum_uuid]["last_sid"] = sid
                  MultiplayerDebug.info("GTS", "User reconnected: #{name} (UUID: #{platinum_uuid[0..7]}...)")
                end

                uuid_to_sid_gts[platinum_uuid] = sid
                sid_to_uuid_gts[sid] = platinum_uuid
                gts_bump_rev!(gts_state)
                gts_save!(gts_state)
                # Send full UUID to client for ownership checks
                ok.call(action, { "uuid" => platinum_uuid }, gts_state)
                next
              end

              # Get platinum UUID for this session
              platinum_uuid = sid_to_uuid_gts[sid] || client_data[c][:platinum_uuid]
              if platinum_uuid
                sid_to_uuid_gts[sid] = platinum_uuid
                uuid_to_sid_gts[platinum_uuid] = sid
              end

              case action
              when "GTS_SNAPSHOT"
                since_rev = payload["since_rev"]
                snap = gts_snapshot(gts_state, since_rev)
                ok.call(action, snap, gts_state)

              when "GTS_LIST"
                # Require platinum authentication
                unless platinum_uuid
                  err.call(action, "NO_AUTH", "Platinum account required"); next
                end

                # Auto-register user if not exists
                if !gts_state["users"][platinum_uuid]
                  now = gts_now_i
                  name = find_name_by_sid(client_data, sid) || "Player"
                  gts_state["users"][platinum_uuid] = {
                    "name"       => name,
                    "created_at" => now,
                    "last_seen"  => now,
                    "last_sid"   => sid
                  }
                  MultiplayerDebug.info("GTS", "Auto-registered #{name} (UUID: #{platinum_uuid[0..7]}...)")
                end

                # Check listing limit (10 active listings per user)
                user_listing_count = gts_state["listings"].count { |l| l["seller"] == platinum_uuid }
                if user_listing_count >= 10
                  err.call(action, "LISTING_LIMIT", "You can only have 10 active listings. Cancel or sell some first."); next
                end

                kind  = (payload["kind"] || "").to_s
                price = (payload["price_money"] || 0).to_i
                if price <= 0
                  err.call(action, "BAD_REQUEST", "Price must be > 0"); next
                end

                now = gts_now_i
                listing = { "id" => nil, "seller" => platinum_uuid, "kind" => kind, "price" => price, "created_at" => now, "locked" => false, "expires_at" => now + (7 * 24 * 60 * 60) }
                escrow_payload = nil

                if kind == "item"
                  item_id = (payload["item_id"] || "").to_s
                  qty     = (payload["item_qty"] || 0).to_i
                  if item_id.empty? || qty <= 0
                    err.call(action, "BAD_REQUEST", "Missing item_id/qty"); next
                  end
                  listing["item_id"] = item_id
                  listing["qty"]     = qty
                  escrow_payload = { "kind" => "item", "payload" => { "item_id" => item_id, "qty" => qty } }
                elsif kind == "pokemon"
                  pj = payload["pokemon_json"]
                  if !pj || pj.to_s.size < 4
                    err.call(action, "BAD_REQUEST", "Missing pokemon_json"); next
                  end
                  listing["pokemon_json"] = pj
                  escrow_payload = { "kind" => "pokemon", "payload" => pj }
                else
                  err.call(action, "BAD_REQUEST", "Unknown kind"); next
                end

                lid, gts_listing_seq = gts_new_lid(gts_listing_seq)
                listing["id"] = lid
                gts_state["listings"] << listing
                gts_state["escrow"][lid] = { "seller" => platinum_uuid, "held" => escrow_payload, "created_at" => now }
                gts_state["users"][platinum_uuid]["last_seen"] = now
                gts_state["users"][platinum_uuid]["last_sid"]  = sid

                gts_bump_rev!(gts_state)
                saved = gts_save!(gts_state)
                if saved
                  ok.call(action, { "listing" => listing }, gts_state)
                else
                  err.call(action, "SAVE_FAILED", "Could not save market.")
                end

              when "GTS_CANCEL"
                lid = (payload["listing_id"] || "").to_s
                l   = gts_state["listings"].find { |x| x["id"] == lid }
                if !l
                  err.call(action, "LISTING_GONE", "Already gone"); next
                end
                if l["seller"] != platinum_uuid
                  err.call(action, "NOT_OWNER", "Cannot cancel others' listing"); next
                end
                if l["locked"]
                  err.call(action, "ESCROW_ERROR", "Listing currently locked"); next
                end

                escrow = gts_state["escrow"][lid]
                if !escrow || !escrow["held"]
                  err.call(action, "ESCROW_ERROR", "Missing escrow payload"); next
                end

                l["locked"] = true
                gts_bump_rev!(gts_state)
                gts_save!(gts_state)

                seller_sid = uuid_to_sid_gts[platinum_uuid]
                if !seller_sid || !sid_sockets[seller_sid]
                  err.call(action, "UNAVAILABLE", "Seller offline; try again while online")
                  next
                end

                ret_payload = { "listing_id" => lid, "kind" => escrow["held"]["kind"], "payload" => escrow["held"]["payload"] }
                safe_send_sid(sid_sockets, seller_sid, "GTS_RETURN:" + MiniJSON.dump(ret_payload))
                ok.call(action, { "listing_id" => lid, "returning" => true }, gts_state)

              when "GTS_BUY"
                lid = (payload["listing_id"] || "").to_s
                l = gts_state["listings"].find { |x| x["id"] == lid }
                if !l
                  err.call(action, "LISTING_GONE", "Already gone"); next
                end
                if l["locked"]
                  err.call(action, "BAD_REQUEST", "Listing is busy"); next
                end

                # Get buyer's platinum UUID
                buyer_uuid = client_data[c][:platinum_uuid]
                if !buyer_uuid
                  err.call(action, "NOT_AUTHENTICATED", "Platinum account required"); next
                end

                # Validate and deduct platinum from buyer
                price_money = l["price"].to_i
                buyer_balance = platinum_get_balance(platinum_accounts, buyer_uuid)
                if buyer_balance < price_money
                  err.call(action, "INSUFFICIENT_PLATINUM", "Not enough platinum"); next
                end

                # Deduct platinum from buyer
                success = platinum_set_balance(platinum_accounts, buyer_uuid, buyer_balance - price_money)
                if !success
                  err.call(action, "PLATINUM_ERROR", "Failed to deduct platinum"); next
                end
                platinum_save!(platinum_accounts)
                MultiplayerDebug.info("GTS", "Deducted #{price_money} Pt from buyer #{sid} (UUID: #{buyer_uuid[0..7]}..., new balance: #{buyer_balance - price_money} Pt)")

                l["locked"] = true
                gts_bump_rev!(gts_state)
                gts_save!(gts_state)

                buyer_sid   = sid
                seller_uid  = l["seller"]
                held        = gts_state["escrow"][lid] && gts_state["escrow"][lid]["held"]
                if !held
                  # Rollback platinum deduction
                  platinum_set_balance(platinum_accounts, buyer_uuid, buyer_balance)
                  platinum_save!(platinum_accounts)
                  l["locked"] = false
                  gts_bump_rev!(gts_state)
                  gts_save!(gts_state)
                  err.call(action, "ESCROW_ERROR", "Missing escrow payload")
                  next
                end

                exec_payload = { "listing_id" => lid, "kind" => held["kind"], "payload" => held["payload"], "price" => price_money, "seller_uid" => seller_uid }
                safe_send_sid(sid_sockets, buyer_sid, "GTS_EXECUTE:" + MiniJSON.dump(exec_payload))
                ok.call(action, { "listing_id" => lid, "listing" => l, "buyer" => buyer_uuid }, gts_state)

              else
                err.call(action, "BAD_REQUEST", "Unknown action")
              end
            end
            next
          end


          if data.start_with?("GTS_EXECUTE_OK:")
            lid = data.split(":",2)[1].to_s.strip
            GTS_MUTEX.synchronize do
              l = gts_state["listings"].find { |x| x["id"] == lid }
              escrow = gts_state["escrow"][lid]
              if l && escrow
                seller_uuid = l["seller"]  # seller is now platinum UUID directly
                price       = l["price"].to_i

                # Credit platinum to seller's persistent account (works even if offline)
                seller_balance = platinum_get_balance(platinum_accounts, seller_uuid)
                platinum_set_balance(platinum_accounts, seller_uuid, seller_balance + price)
                platinum_save!(platinum_accounts)
                MultiplayerDebug.info("GTS", "SALE #{lid} complete; credited #{price} Pt to seller (UUID: #{seller_uuid[0..7]}..., new balance: #{seller_balance + price} Pt)")

                gts_state["listings"].delete(l)
                gts_state["escrow"].delete(lid)
                gts_bump_rev!(gts_state)
                gts_save!(gts_state)
              else
                MultiplayerDebug.warn("GTS", "EXECUTE_OK for missing listing #{lid}")
              end
            end
            next
          end

          if data.start_with?("GTS_RETURN_OK:")
            lid = data.split(":",2)[1].to_s.strip
            GTS_MUTEX.synchronize do
              l = gts_state["listings"].find { |x| x["id"] == lid }
              if l
                gts_state["listings"].delete(l)
                gts_state["escrow"].delete(lid)
                gts_bump_rev!(gts_state)
                gts_save!(gts_state)
                MultiplayerDebug.info("GTS", "RETURN #{lid} complete; listing removed.")
              else
                MultiplayerDebug.warn("GTS", "RETURN_OK for missing listing #{lid}")
              end
            end
            next
          end


          if data.start_with?("GTS_RETURN_FAIL:")
            body   = data.sub("GTS_RETURN_FAIL:", "")
            lid, reason = body.split("|", 2)
            reason = (reason || "FAIL").to_s
            GTS_MUTEX.synchronize do
              l = gts_state["listings"].find { |x| x["id"] == lid }
              if l
                l["locked"] = false
                gts_bump_rev!(gts_state)
                gts_save!(gts_state)
                MultiplayerDebug.warn("GTS", "RETURN #{lid} failed: #{reason}; listing unlocked")
              end
            end
            next
          end


          if data.start_with?("GTS_EXECUTE_FAIL:")
            body = data.sub("GTS_EXECUTE_FAIL:", "")
            lid, reason = body.split("|", 2)
            reason = (reason || "FAIL").to_s
            GTS_MUTEX.synchronize do
              l = gts_state["listings"].find { |x| x["id"] == lid }
              if l
                l["locked"] = false
                gts_bump_rev!(gts_state)
                gts_save!(gts_state)
                MultiplayerDebug.warn("GTS", "SALE #{lid} failed: #{reason}; unlocked")
              end
            end
            next
          end

          # ============================================
          # === Wild Battle Platinum Rewards =========
          # ============================================
          if data.start_with?("WILD_PLATINUM:")
            begin
              body = data.sub("WILD_PLATINUM:", "")
              payload = MiniJSON.parse(body) || {}

              wild_species = payload["wild_species"]
              wild_level = payload["wild_level"].to_i
              wild_catch_rate = payload["wild_catch_rate"].to_i
              wild_stage = payload["wild_stage"].to_i
              active_battler_levels = payload["active_battler_levels"]
              active_battler_stages = payload["active_battler_stages"]
              battler_index = payload["battler_index"].to_i
              battle_id = payload["battle_id"]
              is_coop = payload["is_coop"]

              # Validation
              unless wild_species && wild_level.between?(1, 100) && wild_stage.between?(1, 3)
                safe_send(c, "WILD_PLAT_ERR:Invalid wild Pokemon data")
                next
              end

              unless active_battler_levels.is_a?(Array) && active_battler_stages.is_a?(Array)
                safe_send(c, "WILD_PLAT_ERR:Invalid battler data")
                next
              end

              unless active_battler_levels.length == active_battler_stages.length && active_battler_levels.length > 0
                safe_send(c, "WILD_PLAT_ERR:Battler data mismatch")
                next
              end

              # Deduplication: Check if this exact wild Pokemon was already reported recently BY THIS PLAYER
              # Include SID in dedup key so each player can report independently (for coop battles)
              # Use species:level:battler_index:sid:timestamp (rounded to second) as dedup key
              now = Time.now.to_i
              dedupe_key = "#{wild_species}:#{wild_level}:#{battler_index}:#{sid}:#{now}"

              # Clean old dedupe entries (older than 5 seconds)
              wild_platinum_dedupe.delete_if { |key, ts| now - ts > 5 }

              # Check if already processed
              if wild_platinum_dedupe[dedupe_key]
                MultiplayerDebug.info("WILD-PLAT", "#{sid} duplicate report - sending cached response (#{wild_species} Lv#{wild_level})")
                # Send response with 0 reward (already credited to first reporter)
                # Get current balance to send back
                platinum_uuid = client_data[c][:platinum_uuid]
                if platinum_uuid
                  current_balance = platinum_get_balance(platinum_accounts, platinum_uuid)
                  safe_send(c, "WILD_PLAT_OK:0:#{current_balance}")
                else
                  safe_send(c, "WILD_PLAT_OK:0:0")
                end
                next
              end

              # Mark as processed
              wild_platinum_dedupe[dedupe_key] = now

              # Rate limit: max 12 per minute
              wild_platinum_timestamps[sid] ||= []
              wild_platinum_timestamps[sid].reject! { |ts| now - ts > 60 }

              if wild_platinum_timestamps[sid].length >= 12
                safe_send(c, "WILD_PLAT_ERR:Rate limit exceeded")
                next
              end

              wild_platinum_timestamps[sid] << now

              # Get or create platinum account
              platinum_uuid = client_data[c][:platinum_uuid]

              # Auto-create platinum account if doesn't exist
              unless platinum_uuid
                # Generate new platinum account
                uuid = platinum_generate_uuid
                token = platinum_generate_token(uuid)
                tid = client_data[c][:tid] || 0
                name = client_data[c][:name] || "Player"

                PLATINUM_MUTEX.synchronize do
                  platinum_accounts[uuid] = {
                    "tid" => tid,
                    "name" => name,
                    "platinum" => 0,
                    "token" => token
                  }
                  token_to_uuid[token] = uuid
                end

                platinum_save!(platinum_accounts)
                client_data[c][:platinum_uuid] = uuid
                safe_send(c, "AUTH_TOKEN:#{token}")
                safe_send(c, "PLATINUM_UUID:#{uuid}")
                MultiplayerDebug.info("WILD-PLAT", "Auto-created platinum account for #{sid} (UUID: #{uuid[0..7]}...)")
                platinum_uuid = uuid
              end

              # Calculate platinum reward (all data from client)
              reward = calculate_wild_platinum(wild_level, wild_catch_rate, wild_stage, active_battler_levels, active_battler_stages)

              # Credit platinum
              old_balance = platinum_get_balance(platinum_accounts, platinum_uuid)
              new_balance = old_balance + reward
              platinum_set_balance(platinum_accounts, platinum_uuid, new_balance)
              platinum_save!(platinum_accounts)

              # Send success response with reward AND new total balance
              safe_send(c, "WILD_PLAT_OK:#{reward}:#{new_balance}")
              MultiplayerDebug.info("WILD-PLAT", "#{sid} earned #{reward} platinum (#{wild_species} Lv#{wild_level}), new balance: #{new_balance}")

            rescue => e
              MultiplayerDebug.warn("WILD-PLAT", "Error processing #{sid}: #{e.message}")
              safe_send(c, "WILD_PLAT_ERR:#{e.message}")
            end
            next
          end

          # ===========================
          # === CO-OP party exchange ===
          # ===========================
          # Initiator (or anyone) can nudge a immediate push-now round
          if data.start_with?("COOP_PARTY_PUSH_NOW")
            sq_id = member_squad[sid]
            broadcast_coop_push_now_to_squad(squads, member_squad, sid_sockets, client_data, sq_id) if sq_id
            next
          end


          if data.start_with?("COOP_PARTY_PUSH_HEX:")
            hex = data.sub("COOP_PARTY_PUSH_HEX:", "")
            recips = coop_recipients_for(sid, squads, member_squad, client_data)
            if recips.empty?
              MultiplayerDebug.info("COOP", "No eligible recipients for party(hex) from #{sid}")
            else
              recips.each { |rsid| safe_send_sid(sid_sockets, rsid, "FROM:#{sid}|COOP_PARTY_PUSH_HEX:#{hex}") }
              MultiplayerDebug.info("COOP", "Forwarded party(hex) from #{sid} -> #{recips.join('/')} hex_len=#{hex.length}")
            end
            next
          end

          # ======================================
          # === MODULE 2: Targeted party request
          # ======================================
          if data.start_with?("COOP_PARTY_REQ:")
            target_sid = data.sub("COOP_PARTY_REQ:", "")
            # Only relay if target is in same squad
            recips = coop_recipients_for(sid, squads, member_squad, client_data)
            if recips.include?(target_sid)
              safe_send_sid(sid_sockets, target_sid, "FROM:#{sid}|COOP_PARTY_REQ:#{sid}")
              MultiplayerDebug.info("COOP", "[PARTY-REQ-RELAY] Relayed party request from #{sid} -> #{target_sid}")
            else
              MultiplayerDebug.warn("COOP", "[PARTY-REQ-BLOCK] #{target_sid} not eligible recipient for #{sid}")
            end
            next
          end

          if data.start_with?("COOP_PARTY_RESP:")
            # Format: COOP_PARTY_RESP:<target_sid>|<hex_data>
            rest = data.sub("COOP_PARTY_RESP:", "")
            parts = rest.split("|", 2)
            if parts.length == 2
              target_sid = parts[0]
              hex = parts[1]
              # Only relay if target is in same squad
              recips = coop_recipients_for(sid, squads, member_squad, client_data)
              if recips.include?(target_sid)
                safe_send_sid(sid_sockets, target_sid, "FROM:#{sid}|COOP_PARTY_RESP:#{target_sid}|#{hex}")
                MultiplayerDebug.info("COOP", "[PARTY-RESP-RELAY] Relayed party response from #{sid} -> #{target_sid} (hex_len=#{hex.length})")
              else
                MultiplayerDebug.warn("COOP", "[PARTY-RESP-BLOCK] #{target_sid} not eligible recipient for #{sid}")
              end
            end
            next
          end


          # --- FROM:SID|... wrapper passthrough (generic) ---
          if data.start_with?("FROM:")
            begin
              from_sid, payload = data.split("|", 2)
              sid_from = from_sid.split(":", 2)[1]
              next if sid_from.nil?
              # Nothing to do here at server — this path is for client-side helpers
            rescue => e
              MultiplayerDebug.error("C-FROMERR", "Failed to parse FROM wrapper: #{e.message}")
            end
            next
          end


          # ======================================
          # === CHAT SYSTEM ===
          # ======================================

          # --- CHAT: Global ---
          if data.start_with?("CHAT_GLOBAL:")
            # Rate limit check
            now = Time.now
            last = chat_last_message[c]
            if last && (now - last) < CHAT_RATE_LIMIT
              MultiplayerDebug.warn("CHAT", "#{sid} rate limited (global)")
              next
            end
            chat_last_message[c] = now

            text = data.sub("CHAT_GLOBAL:", "").strip
            text = text.gsub(/[\r\n\x00|]/, "").strip[0..149]  # Sanitize
            next if text.empty?

            # Log to file
            begin
              entry = "Global|#{sid}|#{client_data[c][:name]}|#{text}\n"
              File.open(CHAT_LOG_FILE, "a") { |f| f.write(entry) }
            rescue => e
              MultiplayerDebug.error("CHAT", "Log write failed: #{e.message}")
            end

            # Broadcast to all clients
            msg = "CHAT_GLOBAL:#{sid}:#{client_data[c][:name]}:#{text}"
            clients.each { |cl| safe_send(cl, msg) }

            MultiplayerDebug.info("CHAT", "Global from #{sid}: #{text[0..50]}...")
            next
          end

          # --- CHAT: Trade ---
          if data.start_with?("CHAT_TRADE:")
            # Rate limit check
            now = Time.now
            last = chat_last_message[c]
            if last && (now - last) < CHAT_RATE_LIMIT
              MultiplayerDebug.warn("CHAT", "#{sid} rate limited (trade)")
              next
            end
            chat_last_message[c] = now

            text = data.sub("CHAT_TRADE:", "").strip
            text = text.gsub(/[\r\n\x00|]/, "").strip[0..149]  # Sanitize
            next if text.empty?

            # Log to file
            begin
              entry = "Trade|#{sid}|#{client_data[c][:name]}|#{text}\n"
              File.open(CHAT_LOG_FILE, "a") { |f| f.write(entry) }
            rescue => e
              MultiplayerDebug.error("CHAT", "Log write failed: #{e.message}")
            end

            # Broadcast to all clients
            msg = "CHAT_TRADE:#{sid}:#{client_data[c][:name]}:#{text}"
            clients.each { |cl| safe_send(cl, msg) }

            MultiplayerDebug.info("CHAT", "Trade from #{sid}: #{text[0..50]}...")
            next
          end

          # --- CHAT: Squad ---
          if data.start_with?("CHAT_SQUAD:")
            # Rate limit check
            now = Time.now
            last = chat_last_message[c]
            if last && (now - last) < CHAT_RATE_LIMIT
              MultiplayerDebug.warn("CHAT", "#{sid} rate limited (squad)")
              next
            end
            chat_last_message[c] = now

            # Verify sender is in squad
            squad_id = member_squad[sid]
            next unless squad_id

            text = data.sub("CHAT_SQUAD:", "").strip
            text = text.gsub(/[\r\n\x00|]/, "").strip[0..149]  # Sanitize
            next if text.empty?

            # Broadcast to squad members only (NOT logged)
            squad = squads[squad_id]
            msg = "CHAT_SQUAD:#{sid}:#{client_data[c][:name]}:#{text}"
            squad[:members].each do |member_sid|
              member_socket = sid_sockets[member_sid]
              safe_send(member_socket, msg) if member_socket
            end

            MultiplayerDebug.info("CHAT", "Squad from #{sid}: #{text[0..50]}...")
            next
          end

          # --- CHAT: PM ---
          if data.start_with?("CHAT_PM:")
            # Rate limit check
            now = Time.now
            last = chat_last_message[c]
            if last && (now - last) < CHAT_RATE_LIMIT
              MultiplayerDebug.warn("CHAT", "#{sid} rate limited (PM)")
              next
            end
            chat_last_message[c] = now

            parts = data.sub("CHAT_PM:", "").split(":", 2)
            target_sid = parts[0]
            text = parts[1].to_s.strip
            text = text.gsub(/[\r\n\x00|]/, "").strip[0..149]  # Sanitize
            next if text.empty?

            # Check if receiver has blocked sender (individually or block all)
            if (chat_block_lists[target_sid] && chat_block_lists[target_sid].include?(sid)) || chat_block_all[target_sid]
              safe_send(c, "CHAT_BLOCKED:#{target_sid}")
              MultiplayerDebug.info("CHAT", "PM #{sid} -> #{target_sid} blocked")
              next
            end

            # Check receiver PM tab count
            chat_pm_tab_count[target_sid] ||= 0
            if chat_pm_tab_count[target_sid] >= 4
              safe_send(c, "CHAT_PM_ERROR:Receiver has too many opened tabs.")
              MultiplayerDebug.info("CHAT", "PM #{sid} -> #{target_sid} rejected (tab limit)")
              next
            end

            # Increment receiver tab count (track unique senders)
            # Note: Simplified - in production, track per sender-receiver pair
            chat_pm_tab_count[target_sid] += 1 if chat_pm_tab_count[target_sid] == 0

            # Send to receiver
            msg = "CHAT_PM:#{sid}:#{client_data[c][:name]}:#{text}"
            target_socket = sid_sockets[target_sid]
            if target_socket
              safe_send(target_socket, msg)

              # Echo back to sender (for their PM tab)
              safe_send(c, msg)

              MultiplayerDebug.info("CHAT", "PM #{sid} -> #{target_sid}: #{text[0..50]}...")
            else
              safe_send(c, "CHAT_PM_ERROR:Receiver offline.")
            end

            next
          end

          # --- CHAT: Block ---
          if data.start_with?("CHAT_BLOCK:")
            blocked_sid = data.sub("CHAT_BLOCK:", "").strip

            chat_block_lists[sid] ||= []

            if chat_block_lists[sid].include?(blocked_sid)
              safe_send(c, "CHAT_BLOCK_CONFIRM")  # Already blocked
            else
              chat_block_lists[sid] << blocked_sid

              # Notify blocked user to close PM tab
              blocked_socket = sid_sockets[blocked_sid]
              safe_send(blocked_socket, "CHAT_BLOCKED:#{sid}") if blocked_socket
            end

            MultiplayerDebug.info("CHAT", "#{sid} blocked #{blocked_sid}")
            next
          end

          # --- CHAT: Unblock ---
          if data.start_with?("CHAT_UNBLOCK:")
            unblocked_sid = data.sub("CHAT_UNBLOCK:", "").strip

            chat_block_lists[sid] ||= []
            chat_block_lists[sid].delete(unblocked_sid)

            MultiplayerDebug.info("CHAT", "#{sid} unblocked #{unblocked_sid}")
            next
          end

          # --- CHAT: Block All ---
          if data == "CHAT_BLOCK_ALL"
            chat_block_all[sid] = true
            MultiplayerDebug.info("CHAT", "#{sid} enabled block all")
            next
          end

          # --- CHAT: Unblock All ---
          if data == "CHAT_UNBLOCK_ALL"
            chat_block_all[sid] = false
            chat_block_lists[sid] = []
            MultiplayerDebug.info("CHAT", "#{sid} disabled block all and cleared block list")
            next
          end

          if data == "REQ_DETAILS"
            next
          end

          # ===========================
          # === Settings Sync ==========
          # ===========================
          # MP_SETTINGS_REQUEST:<target_sid>|<sync_type>
          # Routes settings request to target player
          if data.start_with?("MP_SETTINGS_REQUEST:")
            body = data.sub("MP_SETTINGS_REQUEST:", "")
            target_sid, sync_type = body.split("|", 2)
            target_sid = target_sid.to_s.strip
            sync_type = (sync_type || "MP").to_s.strip

            target_sock = sid_sockets[target_sid]
            if target_sock
              from_name = client_data[c] ? (client_data[c][:name] || "") : ""
              # Send to target: MP_SETTINGS_REQUEST:<requester_sid>|<requester_name>|<sync_type>
              safe_send(target_sock, "MP_SETTINGS_REQUEST:#{sid}|#{from_name}|#{sync_type}")
              safe_send(c, "MP_SETTINGS_REQUEST_SENT:#{target_sid}")
              MultiplayerDebug.info("SETTINGS", "Settings request #{sid} -> #{target_sid} (#{sync_type})")
            else
              safe_send(c, "MP_SETTINGS_ERROR:TARGET_OFFLINE")
              MultiplayerDebug.warn("SETTINGS", "Settings request failed - target #{target_sid} offline")
            end
            next
          end

          # MP_SETTINGS_RESPONSE:<target_sid>|<sync_type>|<json_data>
          # Routes settings response back to requester
          if data.start_with?("MP_SETTINGS_RESPONSE:")
            body = data.sub("MP_SETTINGS_RESPONSE:", "")
            # Split only first two pipes to preserve JSON data
            parts = body.split("|", 3)
            target_sid = parts[0].to_s.strip
            sync_type = parts[1].to_s.strip
            json_data = parts[2].to_s

            target_sock = sid_sockets[target_sid]
            if target_sock
              # Send to requester: MP_SETTINGS_RESPONSE:<sender_sid>|<sync_type>|<json_data>
              safe_send(target_sock, "MP_SETTINGS_RESPONSE:#{sid}|#{sync_type}|#{json_data}")
              MultiplayerDebug.info("SETTINGS", "Settings response #{sid} -> #{target_sid} (#{sync_type})")
            else
              MultiplayerDebug.warn("SETTINGS", "Settings response failed - target #{target_sid} offline")
            end
            next
          end


          MultiplayerDebug.info("GENERIC", "From #{sid}: #{data}")
          safe_broadcast(clients, c, "FROM:#{sid}|#{data}")

        else
          # Client disconnected cleanly
          sid = (client_data[c] ? client_data[c][:id] : "SID?").to_s.strip
          puts "[Server] Client #{sid} disconnected."
          MultiplayerDebug.warn("001", "Client #{sid} disconnected.")

          pending_invites.delete_if { |to_sid, inv| inv[:from_sid] == sid || to_sid == sid }

          if sid_active_trade[sid]
            abort_trade(trades, sid_active_trade, sid_sockets, platinum_accounts, sid_active_trade[sid], "PARTY_DISCONNECT")
          end


          # Clean up GTS session tracking
          uuid = sid_to_uuid_gts.delete(sid)
          uuid_to_sid_gts.delete(uuid) if uuid

          begin
            sid_str = sid

            # === MODULE 3: Always broadcast disconnect to squad members ===
            # Don't check busy flag - let client decide if they're in a coop battle
            cdata = client_data[c]
            sq_id = member_squad[sid_str]
            if sq_id && squads[sq_id]
              # Get player name for abort reason
              player_name = cdata ? (cdata[:name] || sid_str) : sid_str
              abort_reason = "Player '#{player_name}' disconnected"
              busy_status = cdata ? cdata[:busy].to_i : 0

              MultiplayerDebug.warn("COOP", "[DISCONNECT] #{sid} disconnected (busy=#{busy_status})")

              # Broadcast abort to all squad members
              squad_members = squads[sq_id][:members] || []
              squad_members.each do |member_sid|
                next if member_sid == sid_str  # Don't send to disconnected player
                # Broadcast to all squad members - they'll figure out if it applies to their battle
                safe_send_sid(sid_sockets, member_sid, "FROM:#{sid}|COOP_BATTLE_ABORT:#{sid}|#{abort_reason}")
                MultiplayerDebug.info("COOP", "[ABORT-BROADCAST] Sent disconnect notice to #{member_sid} (reason: #{abort_reason})")
              end
            end

            sq_id = member_squad[sid_str]
            if sq_id && squads[sq_id]
              squads[sq_id][:members].delete(sid_str)
              member_squad.delete(sid_str)
              if squads[sq_id][:leader] == sid_str && squads[sq_id][:members].any?
                new_leader = squads[sq_id][:members].first
                squads[sq_id][:leader] = new_leader
                MultiplayerDebug.info("SQUAD", "Auto-transferred leadership (disconnect) in squad #{sq_id} to #{new_leader}")
              end
              if squads[sq_id][:members].empty?
                squads.delete(sq_id)
                MultiplayerDebug.info("SQUAD", "Disbanded squad #{sq_id} (leader or last member disconnected)")
              else
                # CRITICAL: Don't broadcast squad state if any remaining members are in battle
                # This prevents crashing clients who are in battle scenes
                any_member_busy = squads[sq_id][:members].any? do |member_sid|
                  member_socket = sid_sockets[member_sid]
                  member_socket && client_data[member_socket] && client_data[member_socket][:busy].to_i == 1
                end

                if any_member_busy
                  MultiplayerDebug.warn("SQUAD", "Skipping squad state broadcast for squad #{sq_id} (members in battle)")
                else
                  broadcast_squad_state_to_members(squads, member_squad, sid_sockets, client_data, sq_id)
                end
              end
            end
          rescue => e
            MultiplayerDebug.error("SQUAD", "Disconnect cleanup error for #{sid}: #{e.message}")
          end


          clients.delete(c)
          sid_sockets.delete(sid)
          client_ids.delete(c)
          client_data.delete(c)
          ServerRateLimit.remove_client(c)  # Clean up rate limit tracking

          # Chat system cleanup
          chat_last_message.delete(c)
          chat_pm_tab_count.delete(sid)
          chat_block_lists.delete(sid)

          c.close rescue nil
        end
      end
    rescue => e
      sid = client_data[c] ? client_data[c][:id] : "SID?"
      MultiplayerDebug.error("005", "Client #{sid} error: #{e.message}")

      pending_invites.delete_if { |to_sid, inv| inv[:from_sid] == sid || to_sid == sid }

      if sid_active_trade[sid]
        abort_trade(trades, sid_active_trade, sid_sockets, platinum_accounts, sid_active_trade[sid], "PARTY_ERROR")
      end

      # Clean up GTS session tracking
      uuid = sid_to_uuid_gts.delete(sid)
      uuid_to_sid_gts.delete(uuid) if uuid

      begin
        sid_str = (client_data[c] && client_data[c][:id]) ? client_data[c][:id].to_s.strip : nil
        if sid_str
          # === MODULE 3: Always broadcast disconnect to squad members (error path) ===
          # Don't check busy flag - let client decide if they're in a coop battle
          cdata = client_data[c]
          sq_id = member_squad[sid_str]
          if sq_id && squads[sq_id]
            # Get player name for abort reason
            player_name = cdata ? (cdata[:name] || sid_str) : sid_str
            abort_reason = "Player '#{player_name}' disconnected"
            busy_status = cdata ? cdata[:busy].to_i : 0

            MultiplayerDebug.warn("COOP", "[DISCONNECT-ERR] #{sid_str} disconnected (busy=#{busy_status}, error path)")

            # Broadcast abort to all squad members
            squad_members = squads[sq_id][:members] || []
            squad_members.each do |member_sid|
              next if member_sid == sid_str  # Don't send to disconnected player
              safe_send_sid(sid_sockets, member_sid, "FROM:#{sid_str}|COOP_BATTLE_ABORT:#{sid_str}|#{abort_reason}")
              MultiplayerDebug.info("COOP", "[ABORT-BROADCAST-ERR] Sent disconnect notice to #{member_sid} (reason: #{abort_reason})")
            end
          end

          sq_id = member_squad[sid_str]
          if sq_id && squads[sq_id]
            squads[sq_id][:members].delete(sid_str)
            member_squad.delete(sid_str)
            if squads[sq_id][:leader] == sid_str && squads[sq_id][:members].any?
              new_leader = squads[sq_id][:members].first
              squads[sq_id][:leader] = new_leader
              MultiplayerDebug.info("SQUAD", "Auto-transferred leadership (error) in squad #{sq_id} to #{new_leader}")
            end
            if squads[sq_id][:members].empty?
              squads.delete(sq_id)
              MultiplayerDebug.info("SQUAD", "Disbanded squad #{sq_id} (error path)")
            else
              # CRITICAL: Don't broadcast squad state if any remaining members are in battle
              # This prevents crashing clients who are in battle scenes
              any_member_busy = squads[sq_id][:members].any? do |member_sid|
                member_socket = sid_sockets[member_sid]
                member_socket && client_data[member_socket] && client_data[member_socket][:busy].to_i == 1
              end

              if any_member_busy
                MultiplayerDebug.warn("SQUAD", "Skipping squad state broadcast for squad #{sq_id} (members in battle, error path)")
              else
                broadcast_squad_state_to_members(squads, member_squad, sid_sockets, client_data, sq_id)
              end
            end
          end

        end
      rescue => e2
        MultiplayerDebug.error("SQUAD", "Error cleanup for #{sid} failed: #{e2.message}")
      end

      clients.delete(c)
      sid_sockets.delete(sid)
      client_ids.delete(c)
      client_data.delete(c)
      ServerRateLimit.remove_client(c)
      c.close rescue nil
    end
  end

  # --- Finalize pending detail sweeps ---
  begin
    now = Time.now
    pending_details.dup.each do |requester, pend|
      if (now - pend[:started]) >= pend[:timeout]
        lines =
          if pend[:data].any?
            pend[:data].map { |sid, h| "#{sid} - #{h[:name]}" }
          else
            client_data.values.map { |info| "#{info[:id]} - #{info[:name]}" }
          end

        response = "PLAYERS:" + lines.join(",")
        safe_send(requester, response)
        MultiplayerDebug.info("REQPLAY", "Completed sweep -> #{response}")
        pending_details.delete(requester)
      end
    end
  rescue => e
    MultiplayerDebug.error("REQPLAY", "Finalize sweep failed: #{e.message}")
  end

  # --- Trade inactivity timeout sweep ---
  begin
    now = Time.now
    trades.dup.each do |tid, t|
      next unless t[:t_last]
      if (now - t[:t_last]) > TRADE_TIMEOUT_SEC
        abort_trade(trades, sid_active_trade, sid_sockets, platinum_accounts, tid, "TIMEOUT")
      end
    end
  rescue => e
    MultiplayerDebug.error("TRADE", "Timeout sweep failed: #{e.message}")
  end

  # --- Monitor network connection (VPN or VPS) ---
  begin
    now = Time.now
    if (now - last_connection_check) >= CONNECTION_CHECK_INTERVAL
      # Check connection based on server mode
      if server_mode == :vpn
        # VPN Mode: Verify VPN IP still exists
        current_vpn_ip = detect_vpn_ip
        if current_vpn_ip.nil?
          puts "\n[Server] VPN connection lost! Shutting down server..."
          MultiplayerDebug.error("VPN", "VPN disconnected - server shutting down")

          # Notify all connected clients
          clients.dup.each do |c|
            begin
              safe_send(c, "SERVER_SHUTDOWN:VPN disconnected")
            rescue
              # Ignore send errors during shutdown
            end
          end

          # Close all connections
          clients.dup.each do |c|
            c.close rescue nil
          end

          # Close server socket
          server.close rescue nil

          puts "[Server] Server shut down gracefully."
          MultiplayerDebug.info("SHUTDOWN", "Server shut down due to VPN disconnection")
          exit(0)
        end
      elsif server_mode == :vps
        # VPS Mode: Verify public IP still exists
        current_public_ip = detect_public_ip
        if current_public_ip.nil?
          puts "\n[Server] Network connection lost! Shutting down server..."
          MultiplayerDebug.error("VPS", "Public IP lost - server shutting down")

          # Notify all connected clients
          clients.dup.each do |c|
            begin
              safe_send(c, "SERVER_SHUTDOWN:Network connection lost")
            rescue
              # Ignore send errors during shutdown
            end
          end

          # Close all connections and shutdown
          clients.dup.each { |c| c.close rescue nil }
          server.close rescue nil

          puts "[Server] Server shut down gracefully."
          MultiplayerDebug.info("SHUTDOWN", "Server shut down due to network disconnection")
          exit(0)
        end
      end
      last_connection_check = now
    end
  rescue => e
    MultiplayerDebug.error("CONN-CHECK", "Connection check failed: #{e.message}")
  end

  # ======================================
  # === ACK Resend Loop
  # ======================================
  now = Time.now
  pending_acks.each do |ack_key, data|
    elapsed = now - data[:sent_at]
    next if elapsed < ACK_TIMEOUT

    if data[:attempts] >= ACK_MAX_ATTEMPTS
      MultiplayerDebug.warn("COOP-ACK", "Giving up on ACK for #{ack_key} after #{data[:attempts]} attempts")
      pending_acks.delete(ack_key)
      next
    end

    # Resend
    from_sid, to_sid, battle_id, turn = ack_key.split("|", 4)
    if sid_sockets[to_sid]
      safe_send_sid(sid_sockets, to_sid, "FROM:#{from_sid}|COOP_ACTION:#{data[:payload]}")
      data[:sent_at] = now
      data[:attempts] += 1
      MultiplayerDebug.info("COOP-ACK", "Resending COOP_ACTION to #{to_sid} (attempt #{data[:attempts]}): battle=#{battle_id}, turn=#{turn}")
    else
      pending_acks.delete(ack_key)
    end
  end
end