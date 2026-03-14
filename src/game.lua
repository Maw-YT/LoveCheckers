local Board = require("src.board")
local Renderer = require("src.renderer")
local Input = require("src.input")
local AiController = require("src.ai_controller")
local AI = require("src.ai")
local Sounds = require("src.sounds")
local Network = require("src.network")

local Game = {
    boardSize = 8,
    tileSize = 80,
    lerpSpeed = 10,
    aiMoveDelay = 0.8,

    sidebarWidth = 140,
    rightMenuWidth = 220,
    boardOffsetX = 0,
    boardOffsetY = 10,

    board = {},
    selectedTile = nil,
    turn = 1,
    lockedPiece = nil,
    aiTimer = 0,
    dragPiece = nil,
    aiPaused = false,

    -- Modes: "hva" (human vs AI), "hvh" (human vs human), "ava" (AI vs AI)
    mode = "hva",
    modeOrder = {"hva", "hvh", "ava"},

    -- AI difficulty settings
    aiDifficulty = "normal",
    difficultyOrder = {"easy", "normal", "hard", "engine"},

    bestMove = nil,
    bestMoveTimer = 0,
    bestMoveInterval = 1.0,

    moveHistory = {},
    maxHistory = 12,

    recentAIMoves = {},
    maxRecentAIMoves = 12,

    -- Endgame timeout (tie-break): if too many turns have passed, decide winner by board evaluation.
    turnCounter = 0,
    maxTurns = 100,

    gameOver = false,
    winner = nil,
    timeoutWinner = nil,

    networked = false,
    network = nil,
    localSide = nil,
}

function Game:init()
    -- Seed the random number generator using the system time
    love.math.setRandomSeed(os.time())

    self.boardOffsetX = self.sidebarWidth + 10
    self.boardOffsetY = 10

    local width = self.boardOffsetX + self.boardSize * self.tileSize + self.rightMenuWidth + 20
    local height = self.boardSize * self.tileSize + self.boardOffsetY + 10
    love.window.setMode(width, height)
    love.window.setTitle("LÖVE Checkers: AI")

    -- Initialize audio
    Sounds:init()

    self:initBoard()

    -- Start AI background worker
    AiController.init(self)

    -- Network (optional multiplayer)
    self.network = Network
    self.network:onAssigned(function(side, gameId)
        self.localSide = side
        print("Joined game " .. gameId .. " as " .. (side == 1 and "Red" or "White"))
    end)
    self.network:onState(function(state)
        if state.gameId == self.network.gameId then
            self:applyNetworkBoard(state.board)
            self.turn = state.turn
            self.gameOver = state.gameOver
            self.winner = state.winner
        end
    end)

    self.network:onDisconnected(function()
        self.networked = false
        self.localSide = nil
        self.network.gameId = nil
        print("Network disconnected")
    end)
end

function Game:applyNetworkBoard(newBoard)
    -- When receiving a full board update from the server we want pieces to animate smoothly.
    -- This function reuses existing piece objects so `visualX/visualY` don't reset to (0,0).

    local function legalMove(fromR, fromC, toR, toC, king, player)
        local dr = toR - fromR
        local dc = toC - fromC
        local adr = math.abs(dr)
        local adc = math.abs(dc)

        if adr == 1 and adc == 1 then
            if king then
                return true
            end
            if player == 1 then
                return dr == -1
            else
                return dr == 1
            end
        end

        if adr == 2 and adc == 2 then
            if king then
                return true
            end
            if player == 1 then
                return dr == -2
            else
                return dr == 2
            end
        end

        return false
    end

    -- Phase 1: identify which positions are already the same (keep those pieces)
    local updated = {}
    local sources = {}
    for r = 1, self.boardSize do
        updated[r] = {}
        for c = 1, self.boardSize do
            local oldP = self.board[r] and self.board[r][c]
            local newP = newBoard[r] and newBoard[r][c]

            if oldP and newP and oldP.player == newP.player and oldP.king == newP.king then
                -- same piece stays in place
                updated[r][c] = oldP
            else
                if oldP then
                    table.insert(sources, {r = r, c = c, piece = oldP, used = false})
                end
                if newP then
                    updated[r][c] = newP -- placeholder, will be fixed in phase 2
                else
                    updated[r][c] = nil
                end
            end
        end
    end

    -- Phase 2: match new positions to source pieces based on legal move patterns.
    for r = 1, self.boardSize do
        for c = 1, self.boardSize do
            local incoming = updated[r][c]
            if incoming and (not (self.board[r] and self.board[r][c] and self.board[r][c].player == incoming.player and self.board[r][c].king == incoming.king)) then
                local bestSource, bestScore
                local targetX = self.boardOffsetX + (c - 0.5) * self.tileSize
                local targetY = self.boardOffsetY + (r - 0.5) * self.tileSize

                for _, src in ipairs(sources) do
                    if not src.used and src.piece.player == incoming.player then
                        if legalMove(src.r, src.c, r, c, src.piece.king, src.piece.player) then
                            local dx = src.piece.visualX - targetX
                            local dy = src.piece.visualY - targetY
                            local score = dx * dx + dy * dy
                            if not bestScore or score < bestScore then
                                bestScore = score
                                bestSource = src
                            end
                        end
                    end
                end

                if bestSource then
                    bestSource.used = true
                    bestSource.piece.king = incoming.king
                    updated[r][c] = bestSource.piece
                else
                    -- fallback: reuse nearest matching piece of same player+king (less strict)
                    for _, src in ipairs(sources) do
                        if not src.used and src.piece.player == incoming.player and src.piece.king == incoming.king then
                            local dx = src.piece.visualX - targetX
                            local dy = src.piece.visualY - targetY
                            local score = dx * dx + dy * dy
                            if not bestScore or score < bestScore then
                                bestScore = score
                                bestSource = src
                            end
                        end
                    end
                    if bestSource then
                        bestSource.used = true
                        updated[r][c] = bestSource.piece
                    else
                        incoming.visualX = targetX
                        incoming.visualY = targetY
                        updated[r][c] = incoming
                    end
                end
            end
        end
    end

    self.board = updated

    -- Clear selection/hints when remote state arrives (avoid stale legal-move highlights)
    self.selectedTile = nil
    self.dragPiece = nil
    self.legalMoves = {}
end

function Game:cycleMode()
    for i, v in ipairs(self.modeOrder) do
        if v == self.mode then
            self.mode = self.modeOrder[(i % #self.modeOrder) + 1]
            break
        end
    end
end

function Game:getModeLabel()
    if self.mode == "hva" then
        return "Human vs AI"
    elseif self.mode == "hvh" then
        return "Human vs Human"
    elseif self.mode == "ava" then
        return "AI vs AI"
    end
    return "Unknown"
end

function Game:cycleDifficulty()
    for i, v in ipairs(self.difficultyOrder) do
        if v == self.aiDifficulty then
            self.aiDifficulty = self.difficultyOrder[(i % #self.difficultyOrder) + 1]
            break
        end
    end
end

function Game:getDifficultyLabel()
    if self.aiDifficulty == "easy" then
        return "Easy"
    elseif self.aiDifficulty == "normal" then
        return "Normal"
    elseif self.aiDifficulty == "hard" then
        return "Hard"
    elseif self.aiDifficulty == "engine" then
        return "Engine"
    end
    return "Unknown"
end

function Game:isAiTurn()
    -- In networked games we never run the built-in AI.
    if self.gameOver or self.networked then
        return false
    end

    if self.mode == "ava" then
        return true
    elseif self.mode == "hva" then
        return self.turn == 2
    end
    return false
end

function Game:isLocalTurn()
    if self.gameOver then
        return false
    end

    if self.networked then
        return self.localSide == self.turn
    end

    if self.mode == "ava" then
        return false
    elseif self.mode == "hva" then
        return self.turn == 1
    end
    return true
end

function Game:checkGameOver()
    -- Determine if either player has no pieces or no legal moves.
    local players = {1, 2}
    for _, player in ipairs(players) do
        -- Check for pieces
        local pieceCount = 0
        for r = 1, self.boardSize do
            for c = 1, self.boardSize do
                if self.board[r][c] and self.board[r][c].player == player then
                    pieceCount = pieceCount + 1
                end
            end
        end

        if pieceCount == 0 then
            self.gameOver = true
            self.winner = 3 - player
            return true
        end

        -- Check for legal moves
        local moves = AI.getAllMoves(self.board, player)
        if #moves == 0 then
            self.gameOver = true
            self.winner = 3 - player
            return true
        end
    end

    -- Timeout: if too many turns have happened, decide winner by board evaluation
    if self.turnCounter >= self.maxTurns then
        self.gameOver = true
        local redScore = AI.evaluate(self.board, 1)
        local whiteScore = AI.evaluate(self.board, 2)
        if redScore > whiteScore then
            self.timeoutWinner = 1
            self.winner = 1
        elseif whiteScore > redScore then
            self.timeoutWinner = 2
            self.winner = 2
        else
            self.timeoutWinner = 0 -- tie
            self.winner = 0
        end
        return true
    end

    return false
end

function Game:initBoard()
    self.board = Board.init(self.boardSize, self.tileSize, self.boardOffsetX, self.boardOffsetY)
    self.selectedTile = nil
    self.lockedPiece = nil
    self.turn = 1
    self.aiTimer = 0
    self.bestMove = nil
    self.bestMoveTimer = 0
    self.moveHistory = {}
    self.recentAIMoves = {}
    self.turnCounter = 0
    self.aiPaused = false
    self.gameOver = false
    self.winner = nil
    self.timeoutWinner = nil
    self.legalMoves = {}
end

function Game:update(dt)
    -- 1. Smooth Animation Logic
    self.time = (self.time or 0) + dt

    for r = 1, self.boardSize do
        for c = 1, self.boardSize do
            local p = self.board[r][c]
            if p then
                local targetX = self.boardOffsetX + (c - 0.5) * self.tileSize
                local targetY = self.boardOffsetY + (r - 0.5) * self.tileSize
                p.visualX = p.visualX + (targetX - p.visualX) * self.lerpSpeed * dt
                p.visualY = p.visualY + (targetY - p.visualY) * self.lerpSpeed * dt
            end
        end
    end

    -- 2. Automated Turn Logic
    if not self.gameOver and not self.networked then
        AiController.update(self, dt)
    end

    -- 3. Network updates
    if self.networked then
        self.network:update()
        if not self.network.connected then
            self.networked = false
            self.localSide = nil
            self.network.gameId = nil
        end
    end

    -- 3. Best-move arrow update (throttled)
    if self:isAiTurn() then
        self.bestMoveTimer = self.bestMoveTimer + dt
        if self.bestMoveTimer >= self.bestMoveInterval then
            -- Use a lighter-weight best-move estimation for arrow display so the game stays smooth.
            self.bestMove = AI.getBestMoveFast(self.board, self.turn)
            self.bestMoveTimer = 0
        end
    else
        self.bestMove = nil
    end
end

function Game:draw()
    Renderer.draw(self)
end

function Game:keypressed(key)
    Input.handleKey(self, key)
end

function Game:addHistory(player, fromR, fromC, toR, toC)
    local entry = string.format("%s: %d,%d -> %d,%d", (player == 1 and "Red" or "White"), fromR, fromC, toR, toC)
    table.insert(self.moveHistory, 1, entry)
    if #self.moveHistory > self.maxHistory then
        table.remove(self.moveHistory)
    end
end

function Game:mousepressed(x, y, button)
    Input.handleMousePressed(self, x, y, button)
end

function Game:mousereleased(x, y, button)
    Input.handleMouseReleased(self, x, y, button)
end

return Game
