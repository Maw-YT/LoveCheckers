local AI = require("src.ai")
local Board = require("src.board")
local Sounds = require("src.sounds")

local AiController = {
    thread = nil,
    jobChannelName = "lovecheckers_ai_job",
    resultChannelName = "lovecheckers_ai_result",
}

local function ensureThread()
    if AiController.thread and AiController.thread:isRunning() then
        return
    end

    AiController.thread = love.thread.newThread("src/ai_worker.lua")
    AiController.thread:start()
end

function AiController.init(game)
    ensureThread()
    game.aiThinking = false
    game.aiJobId = 0

    -- Clear any leftover channel messages
    love.thread.getChannel(AiController.jobChannelName):clear()
    love.thread.getChannel(AiController.resultChannelName):clear()
end

function AiController.update(game, dt)
    if game.aiPaused then
        return
    end

    if not game:isAiTurn() then
        return
    end

    -- Make sure the worker is running
    ensureThread()

    game.aiTimer = game.aiTimer + dt

    -- If already waiting for the AI, check for results
    if game.aiThinking then
        local res = love.thread.getChannel(AiController.resultChannelName):pop()
        if res and res.jobId == game.aiJobId then
            game.aiThinking = false
            game.aiTimer = 0

            local best = res.best
            game.bestMove = best
            game.bestMoveTimer = 0

            if best then
                local moved, jumped, promoted = Board.movePiece(game.board, best.fromR, best.fromC, best.toR, best.toC, game.boardSize)

                if moved then
                    if promoted then
                        Sounds:playPromotion()
                    elseif jumped then
                        Sounds:playCapture()
                    else
                        Sounds:playMove()
                    end
                end

                game:addHistory(game.turn, best.fromR, best.fromC, best.toR, best.toC)

                if jumped and Board.canJump(game.board, best.toR, best.toC, game.boardSize) then
                    game.lockedPiece = {row = best.toR, col = best.toC}
                else
                    game.lockedPiece = nil
                    game.turn = (game.turn == 1) and 2 or 1
                    game.bestMoveTimer = game.bestMoveInterval
                    game.bestMove = nil

                    -- Track moves for repetition handling
                    table.insert(game.recentAIMoves, 1, {fromR = best.fromR, fromC = best.fromC, toR = best.toR, toC = best.toC})
                    if #game.recentAIMoves > game.maxRecentAIMoves then
                        table.remove(game.recentAIMoves)
                    end

                    -- Count turns for timeout condition
                    game.turnCounter = game.turnCounter + 1

                    -- Check for endgame after AI move
                    game:checkGameOver()
                end

                game.aiTimer = 0
            else
                -- If no moves, game over - restart after a delay
                print("Player " .. game.turn .. " has no moves. Restarting...")
                game.aiTimer = -2 -- Pause for 2 seconds before restart
                game:initBoard()
                game.turn = 1
            end
        end

        return
    end

    -- If not yet thinking, start thinking after delay
    if game.aiTimer < game.aiMoveDelay then
        return
    end

    -- Submit a job to the worker thread
    game.aiJobId = (game.aiJobId or 0) + 1
    local job = {
        jobId = game.aiJobId,
        board = AI.copyBoard(game.board),
        player = game.turn,
        difficulty = game.aiDifficulty,
        recentMoves = game.recentAIMoves,
    }

    love.thread.getChannel(AiController.jobChannelName):push(job)

    game.aiThinking = true
end

return AiController
