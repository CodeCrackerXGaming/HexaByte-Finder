--// Services
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")

-- Wait for LocalPlayer to initialize
local LocalPlayer
repeat
    LocalPlayer = Players.LocalPlayer
    task.wait()
until LocalPlayer

--// User Configuration from loader
local webhook = getgenv().webhook or ""
local targetPets = getgenv().TargetPetNames or {}

--// Visited Job Tracking
local visitedJobIds = {[game.JobId] = true}
local hops = 0
local maxHopsBeforeReset = 50

--// Teleport Fail Handling
local teleportFails = 0
local maxTeleportRetries = 3

--// Found Pet Cache
local detectedPets = {}
local stopHopping = false

TeleportService.TeleportInitFailed:Connect(function(_, result)
    teleportFails += 1
    if result == Enum.TeleportResult.GameFull then
        warn("⚠️ Game full. Retrying teleport...")
    elseif result == Enum.TeleportResult.Unauthorized then
        warn("❌ Unauthorized/private server. Blacklisting and retrying...")
        visitedJobIds[game.JobId] = true
    else
        warn("❌ Other teleport error:", result)
    end

    if teleportFails >= maxTeleportRetries then
        warn("⚠️ Too many teleport fails. Forcing fresh server...")
        teleportFails = 0
        task.wait(1)
        TeleportService:Teleport(game.PlaceId)
    else
        task.wait(1)
        serverHop()
    end
end)

--// ESP Function
local function addESP(targetModel)
    if targetModel:FindFirstChild("PetESP") then return end
    local Billboard = Instance.new("BillboardGui")
    Billboard.Name = "PetESP"
    Billboard.Adornee = targetModel
    Billboard.Size = UDim2.new(0, 100, 0, 30)
    Billboard.StudsOffset = Vector3.new(0, 3, 0)
    Billboard.AlwaysOnTop = true
    Billboard.Parent = targetModel

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1, 0, 1, 0)
    Label.BackgroundTransparency = 1
    Label.Text = "🎯 Target Pet"
    Label.TextColor3 = Color3.fromRGB(255, 0, 0)
    Label.TextStrokeTransparency = 0.5
    Label.Font = Enum.Font.SourceSansBold
    Label.TextScaled = true
    Label.Parent = Billboard
end

--// Webhook Function (FIXED: 1 pet = 1 embed)
local function sendWebhook(petName, jobId)
    if webhook == "" then
        warn("⚠️ Webhook is empty, skipping notification.")
        return
    end

    local jsonData = HttpService:JSONEncode({
        ["content"] = "@here 🚨 SECRET BRAINROT DETECTED!",
        ["embeds"] = {{
            ["title"] = "🧠 Pet Found!",
            ["description"] = "A target pet was found!",
            ["fields"] = {
                { ["name"] = "User", ["value"] = LocalPlayer.Name },
                { ["name"] = "Pet", ["value"] = petName },
                { ["name"] = "Server JobId", ["value"] = jobId },
                { ["name"] = "Time", ["value"] = os.date("%Y-%m-%d %H:%M:%S") },
                { 
                    ["name"] = "Teleport Command",
                    ["value"] = "```game:GetService('TeleportService'):TeleportToPlaceInstance(109983668079237, '" .. jobId .. "')```"
                }
            },
            ["color"] = 0xFF00FF
        }}
    })

    local req = http_request or request or syn and syn.request
    if req then
        pcall(function()
            req({
                Url = webhook,
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = jsonData
            })
        end)
    end
end

--// Pet Detection Function
local function checkForPets()
    local found = {}
    for _, obj in pairs(workspace:GetDescendants()) do
        if obj:IsA("Model") then
            local nameLower = string.lower(obj.Name)
            for _, target in pairs(targetPets) do
                if string.find(nameLower, string.lower(target)) and not obj:FindFirstChild("PetESP") then
                    addESP(obj)
                    table.insert(found, obj.Name)
                    stopHopping = true
                    break
                end
            end
        end
    end
    return found
end

--// Server Hop Function
function serverHop()
    if stopHopping then return end
    task.wait(1.5)

    local cursor = nil
    local PlaceId, JobId = game.PlaceId, game.JobId
    local tries = 0

    hops += 1
    if hops >= maxHopsBeforeReset then
        visitedJobIds = {[JobId] = true}
        hops = 0
        print("♻️ Resetting visited JobIds.")
    end

    while tries < 3 do
        local url = "https://games.roblox.com/v1/games/" .. PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
        if cursor then url = url .. "&cursor=" .. cursor end

        local success, response = pcall(function()
            return HttpService:JSONDecode(game:HttpGet(url))
        end)

        if success and response and response.data then
            local servers = {}
            for _, server in ipairs(response.data) do
                if tonumber(server.playing or 0) < tonumber(server.maxPlayers or 1)
                    and server.id ~= JobId
                    and not visitedJobIds[server.id] then
                    table.insert(servers, server.id)
                end
            end

            if #servers > 0 then
                local picked = servers[math.random(1, #servers)]
                print("✅ Hopping to server:", picked)
                teleportFails = 0
                TeleportService:TeleportToPlaceInstance(PlaceId, picked)
                return
            end

            cursor = response.nextPageCursor
            if not cursor then
                tries += 1
                cursor = nil
                task.wait(0.5)
            end
        else
            warn("⚠️ Failed to fetch server list. Retrying...")
            tries += 1
            task.wait(0.5)
        end
    end

    warn("❌ No valid servers found. Forcing random teleport...")
    TeleportService:Teleport(PlaceId)
end

--// Live Detection (FIXED)
workspace.DescendantAdded:Connect(function(obj)
    task.wait(0.25)
    if obj:IsA("Model") then
        local nameLower = string.lower(obj.Name)
        for _, target in pairs(targetPets) do
            if string.find(nameLower, string.lower(target)) and not obj:FindFirstChild("PetESP") then
                if not detectedPets[obj.Name] then
                    detectedPets[obj.Name] = true
                    addESP(obj)
                    print("🎯 New pet appeared:", obj.Name)
                    stopHopping = false

                    sendWebhook(obj.Name, game.JobId)
                    task.wait(0.5) -- prevent rate limit
                end
                break
            end
        end
    end
end)

--// Start
task.wait(6)
local petsFound = checkForPets()

if #petsFound > 0 then
    print("🎯 Found pet(s):", table.concat(petsFound, ", "))

    for _, petName in ipairs(petsFound) do
        detectedPets[petName] = true
        sendWebhook(petName, game.JobId)
        task.wait(0.5) -- prevent rate limit
    end
else
    print("🔍 No target pets found. Hopping to next server...")
    task.delay(1.5, serverHop)
end