import ../../longorc, asyncdispatch, strutils, osproc, os, oids, times, marshal, discord, tables

type EvalPlugin* = ref object of Plugin

method save*(p: EvalPlugin) = return
method load*(p: EvalPlugin) = return
method name*(p: EvalPlugin): string = "eval"

method help*(p: EvalPlugin, b: Bot, s: Service, m: OrcMessage): seq[string] =
    result = @[
        commandHelp("eval", " [code] ", "Evaluates any valid Nim code")
    ]

type Result = object of RootObj
  status: string
  result: string
  compileTime: float
  executionTime: float

proc execute(body: string): Result =
    var status = "success"
    var output = ""
    var compileTime, executionTime: float = 0
    let start = times.epochTime()

    let dir = os.joinPath(os.getTempDir(), "nim_playground")
    if not existsDir(dir): createDir(dir)

    let filePath = os.joinPath(dir, "nim_" & $genOid())
    system.writeFile(filePath & ".nim", body)
    
    var (rawOutput, errCode) = osproc.execCmdEx("nim c --threads:on " & filePath & ".nim")
    compileTime = times.epochTime() - start
    output = $rawOutput
    if errCode > 0: status = "compileError"
    else:
        (rawOutput, errCode) = osproc.execCmdEx(filePath)
        output = $rawOutput & "\n\n" & "#".repeat(60) & "\n###" & " Compiler output " & "#".repeat(40) & "\n" & "#".repeat(60) & "\n\n" & output
        executionTime = times.epochTime() - start - compileTime
        if errCode > 0: status = "executionError"

    var response = Result(status: status, result: output, compileTime: compileTime, executionTime: executionTime)

    return response

method message*(p: EvalPlugin, b: Bot, s: Service, m: OrcMessage) {.async.} =
    if s.isMe(m) or m.user().bot() or m.msgType() == mtMessageDelete:
        return

    if matchesCommand(m, s, "eval"):
        var (code, _) = parseCommand(s, m)
        if code == "": return
        let discord = cast[OrcDiscord](b.services["Discord"].service)
        if code.startsWith("```"):
            code = code[4..high(code)]
        if code.endsWith("```"):
            code = code[0..high(code)-3]

        echo code
        let res = execute(code)
        var embed = Embed(
            title: "Status " & res.status,
            description: "Result:\n" & res.result,
            fields: @[]
        )
        if res.status == "success":
            embed.color = Color
        else:
            embed.color = 0xf44242
        asyncCheck discord.session.channelMessageSendEmbed(m.channel(), embed)