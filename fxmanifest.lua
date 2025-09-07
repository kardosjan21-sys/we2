fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'anti_waterevade'
author 'you'
version '1.1.0'
description 'Anti waterevading with ox_lib UI and equipped-only scuba'

shared_scripts {
  '@ox_lib/init.lua',  -- ox_lib init
  'config.lua'
}

server_scripts {
'server/server.lua',
}

client_scripts {
'client/main.lua' 
}

dependencies {
'PolyZone',
'ox_lib', 
'qb-core'
}

