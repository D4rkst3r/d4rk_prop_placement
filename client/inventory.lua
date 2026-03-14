--[[
    prop_placement – client/inventory.lua
    Optionaler Inventar-Keybind – nur aktiv wenn Config.UseBuiltinInventoryKey = true
    → In shared/config.lua auf false setzen wenn der Server ein eigenes Inventar-System hat!
]]

if not Config.UseBuiltinInventoryKey then return end

RegisterKeyMapping('openinventory', 'Inventar öffnen', 'keyboard', 'TAB')

RegisterCommand('openinventory', function()
    if IsCurrentlyPlacing() then return end
    exports.ox_inventory:openInventory()
end, false)
