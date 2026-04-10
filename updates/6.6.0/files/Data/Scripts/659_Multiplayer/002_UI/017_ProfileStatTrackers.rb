# ===========================================
# File: 017_ProfileStatTrackers.rb
# Purpose: Client-side hooks that flush profile stats to the server
#          for steps, platinum (spent/won), and Pokédex caught count.
# ===========================================

module KIFProfileStatTrackers
  # ── Steps ─────────────────────────────────────────────
  @pending_steps     = 0
  @last_steps_flush  = Time.now.to_f
  STEPS_FLUSH_INTERVAL = 60.0   # flush pending steps every 60s

  def self.record_step
    @pending_steps += 1
  end

  def self.tick_steps_flush
    return unless defined?(MultiplayerClient) && MultiplayerClient.session_id
    now = Time.now.to_f
    return if (now - @last_steps_flush) < STEPS_FLUSH_INTERVAL
    @last_steps_flush = now
    return if @pending_steps <= 0
    delta = @pending_steps.clamp(0, 5000)  # server also clamps
    @pending_steps = 0
    MultiplayerClient.send_data("STAT_STEPS:#{delta}") rescue nil
  rescue; end

  # ── Platinum (money) ──────────────────────────────────
  @last_money        = nil
  @pending_spent     = 0
  @pending_won       = 0
  @last_platinum_flush = Time.now.to_f
  PLATINUM_FLUSH_INTERVAL = 10.0

  def self.tick_platinum
    return unless defined?(MultiplayerClient) && MultiplayerClient.session_id
    return unless defined?($Trainer) && $Trainer && $Trainer.respond_to?(:money)
    current = $Trainer.money.to_i

    # First tick — seed the baseline, don't count it as won
    if @last_money.nil?
      @last_money = current
      return
    end

    diff = current - @last_money
    if diff > 0
      @pending_won += diff
    elsif diff < 0
      @pending_spent += -diff
    end
    @last_money = current

    now = Time.now.to_f
    return if (now - @last_platinum_flush) < PLATINUM_FLUSH_INTERVAL
    @last_platinum_flush = now
    return if @pending_spent <= 0 && @pending_won <= 0
    spent = @pending_spent.clamp(0, 9_999_999)
    won   = @pending_won.clamp(0, 9_999_999)
    @pending_spent = 0
    @pending_won   = 0
    MultiplayerClient.send_data("STAT_PLATINUM:#{spent}:#{won}") rescue nil
  rescue; end

  # ── Pokémon caught (Pokédex owned_count) ──────────────
  @last_caught_count  = nil
  @last_caught_flush  = 0.0
  CAUGHT_FLUSH_INTERVAL = 30.0  # at most once per 30s

  def self.tick_caught
    return unless defined?(MultiplayerClient) && MultiplayerClient.session_id
    return unless defined?($Trainer) && $Trainer && $Trainer.respond_to?(:pokedex)
    count = ($Trainer.pokedex.owned_count rescue nil)
    return if count.nil?

    now = Time.now.to_f
    # Fire if changed OR first sync (caps at once per interval)
    if @last_caught_count != count && (now - @last_caught_flush) >= CAUGHT_FLUSH_INTERVAL
      @last_caught_count = count
      @last_caught_flush = now
      MultiplayerClient.send_data("STAT_POKECAUGHT:#{count}") rescue nil
    end
  rescue; end
end

# ---------- Hook onStepTaken ----------
if defined?(Events) && Events.respond_to?(:onStepTaken)
  Events.onStepTaken += proc { |_sender, _e| KIFProfileStatTrackers.record_step }
end

# ---------- Hook Scene_Map update (non-invasive) ----------
# Throttle to ~1Hz — these trackers don't need per-frame updates, and
# owned_count iterates the full Pokédex which is expensive at 60fps.
if defined?(Scene_Map)
  class ::Scene_Map
    alias kif_stat_trackers_update update unless method_defined?(:kif_stat_trackers_update)

    @@kif_stats_next_tick = 0.0

    def update
      kif_stat_trackers_update
      now = Time.now.to_f
      if now >= @@kif_stats_next_tick
        @@kif_stats_next_tick = now + 1.0
        KIFProfileStatTrackers.tick_steps_flush
        KIFProfileStatTrackers.tick_platinum
        KIFProfileStatTrackers.tick_caught
      end
    end
  end
end
