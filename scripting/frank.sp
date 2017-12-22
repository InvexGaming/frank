#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <clientprefs>
#include <colors_csgo_v2>

#pragma semicolon 1
#pragma newdecls required

/*********************************
 *  Plugin Information
 *********************************/
#define PLUGIN_VERSION "2.01"

public Plugin myinfo =
{
  name = "Frank - Fake Competitive Ranks/Profiles/Coins",
  author = "Invex | Byte",
  description = "Show competitive ranks, profile icons and coins on scoreboard",
  version = PLUGIN_VERSION,
  url = "http://www.invexgaming.com.au"
};

/*********************************
 *  Definitions
 *********************************/
#define CHAT_TAG_PREFIX "[{lightred}FRANK{default}] "
#define MMSTYLE_DEFAULT 0
#define MMSTYLE_WINGMANRANK 7
#define MMSTYLE_WINGMANLEVEL 8

/*********************************
 *  Globals
 *********************************/

//Convars
ConVar g_Cvar_VipFlag = null;

//Globals
int g_CompetitiveRanking[MAXPLAYERS+1] = {0, ...}; //m_iCompetitiveRanking
int g_CompetitiveRankType[MAXPLAYERS+1] = {0, ...}; //m_iCompetitiveRankType
int g_ProfileRank[MAXPLAYERS+1] = {0, ...}; //m_nPersonaDataPublicLevel
int g_ActiveCoinRank[MAXPLAYERS+1] = {0, ...}; //m_nActiveCoinRank

bool g_WaitingForSayInput[MAXPLAYERS+1] = {false, ...};

//Netprop offsets
int g_CompetitiveRankingOffset = -1;
int g_CompetitiveRankTypeOffset = -1;
int g_ProfileRankOffset = -1;
int g_ActiveCoinRankOffset = -1;

//Cookies
Handle g_CompetitiveRankingCookie = null;
Handle g_CompetitiveRankTypeCookie = null;
Handle g_ProfileRankCookie = null;
Handle g_ActiveCoinRankCookie = null;

//ArrayList
ArrayList g_ArrayRanks = null;
ArrayList g_ArrayRankTypes = null;
ArrayList g_ArrayProfileRanks = null;
ArrayList g_ArrayCoins = null;
ArrayList g_ArrayRanksName = null;
ArrayList g_ArrayRankTypesName = null;
ArrayList g_ArrayProfileRanksName = null;
ArrayList g_ArrayCoinsName = null;

//Forwards
bool g_IsPostAdminCheck[MAXPLAYERS+1] = {false, ...}; //for OnClientPostAdminCheckAndCookiesCached

//Lateload
bool g_LateLoaded = false;

/*********************************
 *  Forwards
 *********************************/

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
  g_LateLoaded = late;
  return APLRes_Success;
}

public void OnPluginStart()
{
  //Translations
  LoadTranslations("common.phrases");
  LoadTranslations("frank.phrases");
  
  //Setup cookies
  g_CompetitiveRankingCookie = RegClientCookie("Frank_CompetitiveRanking", "", CookieAccess_Private);
  g_CompetitiveRankTypeCookie = RegClientCookie("Frank_CompetitiveRankType", "", CookieAccess_Private);
  g_ProfileRankCookie = RegClientCookie("Frank_ProfileRank", "", CookieAccess_Private);
  g_ActiveCoinRankCookie = RegClientCookie("Frank_ActiveCoinRank", "", CookieAccess_Private);
  
  //ConVars
  g_Cvar_VipFlag = CreateConVar("sm_frank_vipflag", "", "Flag to identify VIP players");
  
  AutoExecConfig(true, "frank");
  
  //Commands
  RegConsoleCmd("sm_mm", Command_Mm);
  RegConsoleCmd("sm_mmstyle", Command_Mmstyle);
  RegConsoleCmd("sm_profile", Command_Profile);
  RegConsoleCmd("sm_coin", Command_Coin);
  
  RegAdminCmd("sm_setmm", Command_SetMm, ADMFLAG_GENERIC, "Set clients MM rank");
  RegAdminCmd("sm_setmmstyle", Command_SetMmstyle, ADMFLAG_GENERIC, "Set clients MM style");
  RegAdminCmd("sm_setprofile", Command_SetProfile, ADMFLAG_GENERIC, "Set clients Profile");
  RegAdminCmd("sm_setcoin", Command_SetCoin, ADMFLAG_GENERIC, "Set clients Coin");
  
  //Late load
  if (g_LateLoaded) {
    for (int i = 1; i <= MaxClients; ++i) {
      if (IsClientInGame(i)) {
        OnClientPutInServer(i);
        
        if (!IsFakeClient(i) && g_IsPostAdminCheck[i] && AreClientCookiesCached(i))
          OnClientPostAdminCheckAndCookiesCached(i);
      }
    }
    
    g_LateLoaded = false;
  }
  
  //Initilise arrays
  g_ArrayRanks = new ArrayList(1);
  g_ArrayRankTypes = new ArrayList(1);
  g_ArrayProfileRanks = new ArrayList(1);
  g_ArrayCoins = new ArrayList(1);
  g_ArrayRanksName = new ArrayList(ByteCountToCells(255));
  g_ArrayRankTypesName = new ArrayList(ByteCountToCells(255));
  g_ArrayProfileRanksName = new ArrayList(ByteCountToCells(255));
  g_ArrayCoinsName = new ArrayList(ByteCountToCells(255));
  
  //Hooks
  HookEvent("announce_phase_end", Event_AnnouncePhaseEnd);
}

public void OnMapStart()
{
  int entity = FindEntityByClassname(MaxClients+1, "cs_player_manager");
  if (entity == -1)
    SetFailState("Unable to find cs_player_manager entity.");
  
  //Get offsets
  g_CompetitiveRankingOffset = FindSendPropInfo("CCSPlayerResource", "m_iCompetitiveRanking");
  g_CompetitiveRankTypeOffset = FindSendPropInfo("CCSPlayerResource", "m_iCompetitiveRankType");
  g_ProfileRankOffset = FindSendPropInfo("CCSPlayerResource", "m_nPersonaDataPublicLevel");
  g_ActiveCoinRankOffset = FindSendPropInfo("CCSPlayerResource", "m_nActiveCoinRank");
  
  if (g_CompetitiveRankingOffset == -1 || g_CompetitiveRankTypeOffset == -1 || g_ProfileRankOffset == -1 || g_ActiveCoinRankOffset == -1)
    SetFailState("Failed to get required CCSPlayerResource offsets.");
  
  //Read config
  ReadConfigFile();
  
  //Hook ThinkPost
  SDKHook(entity, SDKHook_ThinkPost, Hook_OnThinkPost);
}

//Monitor chat to capture commands
public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
  if (g_WaitingForSayInput[client]) {
    if (IsStringNumeric(sArgs)) {
      SetClientMm(client, StringToInt(sArgs));
      CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Generic Selected", "Wingman Level", sArgs);
    }
    else {
      CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Non Numeric Input", sArgs);
    }
    
    //Reset
    g_WaitingForSayInput[client] = false;
    return Plugin_Handled;
  }
  
  return Plugin_Continue;
}

public void OnClientPutInServer(int client)
{
  //Initilize variables
  g_CompetitiveRanking[client] = 0;
  g_CompetitiveRankType[client] = 0;
  g_ProfileRank[client] = 0;
  g_ActiveCoinRank[client] = 0;
  g_WaitingForSayInput[client] = false;
}

public void OnClientConnected(int client)
{
  g_IsPostAdminCheck[client] = false;
}

public void OnClientCookiesCached(int client)
{
  if (g_IsPostAdminCheck[client])
    OnClientPostAdminCheckAndCookiesCached(client);
}

public void OnClientPostAdminCheck(int client)
{
  g_IsPostAdminCheck[client] = true;

  if (AreClientCookiesCached(client))
    OnClientPostAdminCheckAndCookiesCached(client);
}

//Run when PostAdminCheck reached and cookies are cached
//Always run for every client and always after both OnClientCookiesCached and OnClientPostAdminCheck
void OnClientPostAdminCheckAndCookiesCached(int client)
{
  if (IsFakeClient(client))
    return;
  
  //For non-VIP's do not load in the stored cookie preferences
  //If the client gets VIP status at a later time, their preferences will still be there
  if (!IsClientVip(client))
    return;
  
  //Load in cookie values for VIP players
  char buffer[16];
  GetClientCookie(client, g_CompetitiveRankingCookie, buffer, sizeof(buffer));
  g_CompetitiveRanking[client] = StringToInt(buffer);
  
  GetClientCookie(client, g_CompetitiveRankTypeCookie, buffer, sizeof(buffer));
  g_CompetitiveRankType[client] = StringToInt(buffer);
  
  GetClientCookie(client, g_ProfileRankCookie, buffer, sizeof(buffer));
  g_ProfileRank[client] = StringToInt(buffer);
  
  GetClientCookie(client, g_ActiveCoinRankCookie, buffer, sizeof(buffer));
  g_ActiveCoinRank[client] = StringToInt(buffer);
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
  if (buttons & IN_SCORE && !(GetEntProp(client, Prop_Data, "m_nOldButtons") & IN_SCORE)) {
    Handle hBuffer = StartMessageOne("ServerRankRevealAll", client);
    if (hBuffer == INVALID_HANDLE)
      LogError("Frank - ServerRankRevealAll is null in OnPlayerRunCmd");
    else
      EndMessage();
  }
  return Plugin_Continue;
}

/*********************************
 *  Events
 *********************************/
public Action Event_AnnouncePhaseEnd(Event event, const char[] name, bool dontBroadcast)
{
  Handle hBuffer = StartMessageAll("ServerRankRevealAll");
  if (hBuffer == null)
    LogError("Frank - ServerRankRevealAll is null in Event_AnnouncePhaseEnd");
  else
    EndMessage();
  
  return Plugin_Continue;
}

/*********************************
 *  Hooks
 *********************************/
public void Hook_OnThinkPost(int entity)
{
  //Set entity values
  SetEntDataArray(entity, g_CompetitiveRankingOffset, g_CompetitiveRanking, MAXPLAYERS+1, 4, true);
  SetEntDataArray(entity, g_CompetitiveRankTypeOffset, g_CompetitiveRankType, MAXPLAYERS+1, 1, true);
  SetEntDataArray(entity, g_ProfileRankOffset, g_ProfileRank, MAXPLAYERS+1, 4, true);
  SetEntDataArray(entity, g_ActiveCoinRankOffset, g_ActiveCoinRank, MAXPLAYERS+1, 4, true);
}

/*********************************
 *  Commands
 *********************************/

public Action Command_Mm(int client, int args)
{
  if (!IsClientInGame(client) || IsFakeClient(client))
    return Plugin_Handled;
  
  if (!IsClientVip(client)) {
    CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Client Not VIP");
    return Plugin_Handled;
  }
  
  //Check arguments
  bool argProvided = false;
  char arg[255];
  
  if (args >= 1) {
    argProvided = true;
    GetCmdArgString(arg, sizeof(arg));
  }
  
  //Process command
  if (argProvided) {
    if (g_CompetitiveRankType[client] == MMSTYLE_DEFAULT || g_CompetitiveRankType[client] == MMSTYLE_WINGMANRANK) {
      int index = SearchArray(g_ArrayRanks, g_ArrayRanksName, arg);
      if (index == -1)
        CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Search Found No Results", arg);
      else {
        SetClientMm(client, g_ArrayRanks.Get(index));
        char buffer[255];
        g_ArrayRanksName.GetString(index, buffer, sizeof(buffer));
        CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Generic Selected", "MM Rank", buffer);
      }
    }
    else if (g_CompetitiveRankType[client] == MMSTYLE_WINGMANLEVEL) {
      if (IsStringNumeric(arg)) {
        if (SetClientMm(client, StringToInt(arg)))
          CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Generic Selected", "Wingman Level", arg);
        else
          CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Search Found No Results", arg);
      }
      else
        CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Non Numeric Input", arg);
    }
  }
  else {
    if (g_CompetitiveRankType[client] == MMSTYLE_DEFAULT || g_CompetitiveRankType[client] == MMSTYLE_WINGMANRANK) {
      //Show menu as no argument was provided
      Menu menu = new Menu(MmMenuHandler, MenuAction_Select|MenuAction_Cancel|MenuAction_End|MenuAction_DisplayItem|MenuAction_DrawItem);
      menu.SetTitle("%t", "Menu Title MM");
      
      for (int i = 0; i < g_ArrayRanks.Length; ++i) {
        char value[255], name[255];
        IntToString(g_ArrayRanks.Get(i), value, sizeof(value));
        g_ArrayRanksName.GetString(i, name, sizeof(name));
        menu.AddItem(value, name);
      }
      
      menu.Display(client, MENU_TIME_FOREVER);
    }
    else if (g_CompetitiveRankType[client] == MMSTYLE_WINGMANLEVEL) {
      //Wait to get input as no argument was provided
      g_WaitingForSayInput[client] = true;
      CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Generic Enter Chat", "wingman level");
    }
  }
  
  return Plugin_Handled;
}

public Action Command_SetMm(int client, int args)
{
  if (!IsClientInGame(client) || IsFakeClient(client))
    return Plugin_Handled;
  
  //Check arguments
  if (args != 2) {
    char cmd[64];
    GetCmdArg(0, cmd, sizeof(cmd));
    CPrintToChat(client, "%sUsage: %s <target> \"<query>\"", CHAT_TAG_PREFIX, cmd);
    return Plugin_Handled;
  }
  
  char target[64], query[255];
  GetCmdArg(1, target, sizeof(target));
  GetCmdArg(2, query, sizeof(query));

  char targetName[MAX_TARGET_LENGTH+1];
  int targetList[MAXPLAYERS+1];
  int targetCount;
  bool tnIsMl;
  
  if ((targetCount = ProcessTargetString(
          target,
          client,
          targetList,
          MAXPLAYERS,
          COMMAND_FILTER_CONNECTED,
          targetName,
          sizeof(targetName),
          tnIsMl)) <= 0)
  {
    ReplyToTargetError(client, targetCount);
    return Plugin_Handled;
  }
  
  for (int i = 0; i < targetCount; i++) {
    if (g_CompetitiveRankType[targetList[i]] == MMSTYLE_DEFAULT || g_CompetitiveRankType[targetList[i]] == MMSTYLE_WINGMANRANK) {
      int index = SearchArray(g_ArrayRanks, g_ArrayRanksName, query);
      if (index == -1)
        CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Search Found No Results", query);
      else {
        SetClientMm(targetList[i], g_ArrayRanks.Get(index));
        char buffer[255];
        g_ArrayRanksName.GetString(index, buffer, sizeof(buffer));
        CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Generic Selected Admin", "MM Rank", buffer, targetList[i]);
      }
    }
    else if (g_CompetitiveRankType[targetList[i]] == MMSTYLE_WINGMANLEVEL) {
      if (IsStringNumeric(query)) {
        if (SetClientMm(targetList[i], StringToInt(query)))
          CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Generic Selected Admin", "Wingman Level", query, targetList[i]);
        else
          CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Search Found No Results", query);
      }
      else
        CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Non Numeric Input", query);
    }
  }
  
  return Plugin_Handled;
}

public Action Command_Mmstyle(int client, int args)
{
  if (!IsClientInGame(client) || IsFakeClient(client))
    return Plugin_Handled;
  
  if (!IsClientVip(client)) {
    CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Client Not VIP");
    return Plugin_Handled;
  }
  
  //Check arguments
  bool argProvided = false;
  char arg[255];
  
  if (args >= 1) {
    argProvided = true;
    GetCmdArgString(arg, sizeof(arg));
  }
  
  if (argProvided) {
    int index = SearchArray(g_ArrayRankTypes, g_ArrayRankTypesName, arg);
    if (index == -1)
      CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Search Found No Results", arg);
    else {
      SetClientMmStyle(client, g_ArrayRankTypes.Get(index));
      char buffer[255];
      g_ArrayRankTypesName.GetString(index, buffer, sizeof(buffer));
      CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Generic Selected", "MM Style", buffer);
    }
  }
  else {
    //Show menu as no argument was provided
    Menu menu = new Menu(MmStyleMenuHandler, MenuAction_Select|MenuAction_Cancel|MenuAction_End|MenuAction_DisplayItem|MenuAction_DrawItem);
    menu.SetTitle("%t", "Menu Title MM Style");
    
    for (int i = 0; i < g_ArrayRankTypes.Length; ++i) {
      char value[255], name[255];
      IntToString(g_ArrayRankTypes.Get(i), value, sizeof(value));
      g_ArrayRankTypesName.GetString(i, name, sizeof(name));
      menu.AddItem(value, name);
    }
    
    menu.Display(client, MENU_TIME_FOREVER);
  }
  
  return Plugin_Handled;
}

public Action Command_SetMmstyle(int client, int args)
{
  if (!IsClientInGame(client) || IsFakeClient(client))
    return Plugin_Handled;
  
  //Check arguments
  if (args != 2) {
    char cmd[64];
    GetCmdArg(0, cmd, sizeof(cmd));
    CPrintToChat(client, "%sUsage: %s <target> \"<query>\"", CHAT_TAG_PREFIX, cmd);
    return Plugin_Handled;
  }
  
  char target[64], query[255];
  GetCmdArg(1, target, sizeof(target));
  GetCmdArg(2, query, sizeof(query));

  char targetName[MAX_TARGET_LENGTH+1];
  int targetList[MAXPLAYERS+1];
  int targetCount;
  bool tnIsMl;
  
  if ((targetCount = ProcessTargetString(
          target,
          client,
          targetList,
          MAXPLAYERS,
          COMMAND_FILTER_CONNECTED,
          targetName,
          sizeof(targetName),
          tnIsMl)) <= 0)
  {
    ReplyToTargetError(client, targetCount);
    return Plugin_Handled;
  }
  
  for (int i = 0; i < targetCount; i++) {
    int index = SearchArray(g_ArrayRankTypes, g_ArrayRankTypesName, query);
    if (index == -1)
      CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Search Found No Results", query);
    else {
      SetClientMmStyle(targetList[i], g_ArrayRankTypes.Get(index));
      char buffer[255];
      g_ArrayRankTypesName.GetString(index, buffer, sizeof(buffer));
      CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Generic Selected Admin", "MM Style", buffer, targetList[i]);
    }
  }
  
  return Plugin_Handled;
}

public Action Command_Profile(int client, int args)
{
  if (!IsClientInGame(client) || IsFakeClient(client))
    return Plugin_Handled;
  
  if (!IsClientVip(client)) {
    CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Client Not VIP");
    return Plugin_Handled;
  }
  
  //Check arguments
  bool argProvided = false;
  char arg[255];
  
  if (args >= 1) {
    argProvided = true;
    GetCmdArgString(arg, sizeof(arg));
  }
  
  if (argProvided) {
    int index = SearchArray(g_ArrayProfileRanks, g_ArrayProfileRanksName, arg);
    if (index == -1)
      CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Search Found No Results", arg);
    else {
      SetClientProfile(client, g_ArrayProfileRanks.Get(index));
      char buffer[255];
      g_ArrayProfileRanksName.GetString(index, buffer, sizeof(buffer));
      CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Generic Selected", "Profile Rank", buffer);
    }
  }
  else {
    //Show menu as no argument was provided
    Menu menu = new Menu(ProfileMenuHandler, MenuAction_Select|MenuAction_Cancel|MenuAction_End|MenuAction_DisplayItem|MenuAction_DrawItem);
    menu.SetTitle("%t", "Menu Title Profile Rank");
    
    for (int i = 0; i < g_ArrayProfileRanks.Length; ++i) {
      char value[255], name[255];
      IntToString(g_ArrayProfileRanks.Get(i), value, sizeof(value));
      g_ArrayProfileRanksName.GetString(i, name, sizeof(name));
      menu.AddItem(value, name);
    }
    
    menu.Display(client, MENU_TIME_FOREVER);
  }
  
  return Plugin_Handled;
}

public Action Command_SetProfile(int client, int args)
{
  if (!IsClientInGame(client) || IsFakeClient(client))
    return Plugin_Handled;
  
  //Check arguments
  if (args != 2) {
    char cmd[64];
    GetCmdArg(0, cmd, sizeof(cmd));
    CPrintToChat(client, "%sUsage: %s <target> \"<query>\"", CHAT_TAG_PREFIX, cmd);
    return Plugin_Handled;
  }
  
  char target[64], query[255];
  GetCmdArg(1, target, sizeof(target));
  GetCmdArg(2, query, sizeof(query));

  char targetName[MAX_TARGET_LENGTH+1];
  int targetList[MAXPLAYERS+1];
  int targetCount;
  bool tnIsMl;
  
  if ((targetCount = ProcessTargetString(
          target,
          client,
          targetList,
          MAXPLAYERS,
          COMMAND_FILTER_CONNECTED,
          targetName,
          sizeof(targetName),
          tnIsMl)) <= 0)
  {
    ReplyToTargetError(client, targetCount);
    return Plugin_Handled;
  }
  
  for (int i = 0; i < targetCount; i++) {
    int index = SearchArray(g_ArrayProfileRanks, g_ArrayProfileRanksName, query);
    if (index == -1)
      CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Search Found No Results", query);
    else {
      SetClientProfile(targetList[i], g_ArrayProfileRanks.Get(index));
      char buffer[255];
      g_ArrayProfileRanksName.GetString(index, buffer, sizeof(buffer));
      CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Generic Selected Admin", "Profile Rank", buffer, targetList[i]);
    }
  }
  
  return Plugin_Handled;
}

public Action Command_Coin(int client, int args)
{
  if (!IsClientInGame(client) || IsFakeClient(client))
    return Plugin_Handled;
  
  if (!IsClientVip(client)) {
    CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Client Not VIP");
    return Plugin_Handled;
  }
  
  //Check arguments
  bool argProvided = false;
  char arg[255];
  
  if (args >= 1) {
    argProvided = true;
    GetCmdArgString(arg, sizeof(arg));
  }
  
  if (argProvided) {
    int index = SearchArray(g_ArrayCoins, g_ArrayCoinsName, arg);
    if (index == -1)
      CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Search Found No Results", arg);
    else {
      SetClientCoin(client, g_ArrayCoins.Get(index));
      char buffer[255];
      g_ArrayCoinsName.GetString(index, buffer, sizeof(buffer));
      CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Generic Selected", "Coin", buffer);
    }
  }
  else {
    //Show menu as no argument was provided
    Menu menu = new Menu(CoinMenuHandler, MenuAction_Select|MenuAction_Cancel|MenuAction_End|MenuAction_DisplayItem|MenuAction_DrawItem);
    menu.SetTitle("%t", "Menu Title Coin");
    
    for (int i = 0; i < g_ArrayCoins.Length; ++i) {
      char value[255], name[255];
      IntToString(g_ArrayCoins.Get(i), value, sizeof(value));
      g_ArrayCoinsName.GetString(i, name, sizeof(name));
      menu.AddItem(value, name);
    }
    
    menu.Display(client, MENU_TIME_FOREVER);
  }
  
  return Plugin_Handled;
}

public Action Command_SetCoin(int client, int args)
{
  if (!IsClientInGame(client) || IsFakeClient(client))
    return Plugin_Handled;
  
  //Check arguments
  if (args != 2) {
    char cmd[64];
    GetCmdArg(0, cmd, sizeof(cmd));
    CPrintToChat(client, "%sUsage: %s <target> \"<query>\"", CHAT_TAG_PREFIX, cmd);
    return Plugin_Handled;
  }
  
  char target[64], query[255];
  GetCmdArg(1, target, sizeof(target));
  GetCmdArg(2, query, sizeof(query));

  char targetName[MAX_TARGET_LENGTH+1];
  int targetList[MAXPLAYERS+1];
  int targetCount;
  bool tnIsMl;
  
  if ((targetCount = ProcessTargetString(
          target,
          client,
          targetList,
          MAXPLAYERS,
          COMMAND_FILTER_CONNECTED,
          targetName,
          sizeof(targetName),
          tnIsMl)) <= 0)
  {
    ReplyToTargetError(client, targetCount);
    return Plugin_Handled;
  }
  
  for (int i = 0; i < targetCount; i++) {
    int index = SearchArray(g_ArrayCoins, g_ArrayCoinsName, query);
    if (index == -1)
      CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Search Found No Results", query);
    else {
      SetClientCoin(targetList[i], g_ArrayCoins.Get(index));
      char buffer[255];
      g_ArrayCoinsName.GetString(index, buffer, sizeof(buffer));
      CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Generic Selected Admin", "Coin", buffer, targetList[i]);
    }
  }
  
  return Plugin_Handled;
}

/*********************************
 *  Menus And Handlers
 *********************************/
 
public int MmMenuHandler(Menu menu, MenuAction action, int client, int itemNum)
{
  char info[255];
  char display[255];
  menu.GetItem(itemNum, info, sizeof(info), _, display, sizeof(display));
  
  if (action == MenuAction_DrawItem) {
    if (g_CompetitiveRanking[client] == StringToInt(info))
      return ITEMDRAW_DISABLED;
  }
  else if (action == MenuAction_DisplayItem) {
    if (g_CompetitiveRanking[client] == StringToInt(info)) {
      //Change selected text
      char equipedText[255];
      Format(equipedText, sizeof(equipedText), "%s [*]", display);
      return RedrawMenuItem(equipedText);
    }
  }
  else if (action == MenuAction_Select) {
    SetClientMm(client, StringToInt(info));
    CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Generic Selected", "MM Rank", display);
  }
  else if (action == MenuAction_End) {
    delete menu;
  }
  
  return 0;
}

public int MmStyleMenuHandler(Menu menu, MenuAction action, int client, int itemNum)
{
  char info[255];
  char display[255];
  menu.GetItem(itemNum, info, sizeof(info), _, display, sizeof(display));
  
  if (action == MenuAction_DrawItem) {
    if (g_CompetitiveRankType[client] == StringToInt(info))
      return ITEMDRAW_DISABLED;
  }
  else if (action == MenuAction_DisplayItem) {
    if (g_CompetitiveRankType[client] == StringToInt(info)) {
      //Change selected text
      char equipedText[255];
      Format(equipedText, sizeof(equipedText), "%s [*]", display);
      return RedrawMenuItem(equipedText);
    }
  }
  else if (action == MenuAction_Select) {
    SetClientMmStyle(client, StringToInt(info));
    CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Generic Selected", "MM Style", display);
  }
  else if (action == MenuAction_End) {
    delete menu;
  }
  
  return 0;
}

public int ProfileMenuHandler(Menu menu, MenuAction action, int client, int itemNum)
{
  char info[255];
  char display[255];
  menu.GetItem(itemNum, info, sizeof(info), _, display, sizeof(display));
  
  if (action == MenuAction_DrawItem) {
    if (g_ProfileRank[client] == StringToInt(info))
      return ITEMDRAW_DISABLED;
  }
  else if (action == MenuAction_DisplayItem) {
    if (g_ProfileRank[client] == StringToInt(info)) {
      //Change selected text
      char equipedText[255];
      Format(equipedText, sizeof(equipedText), "%s [*]", display);
      return RedrawMenuItem(equipedText);
    }
  }
  else if (action == MenuAction_Select) {
    SetClientProfile(client, StringToInt(info));
    CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Generic Selected", "Profile Rank", display);
  }
  else if (action == MenuAction_End) {
    delete menu;
  }
  
  return 0;
}

public int CoinMenuHandler(Menu menu, MenuAction action, int client, int itemNum)
{
  char info[255];
  char display[255];
  menu.GetItem(itemNum, info, sizeof(info), _, display, sizeof(display));
  
  if (action == MenuAction_DrawItem) {
    if (g_ActiveCoinRank[client] == StringToInt(info))
      return ITEMDRAW_DISABLED;
  }
  else if (action == MenuAction_DisplayItem) {
    if (g_ActiveCoinRank[client] == StringToInt(info)) {
      //Change selected text
      char equipedText[255];
      Format(equipedText, sizeof(equipedText), "%s [*]", display);
      return RedrawMenuItem(equipedText);
    }
  }
  else if (action == MenuAction_Select) {
    SetClientCoin(client, StringToInt(info));
    CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Generic Selected", "Coin", display);
  }
  else if (action == MenuAction_End) {
    delete menu;
  }
  
  return 0;
}

/*********************************
 *  Helper Functions / Other
 *********************************/

void ReadConfigFile()
{
  char path[PLATFORM_MAX_PATH];
  Format(path, sizeof(path), "configs/frank.cfg");
  BuildPath(Path_SM, path, sizeof(path), path);
  
  if (!FileExists(path)) {
    SetFailState("Config file frank.cfg was not found");
  }

  //Reset current arrays
  g_ArrayRanks.Clear();
  g_ArrayRankTypes.Clear();
  g_ArrayProfileRanks.Clear();
  g_ArrayCoins.Clear();
  g_ArrayRanksName.Clear();
  g_ArrayRankTypesName.Clear();
  g_ArrayProfileRanksName.Clear();
  g_ArrayCoinsName.Clear();
  
  KeyValues kv = new KeyValues("Frank");
  
  if (!kv.ImportFromFile(path))
    return;
  
  if(kv.GotoFirstSubKey(true))
  {
    do
    {
      char sectionName[255];
      kv.GetSectionName(sectionName, sizeof(sectionName));
      
      if(kv.GotoFirstSubKey(false)) {
        do {
          char value[255], name[255];
          kv.GetSectionName(value, sizeof(value));
        
          kv.GetString(NULL_STRING, name, sizeof(name));
          
          if (StrEqual(sectionName, "Ranks", false)) {
            g_ArrayRanks.Push(StringToInt(value));
            g_ArrayRanksName.PushString(name);
          }
          else if (StrEqual(sectionName, "Rank Types", false)) {
            g_ArrayRankTypes.Push(StringToInt(value));
            g_ArrayRankTypesName.PushString(name);
          }
          else if (StrEqual(sectionName, "Profile", false)) {
            g_ArrayProfileRanks.Push(StringToInt(value));
            g_ArrayProfileRanksName.PushString(name);
          }
          else if (StrEqual(sectionName, "Coins", false)) {
            g_ArrayCoins.Push(StringToInt(value));
            g_ArrayCoinsName.PushString(name);
          }
          
        } while (kv.GotoNextKey(false));
      }
      kv.GoBack();
    
    } while(kv.GotoNextKey(true));
  
    kv.GoBack();
  }
  
  delete kv;
}

//Set a clients mm rank
bool SetClientMm(int client, int value)
{
  if (!IsClientInGame(client) || IsFakeClient(client))
    return false;
  
  //Check value parameters
  if (g_CompetitiveRankType[client] == MMSTYLE_DEFAULT || g_CompetitiveRankType[client] == MMSTYLE_WINGMANRANK) {
    if (value < 0 || value >= g_ArrayRanks.Length)
      return false;
    
    g_CompetitiveRanking[client] = value;
  }
  else if (g_CompetitiveRankType[client] == MMSTYLE_WINGMANLEVEL) {
    if (value <= 0)
      return false;
    
    g_CompetitiveRanking[client] = LevelToWingmanLevel(value);
  }
  
  char buffer[255];
  IntToString(g_CompetitiveRanking[client], buffer, sizeof(buffer));
  SetClientCookie(client, g_CompetitiveRankingCookie, buffer);
  
  return true;
}

//Set a clients mm style
bool SetClientMmStyle(int client, int value)
{
  if (!IsClientInGame(client) || IsFakeClient(client))
    return false;
  
  //Check value parameters
  if (value != MMSTYLE_DEFAULT && value != MMSTYLE_WINGMANRANK && value != MMSTYLE_WINGMANLEVEL)
    return false;
  
  g_CompetitiveRankType[client] = value;
  
  char buffer[255];
  IntToString(g_CompetitiveRankType[client], buffer, sizeof(buffer));
  SetClientCookie(client, g_CompetitiveRankTypeCookie, buffer);
  
  return true;
}

//Set a clients profile rank
bool SetClientProfile(int client, int value)
{
  if (!IsClientInGame(client) || IsFakeClient(client))
    return false;
    
  //Check value parameters
  if (value < 0 || value >= g_ArrayProfileRanks.Length)
    return false;
  
  g_ProfileRank[client] = value;
  
  char buffer[255];
  IntToString(g_ProfileRank[client], buffer, sizeof(buffer));
  SetClientCookie(client, g_ProfileRankCookie, buffer);
  
  return true;
}

//Set a clients coin
bool SetClientCoin(int client, int value)
{
  if (!IsClientInGame(client) || IsFakeClient(client))
    return false;
  
  //Check value parameters
  if (value < 0)
    return false;
  
  g_ActiveCoinRank[client] = value;
  
  char buffer[255];
  IntToString(g_ActiveCoinRank[client], buffer, sizeof(buffer));
  SetClientCookie(client, g_ActiveCoinRankCookie, buffer);
  
  return true;
}

/*********************************
 *  Stocks
 *********************************/

//Search an array value/name pair
//Uses index search first before attempting string search (exact and then partial)
//Returns array index of match if found or -1 if no results found
stock int SearchArray(ArrayList &array, ArrayList &arrayName, const char[] query)
{
  //Index search
  if (IsStringNumeric(query)) {
    int queryValue = StringToInt(query);
    
    for (int i = 0; i < array.Length; ++i) {
      if (array.Get(i) == queryValue)
        return i;
    }
    return -1;
  }
  
  //String search
  int partialMatch = -1;
  
  for (int i = 0; i < arrayName.Length; ++i) {
    //Get array name
    char name[255];
    arrayName.GetString(i, name, sizeof(name));
    
    //First find exact matches
    if (StrEqual(name, query, false))
      return i;
      
    //Then try to find partial matches
    if (StrContains(name, query, false) != -1)
      partialMatch = i;
  }
  
  return partialMatch;
}

//Given a destired level, returns the corresponding wingman level
//Relies on hardcoding first 24 levels, afterwhich each level is simply +15 the previous level
stock int LevelToWingmanLevel(int level)
{
  static int wingmanRankValues[24] = {
    1,
    2,
    4,
    7,
    10,
    13,
    16,
    20,
    24,
    28,
    32,
    37,
    42,
    47,
    52,
    58,
    65,
    73,
    82,
    92,
    103,
    115,
    128,
    142
  };

  if (level <= 24)
    return wingmanRankValues[level - 1];
  
  //Otherwise, use formula for all other levels
  //level > 24
  return 142 + ((level - 24) * 15);
}

stock bool IsClientVip(int client)
{
  if (!IsClientConnected(client) || IsFakeClient(client))
    return false;
  
  char buffer[2];
  g_Cvar_VipFlag.GetString(buffer, sizeof(buffer));

  //Empty flag means open access
  if(strlen(buffer) == 0)
    return true;

  return ClientHasCharFlag(client, buffer[0]);
}

stock bool ClientHasCharFlag(int client, char charFlag)
{
  AdminFlag flag;
  return (FindFlagByChar(charFlag, flag) && ClientHasAdminFlag(client, flag));
}

stock bool ClientHasAdminFlag(int client, AdminFlag flag)
{
  if (!IsClientConnected(client))
    return false;
  
  AdminId admin = GetUserAdmin(client);
  if (admin != INVALID_ADMIN_ID && GetAdminFlag(admin, flag, Access_Effective))
    return true;
  return false;
}

//Helper function that tells you if a string is numeric (int or floating point)
stock bool IsStringNumeric(const char[] s) {
  bool decimalFound = false;
  
  for (int i = 0; i < strlen(s); ++i) {
    if (!IsCharNumeric(s[i]))
      if (s[i] == '.') {
        //Cant have two decimal points
        if (decimalFound)
          return false;
        
        //First and last digits can't be the decimal point
        if (i == 0 || i == strlen(s) - 1)
          return false;
        
        decimalFound = true;
      }
      else if (s[i] == '-') {
        //Negative sign only allowed in first position and if more numbers follow
        if (i != 0 || strlen(s) <= 1)
          return false;
      }
      else
        return false;
  }
  
  return true;
}