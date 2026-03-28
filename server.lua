-- ============================================================
--  AX_Farming | server.lua
-- ============================================================

local ESX = exports['es_extended']:getSharedObject()

local plants = {}

-- ─── ESTADO ──────────────────────────────────────────────────
local function getPlantState(plant)
    if plant.health <= 0 then return 'dead' end
    if plant.growth >= 100 then
        local rotMax = Config.RotTimer * 60
        if plant.rotTimer and plant.rotTimer >= rotMax then
            return 'rotten'
        elseif plant.rotTimer and plant.rotTimer >= math.floor(rotMax * 0.5) then
            return 'wilting'
        end
        return 'ready'
    end
    return 'growing'
end

-- ─── CONSTRUIR OBJETO CON LABEL ──────────────────────────────
local function buildPlantObj(data)
    local pType = data.plant_type or data.plantType
    local cfg   = Config.Plants[pType]
    return {
        id         = data.id,
        owner      = data.owner,
        plantType  = pType,
        label        = cfg and cfg.label or pType,
        growTimeSecs = cfg and (cfg.growTime * 60) or 600,  -- segundos totales de crecimiento
        x          = data.x,
        y          = data.y,
        z          = data.z,
        growth     = data.growth,
        water      = data.water,
        fertilizer = data.fertilizer,
        health     = data.health,
        state      = data.state,
        rotTimer   = data.rot_timer  or data.rotTimer  or 0,
        growTimer  = data.grow_timer or data.growTimer or 0,
    }
end

-- ─── CARGA DB ────────────────────────────────────────────────
local function loadPlantsFromDB()
    local rows = MySQL.query.await('SELECT * FROM ax_farming_plants WHERE state != ?', {'dead'})
    if not rows then return end
    for _, row in ipairs(rows) do
        plants[row.id] = buildPlantObj(row)
    end
    print(('[AX_Farming] ^2%d plantas cargadas.^0'):format(#rows))
end

-- ─── CICLO ───────────────────────────────────────────────────
local function updateCycle()
    local intervalSecs = Config.UpdateInterval * 60

    for id, plant in pairs(plants) do
        if plant.state == 'dead' then
            plants[id] = nil
        else
            local state = getPlantState(plant)

            if state == 'growing' then
                plant.growTimer = (plant.growTimer or 0) + intervalSecs

                local gain = Config.GrowthBasePerCycle
                if plant.fertilizer > 0 then gain = gain + Config.GrowthBonusFertilizer end
                if plant.water < 20        then gain = gain - Config.GrowthPenaltyLowWater end
                if plant.water <= 0        then plant.health = math.max(0, plant.health - Config.HealthDecayNoWater) end

                plant.growth = math.min(100, math.max(0, plant.growth + gain))

            elseif state == 'ready' or state == 'wilting' or state == 'rotten' then
                plant.rotTimer = (plant.rotTimer or 0) + intervalSecs

                local rotMax  = Config.RotTimer * 60
                local rotPct  = math.min(1.0, plant.rotTimer / rotMax)
                local hpDecay = math.floor(rotPct * Config.HealthDecayNoWater)
                if hpDecay > 0 then
                    plant.health = math.max(0, plant.health - hpDecay)
                end
            end

            plant.water      = math.max(0, plant.water      - Config.WaterDecayPerCycle)
            plant.fertilizer = math.max(0, plant.fertilizer - Config.FertilizerDecayPerCycle)
            plant.state      = getPlantState(plant)

            MySQL.update(
                'UPDATE ax_farming_plants SET growth=?,water=?,fertilizer=?,health=?,state=?,rot_timer=?,grow_timer=? WHERE id=?',
                {plant.growth, plant.water, plant.fertilizer, plant.health, plant.state, plant.rotTimer or 0, plant.growTimer or 0, plant.id}
            )
        end
    end

    TriggerClientEvent('AX_Farming:syncAllPlants', -1, plants)
end

CreateThread(function()
    Wait(2000)
    loadPlantsFromDB()
    Wait(500)
    TriggerClientEvent('AX_Farming:syncAllPlants', -1, plants)
    while true do
        Wait(Config.UpdateInterval * 60 * 1000)
        updateCycle()
    end
end)

-- ─── CALLBACKS ───────────────────────────────────────────────

lib.callback.register('AX_Farming:getAllPlants', function(source)
    return plants
end)

lib.callback.register('AX_Farming:getPlantData', function(source, plantId)
    return plants[plantId] or nil
end)

lib.callback.register('AX_Farming:plantSeed', function(source, plantType, coords)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return false, 'Sin jugador' end

    local identifier = xPlayer.identifier
    local cfg = Config.Plants[plantType]
    if not cfg then return false, 'Tipo de planta invalido' end

    local count = 0
    for _, p in pairs(plants) do
        if p.owner == identifier then count = count + 1 end
    end
    if count >= Config.MaxPlantsPerPlayer then
        return false, ('Limite de %d plantas alcanzado'):format(Config.MaxPlantsPerPlayer)
    end

    for _, p in pairs(plants) do
        local dist = #(vector3(coords.x, coords.y, coords.z) - vector3(p.x, p.y, p.z))
        if dist < Config.MinDistanceBetween then
            return false, 'Demasiado cerca de otra planta'
        end
    end

    local removed = exports.ox_inventory:RemoveItem(source, cfg.seedItem, 1)
    if not removed then return false, 'No tienes la semilla en el inventario' end

    local insertId = MySQL.insert.await(
        'INSERT INTO ax_farming_plants (owner,plant_type,x,y,z,growth,water,fertilizer,health,state,rot_timer,grow_timer,planted_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,NOW())',
        {identifier, plantType, coords.x, coords.y, coords.z, 0, 50, 0, 100, 'growing', 0, 0}
    )
    if not insertId then return false, 'Error en base de datos' end

    plants[insertId] = {
        id           = insertId,
        owner        = identifier,
        plantType    = plantType,
        label        = cfg.label,
        growTimeSecs = cfg.growTime * 60,
        x            = coords.x,
        y            = coords.y,
        z            = coords.z,
        growth       = 0,
        water        = 50,
        fertilizer   = 0,
        health       = 100,
        state        = 'growing',
        rotTimer     = 0,
        growTimer    = 0,
    }

    TriggerClientEvent('AX_Farming:syncAllPlants', -1, plants)
    return true, insertId
end)

lib.callback.register('AX_Farming:waterPlant', function(source, plantId)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return false, 'Sin jugador' end
    local plant = plants[plantId]
    if not plant then return false, 'Planta no encontrada' end
    if plant.state == 'dead' or plant.state == 'rotten' then return false, 'No se puede regar' end
    local removed = exports.ox_inventory:RemoveItem(source, Config.WaterItem, 1)
    if not removed then return false, 'No tienes agua en el inventario' end
    plant.water = math.min(100, plant.water + Config.WaterPerUse)
    MySQL.update('UPDATE ax_farming_plants SET water=? WHERE id=?', {plant.water, plantId})
    TriggerClientEvent('AX_Farming:syncAllPlants', -1, plants)
    return true, plant
end)

lib.callback.register('AX_Farming:fertilizePlant', function(source, plantId)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return false, 'Sin jugador' end
    local plant = plants[plantId]
    if not plant then return false, 'Planta no encontrada' end
    if plant.state == 'dead' or plant.state == 'rotten' then return false, 'No se puede fertilizar' end
    local removed = exports.ox_inventory:RemoveItem(source, Config.FertilizerItem, 1)
    if not removed then return false, 'No tienes fertilizante en el inventario' end
    plant.fertilizer = math.min(100, plant.fertilizer + Config.FertilizerPerUse)
    MySQL.update('UPDATE ax_farming_plants SET fertilizer=? WHERE id=?', {plant.fertilizer, plantId})
    TriggerClientEvent('AX_Farming:syncAllPlants', -1, plants)
    return true, plant
end)

lib.callback.register('AX_Farming:harvestPlant', function(source, plantId)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return false, 'Sin jugador' end
    local plant = plants[plantId]
    if not plant then return false, 'Planta no encontrada' end
    local state = getPlantState(plant)
    if state ~= 'ready' and state ~= 'wilting' and state ~= 'rotten' then
        return false, 'La planta aun no esta lista para cosechar'
    end
    local cfg = Config.Plants[plant.plantType]
    if not cfg then return false, 'Tipo invalido' end

    local amount = math.random(cfg.harvestMin, cfg.harvestMax)
    if plant.growth >= 100 and plant.fertilizer >= 50 then
        amount = amount + cfg.bonusPerFert
    end
    if state == 'wilting' then amount = math.floor(amount * 0.6)
    elseif state == 'rotten' then amount = math.floor(amount * 0.2) end
    if plant.health < 50 then amount = math.floor(amount * (plant.health / 100)) end
    amount = math.max(1, amount)

    exports.ox_inventory:AddItem(source, cfg.harvestItem, amount)
    plants[plantId] = nil
    MySQL.update('UPDATE ax_farming_plants SET state=? WHERE id=?', {'dead', plantId})
    TriggerClientEvent('AX_Farming:removePlant', -1, plantId)
    return true, {amount = amount, item = cfg.harvestItem, label = cfg.label}
end)

lib.callback.register('AX_Farming:removePlant', function(source, plantId)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return false end
    local plant = plants[plantId]
    if not plant then return false end
    if plant.owner ~= xPlayer.identifier then return false, 'No eres el dueno' end
    plants[plantId] = nil
    MySQL.update('UPDATE ax_farming_plants SET state=? WHERE id=?', {'dead', plantId})
    TriggerClientEvent('AX_Farming:removePlant', -1, plantId)
    return true
end)

AddEventHandler('esx:playerLoaded', function(playerId)
    Wait(3000)
    TriggerClientEvent('AX_Farming:syncAllPlants', playerId, plants)
end)

CreateThread(function()
    Wait(1000)
    for itemName, _ in pairs(Config.Plants) do
        ESX.RegisterUsableItem(itemName, function(source)
            TriggerClientEvent('AX_Farming:useSeed', source, itemName)
        end)
    end
    print('[AX_Farming] ^2Semillas registradas como usables.^0')
end)