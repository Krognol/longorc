import ../../longorc, httpclient, asyncdispatch, json, cgi
 
type CowSayPlugin* = ref object of Plugin

method save*(p: CowSayPlugin) = return
method load*(p: CowSayPlugin) = return
method name*(p: CowSayPlugin): string = "cowsay"

method help*(p: CowSayPlugin, b: Bot, s: Service, m: OrcMessage): seq[string] =
    result = @[
        commandHelp("cowsay", " [text] ", "Moo")
    ]

method message*(p: CowSayPlugin, b: Bot, s: Service, m: OrcMessage) {.async.} =
    if s.isMe(m) or m.user().bot() or m.msgType() == mtMessageDelete:
        return

    if m.matchesCommand(s, "cowsay"):
        let (text, _) = s.parseCommand(m)
        if text == "":
            return
        
        let url = "http://cowsay.morecode.org/say?format=json&message=" & encodeUrl(text)
        let client = newAsyncHttpClient()
        client.headers.add("Accept", "application/json")
        client.headers.add("Content-Type", "application/json")
        let res = await client.get(url)
        if res == nil:
            s.sendMessage(m.channel(), "Something happened")
            return
        let body = await res.body()
        let node = parseJson(body)
        client.close()
        s.sendMessage(m.channel(), "```\n" & node["cow"].str & "\n```")