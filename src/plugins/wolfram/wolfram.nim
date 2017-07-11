import ../../longorc, httpclient, asyncdispatch, cgi

type 
    WolframPlugin* = ref object of Plugin
        appid: string

proc newWolframPlugin*(appid: string): WolframPlugin = WolframPlugin(appid: appid)

method save*(p: WolframPlugin) = return
method load*(p: WolframPlugin) = return
method name*(p: WolframPlugin): string = "wolfram"

method help*(p: WolframPlugin, b: Bot, s: Service, m: OrcMessage): seq[string] = 
    result = @[
        commandHelp("wolfram", " [query] ", "Wolfram|Alpha query result")
    ]

method message*(p: WolframPlugin, b: Bot, s: Service, m: OrcMessage) {.async.} =
    if s.isMe(m) or m.user().bot() or m.msgType() == mtMessageDelete:
        return

    if matchesCommand(m, s, "wolfram"):
        let (query, _) = parseCommand(s, m)
        if query == "": return

        let client = newAsyncHttpClient()
        let res = await client.get("http://api.wolframalpha.com/v1/result?&i=" & encodeUrl(query) & "&appid=" & p.appid)
        client.close()
        if res == nil or res.code != HttpCode(200):
            s.sendMessage(m.channel(), "No result")
            return
            
        let body = await res.body
        if body == "":
            s.sendMessage(m.channel(), "Something happened...")
            return
        s.sendMessage(m.channel(), body)