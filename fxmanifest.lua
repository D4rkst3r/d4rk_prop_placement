fx_version 'cerulean'
game 'gta5'

name 'prop_placement'
description 'Modulares Prop Placement System – ox_lib / ox_inventory / ox_target'
version '1.0.0'
author 'D4rkst3r'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
    'shared/props.lua', -- Props hier bearbeiten
}

client_scripts {
    'client/placement.lua',
    'client/main.lua',
    'client/inventory.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/logger.lua',
    'server/main.lua',
}

-- FIX #9: data/items.lua entfernt – wird nie von FiveM ausgeliefert/verwendet.
-- Items werden automatisch via exports.ox_inventory:Items() in server/main.lua registriert.
-- Icons fuer ox_inventory (512x512 PNG, Name = item_name.png)
files {
    'web/images/*.png',
}

lua54 'yes'

dependencies {
    'ox_lib',
    'ox_inventory',
    'ox_target',
    'oxmysql',
}
