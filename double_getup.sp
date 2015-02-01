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

public OnPluginStart() {
    HookEvent("player_entered_start_area", player_round_start);

    HookEvent("tongue_grab", tongue_grab);
    // HookEvent("player_hurt", PlayerHurt);
    HookEvent("tongue_pull_stopped", smoker_clear);
    HookEvent("choke_stopped", smoker_clear);
    // HookEvent("lunge_pounce", hunter_land);
    HookEvent("pounce_stopped", hunter_clear);
    HookEvent("charger_pummel_end", charger_clear);

    HookEvent("player_incapacitated", player_incap);
    HookEvent("defibrillator_used", player_defib);
    HookEvent("revive_success", player_revive);
}

new pendingGetups[MAXPLAYERS] = 0;
new currentSequence[MAXPLAYERS] = 0;
new isIncapped[MAXPLAYERS] = false;
new interrupt[MAXPLAYERS] = false;

public player_round_start(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
    isIncapped[client] = false;
}

public tongue_grab(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "victim"));
    PrintToChat(1, "Player %d smoked", client);
    if (pendingGetups[client] == 0) return;
    interrupt[client] = true;
}

public smoker_clear(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "victim"));
    PrintToChat(1, "Smoker cleared from player %d", client);
    if (isIncapped[client]) return;
    CreateTimer(ONE_FRAME, CancelGetup, client, TIMER_REPEAT);
}

public hunter_clear(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "victim"));
    PrintToChat(1, "Hunter cleared from player %d", client);
    if (isIncapped[client]) return;
    pendingGetups[client]++;
    CreateTimer(ONE_FRAME, GetupTimer, client, TIMER_REPEAT);
}

public charger_clear(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "victim"));
    PrintToChat(1, "Charger cleared from player %d", client);
    if (isIncapped[client]) return;
    pendingGetups[client]++;
    CreateTimer(ONE_FRAME, GetupTimer, client, TIMER_REPEAT);
}

public player_incap(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
    isIncapped[client] = true;
    PrintToChat(1, "Player %d incapped", client);
}

public player_defib(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "subject"));
    isIncapped[client] = false;
    PrintToChat(1, "Player %d defib'd", client);
    CreateTimer(ONE_FRAME, GetupTimer, client, TIMER_REPEAT);
}

public player_revive(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "subject"));
    isIncapped[client] = false;
    PrintToChat(1, "Player %d revived", client);
    CreateTimer(ONE_FRAME, CancelGetup, client, TIMER_REPEAT);
}

public Action:GetupTimer(Handle:timer, any:client) {
    if (currentSequence[client] == 0) {
        PrintToChat(1, "Player %d is getting up...", client);
        currentSequence[client] = GetEntProp(client, Prop_Send, "m_nSequence");
        PrintToChat(1, "(Sequence number: %d)", currentSequence[client]);
        return Plugin_Continue;
    } else if (interrupt[client]) {
        PrintToChat(1, "Player %d's getup was interrupted!", client, currentSequence[client]);
        interrupt[client] = false;
        return Plugin_Stop;
    } else if (currentSequence[client] == GetEntProp(client, Prop_Send, "m_nSequence")) {
        return Plugin_Continue;
    }
    PrintToChat(1, "Player %d finished getting up. (sequence %d)", client, currentSequence[client]);
    currentSequence[client] = 0;
    pendingGetups[client]--;
    CreateTimer(ONE_FRAME, CancelGetup, client, TIMER_REPEAT);
    return Plugin_Stop;
}

public Action:CancelGetup(Handle:timer, any:client) {
    PrintToChat(1, "Player %d has %d pending getups.", client, pendingGetups[client]);
    if (pendingGetups[client] > 0) {
        pendingGetups[client]--;
        SetEntPropFloat(client, Prop_Send, "m_flCycle", 1000.0);
        return Plugin_Continue;
    }
    return Plugin_Stop;
}