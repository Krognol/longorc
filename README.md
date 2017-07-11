# Long Orc

Discord bot made with [Discordnim](https://github.com/Krognol/discordnim).

Right now it's mostly fitted for Discord, but will be made much more usable for other chat services soon™.

# Writing your own services

When making your own services, make a new `.nim` file in the `src` directory with the same name as the service.

All services **must** inherit these methods:

```nim
import longorc

type
    TService = ref object of Service
        # Any additional fields that are needed

method name*(s: TService): string # Service name

# For checking if the sender of a message is oneself
method isMe*(s: TService, m: OrcMessage) 

# For checking if a sender is a moderator
method isModerator(s: TService, m: OrcMessage)

# For sending a message to `at` 
# For Discord `at` is a channel ID
# while for a service like Twitch it would be 
# a IRC channel name. E.g. `#krognol`
method sendMessage*(s: TService, at: string, message: string)

# The service prefix user when invoking plugin commands
method prefix*(s: TService): string 
```

# Writing your own plugins

Make a new folder in the `src/plugins` directory with the name of the plugin, and a `.nim` file with (preferably) the same name.

All plugins should follow this basic structure:

```nim
import ../../longorc, marshal, asyncdispatch

type
    TPlugin* = ref object of Plugin
        # Any additional fields it may need

method name*(p: TPlugin): string = "tplugin"
method save*(p: TPlugin) = 
    # If something needs to be saved
    writeFile("tpluginstate.json", $$p)
    # else we'll just return and do nothing

method load*(p: TPlugin) =
    # If something needs to loaded
    let body = readFile("tpluginstate.json")
    let temp = marshal.to[TPlugin](body)
    p.fields = temp.fields
    # else we'll just return and do nothing

method help*(p: TPlugin, b: Bot, s: Service, m: OrcMessage): seq[string] =
    # Returns a seq of strings that describes the commands this plugin supports
    result = @[
        longorc.commandHelp("cmd name", "cmd args", "cmd help text")
    ]

method message*(p: TPlugin, b: Bot, s: Service, m: OrcMessage) {.async.} =
    # Message handling
    # If we want to check if a message matches a prefix and a command
    if matchesCommand(m, s, "cmd name"):
        # It matches and we can now parse it 
        let (rest, args) = parseCommand(s, m)
        # `rest` is either everything after the initial `cmd name` or empty
        # while `args` is everything after the initial `cmd name` split by spaces.
        if rest == "something": 
            # Do something
            return
        
        case args[0]:
        of "something else": 
            # Do something
        else: discard

proc newTPlugin(#[Any necessary args]#): TPlugin = 
    # If the plugin doesn't have a `state` that needs to be loaded
    # we'll just return a new TPlugin.
    result = TPlugin()

    # If we however do need to load the plugin from a state
    # we'll call the plugins `load` method.
    # and use `marshal.to[TPlugin](filebody)`
    # and return that.
    p.load()
```

All plugins **must** inherit the following methods:
```nim
method name*(p: TPlugin): string # Name of the plugin
method save*(p: TPlugin) # For saving any long term data
method load*(p: TPlugin) # For loading any long term data

# For displaying help messages about commands
method help*(p: TPlugin, b: longorc.Bot, s: longorc.Service, m: longorc.OrcMessage): seq[string] 

# For message handling
method message*(p: TPlugin, b: longorc.Bot, s: longorc.Service, m: longorc.OrcMessage) {.async.} 
```

# Commands

| Command       | Arg           | Desc  | Mod command |
| ------------- |:-------------:| :-----:| :----: |
| .!iroll      | integer number | Rolls a random integer between 0..n | false |
| .!froll      | floating point number | Rolls a random FPN between 0.0..n | false |
| .!d6 | -- | Rolls a 6 sided die | false |
| .!anime | name | Anilist.co entry on anime | false |
| .!manga | name | Anilist.co entry on manga | false |
| .!character | name | Anilist.co entry on character | false |
| .!urban | word | Urban dictionary definition of word | false |
| .!define | word | Wiktionary definition of word | false |
| .!userinfo | -- | User information | false |
| .!avatar | -- | User avatar | false |
| .!serverinfo | -- | Information about the server | false |
| .!status | -- | Bot status | false |
| .!enablewidget | -- | Enables the server widget | true |
| .!eval | code | Evaluates Nim code. Restricted to one liners | false |
| .!prune | amount | Deletes all N messages not older than 2 weeks | true |
| .!gfy | tag | Looks up a random Gfycat with [tag] | false |
| .!gfy tags | -- | Looks up popular Gfycat tags | false |
| .!gfy trending | -- | Looks up trending Gfycats | false |
| .!gfycat user | name | Looks up Gfycat user | false |
| .!wolfram | query | Wolfram\|Alpha query result | false |
| .!fm | username, or nothing | Looks up last.fm user's last played, and currently playing track. If no username is given takes from local cache | false |
| .!fm set | username | Sets a last.fm username in the local cache | false |
| .!fm collage | username, or nothing | Gets a collage of the users top played albums in the last week | false |
| .!fm topweekly | username, or nothing | Gets statistics of the users most played songs in the last week | false |
| .!tag | tag name | Gets the tags contents. | false |
| .!tag add | [tag name] [tag content] | Adds a new tag | false |
| .!tag edit | [tag name] [tag content] | Edits a tag. Usable by mods and the owner of the tag | false |
| .!tag remove | tag name | Removes a tag. Usable by mods and the owner of the tag | false |
| .!markov | chain name | Generates a random sentence from a file input | false |