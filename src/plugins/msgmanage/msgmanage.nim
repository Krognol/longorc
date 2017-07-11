import ../../longorc, discord, asyncdispatch, strutils, tables

type Msgmanager* = ref object of Plugin

method save*(p: Msgmanager) = return
method load*(p: Msgmanager) = return
method name*(p: Msgmanager): string = "msgmanager"

method help*(p: Msgmanager, b: Bot, s: Service, m: OrcMessage): seq[string] =
    result = @[
        commandHelp("prune", " [amount] ", "Deletes all N messages")
    ]

method message*(p: Msgmanager, b: Bot, s: Service, m: OrcMessage) {.async.} =
    if s.isMe(m) or m.msgType() == mtMessageDelete or m.user().bot():
        return
    
    if m.matchesCommand(s, "prune"):
        if not s.isModerator(m):
            s.sendMessage(m.channel(), "You need to be a moderator to use this feature!")
            return

        let (args, _) = s.parseCommand(m)
        if args == nil or args == "":
            s.sendMessage(m.channel(), "Not enough arguments")
            return
        let i = args.parseInt
        let discord = cast[OrcDiscord](b.services["Discord"].service)
        let msgs = await discord.session.channelMessages(m.channel(), m.id(), "", "", i)
        if msgs.len == 0:
            s.sendMessage(m.channel(), "Something went wrong when retrieving messages")
            return
        var ids: seq[string] = @[]
        for msg in msgs:
            ids.add(msg.id)
        asyncCheck discord.session.channelMessagesDeleteBulk(m.channel(), ids)