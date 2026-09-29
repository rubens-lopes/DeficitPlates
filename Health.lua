-- The value text on the bar. Health values are secret on this client: they
-- go straight into widget calls and are never compared or used in math.

local _, ns = ...
local Health = {}
ns.Health = Health

-- Set by the first failed enemy % call; enemy text stays hidden after that.
Health.percentError = nil

local fullHealthCurve

-- 1 below full health, 0 at full, so SetAlpha hides "-0" on healthy friends.
local function FullHealthCurve()
    if not fullHealthCurve then
        fullHealthCurve = C_CurveUtil.CreateCurve()
        fullHealthCurve:AddPoint(0, 1)
        fullHealthCurve:AddPoint(0.999, 1)
        fullHealthCurve:AddPoint(1, 0)
    end
    return fullHealthCurve
end

-- text: our FontString. friend: UnitIsFriend("player", unit).
function Health.Update(text, unit, friend)
    if friend then
        text:SetText("-" .. AbbreviateNumbers(UnitHealthMissing(unit)))
        text:SetAlpha(UnitHealthPercent(unit, false, FullHealthCurve()))
        return
    end
    if Health.percentError then
        text:SetAlpha(0)
        return
    end
    local ok, err = pcall(function()
        text:SetFormattedText("%d%%", UnitHealthPercent(unit, false, CurveConstants.ScaleTo100))
    end)
    if ok then
        text:SetAlpha(1)
        return
    end
    Health.percentError = tostring(err)
    text:SetAlpha(0)
    error(err, 0)
end
