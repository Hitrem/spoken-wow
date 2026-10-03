setfenv(1, SpokenEnv)
Version = {}

local CLIENT_VERSION, BUILD, _, INTERFACE_VERSION = GetBuildInfo()

Version.Client                  = CLIENT_VERSION
Version.Build                   = BUILD
Version.Interface               = INTERFACE_VERSION or 0
Version.IsAnyLegacy             = WOW_PROJECT_ID == nil or nil
Version.IsLegacyVanilla         = Version.IsAnyLegacy and Version.Interface ==     0 or nil
Version.IsLegacyBurningCrusade  = Version.IsAnyLegacy and Version.Interface == 20400 or nil
Version.IsLegacyWrath           = Version.IsAnyLegacy and Version.Interface == 30300 or nil
Version.IsAnyRetail             = not Version.IsAnyLegacy or nil
Version.IsRetailVanilla         = Version.IsAnyRetail and WOW_PROJECT_ID == WOW_PROJECT_CLASSIC or nil
Version.IsRetailBurningCrusade  = Version.IsAnyRetail and WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC or nil
Version.IsRetailWrath           = Version.IsAnyRetail and WOW_PROJECT_ID == WOW_PROJECT_WRATH_CLASSIC or nil
Version.IsRetailMainline        = Version.IsAnyRetail and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE or nil
-- The "WoW Forever" beta client: vanilla content on the modern engine. Told apart by its
-- interface number alone (16001 for 1.60.1), never by WOW_PROJECT_ID: build 69913 answered
-- WOW_PROJECT_MAINLINE and 70170 answers a project of its own (18), and the next build may
-- answer something else again. Era stays at 115xx and Anniversary at 205xx, so any 1.6x and
-- later 1.x release of Forever lands in the band.
Version.IsCamelot               = Version.IsAnyRetail and Version.Interface >= 16000 and Version.Interface < 20000 or nil

function Version:IsBelowLegacyVersion(version)
    return self.IsAnyLegacy and self.Interface < version or nil
end
function Version:IsRetailOrAboveLegacyVersion(version)
    return self.IsAnyRetail or self.Interface >= version or nil
end
