-- =============================================
--  AX_Farming - client.lua
--  New ESX 1.13.4 | ox_target | ox_inventory | Lua 5.4
-- =============================================

local ESX = exports['es_extended']:getSharedObject()

-- =============================================
--  ESTADO LOCAL
-- =============================================

local Plants          = {}        -- [id] = { datos + objeto }
local NUIOpen         = false
local CurrentPlantId  = nil
local PlantingActive  = false

-- =============================================
--  HELPERS DE PROP
-- =============================================

local function getStage(growth)
    if growth < 34 then return 1
    elseif growth < 67 then return 2
    else return 3 end
end

local function getPropModel(plant_type, stage)
    local cfg = Config.Plants[plant_type]
    if not cfg then return nil end
    return cfg.props[stage] or cfg.props[1]
end

local function spawnPropForPlant(plantData)
    local model = getPropModel(plantData.plant_type, plantData.stage)
    if not model then return nil end

    local hash = GetHashKey(model)
    RequestModel(hash)
    local timeout = 0
    while not HasModelLoaded(hash) and timeout < 100 do
        Wait(50)
        timeout = timeout + 1
    end
    if not HasModelLoaded(hash) then return nil end

    -- Buscar Z del suelo en la posición exacta
    local groundZ = plantData.z
    local found, gz = GetGroundZFor_3dCoord(plantData.x, plantData.y, plantData.z + 2.0, false)
    if found then groundZ = gz end

    local obj = CreateObject(hash, plantData.x, plantData.y, groundZ, false, false, true)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    SetModelAsNoLongerNeeded(hash)
    return obj
end

local function deletePropForPlant(plantId)
    local plant = Plants[plantId]
    if plant and plant.obj and DoesEntityExist(plant.obj) then
        DeleteEntity(plant.obj)
        plant.obj = nil
    end
end

-- =============================================
--  OX_TARGET: registrar/eliminar opciones
-- =============================================

local function registerTargetForPlant(plantId)
    local plant = Plants[plantId]
    if not plant or not plant.obj then return end

    exports.ox_target:addLocalEntity(plant.obj, {
        {
            name    = 'farming_inspect_' .. plantId,
            label   = Config.TargetOptions.inspect.label,
            icon    = Config.TargetOptions.inspect.icon,
            distance = Config.TargetDistance,
            onSelect = function()
                openPlantMenu(plantId)
            end,
        },
        {
            name    = 'farming_destroy_' .. plantId,
            label   = Config.TargetOptions.destroy.label,
            icon    = Config.TargetOptions.destroy.icon,
            distance = Config.TargetDistance,
            onSelect = function()
                destroyPlantAction(plantId)
            end,
        },
    })
end

local function removeTargetForPlant(plantId)
    local plant = Plants[plantId]
    if plant and plant.obj and DoesEntityExist(plant.obj) then
        exports.ox_target:removeLocalEntity(plant.obj, {
            'farming_inspect_' .. plantId,
            'farming_destroy_' .. plantId,
        })
    end
end

-- =============================================
--  CARGAR PLANTAS AL INICIAR
-- =============================================

RegisterNetEvent('AX_Farming:client:loadPlants', function(serverPlants)
    for id, _ in pairs(Plants) do
        deletePropForPlant(id)
    end
    Plants = {}

    CreateThread(function()
        Wait(3000) -- esperar que el mundo cargue
        for id, plantData in pairs(serverPlants) do
            local numId = tonumber(id)
            Plants[numId] = {
                id         = numId,
                plant_type = plantData.plant_type,
                owner      = plantData.owner,
                x          = plantData.x,
                y          = plantData.y,
                z          = plantData.z,
                heading    = plantData.heading,
                growth     = plantData.growth,
                water      = plantData.water,
                fertilizer = plantData.fertilizer,
                stage      = plantData.stage,
                is_dead    = plantData.is_dead or false,
                planted_at = plantData.planted_at or 0,
                last_water = plantData.last_water or 0,
                obj        = nil,
            }
            local obj = spawnPropForPlant(Plants[numId])
            Plants[numId].obj = obj
            if obj then
                registerTargetForPlant(numId)
            end
        end
    end)
end)

-- =============================================
--  AÑADIR PLANTA (nueva)
-- =============================================

RegisterNetEvent('AX_Farming:client:addPlant', function(plantData)
    local id = plantData.id
    Plants[id] = {
        id         = id,
        plant_type = plantData.plant_type,
        owner      = plantData.owner,
        x          = plantData.x,
        y          = plantData.y,
        z          = plantData.z,
        heading    = plantData.heading,
        growth     = plantData.growth,
        water      = plantData.water,
        fertilizer = plantData.fertilizer,
        stage      = plantData.stage,
        is_dead    = plantData.is_dead or false,
        planted_at = plantData.planted_at or os.time(),
        last_water = plantData.last_water or os.time(),
        obj        = nil,
    }
    local obj = spawnPropForPlant(Plants[id])
    Plants[id].obj = obj
    if obj then
        registerTargetForPlant(plantId)
    end
end)

-- =============================================
--  ACTUALIZAR PLANTA
-- =============================================

RegisterNetEvent('AX_Farming:client:updatePlant', function(plantId, data)
    local plant = Plants[plantId]
    if not plant then return end

    local oldStage  = plant.stage
    local wasDead   = plant.is_dead
    plant.growth     = data.growth
    plant.water      = data.water
    plant.fertilizer = data.fertilizer
    plant.stage      = data.stage
    plant.is_dead    = data.is_dead

    if oldStage ~= plant.stage then
        removeTargetForPlant(plantId)
        deletePropForPlant(plantId)
        local obj = spawnPropForPlant(plant)
        plant.obj = obj
        if obj then
            registerTargetForPlant(plantId)
        end
    end

    if NUIOpen and CurrentPlantId == plantId then
        SendNUIMessage({
            type       = 'updatePlant',
            growth     = plant.growth,
            water      = plant.water,
            fertilizer = plant.fertilizer,
            stage      = plant.stage,
            is_dead    = plant.is_dead,
        })
    end
end)

-- =============================================
--  ELIMINAR PLANTA
-- =============================================

RegisterNetEvent('AX_Farming:client:removePlant', function(plantId)
    if NUIOpen and CurrentPlantId == plantId then
        closeNUI()
    end
    removeTargetForPlant(plantId)
    deletePropForPlant(plantId)
    Plants[plantId] = nil
end)

-- =============================================
--  NUI
-- =============================================

function openPlantMenu(plantId)
    local plant = Plants[plantId]
    if not plant then return end
    local cfg = Config.Plants[plant.plant_type]
    if not cfg then return end

    CurrentPlantId = plantId
    NUIOpen        = true
    SetNuiFocus(true, true)

    -- Calcular tiempo estimado
    local now           = os.time()
    local timeRemaining = 0
    local timeMode      = 'growth' -- 'growth', 'death', 'rot'

    if plant.is_dead then
        timeMode      = 'dead'
        timeRemaining = 0
    elseif plant.growth >= 100 then
        timeMode      = 'rot'
        local rotDeadline = plant.last_water + Config.RotTime
        timeRemaining = math.max(0, rotDeadline - now)
    elseif plant.water <= 0 then
        timeMode      = 'death'
        local deathDeadline = plant.last_water + Config.DeathTime
        timeRemaining = math.max(0, deathDeadline - now)
    else
        timeMode      = 'growth'
        -- Estimar ticks restantes para llegar a 100%
        local cfg2       = Config.Plants[plant.plant_type]
        local growPerTick = cfg2.passiveGrowth + (cfg2.waterGrowth * 0.1)
        local ticksLeft   = math.ceil((100 - plant.growth) / growPerTick)
        timeRemaining     = ticksLeft * (Config.GrowthInterval / 1000)
    end

    SendNUIMessage({
        type          = 'open',
        plantId       = plantId,
        label         = cfg.label,
        growth        = plant.growth,
        water         = plant.water,
        fertilizer    = plant.fertilizer,
        fertMax       = cfg.fertMax,
        waterMax      = cfg.waterMax,
        stage         = plant.stage,
        is_dead       = plant.is_dead,
        timeRemaining = timeRemaining,
        timeMode      = timeMode,
    })
end

function closeNUI()
    NUIOpen        = false
    CurrentPlantId = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'close' })
end

RegisterNUICallback('closeMenu', function(_, cb)
    closeNUI()
    cb('ok')
end)

-- =============================================
--  ACCIONES DESDE NUI
-- =============================================

RegisterNUICallback('waterPlant', function(data, cb)
    cb('ok')
    closeNUI()
    local plantId = tonumber(data.plantId)
    local animCfg = Config.Animations.water

    exports['AX_ProgressBar']:Progress({
        duration = animCfg.duration,
        label    = animCfg.label,
        useWhileDead   = false,
        canCancel      = true,
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
        if not cancelled then
            TriggerServerEvent('AX_Farming:server:waterPlant', plantId)
        end
    end)
end)

RegisterNUICallback('fertilizePlant', function(data, cb)
    cb('ok')
    closeNUI()
    local plantId = tonumber(data.plantId)
    local animCfg = Config.Animations.fertilize

    exports['AX_ProgressBar']:Progress({
        duration = animCfg.duration,
        label    = animCfg.label,
        useWhileDead   = false,
        canCancel      = true,
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
        if not cancelled then
            TriggerServerEvent('AX_Farming:server:fertilizePlant', plantId)
        end
    end)
end)

RegisterNUICallback('harvestPlant', function(data, cb)
    cb('ok')
    closeNUI()
    local plantId = tonumber(data.plantId)
    local animCfg = Config.Animations.harvest

    exports['AX_ProgressBar']:Progress({
        duration = animCfg.duration,
        label    = animCfg.label,
        useWhileDead   = false,
        canCancel      = true,
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
        if not cancelled then
            TriggerServerEvent('AX_Farming:server:harvestPlant', plantId)
        end
    end)
end)

RegisterNUICallback('destroyPlantMenu', function(data, cb)
    cb('ok')
    closeNUI()
    local plantId = tonumber(data.plantId)
    destroyPlantAction(plantId)
end)

-- =============================================
--  DESTRUIR PLANTA (desde ox_target)
-- =============================================

function destroyPlantAction(plantId)
    local animCfg = Config.Animations.destroy

    exports['AX_ProgressBar']:Progress({
        duration = animCfg.duration,
        label    = animCfg.label,
        useWhileDead   = false,
        canCancel      = true,
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
        if not cancelled then
            TriggerServerEvent('AX_Farming:server:destroyPlant', plantId)
        end
    end)
end

-- =============================================
--  DETECCIÓN DE SUELO Y PLANTADO
-- =============================================

local function isOnDirt()
    local playerPed = PlayerPedId()
    local pos = GetEntityCoords(playerPed)

    local rayHandle = StartShapeTestRay(
        pos.x, pos.y, pos.z + 0.5,
        pos.x, pos.y, pos.z - 2.0,
        1, playerPed, 7
    )

    local timeout = 0
    while timeout < 10 do
        local status, hit, hitCoords, surfaceNormal, entityHit = GetShapeTestResult(rayHandle)
        if status ~= 1 then
            if hit == 1 and entityHit == 0 then
                -- Verificar material del suelo
                local materialHash = GetMaterialKeyForSurface(GetGroundMaterialAtCoords(hitCoords.x, hitCoords.y, hitCoords.z))
                return true -- suelo nativo encontrado
            end
            return false
        end
        Wait(50)
        timeout = timeout + 1
    end
    return false
end

local function isNearOtherPlant(coords)
    for _, plant in pairs(Plants) do
        local dist = #(vector3(plant.x, plant.y, plant.z) - coords)
        if dist < Config.MinPlantDistance then
            return true
        end
    end
    return false
end

-- =============================================
--  USAR SEMILLA (ITEM)
-- =============================================

local function useSeed(seedItem)
    if PlantingActive then return end

    -- Verificar suelo
    if not isOnDirt() then
        TriggerEvent('esx:showNotification', 'Solo puedes plantar en tierra.')
        return
    end

    local playerPed = PlayerPedId()
    local pos       = GetEntityCoords(playerPed)

    if isNearOtherPlant(pos) then
        TriggerEvent('esx:showNotification', 'Hay una planta demasiado cerca.')
        return
    end

    PlantingActive = true
    local animCfg  = Config.Animations.plant

    exports['AX_ProgressBar']:Progress({
        duration = animCfg.duration,
        label    = animCfg.label,
        useWhileDead   = false,
        canCancel      = true,
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
        PlantingActive = false
        if not cancelled then
            local finalPos = GetEntityCoords(PlayerPedId())
            local heading  = GetEntityHeading(PlayerPedId())
            TriggerServerEvent('AX_Farming:server:plantSeed', seedItem, {
                x = finalPos.x,
                y = finalPos.y,
                z = finalPos.z,
            }, heading)
        end
    end)
end

-- Registrar uso de semillas
AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for seedItem, _ in pairs(Config.Plants) do
        local item = seedItem
        exports(item, function(data, slot)
            exports.ox_inventory:useItem(data, function(result)
                if result then
                    useSeed(item)
                end
            end)
        end)
    end
end)

RegisterNetEvent('AX_Farming:client:useSeed', function(seedItem)
    useSeed(seedItem)
end)

-- =============================================
--  CERRAR NUI CON ESCAPE
-- =============================================

CreateThread(function()
    while true do
        Wait(0)
        if NUIOpen and IsControlJustReleased(0, 200) then -- ESC
            closeNUI()
        end
    end
end)

-- =============================================
--  RECONECTAR: solicitar plantas al servidor
-- =============================================

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        ESX.TriggerServerCallback('AX_Farming:getAllPlants', function(serverPlants)
            TriggerEvent('AX_Farming:client:loadPlants', serverPlants)
        end)
    end
end)