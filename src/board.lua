local Board = {}

function Board.init(boardSize, tileSize, offsetX, offsetY)
    local board = {}

    for row = 1, boardSize do
        board[row] = {}
        for col = 1, boardSize do
            if (row + col) % 2 == 1 then
                local p = nil
                if row <= 3 then p = 2
                elseif row >= 6 then p = 1 end

                if p then
                    board[row][col] = {
                        player = p,
                        king = false,
                        visualX = offsetX + (col - 0.5) * tileSize,
                        visualY = offsetY + (row - 0.5) * tileSize
                    }
                end
            end
        end
    end

    return board
end

function Board.movePiece(board, r1, c1, r2, c2, boardSize)
    local p = board[r1][c1]
    if not p or r2 < 1 or r2 > boardSize or c2 < 1 or c2 > boardSize or board[r2][c2] then
        return false, false, false
    end

    local rDiff = r2 - r1
    local cDiff = math.abs(c2 - c1)
    local dir = (p.player == 1) and -1 or 1

    local promoted = false

    -- Regular Move (Disallow if a multi-jump is in progress)
    -- Caller is responsible for enforcing locked-piece rules.
    if cDiff == 1 and (rDiff == dir or p.king) then
        board[r2][c2], board[r1][c1] = p, nil

        -- Kinging
        if ((p.player == 1 and r2 == 1) or (p.player == 2 and r2 == boardSize)) and not p.king then
            p.king = true
            promoted = true
        end

        return true, false, promoted
    end

    -- Jump Move
    if cDiff == 2 and math.abs(rDiff) == 2 then
        if not p.king and ((p.player == 1 and rDiff > 0) or (p.player == 2 and rDiff < 0)) then
            return false, false, false
        end

        local midR, midC = (r1 + r2) / 2, (c1 + c2) / 2
        if board[midR][midC] and board[midR][midC].player ~= p.player then
            board[r2][c2], board[r1][c1] = p, nil
            board[midR][midC] = nil -- Capture!

            -- Kinging
            if ((p.player == 1 and r2 == 1) or (p.player == 2 and r2 == boardSize)) and not p.king then
                p.king = true
                promoted = true
            end

            return true, true, promoted
        end
    end

    return false, false, false
end

function Board.canJump(board, r, c, boardSize)
    local p = board[r][c]
    if not p then return false end

    local targets = p.king and {{-2,-2}, {-2,2}, {2,-2}, {2,2}} or
                    (p.player == 1 and {{-2,-2}, {-2,2}} or {{2,-2}, {2,2}})

    for _, off in ipairs(targets) do
        local tr, tc = r + off[1], c + off[2]
        local mr, mc = r + off[1] / 2, c + off[2] / 2
        if tr >= 1 and tr <= boardSize and tc >= 1 and tc <= boardSize and not board[tr][tc] then
            if board[mr][mc] and board[mr][mc].player ~= p.player then
                return true
            end
        end
    end

    return false
end

return Board
