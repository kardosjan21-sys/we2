local PolyZone = exports['PolyZone']
local QBCore = exports['qb-core']:GetCoreObject()

local zoneActive = false

-- ================== helpers ==================
local function notify(entry)
    if not entry or not entry.msg then return end
    if not lib or type(lib.notify) ~= 'function' then
        print(('[anti_waterevade] %s'):format(entry.msg))
        return
    end
    lib.notify({
        description = entry.msg,
        type = entry.type or 'inform',
        duration = entry.time or 3000,
        position = 'top-right'
    })
end

local function isEquippedScuba(ped)
    -- primárny spôsob: statebag flag (napr. state["diving_gear"] = true pri "use" itemu)
    local key = Config.Exemptions.EquippedFlagName
    if key then
        -- skús najprv statebag hráča
        if LocalPlayer.state and LocalPlayer.state[key] then
            return true
        end
        -- potom entita pedu
        local ok, ent = pcall(function() return Entity(ped) end)
        if ok and ent and ent.state and ent.state[key] then
            return true
        end
    end
    -- voliteľná heuristika (dlhý čas pod vodou => zrejme scuba)
    if Config.Exemptions.UseHeuristicScuba and IsPedSwimmingUnderWater(ped) then
        local t = GetPlayerUnderwaterTimeRemaining(PlayerId())
        if t and t > 20.0 then return true end
    end
    return false
end

-- helper to (de)activate scuba flag on player and ped
local function setScubaEquipped(enabled)
    local key = Config.Exemptions and Config.Exemptions.EquippedFlagName or 'divinggear'
    LocalPlayer.state:set(key, enabled, true)
    local ped = PlayerPedId()
    local ok, ent = pcall(function() return Entity(ped) end)
    if ok and ent and ent.state then
        ent.state:set(key, enabled, true)
    end
end



local lastUnsafe, safeSince = false, nil

local function isInWaterUnprotected(ped)
    -- výnimka: vozidlo
    if Config.Exemptions.ExemptInVehicle and IsPedInAnyVehicle(ped, false) then
        lastUnsafe = false; safeSince = GetGameTimer(); return false
    end

    local inWater    = IsEntityInWater(ped)
    local submerged  = GetEntitySubmergedLevel(ped) or 0.0
    local isSwim     = IsPedSwimming(ped) or IsPedSwimmingUnderWater(ped)

    -- uznaj aj plávanie na hladine (isSwim) alebo dostatočný ponor
    local waterOK
    if Config.Water.RequireSwimming then
        waterOK = isSwim   -- vyžadujeme plávanie
    else
        waterOK = inWater and (isSwim or submerged >= (Config.Water.MinSubmerged or 0.20))
    end
    if not waterOK then
        -- trochu hysterézy: musíme byť "safe" aspoň 1500 ms, aby sa timer resetol
        if lastUnsafe then
            safeSince = safeSince or GetGameTimer()
            if GetGameTimer() - safeSince > 1500 then
                lastUnsafe = false
            end
        end
        return false
    end

    if isEquippedScuba(ped) then
        lastUnsafe = false
        safeSince = GetGameTimer()
        return false
    end

    -- sme nechránene vo vode
    lastUnsafe = true; safeSince = nil
    return true
end

-- prepínač výstroje (equip/unequip)
RegisterNetEvent('anti_waterevade:toggleScuba', function()
    local key = Config.Exemptions.EquippedFlagName or 'divinggear'
    local newVal = not LocalPlayer.state[key]

    setScubaEquipped(newVal)

    lib.notify({
        description = newVal and 'Nasadil si potápačskú výstroj.' or 'Zložil si potápačskú výstroj.',
        type = newVal and 'success' or 'warning'
    })
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    setScubaEquipped(false)
end)

RegisterNetEvent('qb-diving:client:UseGear', function()
    local key = Config.Exemptions and Config.Exemptions.EquippedFlagName or 'divinggear'
    setScubaEquipped(not LocalPlayer.state[key])
end)
-- ================== stav ==================
local startWaterTime  = nil   -- kedy začal „unprotected“ pobyt vo vode
local inCountdown     = false -- beží finálny odpočet
local countdownThread = nil
local cancelRequested = false -- požiadavka na zrušenie progressu

-- bezpečné zrušenie ox_lib progressu (ak existuje API)
local function cancelProgressSafe()
    if inCountdown then
        cancelRequested = true
    end
    pcall(function()
        if lib and type(lib.cancelProgress) == 'function' then
            if not lib.progressActive or lib.progressActive() then
                lib.cancelProgress()
            end
        end
    end)
end  


-- spustenie finálneho odpočtu (beží v samostatnom vlákne)
local function startFinalCountdown(seconds)
    if inCountdown then return end
    inCountdown = true
    cancelRequested = false

    notify(Config.Notify.OnWarn)
    if Config.Debug then
        print(('[anti_waterevade] FINAL COUNTDOWN START: %ds'):format(seconds or Config.FinalCountdownSeconds or 60))
    end

    countdownThread = CreateThread(function()
        if not zoneActive then inCountdown = false; cancelRequested = false; return end
        local dur = (seconds or Config.FinalCountdownSeconds or 60) * 1000

        -- počkaj, kým nebeží iný progress (max ~1.5s)
        if lib and type(lib.progressActive) == 'function' then
            local untilTs = GetGameTimer() + 1500
        while zoneActive and lib.progressActive() and GetGameTimer() < untilTs do
                if cancelRequested then inCountdown = false; cancelRequested = false; return end
                Wait(50)
            end
            if not zoneActive then inCountdown = false; cancelRequested = false; return end
        end   

        local opts = {
            duration     = dur,
            label        = Config.Progress.label or 'Topíš sa…',
            position     = Config.Progress.position or 'middle',
            useWhileDead = false,
            canCancel    = Config.Progress.canCancel or false,
            disable      = Config.Progress.disable or {},
        }

        local shown = false
        if lib then
            if Config.Progress.useCircle and type(lib.progressCircle) == 'function' then
                local ok = lib.progressCircle(opts); shown = (ok ~= nil)
            end
            if not shown and type(lib.progressBar) == 'function' then
                local ok = lib.progressBar(opts); shown = (ok ~= nil)
            end
        end

        -- fallback – aj keby ox_lib progress neotvoril overlay
         if not shown then
            local deadline = GetGameTimer() + dur
            while zoneActive and GetGameTimer() < deadline and not cancelRequested do
                SetTextFont(4); SetTextScale(0.5,0.5); SetTextCentre(true); SetTextOutline()
                SetTextColour(255,255,255,230)
                BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName('Topíš sa…'); EndTextCommandDisplayText(0.5,0.48)
                local left = (deadline - GetGameTimer()) / dur
                DrawRect(0.5, 0.52, 0.30, 0.014, 0,0,0,160)
                DrawRect(0.35 + 0.15*left, 0.52, 0.30*left, 0.012, 255,255,255,220)
                Wait(0)
            end
            if not zoneActive then inCountdown = false; cancelRequested = false; return end
        end

        if cancelRequested or not zoneActive then
            inCountdown = false; cancelRequested = false
            if Config.Debug then print('[anti_waterevade] FINAL: cancelled (manual)') end
            return
        end

        -- po skončení – ak stále nie je safe, zabime hráča
         local ped = PlayerPedId()
        if isInWaterUnprotected(ped) then
            SetEntityHealth(ped, 0)
            notify(Config.Notify.OnDeath)
            if Config.Debug then print('[anti_waterevade] FINAL: drowned') end
        else
            if Config.Debug then print('[anti_waterevade] FINAL: cancelled (safe)') end
        end

        inCountdown = false
        cancelRequested = false
    end)
end

-- ================== monitorovanie ==================
local function startMonitoring()
    CreateThread(function()
        while zoneActive do
            local ped = PlayerPedId()
            local unprotected = isInWaterUnprotected(ped)

            if not unprotected then
                -- reset všetkého
                if startWaterTime or inCountdown then
                    startWaterTime = nil
                    if inCountdown then
                        cancelProgressSafe()
                        inCountdown = false
                    end
                    notify(Config.Notify.OnSafe)
                    if Config.Debug then print('[anti_waterevade] SAFE: reset') end
                end
                Wait(800)
            else
                -- sme v nechránenej vode
                if not startWaterTime then
                    startWaterTime = GetGameTimer()
                    if Config.Debug then print('[anti_waterevade] DANGER: started') end
                end

                -- po uplynutí varovného času spustiť finálny odpočet raz
                if not inCountdown then
                    local elapsed = (GetGameTimer() - startWaterTime) / 1000.0
                    if elapsed >= (Config.WarnAfterSeconds or 600) then
                        startFinalCountdown(Config.FinalCountdownSeconds or 60)
                    end
                end

                Wait(250)
            end
        end
    end)
end

local test2Zone = PolyZone:Create({
    -- TODO: replace placeholder coordinates with actual zone data
    vector2(0.0, 0.0),
    vector2(10.0, 0.0),
    vector2(10.0, 10.0),
    vector2(0.0, 10.0)
}, {name = 'test2', debugPoly = false})

test2Zone:onPlayerInOut(function(isInside)
    if isInside and not zoneActive then
        zoneActive = true
        startMonitoring()
    elseif not isInside and zoneActive then
        zoneActive = false
    end
end)

-- ================== debug overlay ==================
local dbg = false

RegisterCommand('drown_debug', function()
    Config.Debug = not Config.Debug
    dbg = Config.Debug
    lib.notify({
        description = ('anti_waterevade debug: %s'):format(dbg and 'ON' or 'OFF'),
        type = dbg and 'success' or 'error',
        duration = 2000
    })
end, false)

CreateThread(function()
    while true do
        if zoneActive and dbg then
            local ped = PlayerPedId()
            local inWater = IsEntityInWater(ped)
            local swim = IsPedSwimming(ped) or IsPedSwimmingUnderWater(ped)
            local sub = GetEntitySubmergedLevel(ped) or 0.0
            local veh = IsPedInAnyVehicle(ped, false)
            local eq  = isEquippedScuba(ped)
            local now = GetGameTimer()
            local elapsed = startWaterTime and ((now - startWaterTime) / 1000.0) or 0.0

            SetTextFont(0)
            SetTextScale(0.35, 0.35)
            SetTextColour(255,255,255,220)
            SetTextOutline()
            BeginTextCommandDisplayText('STRING')
            AddTextComponentSubstringPlayerName((
                '[anti_waterevade]\nwater=%s swim=%s submerged=%.2f veh=%s\nEQUIPPED=%s elapsed=%.1fs\ncountdown=%s'
            ):format(tostring(inWater), tostring(swim), sub, tostring(veh), tostring(eq), elapsed, tostring(inCountdown)))
            EndTextCommandDisplayText(0.015, 0.75)
            DrawRect(0.11, 0.805, 0.20, 0.13, 0,0,0,110)
            Wait(0)
        else
            Wait(800)
        end
    end
end)

-- ================== pomocné test príkazy (voliteľné) ==================
RegisterCommand('scuba_on', function()
    local key = Config.Exemptions.EquippedFlagName or 'divinggear'
    LocalPlayer.state:set(key, true, true)
    local ped = PlayerPedId()
    local ok, ent = pcall(function() return Entity(ped) end)
    if ok and ent and ent.state then
        ent.state:set(key, true, true)
    end
    lib.notify({ description='SCUBA equipped (test)', type='success' })
end, false)

RegisterCommand('scuba_off', function()
    local key = Config.Exemptions.EquippedFlagName or 'divinggear'
    LocalPlayer.state:set(key, false, true)
    local ped = PlayerPedId()
    local ok, ent = pcall(function() return Entity(ped) end)
    if ok and ent and ent.state then
        ent.state:set(key, false, true)
    end
    lib.notify({ description='SCUBA unequipped (test)', type='warning' })
end, false)

RegisterCommand('scuba_state', function()
    local key = Config.Exemptions.EquippedFlagName or 'divinggear'
    local pVal = LocalPlayer.state[key]
    local ped = PlayerPedId()
    local ok, ent = pcall(function() return Entity(ped) end)
    local eVal = ok and ent and ent.state and ent.state[key]
    print('diving gear flag (player,ped) =', tostring(pVal), tostring(eVal))
    lib.notify({ description = key..': '..tostring(pVal)..' (ped '..tostring(eVal)..')', type = 'inform' })
end, false)

-- sanity testy ox_lib
RegisterCommand('oxtest', function()
    lib.notify({ description='ox_lib OK', type='success' })
    local hasCircle = type(lib.progressCircle) == 'function'
    lib.notify({ description='progressCircle: '..tostring(hasCircle), type= hasCircle and 'inform' or 'warning' })
    if hasCircle then
        lib.progressCircle({ duration=3000, label='Test progress', position='bottom', canCancel=false })
    else
        lib.progressBar({ duration=3000, label='Test progress (bar)', position='bottom', canCancel=false })
    end
end, false)

RegisterCommand('drown_force', function()
    startFinalCountdown(8) -- rýchly 8s test
end, false)

