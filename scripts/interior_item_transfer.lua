-- Move actual stacks through Factorio's native inventory transfer API. Counts
-- alone cannot represent equipment grids, ammo, tags, health or spoilage.
local transfer = {}

function transfer.move_count(source, destination, name, quality, count)
    if not (source and source.valid and destination and destination.valid)
        or source == destination or count <= 0 then return 0 end
    -- The normal case can stay entirely in the engine, including full/filtered
    -- destinations. Avoid Lua slot scans over the 3,000-slot Storehouses.
    if source.get_item_count { name = name, quality = quality } <= count then
        return destination.transfer_from_inventory(source, {
            name = name, quality = quality, comparator = "=",
        })
    end
    local _, first_index = source.find_item_stack { name = name, quality = quality }
    if not first_index then return 0 end
    local remaining = count
    for index = first_index, #source do
        if remaining <= 0 then break end
        local stack = source[index]
        if stack.valid_for_read and stack.name == name and stack.quality.name == quality
            and destination.can_insert(stack) then
            if stack.count <= remaining then
                remaining = remaining - destination.transfer_from_stack(stack)
            else
                -- Only the newly imported/pending count may move: the rest can
                -- be an earlier export of the same item. Native splitting and
                -- rollback preserve partial magazines and all stack metadata.
                local buffer = game.create_inventory(1)
                buffer[1].transfer_stack(stack, remaining)
                local moved = destination.transfer_from_stack(buffer[1])
                if buffer[1].valid_for_read then
                    assert(stack.transfer_stack(buffer[1]), "Interior item transfer rollback failed")
                end
                buffer.destroy()
                remaining = remaining - moved
            end
        end
    end
    return count - remaining
end

return transfer
