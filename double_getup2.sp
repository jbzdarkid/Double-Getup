#include <sourcemod>
#define ONE_FRAME 0.015

public Plugin:myinfo =
{
    name = "L4D2 Get-Up Fix",
    author = "Darkid",
    description = "When an event causes you to have a getup while in the middle of a getup, you have two getups.",
    version = "2.2",
    url = "https://github.com/jbzdarkid/Double-Getup"
}

/* Known double-getups: (included for posterity)
    Pounced, and then smoked
    Charged, and then hit by tank
    Charged, and then rocked by tank
*/

public OnPluginStart() {
    HookEvent("pounce_stopped", player_getup);
    HookEvent("charger_pummel_end", player_getup);

    // HookEvent("defibrillator_used", player_getup);
    
    HookEvent("tongue_pull_stopped", player_cleared);
    HookEvent("revive_success", player_revived);
    HookEvent("player_hurt", player_hurt);
}

new currentSequence[MAXPLAYERS] = 0;

// Watches for an additional getup. In these cases, there is no current sequence, we're only watching for an additional sequence.
public player_cleared(Handle:event, const String:name[], bool:dontBroadcast) {
    LogMessage("Tongue cut");
    new client = GetClientOfUserId(GetEventInt(event, "victim"));
    currentSequence[client] = -1;
    _GetupTimer(client);
}
public player_revived(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "subject"));
    currentSequence[client] = -1;
    _GetupTimer(client);
}

// Watches for any capping SI being cleared. Interestingly, pick-ups and defibs can also cause a double-getup.
public player_getup(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "victim"));
    _GetupTimer(client);
}

// Watches for tank rocks or tank punches.
public player_hurt(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
    new String:weapon[64];
    GetEventString(event, "weapon", weapon, sizeof(weapon));
    if (strcmp(weapon, "tank_claw") == 0) {
        _GetupTimer(client);
    } else if (strcmp(weapon, "tank_rock") == 0) {
        _GetupTimer(client);
    }
}

// The actual meat of the script. Basically, if a player is in a getup animation, and they then transfer to ANOTHER getup animation, then we cancel the new one. Repeat if necessary.
_GetupTimer(client) {
    CreateTimer(ONE_FRAME, GetupTimer, client, TIMER_REPEAT);
}
public Action:GetupTimer(Handle:timer, any:client) {
    if (currentSequence[client] == 0) {
        LogMessage("Player %d started getting up...", client);
        currentSequence[client] = GetEntProp(client, Prop_Send, "m_nSequence");
        if (currentSequence[client] == 0) {
            // Occurs when m_nSequence is not found.
            return Plugin_Stop;
        }
        LogMessage("(Sequence number: %d)", currentSequence[client]);
        return Plugin_Continue;
    }
    new sequence = GetEntProp(client, Prop_Send, "m_nSequence");
    if (sequence == currentSequence[client]) {
        // This is the most common case. The sequence is still ongoing, i.e. the player is still getting up (from the same source).
        LogMessage("Player %d still in sequence %d...", client, currentSequence[client]);
        return Plugin_Continue;
    }
    switch (sequence) {
    // This series of cases are the other potential getup animations. If the player enters any of these, they are experiencing a double-getup.
    case 528, 531, 537, 620, 621, 625, 629, 656, 660, 661, 667, 671, 672, 674, 675, 676, 678, 679, 759, 762, 763, 764, 766, 767, 819, 823, 824: {
        LogMessage("Player %d entered a second getup animation, cancelling...", client);
        SetEntPropFloat(client, Prop_Send, "m_flCycle", 1000.0);
        LogMessage("(Sequence number: %d)", currentSequence[client]);
        return Plugin_Continue;
    }
    }
    // The player entered another, non-getup animation. They're clear.
    currentSequence[client] = 0;
    return Plugin_Stop;
}
