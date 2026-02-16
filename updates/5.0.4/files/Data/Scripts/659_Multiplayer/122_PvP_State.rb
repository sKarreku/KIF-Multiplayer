module PvPBattleState
  @battle_id = nil
  @is_initiator = false
  @opponent_sid = nil
  @opponent_name = nil
  @settings = {}
  @my_selections = []
  @opponent_party = nil
  @battle_active = false
  @battle_instance = nil

  def self.create_session(is_initiator:, opponent_sid:, opponent_name:, battle_id: nil)
    @battle_id = battle_id || generate_battle_id()
    @is_initiator = is_initiator
    @opponent_sid = opponent_sid
    @opponent_name = opponent_name
    @settings = default_settings()
    @my_selections = []
    @opponent_party = nil
    @battle_active = false
  end

  def self.default_settings
    {
      "battle_size" => "1v1",      # 1v1, 2v2, 3v3
      "party_size" => "full",       # full, pick4, pick3
      "held_items" => true,
      "battle_items" => true,
      "level_cap" => "none"         # none, level50
    }
  end

  def self.generate_battle_id
    my_sid = MultiplayerClient.session_id.to_s
    timestamp_ms = (Time.now.to_f * 1000).to_i
    "PVP#{my_sid}_#{timestamp_ms}"
  end

  # Getters
  def self.battle_id; @battle_id; end
  def self.is_initiator?; @is_initiator; end
  def self.opponent_sid; @opponent_sid; end
  def self.opponent_name; @opponent_name; end
  def self.settings; @settings; end
  def self.my_selections; @my_selections; end
  def self.opponent_party; @opponent_party; end
  def self.battle_instance; @battle_instance; end

  # Update settings (initiator only, but both track)
  def self.update_settings(new_settings)
    @settings.merge!(new_settings)
  end

  # Party selection for Pick modes
  def self.set_my_selections(indices)
    @my_selections = indices
  end

  # Opponent party (received via network)
  def self.set_opponent_party(party)
    @opponent_party = party
  end

  # Battle activation
  def self.mark_battle_active
    @battle_active = true
  end

  def self.in_pvp_battle?
    @battle_active
  end

  # Register battle instance for access during battle
  def self.register_battle_instance(battle)
    @battle_instance = battle
  end

  # Cleanup
  def self.reset
    @battle_id = nil
    @is_initiator = false
    @opponent_sid = nil
    @opponent_name = nil
    @settings = {}
    @my_selections = []
    @opponent_party = nil
    @battle_active = false
    @battle_instance = nil
  end
end
