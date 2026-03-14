local Board = require("src.board")
local Sounds = require("src.sounds")

local AI = require("src.ai")

local Input = {}

local function updateLegalMoves(game)
    game.legalMoves = {}
    local selection = game.selectedTile or game.dragPiece
    if not selection then
        return
    end

    local allMoves = AI.getAllMoves(game.board, game.turn)
    for _, m in ipairs(allMoves) do
        if m.fromR == selection.row and m.fromC == selection.col then
            table.insert(game.legalMoves, m)
        end
    end
end

function Input.handleKey(game, key)
    if key == "space" then
        game:cycleMode()
        game.selectedTile = nil
        print("Mode: " .. game:getModeLabel())
    elseif key == "d" then
        game:cycleDifficulty()
        print("AI Difficulty: " .. game:getDifficultyLabel())
    elseif key == "p" then
        game.aiPaused = not game.aiPaused
        print("AI paused: " .. tostring(game.aiPaused))
    elseif key == "n" then
        if not game.networked then
            local ok, err = game.network:init("127.0.0.1", 6789)
            if ok then
                game.networked = true
                game.network:sendJoin()
                print("Connecting to multiplayer server...")
            else
                print("Network error: " .. tostring(err))
            end
        else
            game.network:disconnect()
            game.networked = false
            game.localSide = nil
            game.network.gameId = nil
            print("Disconnected from multiplayer server")
        end
    elseif key == "r" then
        -- Restart locally always.
        game:initBoard()
        game.turn = 1

        if game.networked and game.network.connected then
            -- Reset the server-side game board while staying connected to the same opponent.
            game.network:sendReset()
        end
    end
end

function Input.handleMousePressed(game, x, y, button)
    if button ~= 1 or not game:isLocalTurn() then return end

    local localX = x - (game.boardOffsetX or 0)
    local localY = y - (game.boardOffsetY or 0)
    if localX < 0 or localY < 0 then
        game.dragPiece = nil
        return
    end

    if localX >= game.boardSize * game.tileSize or localY >= game.boardSize * game.tileSize then
        game.dragPiece = nil
        return
    end

    local col = math.floor(localX / game.tileSize) + 1
    local row = math.floor(localY / game.tileSize) + 1

    -- If a piece is locked (multi-jump), only allow dragging that piece
    if game.lockedPiece then
        if row == game.lockedPiece.row and col == game.lockedPiece.col then
            game.dragPiece = {row = row, col = col}
            game.selectedTile = {row = row, col = col}
            updateLegalMoves(game)
        end
        return
    end

    -- If we already have a piece selected, clicking another square should attempt the move
    if game.selectedTile then
        local active = game.selectedTile
        local moved, jumped, promoted = Board.movePiece(game.board, active.row, active.col, row, col, game.boardSize)
        if moved then
            if promoted then
                Sounds:playPromotion()
            elseif jumped then
                Sounds:playCapture()
            else
                Sounds:playMove()
            end

            game:addHistory(game.turn, active.row, active.col, row, col)
            game.bestMove = nil
            game.bestMoveTimer = game.bestMoveInterval

            if game.networked then
                game.network:sendMove(active.row, active.col, row, col)
            end

            -- Clear legal move hints (the board will change)
            game.legalMoves = {}

            if jumped and Board.canJump(game.board, row, col, game.boardSize) then
                game.lockedPiece = {row = row, col = col}
                game.selectedTile = nil
            else
                game.lockedPiece = nil
                game.selectedTile = nil
                game.turn = 3 - game.turn -- switch player

                -- Count turns for timeout condition
                game.turnCounter = game.turnCounter + 1

                -- Check for endgame after changing turns
                game:checkGameOver()
            end

            return
        end
    end

    -- Start dragging a piece if it belongs to the current player
    if game.board[row] and game.board[row][col] and game.board[row][col].player == game.turn then
        game.selectedTile = {row = row, col = col}
        game.dragPiece = {row = row, col = col}
        updateLegalMoves(game)
    else
        game.selectedTile = nil
        game.dragPiece = nil
        game.legalMoves = {}
    end
end

function Input.handleMouseReleased(game, x, y, button)
    if button ~= 1 or not game:isLocalTurn() then return end
    if not game.dragPiece then return end

    local localX = x - (game.boardOffsetX or 0)
    local localY = y - (game.boardOffsetY or 0)
    if localX < 0 or localY < 0 or localX >= game.boardSize * game.tileSize or localY >= game.boardSize * game.tileSize then
        game.dragPiece = nil
        return
    end

    local col = math.floor(localX / game.tileSize) + 1
    local row = math.floor(localY / game.tileSize) + 1

    local active = game.dragPiece
    game.dragPiece = nil

    local moved, jumped, promoted = Board.movePiece(game.board, active.row, active.col, row, col, game.boardSize)
    if moved then
        if promoted then
            Sounds:playPromotion()
        elseif jumped then
            Sounds:playCapture()
        else
            Sounds:playMove()
        end

        game:addHistory(game.turn, active.row, active.col, row, col)
        game.bestMove = nil
        game.bestMoveTimer = game.bestMoveInterval

        if game.networked then
            game.network:sendMove(active.row, active.col, row, col)
        end

        if jumped and Board.canJump(game.board, row, col, game.boardSize) then
            game.lockedPiece = {row = row, col = col}
            game.selectedTile = nil
        else
            game.lockedPiece = nil
            game.selectedTile = nil
            game.turn = 3 - game.turn -- switch player

            -- Count turns for timeout condition
            game.turnCounter = game.turnCounter + 1

            -- Check for endgame after changing turns
            game:checkGameOver()
        end
    else
        -- If move not allowed, keep selection on original piece
        game.selectedTile = {row = active.row, col = active.col}
        game.legalMoves = {}
    end
end

return Input
