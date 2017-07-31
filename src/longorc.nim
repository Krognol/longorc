import tables, strutils, algorithm, asyncdispatch, os, times

type
    MessageType* = enum
        mtMessageCreate
        mtMessageUpdate
        mtMessageDelete
    OrcUser* = ref object of RootObj
    OrcMessage* = ref object of RootObj
    Plugin* = ref object of RootObj
    Service* = ref object of RootObj
    ServiceEntry* = ref object of RootObj
        service*: Service 
        plugins*: Table[string, Plugin]
    Bot* = ref object of RootObj
        services*: Table[string, ServiceEntry]
        launchtime*: Time
    
    
# Plugin methods
method name*(p: Plugin): string {.base, inline, gcsafe.} = "base"
method save*(p: Plugin) {.base, inline, gcsafe.} = return
method load*(p: Plugin) {.base, inline, gcsafe.} = return
method help*(p: Plugin, b: Bot, s: Service, m: OrcMessage): seq[string] {.base, inline, gcsafe.} = @[]
method message*(p: Plugin, b: Bot, s: Service, m: OrcMessage) {.base, gcsafe, async.} = return

# Service methods
method name*(s: Service): string {.base, inline, gcsafe, gcsafe.} = "base"
method isMe*(s: Service, m: OrcMessage): bool {.base, inline, gcsafe.} = false
method isModerator*(s: Service, m: OrcMessage): bool {.base, inline, gcsafe.} = false
method sendMessage*(s: Service, channel: string, message: string) {.base, inline, gcsafe.} = return
method prefix*(s: Service): string {.base, inline, gcsafe.} = ""

# Message methods
method user*(m: OrcMessage): OrcUser {.base, inline, gcsafe.} = nil
method channel*(m: OrcMessage): string {.base, inline, gcsafe.} = "nil"
method content*(m: OrcMessage): string {.base, inline, gcsafe.} = "empty"
method id*(m: OrcMessage): string {.base, inline, gcsafe.} = "-1"
method msgType*(m: OrcMessage): MessageType {.base, inline, gcsafe.} = mtMessageDelete

# User methods
method name*(u: OrcUser): string {.base, inline, gcsafe.} = "nil"
method id*(u: OrcUser): string {.base, inline, gcsafe.} = "-1"
method avatar*(u: OrcUser): string {.base, inline, gcsafe.} = "nil"
method discriminator*(u: OrcUser): string {.base, inline, gcsafe.} = "1234"
method bot*(u: OrcUser): bool {.base, inline, gcsafe.} = false


type HelpPlugin = ref object of Plugin

proc commandHelp*(cs: string, args: string, h: string): string =
    if args == "":
        result = cs & " " & h
    else:
        result = cs & " " & args & " " & h

proc matchesCommand*(m: OrcMessage, s: Service, command: string): bool =
    if m.content == nil or 
        m.content() == "" or 
        (not m.content().startsWith(s.prefix())): return false
    
    var msg = m.content()[s.prefix.len..m.content.len].toLowerAscii()
    result = (msg == command) or msg.startsWith(command.toLowerAscii() & " ")

proc parseCommand*(s: Service, m: OrcMessage): (string, seq[string]) =
        var msg = m.content()
        var pref = s.prefix()

        if msg.startsWith(pref):
            msg = substr(msg, len(pref), len(msg))

        var rest = msg.splitWhitespace()
        if rest.len > 1:
            rest = rest[1..len(rest)-1]
            result = (join(rest, " "), rest)
        else:
            result = ("", rest)

method name*(p: HelpPlugin): string = "help"
method load*(p: HelpPlugin) = return
method save*(p: HelpPlugin) = return
method help*(p: HelpPlugin, b: Bot, s: Service, m: OrcMessage): seq[string] = 
    result = @[commandHelp("help", "[plugin name]", "displays help for a plugin")]

method message*(p: HelpPlugin, b: Bot, s: Service, m: OrcMessage) {.async.} =
    if m.msgType() != mtMessageCreate or s.isMe(m) or m.user().bot():
        return

    if matchesCommand(m, s, "help"):
        let (_, parts) = parseCommand(s, m)

        var helpSeq: seq[string] = @[]
        var h: seq[string] = @[]

        for _, plugin in b.services[s.name()].plugins:
            h = plugin.help(b,s,m)
            if h != nil and h.len > 0:
                helpSeq.add(h)

        if parts.len == 0:
            sort(helpSeq, system.cmp)

        if parts.len != 0 and helpSeq.len == 0:
            helpSeq = @["Unknown module " & parts[0]]

        if s.name() == "Discord":
            var ret = "```" & helpSeq.join("\n") & "```"
            if ret.len >= 500: 
                ret = "All commands can be found here <https://github.com/Krognol/longorc#commands>"
            s.sendMessage(m.channel(), ret)

proc newBot*(): Bot =
    result = Bot(services: initTable[string, ServiceEntry](), launchtime: getTime())

method registerPlugin*(b: Bot, s: Service, p: Plugin) {.base.} =
    let ser = b.services[s.name()]
    if ser.plugins.hasKey(p.name()):
        echo "Service already has plugin registered"
        return
    ser.plugins[p.name()] = p
    echo "Initialized plugin " & p.name()
    

method registerService*(b: Bot, s: Service) {.base.} =
    if b.services.hasKey(s.name()):
        echo "Bot already has this service registered"
        return
    b.services[s.name()] = ServiceEntry(plugins: initTable[string, Plugin](), service: s)
    echo "registered service " & s.name()
    b.registerPlugin(s, HelpPlugin())
