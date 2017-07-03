import ../../longorc, random, asyncdispatch, strutils

type RNGPlugin* = ref object of Plugin

method save*(p: RNGPlugin) = return
method load*(p: RNGPlugin) = return
method name*(p: RNGPlugin): string = "rng"

method help*(p: RNGPlugin, b: Bot, s: Service, m: OrcMessage): seq[string] =
    result = @[
        commandHelp("iroll", " [integer] ", "Random number"),
        commandHelp("froll", " [floating point number] ", "Random number"),
        commandHelp("rate", " -- ", "Rates a thing"),
        commandHelp("d6", " -- ", "Rolls a dice")
    ]

method message*(p: RNGPlugin, b: Bot, s: Service, m: OrcMessage) {.async.} =
    if s.isMe(m) or m.user().bot() or m.msgType() == mtMessageDelete:
        return

    randomize()
    if m.matchesCommand(s, "iroll"):
        let (i, _) = s.parseCommand(m)
        if i == "":
            s.sendMessage(m.channel(), "0")
            return
        try:
            let ii = i.parseInt()
            s.sendMessage(m.channel(), $random(ii))
        except:
            s.sendMessage(m.channel(), i & " is not a valid integer")
        return
    
    if m.matchesCommand(s, "froll"):
        let (f, _) = s.parseCommand(m)
        if f == "":
            s.sendMessage(m.channel(), "0.0")
            return
        try:
            let ff = f.parseFloat()
            s.sendMessage(m.channel(), $random(ff))
        except:
            s.sendMessage(m.channel(), f & " is not a valid floating point number")
        return
    
    if m.matchesCommand(s, "d6"):
        s.sendMessage(m.channel(), $random(6))
        return
    
    if m.matchesCommand(s, "rate"):
        s.sendMessage(m.channel(), $random(10) & "/10")
        return