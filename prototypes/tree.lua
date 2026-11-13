-- Save-compatible legacy cave tree prototype.
-- New cave frontiers no longer use trees as mineable cover: only rocks advance
-- exploration. Existing diggy-tree entities in old saves therefore behave like
-- ordinary Factorio trees (normal collision, deconstruction and harvest) and do
-- not participate in the digging system.
local tree = table.deepcopy(data.raw.tree["tree-02"])
tree.name = "diggy-tree"
tree.autoplace = nil

data:extend({ tree })
