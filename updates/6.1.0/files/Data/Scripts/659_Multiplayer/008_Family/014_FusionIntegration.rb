#===============================================================================
# MODULE: Family/Subfamily System - Fusion Integration
#===============================================================================
# Handles Family and Talent inheritance during Pokemon fusion.
#
# Requirements:
#   1. Only BASE talents available for fusion (not boosted variants)
#   2. Boosted talents shown when Family talent = Pokemon's actual talent
#   3. Family inheritance: if one parent has family, fused Pokemon inherits it
#      If both have different families, show choice UI
#
# Integration Points:
#   - PokemonFusion.rb (line 978): Family inheritance after species change
#   - PokemonFusion.rb (line 1160): Ability selection (filter base talents)
#   - FusionMenu.rb: Add Family choice UI if both parents have different families
#===============================================================================

#-------------------------------------------------------------------------------
# Hook PokemonFusion to inherit Family attributes
#-------------------------------------------------------------------------------
class PokemonFusionScene
  # Hook pbFusionScreen to inherit family AFTER species change (line 978)
  alias family_original_pbFusionScreen pbFusionScreen
  def pbFusionScreen(cancancel = false, superSplicer = false, firstOptionSelected = false)
    # Store original ability info before fusion
    # Use family_talent_original_ability_id to bypass family hooks and get the REAL base ability
    body_ability = @pokemon1.respond_to?(:family_talent_original_ability_id) ?
                   @pokemon1.family_talent_original_ability_id : @pokemon1.ability_id
    head_ability = @pokemon2.respond_to?(:family_talent_original_ability_id) ?
                   @pokemon2.family_talent_original_ability_id : @pokemon2.ability_id

    body_has_family = @pokemon1.has_family?
    head_has_family = @pokemon2.has_family?

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("FAMILY-FUSION", "=== Fusion Starting ===")
      MultiplayerDebug.info("FAMILY-FUSION", "Body ability (original): #{body_ability}")
      MultiplayerDebug.info("FAMILY-FUSION", "Head ability (original): #{head_ability}")
      MultiplayerDebug.info("FAMILY-FUSION", "Body has family: #{body_has_family}")
      MultiplayerDebug.info("FAMILY-FUSION", "Head has family: #{head_has_family}")
    end

    # Store family data BEFORE species change
    @family_inheritance_data = {
      body_family: body_has_family ? @pokemon1.family : nil,
      body_subfamily: body_has_family ? @pokemon1.subfamily : nil,
      body_family_assigned_at: body_has_family ? @pokemon1.family_assigned_at : nil,
      body_ability: body_ability,
      head_family: head_has_family ? @pokemon2.family : nil,
      head_subfamily: head_has_family ? @pokemon2.subfamily : nil,
      head_family_assigned_at: head_has_family ? @pokemon2.family_assigned_at : nil,
      head_ability: head_ability
    }

    # Call original fusion method
    result = family_original_pbFusionScreen(cancancel, superSplicer, firstOptionSelected)

    # AFTER fusion completes, inherit family (always call, regardless of return value)
    inherit_family_to_fused_pokemon

    return result
  end

  # Inherit family from parent Pokemon to fused Pokemon
  def inherit_family_to_fused_pokemon
    data = @family_inheritance_data
    return unless data

    body_has_family = !data[:body_family].nil?
    head_has_family = !data[:head_family].nil?

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("FAMILY-FUSION", "=== Family Inheritance ===")
      MultiplayerDebug.info("FAMILY-FUSION", "Body has family: #{body_has_family} (family=#{data[:body_family]})")
      MultiplayerDebug.info("FAMILY-FUSION", "Head has family: #{head_has_family} (family=#{data[:head_family]})")
    end

    # ALWAYS store original family data for unfuse (similar to shiny storage)
    @pokemon1.body_family = data[:body_family]
    @pokemon1.body_subfamily = data[:body_subfamily]
    @pokemon1.body_family_assigned_at = data[:body_family_assigned_at]
    @pokemon1.head_family = data[:head_family]
    @pokemon1.head_subfamily = data[:head_subfamily]
    @pokemon1.head_family_assigned_at = data[:head_family_assigned_at]

    # Case 1: Both parents have families (different families)
    if body_has_family && head_has_family && data[:body_family] != data[:head_family]
      # Show choice UI for family selection
      chosen_family = pbChooseFamily(data[:body_family], data[:body_subfamily],
                                      data[:head_family], data[:head_subfamily])

      if chosen_family == :body
        # Keep body's family (already on @pokemon1)
        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("FAMILY-FUSION", "Chose body's family: #{data[:body_family]}")
        end
      else
        # Inherit head's family
        @pokemon1.family = data[:head_family]
        @pokemon1.subfamily = data[:head_subfamily]
        @pokemon1.family_assigned_at = data[:head_family_assigned_at]

        if defined?(MultiplayerDebug)
          MultiplayerDebug.info("FAMILY-FUSION", "Chose head's family: #{data[:head_family]}")
        end
      end

    # Case 2: Both have same family - keep it (already on @pokemon1)
    elsif body_has_family && head_has_family && data[:body_family] == data[:head_family]
      # Keep body's family (no action needed)
      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("FAMILY-FUSION", "Both have same family: #{data[:body_family]} - keeping it")
      end

    # Case 3: Only head has family - inherit it
    elsif !body_has_family && head_has_family
      @pokemon1.family = data[:head_family]
      @pokemon1.subfamily = data[:head_subfamily]
      @pokemon1.family_assigned_at = data[:head_family_assigned_at]

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("FAMILY-FUSION", "Inherited head's family: #{data[:head_family]}")
      end

    # Case 4: Only body has family - keep it (already on @pokemon1)
    elsif body_has_family && !head_has_family
      # Keep body's family (no action needed)
      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("FAMILY-FUSION", "Kept body's family: #{data[:body_family]}")
      end

    # Case 5: Neither has family - no action
    else
      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("FAMILY-FUSION", "Neither parent has family - fused Pokemon has no family")
      end
    end
  end

  # Show UI to choose which family to inherit
  def pbChooseFamily(body_family_id, body_subfamily_id, head_family_id, head_subfamily_id)
    # Get family names
    body_family_name = PokemonFamilyConfig::FAMILIES[body_family_id][:name]
    body_subfamily_name = PokemonFamilyConfig::SUBFAMILIES[body_family_id * 4 + body_subfamily_id][:name]
    body_full_name = "#{body_family_name} #{body_subfamily_name}"

    head_family_name = PokemonFamilyConfig::FAMILIES[head_family_id][:name]
    head_subfamily_name = PokemonFamilyConfig::SUBFAMILIES[head_family_id * 4 + head_subfamily_id][:name]
    head_full_name = "#{head_family_name} #{head_subfamily_name}"

    # Show choice message
    choice = Kernel.pbMessage(
      _INTL("Choose a family for the fused Pokémon."),
      [_INTL("{1} (Body)", body_full_name), _INTL("{1} (Head)", head_full_name)],
      2
    )

    return choice == 0 ? :body : :head
  end

  # Hook pbChooseAbility to show only base talents (not boosted variants)
  # This method is defined in DoubleAbilities.rb with signature (ability1Id, ability2Id)
  alias family_original_pbChooseAbility pbChooseAbility
  def pbChooseAbility(ability1_param, ability2_param)
    # Convert to IDs if objects were passed (handle both cases)
    ability1Id = ability1_param.respond_to?(:id) ? ability1_param.id : ability1_param
    ability2Id = ability2_param.respond_to?(:id) ? ability2_param.id : ability2_param

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("FAMILY-FUSION-ABILITY", "=== Ability Selection ===")
      MultiplayerDebug.info("FAMILY-FUSION-ABILITY", "Received params: #{ability1_param.inspect}, #{ability2_param.inspect}")
      MultiplayerDebug.info("FAMILY-FUSION-ABILITY", "Converted to IDs: #{ability1Id}, #{ability2Id}")
    end

    # Convert boosted talents to base talents for display
    display_ability1_id = convert_boosted_to_base_talent_id(ability1Id)
    display_ability2_id = convert_boosted_to_base_talent_id(ability2Id)

    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("FAMILY-FUSION-ABILITY", "Display abilities: #{display_ability1_id}, #{display_ability2_id}")
    end

    # Call original method with base talents
    # The Family Talent Infusion system will automatically upgrade to boosted if:
    # - Fused Pokemon has family AND
    # - Selected ability matches family base talent
    family_original_pbChooseAbility(display_ability1_id, display_ability2_id)
  end

  private

  # Convert boosted family talent ID to base talent ID
  def convert_boosted_to_base_talent_id(ability_id)
    return ability_id unless ability_id

    boosted_to_base = {
      :PANMORPHOSIS => :PROTEAN,
      :VEILBREAKER => :INFILTRATOR,
      :VOIDBORNE => :LEVITATE,
      :VITALREBIRTH => :REGENERATOR,
      :IMMOVABLE => :STURDY,
      :INDOMITABLE => :MOLDBREAKER,
      :COSMICBLESSING => :SERENEGRACE,
      :MINDSHATTER => :INTIMIDATE
    }

    # If this is a boosted talent, return base talent ID instead
    if boosted_to_base.has_key?(ability_id)
      base_talent_id = boosted_to_base[ability_id]

      if defined?(MultiplayerDebug)
        MultiplayerDebug.info("FAMILY-FUSION-ABILITY", "Converting boosted #{ability_id} -> base #{base_talent_id}")
      end

      return base_talent_id
    end

    # Otherwise, return ability ID as-is
    return ability_id
  end
end

#-------------------------------------------------------------------------------
# Module loaded successfully
#-------------------------------------------------------------------------------
if defined?(MultiplayerDebug)
  MultiplayerDebug.info("FAMILY-FUSION", "=" * 60)
  MultiplayerDebug.info("FAMILY-FUSION", "116_Family_Fusion_Integration.rb loaded successfully")
  MultiplayerDebug.info("FAMILY-FUSION", "Family inheritance:")
  MultiplayerDebug.info("FAMILY-FUSION", "  - Inherits from parent with family")
  MultiplayerDebug.info("FAMILY-FUSION", "  - Shows choice UI if both parents have different families")
  MultiplayerDebug.info("FAMILY-FUSION", "  - Only base talents shown in fusion UI")
  MultiplayerDebug.info("FAMILY-FUSION", "  - Boosted talents activate via Family Talent Infusion system")
  MultiplayerDebug.info("FAMILY-FUSION", "=" * 60)
end
