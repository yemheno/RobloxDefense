-- ReplicatedStorage/Shared/TalentTreeConfig
--[[
    Data-driven talent tree definition — expanded to the full 301-node web.

    Structure
    ═════════
    The tree is a graph: Nodes + Edges.

    Node fields:
        id            (string)   unique identifier
        name          (string)   display name
        type          (string)   "small" | "notable" | "keystone"
        x, y          (number)   UI grid position (unitless; client maps to pixels)
        cost          (number)   talent points to allocate (usually 1)
        effects       (table)    list of effect entries:
                                   { stat = "...", value = N }          → flat bonus stat
                                   { primary = "MIG"|"VIT"|..., value = N } → primary stat bonus
                                   { stat = "...", rule = true }         → keystone toggle
        tags          (table?)   optional archetype tags
        description   (string)   tooltip text

    Edge:
        { from, to }  — bidirectional adjacency.

    Coordinate layout
    ═════════════════
    Sectors are arranged in three concentric rings around Origin (0,0).
    y is positive-down (screen convention), so negative y = "up".

    Inner ring — 5 primary sectors (radius ≈ 13–19):
        Warpath  (MIG)   upper-left   x ∈ [-17,-11], y ∈ [-19, -7]
        Lifeblood(VIT)   top-center   x ∈ [ -3,  3], y ∈ [-28,-16]
        Precision(PRE)   upper-right  x ∈ [ 11, 17], y ∈ [-19, -7]
        Attunement(MAG)  lower-right  x ∈ [ 11, 17], y ∈ [  7, 19]
        Resolve  (RSV)   lower-left   x ∈ [-17,-11], y ∈ [  7, 19]

    Middle ring — 5 hybrid sectors (radius ≈ 22–34):
        Juggernaut(MIG/VIT)  upper-left   x ∈ [-17,-11], y ∈ [-34,-22]
        Predator  (PRE/MIG)  upper-right  x ∈ [ 11, 17], y ∈ [-34,-22]
        Oracle    (MAG/PRE)  right        x ∈ [ 22, 34], y ∈ [ -3,  3]
        Spellblade(RSV/MAG)  bottom       x ∈ [ -3,  3], y ∈ [ 22, 34]
        Sanctuary (VIT/RSV)  left         x ∈ [-34,-22], y ∈ [ -3,  3]

    Outer ring — 5 mastery branches (radius ≈ 38–50):
        Bulwark     off Juggernaut  x ∈ [-17,-11], y ∈ [-50,-38]
        Huntmaster  off Predator    x ∈ [ 11, 17], y ∈ [-50,-38]
        Grace       off Oracle      x ∈ [ 38, 50], y ∈ [ -3,  3]
        Stormweave  off Spellblade  x ∈ [ -3,  3], y ∈ [ 38, 50]
        Fortune     off Sanctuary   x ∈ [-50,-38], y ∈ [ -3,  3]

    Each sector uses a 5-row × 4-col grid:
        Rows 1-3 (all 4 cols):  small nodes
        Row 4, cols 1-2:        small nodes
        Row 4, cols 3-4:        notable nodes
        Row 5, cols 1-3:        notable nodes
        Row 5, col  4:          keystone
    Row 1 is the sector's entry (closest to Origin); Row 5 is deepest.
    For horizontal sectors (Oracle, Spellblade, Sanctuary, Grace, Stormweave, Fortune)
    the "row" axis is x and the "col" axis is y.

    Node IDs:  {sector}_{row}_{col}
    Keystones: {sector}_5_4
]]

local TalentTreeConfig = {}

-- ═══════════════════════════════════════════════════════════
-- HELPER  (inline shorthand for readability)
-- ═══════════════════════════════════════════════════════════

local function N(id, name, t, x, y, cost, tags, effects, desc)
	return { id = id, name = name, type = t, x = x, y = y, cost = cost,
	         tags = tags, effects = effects, description = desc }
end

-- ═══════════════════════════════════════════════════════════
-- NODES
-- ═══════════════════════════════════════════════════════════

TalentTreeConfig.Nodes = {

-- ────────────────────────────────────────────────────────────
-- ORIGIN
-- ────────────────────────────────────────────────────────────
{ id = "start", name = "Origin", type = "notable", x = 0, y = 0, cost = 0,
  effects = {}, description = "The root of all power. Every journey begins here." },

-- ════════════════════════════════════════════════════════════
-- 1. WARPATH  (MIG)
--    upper-left   x cols [-17,-15,-13,-11]   y rows [-7,-10,-13,-16,-19]
--    entry row = y=-7 (closest to Origin), keystone = (-11,-19)
-- ════════════════════════════════════════════════════════════
-- Row 1 – smalls
N("wp_1_1","Brute Force",      "small",-17,-7,1,{"warpath"},{{primary="MIG",value=1}},"+1 MIG"),
N("wp_1_2","Heavy Grip",       "small",-15,-7,1,{"warpath"},{{primary="MIG",value=1}},"+1 MIG"),
N("wp_1_3","Blood in the Arms","small",-13,-7,1,{"warpath"},{{primary="MIG",value=1}},"+1 MIG"),
N("wp_1_4","Martial Bearing",  "small",-11,-7,1,{"warpath"},{{primary="MIG",value=1}},"+1 MIG"),
-- Row 2
N("wp_2_1","Weapon Drill I", "small",-17,-10,1,{"warpath"},{{stat="FlatAttack",  value=2}},"+2 Flat Attack"),
N("wp_2_2","Weapon Drill II","small",-15,-10,1,{"warpath"},{{stat="FlatAttack",  value=2}},"+2 Flat Attack"),
N("wp_2_3","Split Mail",     "small",-13,-10,1,{"warpath"},{{stat="Penetration", value=2}},"+2 Penetration"),
N("wp_2_4","Sundering",      "small",-11,-10,1,{"warpath"},{{stat="Penetration", value=3}},"+3 Penetration"),
-- Row 3
N("wp_3_1","Killing Stroke","small",-17,-13,1,{"warpath"},{{stat="BonusDamage",  value=2}},"+2 Flat Damage"),
N("wp_3_2","Hard Swings",   "small",-15,-13,1,{"warpath"},{{stat="DamagePercent",value=2}},"+2% Damage"),
N("wp_3_3","Momentum Cut",  "small",-13,-13,1,{"warpath"},{{stat="AttackSpeed",  value=2}},"+2% Attack Speed"),
N("wp_3_4","Cleaving Line", "small",-11,-13,1,{"warpath"},{{stat="SkillDamage",  value=2}},"+2% Skill Damage"),
-- Row 4 – 2 smalls + 2 notables
N("wp_4_1","Crushing Pace",     "small",-17,-16,1,{"warpath"},{{stat="Penetration",value=2},{stat="AttackSpeed",value=1}},"+2 Penetration, +1% Attack Speed"),
N("wp_4_2","Battlefield Scar",  "small",-15,-16,1,{"warpath"},{{stat="BonusHealth",value=8}},"+8 Health"),
N("wp_4_3","Martial Discipline","notable",-13,-16,1,{"warpath"},{{primary="MIG",value=2},{stat="FlatAttack",value=4}},"+2 MIG, +4 Flat Attack"),
N("wp_4_4","Breachmaker",       "notable",-11,-16,1,{"warpath"},{{stat="Penetration",value=5},{stat="DamagePercent",value=3}},"+5 Penetration, +3% Damage"),
-- Row 5 – 3 notables + keystone
N("wp_5_1","Iron Tempo",      "notable",-17,-19,1,{"warpath"},{{stat="AttackSpeed",value=4},{stat="BonusDamage",value=2}},"+4% Attack Speed, +2 Flat Damage"),
N("wp_5_2","Execution Weight","notable",-15,-19,1,{"warpath"},{{stat="BonusDamage",value=3},{stat="SkillDamage",value=3}},"+3 Flat Damage, +3% Skill Damage"),
N("wp_5_3","Red Steel",       "notable",-13,-19,1,{"warpath"},{{primary="MIG",value=2},{stat="BonusHealth",value=10},{stat="Penetration",value=3}},"+2 MIG, +10 Health, +3 Penetration"),
N("wp_5_4","Overwhelm",       "keystone",-11,-19,1,{"warpath"},
  {{stat="Overwhelm",rule=true},{stat="AttackSpeed",value=-6}},
  "Hits against enemies above 70% HP gain +15 Penetration and +10% Damage. Attack Speed -6%."),

-- ════════════════════════════════════════════════════════════
-- 2. LIFEBLOOD  (VIT)
--    top-center   x cols [-3,-1,1,3]   y rows [-16,-19,-22,-25,-28]
--    entry = y=-16, keystone = (3,-28)
-- ════════════════════════════════════════════════════════════
N("lb_1_1","Hardy Soul",   "small",-3,-16,1,{"lifeblood"},{{primary="VIT",value=1}},"+1 VIT"),
N("lb_1_2","Thick Veins",  "small",-1,-16,1,{"lifeblood"},{{primary="VIT",value=1}},"+1 VIT"),
N("lb_1_3","Deep Breath",  "small", 1,-16,1,{"lifeblood"},{{primary="VIT",value=1}},"+1 VIT"),
N("lb_1_4","Packed Muscle","small", 3,-16,1,{"lifeblood"},{{primary="VIT",value=1}},"+1 VIT"),

N("lb_2_1","Healthy Frame I",    "small",-3,-19,1,{"lifeblood"},{{stat="BonusHealth",  value=10}},"+10 Health"),
N("lb_2_2","Healthy Frame II",   "small",-1,-19,1,{"lifeblood"},{{stat="BonusHealth",  value=10}},"+10 Health"),
N("lb_2_3","Iron Constitution",  "small", 1,-19,1,{"lifeblood"},{{stat="HealthPercent", value=1}},"+1% Health"),
N("lb_2_4","Reserves of Flesh",  "small", 3,-19,1,{"lifeblood"},{{stat="BonusHealth",  value=12}},"+12 Health"),

N("lb_3_1","Fast Recovery","small",-3,-22,1,{"lifeblood"},{{stat="HpRegen",    value=0.15}},"+0.15% HP Regen/s"),
N("lb_3_2","Knitted Flesh","small",-1,-22,1,{"lifeblood"},{{stat="FlatHpRegen",value=1}},"+1 HP Regen/s"),
N("lb_3_3","Thorn Nerves", "small", 1,-22,1,{"lifeblood"},{{stat="Thorns",     value=2}},"+2 Thorns"),
N("lb_3_4","Stone Skin",   "small", 3,-22,1,{"lifeblood"},{{stat="Armor",      value=3}},"+3 Armor"),

N("lb_4_1","Survival Pulse","small",-3,-25,1,{"lifeblood"},{{stat="HpRegen",     value=0.15}},"+0.15% HP Regen/s"),
N("lb_4_2","Hold Together", "small",-1,-25,1,{"lifeblood"},{{stat="HealthPercent",value=1}},"+1% Health"),
N("lb_4_3","Veteran Hide",  "notable", 1,-25,1,{"lifeblood"},{{primary="VIT",value=2},{stat="BonusHealth",value=15}},"+2 VIT, +15 Health"),
N("lb_4_4","Renewal",       "notable", 3,-25,1,{"lifeblood"},{{stat="HpRegen",value=0.30},{stat="FlatHpRegen",value=1}},"+0.30% HP Regen/s, +1 HP Regen/s"),

N("lb_5_1","Barbed Blood","notable",-3,-28,1,{"lifeblood"},{{stat="Thorns",value=4},{stat="BonusHealth",value=10}},"+4 Thorns, +10 Health"),
N("lb_5_2","Natural Plate","notable",-1,-28,1,{"lifeblood"},{{stat="Armor",value=5},{stat="HealthPercent",value=1}},"+5 Armor, +1% Health"),
N("lb_5_3","Last Supper",  "notable", 1,-28,1,{"lifeblood"},{{primary="VIT",value=2},{stat="HpRegen",value=0.2},{stat="BonusHealth",value=8}},"+2 VIT, +0.2% HP Regen/s, +8 Health"),
N("lb_5_4","Second Heart", "keystone", 3,-28,1,{"lifeblood"},
  {{stat="SecondHeart",rule=true},{stat="DamagePercent",value=-12}},
  "Once every 45s, dropping below 35% HP triggers regeneration equal to 8% max HP over 4s. While active, Damage -12%."),

-- ════════════════════════════════════════════════════════════
-- 3. PRECISION  (PRE)
--    upper-right  x cols [11,13,15,17]   y rows [-7,-10,-13,-16,-19]
--    entry = y=-7, keystone = (17,-19)
-- ════════════════════════════════════════════════════════════
N("pr_1_1","Keen Eye",       "small",11,-7,1,{"precision"},{{primary="PRE",value=1}},"+1 PRE"),
N("pr_1_2","Sure Hand",      "small",13,-7,1,{"precision"},{{primary="PRE",value=1}},"+1 PRE"),
N("pr_1_3","Hunter's Focus", "small",15,-7,1,{"precision"},{{primary="PRE",value=1}},"+1 PRE"),
N("pr_1_4","Fine Control",   "small",17,-7,1,{"precision"},{{primary="PRE",value=1}},"+1 PRE"),

N("pr_2_1","Edge Alignment I", "small",11,-10,1,{"precision"},{{stat="CritChance",value=2}},"+2% Crit Chance"),
N("pr_2_2","Edge Alignment II","small",13,-10,1,{"precision"},{{stat="CritChance",value=2}},"+2% Crit Chance"),
N("pr_2_3","Steady Finger I",  "small",15,-10,1,{"precision"},{{stat="CritDamage",value=0.04}},"+0.04x Crit Damage"),
N("pr_2_4","Quick Release I",  "small",17,-10,1,{"precision"},{{stat="AttackSpeed",value=2}},"+2% Attack Speed"),

N("pr_3_1","Rapid Casting I","small",11,-13,1,{"precision"},{{stat="CastTimeReduction",value=2}},"+2% Cast Speed"),
N("pr_3_2","Open Vein",      "small",13,-13,1,{"precision"},{{stat="Penetration",    value=2}},"+2 Penetration"),
N("pr_3_3","Measured Aim",   "small",15,-13,1,{"precision"},{{stat="CritChance",     value=1}},"+1% Crit Chance"),
N("pr_3_4","Quick Release II","small",17,-13,1,{"precision"},{{stat="AttackSpeed",   value=2}},"+2% Attack Speed"),

N("pr_4_1","Steady Finger II","small",11,-16,1,{"precision"},{{stat="CritDamage",        value=0.04}},"+0.04x Crit Damage"),
N("pr_4_2","Surgical Habit",  "small",13,-16,1,{"precision"},{{stat="CastTimeReduction",  value=2}},"+2% Cast Speed"),
N("pr_4_3","Dead Calm",       "notable",15,-16,1,{"precision"},{{primary="PRE",value=2},{stat="CritChance",value=4}},"+2 PRE, +4% Crit Chance"),
N("pr_4_4","Razor Thought",   "notable",17,-16,1,{"precision"},{{stat="CritDamage",value=0.08},{stat="CastTimeReduction",value=3}},"+0.08x Crit Damage, +3% Cast Speed"),

N("pr_5_1","Reflex Arc",      "notable",11,-19,1,{"precision"},{{stat="AttackSpeed",value=4},{stat="CritChance",value=2}},"+4% Attack Speed, +2% Crit Chance"),
N("pr_5_2","Thread the Gap",  "notable",13,-19,1,{"precision"},{{stat="Penetration",value=5},{stat="CritChance",value=2}},"+5 Penetration, +2% Crit Chance"),
N("pr_5_3","Clean Execution", "notable",15,-19,1,{"precision"},{{primary="PRE",value=2},{stat="CritDamage",value=0.05},{stat="AttackSpeed",value=2}},"+2 PRE, +0.05x Crit Damage, +2% Attack Speed"),
N("pr_5_4","Perfect Form",    "keystone",17,-19,1,{"precision"},
  {{stat="PerfectForm",rule=true}},
  "While stationary for 1.5s: +12% Crit Chance and +0.10x Crit Damage. Moving suppresses the bonus for 2s."),

-- ════════════════════════════════════════════════════════════
-- 4. ATTUNEMENT  (MAG)
--    lower-right  x cols [11,13,15,17]   y rows [7,10,13,16,19]
--    entry = y=7, keystone = (17,19)
-- ════════════════════════════════════════════════════════════
N("at_1_1","Attuned Spark",  "small",11,7,1,{"attunement"},{{primary="MAG",value=1}},"+1 MAG"),
N("at_1_2","Scholar's Reach","small",13,7,1,{"attunement"},{{primary="MAG",value=1}},"+1 MAG"),
N("at_1_3","Aether Sense",   "small",15,7,1,{"attunement"},{{primary="MAG",value=1}},"+1 MAG"),
N("at_1_4","Mystic Nerve",   "small",17,7,1,{"attunement"},{{primary="MAG",value=1}},"+1 MAG"),

N("at_2_1","Spell Weave I",   "small",11,10,1,{"attunement"},{{stat="SkillDamage", value=2}},"+2% Skill Damage"),
N("at_2_2","Spell Weave II",  "small",13,10,1,{"attunement"},{{stat="SkillDamage", value=2}},"+2% Skill Damage"),
N("at_2_3","Broad Glyph I",   "small",15,10,1,{"attunement"},{{stat="AoESize",     value=3}},"+3% AoE Size"),
N("at_2_4","Blessed Practice","small",17,10,1,{"attunement"},{{stat="HealingPower",value=4}},"+4 Healing Power"),

N("at_3_1","Resonant Mind",  "small",11,13,1,{"attunement"},{{stat="DamagePercent",  value=2}},"+2% Damage"),
N("at_3_2","Broad Glyph II", "small",13,13,1,{"attunement"},{{stat="AoESize",        value=3}},"+3% AoE Size"),
N("at_3_3","Soothing Current","small",15,13,1,{"attunement"},{{stat="HealingPercent", value=3}},"+3% Healing"),
N("at_3_4","Spell Weave III","small",17,13,1,{"attunement"},{{stat="SkillDamage",    value=3}},"+3% Skill Damage"),

N("at_4_1","Focused Aether","small",11,16,1,{"attunement"},{{stat="Aether",     value=5}},"+5 Aether"),
N("at_4_2","Gentle Current","small",13,16,1,{"attunement"},{{stat="LifeEnergy", value=4}},"+4 Life Energy"),
N("at_4_3","High Casting",  "notable",15,16,1,{"attunement"},{{primary="MAG",value=2},{stat="SkillDamage",value=4}},"+2 MAG, +4% Skill Damage"),
N("at_4_4","Grand Pattern", "notable",17,16,1,{"attunement"},{{stat="AoESize",value=6},{stat="DamagePercent",value=3}},"+6% AoE Size, +3% Damage"),

N("at_5_1","Deep Reservoir", "notable",11,19,1,{"attunement"},{{primary="MAG",value=2},{stat="Aether",value=10}},"+2 MAG, +10 Aether"),
N("at_5_2","Merciful Current","notable",13,19,1,{"attunement"},{{stat="HealingPower",value=8},{stat="HealingPercent",value=5}},"+8 Healing Power, +5% Healing"),
N("at_5_3","Unbound Formula","notable",15,19,1,{"attunement"},{{stat="SkillDamage",value=5},{stat="AoESize",value=4}},"+5% Skill Damage, +4% AoE Size"),
N("at_5_4","Arc Saturation", "keystone",17,19,1,{"attunement"},
  {{stat="ArcSaturation",rule=true},{stat="DamagePercent",value=-10}},
  "Skills hitting 4+ targets gain +12% Skill Damage and +15% AoE Size. Primary attacks deal -10% damage."),

-- ════════════════════════════════════════════════════════════
-- 5. RESOLVE  (RSV)
--    lower-left   x cols [-17,-15,-13,-11]   y rows [7,10,13,16,19]
--    entry = y=7, keystone = (-11,19)
-- ════════════════════════════════════════════════════════════
N("rs_1_1","Inner Will",      "small",-17,7,1,{"resolve"},{{primary="RSV",value=1}},"+1 RSV"),
N("rs_1_2","Quiet Mind",      "small",-15,7,1,{"resolve"},{{primary="RSV",value=1}},"+1 RSV"),
N("rs_1_3","Hardened Nerves", "small",-13,7,1,{"resolve"},{{primary="RSV",value=1}},"+1 RSV"),
N("rs_1_4","Cold Focus",      "small",-11,7,1,{"resolve"},{{primary="RSV",value=1}},"+1 RSV"),

N("rs_2_1","Efficient Cycle I",  "small",-17,10,1,{"resolve"},{{stat="CooldownReduction",value=1}},"+1% CDR"),
N("rs_2_2","Efficient Cycle II", "small",-15,10,1,{"resolve"},{{stat="CooldownReduction",value=1}},"+1% CDR"),
N("rs_2_3","Resistance Drill I", "small",-13,10,1,{"resolve"},{{stat="StatusResistance", value=3}},"+3% Status Resist"),
N("rs_2_4","Swift Recovery I",   "small",-11,10,1,{"resolve"},{{stat="CastTimeReduction",value=2}},"+2% Cast Speed"),

N("rs_3_1","Efficient Cycle III","small",-17,13,1,{"resolve"},{{stat="CooldownReduction",value=2}},"+2% CDR"),
N("rs_3_2","Resistance Drill II","small",-15,13,1,{"resolve"},{{stat="StatusResistance", value=3}},"+3% Status Resist"),
N("rs_3_3","Swift Recovery II",  "small",-13,13,1,{"resolve"},{{stat="CastTimeReduction",value=2}},"+2% Cast Speed"),
N("rs_3_4","Ordered Motion I",   "small",-11,13,1,{"resolve"},{{stat="MovementSpeed",    value=2}},"+2% Movement Speed"),

N("rs_4_1","Ordered Motion II","small",-17,16,1,{"resolve"},{{stat="MovementSpeed",   value=2}},"+2% Movement Speed"),
N("rs_4_2","Guarded Breathing","small",-15,16,1,{"resolve"},{{stat="DamageReduction", value=1}},"+1% Damage Reduction"),
N("rs_4_3","Tempered Will",    "notable",-13,16,1,{"resolve"},{{primary="RSV",value=2},{stat="StatusResistance",value=3}},"+2 RSV, +3% Status Resist"),
N("rs_4_4","Battle Composure", "notable",-11,16,1,{"resolve"},{{stat="CooldownReduction",value=4},{stat="CastTimeReduction",value=3}},"+4% CDR, +3% Cast Speed"),

N("rs_5_1","Enduring Plan",    "notable",-17,19,1,{"resolve"},{{primary="RSV",value=2},{stat="DamageReduction",value=1},{stat="MovementSpeed",value=2}},"+2 RSV, +1% DR, +2% Movement Speed"),
N("rs_5_2","Reserve Discipline","notable",-15,19,1,{"resolve"},{{primary="RSV",value=2},{stat="StatusResistance",value=8}},"+2 RSV, +8% Status Resist"),
N("rs_5_3","Quiet Machine",    "notable",-13,19,1,{"resolve"},{{primary="RSV",value=2},{stat="CooldownReduction",value=2},{stat="CastTimeReduction",value=2}},"+2 RSV, +2% CDR, +2% Cast Speed"),
N("rs_5_4","Calm Under Fire",  "keystone",-11,19,1,{"resolve"},
  {{stat="CalmUnderFire",rule=true}},
  "Above 80% HP: +6% CDR, +10% Status Resist. Below 40% HP: Attack Speed -8%, Damage Reduction +8%."),

-- ════════════════════════════════════════════════════════════
-- 6. JUGGERNAUT  (MIG/VIT)
--    upper-left   x cols [-17,-15,-13,-11]   y rows [-22,-25,-28,-31,-34]
--    entry = y=-22 (connects from Warpath y=-19), keystone = (-11,-34)
-- ════════════════════════════════════════════════════════════
N("jg_1_1","Stone Shoulders","small",-17,-22,1,{"juggernaut"},{{primary="MIG",value=1},{stat="BonusHealth",value=6}},"+1 MIG, +6 Health"),
N("jg_1_2","Iron Lungs",     "small",-15,-22,1,{"juggernaut"},{{primary="VIT",value=1},{stat="Armor",value=2}},"+1 VIT, +2 Armor"),
N("jg_1_3","Frontline Weight","small",-13,-22,1,{"juggernaut"},{{primary="MIG",value=1},{stat="HealthPercent",value=1}},"+1 MIG, +1% Health"),
N("jg_1_4","Holding Ground", "small",-11,-22,1,{"juggernaut"},{{primary="VIT",value=1},{stat="Armor",value=2}},"+1 VIT, +2 Armor"),

N("jg_2_1","Plated Step I",    "small",-17,-25,1,{"juggernaut"},{{stat="Armor",value=3}},"+3 Armor"),
N("jg_2_2","Plated Step II",   "small",-15,-25,1,{"juggernaut"},{{stat="Armor",value=3}},"+3 Armor"),
N("jg_2_3","Thickened Guard I","small",-13,-25,1,{"juggernaut"},{{stat="DamageReduction",value=1}},"+1% Damage Reduction"),
N("jg_2_4","Thickened Guard II","small",-11,-25,1,{"juggernaut"},{{stat="DamageReduction",value=1}},"+1% Damage Reduction"),

N("jg_3_1","Barbed Plates", "small",-17,-28,1,{"juggernaut"},{{stat="Thorns",      value=3}},"+3 Thorns"),
N("jg_3_2","Taunting Frame","small",-15,-28,1,{"juggernaut"},{{stat="TauntDuration",value=10}},"+10% Taunt Duration"),
N("jg_3_3","War Endurance", "small",-13,-28,1,{"juggernaut"},{{stat="BonusHealth", value=12}},"+12 Health"),
N("jg_3_4","Battle Cushion","small",-11,-28,1,{"juggernaut"},{{stat="HpRegen",     value=0.15}},"+0.15% HP Regen/s"),

N("jg_4_1","Held Line",        "small",-17,-31,1,{"juggernaut"},{{stat="Armor",value=3},{stat="BonusHealth",value=8}},"+3 Armor, +8 Health"),
N("jg_4_2","Grit Before Glory","small",-15,-31,1,{"juggernaut"},{{stat="DamageReduction",value=1},{stat="Thorns",value=2}},"+1% DR, +2 Thorns"),
N("jg_4_3","Iron Bastion",     "notable",-13,-31,1,{"juggernaut"},{{primary="MIG",value=2},{primary="VIT",value=2},{stat="Armor",value=5}},"+2 MIG, +2 VIT, +5 Armor"),
N("jg_4_4","Anchored Guard",   "notable",-11,-31,1,{"juggernaut"},{{stat="DamageReduction",value=3},{stat="BonusHealth",value=15}},"+3% DR, +15 Health"),

N("jg_5_1","Pain Returned",   "notable",-17,-34,1,{"juggernaut"},{{stat="Thorns",value=6},{stat="Armor",value=3}},"+6 Thorns, +3 Armor"),
N("jg_5_2","Provoker",        "notable",-15,-34,1,{"juggernaut"},{{stat="TauntDuration",value=20},{stat="DamageReduction",value=1}},"+20% Taunt Duration, +1% DR"),
N("jg_5_3","Rampart Soul",    "notable",-13,-34,1,{"juggernaut"},{{primary="MIG",value=2},{primary="VIT",value=2},{stat="HpRegen",value=0.2}},"+2 MIG, +2 VIT, +0.2% HP Regen/s"),
N("jg_5_4","Unyielding Advance","keystone",-11,-34,1,{"juggernaut"},
  {{stat="UnyieldingAdvance",rule=true},{stat="MovementSpeed",value=-8}},
  "Gain +1% Damage Reduction per enemy within 10 studs, up to 10%. Movement Speed -8%."),

-- ════════════════════════════════════════════════════════════
-- 7. PREDATOR  (PRE/MIG)
--    upper-right  x cols [11,13,15,17]   y rows [-22,-25,-28,-31,-34]
--    entry = y=-22 (connects from Precision y=-19), keystone = (17,-34)
-- ════════════════════════════════════════════════════════════
N("pd_1_1","Hunter's Muscle","small",11,-22,1,{"predator"},{{primary="MIG",value=1}},"+1 MIG"),
N("pd_1_2","Killer's Eye",   "small",13,-22,1,{"predator"},{{primary="PRE",value=1}},"+1 PRE"),
N("pd_1_3","Chase Instinct", "small",15,-22,1,{"predator"},{{primary="MIG",value=1}},"+1 MIG"),
N("pd_1_4","Snap Judgment",  "small",17,-22,1,{"predator"},{{primary="PRE",value=1}},"+1 PRE"),

N("pd_2_1","Fast Draw I",    "small",11,-25,1,{"predator"},{{stat="AttackSpeed",  value=2}},"+2% Attack Speed"),
N("pd_2_2","Rending Point I","small",13,-25,1,{"predator"},{{stat="Penetration",  value=3}},"+3 Penetration"),
N("pd_2_3","Blood Taste I",  "small",15,-25,1,{"predator"},{{stat="Lifesteal",    value=0.5}},"+0.5% Lifesteal"),
N("pd_2_4","Open Ground I",  "small",17,-25,1,{"predator"},{{stat="MovementSpeed",value=2}},"+2% Movement Speed"),

N("pd_3_1","Fast Draw II",    "small",11,-28,1,{"predator"},{{stat="AttackSpeed",  value=2}},"+2% Attack Speed"),
N("pd_3_2","Mark Weakness",   "small",13,-28,1,{"predator"},{{stat="CritChance",   value=2}},"+2% Crit Chance"),
N("pd_3_3","Rending Point II","small",15,-28,1,{"predator"},{{stat="Penetration",  value=3}},"+3 Penetration"),
N("pd_3_4","Blood Taste II",  "small",17,-28,1,{"predator"},{{stat="Lifesteal",    value=0.5}},"+0.5% Lifesteal"),

N("pd_4_1","Open Ground II",  "small",11,-31,1,{"predator"},{{stat="MovementSpeed",  value=2}},"+2% Movement Speed"),
N("pd_4_2","Killer's Reserve","small",13,-31,1,{"predator"},{{stat="KillerInstinct", value=8}},"+8 Killer Instinct"),
N("pd_4_3","Apex Hunter",     "notable",15,-31,1,{"predator"},{{primary="PRE",value=2},{primary="MIG",value=2},{stat="AttackSpeed",value=4}},"+2 PRE, +2 MIG, +4% Attack Speed"),
N("pd_4_4","Fresh Trail",     "notable",17,-31,1,{"predator"},{{stat="MovementSpeed",value=4},{stat="Lifesteal",value=1}},"+4% Movement Speed, +1% Lifesteal"),

N("pd_5_1","Heartseeker",     "notable",11,-34,1,{"predator"},{{stat="CritChance",value=4},{stat="Penetration",value=5}},"+4% Crit Chance, +5 Penetration"),
N("pd_5_2","Feeding Frenzy",  "notable",13,-34,1,{"predator"},{{primary="MIG",value=2},{primary="PRE",value=2},{stat="KillerInstinct",value=10}},"+2 MIG, +2 PRE, +10 Killer Instinct"),
N("pd_5_3","Pursuit Doctrine","notable",15,-34,1,{"predator"},{{stat="AttackSpeed",value=2},{stat="MovementSpeed",value=2},{stat="Penetration",value=2}},"+2% Attack Speed, +2% Movement Speed, +2 Penetration"),
N("pd_5_4","Cull the Weak",   "keystone",17,-34,1,{"predator"},
  {{stat="CullTheWeak",rule=true}},
  "Hits against enemies below 25% HP: +15% Damage and +2% Lifesteal. Hits against full-life enemies deal -5% damage."),

-- ════════════════════════════════════════════════════════════
-- 8. ORACLE  (MAG/PRE)
--    right side   x rows [22,25,28,31,34]   y cols [-3,-1,1,3]
--    entry = x=22, keystone = (34,3)
-- ════════════════════════════════════════════════════════════
N("oc_1_1","Keen Attunement","small",22,-3,1,{"oracle"},{{primary="MAG",value=1}},"+1 MAG"),
N("oc_1_2","Pattern Sight",  "small",22,-1,1,{"oracle"},{{primary="PRE",value=1}},"+1 PRE"),
N("oc_1_3","Luminous Thought","small",22, 1,1,{"oracle"},{{primary="MAG",value=1}},"+1 MAG"),
N("oc_1_4","Exacting Ritual","small",22, 3,1,{"oracle"},{{primary="PRE",value=1}},"+1 PRE"),

N("oc_2_1","Arcanic Aim I",    "small",25,-3,1,{"oracle"},{{stat="CritChance",   value=2}},"+2% Crit Chance"),
N("oc_2_2","Bright Scalpel I", "small",25,-1,1,{"oracle"},{{stat="CritDamage",   value=0.04}},"+0.04x Crit Damage"),
N("oc_2_3","Soothing Formula I","small",25, 1,1,{"oracle"},{{stat="HealingPower", value=4}},"+4 Healing Power"),
N("oc_2_4","Swift Chant I",    "small",25, 3,1,{"oracle"},{{stat="CastTimeReduction",value=2}},"+2% Cast Speed"),

N("oc_3_1","Blessed Focus",     "small",28,-3,1,{"oracle"},{{stat="HealingPercent",value=3}},"+3% Healing"),
N("oc_3_2","Arcanic Aim II",    "small",28,-1,1,{"oracle"},{{stat="CritChance",    value=2}},"+2% Crit Chance"),
N("oc_3_3","Bright Scalpel II", "small",28, 1,1,{"oracle"},{{stat="CritDamage",    value=0.04}},"+0.04x Crit Damage"),
N("oc_3_4","Soothing Formula II","small",28, 3,1,{"oracle"},{{stat="HealingPower",  value=4}},"+4 Healing Power"),

N("oc_4_1","Swift Chant II",   "small",31,-3,1,{"oracle"},{{stat="CastTimeReduction",value=2}},"+2% Cast Speed"),
N("oc_4_2","Living Current",   "small",31,-1,1,{"oracle"},{{stat="LifeEnergy",      value=8}},"+8 Life Energy"),
N("oc_4_3","Seer's Mercy",     "notable",31, 1,1,{"oracle"},{{primary="MAG",value=2},{primary="PRE",value=2},{stat="HealingPercent",value=5}},"+2 MAG, +2 PRE, +5% Healing"),
N("oc_4_4","Surgical Light",   "notable",31, 3,1,{"oracle"},{{stat="CritChance",value=4},{stat="CritDamage",value=0.06}},"+4% Crit Chance, +0.06x Crit Damage"),

N("oc_5_1","Diviner's Pulse",  "notable",34,-3,1,{"oracle"},{{stat="HealingPower",value=8},{stat="CastTimeReduction",value=2}},"+8 Healing Power, +2% Cast Speed"),
N("oc_5_2","Brilliant Recovery","notable",34,-1,1,{"oracle"},{{primary="PRE",value=2},{primary="MAG",value=2},{stat="LifeEnergy",value=10}},"+2 PRE, +2 MAG, +10 Life Energy"),
N("oc_5_3","High Invocation",  "notable",34, 1,1,{"oracle"},{{stat="HealingPercent",value=4},{stat="SkillDamage",value=4}},"+4% Healing, +4% Skill Damage"),
N("oc_5_4","Clarity Surge",    "keystone",34, 3,1,{"oracle"},
  {{stat="ClaritySurge",rule=true},{stat="Lifesteal",value=0}},
  "Critical heals restore 8 Life Energy. Critical skill hits restore 4 Aether. Lifesteal is set to 0."),

-- ════════════════════════════════════════════════════════════
-- 9. SPELLBLADE  (RSV/MAG)
--    bottom-center  x cols [-3,-1,1,3]   y rows [22,25,28,31,34]
--    entry = y=22, keystone = (3,34)
-- ════════════════════════════════════════════════════════════
N("sb_1_1","Arc Reserve",    "small",-3,22,1,{"spellblade"},{{primary="MAG",value=1}},"+1 MAG"),
N("sb_1_2","Focus Reserve",  "small",-1,22,1,{"spellblade"},{{primary="RSV",value=1}},"+1 RSV"),
N("sb_1_3","Mystic Cadence", "small", 1,22,1,{"spellblade"},{{primary="MAG",value=1}},"+1 MAG"),
N("sb_1_4","Ordered Casting","small", 3,22,1,{"spellblade"},{{primary="RSV",value=1}},"+1 RSV"),

N("sb_2_1","Spellclock I",    "small",-3,25,1,{"spellblade"},{{stat="CooldownReduction",value=2}},"+2% CDR"),
N("sb_2_2","Spellclock II",   "small",-1,25,1,{"spellblade"},{{stat="CooldownReduction",value=2}},"+2% CDR"),
N("sb_2_3","Sigil Radius",    "small", 1,25,1,{"spellblade"},{{stat="AoESize",           value=3}},"+3% AoE Size"),
N("sb_2_4","Charged Formula I","small", 3,25,1,{"spellblade"},{{stat="SkillDamage",      value=2}},"+2% Skill Damage"),

N("sb_3_1","Focused Channel I","small",-3,28,1,{"spellblade"},{{stat="CastTimeReduction",value=2}},"+2% Cast Speed"),
N("sb_3_2","Reservoir I",      "small",-1,28,1,{"spellblade"},{{stat="Aether",           value=8}},"+8 Aether"),
N("sb_3_3","Charged Formula II","small", 1,28,1,{"spellblade"},{{stat="SkillDamage",     value=2}},"+2% Skill Damage"),
N("sb_3_4","Resonant Radius",  "small", 3,28,1,{"spellblade"},{{stat="AoESize",          value=3}},"+3% AoE Size"),

N("sb_4_1","Focused Channel II","small",-3,31,1,{"spellblade"},{{stat="CastTimeReduction",value=2}},"+2% Cast Speed"),
N("sb_4_2","Reservoir II",     "small",-1,31,1,{"spellblade"},{{stat="Aether",            value=8}},"+8 Aether"),
N("sb_4_3","Stable Rotation",  "notable", 1,31,1,{"spellblade"},{{primary="RSV",value=2},{primary="MAG",value=2},{stat="CooldownReduction",value=3}},"+2 RSV, +2 MAG, +3% CDR"),
N("sb_4_4","Wide Cast",        "notable", 3,31,1,{"spellblade"},{{stat="AoESize",value=6},{stat="SkillDamage",value=4}},"+6% AoE Size, +4% Skill Damage"),

N("sb_5_1","Spell Reservoir",  "notable",-3,34,1,{"spellblade"},{{primary="MAG",value=2},{stat="Aether",value=12},{stat="SkillDamage",value=2}},"+2 MAG, +12 Aether, +2% Skill Damage"),
N("sb_5_2","Quickened Circuit","notable",-1,34,1,{"spellblade"},{{primary="RSV",value=2},{stat="CastTimeReduction",value=4}},"+2 RSV, +4% Cast Speed"),
N("sb_5_3","Arc Engine",       "notable", 1,34,1,{"spellblade"},{{primary="RSV",value=2},{primary="MAG",value=2},{stat="SkillDamage",value=3},{stat="CooldownReduction",value=2}},"+2 RSV, +2 MAG, +3% Skill Damage, +2% CDR"),
N("sb_5_4","Spell Rhythm",     "keystone", 3,34,1,{"spellblade"},
  {{stat="SpellRhythm",rule=true}},
  "Casting a skill grants 1 Rhythm (5s). Basic attacks consume Rhythm for +8% Attack Speed and +8% Skill Damage on the next hit. Max 3 stacks."),

-- ════════════════════════════════════════════════════════════
-- 10. SANCTUARY  (VIT/RSV)
--     left side   x rows [-22,-25,-28,-31,-34]   y cols [-3,-1,1,3]
--     entry = x=-22, keystone = (-34,3)
-- ════════════════════════════════════════════════════════════
N("sc_1_1","Gentle Step I",    "small",-22,-3,1,{"sanctuary"},{{stat="MovementSpeed",value=2}},"+2% Movement Speed"),
N("sc_1_2","Humble Learning I","small",-22,-1,1,{"sanctuary"},{{stat="XPBonus",      value=2}},"+2% XP Bonus"),
N("sc_1_3","Full Pouch I",     "small",-22, 1,1,{"sanctuary"},{{stat="MeritBonus",   value=3}},"+3% Merit Bonus"),
N("sc_1_4","Kind Touch I",     "small",-22, 3,1,{"sanctuary"},{{stat="HealingPower", value=3}},"+3 Healing Power"),

N("sc_2_1","Shared Breath I",   "small",-25,-3,1,{"sanctuary"},{{stat="HpRegen",      value=0.15}},"+0.15% HP Regen/s"),
N("sc_2_2","Gentle Step II",    "small",-25,-1,1,{"sanctuary"},{{stat="MovementSpeed", value=2}},"+2% Movement Speed"),
N("sc_2_3","Humble Learning II","small",-25, 1,1,{"sanctuary"},{{stat="XPBonus",       value=2}},"+2% XP Bonus"),
N("sc_2_4","Full Pouch II",     "small",-25, 3,1,{"sanctuary"},{{stat="MeritBonus",    value=3}},"+3% Merit Bonus"),

N("sc_3_1","Kind Touch II", "small",-28,-3,1,{"sanctuary"},{{stat="HealingPower",  value=3}},"+3 Healing Power"),
N("sc_3_2","Shared Breath II","small",-28,-1,1,{"sanctuary"},{{stat="HpRegen",     value=0.15}},"+0.15% HP Regen/s"),
N("sc_3_3","Warmth",         "small",-28, 1,1,{"sanctuary"},{{stat="HealingPercent",value=2}},"+2% Healing"),
N("sc_3_4","Life Reservoir", "small",-28, 3,1,{"sanctuary"},{{stat="LifeEnergy",   value=8}},"+8 Life Energy"),

N("sc_4_1","Field Dressing","small",-31,-3,1,{"sanctuary"},{{stat="FlatHpRegen", value=1}},"+1 HP Regen/s"),
N("sc_4_2","Pilgrim's Pace","small",-31,-1,1,{"sanctuary"},{{stat="MovementSpeed",value=2}},"+2% Movement Speed"),
N("sc_4_3","Caretaker",     "notable",-31, 1,1,{"sanctuary"},{{stat="HealingPower",value=6},{stat="HealingPercent",value=4}},"+6 Healing Power, +4% Healing"),
N("sc_4_4","Trailblazer",   "notable",-31, 3,1,{"sanctuary"},{{stat="MovementSpeed",value=5},{stat="HpRegen",value=0.2}},"+5% Movement Speed, +0.2% HP Regen/s"),

N("sc_5_1","Learned Hands","notable",-34,-3,1,{"sanctuary"},{{stat="XPBonus",value=5},{stat="MeritBonus",value=5}},"+5% XP Bonus, +5% Merit Bonus"),
N("sc_5_2","Wellspring",   "notable",-34,-1,1,{"sanctuary"},{{stat="HealingPercent",value=2},{stat="LifeEnergy",value=10},{stat="FlatHpRegen",value=1}},"+2% Healing, +10 Life Energy, +1 HP Regen/s"),
N("sc_5_3","Fellowship",   "notable",-34, 1,1,{"sanctuary"},{{stat="MovementSpeed",value=4},{stat="XPBonus",value=3},{stat="MeritBonus",value=4}},"+4% Movement Speed, +3% XP Bonus, +4% Merit Bonus"),
N("sc_5_4","Patron Saint", "keystone",-34, 3,1,{"sanctuary"},
  {{stat="PatronSaint",rule=true},{stat="DamagePercent",value=-10}},
  "Nearby party members gain 50% of your HealingPower, HealingPercent, XP Bonus, and Merit Bonus from talents. Your Damage -10%."),

-- ════════════════════════════════════════════════════════════
-- 11. BULWARK  (off Juggernaut)
--     upper-left deep   x cols [-17,-15,-13,-11]   y rows [-38,-41,-44,-47,-50]
--     entry = y=-38, keystone = (-11,-50)
-- ════════════════════════════════════════════════════════════
N("bw_1_1","Guard Oath I",    "small",-17,-38,1,{"bulwark"},{{stat="Armor",value=3}},"+3 Armor"),
N("bw_1_2","Guard Oath II",   "small",-15,-38,1,{"bulwark"},{{stat="Armor",value=3}},"+3 Armor"),
N("bw_1_3","Veteran Plate I", "small",-13,-38,1,{"bulwark"},{{stat="DamageReduction",value=1}},"+1% DR"),
N("bw_1_4","Thick Shielding I","small",-11,-38,1,{"bulwark"},{{stat="BonusHealth",value=12}},"+12 Health"),

N("bw_2_1","Resolute Body I", "small",-17,-41,1,{"bulwark"},{{stat="Determination",value=6}},"+6 Determination"),
N("bw_2_2","Hooked Plate I",  "small",-15,-41,1,{"bulwark"},{{stat="Thorns",       value=3}},"+3 Thorns"),
N("bw_2_3","Guarded Posture I","small",-13,-41,1,{"bulwark"},{{stat="TauntDuration",value=10}},"+10% Taunt Duration"),
N("bw_2_4","Bastion Breath",  "small",-11,-41,1,{"bulwark"},{{stat="HpRegen",      value=0.15}},"+0.15% HP Regen/s"),

N("bw_3_1","Veteran Plate II",  "small",-17,-44,1,{"bulwark"},{{stat="DamageReduction",value=1}},"+1% DR"),
N("bw_3_2","Thick Shielding II","small",-15,-44,1,{"bulwark"},{{stat="BonusHealth",   value=12}},"+12 Health"),
N("bw_3_3","Resolute Body II",  "small",-13,-44,1,{"bulwark"},{{stat="Determination", value=6}},"+6 Determination"),
N("bw_3_4","Hooked Plate II",   "small",-11,-44,1,{"bulwark"},{{stat="Thorns",        value=3}},"+3 Thorns"),

N("bw_4_1","Guarded Posture II","small",-17,-47,1,{"bulwark"},{{stat="TauntDuration",value=10}},"+10% Taunt Duration"),
N("bw_4_2","Adamant Frame",    "small",-15,-47,1,{"bulwark"},{{stat="HealthPercent", value=1}},"+1% Health"),
N("bw_4_3","Shield Eater",     "notable",-13,-47,1,{"bulwark"},{{stat="Armor",value=5},{stat="DamageReduction",value=1}},"+5 Armor, +1% DR"),
N("bw_4_4","Defender's Rule",  "notable",-11,-47,1,{"bulwark"},{{stat="TauntDuration",value=15},{stat="Determination",value=10}},"+15% Taunt Duration, +10 Determination"),

N("bw_5_1","Grudgeborn",    "notable",-17,-50,1,{"bulwark"},{{stat="Thorns",value=6},{stat="BonusHealth",value=12}},"+6 Thorns, +12 Health"),
N("bw_5_2","Adamant Oath",  "notable",-15,-50,1,{"bulwark"},{{stat="HealthPercent",value=2},{stat="HpRegen",value=0.2}},"+2% Health, +0.2% HP Regen/s"),
N("bw_5_3","Thickest Wall", "notable",-13,-50,1,{"bulwark"},{{stat="Armor",value=6},{stat="BonusHealth",value=15},{stat="DamageReduction",value=1}},"+6 Armor, +15 Health, +1% DR"),
N("bw_5_4","Last Bastion",  "keystone",-11,-50,1,{"bulwark"},
  {{stat="LastBastion",rule=true}},
  "While Determination > 70%: +8% Damage Reduction and +20% Taunt Duration. While Determination < 20%: Movement Speed -10%."),

-- ════════════════════════════════════════════════════════════
-- 12. HUNTMASTER  (off Predator)
--     upper-right deep  x cols [11,13,15,17]   y rows [-38,-41,-44,-47,-50]
--     entry = y=-38, keystone = (17,-50)
-- ════════════════════════════════════════════════════════════
N("hm_1_1","Blood Mark I",      "small",11,-38,1,{"huntmaster"},{{stat="CritChance",   value=2}},"+2% Crit Chance"),
N("hm_1_2","Blood Mark II",     "small",13,-38,1,{"huntmaster"},{{stat="CritChance",   value=2}},"+2% Crit Chance"),
N("hm_1_3","Quick Feet I",      "small",15,-38,1,{"huntmaster"},{{stat="MovementSpeed",value=2}},"+2% Movement Speed"),
N("hm_1_4","Killer's Wheel I",  "small",17,-38,1,{"huntmaster"},{{stat="AttackSpeed",  value=2}},"+2% Attack Speed"),

N("hm_2_1","Open Rib I",        "small",11,-41,1,{"huntmaster"},{{stat="Penetration",  value=3}},"+3 Penetration"),
N("hm_2_2","Instinct Reserve I","small",13,-41,1,{"huntmaster"},{{stat="KillerInstinct",value=8}},"+8 Killer Instinct"),
N("hm_2_3","Quick Feet II",     "small",15,-41,1,{"huntmaster"},{{stat="MovementSpeed",value=2}},"+2% Movement Speed"),
N("hm_2_4","Killer's Wheel II", "small",17,-41,1,{"huntmaster"},{{stat="AttackSpeed",  value=2}},"+2% Attack Speed"),

N("hm_3_1","Open Rib II",        "small",11,-44,1,{"huntmaster"},{{stat="Penetration",   value=3}},"+3 Penetration"),
N("hm_3_2","Instinct Reserve II","small",13,-44,1,{"huntmaster"},{{stat="KillerInstinct", value=8}},"+8 Killer Instinct"),
N("hm_3_3","Sharp Intent I",     "small",15,-44,1,{"huntmaster"},{{stat="CritDamage",    value=0.04}},"+0.04x Crit Damage"),
N("hm_3_4","Sharp Intent II",    "small",17,-44,1,{"huntmaster"},{{stat="CritDamage",    value=0.04}},"+0.04x Crit Damage"),

N("hm_4_1","Sightline",    "small",11,-47,1,{"huntmaster"},{{primary="PRE",value=1}},"+1 PRE"),
N("hm_4_2","Draw Weight",  "small",13,-47,1,{"huntmaster"},{{primary="MIG",value=1}},"+1 MIG"),
N("hm_4_3","First Blood",  "notable",15,-47,1,{"huntmaster"},{{stat="CritChance",value=4},{stat="Penetration",value=4}},"+4% Crit Chance, +4 Penetration"),
N("hm_4_4","Running Kill", "notable",17,-47,1,{"huntmaster"},{{stat="MovementSpeed",value=4},{stat="AttackSpeed",value=3}},"+4% Movement Speed, +3% Attack Speed"),

N("hm_5_1","Cold Magazine",    "notable",11,-50,1,{"huntmaster"},{{stat="KillerInstinct",value=12},{stat="CritDamage",value=0.05}},"+12 Killer Instinct, +0.05x Crit Damage"),
N("hm_5_2","Long Pursuit",     "notable",13,-50,1,{"huntmaster"},{{primary="PRE",value=1},{primary="MIG",value=1},{stat="MovementSpeed",value=3}},"+1 PRE, +1 MIG, +3% Movement Speed"),
N("hm_5_3","Merciless Trail",  "notable",15,-50,1,{"huntmaster"},{{stat="Penetration",value=5},{stat="CritChance",value=2},{stat="AttackSpeed",value=2}},"+5 Penetration, +2% Crit Chance, +2% Attack Speed"),
N("hm_5_4","Relentless Quarry","keystone",17,-50,1,{"huntmaster"},
  {{stat="RelentlessQuarry",rule=true}},
  "Hitting the same enemy 4 times within 3s marks it for 6s: +10% Crit Chance and +10 Penetration against it. Hitting a different target removes the mark."),

-- ════════════════════════════════════════════════════════════
-- 13. GRACE  (off Oracle)
--     far right   x rows [38,41,44,47,50]   y cols [-3,-1,1,3]
--     entry = x=38, keystone = (50,3)
-- ════════════════════════════════════════════════════════════
N("gr_1_1","Soft Light I",         "small",38,-3,1,{"grace"},{{stat="HealingPower",  value=4}},"+4 Healing Power"),
N("gr_1_2","Soft Light II",        "small",38,-1,1,{"grace"},{{stat="HealingPower",  value=4}},"+4 Healing Power"),
N("gr_1_3","Open Palms I",         "small",38, 1,1,{"grace"},{{stat="HealingPercent",value=3}},"+3% Healing"),
N("gr_1_4","Swift Prayer I",       "small",38, 3,1,{"grace"},{{stat="CastTimeReduction",value=2}},"+2% Cast Speed"),

N("gr_2_1","Living Wells I",       "small",41,-3,1,{"grace"},{{stat="LifeEnergy",   value=8}},"+8 Life Energy"),
N("gr_2_2","Comforting Presence I","small",41,-1,1,{"grace"},{{stat="HpRegen",       value=0.15}},"+0.15% HP Regen/s"),
N("gr_2_3","Open Palms II",        "small",41, 1,1,{"grace"},{{stat="HealingPercent",value=3}},"+3% Healing"),
N("gr_2_4","Swift Prayer II",      "small",41, 3,1,{"grace"},{{stat="CastTimeReduction",value=2}},"+2% Cast Speed"),

N("gr_3_1","Living Wells II",       "small",44,-3,1,{"grace"},{{stat="LifeEnergy",    value=8}},"+8 Life Energy"),
N("gr_3_2","Comforting Presence II","small",44,-1,1,{"grace"},{{stat="HpRegen",        value=0.15}},"+0.15% HP Regen/s"),
N("gr_3_3","Clear Vision I",        "small",44, 1,1,{"grace"},{{primary="MAG",value=1}},"+1 MAG"),
N("gr_3_4","Clear Vision II",       "small",44, 3,1,{"grace"},{{primary="PRE",value=1}},"+1 PRE"),

N("gr_4_1","Sanctuary Step",   "small",47,-3,1,{"grace"},{{stat="MovementSpeed",value=2}},"+2% Movement Speed"),
N("gr_4_2","Breath Returned",  "small",47,-1,1,{"grace"},{{stat="FlatHpRegen",  value=1}},"+1 HP Regen/s"),
N("gr_4_3","Merciful Timing",  "notable",47, 1,1,{"grace"},{{stat="HealingPower",value=6},{stat="CastTimeReduction",value=4}},"+6 Healing Power, +4% Cast Speed"),
N("gr_4_4","Overflowing Grace","notable",47, 3,1,{"grace"},{{stat="HealingPercent",value=5},{stat="LifeEnergy",value=10}},"+5% Healing, +10 Life Energy"),

N("gr_5_1","Walking Chapel",     "notable",50,-3,1,{"grace"},{{stat="MovementSpeed",value=4},{stat="HpRegen",value=0.2}},"+4% Movement Speed, +0.2% HP Regen/s"),
N("gr_5_2","Restoration Theory","notable",50,-1,1,{"grace"},{{primary="MAG",value=1},{primary="PRE",value=1},{stat="HealingPower",value=5}},"+1 MAG, +1 PRE, +5 Healing Power"),
N("gr_5_3","Kindled Hope",      "notable",50, 1,1,{"grace"},{{stat="FlatHpRegen",value=1},{stat="HealingPercent",value=3},{stat="LifeEnergy",value=6}},"+1 HP Regen/s, +3% Healing, +6 Life Energy"),
N("gr_5_4","Shared Grace",      "keystone",50, 3,1,{"grace"},
  {{stat="SharedGrace",rule=true},{stat="Lifesteal",value=-50}},
  "Overhealing a target grants 20% of the excess as a 4s heal-over-time. Your Lifesteal is reduced by 50%."),

-- ════════════════════════════════════════════════════════════
-- 14. STORMWEAVE  (off Spellblade)
--     far bottom   x cols [-3,-1,1,3]   y rows [38,41,44,47,50]
--     entry = y=38, keystone = (3,50)
-- ════════════════════════════════════════════════════════════
N("sw_1_1","Aether Loom I",   "small",-3,38,1,{"stormweave"},{{stat="Aether",value=8}},"+8 Aether"),
N("sw_1_2","Aether Loom II",  "small",-1,38,1,{"stormweave"},{{stat="Aether",value=8}},"+8 Aether"),
N("sw_1_3","Wide Spiral I",   "small", 1,38,1,{"stormweave"},{{stat="AoESize",value=4}},"+4% AoE Size"),
N("sw_1_4","Wild Formula I",  "small", 3,38,1,{"stormweave"},{{stat="SkillDamage",value=3}},"+3% Skill Damage"),

N("sw_2_1","Quick Sigils I",   "small",-3,41,1,{"stormweave"},{{stat="CastTimeReduction",value=2}},"+2% Cast Speed"),
N("sw_2_2","Charged Reserve I","small",-1,41,1,{"stormweave"},{{stat="CooldownReduction", value=1}},"+1% CDR"),
N("sw_2_3","Wide Spiral II",   "small", 1,41,1,{"stormweave"},{{stat="AoESize",           value=4}},"+4% AoE Size"),
N("sw_2_4","Wild Formula II",  "small", 3,41,1,{"stormweave"},{{stat="SkillDamage",        value=3}},"+3% Skill Damage"),

N("sw_3_1","Quick Sigils II",   "small",-3,44,1,{"stormweave"},{{stat="CastTimeReduction",value=2}},"+2% Cast Speed"),
N("sw_3_2","Charged Reserve II","small",-1,44,1,{"stormweave"},{{stat="CooldownReduction", value=1}},"+1% CDR"),
N("sw_3_3","Spell Battery I",   "small", 1,44,1,{"stormweave"},{{stat="DamagePercent",     value=2}},"+2% Damage"),
N("sw_3_4","Spell Battery II",  "small", 3,44,1,{"stormweave"},{{stat="DamagePercent",     value=2}},"+2% Damage"),

N("sw_4_1","Crackling Intellect","small",-3,47,1,{"stormweave"},{{primary="MAG",value=1}},"+1 MAG"),
N("sw_4_2","Measured Surge",    "small",-1,47,1,{"stormweave"},{{primary="RSV",value=1}},"+1 RSV"),
N("sw_4_3","Spellwake",         "notable", 1,47,1,{"stormweave"},{{stat="SkillDamage",value=5},{stat="AoESize",value=5}},"+5% Skill Damage, +5% AoE Size"),
N("sw_4_4","Burning Diagram",   "notable", 3,47,1,{"stormweave"},{{stat="DamagePercent",value=4},{stat="CastTimeReduction",value=3}},"+4% Damage, +3% Cast Speed"),

N("sw_5_1","Overfull Vessel","notable",-3,50,1,{"stormweave"},{{stat="Aether",value=14},{stat="CooldownReduction",value=2}},"+14 Aether, +2% CDR"),
N("sw_5_2","Master Conduit", "notable",-1,50,1,{"stormweave"},{{primary="MAG",value=1},{primary="RSV",value=1},{stat="SkillDamage",value=4}},"+1 MAG, +1 RSV, +4% Skill Damage"),
N("sw_5_3","Echo Chamber",   "notable", 1,50,1,{"stormweave"},{{stat="AoESize",value=6},{stat="DamagePercent",value=2}},"+6% AoE Size, +2% Damage"),
N("sw_5_4","Eye of the Storm","keystone", 3,50,1,{"stormweave"},
  {{stat="EyeOfTheStorm",rule=true}},
  "Skills hitting only 1 target deal +18% damage. Skills hitting 4+ targets gain +20% AoE Size. Resource cost +10%."),

-- ════════════════════════════════════════════════════════════
-- 15. FORTUNE  (off Sanctuary)
--     far left   x rows [-38,-41,-44,-47,-50]   y cols [-3,-1,1,3]
--     entry = x=-38, keystone = (-50,3)
-- ════════════════════════════════════════════════════════════
N("fo_1_1","Lucky Coin I",      "small",-38,-3,1,{"fortune"},{{stat="MeritBonus",   value=3}},"+3% Merit Bonus"),
N("fo_1_2","Lucky Coin II",     "small",-38,-1,1,{"fortune"},{{stat="MeritBonus",   value=3}},"+3% Merit Bonus"),
N("fo_1_3","Eager Mind I",      "small",-38, 1,1,{"fortune"},{{stat="XPBonus",      value=2}},"+2% XP Bonus"),
N("fo_1_4","Traveler's Pace I", "small",-38, 3,1,{"fortune"},{{stat="MovementSpeed",value=2}},"+2% Movement Speed"),

N("fo_2_1","Field Lessons I",  "small",-41,-3,1,{"fortune"},{{stat="FlatHpRegen", value=1}},"+1 HP Regen/s"),
N("fo_2_2","Small Harvest I",  "small",-41,-1,1,{"fortune"},{{stat="Lifesteal",   value=0.5}},"+0.5% Lifesteal"),
N("fo_2_3","Eager Mind II",    "small",-41, 1,1,{"fortune"},{{stat="XPBonus",     value=2}},"+2% XP Bonus"),
N("fo_2_4","Traveler's Pace II","small",-41, 3,1,{"fortune"},{{stat="MovementSpeed",value=2}},"+2% Movement Speed"),

N("fo_3_1","Field Lessons II","small",-44,-3,1,{"fortune"},{{stat="FlatHpRegen",   value=1}},"+1 HP Regen/s"),
N("fo_3_2","Small Harvest II","small",-44,-1,1,{"fortune"},{{stat="Lifesteal",     value=0.5}},"+0.5% Lifesteal"),
N("fo_3_3","Safe Route I",    "small",-44, 1,1,{"fortune"},{{stat="DamageReduction",value=1}},"+1% DR"),
N("fo_3_4","Safe Route II",   "small",-44, 3,1,{"fortune"},{{stat="DamageReduction",value=1}},"+1% DR"),

N("fo_4_1","Learned Route", "small",-47,-3,1,{"fortune"},{{primary="RSV",value=1}},"+1 RSV"),
N("fo_4_2","Patient Work",  "small",-47,-1,1,{"fortune"},{{primary="VIT",value=1}},"+1 VIT"),
N("fo_4_3","Packed Caravan","notable",-47, 1,1,{"fortune"},{{stat="MeritBonus",value=5},{stat="XPBonus",value=3}},"+5% Merit Bonus, +3% XP Bonus"),
N("fo_4_4","Road Wisdom",   "notable",-47, 3,1,{"fortune"},{{stat="MovementSpeed",value=4},{stat="FlatHpRegen",value=1}},"+4% Movement Speed, +1 HP Regen/s"),

N("fo_5_1","Lasting Effort", "notable",-50,-3,1,{"fortune"},{{primary="VIT",value=1},{primary="RSV",value=1},{stat="Lifesteal",value=0.5}},"+1 VIT, +1 RSV, +0.5% Lifesteal"),
N("fo_5_2","Veteran Trader", "notable",-50,-1,1,{"fortune"},{{stat="MeritBonus",value=6},{stat="XPBonus",value=2}},"+6% Merit Bonus, +2% XP Bonus"),
N("fo_5_3","Untaxed Breath", "notable",-50, 1,1,{"fortune"},{{stat="MovementSpeed",value=2},{stat="DamageReduction",value=1},{stat="FlatHpRegen",value=1}},"+2% Movement Speed, +1% DR, +1 HP Regen/s"),
N("fo_5_4","Fortune Favors", "keystone",-50, 3,1,{"fortune"},
  {{stat="FortuneFavors",rule=true},{stat="DamagePercent",value=-6},{stat="SkillDamage",value=-6}},
  "You and nearby party members gain 50% of your XP Bonus and Merit Bonus from talents. Your Damage and Skill Damage each -6%."),

} -- end TalentTreeConfig.Nodes

-- ═══════════════════════════════════════════════════════════
-- EDGES  (bidirectional links)
-- ═══════════════════════════════════════════════════════════
--[[
  Within-sector edges follow the 5×4 grid:
    Horizontal: (r,c)–(r,c+1) for c=1..3, r=1..5
    Vertical:   (r,c)–(r+1,c) for r=1..4, c=1..4
  Inter-sector bridges are listed explicitly at the end.
]]

local function gridEdges(p)
	-- Returns horizontal + vertical edges for sector prefix p
	local edges = {}
	local rows, cols = {1,2,3,4,5}, {1,2,3,4}
	-- Horizontal
	for _, r in ipairs(rows) do
		for c = 1, 3 do
			edges[#edges+1] = { p.."_"..r.."_"..c, p.."_"..r.."_"..(c+1) }
		end
	end
	-- Vertical
	for _, c in ipairs(cols) do
		for r = 1, 4 do
			edges[#edges+1] = { p.."_"..r.."_"..c, p.."_"..(r+1).."_"..c }
		end
	end
	return edges
end

TalentTreeConfig.Edges = {}

local function addEdges(list)
	for _, e in ipairs(list) do
		TalentTreeConfig.Edges[#TalentTreeConfig.Edges+1] = e
	end
end

-- ── Within-sector grids ────────────────────────────────────
local sectors = {"wp","lb","pr","at","rs","jg","pd","oc","sb","sc","bw","hm","gr","sw","fo"}
for _, s in ipairs(sectors) do
	addEdges(gridEdges(s))
end

-- ── Origin → primary sector entries ───────────────────────
-- Connect Origin to the two innermost entry nodes of each primary sector
addEdges({
	{ "start", "wp_1_4" }, { "start", "wp_1_1" },  -- closest col to center = c4 (x=-11)
	{ "start", "lb_1_1" }, { "start", "lb_1_4" },  -- both outer cols (x=-3 and x=3)
	{ "start", "pr_1_1" }, { "start", "pr_1_4" },  -- closest col to center = c1 (x=11)
	{ "start", "at_1_1" }, { "start", "at_1_4" },
	{ "start", "rs_1_4" }, { "start", "rs_1_1" },  -- closest col = c4 (x=-11)
})

-- ── Primary → Hybrid bridges ───────────────────────────────

-- Warpath (y=-19 row) → Juggernaut (y=-22 row): same x range, direct connection
addEdges({
	{ "wp_5_1", "jg_1_1" }, { "wp_5_2", "jg_1_2" },
	{ "wp_5_3", "jg_1_3" }, { "wp_5_4", "jg_1_4" },
})

-- Lifeblood deep → Juggernaut entry (diagonal bridge: left side of LB → right side of JG)
addEdges({
	{ "lb_5_1", "jg_1_4" },  -- (-3,-28) → (-11,-22)
	{ "lb_4_1", "jg_1_4" },  -- shorter path too (-3,-25) → (-11,-22)
})

-- Precision (y=-19 row) → Predator (y=-22 row): same x range, direct
addEdges({
	{ "pr_5_1", "pd_1_1" }, { "pr_5_2", "pd_1_2" },
	{ "pr_5_3", "pd_1_3" }, { "pr_5_4", "pd_1_4" },
})

-- Warpath deep → Predator entry (long cross-tree bridge: MIG can path into PRE/MIG hybrid)
addEdges({
	{ "wp_5_4", "pd_1_1" },  -- (-11,-19) → (11,-22)  [long diagonal]
})

-- Attunement (y=7 entry row) → Oracle (x=22 entry): upper col of AT to upper col of OC
addEdges({
	{ "at_1_4", "oc_1_1" }, { "at_1_3", "oc_1_2" },  -- (17,7)→(22,-3)
})

-- Precision deep → Oracle entry (diagonal: right edge of PR to left edge of OC)
addEdges({
	{ "pr_5_4", "oc_1_1" }, { "pr_5_3", "oc_1_2" },  -- (17,-19)→(22,-3)
})

-- Attunement deep (y=19 row) → Spellblade entry (y=22 row): right cols of AT to right of SB
addEdges({
	{ "at_5_1", "sb_1_4" }, { "at_5_2", "sb_1_3" },  -- (11,19)→(3,22)
})

-- Resolve deep (y=19 row) → Spellblade entry: left cols of RS to left cols of SB
addEdges({
	{ "rs_5_4", "sb_1_1" }, { "rs_5_3", "sb_1_2" },  -- (-11,19)→(-3,22)
})

-- Resolve entry (y=7 row) → Sanctuary entry (x=-22): upper-left RS to upper SC
addEdges({
	{ "rs_1_1", "sc_1_1" },  -- (-17,7) → (-22,-3)
	{ "rs_1_2", "sc_1_2" },  -- (-15,7) → (-22,-1)
})

-- Lifeblood entry → Sanctuary entry (long bridge: top-center to far-left)
addEdges({
	{ "lb_1_1", "sc_1_1" },  -- (-3,-16) → (-22,-3)
	{ "lb_1_2", "sc_1_2" },
})

-- ── Hybrid → Outer branch bridges ─────────────────────────

-- Juggernaut (y=-34 row) → Bulwark (y=-38 row): same x range, direct
addEdges({
	{ "jg_5_1", "bw_1_1" }, { "jg_5_2", "bw_1_2" },
	{ "jg_5_3", "bw_1_3" }, { "jg_5_4", "bw_1_4" },
})

-- Predator (y=-34 row) → Huntmaster (y=-38 row): same x range, direct
addEdges({
	{ "pd_5_1", "hm_1_1" }, { "pd_5_2", "hm_1_2" },
	{ "pd_5_3", "hm_1_3" }, { "pd_5_4", "hm_1_4" },
})

-- Oracle (x=34 row) → Grace (x=38 row): same y range, direct
addEdges({
	{ "oc_5_1", "gr_1_1" }, { "oc_5_2", "gr_1_2" },
	{ "oc_5_3", "gr_1_3" }, { "oc_5_4", "gr_1_4" },
})

-- Spellblade (y=34 row) → Stormweave (y=38 row): same x range, direct
addEdges({
	{ "sb_5_1", "sw_1_1" }, { "sb_5_2", "sw_1_2" },
	{ "sb_5_3", "sw_1_3" }, { "sb_5_4", "sw_1_4" },
})

-- Sanctuary (x=-34 row) → Fortune (x=-38 row): same y range, direct
addEdges({
	{ "sc_5_1", "fo_1_1" }, { "sc_5_2", "fo_1_2" },
	{ "sc_5_3", "fo_1_3" }, { "sc_5_4", "fo_1_4" },
})

-- ═══════════════════════════════════════════════════════════
-- START NODE ID
-- ═══════════════════════════════════════════════════════════

TalentTreeConfig.StartNodeId = "start"

-- ═══════════════════════════════════════════════════════════
-- HELPERS  (cached — data is static; tables built once on first call)
-- ═══════════════════════════════════════════════════════════

local cachedNodeMap = nil
local cachedAdjList = nil

--- Build a node lookup table  { [id] = nodeDef }
function TalentTreeConfig.GetNodeMap()
	if cachedNodeMap then return cachedNodeMap end
	local map = {}
	for _, node in ipairs(TalentTreeConfig.Nodes) do
		map[node.id] = node
	end
	cachedNodeMap = map
	return map
end

--- Build adjacency list  { [id] = { neighborId, ... } }
function TalentTreeConfig.GetAdjacencyList()
	if cachedAdjList then return cachedAdjList end
	local adj = {}
	for _, node in ipairs(TalentTreeConfig.Nodes) do
		adj[node.id] = {}
	end
	for _, edge in ipairs(TalentTreeConfig.Edges) do
		table.insert(adj[edge[1]], edge[2])
		table.insert(adj[edge[2]], edge[1])
	end
	cachedAdjList = adj
	return adj
end

--- Return count of allocatable nodes (excludes free start node)
function TalentTreeConfig.GetNodeCount()
	return #TalentTreeConfig.Nodes
end

return TalentTreeConfig
