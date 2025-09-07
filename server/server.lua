local QBCore = exports['qb-core']:GetCoreObject()

QBCore.Functions.CreateUseableItem('diving_gear', function(source, item)
    TriggerClientEvent('anti_waterevade:toggleScuba', source)
end)
