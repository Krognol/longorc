import ./longorc, discord, asyncdispatch, queues, tables, algorithm

type
    OrcDiscordUser* = ref object of OrcUser
        user: discord.User
    OrcDiscordMessage* = ref object of OrcMessage
        discord*: OrcDiscord
        msg*: discord.Message
        msgtype*: MessageType
    OrcDiscord* = ref object of Service
        session*: Session

const 
    Color* = 0x57ed78


# Discord message methods
method user*(m: OrcDiscordMessage): OrcUser {.inline, gcsafe.} = OrcDiscordUser(user: m.msg.author)
method channel*(m: OrcDiscordMessage): string {.inline, gcsafe.} = m.msg.channel_id
method content*(m: OrcDiscordMessage): string {.inline, gcsafe.} = m.msg.content
method id*(m: OrcDiscordMessage): string {.inline, gcsafe.} = m.msg.id
method msgType*(m: OrcDiscordMessage): MessageType {.inline, gcsafe.} = m.msgtype

# Discord user methods
method name*(u: OrcDiscordUser): string {.inline, gcsafe.} = u.user.username
method id*(u: OrcDiscordUser): string {.inline, gcsafe.} = u.user.id
method avatar*(u: OrcDiscordUser): string {.inline, gcsafe.} = defaultAvatar(u.user)
method discriminator*(u: OrcDiscordUser): string {.inline, gcsafe.} = u.user.discriminator
method bot*(u: OrcDiscordUser): bool {.inline, gcsafe.} = u.user.bot

proc orcMemberPermissions(g: Guild, c: DChannel, m: GuildMember): int =
    var perms = 0
    for role in g.roles:
        if role.id == g.id:
            perms = perms or role.permissions
            break
    
    for role in g.roles:
        for rid in m.roles:
            if role.id == rid:
                perms = perms or role.permissions
                break
    
    if (perms and permAdministrator) == permAdministrator:
        perms = perms or permAll

    for overwrite in c.permission_overwrites:
        if g.id == overwrite.id:
            perms = perms and (perms xor overwrite.deny)
            perms = perms or overwrite.allow
            break

    var denies = 0
    var allows = 0

    for overwrite in c.permission_overwrites:
        for roleid in m.roles:
            if overwrite.type == "role" and roleid == overwrite.id:
                denies = denies or overwrite.deny
                allows = allows or overwrite.allow
                break

    perms = perms and (perms xor denies)
    perms = perms or allows

    for overwrite in c.permission_overwrites:
        if overwrite.type == "member" and overwrite.id == m.user.id:
            perms = perms and (perms xor overwrite.deny)
            perms = perms or overwrite.allow
            break

    if (perms and permAdministrator) == permAdministrator:
        perms = perms or permAllChannel
    
    result = perms

method userChannelPermissions(s: OrcDiscord, user, chan: string): int {.base.} =
    let channel = waitFor s.session.channel(chan)
    let guild = waitFor s.session.guild(channel.guild_id)
    if guild.id == "": return
    if user == guild.owner_id: 
        return permAll
    
    let member = waitFor s.session.guildMember(guild.id, user)

    result = orcMemberPermissions(guild, channel, member)

method userGiveRole*(s: OrcDiscord, guild, user, role: string) {.base, gcsafe, async.} =
    asyncCheck s.session.guildMemberAddRole(guild, user, role)

method userTakeRole*(s: OrcDiscord, guild, user, role: string) {.base, gcsafe, async, inline.} =
    asyncCheck s.session.guildMemberRemoveRole(guild, user, role)

method sortRoles(s: OrcDiscord, r: seq[Role]): seq[Role] {.base, gcsafe.} =
    result = r
    result.sort do (x, y: Role) -> int:
        cmp(x.color, y.color)
    result.reverse

method userColor*(s: OrcDiscord, channel, user: string): Future[int] {.base, gcsafe, async.} =
    let chan = await s.session.channel(channel)

    let guild = await s.session.guild(chan.guild_id)

    let mem = await s.session.guildMember(guild.id, user)
    let roles = s.sortRoles(guild.roles)
    result = 0
    for role in roles:
        for ur in mem.roles:
            if role.id == ur:
                if role.color != 0: 
                    return role.color
                    

method messageServer*(s: OrcDiscord, m: OrcMessage): string {.base, gcsafe.} =
    let dm = cast[OrcDiscordMessage](m)
    result = s.session.messageGuild(dm.msg)

# Discord service methods
method name*(s: OrcDiscord): string {.inline, gcsafe.} = "Discord"
method isMe*(s: OrcDiscord, m: OrcMessage): bool {.inline.} = m.user().id() == s.session.cache.me.id
method isModerator*(s: OrcDiscord, m: OrcMessage): bool {.inline.} = 
    let perms = s.userChannelPermissions(m.user().id(), m.channel())
    result = ((perms and permAll) == permAll) or 
        ((perms and permAllChannel) == permAllChannel) or
        ((perms and permManageGuild) == permManageGuild)

method sendMessage*(s: OrcDiscord, channel: string, message: string) {.inline.} = asyncCheck s.session.channelMessageSend(channel, message)
method prefix*(s: OrcDiscord): string {.inline.} = ".!"

proc newDiscordService*(token: string): OrcDiscord {.inline.} =
    var ses = newSession(token)
    result = OrcDiscord(
        session: ses,
    )