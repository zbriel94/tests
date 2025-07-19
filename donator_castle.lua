local caveExclusiva = {
	config = {
		actionItemIDS = {60166, 60167, 60168},
		actionIdTeleportExit = 6539,
		rentTime = {
			[60166] = 1 * 24 * 60 * 60,
			[60167] = 3 * 24 * 60 * 60,
			[60168] = 5 * 24 * 60 * 60,
		},
		fullStaminaRestore = {
			[60166] = false,
			[60167] = false,
			[60168] = true,
		},
		buyItemID = {20485},
		caveStats = true,
		buyMessage = "[DONATOR CASTLE] You bought the %s cave for %s.",
		timeLeftMessageInCave = "[DONATOR CASTLE] Your time in the cave %s it's over and you've been teleported to the temple.",
		timeLeftMessage = "[DONATOR CASTLE] Your time in the cave %s is over.",
		signs = {
			useSigns = true,
			signID = 2597,
			signLook = "This cave belongs to %s. Use command !cave stats to check rent time"
		},
		positionExitCaves = Position(236, 332, 6),
	},

	caves = {
	[7001] = {
        caveName = "Donator Castle I",
        signPos = Position(75, 293, 5),
        denyPos = Position(74, 294, 5),
        restrictedZones = {
            {from = Position(61, 267, 3), to = Position(92, 295, 3)},
            {from = Position(60, 266, 4), to = Position(91, 294, 4)},
            {from = Position(59, 265, 5), to = Position(90, 293, 5)},
            {from = Position(58, 264, 6), to = Position(89, 292, 6)},
            {from = Position(1, 1, 8), to = Position(623, 122, 8)},
        }
    },
    [7002] = {
        caveName = "Donator Castle II",
        signPos = Position(129, 293, 5),
        denyPos = Position(128, 294, 5),
        restrictedZones = {
            {from = Position(115, 267, 3), to = Position(146, 295, 3)},
            {from = Position(114, 266, 4), to = Position(145, 294, 4)},
            {from = Position(113, 265, 5), to = Position(144, 293, 5)},
            {from = Position(112, 264, 6), to = Position(143, 292, 6)},
            {from = Position(1, 123, 8), to = Position(623, 244, 8)},
		}
	}
},
	
	storages = {
		time = 9954399,
	}
}

_G.expCaveCache = _G.expCaveCache or {}

local function isGuest(caveActionId, guestGuid)
    local resultId = db.storeQuery("SELECT `guest` FROM `cave_guests` WHERE `cave` = " .. caveActionId .. " AND `guest` = " .. guestGuid)
    if resultId then
        Result.free(resultId)
        return true
    end
    return false
end

local function addGuest(caveActionId, guestGuid)
    if caveActionId and guestGuid then
        db.query("REPLACE INTO `cave_guests` (`cave`, `guest`) VALUES (" .. caveActionId .. ", " .. guestGuid .. ")")
    else
    end
end

local function removeGuest(caveActionId, guestGuid)
    db.query("DELETE FROM `cave_guests` WHERE `cave` = " .. caveActionId .. " AND `guest` = " .. guestGuid)
end

local function listGuests(caveActionId)
    local guests = {}
    local resultId = db.storeQuery("SELECT `guest` FROM `cave_guests` WHERE `cave` = " .. caveActionId)
    if resultId then
        repeat
            local guid = Result.getNumber(resultId, "guest")
            local name = getPlayerNameByGuid(guid)
            table.insert(guests, name)
        until not Result.next(resultId)
        Result.free(resultId)
    end
    return guests
end

local eventCaveExclusive = {}

db.query([[
	CREATE TABLE IF NOT EXISTS `cave_exclusive` (
		`cave` int unsigned NOT NULL DEFAULT '0',
		`owner` int NOT NULL DEFAULT '0',
		PRIMARY KEY `cave` (`cave`)
	) ENGINE=InnoDB DEFAULT CHARACTER SET=utf8;
]])

local function stopCaveExclusiveAction(playerGuid)
	stopEvent(eventCaveExclusive[playerGuid])
	eventCaveExclusive[playerGuid] = nil
end

local function getTimeString(self)
	local format = {
		{'day', self / 60 / 60 / 24},
		{'hour', self / 60 / 60 % 24},
		{'minute', self / 60 % 60},
		{'second', self % 60}
	}

	local out = {}
	for k, t in ipairs(format) do
		local v = math.floor(t[2])
		if(v > 0) then
			table.insert(out, (k < #format and (#out > 0 and ', ' or '') or ' and ') .. v .. ' ' .. t[1] .. (v ~= 1 and 's' or ''))
		end
	end
	local ret = table.concat(out)
	if ret:len() < 16 and ret:find('second') then
		local a, b = ret:find(' and ')
		ret = ret:sub(b + 1)
	end
	return ret
end

local function getPlayerNameByGuid(playerGuid)
	local resultId = db.storeQuery("SELECT `name` FROM `players` WHERE `id` = " .. playerGuid)
	if not resultId then
		return true
	end

	local playerName = Result.getString(resultId, "name")
	Result.free(resultId)

	return playerName
end

local function getCaveValueStorage(caveActionId)
	local caveId = caveExclusiva.caves[caveActionId]
	if not caveId then
		logger.error("[exclusive_caves] function getCaveValueStorage error in 'not caveId' (action id: {}).", caveActionId)
		return false
	end

	local resultId = db.storeQuery("SELECT `owner` FROM `cave_exclusive` WHERE `cave` = " .. caveActionId)
	if not resultId then
		logger.error("[exclusive_caves] function getCaveValueStorage error in 'not resultId' (action id: {}).", caveActionId)
		return false
	end

	local ownerGuid = Result.getNumber(resultId, "owner")
	Result.free(resultId)

	return ownerGuid
end

local function setCaveValueStorage(caveActionId, newOwnerGuid)
	local ownerGuid = getCaveValueStorage(caveActionId)
	if not ownerGuid then
		logger.error("[exclusive_caves] function setCaveValueStorage error in 'not ownerGuid' (action id: {}).", caveActionId)
		return false
	end

	db.query("UPDATE `cave_exclusive` SET `owner` = " .. newOwnerGuid .. " WHERE `cave` = " .. caveActionId .. "")

	return true
end

local function getAllCavesActionId()
	local caves = {}
	for key, value in pairs(caveExclusiva.caves) do
		table.insert(caves, key)
	end
	table.sort(caves, function(a, b) return b > a end)
	return caves
end

local function getOfflinePlayerStorage(playerGuid, storage)
	local player = Player(playerGuid)
	if player then
		return player:getStorageValue(storage)
	end

	local resultId = db.storeQuery("SELECT `value` FROM `player_storage` WHERE `player_id` = " .. playerGuid .. " AND `key` = " .. storage .. ";")
	if not resultId then
		return -1
	end

	local valueStorage = Result.getNumber(resultId, "value")
	Result.free(resultId)

	return valueStorage
end

local function resetSign(caveActionId)
	if not caveExclusiva.config.signs.useSigns then
		return true
	end

	local tile = Tile(caveExclusiva.caves[caveActionId].signPos)
	if not tile then
		logger.error("[exclusive_caves] function resetSign error in 'not tile' (action id: {}, sign pos: {}).", caveActionId, caveExclusiva.caves[caveActionId].signPos)
		return false
	end

	local sign = tile:getItemById(caveExclusiva.config.signs.signID)
	if not sign then
		logger.error("[exclusive_caves] function resetSign error in 'not sign' (action id: {}, sign id: {}).", caveActionId, caveExclusiva.config.signs.signID)
		return false
	end

	if not sign:setAttribute(ITEM_ATTRIBUTE_TEXT, "This cave is free!") then
		logger.error("[exclusive_caves] function resetSign error in 'not sign:setAttribute' (action id: {}).", caveActionId)
		return false
	end

	if not setCaveValueStorage(caveActionId, 0) then
		logger.error("[exclusive_caves] function resetSign error in 'not setCaveValueStorage' (action id: {}).", caveActionId)
		return false
	end

	return true
end

local function doRemoveCave(playerGuid, caveActionId)
	if not resetSign(caveActionId) then
		return false
	end

	local player = Player(playerGuid)
	if not player then
		return false
	end

	local caveId = caveExclusiva.caves[caveActionId]
	if not caveId then
		logger.error("[exclusive_caves] function doRemoveCave error in 'not caveId' (action id: {}).", caveActionId)
		return false
	end

	player:kv():scoped("exclusive-caves"):remove("cave-id")
	player:setStorageValue(caveExclusiva.storages.time, -1)

	local playerInCave = player:kv():scoped("exclusive-caves"):get("in-cave") or 0
	if playerInCave > 0 then
		player:kv():scoped("exclusive-caves"):remove("in-cave")
		player:teleportTo(Position(236, 332, 6))
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, caveExclusiva.config.timeLeftMessageInCave:format(caveId.caveName))
		player:unregisterEvent("exclusiveCaveDeath")

		if _G.expCaveCache[playerGuid] then
			_G.expCaveCache[playerGuid] = nil
		end

		player:kv():remove("bonus-caves-exp")
		player:kv():remove("bonus-caves-loot")
	else
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, caveExclusiva.config.timeLeftMessage:format(caveId.caveName))
	end

	return true
end

local function setSign(playerGuid, caveActionId, timeLeft)
	if not caveExclusiva.config.signs.useSigns then
		return true
	end

	local tile = Tile(caveExclusiva.caves[caveActionId].signPos)
	if not tile then
		logger.error("[exclusive_caves] function setSign error in 'not tile' (action id: {}, sign pos: {}).", caveActionId, caveExclusiva.caves[caveActionId].signPos)
		return false
	end

	local sign = tile:getItemById(caveExclusiva.config.signs.signID)
	if not sign then
		logger.error("[exclusive_caves] function setSign error in 'not sign' (action id: {}, sign id: {}).", caveActionId, caveExclusiva.config.signs.signID)
		return false
	end

	local playerName = getPlayerNameByGuid(playerGuid)
	if not playerName then
		logger.error("[exclusive_caves] function setSign error in 'not playerName' (action id: {}, player guid: {}).", caveActionId, playerGuid)
		return false
	end

	if not sign:setAttribute(ITEM_ATTRIBUTE_TEXT, caveExclusiva.config.signs.signLook:format(playerName, os.date("%X", os.time() + timeLeft))) then
		logger.error("[exclusive_caves] function setSign error in 'not sign:setAttribute' (action id: {}).", caveActionId)
		return false
	end

	stopCaveExclusiveAction(playerGuid)
	eventCaveExclusive[playerGuid] = addEvent(doRemoveCave, timeLeft * 1000, playerGuid, caveActionId)
    if timeLeft > 300 then
        addEvent(function()
            local player = Player(playerGuid)
            if player then
                player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "[CAVE EXCLUSIVA] Your exclusive cave will expire in 5 minutes.")
            end
        end, (timeLeft - 300) * 1000)
    end


	return true
end

local function setCaveTo(playerGuid, caveActionId, itemId)

	local player = Player(playerGuid)
	if not player then
		logger.error("[exclusive_caves] function setCaveTo error in 'not player' (action id: {}, player guid: {}).", caveActionId, playerGuid)
		return false
	end

	local caveId = caveExclusiva.caves[caveActionId]
	if not caveId then
		logger.error("[exclusive_caves] function setCaveTo error in 'not caveId' (action id: {}).", caveActionId)
		return false
	end

	if not table.contains(caveExclusiva.config.actionItemIDS, itemId) then
		logger.error("[exclusive_caves] function setCaveTo error in 'not table.contains' (action id: {}, item id: {}).", caveActionId, itemId)
		return false
	end

	player:kv():scoped("exclusive-caves"):set("cave-id", caveActionId)
	player:kv():scoped("exclusive-caves"):remove("in-cave")
	
    local streakKey = "streak-" .. caveActionId
    local streak = player:kv():scoped("exclusive-caves"):get(streakKey) or 0
    streak = streak + 1

    local bonusTime = caveExclusiva.config.rentTime[itemId]
    if streak >= 3 then
        bonusTime = math.floor(bonusTime * 1.5)
        streak = 0
        player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "[CAVE EXCLUSIVA] Bonus time granted for loyal rentals!")
    end
    player:kv():scoped("exclusive-caves"):set(streakKey, streak)
    player:setStorageValue(caveExclusiva.storages.time, os.time() + bonusTime)


	local fullStamina = caveExclusiva.config.fullStaminaRestore[itemId]
	if fullStamina then
		player:setStamina(2520)
	end

	
    db.query(string.format("INSERT INTO `cave_rent_log` (`player_id`, `cave_id`, `rented_at`) VALUES (%d, %d, %d);", playerGuid, caveActionId, os.time()))
player:sendTextMessage(MESSAGE_EVENT_ADVANCE, caveExclusiva.config.buyMessage:format(caveId.caveName, getTimeString(caveExclusiva.config.rentTime[itemId])))

	if not setSign(player:getGuid(), caveActionId, caveExclusiva.config.rentTime[itemId]) then
		return false
	end

	if not setCaveValueStorage(caveActionId, playerGuid) then
		logger.error("[exclusive_caves] function setCaveTo error in 'not setCaveValueStorage' (action id: {}).", caveActionId)
		return false
	end

	return true
end

local useDoor_action = Action()

function useDoor_action.onUse(player, item, denyPos, target, toPosition, isHotkey)

	local caveId = caveExclusiva.caves[item.actionid]
	if not caveId then
		logger.error("[exclusive_caves] function useDoor_action error in 'not caveId' (action id: {}).", item.actionid)
		return true
	end

	local ownerGuid = getCaveValueStorage(item.actionid)
	if not ownerGuid then
		logger.error("[exclusive_caves] function useDoor_action error in 'not ownerGuid' (action id: {}).", item.actionid)
		return true
	end

	local playerGuid = player:getGuid()
	if ownerGuid ~= playerGuid and not isGuest(item.actionid, playerGuid) then
		player:getPosition():sendMagicEffect(CONST_ME_POFF)
		return true
	end

	player:kv():scoped("exclusive-caves"):set("in-cave", 1)
	player:registerEvent("exclusiveCaveDeath")

	expCaveCache = expCaveCache or {} 

	if not expCaveCache then
		expCaveCache = {} 
	end

	_G.expCaveCache[playerGuid] = 130
	player:kv():set("bonus-caves-exp", 130)
	player:kv():set("bonus-caves-loot", 130)

	return true
end

for key, value in pairs(caveExclusiva.caves) do
	useDoor_action:aid(key)
end

useDoor_action:register()

local exclusiveCaveExitTeleport = MoveEvent()
exclusiveCaveExitTeleport:type("stepin")

function exclusiveCaveExitTeleport.onStepIn(creature, item, position, denyPos)
	local player = creature:getPlayer()
	if not player then
		return true
	end

	player:kv():scoped("exclusive-caves"):remove("in-cave")
	player:unregisterEvent("exclusiveCaveDeath")
	player:teleportTo(caveExclusiva.config.positionExitCaves)

	if not player:isInGhostMode() then
	end

	local playerGuid = player:getGuid()
	if _G.expCaveCache[playerGuid] then
		_G.expCaveCache[playerGuid] = nil
	end

	player:kv():remove("bonus-caves-exp")
	player:kv():remove("bonus-caves-loot")

	return true
end

exclusiveCaveExitTeleport:aid(caveExclusiva.config.actionIdTeleportExit)
exclusiveCaveExitTeleport:register()

local exclusiveCave_login = CreatureEvent("exclusiveCaveLogin")

function exclusiveCave_login.onLogin(player)

	local caveActionId = player:kv():scoped("exclusive-caves"):get("cave-id") or 0
	if caveActionId > 0 then
		local ownerGuid = getCaveValueStorage(caveActionId)
		if not ownerGuid then
			logger.error("[exclusive_caves] function exclusiveCave_login error in 'not ownerGuid' (action id: {}).", caveActionId)
			return true
		end

		local timeLeft = player:getStorageValue(caveExclusiva.storages.time) - os.time()
		local playerGuid = player:getGuid()

		if ownerGuid ~= playerGuid or timeLeft <= 0 then
			player:kv():scoped("exclusive-caves"):remove("cave-id")
			player:setStorageValue(caveExclusiva.storages.time, -1)

			local playerInCave = player:kv():scoped("exclusive-caves"):get("in-cave") or 0
			if playerInCave > 0 then
				player:kv():scoped("exclusive-caves"):remove("in-cave")
				player:teleportTo(player:getTown():getTemplePosition())

				if _G.expCaveCache[playerGuid] then
					_G.expCaveCache[playerGuid] = nil
				end

				player:kv():remove("bonus-caves-exp")
				player:kv():remove("bonus-caves-loot")

				player:sendTextMessage(MESSAGE_EVENT_ADVANCE, caveExclusiva.config.timeLeftMessageInCave:format(caveExclusiva.caves[caveActionId].caveName))
			end
		end

		local playerInCave2 = player:kv():scoped("exclusive-caves"):get("in-cave") or 0
		if playerInCave2 > 0 then
			player:registerEvent("exclusiveCaveDeath")
		end
	end

	return true
end

exclusiveCave_login:register()

local exclusiveCave_death = CreatureEvent("exclusiveCaveDeath")

function exclusiveCave_death.onDeath(player, corpse, killer, mostDamageKiller, lastHitUnjustified, mostDamageUnjustified)

	local playerInCave = player:kv():scoped("exclusive-caves"):get("in-cave") or 0
	if playerInCave > 0 then
		player:kv():scoped("exclusive-caves"):remove("in-cave")
		player:unregisterEvent("exclusiveCaveDeath")
	end

	return true
end

exclusiveCave_death:register()

local exclusiveCave_startup = GlobalEvent("exclusiveCaveStartup")

function exclusiveCave_startup.onStartup()

	for _, caveActionId in pairs(getAllCavesActionId()) do
		local caveId = caveExclusiva.caves[caveActionId]
		if not caveId then
			logger.error("[exclusive_caves] function exclusiveCave_startup error in 'not caveId' (action id: {}).", caveActionId)
			return true
		end

		local ownerGuid = getCaveValueStorage(caveActionId)
		if ownerGuid then
			if ownerGuid > 0 then
				local playerName = getPlayerNameByGuid(ownerGuid)
				if not playerName then
					logger.error("[exclusive_caves] function exclusiveCave_startup error in 'not playerName' (action id: {}, owner guid: {}).", caveActionId, ownerGuid)
					return true
				end

				local timeLeft = getOfflinePlayerStorage(ownerGuid, caveExclusiva.storages.time) - os.time()
				if timeLeft > 0 then
					if not setSign(ownerGuid, caveActionId, timeLeft) then
						logger.error("[exclusive_caves] function exclusiveCave_startup error in 'not setSign' (action id: {}, owner guid: {}).", caveActionId, ownerGuid)
						return true
					end
				else
					if not resetSign(caveActionId) then
						logger.error("[exclusive_caves] function exclusiveCave_startup error in 'not resetSign 1' (action id: {}).", caveActionId)
						return true
					end
				end
			else
				if not resetSign(caveActionId) then
					logger.error("[exclusive_caves] function exclusiveCave_startup error in 'not resetSign 2' (action id: {}).", caveActionId)
					return true
				end
			end
		else
			if not resetSign(caveActionId) then
				logger.error("[exclusive_caves] function exclusiveCave_startup error in 'not resetSign 3' (action id: {}).", caveActionId)
				return true
			end
		end
	end

	return true
end

exclusiveCave_startup:register()

local useKey_action = Action()

function useKey_action.onUse(player, item, denyPos, target, toPosition, isHotkey)

	if table.contains(caveExclusiva.config.buyItemID, target.itemid) then

		local targetActionId = target.actionid
		local ownerGuid = getCaveValueStorage(targetActionId)
		if not ownerGuid then
			logger.error("[exclusive_caves] function useKey_action error in 'not ownerGuid' (action id: {}).", target.actionid)
			return true
		end

		local caveStorage = player:kv():scoped("exclusive-caves"):get("cave-id") or 0
		if caveStorage > 0 then
			local caveName = caveExclusiva.caves[caveStorage].caveName
			if not caveName then
				logger.error("[exclusive_caves] function useKey_action error in 'not caveName' (action id: {}).", caveStorage)
				return true
			end
			local timeLeft = player:getStorageValue(caveExclusiva.storages.time) - os.time()
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "[CAVE EXCLUSIVA] You already own the exclusive ".. caveName ..", wait ".. getTimeString(timeLeft) .." to rent the cave again.")
			player:getPosition():sendMagicEffect(CONST_ME_POFF)
			return true

		elseif ownerGuid > 0 then

			local playerName = getPlayerNameByGuid(ownerGuid)
			if not playerName then
				logger.error("[exclusive_caves] function useKey_action error in 'not playerName' (action id: {}, owner guid: {}).", targetActionId, ownerGuid)
				return true
			end

			local ownerTimeLeft = getOfflinePlayerStorage(ownerGuid, caveExclusiva.storages.time) - os.time()
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "[CAVE EXCLUSIVA] This exclusive cave already belongs to the player ".. playerName ..", remain ".. getTimeString(ownerTimeLeft) .." for the cave to be free again.")
			player:getPosition():sendMagicEffect(CONST_ME_POFF)
			return true

		else
			if not setCaveTo(player:getGuid(), targetActionId, item.itemid) then
				logger.error("[exclusive_caves] function useKey_action error in 'not setCaveTo' (action id: {}, item id: {}).", targetActionId, item.itemid)
				return true
			end

			if not item:remove(1) then
				logger.error("[exclusive_caves] function useKey_action error in 'not item:remove' (action id: {}, item id: {}).", targetActionId, item.itemid)
				return true
			end

			player:getPosition():sendMagicEffect(CONST_ME_FIREWORK_BLUE)
		end
	end

	return true
end

for i = 1, #caveExclusiva.config.actionItemIDS do
	useKey_action:id(caveExclusiva.config.actionItemIDS[i])
end

useKey_action:register()

local caveExclusive_talkaction = TalkAction("!cave")

function caveExclusive_talkaction.onSay(player, words, param, type)

	local exaust = player:getExhaustion("talkactions")
	if exaust > 0 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "[CAVE EXCLUSIVA] You have to wait " .. exaust .. " " .. (exaust > 1 and "seconds" or "second") .. " to use the command again.")
		player:getPosition():sendMagicEffect(CONST_ME_POFF)
		return true
	end

	player:setExhaustion("talkactions", 1)

	if string.lower(param) == "time" then
		local caveActionIdKV = player:kv():scoped("exclusive-caves"):get("cave-id") or 0
		if caveActionIdKV > 0 then
			local timeLeft = player:getStorageValue(caveExclusiva.storages.time) - os.time()
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "[CAVE EXCLUSIVA] You own " .. getTimeString(timeLeft) .. " remaining.")
		else
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "[CAVE EXCLUSIVA] You don't own any exclusive cave.")
		end

	elseif string.lower(param) == "leave" then

		if not Tile(player:getPosition()):hasFlag(TILESTATE_PROTECTIONZONE) then
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "[CAVE EXCLUSIVA] You must be in the protection zone to use these commands.")
			player:getPosition():sendMagicEffect(CONST_ME_POFF)
			return true
		end

		local caveActionIdKV = player:kv():scoped("exclusive-caves"):get("cave-id") or 0
		if caveActionIdKV < 1 then
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "[CAVE EXCLUSIVA] You don't own any exclusive cave.")
			player:getPosition():sendMagicEffect(CONST_ME_POFF)
			return true
		end

		local caveName = caveExclusiva.caves[caveActionIdKV].caveName
		if not caveName then
			logger.error("[exclusive_caves] function caveExclusive_talkaction error in 'not caveName' (action id: {}).", caveActionIdKV)
			return true
		end

		local timeLeft = player:getStorageValue(caveExclusiva.storages.time) - os.time()
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "[CAVE EXCLUSIVA] You left your exclusive ".. caveName .." where you still had ".. getTimeString(timeLeft) .." left time.")

		doRemoveCave(player:getGuid(), caveActionIdKV)

	

    
   elseif string.sub(param, 1, 6) == "invite" then
    local name = param:match("invite%s+(.+)")
    if not name then 
        player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Usage: !cave invite <name>")
        return true
    end

    local caveActionIdKV = player:kv():scoped("exclusive-caves"):get("cave-id") or 0
    if caveActionIdKV == 0 then
        player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "[CAVE EXCLUSIVA] You don't own any cave to invite players to.")
        return true
    end

    local guestPlayer = Player(name)
    local guestGuid

    if guestPlayer then
        guestGuid = guestPlayer:getGuid()
    else
        local resultId = db.storeQuery("SELECT `id` FROM `players` WHERE `name` = " .. db.escapeString(name))
        if resultId then
            guestGuid = Result.getNumber(resultId, "id")
            Result.free(resultId)
        end
    end

    if guestGuid then
        addGuest(caveActionIdKV, guestGuid)
        player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Invited " .. name .. " to your cave.")
    else
        player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Player not found.")
    end
	

    elseif string.sub(param, 1, 8) == "temporary" then
        local name, duration = param:match("temporary%s+([^%s]+)%s+(%d+)")
        if not name or not duration then
            return player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Usage: !cave temporary <name> <minutes>")
        end

        local caveActionIdKV = player:kv():scoped("exclusive-caves"):get("cave-id") or 0
        if caveActionIdKV == 0 then
            return player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "[CAVE EXCLUSIVA] You don't own any cave to invite players to.")
        end

        local guestPlayer = Player(name)
        local guestGuid

        if guestPlayer then
            guestGuid = guestPlayer:getGuid()
        else
            local resultId = db.storeQuery("SELECT `id` FROM `players` WHERE `name` = " .. db.escapeString(name))
            if resultId then
                guestGuid = Result.getNumber(resultId, "id")
                Result.free(resultId)
            end
        end

        if guestGuid then
            addGuest(caveActionIdKV, guestGuid)
            player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Temporarily invited " .. name .. " for " .. duration .. " seconds.")
            addEvent(function()
                removeGuest(caveActionIdKV, guestGuid)
                local guest = Player(guestGuid)
                if guest then
                    guest:sendTextMessage(MESSAGE_EVENT_ADVANCE, "[CAVE EXCLUSIVA] Your temporary access to the cave has expired.")
                    local denyPos = caveExclusiva.caves[caveActionIdKV].denyPos or guest:getTown():getTemplePosition()
                    guest:teleportTo(denyPos)
                    denyPos:sendMagicEffect(CONST_ME_POFF)
                end
            end, tonumber(duration) * 1000)
        else
            player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Player not found.")
        end


    elseif string.sub(param, 1, 4) == "kick" then
    local name = param:match("kick%s+(.+)")
    if not name then
        return player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Usage: !cave kick <name>")
    end

    local caveActionIdKV = player:kv():scoped("exclusive-caves"):get("cave-id") or 0
    if caveActionIdKV == 0 then
        player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "[CAVE EXCLUSIVA] You don't own any cave to kick players from.")
        return true
    end

    local kickedPlayer = Player(name)
    if kickedPlayer then
        removeGuest(caveActionIdKV, kickedPlayer:getGuid())
        player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Removed " .. kickedPlayer:getName() .. " from your cave.")

        local kickedPos = kickedPlayer:getPosition()
        local cave = caveExclusiva.caves[caveActionIdKV]
        if cave and cave.restrictedZones then
            for _, zone in ipairs(cave.restrictedZones) do
                local from, to = zone.from, zone.to
                if kickedPos.z == from.z and
                   kickedPos.x >= from.x and kickedPos.x <= to.x and
                   kickedPos.y >= from.y and kickedPos.y <= to.y then
                    local denyPos = cave.denyPos or kickedPlayer:getTown():getTemplePosition()
                    kickedPlayer:teleportTo(denyPos)
                    denyPos:sendMagicEffect(CONST_ME_POFF)
                    kickedPlayer:sendTextMessage(MESSAGE_EVENT_ADVANCE, "[CAVE EXCLUSIVA] You have been removed from the cave.")
                    break
                end
            end
        end
    else
        player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Player not found online.")
    end

    elseif param == "guests" then
        local guestList = listGuests(caveActionIdKV)
        if #guestList == 0 then
            player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Your cave has no invited guests.")
        else
            player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Invited guests: " .. table.concat(guestList, ", "))
        end


    elseif string.lower(param) == "stats" then
		if not caveExclusiva.config.caveStats then
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "[CAVE EXCLUSIVA] The stats are disabled.")
			return true
		end

		local info = "-----> Cave Exclusiva Stats <-----"
		for _, caveActionId in pairs(getAllCavesActionId()) do
			local caveId = caveExclusiva.caves[caveActionId]
			if not caveId then
				logger.error("[exclusive_caves] function caveExclusive_talkaction error in 'not caveId' (action id: {}).", caveActionId)
				return true
			end

			local ownerGuid = getCaveValueStorage(caveActionId)
			if not ownerGuid then
				logger.error("[exclusive_caves] function caveExclusive_talkaction error in 'not ownerGuid' (action id: {}).", caveActionId)
				return true
			end

			local hasOwner = ownerGuid > 0 and true or false
			local ownerName = hasOwner and getPlayerNameByGuid(ownerGuid) or "-> Cave Free <-"
			local timeLeft = hasOwner and getTimeString(getOfflinePlayerStorage(ownerGuid, caveExclusiva.storages.time) - os.time()) or "0 seconds"

			info = info .. "\n-----------------------------\n"
			info = info .. "* Cave: ".. caveId.caveName .. "\n"
			info = info .. "* Player: ".. ownerName .. "\n"
			info = info .. "* Time left: ".. timeLeft
		end

		player:showTextDialog(8977, info)


elseif string.lower(param) == "renew on" then
    player:kv():scoped("exclusive-caves"):set("renew", 1)
    player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "[CAVE EXCLUSIVA] Auto-renewal enabled.")
elseif string.lower(param) == "renew off" then
    player:kv():scoped("exclusive-caves"):set("renew", 0)
    player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "[CAVE EXCLUSIVA] Auto-renewal disabled.")

else
    local msg = "[CAVE EXCLUSIVA] Comandos disponibles:\n"
    msg = msg .. "!cave time - See how much time you have left\n"
    msg = msg .. "!cave leave - Freeing your cave early\n"
    msg = msg .. "!cave stats - See who has rented caves\n"
    msg = msg .. "!cave invite <name> - Invite player to your cave\n"
    msg = msg .. "!cave kick <name> - Remove guest player\n"
    msg = msg .. "!cave guests - See guest list"
    msg = msg .. "\n!cave renew on/off - Turn automatic renewal on or off"
    msg = msg .. "\n!cave temporary <name> <minutes> - Temporary invitation to your cave"
    player:sendTextMessage(MESSAGE_EVENT_ADVANCE, msg)
end

	return true
end

caveExclusive_talkaction:separator(" ")
caveExclusive_talkaction:groupType("normal")
caveExclusive_talkaction:register()


local exclusiveCaveDoorStepIn = MoveEvent()
exclusiveCaveDoorStepIn:type("stepin")

function exclusiveCaveDoorStepIn.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if not player then return true end

	local caveId = caveExclusiva.caves[item.actionid]
	if not caveId then return true end

	local denyPos = caveId.denyPos or fromPosition

	local ownerGuid = getCaveValueStorage(item.actionid)
	if not ownerGuid then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "[CAVE EXCLUSIVA] This cave has no owner.")
		player:teleportTo(denyPos)
		denyPos:sendMagicEffect(CONST_ME_POFF)
		return false
	end

	local playerGuid = player:getGuid()
	if ownerGuid ~= playerGuid and not isGuest(item.actionid, playerGuid) then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "[CAVE EXCLUSIVA] You do not have access to this cave.")
		player:teleportTo(denyPos)
		denyPos:sendMagicEffect(CONST_ME_POFF)
		return false
	end

	player:kv():scoped("exclusive-caves"):set("in-cave", 1)
	player:registerEvent("exclusiveCaveDeath")
	return true
end

for key, _ in pairs(caveExclusiva.caves) do
	exclusiveCaveDoorStepIn:aid(key)
end

exclusiveCaveDoorStepIn:register()

local exclusiveZoneChecker = MoveEvent()
exclusiveZoneChecker:type("stepin")

function exclusiveZoneChecker.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if not player then return true end

	local playerPos = player:getPosition()
	local playerGuid = player:getGuid()

	for actionId, cave in pairs(caveExclusiva.caves) do
		if cave.restrictedZones then
			for _, zone in ipairs(cave.restrictedZones) do
				local from, to = zone.from, zone.to
				if playerPos.z == from.z and
				   playerPos.x >= from.x and playerPos.x <= to.x and
				   playerPos.y >= from.y and playerPos.y <= to.y then

					local ownerGuid = getCaveValueStorage(actionId)
					if ownerGuid ~= playerGuid and not isGuest(actionId, playerGuid) then
						local denyPos = cave.denyPos or fromPosition
						player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "[CAVE EXCLUSIVA] You are not allowed in this area.")
						player:teleportTo(denyPos)
						denyPos:sendMagicEffect(CONST_ME_POFF)
						return false
					end
				end
			end
		end
	end

	return true
end

for _, cave in pairs(caveExclusiva.caves) do
	if cave.restrictedZones then
		for _, zone in ipairs(cave.restrictedZones) do
			local fromPos, toPos = zone.from, zone.to
			for x = fromPos.x, toPos.x do
				for y = fromPos.y, toPos.y do
					exclusiveZoneChecker:position(Position(x, y, fromPos.z))
				end
			end
		end
	end
end

exclusiveZoneChecker:register()

local huntZones = {
    [9101] = {
        zone = {from = Position(4, 3, 8), to = Position(140, 123, 8)},
        exhibitPos = Position(62, 284, 5),
		creatures = {"Dragon", "Cyclops", "Giant Spider", "Vampire", "Bonebeast", "Wyrm", "Behemoth"},
        label = "Donator Castle I - Teleport I",
        modalId = 9101
    },
    [9102] = {
        zone = {from = Position(140, 3, 8), to = Position(253, 123, 8)},
        exhibitPos = Position(63, 284, 5),
		creatures = {"Dragon Lord", "Nightmare", "Guzzlemaw", "Werewolf", "Hydra", "Plaguesmith", "Defiler"},
        label = "Donator Castle I - Teleport II",
        modalId = 9102
    },
    [9103] = {
        zone = {from = Position(253, 3, 8), to = Position(384, 123, 8)},
        exhibitPos = Position(64, 284, 5),
		creatures = {"Demon", "Mutated Tiger", "Hellspawn", "War Golem", "Blightwalker", "Vampire Bride", "Frost Dragon", "Ice Golem", "Crystal Spider"},
        label = "Donator Castle I - Teleport III",
        modalId = 9103
    },
    [9104] = {
        zone = {from = Position(384, 3, 8), to = Position(501, 123, 8)},
        exhibitPos = Position(65, 284, 5),
		creatures = {"Cobra Vizier", "Cursed Prospector", "Vexclaw", "Grimeleech", "Burster Spectre", "Draken Warmaster"},
        label = "Donator Castle I - Teleport IV",
        modalId = 9104
    },
    [9105] = {
        zone = {from = Position(501, 3, 8), to = Position(625, 123, 8)},
        exhibitPos = Position(66, 284, 5),
		creatures = {"Deepworm", "Silencer", "Dark Torturer", "Shulgrax", "Soul-Broken Harbinger", "Werehyaena Shaman", "Cobra Assassin"},
        label = "Donator Castle I - Teleport V",
        modalId = 9105
    },
    [9106] = {
        zone = {from = Position(4, 123, 8), to = Position(140, 243, 8)},
        exhibitPos = Position(116, 284, 5),
		creatures = {"Dragon", "Cyclops", "Giant Spider", "Vampire", "Bonebeast", "Wyrm", "Behemoth"},
        label = "Donator Castle II - Teleport I",
        modalId = 9106
    },
    [9107] = {
        zone = {from = Position(140, 123, 8), to = Position(253, 243, 8)},
        exhibitPos = Position(117, 284, 5),
		creatures = {"Dragon Lord", "Nightmare", "Guzzlemaw", "Werewolf", "Hydra", "Plaguesmith", "Defiler"},
        label = "Donator Castle II - Teleport II",
        modalId = 9107
    },
    [9108] = {
        zone = {from = Position(253, 123, 8), to = Position(384, 243, 8)},
        exhibitPos = Position(118, 284, 5),
		creatures = {"Demon", "Mutated Tiger", "Hellspawn", "War Golem", "Blightwalker", "Vampire Bride", "Frost Dragon", "Ice Golem", "Crystal Spider"},
        label = "Donator Castle II - Teleport III",
        modalId = 9108
    },
    [9109] = {
        zone = {from = Position(384, 123, 8), to = Position(501, 243, 8)},
        exhibitPos = Position(119, 284, 5),
		creatures = {"Cobra Vizier", "Cursed Prospector", "Vexclaw", "Grimeleech", "Burster Spectre", "Draken Warmaster"},
        label = "Donator Castle II - Teleport IV",
        modalId = 9109
    },
    [9110] = {
        zone = {from = Position(501, 123, 8), to = Position(625, 243, 8)},
        exhibitPos = Position(120, 284, 5),
		creatures = {"Silencer", "Dark Torturer", "Shulgrax", "Soul-Broken Harbinger", "Werehyaena Shaman", "Cobra Assassin"},
        label = "Donator Castle II - Teleport V",
        modalId = 9110
    }
}

local activeSelections = {}
local activeSummonNames = {}

local function clearZone(zone)
    for z = zone.from.z, zone.to.z do
        for x = zone.from.x, zone.to.x do
            for y = zone.from.y, zone.to.y do
                local tile = Tile(Position(x, y, z))
                if tile then
                    for _, thing in ipairs(tile:getCreatures() or {}) do
                        if thing:isMonster() then
                            thing:remove()
                        end
                    end
                end
            end
        end
    end
end

local function countMonstersInArea(area)
    local count = 0
    for x = area.from.x, area.to.x do
        for y = area.from.y, area.to.y do
            local tile = Tile(Position(x, y, area.from.z))
            if tile then
                for _, thing in ipairs(tile:getCreatures() or {}) do
                    if thing:isMonster() then
                        count = count + 1
                    end
                end
            end
        end
    end
    return count
end

local function getFreePosition(area)
    local positions = {}
    for x = area.from.x, area.to.x do
        for y = area.from.y, area.to.y do
            local pos = Position(x, y, area.from.z)
            local tile = Tile(pos)
            if tile and not tile:getTopCreature() then
                table.insert(positions, pos)
            end
        end
    end
    if #positions > 0 then
        return positions[math.random(#positions)]
    end
    return nil
end

local function createRespawnableMonster(name, uid)
    local config = huntZones[uid]
    if not config or activeSummonNames[uid] ~= name then return end
    local pos = getFreePosition(config.zone)
    if not pos then return end
    local monster = Game.createMonster(name, pos)
    if monster then
        monster:registerEvent("RespawnOnDeath")
        monster:setStorageValue(9000, uid)
        monster:setStorageValue(9001, name)
    end
end

local function batchCreate(name, uid, total, delay, step)
    activeSummonNames[uid] = name
    local created = 0
    local function createWave()
        for i = 1, step do
            if created >= total then return end
            createRespawnableMonster(name, uid)
            created = created + 1
        end
        if created < total then
            addEvent(createWave, delay)
        end
    end
    createWave()
end

local huntStepIn = MoveEvent()
huntStepIn:type("stepin")

function huntStepIn.onStepIn(creature, item, position, fromPosition)
    local player = creature:getPlayer()
    if not player then return true end
    local config = huntZones[item.uid]
    if not config then return true end

    player:registerEvent("HuntModalEvent")

    local window = ModalWindow(config.modalId, config.label, "Select a creature to populate this zone.")
    local choiceMap = {}
    for i, name in ipairs(config.creatures) do
        local choiceId = 100 + i
        window:addChoice(choiceId, name)
        choiceMap[choiceId] = name
    end
    window:addButton(1, "Summon")
    window:addButton(2, "Cancel")
    window:setDefaultEnterButton(1)
    window:setDefaultEscapeButton(2)
    window:sendToPlayer(player)

    activeSelections[player:getId()] = {
        uid = item.uid,
        zone = config.zone,
        modalId = config.modalId,
        choiceMap = choiceMap
    }

    return true
end

for uid, _ in pairs(huntZones) do
    huntStepIn:uid(uid)
end
huntStepIn:register()

local modalHandler = CreatureEvent("HuntModalEvent")

function modalHandler.onModalWindow(player, modalId, buttonId, choiceId)
    local cid = player:getId()
    local selection = activeSelections[cid]
    if not selection then return false end

    local config = huntZones[selection.uid]
    if not config then return true end

    if buttonId ~= 1 then
        activeSelections[cid] = nil
        return true
    end

    local monsterName = selection.choiceMap[choiceId]
    if not monsterName then return true end

    clearZone(config.zone)
    batchCreate(monsterName, selection.uid, 250, 1000, 2)

    local exhibit = config.exhibitPos
    if exhibit then
        clearZone({from = exhibit, to = exhibit})
        Game.createMonster(monsterName, exhibit)
    end

    activeSelections[cid] = nil
    return true
end

modalHandler:register()

local deathHandler = CreatureEvent("RespawnOnDeath")
deathHandler:type("death")

function deathHandler.onDeath(monster)
    local uid = monster:getStorageValue(9000)
    local name = monster:getStorageValue(9001)
    if activeSummonNames[uid] ~= name then return true end
    local config = huntZones[uid]
    if not config then return true end
    addEvent(function()
        if countMonstersInArea(config.zone) < 250 then
            createRespawnableMonster(name, uid)
        end
    end, 200)
    return true
end

deathHandler:register()


local config = {
	{ name="Donator Castle I", position = Position(74, 304, 6) },
	{ name="Donator Castle II", position = Position(128, 304, 6) },
}

local teleportCube = Action()
function teleportCube.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local window = ModalWindow {
		title = "Donator Donator Castle",
		message = "Select A Donator Castle"
	}
	for i, info in pairs(config) do
		window:addChoice(string.format("%s", info.name), function (player, button, choice)
			if button.name ~= "Select" then
				return true
			end
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You were teleported to " .. info.name)
			player:teleportTo(info.position)
			return true
		end)
	end
	window:addButton("Select")
	window:addButton("Close")
	window:setDefaultEnterButton(0)
	window:setDefaultEscapeButton(1)
	window:sendToPlayer(player)
	return true
end
teleportCube:aid(31633)
teleportCube:register()
