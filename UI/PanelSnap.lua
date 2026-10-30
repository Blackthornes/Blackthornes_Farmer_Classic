--------------------------------------------------------------------------------
-- UI/PanelSnap.lua
--
-- Kills & Loot, Goals and Where to Farm snap together into one column (the
-- owner, 2026-10-29, on unless unticked). Drop the goals panel near the
-- bottom edge of Kills & Loot, or Kills & Loot so its bottom sits near the
-- goals panel's top, and the goals panel hangs under it again (GoalsUI:Dock),
-- following it when it moves. Drop Where to Farm near the goals panel's
-- bottom edge and it opens under it from then on (`goalSpotsUnder`); dragged
-- away, it opens beside it as before. Each panel still folds and closes.
-- Never in a fight. Saved, account wide, never renamed: `snapPanels` (on
-- unless false) and `goalSpotsUnder`.
--------------------------------------------------------------------------------

local _, ns = ...

local PanelSnap = ns.NewModule("PanelSnap")

-- How close, in screen pixels, an edge must be dropped to snap.
PanelSnap.DISTANCE = 24

function PanelSnap:IsOn()
    return not (ns.db and ns.db.snapPanels == false)
end

function PanelSnap:SetOn(on)
    if not ns.db then return end
    ns.db.snapPanels = on and true or false
end

function PanelSnap.Fighting()
    return InCombatLockdown and InCombatLockdown() and true or false
end

--- A frame's left, right, top and bottom in screen pixels, or nil when the
--- client will not say (a frame not yet placed, a secret value).
function PanelSnap.Edges(frame)
    if not frame then return nil end
    local ok, left, right, top, bottom = pcall(function()
        local scale = frame:GetEffectiveScale() or 1
        local l, t = frame:GetLeft(), frame:GetTop()
        local w, h = frame:GetWidth(), frame:GetHeight()
        if type(l) ~= "number" or type(t) ~= "number" then return nil end
        w, h = tonumber(w) or 0, tonumber(h) or 0
        return l * scale, (l + w) * scale, t * scale, (t - h) * scale
    end)
    if ok and type(left) == "number" then return left, right, top, bottom end
end

--- True when `lower` was dropped with its top near `upper`'s bottom edge
--- and the two overlap side to side.
function PanelSnap.Near(lower, upper)
    local l1, r1, t1 = PanelSnap.Edges(lower)
    local l2, r2, _, b2 = PanelSnap.Edges(upper)
    if not (l1 and l2) then return false end
    if math.abs(t1 - b2) > PanelSnap.DISTANCE then return false end
    return l1 < r2 and r1 > l2
end

local function Shown(frame)
    return frame and frame.IsShown and frame:IsShown()
end

--- The goals panel was dropped: under Kills & Loot, it hangs there again.
function PanelSnap:GoalsDropped()
    if not self:IsOn() or self.Fighting() then return false end
    local goals = ns.GoalsUI
    local tracker = ns.TrackerUI and ns.TrackerUI.frame
    if not (goals and Shown(goals.frame) and Shown(tracker)) then return false end
    if not PanelSnap.Near(goals.frame, tracker) then return false end
    goals:Dock()
    return true
end

--- Kills & Loot was dropped: with its bottom near a loose goals panel's
--- top, the goals panel hangs under it.
function PanelSnap:TrackerDropped()
    if not self:IsOn() or self.Fighting() then return false end
    local goals = ns.GoalsUI
    local tracker = ns.TrackerUI and ns.TrackerUI.frame
    if not (goals and Shown(goals.frame) and Shown(tracker) and ns.db.goalsX) then return false end
    if not PanelSnap.Near(goals.frame, tracker) then return false end
    goals:Dock()
    return true
end

--- Where to Farm was dropped: near the goals panel's bottom, it opens
--- under it from now on; anywhere else, beside it as before.
function PanelSnap:SpotsDropped(panel)
    if not ns.db or self.Fighting() then return false end
    local goals = ns.GoalsUI and ns.GoalsUI.frame
    local under = self:IsOn() and Shown(goals) and PanelSnap.Near(panel, goals) or false
    ns.db.goalSpotsUnder = under or nil
    return under
end

--- Whether Where to Farm hangs under the goals panel.
function PanelSnap:SpotsUnder()
    return self:IsOn() and ns.db and ns.db.goalSpotsUnder and true or false
end
