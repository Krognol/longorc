import ../../longorc, ../../orcdiscord, discordnim, strutils, times, asyncdispatch, tables, os, httpclient, re

type
    UserInfoPlugin* = ref object of Plugin
        cache: Table[string, Embed]


proc newUserInfoPlugin*(): UserInfoPlugin {.inline.} = 
    result = UserInfoPlugin(
        cache: initTable[string, Embed]()
    )

proc idToMs(id: string): int64 {.inline.} = (id.parseInt shr 22) + 1420070400000
proc guildEmojis(emojis: seq[Emoji]): string {.inline.} = 
    result = ""
    for emoji in emojis:
        result &= @emoji

method save*(p: UserInfoPlugin) {.inline.} = return
method load*(p: UserInfoPlugin) {.inline.} = return
method name*(p: UserInfoPlugin): string {.inline.} = "userinfo"

method help*(p: UserInfoPlugin, b: Bot, s: Service, m: OrcMessage): seq[string] {.inline.} = 
    result = @[
        commandHelp("info user", " -- ", "Displays info about the user for whoever used the command"),
        commandHelp("info user", " [@mention of user or user id] ", "Displays info about the @'d user."),
        commandHelp("info server", " -- ", "Displays server info"),
        commandHelp("info bot", " -- ", "Shows the current bot status"),
        commandHelp("info enablewidget", " -- ", "Enables a the guild widget. (Used in the .!serverinfo command to show the number of online people)")
    ]

proc extractUser(s: string): string =
    result = ""
    for _, ch in s:
        if not ch.isDigit: continue
        result &= ch

method createEmbed(p: UserInfoPlugin, b: Bot, discord: OrcDiscord): Embed {.base, gcsafe.} =
    var t = cpuTime()
    var hours: int16 = 0
    var minutes: int8 = 0
    var seconds: int8 = 0
    
    while t > 60:
        minutes.inc
        t -= 60
    while minutes > 60:
        hours.inc
        minutes -= 60
    seconds = t.int8
        
    let fields = @[
        EmbedField(name: "Host OS", value: system.hostOS, inline: true),
        EmbedField(name: "Host CPU", value: system.hostCPU, inline: true),
        EmbedField(name: "Start time", value: b.launchtime.getLocalTime().format("yyyy-MM-dd HH:mm:ss"), inline: true),
        EmbedField(name: "CPU time", value: "$1h$2m$3s" % [$hours, $minutes, $seconds], inline: true),
        EmbedField(name: "Discordnim version", value: VERSION, inline: true),
        EmbedField(name: "Nim version", value: NimVersion, inline: true) 
    ]
    let thumbnail = EmbedThumbnail(url: endpointAvatar(discord.session.cache.me.id, discord.session.cache.me.avatar))
    result = Embed(title: "Bot status", fields: fields, description: system.GC_getStatistics(), thumbnail: thumbnail, color: Color)

method createEmbed(p: UserInfoPlugin, u: User): Embed {.base, gcsafe.} =
    if p.cache.hasKey(u.id): return p.cache[u.id]
    let i = (idToMs(u.id).int/1000).int
    let t = i.fromSeconds().getLocalTime()
    let fields = @[
        EmbedField(name: "Username", value: u.username, inline: true),
        EmbedField(name: "ID", value: u.id, inline: true),
        EmbedField(name: "Discriminator", value: u.discriminator, inline: true),
        EmbedField(name: "Registered", value: t.format("yyyy-MM-dd HH:mm:ss"), inline: true)
    ]
    let img = EmbedThumbnail(url: defaultAvatar(u))
    let embed = Embed(title: "User info", description: "", color: Color, thumbnail: img, fields: fields)
    result = embed
    p.cache[u.id] = result

method createEmbed(p: UserInfoPlugin, g: Guild): Embed {.gcsafe, base.} =
    if p.cache.hasKey(g.id): return p.cache[g.id]
    let i = (idToMs(g.id).int/1000).int
    let t = i.fromSeconds().getLocalTime()
    let fields = @[
        EmbedField(name: "Name", value: g.name, inline: true),
        EmbedField(name: "ID", value: g.id, inline: true),
        EmbedField(name: "Region", value: g.region, inline: true),
        EmbedField(name: "Owner", value: g.owner_id, inline: true),
        EmbedField(name: "Members", value: $g.member_count, inline: true),
        EmbedField(name: "Created", value: t.format("yyyy-MM-dd HH:mm:ss"), inline: true),
    ]
    let thumb = EmbedThumbnail(url: defaultIcon(g))
    let img = EmbedImage(url: "https://discordapp.com/api/v7/guilds/" & g.id & "/embed.png?style=shield")
    let embed = Embed(
        title: "Server info", 
        description: "Emojis\n" & guildEmojis(g.emojis), 
        color: Color, 
        thumbnail: thumb, 
        image: img,
        fields: fields,
    )
    result = embed
    p.cache[g.id] = result

method message*(p: UserInfoPlugin, b: Bot, s: Service, m : OrcMessage) {.async.} = 
    if m.msgType() == mtMessageDelete or s.isMe(m) or m.user().bot:
        return
    
    if matchesCommand(m, s, "info"):
        let discord = cast[OrcDiscord](b.services["Discord"].service)
        let (_, arg) = parseCommand(s, m)
        if not (arg.len >= 1): return
        case arg[0]:
        of "user":
            try:
                var uid = ""
                var user: User
                if arg.len > 1:
                    if arg[1].match(re"(<@!?[0-9]+>)") or arg[1].match(re"([0-9]+)"):
                        uid = extractUser(m.content)
                        user = waitFor discord.session.user(uid)
                    else:
                        user = waitFor discord.session.user(m.user.id)
                else: user = waitFor discord.session.user(m.user.id)
                
                let uembed = p.createEmbed(user)
                asyncCheck discord.session.channelMessageSendEmbed(m.channel, uembed)
            except:
                s.sendMessage(m.channel, "Encountered some error while creating embed")
        of "server":
            try:
                let gid = discord.messageServer(m)
                if gid != "":
                    let g = waitFor discord.session.guild(gid)
                    let gembed = p.createEmbed(g)
                    asyncCheck discord.session.channelMessageSendEmbed(m.channel, gembed)
            except:
                s.sendMessage(m.channel(), "Something happened :(")
        of "enablewidget":
            let chan = await discord.session.channel(m.channel())
            try:
                asyncCheck discord.session.guildEmbedEdit(chan.guild_id, true, m.channel())
            except: discard
        of "status":
            try:
                asyncCheck discord.session.channelMessageSendEmbed(m.channel(), p.createEmbed(b, discord))
            except:
                s.sendMessage(m.channel(), "Something happened :(")
        of "avatar":
            let url = m.user().avatar
            let client = newAsyncHttpClient()
            let res = await client.get(url)
            client.close()
            if res == nil or res.code != HttpCode 200:
                s.sendMessage(m.channel(), "Error getting avatar")
                return
            let body = await res.body
            asyncCheck discord.session.channelFileSendWithMessage(m.channel(), m.user.id&"_avatar.png", body, "<@"&m.user.id&">")