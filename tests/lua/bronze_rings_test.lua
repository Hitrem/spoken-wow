-- Bronze Border on the round buttons: on Forever (1.60.1, interface 16001), every round button's
-- ring takes the bronze the small window wears while the setting is on, and goes back to its own
-- colour when it is turned off. Run with `make test-player`.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local stub = require("wow_client_stub")
local H = require("queue_helpers")
local Expect, Failures = H.Expecter(stub.print)
local SPOKEN = here .. "/../../addons/Spoken/"

stub.SetClient("16001"); stub.ResetSound(); stub.ResetTimers()
stub.LoadSpoken(SPOKEN)
local env = _G.SpokenEnv
env.Addon:Enable()
local frame = env.Addon.db.profile.Frame

-- What colour each ring was last given.
local function Recorded(button)
    local ring = button.ring
    ring.SetVertexColor = function(self, r, g, b) self.colour = string.format("%.2f %.2f %.2f", r, g, b) end
    return ring
end

frame.BronzeTint = true
local play = _G.Spoken:CreateRoundButton(UIParent, "play")
local picture = _G.Spoken:CreateRoundButton(UIParent, "icon", nil, [[Interface\Icons\INV_Misc_Book_11]])
local rings = { Recorded(play), Recorded(picture) }
env.Actions.RefreshRings()
Expect("on Forever, with Bronze Border on, a round button's ring is bronze", rings[1].colour, "0.95 0.68 0.35")
Expect("...a picture's ring too", rings[2].colour, "0.95 0.68 0.35")

frame.BronzeTint = false
env.PlayerFrame:RefreshConfig()
Expect("...its own colour again when the setting is turned off", rings[1].colour, "1.00 1.00 1.00")
Expect("...on every ring", rings[2].colour, "1.00 1.00 1.00")

frame.BronzeTint = true
env.PlayerFrame:RefreshConfig()
Expect("...and bronze again when it is turned back on, through the player's refresh", rings[1].colour, "0.95 0.68 0.35")

if Failures() > 0 then print(string.format("\n%d failure(s)", Failures())); os.exit(1) end
print("\nAll bronze ring tests passed")
