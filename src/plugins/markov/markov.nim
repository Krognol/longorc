import ../../longorc, tables, strutils, random, asyncdispatch, unicode

type
    Generator = ref object
        markov: Table[string, seq[string]]
        beginnings: seq[string]
        prevToken: string
    MarkovPlugin* = ref object of Plugin
        generators: Table[string, Generator]

proc newMarkovPlugin*(): MarkovPlugin = MarkovPlugin(generators: initTable[string, Generator]())

method newGenerator*(p: MarkovPlugin, name, source: string) {.base.} = 
    var body: TaintedString
    try:
        body = readFile(source)
    except:
        echo "Failed to read source"
        return

    let gen = Generator(markov: initTable[string, seq[string]](), beginnings: @[], prevToken: "")
        
    let lines = body.split({char(10), char(13)})
    for line in lines:
        let tokens = line.split(" ")
        var first = true
        for tok in tokens:
            if tok.len == 0: continue
            if gen.markov.hasKey(gen.prevToken):
                gen.markov[gen.prevToken].add(tok)
            else: 
                gen.markov[gen.prevToken] = @[tok]
            gen.prevToken = tok
            
            if first:
                gen.beginnings.add(tok)
                first = false
    p.generators[name] = gen

method randomPrefix(p: Generator): string {.gcsafe, base.} =
    randomize()
    let i = random(high(p.beginnings))
    result = p.beginnings[i]

method generateText(p: Generator, charlimit: int): string {.gcsafe, base.} =
    var prefix = p.randomPrefix()
    result = ""
    while result.len < charlimit:
        let choices = p.markov[prefix]
        randomize()
        let choice = choices[random(choices.len)]
        result &= choice & " "
        prefix = choice
            
method save*(p: MarkovPlugin) = return
method load*(p: MarkovPlugin) = return
method name*(p: MarkovPlugin): string = "markov"

method help*(p: MarkovPlugin, b: Bot, s: Service, m: OrcMessage): seq[string] =
    result = @[
        commandHelp("markov", " [chain name] ", "Random sentence")
    ]

method message*(p: MarkovPlugin, b: Bot, s: Service, m: OrcMessage) {.async.} =
    if m.msgType() != mtMessageCreate or s.isMe(m) or m.user().bot:
        return

    if matchesCommand(m, s, "markov"):
        let (name, _) = parseCommand(s, m)
        if name == "": return
        if p.generators.hasKey(name):
            let gen = p.generators[name]
            let text = gen.generateText(50)
            s.sendMessage(m.channel, text)