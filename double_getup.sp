#include <sourcemod>
#define ONE_FRAME 0.015
#define DEBUG true
#pragma semicolon 1

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
    HookEvent("player_entered_start_area", player_round_start);

    HookEvent("tongue_grab", tongue_grab);
    HookEvent("tongue_pull_stopped", smoker_clear);
    HookEvent("pounce_stopped", hunter_clear);
    HookEvent("charger_pummel_end", charger_clear);
    // HookEvent("lunge_pounce", hunter_land);
    HookEvent("player_hurt", player_hurt);

    HookEvent("player_incapacitated", player_incap);
    HookEvent("defibrillator_used", player_defib);
    HookEvent("revive_success", player_revive);
}

enum PlayerState {
    NONE = 0,
    SMOKER_PULL,
    HUNTER_GETUP,
    JOCKEYED,
    CHARGER_GETUP,
    TANK_PUNCH_GETUP,
    TANK_ROCK_GETUP,
    INCAPPED
}

new pendingGetups[MAXPLAYERS] = 0; // This is used to track the number of pending getups. The collective opinion is that you should have at most 1.
new interrupt[MAXPLAYERS] = false; // If the player was getting up, and that getup is interrupted. This alows us to break out of the GetupTimer loop.
new currentSequence[MAXPLAYERS] = 0; // Kept to track when a player changes sequences, i.e. changes animations.
new PlayerState:playerState[MAXPLAYERS] = PlayerState:NONE; // Similar to currentSequence, but an english representation.

public player_round_start(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
    playerState[client] = PlayerState:NONE;
}

// If a player is smoked while getting up from a hunter, the getup is interrupted.
public tongue_grab(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "victim"));
    playerState[client] = PlayerState:SMOKER_PULL;
    if (playerState[client] == PlayerState:HUNTER_GETUP) {
        interrupt[client] = true;
    }
}

// If a player is cleared from a smoker, they should not have a getup.
// If they incap, they should not get up.
public smoker_clear(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "victim"));
    if (playerState[client] == PlayerState:INCAPPED) return;
    playerState[client] = PlayerState:NONE;
    _CancelGetup(client);
}

// If a player is cleared from a hunter, they should have 1 getup.
public hunter_clear(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "victim"));
    if (playerState[client] == PlayerState:INCAPPED) return;
    playerState[client] = PlayerState:HUNTER_GETUP;
    _GetupTimer(client);
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
    playerState[client] = PlayerState:INCAPPED;
    if (pendingGetups[client] > 0) {
        interrupt[client] = true;
    }
}

// When a player is picked up, they may enter a getup.
public player_revive(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "subject"));
    playerState[client] = PlayerState:NONE;
    _CancelGetup(client);
}

// When a player is defibbed, I have no idea. ###
public player_defib(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "subject"));
    playerState[client] = PlayerState:NONE;
}

// A catch-all to handle damage that is not associated with an event.
public player_hurt(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
    new String:weapon[64];
    GetEventString(event, "weapon", weapon, sizeof(weapon));
    // If a player is punched by a tank, they should have 1 getup.
    if (strcmp(weapon, "tank_claw") == 0) {
        playerState[client] = PlayerState:TANK_PUNCH_GETUP;
        _GetupTimer(client);
    } else if (strcmp(weapon, "tank_rock") == 0) {
        playerState[client] = PlayerState:TANK_ROCK_GETUP;
        _GetupTimer(client);
    }
    // Spit damage
    // Common damage
    LogMessage("Player %d took damage type %s", client, weapon);
}

_GetupTimer(client) {
    pendingGetups[client]++;
    CreateTimer(ONE_FRAME, GetupTimer, client, TIMER_REPEAT);
}
public Action:GetupTimer(Handle:timer, any:client) {
    if (currentSequence[client] == 0) {
        if (interrupt[client]) {
            interrupt[client] = false;
        }
        LogMessage("Player %d is getting up...", client);
        currentSequence[client] = GetEntProp(client, Prop_Send, "m_nSequence");
        LogMessage("(Sequence number: %d)", currentSequence[client]);
        return Plugin_Continue;
    } else if (interrupt[client]) {
        LogMessage("Player %d's getup was interrupted!", client);
        interrupt[client] = false;
        return Plugin_Stop;
    }
    
    if (currentSequence[client] == GetEntProp(client, Prop_Send, "m_nSequence")) {
        return Plugin_Continue;
    } else {
        LogMessage("Player %d finished getting up. (sequence %d)", client, currentSequence[client]);
        currentSequence[client] = 0;
        playerState[client] = PlayerState:NONE;
        pendingGetups[client]--;
        // After a player finishes getting up, cancel any remaining getups.
        _CancelGetup(client);
        return Plugin_Stop;
    }
}

_CancelGetup(client) {
    CreateTimer(ONE_FRAME, CancelGetup, client, TIMER_REPEAT);
}
public Action:CancelGetup(Handle:timer, any:client) {
    LogMessage("Player %d has %d pending getups.", client, pendingGetups[client]);
    if (pendingGetups[client] > 0) {
        pendingGetups[client]--;
        SetEntPropFloat(client, Prop_Send, "m_flCycle", 0.0);
        return Plugin_Continue;
    }
    return Plugin_Stop;
}