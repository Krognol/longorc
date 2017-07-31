import ../../longorc, ../../orcdiscord, discord, asyncdispatch, locks, marshal, strutils, tables

type 
    Role = object
        name: string
        id: string
    Server = ref object
        id: string
        roles: seq[Role]
    RolesPlugin = ref object of Plugin 
        lock: Lock
        servers: seq[Server]
    

proc newRolesPlugin*(): RolesPlugin {.inline.} = 
    var p = RolesPlugin()
    try:
        p.load()
    except: 
        echo "Failed to load Roles state"
        p.servers = @[]
        p.save()
    result = p

method save*(p: RolesPlugin) =
    initLock(p.lock)
    writeFile("rolesstate.json", $$p.servers)
    deinitLock(p.lock)

method load*(p: RolesPlugin) =
    initLock(p.lock)
    let r = readFile("rolesstate.json")
    p.servers = marshal.to[seq[Server]](r)
    deinitLock(p.lock)

method name*(p: RolesPlugin): string = "roles"

method help*(p: RolesPlugin, b: Bot, s: Service, m: OrcMessage): seq[string] =
    result = @[
        commandHelp("roles", " -- ", "Displays all available roles"),
        commandHelp("roles add", " [role name] [role id] ", "(Mod command) Adds a role to the gettable roles list"),
        commandHelp("roles del", " [role id] ", "(Mod command) Removes a role from the gettable roles list"),
        commandHelp("role get", " [role name] ", "Gives a role to the requesting user"),
        commandHelp("role remove", " [role name] ", "Removes a role from the requesting user")
    ]

method serverRoles(p: RolesPlugin, server: string): string {.base, gcsafe, inline.} = 
    result = ""
    for s in p.servers:
        if s.id == server:
            for role in s.roles:
                result &= role.name & " : " & role.id
            break

method serverRole(p: RolesPlugin, server, rolename: string): bool {.base, gcsafe, inline.} =
    result = false
    for s in p.servers:
        if s.id == server:
            for role in s.roles:
                if role.name == rolename: 
                    result = true
                    break

method role(p: RolesPlugin, server, rolename: string): string {.base, gcsafe.} =
    for s in p.servers:
        if s.id == server:
            for role in s.roles:
                if role.name == rolename:
                    return role.id

method serverRolesAdd(p: RolesPlugin, server, name, roleid: string) {.base, gcsafe.} =
    for s in p.servers:
        if s.id == server:
            initLock(p.lock)
            s.roles.add(Role(name: name, id: roleid))
            deinitLock(p.lock)
            p.save()
            return
    p.servers.add(Server(id: server, roles: @[Role(name: name, id: roleid)]))
    p.save()

method serverRolesDel(p: RolesPlugin, server, rolename: string) {.base, gcsafe.} =
    for s in p.servers:
        if s.id == server:
            for i, role in s.roles:
                if role.name == rolename:
                    s.roles.del(i)
                    p.save()
                    break
            return

method message*(p: RolesPlugin, b: Bot, s: Service, m: OrcMessage) {.async.} =
    if m.msgType() == mtMessageDelete or s.isMe(m) or m.user().bot:
        return
    
    if matchesCommand(m, s, "roles"):        
        let discord = cast[OrcDiscord](b.services["Discord"].service)
        let (n, args) = parseCommand(s, m)
        if args.len == 0 or n == "":
            let ret = p.serverRoles(discord.messageServer(m))
            if ret == "":
                s.sendMessage(m.channel, "No roles")
                return
            s.sendMessage(m.channel, ret)
            return
        if s.isModerator(m) and args.len > 2:
            let server = discord.messageServer(m)
            if server == "":
                echo "failed to get the guild the message was sent in"
                return
            case args[0]:
            of "add":
                p.serverRolesAdd(server, args[1], args[2])
                s.sendMessage(m.channel, "Added role " & args[1] & " to the list")
            of "del":
                p.serverRolesDel(server, args[1])
                s.sendMessage(m.channel, "Removed role " & args[1] & " to the list")
        return
    
    if matchesCommand(m, s, "role"):
        let(_, args) = parseCommand(s, m)
        if args.len < 2: return
        let discord = cast[OrcDiscord](b.services["Discord"].service)
        let server = discord.messageServer(m)
        case args[0]:
        of "get":
            if p.serverRole(server, args[1]):
                await discord.userGiveRole(server, m.user.id, p.role(server, args[1]))
        of "remove":
            if p.serverRole(server, args[1]):
                await discord.userTakeRole(server, m.user.id, p.role(server, args[1]))