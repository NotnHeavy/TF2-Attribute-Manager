//////////////////////////////////////////////////////////////////////////////
// MADE BY NOTNHEAVY. USES GPL-3, AS PER REQUEST OF SOURCEMOD               //
//////////////////////////////////////////////////////////////////////////////

// How I feel writing SourceMod plugins:
// Apdujęs einu ten, kur muzika groja
// Apsirūkęs aš ten pasijuntu lyg rojuj. 

// This uses nosoop's fork of TF2Attributes:
// https://github.com/nosoop/tf2attributes

// This also supports nosoop's custom attributes plugin, however it does not require it:
// https://github.com/nosoop/SM-TFCustAttr

// If nosoop's TF2 Econ Data plugin is loaded, configs may refer to weapons by their name
// rather than item def:
// https://github.com/nosoop/SM-TFEconData

#include <sourcemod>
#include <sdkhooks>
#include <tf2_stocks>
#include <dhooks>
#include <third_party/tf2attributes>

#undef REQUIRE_PLUGIN
#include <third_party/tf_econ_data>
#include <third_party/tf_custom_attributes>
#define REQUIRE_PLUGIN

#define AUTOSAVE_PATH "addons/sourcemod/configs/attribute_manager/autosave.cfg"
#define GLOBALS_PATH "addons/sourcemod/configs/attribute_manager.cfg"

#define PLUGIN_NAME "NotnHeavy - Attribute Manager"

//////////////////////////////////////////////////////////////////////////////
// PLUGIN INFO                                                              //
//////////////////////////////////////////////////////////////////////////////

public Plugin myinfo =
{
    name = PLUGIN_NAME,
    author = "NotnHeavy",
    description = "A simple manager for modifying TF2 weapons.",
    version = "1.0.2",
    url = "none"
};

//////////////////////////////////////////////////////////////////////////////
// GLOBALS                                                                  //
//////////////////////////////////////////////////////////////////////////////

static ArrayList g_Definitions;

static bool g_LoadedEcon;
static bool g_LoadedCustomAttributes;
static bool g_AllLoaded;
static char g_szCurrentPath[256];

enum struct ClassDefinition
{
    char m_szName[64];
    TFClassType m_eClass;
}
static ClassDefinition g_Classes[] = {
    { "scout", TFClass_Scout },
    { "soldier", TFClass_Soldier },
    { "pyro", TFClass_Pyro },
    { "demo", TFClass_DemoMan },
    { "demoman", TFClass_DemoMan },
    { "heavy", TFClass_Heavy },
    { "hwg", TFClass_Heavy },
    { "heavyweaponsguy", TFClass_Heavy },
    { "engineer", TFClass_Engineer },
    { "medic", TFClass_Medic },
    { "sniper", TFClass_Sniper },
    { "spy", TFClass_Spy }
};

static DynamicDetour DHooks_CTFPlayer_Regenerate;

static GlobalForward g_LoadedDefinitionsForward;

//////////////////////////////////////////////////////////////////////////////
// DEFINITION                                                               //
//////////////////////////////////////////////////////////////////////////////

// An individiual definition for an item definition index (or weapon name if TF2 Econ Data is loaded), 
// for modifying its runtime attributes.
// Can you believe that I'm actually using an enum struct for the first time since fucking ever?
enum struct Definition
{
    char m_szName[64];
    int m_iItemDef;
    int m_iIndex;
    bool m_bOnlyIterateItemViewAttributes;
    TFClassType m_eClass;
    ArrayList m_Attributes;
    ArrayList m_CustomAttributes;

    void GetAttribute(Attribute attrib, const char[] szName, bool custom = false)
    {
        if (custom)
        {
            for (int i = 0, size = this.m_CustomAttributes.Length; i < size; ++i)
            {
                Attribute indexed;
                this.m_CustomAttributes.GetArray(i, indexed);
                if (strcmp(indexed.m_szName, szName, false) == 0)
                {
                    attrib = indexed;
                    return;
                }
            }
            return;
        }

        for (int i = 0, size = this.m_Attributes.Length; i < size; ++i)
        {
            Attribute indexed;
            this.m_Attributes.GetArray(i, indexed);
            if (strcmp(indexed.m_szName, szName, false) == 0)
            {
                attrib = indexed;
                return;
            }
        }
    }

    void WriteAttribute(const char[] szName, const char[] szValue, bool custom = false)
    {
        Attribute attrib;
        strcopy(attrib.m_szName, strlen(szName) + 1, szName);
        strcopy(attrib.m_szValue, strlen(szValue) + 1, szValue);
        TrimString(attrib.m_szName);
        TrimString(attrib.m_szValue);
        
        if (custom)
        {
            for (int i = 0, size = this.m_CustomAttributes.Length; i < size; ++i)
            {
                Attribute indexed;
                this.m_CustomAttributes.GetArray(i, indexed);
                if (strcmp(indexed.m_szName, szName, false) == 0)
                {
                    this.m_CustomAttributes.SetArray(i, attrib);
                    return;
                }
            }
            this.m_CustomAttributes.PushArray(attrib);
        }
        else
        {
            for (int i = 0, size = this.m_Attributes.Length; i < size; ++i)
            {
                Attribute indexed;
                this.m_Attributes.GetArray(i, indexed);
                if (strcmp(indexed.m_szName, szName, false) == 0)
                {
                    this.m_Attributes.SetArray(i, attrib);
                    return;
                }
            }
            this.m_Attributes.PushArray(attrib);
        }
    }

    void PushToArray()
    {
        this.m_iIndex = g_Definitions.Length;
        g_Definitions.PushArray(this);
    }

    void Delete()
    {
        delete this.m_Attributes;
        delete this.m_CustomAttributes;
        g_Definitions.Erase(this.m_iIndex);
        
        // Correct all indexes from this index.
        for (int i = this.m_iIndex, size = g_Definitions.Length; i < size; ++i)
        {
            Definition def;
            g_Definitions.GetArray(i, def);
            --def.m_iIndex;
            g_Definitions.SetArray(i, def);
        }
    }
}

enum struct Attribute
{   
    char m_szName[64];
    char m_szValue[64];
}

static void CreateDefinition(Definition def, char szName[64], int iItemDef = -1, TFClassType eClass = TFClass_Unknown)
{
    def.m_szName = szName;
    def.m_iItemDef = iItemDef;
    def.m_eClass = eClass;
    def.m_Attributes = new ArrayList(sizeof(Attribute));
    def.m_CustomAttributes = new ArrayList(sizeof(Attribute));
    def.m_bOnlyIterateItemViewAttributes = false;
}

static bool FindDefinition(Definition def, int iItemDef)
{
    if (iItemDef == TF_ITEMDEF_DEFAULT)
        return false;
    
    for (int i = 0, size = g_Definitions.Length; i < size; ++i)
    {
        Definition indexed;
        g_Definitions.GetArray(i, indexed);
        if (indexed.m_iItemDef == iItemDef)
        {
            def = indexed;
            return true;
        }
    }
    return false;
}

static bool FindDefinitionByName(Definition def, char szName[64])
{
    for (int i = 0, size = g_Definitions.Length; i < size; ++i)
    {
        Definition indexed;
        g_Definitions.GetArray(i, indexed);
        if (strcmp(szName, indexed.m_szName, false) == 0)
        {
            def = indexed;
            return true;
        }
    }
    return false;
}

static bool FindDefinitionByClass(Definition def, TFClassType eClass)
{
    for (int i = 0, size = g_Definitions.Length; i < size; ++i)
    {
        Definition indexed;
        g_Definitions.GetArray(i, indexed);
        if (indexed.m_eClass == eClass)
        {
            def = indexed;
            return true;
        }
    }
    return false;
}

static bool FindDefinitionComplex(Definition def, char szName[64])
{
    int itemdef = StringToInt(szName);
    if (itemdef > 0 || EqualsZero(szName))
        return FindDefinition(def, itemdef);

    if (FindDefinitionByName(def, szName))
        return true;

    itemdef = (g_LoadedEcon) ? RetrieveItemDefByName(szName) : TF_ITEMDEF_DEFAULT;
    if (itemdef == TF_ITEMDEF_DEFAULT)
    {
        for (int i = 0; i < sizeof(g_Classes); ++i)
        {
            if (strcmp(g_Classes[i].m_szName, szName, false) == 0)
                return FindDefinitionByClass(def, g_Classes[i].m_eClass);
        }
        return false;
    }
    
    return FindDefinition(def, itemdef);
}

//////////////////////////////////////////////////////////////////////////////
// INITIALISATION                                                           //
//////////////////////////////////////////////////////////////////////////////

public void OnPluginStart()
{
    LoadTranslations("common.phrases");
    g_AllLoaded = false;
 
    // Load gamedata.
    GameData config = LoadGameConfigFile("sm-tf2.games");
    if (!config)
        SetFailState("Failed to load gamedata from \"sm-tf2.games.txt\". Your SourceMod install is corrupted and requires reinstalling.");

    // Set up detour and enable it.
    DHooks_CTFPlayer_Regenerate = new DynamicDetour(Address_Null, CallConv_THISCALL, ReturnType_Void, ThisPointer_CBaseEntity);
    DHooks_CTFPlayer_Regenerate.AddParam(HookParamType_Bool);
    DHooks_CTFPlayer_Regenerate.SetFromConf(config, SDKConf_Signature, "Regenerate");
    DHooks_CTFPlayer_Regenerate.Enable(Hook_Pre, CTFPlayer_Regenerate);

    // Set up global forwrads.
    g_LoadedDefinitionsForward = new GlobalForward("AttributeManager_OnDefinitionsLoaded", ET_Ignore, Param_Cell);

    delete config;
}

public void OnPluginEnd()
{
    if (FileExists(AUTOSAVE_PATH) || g_Definitions.Length > 0)
        ExportKeyValues(AUTOSAVE_PATH);
}

static void LoadDefaults()
{
    strcopy(g_szCurrentPath, sizeof(g_szCurrentPath), AUTOSAVE_PATH);
}

//////////////////////////////////////////////////////////////////////////////
// LIBRARIES                                                                //
//////////////////////////////////////////////////////////////////////////////

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    // Mark custom library natives as optional.
    MarkNativeAsOptional("TF2Econ_GetItemList");
    MarkNativeAsOptional("TF2Econ_GetItemName");
    MarkNativeAsOptional("TF2Econ_GetAttributeName");
    MarkNativeAsOptional("TF2CustAttr_SetInt");
    MarkNativeAsOptional("TF2CustAttr_SetFloat");
    MarkNativeAsOptional("TF2CustAttr_SetString");

    // Register natives within this plugin.
    CreateNative("AttributeManager_GetDefinitions", Native_AttributeManager_GetDefinitions);
    CreateNative("AttributeManager_SetDefinitions", Native_AttributeManager_SetDefinitions);
    CreateNative("AttributeManager_Write", Native_AttributeManager_Write);
    CreateNative("AttributeManager_Load", Native_AttributeManager_Load);
    CreateNative("AttributeManager_Refresh", Native_AttributeManager_Refresh);
    CreateNative("AttributeManager_GetLoadedConfig", Native_AttributeManager_GetLoadedConfig);

    // Register this plugin as a library.
    RegPluginLibrary("NotnHeavy - Attribute Manager");
    return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
    // Continue plugin loading here.
    PrintToServer("--------------------------------------------------------");
    g_LoadedEcon = LibraryExists("tf_econ_data");
    g_LoadedCustomAttributes = LibraryExists("tf2custattr");

    // Parse attribute_manager.cfg.
    if (!FileExists(GLOBALS_PATH, true))
    {
        LoadDefaults();
        PrintToServer("\"%s\" doesn't exist, not parsing globals...\n", GLOBALS_PATH);
    }
    else
    {
        PrintToServer("Parsing attribute_manager.cfg.");

        KeyValues kv = new KeyValues("Settings");
        kv.ImportFromFile(GLOBALS_PATH);
        kv.GotoFirstSubKey();
        
        kv.GetString("defaultconfig", g_szCurrentPath, sizeof(g_szCurrentPath), GLOBALS_PATH);

        if (strlen(g_szCurrentPath) == 0)
        {
            strcopy(g_szCurrentPath, sizeof(g_szCurrentPath), AUTOSAVE_PATH);
            PrintToServer("Parameter \"defaultconfig\" blank, defaulting to \"%s\"...", AUTOSAVE_PATH);
        }
        else if (strcmp(g_szCurrentPath, GLOBALS_PATH) != 0)
            Format(g_szCurrentPath, sizeof(g_szCurrentPath), "addons/sourcemod/configs/attribute_manager/%s.cfg", g_szCurrentPath);
        PrintToServer("g_szCurrentPath set to \"%s\".", g_szCurrentPath);

        PrintToServer("");
        delete kv;
    }
    
    // Create the ArrayList and fill it with definitions, if an autosave is present.
    g_Definitions = new ArrayList(sizeof(Definition));
    if (FileExists(g_szCurrentPath, true))
        ParseDefinitions(g_szCurrentPath);
    else
        PrintToServer("\"%s\" doesn't exist, not parsing any definitions...", g_szCurrentPath);
    Call_StartForward(g_LoadedDefinitionsForward);
    Call_PushCell(true);
    Call_Finish();

    // Create a list of commands server admins can use.
    RegAdminCmd("attrib_write", attrib_write, ADMFLAG_GENERIC, "Creates a file (if it doesn't exist beforehand) and writes all definitions to it. If no name is provided, it will write to autosave.cfg\nattrib_write configname");
    RegAdminCmd("attrib_loadconfig", attrib_loadconfig, ADMFLAG_GENERIC, "Load definitions from an existing config\nattrib_loadconfig configname");
    RegAdminCmd("attrib_load", attrib_loadconfig, ADMFLAG_GENERIC, "Load definitions from an existing config\attrib_load configname");
    RegAdminCmd("attrib_listdefinitions", attrib_listdefinitions, ADMFLAG_GENERIC, "List all the names of the current definitions\nattrib_listdefinitions");
    RegAdminCmd("attrib_listdefs", attrib_listdefinitions, ADMFLAG_GENERIC, "List all the names of the current definitions\nattrib_listdefs");
    RegAdminCmd("attrib_list", attrib_listdefinitions, ADMFLAG_GENERIC, "List all the names of the current definitions\nattrib_list");
    RegAdminCmd("attrib_add", attrib_add, ADMFLAG_GENERIC, "Add a new definition (weapon, class or custom tag). If specified, it can inherit from another definition\nattrib_add name [inherits]");
    RegAdminCmd("attrib_remove", attrib_remove, ADMFLAG_GENERIC, "Remove a definition (weapon, class or custom tag)\nattrib_remove name");
    RegAdminCmd("attrib_delete", attrib_remove, ADMFLAG_GENERIC, "Remove a definition (weapon, class or custom tag)\nattrib_delete name");
    RegAdminCmd("attrib_del", attrib_remove, ADMFLAG_GENERIC, "Remove a definition (weapon, class or custom tag)\nattrib_del name");
    RegAdminCmd("attrib_modify", attrib_modify, ADMFLAG_GENERIC, "Modify a definition's property\nattrib_modify name property value");
    RegAdminCmd("attrib_refresh", attrib_refresh, ADMFLAG_GENERIC, "Reparse all definitions\nattrib_refresh");
    RegAdminCmd("attrib_listdefinition", attrib_listdefinition, ADMFLAG_GENERIC, "List the properties and attributes of a definition\nattrib_listdefinition name");
    RegAdminCmd("attrib_listdef", attrib_listdefinition, ADMFLAG_GENERIC, "List the properties and attributes of a definition\nattrib_listdef name");
    RegAdminCmd("attrib_addattribute", attrib_addattribute, ADMFLAG_GENERIC, "Add an attribute to a definition\nattrib_addattribute name (attribute name | attribute def index if TF2 Econ Data is loaded) value");
    RegAdminCmd("attrib_addattrib", attrib_addattribute, ADMFLAG_GENERIC, "Add an attribute to a definition\nattrib_addattrib name (attribute name | attribute def index if TF2 Econ Data is loaded) value");
    RegAdminCmd("attrib_removeattribute", attrib_removeattribute, ADMFLAG_GENERIC, "Remove an attribute from a definition\nattrib_removeattribute name (attribute name | attribute def index if TF2 Econ Data is loaded)");
    RegAdminCmd("attrib_removeattrib", attrib_removeattribute, ADMFLAG_GENERIC, "Remove an attribute from a definition\nattrib_removeattrib name (attribute name | attribute def index if TF2 Econ Data is loaded)");
    RegAdminCmd("attrib_addcustomattribute", attrib_addcustomattribute, ADMFLAG_GENERIC, "Add a custom attribute to a definition\nattrib_addcustomattribute name attribute value");
    RegAdminCmd("attrib_addcustomattrib", attrib_addcustomattribute, ADMFLAG_GENERIC, "Add a custom attribute to a definition\nattrib_addcustomattrib name attribute value");
    RegAdminCmd("attrib_addcustom", attrib_addcustomattribute, ADMFLAG_GENERIC, "Add a custom attribute to a definition\nattrib_addcustom name attribute value");
    RegAdminCmd("attrib_removecustomattribute", attrib_removecustomattribute, ADMFLAG_GENERIC, "Remove a custom attribute from a definition\nattrib_removecustomattribute name attribute");
    RegAdminCmd("attrib_removecustomattrib", attrib_removecustomattribute, ADMFLAG_GENERIC, "Remove a custom attribute from a definition\nattrib_removecustomattrib name attribute");
    RegAdminCmd("attrib_removecustom", attrib_removecustomattribute, ADMFLAG_GENERIC, "Remove a custom attribute from a definition\nattrib_removecustom name attribute");

    // Show to the server maintainer what plugins are currently loaded.
    PrintToServer("\nTF2 Econ Data: %s", ((g_LoadedEcon) ? "loaded" : "not loaded"));
    PrintToServer("Custom Attributes Framework: %s", ((g_LoadedCustomAttributes) ? "loaded" : "not loaded"));

    // Run OnEntityCreated() on existing entities.
    for (int i = 1; i <= 2048; ++i)
    {
        if (IsValidEntity(i))
            OnEntityCreated(i, "");
    }

    g_AllLoaded = true;
    PrintToServer("\n\"%s\" has loaded.\n--------------------------------------------------------", PLUGIN_NAME);
}

public void OnLibraryAdded(const char[] name)
{
    if (!g_AllLoaded)
        return;

    if (strcmp("tf_econ_data", name) == 0)
    {
        g_LoadedEcon = true;
        if (FileExists(g_szCurrentPath, true))
            ParseDefinitions(g_szCurrentPath)
    }
    else if (strcmp("tf2custattr", name) == 0)
        g_LoadedCustomAttributes = true;
}

public void OnLibraryRemoved(const char[] name)
{
    if (strcmp("tf_econ_data", name) == 0)
        g_LoadedEcon = false;
    else if (strcmp("tf2custattr", name) == 0)
        g_LoadedCustomAttributes = false;
}

//////////////////////////////////////////////////////////////////////////////
// CONFIG PARSER                                                            //
//////////////////////////////////////////////////////////////////////////////

static bool EqualsZero(const char[] value)
{
    bool foundPeriod = false;
    int size = strlen(value);
    if (size == 0)
        return false;
    
    for (int i = 0; i < size; ++i)
    {
        if (value[i] == '.')
        {
            if (foundPeriod)
                return false;
            foundPeriod = true;
            continue;
        }
        if (value[i] != '0')
            return false;
    }
    return true;
}

static void ParseDefinitions(const char[] path)
{
    if (!FileExists(path, true))
        return;
    g_Definitions.Clear();
    PrintToServer("Parsing definitions at \"%s\".", path);

    KeyValues kv = new KeyValues("Attributes");
    kv.ImportFromFile(path);
    kv.GotoFirstSubKey();

    char section[64];
    char key[64];
    char value[64];
    do
    {
        kv.GetSectionName(section, sizeof(section));
        TrimString(section);
        int itemdef = TF_ITEMDEF_DEFAULT;
        TFClassType eClass = TFClass_Unknown;

        if (g_LoadedEcon)
            itemdef = RetrieveItemDefByName(section);
        if (itemdef == TF_ITEMDEF_DEFAULT)
        {
            itemdef = StringToInt(section);
            if ((itemdef == 0 && !EqualsZero(section)) || ((itemdef & 0xFFFF) != itemdef))
            {
                //ThrowError("[%s]: Could not find item definition index for \"%s\" in key values file \"%s\".", PLUGIN_NAME, section, path);
                itemdef = TF_ITEMDEF_DEFAULT;
                for (int i = 0; i < sizeof(g_Classes); ++i)
                {
                    ClassDefinition class;
                    class = g_Classes[i];
                    if (strcmp(class.m_szName, section, false) == 0)
                        eClass = class.m_eClass;
                }
            }
        }

        char inherits_string[64];
        kv.GetString("#inherits", inherits_string, sizeof(inherits_string));
        TrimString(inherits_string);

        Definition inherits_def;
        Definition def;
        CreateDefinition(def, section, itemdef, eClass);
        if (FindDefinitionComplex(inherits_def, inherits_string))
        {
            delete def.m_Attributes;
            delete def.m_CustomAttributes;
            def.m_Attributes = inherits_def.m_Attributes.Clone();
            def.m_CustomAttributes = inherits_def.m_CustomAttributes.Clone();
            def.m_bOnlyIterateItemViewAttributes = inherits_def.m_bOnlyIterateItemViewAttributes;
        }
        def.m_bOnlyIterateItemViewAttributes = !view_as<bool>(kv.GetNum("#keepattributes", !def.m_bOnlyIterateItemViewAttributes));

        if (kv.GotoFirstSubKey(false))
        {
            do
            {
                kv.GetSectionName(key, sizeof(key));
                kv.GetString(NULL_STRING, value, sizeof(value));
                TrimString(key);
                TrimString(value);

                if (key[0] == '#')
                {
                    if (strcmp(key, "#custom_attributes") == 0 && kv.GotoFirstSubKey(false))
                    {
                        do
                        {
                            kv.GetSectionName(key, sizeof(key));
                            kv.GetString(NULL_STRING, value, sizeof(value));
                            TrimString(key);
                            TrimString(value);
                            def.WriteAttribute(key, value, true);
                        }
                        while (kv.GotoNextKey(false));
                        kv.GoBack();
                    }
                    continue;
                }
                
                def.WriteAttribute(key, value);
            }
            while (kv.GotoNextKey(false));
            kv.GoBack();
        }

        def.PushToArray();
        PrintToServer("Parsed definition %s (%s: %i)", section, ((eClass != TFClass_Unknown) ? "class enum" : "item definition index"), ((eClass != TFClass_Unknown) ? view_as<int>(eClass) : itemdef));
    }
    while (kv.GotoNextKey());
    delete kv;

    // Call AttributeManager_OnDefinitionsLoaded().
    Call_StartForward(g_LoadedDefinitionsForward);
    Call_PushCell(false);
    Call_Finish();
}

//////////////////////////////////////////////////////////////////////////////
// ECON                                                                     //
//////////////////////////////////////////////////////////////////////////////

// Convert a string to lower case.
void StringToLower(const char[] buffer, char[] output, int maxlength)
{
	for (int i = 0; i < maxlength; ++i)
	{
		if (buffer[i] == 0)
		{
			output[i] = 0;
			break;
		}
		output[i] = CharToLower(buffer[i]);
	}
}

// Retrieve the item definition index of a weapon by its internal name.
// Requires TF2 Econ Data.
static int RetrieveItemDefByName(const char[] name)
{
    static StringMap definitions;
    if (definitions)
    {
        int value = TF_ITEMDEF_DEFAULT;
        char buffer[64];
        strcopy(buffer, sizeof(buffer), name);
        StringToLower(buffer, buffer, sizeof(buffer));
        return (definitions.GetValue(buffer, value)) ? value : TF_ITEMDEF_DEFAULT;
    }

    definitions = new StringMap();
    ArrayList list = TF2Econ_GetItemList();
    char buffer[64];
    for (int i = 0, size = list.Length; i < size; ++i)
    {
        int itemdef = list.Get(i);
        TF2Econ_GetItemName(itemdef, buffer, sizeof(buffer));
        StringToLower(buffer, buffer, sizeof(buffer));
        definitions.SetValue(buffer, itemdef);

        // Make an additional entry if the first word is "The ".
        if (StrContains(buffer, "the ") == 0)
        {
            char buffer2[64];
            for (int i2 = 4, size2 = strlen(buffer) + 1; i2 < size2; ++i2)
            {
                buffer2[i2 - 4] = buffer[i2];
            }
            definitions.SetValue(buffer2, itemdef);
        }
    }
    delete list;
    return RetrieveItemDefByName(name);
}

//////////////////////////////////////////////////////////////////////////////
// ATTRIBUTES                                                               //
//////////////////////////////////////////////////////////////////////////////

static void SetAttributes(int entity, Definition def)
{
    // Iterate through TF2 attributes.
    for (int i = 0, size = def.m_Attributes.Length; i < size; ++i)
    {
        Attribute attrib;
        def.m_Attributes.GetArray(i, attrib);

        float value = StringToFloat(attrib.m_szValue);
        if (value != 0 || EqualsZero(attrib.m_szValue))
        {
            TF2Attrib_SetByName(entity, attrib.m_szName, value);
            continue;
        }
        TF2Attrib_SetFromStringValue(entity, attrib.m_szName, attrib.m_szValue);
    }

    // Iterate through custom attributes.
    if (def.m_CustomAttributes.Length > 0)
    {
        if (g_LoadedCustomAttributes)
        {
            for (int i = 0, size = def.m_CustomAttributes.Length; i < size; ++i)
            {
                Attribute attrib;
                def.m_CustomAttributes.GetArray(i, attrib);

                int value = StringToInt(attrib.m_szValue);
                if (value != 0 || EqualsZero(attrib.m_szValue))
                {
                    TF2CustAttr_SetInt(entity, attrib.m_szName, value);
                    continue;
                }

                float value_float = StringToFloat(attrib.m_szValue);
                if (value_float != 0)
                {
                    TF2CustAttr_SetFloat(entity, attrib.m_szName, value_float);
                    continue;
                }
                
                TF2CustAttr_SetString(entity, attrib.m_szName, attrib.m_szValue);
            }
        }
        else
        {
            char buffer[64];
            Format(buffer, sizeof(buffer), "%s %i", ((def.m_eClass != TFClass_Unknown) ? "Item definition index" : "Class"), ((def.m_eClass != TFClass_Unknown) ? view_as<int>(def.m_eClass) : def.m_iItemDef));
            PrintToServer("[%s] WARNING! Item definition index %s has custom attributes, however tf_custom_attributes.smx is not loaded!", PLUGIN_NAME, buffer);
        }
    }
}

static void SortPlayerAttributes(int entity)
{
    TFClassType class = TF2_GetPlayerClass(entity);
    Definition def;
    TF2Attrib_RemoveAll(entity);
    if (FindDefinitionByClass(def, class))
        SetAttributes(entity, def);
}

//////////////////////////////////////////////////////////////////////////////
// FILES                                                                    //
//////////////////////////////////////////////////////////////////////////////

static void ExportKeyValues(const char[] buffer)
{
    KeyValues kv = new KeyValues("Attributes");
    for (int i = 0, size = g_Definitions.Length; i < size; ++i)
    {
        char value[64];
        Definition def;
        g_Definitions.GetArray(i, def);
        
        // If an itemdef is provided, use that as the name instead of the weapon's name.
        if (def.m_iItemDef != TF_ITEMDEF_DEFAULT)
        {
            char itemdef_string[64];
            IntToString(def.m_iItemDef, itemdef_string, sizeof(itemdef_string));
            kv.JumpToKey(itemdef_string, true);
        }
        else
            kv.JumpToKey(def.m_szName, true);

        IntToString(view_as<int>(!def.m_bOnlyIterateItemViewAttributes), value, sizeof(value));
        kv.SetString("#keepattributes", value);
        
        for (int i2 = 0, size2 = def.m_Attributes.Length; i2 < size2; ++i2)
        {
            Attribute attrib;
            def.m_Attributes.GetArray(i2, attrib);
            kv.SetString(attrib.m_szName, attrib.m_szValue);
        }

        int size3 = def.m_CustomAttributes.Length;
        if (size3 > 0)
        {
            kv.JumpToKey("#custom_attributes", true);
            for (int i3 = 0; i3 < size3; ++i3)
            {
                Attribute attrib;
                def.m_CustomAttributes.GetArray(i3, attrib);
                kv.SetString(attrib.m_szName, attrib.m_szValue);
            }
            kv.Rewind();
        }
        kv.Rewind();
    }
    kv.ExportToFile(buffer);
    delete kv;
}

//////////////////////////////////////////////////////////////////////////////
// FORWARDS                                                                 //
//////////////////////////////////////////////////////////////////////////////

public void OnEntityCreated(int entity, const char[] classname)
{
    if (HasEntProp(entity, Prop_Send, "m_iItemDefinitionIndex"))
        SDKHook(entity, SDKHook_Spawn, CEconEntity_Spawn);

    if (1 <= entity <= MaxClients)
        SDKHook(entity, SDKHook_Spawn, CTFPlayer_Spawn);
}

//////////////////////////////////////////////////////////////////////////////
// SDKHOOKS                                                                 //
//////////////////////////////////////////////////////////////////////////////

// Pre-call CEconEntity::Spawn().
// Find the entity's definition and insert its new attributes.
static Action CEconEntity_Spawn(int entity)
{
    int itemdef = GetEntProp(entity, Prop_Send, "m_iItemDefinitionIndex");
    Definition def;
    if (FindDefinition(def, itemdef))
    {
        // Should the entity's attributes be wiped out?
        SetEntProp(entity, Prop_Send, "m_bOnlyIterateItemViewAttributes", def.m_bOnlyIterateItemViewAttributes);
        SetAttributes(entity, def);
    }
    return Plugin_Continue;
}

// Pre-call CTFPlayer::Spawn().
// Sort out class-specific attributes set via the provided config's definitions.
// The same is done on resupply.
static Action CTFPlayer_Spawn(int entity)
{
    SortPlayerAttributes(entity);
    return Plugin_Continue;
}

//////////////////////////////////////////////////////////////////////////////
// DHOOKS                                                                   //
//////////////////////////////////////////////////////////////////////////////

// Pre-call CTFPlayer::Regenerate().
// Sort out class-specific attributes set via the provided config's definitions.
static MRESReturn CTFPlayer_Regenerate(int entity, DHookParam parameters)
{
    SortPlayerAttributes(entity);
    return MRES_Ignored;
}

//////////////////////////////////////////////////////////////////////////////
// COMMANDS                                                                 //
//////////////////////////////////////////////////////////////////////////////

// Creates a file (if it doesn't exist beforehand) and writes all definitions to it. 
// If no name is provided, it will write to autosave.cfg
Action attrib_write(int client, int args)
{
    // Check for a passed argument.
    char arg[PLATFORM_MAX_PATH];
    char buffer[PLATFORM_MAX_PATH];
    if (args == 0)
        strcopy(buffer, sizeof(buffer), AUTOSAVE_PATH);
    else
    {
        GetCmdArg(1, arg, sizeof(arg));
        TrimString(arg);
        Format(buffer, sizeof(buffer), "addons/sourcemod/configs/attribute_manager/%s.cfg", arg);
    }

    // Open a new file.
    if (!DirExists("addons/sourcemod/configs/attribute_manager/", true))
        CreateDirectory("addons/sourcemod/configs/attribute_manager/", .use_valve_fs = true);

    File file = OpenFile(buffer, "w", true);
    if (!file)
    {
        ReplyToCommand(client, "[Attribute Manager]: Unable to create file \"%s.cfg\"", arg);
        return Plugin_Continue;
    }
    delete file;

    // Create a KeyValues pair and export it to the file.
    ExportKeyValues(buffer);

    // Return to command.
    ReplyToCommand(client, "[Attribute Manager]: Finished writing to \"%s\"", ((strlen(arg) > 0) ? arg : "autosave"));
    return Plugin_Continue;
}

// Load definitions from an existing config.
Action attrib_loadconfig(int client, int args)
{
    // Check for a passed argument.
    if (args == 0)
    {
        ReplyToCommand(client, "[Attribute Manager]: attrib_loadconfig configname");
        return Plugin_Continue;
    }
    char arg[PLATFORM_MAX_PATH];
    char buffer[PLATFORM_MAX_PATH];
    GetCmdArg(1, arg, sizeof(arg));
    TrimString(arg);
    Format(buffer, sizeof(buffer), "addons/sourcemod/configs/attribute_manager/%s.cfg", arg);

    // Check if it exists.
    if (!FileExists(buffer))
    {
        ReplyToCommand(client, "[Attribute Manager]: File \"%s.cfg\" does not exist", arg);
        return Plugin_Continue;
    }

    // Load all definitions from the file.
    ParseDefinitions(buffer);
    strcopy(g_szCurrentPath, sizeof(g_szCurrentPath), buffer);

    // Return to command.
    ReplyToCommand(client, "[Attribute Manager]: Loaded config \"%s.cfg\"", arg);
    return Plugin_Continue;
}

// List all the names of the current definitions
Action attrib_listdefinitions(int client, int args)
{
    if (g_Definitions.Length == 0)
    {
        ReplyToCommand(client, "[Attribute Manager]: No definitions currently.");
        return Plugin_Continue;
    }

    for (int i = 0, size = g_Definitions.Length; i < size; ++i)
    {
        Definition def;
        g_Definitions.GetArray(i, def);

        // Get weapon name if the definition is a weapon.
        char buffer[64];
        if (def.m_iItemDef != TF_ITEMDEF_DEFAULT)
        {
            char name[64];
            TF2Econ_GetItemName(def.m_iItemDef, name, sizeof(name));
            Format(buffer, sizeof(buffer), "Weapon - %s", name);
        }

        ReplyToCommand(client, "[Attribute Manager]: Definition \"%s\" (%s)", def.m_szName, ((def.m_iItemDef != TF_ITEMDEF_DEFAULT) ? buffer : ((def.m_eClass != TFClass_Unknown) ? "Class" : "Custom tag")));
    }
    return Plugin_Continue;
}

// Add a new definition (weapon, class or custom tag).
// If specified, it can inherit from another definition
Action attrib_add(int client, int args)
{
    // Retrieve the name (and definition to inherit from) provided.
    if (args < 1)
    {
        ReplyToCommand(client, "[Attribute Manager]: attrib_add name [inherits]");
        return Plugin_Continue;
    }
    char arg[64], inherits_string[64];
    GetCmdArg(1, arg, sizeof(arg));
    GetCmdArg(2, inherits_string, sizeof(inherits_string));
    TrimString(arg);
    TrimString(inherits_string);

    // Check if the definition already exists.
    Definition throwaway;
    if (FindDefinitionComplex(throwaway, arg))
    {
        ReplyToCommand(client, "[Attribute Manager]: Definition %s already exists!", arg);
        return Plugin_Continue;
    }

    // Create the definition.
    int itemdef = TF_ITEMDEF_DEFAULT;
    TFClassType eClass = TFClass_Unknown;

    if (g_LoadedEcon)
        itemdef = RetrieveItemDefByName(arg);
    if (itemdef == TF_ITEMDEF_DEFAULT)
    {
        itemdef = StringToInt(arg);
        if ((itemdef == 0 && !EqualsZero(arg)) || ((itemdef & 0xFFFF) != itemdef))
        {
            itemdef = TF_ITEMDEF_DEFAULT;
            for (int i = 0; i < sizeof(g_Classes); ++i)
            {
                ClassDefinition class;
                class = g_Classes[i];
                if (strcmp(class.m_szName, arg, false) == 0)
                    eClass = class.m_eClass;
            }
        }
    }

    Definition inherits_def;
    Definition def;
    CreateDefinition(def, arg, itemdef, eClass);
    if (FindDefinitionComplex(inherits_def, inherits_string))
    {
        delete def.m_Attributes;
        delete def.m_CustomAttributes;
        def.m_Attributes = inherits_def.m_Attributes.Clone();
        def.m_CustomAttributes = inherits_def.m_CustomAttributes.Clone();
        def.m_bOnlyIterateItemViewAttributes = inherits_def.m_bOnlyIterateItemViewAttributes;
    }
    def.PushToArray();
    ReplyToCommand(client, "[Attribtute Manager]: Successfully added new definition \"%s\"", def.m_szName);
    return Plugin_Continue;
}

// Remove a definition (weapon, class or custom tag)
Action attrib_remove(int client, int args)
{
    // Retrieve the name provided.
    if (args < 1)
    {
        char buffer[64];
        GetCmdArg(0, buffer, sizeof(buffer));
        ReplyToCommand(client, "[Attribute Manager]: %s name", buffer);
        return Plugin_Continue;
    }
    char arg[64];
    GetCmdArg(1, arg, sizeof(arg));
    TrimString(arg);

    // Check that the definition actually exists.
    Definition def;
    if (!FindDefinitionComplex(def, arg))
    {
        ReplyToCommand(client, "[Attribute Manager]: Definition %s does not exist", arg);
        return Plugin_Continue;
    }

    // Delete the definition.
    def.Delete();
    ReplyToCommand(client, "[Attribute Manager]: Successfully deleted definition %s", arg);
    return Plugin_Continue;
}

// Modify a definition's property
Action attrib_modify(int client, int args)
{
    // Retrieve the name, property and value
    if (args != 3)
    {
        ReplyToCommand(client, "[Attribute Manager]: attrib_modify name property value");
        return Plugin_Continue;
    }
    char name[64], prop[64], value[64];
    GetCmdArg(1, name, sizeof(name));
    GetCmdArg(2, prop, sizeof(prop));
    GetCmdArg(3, value, sizeof(value));
    TrimString(name);
    TrimString(prop);
    TrimString(value);

    // Convert the value to an int if it is a boolean.
    if (strcmp(value, "true", false) == 0)
        value = "1";
    else if (strcmp(value, "false", false) == 0)
        value = "0";

    // Check that the definition actually exists.
    Definition def;
    if (!FindDefinitionComplex(def, name))
    {
        ReplyToCommand(client, "[Attribute Manager]: Definition %s does not exist", name);
        return Plugin_Continue;
    }

    // Modify the property.
    if (strcmp(prop, "keepattributes", false) == 0)
        def.m_bOnlyIterateItemViewAttributes = !view_as<bool>(StringToInt(value));
    else
    {
        ReplyToCommand(client, "[Attribute Manager]: Property \"%s\" does not exist", prop);
        return Plugin_Continue;
    }

    g_Definitions.SetArray(def.m_iIndex, def);
    ReplyToCommand(client, "[Attribute Manager]: Successfully modified property \"%s\" for %s", prop, def.m_szName);
    return Plugin_Continue;
}

// Reparse all definitions
Action attrib_refresh(int client, int args)
{
    ExportKeyValues(g_szCurrentPath);
    ParseDefinitions(g_szCurrentPath);
    ReplyToCommand(client, "[Attribute Manager]: Refreshed all definitions");
    return Plugin_Continue;
}

// List the properties and attributes of a definition
Action attrib_listdefinition(int client, int args)
{
    // Retrieve the name provided.
    if (args < 1)
    {
        char buffer[64];
        GetCmdArg(0, buffer, sizeof(buffer));
        ReplyToCommand(client, "[Attribute Manager]: %s name", buffer);
        return Plugin_Continue;
    }
    char arg[64];
    GetCmdArg(1, arg, sizeof(arg));
    TrimString(arg);

    // Check that the definition actually exists.
    Definition def;
    if (!FindDefinitionComplex(def, arg))
    {
        ReplyToCommand(client, "[Attribute Manager]: Definition %s does not exist", arg);
        return Plugin_Continue;
    }

    // Print all the props for the definition
    ReplyToCommand(client, "[Attribute Manager]: %s:", def.m_szName);
    ReplyToCommand(client, "(Property) keepattributes: %i", !def.m_bOnlyIterateItemViewAttributes);

    // Iterate all TF2 attributes.
    for (int i = 0, size = def.m_Attributes.Length; i < size; ++i)
    {
        Attribute attrib;
        def.m_Attributes.GetArray(i, attrib);
        ReplyToCommand(client, "(Attribute) %s: %s", attrib.m_szName, attrib.m_szValue);
    }

    // Iterate all custom attributes.
    for (int i = 0, size = def.m_CustomAttributes.Length; i < size; ++i)
    {
        Attribute attrib;
        def.m_CustomAttributes.GetArray(i, attrib);
        ReplyToCommand(client, "(Custom attribute) %s: %s", attrib.m_szName, attrib.m_szValue);
    }

    // Return to command.
    return Plugin_Continue;
}

// Add an attribute to a definition
Action attrib_addattribute(int client, int args)
{
    // Retrieve the name, attribute and value
    if (args != 3)
    {
        char buffer[64];
        GetCmdArg(0, buffer, sizeof(buffer));
        ReplyToCommand(client, "[Attribute Manager]: %s name attribute value", buffer);
        return Plugin_Continue;
    }
    char name[64], attribute[64], value[64];
    GetCmdArg(1, name, sizeof(name));
    GetCmdArg(2, attribute, sizeof(attribute));
    GetCmdArg(3, value, sizeof(value));
    TrimString(name);
    TrimString(attribute);
    TrimString(value);

    // Check that the definition actually exists.
    Definition def;
    if (!FindDefinitionComplex(def, name))
    {
        ReplyToCommand(client, "[Attribute Manager]: Definition %s does not exist", name);
        return Plugin_Continue;
    }

    // If the attribute provided is a def index, convert it to its actual name.
    int defindex = StringToInt(attribute);
    if (defindex > 0)
    {
        if (!g_LoadedEcon)
        {
            ReplyToCommand(client, "[Attribute Manager]: Cannot convert attribute index %i to attribute name due to TF2 Econ Data not being loaded. Contact the server owner.", defindex);
            return Plugin_Continue;
        }
        if (!TF2Econ_GetAttributeName(defindex, attribute, sizeof(attribute)))
        {
            ReplyToCommand(client, "[Attribute Manager]: Attribute definition index %i is invalid", defindex);
            return Plugin_Continue;
        }
    }

    // Verify that the attribute name is valid.
    if (!TF2Attrib_IsValidAttributeName(attribute))
    {
        ReplyToCommand(client, "[Attribute Manager]: Attribute name \"%s\" is not valid", attribute);
        return Plugin_Continue;
    }

    // Add the attribute.
    def.WriteAttribute(attribute, value);
    ReplyToCommand(client, "[Attribute Manager]: Successfully modified attribute \"%s\" on definition %s", attribute, def.m_szName);
    return Plugin_Continue;
}

// Remove an attribute from a definition
Action attrib_removeattribute(int client, int args)
{
    // Retrieve the name, attribute and value
    if (args != 2)
    {
        char buffer[64];
        GetCmdArg(0, buffer, sizeof(buffer));
        ReplyToCommand(client, "[Attribute Manager]: %s name attribute", buffer);
        return Plugin_Continue;
    }
    char name[64], attribute[64];
    GetCmdArg(1, name, sizeof(name));
    GetCmdArg(2, attribute, sizeof(attribute));
    TrimString(name);
    TrimString(attribute);

    // Check that the definition actually exists.
    Definition def;
    if (!FindDefinitionComplex(def, name))
    {
        ReplyToCommand(client, "[Attribute Manager]: Definition %s does not exist", name);
        return Plugin_Continue;
    }

    // If the attribute provided is a def index, convert it to its actual name.
    int defindex = StringToInt(attribute);
    if (defindex > 0)
    {
        if (!g_LoadedEcon)
        {
            ReplyToCommand(client, "[Attribute Manager]: Cannot convert attribute index %i to attribute name due to TF2 Econ Data not being loaded. Contact the server owner.", defindex);
            return Plugin_Continue;
        }
        if (!TF2Econ_GetAttributeName(defindex, attribute, sizeof(attribute)))
        {
            ReplyToCommand(client, "[Attribute Manager]: Attribute definition index %i is invalid", defindex);
            return Plugin_Continue;
        }
    }

    // Verify that the attribute name is valid.
    if (!TF2Attrib_IsValidAttributeName(attribute))
    {
        ReplyToCommand(client, "[Attribute Manager]: Attribute name \"%s\" is not valid", attribute);
        return Plugin_Continue;
    }

    // Remove the attribute.
    for (int i = 0, size = def.m_Attributes.Length; i < size; ++i)
    {
        Attribute attrib;
        def.m_Attributes.GetArray(i, attrib);
        if (strcmp(attrib.m_szName, attribute) == 0)
        {
            def.m_Attributes.Erase(i);
            ReplyToCommand(client, "[Attribute Manager]: Successfully removed attribute \"%s\" from definition %s", attribute, def.m_szName);
            return Plugin_Continue;
        }
    }
    ReplyToCommand(client, "[Attribute Manager]: Could not find attribute \"%s\" in definition %s", attribute, def.m_szName);
    return Plugin_Continue;
}

// Add a custom attribute to a definition
Action attrib_addcustomattribute(int client, int args)
{
    // Retrieve the name, attribute and value
    if (args != 3)
    {
        char buffer[64];
        GetCmdArg(0, buffer, sizeof(buffer));
        ReplyToCommand(client, "[Attribute Manager]: %s name attribute value", buffer);
        return Plugin_Continue;
    }
    char name[64], attribute[64], value[64];
    GetCmdArg(1, name, sizeof(name));
    GetCmdArg(2, attribute, sizeof(attribute));
    GetCmdArg(3, value, sizeof(value));
    TrimString(name);
    TrimString(attribute);
    TrimString(value);

    // Check that the definition actually exists.
    Definition def;
    if (!FindDefinitionComplex(def, name))
    {
        ReplyToCommand(client, "[Attribute Manager]: Definition %s does not exist", name);
        return Plugin_Continue;
    }

    // Add the attribute.
    def.WriteAttribute(attribute, value, true);
    ReplyToCommand(client, "[Attribute Manager]: Successfully modified custom attribute \"%s\" on definition %s", attribute, def.m_szName);
    return Plugin_Continue;
}

// Remove a custom attribute from a definition
Action attrib_removecustomattribute(int client, int args)
{
    // Retrieve the name, attribute and value
    if (args != 2)
    {
        char buffer[64];
        GetCmdArg(0, buffer, sizeof(buffer));
        ReplyToCommand(client, "[Attribute Manager]: %s name attribute", buffer);
        return Plugin_Continue;
    }
    char name[64], attribute[64];
    GetCmdArg(1, name, sizeof(name));
    GetCmdArg(2, attribute, sizeof(attribute));
    TrimString(name);
    TrimString(attribute);

    // Check that the definition actually exists.
    Definition def;
    if (!FindDefinitionComplex(def, name))
    {
        ReplyToCommand(client, "[Attribute Manager]: Definition %s does not exist", name);
        return Plugin_Continue;
    }

    // Remove the attribute.
    for (int i = 0, size = def.m_CustomAttributes.Length; i < size; ++i)
    {
        Attribute attrib;
        def.m_CustomAttributes.GetArray(i, attrib);
        if (strcmp(attrib.m_szName, attribute) == 0)
        {
            def.m_CustomAttributes.Erase(i);
            ReplyToCommand(client, "[Attribute Manager]: Successfully removed custom attribute \"%s\" from definition %s", attribute, def.m_szName);
            return Plugin_Continue;
        }
    }
    ReplyToCommand(client, "[Attribute Manager]: Could not find custom attribute \"%s\" in definition %s", attribute, def.m_szName);
    return Plugin_Continue;
}

//////////////////////////////////////////////////////////////////////////////
// NATIVES                                                                  //
//////////////////////////////////////////////////////////////////////////////

// Returns an ArrayList of definitions.
public any Native_AttributeManager_GetDefinitions(Handle plugin, int numParams)
{
    return g_Definitions.Clone();
}

// Updates g_Definitions on the plugin's end, manipulating weapon/class functionality.
public any Native_AttributeManager_SetDefinitions(Handle plugin, int numParams)
{
    ArrayList list = GetNativeCell(1);
    delete g_Definitions;
    g_Definitions = list.Clone();
    return 0;
}

// Writes all definitions to a config file.
public any Native_AttributeManager_Write(Handle plugin, int numParams)
{
    // Check for a passed argument.
    char arg[PLATFORM_MAX_PATH];
    char buffer[PLATFORM_MAX_PATH];
    
    int bytes;
    GetNativeString(1, arg, sizeof(arg), bytes);
    if (bytes == 0)
        strcopy(buffer, sizeof(buffer), AUTOSAVE_PATH);
    else
    {
        TrimString(arg);
        Format(buffer, sizeof(buffer), "addons/sourcemod/configs/attribute_manager/%s.cfg", arg);
    }

    // Open a new file.
    if (!DirExists("addons/sourcemod/configs/attribute_manager/", true))
        CreateDirectory("addons/sourcemod/configs/attribute_manager/", .use_valve_fs = true);

    File file = OpenFile(buffer, "w", true);
    if (!file)
        return false;
    delete file;

    // Create a KeyValues pair and export it to the file.
    ExportKeyValues(buffer);

    // Return to command.
    return true;
}

// Load definitions from a config file.
public any Native_AttributeManager_Load(Handle plugin, int numParams)
{
    // Check for a passed argument.
    char arg[PLATFORM_MAX_PATH];
    char buffer[PLATFORM_MAX_PATH];
    GetNativeString(1, arg, sizeof(arg));
    TrimString(arg);
    Format(buffer, sizeof(buffer), "addons/sourcemod/configs/attribute_manager/%s.cfg", arg);

    // Check if it exists.
    if (!FileExists(buffer))
        return false;
    
    // Load all definitions from the file.
    ParseDefinitions(buffer);
    strcopy(g_szCurrentPath, sizeof(g_szCurrentPath), buffer);

    // Return to command.
    return true;
}

// Re-parses definitions from the currently loaded config file.
public any Native_AttributeManager_Refresh(Handle plugin, int numParams)
{
    ExportKeyValues(g_szCurrentPath);
    ParseDefinitions(g_szCurrentPath);
    return 0;
}

// Returns the path of the current config file loaded.
public any Native_AttributeManager_GetLoadedConfig(Handle plugin, int numParams)
{
    int maxlength = GetNativeCell(2);
    int bytes = 0;
    SetNativeString(1, g_szCurrentPath, maxlength, true, bytes);
    return bytes;
}