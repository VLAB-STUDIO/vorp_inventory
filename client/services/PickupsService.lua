local PickupsService = {}
local T <const>      = TranslationInv.Langs[Lang]
local WorldPickups   = {}
local PickUpPrompt   = 0
local group <const>  = GetRandomIntInRange(0, 0xffffff)

function PickupsService.loadModel(model)
	if not HasModelLoaded(model) then
		RequestModel(model, false)
		repeat Wait(0) until HasModelLoaded(model)
	end
end

function PickupsService.getUniqueId()
	local index = GetRandomIntInRange(0, 0xffffff)
	while WorldPickups[index] do
		index = GetRandomIntInRange(0, 0xffffff)
	end
	return index
end

local function createPrompt()
	PickUpPrompt = UiPromptRegisterBegin()
	UiPromptSetControlAction(PickUpPrompt, Config.PickupKey)
	UiPromptSetText(PickUpPrompt, VarString(10, "LITERAL_STRING", T.TakeFromFloor))
	UiPromptSetEnabled(PickUpPrompt, true)
	UiPromptSetVisible(PickUpPrompt, true)
	UiPromptSetHoldMode(PickUpPrompt, 1000)
	UiPromptSetGroup(PickUpPrompt, group, 0)
	UiPromptRegisterEnd(PickUpPrompt)
end


function PickupsService.CreateObject(objectHash, position, itemType)
    -- Controlla il tipo dell'oggetto
    local model
    if itemType == "money" then
        model = "p_moneybag02x"
    elseif itemType == "gold" then
        model = "s_pickup_goldbar01x"
    else
        -- Cerca la configurazione per il modello
        local itemConfig = Config.DropItemsProps[objectHash] or Config.DropItemsProps[itemType] or nil
        if itemConfig then
            model = itemConfig.model
        else
            model = "P_COTTONBOX01X" -- Modello predefinito
        end
    end

    -- Parametri di rotazione e offset di default
    local roll = 0.0
    local pitch = 0.0
    local yaw = 0.0
    local offsetX = 0.0
    local offsetY = 0.0
    local offsetZ = 0.0

    -- Se esiste una configurazione, usa i suoi parametri
    if Config.DropItemsProps[objectHash] then
        local itemConfig = Config.DropItemsProps[objectHash]
        roll = itemConfig.roll or roll
        pitch = itemConfig.pitch or pitch
        yaw = itemConfig.yaw or yaw
        offsetX = itemConfig.offsetX or offsetX
        offsetY = itemConfig.offsetY or offsetY
        offsetZ = itemConfig.offsetZ or offsetZ
    end

    -- Carica il modello
    PickupsService.loadModel(model)

    -- Applica l'offset alla posizione
    local adjustedPosition = vector3(position.x + offsetX, position.y + offsetY, position.z + offsetZ)

    -- Crea l'oggetto
    local entityHandle = CreateObject(joaat(model), adjustedPosition.x, adjustedPosition.y, adjustedPosition.z, false, false, false, false)
    repeat Wait(0) until DoesEntityExist(entityHandle)

    -- Posiziona l'oggetto a terra e applica la rotazione
    PlaceObjectOnGroundProperly(entityHandle, false)
    SetEntityRotation(entityHandle, pitch, roll, yaw, 2, true)
    FreezeEntityPosition(entityHandle, true)
    SetPickupLight(entityHandle, true)
    SetEntityCollision(entityHandle, false, true)
    SetModelAsNoLongerNeeded(model)

    return entityHandle
end

function PickupsService.createPickup(name, amount, metadata, weaponId, id, degradation)
    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed, true, true)
    local forward = GetEntityForwardVector(playerPed)
    local basePosition = vector3(coords.x + forward.x * 1.6, coords.y + forward.y * 1.6, coords.z + forward.z * 1.6)
    local index = PickupsService.getUniqueId()

    -- Calcolo dell'offset per evitare sovrapposizioni
    local function getAdjustedPosition(basePos)
        local radius = 0.5 -- Distanza minima tra gli oggetti
        local adjustedPos = basePos
        local attempts = 0

        for _, pickup in pairs(WorldPickups) do
            local dist = #(basePos - pickup.coords)
            if dist < radius then
                -- Se un oggetto è troppo vicino, sposta leggermente la posizione
                local randomX = math.random() * radius * 2 - radius -- Genera un valore casuale tra -radius e +radius
                local randomY = math.random() * radius * 2 - radius
                adjustedPos = vector3(basePos.x + randomX, basePos.y + randomY, basePos.z)
                attempts = attempts + 1
                if attempts > 10 then break end -- Evita loop infiniti
            end
        end

        return adjustedPos
    end

    local position = getAdjustedPosition(basePosition)

    local data = {
        name = name,
        obj = index,
        amount = amount,
        metadata = metadata,
        weaponId = weaponId,
        position = position,
        id = id,
        degradation = degradation
    }

    -- Giocatore esegue l'animazione di "buttare oggetto"
    local animDict = "amb_work@world_human_box_pickup@1@male_a@stand_exit_withprop"
    local animName = "exit_front"

    -- Carica l'animazione
    if not HasAnimDictLoaded(animDict) then
        RequestAnimDict(animDict)
        while not HasAnimDictLoaded(animDict) do
            Wait(10)
        end
    end

    -- Esegui l'animazione
    TaskPlayAnim(playerPed, animDict, animName, 1.0, -1.0, 1200, 0, 0, false, false, false)

    -- Attendi il completamento dell'animazione
    Wait(1200)

    -- Controllo degrado
    if degradation == 0 then
        PickupsService.schedulePickupDeletion(index, Config.DeletionDelaySeconds)
    end

    -- Trigger dell'evento server
    if weaponId == 1 then
        TriggerServerEvent("vorpinventory:sharePickupServerItem", data)
    else
        TriggerServerEvent("vorpinventory:sharePickupServerWeapon", data)
    end

    -- Effetti audio
    PlaySoundFrontend("show_info", "Study_Sounds", true, 0)
end

function PickupsService.schedulePickupDeletion(index, delay)
    CreateThread(function()
        local remainingTime = delay
        while remainingTime > 0 do
            Wait(1000) -- Aggiorna il timer ogni secondo
            remainingTime = remainingTime - 1

            -- Aggiorna il timer nel pickup
            if WorldPickups[index] then
                WorldPickups[index].timer = remainingTime
            end
        end

        -- Elimina l'oggetto una volta scaduto il timer
        local pickup = WorldPickups[index]
        if pickup then
            if pickup.entityId and DoesEntityExist(pickup.entityId) then
                DeleteEntity(pickup.entityId)
            end
            WorldPickups[index] = nil -- Rimuovi dalla tabella
            print("[PickupsService] Oggetto degradato eliminato: " .. tostring(index))
        end
    end)
end

RegisterNetEvent("vorpInventory:createPickup", PickupsService.createPickup)

function PickupsService.createMoneyPickup(amount)
	local playerPed <const> = PlayerPedId()
	local coords <const>    = GetEntityCoords(playerPed, true, true)
	local forward <const>   = GetEntityForwardVector(playerPed)
	local position <const>  = vector3(coords.x + forward.x * 1.6, coords.y + forward.y * 1.6, coords.z + forward.z * 1.6)
	local handle <const>    = PickupsService.getUniqueId()
	local data <const>      = { handle = handle, amount = amount, position = position }
	TriggerServerEvent("vorpinventory:shareMoneyPickupServer", data)
	Wait(1000)
	PlaySoundFrontend("show_info", "Study_Sounds", true, 0)
end

RegisterNetEvent("vorpInventory:createMoneyPickup", PickupsService.createMoneyPickup)

function PickupsService.createGoldPickup(amount)
	if not Config.UseGoldItem then return end

	local playerPed <const> = PlayerPedId()
	local coords <const>    = GetEntityCoords(playerPed, true, true)
	local forward <const>   = GetEntityForwardVector(playerPed)
	local position <const>  = vector3(coords.x + forward.x * 1.6, coords.y + forward.y * 1.6, coords.z + forward.z * 1.6)
	local handle <const>    = PickupsService.getUniqueId()
	local data <const>      = { handle = handle, amount = amount, position = position }
	TriggerServerEvent("vorpinventory:shareGoldPickupServer", data)
	Wait(1000)
	PlaySoundFrontend("show_info", "Study_Sounds", true, 0)
end

RegisterNetEvent("vorpInventory:createGoldPickup", PickupsService.createGoldPickup)

function PickupsService.sharePickupClient(data, value)
    if value == 1 then
        if WorldPickups[data.obj] then return end

        local label = Utils.GetLabel(data.name, data.weaponId, data.metadata)
        local pickup = {
            label    = label .. " x " .. tostring(data.amount),
            entityId = 0,
            coords   = data.position,
            uid      = data.uid,
            type     = data.type,
            name     = data.name,
        }

        -- Identifica il tipo di oggetto (money, gold, o altro)
        if data.name == "money" then
            pickup.type = "money"
        elseif data.name == "gold" then
            pickup.type = "gold"
        end

        WorldPickups[data.obj] = pickup

        -- Controllo degrado
        if data.degradation == 0 then
            PickupsService.schedulePickupDeletion(data.obj, Config.DeletionDelaySeconds)
        end
    else
        local pickup = WorldPickups[data.obj]
        if pickup then
            if pickup.entityId and DoesEntityExist(pickup.entityId) then
                DeleteEntity(pickup.entityId)
            end
            WorldPickups[data.obj] = nil
        end
    end
end

RegisterNetEvent("vorpInventory:sharePickupClient", PickupsService.sharePickupClient)

function PickupsService.shareMoneyPickupClient(handle, amount, position, uuid, value)
	if value == 1 then
		if WorldPickups[handle] == nil then
			local pickup <const> = {
				label = T.money .. tostring(amount) .. ")",
				entityId = 0,
				amount = amount,
				isMoney = true,
				isGold = false,
				coords = position,
				uuid = uuid,
				type = "item_standard",
				name = "money_bag"
			}
			WorldPickups[handle] = pickup
		end
	else
		local pickup <const> = WorldPickups[handle]
		if pickup then
			if pickup.entityId and DoesEntityExist(pickup.entityId) then
				DeleteEntity(pickup.entityId)
			end

			WorldPickups[handle] = nil
		end
	end
end

RegisterNetEvent("vorpInventory:shareMoneyPickupClient", PickupsService.shareMoneyPickupClient)

function PickupsService.shareGoldPickupClient(handle, amount, position, value)
	if value == 1 then
		if not WorldPickups[handle] then
			local pickup <const> = {
				label = T.gold .. " (" .. tostring(amount) .. ")",
				entityId = 0,
				amount = amount,
				isMoney = false,
				isGold = true,
				coords = position,
				type = "item_standard",
				name = "gold_bag"
			}

			WorldPickups[handle] = pickup
		end
	else
		local pickup <const> = WorldPickups[handle]
		if pickup then
			if pickup.entityId and DoesEntityExist(pickup.entityId) then
				DeleteEntity(pickup.entityId)
			end

			WorldPickups[handle] = nil
		end
	end
end

RegisterNetEvent("vorpInventory:shareGoldPickupClient", PickupsService.shareGoldPickupClient)


function PickupsService.playerAnim()
	local playerPed <const> = PlayerPedId()
	local animDict <const> = "amb_work@world_human_box_pickup@1@male_a@stand_exit_withprop"
	if not HasAnimDictLoaded(animDict) then
		RequestAnimDict(animDict)
		repeat Wait(0) until HasAnimDictLoaded(animDict)
	end

	TaskPlayAnim(playerPed, animDict, "exit_front", 1.0, 8.0, -1, 1, 0, false, false, false)
	Wait(1200)
	PlaySoundFrontend("CHECKPOINT_PERFECT", "HUD_MINI_GAME_SOUNDSET", true, 1)
	Wait(1000)
	ClearPedTasks(playerPed, true, true)
end

RegisterNetEvent("vorpInventory:playerAnim", PickupsService.playerAnim)


CreateThread(function()
    local function isAnyPlayerNear()
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed, true, true)
        local players = GetActivePlayers()
        local count = 0
        for _, player in ipairs(players) do
            local targetPed = GetPlayerPed(player)
            if player ~= PlayerId() then
                local targetCoords = GetEntityCoords(targetPed, true, true)
                local distance = #(playerCoords - targetCoords)
                if distance < 1.5 then
                    count = count + 1
                end
            end
        end
        return count
    end

    repeat Wait(2000) until LocalPlayer.state.IsInSession
    createPrompt()
    local pressed = false
    while true do
        local sleep = 1000
        if not InInventory then
            local playerPed = PlayerPedId()
            local isDead = IsEntityDead(playerPed)

            for key, pickup in pairs(WorldPickups) do
                if pickup and pickup.coords then -- Controlla validità del pickup
                    local dist = #(GetEntityCoords(playerPed) - pickup.coords)

                    -- Gestione della visibilità e creazione dell'oggetto
                    if dist < 80.0 then
                        if pickup.entityId == 0 or not DoesEntityExist(pickup.entityId) then
                            pickup.entityId = PickupsService.CreateObject(pickup.name, pickup.coords, pickup.type)
                        end
                    else
                        if DoesEntityExist(pickup.entityId) then
                            DeleteEntity(pickup.entityId)
                            pickup.entityId = 0
                        end
                    end

                    -- Gestione del prompt
                    UiPromptSetVisible(PickUpPrompt, not isDead)

                    if dist <= 1.0 then
                        sleep = 0
                        local label
                        if pickup.timer then -- Aggiungi il timer al prompt se presente
                            local timerText = string.format("%02d:%02d", math.floor(pickup.timer / 60), pickup.timer % 60)
                            label = VarString(10, "LITERAL_STRING", pickup.label .. " - ~e~" .. Config.Decayed .. "~q~ - " .. Config.Remainingtime .. ": " .. timerText)
                        else
                            label = VarString(10, "LITERAL_STRING", pickup.label)
                        end
                        UiPromptSetActiveGroupThisFrame(group, label, 0, 0, 0, 0)

                        if UiPromptHasHoldModeCompleted(PickUpPrompt) then
                            if pickup.entityId == WorldPickups[key].entityId then
                                if not pressed then
                                    pressed = true
                                    if isAnyPlayerNear() == 0 then
                                        if pickup.isMoney then
                                            local data = { obj = key, uuid = pickup.uuid }
                                            TriggerServerEvent("vorpinventory:onPickupMoney", data)
                                        elseif Config.UseGoldItem and pickup.isGold then
                                            local data = { obj = key, uuid = pickup.uuid }
                                            TriggerServerEvent("vorpinventory:onPickupGold", data)
                                        else
                                            local data = { uid = pickup.uid, obj = key }
                                            TriggerServerEvent("vorpinventory:onPickup", data)
                                        end
                                        TaskLookAtEntity(playerPed, pickup.entityId, 1000, 2048, 3, 0)
                                    end

                                    SetTimeout(4000, function()
                                        pressed = false
                                    end)
                                end
                            end
                        end
                    end
                else
                    print("[PickupsService] Pickup non valido per chiave: " .. tostring(key))
                end
            end
        end
        Wait(sleep)
    end
end)


-- for debug
AddEventHandler("onResourceStop", function(resourceName)
	if GetCurrentResourceName() ~= resourceName then return end
	if not Config.DevMode then return end
	--delete all entities
	for key, value in pairs(WorldPickups) do
		if DoesEntityExist(value.entityId) then
			DeleteEntity(value.entityId)
		end
	end
end)
