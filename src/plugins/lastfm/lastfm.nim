import ../../longorc, discord, asyncdispatch, httpclient, marshal, json, tables, cgi, os, strutils, times

type 
    FMUser = object
        id: string
        fmname: string
    LastFMPlugin* = ref object of Plugin
        users: seq[FMUser]
        apikey: string

proc newLastfmPlugin*(apikey: string): LastFMPlugin = 
    result = LastFMPlugin(users: @[], apikey: apikey)
    try:
        result.load()
    except: 
        echo "No state available for LastFM plugin"

method getUser(p: LastFMPlugin, name: string): FMUser {.base, gcsafe.} =
    result = FMUser()
    for user in p.users:
        if user.fmname == name or user.id == name:
            result = user
            break

method save*(p: LastFMPlugin) = 
    try:
        writeFile("lastfmstate.json", $$p)
    except:
        echo "Error writing LastFM state to file"
        

method load*(p: LastFMPlugin) =
    try:
        let b = readFile("lastfmstate.json")
        let r = marshal.to[LastFMPlugin](b)
        p.users = r.users
    except: 
        echo "Couldn't load state for LastFM plugin"

method name*(p: LastFMPlugin): string = "lastfm"

method help*(p: LastFMPlugin, b: Bot, s: Service, m: OrcMessage): seq[string] =
    result = @[
        commandHelp("fm", " [username or nothing] ", "Looks up last.fm user's last played, and currently playing track. If no username is given takes from local cache"),
        commandHelp("fm set", " [last fm username] ", "Sets a last.fm username in the local cache"),
        commandHelp("fm collage", " [last fm username or nothing] ", "Gets a 4x4 collage of the users top played album the last 7 days"),
        commandHelp("fm topweekly", " [last fm username or nothing] ", "Displays playcount for the users top 5 weekly songs, and how many hours they've listened")
    ]

const
    collageUrl = "http://lastfmtopalbums.dinduks.com/patchwork.php?period=7day&rows=4&cols=4&imageSize=250&user="

method message*(p: LastFMPlugin, b: Bot, s: Service, m: OrcMessage) {.async.} =
    if s.isMe(m) or m.user().bot() or m.msgType() == mtMessageDelete:
        return

    if matchesCommand(m, s, "fm"):
        let discord = cast[OrcDiscord](b.services["Discord"].service)
        var (name, parts) = parseCommand(s, m)
        if parts.len > 0:
            case parts[0]:
            of "set":
                let newuser = FMUser(id: m.user().id, fmname: parts[1])
                p.users.add(newuser)
                p.save()
                s.sendMessage(m.channel(), "Set Last.fm username for <@" & m.user().id & "> to '" & parts[1] & "'")
                return
            of "collage":
                let client = newAsyncHttpClient()
                if parts.len < 2:
                    name = p.getUser(m.user().id).fmname
                else: name = parts[1]
                if name == "": return
                let res = await client.get(collageUrl & name)
                client.close() 
                if res == nil or res.code != HttpCode(200):
                    s.sendMessage(m.channel(), "Couldn't get collage")
                let body = await res.body
                asyncCheck discord.session.channelFileSendWithmessage(m.channel(), "collage_"&name&".png", body, "<@"&m.user().id&">")
            of "topweekly":
                let client = newAsyncHttpClient()
                if parts.len == 1:
                    name = p.getUser(m.user().id).fmname
                else: name = parts[1]
                if name == "": return
                let url = "http://ws.audioscrobbler.com/2.0/?method=user.gettoptracks&period=7day&format=json&limit=100&user=" & name & "&api_key=" & p.apikey
                let res = await client.get(url)
                client.close()
                if res == nil or res.code != HttpCode(200):
                    s.sendMessage(m.channel(), "Error while looking up ")
                    return
                let body = await res.body
                let node = parseJson(body)

                var totalplaytime = 0
                let tracks = node["toptracks"]["track"].elems
                var i = 0
                var fields: seq[EmbedField] = @[]
                var thumb = EmbedThumbnail(url: tracks[0]["image"].elems[3]["#text"].str)
                for track in tracks:
                    if i < 5: 
                        fields.add(EmbedField(
                            name: track["@attr"]["rank"].str & ") " & track["playcount"].str & " plays",
                            value: track["name"].str & " -- " & track["artist"]["name"].str,
                            inline: false
                        ))
                    totalplaytime += track["duration"].str.parseInt
                    inc(i)
                let playtime = totalplaytime.fromSeconds.toTimeInterval
                fields.add(EmbedField(
                    name: "Total listening time",
                    value: $playtime.hours & " hours " & $playtime.minutes & " minutes",
                    inline: false
                ))
                let embed = Embed(
                    author: EmbedAuthor(
                        name: "Top 5 weekly tracks for " & name,
                        url: "https://last.fm/user/" & encodeUrl(name),
                        icon_url: "https://upload.wikimedia.org/wikipedia/commons/1/1a/Last.fm_icon.png"
                    ),
                    fields: fields,
                    color: Color,
                    thumbnail: thumb
                )
                asyncCheck discord.session.channelMessageSendEmbed(m.channel, embed)
            else:
                if name == "": 
                    let user = p.getUser(m.user().id)
                    if user.fmname == "":
                        s.sendMessage(m.channel(), "No username to lookup")
                        return
                    
                    let client = newAsyncHttpClient()
                    let url = "http://ws.audioscrobbler.com/2.0/?method=user.getrecenttracks&limit=2&user=" & user.fmname & "&format=json&api_key=" & p.apikey
                    let res = await client.get(url)
                    client.close()
                    if res == nil or res.code != HttpCode(200): 
                        s.sendMessage(m.channel(), "No result")
                        return
                    
                    let body = await res.body
                    let node = parseJson(body)

                    var fields: seq[EmbedField] = @[]
                    var thumb: EmbedThumbnail = EmbedThumbnail()
                    for elem in node["recenttracks"].fields["track"].elems:
                        if elem.hasKey("@attr") and elem["@attr"].hasKey("nowplaying"):
                            fields.add(EmbedField(
                                name: "Currently playing", 
                                value: elem["name"].str & " -- " & elem["artist"].fields["#text"].str, 
                                inline: false
                            ))
                            thumb = EmbedThumbnail(url: elem["image"].elems[3]["#text"].str)
                            continue
                        fields.add(EmbedField(
                            name: "Recently played", 
                            value: elem["name"].str & " -- " & elem["artist"].fields["#text"].str, 
                            inline: false
                        ))
                    
                    if thumb.url == "":
                        var iconurl = "http://i.imgur.com/jzZ5llc.png"
                        if node["recenttracks"]["track"][0]["image"][3]["#text"].str != "":
                            iconurl = node["recenttracks"]["track"][0]["image"][3]["#text"].str
                        thumb = EmbedThumbnail(url: iconurl)

                    let author = EmbedAuthor(
                        name: "Last tracks for " & user.fmname, 
                        url: "https://last.fm/user/" & encodeUrl(user.fmname), 
                        icon_url: "https://upload.wikimedia.org/wikipedia/commons/1/1a/Last.fm_icon.png"
                    )

                    let embed = Embed(
                        author: author,
                        fields: fields,
                        thumbnail: thumb,
                        color: Color,
                        footer: EmbedFooter(text: "Total tracks: " & node["recenttracks"]["@attr"]["total"].str)
                    )

                    asyncCheck discord.session.channelMessageSendEmbed(m.channel(), embed)