import ../../longorc, ../../orcdiscord, asyncdispatch, httpclient, discordnim, cgi, tables, json, marshal, strutils, re

const AnilistUrl = "https://anilist.co/api/"

type AnilistPlugin* = ref object of Plugin
    client_id*: string not nil
    client_secret*: string not nil

proc newAnilistPlugin*(clientid: string, clientsecret: string): AnilistPlugin = AnilistPlugin(client_id: clientid, client_secret: clientsecret)
 
method authenticate(p: AnilistPlugin): Future[string] {.async, gcsafe, base.} =
    var client = newAsyncHttpClient()
    let url = AnilistUrl & "auth/access_token?grant_type=client_credentials&client_id=" & p.client_id & "&client_secret=" & p.client_secret
    let res = await client.post(url)
    client.close()
    if res == nil:
        return nil
    let body = await res.body()
    let node = parseJson(body)
    result = node["access_token"].str

method save*(p: AnilistPlugin) = return
method load*(p: AnilistPlugin) = return
method name*(p: AnilistPlugin): string = "anilist"

method help*(p: AnilistPlugin, b: Bot, s: Service, m: OrcMessage): seq[string] =
    result = @[
        commandHelp("anime", " [name] ", "Anilist entry on the given anime"),
        commandHelp("manga", " [name] ", "Anilist entry on the given manga"),
        commandHelp("character", " [name] ", "Anilist entry on your waifu")
    ]

proc sendAnime*(d: OrcDiscord, channel, user: string, anime: JsonNode) {.async, gcsafe.} =
    var author = EmbedAuthor(url: "https://anilist.co/anime/" & $anime["id"].num.int & "/" & encodeUrl(anime["title_romaji"].str))
    if anime["title_japanese"].str != nil:
        author.name = anime["title_japanese"].str
    else:
        author.name = anime["title_romaji"].str
        
    let thumb = EmbedThumbnail(url: anime["image_url_lge"].str)
    var fields = @[
        EmbedField(name: "Type", value: anime["series_type"].str, inline: true),
        EmbedField(name: "Status", value: anime["airing_status"].str, inline: true),
        EmbedField(name: "Episodes", value: $anime["total_episodes"].num.int, inline: true),
        EmbedField(name: "Score", value: $anime["average_score"].num.int & "/100", inline: true),
    ]
    if anime["genres"].kind != JNull and anime["genres"].elems.len > 1:
        var genres: seq[string] = @[]    
        for elem in anime["genres"].elems:
            if elem.str != "":
                genres.add(elem.str)
        fields.add(EmbedField(name: "Genres", value: genres.join(", "), inline: true))
    if anime["synonyms"].kind != JNull and anime["synonyms"].elems.len > 1:
        var syns: seq[string] = @[]
        for elem in anime["synonyms"].elems:
            if elem.str != "":
                syns.add(elem.str) 
        fields.add(EmbedField(name: "Synonyms", value: syns.join(", "), inline: true))
    if anime["source"].kind != JNull:
        fields.add(EmbedField(name: "Source", value: anime["source"].str, inline: true))
    let clr = await d.userColor(channel, user)
    let embed = Embed(
        author: author,
        fields: fields,
        description: anime["description"].str.replace("<br>", "\n"),
        thumbnail: thumb,
        footer: EmbedFooter(text: "Anilist.co"),
        color: clr
    )
    asyncCheck d.session.channelMessageSendEmbed(channel, embed)

proc sendManga(d: OrcDiscord, channel, user: string, manga: JsonNode) {.async, gcsafe.} =
    var author = EmbedAuthor(url: "https://anilist.co/manga/" & $manga["id"].num.int & "/" & encodeUrl(manga["title_romaji"].str))
    if manga["title_japanese"].str != nil:
        author.name = manga["title_japanese"].str
    else:
        author.name = manga["title_romaji"].str
    let thumb = EmbedThumbnail(url: manga["image_url_lge"].str)
    var fields = @[
        EmbedField(name: "Type", value: manga["series_type"].str, inline: true),
        EmbedField(name: "Status", value: manga["publishing_status"].str, inline: true),
        EmbedField(name: "Volumes", value: $manga["total_volumes"].num.int, inline: true),
        EmbedField(name: "Chapters", value: $manga["total_chapters"].num.int, inline: true)
    ]
    if manga["genres"].kind != JNull and manga["genres"].elems.len > 1:
        var genres: seq[string] = @[]
        for elem in manga["genres"].elems:
            if elem.str != "":
                genres.add(elem.str)
        fields.add(EmbedField(name: "Genres", value: genres.join(", "), inline: true))
    if manga["synonyms"].kind != JNull and manga["synonyms"].elems.len > 1:
        var syns: seq[string] = @[]
        for elem in manga["synonyms"].elems:
            if elem.str != "":
                syns.add(elem.str)
        fields.add(EmbedField(name: "Synonyms", value: syns.join(", "), inline: true))
    let clr = await d.userColor(channel, user)
    let embed = Embed(
        author: author,
        fields: fields,
        thumbnail: thumb,
        description: manga["description"].str.replace("<br>", "\n"),
        footer: EmbedFooter(text: "Anilist.co"),
        color: clr
    )
    asyncCheck d.session.channelMessageSendEmbed(channel, embed)

proc sendCharacter(d: OrcDiscord, chan, user: string, character: JsonNode) {.async, gcsafe.} =
    var name = ""
    if character["name_first"].kind != JNull:
        name &= character["name_first"].str
    if character["name_last"].kind != JNull:
        name &= character["name_last"].str
    name = encodeUrl(name)
    var author = EmbedAuthor(url: "https://anilist.co/character/" & $character["id"].num.int & "/" & name)
    if character["name_japanese"].kind != JNull:
        author.name = character["name_japanese"].str
    else:
        author.name = character["name_first"].str & " " & character["name_last"].str
    
    let img = EmbedImage(url: character["image_url_lge"].str)
    var info = character["info"].str.replace("&quot;", "\"").replace("&#039", "'")
    if info.contains("~!"):
        info = info.replace(re"""(~![\w\d\s():,.'\"-]+!~)""", "")
    if info.len > 1000:
        info = info[0..600] & "...\n\nRead the full bio at the character profile"
    let clr = await d.userColor(chan, user)
    let embed = Embed(
        author: author,
        image: img,
        description: info,
        footer: EmbedFooter(text: "Anilist.co"),
        color: clr,
        fields: @[]
    )
    asyncCheck d.session.channelMessageSendEmbed(chan, embed)

method message*(p: AnilistPlugin, b: Bot, s: Service, m: OrcMessage) {.async.} =
    if s.isMe(m) or m.user().bot() or m.msgType() == mtMessageDelete:
        return

    let discord = cast[OrcDiscord](b.services["Discord"].service)
    if matchesCommand(m, s, "anime"):
        var (name, _) = parseCommand(s, m)
        if name == "":
            return
        if name.contains("/"):
            name = name.replace("/", " ")
        name = encodeUrl(name)
        
        let token = await p.authenticate()
        if token == nil or token == "":
            return

        let client = newAsyncHttpClient()
        client.headers.add("Accept", "application/json")

        let res = await client.get(AnilistUrl & "anime/search/" & name & "?access_token=" & token)
        client.close()
        if res == nil:
            s.sendMessage(m.channel(), "Couldn't find that anime")
            return
        let body = await res.body()
        var animes = parseJson(body)
        if animes.kind == JObject and animes.hasKey("error"): 
            s.sendMessage(m.channel(), "Couldn't find anything")
            return
        if animes.kind != JNull and animes != nil:
            if animes.elems.len > 0:
                let anime = animes.elems[0]
                asyncCheck sendAnime(discord, m.channel(), m.user.id, anime)
        return
    
    if matchesCommand(m, s, "manga"):
        var (name, _) = parseCommand(s, m)
        if name == "": return
        if name.contains("/"):
            name = name.replace("/", " ")
        name = encodeUrl(name)

        let token = await p.authenticate()
        if token == nil or token == "": return

        let client = newAsyncHttpClient()
        client.headers.add("Accept", "application/json")

        let res = await client.get(AnilistUrl & "manga/search/" & name & "?access_token=" & token)
        client.close()
        if res == nil:
            s.sendMessage(m.channel(), "Couldn't find that manga")
            return
        let body = await res.body()
        var mangas = parseJson(body)
        if mangas.kind == JObject and mangas.hasKey("error"): 
            s.sendMessage(m.channel(), "Couldn't find anything")
            return
        if mangas.kind != JNull and mangas != nil:
            if mangas.elems.len > 0:
                let manga = mangas.elems[0]
                asyncCheck sendManga(discord, m.channel(), m.user.id, manga)
        return
    
    if matchesCommand(m, s, "character"):
        var (name, _) = parseCommand(s, m)
        if name == "": return
        if name.contains("/"):
            name = name.replace("/", " ")
        name = encodeUrl(name)

        let token = await p.authenticate()
        if token == nil or token == "": return

        let client = newAsyncHttpClient()

        client.headers.add("Accept", "application/json")
        let res = await client.get(AnilistUrl & "character/search/" & name & "?access_token=" & token)
        client.close()
        if res == nil:
            s.sendMessage(m.channel(), "Couldn't find anything :(")
            return
        let body = await res.body()
        var characters = parseJson(body)
        if characters.kind == JObject and characters.hasKey("error"): 
            s.sendMessage(m.channel(), "Couldn't find anything")
            return
        if characters.kind != JNull and characters != nil:
            if characters.elems.len > 0:
                let character = characters.elems[0]
                asyncCheck sendCharacter(discord, m.channel(), m.user.id, character)