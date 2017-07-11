import ../../longorc, marshal, strutils, sequtils, asyncdispatch, tables, locks

type
    Tag = object
        name: string
        owner_id: string
        content: string
    Server = ref object
        id: string
        tags: seq[Tag]
    TagPlugin* = ref object of Plugin
        lock: Lock
        servers: seq[Server]

proc newTagPlugin*(): TagPlugin =
    var p = TagPlugin()
    try:
        p.load()
    except:
        echo "Failed to load tags state"
        p.servers = @[]
        p.save()
    result = p

method name*(p: TagPlugin): string = "tags"
method save*(p: TagPlugin) =
    initLock(p.lock)
    writeFile("tagsstate.json", $$p.servers)
    deinitLock(p.lock)

method load*(p: TagPlugin) =
    initLock(p.lock)
    let b = readFile("tagsstate.json")
    let t = marshal.to[seq[Server]](b)    
    p.servers = t
    deinitLock(p.lock)

method help*(p: TagPlugin, b: Bot, s: Service, m: OrcMessage): seq[string] =
    result = @[
        commandHelp("tag", " [tag name] ", "Sends the contents of the tag."),
        commandHelp("tag add", " [tag name] [tag content] ", "Adds a new tag."),
        commandHelp("tag remove", " [tag name] ", "Removes the tag, only usable by mods and the tag owner of the tag."),
        commandHelp("tag edit", " [tag name] [new content] ", "Edits a tag, only usable by mods and the tag owner.")
    ]

method findTag(p: TagPlugin, server, name: string): string {.base, gcsafe.} =
    result = ""
    initLock(p.lock)
    defer: deinitLock(p.lock)
    for s in p.servers:
        if s.id == server:
            for tag in s.tags:
                if tag.name == name:
                    return tag.content

method fuzzyMatch(p: TagPlugin, server, name: string): string {.base, gcsafe.} =
    result = "Couldn't find a matching tag."
    initLock(p.lock)
    defer: deinitLock(p.lock)
    var matches: seq[Tag] = @[]
    for _, s in p.servers:
        if s.id == server:
            matches = filter(s.tags, proc(t: Tag): bool = t.name.contains(name))
            break
    if matches.len > 0:
        result &= " Did you mean:\n"
        for item in matches:
            result &= "**" & item.name & "**\n"        
        
method tag(p: TagPlugin, server: string, tagn: string): string {.base, gcsafe.} =
    result = p.findTag(server, tagn)
    if result == "":
        result = p.fuzzyMatch(server, tagn)

method tagAdd(p: TagPlugin, server, tagn, tagc, tago: string): bool {.base, gcsafe.} =
    result = true
    initLock(p.lock)
    defer: deinitLock(p.lock)
    let tag = Tag(
        name: tagn,
        content: tagc,
        owner_id: tago
    )
    for s in p.servers:
        if s.id == server:
            for tag in s.tags:
                if tag.name == tagn:
                    return false
            s.tags.add(tag)
            p.save()
            return
    p.servers.add(Server(
        id: server,
        tags: @[tag]
    ))
    p.save()

method tagRemove(p: TagPlugin, server, tagn, issuer: string, modissuer: bool): bool {.base, gcsafe.} =
    result = false
    initLock(p.lock)
    defer: deinitLock(p.lock)
    for s in p.servers:
        if s.id == server:
            for i, tag in s.tags:
                if tag.name == tagn and (tag.owner_id == issuer or modissuer):
                    s.tags.del(i)
                    p.save()
                    return true
            break

method tagEdit(p: TagPlugin, server, tagn, tagc, issuer: string, modissuer: bool): bool {.base, gcsafe.} =
    result = false
    initLock(p.lock)
    defer: deinitLock(p.lock)
    for s in p.servers:
        if s.id == server:
            for i, tag in s.tags:
                if tag.name == tagn and (tag.owner_id == issuer or modissuer):
                    s.tags[i].content = tagc
                    p.save()
                    return true
            break

method message*(p: TagPlugin, b: Bot, s: Service, m: OrcMessage) {.async.} =
    if s.isMe(m) or m.user().bot() or m.msgType() == mtMessageDelete:
        return

    if matchesCommand(m, s, "tag"):
        let discord = cast[OrcDiscord](b.services["Discord"].service)
        var (_, args) = parseCommand(s, m)
        if args.len < 1: return
        case args[0]:
        of "add":
            if args.len < 2: return
            let tname = args[1]
            args = args[2..high(args)]
            let tcont = args.join(" ")
            let guild = discord.messageServer(m) 
            let success = p.tagAdd(guild, tname, tcont, m.user.id)
            if not success:
                s.sendMessage(m.channel, "Failed to add tag '" & tname & "'. Tag already exists.")
                return
            s.sendMessage(m.channel, "Added tag '" & tname & "'.")
        of "edit":
            if args.len < 2: return
            let tname = args[1]
            args = args[2..high(args)]
            let tcont = args.join(" ")
            let guild = discord.messageServer(m)
            let modissue = s.isModerator(m)
            let success = p.tagEdit(guild, tname, tcont, m.user.id, modissue)
            if not success:
                s.sendMessage(m.channel, "Failed to edit tag '" & tname & "'. You probably don't have permission to edit that tag.")
                return
            s.sendMessage(m.channel, "Edited tag '" & tname & "'.")
        of "remove":
            let tname = args[1]
            let guild = discord.messageServer(m)
            let success = p.tagRemove(guild, tname, m.user.id, s.isModerator(m))
            if not success:
                s.sendMessage(m.channel, "Failed to remove tag '" & tname & "'. You probably don't have the permission to remote that tag.")
                return
            s.sendMessage(m.channel, "Removed tag '" & tname & "'.")
        else:
            let guild = discord.messageServer(m)
            let c = p.tag(guild, args[0])
            s.sendMessage(m.channel, c)