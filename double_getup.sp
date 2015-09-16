// *** Solved
// Charger self-clear (level) and incap
// Hunter & smoker
// Insta-clear hunter
// Charger and tank rock
// Tank Punch during charger getup.

// To test
// Insta-clear charger on a hunter getup.

#include <sourcemod>
#include <sdkhooks>
#define DEBUG true
#pragma semicolon 1

public Plugin:myinfo =
{
    name = "L4D2 Get-Up Fix",
    author = "Darkid",
    description = "Fixes the problem when, after completing a getup animation, you have another one.",
    version = "2.3",
    url = "https://github.com/jbzdarkid/Double-Getup"
}

public OnPluginStart() {
    HookEvent("player_entered_start_area", player_round_start);
    HookEvent("tongue_grab", smoker_land);
    HookEvent("tongue_release", smoker_clear);
    HookEvent("pounce_stopped", hunter_clear);
    HookEvent("charger_carry_end", charger_land);
    HookEvent("charger_pummel_start", charger_pummel_start);
    HookEvent("charger_pummel_end", charger_clear);
    HookEvent("player_incapacitated", player_incap);
    HookEvent("revive_success", player_revive);
}

enum PlayerState {
    UPRIGHT = 0,
    INCAPPED,
    SMOKED,
    HUNTER_GETUP,
    INSTACHARGED,
    CHARGED,
    CHARGER_GETUP,
    TANK_PUNCH_GETUP,
    TANK_ROCK_GETUP,
}

new pendingGetups[MAXPLAYERS] = 0; // This is used to track the number of pending getups. The collective opinion is that you should have at most 1.
new interrupt[MAXPLAYERS] = false; // If the player was getting up, and that getup is interrupted. This alows us to break out of the GetupTimer loop.
new currentSequence[MAXPLAYERS] = 0; // Kept to track when a player changes sequences, i.e. changes animations.
new PlayerState:playerState[MAXPLAYERS] = PlayerState:UPRIGHT; // Since there are multiple sequences for each animation, this acts as a simpler way to track a player's state.

public bool:isGettingUp(any:client) {
    switch (playerState[client]) {
    case (PlayerState:UPRIGHT):
        return false;
    case (PlayerState:INCAPPED):
        return false;
    case (PlayerState:SMOKED):
        return false;
    }
    return true;
}

// Used to check for tank rocks on players getting up from a charge.
public OnClientPostAdminCheck(client)
{
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public player_round_start(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
    playerState[client] = PlayerState:UPRIGHT;
}

// If a player is smoked while getting up from a hunter, the getup is interrupted.
public smoker_land(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "victim"));
    if (playerState[client] == PlayerState:HUNTER_GETUP) {
        interrupt[client] = true;
    }
}

// If a player is cleared from a smoker, they should not have a getup.
public smoker_clear(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "victim"));
    if (playerState[client] == PlayerState:INCAPPED) return;
    playerState[client] = PlayerState:UPRIGHT;
    _CancelGetup(client);
}

// If a player is cleared from a hunter, they should have 1 getup.
public hunter_clear(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "victim"));
    if (playerState[client] == PlayerState:INCAPPED) return;
    // If someone gets cleared WHILE they are otherwise getting up, they double-getup.
    if (isGettingUp(client)) {
        pendingGetups[client]++;
        return;
    }
    playerState[client] = PlayerState:HUNTER_GETUP;
    _GetupTimer(client);
}

// If a player is cleared from a charger, they should have 1 getup.
public charger_land(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "victim"));
    // If the player is incapped when the charger lands, they will getup after being revived.
    if (playerState[client] == PlayerState:INCAPPED) {
        pendingGetups[client]++;
    }
    playerState[client] = PlayerState:INSTACHARGED;
}

public charger_pummel_start(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "victim"));
    if (playerState[client] == PlayerState:INCAPPED) return;
    playerState[client] = PlayerState:CHARGED;
}

// If a player is cleared from a charger, they should have 1 getup.
public charger_clear(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "victim"));
    if (playerState[client] == PlayerState:INCAPPED) return;
    playerState[client] = PlayerState:CHARGER_GETUP;
    _GetupTimer(client);
}

// If a player is incapped, mark that down. This will interrupt their animations, if they have any.
public player_incap(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
    // If the player is incapped when the charger lands, they will getup after being revived.
    if (playerState[client] == PlayerState:INSTACHARGED) {
        pendingGetups[client]++;
    }
    playerState[client] = PlayerState:INCAPPED;
}

// When a player is picked up, they should have 0 getups.
public player_revive(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "subject"));
    playerState[client] = PlayerState:UPRIGHT;
    _CancelGetup(client);
}

// A catch-all to handle damage that is not associated with an event. I use this over player_hurt because it ignores godframes.
public Action:OnTakeDamage(victim, &attacker, &inflictor, &Float:damage, &damagetype)
{
    decl String:weapon[32];
    GetEdictClassname(inflictor, weapon, sizeof(weapon));
    if (strcmp(weapon, "weapon_tank_claw") == 0) {
        if (playerState[victim] == PlayerState:CHARGER_GETUP) {
            interrupt[victim] = true;
        }
        playerState[victim] = PlayerState:TANK_PUNCH_GETUP;
        _GetupTimer(victim);
    } else if (strcmp(weapon, "tank_rock") == 0) {
        if (playerState[victim] == PlayerState:CHARGER_GETUP) {
            interrupt[victim] = true;
        }
        playerState[victim] = PlayerState:TANK_ROCK_GETUP;
        _GetupTimer(victim);
    }
    return Plugin_Continue;
}

_GetupTimer(client) {
    if (client == 0) return;
    if (!IsClientInGame(client)) return;
    pendingGetups[client]++;
    CreateTimer(0.04, GetupTimer, client, TIMER_REPEAT);
}
public Action:GetupTimer(Handle:timer, any:client) {
    if (currentSequence[client] == 0) {
        currentSequence[client] = GetEntProp(client, Prop_Send, "m_nSequence");
        if (DEBUG) LogMessage("[Getup] Player %d is getting up...", client);
        return Plugin_Continue;
    } else if (interrupt[client]) {
        if (DEBUG) LogMessage("[Getup] Player %d's getup was interrupted!", client);
        interrupt[client] = false;
        currentSequence[client] = 0;
        return Plugin_Stop;
    }
    
    if (currentSequence[client] == GetEntProp(client, Prop_Send, "m_nSequence")) {
        return Plugin_Continue;
    } else {
        if (DEBUG) LogMessage("[Getup] Player %d finished getting up.", client);
        playerState[client] = PlayerState:UPRIGHT;
        pendingGetups[client]--;
        // After a player finishes getting up, cancel any remaining getups.
        _CancelGetup(client);
        return Plugin_Stop;
    }
}

_CancelGetup(client) {
    if (client == 0) return;
    if (!IsClientInGame(client)) return;
    CreateTimer(0.04, CancelGetup, client, TIMER_REPEAT);
}
public Action:CancelGetup(Handle:timer, any:client) {
    if (pendingGetups[client] == 0) {
        currentSequence[client] = 0;
        return Plugin_Stop;
    }
    if (DEBUG) LogMessage("[Getup] Canceled extra getup for player %d.", client);
    pendingGetups[client]--;
    SetEntPropFloat(client, Prop_Send, "m_flCycle", 1000.0); // Jumps to frame 1000 in the animation, effectively skipping it.
    return Plugin_Continue;
}