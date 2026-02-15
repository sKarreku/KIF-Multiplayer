#===============================================================================
# MODULE 6: Boss Pokemon System - Move Blocking & Run Prevention
#===============================================================================
# Blocks specific moves against boss Pokemon and prevents running.
#
# Blocked Moves (from BossConfig::BLOCKED_MOVES):
#   - OHKO moves: Fissure, Sheer Cold, Horn Drill, Guillotine
#   - Instant-win: Perish Song, Destiny Bond
#   - Reflect damage: Counter, Mirror Coat, Metal Burst
#   - HP equalize: Endeavor, Pain Split
#
# Run Prevention:
#   - Cannot run from boss battles
#   - Cannot use moves/items that escape battle
#
# Test: Encounter boss, try to run (should fail).
#       Use Fissure/Perish Song on boss (should fail with message).
#===============================================================================

#===============================================================================
# Block Running from Boss Battles
#===============================================================================
class PokeBattle_Battle
  alias boss_block_pbCanRun? pbCanRun?

  def pbCanRun?(idxBattler)
    # Check if any opponent is a boss
    eachOtherSideBattler(idxBattler) do |b|
      if b.pokemon&.is_boss?
        return false
      end
    end
    boss_block_pbCanRun?(idxBattler)
  end

  # Override pbRun to show boss-specific message
  alias boss_block_pbRun pbRun

  def pbRun(idxBattler, duringBattle = false)
    # Check for boss before attempting run
    has_boss = false
    eachOtherSideBattler(idxBattler) do |b|
      has_boss = true if b.pokemon&.is_boss?
    end

    if has_boss
      pbDisplayPaused(_INTL("The boss's presence is overwhelming! You can't escape!"))
      return 0
    end

    boss_block_pbRun(idxBattler, duringBattle)
  end
end

#===============================================================================
# Block Specific Moves Against Bosses
#===============================================================================
# We hook into pbMoveFailed? for each move function code

class PokeBattle_Move
  alias boss_block_pbMoveFailed? pbMoveFailed?

  def pbMoveFailed?(user, targets)
    # Check if any target is a boss and move is blocked
    if BossConfig.move_blocked?(@id)
      boss_target = targets.find { |t| t.pokemon&.is_boss? }
      if boss_target
        @battle.pbDisplay(_INTL("{1} is unaffected by {2}!", boss_target.pbThis, @name))
        return true
      end
    end

    boss_block_pbMoveFailed?(user, targets)
  end
end

#===============================================================================
# Specific Move Function Overrides for Edge Cases
#===============================================================================

# OHKO Moves (Fissure, Sheer Cold, Horn Drill, Guillotine)
# These need special handling because they check accuracy differently
class PokeBattle_Move_070 < PokeBattle_Move  # OHKO base class
  alias boss_block_ohko_pbFailsAgainstTarget? pbFailsAgainstTarget?

  def pbFailsAgainstTarget?(user, target)
    if target.pokemon&.is_boss?
      @battle.pbDisplay(_INTL("{1} is too powerful to be knocked out instantly!", target.pbThis))
      return true
    end
    boss_block_ohko_pbFailsAgainstTarget?(user, target)
  end
end

# Perish Song - Block effect on boss
class PokeBattle_Move_0E5 < PokeBattle_Move  # PerishSong
  alias boss_block_perish_pbEffectGeneral pbEffectGeneral

  def pbEffectGeneral(user)
    # Original effect applies Perish count to all battlers
    # We need to skip bosses
    boss_block_perish_pbEffectGeneral(user)

    # Remove perish count from bosses after it's applied
    @battle.eachBattler do |b|
      if b.pokemon&.is_boss? && b.effects[PBEffects::PerishSong] > 0
        b.effects[PBEffects::PerishSong] = 0
        @battle.pbDisplay(_INTL("{1} is unaffected by the perish song!", b.pbThis))
      end
    end
  end
end

# Destiny Bond - Prevent boss from being KO'd by it
class PokeBattle_Move_0E7 < PokeBattle_Move  # DestinyBond
  alias boss_block_destiny_pbEffectGeneral pbEffectGeneral

  def pbEffectGeneral(user)
    # Check if opponent is boss
    boss_opponent = false
    @battle.eachOtherSideBattler(user.index) do |b|
      boss_opponent = true if b.pokemon&.is_boss?
    end

    if boss_opponent
      @battle.pbDisplay(_INTL("{1}'s Destiny Bond failed! The boss is too powerful!", user.pbThis))
      return
    end

    boss_block_destiny_pbEffectGeneral(user)
  end
end

# Counter/Mirror Coat/Metal Burst - Don't record damage against shielded bosses
class PokeBattle_Move
  alias boss_block_pbRecordDamageLost pbRecordDamageLost

  def pbRecordDamageLost(user, target)
    # Skip recording if target is a boss with shields
    if target.pokemon&.is_boss? && target.pokemon.boss_shields > 0
      return
    end

    boss_block_pbRecordDamageLost(user, target)
  end
end

# Endeavor - Fails against boss
class PokeBattle_Move_06D < PokeBattle_Move  # Endeavor
  alias boss_block_endeavor_pbFailsAgainstTarget? pbFailsAgainstTarget?

  def pbFailsAgainstTarget?(user, target)
    if target.pokemon&.is_boss?
      @battle.pbDisplay(_INTL("{1} is too powerful for Endeavor!", target.pbThis))
      return true
    end
    boss_block_endeavor_pbFailsAgainstTarget?(user, target)
  end
end

# Pain Split - Fails against boss
class PokeBattle_Move_05B < PokeBattle_Move  # PainSplit
  alias boss_block_painsplit_pbFailsAgainstTarget? pbFailsAgainstTarget?

  def pbFailsAgainstTarget?(user, target)
    if target.pokemon&.is_boss?
      @battle.pbDisplay(_INTL("{1}'s pain cannot be shared with the boss!", user.pbThis))
      return true
    end
    boss_block_painsplit_pbFailsAgainstTarget?(user, target)
  end
end

#===============================================================================
# Block Escape Items Against Boss
#===============================================================================
# Smoke Ball, Poke Doll, etc. should also fail
# Only define if the method exists in this version of Essentials
class PokeBattle_Battle
  if method_defined?(:pbCanUseItem?)
    alias boss_block_pbCanUseItem? pbCanUseItem?

    def pbCanUseItem?(idxBattler, item)
      # Check for escape items
      escape_items = [:POKEDOLL, :FLUFFYTAIL, :POKERTOY]

      if escape_items.include?(item)
        has_boss = false
        eachOtherSideBattler(idxBattler) do |b|
          has_boss = true if b.pokemon&.is_boss?
        end

        if has_boss
          pbDisplay(_INTL("The boss blocks your escape attempt!"))
          return false
        end
      end

      boss_block_pbCanUseItem?(idxBattler, item)
    end
  end
end

#===============================================================================
# Block Teleport and Similar Moves
#===============================================================================
class PokeBattle_Move_0EA < PokeBattle_Move  # Teleport
  alias boss_block_teleport_pbMoveFailed? pbMoveFailed?

  def pbMoveFailed?(user, targets)
    has_boss = false
    @battle.eachOtherSideBattler(user.index) do |b|
      has_boss = true if b.pokemon&.is_boss?
    end

    if has_boss
      @battle.pbDisplay(_INTL("The boss's presence prevents teleportation!"))
      return true
    end

    boss_block_teleport_pbMoveFailed?(user, targets)
  end
end
