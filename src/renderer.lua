local AI = require("src.ai")

local Renderer = {}

local function drawArrow(x1, y1, x2, y2)
    local arrowSize = 10
    love.graphics.setLineWidth(3)
    love.graphics.line(x1, y1, x2, y2)

    local angle = math.atan2(y2 - y1, x2 - x1)
    local left = angle + math.pi * 3 / 4
    local right = angle - math.pi * 3 / 4

    love.graphics.line(x2, y2, x2 + math.cos(left) * arrowSize, y2 + math.sin(left) * arrowSize)
    love.graphics.line(x2, y2, x2 + math.cos(right) * arrowSize, y2 + math.sin(right) * arrowSize)

    love.graphics.setLineWidth(1)
end

function Renderer.draw(game)
    -- Sidebar Background
    love.graphics.setColor(0.12, 0.12, 0.12)
    love.graphics.rectangle("fill", 0, 0, game.sidebarWidth, game.boardSize * game.tileSize + game.boardOffsetY + 10)

    -- Performance Bar (Red vs White) - vertical, left side
    local redScore = AI.evaluate(game.board, 1)
    local whiteScore = AI.evaluate(game.board, 2)
    local diff = redScore - whiteScore
    local advantage = (math.tanh(diff / 200) + 1) / 2 -- normalized 0..1

    local barX = 20
    local barY = 20
    local barWidth = 60
    local barHeight = game.boardSize * game.tileSize - 40

    local redHeight = math.floor(barHeight * advantage)
    local whiteHeight = barHeight - redHeight

    -- Bar background
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", barX - 4, barY - 4, barWidth + 8, barHeight + 8, 6, 6)

    -- Red portion (bottom)
    love.graphics.setColor(0.8, 0.1, 0.1)
    love.graphics.rectangle("fill", barX, barY + whiteHeight, barWidth, redHeight)

    -- White portion (top)
    love.graphics.setColor(0.9, 0.9, 0.9)
    love.graphics.rectangle("fill", barX, barY, barWidth, whiteHeight)

    -- Bar outline
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.rectangle("line", barX, barY, barWidth, barHeight, 6, 6)
    love.graphics.setColor(1, 1, 1)

    love.graphics.print("R: " .. math.floor(redScore), barX, barY + barHeight + 10)
    love.graphics.print("W: " .. math.floor(whiteScore), barX, barY + barHeight + 25)

    -- Draw Board
    for row = 1, game.boardSize do
        for col = 1, game.boardSize do
            local x = game.boardOffsetX + (col - 1) * game.tileSize
            local y = game.boardOffsetY + (row - 1) * game.tileSize

            if (row + col) % 2 == 0 then
                love.graphics.setColor(0.9, 0.8, 0.7)
            else
                love.graphics.setColor(0.3, 0.2, 0.1)
            end
            love.graphics.rectangle("fill", x, y, game.tileSize, game.tileSize)
        end
    end

    -- Draw Pieces (and highlight selection + legal moves)
    local selection = game.selectedTile or game.dragPiece
    if selection then
        -- Highlight selected square (or drag source)
        local selX = game.boardOffsetX + (selection.col - 1) * game.tileSize
        local selY = game.boardOffsetY + (selection.row - 1) * game.tileSize
        love.graphics.setColor(0, 1, 0, 0.2)
        love.graphics.rectangle("fill", selX, selY, game.tileSize, game.tileSize)
    end

    for row = 1, game.boardSize do
        for col = 1, game.boardSize do
            if game.dragPiece and game.dragPiece.row == row and game.dragPiece.col == col then
                -- Skip drawing the dragged piece at its original location
            else
                local p = game.board[row][col]
                if p then
                    local px, py = p.visualX, p.visualY

                    -- Highlight selected piece with a gentle pulse
                    local scale = 1
                    if game.selectedTile and game.selectedTile.row == row and game.selectedTile.col == col then
                        scale = 1.05 + 0.03 * math.sin((love.timer.getTime() or 0) * 6)
                    end

                    love.graphics.setColor(p.player == 1 and {0.8, 0.1, 0.1} or {0.9, 0.9, 0.9})
                    love.graphics.circle("fill", px, py, game.tileSize * 0.4 * scale)
                    if p.king then
                        local crownColor = (p.player == 1) and {1, 1, 0} or {0.8, 0.1, 0.1}
                        love.graphics.setColor(crownColor)

                        -- Draw a simple crown marker above the piece
                        local crownSize = game.tileSize * 0.12 * scale
                        local cx, cy = px, py - game.tileSize * 0.22 * scale
                        love.graphics.polygon("fill",
                            cx - crownSize, cy,
                            cx, cy - crownSize,
                            cx + crownSize, cy
                        )

                        -- Outline for clarity
                        love.graphics.setColor(0, 0, 0)
                        love.graphics.polygon("line",
                            cx - crownSize, cy,
                            cx, cy - crownSize,
                            cx + crownSize, cy
                        )
                    end
                end
            end
        end
    end

    -- Draw dragged piece on top
    if game.dragPiece then
        local mx, my = love.mouse.getPosition()
        local p = game.board[game.dragPiece.row][game.dragPiece.col]
        if p then
            local scale = 1.05 + 0.03 * math.sin((love.timer.getTime() or 0) * 6)
            love.graphics.setColor(p.player == 1 and {0.8, 0.1, 0.1} or {0.9, 0.9, 0.9})
            love.graphics.circle("fill", mx, my, game.tileSize * 0.4 * scale)
            if p.king then
                local crownColor = (p.player == 1) and {1, 1, 0} or {0.8, 0.1, 0.1}
                love.graphics.setColor(crownColor)

                local crownSize = game.tileSize * 0.12 * scale
                love.graphics.polygon("fill",
                    mx - crownSize, my - game.tileSize * 0.22 * scale,
                    mx, my - game.tileSize * 0.22 * scale - crownSize,
                    mx + crownSize, my - game.tileSize * 0.22 * scale
                )

                love.graphics.setColor(0, 0, 0)
                love.graphics.polygon("line",
                    mx - crownSize, my - game.tileSize * 0.22 * scale,
                    mx, my - game.tileSize * 0.22 * scale - crownSize,
                    mx + crownSize, my - game.tileSize * 0.22 * scale
                )
            end
        end
    end

    -- Draw legal move targets
    for _, m in ipairs(game.legalMoves or {}) do
        local tx = game.boardOffsetX + (m.toC - 0.5) * game.tileSize
        local ty = game.boardOffsetY + (m.toR - 0.5) * game.tileSize
        love.graphics.setColor(0, 1, 0, 0.5)
        love.graphics.circle("fill", tx, ty, game.tileSize * 0.15)
    end

    -- Highlight best move (updated at a throttled rate)
    local best = game.bestMove
    if best then
        local fromX = game.boardOffsetX + (best.fromC - 0.5) * game.tileSize
        local fromY = game.boardOffsetY + (best.fromR - 0.5) * game.tileSize
        local toX = game.boardOffsetX + (best.toC - 0.5) * game.tileSize
        local toY = game.boardOffsetY + (best.toR - 0.5) * game.tileSize

        love.graphics.setColor(1, 1, 0, 0.8)
        drawArrow(fromX, fromY, toX, toY)
    end

    -- Right-side menu (controls + move history)
    local menuX = game.boardOffsetX + game.boardSize * game.tileSize + 10
    local menuY = game.boardOffsetY
    local menuW = game.rightMenuWidth - 20
    local menuH = game.boardSize * game.tileSize

    love.graphics.setColor(0.12, 0.12, 0.12, 0.95)
    love.graphics.rectangle("fill", menuX, menuY, game.rightMenuWidth, menuH)

    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Mode: " .. game:getModeLabel(), menuX + 10, menuY + 10)
    love.graphics.print("Difficulty: " .. game:getDifficultyLabel(), menuX + 10, menuY + 30)
    love.graphics.print("[Space] Cycle Mode", menuX + 10, menuY + 50)
    love.graphics.print("[D] Cycle Difficulty", menuX + 10, menuY + 65)
    love.graphics.print("[P] Pause/Resume AI", menuX + 10, menuY + 80)
    love.graphics.print("[N] Toggle Network", menuX + 10, menuY + 95)
    love.graphics.print("[R] Reset Game", menuX + 10, menuY + 110)

    love.graphics.print("Turn: " .. game.turnCounter, menuX + 10, menuY + 130)
    love.graphics.print("AI Paused: " .. tostring(game.aiPaused), menuX + 10, menuY + 145)

    local networkY = menuY + 160
    love.graphics.print("Network: " .. (game.networked and "Connected" or "Off"), menuX + 10, networkY)

    local sideY = networkY
    if game.networked and game.localSide then
        sideY = networkY + 15
        love.graphics.print("You are: " .. (game.localSide == 1 and "Red" or "White"), menuX + 10, sideY)
    end

    -- Move history (below network status)
    local historyStartY = sideY + 20
    love.graphics.print("Move History", menuX + 10, historyStartY)
    for i = 1, math.min(#game.moveHistory, 8) do
        love.graphics.print(game.moveHistory[i], menuX + 10, historyStartY + 15 * i)
    end

    -- Game over overlay
    if game.gameOver then
        local msg = "Game Over: " .. (game.winner == 1 and "Red Wins" or "White Wins")
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf(msg, 0, love.graphics.getHeight() / 2 - 30, love.graphics.getWidth(), "center")

        if game.timeoutWinner then
            local timeoutMsg = "(Timeout) "
            if game.timeoutWinner == 0 then
                timeoutMsg = timeoutMsg .. "Tie"
            else
                timeoutMsg = timeoutMsg .. (game.timeoutWinner == 1 and "Red" or "White") .. " wins by position"
            end
            love.graphics.printf(timeoutMsg, 0, love.graphics.getHeight() / 2 - 5, love.graphics.getWidth(), "center")
        end

        love.graphics.printf("Press R to restart", 0, love.graphics.getHeight() / 2 + 20, love.graphics.getWidth(), "center")
    end
end

return Renderer
