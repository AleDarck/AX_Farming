Config = {}

-- =============================================
--  CONFIGURACIÓN GENERAL
-- =============================================

-- Distancia mínima entre plantas (en metros)
Config.MinPlantDistance = 2.0

-- Distancia máxima al suelo para plantar (raycast hacia abajo)
Config.MaxGroundDistance = 2.0

-- Intervalo de crecimiento pasivo (en milisegundos) - cada cuanto sube el %
Config.GrowthInterval = 60000 -- 1 minuto

-- Cada cuánto el servidor sincroniza/guarda las plantas en DB (ms)
Config.SaveInterval = 300000 -- 5 minutos

-- =============================================
--  SISTEMA DE TIEMPO
-- =============================================

-- Tiempo para madurar al 100% desde 0% (en segundos) - referencia visual
-- El crecimiento real lo controla GrowthInterval, esto es solo para calcular
-- el tiempo estimado que se muestra en el menú
Config.EstimatedGrowthTime = 3600 -- 1 hora base (se ajusta según agua/fert)

-- Tiempo que tiene la planta al 100% antes de pudrirse (segundos)
Config.RotTime = 1800 -- 30 minutos para pudrirse si no se cosecha

-- Tiempo que tiene la planta sin agua antes de morir (segundos)
Config.DeathTime = 600 -- 10 minutos sin agua antes de pudrirse

-- =============================================
--  PLANTAS
-- =============================================

Config.Plants = {
    ['semilla_tomate'] = {
        label          = 'Tomate',
        seedItem       = 'semilla_tomate',
        harvestItem    = 'tomate',       -- item que da al cosechar
        baseHarvest    = 2,              -- cantidad base cosechada
        maxHarvest     = 6,              -- máximo con 100% fertilizante
        waterMax       = 100,
        fertMax        = 6,              -- máximo de fertilizante (1-6)
        -- Crecimiento pasivo: % por intervalo sin agua ni fertilizante
        passiveGrowth  = 1,
        -- Crecimiento al regar: +% extra por riego
        waterGrowth    = 8,
        -- Crecimiento al fertilizar: +% extra por fertilización
        fertGrowth     = 5,
        -- Agua que consume por intervalo pasivo
        waterDecay     = 3,
        -- Props según estado de crecimiento
        props = {
            [1] = 'prop_pot_plant_03a',        -- etapa 1: 0-33%   (semilla brotando)
            [2] = 'prop_weed_01',  -- etapa 2: 34-66%  (planta joven)
            [3] = 'prop_weed_02',  -- etapa 3: 67-100% (planta madura)
        },
        -- Animación de plantado
        plantAnim = {
            animDict = 'amb@world_human_gardener_plant@male@idle_a',
            anim     = 'idle_a',
            flags    = 1,
        },
    },
    ['semilla_zanahoria'] = {
        label          = 'Zanahoria',
        seedItem       = 'semilla_zanahoria',
        harvestItem    = 'zanahoria',
        baseHarvest    = 2,
        maxHarvest     = 6,
        waterMax       = 100,
        fertMax        = 6,
        passiveGrowth  = 1,
        waterGrowth    = 7,
        fertGrowth     = 5,
        waterDecay     = 4,
        props = {
            [1] = 'prop_cs_dildo_01',
            [2] = 'prop_weed_02_small_01a',
            [3] = 'prop_weed_03_small_01a',
        },
        plantAnim = {
            animDict = 'amb@world_human_gardener_plant@male@idle_a',
            anim     = 'idle_a',
            flags    = 1,
        },
    },
    ['semilla_maiz'] = {
        label          = 'Maíz',
        seedItem       = 'semilla_maiz',
        harvestItem    = 'maiz',
        baseHarvest    = 2,
        maxHarvest     = 6,
        waterMax       = 100,
        fertMax        = 6,
        passiveGrowth  = 1,
        waterGrowth    = 6,
        fertGrowth     = 6,
        waterDecay     = 3,
        props = {
            [1] = 'prop_cs_dildo_01',
            [2] = 'prop_weed_02_small_01a',
            [3] = 'prop_weed_03_small_01a',
        },
        plantAnim = {
            animDict = 'amb@world_human_gardener_plant@male@idle_a',
            anim     = 'idle_a',
            flags    = 1,
        },
    },
}

-- =============================================
--  ANIMACIONES DE ACCIONES
-- =============================================

Config.Animations = {
    water = {
        animDict = 'amb@world_human_gardener_plant@male@idle_a',
        anim     = 'idle_a',
        flags    = 1,
        duration = 4000,
        label    = 'Regando planta...',
    },
    fertilize = {
        animDict = 'missheistdockssetup1clipboard@base',
        anim     = 'base',
        flags    = 49,
        duration = 5000,
        label    = 'Fertilizando planta...',
    },
    harvest = {
        animDict = 'amb@world_human_gardener_plant@male@idle_a',
        anim     = 'idle_a',
        flags    = 1,
        duration = 6000,
        label    = 'Cosechando planta...',
    },
    plant = {
        animDict = 'amb@world_human_gardener_plant@male@idle_a',
        anim     = 'idle_a',
        flags    = 1,
        duration = 5000,
        label    = 'Plantando semilla...',
    },
    destroy = {
        animDict = 'melee@large_wpn@streamed_core',
        anim     = 'ground_attack_0',
        flags    = 1,
        duration = 3000,
        label    = 'Destruyendo planta...',
    },
}

-- =============================================
--  OX_TARGET
-- =============================================

Config.TargetDistance = 2.0

Config.TargetOptions = {
    inspect = {
        label = 'Inspeccionar Planta',
        icon  = 'fas fa-seedling',
    },
    destroy = {
        label = 'Destruir Planta',
        icon  = 'fas fa-skull',
    },
}