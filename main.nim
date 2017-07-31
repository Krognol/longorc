import src/longorc, asyncdispatch, tables, discord, src/orcdiscord,
        src/plugins/[
            userinfo/userinfoplugin,
            msgmanage/msgmanage,
            cowsay/cowsay,
            rand/randplugin,
            ud/udplugin,
            weeb/anilist,
            gfycat/gfy,
            wiktionary/wik,
            wolfram/wolfram,
            lastfm/lastfm,
            markov/markov,
            tags/tags,
            quotes/quotes,
            logger/logger,
            roles/roles
        ]
        # Loads of plugins!
        # Wow!
        
 
let bot = newBot()
let orc = newDiscordService("Bot <token>")
bot.registerService(orc)
let discordServiceEntry = bot.services["Discord"]
####### Plugins #######
bot.registerPlugin(orc, newUserInfoPlugin())
bot.registerPlugin(orc, Msgmanager())
bot.registerPlugin(orc, CowSayPlugin())
bot.registerPlugin(orc, RNGPlugin())
bot.registerPlugin(orc, UDPlugin())
bot.registerPlugin(orc, newAnilistPlugin("anilist client id", "anilist client secret"))
bot.registerPlugin(orc, newGfycatPlugin("gfycat client id", "gfycat client secret"))
bot.registerPlugin(orc, newWiktionaryPlugin("wordnik api key"))
bot.registerPlugin(orc, newWolframPlugin("app id"))
bot.registerPlugin(orc, newLastFMPlugin("last.fm api key"))
let markovp = newMarkovPlugin()
markovp.newGenerator("abc", "abc.txt")
bot.registerPlugin(orc, markovp)
bot.registerPlugin(orc, newTagPlugin())
bot.registerPlugin(orc, newQuotesPlugin())
bot.registerPlugin(orc, newLoggerPlugin(orc))
bot.registerPlugin(orc, newRolesPlugin())
#######################

proc orcOnReady(s: Session, r: Ready) =
    asyncCheck s.updateStreamingStatus(game = ".!help", url = "")
    orc.session.cache.cacheChannels = true
    orc.session.cache.cacheGuilds = true
    orc.session.cache.cacheGuildMembers = true

proc orcMessageCreate(s: Session, m: MessageCreate) =
    if m.author.id == "" or m.author.id.isNil(): return
    for _, plugin in discordServiceEntry.plugins:
        asyncCheck plugin.message(bot, orc, OrcDiscordMessage(discord: orc, msg: m, msgtype: mtMessageCreate))

proc orcMessageUpdate(s: Session, m: MessageUpdate) =
    if m.author.id == "" or m.author.id.isNil(): return
    for _, plugin in discordServiceEntry.plugins:
        asyncCheck plugin.message(bot, orc, OrcDiscordMessage(discord: orc, msg: m, msgtype: mtMessageUpdate))

proc orcMessageDelete(s: Session, m: MessageDelete) =
    if m.author.id == "" or m.author.id.isNil(): return
    for _, plugin in discordServiceEntry.plugins:
        asyncCheck plugin.message(bot, orc, OrcDiscordMessage(discord: orc, msg: m, msgtype: mtMessageDelete))

proc disc() {.noconv.} =
    echo "disconnecting"
    asyncCheck orc.session.disconnect()
    quit 0

orc.session.addHandler(EventType.message_create, orcMessageCreate)
orc.session.addHandler(EventType.message_update, orcMessageUpdate)
orc.session.addHandler(EventType.message_delete, orcMessageDelete)
orc.session.addHandler(EventType.on_ready, orcOnReady)
setControlCHook(disc)
# TODO :: Add a nicer way too start up all service listeners
waitFor orc.session.startSession()