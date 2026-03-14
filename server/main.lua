-- Simple ENet server for LoveCheckers multiplayer.
-- Run with: love ./server/
-- Requires Love2D's enet module (or lua-enet).

local ok, enet = pcall(require, "enet")
if not ok then
    error("enet is required to run the server (lua-enet)\n")
end

local Board = require("src.board")
local AI = require("src.ai")

local PORT = 6789

local host
local clients = {}
local games = {}
local nextGameId = 1
local nextClientId = 1

local function createHost()
    -- enet.host_create can accept either a string address (lua-enet) or a numeric port (love.enet).
    -- Some builds (love.enet) will error when given the string form, so we pcall it.
    local h, err

    local ok
    ok, h = pcall(enet.host_create, "0.0.0.0:" .. PORT)
    if not ok or not h then
        ok, h = pcall(enet.host_create, PORT)
        if not ok or not h then
            err = h or err
            error("Failed to create ENet host: " .. tostring(err))
        end
    end

    return h
end

local function resetServer()
    host = createHost()
    clients = {}
    games = {}
    nextGameId = 1
    nextClientId = 1
end

local serverStartTime = love and love.timer and love.timer.getTime() or os.time()

local function serializeBoard(board)
    local out = {}
    for r = 1, 8 do
        for c = 1, 8 do
            local p = board[r][c]
            if not p then
                out[#out+1] = "0"
            else
                local base = (p.player == 2) and 20 or 10
                out[#out+1] = tostring(base + (p.king and 1 or 0))
            end
        end
    end
    return table.concat(out, ",")
end

local function formatTime(seconds)
    local m = math.floor(seconds / 60)
    local s = math.floor(seconds % 60)
    return string.format("%02d:%02d", m, s)
end

local function checkGameOver(game)
    -- Determine if either player has no pieces or no legal moves.
    for _, player in ipairs({1, 2}) do
        local pieceCount = 0
        for r = 1, 8 do
            for c = 1, 8 do
                if game.board[r][c] and game.board[r][c].player == player then
                    pieceCount = pieceCount + 1
                end
            end
        end

        if pieceCount == 0 then
            game.gameOver = true
            game.winner = 3 - player
            return
        end

        local moves = AI.getAllMoves(game.board, player)
        if #moves == 0 then
            game.gameOver = true
            game.winner = 3 - player
            return
        end
    end

    game.gameOver = false
    game.winner = nil
end

local function broadcastGameState(game)
    local boardStr = serializeBoard(game.board)
    local gameOverFlag = game.gameOver and 1 or 0
    local winnerId = game.winner or 0
    local msg = string.format("state|%d|%d|%d|%d|%s", game.id, game.turn, gameOverFlag, winnerId, boardStr)
    for _, client in pairs(game.clients) do
        client.peer:send(msg)
    end
end

local function createGame(c1, c2)
    local game = {
        id = nextGameId,
        board = Board.init(8, 80, 0, 0),
        turn = 1,
        clients = {c1, c2},
    }
    c1.game = game
    c1.side = 1
    c2.game = game
    c2.side = 2
    games[game.id] = game
    nextGameId = nextGameId + 1

    c1.peer:send(string.format("assigned|%d|%d|%d", c1.id, 1, game.id))
    c2.peer:send(string.format("assigned|%d|%d|%d", c2.id, 2, game.id))

    broadcastGameState(game)
end

local function findOpenGame()
    for _, g in pairs(games) do
        if #g.clients == 1 then
            return g
        end
    end
    return nil
end

local function handleMove(client, payload)
    local game = client.game
    if not game then return end

    local parts = {}
    for part in string.gmatch(payload, "[^,]+") do
        parts[#parts+1] = tonumber(part)
    end
    if #parts ~= 4 then return end

    local fromR, fromC, toR, toC = parts[1], parts[2], parts[3], parts[4]
    -- Only allow moves for the side whose turn it is
    if game.turn ~= client.side then return end

    local moved, jumped, promoted = Board.movePiece(game.board, fromR, fromC, toR, toC, 8)
    if not moved then return end

    -- enforce multi-jump
    if jumped and Board.canJump(game.board, toR, toC, 8) then
        -- keep same turn
    else
        game.turn = 3 - game.turn
    end

    checkGameOver(game)
    broadcastGameState(game)
end

local serverLogs = {}

local function logServer(msg)
    table.insert(serverLogs, 1, string.format("[%s] %s", formatTime(love.timer.getTime() - serverStartTime), msg))
    while #serverLogs > 10 do
        table.remove(serverLogs)
    end
end

local function cleanupClient(clientId)
    local client = clients[clientId]
    if not client then
        return
    end

    -- Remove from any game (active or waiting)
    if client.game then
        local g = client.game
        for i, c in ipairs(g.clients) do
            if c == client then
                table.remove(g.clients, i)
                break
            end
        end

        if #g.clients == 0 then
            games[g.id] = nil
        end
    else
        -- If the client was waiting (not yet in a real game), remove its waiting placeholder
        for id, g in pairs(games) do
            if g.id < 0 and #g.clients == 1 and g.clients[1] == client then
                games[id] = nil
                break
            end
        end
    end

    clients[clientId] = nil
end

local function processEvent(event)
    if not event then
        return
    end

    if event.type == "connect" then
        local id = nextClientId
        nextClientId = nextClientId + 1
        logServer("Client connected: " .. id)
        clients[id] = {id = id, peer = event.peer, game = nil, side = nil}

        -- attempt to join a game
        local open = findOpenGame()
        if open then
            open.clients[#open.clients+1] = clients[id]

            -- Remove the placeholder waiting-game entry before creating the real game
            if open.id and open.id < 0 then
                games[open.id] = nil
            end

            createGame(open.clients[1], open.clients[2])
        else
            -- create waiting game
            local g = {id = -id, board = nil, turn = 1, clients = {clients[id]}}
            games[-id] = g
        end

        return
    end

    if event.type == "receive" then
        local data = event.data
        local client
        for _, c in pairs(clients) do
            if c.peer == event.peer then
                client = c
                break
            end
        end
        if not client then
            return
        end

        local parts = {}
        for token in string.gmatch(data, "[^|]+") do
            parts[#parts+1] = token
        end

        if parts[1] == "join" then
            -- join logic handled in connect
        elseif parts[1] == "move" then
            local gameId = tonumber(parts[2])
            local payload = parts[3]
            handleMove(client, payload)
        elseif parts[1] == "reset" then
            local gameId = tonumber(parts[2])
            if client.game and client.game.id == gameId then
                local game = client.game
                game.board = Board.init(8, 80, 0, 0)
                game.turn = 1
                game.gameOver = false
                game.winner = nil
                broadcastGameState(game)
                logServer("Game " .. gameId .. " reset")
            end
        end

        return
    end

    if event.type == "disconnect" then
        local disconnectedId
        for id, c in pairs(clients) do
            if c.peer == event.peer then
                disconnectedId = id
                break
            end
        end
        if disconnectedId then
            logServer("Client disconnected: " .. disconnectedId)
            cleanupClient(disconnectedId)
        end
    end
end

function love.load()
    love.window.setTitle("LoveCheckers Server")
    love.window.setMode(500, 400, {resizable = true})

    resetServer()
    logServer("Server started on port " .. PORT)
end

function love.update(dt)
    if host then
        local event = host:service(0)
        while event do
            processEvent(event)
            event = host:service(0)
        end
    end
end

function love.draw()
    love.graphics.clear(0.1, 0.1, 0.12)
    love.graphics.setColor(1, 1, 1)

    love.graphics.print("LoveCheckers Server", 10, 10)
    love.graphics.print("Port: " .. PORT, 10, 30)

    local clientCount = (function() local n=0; for _ in pairs(clients) do n=n+1 end; return n end)()
    local gameCount = (function() local n=0; for _ in pairs(games) do n=n+1 end; return n end)()

    love.graphics.print("Clients: " .. clientCount, 10, 50)
    love.graphics.print("Games: " .. gameCount .. " (active)", 10, 70)

    local y = 100
    for _, g in pairs(games) do
        if g.id > 0 then
            local status = g.gameOver and ("Game " .. g.id .. " OVER (Winner: " .. (g.winner == 1 and "Red" or "White") .. ")") or ("Game " .. g.id .. " Turn: " .. g.turn)
            love.graphics.print(status, 10, y)
            y = y + 16
            for _, c in ipairs(g.clients) do
                love.graphics.print(string.format("  - Client %d (side %d)", c.id, c.side), 16, y)
                y = y + 14
            end
            y = y + 4
        end
    end

    y = y + 10
    love.graphics.print("Server logs:", 10, y)
    y = y + 16
    for i = 1, math.min(#serverLogs, 8) do
        love.graphics.print(serverLogs[i], 10, y)
        y = y + 14
    end

    love.graphics.print("Press Esc to quit", 10, love.graphics.getHeight() - 20)
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    end
end
