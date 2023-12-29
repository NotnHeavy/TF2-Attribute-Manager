//////////////////////////////////////////////////////////////////////////////
// MADE BY NOTNHEAVY. USES GPL-3, AS PER REQUEST OF SOURCEMOD               //
//////////////////////////////////////////////////////////////////////////////

#if defined NOTNHEAVY_ATTRIBUTE_MANAGER
    #endinput
#endif
#define NOTNHEAVY_ATTRIBUTE_MANAGER

//////////////////////////////////////////////////////////////////////////////
// GLOBALS                                                                  //
//////////////////////////////////////////////////////////////////////////////

enum struct ClassDefinition
{
    char m_szName[64];
    TFClassType m_eClass;
}
static stock ClassDefinition g_Classes[] = {
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

enum struct Definition
{
    char m_szName[64];
    int m_iItemDef;
    int m_iIndex;
    bool m_bOnlyIterateItemViewAttributes;
    TFClassType m_eClass;
    ArrayList m_Attributes;
    ArrayList m_CustomAttributes;
}

enum struct Attribute
{   
    char m_szName[64];
    char m_szValue[64];
}

//////////////////////////////////////////////////////////////////////////////
// NATIVES                                                                  //
//////////////////////////////////////////////////////////////////////////////

/** 
 * Returns an ArrayList of definitions.
 * 
 * @return  All definitions within an ArrayList. This must be deleted when finished.
*/
native ArrayList AttributeManager_GetDefinitions();

/**
 * Updates g_Definitions on the plugin's end, manipulating weapon/class functionality.
 * 
 * @param definitions   An ArrayList containing all the updated definitions.
 */
native void AttributeManager_SetDefinitions(ArrayList definitions);

/**
 * Writes all definitions to a config file.
 * 
 * @param cfg   The name of the config file - extension omitted. 
 *              (can be left blank to default to autoexec.cfg).
 * @return      True if succeeded in writing, otherwise false.
 */
native bool AttributeManager_Write(const char[] cfg);

/**
 * Load definitions from a config file.
 * 
 * @param cfg   The name of the config file - extension omitted.
 * @return      True if succeeded in reading, otherwise false.
 */
native bool AttributeManager_Load(const char[] cfg);

/**
 * Re-parses definitions from the currently loaded config file.
 */
native bool AttributeManager_Refresh();

/**
 * Returns the path of the current config file loaded.
 * 
 * @param buffer    The char buffer to store the string in.
 * @param maxlength The maximum length of the buffer (including
 *                  the NUL terminator).
 * @return          The number of bytes written. (UTF-8)
 */
native int AttributeManager_GetLoadedConfig(char[] buffer, int maxlength);

//////////////////////////////////////////////////////////////////////////////
// FORWARDS                                                                 //
//////////////////////////////////////////////////////////////////////////////

/**
 * Called when g_Definitions is reset, either on plugin start or
 * through loading a new config.
 * 
 * @param pluginstart   True if this is called when this plugin
 *                      has started.
 */
forward void AttributeManager_OnDefinitionsLoaded(bool pluginstart);

//////////////////////////////////////////////////////////////////////////////
// PLUGIN INFO                                                              //
//////////////////////////////////////////////////////////////////////////////

public SharedPlugin __pl_notnheavy___attribute_manager = 
{
	name = "NotnHeavy - Attribute Manager",
	file = "NotnHeavy - Attribute Manager.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};