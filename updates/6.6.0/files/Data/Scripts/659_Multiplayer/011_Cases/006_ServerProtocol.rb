#===============================================================================
# KIF Cases — Server Protocol Reference
# File: 011_Cases/006_ServerProtocol.rb
#
# This file documents the server-side protocol for the case system.
# It is NOT executed client-side. Copy the handler logic to your server.
#
# ═══════════════════════════════════════════════════════════════════════════════
#
# ── POOLS (server must define identical pools) ───────────────────────────────
#
# PokéCase (:poke) — 7 rarity tiers, weighted. Pool is species list per tier.
#   Server rolls: tier (weighted), then position = rand(tier_pool.size)
#   Response: CASE_RESULT:poke|<tier>|<position>|<new_balance>
#
# MegaCase (:mega) — flat pool, all mega stones (id_number 9300-9439).
#   Server rolls: position = rand(pool.size)
#   Response: CASE_RESULT:mega|<position>|<new_balance>
#
# MoveCase (:move) — flat pool, all NPT move TMs (id_number 9500-9699).
#   Server rolls: position = rand(pool.size)
#   Response: CASE_RESULT:move|<position>|<new_balance>
#
# ── PRICING ──────────────────────────────────────────────────────────────────
#
# PokéCase: 200 Platinum
# MegaCase: 1000 Platinum
# MoveCase: 500 Platinum
#
# ── CLIENT → SERVER MESSAGES ────────────────────────────────────────────────
#
# CASE_BUYOPEN:<type>
#   Atomic buy-and-open. Deduct platinum, roll result, send back.
#   Validate: balance >= cost, cooldown not active.
#   Response: CASE_RESULT:<type>|... or CASE_ERROR:<reason>
#
# CASE_BUY:<type>
#   Buy a case to inventory (no opening).
#   Validate: balance >= cost, cooldown not active.
#   Deduct platinum, increment inventory count.
#   Response: CASE_BUY_OK:<type>|<new_count>|<new_balance>
#          or CASE_BUY_ERR:<reason>
#
# CASE_OPEN_INV:<type>
#   Open a case from inventory.
#   Validate: inventory[type] >= 1, cooldown not active.
#   Decrement inventory, roll result.
#   Response: CASE_RESULT:<type>|... or CASE_ERROR:<reason>
#
# CASE_INV_REQ
#   Request current inventory counts.
#   Response: CASE_INV:<poke_count>|<mega_count>|<move_count>
#
# CASE_OPEN:global
#   Legacy buy-and-open for PokéCase (backward compat).
#   Equivalent to CASE_BUYOPEN:poke.
#
# ── SERVER → CLIENT MESSAGES ────────────────────────────────────────────────
#
# CASE_RESULT:poke|<tier>|<position>|<new_balance>
# CASE_RESULT:mega|<position>|<new_balance>
# CASE_RESULT:move|<position>|<new_balance>
# CASE_ERROR:<reason>           — "INSUFFICIENT", "NO_INVENTORY", "COOLDOWN",
#                                  "NOT_REGISTERED", "INVALID_TYPE"
# CASE_INV:<poke>|<mega>|<move>
# CASE_BUY_OK:<type>|<new_count>|<new_balance>
# CASE_BUY_ERR:<reason>
#
# ── ANTI-CHEAT ──────────────────────────────────────────────────────────────
#
# 1. Cooldown: 2-second minimum between any case operation per player.
# 2. Rate limit: Max 20 case operations per minute per player.
# 3. All validation server-side (balance, inventory, cooldown).
# 4. Inventory stored in server DB, not client save file.
# 5. Log all transactions: player_uuid, type, operation, result, timestamp.
#
# ═══════════════════════════════════════════════════════════════════════════════
# Example server handler (pseudocode Ruby):
# ═══════════════════════════════════════════════════════════════════════════════
#
# CASE_COSTS = { "poke" => 200, "mega" => 1000, "move" => 500 }
#
# def handle_case_buyopen(player, type)
#   return send_to(player, "CASE_ERROR:INVALID_TYPE") unless CASE_COSTS[type]
#   return send_to(player, "CASE_ERROR:COOLDOWN") if on_cooldown?(player)
#   cost = CASE_COSTS[type]
#   return send_to(player, "CASE_ERROR:INSUFFICIENT") unless player.balance >= cost
#
#   player.balance -= cost
#   set_cooldown(player, 2.0)
#   result = roll_case(type)
#   player.save!
#
#   if type == "poke"
#     send_to(player, "CASE_RESULT:poke|#{result[:tier]}|#{result[:position]}|#{player.balance}")
#   else
#     send_to(player, "CASE_RESULT:#{type}|#{result[:position]}|#{player.balance}")
#   end
# end
#
# def handle_case_buy(player, type)
#   return send_to(player, "CASE_BUY_ERR:INVALID_TYPE") unless CASE_COSTS[type]
#   return send_to(player, "CASE_BUY_ERR:COOLDOWN") if on_cooldown?(player)
#   cost = CASE_COSTS[type]
#   return send_to(player, "CASE_BUY_ERR:Insufficient balance") unless player.balance >= cost
#
#   player.balance -= cost
#   player.case_inventory[type] = (player.case_inventory[type] || 0) + 1
#   set_cooldown(player, 2.0)
#   player.save!
#
#   send_to(player, "CASE_BUY_OK:#{type}|#{player.case_inventory[type]}|#{player.balance}")
# end
#
# def handle_case_open_inv(player, type)
#   return send_to(player, "CASE_ERROR:INVALID_TYPE") unless CASE_COSTS[type]
#   return send_to(player, "CASE_ERROR:COOLDOWN") if on_cooldown?(player)
#   inv = player.case_inventory[type] || 0
#   return send_to(player, "CASE_ERROR:NO_INVENTORY") unless inv > 0
#
#   player.case_inventory[type] -= 1
#   set_cooldown(player, 2.0)
#   result = roll_case(type)
#   player.save!
#
#   if type == "poke"
#     send_to(player, "CASE_RESULT:poke|#{result[:tier]}|#{result[:position]}|#{player.balance}")
#   else
#     send_to(player, "CASE_RESULT:#{type}|#{result[:position]}|#{player.balance}")
#   end
# end
#
# def handle_case_inv_req(player)
#   inv = player.case_inventory
#   send_to(player, "CASE_INV:#{inv['poke']||0}|#{inv['mega']||0}|#{inv['move']||0}")
# end
#
# ── POOL DEFINITIONS (server-side) ──────────────────────────────────────────
#
# def roll_case(type)
#   case type
#   when "poke"
#     tier = weighted_random(RARITY_WEIGHTS)  # [35,25,18,10,6,4,2]
#     pool = POKE_TIERS[tier]
#     { tier: tier, position: rand(pool.size) }
#   when "mega"
#     pool = ALL_MEGA_STONES  # 86 stones, sorted by id_number 9300-9439
#     { position: rand(pool.size) }
#   when "move"
#     pool = ALL_NPT_TMS     # ~187 TMs, sorted by id_number 9500-9699
#     { position: rand(pool.size) }
#   end
# end
#===============================================================================
