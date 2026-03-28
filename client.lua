-- ============================================================
--  AX_Farming | client.lua
-- ============================================================

local ESX = exports['es_extended']:getSharedObject()

local spawnedProps   = {}
local localPlants    = {}
local hudOpen        = false
local currentPlantId = nil

-- ─── HELPERS ─────────────────────────────────────────────────
local function notify(msg, ntype)
    ESX.ShowNotification(msg, ntype or 'info')
end

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

-- ─── PROGRESS BAR ────────────────────────────────────────────
local ANIM_CONFIG = {
    plant     = { animDict = 'amb@world_human_gardener_plant@male@base', anim = 'base', flags = 1  },
    water     = { animDict = 'amb@world_human_drinking@base',            anim = 'base', flags = 1  },
    fertilize = { animDict = 'amb@world_human_gardener_plant@male@base', anim = 'base', flags = 49 },
    harvest   = { animDict = 'amb@world_human_gardener_plant@male@base', anim = 'base', flags = 1  },
    remove    = { animDict = 'amb@world_human_gardener_plant@male@base', anim = 'base', flags = 1  },
}

local function doProgress(label, duration, animType)
    local completed = false
    local finished  = false
    local animCfg   = ANIM_CONFIG[animType] or ANIM_CONFIG.plant

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
        animation = {
            animDict = animCfg.animDict,
            anim     = animCfg.anim,
            flags    = animCfg.flags,
        },
    }, function(cancelled)
        completed = not cancelled
        finished  = true
    end)

    while not finished do Wait(0) end
    return completed
end

-- ─── PROPS ───────────────────────────────────────────────────
local function despawnProp(plantId)
    if spawnedProps[plantId] then
        DeleteObject(spawnedProps[plantId])
        spawnedProps[plantId] = nil
    end
end

local function spawnPlantProp(plant)
    if plant.state == 'dead' then despawnProp(plant.id) return end

    local propName = getPropForPlant(plant)
    if not propName then return end

    local propHash = GetHashKey(propName)
    if not IsModelValid(propHash) then
        print(('[AX_Farming] ^1Prop invalido: %s - verifica config.lua^0'):format(propName))
        return
    end

    local coords   = vector3(plant.x, plant.y, plant.z)
    local existing = spawnedProps[plant.id]
    if existing and DoesEntityExist(existing) then
        if GetEntityModel(existing) == propHash then return end
        DeleteObject(existing)
    end

    lib.requestModel(propHash)
    local prop = CreateObjectNoOffset(propHash, coords.x, coords.y, coords.z, false, false, false)
    SetEntityCollision(prop, true, true)
    FreezeEntityPosition(prop, true)
    PlaceObjectOnGroundProperly(prop)
    SetModelAsNoLongerNeeded(propHash)
    spawnedProps[plant.id] = prop
end

-- ─── OX_TARGET ───────────────────────────────────────────────
-- Solo inspeccionar y arrancar. Sin duplicados: removeLocalEntity antes de add.
local function addTargetToPlant(plant)
    local propHandle = spawnedProps[plant.id]
    if not propHandle or not DoesEntityExist(propHandle) then return end

    -- Quitar target previo para evitar duplicados
    exports.ox_target:removeLocalEntity(propHandle)

    local pid = plant.id  -- captura local para el closure

    exports.ox_target:addLocalEntity(propHandle, {
        {
            name     = 'inspect_' .. pid,
            label    = Config.TargetOptions.inspect.label,
            icon     = Config.TargetOptions.inspect.icon,
            onSelect = function()
                openHUD(pid)
            end,
        },
        {
            name     = 'remove_' .. pid,
            label    = Config.TargetOptions.remove.label,
            icon     = Config.TargetOptions.remove.icon,
            onSelect = function()
                -- Siempre en thread propio para no bloquear ox_target
                CreateThread(function()
                    doRemove(pid)
                end)
            end,
        },
    })
end

-- ─── SYNC ────────────────────────────────────────────────────
local function syncPlants(serverPlants)
    -- Eliminar props que ya no existen en el servidor
    for id, _ in pairs(spawnedProps) do
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

    -- Actualizar HUD si está abierto
    if hudOpen and currentPlantId and localPlants[currentPlantId] then
        SendNUIMessage({ action = 'updatePlant', plant = localPlants[currentPlantId] })
    end
end

-- ─── HUD ─────────────────────────────────────────────────────
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

-- ─── ACCIONES — siempre en thread propio ─────────────────────
-- Los NUI callbacks no tienen un hilo de Citizen, hay que crear uno explícitamente.
-- Sin esto doProgress bloquea y los callbacks nunca retornan al NUI.

function doWater(plantId)
    local done = doProgress('Regando planta...', 4000, 'water')
    if not done then return end
    local ok, result = lib.callback.await('AX_Farming:waterPlant', false, plantId)
    if ok then
        notify('Has regado la planta')
        if hudOpen and currentPlantId == plantId then
            SendNUIMessage({ action = 'updatePlant', plant = result })
        end
    else
        notify(result or 'No puedes regar esta planta', 'error')
    end
end

function doFertilize(plantId)
    local done = doProgress('Fertilizando planta...', 5000, 'fertilize')
    if not done then return end
    local ok, result = lib.callback.await('AX_Farming:fertilizePlant', false, plantId)
    if ok then
        notify('Has fertilizado la planta')
        if hudOpen and currentPlantId == plantId then
            SendNUIMessage({ action = 'updatePlant', plant = result })
        end
    else
        notify(result or 'No puedes fertilizar esta planta', 'error')
    end
end

function doHarvest(plantId)
    local done = doProgress('Cosechando planta...', 6000, 'harvest')
    if not done then return end
    local ok, result = lib.callback.await('AX_Farming:harvestPlant', false, plantId)
    if ok then
        notify(('Has cosechado %d %s'):format(result.amount, result.label))
        closeHUD()
    else
        notify(result or 'No puedes cosechar esta planta', 'error')
    end
end

function doRemove(plantId)
    local done = doProgress('Arrancando planta...', 3000, 'remove')
    if not done then return end
    local ok, err = lib.callback.await('AX_Farming:removePlant', false, plantId)
    if ok then
        notify('Has arrancado la planta')
        closeHUD()
    else
        notify(err or 'No puedes arrancar esta planta', 'error')
    end
end

-- ─── PLANTAR ─────────────────────────────────────────────────
RegisterNetEvent('AX_Farming:useSeed', function(plantType)
    local ped    = PlayerPedId()
    local coords = GetEntityCoords(ped)

    local rayHandle = StartShapeTestRay(coords.x, coords.y, coords.z, coords.x, coords.y, coords.z - 3.0, 1, ped, 0)
    local _, didHit = GetShapeTestResult(rayHandle)
    if not didHit then
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

-- ─── EVENTOS SYNC ────────────────────────────────────────────
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

-- ─── NUI CALLBACKS ───────────────────────────────────────────
-- Cada acción se lanza en su propio thread para que doProgress pueda bloquear
-- sin congelar el callback del NUI (que necesita retornar rápidamente).

RegisterNUICallback('closeHUD', function(_, cb)
    closeHUD()
    cb('ok')
end)

RegisterNUICallback('waterPlant', function(data, cb)
    cb('ok')  -- retornar inmediatamente al NUI
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

-- ─── LIMPIEZA ────────────────────────────────────────────────
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