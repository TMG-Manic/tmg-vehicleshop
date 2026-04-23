
local TMGCore = exports['tmg-core']:GetCoreObject()
local PlayerData = TMGCore.Functions.GetPlayerData()
local testDriveZone = nil
local vehicleMenu = {}
local Initialized = false
local testDriveVeh, inTestDrive = 0, false
local ClosestVehicle = 1
local zones = {}
local insideShop, tempShop = nil, nil
Locale = {}


RegisterNetEvent('TMGCore:Client:OnPlayerLoaded', function()
    local pData = TMGCore.Functions.GetPlayerData()
    local timeout = 0
    
    while (not pData or not pData.citizenid) and timeout < 100 do
        Wait(10)
        pData = TMGCore.Functions.GetPlayerData()
        timeout = timeout + 1
    end

    if not pData or not pData.citizenid then
        return TMGCore.Functions.Notify("Error: Mainframe failed to sync character data. Re-log required.", "error")
    end

    PlayerData = pData
    local citizenid = PlayerData.citizenid

    CreateThread(function()
        TriggerServerEvent('tmg-vehicleshop:server:addPlayer', citizenid)
        Wait(500) 
        TriggerServerEvent('tmg-vehicleshop:server:checkFinance')
    end)

    if not Initialized then 
        Init() 
    else
        PlayerData = TMGCore.Functions.GetPlayerData()
    end
end)


AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    local pData = TMGCore.Functions.GetPlayerData()
    
    if not pData or not pData.citizenid then return end

    if Initialized then return end

    PlayerData = pData
    local citizenid = PlayerData.citizenid

    CreateThread(function()
        TriggerServerEvent('tmg-vehicleshop:server:addPlayer', citizenid)
        Wait(500)
        TriggerServerEvent('tmg-vehicleshop:server:checkFinance')
        
        if not Initialized then
            Init()
        end
    end)
end)

RegisterNetEvent('TMGCore:Client:OnJobUpdate', function(JobInfo)
    PlayerData.job = JobInfo
    
    if insideShop then
        TMGCore.Functions.Notify("Job updated: Refreshing shop permissions...", "primary")
        local currentShop = insideShop
        insideShop = nil
        Wait(100)
        insideShop = currentShop
    end
end)

RegisterNetEvent('TMGCore:Client:OnPlayerUnload', function()
    local citizenid = PlayerData and PlayerData.citizenid or nil
    
    exports['tmg-menu']:closeMenu()
    SetNuiFocus(false, false)
    
    if citizenid then
        TriggerServerEvent('tmg-vehicleshop:server:removePlayer', citizenid)
    end
    
    PlayerData = {}
    insideShop = nil
    inTestDrive = false
    Initialized = false 
end)

RegisterNetEvent('TMGCore:Client:UpdateObject', function()
    local CoreObject = exports['tmg-core']:GetCoreObject()
    if not CoreObject then return end
    
    TMGCore = CoreObject

    local freshData = TMGCore.Functions.GetPlayerData()
    
    if freshData and next(freshData) ~= nil then
        PlayerData = freshData
        
        if insideShop then
            ClosestVehicle = 1 
        end
    end
end)


local function CheckPlate(vehicle, plateToSet)
    local vehiclePlate = promise.new()
    
    CreateThread(function()
        local attempts = 0
        local maxAttempts = 20 

        while attempts < maxAttempts do
            Wait(500)
            
            if not DoesEntityExist(vehicle) then
                vehiclePlate:resolve(false)
                return
            end

            local currentPlate = GetVehicleNumberPlateText(vehicle)
            if currentPlate == plateToSet then
                vehiclePlate:resolve(true)
                return
            end

            if not NetworkHasControlOfEntity(vehicle) then
                NetworkRequestControlOfEntity(vehicle)
            end
            
            SetVehicleNumberPlateText(vehicle, plateToSet)
            attempts = attempts + 1
        end

        print("^3[TMG VehicleShop] Warning: Plate sync timed out for " .. plateToSet .. "^7")
        vehiclePlate:resolve(false)
    end)
    
    return vehiclePlate
end

local function GetSafeText(token, fallback)
    local text = Lang:t(token)
    return (text ~= nil and text ~= token) and text or fallback
end

local vehHeaderMenu = {
    {
        header = GetSafeText('menus.vehHeader_header', "Vehicle Options"),
        txt = GetSafeText('menus.vehHeader_txt', "Manage this vehicle"),
        icon = 'fa-solid fa-car',
        params = {
            event = 'tmg-vehicleshop:client:showVehOptions'
        }
    }
}

local financeMenu = {
    {
        header = GetSafeText('menus.financed_header', "Finance Management"),
        txt = GetSafeText('menus.finance_txt', "Check your payments"),
        icon = 'fa-solid fa-user-ninja',
        params = {
            event = 'tmg-vehicleshop:client:getVehicles'
        }
    }
}

local returnTestDrive = {
    {
        header = GetSafeText('menus.returnTestDrive_header', "End Test Drive"),
        icon = 'fa-solid fa-flag-checkered',
        params = {
            event = 'tmg-vehicleshop:client:TestDriveReturn'
        }
    }
}


local function drawTxt(text)
    if not text then return end
    exports['tmg-core']:DrawText(text, 'left')
end

local function GetActiveVehicleData()
    if not insideShop or not Config.Shops[insideShop] then return nil end
    
    local shop = Config.Shops[insideShop]
    local showroomVehs = shop['ShowroomVehicles']
    
    if not showroomVehs or not showroomVehs[ClosestVehicle] then return nil end
    
    local chosenModel = showroomVehs[ClosestVehicle].chosenVehicle
    local sharedData = TMGCore.Shared.Vehicles[chosenModel]
    
    return sharedData or {
        name = "Unknown Model",
        brand = "Generic",
        price = 0
    }
end

local function getVehName()
    local data = GetActiveVehicleData()
    return data and data.name or "Unknown"
end

local function getVehPrice()
    local data = GetActiveVehicleData()
    return data and comma_value(data.price) or "0"
end

local function getVehBrand()
    local data = GetActiveVehicleData()
    return data and data.brand or "Unknown"
end

local function comma_value(amount)
    local formatted = tostring(amount or 0)
    local k
    while true do
        formatted, k = string.gsub(formatted, '^(-?%d+)(%d%d%d)', '%1,%2')
        if k == 0 then break end
    end
    return formatted
end


local lastPlayerPos = vector3(0, 0, 0)

local function setClosestShowroomVehicle()
    local ped = PlayerPedId()
    local currentPos = GetEntityCoords(ped)
    
    if #(currentPos - lastPlayerPos) < 0.5 then 
        return 
    end
    lastPlayerPos = currentPos

    if not insideShop or not Config.Shops[insideShop] then return end
    
    local showroomVehs = Config.Shops[insideShop]['ShowroomVehicles']
    local closestDist = 999.0
    local closestId = 1

    for id, data in pairs(showroomVehs) do
        local vehCoords = vector3(data.coords.x, data.coords.y, data.coords.z)
        local dist = #(currentPos - vehCoords)

        if dist < closestDist then
            closestDist = dist
            closestId = id
        end
    end

    if ClosestVehicle ~= closestId then
        ClosestVehicle = closestId
    end
end


local function createTestDriveReturn()
    if testDriveZone then
        testDriveZone:destroy()
        testDriveZone = nil
    end

    local shopData = Config.Shops[insideShop]
    if not shopData or not shopData['ReturnLocation'] then return end

    testDriveZone = BoxZone:Create(
        shopData['ReturnLocation'],
        3.0,
        5.0,
        {
            name = 'box_zone_testdrive_return_' .. insideShop,
            debugPoly = false
        })

    testDriveZone:onPlayerInOut(function(isPointInside)
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)

        if isPointInside and veh ~= 0 then
            local currentVehNetId = VehToNet(veh)
            if currentVehNetId == testDriveVeh then
                SetVehicleForwardSpeed(veh, 0.5) 
                exports['tmg-menu']:openMenu(returnTestDrive)
            end
        else
            if inTestDrive then
                exports['tmg-menu']:closeMenu()
            end
        end
    end)
end


local function startTestDriveTimer(testDriveTime, prevCoords)
    local gameTimer = GetGameTimer()
    local totalTimeMs = tonumber(1000 * testDriveTime)
    local endTime = gameTimer + totalTimeMs
    
    CreateThread(function()
        Wait(2000) 
        
        while inTestDrive do
            local currentTime = GetGameTimer()
            local timeLeftMs = endTime - currentTime
            local secondsLeft = math.ceil(timeLeftMs / 1000)

            local veh = NetToVeh(testDriveVeh)
            local isDriver = DoesEntityExist(veh) and (GetPedInVehicleSeat(veh, -1) == PlayerPedId())

            if timeLeftMs <= 0 or not isDriver then
                if testDriveVeh ~= 0 then
                    TriggerServerEvent('tmg-vehicleshop:server:deleteVehicle', testDriveVeh)
                end
                
                testDriveVeh = 0
                inTestDrive = false
                
                DoScreenFadeOut(250)
                Wait(250)
                SetEntityCoords(PlayerPedId(), prevCoords)
                DoScreenFadeIn(250)
                
                TMGCore.Functions.Notify(Lang:t('general.testdrive_complete'), "primary")
                break 
            end

            if secondsLeft > 0 then
                drawTxt(Lang:t('general.testdrive_timer') .. secondsLeft, 4, 0.5, 0.93, 0.50, 255, 255, 255, 180)
            end

            Wait(1000) 
        end
    end)
end


local activeComboZone = nil

local function createVehZones(shopName, entity)
    if not Config.UsingTarget then
        if activeComboZone then 
            activeComboZone:destroy() 
            activeComboZone = nil
        end
        zones = {} 
        
        local shopVehs = Config.Shops[shopName]['ShowroomVehicles']
        for i = 1, #shopVehs do
            local vehCoords = vector3(shopVehs[i]['coords'].x, shopVehs[i]['coords'].y, shopVehs[i]['coords'].z)
            
            zones[#zones + 1] = BoxZone:Create(vehCoords, 
                Config.Shops[shopName]['Zone']['size'], 
                Config.Shops[shopName]['Zone']['size'], 
                {
                    name = 'box_zone_' .. shopName .. '_' .. i,
                    minZ = Config.Shops[shopName]['Zone']['minZ'],
                    maxZ = Config.Shops[shopName]['Zone']['maxZ'],
                    debugPoly = false,
                })
        end

        activeComboZone = ComboZone:Create(zones, { name = 'vehCombo_' .. shopName, debugPoly = false })
        
        activeComboZone:onPlayerInOut(function(isPointInside)
            if isPointInside then
                local job = PlayerData and PlayerData.job and PlayerData.job.name
                local requiredJob = Config.Shops[insideShop] and Config.Shops[insideShop]['Job']
                
                if not requiredJob or requiredJob == 'none' or job == requiredJob then
                    exports['tmg-menu']:showHeader(vehHeaderMenu)
                end
            else
                exports['tmg-menu']:closeMenu()
            end
        end)
    else
        local targetName = "showroom_veh_" .. entity
        
        exports['tmg-target']:AddTargetEntity(entity, {
            options = {
                {
                    type = 'client',
                    event = 'tmg-vehicleshop:client:showVehOptions',
                    icon = 'fas fa-car',
                    label = Lang:t('general.vehinteraction'),
                    canInteract = function()
                        if not insideShop or not PlayerData.job then return false end
                        local shopJob = Config.Shops[insideShop]['Job']
                        return shopJob == 'none' or PlayerData.job.name == shopJob
                    end
                },
            },
            distance = 3.0
        })
    end
end




local function createFreeUseShop(shopShape, name)
    local zone = PolyZone:Create(shopShape, {
        name = name,
        minZ = shopShape.minZ,
        maxZ = shopShape.maxZ,
    })

    zone:onPlayerInOut(function(isPointInside)
        if isPointInside then
            insideShop = name
            local lastVehicle = nil 

            CreateThread(function()
                while insideShop == name do
                    setClosestShowroomVehicle()

                    if lastVehicle ~= ClosestVehicle then
                        lastVehicle = ClosestVehicle
                        
                        local vName = getVehName():upper()
                        local vBrand = getVehBrand():upper()
                        local vPrice = getVehPrice()
                        local chosenVeh = Config.Shops[name]['ShowroomVehicles'][ClosestVehicle].chosenVehicle

                        vehicleMenu = {
                            {
                                isMenuHeader = true,
                                icon = 'fa-solid fa-circle-info',
                                header = string.format("%s %s - $%s", vBrand, vName, vPrice),
                            },
                            {
                                header = Lang:t('menus.test_header'),
                                txt = Lang:t('menus.freeuse_test_txt'),
                                icon = 'fa-solid fa-car-on',
                                params = { event = 'tmg-vehicleshop:client:TestDrive' }
                            },
                            {
                                header = Lang:t('menus.freeuse_buy_header'),
                                txt = Lang:t('menus.freeuse_buy_txt'),
                                icon = 'fa-solid fa-hand-holding-dollar',
                                params = {
                                    isServer = true,
                                    event = 'tmg-vehicleshop:server:buyShowroomVehicle',
                                    args = { buyVehicle = chosenVeh }
                                }
                            },
                            {
                                header = Lang:t('menus.finance_header'),
                                txt = Lang:t('menus.freeuse_finance_txt'),
                                icon = 'fa-solid fa-coins',
                                params = {
                                    event = 'tmg-vehicleshop:client:openFinance',
                                    args = {
                                        price = vPrice,
                                        buyVehicle = chosenVeh
                                    }
                                }
                            },
                            {
                                header = Lang:t('menus.swap_header'),
                                txt = Lang:t('menus.swap_txt'),
                                icon = 'fa-solid fa-arrow-rotate-left',
                                params = {
                                    event = Config.FilterByMake and 'tmg-vehicleshop:client:vehMakes' or 'tmg-vehicleshop:client:vehCategories',
                                }
                            },
                        }
                    end
                    Wait(1000)
                end
            end)
        else
            if insideShop == name then
                insideShop = nil
                ClosestVehicle = 1
                exports['tmg-menu']:closeMenu() 
            end
        end
    end)
end



local function createManagedShop(shopShape, name)
    local zone = PolyZone:Create(shopShape, {
        name = name,
        minZ = shopShape.minZ,
        maxZ = shopShape.maxZ,
    })

    zone:onPlayerInOut(function(isPointInside)
        if isPointInside then
            local requiredJob = Config.Shops[name]['Job']
            if not PlayerData.job or PlayerData.job.name ~= requiredJob then
                return 
            end

            insideShop = name
            local lastVehicle = nil 

            CreateThread(function()
                while insideShop == name and PlayerData.job.name == requiredJob do
                    setClosestShowroomVehicle()

                    if lastVehicle ~= ClosestVehicle then
                        lastVehicle = ClosestVehicle
                        
                        local vPrice = getVehPrice()
                        local chosenVeh = Config.Shops[name]['ShowroomVehicles'][ClosestVehicle].chosenVehicle
                        local vehLabel = string.format("%s %s - $%s", getVehBrand():upper(), getVehName():upper(), vPrice)

                        vehicleMenu = {
                            {
                                isMenuHeader = true,
                                icon = 'fa-solid fa-circle-info',
                                header = vehLabel,
                            },
                            {
                                header = Lang:t('menus.test_header'),
                                txt = Lang:t('menus.managed_test_txt'),
                                icon = 'fa-solid fa-user-plus',
                                params = {
                                    event = 'tmg-vehicleshop:client:openIdMenu',
                                    args = {
                                        vehicle = chosenVeh,
                                        type = 'testDrive'
                                    }
                                }
                            },
                            {
                                header = Lang:t('menus.managed_sell_header'),
                                txt = Lang:t('menus.managed_sell_txt'),
                                icon = 'fa-solid fa-cash-register',
                                params = {
                                    event = 'tmg-vehicleshop:client:openIdMenu',
                                    args = {
                                        vehicle = chosenVeh,
                                        type = 'sellVehicle'
                                    }
                                }
                            },
                            {
                                header = Lang:t('menus.finance_header'),
                                txt = Lang:t('menus.managed_finance_txt'),
                                icon = 'fa-solid fa-coins',
                                params = {
                                    event = 'tmg-vehicleshop:client:openCustomFinance',
                                    args = {
                                        price = vPrice,
                                        vehicle = chosenVeh
                                    }
                                }
                            },
                            {
                                header = Lang:t('menus.swap_header'),
                                txt = Lang:t('menus.swap_txt'),
                                icon = 'fa-solid fa-arrow-rotate-left',
                                params = {
                                    event = Config.FilterByMake and 'tmg-vehicleshop:client:vehMakes' or 'tmg-vehicleshop:client:vehCategories',
                                }
                            },
                        }
                    end
                    Wait(1000)
                end

                if insideShop == name and PlayerData.job.name ~= requiredJob then
                    insideShop = nil
                    exports['tmg-menu']:closeMenu()
                    TMGCore.Functions.Notify("Access Revoked: You are no longer employed here.", "error")
                end
            end)
        else
            if insideShop == name then
                insideShop = nil
                ClosestVehicle = 1
                exports['tmg-menu']:closeMenu()
            end
        end
    end)
end


local activeFinanceZone = nil

local function createFinanceZone(coords, name)
    local zoneName = 'vehicleshop_financeZone_' .. name
    
    local financeZone = BoxZone:Create(coords, 2.0, 2.0, {
        name = zoneName,
        offset = { 0.0, 0.0, 0.0 },
        scale = { 1.0, 1.0, 1.0 },
        minZ = coords.z - 2.0, 
        maxZ = coords.z + 2.0,
        debugPoly = false,
    })

    financeZone:onPlayerInOut(function(isPointInside)
        if isPointInside then
            activeFinanceZone = zoneName
            Wait(50) 
            
            if activeFinanceZone == zoneName then
                exports['tmg-menu']:showHeader(financeMenu)
            end
        else
            if activeFinanceZone == zoneName then
                activeFinanceZone = nil
                exports['tmg-menu']:closeMenu()
            end
        end
    end)
end

function Init()
    if Initialized then return end 
    Initialized = true

    CreateThread(function()
        for name, shop in pairs(Config.Shops) do
            if shop['Type'] == 'free-use' then
                createFreeUseShop(shop['Zone']['Shape'], name)
            elseif shop['Type'] == 'managed' then
                createManagedShop(shop['Zone']['Shape'], name)
            end
            if shop['FinanceZone'] then 
                createFinanceZone(shop['FinanceZone'], name) 
            end
            Wait(10) 
        end
    end)

    CreateThread(function()
        for k, shop in pairs(Config.Shops) do
            for i = 1, #shop['ShowroomVehicles'] do
                local vehData = shop['ShowroomVehicles'][i]
                local model = joaat(vehData.defaultVehicle)

                RequestModel(model)
                local timeout = 0
                while not HasModelLoaded(model) and timeout < 100 do 
                    Wait(10) 
                    timeout = timeout + 1
                end

                if HasModelLoaded(model) then
                    local coords = vehData.coords
                    local veh = CreateVehicle(model, coords.x, coords.y, coords.z, false, false)
                    
                    if DoesEntityExist(veh) then
                        SetModelAsNoLongerNeeded(model)
                        SetVehicleOnGroundProperly(veh)
                        SetEntityInvincible(veh, true)
                        SetVehicleDirtLevel(veh, 0.0)
                        SetVehicleDoorsLocked(veh, 3)
                        SetEntityHeading(veh, coords.w)
                        FreezeEntityPosition(veh, true)
                        SetVehicleNumberPlateText(veh, 'BUY ME')
                        
                        if Config.UsingTarget then 
                            createVehZones(k, veh) 
                        end
                    end
                else
                    print("^1[TMG Mainframe] Error: Asset " .. vehData.defaultVehicle .. " timed out during shop init.^7")
                end
                
                Wait(100) 
            end

            if not Config.UsingTarget then 
                createVehZones(k) 
            end
            Wait(500) 
        end
    end)
end


local function OpenHardenedVehicleMenu(isOptions)
    if not vehicleMenu or #vehicleMenu == 0 then
        return TMGCore.Functions.Notify("Error: Menu data not manifested. Stand closer.", "error")
    end

    exports['tmg-menu']:closeMenu() 
    Wait(10) 

    if isOptions then
        exports['tmg-menu']:openMenu(vehicleMenu, true, true)
    else
        exports['tmg-menu']:openMenu(vehicleMenu)
    end
end

RegisterNetEvent('tmg-vehicleshop:client:homeMenu', function()
    setClosestShowroomVehicle() 
    OpenHardenedVehicleMenu(false)
end)

RegisterNetEvent('tmg-vehicleshop:client:showVehOptions', function()
    setClosestShowroomVehicle()
    OpenHardenedVehicleMenu(true)
end)


RegisterNetEvent('tmg-vehicleshop:client:TestDrive', function()
    if inTestDrive or ClosestVehicle == 0 then
        return TMGCore.Functions.Notify(Lang:t('error.testdrive_alreadyin'), 'error')
    end

    local currentShopName = insideShop
    local shopConfig = Config.Shops[currentShopName]
    local vehicleModel = shopConfig['ShowroomVehicles'][ClosestVehicle].chosenVehicle
    local spawnPoint = shopConfig['TestDriveSpawn']
    local timeLimit = shopConfig['TestDriveTimeLimit']
    local prevCoords = GetEntityCoords(PlayerPedId())

    if not currentShopName or not shopConfig then 
        return TMGCore.Functions.Notify("Error: Shop data lost. Stand closer to the vehicle.", "error") 
    end

    inTestDrive = true

    TMGCore.Functions.TriggerCallback('tmg-vehicleshop:server:spawnvehicle', function(netId, properties, vehPlate)
        if not netId or netId == 0 then
            inTestDrive = false
            return TMGCore.Functions.Notify("Mainframe failed to manifest vehicle.", "error")
        end

        local timeout = 0
        while not NetworkDoesNetworkIdExist(netId) and timeout < 100 do
            Wait(10)
            timeout = timeout + 1
        end

        local veh = NetToVeh(netId)
        if DoesEntityExist(veh) then
            local controlTimeout = 0
            while not NetworkHasControlOfEntity(veh) and controlTimeout < 50 do
                NetworkRequestControlOfEntity(veh)
                Wait(10)
                controlTimeout = controlTimeout + 1
            end

            SetEntityAsMissionEntity(veh, true, true)
            SetVehicleOnGroundProperly(veh)
            
            SetVehicleNumberPlateText(veh, vehPlate)
            exports['LegacyFuel']:SetFuel(veh, 100)
            TriggerEvent('vehiclekeys:client:SetOwner', vehPlate)
            
            local warpAttempts = 0
            while GetVehiclePedIsIn(PlayerPedId(), false) ~= veh and warpAttempts < 3 do
                TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
                Wait(200)
                warpAttempts = warpAttempts + 1
            end

            SetVehicleEngineOn(veh, true, true, false)
            testDriveVeh = netId
            
            createTestDriveReturn()
            startTestDriveTimer(timeLimit * 60, prevCoords)
            
            TMGCore.Functions.Notify(Lang:t('general.testdrive_timenoti', { testdrivetime = timeLimit }), "success")
        else
            inTestDrive = false
            TMGCore.Functions.Notify("Test drive vehicle vanished during transition.", "error")
        end
    end, 'TESTDRIVE', vehicleModel, spawnPoint, true)
end)


RegisterNetEvent('tmg-vehicleshop:client:customTestDrive', function(data)
    if inTestDrive then 
        return TMGCore.Functions.Notify(Lang:t('error.testdrive_alreadyin'), 'error') 
    end

    local shopName = insideShop
    local shopData = shopName and Config.Shops[shopName]
    
    if not shopData then 
        return TMGCore.Functions.Notify("Error: Shop context lost. Stand inside the dealership.", "error") 
    end

    local vehicleModel = shopData['ShowroomVehicles'][ClosestVehicle].chosenVehicle
    local spawnCoords = shopData['TestDriveSpawn']
    local timeLimit = shopData['TestDriveTimeLimit']
    local prevCoords = GetEntityCoords(PlayerPedId())

    if shopData['Type'] == 'managed' and PlayerData.job.name ~= shopData['Job'] then
        return TMGCore.Functions.Notify("Unauthorized: Only employees can initiate custom test drives.", "error")
    end

    inTestDrive = true

    TMGCore.Functions.TriggerCallback('tmg-vehicleshop:server:spawnvehicle', function(netId, properties, vehPlate)
        if not netId or netId == 0 then
            inTestDrive = false
            return TMGCore.Functions.Notify("Server failed to manifest test drive entity.", "error")
        end

        local timeout = 0
        while not NetworkDoesNetworkIdExist(netId) and timeout < 100 do
            Wait(10)
            timeout = timeout + 1
        end

        local veh = NetToVeh(netId)
        if DoesEntityExist(veh) then
            local controlAttempts = 0
            while not NetworkHasControlOfEntity(veh) and controlAttempts < 50 do
                NetworkRequestControlOfEntity(veh)
                Wait(10)
                controlAttempts = controlAttempts + 1
            end

            SetEntityAsMissionEntity(veh, true, true)
            SetVehicleNumberPlateText(veh, vehPlate)
            exports['LegacyFuel']:SetFuel(veh, 100)
            TriggerEvent('vehiclekeys:client:SetOwner', vehPlate)
            
            TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
            SetVehicleEngineOn(veh, true, true, false)
            
            testDriveVeh = netId
            
            createTestDriveReturn()
            startTestDriveTimer(timeLimit * 60, prevCoords)
            
            TMGCore.Functions.Notify(Lang:t('general.testdrive_timenoti', { testdrivetime = timeLimit }))
        else
            inTestDrive = false
        end
    end, 'TESTDRIVE', vehicleModel, spawnCoords, true)
end)


RegisterNetEvent('tmg-vehicleshop:client:TestDriveReturn', function()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    
    if not testDriveVeh or testDriveVeh == 0 then
        return TMGCore.Functions.Notify("Error: No active test drive session found.", "error")
    end

    local testDriveEntity = NetToVeh(testDriveVeh)
    
    if veh ~= 0 and veh == testDriveEntity then
        inTestDrive = false
        local shopToReturnTo = insideShop 
        
        TriggerServerEvent('tmg-vehicleshop:server:deleteVehicle', testDriveVeh)
        
        testDriveVeh = 0
        exports['tmg-menu']:closeMenu()
        
        if testDriveZone then
            testDriveZone:destroy()
            testDriveZone = nil
        end

        DoScreenFadeOut(250)
        Wait(250)
        
        if shopToReturnTo and Config.Shops[shopToReturnTo] then
            SetEntityCoords(ped, Config.Shops[shopToReturnTo]['Location'])
        end
        
        Wait(250)
        DoScreenFadeIn(250)
        TMGCore.Functions.Notify(Lang:t('general.testdrive_complete'), 'success')
    else
        TMGCore.Functions.Notify(Lang:t('error.testdrive_return'), 'error')
    end
end)


local shopCategoryCache = {}

RegisterNetEvent('tmg-vehicleshop:client:vehCategories', function(data)
    if not insideShop then return end
    local currentMake = (Config.FilterByMake and data) and data.make or "ALL"
    local cacheKey = string.format("%s_%s", insideShop, currentMake)
    if not shopCategoryCache[cacheKey] then
        local catmenu = {}
        local firstFound = nil
        
        local sharedVehs = TMGCore.Shared.Vehicles
        local shopID = insideShop

        for _, v in pairs(sharedVehs) do
            local isAvailable = false
            
            if type(v.shop) == 'table' then
                for i=1, #v.shop do
                    if v.shop[i] == shopID then isAvailable = true break end
                end
            elseif v.shop == shopID then
                isAvailable = true
            end

            if isAvailable and (currentMake == "ALL" or v.brand == currentMake) then
                if not catmenu[v.category] then
                    catmenu[v.category] = v.category
                    if not firstFound then firstFound = v.category end
                end
            end
        end
        
        shopCategoryCache[cacheKey] = { 
            list = catmenu, 
            first = firstFound, 
            count = tablelength(catmenu) 
        }
    end

    local cachedData = shopCategoryCache[cacheKey]

    if Config.HideCategorySelectForOne and cachedData.count == 1 then
        TriggerEvent('tmg-vehicleshop:client:openVehCats', { 
            catName = cachedData.first, 
            make = data and data.make, 
            onecat = true 
        })
        return
    end

    local categoryMenu = {
        {
            header = Lang:t('menus.goback_header'),
            icon = 'fa-solid fa-angle-left',
            params = {
                event = Config.FilterByMake and 'tmg-vehicleshop:client:vehMakes' or 'tmg-vehicleshop:client:homeMenu'
            }
        }
    }

    for k, v in pairs(cachedData.list) do
        categoryMenu[#categoryMenu + 1] = {
            header = v,
            icon = 'fa-solid fa-circle',
            params = {
                event = 'tmg-vehicleshop:client:openVehCats',
                args = { catName = k, make = data and data.make }
            }
        }
    end

    exports['tmg-menu']:openMenu(categoryMenu, Config.SortAlphabetically, true)
end)

RegisterNetEvent('TMGCore:Client:UpdateObject', function()
    shopCategoryCache = {}
end)

local vehicleLookupCache = {}

local function RebuildVehicleCache()
    vehicleLookupCache = {}
    local sharedVehs = TMGCore.Shared.Vehicles
    
    for model, data in pairs(sharedVehs) do
        local cat = data.category
        if not vehicleLookupCache[cat] then vehicleLookupCache[cat] = {} end
        
        local shops = {}
        if type(data.shop) == 'table' then
            for i=1, #data.shop do shops[data.shop[i]] = true end
        else
            shops[data.shop] = true
        end
        
        table.insert(vehicleLookupCache[cat], {
            model = model,
            name = data.name,
            price = data.price,
            shops = shops,
            brand = data.brand
        })
    end
end

RegisterNetEvent('tmg-vehicleshop:client:openVehCats', function(data)
    if not insideShop or not data.catName then return end
    
    if not next(vehicleLookupCache) then RebuildVehicleCache() end

    local vehMenu = {
        {
            header = Lang:t('menus.goback_header'),
            icon = 'fa-solid fa-angle-left',
            params = {
                event = data.onecat and 'tmg-vehicleshop:client:vehMakes' or 'tmg-vehicleshop:client:vehCategories',
                args = { make = data.make }
            }
        }
    }

    local potentialVehs = vehicleLookupCache[data.catName] or {}
    local currentShop = insideShop
    local currentMake = (Config.FilterByMake and data.make) and data.make or nil

    for i=1, #potentialVehs do
        local v = potentialVehs[i]
        
        if v.shops[currentShop] and (not currentMake or v.brand == currentMake) then
            vehMenu[#vehMenu + 1] = {
                header = v.name,
                txt = Lang:t('menus.veh_price') .. comma_value(v.price), 
                icon = 'fa-solid fa-car-side',
                params = {
                    isServer = true,
                    event = 'tmg-vehicleshop:server:swapVehicle',
                    args = {
                        toVehicle = v.model,
                        ClosestVehicle = ClosestVehicle,
                        ClosestShop = currentShop
                    }
                }
            }
        end
    end

    exports['tmg-menu']:openMenu(vehMenu, Config.SortAlphabetically, true)
end)

local shopMakeCache = {}

RegisterNetEvent('tmg-vehicleshop:client:vehMakes', function()
    if not insideShop then return end
    local currentShop = insideShop

    if not shopMakeCache[currentShop] then
        local uniqueMakes = {}
        local sharedVehs = TMGCore.Shared.Vehicles

        for _, v in pairs(sharedVehs) do
            local isAvailable = false
            
            if type(v.shop) == 'table' then
                for i = 1, #v.shop do
                    if v.shop[i] == currentShop then 
                        isAvailable = true 
                        break 
                    end
                end
            elseif v.shop == currentShop then
                isAvailable = true
            end

            if isAvailable and v.brand then
                uniqueMakes[v.brand] = v.brand
            end
        end
        
        shopMakeCache[currentShop] = uniqueMakes
    end

    local cachedMakes = shopMakeCache[currentShop]
    local makeMenu = {
        {
            header = Lang:t('menus.goback_header'),
            icon = 'fa-solid fa-angle-left',
            params = {
                event = 'tmg-vehicleshop:client:homeMenu'
            }
        }
    }

    for makeName, _ in pairs(cachedMakes) do
        makeMenu[#makeMenu + 1] = {
            header = makeName,
            icon = 'fa-solid fa-car', 
            params = {
                event = 'tmg-vehicleshop:client:vehCategories',
                args = { make = makeName }
            }
        }
    end

    exports['tmg-menu']:openMenu(makeMenu, Config.SortAlphabetically, true)
end)

AddEventHandler('TMGCore:Client:UpdateObject', function()
    shopMakeCache = {}
end)


RegisterNetEvent('tmg-vehicleshop:client:openFinance', function(data)
    local currentVehicle = data.buyVehicle
    local currentPrice = data.price
    local vehicleLabel = string.format("%s %s", getVehBrand():upper(), currentVehicle:upper())

    local dialog = exports['tmg-input']:ShowInput({
        header = vehicleLabel .. " - $" .. currentPrice,
        submitText = Lang:t('menus.submit_text'),
        inputs = {
            {
                type = 'number',
                isRequired = true,
                name = 'downPayment',
                text = string.format("%s (Min: %s%%)", Lang:t('menus.financesubmit_downpayment'), Config.MinimumDown)
            },
            {
                type = 'number',
                isRequired = true,
                name = 'paymentAmount',
                text = string.format("%s (Max: %s)", Lang:t('menus.financesubmit_totalpayment'), Config.MaximumPayments)
            }
        }
    })

    if dialog then
        local downPayment = tonumber(dialog.downPayment)
        local paymentAmount = tonumber(dialog.paymentAmount)

        if not downPayment or not paymentAmount then 
            return TMGCore.Functions.Notify("Invalid input: Please enter numbers only.", "error") 
        end

        if downPayment < Config.MinimumDown then
            return TMGCore.Functions.Notify(string.format("Down payment must be at least %s%%", Config.MinimumDown), "error")
        end

        if downPayment > 100 then
            return TMGCore.Functions.Notify("Down payment cannot exceed 100%", "error")
        end

        if paymentAmount <= 0 or paymentAmount > Config.MaximumPayments then
            return TMGCore.Functions.Notify(string.format("Invalid payment count (Max: %s)", Config.MaximumPayments), "error")
        end

        TriggerServerEvent('tmg-vehicleshop:server:financeVehicle', downPayment, paymentAmount, currentVehicle)
    end
end)

RegisterNetEvent('tmg-vehicleshop:client:openCustomFinance', function(data)
    local currentVehicle = data.vehicle
    local currentPrice = data.price
    local vehicleLabel = string.format("%s %s", getVehBrand():upper(), currentVehicle:upper())
    local salesmanPos = GetEntityCoords(PlayerPedId())

    local dialog = exports['tmg-input']:ShowInput({
        header = vehicleLabel .. " - $" .. currentPrice,
        submitText = Lang:t('menus.submit_text'),
        inputs = {
            {
                type = 'number',
                isRequired = true,
                name = 'downPayment',
                text = string.format("%s (Min: %s%%)", Lang:t('menus.financesubmit_downpayment'), Config.MinimumDown)
            },
            {
                type = 'number',
                isRequired = true,
                name = 'paymentAmount',
                text = string.format("%s (Max: %s)", Lang:t('menus.financesubmit_totalpayment'), Config.MaximumPayments)
            },
            {
                type = 'number',
                isRequired = true,
                name = 'playerid',
                text = Lang:t('menus.submit_ID')
            }
        }
    })

    if dialog then
        local downPayment = tonumber(dialog.downPayment)
        local paymentAmount = tonumber(dialog.paymentAmount)
        local targetId = tonumber(dialog.playerid)

        if not downPayment or not paymentAmount or not targetId then 
            return TMGCore.Functions.Notify("Invalid input: All fields must be numbers.", "error") 
        end

        if downPayment < Config.MinimumDown or downPayment > 100 then
            return TMGCore.Functions.Notify("Invalid down payment percentage.", "error")
        end

        if paymentAmount <= 0 or paymentAmount > Config.MaximumPayments then
            return TMGCore.Functions.Notify("Invalid payment plan length.", "error")
        end

        local targetPed = GetPlayerPed(GetPlayerFromServerId(targetId))
        if targetPed == 0 or targetPed == PlayerPedId() then
            return TMGCore.Functions.Notify("Target player not found or invalid.", "error")
        end

        local targetPos = GetEntityCoords(targetPed)
        if #(salesmanPos - targetPos) > 10.0 then
            return TMGCore.Functions.Notify("Customer is too far away to sign the papers.", "error")
        end

        TriggerServerEvent('tmg-vehicleshop:server:sellfinanceVehicle', downPayment, paymentAmount, currentVehicle, targetId)
    end
end)


RegisterNetEvent('tmg-vehicleshop:client:swapVehicle', function(data)
    local shopName = data.ClosestShop
    local vehicleIndex = data.ClosestVehicle
    local newModelName = data.toVehicle

    if not shopName or not Config.Shops[shopName] then return end
    local shopData = Config.Shops[shopName]['ShowroomVehicles'][vehicleIndex]
    
    if shopData.chosenVehicle == newModelName then return end

    local oldVeh, distance = TMGCore.Functions.GetClosestVehicle(vector3(shopData.coords.x, shopData.coords.y, shopData.coords.z))
    
    if oldVeh ~= 0 and distance < 2.0 then
        local timeout = 0
        while not NetworkHasControlOfEntity(oldVeh) and timeout < 50 do
            NetworkRequestControlOfEntity(oldVeh)
            Wait(10)
            timeout = timeout + 1
        end
        
        SetEntityAsMissionEntity(oldVeh, true, true)
        DeleteVehicle(oldVeh)
    end

    local model = joaat(newModelName)
    RequestModel(model)
    local loadTimeout = 0
    while not HasModelLoaded(model) and loadTimeout < 100 do
        Wait(10)
        loadTimeout = loadTimeout + 1
    end

    if not HasModelLoaded(model) then
        return TMGCore.Functions.Notify("Mainframe failed to stream model: " .. newModelName, "error")
    end

    shopData.chosenVehicle = newModelName
    local veh = CreateVehicle(model, shopData.coords.x, shopData.coords.y, shopData.coords.z, false, false)
    
    local spawnTimeout = 0
    while not DoesEntityExist(veh) and spawnTimeout < 50 do 
        Wait(10) 
        spawnTimeout = spawnTimeout + 1 
    end

    if DoesEntityExist(veh) then
        SetModelAsNoLongerNeeded(model)
        
        SetVehicleOnGroundProperly(veh)
        SetEntityInvincible(veh, true)
        SetEntityHeading(veh, shopData.coords.w)
        SetVehicleDoorsLocked(veh, 3)
        SetVehicleNumberPlateText(veh, 'BUY ME')
        
        Wait(100)
        FreezeEntityPosition(veh, true)

        if Config.UsingTarget then 
            createVehZones(shopName, veh) 
        end
    end
end)


RegisterNetEvent('tmg-vehicleshop:client:buyShowroomVehicle', function(vehicle, plate)
    local currentShop = insideShop
    if not currentShop or not Config.Shops[currentShop] then
        return TMGCore.Functions.Notify("Mainframe Error: Shop context lost. Transaction aborted.", "error")
    end

    local spawnCoords = Config.Shops[currentShop]['VehicleSpawn']

    TMGCore.Functions.TriggerCallback('tmg-vehicleshop:server:spawnvehicle', function(netId, properties, vehPlate)
        local timeout = 0
        while not NetworkDoesNetworkIdExist(netId) and timeout < 100 do 
            Wait(10) 
            timeout = timeout + 1 
        end

        if not NetworkDoesNetworkIdExist(netId) then
            return TMGCore.Functions.Notify("OneSync Error: Vehicle manifestation failed. Contact staff.", "error")
        end

        local veh = NetToVeh(netId)
        if DoesEntityExist(veh) then
            local controlTimeout = 0
            while not NetworkHasControlOfEntity(veh) and controlTimeout < 50 do
                NetworkRequestControlOfEntity(veh)
                Wait(10)
                controlTimeout = controlTimeout + 1
            end
            Citizen.Await(CheckPlate(veh, vehPlate))
            TMGCore.Functions.SetVehicleProperties(veh, properties)
            exports['LegacyFuel']:SetFuel(veh, 100)
            TriggerEvent('vehiclekeys:client:SetOwner', vehPlate)
            
            SetVehicleEngineOn(veh, true, true, false)
            local warpAttempts = 0
            while GetVehiclePedIsIn(PlayerPedId(), false) ~= veh and warpAttempts < 5 do
                TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
                Wait(200)
                warpAttempts = warpAttempts + 1
            end

            TMGCore.Functions.Notify("Transaction Complete! Your new vehicle is ready.", "success")
        else
            TMGCore.Functions.Notify("Entity Error: Vehicle lost during routing.", "error")
        end
    end, plate, vehicle, spawnCoords, true)
end)

RegisterNetEvent('tmg-vehicleshop:client:getVehicles', function()
    local currentShop = insideShop
    if not currentShop then return end

    TMGCore.Functions.TriggerCallback('tmg-vehicleshop:server:getVehicles', function(vehicles)
        local ownedVehicles = {
            {
                header = Lang:t('menus.goback_header'),
                icon = 'fa-solid fa-angle-left',
                params = { event = 'tmg-vehicleshop:client:homeMenu' }
            }
        }

        for i = 1, #vehicles do
            local v = vehicles[i]
            local modelIdentifier = v.vehicle
            local vehSharedData = TMGCore.Shared.Vehicles[modelIdentifier]
            
            local displayName = vehSharedData and vehSharedData.name or "Unknown Model ("..tostring(modelIdentifier)..")"
            local balance = tonumber(v.balance) or 0
            
            if balance > 0 then
                local plate = tostring(v.plate):upper()
                
                ownedVehicles[#ownedVehicles + 1] = {
                    header = displayName,
                    txt = string.format("%s %s | Balance: $%s", Lang:t('menus.veh_platetxt'), plate, comma_value(balance)),
                    icon = 'fa-solid fa-car-side',
                    params = {
                        event = 'tmg-vehicleshop:client:getVehicleFinance',
                        args = {
                            vehiclePlate = plate,
                            balance = balance,
                            paymentsLeft = v.paymentsleft,
                            paymentAmount = v.paymentamount
                        }
                    }
                }
            end
        end

        if #ownedVehicles > 1 then
            exports['tmg-menu']:openMenu(ownedVehicles)
        else
            TMGCore.Functions.Notify(Lang:t('error.nofinanced'), 'error', 7500)
        end
    end)
end)

local isProcessingPayment = false 

RegisterNetEvent('tmg-vehicleshop:client:getVehicleFinance', function(data)
    if isProcessingPayment then 
        return TMGCore.Functions.Notify("Transaction in progress... please wait.", "error") 
    end

    local pLeft = tonumber(data.paymentsLeft or data.paymentsleft) or 0
    local pAmount = tonumber(data.paymentAmount or data.paymentamount) or 0
    local pBalance = tonumber(data.balance) or 0
    local pPlate = tostring(data.vehiclePlate or data.plate):upper()

    local vehFinance = {
        {
            header = Lang:t('menus.goback_header'),
            icon = 'fa-solid fa-angle-left',
            params = { event = 'tmg-vehicleshop:client:getVehicles' }
        },
        {
            isMenuHeader = true,
            icon = 'fa-solid fa-sack-dollar',
            header = Lang:t('menus.veh_finance_balance'),
            txt = string.format("%s %s", Lang:t('menus.veh_finance_currency'), comma_value(pBalance))
        },
        {
            isMenuHeader = true,
            icon = 'fa-solid fa-hashtag',
            header = Lang:t('menus.veh_finance_total'),
            txt = string.format("Installments Remaining: %s", pLeft)
        },
        {
            isMenuHeader = true,
            icon = 'fa-solid fa-calendar-day',
            header = Lang:t('menus.veh_finance_reccuring'),
            txt = string.format("%s %s", Lang:t('menus.veh_finance_currency'), comma_value(pAmount))
        },
        {
            header = Lang:t('menus.veh_finance_pay'),
            icon = 'fa-solid fa-money-bill-transfer',
            params = {
                event = 'tmg-vehicleshop:client:financePayment',
                args = {
                    vehPlate = pPlate,
                    paymentsLeft = pLeft,
                    paymentAmount = pAmount
                }
            }
        },
        {
            header = Lang:t('menus.veh_finance_payoff'),
            icon = 'fa-solid fa-hand-holding-dollar',
            params = {
                isServer = true,
                event = 'tmg-vehicleshop:server:financePaymentFull',
                args = {
                    vehBalance = pBalance,
                    vehPlate = pPlate
                }
            }
        },
    }

    exports['tmg-menu']:openMenu(vehFinance)
end)


RegisterNetEvent('tmg-vehicleshop:client:financePayment', function(data)
    if isProcessingPayment then return end
    
    local pPlate = data.vehPlate
    local minPayment = tonumber(data.paymentAmount) or 0
    
    if not pPlate then 
        return TMGCore.Functions.Notify("Error: Vehicle plate not found. Restart the menu.", "error") 
    end

    local dialog = exports['tmg-input']:ShowInput({
        header = "Vehicle Finance: " .. pPlate,
        submitText = Lang:t('menus.veh_finance_pay'),
        inputs = {
            {
                type = 'number',
                isRequired = true,
                name = 'amount',
                text = string.format("Enter Amount (Min: $%s)", comma_value(minPayment))
            }
        }
    })

    if dialog then
        local inputAmount = tonumber(dialog.amount)

        if not inputAmount or inputAmount <= 0 then
            return TMGCore.Functions.Notify("Invalid amount entered.", "error")
        end

        if inputAmount < minPayment then
            return TMGCore.Functions.Notify("Amount is below the minimum installment requirement.", "error")
        end

        isProcessingPayment = true 
        
        TriggerServerEvent('tmg-vehicleshop:server:financePayment', inputAmount, pPlate)
        
        SetTimeout(2000, function()
            isProcessingPayment = false
        end)
    end
end)

RegisterNetEvent('tmg-vehicleshop:client:openIdMenu', function(data)
    local vehData = TMGCore.Shared.Vehicles[data.vehicle]
    if not vehData then 
        return TMGCore.Functions.Notify("Error: Vehicle data corrupted.", "error") 
    end

    local dialog = exports['tmg-input']:ShowInput({
        header = string.format("DEALERSHIP ACTION: %s", vehData['name']:upper()),
        submitText = Lang:t('menus.submit_text'),
        inputs = {
            {
                text = "Customer Server ID",
                name = 'playerid',
                type = 'number',
                isRequired = true
            }
        }
    })

    if dialog then
        local targetId = tonumber(dialog.playerid)
        if not targetId or targetId <= 0 then return end

        local salesmanPed = PlayerPedId()
        local customerPed = GetPlayerPed(GetPlayerFromServerId(targetId))
        
        if customerPed == 0 then
            return TMGCore.Functions.Notify("Customer ID not found on the mainframe.", "error")
        end

        local dist = #(GetEntityCoords(salesmanPed) - GetEntityCoords(customerPed))
        if dist > 10.0 then
            return TMGCore.Functions.Notify("Customer is too far away to sign the paperwork.", "error")
        end

        if data.type == 'testDrive' then
            TriggerServerEvent('tmg-vehicleshop:server:customTestDrive', data.vehicle, targetId)
            TMGCore.Functions.Notify("Custom test drive request sent to Customer " .. targetId, "primary")
            
        elseif data.type == 'sellVehicle' then
            TriggerServerEvent('tmg-vehicleshop:server:sellShowroomVehicle', data.vehicle, targetId)
            TMGCore.Functions.Notify("Sale papers submitted for ID: " .. targetId, "success")
        end
    end
end)


local ShopBlips = {}

local function CreateShopBlips()
    for _, blip in pairs(ShopBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    ShopBlips = {}

    for name, data in pairs(Config.Shops) do
        if data.showBlip then
            local coords = data['Location']
            local blip = AddBlipForCoord(coords.x, coords.y, coords.z)

            SetBlipSprite(blip, data['blipSprite'] or 326) 
            SetBlipDisplay(blip, 4)
            SetBlipScale(blip, 0.7)
            SetBlipAsShortRange(blip, true)
            SetBlipColour(blip, data['blipColor'] or 3)

            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(data['ShopLabel'] or "Vehicle Shop")
            EndTextCommandSetBlipName(blip)

            
            ShopBlips[name] = blip
        end
    end
end

CreateThread(function()
    CreateShopBlips()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        for _, blip in pairs(ShopBlips) do
            if DoesBlipExist(blip) then RemoveBlip(blip) end
        end
    end
end)
