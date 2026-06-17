local merge = require("dipher.render.merge")

-- a default-style model: ours/theirs slabs, no base. result carries the markers
local function model()
    return {
        path = "f.txt",
        root = "/r",
        ours_text = "a\nOURS\nc\n",
        base_text = "a\nb\nc\n",
        theirs_text = "a\nTHEIRS\nc\n",
        result_text = "a\n<<<<<<< HEAD\nOURS\n=======\nTHEIRS\n>>>>>>> br\nc\n",
        regions = {
            {
                index = 1,
                result_start = 2,
                result_end = 6,
                ours = { "OURS" },
                theirs = { "THEIRS" },
            },
        },
    }
end

local function by_side(result, side)
    for _, c in ipairs(result.columns) do
        if c.side == side then
            return c
        end
    end
end

describe("render.merge (default layout)", function()
    it("emits ours / theirs / result, result last", function()
        local r = merge.render(model(), { layout = "default" })
        assert.are.equal(3, #r.columns)
        assert.are.equal("ours", r.columns[1].side)
        assert.are.equal("theirs", r.columns[2].side)
        assert.are.equal("result", r.columns[3].side)
        assert.are.equal(3, r.result_index)
    end)

    it("locates each slab inside its stage file", function()
        local r = merge.render(model(), {})
        assert.are.same({ { index = 1, first = 2, last = 2 } }, by_side(r, "ours").regions)
        assert.are.same({ { index = 1, first = 2, last = 2 } }, by_side(r, "theirs").regions)
    end)

    it("uses the exact marker span for the result region", function()
        local r = merge.render(model(), {})
        assert.are.same({ { index = 1, first = 2, last = 6 } }, by_side(r, "result").regions)
    end)

    it("hides the base column by default", function()
        assert.is_nil(by_side(merge.render(model(), {}), "base"))
    end)
end)

describe("render.merge (diff3_mixed layout)", function()
    it("adds the base column between ours and theirs and locates its slab", function()
        local m = model()
        m.regions[1].base = { "b" }
        local r = merge.render(m, { layout = "diff3_mixed" })
        assert.are.equal(4, #r.columns)
        assert.are.equal("base", r.columns[2].side)
        assert.are.same({ { index = 1, first = 2, last = 2 } }, by_side(r, "base").regions)
    end)
end)

describe("render.merge (slab location edges)", function()
    it("maps ordered duplicate slabs to ordered positions", function()
        local m = {
            ours_text = "X\nX\n",
            base_text = "",
            theirs_text = "Y\nY\n",
            result_text = "<<<<<<< a\nX\n=======\nY\n>>>>>>> b\n<<<<<<< a\nX\n=======\nY\n>>>>>>> b\n",
            regions = {
                { index = 1, result_start = 1, result_end = 5, ours = { "X" }, theirs = { "Y" } },
                { index = 2, result_start = 6, result_end = 10, ours = { "X" }, theirs = { "Y" } },
            },
        }
        local r = merge.render(m, {})
        assert.are.same(
            { { index = 1, first = 1, last = 1 }, { index = 2, first = 2, last = 2 } },
            by_side(r, "ours").regions
        )
    end)

    it("omits a region whose slab is not found (no wrong highlight)", function()
        local m = model()
        m.ours_text = "totally\nunrelated\n" -- the OURS slab isn't present
        local r = merge.render(m, {})
        assert.are.same({}, by_side(r, "ours").regions)
        -- theirs still resolves
        assert.are.equal(1, #by_side(r, "theirs").regions)
    end)

    it("omits an empty slab (deleted side)", function()
        local m = model()
        m.regions[1].ours = {}
        local r = merge.render(m, {})
        assert.are.same({}, by_side(r, "ours").regions)
    end)
end)
