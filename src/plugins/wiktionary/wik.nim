import ../../longorc, discord, asyncdispatch, httpclient, json, tables, cgi

type 
    WiktionaryPlugin* = ref object of Plugin
        apikey*: string

proc newWiktionaryPlugin*(apikey: string): WiktionaryPlugin = WiktionaryPlugin(apikey: apikey)

const 
    wordDef = "http://api.wordnik.com/v4/word.json/"
    wordDefQuery = "/definitions?limit=200&includeRelated=false&useCanonical=false&sourceDictionaries=wiktionary&includeTags=false&api_key="
    wordPronQuery = "/pronunciations?useCanonical=false&limit=50&api_key="


method save*(p: WiktionaryPlugin) = return
method load*(p: WiktionaryPlugin) = return
method name*(p: WiktionaryPlugin): string = "wiktionary"

method help*(p: WiktionaryPlugin, b: Bot, s: Service, m: OrcMessage): seq[string] =
    result = @[
        commandHelp("define", " [word] ", "Wiktionary definition of [word]")
    ]

method message*(p: WiktionaryPlugin, b: Bot, s: Service, m: OrcMessage) {.async.} =
    if s.isMe(m) or m.user().bot() or m.msgType() == mtMessageDelete:
        return

    if matchesCommand(m, s, "define"):
        let (word, _) = parseCommand(s, m)
        if word == "": return
        
        let discord = cast[OrcDiscord](b.services["Discord"].service)
        var client = newAsyncHttpClient()
        
        client.headers.add("Accept", "application/json")
        var url = wordDef & word & wordDefQuery & p.apikey
        var res = await client.get(url)
        if res == nil: return
        client.close()

        var body = await res.body
        var node = parseJson(body)
        if node.kind == JArray and node.elems.len == 0:
            s.sendMessage(m.channel(), "Couldn't find a definition for " & word)
            return
        
        let def = node.elems[0]

        url = wordDef & word & wordPronQuery & p.apikey
        client = newAsyncHttpClient()
        client.headers.add("Accept", "application/json")
        res = await client.get(url)
        if res == nil: return
        client.close()
        body = await res.body
        node = parseJson(body)
        var wordpron = ""
        if node.kind == JArray and node.elems.len != 0:
            wordpron = node.elems[0]["raw"].str

        let authorname = if wordpron != "": word & " " & wordpron else: word
        let author = EmbedAuthor(
            name: authorname, 
            url: "https://en.wiktionary.org/wiki/" & encodeUrl(word),
            icon_url: "https://en.wiktionary.org/favicon.ico"
        )
        let embed = Embed(
            author: author,
            description: def["text"].str,
            color: Color,
            fields: @[],
            footer: EmbedFooter(text: def["attributionText"].str)
        )
        asyncCheck discord.session.channelMessageSendEmbed(m.channel(), embed)