local AI = {}

-- Heuristic values
local PIECE_VALUE = 100
local KING_VALUE = 175
local EDGE_BONUS = 10
local BACK_ROW_BONUS = 20

-- Bonus applied to candidate moves that can chain multiple captures in a single turn.
local MULTI_KILL_BONUS = 50

-- Penalty applied to moves that match recent AI moves (discourages repeated play patterns)
local REPEAT_MOVE_PENALTY = 150

local function isMoveSame(a, b)
    if not a or not b then return false end
    return a.fromR == b.fromR and a.fromC == b.fromC and a.toR == b.toR and a.toC == b.toC
end

function AI.getBestMove(board, player, difficulty, recentMoves)
    difficulty = difficulty or "normal"

    local depth = 4
    local threshold = 15
    local allowRandom = true

    if difficulty == "easy" then
        depth = 2
        -- Choose from a very wide pool of moves to make the AI feel random.
        threshold = 1000
        allowRandom = true
    elseif difficulty == "normal" then
        depth = 4
        threshold = 15
        allowRandom = true
    elseif difficulty == "hard" then
        depth = 5
        threshold = 5
        allowRandom = true
    elseif difficulty == "engine" then
        depth = 6
        threshold = 0
        allowRandom = false
    end

    local moves = AI.getAllMoves(board, player)
    if #moves == 0 then return nil end

    local moveEvaluations = {}
    local bestScore = -math.huge
    
    -- Evaluate all possible moves
    for _, move in ipairs(moves) do
        local tempBoard = AI.copyBoard(board)
        AI.applyMove(tempBoard, move)
        
        local score = AI.minimax(tempBoard, depth - 1, -math.huge, math.huge, false, player)
        -- Give extra weight to moves that can chain multiple captures in one turn
        local chainBonus = (move.chain or 0) * MULTI_KILL_BONUS
        score = score + chainBonus

        -- Discourage repeating the same move too frequently (makes AI feel less “stuck”).
        if recentMoves then
            for _, recent in ipairs(recentMoves) do
                if isMoveSame(move, recent) then
                    score = score - REPEAT_MOVE_PENALTY
                    break
                end
            end
        end

        table.insert(moveEvaluations, {move = move, score = score})
        if score > bestScore then
            bestScore = score
        end
    end
    
    -- Filter moves that are "close enough" to the best score (Randomness Threshold)
    -- A threshold of 10-20 allows for variety without making the AI "dumb."
    local candidates = {}
    
    for _, item in ipairs(moveEvaluations) do
        if item.score >= (bestScore - threshold) then
            table.insert(candidates, item.move)
        end
    end
    
    if allowRandom then
        return candidates[math.random(#candidates)]
    else
        -- Engine mode: always choose the best move (first in the candidates list)
        return candidates[1]
    end
end

-- Fast best move estimate used for display (e.g., arrow) to avoid stuttering during deep search.
function AI.getBestMoveFast(board, player)
    local moves = AI.getAllMoves(board, player)
    if #moves == 0 then return nil end

    local bestScore = -math.huge
    local bestMove = nil

    for _, move in ipairs(moves) do
        local tempBoard = AI.copyBoard(board)
        AI.applyMove(tempBoard, move)
        local score = AI.evaluate(tempBoard, player)
        local chainBonus = (move.chain or 0) * MULTI_KILL_BONUS
        score = score + chainBonus

        if score > bestScore then
            bestScore = score
            bestMove = move
        end
    end

    return bestMove
end

function AI.minimax(board, depth, alpha, beta, isMaximizing, aiPlayer)
    if depth == 0 then
        return AI.evaluate(board, aiPlayer)
    end
    
    local opponent = (aiPlayer == 1) and 2 or 1
    local currentPlayer = isMaximizing and aiPlayer or opponent
    local moves = AI.getAllMoves(board, currentPlayer)
    
    if #moves == 0 then return isMaximizing and -10000 or 10000 end

    if isMaximizing then
        local maxEval = -math.huge
        for _, move in ipairs(moves) do
            local tempBoard = AI.copyBoard(board)
            AI.applyMove(tempBoard, move)
            local eval = AI.minimax(tempBoard, depth - 1, alpha, beta, false, aiPlayer)
            maxEval = math.max(maxEval, eval)
            alpha = math.max(alpha, eval)
            if beta <= alpha then break end
        end
        return maxEval
    else
        local minEval = math.huge
        for _, move in ipairs(moves) do
            local tempBoard = AI.copyBoard(board)
            AI.applyMove(tempBoard, move)
            local eval = AI.minimax(tempBoard, depth - 1, alpha, beta, true, aiPlayer)
            minEval = math.min(minEval, eval)
            beta = math.min(beta, eval)
            if beta <= alpha then break end
        end
        return minEval
    end
end

-- Simple evaluation function: Points for pieces, kings, and board control
function AI.evaluate(board, player)
    local score = 0
    local opponent = (player == 1) and 2 or 1
    
    for r = 1, 8 do
        for c = 1, 8 do
            local p = board[r][c]
            if p then
                local val = p.king and KING_VALUE or PIECE_VALUE
                
                -- Positional bonuses
                if c == 1 or c == 8 then val = val + EDGE_BONUS end
                if (p.player == 1 and r == 8) or (p.player == 2 and r == 1) then
                    val = val + BACK_ROW_BONUS
                end
                
                if p.player == player then
                    score = score + val
                else
                    score = score - val
                end
            end
        end
    end
    return score
end

-- Helper: Get all valid moves for a player (standard + jumps)
local function getMaxJumpChain(board, r, c)
    local p = board[r][c]
    if not p then return 0 end

    local best = 0
    local dirs = p.king and {-1, 1} or (p.player == 1 and {-1} or {1})

    for _, dr in ipairs(dirs) do
        for _, dc in ipairs({-1, 1}) do
            local jr, jc = r + dr*2, c + dc*2
            local mr, mc = r + dr, c + dc
            if jr >= 1 and jr <= 8 and jc >= 1 and jc <= 8 and not board[jr][jc] then
                local mid = board[mr][mc]
                if mid and mid.player ~= p.player then
                    -- Simulate the jump
                    local temp = AI.copyBoard(board)
                    local tp = temp[r][c]
                    temp[r][c] = nil
                    temp[jr][jc] = tp
                    temp[mr][mc] = nil

                    -- Apply kinging if needed
                    if not tp.king and ((tp.player == 1 and jr == 1) or (tp.player == 2 and jr == 8)) then
                        tp.king = true
                    end

                    local sub = getMaxJumpChain(temp, jr, jc)
                    best = math.max(best, 1 + sub)
                end
            end
        end
    end

    return best
end

function AI.getAllMoves(board, player)
    local moves = {}
    local jumps = {}

    for r = 1, 8 do
        for c = 1, 8 do
            if board[r][c] and board[r][c].player == player then
                -- Check standard moves and jumps
                local dirs = board[r][c].king and {-1, 1} or (player == 1 and {-1} or {1})
                for _, dr in ipairs(dirs) do
                    for _, dc in ipairs({-1, 1}) do
                        local nr, nc = r + dr, c + dc
                        -- Standard
                        if nr >= 1 and nr <= 8 and nc >= 1 and nc <= 8 and not board[nr][nc] then
                            table.insert(moves, {fromR=r, fromC=c, toR=nr, toC=nc, jump=false, chain=0})
                        end
                        -- Jump
                        local jr, jc = r + (dr*2), c + (dc*2)
                        if jr >= 1 and jr <= 8 and jc >= 1 and jc <= 8 and not board[jr][jc] then
                            local mid = board[r+dr][c+dc]
                            if mid and mid.player ~= player then
                                -- Compute how many captures this jump can lead to (including this one)
                                local temp = AI.copyBoard(board)
                                AI.applyMove(temp, {fromR=r, fromC=c, toR=jr, toC=jc, jump=true})
                                local chain = 1 + getMaxJumpChain(temp, jr, jc)
                                table.insert(jumps, {fromR=r, fromC=c, toR=jr, toC=jc, jump=true, chain=chain})
                            end
                        end
                    end
                end
            end
        end
    end

    -- If any captures are available, they must be taken (standard checkers rule)
    if #jumps > 0 then
        return jumps
    end

    return moves
end

function AI.applyMove(board, move)
    local p = board[move.fromR][move.fromC]
    board[move.toR][move.toC] = p
    board[move.fromR][move.fromC] = nil
    if move.jump then
        board[(move.fromR + move.toR)/2][(move.fromC + move.toC)/2] = nil
    end
    -- Kinging logic
    if (p.player == 1 and move.toR == 1) or (p.player == 2 and move.toR == 8) then
        p.king = true
    end
end

function AI.copyBoard(orig)
    local copy = {}
    for r, row in pairs(orig) do
        copy[r] = {}
        for c, col in pairs(row) do
            copy[r][c] = {player = col.player, king = col.king}
        end
    end
    return copy
end

return AI