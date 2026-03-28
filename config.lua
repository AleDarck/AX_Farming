-- ============================================================
--  AX_Farming | config.lua
--  Sistema de cultivo de vegetales
-- ============================================================

Config = {}

-- ─── GENERAL ────────────────────────────────────────────────
Config.MaxPlantsPerPlayer   = 10        -- Límite de plantas activas por jugador
Config.MinDistanceBetween   = 2.0       -- Distancia mínima entre plantas (metros)
Config.InteractionDistance  = 2.0       -- Distancia para que ox_target detecte la planta
Config.UpdateInterval       = 5         -- Cada cuántos minutos el servidor actualiza las plantas
Config.RotTimer             = 30        -- Minutos tras estar al 100% sin cosechar para que empiece la pudrición

-- ─── ÍTEMS DE INVENTARIO ────────────────────────────────────
Config.WaterItem        = 'water_bottle'     -- Ítem para regar
Config.FertilizerItem   = 'fertilizer'       -- Ítem para fertilizar

-- ─── VALORES DE AGUA & FERTILIZANTE ─────────────────────────
Config.WaterPerUse       = 50   -- Cuánto agua da cada riego (0-100)
Config.FertilizerPerUse  = 75   -- Cuánto fertilizante da cada aplicación (0-100)

-- ─── DECAIMIENTO POR CICLO (cada UpdateInterval minutos) ────
Config.WaterDecayPerCycle        = 15   -- Agua que baja por ciclo
Config.FertilizerDecayPerCycle   = 10   -- Fertilizante que baja por ciclo
Config.HealthDecayNoWater        = 10   -- Salud que pierde si agua = 0
Config.GrowthBasePerCycle        = 8    -- Crecimiento base por ciclo
Config.GrowthBonusFertilizer     = 5    -- Crecimiento extra si tiene fertilizante > 0
Config.GrowthPenaltyLowWater     = 4    -- Reducción de crecimiento si agua < 20

-- ─── SUELO PERMITIDO ─────────────────────────────────────────
-- Materiales de superficie donde se puede plantar
Config.AllowedGroundMaterials = {
    [1] = true,   -- DIRT
    [2] = true,   -- GRASS
    [3] = true,   -- GRASS_TALL
    [131] = true, -- MUD
    [138] = true, -- SAND_COMPACT
}

-- ─── PLANTAS ─────────────────────────────────────────────────
-- Puedes agregar más entradas siguiendo la misma estructura.
-- Props: cada planta define 4 props según etapa de crecimiento.
--   stage1 = recién plantada (semilla)
--   stage2 = brote
--   stage3 = creciendo
--   stage4 = cosechable (100%)
-- harvestMin / harvestMax: rango base de ítems cosechados
-- bonusPerFertilizer: ítems extra por cada 10% de fertilizante acumulado

Config.Plants = {

    ['semilla_tomate'] = {
        label           = 'Tomate',
        seedItem        = 'semilla_tomate',
        harvestItem     = 'tomate',
        harvestMin      = 2,
        harvestMax      = 5,
        bonusPerFert    = 1,
        growTime        = 40,
        props = {
            stage1 = 'prop_pot_plant_03a',   -- semilla / recien plantada (maceta pequena)
            stage2 = 'bkr_prop_weed_bud_02a', -- brote (DLC mpbiker, basegame en Online)
            stage3 = 'prop_weed_01',          -- creciendo
            stage4 = 'prop_weed_02',          -- cosechable
        },
    },

    ['semilla_zanahoria'] = {
        label           = 'Zanahoria',
        seedItem        = 'semilla_zanahoria',
        harvestItem     = 'zanahoria',
        harvestMin      = 3,
        harvestMax      = 6,
        bonusPerFert    = 1,
        growTime        = 30,
        props = {
            stage1 = 'prop_pot_plant_03a',
            stage2 = 'bkr_prop_weed_bud_pruned_01a',
            stage3 = 'prop_weed_01',
            stage4 = 'prop_weed_02',
        },
    },

    ['semilla_maiz'] = {
        label           = 'Maiz',
        seedItem        = 'semilla_maiz',
        harvestItem     = 'maiz',
        harvestMin      = 4,
        harvestMax      = 8,
        bonusPerFert    = 2,
        growTime        = 60,
        props = {
            stage1 = 'prop_pot_plant_03a',
            stage2 = 'bkr_prop_weed_bud_02a',
            stage3 = 'prop_weed_02',
            stage4 = 'prop_weed_01',
        },
    },
}

-- ─── OX_TARGET OPTIONS ───────────────────────────────────────
Config.TargetOptions = {
    water = {
        label = 'Regar planta',
        icon  = 'fa-solid fa-droplet',
    },
    fertilize = {
        label = 'Fertilizar planta',
        icon  = 'fa-solid fa-seedling',
    },
    harvest = {
        label = 'Cosechar planta',
        icon  = 'fa-solid fa-wheat-awn',
    },
    inspect = {
        label = 'Inspeccionar planta',
        icon  = 'fa-solid fa-magnifying-glass',
    },
    remove = {
        label = 'Arrancar planta',
        icon  = 'fa-solid fa-trash',
    },
}