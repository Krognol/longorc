import ./src/longorc, 
        # Loads of plugins!
        # Wow!
        src/plugins/[
            userinfo/userinfoplugin,
            msgmanage/msgmanage,
            cowsay/cowsay,
            rand/randplugin,
            ud/udplugin,
            weeb/anilist,
            eval/evalplugin,
            gfycat/gfy,
            wiktionary/wik
        ],
        asyncdispatch, tables, discord
 
let bot = newBot()
let orc = newDiscordService("Bot <token>")
bot.registerService(orc)
bot.registerPlugin(orc, UserInfoPlugin())
bot.registerPlugin(orc, Msgmanager())
bot.registerPlugin(orc, CowSayPlugin())
bot.registerPlugin(orc, RNGPlugin())
bot.registerPlugin(orc, UDPlugin()) 
bot.registerPlugin(orc, newAnilistPlugin("anilist client id", "anilist client secret"))
bot.registerPlugin(orc, EvalPlugin())
bot.registerPlugin(orc, newGfycatPlugin("gfycat client id", "gfycat client secret"))
bot.registerPlugin(orc, newWiktionaryPlugin("wordnik api key"))

proc orcReady(s: Session, m: Ready) =
    s.updateStreamingStatus(0, ".!help", "")
    orc.session.cache.cacheChannels = true

proc orcMessageCreate(s: Session, m: MessageCreate) =
    for _, plugin in bot.services[orc.name()].plugins:
        asyncCheck plugin.message(bot, orc, OrcDiscordMessage(discord: orc, msg: m, msgType: mtMessageCreate))

proc orcMessageUpdate(s: Session, m: MessageUpdate) =
    for _, plugin in bot.services[orc.name()].plugins:
        asyncCheck plugin.message(bot, orc, OrcDiscordMessage(discord: orc, msg: m, msgType: mtMessageUpdate))

proc orcMessageDelete(s: Session, m: MessageDelete) =
    for _, plugin in bot.services[orc.name()].plugins:
        asyncCheck plugin.message(bot, orc, OrcDiscordMessage(discord: orc, msg: m, msgType: mtMessageDelete))

orc.session.addHandler(EventType.message_create, orcMessageCreate)
orc.session.addHandler(EventType.message_update, orcMessageUpdate)
orc.session.addHandler(EventType.message_delete, orcMessageDelete)
orc.session.addHandler(EventType.on_ready, orcReady)
waitFor orc.session.SessionStart() 