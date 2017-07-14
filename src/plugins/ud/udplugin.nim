import ../../longorc, ../../orcdiscord,  discord, httpclient, asyncdispatch, json, cgi, tables

type UDPlugin* = ref object of Plugin

method save*(p: UDPlugin) = return
method load*(p: UDPlugin) = return
method name*(p: UDPlugin): string = "ud"

method help*(p: UDPlugin, b: Bot, s: Service, m: OrcMessage): seq[string] =
    result = @[
        commandHelp("urban", " [word] ", "Urban Dictionary word definition")
    ]

method message*(p: UDPlugin, b: Bot, s: Service, m: OrcMessage) {.async.} =
    if m.msgType() != mtMessageCreate or s.isMe(m) or m.user().bot:
        return

    let discord = cast[OrcDiscord](b.services["Discord"].service)
    
    if matchesCommand(m, s, "urban"):
        let (word, _) = parseCommand(s, m)
        if word == "": return

        let client = newAsyncHttpClient()
        client.headers.add("Content-Type", "application/json")
        client.headers.add("Accept", "application/json")
        let res = await client.get("http://api.urbandictionary.com/v0/define?term=" & encodeUrl(word))
        client.close()
        
        if res == nil: 
            s.sendMessage(m.channel(), "Couldn't find definiton for " & word)
            return
        let body = await res.body()
        let node = parseJson(body)
        if node["result_type"].str == "no_results":
            s.sendMessage(m.channel(), "Couldn't find definition for " & word)
            return
        
        let first = node["list"].elems[0]
        let footer = EmbedFooter(text: "Urban Dictionary") 
        let author = EmbedAuthor(
            name: word,
            url: "http://www.urbandictionary.com/define.php?term=" & encodeUrl(word),
            icon_url: "http://urbandictionary.com/favicon.ico"
        )
        var description = first.fields["definition"].str 
        if description.len > 1000:
            description = description[0..800] & "... Read the full definition at urbandictionary.com" & "\n```\n" & first.fields["example"].str & "\n```"
        let embed = Embed(
            author: author,
            description: description,
            footer: footer,
            color: Color,
                fields: @[]
        )
        asyncCheck discord.session.channelMessageSendEmbed(m.channel(), embed)
        