local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Vérifie si un joueur est un coéquipier
local function isTeammate(otherPlayer)
    -- Si pas de système de teams, retourne false
    if not player.Team or not otherPlayer.Team then
        return false
    end
    -- Même équipe = coéquipier
    return player.Team == otherPlayer.Team
end

-- Trouve le joueur ENNEMI le plus proche du curseur
local function getClosestEnemyToCursor()
    local mousePos = UserInputService:GetMouseLocation()
    local closestPlayer = nil
    local closestDist = math.huge

    for _, otherPlayer in ipairs(Players:GetPlayers()) do
        -- Ignore soi-même
        if otherPlayer ~= player and otherPlayer.Character then
            -- Ignore les coéquipiers
            if not isTeammate(otherPlayer) then
                local head = otherPlayer.Character:FindFirstChild("Head")
                if head then
                    local screenPos, onScreen = camera:WorldToViewportPoint(head.Position)
                    if onScreen then
                        local dist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                        if dist < closestDist then
                            closestDist = dist
                            closestPlayer = otherPlayer
                        end
                    end
                end
            end
        end
    end
    return closestPlayer
end

-- Appui sur X → tp sur l'ennemi le plus proche du curseur
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.X then
        local target = getClosestEnemyToCursor()
        if target and target.Character then
            local myChar = player.Character
            local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")
            local targetHRP = target.Character:FindFirstChild("HumanoidRootPart")
            if myHRP and targetHRP then
                myHRP.CFrame = targetHRP.CFrame
            end
        end
    end
end)



local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local LP = Players.LocalPlayer

local G = getgenv()

if typeof(STATE) ~= "table" then
    if G.__AF_SINGLETON == true then
        warn("[ArsenalFinal] already running, exiting (don't execute twice)")
        return
    end
    G.__AF_SINGLETON = true
end

if G.__ArsenalRapid3 == nil then G.__ArsenalRapid3 = { enabled = true } end
if G.__ArsenalHitbox3 == nil then G.__ArsenalHitbox3 = { enabled = true } end
if G.__ArsenalOrig3 == nil then G.__ArsenalOrig3 = {} end
if G.__ArsenalHitboxOrig3 == nil then G.__ArsenalHitboxOrig3 = {} end
local gunFlags = G.__ArsenalRapid3
local hbFlags = G.__ArsenalHitbox3
local gunOrig = G.__ArsenalOrig3
local hbOrig = G.__ArsenalHitboxOrig3

if gunFlags.rapid == nil then gunFlags.rapid = true end
if gunFlags.infinite == nil then gunFlags.infinite = true end
if gunFlags.norecoil == nil then gunFlags.norecoil = true end

local FIRE_RATE = 0.03
local NO_RECOIL = 0
local HEAD_HB_SIZE = Vector3.new(16, 16, 16)

local STOCK_HB = Vector3.new(1.4497, 1.3017, 1.3017)
local STOCK_BODY_HB = Vector3.new(4.5, 4, 4) -- v18 leftover cleanup only, never expanded
local STOCK_HRP = Vector3.new(2, 2, 2)
local STOCK_UPPER = Vector3.new(2, 1.6, 1)
-- v20: Torso mode expands ONLY UpperTorso. v19 also resized HumanoidRootPart,
-- but HRP is the assembly root / Humanoid movement part -- resizing it breaks
-- the rig client-side and freezes enemy avatars in place. UpperTorso (2x2x1)
-- gives the same big body target without touching physics.
local TORSO_PARTS = { "UpperTorso" }
local hbCollide = {} -- orig CanCollide per part (stock torso parts are collidable)
local hbMass = {} -- orig Massless per part (stock torso parts are not massless)
local BUILD = "v21-mixedrotate"

-- v18: hitbox target modes. Defaults preserve old behaviour (Head only).
if hbFlags.mode == nil then hbFlags.mode = "Head" end -- "Head" | "Torso" | "Mixed"
if hbFlags.headSize == nil then hbFlags.headSize = HEAD_HB_SIZE end
if hbFlags.bodySize == nil then hbFlags.bodySize = Vector3.new(10, 10, 10) end
if hbFlags.mixedChance == nil then hbFlags.mixedChance = 50 end -- % of enemies assigned Head in Mixed mode

-- Stable per-character fallback for Mixed when no Player is found (weak keys, no leak).
local _mixedCache = setmetatable({}, { __mode = "k" })
local _ModeDropdown = nil

local function connect(sig, fn)
    if typeof(STATE) == "table" and STATE.connect then
        STATE.connect(sig, fn)
    else
        sig:Connect(fn)
    end
end

local function cleanup(fn)
    if typeof(STATE) == "table" and STATE.onCleanup then
        STATE.onCleanup(fn)
    end
end

local function saveGunOrig(w)
    local o = gunOrig[w.Name]
    if o then
        if o.recoil == nil then
            local rc = w:FindFirstChild("RecoilControl")
            if rc and rc:IsA("NumberValue") then o.recoil = rc.Value end
        end
        return
    end
    local fr = w:FindFirstChild("FireRate")
    local au = w:FindFirstChild("Auto")
    local rc = w:FindFirstChild("RecoilControl")
    gunOrig[w.Name] = {
        fr = (fr and fr:IsA("NumberValue")) and fr.Value or nil,
        auto = (au and au:IsA("BoolValue")) and au.Value or nil,
        recoil = (rc and rc:IsA("NumberValue")) and rc.Value or nil,
        hadInfinite = w:FindFirstChild("Infinite") ~= nil,
        addedInfinite = false,
    }
end

local function applyGuns()
    local weapons = RS:FindFirstChild("Weapons")
    if not weapons then return 0 end
    local n = 0
    for _, w in ipairs(weapons:GetChildren()) do
        if w:FindFirstChild("FireRate") == nil then continue end
        saveGunOrig(w)
        local o = gunOrig[w.Name]
        local fr = w:FindFirstChild("FireRate")
        if fr:IsA("NumberValue") then
            pcall(function() fr.Value = gunFlags.rapid and FIRE_RATE or o.fr end)
        end
        local au = w:FindFirstChild("Auto")
        if au and au:IsA("BoolValue") then
            pcall(function() au.Value = gunFlags.rapid and true or o.auto end)
        end
        local rc = w:FindFirstChild("RecoilControl")
        if rc and rc:IsA("NumberValue") then
            pcall(function() rc.Value = gunFlags.norecoil and NO_RECOIL or o.recoil end)
        end
        if gunFlags.infinite then
            if w:FindFirstChild("Infinite") == nil then
                local ok, _ = pcall(function()
                    local f = Instance.new("Folder")
                    f.Name = "Infinite"
                    f.Parent = w
                end)
                if ok then o.addedInfinite = true end
            end
        else
            if o.addedInfinite and not o.hadInfinite then
                local m = w:FindFirstChild("Infinite")
                if m then pcall(function() m:Destroy() end) end
                o.addedInfinite = false
            end
        end

        n += 1
    end
    return n
end

local function patchLiveTool(tool)
    local fr = tool:FindFirstChild("FireRate")
    if fr and fr:IsA("NumberValue") and gunFlags.rapid then
        pcall(function() fr.Value = FIRE_RATE end)
    end
    local au = tool:FindFirstChild("Auto")
    if au and au:IsA("BoolValue") and gunFlags.rapid then
        pcall(function() au.Value = true end)
    end
    local rc = tool:FindFirstChild("RecoilControl")
    if rc and rc:IsA("NumberValue") and gunFlags.norecoil then
        pcall(function() rc.Value = NO_RECOIL end)
    end
    if gunFlags.infinite and tool:FindFirstChild("Infinite") == nil then
        pcall(function()
            local f = Instance.new("Folder")
            f.Name = "Infinite"
            f.Parent = tool
        end)
    end
end

local function isEnemyChar(model)
    if model == LP.Character then return false end
    local plr = Players:GetPlayerFromCharacter(model)
    if plr == nil or plr == LP then return false end
    local wk = RS:FindFirstChild("wkspc")
    local ffa = wk and wk:FindFirstChild("FFA")
    if ffa and ffa:IsA("BoolValue") and ffa.Value then return true end
    if LP.Team == nil then return false end
    return plr.Team ~= LP.Team
end

local function isBig(hb)
    return hb and hb:IsA("BasePart") and hb.Size.X > 2.5
end

local function isTorsoBig(model)
    for _, n in ipairs(TORSO_PARTS) do
        local p = model:FindFirstChild(n)
        if p and p:IsA("BasePart") and p.Size.X > 3 then return true end
    end
    return false
end

local function getHead(model)
    local hb = model:FindFirstChild("HeadHB")
    if hb and hb:IsA("BasePart") then return hb end
    return nil
end

-- v18 expanded the part named "Hitbox" for Torso mode; hits on it deal no
-- damage, so v19 only ever RESTORES it (migration for users coming from v18).
local function restoreStaleHitbox(model)
    local bd = model:FindFirstChild("Hitbox")
    if bd and bd:IsA("BasePart") and bd.Size.X > 6 then
        local key = bd:GetFullName()
        pcall(function()
            bd.Size = hbOrig[key] or STOCK_BODY_HB
            bd.Massless = true
            bd.CanTouch = true
        end)
        local ad = bd:FindFirstChild("BodyShow")
        if ad then pcall(function() ad:Destroy() end) end
    elseif bd and bd:IsA("BasePart") then
        local ad = bd:FindFirstChild("BodyShow")
        if ad then pcall(function() ad:Destroy() end) end
    end
end

-- Mixed ROTATES over time: every ~6s each enemy is re-dealt head or torso
-- (weighted by mixedChance), so every target alternates instead of one guy
-- being permanently head and everyone else permanently body.
local function decideHit(model)
    local m = hbFlags.mode
    if m == "Torso" or m == "Body" then return "Body" end
    if m == "Mixed" then
        local chance = tonumber(hbFlags.mixedChance) or 50
        local bucket = math.floor(os.clock() / 6)
        local plr = nil
        pcall(function() plr = Players:GetPlayerFromCharacter(model) end)
        local id
        if plr and plr.UserId and plr.UserId > 0 then
            id = plr.UserId
        else
            id = 0
            local nm = model:GetFullName()
            for i = 1, #nm do id = (id * 31 + string.byte(nm, i)) % 100 end
        end
        return (((id + bucket * 61) % 100) < chance) and "Head" or "Body"
    end
    return "Head"
end

local function expandHead(model)
    local hb = getHead(model)
    if hb == nil then return end
    local size = hbFlags.headSize or HEAD_HB_SIZE
    local key = hb:GetFullName()
    if hbOrig[key] == nil then hbOrig[key] = hb.Size end
    pcall(function()
        if hb.Size ~= size then hb.Size = size end
        hb.CanCollide = false
        hb.Massless = true
        hb.CanTouch = false
        hb.CanQuery = true
        hb.Transparency = 1
    end)
    pcall(function()
        local ad = hb:FindFirstChild("HBShow")
        if not ad then
            ad = Instance.new("BoxHandleAdornment")
            ad.Name = "HBShow"
            ad.Adornee = hb
            ad.Color3 = Color3.fromRGB(255, 60, 60)
            ad.Transparency = 0.75
            ad.AlwaysOnTop = true
            ad.ZIndex = 5
            ad.Parent = hb
        end
        ad.Size = size
    end)
end

local function expandTorso(model)
    local size = hbFlags.bodySize or Vector3.new(10, 10, 10)
    for _, n in ipairs(TORSO_PARTS) do
        local bd = model:FindFirstChild(n)
        if bd and bd:IsA("BasePart") then
            local key = bd:GetFullName()
            if hbOrig[key] == nil then hbOrig[key] = bd.Size end
            if hbCollide[key] == nil then hbCollide[key] = bd.CanCollide end
            if hbMass[key] == nil then hbMass[key] = bd.Massless end
            pcall(function()
                if bd.Size ~= size then bd.Size = size end
                bd.CanCollide = false
                bd.Massless = true
                bd.CanTouch = false
                bd.CanQuery = true
                bd.Transparency = 1
            end)
        end
    end
    local torso = model:FindFirstChild("UpperTorso")
    if torso and torso:IsA("BasePart") then
        pcall(function()
            local ad = torso:FindFirstChild("BodyShow")
            if not ad then
                ad = Instance.new("BoxHandleAdornment")
                ad.Name = "BodyShow"
                ad.Adornee = torso
                ad.Color3 = Color3.fromRGB(80, 160, 255)
                ad.Transparency = 0.75
                ad.AlwaysOnTop = true
                ad.ZIndex = 5
                ad.Parent = torso
            end
            ad.Size = size
        end)
    end
end

local function restoreHead(model)
    local p = getHead(model)
    if p == nil then return end
    local key = p:GetFullName()
    if hbOrig[key] ~= nil then
        pcall(function() p.Size = hbOrig[key] end)
    else
        pcall(function() p.Size = STOCK_HB end)
    end
    pcall(function()
        p.Massless = false
        p.CanTouch = true
    end)
    local ad = p:FindFirstChild("HBShow")
    if ad then pcall(function() ad:Destroy() end) end
end

local function restoreTorso(model)
    for _, n in ipairs(TORSO_PARTS) do
        local p = model:FindFirstChild(n)
        if p and p:IsA("BasePart") then
            local key = p:GetFullName()
            pcall(function()
                p.Size = hbOrig[key] or STOCK_UPPER
                if hbCollide[key] ~= nil then p.CanCollide = hbCollide[key] else p.CanCollide = true end
                if hbMass[key] ~= nil then p.Massless = hbMass[key] else p.Massless = false end
                p.CanTouch = true
            end)
            local ad = p:FindFirstChild("BodyShow")
            if ad then pcall(function() ad:Destroy() end) end
        end
    end
end

-- v19 migration: a leftover v19 run may have left HumanoidRootPart huge, which
-- freezes that avatar. Restore it to stock (size + physics props) once.
local function restoreStaleHRP(model)
    local hrp = model:FindFirstChild("HumanoidRootPart")
    if hrp and hrp:IsA("BasePart") and hrp.Size.X > 3 then
        local key = hrp:GetFullName()
        pcall(function()
            hrp.Size = hbOrig[key] or STOCK_HRP
            if hbCollide[key] ~= nil then hrp.CanCollide = hbCollide[key] else hrp.CanCollide = true end
            if hbMass[key] ~= nil then hrp.Massless = hbMass[key] else hrp.Massless = false end
            hrp.CanTouch = true
        end)
        local ad = hrp:FindFirstChild("BodyShow")
        if ad then pcall(function() ad:Destroy() end) end
    end
end

local function restoreModel(model)
    restoreHead(model)
    restoreTorso(model)
    restoreStaleHitbox(model)
    restoreStaleHRP(model) -- v19 enlarged HRPs: put them back, then never touch HRP again
    _mixedCache[model] = nil
end

-- Mode-aware: expands the wanted part, restores the other so only one is big.
local function expandModel(model)
    restoreStaleHitbox(model) -- never leave a v18-style Hitbox expanded
    restoreStaleHRP(model) -- unfreeze avatars a v19 run left with a huge HRP
    local want = decideHit(model)
    if want == "Body" then
        expandTorso(model)
        restoreHead(model)
    else
        expandHead(model)
        restoreTorso(model)
    end
end

local function clearAdornsIfSmall(model)
    local hb = getHead(model)
    if hb and not isBig(hb) then
        local ad = hb:FindFirstChild("HBShow")
        if ad then pcall(function() ad:Destroy() end) end
    end
    if not isTorsoBig(model) then
        for _, n in ipairs(TORSO_PARTS) do
            local p = model:FindFirstChild(n)
            if p then
                local ad = p:FindFirstChild("BodyShow")
                if ad then pcall(function() ad:Destroy() end) end
            end
        end
    end
    restoreStaleHitbox(model)
end

local function applyHitboxes()
    for _, m in ipairs(workspace:GetChildren()) do
        if m:IsA("Model") then
            local hb = m:FindFirstChild("HeadHB")
            local torsoBig = isTorsoBig(m)
            if hb == nil and not torsoBig then
                restoreStaleHitbox(m)
                continue
            end
            if not hbFlags.enabled then
                if (hb and isBig(hb)) or torsoBig then
                    restoreModel(m)
                else
                    clearAdornsIfSmall(m)
                end
            elseif isEnemyChar(m) then
                expandModel(m)
            else
                if (hb and isBig(hb)) or torsoBig then
                    restoreModel(m)
                else
                    clearAdornsIfSmall(m)
                end
            end
        end
    end

    for _, m in ipairs(workspace:GetChildren()) do
        if m:IsA("Model") and isEnemyChar(m) then
            local hb = getHead(m)
            if hb and isBig(hb) then
                if hb.Massless == false or hb.CanTouch ~= false then
                    pcall(function()
                        hb.Massless = true
                        hb.CanTouch = false
                    end)
                end
            end
            for _, n in ipairs(TORSO_PARTS) do
                local p = m:FindFirstChild(n)
                if p and p:IsA("BasePart") and p.Size.X > 3 then
                    if p.Massless == false or p.CanTouch ~= false then
                        pcall(function()
                            p.Massless = true
                            p.CanTouch = false
                        end)
                    end
                end
            end
        end
    end
end

pcall(function()
    for _, m in ipairs(workspace:GetChildren()) do
        if m:IsA("Model") then
            local hb = m:FindFirstChild("HeadHB")
            local big = (hb and isBig(hb)) or isTorsoBig(m)
            if big then
                if not hbFlags.enabled or not isEnemyChar(m) then
                    restoreModel(m)
                else
                    pcall(function()
                        if hb and isBig(hb) then
                            hb.Massless = true
                            hb.CanTouch = false
                        end
                        for _, n in ipairs(TORSO_PARTS) do
                            local p = m:FindFirstChild(n)
                            if p and p:IsA("BasePart") and p.Size.X > 3 then
                                p.Massless = true
                                p.CanTouch = false
                            end
                        end
                    end)
                end
            else
                restoreStaleHitbox(m)
            end
        end
    end
end)

pcall(function()
    local weapons = RS:FindFirstChild("Weapons")
    if weapons then
        for _, w in ipairs(weapons:GetChildren()) do
            local o = gunOrig[w.Name]
            if o and o.addedPenetration and not o.hadPenetration then
                local m = w:FindFirstChild("Penetration")
                if m and m:IsA("IntValue") then pcall(function() m:Destroy() end) end
                o.addedPenetration = false
            end
        end
    end
end)

connect(UIS.InputBegan, function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.F1 then
        local anyOn = gunFlags.rapid or gunFlags.infinite or gunFlags.norecoil
        gunFlags.rapid, gunFlags.infinite, gunFlags.norecoil = not anyOn, not anyOn, not anyOn
        applyGuns()
        print("[ArsenalFinal] guns " .. (not anyOn and "ON" or "OFF") .. " (F1)")
    elseif input.KeyCode == Enum.KeyCode.F5 then
        hbFlags.enabled = not hbFlags.enabled
        applyHitboxes()
        print("[ArsenalFinal] hitbox " .. (hbFlags.enabled and "ON" or "OFF") .. " (F5)")
    elseif input.KeyCode == Enum.KeyCode.F6 then
        hbFlags.mode = (hbFlags.mode == "Head" and "Torso") or (hbFlags.mode == "Torso" and "Mixed") or "Head"
        if _ModeDropdown then pcall(function() _ModeDropdown:SetValue(hbFlags.mode) end) end
        applyHitboxes()
        print("[ArsenalFinal] hitbox mode " .. tostring(hbFlags.mode) .. " (F6)")
    end
end)

local pack = LP:FindFirstChild("Backpack")
if pack then
    connect(pack.ChildAdded, function(child)
        task.wait(0.3)
        patchLiveTool(child)
    end)
end

connect(LP.CharacterAdded, function()
    task.wait(1)
    pcall(applyHitboxes)
end)

connect(workspace.ChildAdded, function(child)
    if not hbFlags.enabled then return end
    if child:IsA("Model") then
        task.wait(1)
        if isEnemyChar(child) then expandModel(child) end
    end
end)

local hbAcc = 0
connect(RunService.Heartbeat, function(dt)
    hbAcc += dt
    if hbAcc < 2 then return end
    hbAcc = 0
    pcall(applyHitboxes)
end)

cleanup(function()
    G.__AF_SINGLETON = nil
end)

print("[ArsenalFinal] " .. BUILD .. " loaded (mode=" .. tostring(hbFlags.mode) .. ")")
applyGuns()
applyHitboxes()

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local Window = Fluent:CreateWindow({
    Title = "Arsenal",
    SubTitle = "rapid + inf + hitbox",
    TabWidth = 140,
    Size = UDim2.fromOffset(480, 400),
    Acrylic = false,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.RightShift,
})

cleanup(function()
    pcall(function() Window:Destroy() end)
end)

local Tabs = {
    Main = Window:AddTab({ Title = "Main", Icon = "" }),
}

Tabs.Main:AddParagraph({
    Title = "Status",
    Content = "Re-equip your gun once after toggling guns.\nF1 = guns, F5 = hitbox, F6 = head/torso/mixed, RightShift = hide UI.",
})

Tabs.Main:AddSection("Guns")

local RapidToggle = Tabs.Main:AddToggle("RapidFire", {
    Title = "Rapid Fire",
    Description = "0.03s fire rate, pistols full-auto",
    Default = gunFlags.rapid,
})
RapidToggle:OnChanged(function()
    gunFlags.rapid = RapidToggle.Value
    applyGuns()
end)

local InfToggle = Tabs.Main:AddToggle("InfAmmo", {
    Title = "Infinite Ammo",
    Description = "Game's own Infinite marker, shows 'inf'",
    Default = gunFlags.infinite,
})
InfToggle:OnChanged(function()
    gunFlags.infinite = InfToggle.Value
    applyGuns()
end)

local RecoilToggle = Tabs.Main:AddToggle("NoRecoil", {
    Title = "No Recoil",
    Description = "RecoilControl 0 (native-safe value)",
    Default = gunFlags.norecoil,
})
RecoilToggle:OnChanged(function()
    gunFlags.norecoil = RecoilToggle.Value
    applyGuns()
end)

Tabs.Main:AddSection("Hitbox")

local HBToggle = Tabs.Main:AddToggle("Hitboxes", {
    Title = "Enemy Hitboxes",
    Description = "Big invisible hitboxes on all enemies + boxes",
    Default = hbFlags.enabled,
})
HBToggle:OnChanged(function()
    hbFlags.enabled = HBToggle.Value
    applyHitboxes()
end)

_ModeDropdown = Tabs.Main:AddDropdown("HitboxMode", {
    Title = "Hitbox Target",
    Description = "Head = headshots only. Torso = body only. Mixed = split per enemy.",
    Values = { "Head", "Torso", "Mixed" },
    Multi = false,
    Default = (hbFlags.mode == "Torso" and 2) or (hbFlags.mode == "Mixed" and 3) or 1,
})
_ModeDropdown:SetValue(hbFlags.mode)
_ModeDropdown:OnChanged(function(Value)
    if Value == "Torso" or Value == "Mixed" or Value == "Head" then
        hbFlags.mode = Value
        applyHitboxes()
    end
end)

local HeadSizeSlider = Tabs.Main:AddSlider("HeadSize", {
    Title = "Head Size",
    Description = "HeadHB cube size (default 16)",
    Default = (hbFlags.headSize and math.clamp(math.floor(hbFlags.headSize.X), 2, 24)) or 16,
    Min = 2,
    Max = 24,
    Rounding = 0,
    Callback = function(Value)
        hbFlags.headSize = Vector3.new(Value, Value, Value)
        applyHitboxes()
    end
})
HeadSizeSlider:OnChanged(function(Value)
    hbFlags.headSize = Vector3.new(Value, Value, Value)
    applyHitboxes()
end)

local BodySizeSlider = Tabs.Main:AddSlider("BodySize", {
    Title = "Torso Size",
    Description = "UpperTorso cube size (default 10)",
    Default = (hbFlags.bodySize and math.clamp(math.floor(hbFlags.bodySize.X), 5, 24)) or 10,
    Min = 5,
    Max = 24,
    Rounding = 0,
    Callback = function(Value)
        hbFlags.bodySize = Vector3.new(Value, Value, Value)
        applyHitboxes()
    end
})
BodySizeSlider:OnChanged(function(Value)
    hbFlags.bodySize = Vector3.new(Value, Value, Value)
    applyHitboxes()
end)

local MixedSlider = Tabs.Main:AddSlider("MixedChance", {
    Title = "Mixed: Head Chance %",
    Description = "In Mixed mode, % of enemies set to Head (rest Torso)",
    Default = tonumber(hbFlags.mixedChance) or 50,
    Min = 0,
    Max = 100,
    Rounding = 0,
    Callback = function(Value)
        hbFlags.mixedChance = Value
        _mixedCache = setmetatable({}, { __mode = "k" })
        applyHitboxes()
    end
})
MixedSlider:OnChanged(function(Value)
    hbFlags.mixedChance = Value
    _mixedCache = setmetatable({}, { __mode = "k" })
    applyHitboxes()
end)

Window:SelectTab(1)
Fluent:Notify({
    Title = "Arsenal loaded",
    Content = "Rapid + inf + no recoil + head/torso/mixed ready.",
    Duration = 5,
})
