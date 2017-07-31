import ../../longorc, ../../orcdiscord, asyncdispatch, httpclient, json, tables, random, discord, times, strutils

type 
    GfycatPlugin* = ref object of Plugin
        client_id: string
        client_secret: string

proc newGfycatPlugin*(id: string, secret: string): GfycatPlugin = GfycatPlugin(client_id: id, client_secret: secret)
method save*(p: GfycatPlugin) = return
method load*(p: GfycatPlugin) = return
method name*(p: GfycatPlugin): string = "gfycat"

method help*(p: GfycatPlugin, b: Bot, s: Service, m: OrcMessage): seq[string] =
    result = @[
        commandHelp("gfy", " [tag] ", "Looks for a gfycat with [tag]"),
        commandHelp("gfy tags", " -- ", "List of trending tags"),
        commandHelp("gfy trending", " -- ", "Random trending gfycat"),
        commandHelp("gfy user", " [username] ", "Looks up gfycat user")
    ]

method auth(p: GfycatPlugin): Future[string] {.async, gcsafe, base.} =
    result = ""
    let client = newAsyncHttpClient()
    let payload= %*{
        "grant_type": "client_credentials",
        "client_id": p.client_id,
        "client_secret": p.client_secret
    }
    let res = await client.post("https://api.gfycat.com/v1/oauth/token", $payload)
    client.close()
    if res == nil or res.code() == HttpCode(401): return
    let body = await res.body()
    let node = parseJson(body)
    if node.kind == JObject and node.hasKey("access_token"):
        result = node["access_token"].str

proc getRandomGfy(cats: JsonNode): JsonNode = 
    if (cats.kind == JObject and cats.hasKey("errorMessage")) or
        cats["gfycats"].elems.len < 1:
            return nil
    randomize()
    let i = random(cats["gfycats"].len)
    result = cats["gfycats"].elems[i]
    # I hate the gfycat api, sending varying types
    while result.hasKey("nsfw") and result["nsfw"].kind == JString and result["nsfw"].str != "0":
        randomize()
        result = cats["gfycats"].elems[random(cats["gfycats"].len)]

method getGfyUser(p: GfycatPlugin, username: string): Future[JsonNode] {.async, gcsafe, base.} =
    let client = newAsyncHttpClient()
    let res = await client.get("https://api.gfycat.com/v1/users/" & username)
    client.close()
    if res == nil: return
    let body = await res.body()
    result = parseJson(body)
    if result.kind == JObject and result.hasKey("errorMessage"): 
        result = nil

method message*(p: GfycatPlugin, b: Bot, s: Service, m: OrcMessage) {.async.} =
    if s.isMe(m) or m.user().bot() or m.msgType() == mtMessageDelete: return

    if matchesCommand(m, s, "gfy"):
        let discord = cast[OrcDiscord](b.services["Discord"].service)
        let (tag, parts) = parseCommand(s, m)
        let token = await p.auth()
        if token == "": 
            echo "[Gfycat] :: Couldn't retrieve access token"
            return
        
        let client = newAsyncHttpClient()
        client.headers.add("Authorization", "Bearer " & token)
        client.headers.add("Accept", "application/json")
        if parts.len > 1:
            case parts[0]:
            of "user": 
                if parts.len > 1:
                    let node = await p.getGfyUser(parts[0])
                    if node == nil: 
                        s.sendMessage(m.channel, "No results")
                        return
                    let embed = Embed(
                        author: EmbedAuthor(
                            name: node["username"].str,
                            url: node["url"].str
                        ),
                        color: Color,
                        fields: @[
                            EmbedField(name: "Views", value: node["views"].str, inline: true),
                            EmbedField(name: "Verified", value: $node["verified"].bval, inline: true),
                            EmbedField(name: "Followers", value: node["followers"].str, inline: true),
                            EmbedField(name: "Following", value: node["following"].str, inline: true),
                            EmbedField(name: "Created at", value: $node["createDate"].str.parseInt.fromSeconds(), inline: true)
                        ]
                    )
                    asyncCheck discord.session.channelMessageSendEmbed(m.channel(), embed)
            else: discard
        else:
            if tag == "tags":
                let res = await client.get("https://api.gfycat.com/v1test/tags/trending")
                client.close()
                if res == nil: return
                let body = await res.body
                let node = parseJson(body)
                let selection = node.elems[0..5]
                var msg = ""
                for elem in selection:
                    msg &= elem.str & "\n"
                msg &= "...and " & $(node.elems.len-5) & " more"
                s.sendMessage(m.channel(), msg)
            elif tag == "trending":
                let res = await client.get("https://api.gfycat.com/v1test/gfycats/trending")
                client.close()
                if res == nil: return
                let body = await res.body
                let node = parseJson(body)
                let cat = getRandomGfy(node)
                let embed = Embed(
                    title: cat["title"].str,
                    description: cat["description"].str,
                    url: "https://gfycat.com/"&cat["gfyName"].str,
                    image: EmbedImage(url: cat["gifUrl"].str),
                    color: Color,
                    fields: @[]
                )
                asyncCheck discord.session.channelMessageSendEmbed(m.channel(), embed)
            else:
                let res = await client.get("https://api.gfycat.com/v1test/gfycats/search?search_text=" & tag)
                client.close()
                if res == nil: return
                let body = await res.body()
                let node = parseJson(body)
                let cat = getRandomGfy(node)
                let embed = Embed(
                    title: cat["title"].str,
                    description: cat["description"].str,
                    url: "https://gfycat.com/"&cat["gfyName"].str,
                    image: EmbedImage(url: cat["gifUrl"].str),
                    color: Color,
                    fields: @[]
                )
                asyncCheck discord.session.channelMessageSendEmbed(m.channel(), embed)