---@class TreatmentItem
---@field injuries (InjuryKind|'down')[]
---@field consume boolean
---@field seconds integer
---@field anim { dict: string, clip: string, flag?: integer }
---@field charges? integer

---@class Bed
---@field label string
---@field coords? vector4 where a patient lies on the mattress, with heading
---@field exit? vector4 where a patient stands up beside the bed, with heading

---@class Hospital
---@field id string
---@field enabled boolean
---@field label string
---@field short string
---@field coords vector3
---@field blip { sprite: integer, color: integer, scale: number }
---@field respawn vector4
---@field doctor? { model: string, coords: vector4, scenario?: string }
---@field checkIn? vector3
---@field supplyStash? { id: string, label: string, coords: vector3 }
---@field wardrobe? vector3
---@field spawner? { coords: vector3, spawnCoords: vector4, vehicles: { model: string, label: string }[] }
---@field beds Bed[]

return {
    -- Job
    job = 'ambulance', -- cobalt_core job of the medics

    -- Going down and dying
    death = {
        bleedoutSeconds = 300, -- seconds a downed player can be saved before they die
        deadSeconds = 120, -- seconds dead before the player can respawn themselves
        autoRespawnSeconds = 600, -- seconds dead before the server respawns them at hospital
        selfRespawnFee = 200, -- dollars charged for a self respawn
        autoRespawnFee = 0, -- dollars charged for an automatic respawn
        requestEmsHoldMs = 3000, -- milliseconds to hold the call key to call EMS
        executedHpFloor = 50, -- health below which a downed player dies outright from more damage
        characterKill = false, -- true lets a dead player permanently delete their character with the characterKill key
        keys = { -- GTA control ids and the key labels shown on screen
            callEms = { control = 47, label = 'G' }, -- hold to call EMS while down
            respawn = { control = 38, label = 'E' }, -- respawn at hospital once dead long enough
            characterKill = { control = 23, label = 'F' }, -- delete the character while dead
        },
    },

    -- Downed state before death
    lastStand = {
        health = 150, -- health a downed player is held at
        idleAnim = { dict = 'combat@damage@writhe', clip = 'writhe_loop' }, -- animation while lying still
        crawlAnim = { dict = 'move_injured_ground', clip = 'front_loop' }, -- animation while crawling
        turnRate = 0.08, -- how fast a downed player turns while crawling
        allowedControls = { 1, 2, 245, 249 }, -- controls kept while down: look, chat and push-to-talk
    },

    -- Screen and sound effects while down or dead; sounds are cobalt_sound files
    effects = {
        volume = 0.8, -- 0.0 to 1.0
        sounds = { down = 'bleedout', dead = 'flatline' }, -- cobalt_sound files played on going down and on dying
        heartbeat = { sound = 'heartbeat', minVolume = 0.25, maxVolume = 0.9 }, -- heartbeat while down, louder as bleed-out nears (0.0 to 1.0)
        impact = 'DeathFailMPIn', -- screen effect flashed on going down
        lastStand = { -- look while down
            timecycle = 'REDMIST_blend', -- GTA timecycle modifier name; leave it out for none
            strength = 0.35, -- timecycle strength, 0.0 to 1.0
            shake = 'DRUNK_SHAKE', -- GTA camera shake name; leave it out for none
            shakeAmount = 0.35, -- camera shake intensity; 1.0 is the shake's full strength
        },
        dead = { -- look while dead
            postfx = 'DeathFailMPDark', -- GTA screen effect name; leave it out for none
            timecycle = 'rply_saturation_neg', -- GTA timecycle modifier name; leave it out for none
            strength = 1.0, -- timecycle strength, 0.0 to 1.0
        },
        knockedOut = { -- look while knocked out
            timecycle = 'hud_def_blur', -- GTA timecycle modifier name; leave it out for none
            strength = 1.0, -- timecycle strength, 0.0 to 1.0
            shake = 'DRUNK_SHAKE', -- GTA camera shake name; leave it out for none
            shakeAmount = 0.6, -- camera shake intensity; 1.0 is the shake's full strength
        },
    },

    -- Animation while dead
    deadAnim = { dict = 'dead', clip = 'dead_a' },

    -- Knockouts from melee and stun weapons instead of going down
    knockout = {
        seconds = 30, -- seconds knocked out
        weapons = { -- weapons that knock out
            [`WEAPON_UNARMED`] = true,
            [`WEAPON_BAT`] = true,
            [`WEAPON_GOLFCLUB`] = true,
            [`WEAPON_HAMMER`] = true,
            [`WEAPON_KNUCKLE`] = true,
            [`WEAPON_NIGHTSTICK`] = true,
            [`WEAPON_WRENCH`] = true,
            [`WEAPON_POOLCUE`] = true,
            [`WEAPON_CANDYCANE`] = true,
            [`WEAPON_SNOWBALL`] = true,
            [`WEAPON_STUNGUN`] = true,
            [`WEAPON_FLASHLIGHT`] = true,
        },
    },

    -- CPR on a downed player
    cpr = {
        windowSeconds = 30, -- seconds after one CPR before another can add time
        addsSeconds = 30, -- seconds added to the bleed-out timer per CPR
        seconds = 4, -- seconds each CPR takes
        anim = { -- animation the medic plays
            dict = 'mini@cpr@char_a@cpr_str', -- animation dictionary
            clip = 'cpr_pumpchest', -- animation clip
            flag = 1, -- animation flag; 1 loops it
        },
    },

    -- Treatment items (cobalt_inventory names): injuries each treats, whether it is used up, seconds, animation, charges before it is used up
    ---@type table<string, TreatmentItem>
    treatment = {
        bandage = {
            injuries = { 'bleeding' }, -- injuries this item treats: 'bleeding', 'fracture', 'burn', 'severed' or 'down'
            consume = true, -- true uses up one item per treatment
            seconds = 6, -- how long the treatment takes, in seconds
            anim = { dict = 'amb@medic@standing@kneel@base', clip = 'base', flag = 1 }, -- animation the medic plays
        },
        splint = {
            injuries = { 'fracture' },
            consume = true,
            seconds = 8,
            anim = { dict = 'amb@medic@standing@kneel@base', clip = 'base', flag = 1 },
        },
        burn_dressing = {
            injuries = { 'burn' },
            consume = true,
            seconds = 6,
            anim = { dict = 'amb@medic@standing@kneel@base', clip = 'base', flag = 1 },
        },
        tourniquet = {
            injuries = { 'bleeding', 'severed' },
            consume = true,
            seconds = 5,
            anim = { dict = 'amb@medic@standing@kneel@base', clip = 'base', flag = 1 },
        },
        defibrillator = {
            injuries = { 'down' },
            consume = false,
            charges = 5, -- uses before the item is used up, for items that set consume = false
            seconds = 8,
            anim = { dict = 'mini@cpr@char_a@cpr_str', clip = 'cpr_pumpchest', flag = 49 },
        },
    },

    -- Body parts injuries are tracked on
    bodyParts = { 'head', 'torso', 'left_arm', 'right_arm', 'left_leg', 'right_leg' },

    -- Hospitals: blip, respawn point, check-in doctor, supply stash, wardrobe, vehicle spawner and beds
    ---@type Hospital[]
    hospitals = {
        {
            id = 'pillbox', -- unique id that beds and check-ins refer to
            enabled = true, -- false leaves the hospital out: no blip, no respawns, no check-in, no beds
            label = 'Pillbox Hill Medical', -- full name on the blip and in menus
            short = 'Pillbox Hill', -- short name in notifications
            coords = vec3(298.62, -584.83, 43.27), -- blip position
            blip = { sprite = 61, color = 1, scale = 1.0 }, -- blip sprite id, colour id and size
            respawn = vec4(304.45, -600.40, 43.28, 245.0), -- where a patient wakes up after respawning here, with heading
            doctor = { -- check-in ped; leave out for no ped
                model = 's_m_m_doctor_01', -- ped model
                coords = vec4(306.16, -597.48, 43.29, 19.5), -- behind the front reception counter facing the entrance; z is 1 meter above the floor
                scenario = 'WORLD_HUMAN_CLIPBOARD', -- scenario the ped plays
            },
            checkIn = vec3(305.57, -595.84, 43.29), -- in front of the reception counter, where players check in; defaults to the doctor's position
            supplyStash = { -- medics' supply stash
                id = 'pillbox_supplies', -- cobalt_inventory stash id
                label = 'Pillbox Medical Supplies', -- stash title
                coords = vec3(307.42, -601.58, 43.28), -- where medics open it
            },
            wardrobe = vec3(310.56, -598.14, 43.28), -- where medics change into uniform
            spawner = { -- work vehicle garage
                coords = vec3(294.55, -603.16, 42.10), -- where medics open the garage
                spawnCoords = vec4(297.79, -603.61, 43.18, 70.0), -- where the vehicle appears, with heading
                vehicles = { -- vehicles on offer: model name and menu label
                    { model = 'ambulance', label = 'Ambulance' },
                    { model = 'lguard', label = 'Lifeguard' },
                },
            },
            beds = { -- treatment beds in the hospital_map interior; coords is the lie-down point on the mattress, exit the stand-up point beside the bed; a bed without both stays empty and doesn't count on the MDT
                { label = 'Bed 1', coords = vec4(349.69, -583.61, 43.02, 160.0), exit = vec4(350.67, -584.29, 43.32, 250.0) }, -- main ward, north row
                { label = 'Bed 2', coords = vec4(353.24, -584.69, 43.11, 160.0), exit = vec4(354.22, -585.36, 43.32, 250.0) }, -- main ward, north row
                { label = 'Bed 3', coords = vec4(356.74, -585.94, 43.11, 160.0), exit = vec4(355.55, -585.82, 43.32, 70.0) }, -- main ward, north row
                { label = 'Bed 4', coords = vec4(360.42, -587.03, 43.02, 160.0), exit = vec4(359.23, -586.92, 43.32, 70.0) }, -- main ward, north row
                { label = 'Bed 5', coords = vec4(346.91, -590.64, 43.11, 340.0), exit = vec4(345.93, -589.96, 43.32, 70.0) }, -- main ward, south row
                { label = 'Bed 6', coords = vec4(350.72, -591.76, 43.11, 340.0), exit = vec4(351.91, -591.87, 43.32, 250.0) }, -- main ward, south row
                { label = 'Bed 7', coords = vec4(354.23, -592.68, 43.11, 340.0), exit = vec4(355.42, -592.79, 43.32, 250.0) }, -- main ward, south row
                { label = 'Bed 8', coords = vec4(357.39, -594.36, 43.11, 340.0), exit = vec4(358.57, -594.48, 43.32, 250.0) }, -- main ward, south row
                { label = 'Bed 9', coords = vec4(344.70, -581.05, 43.02, 250.0), exit = vec4(344.59, -582.23, 43.32, 160.0) }, -- main ward, west end
                { label = 'Bed 10', coords = vec4(333.98, -578.44, 43.01, 250.0), exit = vec4(333.87, -579.62, 43.32, 160.0) }, -- side ward, east wall
                { label = 'Bed 11', coords = vec4(326.91, -576.34, 43.03, 160.0), exit = vec4(325.72, -576.23, 43.32, 70.0) }, -- side ward
                { label = 'Bed 12', coords = vec4(323.71, -575.18, 43.03, 160.0), exit = vec4(324.69, -575.86, 43.32, 250.0) }, -- side ward
            },
        },
        {
            id = 'sandy',
            enabled = false,
            label = 'Sandy Shores Medical',
            short = 'Sandy Shores',
            coords = vec3(1839.44, 3672.71, 34.28),
            blip = { sprite = 61, color = 1, scale = 0.8 },
            respawn = vec4(1836.52, 3669.84, 34.28, 210.0),
            beds = { { label = 'Bed 1' }, { label = 'Bed 2' }, { label = 'Bed 3' }, { label = 'Bed 4' } },
        },
        {
            id = 'paleto',
            enabled = false,
            label = 'Paleto Bay Care Center',
            short = 'Paleto Bay',
            coords = vec3(-247.76, 6331.23, 32.43),
            blip = { sprite = 61, color = 1, scale = 0.8 },
            respawn = vec4(-251.09, 6334.19, 32.43, 225.0),
            beds = { { label = 'Bed 1' }, { label = 'Bed 2' }, { label = 'Bed 3' }, { label = 'Bed 4' } },
        },
    },

    -- Animation for a patient lying in a bed
    bedAnim = { dict = 'anim@gangops@morgue@table@', clip = 'body_search', flag = 1 },

    -- Self check-in at a hospital desk, which puts the player in a free bed and treats them
    checkIn = {
        fee = 150, -- dollars charged for treatment in a bed
        disableWhenEmsOnDuty = true, -- true closes check-in while enough EMS are on duty, so players call a medic instead
        minEmsOnDuty = 1, -- on-duty EMS count that closes check-in when disableWhenEmsOnDuty is true
        checkInSeconds = 3, -- seconds of the cancelable check-in progress bar at the desk
        treatmentSeconds = 15, -- seconds the patient spends treated in a bed before getting up healed
        key = { control = 74, label = 'H' }, -- GTA control id and key label to check in while down or dead at the desk
    },

    -- EMS MDT tablet
    mdt = {
        tablet = { -- animation and prop while it is open
            dict = 'amb@code_human_in_bus_passenger_idles@female@tablet@base', -- animation dictionary
            clip = 'base', -- animation clip
            flag = 49, -- animation flag; 49 loops on the upper body so the player can walk
            prop = {
                model = `prop_cs_tablet`, -- prop model
                bone = 60309, -- ped bone id the prop attaches to
                offset = vec3(0.03, 0.002, -0.0), -- attach offset in meters
                rotation = vec3(10.0, 160.0, 0.0), -- attach rotation in degrees
            },
        },
        lockedRank = 'EMT', -- rank named on a locked MDT feature when no grade has its permission
        invoiceDays = 7, -- days a patient has to pay an invoice, 1 to 365
        prescriptionDays = 30, -- default days a prescription stays valid
        invoiceLimits = { -- caps on one invoice: line count, dollars per line, dollars in total
            lines = 20, -- most lines on one invoice
            lineAmount = 5000, -- most dollars on one line
            total = 25000, -- most dollars on one invoice
        },
    },

    -- EMS dispatch
    dispatch = {
        popupSeconds = 20, -- seconds a call popup stays on screen
        respondKey = 'E', -- default key to respond
        waypointKey = 'K', -- default key to set a waypoint to the call while its alert shows; players can rebind it in GTA settings
    },

    -- Training: reports a trainee files before they count as trained
    training = { reports = 10 },

    -- Job grades shown as doctors and as trainees on the roster
    doctorGrades = { [3] = true, [4] = true }, -- grade levels marked as doctors on the roster
    traineeGrades = { [0] = true }, -- grade levels marked as trainees on the roster, who see their training progress on the MDT dashboard

    -- Certifications a boss can grant on the roster, stored in the character's metadata.certifications.<job>
    certifications = { 'life', 'flight', 'fto' }, -- ids; each needs a certifications.<id> name in locales/en.json

    -- Starting treatment and fee catalogue on the MDT; bosses edit it in game
    defaultTreatments = {
        {
            name = 'Bleeding control',
            category = 'injury',
            treats = { 'bleeding' },
            item = 'bandage',
            price = 120,
            seconds = 6,
        },
        {
            name = 'Gunshot wound care',
            category = 'injury',
            treats = { 'bleeding', 'severed' },
            item = 'tourniquet',
            price = 600,
            seconds = 5,
        },
        {
            name = 'Splint a fracture',
            category = 'injury',
            treats = { 'fracture' },
            item = 'splint',
            price = 150,
            seconds = 8,
        },
        {
            name = 'Burn dressing',
            category = 'injury',
            treats = { 'burn' },
            item = 'burn_dressing',
            price = 180,
            seconds = 6,
        },
        {
            name = 'Defibrillator revive',
            category = 'procedure',
            treats = { 'down' },
            item = 'defibrillator',
            price = 300,
            seconds = 8,
        },
        { name = 'CPR', category = 'procedure', treats = { 'down' }, price = 0, seconds = 4 },
        { name = 'Morphine 10 mg, IV', category = 'medication', treats = {}, price = 50, seconds = 0 },
        { name = 'Saline 500 ml', category = 'medication', treats = {}, price = 30, seconds = 0 },
        { name = 'Paracetamol 1 g', category = 'medication', treats = {}, price = 20, seconds = 0 },
        { name = 'Ambulance transport', category = 'fee', treats = {}, price = 250, seconds = 0 },
        { name = 'Hospital check-in', category = 'fee', treats = {}, price = 150, seconds = 0 },
        { name = 'Hospital respawn', category = 'fee', treats = {}, price = 200, seconds = 0 },
    },

    -- Starting MDT permissions per job grade; bosses edit them in game
    rankDefaults = {
        [0] = { writeReports = true, useDefib = true },
        [1] = { writeReports = true, useDefib = true, editPatients = true, sendInvoices = true },
        [2] = {
            writeReports = true,
            useDefib = true,
            editPatients = true,
            sendInvoices = true,
            writePrescriptions = true,
            editOtherReports = true,
            voidInvoices = true,
        },
        [3] = {
            writeReports = true,
            useDefib = true,
            editPatients = true,
            sendInvoices = true,
            writePrescriptions = true,
            prescribeControlled = true,
            editOtherReports = true,
            voidInvoices = true,
            shareReports = true,
        },
    },

    -- Starting report templates on the MDT
    defaultTemplates = {
        {
            name = 'Gunshot wound',
            narrative = [[Found [conscious or unresponsive] at [location], [time].
Wound: [entry site], [exit site or none].
Blood loss: [none, moderate, severe].

Treatment on scene: [tourniquet, gauze, splint].
Medications: [drug, dose, route].

Handed to: [hospital and doctor], or treated and released.]],
        },
        {
            name = 'Vehicle crash',
            narrative = [[Called to a [number]-vehicle crash at [location].
Patient was the [driver or passenger], [belted or unbelted].

Injuries: [details].
Treatment: [details].

Handed to: [hospital and doctor], or treated and released.]],
        },
        {
            name = 'Overdose',
            narrative = [[Found [conscious or unresponsive] at [location], [time].
Substance: [drug, if known].
Naloxone: [dose and response].

Handed to: [hospital and doctor], or treated and released.]],
        },
        {
            name = 'Death on scene',
            narrative = [[Pronounced dead at [time] at [location].
Cause: [cause].
Next of kin: [informed or not].]],
        },
    },

    -- Starting department settings: percent of each paid bill to the filing medic, and whether police can read EMS reports
    defaultSettings = { medicShare = 20, shareWithPolice = false },

}
