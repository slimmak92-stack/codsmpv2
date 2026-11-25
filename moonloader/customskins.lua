-- customskins.lua (v0.9) - uses customskins_core.dll to add NEW ped ids
-- MoonLoader script for SA-MP 0.3.7 (DL) / GTA SA 1.0 US

script_name("CustomSkins")
script_author("draft")
script_version("0.9")

local ffi    = require("ffi")
local lfs    = require("lfs")
local inicfg = require("inicfg")

local FOLDER   = getGameDirectory() .. "\\custom_models"
local INI_FILE = "CustomSkins.ini"
local DLL_PATH = getGameDirectory() .. "\\moonloader\\lib\\customskins_core.dll"

local cfg = inicfg.load({ settings = { savedSkin = "", autoApply = true } }, INI_FILE)
inicfg.save(cfg, INI_FILE)

ffi.cdef[[
int CS_AddSkin(const char* dff, const char* txd, const char* name, int baseModel);
int CS_SlotsLeft();
]]
local okLoad, core = pcall(ffi.load, DLL_PATH)
if not okLoad then
    print("[CustomSkins] cannot load " .. DLL_PATH .. ": " .. tostring(core))
    core = nil
end

local ERR = {
    [-1] = "bad arguments", [-2] = "no free skin slots", [-3] = "txd slot",
    [-4] = "txd failed to load", [-5] = "AddPedModel failed",
    [-6] = "cannot open dff", [-7] = "dff has no clump", [-8] = "engine exception (caught)",
}

local skins = {}  -- lowerName -> { dff, txd, name, id }
local active, activeName, origSkin = nil, nil, nil
local busy = false

local function log(s) print("[CustomSkins] " .. s) end
local function say(s) sampAddChatMessage("{FFCC00}[CustomSkins]{FFFFFF} " .. s, -1) end

local function saveSkinState(n)
    cfg.settings.savedSkin = n or ""
    inicfg.save(cfg, INI_FILE)
end

-- file scan -----------------------------------------------------
local function scan(dir)
    for f in lfs.dir(dir) do
        if f ~= "." and f ~= ".." then
            local p = dir .. "\\" .. f
            local a = lfs.attributes(p)
            if a and a.mode == "directory" then
                scan(p)
            else
                local n = f:match("^(.+)%.[dD][fF][fF]$")
                if n then
                    local base = p:sub(1, -5)
                    for _, ext in ipairs({ ".txd", ".TXD", ".Txd" }) do
                        if lfs.attributes(base .. ext) then
                            skins[n:lower()] = { dff = p, txd = base .. ext, name = n }
                            break
                        end
                    end
                end
            end
        end
    end
end

local function rescan()
    local old = skins
    skins = {}
    if not lfs.attributes(FOLDER) then lfs.mkdir(FOLDER) end
    scan(FOLDER)
    for k, s in pairs(skins) do
        if old[k] and old[k].dff == s.dff then s.id = old[k].id end
    end
end

local function sortedNames()
    local t = {}
    for _, s in pairs(skins) do t[#t + 1] = s.name end
    table.sort(t, function(a, b) return a:lower() < b:lower() end)
    return t
end

local function findSkin(name)
    local q = name:lower()
    if skins[q] then return skins[q] end
    local hits = {}
    for k, s in pairs(skins) do
        if k:sub(1, #q) == q then hits[#hits + 1] = s end
    end
    if #hits == 0 then
        for k, s in pairs(skins) do
            if k:find(q, 1, true) then hits[#hits + 1] = s end
        end
    end
    if #hits == 1 then return hits[1] end
    return nil, #hits
end

-- loading -------------------------------------------------------
local function loadSkin(s)
    if s.id then return s.id end
    if not core then return nil, "customskins_core.dll not loaded" end
    log("loadSkin: calling CS_AddSkin for " .. s.name)
    local ok, id = pcall(core.CS_AddSkin, s.dff, s.txd, s.name, 0)
    if not ok then return nil, tostring(id) end
    if id < 0 then return nil, ERR[id] or ("error " .. id) end
    log("loadSkin: got id " .. id)
    s.id = id
    return id
end

local CUSTOM_MIN = 312 -- ids >= this are ours (see BASE_ID in the DLL)

-- Only gives control back. No teleport, no clearing tasks -> no visible hitch.
local function unfreezePlayer()
    if not doesCharExist(PLAYER_PED) then return end
    setPlayerControl(PLAYER_HANDLE, true)
    freezeCharPosition(PLAYER_PED, false)
end

local function wear(id)
    if not doesCharExist(PLAYER_PED) then return end
    requestModel(id)
    loadAllModelsNow()
    setPlayerModel(PLAYER_HANDLE, id)
    unfreezePlayer()
end

local function applySkinByName(name, silent)
    if busy then
        if not silent then say("busy, try again in a moment") end
        return false
    end
    local s, count = findSkin(name)
    if not s then
        if not silent then
            say(count and count > 1 and "multiple matches, be more specific (/models)"
                or "skin not found, try /models")
        end
        return false
    end

    busy = true
    local ok, res = pcall(function()
        if doesCharExist(PLAYER_PED) then
            local m = getCharModel(PLAYER_PED)
            if m < CUSTOM_MIN then origSkin = m end
        end
        local id, err = loadSkin(s)
        if not id then
            if not silent then say("failed: " .. tostring(err)) end
            return false
        end
        wear(id)
        active, activeName = id, s.name
        saveSkinState(s.name)
        if not silent then say("wearing " .. s.name .. " {AAAAAA}(auto-saved)") end
        return true
    end)
    busy = false

    if not ok then
        log("error: " .. tostring(res))
        if not silent then say("error, see moonloader.log") end
        return false
    end
    return res
end

local function removeSkin()
    if busy then return end
    busy = true
    pcall(function()
        local was = active
        active, activeName = nil, nil
        saveSkinState("")
        if origSkin and was then wear(origSkin) else unfreezePlayer() end
    end)
    busy = false
    say("back to normal skin {AAAAAA}(auto-save cleared)")
end

-- Optional (needs SAMP.Lua): swallow the server's own skin change for our player
-- so the vanilla skin never flashes. Falls back to the per-frame check in main().
local okEv, sampev = pcall(require, "samp.events")
if okEv and sampev then
    function sampev.onSetPlayerSkin(playerId, skinId)
        if active then
            local ok, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
            if ok and myId == playerId then
                origSkin = skinId
                return false
            end
        end
    end
end

-- main ----------------------------------------------------------
function main()
    while not isSampAvailable() do wait(100) end
    rescan()
    log("v0.9 started, dll " .. (core and "loaded" or "MISSING") .. ", " .. #sortedNames() .. " skins")
    if not core then say("{FF5555}customskins_core.dll missing in moonloader\\lib") end

    sampRegisterChatCommand("models", function()
        local names = sortedNames()
        if #names == 0 then say("no skins found in " .. FOLDER) return end
        for _, n in ipairs(names) do
            local tag = (activeName and activeName:lower() == n:lower()) and " {55FF55}[active]" or ""
            say(n .. tag)
        end
    end)

    sampRegisterChatCommand("reloadmodels", function()
        rescan()
        say("rescanned custom_models: " .. #sortedNames() .. " skin(s)")
    end)

    sampRegisterChatCommand("autoskin", function()
        cfg.settings.autoApply = not cfg.settings.autoApply
        inicfg.save(cfg, INI_FILE)
        say("auto-load on join: " .. (cfg.settings.autoApply and "{55FF55}ON" or "{FF5555}OFF"))
    end)

    sampRegisterChatCommand("model", function(arg)
        arg = (arg or ""):match("^%s*(.-)%s*$")
        if arg == "" then
            say("usage: /model <name> | /model off | /models | /autoskin")
        elseif arg:lower() == "off" then
            lua_thread.create(removeSkin)
        else
            lua_thread.create(function() applySkinByName(arg, false) end)
        end
    end)

    -- Preload the saved skin NOW (before spawn) so nothing has to load at spawn time.
    if cfg.settings.autoApply and cfg.settings.savedSkin ~= "" and core then
        while not doesCharExist(PLAYER_PED) do wait(100) end
        local s = findSkin(cfg.settings.savedSkin)
        if s then
            local id, err = loadSkin(s)
            if id then
                active, activeName = id, s.name
                log("preloaded saved skin " .. s.name .. " (id " .. id .. ")")
            else
                say("saved skin could not be loaded: " .. tostring(err))
            end
        end
    end

    -- Keep the custom skin on. Checked every frame, so after a spawn / server skin
    -- change it is corrected within ~2 frames instead of up to a second later.
    local lastApply, mismatch = 0, 0
    while true do
        wait(0)
        if active and not busy and sampIsLocalPlayerSpawned()
           and doesCharExist(PLAYER_PED) and not isCharDead(PLAYER_PED) then
            local m = getCharModel(PLAYER_PED)
            if m ~= active then
                mismatch = mismatch + 1
                if mismatch >= 2 and os.clock() - lastApply > 0.25 then
                    if m < CUSTOM_MIN then origSkin = m end
                    lastApply = os.clock()
                    busy = true
                    pcall(wear, active)
                    busy = false
                end
            else
                mismatch = 0
            end
        end
    end
end
