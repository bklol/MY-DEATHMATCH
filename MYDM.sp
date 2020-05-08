
#include <sourcemod>
#include <cstrike>
#include <sdktools>
#include <sdkhooks>
#include <events>
#include <string>

#define DMG_HEADSHOT (1 << 30)

ConVar IsEnemies;
ConVar mp_respawn_on_death_t;
ConVar mp_respawn_on_death_ct;
ConVar sv_infinite_ammo;
ConVar mp_death_drop_defuser;
ConVar mp_buytime;
ConVar mp_ignore_round_win_conditions;

int g_iLastEditorSpawnPoint[MAXPLAYERS + 1] = {-1, ...};
int FavPri[MAXPLAYERS+1];
int FavSec[MAXPLAYERS+1];
int TotalKills[MAXPLAYERS+1];
int g_iSpawnPointCount;
int g_iGlowSprite;
int g_iAmmoOffset;

bool UseOldWpn[MAXPLAYERS+1];
bool g_bInEditMode = false;
bool g_bHSOnlyClient[MAXPLAYERS + 1];

float g_fSpawnPositions[137][3];
float g_fSpawnAngles[137][3];
float g_fSpawnPointOffset[3] = { 0.0, 0.0, 20.0 };

enum Slots
{
	SlotPrimary,
	SlotSecondary,
	SlotKnife
}

char WpNameFst[24][]=
{
	"weapon_ak47","weapon_m4a1","weapon_m4a1_silencer","weapon_awp","weapon_ssg08","weapon_negev",
	"weapon_mac10","weapon_mp9","weapon_mp7","weapon_p90","weapon_ump45","weapon_bizon",
	"weapon_nova","weapon_xm1014","weapon_galilar","weapon_famas","weapon_sg556","weapon_aug",
	"weapon_sawedoff","weapon_m249","weapon_mag7","weapon_g3sg1","weapon_scar20","weapon_mp5sd"
}

char WpNameSec[10][]=
{
	"weapon_glock","weapon_hkp2000","weapon_deagle","weapon_p250","weapon_elite","weapon_cz75a",
	"weapon_tec9","weapon_fiveseven","weapon_usp_silencer","weapon_revolver"
}

char WpnCnNamePri[24][]=
{
	"AK-47","M4A4","M4A1 Silencer","AWP","SSG 08","Negev",
	"MAC-10","MP9","MP7","P90","UMP-45","PP-Bizon",
	"Nova","XM1014","Galil AR","FAMAS","SG 553","AUG",
	"Sawed-Off","M249","MAG-7","G3SG1","SCAR-20","MP5-SD"
}

char WpnCnNameSec[10][]=
{
	"Glock-18","P2000","Desert Eagle","P250","Dual Berettas","CZ75 Auto",
	"Tec-9","Five-SeveN","USP Silencer","R8 Revolver"
}

public void OnPluginStart() 
{
   RegConsoleCmd("sm_guns", Gunmenu);
   RegConsoleCmd("sm_gun", Gunmenu);
   RegConsoleCmd("sm_p", SetPosition);
   RegConsoleCmd("sm_hs", Hs);
   
   HookEvent("bomb_pickup", Event_BombPickup);
   HookEvent("weapon_fire_on_empty", Event_WeaponFireOnEmpty, EventHookMode_Post);
   
   HookEvent("player_death", Event_PlayerDeath);
   HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Pre);
   HookEvent("player_spawn", PlayerSpawn);
   
   CreateTimer(35.0, AD, INVALID_HANDLE, TIMER_REPEAT);

   g_iAmmoOffset = FindSendPropInfo("CCSPlayer", "m_iAmmo");
}

public void OnClientPostAdminCheck(int client)
{
	FavPri[client]=GetRandomInt(0,22);
	FavSec[client]=GetRandomInt(0,9);
	UseOldWpn[client]=false;
	g_bHSOnlyClient[client]=false;
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_TraceAttack, OnTraceAttack);
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	SDKHook(client, SDKHook_WeaponDropPost, Event_WeaponDrop);
}

public Event_WeaponDrop(client, weapon)
{
    CreateTimer(0.1, removeWeapon, EntIndexToEntRef(weapon), TIMER_FLAG_NO_MAPCHANGE);
}

public Action removeWeapon(Handle hTimer, any iWeaponRef)
{
    static weapon;
    weapon = EntRefToEntIndex(iWeaponRef);
    if(iWeaponRef == INVALID_ENT_REFERENCE || !IsValidEntity(weapon))
		return ;
    AcceptEntityInput(weapon, "kill");
    
} 
public Action AD(Handle timer)
{
	PrintToChatAll("[\x04NEKO DM\x01]输入\x04!gun\x01或者\x04!gun\x01来选择武器!");
	PrintToChatAll("[\x04NEKO DM\x01]输入\x04!hs\x01来开启或者关闭爆头模式");
}
public void OnMapStart()
{
	g_iGlowSprite = PrecacheModel("sprites/glow01.vmt", true);
	IsEnemies = FindConVar("mp_teammates_are_enemies");
	mp_respawn_on_death_t=FindConVar("mp_respawn_on_death_t");
	mp_respawn_on_death_ct=FindConVar("mp_respawn_on_death_ct");
	sv_infinite_ammo=FindConVar("sv_infinite_ammo");
	mp_death_drop_defuser=FindConVar("mp_death_drop_defuser");
	mp_buytime=FindConVar("mp_buytime");
	mp_ignore_round_win_conditions=FindConVar("mp_ignore_round_win_conditions");
	changeConvar();
	LoadMapConfig();
	
	for(new i = 1; i <= MaxClients; i++)
    {
        if(IsValidClient(i))
        {
			TotalKills[i] = 0;
        }
    }
}

changeConvar()
{
	IsEnemies.IntValue=1;
	mp_respawn_on_death_t.IntValue=1;
	mp_respawn_on_death_ct.IntValue=1;
	sv_infinite_ammo.IntValue=2;
	mp_death_drop_defuser.IntValue=0;
	mp_buytime.IntValue=0;
	mp_ignore_round_win_conditions.IntValue=1;
}

//https://github.com/Maxximou5/csgo-deathmatch/blob/master/scripting/deathmatch.sp
//im so lazy
void LoadMapConfig()
{
    char path[PLATFORM_MAX_PATH];
    char workshopID[PLATFORM_MAX_PATH];
    char map[PLATFORM_MAX_PATH];
    char workshop[PLATFORM_MAX_PATH];
    GetCurrentMap(map, PLATFORM_MAX_PATH);

    BuildPath(Path_SM, path, sizeof(path), "configs/deathmatch/spawns");
    if (!DirExists(path))
        if (!CreateDirectory(path, 511))
            LogError("Failed to create directory %s", path);

    BuildPath(Path_SM, path, sizeof(path), "configs/deathmatch/spawns/workshop");
    if (!DirExists(path))
        if (!CreateDirectory(path, 511))
            LogError("Failed to create directory %s", path);

    if (StrContains(map, "workshop", false) != -1)
    {
        GetCurrentWorkshopMap(workshop, PLATFORM_MAX_PATH, workshopID, sizeof(workshopID) - 1);
        BuildPath(Path_SM, path, sizeof(path), "configs/deathmatch/spawns/workshop/%s", workshopID);
        if (!DirExists(path))
            if (!CreateDirectory(path, 511))
                LogError("Failed to create directory %s", path);

        BuildPath(Path_SM, path, sizeof(path), "configs/deathmatch/spawns/workshop/%s/%s.txt", workshopID, workshop);
    }
    else
        BuildPath(Path_SM, path, sizeof(path), "configs/deathmatch/spawns/%s.txt", map);

    g_iSpawnPointCount = 0;

    /* Open file */
    File file = OpenFile(path, "r");
    if (file != null)
    {
        /* Read file */
        char buffer[256];
        char parts[6][16];
        while (!IsEndOfFile(file) && ReadFileLine(file, buffer, sizeof(buffer)))
        {
            ExplodeString(buffer, " ", parts, 6, 16);
            g_fSpawnPositions[g_iSpawnPointCount][0] = StringToFloat(parts[0]);
            g_fSpawnPositions[g_iSpawnPointCount][1] = StringToFloat(parts[1]);
            g_fSpawnPositions[g_iSpawnPointCount][2] = StringToFloat(parts[2]);
            g_fSpawnAngles[g_iSpawnPointCount][0] = StringToFloat(parts[3]);
            g_fSpawnAngles[g_iSpawnPointCount][1] = StringToFloat(parts[4]);
            g_fSpawnAngles[g_iSpawnPointCount][2] = StringToFloat(parts[5]);
            g_iSpawnPointCount++;
        }
	
    }
    /* Close file */
    delete file;
}

void OpenSelectmenu(int client)
{
	Menu menu = new Menu(Handler_SMenu);
	menu.SetTitle("武器菜单");
	menu.AddItem("1","选择不同武器");
	menu.AddItem("2","使用上次武器");
	menu.AddItem("3","保持上次武器");
	menu.AddItem("4","随机武器");
	menu.Display(client, MENU_TIME_FOREVER);
	menu.ExitButton = true;
}

public int Handler_SMenu(Menu menu, MenuAction action, int client,int itemNum)
{
	if (action == MenuAction_Select)
	{
		switch (itemNum)
		{
			case 0:
			{	
				OpenALLGunsmenu(client);
			}
			case 1:
			{
				RemoveGuns(client,1);
				GivePlayerItem(client,WpNameFst[FavPri[client]]);
				RemoveGuns(client,2);
				GivePlayerItem(client,WpNameSec[FavSec[client]]);
			}
			case 2:
			{
				RemoveGuns(client,1);
				GivePlayerItem(client,WpNameFst[FavPri[client]]);
				RemoveGuns(client,2);
				GivePlayerItem(client,WpNameSec[FavSec[client]]);
				UseOldWpn[client]=true;
			}
			case 3:
			{
				RemoveGuns(client,1);
				int WeaponIndex=GetRandomInt(0,23);
				GivePlayerItem(client,WpNameFst[WeaponIndex]);
				RemoveGuns(client,2);
				WeaponIndex=GetRandomInt(0,9);
				GivePlayerItem(client,WpNameSec[WeaponIndex]);
			}
		}
	}
	
}

public Action Gunmenu(client, args)
{
	OpenSelectmenu(client);
}

public Action SetPosition(client, args)
{
	if (client == 0)
    {
        ReplyToCommand(client, "[SM]", "只能在游戏里面使用");
        return Plugin_Handled;
    }
	BuildSpawnEditorMenu(client);
	return Plugin_Handled;
}

public Action Hs(client, args)
{
	g_bHSOnlyClient[client]=!g_bHSOnlyClient[client];
	ReplyToCommand(client,g_bHSOnlyClient[client]?"[\x04NEKO DM\x01]爆头模式开启":"[\x04NEKO DM\x01]爆头模式关闭");
}

void BuildSpawnEditorMenu(int client)
{
	char editModeItem[24];
	Menu menu = new Menu(MenuSpawnEditor);
	menu.SetTitle("Spawn Point Editor:");
	menu.ExitButton = true;
	Format(editModeItem, sizeof(editModeItem), "%s Edit Mode", (!g_bInEditMode) ? "Enable" : "Disable");
	menu.AddItem("Edit", editModeItem);
	menu.AddItem("Nearest", "Teleport to nearest");
	menu.AddItem("Previous", "Teleport to previous");
	menu.AddItem("Next", "Teleport to next");
	menu.AddItem("Add", "Add position");
	menu.AddItem("Insert", "Insert position here");
	menu.AddItem("Delete", "Delete nearest");
	menu.AddItem("Delete All", "Delete all");
	menu.AddItem("Save", "Save Configuration");
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuSpawnEditor(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[24];
		GetMenuItem(menu, param2, info, sizeof(info));
		if (StrEqual(info, "Edit"))
		{
			g_bInEditMode = !g_bInEditMode;
			if (g_bInEditMode)
			{
				CreateTimer(1.0, RenderSpawnPoints, INVALID_HANDLE, TIMER_REPEAT);
				PrintToChat(param1, "[\x04DM\x01] Spawn Editor Enabled");
			}
			else
				PrintToChat(param1, "[\x04DM\x01] Spawn Editor Disabled");
		}
		else if (StrEqual(info, "Nearest"))
		{
			int spawnPoint = GetNearestSpawn(param1);
			if (spawnPoint != -1)
			{
				TeleportEntity(param1, g_fSpawnPositions[spawnPoint], g_fSpawnAngles[spawnPoint], NULL_VECTOR);
				g_iLastEditorSpawnPoint[param1] = spawnPoint;
				PrintToChat(param1, "[\x04DM\x01] Spawn Editor Teleported #%i (%i total).", spawnPoint + 1, g_iSpawnPointCount);
			}
		}
		else if (StrEqual(info, "Previous"))
		{
			if (g_iSpawnPointCount == 0)
				PrintToChat(param1, "[\x04DM\x01] Spawn Editor No Spawn");
			else
			{
				int spawnPoint = g_iLastEditorSpawnPoint[param1] - 1;
				if (spawnPoint < 0)
					spawnPoint = g_iSpawnPointCount - 1;

				TeleportEntity(param1, g_fSpawnPositions[spawnPoint], g_fSpawnAngles[spawnPoint], NULL_VECTOR);
				g_iLastEditorSpawnPoint[param1] = spawnPoint;
				PrintToChat(param1, "[\x04DM\x01] Spawn Editor Teleported #%i (%i total).", spawnPoint + 1, g_iSpawnPointCount);
			}
		}
		else if (StrEqual(info, "Next"))
		{
		if (g_iSpawnPointCount == 0)
				PrintToChat(param1, "[\x04DM\x01] %Spawn Editor No Spawn");
			else
			{
				int spawnPoint = g_iLastEditorSpawnPoint[param1] + 1;
				if (spawnPoint >= g_iSpawnPointCount)
					spawnPoint = 0;

				TeleportEntity(param1, g_fSpawnPositions[spawnPoint], g_fSpawnAngles[spawnPoint], NULL_VECTOR);
				g_iLastEditorSpawnPoint[param1] = spawnPoint;
				PrintToChat(param1, "[\x04DM\x01] Spawn Editor Teleported #%i (%i total).", spawnPoint + 1, g_iSpawnPointCount);
			}
		}
		else if (StrEqual(info, "Add"))
		{
			AddSpawn(param1);
		}
		else if (StrEqual(info, "Insert"))
		{
			InsertSpawn(param1);
		}
			else if (StrEqual(info, "Delete"))
		{
			int spawnPoint = GetNearestSpawn(param1);
			if (spawnPoint != -1)
			{
				DeleteSpawn(spawnPoint);
				PrintToChat(param1, "[\x04DM\x01] Spawn Editor Deleted Spawn #%i (%i total).", spawnPoint + 1, g_iSpawnPointCount);
			}
		}
		else if (StrEqual(info, "Delete All"))
		{
            Panel panel = new Panel();
            panel.SetTitle("Delete all spawn points?");
            panel.DrawItem("Yes");
            panel.DrawItem("No");
            panel.Send(param1, PanelConfirmDeleteAllSpawns, MENU_TIME_FOREVER);
            delete panel;
        }
        else if (StrEqual(info, "Save"))
        {
			if (WriteMapConfig())
                PrintToChat(param1, "[\x04DM\x01] Spawn Editor Config Saved");
            else
                PrintToChat(param1, "[\x04DM\x01] Spawn Editor Config Not Saved");
        }
		if (!StrEqual(info, "Delete All"))
			BuildSpawnEditorMenu(param1);
    }
    else if (action == MenuAction_End)
        delete menu;
}

public int PanelConfirmDeleteAllSpawns(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        if (param2 == 1)
        {
            g_iSpawnPointCount = 0;
            PrintToChat(param1, "[\x04DM\x01]Spawn Editor Deleted All");
        }
        BuildSpawnEditorMenu(param1);
    }
}

bool WriteMapConfig()
{
    char map[64];
    GetCurrentMap(map, sizeof(map));

    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "configs/deathmatch/spawns/%s.txt", map);

    /* Open file */
    File file = OpenFile(path, "w");
    if (file == null)
    {
        LogError("Could not open spawn point file \"%s\" for writing.", path);
        return false;
    }
    /* Write spawn points */
    for (int i = 0; i < g_iSpawnPointCount; i++)
        WriteFileLine(file, "%f %f %f %f %f %f", g_fSpawnPositions[i][0], g_fSpawnPositions[i][1], g_fSpawnPositions[i][2], g_fSpawnAngles[i][0], g_fSpawnAngles[i][1], g_fSpawnAngles[i][2]);
    /* Close file */
    delete file;

    return true;
}

void OpenALLGunsmenu(int client)
{
	Menu menu = new Menu(Handler_mianMenu);
	menu.SetTitle("武器菜单");
	menu.AddItem("1","主武器");
	menu.AddItem("2","副武器");
	menu.Display(client, MENU_TIME_FOREVER);
	menu.ExitButton = true;
}

public int Handler_mianMenu(Menu menu, MenuAction action, int client,int itemNum)
{
	if (action == MenuAction_Select)
	{
		switch (itemNum)
		{
			case 0:
			{
				ShowGunMenuPri(client);
			}
			case 1:
			{
				ShowGunMenuSec(client);
			}
		}
	}
	
}

void ShowGunMenuPri(int client)
{
	FavPri[client]=-1;
	Handle HandleGunMenuPri = CreateMenu(GunMenuPri);
	SetMenuTitle(HandleGunMenuPri, "选择你的主武器:")
	for (new i=0;i<24;i++)
		AddMenuItem(HandleGunMenuPri, "", WpnCnNamePri[i]);
	SetMenuExitButton(HandleGunMenuPri, true);
	DisplayMenu(HandleGunMenuPri, client, 20);
	
}

public GunMenuPri(Handle HandleGunMenuPri, MenuAction action, param1, param2)
{
	if (action == MenuAction_Select)
	{
		RemoveGuns(param1,1);
		FavPri[param1]=param2;
		GivePlayerItem(param1, WpNameFst[param2]);
		ShowGunMenuSec(param1);
	}
	else if (action == MenuAction_End)
		CloseHandle(HandleGunMenuPri);
}

void ShowGunMenuSec(int client)
{
	FavSec[client]=-1;
	Handle HandleGunMenuSec = CreateMenu(GunMenuSec);
	SetMenuTitle(HandleGunMenuSec, "选择你的副武器:")
	for (new i=0;i<10;i++)
		AddMenuItem(HandleGunMenuSec, "", WpnCnNameSec[i]);
	SetMenuExitButton(HandleGunMenuSec, true);
	DisplayMenu(HandleGunMenuSec, client, 20);
	
}

public GunMenuSec(Handle HandleGunMenuSec, MenuAction action, param1, param2)
{

	if (action == MenuAction_Select)
	{
		RemoveGuns(param1,2);
		FavSec[param1]=param2;
		GivePlayerItem(param1, WpNameSec[param2]);
	}
	else if (action == MenuAction_End)
		CloseHandle(HandleGunMenuSec);
}

public Action PlayerSpawn(Event event, const char[] name, bool dontBroadcast) 
{
	
	int client=GetClientOfUserId(GetEventInt(event, "userid"));
	if(IsValidClient(client))
	{
		if(!UseOldWpn[client])
			CreateTimer(0.1, OM, client);
		else
		{
			CreateTimer(0.1, GW, client);
		}
	}
	if(IsValidBotClient(client))
	{
		RemoveGuns(client,1);
		int WeaponIndex=GetRandomInt(0,23);
		GivePlayerItem(client,WpNameFst[WeaponIndex]);
		RemoveGuns(client,2);
		WeaponIndex=GetRandomInt(0,9);
		GivePlayerItem(client,WpNameSec[WeaponIndex]);
	}
	if(g_iSpawnPointCount > 0)
	{
		int spawnPoint = GetRandomInt(0, g_iSpawnPointCount - 1);
		TeleportEntity(client, g_fSpawnPositions[spawnPoint], g_fSpawnAngles[spawnPoint], NULL_VECTOR);
	}
	SetEntProp(client, Prop_Data, "m_takedamage", 0);
	SetEntityRenderColor(client, 0, 0,255, 255);
	CreateTimer(0.1,RemoveRadar,client)
	CreateTimer(4.0, removeGod, client);
}

public Action RemoveRadar(Handle timer, any client)
{
	if (!IsValidEntity(client))
		return
	SetEntProp(client, Prop_Send, "m_iHideHUD", 1 << 12)
}

public Action OM(Handle timer,int client)
{
	OpenSelectmenu(client);
}

public Action GW(Handle timer,int client)
{
	RemoveGuns(client,1);
	GivePlayerItem(client,WpNameFst[FavPri[client]]);
	RemoveGuns(client,2);
	GivePlayerItem(client,WpNameSec[FavSec[client]]);
}

public Action removeGod(Handle timer,int client)
{
	SetEntProp(client, Prop_Data, "m_takedamage", 2);
	SetEntityRenderColor(client, 255, 255,255, 255);
}

stock bool IsValidClient( client )
{
	if ( client < 1 || client > MaxClients ) return false;
	if ( !IsClientConnected( client )) return false;
	if ( !IsClientInGame( client )) return false;
	if ( IsFakeClient(client)) return false;
	return true;
}

stock bool IsValidBotClient( client )
{
	if ( client < 1 || client > MaxClients ) return false;
	if ( !IsClientConnected( client )) return false;
	if ( !IsClientInGame( client )) return false;
	if ( !IsFakeClient(client)) return false;
	return true;
}

public Action OnPlayerRunCmd( client, &Buttons, &Impulse, float Vel[3], float Angles[3], &Weapon)
{
	
	if(IsPlayerAlive(client))
	{
		if(Buttons & (IN_ATTACK|IN_ATTACK2|IN_LEFT|IN_RIGHT|IN_FORWARD|IN_WALK|IN_BACK) )
		{
			SetEntProp( client, Prop_Data, "m_takedamage", 2);
			SetEntityRenderColor(client, 255, 255,255, 255);
		}
	}
}

RemoveGuns(client,slot)
{
	if (slot==1)
	{
		int WpnId = GetPlayerWeaponSlot(client,_:SlotPrimary)
		if (WpnId!=-1)
		{
			RemovePlayerItem(client, WpnId)
			AcceptEntityInput(WpnId, "Kill")
		}
	}
	else if (slot==2)
	{
		int WpnId = GetPlayerWeaponSlot(client,_:SlotSecondary)
		if (WpnId!=-1)
		{
			RemovePlayerItem(client, WpnId)
			AcceptEntityInput(WpnId, "Kill")
		}
	}
	
}

public void Event_BombPickup(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	StripC4(client); 
}

void GetCurrentWorkshopMap(char[] map, int mapbuffer, char[] workshopID, int workshopbuffer)
{
    char currentmap[128]
    char currentmapbuffer[2][64]

    GetCurrentMap(currentmap, 127)
    ReplaceString(currentmap, sizeof(currentmap), "workshop/", "", false)
    ExplodeString(currentmap, "/", currentmapbuffer, 2, 63)

    strcopy(map, mapbuffer, currentmapbuffer[1])
    strcopy(workshopID, workshopbuffer, currentmapbuffer[0])
}

int GetNearestSpawn(int client)
{
    if (g_iSpawnPointCount == 0)
    {
        PrintToChat(client, "[\x04DM\x01]Spawn Editor No Spawn");
        return -1;
    }

    float clientPosition[3];
    GetClientAbsOrigin(client, clientPosition);

    int nearestPoint = 0;
    float nearestPointDistance = GetVectorDistance(g_fSpawnPositions[0], clientPosition, true);

    for (int i = 1; i < g_iSpawnPointCount; i++)
    {
        float distance = GetVectorDistance(g_fSpawnPositions[i], clientPosition, true);
        if (distance < nearestPointDistance)
        {
            nearestPoint = i;
            nearestPointDistance = distance;
        }
    }
    return nearestPoint;
}

public Action RenderSpawnPoints(Handle timer)
{
    if (!g_bInEditMode)
        return Plugin_Stop;

    for (int i = 0; i < g_iSpawnPointCount; i++)
    {
        float spawnPosition[3];
        AddVectors(g_fSpawnPositions[i], g_fSpawnPointOffset, spawnPosition);
        TE_SetupGlowSprite(spawnPosition, g_iGlowSprite, 1.0, 0.5, 255);
        TE_SendToAll();
    }
    return Plugin_Continue;
}

void AddSpawn(int client)
{
    if (g_iSpawnPointCount >= 137)
    {
        PrintToChat(client, "[\x04DM\x01] Spawn Editor Spawn Not Added");
        return;
    }
    GetClientAbsOrigin(client, g_fSpawnPositions[g_iSpawnPointCount]);
    GetClientAbsAngles(client, g_fSpawnAngles[g_iSpawnPointCount]);
    g_iSpawnPointCount++;
    PrintToChat(client, "[\x04DM\x01] Spawn Editor Spawn Added");
}

void InsertSpawn(int client)
{
    if (g_iSpawnPointCount >= 137)
    {
        PrintToChat(client, "[\x04DM\x01]Spawn Editor Spawn Not Added");
        return;
    }

    if (g_iSpawnPointCount == 0)
        AddSpawn(client);
    else
    {
        /* Move spawn points down the list to make room for insertion. */
        for (int i = g_iSpawnPointCount - 1; i >= g_iLastEditorSpawnPoint[client]; i--)
        {
            g_fSpawnPositions[i + 1] = g_fSpawnPositions[i];
            g_fSpawnAngles[i + 1] = g_fSpawnAngles[i];
        }
        /* Insert new spawn point. */
        GetClientAbsOrigin(client, g_fSpawnPositions[g_iLastEditorSpawnPoint[client]]);
        GetClientAbsAngles(client, g_fSpawnAngles[g_iLastEditorSpawnPoint[client]]);
        g_iSpawnPointCount++;
        PrintToChat(client, "[\x04DM\x01] Spawn Editor Spawn Inserted #%i (%i total).", g_iLastEditorSpawnPoint[client] + 1, g_iSpawnPointCount);
    }
}

void DeleteSpawn(int spawnIndex)
{
    for (int i = spawnIndex; i < (g_iSpawnPointCount - 1); i++)
    {
        g_fSpawnPositions[i] = g_fSpawnPositions[i + 1];
        g_fSpawnAngles[i] = g_fSpawnAngles[i + 1];
    }
    g_iSpawnPointCount--;
}

bool StripC4(int client)
{
    if (IsValidClient(client) && IsPlayerAlive(client))
    {
        int c4Index = GetPlayerWeaponSlot(client, CS_SLOT_C4);
        if (c4Index != -1)
        {
            char weapon[24];
            GetClientWeapon(client, weapon, sizeof(weapon));
            /* If the player is holding C4, switch to the best weapon before removing it. */
            if (StrEqual(weapon, "weapon_c4"))
            {
                if (GetPlayerWeaponSlot(client, CS_SLOT_PRIMARY) != -1)
                    ClientCommand(client, "slot1");
                else if (GetPlayerWeaponSlot(client, CS_SLOT_SECONDARY) != -1)
                    ClientCommand(client, "slot2");
                else
                    ClientCommand(client, "slot3");
            }
            RemovePlayerItem(client, c4Index);
            AcceptEntityInput(c4Index, "Kill");
            return true;
        }
    }
    return false;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
        int attacker = GetClientOfUserId(event.GetInt("attacker"));
		TotalKills[attacker]++;
		if(TotalKills[attacker]>44)
			Endmap();
		if(TotalKills[attacker]>40)
			PrintToChatAll("[\x04NEKO DM\x01]%N已到达%i人头,比赛将在任意玩家到达45人头后结束",attacker,TotalKills[attacker])
			
        char weapon[32];
        event.GetString("weapon", weapon, sizeof(weapon));

        bool validAttacker = IsValidClient(attacker) && IsPlayerAlive(attacker);

        /* Reward the attacker with ammo. */
        if (validAttacker)
            RequestFrame(Frame_GiveAmmo, GetClientSerial(attacker));

        /* Reward attacker with HP. */
        if (validAttacker)
        {
            bool knifed = StrEqual(weapon, "knife");
            bool naded = StrEqual(weapon, "hegrenade");
            bool decoy = StrEqual(weapon, "decoy");
            bool inferno = StrEqual(weapon, "inferno");
            bool headshot = event.GetBool("headshot");
            int attackerHP = GetClientHealth(attacker);
			if (attackerHP < 100)
			{
				int addHP;

				if (knifed)
					addHP = 50;
				else if (headshot)
					addHP = 10;
				else if (naded || decoy || inferno)
					addHP = 30;
				else
					addHP = 30;
				int newHP = attackerHP + addHP;

                    if (newHP > 100)
                        newHP = 100;
                    SetEntProp(attacker, Prop_Send, "m_iHealth", newHP, 1);
			}
            /* Reward attacker with AP. */
				int attackerAP = GetClientArmor(attacker);
				if (attackerAP < 100)
                {
                    int addAP;

                    if (knifed)
                        addAP = 50;
                    else if (headshot)
                        addAP = 10;
                    else if (naded || decoy || inferno)
                        addAP = 30;
                    else
                        addAP = 10;

                    int newAP = attackerAP + addAP;

                    if (newAP > 100)
                        newAP = 100;

                    SetEntProp(attacker, Prop_Send, "m_ArmorValue", newAP, 1);
                }
		}
}

public void Frame_GiveAmmo(any serial)
{
    int weaponEntity;
    int client = GetClientFromSerial(serial)
    if (IsValidClient(client) && !IsFakeClient(client) && IsPlayerAlive(client))
    {
		weaponEntity = GetPlayerWeaponSlot(client, CS_SLOT_PRIMARY);
		if (weaponEntity != -1)
			Ammo_FullRefill(EntIndexToEntRef(weaponEntity), client);
		weaponEntity = GetPlayerWeaponSlot(client, CS_SLOT_SECONDARY);
		if (weaponEntity != -1)
			Ammo_FullRefill(EntIndexToEntRef(weaponEntity), client);
    }
}

void Ammo_FullRefill(int weaponRef, any client)
{
    int weaponEntity = EntRefToEntIndex(weaponRef);
    if (IsValidEdict(weaponEntity))
    {
        char weaponName[35];
        char clipSize;
        int maxAmmoCount;
        int ammoType = GetEntProp(weaponEntity, Prop_Send, "m_iPrimaryAmmoType", 1) * 4;

        if (GetEntityClassname(weaponEntity, weaponName, sizeof(weaponName)))
        {
            clipSize = GetWeaponAmmoCount(weaponName, true);
            maxAmmoCount = GetWeaponAmmoCount(weaponName, false);
            switch (GetEntProp(weaponRef, Prop_Send, "m_iItemDefinitionIndex"))
            {
                case 60: { clipSize = 25;maxAmmoCount = 75; }
                case 61: { clipSize = 12;maxAmmoCount = 24; }
                case 63: { clipSize = 12;maxAmmoCount = 12; }
                case 64: { clipSize = 8;maxAmmoCount = 8; }
            }
        }

        SetEntData(client, g_iAmmoOffset + ammoType, maxAmmoCount, true);
        SetEntProp(weaponEntity, Prop_Send, "m_iClip1", clipSize);
    }
}

int GetWeaponAmmoCount(char[] weaponName, bool currentClip)
{
    if (StrEqual(weaponName,  "weapon_ak47"))
        return currentClip ? 30 : 90;
    else if (StrEqual(weaponName,  "weapon_m4a1"))
        return currentClip ? 30 : 90;
    else if (StrEqual(weaponName,  "weapon_m4a1_silencer"))
        return currentClip ? 25 : 75;
    else if (StrEqual(weaponName,  "weapon_awp"))
        return currentClip ? 10 : 30;
    else if (StrEqual(weaponName,  "weapon_sg552"))
        return currentClip ? 30 : 90;
    else if (StrEqual(weaponName,  "weapon_aug"))
        return currentClip ? 30 : 90;
    else if (StrEqual(weaponName,  "weapon_p90"))
        return currentClip ? 50 : 100;
    else if (StrEqual(weaponName,  "weapon_galilar"))
        return currentClip ? 35 : 90;
    else if (StrEqual(weaponName,  "weapon_famas"))
        return currentClip ? 25 : 90;
    else if (StrEqual(weaponName,  "weapon_ssg08"))
        return currentClip ? 10 : 90;
    else if (StrEqual(weaponName,  "weapon_g3sg1"))
        return currentClip ? 20 : 90;
    else if (StrEqual(weaponName,  "weapon_scar20"))
        return currentClip ? 20 : 90;
    else if (StrEqual(weaponName,  "weapon_m249"))
        return currentClip ? 100 : 200;
    else if (StrEqual(weaponName,  "weapon_negev"))
        return currentClip ? 150 : 200;
    else if (StrEqual(weaponName,  "weapon_nova"))
        return currentClip ? 8 : 32;
    else if (StrEqual(weaponName,  "weapon_xm1014"))
        return currentClip ? 7 : 32;
    else if (StrEqual(weaponName,  "weapon_sawedoff"))
        return currentClip ? 7 : 32;
    else if (StrEqual(weaponName,  "weapon_mag7"))
        return currentClip ? 5 : 32;
    else if (StrEqual(weaponName,  "weapon_mac10"))
        return currentClip ? 30 : 100;
    else if (StrEqual(weaponName,  "weapon_mp9"))
        return currentClip ? 30 : 120;
    else if (StrEqual(weaponName,  "weapon_mp7"))
        return currentClip ? 30 : 120;
    else if (StrEqual(weaponName,  "weapon_ump45"))
        return currentClip ? 25 : 100;
    else if (StrEqual(weaponName,  "weapon_mp5sd"))
        return currentClip ? 30 : 120; 
    else if (StrEqual(weaponName,  "weapon_bizon"))
        return currentClip ? 64 : 120;
    else if (StrEqual(weaponName,  "weapon_glock"))
        return currentClip ? 20 : 120;
    else if (StrEqual(weaponName,  "weapon_fiveseven"))
        return currentClip ? 20 : 100;
    else if (StrEqual(weaponName,  "weapon_deagle"))
        return currentClip ? 7 : 35;
    else if (StrEqual(weaponName,  "weapon_revolver"))
        return currentClip ? 8 : 8;
    else if (StrEqual(weaponName,  "weapon_hkp2000"))
        return currentClip ? 13 : 52;
    else if (StrEqual(weaponName,  "weapon_usp_silencer"))
        return currentClip ? 12 : 24;
    else if (StrEqual(weaponName,  "weapon_p250"))
        return currentClip ? 13 : 26;
    else if (StrEqual(weaponName,  "weapon_elite"))
        return currentClip ? 30 : 120;
    else if (StrEqual(weaponName,  "weapon_tec9"))
        return currentClip ? 24 : 120;
    else if (StrEqual(weaponName,  "weapon_cz75a"))
        return currentClip ? 12 : 12;
	
    return currentClip ? 30 : 90;
}

public Action Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
        int attacker = GetClientOfUserId(event.GetInt("attacker"));
        if (g_bHSOnlyClient[attacker])
        {
			int victim = GetClientOfUserId(event.GetInt("userid"));
            int dhealth = event.GetInt("dmg_health");
            int darmor = event.GetInt("dmg_iArmor");
            int health = event.GetInt("health");
            int armor = event.GetInt("armor");
            char weapon[32];
            event.GetString("weapon", weapon, sizeof(weapon));
			if (StrEqual(weapon, "knife", false))
                {
                    if (attacker != victim && victim != 0)
                    {
                        if (dhealth > 0)
                            SetEntProp(victim, Prop_Send, "m_iHealth", (health + dhealth));

                        if (darmor > 0)
                            SetEntProp(victim, Prop_Send, "m_ArmorValue", (armor + darmor));
                    }
				}
				if (victim !=0 && attacker == 0)
				{
					if (dhealth > 0)
						SetEntProp(victim, Prop_Send, "m_iHealth", (health + dhealth));
					if (darmor > 0)
						SetEntProp(victim, Prop_Send, "m_ArmorValue", (armor + darmor));
				}
		}

	return Plugin_Continue;
}

public Action Event_WeaponFireOnEmpty(Event event, const char[] name, bool dontBroadcast)
{
        int client = GetClientOfUserId(event.GetInt("userid"));
        RequestFrame(Frame_GiveAmmo, GetClientSerial(client));
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    if (g_bHSOnlyClient[attacker])
    {
        char grenade[32],weapon[32];
		GetEdictClassname(inflictor, grenade, sizeof(grenade));
		GetClientWeapon(attacker, weapon, sizeof(weapon));
		if (damagetype & DMG_HEADSHOT)
			return Plugin_Continue;
		else  
			return Plugin_Handled;  
    }
    return Plugin_Continue;
}

public Action OnTraceAttack(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int hitgroup)
{
	if(g_bHSOnlyClient[attacker])
	{
		char weapon[32],grenade[32];
		GetEdictClassname(inflictor, grenade, sizeof(grenade));
		GetClientWeapon(attacker, weapon, sizeof(weapon));
		if (hitgroup == 1)
			return Plugin_Continue;
		else
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

void Endmap()
{
	CS_TerminateRound(0.1, CSRoundEnd_TerroristWin, true);
	int ent = CreateEntityByName("game_end");
	AcceptEntityInput(ent, "EndGame"); 
}