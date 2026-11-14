fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_experimental_fxv2_oal 'yes'

name 'cobalt_ambulancejob'
author 'Project Cobalt'
description 'EMS: down and revive, treatment, carry, hospitals, check-in and the EMS MDT'
version '1.0.0'

dependencies {
    'cobalt_mysql',
    'ox_lib',
    'ox_target',
    'cobalt_core',
    'cobalt_inventory',
    'cobalt_banking',
    'cobalt_management',
    'cobalt_police',
}

shared_script '@ox_lib/init.lua'

ox_libs { 'locale' }

client_script 'client/init.lua'

server_scripts {
    '@cobalt_mysql/lib/MySQL.lua',
    '@cobalt_core/server/migrationgate.lua',
    'server/init.lua',
}

ui_page '_nui/build/index.html'

files {
    'config.lua',
    'locales/*.json',
    'shared/*.lua',
    'data/*.lua',
    'client/*.lua',
    '_nui/build/index.html',
    '_nui/build/**/*',
}
