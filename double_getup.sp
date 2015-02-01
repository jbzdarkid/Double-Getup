#include <sourcemod>
#define ONE_FRAME 0.015
#define DEBUG true

public Plugin:myinfo =
{
    name = "L4D2 Get-Up Fix",
    author = "Darkid, with code adaptations from l4d2_getupfix.sp",
    description = "When an event causes you to have a getup while in the middle of a getup, you have two getups.",
    version = "1.0",
    url = "none"
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

new pendingGetups[MAXPLAYERS] = 0;
new interrupt[MAXPLAYERS] = false;
new currentSequence[MAXPLAYERS] = 0;
new PlayerState:playerState[MAXPLAYERS] = PlayerState:NONE;
// While the current sequence and player state are slightly reduntant, it is simipler to track a separate player state rather than to write down the sequence numbers.

public player_round_start(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
    playerState[client] = PlayerState:NONE;
}

public tongue_grab(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "victim"));
    if (playerState[client] != PlayerState:HUNTER_GETUP) return;
    playerState[client] = PlayerState:SMOKER_PULL;
    interrupt[client] = true;
}

public smoker_clear(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "victim"));
    if (playerState[client] == PlayerState:INCAPPED) return;
    playerState[client] = PlayerState:NONE;
    local_CancelGetup(client);
}

public hunter_clear(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "victim"));
    if (playerState[client] == PlayerState:INCAPPED) return;
    playerState[client] = PlayerState:HUNTER_GETUP;
    pendingGetups[client]++;
    local_GetupTimer(client)
}

public charger_clear(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "victim"));
    if (playerState[client] == PlayerState:INCAPPED) return;
    playerState[client] = PlayerState:CHARGER_GETUP;
    pendingGetups[client]++;
    local_GetupTimer(client)
}

public player_incap(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
    playerState[client] = PlayerState:INCAPPED;
}

public player_revive(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "subject"));
    playerState[client] = PlayerState:NONE;
}

public player_defib(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "subject"));
    playerState[client] = PlayerState:NONE;
}

public player_hurt(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
    new String:weapon[64];
    GetEventString(event, "weapon", weapon, sizeof(weapon));
    if (strcmp(weapon, "tank_claw") == 0) {
        if (playerState[client] != PlayerState:CHARGER_GETUP) return;
        playerState[client] = PlayerState:TANK_PUNCH_GETUP;
        local_GetupTimer(client)
    } else if (strcmp(weapon, "tank_rock") == 0) {
        if (playerState[client] != PlayerState:CHARGER_GETUP) return;
        playerState[client] = PlayerState:TANK_ROCK_GETUP;
        local_GetupTimer(client);
    }
}

local_GetupTimer(client) {
    CreateTimer(ONE_FRAME, GetupTimer, client, TIMER_REPEAT);
}
public Action:GetupTimer(Handle:timer, any:client) {
    if (currentSequence[client] == 0) {
        LogMessage("Player %d is getting up...", client);
        currentSequence[client] = GetEntProp(client, Prop_Send, "m_nSequence");
        LogMessage("(Sequence number: %d)", currentSequence[client]);
        return Plugin_Continue;
    } else if (interrupt[client]) {
        LogMessage("Player %d's getup was interrupted!", client);
        interrupt[client] = false;
        return Plugin_Stop;
    } else if (currentSequence[client] == GetEntProp(client, Prop_Send, "m_nSequence")) {
        return Plugin_Continue;
    }
    LogMessage("Player %d finished getting up. (sequence %d)", client, currentSequence[client]);
    currentSequence[client] = 0;
    playerState[client] = PlayerState:NONE;
    pendingGetups[client]--;
    local_CancelGetup(client);
    return Plugin_Stop;
}

local_CancelGetup(client) {
    CreateTimer(ONE_FRAME, CancelGetup, client, TIMER_REPEAT);
}
public Action:CancelGetup(Handle:timer, any:client) {
    LogMessage("Player %d has %d pending getups.", client, pendingGetups[client]);
    if (pendingGetups[client] > 0) {
        pendingGetups[client]--;
        SetEntPropFloat(client, Prop_Send, "m_flCycle", 1000.0);
        return Plugin_Continue;
    }
    return Plugin_Stop;
}