-- ============================================================
--  AX_Farming | client.lua
-- ============================================================

local ESX = exports['es_extended']:getSharedObject()

local spawnedProps   = {}
local localPlants    = {}
local hudOpen        = false
local currentPlantId = nil

-- ── NOTIFY ───────────────────────────────────────────────────
local function notify(msg, ntype)
    ESX.ShowNotification(msg, ntype or 'info')
end

-- ── STAGE / PROP ─────────────────────────────────────────────
local function getStageFromGrowth(growth, state)
    if state == 'dead' or state == 'rotten' then return 4 end
    if growth >= 100 then return 4 end
    if growth >= 60  then return 3 end
    if growth >= 25  then return 2 end
    return 1
end

local function getPropForPlant(plant)
    local cfg = Config.Plants[plant.plantType]
    if not cfg then return nil end
    return cfg.props['stage' .. getStageFromGrowth(plant.growth, plant.state)]
end

-- ── PROGRESS BAR ─────────────────────────────────────────────
local ANIMS = {
    plant     = { dict = 'amb@world_human_gardener_plant@male@base', anim = 'base', flags = 1  },
    water     = { dict = 'amb@world_human_drinking@base',            anim = 'base', flags = 1  },
    fertilize = { dict = 'amb@world_human_gardener_plant@male@base', anim = 'base', flags = 49 },
    harvest   = { dict = 'amb@world_human_gardener_plant@male@base', anim = 'base', flags = 1  },
    remove    = { dict = 'amb@world_human_gardener_plant@male@base', anim = 'base', flags = 1  },
}

local function doProgress(label, duration, animType)
    local done     = false
    local finished = false
    local a        = ANIMS[animType] or ANIMS.plant

    exports['AX_ProgressBar']:Progress({
        duration        = duration,
        label           = label,
        useWhileDead    = false,
        canCancel       = true,
        controlDisables = {
            disableMovement    = true,
            disableCarMovement = true,
            disableMouse       = false,
            disableCombat      = true,
        },
        animation = { animDict = a.dict, anim = a.anim, flags = a.flags },
    }, function(cancelled)
        done     = not cancelled
        finished = true
    end)

    while not finished do Wait(0) end
    return done
end

-- ── PROPS ────────────────────────────────────────────────────
local function despawnProp(pid)
    if spawnedProps[pid] then
        DeleteObject(spawnedProps[pid])
        spawnedProps[pid] = nil
    end
end

local function spawnPlantProp(plant)
    if plant.state == 'dead' then despawnProp(plant.id) return end

    local propName = getPropForPlant(plant)
    if not propName then return end

    local hash = GetHashKey(propName)
    if not IsModelValid(hash) then
        print(('[AX_Farming] ^1Prop invalido: %s^0'):format(propName))
        return
    end

    local existing = spawnedProps[plant.id]
    if existing and DoesEntityExist(existing) then
        if GetEntityModel(existing) == hash then return end
        DeleteObject(existing)
    end

    lib.requestModel(hash)
    local prop = CreateObjectNoOffset(hash, plant.x, plant.y, plant.z, false, false, false)
    SetEntityCollision(prop, true, true)
    FreezeEntityPosition(prop, true)
    PlaceObjectOnGroundProperly(prop)
    SetModelAsNoLongerNeeded(hash)
    spawnedProps[plant.id] = prop
end

-- ── OX_TARGET ────────────────────────────────────────────────
local function addTargetToPlant(plant)
    local handle = spawnedProps[plant.id]
    if not handle or not DoesEntityExist(handle) then return end

    exports.ox_target:removeLocalEntity(handle)

    local pid = plant.id

    exports.ox_target:addLocalEntity(handle, {
        {
            name     = 'inspect_' .. pid,
            label    = Config.TargetOptions.inspect.label,
            icon     = Config.TargetOptions.inspect.icon,
            onSelect = function()
                CreateThread(function() openHUD(pid) end)
            end,
        },
        {
            name     = 'remove_' .. pid,
            label    = Config.TargetOptions.remove.label,
            icon     = Config.TargetOptions.remove.icon,
            onSelect = function()
                CreateThread(function() doRemove(pid) end)
            end,
        },
    })
end

-- ── SYNC ─────────────────────────────────────────────────────
local function syncPlants(serverPlants)
    for id in pairs(spawnedProps) do
        if not serverPlants[id] then
            exports.ox_target:removeLocalEntity(spawnedProps[id])
            despawnProp(id)
        end
    end

    localPlants = serverPlants

    for id, plant in pairs(serverPlants) do
        plant.id = id
        if plant.state ~= 'dead' then
            spawnPlantProp(plant)
            Wait(100)
            addTargetToPlant(plant)
        end
    end

    -- Si el HUD está abierto actualizar datos en pantalla
    if hudOpen and currentPlantId and localPlants[currentPlantId] then
        SendNUIMessage({ action = 'updatePlant', plant = localPlants[currentPlantId] })
    end
end

-- ── HUD ──────────────────────────────────────────────────────
function openHUD(plantId)
    local plant = localPlants[plantId]
    if not plant then
        local fresh = lib.callback.await('AX_Farming:getPlantData', false, plantId)
        if not fresh then notify('No se puede obtener informacion de la planta') return end
        fresh.id = plantId
        plant = fresh
    end
    currentPlantId = plantId
    hudOpen        = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openHUD', plant = plant })
end

function closeHUD()
    hudOpen        = false
    currentPlantId = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeHUD' })
end

-- ── ACCIONES ─────────────────────────────────────────────────
-- Patrón para acciones desde el HUD:
--   1. Cerrar foco NUI para que el juego reciba input (animación/progressbar)
--   2. Ejecutar progressbar
--   3. Llamar al servidor
--   4. El servidor manda syncAllPlants → el NUI recibe updatePlant automáticamente
-- No hay que reabrir el HUD manualmente: el HUD sigue visible en pantalla,
-- solo perdió el foco. Al terminar la acción, devolvemos el foco.

local function runHUDAction(progressLabel, duration, animType, callback)
    -- 1. Quitar foco para que la animación funcione
    SetNuiFocus(false, false)

    -- 2. Progressbar
    local done = doProgress(progressLabel, duration, animType)

    -- 3. Ejecutar acción si no canceló
    if done then
        callback()
    end

    -- 4. Devolver foco al HUD si sigue abierto
    if hudOpen then
        SetNuiFocus(true, true)
    end
end

function doWater(plantId)
    runHUDAction('Regando planta...', 4000, 'water', function()
        local ok, result = lib.callback.await('AX_Farming:waterPlant', false, plantId)
        if ok then
            notify('Has regado la planta')
        else
            notify(result or 'No puedes regar esta planta', 'error')
        end
    end)
end

function doFertilize(plantId)
    runHUDAction('Fertilizando planta...', 5000, 'fertilize', function()
        local ok, result = lib.callback.await('AX_Farming:fertilizePlant', false, plantId)
        if ok then
            notify('Has fertilizado la planta')
        else
            notify(result or 'No puedes fertilizar esta planta', 'error')
        end
    end)
end

function doHarvest(plantId)
    runHUDAction('Cosechando planta...', 6000, 'harvest', function()
        local ok, result = lib.callback.await('AX_Farming:harvestPlant', false, plantId)
        if ok then
            notify(('Has cosechado %d %s'):format(result.amount, result.label))
            closeHUD()
        else
            notify(result or 'No puedes cosechar esta planta', 'error')
        end
    end)
end

function doRemove(plantId)
    -- El arrancar puede venir del target (sin HUD abierto) o del HUD
    local fromHUD = hudOpen
    if fromHUD then SetNuiFocus(false, false) end

    local done = doProgress('Arrancando planta...', 3000, 'remove')
    if done then
        local ok, err = lib.callback.await('AX_Farming:removePlant', false, plantId)
        if ok then
            notify('Has arrancado la planta')
            if fromHUD then closeHUD() end
        else
            notify(err or 'No puedes arrancar esta planta', 'error')
            if fromHUD then SetNuiFocus(true, true) end
        end
    else
        if fromHUD then SetNuiFocus(true, true) end
    end
end

-- ── PLANTAR ──────────────────────────────────────────────────
RegisterNetEvent('AX_Farming:useSeed', function(plantType)
    local ped    = PlayerPedId()
    local coords = GetEntityCoords(ped)

    local ray = StartShapeTestRay(coords.x, coords.y, coords.z, coords.x, coords.y, coords.z - 3.0, 1, ped, 0)
    local _, hit = GetShapeTestResult(ray)
    if not hit then
        notify('No puedes plantar aqui, necesitas suelo de tierra', 'error')
        return
    end

    for _, p in pairs(localPlants) do
        if #(coords - vector3(p.x, p.y, p.z)) < Config.MinDistanceBetween then
            notify('Demasiado cerca de otra planta', 'error')
            return
        end
    end

    local done = doProgress('Plantando semilla...', 5000, 'plant')
    if not done then return end

    coords = GetEntityCoords(ped)
    local ok, result = lib.callback.await('AX_Farming:plantSeed', false, plantType, {
        x = coords.x, y = coords.y, z = coords.z
    })
    if ok then
        notify('Has plantado la semilla')
    else
        notify(result or 'No se pudo plantar la semilla', 'error')
    end
end)

-- ── EVENTOS ──────────────────────────────────────────────────
RegisterNetEvent('AX_Farming:syncAllPlants', function(serverPlants)
    syncPlants(serverPlants)
end)

RegisterNetEvent('AX_Farming:removePlant', function(plantId)
    if hudOpen and currentPlantId == plantId then closeHUD() end
    if spawnedProps[plantId] then
        exports.ox_target:removeLocalEntity(spawnedProps[plantId])
    end
    despawnProp(plantId)
    localPlants[plantId] = nil
end)

-- ── NUI CALLBACKS ────────────────────────────────────────────
RegisterNUICallback('closeHUD', function(_, cb)
    cb('ok')
    closeHUD()
end)

RegisterNUICallback('waterPlant', function(data, cb)
    cb('ok')
    local pid = tonumber(data.plantId)
    CreateThread(function() doWater(pid) end)
end)

RegisterNUICallback('fertilizePlant', function(data, cb)
    cb('ok')
    local pid = tonumber(data.plantId)
    CreateThread(function() doFertilize(pid) end)
end)

RegisterNUICallback('harvestPlant', function(data, cb)
    cb('ok')
    local pid = tonumber(data.plantId)
    CreateThread(function() doHarvest(pid) end)
end)

RegisterNUICallback('removePlant', function(data, cb)
    cb('ok')
    local pid = tonumber(data.plantId)
    CreateThread(function() doRemove(pid) end)
end)

-- ── LIMPIEZA ─────────────────────────────────────────────────
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, prop in pairs(spawnedProps) do
        if DoesEntityExist(prop) then DeleteObject(prop) end
    end
    closeHUD()
end)

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    CreateThread(function()
        Wait(3000)
        local serverPlants = lib.callback.await('AX_Farming:getAllPlants', false)
        if serverPlants then syncPlants(serverPlants) end
    end)
end)