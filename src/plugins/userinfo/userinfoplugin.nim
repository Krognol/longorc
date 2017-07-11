import ../../longorc, discord, strutils, times, asyncdispatch, tables, os, httpclient

type
    UserInfoPlugin* = ref object of Plugin

proc idToMs(id: string): int64 {.inline.} = (id.parseInt shr 22) + 1420070400000
proc guildEmojis(emojis: seq[Emoji]): string = 
    result = ""
    for emoji in emojis:
        result &= @emoji
method save*(u: UserInfoPlugin) = return
method load*(u: UserInfoPlugin) = return
method name*(u: UserInfoPlugin): string = "userinfo"

method help*(u: UserInfoPlugin, b: Bot, s: Service, m: OrcMessage): seq[string] =
    result = @[
        commandHelp("userinfo", " -- ", "Displays info about the user for whoever used the command"),
        commandHelp("serverinfo", " -- ", "Displays server info"),
        commandHelp("status", " -- ", "Shows the current bot status"),
        commandHelp("enablewidget", " -- ", "Enables a the guild widget. (Used in the .!serverinfo command to show the number of online people)")
    ]

method message*(u: UserInfoPlugin, b: Bot, s: Service, m : OrcMessage) {.async.} = 
    if m.msgType() != mtMessageCreate or s.isMe(m) or m.user().bot:
        return
    
    let discord = cast[OrcDiscord](b.services["Discord"].service)
    let (_, arg) = parseCommand(s, m)
    if not (arg.len >= 1): return
    case arg[0]:
    of "enablewidget":
        let chan = await discord.session.channel(m.channel())
        try:
            asyncCheck discord.session.guildEmbedEdit(chan.guild_id, true, m.channel())
        except: discard
    of "userinfo":
        var (id, _) = s.parseCommand(m)
        if id == "": id = m.user.id
        if id != "": 
            try:
                let user = waitFor discord.session.user(id)
                let i = (idToMs(user.id).int/1000).int
                let t = i.fromSeconds().getLocalTime()
                let fields = @[
                    EmbedField(name: "Username", value: user.username, inline: true),
                    EmbedField(name: "ID", value: user.id, inline: true),
                    EmbedField(name: "Discriminator", value: user.discriminator, inline: true),
                    EmbedField(name: "Registered", value: t.format("yyyy-MM-dd HH:mm:ss"), inline: true)
                ]
                let img = EmbedThumbnail(url: "https://cdn.discordapp.com/avatars/" & user.id & "/" & user.avatar & ".png")
                let embed = Embed(title: "User info", description: "", color: Color, thumbnail: img, fields: fields)
                asyncCheck discord.session.channelMessageSendEmbed(m.channel(), embed)
            except:
                s.sendMessage(m.channel(), "Unknown user")
    of "serverinfo":
        try:
            let channel = waitFor discord.session.channel(m.channel())
            let guild = waitFor discord.session.guild(channel.guild_id)
            let i = (idToMs(guild.id).int/1000).int
            let t = i.fromSeconds().getLocalTime()
            let fields = @[
                EmbedField(name: "Name", value: guild.name, inline: true),
                EmbedField(name: "ID", value: guild.id, inline: true),
                EmbedField(name: "Region", value: guild.region, inline: true),
                EmbedField(name: "Owner", value: guild.owner_id, inline: true),
                EmbedField(name: "Members", value: $guild.member_count, inline: true),
                EmbedField(name: "Created", value: t.format("yyyy-MM-dd HH:mm:ss"), inline: true),
            ]
            var url = ""
            if guild.icon == nil:
                url = "https://discordapp.com/assets/dd4dbc0016779df1378e7812eabaa04d.png"
            else:
                url = "https://cdn.discordapp.com/icons/" & guild.id & "/" & guild.icon & ".png"
            let thumb = EmbedThumbnail(url: url)
            let img = EmbedImage(url: "https://discordapp.com/api/v7/guilds/" & guild.id & "/embed.png?style=shield")
            let embed = Embed(
                title: "Server info", 
                description: "Emojis\n" & guildEmojis(guild.emojis), 
                color: Color, 
                thumbnail: thumb, 
                image: img,
                fields: fields
            )
            asyncCheck discord.session.channelMessageSendEmbed(m.channel(), embed)
        except:
            s.sendMessage(m.channel(), "Something happened :(")
    of "status":
        try:
            let fields = @[
                EmbedField(name: "Host OS", value: system.hostOS, inline: true),
                EmbedField(name: "Host CPU", value: system.hostCPU, inline: true),
                EmbedField(name: "Start time", value: b.launchtime.getLocalTime().format("yyyy-MM-dd HH:mm:ss"), inline: true),
                EmbedField(name: "CPU time", value: $cpuTime(), inline: true),
                EmbedField(name: "Discordnim version", value: "1.5.0", inline: true),
                EmbedField(name: "Nim version", value: NimVersion, inline: true) 
            ]
            let thumbnail = EmbedThumbnail(url: "https://cdn.discordapp.com/avatars/330139412983840769/" & discord.session.cache.me.avatar & ".png")
            let embed = Embed(title: "Bot status", fields: fields, description: system.GC_getStatistics(), thumbnail: thumbnail, color: Color)
            asyncCheck discord.session.channelMessageSendEmbed(m.channel(), embed)
        except:
            s.sendMessage(m.channel(), "Something happened :(")
    of "avatar":
        let url = endpointAvatar(m.user().id, m.user().avatar)
        let client = newAsyncHttpClient()
        let res = await client.get(url)
        client.close()
        if res == nil or res.code != HttpCode 200:
            s.sendMessage(m.channel(), "Error getting avatar")
            return
        let body = await res.body
        asyncCheck discord.session.channelFileSendWithMessage(m.channel(), m.user.id&"_avatar.png", body, "<@"&m.user.id&">")