local oldData;
local oldTempData;
local tempConfig;
if (THI) then
    oldData = THI.Data;
    oldTempData = THI.TempData;
    tempConfig = THI.Config;
end
THI = RegisterMod("Reverie", 1);
THI.Version = {
    10,4,2
}

function THI:GetVersionString()
    local versionString = "";
    for i, version in pairs(self.Version) do
        if (i > 1) then
            versionString = versionString..".";
        end
        versionString = versionString..version;
    end
    return versionString;
end

THI.Data = oldData or {};
THI.TempData = oldTempData or {};
THI.Config = tempConfig or {};

-- Avoid Shader Crash.
THI:AddCallback(ModCallbacks.MC_POST_PLAYER_INIT, function()
    if #Isaac.FindByType(EntityType.ENTITY_PLAYER) == 0 then
        Isaac.ExecuteCommand("reloadshaders")
    end
end)

if (StageAPI) then
    StageAPI.UnregisterCallbacks(THI.Name);
end


local function IsMainmenu()
    return Game():GetLevel():GetStage() <= 0;
end


THI.Game = Game();
THI.SFXManager = SFXManager();
--THI.HUD = THI.Game:GetHUD();
--THI.Room = THI.Game:GetRoom();
--THI.Level = THI.Game:GetLevel();
--THI.ItemPool = THI.Game:GetItemPool();
--THI.Seeds = THI.Game:GetSeeds();

function THI.GetData(entity)
    local entityData = entity:GetData();
    entityData._TOUHOU_DATA = entityData._TOUHOU_DATA or {};
    return entityData._TOUHOU_DATA;
end



function THI.GetSaveGlobalData(data)
    local touhouData = data._TOUHOU_DATA or {
        Players = {},
        Global = {}
    };
    touhouData.Global = touhouData.Global or {};
    return touhouData.Global;
end


---- Save and Load -------------
function THI:GetGlobalData(temp) 
    if (temp) then
        return self.TempData;
    end
    return self.Data; 
end
function THI:SetGlobalData(data, temp) 
    if (temp) then
        self.TempData = data;
    else
        self.Data = data; 
    end
end

------------------------
-- Stage
------------------------

local Lib = include("cuerlib/main");
CuerLib = Lib;

THI.Lib = Lib;
THI.Require = Lib.Require;
local Require = THI.Require;

local getter = function(temp) return THI:GetGlobalData(temp) end;
local setter = function(data, temp) THI:SetGlobalData(data, temp) end
Lib:Register(THI, "_TOUHOU_DATA", getter, setter);

local Shared = {};
THI.Instruments = Require("scripts/shared/instruments");
THI.GapFloor = Require("scripts/shared/gap_floor");
Shared.Wheelchair = include("scripts/shared/wheelchair");
Shared.Wheelchair:Register(THI);
Shared.LightFairies = include("scripts/shared/light_fairies");
Shared.TearEffects = include("scripts/shared/tear_effects");
Shared.EntityTags = include("scripts/shared/entity_tags");
Shared.PathFinding = include("scripts/shared/path_finding")
Shared.SoftlockFix = include("scripts/shared/softlock_fix")
Shared.Database = include("scripts/shared/database")
Shared.Options = include("scripts/shared/options");
THI.Halos = Require("scripts/shared/halos");


THI.Shared = Shared;
function THI.Random(min, max)
    if (not max) then
        max = min;
        min = 0;
    end
    return Random() % (max - min) + min;
end 

function THI.RandomFloat(min, max)
    if (not max) then
        max = min;
        min = 0;
    end
    return Random() % ((max - min) * 1000) / 1000 + min;
end 



do -- Announcers.
    local Announcer = {}
    local Announcers = {};
    local PillAnnouncers = {};
    local QueuedAnnouncers = {};

    local AnnouncerEnabled = true;

    function Announcer.UpdateAnnouncer()
        local persistent = Lib.SaveAndLoad.ReadPersistentData();
        if (persistent.AnnouncerEnabled == false) then
            AnnouncerEnabled = false;
        end
    end
    Announcer.UpdateAnnouncer();

    function Announcer:PostGameStarted(isContinued)
        Announcer.UpdateAnnouncer()
    end
    THI:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, Announcer.PostGameStarted)
    local function PostUpdate(mod)
        for i = #QueuedAnnouncers, 1, -1 do
            local announcer = QueuedAnnouncers[i];
            if (announcer.Timeout < 0) then
                THI.SFXManager:Play(announcer.ID);
                table.remove(QueuedAnnouncers ,i);
            else
                announcer.Timeout = announcer.Timeout - 1;
            end
        end
    end
    THI:AddCallback(ModCallbacks.MC_POST_UPDATE, PostUpdate);

    local function PostGameStarted(mod, isContinued)
        for i = 1, #QueuedAnnouncers do
            QueuedAnnouncers[i] = nil;
        end
    end
    THI:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, PostGameStarted);

    local function PostUseCard(mod, card, player, flags)
        if (flags & UseFlag.USE_NOANNOUNCER <= 0 and THI.AnnouncerEnabled()) then
            local announcer = THI:GetAnnouncer(card);
            if (announcer) then
                local willRandomPlay = Random() % 2 == 1;
                local announcerMode = Options.AnnouncerVoiceMode;
                if (announcerMode == 2 or (announcerMode == 0 and willRandomPlay)) then
                    table.insert(QueuedAnnouncers, 1, {ID = announcer.ID, Timeout = announcer.Delay});
                end 
            end
        end
    end
    THI:AddCallback(ModCallbacks.MC_USE_CARD, PostUseCard)

    local function PostUsePill(mod, effect, player, flags)
        if (flags & UseFlag.USE_NOANNOUNCER <= 0 and THI.AnnouncerEnabled()) then
            local announcer = THI:GetPillAnnouncer(effect);
            if (announcer) then
                local announcerMode = Options.AnnouncerVoiceMode;
                local willRandomPlay = Random() % 2 == 1;
                if (announcerMode == 2 or (announcerMode == 0 and willRandomPlay)) then


                    local mega = false;
                    if (flags & UseFlag.USE_MIMIC <= 0) then
                        local itemPool = Game():GetItemPool();
                        local pillColor = player:GetPill(0);
                        local pillEffect = itemPool:GetPillEffect(pillColor, player);
                        if (pillEffect == effect) then
                            if (pillColor & PillColor.PILL_GIANT_FLAG > 0) then
                                mega = true;
                            end
                        end
                    end

                    local sound = announcer.ID;
                    if (mega) then
                        sound = announcer.MegaID or sound;
                    end
                    table.insert(QueuedAnnouncers, 1, {ID = sound, Timeout = announcer.Delay});
                end 
            end
        end
    end
    THI:AddCallback(ModCallbacks.MC_USE_PILL, PostUsePill)

    function THI.AnnouncerEnabled()
        return AnnouncerEnabled;
    end

    function THI.SetAnnouncerEnabled(value)
        local persistent = Lib.SaveAndLoad.ReadPersistentData();
        persistent.AnnouncerEnabled = value;
        AnnouncerEnabled = value;
        Lib.SaveAndLoad.WritePersistentData(persistent);
    end


    function THI:AddAnnouncer(id, sound, delay)
        delay = delay or 0;
        Announcers[id] = {ID = sound, Delay = delay};
    end
    function THI:GetAnnouncer(id)
        return Announcers[id];
    end
    

    function THI:AddPillAnnouncer(id, sound, megaSound, delay)
        delay = delay or 0;
        PillAnnouncers[id] = {ID = sound, MegaID = megaSound, Delay = delay};
    end
    function THI:GetPillAnnouncer(card)
        return PillAnnouncers[card];
    end

end

function ModEntity(name, dataName) 
    return Lib.ModComponents.ModEntity:New(name, dataName);
end


function ModItem(name, dataName) 
    return Lib.ModComponents.ModItem:New(name, dataName);
end

---- Trinkets
function ModTrinket(name, dataName) 
    return Lib.ModComponents.ModTrinket:New(name, dataName);
end

---- Player
function ModPlayer(name, tainted, dataName) 
    return Lib.ModComponents.ModPlayer:New(name, tainted, dataName);
end

function ModCard(name, dataName) 
    return Lib.ModComponents.ModCard:New(name, dataName);
end
function ModPill(name, dataName) 
    return Lib.ModComponents.ModPill:New(name, dataName);
end

function ModChallenge(name, dataName)
    return Lib.ModComponents.ModChallenge:New(name, dataName);
end





local teammeat10 = Font();
teammeat10:Load("font/teammeatfont10.fnt");
local teammeatExtended10 = Font();
teammeatExtended10:Load("font/teammeatfontextended10.fnt");
local lanapixel = Font();
lanapixel:Load("font/cjk/lanapixel.fnt");
local terminus8 = Font();
terminus8:Load("font/terminus8.fnt");
local pftempesta7 = Font();
pftempesta7:Load("font/pftempestasevencondensed.fnt");
THI.Fonts = {
    Teammeat10 = teammeat10,
    TeammeatExtended10 = teammeatExtended10,
    Lanapixel = lanapixel,
    Terminus8 = terminus8,
    PFTempesta7 = pftempesta7,
}
THI.Music = {
    UFO = Isaac.GetMusicIdByName("UFO"),
    REVERIE = Isaac.GetMusicIdByName("Reverie"),
}

THI.Sounds = {
    SOUND_FAIRY_HEAL = Isaac.GetSoundIdByName("Fairy Heal"),
    SOUND_TOUHOU_CHARGE = Isaac.GetSoundIdByName("Touhou Charge"),
    SOUND_TOUHOU_CHARGE_RELEASE = Isaac.GetSoundIdByName("Touhou Charge Release"),
    SOUND_TOUHOU_DESTROY = Isaac.GetSoundIdByName("Touhou Destroy"),
    SOUND_TOUHOU_DANMAKU = Isaac.GetSoundIdByName("Touhou Danmaku"),
    SOUND_TOUHOU_LASER = Isaac.GetSoundIdByName("Touhou Laser"),
    SOUND_TOUHOU_SPELL_CARD = Isaac.GetSoundIdByName("Touhou Spell Card"),
    SOUND_TOUHOU_BOON = Isaac.GetSoundIdByName("Touhou Boon"),
    SOUND_TOUHOU_KAGEROU_ROAR = Isaac.GetSoundIdByName("Touhou Kagerou Roar"),
    SOUND_NIMBLE_FABRIC = Isaac.GetSoundIdByName("Nimble Fabric"),
    SOUND_MIND_CONTROL = Isaac.GetSoundIdByName("Mind Control"),
    SOUND_MIND_WAVE = Isaac.GetSoundIdByName("Mind Wave"),
    SOUND_EXECUTE = Isaac.GetSoundIdByName("Execute"),
    SOUND_CENTIPEDE = Isaac.GetSoundIdByName("Centipede"),
    SOUND_HOOK_CATCH = Isaac.GetSoundIdByName("Hook Catch"),
    SOUND_UFO = Isaac.GetSoundIdByName("UFO"),
    SOUND_UFO_ALERT = Isaac.GetSoundIdByName("UFO Alert"),
    SOUND_FAULT = Isaac.GetSoundIdByName("Fault"),
    SOUND_RADAR = Isaac.GetSoundIdByName("Radar"),
    SOUND_SCIFI_MECH = Isaac.GetSoundIdByName("Scifi Mech"),
    SOUND_SCIFI_LASER = Isaac.GetSoundIdByName("Scifi Laser"),
    SOUND_NUCLEAR_ALERT = Isaac.GetSoundIdByName("Nuclear Alert"),
    SOUND_THUNDER_SHOCK = Isaac.GetSoundIdByName("Thunder Shock"),
    SOUND_SUMMONER_DEATH = Isaac.GetSoundIdByName("Summoner Death"),
    SOUND_MAGIC_IMPACT = Isaac.GetSoundIdByName("Magic Impact"),
    SOUND_CURSE_CAST = Isaac.GetSoundIdByName("Curse Cast"),
    SOUND_CURSE_FEARNESS = Isaac.GetSoundIdByName("Fearness Curse"),
    SOUND_REVIVE_SKELETON_CAST = Isaac.GetSoundIdByName("Revive Skeleton Cast"),
    SOUND_CORPSE_EXPLODE_CAST = Isaac.GetSoundIdByName("Corpse Explode Cast"),
    SOUND_CORPSE_EXPLODE = Isaac.GetSoundIdByName("Corpse Explode"),
    SOUND_BONE_CAST = Isaac.GetSoundIdByName("Bone Cast"),
    SOUND_DIABLO_IDENTIFY = Isaac.GetSoundIdByName("Diablo Identify"),
    SOUND_DIABLO_SCROLL = Isaac.GetSoundIdByName("Diablo Scroll"),
    SOUND_ROOSTER_CROW = Isaac.GetSoundIdByName("Rooster Crow"),
    SOUND_SOUL_OF_EIKA = Isaac.GetSoundIdByName("Soul of Eika"),
    SOUND_SOUL_OF_SATORI = Isaac.GetSoundIdByName("Soul of Satori"),
    SOUND_SOUL_OF_SEIJA = Isaac.GetSoundIdByName("Soul of Seija"),
    SOUND_SPIRIT_MIRROR = Isaac.GetSoundIdByName("Spirit Mirror"),
    SOUND_SITUATION_TWIST = Isaac.GetSoundIdByName("Situation Twist"),
    SOUND_PILL_OF_ULTRAMARINE_ORB = Isaac.GetSoundIdByName("Pill of Ultramarine Orb"),
    SOUND_MEGA_PILL_OF_ULTRAMARINE_ORB = Isaac.GetSoundIdByName("Mega Pill of Ultramarine Orb"),
    SOUND_HAMMER_80 = Isaac.GetSoundIdByName("Hammer 80"),
    SOUND_ROBOT_SMASH = Isaac.GetSoundIdByName("Robot Smash"),
    SOUND_EARTHQUAKE = Isaac.GetSoundIdByName("Earthquake"),
    SOUND_WILD_ROAR = Isaac.GetSoundIdByName("Wild Roar"),
    SOUND_WILD_BITE = Isaac.GetSoundIdByName("Wild Bite"),
    SOUND_PIANO_C4 = Isaac.GetSoundIdByName("Piano C4"),
    SOUND_MUSIC_BOX_C4 = Isaac.GetSoundIdByName("Music Box C4"),
    
}


THI.Players = {
    Eika = Require("scripts/players/eika"),
    EikaB = Require("scripts/players/eika_b"),
    Satori = Require("scripts/players/satori"),
    SatoriB = Require("scripts/players/satori_b"),
    Seija = Require("scripts/players/seija"),
    SeijaB = Require("scripts/players/seija_b"),
}
THI.Bosses = {
    TheAbandoned = Require("scripts/bosses/the_abandoned"),
    Necrospyder = Require("scripts/bosses/necrospyder"),
    TheCentipede = Require("scripts/bosses/the_centipede"),
    Pyroplume = Require("scripts/bosses/pyroplume"),
    TheSummoner = Require("scripts/bosses/the_summoner"),
    Devilcrow = Require("scripts/bosses/devilcrow"),
    Guppet = Require("scripts/bosses/guppet"),
    ReverieNote = Require("scripts/bosses/reverie_note")
}

THI.Cards = {
    SoulOfEika = Require("scripts/pockets/soul_of_eika"),
    SoulOfSatori = Require("scripts/pockets/soul_of_satori"),
    ASmallStone = Require("scripts/pockets/a_small_stone"),
    SpiritMirror = Require("scripts/pockets/spirit_mirror"),
    SoulOfSeija = Require("scripts/pockets/soul_of_seija"),
    SituationTwist = Require("scripts/pockets/situation_twist"),
}
THI.Pills = {
    PillOfUltramarineOrb = Require("scripts/pockets/pill_of_ultramarine_orb")
}
THI.Pickups = {
    SpringFairy = Require("scripts/pickups/spring_fairy"),
    StarseekerBall = ModEntity("Starseeker Ball", "StarseekerBall"),
    FoxsAdviceBottle = Require("scripts/pickups/foxs_advice_bottle"),
    SakeBottle = Require("scripts/pickups/sake_bottle"),
    ReverieMusicBox = Require("scripts/pickups/reverie_music_box"),
    RebechaIdle = Require("scripts/pickups/rebecha_idle"),
    FoodPickup = Require("scripts/pickups/food_pickup"),
}
THI.Knives = {
    HaniwaKnife = Require("scripts/knives/haniwa_knife"),
}
THI.Effects = {
    FairyEffect = Require("scripts/effects/fairy_effect"),
    FairyParticle = Require("scripts/effects/fairy_particle"),
    PlayerTrail = Require("scripts/effects/player_trail"),
    RabbitTrap = Require("scripts/effects/rabbit_trap"),
    TenguSpotlight = Require("scripts/effects/tengu_spotlight"),
    SpellCardLeaf = Require("scripts/effects/spell_card_leaf"),
    SpellCardWave = Require("scripts/effects/spell_card_wave"),
    PickupEffect = Require("scripts/effects/pickup_effect"),
    ExtendingArm = Require("scripts/effects/extending_arm"),
    Onbashira = Require("scripts/effects/onbashira"),
    HolyThunder = Require("scripts/effects/holy_thunder"),
    MagicCluster = Require("scripts/effects/magic_cluster"),
    MagicCircle = Require("scripts/effects/magic_circle"),
    MagicCircleFire = Require("scripts/effects/magic_circle_fire"),
    SummonerGhost = Require("scripts/effects/summoner_ghost"),
    MiracleMalletReplica = Require("scripts/effects/miracle_mallet_replica"),
    WildFangs = Require("scripts/effects/wild_fangs"),
    UnzanFace = Require("scripts/effects/unzan_face"),
    ReverieMusicPaper = Require("scripts/effects/reverie_music_paper"),
    ReverieNoteWave = Require("scripts/effects/reverie_note_wave"),
    ReverieProp = Require("scripts/effects/reverie_prop"),
    TinyMeteor = Require("scripts/effects/tiny_meteor"),
    SeijasShade = Require("scripts/effects/seijas_shade"),
    ItemSoul = Require("scripts/effects/item_soul"),
    RemainsFountain = Require("scripts/effects/remains_fountain"),
}
THI.Familiars = {
    Illusion = Require("scripts/familiars/illusion"),
    RobeFire = Require("scripts/familiars/robe_fire"),
    LeafShieldRing = Require("scripts/familiars/leaf_shield_ring"),
    IsaacGolem = Require("scripts/familiars/isaac_golem"),
    PsycheEye = Require("scripts/familiars/psyche_eye"),
    ScaringUmbrella = Require("scripts/familiars/scaring_umbrella"),
    SekibankiHead = Require("scripts/familiars/sekibanki_head"),
    ThunderDrum = Require("scripts/familiars/thunder_drum"),
    HellPlanets = Require("scripts/familiars/hell_planets"),
    SunnyFairy = Require("scripts/familiars/sunny_fairy"),
    LunarFairy = Require("scripts/familiars/lunar_fairy"),
    StarFairy = Require("scripts/familiars/star_fairy"),
    YoungNativeGod = Require("scripts/familiars/young_native_god"),
    DancerServant = Require("scripts/familiars/dancer_servant"),
    BackDoor = Require("scripts/familiars/back_door"),
    Unzan = Require("scripts/familiars/unzan"),
    Haniwa = Require("scripts/familiars/haniwa")
}
THI.Slots = {
    Trader = Require("scripts/slots/trader"),
}

THI.Monsters = {
    BloodBony = Require("scripts/monsters/blood_bony"),
    BonusUFO = Require("scripts/monsters/bonus_ufo"),
    EvilSpirit = Require("scripts/monsters/evil_spirit"),
    Immortal = Require("scripts/monsters/immortal"),
    Rebecha = Require("scripts/monsters/rebecha"),
}

THI.Rooms = {
    MovedShop = Require("scripts/rooms/moved_shop")
}

local Collectibles = {};

Collectibles.YinYangOrb = Require("scripts/items/protagonists/yin-yang_orb");
Collectibles.MarisasBroom = Require("scripts/items/protagonists/marisas_broom");
--TH6
Collectibles.DarkRibbon = Require("scripts/items/th6/dark_ribbon");
Collectibles.DYSSpring = Require("scripts/items/th6/spring_of_daiyousei");
Collectibles.DragonBadge = Require("scripts/items/th6/rainbow_dragon_badge");
Collectibles.Koakuma = Require("scripts/items/th6/koakuma_baby");
Collectibles.Grimoire = Require("scripts/items/th6/grimoire_of_patchouli");
Collectibles.MaidSuit = Require("scripts/items/th6/maid_suit");
Collectibles.VampireTooth = Require("scripts/items/th6/tooth_of_vampire");
Collectibles.Destruction = Require("scripts/items/th6/destruction");
Collectibles.DeletedErhu = Require("scripts/items/th6/deleted_erhu");
--TH7
Collectibles.FrozenSakura = Require("scripts/items/th7/frozen_sakura");
Collectibles.ChenBaby = Require("scripts/items/th7/chen_baby");
Collectibles.ShanghaiDoll = Require("scripts/items/th7/shanghai_doll");
Collectibles.MelancholicViolin = Require("scripts/items/th7/melancholic_violin");
Collectibles.ManiacTrumpet = Require("scripts/items/th7/maniac_trumpet");
Collectibles.IllusionaryKeyboard = Require("scripts/items/th7/illusionary_keyboard");
Collectibles.Roukanken = Require("scripts/items/th7/roukanken");
Collectibles.FanOfTheDead = Require("scripts/items/th7/fan_of_the_dead");
Collectibles.FriedTofu = Require("scripts/items/th7/fried_tofu");
Collectibles.OneOfNineTails = Require("scripts/items/th7/one_of_nine_tails");
Collectibles.Gap = Require("scripts/items/th7/the_gap");
-- Secret Sealing
Collectibles.Starseeker = Require("scripts/items/secret_sealing/starseeker");
Collectibles.Pathseeker = Require("scripts/items/secret_sealing/pathseeker");
-- TH7.5
Collectibles.GourdShroom = Require("scripts/items/th7-5/gourd_shroom");
-- TH8
Collectibles.JarOfFireflies = Require("scripts/items/th8/jar_of_fireflies");
Collectibles.SongOfNightbird = Require("scripts/items/th8/song_of_nightbird");
Collectibles.BookOfYears = Require("scripts/items/th8/book_of_years");
Collectibles.RabbitTrap = Require("scripts/items/th8/rabbit_trap");
Collectibles.Illusion = Require("scripts/items/th8/illusion");
Collectibles.PeerlessElixir = Require("scripts/items/th8/peerless_elixir");
Collectibles.DragonNeckJewel = Require("scripts/items/th8/dragon_neck_jewel");
Collectibles.RobeOfFirerat = Require("scripts/items/th8/robe_of_firerat");
Collectibles.JeweledBranch = Require("scripts/items/th8/jeweled_branch");
Collectibles.AshOfPhoenix = Require("scripts/items/th8/ash_of_phoenix");

-- TH9
Collectibles.TenguCamera = Require("scripts/items/th9/tengu_camera");
Collectibles.SunflowerPot = Require("scripts/items/th9/sunflower_pot");
Collectibles.ContinueArcade = Require("scripts/items/th9/continue_arcade");
Collectibles.RodOfRemorse = Require("scripts/items/th9/rod_of_remorse");

-- TH10
Collectibles.LeafShield = Require("scripts/items/th10/leaf_shield");
Collectibles.BakedSweetPotato = Require("scripts/items/th10/baked_sweet_potato");
Collectibles.BrokenAmulet = Require("scripts/items/th10/broken_amulet");
Collectibles.ExtendingArm = Require("scripts/items/th10/extending_arm");
Collectibles.WolfEye = Require("scripts/items/th10/wolf_eye");
Collectibles.Benediction = Require("scripts/items/th10/benediction");
Collectibles.Onbashira = Require("scripts/items/th10/onbashira");
Collectibles.YoungNativeGod = Require("scripts/items/th10/young_native_god");

-- TH10.5
Collectibles.Keystone = Require("scripts/items/th10-5/keystone");
Collectibles.AngelsRaiment = Require("scripts/items/th10-5/angels_raiment");

-- TH11
Collectibles.BucketOfWisps = Require("scripts/items/th11/bucket_of_wisps");
Collectibles.PlagueLord = Require("scripts/items/th11/plague_lord");
Collectibles.GreenEyedEnvy = Require("scripts/items/th11/green_eyed_envy");
Collectibles.OniHorn = Require("scripts/items/th11/oni_horn");
Collectibles.PsycheEye = Require("scripts/items/th11/psyche_eye");
Collectibles.GuppysCorpseCart = Require("scripts/items/th11/guppys_corpse_cart");
Collectibles.Technology666 = Require("scripts/items/th11/technology_666");
Collectibles.PsychoKnife = Require("scripts/items/th11/psycho_knife");
-- TH12
Collectibles.DowsingRods = Require("scripts/items/th12/dowsing_rods");
Collectibles.ScaringUmbrella = Require("scripts/items/th12/scaring_umbrella");
Collectibles.Unzan = Require("scripts/items/th12/unzan");
Collectibles.Pagota = Require("scripts/items/th12/bishamontens_pagota");
Collectibles.SorcerersScroll = Require("scripts/items/th12/sorcerers_scroll");
Collectibles.SaucerRemote = Require("scripts/items/th12/saucer_remote");

-- TH12.5
Collectibles.TenguCellphone = Require("scripts/items/th12-5/tengu_cellphone");
-- TH13
Collectibles.MountainEar = Require("scripts/items/th13/mountain_ear");
Collectibles.ZombieInfestation = Require("scripts/items/th13/zombie_infestation");
Collectibles.WarpingHairpin = Require("scripts/items/th13/warpping_hairpin");
Collectibles.HolyThunder = Require("scripts/items/th13/holy_thunder");
Collectibles.GeomanticDetector = Require("scripts/items/th13/geomantic_detector");
Collectibles.Lightbombs = Require("scripts/items/th13/lightbombs");
Collectibles.D2147483647 = Require("scripts/items/th13/d2147483647");
-- TH13.5
Collectibles.TheInfamies = Require("scripts/items/th13-5/the_infamies");
-- TH14
Collectibles.SekibankisHead = Require("scripts/items/th14/sekibankis_head");
Collectibles.WildFury = Require("scripts/items/th14/wild_fury");
Collectibles.ReverieMusic = Require("scripts/items/th14/reverie_music");
Collectibles.DFlip = Require("scripts/items/th14/d_flip");
Collectibles.MiracleMallet = Require("scripts/items/th14/miracle_mallet");
Collectibles.ThunderDrum = Require("scripts/items/th14/thunder_drum");
-- Collectibles.DualDivision = Require("scripts/items/th14/dual_division");
Collectibles.DSiphon = Require("scripts/items/th14/d_siphon");
-- TH14.3
Collectibles.NimbleFabric = Require("scripts/items/th14-3/nimble_fabric");
Collectibles.MiracleMalletReplica = Require("scripts/items/th14-3/miracle_mallet_replica");
-- TH14.5
Collectibles.RuneCape = Require("scripts/items/th14-5/rune_cape");
-- TH15
Collectibles.LunaticGun = Require("scripts/items/th15/lunatic_gun");
Collectibles.ViciousCurse = Require("scripts/items/th15/vicious_curse");
Collectibles.CarnivalHat = Require("scripts/items/th15/carnival_hat");
Collectibles.PureFury = Require("scripts/items/th15/pure_fury");
Collectibles.Hekate = Require("scripts/items/th15/hekate");
-- TH15.5
Collectibles.DadsShares = Require("scripts/items/th15-5/dads_shares");
Collectibles.MomsIOU = Require("scripts/items/th15-5/moms_iou");
-- TH16
Collectibles.YamanbasChopper = Require("scripts/items/th16/yamanbas_chopper");
Collectibles.GolemOfIsaac = Require("scripts/items/th16/golem_of_isaac");
Collectibles.DancerServants = Require("scripts/items/th16/dancer_servants")
Collectibles.BackDoor = Require("scripts/items/th16/back_door")
-- TH17
Collectibles.FetusBlood = Require("scripts/items/th17/fetus_blood");
Collectibles.CockcrowWings = Require("scripts/items/th17/cockcrow_wings");
Collectibles.KiketsuBlackmail = Require("scripts/items/th17/kiketsu_familys_blackmail");
Collectibles.CarvingTools = Require("scripts/items/th17/carving_tools");
Collectibles.BrutalHorseshoe = Require("scripts/items/th17/brutal_horseshoe");

-- TH17.5
Collectibles.Hunger = Require("scripts/items/th17-5/hunger");

Collectibles.DreamSoul = {Item = Isaac.GetItemIdByName("Dream Soul")};

-- TH18
Collectibles.GamblingD6 = Require("scripts/items/th18/gambling_d6");
Collectibles.YamawarosCrate = Require("scripts/items/th18/yamawaros_crate");
Collectibles.DelusionPipe = Require("scripts/items/th18/delusion_pipe");
Collectibles.SoulMagatama = Require("scripts/items/th18/soul_magatama");
Collectibles.FoxInTube = Require("scripts/items/th18/fox_in_tube");
Collectibles.DaitenguTelescope = Require("scripts/items/th18/daitengu_telescope");
Collectibles.ExchangeTicket = Require("scripts/items/th18/exchange_ticket");
Collectibles.CurseOfCentipede = Require("scripts/items/th18/curse_of_centipede");

-- Make resistance of player at the last.
Collectibles.BuddhasBowl = Require("scripts/items/th8/buddhas_bowl");
Collectibles.SwallowsShell = Require("scripts/items/th8/swallows_shell");


-- Printworks
Collectibles.IsaacsLastWills = Require("scripts/items/printworks/isaacs_last_wills");
Collectibles.SunnyFairy = Require("scripts/items/printworks/sunny_fairy");
Collectibles.LunarFairy = Require("scripts/items/printworks/lunar_fairy");
Collectibles.StarFairy = Require("scripts/items/printworks/star_fairy");
Collectibles.EmptyBook = Require("scripts/items/printworks/empty_book");
Collectibles.GeographicChain = Require("scripts/items/printworks/geographic_chain");
Collectibles.RuneSword = Require("scripts/items/printworks/rune_sword");
Collectibles.Escape = Require("scripts/items/printworks/escape");
Collectibles.EtherealArm = Require("scripts/items/printworks/ethereal_arm");
Collectibles.SakeOfForgotten = Require("scripts/items/printworks/sake_of_forgotten");
Collectibles.RebelMechaCaller = Require("scripts/items/printworks/rebel_mecha_caller");




THI.Collectibles = Collectibles;

THI.MinCollectibleID = Collectibles.YinYangOrb.Item;
THI.MaxCollectibleID = THI.MinCollectibleID;
for k,v in pairs(Collectibles) do
    if (v and v.Item > THI.MaxCollectibleID) then
        THI.MaxCollectibleID = v.Item;
    end
end

function THI:ContainsCollectible(id)
    return id >= self.MinCollectibleID and id <= self.MaxCollectibleID;
end



THI.Transformations = {
    Musician = Require("scripts/transformations/musician");
}

THI.Challenges = {
    HeavyDebt = Require("scripts/challenges/heavy_debt"),
    ShadowDieTwice = Require("scripts/challenges/shadow_die_twice"),
    SteamAge = Require("scripts/challenges/steam_age"),
    PurePurist = Require("scripts/challenges/pure_purist"),
    PhotoExam = Require("scripts/challenges/photo_exam"),
}


THI.GensouDream = Require("scripts/doremy/main");

THI.Trinkets = {
    FrozenFrog = Require("scripts/trinkets/frozen_frog"),
    AromaticFlower = Require("scripts/trinkets/aromatic_flower"),
    GlassesOfKnowledge = Require("scripts/trinkets/glasses_of_knowledge"),
    HowToReadABook = Require("scripts/trinkets/how_to_read_a_book"),
    CorrodedDoll = Require("scripts/trinkets/corroded_doll"),
    LionStatue = Require("scripts/trinkets/lion_statue"),
    FortuneCatPaw = Require("scripts/trinkets/fortune_cat_paw"),
    GhostAnchor = Require("scripts/trinkets/ghost_anchor"),
    MermanShell = Require("scripts/trinkets/merman_shell"),
    Dangos = Require("scripts/trinkets/dangos"),
    BundledStatue = Require("scripts/trinkets/bundled_statue"),
    ShieldOfLoyalty = Require("scripts/trinkets/shield_of_loyalty"),
    SwordOfLoyalty = Require("scripts/trinkets/sword_of_loyalty"),
    ButterflyWings = Require("scripts/trinkets/butterfly_wings")
}


-- Synergies

--- Hunger
Collectibles.Hunger:SetCollectibleHunger(Collectibles.BakedSweetPotato.Item, 3);
Collectibles.Hunger:SetTrinketHunger(THI.Trinkets.Dangos.Trinket, 2);
Collectibles.Hunger:SetTrinketHunger(THI.Trinkets.ButterflyWings.Trinket, 1);

--- DFlip
--Dr. Fetus - Fetus Blood
Collectibles.DFlip:AddFixedPair(5,100,CollectibleType.COLLECTIBLE_DR_FETUS, 5,100, Collectibles.FetusBlood.Item);
--Godhead - Broken Amulet
Collectibles.DFlip:AddFixedPair(5,100,CollectibleType.COLLECTIBLE_GODHEAD, 5,100, Collectibles.BrokenAmulet.Item);
--Genesis - Destruction
Collectibles.DFlip:AddFixedPair(5,100,CollectibleType.COLLECTIBLE_GENESIS, 5,100, Collectibles.Destruction.Item);
--Brimstone Bombs - Lightbombs
Collectibles.DFlip:AddFixedPair(5,100,CollectibleType.COLLECTIBLE_BRIMSTONE_BOMBS, 5,100, Collectibles.Lightbombs.Item);
--Starseeker - Pathseeker
Collectibles.DFlip:AddFixedPair(5,100,Collectibles.Starseeker.Item, 5,100, Collectibles.Pathseeker.Item);
--Wolf Eye - Wild Fury
Collectibles.DFlip:AddFixedPair(5,100,Collectibles.WolfEye.Item, 5,100, Collectibles.WildFury.Item);
--Onbashira - Young Native God
Collectibles.DFlip:AddFixedPair(5,100,Collectibles.Onbashira.Item, 5,100, Collectibles.YoungNativeGod.Item);
--D Flip - D DSiphon
Collectibles.DFlip:AddFixedPair(5,100,Collectibles.DFlip.Item, 5,100, Collectibles.DSiphon.Item);
--Miracle Mallet - Miracle Mallet Replica
Collectibles.DFlip:AddFixedPair(5,100,Collectibles.MiracleMallet.Item, 5,100, Collectibles.MiracleMalletReplica.Item);
--Mom's IOU - Dad's Shares
Collectibles.DFlip:AddFixedPair(5,100,Collectibles.MomsIOU.Item, 5,100, Collectibles.DadsShares.Item);
--Soul of Seija - Another Soul of Seija
Collectibles.DFlip:AddFixedPair(5,300,THI.Cards.SoulOfSeija.ID, 5,300, THI.Cards.SoulOfSeija.ReversedID);

include("scripts/post_load.lua");

ModEntity = nil;
ModItem = nil;
ModChallenge = nil;
ModCard = nil;
ModTrinket = nil;

-- Translations
do
    THI.ShowTranslationText = true;
    THI.Translations = {};
    THI.IncludedLanguages = {
        "en", "zh"
    }
    THI.Translations.en = Require("translations/en");
    for _, language in pairs(THI.IncludedLanguages) do
        THI.Translations[language] = Require("translations/"..language);
    end
    local language = Options.Language;

    THI.StringCategories = {
        DEFAULT = "Default",
        DIALOGS = "Dialogs",

    }

    local function GetLanguageText(category, key, lang)
        local Translations = THI.Translations;
        local translation = Translations[lang];
        if (translation) then
            local categoryStrings = translation[category];
            if (categoryStrings) then
                local string = categoryStrings[key];
                if (string) then
                    return string;
                end
            end
        end
        return nil;
    end
    function THI.ContainsText(category, key, lang)
        lang = lang or language;
        local languageString = GetLanguageText(category, key, language);
        if (languageString) then
            return true;
        end
        return false;
    end
    function THI.GetText(category, key, lang)
        local lang = lang or language;
        local languageString = GetLanguageText(category, key, lang);
        if (languageString) then
            return languageString;
        end
        -- English Fallback.
        return GetLanguageText(category, key, "en");
    end

    local BirthrightNames = {
        en = "Birthright",
        jp = "バースライト",
        kr = "생득권",
        zh = "长子名分",
        ru = "Право Первородства",
        de = "Geburtsrecht",
        es = "Primogenitura",
    }

    local function PostPickupItem(mod, player, item, touched)
        if (not THI.ShowTranslationText) then
            return;
        end
        local language = Options.Language;
        local Translations = THI.Translations;
        local translation = Translations[language];
        if (translation) then
            if (item == CollectibleType.COLLECTIBLE_BIRTHRIGHT) then
                local playerType = player:GetPlayerType();
                local info = translation.Players and translation.Players[playerType];
                if (info) then
                    THI.Game:GetHUD():ShowItemText(BirthrightNames[language] or BirthrightNames.en, info.Birthright or "");
                end
            else
                local info = translation.Collectibles and translation.Collectibles[item];
                if (info) then
                    THI.Game:GetHUD():ShowItemText(info.Name or "", info.Description or "");
                end
            end
        end
    end
    Lib.Callbacks:AddCallback(Lib.CLCallbacks.CLC_POST_PICKUP_COLLECTIBLE, PostPickupItem);

    
    local function PostPickupTrinket(mod, player, item, golden, touched)
        if (not THI.ShowTranslationText) then
            return;
        end
        if (item > 32768) then
            item = item - 32768
        end
        local language = Options.Language;
        local Translations = THI.Translations;
        local translation = Translations[language];
        if (translation) then
            local info = translation.Trinkets and translation.Trinkets[item];
            if (info) then
                THI.Game:GetHUD():ShowItemText(info.Name or "", info.Description or "");
            end
        end
    end
    Lib.Callbacks:AddCallback(Lib.CLCallbacks.CLC_POST_PICKUP_TRINKET, PostPickupTrinket);

    
    local function PostPickUpCard(mod, player, card)
        if (not THI.ShowTranslationText) then
            return;
        end

        local language = Options.Language;
        local Translations = THI.Translations;
        local translation = Translations[language];
        if (translation) then
            local info = translation.Cards and translation.Cards[card];
            if (info) then
                THI.Game:GetHUD():ShowItemText(info.Name or "", info.Description or "");
            end
        end
    end
    Lib.Callbacks:AddCallback(Lib.CLCallbacks.CLC_POST_PICK_UP_CARD, PostPickUpCard);

    
    local function PostUsePill(mod, pilleffect, player, flags)
        if (not THI.ShowTranslationText) then
            return;
        end

        if (flags & UseFlag.USE_NOHUD < 0) then
            return;
        end

        local language = Options.Language;
        local Translations = THI.Translations;
        local translation = Translations[language];
        if (translation) then
            local info = translation.Pills and translation.Pills[pilleffect];
            if (info) then
                THI.Game:GetHUD():ShowItemText(info.Name or "", info.Description or "");
            end
        end
    end
    THI:AddCallback(ModCallbacks.MC_USE_PILL, PostUsePill);
end

do -- Clear Datas when exited.
    local function PostExit(mod)
        for k, _ in pairs(THI.Data) do
            THI.Data[k] = nil
        end
    
        for k, _ in pairs(THI.TempData) do
            THI.TempData[k] = nil
        end
    end
    Lib.Callbacks:AddCallback(Lib.CLCallbacks.CLC_POST_EXIT, PostExit);
end

if (EID) then
    Require("descriptions/rep/main")
end

if (HPBars) then
    Require("compatilities/boss_bars")
end

CuerLib:LateRegister();

-- Lunatic.
do
    local Lunatic = {}

    local IsLunatic = false;

    function Lunatic.UpdateLunatic()
        local persistent = Lib.SaveAndLoad.ReadPersistentData();
        if (persistent.Lunatic) then
            IsLunatic = true;
        end
    end
    Lunatic.UpdateLunatic();

    function THI.IsLunatic()
        return IsLunatic;
    end

    function THI.SetLunatic(value)
        local persistent = Lib.SaveAndLoad.ReadPersistentData();
        persistent.Lunatic = value;
        IsLunatic = value;
        Lib.SaveAndLoad.WritePersistentData(persistent);
    end

    function Lunatic:PostExecuteCommand(cmd, parameters)
        if (cmd == "thlunatic") then
            local lunatic = THI.IsLunatic();
            THI.SetLunatic(not lunatic);
            if (lunatic) then
                print("Lunatic Mode is now off.");
            else
                print("Lunatic Mode is now on.");
            end
        -- elseif (cmd == "thfortune") then
        --     local value = tonumber(parameters);
        --     THI.SetFortune(value);
        --     print("Reverie item fortune has been set to "..value..".");
        end
    end
    THI:AddCallback(ModCallbacks.MC_EXECUTE_CMD, Lunatic.PostExecuteCommand)

    function Lunatic:PostGameStarted(isContinued)
        Lunatic.UpdateLunatic()
    end
    THI:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, Lunatic.PostGameStarted)

    local LunaticIcon = Sprite();
    LunaticIcon:Load("gfx/reverie/ui/lunatic.anm2", true);
    LunaticIcon:Play("Icon");
    function Lunatic:PostRender()
        if (THI.Game:GetHUD():IsVisible ( ) and THI.IsLunatic()) then
            local size = Lib.Screen.GetScreenSize() 
            local pos = Vector(size.X / 2 + 60, 14 + Options.HUDOffset * 24);
            LunaticIcon:Render(pos, Vector.Zero, Vector.Zero);
        end
    end
    THI:AddCallback(ModCallbacks.MC_POST_RENDER, Lunatic.PostRender)

end

-- function THI:PostGameStartGetItemPools(isContinued)
--     if (not isContinued) then
--         THI.Config.CollectibleItemPools = Lib.ItemPools.GetItemPoolCollectibles()
--     end
--     --print("Collectible Item Pools Loaded.");
-- end
-- THI:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, THI.PostGameStartGetItemPools);

function THI.GotoRoom(id)
    Isaac.ExecuteCommand("goto "..id);
end

-- Reevaluate caches after gameStarted.
function THI:PostGameStartEvaluate(isContinued)
    if  (isContinued) then
        for index, player in Lib.Detection.PlayerPairs(true, true) do
            --local player = THI.Game:GetPlayer(p);
            --print(index);
            player:AddCacheFlags(CacheFlag.CACHE_ALL);
            player:EvaluateItems();
            --print(player.MaxFireDelay)
        end
    end
end
THI:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, THI.PostGameStartEvaluate);


-- Curses.
do
    local function EvaluateCurse(curses)
        curses = curses or Game():GetLevel():GetCurses();
        for i, info in pairs(Lib.Callbacks.Functions.EvaluateCurse) do
            local result = info.Func(info.Mod, curses);
            if (result ~= nil) then
                if (type(result) == "number") then
                    curses = result;
                else
                    error("Trying to return a value which is not a number or nil in EVALUATE_CURSE.");
                end
            end
        end
        return curses;
    end
    function THI:EvaluateCurses()
        local level = Game():GetLevel();
        local beforeCurses = level:GetCurses();
        local curses = EvaluateCurse();

        local removedCurses = ~curses & beforeCurses;
        local addedCurses = ~beforeCurses & curses;

        -- Avoid remove Curse of Labyrinth.
        removedCurses = removedCurses & ~LevelCurse.CURSE_OF_LABYRINTH;
        addedCurses = addedCurses & ~LevelCurse.CURSE_OF_LABYRINTH;
        level:RemoveCurses(removedCurses);
        level:AddCurse(addedCurses);
    end

    local function OnCurseEvaluate(mod, curses)
        local newCurses = EvaluateCurse(curses);
        return newCurses;
    end
    THI:AddCallback(ModCallbacks.MC_POST_CURSE_EVAL, OnCurseEvaluate);
end

do -- Queued Item.

    THI.QueuedItemNil = nil;
    
    local function PostPlayerUpdate(mod, player)
        local queuedItem = player.QueuedItem.Item;
        if (not queuedItem) then
            THI.QueuedItemNil = player.QueuedItem
        end
    end
    THI:AddCallback(ModCallbacks.MC_POST_PLAYER_UPDATE, PostPlayerUpdate);
end

if (not StageAPI) then
    -- Custom Boss.
    do
        local CustomBosses = {};
        local noSkipBoss = false;
        function CustomBosses:PostExecuteCommand(cmd, parameters)
            if (cmd == "noskipboss") then
                noSkipBoss = not noSkipBoss;
                if (noSkipBoss) then
                    print("Disabled boss splash skip.");
                else
                    print("Enabled boss splash skip.");
                end
            -- elseif (cmd == "thfortune") then
            --     local value = tonumber(parameters);
            --     THI.SetFortune(value);
            --     print("Reverie item fortune has been set to "..value..".");
            end
        end
        THI:AddCallback(ModCallbacks.MC_EXECUTE_CMD, CustomBosses.PostExecuteCommand)

        
        local function InputAction(mod, entity, hook, action)
            if (noSkipBoss and Lib.Bosses:IsPlayingSplashSprite()) then
                if (action == ButtonAction.ACTION_MENUCONFIRM or action == ButtonAction.ACTION_CONSOLE) then
                    if ((hook == InputHook.IS_ACTION_TRIGGERED or hook == InputHook.IS_ACTION_PRESSED)) then
                        return false;
                    else
                        return 0;
                    end
                end
            end
        end
        THI:AddCallback(ModCallbacks.MC_INPUT_ACTION, InputAction);
    end
end

if (ModConfigMenu) then
    require("compatilities/mod_config_menu");
end
CuerLib = nil;
print("[Reverie] Reverie "..THI:GetVersionString().." Loaded.")

function SpawnPlanets()
    local planets = THI.Familiars.HellPlanets;
    local planet1 = Isaac.Spawn(planets.Type, planets.Variant, planets.SubTypes.OTHERWORLD, Vector(320, 280), Vector.Zero, nil):ToFamiliar();
    planet1.Parent = Isaac.GetPlayer();
    
    local planet2 = Isaac.Spawn(planets.Type, planets.Variant, planets.SubTypes.EARTH, Vector(320, 280), Vector.Zero, nil):ToFamiliar();
    planet2.Parent = planet1;
    
    local planet3 = Isaac.Spawn(planets.Type, planets.Variant, planets.SubTypes.MOON, Vector(320, 280), Vector.Zero, nil):ToFamiliar();
    planet3.Parent = planet2;
end