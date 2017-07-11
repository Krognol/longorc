import discord, tables, strutils, algorithm, asyncdispatch, os, times

type
    MessageType* = enum
        mtMessageCreate
        mtMessageUpdate
        mtMessageDelete
    OrcUser* = ref object of RootObj
    OrcDiscordUser* = ref object of OrcUser
        user: discord.User
    OrcMessage* = ref object of RootObj
    OrcDiscordMessage* = ref object of OrcMessage
        discord*: OrcDiscord
        msg*: discord.Message
        msgtype*: MessageType
    Plugin* = ref object of RootObj
    Service* = ref object of RootObj
    ServiceEntry = ref object of RootObj
        service*: Service 
        plugins*: Table[string, Plugin]
    Bot* = ref object of RootObj
        services*: Table[string, ServiceEntry]
        launchtime*: Time
    OrcDiscord* = ref object of Service
        session*: Session
    
const Color* = 0x57ed78
    
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

# Discord message methods
method user*(m: OrcDiscordMessage): OrcUser {.inline, gcsafe.} = OrcDiscordUser(user: m.msg.author)
method channel*(m: OrcDiscordMessage): string {.inline, gcsafe.} = m.msg.channel_id
method content*(m: OrcDiscordMessage): string {.inline, gcsafe.} = m.msg.content
method id*(m: OrcDiscordMessage): string {.inline, gcsafe.} = m.msg.id
method msgType*(m: OrcDiscordMessage): MessageType {.inline, gcsafe.} = m.msgtype

# User methods
method name*(u: OrcUser): string {.base, inline, gcsafe.} = "nil"
method id*(u: OrcUser): string {.base, inline, gcsafe.} = "-1"
method avatar*(u: OrcUser): string {.base, inline, gcsafe.} = "nil"
method discriminator*(u: OrcUser): string {.base, inline, gcsafe.} = "1234"
method bot*(u: OrcUser): bool {.base, inline, gcsafe.} = false

# Discord user methods
method name*(u: OrcDiscordUser): string {.inline, gcsafe.} = u.user.username
method id*(u: OrcDiscordUser): string {.inline, gcsafe.} = u.user.id
method avatar*(u: OrcDiscordUser): string {.inline, gcsafe.} = u.user.avatar
method discriminator*(u: OrcDiscordUser): string {.inline, gcsafe.} = u.user.discriminator
method bot*(u: OrcDiscordUser): bool {.inline, gcsafe.} = u.user.bot

proc orcMemberPermissions(g: Guild, c: DChannel, m: GuildMember): int =
    var perms = 0
    for role in g.roles:
        if role.id == g.id:
            perms = perms or role.permissions
            break
    
    for role in g.roles:
        for rid in m.roles:
            if role.id == rid:
                perms = perms or role.permissions
                break
    
    if (perms and permAdministrator) == permAdministrator:
        perms = perms or permAll

    for overwrite in c.permission_overwrites:
        if g.id == overwrite.id:
            perms = perms and (perms xor overwrite.deny)
            perms = perms or overwrite.allow
            break

    var denies = 0
    var allows = 0

    for overwrite in c.permission_overwrites:
        for roleid in m.roles:
            if overwrite.type == "role" and roleid == overwrite.id:
                denies = denies or overwrite.deny
                allows = allows or overwrite.allow
                break

    perms = perms and (perms xor denies)
    perms = perms or allows

    for overwrite in c.permission_overwrites:
        if overwrite.type == "member" and overwrite.id == m.user.id:
            perms = perms and (perms xor overwrite.deny)
            perms = perms or overwrite.allow
            break

    if (perms and permAdministrator) == permAdministrator:
        perms = perms or permAllChannel
    
    result = perms

method userChannelPermissions(s: OrcDiscord, user, channel: string): int {.base.} =
    let channel = waitFor s.session.channel(channel)
    let guild = waitFor s.session.guild(channel.guild_id)

    if user == guild.owner_id: 
        return permAll
    
    let member = waitFor s.session.guildMember(guild.id, user)

    result = orcMemberPermissions(guild, channel, member)

method messageServer*(s: OrcDiscord, m: OrcMessage): string {.base, gcsafe.} =
    let dm = cast[OrcDiscordMessage](m)
    result = s.session.messageGuild(dm.msg)

# Discord service methods
method name*(s: OrcDiscord): string {.inline, gcsafe.} = "Discord"
method isMe*(s: OrcDiscord, m: OrcMessage): bool {.inline.} = m.user().id() == s.session.cache.me.id
method isModerator*(s: OrcDiscord, m: OrcMessage): bool {.inline.} = 
    let perms = s.userChannelPermissions(m.user().id(), m.channel())
    result = ((perms and permAll) == permAll) or 
        ((perms and permAllChannel) == permAllChannel) or
        ((perms and permManageGuild) == permManageGuild)

method sendMessage*(s: OrcDiscord, channel: string, message: string) {.inline.} = asyncCheck s.session.channelMessageSend(channel, message)
method prefix*(s: OrcDiscord): string {.inline.} = ".!"



type HelpPlugin = ref object of Plugin

proc newDiscordMessage*(s: OrcDiscord, m: Message, typ: MessageType): OrcMessage =
    result = OrcDiscordMessage(discord: s, msg: m, msgType: typ)

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
        var msg = m.content().toLowerAscii()
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
                ret = "All commands can be found here <https://github.com/Krognol/longorc>"
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

proc newDiscordService*(token: string): OrcDiscord =
    var ses = newSession(token)
    result = OrcDiscord(
        session: ses,
    )