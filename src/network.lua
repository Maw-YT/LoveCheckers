-- Minimal ENet-based client for the LoveCheckers multiplayer server.
-- Messages are simple pipe-separated strings to avoid JSON dependencies.

local Network = {
    peer = nil,
    host = nil,
    connected = false,
    playerId = nil,
    playerSide = nil, -- 1=Red,2=White
    gameId = nil,
    onState = nil,
    onAssigned = nil,
    onDisconnected = nil,
}

local function split(str, sep)
    local out = {}
    for token in string.gmatch(str, "[^" .. sep .. "]+") do
        out[#out+1] = token
    end
    return out
end

local function parseBoard(str)
    local board = {}
    local values = split(str, ",")
    local idx = 1
    for r = 1, 8 do
        board[r] = {}
        for c = 1, 8 do
            local v = tonumber(values[idx] or "0") or 0
            if v == 0 then
                board[r][c] = nil
            else
                local player = (v >= 20) and 2 or 1
                local king = (v % 10) == 1
                board[r][c] = {player = player, king = king, visualX = 0, visualY = 0}
            end
            idx = idx + 1
        end
    end
    return board
end

local function serializeMove(fromR, fromC, toR, toC)
    return string.format("%d,%d,%d,%d", fromR, fromC, toR, toC)
end

function Network:init(host, port)
    local enet

    -- Prefer Love2D's built-in enet module (if available). Otherwise fall back to lua-enet.
    if love and love.enet then
        enet = love.enet
    else
        local ok
        ok, enet = pcall(require, "enet")
        if not ok then
            return false, "enet not available"
        end
    end

    self.host = enet.host_create()
    self.peer = self.host:connect(string.format("%s:%d", host, port))
    self.connected = true
    return true
end

function Network:onAssigned(fn)
    self.onAssigned = fn
end

function Network:onState(fn)
    self.onState = fn
end

function Network:onDisconnected(fn)
    self.onDisconnected = fn
end

function Network:update()
    if not self.connected or not self.host then
        return
    end

    local event = self.host:service(0)
    while event do
        if event.type == "connect" then
            -- waiting for server assignment
        elseif event.type == "receive" then
            local msg = event.data
            local parts = split(msg, "|")
            local typ = parts[1]
            if typ == "assigned" then
                self.playerId = parts[2]
                self.playerSide = tonumber(parts[3])
                self.gameId = parts[4]
                if self.onAssigned then self.onAssigned(self.playerSide, self.gameId) end
            elseif typ == "state" then
                -- Format: state|gameId|turn|gameOver|winner|board
                local gameId = parts[2]
                local turn = tonumber(parts[3])
                local gameOver = tonumber(parts[4]) == 1
                local winner = tonumber(parts[5]) or 0
                local board = parseBoard(parts[6])
                if self.onState then
                    self.onState({gameId = gameId, turn = turn, gameOver = gameOver, winner = winner, board = board})
                end
            end
        elseif event.type == "disconnect" then
            self.connected = false
            self.playerId = nil
            self.playerSide = nil
            self.gameId = nil
            if self.onDisconnected then
                self.onDisconnected()
            end
        end
        event = self.host:service(0)
    end
end

function Network:sendJoin()
    if not self.connected or not self.peer then return end
    self.peer:send("join")
end

function Network:sendMove(fromR, fromC, toR, toC)
    if not self.connected or not self.peer or not self.gameId then return end
    local payload = string.format("move|%s|%s", self.gameId, serializeMove(fromR, fromC, toR, toC))
    self.peer:send(payload)
end

function Network:sendReset()
    if not self.connected or not self.peer or not self.gameId then return end
    local payload = string.format("reset|%s", self.gameId)
    self.peer:send(payload)
end

function Network:disconnect()
    if self.connected and self.host then
        self.host:flush()
        self.host = nil
        self.peer = nil
        self.connected = false
        if self.onDisconnected then
            self.onDisconnected()
        end
    end
end

return Network
