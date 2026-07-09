local profile = {};
gcinclude = gFunc.LoadFile('dlac\\gcinclude.lua');

-- Initialize state variables here (local to the file, persistent across profile.HandleDefault calls)
local lastKnownLevel = 0;
local lastKnownSJLevel = 0;
local lastKnownSJ = '';

local gear = require("dlac\\gear");
local utils = require("dlac\\utils");



local sets = {

    Dynamic = {
        Idle = {
            Main = {
                gear.Main.Sword.WaxSword_1,
                gear.Main.Dagger.MercenarysKnife,
                gear.Main.Dagger.ParryingKnife,
                gear.Main.Dagger.MaraudersKnife,
                gear.Main.Dagger.Hornetneedle,
                gear.Main.Dagger.ThiefsKnife,
                gear.Main.Dagger.Atoyac,

            },
            Sub = {
                gear.Main.Dagger.MercenarysKnife,
                gear.Main.Dagger.ParryingKnife,
                gear.Main.Dagger.MaraudersKnife,
                gear.Main.Dagger.Hornetneedle,
                gear.Main.Dagger.ThiefsKnife,
            },
            Head = {
                gear.Head.PoetsCirclet,
                gear.Head.GarrisonSallet,
                gear.Head.EmperorHairpin,
                gear.Head.AdhemarBonnet,
            },
            Body = {
                gear.Body.Doublet,
                gear.Body.GarrisonTunica,
                gear.Body.CottonDoublet,
                gear.Body.AdhemarJacket,
            },
            Hands = {
                gear.Hands.GuerillaGloves,
                gear.Hands.AdhemarWristbands,
            },
            Legs =  {
                gear.Legs.LinenSlops,
                gear.Legs.PhlegethonsTrousers,
                gear.Legs.GarrisonHose,
                gear.Legs.AdhemarKecks,
            },
            Feet = {
                gear.Feet.LeapingBoots,
                gear.Feet.AdhemarGamashes,
            },
            Neck = {
                gear.Neck.PileChain,
                gear.Neck.WivreGorget,
            },
            Back = {
                gear.Back.TravelersMantle,
                gear.Back.RamMantle,
            },
            Waist = {
                gear.Waist.WarriorsBelt_1,
                gear.Waist.HeadlongBelt,
            },
            Ear1 = {
                gear.Ear.OpticalEarring,
            },
            Ear2 = {
                gear.Ear.DodgeEarring,
                gear.Ear.OutlawsEarring,
            },
            Ring1 = {
                gear.Ring.SanDorianRing,
                gear.Ring.LavasRing,
            },
            Ring2 = {
                gear.Ring.ProvenanceRing,
                gear.Ring.KushasRing,
            }
        },
    },
    Extenterator = {
        Head = gear.Head.AdhemarBonnet.Name,
        Neck = gear.Neck.PileChain.Name,
        Body = gear.Body.AssaultJerkin.Name,
        Hands = gear.Hands.AdhemarWristbands.Name,
        Ring1 = gear.Ring.LavasRing.Name,
        Ring2 = gear.Ring.KushasRing.Name,
        Back = gear.Back.TundraMantle.Name,
        Waist = gear.Waist.VirtuosoBelt.Name,
        Legs = gear.Legs.AdhemarKecks.Name,
        Feet = gear.Feet.AdhemarGamashes.Name,
    }
};
profile.Sets = sets;


profile.OnLoad = function()
	gSettings.AllowAddSet = true;
    gcinclude.Initialize();
    --[[ Set you job macro defaults here]]
    AshitaCore:GetChatManager():QueueCommand(1, '/macro book 1');
    AshitaCore:GetChatManager():QueueCommand(1, '/macro set 1');
end

profile.OnUnload = function()
    gcinclude.Unload();
end

profile.HandleCommand = function(args)
	gcinclude.HandleCommands(args);
end

 
profile.HandleDefault = function()
    local player = gData.GetPlayer();

    sets, lastKnownLevel, lastKnownSJLevel, lastKnownSJ = utils.rebuildSetsIfNeeded(
        player, 
        sets, 
        lastKnownLevel, 
        lastKnownSJLevel, 
        lastKnownSJ
    );

    -- if (player.Status == 'Engaged') then
    --     gFunc.EquipSet(sets.Tp_Default);
    if (player.Status == 'Resting') then
        gFunc.EquipSet(sets.Resting);
    else
        gFunc.EquipSet(sets.Idle);
    end


	gcinclude.CheckDefault ();
    if (gcdisplay.GetToggle('DTset') == true) then
		gFunc.EquipSet(sets.Dt);
        if (pet ~= nil) then
            gFunc.EquipSet(sets.Pet_Dt);
		end
	end
    if (gcdisplay.GetToggle('Kite') == true) then gFunc.EquipSet(sets.Movement) end;
end



profile.HandlePrecast = function()
    local spell = gData.GetAction();
    gFunc.EquipSet(sets.Precast);

    gcinclude.CheckCancels();
end

profile.HandleMidcast = function()
    local spell = gData.GetAction();

	if (gcdisplay.GetToggle('TH') == true) then gFunc.EquipSet(sets.TH) end
    
end

profile.HandlePreshot = function()
    gFunc.EquipSet(sets.Preshot);
end

profile.HandleMidshot = function()
    gFunc.EquipSet(sets.Midshot);
	if (gcdisplay.GetToggle('TH') == true) then gFunc.EquipSet(sets.TH) end
end

profile.HandleWeaponskill = function()
	local canWS = gcinclude.CheckWsBailout();
    if (canWS == false) then gFunc.CancelAction() return;
    else
        local ws = gData.GetAction();
        
        gFunc.EquipSet(sets.Ws_Default)
        if (ws.Name == 'Exenterator') then
            gFunc.EquipSet(sets.Extenterator);
        end
    end
end

return profile;