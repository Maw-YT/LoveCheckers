local Sounds = {
    move = {},
    capture = {},
    promote = nil,
    enabled = true,

    -- Track last played indices to reduce repeated sounds
    lastMoveIndex = nil,
    lastCaptureIndex = nil,
}

local function playWithRandomPitch(source)
    -- Use a subtle random pitch shift to make repeated sounds feel less repetitive.
    -- LÖVE expects 1.0 as normal pitch.
    local pitch = 0.95 + math.random() * 0.1
    source:setPitch(pitch)
    source:stop()
    source:play()
end

local function playRandomFromList(list, lastIndex)
    if #list == 0 then
        return nil
    end

    local idx
    if #list == 1 then
        idx = 1
    else
        -- Try to avoid repeating the same sound twice in a row
        repeat
            idx = math.random(1, #list)
        until idx ~= lastIndex
    end

    playWithRandomPitch(list[idx])
    return idx
end

function Sounds:init()
    -- Preload sound effects
    self.move = {
        love.audio.newSource("assets/sounds/piece_move.mp3", "static"),
        love.audio.newSource("assets/sounds/piece_move2.mp3", "static"),
    }

    self.capture = {
        love.audio.newSource("assets/sounds/piece_capture.mp3", "static"),
        love.audio.newSource("assets/sounds/piece_capture2.mp3", "static"),
    }

    self.promote = love.audio.newSource("assets/sounds/piece_promotion.mp3", "static")
end

function Sounds:playMove()
    if not self.enabled or #self.move == 0 then
        return
    end
    self.lastMoveIndex = playRandomFromList(self.move, self.lastMoveIndex)
end

function Sounds:playCapture()
    if not self.enabled or #self.capture == 0 then
        return
    end
    self.lastCaptureIndex = playRandomFromList(self.capture, self.lastCaptureIndex)
end

function Sounds:playPromotion()
    if not self.enabled or not self.promote then
        return
    end
    playWithRandomPitch(self.promote)
end

function Sounds:setEnabled(enabled)
    self.enabled = enabled
end

return Sounds
