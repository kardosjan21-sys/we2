local QBCore = exports['qb-core']:GetCoreObject()

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
    -- primárny spôsob: statebag flag (napr. Entity(ped).state.scuba = true pri "use" itemu)
    local ok, ent = pcall(function() return Entity(ped) end)
    if ok and ent and ent.state and Config.Exemptions.EquippedFlagName then
        if ent.state[Config.Exemptions.EquippedFlagName] then
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

    -- výstroj (musí byť equipped, nie len v inventári)
    if isEquippedScuba(ped) then
        lastUnsafe = false; safeSince = GetGameTimer(); return false
    end

    -- sme nechránene vo vode
    lastUnsafe = true; safeSince = nil
    return true
end


-- ================== stav ==================
local startWaterTime  = nil   -- kedy začal „unprotected“ pobyt vo vode
local inCountdown     = false -- beží finálny odpočet
local countdownThread = nil

-- bezpečné zrušenie ox_lib progressu (ak existuje API)
local function cancelProgressSafe()
    pcall(function()
        if lib and type(lib.cancelProgress) == 'function' then
            lib.cancelProgress()
        end
    end)
end

-- spustenie finálneho odpočtu (beží v samostatnom vlákne)
local function startFinalCountdown(seconds)
    if inCountdown then return end
    inCountdown = true

    notify(Config.Notify.OnWarn)  -- „Pozor! Začínaš sa topiť“
    if Config.Debug then
        print(('[anti_waterevade] FINAL COUNTDOWN START: %ds'):format(seconds or Config.FinalCountdownSeconds or 60))
    end

    countdownThread = CreateThread(function()
        local dur = (seconds or Config.FinalCountdownSeconds or 60) * 1000
        local progress

        if lib then
            if Config.Progress.useCircle and type(lib.progressCircle) == 'function' then
                progress = lib.progressCircle
            elseif type(lib.progressBar) == 'function' then
                progress = lib.progressBar
            end
        end

        local deadline = GetGameTimer() + dur
        if progress then
            progress({
                duration     = dur,
                label        = Config.Progress.label or 'Topíš sa…',
                position     = Config.Progress.position or 'bottom',
                useWhileDead = false,
                canCancel    = Config.Progress.canCancel or false,
                disable      = Config.Progress.disable or {},
            })
            local remaining = deadline - GetGameTimer()
            if remaining > 0 then Wait(remaining) end
        else
            -- fallback wait if ox_lib progress is unavailable
            Wait(dur)
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
    end)
end

-- ================== hlavná slučka ==================
CreateThread(function()
    while true do
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
        if dbg then
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
    local ped = PlayerPedId()
    local ok, ent = pcall(function() return Entity(ped) end)
    if ok and ent and ent.state and Config.Exemptions.EquippedFlagName then
        ent.state[Config.Exemptions.EquippedFlagName] = true
    end
    lib.notify({ description='SCUBA equipped (test)', type='success' })
end, false)

RegisterCommand('scuba_off', function()
    local ped = PlayerPedId()
    local ok, ent = pcall(function() return Entity(ped) end)
    if ok and ent and ent.state and Config.Exemptions.EquippedFlagName then
        ent.state[Config.Exemptions.EquippedFlagName] = false
    end
    lib.notify({ description='SCUBA unequipped (test)', type='warning' })
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
