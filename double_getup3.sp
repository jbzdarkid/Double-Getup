// Possible hack (if too many things to find):
// After each key event (capper clear) process 0 or 1 animations and then skip animations until we reach "no animation".

#include <sourcemod>
#define ONE_FRAME 0.015
#define DEBUG true
#pragma semicolon 1;

public Plugin:myinfo =
{
    name = "L4D2 Get-Up Fix",
    author = "Darkid, with code adaptations from l4d2_getupfix.sp",
    description = "When an event causes you to have a getup while in the middle of a getup, you have two getups.",
    version = "1.0",
    url = "https://github.com/jbzdarkid/Double-Getup"
}

/* Known double-getups:
    Pounced, and then smoked
    Charged, and then hit by tank
    Charged, and then rocked by tank
*/

public OnPluginStart() {
    HookEvent("player_entered_start_area", round_start);

    HookEvent("tongue_pull_stopped", smoker_clear);
    HookEvent("pounce_stopped", hunter_clear);
    HookEvent("charger_pummel_end", charger_clear);
    HookEvent("player_hurt", player_hurt);
    HookEvent("defibrillator_used", player_defib);
    
    HookEvent("player_death", player_dead, EventHookMode_Pre);
    HookEvent("revive_success", player_revive);
}

new sequence[MAXPLAYERS] = 0; // Tracks when a player changes sequences, i.e. changes animations.
new incapped[MAXPLAYERS] = false; // Tracks if a player is incapped.

public round_start(Handle:event, const String:name[], bool:dontBroadcast) {
    for (new i=0; i<MAXPLAYERS; i++) {
        sequence[i] = 0;
        incapped[i] = false;
    }
}

// If a player is cleared from a smoker, they should not have a getup.
public smoker_clear(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "victim"));
    if (incapped[client]) return;
    _CancelGetup(client);
}

// If a player is cleared from a hunter, they should have a getup.
public hunter_clear(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "victim"));
    if (incapped[client]) return;
    _GetupTimer(client);
}

// If a player is cleared from a charger, they should have a getup.
public charger_clear(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "victim"));
    if (incapped[client]) return;
    _GetupTimer(client);
}

public player_incap(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
    incapped[client] = true;
}

// When a player is picked up, they should not have an additional getup.
public player_revive(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "subject"));
    incapped[client] = false;
    _CancelGetup(client);
}

public player_dead(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
    incapped[client] = true; // A bit of a lie, but whatever.
}

// When a player is defibbed, I have no idea. ###
public player_defib(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "subject"));
    incapped[client] = false;
}

// A catch-all to handle damage that is not associated with an event.
public player_hurt(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
    new String:weapon[64];
    GetEventString(event, "weapon", weapon, sizeof(weapon));
    // If a player is punched by a tank, they should have 1 getup.
    if (strcmp(weapon, "tank_claw") == 0) {
        _GetupTimer(client);
    } else if (strcmp(weapon, "tank_rock") == 0) {
        _GetupTimer(client);
    }
}

_GetupTimer(client) {
    CreateTimer(ONE_FRAME, GetupTimer, client, TIMER_REPEAT);
}
public Action:GetupTimer(Handle:timer, any:client) {
    if (sequence[client] == 0) {
        if (DEBUG) LogMessage("Player %d is getting up...", client);
        sequence[client] = GetEntProp(client, Prop_Send, "m_nSequence");
        if (DEBUG) LogMessage("(Sequence number: %d)", sequence[client]);
        return Plugin_Continue;
    } else if (sequence[client] == GetEntProp(client, Prop_Send, "m_nSequence")) {
        return Plugin_Continue;
    } else {
        if (DEBUG) LogMessage("Player %d finished getting up. (sequence %d)", client, sequence[client]);
        sequence[client] = 0;
        // After a player finishes getting up, cancel any remaining getups.
        _CancelGetup(client);
        return Plugin_Stop;
    }
}

_CancelGetup(client) {
    CreateTimer(ONE_FRAME, CancelGetup, client, TIMER_REPEAT);
}
public Action:CancelGetup(Handle:timer, any:client) {
    if (sequence[client] != 0) {
        if (DEBUG) LogMessage("Canceled sequence %d for client %d.", sequence[client], client);
        SetEntPropFloat(client, Prop_Send, "m_flCycle", 0.0);
        return Plugin_Continue;
    }
    return Plugin_Stop;
}