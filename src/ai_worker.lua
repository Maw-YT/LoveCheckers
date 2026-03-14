-- This file runs in a separate thread via love.thread.
-- It receives board/difficulty jobs on a channel and computes the best move using the existing AI logic.

local AI = require("src.ai")

local jobChannel = love.thread.getChannel("lovecheckers_ai_job")
local resultChannel = love.thread.getChannel("lovecheckers_ai_result")

while true do
    local job = jobChannel:demand() -- blocks until a job is available
    if job and job.quit then
        break
    end

    if job then
        local best = AI.getBestMove(job.board, job.player, job.difficulty, job.recentMoves)
        resultChannel:push({jobId = job.jobId, best = best})
    end
end
