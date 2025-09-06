Config = {}

-- A) Limity
Config.WarnAfterSeconds      = 10   -- po toľkých sekundách vo vode "bez ochrany" spustíme finálny odpočet
Config.FinalCountdownSeconds = 8        -- dĺžka finálneho odpočtu (po varovaní)

-- B) Detekcia vody
Config.Water = {
  RequireSwimming = false,  -- false = stačí byť v/na vode
  MinSubmerged    = 0.20,   -- 0..1 (0.20 ~ po kolená, 0.50 ~ po pás, 1.0 = celé telo)
}

Config.Water.MinSubmerged    = 0.05

-- C) Výnimky – MUSÍ byť „equipped“, nie len v inventári
Config.Exemptions = {
  ExemptInVehicle    = true,      -- v člne/vozidle neriešime
  EquippedFlagName   = 'scuba',   -- meno statebag/flag-u na pede: Entity(ped).state[EquippedFlagName] == true
  UseHeuristicScuba  = false,     -- ak nevieš flag, môžeš zapnúť heuristiku (dlhý oxygen pod vodou)
}

-- D) Notifikácie (ox_lib)
Config.Notify = {
  OnWarn  = { msg = 'Pozor! Začínaš sa topiť.', type = 'error',   time = 5000 },
  OnSafe  = { msg = 'Prestal si sa topiť.',                                       type = 'success', time = 3000 },
  OnDeath = { msg = 'Utopil si sa.',                                              type = 'error',   time = 4000 },
}

-- E) Progress bar (ox_lib)
Config.Progress = {
  label     = 'Topíš sa…',
  position  = 'bottom',       -- 'bottom' | 'top' | 'middle'
  useCircle = true,           -- true = progressCircle, false = progressBar
  canCancel = false,          -- hráč nemôže sám cancelnúť (rušíme to my, keď je safe)
  disable   = { move = false, car = false, mouse = false, combat = false },
}

-- Debug overlay
Config.Debug = false
