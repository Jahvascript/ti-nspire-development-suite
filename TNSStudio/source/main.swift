import Cocoa
import Foundation

func check(_ condition:Bool,_ message:String)throws {if !condition{throw StudioError("Test failed: "+message)}}
func selfTest()throws {
 let fm=FileManager.default,tmp=fm.temporaryDirectory.appendingPathComponent("tnsstudio-tests-"+UUID().uuidString);try fm.createDirectory(at:tmp,withIntermediateDirectories:true);defer{try? fm.removeItem(at:tmp)}
 try check(luaQuote("\"\\\nπ")=="\"\\\"\\\\\\010\\207\\128\"","Lua strings safely encode quotes, backslashes, newlines and Unicode")
 let long=String(repeating:"A long paragraph with pi π and x^2.\n",count:700);try check(splitText(long).joined()==long,"splitting preserves every character")
 try check(cleanMath("x² − π × 2") == "x^2 - pi * 2","explicit math cleanup")
 var project=Project();project.title="Test & <guide>";project.pages=[NotePage(title:"Quote \" < >",text:"x = (11-3)/2\nπ ≤ 4\n]]; error('not code')"),NotePage(title:"Second page",text:long.prefix(4000).description)]
 let encoded=try JSONEncoder().encode(project),decoded=try JSONDecoder().decode(Project.self,from:encoded);try check(decoded.pages[0].text==project.pages[0].text,"project round trip")
 let out=tmp.appendingPathComponent("test.tns");try exportTNS(project,to:out);let good=try Data(contentsOf:out)
 try check(good.count>40,"notes compile")
 project.pages=[NotePage(title:"Broken Lua",kind:.lua,text:"function on.paint( !!")]
 var rejected=false;do{try exportTNS(project,to:out)}catch{rejected=true}
 try check(rejected,"invalid Lua rejected");try check(try Data(contentsOf:out)==good,"failed export preserves existing output")
 project.pages=[NotePage(title:"main",kind:.python,text:"print('TI-Nspire')\n")];try exportTNS(project,to:tmp.appendingPathComponent("python.tns"))
 project.pages.append(NotePage(title:"mixed",text:"no"));rejected=false;do{try validate(project)}catch{rejected=true};try check(rejected,"mixed Python document rejected")
 let file=tmp.appendingPathComponent("notes.txt");try long.write(to:file,atomically:true,encoding:.utf8);let imported=try importPages(file);try check(imported.map{$0.text}.joined()==long,"text import preserves content")
 print("PASS: escaping, Unicode, lossless split, cleanup, project round-trip, multipage Luna build, Lua rejection, destination preservation, Python packaging, document modes, text import")
}
#if STUDIO_HEADLESS_TEST
@_silgen_name("studio_test_no_screen") func stubScreen()
stubScreen()
#endif
let args=CommandLine.arguments
if args.contains("--self-test") {
 do{try selfTest()}catch{fputs(error.localizedDescription+"\n",stderr);exit(1)}
}else if let flag=args.firstIndex(of:"--source"),args.count>flag+2 {
 do{let p=try JSONDecoder().decode(Project.self,from:Data(contentsOf:URL(fileURLWithPath:args[flag+1])));try exportSource(p,to:URL(fileURLWithPath:args[flag+2]));print("Exported editable Lua/Python sources.")}catch{fputs(error.localizedDescription+"\n",stderr);exit(1)}
}else if let flag=args.firstIndex(of:"--convert"),args.count>flag+2 {
 do{
  let input=URL(fileURLWithPath:args[flag+1]),output=URL(fileURLWithPath:args[flag+2]);var project=Project();project.title=String(input.deletingPathExtension().lastPathComponent.prefix(120));project.pages=try importPages(input,forceOCR:args.contains("--ocr")){print($0)}
  try exportTNS(project,to:output);try JSONEncoder().encode(project).write(to:output.deletingPathExtension().appendingPathExtension("tnsproject"),options:.atomic)
  print("Built \(project.pages.count) pages: \(output.path)")
 }catch{fputs(error.localizedDescription+"\n",stderr);exit(1)}
}else {
 let application=NSApplication.shared;application.setActivationPolicy(.regular);let delegate=StudioApp();application.delegate=delegate
 withExtendedLifetime(delegate){application.run()}
}
