
local TMGCore = exports['tmg-core']:GetCoreObject()
local financetimer = {}


local vehicleTypes = {
    motorcycles = 'bike',
    boats       = 'boat',
    helicopters = 'heli',
    planes      = 'plane',
    submarines  = 'submarine',
    trailer     = 'trailer',
    train       = 'train'
}

local function GetVehicleTypeByModel(model)
    local vehicleData = TMGCore.Shared.Vehicles[model]
    
    if not vehicleData then return 'automobile' end

    if vehicleData.type then return vehicleData.type end

    local category = vehicleData.category
    local vehicleType = vehicleTypes[category]

    return vehicleType or 'automobile'
end


TMGCore.Functions.CreateCallback('tmg-vehicleshop:server:spawnVehicle', function(source, cb, plate, vehicle, coords)
    local trimmedPlate = plate:gsub("%s+", ""):upper()
    local vehType = TMGCore.Shared.Vehicles[vehicle] and TMGCore.Shared.Vehicles[vehicle].type or GetVehicleTypeByModel(vehicle)

    exports['tmgnosql']:FetchOne('player_vehicles', { ["plate"] = trimmedPlate }, function(result)
        local vehProps = (result and result.mods) or {}

        local veh = CreateVehicleServerSetter(GetHashKey(vehicle), vehType, coords.x, coords.y, coords.z, coords.w)
        
        local netId = NetworkGetNetworkIdFromEntity(veh)
        SetVehicleNumberPlateText(veh, plate)

        cb(netId, vehProps, plate)
        
        print(string.format("^5[TMG]^7 Materialization: Asset [%s] localized in world by NetID %d", trimmedPlate, netId))
    end)
end)


RegisterNetEvent('tmg-vehicleshop:server:addPlayer', function()
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid

    financetimer[citizenid] = os.time()

    print(string.format("^5[TMG]^7 Finance: Chronometer started for Citizen %s", citizenid))
end)



RegisterNetEvent('tmg-vehicleshop:server:removePlayer', function()
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    if not Player then return end

    local cid = Player.PlayerData.citizenid
    local startTime = financetimer[cid]

    if not startTime then return end

    local minutesPlayed = math.floor((os.time() - startTime) / 60)
    financetimer[cid] = nil 

    if minutesPlayed <= 0 then return end

    local filter = { 
        ["citizenid"] = cid, 
        ["balance"] = { ["$gt"] = 0 } 
    }
    
    local update = { 
        ["$inc"] = { ["financetime"] = -minutesPlayed } 
    }

    exports['tmgnosql']:UpdateMany('player_vehicles', filter, update, function(affected)
        exports['tmgnosql']:UpdateMany('player_vehicles', 
            { ["citizenid"] = cid, ["financetime"] = { ["$lt"] = 0 } }, 
            { ["$set"] = { ["financetime"] = 0 } }
        )
        
        print(string.format("^5[TMG]^7 Finance: Aged %d loans by %d minutes for CID [%s]", affected or 0, minutesPlayed, cid))
    end)
end)


AddEventHandler('playerDropped', function()
    local src = source
    
    local Player = TMGCore.Functions.GetPlayer(src)
    if not Player then return end

    local cid = Player.PlayerData.citizenid
    local startTime = financetimer[cid]

    if not startTime then return end

    local minutesPlayed = math.floor((os.time() - startTime) / 60)
    financetimer[cid] = nil 

    if minutesPlayed <= 0 then return end

    exports['tmgnosql']:UpdateMany('player_vehicles', 
        { 
            ["citizenid"] = cid, 
            ["balance"] = { ["$gt"] = 0 } 
        }, 
        { 
            ["$inc"] = { ["financetime"] = -minutesPlayed } 
        }, 
        function()
            exports['tmgnosql']:UpdateMany('player_vehicles', 
                { ["citizenid"] = cid, ["financetime"] = { ["$lt"] = 0 } }, 
                { ["$set"] = { ["financetime"] = 0 } }
            )
        end
    )
    
    print(string.format("^5[TMG]^7 Finance: Disconnect Cleanup for CID [%s] complete (-%d min).", cid, minutesPlayed))
end)


local function round(x)
    if not x then return 0 end
    return x >= 0 and math.floor(x + 0.5) or math.ceil(x - 0.5)
end

local function calculateNewFinance(paymentAmount, vehData)
    local currentBalance = tonumber(vehData.balance) or 0
    local currentPayments = tonumber(vehData.paymentsLeft) or 1
    
    local newBalance = currentBalance - (tonumber(paymentAmount) or 0)
    local remainingTerms = currentPayments - 1
    
    if remainingTerms <= 0 then return 0, 0, 0 end
    
    local newPayment = newBalance / remainingTerms
    return round(newBalance), round(newPayment), remainingTerms
end

local function GeneratePlate()
    local plate = TMGCore.Shared.RandomInt(1) .. 
                  TMGCore.Shared.RandomStr(2) .. 
                  TMGCore.Shared.RandomInt(3) .. 
                  TMGCore.Shared.RandomStr(2)
    plate = plate:upper()

    local exists = exports['tmgnosql']:FetchOne('player_vehicles', 
        { ["plate"] = plate }, 
        nil,
        { ["plate"] = 1 }
    )
    
    if exists then 
        print(string.format("^5[TMG]^7 Registry: Plate Collision [%s] - Regenerating...", plate))
        return GeneratePlate()
    end
    
    return plate
end

local function comma_value(amount)
    local formatted = tostring(amount or 0)
    local k
    while true do
        formatted, k = string.gsub(formatted, '^(-?%d+)(%d%d%d)', '%1,%2')
        if (k == 0) then break end
    end
    return formatted
end


TMGCore.Functions.CreateCallback('tmg-vehicleshop:server:getVehicles', function(source, cb)
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    
    if not Player then return cb(nil) end

    exports['tmgnosql']:FetchAll('player_vehicles', { 
        ["citizenid"] = Player.PlayerData.citizenid 
    }, function(vehicles)
        if vehicles and #vehicles > 0 then
            cb(vehicles)
        else
            cb(nil)
        end
    end)
    
    print(string.format("^5[TMG]^7 Logistics: CID %s streaming %d assets to Terminal %d", 
        Player.PlayerData.citizenid, #vehicles or 0, src))
end)




RegisterNetEvent('tmg-vehicleshop:server:deleteVehicle', function(netId)
    local vehicle = NetworkGetEntityFromNetworkId(netId)

    if DoesEntityExist(vehicle) then
        DeleteEntity(vehicle)
        
        print(string.format("^5[TMG]^7 Purge: Entity %s (NetID: %s) has been removed.", vehicle, netId))
    else
        print(string.format("^1[TMG]^7 Warning: Terminal requested purge of non-existent NetID %s", netId))
    end
end)


RegisterNetEvent('tmg-vehicleshop:server:swapVehicle', function(data)
    local src = source
    
    TriggerClientEvent('tmg-vehicleshop:client:swapVehicle', -1, data)

    SetTimeout(1500, function()
        if TMGCore.Functions.GetPlayer(src) then
            TriggerClientEvent('tmg-vehicleshop:client:homeMenu', src)
        end
    end)
    
    print(string.format("^5[TMG]^7 Showroom: Terminal %s initiated an asset swap.", src))
end)


RegisterNetEvent('tmg-vehicleshop:server:customTestDrive', function(vehicle, playerid)
    local src = source
    local targetId = tonumber(playerid)
    
    local TargetPlayer = TMGCore.Functions.GetPlayer(targetId)
    if not TargetPlayer then
        return TriggerClientEvent('TMGCore:Notify', src, Lang:t('error.Invalid_ID'), 'error')
    end

    local dealerPed = GetPlayerPed(src)
    local targetPed = GetPlayerPed(targetId)
    local dist = #(GetEntityCoords(dealerPed) - GetEntityCoords(targetPed))

    if dist < 3.0 then
        TriggerClientEvent('tmg-vehicleshop:client:customTestDrive', targetId, vehicle)
        
        print(string.format("^5[TMG]^7 Test Drive: Terminal %s authorized %s for Terminal %s", src, vehicle, targetId))
    else
        TriggerClientEvent('TMGCore:Notify', src, Lang:t('error.playertoofar'), 'error')
    end
end)

RegisterNetEvent('tmg-vehicleshop:server:processFinancePayment', function(paymentAmount, vehData)
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    if not Player or not vehData.vehiclePlate then return end

    local plate = vehData.vehiclePlate:gsub("%s+", ""):upper()
    local amount = tonumber(paymentAmount) or 0
    local minPayment = tonumber(vehData.paymentAmount) or 0
    
    local newBalance, newPayment, newPaymentsLeft = calculateNewFinance(amount, vehData)

    if newBalance < 0 then
        return TriggerClientEvent('TMGCore:Notify', src, Lang:t('error.overpaid'), 'error')
    end

    if amount < minPayment then
        return TriggerClientEvent('TMGCore:Notify', src, Lang:t('error.minimumallowed') .. comma_value(minPayment), 'error')
    end

    local paymentType = Player.PlayerData.money.cash >= amount and 'cash' or 'bank'
    
    if Player.PlayerData.money[paymentType] >= amount then
        Player.Functions.RemoveMoney(paymentType, amount, 'financed-vehicle-installment')

        local updateData = {
            ["$set"] = {
                ["balance"] = newBalance,
                ["paymentamount"] = newPayment,
                ["paymentsleft"] = newPaymentsLeft,
                ["financetime"] = (Config.PaymentInterval * 60) 
            }
        }

        exports['tmgnosql']:UpdateOne('player_vehicles', { ["plate"] = plate }, updateData, function(success)
            if success then
                TriggerClientEvent('TMGCore:Notify', src, "Mainframe: Installment verified. Asset debt reduced.", 'success')
                print(string.format("^5[TMG]^7 Finance: CID %s paid $%d toward Plate [%s]", Player.PlayerData.citizenid, amount, plate))
            else
                print(string.format("^1[TMG Error]^7 Registry Desync: Failed to update debt for Plate %s", plate))
            end
        end)
    else
        TriggerClientEvent('TMGCore:Notify', src, Lang:t('error.notenoughmoney'), 'error')
    end
end)



RegisterNetEvent('tmg-vehicleshop:server:settleFinanceFull', function(data)
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    if not Player or not data.vehPlate then return end

    local vehBalance = math.floor(tonumber(data.vehBalance) or 0)
    local vehPlate = data.vehPlate:gsub("%s+", ""):upper()

    if vehBalance <= 0 then
        return TriggerClientEvent('TMGCore:Notify', src, Lang:t('error.alreadypaid'), 'error')
    end

    local paymentType = Player.PlayerData.money.cash >= vehBalance and 'cash' or 'bank'
    
    if Player.PlayerData.money[paymentType] >= vehBalance then
        Player.Functions.RemoveMoney(paymentType, vehBalance, 'vehicle-finance-settlement')

        local settlementData = {
            ["$set"] = {
                ["balance"] = 0,
                ["paymentamount"] = 0,
                ["paymentsleft"] = 0,
                ["financetime"] = 0
            }
        }

        exports['tmgnosql']:UpdateOne('player_vehicles', { ["plate"] = vehPlate }, settlementData, function(success)
            if success then
                TriggerClientEvent('TMGCore:Notify', src, "Mainframe: Asset title cleared. Full ownership acknowledged.", 'success')
                
                print(string.format("^5[TMG]^7 Finance: CID %s fully settled debt for Plate [%s]", Player.PlayerData.citizenid, vehPlate))
            else
                print(string.format("^1[TMG Critical]^7 Registry Sync Failure: CID %s settled plate %s but DB update failed.", Player.PlayerData.citizenid, vehPlate))
            end
        end)
    else
        TriggerClientEvent('TMGCore:Notify', src, Lang:t('error.notenoughmoney'), 'error')
    end
end)


RegisterNetEvent('tmg-vehicleshop:server:purchaseShowroomAsset', function(data)
    local src = source
    local vehicle = data.buyVehicle
    local Player = TMGCore.Functions.GetPlayer(src)
    if not Player or not vehicle then return end

    local vehiclePrice = TMGCore.Shared.Vehicles[vehicle] and TMGCore.Shared.Vehicles[vehicle].price or 0
    
    local plate = GeneratePlate() 

    local paymentType = Player.PlayerData.money.cash >= vehiclePrice and 'cash' or 'bank'

    if Player.PlayerData.money[paymentType] >= vehiclePrice then
        Player.Functions.RemoveMoney(paymentType, vehiclePrice, 'showroom-purchase')

        local vehicleDocument = {
            ["license"] = Player.PlayerData.license,
            ["citizenid"] = Player.PlayerData.citizenid,
            ["vehicle"] = vehicle,
            ["hash"] = GetHashKey(vehicle),
            ["mods"] = {}, 
            ["plate"] = plate,
            ["garage"] = 'pillboxgarage', 
            ["state"] = 0,
            ["balance"] = 0, 
            ["paymentamount"] = 0,
            ["paymentsleft"] = 0,
            ["financetime"] = 0,
            ["purchase_date"] = os.time()
        }

        exports['tmgnosql']:InsertOne('player_vehicles', vehicleDocument, function(success)
            if success then
                TriggerClientEvent('TMGCore:Notify', src, Lang:t('success.purchased'), 'success')
                TriggerClientEvent('tmg-vehicleshop:client:spawnPurchasedVehicle', src, vehicle, plate)
                
                print(string.format("^5[TMG]^7 Economy: Asset [%s] registered to CID [%s]", plate, Player.PlayerData.citizenid))
            else
                print(string.format("^1[TMG Critical]^7 Registry Sync Failure: CID %s paid $%d but document insertion failed.", Player.PlayerData.citizenid, vehiclePrice))
            end
        end)
    else
        TriggerClientEvent('TMGCore:Notify', src, Lang:t('error.notenoughmoney'), 'error')
    end
end)



RegisterNetEvent('tmg-vehicleshop:server:financeAsset', function(downPayment, paymentAmount, vehicle)
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    if not Player or not vehicle then return end

    downPayment = tonumber(downPayment) or 0
    paymentAmount = tonumber(paymentAmount) or 0
    
    local vehiclePrice = TMGCore.Shared.Vehicles[vehicle] and TMGCore.Shared.Vehicles[vehicle].price or 0
    local minDown = math.floor((Config.MinimumDown / 100) * vehiclePrice)
    local timer = (Config.PaymentInterval * 60)

    if downPayment > vehiclePrice then 
        return TriggerClientEvent('TMGCore:Notify', src, Lang:t('error.notworth'), 'error') 
    end
    if downPayment < minDown then 
        return TriggerClientEvent('TMGCore:Notify', src, Lang:t('error.downtoosmall'), 'error') 
    end
    if paymentAmount > Config.MaximumPayments then 
        return TriggerClientEvent('TMGCore:Notify', src, Lang:t('error.exceededmax'), 'error') 
    end

    local plate = GeneratePlate()
    local balance, installmentPrice = calculateFinance(vehiclePrice, downPayment, paymentAmount)

    local paymentType = Player.PlayerData.money.cash >= downPayment and 'cash' or 'bank'

    if Player.PlayerData.money[paymentType] >= downPayment then
        Player.Functions.RemoveMoney(paymentType, downPayment, 'vehicle-finance-downpayment')

        local vehicleDocument = {
            ["license"] = Player.PlayerData.license,
            ["citizenid"] = Player.PlayerData.citizenid,
            ["vehicle"] = vehicle,
            ["hash"] = GetHashKey(vehicle),
            ["mods"] = {},
            ["plate"] = plate,
            ["garage"] = 'pillboxgarage',
            ["state"] = 0,
            ["balance"] = balance, 
            ["paymentamount"] = installmentPrice, 
            ["paymentsleft"] = paymentAmount, 
            ["financetime"] = timer, 
            ["timestamp"] = os.time()
        }

        exports['tmgnosql']:InsertOne('player_vehicles', vehicleDocument, function(success)
            if success then
                TriggerClientEvent('TMGCore:Notify', src, Lang:t('success.purchased'), 'success')
                TriggerClientEvent('tmg-vehicleshop:client:spawnPurchasedVehicle', src, vehicle, plate)
                
                print(string.format("^5[TMG]^7 Finance: CID %s anchored loan for [%s] | Balance: $%d", 
                   Player.PlayerData.citizenid, plate, balance))
            else
                print(string.format("^1[TMG Critical]^7 Registry Sync Failure: CID %s paid downpayment but loan insertion failed.", Player.PlayerData.citizenid))
            end
        end)
    else
        TriggerClientEvent('TMGCore:Notify', src, Lang:t('error.notenoughmoney'), 'error')
    end
end)


RegisterNetEvent('tmg-vehicleshop:server:sellShowroomVehicle', function(data, playerid)
    local src = source
    local Dealer = TMGCore.Functions.GetPlayer(src)
    local Buyer = TMGCore.Functions.GetPlayer(tonumber(playerid))

    if not Dealer or not Buyer then
        return TriggerClientEvent('TMGCore:Notify', src, Lang:t('error.Invalid_ID'), 'error')
    end

    local dist = #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(GetPlayerPed(Buyer.PlayerData.source)))
    if dist > 3.0 then
        return TriggerClientEvent('TMGCore:Notify', src, Lang:t('error.playertoofar'), 'error')
    end

    local vehicle = data
    local vehiclePrice = TMGCore.Shared.Vehicles[vehicle] and TMGCore.Shared.Vehicles[vehicle].price or 0
    local commission = math.floor(vehiclePrice * (Config.Commission or 0.10))
    local plate = GeneratePlate() 

    local paymentType = Buyer.PlayerData.money.cash >= vehiclePrice and 'cash' or 'bank'

    if Buyer.PlayerData.money[paymentType] >= vehiclePrice then
        local vehicleDoc = {
            ["license"] = Buyer.PlayerData.license,
            ["citizenid"] = Buyer.PlayerData.citizenid,
            ["vehicle"] = vehicle,
            ["hash"] = GetHashKey(vehicle),
            ["mods"] = {}, 
            ["plate"] = plate,
            ["garage"] = 'pillboxgarage',
            ["state"] = 0,
            ["balance"] = 0, 
            ["sale_metadata"] = {
                ["dealer"] = Dealer.PlayerData.citizenid,
                ["timestamp"] = os.time()
            }
        }

        exports['tmgnosql']:InsertOne('player_vehicles', vehicleDoc, function(success)
            if success then
                Buyer.Functions.RemoveMoney(paymentType, vehiclePrice, 'showroom-purchase-assisted')
                Dealer.Functions.AddMoney('bank', commission, 'vehicle-sale-commission')
                
                exports['tmg-banking']:AddMoney(Dealer.PlayerData.job.name, vehiclePrice, 'Vehicle Sale: '..plate)

                TriggerClientEvent('tmg-vehicleshop:client:spawnPurchasedVehicle', Buyer.PlayerData.source, vehicle, plate)
                
                TriggerClientEvent('TMGCore:Notify', src, Lang:t('success.earned_commission', { amount = commission }), 'success')
                TriggerClientEvent('TMGCore:Notify', Buyer.PlayerData.source, Lang:t('success.purchased'), 'success')
                
                print(string.format("^5[TMG]^7 Commerce: Dealer %s sold [%s] to CID %s", Dealer.PlayerData.citizenid, plate, Buyer.PlayerData.citizenid))
            else
                TriggerClientEvent('TMGCore:Notify', src, "Mainframe Critical: Registry injection failed. Transaction aborted.", 'error')
            end
        end)
    else
        TriggerClientEvent('TMGCore:Notify', src, Lang:t('error.notenoughmoney'), 'error')
    end
end)


RegisterNetEvent('tmg-vehicleshop:server:sellFinanceAsset', function(downPayment, paymentAmount, vehicle, playerid)
    local src = source
    local Dealer = TMGCore.Functions.GetPlayer(src)
    local Buyer = TMGCore.Functions.GetPlayer(tonumber(playerid))

    if not Dealer or not Buyer then
        return TriggerClientEvent('TMGCore:Notify', src, Lang:t('error.Invalid_ID'), 'error')
    end

    local dist = #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(GetPlayerPed(Buyer.PlayerData.source)))
    if dist > 3.0 then
        return TriggerClientEvent('TMGCore:Notify', src, Lang:t('error.playertoofar'), 'error')
    end

    downPayment = tonumber(downPayment) or 0
    paymentAmount = tonumber(paymentAmount) or 0
    local vehiclePrice = TMGCore.Shared.Vehicles[vehicle] and TMGCore.Shared.Vehicles[vehicle].price or 0
    local minDown = math.floor((Config.MinimumDown / 100) * vehiclePrice)
    
    if downPayment > vehiclePrice then return TriggerClientEvent('TMGCore:Notify', src, "Price integrity error.", 'error') end
    if downPayment < minDown then return TriggerClientEvent('TMGCore:Notify', src, Lang:t('error.downtoosmall'), 'error') end
    
    local commission = math.floor(vehiclePrice * (Config.Commission or 0.10))
    local plate = GeneratePlate() 
    local balance, installmentAmount = calculateFinance(vehiclePrice, downPayment, paymentAmount)
    local timer = (Config.PaymentInterval * 60)

    local paymentType = Buyer.PlayerData.money.cash >= downPayment and 'cash' or 'bank'

    if Buyer.PlayerData.money[paymentType] >= downPayment then
        local vehicleDoc = {
            ["license"] = Buyer.PlayerData.license,
            ["citizenid"] = Buyer.PlayerData.citizenid,
            ["vehicle"] = vehicle,
            ["hash"] = GetHashKey(vehicle),
            ["mods"] = {},
            ["plate"] = plate,
            ["garage"] = 'pillboxgarage',
            ["state"] = 0,
            ["balance"] = balance,
            ["paymentamount"] = installmentAmount,
            ["paymentsleft"] = paymentAmount,
            ["financetime"] = timer,
            ["dealer_audit"] = Dealer.PlayerData.citizenid
        }

        exports['tmgnosql']:InsertOne('player_vehicles', vehicleDoc, function(success)
            if success then
                Buyer.Functions.RemoveMoney(paymentType, downPayment, 'financed-showroom-downpayment')
                Dealer.Functions.AddMoney('bank', commission, 'vehicle-sale-commission')
                
                exports['tmg-banking']:AddMoney(Dealer.PlayerData.job.name, vehiclePrice, 'Financed Asset Sale: '..plate)

                TriggerClientEvent('tmg-vehicleshop:client:spawnPurchasedVehicle', Buyer.PlayerData.source, vehicle, plate)
                TriggerClientEvent('TMGCore:Notify', src, Lang:t('success.earned_commission', { amount = comma_value(commission) }), 'success')
                TriggerClientEvent('TMGCore:Notify', Buyer.PlayerData.source, Lang:t('success.purchased'), 'success')
            else
                TriggerClientEvent('TMGCore:Notify', src, "Mainframe Critical: Loan document rejected. Transaction aborted.", 'error')
            end
        end)
    else
        TriggerClientEvent('TMGCore:Notify', src, Lang:t('error.notenoughmoney'), 'error')
    end
end)


RegisterNetEvent('tmg-vehicleshop:server:checkFinance', function()
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    if not Player then return end

    local cid = Player.PlayerData.citizenid

    local filter = { 
        ["citizenid"] = cid, 
        ["balance"] = { ["$gt"] = 0 }, 
        ["financetime"] = { ["$lt"] = 1 } 
    }

    exports['tmgnosql']:FetchAll('player_vehicles', filter, function(results)
        if not results or #results == 0 then return end

        TriggerClientEvent('TMGCore:Notify', src, Lang:t('general.paymentduein', { time = Config.PaymentWarning }), 'primary', 10000)

        SetTimeout(Config.PaymentWarning * 60000, function()
            exports['tmgnosql']:FetchAll('player_vehicles', filter, function(finalResults)
                if not finalResults or #finalResults == 0 then return end

                for _, veh in pairs(finalResults) do
                    local plate = veh.plate
                    
                    exports['tmgnosql']:DeleteOne('player_vehicles', { ["plate"] = plate }, function(deleted)
                        if deleted then
                            TriggerClientEvent('TMGCore:Notify', src, Lang:t('error.repossessed', { plate = plate }), 'error', 15000)
                            
                            TriggerEvent('tmg-log:server:CreateLog', 'vehicleshop', 'Asset Seizure', 'red', 
                                string.format("**%s** (CID: %s) had vehicle [%s] repossessed for non-payment.", 
                                Player.PlayerData.name, cid, plate))
                            
                            print(string.format("^5[TMG]^7 Repo: Asset [%s] liquidated for CID [%s]", plate, cid))
                        end
                    end)
                end
            end)
        end)
    end)
end)


TMGCore.Commands.Add('transfervehicle', Lang:t('general.command_transfervehicle'), { 
    { name = 'ID', help = Lang:t('general.command_transfervehicle_help') }, 
    { name = 'amount', help = Lang:t('general.command_transfervehicle_amount') } 
}, false, function(source, args)
    local src = source
    local buyerId = tonumber(args[1])
    local sellAmount = math.abs(tonumber(args[2]) or 0) 
    
    local Player = TMGCore.Functions.GetPlayer(src)
    local Target = TMGCore.Functions.GetPlayer(buyerId)
    
    if not Target or buyerId == src then 
        return TriggerClientEvent('TMGCore:Notify', src, Lang:t('error.buyerinfo'), 'error') 
    end

    local ped = GetPlayerPed(src)
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then 
        return TriggerClientEvent('TMGCore:Notify', src, Lang:t('error.notinveh'), 'error') 
    end

    local plate = TMGCore.Shared.Trim(GetVehicleNumberPlateText(vehicle)):upper()
    
    exports['tmgnosql']:FetchOne('player_vehicles', { ["plate"] = plate }, function(vehRow)
        if not vehRow then 
            return TriggerClientEvent('TMGCore:Notify', src, Lang:t('error.vehinfo'), 'error') 
        end
        if vehRow.citizenid ~= Player.PlayerData.citizenid then 
            return TriggerClientEvent('TMGCore:Notify', src, Lang:t('error.notown'), 'error') 
        end
        if Config.PreventFinanceSelling and (vehRow.balance or 0) > 0 then 
            return TriggerClientEvent('TMGCore:Notify', src, Lang:t('error.financed'), 'error') 
        end
        if #(GetEntityCoords(ped) - GetEntityCoords(GetPlayerPed(buyerId))) > 5.0 then 
            return TriggerClientEvent('TMGCore:Notify', src, Lang:t('error.playertoofar'), 'error') 
        end

        local function CompleteTransfer()
            local updateData = {
                ["$set"] = {
                    ["citizenid"] = Target.PlayerData.citizenid,
                    ["license"] = Target.PlayerData.license,
                    ["state"] = 0 
                }
            }

            exports['tmgnosql']:UpdateOne('player_vehicles', { ["plate"] = plate }, updateData, function(success)
                if success then
                    TriggerClientEvent('vehiclekeys:client:SetOwner', buyerId, plate)
                    TriggerClientEvent('TMGCore:Notify', src, Lang:t('success.soldfor') .. comma_value(sellAmount), 'success')
                    TriggerClientEvent('TMGCore:Notify', buyerId, Lang:t('success.boughtfor') .. comma_value(sellAmount), 'success')
                    
                    print(string.format("^5[TMG]^7 Transfer: [%s] migrated from %s to %s", plate, Player.PlayerData.citizenid, Target.PlayerData.citizenid))
                end
            end)
        end

        if sellAmount <= 0 then
            CompleteTransfer() 
        else
            local paymentType = Target.PlayerData.money.cash >= sellAmount and 'cash' or 'bank'
            
            if Target.PlayerData.money[paymentType] >= sellAmount then
                Target.Functions.RemoveMoney(paymentType, sellAmount, 'bought-vehicle-p2p')
                Player.Functions.AddMoney(paymentType, sellAmount, 'sold-vehicle-p2p')
                CompleteTransfer()
            else
                TriggerClientEvent('TMGCore:Notify', src, Lang:t('error.buyertoopoor'), 'error')
            end
        end
    end)
end)
