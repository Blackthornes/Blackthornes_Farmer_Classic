-- A mob row leaves its kind empty to keep each row's table small, and
-- DB.KindOf reads it back as "mob". Every reader must see the same kinds.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("kindof")

local ns = env.Load()
local DB = ns.DB

local stored, unknown, rows, mobs = 0, 0, 0, 0
for _, item in pairs(DB.items) do
    for _, source in ipairs(item.sources or {}) do
        rows = rows + 1
        if source.kind == "mob" then stored = stored + 1 end
        local kind = DB.KindOf(source)
        if kind == "mob" then mobs = mobs + 1 end
        if not DB.KIND_LABEL[kind] then unknown = unknown + 1 end
    end
end

suite.check("the data has rows", rows > 0, rows)
suite.check("most rows are mobs", mobs > 0, mobs)
suite.check("no row stores the word mob", stored == 0, stored)
suite.check("every row reads a known kind", unknown == 0, unknown)

suite.check("an empty row reads as a mob", DB.KindOf({}) == "mob")
suite.check("nothing reads as a mob", DB.KindOf(nil) == "mob")
suite.check("a skinning row keeps its kind", DB.KindOf({ kind = "skinning" }) == "skinning")
suite.check("the label for none is a mob's", DB:KindLabel(nil) == DB:KindLabel("mob"))
suite.check("the tag for none is a mob's", DB:KindTag(nil) == DB:KindTag("mob"))

-- A row added as a mob comes out empty, and one added as skinning stays so.
local item = DB:RegisterItem({ name = "Kind Test Item", category = "Cloth" })
DB:AddSource(item or "Kind Test Item", { kind = "mob", name = "Kind Mob", zone = "Durotar", minLevel = 1, maxLevel = 2 })
DB:AddSource(item or "Kind Test Item", { kind = "skinning", name = "Kind Beast", zone = "Durotar", minLevel = 1, maxLevel = 2 })
local added = DB:GetItem("Kind Test Item")
local mobRow, skinRow
for _, source in ipairs(added and added.sources or {}) do
    if source.name == "Kind Mob" then mobRow = source end
    if source.name == "Kind Beast" then skinRow = source end
end
suite.check("a mob row is stored without a kind", mobRow and mobRow.kind == nil)
suite.check("and reads as a mob", mobRow and DB.KindOf(mobRow) == "mob")
suite.check("a skinning row is stored as skinning", skinRow and skinRow.kind == "skinning")
suite.check("its item is marked as skinned", added and added.fromSkinning == true)

suite.done()
