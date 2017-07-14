import ../../longorc, ../../orcdiscord, marshal, asyncdispatch, random, tables, sequtils, locks, strutils, json

type
    Server = ref object
        id: string
        quotes: seq[string]
    QuotesPlugin* = ref object of Plugin
        lock: Lock
        servers: seq[Server]

method name*(p: QuotesPlugin): string = "quotes"
method save*(p: QuotesPlugin) =
    initLock(p.lock)
    let s = %*{"servers": p.servers}
    writeFile("quotesstate.json", $s)
    deinitLock(p.lock)

method load*(p: QuotesPlugin) = 
    initLock(p.lock)
    let b = readFile("quotesstate.json")
    let temp = parseJson(b)
    p.servers = json.to(temp["servers"], seq[Server])
    deinitLock(p.lock)

proc newQuotesPlugin*(): QuotesPlugin =
    result = QuotesPlugin(servers: @[])
    try:
        result.load()
    except:
        echo "No quotes state"
        echo getCurrentExceptionMsg()
        result.save()

method help*(p: QuotesPlugin, b: Bot, s: Service, m: OrcMessage): seq[string] =
    result = @[
        commandHelp("quote", " [index or nothing] ", "Grabs a random quote if no index is given"),
        commandHelp("quote add", " [content] ", "Adds a new quote"),
        commandHelp("quote edit", " [index] ", "Edits a quote with the new content. Only usable by mods."),
        commandHelp("quote remove", " [index] ", "Removes a quote. Only usable by mods")
    ]

method getQuote(p: QuotesPlugin, server: string): (int, string) {.base, gcsafe.} =
    initLock(p.lock)
    result = (-1, "")
    let s = p.servers.filter(proc(x: Server): bool = x.id == server)
    if s.len > 0:
        randomize()
        if s[0].quotes.len == 1:
            result = (0, s[0].quotes[0])
        elif s[0].quotes.len >= 2:
            let idx = random(high(s[0].quotes))
            result = (idx, s[0].quotes[idx])
    deinitLock(p.lock)


method getQuote(p: QuotesPlugin, server: string, index: int): string {.base, gcsafe.} =
    initLock(p.lock)
    result = ""
    let s = p.servers.filter(proc(x: Server): bool = x.id == server)
    if s.len > 0:
        result = if not (index < 0) and not (index > s[0].quotes.len): s[0].quotes[index] else: ""
    deinitLock(p.lock)

method addQuote(p: QuotesPlugin, guild: string, quote: string) {.base, gcsafe.} =
    for server in p.servers:
        if server.id == guild:
            server.quotes.add(quote)
            p.save()
            return
    p.servers.add(Server(id: guild, quotes: @[quote]))
    p.save()

method editQuote(p: QuotesPlugin, guild: string, index: int, quote: string): bool {.base, gcsafe.} =
    result = false
    for server in p.servers:
        if server.id == guild:
            initLock(p.lock)
            server.quotes[index] = quote
            deinitLock(p.lock)
            result = true
            break

method removeQuote(p: QuotesPlugin, guild: string, index: int): bool {.base, gcsafe.} =
    result = false
    for server in p.servers:
        if server.id == guild:
            initLock(p.lock)
            server.quotes.del(index)
            initLock(p.lock)
            result = true
            break

method message*(p: QuotesPlugin, b: Bot, s: Service, m: OrcMessage) {.async.} =
    if s.isMe(m) or m.msgType() == mtMessageDelete or m.user().bot():
        return

    if matchesCommand(m, s, "quote"):
        let discord = cast[OrcDiscord](b.services["Discord"].service)
        var (rest, args) = parseCommand(s, m)
        if args.len == 0 or rest == "": # wat
            let (i, quote) = p.getQuote(discord.messageServer(m))
            if quote == "":
                s.sendMessage(m.channel, "No quotes")
            else:
                s.sendMessage(m.channel, $i & ". " & quote)
            return
        case args[0]:
        of "add":
            if args.len < 2: return
            args = args[1..high(args)]
            let quote = args.join(" ")
            let guild = discord.messageServer(m) 
            p.addQuote(guild, quote)
            s.sendMessage(m.channel, "Added quote" )
        of "edit":
            if args.len < 2: return
            let index = args[1].parseInt
            args = args[2..high(args)]
            let quote = args.join(" ")
            let success = p.editQuote(discord.messageServer(m), index, quote)
            if not success:
                s.sendMessage(m.channel, "Failed to edit quote #" & $index)
            else:
                s.sendMessage(m.channel, "Edited quote 3" & $index & ".")
        of "remove":
            if args.len < 2: return
            let index = args[1].parseInt
            let success = p.removeQuote(discord.messageServer(m), index)
            if not success:
                s.sendMessage(m.channel, "Failed to remove quote #" & $index)
            else:
                s.sendMessage(m.channel, "Removed quote #" & $index)
        else:
            try:
                let index = args[0].parseInt
                let guild = discord.messageServer(m)
                let quote = p.getQuote(guild, index)
                if quote != "":
                    s.sendMessage(m.channel, quote)
                else:
                    s.sendMessage(m.channel, "Index out of range")
            except: discard