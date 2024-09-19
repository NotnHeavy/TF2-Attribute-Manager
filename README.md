# (TF2) Attribute Manager

This is a plugin that allows users to modify attributes - either native attributes applied at runtime, or through [nosoop's custom attribute framework](https://github.com/nosoop/SM-TFCustAttr) - in-game, through modifying a config or programmatically.

# How to use
Users may create definitions for TF2 classes or TF2 econ entities (wearables or weapons), the latter being referenced by either their name as specified in `items_game.txt` (usually it is the weapon or wearable's in-game name) or [their item definition index](https://wiki.alliedmods.net/Team_fortress_2_item_definition_indexes). All native TF2 attributes can be found [here](https://wiki.teamfortress.com/wiki/List_of_item_attributes), while custom attributes through nosoop's custom attribute framework will only work if their respective plugins are loaded. Usually you'll have to find these yourself. Users may also create definitions for specific tags that aren't linked to any weapon; these definitions are designed to be inherited by other definitions through a copy-paste mechanism. Additionally, definitions can be specified for classes:
- "scout" for Scout
- "soldier" for Soldier
- "pyro" for Pyro
- "demoman", "demo" for Demoman
- "heavy", "heavyweaponsguy", "hwg" for Heavy Weapons Guy
- "engineer" for Engineer
- "medic" for Medic
- "sniper" for Sniper
- "spy" for Spy

Definitions are defined within config files in `addons/sourcemod/configs/attribute_manager/`, with an `autosave.cfg` being created whenever you save on demand, or on plugin end. Each individiual definition is listed within the `Attributes` key. Within each definition, you may specify properties, native attributes and custom attributes. Properties are prefixed with `#`, and there currently exists two properties:
- `#inherits` - if specified, this definition will inherit all data from an existing definition (MUST BE LISTED BEFORE THIS DEFINITION!)
- `#keepattributes` - defaults to true. If false, none of the attributes associated with the weapon/wearable being modified will apply upon entity creation. This may break some weapons unless key attributes are respecified (check `items_game.txt`)!

Attributes are specified as sub-keys, with a string value provided (the type of the value will be handled internally). For example:
```
"no crit vs nonburning"  "1"
```

Custom attributes must be specified within its own sub-key section, called `#custom_attributes`. For example:
```
"#custom_attributes"
{
    "alt fire throws cleaver"  "velocity=800 regen=1"
}
```

See the **Config Manipulation** sub-section for more info, after **In-game**.

Currently, there are three methods of manipulating definitions, shown below.

## In-game
There are plenty of in-game commands (feel free to inform me if you would like these to be expanded) in order to manipulate definitions. When conducting operations on existing definitions which modify weapons or wearables, you may specify them by either naming them or providing their item definition index - this should be resolved internally.
- `attrib_write [configname]` - writes all definitions to a config file, (autosave.cfg by default, `configname`.cfg if specified). The extension must be omitted.
- `(attrib_loadconfig | attrib_load) configname` - loads definitions from an existing config file. The extension must be omitted.
- `(attrib_listdefinitions | attrib_listdefs | attrib_list)` - lists the names of all current definitions.
- `attrib_add name [inherits]` - define a new definition by weapon/wearable name, item definition index, class name or as a tag. If specified, this definition's data can be inherited from another existing definition.
- `(attrib_remove | attrib_delete | attrib_del) name` - removes an existing definition by weapon/wearable name, item definition index, class name or as a tag.
- `attrib_modify name property value` - modifies a property of an existing definition If `value` is `true` or `false`, these will be resolved to `1` and `0` respectively.
- `attrib_refresh` - reparses all definitions using the current set config.
- `(attrib_listdefinition | attrib_listdef) name` - lists the name, properties and attributes of an existing definition.
- `(attrib_addattribute | attrib_addattrib) name attribute value` - adds an attribute to an existing definition. `attribute` may be the attribute name, or its respective attribute definition index (ID) - however this will only be resolved if [TF2 Econ Data](https://github.com/nosoop/SM-TFEconData) is loaded. See the **Dependencies** section for more info.
- `(attrib_removeattribute | attrib_removeattrib) name attribute` - removes an attribute from an existing definition. Akin to `attrib_addattribute`, `attribute` may be the attribute name or its attribute definition index.
- `(attrib_addcustomattribute | attrib_addcustomattrib | attrib_addcustom) name attribute value` - adds a custom attribute to an existing definition, using nosoop's custom attribute framework. `attribute` can only be a name.
- `(attrib_removecustomattribute | attrib_removecustomattrib | attrib_removecustom) name attribute` - removes a custom attribute from an existing definition.

## Config Manipulation
As mentioned earlier, config files are defined in `addons/sourcemod/configs/attribute_manager/`, denoted with the `*.cfg` extension. These are `KeyValues` pairs. These may be modified whilst the plugin is running, and you can use the `(attrib_loadconfig | attrib_load)`/`attrib_refresh` commands to reload them in-game. See `example.cfg` for more specification. For details on specifying which config is loaded on plugin start (by default it will search for `autosave.cfg`), read the **Settings** section.

## Natives
If you're a programmer, I presume you know how to read includes, so please read `./scripting/include/attribute_manager.inc`, or something. If there aren't enough natives, ping me in AlliedModders.

# Settings
By default, this plugin will search for `autosave.cfg` on plugin load, to load any definitions. This is written to on plugin end or on demand (using `attrib_write` or the native `AttributeManager_Write(const char[] cfg)`). However, using a config file located at `addons/sourcemod/configs/attribute_manager.cfg`, you may specify the default config path using the `"defaultconfig"` key. See `addons/sourcemod/configs/attribute_manager.cfg` for more details.

# Dependencies
This plugin is compiled using SourceMod 1.12, but should work under SourceMod 1.11.

The following external dependencies are mandatory for this plugin to function:
- [nosoop's TF2Attributes](https://github.com/nosoop/tf2attributes)

The following external dependencies are advisory and may be utilised to improve plugin functionality, but not mandatory:
- [nosoop's custom attribute framework](https://github.com/nosoop/SM-TFCustAttr) - if loaded, custom attributes may also be loaded onto players/weapons/wearables. This is also used to reject fake slot replacement entities set up by [Weapon Manager](https://github.com/NotnHeavy/TF2-Weapon-Manager).
- [TF2 Econ Data](https://github.com/nosoop/SM-TFEconData) - if loaded, weapon/wearable names and item definition indexes can be resolved, alongside attribute definition indexes (attribute IDs) for their respective attribute names.