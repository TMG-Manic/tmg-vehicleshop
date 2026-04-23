fx_version 'cerulean'
game 'gta5'
lua54 'yes'
author 'TMG_Manic'
description 'Allows players to purchase vehicles and manage shops through a job'
version '1.0.0'

shared_script {
    'config.lua',
    '@tmg-core/shared/locale.lua',
    'locales/en.lua',
    'locales/*.lua'
}

client_scripts {
    '@PolyZone/client.lua',
    '@PolyZone/BoxZone.lua',
    '@PolyZone/EntityZone.lua',
    '@PolyZone/CircleZone.lua',
    '@PolyZone/ComboZone.lua',
    'client.lua'
}

server_scripts {
    'server.lua'
}
