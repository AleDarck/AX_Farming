-- =============================================
--  AX_Farming - server.lua
--  New ESX 1.13.4 | oxmysql | ox_inventory | Lua 5.4
-- =============================================

local ESX = exports['es_extended']:getSharedObject()

-- =============================================
--  CREACIÓN AUTOMÁTICA DE TABLA
-- =============================================

MySQL.ready(function()
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `ax_farming_plants` (
            `id`         INT          NOT NULL AUTO_INCREMENT,
            `plant_type` VARCHAR(50)  NOT NULL,
            `owner`      VARCHAR(60)  NOT NULL DEFAULT 'unknown',
            `x`          FLOAT        NOT NULL,
            `y`          FLOAT        NOT NULL,
            `z`          FLOAT        NOT NULL,
            `heading`    FLOAT        NOT NULL DEFAULT 0.0,
            `growth`     FLOAT        NOT NULL DEFAULT 0.0,
            `water`      FLOAT        NOT NULL DEFAULT 50.0,
            `fertilizer` INT          NOT NULL DEFAULT 0,
            `stage`      INT          NOT NULL DEFAULT 1,
            `is_dead`    TINYINT(1)   NOT NULL DEFAULT 0,
            `planted_at` INT          NOT NULL DEFAULT 0,
            `last_water` INT          NOT NULL DEFAULT 0,
            `created_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
end)

-- =============================================
--  ESTADO DE PLANTAS EN MEMORIA
-- =============================================

local Plants = {}       -- [id] = { datos }
local nextId  = 1       -- fallback si DB tarda

local function getStage(growth)
    if growth < 34 then return 1
    elseif growth < 67 then return 2
    else return 3 end
end

-- =============================================
--  CARGAR PLANTAS AL INICIAR
-- =============================================

MySQL.ready(function()
    local rows = MySQL.query.await('SELECT * FROM ax_farming_plants')
    for _, row in ipairs(rows) do
        Plants[row.id] = {
            id         = row.id,
            plant_type = row.plant_type,
            owner      = row.owner,
            x          = row.x,
            y          = row.y,
            z          = row.z,
            heading    = row.heading,
            growth     = row.growth,
            water      = row.water,
            fertilizer = row.fertilizer,
            stage      = row.stage,
            is_dead    = row.is_dead == 1,
            planted_at = row.planted_at,
            last_water = row.last_water,
        }
    end
    print('[AX_Farming] Plantas cargadas desde DB: ' .. #rows)
    TriggerClientEvent('AX_Farming:client:loadPlants', -1, Plants)
end)

-- =============================================
--  CRECIMIENTO PASIVO (servidor)
-- =============================================

CreateThread(function()
    while true do
        Wait(Config.GrowthInterval)
        local now = os.time()

        for id, plant in pairs(Plants) do
            local cfg = Config.Plants[plant.plant_type]
            if cfg and not plant.is_dead then

                local timeSinceWater = now - plant.last_water

                if plant.growth >= 100 then
                    local rotDeadline = plant.last_water + Config.RotTime
                    if now >= rotDeadline then
                        plant.is_dead = true
                        MySQL.update('UPDATE ax_farming_plants SET is_dead=1 WHERE id=?', { id })
                        TriggerClientEvent('AX_Farming:client:updatePlant', -1, id, {
                            growth        = plant.growth,
                            water         = plant.water,
                            fertilizer    = plant.fertilizer,
                            stage         = plant.stage,
                            is_dead       = true,
                            timeMode      = 'dead',
                            timeRemaining = 0,
                        })
                    else
                        TriggerClientEvent('AX_Farming:client:updatePlant', -1, id, {
                            growth        = plant.growth,
                            water         = plant.water,
                            fertilizer    = plant.fertilizer,
                            stage         = plant.stage,
                            is_dead       = false,
                            timeMode      = 'rot',
                            timeRemaining = math.max(0, rotDeadline - now),
                        })
                    end

                elseif plant.water <= 0 and timeSinceWater >= Config.DeathTime then
                    plant.is_dead = true
                    MySQL.update('UPDATE ax_farming_plants SET is_dead=1 WHERE id=?', { id })
                    TriggerClientEvent('AX_Farming:client:updatePlant', -1, id, {
                        growth        = plant.growth,
                        water         = plant.water,
                        fertilizer    = plant.fertilizer,
                        stage         = plant.stage,
                        is_dead       = true,
                        timeMode      = 'dead',
                        timeRemaining = 0,
                    })

                else
                    if plant.growth < 100 then
                        local grow = cfg.passiveGrowth
                        if plant.water > 0 then
                            grow = grow + (cfg.waterGrowth * 0.1)
                        end
                        plant.growth = math.min(100, plant.growth + grow)
                        plant.water  = math.max(0, plant.water - cfg.waterDecay)
                        plant.stage  = getStage(plant.growth)

                        if plant.growth >= 100 then
                            plant.last_water = now
                            MySQL.update('UPDATE ax_farming_plants SET last_water=? WHERE id=?', { now, id })
                        end
                    end

                    local timeMode      = 'growth'
                    local timeRemaining = 0

                    if plant.growth >= 100 then
                        timeMode      = 'rot'
                        timeRemaining = math.max(0, (plant.last_water + Config.RotTime) - now)
                    elseif plant.water <= 0 then
                        timeMode      = 'death'
                        timeRemaining = math.max(0, (plant.last_water + Config.DeathTime) - now)
                    else
                        local growPerTick = cfg.passiveGrowth + (cfg.waterGrowth * 0.1)
                        local ticksLeft   = math.ceil((100 - plant.growth) / growPerTick)
                        timeRemaining     = ticksLeft * (Config.GrowthInterval / 1000)
                    end

                    TriggerClientEvent('AX_Farming:client:updatePlant', -1, id, {
                        growth        = plant.growth,
                        water         = plant.water,
                        fertilizer    = plant.fertilizer,
                        stage         = plant.stage,
                        is_dead       = false,
                        timeMode      = timeMode,
                        timeRemaining = timeRemaining,
                    })
                end
            end
        end
    end
end)

-- =============================================
--  GUARDADO PERIÓDICO EN DB
-- =============================================

CreateThread(function()
    while true do
        Wait(Config.SaveInterval)
        for id, plant in pairs(Plants) do
            MySQL.update(
                'UPDATE ax_farming_plants SET growth=?, water=?, fertilizer=?, stage=? WHERE id=?',
                { plant.growth, plant.water, plant.fertilizer, plant.stage, id }
            )
        end
    end
end)

-- =============================================
--  EVENTO: PLANTAR SEMILLA
-- =============================================

RegisterNetEvent('AX_Farming:server:plantSeed', function(seedItem, coords, heading)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    local cfg = Config.Plants[seedItem]
    if not cfg then return end

    local hasItem = exports.ox_inventory:GetItem(src, seedItem, nil, false)
    if not hasItem or hasItem.count < 1 then
        TriggerClientEvent('esx:showNotification', src, 'No tienes esa semilla.')
        return
    end

    for _, plant in pairs(Plants) do
        local dist = #(vector3(plant.x, plant.y, plant.z) - vector3(coords.x, coords.y, coords.z))
        if dist < Config.MinPlantDistance then
            TriggerClientEvent('esx:showNotification', src, 'Hay una planta demasiado cerca.')
            return
        end
    end

    exports.ox_inventory:RemoveItem(src, seedItem, 1)

    local now = os.time()
    local id = MySQL.insert.await(
        'INSERT INTO ax_farming_plants (plant_type, owner, x, y, z, heading, growth, water, fertilizer, stage, is_dead, planted_at, last_water) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
        { seedItem, xPlayer.identifier, coords.x, coords.y, coords.z, heading, 0.0, 50.0, 0, 1, 0, now, now }
    )

    local plantData = {
        id         = id,
        plant_type = seedItem,
        owner      = xPlayer.identifier,
        x          = coords.x,
        y          = coords.y,
        z          = coords.z,
        heading    = heading,
        growth     = 0.0,
        water      = 50.0,
        fertilizer = 0,
        stage      = 1,
        is_dead    = false,
        planted_at = now,
        last_water = now,
    }
    Plants[id] = plantData

    TriggerClientEvent('AX_Farming:client:addPlant', -1, plantData)
    TriggerClientEvent('esx:showNotification', src, 'Semilla plantada con éxito.')
end)

-- =============================================
--  EVENTO: REGAR PLANTA
-- =============================================

RegisterNetEvent('AX_Farming:server:waterPlant', function(plantId)
    local src = source
    local plant = Plants[plantId]
    if not plant then return end

    if plant.is_dead then
        TriggerClientEvent('esx:showNotification', src, 'Esta planta está muerta, solo puedes destruirla.')
        return
    end

    local hasItem = exports.ox_inventory:GetItem(src, 'water_bottle', nil, false)
    if not hasItem or hasItem.count < 1 then
        TriggerClientEvent('esx:showNotification', src, 'Necesitas una botella de agua.')
        return
    end

    local cfg = Config.Plants[plant.plant_type]
    if not cfg then return end

    exports.ox_inventory:RemoveItem(src, 'water_bottle', 1)

    local now = os.time()
    plant.water      = math.min(cfg.waterMax, plant.water + 30)
    plant.growth     = math.min(100, plant.growth + cfg.waterGrowth)
    plant.stage      = getStage(plant.growth)
    plant.last_water = now

    MySQL.update(
        'UPDATE ax_farming_plants SET growth=?, water=?, stage=?, last_water=? WHERE id=?',
        { plant.growth, plant.water, plant.stage, now, plantId }
    )

    TriggerClientEvent('AX_Farming:client:updatePlant', -1, plantId, {
        growth     = plant.growth,
        water      = plant.water,
        fertilizer = plant.fertilizer,
        stage      = plant.stage,
        is_dead    = false,
    })
    TriggerClientEvent('esx:showNotification', src, 'Planta regada.')
end)

-- =============================================
--  EVENTO: FERTILIZAR PLANTA
-- =============================================

RegisterNetEvent('AX_Farming:server:fertilizePlant', function(plantId)
    local src = source
    local plant = Plants[plantId]
    if not plant then return end

    local cfg = Config.Plants[plant.plant_type]
    if not cfg then return end

    if plant.fertilizer >= cfg.fertMax then
        TriggerClientEvent('esx:showNotification', src, 'La planta ya tiene el fertilizante máximo.')
        return
    end

    -- Verificar fertilizante
    local hasItem = exports.ox_inventory:GetItem(src, 'fertilizer', nil, false)
    if not hasItem or hasItem.count < 1 then
        TriggerClientEvent('esx:showNotification', src, 'Necesitas fertilizante.')
        return
    end

    exports.ox_inventory:RemoveItem(src, 'fertilizer', 1)

    plant.fertilizer = math.min(cfg.fertMax, plant.fertilizer + 2)
    plant.growth     = math.min(100, plant.growth + cfg.fertGrowth)
    plant.stage      = getStage(plant.growth)

    MySQL.update(
        'UPDATE ax_farming_plants SET growth=?, fertilizer=?, stage=? WHERE id=?',
        { plant.growth, plant.fertilizer, plant.stage, plantId }
    )

    TriggerClientEvent('AX_Farming:client:updatePlant', -1, plantId, {
        growth     = plant.growth,
        water      = plant.water,
        fertilizer = plant.fertilizer,
        stage      = plant.stage,
    })
    TriggerClientEvent('esx:showNotification', src, 'Planta fertilizada. (' .. plant.fertilizer .. '/' .. cfg.fertMax .. ')')
end)

-- =============================================
--  EVENTO: COSECHAR PLANTA
-- =============================================

RegisterNetEvent('AX_Farming:server:harvestPlant', function(plantId)
    local src = source
    local plant = Plants[plantId]
    if not plant then return end

    local cfg = Config.Plants[plant.plant_type]
    if not cfg then return end

    if plant.growth < 100 then
        TriggerClientEvent('esx:showNotification', src, 'La planta aún no está lista.')
        return
    end

    -- Calcular cosecha: base + extra por fertilizante
    local fertPercent = (plant.fertilizer / cfg.fertMax)
    local extraHarvest = math.floor((cfg.maxHarvest - cfg.baseHarvest) * fertPercent)
    local totalHarvest = cfg.baseHarvest + extraHarvest

    exports.ox_inventory:AddItem(src, cfg.harvestItem, totalHarvest)

    -- Eliminar planta
    MySQL.query('DELETE FROM ax_farming_plants WHERE id=?', { plantId })
    Plants[plantId] = nil

    TriggerClientEvent('AX_Farming:client:removePlant', -1, plantId)
    TriggerClientEvent('esx:showNotification', src, 'Cosechaste ' .. totalHarvest .. 'x ' .. cfg.harvestItem .. '.')
end)

-- =============================================
--  EVENTO: DESTRUIR PLANTA
-- =============================================

RegisterNetEvent('AX_Farming:server:destroyPlant', function(plantId)
    local src = source
    local plant = Plants[plantId]
    if not plant then return end

    MySQL.query('DELETE FROM ax_farming_plants WHERE id=?', { plantId })
    Plants[plantId] = nil

    TriggerClientEvent('AX_Farming:client:removePlant', -1, plantId)
    TriggerClientEvent('esx:showNotification', src, 'Planta destruida.')
end)

-- =============================================
--  CALLBACK: OBTENER DATOS DE UNA PLANTA
-- =============================================

ESX.RegisterServerCallback('AX_Farming:getPlantData', function(source, cb, plantId)
    local plant = Plants[plantId]
    cb(plant)
end)

-- =============================================
--  CALLBACK: VERIFICAR SUELO (desde cliente)
-- =============================================

ESX.RegisterServerCallback('AX_Farming:getAllPlants', function(source, cb)
    cb(Plants)
end)

