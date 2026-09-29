-- The value text on the bar. Health values are secret on this client: they
-- go straight into widget calls and are never compared or used in math.

local _, ns = ...
local Health = {}
ns.Health = Health

-- Set by the first failed enemy % call; enemy text stays hidden after that.
Health.percentError = nil

-- text: our FontString. friend: UnitIsFriend("player", unit).
function Health.Update(text, unit, friend)
    if friend then
        text:SetText("-" .. AbbreviateNumbers(UnitHealthMissing(unit)))
        text:SetAlpha(1)
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
