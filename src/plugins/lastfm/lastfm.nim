import ../../longorc, ../../orcdiscord, discord, asyncdispatch, httpclient, marshal, json, tables, cgi, os, strutils, times

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
    result = FMUser(id: "", fmname: "")
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
        commandHelp("fm set",        " [last fm username] ", "Sets a last.fm username in the local cache"),
        commandHelp("fm now",       "", "Looks up last.fm user's last played, and currently playing track. If no username is given takes from local cache"),
        commandHelp("fm recent",    "", "Gets the users last 5 played songs."),
        commandHelp("fm collage",    "", "Gets a 4x4 collage of the users top played album the last 7 days"),

        commandHelp("fm top weekly", "", "Weekly top tracks for the user"),
        commandHelp("fm top tracks", "", "All time top tracks for the user"),
        commandHelp("fm top albums", "", "All time top albums for the user"),
        commandHelp("fm top artists", "", "All time top artists for the user"),
    ]

const
    collageUrl = "http://lastfmtopalbums.dinduks.com/patchwork.php?period=7day&rows=4&cols=4&imageSize=250&user="

method fmrequest(p: LastFMPlugin, meth, user: string, limit: int = 0, span: string = ""): Future[JsonNode] {.base, async, gcsafe,} =
    let client = newAsyncHttpClient()
    var url = "https://ws.audioscrobbler.com/2.0/?method=$1&format=json&user=$2&api_key=$3" % [meth, user, p.api_key]
    if limit != 0: url &= "&limit=" & $limit
    if span != "": url &= "&span=" & span
    let res = await client.get(url)
    if not res.code.is2xx():
        return nil
    let body = await res.body
    try:
        result = body.parseJson
        if result.hasKey("error"): return nil
    except:
        return nil

method fmNow(p: LastFMPlugin, d: OrcDiscord, user, id, channel, avatar: string) {.base, async, gcsafe.} =
    let js = await p.fmrequest("user.getrecenttracks", user, 1)
    if js == nil: return
    var embed = Embed(fields: @[], description: "")
    for node in js["recenttracks"]["track"].elems:
        if node.hasKey("@attr") and node["@attr"].hasKey("nowplaying"):
            embed.author = EmbedAuthor(
                name: user,
                url: "https://last.fm/user/" & user,
                icon_url: avatar
            )
            embed.title = node["name"].str & " -- " & node["artist"]["#text"].str
            embed.url = node["url"].str
            embed.image = EmbedImage(
                url: if node["image"][3]["#text"].kind != JNull and node["image"][3]["#text"].str != "": node["image"][3]["#text"].str else: "http://i.imgur.com/jzZ5llc.png",
            )
            break

    if embed.title.isNilOrEmpty():
        asyncCheck d.session.channelMessageSend(channel, "Looks like you're not playing a song right now")
        return
    embed.color = await d.userColor(channel, id)
    asyncCheck d.session.channelMessageSendEmbed(channel, embed)

method fmRecent(p: LastFMPlugin, d: OrcDiscord, user, id, channel, avatar: string) {.base, async, gcsafe.} =
    let js = await p.fmrequest("user.getrecenttracks", user, 9)
    if js == nil: return
    var embed = Embed(fields: @[], description: "", url: "")
    for i, track in js["recenttracks"]["track"].elems:
        let artist = track["artist"]["#text"].str
        let song = track["name"].str
        if i != 9:
            embed.description &= "`$1`\t    **[$2]($3)** by **$4**\n" % [$(i+1), song, track["url"].str, artist]
        else: 
            embed.description &= "`$1`\t  **[$2]($3)** by **$4**\n" % [$(i+1), song, track["url"].str, artist]
    embed.url = "https://last.fm/user/$1/library" % [user]
    embed.author = EmbedAuthor(
        name: "$1's Recent Tracks" % [user],
        icon_url: avatar,
    )
    embed.color = await d.userColor(channel, id)
    let img = js["recenttracks"]["track"][0]["image"][3]
    embed.thumbnail = EmbedThumbnail(
        url: if img["#text"].kind != JNull and img["#text"].str != "": img["#text"].str else: "http://i.imgur.com/jzZ5llc.png"
    )
    asyncCheck d.session.channelMessageSendEmbed(channel, embed)

method fmTopTracks(p: LastFMPlugin, d: OrcDiscord, user, id, channel: string) {.base, gcsafe, async.} =
    let js = await p.fmrequest("user.gettoptracks", user, 9)
    if js == nil: return
    var embed = Embed(fields: @[], description: "")

    for i, track in js["toptracks"]["track"].elems:
        let artist = track["artist"]["name"].str
        let artisturl = track["artist"]["url"].str

        let song = track["name"].str
        let songurl = track["url"].str

        let playcount = track["playcount"].str
        if i != 9:
            embed.description &= "`$1`\t    **[$2]($3)** by **[$4]($5)** ($6 plays)\n" % [$(i+1), song, songurl, artist, artisturl, playcount]
        else:
            embed.description &= "`$1`\t  **[$2]($3)** by **[$4]($5)** ($6 plays)\n" % [$(i+1), song, songurl, artist, artisturl, playcount]
    
    embed.thumbnail = EmbedThumbnail()
    let img = js["toptracks"]["track"][0]["image"][3]["#text"]
    embed.thumbnail.url = if img.kind != JNull and img.str != "": img.str else: "http://i.imgur.com/jzZ5llc.png"
    embed.color = await d.userColor(channel, id)
    asyncCheck d.session.channelMessageSendEmbed(channel, embed)

method fmTopAlbums(p: LastFMPlugin, d: OrcDiscord, user, id, channel: string) {.base, gcsafe, async.} =
    let js = await p.fmrequest("user.gettopalbums", user, 10)
    if js == nil: return
    var embed = Embed(fields: @[], description: "")

    for i, album in js["topalbums"]["album"].elems:
        let name = album["name"].str
        let playcount = album["playcount"].str
        let url = album["url"].str
        let artist = album["artist"]["name"].str
        let artisturl = album["artist"]["url"].str
        
        if i != 9:
            embed.description &= "`$1`\t    **[$2]($3)** by **[$4]($5)** ($6 plays)\n" % [$(i+1), name, url, artist, artisturl, playcount]
        else:
            embed.description &= "`$1`\t  **[$2]($3)** by **[$4]($5)** ($6 plays)\n" % [$(i+1), name, url, artist, artisturl, playcount]
    embed.thumbnail = EmbedThumbnail()
    let img = js["topalbums"]["album"][0]["image"][3]["#text"]
    embed.thumbnail.url = if img.kind != JNull and img.str != "": img.str else: "http://i.imgur.com/jzZ5llc.png"
    embed.color = await d.userColor(channel, id)
    asyncCheck d.session.channelMessageSendEmbed(channel, embed)

method fmTopArtists(p: LastFMPlugin, d: OrcDiscord, user, id, channel: string) {.base, gcsafe, async.} =
    let js = await p.fmrequest("user.gettopartists", user, 10)
    if js == nil: return
    var embed = Embed(fields: @[], description: "")

    for i, artist in js["topartists"]["artist"].elems:
        let name = artist["name"].str
        let playcount = artist["playcount"].str
        let url = artist["url"].str
        if i != 9:
            embed.description &= "`$1`\t    **[$3]($4)** ($2 plays)\n" % [$(i+1), playcount, name, url]
        else: 
            embed.description &= "`$1`\t  **[$3]($4)** ($2 plays)\n" % [$(i+1), playcount, name, url]
    embed.thumbnail = EmbedThumbnail()
    let img = js["topartists"]["artist"][0]["image"][3]["#text"]
    embed.thumbnail.url = if img.kind != JNull and img.str != "": img.str else: "http://i.imgur.com/jzZ5llc.png"
    embed.color = await d.userColor(channel, id)
    asyncCheck d.session.channelMessageSendEmbed(channel, embed)

method fmTopWeekly(p: LastFMPlugin, d: OrcDiscord, user, id, channel, avatar: string) {.base, gcsafe, async.} =
    let js = await p.fmrequest("user.gettoptracks", user, 10, "7day")
    if js == nil: return
    var embed = Embed(fields: @[], description: "")
    
    for i, track in js["toptracks"]["track"].elems:
        let artist = track["artist"]["name"].str
        let artisturl = track["artist"]["url"].str

        let song = track["name"].str
        let songurl = track["url"].str

        let playcount = track["playcount"].str
        if i != 9:
            embed.description &= "`$1`\t    **[$2]($3)** by **[$4]($5)** ($6 total plays)\n" % [$(i+1), song, songurl, artist, artisturl, playcount]
        else:
            embed.description &= "`$1`\t  **[$2]($3)** by **[$4]($5)** ($6 total plays)\n" % [$(i+1), song, songurl, artist, artisturl, playcount]
    
    embed.thumbnail = EmbedThumbnail()
    let img = js["toptracks"]["track"][0]["image"][3]["#text"]
    embed.thumbnail.url = if img.kind != JNull and img.str != "": img.str else: "http://i.imgur.com/jzZ5llc.png"
    embed.color = await d.userColor(channel, id)
    embed.author = EmbedAuthor(name: "$1's Weekly Top 10"%[user], icon_url: avatar, url: "https://last.fm/user/$1"%[user])
    asyncCheck d.session.channelMessageSendEmbed(channel, embed)

method message*(p: LastFMPlugin, b: Bot, s: Service, m: OrcMessage) {.async.} =
    if s.isMe(m) or m.user().bot() or m.msgType() == mtMessageDelete:
        return

    if matchesCommand(m, s, "fm"):
        let discord = cast[OrcDiscord](b.services["Discord"].service)
        var (name, parts) = parseCommand(s, m)
        name = ""
        if parts.len > 0:
            case parts[0].toLowerAscii
            of "set":
                if parts.len < 2: return
                let newuser = FMUser(id: m.user().id, fmname: parts[1])
                p.users.add(newuser)
                p.save()
                s.sendMessage(m.channel(), "Set Last.fm username for <@" & m.user().id & "> to '" & parts[1] & "'")
            of "collage":
                if parts.len < 2:
                    name = p.getUser(m.user().id).fmname
                else: name = parts[1]
                if name == "" or name == nil: return
                let client = newAsyncHttpClient()
                let res = await client.get(collageUrl & name) 
                client.close()
                if res == nil or res.code != HttpCode(200):
                    s.sendMessage(m.channel(), "Couldn't get collage")
                let body = await res.body
                asyncCheck discord.session.channelFileSendWithmessage(m.channel(), "collage_"&name&".png", body, "<@"&m.user().id&">")
            of "recent":
                if parts.len >= 2: name = parts[1]
                if name == "":
                    let user = p.getUser(m.user.id)
                    if user.fmname == "":
                        s.sendMessage(m.channel, "No username set")
                        return
                    name = user.fmname
                asyncCheck p.fmRecent(discord, name, m.user.id, m.channel, m.user.avatar)
            of "now":
                if parts.len >= 2: name = parts[1]
                if name == "": 
                    let user = p.getUser(m.user().id)
                    if user.fmname == "":
                        s.sendMessage(m.channel(), "No username set")
                        return
                    name = user.fmname
                asyncCheck p.fmNow(discord, name, m.user.id, m.channel, m.user.avatar)
            of "top":
                if parts.len < 2: return
                if parts.len > 2: name = parts[3]
                else: name = p.getUser(m.user.id).fmname
                if name == "":
                    s.sendMessage(m.channel, "No username set")
                    return
                case parts[1]
                of "tracks":
                    asyncCheck p.fmTopTracks(discord, name, m.user.id, m.channel)
                of "albums":
                    asyncCheck p.fmTopAlbums(discord, name, m.user.id, m.channel)
                of "artists":
                    asyncCheck p.fmTopArtists(discord, name, m.user.id, m.channel)
                of "weekly":
                    asyncCheck p.fmTopWeekly(discord, name, m.user.id, m.channel, m.user.avatar)
                else: discard
            else: discard