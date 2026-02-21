# =============================================================================
# Family Double Ability System
# =============================================================================
# Override logic + UI for Pokemon with two family abilities.
#
# Source files merged:
#   119_Family_Double_Ability_Override.rb → Core override logic
#   121_DoubleAbilities_UI.rb            → UI for ability selection
# =============================================================================

#===============================================================================
# Helper method to check if Family Abilities are enabled
#===============================================================================
def family_abilities_enabled?
  # Check runtime Family Abilities setting first (from $PokemonSystem)
  if defined?($PokemonSystem) && $PokemonSystem && $PokemonSystem.respond_to?(:mp_family_abilities_enabled)
    return $PokemonSystem.mp_family_abilities_enabled != 0
  elsif defined?(PokemonFamilyConfig)
    return PokemonFamilyConfig.talent_infusion_enabled?
  end
  return true  # Default to enabled if no setting found
end

#===============================================================================
# Pokemon Class - ability2 getter override
#===============================================================================
class Pokemon
  # Override ability2 to work for Family Pokemon without switch requirement
  alias family_double_ability_original_ability2 ability2
  def ability2
    # If this is a Family Pokemon AND abilities are enabled, return ability2 (bypass switch check)
    if self.respond_to?(:has_family?) && self.has_family? && family_abilities_enabled?
      return GameData::Ability.try_get(ability2_id())
    end

    # Otherwise, use original implementation (requires SWITCH_DOUBLE_ABILITIES)
    return family_double_ability_original_ability2
  end
end

#===============================================================================
# Battler Class - ability2 getter and battle display override
#===============================================================================
class PokeBattle_Battler
  # Override ability2 to work for Family Pokemon without switch requirement
  alias family_double_ability_original_ability2 ability2
  def ability2
    # If this battler's Pokemon has a family AND abilities enabled, return ability2 (bypass switch check)
    if @ability2_id
      pkmn = self.pokemon rescue nil
      if pkmn && pkmn.respond_to?(:has_family?) && pkmn.has_family? && family_abilities_enabled?
        return GameData::Ability.try_get(@ability2_id)
      end
    end

    # Otherwise, use original implementation (requires SWITCH_DOUBLE_ABILITIES)
    return family_double_ability_original_ability2
  end

  # Override hasActiveAbility to check ability2 for Family Pokemon
  alias family_double_ability_original_hasActiveAbility hasActiveAbility?
  def hasActiveAbility?(check_ability, ignore_fainted = false, mold_broken = false)
    # For Family Pokemon with abilities enabled, check both abilities
    pkmn = self.pokemon rescue nil
    if pkmn && pkmn.respond_to?(:has_family?) && pkmn.has_family? && family_abilities_enabled? && @ability2_id
      return false if !abilityActive?(ignore_fainted)
      if check_ability.is_a?(Array)
        return check_ability.include?(@ability_id) || check_ability.include?(@ability2_id)
      end
      return self.ability == check_ability || self.ability2 == check_ability
    end

    # Otherwise, use original implementation
    return family_double_ability_original_hasActiveAbility(check_ability, ignore_fainted, mold_broken)
  end

  # Override pbEffectsOnSwitchIn to trigger ability2 for Family Pokemon
  alias family_double_ability_original_pbEffectsOnSwitchIn pbEffectsOnSwitchIn
  def pbEffectsOnSwitchIn(switchIn=false)
    # Call original first
    family_double_ability_original_pbEffectsOnSwitchIn(switchIn)

    # Trigger ability2 for Family Pokemon (if abilities enabled)
    pkmn = self.pokemon rescue nil
    if pkmn && pkmn.respond_to?(:has_family?) && pkmn.has_family? && family_abilities_enabled? && @ability2_id
      # Trigger ability2 switch-in handler if it exists
      if (!fainted? && unstoppableAbility?) || abilityActive?
        # Mark that ability2 is about to trigger (for splash display)
        @triggering_ability2 = true

        BattleHandlers.triggerAbilityOnSwitchIn(self.ability2,self,@battle) if self.ability2

        # Clear flag after trigger
        @triggering_ability2 = false

        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("FAMILY-BATTLE", "Triggered ability2 switch-in for #{pkmn.name}: #{self.ability2.name}")
        end
      end
    end
  end

  # Attribute accessor for ability2 trigger flag
  attr_accessor :triggering_ability2
end

#===============================================================================
# Battler Class - Override abilityName for ability2 triggers
#===============================================================================

class PokeBattle_Battler
  # Override abilityName to return ability2 name when ability2 is triggering
  alias family_double_ability_original_abilityName abilityName
  def abilityName
    # If ability2 is currently triggering, return ability2 name instead
    if @triggering_ability2 && self.ability2
      return self.ability2.name
    end

    # Otherwise, return original ability name
    return family_double_ability_original_abilityName
  end
end

#===============================================================================
# Battler Class - Override pbAbilitiesOnSwitchOut to trigger ability2
#===============================================================================

class PokeBattle_Battler
  alias family_double_ability_original_pbAbilitiesOnSwitchOut pbAbilitiesOnSwitchOut

  def pbAbilitiesOnSwitchOut
    # Check for ability2 BEFORE calling original (which sets @fainted = true)
    pkmn = self.pokemon rescue nil
    has_family_ability2 = pkmn &&
                          pkmn.respond_to?(:has_family?) &&
                          pkmn.has_family? &&
                          family_abilities_enabled? &&
                          @ability2_id &&
                          abilityActive?

    # Trigger primary ability first (from original method logic)
    if abilityActive?
      BattleHandlers.triggerAbilityOnSwitchOut(self.ability, self, false)
    end

    # Trigger ability2 for Family Pokemon BEFORE fainted state is set
    if has_family_ability2
      # Mark that ability2 is triggering
      @triggering_ability2 = true

      # Trigger ability2 switch-out handler
      BattleHandlers.triggerAbilityOnSwitchOut(self.ability2, self, false) if self.ability2

      # Clear flag
      @triggering_ability2 = false

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("FAMILY-BATTLE", "Triggered ability2 switch-out for #{pkmn.name}: #{self.ability2.name}")
      end
    end

    # Reset form
    @battle.peer.pbOnLeavingBattle(@battle, @pokemon, @battle.usedInBattle[idxOwnSide][@index/2])
    # Treat self as fainted
    @hp = 0
    @fainted = true
    # Check for end of primordial weather
    @battle.pbEndPrimordialWeather
  end
end

#-------------------------------------------------------------------------------
# Module loaded successfully
#-------------------------------------------------------------------------------
if defined?(MultiplayerDebug)
  MultiplayerDebug.info("FAMILY-DOUBLE-ABILITY", "Family Double Ability Override loaded")
end

#===============================================================================
# UI: Double Ability Splash Bar & Animations (from 121_DoubleAbilities_UI.rb)
#===============================================================================

# class AbilitySplashBar < SpriteWrapper
#   def refresh
#     self.bitmap.clear
#     return if !@battler
#     textPos = []
#     textX = (@side==0) ? 10 : self.bitmap.width-8
#     # Draw Pokémon's name
#     textPos.push([_INTL("{1}'s",@battler.name),textX,-4,@side==1,
#                   TEXT_BASE_COLOR,TEXT_SHADOW_COLOR,true])
#     # Draw Pokémon's ability
#     textPos.push([@battler.abilityName,textX,26,@side==1,
#                   TEXT_BASE_COLOR,TEXT_SHADOW_COLOR,true])
#     pbDrawTextPositions(self.bitmap,textPos)
#
#     #2nd ability
#     if $game_switches[SWITCH_DOUBLE_ABILITIES]
#       textPos.push([@battler.ability2Name,textX,26,@side==1,
#                     TEXT_BASE_COLOR,TEXT_SHADOW_COLOR,true])
#       pbDrawTextPositions(self.bitmap,textPos)
#     end
#   end
# end


class AbilitySplashDisappearAnimation < PokeBattle_Animation
  def initialize(sprites,viewport,side)
    @side = side
    super(sprites,viewport)
  end

  def createProcesses
    return if !@sprites["abilityBar_#{@side}"]
    bar = addSprite(@sprites["abilityBar_#{@side}"])
    bar2 = addSprite(@sprites["ability2Bar_#{@side}"]) if @sprites["ability2Bar_#{@side}"]

    dir = (@side==0) ? -1 : 1
    bar.moveDelta(0,8,dir*Graphics.width/2,0)
    bar2.moveDelta(0,8,dir*Graphics.width/2,0) if bar2

    bar.setVisible(8,false)
    bar2.setVisible(8,false) if bar2
  end
end

class PokeBattle_Scene
  def pbShowAbilitySplash(battler,secondAbility=false, abilityName=nil)
    return if !PokeBattle_SceneConstants::USE_ABILITY_SPLASH
    side = battler.index%2
    if secondAbility
      pbHideAbilitySplash(battler) if @sprites["ability2Bar_#{side}"].visible
    else
      pbHideAbilitySplash(battler) if @sprites["abilityBar_#{side}"].visible
    end
    if abilityName
      @sprites["abilityBar_#{side}"].ability_name = abilityName if !secondAbility
      @sprites["ability2Bar_#{side}"].ability_name = abilityName if secondAbility
    end


    @sprites["abilityBar_#{side}"].battler = battler
    @sprites["ability2Bar_#{side}"].battler = battler if @sprites["ability2Bar_#{side}"]

    abilitySplashAnim = AbilitySplashAppearAnimation.new(@sprites,@viewport,side,secondAbility)
    loop do
      abilitySplashAnim.update
      pbUpdate
      break if abilitySplashAnim.animDone?
    end
    abilitySplashAnim.dispose
  end
end

class PokeBattle_Battle

  def pbShowSecondaryAbilitySplash(battler,delay=false,logTrigger=true)
    return if !PokeBattle_SceneConstants::USE_ABILITY_SPLASH
    @scene.pbShowAbilitySplash(battler,true)
    if delay
      Graphics.frame_rate.times { @scene.pbUpdate }   # 1 second
    end
  end

  def pbShowPrimaryAbilitySplash(battler,delay=false,logTrigger=true)
    return if !PokeBattle_SceneConstants::USE_ABILITY_SPLASH
    @scene.pbShowAbilitySplash(battler,false)
    if delay
      Graphics.frame_rate.times { @scene.pbUpdate }   # 1 second
    end
  end

end



class FusionSelectOptionsScene < PokemonOption_Scene
  def pbGetOptions(inloadscreen = false)

    options = []
    if shouldSelectNickname
      options << EnumOption.new(_INTL("Nickname"), [_INTL(@pokemon1.name), _INTL(@pokemon2.name)],
                                proc { 0 },
                                proc { |value|
                                  if value ==0
                                    @nickname = @pokemon1.name
                                  else
                                    @nickname = @pokemon2.name
                                  end
                                }, "Select the Pokémon's nickname")
    end

    if @abilityList != nil
      options << EnumOption.new(_INTL("Ability"), [_INTL(getAbilityName(@abilityList[0])), _INTL(getAbilityName(@abilityList[1]))],
                                proc { 0 },
                                proc { |value|
                                  @selectedAbility=@abilityList[value]
                                }, [getAbilityDescription(@abilityList[0]), getAbilityDescription(@abilityList[1])]
      )
    end

    options << EnumOption.new(_INTL("Nature"), [_INTL(getNatureName(@natureList[0])), _INTL(getNatureName(@natureList[1]))],
                              proc { 0 },
                              proc { |value|
                                @selectedNature=@natureList[value]
                              }, [getNatureDescription(@natureList[0]), getNatureDescription(@natureList[1])]
    )
    return options
  end
end
